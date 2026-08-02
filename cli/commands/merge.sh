#!/bin/sh
# talos merge - gobierno del merge. Ver talos-0.0.7.md seccion 31.
#
# MergeGate es nucleo, no rol. Ningun agente lo implementa y ninguna extension
# puede autorizar un merge.
#
# Sale 0 mergeado, 2 precondition, 3 gate rechazado, 4 requiere humano.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

EVDIR=orchestration/evidence

usage() {
    cat <<'USAGE'
talos merge - evalua MERGE_GATE y, si autoriza, ejecuta el merge

USO
    talos merge check <FEATURE> --pr <N>    solo evalua
    talos merge do <FEATURE> --pr <N>       evalua y mergea si autoriza

QUE VERIFICA
    CHECKS_GREEN           todos los checks en pass, segun el CIAdapter
    CHECKS_VERIFIABLE      el CheckRunSet es verificable
    MERGEABLE              el PR esta en estado mergeable
    NO_CONFLICTING_LEASE   nadie mas tiene la rama destino
    AUTO_MERGE_POLICY      auto_merge esta deshabilitado por defecto
    HUMAN_APPROVAL         riesgo critical exige HumanApproval
    MODE_ALLOWS_MERGE      dry-run-only no alcanza FEATURE_MERGED

    El veredicto de pase lo da el CIAdapter y nadie mas (regla 30.4.1). Un
    LocalTestReport no alcanza: es evidencia de avance, no de pase (30.4.3).

    Ninguna condicion se asume. Lo que no se puede comprobar se reporta como
    fallo, no como aprobado.

SALIDA
    0  mergeado, o el gate autoriza en modo check
    2  precondition fallida
    3  MERGE_GATE rechazo
    4  requiere decision humana
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# shellcheck source=../../hooks/lib/merge-gate.sh
. "$SYS/hooks/lib/merge-gate.sh"

sub="${1:-check}"
[ $# -gt 0 ] && shift
FEAT="${1:-}"
[ $# -gt 0 ] && shift

PR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --pr) PR="${2:?falta el numero de PR}"; shift 2 ;;
        *) shift ;;
    esac
done

[ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
[ -n "$PR" ]   || { echo "talos: falta --pr" >&2; exit 1; }

echo "talos ${TALOS_VERSION:-?}"
echo ""
printf '  feature  %s\n  pr       #%s\n  gate     MERGE_GATE\n\n' "$FEAT" "$PR"

set +e
report=$(talos_merge_gate "$FEAT" "$PR" "$EVDIR")
code=$?
set -e

printf '%s' "$report" \
    | sed -n 's/.*"reasons":\[\(.*\)\],"missing_evidence".*/\1/p' \
    | tr '}' '\n' \
    | while read -r line; do
        case "$line" in *code*) ;; *) continue ;; esac
        c=$(printf '%s' "$line" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
        s=$(printf '%s' "$line" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
        d=$(printf '%s' "$line" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
        case "$s" in
            pass) mark="ok  " ;;
            skip) mark="--  " ;;
            *)    mark="FALL" ;;
        esac
        printf '  %s %-22s %s\n' "$mark" "$c" "$d"
    done

# Regla 31.5: el MergeGateReport se persiste como evidencia, pase o falle.
saved=$(talos_gate_persist "$report" "$EVDIR" "${TALOS_RUN_ID:-}" "$FEAT" 2>/dev/null || true)

echo ""
case "$code" in
    0) echo "  MERGE_GATE pass" ;;
    4) echo "  MERGE_GATE needs_human: hace falta una decision humana explicita" ;;
    *) echo "  MERGE_GATE fail: el merge NO esta autorizado" ;;
esac
[ -n "$saved" ] && printf '  MergeGateReport en %s\n' "$saved"

if [ "$sub" = check ]; then
    exit "$code"
fi

[ "$sub" = "do" ] || { echo "talos: subcomando desconocido: $sub" >&2
                     echo "talos: disponibles: check, do" >&2; exit 1; }

if [ "$code" -ne 0 ]; then
    echo ""
    echo "  No se ejecuta ningun merge. El gate es la condicion, no una sugerencia."
    exit "$code"
fi

# Regla 31.8: el merge se delega al CoordinationAdapter con idempotency key.
# Este comando no mergea por su cuenta: autoriza y delega.
echo ""
echo "  el gate autoriza; se delega el merge al CoordinationAdapter"
set +e
out=$(talos_capability_run CoordinationAdapter merge_pr \
      "{\"pr\":\"$PR\",\"method\":\"squash\"}" 2>&1)
mrc=$?
set -e
if [ "$mrc" -ne 0 ]; then
    echo "  FALL el CoordinationAdapter no pudo mergear"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
    exit 5
fi
printf '  %s\n' "$out" | head -1
exit 0
