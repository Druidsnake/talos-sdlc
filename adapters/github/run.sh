#!/bin/sh
# talos.adapter.github - implementacion productiva de CoordinationAdapter.
#
# Uso:   run.sh <operacion> [semantic_args_json]
# Env:   TALOS_RUN_ID, TALOS_FEATURE_ID   contexto de la idempotency key
#        TALOS_GH_BIN                     primer paso de la cascada (37.4.5)
#        TALOS_DRY_RUN=1                  registra la intencion, no toca el remoto
# Sale:  0 ok / 2 precondition fallida / 5 error de adapter
#
# RECONCILIACION (regla 38.2.6)
#   GitHub no acepta claves de idempotencia. Cuando el backend no la soporta,
#   el adapter DEBE buscar el recurso por su key antes de crearlo. Aca la key
#   viaja incrustada en el cuerpo del issue y del PR, y se busca por ella.
#
#   El ledger local no alcanza: si se pierde, o si otro proceso creo el issue,
#   Talos volveria a crearlo. El remoto es la fuente de verdad de lo que existe
#   en el remoto.

set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/../lib/adapter.sh"
. "$DIR/../lib/semver.sh"

REQUIRED_RANGE=">=2.0.0"

op="${1:-}"
args="${2:-{\}}"
run="${TALOS_RUN_ID:-r-unknown}"
feat="${TALOS_FEATURE_ID:-none}"

DRY="${TALOS_DRY_RUN:-0}"
# shellcheck disable=SC2034
TALOS_ADAPTER_SIMULATED="$DRY"

# ---------- resolucion del binario (seccion 37.4.5) ----------

resolve_gh() {
    if [ -n "${TALOS_GH_BIN:-}" ] && [ -x "${TALOS_GH_BIN}" ]; then
        printf '%s' "$TALOS_GH_BIN"; return 0
    fi
    _vendored="${TALOS_PROJECT_ROOT:-.}/.talos/bin/gh"
    [ -x "$_vendored" ] && { printf '%s' "$_vendored"; return 0; }
    command -v gh 2>/dev/null && return 0
    return 1
}

GH=$(resolve_gh) || {
    printf '{"status":"error","error_class":"precondition",' >&2
    printf '"message":"gh no esta instalado","required":"%s",' >&2 "$REQUIRED_RANGE"
    printf '"resolution_order":["$TALOS_GH_BIN",".talos/bin/gh","PATH"],' >&2
    printf '"install_hint":"brew install gh && gh auth login"}\n' >&2
    exit 2
}

check_version() {
    _v=$("$GH" --version 2>/dev/null | head -1 | sed 's/[^0-9]*\([0-9][0-9.]*\).*/\1/')
    [ -n "$_v" ] || { talos_error precondition "no se pudo leer la version de $GH"; return 2; }
    if ! talos_semver_satisfies "$_v" "$REQUIRED_RANGE"; then
        printf '{"status":"error","error_class":"precondition",' >&2
        printf '"message":"gh %s no satisface %s","path":"%s"}\n' >&2 "$_v" "$REQUIRED_RANGE" "$GH"
        return 2
    fi
    printf '%s' "$_v"
}

gh_do() {
    if [ "$DRY" = 1 ]; then
        talos_ledger_record "dryrun-$(date -u +%s)-$$" "gh:$1" "{\"intended\":\"$*\"}"
        printf '{"dry_run":true,"intended":"%s"}' "$*"
        return 0
    fi
    "$GH" "$@" 2>&1
}

json_get() {
    printf '%s' "$args" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# La marca que hace posible reconciliar. Va en el cuerpo, no en el titulo: el
# titulo lo lee una persona y no tiene por que cargar con esto.
talos_marker() {
    printf '<!-- talos-idempotency-key: %s -->' "$1"
}

# ---------- reconciliacion ----------
#
# busca_issue <key>  -> numero del issue que ya lleva esa key, o vacio
#
# NO se usa --search. El indice de busqueda de GitHub no es inmediatamente
# consistente: un issue creado hace segundos todavia no aparece, y una guarda
# de idempotencia que no ve lo recien creado no sirve para nada -precisamente
# el reintento inmediato es el caso que tiene que cubrir.
#
# Se lista por API, que si es consistente al instante, y se filtra localmente.
# Cuesta mas que una busqueda indexada; duplicar un issue cuesta mas todavia.
TALOS_GH_SCAN="${TALOS_GH_SCAN:-100}"

busca_issue() {
    [ "$DRY" = 1 ] && return 1
    "$GH" issue list --state all --json number,body --limit "$TALOS_GH_SCAN" 2>/dev/null \
        | tr '}' '\n' \
        | grep -F "$1" \
        | sed -n 's/.*"number":\([0-9]*\).*/\1/p' | head -1
}

busca_pr() {
    [ "$DRY" = 1 ] && return 1
    "$GH" pr list --state all --json number,body --limit "$TALOS_GH_SCAN" 2>/dev/null \
        | tr '}' '\n' \
        | grep -F "$1" \
        | sed -n 's/.*"number":\([0-9]*\).*/\1/p' | head -1
}

# emite <status> <id> <url> <key>
emite() {
    printf '{"status":"%s","resource_ref":{"id":"%s","url":"%s"},' "$1" "$2" "$3"
    printf '"idempotency_key":"%s","dry_run":%s}\n' "$4" \
        "$([ "$DRY" = 1 ] && echo true || echo false)"
}

case "$op" in
    health)
        _v=$(check_version) || exit 2
        # Tener gh no alcanza: sin autenticacion y sin repo no hay donde
        # coordinar, y la capacidad no esta satisfecha.
        if [ "$DRY" = 1 ]; then
            talos_ok "{\"healthy\":true,\"capability\":\"CoordinationAdapter\",\"version\":\"$_v\",\"path\":\"$GH\",\"dry_run\":true}"
        elif ! "$GH" auth status >/dev/null 2>&1; then
            printf '{"status":"error","error_class":"auth",' >&2
            printf '"message":"gh %s sin autenticar","hint":"gh auth login"}\n' >&2 "$_v"
            exit 2
        elif _repo=$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null); then
            talos_ok "{\"healthy\":true,\"capability\":\"CoordinationAdapter\",\"version\":\"$_v\",\"path\":\"$GH\",\"repo\":\"$_repo\"}"
        else
            printf '{"status":"error","error_class":"precondition",' >&2
            printf '"message":"gh autenticado pero el directorio no es un repo de GitHub"}\n' >&2
            exit 2
        fi
        ;;

    create_issue)
        check_version >/dev/null || exit 2
        _title=$(json_get title); _body=$(json_get body)
        [ -n "$_title" ] || { talos_error precondition "create_issue requiere title"; exit 5; }
        _key=$(talos_idempotency_key "$run" "$feat" "$op" "$args") || exit 5

        # Reconciliacion antes de crear: el remoto manda sobre el ledger.
        if _n=$(busca_issue "$_key") && [ -n "$_n" ]; then
            emite already_exists "$_n" "$("$GH" issue view "$_n" --json url --jq .url 2>/dev/null)" "$_key"
            exit 0
        fi

        _out=$(gh_do issue create --title "$_title" \
               --body "$(printf '%s\n\n%s' "${_body:-Creado por Talos para $feat}" "$(talos_marker "$_key")")") || {
            printf '{"status":"error","error_class":"adapter","operation":"create_issue","message":%s}\n' \
                "$(printf '%s' "$_out" | talos_json_string)" >&2
            exit 5
        }
        _url=$(printf '%s' "$_out" | grep -o 'https://[^ ]*' | head -1)
        talos_ledger_record "$_key" "$op" "{\"id\":\"$(basename "${_url:-0}")\",\"url\":\"$_url\"}"
        emite created "$(basename "${_url:-0}")" "$_url" "$_key"
        ;;

    create_branch)
        check_version >/dev/null || exit 2
        _name=$(json_get name)
        [ -n "$_name" ] || { talos_error precondition "create_branch requiere name"; exit 5; }
        _key=$(talos_idempotency_key "$run" "$feat" "$op" "$args") || exit 5

        # Una rama ya existente ES el estado deseado: crear de nuevo seria un
        # error y no crear nada seria mentir. already_exists dice la verdad.
        if [ "$DRY" != 1 ] && git show-ref --verify --quiet "refs/heads/$_name"; then
            emite already_exists "$_name" "" "$_key"
            exit 0
        fi
        if [ "$DRY" = 1 ]; then
            talos_ledger_record "$_key" "$op" "{\"id\":\"$_name\",\"url\":null}"
            emite created "$_name" "" "$_key"
            exit 0
        fi
        _out=$(git branch "$_name" 2>&1) || {
            printf '{"status":"error","error_class":"adapter","operation":"create_branch","message":%s}\n' \
                "$(printf '%s' "$_out" | talos_json_string)" >&2
            exit 5
        }
        talos_ledger_record "$_key" "$op" "{\"id\":\"$_name\",\"url\":null}"
        emite created "$_name" "" "$_key"
        ;;

    open_pr)
        check_version >/dev/null || exit 2
        _title=$(json_get title); _head=$(json_get head); _base=$(json_get base)
        [ -n "$_title" ] && [ -n "$_head" ] || {
            talos_error precondition "open_pr requiere title y head"; exit 5; }
        _key=$(talos_idempotency_key "$run" "$feat" "$op" "$args") || exit 5

        if _n=$(busca_pr "$_key") && [ -n "$_n" ]; then
            emite already_exists "$_n" "$("$GH" pr view "$_n" --json url --jq .url 2>/dev/null)" "$_key"
            exit 0
        fi

        _out=$(gh_do pr create --title "$_title" --head "$_head" \
               ${_base:+--base "$_base"} \
               --body "$(printf 'Abierto por Talos para %s\n\n%s' "$feat" "$(talos_marker "$_key")")") || {
            printf '{"status":"error","error_class":"adapter","operation":"open_pr","message":%s}\n' \
                "$(printf '%s' "$_out" | talos_json_string)" >&2
            exit 5
        }
        _url=$(printf '%s' "$_out" | grep -o 'https://[^ ]*' | head -1)
        talos_ledger_record "$_key" "$op" "{\"id\":\"$(basename "${_url:-0}")\",\"url\":\"$_url\"}"
        emite created "$(basename "${_url:-0}")" "$_url" "$_key"
        ;;

    get_pr_checks)
        check_version >/dev/null || exit 2
        _pr=$(json_get pr)
        [ -n "$_pr" ] || { talos_error precondition "get_pr_checks requiere pr"; exit 5; }
        # El CheckRunSet sale del CIAdapter, no de aca (regla 30.4.1). Esto es
        # lo que el coordinador ve del PR, no un veredicto de pase.
        _out=$(gh_do pr checks "$_pr" --json name,state,link 2>/dev/null || printf '[]')
        talos_ok "{\"pr\":\"$_pr\",\"checks\":$(printf '%s' "$_out" | grep -q '^\[' && printf '%s' "$_out" || printf '[]')}"
        ;;

    request_review)
        check_version >/dev/null || exit 2
        _pr=$(json_get pr); _who=$(json_get reviewer)
        [ -n "$_pr" ] || { talos_error precondition "request_review requiere pr"; exit 5; }
        talos_mutate_run "$op" "$run" "$feat" "$args" number \
            gh_do pr edit "$_pr" ${_who:+--add-reviewer} ${_who:+"$_who"}
        ;;

    merge_pr)
        check_version >/dev/null || exit 2
        _pr=$(json_get pr); _method=$(json_get method)
        [ -n "$_pr" ] || { talos_error precondition "merge_pr requiere pr"; exit 5; }
        # Este adapter NO decide si corresponde mergear. MergeGate ya lo
        # autorizo (seccion 31); aca solo se ejecuta.
        talos_mutate_run "$op" "$run" "$feat" "$args" sha \
            gh_do pr merge "$_pr" "--${_method:-squash}"
        ;;

    "")
        talos_error precondition "falta la operacion"
        ;;
    *)
        talos_unknown_op "$op"
        ;;
esac
