#!/bin/sh
# Ejecutor de transiciones. Ver talos-0.0.6.md seccion 22.6.
#
# Hasta ahora Talos sabia EVALUAR una transicion pero nada la EJECUTABA: el
# gate decidia y la decision se perdia. Este es el unico lugar que hace avanzar
# el estado, y solo lo hace cuando el gate lo autoriza.
#
# Cumple, en este orden:
#   22.6.3  la evidencia se presenta antes de evaluar el gate
#   22.6.6  la transicion registra el GateResult que la autorizo
#   22.6.5  la transicion emite exactamente un evento
#   22.6.2  una transicion no listada se rechaza y emite talos.transition.rejected
#   22.6.7  todo queda reconstruible desde el event log
#   22.6.8  al llegar a un estado terminal se liberan los leases de la feature
#
# Uso:  . hooks/lib/transition.sh
#       talos_transition_exec <maquina> <desde> <hacia> <dir-evidencia> [feature]

_tr_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_tr_lib_dir" in
    */lib) TALOS_TR_SYS=$(dirname "$(dirname "$_tr_lib_dir")") ;;
    *)     TALOS_TR_SYS="${TALOS_SYSTEM_ROOT:-$_tr_lib_dir}" ;;
esac
[ -n "${TALOS_SYSTEM_ROOT:-}" ] && TALOS_TR_SYS="$TALOS_SYSTEM_ROOT"

# shellcheck source=./gate.sh
. "$TALOS_TR_SYS/hooks/lib/gate.sh"

TALOS_LOCKS="${TALOS_LOCKS_FILE:-orchestration/locks.json}"

# talos_feature_state <feature>  -> estado actual, o vacio si no existe
talos_feature_state() {
    _sf="orchestration/features/$1/state.json"
    [ -f "$_sf" ] || return 1
    sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([A-Z_]*\)".*/\1/p' "$_sf" | head -1
}

# talos_feature_write <feature> <estado> <gate-result-ref> [seq]
# Proyeccion del event log, no fuente de verdad (seccion 41).
talos_feature_write() {
    _f="$1"; _st="$2"; _gr="${3:-}"; _seq="${4:-0}"
    _dir="orchestration/features/$_f"
    mkdir -p "$_dir"

    _issue=null; _branch=null; _leases=""
    if [ -f "$_dir/state.json" ]; then
        _issue=$(sed -n 's/.*"issue_ref"[[:space:]]*:[[:space:]]*\("[^"]*"\|null\).*/\1/p' "$_dir/state.json" | head -1)
        _branch=$(sed -n 's/.*"branch_ref"[[:space:]]*:[[:space:]]*\("[^"]*"\|null\).*/\1/p' "$_dir/state.json" | head -1)
        [ -z "$_issue" ] && _issue=null
        [ -z "$_branch" ] && _branch=null
    fi
    [ -n "${TALOS_ISSUE_REF:-}" ] && _issue="\"$TALOS_ISSUE_REF\""
    [ -n "${TALOS_BRANCH_REF:-}" ] && _branch="\"$TALOS_BRANCH_REF\""
    [ -n "${TALOS_LEASE_ID:-}" ] && _leases="\"$TALOS_LEASE_ID\""

    _gr_json=null
    [ -n "$_gr" ] && _gr_json="\"$_gr\""

    cat >"$_dir/state.json" <<EOF
{
  "schema_version": 1,
  "feature_id": "$_f",
  "run_id": "${TALOS_RUN_ID:-r-unknown}",
  "state": "$_st",
  "issue_ref": $_issue,
  "branch_ref": $_branch,
  "pr_ref": null,
  "leases": [$_leases],
  "last_gate_result": $_gr_json,
  "last_event_seq": $_seq,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# talos_mint_lock_release <feature> <lease_id>
# Un lease liberado tiene que dejar constancia: la tabla 22.5 exige LockRelease
# como evidencia de F27, y una evidencia que nadie produce vuelve la transicion
# inalcanzable.
talos_mint_lock_release() {
    _py=$(talos_python) || return 1
    _ev="orchestration/evidence/ev-$1-lockrelease-$(date -u +%Y%m%d%H%M%S)"
    mkdir -p orchestration/evidence
    cat >"$_ev.json" <<EOF
{"id":"$(basename "$_ev")","kind":"LockRelease","schema_version":1,
 "run_id":"${TALOS_RUN_ID:-r-unknown}","feature_id":"$1",
 "produced_by":"core:LockManager","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "digest":"pendiente","verifiable":true,"payload":{"lease_id":"$2"}}
EOF
    "$_py" "$TALOS_TR_SYS/hooks/lib/evidence.py" seal "$_ev.json" >/dev/null 2>&1
    printf '%s' "$_ev.json"
}

# talos_release_feature_leases <feature>
# Regla 22.6.8: al alcanzar un estado terminal se liberan todos los leases.
talos_release_feature_leases() {
    _py=$(talos_python) || return 0
    [ -f "$TALOS_LOCKS" ] || return 0
    "$_py" "$TALOS_TR_SYS/hooks/lib/lock.py" list "$TALOS_LOCKS" 2>/dev/null \
        | awk -F'\t' -v f="$1" '$3 == f { print $1 }' \
        | while read -r _lid; do
            [ -z "$_lid" ] && continue
            "$_py" "$TALOS_TR_SYS/hooks/lib/lock.py" release "$TALOS_LOCKS" "$_lid" >/dev/null 2>&1
            talos_mint_lock_release "$1" "$_lid" >/dev/null 2>&1 || true
            printf '%s\n' "$_lid"
        done
}

# talos_transition_exec <maquina> <desde> <hacia> <dir-evidencia> [feature]
#
# Sale 0 ejecutada, 3 gate rechazo, 4 needs_human.
# Imprime lineas <clave>=<valor> para que quien llama las lea sin parsear JSON.
talos_transition_exec() {
    _m="$1"; _from="$2"; _to="$3"; _evdir="$4"; _feat="${5:-}"

    _cli="$TALOS_TR_SYS/cli/talos"
    _event=$(talos_transition_event "$_m" "$_from" "$_to" 2>/dev/null || echo "")
    _actor=$(talos_transition_actor "$_m" "$_from" "$_to" 2>/dev/null || echo "Orchestrator")

    set +e
    _result=$(talos_gate_eval "$_m" "$_from" "$_to" "$_evdir" "${TALOS_RUN_ID:-}" "$_feat")
    _code=$?
    set -e

    # Regla 22.6.6: el GateResult que autoriza -o rechaza- queda registrado.
    _saved=$(talos_gate_persist "$_result" "orchestration/evidence" \
                "${TALOS_RUN_ID:-}" "$_feat" 2>/dev/null || true)
    _ev_id=$(basename "${_saved:-}" .json)

    echo "gate_result=${_saved:-}"

    if [ "$_code" -ne 0 ]; then
        # Regla 22.6.2: una transicion no autorizada emite transition.rejected.
        # El rechazo tambien es historia: sin el, el log miente por omision.
        _rej_args="--type talos.transition.rejected --actor core:GateEvaluator"
        [ -n "$_feat" ] && _rej_args="$_rej_args --feature $_feat"
        [ -n "$_ev_id" ] && _rej_args="$_rej_args --evidence $_ev_id"
        # shellcheck disable=SC2086
        "$_cli" event append $_rej_args >/dev/null 2>&1 || true
        echo "decision=$([ "$_code" -eq 4 ] && echo needs_human || echo fail)"
        echo "event=talos.transition.rejected"
        return "$_code"
    fi

    # Regla 22.6.5: exactamente un evento de estado por transicion.
    _seq=0
    if [ -n "$_event" ] && [ "$_event" != "-" ]; then
        _args="--type $_event --actor role:$_actor"
        [ -n "$_feat" ] && _args="$_args --feature $_feat"
        [ -n "$_ev_id" ] && _args="$_args --evidence $_ev_id"
        # shellcheck disable=SC2086
        _out=$("$_cli" event append $_args 2>&1) || {
            echo "decision=fail"
            echo "error=no se pudo registrar el evento: $_out"
            return 5
        }
        _seq=$(printf '%s' "$_out" | sed -n 's/.*seq[= ]*\([0-9][0-9]*\).*/\1/p' | head -1)
        [ -z "$_seq" ] && _seq=0
    fi

    # El estado se escribe DESPUES del evento: el event log es la fuente de
    # verdad y state.json su proyeccion (seccion 41). Si se cayera en el medio,
    # la proyeccion se reconstruye; al reves se perderia el hecho.
    if [ "$_m" = feature ] && [ -n "$_feat" ]; then
        talos_feature_write "$_feat" "$_to" "$_ev_id" "$_seq"
        if talos_is_terminal feature "$_to"; then
            talos_release_feature_leases "$_feat" | while read -r _l; do
                [ -n "$_l" ] && echo "lease_released=$_l"
            done
        fi
    fi

    echo "decision=pass"
    echo "event=$_event"
    echo "seq=$_seq"
    return 0
}
