#!/bin/sh
# thalos agent - si el agente esta vivo. Ver thalos-mensajeria-0.0.1.md.
#
# La pregunta que Thalos no podia contestar. El estado que publica el runtime
# es la memoria de lo que alguien dijo y sobrevive a que ese alguien se muera:
# un agente al que le matan el proceso sigue figurando `working` para siempre,
# y el maestro lo espera hasta agotar el plazo. Media hora esperando a nadie.
#
# Aca se juntan dos cosas que el backend no junta: lo que el runtime REPORTA y
# lo que el sistema operativo MUESTRA. Cuando se contradicen, gana el proceso.
#
# Sale 0 no hay nada que hacer, 1 error de uso, 2 no observable,
#      3 plazo agotado, 4 escalacion requerida, 5 hay que redespachar.

set -eu

SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

LIB="$SYS/hooks/lib/liveness.py"

usage() {
    cat <<'USAGE'
thalos agent - vitalidad de un agente despachado

USO
    thalos agent observe <FEATURE>     los cuatro hechos, sin interpretar
    thalos agent verdict <FEATURE>     el veredicto y que hacer con el

    thalos agent verdict --observation '<json>'
                                       decide sobre una observacion dada,
                                       sin tocar el backend

OPCIONES de verdict
    --ack                 hubo ACK confirmado del encargo vigente
    --expired             se vencio el plazo de pared
    --blocked-samples N   muestras consecutivas en blocked

VEREDICTOS
    ALIVE_WORKING   vivo y sin razon para cortar
    DONE            termino su turno; recien ahi se mira el entregable
    WAITING_HUMAN   espera una decision: escala con evidencia
    DEAD            el estado dice que trabaja y su proceso no esta
    FAILED          bloqueado y sin proceso: la sesion fallo
    GONE            no existe el panel
    UNOBSERVABLE    el backend no sabe; se repara la observacion, no el agente

SALIDA
    El veredicto va como PRIMER token para que un `case` ramifique sin parsear.

CODIGOS DE SALIDA
    Llevan la CLASE DE ACCION, no el veredicto (seccion 40.4 del nucleo).
    0 nada que hacer   1 error de uso        2 no observable
    3 plazo agotado    4 escalacion          5 hay que redespachar
USAGE
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") usage >&2; exit 1 ;;
esac

PY=$(command -v python3 2>/dev/null) || { echo "thalos: no hay python3" >&2; exit 2; }
sub="$1"; shift

# La referencia del agente la dejo dispatch: no se repite en cada paso.
# shellcheck source=../../hooks/lib/resolve-capability.sh
. "$SYS/hooks/lib/resolve-capability.sh"
# shellcheck source=../../hooks/lib/agent-ref.sh
. "$SYS/hooks/lib/agent-ref.sh"

# Pide la foto al ExecutionAdapter. Devuelve el JSON crudo por salida estandar.
observar() {
    _feat="$1"
    _target=$(thalos_agent_ref_field "$_feat" name 2>/dev/null || echo "")
    if [ -z "$_target" ]; then
        echo "thalos: la feature $_feat no tiene un agente despachado" >&2
        echo "thalos: thalos feature dispatch $_feat --role Developer" >&2
        return 2
    fi
    thalos_capability_run ExecutionAdapter observe_agent \
        "{\"target\":\"$_target\"}" 2>/dev/null
}

case "$sub" in
    observe)
        FEAT="${1:-}"
        [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
        observar "$FEAT" || exit $?
        ;;

    verdict)
        OBS=""
        FEAT=""
        FLAGS=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --observation) OBS="${2:?falta el json de la observacion}"; shift 2 ;;
                --ack|--expired) FLAGS="$FLAGS $1"; shift ;;
                --blocked-samples|--blocked-confirm)
                    FLAGS="$FLAGS $1 ${2:?falta el numero}"; shift 2 ;;
                -*) echo "thalos: opcion desconocida: $1" >&2; exit 1 ;;
                *) FEAT="$1"; shift ;;
            esac
        done

        # --observation existe para decidir sin backend: es lo que permite
        # probar la tabla entera, y lo que deja al loop reutilizar una foto
        # que ya tomo en vez de pedir otra.
        if [ -z "$OBS" ]; then
            [ -n "$FEAT" ] || { echo "thalos: falta la feature o --observation" >&2; exit 1; }
            OBS=$(observar "$FEAT") || exit $?
            # El ACK lo sabe Thalos porque el mando el encargo; el backend no
            # puede saberlo. Es lo que separa un `done` de reposo de un `done`
            # de terminacion (decision M-004).
            if thalos_agent_ack_is "$FEAT"; then
                case "$FLAGS" in *--ack*) ;; *) FLAGS="$FLAGS --ack" ;; esac
            fi
        fi

        # El umbral de blocked sale de la config, no del codigo (principio 10).
        _conf="$SYS/config/communication.yaml"
        _umbral=3
        if [ -f "$_conf" ]; then
            _v=$(sed -n 's/^[[:space:]]*blocked_confirm_samples:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
                 "$_conf" | head -1)
            [ -n "$_v" ] && _umbral="$_v"
        fi

        # shellcheck disable=SC2086
        exec "$PY" "$LIB" verdict "$OBS" --blocked-confirm "$_umbral" $FLAGS
        ;;

    *)
        echo "thalos: subcomando desconocido: $sub" >&2
        echo "thalos: disponibles: observe, verdict" >&2
        exit 1 ;;
esac
