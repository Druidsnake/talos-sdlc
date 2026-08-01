#!/bin/sh
# talos feature - ejecucion de features. Ver talos-0.0.6.md secciones 30 y 22.5.
#
# start recorre las transiciones F1 y F2 de la tabla 22.5:
#   F1  ->  FEATURE_READY          READY_GATE, evidencia ProgramPlanEntry + DependencySet
#   F2  ->  FEATURE_IN_PROGRESS    READY_GATE + lease, evidencia LockLease + IssueRef + BranchRef
#
# Ninguna la fuerza: produce la evidencia, deja que el gate decida y solo
# avanza si el gate autoriza.
#
# Sale 0 ok, 2 precondition fallida, 3 gate rechazado, 4 needs_human.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

PLAN=orchestration/program-plan.json
LOCKS=orchestration/locks.json
EVDIR=orchestration/evidence

usage() {
    cat <<'USAGE'
talos feature - ejecucion de features

USO
    talos feature start <ID>      lleva la feature a FEATURE_IN_PROGRESS
    talos feature dispatch <ID> --role <ROL> --pane <PANE> [--kind KIND]
                                  despacha un agente con rol y alcance activos
    talos feature list            estado de todas las features del plan
    talos feature show <ID>       detalle de una feature
    talos feature release <ID>    suelta el rol activo

QUE HACE start
    1. verifica que la feature exista en el plan y que sus dependencias esten
       terminadas
    2. produce ProgramPlanEntry y DependencySet como evidencia sellada
    3. transiciona a FEATURE_READY si READY_GATE lo autoriza          (F1)
    4. toma el lease de la rama, crea issue y rama por el
       CoordinationAdapter, y sella LockLease, IssueRef y BranchRef
    5. transiciona a FEATURE_IN_PROGRESS si el gate lo autoriza       (F2)

    Cada paso emite su evento y persiste el GateResult que lo autorizo. Si un
    gate rechaza, se emite talos.transition.rejected y no se avanza.

    El adapter que crea issue y rama sale del registry, no esta cableado.
    En dry-run-only las operaciones se simulan y quedan en el ledger.

QUE HACE dispatch
    1. verifica que la feature este en FEATURE_IN_PROGRESS
    2. verifica que el rol exista en el registro de scope
    3. activa el rol: a partir de ahi toda escritura del agente pasa por el
       mecanismo 2 y se deniega fuera de write_paths
    4. compone el brief -instrucciones del rol + alcance concreto- y arranca
       el agente por el ExecutionAdapter

    El rol lo fija Talos, no lo elige el agente. Un rol desconocido no se
    despacha: sin scope, el bloqueo dejaria pasar todo.

SALIDA
    0  la feature quedo en FEATURE_IN_PROGRESS
    1  error de uso
    2  precondition fallida
    3  un gate rechazo la transicion
    4  requiere decision humana
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# shellcheck source=../../hooks/lib/transition.sh
. "$SYS/hooks/lib/transition.sh"
# shellcheck source=../../hooks/lib/role.sh
. "$SYS/hooks/lib/role.sh"
# shellcheck source=../../hooks/lib/resolve-capability.sh
. "$SYS/hooks/lib/resolve-capability.sh"

PY=$(talos_python) || { echo "talos: no hay python3" >&2; exit 2; }

sub="${1:-list}"
[ $# -gt 0 ] && shift
FEAT="${1:-}"

need_plan() {
    [ -f "$PLAN" ] || { echo "talos: no existe $PLAN" >&2
                        echo "talos: talos plan init" >&2; exit 2; }
}

# ---------- list ----------

if [ "$sub" = list ]; then
    need_plan
    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  %-6s %-38s %-22s %s\n' ID TITULO ESTADO RIESGO
    "$PY" - "$PLAN" <<'PYEOF' | while IFS='	' read -r fid title risk; do
import json, sys
for f in json.loads(open(sys.argv[1]).read())["features"]:
    print(f"{f['id']}\t{f['title'][:36]}\t{f['risk']}")
PYEOF
        st=$(talos_feature_state "$fid" 2>/dev/null || echo "-")
        printf '  %-6s %-38s %-22s %s\n' "$fid" "$title" "$st" "$risk"
    done
    echo ""
    echo "  - = todavia no arranco"
    exit 0
fi

# ---------- show ----------

if [ "$sub" = show ]; then
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    sf="orchestration/features/$FEAT/state.json"
    [ -f "$sf" ] || { echo "talos: $FEAT no arranco todavia" >&2; exit 2; }
    "$PY" -m json.tool "$sf"
    exit 0
fi

# ---------- release ----------

if [ "$sub" = release ]; then
    actual=$(talos_role_current 2>/dev/null || echo "")
    talos_role_deactivate
    if [ -n "$actual" ]; then
        echo "rol $actual liberado: Talos ya no gobierna esta sesion"
    else
        echo "no habia rol activo"
    fi
    exit 0
fi

# ---------- dispatch ----------

if [ "$sub" = dispatch ]; then
    ROLE=""; PANE=""; KIND="claude"
    while [ $# -gt 0 ]; do
        case "$1" in
            --role) ROLE="${2:?falta el rol}"; shift 2 ;;
            --pane) PANE="${2:?falta el pane}"; shift 2 ;;
            --kind) KIND="${2:?falta el kind}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    [ -n "$ROLE" ] || { echo "talos: falta --role" >&2; exit 1; }
    [ -n "$PANE" ] || { echo "talos: falta --pane" >&2; exit 1; }

    echo "talos ${TALOS_VERSION:-?}"
    echo ""

    # Un agente no se despacha sobre una feature que no arranco.
    est=$(talos_feature_state "$FEAT" 2>/dev/null || echo "")
    if [ "$est" != FEATURE_IN_PROGRESS ]; then
        printf '  FALL %s esta en %s, no en FEATURE_IN_PROGRESS\n' "$FEAT" "${est:--}"
        echo ""
        echo "  Un Developer se despacha sobre trabajo en curso. Arranca con:"
        echo "    talos feature start $FEAT"
        exit 2
    fi

    # Fail-closed: sin rol conocido no hay scope, y sin scope el bloqueo deja
    # pasar todo. Es preferible no despachar.
    if ! talos_role_activate "$ROLE" "$FEAT"; then
        exit 2
    fi
    printf '  rol      %s (activo)\n' "$ROLE"
    printf '  feature  %s\n' "$FEAT"
    printf '  pane     %s\n\n' "$PANE"

    printf '  alcance de escritura que se le impone:\n'
    talos_role_scope "$ROLE" | while IFS='	' read -r v g; do
        [ -z "$v" ] && continue
        printf '    %-9s %s\n' "$v" "$g"
    done
    echo ""

    brief_file="orchestration/features/$FEAT/brief.md"
    mkdir -p "$(dirname "$brief_file")"
    talos_role_brief "$ROLE" "$FEAT" > "$brief_file"
    printf '  brief    %s (%s lineas)\n' "$brief_file" "$(wc -l < "$brief_file" | tr -d ' ')"

    # El nucleo compone la identidad; el adapter solo arranca el proceso.
    aargs="--append-system-prompt $(printf '%s' "$brief_file")"
    set +e
    out=$(talos_capability_run ExecutionAdapter start_agent \
          "{\"name\":\"talos_$(printf '%s' "$FEAT" | tr 'A-Z' 'a-z')\",\"kind\":\"$KIND\",\"pane\":\"$PANE\",\"agent_args\":\"$aargs\"}" 2>&1)
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        printf '  FALL el ExecutionAdapter no pudo arrancar el agente\n'
        printf '%s\n' "$out" | sed 's/^/    /' | head -4
        talos_role_deactivate
        echo ""
        echo "  Rol liberado: no queda gobernando una sesion que no arranco."
        exit 5
    fi
    printf '  agente   arrancado por el ExecutionAdapter\n'
    echo ""
    echo "  El rol queda activo hasta  talos feature release $FEAT"
    exit 0
fi

[ "$sub" = start ] || { echo "talos: subcomando desconocido: $sub" >&2
                        echo "talos: disponibles: start, dispatch, list, show, release" >&2; exit 1; }
[ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }

# ---------- start ----------

need_plan
mkdir -p "$EVDIR" orchestration/features

echo "talos ${TALOS_VERSION:-?}"
echo ""
printf '  feature  %s\n\n' "$FEAT"

# start no es idempotente: reejecutarlo sobre una feature ya arrancada la haria
# retroceder a FEATURE_READY, y un estado no retrocede por reintentar un
# comando. La tabla 22.5 no tiene ninguna transicion de vuelta a FEATURE_READY.
actual=$(talos_feature_state "$FEAT" 2>/dev/null || echo "")
if [ -n "$actual" ] && [ "$actual" != FEATURE_READY ]; then
    printf '  FALL %s ya esta en %s\n' "$FEAT" "$actual"
    echo ""
    echo "  start solo entra a la maquina. Para avanzar desde aca hace falta la"
    echo "  transicion que corresponda; ver  talos gate --from feature $actual"
    exit 2
fi

# Regla 29: la feature tiene que existir en el plan y sus dependencias tienen
# que estar terminadas. Sin eso no hay ProgramPlanEntry que sellar.
set +e
info=$("$PY" - "$PLAN" "$FEAT" <<'PYEOF'
import json, sys
plan = json.loads(open(sys.argv[1]).read())
feats = {f["id"]: f for f in plan["features"]}
f = feats.get(sys.argv[2])
if f is None:
    print(f"ERROR\tno existe {sys.argv[2]} en el plan", file=sys.stderr)
    raise SystemExit(2)
print(json.dumps({"entry": f, "deps": f.get("depends_on") or []}))
PYEOF
)
rc=$?
set -e
[ "$rc" -ne 0 ] && { echo "$info" >&2; exit 2; }

deps=$(printf '%s' "$info" | "$PY" -c 'import json,sys; print(" ".join(json.load(sys.stdin)["deps"]))')

# DependencySet: una dependencia satisfecha es una feature en estado terminal
# de exito. Cualquier otra cosa bloquea (transicion F3).
dep_ok=1
dep_detail=""
for d in $deps; do
    dst=$(talos_feature_state "$d" 2>/dev/null || echo "-")
    if [ "$dst" != FEATURE_DONE ]; then
        dep_ok=0
        dep_detail="$dep_detail $d=$dst"
    fi
done

if [ "$dep_ok" -eq 0 ]; then
    printf '  FALL dependencias sin terminar:%s\n' "$dep_detail"
    echo ""
    echo "  READY_GATE no autoriza: una dependencia sin FEATURE_DONE bloquea (F3)."
    exit 3
fi

# ---------- evidencia de F1 ----------

seal() {
    "$PY" "$SYS/hooks/lib/evidence.py" seal "$1" >/dev/null
}
mkev() {
    _id="$1"; _kind="$2"; _ver="$3"; _payload="$4"
    cat >"$EVDIR/$_id.json" <<EOF
{"id":"$_id","kind":"$_kind","schema_version":1,
 "run_id":"${TALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"core:Orchestrator","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "digest":"pendiente","verifiable":true,"payload":$_payload}
EOF
    seal "$EVDIR/$_id.json"
}

stamp=$(date -u +%Y%m%d%H%M%S)
entry=$(printf '%s' "$info" | "$PY" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["entry"]))')
mkev "ev-$FEAT-plan-$stamp" ProgramPlanEntry true "$entry"
mkev "ev-$FEAT-deps-$stamp" DependencySet true \
     "{\"satisfied\":true,\"depends_on\":$(printf '%s' "$info" | "$PY" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["deps"]))')}"

# F1 no tiene estado origen: es la entrada a la maquina de feature, y en la
# tabla figura con "-". Se ejecuta como cualquier otra transicion.
printf '  F1  -> FEATURE_READY\n'
set +e
out=$(talos_transition_exec feature - FEATURE_READY "$EVDIR" "$FEAT")
rc=$?
set -e
printf '%s\n' "$out" | while IFS='=' read -r k v; do
    case "$k" in
        event)       [ -n "$v" ] && printf '      ok   evento %s\n' "$v" ;;
        gate_result) [ -n "$v" ] && printf '      ok   GateResult %s\n' "$(basename "$v")" ;;
    esac
done
if [ "$rc" -ne 0 ]; then
    echo ""
    echo "  READY_GATE no autoriza la entrada a la maquina de feature (F1)."
    exit "$rc"
fi

# ---------- evidencia de F2 ----------

printf '\n  F2  -> FEATURE_IN_PROGRESS\n'

# Lease sobre la rama: regla 32.4.1, dos features no comparten el recurso.
set +e
lease=$("$PY" "$SYS/hooks/lib/lock.py" acquire "$LOCKS" \
        "branch:feature/$FEAT" "$FEAT" "${TALOS_RUN_ID:-r-unknown}" \
        "feature start" 300 2>/tmp/talos-lock-err)
lrc=$?
set -e
if [ "$lrc" -ne 0 ]; then
    printf '      FALL no se pudo tomar el lease\n'
    sed 's/^/      /' /tmp/talos-lock-err
    echo ""
    echo "  Regla 32.4.1: si dos features quieren el mismo recurso, se serializa."
    exit 3
fi
LEASE_ID=$(printf '%s' "$lease" | sed -n 's/.*"lease_id"[^"]*"\([^"]*\)".*/\1/p')
GEN=$(printf '%s' "$lease" | sed -n 's/.*"generation"[^0-9]*\([0-9]*\).*/\1/p')
printf '      ok   lease %s (generation %s)\n' "$LEASE_ID" "$GEN"

# Issue y rama por el adapter ligado a CoordinationAdapter. El nucleo no sabe
# cual es: lo resuelve el registry.
sem="{\"feature\":\"$FEAT\",\"generation\":$GEN}"
set +e
issue_out=$(talos_capability_run CoordinationAdapter create_issue "$sem" 2>&1)
irc=$?
talos_capability_run CoordinationAdapter create_branch "$sem" >/dev/null 2>&1
brc=$?
set -e
if [ "$irc" -ne 0 ] || [ "$brc" -ne 0 ]; then
    printf '      FALL el CoordinationAdapter no respondio\n'
    "$PY" "$SYS/hooks/lib/lock.py" release "$LOCKS" "$LEASE_ID" >/dev/null 2>&1 || true
    exit 5
fi
ISSUE=$(printf '%s' "$issue_out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
BRANCH="feature/$FEAT"
printf '      ok   issue %s, rama %s\n' "$ISSUE" "$BRANCH"

mkev "ev-$FEAT-lease-$stamp" LockLease true "$lease"
mkev "ev-$FEAT-issue-$stamp" IssueRef true "{\"id\":\"$ISSUE\",\"adapter_status\":\"simulado\"}"
mkev "ev-$FEAT-branch-$stamp" BranchRef true "{\"name\":\"$BRANCH\",\"sha\":null}"

TALOS_LEASE_ID="$LEASE_ID"
TALOS_ISSUE_REF="$ISSUE"
TALOS_BRANCH_REF="$BRANCH"
export TALOS_LEASE_ID TALOS_ISSUE_REF TALOS_BRANCH_REF

set +e
out=$(talos_transition_exec feature FEATURE_READY FEATURE_IN_PROGRESS "$EVDIR" "$FEAT")
rc=$?
set -e
printf '%s\n' "$out" | while IFS='=' read -r k v; do
    case "$k" in
        decision) printf '      %s  %s\n' "$([ "$v" = pass ] && echo 'ok  ' || echo FALL)" "decision: $v" ;;
        event)    printf '      ok   evento %s\n' "$v" ;;
        gate_result) [ -n "$v" ] && printf '      ok   GateResult %s\n' "$v" ;;
    esac
done

echo ""
if [ "$rc" -eq 0 ]; then
    printf '  %s esta en FEATURE_IN_PROGRESS\n' "$FEAT"
    echo "  El lease vence en 300s. Sin heartbeat, el LockManager lo da por muerto."
else
    printf '  %s NO avanzo: el gate rechazo la transicion\n' "$FEAT"
    "$PY" "$SYS/hooks/lib/lock.py" release "$LOCKS" "$LEASE_ID" >/dev/null 2>&1 || true
    echo "  Lease liberado."
fi
exit "$rc"
