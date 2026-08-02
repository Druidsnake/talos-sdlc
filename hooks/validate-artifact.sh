#!/bin/sh
# Mecanismo 1: validacion de schema.
# Rechaza un artefacto que no cumple su contrato estructural.
#
# Uso:  validate-artifact.sh <schema-name> <ruta-artefacto>
# Ej:   validate-artifact.sh review orchestration/reports/F001/review.json
# Sale: 0 valido / 1 invalido / 2 error de uso / 3 sin validador

set -eu

HOOKS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HOOKS_DIR")
SCHEMAS="${THALOS_SCHEMAS_DIR:-$ROOT/schemas}"

. "$HOOKS_DIR/lib/resolve-validator.sh"

if [ $# -ne 2 ]; then
    echo "uso: validate-artifact.sh <schema-name> <ruta-artefacto>" >&2
    exit 2
fi

schema_file="$SCHEMAS/$1.schema.json"
doc="$2"

if [ ! -f "$schema_file" ]; then
    echo "thalos: no existe el schema $1 en $SCHEMAS" >&2
    exit 2
fi
if [ ! -f "$doc" ]; then
    echo "thalos: no existe el artefacto $doc" >&2
    exit 2
fi

if thalos_validate "$schema_file" "$doc"; then
    exit 0
else
    status=$?
    [ "$status" -eq 3 ] && exit 3
    echo "thalos: RECHAZADO $doc no valida contra $1.schema.json" >&2
    exit 1
fi
