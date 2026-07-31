#!/bin/sh
# Maquina de estados: que transicion esta permitida y que exige.
#
# Regla 22.6.1: una transicion DEBE existir en la tabla para ser permitida.
# Regla 22.6.2: toda transicion no listada DEBE rechazarse.
#
# El default es rechazar. Una tabla ausente no habilita nada: si no se puede
# leer el contrato, no se puede autorizar una transicion contra el.
#
# Uso:  . hooks/lib/state-machine.sh
#       talos_transition_find feature FEATURE_READY FEATURE_IN_PROGRESS
#       talos_transition_requires feature FEATURE_READY FEATURE_IN_PROGRESS

_sm_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_sm_lib_dir" in
    */lib) TALOS_SM_SYS=$(dirname "$(dirname "$_sm_lib_dir")") ;;
    *)     TALOS_SM_SYS="${TALOS_SYSTEM_ROOT:-$_sm_lib_dir}" ;;
esac
[ -n "${TALOS_SYSTEM_ROOT:-}" ] && TALOS_SM_SYS="$TALOS_SYSTEM_ROOT"

TALOS_TRANSITIONS="${TALOS_TRANSITIONS_FILE:-$TALOS_SM_SYS/hooks/generated/transitions.tsv}"

# Estados terminales, secciones 22.1 y 22.2.
TALOS_TERMINAL_PROGRAM="PROGRAM_DONE HALTED"
TALOS_TERMINAL_FEATURE="FEATURE_DONE FEATURE_FAILED FEATURE_ABANDONED"

talos_transition_table() {
    [ -f "$TALOS_TRANSITIONS" ] || return 1
    grep -v '^#' "$TALOS_TRANSITIONS" | grep -v '^[[:space:]]*$'
}

# talos_is_terminal <maquina> <estado>
talos_is_terminal() {
    case "$1" in
        program) _list="$TALOS_TERMINAL_PROGRAM" ;;
        feature) _list="$TALOS_TERMINAL_FEATURE" ;;
        *)       return 1 ;;
    esac
    for _s in $_list; do
        [ "$_s" = "$2" ] && return 0
    done
    return 1
}

# talos_transition_find <maquina> <desde> <hacia>
# Imprime la fila completa. Sale 1 si la transicion no existe.
#
# El comodin "*" cubre F27 (cualquier estado no terminal -> FEATURE_ABANDONED).
# Un comodin NO habilita salir de un estado terminal: la regla 22.6.9 dice que
# los terminales no tienen transiciones de salida.
talos_transition_find() {
    _m="$1"; _from="$2"; _to="$3"

    talos_is_terminal "$_m" "$_from" && return 1

    _row=$(talos_transition_table 2>/dev/null \
        | awk -F'\t' -v m="$_m" -v f="$_from" -v t="$_to" \
            '$1 == m && $4 == t && ($3 == f || $3 == "*") { print; exit }')
    [ -n "$_row" ] || return 1
    printf '%s\n' "$_row"
}

# talos_transition_allowed <maquina> <desde> <hacia>  -> 0 permitida / 1 no
talos_transition_allowed() {
    talos_transition_find "$@" >/dev/null 2>&1
}

_sm_field() {
    talos_transition_find "$1" "$2" "$3" | cut -f"$4"
}

# talos_transition_id       <maquina> <desde> <hacia>  -> P1, F19, ...
talos_transition_id()       { _sm_field "$1" "$2" "$3" 2; }
# talos_transition_gate     -> nombre del gate, o "-"
talos_transition_gate()     { _sm_field "$1" "$2" "$3" 5; }
# talos_transition_condition-> condicion extra que el gate no cubre
talos_transition_condition(){ _sm_field "$1" "$2" "$3" 6; }
# talos_transition_actor    -> quien puede ejecutarla
talos_transition_actor()    { _sm_field "$1" "$2" "$3" 7; }
# talos_transition_requires -> tipos de evidencia exigidos, separados por coma
talos_transition_requires() { _sm_field "$1" "$2" "$3" 8; }
# talos_transition_event    -> el evento que debe emitir (regla 22.6.5)
talos_transition_event()    { _sm_field "$1" "$2" "$3" 9; }

# talos_transitions_from <maquina> <estado>
# Todas las transiciones disponibles desde un estado. Vacio si es terminal.
talos_transitions_from() {
    talos_is_terminal "$1" "$2" && return 0
    talos_transition_table 2>/dev/null \
        | awk -F'\t' -v m="$1" -v f="$2" '$1 == m && ($3 == f || $3 == "*")'
}
