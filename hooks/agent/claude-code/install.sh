#!/bin/sh
# Instala el enforcement de Talos en el runtime de Claude Code.
#
# Un shim por runtime, igual que pre-tool-use.sh. El nucleo no conoce
# .claude/settings.json ni CLAUDE.md: son detalles de ESTE agente. Cambiar de
# runtime es escribir otro instalador, no rehacer la politica.
#
# Hace dos cosas, y las dos hacen falta:
#
#   1. Registra el hook PreToolUse. Sin esto el alcance esta DECLARADO y no
#      IMPUESTO: el agente lo respeta por criterio propio, que es exactamente
#      lo que Talos existe para no depender.
#
#   2. Deja el brief donde el agente lo lee. Pasarlo por linea de comandos es
#      fragil -son cien lineas con saltos y comillas- y se rompe en silencio:
#      el agente arranca igual, sin instrucciones y sin saber que le faltan.
#
# Uso:   install.sh <raiz-del-proyecto> <raiz-de-talos> <archivo-de-brief>
#        install.sh <raiz-del-proyecto> --uninstall
# Sale:  0 instalado / 1 no se pudo

set -eu

PROJ="${1:?falta la raiz del proyecto}"

# Retirar lo que se instalo es parte del mismo shim: el nucleo no sabe que
# existe CLAUDE.md, asi que tampoco puede borrarlo.
if [ "${2:-}" = "--uninstall" ]; then
    cd "$PROJ"
    if [ -f CLAUDE.md ] && head -1 CLAUDE.md | grep -q "GENERADO por Talos"; then
        rm -f CLAUDE.md
        echo "brief retirado (CLAUDE.md)"
    fi
    # El hook TAMBIEN se retira. Retirar solo el brief dejaba el bloqueo
    # registrado en .claude/settings.json de una sesion que Talos ya no
    # gobierna: apuntando a una ruta de .talos/ que puede no existir, y
    # bloqueando escrituras segun un rol que ya nadie activo. Instalar es
    # reversible o no es instalar.
    if [ -f .claude/settings.json ]; then
        _py=""
        for _c in "$PROJ/.venv/bin/python" "$HOME/.venv/bin/python"; do
            [ -x "$_c" ] && { _py="$_c"; break; }
        done
        [ -n "$_py" ] || _py=$(command -v python3 2>/dev/null) || _py=""
        if [ -n "$_py" ]; then
            "$_py" - <<'PYEOF'
import json, pathlib

p = pathlib.Path(".claude/settings.json")
try:
    cfg = json.loads(p.read_text())
except (json.JSONDecodeError, OSError):
    raise SystemExit(0)

# Se saca SOLO lo que puso Talos, reconocido por la ruta del shim. Lo que la
# persona haya configurado no es de Talos y no se toca.
def es_de_talos(h):
    return "hooks/agent/claude-code/pre-tool-use.sh" in str(h.get("command", ""))

pre = (cfg.get("hooks") or {}).get("PreToolUse") or []
quedan, saco = [], False
for e in pre:
    hs = [h for h in e.get("hooks", []) if not es_de_talos(h)]
    if len(hs) != len(e.get("hooks", [])):
        saco = True
    if hs:
        e["hooks"] = hs
        quedan.append(e)
    elif not e.get("hooks"):
        quedan.append(e)

if not saco:
    raise SystemExit(0)

if quedan:
    cfg["hooks"]["PreToolUse"] = quedan
else:
    cfg["hooks"].pop("PreToolUse", None)
    if not cfg["hooks"]:
        cfg.pop("hooks", None)

# Un settings.json que queda vacio por retirar lo unico que tenia es un
# archivo que Talos creo: se lleva lo suyo entero.
if cfg:
    p.write_text(json.dumps(cfg, indent=2) + "\n")
else:
    p.unlink()
print("bloqueo retirado (.claude/settings.json)")
PYEOF
        fi
    fi
    exit 0
fi

SYS="${2:?falta la raiz de Talos}"
BRIEF="${3:-}"

cd "$PROJ"
mkdir -p .claude

SHIM="$SYS/hooks/agent/claude-code/pre-tool-use.sh"
[ -x "$SHIM" ] || { echo "talos: falta el shim $SHIM" >&2; exit 1; }

# ---------- 1. el hook que bloquea ----------
#
# Se fusiona con lo que ya haya. Pisar settings.json de una persona para
# instalar un hook seria cobrarse el enforcement con su configuracion.
PY=""
for c in "$PROJ/.venv/bin/python" "$SYS/.venv/bin/python"; do
    [ -x "$c" ] && { PY="$c"; break; }
done
[ -n "$PY" ] || PY=$(command -v python3 2>/dev/null) || {
    echo "talos: no hay python3 para editar .claude/settings.json" >&2; exit 1; }

"$PY" - "$SHIM" <<'PYEOF' || exit 1
import json, pathlib, sys

shim = sys.argv[1]
p = pathlib.Path(".claude/settings.json")
try:
    cfg = json.loads(p.read_text()) if p.is_file() else {}
except json.JSONDecodeError:
    print("talos: .claude/settings.json no es JSON valido; no se toca",
          file=sys.stderr)
    raise SystemExit(1)

hooks = cfg.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])

# Las herramientas que escriben. Leer no necesita permiso de alcance: el
# bloqueo es sobre lo que el agente MODIFICA.
matcher = "Write|Edit|MultiEdit|NotebookEdit"
entrada = {"matcher": matcher,
           "hooks": [{"type": "command", "command": shim}]}

# Idempotente: si ya esta el mismo shim para el mismo matcher, no se duplica.
for e in pre:
    if e.get("matcher") != matcher:
        continue
    for h in e.get("hooks", []):
        if h.get("command") == shim:
            raise SystemExit(0)
    e.setdefault("hooks", []).append({"type": "command", "command": shim})
    break
else:
    pre.append(entrada)

p.write_text(json.dumps(cfg, indent=2) + "\n")
PYEOF

# ---------- 2. el brief donde el agente lo lee ----------
if [ -n "$BRIEF" ] && [ -f "$BRIEF" ]; then
    {
        echo "<!-- GENERADO por Talos al despachar un agente. Se borra al liberar el rol. -->"
        echo ""
        cat "$BRIEF"
    } > CLAUDE.md
fi

exit 0
