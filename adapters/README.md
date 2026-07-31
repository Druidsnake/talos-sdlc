# Adapters

Toda integración externa de Talos entra por acá. El núcleo define **puertos**; los adapters los implementan.

## La distinción que gobierna todo

Talos separa dos ejes que se confunden fácil:

| | Qué es | Quién decide |
|---|---|---|
| **Capacidad** | un extension point que el sistema necesita | la spec (`talos-0.0.6.md` 37.4.2) |
| **Implementación** | un adapter concreto que la satisface | vos, en `config/extensions.yaml` |

Una capacidad puede ser **requerida** y su implementación seguir siendo **reemplazable**. Marcar un adapter como "opcional" porque es intercambiable era arquitectónicamente cierto y operacionalmente engañoso: por eso 0.0.6 separó los dos ejes.

- Cero implementaciones de una capacidad **REQUERIDA** → falla en `PRECONDITION_GATE`.
- Cero implementaciones de una capacidad **OPCIONAL** → estado perfectamente válido.

Verificá el estado actual con:

```bash
talos adapters
```

## Qué hay acá

Los cinco adapters de referencia satisfacen las cinco capacidades requeridas en modo `dry-run-only`. Ninguno depende de un binario externo, que es lo que permite correr el sistema sin nada instalado (regla 37.4.4.1).

| Directorio | Capacidad | Qué hace |
|---|---|---|
| `fs_local/` | `FileSystemAdapter` | operaciones reales sobre el filesystem local |
| `model_dryrun/` | `ModelProviderAdapter` | respuestas canónicas, no invoca ningún modelo |
| `exec_dryrun/` | `ExecutionAdapter` | simula workspaces, sesiones y agentes |
| `coord_dryrun/` | `CoordinationAdapter` | simula issues, ramas y PRs sin tocar el remoto |
| `ci_dryrun/` | `CIAdapter` | simula checks; el `CheckRunSet` sale `verifiable: false` |

`lib/adapter.sh` es infraestructura compartida entre implementaciones. **No es núcleo** — el núcleo nunca la carga.

## Anatomía de un adapter

```txt
adapters/<nombre>/
  adapter.yaml    manifiesto, valida contra schemas/adapter-manifest.schema.json
  run.sh          ejecutable: run.sh <operacion> [semantic_args_json]
```

Un manifiesto sin ejecutable es una declaración, no un adapter.

### El manifiesto

Declara qué capacidad implementa, qué operaciones expone y cómo se comporta cada una:

```yaml
id: talos.adapter.mi_impl        # namespace obligatorio: talos.adapter.*
implements: CoordinationAdapter  # una sola capacidad por adapter
supports_dry_run: true           # regla 38.1.5, no negociable

health_check:
  command: run.sh health

operations:
  - name: create_issue
    mutating: true
    idempotency: required        # obligatorio si mutating: true
    max_attempts: 3
```

Los nombres de las operaciones **no son libres**: cada capacidad tiene su contrato en la sección 38.4 de la spec, y `tests/test_adapters.py` verifica que estén todas.

### Idempotencia

Toda operación que mute estado externo acepta una `idempotency_key` derivada de forma determinista:

```txt
sha256(run_id : feature_id : operation : canonical_json(semantic_args))
```

`semantic_args` **no debe** contener timestamps ni valores no deterministas — eso es responsabilidad de quien llama, porque el adapter no puede saber qué campo es semántico.

Reintentar con los mismos argumentos devuelve `already_exists` en vez de crear un duplicado:

```json
{ "status": "already_exists", "resource_ref": {...}, "idempotency_key": "..." }
```

Sin esto, un reintento duplicaba PRs e issues. Es el defecto concreto de 0.0.4 que corrige la sección 38.2.

Cuando el adapter **no puede** garantizar idempotencia — la salida de un modelo no es reproducible, un comando arbitrario tiene efectos de lado arbitrarios — declara `idempotency: at_most_once` y el núcleo no lo reintenta solo.

## Escribir el tuyo

1. Creá `adapters/<nombre>/adapter.yaml` con las operaciones que exige la sección 38.4 para esa capacidad.
2. Escribí `run.sh`, sourceando `../lib/adapter.sh` para no reimplementar la idempotencia.
3. Ligá la capacidad a tu implementación en `config/extensions.yaml`.
4. Recompilá la tabla que lee el núcleo:

```bash
python3 tools/build-registry.py
```

5. Verificá:

```bash
talos adapters && ./tools/check-all.sh
```

Reemplazar una implementación **no toca el núcleo**: se cambia una línea en `config/extensions.yaml`. Si escribiendo un adapter necesitás modificar algo bajo `cli/`, `hooks/` o `system/`, algo está mal en el diseño.

## Por qué el núcleo nunca nombra un adapter

La regla 37.4.3.5 dice que el núcleo no puede nombrar implementaciones concretas fuera del extension registry. `config/extensions.yaml` y estos manifiestos son los únicos lugares donde aparece un id `talos.adapter.*`.

`hooks/lib/resolve-capability.sh` resuelve capacidad → implementación leyendo `hooks/generated/capabilities.tsv`, que `tools/build-registry.py` compila desde el registry. Ese archivo generado contiene ids concretos y no viola la regla: es una **proyección** del registry, igual que `state.json` es una proyección del event log.

`tests/test_adapters.py` verifica la regla con un grep sobre `cli/`, `hooks/` y `system/`. Si cableás un adapter en el núcleo, el test falla.

## Binarios externos

Un adapter que dependa de un binario lo declara en su manifiesto:

```yaml
external_binary:
  name: herdr
  version_range: ">=0.7.0"
  env_override: TALOS_HERDR_BIN
  install_hint: "brew install herdr"
  machine_level: true
```

La resolución baja por cascada, primera coincidencia gana:

```txt
$TALOS_HERDR_BIN  ->  .talos/bin/herdr  ->  PATH
```

Talos **nunca instala nada**: detecta, te dice la versión requerida y te da el comando exacto.

`machine_level: true` marca herramientas que gestionan estado de máquina o de sesión de terminal. Esas **no se vendorean por proyecto**: dos copias pelearían por el mismo recurso, igual que pasaría vendoreando `tmux`.

## Modos de operación

| Modo | ExecutionAdapter | CoordinationAdapter | CIAdapter |
|---|---|---|---|
| `dry-run-only` | dryrun | dryrun | dryrun |
| `partial` | productivo | dryrun | dryrun |
| `production` | productivo | productivo | productivo |

Se declara en `config/system.yaml`. En `dry-run-only`:

- no se puede producir evidencia con `verifiable: true` (regla 37.4.4.2),
- no se puede alcanzar `FEATURE_MERGED` (regla 37.4.4.3).

Subir de modo es reemplazar ligaduras en `config/extensions.yaml`, no reescribir el núcleo.
