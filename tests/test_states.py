"""Auditoria de la maquina de estados y del contrato de gates.

Paso 3 de la ruta de implementacion (seccion 51).

La tabla de transiciones se deriva de la spec, no se escribe a mano. Estos
checks verifican que la derivacion sea fiel y que el checker rechace lo que la
seccion 22.6 manda rechazar. Un gate que solo sabe decir pass no es un gate.
"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile

from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
TABLE = ROOT / "hooks" / "generated" / "transitions.tsv"
SPEC = ROOT / "talos-0.0.6.md"
TALOS = ROOT / "cli" / "talos"

TERMINAL = {
    "program": {"PROGRAM_DONE", "HALTED"},
    "feature": {"FEATURE_DONE", "FEATURE_FAILED", "FEATURE_ABANDONED"},
}


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def rows():
    out = []
    for line in TABLE.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        out.append(line.split("\t"))
    return out


def gate(*args, evidence=None, run_root=None):
    """Corre talos gate y devuelve (exit_code, stdout)."""
    cmd = [str(TALOS), "gate", *args]
    if evidence:
        cmd += ["--evidence", str(evidence)]
    cmd += ["--format", "json"]
    env = {
        "PATH": "/usr/bin:/bin:/usr/local/bin",
        "HOME": str(pathlib.Path.home()),
        "TALOS_PROJECT_ROOT": str(run_root or tempfile.mkdtemp()),
    }
    p = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return p.returncode, p.stdout


def evidence_dir(kinds):
    """kinds: lista de (kind, verifiable)."""
    d = pathlib.Path(tempfile.mkdtemp())
    for i, (kind, verifiable) in enumerate(kinds):
        (d / f"{i}.json").write_text(json.dumps({
            "id": f"ev-{i}", "kind": kind, "schema_version": 1, "run_id": "r-1",
            "produced_by": "core:test", "produced_at": "2026-07-31T00:00:00Z",
            "digest": "sha256:" + "0" * 64, "verifiable": verifiable,
        }))
    return d


def main():
    results = []
    table = rows()

    # ---------- fidelidad de la derivacion ----------

    spec = SPEC.read_text()
    n_prog = len(re.findall(r"^\| P\d+ \|", spec, re.M))
    n_feat = len(re.findall(r"^\| F\d+ \|", spec, re.M))
    prog = [r for r in table if r[0] == "program"]
    feat = [r for r in table if r[0] == "feature"]

    results.append(check(
        "la tabla tiene todas las transiciones de programa de la seccion 22.4",
        len(prog) == n_prog, f"tabla {len(prog)} vs spec {n_prog}",
    ))
    results.append(check(
        "la tabla tiene todas las transiciones de feature de la seccion 22.5",
        len(feat) == n_feat, f"tabla {len(feat)} vs spec {n_feat}",
    ))

    # Regla 22.6.9: los terminales no tienen transiciones de salida.
    salidas = [f"{r[0]} {r[1]}" for r in table if r[2] in TERMINAL[r[0]]]
    results.append(check(
        "ningun estado terminal tiene transiciones de salida (regla 22.6.9)",
        not salidas, f"salen de terminal: {salidas}",
    ))

    # Regla 22.6.5: toda transicion emite exactamente un evento.
    sin_evento = [f"{r[0]} {r[1]}" for r in table if r[8] in ("-", "")]
    results.append(check(
        "toda transicion declara su evento (regla 22.6.5)",
        not sin_evento, f"sin evento: {sin_evento}",
    ))

    # Todo gate nombrado tiene que estar en la lista de la seccion 22.3.
    gates_spec = set(re.search(r"### 22\.3\. Gates\n\n```txt\n(.*?)\n```", spec, re.S)
                     .group(1).split())
    gates_tabla = {r[4] for r in table if r[4] != "-"}
    results.append(check(
        "todo gate de la tabla existe en la seccion 22.3",
        gates_tabla <= gates_spec, f"desconocidos: {sorted(gates_tabla - gates_spec)}",
    ))

    # Todo kind de evidencia tiene que estar en el catalogo 23.4, que es el
    # enum de evidence.schema.json.
    ev_schema = json.loads((SCHEMAS / "evidence.schema.json").read_text())
    kinds_validos = set(ev_schema["properties"]["kind"]["enum"])
    kinds_tabla = set()
    for r in table:
        if r[7] != "-":
            kinds_tabla |= set(r[7].split(","))
    results.append(check(
        "toda evidencia exigida existe en el catalogo de la seccion 23.4",
        kinds_tabla <= kinds_validos,
        f"fuera del catalogo: {sorted(kinds_tabla - kinds_validos)}",
    ))

    # Deriva: la tabla versionada coincide con la spec.
    box = pathlib.Path(tempfile.mkdtemp())
    (box / "hooks" / "generated").mkdir(parents=True)
    (box / "tools").mkdir()
    (box / "tools" / "build-transitions.py").write_bytes(
        (ROOT / "tools" / "build-transitions.py").read_bytes())
    (box / SPEC.name).write_bytes(SPEC.read_bytes())
    p = subprocess.run([sys.executable, str(box / "tools" / "build-transitions.py")],
                       capture_output=True, text=True)
    generada = box / "hooks" / "generated" / "transitions.tsv"
    results.append(check(
        "hooks/generated/transitions.tsv coincide con la spec",
        p.returncode == 0 and generada.exists()
        and generada.read_text() == TABLE.read_text(),
        "corre python3 tools/build-transitions.py y commiteá el resultado",
    ))

    # ---------- el checker rechaza ----------

    # Regla 22.6.1 y 22.6.2: sin transicion en la tabla, se rechaza.
    code, out = gate("feature", "FEATURE_READY", "FEATURE_MERGED")
    results.append(check(
        "RECHAZA una transicion que no existe en la tabla (regla 22.6.2)",
        code == 3 and "TRANSITION_NOT_DEFINED" in out, f"exit={code}",
    ))

    # Salir de un estado terminal se rechaza aunque el destino exista.
    code, out = gate("feature", "FEATURE_DONE", "FEATURE_IN_PROGRESS")
    results.append(check(
        "RECHAZA salir de un estado terminal (regla 22.6.9)",
        code == 3, f"exit={code}",
    ))

    # Regla 22.6.4: si falta evidencia, fail con missing_evidence poblado.
    code, out = gate("feature", "FEATURE_READY", "FEATURE_IN_PROGRESS",
                     evidence=evidence_dir([]))
    r = json.loads(out)
    results.append(check(
        "RECHAZA sin la evidencia exigida y la lista en missing_evidence (regla 22.6.4)",
        code == 3 and r["decision"] == "fail"
        and set(r["missing_evidence"]) == {"LockLease", "IssueRef", "BranchRef"},
        f"exit={code} missing={r.get('missing_evidence')}",
    ))

    # Regla 24.4.4: todo fail puebla reasons con al menos un item en fail.
    results.append(check(
        "todo fail trae al menos una razon en estado fail (regla 24.4.4)",
        any(x["status"] == "fail" for x in r["reasons"]),
    ))

    # Con toda la evidencia, pasa.
    ok_dir = evidence_dir([("LockLease", True), ("IssueRef", True), ("BranchRef", True)])
    code, out = gate("feature", "FEATURE_READY", "FEATURE_IN_PROGRESS", evidence=ok_dir)
    passing = json.loads(out)
    results.append(check(
        "AUTORIZA cuando toda la evidencia exigida esta presente",
        code == 0 and passing["decision"] == "pass", f"exit={code}",
    ))

    # Regla 24.4.6: un gate humano nunca resuelve pass por su cuenta.
    code, out = gate("feature", "FEATURE_HUMAN_REVIEW", "FEATURE_MERGING",
                     evidence=evidence_dir([("HumanApproval", True)]))
    results.append(check(
        "un gate humano resuelve needs_human, no pass (regla 24.4.6)",
        code == 4 and json.loads(out)["decision"] == "needs_human", f"exit={code}",
    ))

    # Regla 23.3.5: evidencia no verificable no satisface un gate critico.
    code, out = gate("feature", "FEATURE_CHECKS_RUNNING", "FEATURE_CHECKS_PASS",
                     evidence=evidence_dir([("CheckRunSet", False)]))
    results.append(check(
        "RECHAZA evidencia no verificable en un gate critico (regla 23.3.5)",
        code == 3 and "EVIDENCE_NOT_VERIFIABLE" in out, f"exit={code}",
    ))

    # La misma evidencia marcada verifiable si pasa: el rechazo es por la
    # marca, no por el tipo.
    code, out = gate("feature", "FEATURE_CHECKS_RUNNING", "FEATURE_CHECKS_PASS",
                     evidence=evidence_dir([("CheckRunSet", True)]))
    results.append(check(
        "la misma evidencia marcada verifiable si satisface el gate critico",
        code == 0, f"exit={code}",
    ))

    # Regla 37.4.4.3: dry-run-only no puede alcanzar FEATURE_MERGED.
    code, out = gate("feature", "FEATURE_MERGING", "FEATURE_MERGED",
                     evidence=evidence_dir([("CheckRunSet", True), ("PolicyDecision", True),
                                            ("MergeResult", True)]))
    results.append(check(
        "dry-run-only NO alcanza FEATURE_MERGED aun con toda la evidencia (regla 37.4.4.3)",
        code == 3 and "MODE_FORBIDS_MERGE" in out, f"exit={code}",
    ))

    # ---------- contrato de salida ----------

    schema = json.loads((SCHEMAS / "gate-result.schema.json").read_text())
    validator = Draft202012Validator(schema)
    errores = list(validator.iter_errors(passing))
    results.append(check(
        "el GateResult valida contra gate-result.schema.json",
        not errores, "; ".join(e.message[:90] for e in errores[:3]),
    ))
    results.append(check(
        "el GateResult de un fail tambien valida contra su schema",
        not list(validator.iter_errors(r)),
    ))

    # Regla 24.4.8: determinista. Misma entrada, misma salida salvo el sello.
    _, out2 = gate("feature", "FEATURE_READY", "FEATURE_IN_PROGRESS", evidence=ok_dir)
    a, b = json.loads(out), json.loads(out2)
    for d in (a, b):
        d.pop("evaluated_at", None)
    a2 = dict(passing); a2.pop("evaluated_at", None)
    b2 = dict(json.loads(out2)); b2.pop("evaluated_at", None)
    results.append(check(
        "el gate es determinista: misma entrada, misma decision (regla 24.4.8)",
        a2 == b2, "dos evaluaciones identicas difieren",
    ))

    # Regla 24.4.3: el gate no invoca modelos. Se verifica estructuralmente.
    fuente = (ROOT / "hooks" / "lib" / "gate.sh").read_text()
    sospechoso = [w for w in ("invoke_model", "ModelProvider", "curl", "prompt_agent")
                  if w in fuente]
    results.append(check(
        "el GateEvaluator no invoca modelos ni hace efectos externos (reglas 24.4.2 y 24.4.3)",
        not sospechoso, f"referencias sospechosas: {sospechoso}",
    ))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks de estados y gates")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
