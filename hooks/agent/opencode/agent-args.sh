#!/bin/sh
# Traduce modelo y proveedor a los argumentos NATIVOS de opencode.
#
# El nucleo resuelve tier -> modelo leyendo config/models.yaml y no sabe como
# se le pide un modelo a un agente concreto: eso es vocabulario del runtime, y
# vive en su shim. opencode lo toma como  -m provider/model.
#
# Si el proveedor no es opencode, no se emite nada. Pasarle a un runtime el id
# de un modelo de otro proveedor es peor que no pasar ninguno: arranca con una
# cadena que no resuelve y falla lejos de aca.
#
# Uso:  agent-args.sh <modelo> <proveedor>

set -eu

modelo="${1:-}"
proveedor="${2:-}"

[ -n "$modelo" ] || exit 0
[ "$proveedor" = "opencode" ] || exit 0

printf -- '--model %s' "$modelo"
