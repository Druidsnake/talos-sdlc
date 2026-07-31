# Talos — Guardián del ciclo de desarrollo con IA

Talos es un marco normativo para orquestar desarrollo de software asistido por agentes: intake de spec, planificación, desarrollo, revisión, pruebas, aprobación y merge, con trazabilidad completa y supervisión humana en las rutas críticas.

**Estado actual: especificación, sin implementación.** Este repositorio contiene el contrato normativo. El código todavía no existe. La [ruta de implementación](talos-0.0.5.md#51-ruta-de-implementación-recomendada) define en qué orden construirlo.

---

## Quick path

1. Leé [`talos-0.0.5.md`](talos-0.0.5.md) — la especificación del núcleo.
2. Si te interesa la memoria persistente, leé [`talos-memory-0.0.1.md`](talos-memory-0.0.1.md) — extensión **opcional**.
3. Empezá por las secciones 22 (ciclo de vida), 23 (evidencia) y 24 (gates). Son el corazón del sistema.

---

## Qué hay acá

| Archivo | Contenido | Versión |
|---|---|---|
| [`talos-0.0.5.md`](talos-0.0.5.md) | Especificación del núcleo | 0.0.5 |
| [`talos-memory-0.0.1.md`](talos-memory-0.0.1.md) | Extensión opcional de memoria persistente | 0.0.1 |
| [`history/talos-0.0.4.md`](history/talos-0.0.4.md) | Versión anterior, superada | 0.0.4 |

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

El event log es la fuente de verdad del estado. `state.json` es una proyección reconstruible.

---

## Estado de madurez

| Aspecto | Estado |
|---|---|
| Especificación del núcleo | completa para piloto serial |
| Especificación de memoria | completa, opcional |
| Schemas JSON | definidos, no implementados |
| CLI `talos` | no implementada |
| Adapters | no implementados |
| Modo objetivo | serial, un feature a la vez, dry-run preferente |

---

## Decisiones abiertas

Estas bloquean versiones futuras y están documentadas en la [sección 50](talos-0.0.5.md#50-decisiones-abiertas):

| ID | Decisión | Bloquea |
|---|---|---|
| D-001 | Nombre del binario ante la colisión con Talos Linux (Sidero Labs) | v0.1.0 |
| D-002 | Backend del state store: archivos o SQLite | paralelismo > 1 |
| D-003 | Estrategia de merge por defecto | primer merge real |
| D-004 | Alcance del primer vertical slice | inicio de implementación |

---

## Cómo evolucionó

La versión 0.0.5 es una corrección estructural de 0.0.4, no un incremento de features. Se arreglaron una contradicción normativa que invertía la autoridad de la memoria sobre el spec aprobado, la ausencia total de tabla de transiciones, la falta de definición del término "evidencia", locks sin expiración que permitían deadlock permanente y adapters sin idempotencia que duplicaban PRs al reintentar. El detalle completo está en el [changelog](talos-0.0.5.md#49-changelog).

La memoria persistente ocupaba el 38% del documento del núcleo siendo una feature opcional. Se extrajo a su propio documento versionado de forma independiente.

---

## Próximo paso

Construir el primer vertical slice: `talos doctor` → `talos spec check` → `talos plan` → `talos feature start` en dry-run, sin extensiones. Ver [sección 51](talos-0.0.5.md#51-ruta-de-implementación-recomendada).

---

## Licencia

Por definir.
