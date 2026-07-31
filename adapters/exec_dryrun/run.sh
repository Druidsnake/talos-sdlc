#!/bin/sh
# talos.adapter.exec_dryrun - implementacion de referencia de ExecutionAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   TALOS_RUN_ID, TALOS_FEATURE_ID
# Sale:  0 ok / 5 error de adapter
#
# Simula workspaces, sesiones y agentes. NO ejecuta nada. Existe para que el
# modo dry-run-only corra sin herramientas externas (regla 37.4.4.1); una
# instalacion productiva reemplaza esta ligadura en config/extensions.yaml
# sin tocar el nucleo (regla 37.4.3.6).

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"

op="${1:-}"
args="${2:-{\}}"
run="${TALOS_RUN_ID:-r-unknown}"
feat="${TALOS_FEATURE_ID:-none}"

case "$op" in
    health)
        talos_ok '{"healthy":true,"capability":"ExecutionAdapter","simulated":true}'
        ;;
    create_workspace)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"exec:workspace","url":null}'
        ;;
    create_session)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"exec:session","url":null}'
        ;;
    start_agent)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"exec:agent","url":null}'
        ;;
    prompt_agent|run_command)
        # at_most_once: respuesta no reproducible / efectos de lado arbitrarios.
        talos_mutate "$op" "$run" "$feat" "$args" \
            "{\"id\":\"exec:$op\",\"url\":null}"
        ;;
    wait_agent)
        talos_ok '{"state":"idle","exit_code":0,"simulated":true}'
        ;;
    read_agent)
        talos_ok '{"output":"","truncated":false,"simulated":true}'
        ;;
    report_metadata)
        talos_ok '{"adapter":"dry-run","supports_parallel":false}'
        ;;
    "")
        talos_error precondition "falta la operacion"
        ;;
    *)
        talos_unknown_op "$op"
        ;;
esac
