#!/bin/sh
# Referencia al agente despachado para una feature.
#
# Esto es NUCLEO. No nombra ninguna implementacion concreta: guarda el id del
# adapter que produjo la referencia leyendolo del registry (regla 37.4.3.5).
#
# POR QUE EXISTE
#
# Un ExecutionAdapter devuelve ids que solo el sabe interpretar: un pane de un
# runtime no significa nada en otro, y el id simulado de un adapter dry-run no
# existe en ningun backend real. Antes se guardaba el pane pelado en .pane, sin
# decir quien lo habia producido. Cambiar la ligadura de ExecutionAdapter
# dejaba ese archivo intacto, y el paso siguiente le mandaba a un adapter
# productivo un id fabricado por el simulador. El backend respondia "no existe"
# y el fallo aparecia a dos comandos de distancia de su causa.
#
# Una referencia sin procedencia no es verificable. Aca la procedencia se
# guarda con el id y se compara antes de usarlo.
#
# QUE SE GUARDA
#
#   adapter  id de la implementacion ligada cuando se despacho
#   name     nombre que Talos le puso al agente. Es lo que Talos CONTROLA, y
#            por eso es el target de las operaciones de agente. Un pane puede
#            tener un agente muerto o el shell de una persona; el nombre no.
#   pane     donde quedo abierto. Solo para operaciones de pane (run_command).
#   ref      id de recurso que devolvio start_agent, para diagnostico.
#
# Uso:  . hooks/lib/agent-ref.sh
#       talos_agent_ref_write F001 <id-del-adapter> talos_f001 <pane> <ref>
#       talos_agent_ref_check F001   || exit 2
#       talos_agent_ref_field F001 name

# talos_agent_ref_path <feature_id>
talos_agent_ref_path() {
    printf '%s/orchestration/features/%s/.agent' "${TALOS_PROJECT_ROOT:-.}" "$1"
}

# talos_agent_ref_write <feature_id> <adapter> <name> <pane> [ref]
talos_agent_ref_write() {
    _ar_f=$(talos_agent_ref_path "$1")
    mkdir -p "$(dirname "$_ar_f")"
    printf '{"adapter":"%s","name":"%s","pane":"%s","ref":"%s","dispatched_at":"%s"}\n' \
        "$2" "$3" "$4" "${5:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_ar_f"
    # El .pane suelto es la version sin procedencia de esto mismo. Se borra al
    # escribir la referencia buena: dos fuentes para el mismo dato garantizan
    # que alguna quede vieja.
    rm -f "${TALOS_PROJECT_ROOT:-.}/orchestration/features/$1/.pane"
}

# talos_agent_ref_field <feature_id> <campo>
talos_agent_ref_field() {
    _ar_f=$(talos_agent_ref_path "$1")
    [ -f "$_ar_f" ] || return 1
    _ar_v=$(sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_ar_f" | head -1)
    [ -n "$_ar_v" ] || return 1
    printf '%s' "$_ar_v"
}

# talos_agent_ref_clear <feature_id>
talos_agent_ref_clear() {
    rm -f "$(talos_agent_ref_path "$1")" \
          "${TALOS_PROJECT_ROOT:-.}/orchestration/features/$1/.pane"
}

# talos_agent_ref_check <feature_id>
#
# Sale 0 si hay referencia y la produjo el adapter que hoy esta ligado.
# Sale 1 si no hay referencia. Sale 2 si la produjo otro adapter.
#
# Requiere hooks/lib/resolve-capability.sh cargado.
talos_agent_ref_check() {
    _ar_own=$(talos_agent_ref_field "$1" adapter) || return 1
    _ar_now=$(talos_capability_impl ExecutionAdapter 2>/dev/null) || return 2
    [ "$_ar_own" = "$_ar_now" ] || return 2
    return 0
}

# talos_agent_ref_explain <feature_id> <codigo-de-check>
# El mensaje que corresponde al codigo, con el paso para salir del estado.
talos_agent_ref_explain() {
    case "$2" in
        1)
            printf '  FALL no hay agente despachado para %s\n' "$1"
            printf '\n  Despacha uno:\n    talos feature dispatch %s --role Developer\n' "$1"
            ;;
        2)
            printf '  FALL la referencia del agente de %s la produjo otro adapter\n' "$1"
            printf '    registrada  %s\n' "$(talos_agent_ref_field "$1" adapter 2>/dev/null || echo '-')"
            printf '    ligada hoy  %s\n' "$(talos_capability_impl ExecutionAdapter 2>/dev/null || echo '-')"
            printf '\n  Un id de un ExecutionAdapter no significa nada en otro.\n'
            printf '  Suelta el rol y despacha de nuevo:\n'
            printf '    talos feature release %s\n    talos feature dispatch %s --role Developer\n' "$1" "$1"
            ;;
    esac
}
