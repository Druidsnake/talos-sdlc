# Talos — Guardián del ciclo de desarrollo con IA

Talos es un marco normativo para orquestar desarrollo de software asistido por agentes: intake de spec, planificación, desarrollo, revisión, pruebas, aprobación y merge, con trazabilidad completa y supervisión humana en las rutas críticas.

**Estado actual: `dry-run-only` ejecutable.** El contrato normativo está completo y hay un slice vertical que corre: CLI, schemas, registro de capacidades y cinco adapters de referencia. Faltan la máquina de estados, los gates y la ejecución real. La [ruta de implementación](talos-0.0.6.md#51-ruta-de-implementación-recomendada) define el orden.

---

## Quick path

1. Leé [`talos-0.0.6.md`](talos-0.0.6.md) — la especificación del núcleo.
2. Si te interesa la memoria persistente, leé [`talos-memory-0.0.1.md`](talos-memory-0.0.1.md) — extensión **opcional**.
3. Empezá por las secciones 22 (ciclo de vida), 23 (evidencia) y 24 (gates). Son el corazón del sistema.

---

## Qué hay acá

| Archivo | Contenido | Versión |
|---|---|---|
| [`talos-0.0.6.md`](talos-0.0.6.md) | Especificación del núcleo | 0.0.6 |
| [`talos-memory-0.0.1.md`](talos-memory-0.0.1.md) | Extensión opcional de memoria persistente | 0.0.1 |
| [`history/`](history/) | Versiones superadas | 0.0.4, 0.0.5 |

---

## Integraciones: capacidad requerida ≠ implementación elegida

Esta es la distinción que gobierna todo el modelo de extensión, y conviene entenderla antes de leer la spec.

Talos define **capacidades** (extension points). Cada capacidad la satisface una **implementación** concreta (un adapter). Una capacidad puede ser requerida y su implementación seguir siendo reemplazable — son dos ejes distintos.

| Capacidad | ¿Requerida? | Implementación de referencia | Binario externo |
|---|---|---|---|
| `FileSystemAdapter` | sí | `talos-adapter-filesystem` | — |
| `ModelProviderAdapter` | sí | `talos-adapter-model` | — |
| `ExecutionAdapter` | **sí** | **`talos-adapter-herdr`** | `herdr >= 0.7.0` |
| `CoordinationAdapter` | sí | `talos-adapter-github` | `git`, `gh` |
| `CIAdapter` | sí | `talos-adapter-ci` | — |
| `MemoryAdapter` | **no** | `talos-adapter-engram` | `engram` |
| `Plugin` | no | `talos-plugin-herdr` | — |

Leído en concreto:

- **Herdr es requerido en una instalación productiva**, porque los agentes tienen que ejecutarse en algún lado. Pero el núcleo nunca lo nombra: escribís otro `ExecutionAdapter` y Talos no se entera.
- **Engram es opcional de punta a punta.** Implementa una capacidad opcional. Cero implementaciones de `MemoryAdapter` es un estado perfectamente válido.

### Modos de operación

| Modo | Qué necesita instalado | Para qué sirve |
|---|---|---|
| `dry-run-only` | nada | validar el sistema, correr los tests de Talos |
| `partial` | Herdr | ejecutar agentes sin tocar el repositorio remoto |
| `production` | Herdr, git, gh | ejecución real |

Arrancás en `dry-run-only` y subís cuando cada modo cumple sus criterios.

### Talos no instala nada por vos

Cuando falta un binario, `talos doctor` lo detecta, te dice la versión requerida y te da el comando exacto. No lo instala solo. La resolución del binario baja por cascada:

```txt
$TALOS_HERDR_BIN  ->  .talos/bin/herdr  ->  PATH
```

Herdr gestiona workspaces y paneles de terminal, que es estado a nivel de máquina. Por eso se instala a nivel de sistema y **no se vendorea por proyecto** — dos copias pelearían por los mismos paneles, igual que pasaría vendoreando `tmux`.

---

## Ideas centrales

| Principio | Qué significa |
|---|---|
| **El sistema no es el producto** | Talos vive en `.talos/`; el spec del producto vive en `spec/`. Talos nunca escribe reglas propias dentro de `spec/`. |
| **Toda transición exige evidencia** | Ningún estado avanza sin un artefacto tipado y verificable que lo justifique. La salida de un agente no es evidencia verificable. |
| **Los gates son código, no criterio** | Un `GateEvaluator` es una función pura de evidencia, policy y configuración. No invoca modelos. |
| **El núcleo no conoce vendors** | Toda integración externa es un adapter. El sistema debe poder correr solo con el adapter dry-run. |
| **Las extensiones son consultivas** | Ninguna extensión puede aprobar un gate, producir evidencia ni anular el spec aprobado. |
| **El humano aprueba lo crítico** | Riesgo `critical` exige `HumanApprover`. El auto-merge está deshabilitado por defecto. |

---

## Arquitectura en una vista

```txt
spec/            <- qué construir           (fuente de verdad del producto)
.talos/          <- cómo construirlo        (el sistema, versionado)
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
| Schemas JSON | 25 definidos y verificados con suite de rechazo |
| CLI `talos` | `init`, `doctor`, `spec check`, `status`, `rules`, `adapters`, `gate`, `event append/tail` |
| Registro de capacidades | implementado (`config/extensions.yaml`) |
| Adapters | 5 de referencia en dry-run, uno por capacidad requerida |
| Máquina de estados y gates | 52 transiciones derivadas de la spec, `GateEvaluator` puro |
| `talos plan` / `talos feature start` | no implementados |
| Modo actual | `dry-run-only`, serial, un feature a la vez |
| Suite | 310 checks |

---

## Decisiones abiertas

Estas bloquean versiones futuras y están documentadas en la [sección 50](talos-0.0.6.md#50-decisiones-abiertas):

| ID | Decisión | Bloquea |
|---|---|---|
| D-001 | Nombre del binario ante la colisión con Talos Linux (Sidero Labs) | v0.1.0 |
| D-002 | Backend del state store: archivos o SQLite | paralelismo > 1 |
| D-003 | Estrategia de merge por defecto | primer merge real |
| D-004 | Alcance del primer vertical slice | inicio de implementación |

---

## Cómo evolucionó

La versión 0.0.5 es una corrección estructural de 0.0.4, no un incremento de features. Se arreglaron una contradicción normativa que invertía la autoridad de la memoria sobre el spec aprobado, la ausencia total de tabla de transiciones, la falta de definición del término "evidencia", locks sin expiración que permitían deadlock permanente y adapters sin idempotencia que duplicaban PRs al reintentar. El detalle completo está en el [changelog](talos-0.0.6.md#49-changelog).

La memoria persistente ocupaba el 38% del documento del núcleo siendo una feature opcional. Se extrajo a su propio documento versionado de forma independiente.

La versión 0.0.6 separa la **capacidad** de la **implementación**. Antes, marcar `talos-adapter-herdr` como "opcional" era arquitectónicamente cierto y operacionalmente engañoso: el adapter es reemplazable, pero la capacidad que implementa no es prescindible. Ahora cada extension point se clasifica como requerido u opcional, independientemente de qué adapter lo satisface, y aparecen los modos de operación que hacen explícito qué hace falta instalar para cada nivel de uso.

---

## Próximo paso

Los pasos 1 a 6 de la [sección 51](talos-0.0.6.md#51-ruta-de-implementación-recomendada) están hechos. Falta cerrar el modo `dry-run-only`:

| Paso | Qué falta |
|---|---|
| 7 | `talos plan` |
| 8 | `talos feature start` |

Recién después de eso el paso 9 reemplaza el `ExecutionAdapter` dry-run por uno productivo, que es donde los agentes empiezan a trabajar de verdad.

### La tabla de transiciones no se escribe a mano

`tools/build-transitions.py` la extrae de las secciones 22.4 y 22.5 de la spec. Una copia manual en otro archivo podría divergir del contrato, y la que gobernaría la ejecución no sería la normativa.

```bash
talos gate --from feature FEATURE_READY   # qué transiciones salen de un estado
talos gate feature FEATURE_READY FEATURE_IN_PROGRESS
```

El gate es una función pura de evidencia, policy y config. No invoca modelos: un gate que llama a un modelo no es un gate, es una opinión.

---

## Licencia

Por definir.
