#!/bin/sh
# Comparacion de versiones para la verificacion de binarios externos.
#
# Regla 37.4.5.2: el adapter DEBE verificar la version del binario resuelto
# contra su rango declarado. Regla 37.4.5.3: una version fuera de rango DEBE
# fallar en PRECONDITION_GATE.
#
# Sin esto, "declara herdr >= 0.7.0" es un comentario, no una precondition.

# thalos_semver_ge <a> <b>  -> 0 si a >= b
#
# Compara mayor, menor y patch como enteros. Ordenar versiones como texto
# diria que 0.10.0 < 0.9.0, que es exactamente el error que hay que evitar.
thalos_semver_ge() {
    _a=$(printf '%s' "$1" | sed 's/^[^0-9]*//' | cut -d- -f1)
    _b=$(printf '%s' "$2" | sed 's/^[^0-9]*//' | cut -d- -f1)

    # Una cadena sin ningun digito no es una version. Sale 2 -indeterminado-
    # en vez de caer al 0.0.0 que dejarian los defaults de abajo: tratar
    # "desconocida" como 0.0.0 convierte un dato faltante en un rechazo con
    # motivo falso.
    [ -n "$_a" ] || return 2
    [ -n "$_b" ] || return 2

    _a1=$(printf '%s' "$_a" | cut -d. -f1); _a1=${_a1:-0}
    _a2=$(printf '%s' "$_a" | cut -d. -f2); _a2=${_a2:-0}
    _a3=$(printf '%s' "$_a" | cut -d. -f3); _a3=${_a3:-0}
    _b1=$(printf '%s' "$_b" | cut -d. -f1); _b1=${_b1:-0}
    _b2=$(printf '%s' "$_b" | cut -d. -f2); _b2=${_b2:-0}
    _b3=$(printf '%s' "$_b" | cut -d. -f3); _b3=${_b3:-0}

    # Un componente no numerico invalida la comparacion: no se adivina.
    # El nombre del contador va prefijado y es local a esta funcion por
    # convencion: en POSIX sh no hay scope, y un _v aca pisaria el _v de quien
    # llame. Esa colision hacia que la version leida se reportara como "0".
    for _semver_c in "$_a1" "$_a2" "$_a3" "$_b1" "$_b2" "$_b3"; do
        case "$_semver_c" in ''|*[!0-9]*) return 2 ;; esac
    done

    [ "$_a1" -gt "$_b1" ] && return 0
    [ "$_a1" -lt "$_b1" ] && return 1
    [ "$_a2" -gt "$_b2" ] && return 0
    [ "$_a2" -lt "$_b2" ] && return 1
    [ "$_a3" -ge "$_b3" ] && return 0
    return 1
}

# thalos_semver_satisfies <version> <rango>
# Soporta ">=X.Y.Z" y "X.Y.Z" exacto, que es lo que declaran los manifiestos.
thalos_semver_satisfies() {
    _ver="$1"; _range="$2"
    case "$_range" in
        ">="*)
            thalos_semver_ge "$_ver" "${_range#>=}"
            ;;
        "")
            return 0
            ;;
        *)
            [ "$_ver" = "$_range" ]
            ;;
    esac
}
