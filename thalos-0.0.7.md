# Thalos Core System Specification

**System Name:** Thalos
**Canonical Package:** thalos-sdlc
**System Version:** 0.0.6
**Status:** Experimental Baseline
**Date:** 2026-07-30
**Document Type:** Core System Specification
**Language:** Spanish normative text
**Supersedes:** 0.0.5
**Companion documents:** `thalos-memory-0.0.1.md` (extensión opcional de memoria)

---

## 0. Convenciones del documento

### 0.1. Palabras clave normativas

Las palabras clave DEBE, NO DEBE, REQUERIDO, PUEDE, RECOMENDADO y OPCIONAL deben interpretarse como requisitos normativos.

### 0.2. Alcance del documento

Este documento define el **núcleo** del sistema automatizador llamado **Thalos**.

Este documento NO define el spec del producto a desarrollar.

Este documento NO define el sistema de memoria persistente. La memoria es una extensión OPCIONAL especificada en `thalos-memory-0.0.1.md`.

### 0.3. Política de términos indefinidos

1. Todo término usado en un requisito normativo DEBE estar definido en este documento o en un documento referenciado.
2. Si un requisito depende de un término indefinido, ese requisito NO ES normativo hasta que el término se defina.
3. Los términos `evidencia`, `gate`, `lease`, `idempotencia` y `evento` están definidos en las secciones 23, 24, 32, 38 y 41 respectivamente.

### 0.4. Decisiones abiertas

Las decisiones que requieren resolución humana antes de implementar se marcan como `DECISIÓN ABIERTA D-nnn` y se listan en la sección 50.

---

## 1. Nombre del sistema

El sistema se denomina:

```txt
Thalos
```

Nombre canónico de paquete:

```txt
thalos-sdlc
```

CLI oficial:

```txt
thalos
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
Thalos, autómata guardián de la mitología griega.
```

---

### 1.1. Nombre y colisión

`DECISIÓN D-001 — RESUELTA en 0.0.7`

El proyecto se llamaba `Talos`. El nombre estaba tomado, y no por uno sino por varios proyectos activos:

| Registry | `talos` | `thalos` |
|---|---|---|
| npm | tomado (framework de bots IRC, 2014) | libre |
| PyPI | **tomado y activo** (Talos Hyperparameter Tuning for Keras, v1.4, abril 2024) | libre |
| crates.io | — | libre |

A eso se suma **Talos Linux** (Sidero Labs), sistema operativo inmutable para Kubernetes con ecosistema activo y CLI `talosctl`, y Cisco Talos en seguridad. Tres proyectos vivos en dominios distintos.

Verificado esto, el proyecto pasa a llamarse **Thalos**, con paquete canónico `thalos-sdlc`.

Dos correcciones al análisis que traía 0.0.6:

1. **La colisión de binario era más débil de lo que se afirmaba.** El CLI de Talos Linux es `talosctl`, no `talos`. El riesgo real era de registries y de búsqueda, no de `PATH`.
2. **La colisión de registries era más fuerte.** El documento solo nombraba a Talos Linux; la colisión que de verdad bloqueaba publicar es la de PyPI, que está mantenida y es de otro dominio por completo.

Lo que el cambio NO resuelve, y conviene tener presente: `Thalos` y `Talos` son homófonos en español. Mejora la búsqueda y la publicación; no elimina la confusión hablada.

El momento del cambio se eligió por costo: la superficie era de 133 archivos y **cero instalaciones de terceros**. Renombrar más tarde solo podía salir más caro.

---

## 2. Propósito

Thalos define un marco normativo y extensible para orquestar desarrollo de software asistido por agentes.

Thalos cubre:

- intake de spec,
- planificación,
- desarrollo,
- revisión,
- pruebas,
- aprobación,
- merge,
- trazabilidad.

Thalos está diseñado para ser:

- versionado,
- reutilizable,
- configurable,
- auditable,
- desacoplado,
- extensible,
- integrable con múltiples agentes y entornos.

La capacidad de aprender de ejecuciones anteriores es una extensión OPCIONAL, no una propiedad del núcleo.

---

## 3. Alcance de la versión 0.0.6

La versión 0.0.6 define, además de todo lo definido en 0.0.5:

1. **Clasificación de extension points por capacidad REQUERIDA u OPCIONAL, separada de la implementación que la satisface.**
2. **`ExecutionAdapter` como capacidad requerida, con `thalos-adapter-herdr` como implementación de referencia.**
3. **Precondition de exactamente un `ExecutionAdapter` habilitado y sano.**
4. **Modo `--dry-run-only` para validar el sistema sin ExecutionAdapter productivo.**
5. **Prohibición explícita de nombrar implementaciones concretas fuera del extension registry.**

La versión 0.0.5 definió:

1. Nombre oficial del sistema y riesgo de colisión declarado.
2. Separación entre sistema automatizador y spec de producto.
3. Arquitectura desacoplada por capas.
4. Modelo de extensión basado en adapters y plugins.
5. Entidades fundamentales.
6. Roles agente, rol humano y componentes de núcleo.
7. **Dos máquinas de estado explícitas: programa y feature.**
8. **Tabla completa de transiciones con gate, actor, evidencia y evento.**
9. **Tipo `Evidence` definido y enumerado.**
10. **Contrato de `GateEvaluator`.**
11. Protocolo de comunicación.
12. **Routing por capacidad, desacoplado de costo.**
13. Gobierno de merge como componente de núcleo.
14. Preconditions.
15. Gestión de spec faltante e inválido.
16. **Contratos de adapters con idempotencia obligatoria.**
17. **Semántica de timeout, reintento y backoff.**
18. **Locks como leases con TTL, heartbeat y fencing token.**
19. Contratos de plugins.
20. CLI oficial `thalos`.
21. **Event system con secuencia monotónica y versión de schema por evento.**
22. **Schemas completos de los artefactos obligatorios.**
23. **Cadena de configuración separada de la cadena de autoridad de decisión.**
24. **Contrato de migración de estado runtime.**
25. Criterios de aceptación para piloto serial.

---

## 4. No alcance de la versión 0.0.6

La versión 0.0.6 NO define completamente:

1. Paralelismo agresivo multi-feature.
2. Auto-merge autónomo sin supervisión.
3. Optimización avanzada de costos.
4. Dashboard gráfico externo.
5. Recuperación automática ante todos los modos de fallo.
6. Entornos distribuidos multi-máquina.
7. Marketplace completo de plugins.
8. Entrenamiento o fine-tuning de modelos.
9. **Memoria persistente** — extensión opcional en documento aparte.

La versión 0.0.6 está orientada a:

```txt
piloto controlado, serial, con supervisión humana, dry-run preferente, arquitectura extensible
```

---

## 5. Principios normativos

### 5.1. Separación

1. Thalos DEBE ser independiente del spec del producto.
2. Thalos DEBE ser versionado.
3. El spec del producto DEBE residir en `spec/`.
4. Thalos NO DEBE escribir reglas propias dentro de `spec/`.

### 5.2. Trazabilidad

5. Todo cambio DEBE ser trazable a spec, feature, task y PR.
6. Toda comunicación entre roles DEBE ser explícita y estructurada. **La estructura es del sobre y la pone Thalos; el contenido puede ser cualquier cosa.**
6.a. Ninguna respuesta de un rol DEBE descartarse por no tener el formato esperado.
6.b. Toda respuesta que no pueda interpretarse DEBE persistirse igual y entregarse a alguien que pueda actuar sobre ella.
6.c. La comunicación NO DEBE cortarse de forma inesperada: un paso que termina sin lo que esperaba DEBE dejar registrado lo que sí recibió.
7. Toda decisión relevante DEBE persistirse como artefacto o evento.
8. Toda transición de estado DEBE producir evidencia según la sección 23.
9. Todo evento DEBE tener secuencia monotónica dentro de su run.

### 5.3. Gobierno

10. Toda ejecución DEBE respetar permisos de rol.
11. Toda feature DEBE clasificarse por riesgo y esfuerzo.
12. Todo merge DEBE cumplir gates automáticos y política de aprobación.
13. Ante ambigüedad, Thalos DEBE preguntar o escalar.
14. La configuración NO DEBE poder violar policy; una config que viole policy DEBE rechazarse al cargar.

### 5.4. Desacople

15. El núcleo de Thalos DEBE permanecer independiente de vendors.
16. Toda integración externa DEBE implementarse como adapter.
17. Toda extensión de UI o automatización DEBE implementarse como plugin.
18. Thalos DEBE poder operar sin plugins.
19. Los plugins NO DEBEN reemplazar al núcleo.
20. Los adapters NO DEBEN definir política de negocio.
20.a. Una capacidad REQUERIDA obliga a habilitar alguna implementación; NO obliga a una implementación concreta.
20.b. El núcleo NO DEBE nombrar implementaciones concretas fuera del extension registry y de la configuración.
20.c. Que una implementación sea reemplazable NO significa que la capacidad sea prescindible.

### 5.5. Robustez

21. Toda operación externa mutante DEBE ser idempotente.
22. Todo lock DEBE tener expiración.
23. Todo error DEBE clasificarse antes de decidir reintento.
24. El estado runtime DEBE poder migrarse entre versiones de Thalos.
25. Toda referencia a un recurso externo DEBE llevar la procedencia de quien la produjo.
26. Una referencia NO DEBE usarse contra un productor distinto del que la creó.
27. Que un recurso se haya creado NO prueba que siga existiendo. Antes de reusar una referencia sobre un recurso que puede desaparecer, el estado DEBE reconciliarse contra el backend.
28. Toda identidad DEBE ser única en el espacio de nombres donde se usa, no en el que la produjo.

### 5.6. Extensiones

25. Ninguna extensión DEBE ser requerida para ejecutar el núcleo.
26. Ninguna extensión DEBE aprobar gates.
27. Ninguna extensión DEBE tener autoridad normativa sobre spec o policy.

---

## 6. Identidad técnica de Thalos

| Elemento | Valor |
|---|---|
| Nombre | Thalos |
| Paquete canónico | thalos-sdlc |
| CLI | thalos |
| Namespace de eventos | thalos |
| Prefijo de adapters | thalos-adapter- |
| Prefijo de plugins | thalos-plugin- |
| Runtime local | .thalos/ |
| API namespace | thalos/v0 |
| Extensión de memoria | thalos-ext-memory (opcional) |

---

## 7. Arquitectura general

El núcleo de Thalos se divide en siete capas normativas:

```txt
1. Spec Layer
2. Core Kernel
3. Contracts & Schemas
4. Configuration
5. CLI / API
6. Adapters
7. Plugins
```

La capa de memoria NO es parte del núcleo. Se integra, si está habilitada, mediante el extension point `MemoryAdapter` definido en `thalos-memory-0.0.1.md`.

---

## 8. Separación arquitectónica obligatoria

### 8.1. Automation System

Capa normativa y ejecutable de Thalos.

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

### 8.4. Extensiones opcionales

Toda capacidad no requerida por los criterios de aceptación del núcleo DEBE vivir fuera del núcleo y conectarse por extension point.

---

## 9. Reserva semántica de directorios

| Directorio | Significado | Normatividad |
|---|---|---|
| `system/` | Documentos normativos de Thalos | Obligatorio |
| `contracts/` | Contratos funcionales y puertos | Obligatorio |
| `schemas/` | Contratos estructurales JSON Schema | Obligatorio |
| `core/` | Lógica central de Thalos | Obligatorio |
| `cli/` | Interfaz de comandos `thalos` | Obligatorio |
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
thalos-sdlc/
  VERSION
  CHANGELOG.md
  README.md

  system/
    00-principles.md
    01-entities.md
    02-roles.md
    03-lifecycle.md
    04-evidence.md
    05-gates.md
    06-communication.md
    07-governance.md
    08-preconditions.md
    09-spec-intake.md
    10-extensibility.md
    11-reliability.md
    12-naming.md

  contracts/
    ports.md
    adapters.md
    plugins.md
    events.md
    cli.md
    evidence.md
    gates.md

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
    evidence.schema.json
    gate-result.schema.json
    feature-state.schema.json
    program-plan.schema.json
    review.schema.json
    locks.schema.json
    runtime-meta.schema.json

  core/
    state/
    policy/
    routing/
    messaging/
    planning/
    validation/
    events/
    gates/
    locks/
    reliability/
    migration/

  cli/
    thalos
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
    reliability.yaml

  adapters/
    filesystem/
    github/
    herdr/
    ci/
    model/
    dryrun/

  plugins/
    herdr/

  examples/
    project-sample/
    spec-sample/
```

---

## 11. Estructura del repositorio de proyecto

```txt
my-project/
  .thalos/
    VERSION
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

  thalos.config/
    project.yaml
    overrides.yaml
    extensions.yaml
    reliability.yaml

  orchestration/
    .meta.json
    state.json
    program-plan.json
    locks.json
    features/
    messages/
    reports/
    events/
    evidence/

  src/
  tests/
  docs/
```

**Nota de corrección respecto de 0.0.4:** el directorio de configuración del proyecto se renombra de `config/` a `thalos.config/` para eliminar la colisión con el `config/` del sistema vendoreado en `.thalos/config/` y con cualquier `config/` propio del producto.

---

## 12. Versionado y migración

### 12.1. Versionado

1. Thalos DEBE tener un archivo `VERSION`.
2. Thalos DEBE seguir versionado semántico.
3. Cada proyecto DEBE fijar una versión específica de Thalos.
4. Thalos NO DEBE depender de cambios no versionados en el proyecto.
5. Thalos DEBE poder ser instalado como subdirectorio `.thalos/`.
6. Los plugins DEBEN declarar compatibilidad con versiones del core.
7. Los adapters DEBEN declarar versión y API soportada.

### 12.2. Metadatos de runtime

Todo runtime DEBE contener `orchestration/.meta.json`:

```json
{
  "runtime_schema_version": 1,
  "thalos_version": "0.0.6",
  "run_id": "r-2026-07-30-001",
  "created_at": "2026-07-30T10:00:00Z",
  "last_migrated_at": null,
  "last_event_seq": 0
}
```

### 12.3. Contrato de migración

1. Thalos DEBE comparar `runtime_schema_version` contra la versión soportada al arrancar.
2. Si el runtime es más viejo, Thalos DEBE detenerse y exigir `thalos migrate`.
3. Si el runtime es más nuevo, Thalos DEBE detenerse y exigir upgrade del sistema.
4. `thalos migrate` DEBE crear un backup completo de `orchestration/` antes de modificar.
5. Las migraciones DEBEN ser forward-only.
6. Toda migración DEBE ser idempotente.
7. Toda migración DEBE emitir `thalos.runtime.migrated`.
8. Si el estado no puede migrarse, Thalos DEBE ofrecer reconstrucción desde el event log.
9. El event log DEBE conservarse íntegro entre migraciones.

---

## 13. Manifiesto del sistema

Thalos DEBE declarar:

```txt
system_name
system_version
api_version
spec_schema_version
config_schema_version
runtime_schema_version
event_schema_version
status
adapters
plugins
extensions
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
config root
config overrides
extensions
```

---

## 15. Spec de producto

### 15.1. Reserva de `spec/`

1. `spec/` DEBE contener únicamente el spec del producto.
2. `spec/` NO DEBE contener configuración de Thalos.
3. `spec/` NO DEBE contener estado de orquestación.
4. `spec/` NO DEBE contener ejemplos del sistema.
5. `spec/` NO DEBE contener reportes de ejecución.
6. `spec/` NO DEBE contener plugins ni adapters.
7. `spec/` NO DEBE contener artefactos de extensiones.

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

## 16. Spec faltante e inválido

### 16.1. Spec faltante

1. Thalos DEBE verificar presencia de spec.
2. Si no existe spec, Thalos DEBE entrar en `SPEC_MISSING`.
3. Thalos DEBE preguntar al usuario si desea asistencia.
4. Si el usuario acepta, Thalos DEBE entrar en `SPEC_GENERATING` con `SpecAssistant`.
5. Si el usuario rechaza, Thalos DEBE entrar en `HALTED`.
6. `SpecAssistant` SOLO PUEDE escribir dentro de `spec/`.
7. `SpecAssistant` NO PUEDE aprobar el spec.
8. El spec generado DEBE requerir aprobación humana.

### 16.2. Spec inválido

**Corrección respecto de 0.0.4: este caso no tenía estado.**

1. Si el spec existe pero no valida contra `spec-manifest.schema.json`, Thalos DEBE entrar en `SPEC_INVALID`.
2. Thalos DEBE producir un `SchemaValidationReport` con la lista completa de violaciones.
3. Thalos NO DEBE intentar corregir el spec sin autorización explícita del usuario.
4. Desde `SPEC_INVALID` el usuario PUEDE corregir manualmente o autorizar a `SpecAssistant`.
5. Thalos NO DEBE planificar desde `SPEC_INVALID`.

---

## 17. Entidades de Thalos

| Entidad | Definición |
|---|---|
| Project | Entidad raíz del desarrollo actual |
| System | Motor normativo y ejecutable llamado Thalos |
| Spec | Descripción normativa del producto a construir |
| Program | Conjunto planificado de features derivadas del spec |
| Feature | Unidad independiente de valor |
| Task | Unidad atómica de trabajo |
| Role | Responsabilidad con permisos |
| Agent | Modelo que ejecuta un rol agente |
| Session | Entorno de ejecución asociado a un rol |
| Artifact | Archivo versionado o referencia estable |
| Evidence | Artefacto tipado que justifica una transición (sección 23) |
| Message | Comunicación estructurada entre roles |
| Event | Registro inmutable y secuenciado de cambio de estado |
| Gate | Condición evaluable requerida para transición (sección 24) |
| Policy | Regla vinculante de ejecución y aprobación |
| Lease | Lock con expiración y fencing token (sección 32) |
| Budget | Límite de costo, iteraciones o tiempo |
| Adapter | Componente que integra un sistema externo |
| Plugin | Extensión opcional que expone acciones, eventos o UI |
| ExtensionRegistry | Registro de adapters y plugins habilitados |

---

## 18. Roles y componentes

**Corrección respecto de 0.0.4: 12 roles se reducen a 5 roles agente, 1 rol humano y 5 componentes de núcleo. Un "rol" sin modelo no es un rol, es código.**

### 18.1. Roles agente

Ejecutados por un modelo. Consumen presupuesto. Requieren routing.

| Rol | Responsabilidad |
|---|---|
| `SpecAssistant` | Asistir la generación del spec dentro de `spec/` |
| `Planner` | Generar el plan de programa y la estrategia por feature |
| `FeatureLead` | Responsable extremo a extremo de una feature |
| `Developer` | Implementar tareas asignadas, incluidas correcciones |
| `Reviewer` | Revisar calidad, conformidad y cobertura de pruebas |

### 18.2. Rol humano

| Rol | Responsabilidad |
|---|---|
| `HumanApprover` | Aprobar spec, cambios críticos, merges críticos y desbloqueos |

### 18.3. Componentes de núcleo

Deterministas. Sin modelo. Sin presupuesto de tokens. **No son roles.**

| Componente | Responsabilidad |
|---|---|
| `Orchestrator` | Coordinar transiciones, invocar gates, despachar mensajes |
| `GateEvaluator` | Evaluar gates contra evidencia (sección 24) |
| `MergeGate` | Validar condiciones de merge (sección 31) |
| `LockManager` | Otorgar, renovar, expirar y reclamar leases (sección 32) |
| `EventLog` | Asignar secuencia y persistir eventos (sección 41) |

### 18.4. Roles eliminados y su destino

| Rol 0.0.4 | Destino en 0.0.5 | Razón |
|---|---|---|
| `Orchestrator` | Componente de núcleo | No requiere modelo |
| `QA` | Absorbido por `Reviewer` + `CIAdapter` | El pase real lo determina CI, no un agente |
| `Fixer` | Absorbido por `Developer` | Mismo permiso, mismo modelo, solo cambia el input |
| `MergeManager` | Componente `MergeGate` | Evaluaba cinco booleanos; tenía `model: none` |
| `Escalation` | Estado + `HumanApprover` | Escalar es una transición, no un actor |
| `MemoryCurator` | Extensión de memoria | Fuera del núcleo |

---

## 19. Permisos de rol

1. Cada rol DEBE tener permisos explícitos.
2. Cada rol DEBE tener prohibiciones explícitas.
3. Un rol NO DEBE ejecutar acciones fuera de sus permisos.
4. Los permisos DEBEN ser configurables.
5. Los permisos críticos DEBEN requerir aprobación humana.
6. Los plugins NO DEBEN otorgar permisos fuera de policy.
7. Los adapters NO DEBEN modificar permisos de rol.

### 19.1. Matriz mínima

| Rol | PUEDE escribir | NO DEBE |
|---|---|---|
| `SpecAssistant` | `spec/` | aprobar spec, tocar `src/`, tocar `orchestration/` |
| `Planner` | `orchestration/program-plan.json` | modificar `spec/`, crear ramas, abrir PR |
| `FeatureLead` | `orchestration/features/`, ramas de feature | mergear, tocar ramas protegidas, modificar `spec/` |
| `Developer` | `src/`, `tests/` dentro del scope de la task | ampliar alcance, abrir PR, mergear |
| `Reviewer` | `orchestration/reports/` | reescribir código, aprobar merge crítico |
| `HumanApprover` | aprobaciones | — |

---

## 20. Modelos y routing

**Corrección respecto de 0.0.4: los perfiles ordenaban por precio como proxy de capacidad, y la tabla de mínimos contenía valores fuera del dominio (`dynamic`, `none`) que rompían el `max()`.**

### 20.1. Ejes ortogonales

Thalos separa dos dimensiones que 0.0.4 mezclaba:

```txt
capability_tier -> qué tan capaz debe ser el modelo (ordena el routing)
cost_budget     -> cuánto se puede gastar (limita la ejecución, sección 33)
```

El routing selecciona por capacidad. El presupuesto limita por costo. Nunca al revés.

### 20.2. Perfiles de capacidad

```txt
fast
balanced
deep
```

Orden total:

```txt
fast < balanced < deep
```

### 20.3. Mapeo a modelos concretos

1. El mapeo `capability_tier -> modelo concreto` DEBE vivir en `config/models.yaml`.
2. El mapeo DEBE resolverse mediante `ModelProviderAdapter.resolve_profile`.
3. El núcleo NO DEBE conocer identificadores de modelo concretos.
4. Cambiar de proveedor NO DEBE requerir cambios en el routing.

### 20.4. Mínimo por rol

`role_minimum_tier` tiene dominio:

```txt
fast | balanced | deep | null
```

`null` significa **sin mínimo propio**: el rol se resuelve enteramente por esfuerzo y riesgo.

| Rol | `role_minimum_tier` |
|---|---|
| `Planner` | deep |
| `SpecAssistant` | deep |
| `Reviewer` | balanced |
| `FeatureLead` | deep |
| `Developer` | null |

### 20.5. Algoritmo de selección

```txt
candidates = [
  tier_by_task_effort,
  tier_by_feature_risk,
  role_minimum_tier
]

defined = [c for c in candidates if c is not null]

if defined is empty:
    tier = config.routing.default_tier
else:
    tier = max(defined)      # orden total: fast < balanced < deep

model = ModelProviderAdapter.resolve_profile(tier)
```

Reglas:

1. `max()` SOLO PUEDE aplicarse sobre valores del dominio ordenado.
2. `null` NO PUEDE participar en `max()`.
3. `config.routing.default_tier` DEBE estar definido y DEBE ser válido.
4. El routing DEBE ser determinista.
5. El routing DEBE poder sobreescribirse por configuración de proyecto.
6. El routing NO DEBE depender de plugins.
7. El routing NO DEBE consultar costo.

### 20.6. Mapeo de esfuerzo y riesgo a capacidad

| Esfuerzo | Tier |
|---|---|
| trivial | fast |
| low | fast |
| medium | balanced |
| high | deep |
| critical | deep |

| Riesgo | Tier |
|---|---|
| low | fast |
| medium | balanced |
| high | deep |
| critical | deep |

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
```

### 21.3. Niveles de riesgo

```txt
low
medium
high
critical
```

### 21.4. Factores de riesgo

```txt
auth
billing
security
migrations
public_api
ci_cd
infrastructure
breaking_change
```

### 21.5. Regla de agregación

1. El nivel de riesgo de una feature DEBE ser el máximo de los factores presentes.
2. Todo factor de la sección 21.4 presente en una feature DEBE elevar el riesgo a `high` como mínimo.
3. `breaking_change` o `security` presentes DEBEN elevar el riesgo a `critical`.
4. Riesgo `critical` DEBE requerir `HumanApprover`.

---

## 22. Ciclo de vida

**Corrección respecto de 0.0.4: 0.0.4 mezclaba estados de programa y de feature en una sola lista y no definía ninguna transición. 0.0.5 define dos máquinas separadas y la tabla completa.**

### 22.1. Máquina de programa

Estados:

```txt
INIT
PRECONDITION_CHECK
PRECONDITION_FAILED
SPEC_MISSING
SPEC_ASSIST_OFFERED
SPEC_GENERATING
SPEC_INVALID
SPEC_REVIEW
SPEC_APPROVED
PROGRAM_PLANNING
PROGRAM_READY
PROGRAM_DONE
HALTED
```

Terminales:

```txt
PROGRAM_DONE
HALTED
```

### 22.2. Máquina de feature

Estados:

```txt
FEATURE_READY
FEATURE_IN_PROGRESS
FEATURE_REVIEW
FEATURE_PR_OPEN
FEATURE_CHECKS_RUNNING
FEATURE_CHECKS_PASS
FEATURE_CHECKS_FAIL
FEATURE_FIXING
FEATURE_HUMAN_REVIEW
FEATURE_MERGING
FEATURE_MERGED
FEATURE_DONE
FEATURE_BLOCKED
FEATURE_ESCALATED
FEATURE_FAILED
FEATURE_ABANDONED
```

Terminales:

```txt
FEATURE_DONE
FEATURE_FAILED
FEATURE_ABANDONED
```

### 22.3. Gates

```txt
PRECONDITION_GATE
SPEC_SCHEMA_GATE
SPEC_GATE
PLAN_GATE
READY_GATE
DEV_GATE
REVIEW_GATE
CHECKS_GATE
POLICY_GATE
HUMAN_GATE
MERGE_GATE
POST_MERGE_GATE
```

### 22.4. Tabla de transiciones — programa

| # | Desde | Hacia | Gate | Actor | Evidencia requerida | Evento |
|---|---|---|---|---|---|---|
| P1 | INIT | PRECONDITION_CHECK | — | Orchestrator | — | `thalos.run.started` |
| P2 | PRECONDITION_CHECK | PRECONDITION_FAILED | PRECONDITION_GATE=fail | Orchestrator | `PreconditionReport` | `thalos.precondition.failed` |
| P3 | PRECONDITION_CHECK | SPEC_MISSING | PRECONDITION_GATE=pass | Orchestrator | `PreconditionReport` | `thalos.spec.missing` |
| P4 | PRECONDITION_CHECK | SPEC_INVALID | SPEC_SCHEMA_GATE=fail | Orchestrator | `PreconditionReport`, `SchemaValidationReport` | `thalos.spec.invalid` |
| P5 | PRECONDITION_CHECK | SPEC_REVIEW | SPEC_SCHEMA_GATE=pass | Orchestrator | `PreconditionReport`, `SchemaValidationReport` | `thalos.spec.validated` |
| P6 | PRECONDITION_CHECK | SPEC_APPROVED | SPEC_SCHEMA_GATE=pass + status=approved | Orchestrator | `SchemaValidationReport`, `HumanApproval` | `thalos.spec.approved` |
| P7 | PRECONDITION_FAILED | PRECONDITION_CHECK | — | HumanApprover | `HumanDecision(retry)` | `thalos.precondition.recheck` |
| P8 | PRECONDITION_FAILED | HALTED | — | HumanApprover | `HumanDecision(abort)` | `thalos.run.halted` |
| P9 | SPEC_MISSING | SPEC_ASSIST_OFFERED | — | Orchestrator | — | `thalos.spec.assist_offered` |
| P10 | SPEC_ASSIST_OFFERED | SPEC_GENERATING | HUMAN_GATE=accept | HumanApprover | `HumanDecision(accept)` | `thalos.spec.assist_requested` |
| P11 | SPEC_ASSIST_OFFERED | HALTED | HUMAN_GATE=decline | HumanApprover | `HumanDecision(decline)` | `thalos.run.halted` |
| P12 | SPEC_GENERATING | SPEC_REVIEW | SPEC_SCHEMA_GATE=pass | SpecAssistant | `SpecDraft`, `SchemaValidationReport` | `thalos.spec.draft_generated` |
| P13 | SPEC_GENERATING | SPEC_INVALID | SPEC_SCHEMA_GATE=fail | SpecAssistant | `SchemaValidationReport` | `thalos.spec.invalid` |
| P14 | SPEC_INVALID | SPEC_GENERATING | HUMAN_GATE=accept | HumanApprover | `HumanDecision(assist)` | `thalos.spec.assist_requested` |
| P15 | SPEC_INVALID | SPEC_REVIEW | SPEC_SCHEMA_GATE=pass | HumanApprover | `SchemaValidationReport` | `thalos.spec.validated` |
| P16 | SPEC_INVALID | HALTED | — | HumanApprover | `HumanDecision(abort)` | `thalos.run.halted` |
| P17 | SPEC_REVIEW | SPEC_APPROVED | HUMAN_GATE=approve | HumanApprover | `HumanApproval` | `thalos.spec.approved` |
| P18 | SPEC_REVIEW | SPEC_GENERATING | HUMAN_GATE=revise | HumanApprover | `HumanDecision(revise)` | `thalos.spec.revision_requested` |
| P19 | SPEC_REVIEW | HALTED | HUMAN_GATE=reject | HumanApprover | `HumanDecision(reject)` | `thalos.run.halted` |
| P20 | SPEC_APPROVED | PROGRAM_PLANNING | SPEC_GATE | Planner | `ApprovedSpecRef` | `thalos.program.planning_started` |
| P21 | PROGRAM_PLANNING | PROGRAM_READY | PLAN_GATE=pass | Orchestrator | `ProgramPlan`, `SchemaValidationReport` | `thalos.program.planned` |
| P22 | PROGRAM_PLANNING | PROGRAM_PLANNING | PLAN_GATE=fail, attempts<max | Planner | `ErrorRecord` | `thalos.program.planning_retried` |
| P23 | PROGRAM_PLANNING | HALTED | PLAN_GATE=fail, attempts>=max | Orchestrator | `ErrorRecord` | `thalos.escalation.triggered` |
| P24 | PROGRAM_READY | PROGRAM_DONE | — | Orchestrator | `FeatureStateSet(all terminal)` | `thalos.program.completed` |
| P25 | PROGRAM_READY | HALTED | — | HumanApprover | `HumanDecision(abort)` | `thalos.run.halted` |

### 22.5. Tabla de transiciones — feature

| # | Desde | Hacia | Gate | Actor | Evidencia requerida | Evento |
|---|---|---|---|---|---|---|
| F1 | — | FEATURE_READY | READY_GATE | Orchestrator | `ProgramPlanEntry`, `DependencySet(satisfied)` | `thalos.feature.ready` |
| F2 | FEATURE_READY | FEATURE_IN_PROGRESS | READY_GATE + lease otorgado | FeatureLead | `LockLease`, `IssueRef`, `BranchRef` | `thalos.feature.started` |
| F3 | FEATURE_READY | FEATURE_BLOCKED | READY_GATE=fail | Orchestrator | `GateResult(reasons)` | `thalos.feature.blocked` |
| F4 | FEATURE_IN_PROGRESS | FEATURE_REVIEW | DEV_GATE=pass | Developer | `TaskResultSet`, `LocalTestReport`, `CommitRef` | `thalos.feature.dev_complete` |
| F5 | FEATURE_IN_PROGRESS | FEATURE_BLOCKED | DEV_GATE=fail | Orchestrator | `ErrorRecord` | `thalos.feature.blocked` |
| F6 | FEATURE_REVIEW | FEATURE_IN_PROGRESS | REVIEW_GATE=changes | Reviewer | `Review(blockers>0)` | `thalos.review.changes_requested` |
| F7 | FEATURE_REVIEW | FEATURE_PR_OPEN | REVIEW_GATE=pass | FeatureLead | `Review(blockers=0)`, `PullRequestRef` | `thalos.feature.pr_opened` |
| F8 | FEATURE_PR_OPEN | FEATURE_CHECKS_RUNNING | — | Orchestrator | `CheckRunSet(pending)` | `thalos.feature.checks_started` |
| F9 | FEATURE_CHECKS_RUNNING | FEATURE_CHECKS_PASS | CHECKS_GATE=pass | Orchestrator | `CheckRunSet(all pass)` | `thalos.feature.checks_passed` |
| F10 | FEATURE_CHECKS_RUNNING | FEATURE_CHECKS_FAIL | CHECKS_GATE=fail | Orchestrator | `CheckRunSet(>=1 fail)` | `thalos.feature.checks_failed` |
| F11 | FEATURE_CHECKS_FAIL | FEATURE_FIXING | — | FeatureLead | `IssueList` | `thalos.feature.fixing` |
| F12 | FEATURE_CHECKS_FAIL | FEATURE_ESCALATED | attempts>=max | Orchestrator | `ErrorRecord(attempts)` | `thalos.escalation.triggered` |
| F13 | FEATURE_FIXING | FEATURE_CHECKS_RUNNING | DEV_GATE=pass | Developer | `TaskResultSet`, `CommitRef` | `thalos.feature.checks_started` |
| F14 | FEATURE_CHECKS_PASS | FEATURE_HUMAN_REVIEW | POLICY_GATE=needs_human | Orchestrator | `PolicyDecision(human_required)` | `thalos.feature.human_requested` |
| F15 | FEATURE_CHECKS_PASS | FEATURE_MERGING | POLICY_GATE=pass | Orchestrator | `PolicyDecision(auto_allowed)` | `thalos.feature.merge_requested` |
| F16 | FEATURE_HUMAN_REVIEW | FEATURE_MERGING | HUMAN_GATE=approve | HumanApprover | `HumanApproval` | `thalos.feature.merge_requested` |
| F17 | FEATURE_HUMAN_REVIEW | FEATURE_IN_PROGRESS | HUMAN_GATE=changes | HumanApprover | `HumanDecision(changes)` | `thalos.review.changes_requested` |
| F18 | FEATURE_HUMAN_REVIEW | FEATURE_ABANDONED | HUMAN_GATE=reject | HumanApprover | `HumanDecision(reject)` | `thalos.feature.abandoned` |
| F19 | FEATURE_MERGING | FEATURE_MERGED | MERGE_GATE=pass | MergeGate | `CheckRunSet`, `PolicyDecision`, `MergeResult` | `thalos.feature.merged` |
| F20 | FEATURE_MERGING | FEATURE_BLOCKED | MERGE_GATE=fail | MergeGate | `MergeGateReport` | `thalos.feature.blocked` |
| F21 | FEATURE_MERGED | FEATURE_DONE | POST_MERGE_GATE=pass | Orchestrator | `PostMergeReport`, `LockRelease` | `thalos.feature.done` |
| F22 | FEATURE_MERGED | FEATURE_ESCALATED | POST_MERGE_GATE=fail | Orchestrator | `PostMergeReport(failures)` | `thalos.escalation.triggered` |
| F23 | FEATURE_BLOCKED | FEATURE_IN_PROGRESS | — | FeatureLead | `BlockerResolution` | `thalos.feature.unblocked` |
| F24 | FEATURE_BLOCKED | FEATURE_ESCALATED | timeout o attempts>=max | Orchestrator | `ErrorRecord` | `thalos.escalation.triggered` |
| F25 | FEATURE_ESCALATED | FEATURE_IN_PROGRESS | HUMAN_GATE=resume | HumanApprover | `HumanDecision(resume)` | `thalos.feature.unblocked` |
| F26 | FEATURE_ESCALATED | FEATURE_FAILED | HUMAN_GATE=abort | HumanApprover | `HumanDecision(abort)` | `thalos.feature.failed` |
| F27 | cualquier no terminal | FEATURE_ABANDONED | HUMAN_GATE=abandon | HumanApprover | `HumanDecision(abandon)`, `LockRelease` | `thalos.feature.abandoned` |

### 22.6. Reglas de transición

1. Una transición DEBE existir en la tabla 22.4 o 22.5 para ser permitida.
2. Toda transición no listada DEBE rechazarse y emitir `thalos.transition.rejected`.
3. Toda transición DEBE presentar la evidencia requerida antes de evaluar el gate.
4. Si falta evidencia, el gate DEBE resolver `fail` con `missing_evidence` poblado.
5. Toda transición DEBE emitir exactamente un evento de estado.
6. Toda transición DEBE registrar el `GateResult` que la autorizó.
7. Toda transición DEBE poder reconstruirse desde el event log.
8. Al alcanzar un estado terminal de feature, el `LockManager` DEBE liberar todos los leases de esa feature.
9. Los estados terminales NO DEBEN tener transiciones de salida, excepto reapertura explícita por `HumanApprover` que DEBE crear una nueva feature derivada, no reabrir la anterior.

---

## 23. Evidencia

**Corrección respecto de 0.0.4: "evidencia" se usaba normativamente unas diez veces y nunca se definía.**

### 23.1. Definición

Una `Evidence` es un artefacto tipado, persistido e inmutable que justifica una transición de estado.

### 23.2. Envoltorio común

Toda evidencia DEBE cumplir:

```json
{
  "id": "ev-01H...",
  "kind": "CheckRunSet",
  "schema_version": 1,
  "run_id": "r-2026-07-30-001",
  "feature_id": "F001",
  "produced_by": "adapter:thalos.adapter.github",
  "produced_at": "2026-07-30T12:00:00Z",
  "artifact_refs": ["orchestration/reports/F001/checks.json"],
  "digest": "sha256:...",
  "verifiable": true,
  "payload": {}
}
```

### 23.3. Reglas

1. Toda evidencia DEBE persistirse en `orchestration/evidence/`.
2. Toda evidencia DEBE ser inmutable una vez escrita.
3. Toda evidencia DEBE tener `digest` que cubra `payload` y `artifact_refs`.
4. Toda evidencia con `verifiable: true` DEBE poder revalidarse consultando la fuente original.
5. Una evidencia con `verifiable: false` NO PUEDE satisfacer un gate crítico.
6. La evidencia producida por un agente DEBE marcarse `verifiable: false` salvo que incluya salida de una herramienta determinista.
7. La evidencia NO DEBE contener secretos.
8. La evidencia DEBE referenciar artefactos grandes, no embeberlos.

### 23.4. Catálogo de tipos

| `kind` | Producido por | `verifiable` | Contenido |
|---|---|---|---|
| `PreconditionReport` | core | true | resultado por precondition |
| `SchemaValidationReport` | core | true | violaciones de schema |
| `HumanDecision` | HumanApprover | true | decisión, actor, timestamp |
| `HumanApproval` | HumanApprover | true | aprobación firmada, scope |
| `SpecDraft` | SpecAssistant | false | ruta y digest del draft |
| `ApprovedSpecRef` | core | true | ruta, digest, status |
| `ProgramPlan` | Planner | false | plan completo |
| `ProgramPlanEntry` | core | true | entrada de feature |
| `DependencySet` | core | true | dependencias y su estado |
| `LockLease` | LockManager | true | lease otorgado |
| `LockRelease` | LockManager | true | lease liberado |
| `IssueRef` | CoordinationAdapter | true | id, url |
| `BranchRef` | CoordinationAdapter | true | nombre, sha |
| `CommitRef` | CoordinationAdapter | true | sha, mensaje |
| `PullRequestRef` | CoordinationAdapter | true | número, url, mergeable |
| `TaskResultSet` | Developer | false | tasks completadas, archivos |
| `LocalTestReport` | ExecutionAdapter | true | comando, exit code, salida |
| `Review` | Reviewer | false | findings, blockers |
| `IssueList` | core | true | issues derivados de checks |
| `CheckRunSet` | CIAdapter | true | checks, estado, urls |
| `PolicyDecision` | core | true | regla aplicada, resultado |
| `MergeGateReport` | MergeGate | true | condiciones y resultados |
| `MergeResult` | CoordinationAdapter | true | sha de merge, método |
| `PostMergeReport` | core | true | verificaciones post-merge |
| `BlockerResolution` | FeatureLead | false | qué se desbloqueó |
| `ErrorRecord` | core | true | clase, intentos, causa |
| `GateResult` | GateEvaluator | true | ver sección 24 |
| `FeatureStateSet` | core | true | estado de todas las features |

---

## 24. Contrato de gates

**Corrección respecto de 0.0.4: existían 12 gates listados y ningún contrato.**

### 24.1. Entrada

```json
{
  "gate": "MERGE_GATE",
  "run_id": "r-2026-07-30-001",
  "feature_id": "F001",
  "from_state": "FEATURE_MERGING",
  "to_state": "FEATURE_MERGED",
  "evidence": ["ev-...", "ev-..."],
  "policy_snapshot_digest": "sha256:...",
  "config_snapshot_digest": "sha256:..."
}
```

### 24.2. Salida

```json
{
  "gate": "MERGE_GATE",
  "decision": "pass",
  "reasons": [
    { "code": "CHECKS_GREEN", "status": "pass", "detail": "12/12" },
    { "code": "MERGEABLE", "status": "pass", "detail": "clean" },
    { "code": "POLICY_APPROVAL", "status": "pass", "detail": "risk=medium" },
    { "code": "NO_CONFLICTING_LEASE", "status": "pass", "detail": "-" }
  ],
  "missing_evidence": [],
  "evaluated_at": "2026-07-30T12:05:00Z",
  "evaluator_version": "0.0.6"
}
```

### 24.3. Dominio de decisión

```txt
pass
fail
needs_human
```

### 24.4. Reglas

1. Un `GateEvaluator` DEBE ser una función pura de `(evidencia, policy, config)`.
2. Un `GateEvaluator` NO DEBE realizar efectos externos.
3. Un `GateEvaluator` NO DEBE invocar modelos.
4. Todo `fail` DEBE poblar `reasons` con al menos un item en estado `fail`.
5. Toda evidencia faltante DEBE aparecer en `missing_evidence`.
6. `needs_human` DEBE producir una transición hacia un estado de espera humana, nunca hacia un estado de avance.
7. Todo `GateResult` DEBE persistirse como evidencia.
8. Un gate DEBE ser determinista: la misma entrada DEBE producir la misma salida.
9. Los plugins NO DEBEN implementar gates del núcleo.
10. Los `GateEvaluator` personalizados DEBEN declararse en el extension registry y NO DEBEN reemplazar `MERGE_GATE`, `POLICY_GATE` ni `HUMAN_GATE`.

---

## 25. Comunicación

**Corrección respecto de 0.0.6: esta sección estaba especificada entera y no la implementaba nadie.** Tipos, estados, hilos, canales, expiración y límite de payload, más su schema, y lo único que la mencionaba en el código era el `init` creando `orchestration/messages/` vacío. La consecuencia se vio corriendo: un agente contestó *"no puedo seguir, confirmame si reiniciaron el workspace"* y Thalos lo descartó porque esperaba un archivo con otro formato. El motivo existía, era bueno, y no llegaba a nadie.

### 25.1. Principios

1. Toda comunicación entre roles DEBE ser estructurada. **Lo estructurado es el sobre —quién, a quién, sobre qué, en qué hilo— y lo pone Thalos. El cuerpo puede ser cualquier cosa, incluido ruido.**
1.a. Un rol NO DEBE quedar obligado a conocer un formato para ser escuchado. Exigirle la estructura al emisor es lo que rompe la comunicación: si contesta distinto, se pierde.
1.b. Una respuesta que no se puede interpretar DEBE persistirse igual y entregarse a quien pueda actuar sobre ella. Un mensaje ilegible entregado vale más que uno perfecto que nunca se escribió.
1.c. Un paso que termina sin lo que esperaba DEBE registrar lo que sí recibió, y DEBE decir dónde leerlo y cómo responder.
1.d. Toda respuesta DEBE entregarse al destinatario, no solo escribirse. Una respuesta persistida que nadie lee corta la comunicación en el último tramo, que es el que importa.
2. Toda comunicación DEBE persistirse.
3. Toda solicitud DEBE poder recibir respuesta.
4. Toda respuesta DEBE referenciar la solicitud original.
5. El contexto extenso DEBE referenciarse por artefacto.
6. Los mensajes NO DEBEN transportar contexto extenso embebido.
7. Toda pregunta sin respuesta DEBE expirar o escalar.
8. Toda comunicación DEBE poder reconstruirse desde eventos.
9. El transporte de mensajes DEBE ser intercambiable.
10. El protocolo de mensajes NO DEBE depender del plugin.

### 25.2. Canales

```txt
durable:      repo_files
operational:  adapter_specific
coordination: coordination_adapter
```

### 25.3. Tipos de mensaje

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
```

### 25.4. Estados de mensaje

```txt
OPEN
ACKED
ANSWERED
CLOSED
EXPIRED
ESCALATED
```

### 25.5. Reglas de eficiencia

**Corrección respecto de 0.0.4: el límite de payload era "RECOMENDADO" sin regla de enforcement.**

1. `payload` DEBE ser menor o igual a 16 KB.
2. Si `payload` excede 16 KB, el emisor DEBE persistir el contenido como artefacto y reemplazarlo por `artifact_refs`.
3. Si el emisor no puede reducir el payload, el mensaje DEBE rechazarse con error `VALIDATION`.
4. Cada mensaje DEBE tener `id`.
5. Cada mensaje DEBE tener `thread_id`.
6. Cada mensaje DEBE tener `created_at`.
7. Cada mensaje PUEDE tener `expires_at`.
8. Si expira sin respuesta, el mensaje DEBE marcar `EXPIRED`.
9. Si `EXPIRED` y el mensaje es crítico, DEBE escalar.

---

## 26. Artefactos y referencias

1. Todo artefacto DEBE ser versionable o referenciable.
2. Toda referencia DEBE usar ruta relativa o URI estable.
3. Toda referencia crítica DEBE poder validarse.
4. Los artefactos de entrada DEBEN existir antes de ejecutar la tarea.
5. Los artefactos de salida DEBEN declararse explícitamente.
6. Todo artefacto referenciado por evidencia DEBE tener digest.
7. Los plugins PUEDEN mostrar artefactos.
8. Los plugins NO DEBEN ser la única copia de un artefacto.

---

## 27. Preconditions

### 27.1. Preconditions obligatorias

1. Git instalado.
2. Repositorio git existente.
3. Identidad git configurada.
4. Autenticación git válida.
5. Permiso de push verificado.
6. Rama por defecto existente.
7. Spec presence verificada.
8. Spec manifest válido si el spec existe.
9. Core version compatible.
10. Runtime schema version compatible.
11. Extension registry válido.
12. Adapters habilitados responden health check.
13. Exactamente una implementación habilitada por cada capacidad REQUERIDA (sección 37.4.2).
14. Binarios externos de los adapters habilitados resueltos y dentro del rango de versión declarado.
15. Modo de operación declarado y coherente con los adapters habilitados.

### 27.2. Comprobación de cuenta git

Thalos DEBE verificar como mínimo:

```txt
git --version
git rev-parse --is-inside-work-tree
git config user.name
git config user.email
git remote get-url origin
```

Si se usa GitHub, Thalos DEBE verificar:

```txt
gh auth status
```

### 27.3. Fallo de precondition

1. Si una precondition requerida falla, Thalos DEBE transicionar a `PRECONDITION_FAILED`.
2. Thalos DEBE producir un `PreconditionReport` con el resultado de cada verificación.
3. Thalos DEBE mostrar el requisito faltante.
4. Thalos DEBE sugerir comando de remediación.
5. Thalos NO DEBE continuar en modo silencioso.
6. Thalos PUEDE continuar en modo dry-run si la falla es externa y no crítica, y DEBE declararlo explícitamente en el reporte.
7. Si falla el health check de un adapter OPCIONAL, Thalos PUEDE continuar sin esa capacidad.

---

## 28. Spec intake

1. Thalos DEBE leer `spec/manifest.yaml`.
2. Thalos DEBE validar el spec contra `spec-manifest.schema.json`.
3. Thalos DEBE producir `SchemaValidationReport` en toda validación.
4. Thalos NO DEBE planificar si el spec no está `approved`.
5. Thalos PUEDE asistir la generación del spec en estado `draft`.
6. Thalos DEBE requerir aprobación humana para pasar a `approved`.
7. El spec intake DEBE poder ejecutarse sin plugins.
8. El digest del spec aprobado DEBE registrarse en `ApprovedSpecRef`.
9. Si el spec cambia después de `SPEC_APPROVED`, Thalos DEBE detectarlo por digest y DEBE exigir re-aprobación.

---

## 29. Planificación de programa

1. `Planner` SOLO PUEDE ejecutarse tras `SPEC_APPROVED`.
2. `Planner` DEBE generar `orchestration/program-plan.json`.
3. El plan DEBE validar contra `program-plan.schema.json`.
4. `Planner` NO DEBE modificar `spec/`.
5. `Planner` DEBE identificar dependencias entre features.
6. `Planner` DEBE clasificar riesgo y esfuerzo por feature.
7. `Planner` DEBE indicar el `capability_tier` recomendado.
8. `Planner` DEBE indicar si se requiere aprobación humana.
9. El grafo de dependencias DEBE ser acíclico; un ciclo DEBE fallar `PLAN_GATE`.
10. `PLAN_GATE` DEBE reintentarse como máximo `config.reliability.max_plan_attempts` veces.

---

## 30. Ejecución de feature

### 30.1. FeatureLead

1. DEBE adquirir lease antes de iniciar.
2. DEBE crear issue.
3. DEBE crear rama.
4. DEBE crear worktree o entorno aislado.
5. DEBE descomponer en tasks.
6. DEBE delegar tasks con mensaje estructurado.
7. DEBE mantener `feature-state.json`.
8. DEBE abrir PR cuando `REVIEW_GATE` pase.
9. NO DEBE mergear.
10. NO DEBE modificar ramas protegidas.
11. DEBE usar adapters para toda operación externa.

### 30.2. Developer

1. DEBE implementar solo las tasks asignadas.
2. NO DEBE ampliar alcance.
3. DEBE ejecutar pruebas locales mediante `ExecutionAdapter`.
4. DEBE responder con `TaskResultSet` y `LocalTestReport`.
5. Cuando actúa sobre issues de checks fallidos, DEBE limitarse al `IssueList` recibido.

### 30.3. Reviewer

1. DEBE revisar contra el spec aprobado.
2. DEBE generar `Review` estructurada.
3. NO DEBE reescribir código directamente.
4. DEBE marcar blocker si faltan pruebas para requisitos con `acceptance_criteria`.
5. DEBE marcar blocker si el diff excede el scope declarado de las tasks.

### 30.4. Verificación de pruebas

1. El pase de pruebas DEBE determinarse por `CheckRunSet` del `CIAdapter`.
2. Ningún rol agente PUEDE declarar `pass` sin `CheckRunSet` correspondiente.
3. `LocalTestReport` es evidencia de avance, NO es evidencia de pase.

---

## 31. Merge governance

`MergeGate` es un componente de núcleo, no un rol.

1. Merge DEBE requerir `CheckRunSet` con todos los checks en pass.
2. Merge DEBE requerir estado mergeable.
3. Merge DEBE respetar política de aprobación.
4. Merge DEBE verificar que no exista lease en conflicto.
5. Merge DEBE producir `MergeGateReport` con una entrada por condición.
6. Merge crítico DEBE requerir `HumanApproval`.
7. Auto-merge en v0.0.6 DEBE estar deshabilitado por defecto.
8. `MergeGate` DEBE invocar `CoordinationAdapter.merge_pr` con idempotency key.
9. Los plugins NO DEBEN ejecutar merge.
10. Merge DEBE poder simularse en dry-run.
11. Ninguna extensión PUEDE autorizar merge.

---

## 32. Locks y concurrencia

**Corrección respecto de 0.0.4: los locks no tenían expiración, lo que producía deadlock permanente si el proceso propietario moría.**

### 32.1. Lease

Un lock es un **lease**: una concesión con expiración.

```json
{
  "lease_id": "lk-01H...",
  "resource": "branch:main",
  "owner_feature": "F001",
  "owner_run": "r-2026-07-30-001",
  "reason": "merge in progress",
  "acquired_at": "2026-07-30T12:00:00Z",
  "expires_at": "2026-07-30T12:05:00Z",
  "last_heartbeat_at": "2026-07-30T12:03:00Z",
  "ttl_seconds": 300,
  "generation": 7
}
```

### 32.2. Reglas

1. Todo recurso compartido crítico PUEDE requerir lease.
2. Todo lease DEBE tener `owner_feature`, `reason`, `ttl_seconds` y `expires_at`.
3. El propietario DEBE emitir heartbeat con intervalo menor o igual a `ttl_seconds / 3`.
4. Un heartbeat DEBE extender `expires_at`.
5. Si `now > expires_at`, el `LockManager` DEBE considerar el lease expirado.
6. Al expirar, el `LockManager` DEBE incrementar `generation` y emitir `thalos.lock.expired`.
7. El lease DEBE liberarse al alcanzar un estado terminal de feature.
8. Los leases DEBEN persistirse en `orchestration/locks.json`.

### 32.3. Fencing token

1. `generation` ES el fencing token.
2. Toda operación externa protegida por lease DEBE incluir la `generation` vigente.
3. Un adapter DEBE rechazar una operación cuya `generation` sea menor que la vigente.
4. Este mecanismo previene que un propietario zombi complete una operación tras perder el lease.

### 32.4. Concurrencia

1. Si dos features requieren el mismo recurso, Thalos DEBE serializar.
2. Si la serialización excede `config.reliability.lock_wait_timeout`, Thalos DEBE escalar.
3. v0.0.6 RECOMIENDA `max_parallel_features = 1`.
4. Los plugins PUEDEN visualizar leases.
5. Los plugins NO DEBEN liberar leases.

---

## 33. Presupuestos

1. Toda ejecución PUEDE tener presupuesto.
2. Todo rol agente PUEDE tener límite de costo.
3. Toda feature PUEDE tener límite de iteraciones.
4. Si se excede el presupuesto, Thalos DEBE pausar o escalar.
5. v0.0.6 RECOMIENDA límites estrictos.
6. Todo consumo de presupuesto DEBE registrarse como evento.
7. El presupuesto NO DEBE influir en el routing por capacidad (sección 20.1); DEBE limitar la ejecución.
8. Si el presupuesto impide usar el tier requerido, Thalos DEBE escalar en lugar de degradar silenciosamente el modelo.
9. Los plugins PUEDEN mostrar presupuesto.
10. Los plugins NO DEBEN omitir límites.

---

## 34. Observabilidad

1. Todo cambio de estado DEBE registrar evento.
2. Todo mensaje DEBE poder consultarse.
3. Toda feature DEBE exponer estado actual.
4. Todo PR DEBE exponer checks.
5. Todo fallo DEBE registrar `ErrorRecord`.
6. Todo `GateResult` DEBE persistirse.
7. Thalos DEBE permitir reconstruir el historial completo desde el event log.
8. Thalos DEBE exponer consumo de tokens y costo por rol y por feature.
9. Los plugins PUEDEN proveer vistas.
10. La observabilidad del núcleo NO DEBE depender de plugins.

---

## 35. Fiabilidad: timeouts, reintentos y backoff

**Corrección respecto de 0.0.4: existía "tras 3 fallos escalar" sin clases de error, sin timeouts y sin backoff.**

### 35.1. Clases de error

Todo error DEBE clasificarse en exactamente una clase:

| Clase | Reintentable | Descripción |
|---|---|---|
| `TRANSIENT` | sí | fallo temporal de red o servicio |
| `TIMEOUT` | sí | la operación excedió su plazo |
| `RATE_LIMITED` | sí, con espera | límite de tasa del proveedor |
| `CONFLICT` | sí, tras refrescar estado | estado remoto cambió |
| `AUTH` | no | credenciales inválidas o insuficientes |
| `PRECONDITION` | no | condición previa no cumplida |
| `VALIDATION` | no | entrada inválida |
| `INTERNAL` | no | defecto del propio Thalos |

### 35.2. Reglas

1. Todo error DEBE clasificarse antes de decidir reintento.
2. Solo las clases marcadas reintentables PUEDEN reintentarse.
3. Un error no reintentable DEBE escalar inmediatamente.
4. Todo reintento DEBE usar backoff exponencial con jitter.
5. `RATE_LIMITED` DEBE respetar el `retry_after` del proveedor si existe.
6. Todo reintento DEBE reutilizar la misma idempotency key.
7. Al agotar `max_attempts`, Thalos DEBE escalar y registrar `ErrorRecord` con el historial de intentos.
8. Thalos NO DEBE ocultar errores.
9. Los adapters DEBEN reportar errores estructurados con clase.
10. Los plugins DEBEN mostrar errores sin mutar estado.

### 35.3. Configuración por defecto

```yaml
version: 1

reliability:
  defaults:
    timeout_seconds: 60
    max_attempts: 3
    backoff:
      strategy: exponential
      base_ms: 500
      max_ms: 30000
      jitter: full

  operations:
    model_invoke:
      timeout_seconds: 300
      max_attempts: 2
    ci_poll:
      timeout_seconds: 30
      max_attempts: 60
      backoff:
        strategy: fixed
        base_ms: 10000
    coordination_write:
      timeout_seconds: 45
      max_attempts: 5
    merge:
      timeout_seconds: 120
      max_attempts: 1

  lock_wait_timeout_seconds: 900
  max_plan_attempts: 3
  max_fix_attempts: 3
  escalate_after_consecutive_failures: 3
```

---

## 36. Seguridad

1. Los secrets NO DEBEN escribirse en prompts.
2. Los secrets NO DEBEN versionarse.
3. Los tokens DEBEN tener mínimo privilegio.
4. Los logs NO DEBEN exponer secrets.
5. La aprobación humana DEBE exigirse en rutas críticas.
6. Thalos DEBE respetar branch protection.
7. Los plugins NO DEBEN almacenar secrets en claro.
8. Los adapters DEBEN soportar credenciales externas.
9. Las extensiones DEBEN declarar permisos sensibles.
10. La evidencia NO DEBE contener secrets.
11. Thalos DEBE aplicar detección de secrets antes de persistir cualquier artefacto derivado de salida de modelo.
12. La detección de secrets DEBE ser **fail-closed**: ante resultado incierto, Thalos NO DEBE persistir y DEBE escalar.
13. Thalos DEBE redactar y registrar el hecho de la redacción, nunca el valor redactado.

---

## 37. Extensibilidad

### 37.1. Principio de desacople

1. El core DEBE definir puertos.
2. Los adapters DEBEN implementar puertos.
3. Los plugins DEBEN consumir la CLI/API del core.
4. Los plugins NO DEBEN acceder directamente a estado interno no expuesto.
5. El core NO DEBE depender de implementaciones concretas.
6. Thalos DEBE poder reemplazar adapters sin cambiar el core.
7. Thalos DEBE poder operar sin plugins.
8. Thalos DEBE poder operar solo con el adapter dry-run.
9. Thalos DEBE poder operar sin ninguna extensión opcional.

### 37.2. Extension points

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
MemoryAdapter        (definido en thalos-memory-0.0.1.md)
```

### 37.3. Reglas de extensión

1. Toda extensión DEBE declarar versión.
2. Toda extensión DEBE declarar compatibilidad con el core.
3. Toda extensión DEBE declarar permisos.
4. Toda extensión DEBE poder habilitarse o deshabilitarse.
5. Toda extensión DEBE fallar de forma controlada.
6. Ninguna extensión DEBE romper el aislamiento de `spec/`.
7. Ninguna extensión DEBE saltarse policy.
8. Ninguna extensión DEBE escribir en `schemas/` en runtime.
9. Ninguna extensión DEBE modificar `system/` en runtime.
10. Ninguna extensión DEBE aprobar gates.
11. Ninguna extensión DEBE alterar estado normativo.
12. Toda extensión DEBE ser auditable.

---

### 37.4. Capacidades requeridas e implementaciones

**Novedad de 0.0.6.** La versión 0.0.5 marcaba adapters concretos como "opcionales" sin distinguir entre la capacidad y quién la implementa. Eso era arquitectónicamente correcto y operacionalmente engañoso: `thalos-adapter-herdr` es reemplazable, pero la capacidad que implementa no es prescindible.

#### 37.4.1. Definiciones

```txt
Capacidad     -> un extension point que el sistema necesita para funcionar
Implementación-> un adapter concreto que satisface esa capacidad
```

Una capacidad ES **REQUERIDA** si el sistema no puede ejecutar trabajo real sin alguna implementación de ella.

Una capacidad ES **OPCIONAL** si el sistema cumple todos sus criterios de aceptación sin ella.

#### 37.4.2. Clasificación

| Extension point | Capacidad | Implementación de referencia | Satisfacible por dry-run |
|---|---|---|---|
| `FileSystemAdapter` | REQUERIDA | `thalos-adapter-filesystem` | no |
| `ModelProviderAdapter` | REQUERIDA | `thalos-adapter-model` | no |
| `ExecutionAdapter` | REQUERIDA | `thalos-adapter-herdr` | solo simulación |
| `CoordinationAdapter` | REQUERIDA | `thalos-adapter-github` | sí |
| `CIAdapter` | REQUERIDA | `thalos-adapter-ci` | sí |
| `MessageTransport` | REQUERIDA | incluida en el núcleo | n/a |
| `StateStore` | REQUERIDA | incluida en el núcleo | n/a |
| `EventBus` | REQUERIDA | incluida en el núcleo | n/a |
| `GateEvaluator` | REQUERIDA | incluida en el núcleo | n/a |
| `RoutingStrategy` | OPCIONAL | incluida en el núcleo | n/a |
| `RoleRegistry` | OPCIONAL | incluida en el núcleo | n/a |
| `Validator` | OPCIONAL | — | n/a |
| `Reporter` | OPCIONAL | — | n/a |
| `Plugin` | OPCIONAL | `thalos-plugin-herdr` | n/a |
| `MemoryAdapter` | OPCIONAL | `thalos-adapter-engram` | n/a |

#### 37.4.3. Reglas

1. Toda capacidad REQUERIDA DEBE tener exactamente una implementación habilitada.
2. Cero implementaciones de una capacidad REQUERIDA DEBE fallar en `PRECONDITION_GATE`.
3. Dos o más implementaciones de la misma capacidad DEBEN fallar en `PRECONDITION_GATE` por ambigüedad.
4. Una capacidad OPCIONAL PUEDE tener cero implementaciones.
5. El núcleo NO DEBE nombrar implementaciones concretas fuera del extension registry y de la configuración.
6. Toda implementación de referencia DEBE ser reemplazable sin modificar el núcleo.
7. La ausencia de una capacidad OPCIONAL NO DEBE afectar ningún criterio de aceptación del núcleo.

#### 37.4.4. Modos de operación

| Modo | ExecutionAdapter | CoordinationAdapter | CIAdapter | Uso |
|---|---|---|---|---|
| `dry-run-only` | dryrun | dryrun | dryrun | validar el sistema, tests del propio Thalos |
| `partial` | productivo | dryrun | dryrun | ejecutar agentes sin tocar el repositorio remoto |
| `production` | productivo | productivo | productivo | ejecución real |

Reglas:

1. `dry-run-only` DEBE poder ejecutarse sin ninguna herramienta externa instalada.
2. `dry-run-only` NO PUEDE producir evidencia con `verifiable: true`.
3. `dry-run-only` NO PUEDE alcanzar `FEATURE_MERGED`.
4. El modo DEBE declararse en `config/system.yaml` y DEBE registrarse en todo `GateResult`.
5. Un cambio de modo DEBE emitir `thalos.run.mode_changed`.

#### 37.4.5. Resolución de binarios externos

Cuando una implementación depende de un binario externo, la resolución DEBE seguir esta cascada:

```txt
1. variable de entorno específica    (p. ej. THALOS_HERDR_BIN)
2. .thalos/bin/<binario>
3. PATH del sistema
```

Reglas:

1. La primera coincidencia gana.
2. El adapter DEBE verificar la versión del binario resuelto contra su rango declarado.
3. Una versión fuera de rango DEBE fallar en `PRECONDITION_GATE`.
4. Thalos NO DEBE instalar binarios de terceros de forma automática.
5. Thalos DEBE mostrar el comando de instalación exacto cuando el binario falte.
6. Thalos DEBE reportar la ruta resuelta en `thalos doctor`.

**Nota sobre vendoring:** el paso 2 existe para casos de pinneo deliberado. NO ES el mecanismo recomendado para herramientas que gestionan estado a nivel de máquina o de sesión de terminal, porque múltiples copias compiten por el mismo recurso. Las herramientas de esa clase DEBEN instalarse a nivel de sistema.

---

## 38. Adapters

### 38.1. Principios

1. El core NO DEBE depender directamente de vendors.
2. Toda integración externa DEBE implementarse como adapter.
3. Todo adapter DEBE devolver resultados estructurados.
4. Todo adapter DEBE exponer health check.
5. Todo adapter DEBE soportar dry-run.
6. Todo adapter DEBE declarar capacidades.
7. Todo adapter DEBE declarar versión y API soportada.
8. Todo adapter DEBE poder ser reemplazado.
9. Todo adapter DEBE clasificar sus errores según la sección 35.1.

### 38.2. Idempotencia obligatoria

**Corrección respecto de 0.0.4: no se exigía idempotencia, y el modelo de reintentos permitía crear PRs e issues duplicados.**

1. Toda operación de adapter que mute estado externo DEBE aceptar `idempotency_key`.
2. Toda operación mutante DEBE ser segura de reintentar con la misma key.
3. Toda operación mutante DEBE devolver:

```json
{
  "status": "created | already_exists",
  "resource_ref": { "id": "...", "url": "..." },
  "idempotency_key": "..."
}
```

4. La key DEBE derivarse de forma determinista:

```txt
idempotency_key = sha256(
  run_id + ":" +
  feature_id + ":" +
  operation + ":" +
  canonical_json(semantic_args)
)
```

5. `semantic_args` DEBE excluir timestamps y valores no deterministas.
6. Si el backend externo no soporta idempotencia nativa, el adapter DEBE implementar reconciliación: buscar el recurso por key antes de crear.
7. Un adapter que no pueda garantizar idempotencia en una operación DEBE declararla `at_most_once` en su manifiesto, y el core NO DEBE reintentarla automáticamente.
8. `semantic_args` DEBE identificar la **instancia** del recurso sobre el que se actúa, no solo su nombre. Si el nombre se reutiliza entre instancias, DEBE incluirse un identificador de instancia —una generación— que sea constante entre reintentos de la misma operación y distinto entre instancias.

**Corrección respecto de 0.0.7: la regla 5 decía qué excluir y ninguna decía qué incluir.** La consecuencia se vio corriendo. Thalos reutiliza a propósito el nombre del agente entre despachos —es lo que le permite reconciliar— y el encargo que arma `feature work` es determinista para una feature y una task dadas. Con eso, un **redespacho producía la misma key que el despacho anterior**: el ledger contestaba `already_exists` y el prompt no se enviaba nunca. El agente nuevo no recibía su encargo, jamás. Antes del ACK observado de la sección 7 de la mensajería, el paso reportaba *"trabajo entregado"* y esperaba el presupuesto completo por un entregable que no podía existir.

Una generación no es un timestamp ni un valor no determinista, así que no contradice la regla 5: es constante mientras la instancia lo sea. Es el mismo mecanismo que la sección 32.3 usa para los leases.

### 38.3. Adapters recomendados

```txt
thalos-adapter-filesystem
thalos-adapter-github
thalos-adapter-herdr
thalos-adapter-ci
thalos-adapter-model
thalos-adapter-dryrun
```

### 38.4. Capacidades esperadas

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
resolve_profile      (capability_tier -> modelo concreto)
invoke_model
estimate_cost
report_usage
```

#### ExecutionAdapter

```txt
create_workspace
create_session
start_agent
prompt_agent
wait_agent
read_agent
run_command
report_metadata
```

#### CoordinationAdapter

Todas las operaciones marcadas `[M]` son mutantes y REQUIEREN idempotency key.

```txt
create_issue        [M]
create_branch       [M]
open_pr             [M]
get_pr_checks
request_review      [M]
merge_pr            [M]
```

#### CIAdapter

```txt
run_checks          [M]
get_check_status
publish_report      [M]
```

#### DryRunAdapter

```txt
simulate_action
log_intended_action
return_mock_result
```

### 38.5. Herdr adapter

**Corrección respecto de 0.0.5: este adapter estaba marcado "opcional", lo que confundía la reemplazabilidad de la implementación con la prescindibilidad de la capacidad.**

`thalos-adapter-herdr` ES la **implementación de referencia** de `ExecutionAdapter`, que es una capacidad **REQUERIDA** según la sección 37.4.2.

Consecuencias normativas:

1. Toda instalación productiva DEBE tener exactamente un `ExecutionAdapter` habilitado.
2. `thalos-adapter-herdr` DEBE ser reemplazable por otra implementación sin modificar el núcleo.
3. Thalos DEBE poder validarse en modo `dry-run-only` sin Herdr instalado.
4. Thalos NO PUEDE ejecutar trabajo real sin un `ExecutionAdapter` productivo.
5. El núcleo NO DEBE nombrar a Herdr fuera del extension registry y de la configuración.

ID:

```txt
thalos.adapter.herdr
```

Implementa:

```txt
ExecutionAdapter
```

Binario externo requerido:

```txt
herdr >= 0.7.0
```

Resolución del binario según la sección 37.4.5:

```txt
THALOS_HERDR_BIN -> .thalos/bin/herdr -> PATH
```

Herdr gestiona workspaces y paneles de terminal, que ES estado a nivel de máquina y de sesión. Por lo tanto DEBE instalarse a nivel de sistema y NO DEBE vendorearse por proyecto.

**Corrección respecto de 0.0.4: adapter y plugin de Herdr compartían responsabilidades de creación de workspaces y layouts. La frontera ahora es filosa.**

El adapter de Herdr ES responsable del **ciclo de vida de procesos**:

```txt
- crear workspaces y sesiones de ejecución,
- lanzar agentes,
- enviar prompts,
- esperar estados,
- leer salida,
- ejecutar comandos,
- cerrar sesiones de ejecución,
- reportar metadata de ejecución.
```

**Corrección respecto de 0.0.6 inicial: la lista declaraba un ciclo de vida sin cierre.** Thalos abría sesiones y no cerraba ninguna: cada despacho dejaba un panel ocupando la pantalla, y quien decidiera que una sesión ya no hace falta -una persona o un rol coordinador- no tenía por dónde pedirlo. Un ciclo de vida con nacimiento y sin fin no es un ciclo.

El adapter de Herdr NO DEBE:

```txt
- definir política de merge,
- modificar schemas,
- aprobar cambios,
- reemplazar el state store,
- decidir routing,
- exponer comandos de usuario,
- definir layouts de UI.
```

---

## 39. Plugins

### 39.1. Definición

Un plugin es una extensión opcional que expone:

```txt
- comandos de usuario,
- layouts de UI,
- event handlers,
- reportes,
- metadata visual.
```

Un plugin NO ejecuta trabajo del ciclo de vida. Un plugin **invoca** al núcleo.

### 39.2. Principios

1. Un plugin NO DEBE ser requerido para ejecutar el núcleo.
2. Un plugin DEBE invocar a Thalos mediante CLI/API.
3. Un plugin NO DEBE mutar estado interno directamente.
4. Un plugin NO DEBE redefinir política.
5. Un plugin NO DEBE crear recursos de ejecución; eso es responsabilidad de un adapter.
6. Un plugin PUEDE mejorar UX.
7. Un plugin PUEDE reaccionar a eventos.
8. Un plugin DEBE declarar permisos.
9. Un plugin DEBE declarar compatibilidad con el core.
10. Un plugin DEBE poder desinstalarse sin corromper el proyecto.

### 39.3. Plugin de Herdr

ID recomendado:

```txt
thalos.plugin.herdr
```

Paquete recomendado:

```txt
thalos-plugin-herdr
```

El plugin PUEDE exponer comandos que invocan la CLI:

```txt
Start SDLC      -> thalos plan
Start Feature   -> thalos feature start <id>
Run Review      -> thalos review run <id>
Open PR         -> thalos feature pr <id>
Merge Guard     -> thalos merge guard <pr>
Show Status     -> thalos status --format json
```

El plugin PUEDE definir layouts de visualización:

```txt
Workspace: proyecto
  Tab: control
  Tab: agents
  Tab: coordination
  Tab: checks
  Tab: logs
```

El plugin NO DEBE lanzar agentes por su cuenta; DEBE delegar en `thalos` que a su vez usa `ExecutionAdapter`.

---

## 40. CLI / API

### 40.1. Principios

1. Thalos DEBE exponer una CLI principal llamada `thalos`.
2. La CLI DEBE poder operar sin plugins.
3. La CLI DEBE ser el medio principal de automatización.
4. Los plugins DEBEN usar CLI/API en lugar de acceso directo a archivos internos.
5. La CLI DEBE devolver salida estructurada cuando se solicite.
6. Todo comando mutante DEBE soportar `--dry-run`.

### 40.2. Comandos mínimos

**Corrección respecto de 0.0.6: la lista mezclaba comandos existentes con comandos que nadie había construido, sin distinguirlos.** Un comando listado como mínimo y ausente del código no es una omisión menor: el ciclo se queda sin camino en el punto donde ese comando produciría la evidencia que la transición siguiente exige. Pasó con `feature pr` y con `message`.

Los pasos que PRODUCEN evidencia se listan aparte porque son los que hacen avanzar el ciclo: sin ellos la máquina de estados sabe qué falta y nadie lo produce.

```txt
thalos init
thalos init --dry-run-only
thalos doctor
thalos migrate
thalos spec check
thalos spec assist
thalos plan
thalos status
thalos next
thalos run [--max N]
thalos boot <feature_id>
thalos feature start <id>
thalos feature dispatch <id> --role <rol>
thalos feature work <id>
thalos feature commit <id>
thalos feature test <id>
thalos feature collect <id>
thalos feature pr <id>
thalos feature checks <id>
thalos feature advance <id> --to <estado>
thalos feature release <id>
thalos feature status <id>
thalos review run <feature_id>
thalos merge guard <pr_number>
thalos message list
thalos message show <id>
thalos message answer <id> --text "..."
thalos message send
thalos budget [feature_id]
thalos events tail
thalos evidence show <evidence_id>
thalos gate explain <gate> <feature_id>
thalos lock list
thalos lock reclaim <resource>
thalos plugin list
thalos plugin enable <id>
thalos plugin disable <id>
thalos adapter list
thalos adapter check <id>
thalos adapter capabilities
thalos adapter set <capability> <adapter_id>
thalos mode show
thalos mode set <dry-run-only|partial|production>
```

`thalos adapter capabilities` DEBE listar cada capacidad, su clasificación REQUERIDA u OPCIONAL, la implementación habilitada y el estado de su binario externo si aplica.

### 40.3. Salida estructurada

La CLI DEBE soportar `--format json` para al menos:

```txt
status
feature status
doctor
adapter list
plugin list
events tail
evidence show
gate explain
lock list
```

### 40.4. Códigos de salida

```txt
0   éxito
1   error de uso
2   precondition fallida
3   gate rechazado
4   escalación requerida
5   error de adapter no reintentable
6   migración requerida
```

---

## 41. Event system

**Corrección respecto de 0.0.4: los eventos eran append-only pero sin secuencia ni versión de schema, lo que hacía indefinida la reconstrucción de estado.**

### 41.1. Principios

1. Todo cambio relevante DEBE emitir evento.
2. Los eventos DEBEN ser append-only.
3. Los eventos DEBEN ser estructurados.
4. Los eventos NO DEBEN mutar estado por sí solos.
5. El core DEBE ser la autoridad de estado.
6. Los plugins PUEDEN suscribirse a eventos.
7. Los adapters PUEDEN emitir eventos.

### 41.2. Secuencia y orden

1. Todo evento DEBE tener `seq`, entero monotónicamente creciente dentro de un `run_id`.
2. `seq` DEBE ser asignado exclusivamente por el componente `EventLog`.
3. `EventLog` DEBE ser el único escritor del log.
4. Todo evento DEBE tener `schema_version`.
5. La reconstrucción de estado DEBE procesar eventos en orden de `seq`.
6. Un hueco en la secuencia DEBE tratarse como corrupción y DEBE detener la reconstrucción.
7. `orchestration/.meta.json` DEBE mantener `last_event_seq`.

### 41.3. Estructura del evento

```json
{
  "id": "ev-01H...",
  "seq": 142,
  "schema_version": 1,
  "type": "thalos.feature.merged",
  "ts": "2026-07-30T12:05:00Z",
  "run_id": "r-2026-07-30-001",
  "project": "my-project",
  "feature_id": "F001",
  "actor": "core:MergeGate",
  "correlation_id": "F001",
  "causation_id": "ev-01H...",
  "evidence_refs": ["ev-..."],
  "payload": {}
}
```

### 41.4. Namespace

Todos los eventos oficiales DEBEN usar namespace `thalos`.

### 41.5. Catálogo de eventos

```txt
thalos.run.started
thalos.run.halted
thalos.runtime.migrated

thalos.precondition.checked
thalos.precondition.failed
thalos.precondition.recheck

thalos.spec.missing
thalos.spec.invalid
thalos.spec.assist_offered
thalos.spec.assist_requested
thalos.spec.draft_generated
thalos.spec.validated
thalos.spec.revision_requested
thalos.spec.approved

thalos.program.planning_started
thalos.program.planning_retried
thalos.program.planned
thalos.program.completed

thalos.feature.ready
thalos.feature.started
thalos.feature.dev_complete
thalos.feature.pr_opened
thalos.feature.checks_started
thalos.feature.checks_passed
thalos.feature.checks_failed
thalos.feature.fixing
thalos.feature.human_requested
thalos.feature.merge_requested
thalos.feature.merged
thalos.feature.done
thalos.feature.blocked
thalos.feature.unblocked
thalos.feature.failed
thalos.feature.abandoned

thalos.review.changes_requested
thalos.review.completed

thalos.gate.evaluated
thalos.transition.rejected

thalos.message.sent
thalos.message.acked
thalos.message.expired
thalos.message.status_updated

thalos.agent.ack_confirmed
thalos.agent.ack_missing
thalos.agent.observed
thalos.agent.dead
thalos.agent.gone
thalos.agent.waiting_human
thalos.agent.turn_done

thalos.lock.acquired
thalos.lock.renewed
thalos.lock.released
thalos.lock.expired
thalos.lock.reclaimed

thalos.budget.consumed
thalos.budget.exceeded

thalos.error.occurred
thalos.escalation.triggered
```

---

## 42. State store

### 42.1. Principios

1. El estado DEBE persistirse de forma durable.
2. El estado DEBE poder reconstruirse desde el event log.
3. El estado NO DEBE depender de plugins.
4. El estado DEBE versionarse mediante `runtime_schema_version`.
5. El state store PUEDE ser intercambiable.
6. El estado normativo NO DEBE vivir exclusivamente en memoria de proceso.
7. `state.json` ES una proyección; el event log ES la fuente de verdad.

### 42.2. Layout por defecto

```txt
orchestration/
  .meta.json
  state.json
  program-plan.json
  locks.json
  features/
    F001/
      feature-state.json
      tasks/
      reports/
  messages/
  reports/
  events/
    000001.ndjson
  evidence/
    ev-....json
```

### 42.3. Reconstrucción

1. `thalos doctor --rebuild-state` DEBE reconstruir `state.json` desde `events/`.
2. La reconstrucción DEBE validar continuidad de `seq`.
3. La reconstrucción DEBE producir un estado idéntico al proyectado.
4. Una divergencia entre proyección y reconstrucción DEBE reportarse como error `INTERNAL`.

---

## 43. Configuración

### 43.1. Archivos obligatorios del sistema

```txt
config/system.yaml
config/models.yaml
config/roles.yaml
config/routing.yaml
config/policy.yaml
config/communication.yaml
config/preconditions.yaml
config/extensions.yaml
config/reliability.yaml
```

### 43.2. Archivos del proyecto

```txt
thalos.config/project.yaml
thalos.config/overrides.yaml
thalos.config/extensions.yaml
thalos.config/reliability.yaml
```

### 43.3. Cadena de resolución de configuración

**Corrección respecto de 0.0.4: la cadena mezclaba configuración con autoridad de decisión, y colocaba la memoria por encima del spec aprobado y de la aprobación humana. Ahora son dos cadenas distintas.**

Resolución de un valor de configuración, de menor a mayor precedencia:

```txt
1. system defaults        (config/*.yaml del sistema)
2. project config         (thalos.config/project.yaml)
3. project overrides      (thalos.config/overrides.yaml)
4. environment variables  (THALOS_*)
5. CLI flags
```

Reglas:

1. La resolución DEBE ser un merge profundo por clave.
2. Las listas DEBEN reemplazarse, no concatenarse, salvo declaración explícita.
3. El resultado DEBE validarse contra el schema correspondiente.
4. Toda configuración resuelta DEBE tener digest y DEBE registrarse en `GateResult`.

### 43.4. Restricción de policy sobre configuración

1. `config/policy.yaml` NO participa en la cadena de resolución: **restringe** el resultado.
2. Tras resolver la configuración, Thalos DEBE validarla contra policy.
3. Un valor resuelto que viole policy DEBE causar error `VALIDATION` al cargar.
4. Thalos NO DEBE sobreescribir silenciosamente un valor que viole policy.
5. Un override de proyecto NO PUEDE relajar una restricción de policy.

### 43.5. Cadena de autoridad de decisión

Cuando Thalos debe decidir y las fuentes se contradicen, el orden de autoridad, de mayor a menor, ES:

```txt
1. Policy y aprobación humana
2. Spec aprobado
3. Evidencia verificable (CI, adapters, estado runtime)
4. Configuración resuelta
5. Contexto consultivo de extensiones      (p. ej. memoria)
6. Heurísticas del agente
```

Reglas:

1. Una fuente de menor autoridad NUNCA PUEDE anular a una de mayor autoridad.
2. El contexto consultivo de extensiones NO ES normativo.
3. El contexto consultivo NO PUEDE satisfacer un gate.
4. Una contradicción entre niveles 1 a 3 DEBE escalar, no resolverse por heurística.

### 43.6. Extensions config

`config/extensions.yaml` DEBE registrar:

```txt
adapters habilitados
plugins habilitados
extensiones opcionales habilitadas
prioridad
compatibilidad
permisos
```

---

## 44. Schemas obligatorios

**Corrección respecto de 0.0.4: los schemas obligatorios existían solo como nombres de archivo, mientras la extensión opcional de memoria tenía tres schemas completos.**

**Nota de versionado:** los `$id` de esta sección permanecen en `0.0.5` porque ningún schema cambió en 0.0.6. El `$id` de un schema DEBE versionar el schema, no el documento que lo contiene. Un `$id` solo DEBE incrementarse cuando su estructura cambia.

### 44.1. evidence.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/evidence/0.0.5",
  "type": "object",
  "required": [
    "id", "kind", "schema_version", "run_id",
    "produced_by", "produced_at", "digest", "verifiable"
  ],
  "properties": {
    "id": { "type": "string" },
    "kind": {
      "type": "string",
      "enum": [
        "PreconditionReport", "SchemaValidationReport", "HumanDecision",
        "HumanApproval", "SpecDraft", "ApprovedSpecRef", "ProgramPlan",
        "ProgramPlanEntry", "DependencySet", "LockLease", "LockRelease",
        "IssueRef", "BranchRef", "CommitRef", "PullRequestRef",
        "TaskResultSet", "LocalTestReport", "Review", "IssueList",
        "CheckRunSet", "PolicyDecision", "MergeGateReport", "MergeResult",
        "PostMergeReport", "BlockerResolution", "ErrorRecord",
        "GateResult", "FeatureStateSet"
      ]
    },
    "schema_version": { "type": "integer", "minimum": 1 },
    "run_id": { "type": "string" },
    "feature_id": { "type": ["string", "null"] },
    "produced_by": { "type": "string" },
    "produced_at": { "type": "string", "format": "date-time" },
    "artifact_refs": { "type": "array", "items": { "type": "string" } },
    "digest": { "type": "string", "pattern": "^sha256:[a-f0-9]{64}$" },
    "verifiable": { "type": "boolean" },
    "payload": { "type": "object" }
  },
  "additionalProperties": false
}
```

### 44.2. gate-result.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/gate-result/0.0.5",
  "type": "object",
  "required": ["gate", "decision", "reasons", "evaluated_at", "evaluator_version"],
  "properties": {
    "gate": {
      "type": "string",
      "enum": [
        "PRECONDITION_GATE", "SPEC_SCHEMA_GATE", "SPEC_GATE", "PLAN_GATE",
        "READY_GATE", "DEV_GATE", "REVIEW_GATE", "CHECKS_GATE",
        "POLICY_GATE", "HUMAN_GATE", "MERGE_GATE", "POST_MERGE_GATE"
      ]
    },
    "run_id": { "type": "string" },
    "feature_id": { "type": ["string", "null"] },
    "from_state": { "type": "string" },
    "to_state": { "type": "string" },
    "decision": { "type": "string", "enum": ["pass", "fail", "needs_human"] },
    "reasons": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["code", "status"],
        "properties": {
          "code": { "type": "string" },
          "status": { "type": "string", "enum": ["pass", "fail", "skip"] },
          "detail": { "type": "string" }
        }
      }
    },
    "missing_evidence": { "type": "array", "items": { "type": "string" } },
    "policy_snapshot_digest": { "type": "string" },
    "config_snapshot_digest": { "type": "string" },
    "evaluated_at": { "type": "string", "format": "date-time" },
    "evaluator_version": { "type": "string" }
  }
}
```

### 44.3. event.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/event/0.0.5",
  "type": "object",
  "required": ["id", "seq", "schema_version", "type", "ts", "run_id", "project", "actor"],
  "properties": {
    "id": { "type": "string" },
    "seq": { "type": "integer", "minimum": 1 },
    "schema_version": { "type": "integer", "minimum": 1 },
    "type": { "type": "string", "pattern": "^thalos\\.[a-z_]+\\.[a-z_]+$" },
    "ts": { "type": "string", "format": "date-time" },
    "run_id": { "type": "string" },
    "project": { "type": "string" },
    "feature_id": { "type": ["string", "null"] },
    "actor": { "type": "string" },
    "correlation_id": { "type": ["string", "null"] },
    "causation_id": { "type": ["string", "null"] },
    "evidence_refs": { "type": "array", "items": { "type": "string" } },
    "payload": { "type": "object" }
  },
  "additionalProperties": false
}
```

### 44.4. program-plan.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/program-plan/0.0.5",
  "type": "object",
  "required": ["schema_version", "project", "spec_digest", "created_at", "features"],
  "properties": {
    "schema_version": { "type": "integer", "const": 1 },
    "project": { "type": "string" },
    "spec_digest": { "type": "string" },
    "created_by": { "type": "string" },
    "created_at": { "type": "string", "format": "date-time" },
    "features": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["id", "title", "effort", "risk", "capability_tier", "human_approval_required"],
        "properties": {
          "id": { "type": "string", "pattern": "^F[0-9]{3,}$" },
          "title": { "type": "string" },
          "description": { "type": "string" },
          "spec_refs": { "type": "array", "items": { "type": "string" } },
          "acceptance_refs": { "type": "array", "items": { "type": "string" } },
          "depends_on": { "type": "array", "items": { "type": "string" } },
          "effort": { "type": "string", "enum": ["trivial", "low", "medium", "high", "critical"] },
          "risk": { "type": "string", "enum": ["low", "medium", "high", "critical"] },
          "risk_factors": { "type": "array", "items": { "type": "string" } },
          "capability_tier": { "type": "string", "enum": ["fast", "balanced", "deep"] },
          "human_approval_required": { "type": "boolean" },
          "required_locks": { "type": "array", "items": { "type": "string" } },
          "budget": {
            "type": "object",
            "properties": {
              "max_cost_usd": { "type": "number" },
              "max_iterations": { "type": "integer" },
              "max_wall_minutes": { "type": "integer" }
            }
          }
        }
      }
    }
  }
}
```

### 44.5. feature-state.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/feature-state/0.0.5",
  "type": "object",
  "required": ["schema_version", "feature_id", "state", "updated_at", "last_event_seq"],
  "properties": {
    "schema_version": { "type": "integer", "const": 1 },
    "feature_id": { "type": "string" },
    "run_id": { "type": "string" },
    "state": {
      "type": "string",
      "enum": [
        "FEATURE_READY", "FEATURE_IN_PROGRESS", "FEATURE_REVIEW",
        "FEATURE_PR_OPEN", "FEATURE_CHECKS_RUNNING", "FEATURE_CHECKS_PASS",
        "FEATURE_CHECKS_FAIL", "FEATURE_FIXING", "FEATURE_HUMAN_REVIEW",
        "FEATURE_MERGING", "FEATURE_MERGED", "FEATURE_DONE",
        "FEATURE_BLOCKED", "FEATURE_ESCALATED", "FEATURE_FAILED",
        "FEATURE_ABANDONED"
      ]
    },
    "issue_ref": { "type": ["string", "null"] },
    "branch_ref": { "type": ["string", "null"] },
    "pr_ref": { "type": ["string", "null"] },
    "leases": { "type": "array", "items": { "type": "string" } },
    "tasks": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "status"],
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "status": { "type": "string", "enum": ["pending", "in_progress", "done", "failed"] },
          "assigned_role": { "type": "string" },
          "effort": { "type": "string" },
          "files": { "type": "array", "items": { "type": "string" } }
        }
      }
    },
    "attempts": {
      "type": "object",
      "properties": {
        "fix": { "type": "integer" },
        "review": { "type": "integer" },
        "merge": { "type": "integer" }
      }
    },
    "budget_consumed": {
      "type": "object",
      "properties": {
        "cost_usd": { "type": "number" },
        "iterations": { "type": "integer" },
        "wall_minutes": { "type": "integer" }
      }
    },
    "last_gate_result": { "type": ["string", "null"] },
    "last_event_seq": { "type": "integer" },
    "updated_at": { "type": "string", "format": "date-time" }
  }
}
```

### 44.6. review.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/review/0.0.5",
  "type": "object",
  "required": ["schema_version", "feature_id", "reviewer", "created_at", "verdict", "findings"],
  "properties": {
    "schema_version": { "type": "integer", "const": 1 },
    "feature_id": { "type": "string" },
    "pr_ref": { "type": ["string", "null"] },
    "reviewer": { "type": "string" },
    "created_at": { "type": "string", "format": "date-time" },
    "verdict": { "type": "string", "enum": ["approve", "request_changes"] },
    "spec_refs_checked": { "type": "array", "items": { "type": "string" } },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["severity", "file", "summary"],
        "properties": {
          "severity": { "type": "string", "enum": ["blocker", "major", "minor", "nit"] },
          "category": { "type": "string" },
          "file": { "type": "string" },
          "line": { "type": ["integer", "null"] },
          "summary": { "type": "string" },
          "suggested_fix": { "type": "string" },
          "spec_ref": { "type": ["string", "null"] }
        }
      }
    },
    "blocker_count": { "type": "integer" },
    "scope_violation": { "type": "boolean" },
    "missing_tests": { "type": "array", "items": { "type": "string" } }
  }
}
```

### 44.7. locks.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/locks/0.0.5",
  "type": "object",
  "required": ["schema_version", "leases"],
  "properties": {
    "schema_version": { "type": "integer", "const": 1 },
    "leases": {
      "type": "array",
      "items": {
        "type": "object",
        "required": [
          "lease_id", "resource", "owner_feature", "owner_run",
          "reason", "acquired_at", "expires_at", "ttl_seconds", "generation"
        ],
        "properties": {
          "lease_id": { "type": "string" },
          "resource": { "type": "string" },
          "owner_feature": { "type": "string" },
          "owner_run": { "type": "string" },
          "reason": { "type": "string" },
          "acquired_at": { "type": "string", "format": "date-time" },
          "expires_at": { "type": "string", "format": "date-time" },
          "last_heartbeat_at": { "type": ["string", "null"], "format": "date-time" },
          "ttl_seconds": { "type": "integer", "minimum": 30 },
          "generation": { "type": "integer", "minimum": 1 }
        }
      }
    }
  }
}
```

### 44.8. message.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/message/0.0.5",
  "type": "object",
  "required": ["id", "thread_id", "type", "from", "to", "state", "created_at"],
  "properties": {
    "id": { "type": "string" },
    "thread_id": { "type": "string" },
    "in_reply_to": { "type": ["string", "null"] },
    "type": {
      "type": "string",
      "enum": [
        "TASK_REQUEST", "TASK_RESPONSE", "QUESTION", "ANSWER",
        "REVIEW_REQUEST", "REVIEW_RESPONSE", "FIX_REQUEST", "FIX_RESPONSE",
        "STATUS_UPDATE", "ESCALATION", "APPROVAL_REQUEST", "APPROVAL_RESPONSE",
        "SPEC_ASSIST_REQUEST", "SPEC_ASSIST_RESPONSE"
      ]
    },
    "from": { "type": "string" },
    "to": { "type": "string" },
    "run_id": { "type": "string" },
    "feature_id": { "type": ["string", "null"] },
    "task_id": { "type": ["string", "null"] },
    "state": {
      "type": "string",
      "enum": ["OPEN", "ACKED", "ANSWERED", "CLOSED", "EXPIRED", "ESCALATED"]
    },
    "critical": { "type": "boolean" },
    "artifact_refs": { "type": "array", "items": { "type": "string" } },
    "evidence_refs": { "type": "array", "items": { "type": "string" } },
    "payload": { "type": "object", "maxProperties": 64 },
    "payload_bytes": { "type": "integer", "maximum": 16384 },
    "created_at": { "type": "string", "format": "date-time" },
    "expires_at": { "type": ["string", "null"], "format": "date-time" }
  }
}
```

### 44.9. runtime-meta.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://thalos-sdlc/schemas/runtime-meta/0.0.5",
  "type": "object",
  "required": ["runtime_schema_version", "thalos_version", "run_id", "created_at", "last_event_seq"],
  "properties": {
    "runtime_schema_version": { "type": "integer", "minimum": 1 },
    "thalos_version": { "type": "string" },
    "run_id": { "type": "string" },
    "created_at": { "type": "string", "format": "date-time" },
    "last_migrated_at": { "type": ["string", "null"], "format": "date-time" },
    "last_event_seq": { "type": "integer", "minimum": 0 }
  }
}
```

---

### 44.10. task.schema.json

**Añadido en 0.0.7.** `task-result.schema.json` exigía `declared_scope` y ningún artefacto declaraba ese alcance: el rol tenía que producir un resultado sobre una task que no existía como artefacto. Un entregable cuyo contrato de ENTRADA no existe no es verificable, es adivinado.

El `declared_scope` de la task DEBE salir del alcance del rol —el mismo que impone el hook del mecanismo 2— y NO DEBE declarar rutas que el bloqueo vaya a denegar.

```json
{
  "$id": "https://thalos-sdlc/schemas/task/0.0.7",
  "required": ["schema_version", "feature_id", "task_id", "title", "declared_scope", "created_at"],
  "properties": {
    "role": "quién la ejecuta",
    "created_by": "component:Orchestrator cuando la deriva el núcleo del plan; role:FeatureLead cuando la descompone un coordinador",
    "declared_scope": "rutas autorizadas; contra esto se difea files_changed",
    "output": { "schema": "...", "path": "..." },
    "blocked": { "schema": "blocker", "path": "..." }
  }
}
```

### 44.11. blocker.schema.json

**Añadido en 0.0.7.** La OTRA salida de un encargo. Un rol tenía una sola forma de terminar —su entregable— y ninguna de decir "no puedo": cuando no podía, contestaba en prosa, Thalos esperaba un archivo que no llegaba y reportaba "terminó sin dejar entregable", perdiendo el motivo.

Esto NO reemplaza al canal de mensajes de la sección 25, lo complementa: el rol que puede contestar estructurado tiene por dónde, y el que no, igual es escuchado. Exigir este formato como única vía sería repetir el error que la regla 25.1.a corrige.

```json
{
  "$id": "https://thalos-sdlc/schemas/blocker/0.0.7",
  "required": ["schema_version", "feature_id", "task_id", "role", "reason", "created_at"],
  "properties": {
    "reason": "por qué no se puede seguir, concreto",
    "kind": "needs_decision | scope_insufficient | spec_contradiction | environment | dependency_missing | other",
    "needs": "qué haría falta para desbloquear",
    "tried": "qué se intentó antes de bloquear",
    "evidence_refs": "rutas o ids que sostienen el motivo"
  }
}
```

---

## 45. Extensiones opcionales

### 45.1. Contrato general

1. Una extensión opcional NO DEBE ser requerida por ningún criterio de aceptación del núcleo.
2. Una extensión opcional DEBE fallar de forma no bloqueante.
3. Una extensión opcional NO DEBE producir evidencia que satisfaga gates.
4. Una extensión opcional PUEDE producir **contexto consultivo**, que ocupa el nivel 5 de la cadena de autoridad (sección 43.5).

### 45.2. Memoria persistente

La memoria persistente ES una extensión opcional.

Su especificación completa vive en:

```txt
thalos-memory-0.0.1.md
```

El núcleo solo declara:

1. El extension point `MemoryAdapter`.
2. Que la memoria es contexto consultivo, nunca normativo.
3. Que la ausencia de `MemoryAdapter` NO DEBE afectar ningún criterio de aceptación del núcleo.
4. Que ninguna memoria PUEDE aparecer en `evidence_refs` de una transición.

---

## 46. Criterios de aceptación de Thalos v0.0.6

La versión 0.0.6 se considera aceptable si:

**Identidad y estructura**

1. El paquete canónico es `thalos-sdlc` y la decisión `D-001` está resuelta.
2. El sistema respeta la reserva semántica de directorios.
3. El sistema no escribe reglas dentro de `spec/`.

**Preconditions y spec**

4. El sistema detecta preconditions fallidas y produce `PreconditionReport`.
5. El sistema detecta spec faltante y ofrece asistencia.
6. El sistema detecta spec inválido y entra en `SPEC_INVALID`.
7. El sistema no planifica sin spec `approved`.
8. El sistema detecta cambios de spec posteriores a la aprobación por digest.

**Ciclo de vida**

9. Toda transición ejecutada existe en la tabla de transiciones.
10. Toda transición no listada se rechaza y emite `thalos.transition.rejected`.
11. Toda transición produce y persiste la evidencia declarada.
12. Todo gate devuelve un `GateResult` válido contra su schema.
13. Un gate con evidencia faltante devuelve `fail` con `missing_evidence` poblado.
14. El sistema genera un `program-plan.json` válido con grafo acíclico.
15. El sistema ejecuta una feature completa en modo serial.

**Fiabilidad**

16. Toda operación mutante de adapter acepta y usa idempotency key.
17. Un reintento de `open_pr` con la misma key devuelve `already_exists` y no duplica el PR.
18. Todo error se clasifica antes de decidir reintento.
19. Un error no reintentable escala sin consumir intentos.
20. Un lease expirado se reclama e incrementa `generation`.
21. Un adapter rechaza una operación con `generation` obsoleta.

**Eventos y estado**

22. Todo evento tiene `seq` monotónico y `schema_version`.
23. `thalos doctor --rebuild-state` reconstruye el estado y coincide con la proyección.
24. Un hueco en `seq` detiene la reconstrucción y reporta error.
25. El runtime declara `runtime_schema_version` y exige migración cuando corresponde.

**Configuración y gobierno**

26. La configuración resuelve por la cadena de la sección 43.3.
27. Una configuración que viola policy falla al cargar.
28. Ninguna fuente de menor autoridad anula a una de mayor autoridad.
29. El merge exige checks verdes, mergeable y política de aprobación.
30. El merge crítico exige `HumanApproval`.

**Routing**

31. El routing selecciona por `capability_tier` y nunca por costo.
32. `max()` opera solo sobre valores definidos del dominio ordenado.
33. Un presupuesto insuficiente escala en lugar de degradar el tier.

**Extensibilidad**

34. El sistema opera sin plugins.
35. El sistema opera en modo `dry-run-only` sin ninguna herramienta externa instalada.
36. El sistema opera sin ninguna capacidad OPCIONAL habilitada.
37. Ninguna extensión aprueba gates ni produce evidencia de transición.

**Capacidades e implementaciones**

38. Cada capacidad REQUERIDA tiene exactamente una implementación habilitada.
39. Cero implementaciones de una capacidad REQUERIDA falla en `PRECONDITION_GATE`.
40. Dos implementaciones de la misma capacidad falla en `PRECONDITION_GATE` por ambigüedad.
41. El núcleo no nombra `herdr`, `engram`, `github` ni ninguna otra implementación fuera del extension registry y la configuración.
42. `thalos-adapter-herdr` puede reemplazarse por otra implementación de `ExecutionAdapter` sin modificar el núcleo.
43. Un binario externo faltante produce un mensaje con el comando de instalación exacto y no instala nada por su cuenta.
44. Un binario externo fuera del rango de versión declarado falla en `PRECONDITION_GATE`.
45. La cascada de resolución de binarios respeta el orden entorno → `.thalos/bin/` → `PATH`.
46. El modo `dry-run-only` no produce evidencia con `verifiable: true` ni alcanza `FEATURE_MERGED`.
47. `thalos adapter capabilities` reporta la clasificación y el estado real de cada capacidad.

---

## 47. Modo recomendado para v0.0.6

```txt
execution_mode = dry-run-only        (elevar a partial cuando el slice funcione)
concurrency = serial
max_parallel_features = 1
auto_merge = false
human_approval = required_for_critical
routing = capability_based

execution_adapter = thalos.adapter.dryrun
coordination_adapter = thalos.adapter.dryrun
ci_adapter = thalos.adapter.dryrun

plugins = none
memory_extension = disabled
```

Progresión recomendada de modos:

```txt
dry-run-only -> partial -> production
```

No DEBE avanzarse de modo hasta que el modo anterior cumpla sus criterios de aceptación.

---

## 48. Migración

### 48.0. Desde 0.0.6

| Cambio | Acción requerida |
|---|---|
| `close_session` añadida a `ExecutionAdapter` | implementarla en todo adapter propio de esa capacidad |
| `api_version` de los manifiestos | subir a `0.0.7`; `core_compatibility` pasa a `>=0.0.7` |
| Comando de pruebas del proyecto | declarar `test_command` en `config/system.yaml` |
| Alcance del `Developer` | regenerar `write-scope.rules`; el deny total sobre `orchestration/` se reemplaza por denies dirigidos |
| Canal de mensajes | ninguna: `orchestration/messages/` ya lo creaba `thalos init` |

**Este es el único cambio que rompe compatibilidad de adapters.** Un `ExecutionAdapter` de 0.0.6 no implementa `close_session`: `thalos adapters` lo reporta como operación faltante y el ciclo no puede cerrar sesiones, aunque el resto siga funcionando.

No hay cambios de schema de estado runtime. `runtime_schema_version` permanece en `1`. La migración desde 0.0.6 NO requiere `thalos migrate`.

---

### 48.1. Desde 0.0.5

| Cambio | Acción requerida |
|---|---|
| Extension points clasificados por capacidad | declarar exactamente una implementación por capacidad REQUERIDA |
| `ExecutionAdapter` pasa a capacidad REQUERIDA | habilitar `thalos-adapter-herdr` o `thalos-adapter-dryrun` |
| Modo de operación explícito | declarar `execution_mode` en `config/system.yaml` |
| Preconditions 13, 14 y 15 añadidas | verificar con `thalos doctor` |
| Resolución de binarios en cascada | definir `THALOS_HERDR_BIN` solo si se necesita override |

No hay cambios de schema ni de estado runtime. `runtime_schema_version` permanece en `1`. La migración desde 0.0.5 NO requiere `thalos migrate`.

---

### 48.2. Desde 0.0.4 — cambios que rompen compatibilidad

| Cambio | Acción requerida |
|---|---|
| `config/` de proyecto renombrado a `thalos.config/` | mover archivos |
| Perfiles `cheap/mid/expensive` → `fast/balanced/deep` | reescribir `models.yaml` y `routing.yaml` |
| `dynamic` y `none` eliminados del dominio de tier | usar `null` en `role_minimum_tier` |
| Roles `QA`, `Fixer`, `MergeManager`, `Escalation`, `Orchestrator` eliminados | reasignar según tabla 18.4 |
| Estados de programa y feature separados | dividir `state.json` |
| Estado `SPEC_INVALID` añadido | actualizar máquina de estados |
| `CHECKS_GATE` añadido, `QA_GATE` eliminado | renombrar |
| Eventos requieren `seq` y `schema_version` | migrar event log |
| Locks requieren `ttl_seconds`, `expires_at`, `generation` | migrar `locks.json` |
| Adapters mutantes requieren `idempotency_key` | actualizar implementaciones |
| Cadena de precedencia de config corregida | revisar overrides que dependían del orden anterior |
| Memoria movida a documento aparte | migrar config a `thalos-memory-0.0.1.md` |

### 48.3. Procedimiento

```txt
1. thalos migrate --dry-run
2. revisar el plan de migración
3. thalos migrate
4. thalos doctor
5. thalos doctor --rebuild-state
6. comparar proyección contra reconstrucción
```

---

## 49. Changelog

### 0.0.7

Esta versión no salió de leer el spec: salió de **correr el ciclo completo contra agentes reales** hasta verlo cerrar. Cada corrección de acá es un defecto que solo apareció ejecutando, y la mayoría estaba tapada por probar los pasos por separado en vez del ciclo entero.

**Procedencia: la identidad no alcanza (reglas 25 a 28)**

Cuatro defectos distintos resultaron ser el mismo: una referencia que no llevaba consigo quién la produjo.

- El ledger de idempotencia devolvía `already_exists` sobre recursos creados por **otro adapter**: la clave es `sha256(run_id:feature:op:args)` y el `run_id` es estable entre sesiones, así que un adapter productivo recibía el id fabricado por el simulador y lo daba por bueno.
- El mismo ledger devolvía referencias a recursos **que ya no existían**, porque "esto se hizo una vez" no es "esto sigue estando".
- Los nombres de agente no distinguían **proyecto**: dos repos con una `F001` pedían el mismo agente, el adapter reconciliaba por nombre, y el trabajo de un proyecto se le mandaba al agente de otro.
- Los nombres de agente tampoco distinguían **rol**: despachar un `Reviewer` sobre una feature que ya tuvo `Developer` reusaba al `Developer`, que terminaba revisando su propio trabajo.

En los cuatro casos la operación reportaba éxito. Ninguno era detectable sin ejecutar.

**Comunicación: la estructura es del sobre (reglas 6.a a 6.c)**

La regla 6 pedía comunicación "estructurada", y exigirle esa estructura al agente es justamente lo que la rompe: si contesta distinto, se pierde. Un agente contestó *"no puedo seguir: el repo ya tiene memorias de F001 y el árbol está vacío, confirmame si reiniciaron el workspace"* —un bloqueo legítimo y bien argumentado— y Thalos lo descartó porque esperaba un archivo con un formato.

- La sección 25 estaba especificada entera y **no la implementaba nadie**: lo único que la mencionaba era el `init` creando `orchestration/messages/` vacío.
- Un paso que termina sin su entregable ahora lee lo que el agente dijo y lo persiste como mensaje dirigido a quien pueda actuar.
- `thalos message answer` cierra el circuito: persiste la respuesta en el mismo hilo, referencia la pregunta **y se la entrega al agente**. Sin ese último tramo la respuesta queda escrita y nadie la lee.

**El encargo tiene contrato, y tiene dos salidas**

- Añadido `schemas/task.schema.json`. El `task-result` exigía `declared_scope` y ningún artefacto declaraba ese alcance: el rol producía un resultado sobre una task que no existía. Un agente serio se negó a trabajar así, con razón.
- Añadido `schemas/blocker.schema.json`: la otra forma válida de terminar un encargo. El rol que puede contestar estructurado tiene por dónde; el que no, igual es escuchado por el canal de mensajes.
- El `declared_scope` de la task sale del alcance del rol —el mismo que el hook impone— para no prometer permisos que el bloqueo deniega.

**Ciclo de vida completo**

- Añadida `close_session` al contrato de `ExecutionAdapter` (38.5). La lista de responsabilidades iba de "crear sesiones" a "reportar metadata" sin pasar por cerrar: Thalos abría paneles y no cerraba ninguno. Un ciclo de vida con nacimiento y sin fin no es un ciclo. **Cambio de contrato: ver 48.0.**
- `thalos feature pr` y `thalos feature checks`: después de aprobar la revisión el ciclo se quedaba sin camino, porque las transiciones siguientes exigen `PullRequestRef` y `CheckRunSet` y ningún comando los producía.
- `thalos boot` enciende al coordinador y le cede la decisión del próximo paso, conservando gates, alcance y evidencia en el núcleo.

**Los gates evalúan sus condiciones**

- `CONDITION_DECLARED` se emitía como informativo y la transición pasaba igual. `F6` (la revisión pidió cambios) y `F7` (la revisión aprobó) exigen ambas un `Review`: con la condición ignorada las dos quedaban autorizadas, el loop tomaba la primera y volvía a trabajar sobre algo ya aprobado, para revisarlo otra vez, indefinidamente.
- Una condición que no puede evaluarse se sigue declarando. Una conclusión que no dice ni una cosa ni la otra —la de una simulación— no autoriza ninguna: elegir sería inventar el resultado de una prueba que nadie corrió.

**Alcance de rol**

- El `Developer` tenía prohibido escribir el único artefacto que el sistema le exige: su `output_artifact` vive bajo `orchestration/` y su alcance denegaba `orchestration/**`. `deny` gana sobre `allow`, así que el sistema le pedía algo que él mismo le prohibía.
- El resolvedor de instrucciones no llegaba a los roles de más de una palabra: `FeatureLead` resolvía a `featurelead.md` y el archivo es `feature-lead.md`. Despacharlo fallaba siempre; sobrevivió porque los roles que se ejercitan a diario son de una sola palabra.

**Routing**

- El tier ahora sale de `max(tier de la feature, mínimo del rol)`, que es el algoritmo que 20.5 ya definía. Mirar solo la feature dejaba el mínimo del rol declarado y sin efecto.
- `FeatureLead` pasa a exigir piso `deep` (20.4): coordinar mal no cuesta una tarea, cuesta la feature.

**Nombre**

- `D-001` resuelta: el proyecto pasa de `Talos` a **Thalos**. `talos` estaba tomado en npm y en PyPI —esta última mantenida y de otro dominio— más Talos Linux y Cisco Talos. `thalos` está libre en npm, PyPI y crates.io.
- El análisis de 0.0.6 tenía dos errores: sobreestimaba la colisión de binario (el CLI ajeno es `talosctl`) y subestimaba la de registries (solo nombraba a Talos Linux).
- Se hizo ahora y no en `v0.1.0` por costo: 133 archivos y cero instalaciones de terceros. Más tarde solo podía ser más caro.

**Lo que ejecutar enseñó sobre el propio contrato**

- Un texto con saltos de línea o comillas llegaba mutilado al agente: los `semantic_args` se leían con `sed`, que no decodifica. La operación reportaba éxito con el texto recortado.
- Un paso que no produce su evidencia ya no sale `0`. Reportar éxito sin el artefacto hacía que el loop lo contara como avance y reencargara lo mismo hasta agotar el presupuesto.
- Esperar un estado del runtime no es esperar el trabajo: un agente se asienta apenas recibe el prompt, antes de empezar. La condición de terminación de un encargo es el **artefacto**.
- Las órdenes que el loop propone no pueden llevar argumentos con espacios: se expanden sin comillas. El comando de pruebas se declara ahora en `config/system.yaml`.

---

### 0.0.6

**Capacidades requeridas frente a implementaciones elegidas**

- Añadida la sección 37.4: los extension points se clasifican como capacidad REQUERIDA u OPCIONAL, separado de qué adapter la implementa. La versión 0.0.5 marcaba adapters concretos como "opcionales", lo que confundía la reemplazabilidad de la implementación con la prescindibilidad de la capacidad.
- `ExecutionAdapter`, `FileSystemAdapter`, `ModelProviderAdapter`, `CoordinationAdapter` y `CIAdapter` pasan a capacidades REQUERIDAS.
- `MemoryAdapter` y `Plugin` permanecen OPCIONALES.
- Regla nueva: cada capacidad REQUERIDA debe tener exactamente una implementación habilitada. Cero implementaciones y dos implementaciones fallan ambas en `PRECONDITION_GATE`.

**Herdr**

- Reformulada la sección 38.5: `thalos-adapter-herdr` deja de ser "opcional" y pasa a ser la **implementación de referencia** de una capacidad REQUERIDA, reemplazable sin modificar el núcleo.
- Declarado el binario externo requerido `herdr >= 0.7.0`.
- Declarado que Herdr gestiona estado de máquina y sesión, por lo que debe instalarse a nivel de sistema y no debe vendorearse por proyecto.

**Modos de operación**

- Añadida la sección 37.4.4 con tres modos: `dry-run-only`, `partial` y `production`.
- `dry-run-only` debe poder ejecutarse sin ninguna herramienta externa instalada, no puede producir evidencia verificable y no puede alcanzar `FEATURE_MERGED`.
- El modo se declara en configuración y se registra en todo `GateResult`.

**Resolución de binarios externos**

- Añadida la sección 37.4.5 con cascada `variable de entorno → .thalos/bin/ → PATH`.
- Verificación obligatoria de rango de versión.
- Prohibición explícita de instalar binarios de terceros de forma automática; Thalos detecta y guía, no instala.

**Aislamiento de vendors**

- Nuevo principio 20.b: el núcleo no debe nombrar implementaciones concretas fuera del extension registry y la configuración.
- Nuevo criterio de aceptación 41 que lo verifica.

**Otros**

- Preconditions 13, 14 y 15 añadidas: una implementación por capacidad requerida, binarios resueltos y en rango, modo coherente.
- Comandos nuevos: `thalos adapter capabilities`, `thalos adapter set`, `thalos mode show`, `thalos mode set`, y el flag `thalos init --dry-run-only`.
- Criterios de aceptación ampliados de 37 a 47.
- Modo recomendado de la sección 47 pasa a arrancar en `dry-run-only` con progresión explícita.
- Sin cambios de schema ni de estado runtime: migrar desde 0.0.5 no requiere `thalos migrate`.

### 0.0.5

**Correcciones de consistencia normativa**

- Corregida la contradicción entre la cadena de precedencia de configuración y la prioridad de fuentes de decisión. Ahora son dos cadenas separadas (secciones 43.3 y 43.5) y la memoria ya no puede anular al spec aprobado ni a la aprobación humana.
- Corregido el dominio de `role_minimum_tier`: se eliminan `dynamic` y `none`, que rompían el `max()` del algoritmo de routing.
- Corregida la definición de payload máximo de mensaje: pasa de RECOMENDADO sin enforcement a límite obligatorio con regla de reducción a `artifact_refs`.

**Definiciones que faltaban**

- Añadida la sección 23: tipo `Evidence`, envoltorio común y catálogo completo de 28 tipos. El término se usaba normativamente sin estar definido.
- Añadida la sección 24: contrato de `GateEvaluator` con entrada, salida, dominio de decisión y reglas de pureza.
- Añadida la tabla completa de transiciones (25 de programa, 27 de feature) con gate, actor, evidencia requerida y evento por transición.

**Máquina de estados**

- Separadas dos máquinas de estado independientes: programa y feature.
- Añadidos los estados `INIT`, `PRECONDITION_FAILED`, `SPEC_INVALID`, `PROGRAM_DONE`, `HALTED`, `FEATURE_REVIEW`, `FEATURE_FIXING`, `FEATURE_MERGING`, `FEATURE_ABANDONED`.
- Renombrado `QA_GATE` a `CHECKS_GATE`; añadido `SPEC_SCHEMA_GATE`.
- Definidos estados terminales y su efecto sobre los leases.

**Fiabilidad**

- Añadida idempotencia obligatoria en toda operación de adapter que mute estado externo, con derivación determinista de la key y contrato de respuesta `created | already_exists`.
- Añadida la clasificación de errores en ocho clases con reintentabilidad explícita.
- Añadidos timeouts, backoff exponencial con jitter y configuración por clase de operación.
- Convertidos los locks en leases con TTL, heartbeat, expiración, reclamo y fencing token (`generation`).

**Eventos y estado**

- Añadida secuencia monotónica `seq` asignada por un escritor único.
- Añadido `schema_version` por evento.
- Definida la detección de huecos de secuencia como corrupción.
- Añadido `orchestration/.meta.json` y el contrato de migración de runtime.
- Declarado el event log como fuente de verdad y `state.json` como proyección.

**Routing**

- Separados los ejes de capacidad y costo. Los perfiles pasan de `cheap/mid/expensive` a `fast/balanced/deep`.
- El presupuesto ya no influye en la selección de capacidad: si no alcanza, escala en lugar de degradar.

**Roles**

- Reducidos de 12 a 5 roles agente, 1 rol humano y 5 componentes de núcleo.
- `Orchestrator`, `MergeManager` (ahora `MergeGate`), `LockManager`, `GateEvaluator` y `EventLog` pasan a ser componentes deterministas sin modelo.
- `QA` absorbido por `Reviewer` más `CIAdapter`; `Fixer` absorbido por `Developer`; `Escalation` convertido en estado.

**Schemas**

- Añadidos schemas completos para los artefactos obligatorios que en 0.0.4 solo existían como nombres de archivo: `evidence`, `gate-result`, `event`, `program-plan`, `feature-state`, `review`, `locks`, `message`, `runtime-meta`.

**Estructura y alcance**

- Extraída la especificación de memoria a `thalos-memory-0.0.1.md`. El núcleo pasa de ~38% de contenido opcional a 0%.
- Renombrado el directorio de configuración de proyecto de `config/` a `thalos.config/` para eliminar la colisión con `.thalos/config/`.
- Sharpened la frontera entre el adapter y el plugin de Herdr: adapter gobierna procesos, plugin gobierna UI y comandos.
- Documentado el riesgo de colisión de nombre con Talos Linux como `DECISIÓN ABIERTA D-001`.

**Seguridad**

- La detección de secrets pasa a ser fail-closed: ante incertidumbre no se persiste y se escala.

**Otros**

- Añadida la regla de agregación de riesgo (sección 21.5).
- Añadida la verificación por digest de cambios de spec posteriores a la aprobación.
- Añadidos códigos de salida de CLI.
- Añadidos comandos `thalos migrate`, `thalos events tail`, `thalos evidence show`, `thalos gate explain`, `thalos lock list`, `thalos lock reclaim`.

### 0.0.4

- Introducción del sistema de memoria persistente.
- Nuevo extension point: MemoryAdapter.
- Nueva entidad: Memory.
- Nuevo rol opcional: MemoryCurator.
- Nuevos eventos `thalos.memory.*` y comandos CLI `thalos memory *`.
- Regla explícita: memoria es consultiva, no normativa.

### 0.0.3

- Nombre oficial del sistema: Thalos.
- Paquete canónico: thalos-sdlc. CLI oficial: thalos.
- Runtime local recomendado: `.thalos/`.
- Namespace de eventos: thalos.
- Prefijos oficiales para adapters y plugins.

### 0.0.2

- Arquitectura desacoplada por capas.
- Introducción de contratos, puertos, adapters y plugins.
- Extension registry. CLI mínima. Event system. State store.
- Dry-run adapter recomendado. Core portable sin plugins.

### 0.0.1

- Versión inicial experimental.
- Separación formal entre sistema y spec.
- Definición de roles, lifecycle, comunicación y governance.
- Preconditions y spec intake. Routing por riesgo y esfuerzo.

---

## 50. Decisiones abiertas

| ID | Decisión | Bloquea | Recomendación |
|---|---|---|---|
| D-002 | Backend por defecto del `StateStore` (archivos vs SQLite) | paralelismo > 1 | archivos para el piloto serial; SQLite antes de habilitar paralelismo |
| D-003 | Estrategia de merge por defecto (squash / merge / rebase) | primer merge real | squash, para mantener una trazabilidad de un commit por feature |
| D-004 | Alcance del primer vertical slice | inicio de implementación | `doctor → spec check → plan → feature start` en dry-run, sin extensiones |

---

## 51. Ruta de implementación recomendada

La versión 0.0.6 NO DEBE extenderse con nuevas secciones normativas antes de tener un vertical slice ejecutable.

Orden recomendado:

```txt
modo dry-run-only
  1. schemas/ + validación            (secciones 44, 28)
  2. EventLog con seq                 (sección 41)
  3. Máquina de estados + gates       (secciones 22, 23, 24)
  4. Registro de capacidades          (sección 37.4)
  5. DryRunAdapter                    (sección 38)
  6. thalos doctor / thalos spec check  (secciones 27, 28)
  7. thalos plan                       (sección 29)
  8. thalos feature start              (sección 30)

modo partial
  9. ExecutionAdapter real (herdr)    (sección 38.5)
 10. LockManager                      (sección 32)

modo production
 11. CoordinationAdapter real         (sección 38)
 12. CIAdapter real                   (sección 38)
 13. MergeGate                        (sección 31)
```

Reglas:

1. Cada modo DEBE cumplir sus criterios de aceptación antes de avanzar al siguiente.
2. Las capacidades OPCIONALES, incluida la memoria, NO DEBEN implementarse antes del paso 13.
3. El paso 4 DEBE preceder a cualquier adapter, para que ningún adapter concreto quede cableado en el núcleo.
