#!/bin/sh
# Resuelve qué ejecuta la validación de JSON Schema.
#
# Aplica la misma cascada que talos-0.0.6.md seccion 37.4.5 define para
# binarios externos: variable de entorno, luego local al proyecto, luego PATH.
# Talos NO instala nada: detecta y guia.
#
# Uso:   . hooks/lib/resolve-validator.sh && talos_validate <schema> <documento>
# Sale:  0 valido / 1 invalido / 3 sin validador disponible

talos_resolve_validator() {
    # 1. Override explicito
    if [ -n "${TALOS_VALIDATOR:-}" ]; then
        echo "env"
        return 0
    fi
    # 2. Entorno local al proyecto
    if [ -x ".venv/bin/python" ] && .venv/bin/python -c "import jsonschema" 2>/dev/null; then
        echo "venv"
        return 0
    fi
    # 3. PATH: validador dedicado primero
    if command -v check-jsonschema >/dev/null 2>&1; then
        echo "check-jsonschema"
        return 0
    fi
    if command -v ajv >/dev/null 2>&1; then
        echo "ajv"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" 2>/dev/null; then
        echo "python3"
        return 0
    fi
    echo "none"
    return 1
}

talos_validator_hint() {
    cat >&2 <<'HINT'
talos: no hay validador de JSON Schema disponible.

Instala uno (Talos no instala nada por su cuenta):

  pipx install check-jsonschema
  # o
  python3 -m venv .venv && .venv/bin/pip install jsonschema
  # o
  npm install -g ajv-cli

O define uno propio:

  export TALOS_VALIDATOR="mi-validador --schema"
HINT
}

talos_validate() {
    schema="$1"
    doc="$2"
    impl=$(talos_resolve_validator) || {
        talos_validator_hint
        return 3
    }
    case "$impl" in
        env)              $TALOS_VALIDATOR "$schema" "$doc" ;;
        venv)             .venv/bin/python -c "$TALOS_PY_VALIDATE" "$schema" "$doc" ;;
        python3)          python3 -c "$TALOS_PY_VALIDATE" "$schema" "$doc" ;;
        check-jsonschema) check-jsonschema --schemafile "$schema" "$doc" ;;
        ajv)              ajv validate -s "$schema" -d "$doc" ;;
    esac
}

TALOS_PY_VALIDATE='
import json, sys, pathlib
from jsonschema import Draft202012Validator
schema = json.loads(pathlib.Path(sys.argv[1]).read_text())
raw = pathlib.Path(sys.argv[2]).read_text()
if sys.argv[2].endswith((".yaml", ".yml")):
    import yaml
    doc = yaml.safe_load(raw)
else:
    doc = json.loads(raw)
errors = sorted(Draft202012Validator(schema).iter_errors(doc), key=lambda e: list(e.path))
for e in errors:
    loc = "/".join(str(p) for p in e.path) or "(raiz)"
    print(f"  {loc}: {e.message}", file=sys.stderr)
sys.exit(1 if errors else 0)
'
export TALOS_PY_VALIDATE
