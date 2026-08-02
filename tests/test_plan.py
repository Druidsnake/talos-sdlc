"""Auditoria de PLAN_GATE. Ver talos-0.0.7.md seccion 29.

Paso 7 de la ruta de implementacion (seccion 51).

Verifica rechazo, no solo aceptacion. Un plan con un ciclo, con una dependencia
colgada o con un riesgo critical que no pide humano tiene que fallar el gate;
si pasa, el gate no es una barrera sino un adorno.
"""
import json
import pathlib
import subprocess
import sys
import tempfile

from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"

sys.path.insert(0, str(ROOT / "hooks" / "lib"))
import plan as plan_lib  # noqa: E402

DIGEST = "sha256:" + "a" * 64


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def feature(fid, risk="low", tier="fast", human=False, deps=None, effort="medium"):
    return {
        "id": fid, "title": f"feature {fid}", "effort": effort, "risk": risk,
        "capability_tier": tier, "human_approval_required": human,
        "depends_on": deps or [],
    }


def make_plan(features, digest=DIGEST):
    return {
        "schema_version": 1, "project": "prueba", "spec_digest": digest,
        "created_by": "role:Planner", "created_at": "2026-07-31T00:00:00Z",
        "features": features,
    }


def manifest(status="approved", digest=DIGEST):
    d = pathlib.Path(tempfile.mkdtemp())
    p = d / "manifest.yaml"
    p.write_text(f'version: "1"\nstatus: {status}\ndigest: "{digest}"\n')
    return str(p)


def codes(reasons):
    return {c: s for c, s, _ in reasons}


def main():
    results = []
    ok_manifest = manifest()

    # ---------- el plan sano pasa ----------

    sano = make_plan([
        feature("F001"),
        feature("F002", risk="critical", tier="deep", human=True, deps=["F001"]),
        feature("F003", risk="high", tier="balanced", deps=["F001"]),
    ])
    decision, reasons = plan_lib.evaluate(sano, ok_manifest)
    results.append(check(
        "un plan coherente pasa PLAN_GATE",
        decision == "pass", f"{[r for r in reasons if r[1] == 'fail']}",
    ))

    # El plan sano tambien tiene que validar contra su schema: el gate y el
    # contrato estructural no pueden discrepar.
    schema = Draft202012Validator(
        json.loads((SCHEMAS / "program-plan.schema.json").read_text()))
    results.append(check(
        "el plan de prueba valida contra program-plan.schema.json",
        not list(schema.iter_errors(sano)),
        "; ".join(e.message[:80] for e in schema.iter_errors(sano)),
    ))

    # ---------- rechazo ----------

    # Regla 29.9: el grafo DEBE ser aciclico.
    ciclo = make_plan([
        feature("F001", deps=["F002"]),
        feature("F002", deps=["F001"]),
    ])
    decision, reasons = plan_lib.evaluate(ciclo, ok_manifest)
    results.append(check(
        "RECHAZA un grafo con ciclo (regla 29.9)",
        decision == "fail" and codes(reasons)["ACYCLIC_GRAPH"] == "fail",
    ))

    # Ciclo largo: el detector no puede quedarse solo con el caso de dos.
    largo = make_plan([
        feature("F001", deps=["F004"]), feature("F002", deps=["F001"]),
        feature("F003", deps=["F002"]), feature("F004", deps=["F003"]),
    ])
    decision, reasons = plan_lib.evaluate(largo, ok_manifest)
    results.append(check(
        "RECHAZA un ciclo de cuatro saltos",
        decision == "fail" and codes(reasons)["ACYCLIC_GRAPH"] == "fail",
    ))

    # Autodependencia: ciclo de largo 1, suele ser un tipeo.
    propio = make_plan([feature("F001", deps=["F001"]), feature("F002")])
    decision, reasons = plan_lib.evaluate(propio, ok_manifest)
    results.append(check(
        "RECHAZA una feature que depende de si misma",
        decision == "fail" and codes(reasons).get("NO_SELF_DEPENDENCY") == "fail",
    ))

    # Un grafo con diamante NO es un ciclo: el detector no puede confundirlos.
    diamante = make_plan([
        feature("F001"), feature("F002", deps=["F001"]),
        feature("F003", deps=["F001"]), feature("F004", deps=["F002", "F003"]),
    ])
    decision, reasons = plan_lib.evaluate(diamante, ok_manifest)
    results.append(check(
        "un grafo en diamante NO se confunde con un ciclo",
        codes(reasons)["ACYCLIC_GRAPH"] == "pass", f"{reasons}",
    ))

    # Dependencia a una feature inexistente.
    colgada = make_plan([feature("F001", deps=["F999"])])
    decision, reasons = plan_lib.evaluate(colgada, ok_manifest)
    results.append(check(
        "RECHAZA una dependencia que no existe",
        decision == "fail" and codes(reasons)["DEPENDENCIES_RESOLVABLE"] == "fail",
    ))

    # Ids duplicados.
    dupe = make_plan([feature("F001"), feature("F001")])
    decision, reasons = plan_lib.evaluate(dupe, ok_manifest)
    results.append(check(
        "RECHAZA ids de feature duplicados",
        decision == "fail" and codes(reasons)["UNIQUE_FEATURE_IDS"] == "fail",
    ))

    # Riesgo critical sin aprobacion humana: contradice la politica de la
    # seccion 36.5 y el human_approval de config/system.yaml.
    critico = make_plan([feature("F001", risk="critical", tier="deep", human=False)])
    decision, reasons = plan_lib.evaluate(critico, ok_manifest)
    results.append(check(
        "RECHAZA un riesgo critical sin aprobacion humana",
        decision == "fail" and codes(reasons)["CRITICAL_REQUIRES_HUMAN"] == "fail",
    ))

    # Tier incoherente con el riesgo (seccion 20.1).
    barato = make_plan([feature("F001", risk="critical", tier="fast", human=True)])
    decision, reasons = plan_lib.evaluate(barato, ok_manifest)
    results.append(check(
        "RECHAZA un riesgo critical con capability_tier fast",
        decision == "fail" and codes(reasons)["TIER_MATCHES_RISK"] == "fail",
    ))

    alto = make_plan([feature("F001", risk="high", tier="fast")])
    decision, reasons = plan_lib.evaluate(alto, ok_manifest)
    results.append(check(
        "RECHAZA un riesgo high con capability_tier fast",
        decision == "fail" and codes(reasons)["TIER_MATCHES_RISK"] == "fail",
    ))

    # Regla 29.1: sin spec approved no se planifica.
    decision, reasons = plan_lib.evaluate(sano, manifest(status="draft"))
    results.append(check(
        "RECHAZA planificar sobre un spec que no esta approved (regla 29.1)",
        decision == "fail" and codes(reasons)["SPEC_APPROVED"] == "fail",
    ))

    # El plan tiene que apuntar al digest del spec aprobado: si el spec cambio,
    # el plan planifica sobre algo que ya no existe.
    decision, reasons = plan_lib.evaluate(
        make_plan([feature("F001")], digest="sha256:" + "b" * 64), ok_manifest)
    results.append(check(
        "RECHAZA un plan que no apunta al digest del spec aprobado",
        decision == "fail" and codes(reasons)["SPEC_DIGEST_MATCH"] == "fail",
    ))

    # Un plan donde toda feature depende de otra no puede arrancar.
    sin_raiz = make_plan([
        feature("F001", deps=["F002"]), feature("F002", deps=["F003"]),
        feature("F003", deps=["F001"]),
    ])
    decision, reasons = plan_lib.evaluate(sin_raiz, ok_manifest)
    results.append(check(
        "RECHAZA un plan sin ninguna feature ejecutable de entrada",
        decision == "fail" and codes(reasons)["HAS_ENTRY_POINT"] == "fail",
    ))

    # ---------- el gate como comando ----------

    def run_gate(plan_doc, mani=None):
        d = pathlib.Path(tempfile.mkdtemp())
        (d / "spec").mkdir()
        (d / "spec" / "manifest.yaml").write_text(
            pathlib.Path(mani or ok_manifest).read_text())
        pp = d / "plan.json"
        pp.write_text(json.dumps(plan_doc))
        p = subprocess.run(
            [str(ROOT / "cli" / "talos"), "plan", "check", str(pp),
             "--format", "json", "--no-persist"],
            capture_output=True, text=True,
            env={"PATH": "/usr/bin:/bin:/usr/local/bin",
                 "HOME": str(pathlib.Path.home()),
                 "TALOS_PROJECT_ROOT": str(d)})
        return p.returncode, p.stdout

    code, out = run_gate(sano)
    results.append(check(
        "talos plan check sale 0 con un plan sano",
        code == 0, f"exit={code} out={out[:200]}",
    ))

    gr = json.loads(out) if out.strip().startswith("{") else {}
    gate_schema = Draft202012Validator(
        json.loads((SCHEMAS / "gate-result.schema.json").read_text()))
    results.append(check(
        "el GateResult de PLAN_GATE valida contra su schema",
        gr and not list(gate_schema.iter_errors(gr)),
        "; ".join(e.message[:80] for e in gate_schema.iter_errors(gr)) if gr else "sin salida",
    ))
    results.append(check(
        "el GateResult declara gate PLAN_GATE y transiciona a PROGRAM_READY",
        gr.get("gate") == "PLAN_GATE" and gr.get("to_state") == "PROGRAM_READY",
        f"{gr.get('gate')} -> {gr.get('to_state')}",
    ))

    code, out = run_gate(ciclo)
    results.append(check(
        "talos plan check sale 3 con un ciclo (gate rechazado)",
        code == 3, f"exit={code}",
    ))
    gr_fail = json.loads(out) if out.strip().startswith("{") else {}
    results.append(check(
        "el GateResult de rechazo no promueve a PROGRAM_READY",
        gr_fail.get("to_state") == "PROGRAM_PLANNING",
        f"to_state={gr_fail.get('to_state')}",
    ))

    # Un plan que no valida contra el schema se rechaza antes de analizarse.
    code, out = run_gate({"schema_version": 1, "features": []})
    results.append(check(
        "RECHAZA un plan que no valida contra program-plan.schema.json",
        code == 3 and "SCHEMA_VALID" in out, f"exit={code}",
    ))

    # Regla 24.4.3: PLAN_GATE tampoco invoca modelos.
    fuente = (ROOT / "hooks" / "lib" / "plan.py").read_text()
    sospechoso = [w for w in ("invoke_model", "urllib", "requests", "subprocess")
                  if w in fuente]
    results.append(check(
        "PLAN_GATE no invoca modelos ni hace efectos externos (regla 24.4.3)",
        not sospechoso, f"{sospechoso}",
    ))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks de PLAN_GATE")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
