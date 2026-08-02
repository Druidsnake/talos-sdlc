#!/bin/sh
# Shim de opencode para el mecanismo 2.
#
# opencode no ejecuta comandos como hook: sus extensiones son plugins que
# corren dentro del proceso. El plugin que instala install.sh invoca a ESTE
# script y le pasa por stdin lo que recibio el hook tool.execute.before:
#
#   {"tool":"write","args":{"filePath":"/abs/ruta"}}
#
# La forma la fija el plugin de Thalos, no opencode: es el contrato entre las
# dos mitades de este mismo shim.
#
# Sale 0 permitido / 2 denegado, con el motivo por stderr. El plugin traduce
# ese 2 en una excepcion, que es como opencode aborta una tool call.
#
# El contrato exacto del runtime puede cambiar entre versiones. Verificalo
# contra tu version antes de confiar en el bloqueo.

set -eu

SHIM_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
AGENT_DIR=$(dirname "$SHIM_DIR")

payload=$(cat)

# Un payload que no parsea devuelve vacio, nunca error. Denegar por no haber
# podido leer el formato convierte cualquier cambio del runtime en un bloqueo
# total del agente. Ver hooks/agent/README.md.
extract() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null || true
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for key in sys.argv[1].lstrip(".").split("."):
    if not isinstance(data, dict):
        sys.exit(0)
    data = data.get(key)
    if data is None:
        sys.exit(0)
print(data)
' "$1"
    fi
}

tool=$(extract '.tool')
file=$(extract '.args.filePath')
[ -z "$file" ] && file=$(extract '.args.path')

# Sin herramienta o sin ruta no hay nada que decidir.
if [ -z "$tool" ] || [ -z "$file" ]; then
    exit 0
fi

if reason=$("$AGENT_DIR/check-tool-call.sh" "$tool" "$file" 2>&1); then
    exit 0
fi

printf '%s\n' "$reason" >&2
exit 2
