#!/bin/sh
# Resuelve capacidad -> implementacion -> ejecutable del adapter.
#
# Este archivo es NUCLEO. No nombra ninguna implementacion concreta: lee la
# ligadura que declara config/extensions.yaml, compilada a plano por
# tools/build-registry.py. Esa es la regla 37.4.3.5 de thalos-0.0.7.md.
#
# Aplica las reglas 37.4.3.1 a 37.4.3.3:
#   - toda capacidad REQUERIDA debe tener exactamente una implementacion
#   - cero implementaciones de una requerida falla en PRECONDITION_GATE
#   - dos o mas de la misma capacidad falla por ambiguedad
#
# Uso:  . hooks/lib/resolve-capability.sh
#       thalos_capability_impl ExecutionAdapter
#       thalos_capability_health ExecutionAdapter

# Raiz del sistema: donde vive Thalos, no donde vive el trabajo (seccion 8).
_cap_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_cap_lib_dir" in
    */lib) THALOS_CAP_SYS=$(dirname "$(dirname "$_cap_lib_dir")") ;;
    *)     THALOS_CAP_SYS="${THALOS_SYSTEM_ROOT:-$_cap_lib_dir}" ;;
esac
[ -n "${THALOS_SYSTEM_ROOT:-}" ] && THALOS_CAP_SYS="$THALOS_SYSTEM_ROOT"

THALOS_CAP_TABLE="${THALOS_CAPABILITIES_FILE:-$THALOS_CAP_SYS/hooks/generated/capabilities.tsv}"

# thalos_capability_table
# Emite la tabla sin comentarios ni lineas vacias.
thalos_capability_table() {
    [ -f "$THALOS_CAP_TABLE" ] || return 1
    grep -v '^#' "$THALOS_CAP_TABLE" | grep -v '^[[:space:]]*$'
}

# thalos_capability_row <capacidad>  -> "cap<TAB>kind<TAB>impl<TAB>dir"
thalos_capability_row() {
    thalos_capability_table | awk -F'\t' -v c="$1" '$1 == c { print; found = 1 } END { exit !found }'
}

# thalos_capability_kind <capacidad>  -> required | optional
thalos_capability_kind() {
    thalos_capability_row "$1" | cut -f2
}

# thalos_capability_impl <capacidad>  -> id de la implementacion ligada
# Sale 1 si la capacidad no tiene implementacion.
thalos_capability_impl() {
    _impl=$(thalos_capability_row "$1" | cut -f3) || return 1
    [ "$_impl" = "-" ] && return 1
    printf '%s' "$_impl"
}

# thalos_capability_dir <capacidad>  -> ruta absoluta del adapter
thalos_capability_dir() {
    _dir=$(thalos_capability_row "$1" | cut -f4) || return 1
    [ "$_dir" = "-" ] && return 1
    printf '%s/%s' "$THALOS_CAP_SYS" "$_dir"
}

# thalos_capability_run <capacidad> <operacion> [args-json]
# Invoca el adapter ligado a la capacidad.
thalos_capability_run() {
    _cap="$1"; shift
    _dir=$(thalos_capability_dir "$_cap") || {
        echo "thalos: no hay implementacion ligada para $_cap" >&2
        return 2
    }
    [ -x "$_dir/run.sh" ] || {
        echo "thalos: el adapter de $_cap no tiene run.sh ejecutable en $_dir" >&2
        return 5
    }
    "$_dir/run.sh" "$@"
}

# thalos_capability_health <capacidad>  -> 0 sana / 1 sin ligar / 5 no responde
thalos_capability_health() {
    thalos_capability_dir "$1" >/dev/null 2>&1 || return 1
    thalos_capability_run "$1" health >/dev/null 2>&1 || return 5
    return 0
}

# ---------- resolucion de binarios externos (seccion 37.4.5) ----------
#
# Cascada: variable de entorno -> .thalos/bin/<binario> -> PATH.
# La primera coincidencia gana. Thalos NO instala nada (regla 37.4.5.4).

# thalos_resolve_binary <nombre> [variable-de-entorno]
thalos_resolve_binary() {
    _bin="$1"
    _env="${2:-}"

    if [ -n "$_env" ]; then
        eval "_val=\${$_env:-}"
        if [ -n "$_val" ] && [ -x "$_val" ]; then
            printf '%s' "$_val"
            return 0
        fi
    fi

    _vendored="${THALOS_PROJECT_ROOT:-.}/.thalos/bin/$_bin"
    if [ -x "$_vendored" ]; then
        printf '%s' "$_vendored"
        return 0
    fi

    if command -v "$_bin" >/dev/null 2>&1; then
        command -v "$_bin"
        return 0
    fi

    return 1
}

# ---------- verificacion del registry completo ----------
#
# thalos_capability_audit
# Emite una linea por capacidad: <cap>|<kind>|<estado>|<detalle>
# Estados: ok | sin_ligar | sin_adapter | no_responde
#
# Corre el health check UNA sola vez por capacidad. Quien necesite el conteo de
# fallas lo saca de estas mismas filas con thalos_capability_failures: volver a
# auditar para contar hacia tres pasadas de health checks por invocacion.
thalos_capability_audit() {
    if ! thalos_capability_table >/dev/null 2>&1; then
        echo "-|-|sin_tabla|falta $THALOS_CAP_TABLE, corre tools/build-registry.py"
        return 2
    fi

    # Se leen los siete campos: con menos variables, read mete el resto de la
    # linea en la ultima y _dir deja de ser una ruta.
    # shellcheck disable=SC2034
    thalos_capability_table | while IFS='	' read -r _cap _kind _impl _dir _bin _range _env; do
        [ -z "$_cap" ] && continue
        if [ "$_impl" = "-" ]; then
            # Regla 37.4.3.4: cero implementaciones de una opcional es valido.
            if [ "$_kind" = required ]; then
                echo "$_cap|$_kind|sin_ligar|capacidad REQUERIDA sin implementacion"
            else
                echo "$_cap|$_kind|sin_ligar|sin implementacion (valido)"
            fi
            continue
        fi
        if [ ! -x "$THALOS_CAP_SYS/$_dir/run.sh" ]; then
            echo "$_cap|$_kind|sin_adapter|$_impl no tiene run.sh ejecutable"
            continue
        fi
        if "$THALOS_CAP_SYS/$_dir/run.sh" health >/dev/null 2>&1; then
            echo "$_cap|$_kind|ok|$_impl"
        else
            echo "$_cap|$_kind|no_responde|$_impl fallo el health check"
        fi
    done
    return 0
}

# thalos_capability_binaries
# Una linea por capacidad ligada que declara binario externo:
#   <cap>|<binario>|<rango>|<ruta-resuelta|->
#
# Regla 37.4.5.6: thalos doctor DEBE reportar la ruta resuelta. Sin esto, saber
# cual de los tres pasos de la cascada gano exige adivinar.
thalos_capability_binaries() {
    thalos_capability_table 2>/dev/null \
        | awk -F'\t' '$5 != "-" { print $1 "|" $5 "|" $6 "|" $7 }' \
        | while IFS='|' read -r _cap _bin _range _env; do
            [ -z "$_cap" ] && continue
            if _path=$(thalos_resolve_binary "$_bin" "$_env"); then
                echo "$_cap|$_bin|$_range|$_path"
            else
                echo "$_cap|$_bin|$_range|-"
            fi
        done
}

# thalos_capability_failures <filas-de-audit>
# Cuenta las capacidades REQUERIDAS que no quedaron en ok.
thalos_capability_failures() {
    printf '%s\n' "$1" | awk -F'|' '$2 == "required" && $3 != "ok"' | grep -c . | tr -d ' '
}

# thalos_capability_audit_failures
# Compatibilidad: audita y cuenta en un paso.
thalos_capability_audit_failures() {
    thalos_capability_failures "$(thalos_capability_audit || true)"
}
