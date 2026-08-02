#!/bin/sh
# talos plan - planificacion de programa. Ver talos-0.0.7.md seccion 29.
#
# Generar el plan es trabajo del Planner, que es un rol agente.
# Verificarlo es trabajo de PLAN_GATE, que es codigo y no invoca modelos.
#
# Sale 0 pass, 2 precondition fallida, 3 PLAN_GATE rechazado.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

PLAN_PATH="orchestration/program-plan.json"
SPEC_MANIFEST="spec/manifest.yaml"

usage() {
    cat <<'USAGE'
talos plan - planificacion de programa

USO
    talos plan check [ruta]       evalua PLAN_GATE sobre el plan
    talos plan init               esqueleto para empezar a planificar
    talos plan show [ruta]        el plan en orden de ejecucion

    Por defecto el plan es orchestration/program-plan.json

OPCIONES
    --format json     GateResult crudo
    --no-persist      no guarda el GateResult como evidencia

QUE VERIFICA PLAN_GATE
    el plan valida contra program-plan.schema.json
    el spec esta approved y el plan apunta a su digest
    los ids de feature son unicos
    toda dependencia declarada existe
    el grafo es aciclico
    todo riesgo critical exige aprobacion humana
    el capability_tier es coherente con el riesgo
    hay al menos una feature sin dependencias

    Un plan cuyo spec cambio despues de planificarse no vale: planifica sobre
    algo que ya no existe.

QUIEN GENERA EL PLAN
    El Planner. En modo dry-run-only no hay ModelProviderAdapter productivo,
    asi que talos plan init deja un esqueleto para completar a mano y el gate
    lo verifica igual. Ver talos-0.0.7.md 29.1 y 37.4.4.

SALIDA
    0  el plan pasa PLAN_GATE
    1  error de uso
    2  precondition fallida
    3  PLAN_GATE rechazo el plan
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# shellcheck source=../../hooks/lib/gate.sh
. "$SYS/hooks/lib/gate.sh"

PY=$(talos_python) || {
    echo "talos: no hay python3 para analizar el plan" >&2
    exit 2
}

sub="${1:-check}"
[ $# -gt 0 ] && shift

FORMAT=text
PERSIST=1
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        --format)     [ "${2:-}" = json ] && FORMAT=json; shift 2 ;;
        --no-persist) PERSIST=0; shift ;;
        -*) echo "talos: opcion desconocida: $1" >&2; exit 1 ;;
        *)  TARGET="$1"; shift ;;
    esac
done
[ -n "$TARGET" ] && PLAN_PATH="$TARGET"

# ---------- init ----------

if [ "$sub" = init ]; then
    if [ -f "$PLAN_PATH" ]; then
        echo "talos: $PLAN_PATH ya existe, no se pisa"
        echo "talos: el plan es un artefacto humano-revisable, no se regenera solo"
        exit 0
    fi
    # Regla 29.1: sin spec aprobado no hay nada que planificar.
    if [ ! -f "$SPEC_MANIFEST" ]; then
        echo "talos: no existe $SPEC_MANIFEST" >&2
        echo "talos: talos init --with-spec genera un esqueleto" >&2
        exit 2
    fi
    st=$(grep -E '^status:' "$SPEC_MANIFEST" | head -1 | sed 's/status:[[:space:]]*//' | tr -d '"')
    if [ "$st" != approved ]; then
        echo "talos: el spec esta en $st, no approved" >&2
        echo "talos: Talos no planifica hasta que sea approved (regla 29.1)" >&2
        exit 2
    fi
    dg=$(grep -E '^digest:' "$SPEC_MANIFEST" | head -1 | sed 's/digest:[[:space:]]*//' | tr -d '"')
    proj=$(grep -E '^title:' "$SPEC_MANIFEST" | head -1 | sed 's/title:[[:space:]]*//' | tr -d '"')

    mkdir -p "$(dirname "$PLAN_PATH")"
    cat >"$PLAN_PATH" <<EOF
{
  "schema_version": 1,
  "project": "${proj:-sin titulo}",
  "spec_digest": "$dg",
  "created_by": "role:Planner",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "features": [
    {
      "id": "F001",
      "title": "CAMBIAME: la primera feature",
      "description": "Derivada de los requisitos del spec aprobado.",
      "spec_refs": [],
      "acceptance_refs": [],
      "depends_on": [],
      "effort": "medium",
      "risk": "low",
      "capability_tier": "balanced",
      "human_approval_required": false
    }
  ]
}
EOF
    echo "creado $PLAN_PATH"
    echo ""
    echo "  Es un esqueleto, no un plan. El Planner lo completa; en dry-run-only"
    echo "  no hay ModelProviderAdapter productivo, asi que lo completas vos."
    echo ""
    echo "  Cuando este listo:  talos plan check"
    exit 0
fi

# ---------- show ----------

if [ "$sub" = show ]; then
    [ -f "$PLAN_PATH" ] || { echo "talos: no existe $PLAN_PATH" >&2; exit 2; }
    "$PY" - "$PLAN_PATH" <<'PYEOF'
import json, sys
plan = json.loads(open(sys.argv[1]).read())
feats = {f["id"]: f for f in plan["features"]}
done, wave = set(), 0
print(f"talos plan: {plan.get('project','?')}")
print()
while len(done) < len(feats):
    listos = [f for i, f in feats.items()
              if i not in done and set(f.get("depends_on") or []) <= done]
    if not listos:
        print("  quedan features bloqueadas: el grafo tiene un ciclo")
        break
    wave += 1
    print(f"  onda {wave}  (se pueden ejecutar en paralelo si lo permite la config)")
    for f in sorted(listos, key=lambda x: x["id"]):
        marca = "H" if f.get("human_approval_required") else " "
        print(f"    {marca} {f['id']}  {f['title'][:44]:<44} "
              f"{f['risk']:<8} {f['capability_tier']}")
        done.add(f["id"])
    print()
print("  H = exige aprobacion humana")
PYEOF
    exit 0
fi

[ "$sub" = check ] || { echo "talos: subcomando desconocido: $sub" >&2
                        echo "talos: disponibles: check, init, show" >&2; exit 1; }

# ---------- check: PLAN_GATE ----------

if [ ! -f "$PLAN_PATH" ]; then
    echo "talos: no existe $PLAN_PATH" >&2
    echo "talos: talos plan init deja un esqueleto" >&2
    exit 2
fi

reasons_json=""
add_reason() {
    reasons_json="$reasons_json{\"code\":\"$1\",\"status\":\"$2\",\"detail\":\"$3\"},"
}
decision=pass

# Mecanismo 1 antes que nada: un plan que no valida contra su schema no se
# analiza, se rechaza.
if "$SYS/hooks/validate-artifact.sh" program-plan "$PLAN_PATH" >/dev/null 2>&1; then
    add_reason SCHEMA_VALID pass "program-plan.schema.json"
else
    add_reason SCHEMA_VALID fail "no valida contra program-plan.schema.json"
    decision=fail
fi

if [ "$decision" = pass ]; then
    set +e
    analysis=$("$PY" "$SYS/hooks/lib/plan.py" check "$PLAN_PATH" "$SPEC_MANIFEST")
    acode=$?
    set -e
    [ "$acode" -eq 3 ] && decision=fail
    printf '%s\n' "$analysis" | while IFS='	' read -r c s d; do :; done
    while IFS='	' read -r c s d; do
        [ -z "$c" ] && continue
        add_reason "$c" "$s" "$(printf '%s' "$d" | sed 's/"/\\"/g')"
    done <<EOF
$analysis
EOF
fi

result=$(printf '{"gate":"PLAN_GATE","run_id":"%s","feature_id":null,"from_state":"PROGRAM_PLANNING","to_state":"%s","decision":"%s","reasons":[%s],"missing_evidence":[],"execution_mode":"%s","evaluated_at":"%s","evaluator_version":"%s"}' \
    "${TALOS_RUN_ID:-r-unknown}" \
    "$([ "$decision" = pass ] && echo PROGRAM_READY || echo PROGRAM_PLANNING)" \
    "$decision" "${reasons_json%,}" \
    "$(talos_execution_mode)" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "${TALOS_VERSION:-0.0.6}")

saved=""
[ "$PERSIST" -eq 1 ] && saved=$(talos_gate_persist "$result" "orchestration/evidence" 2>/dev/null || true)

if [ "$FORMAT" = json ]; then
    printf '%s\n' "$result"
    [ "$decision" = pass ] && exit 0 || exit 3
fi

echo "talos ${TALOS_VERSION:-?}"
echo ""
printf '  plan  %s\n' "$PLAN_PATH"
printf '  gate  PLAN_GATE\n'
echo ""
printf '%s' "$reasons_json" | tr '}' '\n' | while read -r line; do
    case "$line" in *code*) ;; *) continue ;; esac
    c=$(printf '%s' "$line" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
    s=$(printf '%s' "$line" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
    d=$(printf '%s' "$line" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
    case "$s" in
        pass) mark="ok  " ;;
        skip) mark="--  " ;;
        *)    mark="FALL" ;;
    esac
    printf '  %s %-26s %s\n' "$mark" "$c" "$d"
done

echo ""
if [ "$decision" = pass ]; then
    echo "  PLAN_GATE pass: el programa puede pasar a PROGRAM_READY"
else
    echo "  PLAN_GATE fail: el plan no autoriza planificar"
    echo "  Regla 29.10: se reintenta hasta config.reliability.max_plan_attempts."
fi
[ -n "$saved" ] && printf '  GateResult persistido en %s\n' "$saved"

[ "$decision" = pass ] && exit 0
exit 3
