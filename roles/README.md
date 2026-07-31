# roles/

Instrucciones que se inyectan como contexto cuando un agente ejecuta un rol.

Esta carpeta es la mitad **blanda** del par de enforcement (mecanismos 9 y 10 de [`system/00-enforcement.md`](../system/00-enforcement.md)). Por sí sola no fuerza nada. Funciona porque cada rol está atado a tres cosas que sí se verifican:

```txt
roles/<rol>.md        -> le dice al modelo qué hacer          (blando)
config/roles.yaml     -> declara scope, herramientas, salida  (contrato)
schemas/<salida>.json -> rechaza la salida inválida           (duro)
```

Leer el `.md` sin los otros dos es leer un consejo.

---

## Los cinco roles

| Rol | Entregable obligatorio | Escribe en | Tier mínimo |
|---|---|---|---|
| [`SpecAssistant`](spec-assistant.md) | `spec/manifest.yaml` | `spec/**` | deep |
| [`Planner`](planner.md) | `orchestration/program-plan.json` | `orchestration/program-plan.json` | deep |
| [`FeatureLead`](feature-lead.md) | `feature-state.json` | `orchestration/features/**` | — |
| [`Developer`](developer.md) | `task-result.json` | `src/**`, `tests/**` | — |
| [`Reviewer`](reviewer.md) | `review.json` | `orchestration/reports/**` | balanced |

Tier mínimo `—` significa `null`: sin mínimo propio, se resuelve por esfuerzo y riesgo.

---

## Cómo está escrito cada archivo

No son descripciones de puesto. Están estructurados para reducir la deriva del modelo:

**Entregable primero.** Antes que cualquier otra cosa, qué archivo tiene que producir y contra qué schema valida. Es lo único que el sistema mira.

**Espacio negativo explícito.** Cada rol declara qué *no* puede escribir y qué *no* puede hacer. Los modelos derivan hacia hacer de más; la prohibición hay que escribirla, no asumirla.

**Condiciones de parada.** Cada rol termina con "cuándo escalar". Un rol que no sabe cuándo parar, adivina — y adivinar es más caro que preguntar.

**Ejemplos de mal y bien.** Donde el criterio es difuso (un finding de review, un criterio de aceptación), hay un par concreto. Es más barato reconocer que recordar.

---

## Las tres restricciones que hacen esto funcionar

**1. El Developer no puede afirmar que las pruebas pasaron.**
`task-result.schema.json` no tiene campo para eso. Un `status: done` exige `test_report_refs` no vacío, y esos reportes los produce el adapter de ejecución. La afirmación del modelo no cuenta; el `exit_code` sí.

**2. El Reviewer tiene que declarar contra qué revisó.**
`review.schema.json` exige `spec_refs_checked` con al menos un elemento. No se puede forzar que la revisión sea buena; sí se puede forzar que sea trazable a criterios concretos del spec.

**3. El SpecAssistant no puede aprobar el spec.**
`spec-manifest.schema.json` exige `approved_by`, `approved_at` y `digest` cuando `status: approved`. El rol no puede producir esos valores. La aprobación queda del lado humano por construcción, no por buena voluntad.

---

## Separación de roles

Quien implementa no revisa. Quien coordina no mergea. Quien escribe el spec no lo aprueba.

No es burocracia: es eliminar el conflicto de interés dentro de un mismo contexto. Un modelo que implementó algo y después lo revisa va a encontrar menos problemas que uno que llega sin haberlo escrito.
