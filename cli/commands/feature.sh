#!/bin/sh
# talos feature - ejecucion de features. Ver talos-0.0.6.md secciones 30 y 22.5.
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

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

PLAN=orchestration/program-plan.json
LOCKS=orchestration/locks.json
EVDIR=orchestration/evidence

usage() {
    cat <<'USAGE'
talos feature - ejecucion de features

USO
    talos feature start <ID>      lleva la feature a FEATURE_IN_PROGRESS
    talos feature dispatch <ID> --role <ROL> --pane <PANE> [--kind KIND]
                                  despacha un agente con rol y alcance activos
    talos feature advance <ID> --to <ESTADO>
                                  ejecuta la transicion si el gate autoriza
    talos feature next <ID>       que transiciones salen del estado actual
    talos feature work <ID>       le da al agente despachado el trabajo de la feature
    talos feature commit <ID>     observa git y sella CommitRef
    talos feature collect <ID>    recoge el entregable del rol como evidencia
    talos feature test <ID> --pane <PANE> --command "<CMD>"
                                  corre una verificacion y sella LocalTestReport
    talos feature list            estado de todas las features del plan
    talos feature show <ID>       detalle de una feature
    talos feature release <ID>    suelta el rol activo

QUE HACE start
    1. verifica que la feature exista en el plan y que sus dependencias esten
       terminadas
    2. produce ProgramPlanEntry y DependencySet como evidencia sellada
    3. transiciona a FEATURE_READY si READY_GATE lo autoriza          (F1)
    4. toma el lease de la rama, crea issue y rama por el
       CoordinationAdapter, y sella LockLease, IssueRef y BranchRef
    5. transiciona a FEATURE_IN_PROGRESS si el gate lo autoriza       (F2)

    Cada paso emite su evento y persiste el GateResult que lo autorizo. Si un
    gate rechaza, se emite talos.transition.rejected y no se avanza.

    El adapter que crea issue y rama sale del registry, no esta cableado.
    En dry-run-only las operaciones se simulan y quedan en el ledger.

QUE HACE dispatch
    1. verifica que la feature este en FEATURE_IN_PROGRESS
    2. verifica que el rol exista en el registro de scope
    3. activa el rol: a partir de ahi toda escritura del agente pasa por el
       mecanismo 2 y se deniega fuera de write_paths
    4. compone el brief -instrucciones del rol + alcance concreto- y arranca
       el agente por el ExecutionAdapter

    El rol lo fija Talos, no lo elige el agente. Un rol desconocido no se
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

PY=$(talos_python) || { echo "talos: no hay python3" >&2; exit 2; }

sub="${1:-list}"
[ $# -gt 0 ] && shift
FEAT="${1:-}"

need_plan() {
    [ -f "$PLAN" ] || { echo "talos: no existe $PLAN" >&2
                        echo "talos: talos plan init" >&2; exit 2; }
}

# ---------- list ----------

if [ "$sub" = list ]; then
    need_plan
    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  %-6s %-38s %-22s %s\n' ID TITULO ESTADO RIESGO
    "$PY" - "$PLAN" <<'PYEOF' | while IFS='	' read -r fid title risk; do
import json, sys
for f in json.loads(open(sys.argv[1]).read())["features"]:
    print(f"{f['id']}\t{f['title'][:36]}\t{f['risk']}")
PYEOF
        st=$(talos_feature_state "$fid" 2>/dev/null || echo "-")
        printf '  %-6s %-38s %-22s %s\n' "$fid" "$title" "$st" "$risk"
    done
    echo ""
    echo "  - = todavia no arranco"
    exit 0
fi

# ---------- show ----------

if [ "$sub" = show ]; then
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    sf="orchestration/features/$FEAT/state.json"
    [ -f "$sf" ] || { echo "talos: $FEAT no arranco todavia" >&2; exit 2; }
    "$PY" -m json.tool "$sf"
    exit 0
fi

# ---------- next ----------

if [ "$sub" = next ]; then
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    est=$(talos_feature_state "$FEAT" 2>/dev/null || echo "")
    [ -n "$est" ] || { echo "talos: $FEAT no arranco todavia" >&2; exit 2; }
    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  %s esta en %s\n\n' "$FEAT" "$est"
    if talos_is_terminal feature "$est"; then
        echo "  Estado terminal: no tiene transiciones de salida (regla 22.6.9)."
        exit 0
    fi
    printf '  %-4s %-24s %-18s %-14s %s\n' ID HACIA GATE ACTOR EVIDENCIA
    # shellcheck disable=SC2034
    talos_transitions_from feature "$est" | while IFS='	' read -r mm id from to gate cond actor req event; do
        printf '  %-4s %-24s %-18s %-14s %s\n' "$id" "$to" "$gate" "$actor" "$req"
    done
    echo ""
    echo "  talos feature advance $FEAT --to <ESTADO>"
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
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    [ -n "$TO" ]   || { echo "talos: falta --to" >&2; exit 1; }

    est=$(talos_feature_state "$FEAT" 2>/dev/null || echo "")
    [ -n "$est" ] || { echo "talos: $FEAT no arranco todavia" >&2
                       echo "talos: talos feature start $FEAT" >&2; exit 2; }

    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  feature  %s\n  desde    %s\n  hacia    %s\n' "$FEAT" "$est" "$TO"

    tid=$(talos_transition_id feature "$est" "$TO" 2>/dev/null || echo "")
    if [ -z "$tid" ]; then
        echo ""
        printf '  FALL no existe la transicion %s -> %s en la tabla 22.5\n' "$est" "$TO"
        echo ""
        echo "  Regla 22.6.2: toda transicion no listada se rechaza."
        echo "  Ver las disponibles con  talos feature next $FEAT"
        exit 3
    fi
    printf '  %-8s %s\n\n' "id" "$tid"

    # Regla 22.6.3: la evidencia se presenta ANTES de evaluar el gate. Si la
    # transicion exige LockRelease, soltar los leases no puede ser consecuencia
    # de haber transicionado: seria pedir como requisito algo que solo existe
    # despues. Se sueltan primero y se acuña la evidencia.
    req=$(talos_transition_requires feature "$est" "$TO" 2>/dev/null || echo "-")
    case "$req" in
        *LockRelease*)
            talos_release_feature_leases "$FEAT" | while read -r l; do
                [ -n "$l" ] && printf '  ok   lease liberado %s\n' "$l"
            done
            ;;
    esac

    set +e
    out=$(talos_transition_exec feature "$est" "$TO" "$EVDIR" "$FEAT")
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
           talos_is_terminal feature "$TO" && \
             echo "  Estado terminal: los leases de la feature quedaron liberados (regla 22.6.8)." ;;
        4) echo "  needs_human: registra la decision con  talos human decide $FEAT --decision <D>" ;;
        *) echo "  el gate rechazo la transicion: la feature no avanzo"
           echo "  Se emitio talos.transition.rejected (regla 22.6.2)." ;;
    esac
    exit "$rc"
fi

# ---------- work ----------
#
# dispatch arranca al agente con su rol y su alcance, pero no le dice que
# construir. Esto le entrega el trabajo concreto de la feature y espera a que
# termine.

if [ "$sub" = work ]; then
    PANE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --pane) PANE="${2:?falta el pane}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    need_plan

    ROLE=$(talos_role_current 2>/dev/null || echo "")
    [ -n "$ROLE" ] || { echo "talos: no hay rol activo; despacha primero" >&2
                        echo "talos: talos feature dispatch $FEAT --role Developer --pane <PANE>" >&2
                        exit 2; }

    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  feature  %s\n  rol      %s\n\n' "$FEAT" "$ROLE"

    encargo=$("$PY" - "$PLAN" "$FEAT" <<'PYEOF'
import json, sys
plan = json.loads(open(sys.argv[1]).read())
f = next((x for x in plan["features"] if x["id"] == sys.argv[2]), None)
if f is None:
    raise SystemExit(2)
partes = [
    f"Implementa {f['id']}: {f['title']}.",
    "",
    f.get("description") or "",
    "",
    "El spec aprobado manda. Leelo antes de escribir:",
    *[f"  spec/{r}" for r in (f.get("spec_refs") or [])],
    *[f"  spec/{r}" for r in (f.get("acceptance_refs") or [])],
    "",
    "Escribi el codigo Y sus tests. Un criterio de aceptacion sin test no",
    "esta cumplido. Los casos de rechazo son obligatorios.",
    "",
    "Cuando termines, deja tu entregable en:",
    f"  orchestration/features/{f['id']}/tasks/T01/task-result.json",
    "que tiene que validar contra .talos/schemas/task-result.schema.json.",
    "Sin ese archivo tu trabajo no existe para el sistema.",
]
print("\n".join(x for x in partes if x is not None))
PYEOF
) || { echo "talos: $FEAT no esta en el plan" >&2; exit 2; }

    printf '%s\n' "$encargo" | sed 's/^/    /' | head -6
    echo "    ..."
    echo ""

    # El texto va como semantic_args del adapter: quien ejecuta es el
    # ExecutionAdapter, y el nucleo no sabe con que agente esta hablando.
    esc=$(printf '%s' "$encargo" | "$PY" -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')
    set +e
    out=$(talos_capability_run ExecutionAdapter prompt_agent \
          "{\"target\":\"$PANE\",\"text\":\"$esc\",\"timeout_ms\":\"900000\"}" 2>&1)
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        echo "  FALL el ExecutionAdapter no pudo entregar el trabajo"
        printf '%s\n' "$out" | sed 's/^/    /' | head -3
        exit 5
    fi
    echo "  ok   trabajo entregado al agente"
    echo "  El agente esta trabajando. Mira su pane."
    exit 0
fi

# ---------- commit ----------
#
# El catalogo de la seccion 23.4 dice que CommitRef lo produce el
# CoordinationAdapter, pero la seccion 38.4 no define ninguna operacion de
# commit para ese adapter. Un commit no es una mutacion que Talos ordene: es un
# hecho de git que Talos OBSERVA. Por eso sale verifiable:true, y de la unica
# forma en que eso es cierto: el sha se puede revalidar contra el repo
# (regla 23.3.4).

if [ "$sub" = commit ]; then
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    rama="feature/$FEAT"
    if ! git rev-parse --verify --quiet "$rama" >/dev/null 2>&1; then
        rama=$(git rev-parse --abbrev-ref HEAD)
    fi
    sha=$(git rev-parse "$rama" 2>/dev/null || echo "")
    [ -n "$sha" ] || { echo "talos: no se pudo leer el estado de git" >&2; exit 2; }

    # Un commit que no existe no se inventa: si no hay nada nuevo respecto de
    # main, no hay trabajo que referenciar.
    base=$(git merge-base "$rama" main 2>/dev/null || echo "")
    if [ -n "$base" ] && [ "$base" = "$sha" ]; then
        echo "talos: $rama no tiene commits propios; no hay CommitRef que sellar" >&2
        echo "talos: el agente todavia no commiteo su trabajo" >&2
        exit 3
    fi

    msg=$(git log -1 --pretty=%s "$sha" 2>/dev/null || echo "")
    mkdir -p "$EVDIR"
    evid="ev-$FEAT-commit-$(date -u +%Y%m%d%H%M%S)"
    cat > "$EVDIR/$evid.json" <<EOF2
{"id":"$evid","kind":"CommitRef","schema_version":1,
 "run_id":"${TALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
 "produced_by":"core:Orchestrator","produced_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "digest":"pendiente","verifiable":true,
 "payload":{"sha":"$sha","branch":"$rama","message":"$(printf '%s' "$msg" | sed 's/"/\\"/g')"}}
EOF2
    "$PY" "$SYS/hooks/lib/evidence.py" seal "$EVDIR/$evid.json" >/dev/null

    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '  rama     %s\n  sha      %s\n  mensaje  %s\n' "$rama" "$sha" "$msg"
    printf '  sellada  CommitRef (verifiable: true, revalidable contra el repo)\n'
    exit 0
fi

# ---------- collect ----------
#
# La otra mitad de la costura: ya controlamos que ENTRA al agente (rol y
# alcance); esto controla que SALE. El rol declara su entregable en
# config/roles.yaml y hasta ahora nadie lo recogia.

if [ "$sub" = collect ]; then
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    ROLE=$(talos_role_current 2>/dev/null || echo "")
    [ -n "$ROLE" ] || { echo "talos: no hay rol activo; nada que recoger" >&2
                        echo "talos: talos feature dispatch $FEAT --role <ROL> --pane <PANE>" >&2
                        exit 2; }

    schema=$(talos_role_output_schema "$ROLE") || {
        echo "talos: el rol $ROLE no declara entregable" >&2; exit 2; }
    patron=$(talos_role_output_path "$ROLE" "$FEAT")

    echo "talos ${TALOS_VERSION:-?}"
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

        kind=$(talos_role_evidence_kind "$schema") || kind=TaskResultSet
        dg=$(shasum -a 256 "$art" 2>/dev/null | awk '{print $1}')
        evid="ev-$FEAT-$(basename "$art" .json)-$(date -u +%Y%m%d%H%M%S)-$n"
        # Regla 23.3.6: la evidencia producida por un agente NO es verificable
        # salvo que traiga salida de una herramienta determinista. Un entregable
        # que el agente escribio es su palabra, no una medicion.
        cat > "$EVDIR/$evid.json" <<EOF2
{"id":"$evid","kind":"$kind","schema_version":1,
 "run_id":"${TALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
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
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    [ -n "$PANE" ] || { echo "talos: falta --pane" >&2; exit 1; }
    [ -n "$CMD" ]  || { echo "talos: falta --command" >&2; exit 1; }

    echo "talos ${TALOS_VERSION:-?}"
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
    disp=$(talos_capability_run ExecutionAdapter run_command \
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
    printf '  exit     %s\n' "$rc"
    printf '  salida   %s\n\n' "$log"
    tail -6 "$log" 2>/dev/null | sed 's/^/    /'

    dg=$(shasum -a 256 "$log" 2>/dev/null | awk '{print $1}')
    evid="ev-$FEAT-localtest-$(date -u +%Y%m%d%H%M%S)"
    # verifiable: true. Es salida de una herramienta determinista con su codigo
    # de salida, no la afirmacion de un agente (regla 23.3.6).
    cat > "$EVDIR/$evid.json" <<EOF2
{"id":"$evid","kind":"LocalTestReport","schema_version":1,
 "run_id":"${TALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
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
    actual=$(talos_role_current 2>/dev/null || echo "")
    talos_role_deactivate
    if [ -n "$actual" ]; then
        echo "rol $actual liberado: Talos ya no gobierna esta sesion"
    else
        echo "no habia rol activo"
    fi
    exit 0
fi

# ---------- dispatch ----------

if [ "$sub" = dispatch ]; then
    ROLE=""; PANE=""; KIND="claude"
    while [ $# -gt 0 ]; do
        case "$1" in
            --role) ROLE="${2:?falta el rol}"; shift 2 ;;
            --pane) PANE="${2:?falta el pane}"; shift 2 ;;
            --kind) KIND="${2:?falta el kind}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }
    [ -n "$ROLE" ] || { echo "talos: falta --role" >&2; exit 1; }
    [ -n "$PANE" ] || { echo "talos: falta --pane" >&2; exit 1; }

    echo "talos ${TALOS_VERSION:-?}"
    echo ""

    # Un agente no se despacha sobre una feature que no arranco.
    est=$(talos_feature_state "$FEAT" 2>/dev/null || echo "")
    if [ "$est" != FEATURE_IN_PROGRESS ]; then
        printf '  FALL %s esta en %s, no en FEATURE_IN_PROGRESS\n' "$FEAT" "${est:--}"
        echo ""
        echo "  Un Developer se despacha sobre trabajo en curso. Arranca con:"
        echo "    talos feature start $FEAT"
        exit 2
    fi

    # Fail-closed: sin rol conocido no hay scope, y sin scope el bloqueo deja
    # pasar todo. Es preferible no despachar.
    if ! talos_role_activate "$ROLE" "$FEAT"; then
        exit 2
    fi
    printf '  rol      %s (activo)\n' "$ROLE"
    printf '  feature  %s\n' "$FEAT"
    printf '  pane     %s\n\n' "$PANE"

    printf '  alcance de escritura que se le impone:\n'
    talos_role_scope "$ROLE" | while IFS='	' read -r v g; do
        [ -z "$v" ] && continue
        printf '    %-9s %s\n' "$v" "$g"
    done
    echo ""

    brief_file="orchestration/features/$FEAT/brief.md"
    mkdir -p "$(dirname "$brief_file")"
    talos_role_brief "$ROLE" "$FEAT" > "$brief_file"
    printf '  brief    %s (%s lineas)\n' "$brief_file" "$(wc -l < "$brief_file" | tr -d ' ')"

    # El nucleo compone la identidad; el adapter solo arranca el proceso.
    aargs="--append-system-prompt $(printf '%s' "$brief_file")"
    set +e
    out=$(talos_capability_run ExecutionAdapter start_agent \
          "{\"name\":\"talos_$(printf '%s' "$FEAT" | tr 'A-Z' 'a-z')\",\"kind\":\"$KIND\",\"pane\":\"$PANE\",\"agent_args\":\"$aargs\"}" 2>&1)
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        printf '  FALL el ExecutionAdapter no pudo arrancar el agente\n'
        printf '%s\n' "$out" | sed 's/^/    /' | head -4
        talos_role_deactivate
        echo ""
        echo "  Rol liberado: no queda gobernando una sesion que no arranco."
        exit 5
    fi
    printf '  agente   arrancado por el ExecutionAdapter\n'
    echo ""
    echo "  El rol queda activo hasta  talos feature release $FEAT"
    exit 0
fi

[ "$sub" = start ] || { echo "talos: subcomando desconocido: $sub" >&2
                        echo "talos: disponibles: start, dispatch, list, show, release" >&2; exit 1; }
[ -n "$FEAT" ] || { echo "talos: falta el id de la feature" >&2; exit 1; }

# ---------- start ----------

need_plan
mkdir -p "$EVDIR" orchestration/features

echo "talos ${TALOS_VERSION:-?}"
echo ""
printf '  feature  %s\n\n' "$FEAT"

# start no es idempotente: reejecutarlo sobre una feature ya arrancada la haria
# retroceder a FEATURE_READY, y un estado no retrocede por reintentar un
# comando. La tabla 22.5 no tiene ninguna transicion de vuelta a FEATURE_READY.
actual=$(talos_feature_state "$FEAT" 2>/dev/null || echo "")
if [ -n "$actual" ] && [ "$actual" != FEATURE_READY ]; then
    printf '  FALL %s ya esta en %s\n' "$FEAT" "$actual"
    echo ""
    echo "  start solo entra a la maquina. Para avanzar desde aca hace falta la"
    echo "  transicion que corresponda; ver  talos gate --from feature $actual"
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
    dst=$(talos_feature_state "$d" 2>/dev/null || echo "-")
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
 "run_id":"${TALOS_RUN_ID:-r-unknown}","feature_id":"$FEAT",
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
out=$(talos_transition_exec feature - FEATURE_READY "$EVDIR" "$FEAT")
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
        "branch:feature/$FEAT" "$FEAT" "${TALOS_RUN_ID:-r-unknown}" \
        "feature start" 300 2>/tmp/talos-lock-err)
lrc=$?
set -e
if [ "$lrc" -ne 0 ]; then
    printf '      FALL no se pudo tomar el lease\n'
    sed 's/^/      /' /tmp/talos-lock-err
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
issue_out=$(talos_capability_run CoordinationAdapter create_issue "$sem" 2>&1)
irc=$?
talos_capability_run CoordinationAdapter create_branch "$sem" >/dev/null 2>&1
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

TALOS_LEASE_ID="$LEASE_ID"
TALOS_ISSUE_REF="$ISSUE"
TALOS_BRANCH_REF="$BRANCH"
export TALOS_LEASE_ID TALOS_ISSUE_REF TALOS_BRANCH_REF

set +e
out=$(talos_transition_exec feature FEATURE_READY FEATURE_IN_PROGRESS "$EVDIR" "$FEAT")
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
    printf '  %s esta en FEATURE_IN_PROGRESS\n' "$FEAT"
    echo "  El lease vence en 300s. Sin heartbeat, el LockManager lo da por muerto."
else
    printf '  %s NO avanzo: el gate rechazo la transicion\n' "$FEAT"
    "$PY" "$SYS/hooks/lib/lock.py" release "$LOCKS" "$LEASE_ID" >/dev/null 2>&1 || true
    echo "  Lease liberado."
fi
exit "$rc"
