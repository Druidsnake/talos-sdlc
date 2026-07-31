# schemas/

Contratos estructurales de Talos. **Este es el único mecanismo de enforcement duro que funciona en cualquier nivel de instalación** (ver [`system/00-enforcement.md`](../system/00-enforcement.md), mecanismo 1).

Un schema no describe un artefacto: lo **rechaza** cuando no cumple. Esa diferencia es la razón por la que esta carpeta existe.

---

## Qué se enforza acá

Cada schema traduce requisitos normativos de [`talos-0.0.6.md`](../talos-0.0.6.md) en validación ejecutable, sin modelo de por medio.

| Schema | Requisito que vuelve verificable |
|---|---|
| `spec-manifest` | Un spec `approved` sin `approved_by` y `digest` es inválido (§28.5, §28.9) |
| `extension-registry` | Cero implementaciones de una capacidad REQUERIDA es inválido (§37.4.3) |
| `policy-config` | `require_green_checks: false` es inválido; `critical` siempre exige humano (§31.1, §21.5.4) |
| `routing-config` | `dynamic` y `none` no pertenecen al dominio de tier (§20.4) |
| `roles-config` | Todo rol declara su scope de escritura y su artefacto de salida (§19.1) |
| `system-config` | `serial` con `max_parallel_features > 1` es inválido (§32.4) |
| `evidence` | Todo artefacto de evidencia exige `digest` sha256 y un `kind` del catálogo (§23.3, §23.4) |
| `event` | Un evento sin `seq` es inválido: sin secuencia no hay reconstrucción (§41.2) |
| `gate-result` | Un `fail` sin `reasons` es inválido (§24.4) |
| `message` | Payload sobre 16 KB es inválido (§25.5) |
| `locks` | Un lock sin `ttl_seconds` ni `expires_at` es inválido (§32.2) |
| `review` | Un review sin `spec_refs_checked` es inválido |
| `task-result` | Un `status: done` sin `test_report_refs` es inválido: el Developer no puede afirmar que las pruebas pasaron |
| `adapter-manifest` | Una operación mutante sin `idempotency` declarada es inválida (§38.2) |
| `program-plan` | Un plan sin features es inválido (§29) |

---

## La palanca

`review.schema.json` es el ejemplo más claro del principio de `system/00-enforcement.md` §7:

> No se puede forzar que el Reviewer revise **bien**. Sí se puede forzar que produzca un `review.json` válido con `spec_refs_checked` no vacío.

El modelo decide el contenido. La estructura deja de ser opcional. Y la estructura se valida sin el modelo.

---

## Verificar

```bash
python3 -m venv .venv && .venv/bin/pip install jsonschema && .venv/bin/python tests/test_schemas.py
```

39 casos: cada uno afirma que un documento válido pasa **y** que su contraparte inválida se rechaza. Un schema que solo acepta cosas buenas no prueba nada; hay que probar que bloquea las malas.

---

## Versionado

El `$id` de un schema versiona **el schema**, no el documento que lo contiene. Los nueve schemas de artefactos siguen en `0.0.5` porque no cambiaron; los introducidos en 0.0.6 llevan `0.0.6`. Un `$id` solo se incrementa cuando la estructura cambia.

---

## Inventario

**Artefactos runtime** — `evidence`, `gate-result`, `event`, `program-plan`, `feature-state`, `task-result`, `review`, `locks`, `message`, `runtime-meta`

**Manifiestos** — `system-manifest`, `project-manifest`, `spec-manifest`, `adapter-manifest`, `plugin-manifest`

**Configuración** — `system-config`, `models-config`, `roles-config`, `routing-config`, `policy-config`, `communication-config`, `preconditions-config`, `reliability-config`, `extension-registry`
