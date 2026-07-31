#!/bin/sh
# Verifica que los hooks BLOQUEEN lo que deben bloquear.
# Un hook que nunca deniega no es un mecanismo de enforcement.

set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

pass=0
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

expect() {
    want="$1"; shift
    label="$1"; shift
    if "$@" >/dev/null 2>&1; then got="permite"; else got="bloquea"; fi
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
        printf "  ok    %-8s %s\n" "$got" "$label"
    else
        fail=$((fail + 1))
        printf "  FALLA esperaba %s, obtuvo %s: %s\n" "$want" "$got" "$label"
    fi
}

echo "=== mecanismo 2: scope de escritura por rol ==="
scope() { ./hooks/check-write-scope.sh "$1" "$2"; }
expect permite "Developer escribe en src/"            scope Developer src/auth/verify.ts
expect permite "Developer escribe en tests/"          scope Developer tests/auth.test.ts
expect bloquea "Developer toca spec/"                 scope Developer spec/SPEC.md
expect bloquea "Developer toca workflows de CI"       scope Developer .github/workflows/ci.yml
expect bloquea "Developer toca orchestration/"        scope Developer orchestration/state.json
expect bloquea "Developer toca ruta no contemplada"   scope Developer package.json
expect bloquea "Reviewer reescribe codigo"            scope Reviewer src/auth/verify.ts
expect permite "Reviewer escribe su reporte"          scope Reviewer orchestration/reports/F001/review.json
expect permite "SpecAssistant escribe el spec"        scope SpecAssistant spec/manifest.yaml
expect bloquea "SpecAssistant toca codigo"            scope SpecAssistant src/index.ts
expect permite "Planner escribe el plan"              scope Planner orchestration/program-plan.json
expect bloquea "Planner corrige el spec"              scope Planner spec/SPEC.md
expect bloquea "FeatureLead implementa"               scope FeatureLead src/auth/verify.ts
expect bloquea "rol inexistente"                      scope Fixer src/auth/verify.ts

echo ""
echo "=== mecanismo 1: validacion de artefactos ==="
cat > "$tmp/review-ok.json" <<'EOF'
{"schema_version":1,"feature_id":"F001","reviewer":"R","created_at":"2026-07-31T10:00:00Z",
 "verdict":"approve","spec_refs_checked":["acceptance.md#AC-1"],"findings":[],"blocker_count":0}
EOF
cat > "$tmp/review-bad.json" <<'EOF'
{"schema_version":1,"feature_id":"F001","reviewer":"R","created_at":"2026-07-31T10:00:00Z",
 "verdict":"approve","spec_refs_checked":[],"findings":[],"blocker_count":0}
EOF
cat > "$tmp/task-bad.json" <<'EOF'
{"schema_version":1,"feature_id":"F001","task_id":"T1","status":"done",
 "declared_scope":["src/**"],"files_changed":["src/a.ts"],"created_at":"2026-07-31T10:00:00Z"}
EOF
cat > "$tmp/task-ok.json" <<'EOF'
{"schema_version":1,"feature_id":"F001","task_id":"T1","status":"done",
 "declared_scope":["src/**"],"files_changed":["src/a.ts"],"test_report_refs":["ev-1"],
 "created_at":"2026-07-31T10:00:00Z"}
EOF
val() { ./hooks/validate-artifact.sh "$1" "$2"; }
expect permite "review con spec_refs_checked"         val review "$tmp/review-ok.json"
expect bloquea "review sin declarar que reviso"       val review "$tmp/review-bad.json"
expect permite "task done con evidencia de pruebas"   val task-result "$tmp/task-ok.json"
expect bloquea "task done sin evidencia de pruebas"   val task-result "$tmp/task-bad.json"
expect permite "config real del repo"                 val roles-config config/roles.yaml

echo ""
echo "=== mecanismo 4: commit-msg ==="
msg() { printf '%s\n' "$1" > "$tmp/msg"; ./hooks/git/commit-msg "$tmp/msg"; }
expect permite "conventional commit valido"           msg "feat(schemas): agrega contrato de evidencia"
expect permite "merge generado por git"               msg "Merge branch 'main' into feature/F001"
expect bloquea "sin prefijo de tipo"                  msg "agrega contrato de evidencia"
expect bloquea "tipo inventado"                       msg "cosas(schemas): agrega contrato"
expect bloquea "asunto con punto final"               msg "feat(schemas): agrega contrato."
expect bloquea "asunto de mas de 72 caracteres"       msg "feat(schemas): $(printf 'x%.0s' $(seq 1 70))"

echo ""
echo "=== deriva: reglas generadas al dia ==="
if command -v python3 >/dev/null 2>&1 && [ -x .venv/bin/python ]; then
    cp hooks/generated/write-scope.rules "$tmp/rules.before"
    .venv/bin/python tools/build-rules.py >/dev/null 2>&1 || true
    if cmp -s "$tmp/rules.before" hooks/generated/write-scope.rules; then
        pass=$((pass + 1)); echo "  ok    write-scope.rules coincide con config/roles.yaml"
    else
        fail=$((fail + 1)); echo "  FALLA write-scope.rules quedo desincronizado"
    fi
else
    echo "  skip  sin .venv para regenerar reglas"
fi

echo ""
total=$((pass + fail))
echo "$pass/$total checks de hooks"
[ "$fail" -eq 0 ] || exit 1
echo "Todos los hooks bloquean lo que deben bloquear."
