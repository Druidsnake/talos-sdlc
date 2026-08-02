#!/bin/sh
# Resolucion y activacion de roles. Ver thalos-0.0.7.md secciones 18 a 21.
#
# Esto es NUCLEO, no adapter. Que rol se despacha y con que instrucciones es
# politica; lanzar el proceso es ciclo de vida (seccion 38.5). Mezclarlos haria
# que cambiar de ExecutionAdapter obligue a reimplementar la politica.
#
# hooks/agent/README.md lo dice: "El rol lo fija Thalos al despachar un agente,
# no lo elige el agente." Este archivo es quien lo fija.
#
# Uso:  . hooks/lib/role.sh
#       thalos_role_exists Developer
#       thalos_role_activate Developer F001
#       thalos_role_brief Developer F001

_role_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_role_lib_dir" in
    */lib) THALOS_ROLE_SYS=$(dirname "$(dirname "$_role_lib_dir")") ;;
    *)     THALOS_ROLE_SYS="${THALOS_SYSTEM_ROOT:-$_role_lib_dir}" ;;
esac
[ -n "${THALOS_SYSTEM_ROOT:-}" ] && THALOS_ROLE_SYS="$THALOS_SYSTEM_ROOT"

THALOS_SCOPE_RULES="${THALOS_SCOPE_RULES:-$THALOS_ROLE_SYS/hooks/generated/write-scope.rules}"

# thalos_role_list
# Los roles que declara el registro de scope. Se lee de las reglas generadas y
# no del YAML: es la misma fuente que usa el bloqueo, asi que un rol que
# aparezca aca es un rol que el mecanismo 2 sabe hacer cumplir.
thalos_role_list() {
    [ -f "$THALOS_SCOPE_RULES" ] || return 1
    grep -v '^#' "$THALOS_SCOPE_RULES" | awk -F'\t' 'NF>1 {print $1}' | sort -u
}

# thalos_role_exists <rol>
thalos_role_exists() {
    thalos_role_list 2>/dev/null | grep -qx "$1"
}

# thalos_role_scope <rol>  -> <allow|deny><TAB><glob>
thalos_role_scope() {
    [ -f "$THALOS_SCOPE_RULES" ] || return 1
    grep -v '^#' "$THALOS_SCOPE_RULES" | awk -F'\t' -v r="$1" '$1 == r {print $2 "\t" $3}'
}

# thalos_role_instructions <rol>  -> ruta del archivo de instrucciones
#
# Convencion: roles/<rol-en-kebab>.md. El YAML lo declara, pero leerlo exigiria
# un parser en el camino caliente.
#
# El kebab NO es cosmetico: pasar el nombre a minuscula a secas da
# "featurelead.md" y el archivo es "feature-lead.md". Con eso, despachar
# FeatureLead o SpecAssistant fallaba con "sin archivo de instrucciones" -los
# dos unicos roles de mas de una palabra-, mientras Developer y Reviewer
# funcionaban. El bug se escondia en que los roles que se probaban a diario
# eran justo los de una sola palabra.
thalos_role_instructions() {
    _kebab=$(printf '%s' "$1" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr 'A-Z' 'a-z')
    for _f in "$THALOS_ROLE_SYS/roles/$_kebab.md" \
              "$THALOS_ROLE_SYS/roles/$(printf '%s' "$1" | tr 'A-Z' 'a-z').md"; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return 0; }
    done
    return 1
}

# thalos_role_activate <rol> [feature_id]
#
# Deja el rol activo para la sesion. check-tool-call.sh lo lee de aca cuando
# no hay $THALOS_ROLE en el entorno, asi que a partir de este punto toda
# escritura del agente pasa por el mecanismo 2.
#
# Sale 2 si el rol no existe: fail-closed. Un rol desconocido no puede quedar
# sin scope, porque sin scope el bloqueo deja pasar todo.
thalos_role_activate() {
    if ! thalos_role_exists "$1"; then
        echo "thalos: rol desconocido: $1" >&2
        echo "thalos: declarados: $(thalos_role_list 2>/dev/null | tr '\n' ' ')" >&2
        return 2
    fi
    mkdir -p "${THALOS_PROJECT_ROOT:-.}/orchestration"
    printf '%s\n' "$1" > "${THALOS_PROJECT_ROOT:-.}/orchestration/.current-role"
    [ -n "${2:-}" ] && printf '%s\n' "$2" > "${THALOS_PROJECT_ROOT:-.}/orchestration/.current-feature"
    return 0
}

# thalos_role_deactivate
# Al terminar, el rol se suelta. Un rol que queda pegado gobierna sesiones que
# Thalos ya no esta despachando.
thalos_role_deactivate() {
    rm -f "${THALOS_PROJECT_ROOT:-.}/orchestration/.current-role" \
          "${THALOS_PROJECT_ROOT:-.}/orchestration/.current-feature"
}

# thalos_role_current
thalos_role_current() {
    _f="${THALOS_PROJECT_ROOT:-.}/orchestration/.current-role"
    [ -f "$_f" ] || return 1
    cat "$_f"
}

# thalos_role_brief <rol> [feature_id]
#
# El texto que se le entrega al agente al despacharlo: sus instrucciones mas
# el alcance concreto de esta corrida. Las instrucciones solas no alcanzan,
# porque el rol no sabe en que feature esta ni que rutas tiene permitidas.
thalos_role_brief() {
    _r="$1"; _f="${2:-}"
    _ins=$(thalos_role_instructions "$_r") || {
        echo "thalos: sin archivo de instrucciones para $_r" >&2
        return 2
    }

    printf 'Thalos te despacha con el rol %s' "$_r"
    [ -n "$_f" ] && printf ' para la feature %s' "$_f"
    printf '.\n\n'

    printf 'ALCANCE DE ESCRITURA (lo fuerza un hook, no tu criterio)\n'
    thalos_role_scope "$_r" | while IFS='	' read -r _verdict _glob; do
        [ -z "$_verdict" ] && continue
        case "$_verdict" in
            allow) printf '  permitido  %s\n' "$_glob" ;;
            deny)  printf '  prohibido  %s\n' "$_glob" ;;
        esac
    done
    printf '\n  deny gana sobre allow. Sin allow que matchee, se deniega.\n'
    printf '  No pidas excepciones: el bloqueo no consulta al agente.\n\n'

    printf -- '--- instrucciones del rol ---\n\n'
    cat "$_ins"
}

# ---------- contrato de salida (evidencia que produce el rol) ----------

THALOS_ROLE_OUTPUT="${THALOS_ROLE_OUTPUT:-$THALOS_ROLE_SYS/hooks/generated/role-output.tsv}"

# thalos_role_output <rol>  -> <schema><TAB><plantilla-de-ruta>
thalos_role_output() {
    [ -f "$THALOS_ROLE_OUTPUT" ] || return 1
    _row=$(grep -v '^#' "$THALOS_ROLE_OUTPUT" | awk -F'\t' -v r="$1" '$1 == r {print $2 "\t" $3; exit}')
    [ -n "$_row" ] || return 1
    printf '%s' "$_row"
}

# thalos_role_output_path <rol> <feature_id> [task_id]
# Resuelve la plantilla. Un {task_id} sin valor queda como comodin para buscar.
thalos_role_output_path() {
    _tpl=$(thalos_role_output "$1" | cut -f2) || return 1
    _p=$(printf '%s' "$_tpl" | sed "s|{feature_id}|$2|g")
    if [ -n "${3:-}" ]; then
        printf '%s' "$_p" | sed "s|{task_id}|$3|g"
    else
        printf '%s' "$_p" | sed "s|{task_id}|*|g"
    fi
}

# thalos_role_output_schema <rol>
thalos_role_output_schema() {
    thalos_role_output "$1" | cut -f1
}

# La evidencia que produce un agente NO es verificable salvo que traiga salida
# de una herramienta determinista (regla 23.3.6). El kind se deduce del schema
# del entregable, no se elige a dedo.
thalos_role_evidence_kind() {
    case "$1" in
        task-result)    printf 'TaskResultSet' ;;
        review)         printf 'Review' ;;
        program-plan)   printf 'ProgramPlan' ;;
        feature-state)  printf 'FeatureStateSet' ;;
        spec-manifest)  printf 'SpecDraft' ;;
        *)              return 1 ;;
    esac
}
