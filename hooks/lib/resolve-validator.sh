#!/bin/sh
# Resuelve qué ejecuta la validación de JSON Schema.
#
# Aplica la misma cascada que thalos-0.0.7.md seccion 37.4.5 define para
# binarios externos: variable de entorno, luego local al proyecto, luego PATH.
# Thalos NO instala nada: detecta y guia.
#
# Uso:   . hooks/lib/resolve-validator.sh && thalos_validate <schema> <documento>
# Sale:  0 valido / 1 invalido / 3 sin validador disponible

# Ruta del validador de referencia, relativa a este archivo.
THALOS_LIB_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
[ -f "$THALOS_LIB_DIR/lib/validate.py" ] && THALOS_LIB_DIR="$THALOS_LIB_DIR/lib"
THALOS_PY_VALIDATOR="$THALOS_LIB_DIR/validate.py"

thalos_resolve_validator() {
    # 1. Override explicito
    if [ -n "${THALOS_VALIDATOR:-}" ]; then
        echo "env"
        return 0
    fi
    # 2. Entorno local al proyecto
    if [ -x ".venv/bin/python" ] && .venv/bin/python -c "import jsonschema" 2>/dev/null; then
        echo "venv"
        return 0
    fi
    # 2b. Entorno de la instalacion de Thalos.
    # Con Thalos vendoreado en .thalos/, el proyecto puede no tener venv propio y
    # el que sirve es el del sistema. Sin este paso, validar depende de donde
    # se pare uno.
    if [ -n "${THALOS_SYSTEM_ROOT:-}" ] \
       && [ -x "$THALOS_SYSTEM_ROOT/.venv/bin/python" ] \
       && "$THALOS_SYSTEM_ROOT/.venv/bin/python" -c "import jsonschema" 2>/dev/null; then
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

thalos_validator_hint() {
    cat >&2 <<'HINT'
thalos: no hay validador de JSON Schema disponible.

Instala uno (Thalos no instala nada por su cuenta):

  python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml
  # o
  pipx install check-jsonschema
  # o
  npm install -g ajv-cli

O define uno propio, que reciba <schema> <documento> y salga 0 o 1:

  export THALOS_VALIDATOR="mi-validador"
HINT
}

thalos_validate() {
    thalos_schema="$1"
    thalos_doc="$2"
    thalos_impl=$(thalos_resolve_validator) || {
        thalos_validator_hint
        return 3
    }
    case "$thalos_impl" in
        env)              $THALOS_VALIDATOR "$thalos_schema" "$thalos_doc" ;;
        venv)             .venv/bin/python "$THALOS_PY_VALIDATOR" "$thalos_schema" "$thalos_doc" ;;
        venv-sistema)     "$THALOS_SYSTEM_ROOT/.venv/bin/python" "$THALOS_PY_VALIDATOR" "$thalos_schema" "$thalos_doc" ;;
        python3)          python3 "$THALOS_PY_VALIDATOR" "$thalos_schema" "$thalos_doc" ;;
        check-jsonschema) check-jsonschema --schemafile "$thalos_schema" "$thalos_doc" ;;
        ajv)              ajv validate -s "$thalos_schema" -d "$thalos_doc" ;;
    esac
}
