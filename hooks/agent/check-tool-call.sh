#!/bin/sh
# Mecanismo 2: decide si una llamada a herramienta puede proceder.
#
# Agnostico del runtime. Recibe herramienta y ruta ya extraidas; los shims
# de hooks/agent/<runtime>/ se encargan de extraerlas del formato de cada
# agente. Mismo patron que adapters sobre un puerto.
#
# Uso:   check-tool-call.sh <herramienta> <ruta>
# Sale:  0 permitido / 1 denegado / 2 error de uso
#
# El rol activo se resuelve de:
#   1. $TALOS_ROLE
#   2. orchestration/.current-role
#
# Sin rol activo, Talos NO esta gobernando la sesion y la llamada pasa.
# Eso es deliberado: el rol lo fija Talos al despachar, no el agente.

set -eu

AGENT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
HOOKS_DIR=$(dirname "$AGENT_DIR")
SYS=$(dirname "$HOOKS_DIR")

# Dos raices distintas, como exige la seccion 8:
#   SYS   -> donde vive Talos      (.talos/ vendoreado, o el repo si se autohospeda)
#   ROOT  -> donde vive el trabajo (spec/, orchestration/, src/)
#
# Confundirlas rompe el bloqueo entero y en silencio: con Talos vendoreado,
# dirname(hooks/) da .talos/, ahi no hay orchestration/.current-role, el rol
# queda vacio y la regla "sin rol la llamada pasa" deja pasar TODO.
#
# Es decir: el mecanismo 2 quedaba inerte justo en la instalacion normal.
if [ -n "${TALOS_PROJECT_ROOT:-}" ]; then
    ROOT="$TALOS_PROJECT_ROOT"
else
    case "$SYS" in
        */.talos) ROOT=$(dirname "$SYS") ;;
        *)        ROOT="$SYS" ;;
    esac
fi

if [ $# -ne 2 ]; then
    echo "uso: check-tool-call.sh <herramienta> <ruta>" >&2
    exit 2
fi

tool="$1"
path="$2"

# Herramientas que escriben en el sistema de archivos.
# Bash queda fuera a proposito: no se puede saber de forma confiable que
# rutas toca un comando arbitrario. Ver hooks/agent/README.md.
case "$tool" in
    Write|Edit|MultiEdit|NotebookEdit|write_file|edit_file|create_file) ;;
    *) exit 0 ;;
esac

# Rol activo
role="${TALOS_ROLE:-}"
if [ -z "$role" ] && [ -f "$ROOT/orchestration/.current-role" ]; then
    role=$(cat "$ROOT/orchestration/.current-role")
fi
if [ -z "$role" ]; then
    exit 0
fi

# Normaliza a ruta relativa a la raiz del proyecto.
#
# Se compara contra la raiz LOGICA y contra la FISICA. En macOS /tmp y /var son
# enlaces a /private/..., y un runtime que resuelve enlaces manda
# /private/var/.../src/a.ts mientras la raiz es /var/.../. Comparar prefijos en
# texto las ve distintas y deniega una ruta que esta dentro del proyecto: el
# bloqueo pasa a mentir sobre el alcance en cualquier proyecto bajo /tmp.
ROOT_REAL=$(CDPATH='' cd -P -- "$ROOT" 2>/dev/null && pwd) || ROOT_REAL="$ROOT"

case "$path" in
    "$ROOT"/*)      path="${path#"$ROOT"/}" ;;
    "$ROOT_REAL"/*) path="${path#"$ROOT_REAL"/}" ;;
    /*)
        echo "talos: DENEGADO ruta fuera del proyecto: $path" >&2
        echo "talos: rol $role solo puede escribir dentro de $ROOT" >&2
        exit 1
        ;;
    ./*) path="${path#./}" ;;
esac

# Traversal: una ruta que sube de nivel sale del proyecto.
# Los tres patrones cubren: ".." solo, algo que termina en "/..",
# y ".." en cualquier posicion intermedia.
case "$path" in
    ..|*/..|*../*)
        echo "talos: DENEGADO ruta con traversal: $path" >&2
        exit 1
        ;;
esac

exec "$HOOKS_DIR/check-write-scope.sh" "$role" "$path"
