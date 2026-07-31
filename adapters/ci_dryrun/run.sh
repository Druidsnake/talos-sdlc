#!/bin/sh
# talos.adapter.ci_dryrun - implementacion de referencia de CIAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   TALOS_RUN_ID, TALOS_FEATURE_ID
# Sale:  0 ok / 5 error de adapter
#
# El CheckRunSet que devuelve esta marcado verifiable:false. Regla 30.4.1 dice
# que el pase de pruebas se determina por CheckRunSet del CIAdapter; regla
# 37.4.4.2 prohibe evidencia verificable en dry-run-only. Ambas se cumplen
# devolviendo un CheckRunSet que no puede pasar por evidencia de pase.

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"

op="${1:-}"
args="${2:-{\}}"
run="${TALOS_RUN_ID:-r-unknown}"
feat="${TALOS_FEATURE_ID:-none}"

case "$op" in
    health)
        talos_ok '{"healthy":true,"capability":"CIAdapter","simulated":true}'
        ;;
    run_checks)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"ci:run","url":"dry-run://checks"}'
        ;;
    get_check_status)
        talos_ok '{"check_runs":[],"conclusion":"simulated","verifiable":false}'
        ;;
    publish_report)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"ci:report","url":null}'
        ;;
    "")
        talos_error precondition "falta la operacion"
        ;;
    *)
        talos_unknown_op "$op"
        ;;
esac
