#!/bin/sh
# Resuelve capacidad -> implementacion -> ejecutable del adapter.
#
# Este archivo es NUCLEO. No nombra ninguna implementacion concreta: lee la
# ligadura que declara config/extensions.yaml, compilada a plano por
# tools/build-registry.py. Esa es la regla 37.4.3.5 de talos-0.0.6.md.
#
# Aplica las reglas 37.4.3.1 a 37.4.3.3:
#   - toda capacidad REQUERIDA debe tener exactamente una implementacion
#   - cero implementaciones de una requerida falla en PRECONDITION_GATE
#   - dos o mas de la misma capacidad falla por ambiguedad
#
# Uso:  . hooks/lib/resolve-capability.sh
#       talos_capability_impl ExecutionAdapter
#       talos_capability_health ExecutionAdapter

# Raiz del sistema: donde vive Talos, no donde vive el trabajo (seccion 8).
_cap_lib_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
case "$_cap_lib_dir" in
    */lib) TALOS_CAP_SYS=$(dirname "$(dirname "$_cap_lib_dir")") ;;
    *)     TALOS_CAP_SYS="${TALOS_SYSTEM_ROOT:-$_cap_lib_dir}" ;;
esac
[ -n "${TALOS_SYSTEM_ROOT:-}" ] && TALOS_CAP_SYS="$TALOS_SYSTEM_ROOT"

TALOS_CAP_TABLE="${TALOS_CAPABILITIES_FILE:-$TALOS_CAP_SYS/hooks/generated/capabilities.tsv}"

# talos_capability_table
# Emite la tabla sin comentarios ni lineas vacias.
talos_capability_table() {
    [ -f "$TALOS_CAP_TABLE" ] || return 1
    grep -v '^#' "$TALOS_CAP_TABLE" | grep -v '^[[:space:]]*$'
}

# talos_capability_row <capacidad>  -> "cap<TAB>kind<TAB>impl<TAB>dir"
talos_capability_row() {
    talos_capability_table | awk -F'\t' -v c="$1" '$1 == c { print; found = 1 } END { exit !found }'
}

# talos_capability_kind <capacidad>  -> required | optional
talos_capability_kind() {
    talos_capability_row "$1" | cut -f2
}

# talos_capability_impl <capacidad>  -> id de la implementacion ligada
# Sale 1 si la capacidad no tiene implementacion.
talos_capability_impl() {
    _impl=$(talos_capability_row "$1" | cut -f3) || return 1
    [ "$_impl" = "-" ] && return 1
    printf '%s' "$_impl"
}

# talos_capability_dir <capacidad>  -> ruta absoluta del adapter
talos_capability_dir() {
    _dir=$(talos_capability_row "$1" | cut -f4) || return 1
    [ "$_dir" = "-" ] && return 1
    printf '%s/%s' "$TALOS_CAP_SYS" "$_dir"
}

# talos_capability_run <capacidad> <operacion> [args-json]
# Invoca el adapter ligado a la capacidad.
talos_capability_run() {
    _cap="$1"; shift
    _dir=$(talos_capability_dir "$_cap") || {
        echo "talos: no hay implementacion ligada para $_cap" >&2
        return 2
    }
    [ -x "$_dir/run.sh" ] || {
        echo "talos: el adapter de $_cap no tiene run.sh ejecutable en $_dir" >&2
        return 5
    }
    "$_dir/run.sh" "$@"
}

# talos_capability_health <capacidad>  -> 0 sana / 1 sin ligar / 5 no responde
talos_capability_health() {
    talos_capability_dir "$1" >/dev/null 2>&1 || return 1
    talos_capability_run "$1" health >/dev/null 2>&1 || return 5
    return 0
}

# ---------- resolucion de binarios externos (seccion 37.4.5) ----------
#
# Cascada: variable de entorno -> .talos/bin/<binario> -> PATH.
# La primera coincidencia gana. Talos NO instala nada (regla 37.4.5.4).

# talos_resolve_binary <nombre> [variable-de-entorno]
talos_resolve_binary() {
    _bin="$1"
    _env="${2:-}"

    if [ -n "$_env" ]; then
        eval "_val=\${$_env:-}"
        if [ -n "$_val" ] && [ -x "$_val" ]; then
            printf '%s' "$_val"
            return 0
        fi
    fi

    _vendored="${TALOS_PROJECT_ROOT:-.}/.talos/bin/$_bin"
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
# talos_capability_audit
# Emite una linea por capacidad: <cap>|<kind>|<estado>|<detalle>
# Estados: ok | sin_ligar | sin_adapter | no_responde
#
# Corre el health check UNA sola vez por capacidad. Quien necesite el conteo de
# fallas lo saca de estas mismas filas con talos_capability_failures: volver a
# auditar para contar hacia tres pasadas de health checks por invocacion.
talos_capability_audit() {
    if ! talos_capability_table >/dev/null 2>&1; then
        echo "-|-|sin_tabla|falta $TALOS_CAP_TABLE, corre tools/build-registry.py"
        return 2
    fi

    talos_capability_table | while IFS='	' read -r _cap _kind _impl _dir; do
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
        if [ ! -x "$TALOS_CAP_SYS/$_dir/run.sh" ]; then
            echo "$_cap|$_kind|sin_adapter|$_impl no tiene run.sh ejecutable"
            continue
        fi
        if "$TALOS_CAP_SYS/$_dir/run.sh" health >/dev/null 2>&1; then
            echo "$_cap|$_kind|ok|$_impl"
        else
            echo "$_cap|$_kind|no_responde|$_impl fallo el health check"
        fi
    done
    return 0
}

# talos_capability_failures <filas-de-audit>
# Cuenta las capacidades REQUERIDAS que no quedaron en ok.
talos_capability_failures() {
    printf '%s\n' "$1" | awk -F'|' '$2 == "required" && $3 != "ok"' | grep -c . | tr -d ' '
}

# talos_capability_audit_failures
# Compatibilidad: audita y cuenta en un paso.
talos_capability_audit_failures() {
    talos_capability_failures "$(talos_capability_audit || true)"
}
