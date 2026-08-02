#!/bin/sh
# thalos.adapter.model_dryrun - implementacion de referencia de ModelProviderAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   THALOS_RUN_ID, THALOS_FEATURE_ID
# Sale:  0 ok / 5 error de adapter
#
# No invoca ningun modelo. Devuelve respuestas canonicas para que el ciclo
# completo se pueda ejercitar sin credenciales ni costo.

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"

op="${1:-}"
args="${2:-{\}}"
run="${THALOS_RUN_ID:-r-unknown}"
feat="${THALOS_FEATURE_ID:-none}"

case "$op" in
    health)
        thalos_ok '{"healthy":true,"capability":"ModelProviderAdapter"}'
        ;;
    list_models)
        thalos_ok '{"models":[{"id":"dryrun.echo","tier":"any"}]}'
        ;;
    resolve_profile)
        # El routing por capacidad (20.1) resuelve tier -> modelo. En dry-run
        # todo tier resuelve al mismo modelo simulado.
        thalos_ok "{\"model\":\"dryrun.echo\",\"requested\":$args}"
        ;;
    estimate_cost)
        thalos_ok '{"currency":"USD","amount":0,"reason":"dry-run no consume presupuesto"}'
        ;;
    invoke_model)
        # at_most_once: el nucleo no debe reintentar esto solo (38.2.7).
        thalos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"model:invocation","url":null}'
        ;;
    report_usage)
        thalos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"model:usage","url":null}'
        ;;
    "")
        thalos_error precondition "falta la operacion"
        ;;
    *)
        thalos_unknown_op "$op"
        ;;
esac
