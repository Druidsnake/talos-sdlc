#!/bin/sh
# Corre todas las verificaciones de Talos.
# Lo usan por igual una persona y el CI: una sola definicion de "esta bien".

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

PY=""
if [ -x .venv/bin/python ]; then
    PY=".venv/bin/python"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema, yaml" 2>/dev/null; then
    PY="python3"
else
    echo "talos: falta un python con jsonschema y pyyaml" >&2
    echo "talos: python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml" >&2
    exit 3
fi

failed=0
run() {
    printf '\n=== %s ===\n' "$1"
    shift
    if "$@"; then :; else failed=1; fi
}

run "schemas: rechazo de documentos invalidos" $PY tests/test_schemas.py
run "roles: coherencia entre config, archivos y schemas" $PY tests/test_roles.py
run "reglas: mapeo de requisito a mecanismo" $PY tests/test_rules.py
run "capacidades: registry y adapters de referencia" $PY tests/test_adapters.py
run "hooks: bloqueo efectivo" ./tests/test_hooks.sh
run "cli: slice vertical de punta a punta" ./tests/test_cli.sh

printf '\n=== JSON de todos los schemas ===\n'
bad=0
for f in schemas/*.json; do
    if ! $PY -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
        echo "  FALLA $f no es JSON valido"
        bad=1
    fi
done
[ "$bad" -eq 0 ] && echo "  ok    $(ls schemas/*.json | wc -l | tr -d ' ') schemas parsean"
[ "$bad" -eq 0 ] || failed=1

printf '\n'
if [ "$failed" -eq 0 ]; then
    echo "TODO VERDE"
    exit 0
fi
echo "HAY FALLAS"
exit 1
