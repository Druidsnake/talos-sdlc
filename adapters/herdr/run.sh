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
        # Un panel puede cerrarse: lo cierra una persona, o lo cierra el propio
        # Talos al soltar el rol. Sin esta verificacion, el ledger devolvia
        # already_exists sobre un panel muerto y el start_agent siguiente
        # fallaba con "pane not found" -a un comando de distancia de la causa,
        # y sobre un id que Talos mismo habia cerrado.
        #
        # Misma leccion que start_agent ya aplicaba para los agentes: para un
        # recurso que puede dejar de existir, la fuente de verdad es el
        # backend, no el registro local.
        talos_pane_vive() {
            [ "$DRY" = 1 ] && return 0
            "$HERDR" pane list 2>/dev/null | grep -qF "\"pane_id\":\"$1\""
        }
        # La lee talos_mutate_run, que viene de adapters/lib/adapter.sh.
        # shellcheck disable=SC2034
        TALOS_LEDGER_VERIFY=talos_pane_vive
        # Una sesion de ejecucion se realiza como un pane HERMANO, no como un
        # tab. Con un tab hay que cambiar de pestaña para ver al agente; con un
        # pane queda al lado de la consola, que es el punto de mirarlo.
        # El anchor sale del entorno de Herdr, no del nucleo. Donde esta
        # parado quien llama es asunto del runtime de ejecucion, y el nucleo no
        # tiene por que conocer una variable de Herdr (regla 38.5.5).
        _anchor=$(json_get pane)
        [ -n "$_anchor" ] || _anchor="${HERDR_PANE_ID:-}"
        _cwd=$(json_get cwd)
        _dir=$(json_get direction); [ -n "$_dir" ] || _dir=right
        # shellcheck disable=SC2086
        talos_mutate_run "$op" "$run" "$feat" "$args" pane_id \
            herdr_do pane split ${_anchor:+"$_anchor"} --direction "$_dir" \
                ${_cwd:+--cwd} ${_cwd:+"$_cwd"} --no-focus
        ;;

    start_agent)
        check_version >/dev/null || exit 2
        _name=$(json_get name); _kind=$(json_get kind); _pane=$(json_get pane)
        [ -n "$_name" ] && [ -n "$_kind" ] && [ -n "$_pane" ] || {
            talos_error precondition "start_agent requiere name, kind y pane"
            exit 5
        }

        # RECONCILIACION, no consulta al ledger.
        #
        # El ledger dice "esto ya se hizo una vez". Un agente puede MORIRSE:
        # que se haya arrancado no significa que este corriendo. Confiar en el
        # ledger devuelve already_exists sobre un pane vacio, y quien llamo se
        # queda esperando a un agente que no existe.
        #
        # Misma leccion que con GitHub: para un recurso que puede dejar de
        # existir, la fuente de verdad es el backend, no el registro local.
        if [ "$DRY" != 1 ]; then
            # Se busca por NOMBRE, que es lo que Talos controla, y no por
            # pane: un pane puede tener un agente muerto que herdr todavia
            # lista, o el shell de una persona. El nombre lo puso Talos al
            # despachar, asi que encontrarlo significa que ESTE agente vive.
            _vivo=$("$HERDR" agent list 2>/dev/null \
                    | tr '}' '\n' | grep -F "\"name\":\"$_name\"" | head -1)
            if [ -n "$_vivo" ]; then
                _tid=$(printf '%s' "$_vivo" | first_id terminal_id)
                _key=$(talos_idempotency_key "$run" "$feat" "$op" "$args") || exit 5
                printf '{"status":"already_exists","resource_ref":{"id":"%s","url":null},' "$_tid"
                printf '"idempotency_key":"%s","dry_run":false}\n' "$_key"
                exit 0
            fi
            # No hay agente vivo: si el ledger tiene una entrada vieja, esta
            # obsoleta. Se arranca igual.
            _key=$(talos_idempotency_key "$run" "$feat" "$op" "$args") || exit 5

            # Un pane recien abierto todavia no llego a su prompt: el shell
            # esta arrancando. herdr responde agent_pane_busy y quien pidio el
            # agente se queda sin el, por una carrera de un par de segundos.
            #
            # Se reintenta acotado. Si el pane esta ocupado de verdad -por el
            # shell de una persona, o por un agente que herdr todavia lista- el
            # reintento se agota y falla diciendolo, que es lo correcto.
            _intentos=0
            while :; do
                if _out=$(herdr_do agent start "$_name" --kind "$_kind" --pane "$_pane"); then
                    break
                fi
                case "$_out" in
                    *agent_pane_busy*)
                        _intentos=$((_intentos + 1))
                        if [ "$_intentos" -ge 10 ]; then
                            printf '{"status":"error","error_class":"adapter","operation":"start_agent",' >&2
                            printf '"message":"el pane %s no quedo disponible tras %s intentos",' >&2 \
                                "$_pane" "$_intentos"
                            printf '"backend":%s}\n' >&2 "$(printf '%s' "$_out" | talos_json_string)"
                            exit 5
                        fi
                        sleep 2
                        ;;
                    *)
                        printf '{"status":"error","error_class":"adapter","operation":"start_agent","message":%s}\n' \
                            "$(printf '%s' "$_out" | talos_json_string)" >&2
                        exit 5
                        ;;
                esac
            done
            # Un id extraido de una respuesta cualquiera no prueba que el
            # agente exista. Se verifica que quedo vivo con el nombre pedido.
            if ! "$HERDR" agent list 2>/dev/null | grep -qF "\"name\":\"$_name\""; then
                printf '{"status":"error","error_class":"adapter","operation":"start_agent",' >&2
                printf '"message":"herdr no reporto el agente %s vivo despues de arrancarlo"}\n' >&2 "$_name"
                exit 5
            fi
            _tid=$(printf '%s' "$_out" | first_id terminal_id)
            talos_ledger_record "$_key" "$op" "{\"id\":\"$_tid\",\"url\":null}"
            printf '{"status":"created","resource_ref":{"id":"%s","url":null},' "$_tid"
            printf '"idempotency_key":"%s","dry_run":false}\n' "$_key"
            exit 0
        fi
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

    close_session)
        check_version >/dev/null || exit 2
        _pane=$(json_get pane)
        [ -n "$_pane" ] || {
            talos_error precondition "close_session requiere pane"
            exit 5
        }
        # Cerrar un panel que ya no existe NO es un error: el resultado que se
        # pedia -que no este- ya se cumple. Fallar aca obligaria a quien libera
        # una feature a distinguir entre "no pude cerrar" y "no habia nada que
        # cerrar", y lo dejaria sin poder soltar el rol por un panel que una
        # persona ya cerro a mano.
        if [ "$DRY" != 1 ] && ! "$HERDR" pane list 2>/dev/null | grep -qF "\"pane_id\":\"$_pane\""; then
            printf '{"status":"already_exists","resource_ref":{"id":"%s","url":null},' "$_pane"
            printf '"idempotency_key":"%s","dry_run":false,"note":"el panel ya no existe"}\n' \
                "$(talos_idempotency_key "$run" "$feat" "$op" "$args")"
            exit 0
        fi
        talos_mutate_run "$op" "$run" "$feat" "$args" pane_id \
            herdr_do pane close "$_pane"
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
