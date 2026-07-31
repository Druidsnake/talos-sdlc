#!/bin/sh
# talos.adapter.coord_dryrun - implementacion de referencia de CoordinationAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   TALOS_RUN_ID, TALOS_FEATURE_ID
# Sale:  0 ok / 5 error de adapter
#
# Simula issues, ramas y PRs sin tocar ningun remoto. Toda operacion mutante
# pasa por talos_mutate, que devuelve already_exists en un reintento con los
# mismos argumentos: sin eso, reintentar duplicaba PRs (correccion 38.2).

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"

op="${1:-}"
args="${2:-{\}}"
run="${TALOS_RUN_ID:-r-unknown}"
feat="${TALOS_FEATURE_ID:-none}"

case "$op" in
    health)
        talos_ok '{"healthy":true,"capability":"CoordinationAdapter","simulated":true}'
        ;;
    create_issue)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"coord:issue","url":"dry-run://issue"}'
        ;;
    create_branch)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"coord:branch","url":null}'
        ;;
    open_pr)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"coord:pr","url":"dry-run://pr"}'
        ;;
    request_review)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"coord:review-request","url":null}'
        ;;
    merge_pr)
        # Regla 37.4.4.3: dry-run-only NO PUEDE alcanzar FEATURE_MERGED.
        # El adapter simula la llamada; el gate es quien impide el estado.
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"coord:merge","url":null}'
        ;;
    get_pr_checks)
        talos_ok '{"checks":[],"simulated":true}'
        ;;
    "")
        talos_error precondition "falta la operacion"
        ;;
    *)
        talos_unknown_op "$op"
        ;;
esac
