#!/bin/sh
# Resolucion y activacion de roles. Ver talos-0.0.6.md secciones 18 a 21.
#
# Esto es NUCLEO, no adapter. Que rol se despacha y con que instrucciones es
# politica; lanzar el proceso es ciclo de vida (seccion 38.5). Mezclarlos haria
# que cambiar de ExecutionAdapter obligue a reimplementar la politica.
#
# hooks/agent/README.md lo dice: "El rol lo fija Talos al despachar un agente,
# no lo elige el agente." Este archivo es quien lo fija.
#
# Uso:  . hooks/lib/role.sh
#       talos_role_exists Developer
#       talos_role_activate Developer F001
#       talos_role_brief Developer F001

_role_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_role_lib_dir" in
    */lib) TALOS_ROLE_SYS=$(dirname "$(dirname "$_role_lib_dir")") ;;
    *)     TALOS_ROLE_SYS="${TALOS_SYSTEM_ROOT:-$_role_lib_dir}" ;;
esac
[ -n "${TALOS_SYSTEM_ROOT:-}" ] && TALOS_ROLE_SYS="$TALOS_SYSTEM_ROOT"

TALOS_SCOPE_RULES="${TALOS_SCOPE_RULES:-$TALOS_ROLE_SYS/hooks/generated/write-scope.rules}"

# talos_role_list
# Los roles que declara el registro de scope. Se lee de las reglas generadas y
# no del YAML: es la misma fuente que usa el bloqueo, asi que un rol que
# aparezca aca es un rol que el mecanismo 2 sabe hacer cumplir.
talos_role_list() {
    [ -f "$TALOS_SCOPE_RULES" ] || return 1
    grep -v '^#' "$TALOS_SCOPE_RULES" | awk -F'\t' 'NF>1 {print $1}' | sort -u
}

# talos_role_exists <rol>
talos_role_exists() {
    talos_role_list 2>/dev/null | grep -qx "$1"
}

# talos_role_scope <rol>  -> <allow|deny><TAB><glob>
talos_role_scope() {
    [ -f "$TALOS_SCOPE_RULES" ] || return 1
    grep -v '^#' "$TALOS_SCOPE_RULES" | awk -F'\t' -v r="$1" '$1 == r {print $2 "\t" $3}'
}

# talos_role_instructions <rol>  -> ruta del archivo de instrucciones
#
# Convencion: roles/<rol-en-minuscula>.md. El YAML lo declara, pero leerlo
# exigiria un parser en el camino caliente; la convencion la verifica
# tests/test_roles.py, que ya comprueba que config y archivos coincidan.
talos_role_instructions() {
    _f="$TALOS_ROLE_SYS/roles/$(printf '%s' "$1" | tr 'A-Z' 'a-z').md"
    [ -f "$_f" ] || return 1
    printf '%s' "$_f"
}

# talos_role_activate <rol> [feature_id]
#
# Deja el rol activo para la sesion. check-tool-call.sh lo lee de aca cuando
# no hay $TALOS_ROLE en el entorno, asi que a partir de este punto toda
# escritura del agente pasa por el mecanismo 2.
#
# Sale 2 si el rol no existe: fail-closed. Un rol desconocido no puede quedar
# sin scope, porque sin scope el bloqueo deja pasar todo.
talos_role_activate() {
    if ! talos_role_exists "$1"; then
        echo "talos: rol desconocido: $1" >&2
        echo "talos: declarados: $(talos_role_list 2>/dev/null | tr '\n' ' ')" >&2
        return 2
    fi
    mkdir -p "${TALOS_PROJECT_ROOT:-.}/orchestration"
    printf '%s\n' "$1" > "${TALOS_PROJECT_ROOT:-.}/orchestration/.current-role"
    [ -n "${2:-}" ] && printf '%s\n' "$2" > "${TALOS_PROJECT_ROOT:-.}/orchestration/.current-feature"
    return 0
}

# talos_role_deactivate
# Al terminar, el rol se suelta. Un rol que queda pegado gobierna sesiones que
# Talos ya no esta despachando.
talos_role_deactivate() {
    rm -f "${TALOS_PROJECT_ROOT:-.}/orchestration/.current-role" \
          "${TALOS_PROJECT_ROOT:-.}/orchestration/.current-feature"
}

# talos_role_current
talos_role_current() {
    _f="${TALOS_PROJECT_ROOT:-.}/orchestration/.current-role"
    [ -f "$_f" ] || return 1
    cat "$_f"
}

# talos_role_brief <rol> [feature_id]
#
# El texto que se le entrega al agente al despacharlo: sus instrucciones mas
# el alcance concreto de esta corrida. Las instrucciones solas no alcanzan,
# porque el rol no sabe en que feature esta ni que rutas tiene permitidas.
talos_role_brief() {
    _r="$1"; _f="${2:-}"
    _ins=$(talos_role_instructions "$_r") || {
        echo "talos: sin archivo de instrucciones para $_r" >&2
        return 2
    }

    printf 'Talos te despacha con el rol %s' "$_r"
    [ -n "$_f" ] && printf ' para la feature %s' "$_f"
    printf '.\n\n'

    printf 'ALCANCE DE ESCRITURA (lo fuerza un hook, no tu criterio)\n'
    talos_role_scope "$_r" | while IFS='	' read -r _verdict _glob; do
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
