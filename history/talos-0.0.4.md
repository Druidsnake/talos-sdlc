# Talos System Specification

**System Name:** Talos  
**Canonical Package:** talos-sdlc  
**System Version:** 0.0.4  
**Status:** Experimental Baseline  
**Date:** 2026-07-31  
**Document Type:** System Specification  
**Language:** Spanish normative text  

---

## 0. Convenciones del documento

Las palabras clave DEBE, NO DEBE, REQUERIDO, PUEDE, RECOMENDADO y OPCIONAL deben interpretarse como requisitos normativos.

Este documento define el sistema automatizador llamado **Talos**.

Este documento NO define el spec del producto a desarrollar.

---

## 1. Nombre del sistema

El sistema se denomina:

```txt
Talos
```

Nombre canónico de paquete:

```txt
talos-sdlc
```

CLI oficial:

```txt
talos
```

Tagline recomendado:

```txt
Guardian of the software development lifecycle
```

Tagline en español:

```txt
Guardián del ciclo de desarrollo con IA
```

Inspiración:

```txt
Talos, autómata guardián de la mitología griega.
```

---

## 2. Propósito

Talos define un marco normativo y extensible para orquestar desarrollo de software asistido por agentes.

Talos cubre:

- intake de spec,
- planificación,
- desarrollo,
- revisión,
- corrección,
- pruebas,
- aprobación,
- merge,
- trazabilidad,
- memoria de largo plazo.

Talos está diseñado para ser:

- versionado,
- reutilizable,
- configurable,
- auditable,
- desacoplado,
- extensible,
- integrable con múltiples agentes y entornos,
- capaz de aprender de ejecuciones anteriores.

---

## 3. Alcance de la versión 0.0.4

La versión 0.0.4 define:

1. Nombre oficial del sistema: Talos.
2. Separación entre sistema automatizador y spec de producto.
3. Arquitectura desacoplada por capas.
4. Modelo de extensión basado en adapters y plugins.
5. Entidades fundamentales.
6. Roles y permisos.
7. Ciclo de vida.
8. Protocolo de comunicación.
9. Configuración de modelos y routing.
10. Gobierno de merge.
11. Preconditions.
12. Gestión de spec faltante.
13. Contratos de adapters.
14. Contratos de plugins.
15. CLI oficial `talos`.
16. Event system con namespace `talos`.
17. Schemas mínimos de datos.
18. Sistema de memoria persistente.
19. MemoryAdapter.
20. Integración opcional con Engram.
21. Política de escritura de memoria.
22. Política de recuperación de memoria.
23. Ciclo de vida de memorias.
24. Ranking y presupuesto de contexto.
25. Privacidad y gobierno de memoria.
26. Métricas de calidad de memoria.
27. Criterios de aceptación para piloto serial.

---

## 4. No alcance de la versión 0.0.4

La versión 0.0.4 NO define completamente:

1. Paralelismo agresivo multi-feature.
2. Auto-merge autónomo sin supervisión.
3. Optimización avanzada de costos.
4. Dashboard gráfico externo.
5. Recuperación automática ante todos los modos de fallo.
6. Entornos distribuidos multi-máquina.
7. Marketplace completo de plugins.
8. Entrenamiento o fine-tuning de modelos.
9. Memoria vectorial avanzada como requisito obligatorio.

La versión 0.0.4 está orientada a:

```txt
piloto controlado, serial, con supervisión humana, dry-run preferente, arquitectura extensible y memoria persistente opcional
```

---

## 5. Principios normativos

1. Talos DEBE ser independiente del spec del producto.
2. Talos DEBE ser versionado.
3. El spec del producto DEBE residir en `spec/`.
4. Talos NO DEBE escribir reglas propias dentro de `spec/`.
5. Todo cambio DEBE ser trazable a spec, feature, task y PR.
6. Toda comunicación entre roles DEBE ser explícita y estructurada.
7. Toda decisión relevante DEBE persistirse como artefacto o evento.
8. Toda transición de estado DEBE requerir evidencia.
9. Toda ejecución DEBE respetar permisos de rol.
10. Toda feature DEBE clasificarse por riesgo y esfuerzo.
11. Todo merge DEBE cumplir gates automáticos y política de aprobación.
12. Ante ambigüedad, Talos DEBE preguntar o escalar.
13. El núcleo de Talos DEBE permanecer independiente de vendors.
14. Toda integración externa DEBE implementarse como adapter.
15. Toda extensión de UI o automatización DEBE implementarse como plugin.
16. Talos DEBE poder operar sin plugins.
17. Los plugins NO DEBEN reemplazar al núcleo.
18. Los adapters NO DEBEN definir política de negocio.
19. La memoria persistente DEBE ser opcional.
20. La memoria DEBE ser consultiva, no normativa.
21. La memoria NO DEBE reemplazar spec, policy o evidencia CI.
22. La memoria NO DEBE contener secretos.
23. La memoria DEBE poder auditarse.
24. La memoria DEBE poder archivarse u olvidarse.

---

## 6. Identidad técnica de Talos

| Elemento | Valor |
|---|---|
| Nombre | Talos |
| Paquete canónico | talos-sdlc |
| CLI | talos |
| Namespace de eventos | talos |
| Prefijo de adapters | talos-adapter- |
| Prefijo de plugins | talos-plugin- |
| Runtime local | .talos/ |
| API namespace | talos/v0 |
| Memory adapter oficial | talos-adapter-engram |

---

## 7. Arquitectura general

Talos se divide en ocho capas normativas:

```txt
1. Spec Layer
2. Core Kernel
3. Contracts & Schemas
4. Configuration
5. CLI / API
6. Adapters
7. Plugins
8. Memory Layer
```

---

## 8. Separación arquitectónica obligatoria

### 8.1. Automation System

Capa normativa y ejecutable de Talos.

Contiene:

```txt
system/
contracts/
schemas/
core/
cli/
config/
adapters/
plugins/
```

### 8.2. Product Spec

Capa de entrada del desarrollo actual.

Contiene:

```txt
spec/
```

### 8.3. Runtime Instance

Capa de ejecución del desarrollo actual.

Contiene:

```txt
orchestration/
```

### 8.4. Memory Layer

Capa opcional de memoria persistente.

Puede integrarse con:

```txt
Engram
```

u otro backend mediante:

```txt
MemoryAdapter
```

---

## 9. Reserva semántica de directorios

| Directorio | Significado | Normatividad |
|---|---|---|
| `system/` | Documentos normativos de Talos | Obligatorio |
| `contracts/` | Contratos funcionales y puertos | Obligatorio |
| `schemas/` | Contratos estructurales JSON Schema | Obligatorio |
| `core/` | Lógica central de Talos | Obligatorio |
| `cli/` | Interfaz de comandos `talos` | Obligatorio |
| `config/` | Configuración base del sistema | Obligatorio |
| `adapters/` | Integraciones externas | Obligatorio |
| `plugins/` | Extensiones opcionales | Opcional |
| `spec/` | Spec del producto a desarrollar | Obligatorio |
| `orchestration/` | Estado runtime | Obligatorio |
| `examples/` | Ejemplos no normativos | Opcional |
| `src/` | Código resultado del proyecto | Opcional |
| `tests/` | Pruebas del proyecto | Opcional |

---

## 10. Estructura del repositorio del sistema

```txt
talos-sdlc/
  VERSION
  CHANGELOG.md
  README.md

  system/
    00-principles.md
    01-entities.md
    02-roles.md
    03-lifecycle.md
    04-communication.md
    05-governance.md
    06-preconditions.md
    07-spec-intake.md
    08-extensibility.md
    09-naming.md
    10-memory.md

  contracts/
    ports.md
    adapters.md
    plugins.md
    events.md
    cli.md
    memory.md

  schemas/
    system-manifest.schema.json
    project-manifest.schema.json
    spec-manifest.schema.json
    models-config.schema.json
    roles-config.schema.json
    routing-config.schema.json
    policy-config.schema.json
    communication-config.schema.json
    preconditions-config.schema.json
    extension-registry.schema.json
    adapter-manifest.schema.json
    plugin-manifest.schema.json
    message.schema.json
    event.schema.json
    feature-state.schema.json
    program-plan.schema.json
    review.schema.json
    locks.schema.json
    memory.schema.json
    memory-config.schema.json
    memory-query.schema.json

  core/
    state/
    policy/
    routing/
    messaging/
    planning/
    validation/
    events/
    gates/
    memory/

  cli/
    talos
    commands/

  config/
    system.yaml
    models.yaml
    roles.yaml
    routing.yaml
    policy.yaml
    communication.yaml
    preconditions.yaml
    extensions.yaml
    memory.yaml
    engram.yaml

  adapters/
    filesystem/
    github/
    herdr/
    ci/
    model/
    dryrun/
    engram/

  plugins/
    herdr/

  examples/
    project-sample/
    spec-sample/
    memory-sample/
```

---

## 11. Estructura del repositorio de proyecto

```txt
my-project/
  .talos/
    system/
    contracts/
    schemas/
    core/
    cli/
    config/
    adapters/
    plugins/

  spec/
    manifest.yaml
    SPEC.md
    requirements.md
    acceptance.md
    constraints.md
    test_plan.md

  config/
    project.yaml
    overrides.yaml
    extensions.yaml
    memory.yaml
    engram.yaml

  orchestration/
    state.json
    program-plan.json
    locks.json
    features/
    messages/
    reports/
    events/
    memory/

  src/
  tests/
  docs/
```

---

## 12. Versionado de Talos

1. Talos DEBE tener un archivo `VERSION`.
2. Talos DEBE seguir versionado semántico.
3. Cada proyecto DEBE fijar una versión específica de Talos.
4. Talos NO DEBE depender de cambios no versionados en el proyecto.
5. Talos DEBE poder ser instalado como subdirectorio `.talos/`.
6. Los plugins DEBEN declarar compatibilidad con versiones del core.
7. Los adapters DEBEN declarar versión y API soportada.
8. El MemoryAdapter DEBE declarar compatibilidad con el backend de memoria.

---

## 13. Manifiesto del sistema

Talos DEBE declarar:

```txt
system_name
system_version
api_version
spec_schema_version
config_schema_version
status
adapters
plugins
memory_adapter
```

---

## 14. Manifiesto de proyecto

El proyecto DEBE declarar:

```txt
system name
system root
system version
spec root
runtime root
config overrides
extensions
memory config
```

---

## 15. Spec de producto

### 15.1. Reserva de `spec/`

1. `spec/` DEBE contener únicamente el spec del producto.
2. `spec/` NO DEBE contener configuración de Talos.
3. `spec/` NO DEBE contener estado de orquestación.
4. `spec/` NO DEBE contener ejemplos del sistema.
5. `spec/` NO DEBE contener reportes de ejecución.
6. `spec/` NO DEBE contener plugins.
7. `spec/` NO DEBE contener adapters.
8. `spec/` NO DEBE contener memorias.

---

### 15.2. Spec manifest

El spec DEBE tener un manifiesto.

Campos requeridos:

```txt
version
title
status
entry
```

Estados válidos:

```txt
draft
review
approved
deprecated
```

---

### 15.3. Spec mínimo aceptable

El spec DEBE incluir:

```txt
problem
goal
non_goals
users
requirements
acceptance_criteria
constraints
risks
test_plan
```

---

## 16. Spec faltante

1. Talos DEBE verificar presencia de spec.
2. Si no existe spec, Talos DEBE entrar en `SPEC_MISSING`.
3. Talos DEBE preguntar al usuario si desea asistencia.
4. Si el usuario acepta, Talos DEBE iniciar `SpecAssistant`.
5. Si el usuario rechaza, Talos DEBE detenerse.
6. `SpecAssistant` SOLO PUEDE escribir dentro de `spec/`.
7. `SpecAssistant` NO PUEDE aprobar el spec automáticamente.
8. El spec generado DEBE requerir aprobación humana.

---

## 17. Entidades de Talos

### 17.1. Project

Entidad raíz del desarrollo actual.

### 17.2. System

Motor normativo y ejecutable llamado Talos.

### 17.3. Spec

Descripción normativa del producto a construir.

### 17.4. Program

Conjunto planificado de features derivadas del spec.

### 17.5. Feature

Unidad independiente de valor.

### 17.6. Task

Unidad atómica de trabajo.

### 17.7. Role

Responsabilidad con permisos.

### 17.8. Agent

Modelo que ejecuta un rol.

### 17.9. Session

Entorno de ejecución asociado a un rol.

### 17.10. Artifact

Archivo versionado o referencia estable.

### 17.11. Message

Comunicación estructurada entre roles.

### 17.12. Event

Registro inmutable de cambio de estado.

### 17.13. Gate

Condición requerida para transición de estado.

### 17.14. Policy

Regla vinculante de ejecución y aprobación.

### 17.15. Lock

Restricción temporal sobre recursos compartidos.

### 17.16. Budget

Límite de costo, iteraciones o tiempo.

### 17.17. Adapter

Componente que integra un sistema externo.

### 17.18. Plugin

Extensión opcional que expone acciones, eventos o UI.

### 17.19. ExtensionRegistry

Registro de adapters y plugins habilitados.

### 17.20. Memory

Conocimiento persistente destilado, recuperable y auditable.

### 17.21. MemoryAdapter

Puerto que integra un backend de memoria persistente.

---

## 18. Roles

### 18.1. Planner

Responsable de generar el plan global y estrategia por features.

### 18.2. Orchestrator

Responsable de coordinar ejecución, estados, locks y gates.

### 18.3. FeatureLead

Responsable extremo a extremo de una feature.

### 18.4. Developer

Responsable de implementar tareas.

### 18.5. Reviewer

Responsable de revisar calidad y conformidad.

### 18.6. QA

Responsable de pruebas.

### 18.7. Fixer

Responsable de corregir issues.

### 18.8. MergeManager

Responsable de validar merge.

### 18.9. Escalation

Responsable de desbloqueos.

### 18.10. SpecAssistant

Responsable de asistir generación de spec.

### 18.11. HumanApprover

Responsable de aprobar cambios críticos.

### 18.12. MemoryCurator

Responsable opcional de curar, validar, archivar o resolver conflictos de memoria.

---

## 19. Permisos de rol

1. Cada rol DEBE tener permisos explícitos.
2. Cada rol DEBE tener prohibiciones explícitas.
3. Un rol NO DEBE ejecutar acciones fuera de sus permisos.
4. Los permisos DEBEN ser configurables.
5. Los permisos críticos DEBEN requerir aprobación humana.
6. Los plugins NO DEBEN otorgar permisos fuera de policy.
7. Los adapters NO DEBEN modificar permisos de rol.
8. MemoryCurator NO DEBE modificar spec ni policy.
9. MemoryCurator PUEDE validar, archivar o marcar conflictos de memoria.

---

## 20. Modelos y routing

### 20.1. Perfiles de modelo

Talos define tres perfiles normativos:

```txt
cheap
mid
expensive
```

### 20.2. Orden de capacidad

```txt
cheap < mid < expensive
```

### 20.3. Routing obligatorio

1. El FeatureLead DEBE seleccionar modelo según routing.
2. El routing DEBE considerar riesgo de feature.
3. El routing DEBE considerar esfuerzo de tarea.
4. El routing DEBE considerar mínimo de rol.
5. El routing DEBE ser determinista.
6. El routing DEBE poder sobreescribirse por configuración de proyecto.
7. El routing NO DEBE depender del plugin.
8. El routing PUEDE considerar memorias validadas como contexto.

---

### 20.4. Algoritmo de selección

```txt
model_profile = max(
  model_by_task_effort,
  model_by_feature_risk,
  role_minimum_model
)
```

---

### 20.5. Mínimos recomendados

| Rol | Modelo mínimo |
|---|---|
| Planner | expensive |
| FeatureLead | dynamic |
| Developer | dynamic |
| Reviewer | mid |
| QA | mid |
| Fixer | dynamic |
| Escalation | expensive |
| SpecAssistant | expensive |
| MergeManager | none |
| MemoryCurator | mid |

---

## 21. Clasificación de esfuerzo y riesgo

### 21.1. Niveles de esfuerzo

```txt
trivial
low
medium
high
critical
```

### 21.2. Factores de esfuerzo

```txt
files_touched
contract_changes
data_migration
security_impact
test_complexity
dependency_depth
memory_complexity
```

### 21.3. Factores de riesgo

```txt
auth
billing
security
migrations
public_api
ci_cd
infrastructure
breaking_change
memory_poisoning
```

---

## 22. Ciclo de vida

### 22.1. Estados globales

```txt
PRECONDITION_CHECK
SPEC_MISSING
SPEC_ASSIST_OFFERED
SPEC_GENERATING
SPEC_REVIEW
SPEC_APPROVED
PROGRAM_PLANNING
PROGRAM_READY
FEATURE_READY
FEATURE_IN_PROGRESS
FEATURE_PR_OPEN
FEATURE_CHECKS_RUNNING
FEATURE_CHECKS_PASS
FEATURE_HUMAN_REVIEW
FEATURE_MERGED
FEATURE_DONE
FEATURE_BLOCKED
FEATURE_ESCALATED
FEATURE_FAILED
```

---

### 22.2. Gates

```txt
PRECONDITION_GATE
SPEC_GATE
PLAN_GATE
READY_GATE
DEV_GATE
REVIEW_GATE
QA_GATE
POLICY_GATE
HUMAN_GATE
MERGE_GATE
POST_MERGE_GATE
MEMORY_GATE
```

---

### 22.3. Reglas de transición

1. Toda transición DEBE estar permitida.
2. Toda transición DEBE registrar evento.
3. Toda transición DEBE requerir gate aprobado.
4. Toda transición fallida DEBE registrar causa.
5. Toda transición crítica DEBE requerir humano si policy lo indica.
6. Toda transición DEBE poder ser auditada.
7. Toda transición DEBE poder reconstruirse desde eventos.
8. Toda transición que consuma memoria DEBE registrar query usada.

---

## 23. Comunicación

### 23.1. Principios

1. Toda comunicación entre roles DEBE ser estructurada.
2. Toda comunicación DEBE persistirse.
3. Toda solicitud DEBE poder recibir respuesta.
4. Toda respuesta DEBE referenciar la solicitud original.
5. El contexto extenso DEBE referenciarse por artefacto.
6. Los mensajes NO DEBEN transportar contexto extenso embebido.
7. Toda pregunta sin respuesta DEBE expirar o escalar.
8. Toda comunicación DEBE poder reconstruirse desde eventos.
9. El transporte de mensajes DEBE ser intercambiable.
10. El protocolo de mensajes NO DEBE depender del plugin.

---

### 23.2. Canales

```txt
durable: repo_files
operational: adapter_specific
coordination: github_or_equivalent
memory: memory_adapter
```

---

### 23.3. Tipos de mensaje

```txt
TASK_REQUEST
TASK_RESPONSE
QUESTION
ANSWER
REVIEW_REQUEST
REVIEW_RESPONSE
FIX_REQUEST
FIX_RESPONSE
STATUS_UPDATE
ESCALATION
APPROVAL_REQUEST
APPROVAL_RESPONSE
SPEC_ASSIST_REQUEST
SPEC_ASSIST_RESPONSE
MEMORY_QUERY_REQUEST
MEMORY_QUERY_RESPONSE
MEMORY_VALIDATION_REQUEST
MEMORY_VALIDATION_RESPONSE
```

---

### 23.4. Estados de mensaje

```txt
OPEN
ACKED
ANSWERED
CLOSED
EXPIRED
ESCALATED
```

---

### 23.5. Reglas de eficiencia

1. Payload máximo RECOMENDADO: 16 KB.
2. Contexto grande DEBE ir como `artifact_refs`.
3. Cada mensaje DEBE tener `thread_id`.
4. Cada mensaje DEBE tener `id`.
5. Cada mensaje DEBE tener `created_at`.
6. Cada mensaje PUEDE tener `expires_at`.
7. Si expira sin respuesta, DEBE marcar `EXPIRED`.
8. Si `EXPIRED` y crítico, DEBE escalar.
9. Contexto de memoria DEBE contar contra presupuesto de prompt.

---

## 24. Artefactos y referencias

1. Todo artefacto DEBE ser versionable o referenciable.
2. Toda referencia DEBE usar ruta relativa o URI estable.
3. Toda referencia crítica DEBE poder validarse.
4. Los artefactos de entrada DEBEN existir antes de ejecutar tarea.
5. Los artefactos de salida DEBEN declararse explícitamente.
6. Los plugins PUEDEN mostrar artefactos.
7. Los plugins NO DEBEN ser la única copia de un artefacto.
8. Las memorias DEBEN referenciar artefactos cuando exista evidencia.

---

## 25. Preconditions

### 25.1. Preconditions obligatorias

1. Git instalado.
2. Repositorio git existente.
3. Identidad git configurada.
4. Autenticación git válida.
5. Permiso de push verificado.
6. Rama por defecto existente.
7. Spec presence verificada.
8. Spec manifest válido si spec existe.
9. Core version compatible.
10. Extension registry válido.

---

### 25.2. Preconditions opcionales de memoria

Si el MemoryAdapter está habilitado:

1. Backend de memoria instalado.
2. Backend de memoria accesible.
3. Proyecto de memoria configurado.
4. Memory config válida.
5. Secret scanning activo.

Para Engram:

```txt
engram instalado
engram version compatible
engram project configurado
MCP stdio u HTTP API disponible
```

---

### 25.3. Comprobación de cuenta git

Talos DEBE verificar como mínimo:

```txt
git --version
git rev-parse --is-inside-work-tree
git config user.name
git config user.email
git remote get-url origin
```

Si se usa GitHub, Talos DEBE verificar:

```txt
gh auth status
```

---

### 25.4. Fallo de precondition

1. Si una precondition requerida falla, Talos DEBE detenerse.
2. Talos DEBE mostrar requisito faltante.
3. Talos DEBE sugerir comando de remediación.
4. Talos NO DEBE continuar en modo silencioso.
5. Talos PUEDE continuar en modo dry-run si la falla es externa y no crítica.
6. Si falla el MemoryAdapter opcional, Talos PUEDE continuar sin memoria.

---

## 26. Spec intake

1. Talos DEBE leer `spec/manifest.yaml`.
2. Talos DEBE validar spec contra schema.
3. Talos NO DEBE planificar si spec no está aprobado.
4. Talos PUEDE asistir generación de spec en estado draft.
5. Talos DEBE requerir aprobación humana para `approved`.
6. El spec intake DEBE poder ejecutarse sin plugins.
7. El spec intake PUEDE consultar memorias de arquitectura y constraints.

---

## 27. Planificación de programa

1. Planner SOLO PUEDE ejecutarse tras `SPEC_APPROVED`.
2. Planner DEBE generar `orchestration/program-plan.json`.
3. Planner DEBE generar estrategia por feature.
4. Planner NO DEBE modificar `spec/`.
5. Planner DEBE identificar dependencias.
6. Planner DEBE clasificar riesgo.
7. Planner DEBE indicar modelo recomendado.
8. Planner DEBE indicar aprobación humana requerida.
9. Planner DEBE emitir eventos de planificación.
10. Planner PUEDE consultar memorias activas validadas.

---

## 28. Ejecución de feature

### 28.1. FeatureLead

1. FeatureLead DEBE crear issue.
2. FeatureLead DEBE crear rama.
3. FeatureLead DEBE crear worktree o entorno aislado.
4. FeatureLead DEBE descomponer tareas.
5. FeatureLead DEBE delegar tareas con mensaje estructurado.
6. FeatureLead DEBE mantener `feature-state.json`.
7. FeatureLead DEBE abrir PR.
8. FeatureLead NO DEBE mergear.
9. FeatureLead NO DEBE modificar ramas protegidas.
10. FeatureLead DEBE usar adapters para operaciones externas.
11. FeatureLead PUEDE consultar memorias relevantes.

---

### 28.2. Developer

1. Developer DEBE implementar solo tareas asignadas.
2. Developer NO DEBE ampliar alcance.
3. Developer DEBE ejecutar pruebas locales si aplica.
4. Developer DEBE responder con evidencia.
5. Developer PUEDE recibir contexto de memoria.
6. Developer NO DEBE tratar memoria como spec.

---

### 28.3. Reviewer

1. Reviewer DEBE revisar contra spec.
2. Reviewer DEBE generar review estructurada.
3. Reviewer NO DEBE reescribir código directamente.
4. Reviewer DEBE marcar blocker si faltan pruebas.
5. Reviewer PUEDE consultar memorias de seguridad y bugs.
6. Reviewer PUEDE proponer nuevas memorias.

---

### 28.4. QA

1. QA DEBE generar pruebas reproducibles.
2. QA DEBE generar reportes.
3. QA NO DEBE marcar pass sin ejecución real.
4. QA PUEDE modificar fixtures si es necesario.
5. QA PUEDE consultar memorias de test_strategy.

---

### 28.5. Fixer

1. Fixer DEBE corregir solo issues listados.
2. Fixer NO DEBE introducir nuevo alcance.
3. Fixer DEBE ejecutar pruebas tras corrección.
4. Fixer PUEDE consultar memorias de root_cause.

---

## 29. Merge governance

1. Merge DEBE requerir checks verdes.
2. Merge DEBE requerir estado mergeable.
3. Merge DEBE respetar política de aprobación.
4. Merge DEBE respetar locks.
5. Merge DEBE registrar evento.
6. Merge crítico DEBE requerir aprobación humana.
7. Auto-merge en v0.0.4 DEBE estar deshabilitado por defecto.
8. MergeManager DEBE usar adapter de coordinación.
9. Plugins NO DEBEN ejecutar merge directamente.
10. Merge DEBE poder simularse en dry-run.
11. Memoria NO DEBE autorizar merge por sí sola.

---

## 30. Locks y concurrencia

1. Todo recurso compartido crítico PUEDE requerir lock.
2. Todo lock DEBE tener feature propietaria.
3. Todo lock DEBE tener razón.
4. Todo lock DEBE tener timestamp.
5. Todo lock DEBE liberarse al terminar.
6. Si dos features requieren el mismo lock, Talos DEBE serializar o escalar.
7. v0.0.4 RECOMIENDA `max_parallel_features = 1`.
8. Locks DEBEN persistirse en runtime.
9. Plugins PUEDEN visualizar locks.
10. Plugins NO DEBEN liberar locks sin core.

---

## 31. Presupuestos

1. Toda ejecución PUEDE tener presupuesto.
2. Todo rol PUEDE tener límite de costo.
3. Toda feature PUEDE tener límite de iteraciones.
4. Si se excede presupuesto, Talos DEBE pausar o escalar.
5. v0.0.4 RECOMIENDA límites estrictos.
6. Presupuesto DEBE registrarse como evento.
7. Plugins PUEDEN mostrar presupuesto.
8. Plugins NO DEBEN omitir límites.
9. Consultas de memoria DEBEN respetar presupuesto de tokens.

---

## 32. Observabilidad

1. Todo cambio de estado DEBE registrar evento.
2. Todo mensaje DEBE poder consultarse.
3. Toda feature DEBE exponer estado actual.
4. Todo PR DEBE exponer checks.
5. Todo fallo DEBE registrar evidencia.
6. Talos DEBE permitir reconstruir historial.
7. Plugins PUEDEN proveer vistas.
8. La observabilidad core NO DEBE depender de plugins.
9. Toda consulta de memoria DEBE poder auditarse.
10. Toda escritura de memoria DEBE poder auditarse.

---

## 33. Error handling

1. Todo error DEBE clasificarse.
2. Todo error DEBE registrarse.
3. Todo error recuperable PUEDE reintentarse.
4. Todo error crítico DEBE escalar.
5. Tras 3 fallos repetidos, Talos DEBE escalar.
6. Talos NO DEBE ocultar errores.
7. Adapters DEBEN reportar errores estructurados.
8. Plugins DEBEN mostrar errores sin mutar estado directamente.
9. Fallos de memoria NO DEBEN bloquear el flujo principal si memoria es opcional.

---

## 34. Seguridad

1. Secrets NO DEBEN escribirse en prompts.
2. Secrets NO DEBEN versionarse.
3. Tokens DEBEN tener mínimo privilegio.
4. Logs NO DEBEN exponer secrets.
5. Aprobación humana DEBE exigirse en rutas críticas.
6. Talos DEBE respetar branch protection.
7. Plugins NO DEBEN almacenar secrets en claro.
8. Adapters DEBEN soportar credenciales externas.
9. Extensiones DEBEN declarar permisos sensibles.
10. Memorias NO DEBEN contener secrets.
11. Talos DEBE filtrar secrets antes de guardar memoria.
12. Talos DEBE marcar memorias sensibles si contienen datos delicados no secretos.

---

## 35. Extensibilidad

### 35.1. Principio de desacople

1. El core DEBE definir puertos.
2. Los adapters DEBEN implementar puertos.
3. Los plugins DEBEN consumir APIs del core.
4. Los plugins NO DEBEN acceder directamente a estado interno no expuesto.
5. El core NO DEBE depender de implementaciones concretas.
6. Talos DEBE poder reemplazar adapters sin cambiar core.
7. Talos DEBE poder operar sin plugins.
8. Talos DEBE poder operar con adapter dry-run.
9. Talos DEBE poder operar sin MemoryAdapter.
10. Talos DEBE poder reemplazar Engram por otro backend de memoria.

---

### 35.2. Extension points

Talos define los siguientes extension points:

```txt
ModelProviderAdapter
ExecutionAdapter
CoordinationAdapter
CIAdapter
FileSystemAdapter
MessageTransport
StateStore
EventBus
GateEvaluator
RoutingStrategy
RoleRegistry
Validator
Reporter
Plugin
MemoryAdapter
```

---

### 35.3. Tipos de extensión

| Tipo | Propósito |
|---|---|
| Adapter | Integra sistema externo |
| Plugin | Añade acciones, UI o automatización |
| Validator | Valida schemas o reglas |
| GateEvaluator | Evalúa gates personalizados |
| Reporter | Genera reportes |
| MessageTransport | Transporta mensajes |
| StateStore | Persiste estado |
| RoutingStrategy | Modifica selección de modelos |
| RoleRegistry | Registra roles personalizados |
| MemoryAdapter | Persiste y recupera memoria |

---

### 35.4. Reglas de extensión

1. Toda extensión DEBE declarar versión.
2. Toda extensión DEBE declarar compatibilidad.
3. Toda extensión DEBE declarar permisos.
4. Toda extensión DEBE poder ser habilitada o deshabilitada.
5. Toda extensión DEBE fallar de forma controlada.
6. Ninguna extensión DEBE romper aislamiento de `spec/`.
7. Ninguna extensión DEBE saltarse policy.
8. Ninguna extensión DEBE escribir en `schemas/` en runtime.
9. Ninguna extensión DEBE modificar `system/` en runtime.
10. Toda extensión DEBE ser auditable.
11. MemoryAdapter NO DEBE modificar estado normativo.
12. MemoryAdapter NO DEBE aprobar gates.

---

## 36. Adapters

### 36.1. Principio

1. El core NO DEBE depender directamente de vendors.
2. Toda integración externa DEBE implementarse como adapter.
3. Todo adapter DEBE devolver resultados estructurados.
4. Todo adapter DEBE tener health check.
5. Todo adapter DEBE soportar dry-run cuando sea posible.
6. Todo adapter DEBE declarar capacidades.
7. Todo adapter DEBE declarar versión.
8. Todo adapter DEBE poder ser reemplazado.

---

### 36.2. Adaptadores recomendados

```txt
talos-adapter-filesystem
talos-adapter-github
talos-adapter-herdr
talos-adapter-ci
talos-adapter-model
talos-adapter-dryrun
talos-adapter-engram
```

---

### 36.3. Capacidades esperadas

#### FileSystemAdapter

```txt
read_file
write_file
list_dir
ensure_dir
validate_path
```

#### ModelProviderAdapter

```txt
list_models
resolve_profile
invoke_model
estimate_cost
```

#### ExecutionAdapter

```txt
create_workspace
create_pane
start_agent
prompt_agent
wait_agent
read_agent
report_metadata
```

#### CoordinationAdapter

```txt
create_issue
create_branch
open_pr
get_pr_checks
request_review
merge_pr
```

#### CIAdapter

```txt
run_checks
get_check_status
publish_report
```

#### DryRunAdapter

```txt
simulate_action
log_intended_action
return_mock_result
```

#### MemoryAdapter

```txt
save_memory
update_memory
search_memory
get_context
compare_memory
judge_memory
archive_memory
forget_memory
memory_stats
detect_conflicts
```

---

### 36.4. Herdr adapter

El adapter de Herdr ES opcional.

ID recomendado:

```txt
talos.adapter.herdr
```

Responsabilidades:

```txt
- crear workspaces,
- crear tabs/panes,
- lanzar agentes,
- enviar prompts,
- esperar estados,
- leer salida,
- reportar metadata.
```

El adapter de Herdr NO DEBE:

```txt
- definir política de merge,
- modificar schemas,
- aprobar cambios críticos,
- reemplazar state store,
- decidir routing,
- escribir memoria normativa.
```

---

### 36.5. Engram adapter

El adapter de Engram ES opcional.

ID recomendado:

```txt
talos.adapter.engram
```

Paquete recomendado:

```txt
talos-adapter-engram
```

Backend:

```txt
Engram
```

Transportes soportados:

```txt
mcp_stdio
http_api
cli
```

Responsabilidades:

```txt
- guardar memorias,
- buscar memorias,
- actualizar memorias,
- comparar memorias,
- detectar conflictos,
- resumir sesiones,
- exponer estadísticas.
```

El adapter de Engram NO DEBE:

```txt
- definir policy,
- modificar spec,
- aprobar merges,
- alterar estado runtime normativo,
- almacenar secretos,
- reemplazar evidencia CI.
```

---

## 37. Plugins

### 37.1. Definición

Un plugin es una extensión opcional que expone:

```txt
- acciones,
- comandos,
- layouts,
- event handlers,
- reportes,
- metadata UI.
```

---

### 37.2. Principios

1. Un plugin NO DEBE ser requerido para ejecutar el core.
2. Un plugin DEBE invocar a Talos mediante CLI/API.
3. Un plugin NO DEBE mutar estado interno directamente.
4. Un plugin NO DEBE redefinir política.
5. Un plugin PUEDE mejorar UX.
6. Un plugin PUEDE automatizar acciones.
7. Un plugin PUEDE reaccionar a eventos.
8. Un plugin DEBE declarar permisos.
9. Un plugin DEBE declarar compatibilidad con core.
10. Un plugin DEBE poder desinstalarse sin corromper el proyecto.
11. Un plugin PUEDE visualizar memorias.
12. Un plugin NO DEBE escribir memoria sin pasar por MemoryAdapter.

---

### 37.3. Plugin de Herdr

ID recomendado:

```txt
talos.plugin.herdr
```

Paquete recomendado:

```txt
talos-plugin-herdr
```

El plugin de Herdr PUEDE exponer acciones como:

```txt
Start SDLC
Plan Portfolio
Start Feature
Run Review
Run QA
Open PR
Merge Guard
Escalate
Show Status
Memory Search
Memory Validate
Memory Conflicts
```

El plugin de Herdr PUEDE crear layouts:

```txt
Workspace: proyecto
  Tab: control
  Tab: agents
  Tab: github
  Tab: tests
  Tab: memory
  Tab: logs
```

El plugin de Herdr PUEDE mostrar metadata:

```txt
feature=F001
stage=IN_PROGRESS
model=expensive
risk=high
pr=57
checks=running
human=required
memory=8_hits
```

---

## 38. CLI / API

### 38.1. Principio

1. Talos DEBE exponer una CLI principal llamada `talos`.
2. La CLI DEBE poder operar sin plugins.
3. La CLI DEBE ser el medio principal de automatización.
4. Los plugins DEBEN preferir CLI/API sobre acceso directo a archivos internos.
5. La CLI DEBE devolver salida estructurada cuando se solicite.

---

### 38.2. Comandos mínimos

```txt
talos init
talos doctor
talos spec check
talos spec assist
talos plan
talos feature start <id>
talos feature status <id>
talos message send
talos review run <feature_id>
talos merge guard <pr_number>
talos status
talos plugin list
talos plugin enable <id>
talos plugin disable <id>
talos adapter list
talos adapter check <id>
```

---

### 38.3. Comandos de memoria

```txt
talos memory search <query>
talos memory show <memory_id>
talos memory save
talos memory update <memory_id>
talos memory validate <memory_id>
talos memory archive <memory_id>
talos memory forget <memory_id>
talos memory conflicts
talos memory stats
talos memory doctor
```

---

### 38.4. Salida estructurada

La CLI DEBE soportar:

```txt
--format json
```

para al menos:

```txt
status
feature status
adapter list
plugin list
doctor
memory search
memory stats
memory conflicts
```

---

## 39. Event system

### 39.1. Principio

1. Todo cambio relevante DEBE emitir evento.
2. Los eventos DEBEN ser append-only.
3. Los eventos DEBEN ser estructurados.
4. Los plugins PUEDEN suscribirse a eventos.
5. Los adapters PUEDEN emitir eventos.
6. Los eventos NO DEBEN mutar estado por sí solos.
7. El core DEBE ser la autoridad de estado.
8. Los eventos de memoria DEBEN auditar escritura y lectura.

---

### 39.2. Namespace de eventos

Todos los eventos oficiales DEBEN usar namespace:

```txt
talos
```

---

### 39.3. Eventos recomendados

```txt
talos.precondition.checked
talos.spec.missing
talos.spec.assist_requested
talos.spec.draft_generated
talos.spec.approved
talos.program.planned
talos.feature.ready
talos.feature.started
talos.feature.blocked
talos.feature.pr_opened
talos.feature.checks_started
talos.feature.checks_passed
talos.feature.checks_failed
talos.feature.human_requested
talos.feature.merged
talos.message.sent
talos.message.acked
talos.message.expired
talos.lock.acquired
talos.lock.released
talos.error.occurred
talos.escalation.triggered
```

---

### 39.4. Eventos de memoria

```txt
talos.memory.saved
talos.memory.updated
talos.memory.searched
talos.memory.injected
talos.memory.validated
talos.memory.archived
talos.memory.forgotten
talos.memory.conflict_detected
talos.memory.stale_detected
talos.memory.metric_reported
```

---

## 40. State store

### 40.1. Principio

1. El estado DEBE persistirse de forma durable.
2. El estado DEBE poder reconstruirse.
3. El estado NO DEBE depender de plugins.
4. El estado DEBE versionarse dentro de runtime.
5. El state store PUEDE ser intercambiable.
6. El estado normativo NO DEBE vivir exclusivamente en memoria.

---

### 40.2. Default state store

```txt
orchestration/
  state.json
  program-plan.json
  locks.json
  features/
  messages/
  reports/
  events/
  memory/
```

---

## 41. Configuración

### 41.1. Archivos obligatorios

```txt
config/system.yaml
config/models.yaml
config/roles.yaml
config/routing.yaml
config/policy.yaml
config/communication.yaml
config/preconditions.yaml
config/extensions.yaml
```

---

### 41.2. Archivos opcionales de memoria

```txt
config/memory.yaml
config/engram.yaml
```

---

### 41.3. Precedencia

```txt
system defaults
  < project overrides
    < policy gates
      < human approval
        < spec aprobado
          < memoria consultiva
```

---

### 41.4. Extensions config

```txt
config/extensions.yaml
```

DEBE registrar:

```txt
adapters habilitados
plugins habilitados
prioridad
compatibilidad
permisos
memory adapter
```

---

## 42. Sistema de memoria

### 42.1. Propósito

El sistema de memoria permite que Talos conserve conocimiento útil entre sesiones.

La memoria sirve para:

```txt
- mejorar planificación,
- reducir errores repetidos,
- recuperar decisiones,
- recuperar constraints,
- recuperar lecciones,
- acelerar escalaciones,
- mantener continuidad del proyecto.
```

---

### 42.2. Naturaleza de la memoria

1. La memoria ES consultiva.
2. La memoria NO ES normativa.
3. La memoria NO DEBE reemplazar spec.
4. La memoria NO DEBE reemplazar policy.
5. La memoria NO DEBE reemplazar evidencia CI.
6. La memoria PUEDE influir en prompts.
7. La memoria PUEDE influir en ranking de contexto.
8. La memoria PUEDE ser validada o archivada.

---

### 42.3. Prioridad de fuentes

Cuando Talos toma decisiones, el orden normativo es:

```txt
1. Policy / aprobación humana
2. Spec aprobado
3. Estado runtime y evidencia CI
4. Configuración de proyecto
5. Memoria validada
6. Memoria inferida
7. Heurísticas del agente
```

---

## 43. MemoryAdapter

### 43.1. Definición

MemoryAdapter es el puerto que integra un backend de memoria persistente.

Backend recomendado:

```txt
Engram
```

---

### 43.2. Capacidades del puerto

```txt
save_memory
update_memory
search_memory
get_context
compare_memory
judge_memory
archive_memory
forget_memory
memory_stats
detect_conflicts
```

---

### 43.3. Reglas del puerto

1. MemoryAdapter DEBE devolver resultados estructurados.
2. MemoryAdapter DEBE soportar scopes por proyecto.
3. MemoryAdapter DEBE soportar metadata.
4. MemoryAdapter DEBE permitir archivado.
5. MemoryAdapter DEBE permitir olvido explícito.
6. MemoryAdapter NO DEBE alterar estado runtime.
7. MemoryAdapter NO DEBE ejecutar acciones de merge.
8. MemoryAdapter NO DEBE almacenar secretos.
9. MemoryAdapter DEBE fallar de forma no bloqueante si es opcional.
10. MemoryAdapter DEBE registrar eventos de memoria.

---

## 44. Integración con Engram

### 44.1. Adapter oficial

```txt
talos-adapter-engram
```

---

### 44.2. Mapeo de capacidades

| Capacidad Talos | Engram |
|---|---|
| save_memory | mem_save |
| update_memory | mem_update |
| search_memory | mem_search |
| get_context | mem_context |
| compare_memory | mem_compare |
| judge_memory | mem_judge |
| archive_memory | mem_update / status archived |
| forget_memory | mem_delete |
| memory_stats | mem_stats |
| detect_conflicts | mem_compare / mem_review |
| session_summary | mem_session_summary |

---

### 44.3. Uso recomendado de Engram

1. Talos DEBE usar Engram como backend opcional.
2. Talos DEBE escribir memorias atómicas.
3. Talos DEBE buscar antes de guardar.
4. Talos DEBE comparar memorias similares.
5. Talos DEBE marcar conflictos.
6. Talos DEBE limitar recuperación por rol.
7. Talos DEBE inyectar memoria como contexto consultivo.
8. Talos NO DEBE usar passive capture como memoria activa sin curación.
9. Talos PUEDE usar session summaries como candidatas.
10. Talos PUEDE usar mem_judge para validar conflictos.

---

## 45. Entidad Memory

### 45.1. Campos obligatorios

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

---

### 45.2. Campos recomendados

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
```

---

### 45.3. Tipos de memoria

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

---

### 45.4. Estados de memoria

```txt
captured
candidate
validated
active
stale
archived
conflicted
```

---

### 45.5. Niveles de importancia

```txt
low
medium
high
critical
```

---

### 45.6. Niveles de confianza

```txt
low
medium
high
```

---

## 46. Política de escritura de memoria

### 46.1. Principios de guardado

1. Talos DEBE guardar conocimiento destilado.
2. Talos NO DEBE guardar ruido.
3. Talos NO DEBE guardar conversaciones crudas por defecto.
4. Talos NO DEBE guardar logs completos.
5. Talos NO DEBE guardar código completo.
6. Talos NO DEBE guardar secretos.
7. Talos DEBE guardar memorias atómicas.
8. Talos DEBE guardar títulos buscables.
9. Talos DEBE guardar metadata explícita.
10. Talos DEBE guardar referencias a artefactos cuando exista evidencia.

---

### 46.2. Títulos buscables

Los títulos DEBEN contener palabras clave relevantes.

Mal:

```txt
Cambio importante
```

Bien:

```txt
[auth] Magic link tokens expiran en 15 minutos
```

Mal:

```txt
Fix raro
```

Bien:

```txt
[auth] Fix token reuse por falta de invalidación en MagicLinkToken
```

---

### 46.3. Atomicidad

Cada memoria DEBE representar una sola idea.

Ejemplos válidos:

```txt
una decisión,
una lección,
un constraint,
un bug,
una causa raíz,
una estrategia de testing.
```

---

### 46.4. Deduplicación

Antes de guardar una memoria, Talos DEBE:

```txt
1. buscar memorias similares,
2. comparar similitud,
3. actualizar si es la misma,
4. marcar conflicto si contradice,
5. guardar solo si es nueva.
```

---

### 46.5. Validación

Memorias de alto impacto DEBEN requerir validación.

Tipos que RECOMIENDAN validación:

```txt
decision
constraint
architecture
security_note
api_contract
```

Estados:

```txt
captured -> candidate -> validated -> active
```

---

### 46.6. Eventos que generan memoria

Talos PUEDE generar memoria desde:

```txt
talos.spec.approved
talos.program.planned
talos.feature.merged
talos.error.occurred
talos.escalation.triggered
talos.review.completed
talos.checks.failed
```

---

### 46.7. Plantillas de memoria

#### Decision

```txt
Title: [module] decisión concreta
What: qué se decidió
Why: por qué
Alternatives: qué se descartó
Consequences: consecuencias
Evidence: artefactos/PRs
```

#### Lesson

```txt
Title: [module] lección operativa
Trigger: cuándo ocurre
Observation: qué se observó
Lesson: qué aprendimos
Prevention: cómo evitarlo
```

#### Bug / Root cause

```txt
Title: [module] síntoma/error
Symptom: error visible
Cause: causa raíz
Fix: solución
RegressionTest: prueba añadida
```

#### Constraint

```txt
Title: [module] restricción
Constraint: regla
Reason: razón
AppliesTo: archivos/módulos
```

#### Test strategy

```txt
Title: [module] estrategia de pruebas
What: qué probar
Why: por qué
How: unit/integration/e2e
KnownEdgeCases: casos edge
```

---

## 47. Política de recuperación de memoria

### 47.1. Principios de recuperación

1. Talos DEBE recuperar poca memoria y relevante.
2. Talos NO DEBE inyectar todas las memorias disponibles.
3. Talos DEBE filtrar por proyecto.
4. Talos DEBE filtrar por estado activo.
5. Talos DEBE limitar por rol.
6. Talos DEBE respetar presupuesto de contexto.
7. Talos DEBE rankear memorias.
8. Talos DEBE registrar queries de memoria.
9. Talos DEBE inyectar memoria como consejo.
10. Talos NO DEBE tratar memoria como regla superior.

---

### 47.2. Recuperación por rol

#### Planner

Recupera:

```txt
architecture
decision
constraint
security_note
performance_note
```

Top-k recomendado:

```txt
8-12
```

---

#### FeatureLead

Recupera:

```txt
decision
lesson
bug
test_strategy
constraint
```

Top-k recomendado:

```txt
5-8
```

---

#### Developer

Recupera:

```txt
lesson
bug
pattern
test_strategy
```

Top-k recomendado:

```txt
3-6
```

---

#### Reviewer

Recupera:

```txt
security_note
constraint
bug
anti_pattern
```

Top-k recomendado:

```txt
4-8
```

---

#### Escalation

Recupera:

```txt
root_cause
bug
lesson
escalation_summary
conflict
```

Top-k recomendado:

```txt
8-15
```

---

### 47.3. Construcción de query

Talos DEBE construir queries desde:

```txt
feature title,
module,
files,
tags,
error messages,
spec refs,
task description,
role.
```

---

### 47.4. Filtros obligatorios

```txt
project = current_project
status = active
```

Filtros opcionales:

```txt
type in allowed_types
feature_id = current_feature
files overlap current_files
importance >= threshold
confidence >= threshold
```

---

### 47.5. Ranking recomendado

```txt
final_score =
  0.45 * text_relevance
+ 0.20 * recency
+ 0.20 * importance
+ 0.10 * confidence
+ 0.05 * usage_frequency
```

Donde:

```txt
text_relevance  -> relevancia de búsqueda
recency         -> memorias recientes puntúan más
importance      -> high > medium > low
confidence      -> validated > inferred
usage_frequency -> memorias útiles usadas antes
```

---

### 47.6. Presupuesto de contexto

Recomendación:

```txt
máximo 5-10 memorias por prompt
máximo 2-4 KB de contexto de memoria
```

---

### 47.7. Formato de inyección

Talos DEBE inyectar memoria como paquete consultivo.

Ejemplo:

```md
## Relevant project memories

- [decision][high] Auth: magic link tokens expiran en 15 minutos
  Source: F001 merged
  Ref: spec/SPEC.md

- [lesson][medium] Auth: invalidar token tras primer uso
  Source: bug #132
  Ref: src/auth/verify.ts

- [security_note][high] No loguear tokens completos
  Source: security review
  Ref: src/logger.ts
```

---

## 48. Ciclo de vida de memoria

### 48.1. Estados

```txt
captured
candidate
validated
active
stale
archived
conflicted
```

---

### 48.2. Transiciones recomendadas

```txt
captured -> candidate
candidate -> validated
validated -> active
active -> stale
stale -> archived
active -> conflicted
conflicted -> validated
conflicted -> archived
active -> archived
archived -> forgotten
```

---

### 48.3. Reglas de lifecycle

1. Memorias automáticas DEBEN iniciar como `captured` o `candidate`.
2. Memorias críticas DEBEN requerir validación para `active`.
3. Memorias obsoletas DEBEN marcarse `stale`.
4. Memorias obsoletas confirmadas DEBEN archivarse.
5. Memorias contradictorias DEBEN marcarse `conflicted`.
6. Memorias archivadas NO DEBEN recuperarse por defecto.
7. Memorias olvidadas DEBEN eliminarse del backend.
8. Lifecycle DEBE registrarse con eventos.

---

## 49. Privacidad y gobierno de memoria

### 49.1. Reglas de privacidad

1. Talos NO DEBE guardar secrets.
2. Talos NO DEBE guardar tokens.
3. Talos NO DEBE guardar passwords.
4. Talos NO DEBE guardar credenciales.
5. Talos NO DEBE guardar logs sensibles completos.
6. Talos DEBE aplicar secret scanning antes de guardar.
7. Talos DEBE limitar tamaño de payload.
8. Talos PUEDE marcar memorias sensibles.
9. Talos DEBE permitir olvido explícito.
10. Talos DEBE auditar accesos a memoria sensible.

---

### 49.2. Reglas de gobierno

1. Memoria NO DEBE aprobar merges.
2. Memoria NO DEBE modificar spec.
3. Memoria NO DEBE modificar policy.
4. Memoria NO DEBE bloquear flujo principal si es opcional.
5. Memoria crítica DEBE poder revisarse.
6. Memoria conflictiva DEBE escalarse o curarse.
7. Memoria validada DEBE tener precedencia sobre memoria inferida.
8. Memoria antigua DEBE decaer en ranking.
9. Memoria DEBE poder exportarse.
10. Memoria DEBE poder auditarse.

---

## 50. Métricas de memoria

Talos DEBE poder medir calidad de memoria.

### 50.1. Métricas recomendadas

```txt
duplicate_memory_rate
stale_memory_rate
memory_hit_rate
memory_usage_rate
irrelevant_memory_rate
conflict_memory_rate
validation_rate
forget_rate
memory_latency
memory_error_rate
```

---

### 50.2. Definiciones

#### duplicate_memory_rate

```txt
memorias duplicadas / memorias guardadas
```

#### stale_memory_rate

```txt
memorias stale / memorias activas
```

#### memory_hit_rate

```txt
memorias recuperadas útiles / memorias recuperadas
```

#### irrelevant_memory_rate

```txt
memorias inyectadas no usadas / memorias inyectadas
```

#### conflict_memory_rate

```txt
memorias conflictivas / memorias activas
```

---

### 50.3. Uso de métricas

Talos DEBE usar métricas para:

```txt
- ajustar top_k,
- ajustar ranking,
- detectar ruido,
- detectar obsolescencia,
- mejorar curación,
- disparar revisión humana.
```

---

## 51. Configuración de memoria

### 51.1. Archivo recomendado

```txt
config/memory.yaml
```

```yaml
version: 1

memory:
  enabled: true
  adapter: talos.adapter.engram
  inject_as: advisory_context

  write_policy:
    enabled: true
    secret_scan: true
    dedupe_before_save: true
    min_importance_to_save: low
    min_confidence_to_activate: medium
    max_payload_kb: 64
    require_validation_for:
      - decision
      - constraint
      - security_note
      - architecture
      - api_contract
    auto_capture_events:
      - talos.spec.approved
      - talos.program.planned
      - talos.feature.merged
      - talos.escalation.triggered
      - talos.error.occurred
      - talos.review.completed

  read_policy:
    enabled: true
    max_memories_per_prompt: 8
    max_context_kb: 4
    only_active: true
    prefer_validated: true

    ranking:
      text_relevance: 0.45
      recency: 0.20
      importance: 0.20
      confidence: 0.10
      usage_frequency: 0.05

    role_profiles:
      planner:
        types:
          - architecture
          - decision
          - constraint
          - security_note
          - performance_note
        top_k: 10

      feature_lead:
        types:
          - decision
          - lesson
          - bug
          - test_strategy
          - constraint
        top_k: 8

      developer:
        types:
          - lesson
          - bug
          - pattern
          - test_strategy
        top_k: 5

      reviewer:
        types:
          - security_note
          - constraint
          - bug
          - anti_pattern
        top_k: 6

      escalation:
        types:
          - root_cause
          - bug
          - lesson
          - escalation_summary
          - conflict
        top_k: 12

  lifecycle:
    stale_after_days: 90
    archive_after_days: 365
    review_high_importance_every_days: 90

  metrics:
    enabled: true
    report_every: daily
```

---

### 51.2. Archivo recomendado para Engram

```txt
config/engram.yaml
```

```yaml
version: 1

adapter: talos.adapter.engram

project: my-project
data_dir: ~/.engram
transport: mcp_stdio

health_check:
  command: engram version

mcp:
  tools:
    save: mem_save
    update: mem_update
    search: mem_search
    context: mem_context
    compare: mem_compare
    judge: mem_judge
    stats: mem_stats
    session_summary: mem_session_summary

privacy:
  forbid_secrets: true
  forbid_full_code_dumps: true
  forbid_raw_logs: true
  max_payload_kb: 64
```

---

## 52. Algoritmo de guardado óptimo

```txt
cuando ocurre un evento importante:

  1. extraer resumen estructurado
  2. clasificar tipo de memoria
  3. detectar proyecto, feature, files, tags
  4. filtrar secrets
  5. calcular importance/confidence
  6. mem_search memorias similares
  7. si existe similar:
       mem_compare
       si misma:
         mem_update
       si conflicto:
         marcar conflicted
       si complementaria:
         mem_update o link
  8. si nueva:
       mem_save
  9. emitir talos.memory.saved
```

---

## 53. Algoritmo de recuperación óptima

```txt
antes de ejecutar un rol:

  1. construir query desde contexto actual
  2. definir filtros por rol
  3. mem_search
  4. filtrar status = active
  5. rerankear con score Talos
  6. aplicar top_k
  7. aplicar presupuesto de tokens
  8. ensamblar context packet
  9. inyectar como advisory_context
  10. registrar talos.memory.searched
```

---

## 54. Schemas nuevos en v0.0.4

### 54.1. memory.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://talos-sdlc/schemas/memory/0.0.4",
  "type": "object",
  "required": [
    "id",
    "project",
    "type",
    "title",
    "summary",
    "status",
    "importance",
    "confidence",
    "created_at"
  ],
  "properties": {
    "id": { "type": "string" },
    "project": { "type": "string" },
    "scope": {
      "type": "string",
      "enum": ["global", "project", "feature", "task"]
    },
    "feature_id": { "type": ["string", "null"] },
    "task_id": { "type": ["string", "null"] },
    "type": {
      "type": "string",
      "enum": [
        "decision",
        "lesson",
        "constraint",
        "architecture",
        "bug",
        "root_cause",
        "test_strategy",
        "security_note",
        "performance_note",
        "api_contract",
        "workflow_pattern",
        "anti_pattern",
        "escalation_summary"
      ]
    },
    "title": { "type": "string" },
    "summary": { "type": "string" },
    "content": { "type": "string" },
    "tags": {
      "type": "array",
      "items": { "type": "string" }
    },
    "files": {
      "type": "array",
      "items": { "type": "string" }
    },
    "artifact_refs": {
      "type": "array",
      "items": { "type": "string" }
    },
    "source_event": { "type": "string" },
    "importance": {
      "type": "string",
      "enum": ["low", "medium", "high", "critical"]
    },
    "confidence": {
      "type": "string",
      "enum": ["low", "medium", "high"]
    },
    "status": {
      "type": "string",
      "enum": [
        "captured",
        "candidate",
        "validated",
        "active",
        "stale",
        "archived",
        "conflicted"
      ]
    },
    "review_at": { "type": ["string", "null"] },
    "created_at": { "type": "string" },
    "updated_at": { "type": ["string", "null"] },
    "superseded_by": { "type": ["string", "null"] },
    "usage_count": { "type": "integer" },
    "last_used_at": { "type": ["string", "null"] }
  }
}
```

---

### 54.2. memory-config.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://talos-sdlc/schemas/memory-config/0.0.4",
  "type": "object",
  "required": ["version", "memory"],
  "properties": {
    "version": {
      "type": "integer",
      "const": 1
    },
    "memory": {
      "type": "object",
      "required": ["enabled", "adapter"],
      "properties": {
        "enabled": { "type": "boolean" },
        "adapter": { "type": "string" },
        "inject_as": {
          "type": "string",
          "enum": ["advisory_context", "disabled"]
        },
        "write_policy": {
          "type": "object",
          "properties": {
            "enabled": { "type": "boolean" },
            "secret_scan": { "type": "boolean" },
            "dedupe_before_save": { "type": "boolean" },
            "min_importance_to_save": {
              "type": "string",
              "enum": ["low", "medium", "high", "critical"]
            },
            "min_confidence_to_activate": {
              "type": "string",
              "enum": ["low", "medium", "high"]
            },
            "max_payload_kb": { "type": "integer" },
            "require_validation_for": {
              "type": "array",
              "items": { "type": "string" }
            },
            "auto_capture_events": {
              "type": "array",
              "items": { "type": "string" }
            }
          }
        },
        "read_policy": {
          "type": "object",
          "properties": {
            "enabled": { "type": "boolean" },
            "max_memories_per_prompt": { "type": "integer" },
            "max_context_kb": { "type": "integer" },
            "only_active": { "type": "boolean" },
            "prefer_validated": { "type": "boolean" },
            "ranking": {
              "type": "object",
              "properties": {
                "text_relevance": { "type": "number" },
                "recency": { "type": "number" },
                "importance": { "type": "number" },
                "confidence": { "type": "number" },
                "usage_frequency": { "type": "number" }
              }
            },
            "role_profiles": {
              "type": "object"
            }
          }
        },
        "lifecycle": {
          "type": "object",
          "properties": {
            "stale_after_days": { "type": "integer" },
            "archive_after_days": { "type": "integer" },
            "review_high_importance_every_days": { "type": "integer" }
          }
        },
        "metrics": {
          "type": "object",
          "properties": {
            "enabled": { "type": "boolean" },
            "report_every": { "type": "string" }
          }
        }
      }
    }
  }
}
```

---

### 54.3. memory-query.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://talos-sdlc/schemas/memory-query/0.0.4",
  "type": "object",
  "required": [
    "project",
    "role",
    "query"
  ],
  "properties": {
    "project": { "type": "string" },
    "role": { "type": "string" },
    "query": { "type": "string" },
    "feature_id": { "type": ["string", "null"] },
    "task_id": { "type": ["string", "null"] },
    "types": {
      "type": "array",
      "items": { "type": "string" }
    },
    "files": {
      "type": "array",
      "items": { "type": "string" }
    },
    "tags": {
      "type": "array",
      "items": { "type": "string" }
    },
    "status": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": [
          "captured",
          "candidate",
          "validated",
          "active",
          "stale",
          "archived",
          "conflicted"
        ]
      }
    },
    "top_k": { "type": "integer" },
    "max_context_kb": { "type": "integer" },
    "ranking": {
      "type": "object",
      "properties": {
        "text_relevance": { "type": "number" },
        "recency": { "type": "number" },
        "importance": { "type": "number" },
        "confidence": { "type": "number" },
        "usage_frequency": { "type": "number" }
      }
    }
  }
}
```

---

## 55. Schemas previos vigentes

Los siguientes schemas de versiones anteriores permanecen vigentes y deben actualizarse su `$id` a `0.0.4` cuando se implementen:

```txt
system-manifest.schema.json
project-manifest.schema.json
spec-manifest.schema.json
models-config.schema.json
roles-config.schema.json
routing-config.schema.json
policy-config.schema.json
communication-config.schema.json
preconditions-config.schema.json
extension-registry.schema.json
adapter-manifest.schema.json
plugin-manifest.schema.json
message.schema.json
event.schema.json
feature-state.schema.json
program-plan.schema.json
review.schema.json
locks.schema.json
```

---

## 56. Criterios de aceptación de Talos v0.0.4

La versión 0.0.4 se considera aceptable si:

1. El sistema se llama oficialmente Talos.
2. El paquete canónico es `talos-sdlc`.
3. La CLI oficial es `talos`.
4. El sistema valida schemas básicos.
5. El sistema detecta preconditions fallidas.
6. El sistema detecta spec faltante.
7. El sistema pregunta si generar spec.
8. El sistema no planifica sin spec aprobado.
9. El sistema genera program-plan válido.
10. El sistema delega una feature en modo serial.
11. El sistema registra mensajes estructurados.
12. El sistema registra eventos con namespace `talos`.
13. El sistema abre PR o simula apertura en dry-run.
14. El sistema no mergea sin checks.
15. El sistema exige humano en riesgo crítico.
16. El sistema no escribe reglas dentro de `spec/`.
17. El sistema mantiene estado reconstruible.
18. El sistema puede ejecutarse en proyecto de prueba pequeño.
19. El sistema puede operar sin plugins.
20. El sistema puede operar con adapter dry-run.
21. El plugin de Herdr es opcional.
22. El plugin de Herdr no puede saltarse policy.
23. El core valida compatibilidad de extensiones.
24. El sistema puede operar sin MemoryAdapter.
25. El sistema puede integrar Engram mediante `talos-adapter-engram`.
26. El sistema guarda memorias atómicas.
27. El sistema deduplica memorias antes de guardar.
28. El sistema filtra secretos antes de guardar.
29. El sistema recupera memorias por rol.
30. El sistema aplica ranking y top-k.
31. El sistema inyecta memoria como contexto consultivo.
32. El sistema marca conflictos de memoria.
33. El sistema permite validar, archivar y olvidar memorias.
34. El sistema expone métricas de memoria.
35. Memoria no reemplaza spec, policy ni CI.

---

## 57. Modo recomendado para v0.0.4

```txt
mode = serial
auto_merge = false
human_approval = required_for_critical
dry_run = preferred
max_parallel_features = 1
plugins = optional
herdr_plugin = optional
memory_adapter = optional
engram_adapter = optional
memory_injection = advisory_context
```

---

## 58. Changelog

### 0.0.4

- Introducción del sistema de memoria persistente.
- Nuevo extension point: MemoryAdapter.
- Nuevo adapter recomendado: talos-adapter-engram.
- Nueva entidad: Memory.
- Nuevo rol opcional: MemoryCurator.
- Nueva sección: Memory Governance.
- Nueva política de escritura de memoria.
- Nueva política de recuperación de memoria.
- Nuevo lifecycle de memoria.
- Nuevo ranking de recuperación.
- Nuevo presupuesto de contexto para memoria.
- Nuevos eventos `talos.memory.*`.
- Nuevos comandos CLI `talos memory *`.
- Nuevos schemas:
  - memory.schema.json
  - memory-config.schema.json
  - memory-query.schema.json
- Nueva configuración:
  - config/memory.yaml
  - config/engram.yaml
- Regla explícita: memoria es consultiva, no normativa.
- Regla explícita: memoria no debe contener secretos.
- Regla explícita: memoria no debe reemplazar spec, policy o CI.

### 0.0.3

- Nombre oficial del sistema: Talos.
- Paquete canónico: talos-sdlc.
- CLI oficial: talos.
- Runtime local recomendado: .talos/.
- Namespace de eventos: talos.
- Prefijos oficiales para adapters y plugins.
- Plugin de Herdr renombrado conceptualmente como talos-plugin-herdr.
- Adapter de Herdr renombrado conceptualmente como talos-adapter-herdr.
- Schemas actualizados con namespace talos-sdlc.
- Project manifest actualizado para usar system name Talos.

### 0.0.2

- Arquitectura desacoplada por capas.
- Introducción de contratos y puertos.
- Introducción de adapters.
- Introducción de plugins.
- Separación explícita entre core y plugin de Herdr.
- Extension registry.
- Adapter manifest schema.
- Plugin manifest schema.
- CLI mínima normativa.
- Event system normativo.
- State store normativo.
- Dry-run adapter recomendado.
- Core portable sin plugins.

### 0.0.1

- Versión inicial experimental.
- Separación formal entre sistema y spec.
- Definición de roles, lifecycle, comunicación y governance.
- Schemas mínimos.
- Preconditions y spec intake.
- Routing por riesgo y esfuerzo.
- Orientación a piloto serial supervisado.