#!/bin/sh
# talos message - la comunicacion entre roles. Ver talos-0.0.6.md seccion 25.
#
# La seccion 25 estaba especificada entera y no la implementaba nadie. Se veia
# corriendo: un agente contestaba "no puedo por X", Talos esperaba un archivo
# que no llegaba y reportaba "termino sin dejar entregable". El motivo existia
# y se perdia.
#
# LA ESTRUCTURA LA PONE TALOS, EL CONTENIDO PUEDE SER RUIDO. Exigirle al agente
# que conteste en un formato es lo que rompe la comunicacion: si contesta
# distinto, se pierde. Aca lo estructurado es el sobre -quien, a quien, sobre
# que, en que hilo- y el cuerpo es lo que haya dicho, tal cual.
#
# Sale 0 ok, 1 error de uso, 2 no se encontro.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

DIR=orchestration/messages
LIB="$SYS/hooks/lib/message.py"

usage() {
    cat <<'USAGE'
talos message - comunicacion entre roles, humanos y el nucleo

USO
    talos message list [ESTADO]        los mensajes, opcionalmente por estado
    talos message show <ID>            un mensaje entero
    talos message answer <ID> --text "..."
                                       responde y ENTREGA la respuesta al agente
    talos message close <ID> [ESTADO]  lo cierra (por defecto CLOSED)

ESTADOS
    OPEN  ACKED  ANSWERED  CLOSED  EXPIRED  ESCALATED

QUE HACE answer
    1. persiste tu respuesta como mensaje ANSWER, referenciando el original
    2. se la entrega al agente que pregunto, por el ExecutionAdapter
    3. marca la pregunta como ANSWERED

    Sin el paso 2 la respuesta queda escrita y nadie la lee: la comunicacion
    se corta en el ultimo tramo, que es el que importa.

SALIDA
    0  listo        1  error de uso        2  no se encontro
USAGE
}

case "${1:-list}" in -h|--help) usage; exit 0 ;; esac

PY=$(command -v python3 2>/dev/null) || { echo "talos: no hay python3" >&2; exit 2; }
sub="${1:-list}"
[ $# -gt 0 ] && shift

case "$sub" in
    list)
        echo "talos ${TALOS_VERSION:-?}"
        echo ""
        if [ -z "$(ls "$DIR"/msg-*.json 2>/dev/null)" ]; then
            echo "  no hay mensajes"
            exit 0
        fi
        printf '  %-22s %-10s %-16s %s\n' ID ESTADO TIPO DE-PARA
        "$PY" "$LIB" list "$DIR" "${1:-}" | while IFS='	' read -r id est tipo dep feat texto; do
            printf '  %-22s %-10s %-16s %s  [%s]\n' "$id" "$est" "$tipo" "$dep" "$feat"
            printf '  %-22s %s\n' "" "$texto"
        done
        echo ""
        echo "  talos message show <ID>      para leerlo entero"
        echo "  talos message answer <ID> --text \"...\"   para contestar"
        ;;
    show)
        [ -n "${1:-}" ] || { echo "talos: falta el id" >&2; exit 1; }
        exec "$PY" "$LIB" show "$DIR" "$1"
        ;;
    close)
        [ -n "${1:-}" ] || { echo "talos: falta el id" >&2; exit 1; }
        exec "$PY" "$LIB" close "$DIR" "$1" "${2:-CLOSED}"
        ;;
    answer)
        MID="${1:-}"; [ -n "$MID" ] || { echo "talos: falta el id" >&2; exit 1; }
        shift
        TEXTO=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --text) TEXTO="${2:?falta el texto}"; shift 2 ;;
                *) shift ;;
            esac
        done
        [ -n "$TEXTO" ] || { echo "talos: falta --text" >&2; exit 1; }

        # A quien se le contesta y sobre que: sale del mensaje original, no de
        # lo que recuerde quien responde.
        _orig=$("$PY" "$LIB" show "$DIR" "$MID") || exit 2
        _de=$(printf '%s' "$_orig" | sed -n 's/.*"from"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        _feat=$(printf '%s' "$_orig" | sed -n 's/.*"feature_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        _task=$(printf '%s' "$_orig" | sed -n 's/.*"task_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        _hilo=$(printf '%s' "$_orig" | sed -n 's/.*"thread_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

        echo "talos ${TALOS_VERSION:-?}"
        echo ""
        _nuevo=$("$PY" "$LIB" send "$DIR" ANSWER "human:operator" "$_de" \
                 "${TALOS_RUN_ID:-r-unknown}" "$_feat" "$_task" "$TEXTO" "$_hilo" "$MID")
        printf '  respuesta %s registrada en el hilo %s\n' "$_nuevo" "$_hilo"

        # Y se ENTREGA. Una respuesta escrita que nadie lee corta la
        # comunicacion en el ultimo tramo, que es justo el que importa.
        # shellcheck source=../../hooks/lib/resolve-capability.sh
        . "$SYS/hooks/lib/resolve-capability.sh"
        # shellcheck source=../../hooks/lib/agent-ref.sh
        . "$SYS/hooks/lib/agent-ref.sh"
        _target=$(talos_agent_ref_field "$_feat" name 2>/dev/null || echo "")
        if [ -n "$_target" ] && talos_agent_ref_check "$_feat" 2>/dev/null; then
            _esc=$(printf 'Respuesta a tu bloqueo (%s):\n\n%s' "$MID" "$TEXTO" \
                   | "$PY" -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')
            if talos_capability_run ExecutionAdapter prompt_agent \
                   "{\"target\":\"$_target\",\"text\":\"$_esc\",\"timeout_ms\":\"900000\"}" \
                   >/dev/null 2>&1; then
                printf '  entregada a %s\n' "$_target"
            else
                printf '  NO se pudo entregar a %s: quedo escrita y sin leer\n' "$_target"
            fi
        else
            echo "  el agente que pregunto ya no esta: la respuesta queda registrada"
            printf '  Cuando lo vuelvas a despachar, %s la va a tener en el hilo\n' "$_feat"
        fi
        "$PY" "$LIB" close "$DIR" "$MID" ANSWERED
        echo "  la pregunta quedo ANSWERED"
        ;;
    *)
        echo "talos: subcomando desconocido: $sub" >&2
        echo "talos: disponibles: list, show, answer, close" >&2
        exit 1 ;;
esac
