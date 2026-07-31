#!/bin/sh
# Mecanismo 5 de system/00-enforcement.md: proteccion de rama.
#
# Esta es la barrera que NO se saltea. Los git hooks corren en la maquina de
# quien commitea y se evitan con --no-verify; esto corre del lado de GitHub.
#
# NO se ejecuta solo. Lo corre una persona, una vez, a conciencia:
# despues de aplicarlo, nadie puede pushear directo a main.
#
# Uso:  tools/setup-branch-protection.sh [owner/repo] [rama]

set -eu

REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
BRANCH="${2:-main}"
REVIEWS="${TALOS_REQUIRED_REVIEWS:-0}"

echo "Repositorio: $REPO"
echo "Rama:        $BRANCH"
echo "Reviews:     $REVIEWS"
echo ""
echo "Se va a exigir, para mergear en $BRANCH:"
echo "  - pull request (no mas push directo)"
echo "  - checks verdes: enforcement, generados al dia, sintaxis de shell"
echo "  - rama al dia con la base"
echo "  - conversaciones resueltas"
echo "  - sin force push ni borrado de rama"
echo ""
printf "Aplicar? [y/N] "
read -r answer
case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "cancelado"; exit 0 ;;
esac

gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
    -H "Accept: application/vnd.github+json" \
    --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "enforcement",
      "generados al dia",
      "sintaxis de shell"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": $REVIEWS,
    "dismiss_stale_reviews": true,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON

echo ""
echo "Aplicado. Verificar con:"
echo "  gh api repos/$REPO/branches/$BRANCH/protection --jq '{checks: .required_status_checks.contexts, pr: .required_pull_request_reviews.required_approving_review_count}'"
echo ""
echo "Notas:"
echo "  - enforce_admins queda en false: podes destrabar en una emergencia."
echo "    Ponelo en true cuando el flujo este asentado."
echo "  - TALOS_REQUIRED_REVIEWS=1 exige aprobacion de otra persona."
echo "    En un repo de una sola persona, dejalo en 0 o te bloqueas a vos mismo."
echo "  - Para quitar la proteccion:"
echo "      gh api -X DELETE repos/$REPO/branches/$BRANCH/protection"
