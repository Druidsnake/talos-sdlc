#!/bin/sh
# thalos rules - reglas activas y su mecanismo de enforcement.
set -eu
SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
thalos rules - reglas normativas activas y su mecanismo de enforcement

USO
    thalos rules [topic]

TOPICS
    roles  lifecycle  evidence  gates  spec  merge
    locks  security   extensions  events  config

FUERZA (derivada del mecanismo, no declarada)
    dura    1-5   el requisito ES obligatorio
    media   6-8   obligatorio con ventana de violacion
    blanda  9-10  consultivo, aunque el texto suene a orden

EJEMPLO
    thalos rules merge
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

[ -f "$SYS/system/rules.yaml" ] || { echo "thalos: falta system/rules.yaml" >&2; exit 2; }

PY=""
[ -x .venv/bin/python ] && PY=".venv/bin/python"
[ -z "$PY" ] && command -v python3 >/dev/null 2>&1 && PY="python3"
[ -n "$PY" ] || { echo "thalos: hace falta python con pyyaml" >&2; exit 3; }

exec "$PY" - "$SYS" "$@" <<'PY'
import sys, pathlib, yaml

FUERZA = {**{m: "dura" for m in range(1, 6)},
          **{m: "media" for m in range(6, 9)},
          **{m: "blanda" for m in (9, 10)}}
NOMBRE = {1: "schema", 2: "hook pre-accion", 3: "CI", 4: "git hook",
          5: "branch protection", 6: "hook post-accion", 7: "presencia artefacto",
          8: "aislamiento permisos", 9: "contexto por rol", 10: "instruccion md"}

SYS = sys.argv[1]
rules = yaml.safe_load((pathlib.Path(SYS) / "system" / "rules.yaml").read_text())["rules"]
topic = None
for a in sys.argv[2:]:
    if not a.startswith("-"):
        topic = a

if topic:
    rules = [r for r in rules if r["topic"] == topic]
    if not rules:
        print(f"sin reglas para el topic: {topic}")
        raise SystemExit(0)

by_topic = {}
for r in rules:
    by_topic.setdefault(r["topic"], []).append(r)

for t in sorted(by_topic):
    print(f"\n{t}")
    for r in by_topic[t]:
        f = FUERZA[r["mecanismo"]]
        print(f"  {r['id']}  [{f:6}] {r['nivel_normativo']:9} {r['requisito']}")
        print(f"             mecanismo {r['mecanismo']} ({NOMBRE[r['mecanismo']]})")

print()
for f in ("dura", "media", "blanda"):
    n = sum(1 for r in rules if FUERZA[r["mecanismo"]] == f)
    print(f"  {f:7} {n:3}")
PY
