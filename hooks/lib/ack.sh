#!/bin/sh
# ACK observado de un encargo. Ver thalos-mensajeria-0.0.1.md seccion 7.
#
# EL TRAMO QUE FALTABA
#
# prompt_agent confirma que el backend acepto el envio. NO confirma que el
# encargo llego al agente. Entre "la terminal recibio las teclas" y "el agente
# empezo a procesar" se perdian encargos en silencio: el paso reportaba exito,
# nadie trabajaba, y el bucle de espera consumia el plazo entero esperando un
# entregable que nunca iba a existir porque nunca hubo encargo.
#
# EL ACK NO SE PIDE, SE OBSERVA
#
# Pedirle al agente que confirme rompe la regla 25.1.1.a: un rol no debe quedar
# obligado a conocer un formato para ser escuchado. Y no serviria igual, porque
# un agente confundido no contesta y quedaria indistinguible de uno muerto.
#
# Aca el ACK es una TRANSICION DE ESTADO posterior al envio. El contador de
# cambios de estado solo se mueve cuando el estado cambia -medido-, asi que ver
# ese contador moverse ES la prueba de que el encargo entro. No hace falta que
# el agente diga nada.
#
# NOT_DELIVERED ES UN ERROR, NO UN VEREDICTO
#
# Si no hay transicion, el encargo no llego. Eso no es un estado del agente:
# es una operacion que no se completo, clase TRANSIENT de la seccion 35.1. Por
# eso reintenta con backoff y NO consume iteracion de presupuesto: no hubo
# encargo que ejecutar. Reenviar es seguro justamente porque no llego.
#
# Requiere hooks/lib/resolve-capability.sh cargado.

# thalos_ack_baseline <target>
#
# Imprime "<estado> <seq> <observable>" antes de mandar nada. Es contra esto
# que se compara despues.
#
# El tercer campo es 0 cuando el ExecutionAdapter no devolvio NI estado NI
# contador, o sea cuando no implementa observe_agent de verdad. Sin el, un
# adapter mudo hacia que TODO despacho terminara en NOT_DELIVERED: la falta de
# senal se leia como falta de entrega, y se abortaban despachos que habian
# funcionado. Es la misma leccion que la regla 4.3.1 -no poder mirar no es
# estar muerto- aplicada al ACK.
thalos_ack_baseline() {
    _ab_o=$(thalos_capability_run ExecutionAdapter observe_agent \
            "{\"target\":\"$1\"}" 2>/dev/null || echo '')
    _ab_s=$(printf '%s' "$_ab_o" | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    _ab_q=$(printf '%s' "$_ab_o" | sed -n 's/.*"state_change_seq"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
    if [ -z "$_ab_s" ] && [ -z "$_ab_q" ]; then
        printf 'unknown 0 0'
    else
        printf '%s %s 1' "${_ab_s:-unknown}" "${_ab_q:-0}"
    fi
}

# thalos_ack_wait <target> <estado0> <seq0> <timeout_s>
# Sale 0 si vio la transicion, 1 si se vencio el plazo sin verla.
thalos_ack_wait() {
    _aw_t="$1"; _aw_e0="$2"; _aw_q0="$3"; _aw_lim=$(( $(date +%s) + $4 ))
    while [ "$(date +%s)" -lt "$_aw_lim" ]; do
        _aw_o=$(thalos_capability_run ExecutionAdapter observe_agent \
                "{\"target\":\"$_aw_t\"}" 2>/dev/null || echo '')
        _aw_e=$(printf '%s' "$_aw_o" | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        _aw_q=$(printf '%s' "$_aw_o" | sed -n 's/.*"state_change_seq"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
        # Cualquiera de las dos alcanza: el contador se mueve en la transicion
        # y el estado cambia de valor. Ver una sola ya prueba que entro.
        [ "${_aw_q:-0}" != "$_aw_q0" ] && return 0
        [ "${_aw_e:-unknown}" != "$_aw_e0" ] && return 0
        sleep 1
    done
    return 1
}

# thalos_ack_config <clave> <default>
# Los umbrales salen de config/, no del codigo (principio 10).
thalos_ack_config() {
    _ac_py=$(command -v python3 2>/dev/null) || { printf '%s' "$2"; return 0; }
    _ac_v=$("$_ac_py" "${THALOS_SYSTEM_ROOT:-.}/hooks/lib/config.py" \
            "${THALOS_SYSTEM_ROOT:-.}/config/$1" "$2" "$3" 2>/dev/null) || _ac_v="$3"
    printf '%s' "${_ac_v:-$3}"
}

# thalos_ack_send <target> <texto-escapado>
#
# Despacha un encargo y NO vuelve hasta saber si entro. Reintenta con backoff
# mientras el encargo no haya llegado, porque reenviar algo que nunca llego no
# duplica nada.
#
# Sale 0  el encargo entro: hubo ACK observado
#      1  NOT_DELIVERED tras agotar los intentos (clase TRANSIENT)
#      5  el adapter no pudo ni enviar
#
# Deja en THALOS_ACK_OUT la ultima respuesta del adapter, para que quien llama
# pueda mirar dry_run u otros campos sin volver a preguntar.
thalos_ack_send() {
    _as_t="$1"; _as_x="$2"
    _as_tmo=$(thalos_ack_config communication.yaml liveness.ack_timeout_seconds 45)
    _as_max=$(thalos_ack_config reliability.yaml \
              reliability.operations.agent_prompt.max_attempts 3)
    _as_base=$(thalos_ack_config reliability.yaml \
               reliability.operations.agent_prompt.backoff.base_ms 1000)
    _as_maxms=$(thalos_ack_config reliability.yaml \
                reliability.operations.agent_prompt.backoff.max_ms 15000)

    _as_n=1
    _as_espera=$(( _as_base / 1000 ))
    [ "$_as_espera" -lt 1 ] && _as_espera=1
    while :; do
        # shellcheck disable=SC2046  # se quiere el word-splitting: son 3 campos
        set -- $(thalos_ack_baseline "$_as_t")
        _as_e0="$1"; _as_q0="$2"; _as_obs="$3"

        set +e
        THALOS_ACK_OUT=$(thalos_capability_run ExecutionAdapter prompt_agent \
                         "{\"target\":\"$_as_t\",\"text\":\"$_as_x\"}" 2>&1)
        _as_rc=$?
        set -e
        [ "$_as_rc" -ne 0 ] && return 5

        # En simulacion nadie procesa el encargo, asi que no hay transicion que
        # esperar: exigir ACK convertiria toda corrida dry-run en NOT_DELIVERED.
        case "$THALOS_ACK_OUT" in
            *'"dry_run":true'*|*'"simulated":true'*) return 0 ;;
        esac

        # Adapter que no observa: no hay contra que comparar. Se acepta el
        # envio como antes de este subsistema. Degradar es correcto; inventar
        # un NOT_DELIVERED sobre un encargo que si llego, no.
        [ "$_as_obs" = 0 ] && return 0

        if thalos_ack_wait "$_as_t" "$_as_e0" "$_as_q0" "$_as_tmo"; then
            return 0
        fi

        _as_n=$(( _as_n + 1 ))
        [ "$_as_n" -gt "$_as_max" ] && return 1
        sleep "$_as_espera"
        _as_espera=$(( _as_espera * 2 ))
        [ "$_as_espera" -gt $(( _as_maxms / 1000 )) ] && _as_espera=$(( _as_maxms / 1000 ))
    done
}
