#!/bin/sh
# thalos.adapter.ci_dryrun - implementacion de referencia de CIAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   THALOS_RUN_ID, THALOS_FEATURE_ID
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
run="${THALOS_RUN_ID:-r-unknown}"
feat="${THALOS_FEATURE_ID:-none}"

case "$op" in
    health)
        thalos_ok '{"healthy":true,"capability":"CIAdapter","simulated":true}'
        ;;
    run_checks)
        thalos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"ci:run","url":"dry-run://checks"}'
        ;;
    get_check_status)
        thalos_ok '{"check_runs":[],"conclusion":"simulated","verifiable":false}'
        ;;
    publish_report)
        thalos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"ci:report","url":null}'
        ;;
    "")
        thalos_error precondition "falta la operacion"
        ;;
    *)
        thalos_unknown_op "$op"
        ;;
esac
