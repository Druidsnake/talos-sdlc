#!/bin/sh
# thalos feature - ejecucion de features. Ver thalos-0.0.7.md secciones 30 y 22.5.
#
# start recorre las transiciones F1 y F2 de la tabla 22.5:
#   F1  ->  FEATURE_READY          READY_GATE, evidencia ProgramPlanEntry + DependencySet
#   F2  ->  FEATURE_IN_PROGRESS    READY_GATE + lease, evidencia LockLease + IssueRef + BranchRef
#
# Ninguna la fuerza: produce la evidencia, deja que el gate decida y solo
# avanza si el gate autoriza.
#
# Sale 0 ok, 2 precondition fallida, 3 gate rechazado, 4 needs_human.

set -eu

SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

PLAN=orchestration/program-plan.json
LOCKS=orchestration/locks.json
EVDIR=orchestration/evidence

usage() {
    cat <<'USAGE'
thalos feature - ejecucion de features

USO
    thalos feature start <ID>      lleva la feature a FEATURE_IN_PROGRESS
    thalos feature dispatch <ID> --role <ROL> [--pane <PANE>] [--kind KIND]
                                  despacha un agente con rol y alcance activos
                                  sin --pane, Thalos crea uno
    thalos feature advance <ID> --to <ESTADO>
                                  ejecuta la transicion si el gate autoriza
    thalos feature next <ID>       que transiciones salen del estado actual
    thalos feature work <ID> [--agent <NOMBRE>] [--timeout <SEG>]
                                  le da al agente despachado el trabajo de la
                                  feature. Sin --agent usa el que registro
                                  dispatch, si lo produjo el adapter ligado
    thalos feature commit <ID>     observa git y sella CommitRef
    thalos feature pr <ID>         abre el PR y sella PullRequestRef
    thalos feature checks <ID>     pide los checks al CI y sella CheckRunSet
    thalos feature collect <ID>    recoge el entregable del rol como evidencia
    thalos feature test <ID> --pane <PANE> --command "<CMD>"
                                  corre una verificacion y sella LocalTestReport
    thalos feature list            estado de todas las features del plan
    thalos feature show <ID>       detalle de una feature
    thalos feature release <ID>    suelta el rol activo

QUE HACE start
    1. verifica que la feature exista en el plan y que sus dependencias esten
       terminadas
    2. produce ProgramPlanEntry y DependencySet como evidencia sellada
    3. transiciona a FEATURE_READY si READY_GATE lo autoriza          (F1)
    4. toma el lease de la rama, crea issue y rama por el
       CoordinationAdapter, y sella LockLease, IssueRef y BranchRef
    5. transiciona a FEATURE_IN_PROGRESS si el gate lo autoriza       (F2)

    Cada paso emite su evento y persiste el GateResult que lo autorizo. Si un
    gate rechaza, se emite thalos.transition.rejected y no se avanza.

    El adapter que crea issue y rama sale del registry, no esta cableado.
    En dry-run-only las operaciones se simulan y quedan en el ledger.

QUE HACE dispatch
    1. verifica que la feature este en FEATURE_IN_PROGRESS
    2. verifica que el rol exista en el registro de scope
    3. activa el rol: a partir de ahi toda escritura del agente pasa por el
       mecanismo 2 y se deniega fuera de write_paths
    4. compone el brief -instrucciones del rol + alcance concreto- y arranca
       el agente por el ExecutionAdapter

    El rol lo fija Thalos, no lo elige el agente. Un rol desconocido no se
    despacha: sin scope, el bloqueo dejaria pasar todo.

SALIDA
    0  la feature quedo en FEATURE_IN_PROGRESS
    1  error de uso
    2  precondition fallida
    3  un gate rechazo la transicion
    4  requiere decision humana
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

# shellcheck source=../../hooks/lib/transition.sh
. "$SYS/hooks/lib/transition.sh"
# shellcheck source=../../hooks/lib/role.sh
. "$SYS/hooks/lib/role.sh"
# shellcheck source=../../hooks/lib/resolve-capability.sh
. "$SYS/hooks/lib/resolve-capability.sh"
# shellcheck source=../../hooks/lib/agent-ref.sh
. "$SYS/hooks/lib/agent-ref.sh"
# shellcheck source=../../hooks/lib/model.sh
. "$SYS/hooks/lib/model.sh"

PY=$(thalos_python) || { echo "thalos: no hay python3" >&2; exit 2; }

sub="${1:-list}"
[ $# -gt 0 ] && shift
FEAT="${1:-}"

need_plan() {
    [ -f "$PLAN" ] || { echo "thalos: no existe $PLAN" >&2
                        echo "thalos: thalos plan init" >&2; exit 2; }
}

# ---------- list ----------

if [ "$sub" = list ]; then
    need_plan
    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  %-6s %-38s %-22s %s\n' ID TITULO ESTADO RIESGO
    "$PY" - "$PLAN" <<'PYEOF' | while IFS='	' read -r fid title risk; do
import json, sys
for f in json.loads(open(sys.argv[1]).read())["features"]:
    print(f"{f['id']}\t{f['title'][:36]}\t{f['risk']}")
PYEOF
        st=$(thalos_feature_state "$fid" 2>/dev/null || echo "-")
        printf '  %-6s %-38s %-22s %s\n' "$fid" "$title" "$st" "$risk"
    done
    echo ""
    echo "  - = todavia no arranco"
    exit 0
fi

# ---------- show ----------

if [ "$sub" = show ]; then
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    sf="orchestration/features/$FEAT/state.json"
    [ -f "$sf" ] || { echo "thalos: $FEAT no arranco todavia" >&2; exit 2; }
    "$PY" -m json.tool "$sf"
    exit 0
fi

# ---------- next ----------

if [ "$sub" = next ]; then
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    est=$(thalos_feature_state "$FEAT" 2>/dev/null || echo "")
    [ -n "$est" ] || { echo "thalos: $FEAT no arranco todavia" >&2; exit 2; }
    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  %s esta en %s\n\n' "$FEAT" "$est"
    if thalos_is_terminal feature "$est"; then
        echo "  Estado terminal: no tiene transiciones de salida (regla 22.6.9)."
        exit 0
    fi
    printf '  %-4s %-24s %-18s %-14s %s\n' ID HACIA GATE ACTOR EVIDENCIA
    # shellcheck disable=SC2034
    thalos_transitions_from feature "$est" | while IFS='	' read -r mm id from to gate cond actor req event; do
        printf '  %-4s %-24s %-18s %-14s %s\n' "$id" "$to" "$gate" "$actor" "$req"
    done
    echo ""
    echo "  thalos feature advance $FEAT --to <ESTADO>"
    exit 0
fi

# ---------- advance ----------
#
# No hace falta un comando por transicion: la tabla ya describe las 27 y el
# ejecutor ya es generico. Esto es la superficie que las recorre.

if [ "$sub" = advance ]; then
    TO=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --to) TO="${2:?falta el estado destino}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    [ -n "$TO" ]   || { echo "thalos: falta --to" >&2; exit 1; }

    est=$(thalos_feature_state "$FEAT" 2>/dev/null || echo "")
    [ -n "$est" ] || { echo "thalos: $FEAT no arranco todavia" >&2
                       echo "thalos: thalos feature start $FEAT" >&2; exit 2; }

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  feature  %s\n  desde    %s\n  hacia    %s\n' "$FEAT" "$est" "$TO"

    tid=$(thalos_transition_id feature "$est" "$TO" 2>/dev/null || echo "")
    if [ -z "$tid" ]; then
        echo ""
        printf '  FALL no existe la transicion %s -> %s en la tabla 22.5\n' "$est" "$TO"
        echo ""
        echo "  Regla 22.6.2: toda transicion no listada se rechaza."
        echo "  Ver las disponibles con  thalos feature next $FEAT"
        exit 3
    fi
    printf '  %-8s %s\n\n' "id" "$tid"

    # Regla 22.6.3: la evidencia se presenta ANTES de evaluar el gate. Si la
    # transicion exige LockRelease, soltar los leases no puede ser consecuencia
    # de haber transicionado: seria pedir como requisito algo que solo existe
    # despues. Se sueltan primero y se acuña la evidencia.
    req=$(thalos_transition_requires feature "$est" "$TO" 2>/dev/null || echo "-")
    case "$req" in
        *LockRelease*)
            thalos_release_feature_leases "$FEAT" | while read -r l; do
                [ -n "$l" ] && printf '  ok   lease liberado %s\n' "$l"
            done
            ;;
    esac

    set +e
    out=$(thalos_transition_exec feature "$est" "$TO" "$EVDIR" "$FEAT")
    rc=$?
    set -e
    printf '%s\n' "$out" | while IFS='=' read -r k v; do
        case "$k" in
            gate_result) [ -n "$v" ] && printf '  ok   GateResult %s\n' "$(basename "$v")" ;;
            event)       [ -n "$v" ] && printf '  ok   evento %s\n' "$v" ;;
            seq)         [ -n "$v" ] && printf '  ok   seq %s\n' "$v" ;;
            lease_released) printf '  ok   lease liberado %s\n' "$v" ;;
        esac
    done

    echo ""
    case "$rc" in
        0) printf '  %s quedo en %s\n' "$FEAT" "$TO"
           thalos_is_terminal feature "$TO" && \
             echo "  Estado terminal: los leases de la feature quedaron liberados (regla 22.6.8)." ;;
        4) echo "  needs_human: registra la decision con  thalos human decide $FEAT --decision <D>" ;;
        *) echo "  el gate rechazo la transicion: la feature no avanzo"
           echo "  Se emitio thalos.transition.rejected (regla 22.6.2)." ;;
    esac
    exit "$rc"
fi

# ---------- work ----------
#
# dispatch arranca al agente con su rol y su alcance, pero no le dice que
# construir. Esto le entrega el trabajo concreto de la feature y espera a que
# termine.

if [ "$sub" = work ]; then
    TARGET=""
    # Cuanto se espera al entregable. El plan declara max_wall_minutes por
    # feature y ese es el numero que manda; --timeout existe para poder
    # ejercitar el camino de "no entrego" sin esperar el limite real.
    ESPERA_S=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --agent)   TARGET="${2:?falta el agente}"; shift 2 ;;
            --timeout) ESPERA_S="${2:?falta el timeout en segundos}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    need_plan
    # La referencia la dejo dispatch: no hace falta repetirla en cada paso.
    #
    # Se apunta al NOMBRE del agente, no al pane donde quedo. El nombre lo puso
    # Thalos al despachar y no cambia; el pane es del runtime, puede quedar
    # vacio, reciclado o con el shell de una persona. Es la misma leccion que
    # ya aplica la reconciliacion de start_agent en la capa de adapters.
    if [ -z "$TARGET" ]; then
        set +e
        thalos_agent_ref_check "$FEAT"; _arc=$?
        set -e
        if [ "$_arc" -ne 0 ]; then
            echo "thalos ${THALOS_VERSION:-?}"
            echo ""
            thalos_agent_ref_explain "$FEAT" "$_arc"
            exit 2
        fi
        TARGET=$(thalos_agent_ref_field "$FEAT" name)
    fi

    ROLE=$(thalos_role_current 2>/dev/null || echo "")
    [ -n "$ROLE" ] || { echo "thalos: no hay rol activo; despacha primero" >&2
                        echo "thalos: thalos feature dispatch $FEAT --role Developer" >&2
                        exit 2; }

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  feature  %s\n  rol      %s\n  agente   %s\n\n' "$FEAT" "$ROLE" "$TARGET"

    # ---------- la task ----------
    #
    # El rol NO PUEDE trabajar sobre una task que no existe. Su contrato de
    # salida exige declared_scope, su brief le dice "lee la task y su
    # declared_scope", y nadie escribia ninguna: se le mandaba la descripcion
    # de la feature y se le pedia un resultado sobre una task inventada. Un
    # agente serio se niega -y se nego-, y uno complaciente inventa el alcance,
    # que es peor.
    #
    # Cuando hay un coordinador, la descomposicion es suya (seccion 30.2). En
    # el camino del loop no hay coordinador, asi que el nucleo deriva UNA task
    # de la feature: es lo unico que puede hacer sin criterio propio.
    TAREA="orchestration/features/$FEAT/tasks/T01"
    mkdir -p "$TAREA"
    ALCANCE=$(thalos_role_scope "$ROLE" | awk -F'\t' '$1 == "allow" {print $2}')
    # El entregable sale del CONTRATO DEL ROL, no de una ruta cableada. Fijar
    # aca el task-result del Developer hacia que a un Reviewer despachado se le
    # pidiera el artefacto de otro rol: escribia -o no escribia- en el lugar
    # equivocado, y el gate seguia sin ver su Review.
    BLOQUEO="orchestration/features/$FEAT/tasks/T01/blocker.json"
    ESQUEMA=$(thalos_role_output_schema "$ROLE" 2>/dev/null || echo "")
    SALIDA=$(thalos_role_output_path "$ROLE" "$FEAT" T01 2>/dev/null || echo "")
    if [ -z "$ESQUEMA" ] || [ -z "$SALIDA" ]; then
        echo "  FALL el rol $ROLE no declara entregable en el registro de salida" >&2
        echo "  Sin contrato de salida no hay como saber si trabajo." >&2
        exit 2
    fi
    if ! "$PY" - "$PLAN" "$FEAT" "$ROLE" "$TAREA/task.json" "$ALCANCE" "$ESQUEMA" "$SALIDA" <<'PYEOF'
import json, sys, datetime
plan = json.loads(open(sys.argv[1]).read())
fid, rol, destino, alcance = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
esquema, salida = sys.argv[6], sys.argv[7]
f = next((x for x in plan["features"] if x["id"] == fid), None)
if f is None:
    raise SystemExit(2)
task = {
    "schema_version": 1,
    "feature_id": fid,
    "task_id": "T01",
    "role": rol,
    "title": f["title"],
    "description": f.get("description") or "",
    "created_at": datetime.datetime.now(datetime.timezone.utc)
                  .strftime("%Y-%m-%dT%H:%M:%SZ"),
    # El nucleo la derivo del plan, no un rol con criterio. Decirlo importa:
    # una task compuesta por un coordinador lleva role:FeatureLead.
    "created_by": "component:Orchestrator",
    # El alcance NO se inventa: es el del rol, el mismo que el hook impone.
    # Declarar uno mas ancho seria prometer permisos que el bloqueo deniega.
    "declared_scope": [g for g in alcance.split("\n") if g.strip()],
    "spec_refs": [f"spec/{r}" for r in (f.get("spec_refs") or [])],
    "acceptance_refs": [f"spec/{r}" for r in (f.get("acceptance_refs") or [])],
    "output": {"schema": esquema, "path": salida},
    # La otra salida. Un encargo con una sola forma de terminar obliga al rol
    # a contestar en prosa cuando no puede, y la prosa Thalos no la lee: espera
    # un archivo que no llega y pierde el motivo.
    "blocked": {
        "schema": "blocker",
        "path": f"orchestration/features/{fid}/tasks/T01/blocker.json",
    },
}
open(destino, "w").write(json.dumps(task, indent=2) + "\n")
PYEOF
    then
        echo "thalos: $FEAT no esta en el plan" >&2
        exit 2
    fi

    # Mecanismo 1: si Thalos produce un artefacto invalido, falla aca y no
    # despues, en el gate, con el agente ya trabajando sobre un encargo roto.
    if ! "$SYS/hooks/validate-artifact.sh" task "$TAREA/task.json" >/dev/null 2>&1; then
        echo "  FALL la task que compuso Thalos no valida contra su schema"
        "$SYS/hooks/validate-artifact.sh" task "$TAREA/task.json" 2>&1 | sed 's/^/    /' | head -5
        exit 2
    fi
    printf '  task     %s (alcance: %s)\n' "$TAREA/task.json" \
        "$(printf '%s' "$ALCANCE" | tr '\n' ' ')"

    encargo=$("$PY" - "$FEAT" "$TAREA" <<'PYEOF'
import json, sys
fid, tdir = sys.argv[1], sys.argv[2]
t = json.loads(open(f"{tdir}/task.json").read())
partes = [
    f"Tu task es {t['task_id']} de {fid}: {t['title']}.",
    "",
    "Esta definida en:",
    f"  {tdir}/task.json",
    "Leela primero: ahi esta tu declared_scope y donde va tu entregable.",
    "",
    t.get("description") or "",
    "",
    "El spec aprobado manda. Leelo antes de escribir:",
    *[f"  {r}" for r in (t.get("spec_refs") or [])],
    *[f"  {r}" for r in (t.get("acceptance_refs") or [])],
    "",
    "Escribi el codigo Y sus tests. Un criterio de aceptacion sin test no",
    "esta cumplido. Los casos de rechazo son obligatorios.",
    "",
    "Cuando termines, deja tu entregable en:",
    f"  {t['output']['path']}",
    f"que tiene que validar contra el schema {t['output']['schema']}.",
    "Sin ese archivo tu trabajo no existe para el sistema.",
    "",
    "SI NO PODES TERMINAR, no contestes en prosa: Thalos no la lee.",
    "Escribi este archivo y detenete:",
    f"  {t['blocked']['path']}",
    "con reason (por que), needs (que haria falta) y tried (que intentaste).",
    "Un bloqueo dicho asi lo lee el sistema; dicho en un mensaje se pierde.",
    "",
    # El CommitRef es evidencia que Thalos OBSERVA de git, no una mutacion que
    # ordene. Si nadie commitea, no hay nada que observar y la feature se
    # planta con "el agente todavia no commiteo su trabajo". Pedirlo aca es la
    # unica forma de que el hecho exista.
    "Y commitea lo que hiciste. Thalos no commitea por vos: lee git para",
    "sellar el CommitRef, y sin commit no hay nada que leer.",
    "Un solo commit, conventional commits, sin agregar co-autores.",
]
print("\n".join(x for x in partes if x is not None))
PYEOF
)

    printf '%s\n' "$encargo" | sed 's/^/    /' | head -6
    echo "    ..."
    echo ""

    # El texto va como semantic_args del adapter: quien ejecuta es el
    # ExecutionAdapter, y el nucleo no sabe con que agente esta hablando.
    esc=$(printf '%s' "$encargo" | "$PY" -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')

    # No alcanza con que el adapter acepte el envio: eso confirma que la
    # terminal recibio las teclas, no que el agente recibio el encargo. El ACK
    # se OBSERVA como transicion de estado posterior al envio, sin pedirle nada
    # al agente. Ver thalos-mensajeria-0.0.1.md seccion 7.
    # shellcheck source=../../hooks/lib/ack.sh
    . "$SYS/hooks/lib/ack.sh"
    set +e
    thalos_ack_send "$TARGET" "$esc"
    rc=$?
    set -e
    out="${THALOS_ACK_OUT:-}"

    # NOT_DELIVERED: se agotaron los intentos y el encargo nunca entro. Es un
    # error de clase TRANSIENT (35.1), no un veredicto sobre el agente, y por
    # eso NO consume iteracion de presupuesto: no hubo encargo que ejecutar.
    if [ "$rc" -eq 1 ]; then
        echo "  FALL el encargo no le llego al agente (NOT_DELIVERED)"
        echo ""
        echo "  El adapter lo envio y el agente nunca cambio de estado."
        echo "  No se consumio iteracion: no hubo encargo que ejecutar."
        echo ""
        printf '  Si %s ya no responde, la referencia quedo vieja:\n' "$TARGET"
        printf '    thalos feature release %s\n    thalos feature dispatch %s --role %s\n' \
            "$FEAT" "$FEAT" "$ROLE"
        exit 5
    fi
    if [ "$rc" -ne 0 ]; then
        echo "  FALL el ExecutionAdapter no pudo entregar el trabajo"
        # Un agente puede MORIRSE: que se haya despachado no prueba que siga
        # vivo. Si el backend no lo encuentra, la referencia esta obsoleta y
        # el paso que corresponde es despachar de nuevo, no reintentar este.
        echo "  Si el agente $TARGET ya no existe, la referencia quedo vieja:"
        printf '    thalos feature release %s\n    thalos feature dispatch %s --role %s\n' \
            "$FEAT" "$FEAT" "$ROLE"
        echo ""
        # El motivo del backend va ULTIMO, no primero: quien mira esto en la
        # consola del loop ve las ultimas lineas, y con la ayuda abajo el error
        # real quedaba tapado justo cuando hacia falta.
        echo "  lo que dijo el adapter:"
        printf '%s\n' "$out" | sed 's/^/    /' | tail -3
        exit 5
    fi
    echo "  ok   el agente recibio el encargo (ACK observado)"

    # El ACK se persiste porque lo consulta la tabla de veredictos DESPUES,
    # desde otro proceso. Sin el, un `done` en reposo -nunca recibio nada- es
    # indistinguible de un `done` de terminacion.
    thalos_agent_ack_set "$FEAT"

    # Cada encargo consume una iteracion (regla 33.3). Sin esto el loop
    # reencarga para siempre: la primera vez el ledger lo deja pasar, y de ahi
    # en adelante devuelve already_exists sin hacer nada, asi que la condicion
    # "no hay entregable" nunca cambia. El limite de iteraciones del
    # presupuesto ES el limite de reintentos; no hace falta inventar otro.
    #
    # Se consume ACA y no antes: un encargo que no entro no gasta iteracion
    # (regla 7.3.3), y ese camino ya salio mas arriba.
    "$SYS/cli/thalos" budget consume "$FEAT" 0 1 0 >/dev/null 2>&1 || true

    # Esperar a que el agente se asiente. Devolver apenas se entrega el prompt
    # deja a quien llama sin forma de saber si hubo trabajo.
    # Se espera al ENTREGABLE, no a un estado.
    #
    # wait_agent devuelve al primer estado asentado, y un agente se asienta
    # apenas recibe el prompt -antes de empezar a trabajar-. Con eso el paso
    # miraba el disco, no encontraba nada y reportaba ok igual: el loop lo
    # tomaba por avance, volvia a encargar lo mismo y quemaba las iteraciones
    # del presupuesto sin que nadie hubiera hecho nada.
    #
    # La condicion de terminacion de este paso es el artefacto. Un estado del
    # runtime no lo sustituye.
    if [ -z "$ESPERA_S" ]; then
        ESPERA_S=$("$PY" - "$PLAN" "$FEAT" <<'PYWALL'
import json, sys
plan = json.loads(open(sys.argv[1]).read())
f = next((x for x in plan.get("features", []) if x.get("id") == sys.argv[2]), None)
m = ((f or {}).get("budget") or {}).get("max_wall_minutes")
print(int(m) * 60 if m else 900)
PYWALL
)
    fi
    # En simulacion no hay a quien esperar: el adapter no ejecuta nada, asi
    # que el entregable no va a aparecer nunca y esperar el plazo entero es
    # tiempo tirado. El adapter lo declara en su respuesta; no se adivina.
    case "$out" in
        *'"dry_run":true'*)
            echo "  --   el ExecutionAdapter esta simulando: no hay entregable que esperar"
            echo ""
            echo "  En modo simulacion nadie ejecuta el encargo (regla 37.4.4.2)."
            exit 3
            ;;
    esac

    printf '  ..   esperando el entregable del agente (hasta %ss)\n' "$ESPERA_S"
    # wait_agent devuelve cuando el agente SE ASIENTA. Un agente asentado ya
    # no esta trabajando: volver a esperarlo es esperar a alguien que se fue.
    #
    # Antes el bucle hacia justo eso -reesperaba a un agente quieto y dormia
    # hasta agotar el presupuesto-, asi que "nunca arranco" y "trabaja lento"
    # costaban lo mismo: media hora. La diferencia importa, y se puede ver:
    # trabajando se mide en el estado, terminado se mide en el artefacto.
    _limite=$(( $(date +%s) + ESPERA_S ))
    _quieto_desde=""
    while :; do
        set +e
        espera=$(thalos_capability_run ExecutionAdapter wait_agent \
                 "{\"target\":\"$TARGET\",\"timeout_ms\":\"900000\"}" 2>&1)
        set -e
        [ -f "$SALIDA" ] && break
        # El bloqueo termina la espera igual que el entregable: son las dos
        # formas validas de terminar un encargo.
        [ -f "$BLOQUEO" ] && break
        case "$espera" in
            *'"state":"working"'*)
                _quieto_desde=""
                ;;
            *)
                # Asentado y sin entregable. Se le da una gracia por si se
                # asienta entre tandas, y si sigue quieto no hay a quien
                # esperarle.
                [ -n "$_quieto_desde" ] || _quieto_desde=$(date +%s)
                if [ "$(( $(date +%s) - _quieto_desde ))" -ge 90 ]; then
                    break
                fi
                ;;
        esac
        [ "$(date +%s)" -ge "$_limite" ] && break
        sleep 5
    done

    # Bloqueado es bloqueado cuando SIGUE bloqueado al vencer el plazo.
    #
    # El runtime muestra cosas y las resuelve solo: un agente que trabaja pasa
    # por estados momentaneos de bloqueo. Cortar en la primera lectura -o en la
    # segunda- abortaba el paso de un agente que estaba trabajando bien.
    if [ ! -f "$SALIDA" ]; then
        case "$espera" in
            *'"state":"blocked"'*)
                echo "  --   el agente sigue BLOQUEADO esperando una decision"
                echo ""
                echo "  No fracaso ni termino: su runtime le esta pidiendo permiso"
                echo "  para algo y no puede seguir hasta que alguien conteste."
                printf '  Mira su pane:  %s\n' "$(thalos_agent_ref_field "$FEAT" pane 2>/dev/null || echo '?')"
                exit 4
                ;;
        esac
    fi

    if [ -f "$BLOQUEO" ]; then
        echo "  --   el agente se BLOQUEO y lo dejo dicho"
        echo ""
        "$SYS/hooks/validate-artifact.sh" blocker "$BLOQUEO" >/dev/null 2>&1 \
            && printf '  el bloqueo valida contra su schema\n' \
            || printf '  ojo: el bloqueo NO valida contra blocker.schema.json\n'
        "$PY" - "$BLOQUEO" <<'PYBLOQ' | sed 's/^/    /'
import json, sys
b = json.loads(open(sys.argv[1]).read())
print(f"motivo:  {b.get('reason','-')}")
if b.get("kind"):
    print(f"clase:   {b['kind']}")
if b.get("needs"):
    print(f"necesita: {b['needs']}")
for x in (b.get("tried") or [])[:4]:
    print(f"intento: {x}")
PYBLOQ
        echo ""
        printf '  %s\n' "$BLOQUEO"
        echo "  No es un fracaso del paso: es una respuesta que el sistema puede leer."
        exit 4
    fi

    # El encargo pide DOS cosas al Developer: el entregable y el commit. Un
    # agente que deja el archivo y se detiene cumplio la mitad, y el paso
    # siguiente falla diciendo que no commiteo -que es cierto y llega tarde-.
    #
    # Se le recuerda una vez, dentro del mismo encargo. No consume otra
    # iteracion del presupuesto porque no es un encargo nuevo: es el mismo, sin
    # terminar.
    _base=$(cat "orchestration/features/$FEAT/.base-sha" 2>/dev/null || echo "")
    if [ -f "$SALIDA" ] && [ -n "$_base" ] && [ "$ROLE" = Developer ] \
       && [ "$(git rev-parse HEAD 2>/dev/null || echo "$_base")" = "$_base" ]; then
        printf '  ..   dejo el entregable y no commiteo: se lo recuerdo\n'
        _rec="Dejaste tu entregable pero no commiteaste. Thalos lee git para sellar el CommitRef y sin commit no hay nada que leer. Commitea ahora lo que hiciste: un solo commit, conventional commits, sin co-autores."
        _rec_esc=$(printf '%s' "$_rec" | "$PY" -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')
        set +e
        thalos_capability_run ExecutionAdapter prompt_agent \
            "{\"target\":\"$TARGET\",\"text\":\"$_rec_esc\",\"timeout_ms\":\"300000\"}" >/dev/null 2>&1
        _lim2=$(( $(date +%s) + 300 ))
        while [ "$(git rev-parse HEAD 2>/dev/null || echo "$_base")" = "$_base" ]; do
            thalos_capability_run ExecutionAdapter wait_agent \
                "{\"target\":\"$TARGET\",\"timeout_ms\":\"300000\"}" >/dev/null 2>&1
            [ "$(date +%s)" -ge "$_lim2" ] && break
            sleep 5
        done
        set -e
    fi

    # Se busca el entregable QUE SE LE PIDIO, no el del Developer: cada rol
    # tiene el suyo y el de otro rol no prueba nada sobre este.
    if [ -f "$SALIDA" ]; then
        printf '  ok   el agente dejo su entregable: %s\n' "$SALIDA"
        exit 0
    fi
    echo "  --   el agente termino sin dejar entregable"
    echo ""

    # LO QUE HAYA DICHO NO SE PIERDE.
    #
    # Un agente que no puede seguir contesta como sabe: en prosa, con una
    # pregunta, a veces con ruido de su interfaz. Thalos esperaba un archivo
    # con un formato y descartaba todo lo demas, asi que el motivo -que
    # existia- no llegaba a nadie. La seccion 25 ya definia el canal; lo que
    # faltaba era usarlo.
    #
    # La estructura la pone Thalos: el sobre dice quien, a quien y sobre que.
    # El cuerpo es lo que se leyo, tal cual, sin exigirle forma.
    set +e
    _dicho=$(thalos_capability_run ExecutionAdapter read_agent \
             "{\"target\":\"$TARGET\",\"lines\":\"120\"}" 2>&1)
    set -e
    _cuerpo=$(printf '%s' "$_dicho" | "$PY" -c '
import json, sys
crudo = sys.stdin.read()
try:
    d = json.loads(crudo)
    print((d.get("result") or {}).get("output") or crudo)
except Exception:
    print(crudo)
' 2>/dev/null || printf '%s' "$_dicho")

    _tmpm=$(mktemp)
    printf '%s' "$_cuerpo" > "$_tmpm"
    _msg=$("$PY" "$SYS/hooks/lib/message.py" send orchestration/messages \
           QUESTION "role:$ROLE" "human:operator" "${THALOS_RUN_ID:-r-unknown}" \
           "$FEAT" T01 "$_tmpm" 2>/dev/null || echo "")
    rm -f "$_tmpm"

    echo "  Sin ese archivo su trabajo no existe para el sistema."
    printf '  Se esperaba:  %s\n' "$SALIDA"
    if [ -n "$_msg" ]; then
        echo ""
        printf '  Lo que dijo quedo registrado como %s\n' "$_msg"
        printf '  Leelo:      thalos message show %s\n' "$_msg"
        printf '  Contestale: thalos message answer %s --text "..."\n' "$_msg"
    fi
    printf '  Su pane:      %s\n' "$(thalos_agent_ref_field "$FEAT" pane 2>/dev/null || echo '?')"
    # Sale 3, no 0. Reportar exito sin haber producido el entregable hacia que
    # el loop lo contara como avance: reencargaba lo mismo hasta agotar las
    # iteraciones, y recien ahi decia que nada habia pasado. Un paso que no
    # produjo su evidencia no avanzo.
    exit 3
fi

# ---------- commit ----------
#
# El catalogo de la seccion 23.4 dice que CommitRef lo produce el
# CoordinationAdapter, pero la seccion 38.4 no define ninguna operacion de
# commit para ese adapter. Un commit no es una mutacion que Thalos ordene: es un
# hecho de git que Thalos OBSERVA. Por eso sale verifiable:true, y de la unica
# forma en que eso es cierto: el sha se puede revalidar contra el repo
# (regla 23.3.4).

if [ "$sub" = commit ]; then
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    rama="feature/$FEAT"
    if ! git rev-parse --verify --quiet "$rama" >/dev/null 2>&1; then
        rama=$(git rev-parse --abbrev-ref HEAD)
    fi
    sha=$(git rev-parse "$rama" 2>/dev/null || echo "")
    [ -n "$sha" ] || { echo "thalos: no se pudo leer el estado de git" >&2; exit 2; }

    # Un commit que no existe no se inventa: si no aparecio nada desde que la
    # feature arranco, no hay trabajo que referenciar.
    #
    # La base es donde estaba git al arrancar, no merge-base contra main.
    # Comparar la rama contra main falla cuando no hay rama de feature: la
    # rama resuelta ES main, merge-base(main, main) es el propio HEAD, y el
    # paso quedaba imposible de pasar culpando al agente de no haber
    # commiteado algo que si habia commiteado.
    base=$(cat "orchestration/features/$FEAT/.base-sha" 2>/dev/null || echo "")
    if [ -z "$base" ]; then
        base=$(git merge-base "$rama" main 2>/dev/null || echo "")
    fi
    if [ -n "$base" ] && [ "$base" = "$sha" ]; then
        echo "thalos: no hay commits nuevos desde que $FEAT arranco" >&2
        echo "thalos: el agente todavia no commiteo su trabajo" >&2
        exit 3
    fi
    if [ -z "$base" ]; then
        echo "thalos: no se sabe desde donde contar los commits de $FEAT" >&2
        echo "thalos: falta orchestration/features/$FEAT/.base-sha, que escribe  thalos feature start" >&2
        exit 2
    fi

    msg=$(git log -1 --pretty=%s "$sha" 2>/dev/null || echo "")
    mkdir -p "$EVDIR"
    evid="ev-$FEAT-commit-$(date -u +%Y%m%d%H%M%S)"
    cat > "$EVDIR/$evid.json" <<EOF2
{"id":"$evid","kind":"CommitRef","schema_version":1,
 "run_id":"${THALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"core:Orchestrator","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "digest":"pendiente","verifiable":true,
 "payload":{"sha":"$sha","branch":"$rama","message":"$(printf '%s' "$msg" | sed 's/"/\\"/g')"}}
EOF2
    "$PY" "$SYS/hooks/lib/evidence.py" seal "$EVDIR/$evid.json" >/dev/null

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  rama     %s\n  sha      %s\n  mensaje  %s\n' "$rama" "$sha" "$msg"
    printf '  sellada  CommitRef (verifiable: true, revalidable contra el repo)\n'
    exit 0
fi

# ---------- pr ----------
#
# Con la revision aprobada, la transicion a FEATURE_PR_OPEN pide un
# PullRequestRef y ningun comando lo producia: el ciclo se quedaba sin camino
# justo despues de aprobar. Abrir el PR no es una decision -la decision la tomo
# el Reviewer y la sello el gate-, es una mutacion en el proveedor, y el
# catalogo de la seccion 23.4 la asigna al CoordinationAdapter.

if [ "$sub" = pr ]; then
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    need_plan

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  feature  %s\n\n' "$FEAT"

    # No se abre un PR sobre trabajo que nadie reviso. El gate decide si se
    # avanza; esto solo evita producir un PR que ninguna transicion podria
    # usar, y con un veredicto que pide cambios seria peor: lo publicaria.
    _rev="orchestration/reports/$FEAT/review.json"
    _verd=$(sed -n 's/.*"verdict"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_rev" 2>/dev/null | head -1)
    if [ "$_verd" != approve ]; then
        printf '  FALL la revision de %s dice %s\n' "$FEAT" "${_verd:-que todavia no existe}"
        echo ""
        echo "  Un PR abierto sobre una revision que pide cambios publica el problema."
        exit 2
    fi

    _titulo=$("$PY" - "$PLAN" "$FEAT" <<'PYEOF'
import json, sys
plan = json.loads(open(sys.argv[1]).read())
f = next((x for x in plan["features"] if x["id"] == sys.argv[2]), None)
print(f"{sys.argv[2]}: {f['title']}" if f else sys.argv[2])
PYEOF
)
    set +e
    out=$(thalos_capability_run CoordinationAdapter open_pr \
          "{\"title\":\"$_titulo\",\"head\":\"feature/$FEAT\",\"base\":\"main\",\"feature\":\"$FEAT\"}" 2>&1)
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        echo "  FALL el CoordinationAdapter no pudo abrir el PR"
        printf '%s\n' "$out" | sed 's/^/    /' | head -3
        exit 5
    fi
    PR=$(printf '%s' "$out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
    URL=$(printf '%s' "$out" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$PR" ] || { echo "  FALL el adapter no devolvio un id de PR"; exit 5; }

    mkdir -p "$EVDIR"
    evid="ev-$FEAT-pr-$(date -u +%Y%m%d%H%M%S)"
    # verifiable:false. Lo que prueba que un PR existe es consultarlo en el
    # proveedor, no que nosotros hayamos pedido abrirlo (regla 23.3.6).
    cat > "$EVDIR/$evid.json" <<EOF3
{"id":"$evid","kind":"PullRequestRef","schema_version":1,
 "run_id":"${THALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"adapter:CoordinationAdapter","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "artifact_refs":[],"digest":"pendiente","verifiable":false,
 "payload":{"id":"$PR","url":"${URL:-null}","head":"feature/$FEAT","base":"main"}}
EOF3
    "$PY" "$SYS/hooks/lib/evidence.py" seal "$EVDIR/$evid.json" >/dev/null

    printf '  ok   PR %s abierto por el CoordinationAdapter\n' "$PR"
    printf '  sellada  PullRequestRef (verifiable: false: lo prueba el proveedor)\n'
    exit 0
fi

# ---------- checks ----------
#
# Con el PR abierto, la transicion a FEATURE_CHECKS_RUNNING pide un CheckRunSet
# y ningun comando lo producia. Thalos NO decide si las pruebas pasan: pide que
# corran y observa lo que el CIAdapter contesta. Por eso verifiable sale de la
# respuesta del adapter y no de aca: en dry-run no es verificable, y decir lo
# contrario haria que MERGE_GATE aprobara sobre una simulacion (regla 31).

if [ "$sub" = checks ]; then
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  feature  %s\n\n' "$FEAT"

    _pr=$("$PY" - "$EVDIR" <<'PYEOF'
import json, pathlib, sys
d = pathlib.Path(sys.argv[1])
pr = ""
for f in sorted(d.glob("*.json")) if d.is_dir() else []:
    try:
        ev = json.loads(f.read_text())
    except (json.JSONDecodeError, OSError):
        continue
    if ev.get("kind") == "PullRequestRef":
        pr = (ev.get("payload") or {}).get("id") or pr
print(pr)
PYEOF
)
    if [ -z "$_pr" ]; then
        echo "  FALL no hay PullRequestRef sellado: no hay PR sobre el que correr checks"
        printf '  Abrilo con  thalos feature pr %s\n' "$FEAT"
        exit 2
    fi

    set +e
    thalos_capability_run CIAdapter run_checks "{\"pr\":\"$_pr\",\"feature\":\"$FEAT\"}" >/dev/null 2>&1
    out=$(thalos_capability_run CIAdapter get_check_status "{\"pr\":\"$_pr\"}" 2>&1)
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        echo "  FALL el CIAdapter no pudo reportar el estado de los checks"
        printf '%s\n' "$out" | sed 's/^/    /' | head -3
        exit 5
    fi

    # verifiable lo dice el adapter, no Thalos. Un CheckRunSet simulado marcado
    # verificable dejaria pasar MERGE_GATE sobre nada.
    _verif=$(printf '%s' "$out" | sed -n 's/.*"verifiable"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)
    [ -n "$_verif" ] || _verif=false
    _concl=$(printf '%s' "$out" | sed -n 's/.*"conclusion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

    mkdir -p "$EVDIR"
    evid="ev-$FEAT-checks-$(date -u +%Y%m%d%H%M%S)"
    cat > "$EVDIR/$evid.json" <<EOF4
{"id":"$evid","kind":"CheckRunSet","schema_version":1,
 "run_id":"${THALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"adapter:CIAdapter","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "artifact_refs":[],"digest":"pendiente","verifiable":$_verif,
 "payload":{"pr":"$_pr","conclusion":"${_concl:-unknown}"}}
EOF4
    "$PY" "$SYS/hooks/lib/evidence.py" seal "$EVDIR/$evid.json" >/dev/null

    printf '  ok   checks pedidos al CIAdapter sobre el PR %s\n' "$_pr"
    printf '  sellada  CheckRunSet (conclusion: %s, verifiable: %s)\n' "${_concl:-unknown}" "$_verif"
    [ "$_verif" = true ] || echo "  En este modo el resultado NO es verificable: MERGE_GATE no lo va a aceptar."
    exit 0
fi

# ---------- collect ----------
#
# La otra mitad de la costura: ya controlamos que ENTRA al agente (rol y
# alcance); esto controla que SALE. El rol declara su entregable en
# config/roles.yaml y hasta ahora nadie lo recogia.

if [ "$sub" = collect ]; then
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    # El rol sale de la TASK, y el archivo de sesion es el respaldo.
    #
    # Al reves fallaba: recoger no necesita que el agente siga despachado -el
    # entregable ya esta en disco, escrito y firmado por un rol concreto-, y
    # un loop que retoma un ciclo a medias no tiene rol activo. El paso moria
    # con "no hay rol activo; nada que recoger" sobre un entregable que estaba
    # ahi, mandando a despachar de nuevo a alguien que ya habia trabajado.
    #
    # Es la misma leccion de siempre: el archivo de rol dice quien gobierna la
    # sesion AHORA, no quien produjo lo que hay que recoger.
    ROLE=""
    _tk="orchestration/features/$FEAT/tasks/T01/task.json"
    [ -f "$_tk" ] && ROLE=$(sed -n 's/.*"role"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_tk" | head -1)
    [ -n "$ROLE" ] || ROLE=$(thalos_role_current 2>/dev/null || echo "")
    [ -n "$ROLE" ] || { echo "thalos: no se sabe que rol produjo el entregable de $FEAT" >&2
                        echo "thalos: falta $_tk y no hay rol activo" >&2
                        exit 2; }

    schema=$(thalos_role_output_schema "$ROLE") || {
        echo "thalos: el rol $ROLE no declara entregable" >&2; exit 2; }
    patron=$(thalos_role_output_path "$ROLE" "$FEAT")

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  rol       %s\n  entregable %s\n  schema    %s\n\n' "$ROLE" "$patron" "$schema"

    # shellcheck disable=SC2086
    encontrados=$(ls $patron 2>/dev/null || true)
    if [ -z "$encontrados" ]; then
        echo "  FALL el agente no dejo su entregable"
        echo ""
        echo "  Sin ese archivo su trabajo no existe para el sistema."
        echo "  Ver roles/$(printf '%s' "$ROLE" | tr 'A-Z' 'a-z').md"
        exit 3
    fi

    mkdir -p "$EVDIR"
    n=0; malos=0
    for art in $encontrados; do
        printf '  %s\n' "$art"
        if ! "$SYS/hooks/validate-artifact.sh" "$schema" "$art" >/dev/null 2>&1; then
            printf '    FALL no valida contra %s.schema.json\n' "$schema"
            malos=$((malos + 1))
            continue
        fi
        printf '    ok   valida contra %s.schema.json\n' "$schema"

        kind=$(thalos_role_evidence_kind "$schema") || kind=TaskResultSet
        dg=$(shasum -a 256 "$art" 2>/dev/null | awk '{print $1}')
        evid="ev-$FEAT-$(basename "$art" .json)-$(date -u +%Y%m%d%H%M%S)-$n"
        # Regla 23.3.6: la evidencia producida por un agente NO es verificable
        # salvo que traiga salida de una herramienta determinista. Un entregable
        # que el agente escribio es su palabra, no una medicion.
        cat > "$EVDIR/$evid.json" <<EOF2
{"id":"$evid","kind":"$kind","schema_version":1,
 "run_id":"${THALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"role:$ROLE","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "artifact_refs":["$art"],"digest":"pendiente","verifiable":false,
 "payload":{"schema":"$schema","artifact_sha256":"$dg"}}
EOF2
        "$PY" "$SYS/hooks/lib/evidence.py" seal "$EVDIR/$evid.json" >/dev/null
        printf '    ok   sellada como %s (verifiable: false)\n' "$kind"
        n=$((n + 1))
    done

    echo ""
    if [ "$malos" -gt 0 ]; then
        echo "  $malos entregable(s) invalido(s): no se sellaron"
        echo "  Un entregable que no valida contra su schema no es evidencia."
        exit 3
    fi
    printf '  %s evidencia(s) recogida(s)\n' "$n"
    echo "  Es la palabra del agente, no una medicion: no satisface un gate critico."
    exit 0
fi

# ---------- test ----------
#
# La unica evidencia VERIFICABLE que el ExecutionAdapter puede producir hoy.
# Regla 30.4.3: LocalTestReport es evidencia de avance, no de pase.

if [ "$sub" = test ]; then
    PANE=""; CMD=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --pane)    PANE="${2:?falta el pane}"; shift 2 ;;
            --command) CMD="${2:?falta el comando}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    # El comando necesita una terminal PROPIA.
    #
    # Antes se reusaba el pane del agente, que es justo el unico que no sirve:
    # ahi corre su interfaz interactiva, no una shell. El comando se escribia
    # sobre el TUI, no se ejecutaba nunca, y el paso moria a los 120s diciendo
    # que el comando no termino -sin decir que jamas habia arrancado-.
    PROPIO=0
    if [ -z "$PANE" ]; then
        set +e
        _ses=$(thalos_capability_run ExecutionAdapter create_session \
               "{\"cwd\":\"$PROJ\",\"direction\":\"down\",\"label\":\"thalos-test-$FEAT\"}" 2>&1)
        _src=$?
        set -e
        if [ "$_src" -ne 0 ]; then
            echo "thalos ${THALOS_VERSION:-?}"
            echo ""
            echo "  FALL no se pudo abrir una terminal para correr la verificacion"
            printf '%s\n' "$_ses" | sed 's/^/    /' | tail -3
            exit 5
        fi
        PANE=$(printf '%s' "$_ses" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
        PROPIO=1
    fi
    [ -n "$PANE" ] || { echo "thalos: falta --pane y no hay uno registrado" >&2; exit 1; }
    if [ -z "$CMD" ]; then
        # Thalos no adivina como se prueba un proyecto: el stack lo decide.
        CMD=$(sed -n 's/^test_command:[[:space:]]*//p' "$SYS/config/system.yaml" 2>/dev/null | head -1)
        CMD=$(printf '%s' "$CMD" | sed 's/^"//;s/"$//')
    fi
    if [ -z "$CMD" ]; then
        echo "thalos: falta --command y el proyecto no declara test_command" >&2
        echo "thalos: agregalo a config/system.yaml; sin comando no hay medicion" >&2
        exit 2
    fi

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  feature  %s\n  comando  %s\n\n' "$FEAT" "$CMD"

    outdir="orchestration/reports/$FEAT"
    mkdir -p "$outdir" "$EVDIR"
    log="$outdir/localtest-$(date -u +%Y%m%d%H%M%S).log"
    rcfile="$log.rc"

    # La salida va a un archivo, no a la pantalla. Leer el pane es poco fiable:
    # lo que sale de la pantalla alternativa no vuelve, y el ancho del pane
    # decide cuanto se conserva. Un archivo es determinista.
    wrapped="{ $CMD ; } > $log 2>&1 ; echo \$? > $rcfile"
    # Si el adapter no pudo lanzar el comando, no tiene sentido esperar dos
    # minutos por un codigo de salida que nunca va a llegar.
    set +e
    disp=$(thalos_capability_run ExecutionAdapter run_command \
           "{\"pane\":\"$PANE\",\"command\":\"$wrapped\"}" 2>&1)
    drc=$?
    set -e
    if [ "$drc" -ne 0 ]; then
        echo "  FALL el ExecutionAdapter no pudo lanzar el comando"
        printf '%s\n' "$disp" | sed 's/^/    /' | head -3
        exit 5
    fi

    # Esperar el codigo de salida. Sin el no hay medicion, solo una suposicion.
    waited=0
    while [ ! -f "$rcfile" ] && [ "$waited" -lt 120 ]; do
        sleep 2; waited=$((waited + 2))
    done
    if [ ! -f "$rcfile" ]; then
        echo "  FALL el comando no termino en ${waited}s"
        echo "  Sin codigo de salida no hay evidencia: no se sella nada."
        exit 3
    fi

    rc=$(cat "$rcfile")
    # La terminal que abrio este paso la cierra este paso.
    if [ "$PROPIO" = 1 ]; then
        thalos_capability_run ExecutionAdapter close_session \
            "{\"pane\":\"$PANE\"}" >/dev/null 2>&1 || true
    fi
    printf '  exit     %s\n' "$rc"
    printf '  salida   %s\n\n' "$log"
    tail -6 "$log" 2>/dev/null | sed 's/^/    /'

    dg=$(shasum -a 256 "$log" 2>/dev/null | awk '{print $1}')
    evid="ev-$FEAT-localtest-$(date -u +%Y%m%d%H%M%S)"
    # verifiable: true. Es salida de una herramienta determinista con su codigo
    # de salida, no la afirmacion de un agente (regla 23.3.6).
    cat > "$EVDIR/$evid.json" <<EOF2
{"id":"$evid","kind":"LocalTestReport","schema_version":1,
 "run_id":"${THALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"adapter:ExecutionAdapter","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "artifact_refs":["$log"],"digest":"pendiente","verifiable":true,
 "payload":{"command":"$(printf '%s' "$CMD" | sed 's/"/\\"/g')","exit_code":$rc,"log_sha256":"$dg"}}
EOF2
    "$PY" "$SYS/hooks/lib/evidence.py" seal "$EVDIR/$evid.json" >/dev/null

    echo ""
    printf '  sellada  LocalTestReport (verifiable: true)\n'
    echo "  Regla 30.4.3: es evidencia de AVANCE, no de pase."
    echo "  El pase lo determina el CheckRunSet del CIAdapter."
    [ "$rc" -eq 0 ] && exit 0
    exit 3
fi

# ---------- release ----------

if [ "$sub" = release ]; then
    actual=$(thalos_role_current 2>/dev/null || echo "")
    thalos_role_deactivate
    # Lo que instalo el shim lo retira el shim. El nucleo no sabe que dejo:
    # eso es especifico del runtime.
    for _fd in orchestration/features/*; do
        [ -d "$_fd" ] || continue
        # Se barren TODOS los shims conocidos, no solo el que quedo anotado.
        #
        # El .runtime dice cual se uso la ultima vez. Si entre un despacho y
        # otro cambio el runtime -porque cambio el tier, o el proveedor-, lo
        # que dejo el anterior sobrevive: dos briefs conviviendo en la raiz y
        # un bloqueo registrado apuntando a un rol que ya nadie activo.
        #
        # Cada uninstall retira solo lo que su propio shim marco, asi que
        # correrlos todos es seguro y es la unica forma de no depender de que
        # el anotado sea el unico que dejo algo.
        rm -f "$_fd/.runtime"
        for _sd in $(grep -v '^#' "$SYS/hooks/agent/runtimes.tsv" 2>/dev/null \
                     | awk -F'\t' 'NF>1 {print $2}' | sort -u); do
            _sh="$SYS/hooks/agent/$_sd/install.sh"
            [ -x "$_sh" ] && "$_sh" "$PROJ" --uninstall 2>/dev/null | sed 's/^/  /'
        done
        _fid=$(basename "$_fd")
        # Thalos abrio la sesion: Thalos la cierra. Dejarla abierta acumula
        # paneles muertos ocupando pantalla, y quien mira la maquina no puede
        # distinguir un agente trabajando de uno que ya nadie gobierna.
        #
        # Un cierre fallido NO impide soltar el rol: el rol es lo que gobierna
        # la sesion, y quedarse con el rol tomado por un panel que no se pudo
        # cerrar es peor que un panel de mas.
        if _pane=$(thalos_agent_ref_field "$_fid" pane 2>/dev/null); then
            if [ -n "$_pane" ] && thalos_agent_ref_check "$_fid" 2>/dev/null; then
                if thalos_capability_run ExecutionAdapter close_session \
                       "{\"pane\":\"$_pane\"}" >/dev/null 2>&1; then
                    printf '  sesion %s cerrada\n' "$_pane"
                else
                    printf '  la sesion %s no se pudo cerrar: revisala a mano\n' "$_pane"
                fi
            fi
        fi
        # La referencia al agente se suelta con el rol. Sobrevivirla la deja
        # apuntando a un agente que ya nadie gobierna, y el paso siguiente le
        # manda trabajo igual.
        thalos_agent_ref_clear "$_fid"
    done
    if [ -n "$actual" ]; then
        echo "rol $actual liberado: Thalos ya no gobierna esta sesion"
    else
        echo "no habia rol activo"
    fi
    exit 0
fi

# ---------- dispatch ----------

if [ "$sub" = dispatch ]; then
    ROLE=""; PANE=""; KIND=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --role) ROLE="${2:?falta el rol}"; shift 2 ;;
            --pane) PANE="${2:?falta el pane}"; shift 2 ;;
            --kind) KIND="${2:?falta el kind}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }
    [ -n "$ROLE" ] || { echo "thalos: falta --role" >&2; exit 1; }

    # El tier sale de max(tier de la feature, minimo del rol), que es el
    # algoritmo de la seccion 20.5. Mirar solo la feature dejaba a un rol que
    # exige deep -un coordinador, un planificador- corriendo en fast porque la
    # feature era de riesgo bajo: el minimo del rol quedaba declarado y sin
    # efecto. El nucleo no nombra modelos: traduce por config/models.yaml (20.3).
    MODELO=""; PROVEEDOR=""
    if TIER=$(thalos_tier_resolve "$FEAT" "$ROLE" 2>/dev/null); then
        if _mp=$(thalos_model_for_tier "$TIER" 2>/dev/null); then
            MODELO=$(printf '%s' "$_mp" | cut -f1)
            PROVEEDOR=$(printf '%s' "$_mp" | cut -f2)
        fi
    fi
    # Sin --kind, el runtime es el proveedor que declara el tier. Cablear uno
    # por defecto haria que cambiar de proveedor en la config despachara igual
    # el agente de antes, con el modelo de otro.
    [ -n "$KIND" ] || KIND="$PROVEEDOR"
    [ -n "$KIND" ] || { echo "thalos: no hay runtime: pasa --kind o declara provider en config/models.yaml" >&2
                        exit 2; }

    echo "thalos ${THALOS_VERSION:-?}"
    echo ""

    # Un agente no se despacha sobre una feature que no arranco, ni sobre una
    # que ya termino.
    #
    # Antes se exigia FEATURE_IN_PROGRESS y nada mas. Eso estaba escrito para
    # un solo rol: el Reviewer trabaja con la feature en FEATURE_REVIEW, asi
    # que el loop proponia despacharlo y el despacho lo rechazaba mandandolo a
    # arrancar una feature que ya estaba arrancada.
    #
    # La condicion real es que la feature siga viva. Un estado terminal no
    # tiene transiciones de salida: eso lo dice la tabla, no una lista de
    # estados escrita a mano que habria que actualizar con cada rol nuevo.
    est=$(thalos_feature_state "$FEAT" 2>/dev/null || echo "")
    if [ -z "$est" ]; then
        printf '  FALL %s no arranco\n' "$FEAT"
        echo ""
        echo "  Un rol se despacha sobre una feature en curso. Arranca con:"
        echo "    thalos feature start $FEAT"
        exit 2
    fi
    if [ -z "$(thalos_transitions_from feature "$est" 2>/dev/null)" ]; then
        printf '  FALL %s esta en %s, que es terminal\n' "$FEAT" "$est"
        echo ""
        echo "  No hay nada que despachar sobre una feature que ya cerro."
        exit 2
    fi

    # Fail-closed: sin rol conocido no hay scope, y sin scope el bloqueo deja
    # pasar todo. Es preferible no despachar.
    if ! thalos_role_activate "$ROLE" "$FEAT"; then
        exit 2
    fi

    # Cambiar de rol suelta al agente anterior, y se hace ANTES de pedir la
    # sesion nueva. Haciendolo despues se cerraba el panel que la sesion recien
    # resuelta acababa de devolver -son el mismo- y start_agent fallaba con
    # "pane not found" sobre un panel que Thalos habia cerrado un segundo antes.
    _rolp=$(printf '%s' "$ROLE" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '_' | cut -c1-4)
    _previo=$(thalos_agent_ref_field "$FEAT" name 2>/dev/null || echo "")
    case "$_previo" in
        ""|*_"$_rolp") ;;
        *)
            if thalos_agent_ref_check "$FEAT" 2>/dev/null; then
                _ppane=$(thalos_agent_ref_field "$FEAT" pane 2>/dev/null || echo "")
                if [ -n "$_ppane" ] && thalos_capability_run ExecutionAdapter close_session \
                       "{\"pane\":\"$_ppane\"}" >/dev/null 2>&1; then
                    printf '  previo   %s soltado y su sesion %s cerrada\n' "$_previo" "$_ppane"
                fi
                thalos_agent_ref_clear "$FEAT"
            fi
            ;;
    esac
    # Sin pane, Thalos crea el suyo. Pedirle a una persona que elija uno la
    # obliga a saber cual esta libre, y el candidato obvio -donde esta
    # tipeando- es justo el que no sirve: ahi vive su shell.
    # Thalos se arma la ventana que necesita. El pane donde corre el
    # orquestador es su CONSOLA: ahi va el log, no un agente. Pedirle a una
    # persona que elija un pane la obliga a saber cual esta libre, y el
    # candidato obvio -donde esta tipeando- es justo el que no sirve.
    if [ -z "$PANE" ]; then
        set +e
        # El ROL es parte de la identidad de la sesion. Sin el, la
        # idempotency key de dos despachos sobre la misma feature es la misma:
        # el ledger le devolvia al Reviewer el panel del Developer, y dos
        # agentes no entran en un panel.
        _ses=$(thalos_capability_run ExecutionAdapter create_session \
               "{\"cwd\":\"$PROJ\",\"direction\":\"right\",\"role\":\"$ROLE\"}" 2>&1)
        _src=$?
        set -e
        if [ "$_src" -ne 0 ]; then
            echo "  FALL no se pudo abrir un pane para el agente"
            printf '%s\n' "$_ses" | sed 's/^/    /' | head -3
            thalos_role_deactivate
            exit 5
        fi
        PANE=$(printf '%s' "$_ses" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
        [ -n "$PANE" ] || { echo "  FALL el adapter no devolvio un pane"; thalos_role_deactivate; exit 5; }
        printf '  pane     %s (abierto por Thalos, al lado de la consola)\n' "$PANE"
    fi
    printf '  rol      %s (activo)\n' "$ROLE"
    printf '  feature  %s\n' "$FEAT"
    printf '  pane     %s\n\n' "$PANE"

    printf '  alcance de escritura que se le impone:\n'
    thalos_role_scope "$ROLE" | while IFS='	' read -r v g; do
        [ -z "$v" ] && continue
        printf '    %-9s %s\n' "$v" "$g"
    done
    echo ""

    brief_file="orchestration/features/$FEAT/brief.md"
    mkdir -p "$(dirname "$brief_file")"
    thalos_role_brief "$ROLE" "$FEAT" > "$brief_file"
    printf '  brief    %s (%s lineas)\n' "$brief_file" "$(wc -l < "$brief_file" | tr -d ' ')"

    # El nucleo compone la identidad. COMO se la entrega a un agente concreto
    # es especifico de su runtime, asi que lo hace el shim de ese runtime.
    #
    # Antes se pasaba --append-system-prompt con la RUTA del brief. Esa opcion
    # espera el texto: el agente recibia la cadena "orchestration/.../brief.md"
    # como system prompt y arrancaba sin instrucciones ni alcance, sin que nada
    # lo dijera.
    _rt=$(printf '%s' "$KIND" | tr 'A-Z' 'a-z')
    # El nombre del runtime lo elige el adapter; el del shim, el producto que
    # envuelve. Los une hooks/agent/runtimes.tsv, en la capa de shims.
    _shim=$(grep -v '^#' "$SYS/hooks/agent/runtimes.tsv" 2>/dev/null \
            | awk -F'\t' -v k="$_rt" '$1 == k {print $2; exit}')
    [ -n "$_shim" ] || _shim="$_rt"
    instalador="$SYS/hooks/agent/$_shim/install.sh"
    if [ -x "$instalador" ]; then
        if "$instalador" "$PROJ" "$SYS" "$brief_file"; then
            printf '  ok   enforcement instalado en el runtime %s\n' "$KIND"
        else
            echo "  FALL no se pudo instalar el enforcement en el runtime"
            echo "  Sin el hook, el alcance queda declarado y no impuesto."
            thalos_role_deactivate
            exit 5
        fi
    else
        echo "  FALL no hay shim de enforcement para el runtime $KIND"
        echo "  Despachar sin bloqueo seria despachar sin alcance."
        echo "  Ver hooks/agent/README.md: un shim por runtime."
        thalos_role_deactivate
        exit 2
    fi
    # agent_args son argumentos NATIVOS del agente: como se le pide un modelo
    # es vocabulario del runtime, asi que lo traduce su shim. El nucleo pasa el
    # modelo y el proveedor, y no sabe que bandera sale del otro lado.
    aargs=""
    _traductor="$SYS/hooks/agent/$_shim/agent-args.sh"
    if [ -n "$MODELO" ] && [ -x "$_traductor" ]; then
        aargs=$("$_traductor" "$MODELO" "$PROVEEDOR" || echo "")
    fi
    if [ -n "$aargs" ]; then
        printf '  modelo   %s (tier %s, proveedor %s)\n' "$MODELO" "${TIER:-?}" "$PROVEEDOR"
    else
        # Silencio aca significa "arranca con el modelo que tenga configurado el
        # runtime". Decirlo evita creer que el tier del plan se esta aplicando.
        printf '  modelo   el del runtime: el tier %s no se pudo traducir\n' "${TIER:-?}"
    fi
    # El nombre es la identidad del agente para todo lo que venga despues. Lo
    # elige Thalos, no el runtime: por eso se calcula una vez y se guarda.
    #
    # LLEVA EL PROYECTO ADENTRO. El espacio de nombres del runtime de ejecucion
    # es de la MAQUINA, no del proyecto: dos proyectos con una F001 pedian el
    # mismo thalos_f001. El adapter reconcilia por nombre -encuentra uno vivo y
    # no arranca otro-, asi que el segundo proyecto se quedaba sin agente y le
    # mandaba su trabajo al agente del primero, que corre en otro repo.
    #
    # Nadie lo notaba: el despacho decia ok, el prompt decia ok, y el entregable
    # no aparecia nunca en el proyecto que lo habia pedido.
    # LLEVA EL ROL ADENTRO por el mismo motivo. Sin el, despachar un Reviewer
    # sobre una feature que ya tuvo Developer reusaba al Developer: el adapter
    # reconcilia por nombre, encontraba uno vivo y no arrancaba otro. El
    # Reviewer terminaba siendo la misma sesion que escribio el codigo, con su
    # contexto y su brief, revisando su propio trabajo. Eso es exactamente lo
    # que la separacion de roles existe para impedir, y ningun mensaje lo
    # decia: el despacho reportaba ok.
    # El runtime acota el nombre: minusculas, digitos, - o _, hasta 32
    # caracteres. Cada parte se recorta para que el nombre entre entero; pasarse
    # hace fallar el arranque con invalid_agent_name, que es un error del
    # nombre y no del despacho, y cuesta encontrarlo.
    _proy=$(basename "$PROJ" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '_' | cut -c1-12 | sed 's/_*$//')
    _rol=$(printf '%s' "$ROLE" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '_' | cut -c1-4)
    AGENTE="thalos_${_proy}_$(printf '%s' "$FEAT" | tr 'A-Z' 'a-z' | cut -c1-6)_${_rol}"

    # Cambiar de rol suelta al agente anterior. La referencia se sobreescribe
    # unas lineas mas abajo, asi que sin esto el agente del rol viejo queda
    # corriendo con su panel abierto y sin nadie que lo gobierne ni lo pueda
    # cerrar despues: Thalos pierde el hilo de algo que abrio.
    _previo=$(thalos_agent_ref_field "$FEAT" name 2>/dev/null || echo "")
    if [ -n "$_previo" ] && [ "$_previo" != "$AGENTE" ] \
       && thalos_agent_ref_check "$FEAT" 2>/dev/null; then
        _ppane=$(thalos_agent_ref_field "$FEAT" pane 2>/dev/null || echo "")
        if [ -n "$_ppane" ] && thalos_capability_run ExecutionAdapter close_session \
               "{\"pane\":\"$_ppane\"}" >/dev/null 2>&1; then
            printf '  previo   %s soltado y su sesion %s cerrada\n' "$_previo" "$_ppane"
        fi
    fi
    set +e
    out=$(thalos_capability_run ExecutionAdapter start_agent \
          "{\"name\":\"$AGENTE\",\"kind\":\"$KIND\",\"pane\":\"$PANE\",\"agent_args\":\"$aargs\"}" 2>&1)
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        printf '  FALL el ExecutionAdapter no pudo arrancar el agente\n'
        printf '%s\n' "$out" | sed 's/^/    /' | head -4
        thalos_role_deactivate
        echo ""
        echo "  Rol liberado: no queda gobernando una sesion que no arranco."
        exit 5
    fi
    printf '  agente   %s arrancado por el ExecutionAdapter\n' "$AGENTE"
    # Quien siga -work, test- necesita saber a quien le habla. Se guarda CON el
    # id del adapter que lo produjo: un id de un ExecutionAdapter no significa
    # nada en otro, y sin procedencia el paso siguiente no puede darse cuenta.
    _ref=$(printf '%s' "$out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
    thalos_agent_ref_write "$FEAT" \
        "$(thalos_capability_impl ExecutionAdapter)" "$AGENTE" "$PANE" "$_ref"
    # Quien libere el rol necesita saber a que shim pedirle que se retire.
    printf '%s\n' "$_shim" > "orchestration/features/$FEAT/.runtime"
    echo ""
    echo "  El rol queda activo hasta  thalos feature release $FEAT"
    exit 0
fi

[ "$sub" = start ] || { echo "thalos: subcomando desconocido: $sub" >&2
                        echo "thalos: disponibles: start, dispatch, list, show, release" >&2; exit 1; }
[ -n "$FEAT" ] || { echo "thalos: falta el id de la feature" >&2; exit 1; }

# ---------- start ----------

need_plan
mkdir -p "$EVDIR" orchestration/features

echo "thalos ${THALOS_VERSION:-?}"
echo ""
printf '  feature  %s\n\n' "$FEAT"

# start no es idempotente: reejecutarlo sobre una feature ya arrancada la haria
# retroceder a FEATURE_READY, y un estado no retrocede por reintentar un
# comando. La tabla 22.5 no tiene ninguna transicion de vuelta a FEATURE_READY.
actual=$(thalos_feature_state "$FEAT" 2>/dev/null || echo "")
if [ -n "$actual" ] && [ "$actual" != FEATURE_READY ]; then
    printf '  FALL %s ya esta en %s\n' "$FEAT" "$actual"
    echo ""
    echo "  start solo entra a la maquina. Para avanzar desde aca hace falta la"
    echo "  transicion que corresponda; ver  thalos gate --from feature $actual"
    exit 2
fi

# Regla 29: la feature tiene que existir en el plan y sus dependencias tienen
# que estar terminadas. Sin eso no hay ProgramPlanEntry que sellar.
set +e
info=$("$PY" - "$PLAN" "$FEAT" <<'PYEOF'
import json, sys
plan = json.loads(open(sys.argv[1]).read())
feats = {f["id"]: f for f in plan["features"]}
f = feats.get(sys.argv[2])
if f is None:
    print(f"ERROR\tno existe {sys.argv[2]} en el plan", file=sys.stderr)
    raise SystemExit(2)
print(json.dumps({"entry": f, "deps": f.get("depends_on") or []}))
PYEOF
)
rc=$?
set -e
[ "$rc" -ne 0 ] && { echo "$info" >&2; exit 2; }

deps=$(printf '%s' "$info" | "$PY" -c 'import json,sys; print(" ".join(json.load(sys.stdin)["deps"]))')

# DependencySet: una dependencia satisfecha es una feature en estado terminal
# de exito. Cualquier otra cosa bloquea (transicion F3).
dep_ok=1
dep_detail=""
for d in $deps; do
    dst=$(thalos_feature_state "$d" 2>/dev/null || echo "-")
    if [ "$dst" != FEATURE_DONE ]; then
        dep_ok=0
        dep_detail="$dep_detail $d=$dst"
    fi
done

if [ "$dep_ok" -eq 0 ]; then
    printf '  FALL dependencias sin terminar:%s\n' "$dep_detail"
    echo ""
    echo "  READY_GATE no autoriza: una dependencia sin FEATURE_DONE bloquea (F3)."
    exit 3
fi

# ---------- evidencia de F1 ----------

seal() {
    "$PY" "$SYS/hooks/lib/evidence.py" seal "$1" >/dev/null
}
mkev() {
    _id="$1"; _kind="$2"; _ver="$3"; _payload="$4"
    cat >"$EVDIR/$_id.json" <<EOF
{"id":"$_id","kind":"$_kind","schema_version":1,
 "run_id":"${THALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"core:Orchestrator","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "digest":"pendiente","verifiable":true,"payload":$_payload}
EOF
    seal "$EVDIR/$_id.json"
}

stamp=$(date -u +%Y%m%d%H%M%S)
entry=$(printf '%s' "$info" | "$PY" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["entry"]))')
mkev "ev-$FEAT-plan-$stamp" ProgramPlanEntry true "$entry"
mkev "ev-$FEAT-deps-$stamp" DependencySet true \
     "{\"satisfied\":true,\"depends_on\":$(printf '%s' "$info" | "$PY" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["deps"]))')}"

# F1 no tiene estado origen: es la entrada a la maquina de feature, y en la
# tabla figura con "-". Se ejecuta como cualquier otra transicion.
printf '  F1  -> FEATURE_READY\n'
set +e
out=$(thalos_transition_exec feature - FEATURE_READY "$EVDIR" "$FEAT")
rc=$?
set -e
printf '%s\n' "$out" | while IFS='=' read -r k v; do
    case "$k" in
        event)       [ -n "$v" ] && printf '      ok   evento %s\n' "$v" ;;
        gate_result) [ -n "$v" ] && printf '      ok   GateResult %s\n' "$(basename "$v")" ;;
    esac
done
if [ "$rc" -ne 0 ]; then
    echo ""
    echo "  READY_GATE no autoriza la entrada a la maquina de feature (F1)."
    exit "$rc"
fi

# ---------- evidencia de F2 ----------

printf '\n  F2  -> FEATURE_IN_PROGRESS\n'

# Lease sobre la rama: regla 32.4.1, dos features no comparten el recurso.
set +e
lease=$("$PY" "$SYS/hooks/lib/lock.py" acquire "$LOCKS" \
        "branch:feature/$FEAT" "$FEAT" "${THALOS_RUN_ID:-r-unknown}" \
        "feature start" 300 2>/tmp/thalos-lock-err)
lrc=$?
set -e
if [ "$lrc" -ne 0 ]; then
    printf '      FALL no se pudo tomar el lease\n'
    sed 's/^/      /' /tmp/thalos-lock-err
    echo ""
    echo "  Regla 32.4.1: si dos features quieren el mismo recurso, se serializa."
    exit 3
fi
LEASE_ID=$(printf '%s' "$lease" | sed -n 's/.*"lease_id"[^"]*"\([^"]*\)".*/\1/p')
GEN=$(printf '%s' "$lease" | sed -n 's/.*"generation"[^0-9]*\([0-9]*\).*/\1/p')
printf '      ok   lease %s (generation %s)\n' "$LEASE_ID" "$GEN"

# Issue y rama por el adapter ligado a CoordinationAdapter. El nucleo no sabe
# cual es: lo resuelve el registry.
sem="{\"feature\":\"$FEAT\",\"generation\":$GEN}"
set +e
issue_out=$(thalos_capability_run CoordinationAdapter create_issue "$sem" 2>&1)
irc=$?
thalos_capability_run CoordinationAdapter create_branch "$sem" >/dev/null 2>&1
brc=$?
set -e
if [ "$irc" -ne 0 ] || [ "$brc" -ne 0 ]; then
    printf '      FALL el CoordinationAdapter no respondio\n'
    "$PY" "$SYS/hooks/lib/lock.py" release "$LOCKS" "$LEASE_ID" >/dev/null 2>&1 || true
    exit 5
fi
ISSUE=$(printf '%s' "$issue_out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
BRANCH="feature/$FEAT"
printf '      ok   issue %s, rama %s\n' "$ISSUE" "$BRANCH"

mkev "ev-$FEAT-lease-$stamp" LockLease true "$lease"
mkev "ev-$FEAT-issue-$stamp" IssueRef true "{\"id\":\"$ISSUE\",\"adapter_status\":\"simulado\"}"
mkev "ev-$FEAT-branch-$stamp" BranchRef true "{\"name\":\"$BRANCH\",\"sha\":null}"

THALOS_LEASE_ID="$LEASE_ID"
THALOS_ISSUE_REF="$ISSUE"
THALOS_BRANCH_REF="$BRANCH"
export THALOS_LEASE_ID THALOS_ISSUE_REF THALOS_BRANCH_REF

set +e
out=$(thalos_transition_exec feature FEATURE_READY FEATURE_IN_PROGRESS "$EVDIR" "$FEAT")
rc=$?
set -e
printf '%s\n' "$out" | while IFS='=' read -r k v; do
    case "$k" in
        decision) printf '      %s  %s\n' "$([ "$v" = pass ] && echo 'ok  ' || echo FALL)" "decision: $v" ;;
        event)    printf '      ok   evento %s\n' "$v" ;;
        gate_result) [ -n "$v" ] && printf '      ok   GateResult %s\n' "$v" ;;
    esac
done

echo ""
if [ "$rc" -eq 0 ]; then
    # Donde estaba git cuando la feature arranco. Es lo que hace atribuible un
    # commit: "commits propios" es lo que aparecio DESPUES de esto.
    #
    # Antes se comparaba la rama contra main con merge-base. Cuando no hay rama
    # de feature -y no la hay mientras el CoordinationAdapter sea de
    # simulacion- la rama resuelta ES main, merge-base(main, main) es el propio
    # HEAD, y la comparacion daba siempre "no tiene commits propios". El paso
    # era imposible de pasar y el motivo culpaba al agente.
    _base=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [ -n "$_base" ]; then
        mkdir -p "orchestration/features/$FEAT"
        printf '%s\n' "$_base" > "orchestration/features/$FEAT/.base-sha"
    fi
    printf '  %s esta en FEATURE_IN_PROGRESS\n' "$FEAT"
    echo "  El lease vence en 300s. Sin heartbeat, el LockManager lo da por muerto."
else
    printf '  %s NO avanzo: el gate rechazo la transicion\n' "$FEAT"
    "$PY" "$SYS/hooks/lib/lock.py" release "$LOCKS" "$LEASE_ID" >/dev/null 2>&1 || true
    echo "  Lease liberado."
fi
exit "$rc"
