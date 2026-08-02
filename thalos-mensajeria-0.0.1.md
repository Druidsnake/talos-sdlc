# Thalos Mensajería — Especificación

**Nombre:** Thalos Mensajería
**Versión del documento:** 0.0.1
**Requiere núcleo:** thalos-sdlc >= 0.0.7
**Requiere backend:** herdr >= 0.7.5, protocolo 17
**Estado:** Propuesta — NÚCLEO, no extensión
**Fecha:** 2026-08-02
**Tipo de documento:** Especificación de subsistema
**Idioma:** texto normativo en español
**Enmienda:** `thalos-0.0.7.md` secciones 25, 35, 38.4, 41.5, 43

> Todo comportamiento del backend que se afirma en este documento fue **medido**,
> no inferido. Los experimentos y sus resultados están en el anexo A.

---

## 0. Convenciones y posición en el sistema

### 0.1. Palabras clave normativas

Las palabras clave DEBE, NO DEBE, REQUERIDO, PUEDE, RECOMENDADO y OPCIONAL deben interpretarse como requisitos normativos.

### 0.2. Naturaleza de este documento

Este documento NO describe una extensión opcional. La mensajería ES parte del núcleo: sin ella, Thalos no puede saber si un agente está vivo, y un orquestador que no puede responder esa pregunta no orquesta nada.

Se escribe aparte del núcleo porque enmienda cinco secciones a la vez y porque el subsistema tiene coherencia propia. Al estabilizarse, sus reglas DEBEN integrarse a `thalos-0.0.7.md` o a su sucesor.

### 0.3. El eje que ordena todo el documento

**Vitalidad y avance son ejes ortogonales. Medir uno con el instrumento del otro es el defecto que este documento corrige.**

```txt
Eje A — VITALIDAD        ¿el canal con el agente está vivo?
                         lo observa Thalos, sin cooperación del agente
                         pertenece a la MENSAJERÍA

Eje B — AVANCE           ¿apareció el artefacto que el contrato de rol exige?
                         lo produce el agente, lo valida un schema
                         pertenece al CICLO DE DESARROLLO
```

El `task-result.json` de la sección 30.2, el `blocker.json`, el `Review` — son requisitos de Thalos para que el desarrollo avance y para que un gate pueda evaluar. **NO son señales de comunicación.** Que no exista un entregable no dice absolutamente nada sobre si el agente está vivo.

Consecuencias normativas:

1. La mensajería NO DEBE usar la existencia de un entregable como prueba de vitalidad.
2. La ausencia de un entregable NO DEBE producir, por sí sola, un veredicto de vitalidad negativo.
3. Un paso de espera DEBE reportar los dos ejes por separado y NO DEBE colapsarlos en un único resultado.
4. Un gate DEBE seguir evaluando sobre el eje B exclusivamente. La vitalidad NO PUEDE satisfacer un gate.

### 0.4. Alcance de la vitalidad

**Este subsistema detecta MUERTE. NO detecta FUTILIDAD.**

Un agente en bucle de reintento está vivo: su proceso corre y el runtime lo reporta trabajando. Para este subsistema ES un agente vivo, y lo es. Lo que acota el trabajo inútil sigue siendo el reloj de pared y el presupuesto de la sección 33.

Ningún sistema de vitalidad puede decidir si el trabajo sirve. Eso es el eje B.

---

## 1. Propósito

Que el maestro sepa **en todo momento** en cuál de estos estados está un agente despachado, y que cada estado tenga una acción distinta:

```txt
- el encargo nunca le llegó,
- le llegó y está trabajando,
- le llegó y está esperando una decisión humana,
- terminó su turno,
- su proceso murió,
- ya no existe el panel,
- no es observable.
```

Antes de este documento, cinco de esos siete colapsaban en el mismo veredicto y uno no terminaba nunca.

No objetivos:

```txt
- imponerle un formato de respuesta al agente,
- introducir un proceso demonio,
- detectar trabajo inútil,
- reemplazar los gates,
- reemplazar el contrato de salida de los roles.
```

---

## 2. El defecto que se corrige

**Corrección respecto de 0.0.7: la sección 25 quedó implementada como transporte de mensajes, pero la espera de un agente siguió resolviéndose contra el disco.**

| Dónde | Qué hace | Por qué falla |
|---|---|---|
| `cli/commands/feature.sh:485` | el bucle corta cuando aparece `$SALIDA` o `$BLOQUEO` | la condición de término de la COMUNICACIÓN es un artefacto del CICLO |
| `cli/commands/feature.sh:490` | solo distingue `working` y `blocked` | `done` —la terminación explícita del runtime— cae en el caso por defecto y cobra 90s de gracia |
| `adapters/herdr/run.sh:391` | `wait_agent` devuelve un estado | el estado sobrevive a la muerte del proceso que lo reportó |
| `cli/commands/feature.sh:412` | `prompt_agent` confirma vía `state_change_seq` | confirma que la TERMINAL recibió las teclas, no que el agente recibió el encargo |
| `hooks/lib/message.py:87` | `expires_at` se escribe siempre en `None` | las reglas 25.5.7/8/9 están escritas y sin implementar |
| `schemas/message.schema.json` | `STATUS_UPDATE` está en el enum | ningún emisor lo produce |

**El defecto central, medido (anexo A, experimento 5):** con el agente muerto y el shell vivo, herdr publica `working` indefinidamente y `state_change_seq` queda congelado. El maestro espera el `max_wall_minutes` completo sobre un agente que ya no existe.

---

## 3. Principios normativos

1. **Thalos NO DEBE esperar por una condición que no puede observar por sí mismo.**
2. La vitalidad DEBE ser observable sin cooperación del agente.
3. La cooperación del agente MEJORA la señal; NO DEBE habilitarla.
4. Ningún canal PUEDE ser compuerta de otro.
5. Un rol NO DEBE quedar obligado a conocer un formato para ser considerado vivo. *(deriva de 25.1.1.a)*
6. **Un hecho del sistema operativo DEBE prevalecer sobre un estado reportado.** Un estado es la memoria de lo que alguien dijo; un proceso es lo que hay.
7. Toda espera DEBE terminar en un veredicto nombrado. `null`, `unknown` y "seguir esperando" NO SON veredictos.
8. Cada veredicto DEBE tener exactamente una acción recomendada.
9. Toda observación DEBE poder reconstruirse desde eventos. *(deriva de 25.1.8)*
10. Ningún umbral de este subsistema DEBE estar cableado en el código. *(deriva de 43.3)*
11. Este subsistema NO DEBE introducir un proceso de larga vida.

### 3.1. Sobre el principio 3

Un latido emitido por el agente **no prueba avance**. Un agente clavado en un reintento infinito late perfecto, contesta todos los ACK y no progresa. Un protocolo que confía en la declaración del agente es igual de ciego que el actual, con el agravante de parecer confiable.

Por eso el canal declarado es **monótono positivo**: ver la sección 6.3.

---

## 4. Canal observado — REQUERIDO

### 4.1. Definición

El canal observado ES la lectura que Thalos hace del agente a través del `ExecutionAdapter`, **sin pedirle nada**.

### 4.2. Nueva capacidad: `observe_agent`

**Enmienda a la sección 38.4.** El `ExecutionAdapter` DEBE implementar:

```txt
observe_agent
```

Entrada:

```json
{ "target": "<nombre del agente>" }
```

Salida:

```json
{
  "pane_exists":       true,
  "state":             "working | blocked | done | idle | unknown",
  "state_change_seq":  207,
  "process_alive":     true,
  "process_observed":  true,
  "observed_at":       "2026-08-02T00:00:00Z"
}
```

Reglas:

1. `observe_agent` DEBE ser no mutante y NO DEBE requerir idempotency key.
2. `observe_agent` DEBE devolver los cuatro hechos en una sola operación. Componerlos en el núcleo obligaría al núcleo a conocer el vocabulario del backend, lo que viola 38.5.5.
3. `observe_agent` NO DEBE bloquear. Es una foto, no una espera.
4. `observe_agent` NO DEBE leer ni transportar texto de terminal. El texto es caro, frágil y no hace falta para decidir vitalidad.
5. La implementación de referencia lo resuelve con dos llamadas al socket de herdr: `agent.list` y `pane.process_info`.

### 4.3. `process_alive` — la única señal que no miente

```txt
process_alive := foreground_process_group_id != shell_pid
```

Cuando el único proceso en primer plano ES el shell, no hay agente corriendo en ese panel.

1. `process_alive` DEBE derivarse de `pane.process_info`, no del estado reportado.
2. `process_alive` en falso DEBE prevalecer sobre cualquier `state`, **solo si `process_observed` es verdadero**.
3. Un panel ausente de `pane.list` DEBE tratarse como `pane_exists: false`, que es más fuerte que `process_alive: false`.

### 4.3.1. No poder mirar no es estar muerto

`pane.process_info` puede no responder, o devolver `shell_pid: null`, que su schema admite. En ese caso Thalos **no sabe** si el proceso vive.

1. Cuando la observación del proceso no se pudo hacer, el adapter DEBE devolver `process_observed: false`.
2. Con `process_observed: false`, el campo `process_alive` NO PORTA INFORMACIÓN y NO DEBE alimentar ningún veredicto.
3. Con `process_observed: false`, el veredicto DEBE derivarse del `state`, es decir, DEBE degradar al comportamiento anterior a este documento.
4. Un adapter NO DEBE reportar `process_alive: false` para expresar que no pudo mirar.

La regla 4 es la importante. Afirmar la muerte por un fallo de lectura mataría agentes sanos, que es **peor** que el problema que este subsistema vino a resolver: hoy un agente muerto cuesta media hora de espera; un agente sano declarado muerto cuesta el trabajo que estaba haciendo. Ante la duda, el subsistema degrada a lo de antes en vez de empeorarlo.

El reintento de `agent_observe` (`max_attempts: 2`) existe para esto: una lectura perdida se vuelve a pedir antes de resignarse a no saber.

**Medido (anexo A, experimentos 5 y 6):** con el agente muerto, `state` se queda en `working` para siempre y `process_alive` cae en menos de 1 segundo. Con el shell muerto, el panel desaparece de `pane.list` en menos de 1 segundo.

### 4.4. `state_change_seq` NO es un latido

**Medido (anexo A, experimento 1):** `state_change_seq` se mueve **solo cuando el estado cambia**. Tres reportes consecutivos de `working` lo dejan quieto.

1. `state_change_seq` DEBE usarse para detectar TRANSICIONES.
2. `state_change_seq` NO DEBE usarse para medir quietud ni para inferir vitalidad.
3. Un `seq` congelado NO ES evidencia de nada por sí solo: un agente sano que trabaja diez minutos lo tiene congelado igual que uno muerto.

Esta regla existe porque la versión anterior de este documento definía la quietud sobre `seq` y sobre un digest de terminal. Las dos ideas resultaron equivocadas al medirlas: el digest no hacía falta y el `seq` no servía.

### 4.5. Vocabulario de estado del backend

Cinco valores, con orígenes distintos:

| Estado publicado | De dónde sale |
|---|---|
| `working` | la integración lo reporta: `chat.message`, `tool.execute.*`, `session.status` busy/retry, respuestas a permiso |
| `blocked` | la integración lo reporta: `permission.asked`, `question.asked`, **`session.error`** |
| `done` | **herdr lo deriva**: todo `idle` reportado se publica como `done` |
| `idle` | detección de pantalla, o agentes sin integración instalada |
| `unknown` | herdr no tiene información |

Reglas:

1. `done` ES la terminación del turno y DEBE tratarse como una razón válida de fin de espera.
2. `unknown` significa **"el backend no sabe"**, NO significa fallo. Un agente sin integración instalada reporta `unknown` estando perfectamente sano.
3. Un veredicto negativo NO DEBE fundarse en `unknown`. La acción ante `unknown` es reparar la observación, no matar al agente.
4. `blocked` es ambiguo por origen: mezcla "espera una decisión humana" con "la sesión falló". Ver 5.5.

**Medido (anexo A, experimentos 2 y 3):** `pane.report_agent` RECHAZA `done` como entrada —su enum es `idle|working|blocked|unknown`— y traduce todo `idle` a `done` en la publicación. Por lo tanto `done` NO puede emitirse; solo puede observarse.

---

## 5. Veredictos de vitalidad

### 5.1. Entradas de la decisión

```txt
pane_exists      el panel está en pane.list
state            working | blocked | done | idle | unknown
process_alive    foreground_process_group_id != shell_pid
ack_confirmed    hubo transición de estado posterior al encargo vigente
```

`ack_confirmed` NO viene del backend: lo sabe Thalos porque él mandó el encargo. Es la información que distingue un `done` **de reposo** —el estado en que un agente espera antes de recibir nada— de un `done` **de terminación**.

**Decisión M-004:** el mismo valor crudo significa cosas opuestas según dónde esté el handshake. Por eso `done` e `idle` se clasifican juntos y se desambiguan por `ack_confirmed`, no por el valor.

### 5.2. Tabla de decisión

| `pane_exists` | `state` | `process_alive` | `ack_confirmed` | Veredicto | Acción |
|---|---|---|---|---|---|
| no | — | — | — | `GONE` | liberar la referencia y redespachar |
| sí | `working` | sí | — | `ALIVE_WORKING` | seguir observando |
| sí | `working` | **no** | — | `DEAD` | cortar, redespachar |
| sí | `blocked` | sí | — | `WAITING_HUMAN` | escalar con evidencia (5.6) |
| sí | `blocked` | no | — | `FAILED` | cortar, redespachar |
| sí | `done` / `idle` | sí | **sí** | `DONE` | fin de turno: mirar el eje B |
| sí | `done` / `idle` | sí | **no** | `UNOBSERVABLE` | esperar el ACK o reparar la integración |
| sí | `unknown` | sí | — | `UNOBSERVABLE` | reparar la integración |
| sí | `done`/`idle`/`unknown` | **no** | — | `DEAD` | cortar, redespachar |
| — | — | — | — | `EXPIRED` | venció el plazo de pared |

La columna `process_alive` SOLO se lee cuando `process_observed` es verdadero. Con `process_observed: false` la columna se ignora y el veredicto sale del `state`, por la regla 4.3.1.3.

`NOT_DELIVERED` NO aparece en esta tabla: por decisión M-002 es una clase de error, no un veredicto. Ver 7.3.

### 5.3. Reglas de veredicto

1. Todo ciclo de observación DEBE producir exactamente un veredicto de la tabla.
2. `EXPIRED` tiene precedencia sobre todos los demás.
3. `GONE` tiene precedencia sobre `DEAD`.
4. `DEAD` tiene precedencia sobre cualquier veredicto derivado del `state`.
5. `WAITING_HUMAN` NO DEBE emitirse en la primera muestra. El runtime muestra bloqueos momentáneos que resuelve solo; cortar en la primera lectura aborta a un agente que trabaja bien. *(lección ya presente en `feature.sh:513`, se eleva a norma)*
6. Ningún veredicto DEBE consultar el eje B.
7. `DONE` NO DEBE emitirse sin `ack_confirmed`. Un agente en reposo que nunca recibió el encargo no terminó nada.

### 5.4. Precedencia

```txt
EXPIRED > GONE > DEAD > WAITING_HUMAN > DONE > ALIVE_WORKING > UNOBSERVABLE
```

### 5.5. Terminación de la espera

Una espera DEBE terminar por una de dos razones, **y DEBE decir cuál**:

```txt
razón de vitalidad   DONE | DEAD | GONE | FAILED | WAITING_HUMAN | EXPIRED
razón de avance      apareció el artefacto del contrato de rol
```

1. Las dos razones DEBEN reportarse por separado.
2. Terminar por avance NO DEBE reportarse como un veredicto de vitalidad.
3. La combinación `DONE` **sin** artefacto ES un hecho perfectamente decible: *terminó su turno y no entregó*. NO DEBE confundirse con `DEAD`.
4. La combinación `DEAD` **con** artefacto ES válida: entregó y su proceso terminó. NO ES un error.

### 5.6. `blocked` ambiguo: escalación con evidencia

`permission.asked`, `question.asked` y `session.error` producen el mismo `blocked`.

**Decisión M-005: se escala de más, con evidencia adjunta y sin interpretarla.**

1. `blocked` con `process_alive: false` DEBE resolverse como `FAILED`.
2. `blocked` con `process_alive: true` DEBE resolverse como `WAITING_HUMAN`.
3. Toda escalación por `WAITING_HUMAN` DEBE adjuntar las últimas `escalation_context_lines` líneas de la salida del agente.
4. Ese texto NO DEBE interpretarse, ni parsearse, ni alimentar el veredicto. Va como `artifact_refs` o `payload` del mensaje de escalación, tal cual.
5. La regla 4 preserva 4.2.4: `observe_agent` sigue sin leer terminal. La lectura ocurre **al escalar**, no al decidir.

Esto es la regla 25.1.1 aplicada a la escalación: *la estructura la pone Thalos, el contenido puede ser ruido*. Una persona distingue "me pide permiso" de "explotó" en dos segundos leyendo la pantalla; una heurística lo adivina mal justo cuando importa.

---

## 6. Canal declarado — OPCIONAL

### 6.1. Definición

El canal declarado ES lo que el agente dice por voluntad propia, en el tipo `STATUS_UPDATE` que ya existe en `message.schema.json`.

### 6.2. Emisión

El agente PUEDE emitir con:

```bash
thalos message status --text "..."
```

1. El comando DEBE estar disponible dentro del alcance del rol.
2. El texto DEBE persistirse tal cual, sin exigir formato. *(25.1.1)*
3. El mensaje DEBE quedar en el hilo de la task.
4. **Decisión M-001: la CLI explícita ES el único emisor.** Thalos NO DEBE inferir `STATUS_UPDATE` parseando la salida de terminal.

La regla 4 se sostiene en que el canal declarado, por 6.3, nunca resta. Un canal que no puede producir un veredicto negativo no justifica una heurística frágil para capturar más señal: el costo de adivinar mal no se compensa con nada.

### 6.3. Regla de monotonía positiva

**Un `STATUS_UPDATE` PUEDE mover un veredicto hacia MÁS vida. NUNCA hacia menos.**

1. Recibir un `STATUS_UPDATE` DEBE contar como señal de vida.
2. La AUSENCIA de `STATUS_UPDATE` NO DEBE ser entrada de ningún veredicto.
3. Ningún veredicto negativo PUEDE fundarse, ni total ni parcialmente, en que el agente no habló.
4. Un `STATUS_UPDATE` ilegible o absurdo DEBE tratarse igual que uno claro a efectos de vitalidad. Su contenido es para el humano; su llegada es para el sistema.

Esta regla ES el mecanismo que impide reintroducir el defecto de 0.0.6: si el silencio nunca resta, un agente que no conoce el protocolo no puede ser declarado muerto por no conocerlo.

### 6.4. Por qué NO se instruye al agente a narrar

Se evaluó instruir en el brief de rol que el agente emita `STATUS_UPDATE` periódicos. Se descarta:

1. El costo real no son los tokens de salida sino el **contexto**: cada emisión queda en la conversación del agente y se relee en cada inferencia posterior.
2. Interrumpe el razonamiento entre pasos de un plan.
3. **No hace falta.** El pensamiento silencioso del modelo ya produce `working` en el canal observado: la integración reporta en `chat.message`, que dispara al empezar a producir. El silencio del agente es silencio de TERMINAL, no de RUNTIME.

---

## 7. Handshake de despacho

### 7.1. El tramo que falta

`prompt_agent` confirma que el backend aceptó el envío. No confirma que el encargo llegó al agente. Entre "la terminal recibió las teclas" y "el agente empezó a procesar" hay un tramo donde hoy se pierden encargos en silencio.

### 7.2. ACK observado

**El ACK NO se le pide al agente. Se observa.**

```txt
1. Thalos toma una observación base       -> obs0 (state, seq0)
2. Thalos envía el encargo                -> prompt_agent
3. Thalos observa hasta ack_timeout_seconds
4. ACK := transición de estado a `working`, o cambio de state_change_seq
```

Reglas:

1. El ACK DEBE ser una TRANSICIÓN, no un valor. Como `state_change_seq` solo se mueve en cambios de estado (4.4), la transición `done → working` ES la señal de que el encargo entró.
2. El ACK confirmado DEBE persistirse: alimenta `ack_confirmed` de la tabla 5.2 durante toda la espera.
3. Thalos NO DEBE enviar un segundo encargo sobre una feature con un ACK confirmado y sin veredicto de terminación.

La regla 3 ES la confirmación previa al despacho: no se lanzan instrucciones nuevas sobre un canal cuyo estado no se confirmó.

### 7.3. `NOT_DELIVERED` es un error, no un veredicto

**Decisión M-002.** Si no hay transición dentro de `ack_timeout_seconds`, el encargo no llegó. Eso NO es un estado del agente: es el resultado de una operación que no se completó.

1. `NOT_DELIVERED` DEBE clasificarse como error de clase `TRANSIENT` según la sección 35.1.
2. Por lo tanto hereda, sin implementarlos de nuevo: backoff exponencial con jitter (35.2.4), `max_attempts` (35.2.7), `ErrorRecord` con historial de intentos (35.2.7) y reutilización de la idempotency key (35.2.6).
3. `NOT_DELIVERED` NO DEBE consumir iteración de presupuesto. No hubo encargo que ejecutar.
4. `NOT_DELIVERED` NO DEBE aparecer en la tabla de veredictos 5.2.
5. Al agotar `max_attempts`, DEBE escalar como cualquier otro error de la sección 35.

El reenvío es seguro pese a que `prompt_agent` sea `at_most_once`: si el agente nunca recibió el encargo, no hay duplicado que evitar.

### 7.3.1. No poder observar no es no haber entregado

Un `ExecutionAdapter` puede no implementar `observe_agent` de forma útil, o devolver una observación sin `state` ni `state_change_seq`. En ese caso no hay contra qué comparar y **el ACK no se puede decidir**.

1. Si la observación base no trae `state` ni `state_change_seq`, Thalos NO DEBE exigir ACK.
2. En ese caso el envío DEBE aceptarse como antes de este subsistema, y NO DEBE reintentarse.
3. Un adapter que simula (`dry_run` o `simulated`) queda cubierto por la misma regla: nadie procesa el encargo, así que no hay transición que esperar.

Es la regla 4.3.1 aplicada al handshake, y la asimetría es la misma: no detectar un encargo perdido cuesta una espera; declarar `NOT_DELIVERED` sobre un encargo que sí llegó **aborta un despacho que funcionaba**. Ante la falta de señal se degrada, no se inventa el fallo.

### 7.4. Limitación conocida

Si el agente ya estaba en `working` al momento del despacho, no hay transición y el ACK no se puede observar. La regla 7.2.3 hace que esa situación no deba ocurrir dentro del ciclo de Thalos.

---

## 8. Ciclo de vida del mensaje

### 8.1. Expiración — implementa 25.5.7/8/9

1. Todo mensaje DEBE recibir `expires_at` al crearse, derivado de `default_expiry_seconds`.
2. Un mensaje `OPEN` cuyo `expires_at` pasó DEBE marcarse `EXPIRED`.
3. Un mensaje `EXPIRED` con `critical: true` DEBE escalar y emitir `thalos.escalation.triggered`.
4. `ANSWERED`, `CLOSED` y `ESCALATED` son terminales y NO DEBEN expirar.

### 8.2. Quién ejecuta el barrido

**Sin demonio.** *(principio 11)*

**Decisión M-003: barrido acoplado MÁS expiración perezosa.** Las dos, porque resuelven cosas distintas.

**Barrido acoplado** — a operaciones que ya ocurren:

```txt
thalos message list
thalos feature work        (al abrir y al cerrar la espera)
thalos next
thalos status
```

1. El barrido DEBE ser idempotente.
2. El barrido NO DEBE fallar la operación que lo hospeda.
3. El barrido PUEDE invocarse explícitamente con `thalos message sweep`.

**Expiración perezosa** — al leer un mensaje individual:

4. Toda lectura de un mensaje DEBE evaluar su `expires_at` antes de devolverlo.
5. Un mensaje vencido NO DEBE mostrarse nunca con estado `OPEN`.

La regla 5 elimina una clase entera de defecto: que alguien mire un mensaje, vea que venció hace horas y lo vea `OPEN` porque el barrido todavía no pasó. El acoplado sigue haciendo falta: es lo único que escala los críticos vencidos que **nadie** mira.

La latencia del barrido acoplado ES aceptable: la escalación importa cuando alguien mira, y alguien mira cuando corre un comando.

### 8.3. Transiciones

```txt
OPEN       -> ACKED       recepción observada
OPEN       -> ANSWERED    llegó respuesta en el hilo
OPEN       -> EXPIRED     venció expires_at
ACKED      -> ANSWERED    llegó respuesta en el hilo
ACKED      -> EXPIRED     venció expires_at
EXPIRED    -> ESCALATED   critical = true
ANSWERED   -> CLOSED      cierre explícito
```

---

## 9. Configuración

### 9.1. `config/communication.yaml`

Hoy **no existe**, aunque `schemas/communication-config.schema.json` sí. Se crea, y el schema DEBE enmendarse para admitir el bloque `liveness`.

```yaml
version: 1

max_payload_bytes: 16384
default_expiry_seconds: 3600
escalate_expired_critical: true

channels:
  durable: repo_files
  operational: adapter_specific
  coordination: coordination_adapter

liveness:
  observe_interval_seconds: 5
  ack_timeout_seconds: 45
  blocked_confirm_samples: 3
  escalation_context_lines: 40
```

`escalation_context_lines` es el único lugar del subsistema donde se lee terminal, y es al escalar, no al decidir (5.6).

Respecto de la versión anterior de este documento desaparecen `quiet_grace_seconds`, `quiet_threshold_seconds` y `digest_lines`: la quietud dejó de ser una señal al medir que `state_change_seq` no la representa y que `process_alive` la vuelve innecesaria.

### 9.2. `config/reliability.yaml`

Hoy **no existe**, aunque `schemas/reliability-config.schema.json` sí. Se crea con los valores por defecto de la sección 35.3 del núcleo, más:

```yaml
  operations:
    agent_prompt:
      timeout_seconds: 900
      max_attempts: 3
      backoff:
        strategy: exponential
        base_ms: 1000
        max_ms: 15000
        jitter: full
    agent_observe:
      timeout_seconds: 10
      max_attempts: 2
```

`agent_prompt` pasa a `max_attempts: 3` con backoff porque `NOT_DELIVERED` es `TRANSIENT` (7.3) y reintentar un encargo que nunca llegó es seguro.

### 9.3. Destierro de valores cableados

| Valor | Dónde | Va a |
|---|---|---|
| `900000` | `boot.sh:158`, `feature.sh:412`, `feature.sh:487`, `message.sh:120` | `reliability.operations.agent_prompt.timeout_seconds` |
| `300000` | `feature.sh:567`, `feature.sh:571` | `reliability.operations.*` |
| `90` (gracia de quietud) | `feature.sh` bucle de espera | **se elimina**: la reemplaza `process_alive` |
| `5` (intervalo de sondeo) | `feature.sh` bucle de espera | `liveness.observe_interval_seconds` |
| `60` (ventana de `agent_prompt_stalled`) | `adapters/herdr/run.sh` | `liveness.ack_timeout_seconds` |

---

## 10. Eventos

**Enmienda al catálogo de la sección 41.5.** Se agregan:

```txt
thalos.agent.ack_confirmed
thalos.agent.ack_missing
thalos.agent.observed
thalos.agent.dead
thalos.agent.gone
thalos.agent.waiting_human
thalos.agent.turn_done

thalos.message.status_updated
thalos.message.escalated
```

1. `thalos.agent.observed` DEBE emitirse **solo al cambiar el veredicto**, no en cada muestreo.
2. Los eventos de vitalidad NO DEBEN referenciar artefactos del eje B.
3. `thalos.message.acked` y `thalos.message.expired` ya existen en el catálogo y ahora tienen productor.

---

## 11. CLI

**Enmienda a la sección 40.2.**

```txt
thalos agent observe <FEATURE>      los cuatro hechos, sin interpretar
thalos agent verdict <FEATURE>      el veredicto actual y su acción
thalos message status --text "..."  emitir STATUS_UPDATE (lo usa el agente)
thalos message sweep                barrido explícito de expiración
```

1. `thalos agent verdict` DEBE imprimir el nombre del veredicto como primer token de la salida, para que un loop pueda ramificar con un `case` sin parsear JSON.
2. El código de salida DEBE portar la **clase de acción**, no la identidad del veredicto, y DEBE respetar la tabla de la sección 40.4 del núcleo:

| Código | Clase | Veredictos |
|---|---|---|
| 0 | no hay nada que hacer | `ALIVE_WORKING`, `DONE` |
| 2 | precondition fallida | `UNOBSERVABLE` |
| 3 | plazo agotado | `EXPIRED` |
| 4 | escalación requerida | `WAITING_HUMAN` |
| 5 | hay que redespachar | `DEAD`, `GONE`, `FAILED` |

3. `thalos agent observe` NO DEBE mutar estado.

**Corrección respecto de la primera redacción de esta sección:** decía que el código de salida llevara el veredicto. Son siete veredictos y la sección 40.4 define seis códigos con significado fijo; meterlos ahí obligaba a inventar códigos o a redefinir los existentes, y un `2` que a veces significa "precondition fallida" y a veces "el agente terminó" no sirve para ramificar ni para nada. El nombre va por salida estándar, que es donde un nombre se puede leer.

---

## 12. Criterios de aceptación

Un criterio no verificable NO ES un criterio.

1. Matado el proceso del agente con el shell vivo, `thalos agent verdict` DEBE devolver `DEAD` en menos de `observe_interval_seconds * 2`, aunque el backend siga publicando `working`.
2. Cerrado el panel, DEBE devolver `GONE`, con mensaje distinto al de `DEAD`.
3. Un agente que termina su turno con ACK confirmado DEBE producir `DONE` sin esperar ninguna gracia.
4. **(M-004)** El mismo agente en `done` **sin** ACK confirmado DEBE producir `UNOBSERVABLE`, nunca `DONE`.
5. Un agente que entrega el artefacto y termina DEBE reportar terminación por avance y vitalidad `DONE`, y NO DEBE reportarse como fallo.
6. Un agente sin integración instalada DEBE producir `UNOBSERVABLE` y NUNCA un veredicto negativo.
7. Un agente que nunca emite `STATUS_UPDATE` DEBE poder completar un ciclo entero sin ningún veredicto negativo atribuible a su silencio.
8. **(M-002)** Con `prompt_agent` apuntado a un target inexistente, el paso DEBE registrar un error `TRANSIENT`, reintentar con backoff hasta `max_attempts` y NO DEBE consumir iteración de presupuesto.
9. **(M-005)** Una escalación por `WAITING_HUMAN` DEBE incluir `escalation_context_lines` líneas de salida del agente, y el veredicto DEBE ser idéntico con o sin ese texto.
10. **(M-001)** Un agente que imprime algo parecido a un status en la terminal, sin correr `thalos message status`, NO DEBE producir ningún `STATUS_UPDATE`.
11. **(M-003)** Un mensaje con `expires_at` vencido NO DEBE mostrarse nunca como `OPEN`, ni siquiera leído individualmente antes de cualquier barrido.
12. Un mensaje `EXPIRED` con `critical: true` DEBE producir `thalos.escalation.triggered`.
13. Un agente bloqueado un solo muestreo y luego trabajando NO DEBE producir `WAITING_HUMAN`.
14. `grep -rn '900000' cli/ adapters/` NO DEBE encontrar umbrales cableados.
15. Cambiar `observe_interval_seconds` en `config/communication.yaml` DEBE cambiar el comportamiento observable sin tocar código.

---

## 13. Ruta de implementación

Cada etapa DEBE dejar el sistema funcionando.

```txt
1. config/communication.yaml + config/reliability.yaml, con enmienda de schema   [HECHA]
   -> nadie los lee todavía; se validan solos

2. observe_agent en el adapter de herdr + en los adapters dry-run                [HECHA]
   -> capacidad nueva, sin consumidor

3. hooks/lib/liveness.py: la tabla de decisión de 5.2                            [HECHA]
   -> unidad pura, testeable sin agente

4. thalos agent observe / verdict                                                [HECHA]
   -> primer consumidor, sin tocar el bucle de espera

5. ACK observado en feature work y boot                                          [HECHA]
   -> aparece NOT_DELIVERED

6. reescritura del bucle de espera sobre veredictos
   -> se separa el eje A del eje B en el reporte, y `done` deja de costar 90s

7. expiración, sweep acoplado y STATUS_UPDATE
   -> se cierran 25.5.7/8/9

8. destierro de los literales cableados
   -> criterio de aceptación 11
```

Las etapas 1–4 no cambian ningún comportamiento existente. La 6 ES la que cambia el reporte que ve una persona, y DEBE hacerse cuando 1–5 estén verificadas.

---

## Anexo A. Evidencia medida

Banco de pruebas: cliente crudo del socket de herdr, sin Thalos y sin adapters. Workspaces descartables, cero tokens de modelo consumidos.

### A.1. `state_change_seq` solo marca transiciones

```txt
reporto working  -> status=working  seq=187
reporto working  -> status=working  seq=187
reporto working  -> status=working  seq=187
reporto blocked  -> status=blocked  seq=188
```

**Conclusión:** no sirve como latido. Sirve para detectar transiciones, que es lo que usa el ACK.

### A.2. `done` no es emitible

```txt
reporto done -> RECHAZADO
   invalid request: unknown variant `done`,
   expected one of `idle`, `working`, `blocked`, `unknown`
```

**Conclusión:** ninguna implementación puede hacer que Thalos emita `done`. Solo puede observarlo.

### A.3. `done` lo deriva herdr de todo `idle`

```txt
idle en frío       -> done
working -> idle    -> done
blocked -> idle    -> done
idle -> idle       -> done
```

Con y sin `agent_session_id`. Estable durante al menos 150 segundos.

**Conclusión:** Thalos ya tiene la señal de terminación de turno y hoy la ignora.

### A.4. Lecturas de terminal

`read --source recent-unwrapped` devuelve contenido estable entre lecturas sucesivas en paneles de agente (550 bytes en tres lecturas), y vacío en shells sin integración. No es una vista delta.

**Conclusión:** no hay defecto en el `read_agent` actual. El digest de terminal que proponía la versión anterior de este documento es innecesario.

### A.5. El agente congelado

```txt
agente trabajando        status=working  seq=207  procs=['sleep(6597)']  fg_pgid=6597
-- SIGKILL solo al agente; el shell sigue vivo --
t+1s                     status=working  seq=207  procs=['zsh(6105)']    fg_pgid=6105
t+3s                     status=working  seq=207  procs=['zsh(6105)']    fg_pgid=6105
t+10s                    status=working  seq=207  procs=['zsh(6105)']    fg_pgid=6105
```

**Conclusión:** el estado publicado miente indefinidamente. `foreground_process_group_id == shell_pid` lo detecta en menos de 1 segundo.

### A.6. Muerte del shell

```txt
-- SIGKILL al shell --
t+1s   pane_not_found; el panel desaparece de pane.list y de agent.list
```

**Conclusión:** `GONE` es detectable de inmediato y es más fuerte que `DEAD`.

### A.7. Validación contra agentes reales

```txt
w5:p2  shell=31699  fg_pgid=35945  vivo  procs=['node',...,'engram','opencode']
w7:p2  shell=31730  fg_pgid=35950  vivo  procs=['node',...,'engram','opencode']
lab    shell=6105   fg_pgid=6105   MUERTO procs=['zsh']
```

**Conclusión:** la regla discrimina correctamente en ambos sentidos.

---

## 14. Decisiones

| Id | Decisión | Resolución | Dónde |
|---|---|---|---|
| M-001 | ¿`STATUS_UPDATE` por parseo de terminal o solo por CLI explícita? | **Solo CLI explícita.** Un canal que por diseño nunca resta no justifica una heurística frágil. | 6.2.4 |
| M-002 | ¿`NOT_DELIVERED` es veredicto o clase de error? | **Clase `TRANSIENT` de la 35.1.** Hereda backoff, `max_attempts`, `ErrorRecord` e idempotency key sin reimplementarlos. | 7.3 |
| M-003 | ¿Barrido acoplado o expiración perezosa? | **Las dos.** El perezoso mata "vencido pero `OPEN`"; el acoplado escala lo que nadie mira. | 8.2 |
| M-004 | Los agentes de larga inactividad publican `idle` y no `done`; no se pudo reproducir la diferencia. | **Se elude el misterio:** `done` e `idle` se clasifican juntos y se desambiguan por `ack_confirmed`, no por el valor. | 5.1, 5.2 |
| M-005 | `blocked` con proceso vivo mezcla `permission.asked` con `session.error`. | **Escalar de más con evidencia adjunta, sin interpretarla.** La persona decide en dos segundos lo que una heurística adivina mal. | 5.6 |

### 14.1. Sigue abierto

Nada bloquea la implementación. Queda como observación sin resolver, ahora inocua:

- Por qué un agente de larga inactividad publica `idle` en vez de `done`. No se observó decaimiento en 150 segundos, con y sin `agent_session_id`. La decisión M-004 hace que la respuesta ya no cambie ningún comportamiento.

---

## 15. Changelog

### 0.0.1

- Se separan vitalidad y avance como ejes ortogonales, y se prohíbe medir uno con el instrumento del otro.
- Se acota el alcance: el subsistema detecta muerte, no futilidad.
- Se define el canal observado como REQUERIDO y el declarado como OPCIONAL, con regla de monotonía positiva que preserva 25.1.1.a.
- Se agrega `observe_agent` al `ExecutionAdapter`, sobre cuatro hechos y sin lectura de terminal.
- Se establece que un hecho del sistema operativo prevalece sobre un estado reportado, con `process_alive` como señal rectora.
- Se documenta que `state_change_seq` no es un latido y que `done` no es emitible sino derivado.
- Se define la tabla de decisión de siete veredictos y su precedencia.
- Se define el ACK observado como transición y el veredicto `NOT_DELIVERED`.
- Se implementan las reglas 25.5.7/8/9, escritas desde 0.0.4 y sin productor.
- Se crean `config/communication.yaml` y `config/reliability.yaml`, cuyos schemas existían sin archivo.
- Se descartan por medición el digest de terminal, la quietud y sus tres umbrales.
- Se agrega el anexo A con la evidencia de los siete experimentos.
- Se resuelven las cinco decisiones abiertas M-001 a M-005 (sección 14).
- Se agrega `ack_confirmed` como cuarta entrada de la decisión, lo que permite clasificar `done` e `idle` juntos sin depender del valor crudo.
- `NOT_DELIVERED` sale de la tabla de veredictos y pasa a ser clase de error `TRANSIENT`.
- La escalación por `WAITING_HUMAN` adjunta contexto de terminal sin interpretarlo, único punto del subsistema donde se lee la pantalla.
- Se agrega `process_observed` (4.3.1), surgido al implementar la etapa 2: no poder mirar el proceso NO es estar muerto, y afirmarlo mataría agentes sanos por un fallo de lectura.
- El piso de herdr sube a `>=0.7.5`, que es la versión donde se verificó que `pane.process_info` existe y devuelve `foreground_process_group_id`.
