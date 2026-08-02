#!/bin/sh
# thalos.adapter.fs_local - implementacion de referencia de FileSystemAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   THALOS_RUN_ID, THALOS_FEATURE_ID  (contexto para la idempotency key)
# Sale:  0 ok / 5 error de adapter
#
# El filesystem es local: estas operaciones son reales, no simuladas. Lo que
# se mantiene es el contrato: resultado estructurado y forma de retorno
# mutante segun thalos-0.0.7.md 38.1.3 y 38.2.3.

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"

op="${1:-}"
args="${2:-{\}}"
run="${THALOS_RUN_ID:-r-unknown}"
feat="${THALOS_FEATURE_ID:-none}"

case "$op" in
    health)
        thalos_ok '{"healthy":true,"capability":"FileSystemAdapter"}'
        ;;
    read_file|list_dir|validate_path)
        thalos_ok "{\"operation\":\"$op\",\"args\":$args}"
        ;;
    write_file|ensure_dir)
        thalos_mutate "$op" "$run" "$feat" "$args" \
            "{\"id\":\"fs:$op\",\"url\":null}"
        ;;
    "")
        thalos_error precondition "falta la operacion"
        ;;
    *)
        thalos_unknown_op "$op"
        ;;
esac
