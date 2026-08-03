#!/bin/sh
# thalos boot - la chispa.
#
# Thalos no es inteligente y no tiene por que serlo. Lo que sabe hacer es abrir
# una sesion, imponerle un alcance a quien la ocupa, validar artefactos contra
# schemas y evaluar gates contra evidencia sellada. Nada de eso requiere un
# modelo, y por eso la seccion 18.3 lo declara componente de nucleo.
#
# Lo que SI requiere un modelo es decidir: en que orden, a quien despachar,
# cuando una task esta bien partida, cuando la feature esta lista. Ese es el
# FeatureLead (seccion 18.1), y este comando existe para encenderlo.
#
# Despues de esto Thalos no conduce: queda como puerta. Cada cambio de estado
# ocurre porque el maestro llama a un comando, y ese comando decide si esta
# permitido. El alcance lo sigue imponiendo el hook dentro de su runtime, no
# este proceso.
#
# Uso:   thalos boot <FEATURE> [--role FeatureLead] [--kind KIND]
# Sale:  0 encendido / 1 uso / 2 precondition / 5 error de adapter

set -eu

SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

CLI="$SYS/cli/thalos"

usage() {
    cat <<'USAGE'
thalos boot - enciende al coordinador de una feature

USO
    thalos boot <FEATURE> [--role <ROL>] [--kind <RUNTIME>]

QUE HACE
    1. despacha el rol coordinador sobre la feature: abre su sesion, le impone
       el alcance con un hook y le deja el brief donde lo lee
    2. le entrega el encargo de coordinacion: que feature es suya, que estado
       tiene hoy y por donde se pasa para cambiarlo
    3. se retira

    A partir de ahi el coordinador decide. Thalos deja de proponer pasos y
    queda como puerta: valida, evalua gates y registra.

    El tier sale de max(tier de la feature, minimo del rol) segun la seccion
    20.5. FeatureLead declara piso deep: coordinar mal no cuesta una tarea,
    cuesta la feature.

DIFERENCIA CON  thalos run
    run conduce: deriva el paso siguiente y lo ejecuta el mismo. Sirve cuando
    no queres gastar un coordinador, y no decide nada que no este derivado del
    plan y de la evidencia.

    boot delega esa decision en un modelo. Los gates, el alcance y la evidencia
    no cambian: lo que cambia es quien elige el proximo paso.

SALIDA
    0  el coordinador quedo encendido
    1  error de uso
    2  precondition fallida
    5  el ExecutionAdapter no pudo con su parte
USAGE
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

FEAT="${1:-}"
[ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2
                    echo "thalos: thalos boot F001" >&2; exit 1; }
shift

ROLE=FeatureLead
KIND=""
while [ $# -gt 0 ]; do
    case "$1" in
        --role) ROLE="${2:?falta el rol}"; shift 2 ;;
        --kind) KIND="${2:?falta el kind}"; shift 2 ;;
        *) shift ;;
    esac
done

# shellcheck source=../../hooks/lib/resolve-capability.sh
. "$SYS/hooks/lib/resolve-capability.sh"
# shellcheck source=../../hooks/lib/agent-ref.sh
. "$SYS/hooks/lib/agent-ref.sh"

echo "thalos ${THALOS_VERSION:-?}"
echo ""
printf '  encendiendo al coordinador de %s\n\n' "$FEAT"

# ---------- 1. despachar ----------
#
# Se delega en feature dispatch en vez de repetir su logica: es quien sabe
# activar el rol, componer el brief, instalar el enforcement en el runtime y
# registrar la referencia con procedencia. Duplicar eso aca serian dos formas
# de despachar, y una quedaria vieja.
set +e
if [ -n "$KIND" ]; then
    "$CLI" feature dispatch "$FEAT" --role "$ROLE" --kind "$KIND" | sed 's/^/  /'
else
    "$CLI" feature dispatch "$FEAT" --role "$ROLE" | sed 's/^/  /'
fi
rc=$?
set -e
[ "$rc" -eq 0 ] || {
    echo ""
    echo "  no se encendio: sin sesion no hay a quien coordinarle nada."
    exit "$rc"
}

TARGET=$(thalos_agent_ref_field "$FEAT" name) || {
    echo "  FALL el despacho no dejo referencia del agente" >&2
    exit 5
}

# ---------- 2. el encargo de coordinacion ----------
#
# El brief ya lleva las instrucciones del rol y su alcance. Lo que falta es lo
# de ESTA corrida: cual es su feature y como esta hoy. Sin eso el coordinador
# arranca preguntando lo que el sistema ya sabe.
estado=$("$CLI" feature show "$FEAT" 2>/dev/null | sed -n '1,25p' || echo "")
siguiente=$("$CLI" next 2>/dev/null | sed -n '1,20p' || echo "")

encargo=$(cat <<ENCARGO
Sos el coordinador de $FEAT. De punta a punta.

Thalos no te va a decir que hacer: ya no conduce. A partir de ahora vos decidis
el proximo paso y lo pedis por su comando. Thalos valida, evalua el gate y
registra; si algo no esta permitido, el comando falla y te dice por que.

Tu brief tiene la superficie de comandos completa. Lo esencial:
  thalos feature next $FEAT          que transiciones salen del estado actual
  thalos feature dispatch $FEAT --role Developer
  thalos feature work $FEAT          le entrega el trabajo al Developer
  thalos feature release $FEAT       cierra su panel cuando ya no hace falta
  thalos feature advance $FEAT --to <ESTADO>

Estado de hoy:

$estado

Lo que el sistema deriva del plan y de la evidencia:

$siguiente

Empeza por leer el spec aprobado y $FEAT en el plan. Despues decidi el primer
paso y ejecutalo. No escribas codigo: para eso despachas un Developer.
ENCARGO
)

PY=$(command -v python3 2>/dev/null) || {
    echo "  FALL no hay python3 para escapar el encargo" >&2; exit 2; }
esc=$(printf '%s' "$encargo" | "$PY" -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')

# Mismo criterio que feature work: que el adapter acepte el envio no prueba
# que el coordinador lo haya recibido. Aca importa mas todavia, porque despues
# de esto Thalos deja de proponer pasos: un coordinador encendido sin encargo
# no le pide nada a nadie y nadie se entera.
# shellcheck source=../../hooks/lib/ack.sh
. "$SYS/hooks/lib/ack.sh"
# shellcheck source=../../hooks/lib/agent-events.sh
. "$SYS/hooks/lib/agent-events.sh"
set +e
thalos_ack_send "$TARGET" "$esc"
prc=$?
set -e
out="${THALOS_ACK_OUT:-}"

if [ "$prc" -eq 0 ]; then
    thalos_evento_agente thalos.agent.ack_confirmed "$FEAT" \
        "{\"target\":\"$TARGET\",\"role\":\"coordinador\"}"
elif [ "$prc" -eq 1 ]; then
    thalos_evento_agente thalos.agent.ack_missing "$FEAT" \
        "{\"target\":\"$TARGET\",\"role\":\"coordinador\"}"
fi
if [ "$prc" -eq 1 ]; then
    echo ""
    echo "  FALL el encargo no le llego al coordinador (NOT_DELIVERED)"
    echo ""
    echo "  Se envio y el agente nunca cambio de estado."
    echo "  Una sesion encendida sin encargo es un agente esperando sin saber que."
    printf '  Soltala con  thalos feature release %s\n' "$FEAT"
    exit 5
fi
if [ "$prc" -ne 0 ]; then
    echo ""
    echo "  FALL el coordinador arranco pero no recibio su encargo"
    printf '%s\n' "$out" | sed 's/^/    /' | head -3
    echo ""
    echo "  Una sesion encendida sin encargo es un agente esperando sin saber que."
    printf '  Soltala con  thalos feature release %s\n' "$FEAT"
    exit 5
fi

thalos_agent_ack_set "$FEAT"

echo ""
printf '  ok   %s recibio su encargo (ACK observado)\n' "$TARGET"
echo ""
echo "  Thalos deja de proponer pasos. Desde aca decide el coordinador."
printf '  Para retomar el control:  thalos feature release %s\n' "$FEAT"
exit 0
