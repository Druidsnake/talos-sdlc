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

mkdir -p .talos
for d in cli hooks schemas system config; do cp -R "$SYS/$d" .talos/; done
cp "$SYS/VERSION" .talos/
[ -d "$SYS/.venv" ] && cp -R "$SYS/.venv" .venv

TALOS=".talos/cli/talos"

echo "=== proyecto virgen ==="
expect_out "L0" "doctor reporta L0 sin git hooks ni CI" $TALOS doctor
expect_out "sin inicializar" "doctor detecta runtime sin inicializar" $TALOS doctor
expect_exit 2 "status sale 2 sin inicializar" $TALOS status
expect_exit 2 "spec check sale 2 sin spec" $TALOS spec check

echo ""
echo "=== talos init ==="
expect_exit 0 "init corre limpio" $TALOS init --with-spec
[ -f orchestration/.meta.json ] && ok "crea orchestration/.meta.json" || bad "crea orchestration/.meta.json"
[ -f orchestration/state.json ] && ok "crea orchestration/state.json" || bad "crea orchestration/state.json"
[ -f spec/manifest.yaml ] && ok "crea spec/manifest.yaml" || bad "crea spec/manifest.yaml"
expect_out "valida contra su schema" "lo generado valida contra runtime-meta" $TALOS init
expect_out "Ya estaba inicializado" "init es idempotente" $TALOS init

echo ""
echo "=== spec check ==="
expect_exit 2 "rechaza spec cuyas secciones no existen" $TALOS spec check
expect_out "secciones que no resuelven" "explica que secciones faltan" $TALOS spec check
( cd spec && for f in SPEC.md requirements.md acceptance.md constraints.md test_plan.md; do
    printf '# %s\n\nejemplo\n' "$f" > "$f"
  done )
expect_exit 0 "acepta spec con las 9 secciones resueltas" $TALOS spec check
expect_out "no planifica hasta que sea approved" "avisa que draft no habilita planificar" $TALOS spec check

echo ""
echo "=== EventLog ==="
expect_exit 0 "append de evento valido" $TALOS event append --type talos.run.started --actor core:Orchestrator
$TALOS event append --type talos.precondition.checked --actor core:Orchestrator >/dev/null
$TALOS event append --type talos.spec.validated --actor core:Orchestrator >/dev/null
expect_exit 1 "rechaza tipo fuera del namespace talos" $TALOS event append --type otro.mi.evento --actor x
expect_exit 1 "rechaza append sin --type" $TALOS event append --actor x

seqs=$(cat orchestration/events/*.ndjson | sed 's/.*"seq":\([0-9]*\).*/\1/')
expected="1
2
3"
if [ "$seqs" = "$expected" ]; then ok "la secuencia es monotonica y sin huecos"; else bad "secuencia monotonica" "obtuve: $(echo "$seqs" | tr '\n' ' ')"; fi

last=$(sed -n 's/.*"last_event_seq"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' orchestration/.meta.json)
[ "$last" = "3" ] && ok "meta refleja last_event_seq=3" || bad "meta refleja last_event_seq" "obtuve: $last"

n=$(cat orchestration/events/*.ndjson | wc -l | tr -d ' ')
[ "$n" = "3" ] && ok "el evento rechazado no entro al log" || bad "el evento rechazado no entro al log" "lineas: $n"

expect_out "talos.run.started" "event tail muestra los eventos" $TALOS event tail
expect_out "eventos         3" "status refleja el conteo" $TALOS status

echo ""
echo "=== validacion cruzada de artefactos generados ==="
for pair in "runtime-meta:orchestration/.meta.json" "locks:orchestration/locks.json" "spec-manifest:spec/manifest.yaml"; do
    schema=$(echo "$pair" | cut -d: -f1)
    file=$(echo "$pair" | cut -d: -f2)
    expect_exit 0 "$file valida contra $schema" .talos/hooks/validate-artifact.sh "$schema" "$file"
done

echo ""
echo "=== separacion de raices ==="
[ ! -d .talos/orchestration ] && ok "el runtime NO se creo dentro de .talos/" || bad "el runtime se creo dentro del sistema"
[ ! -d .talos/spec ] && ok "el spec NO se creo dentro de .talos/" || bad "el spec se creo dentro del sistema"

echo ""
echo "=== ayuda de cada comando ==="
# talos rules estuvo roto por completo hasta que alguien pidio --help:
# ningun test lo invocaba. Estos checks cubren la superficie entera.
for c in doctor status rules init "spec check" "event append" "event tail"; do
    # shellcheck disable=SC2086  # se quiere el word-splitting del subcomando
    set -- $c
    if $TALOS "$@" --help >/dev/null 2>&1; then
        ok "talos $c --help sale 0"
    else
        bad "talos $c --help" "salio $?"
    fi
    if $TALOS "$@" --help 2>&1 | head -1 | grep -q "^talos $c"; then
        ok "talos $c --help se identifica"
    else
        bad "talos $c --help se identifica" "primera linea no nombra el comando"
    fi
done

expect_exit 0 "talos help lista los comandos" $TALOS help
expect_out "talos rules -" "talos help <cmd> reenvia al comando" $TALOS help rules
expect_exit 1 "sin argumentos sale 1" $TALOS
expect_exit 1 "comando inexistente sale 1" $TALOS inventado

echo ""
echo "=== cada comando corre de verdad ==="
expect_exit 0 "talos version" $TALOS version
expect_exit 0 "talos rules" $TALOS rules
expect_out "R-ROLE-001" "talos rules lista reglas reales" $TALOS rules
expect_out "merge" "talos rules filtra por topic" $TALOS rules merge
expect_exit 0 "talos status tras init" $TALOS status
expect_exit 0 "talos doctor --format json" $TALOS doctor --format json
expect_out '"install_level"' "doctor emite JSON con install_level" $TALOS doctor --format json

echo ""
total=$((pass + fail))
echo "$pass/$total checks de la CLI"
[ "$fail" -eq 0 ] || exit 1
echo "El slice vertical funciona de punta a punta."
