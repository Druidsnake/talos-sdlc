#!/bin/sh
# thalos.adapter.github_ci - implementacion productiva de CIAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   THALOS_RUN_ID, THALOS_FEATURE_ID, THALOS_GH_BIN, THALOS_DRY_RUN
# Sale:  0 ok / 2 precondition fallida / 5 error de adapter
#
# Este adapter es la AUTORIDAD sobre el pase de pruebas (regla 30.4.1). Ningun
# rol agente puede declarar pass sin su CheckRunSet (30.4.2), y un
# LocalTestReport no lo reemplaza porque es evidencia de avance, no de pase
# (30.4.3).
#
# Su salida es verificable porque sale de CI y puede revalidarse consultando la
# fuente (regla 23.3.4): el CheckRunSet lleva el sha y las urls de cada check.

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"
. "$DIR/../lib/semver.sh"

REQUIRED_RANGE=">=2.0.0"

op="${1:-}"
args="${2:-{\}}"
run="${THALOS_RUN_ID:-r-unknown}"
feat="${THALOS_FEATURE_ID:-none}"

DRY="${THALOS_DRY_RUN:-0}"
# shellcheck disable=SC2034
THALOS_ADAPTER_SIMULATED="$DRY"

resolve_gh() {
    if [ -n "${THALOS_GH_BIN:-}" ] && [ -x "${THALOS_GH_BIN}" ]; then
        printf '%s' "$THALOS_GH_BIN"; return 0
    fi
    _vendored="${THALOS_PROJECT_ROOT:-.}/.thalos/bin/gh"
    [ -x "$_vendored" ] && { printf '%s' "$_vendored"; return 0; }
    command -v gh 2>/dev/null && return 0
    return 1
}

GH=$(resolve_gh) || {
    printf '{"status":"error","error_class":"precondition",' >&2
    printf '"message":"gh no esta instalado","required":"%s",' >&2 "$REQUIRED_RANGE"
    printf '"resolution_order":["$THALOS_GH_BIN",".thalos/bin/gh","PATH"],' >&2
    printf '"install_hint":"brew install gh && gh auth login"}\n' >&2
    exit 2
}

check_version() {
    _v=$("$GH" --version 2>/dev/null | head -1 | sed 's/[^0-9]*\([0-9][0-9.]*\).*/\1/')
    [ -n "$_v" ] || { thalos_error precondition "no se pudo leer la version de $GH"; return 2; }
    if ! thalos_semver_satisfies "$_v" "$REQUIRED_RANGE"; then
        printf '{"status":"error","error_class":"precondition",' >&2
        printf '"message":"gh %s no satisface %s","path":"%s"}\n' >&2 "$_v" "$REQUIRED_RANGE" "$GH"
        return 2
    fi
    printf '%s' "$_v"
}

gh_do() {
    if [ "$DRY" = 1 ]; then
        thalos_ledger_record "dryrun-$(date -u +%s)-$$" "ci:$1" "{\"intended\":\"$*\"}"
        printf '{"dry_run":true,"intended":"%s"}' "$*"
        return 0
    fi
    "$GH" "$@" 2>&1
}

json_get() {
    printf '%s' "$args" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

case "$op" in
    health)
        _v=$(check_version) || exit 2
        if [ "$DRY" = 1 ]; then
            thalos_ok "{\"healthy\":true,\"capability\":\"CIAdapter\",\"version\":\"$_v\",\"path\":\"$GH\",\"dry_run\":true}"
        elif ! "$GH" auth status >/dev/null 2>&1; then
            printf '{"status":"error","error_class":"auth","message":"gh sin autenticar","hint":"gh auth login"}\n' >&2
            exit 2
        elif _repo=$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null); then
            thalos_ok "{\"healthy\":true,\"capability\":\"CIAdapter\",\"version\":\"$_v\",\"path\":\"$GH\",\"repo\":\"$_repo\"}"
        else
            printf '{"status":"error","error_class":"precondition","message":"el directorio no es un repo de GitHub"}\n' >&2
            exit 2
        fi
        ;;

    run_checks)
        check_version >/dev/null || exit 2
        _wf=$(json_get workflow); _ref=$(json_get ref)
        [ -n "$_wf" ] || { thalos_error precondition "run_checks requiere workflow"; exit 5; }
        # shellcheck disable=SC2086
        thalos_mutate_run "$op" "$run" "$feat" "$args" workflow \
            gh_do workflow run "$_wf" ${_ref:+--ref} ${_ref:+"$_ref"}
        ;;

    get_check_status)
        check_version >/dev/null || exit 2
        _pr=$(json_get pr)
        [ -n "$_pr" ] || { thalos_error precondition "get_check_status requiere pr"; exit 5; }

        if [ "$DRY" = 1 ]; then
            # Regla 37.4.4.2: en dry-run nada de esto es evidencia verificable,
            # y un CheckRunSet no verificable no puede satisfacer CHECKS_GATE.
            thalos_ok "{\"pr\":\"$_pr\",\"check_runs\":[],\"conclusion\":\"simulated\",\"verifiable\":false}"
            exit 0
        fi

        _raw=$("$GH" pr checks "$_pr" --json name,state,link 2>/dev/null || printf '[]')
        case "$_raw" in
            \[*) : ;;
            *)   _raw='[]' ;;
        esac

        # El veredicto sale de contar, no de interpretar. Un check en cualquier
        # estado que no sea SUCCESS impide declarar pass: el default es negar.
        _total=$(printf '%s' "$_raw" | tr '}' '\n' | grep -c '"name"' || true)
        _ok=$(printf '%s' "$_raw" | tr '}' '\n' | grep -c '"state":"SUCCESS"' || true)
        _pend=$(printf '%s' "$_raw" | tr '}' '\n' | grep -cE '"state":"(PENDING|QUEUED|IN_PROGRESS)"' || true)

        if [ "$_total" -eq 0 ]; then
            _concl=no_checks
        elif [ "$_pend" -gt 0 ]; then
            _concl=pending
        elif [ "$_ok" -eq "$_total" ]; then
            _concl=pass
        else
            _concl=fail
        fi

        _sha=$("$GH" pr view "$_pr" --json headRefOid --jq .headRefOid 2>/dev/null || printf '')
        thalos_ok "{\"pr\":\"$_pr\",\"head_sha\":\"$_sha\",\"total\":$_total,\"passed\":$_ok,\"pending\":$_pend,\"conclusion\":\"$_concl\",\"verifiable\":true,\"check_runs\":$_raw}"
        ;;

    publish_report)
        check_version >/dev/null || exit 2
        _pr=$(json_get pr); _body=$(json_get body)
        [ -n "$_pr" ] || { thalos_error precondition "publish_report requiere pr"; exit 5; }
        thalos_mutate_run "$op" "$run" "$feat" "$args" pr \
            gh_do pr comment "$_pr" --body "${_body:-Reporte de Thalos para $feat}"
        ;;

    "")
        thalos_error precondition "falta la operacion"
        ;;
    *)
        thalos_unknown_op "$op"
        ;;
esac
