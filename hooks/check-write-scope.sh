#!/bin/sh
# Mecanismo 2: hook bloqueante pre-accion.
# Decide si un rol puede escribir en una ruta. POSIX shell puro, sin dependencias.
#
# Uso:  check-write-scope.sh <rol> <ruta>
# Sale: 0 permitido / 1 denegado / 2 error de uso
#
# Politica: deny gana sobre allow. Sin allow que matchee, se deniega.
# Fail-closed por diseno: una ruta no contemplada se bloquea, no se permite.

set -eu

RULES="${THALOS_SCOPE_RULES:-$(dirname "$0")/generated/write-scope.rules}"

if [ $# -ne 2 ]; then
    echo "uso: check-write-scope.sh <rol> <ruta>" >&2
    exit 2
fi

role="$1"
path="$2"

if [ ! -f "$RULES" ]; then
    echo "thalos: no existe $RULES" >&2
    echo "thalos: ejecuta tools/build-rules.py para generarlo" >&2
    exit 2
fi

# Normaliza el glob de Thalos a un patron de case:
#   src/**  -> src/*    (case de POSIX hace que * cruce /)
#   *.md    -> *.md
to_pattern() {
    printf '%s' "$1" | sed 's|\*\*|*|g'
}

matched_allow=0

# Primera pasada: deny gana, corta de inmediato.
while IFS='	' read -r r mode glob; do
    case "$r" in ''|'#'*) continue ;; esac
    [ "$r" = "$role" ] || continue
    [ "$mode" = "deny" ] || continue
    pattern=$(to_pattern "$glob")
    # shellcheck disable=SC2254  # el glob es deliberado: es el matcher de rutas
    case "$path" in
        $pattern)
            echo "thalos: DENEGADO $role no puede escribir en $path" >&2
            echo "thalos: regla: deny $glob" >&2
            exit 1
            ;;
    esac
done < "$RULES"

# Segunda pasada: busca un allow que matchee.
while IFS='	' read -r r mode glob; do
    case "$r" in ''|'#'*) continue ;; esac
    [ "$r" = "$role" ] || continue
    [ "$mode" = "allow" ] || continue
    pattern=$(to_pattern "$glob")
    # shellcheck disable=SC2254  # el glob es deliberado: es el matcher de rutas
    case "$path" in
        $pattern) matched_allow=1; break ;;
    esac
done < "$RULES"

if [ "$matched_allow" -eq 1 ]; then
    exit 0
fi

echo "thalos: DENEGADO $role no tiene write_paths que cubra $path" >&2
echo "thalos: sin regla allow que matchee, se deniega (fail-closed)" >&2
exit 1
