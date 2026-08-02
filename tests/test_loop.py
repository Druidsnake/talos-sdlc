"""Auditoria de la proyeccion "que sigue" y del loop del orquestador.

Ver talos-0.0.7.md secciones 22, 29 y 43.5.

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
        "el loop deja constancia de lo que hizo en la consola",
        "[01]" in out and "consola" in out, out[-300:]))

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

    # Nadie tiene que elegir un pane: Talos abre el suyo por el
    # ExecutionAdapter. El pane donde corre el orquestador es su consola.
    #
    # Se mira un proyecto FRESCO: en el de arriba el loop ya despacho, asi que
    # el siguiente paso ya no es dispatch sino work.
    pf = proyecto()
    talos(pf, "feature", "start", "F001")
    d = next_json(pf)
    ordenes = [a["orden"] for a in d.get("acciones", [])]
    results.append(check(
        "el loop propone despachar sin que nadie le diga donde",
        any("feature dispatch" in o for o in ordenes), f"{ordenes}"))
    results.append(check(
        "y la orden no arrastra un pane",
        all("--pane" not in o for o in ordenes), f"{ordenes}"))

    # Un rol activo NO prueba que haya agente. El rol es un archivo que escribe
    # Talos; el agente es un proceso que puede no haber arrancado, haberse
    # muerto, o pertenecer a otro ExecutionAdapter. Tratar lo primero como
    # evidencia de lo segundo hacia que el loop saltara el despacho y le
    # mandara trabajo a un id que ya no significaba nada.
    talos(pf, "feature", "dispatch", "F001", "--role", "Developer")
    ordenes = [a["orden"] for a in next_json(pf).get("acciones", [])]
    results.append(check(
        "con agente despachado el loop pasa a encargar el trabajo",
        any("feature work" in o for o in ordenes), f"{ordenes}"))

    refp = pf / "orchestration" / "features" / "F001" / ".agent"
    ref = json.loads(refp.read_text())
    rol = pf / "orchestration" / ".current-role"
    refp.unlink()
    results.append(check(
        "sin referencia de agente el loop vuelve a despachar aunque el rol siga activo",
        rol.is_file()
        and any("feature dispatch" in a["orden"]
                for a in next_json(pf).get("acciones", [])),
        f"{[a['orden'] for a in next_json(pf).get('acciones', [])]}"))

    ref["adapter"] = "talos.adapter.otro"
    refp.write_text(json.dumps(ref))
    acciones = next_json(pf).get("acciones", [])
    results.append(check(
        "y tambien si la referencia la produjo otro adapter que el ligado hoy",
        any("feature dispatch" in a["orden"] for a in acciones),
        f"{[a['orden'] for a in acciones]}"))
    results.append(check(
        "el motivo nombra el desajuste de procedencia, no 'espera evidencia'",
        any("adapter" in a["porque"] for a in acciones),
        f"{[a['porque'] for a in acciones]}"))

    # Regla 38.5.5: el nucleo no nombra a Herdr. Donde se abre una ventana lo
    # resuelve el adapter, que es quien conoce el runtime.
    for f in ("cli/commands/run.sh", "cli/commands/feature.sh",
              "hooks/lib/next.py"):
        txt = (ROOT / f).read_text()
        results.append(check(
            f"{f} no conoce variables de Herdr (regla 38.5.5)",
            "HERDR_" not in txt, f))

    # La secuencia respeta el orden en que la evidencia se puede obtener.
    src_next = (ROOT / "hooks" / "lib" / "next.py").read_text()
    orden_esperado = ["dispatch", "work", "commit", "test", "collect"]
    pos = [src_next.index(f"feature {x}") for x in orden_esperado]
    results.append(check(
        "los pasos de trabajo van en el orden en que la evidencia se obtiene",
        pos == sorted(pos), f"{list(zip(orden_esperado, pos))}"))

    results.append(check(
        "run no pide un pane: Talos se arma la ventana que necesita",
        "--pane" not in (ROOT / "cli" / "commands" / "run.sh").read_text()))

    # El alcance tiene que quedar IMPUESTO, no solo declarado. dispatch instala
    # el hook en el runtime del agente; sin eso el brief es una sugerencia.
    src_feat0 = (ROOT / "cli" / "commands" / "feature.sh").read_text()
    results.append(check(
        "dispatch instala el enforcement en el runtime, o no despacha",
        "install.sh" in src_feat0 and "Despachar sin bloqueo" in src_feat0,
        "un alcance declarado y no impuesto lo cumple el agente por criterio"))
    # Se miran las lineas de CODIGO: los comentarios que explican por que NO
    # usar algo tienen que poder nombrarlo.
    codigo = [l for l in src_feat0.splitlines() if not l.lstrip().startswith("#")]
    results.append(check(
        "el nucleo no conoce settings.json ni CLAUDE.md: eso es del shim",
        not any("settings.json" in l or "CLAUDE.md" in l
                or "append-system-prompt" in l for l in codigo),
        [l.strip()[:70] for l in codigo
         if "settings.json" in l or "CLAUDE.md" in l or "append-system" in l]))

    # ---------- convergencia ----------
    #
    # La primera corrida real repitio "feature work" veinte veces hasta que la
    # cota la corto. El ledger dejaba pasar el primer encargo y devolvia
    # already_exists en los siguientes, asi que la condicion "no hay
    # entregable" no cambiaba nunca.

    src_next = (ROOT / "hooks" / "lib" / "next.py").read_text()
    results.append(check(
        "reencargar trabajo esta acotado por las iteraciones del presupuesto",
        "iteraciones_agotadas" in src_next and "33.3" in src_next,
        "el limite de reintentos ya existe en la spec; no hace falta otro"))

    src_feat = (ROOT / "cli" / "commands" / "feature.sh").read_text()
    results.append(check(
        "cada encargo consume una iteracion",
        "budget consume" in src_feat))

    # Un loop que se planta sin decir por que obliga a adivinar entre
    # "termino" y "no puedo seguir". No es lo mismo.
    results.append(check(
        "cuando el avance esta frenado, el loop dice el motivo",
        "frenos" in src_next and "el avance esta frenado" in src_next))
    results.append(check(
        "y run lo muestra en la consola",
        "el loop se detiene porque el avance esta frenado" in
        (ROOT / "cli" / "commands" / "run.sh").read_text()))
    # Esperar un ESTADO no alcanza: un agente se asienta apenas recibe el
    # prompt, antes de trabajar. Con eso el paso miraba el disco, no encontraba
    # nada y reportaba exito igual; el loop lo contaba como avance y reencargaba
    # lo mismo hasta agotar el presupuesto. La condicion de terminacion es el
    # ARTEFACTO.
    results.append(check(
        "work espera el entregable, no un estado del runtime",
        "wait_agent" in src_feat and "esperando el entregable" in src_feat
        and "_limite" in src_feat,
        "devolver apenas se entrega el prompt deja a quien llama sin saber si hubo trabajo"))

    # El adapter no puede creerle al ledger sobre un recurso que puede morirse.
    src_herdr = (ROOT / "adapters" / "herdr" / "run.sh").read_text()
    results.append(check(
        "start_agent reconcilia contra los agentes vivos, no contra el ledger",
        "agent list" in src_herdr and "puede MORIRSE" in src_herdr,
        "el ledger dice que se hizo una vez; no dice que siga corriendo"))

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
