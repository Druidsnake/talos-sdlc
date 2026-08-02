#!/bin/sh
# thalos human - la via por la que una persona acuña su decision.
#
# Diecisiete transiciones de las tablas 22.4 y 22.5 exigen HumanDecision o
# HumanApproval. Sin una forma de producirlas, esas transiciones son
# inalcanzables y el sistema no puede terminar nada que toque una ruta critica.
#
# Ningun agente puede emitir esta evidencia. El actor queda registrado y la
# evidencia sale verifiable:true porque una decision humana ES el hecho, no la
# afirmacion de un tercero sobre un hecho.
#
# Sale 0 registrada, 1 error de uso, 2 precondition fallida.

set -eu

SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

EVDIR=orchestration/evidence

usage() {
    cat <<'USAGE'
thalos human - registra una decision humana como evidencia

USO
    thalos human approve <FEATURE> [--scope TEXTO] [--note TEXTO]
    thalos human decide  <FEATURE> --decision <D> [--note TEXTO]
    thalos human list    [FEATURE]

DECISIONES
    retry     reintentar lo que fallo
    abort     detener
    accept    aceptar una oferta del sistema
    decline   rechazarla
    revise    pedir cambios
    reject    rechazar
    changes   pedir cambios sobre una revision
    resume    retomar algo escalado
    abandon   abandonar la feature

QUIEN FIRMA
    El actor sale de la identidad de git configurada en este repositorio. No se
    puede firmar por otro: si git no tiene identidad, no se registra nada.

    Un agente NO puede producir esta evidencia. Es el unico tipo que exige una
    persona, y por eso es lo que sostiene las rutas criticas.

SALIDA
    0  decision registrada y sellada
    1  error de uso
    2  falta identidad de git, o la decision no es del dominio
USAGE
}
case "${1:-}" in -h|--help|"") usage; [ -z "${1:-}" ] && exit 1 || exit 0 ;; esac

# shellcheck source=../../hooks/lib/gate.sh
. "$SYS/hooks/lib/gate.sh"

PY=$(thalos_python) || { echo "thalos: no hay python3" >&2; exit 2; }

VALID="retry abort accept decline revise reject changes resume abandon"

sub="$1"; shift
FEAT="${1:-}"
[ $# -gt 0 ] && shift

# ---------- list ----------

if [ "$sub" = list ]; then
    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    [ -d "$EVDIR" ] || { echo "  sin evidencia"; exit 0; }
    printf '  %-14s %-12s %-26s %s\n' TIPO FEATURE ACTOR DETALLE
    for f in "$EVDIR"/*.json; do
        [ -f "$f" ] || continue
        k=$(sed -n 's/.*"kind"[[:space:]]*:[[:space:]]*"\(Human[A-Za-z]*\)".*/\1/p' "$f" | head -1)
        [ -n "$k" ] || continue
        ff=$(sed -n 's/.*"feature_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
        [ -n "$FEAT" ] && [ "$ff" != "$FEAT" ] && continue
        who=$(sed -n 's/.*"produced_by"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
        det=$(sed -n 's/.*"decision"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
        [ -z "$det" ] && det=$(sed -n 's/.*"scope"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
        printf '  %-14s %-12s %-26s %s\n' "$k" "${ff:--}" "${who#human:}" "${det:--}"
    done
    exit 0
fi

[ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }

# El actor no se elige: sale de la identidad del repositorio. Firmar por otro
# convertiria la aprobacion humana en un campo de texto.
who=$(git config user.email 2>/dev/null || true)
[ -n "$who" ] || {
    echo "thalos: git no tiene identidad configurada en este repositorio" >&2
    echo "thalos: git config user.email <tu correo>" >&2
    exit 2
}

DECISION=""; NOTE=""; SCOPE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --decision) DECISION="${2:?falta la decision}"; shift 2 ;;
        --note)     NOTE="${2:-}"; shift 2 ;;
        --scope)    SCOPE="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

stamp=$(date -u +%Y%m%d%H%M%S)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

case "$sub" in
    approve)
        kind=HumanApproval
        evid="ev-$FEAT-approval-$stamp"
        payload="{\"scope\":\"${SCOPE:-feature:$FEAT}\",\"note\":\"$NOTE\",\"approved_by\":\"$who\"}"
        ;;
    decide)
        [ -n "$DECISION" ] || { echo "thalos: falta --decision" >&2; exit 1; }
        ok=0
        for d in $VALID; do [ "$d" = "$DECISION" ] && ok=1; done
        [ "$ok" -eq 1 ] || {
            echo "thalos: decision fuera del dominio: $DECISION" >&2
            echo "thalos: validas: $VALID" >&2
            exit 2
        }
        kind=HumanDecision
        evid="ev-$FEAT-decision-$stamp"
        payload="{\"decision\":\"$DECISION\",\"note\":\"$NOTE\",\"decided_by\":\"$who\"}"
        ;;
    *)
        echo "thalos: subcomando desconocido: $sub" >&2
        echo "thalos: disponibles: approve, decide, list" >&2
        exit 1
        ;;
esac

mkdir -p "$EVDIR"
cat > "$EVDIR/$evid.json" <<EOF
{"id":"$evid","kind":"$kind","schema_version":1,
 "run_id":"${THALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"human:$who","produced_at":"$now",
 "digest":"pendiente","verifiable":true,"payload":$payload}
EOF
"$PY" "$SYS/hooks/lib/evidence.py" seal "$EVDIR/$evid.json" >/dev/null

if ! "$SYS/hooks/validate-artifact.sh" evidence "$EVDIR/$evid.json" >/dev/null 2>&1; then
    rm -f "$EVDIR/$evid.json"
    echo "thalos: lo generado no valida contra evidence.schema.json" >&2
    exit 2
fi

echo "thalos ${THALOS_VERSION:-?}"
echo ""
printf '  %s registrada\n' "$kind"
printf '  feature   %s\n' "$FEAT"
printf '  actor     %s\n' "$who"
[ -n "$DECISION" ] && printf '  decision  %s\n' "$DECISION"
[ -n "$SCOPE" ]    && printf '  alcance   %s\n' "$SCOPE"
printf '  evidencia %s\n' "$EVDIR/$evid.json"
echo ""
echo "  Ahora la transicion que la exigia puede evaluarse."
exit 0
