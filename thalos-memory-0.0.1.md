# Thalos Memory Extension Specification

**Extension Name:** Thalos Memory
**Canonical Package:** thalos-ext-memory
**Extension Version:** 0.0.1
**Requires Core:** thalos-sdlc >= 0.0.6
**Status:** Experimental — OPCIONAL
**Date:** 2026-07-30
**Document Type:** Extension Specification
**Language:** Spanish normative text
**Origin:** extraído de `thalos-0.0.4.md` secciones 42–54

---

## 0. Convenciones y posición en el sistema

### 0.1. Palabras clave normativas

Las palabras clave DEBE, NO DEBE, REQUERIDO, PUEDE, RECOMENDADO y OPCIONAL deben interpretarse como requisitos normativos.

### 0.2. Naturaleza de esta extensión

`MemoryAdapter` ES una capacidad **OPCIONAL** según `thalos-0.0.7.md` sección 37.4.2. El núcleo DEBE funcionar sin ella, y ningún criterio de aceptación del núcleo PUEDE depender de ella.

Esto la distingue de las capacidades REQUERIDAS como `ExecutionAdapter`, donde el adapter concreto es reemplazable pero la capacidad no es prescindible. Acá tanto la implementación como la capacidad son prescindibles: cero implementaciones de `MemoryAdapter` ES un estado válido del sistema.

`thalos-adapter-engram` ES la implementación de referencia, no un requisito.

### 0.3. Autoridad

Según `thalos-0.0.5.md` sección 43.5, la memoria ocupa el **nivel 5** de la cadena de autoridad de decisión:

```txt
1. Policy y aprobación humana
2. Spec aprobado
3. Evidencia verificable (CI, adapters, estado runtime)
4. Configuración resuelta
5. Contexto consultivo de extensiones      <- memoria
6. Heurísticas del agente
```

Consecuencias normativas:

1. La memoria NO PUEDE anular spec, policy, evidencia ni configuración.
2. La memoria NO PUEDE satisfacer un gate.
3. La memoria NO PUEDE aparecer en `evidence_refs` de una transición.
4. La memoria NO PUEDE autorizar merge.
5. Un fallo de memoria NO DEBE bloquear el flujo principal.

**Corrección respecto de 0.0.4:** en 0.0.4 la sección 41.3 colocaba `memoria consultiva` al final de una cadena `<`, lo que la hacía la fuente de MAYOR precedencia y contradecía directamente a la sección 42.3. Esa contradicción está resuelta en el núcleo 0.0.5 y esta extensión se alinea con la cadena única.

---

## 1. Propósito

La memoria permite que Thalos conserve conocimiento destilado entre ejecuciones.

Objetivos:

```txt
- mejorar planificación,
- reducir errores repetidos,
- recuperar decisiones previas,
- recuperar constraints,
- recuperar lecciones operativas,
- acelerar escalaciones,
- mantener continuidad del proyecto.
```

No objetivos:

```txt
- reemplazar el spec,
- reemplazar policy,
- reemplazar evidencia de CI,
- persistir conversaciones crudas,
- persistir código completo,
- persistir logs completos.
```

---

## 2. Alcance de la versión 0.0.1

Define:

1. Extension point `MemoryAdapter`.
2. Entidad `Memory` y su schema.
3. Ciclo de vida de memorias.
4. Política de escritura con deduplicación asíncrona.
5. Política de recuperación con normalización de ranking definida.
6. Presupuesto de contexto.
7. Métricas computables con señal de feedback definida.
8. Privacidad y gobierno con secret scanning fail-closed.
9. Rol opcional `MemoryCurator`.
10. Eventos `thalos.memory.*`.
11. Comandos CLI `thalos memory *`.
12. Adapter de referencia para Engram.

No define:

1. Memoria vectorial como requisito obligatorio.
2. Curación totalmente automática sin supervisión.
3. Memoria compartida entre proyectos.

---

## 3. Entidad Memory

### 3.1. Campos obligatorios

```txt
id
project
type
title
summary
status
importance
confidence
created_at
```

### 3.2. Campos recomendados

```txt
scope
feature_id
task_id
content
tags
files
artifact_refs
source_event
review_at
updated_at
superseded_by
usage_count
last_used_at
last_useful_at
useful_count
```

**Corrección respecto de 0.0.4:** se añaden `last_useful_at` y `useful_count`. Sin ellos, las métricas `memory_hit_rate` e `irrelevant_memory_rate` de 0.0.4 eran incomputables (ver sección 8).

### 3.3. Tipos

```txt
decision
lesson
constraint
architecture
bug
root_cause
test_strategy
security_note
performance_note
api_contract
workflow_pattern
anti_pattern
escalation_summary
```

### 3.4. Estados

```txt
captured
candidate
validated
active
stale
archived
conflicted
```

### 3.5. Importancia

```txt
low
medium
high
critical
```

### 3.6. Confianza

```txt
low
medium
high
```

---

## 4. MemoryAdapter

### 4.1. Definición

`MemoryAdapter` ES el puerto que integra un backend de memoria persistente.

### 4.2. Capacidades del puerto

```txt
save_memory          [M]
update_memory        [M]
search_memory
get_context
compare_memory
archive_memory       [M]
forget_memory        [M]
memory_stats
detect_conflicts
record_usage         [M]
```

Las operaciones marcadas `[M]` mutan estado externo y REQUIEREN `idempotency_key` según `thalos-0.0.5.md` sección 38.2.

**Corrección respecto de 0.0.4:** se elimina `judge_memory` como capacidad del puerto. Delegar el juicio de conflictos al backend acoplaba el núcleo a una capacidad específica de Engram. La resolución de conflictos ahora es responsabilidad de `MemoryCurator` o de `HumanApprover`, y el adapter solo DEBE detectarlos. Se añade `record_usage`, necesaria para las métricas.

### 4.3. Reglas del puerto

1. `MemoryAdapter` DEBE devolver resultados estructurados.
2. `MemoryAdapter` DEBE soportar scopes por proyecto.
3. `MemoryAdapter` DEBE soportar metadata.
4. `MemoryAdapter` DEBE permitir archivado.
5. `MemoryAdapter` DEBE permitir olvido explícito.
6. `MemoryAdapter` NO DEBE alterar estado runtime del núcleo.
7. `MemoryAdapter` NO DEBE ejecutar acciones de merge.
8. `MemoryAdapter` NO DEBE almacenar secretos.
9. `MemoryAdapter` NO DEBE aprobar gates.
10. `MemoryAdapter` NO DEBE producir evidencia.
11. `MemoryAdapter` DEBE fallar de forma no bloqueante.
12. `MemoryAdapter` DEBE clasificar errores según la sección 35.1 del núcleo.
13. `MemoryAdapter` DEBE registrar eventos `thalos.memory.*`.

### 4.4. Fallo no bloqueante

1. Un timeout de memoria NO DEBE detener una transición de estado.
2. Si `search_memory` falla, el rol DEBE ejecutarse sin contexto de memoria.
3. Si `save_memory` falla, el fallo DEBE registrarse y DEBE reintentarse fuera del camino crítico.
4. El presupuesto de tiempo de una operación de memoria en el camino crítico DEBE ser menor o igual a `config.memory.read_policy.timeout_ms`.

---

## 5. Política de escritura

### 5.1. Principios

1. Thalos DEBE guardar conocimiento destilado.
2. Thalos NO DEBE guardar ruido.
3. Thalos NO DEBE guardar conversaciones crudas.
4. Thalos NO DEBE guardar logs completos.
5. Thalos NO DEBE guardar código completo.
6. Thalos NO DEBE guardar secretos.
7. Thalos DEBE guardar memorias atómicas.
8. Thalos DEBE guardar títulos buscables.
9. Thalos DEBE guardar metadata explícita.
10. Thalos DEBE referenciar artefactos cuando exista evidencia.

### 5.2. Atomicidad

Cada memoria DEBE representar una sola idea:

```txt
una decisión,
una lección,
un constraint,
un bug,
una causa raíz,
una estrategia de testing.
```

### 5.3. Títulos buscables

Los títulos DEBEN contener el módulo y el hecho concreto.

Mal:

```txt
Cambio importante
Fix raro
```

Bien:

```txt
[auth] Magic link tokens expiran en 15 minutos
[auth] Fix token reuse por falta de invalidación en MagicLinkToken
```

### 5.4. Deduplicación asíncrona

**Corrección respecto de 0.0.4:** la sección 46.4 exigía `search → compare → save` en cada escritura, dentro del camino crítico. Eso agregaba dos llamadas de red y consumo de presupuesto a cada evento del ciclo de vida.

Nuevo modelo:

```txt
camino crítico (síncrono):
  1. destilar
  2. clasificar tipo
  3. secret scan (fail-closed)
  4. calcular importance/confidence
  5. save_memory con status = captured
  6. emitir thalos.memory.saved

reconciliación (asíncrona, fuera del camino crítico):
  7. search_memory por similitud
  8. compare_memory
  9. si es la misma      -> update_memory, marcar duplicada como archived
     si contradice       -> marcar ambas conflicted
     si es complementaria-> update_memory o enlazar
     si es nueva         -> promover a candidate
 10. emitir thalos.memory.reconciled
```

Reglas:

1. La escritura síncrona NO DEBE hacer búsqueda previa.
2. La reconciliación DEBE ejecutarse antes de que una memoria pueda pasar a `active`.
3. Una memoria en `captured` NO DEBE recuperarse para inyección.
4. La reconciliación PUEDE agruparse en lotes.
5. La ventana de duplicados transitorios ES aceptable porque `captured` no se inyecta.

### 5.5. Validación

Memorias de alto impacto DEBEN requerir validación antes de `active`.

Tipos que REQUIEREN validación:

```txt
decision
constraint
architecture
security_note
api_contract
```

Progresión:

```txt
captured -> candidate -> validated -> active
```

### 5.6. Eventos que generan memoria

Thalos PUEDE generar memoria desde:

```txt
thalos.spec.approved
thalos.program.planned
thalos.feature.merged
thalos.feature.failed
thalos.error.occurred
thalos.escalation.triggered
thalos.review.completed
thalos.feature.checks_failed
```

### 5.7. Plantillas

#### Decision

```txt
Title:        [module] decisión concreta
What:         qué se decidió
Why:          por qué
Alternatives: qué se descartó y con qué tradeoff
Consequences: consecuencias
Evidence:     artefactos, PRs, evidence_ids
```

#### Lesson

```txt
Title:       [module] lección operativa
Trigger:     cuándo ocurre
Observation: qué se observó
Lesson:      qué aprendimos
Prevention:  cómo evitarlo
```

#### Bug / Root cause

```txt
Title:          [module] síntoma
Symptom:        error visible
Cause:          causa raíz
Fix:            solución
RegressionTest: prueba añadida
```

#### Constraint

```txt
Title:      [module] restricción
Constraint: regla
Reason:     razón
AppliesTo:  archivos o módulos
```

#### Test strategy

```txt
Title:          [module] estrategia de pruebas
What:           qué probar
Why:            por qué
How:            unit / integration / e2e
KnownEdgeCases: casos borde
```

---

## 6. Política de recuperación

### 6.1. Principios

1. Thalos DEBE recuperar poca memoria y relevante.
2. Thalos NO DEBE inyectar todas las memorias disponibles.
3. Thalos DEBE filtrar por proyecto.
4. Thalos DEBE filtrar por estado.
5. Thalos DEBE limitar por rol.
6. Thalos DEBE respetar el presupuesto de contexto.
7. Thalos DEBE rankear.
8. Thalos DEBE registrar toda query.
9. Thalos DEBE inyectar la memoria como consejo explícito.
10. Thalos NO DEBE tratar la memoria como regla.

### 6.2. Filtros obligatorios

```txt
project = current_project
status  in ["active", "validated"]
```

Filtros opcionales:

```txt
type in allowed_types_for_role
feature_id = current_feature
files overlap current_files
importance >= threshold
confidence >= threshold
```

Regla: una memoria en `captured`, `candidate`, `stale`, `archived` o `conflicted` NO DEBE inyectarse.

### 6.3. Perfiles por rol

Los roles corresponden al núcleo 0.0.5 (5 roles agente).

| Rol | Tipos recuperados | top_k |
|---|---|---|
| `Planner` | architecture, decision, constraint, security_note, performance_note | 10 |
| `SpecAssistant` | constraint, architecture, decision, api_contract | 6 |
| `FeatureLead` | decision, lesson, bug, test_strategy, constraint | 8 |
| `Developer` | lesson, bug, workflow_pattern, anti_pattern, test_strategy | 5 |
| `Reviewer` | security_note, constraint, bug, anti_pattern, api_contract | 6 |

**Corrección respecto de 0.0.4:** se elimina el perfil `escalation` porque `Escalation` dejó de ser un rol en el núcleo 0.0.5 (es un estado). Las memorias de escalación se recuperan bajo el perfil de `FeatureLead` cuando la feature está en `FEATURE_ESCALATED`, con `top_k` elevado a 12. Se añade perfil para `SpecAssistant`, que no existía.

### 6.4. Construcción de query

Thalos DEBE construir la query desde:

```txt
feature title
module
files tocados
tags
mensajes de error
spec refs
task description
rol
estado actual de la feature
```

### 6.5. Ranking normalizado

**Corrección respecto de 0.0.4:** la fórmula 47.5 sumaba términos de unidades incomparables (un enum de string, una fecha, un contador sin techo) con pesos que asumían el rango [0,1], sin definir ninguna normalización. Los pesos no significaban nada. Aquí se define cada término.

Fórmula:

```txt
final_score =
  0.45 * n_text_relevance
+ 0.20 * n_recency
+ 0.20 * n_importance
+ 0.10 * n_confidence
+ 0.05 * n_usage
```

Todos los términos DEBEN normalizarse a `[0, 1]` antes de sumarse.

#### n_text_relevance

```txt
El backend DEBE devolver un score de relevancia.
Si el score no está acotado, Thalos DEBE normalizar min-max
sobre el conjunto de resultados de la misma query:

  n_text_relevance = (score - min_score) / (max_score - min_score)

Si max_score == min_score, n_text_relevance = 1.0 para todos.
```

#### n_recency

Decaimiento exponencial con vida media configurable:

```txt
age_days = (now - updated_at_or_created_at).days
n_recency = 0.5 ^ (age_days / half_life_days)

half_life_days por defecto = 45
```

Propiedades: una memoria de hoy vale 1.0; a 45 días vale 0.5; a 90 días vale 0.25. Nunca es negativo ni supera 1.

#### n_importance

Mapeo explícito del enum:

```txt
low      -> 0.25
medium   -> 0.50
high     -> 0.75
critical -> 1.00
```

#### n_confidence

```txt
low    -> 0.33
medium -> 0.66
high   -> 1.00
```

Además: si `status == "validated"` o `status == "active"` tras validación humana, `n_confidence` DEBE elevarse a 1.00 independientemente del enum.

#### n_usage

Saturación logarítmica para evitar que un contador sin techo domine:

```txt
n_usage = log(1 + useful_count) / log(1 + usage_saturation)

usage_saturation por defecto = 20
n_usage DEBE acotarse a un máximo de 1.0
```

Se usa `useful_count`, no `usage_count`: se premia la utilidad confirmada, no la inyección.

#### Reglas

1. Los pesos DEBEN sumar 1.0.
2. Los pesos DEBEN ser configurables.
3. Toda normalización DEBE ser determinista.
4. El score final DEBE registrarse junto a la query para auditoría.
5. Un cambio de pesos DEBE registrarse como evento de configuración.

### 6.6. Presupuesto de contexto

```txt
máximo 5-10 memorias por prompt
máximo 2-4 KB de contexto de memoria
```

Reglas:

1. El contexto de memoria DEBE contar contra el presupuesto de tokens del rol.
2. Si el presupuesto se agota, Thalos DEBE truncar por `final_score` descendente.
3. Thalos NO DEBE truncar una memoria a la mitad; DEBE excluirla completa.
4. Si el presupuesto no permite ninguna memoria, el rol DEBE ejecutarse sin contexto de memoria.

### 6.7. Formato de inyección

Thalos DEBE inyectar la memoria como paquete consultivo, marcado explícitamente como no normativo.

```md
## Contexto consultivo del proyecto (NO normativo)

Estas memorias son consejo de ejecuciones anteriores. NO son spec,
NO son policy y NO son evidencia. Si contradicen el spec aprobado
o la policy, el spec y la policy ganan. Reportá la contradicción.

- [decision][high] Auth: magic link tokens expiran en 15 minutos
  Fuente: F001 merged · Ref: spec/SPEC.md · id: m-001

- [lesson][medium] Auth: invalidar token tras primer uso
  Fuente: bug #132 · Ref: src/auth/verify.ts · id: m-002

- [security_note][high] No loguear tokens completos
  Fuente: security review · Ref: src/logger.ts · id: m-003
```

### 6.8. Señal de utilidad

**Corrección respecto de 0.0.4: sin esta señal, las métricas de la sección 8 no se pueden calcular.**

1. Todo paquete inyectado DEBE incluir el `id` de cada memoria.
2. El rol DEBE reportar, en su respuesta estructurada, qué `memory_ids` influyeron en su output.
3. Thalos DEBE invocar `record_usage` con esa lista.
4. `record_usage` DEBE incrementar `usage_count` para toda memoria inyectada.
5. `record_usage` DEBE incrementar `useful_count` y actualizar `last_useful_at` solo para las memorias reportadas como influyentes.
6. Si el rol no reporta la lista, Thalos DEBE registrar la inyección como no confirmada y NO DEBE incrementar `useful_count`.

---

## 7. Ciclo de vida de memoria

### 7.1. Estados

```txt
captured
candidate
validated
active
stale
archived
conflicted
```

### 7.2. Tabla de transiciones

| # | Desde | Hacia | Disparador | Actor | Evento |
|---|---|---|---|---|---|
| M1 | — | captured | escritura síncrona | core | `thalos.memory.saved` |
| M2 | captured | candidate | reconciliación sin duplicado | core | `thalos.memory.reconciled` |
| M3 | captured | archived | reconciliación detecta duplicado | core | `thalos.memory.archived` |
| M4 | captured | conflicted | reconciliación detecta contradicción | core | `thalos.memory.conflict_detected` |
| M5 | candidate | validated | validación (requerida por tipo) | MemoryCurator o HumanApprover | `thalos.memory.validated` |
| M6 | candidate | active | tipo no requiere validación | core | `thalos.memory.activated` |
| M7 | validated | active | promoción | core | `thalos.memory.activated` |
| M8 | active | stale | `age > stale_after_days` sin uso útil | core | `thalos.memory.stale_detected` |
| M9 | active | conflicted | nueva memoria contradice | core | `thalos.memory.conflict_detected` |
| M10 | stale | active | uso útil confirmado | core | `thalos.memory.activated` |
| M11 | stale | archived | `age > archive_after_days` | core | `thalos.memory.archived` |
| M12 | conflicted | validated | resolución a favor | MemoryCurator o HumanApprover | `thalos.memory.validated` |
| M13 | conflicted | archived | resolución en contra | MemoryCurator o HumanApprover | `thalos.memory.archived` |
| M14 | active | archived | archivado explícito | usuario | `thalos.memory.archived` |
| M15 | archived | forgotten | olvido explícito | usuario | `thalos.memory.forgotten` |

### 7.3. Reglas

1. Las memorias automáticas DEBEN iniciar en `captured`.
2. Las memorias de tipos críticos DEBEN pasar por `validated` antes de `active`.
3. Solo `active` y `validated` PUEDEN inyectarse.
4. Las memorias archivadas NO DEBEN recuperarse por defecto.
5. Las memorias olvidadas DEBEN eliminarse del backend.
6. Todo cambio de estado DEBE emitir evento.
7. `forgotten` NO ES un estado persistido: es la eliminación.
8. Una memoria `conflicted` DEBE escalar si no se resuelve en `conflict_resolution_days`.

---

## 8. Métricas

**Corrección respecto de 0.0.4: las métricas de la sección 50 dependían de saber si una memoria fue "útil", sin definir ninguna señal. Eran incomputables. Con `useful_count` de la sección 6.8, ahora se calculan.**

### 8.1. Métricas y fórmulas

| Métrica | Fórmula | Fuente de datos |
|---|---|---|
| `duplicate_memory_rate` | memorias archivadas por duplicado / memorias guardadas | transición M3 |
| `stale_memory_rate` | memorias en `stale` / memorias en `active` + `stale` | estado |
| `memory_injection_rate` | memorias inyectadas / prompts con memoria habilitada | eventos de inyección |
| `memory_usefulness_rate` | memorias reportadas como influyentes / memorias inyectadas | `record_usage` |
| `memory_unconfirmed_rate` | inyecciones sin reporte de influencia / inyecciones | `record_usage` |
| `conflict_memory_rate` | memorias en `conflicted` / memorias en `active` | estado |
| `validation_rate` | memorias `validated` / memorias que requieren validación | estado |
| `forget_rate` | memorias olvidadas / memorias guardadas | transición M15 |
| `memory_latency_p95` | percentil 95 de latencia por operación | telemetría de adapter |
| `memory_error_rate` | operaciones fallidas / operaciones totales | telemetría de adapter |

`memory_usefulness_rate` reemplaza a `memory_hit_rate` e `irrelevant_memory_rate` de 0.0.4, que medían lo mismo desde dos lados y ninguno era computable.

### 8.2. Uso de métricas

Thalos DEBE usar las métricas para:

```txt
- ajustar top_k por rol,
- ajustar los pesos de ranking,
- detectar ruido en la escritura,
- detectar obsolescencia,
- disparar revisión humana,
- decidir si la extensión aporta valor.
```

### 8.3. Umbrales de alarma recomendados

```txt
memory_usefulness_rate  < 0.30   -> el ranking o el top_k están mal
duplicate_memory_rate   > 0.20   -> la destilación es demasiado granular
stale_memory_rate       > 0.40   -> falta curación
conflict_memory_rate    > 0.10   -> el proyecto cambió de dirección; revisar
memory_unconfirmed_rate > 0.50   -> los roles no reportan; la métrica no es confiable
```

Si `memory_usefulness_rate` se mantiene bajo el umbral durante dos ciclos de reporte, Thalos DEBE recomendar deshabilitar la extensión.

---

## 9. Privacidad y gobierno

### 9.1. Privacidad

1. Thalos NO DEBE guardar secrets, tokens, passwords ni credenciales.
2. Thalos NO DEBE guardar logs sensibles completos.
3. Thalos DEBE aplicar detección de secrets antes de guardar.
4. La detección de secrets DEBE ser **fail-closed**: ante resultado incierto, Thalos NO DEBE guardar y DEBE registrar el descarte.
5. Thalos DEBE limitar el tamaño de payload.
6. Thalos PUEDE marcar memorias sensibles.
7. Thalos DEBE permitir olvido explícito.
8. Thalos DEBE auditar accesos a memorias marcadas sensibles.
9. Thalos DEBE registrar el hecho de una redacción, nunca el valor redactado.

**Corrección respecto de 0.0.4:** la regla 34.11 decía "filtrar secrets antes de guardar", lo que admite la lectura "filtré lo que reconocí y guardé el resto". La detección de secretos es best-effort por naturaleza; la única política segura es no persistir ante duda.

### 9.2. Gobierno

1. La memoria NO DEBE aprobar merges.
2. La memoria NO DEBE modificar spec.
3. La memoria NO DEBE modificar policy.
4. La memoria NO DEBE satisfacer gates.
5. La memoria NO DEBE bloquear el flujo principal.
6. La memoria crítica DEBE poder revisarse.
7. La memoria conflictiva DEBE curarse o escalarse.
8. La memoria validada DEBE tener precedencia sobre la inferida.
9. La memoria antigua DEBE decaer en ranking.
10. La memoria DEBE poder exportarse.
11. Toda lectura y escritura de memoria DEBE poder auditarse.

### 9.3. Rol MemoryCurator

`MemoryCurator` ES un rol OPCIONAL de esta extensión. No existe en el núcleo.

| Permiso | Alcance |
|---|---|
| PUEDE | validar, archivar, marcar conflicto, resolver conflicto, fusionar duplicados |
| NO DEBE | modificar spec, modificar policy, aprobar gates, aprobar merges, escribir en `src/` |

`role_minimum_tier` recomendado:

```txt
balanced
```

---

## 10. Eventos

Todos los eventos de esta extensión DEBEN cumplir `event.schema.json` del núcleo, incluidos `seq` y `schema_version`.

```txt
thalos.memory.saved
thalos.memory.reconciled
thalos.memory.updated
thalos.memory.searched
thalos.memory.injected
thalos.memory.usage_recorded
thalos.memory.validated
thalos.memory.activated
thalos.memory.stale_detected
thalos.memory.conflict_detected
thalos.memory.conflict_resolved
thalos.memory.archived
thalos.memory.forgotten
thalos.memory.discarded_secret
thalos.memory.metric_reported
```

Reglas:

1. Toda query DEBE emitir `thalos.memory.searched` con la query, los filtros y los `ids` devueltos.
2. Toda inyección DEBE emitir `thalos.memory.injected` con los `ids` y el `final_score` de cada uno.
3. Todo descarte por secret scanning DEBE emitir `thalos.memory.discarded_secret` sin incluir el contenido descartado.

---

## 11. CLI

```txt
thalos memory search <query>
thalos memory show <memory_id>
thalos memory save
thalos memory update <memory_id>
thalos memory validate <memory_id>
thalos memory archive <memory_id>
thalos memory forget <memory_id>
thalos memory conflicts
thalos memory reconcile
thalos memory stats
thalos memory doctor
thalos memory export
```

DEBEN soportar `--format json`:

```txt
memory search
memory show
memory stats
memory conflicts
memory doctor
```

---

## 12. Configuración

### 12.1. Archivo

```txt
thalos.config/memory.yaml
```

**Nota:** el directorio de configuración del proyecto es `thalos.config/`, no `config/`, según el núcleo 0.0.5 sección 11.

```yaml
version: 1

memory:
  enabled: true
  adapter: thalos.adapter.engram
  inject_as: advisory_context

  write_policy:
    enabled: true
    secret_scan: true
    secret_scan_mode: fail_closed
    max_payload_kb: 64
    min_importance_to_save: low
    require_validation_for:
      - decision
      - constraint
      - security_note
      - architecture
      - api_contract
    auto_capture_events:
      - thalos.spec.approved
      - thalos.program.planned
      - thalos.feature.merged
      - thalos.feature.failed
      - thalos.escalation.triggered
      - thalos.error.occurred
      - thalos.review.completed

  reconciliation:
    enabled: true
    mode: async
    batch_size: 20
    run_every_minutes: 15
    similarity_threshold: 0.82

  read_policy:
    enabled: true
    timeout_ms: 3000
    max_memories_per_prompt: 8
    max_context_kb: 4
    allowed_status:
      - active
      - validated

    ranking:
      weights:
        text_relevance: 0.45
        recency: 0.20
        importance: 0.20
        confidence: 0.10
        usage: 0.05
      normalization:
        recency_half_life_days: 45
        usage_saturation: 20
        importance_map:
          low: 0.25
          medium: 0.50
          high: 0.75
          critical: 1.00
        confidence_map:
          low: 0.33
          medium: 0.66
          high: 1.00

    role_profiles:
      planner:
        types: [architecture, decision, constraint, security_note, performance_note]
        top_k: 10
      spec_assistant:
        types: [constraint, architecture, decision, api_contract]
        top_k: 6
      feature_lead:
        types: [decision, lesson, bug, test_strategy, constraint]
        top_k: 8
        escalated_top_k: 12
      developer:
        types: [lesson, bug, workflow_pattern, anti_pattern, test_strategy]
        top_k: 5
      reviewer:
        types: [security_note, constraint, bug, anti_pattern, api_contract]
        top_k: 6

  lifecycle:
    stale_after_days: 90
    archive_after_days: 365
    conflict_resolution_days: 14
    review_high_importance_every_days: 90

  metrics:
    enabled: true
    report_every: daily
    alarms:
      min_usefulness_rate: 0.30
      max_duplicate_rate: 0.20
      max_stale_rate: 0.40
      max_conflict_rate: 0.10
      max_unconfirmed_rate: 0.50
```

### 12.2. Validación

1. Los pesos de ranking DEBEN sumar 1.0; si no, la config DEBE rechazarse.
2. `max_memories_per_prompt` DEBE ser menor o igual al `top_k` máximo de cualquier perfil.
3. `secret_scan_mode` DEBE ser `fail_closed` para que la extensión pueda habilitarse en un proyecto con policy de seguridad.

---

## 13. Adapter de referencia: Engram

### 13.1. Identidad

```txt
id:       thalos.adapter.engram
paquete:  thalos-adapter-engram
backend:  Engram
```

### 13.2. Transportes

```txt
mcp_stdio
http_api
cli
```

### 13.3. Mapeo de capacidades

| Capacidad `MemoryAdapter` | Engram |
|---|---|
| `save_memory` | `mem_save` |
| `update_memory` | `mem_update` |
| `search_memory` | `mem_search` |
| `get_context` | `mem_context` |
| `compare_memory` | `mem_compare` |
| `archive_memory` | `mem_update` con `status: archived` |
| `forget_memory` | `mem_delete` |
| `memory_stats` | `mem_stats` |
| `detect_conflicts` | `mem_compare` + `mem_review` |
| `record_usage` | `mem_update` sobre `usage_count` / `useful_count` |

**Nota:** `mem_judge` NO se mapea a una capacidad del puerto. Si el backend lo expone, el adapter PUEDE usarlo internamente como insumo de `detect_conflicts`, pero la decisión de resolución NO DEBE delegarse al backend.

### 13.4. Preconditions

Si el adapter está habilitado:

```txt
engram instalado
engram version compatible
engram project configurado
transporte disponible (MCP stdio o HTTP)
```

Si alguna falla, Thalos PUEDE continuar sin memoria y DEBE declararlo en el `PreconditionReport`.

### 13.5. Prohibiciones

El adapter de Engram NO DEBE:

```txt
- definir policy,
- modificar spec,
- aprobar merges,
- satisfacer gates,
- producir evidencia,
- alterar estado runtime del núcleo,
- almacenar secretos,
- reemplazar evidencia de CI.
```

### 13.6. Uso recomendado

1. Escribir memorias atómicas.
2. No usar passive capture como memoria activa sin reconciliación.
3. Usar session summaries solo como candidatas.
4. Aplicar el ranking de Thalos sobre los resultados del backend, no confiar en el orden nativo.
5. Reintentar escrituras fallidas fuera del camino crítico con la misma idempotency key.

---

## 14. Criterios de aceptación

La extensión 0.0.1 se considera aceptable si:

1. El núcleo pasa todos sus criterios de aceptación con la extensión deshabilitada.
2. El núcleo pasa todos sus criterios de aceptación con la extensión habilitada.
3. Una caída del backend de memoria no detiene ninguna transición de estado.
4. Ninguna memoria aparece en `evidence_refs` de una transición.
5. Ninguna memoria satisface un gate.
6. La escritura síncrona no realiza búsqueda previa.
7. La reconciliación asíncrona detecta duplicados y contradicciones.
8. Una memoria en `captured` nunca se inyecta.
9. El secret scanning descarta ante incertidumbre y emite `thalos.memory.discarded_secret`.
10. Todos los términos del ranking se normalizan a `[0,1]` de forma determinista.
11. Una configuración con pesos que no suman 1.0 es rechazada.
12. El paquete inyectado incluye el aviso de no normatividad y los `ids`.
13. Los roles reportan `memory_ids` influyentes y `record_usage` los registra.
14. `memory_usefulness_rate` se calcula con datos reales.
15. Todo evento de memoria cumple el schema de eventos del núcleo, con `seq` y `schema_version`.
16. `thalos memory export` produce un dump completo y legible.
17. `thalos memory forget` elimina del backend y emite el evento.

---

## 15. Changelog

### 0.0.1

Extraído de `thalos-0.0.4.md` secciones 42–54, con las siguientes correcciones:

**Autoridad**

- Resuelta la contradicción de precedencia: la memoria ocupa el nivel 5 de una única cadena de autoridad, por debajo de config, evidencia, spec y policy.
- Prohibición explícita de que una memoria aparezca en `evidence_refs`.

**Ranking**

- Definida la normalización de los cinco términos, que en 0.0.4 sumaba unidades incomparables con pesos sin significado.
- `recency` pasa a decaimiento exponencial con vida media configurable.
- `importance` y `confidence` obtienen mapeo numérico explícito.
- `usage` pasa a saturación logarítmica sobre `useful_count`, no sobre `usage_count`.
- Validación obligatoria de que los pesos sumen 1.0.

**Métricas**

- Añadidos `useful_count` y `last_useful_at` a la entidad, y la capacidad `record_usage` al puerto.
- Definida la señal de utilidad: el rol reporta qué memorias influyeron en su output.
- `memory_hit_rate` e `irrelevant_memory_rate`, ambos incomputables en 0.0.4, se reemplazan por `memory_usefulness_rate` y `memory_unconfirmed_rate`.
- Añadidos umbrales de alarma y la recomendación de deshabilitar la extensión si no aporta valor medible.

**Escritura**

- Deduplicación movida del camino crítico a reconciliación asíncrona por lotes.
- Garantía de seguridad: una memoria `captured` no se inyecta, por lo que la ventana de duplicados transitorios es inocua.

**Seguridad**

- Secret scanning pasa a `fail_closed`: ante incertidumbre no se persiste.
- Añadido `thalos.memory.discarded_secret` que registra el descarte sin el contenido.

**Ciclo de vida**

- Añadida la tabla completa de 15 transiciones con disparador, actor y evento; en 0.0.4 solo había una lista de pares sin condiciones.
- Añadido plazo de resolución de conflictos con escalación.

**Puerto**

- Eliminada `judge_memory`, que acoplaba el núcleo a una capacidad específica del backend.
- Añadida `record_usage`.
- Marcadas las operaciones mutantes como sujetas a idempotency key del núcleo.

**Roles**

- Eliminado el perfil `escalation` (dejó de ser rol en el núcleo 0.0.5); su comportamiento se preserva vía `escalated_top_k` en `FeatureLead`.
- Añadido perfil para `SpecAssistant`, ausente en 0.0.4.
- `Developer` recupera `workflow_pattern` y `anti_pattern` en lugar del tipo `pattern`, que no existía en la enumeración de tipos de 0.0.4.

**Configuración**

- Movida a `thalos.config/memory.yaml` por el renombrado de directorio del núcleo.
- Añadidas secciones `reconciliation`, `ranking.normalization` y `metrics.alarms`.
