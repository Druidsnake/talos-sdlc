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
            cat <<'USAGE'
talos init - prepara orchestration/ en el proyecto actual

USO
    talos init [--with-spec]

OPCIONES
    --with-spec   genera tambien un esqueleto en spec/

QUE CREA
    orchestration/.meta.json    run_id y secuencia de eventos
    orchestration/state.json    estado del programa
    orchestration/locks.json    leases activos
    orchestration/.gitignore    excluye events/ y evidence/
    .gitignore                  agrega .talos/ si esta vendoreado

    Es idempotente: correrlo dos veces no pisa nada.
    Valida lo que genera; si Talos produce algo invalido, falla.

SALIDA
    0  listo
    1  lo generado no valida contra su schema
USAGE
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
dry-run/
EOF
    note "creado orchestration/.gitignore"
fi

# Talos vendoreado son cientos de archivos. Sin decidir que hacer con ellos,
# quedan como ruido permanente en el work tree del proyecto: cada git status
# los lista y tapan lo que la persona si esta cambiando.
#
# Se ignora por defecto. Fijar la version de Talos con el proyecto es una
# decision valida, y para tomarla alcanza con borrar la linea; dejar el ruido
# sin decidir no es una decision, es un descuido.
if [ -d .talos ] && ! grep -qE '^/?\.talos/?$' .gitignore 2>/dev/null; then
    {
        [ -f .gitignore ] && [ -s .gitignore ] && echo ""
        echo "# Talos vendoreado. Son cientos de archivos del sistema, no del producto."
        echo "# Si preferis fijar la version de Talos junto al proyecto, borra esta linea."
        echo ".talos/"
    } >> .gitignore
    note "agregado .talos/ a .gitignore"
    created=$((created + 1))
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
