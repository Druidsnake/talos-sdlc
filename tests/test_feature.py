"""Auditoria del ejecutor de transiciones y de thalos feature start.

Paso 8 de la ruta de implementacion (seccion 51).

Es la primera pieza que hace AVANZAR el estado. Hasta el paso 7 Thalos sabia
evaluar una transicion y nada la ejecutaba. Estos checks verifican que el
avance solo ocurra cuando el gate autoriza, que quede registrado en el event
log y que un fallo no deje el sistema en un estado peor que antes.
"""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"

sys.path.insert(0, str(ROOT / "hooks" / "lib"))
import lock as lock_lib  # noqa: E402


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def feature(fid, risk="low", tier="fast", human=False, deps=None):
    return {"id": fid, "title": f"feature {fid}", "effort": "medium",
            "risk": risk, "capability_tier": tier,
            "human_approval_required": human, "depends_on": deps or []}


def project():
    """Proyecto desechable con Thalos vendoreado y un plan valido."""
    d = pathlib.Path(tempfile.mkdtemp())
    (d / ".thalos").mkdir()
    for sub in ("cli", "hooks", "schemas", "system", "config", "adapters", "roles"):
        shutil.copytree(ROOT / sub, d / ".thalos" / sub)
    shutil.copy(ROOT / "VERSION", d / ".thalos" / "VERSION")
    if (ROOT / ".venv").is_dir():
        (d / ".venv").symlink_to(ROOT / ".venv")

    subprocess.run(["git", "init", "-q"], cwd=d, capture_output=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=d, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t.t"], cwd=d, capture_output=True)
    thalos(d, "init")

    digest = "sha256:" + "c" * 64
    plan = {"schema_version": 1, "project": "prueba", "spec_digest": digest,
            "created_by": "role:Planner", "created_at": "2026-07-31T00:00:00Z",
            "features": [feature("F001"),
                         feature("F002", deps=["F001"]),
                         feature("F003", deps=["F001"])]}
    (d / "orchestration" / "program-plan.json").write_text(json.dumps(plan))
    return d


def thalos(root, *args):
    p = subprocess.run(
        [str(root / ".thalos" / "cli" / "thalos"), *args],
        capture_output=True, text=True, cwd=root,
        env={"PATH": "/usr/bin:/bin:/usr/local/bin",
             "HOME": str(pathlib.Path.home()),
             "THALOS_PROJECT_ROOT": str(root)})
    return p.returncode, p.stdout + p.stderr


def state_of(root, fid):
    f = root / "orchestration" / "features" / fid / "state.json"
    if not f.is_file():
        return None
    return json.loads(f.read_text())


# El contador hace que observe_agent devuelva un state_change_seq distinto en
# cada llamada. Sin eso no hay transicion que observar y todo encargo terminaria
# en NOT_DELIVERED: el ACK es justamente ver moverse ese contador
# (thalos-mensajeria-0.0.1.md seccion 7).
SPY = """#!/bin/sh
# Adapter espia: registra que le pidieron y responde lo minimo viable.
printf '%s\\t%s\\n' "$1" "${2:-}" >> "${THALOS_PROJECT_ROOT:-.}/spy.log"
_n=$(cat "${THALOS_PROJECT_ROOT:-.}/spy.seq" 2>/dev/null || echo 0)
_n=$((_n + 1))
echo "$_n" > "${THALOS_PROJECT_ROOT:-.}/spy.seq"
case "$1" in
    create_session)
        echo '{"status":"created","resource_ref":{"id":"spy:pane","url":null},"dry_run":false}' ;;
    start_agent)
        echo '{"status":"created","resource_ref":{"id":"spy:term","url":null},"dry_run":false}' ;;
    observe_agent)
        printf '{"pane_exists":true,"state":"idle","state_change_seq":%s,' "$_n"
        echo '"process_alive":true,"process_observed":true,"dry_run":false}' ;;
    *)
        echo '{"status":"ok","dry_run":false,"result":{}}' ;;
esac
"""


def espia(root, impl="thalos.adapter.spy"):
    """Liga ExecutionAdapter a un adapter que anota lo que le piden.

    Se toca la tabla generada, que es la fuente que usa el resolvedor del
    nucleo: cambiar la ligadura es exactamente lo que hace una instalacion al
    pasar de simulacion a produccion.
    """
    d = root / ".thalos" / "adapters" / "spy"
    if not d.is_dir():
        d.mkdir(parents=True)
        (d / "run.sh").write_text(SPY)
        (d / "run.sh").chmod(0o755)
    tabla = root / ".thalos" / "hooks" / "generated" / "capabilities.tsv"
    filas = []
    for linea in tabla.read_text().splitlines():
        campos = linea.split("\t")
        if len(campos) > 3 and campos[0] == "ExecutionAdapter":
            campos[2], campos[3] = impl, "adapters/spy"
            linea = "\t".join(campos)
        filas.append(linea)
    tabla.write_text("\n".join(filas) + "\n")
    return root / "spy.log"


def spy_lines(log, op):
    if not log.is_file():
        return []
    return [l.split("\t", 1)[1] if "\t" in l else ""
            for l in log.read_text().splitlines() if l.startswith(op + "\t")]


def events(root):
    """El EventLog son segmentos .ndjson, un evento por linea."""
    d = root / "orchestration" / "events"
    out = []
    for f in sorted(d.glob("*.ndjson")) if d.is_dir() else []:
        for line in f.read_text().splitlines():
            if line.strip():
                out.append(json.loads(line))
    return sorted(out, key=lambda e: e["seq"])


def main():
    results = []

    # ---------- LockManager ----------

    lp = str(pathlib.Path(tempfile.mkdtemp()) / "locks.json")
    lease, _, conflict = lock_lib.acquire(lp, "branch:main", "F001", "r-1", "test")
    results.append(check("se otorga un lease sobre un recurso libre",
                         lease is not None and conflict is None))

    _, _, conflict = lock_lib.acquire(lp, "branch:main", "F002", "r-1", "test")
    results.append(check(
        "RECHAZA un segundo lease sobre el mismo recurso (regla 32.4.1)",
        conflict is not None and conflict["owner_feature"] == "F001"))

    otro, _, conflict = lock_lib.acquire(lp, "branch:otra", "F002", "r-1", "test")
    results.append(check("dos recursos distintos no se estorban",
                         otro is not None and conflict is None))

    # Regla 32.2.4: el heartbeat extiende expires_at.
    antes = lease["expires_at"]
    import time
    time.sleep(1.1)
    hb = lock_lib.heartbeat(lp, lease["lease_id"])
    results.append(check("el heartbeat extiende la expiracion (regla 32.2.4)",
                         hb and hb["expires_at"] > antes,
                         f"{antes} -> {hb['expires_at'] if hb else None}"))

    # Reglas 32.2.5 y 32.3: al expirar cae el lease y sube el fencing token.
    lp2 = str(pathlib.Path(tempfile.mkdtemp()) / "locks.json")
    corto, _, _ = lock_lib.acquire(lp2, "branch:x", "F001", "r-1", "test", ttl=30)
    doc = lock_lib.load(lp2)
    doc["leases"][0]["expires_at"] = "2020-01-01T00:00:00Z"
    lock_lib.save(lp2, doc)
    nuevo, expirados, conflict = lock_lib.acquire(lp2, "branch:x", "F002", "r-1", "test")
    results.append(check(
        "un lease vencido se barre y el recurso queda libre (regla 32.2.5)",
        nuevo is not None and conflict is None and len(expirados) == 1))
    results.append(check(
        "generation sube al expirar: es el fencing token (regla 32.3)",
        nuevo["generation"] > corto["generation"],
        f"{corto['generation']} -> {nuevo['generation']}"))

    # Una feature NO compite consigo misma. La regla 32.4.1 habla de dos
    # features distintas; sin esta excepcion, un reintento tras una caida deja
    # a la feature afuera de su propio recurso hasta que venza el TTL.
    lp3 = str(pathlib.Path(tempfile.mkdtemp()) / "locks.json")
    primero, _, _ = lock_lib.acquire(lp3, "branch:x", "F001", "r-1", "test")
    otra_vez, _, conflicto = lock_lib.acquire(lp3, "branch:x", "F001", "r-1", "test")
    results.append(check(
        "la misma feature en la misma corrida puede retomar su propio lease",
        conflicto is None and otra_vez is not None
        and otra_vez["lease_id"] == primero["lease_id"],
        f"conflicto={conflicto}"))
    results.append(check(
        "y no se otorga un segundo lease sobre el mismo recurso",
        len(lock_lib.load(lp3)["leases"]) == 1))

    # Otra corrida de la misma feature SI se serializa: la anterior puede
    # seguir viva y desde aca no se puede saber.
    _, _, conflicto = lock_lib.acquire(lp3, "branch:x", "F001", "r-2", "test")
    results.append(check(
        "otra corrida de la misma feature si espera (el zombi no se asume muerto)",
        conflicto is not None, f"{conflicto}"))

    locks_schema = Draft202012Validator(
        json.loads((SCHEMAS / "locks.schema.json").read_text()))
    results.append(check(
        "locks.json valida contra locks.schema.json",
        not list(locks_schema.iter_errors(
            lock_lib.clean_for_schema(lock_lib.load(lp2))))))

    # ---------- feature start ----------

    proj = project()

    code, out = thalos(proj, "feature", "start", "F001")
    results.append(check("feature start lleva a FEATURE_IN_PROGRESS",
                         code == 0, f"exit={code} {out[-300:]}"))

    st = state_of(proj, "F001")
    results.append(check(
        "el estado proyectado queda en FEATURE_IN_PROGRESS",
        st and st["state"] == "FEATURE_IN_PROGRESS",
        f"{st['state'] if st else None}"))

    fs_schema = Draft202012Validator(
        json.loads((SCHEMAS / "feature-state.schema.json").read_text()))
    results.append(check(
        "feature-state valida contra su schema",
        st and not list(fs_schema.iter_errors(st)),
        "; ".join(e.message[:80] for e in fs_schema.iter_errors(st)) if st else ""))

    results.append(check(
        "el estado registra issue, rama y lease",
        st and st["issue_ref"] and st["branch_ref"] and st["leases"],
        f"{st.get('issue_ref')} {st.get('branch_ref')} {st.get('leases')}" if st else ""))

    # Regla 22.6.5: exactamente un evento por transicion, y en orden.
    evs = events(proj)
    tipos = [e["type"] for e in evs]
    results.append(check(
        "emite thalos.feature.ready y thalos.feature.started, en ese orden",
        tipos == ["thalos.feature.ready", "thalos.feature.started"], f"{tipos}"))

    # Un log vacio haria pasar este check sin probar nada: se exige que haya
    # eventos antes de afirmar que ninguno es un rechazo.
    results.append(check(
        "no emite ningun thalos.transition.rejected en el camino feliz",
        tipos and "thalos.transition.rejected" not in tipos, f"{tipos}"))

    # Regla 22.6.7: la transicion se reconstruye desde el event log.
    results.append(check(
        "los eventos son consecutivos desde 1 (regla 41.2)",
        evs and [e["seq"] for e in evs] == list(range(1, len(evs) + 1)),
        f"{[e['seq'] for e in evs]}"))

    ev_schema = Draft202012Validator(
        json.loads((SCHEMAS / "event.schema.json").read_text()))
    malos = [e["type"] for e in evs if list(ev_schema.iter_errors(e))]
    results.append(check("todo evento emitido valida contra event.schema.json",
                         evs and not malos, f"{malos}"))

    # Regla 22.6.6: el GateResult que autorizo queda registrado.
    gate_evs = list((proj / "orchestration" / "evidence").glob("ev-gate-*.json"))
    results.append(check(
        "queda persistido el GateResult que autorizo la transicion (22.6.6)",
        len(gate_evs) >= 1, f"{len(gate_evs)}"))

    feature_evs = [e for e in evs if e["type"].startswith("thalos.feature")]
    results.append(check(
        "el evento referencia la evidencia que lo justifica",
        feature_evs and all(e.get("evidence_refs") for e in feature_evs),
        f"{[e.get('evidence_refs') for e in evs]}"))

    # ---------- rechazo ----------

    # Una dependencia que no termino bloquea: transicion F3.
    code, out = thalos(proj, "feature", "start", "F002")
    results.append(check(
        "RECHAZA arrancar con una dependencia sin FEATURE_DONE",
        code == 3 and "F001" in out, f"exit={code}"))

    results.append(check(
        "la feature bloqueada no queda con estado",
        state_of(proj, "F002") is None))

    # Reejecutar start sobre una feature ya arrancada no puede retrocederla.
    code, out = thalos(proj, "feature", "start", "F001")
    st2 = state_of(proj, "F001")
    results.append(check(
        "reejecutar start NO retrocede el estado a FEATURE_READY",
        code == 2 and st2["state"] == "FEATURE_IN_PROGRESS",
        f"exit={code} state={st2['state']}"))

    # Un start fallido no puede dejar leases huerfanos.
    proj2 = project()
    thalos(proj2, "feature", "start", "F001")
    doc = lock_lib.load(str(proj2 / "orchestration" / "locks.json"))
    recursos = [x["resource"] for x in doc["leases"]]
    results.append(check(
        "el lease de la feature arrancada queda tomado",
        "branch:feature/F001" in recursos, f"{recursos}"))

    thalos(proj2, "feature", "start", "F003")
    doc = lock_lib.load(str(proj2 / "orchestration" / "locks.json"))
    results.append(check(
        "un start rechazado no deja lease huerfano",
        len(doc["leases"]) == 1, f"{[x['resource'] for x in doc['leases']]}"))

    # ---------- despacho con rol (secciones 18 a 21) ----------
    #
    # Hasta ahora roles/ y config/roles.yaml eran declaraciones que nunca
    # llegaban al agente: Thalos lanzaba un agente pelado, con permisos
    # completos. El enforcement existia del lado del sistema y no del lado del
    # trabajo, que es donde tiene que estar.

    prol = project()
    thalos(prol, "feature", "start", "F001")

    # Fail-closed: un rol que no esta en el registro de scope no se despacha.
    # Sin scope, el bloqueo dejaria pasar todo.
    code, out = thalos(prol, "feature", "dispatch", "F001",
                      "--role", "Intruso", "--pane", "w1:p1")
    results.append(check(
        "RECHAZA despachar un rol que no existe en el registro de scope",
        code == 2 and "desconocido" in out, f"exit={code}"))

    results.append(check(
        "un despacho rechazado no deja rol activo",
        not (prol / "orchestration" / ".current-role").exists()))

    # No se despacha un agente sobre una feature que no arranco.
    #
    # La condicion es que la feature siga VIVA, no que este en un estado
    # concreto: exigir FEATURE_IN_PROGRESS estaba escrito para un solo rol, y
    # el Reviewer trabaja con la feature en FEATURE_REVIEW. El loop proponia
    # despacharlo y el despacho lo mandaba a arrancar algo ya arrancado.
    code, out = thalos(prol, "feature", "dispatch", "F002",
                      "--role", "Developer", "--pane", "w1:p1")
    results.append(check(
        "RECHAZA despachar sobre una feature que no arranco",
        code == 2 and "no arranco" in out, f"exit={code} {out[-200:]}"))

    # El brief lleva instrucciones Y alcance: las instrucciones solas no dicen
    # que rutas puede tocar en esta corrida.
    script = (f'. "{ROOT}/hooks/lib/role.sh"; thalos_role_brief Developer F001')
    brief = subprocess.run(["sh", "-c", script], capture_output=True, text=True,
                           env={"PATH": "/usr/bin:/bin",
                                "THALOS_SYSTEM_ROOT": str(ROOT),
                                "HOME": str(pathlib.Path.home())}).stdout
    results.append(check(
        "el brief declara el alcance concreto de escritura",
        "permitido  src/**" in brief and "prohibido  spec/**" in brief,
        brief[:200]))
    results.append(check(
        "el brief incluye las instrucciones del rol",
        "Rol: Developer" in brief, brief[-200:]))
    results.append(check(
        "el brief dice que el bloqueo no negocia",
        "no consulta al agente" in brief))

    # El mecanismo 2 tiene que denegar de verdad con ese rol.
    def scope(role, path):
        return subprocess.run(
            [str(ROOT / "hooks" / "check-write-scope.sh"), role, path],
            capture_output=True).returncode

    results.append(check("Developer PUEDE escribir en src/", scope("Developer", "src/a.ts") == 0))
    results.append(check("Developer NO puede escribir en spec/", scope("Developer", "spec/x.md") != 0))
    results.append(check("Developer NO puede escribir en orchestration/",
                         scope("Developer", "orchestration/state.json") != 0))
    results.append(check("Developer NO puede tocar los workflows de CI",
                         scope("Developer", ".github/workflows/ci.yml") != 0))

    # EL BLOQUEO CON THALOS VENDOREADO.
    #
    # check-tool-call.sh calculaba la raiz como dirname(hooks/), que con Thalos
    # en .thalos/ da .thalos/ y no el proyecto. Ahi no hay
    # orchestration/.current-role, el rol quedaba vacio, y la regla "sin rol la
    # llamada pasa" dejaba pasar TODO. El mecanismo 2 estaba inerte justo en la
    # instalacion normal, y sin decirlo.
    vend = project()
    (vend / "orchestration").mkdir(exist_ok=True)
    (vend / "orchestration" / ".current-role").write_text("Developer\n")

    def hook(path_rel, root):
        payload = json.dumps({"tool_name": "Write",
                              "tool_input": {"file_path": path_rel}})
        p = subprocess.run(
            [str(root / ".thalos" / "hooks" / "agent" / "claude-code" / "pre-tool-use.sh")],
            input=payload, capture_output=True, text=True, cwd=root,
            env={"PATH": "/usr/bin:/bin:/usr/local/bin",
                 "HOME": str(pathlib.Path.home())})
        return p.returncode

    results.append(check(
        "con Thalos vendoreado, el bloqueo PERMITE lo que el rol permite",
        hook("src/a.py", vend) == 0))
    results.append(check(
        "y DENIEGA lo que el rol prohibe (mecanismo 2 vivo con .thalos/)",
        hook("spec/x.md", vend) != 0,
        "sin esto el bloqueo queda inerte en toda instalacion normal"))
    results.append(check(
        "tambien deniega orchestration/, que es del sistema",
        hook("orchestration/state.json", vend) != 0))

    # El adapter no puede saber de roles: que rol se despacha es politica del
    # nucleo, lanzar el proceso es ciclo de vida (seccion 38.5).
    adapter_src = (ROOT / "adapters" / "herdr" / "run.sh").read_text()
    results.append(check(
        "el ExecutionAdapter no conoce roles ni scope (seccion 38.5)",
        "roles.yaml" not in adapter_src and "write_paths" not in adapter_src
        and "current-role" not in adapter_src))

    # ---------- la referencia del agente lleva procedencia ----------
    #
    # Un ExecutionAdapter devuelve ids que solo el sabe interpretar. Guardar el
    # pane pelado, sin decir quien lo produjo, hacia que al cambiar la ligadura
    # el paso siguiente le mandara a un adapter productivo un id fabricado por
    # el simulador: el backend contestaba "no existe" y el fallo aparecia a dos
    # comandos de distancia de su causa.

    pa = project()
    thalos(pa, "feature", "start", "F001")
    log = espia(pa)
    code, out = thalos(pa, "feature", "dispatch", "F001", "--role", "Developer")
    ref_p = pa / "orchestration" / "features" / "F001" / ".agent"
    results.append(check(
        "dispatch registra la referencia del agente",
        code == 0 and ref_p.is_file(), f"exit={code} {out[-300:]}"))
    ref = json.loads(ref_p.read_text()) if ref_p.is_file() else {}
    results.append(check(
        "la referencia dice QUE adapter la produjo (regla 37.4.3.5 del lado del dato)",
        ref.get("adapter") == "thalos.adapter.spy", f"{ref}"))
    # El nombre lleva el PROYECTO adentro: el espacio de nombres del runtime
    # de ejecucion es de la maquina, y dos proyectos con una F001 pedian el
    # mismo agente. El segundo se quedaba sin agente propio y le mandaba su
    # trabajo al del primero, que corre en otro repo.
    # El nombre distingue PROYECTO y ROL. El espacio de nombres del runtime es
    # de la maquina y el adapter reconcilia por nombre: sin el proyecto, dos
    # repos con una F001 se robaban el agente; sin el rol, despachar un
    # Reviewer sobre una feature que ya tuvo Developer reusaba al Developer, y
    # el Reviewer terminaba revisando su propio trabajo.
    nombre = ref.get("name") or ""
    results.append(check(
        "el nombre del agente distingue proyecto y rol, no solo la feature",
        nombre.startswith("thalos_") and nombre.endswith("_f001_deve")
        and pa.name.lower().replace("-", "_")[:8] in nombre,
        f"{nombre} para el proyecto {pa.name}"))
    # El runtime acota el nombre y lo rechaza si se pasa: minusculas, digitos,
    # - o _, hasta 32. Un nombre invalido falla en el arranque diciendo
    # invalid_agent_name, que suena a problema del despacho y no lo es.
    import re as _re
    results.append(check(
        "y respeta el formato que el runtime acepta (<=32, [a-z0-9_-])",
        bool(_re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", nombre)),
        f"{nombre!r} ({len(nombre)} caracteres)"))
    results.append(check(
        "el pane queda como dato de la referencia, no como archivo suelto",
        ref.get("pane") == "spy:pane"
        and not (pa / "orchestration" / "features" / "F001" / ".pane").exists(),
        f"{ref}"))

    # El target de una operacion de agente es el NOMBRE, no el pane. Un pane
    # puede quedar vacio, reciclado o con el shell de una persona; el nombre lo
    # controla Thalos.
    code, out = thalos(pa, "feature", "work", "F001", "--timeout", "3")
    agente = ref.get("name")
    prompts = spy_lines(log, "prompt_agent")
    results.append(check(
        "work le habla al agente por su nombre, no por el pane",
        prompts and f'"target":"{agente}"' in prompts[0]
        and '"target":"spy:pane"' not in prompts[0],
        f"{prompts[:1]}"))
    # Se OBSERVA, no se espera. wait_agent bloquea hasta que el agente se
    # asienta y devuelve un estado que sobrevive a la muerte de quien lo
    # reporto; observe_agent es una foto que trae ademas si el proceso vive.
    esperas = spy_lines(log, "observe_agent")
    results.append(check(
        "y observa al mismo target con el que encargo",
        esperas and f'"target":"{agente}"' in esperas[0], f"{esperas[:1]}"))
    # El adapter espia nunca deja entregable: ese es el caso que importa.
    # Reportar exito sin el artefacto hacia que el loop lo contara como avance
    # y reencargara lo mismo hasta agotar el presupuesto.
    results.append(check(
        "un paso que no produjo su entregable NO reporta exito",
        code == 3 and "sin dejar entregable" in out, f"exit={code} {out[-200:]}"))

    # LA REGRESION: cambiar la ligadura invalida la referencia vieja.
    espia(pa, impl="thalos.adapter.otro")
    code, out = thalos(pa, "feature", "work", "F001", "--timeout", "3")
    results.append(check(
        "RECHAZA usar una referencia que produjo otro ExecutionAdapter",
        code == 2 and "otro adapter" in out, f"exit={code} {out[-300:]}"))
    results.append(check(
        "y dice cual quedo registrada y cual esta ligada hoy",
        "thalos.adapter.spy" in out and "thalos.adapter.otro" in out, out[-300:]))
    results.append(check(
        "no se le entrego trabajo a nadie con la referencia invalida",
        len(spy_lines(log, "prompt_agent")) == 1,
        f"{spy_lines(log, 'prompt_agent')}"))

    # El rol y la referencia se sueltan juntos. Una referencia que sobrevive al
    # rol apunta a un agente que ya nadie gobierna.
    #
    # Se vuelve a ligar el adapter que abrio la sesion: cerrar un panel cuyo id
    # es de otro adapter seria cerrarle el panel a cualquiera.
    espia(pa)
    code, out = thalos(pa, "feature", "release", "F001")
    results.append(check(
        "release suelta tambien la referencia del agente",
        not ref_p.exists()))
    # Instalar es reversible o no es instalar. Lo que el shim dejo en el
    # proyecto se retira entero: el brief Y el bloqueo. Un bloqueo que
    # sobrevive al rol queda apuntando a una ruta de .thalos/ y gobernando una
    # sesion que Thalos ya solto.
    results.append(check(
        "release no deja briefs ni bloqueos en el proyecto",
        not (pa / "AGENTS.md").exists() and not (pa / "CLAUDE.md").exists()
        and not (pa / ".opencode" / "plugin" / "thalos-scope.js").exists(),
        f"{[str(x) for x in (pa / '.opencode').rglob('*') if x.is_file()]}"))
    _cs = pa / ".claude" / "settings.json"
    results.append(check(
        "y el hook de Claude Code no queda registrado tras liberar",
        not _cs.exists() or "pre-tool-use.sh" not in _cs.read_text(),
        _cs.read_text()[:200] if _cs.exists() else ""))

    cierres = spy_lines(log, "close_session")
    results.append(check(
        "y cierra la sesion que Thalos abrio (seccion 38.5)",
        cierres and '"pane":"spy:pane"' in cierres[0],
        f"{cierres[:1]} {out[-200:]}"))
    results.append(check(
        "el cierre se reporta a quien libera",
        "spy:pane" in out and "cerrada" in out, out[-300:]))
    code, out = thalos(pa, "feature", "work", "F001", "--timeout", "3")
    results.append(check(
        "sin referencia, work manda a despachar en vez de adivinar un target",
        code == 2 and "dispatch" in out, f"exit={code} {out[-300:]}"))

    # ---------- el runtime y el modelo salen de la config ----------
    #
    # El nucleo no nombra modelos: conoce tiers (seccion 20.3). El plan le pone
    # el tier a la feature por su RIESGO, config/models.yaml traduce tier a
    # modelo y proveedor, y el shim del runtime traduce eso a la bandera nativa
    # que entiende su agente. Cablear un runtime por defecto haria que cambiar
    # de proveedor en la config despachara igual el agente de antes.
    pm = project()
    thalos(pm, "feature", "start", "F001")
    logm = espia(pm)
    (pm / ".thalos" / "config" / "models.yaml").write_text(
        "version: 1\ntiers:\n"
        "  fast:\n    model: proveedor-x/modelo-y\n    provider: opencode\n"
        "  balanced:\n    model: b\n    provider: opencode\n"
        "  deep:\n    model: d\n    provider: opencode\n")
    code, out = thalos(pm, "feature", "dispatch", "F001", "--role", "Developer")
    results.append(check(
        "dispatch elige el runtime que declara el proveedor del tier",
        code == 0 and (pm / "orchestration" / "features" / "F001" / ".runtime").is_file()
        and (pm / "orchestration" / "features" / "F001" / ".runtime").read_text().strip() == "opencode",
        f"exit={code} {out[-300:]}"))
    arranques = spy_lines(logm, "start_agent")
    results.append(check(
        "y le pasa el modelo del tier como argumento nativo del agente",
        arranques and "--model proveedor-x/modelo-y" in arranques[0],
        f"{arranques[:1]}"))
    results.append(check(
        "el despacho dice que modelo y que tier quedaron aplicados",
        "proveedor-x/modelo-y" in out and "tier fast" in out, out[-400:]))

    # Un modelo de otro proveedor no se le pasa a este runtime: arrancaria con
    # una cadena que no resuelve y fallaria lejos de aca.
    ajeno = subprocess.run(
        [str(ROOT / "hooks" / "agent" / "opencode" / "agent-args.sh"),
         "claude-opus-5", "claude"], capture_output=True, text=True)
    results.append(check(
        "el shim ignora un modelo que no es de su proveedor",
        ajeno.stdout.strip() == "", f"emitio {ajeno.stdout!r}"))

    # ---------- un agente bloqueado no es un agente que fracaso ----------
    #
    # wait_agent se llamaba y su resultado se tiraba. Con eso, "esta bloqueado
    # pidiendo permiso" y "termino" eran indistinguibles: se reportaba que el
    # agente no dejo entregable cuando en realidad no habia llegado a empezar.
    pblock = project()
    thalos(pblock, "feature", "start", "F001")
    esp = pblock / ".thalos" / "adapters" / "spy"
    espia(pblock)
    (esp / "run.sh").write_text(
        '#!/bin/sh\n'
        'printf \'%s\\t%s\\n\' "$1" "${2:-}" >> "${THALOS_PROJECT_ROOT:-.}/spy.log"\n'
        'case "$1" in\n'
        '  create_session) echo \'{"status":"created","resource_ref":{"id":"spy:pane","url":null},"dry_run":false}\' ;;\n'
        '  start_agent) echo \'{"status":"created","resource_ref":{"id":"spy:term","url":null},"dry_run":false}\' ;;\n'
        '  observe_agent)\n'
        '     _n=$(cat "${THALOS_PROJECT_ROOT:-.}/spy.seq" 2>/dev/null || echo 0)\n'
        '     _n=$((_n + 1)); echo "$_n" > "${THALOS_PROJECT_ROOT:-.}/spy.seq"\n'
        '     printf \'{"pane_exists":true,"state":"blocked","state_change_seq":%s,\' "$_n"\n'
        '     echo \'"process_alive":true,"process_observed":true,"dry_run":false}\' ;;\n'
        '  *) echo \'{"status":"ok","dry_run":false,"result":{}}\' ;;\n'
        'esac\n')
    (esp / "run.sh").chmod(0o755)
    thalos(pblock, "feature", "dispatch", "F001", "--role", "Developer")
    # El plazo tiene que alcanzar para blocked_confirm_samples muestras
    # consecutivas: un bloqueo momentaneo no es un bloqueo (regla 5.3.5), y con
    # un plazo corto el veredicto seria EXPIRED antes de poder confirmarlo.
    code, out = thalos(pblock, "feature", "work", "F001", "--timeout", "25")
    results.append(check(
        "un agente bloqueado sale needs_human (4), no exito silencioso",
        code == 4, f"exit={code} {out[-300:]}"))
    results.append(check(
        "y lo dice: bloqueado, no 'termino sin entregable'",
        "BLOQUEADO" in out and "termino sin dejar entregable" not in out,
        out[-400:]))
    results.append(check(
        "y dice donde mirar",
        "spy:pane" in out, out[-200:]))

    # El shim tiene que arrancar al agente sin dialogos de permiso: un sistema
    # que despacha agentes para que trabajen solos y los deja esperando a una
    # persona por cada paso no despacha nada. Lo que lo contiene es el hook.
    aa = subprocess.run(
        [str(ROOT / "hooks" / "agent" / "opencode" / "agent-args.sh"), "m/x", "opencode"],
        capture_output=True, text=True)
    results.append(check(
        "el shim de opencode arranca al agente sin dialogos de permiso",
        "--auto" in aa.stdout and "--model m/x" in aa.stdout, aa.stdout))

    # ---------- la comunicacion no se pierde ----------
    #
    # Un agente que no puede seguir contesta como sabe: en prosa, con una
    # pregunta, a veces con ruido de su interfaz. Thalos esperaba un archivo con
    # un formato y descartaba todo lo demas: el motivo existia y no llegaba a
    # nadie. La seccion 25 ya definia el canal entero -tipos, estados, hilos- y
    # no lo implementaba nadie.
    pmsg = project()
    thalos(pmsg, "feature", "start", "F001")
    esp2 = pmsg / ".thalos" / "adapters" / "spy"
    espia(pmsg)
    (esp2 / "run.sh").write_text(
        '#!/bin/sh\n'
        'printf \'%s\\t%s\\n\' "$1" "${2:-}" >> "${THALOS_PROJECT_ROOT:-.}/spy.log"\n'
        'case "$1" in\n'
        '  create_session) echo \'{"status":"created","resource_ref":{"id":"spy:pane","url":null},"dry_run":false}\' ;;\n'
        '  start_agent) echo \'{"status":"created","resource_ref":{"id":"spy:term","url":null},"dry_run":false}\' ;;\n'
        '  read_agent) echo \'{"status":"ok","dry_run":false,"result":{"output":"No puedo seguir: el repo ya tiene memorias de F001 y el arbol esta vacio. Confirmame si reiniciaron el workspace."}}\' ;;\n'
        '  *) echo \'{"status":"ok","dry_run":false,"result":{}}\' ;;\n'
        'esac\n')
    (esp2 / "run.sh").chmod(0o755)
    thalos(pmsg, "feature", "dispatch", "F001", "--role", "Developer")
    code, out = thalos(pmsg, "feature", "work", "F001", "--timeout", "3")

    msgs = list((pmsg / "orchestration" / "messages").glob("msg-*.json"))
    results.append(check(
        "lo que el agente dijo queda registrado, aunque sea prosa suelta",
        len(msgs) == 1, f"{[m.name for m in msgs]}"))
    m = json.loads(msgs[0].read_text()) if msgs else {}
    results.append(check(
        "el mensaje conserva el texto tal cual, sin exigirle formato",
        "No puedo seguir" in (m.get("payload") or {}).get("text", ""),
        f"{(m.get('payload') or {}).get('text','')[:80]}"))
    results.append(check(
        "y el sobre dice quien lo dijo, a quien y sobre que",
        m.get("from") == "role:Developer" and m.get("to") == "human:operator"
        and m.get("feature_id") == "F001" and m.get("state") == "OPEN"
        and m.get("type") == "QUESTION",
        f"{m.get('from')} -> {m.get('to')} {m.get('type')} {m.get('state')}"))
    results.append(check(
        "el paso le dice a quien mira como leerlo y como contestar",
        "thalos message show" in out and "thalos message answer" in out,
        out[-300:]))

    # Contestar cierra el circuito: se registra Y se entrega.
    logm2 = pmsg / "spy.log"
    prev = len(spy_lines(logm2, "prompt_agent"))
    code, out = thalos(pmsg, "message", "answer", m.get("id", "x"),
                      "--text", "Si, el workspace se reinicio a proposito. Segui.")
    results.append(check(
        "responder entrega la respuesta al agente, no solo la escribe",
        code == 0 and len(spy_lines(logm2, "prompt_agent")) == prev + 1,
        f"exit={code} {out[-200:]}"))
    resp = [json.loads(f.read_text())
            for f in sorted((pmsg / "orchestration" / "messages").glob("msg-*.json"))]
    results.append(check(
        "la respuesta queda en el mismo hilo y referencia la pregunta",
        len(resp) == 2 and resp[1]["type"] == "ANSWER"
        and resp[1]["thread_id"] == resp[0]["thread_id"]
        and resp[1]["in_reply_to"] == resp[0]["id"],
        f"{[(x['id'], x['type'], x['in_reply_to']) for x in resp]}"))
    results.append(check(
        "y la pregunta queda ANSWERED, no abierta para siempre",
        resp[0]["state"] == "ANSWERED" if resp else False,
        f"{resp[0]['state'] if resp else '-'}"))

    # ---------- dos roles sobre la misma feature no comparten sesion ----------
    #
    # La identidad de la sesion tiene que incluir el ROL. Sin eso la
    # idempotency key de dos despachos sobre la misma feature es la misma, el
    # ledger le devuelve al segundo el panel del primero, y dos agentes no
    # entran en un panel. Ademas soltar al anterior DESPUES de pedir la sesion
    # cerraba el panel recien resuelto -son el mismo- y el arranque fallaba con
    # "pane not found" sobre algo que Thalos habia cerrado un segundo antes.
    pdos = project()
    thalos(pdos, "feature", "start", "F001")
    logd = espia(pdos)
    thalos(pdos, "feature", "dispatch", "F001", "--role", "Developer")
    ref_dev = json.loads((pdos / "orchestration" / "features" / "F001" / ".agent").read_text())
    code, out = thalos(pdos, "feature", "dispatch", "F001", "--role", "Reviewer")
    ref_rev = json.loads((pdos / "orchestration" / "features" / "F001" / ".agent").read_text())
    results.append(check(
        "despachar otro rol sobre la misma feature funciona",
        code == 0, f"exit={code} {out[-300:]}"))
    results.append(check(
        "y le da un agente propio, no el del rol anterior",
        ref_rev.get("name") != ref_dev.get("name")
        and ref_rev.get("name", "").endswith("_revi"),
        f"{ref_dev.get('name')} -> {ref_rev.get('name')}"))
    sesiones = spy_lines(logd, "create_session")
    results.append(check(
        "la sesion que se pide lleva el rol: dos roles, dos sesiones distintas",
        len(sesiones) == 2 and '"role":"Developer"' in sesiones[0]
        and '"role":"Reviewer"' in sesiones[1],
        f"{sesiones}"))
    cierres = spy_lines(logd, "close_session")
    results.append(check(
        "y el agente del rol anterior se suelta al cambiar",
        cierres and '"pane"' in cierres[0], f"{cierres}"))

    # ---------- lo que un shim instala, lo retira ----------
    #
    # Retirar solo el brief dejaba el bloqueo registrado en el runtime de una
    # sesion que Thalos ya no gobierna: apuntando a una ruta de .thalos/ que
    # puede no existir, y aplicando un rol que nadie activo.
    ps = pathlib.Path(tempfile.mkdtemp())
    (ps / ".claude").mkdir()
    # Configuracion ajena que Thalos NO puede pisar al instalar ni al retirar.
    (ps / ".claude" / "settings.json").write_text(json.dumps({
        "model": "el-que-la-persona-eligio",
        "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
            {"type": "command", "command": "/mio/audita.sh"}]}]}}))
    brief = ps / "brief.md"
    brief.write_text("brief de prueba\n")
    inst = ROOT / "hooks" / "agent" / "claude-code" / "install.sh"
    entorno = {"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": str(pathlib.Path.home())}
    subprocess.run([str(inst), str(ps), str(ROOT), str(brief)],
                   capture_output=True, text=True, env=entorno)
    cfg = json.loads((ps / ".claude" / "settings.json").read_text())
    puesto = json.dumps(cfg)
    results.append(check(
        "el shim de Claude Code instala su bloqueo",
        "pre-tool-use.sh" in puesto and (ps / "CLAUDE.md").is_file()))

    subprocess.run([str(inst), str(ps), "--uninstall"],
                   capture_output=True, text=True, env=entorno)
    cfg2 = json.loads((ps / ".claude" / "settings.json").read_text())
    results.append(check(
        "y al retirar no queda registrado",
        "pre-tool-use.sh" not in json.dumps(cfg2) and not (ps / "CLAUDE.md").exists(),
        json.dumps(cfg2)[:200]))
    results.append(check(
        "sin llevarse por delante la configuracion de la persona",
        cfg2.get("model") == "el-que-la-persona-eligio"
        and any(h.get("command") == "/mio/audita.sh"
                for e in (cfg2.get("hooks") or {}).get("PreToolUse", [])
                for h in e.get("hooks", [])),
        json.dumps(cfg2)[:200]))

    # ---------- la chispa: thalos boot ----------
    #
    # Thalos no es inteligente y no tiene por que serlo: abre la sesion, impone
    # el alcance, valida y evalua gates. Decidir el proximo paso SI requiere un
    # modelo, y para eso existe el coordinador. boot lo enciende y se retira.

    pb = project()
    thalos(pb, "feature", "start", "F001")
    logb = espia(pb)
    (pb / ".thalos" / "config" / "models.yaml").write_text(
        "version: 1\ntiers:\n"
        "  fast:\n    model: barato\n    provider: opencode\n"
        "  balanced:\n    model: medio\n    provider: opencode\n"
        "  deep:\n    model: caro\n    provider: opencode\n")
    code, out = thalos(pb, "boot", "F001")
    results.append(check(
        "boot enciende al coordinador de la feature",
        code == 0, f"exit={code} {out[-400:]}"))

    # F001 es de riesgo bajo y el plan le puso tier fast. FeatureLead declara
    # piso deep: max() manda (seccion 20.5), y mirar solo la feature dejaba el
    # minimo del rol declarado y sin efecto.
    arr = spy_lines(logb, "start_agent")
    results.append(check(
        "el tier sale de max(feature, minimo del rol), no solo de la feature",
        arr and "--model caro" in arr[0] and "--model barato" not in arr[0],
        f"{arr[:1]}"))
    results.append(check(
        "y el despacho lo dice: tier deep sobre una feature fast",
        "tier deep" in out, out[-400:]))

    pr = spy_lines(logb, "prompt_agent")
    results.append(check(
        "boot le entrega el encargo de coordinacion, no una tarea",
        pr and "coordinador de F001" in pr[0], f"{pr[:1][:1]}"))
    results.append(check(
        "el encargo incluye la superficie de comandos: la chispa muestra el camino",
        pr and "thalos feature dispatch F001" in pr[0]
        and "thalos feature advance F001" in pr[0],
        "sin los comandos, la chispa muestra una intencion y no un camino"))
    results.append(check(
        "y le dice explicitamente que Thalos deja de conducir",
        "deja de proponer pasos" in out, out[-300:]))

    # El brief del rol tiene que traer la superficie completa, no solo el
    # recordatorio del encargo.
    fl = (ROOT / "roles" / "feature-lead.md").read_text()
    results.append(check(
        "el brief del coordinador declara por donde se pasa",
        "thalos feature release" in fl and "El gate decide, no vos" in fl))

    # ---------- el ejecutor no fuerza ----------

    # Sin evidencia, el ejecutor no avanza aunque se lo pida directo.
    proj3 = project()
    code, out = thalos(proj3, "gate", "feature", "FEATURE_READY",
                      "FEATURE_IN_PROGRESS", "--no-persist")
    results.append(check(
        "sin evidencia el gate niega, y el ejecutor depende del gate",
        code == 3, f"exit={code}"))
    results.append(check(
        "no se creo estado de feature por evaluar un gate",
        not (proj3 / "orchestration" / "features" / "F001").exists()))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks de ejecucion de features")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
