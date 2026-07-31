#!/bin/sh
# Librería compartida por los adapters de referencia.
#
# No es parte del núcleo: vive bajo adapters/ porque es infraestructura de
# implementación, no contrato. El núcleo nunca la carga.
#
# Provee lo que talos-0.0.6.md seccion 38 exige de todo adapter:
#   - resultado estructurado                        (38.1.3)
#   - idempotency key determinista                  (38.2.4)
#   - forma de retorno de operacion mutante         (38.2.3)
#   - registro de la accion simulada en vez de ejecutarla (38.4 DryRunAdapter)

# ---------- salida estructurada ----------

# talos_ok <json-body>
# Resultado de una operacion no mutante.
#
# dry_run refleja lo que realmente paso. Un adapter productivo que reporte
# dry_run:true estaria mintiendo sobre si toco el mundo, y el campo se vuelve
# inservible justo cuando importa. Los adapters de simulacion lo dejan en 1;
# los productivos lo bajan a 0 cuando ejecutan de verdad.
TALOS_ADAPTER_SIMULATED="${TALOS_ADAPTER_SIMULATED:-1}"

talos_ok() {
    if [ "${TALOS_ADAPTER_SIMULATED}" = 1 ]; then
        printf '{"status":"ok","dry_run":true,"result":%s}\n' "$1"
    else
        printf '{"status":"ok","dry_run":false,"result":%s}\n' "$1"
    fi
}

# talos_error <clase> <mensaje>
# Clases segun talos-0.0.6.md seccion 35.1.
talos_error() {
    printf '{"status":"error","error_class":"%s","message":"%s"}\n' "$1" "$2" >&2
    return 5
}

# ---------- idempotencia ----------

# talos_sha256 <cadena>
# sha256sum en Linux, shasum en macOS. Sin dependencias nuevas.
talos_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    else
        return 1
    fi
}

# talos_canonical_json <json>
# Serializacion canonica: claves ordenadas, sin espacios. Es lo que hace
# determinista a la key. Requiere python3, que ya es requisito del validador.
talos_canonical_json() {
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True, separators=(",",":")))'
    else
        return 1
    fi
}

# talos_idempotency_key <run_id> <feature_id> <operation> <semantic_args_json>
#
# Formula exacta de talos-0.0.6.md 38.2.4. semantic_args NO DEBE contener
# timestamps ni valores no deterministas (38.2.5): eso es responsabilidad de
# quien llama, porque el adapter no puede saber que campo es semantico.
talos_idempotency_key() {
    _canon=$(talos_canonical_json "$4") || {
        talos_error precondition "no hay python3 para canonicalizar semantic_args"
        return 5
    }
    talos_sha256 "$1:$2:$3:$_canon" || {
        talos_error precondition "no hay sha256sum ni shasum disponible"
        return 5
    }
}

# ---------- ledger de acciones simuladas ----------
#
# Un adapter dry-run que no deja rastro no es auditable. El ledger es lo que
# hace que "already_exists" sea comprobable en un reintento, que es la unica
# forma de demostrar idempotencia sin backend externo.

talos_ledger_path() {
    printf '%s/orchestration/dry-run/ledger.tsv' "${TALOS_PROJECT_ROOT:-.}"
}

# talos_ledger_lookup <key>  -> imprime el resource_ref guardado, o falla
talos_ledger_lookup() {
    _ledger=$(talos_ledger_path)
    [ -f "$_ledger" ] || return 1
    _hit=$(grep -- "^$1	" "$_ledger" 2>/dev/null | head -1) || return 1
    [ -n "$_hit" ] || return 1
    printf '%s' "$_hit" | cut -f3
}

# talos_ledger_record <key> <operation> <resource_ref_json>
talos_ledger_record() {
    _ledger=$(talos_ledger_path)
    mkdir -p "$(dirname "$_ledger")"
    if [ ! -f "$_ledger" ]; then
        {
            echo "# Acciones simuladas por los adapters dry-run."
            echo "# El modo dry-run-only NO produce evidencia verificable (regla 37.4.4.2)."
            echo "# formato: <idempotency_key>\t<operation>\t<resource_ref_json>"
        } >"$_ledger"
    fi
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$_ledger"
}

# talos_mutate <operation> <run_id> <feature_id> <semantic_args_json> <resource_ref_json>
#
# Forma de retorno exacta de talos-0.0.6.md 38.2.3. Reintentar con los mismos
# argumentos devuelve already_exists en vez de crear un duplicado: es la
# correccion de 0.0.4 que evitaba PRs e issues duplicados al reintentar.
talos_mutate() {
    _op="$1"; _run="$2"; _feat="$3"; _args="$4"; _ref="$5"

    _key=$(talos_idempotency_key "$_run" "$_feat" "$_op" "$_args") || return 5

    if _existing=$(talos_ledger_lookup "$_key"); then
        printf '{"status":"already_exists","resource_ref":%s,"idempotency_key":"%s","dry_run":true}\n' \
            "$_existing" "$_key"
        return 0
    fi

    talos_ledger_record "$_key" "$_op" "$_ref"
    printf '{"status":"created","resource_ref":%s,"idempotency_key":"%s","dry_run":%s}\n' \
        "$_ref" "$_key" "$([ "$TALOS_ADAPTER_SIMULATED" = 1 ] && echo true || echo false)"
}

# talos_mutate_run <operation> <run_id> <feature_id> <semantic_args> <campo-id> <cmd...>
#
# Igual que talos_mutate, pero EJECUTA el comando en vez de recibir su
# resultado ya calculado.
#
# La diferencia no es de estilo. Pasar "$(comando)" como argumento hace que la
# sustitucion se evalue ANTES de entrar a la funcion: el efecto de lado ocurre
# siempre, y la consulta al ledger llega tarde. Con eso un reintento devuelve
# already_exists y aun asi crea un recurso duplicado, que es exactamente lo que
# la seccion 38.2 corrige de 0.0.4.
#
# Un adapter que ejecuta de verdad DEBE usar esta forma.
talos_mutate_run() {
    _op="$1"; _run="$2"; _feat="$3"; _args="$4"; _field="$5"
    shift 5

    _key=$(talos_idempotency_key "$_run" "$_feat" "$_op" "$_args") || return 5

    # Consulta ANTES de tocar nada.
    if _existing=$(talos_ledger_lookup "$_key"); then
        printf '{"status":"already_exists","resource_ref":%s,"idempotency_key":"%s","dry_run":%s}\n' \
            "$_existing" "$_key" \
            "$([ "$TALOS_ADAPTER_SIMULATED" = 1 ] && echo true || echo false)"
        return 0
    fi

    _out=$("$@") || {
        talos_error adapter "la operacion $_op fallo en el backend"
        return 5
    }
    _id=$(printf '%s' "$_out" \
          | sed -n 's/.*"'"$_field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$_id" ] || _id="$_op"
    _ref="{\"id\":\"$_id\",\"url\":null}"

    talos_ledger_record "$_key" "$_op" "$_ref"
    printf '{"status":"created","resource_ref":%s,"idempotency_key":"%s","dry_run":%s}\n' \
        "$_ref" "$_key" \
        "$([ "$TALOS_ADAPTER_SIMULATED" = 1 ] && echo true || echo false)"
}

# ---------- despacho ----------

# talos_require_op <operacion> <lista de operaciones soportadas>
talos_unknown_op() {
    talos_error precondition "operacion no soportada por este adapter: $1"
}
