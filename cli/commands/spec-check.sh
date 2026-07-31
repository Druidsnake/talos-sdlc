#!/bin/sh
# talos spec check - valida el spec del producto contra su schema.
#
# Verifica tres cosas que el schema solo no puede:
#   - que los archivos que el manifiesto referencia existan
#   - que un spec approved no haya cambiado despues de aprobarse (28.9)
#   - que el digest registrado corresponda al contenido actual
#
# Sale 0 valido / 2 invalido o ausente / 3 sin validador

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
talos spec check - valida el spec del producto

USO
    talos spec check [ruta-al-manifiesto]

    Por defecto: spec/manifest.yaml

QUE VERIFICA
    que valide contra spec-manifest.schema.json
    que el entry exista
    que las 9 secciones del minimo aceptable apunten a archivos reales
    si esta approved, que el digest coincida con el contenido actual
    (un spec que cambio despues de aprobarse exige re-aprobacion)

SALIDA
    0  spec valido
    2  spec ausente o rechazado
    3  sin validador de JSON Schema disponible
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

MANIFEST="${1:-spec/manifest.yaml}"

if [ ! -f "$MANIFEST" ]; then
    echo "talos: no existe $MANIFEST" >&2
    echo "talos: genera un esqueleto con: talos init --with-spec" >&2
    exit 2
fi

echo "spec: $MANIFEST"
echo ""

status=0

# 1. Schema
if "$SYS/hooks/validate-artifact.sh" spec-manifest "$MANIFEST"; then
    echo "  ok    valida contra spec-manifest.schema.json"
else
    rc=$?
    [ "$rc" -eq 3 ] && exit 3
    echo "  FALL  no valida contra su schema"
    status=2
fi

spec_dir=$(dirname "$MANIFEST")

field() {
    grep -E "^$1:" "$MANIFEST" | head -1 | sed "s/^$1:[[:space:]]*//" | tr -d '"' || true
}

st=$(field status)
entry=$(field entry)
[ -n "$st" ] && echo "  ok    status declarado: $st"

# 2. El entry existe
if [ -n "$entry" ]; then
    if [ -f "$spec_dir/$entry" ]; then
        echo "  ok    entry existe: $spec_dir/$entry"
    else
        echo "  FALL  entry no existe: $spec_dir/$entry"
        status=2
    fi
fi

# 3. Las nueve secciones apuntan a archivos reales
missing=""
for key in problem goal non_goals users requirements acceptance_criteria constraints risks test_plan; do
    ref=$(grep -E "^[[:space:]]+$key:" "$MANIFEST" | head -1 | sed "s/.*$key:[[:space:]]*//" | tr -d '"' || true)
    if [ -z "$ref" ]; then
        missing="$missing $key(sin-declarar)"
        continue
    fi
    file=$(printf '%s' "$ref" | sed 's/#.*//')
    [ -f "$spec_dir/$file" ] || missing="$missing $key($file)"
done

if [ -z "$missing" ]; then
    echo "  ok    las 9 secciones apuntan a archivos existentes"
else
    echo "  FALL  secciones que no resuelven:$missing"
    status=2
fi

# 4. Un spec approved no debe haber cambiado despues de aprobarse
if [ "$st" = "approved" ]; then
    recorded=$(field digest)
    if [ -z "$recorded" ]; then
        echo "  FALL  approved sin digest registrado"
        status=2
    elif command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
        if command -v sha256sum >/dev/null 2>&1; then
            actual="sha256:$(find "$spec_dir" -type f ! -name manifest.yaml -print0 2>/dev/null | sort -z | xargs -0 cat 2>/dev/null | sha256sum | cut -d' ' -f1)"
        else
            actual="sha256:$(find "$spec_dir" -type f ! -name manifest.yaml -print0 2>/dev/null | sort -z | xargs -0 cat 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
        fi
        if [ "$recorded" = "$actual" ]; then
            echo "  ok    el digest coincide: el spec no cambio desde la aprobacion"
        else
            echo "  FALL  el spec cambio despues de aprobarse (28.9)"
            echo "        registrado $recorded"
            echo "        actual     $actual"
            echo "        -> requiere re-aprobacion humana"
            status=2
        fi
    fi
fi

echo ""
case "$status" in
    0)
        if [ "$st" = "approved" ]; then
            echo "spec aprobado y consistente. Se puede planificar."
        else
            echo "spec valido, status=$st. Talos no planifica hasta que sea approved."
        fi
        ;;
    *) echo "spec RECHAZADO" ;;
esac
exit $status
