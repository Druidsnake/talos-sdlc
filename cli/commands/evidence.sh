#!/bin/sh
# talos evidence - sella y verifica la evidencia que justifica una transicion.
#
# Sin sellar, una evidencia no satisface ningun gate: el digest se verifica al
# leer (reglas 23.3.3 y 23.3.4).

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
talos evidence - sella y verifica evidencia

USO
    talos evidence seal <archivo.json>    calcula y escribe su digest
    talos evidence check [dir]            que hay y si cierra
    talos evidence digest <archivo.json>  el digest que le corresponde

QUE ES UNA EVIDENCIA
    Un artefacto tipado, persistido e inmutable que justifica una transicion
    de estado. La salida de un agente NO es evidencia verificable.

EL DIGEST
    Cubre payload y artifact_refs, con claves ordenadas y sin espacios:

        sha256(canonical_json({artifact_refs, payload}))

    Una evidencia cuyo digest no cuadra esta rota. No cuenta como presente:
    no se puede confiar en algo que cambio despues de sellarse.

    La seccion 23.3.3 exige el digest pero no fija la serializacion. Esta es
    una decision de implementacion, documentada en hooks/lib/evidence.py.

SALIDA
    0  todo bien
    1  hay evidencia rota
    2  error de uso
USAGE
}
case "${1:-}" in -h|--help|"") usage; [ -z "${1:-}" ] && exit 2 || exit 0 ;; esac

# shellcheck source=../../hooks/lib/gate.sh
. "$SYS/hooks/lib/gate.sh"

PY=$(talos_python) || {
    echo "talos: no hay python3 para leer evidencia" >&2
    echo "talos: python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml" >&2
    exit 2
}
LIB="$SYS/hooks/lib/evidence.py"

sub="$1"
shift

case "$sub" in
    seal)
        f="${1:?falta el archivo}"
        [ -f "$f" ] || { echo "talos: no existe $f" >&2; exit 2; }
        d=$("$PY" "$LIB" seal "$f") || exit 1
        # Validar despues de sellar: un digest correcto sobre un documento que
        # no cumple el envoltorio de la seccion 23.2 no sirve de nada.
        if "$SYS/hooks/validate-artifact.sh" evidence "$f" >/dev/null 2>&1; then
            printf 'sellada  %s\n  %s\n' "$f" "$d"
        else
            printf 'sellada  %s\n  %s\n' "$f" "$d"
            echo "  AVISO no valida contra evidence.schema.json" >&2
            exit 1
        fi
        ;;
    digest)
        f="${1:?falta el archivo}"
        "$PY" "$LIB" digest "$f"
        ;;
    check)
        dir="${1:-orchestration/evidence}"
        [ -d "$dir" ] || { echo "talos: no existe $dir" >&2; exit 2; }
        echo "talos ${TALOS_VERSION:-?}"
        echo ""
        printf '  evidencia en %s\n\n' "$dir"
        rows=$("$PY" "$LIB" read "$dir")
        if [ -z "$rows" ]; then
            echo "  sin evidencia legible"
            exit 0
        fi
        printf '  %-24s %-12s %s\n' KIND VERIFICABLE DIGEST
        printf '%s\n' "$rows" | while IFS='	' read -r kind ver dig id; do
            [ -z "$kind" ] && continue
            [ "$dig" = true ] && mark="ok  " || mark="FALL"
            printf '  %s %-22s %-12s %s\n' "$mark" "$kind" "$ver" "$id"
        done
        echo ""
        rotas=$(printf '%s\n' "$rows" | awk -F'\t' '$3 == "false"' | grep -c . | tr -d ' ')
        if [ "$rotas" -gt 0 ]; then
            echo "  $rotas evidencia(s) con digest que no cuadra"
            echo "  Una evidencia rota no justifica ninguna transicion."
            exit 1
        fi
        echo "  toda la evidencia cierra contra su digest"
        ;;
    *)
        echo "talos: subcomando desconocido: $sub" >&2
        echo "talos: disponibles: seal, check, digest" >&2
        exit 2
        ;;
esac
