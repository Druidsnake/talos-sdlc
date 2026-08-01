#!/bin/sh
# talos budget - presupuesto por feature. Ver talos-0.0.6.md seccion 33.
#
# El presupuesto solo puede dejar seguir o frenar. NUNCA elegir un modelo
# distinto: la regla 33.7 dice que no influye en el routing por capacidad, y
# la 33.8 que si no alcanza para el tier requerido se ESCALA en vez de
# degradar en silencio.
#
# Sale 0 dentro, 3 excedido, 4 el saldo no alcanza para el tier requerido.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
talos budget - presupuesto por feature

USO
    talos budget [FEATURE] [--format json]
    talos budget consume <FEATURE> <USD> <ITER> <MIN>

QUE HACE
    Compara lo consumido contra lo que declara el plan, y decide si se puede
    seguir. Nada mas.

    El presupuesto NO elige modelo. Si el saldo no alcanza para el tier que el
    plan pidio, la respuesta es escalar, no bajar el tier: el plan pidio ese
    tier por el riesgo de la feature, y bajarlo resuelve el numero rompiendo la
    razon.

    Todo consumo se registra como evento (regla 33.6).

SALIDA
    0  dentro del presupuesto
    2  error de uso
    3  excedido: pausar o escalar (regla 33.4)
    4  el saldo no alcanza para el tier requerido: escalar (regla 33.8)
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# shellcheck source=../../hooks/lib/gate.sh
. "$SYS/hooks/lib/gate.sh"
PY=$(talos_python) || { echo "talos: no hay python3" >&2; exit 2; }
LIB="$SYS/hooks/lib/budget.py"

if [ "${1:-}" = consume ]; then
    shift
    FEAT="${1:?falta la feature}"; USD="${2:?falta el costo}"
    ITER="${3:?faltan las iteraciones}"; MIN="${4:?faltan los minutos}"
    set +e
    out=$("$PY" "$LIB" consume "$PROJ" "$FEAT" "$USD" "$ITER" "$MIN")
    rc=$?
    set -e
    [ "$rc" -eq 2 ] && { printf '%s\n' "$out" >&2; exit 2; }

    # Regla 33.6: el consumo se registra como evento. Sin eso, el gasto no es
    # reconstruible desde el event log y la trazabilidad tiene un agujero.
    "$SYS/cli/talos" event append --type talos.budget.consumed \
        --actor core:Orchestrator --feature "$FEAT" >/dev/null 2>&1 || true

    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  consumo registrado en %s\n  %s\n' "$FEAT" "$out"
    echo ""
    exec "$PY" "$LIB" check "$PROJ" "$FEAT"
fi

exec "$PY" "$LIB" check "$PROJ" "$@"
