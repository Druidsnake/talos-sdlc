#!/bin/sh
# Corre todas las verificaciones de Thalos.
# Lo usan por igual una persona y el CI: una sola definicion de "esta bien".

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

PY=""
if [ -x .venv/bin/python ]; then
    PY=".venv/bin/python"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema, yaml" 2>/dev/null; then
    PY="python3"
else
    echo "thalos: falta un python con jsonschema y pyyaml" >&2
    echo "thalos: python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml" >&2
    exit 3
fi

failed=0
run() {
    printf '\n=== %s ===\n' "$1"
    shift
    if "$@"; then :; else failed=1; fi
}

run "schemas: rechazo de documentos invalidos" $PY tests/test_schemas.py
run "roles: coherencia entre config, archivos y schemas" $PY tests/test_roles.py
run "reglas: mapeo de requisito a mecanismo" $PY tests/test_rules.py
run "capacidades: registry y adapters de referencia" $PY tests/test_adapters.py
run "estados: transiciones y contrato de gates" $PY tests/test_states.py
run "plan: PLAN_GATE sobre el grafo de features" $PY tests/test_plan.py
run "features: ejecutor de transiciones y leases" $PY tests/test_feature.py
run "herdr: adapter productivo y cascada de binarios" $PY tests/test_herdr.py
run "github: CoordinationAdapter y reconciliacion" $PY tests/test_github.py
run "merge: MergeGate y CIAdapter" $PY tests/test_merge.py
run "loop: proyeccion y orquestador" $PY tests/test_loop.py
run "presupuestos: limites sin degradar el tier" $PY tests/test_budget.py
run "vitalidad: la tabla de decision sobre un agente" $PY tests/test_liveness.py
run "ack: el encargo entro o no entro, y se sabe" $PY tests/test_ack.py
run "hooks: bloqueo efectivo" ./tests/test_hooks.sh
run "cli: slice vertical de punta a punta" ./tests/test_cli.sh

printf '\n=== sintaxis y estilo de shell ===\n'
# Este runner dice ser la unica definicion de "esta bien", para una persona y
# para el CI. Si no corre shellcheck y el CI si, son dos definiciones y una se
# entera tarde. Cubre tambien cli/ y adapters/, que son shell como el resto.
SH_FILES=$(find hooks tools tests cli adapters -name '*.sh' 2>/dev/null)
SH_FILES="$SH_FILES cli/thalos hooks/git/commit-msg hooks/git/pre-commit"

bad=0
for f in $SH_FILES; do
    [ -f "$f" ] || continue
    sh -n "$f" 2>/dev/null || { echo "  FALLA $f no es POSIX sh valido"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "  ok    $(echo "$SH_FILES" | wc -w | tr -d ' ') archivos parsean como POSIX sh"
[ "$bad" -eq 0 ] || failed=1

if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    if shellcheck --shell=sh --severity=warning $SH_FILES; then
        echo "  ok    shellcheck sin advertencias"
    else
        failed=1
    fi
else
    echo "  skip  shellcheck no instalado (brew install shellcheck)"
fi

printf '\n=== JSON de todos los schemas ===\n'
bad=0
for f in schemas/*.json; do
    if ! $PY -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
        echo "  FALLA $f no es JSON valido"
        bad=1
    fi
done
[ "$bad" -eq 0 ] && echo "  ok    $(ls schemas/*.json | wc -l | tr -d ' ') schemas parsean"
[ "$bad" -eq 0 ] || failed=1

printf '\n'
if [ "$failed" -eq 0 ]; then
    echo "TODO VERDE"
    exit 0
fi
echo "HAY FALLAS"
exit 1
