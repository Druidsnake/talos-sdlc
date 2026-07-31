#!/bin/sh
# talos init - prepara orchestration/ en el proyecto actual.
#
# Idempotente: correrlo dos veces no rompe nada ni pisa lo existente.
# No instala herramientas de terceros ni toca spec/ salvo que se pida.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

RUNTIME_SCHEMA_VERSION=1
WITH_SPEC=0
for arg in "$@"; do
    case "$arg" in
        --with-spec) WITH_SPEC=1 ;;
        -h|--help)
            echo "uso: talos init [--with-spec]"
            echo "  --with-spec  genera tambien un esqueleto en spec/"
            exit 0 ;;
        *) echo "talos: opcion desconocida: $arg" >&2; exit 1 ;;
    esac
done

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
run_id="r-$(date -u +%Y%m%d)-$(od -An -N2 -tu2 </dev/urandom | tr -d ' ')"

created=0
note() { echo "  $1"; }

mkdir -p orchestration/features orchestration/messages orchestration/reports \
         orchestration/events orchestration/evidence

if [ -f orchestration/.meta.json ]; then
    note "orchestration/.meta.json ya existe, no se toca"
else
    cat > orchestration/.meta.json <<EOF
{
  "runtime_schema_version": $RUNTIME_SCHEMA_VERSION,
  "talos_version": "${TALOS_VERSION:-0.0.6}",
  "run_id": "$run_id",
  "created_at": "$now",
  "last_migrated_at": null,
  "last_event_seq": 0
}
EOF
    note "creado orchestration/.meta.json (run_id=$run_id)"
    created=$((created + 1))
fi

if [ -f orchestration/state.json ]; then
    note "orchestration/state.json ya existe, no se toca"
else
    cat > orchestration/state.json <<EOF
{
  "schema_version": 1,
  "program_state": "INIT",
  "features": {},
  "updated_at": "$now"
}
EOF
    note "creado orchestration/state.json"
    created=$((created + 1))
fi

if [ -f orchestration/locks.json ]; then
    note "orchestration/locks.json ya existe, no se toca"
else
    printf '{\n  "schema_version": 1,\n  "leases": []\n}\n' > orchestration/locks.json
    note "creado orchestration/locks.json"
    created=$((created + 1))
fi

if [ ! -f orchestration/.gitignore ]; then
    cat > orchestration/.gitignore <<'EOF'
# El event log y la evidencia son runtime, no fuente.
# Quitalo si queres versionar la trazabilidad completa.
events/
evidence/
.lock/
EOF
    note "creado orchestration/.gitignore"
fi

if [ "$WITH_SPEC" -eq 1 ]; then
    if [ -f spec/manifest.yaml ]; then
        note "spec/manifest.yaml ya existe, no se toca"
    else
        mkdir -p spec
        cat > spec/manifest.yaml <<'EOF'
version: "1"
title: CAMBIAME - titulo del producto
status: draft
entry: SPEC.md

# Las nueve secciones del minimo aceptable son obligatorias.
# El schema rechaza el manifiesto si falta alguna.
sections:
  problem: SPEC.md#problema
  goal: SPEC.md#objetivo
  non_goals: SPEC.md#fuera-de-alcance
  users: SPEC.md#usuarios
  requirements: requirements.md
  acceptance_criteria: acceptance.md
  constraints: constraints.md
  risks: SPEC.md#riesgos
  test_plan: test_plan.md
EOF
        note "creado spec/manifest.yaml (status=draft)"
        created=$((created + 1))
    fi
fi

# Valida lo que acaba de escribir. Si Talos genera algo invalido, hay que saberlo.
if [ -x "$SYS/hooks/validate-artifact.sh" ]; then
    if "$SYS/hooks/validate-artifact.sh" runtime-meta orchestration/.meta.json >/dev/null 2>&1; then
        note "orchestration/.meta.json valida contra su schema"
    else
        echo "talos: lo generado NO valida contra runtime-meta.schema.json" >&2
        "$SYS/hooks/validate-artifact.sh" runtime-meta orchestration/.meta.json >&2 || true
        exit 1
    fi
fi

echo ""
if [ "$created" -eq 0 ]; then
    echo "Ya estaba inicializado. Nada que hacer."
else
    echo "Listo. $created artefacto(s) creado(s)."
fi
echo ""
echo "Siguiente: talos doctor"
