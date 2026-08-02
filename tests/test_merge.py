"""Auditoria de MergeGate y del CIAdapter. Ver thalos-0.0.7.md secciones 30.4 y 31.

Pasos 12 y 13 de la ruta de implementacion (seccion 51).

MergeGate es el ultimo gate y el mas facil de debilitar sin que se note: basta
con asumir una condicion que no se pudo comprobar. Estos checks verifican que
ninguna se asuma.
"""
import json
import pathlib
import subprocess
import sys
import tempfile

import yaml
from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def main():
    results = []

    # ---------- manifiesto del CIAdapter ----------

    man = yaml.safe_load((ROOT / "adapters" / "github_ci" / "adapter.yaml").read_text())
    errors = list(Draft202012Validator(
        json.loads((SCHEMAS / "adapter-manifest.schema.json").read_text())
    ).iter_errors(man))
    results.append(check("adapters/github_ci/adapter.yaml valida contra su schema",
                         not errors, "; ".join(e.message[:80] for e in errors[:3])))
    results.append(check("implementa CIAdapter",
                         man["implements"] == "CIAdapter"))

    dry = yaml.safe_load((ROOT / "adapters" / "ci_dryrun" / "adapter.yaml").read_text())
    results.append(check(
        "expone exactamente las operaciones de CIAdapter (38.4)",
        {o["name"] for o in man["operations"]} == {o["name"] for o in dry["operations"]}))

    # ---------- el veredicto de pase ----------

    src = (ROOT / "adapters" / "github_ci" / "run.sh").read_text()
    results.append(check(
        "en dry-run el CheckRunSet sale verifiable:false (regla 37.4.4.2)",
        '"verifiable\\":false' in src or '\\"verifiable\\":false' in src
        or '"verifiable":false' in src))
    results.append(check(
        "el veredicto sale de contar checks, no de interpretar texto",
        'grep -c' in src and 'SUCCESS' in src))
    results.append(check(
        "un check pendiente NO cuenta como pase",
        'pending' in src and 'PENDING' in src))

    # ---------- MergeGate ----------

    mg = (ROOT / "hooks" / "lib" / "merge-gate.sh").read_text()
    for code, regla in [
        ("CHECKS_GREEN", "31.1"), ("MERGEABLE", "31.2"),
        ("NO_CONFLICTING_LEASE", "31.4"), ("AUTO_MERGE_POLICY", "31.7"),
        ("HUMAN_APPROVAL", "31.6"), ("MODE_ALLOWS_MERGE", "37.4.4.3"),
        ("CHECKS_VERIFIABLE", "23.3.5"),
    ]:
        results.append(check(f"MergeGate evalua {code} (regla {regla})", code in mg))

    results.append(check(
        "un riesgo que no se puede leer se trata como critical",
        mg.count("critical") >= 3,
        "relajar lo desconocido es la forma mas facil de debilitar el gate"))

    # needs_human es la DECISION del gate; una condicion es pass, fail o skip.
    # gate-result.schema.json lo impone y tiene razon: "hace falta un humano" es
    # el veredicto, no el resultado de haber medido algo.
    results.append(check(
        "auto_merge deshabilitado deja la condicion en skip y la decision en needs_human",
        "AUTO_MERGE_POLICY skip" in mg and "_decision=needs_human" in mg))

    # Regla 31.9 y 31.11: ninguna extension autoriza un merge.
    results.append(check(
        "MergeGate vive en el nucleo, no en un adapter",
        (ROOT / "hooks" / "lib" / "merge-gate.sh").exists()
        and not list((ROOT / "adapters").glob("*/merge-gate.sh"))))

    # Regla 31.8: el merge se delega al adapter, el gate no mergea por su cuenta.
    cmd = (ROOT / "cli" / "commands" / "merge.sh").read_text()
    results.append(check(
        "el merge se delega al CoordinationAdapter (regla 31.8)",
        "thalos_capability_run CoordinationAdapter merge_pr" in cmd))
    results.append(check(
        "no se mergea si el gate no autoriza",
        'No se ejecuta ningun merge' in cmd))
    results.append(check(
        "el nucleo no nombra a gh ni a GitHub para mergear",
        "gh pr merge" not in cmd and "github" not in cmd.lower()))

    # ---------- comportamiento ----------

    def corre(*args, root=None, env=None):
        e = {"PATH": "/usr/bin:/bin:/usr/local/bin",
             "HOME": str(pathlib.Path.home()),
             "THALOS_PROJECT_ROOT": str(root or tempfile.mkdtemp())}
        if env:
            e.update(env)
        p = subprocess.run([str(ROOT / "cli" / "thalos"), *args],
                           capture_output=True, text=True, env=e)
        return p.returncode, p.stdout + p.stderr

    proj = pathlib.Path(tempfile.mkdtemp())
    (proj / "orchestration" / "evidence").mkdir(parents=True)

    code, out = corre("merge", "check", "F001", "--pr", "1", root=proj)
    results.append(check(
        "en dry-run-only MERGE_GATE nunca autoriza (regla 37.4.4.3)",
        code != 0 and "MODE_ALLOWS_MERGE" in out, f"exit={code}"))
    results.append(check(
        "y lo dice por condicion, no con un mensaje generico",
        "dry-run-only no alcanza FEATURE_MERGED" in out))

    results.append(check(
        "el CheckRunSet simulado no satisface el gate (regla 23.3.5)",
        "CHECKS_VERIFIABLE" in out and "no es verificable" in out))

    # El reporte tiene que validar como GateResult.
    reports = sorted((proj / "orchestration" / "evidence").glob("ev-gate-merge-gate-*.json"))
    results.append(check("el MergeGateReport se persiste (regla 31.5)", len(reports) >= 1))
    if reports:
        ev = json.loads(reports[0].read_text())
        ev_val = Draft202012Validator(json.loads((SCHEMAS / "evidence.schema.json").read_text()))
        gr_val = Draft202012Validator(json.loads((SCHEMAS / "gate-result.schema.json").read_text()))
        results.append(check("el reporte valida como evidencia",
                             not list(ev_val.iter_errors(ev)),
                             "; ".join(e.message[:70] for e in ev_val.iter_errors(ev))))
        results.append(check("y su payload valida como GateResult",
                             not list(gr_val.iter_errors(ev["payload"])),
                             "; ".join(e.message[:70] for e in gr_val.iter_errors(ev["payload"]))))
        results.append(check("una condicion por linea, ninguna asumida (regla 31.5)",
                             len(ev["payload"]["reasons"]) >= 7,
                             f"{len(ev['payload']['reasons'])} condiciones"))

    code, out = corre("merge", "do", "F001", "--pr", "1", root=proj)
    results.append(check(
        "merge do NO mergea cuando el gate rechaza",
        code != 0 and "No se ejecuta ningun merge" in out, f"exit={code}"))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks de MergeGate y CIAdapter")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
