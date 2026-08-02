#!/bin/sh
# Prueba de punta a punta de la CLI sobre un proyecto limpio y desechable.
#
# Verifica el slice vertical completo: init, doctor, spec check y EventLog,
# incluyendo que rechace lo que debe rechazar.

set -eu
SYS=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

pass=0
fail=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ok()   { pass=$((pass + 1)); printf "  ok    %s\n" "$1"; }
bad()  { fail=$((fail + 1)); printf "  FALLA %s\n" "$1"; [ -n "${2:-}" ] && printf "        %s\n" "$2"; return 0; }

expect_exit() {
    want="$1"; label="$2"; shift 2
    set +e; "$@" >/dev/null 2>&1; got=$?; set -e
    if [ "$got" -eq "$want" ]; then ok "$label (exit $got)"; else bad "$label" "esperaba exit $want, obtuvo $got"; fi
}

expect_out() {
    pattern="$1"; label="$2"; shift 2
    if "$@" 2>&1 | grep -q "$pattern"; then ok "$label"; else bad "$label" "no aparece: $pattern"; fi
}

# ---------- proyecto de prueba ----------
proj="$work/proyecto"
mkdir -p "$proj"
cd "$proj"
git init -q
git config user.name "Prueba"
git config user.email "prueba@ejemplo.com"

mkdir -p .thalos
for d in cli hooks schemas system config adapters roles; do cp -R "$SYS/$d" .thalos/; done
cp "$SYS/VERSION" .thalos/
[ -d "$SYS/.venv" ] && cp -R "$SYS/.venv" .venv

THALOS=".thalos/cli/thalos"

echo "=== proyecto virgen ==="
expect_out "L0" "doctor reporta L0 sin git hooks ni CI" $THALOS doctor
expect_out "sin inicializar" "doctor detecta runtime sin inicializar" $THALOS doctor
expect_exit 2 "status sale 2 sin inicializar" $THALOS status
expect_exit 2 "spec check sale 2 sin spec" $THALOS spec check

echo ""
echo "=== thalos init ==="
expect_exit 0 "init corre limpio" $THALOS init --with-spec
[ -f orchestration/.meta.json ] && ok "crea orchestration/.meta.json" || bad "crea orchestration/.meta.json"
[ -f orchestration/state.json ] && ok "crea orchestration/state.json" || bad "crea orchestration/state.json"
[ -f spec/manifest.yaml ] && ok "crea spec/manifest.yaml" || bad "crea spec/manifest.yaml"
expect_out "valida contra su schema" "lo generado valida contra runtime-meta" $THALOS init
expect_out "Ya estaba inicializado" "init es idempotente" $THALOS init

echo ""
echo "=== spec check ==="
expect_exit 2 "rechaza spec cuyas secciones no existen" $THALOS spec check
expect_out "secciones que no resuelven" "explica que secciones faltan" $THALOS spec check
( cd spec && for f in SPEC.md requirements.md acceptance.md constraints.md test_plan.md; do
    printf '# %s\n\nejemplo\n' "$f" > "$f"
  done )
expect_exit 0 "acepta spec con las 9 secciones resueltas" $THALOS spec check
expect_out "no planifica hasta que sea approved" "avisa que draft no habilita planificar" $THALOS spec check

echo ""
echo "=== EventLog ==="
expect_exit 0 "append de evento valido" $THALOS event append --type thalos.run.started --actor core:Orchestrator
$THALOS event append --type thalos.precondition.checked --actor core:Orchestrator >/dev/null
$THALOS event append --type thalos.spec.validated --actor core:Orchestrator >/dev/null
expect_exit 1 "rechaza tipo fuera del namespace thalos" $THALOS event append --type otro.mi.evento --actor x
expect_exit 1 "rechaza append sin --type" $THALOS event append --actor x

seqs=$(cat orchestration/events/*.ndjson | sed 's/.*"seq":\([0-9]*\).*/\1/')
expected="1
2
3"
if [ "$seqs" = "$expected" ]; then ok "la secuencia es monotonica y sin huecos"; else bad "secuencia monotonica" "obtuve: $(echo "$seqs" | tr '\n' ' ')"; fi

last=$(sed -n 's/.*"last_event_seq"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' orchestration/.meta.json)
[ "$last" = "3" ] && ok "meta refleja last_event_seq=3" || bad "meta refleja last_event_seq" "obtuve: $last"

n=$(cat orchestration/events/*.ndjson | wc -l | tr -d ' ')
[ "$n" = "3" ] && ok "el evento rechazado no entro al log" || bad "el evento rechazado no entro al log" "lineas: $n"

expect_out "thalos.run.started" "event tail muestra los eventos" $THALOS event tail
expect_out "eventos         3" "status refleja el conteo" $THALOS status

echo ""
echo "=== validacion cruzada de artefactos generados ==="
for pair in "runtime-meta:orchestration/.meta.json" "locks:orchestration/locks.json" "spec-manifest:spec/manifest.yaml"; do
    schema=$(echo "$pair" | cut -d: -f1)
    file=$(echo "$pair" | cut -d: -f2)
    expect_exit 0 "$file valida contra $schema" .thalos/hooks/validate-artifact.sh "$schema" "$file"
done

echo ""
echo "=== separacion de raices ==="
[ ! -d .thalos/orchestration ] && ok "el runtime NO se creo dentro de .thalos/" || bad "el runtime se creo dentro del sistema"
[ ! -d .thalos/spec ] && ok "el spec NO se creo dentro de .thalos/" || bad "el spec se creo dentro del sistema"

echo ""
echo "=== ayuda de cada comando ==="
# thalos rules estuvo roto por completo hasta que alguien pidio --help:
# ningun test lo invocaba. Estos checks cubren la superficie entera.
for c in doctor status rules adapters gate evidence plan feature merge human next run budget init "spec check" "event append" "event tail"; do
    # shellcheck disable=SC2086  # se quiere el word-splitting del subcomando
    set -- $c
    if $THALOS "$@" --help >/dev/null 2>&1; then
        ok "thalos $c --help sale 0"
    else
        bad "thalos $c --help" "salio $?"
    fi
    if $THALOS "$@" --help 2>&1 | head -1 | grep -q "^thalos $c"; then
        ok "thalos $c --help se identifica"
    else
        bad "thalos $c --help se identifica" "primera linea no nombra el comando"
    fi
done

expect_exit 0 "thalos help lista los comandos" $THALOS help
expect_out "thalos rules -" "thalos help <cmd> reenvia al comando" $THALOS help rules
expect_exit 1 "sin argumentos sale 1" $THALOS
expect_exit 1 "comando inexistente sale 1" $THALOS inventado

echo ""
echo "=== cada comando corre de verdad ==="
expect_exit 0 "thalos version" $THALOS version
expect_exit 0 "thalos rules" $THALOS rules
expect_out "R-ROLE-001" "thalos rules lista reglas reales" $THALOS rules
expect_out "merge" "thalos rules filtra por topic" $THALOS rules merge
expect_exit 0 "thalos status tras init" $THALOS status
expect_exit 0 "thalos doctor --format json" $THALOS doctor --format json
expect_out '"install_level"' "doctor emite JSON con install_level" $THALOS doctor --format json

echo ""
echo "=== capacidades y adapters ==="
expect_exit 0 "thalos adapters sale 0 con el registry completo" $THALOS adapters
expect_out "dry-run-only" "adapters reporta el modo de ejecucion" $THALOS adapters
expect_out "ExecutionAdapter" "adapters lista las capacidades requeridas" $THALOS adapters
expect_out "sin_ligar" "adapters muestra las opcionales sin ligar" $THALOS adapters
expect_exit 0 "thalos adapters --format json" $THALOS adapters --format json
expect_out '"execution_mode"' "adapters emite JSON con el modo" $THALOS adapters --format json
expect_out "modo_ejecucion" "doctor verifica el modo declarado (precondition 27.1.15)" $THALOS doctor
expect_out "capacidades" "doctor verifica las capacidades requeridas" $THALOS doctor

# Sin la tabla de capacidades, el nucleo no puede resolver ninguna: eso es
# una precondition fallida, no una advertencia.
mv .thalos/hooks/generated/capabilities.tsv .thalos/hooks/generated/capabilities.off
expect_exit 2 "adapters sale 2 sin tabla de capacidades" $THALOS adapters
expect_exit 2 "doctor sale 2 sin tabla de capacidades" $THALOS doctor
mv .thalos/hooks/generated/capabilities.off .thalos/hooks/generated/capabilities.tsv
expect_exit 0 "doctor vuelve a 0 al restaurar la tabla" $THALOS doctor

echo ""
echo "=== maquina de estados y gates ==="
expect_exit 0 "thalos gate --list vuelca la tabla" $THALOS gate --list
expect_out "F19" "la tabla trae las transiciones de feature" $THALOS gate --list
expect_out "P21" "la tabla trae las transiciones de programa" $THALOS gate --list
expect_out "FEATURE_ABANDONED" "adapters lista el comodin F27" $THALOS gate --from feature FEATURE_READY
expect_out "terminal" "un estado terminal no ofrece salidas" $THALOS gate --from feature FEATURE_DONE
expect_exit 3 "gate rechaza sin evidencia (exit 3)" $THALOS gate feature FEATURE_READY FEATURE_IN_PROGRESS
expect_exit 3 "gate rechaza una transicion inexistente" $THALOS gate feature FEATURE_READY FEATURE_MERGED
expect_exit 1 "gate rechaza una maquina desconocida" $THALOS gate inventada A B
expect_out "TRANSITION_NOT_DEFINED" "el rechazo dice por que" $THALOS gate feature FEATURE_READY FEATURE_MERGED

echo ""
echo "=== evidencia: sellado y verificacion ==="
mkdir -p orchestration/evidence
printf '{"id":"ev-t","kind":"LockLease","schema_version":1,"run_id":"r-1","produced_by":"core:t","produced_at":"2026-07-31T00:00:00Z","digest":"pendiente","verifiable":true,"payload":{"a":1}}\n' > orchestration/evidence/t.json
expect_exit 0 "evidence seal calcula el digest" $THALOS evidence seal orchestration/evidence/t.json
expect_exit 0 "evidence check pasa con la evidencia sellada" $THALOS evidence check
expect_out "cierra contra su digest" "check confirma que todo cierra" $THALOS evidence check

# Cambiar el payload despues de sellar tiene que romperla.
printf '{"id":"ev-t","kind":"LockLease","schema_version":1,"run_id":"r-1","produced_by":"core:t","produced_at":"2026-07-31T00:00:00Z","digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","verifiable":true,"payload":{"a":2}}\n' > orchestration/evidence/t.json
expect_exit 1 "evidence check detecta un digest que no cuadra" $THALOS evidence check
expect_out "no justifica" "check explica por que una evidencia rota no sirve" $THALOS evidence check
rm -f orchestration/evidence/t.json

echo ""
echo "=== planificacion ==="
# Regla 29.1: sin spec approved no se planifica.
expect_exit 2 "plan init se niega con el spec en draft (regla 29.1)" $THALOS plan init
expect_out "no approved" "dice por que se niega" $THALOS plan init
expect_exit 2 "plan check sin plan sale 2" $THALOS plan check

echo ""
echo "=== decision humana y avance generico ==="
expect_exit 1 "human sin subcomando sale 1" $THALOS human
expect_out "abandon " "human --help lista el dominio de decisiones" $THALOS human --help
expect_exit 2 "human decide rechaza una decision fuera del dominio" $THALOS human decide F001 --decision inventada
expect_out "fuera del dominio" "y dice por que" $THALOS human decide F001 --decision inventada
expect_exit 2 "feature next sale 2 si la feature no arranco" $THALOS feature next F001
expect_exit 2 "feature advance sale 2 si la feature no arranco" $THALOS feature advance F001 --to FEATURE_REVIEW
expect_exit 1 "feature advance sin --to sale 1" $THALOS feature advance F001

echo ""
total=$((pass + fail))
echo "$pass/$total checks de la CLI"
[ "$fail" -eq 0 ] || exit 1
echo "El slice vertical funciona de punta a punta."
