#!/bin/sh
# thalos adapters - que capacidad esta ligada a que implementacion, y si responde.
#
# El nucleo no nombra implementaciones concretas: las lee del registry
# (regla 37.4.3.5). Este comando muestra lo que el registry declara.
#
# Sale 0 si toda capacidad REQUERIDA esta ligada y sana, 2 si no.

set -eu

SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
thalos adapters - capacidades, implementaciones ligadas y su health check

USO
    thalos adapters [--format json]

QUE MUESTRA
    cada extension point del sistema
    si la capacidad es REQUERIDA u OPCIONAL
    que implementacion la satisface, segun config/extensions.yaml
    si esa implementacion responde al health check

CAPACIDAD vs IMPLEMENTACION
    Una capacidad puede ser requerida y su implementacion seguir siendo
    reemplazable: son dos ejes distintos. Cambiar de implementacion se hace
    en config/extensions.yaml, sin tocar el nucleo.

    Cero implementaciones de una capacidad REQUERIDA falla.
    Cero implementaciones de una capacidad OPCIONAL es un estado valido.

    Ver thalos-0.0.7.md seccion 37.4.

SALIDA
    0  toda capacidad requerida ligada y sana
    2  falta una capacidad requerida o su adapter no responde
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

FORMAT=text
[ "${1:-}" = "--format" ] && [ "${2:-}" = "json" ] && FORMAT=json

# shellcheck source=../../hooks/lib/resolve-capability.sh
. "$SYS/hooks/lib/resolve-capability.sh"

if ! thalos_capability_table >/dev/null 2>&1; then
    echo "thalos: falta la tabla de capacidades" >&2
    echo "thalos: generala con  python3 tools/build-registry.py" >&2
    exit 2
fi

mode=$(grep -E '^execution_mode:' "$SYS/config/system.yaml" 2>/dev/null \
       | head -1 | sed 's/execution_mode:[[:space:]]*//' | tr -d '"' || echo "?")

rows=$(thalos_capability_audit || true)
fails=$(thalos_capability_failures "$rows")

if [ "$FORMAT" = json ]; then
    printf '{\n  "execution_mode": "%s",\n  "capabilities": [\n' "$mode"
    first=1
    printf '%s\n' "$rows" | while IFS='|' read -r cap kind state detail; do
        [ -z "$cap" ] && continue
        [ "$first" -eq 0 ] && printf ',\n'
        first=0
        printf '    {"capability": "%s", "required": %s, "state": "%s", "detail": "%s"}' \
            "$cap" "$([ "$kind" = required ] && echo true || echo false)" "$state" "$detail"
    done
    printf '\n  ],\n  "failed": %s\n}\n' "$fails"
    [ "$fails" -gt 0 ] && exit 2
    exit 0
fi

echo "thalos ${THALOS_VERSION:-?}"
echo ""
printf '  modo de ejecucion: %s\n' "$mode"
echo ""
printf '  %-22s %-9s %-12s %s\n' CAPACIDAD TIPO ESTADO IMPLEMENTACION
printf '%s\n' "$rows" | while IFS='|' read -r cap kind state detail; do
    [ -z "$cap" ] && continue
    case "$state" in
        ok)          mark="ok  " ;;
        sin_ligar)   [ "$kind" = required ] && mark="FALL" || mark="--  " ;;
        *)           mark="FALL" ;;
    esac
    printf '  %s %-21s %-9s %-12s %s\n' "$mark" "$cap" "$kind" "$state" "$detail"
done

echo ""
if [ "$fails" -gt 0 ]; then
    echo "  $fails capacidad(es) REQUERIDA(s) sin satisfacer"
    echo "  Ver thalos-0.0.7.md 37.4.3: cero implementaciones falla en PRECONDITION_GATE."
    exit 2
fi
echo "  capacidades requeridas: OK"
echo "  las opcionales sin ligar son un estado valido (regla 37.4.3.4)"
exit 0
