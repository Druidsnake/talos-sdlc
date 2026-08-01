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
TERMINAL = {"FEATURE_DONE", "FEATURE_FAILED", "FEATURE_ABANDONED"}


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


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root = pathlib.Path(argv[1])
    transiciones = leer_transiciones(argv[2])
    formato = argv[3] if len(argv) > 3 else "texto"

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
                if not faltan and t["hacia"] not in ("FEATURE_ABANDONED",):
                    out["acciones"].append({
                        "feature": fid,
                        "orden": f"talos feature advance {fid} --to {t['hacia']}",
                        "porque": f"{t['id']}: toda la evidencia esta presente",
                    })
            sin_falta = [s for s in info["salidas"] if not s["falta"]]
            info["motivo"] = ("puede avanzar" if sin_falta
                              else "espera evidencia")

        out["features"].append(info)

    return emitir(out, formato)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
