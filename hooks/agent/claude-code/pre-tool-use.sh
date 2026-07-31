#!/bin/sh
# Shim de Claude Code para el mecanismo 2.
#
# Claude Code entrega un JSON por stdin con tool_name y tool_input.
# Este shim extrae la ruta, delega en check-tool-call.sh y traduce el
# veredicto al formato que el runtime espera.
#
# Instalar en .claude/settings.json:
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit|NotebookEdit",
#           "hooks": [
#             { "type": "command",
#               "command": "$CLAUDE_PROJECT_DIR/hooks/agent/claude-code/pre-tool-use.sh" }
#           ]
#         }
#       ]
#     }
#   }
#
# El contrato exacto del runtime puede cambiar entre versiones. Verificalo
# contra tu version antes de confiar en el bloqueo.

set -eu

SHIM_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
AGENT_DIR=$(dirname "$SHIM_DIR")

payload=$(cat)

# Extraccion de campos: jq si esta, python3 si no.
#
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
path = sys.argv[1].lstrip(".").split(".")
for key in path:
    if not isinstance(data, dict):
        sys.exit(0)
    data = data.get(key)
    if data is None:
        sys.exit(0)
print(data)
' "$1"
    fi
}

tool=$(extract '.tool_name')
file=$(extract '.tool_input.file_path')
[ -z "$file" ] && file=$(extract '.tool_input.notebook_path')
[ -z "$file" ] && file=$(extract '.tool_input.path')

# Sin herramienta o sin ruta no hay nada que decidir.
if [ -z "$tool" ] || [ -z "$file" ]; then
    exit 0
fi

if reason=$("$AGENT_DIR/check-tool-call.sh" "$tool" "$file" 2>&1); then
    exit 0
fi

# Denegado. Se emite la decision estructurada y ademas se sale con 2,
# para cubrir ambas convenciones del runtime.
escaped=$(printf '%s' "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')
cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$escaped"
  }
}
JSON
printf '%s\n' "$reason" >&2
exit 2
