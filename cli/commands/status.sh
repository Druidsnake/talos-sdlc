#!/bin/sh
# thalos status - estado del proyecto.
set -eu
# Este comando solo lee el runtime del proyecto; no necesita $SYS.
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
thalos status - estado del proyecto

USO
    thalos status [--format json]

MUESTRA
    run_id, fecha de creacion, eventos registrados,
    estado del spec y cantidad de features

SALIDA
    0  el proyecto esta inicializado
    2  falta thalos init
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

FORMAT=text
[ "${1:-}" = "--format" ] && [ "${2:-}" = "json" ] && FORMAT=json

meta_get() {
    [ -f orchestration/.meta.json ] || return 1
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\(.*\)/\1/p" orchestration/.meta.json | head -1 | sed 's/[",]//g' | tr -d ' '
}

if [ ! -f orchestration/.meta.json ]; then
    if [ "$FORMAT" = json ]; then
        echo '{"initialized": false}'
    else
        echo "sin inicializar. Ejecuta thalos init"
    fi
    exit 2
fi

run_id=$(meta_get run_id)
seq=$(meta_get last_event_seq)
created=$(meta_get created_at)

spec_status="ausente"
[ -f spec/manifest.yaml ] && spec_status=$(grep -E '^status:' spec/manifest.yaml | head -1 | sed 's/status:[[:space:]]*//' | tr -d '"' || echo "?")

n_features=0
[ -d orchestration/features ] && n_features=$(find orchestration/features -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

if [ "$FORMAT" = json ]; then
    printf '{"initialized": true, "run_id": "%s", "last_event_seq": %s, "spec_status": "%s", "features": %s}\n' \
        "$run_id" "${seq:-0}" "$spec_status" "$n_features"
else
    echo "thalos ${THALOS_VERSION:-?}"
    echo ""
    printf '  run_id          %s\n' "$run_id"
    printf '  creado          %s\n' "$created"
    printf '  eventos         %s\n' "${seq:-0}"
    printf '  spec            %s\n' "$spec_status"
    printf '  features        %s\n' "$n_features"
    # Barrido acoplado (mensajeria 8.2). Una escalacion no puede quedar
    # esperando a que alguien se acuerde de correr `message list`.
    "$SYS/cli/thalos" message sweep 2>/dev/null | grep '!!' || true
fi
