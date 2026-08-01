#!/bin/sh
# Instala el enforcement de Talos en el runtime de opencode.
#
# Un shim por runtime. El nucleo no conoce .opencode/plugin/ ni AGENTS.md: son
# detalles de ESTE agente. Cambiar de runtime es escribir otro instalador, no
# rehacer la politica.
#
# Hace dos cosas, y las dos hacen falta:
#
#   1. Instala el plugin que bloquea. Sin esto el alcance esta DECLARADO y no
#      IMPUESTO: el agente lo respeta por criterio propio, que es exactamente
#      lo que Talos existe para no depender.
#
#   2. Deja el brief donde el agente lo lee. Pasarlo por linea de comandos es
#      fragil -son cien lineas con saltos y comillas- y se rompe en silencio.
#
# Uso:   install.sh <raiz-del-proyecto> <raiz-de-talos> <archivo-de-brief>
#        install.sh <raiz-del-proyecto> --uninstall
# Sale:  0 instalado / 1 no se pudo

set -eu

PROJ="${1:?falta la raiz del proyecto}"

PLUGIN_REL=".opencode/plugin/talos-scope.js"
BRIEF_DST="AGENTS.md"
BACKUP="AGENTS.md.talos-backup"
MARCA="GENERADO por Talos"

if [ "${2:-}" = "--uninstall" ]; then
    cd "$PROJ"
    [ -f "$PLUGIN_REL" ] && rm -f "$PLUGIN_REL" && echo "bloqueo retirado ($PLUGIN_REL)"
    if [ -f "$BRIEF_DST" ] && head -1 "$BRIEF_DST" | grep -q "$MARCA"; then
        rm -f "$BRIEF_DST"
        echo "brief retirado ($BRIEF_DST)"
        # Lo que habia antes vuelve. Talos toma prestado el archivo, no se lo
        # queda: quien tenia su propio AGENTS.md no lo pierde por despachar.
        [ -f "$BACKUP" ] && mv "$BACKUP" "$BRIEF_DST" && echo "$BRIEF_DST propio restaurado"
    fi
    exit 0
fi

SYS="${2:?falta la raiz de Talos}"
BRIEF="${3:-}"

cd "$PROJ"

SHIM="$SYS/hooks/agent/opencode/pre-tool-use.sh"
PLANTILLA="$SYS/hooks/agent/opencode/plugin.js"
[ -x "$SHIM" ] || { echo "talos: falta el shim $SHIM" >&2; exit 1; }
[ -f "$PLANTILLA" ] || { echo "talos: falta la plantilla $PLANTILLA" >&2; exit 1; }

# ---------- 1. el plugin que bloquea ----------
#
# Se escribe un archivo PROPIO bajo .opencode/plugin/, que opencode descubre
# solo. No se toca ningun plugin ajeno: cobrarse el enforcement con la
# configuracion de una persona seria el mismo error que pisarle un settings.
mkdir -p "$(dirname "$PLUGIN_REL")"
sed "s|__TALOS_SHIM__|$SHIM|" "$PLANTILLA" > "$PLUGIN_REL"

# El bloqueo tiene que quedar instalado de verdad, no intentado.
grep -q "$SHIM" "$PLUGIN_REL" || {
    echo "talos: el plugin quedo sin la ruta del shim" >&2
    exit 1
}

# ---------- 2. el brief donde el agente lo lee ----------
if [ -n "$BRIEF" ] && [ -f "$BRIEF" ]; then
    if [ -f "$BRIEF_DST" ] && ! head -1 "$BRIEF_DST" | grep -q "$MARCA"; then
        # Hay un AGENTS.md que no es de Talos: se guarda antes de tomar el
        # lugar. El brief tiene que ser lo que el agente lee, y dos briefs
        # concatenados son un brief ambiguo.
        cp "$BRIEF_DST" "$BACKUP"
    fi
    {
        echo "<!-- $MARCA al despachar un agente. Se borra al liberar el rol. -->"
        echo ""
        cat "$BRIEF"
    } > "$BRIEF_DST"
fi

exit 0
