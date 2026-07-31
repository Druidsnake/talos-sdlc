#!/bin/sh
# talos gate - evalua si una transicion de estado esta autorizada.
#
# El gate es codigo, no criterio: funcion pura de evidencia, policy y config.
# No invoca modelos (regla 24.4.3).
#
# Sale 0 pass, 3 fail (gate rechazado), 4 needs_human (escalacion).

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
talos gate - evalua si una transicion de estado esta autorizada

USO
    talos gate <maquina> <desde> <hacia> [--format json]
    talos gate --list [maquina]
    talos gate --from <maquina> <estado>

ARGUMENTOS
    maquina   program | feature
    desde     estado de origen
    hacia     estado de destino

OPCIONES
    --list            vuelca la tabla de transiciones
    --from            que transiciones salen de un estado
    --evidence DIR    donde buscar la evidencia (default orchestration/evidence)
    --format json     solo el GateResult

COMO DECIDE
    1. La transicion tiene que existir en la tabla 22.4 o 22.5. Si no existe,
       se rechaza: el default es negar.
    2. Toda la evidencia que exige la transicion tiene que estar presente
       ANTES de evaluar. Si falta, el gate resuelve fail y la lista en
       missing_evidence.
    3. Una evidencia con verifiable:false no puede satisfacer un gate critico.
    4. Un gate humano nunca resuelve pass por su cuenta: resuelve needs_human.

    La tabla se deriva de la spec, no se escribe a mano. Ver
    tools/build-transitions.py.

SALIDA
    0  pass
    1  error de uso
    3  fail: el gate rechazo la transicion
    4  needs_human: requiere decision humana
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# shellcheck source=../../hooks/lib/gate.sh
. "$SYS/hooks/lib/gate.sh"

if ! talos_transition_table >/dev/null 2>&1; then
    echo "talos: falta la tabla de transiciones" >&2
    echo "talos: generala con  python3 tools/build-transitions.py" >&2
    exit 2
fi

# ---------- modos de consulta ----------

if [ "${1:-}" = "--list" ]; then
    m="${2:-}"
    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  %-8s %-4s %-24s %-24s %-18s %s\n' MAQUINA ID DESDE HACIA GATE EVENTO
    talos_transition_table | while IFS='	' read -r mm id from to gate cond actor req event; do
        [ -n "$m" ] && [ "$mm" != "$m" ] && continue
        printf '  %-8s %-4s %-24s %-24s %-18s %s\n' "$mm" "$id" "$from" "$to" "$gate" "$event"
    done
    exit 0
fi

if [ "${1:-}" = "--from" ]; then
    m="${2:?falta la maquina}"
    st="${3:?falta el estado}"
    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    if talos_is_terminal "$m" "$st"; then
        echo "  $st es un estado terminal: no tiene transiciones de salida (regla 22.6.9)."
        echo "  Reabrir exige crear una feature derivada, no reabrir esta."
        exit 0
    fi
    printf '  desde %s\n\n' "$st"
    printf '  %-4s %-24s %-18s %-14s %s\n' ID HACIA GATE ACTOR EVIDENCIA
    talos_transitions_from "$m" "$st" | while IFS='	' read -r mm id from to gate cond actor req event; do
        printf '  %-4s %-24s %-18s %-14s %s\n' "$id" "$to" "$gate" "$actor" "$req"
    done
    exit 0
fi

# ---------- evaluacion ----------

[ $# -lt 3 ] && { usage >&2; exit 1; }

machine="$1"; from="$2"; to="$3"
shift 3

case "$machine" in
    program|feature) ;;
    *) echo "talos: maquina desconocida: $machine (program | feature)" >&2; exit 1 ;;
esac

EVDIR="orchestration/evidence"
FORMAT=text
while [ $# -gt 0 ]; do
    case "$1" in
        --evidence) EVDIR="${2:?falta el directorio}"; shift 2 ;;
        --format)   [ "${2:-}" = json ] && FORMAT=json; shift 2 ;;
        *) echo "talos: opcion desconocida: $1" >&2; exit 1 ;;
    esac
done

set +e
result=$(talos_gate_eval "$machine" "$from" "$to" "$EVDIR")
code=$?
set -e

if [ "$FORMAT" = json ]; then
    printf '%s\n' "$result"
    exit "$code"
fi

tid=$(talos_transition_id "$machine" "$from" "$to" 2>/dev/null || echo "-")
gate=$(talos_transition_gate "$machine" "$from" "$to" 2>/dev/null || echo "-")
req=$(talos_transition_requires "$machine" "$from" "$to" 2>/dev/null || echo "-")
event=$(talos_transition_event "$machine" "$from" "$to" 2>/dev/null || echo "-")

echo "talos ${TALOS_VERSION:-?}"
echo ""
printf '  transicion   %s  %s -> %s\n' "$tid" "$from" "$to"
printf '  gate         %s\n' "$gate"
printf '  evidencia    %s\n' "$req"
printf '  evento       %s\n' "$event"
echo ""

printf '%s' "$result" \
    | sed -n 's/.*"reasons":\[\(.*\)\],"missing_evidence".*/\1/p' \
    | tr '}' '\n' \
    | while read -r line; do
        case "$line" in *code*) ;; *) continue ;; esac
        c=$(printf '%s' "$line" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
        s=$(printf '%s' "$line" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
        d=$(printf '%s' "$line" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
        case "$s" in
            pass) mark="ok  " ;;
            skip) mark="--  " ;;
            *)    mark="FALL" ;;
        esac
        printf '  %s %-28s %s\n' "$mark" "$c" "$d"
    done

echo ""
case "$code" in
    0) echo "  pass: la transicion esta autorizada" ;;
    4) echo "  needs_human: un gate humano no resuelve pass por su cuenta (regla 24.4.6)" ;;
    *) echo "  fail: la transicion NO esta autorizada" ;;
esac
exit "$code"
