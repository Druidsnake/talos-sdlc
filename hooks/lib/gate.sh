#!/bin/sh
# GateEvaluator: funcion pura de (evidencia, policy, config).
#
# Reglas 24.4.1 a 24.4.3: no hace efectos externos y NO invoca modelos. Un gate
# que llama a un modelo no es un gate, es una opinion.
#
# Regla 24.4.8: determinista. La misma entrada produce la misma salida, asi que
# no se usa el reloj mas que para el sello evaluated_at.
#
# Uso:  . hooks/lib/gate.sh
#       talos_gate_eval <maquina> <desde> <hacia> <dir-evidencia> [run_id] [feature_id]

_gate_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_gate_lib_dir" in
    */lib) TALOS_GATE_SYS=$(dirname "$(dirname "$_gate_lib_dir")") ;;
    *)     TALOS_GATE_SYS="${TALOS_SYSTEM_ROOT:-$_gate_lib_dir}" ;;
esac
[ -n "${TALOS_SYSTEM_ROOT:-}" ] && TALOS_GATE_SYS="$TALOS_SYSTEM_ROOT"

# shellcheck source=./state-machine.sh
. "$TALOS_GATE_SYS/hooks/lib/state-machine.sh"

# Gates que exigen aprobacion humana explicita. Regla 24.4.6: needs_human
# transiciona a un estado de espera, nunca a uno de avance.
TALOS_HUMAN_GATES="HUMAN_GATE"

# Gates criticos: una evidencia con verifiable:false no puede satisfacerlos
# (regla 23.3.5).
TALOS_CRITICAL_GATES="MERGE_GATE POLICY_GATE POST_MERGE_GATE CHECKS_GATE"

_gate_is_in() {
    _needle="$1"; shift
    # Quien llama pasa la lista sin comillas a proposito, para que el shell la
    # separe en palabras antes de entrar. Aca ya son argumentos: "$@" recorre
    # exactamente esos, sin volver a partir nada.
    for _x in "$@"; do
        [ "$_x" = "$_needle" ] && return 0
    done
    return 1
}

# La evidencia NO se lee con sed ni grep.
#
# Un payload que contenga la clave "kind" hace que una expresion de linea
# agarre el valor equivocado, y ahi una evidencia se hace pasar por otra:
# exactamente el ataque que el modelo de evidencia existe para impedir. Todo
# el parseo va por hooks/lib/evidence.py, que ademas verifica el digest.
#
# Salida de evidence.py read:  <kind>\t<verifiable>\t<digest_ok>\t<id>

# Interprete disponible. Sin python no hay lectura de evidencia, y sin lectura
# de evidencia no hay gate que pueda autorizar nada.
talos_python() {
    if [ -x "${TALOS_PROJECT_ROOT:-.}/.venv/bin/python" ]; then
        printf '%s' "${TALOS_PROJECT_ROOT:-.}/.venv/bin/python"
        return 0
    fi
    if [ -x "$TALOS_GATE_SYS/.venv/bin/python" ]; then
        printf '%s' "$TALOS_GATE_SYS/.venv/bin/python"
        return 0
    fi
    command -v python3 2>/dev/null && return 0
    return 1
}

talos_evidence_read() {
    [ -d "$1" ] || return 0
    _py=$(talos_python) || return 0
    "$_py" "$TALOS_GATE_SYS/hooks/lib/evidence.py" read "$1" 2>/dev/null
    return 0
}

# talos_evidence_kinds <dir>
# Solo cuenta como presente la evidencia con digest valido: una evidencia cuyo
# digest no cuadra esta rota, y una evidencia rota no justifica una transicion
# (reglas 23.3.3 y 23.3.4).
talos_evidence_kinds() {
    talos_evidence_read "$1" | awk -F'\t' '$3 == "true" { print $1 }'
}

# talos_evidence_unverifiable <dir>
# Los kind marcados verifiable:false.
talos_evidence_unverifiable() {
    talos_evidence_read "$1" | awk -F'\t' '$2 == "false" { print $1 }'
}

# talos_evidence_tampered <dir>
# Presente pero con digest invalido. Se reporta aparte para que el gate no diga
# "falta" cuando lo cierto es "esta y no se puede confiar".
talos_evidence_tampered() {
    talos_evidence_read "$1" | awk -F'\t' '$3 == "false" { print $1 }'
}

# talos_gate_eval <maquina> <desde> <hacia> <dir-evidencia> [run_id] [feature_id]
#
# Emite un GateResult que valida contra gate-result.schema.json.
# Sale 0 si pass, 3 si fail, 4 si needs_human.
talos_gate_eval() {
    _m="$1"; _from="$2"; _to="$3"; _evdir="$4"
    _run="${5:-${TALOS_RUN_ID:-r-unknown}}"
    _feat="${6:-${TALOS_FEATURE_ID:-}}"

    # Regla 22.6.1: sin transicion en la tabla no hay nada que evaluar.
    if ! talos_transition_allowed "$_m" "$_from" "$_to"; then
        _gate_emit "-" "$_run" "$_feat" "$_from" "$_to" fail \
            '{"code":"TRANSITION_NOT_DEFINED","status":"fail","detail":"no existe en la tabla 22.4/22.5"}' \
            ""
        return 3
    fi

    _gate=$(talos_transition_gate "$_m" "$_from" "$_to")
    _requires=$(talos_transition_requires "$_m" "$_from" "$_to")
    _cond=$(talos_transition_condition "$_m" "$_from" "$_to")

    _present=$(talos_evidence_kinds "$_evdir" | sort -u | tr '\n' ' ')
    _unverifiable=$(talos_evidence_unverifiable "$_evdir" | sort -u | tr '\n' ' ')
    _tampered=$(talos_evidence_tampered "$_evdir" | sort -u | tr '\n' ' ')

    _reasons=""
    _missing=""
    _decision=pass

    # Regla 22.6.3 y 22.6.4: la evidencia se presenta ANTES de evaluar el gate;
    # si falta, el gate resuelve fail con missing_evidence poblado.
    if [ "$_requires" != "-" ]; then
        _old_ifs="$IFS"; IFS=','
        for _kind in $_requires; do
            IFS="$_old_ifs"
            if _gate_is_in "$_kind" $_present; then
                _reasons="$_reasons{\"code\":\"EVIDENCE_PRESENT\",\"status\":\"pass\",\"detail\":\"$_kind\"},"
                # Regla 23.3.5: no verificable no satisface un gate critico.
                if _gate_is_in "$_gate" $TALOS_CRITICAL_GATES && _gate_is_in "$_kind" $_unverifiable; then
                    _reasons="$_reasons{\"code\":\"EVIDENCE_NOT_VERIFIABLE\",\"status\":\"fail\",\"detail\":\"$_kind no puede satisfacer $_gate\"},"
                    _decision=fail
                fi
            elif _gate_is_in "$_kind" $_tampered; then
                # Presente pero con digest roto. Decirlo distinto de "falta"
                # importa: quien lee el reporte tiene que saber que alguien
                # produjo esa evidencia y no cierra.
                _reasons="$_reasons{\"code\":\"EVIDENCE_DIGEST_MISMATCH\",\"status\":\"fail\",\"detail\":\"$_kind no coincide con su digest\"},"
                _missing="$_missing\"$_kind\","
                _decision=fail
            else
                _reasons="$_reasons{\"code\":\"EVIDENCE_MISSING\",\"status\":\"fail\",\"detail\":\"$_kind\"},"
                _missing="$_missing\"$_kind\","
                _decision=fail
            fi
            IFS=','
        done
        IFS="$_old_ifs"
    else
        _reasons="{\"code\":\"NO_EVIDENCE_REQUIRED\",\"status\":\"pass\",\"detail\":\"-\"},"
    fi

    # Regla 24.4.6: un gate humano no decide por su cuenta que se avanza.
    #
    # Pero "no decide por su cuenta" no es "ignora la decision ya tomada". Si la
    # transicion exige HumanDecision o HumanApproval y esa evidencia esta
    # presente, la persona YA decidio: volver a pedirla dejaria esas
    # transiciones fuera de alcance para siempre.
    #
    # needs_human es para cuando falta la decision, no para cuando sobra.
    if [ "$_decision" = pass ] && _gate_is_in "$_gate" $TALOS_HUMAN_GATES; then
        case "$_requires" in
            *Human*)
                _reasons="$_reasons{\"code\":\"HUMAN_DECIDED\",\"status\":\"pass\",\"detail\":\"decision humana presente\"},"
                ;;
            *)
                _decision=needs_human
                _reasons="$_reasons{\"code\":\"HUMAN_REQUIRED\",\"status\":\"skip\",\"detail\":\"$_gate espera una decision humana\"},"
                ;;
        esac
    fi

    # Regla 37.4.4.3: dry-run-only no puede alcanzar FEATURE_MERGED.
    if [ "$_to" = "FEATURE_MERGED" ] && [ "$(talos_execution_mode)" = "dry-run-only" ]; then
        _decision=fail
        _reasons="$_reasons{\"code\":\"MODE_FORBIDS_MERGE\",\"status\":\"fail\",\"detail\":\"dry-run-only no alcanza FEATURE_MERGED\"},"
    fi

    [ "$_cond" != "-" ] && _reasons="$_reasons{\"code\":\"CONDITION_DECLARED\",\"status\":\"skip\",\"detail\":\"$_cond\"},"

    _gate_emit "$_gate" "$_run" "$_feat" "$_from" "$_to" "$_decision" \
        "${_reasons%,}" "${_missing%,}"

    case "$_decision" in
        pass)        return 0 ;;
        needs_human) return 4 ;;
        *)           return 3 ;;
    esac
}

# talos_gate_persist <gate-result-json> <dir-evidencia> [run_id] [feature_id]
#
# Regla 24.4.7: todo GateResult DEBE persistirse como evidencia. Sin esto la
# regla 22.6.6 -toda transicion registra el GateResult que la autorizo- no se
# puede cumplir: la decision se perderia al cerrar la terminal.
#
# Imprime la ruta escrita.
talos_gate_persist() {
    _res="$1"; _dir="$2"
    _run="${3:-${TALOS_RUN_ID:-r-unknown}}"
    _feat="${4:-${TALOS_FEATURE_ID:-}}"

    _py=$(talos_python) || return 1
    mkdir -p "$_dir" || return 1

    # El id solo admite alfanumericos y guiones (evidence.schema.json).
    _slug=$(printf '%s' "$_res" | sed -n 's/.*"gate":"\([A-Z_]*\)".*/\1/p' | tr 'A-Z_' 'a-z-')
    [ -z "$_slug" ] && _slug="sin-gate"
    _stamp=$(date -u +%Y%m%d%H%M%S)
    _n=0
    while [ -e "$_dir/ev-gate-$_slug-$_stamp-$_n.json" ]; do
        _n=$((_n + 1))
    done
    _out="$_dir/ev-gate-$_slug-$_stamp-$_n.json"

    _feat_json=null
    [ -n "$_feat" ] && _feat_json="\"$_feat\""

    # El GateResult va como payload de un envoltorio Evidence (seccion 23.2).
    printf '{"id":"ev-gate-%s-%s-%s","kind":"GateResult","schema_version":1,' \
        "$_slug" "$_stamp" "$_n" >"$_out"
    printf '"run_id":"%s","feature_id":%s,"produced_by":"core:GateEvaluator",' \
        "$_run" "$_feat_json" >>"$_out"
    printf '"produced_at":"%s","digest":"pendiente","verifiable":true,"payload":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_res" >>"$_out"

    "$_py" "$TALOS_GATE_SYS/hooks/lib/evidence.py" seal "$_out" >/dev/null 2>&1 || {
        rm -f "$_out"
        return 1
    }

    # Regla 23.3.2: la evidencia es inmutable una vez escrita. Solo lectura no
    # detiene a root, pero convierte un pisado accidental en un error visible.
    chmod 444 "$_out" 2>/dev/null || true

    printf '%s\n' "$_out"
}

talos_execution_mode() {
    grep -E '^execution_mode:' "$TALOS_GATE_SYS/config/system.yaml" 2>/dev/null \
        | head -1 | sed 's/execution_mode:[[:space:]]*//' | tr -d '"'
}

_gate_emit() {
    _g="$1"; _r="$2"; _f="$3"; _fr="$4"; _t="$5"; _d="$6"; _rs="$7"; _ms="$8"
    _feat_json="null"
    [ -n "$_f" ] && _feat_json="\"$_f\""
    _gate_json="null"
    [ "$_g" != "-" ] && _gate_json="\"$_g\""

    # gate-result.schema.json exige gate del enum; una transicion sin gate no
    # produce GateResult persistible, se reporta con gate ausente.
    printf '{'
    [ "$_gate_json" != null ] && printf '"gate":%s,' "$_gate_json"
    printf '"run_id":"%s","feature_id":%s,"from_state":"%s","to_state":"%s",' \
        "$_r" "$_feat_json" "$_fr" "$_t"
    printf '"decision":"%s","reasons":[%s],"missing_evidence":[%s],' "$_d" "$_rs" "$_ms"
    printf '"execution_mode":"%s","evaluated_at":"%s","evaluator_version":"%s"}\n' \
        "$(talos_execution_mode)" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "${TALOS_VERSION:-0.0.6}"
}
