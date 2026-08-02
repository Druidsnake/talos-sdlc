#!/bin/sh
# thalos run - el loop del orquestador.
#
# Avanza mientras los gates autoricen, y se detiene apenas dejan de hacerlo.
#
# NO decide nada por su cuenta. Cada paso sale de la misma proyeccion que
# muestra `thalos next`, que a su vez se deriva del spec aprobado y del plan. El
# loop no es una fuente de intencion: es un ejecutor de lo que ya esta
# autorizado.
#
# Se detiene, sin excepcion, cuando:
#   - ningun gate autoriza nada mas
#   - un gate pide decision humana (regla 24.4.6)
#   - se alcanza el limite de pasos
#
# Ese ultimo limite no es una comodidad. Un loop sin cota que se equivoque al
# evaluar una condicion no se equivoca una vez: se equivoca hasta que alguien
# lo mata.
#
# Sale 0 si no queda nada por hacer, 4 si espera a un humano, 3 si un gate
# rechazo, 2 si falta una precondition.

set -eu

SYS="${THALOS_SYSTEM_ROOT:?}"
PROJ="${THALOS_PROJECT_ROOT:?}"
cd "$PROJ"

MAX_PASOS=20

usage() {
    cat <<'USAGE'
thalos run - avanza mientras los gates autoricen

USO
    thalos run [--max N] [--dry-run]

OPCIONES
    --max N      cota de pasos (default 20)
    --dry-run    muestra que haria, sin ejecutar nada

DONDE CORREN LOS AGENTES
    Thalos abre las ventanas que necesita por el ExecutionAdapter. Este pane es
    la CONSOLA del orquestador: aca va el log, no un agente. Los agentes
    aparecen al lado, en panes hermanos, para que se los pueda mirar.

QUE HACE
    1. deriva que sigue, igual que thalos next
    2. ejecuta la primera accion disponible
    3. vuelve a derivar

    Repite hasta que no quede nada autorizado.

QUE NO HACE
    No elige objetivos. No fuerza transiciones. No produce evidencia por
    nadie. Cada paso ya estaba autorizado por un gate antes de que el loop
    existiera; lo unico que agrega es no tener que tipearlo.

    Se detiene ante una decision humana en vez de asumirla. Es la unica
    respuesta correcta: un loop que decide por una persona convierte la
    aprobacion en un tramite.

SALIDA
    0  no queda nada por hacer
    2  precondition fallida
    3  un gate rechazo
    4  espera una decision humana
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --max)     MAX_PASOS="${2:?falta el maximo}"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        *) shift ;;
    esac
done

# shellcheck source=../../hooks/lib/gate.sh
. "$SYS/hooks/lib/gate.sh"

PY=$(thalos_python) || { echo "thalos: no hay python3" >&2; exit 2; }
TABLA="$SYS/hooks/generated/transitions.tsv"
[ -f "$TABLA" ] || { echo "thalos: falta la tabla de transiciones" >&2; exit 2; }

CLI="$SYS/cli/thalos"

echo "thalos ${THALOS_VERSION:-?}"
echo ""
[ "$DRY" -eq 1 ] && echo "  modo dry-run: no se ejecuta nada" && echo ""
# Donde se abren los agentes lo decide el ExecutionAdapter, que es quien
# conoce el runtime. El nucleo solo declara que este pane es la consola.
echo "  esta terminal es la consola: aca va el log, los agentes se abren aparte"
echo ""

# Regla 33.4: si se excede el presupuesto, Thalos DEBE pausar o escalar. El
# loop es justamente lo que puede gastar sin que nadie mire, asi que se
# verifica antes de cada paso y no solo al principio.
presupuesto_ok() {
    set +e
    "$PY" "$SYS/hooks/lib/budget.py" check "$PROJ" >/dev/null 2>&1
    _brc=$?
    set -e
    return "$_brc"
}

paso=0
salida=0
while [ "$paso" -lt "$MAX_PASOS" ]; do
    if ! presupuesto_ok; then
        brc=$?
        echo ""
        case "$brc" in
            4) echo "  el presupuesto no alcanza para el tier requerido: el loop escala"
               echo "  Bajar el tier no es una opcion (reglas 33.7 y 33.8)." ;;
            *) echo "  presupuesto excedido: el loop pausa (regla 33.4)" ;;
        esac
        echo "  Ver  thalos budget"
        salida=4
        break
    fi
    data=$("$PY" "$SYS/hooks/lib/next.py" "$PROJ" "$TABLA" json "" 2>/dev/null) || {
        echo "  no se pudo derivar el estado"; exit 2; }

    orden=$(printf '%s' "$data" | "$PY" -c '
import json,sys
d = json.load(sys.stdin)
a = d.get("acciones") or []
print(a[0]["orden"] if a else "")
' 2>/dev/null)

    if [ -z "$orden" ]; then
        prog=$(printf '%s' "$data" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["programa"])')
        # Un loop que se planta sin decir por que obliga a adivinar entre
        # "termino" y "no puede seguir". No es lo mismo.
        frenos=$(printf '%s' "$data" | "$PY" -c '
import json,sys
for f in (json.load(sys.stdin).get("frenos") or []):
    print(f"    {f[\"feature\"]}: {f[\"porque\"]}")
' 2>/dev/null)
        echo ""
        if [ "$prog" = PROGRAM_DONE ]; then
            echo "  PROGRAM_DONE: todas las features llegaron a un estado terminal."
        elif [ -n "$frenos" ]; then
            echo "  el loop se detiene porque el avance esta frenado:"
            printf '%s\n' "$frenos"
            salida=4
        else
            echo "  nada mas que el loop pueda avanzar por su cuenta."
            echo "  Lo que falta es evidencia o una decision humana, no un comando."
        fi
        break
    fi

    paso=$((paso + 1))
    printf '  [%02d] %s\n' "$paso" "$orden"

    if [ "$DRY" -eq 1 ]; then
        # Sin ejecutar, la proyeccion no cambia y el loop no terminaria nunca.
        echo "       (dry-run: se corta despues del primer paso)"
        break
    fi

    set +e
    # shellcheck disable=SC2086
    out=$(cd "$PROJ" && $CLI ${orden#thalos } 2>&1)
    rc=$?
    set -e

    case "$rc" in
        0) printf '       ok\n' ;;
        4) printf '       needs_human: el loop se detiene\n'
           printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
           salida=4
           break ;;
        *) printf '       el paso no avanzo (exit %s)\n' "$rc"
           printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
           salida=3
           break ;;
    esac
done

if [ "$paso" -ge "$MAX_PASOS" ]; then
    echo ""
    printf '  cota de %s pasos alcanzada: el loop se detiene\n' "$MAX_PASOS"
    echo "  Si hacian falta mas, subila a mano y mira por que no converge."
    salida=4
fi

echo ""
echo "  estado final:"
"$PY" "$SYS/hooks/lib/next.py" "$PROJ" "$TABLA" texto "" 2>/dev/null | sed -n '4,14p'
exit "$salida"
