#!/usr/bin/env python3
"""Proyeccion de "que sigue". Ver talos-0.0.6.md secciones 22, 29 y 43.5.

Esto NO es una fuente de intencion. La cadena de autoridad de la seccion 43.5
pone el spec aprobado por encima de todo lo que no sea policy o aprobacion
humana, y una fuente de menor autoridad nunca puede anular a una de mayor.

Por eso "que sigue" se DERIVA y no se declara:

    spec aprobado        ->  que construir
    program-plan.json    ->  features, dependencias, riesgo
    estado de cada una   ->  donde esta cada feature
    tabla de transiciones->  que puede pasar desde ahi

Un objetivo declarado aparte competiria con el spec, y es exactamente el
defecto que 0.0.5 corrigio de 0.0.4: la memoria quedaba por encima del spec
aprobado.

USO
    next.py <raiz-del-proyecto> <tabla-de-transiciones> [json|texto]

El render vive aca y no en el shell: pipear los datos y pasar el script por
heredoc compite por stdin, y gana el heredoc.
"""
import json
import pathlib
import sys

TERMINAL_OK = {"FEATURE_DONE"}

# Estados a los que el loop NUNCA propone ir por su cuenta. No son invalidos:
# son decisiones sobre dar algo por perdido, y eso no lo decide un bucle.
CAMINOS_DE_FRACASO = {
    "FEATURE_BLOCKED", "FEATURE_ABANDONED", "FEATURE_FAILED", "FEATURE_ESCALATED",
}
TERMINAL = {"FEATURE_DONE", "FEATURE_FAILED", "FEATURE_ABANDONED"}


def cargar(p, default=None):
    try:
        return json.loads(pathlib.Path(p).read_text())
    except (json.JSONDecodeError, OSError):
        return default


def leer_transiciones(path):
    filas = []
    for linea in pathlib.Path(path).read_text().splitlines():
        if linea.startswith("#") or not linea.strip():
            continue
        c = linea.split("\t")
        if len(c) >= 9 and c[0] == "feature":
            filas.append({"id": c[1], "desde": c[2], "hacia": c[3],
                          "gate": c[4], "actor": c[6], "evidencia": c[7]})
    return filas


def estado_feature(root, fid):
    f = root / "orchestration" / "features" / fid / "state.json"
    if not f.is_file():
        return None
    try:
        return json.loads(f.read_text()).get("state")
    except (json.JSONDecodeError, OSError):
        return None


def evidencia_presente(root):
    """Kinds con digest valido. Se reusa el mismo lector que usan los gates."""
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    try:
        import evidence
    except ImportError:
        return set()
    d = root / "orchestration" / "evidence"
    return {k for k, _, dig, _ in evidence.read_dir(d) if dig == "true"}


def render(d):
    print("talos")
    print()
    print(f"  programa   {d['programa']}")
    if d.get("spec"):
        print(f"  spec       {d['spec']}")
    print()

    if d["features"]:
        print(f"  {'ID':<6} {'ESTADO':<22} {'RIESGO':<9} MOTIVO")
        for f in d["features"]:
            riesgo = str(f.get("riesgo") or "-")
            print(f"  {f['id']:<6} {f['estado']:<22} {riesgo:<9} {f['motivo']}")
            if f.get("trabajo"):
                print(f"           .. {f['trabajo']}")
            for s in f.get("salidas", []):
                marca = "->" if not s["falta"] else "  "
                falta = "" if not s["falta"] else "  falta: " + ", ".join(s["falta"])
                print(f"           {marca} {s['transicion']:<4} {s['hacia']:<22}{falta}")
        print()

    if d["acciones"]:
        print("  lo que se puede hacer ahora:")
        for a in d["acciones"]:
            print(f"    {a['orden']}")
            print(f"      {a['porque']}")
    else:
        print("  nada listo para avanzar por su cuenta.")
        print("  Lo que falta es evidencia o una decision humana, no un comando.")


def emitir(out, formato):
    if formato == "json":
        print(json.dumps(out, indent=2, ensure_ascii=False))
    else:
        render(out)
    return 0


def iteraciones_agotadas(root, fid):
    """El limite de iteraciones del presupuesto es el limite de reintentos.

    Un loop que reencarga trabajo mientras no haya entregable no converge: si
    el agente no entrega, la condicion nunca cambia. La regla 33.3 ya define
    cuantas veces se puede intentar una feature; no hace falta inventar otro
    numero.
    """
    plan = cargar(root / "orchestration" / "program-plan.json", {}) or {}
    f = next((x for x in plan.get("features", []) if x.get("id") == fid), None)
    if not f:
        return False
    lim = (f.get("budget") or {}).get("max_iterations")
    if lim is None:
        return False
    st = cargar(root / "orchestration" / "features" / fid / "state.json", {}) or {}
    return (st.get("budget_consumed") or {}).get("iterations", 0) >= lim


def trabajo_pendiente(root, fid, presentes, pane):
    """Los pasos que PRODUCEN el trabajo, no los que mueven el estado.

    El loop sabia mover la maquina de estados pero no causar que se hiciera el
    trabajo: proponia start y advance, y nada mas. Con eso arrancaba una
    feature y se plantaba, porque la transicion siguiente pide evidencia que
    solo un agente puede producir.

    Cada paso de aca produce una evidencia concreta, y se propone uno por vez
    en el orden en que la evidencia se puede obtener.
    """
    rol = root / "orchestration" / ".current-role"
    entregable = list((root / "orchestration" / "features" / fid / "tasks").glob(
        "*/task-result.json")) if (root / "orchestration" / "features" / fid / "tasks").is_dir() else []

    # 1. Sin rol activo no hay quien trabaje. Despachar es lo primero.
    if not rol.is_file():
        return {"feature": fid,
                "orden": f"talos feature dispatch {fid} --role Developer --pane {pane}",
                "porque": "no hay agente despachado para esta feature",
                "necesita_pane": True}

    # 2. Con rol y sin entregable, el agente todavia no recibio el encargo.
    #    Salvo que ya se hayan gastado las iteraciones: ahi reencargar no es
    #    insistir, es no converger.
    if not entregable and iteraciones_agotadas(root, fid):
        return None
    if not entregable:
        return {"feature": fid,
                "orden": f"talos feature work {fid} --pane {pane}",
                "porque": "el agente esta despachado y no dejo su entregable",
                "necesita_pane": True}

    # 3. Con entregable pero sin CommitRef, falta observar git.
    if "CommitRef" not in presentes:
        return {"feature": fid, "orden": f"talos feature commit {fid}",
                "porque": "hay entregable y falta sellar el commit"}

    # 4. Sin medicion propia no hay evidencia verificable de avance.
    if "LocalTestReport" not in presentes:
        return {"feature": fid,
                "orden": f"talos feature test {fid} --pane {pane} --command \"python3 -m pytest tests/ -q\"",
                "porque": "falta la unica evidencia verificable que se puede producir",
                "necesita_pane": True}

    # 5. El entregable existe en disco pero nadie lo valido ni lo sello.
    if "TaskResultSet" not in presentes:
        return {"feature": fid, "orden": f"talos feature collect {fid}",
                "porque": "el entregable esta y falta validarlo y sellarlo"}

    return None


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root = pathlib.Path(argv[1])
    transiciones = leer_transiciones(argv[2])
    formato = argv[3] if len(argv) > 3 else "texto"
    pane = argv[4] if len(argv) > 4 else None

    out = {"programa": "SIN_PLAN", "spec": None, "features": [], "acciones": []}

    # El spec manda: sin spec aprobado no hay nada que planificar (regla 29.1).
    man = root / "spec" / "manifest.yaml"
    if man.is_file():
        texto = man.read_text()
        estado = next((l.split(":", 1)[1].strip().strip('"\'')
                       for l in texto.splitlines() if l.strip().startswith("status:")), None)
        out["spec"] = estado
        if estado != "approved":
            out["programa"] = "SPEC_REVIEW"
            out["acciones"].append({
                "orden": "talos spec check",
                "porque": f"el spec esta en {estado}; Talos no planifica hasta approved",
            })
            return emitir(out, formato)
    else:
        out["acciones"].append({"orden": "talos init --with-spec",
                                "porque": "no hay spec del producto"})
        return emitir(out, formato)

    plan_p = root / "orchestration" / "program-plan.json"
    if not plan_p.is_file():
        out["programa"] = "SPEC_APPROVED"
        out["acciones"].append({"orden": "talos plan init",
                                "porque": "el spec esta aprobado y no hay plan"})
        return emitir(out, formato)

    try:
        plan = json.loads(plan_p.read_text())
    except json.JSONDecodeError:
        out["acciones"].append({"orden": "talos plan check",
                                "porque": "el plan no es JSON valido"})
        return emitir(out, formato)

    feats = plan.get("features", [])
    estados = {f["id"]: estado_feature(root, f["id"]) for f in feats}
    presentes = evidencia_presente(root)

    terminadas = {i for i, e in estados.items() if e in TERMINAL_OK}
    todas_terminales = all(estados[f["id"]] in TERMINAL for f in feats) if feats else False
    out["programa"] = "PROGRAM_DONE" if todas_terminales else "PROGRAM_READY"

    for f in feats:
        fid = f["id"]
        est = estados[fid]
        deps = f.get("depends_on") or []
        pendientes = [d for d in deps if d not in terminadas]

        info = {"id": fid, "titulo": f.get("title"), "estado": est or "-",
                "riesgo": f.get("risk"), "bloqueada_por": pendientes,
                "salidas": []}

        if est is None:
            if pendientes:
                info["motivo"] = f"espera a {', '.join(pendientes)}"
            else:
                info["motivo"] = "lista para arrancar"
                out["acciones"].append({
                    "feature": fid, "orden": f"talos feature start {fid}",
                    "porque": "sin dependencias pendientes",
                })
        elif est in TERMINAL:
            info["motivo"] = "terminal"
        else:
            # Que transiciones salen de aca, y que evidencia les falta.
            for t in transiciones:
                if t["desde"] not in (est, "*"):
                    continue
                req = [] if t["evidencia"] == "-" else t["evidencia"].split(",")
                faltan = [k for k in req if k not in presentes]
                info["salidas"].append({
                    "transicion": t["id"], "hacia": t["hacia"],
                    "gate": t["gate"], "actor": t["actor"],
                    "falta": faltan,
                })
                # Un loop autonomo siempre encuentra la salida mas barata, y
                # declarar el fracaso siempre esta disponible: BLOCKED, FAILED,
                # ESCALATED y ABANDONED son alcanzables casi desde cualquier
                # lado. Si el loop las propusiera, "resolveria" toda feature
                # dificil marcandola como perdida.
                #
                # Los caminos de fracaso los toma una persona, no un bucle.
                if not faltan and t["hacia"] not in CAMINOS_DE_FRACASO:
                    out["acciones"].append({
                        "feature": fid,
                        "orden": f"talos feature advance {fid} --to {t['hacia']}",
                        "porque": f"{t['id']}: toda la evidencia esta presente",
                    })
            sin_falta = [s for s in info["salidas"] if not s["falta"]]
            if sin_falta:
                info["motivo"] = "puede avanzar"
            else:
                # Nada autorizado todavia: falta producir la evidencia. Esto es
                # lo que convierte al loop en algo que llega a un producto y no
                # solo en algo que mueve estados.
                info["motivo"] = "espera evidencia"
                paso = trabajo_pendiente(root, fid, presentes, pane or "<PANE>")
                if paso:
                    info["trabajo"] = paso["orden"]
                    if pane or not paso.get("necesita_pane"):
                        out["acciones"].append(paso)
                    else:
                        info["motivo"] = "necesita un pane para trabajar"

        out["features"].append(info)

    return emitir(out, formato)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
