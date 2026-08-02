#!/usr/bin/env python3
"""Proyeccion de "que sigue". Ver thalos-0.0.7.md secciones 22, 29 y 43.5.

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
                          "gate": c[4], "condicion": c[5], "actor": c[6],
                          "evidencia": c[7]})
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
    print("thalos")
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
                libre = not s["falta"] and s.get("condicion_ok", True)
                marca = "->" if libre else "  "
                if s["falta"]:
                    falta = "  falta: " + ", ".join(s["falta"])
                elif not s.get("condicion_ok", True):
                    falta = f"  condicion: {s.get('condicion')}"
                else:
                    falta = ""
                print(f"           {marca} {s['transicion']:<4} {s['hacia']:<22}{falta}")
        print()

    if d["acciones"]:
        print("  lo que se puede hacer ahora:")
        for a in d["acciones"]:
            print(f"    {a['orden']}")
            print(f"      {a['porque']}")
    elif d.get("frenos"):
        print("  el avance esta frenado:")
        for f in d["frenos"]:
            print(f"    {f['feature']}: {f['porque']}")
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


def adapter_ligado(tabla, capacidad):
    """Que implementacion tiene ligada hoy una capacidad, o None.

    Se lee la MISMA tabla generada que usa el resolvedor del nucleo. Mirar el
    YAML por su cuenta haria que el loop decida sobre una ligadura que no es la
    que se va a ejecutar.
    """
    p = pathlib.Path(tabla).parent / "capabilities.tsv"
    if not p.is_file():
        return None
    for linea in p.read_text().splitlines():
        if linea.startswith("#") or not linea.strip():
            continue
        campos = linea.split("\t")
        if len(campos) > 2 and campos[0] == capacidad:
            return None if campos[2] == "-" else campos[2]
    return None


def agente_despachado(root, fid, adapter):
    """Si hay un agente al que este paso le pueda hablar, y por que no.

    Un rol activo NO prueba que haya agente: el rol es un archivo local que
    Thalos escribe, el agente es un proceso que puede no haber arrancado, haber
    muerto, o pertenecer a otro ExecutionAdapter. Tratar lo primero como
    evidencia de lo segundo es lo que hacia que el loop le mandara trabajo a un
    id fabricado por otro adapter y fallara dos comandos despues de la causa.

    Devuelve (True, None) o (False, motivo).
    """
    ref = cargar(root / "orchestration" / "features" / fid / ".agent", None)
    if not isinstance(ref, dict) or not ref.get("name"):
        return False, "no hay referencia del agente despachado para esta feature"
    if adapter and ref.get("adapter") != adapter:
        return False, (f"la referencia del agente la produjo {ref.get('adapter') or '-'} "
                       f"y hoy esta ligado {adapter}: un id de un adapter no vale en otro")
    return True, None


def condicion_ok(root, fid, cond, evidencia=""):
    """Si la condicion declarada de una transicion se cumple hoy.

    Dos transiciones pueden salir del mismo estado con la misma evidencia y
    significar lo contrario: F6 es "la revision pidio cambios" y F7 es "la
    revision aprobo", y las dos exigen un Review. Contando evidencia sola son
    indistinguibles, y el loop tomaba la primera: volvia a trabajar sobre algo
    ya aprobado, para revisarlo otra vez, para siempre.

    Solo se decide cuando hay con que. Sin revision, la condicion no se puede
    evaluar y no se bloquea nada: eso lo resuelve el gate, que es quien manda.
    """
    if cond in (None, "", "-"):
        return True
    # Los checks tienen sus propias condiciones pass/fail, y son otro
    # artefacto: F9 -pasaron- y F10 -fallaron- exigen las dos un CheckRunSet.
    if "CheckRunSet" in (evidencia or ""):
        concl = conclusion_checks(root, fid)
        if concl in ("success", "passed"):
            return cond == "pass"
        if concl in ("failure", "failed"):
            return cond == "fail"
        # Una conclusion que no dice ni una cosa ni la otra -por ejemplo la de
        # una simulacion- no autoriza ninguna de las dos. Elegir una seria
        # inventar el resultado de una prueba que nadie corrio.
        return False
    review = root / "orchestration" / "reports" / fid / "review.json"
    if not review.is_file():
        return True
    veredicto = (cargar(review, {}) or {}).get("verdict")
    if not veredicto:
        return True
    if cond == "pass":
        return veredicto == "approve"
    if cond == "changes":
        return veredicto == "request_changes"
    return True


def conclusion_checks(root, fid):
    """La conclusion del ultimo CheckRunSet sellado, o None."""
    d = root / "orchestration" / "evidence"
    ultima = None
    for f in sorted(d.glob("*.json")) if d.is_dir() else []:
        ev = cargar(f, None)
        if isinstance(ev, dict) and ev.get("kind") == "CheckRunSet":
            ultima = (ev.get("payload") or {}).get("conclusion")
    return ultima


def paso_con_agente(root, fid, pane, adapter, rol_necesario):
    """El despacho que hace falta para que un rol pueda trabajar, o None.

    Solo los pasos que ENCARGAN trabajo necesitan un agente. Pedir uno para
    sellar un commit o abrir un PR abria un panel y gastaba un modelo para
    ejecutar tres comandos deterministas.
    """
    rol = root / "orchestration" / ".current-role"
    activo = rol.read_text().strip() if rol.is_file() else ""
    hay_agente, motivo = agente_despachado(root, fid, adapter)
    if rol.is_file() and hay_agente and activo == rol_necesario:
        return None
    orden = f"thalos feature dispatch {fid} --role {rol_necesario}"
    if pane and pane != "<PANE>":
        orden += f" --pane {pane}"
    if not rol.is_file():
        motivo = "no hay agente despachado para esta feature"
    elif activo != rol_necesario:
        motivo = (f"el rol activo es {activo} y lo que falta ahora "
                  f"lo produce {rol_necesario}")
    return {"feature": fid, "orden": orden, "porque": motivo}


def trabajo_pendiente(root, fid, presentes, pane, adapter=None):
    """Los pasos que PRODUCEN el trabajo, no los que mueven el estado.

    El loop sabia mover la maquina de estados pero no causar que se hiciera el
    trabajo: proponia start y advance, y nada mas. Con eso arrancaba una
    feature y se plantaba, porque la transicion siguiente pide evidencia que
    solo un agente puede producir.

    Cada paso de aca produce una evidencia concreta, y se propone uno por vez
    en el orden en que la evidencia se puede obtener. Los que encargan trabajo
    piden un agente del rol que corresponda; los mecanicos no piden ninguno.
    """
    tasks = root / "orchestration" / "features" / fid / "tasks"
    entregable = list(tasks.glob("*/task-result.json")) if tasks.is_dir() else []

    # 1. Sin entregable, el Developer todavia no hizo -o no entrego- su trabajo.
    #    Salvo que se hayan gastado las iteraciones: ahi reencargar no es
    #    insistir, es no converger.
    if not entregable:
        if iteraciones_agotadas(root, fid):
            # Se devuelve el motivo, no None. Un loop que se planta sin decir
            # por que obliga a adivinar entre "termino" y "no puede".
            return {"feature": fid, "orden": None,
                    "porque": "las iteraciones del presupuesto se agotaron "
                              "y el agente no dejo entregable (regla 33.3)"}
        despacho = paso_con_agente(root, fid, pane, adapter, "Developer")
        if despacho:
            return despacho
        return {"feature": fid, "orden": f"thalos feature work {fid}",
                "porque": "el agente esta despachado y no dejo su entregable"}

    # 2. Con entregable pero sin CommitRef, falta observar git.
    if "CommitRef" not in presentes:
        return {"feature": fid, "orden": f"thalos feature commit {fid}",
                "porque": "hay entregable y falta sellar el commit"}

    # 3. Sin medicion propia no hay evidencia verificable de avance.
    if "LocalTestReport" not in presentes:
        # La orden NO lleva argumentos con espacios. El loop la ejecuta
        # partiendola por espacios, asi que un --command "a b c" llegaba
        # despedazado y el adapter recibia basura. El comando de pruebas lo
        # declara el proyecto en config/system.yaml, que es donde vive lo que
        # depende del stack.
        return {"feature": fid, "orden": f"thalos feature test {fid}",
                "porque": "falta la unica evidencia verificable que se puede producir"}

    # 4. El entregable existe en disco pero nadie lo valido ni lo sello.
    if "TaskResultSet" not in presentes:
        return {"feature": fid, "orden": f"thalos feature collect {fid}",
                "porque": "el entregable esta y falta validarlo y sellarlo"}

    # 5. Con el trabajo sellado, lo que falta lo produce el Reviewer. Despachar
    #    un Developer aca seria pedirle que revise lo que acaba de escribir, que
    #    es justo lo que la separacion de roles existe para impedir.
    if "Review" not in presentes:
        if not (root / "orchestration" / "reports" / fid / "review.json").is_file():
            despacho = paso_con_agente(root, fid, pane, adapter, "Reviewer")
            if despacho:
                return despacho
            return {"feature": fid, "orden": f"thalos feature work {fid}",
                    "porque": "la feature esta en revision y no hay Review"}
        return {"feature": fid, "orden": f"thalos feature collect {fid}",
                "porque": "el Reviewer dejo su revision y falta sellarla"}

    # 6. Revision sellada: falta publicar el trabajo. Sin este paso el ciclo se
    #    quedaba sin camino justo despues de aprobar, porque la transicion a
    #    FEATURE_PR_OPEN pide un PullRequestRef que nadie producia.
    if "PullRequestRef" not in presentes:
        review = cargar(root / "orchestration" / "reports" / fid / "review.json", {}) or {}
        if review.get("verdict") == "approve":
            return {"feature": fid, "orden": f"thalos feature pr {fid}",
                    "porque": "la revision aprobo y falta abrir el PR"}

    # 7. Con el PR abierto falta que corran los checks. Thalos no decide si
    #    pasan: le pide al CIAdapter que corra y observa lo que contesta.
    if "PullRequestRef" in presentes and "CheckRunSet" not in presentes:
        return {"feature": fid, "orden": f"thalos feature checks {fid}",
                "porque": "el PR esta abierto y falta el resultado de los checks"}

    return None


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root = pathlib.Path(argv[1])
    transiciones = leer_transiciones(argv[2])
    formato = argv[3] if len(argv) > 3 else "texto"
    pane = argv[4] if len(argv) > 4 else None
    # Quien ejecuta hoy. No se nombra ninguna implementacion: sale del registry.
    ejecutor = adapter_ligado(argv[2], "ExecutionAdapter")

    out = {"programa": "SIN_PLAN", "spec": None, "features": [],
           "acciones": [], "frenos": []}

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
                "orden": "thalos spec check",
                "porque": f"el spec esta en {estado}; Thalos no planifica hasta approved",
            })
            return emitir(out, formato)
    else:
        out["acciones"].append({"orden": "thalos init --with-spec",
                                "porque": "no hay spec del producto"})
        return emitir(out, formato)

    plan_p = root / "orchestration" / "program-plan.json"
    if not plan_p.is_file():
        out["programa"] = "SPEC_APPROVED"
        out["acciones"].append({"orden": "thalos plan init",
                                "porque": "el spec esta aprobado y no hay plan"})
        return emitir(out, formato)

    try:
        plan = json.loads(plan_p.read_text())
    except json.JSONDecodeError:
        out["acciones"].append({"orden": "thalos plan check",
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
                    "feature": fid, "orden": f"thalos feature start {fid}",
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
                # La condicion es parte de estar disponible, no un adorno. Una
                # transicion con toda su evidencia pero con la condicion en
                # contra NO se puede tomar: el gate la rechaza. Contarla como
                # disponible dejaba a la feature en "puede avanzar" sin nada
                # que avanzar, y el loop se plantaba sin decir por que.
                cond_ok = condicion_ok(root, fid, t.get("condicion"), t.get("evidencia"))
                info["salidas"].append({
                    "transicion": t["id"], "hacia": t["hacia"],
                    "gate": t["gate"], "actor": t["actor"],
                    "falta": faltan,
                    "condicion": t.get("condicion"),
                    "condicion_ok": cond_ok,
                })
                # Un loop autonomo siempre encuentra la salida mas barata, y
                # declarar el fracaso siempre esta disponible: BLOCKED, FAILED,
                # ESCALATED y ABANDONED son alcanzables casi desde cualquier
                # lado. Si el loop las propusiera, "resolveria" toda feature
                # dificil marcandola como perdida.
                #
                # Los caminos de fracaso los toma una persona, no un bucle.
                if not faltan and cond_ok and t["hacia"] not in CAMINOS_DE_FRACASO:
                    out["acciones"].append({
                        "feature": fid,
                        "orden": f"thalos feature advance {fid} --to {t['hacia']}",
                        "porque": f"{t['id']}: toda la evidencia esta presente",
                    })
            sin_falta = [s for s in info["salidas"]
                         if not s["falta"] and s.get("condicion_ok", True)]
            if sin_falta:
                info["motivo"] = "puede avanzar"
            else:
                # Nada autorizado todavia: falta producir la evidencia. Esto es
                # lo que convierte al loop en algo que llega a un producto y no
                # solo en algo que mueve estados.
                info["motivo"] = "espera evidencia"
                # Ya no hace falta que nadie elija un pane: Thalos abre el
                # suyo. La proyeccion propone el trabajo sin condiciones.
                paso = trabajo_pendiente(root, fid, presentes, pane, ejecutor)
                if paso and paso.get("orden"):
                    info["trabajo"] = paso["orden"]
                    out["acciones"].append(paso)
                elif paso:
                    # Hay un motivo concreto para no proponer nada. Decirlo es
                    # la diferencia entre "no queda nada" y "no puedo seguir".
                    info["motivo"] = paso["porque"]
                    out.setdefault("frenos", []).append(
                        {"feature": fid, "porque": paso["porque"]})

        out["features"].append(info)

    return emitir(out, formato)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
