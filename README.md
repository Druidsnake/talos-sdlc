# Thalos — Guardián del ciclo de desarrollo con IA

Thalos es un marco normativo para orquestar desarrollo de software asistido por agentes: intake de spec, planificación, desarrollo, revisión, pruebas, aprobación y merge, con trazabilidad completa y supervisión humana en las rutas críticas.

**Estado actual: la spec está implementada.** Los trece pasos de la ruta, las veintisiete transiciones de feature, el loop que las recorre y los presupuestos que lo frenan. Hay implementaciones productivas de las tres capacidades que tocan el mundo —Herdr para ejecutar agentes, GitHub para coordinar, GitHub Actions para verificar— y el `MergeGate` que gobierna el merge.

El repo se queda en `dry-run-only` a propósito: su propia suite no puede depender de tener credenciales ni herramientas instaladas. Lo que falta son las [decisiones abiertas](#decisiones-abiertas) y usarlo en serio.

---

## Quick path

1. Leé [`thalos-0.0.7.md`](thalos-0.0.7.md) — la especificación del núcleo.
2. Si te interesa la memoria persistente, leé [`thalos-memory-0.0.1.md`](thalos-memory-0.0.1.md) — extensión **opcional**.
3. Empezá por las secciones 22 (ciclo de vida), 23 (evidencia) y 24 (gates). Son el corazón del sistema.

---

## Instalación

Dos formas, y no compiten.

**Una sola copia, todos los proyectos.** Enlazá el lanzador a un directorio que ya esté en tu `PATH`:

```sh
ln -s "$PWD/cli/thalos" ~/.local/bin/thalos
```

Desde ahí `thalos` funciona en cualquier repo sin copiar nada: la raíz del **sistema** sale de dónde vive el lanzador —siguiendo la cadena de enlaces— y la raíz del **proyecto** sale del repo donde estás parado.

**Vendoreado en `.thalos/`.** Copiar el sistema dentro del proyecto fija una versión para ese proyecto.

### Cuál gana

```txt
1. THALOS_SYSTEM_ROOT exportado    quien lo exporta sabe lo que hace
2. .thalos/ del proyecto           el proyecto fijó SU versión
3. la instalación que se invocó    el caso normal
```

El punto 2 no es cortesía. Un proyecto que vendorea eligió una versión y sus artefactos están escritos contra ella; correrle encima otra es una **migración** (sección 12.3), no una rutina. Sin esa precedencia, actualizar tu instalación cambiaría en silencio la versión que corre en proyectos que habían decidido no moverse.

---

## Qué hay acá

| Archivo | Contenido | Versión |
|---|---|---|
| [`thalos-0.0.7.md`](thalos-0.0.7.md) | Especificación del núcleo | 0.0.6 |
| [`thalos-memory-0.0.1.md`](thalos-memory-0.0.1.md) | Extensión opcional de memoria persistente | 0.0.1 |
| [`history/`](history/) | Versiones superadas | 0.0.4, 0.0.5 |

---

## Integraciones: capacidad requerida ≠ implementación elegida

Esta es la distinción que gobierna todo el modelo de extensión, y conviene entenderla antes de leer la spec.

Thalos define **capacidades** (extension points). Cada capacidad la satisface una **implementación** concreta (un adapter). Una capacidad puede ser requerida y su implementación seguir siendo reemplazable — son dos ejes distintos.

| Capacidad | ¿Requerida? | Implementación de referencia | Binario externo |
|---|---|---|---|
| `FileSystemAdapter` | sí | `thalos-adapter-filesystem` | — |
| `ModelProviderAdapter` | sí | `thalos-adapter-model` | — |
| `ExecutionAdapter` | **sí** | **`thalos-adapter-herdr`** | `herdr >= 0.7.0` |
| `CoordinationAdapter` | sí | `thalos-adapter-github` | `git`, `gh` |
| `CIAdapter` | sí | `thalos-adapter-ci` | — |
| `MemoryAdapter` | **no** | `thalos-adapter-engram` | `engram` |
| `Plugin` | no | `thalos-plugin-herdr` | — |

Leído en concreto:

- **Herdr es requerido en una instalación productiva**, porque los agentes tienen que ejecutarse en algún lado. Pero el núcleo nunca lo nombra: escribís otro `ExecutionAdapter` y Thalos no se entera.
- **Engram es opcional de punta a punta.** Implementa una capacidad opcional. Cero implementaciones de `MemoryAdapter` es un estado perfectamente válido.

### Modos de operación

| Modo | Qué necesita instalado | Para qué sirve |
|---|---|---|
| `dry-run-only` | nada | validar el sistema, correr los tests de Thalos |
| `partial` | Herdr | ejecutar agentes sin tocar el repositorio remoto |
| `production` | Herdr, git, gh | ejecución real |

Arrancás en `dry-run-only` y subís cuando cada modo cumple sus criterios.

### Thalos no instala nada por vos

Cuando falta un binario, `thalos doctor` lo detecta, te dice la versión requerida y te da el comando exacto. No lo instala solo. La resolución del binario baja por cascada:

```txt
$THALOS_HERDR_BIN  ->  .thalos/bin/herdr  ->  PATH
```

Herdr gestiona workspaces y paneles de terminal, que es estado a nivel de máquina. Por eso se instala a nivel de sistema y **no se vendorea por proyecto** — dos copias pelearían por los mismos paneles, igual que pasaría vendoreando `tmux`.

---

## Ideas centrales

| Principio | Qué significa |
|---|---|
| **El sistema no es el producto** | Thalos vive en `.thalos/`; el spec del producto vive en `spec/`. Thalos nunca escribe reglas propias dentro de `spec/`. |
| **Toda transición exige evidencia** | Ningún estado avanza sin un artefacto tipado y verificable que lo justifique. La salida de un agente no es evidencia verificable. |
| **Los gates son código, no criterio** | Un `GateEvaluator` es una función pura de evidencia, policy y configuración. No invoca modelos. |
| **El núcleo no conoce vendors** | Toda integración externa es un adapter. El sistema debe poder correr solo con el adapter dry-run. |
| **Las extensiones son consultivas** | Ninguna extensión puede aprobar un gate, producir evidencia ni anular el spec aprobado. |
| **El humano aprueba lo crítico** | Riesgo `critical` exige `HumanApprover`. El auto-merge está deshabilitado por defecto. |
| **Toda identidad lleva su procedencia** | Una referencia dice quién la produjo, y no se usa contra otro productor. Que un recurso se haya creado no prueba que siga existiendo: se reconcilia contra el backend, no contra el registro local. |
| **La comunicación no se corta** | Lo estructurado es el sobre y lo pone Thalos; el contenido puede ser ruido. Ninguna respuesta se descarta por no tener el formato esperado: se persiste y se entrega a quien pueda actuar. |
| **Un paso sin evidencia no avanzó** | Reportar éxito sin el artefacto hace que el loop lo cuente como progreso y repita hasta agotar el presupuesto. La condición de terminación es el artefacto, no un estado del runtime. |

---

## Arquitectura en una vista

```txt
spec/            <- qué construir           (fuente de verdad del producto)
.thalos/          <- cómo construirlo        (el sistema, versionado)
orchestration/   <- qué pasó                (estado runtime + event log)
src/ tests/      <- lo construido           (resultado)
```

Dentro del sistema:

```txt
schemas/         <- los contratos           (único enforcement duro)
config/          <- qué está ligado a qué   (roles, capacidades, modo)
adapters/        <- toda integración externa
hooks/           <- los bloqueos ejecutables
cli/             <- la superficie de uso
```

El event log es la fuente de verdad del estado. `state.json` es una proyección reconstruible.

---

## Estado de madurez

| Aspecto | Estado |
|---|---|
| Especificación del núcleo | completa para piloto serial |
| Especificación de memoria | completa, opcional |
| Schemas JSON | 27 definidos y verificados con suite de rechazo |
| CLI `thalos` | `init`, `doctor`, `spec check`, `status`, `next`, `run`, `boot`, `rules`, `adapters`, `gate`, `evidence`, `plan`, `feature`, `merge`, `human`, `budget`, `event`, `message` |
| Registro de capacidades | implementado (`config/extensions.yaml`) |
| Adapters | 5 de simulación + 3 productivos (Herdr, GitHub, CI) |
| Contrato de ejecución | ciclo de vida completo: abrir, arrancar, promptear, esperar, leer, ejecutar y **cerrar** |
| Resolución de binarios | cascada de 37.4.5 con verificación de versión |
| Máquina de estados y gates | 52 transiciones derivadas de la spec, `GateEvaluator` puro |
| Evidencia | digest verificado, `GateResult` persistido e inmutable |
| `thalos plan` | `PLAN_GATE` completo sobre el grafo de features |
| `thalos feature` | `start`, `dispatch` con rol y alcance, `work`, `commit`, `test`, `collect`, `pr`, `checks`, `advance`, `release` |
| `thalos boot` | enciende al coordinador y le cede la decisión del próximo paso |
| `thalos message` | la comunicación no se pierde: lo que el agente diga se registra y se entrega |
| `thalos merge` | `MERGE_GATE` con siete condiciones, delega en el adapter |
| `thalos next` / `run` | proyección de qué sigue y loop acotado |
| `thalos human` | la vía por la que una persona acuña su decisión |
| Presupuestos | frenan la ejecución; nunca degradan el tier |
| Ejecutor de transiciones | gate, evento y proyección de estado |
| LockManager | leases con TTL y fencing token |
| Ciclo completo | verificado de punta a punta con agentes reales hasta `FEATURE_CHECKS_RUNNING` |
| Modo actual | `dry-run-only`, serial, un feature a la vez |
| Suite | 630 checks + shellcheck |

---

## Decisiones abiertas

Estas bloquean versiones futuras y están documentadas en la [sección 50](thalos-0.0.7.md#50-decisiones-abiertas):

| ID | Decisión | Bloquea |
|---|---|---|
| D-001 | Nombre del binario ante la colisión con Talos Linux (Sidero Labs) | v0.1.0 |
| D-002 | Backend del state store: archivos o SQLite | paralelismo > 1 |
| D-003 | Estrategia de merge por defecto | primer merge real |
| D-004 | Alcance del primer vertical slice | inicio de implementación |

---

## Cómo evolucionó

La versión 0.0.5 es una corrección estructural de 0.0.4, no un incremento de features. Se arreglaron una contradicción normativa que invertía la autoridad de la memoria sobre el spec aprobado, la ausencia total de tabla de transiciones, la falta de definición del término "evidencia", locks sin expiración que permitían deadlock permanente y adapters sin idempotencia que duplicaban PRs al reintentar. El detalle completo está en el [changelog](thalos-0.0.7.md#49-changelog).

La memoria persistente ocupaba el 38% del documento del núcleo siendo una feature opcional. Se extrajo a su propio documento versionado de forma independiente.

La versión 0.0.6 separa la **capacidad** de la **implementación**. Antes, marcar `thalos-adapter-herdr` como "opcional" era arquitectónicamente cierto y operacionalmente engañoso: el adapter es reemplazable, pero la capacidad que implementa no es prescindible. Ahora cada extension point se clasifica como requerido u opcional, independientemente de qué adapter lo satisface, y aparecen los modos de operación que hacen explícito qué hace falta instalar para cada nivel de uso.

La versión 0.0.7 no salió de leer el documento: salió de **correr el ciclo completo contra agentes reales** hasta verlo cerrar. Cada corrección es un defecto que solo aparecía ejecutando, y la mayoría estaba tapada por probar los pasos por separado en vez del ciclo entero.

Cuatro de esos defectos resultaron ser el mismo: una referencia que no llevaba consigo quién la había producido. El ledger devolvía ids fabricados por el simulador a un adapter productivo; devolvía recursos que ya no existían; dos proyectos con una `F001` se robaban el agente; y un `Reviewer` despachado sobre una feature que ya tuvo `Developer` terminaba siendo el mismo agente, revisando su propio trabajo. Los cuatro reportaban éxito.

El otro hallazgo grande fue de comunicación. La sección 25 estaba especificada entera —tipos, estados, hilos, expiración— y no la implementaba nadie. Un agente contestó *"no puedo seguir, confirmame si reiniciaron el workspace"* y Thalos lo descartó porque esperaba un archivo con otro formato. La regla pedía comunicación "estructurada", y exigirle esa estructura al emisor es justamente lo que la rompe.

---

## Próximo paso

Los pasos 1 a 6 de la [sección 51](thalos-0.0.7.md#51-ruta-de-implementación-recomendada) están hechos. Falta cerrar el modo `dry-run-only`:

El modo `dry-run-only` está cerrado. Un ciclo completo corre hoy:

```bash
thalos doctor          # preconditions y capacidades
thalos spec check      # el spec del producto
thalos plan check      # PLAN_GATE sobre el grafo
thalos feature start F001
```

El paso 9 está hecho: `thalos.adapter.herdr` implementa `ExecutionAdapter` de verdad. Pasar a `partial` es cambiar una ligadura — ver [`adapters/README.md`](adapters/README.md#pasar-a-modo-partial).

Los trece pasos están hechos, las 27 transiciones son recorribles y el loop avanza lo que los gates autoricen.

```bash
thalos next                 # qué sigue, y qué evidencia falta para cada salida
thalos run                  # avanza mientras esté autorizado; para ante un humano
thalos budget               # consumido contra declarado
```

Lo que queda son las [decisiones abiertas](#decisiones-abiertas) —D-001 bloquea v0.1.0— y usarlo en un proyecto real el tiempo suficiente para que aparezca lo que ninguna suite anticipa.

Cambiar de modo es reemplazar ligaduras en `config/extensions.yaml`, no reescribir el núcleo:

```yaml
ExecutionAdapter:    { implementation: thalos.adapter.herdr }
CoordinationAdapter: { implementation: thalos.adapter.github }
CIAdapter:           { implementation: thalos.adapter.github_ci }
```

Recién después de eso el paso 9 reemplaza el `ExecutionAdapter` dry-run por uno productivo, que es donde los agentes empiezan a trabajar de verdad.

### La tabla de transiciones no se escribe a mano

`tools/build-transitions.py` la extrae de las secciones 22.4 y 22.5 de la spec. Una copia manual en otro archivo podría divergir del contrato, y la que gobernaría la ejecución no sería la normativa.

```bash
thalos gate --from feature FEATURE_READY   # qué transiciones salen de un estado
thalos gate feature FEATURE_READY FEATURE_IN_PROGRESS
```

El gate es una función pura de evidencia, policy y config. No invoca modelos: un gate que llama a un modelo no es un gate, es una opinión.

---

## Licencia

Por definir.
