"""Auditoria de la proyeccion "que sigue" y del loop del orquestador.

Ver talos-0.0.6.md secciones 22, 29 y 43.5.

Lo que se verifica no es que el loop avance, sino que NO avance de mas: un
ejecutor automatico es peligroso exactamente en la medida en que puede saltear
una condicion que nadie miro.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLA = ROOT / "hooks" / "generated" / "transitions.tsv"


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def proyecto(con_plan=True, aprobado=True):
    d = pathlib.Path(tempfile.mkdtemp())
    (d / ".talos").mkdir()
    for sub in ("cli", "hooks", "schemas", "system", "config", "adapters", "roles"):
        shutil.copytree(ROOT / sub, d / ".talos" / sub)
    shutil.copy(ROOT / "VERSION", d / ".talos" / "VERSION")
    if (ROOT / ".venv").is_dir():
        (d / ".venv").symlink_to(ROOT / ".venv")
    for c in (["git", "init", "-q"], ["git", "config", "user.name", "t"],
              ["git", "config", "user.email", "t@t.t"]):
        subprocess.run(c, cwd=d, capture_output=True)
    talos(d, "init")

    (d / "spec").mkdir(exist_ok=True)
    estado = "approved" if aprobado else "draft"
    (d / "spec" / "manifest.yaml").write_text(
        f'version: "1"\nstatus: {estado}\nentry: SPEC.md\n')
    if con_plan:
        f = lambda i, r, dep: {  # noqa: E731
            "id": i, "title": f"feature {i}", "effort": "medium", "risk": r,
            "capability_tier": "deep" if r == "critical" else "fast",
            "human_approval_required": r == "critical", "depends_on": dep}
        (d / "orchestration" / "program-plan.json").write_text(json.dumps({
            "schema_version": 1, "project": "demo", "spec_digest": "sha256:" + "c" * 64,
            "created_by": "role:Planner", "created_at": "2026-08-01T00:00:00Z",
            "features": [f("F001", "low", []), f("F002", "critical", ["F001"])]}))
    return d


def talos(root, *args):
    p = subprocess.run([str(root / ".talos" / "cli" / "talos"), *args],
                       capture_output=True, text=True, cwd=root,
                       env={"PATH": "/usr/bin:/bin:/usr/local/bin",
                            "HOME": str(pathlib.Path.home()),
                            "TALOS_PROJECT_ROOT": str(root)})
    return p.returncode, p.stdout + p.stderr


def next_json(root):
    code, out = talos(root, "next", "--format", "json")
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return {}


def main():
    results = []

    # ---------- la proyeccion deriva, no declara ----------

    src = (ROOT / "hooks" / "lib" / "next.py").read_text()
    results.append(check(
        "la proyeccion no acepta un objetivo declarado aparte",
        "goal" not in src.lower() and "objetivo declarado" in src,
        "una intencion al margen competiria con el spec (seccion 43.5)"))

    vacio = proyecto(con_plan=False, aprobado=False)
    d = next_json(vacio)
    results.append(check(
        "sin spec aprobado no propone planificar (regla 29.1)",
        d.get("programa") == "SPEC_REVIEW"
        and all("plan" not in a["orden"] for a in d.get("acciones", [])),
        f"{d.get('programa')} {d.get('acciones')}"))

    sin_plan = proyecto(con_plan=False)
    d = next_json(sin_plan)
    results.append(check(
        "con spec aprobado y sin plan, propone planificar",
        any("plan init" in a["orden"] for a in d.get("acciones", [])),
        f"{d.get('acciones')}"))

    p = proyecto()
    d = next_json(p)
    results.append(check(
        "propone arrancar solo la feature sin dependencias pendientes",
        [a["orden"] for a in d["acciones"]] == ["talos feature start F001"],
        f"{d['acciones']}"))
    results.append(check(
        "y dice por que la otra no puede",
        any(f["id"] == "F002" and f["bloqueada_por"] == ["F001"] for f in d["features"]),
        f"{d['features']}"))

    # ---------- el loop no fuerza ----------

    code, out = talos(p, "run")
    results.append(check("el loop avanza lo que esta autorizado",
                         "feature start F001" in out, out[-300:]))

    d = next_json(p)
    f001 = [f for f in d["features"] if f["id"] == "F001"][0]
    results.append(check("F001 quedo en FEATURE_IN_PROGRESS",
                         f001["estado"] == "FEATURE_IN_PROGRESS", f001["estado"]))

    results.append(check(
        "el loop se detiene cuando no hay nada autorizado",
        "nada mas que el loop pueda avanzar" in out, out[-300:]))

    results.append(check(
        "y NO avanza F001 sin la evidencia que exige DEV_GATE",
        f001["estado"] != "FEATURE_REVIEW"
        and any(s["hacia"] == "FEATURE_REVIEW" and s["falta"] for s in f001["salidas"]),
        f"{f001['salidas']}"))

    # Lo mas importante: el loop no puede abandonar una feature por su cuenta.
    # F27 sale de cualquier estado y solo exige una decision humana; si el loop
    # la propusiera, terminaria "resolviendo" features abandonandolas.
    # Declarar el fracaso siempre esta disponible: BLOCKED, FAILED, ESCALATED y
    # ABANDONED se alcanzan casi desde cualquier estado. Un loop que las
    # propusiera "resolveria" toda feature dificil marcandola como perdida.
    FRACASO = ("FEATURE_BLOCKED", "FEATURE_ABANDONED",
               "FEATURE_FAILED", "FEATURE_ESCALATED")
    results.append(check(
        "el loop NUNCA propone un camino de fracaso",
        all(not any(f in a["orden"] for f in FRACASO) for a in d["acciones"]),
        f"{d['acciones']}"))
    results.append(check(
        "abandonar sigue siendo una decision humana explicita",
        "FEATURE_ABANDONED" in (ROOT / "hooks" / "lib" / "next.py").read_text()))

    # ---------- la secuencia de trabajo ----------
    #
    # El loop movia estados pero no causaba que se hiciera el trabajo:
    # proponia start y advance y nada mas. Con eso arrancaba una feature y se
    # plantaba, porque la transicion siguiente pide evidencia que solo un
    # agente puede producir.

    def next_con_pane(root, pane="w9:p1"):
        code, out = talos(root, "next", "--pane", pane, "--format", "json")
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return {}

    d = next_con_pane(p)
    ordenes = [a["orden"] for a in d.get("acciones", [])]
    results.append(check(
        "con pane, el loop propone despachar un agente",
        any("feature dispatch" in o for o in ordenes), f"{ordenes}"))

    # Sin pane no se propone: Talos no elige donde ejecutar por vos.
    d2 = next_json(p)
    results.append(check(
        "SIN pane no propone nada que necesite un agente",
        not any("dispatch" in a["orden"] or "work" in a["orden"]
                for a in d2.get("acciones", [])),
        f"{[a['orden'] for a in d2.get('acciones', [])]}"))
    results.append(check(
        "y lo dice, en vez de callarse",
        any(f.get("motivo") == "necesita un pane para trabajar"
            for f in d2.get("features", [])),
        f"{[f.get('motivo') for f in d2.get('features', [])]}"))

    # La secuencia respeta el orden en que la evidencia se puede obtener.
    src_next = (ROOT / "hooks" / "lib" / "next.py").read_text()
    orden_esperado = ["dispatch", "work", "commit", "test", "collect"]
    pos = [src_next.index(f"feature {x}") for x in orden_esperado]
    results.append(check(
        "los pasos de trabajo van en el orden en que la evidencia se obtiene",
        pos == sorted(pos), f"{list(zip(orden_esperado, pos))}"))

    results.append(check(
        "run acepta --pane y avisa cuando falta",
        "--pane" in (ROOT / "cli" / "commands" / "run.sh").read_text()
        and "no elige donde ejecutar" in (ROOT / "cli" / "commands" / "run.sh").read_text()))

    # ---------- la cota ----------

    run_src = (ROOT / "cli" / "commands" / "run.sh").read_text()
    results.append(check(
        "el loop tiene cota de pasos",
        "MAX_PASOS" in run_src and "--max" in run_src))
    results.append(check(
        "y explica por que la cota no es una comodidad",
        "hasta que alguien" in run_src,
        "un loop sin cota que se equivoca no se equivoca una sola vez"))

    code, out = talos(p, "run", "--max", "0")
    results.append(check(
        "con cota 0 no ejecuta nada",
        "[01]" not in out, out[-200:]))

    # ---------- dry-run ----------

    p2 = proyecto()
    code, out = talos(p2, "run", "--dry-run")
    results.append(check("dry-run muestra el paso sin ejecutarlo",
                         "[01]" in out and "dry-run" in out, out[-200:]))
    results.append(check(
        "y de verdad no lo ejecuta",
        next_json(p2)["features"][0]["estado"] == "-",
        f"{next_json(p2)['features'][0]}"))

    # ---------- el loop no produce evidencia ----------

    results.append(check(
        "el loop no sella evidencia por su cuenta",
        "evidence.py seal" not in run_src and "verifiable" not in run_src,
        "producir la evidencia que el mismo consume seria firmarse los permisos"))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks del loop y la proyeccion")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
