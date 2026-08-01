"""Verifica que los schemas de Talos rechacen lo que deben rechazar.

Un schema que acepta todo no es un mecanismo de enforcement.
Cada caso NEGATIVO corresponde a un requisito normativo de la spec.
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator

SCHEMAS = pathlib.Path(__file__).resolve().parent.parent / "schemas"


def load(name):
    return json.loads((SCHEMAS / f"{name}.schema.json").read_text())


# (schema, descripcion, documento, debe_validar, requisito_de_la_spec)
CASES = [
    # --- spec-manifest: approved exige evidencia de aprobacion (28.5, 28.9)
    ("spec-manifest", "draft sin aprobacion", {
        "version": "1", "title": "Producto", "status": "draft", "entry": "SPEC.md",
        "sections": {k: f"{k}.md" for k in
                     ["problem", "goal", "non_goals", "users", "requirements",
                      "acceptance_criteria", "constraints", "risks", "test_plan"]},
    }, True, "spec en draft no requiere aprobacion"),

    ("spec-manifest", "approved SIN approved_by ni digest", {
        "version": "1", "title": "Producto", "status": "approved", "entry": "SPEC.md",
        "sections": {k: f"{k}.md" for k in
                     ["problem", "goal", "non_goals", "users", "requirements",
                      "acceptance_criteria", "constraints", "risks", "test_plan"]},
    }, False, "28.5: approved exige aprobacion humana registrada"),

    ("spec-manifest", "falta la seccion test_plan", {
        "version": "1", "title": "Producto", "status": "draft", "entry": "SPEC.md",
        "sections": {k: f"{k}.md" for k in
                     ["problem", "goal", "non_goals", "users", "requirements",
                      "acceptance_criteria", "constraints", "risks"]},
    }, False, "15.3: spec minimo aceptable exige las 9 secciones"),

    # --- extension-registry: capacidad requerida sin implementacion (37.4.3)
    ("extension-registry", "todas las capacidades requeridas ligadas", {
        "version": 1,
        "capabilities": {
            "FileSystemAdapter": {"implementation": "talos.adapter.filesystem"},
            "ModelProviderAdapter": {"implementation": "talos.adapter.model"},
            "ExecutionAdapter": {"implementation": "talos.adapter.dryrun"},
            "CoordinationAdapter": {"implementation": "talos.adapter.dryrun"},
            "CIAdapter": {"implementation": "talos.adapter.dryrun"},
        },
    }, True, "37.4.3: una implementacion por capacidad requerida"),

    ("extension-registry", "SIN ExecutionAdapter", {
        "version": 1,
        "capabilities": {
            "FileSystemAdapter": {"implementation": "talos.adapter.filesystem"},
            "ModelProviderAdapter": {"implementation": "talos.adapter.model"},
            "CoordinationAdapter": {"implementation": "talos.adapter.dryrun"},
            "CIAdapter": {"implementation": "talos.adapter.dryrun"},
        },
    }, False, "37.4.3: cero implementaciones de capacidad requerida falla"),

    ("extension-registry", "MemoryAdapter ausente (opcional)", {
        "version": 1,
        "capabilities": {
            "FileSystemAdapter": {"implementation": "talos.adapter.filesystem"},
            "ModelProviderAdapter": {"implementation": "talos.adapter.model"},
            "ExecutionAdapter": {"implementation": "talos.adapter.herdr"},
            "CoordinationAdapter": {"implementation": "talos.adapter.github"},
            "CIAdapter": {"implementation": "talos.adapter.ci"},
        },
    }, True, "37.4.3: capacidad opcional puede tener cero implementaciones"),

    # --- policy: no relajable (31.1, 21.5.4)
    ("policy-config", "policy estricta", {
        "version": 1,
        "merge": {"require_green_checks": True, "require_mergeable": True,
                  "auto_merge_allowed": False},
        "human_approval": {"required_for_risk": ["critical"]},
        "constraints": {"max_parallel_features": 1},
    }, True, "policy valida"),

    ("policy-config", "intenta desactivar checks verdes", {
        "version": 1,
        "merge": {"require_green_checks": False, "require_mergeable": True,
                  "auto_merge_allowed": True},
        "human_approval": {"required_for_risk": ["critical"]},
        "constraints": {},
    }, False, "31.1: checks verdes no es relajable"),

    ("policy-config", "quita critical de aprobacion humana", {
        "version": 1,
        "merge": {"require_green_checks": True, "require_mergeable": True,
                  "auto_merge_allowed": False},
        "human_approval": {"required_for_risk": ["high"]},
        "constraints": {},
    }, False, "21.5.4: riesgo critical siempre exige humano"),

    # --- routing: dominio de tier (20.4, 20.5)
    ("routing-config", "routing valido", {
        "version": 1, "default_tier": "balanced",
        "effort_to_tier": {"trivial": "fast", "low": "fast", "medium": "balanced",
                           "high": "deep", "critical": "deep"},
        "risk_to_tier": {"low": "fast", "medium": "balanced", "high": "deep",
                         "critical": "deep"},
    }, True, "20.6: mapeos completos"),

    ("routing-config", "usa 'dynamic' como tier", {
        "version": 1, "default_tier": "dynamic",
        "effort_to_tier": {"trivial": "fast", "low": "fast", "medium": "balanced",
                           "high": "deep", "critical": "deep"},
        "risk_to_tier": {"low": "fast", "medium": "balanced", "high": "deep",
                         "critical": "deep"},
    }, False, "20.4: dynamic no pertenece al dominio ordenado"),

    # --- roles: role_minimum_tier null es valido (20.4)
    ("roles-config", "Developer con minimo null", {
        "version": 1,
        "roles": {
            "SpecAssistant": {"role_minimum_tier": "deep", "write_paths": ["spec/**"],
                              "output_artifact": None},
            "Planner": {"role_minimum_tier": "deep", "write_paths": ["orchestration/program-plan.json"],
                        "output_artifact": {"schema": "program-plan", "path": "orchestration/program-plan.json"}},
            "FeatureLead": {"role_minimum_tier": None, "write_paths": ["orchestration/features/**"],
                            "output_artifact": {"schema": "feature-state", "path": "orchestration/features/{feature_id}/feature-state.json"}},
            "Developer": {"role_minimum_tier": None, "write_paths": ["src/**", "tests/**"],
                          "output_artifact": None},
            "Reviewer": {"role_minimum_tier": "balanced", "write_paths": ["orchestration/reports/**"],
                         "output_artifact": {"schema": "review", "path": "orchestration/reports/{feature_id}/review.json"}},
        },
    }, True, "20.4: null significa sin minimo propio"),

    ("roles-config", "rol sin write_paths declarados", {
        "version": 1,
        "roles": {
            "SpecAssistant": {"role_minimum_tier": "deep", "output_artifact": None},
            "Planner": {"role_minimum_tier": "deep", "write_paths": [], "output_artifact": None},
            "FeatureLead": {"role_minimum_tier": None, "write_paths": [], "output_artifact": None},
            "Developer": {"role_minimum_tier": None, "write_paths": [], "output_artifact": None},
            "Reviewer": {"role_minimum_tier": "balanced", "write_paths": [], "output_artifact": None},
        },
    }, False, "19.1: todo rol declara su scope de escritura"),

    # --- system-config: serial implica 1 feature (32.4.3)
    ("system-config", "serial con 1 feature", {
        "version": 1, "execution_mode": "dry-run-only", "install_level": "L1",
        "concurrency": {"mode": "serial", "max_parallel_features": 1},
    }, True, "modo serial coherente"),

    ("system-config", "serial con 4 features", {
        "version": 1, "execution_mode": "dry-run-only", "install_level": "L1",
        "concurrency": {"mode": "serial", "max_parallel_features": 4},
    }, False, "32.4: serial implica max_parallel_features = 1"),

    # --- evidence: digest y verificabilidad (23.3)
    ("evidence", "CheckRunSet verificable", {
        "id": "ev-01HZ", "kind": "CheckRunSet", "schema_version": 1,
        "run_id": "r-001", "produced_by": "adapter:talos.adapter.ci",
        "produced_at": "2026-07-30T12:00:00Z",
        "digest": "sha256:" + "a" * 64, "verifiable": True, "payload": {},
    }, True, "evidencia de adapter es verificable"),

    ("evidence", "digest con formato invalido", {
        "id": "ev-01HZ", "kind": "CheckRunSet", "schema_version": 1,
        "run_id": "r-001", "produced_by": "adapter:talos.adapter.ci",
        "produced_at": "2026-07-30T12:00:00Z",
        "digest": "abc123", "verifiable": True,
    }, False, "23.3.3: toda evidencia exige digest sha256"),

    ("evidence", "kind inventado", {
        "id": "ev-01HZ", "kind": "TotallyFineTrustMe", "schema_version": 1,
        "run_id": "r-001", "produced_by": "role:Developer",
        "produced_at": "2026-07-30T12:00:00Z",
        "digest": "sha256:" + "a" * 64, "verifiable": False,
    }, False, "23.4: kind debe pertenecer al catalogo"),

    # --- event: seq obligatorio (41.2)
    ("event", "evento con seq", {
        "id": "ev-01HZ", "seq": 42, "schema_version": 1,
        "type": "talos.feature.merged", "ts": "2026-07-30T12:00:00Z",
        "run_id": "r-001", "project": "p", "actor": "core:MergeGate",
    }, True, "41.2: evento con secuencia"),

    ("event", "evento SIN seq", {
        "id": "ev-01HZ", "schema_version": 1,
        "type": "talos.feature.merged", "ts": "2026-07-30T12:00:00Z",
        "run_id": "r-001", "project": "p", "actor": "core:MergeGate",
    }, False, "41.2: seq es obligatorio para reconstruir estado"),

    ("event", "tipo fuera del namespace talos", {
        "id": "ev-01HZ", "seq": 1, "schema_version": 1,
        "type": "custom.thing.happened", "ts": "2026-07-30T12:00:00Z",
        "run_id": "r-001", "project": "p", "actor": "core",
    }, False, "41.4: namespace talos obligatorio"),

    # --- gate-result: fail exige razones (24.4)
    ("gate-result", "gate pass con razones", {
        "gate": "MERGE_GATE", "decision": "pass",
        "reasons": [{"code": "CHECKS_GREEN", "status": "pass"}],
        "evaluated_at": "2026-07-30T12:00:00Z", "evaluator_version": "0.0.6",
    }, True, "24.2: salida valida"),

    ("gate-result", "gate sin razones", {
        "gate": "MERGE_GATE", "decision": "fail", "reasons": [],
        "evaluated_at": "2026-07-30T12:00:00Z", "evaluator_version": "0.0.6",
    }, False, "24.4.4: todo fail puebla reasons"),

    # --- message: limite de payload (25.5)
    ("message", "payload dentro del limite", {
        "id": "m1", "thread_id": "t1", "type": "TASK_REQUEST",
        "from": "FeatureLead", "to": "Developer", "state": "OPEN",
        "created_at": "2026-07-30T12:00:00Z", "payload_bytes": 2048,
    }, True, "25.5.1: payload bajo 16 KB"),

    ("message", "payload de 32 KB", {
        "id": "m1", "thread_id": "t1", "type": "TASK_REQUEST",
        "from": "FeatureLead", "to": "Developer", "state": "OPEN",
        "created_at": "2026-07-30T12:00:00Z", "payload_bytes": 32768,
    }, False, "25.5.1: limite duro de 16 KB"),

    # --- locks: TTL obligatorio (32.2)
    ("locks", "lease con TTL y generation", {
        "schema_version": 1,
        "leases": [{
            "lease_id": "lk-1", "resource": "branch:main", "owner_feature": "F001",
            "owner_run": "r-001", "reason": "merge", "acquired_at": "2026-07-30T12:00:00Z",
            "expires_at": "2026-07-30T12:05:00Z", "ttl_seconds": 300, "generation": 1,
        }],
    }, True, "32.1: lease completo"),

    ("locks", "lock sin expiracion", {
        "schema_version": 1,
        "leases": [{
            "lease_id": "lk-1", "resource": "branch:main", "owner_feature": "F001",
            "owner_run": "r-001", "reason": "merge", "acquired_at": "2026-07-30T12:00:00Z",
            "generation": 1,
        }],
    }, False, "32.2.2: todo lease exige TTL y expires_at"),

    # --- review: salida estructurada del rol (enforcement 7)
    ("review", "review con refs de spec", {
        "schema_version": 1, "feature_id": "F001", "reviewer": "Reviewer",
        "created_at": "2026-07-30T12:00:00Z", "verdict": "approve",
        "spec_refs_checked": ["acceptance.md#AC-1"], "findings": [], "blocker_count": 0,
    }, True, "salida estructurada valida"),

    ("review", "review sin declarar contra que reviso", {
        "schema_version": 1, "feature_id": "F001", "reviewer": "Reviewer",
        "created_at": "2026-07-30T12:00:00Z", "verdict": "approve",
        "spec_refs_checked": [], "findings": [], "blocker_count": 0,
    }, False, "enforcement 7: obliga a declarar los criterios revisados"),

    # --- adapter-manifest: idempotencia en mutantes (38.2)
    ("adapter-manifest", "operacion mutante con idempotencia", {
        "id": "talos.adapter.github", "version": "0.1.0", "api_version": "talos/v0",
        "implements": "CoordinationAdapter", "supports_dry_run": True,
        "health_check": {"command": "gh auth status"},
        "operations": [{"name": "open_pr", "mutating": True, "idempotency": "required"}],
    }, True, "38.2.1: mutante declara idempotencia"),

    ("adapter-manifest", "operacion mutante SIN idempotencia", {
        "id": "talos.adapter.github", "version": "0.1.0", "api_version": "talos/v0",
        "implements": "CoordinationAdapter", "supports_dry_run": True,
        "health_check": {"command": "gh auth status"},
        "operations": [{"name": "open_pr", "mutating": True}],
    }, False, "38.2.1: toda operacion mutante declara idempotencia"),

    # --- program-plan: id de feature y tier (29)
    ("program-plan", "plan valido", {
        "schema_version": 1, "project": "p", "spec_digest": "sha256:" + "b" * 64,
        "created_at": "2026-07-30T12:00:00Z",
        "features": [{"id": "F001", "title": "Auth", "effort": "medium", "risk": "high",
                      "capability_tier": "deep", "human_approval_required": True}],
    }, True, "29.2: plan valido"),

    ("program-plan", "plan sin features", {
        "schema_version": 1, "project": "p", "spec_digest": "sha256:" + "b" * 64,
        "created_at": "2026-07-30T12:00:00Z", "features": [],
    }, False, "29: un plan sin features no es un plan"),

    # --- task-result: el Developer no puede afirmar que las pruebas pasaron
    ("task-result", "done con referencia a reporte de pruebas", {
        "schema_version": 1, "feature_id": "F001", "task_id": "T1",
        "status": "done", "declared_scope": ["src/auth/**"],
        "files_changed": ["src/auth/verify.ts"],
        "test_report_refs": ["ev-01HZ"],
        "created_at": "2026-07-30T12:00:00Z",
    }, True, "30.2.4: responde con evidencia"),

    ("task-result", "done SIN reporte de pruebas", {
        "schema_version": 1, "feature_id": "F001", "task_id": "T1",
        "status": "done", "declared_scope": ["src/auth/**"],
        "files_changed": ["src/auth/verify.ts"],
        "created_at": "2026-07-30T12:00:00Z",
    }, False, "30.4.2: ningun rol agente declara pass sin evidencia de adapter"),

    ("task-result", "done sin archivos cambiados", {
        "schema_version": 1, "feature_id": "F001", "task_id": "T1",
        "status": "done", "declared_scope": ["src/auth/**"],
        "files_changed": [], "test_report_refs": ["ev-01HZ"],
        "created_at": "2026-07-30T12:00:00Z",
    }, False, "una task done sin cambios no implemento nada"),

    ("task-result", "blocked con blocker concreto", {
        "schema_version": 1, "feature_id": "F001", "task_id": "T1",
        "status": "blocked", "declared_scope": ["src/auth/**"],
        "files_changed": [],
        "blockers": [{"summary": "El scope no incluye el modelo de sesion"}],
        "created_at": "2026-07-30T12:00:00Z",
    }, True, "blocked es un resultado valido"),

    ("task-result", "blocked sin decir por que", {
        "schema_version": 1, "feature_id": "F001", "task_id": "T1",
        "status": "blocked", "declared_scope": ["src/auth/**"],
        "files_changed": [], "blockers": [],
        "created_at": "2026-07-30T12:00:00Z",
    }, False, "un blocker sin causa no es accionable"),

    # --- rules-registry: el sistema no puede mentir sobre su propio enforcement
    ("rules-registry", "DEBE con respaldo de schema", {
        "version": 1, "rules": [{
            "id": "R-TEST-001", "topic": "roles", "nivel_normativo": "DEBE",
            "requisito": "El artefacto debe validar contra su schema declarado.",
            "mecanismo": 1, "implementacion": ["schemas/x.json"], "spec_ref": "s.md"}],
    }, True, "00-enforcement 4: un DEBE nombra su mecanismo"),

    ("rules-registry", "DEBE apoyado solo en un .md", {
        "version": 1, "rules": [{
            "id": "R-TEST-002", "topic": "roles", "nivel_normativo": "DEBE",
            "requisito": "El agente debe portarse bien y seguir las instrucciones.",
            "mecanismo": 10, "estrategia_guia": ["contexto_minimo"], "spec_ref": "s.md"}],
    }, False, "00-enforcement 4.2: fuerza blanda no puede redactarse como DEBE"),

    ("rules-registry", "NO_DEBE apoyado solo en contexto de rol", {
        "version": 1, "rules": [{
            "id": "R-TEST-003", "topic": "roles", "nivel_normativo": "NO_DEBE",
            "requisito": "El agente no debe salirse del alcance asignado nunca.",
            "mecanismo": 9, "estrategia_guia": ["contexto_minimo"], "spec_ref": "s.md"}],
    }, False, "00-enforcement 3.1: mecanismos 9-10 son consultivos"),

    ("rules-registry", "RECOMENDADO blando con estrategia", {
        "version": 1, "rules": [{
            "id": "R-TEST-004", "topic": "roles", "nivel_normativo": "RECOMENDADO",
            "requisito": "El agente escribe codigo parecido al que ya esta.",
            "mecanismo": 10, "estrategia_guia": ["contexto_minimo"], "spec_ref": "s.md"}],
    }, True, "00-enforcement 7: lo no forzable se guia"),

    ("rules-registry", "blando sin estrategia de guia", {
        "version": 1, "rules": [{
            "id": "R-TEST-005", "topic": "roles", "nivel_normativo": "RECOMENDADO",
            "requisito": "El agente escribe codigo parecido al que ya esta.",
            "mecanismo": 10, "spec_ref": "s.md"}],
    }, False, "00-enforcement 7.1: todo requisito no forzable declara estrategia"),

    ("rules-registry", "mecanismo ejecutable sin nombrar quien lo ejecuta", {
        "version": 1, "rules": [{
            "id": "R-TEST-006", "topic": "roles", "nivel_normativo": "DEBE",
            "requisito": "El artefacto debe validar contra su schema declarado.",
            "mecanismo": 1, "spec_ref": "s.md"}],
    }, False, "00-enforcement 4: mecanismos 1-8 nombran su implementacion"),

    ("task-result", "intenta reportar pruebas como texto libre", {
        "schema_version": 1, "feature_id": "F001", "task_id": "T1",
        "status": "done", "declared_scope": ["src/auth/**"],
        "files_changed": ["src/auth/verify.ts"],
        "test_report_refs": ["ev-01HZ"],
        "tests_passed": True,
        "created_at": "2026-07-30T12:00:00Z",
    }, False, "additionalProperties false: no hay campo para afirmar resultados"),
]



def check_evidence_id_patterns():
    """Todo schema que hable de ids de evidencia tiene que usar el MISMO patron.

    task-result.schema.json usaba ^ev-[A-Za-z0-9]+$ mientras evidence y event
    usaban ^ev-[A-Za-z0-9][A-Za-z0-9-]*$. Un id valido segun evidence.schema
    podia referenciarse desde un evento y no desde un task-result: la cadena se
    cortaba justo donde el Developer tiene que citar la medicion que lo habilita
    a declararse done.
    """
    import re as _re
    encontrados = {}
    for path in sorted(SCHEMAS.glob("*.json")):
        for m in _re.finditer(r'"\^ev-[^"]*"', path.read_text()):
            encontrados.setdefault(m.group(0), []).append(path.name)
    return encontrados


def main():
    failures = []
    passed = 0
    for schema_name, desc, doc, should_pass, requisito in CASES:
        validator = Draft202012Validator(load(schema_name))
        errors = list(validator.iter_errors(doc))
        actually_passed = not errors
        if actually_passed == should_pass:
            passed += 1
            mark = "valida  " if should_pass else "RECHAZA "
            print(f"  ok   [{schema_name}] {mark} {desc}")
        else:
            failures.append((schema_name, desc, should_pass, errors, requisito))
            print(f"  FALLA[{schema_name}] {desc}")
            print(f"       esperado: {'valida' if should_pass else 'rechaza'}")
            print(f"       requisito: {requisito}")
            for e in errors[:2]:
                print(f"       -> {e.message[:120]}")

    # Coherencia entre schemas: todo el que hable de ids de evidencia tiene que
    # usar el MISMO patron, o la cadena de referencias se corta.
    patrones = check_evidence_id_patterns()
    if len(patrones) <= 1:
        passed += 1
        print(f"  ok   [cross] los {sum(len(v) for v in patrones.values())} "
              f"schemas que citan ids de evidencia usan un unico patron")
    else:
        failures.append(("cross", "patrones de id de evidencia divergentes",
                         True, [], "un id valido debe poder citarse desde cualquier schema"))
        print("  FALLA[cross] hay mas de un patron de id de evidencia")
        for pat, files in patrones.items():
            print(f"       {pat} -> {files}")

    print()
    # +1 por el check de coherencia entre schemas, que no es un caso de CASES.
    print(f"{passed}/{len(CASES) + 1} casos correctos")
    if failures:
        print(f"{len(failures)} schemas NO enforzan su requisito")
        return 1
    print("Todos los schemas rechazan lo que deben rechazar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
