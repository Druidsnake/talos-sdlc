#!/bin/sh
# Instala los git hooks de Talos en el repositorio actual.
# Talos no instala nada por su cuenta: esto lo ejecuta una persona.
set -eu
ROOT=$(git rev-parse --show-toplevel)
HOOKS="$ROOT/.git/hooks"
SRC=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

for h in commit-msg pre-commit; do
    if [ -e "$HOOKS/$h" ] && [ ! -L "$HOOKS/$h" ]; then
        echo "talos: ya existe $HOOKS/$h y no es un symlink. No se toca." >&2
        echo "talos: moveelo o mergealo a mano." >&2
        exit 1
    fi
    ln -sf "$SRC/$h" "$HOOKS/$h"
    echo "instalado: .git/hooks/$h -> hooks/git/$h"
done
