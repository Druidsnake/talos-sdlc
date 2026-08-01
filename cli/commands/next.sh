#!/bin/sh
# talos next - que sigue, derivado de los artefactos aprobados.
#
# No hay un objetivo declarado aparte, y no deberia haberlo: la cadena de
# autoridad de la seccion 43.5 pone el spec aprobado por encima de todo lo que
# no sea policy o aprobacion humana. Una intencion declarada al margen
# competiria con el, que es el defecto que 0.0.5 corrigio de 0.0.4.
#
# Lo que sigue se DERIVA: spec -> plan -> estado -> tabla de transiciones.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
talos next - que sigue, derivado de los artefactos aprobados

USO
    talos next [--pane <PANE>] [--format json]

    Sin --pane no se proponen los pasos que necesitan un agente: el sistema
    no elige donde ejecutar por vos.

DE DONDE SALE
    spec aprobado          que construir
    program-plan.json      features, dependencias, riesgo
    estado de cada feature donde esta cada una
    tabla de transiciones  que puede pasar desde ahi

    Nada de esto se declara aparte. Un objetivo propio competiria con el spec
    aprobado, y la seccion 43.5 dice que una fuente de menor autoridad nunca
    puede anular a una de mayor.

SALIDA
    0  siempre que se pueda derivar el estado
    2  no se pudo leer lo necesario
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# shellcheck source=../../hooks/lib/gate.sh
. "$SYS/hooks/lib/gate.sh"

PY=$(talos_python) || { echo "talos: no hay python3" >&2; exit 2; }
TABLA="$SYS/hooks/generated/transitions.tsv"
[ -f "$TABLA" ] || { echo "talos: falta la tabla de transiciones" >&2; exit 2; }

FORMATO=texto
PANE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --format) [ "${2:-}" = json ] && FORMATO=json; shift 2 ;;
        --pane)   PANE="${2:?falta el pane}"; shift 2 ;;
        *) shift ;;
    esac
done

exec "$PY" "$SYS/hooks/lib/next.py" "$PROJ" "$TABLA" "$FORMATO" "$PANE"
