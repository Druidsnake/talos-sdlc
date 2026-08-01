"""Auditoria del ejecutor de transiciones y de talos feature start.

Paso 8 de la ruta de implementacion (seccion 51).

Es la primera pieza que hace AVANZAR el estado. Hasta el paso 7 Talos sabia
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
    """Proyecto desechable con Talos vendoreado y un plan valido."""
    d = pathlib.Path(tempfile.mkdtemp())
    (d / ".talos").mkdir()
    for sub in ("cli", "hooks", "schemas", "system", "config", "adapters", "roles"):
        shutil.copytree(ROOT / sub, d / ".talos" / sub)
    shutil.copy(ROOT / "VERSION", d / ".talos" / "VERSION")
    if (ROOT / ".venv").is_dir():
        (d / ".venv").symlink_to(ROOT / ".venv")

    subprocess.run(["git", "init", "-q"], cwd=d, capture_output=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=d, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t.t"], cwd=d, capture_output=True)
    talos(d, "init")

    digest = "sha256:" + "c" * 64
    plan = {"schema_version": 1, "project": "prueba", "spec_digest": digest,
            "created_by": "role:Planner", "created_at": "2026-07-31T00:00:00Z",
            "features": [feature("F001"),
                         feature("F002", deps=["F001"]),
                         feature("F003", deps=["F001"])]}
    (d / "orchestration" / "program-plan.json").write_text(json.dumps(plan))
    return d


def talos(root, *args):
    p = subprocess.run(
        [str(root / ".talos" / "cli" / "talos"), *args],
        capture_output=True, text=True, cwd=root,
        env={"PATH": "/usr/bin:/bin:/usr/local/bin",
             "HOME": str(pathlib.Path.home()),
             "TALOS_PROJECT_ROOT": str(root)})
    return p.returncode, p.stdout + p.stderr


def state_of(root, fid):
    f = root / "orchestration" / "features" / fid / "state.json"
    if not f.is_file():
        return None
    return json.loads(f.read_text())


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

    code, out = talos(proj, "feature", "start", "F001")
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
        "emite talos.feature.ready y talos.feature.started, en ese orden",
        tipos == ["talos.feature.ready", "talos.feature.started"], f"{tipos}"))

    # Un log vacio haria pasar este check sin probar nada: se exige que haya
    # eventos antes de afirmar que ninguno es un rechazo.
    results.append(check(
        "no emite ningun talos.transition.rejected en el camino feliz",
        tipos and "talos.transition.rejected" not in tipos, f"{tipos}"))

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

    feature_evs = [e for e in evs if e["type"].startswith("talos.feature")]
    results.append(check(
        "el evento referencia la evidencia que lo justifica",
        feature_evs and all(e.get("evidence_refs") for e in feature_evs),
        f"{[e.get('evidence_refs') for e in evs]}"))

    # ---------- rechazo ----------

    # Una dependencia que no termino bloquea: transicion F3.
    code, out = talos(proj, "feature", "start", "F002")
    results.append(check(
        "RECHAZA arrancar con una dependencia sin FEATURE_DONE",
        code == 3 and "F001" in out, f"exit={code}"))

    results.append(check(
        "la feature bloqueada no queda con estado",
        state_of(proj, "F002") is None))

    # Reejecutar start sobre una feature ya arrancada no puede retrocederla.
    code, out = talos(proj, "feature", "start", "F001")
    st2 = state_of(proj, "F001")
    results.append(check(
        "reejecutar start NO retrocede el estado a FEATURE_READY",
        code == 2 and st2["state"] == "FEATURE_IN_PROGRESS",
        f"exit={code} state={st2['state']}"))

    # Un start fallido no puede dejar leases huerfanos.
    proj2 = project()
    talos(proj2, "feature", "start", "F001")
    doc = lock_lib.load(str(proj2 / "orchestration" / "locks.json"))
    recursos = [x["resource"] for x in doc["leases"]]
    results.append(check(
        "el lease de la feature arrancada queda tomado",
        "branch:feature/F001" in recursos, f"{recursos}"))

    talos(proj2, "feature", "start", "F003")
    doc = lock_lib.load(str(proj2 / "orchestration" / "locks.json"))
    results.append(check(
        "un start rechazado no deja lease huerfano",
        len(doc["leases"]) == 1, f"{[x['resource'] for x in doc['leases']]}"))

    # ---------- despacho con rol (secciones 18 a 21) ----------
    #
    # Hasta ahora roles/ y config/roles.yaml eran declaraciones que nunca
    # llegaban al agente: Talos lanzaba un agente pelado, con permisos
    # completos. El enforcement existia del lado del sistema y no del lado del
    # trabajo, que es donde tiene que estar.

    prol = project()
    talos(prol, "feature", "start", "F001")

    # Fail-closed: un rol que no esta en el registro de scope no se despacha.
    # Sin scope, el bloqueo dejaria pasar todo.
    code, out = talos(prol, "feature", "dispatch", "F001",
                      "--role", "Intruso", "--pane", "w1:p1")
    results.append(check(
        "RECHAZA despachar un rol que no existe en el registro de scope",
        code == 2 and "desconocido" in out, f"exit={code}"))

    results.append(check(
        "un despacho rechazado no deja rol activo",
        not (prol / "orchestration" / ".current-role").exists()))

    # No se despacha un agente sobre una feature que no arranco.
    code, out = talos(prol, "feature", "dispatch", "F002",
                      "--role", "Developer", "--pane", "w1:p1")
    results.append(check(
        "RECHAZA despachar sobre una feature que no esta en curso",
        code == 2 and "FEATURE_IN_PROGRESS" in out, f"exit={code}"))

    # El brief lleva instrucciones Y alcance: las instrucciones solas no dicen
    # que rutas puede tocar en esta corrida.
    script = (f'. "{ROOT}/hooks/lib/role.sh"; talos_role_brief Developer F001')
    brief = subprocess.run(["sh", "-c", script], capture_output=True, text=True,
                           env={"PATH": "/usr/bin:/bin",
                                "TALOS_SYSTEM_ROOT": str(ROOT),
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

    # El adapter no puede saber de roles: que rol se despacha es politica del
    # nucleo, lanzar el proceso es ciclo de vida (seccion 38.5).
    adapter_src = (ROOT / "adapters" / "herdr" / "run.sh").read_text()
    results.append(check(
        "el ExecutionAdapter no conoce roles ni scope (seccion 38.5)",
        "roles.yaml" not in adapter_src and "write_paths" not in adapter_src
        and "current-role" not in adapter_src))

    # ---------- el ejecutor no fuerza ----------

    # Sin evidencia, el ejecutor no avanza aunque se lo pida directo.
    proj3 = project()
    code, out = talos(proj3, "gate", "feature", "FEATURE_READY",
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
