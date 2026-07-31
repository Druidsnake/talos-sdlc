#!/bin/sh
# talos.adapter.model_dryrun - implementacion de referencia de ModelProviderAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   TALOS_RUN_ID, TALOS_FEATURE_ID
# Sale:  0 ok / 5 error de adapter
#
# No invoca ningun modelo. Devuelve respuestas canonicas para que el ciclo
# completo se pueda ejercitar sin credenciales ni costo.

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"

op="${1:-}"
args="${2:-{\}}"
run="${TALOS_RUN_ID:-r-unknown}"
feat="${TALOS_FEATURE_ID:-none}"

case "$op" in
    health)
        talos_ok '{"healthy":true,"capability":"ModelProviderAdapter"}'
        ;;
    list_models)
        talos_ok '{"models":[{"id":"dryrun.echo","tier":"any"}]}'
        ;;
    resolve_profile)
        # El routing por capacidad (20.1) resuelve tier -> modelo. En dry-run
        # todo tier resuelve al mismo modelo simulado.
        talos_ok "{\"model\":\"dryrun.echo\",\"requested\":$args}"
        ;;
    estimate_cost)
        talos_ok '{"currency":"USD","amount":0,"reason":"dry-run no consume presupuesto"}'
        ;;
    invoke_model)
        # at_most_once: el nucleo no debe reintentar esto solo (38.2.7).
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"model:invocation","url":null}'
        ;;
    report_usage)
        talos_mutate "$op" "$run" "$feat" "$args" \
            '{"id":"model:usage","url":null}'
        ;;
    "")
        talos_error precondition "falta la operacion"
        ;;
    *)
        talos_unknown_op "$op"
        ;;
esac
