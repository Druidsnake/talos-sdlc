# hooks/agent/

Conecta el mecanismo 2 al runtime del agente: la denegación ocurre **antes** de la escritura, no después.

```txt
runtime del agente
      |  payload propio de cada runtime
      v
<runtime>/pre-tool-use.sh    <- shim: extrae herramienta y ruta, traduce el veredicto
      |  (herramienta, ruta)
      v
check-tool-call.sh           <- generico: resuelve el rol, normaliza la ruta
      |  (rol, ruta)
      v
../check-write-scope.sh      <- decide contra las reglas generadas
```

Un shim por runtime, un checker para todos. Cambiar de agente es escribir un shim, no rehacer la política.

---

## Cómo se resuelve el rol

```txt
1. $TALOS_ROLE
2. orchestration/.current-role
3. sin rol -> la llamada pasa
```

El paso 3 es deliberado. **Sin rol activo, Talos no está gobernando esa sesión** y no tiene por qué opinar sobre lo que escribís. El rol lo fija Talos al despachar un agente, no lo elige el agente.

---

## Lo que este mecanismo NO cubre

Decirlo importa más que taparlo.

**El tool de shell queda fuera.** No se puede saber de forma confiable qué rutas toca un comando arbitrario: `sh -c 'cat > x'`, un script, un `make`, un editor invocado desde adentro. Filtrar por texto del comando da falsa sensación de seguridad. El checker ignora esas llamadas en vez de fingir que las controla.

La cobertura real es sobre las herramientas de archivo declaradas: `Write`, `Edit`, `MultiEdit`, `NotebookEdit` y sus equivalentes.

**Es una barrera de conveniencia, no una real.** Corre en la misma máquina que el agente. Lo que no se saltea es el mecanismo 3 (CI) y el 5 (protección de rama), porque corren del otro lado. Ver [`system/00-enforcement.md`](../../system/00-enforcement.md) §3.1.

La consecuencia práctica: el hook de agente sirve para que un agente bien intencionado **no se equivoque**. Para lo que un agente pueda hacer mal, la barrera está en CI.

---

## Escribir un shim para otro runtime

El contrato es chico. Un shim tiene que:

1. Leer el payload del runtime.
2. Extraer el **nombre de la herramienta** y la **ruta de destino**.
3. Llamar a `check-tool-call.sh <herramienta> <ruta>`.
4. Traducir el código de salida al formato de decisión del runtime.

```sh
if reason=$(../check-tool-call.sh "$tool" "$file" 2>&1); then
    # permitido
else
    # denegado: $reason explica por qué
fi
```

Si no podés extraer la ruta, salí con 0. Denegar por no haber podido parsear convierte cualquier cambio de formato en un bloqueo total.

---

## Claude Code

El shim está en [`claude-code/pre-tool-use.sh`](claude-code/pre-tool-use.sh). Parsea con `jq`, y si no está, con `python3`.

En `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/hooks/agent/claude-code/pre-tool-use.sh"
          }
        ]
      }
    ]
  }
}
```

Al denegar emite la decisión estructurada **y** sale con código 2, para cubrir las dos convenciones. El contrato exacto del runtime puede cambiar entre versiones: verificalo contra la tuya antes de confiar en el bloqueo.

---

## Probar

```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"spec/SPEC.md"}}' \
  | TALOS_ROLE=Developer hooks/agent/claude-code/pre-tool-use.sh
```

```txt
talos: DENEGADO Developer no puede escribir en spec/SPEC.md
talos: regla: deny spec/**
```

Los casos automatizados están en `tests/test_hooks.sh`.
