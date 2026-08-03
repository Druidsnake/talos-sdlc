#!/bin/sh
# Eventos de vitalidad. Ver thalos-mensajeria-0.0.1.md seccion 10.
#
# POR QUE EXISTE
#
# El principio 3.9 pide que toda observacion pueda reconstruirse desde eventos,
# y no se podia: el subsistema entero decidia veredictos y no dejaba ni uno
# escrito. Se sabia CUAL era el estado de un agente; no se sabia COMO llego
# ahi. Para entender un despacho raro al dia siguiente -estuvo bloqueado tres
# veces antes de morir? el encargo entro a la primera?- no habia nada que leer.
#
# QUE SE EMITE Y QUE NO
#
# Solo los CAMBIOS. Un sondeo cada 5 segundos durante 15 minutos son 180
# observaciones y una sola cosa que contar: que el veredicto cambio, cuando.
# Emitir cada muestra llenaria el log de ruido que hay que filtrar para
# encontrar el dato (regla 10.1).
#
# Requiere THALOS_SYSTEM_ROOT.

# thalos_evento_agente <tipo> <feature> <payload-json>
#
# Un fallo del EventLog NO DEBE tumbar el despacho: registrar es importante y
# no es la tarea. Pero tampoco se traga en silencio -eso ya paso con un flag
# inventado que nadie noto durante toda una etapa-: se avisa por stderr.
thalos_evento_agente() {
    _ea_out=$("${THALOS_SYSTEM_ROOT:?}/cli/thalos" event append \
        --type "$1" --actor thalos:core --feature "$2" --payload "$3" 2>&1) || {
        printf 'thalos: no se pudo registrar %s: %s\n' "$1" \
            "$(printf '%s' "$_ea_out" | head -1)" >&2
        return 0
    }
    return 0
}

# thalos_evento_veredicto <feature> <veredicto> <estado-crudo>
#
# Traduce un veredicto al evento que le corresponde. Los terminales tienen
# tipo propio para poder filtrarlos sin parsear payload, que es como el resto
# del catalogo trata los desenlaces (feature.blocked, feature.failed...).
thalos_evento_veredicto() {
    _ev_f="$1"; _ev_v="$2"; _ev_st="${3:-unknown}"
    case "$_ev_v" in
        DONE)          _ev_t=thalos.agent.turn_done ;;
        DEAD|FAILED)   _ev_t=thalos.agent.dead ;;
        GONE)          _ev_t=thalos.agent.gone ;;
        WAITING_HUMAN) _ev_t=thalos.agent.waiting_human ;;
        *)             _ev_t=thalos.agent.observed ;;
    esac
    thalos_evento_agente "$_ev_t" "$_ev_f" \
        "{\"verdict\":\"$_ev_v\",\"state\":\"$_ev_st\"}"
}
