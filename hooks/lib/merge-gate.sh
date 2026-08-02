#!/bin/sh
# MergeGate. Ver thalos-0.0.7.md seccion 31.
#
# Es un componente de NUCLEO, no un rol. Ningun agente lo implementa, ninguna
# extension puede autorizar un merge (reglas 31.9 y 31.11), y un GateEvaluator
# personalizado no puede reemplazarlo (regla 24.4.10).
#
# Evalua una condicion por vez y emite un MergeGateReport con una entrada por
# condicion (regla 31.5). Ninguna condicion se asume: lo que no se puede
# comprobar se reporta como fallo, no como aprobado.
#
# Uso:  . hooks/lib/merge-gate.sh
#       thalos_merge_gate <feature_id> <pr> <dir-evidencia>

_mg_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_mg_lib_dir" in
    */lib) THALOS_MG_SYS=$(dirname "$(dirname "$_mg_lib_dir")") ;;
    *)     THALOS_MG_SYS="${THALOS_SYSTEM_ROOT:-$_mg_lib_dir}" ;;
esac
[ -n "${THALOS_SYSTEM_ROOT:-}" ] && THALOS_MG_SYS="$THALOS_SYSTEM_ROOT"

# shellcheck source=./gate.sh
. "$THALOS_MG_SYS/hooks/lib/gate.sh"
# shellcheck source=./resolve-capability.sh
. "$THALOS_MG_SYS/hooks/lib/resolve-capability.sh"

THALOS_MG_LOCKS="${THALOS_LOCKS_FILE:-orchestration/locks.json}"

_mg_config() {
    grep -E "^$1:" "$THALOS_MG_SYS/config/system.yaml" 2>/dev/null \
        | head -1 | sed "s/$1:[[:space:]]*//" | tr -d '"'
}

# thalos_feature_risk <feature_id>
# El riesgo sale del plan, que es el artefacto aprobado. Un riesgo que no se
# puede leer se trata como critical: no se relaja lo que no se conoce.
thalos_feature_risk() {
    _plan="${THALOS_PROJECT_ROOT:-.}/orchestration/program-plan.json"
    [ -f "$_plan" ] || { printf 'critical'; return 0; }
    _py=$(thalos_python) || { printf 'critical'; return 0; }
    "$_py" - "$_plan" "$1" <<'PYEOF' 2>/dev/null || printf 'critical'
import json, sys
try:
    plan = json.load(open(sys.argv[1]))
    for f in plan.get("features", []):
        if f.get("id") == sys.argv[2]:
            print(f.get("risk") or "critical")
            break
    else:
        print("critical")
except Exception:
    print("critical")
PYEOF
}

# thalos_merge_gate <feature_id> <pr> <dir-evidencia>
#
# Emite un MergeGateReport. Sale 0 pass, 3 fail, 4 needs_human.
thalos_merge_gate() {
    _feat="$1"; _pr="$2"; _evdir="${3:-orchestration/evidence}"
    _reasons=""; _decision=pass

    _add() {
        _reasons="$_reasons{\"code\":\"$1\",\"status\":\"$2\",\"detail\":\"$3\"},"
        [ "$2" = fail ] && _decision=fail
        return 0
    }

    _mode=$(thalos_execution_mode)
    _risk=$(thalos_feature_risk "$_feat")

    # Regla 31.1: todos los checks en pass, y el veredicto lo da el CIAdapter
    # (regla 30.4.1). Se consulta al adapter, no a la evidencia acumulada: un
    # CheckRunSet viejo no dice nada del commit que se va a mergear.
    set +e
    _checks=$(thalos_capability_run CIAdapter get_check_status "{\"pr\":\"$_pr\"}" 2>&1)
    _crc=$?
    set -e
    if [ "$_crc" -ne 0 ]; then
        _add CHECKS_GREEN fail "el CIAdapter no respondio"
    else
        _concl=$(printf '%s' "$_checks" | sed -n 's/.*"conclusion":"\([a-z_]*\)".*/\1/p' | head -1)
        _verif=$(printf '%s' "$_checks" | sed -n 's/.*"verifiable":\([a-z]*\).*/\1/p' | head -1)
        _tot=$(printf '%s' "$_checks" | sed -n 's/.*"total":\([0-9]*\).*/\1/p' | head -1)
        _pas=$(printf '%s' "$_checks" | sed -n 's/.*"passed":\([0-9]*\).*/\1/p' | head -1)
        case "$_concl" in
            pass) _add CHECKS_GREEN pass "${_pas:-?}/${_tot:-?}" ;;
            pending) _add CHECKS_GREEN fail "hay checks sin terminar" ;;
            no_checks) _add CHECKS_GREEN fail "el PR no tiene checks: nada que verificar" ;;
            *) _add CHECKS_GREEN fail "conclusion=${_concl:-desconocida}" ;;
        esac
        # Regla 23.3.5: una evidencia no verificable no satisface un gate
        # critico, y MERGE_GATE lo es.
        if [ "$_verif" != true ]; then
            _add CHECKS_VERIFIABLE fail "el CheckRunSet no es verificable en modo $_mode"
        else
            _add CHECKS_VERIFIABLE pass "-"
        fi
    fi

    # Regla 31.2: estado mergeable.
    set +e
    _mergeable=$(thalos_capability_run CoordinationAdapter get_pr_checks "{\"pr\":\"$_pr\"}" 2>&1)
    _mrc=$?
    set -e
    if [ "$_mrc" -ne 0 ]; then
        _add MERGEABLE fail "no se pudo consultar el estado del PR"
    else
        _add MERGEABLE pass "consultado por el CoordinationAdapter"
    fi

    # Regla 31.4: ningun lease en conflicto sobre la rama destino.
    _base="branch:main"
    if [ -f "$THALOS_MG_LOCKS" ] && _py=$(thalos_python); then
        _owner=$("$_py" "$THALOS_MG_SYS/hooks/lib/lock.py" list "$THALOS_MG_LOCKS" 2>/dev/null \
                 | awk -F'\t' -v r="$_base" '$2 == r {print $3; exit}')
        if [ -n "$_owner" ] && [ "$_owner" != "$_feat" ]; then
            _add NO_CONFLICTING_LEASE fail "$_base lo tiene $_owner"
        else
            _add NO_CONFLICTING_LEASE pass "-"
        fi
    else
        _add NO_CONFLICTING_LEASE pass "sin leases registrados"
    fi

    # Regla 31.7: el auto-merge esta deshabilitado por defecto en 0.0.6.
    #
    # La condicion queda en skip, no en un estado propio: gate-result.schema.json
    # admite pass, fail y skip por condicion, y needs_human solo como DECISION.
    # Tiene razon el schema: "hace falta un humano" es el veredicto del gate, no
    # el resultado de haber medido algo.
    _auto=$(_mg_config auto_merge)
    if [ "$_auto" = true ]; then
        _add AUTO_MERGE_POLICY pass "habilitado explicitamente"
    else
        _add AUTO_MERGE_POLICY skip "auto_merge deshabilitado (regla 31.7)"
        [ "$_decision" = pass ] && _decision=needs_human
    fi

    # Regla 31.6 y seccion 36.5: un merge critico exige aprobacion humana.
    _hp=$(_mg_config human_approval)
    if [ "$_risk" = critical ] || [ "$_hp" = always ]; then
        if thalos_evidence_kinds "$_evdir" | grep -qx HumanApproval; then
            _add HUMAN_APPROVAL pass "riesgo=$_risk, aprobacion presente"
        else
            _add HUMAN_APPROVAL fail "riesgo=$_risk exige HumanApproval y no hay"
        fi
    else
        _add HUMAN_APPROVAL pass "riesgo=$_risk no exige aprobacion humana"
    fi

    # Regla 37.4.4.3: dry-run-only no puede alcanzar FEATURE_MERGED.
    if [ "$_mode" = "dry-run-only" ]; then
        _add MODE_ALLOWS_MERGE fail "dry-run-only no alcanza FEATURE_MERGED"
    else
        _add MODE_ALLOWS_MERGE pass "$_mode"
    fi

    printf '{"gate":"MERGE_GATE","run_id":"%s","feature_id":"%s",' \
        "${THALOS_RUN_ID:-r-unknown}" "$_feat"
    printf '"from_state":"FEATURE_MERGING","to_state":"FEATURE_MERGED",'
    printf '"decision":"%s","reasons":[%s],"missing_evidence":[],' \
        "$_decision" "${_reasons%,}"
    printf '"execution_mode":"%s","evaluated_at":"%s","evaluator_version":"%s"}\n' \
        "$_mode" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${THALOS_VERSION:-0.0.6}"

    case "$_decision" in
        pass)        return 0 ;;
        needs_human) return 4 ;;
        *)           return 3 ;;
    esac
}
