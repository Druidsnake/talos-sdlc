#!/bin/sh
# talos.adapter.herdr - implementacion productiva de ExecutionAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   TALOS_RUN_ID, TALOS_FEATURE_ID   contexto de la idempotency key
#        TALOS_HERDR_BIN                  primer paso de la cascada (37.4.5)
#        TALOS_DRY_RUN=1                  registra la intencion, no ejecuta
# Sale:  0 ok / 2 precondition fallida / 5 error de adapter
#
# Responsable del ciclo de vida de procesos y de nada mas (seccion 38.5): no
# define politica de merge, no aprueba cambios, no decide routing y no expone
# comandos de usuario.

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"
. "$DIR/../lib/semver.sh"

REQUIRED_RANGE=">=0.7.0"

op="${1:-}"
args="${2:-{\}}"
run="${TALOS_RUN_ID:-r-unknown}"
feat="${TALOS_FEATURE_ID:-none}"

# ---------- resolucion del binario (seccion 37.4.5) ----------
#
# Cascada: variable de entorno -> .talos/bin/herdr -> PATH.
# La primera coincidencia gana. Talos NO instala nada (regla 37.4.5.4).
resolve_herdr() {
    if [ -n "${TALOS_HERDR_BIN:-}" ] && [ -x "${TALOS_HERDR_BIN}" ]; then
        printf '%s' "$TALOS_HERDR_BIN"
        return 0
    fi
    _vendored="${TALOS_PROJECT_ROOT:-.}/.talos/bin/herdr"
    if [ -x "$_vendored" ]; then
        printf '%s' "$_vendored"
        return 0
    fi
    command -v herdr 2>/dev/null && return 0
    return 1
}

missing_binary() {
    printf '{"status":"error","error_class":"precondition",' >&2
    printf '"message":"herdr no esta instalado",' >&2
    printf '"required":"%s",' >&2 "$REQUIRED_RANGE"
    printf '"resolution_order":["$TALOS_HERDR_BIN",".talos/bin/herdr","PATH"],' >&2
    printf '"install_hint":"curl -fsSL https://herdr.dev/install.sh | sh"}\n' >&2
    return 2
}

HERDR=$(resolve_herdr) || { missing_binary; exit 2; }

herdr_version() {
    "$HERDR" --version 2>/dev/null | head -1 | sed 's/[^0-9]*\([0-9][0-9.]*\).*/\1/'
}

# Regla 37.4.5.3: una version fuera de rango falla en PRECONDITION_GATE. No se
# degrada en silencio a "capaz funciona".
check_version() {
    _v=$(herdr_version)
    if [ -z "$_v" ]; then
        talos_error precondition "no se pudo leer la version de $HERDR"
        return 2
    fi
    if ! talos_semver_satisfies "$_v" "$REQUIRED_RANGE"; then
        printf '{"status":"error","error_class":"precondition",' >&2
        printf '"message":"herdr %s no satisface %s","path":"%s"}\n' >&2 \
            "$_v" "$REQUIRED_RANGE" "$HERDR"
        return 2
    fi
    printf '%s' "$_v"
}

# ---------- ejecucion ----------
#
# En dry-run el adapter registra la intencion y no toca el servidor. Es lo que
# permite ensayar una corrida productiva sin crear workspaces reales.
DRY="${TALOS_DRY_RUN:-0}"

# Este adapter ejecuta de verdad salvo que se le pida lo contrario. Lo declara
# antes de emitir cualquier resultado, para que dry_run no mienta.
# La lee talos_ok, que viene de adapters/lib/adapter.sh.
# shellcheck disable=SC2034
TALOS_ADAPTER_SIMULATED="$DRY"

herdr_do() {
    if [ "$DRY" = 1 ]; then
        talos_ledger_record "dryrun-$(date -u +%s)-$$" "herdr:$1" \
            "{\"intended\":\"$*\"}"
        printf '{"dry_run":true,"intended":"%s"}' "$*"
        return 0
    fi
    "$HERDR" "$@" 2>&1
}

# jq no es dependencia de Talos: el id sale del JSON de Herdr por sed.
first_id() {
    sed -n 's/.*"\('"$1"'\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' | head -1
}

json_get() {
    printf '%s' "$args" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

case "$op" in
    health)
        _v=$(check_version) || exit 2
        # Sano no es solo "el binario existe": tiene que haber servidor. Sin
        # servidor no hay donde ejecutar y la capacidad no esta satisfecha.
        if [ "$DRY" = 1 ]; then
            talos_ok "{\"healthy\":true,\"capability\":\"ExecutionAdapter\",\"version\":\"$_v\",\"path\":\"$HERDR\",\"dry_run\":true}"
        elif "$HERDR" workspace list >/dev/null 2>&1; then
            talos_ok "{\"healthy\":true,\"capability\":\"ExecutionAdapter\",\"version\":\"$_v\",\"path\":\"$HERDR\"}"
        else
            printf '{"status":"error","error_class":"precondition",' >&2
            printf '"message":"herdr %s responde pero no hay servidor","path":"%s",' >&2 "$_v" "$HERDR"
            printf '"hint":"arranca una sesion con  herdr"}\n' >&2
            exit 2
        fi
        ;;

    create_workspace)
        check_version >/dev/null || exit 2
        _label=$(json_get label)
        # El cwd es parte del contrato: una feature se desarrolla en su propio
        # directorio o worktree, no donde haya quedado parado el orquestador.
        _cwd=$(json_get cwd)
        # talos_mutate_run consulta el ledger ANTES de ejecutar. Con la forma
        # que recibe "$(comando)" ya evaluado, el workspace se creaba en cada
        # reintento aunque la respuesta dijera already_exists.
        # shellcheck disable=SC2086
        talos_mutate_run "$op" "$run" "$feat" "$args" workspace_id \
            herdr_do workspace create --no-focus \
                ${_label:+--label} ${_label:+"$_label"} \
                ${_cwd:+--cwd} ${_cwd:+"$_cwd"}
        ;;

    create_session)
        check_version >/dev/null || exit 2
        _ws=$(json_get workspace_id)
        # shellcheck disable=SC2086
        talos_mutate_run "$op" "$run" "$feat" "$args" tab_id \
            herdr_do tab create ${_ws:+--workspace} ${_ws:+"$_ws"}
        ;;

    start_agent)
        check_version >/dev/null || exit 2
        _name=$(json_get name); _kind=$(json_get kind); _pane=$(json_get pane)
        [ -n "$_name" ] && [ -n "$_kind" ] && [ -n "$_pane" ] || {
            talos_error precondition "start_agent requiere name, kind y pane"
            exit 5
        }
        # agent_args son argumentos NATIVOS del agente, opacos para el
        # adapter. Quien despacha decide que identidad e instrucciones lleva;
        # el adapter solo lo arranca (seccion 38.5).
        _aargs=$(json_get agent_args)
        if [ -n "$_aargs" ]; then
            # shellcheck disable=SC2086
            talos_mutate_run "$op" "$run" "$feat" "$args" terminal_id \
                herdr_do agent start "$_name" --kind "$_kind" --pane "$_pane" \
                    -- $_aargs
        else
            talos_mutate_run "$op" "$run" "$feat" "$args" terminal_id \
                herdr_do agent start "$_name" --kind "$_kind" --pane "$_pane"
        fi
        ;;

    prompt_agent)
        check_version >/dev/null || exit 2
        _target=$(json_get target); _text=$(json_get text)
        [ -n "$_target" ] && [ -n "$_text" ] || {
            talos_error precondition "prompt_agent requiere target y text"
            exit 5
        }
        # --wait no es una comodidad: sin el, un prompt enviado justo despues
        # de start_agent se pierde en silencio y la operacion reporta exito
        # igual. Con --wait, Herdr confirma que el agente cambio de estado o
        # devuelve agent_prompt_stalled, que es un error visible.
        _tmo=$(json_get timeout_ms)
        # shellcheck disable=SC2086
        talos_mutate_run "$op" "$run" "$feat" "$args" agent \
            herdr_do agent prompt "$_target" "$_text" --wait \
                ${_tmo:+--timeout} ${_tmo:+"$_tmo"}
        ;;

    wait_agent)
        check_version >/dev/null || exit 2
        _target=$(json_get target); _until=$(json_get until); _timeout=$(json_get timeout_ms)
        # shellcheck disable=SC2086
        talos_ok "$(herdr_do agent wait "$_target" \
                    ${_until:+--until} ${_until:+"$_until"} \
                    ${_timeout:+--timeout} ${_timeout:+"$_timeout"})"
        ;;

    read_agent)
        check_version >/dev/null || exit 2
        _target=$(json_get target); _lines=$(json_get lines)
        # agent read devuelve TEXTO de terminal, no JSON: saltos de linea,
        # comillas y caracteres de dibujo. Meterlo crudo en una posicion JSON
        # produce basura no parseable y rompe la regla 38.1.3.
        # shellcheck disable=SC2086
        _raw=$(herdr_do agent read "$_target" ${_lines:+--lines} ${_lines:+"$_lines"} \
               --source recent-unwrapped --format text)
        talos_ok "{\"output\":$(printf '%s' "$_raw" | talos_json_string),\"target\":\"$_target\"}"
        ;;

    run_command)
        check_version >/dev/null || exit 2
        _pane=$(json_get pane); _cmd=$(json_get command)
        [ -n "$_pane" ] && [ -n "$_cmd" ] || {
            talos_error precondition "run_command requiere pane y command"
            exit 5
        }
        # pane run manda el texto Y el Enter de forma atomica. Con send-text
        # el comando queda escrito en el prompt y nunca se ejecuta: la
        # operacion reportaba exito sin haber corrido nada.
        talos_mutate_run "$op" "$run" "$feat" "$args" pane_id \
            herdr_do pane run "$_pane" "$_cmd"
        ;;

    report_metadata)
        _v=$(check_version) || exit 2
        talos_ok "{\"adapter\":\"herdr\",\"version\":\"$_v\",\"path\":\"$HERDR\",\"supports_parallel\":true}"
        ;;

    "")
        talos_error precondition "falta la operacion"
        ;;
    *)
        talos_unknown_op "$op"
        ;;
esac
