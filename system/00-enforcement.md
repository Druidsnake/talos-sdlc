# Talos — Modelo de Enforcement

**Documento:** system/00-enforcement.md
**Versión:** 0.0.1
**Requiere core:** talos-sdlc >= 0.0.6
**Estado:** Normativo

---

## 0. Por qué este documento existe primero

Talos se distribuye como un conjunto de archivos que un modelo de IA consume: `.md`, `.yaml`, `.json`. Esa decisión define el formato, no el poder.

El problema central de Talos no es **qué reglas escribir**. Es **cómo lograr que se cumplan**.

Este documento define ese mecanismo. Sin él, el resto de la especificación es una lista de deseos.

---

## 1. El axioma incómodo

```txt
Un documento leído por un modelo NO PUEDE forzar el comportamiento de ese modelo.
```

Todo archivo que el agente lee entra a su contexto como texto. El modelo lo pondera junto al resto de su contexto: el pedido del usuario, el código que ve, su propio razonamiento. Un `DEBE` en mayúsculas es una señal de peso, no una barrera.

Consecuencia normativa:

1. Un requisito respaldado únicamente por texto ES **consultivo**, sin importar cómo esté redactado.
2. Redactar un consejo como obligación NO lo convierte en obligación.
3. Un requisito que Talos declare obligatorio DEBE tener un mecanismo de enforcement asociado.
4. Un requisito obligatorio sin mecanismo DEBE reescribirse como recomendación o DEBE recibir un mecanismo.

Esta es la regla que gobierna el resto del documento.

---

## 2. Dónde vive el enforcement

El enforcement NO vive en el documento. Vive en **puntos de control que se ejecutan fuera del modelo**.

```txt
documento  -> le dice al modelo QUÉ hacer          (guía)
control    -> le impide al modelo hacer OTRA cosa  (enforcement)
```

Ambos son necesarios. El documento sin control es un consejo. El control sin documento es una pared sin cartel: el agente choca y no sabe por qué.

### 2.1. Propiedad que define un punto de control

Un punto de control ES válido si cumple las tres:

1. **Se ejecuta fuera del modelo.** Su resultado no depende de que el modelo coopere.
2. **Es determinista.** La misma entrada produce el mismo veredicto.
3. **Tiene consecuencia.** Un veredicto negativo impide que algo avance.

Un "control" que el modelo puede ignorar no es un control.

---

## 3. Taxonomía de mecanismos

Ordenados por fuerza real, de mayor a menor.

| # | Mecanismo | Fuerza | Se ejecuta en | Consecuencia del fallo |
|---|---|---|---|---|
| 1 | Validación de schema | **dura** | validador | el artefacto se rechaza |
| 2 | Hook bloqueante pre-acción | **dura** | runtime del agente | la acción no ocurre |
| 3 | Check de CI | **dura** | CI | el PR no mergea |
| 4 | Git hook | **dura** | git | el commit o push no entra |
| 5 | Protección de rama | **dura** | plataforma | el merge no ocurre |
| 6 | Hook post-acción con reversión | **media** | runtime del agente | la acción ocurre y se revierte |
| 7 | Presencia obligatoria de artefacto | **media** | validador | el gate siguiente falla |
| 8 | Aislamiento de permisos | **media** | runtime del agente | la herramienta no está disponible |
| 9 | Inyección de contexto por rol | **blanda** | prompt | el modelo tiene menos con qué desviarse |
| 10 | Instrucción en `.md` | **blanda** | prompt | ninguna |

### 3.1. La línea que importa

```txt
mecanismos 1-5  -> el requisito ES obligatorio
mecanismos 6-8  -> el requisito ES obligatorio con ventana de violación
mecanismos 9-10 -> el requisito ES consultivo, aunque diga DEBE
```

Un requisito de Talos marcado `DEBE` que solo cuente con mecanismos 9 o 10 está **mal clasificado**.

---

## 4. Regla de mapeo

```txt
Todo requisito normativo de Talos DEBE declarar su mecanismo de enforcement.
```

Formato requerido en las tablas de reglas:

| Campo | Contenido |
|---|---|
| `id` | identificador estable del requisito |
| `requisito` | el texto normativo |
| `mecanismo` | número de la taxonomía (sección 3) |
| `implementación` | archivo o check concreto que lo ejecuta |
| `fuerza` | dura, media o blanda, derivada del mecanismo |

Reglas:

1. Un requisito sin `mecanismo` NO DEBE publicarse como `DEBE`.
2. Un requisito con `fuerza: blanda` DEBE redactarse como `RECOMENDADO`, no como `DEBE`.
3. La auditoría de mapeo DEBE poder ejecutarse automáticamente sobre los documentos de `system/`.
4. Un cambio que degrade la fuerza de un requisito DEBE registrarse en el changelog.

---

## 5. Los tres niveles de instalación

El enforcement disponible depende de dónde se instala Talos. No todos los proyectos pueden ejecutar todos los mecanismos.

| Nivel | Qué incluye | Mecanismos disponibles | Enforcement real |
|---|---|---|---|
| `L0 — guía` | solo `system/`, `roles/`, `templates/` | 9, 10 | ninguno |
| `L1 — verificado` | L0 + `schemas/` + validador + git hooks | 1, 4, 7, 9, 10 | artefactos y commits |
| `L2 — gobernado` | L1 + hooks del agente + CI + protección de rama | 1-10 | acciones, merges, ciclo completo |

Reglas:

1. Talos DEBE declarar su nivel de instalación en `config/system.yaml`.
2. Talos DEBE reportar el nivel en `talos doctor`.
3. Un requisito cuyo mecanismo no esté disponible en el nivel instalado DEBE degradarse a consultivo **y DEBE reportarse como degradado**.
4. Talos NO DEBE afirmar que un requisito se cumple cuando su mecanismo no está disponible.
5. `L0` NO DEBE presentarse como un sistema de gobierno. ES documentación.

La regla 4 es la que preserva la honestidad del sistema: es preferible un Talos que diga "esto no lo puedo garantizar en tu instalación" a uno que finja gobierno que no ejerce.

---

## 6. Mapeo de los requisitos del núcleo

Clasificación de los requisitos estructurales de `talos-0.0.7.md`.

### 6.1. Enforcement duro disponible

| Requisito del núcleo | Mecanismo | Implementación |
|---|---|---|
| Todo artefacto valida contra su schema (§44) | 1 | `schemas/*.json` + validador |
| Spec manifest válido (§28.2) | 1 | `schemas/spec-manifest.schema.json` |
| `program-plan.json` válido (§29.3) | 1 | `schemas/program-plan.schema.json` |
| Grafo de dependencias acíclico (§29.9) | 1 | validador |
| Payload de mensaje ≤ 16 KB (§25.5) | 1 | `schemas/message.schema.json` |
| Pesos de ranking suman 1.0 (memoria §12.2) | 1 | `schemas/memory-config.schema.json` |
| Config no viola policy (§43.4) | 1 | validador de policy |
| Una implementación por capacidad requerida (§37.4.3) | 1 | validador de extension registry |
| Agente no escribe fuera de su scope (§19.1) | 2 | hook pre-acción sobre rutas |
| `SpecAssistant` solo escribe en `spec/` (§16.1.6) | 2 | hook pre-acción sobre rutas |
| Agente no toca ramas protegidas (§30.1.10) | 2, 5 | hook + protección de rama |
| Agente no mergea (§30.1.9) | 2, 5 | hook + protección de rama |
| Checks verdes antes de merge (§31.1) | 3, 5 | CI + protección de rama |
| Aprobación humana en riesgo crítico (§31.6) | 5 | protección de rama con review requerido |
| Commit referencia feature y task (§5.5) | 4 | `commit-msg` hook |
| Evidencia presente antes de transición (§22.6.3) | 1, 7 | validador de gate |
| Secrets no persistidos (§36.11) | 2, 3 | hook pre-escritura + check de CI |

### 6.2. Enforcement medio

| Requisito del núcleo | Mecanismo | Nota |
|---|---|---|
| `feature-state.json` actualizado (§30.1.7) | 7 | se detecta en el gate siguiente, no al momento |
| Evento emitido por transición (§22.6.5) | 7 | ausencia detectable, emisión no forzable sin proceso |
| Lease liberado al terminar (§32.2.7) | 6 | requiere barrido posterior |
| Developer no amplía alcance (§30.2.2) | 6, 7 | detectable por diff contra scope declarado |

### 6.3. Sin enforcement duro posible

Estos requisitos dependen del juicio del modelo. **DEBEN reclasificarse como `RECOMENDADO`** o apoyarse en revisión humana.

| Requisito del núcleo | Por qué no se puede forzar |
|---|---|
| Reviewer revisa contra el spec (§30.3.1) | la calidad del juicio no es verificable automáticamente |
| Planner clasifica riesgo correctamente (§29.6) | la corrección de la clasificación es opinión |
| Memorias atómicas (memoria §5.2) | la atomicidad es criterio |
| Títulos buscables (memoria §5.3) | la calidad es criterio |
| Talos pregunta ante ambigüedad (§5.13) | detectar la ambigüedad requiere el modelo |

Regla: para los requisitos de esta tabla, el enforcement disponible es **estructural, no semántico**. Se puede forzar que exista un `Review` con el schema correcto; no se puede forzar que la revisión sea buena. Esa distinción DEBE quedar explícita en cada regla.

---

## 7. Estrategias de guía para lo no forzable

Cuando un requisito cae en 6.3, el enforcement duro no está disponible, pero la probabilidad de cumplimiento sí se puede mejorar. Estas estrategias operan sobre mecanismos 8 y 9.

| Estrategia | Cómo | Por qué funciona |
|---|---|---|
| **Reducir el espacio de acción** | dar al rol solo las herramientas que necesita | el modelo no puede hacer lo que no tiene disponible |
| **Contexto mínimo por rol** | inyectar solo las reglas de ese rol | menos contexto irrelevante, menos deriva |
| **Salida estructurada obligatoria** | exigir un artefacto con schema | fuerza a explicitar lo que hizo, y el schema sí se valida |
| **Checklist verificable** | exigir marcar ítems con evidencia por ítem | convierte juicio difuso en afirmaciones puntuales |
| **Declaración de scope previa** | el rol declara qué va a tocar antes de tocarlo | habilita el diff posterior contra lo declarado |
| **Separación de roles** | quien implementa no revisa | elimina el conflicto de interés del mismo contexto |

Reglas:

1. Todo requisito de la tabla 6.3 DEBE tener al menos una estrategia de esta sección asignada.
2. Estas estrategias NO DEBEN presentarse como enforcement.
3. La salida estructurada ES la estrategia más fuerte, porque convierte una obligación semántica en un artefacto sintáctico verificable.

La regla 3 es la palanca principal del diseño: **no podés forzar que el Reviewer revise bien, pero sí podés forzar que produzca un `review.json` válido con un finding por cada `acceptance_criteria` del spec.** El modelo sigue decidiendo el contenido; la estructura deja de ser opcional.

---

## 8. Artefactos de esta capa

| Directorio | Contenido | Mecanismo que habilita |
|---|---|---|
| `system/` | reglas normativas legibles por el modelo | 10 |
| `roles/` | instrucciones y scope por rol | 8, 9 |
| `schemas/` | contratos estructurales | 1 |
| `templates/` | plantillas de artefactos de salida | 9 |
| `hooks/` | puntos de control ejecutables | 2, 4, 6 |
| `config/` | configuración declarativa | 1 |
| `contracts/` | contratos de puertos y adapters | 10 |

---

## 9. Criterios de aceptación de esta capa

1. Todo requisito de `system/` declara su mecanismo de enforcement.
2. Ningún requisito con fuerza blanda está redactado como `DEBE`.
3. La auditoría de mapeo se ejecuta automáticamente y falla si encuentra un `DEBE` sin mecanismo.
4. El nivel de instalación se declara y se reporta.
5. Un requisito cuyo mecanismo no está disponible se reporta como degradado, no como cumplido.
6. Cada requisito de la tabla 6.3 tiene al menos una estrategia de guía asignada.
7. Todo rol tiene un artefacto de salida con schema obligatorio.
8. Un artefacto que no valida contra su schema es rechazado sin intervención del modelo.

---

## 10. Changelog

### 0.0.1

- Documento inicial.
- Axioma: un documento leído por un modelo no puede forzar su comportamiento.
- Taxonomía de diez mecanismos de enforcement ordenados por fuerza.
- Regla de mapeo: todo requisito normativo declara su mecanismo.
- Tres niveles de instalación con enforcement disponible por nivel.
- Clasificación de los requisitos del núcleo en duro, medio y no forzable.
- Estrategias de guía para lo no forzable, con la salida estructurada como palanca principal.
