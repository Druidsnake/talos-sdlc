#!/bin/sh
# talos event tail - muestra los ultimos eventos en orden de seq.
set -eu
# Este comando solo lee el runtime del proyecto; no necesita $SYS.
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

n=20
FORMAT=text
while [ $# -gt 0 ]; do
    case "$1" in
        --format) [ "${2:-}" = json ] && FORMAT=json; shift 2 ;;
        [0-9]*) n="$1"; shift ;;
        -h|--help) echo "uso: talos event tail [n] [--format json]"; exit 0 ;;
        *) echo "talos: opcion desconocida: $1" >&2; exit 1 ;;
    esac
done

if [ ! -d orchestration/events ]; then
    echo "talos: no hay event log. Ejecuta talos init" >&2
    exit 2
fi

all=$(cat orchestration/events/*.ndjson 2>/dev/null || true)
if [ -z "$all" ]; then
    [ "$FORMAT" = json ] && echo "[]" || echo "sin eventos"
    exit 0
fi

if [ "$FORMAT" = json ]; then
    printf '%s\n' "$all" | tail -n "$n" | sed '1s/^/[/; $!s/$/,/; $s/$/]/'
else
    printf '%s\n' "$all" | tail -n "$n" | while read -r line; do
        s=$(printf '%s' "$line" | sed 's/.*"seq":\([0-9]*\).*/\1/')
        t=$(printf '%s' "$line" | sed 's/.*"type":"\([^"]*\)".*/\1/')
        a=$(printf '%s' "$line" | sed 's/.*"actor":"\([^"]*\)".*/\1/')
        ts=$(printf '%s' "$line" | sed 's/.*"ts":"\([^"]*\)".*/\1/')
        printf '  %5s  %-19s  %-34s  %s\n' "$s" "$ts" "$t" "$a"
    done
fi
