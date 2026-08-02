#!/bin/sh
# Resuelve qué ejecuta la validación de JSON Schema.
#
# Aplica la misma cascada que talos-0.0.7.md seccion 37.4.5 define para
# binarios externos: variable de entorno, luego local al proyecto, luego PATH.
# Talos NO instala nada: detecta y guia.
#
# Uso:   . hooks/lib/resolve-validator.sh && talos_validate <schema> <documento>
# Sale:  0 valido / 1 invalido / 3 sin validador disponible

# Ruta del validador de referencia, relativa a este archivo.
TALOS_LIB_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
[ -f "$TALOS_LIB_DIR/lib/validate.py" ] && TALOS_LIB_DIR="$TALOS_LIB_DIR/lib"
TALOS_PY_VALIDATOR="$TALOS_LIB_DIR/validate.py"

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
    # 2b. Entorno de la instalacion de Talos.
    # Con Talos vendoreado en .talos/, el proyecto puede no tener venv propio y
    # el que sirve es el del sistema. Sin este paso, validar depende de donde
    # se pare uno.
    if [ -n "${TALOS_SYSTEM_ROOT:-}" ] \
       && [ -x "$TALOS_SYSTEM_ROOT/.venv/bin/python" ] \
       && "$TALOS_SYSTEM_ROOT/.venv/bin/python" -c "import jsonschema" 2>/dev/null; then
        echo "venv-sistema"
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

  python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml
  # o
  pipx install check-jsonschema
  # o
  npm install -g ajv-cli

O define uno propio, que reciba <schema> <documento> y salga 0 o 1:

  export TALOS_VALIDATOR="mi-validador"
HINT
}

talos_validate() {
    talos_schema="$1"
    talos_doc="$2"
    talos_impl=$(talos_resolve_validator) || {
        talos_validator_hint
        return 3
    }
    case "$talos_impl" in
        env)              $TALOS_VALIDATOR "$talos_schema" "$talos_doc" ;;
        venv)             .venv/bin/python "$TALOS_PY_VALIDATOR" "$talos_schema" "$talos_doc" ;;
        venv-sistema)     "$TALOS_SYSTEM_ROOT/.venv/bin/python" "$TALOS_PY_VALIDATOR" "$talos_schema" "$talos_doc" ;;
        python3)          python3 "$TALOS_PY_VALIDATOR" "$talos_schema" "$talos_doc" ;;
        check-jsonschema) check-jsonschema --schemafile "$talos_schema" "$talos_doc" ;;
        ajv)              ajv validate -s "$talos_schema" -d "$talos_doc" ;;
    esac
}
