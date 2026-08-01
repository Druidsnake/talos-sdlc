#!/bin/sh
# Traduce modelo y proveedor a los argumentos NATIVOS de Claude Code.
#
# Mismo criterio que el shim de opencode: el nucleo resuelve tier -> modelo y
# no sabe como se le pide un modelo a un agente concreto. Claude Code lo toma
# como  --model <id>.
#
# Si el proveedor no es claude, no se emite nada.
#
# Uso:  agent-args.sh <modelo> <proveedor>

set -eu

modelo="${1:-}"
proveedor="${2:-}"

[ -n "$modelo" ] || exit 0
[ "$proveedor" = "claude" ] || exit 0

printf -- '--model %s' "$modelo"
