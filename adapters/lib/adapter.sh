#!/bin/sh
# Librería compartida por los adapters de referencia.
#
# No es parte del núcleo: vive bajo adapters/ porque es infraestructura de
# implementación, no contrato. El núcleo nunca la carga.
#
# Provee lo que thalos-0.0.7.md seccion 38 exige de todo adapter:
#   - resultado estructurado                        (38.1.3)
#   - idempotency key determinista                  (38.2.4)
#   - forma de retorno de operacion mutante         (38.2.3)
#   - registro de la accion simulada en vez de ejecutarla (38.4 DryRunAdapter)

# ---------- salida estructurada ----------

# thalos_ok <json-body>
# Resultado de una operacion no mutante.
#
# dry_run refleja lo que realmente paso. Un adapter productivo que reporte
# dry_run:true estaria mintiendo sobre si toco el mundo, y el campo se vuelve
# inservible justo cuando importa. Los adapters de simulacion lo dejan en 1;
# los productivos lo bajan a 0 cuando ejecutan de verdad.
THALOS_ADAPTER_SIMULATED="${THALOS_ADAPTER_SIMULATED:-1}"

thalos_ok() {
    if [ "${THALOS_ADAPTER_SIMULATED}" = 1 ]; then
        printf '{"status":"ok","dry_run":true,"result":%s}\n' "$1"
    else
        printf '{"status":"ok","dry_run":false,"result":%s}\n' "$1"
    fi
}

# thalos_error <clase> <mensaje>
# Clases segun thalos-0.0.7.md seccion 35.1.
thalos_error() {
    printf '{"status":"error","error_class":"%s","message":"%s"}\n' "$1" "$2" >&2
    return 5
}

# ---------- idempotencia ----------

# thalos_sha256 <cadena>
# sha256sum en Linux, shasum en macOS. Sin dependencias nuevas.
thalos_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    else
        return 1
    fi
}

# thalos_canonical_json <json>
# Serializacion canonica: claves ordenadas, sin espacios. Es lo que hace
# determinista a la key. Requiere python3, que ya es requisito del validador.
thalos_canonical_json() {
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True, separators=(",",":")))'
    else
        return 1
    fi
}

# thalos_idempotency_key <run_id> <feature_id> <operation> <semantic_args_json>
#
# Formula exacta de thalos-0.0.7.md 38.2.4. semantic_args NO DEBE contener
# timestamps ni valores no deterministas (38.2.5): eso es responsabilidad de
# quien llama, porque el adapter no puede saber que campo es semantico.
thalos_idempotency_key() {
    _canon=$(thalos_canonical_json "$4") || {
        thalos_error precondition "no hay python3 para canonicalizar semantic_args"
        return 5
    }
    thalos_sha256 "$1:$2:$3:$_canon" || {
        thalos_error precondition "no hay sha256sum ni shasum disponible"
        return 5
    }
}

# ---------- ledger de acciones ----------
#
# Un adapter que no deja rastro no es auditable. El ledger es lo que hace que
# "already_exists" sea comprobable en un reintento, que es la unica forma de
# demostrar idempotencia sin backend externo.
#
# CADA ENTRADA DICE QUIEN LA ESCRIBIO, y una consulta solo acepta las propias.
#
# La idempotency key de la seccion 38.2.4 es sha256(run_id:feature:op:args), y
# el run_id sale del runtime del proyecto: es estable entre sesiones. Con un
# ledger compartido y sin procedencia, un adapter productivo consultaba una
# clave que habia escrito el SIMULADOR, recibia already_exists y devolvia un id
# fabricado sin ejecutar nada. Reportaba exito habiendo creado nada, y el
# recurso inexistente reventaba en el paso siguiente.
#
# La key no cambia: la formula es contrato (38.2.4). Lo que cambia es que el
# ledger deja de mentir sobre de quien es cada linea.

thalos_ledger_path() {
    printf '%s/orchestration/dry-run/ledger.tsv' "${THALOS_PROJECT_ROOT:-.}"
}

# thalos_adapter_id
# El id declarado en el manifiesto del adapter que se esta ejecutando. Sale de
# adapter.yaml, que vive junto a run.sh: ningun adapter necesita repetirlo.
thalos_adapter_id() {
    _self=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || {
        printf '%s' "-"; return 0
    }
    _id=$(sed -n 's/^id:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$_self/adapter.yaml" 2>/dev/null | head -1)
    [ -n "$_id" ] || _id="-"
    printf '%s' "$_id"
}

# thalos_ledger_lookup <key>  -> imprime el resource_ref guardado, o falla
#
# Falla tambien cuando la entrada la escribio OTRO adapter: un recurso creado
# por otra implementacion no es un recurso que este pueda dar por existente.
# Las entradas viejas sin columna de procedencia caen en el mismo caso, que es
# lo correcto: sin saber quien las escribio no se les puede creer.
# Gana la ULTIMA fila, no la primera: cuando una entrada queda obsoleta y la
# operacion se vuelve a ejecutar, se registra otra con la misma clave. Quedarse
# con la primera devolveria para siempre el recurso viejo, que es justo el que
# ya no existe.
thalos_ledger_lookup() {
    _ledger=$(thalos_ledger_path)
    [ -f "$_ledger" ] || return 1
    _me=$(thalos_adapter_id)
    _hit=$(awk -F'\t' -v k="$1" -v a="$_me" \
           '$1 == k && $4 == a { v = $3 } END { if (v != "") print v }' "$_ledger")
    [ -n "$_hit" ] || return 1
    printf '%s' "$_hit"
}

# thalos_ledger_vigente <resource_ref_json>
#
# El ledger dice "esto se hizo una vez". NO dice "el recurso sigue existiendo".
# Para un recurso que puede desaparecer -un panel que alguien cierra, o que
# cierra el propio Thalos al soltar el rol- creerle al registro devuelve
# already_exists sobre algo que ya no esta, y quien llamo se lleva un id muerto.
#
# Un adapter que maneje recursos asi define THALOS_LEDGER_VERIFY con el nombre
# de una funcion que reciba el id y salga 0 si el recurso vive. Sin esa
# variable el comportamiento es el de siempre: se le cree al ledger.
thalos_ledger_vigente() {
    [ -n "${THALOS_LEDGER_VERIFY:-}" ] || return 0
    _lv_id=$(printf '%s' "$1" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$_lv_id" ] || return 0
    "$THALOS_LEDGER_VERIFY" "$_lv_id"
}

# thalos_ledger_record <key> <operation> <resource_ref_json>
thalos_ledger_record() {
    _ledger=$(thalos_ledger_path)
    mkdir -p "$(dirname "$_ledger")"
    if [ ! -f "$_ledger" ]; then
        {
            echo "# Acciones registradas por los adapters."
            echo "# El modo dry-run-only NO produce evidencia verificable (regla 37.4.4.2)."
            echo "# formato: <idempotency_key>\t<operation>\t<resource_ref_json>\t<adapter>"
        } >"$_ledger"
    fi
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(thalos_adapter_id)" >>"$_ledger"
}

# thalos_mutate <operation> <run_id> <feature_id> <semantic_args_json> <resource_ref_json>
#
# Forma de retorno exacta de thalos-0.0.7.md 38.2.3. Reintentar con los mismos
# argumentos devuelve already_exists en vez de crear un duplicado: es la
# correccion de 0.0.4 que evitaba PRs e issues duplicados al reintentar.
thalos_mutate() {
    _op="$1"; _run="$2"; _feat="$3"; _args="$4"; _ref="$5"

    _key=$(thalos_idempotency_key "$_run" "$_feat" "$_op" "$_args") || return 5

    if _existing=$(thalos_ledger_lookup "$_key"); then
        printf '{"status":"already_exists","resource_ref":%s,"idempotency_key":"%s","dry_run":true}\n' \
            "$_existing" "$_key"
        return 0
    fi

    thalos_ledger_record "$_key" "$_op" "$_ref"
    printf '{"status":"created","resource_ref":%s,"idempotency_key":"%s","dry_run":%s}\n' \
        "$_ref" "$_key" "$([ "$THALOS_ADAPTER_SIMULATED" = 1 ] && echo true || echo false)"
}

# thalos_mutate_run <operation> <run_id> <feature_id> <semantic_args> <campo-id> <cmd...>
#
# Igual que thalos_mutate, pero EJECUTA el comando en vez de recibir su
# resultado ya calculado.
#
# La diferencia no es de estilo. Pasar "$(comando)" como argumento hace que la
# sustitucion se evalue ANTES de entrar a la funcion: el efecto de lado ocurre
# siempre, y la consulta al ledger llega tarde. Con eso un reintento devuelve
# already_exists y aun asi crea un recurso duplicado, que es exactamente lo que
# la seccion 38.2 corrige de 0.0.4.
#
# Un adapter que ejecuta de verdad DEBE usar esta forma.
thalos_mutate_run() {
    _op="$1"; _run="$2"; _feat="$3"; _args="$4"; _field="$5"
    shift 5

    _key=$(thalos_idempotency_key "$_run" "$_feat" "$_op" "$_args") || return 5

    # Consulta ANTES de tocar nada, y verifica que lo registrado siga vivo
    # cuando el adapter sabe como comprobarlo.
    if _existing=$(thalos_ledger_lookup "$_key"); then
        if thalos_ledger_vigente "$_existing"; then
            printf '{"status":"already_exists","resource_ref":%s,"idempotency_key":"%s","dry_run":%s}\n' \
                "$_existing" "$_key" \
                "$([ "$THALOS_ADAPTER_SIMULATED" = 1 ] && echo true || echo false)"
            return 0
        fi
        # La entrada quedo obsoleta: el recurso que nombra ya no existe. Se
        # ejecuta de nuevo y se registra la nueva, que pasa a ser la vigente.
    fi

    # El motivo del backend viaja en el error. "fallo en el backend" no dice
    # nada: obliga a reproducir a mano lo que el adapter ya sabia.
    if ! _out=$("$@" 2>&1); then
        printf '{"status":"error","error_class":"adapter","operation":"%s","message":%s}\n' \
            "$_op" "$(printf '%s' "$_out" | thalos_json_string)" >&2
        return 5
    fi
    _id=$(printf '%s' "$_out" \
          | sed -n 's/.*"'"$_field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$_id" ] || _id="$_op"
    _ref="{\"id\":\"$_id\",\"url\":null}"

    thalos_ledger_record "$_key" "$_op" "$_ref"
    printf '{"status":"created","resource_ref":%s,"idempotency_key":"%s","dry_run":%s}\n' \
        "$_ref" "$_key" \
        "$([ "$THALOS_ADAPTER_SIMULATED" = 1 ] && echo true || echo false)"
}

# ---------- lectura de semantic_args ----------
#
# thalos_json_get <json> <clave>
#
# Extraer con sed no alcanza: sed no DECODIFICA. Un valor con saltos de linea
# viaja como la secuencia literal \n hasta el agente, que recibe un parrafo de
# una sola linea con barras adentro; y un valor con comillas se corta en la
# primera, porque [^"]* no sabe que \" esta escapada. Las dos fallas son
# silenciosas: la operacion reporta exito con el texto mutilado.
#
# Se usa python3, que ya es requisito para canonicalizar la idempotency key.
# Sin python3 se degrada al sed de antes, que es peor pero no inventa nada.
thalos_json_get() {
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
v = d.get(sys.argv[1])
if v is None:
    raise SystemExit(0)
sys.stdout.write(v if isinstance(v, str) else json.dumps(v))
' "$2"
    else
        printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
    fi
}

# ---------- despacho ----------

# thalos_require_op <operacion> <lista de operaciones soportadas>
thalos_unknown_op() {
    thalos_error precondition "operacion no soportada por este adapter: $1"
}

# thalos_json_string
# Convierte la entrada estandar en un string JSON valido, escapes incluidos.
#
# La salida de una terminal trae saltos de linea, comillas y caracteres de
# control. Insertarla cruda en una posicion JSON produce algo no parseable, y
# la regla 38.1.3 exige resultado estructurado.
thalos_json_string() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
    else
        # Sin python: se degrada a un string vacio antes que emitir JSON roto.
        printf '""'
    fi
}
