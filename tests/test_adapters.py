"""Auditoria del registro de capacidades y de los adapters de referencia.

Cubre los pasos 4 y 5 de la ruta de implementacion (talos-0.0.7.md seccion 51):
el registry y el DryRunAdapter.

Verifica RECHAZO, no solo aceptacion: un registry que acepta cero
implementaciones de una capacidad requerida, o un adapter mutante sin
idempotencia, tienen que fallar. Si solo se prueba el camino feliz, la barrera
no esta probada.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

import yaml
from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
ADAPTERS = ROOT / "adapters"

# Clasificacion normativa de la seccion 37.4.2. Duplicada aca a proposito:
# si tools/build-registry.py la cambia sin que cambie la spec, este test falla.
REQUIRED = {
    "FileSystemAdapter",
    "ModelProviderAdapter",
    "ExecutionAdapter",
    "CoordinationAdapter",
    "CIAdapter",
}

# Operaciones que cada capacidad debe exponer, seccion 38.4.
EXPECTED_OPS = {
    "FileSystemAdapter": {"read_file", "write_file", "list_dir", "ensure_dir", "validate_path"},
    "ModelProviderAdapter": {"list_models", "resolve_profile", "invoke_model", "estimate_cost", "report_usage"},
    # close_session es parte del ciclo de vida (seccion 38.5): un adapter que
    # abre sesiones y no las cierra deja paneles muertos para siempre.
    "ExecutionAdapter": {"create_workspace", "create_session", "start_agent", "prompt_agent",
                         "wait_agent", "read_agent", "run_command", "close_session",
                         "report_metadata"},
    "CoordinationAdapter": {"create_issue", "create_branch", "open_pr", "get_pr_checks",
                            "request_review", "merge_pr"},
    "CIAdapter": {"run_checks", "get_check_status", "publish_report"},
}

# Las marcadas [M] en la seccion 38.4 del CoordinationAdapter.
COORD_MUTATING = {"create_issue", "create_branch", "open_pr", "request_review", "merge_pr"}


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def validate(schema_name, doc):
    schema = json.loads((SCHEMAS / f"{schema_name}.schema.json").read_text())
    return list(Draft202012Validator(schema).iter_errors(doc))


def manifests():
    out = {}
    for path in sorted(ADAPTERS.glob("*/adapter.yaml")):
        out[path.parent.name] = yaml.safe_load(path.read_text())
    return out


def run_adapter(directory, op, args=None, env=None, project_root=None):
    cmd = [str(ADAPTERS / directory / "run.sh"), op]
    if args is not None:
        cmd.append(json.dumps(args))
    e = dict(os.environ)
    e["TALOS_PROJECT_ROOT"] = project_root or tempfile.mkdtemp()
    e.setdefault("TALOS_RUN_ID", "r-test-0001")
    e.setdefault("TALOS_FEATURE_ID", "F001")
    if env:
        e.update(env)
    return subprocess.run(cmd, capture_output=True, text=True, env=e)


def build_registry(workdir):
    """Corre tools/build-registry.py sobre una copia del repo. Devuelve (rc, stderr)."""
    proc = subprocess.run(
        [sys.executable, str(workdir / "tools" / "build-registry.py")],
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stderr


def sandbox():
    """Copia minima del repo para probar mutaciones del registry sin tocarlo."""
    tmp = pathlib.Path(tempfile.mkdtemp())
    for item in ("config", "adapters", "tools", "schemas"):
        shutil.copytree(ROOT / item, tmp / item)
    (tmp / "hooks" / "generated").mkdir(parents=True)
    return tmp


def main():
    results = []
    mans = manifests()

    # ---------- configuracion ----------

    sys_cfg = yaml.safe_load((ROOT / "config" / "system.yaml").read_text())
    results.append(check(
        "config/system.yaml valida contra system-config.schema.json",
        not validate("system-config", sys_cfg),
        "; ".join(e.message[:90] for e in validate("system-config", sys_cfg)[:3]),
    ))

    reg = yaml.safe_load((ROOT / "config" / "extensions.yaml").read_text())
    results.append(check(
        "config/extensions.yaml valida contra extension-registry.schema.json",
        not validate("extension-registry", reg),
        "; ".join(e.message[:90] for e in validate("extension-registry", reg)[:3]),
    ))

    # Regla 31.7: auto_merge deshabilitado por defecto en 0.0.6.
    results.append(check(
        "auto_merge esta deshabilitado (regla 31.7)",
        sys_cfg.get("auto_merge") is False,
        f"auto_merge={sys_cfg.get('auto_merge')}",
    ))

    # Recomendacion 32.4.3 para el piloto serial.
    results.append(check(
        "concurrencia serial con max_parallel_features=1 (recomendacion 32.4.3)",
        sys_cfg["concurrency"]["mode"] == "serial"
        and sys_cfg["concurrency"]["max_parallel_features"] == 1,
        str(sys_cfg["concurrency"]),
    ))

    # ---------- manifiestos ----------

    for name, man in mans.items():
        errors = validate("adapter-manifest", man)
        results.append(check(
            f"adapters/{name}/adapter.yaml valida contra adapter-manifest.schema.json",
            not errors,
            "; ".join(e.message[:90] for e in errors[:3]),
        ))

    # Regla 38.1.5: todo adapter debe soportar dry-run.
    sin_dryrun = [n for n, m in mans.items() if not m.get("supports_dry_run")]
    results.append(check(
        "todo adapter soporta dry-run (regla 38.1.5)",
        not sin_dryrun,
        f"sin soporte: {sin_dryrun}",
    ))

    # Regla 38.2.1: toda operacion mutante acepta idempotency_key.
    sin_idem = []
    for name, man in mans.items():
        for op in man["operations"]:
            if op["mutating"] and not op.get("idempotency"):
                sin_idem.append(f"{name}:{op['name']}")
    results.append(check(
        "toda operacion mutante declara idempotencia (regla 38.2.1)",
        not sin_idem,
        f"sin declarar: {sin_idem}",
    ))

    # Regla 38.2.7: at_most_once implica que el nucleo no reintenta solo.
    mal_reintento = []
    for name, man in mans.items():
        for op in man["operations"]:
            if op.get("idempotency") == "at_most_once" and op.get("max_attempts", 1) > 1:
                mal_reintento.append(f"{name}:{op['name']}")
    results.append(check(
        "ninguna operacion at_most_once se reintenta automaticamente (regla 38.2.7)",
        not mal_reintento,
        f"con max_attempts>1: {mal_reintento}",
    ))

    # Seccion 38.4: cada capacidad expone las operaciones que la spec le exige.
    by_cap = {m["implements"]: m for m in mans.values()}
    for cap, expected in EXPECTED_OPS.items():
        man = by_cap.get(cap)
        if man is None:
            results.append(check(f"{cap} tiene un manifiesto", False))
            continue
        actual = {o["name"] for o in man["operations"]}
        results.append(check(
            f"{cap} expone las operaciones de la seccion 38.4",
            actual == expected,
            f"faltan {sorted(expected - actual)}, sobran {sorted(actual - expected)}",
        ))

    # Las [M] del CoordinationAdapter son mutantes.
    coord = by_cap.get("CoordinationAdapter", {"operations": []})
    marcadas = {o["name"] for o in coord["operations"] if o["mutating"]}
    results.append(check(
        "las operaciones [M] de CoordinationAdapter son mutantes (seccion 38.4)",
        marcadas == COORD_MUTATING,
        f"mutantes declaradas: {sorted(marcadas)}",
    ))

    # ---------- ligaduras ----------

    caps = reg["capabilities"]
    faltantes = [c for c in REQUIRED
                 if not isinstance(caps.get(c), dict) or not caps[c].get("implementation")]
    results.append(check(
        "toda capacidad REQUERIDA tiene exactamente una implementacion (regla 37.4.3.1)",
        not faltantes,
        f"sin ligar: {faltantes}",
    ))

    declarados = {m["id"] for m in mans.values()}
    ligados = {caps[c]["implementation"] for c in REQUIRED if isinstance(caps.get(c), dict)}
    results.append(check(
        "toda implementacion ligada existe bajo adapters/",
        ligados <= declarados,
        f"ligadas sin manifiesto: {sorted(ligados - declarados)}",
    ))

    # Regla 37.4.3.4: cero implementaciones de una opcional es valido.
    opcionales_nulas = [c for c, v in caps.items() if c not in REQUIRED and v is None]
    results.append(check(
        "las capacidades OPCIONALES pueden quedar sin ligar (regla 37.4.3.4)",
        len(opcionales_nulas) > 0,
        "ninguna opcional sin ligar: el nucleo no demuestra correr sin extensiones",
    ))

    # Regla 37.4.3.5: el nucleo no nombra implementaciones concretas.
    filtrados = []
    for d in ("cli", "hooks", "system"):
        for path in (ROOT / d).rglob("*"):
            if not path.is_file() or "generated" in path.parts:
                continue
            try:
                if "talos.adapter." in path.read_text():
                    filtrados.append(str(path.relative_to(ROOT)))
            except (UnicodeDecodeError, PermissionError):
                continue
    results.append(check(
        "ningun id de adapter concreto aparece en el nucleo (regla 37.4.3.5)",
        not filtrados,
        f"cableado en: {filtrados}",
    ))

    # ---------- rechazo del registry ----------

    box = sandbox()
    rc, _ = build_registry(box)
    results.append(check(
        "el registry valido compila",
        rc == 0,
    ))

    # Deriva: la tabla versionada tiene que coincidir con sus fuentes. Una
    # tabla desactualizada hace que el nucleo resuelva una ligadura que el
    # registry ya no declara.
    generada = (box / "hooks" / "generated" / "capabilities.tsv")
    comprometida = ROOT / "hooks" / "generated" / "capabilities.tsv"
    results.append(check(
        "hooks/generated/capabilities.tsv coincide con config/extensions.yaml",
        generada.exists() and comprometida.exists()
        and generada.read_text() == comprometida.read_text(),
        "corre python3 tools/build-registry.py y commiteá el resultado",
    ))

    # Cero implementaciones de una capacidad REQUERIDA debe fallar (regla 37.4.3.2).
    box2 = sandbox()
    cfg2 = yaml.safe_load((box2 / "config" / "extensions.yaml").read_text())
    cfg2["capabilities"]["ExecutionAdapter"] = None
    (box2 / "config" / "extensions.yaml").write_text(yaml.safe_dump(cfg2))
    rc2, err2 = build_registry(box2)
    results.append(check(
        "RECHAZA cero implementaciones de una capacidad REQUERIDA (regla 37.4.3.2)",
        rc2 != 0 and "ExecutionAdapter" in err2,
        f"rc={rc2} stderr={err2.strip()[:120]}",
    ))

    # Una implementacion inexistente debe fallar.
    box3 = sandbox()
    cfg3 = yaml.safe_load((box3 / "config" / "extensions.yaml").read_text())
    cfg3["capabilities"]["CIAdapter"] = {"implementation": "talos.adapter.no_existe"}
    (box3 / "config" / "extensions.yaml").write_text(yaml.safe_dump(cfg3))
    rc3, err3 = build_registry(box3)
    results.append(check(
        "RECHAZA una implementacion que no existe bajo adapters/",
        rc3 != 0 and "no_existe" in err3,
        f"rc={rc3} stderr={err3.strip()[:120]}",
    ))

    # Dos manifiestos con el mismo id: ambiguedad (regla 37.4.3.3).
    box4 = sandbox()
    dup = box4 / "adapters" / "ci_clone"
    shutil.copytree(box4 / "adapters" / "ci_dryrun", dup)
    rc4, err4 = build_registry(box4)
    results.append(check(
        "RECHAZA dos manifiestos que declaran el mismo id (regla 37.4.3.3)",
        rc4 != 0 and "duplicado" in err4.lower(),
        f"rc={rc4} stderr={err4.strip()[:120]}",
    ))

    # El schema tambien rechaza un binding sin implementation.
    errors = validate("extension-registry", {
        "version": 1,
        "capabilities": {
            "FileSystemAdapter": {}, "ModelProviderAdapter": {"implementation": "talos.adapter.a"},
            "ExecutionAdapter": {"implementation": "talos.adapter.b"},
            "CoordinationAdapter": {"implementation": "talos.adapter.c"},
            "CIAdapter": {"implementation": "talos.adapter.d"},
        },
    })
    results.append(check(
        "el schema RECHAZA un binding requerido sin campo implementation",
        bool(errors),
    ))

    # Un id que no respeta el namespace tambien se rechaza.
    errors = validate("extension-registry", {
        "version": 1,
        "capabilities": {
            "FileSystemAdapter": {"implementation": "mi-adapter"},
            "ModelProviderAdapter": {"implementation": "talos.adapter.a"},
            "ExecutionAdapter": {"implementation": "talos.adapter.b"},
            "CoordinationAdapter": {"implementation": "talos.adapter.c"},
            "CIAdapter": {"implementation": "talos.adapter.d"},
        },
    })
    results.append(check(
        "el schema RECHAZA un id fuera del namespace talos.adapter.*",
        bool(errors),
    ))

    # doctor tiene que detectar que su tabla ya no coincide con su registry.
    # Una proyeccion desincronizada hace que Talos resuelva contra una ligadura
    # que su propia configuracion ya no declara, y en silencio: reporta las
    # capacidades sanas leyendo la tabla vieja. Es la clase de deriva que Talos
    # existe para detectar, aplicada al propio sistema.
    doc = (ROOT / "cli" / "commands" / "doctor.sh").read_text()
    results.append(check(
        "doctor verifica que la tabla de capacidades no derive del registry",
        "registro_al_dia" in doc and "build-registry.py" in doc))
    results.append(check(
        "y si no puede verificarlo lo dice, en vez de saltearse en silencio",
        "no se pudo verificar la deriva" in doc,
        "un check que puede no correr sin avisar hace asumir que paso"))

    # ---------- comportamiento en ejecucion ----------

    # Regla 37.4.4.1: dry-run-only corre sin ninguna herramienta externa
    # instalada. Eso aplica a los adapters que NO dependen de un binario: uno
    # que declara external_binary DEBE negarse cuando ese binario falta, y su
    # propia suite lo cubre con un binario de mentira.
    #
    # Correrle el health a todos escondia el problema en una maquina que si
    # tenia el binario y lo destapaba solo en CI.
    autonomos = [n for n, m in mans.items() if not m.get("external_binary")]
    con_binario = [n for n, m in mans.items() if m.get("external_binary")]

    sanos = []
    for name in autonomos:
        proc = run_adapter(name, "health")
        sanos.append((name, proc.returncode == 0 and '"healthy":true' in proc.stdout))
    results.append(check(
        f"los {len(autonomos)} adapters sin binario externo responden al health "
        f"check (regla 37.4.4.1)",
        autonomos and all(ok for _, ok in sanos),
        f"fallan: {[n for n, ok in sanos if not ok]}",
    ))

    results.append(check(
        "todo adapter con binario externo lo declara con rango y env_override",
        all((mans[n]["external_binary"] or {}).get("version_range")
            and (mans[n]["external_binary"] or {}).get("env_override")
            for n in con_binario),
        f"{ {n: mans[n].get('external_binary') for n in con_binario} }",
    ))

    # Toda salida es JSON parseable (regla 38.1.3).
    no_json = []
    for name in autonomos:
        proc = run_adapter(name, "health")
        try:
            json.loads(proc.stdout)
        except json.JSONDecodeError:
            no_json.append(name)
    results.append(check(
        "todo adapter autonomo devuelve resultado estructurado (regla 38.1.3)",
        not no_json,
        f"salida no parseable: {no_json}",
    ))

    # Idempotencia: misma entrada -> misma key (formula 38.2.4).
    work = tempfile.mkdtemp()
    a = run_adapter("coord_dryrun", "create_issue", {"title": "x", "body": "y"}, project_root=work)
    ra = json.loads(a.stdout)
    work2 = tempfile.mkdtemp()
    b = run_adapter("coord_dryrun", "create_issue", {"body": "y", "title": "x"}, project_root=work2)
    rb = json.loads(b.stdout)
    results.append(check(
        "la idempotency_key es determinista y no depende del orden de las claves (38.2.4)",
        ra["idempotency_key"] == rb["idempotency_key"],
        f"{ra['idempotency_key'][:16]} != {rb['idempotency_key'][:16]}",
    ))

    # Entrada distinta -> key distinta.
    work3 = tempfile.mkdtemp()
    c = run_adapter("coord_dryrun", "create_issue", {"title": "otro", "body": "y"}, project_root=work3)
    rc_ = json.loads(c.stdout)
    results.append(check(
        "argumentos semanticos distintos producen keys distintas",
        rc_["idempotency_key"] != ra["idempotency_key"],
    ))

    # Reintento con la misma key -> already_exists, no un duplicado (38.2.3).
    retry = run_adapter("coord_dryrun", "create_issue", {"title": "x", "body": "y"}, project_root=work)
    rr = json.loads(retry.stdout)
    results.append(check(
        "reintentar una operacion mutante devuelve already_exists (regla 38.2.3)",
        ra["status"] == "created" and rr["status"] == "already_exists"
        and rr["idempotency_key"] == ra["idempotency_key"],
        f"primera={ra['status']} reintento={rr['status']}",
    ))

    # La forma de retorno mutante es la exacta de 38.2.3.
    results.append(check(
        "la respuesta mutante trae status, resource_ref e idempotency_key (38.2.3)",
        {"status", "resource_ref", "idempotency_key"} <= set(ra),
        f"campos: {sorted(ra)}",
    ))

    # Una operacion desconocida se rechaza con error de adapter (exit 5).
    bad = run_adapter("ci_dryrun", "operacion_inventada")
    results.append(check(
        "RECHAZA una operacion que el adapter no declara (exit 5)",
        bad.returncode == 5,
        f"exit={bad.returncode}",
    ))

    # Regla 37.4.4.2: dry-run-only no produce evidencia verificable.
    status = run_adapter("ci_dryrun", "get_check_status")
    results.append(check(
        "el CheckRunSet en dry-run no es evidencia verificable (regla 37.4.4.2)",
        '"verifiable":false' in status.stdout,
        status.stdout.strip()[:120],
    ))

    print()
    ok = sum(1 for r in results if r)
    print(f"{ok}/{len(results)} checks de capacidades y adapters")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
