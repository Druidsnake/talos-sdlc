#!/bin/sh
# thalos event append - registra un evento con secuencia monotonica.
#
# EventLog es el UNICO escritor de seq (thalos-0.0.7.md 41.2.2). La exclusion
# se hace con mkdir, que es atomico en POSIX: si el directorio ya existe,
# mkdir falla y sabemos que otro escritor tiene el turno.
#
# Uso: thalos event append --type thalos.feature.started --actor role:FeatureLead
#                         [--feature F001] [--evidence ev-1,ev-2]

set -eu

SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

META=orchestration/.meta.json
LOCKDIR=orchestration/.lock
EVENTS=orchestration/events

type=""
actor=""
feature=""
evidence=""
causation=""
payload=""

while [ $# -gt 0 ]; do
    case "$1" in
        --type)      type="${2:?falta valor para --type}"; shift 2 ;;
        --actor)     actor="${2:?falta valor para --actor}"; shift 2 ;;
        --feature)   feature="${2:?falta valor para --feature}"; shift 2 ;;
        --evidence)  evidence="${2:?falta valor para --evidence}"; shift 2 ;;
        --causation) causation="${2:?falta valor para --causation}"; shift 2 ;;
        # event.schema.json define payload desde 0.0.6 y ningun comando lo
        # exponia: el campo estaba muerto y todo evento salia con {}. Sin el,
        # una escalacion puede decir que escalo pero no QUE escalo, y el que
        # lee el log se queda sin el unico dato accionable.
        --payload)   payload="${2:?falta valor para --payload}"; shift 2 ;;
        -h|--help)
            cat <<'USAGE'
thalos event append - registra un evento con secuencia monotonica

USO
    thalos event append --type <thalos.x.y> --actor <actor> [opciones]

OBLIGATORIOS
    --type       tipo del evento, en el namespace thalos
    --actor      quien lo produce. Ej: core:MergeGate, role:Developer

OPCIONALES
    --feature    id de feature. Ej: F001
    --evidence   ids de evidencia separados por coma
    --causation  id del evento que lo causo
    --payload    objeto JSON con el detalle del evento. Se valida antes de
                 escribir: uno que no parsea no entra al log

COMO FUNCIONA
    EventLog es el unico escritor de seq. La exclusion usa mkdir, que es
    atomico en POSIX. El evento se valida ANTES de escribirse: uno
    invalido no entra al log y no consume secuencia.

EJEMPLO
    thalos event append --type thalos.feature.started \
                       --actor role:FeatureLead --feature F001

SALIDA
    0  registrado    1  evento invalido
    2  runtime sin inicializar    5  no se pudo tomar el lock
USAGE
            exit 0 ;;
        *) echo "thalos: opcion desconocida: $1" >&2; exit 1 ;;
    esac
done

[ -n "$type" ]  || { echo "thalos: --type es obligatorio" >&2; exit 1; }
[ -n "$actor" ] || { echo "thalos: --actor es obligatorio" >&2; exit 1; }

if [ ! -f "$META" ]; then
    echo "thalos: runtime sin inicializar" >&2
    echo "thalos: ejecuta thalos init" >&2
    exit 2
fi

# El namespace lo valida despues el schema, pero fallar temprano da mejor mensaje.
case "$type" in
    thalos.*.*) ;;
    *) echo "thalos: el tipo debe usar el namespace thalos: $type" >&2; exit 1 ;;
esac

# --- exclusion mutua: mkdir es atomico ---
attempts=0
until mkdir "$LOCKDIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 50 ]; then
        echo "thalos: no se pudo tomar el lock del event log tras 50 intentos" >&2
        echo "thalos: si ningun proceso esta escribiendo, borra $LOCKDIR" >&2
        exit 5
    fi
    sleep 0.1 2>/dev/null || sleep 1
done
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT INT TERM

# Ancla en la clave. Un sed con .*: es codicioso y parte mal los timestamps.
read_meta() {
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\(.*\)/\1/p" "$META" \
        | head -1 | sed 's/[",]//g' | tr -d ' '
}

last_seq=$(read_meta last_event_seq)
run_id=$(read_meta run_id)
project=$(basename "$PROJ")
: "${last_seq:=0}"

seq=$((last_seq + 1))
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
eid="ev-$(printf '%06d' "$seq")-$(od -An -N3 -tx1 </dev/urandom | tr -d ' \n')"

# evidencia como array JSON
ev_json="[]"
if [ -n "$evidence" ]; then
    ev_json=$(printf '%s' "$evidence" | tr ',' '\n' | sed 's/^/"/; s/$/"/' | tr '\n' ',' | sed 's/,$//')
    ev_json="[$ev_json]"
fi

json_or_null() { [ -n "$1" ] && printf '"%s"' "$1" || printf 'null'; }

# Un payload que no parsea NO entra: el evento se valida contra su schema
# antes de escribirse, y meter basura ahi lo volveria irrecuperable justo
# cuando alguien lo lee para entender que paso.
pl_json="{}"
if [ -n "$payload" ]; then
    if command -v python3 >/dev/null 2>&1 \
       && printf '%s' "$payload" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        pl_json="$payload"
    else
        echo "thalos: --payload no es un objeto JSON valido" >&2
        exit 1
    fi
fi

mkdir -p "$EVENTS"
logfile="$EVENTS/$(printf '%06d' $(( (seq - 1) / 1000 + 1 ))).ndjson"

event=$(cat <<EOF
{"id":"$eid","seq":$seq,"schema_version":1,"type":"$type","ts":"$now","run_id":"$run_id","project":"$project","feature_id":$(json_or_null "$feature"),"actor":"$actor","correlation_id":$(json_or_null "$feature"),"causation_id":$(json_or_null "$causation"),"evidence_refs":$ev_json,"payload":$pl_json}
EOF
)

# Se valida ANTES de escribir: un evento invalido no entra al log.
tmp=$(mktemp)
printf '%s\n' "$event" > "$tmp"
if [ -x "$SYS/hooks/validate-artifact.sh" ]; then
    if ! "$SYS/hooks/validate-artifact.sh" event "$tmp" >/dev/null 2>&1; then
        echo "thalos: el evento no valida contra event.schema.json" >&2
        "$SYS/hooks/validate-artifact.sh" event "$tmp" >&2 || true
        rm -f "$tmp"
        exit 1
    fi
fi
rm -f "$tmp"

printf '%s\n' "$event" >> "$logfile"

# Actualiza last_event_seq de forma atomica
newmeta=$(mktemp)
sed "s/\"last_event_seq\": *[0-9]*/\"last_event_seq\": $seq/" "$META" > "$newmeta"
mv "$newmeta" "$META"

echo "$eid seq=$seq $type"
