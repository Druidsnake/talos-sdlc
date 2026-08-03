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
#   name     nombre que Thalos le puso al agente. Es lo que Thalos CONTROLA, y
#            por eso es el target de las operaciones de agente. Un pane puede
#            tener un agente muerto o el shell de una persona; el nombre no.
#   pane     donde quedo abierto. Solo para operaciones de pane (run_command).
#   ref      id de recurso que devolvio start_agent, para diagnostico.
#
# Uso:  . hooks/lib/agent-ref.sh
#       thalos_agent_ref_write F001 <id-del-adapter> thalos_f001 <pane> <ref>
#       thalos_agent_ref_check F001   || exit 2
#       thalos_agent_ref_field F001 name

# thalos_agent_ref_path <feature_id>
thalos_agent_ref_path() {
    printf '%s/orchestration/features/%s/.agent' "${THALOS_PROJECT_ROOT:-.}" "$1"
}

# GENERACION: que instancia de despacho es esta.
#
# La idempotency key es sha256(run:feature:op:args) por la regla 38.2.4, y el
# encargo que arma `feature work` es determinista para una feature+task dada.
# Sin nada que distinga una instancia de otra, un REDESPACHO producia la misma
# key, el ledger contestaba already_exists y el prompt no se enviaba nunca: el
# agente nuevo no recibia su encargo, jamas.
#
# El nombre del agente no alcanza para distinguirlas porque Thalos lo reutiliza
# a proposito -es lo que le permite reconciliar-. Hace falta un contador.
#
# NO es un timestamp ni un valor no determinista, asi que no viola la regla
# 38.2.5: es constante entre reintentos del MISMO despacho -la deduplicacion
# sigue protegiendo contra el doble envio- y solo cambia cuando hay uno nuevo.
# Es el mismo patron que la seccion 32.3 usa para los leases.
#
# Vive aparte de .agent y SOBREVIVE a release: si se borrara con el resto, el
# proximo despacho volveria a empezar en 1 y chocaria con las keys viejas.
thalos_agent_gen_path() {
    printf '%s-gen' "$(thalos_agent_ref_path "$1")"
}

# thalos_agent_ref_write <feature_id> <adapter> <name> <pane> [ref]
thalos_agent_ref_write() {
    _ar_f=$(thalos_agent_ref_path "$1")
    mkdir -p "$(dirname "$_ar_f")"
    _ar_g=$(cat "$(thalos_agent_gen_path "$1")" 2>/dev/null || echo 0)
    case "$_ar_g" in ''|*[!0-9]*) _ar_g=0 ;; esac
    _ar_g=$(( _ar_g + 1 ))
    printf '%s\n' "$_ar_g" > "$(thalos_agent_gen_path "$1")"
    # La generacion se guarda como CADENA para que el lector de campos, que
    # busca "clave":"valor", la encuentre igual que a las demas.
    printf '{"adapter":"%s","name":"%s","pane":"%s","ref":"%s","generation":"%s","dispatched_at":"%s"}\n' \
        "$2" "$3" "$4" "${5:-}" "$_ar_g" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_ar_f"
    # El .pane suelto es la version sin procedencia de esto mismo. Se borra al
    # escribir la referencia buena: dos fuentes para el mismo dato garantizan
    # que alguna quede vieja.
    rm -f "${THALOS_PROJECT_ROOT:-.}/orchestration/features/$1/.pane"
}

# thalos_agent_ref_field <feature_id> <campo>
thalos_agent_ref_field() {
    _ar_f=$(thalos_agent_ref_path "$1")
    [ -f "$_ar_f" ] || return 1
    _ar_v=$(sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_ar_f" | head -1)
    [ -n "$_ar_v" ] || return 1
    printf '%s' "$_ar_v"
}

# thalos_agent_ref_clear <feature_id>
thalos_agent_ref_clear() {
    rm -f "$(thalos_agent_ref_path "$1")" \
          "$(thalos_agent_ref_path "$1")-ack" \
          "${THALOS_PROJECT_ROOT:-.}/orchestration/features/$1/.pane"
}

# ---------- ACK del encargo vigente ----------
#
# Ver thalos-mensajeria-0.0.1.md regla 7.2.2. El ACK se persiste porque
# alimenta `ack_confirmed` de la tabla de veredictos, y esa tabla se consulta
# despues del despacho, desde otro proceso.
#
# Sin esto, el mismo `done` crudo es indistinguible entre dos situaciones
# opuestas: un agente en REPOSO que nunca recibio nada, y uno que TERMINO el
# encargo. La diferencia no esta en el backend -que no sabe que se le pidio-
# sino en si Thalos vio entrar su encargo.

# thalos_agent_ack_set <feature_id>
thalos_agent_ack_set() {
    _aa_f="$(thalos_agent_ref_path "$1")-ack"
    mkdir -p "$(dirname "$_aa_f")"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$_aa_f"
}

# thalos_agent_ack_is <feature_id>
# Sale 0 si el encargo vigente tuvo ACK observado.
thalos_agent_ack_is() {
    [ -f "$(thalos_agent_ref_path "$1")-ack" ]
}

# thalos_agent_ack_clear <feature_id>
thalos_agent_ack_clear() {
    rm -f "$(thalos_agent_ref_path "$1")-ack"
}

# thalos_agent_ref_check <feature_id>
#
# Sale 0 si hay referencia y la produjo el adapter que hoy esta ligado.
# Sale 1 si no hay referencia. Sale 2 si la produjo otro adapter.
#
# Requiere hooks/lib/resolve-capability.sh cargado.
thalos_agent_ref_check() {
    _ar_own=$(thalos_agent_ref_field "$1" adapter) || return 1
    _ar_now=$(thalos_capability_impl ExecutionAdapter 2>/dev/null) || return 2
    [ "$_ar_own" = "$_ar_now" ] || return 2
    return 0
}

# thalos_agent_ref_explain <feature_id> <codigo-de-check>
# El mensaje que corresponde al codigo, con el paso para salir del estado.
thalos_agent_ref_explain() {
    case "$2" in
        1)
            printf '  FALL no hay agente despachado para %s\n' "$1"
            printf '\n  Despacha uno:\n    thalos feature dispatch %s --role Developer\n' "$1"
            ;;
        2)
            printf '  FALL la referencia del agente de %s la produjo otro adapter\n' "$1"
            printf '    registrada  %s\n' "$(thalos_agent_ref_field "$1" adapter 2>/dev/null || echo '-')"
            printf '    ligada hoy  %s\n' "$(thalos_capability_impl ExecutionAdapter 2>/dev/null || echo '-')"
            printf '\n  Un id de un ExecutionAdapter no significa nada en otro.\n'
            printf '  Suelta el rol y despacha de nuevo:\n'
            printf '    thalos feature release %s\n    thalos feature dispatch %s --role Developer\n' "$1" "$1"
            ;;
    esac
}
