# hooks/

Los puntos de control que se ejecutan **fuera del modelo**. Acá el sistema deja de pedir y empieza a impedir.

Todo lo demás en este repo le dice al agente qué hacer. Esta carpeta le impide hacer otra cosa. Ver [`system/00-enforcement.md`](../system/00-enforcement.md).

---

## Qué hay

| Archivo | Mecanismo | Qué impide |
|---|---|---|
| `check-write-scope.sh` | 2 — bloqueante pre-acción | que un rol escriba fuera de su `write_paths` |
| `validate-artifact.sh` | 1 — validación de schema | que un artefacto inválido cuente como entregable |
| `git/commit-msg` | 4 — git hook | commits sin formato ni trazabilidad a la feature |
| `git/pre-commit` | 4 — git hook | config inválida, schemas rotos, generados desincronizados |
| `lib/resolve-validator.sh` | — | resuelve qué ejecuta la validación |
| `generated/write-scope.rules` | — | compilado de `config/roles.yaml`, **no editar** |

---

## Instalar

```bash
hooks/git/install.sh
```

Crea symlinks en `.git/hooks/`. Si ya tenés un hook propio ahí, no lo pisa: te avisa y sale.

---

## El validador se resuelve, no se instala

Talos necesita un validador de JSON Schema y **no lo instala por vos**. Aplica la misma cascada que [`talos-0.0.7.md` §37.4.5](../talos-0.0.7.md) define para binarios externos:

```txt
$TALOS_VALIDATOR      ->  comando propio, si querés otro
.venv/bin/python      ->  entorno local del proyecto
check-jsonschema      ->  del PATH
ajv                   ->  del PATH
python3 + jsonschema  ->  del PATH
```

Sin ninguno, el hook sale con código 3 y te muestra los comandos de instalación. No adivina, no descarga, no sigue de largo.

```bash
python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml
```

Esta decisión mantiene el sistema honesto: cualquiera puede reemplazar el validador sin tocar los hooks, igual que cualquiera puede reemplazar `talos-adapter-herdr` sin tocar el núcleo.

---

## Fail-closed

`check-write-scope.sh` deniega cuando **ninguna regla `allow` matchea**. No es un descuido:

```bash
$ hooks/check-write-scope.sh Developer package.json
talos: DENEGADO Developer no tiene write_paths que cubra package.json
talos: sin regla allow que matchee, se deniega (fail-closed)
```

`package.json` no está en ninguna lista de prohibiciones. Se bloquea igual. Un sistema que permite lo no contemplado deja de gobernar en cuanto aparece un caso nuevo — y con agentes, los casos nuevos aparecen todo el tiempo.

`deny` gana sobre `allow` siempre.

---

## Las reglas son generadas

`config/roles.yaml` es la fuente de verdad. Los hooks leen `generated/write-scope.rules`, que es plano y se parsea en shell puro sin dependencias.

```bash
python3 tools/build-rules.py
```

El `pre-commit` detecta la deriva: si commiteás `config/roles.yaml` sin regenerar las reglas, rechaza el commit. Y si editás el archivo generado a mano, también.

Compilar una vez mantiene el camino caliente sin dependencias. Un hook que necesita parsear YAML necesita un runtime con YAML; uno que lee líneas separadas por tabs no necesita nada.

---

## Verificar

```bash
tests/test_hooks.sh
```

26 checks. Cada uno afirma que el hook **bloquea** o **permite** un caso concreto. Un hook que nunca deniega no prueba nada.

---

## Qué NO hacen estos hooks

**No revisan calidad.** Ningún hook puede decidir si una revisión fue buena o si un nombre de variable es claro. Eso es semántico y no se fuerza — ver [`system/00-enforcement.md`](../system/00-enforcement.md) §6.3.

**No reemplazan CI.** El `pre-commit` corre en la máquina de quien commitea y se puede saltear con `--no-verify`. Los mecanismos 3 y 5 (CI y protección de rama) son los que no se saltean, porque corren del otro lado.

Esa diferencia importa: un hook local es una barrera de conveniencia; un check de CI es una barrera real.
