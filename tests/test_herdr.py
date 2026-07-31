"""Auditoria del adapter de Herdr y de la resolucion de binarios externos.

Paso 9 de la ruta de implementacion (seccion 51): la implementacion productiva
de ExecutionAdapter.

Ninguno de estos checks necesita Herdr instalado. Esa es la propiedad que se
verifica: el modo dry-run-only tiene que correr sin ninguna herramienta externa
(regla 37.4.4.1), asi que la suite del propio Talos no puede depender de ella.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

import yaml
from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
ADAPTER = ROOT / "adapters" / "herdr"


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def fake_herdr(version, works=True, tally=None):
    """Un herdr de mentira: la suite no puede depender del real.

    Con tally, cada `workspace create` deja una marca en ese archivo. Es lo
    que permite contar efectos reales en vez de creerle a la respuesta.
    """
    d = pathlib.Path(tempfile.mkdtemp())
    p = d / "herdr"
    body = f'#!/bin/sh\ncase "$1 $2" in\n'
    if tally:
        body += f'  "workspace create") echo x >> {tally}; echo \'{{"workspace_id":"w1"}}\' ; exit 0 ;;\n'
    body += 'esac\ncase "$1" in\n'
    body += f'  --version) echo "herdr {version}" ;;\n'
    body += '  workspace) exit 0 ;;\n' if works else '  workspace) exit 1 ;;\n'
    body += '  *) echo "{}" ;;\nesac\n'
    p.write_text(body)
    p.chmod(0o755)
    return p


def run_adapter(op, args=None, env=None):
    e = {"PATH": "/usr/bin:/bin", "HOME": str(pathlib.Path.home()),
         "TALOS_PROJECT_ROOT": tempfile.mkdtemp()}
    if env:
        e.update(env)
    cmd = [str(ADAPTER / "run.sh"), op]
    if args is not None:
        cmd.append(json.dumps(args))
    p = subprocess.run(cmd, capture_output=True, text=True, env=e)
    return p.returncode, p.stdout, p.stderr


def sh_semver(a, b):
    """Ejercita talos_semver_ge tal como lo usa el adapter."""
    script = (f'. "{ROOT}/adapters/lib/semver.sh"\n'
              f'talos_semver_ge "{a}" "{b}"\n')
    return subprocess.run(["sh", "-c", script], capture_output=True).returncode


def main():
    results = []

    # ---------- manifiesto ----------

    man = yaml.safe_load((ADAPTER / "adapter.yaml").read_text())
    errors = list(Draft202012Validator(
        json.loads((SCHEMAS / "adapter-manifest.schema.json").read_text())
    ).iter_errors(man))
    results.append(check("adapters/herdr/adapter.yaml valida contra su schema",
                         not errors,
                         "; ".join(e.message[:80] for e in errors[:3])))

    results.append(check(
        "declara el id y la capacidad de la seccion 38.5",
        man["id"] == "talos.adapter.herdr"
        and man["implements"] == "ExecutionAdapter",
        f"{man['id']} / {man['implements']}"))

    ext = man.get("external_binary") or {}
    results.append(check(
        "declara herdr >= 0.7.0 con su env_override (seccion 38.5)",
        ext.get("name") == "herdr" and ext.get("version_range") == ">=0.7.0"
        and ext.get("env_override") == "TALOS_HERDR_BIN",
        f"{ext}"))

    results.append(check(
        "marca machine_level: Herdr no se vendorea por proyecto (seccion 38.5)",
        ext.get("machine_level") is True))

    results.append(check(
        "da el comando exacto de instalacion (regla 37.4.5.5)",
        bool(ext.get("install_hint"))))

    # Mismas operaciones que el adapter dry-run: son la misma capacidad.
    dry = yaml.safe_load(
        (ROOT / "adapters" / "exec_dryrun" / "adapter.yaml").read_text())
    ops_h = {o["name"] for o in man["operations"]}
    ops_d = {o["name"] for o in dry["operations"]}
    results.append(check(
        "expone exactamente las operaciones de ExecutionAdapter (38.4)",
        ops_h == ops_d, f"solo en herdr: {ops_h - ops_d}, solo en dryrun: {ops_d - ops_h}"))

    # La clasificacion de idempotencia no puede cambiar entre implementaciones
    # de la misma capacidad: es parte del contrato, no de quien lo cumple.
    idem_h = {o["name"]: o.get("idempotency") for o in man["operations"]}
    idem_d = {o["name"]: o.get("idempotency") for o in dry["operations"]}
    results.append(check(
        "la idempotencia por operacion coincide con la del contrato",
        idem_h == idem_d,
        f"{ {k: (idem_h[k], idem_d[k]) for k in idem_h if idem_h[k] != idem_d.get(k)} }"))

    # ---------- comparacion de versiones ----------

    results.append(check("0.7.5 >= 0.7.0", sh_semver("0.7.5", "0.7.0") == 0))
    results.append(check("0.7.0 >= 0.7.0 (igual pasa)",
                         sh_semver("0.7.0", "0.7.0") == 0))
    results.append(check("0.6.9 NO >= 0.7.0", sh_semver("0.6.9", "0.7.0") == 1))
    # El caso que rompe una comparacion hecha como texto.
    results.append(check("0.10.0 >= 0.9.0 (no se compara como texto)",
                         sh_semver("0.10.0", "0.9.0") == 0))
    results.append(check("1.0.0 >= 0.99.99", sh_semver("1.0.0", "0.99.99") == 0))
    results.append(check("una version no numerica no se adivina",
                         sh_semver("abc", "0.7.0") == 2))

    # ---------- resolucion del binario (seccion 37.4.5) ----------

    bien = fake_herdr("0.7.5")
    code, out, err = run_adapter("health", env={"TALOS_HERDR_BIN": str(bien)})
    results.append(check(
        "resuelve el binario por TALOS_HERDR_BIN, primer paso de la cascada",
        code == 0 and str(bien) in out, f"exit={code} {out[:120]}{err[:120]}"))

    results.append(check(
        "un adapter productivo NO reporta dry_run:true",
        '"dry_run":false' in out, out[:160]))

    # Regla 37.4.5.3: version fuera de rango falla en PRECONDITION_GATE.
    viejo = fake_herdr("0.6.9")
    code, out, err = run_adapter("health", env={"TALOS_HERDR_BIN": str(viejo)})
    results.append(check(
        "RECHAZA una version fuera del rango declarado (regla 37.4.5.3)",
        code == 2 and "0.6.9" in err and "0.7.0" in err,
        f"exit={code} {err[:140]}"))

    # Sin binario en ningun paso: precondition, no crash.
    code, out, err = run_adapter("health")
    results.append(check(
        "sin binario en ningun paso de la cascada sale 2, no rompe",
        code == 2 and "no esta instalado" in err, f"exit={code} {err[:120]}"))

    results.append(check(
        "el error nombra los tres pasos de la cascada (seccion 37.4.5)",
        "TALOS_HERDR_BIN" in err and ".talos/bin/herdr" in err and "PATH" in err,
        err[:200]))

    results.append(check(
        "el error da el comando de instalacion y NO instala nada (37.4.5.4)",
        "install_hint" in err, err[:160]))

    # Binario presente y version buena, pero sin servidor: no esta sano.
    # Tener el binario no alcanza; sin servidor no hay donde ejecutar.
    muerto = fake_herdr("0.7.5", works=False)
    code, out, err = run_adapter("health", env={"TALOS_HERDR_BIN": str(muerto)})
    results.append(check(
        "RECHAZA cuando el binario esta pero no hay servidor",
        code == 2 and "servidor" in err, f"exit={code} {err[:140]}"))

    # Con TALOS_DRY_RUN el adapter no toca el servidor.
    code, out, err = run_adapter(
        "report_metadata", env={"TALOS_HERDR_BIN": str(muerto), "TALOS_DRY_RUN": "1"})
    results.append(check(
        "en dry-run no exige servidor y lo declara (regla 38.1.5)",
        code == 0 and '"dry_run":true' in out, f"exit={code} {out[:140]}"))

    # ---------- idempotencia con efecto real ----------
    #
    # Este es el caso que los adapters de simulacion NO pueden cubrir: ellos
    # no ejecutan nada, asi que su resource_ref es una constante y el reintento
    # "funciona" sin probar nada.
    #
    # Pasar "$(comando)" como argumento a talos_mutate evalua la sustitucion
    # ANTES de entrar a la funcion: el efecto ocurre siempre y la consulta al
    # ledger llega tarde. La respuesta decia already_exists y el recurso se
    # duplicaba igual, que es justo lo que corrige la seccion 38.2.
    tally = pathlib.Path(tempfile.mkdtemp()) / "invocaciones"
    contador = fake_herdr("0.7.5", tally=str(tally))
    proyecto = tempfile.mkdtemp()   # ledger compartido entre las llamadas
    env = {"TALOS_HERDR_BIN": str(contador), "TALOS_PROJECT_ROOT": proyecto,
           "TALOS_RUN_ID": "r-1", "TALOS_FEATURE_ID": "F001"}

    r1 = run_adapter("create_workspace", {"label": "x"}, env=env)
    r2 = run_adapter("create_workspace", {"label": "x"}, env=env)
    r3 = run_adapter("create_workspace", {"label": "x"}, env=env)

    veces = len(tally.read_text().split()) if tally.exists() else 0
    results.append(check(
        "tres llamadas iguales ejecutan el efecto UNA sola vez (seccion 38.2)",
        veces == 1, f"el backend se invoco {veces} veces"))

    results.append(check(
        "la primera dice created y las siguientes already_exists",
        '"status":"created"' in r1[1]
        and '"status":"already_exists"' in r2[1]
        and '"status":"already_exists"' in r3[1],
        f"{r1[1][:60]} | {r2[1][:60]}"))

    results.append(check(
        "una mutacion real NO se reporta como dry_run",
        '"dry_run":false' in r1[1], r1[1][:120]))

    # Argumentos distintos si tienen que ejecutar de nuevo.
    run_adapter("create_workspace", {"label": "otro"}, env=env)
    veces2 = len(tally.read_text().split())
    results.append(check(
        "argumentos distintos si ejecutan el efecto de nuevo",
        veces2 == 2, f"invocaciones: {veces2}"))

    # Ninguna operacion mutante puede quedar con la forma vieja.
    fuente = (ADAPTER / "run.sh").read_text()
    results.append(check(
        "ninguna mutante usa la forma que evalua el efecto por adelantado",
        "talos_mutate " not in fuente and "talos_mutate_run" in fuente,
        "queda una llamada a talos_mutate con el resultado ya calculado"))

    # ---------- el nucleo sigue sin nombrar a Herdr ----------

    # Regla 38.5.5: el nucleo NO DEBE nombrar a Herdr fuera del registry y la
    # configuracion. Es la propiedad que justifico hacer el paso 4 primero.
    # El alcance es la superficie ejecutable y de configuracion. La regla
    # prohibe que el nucleo DEPENDA de una implementacion concreta; la
    # documentacion que la usa como ejemplo no acopla nada, y explicar el
    # principio exige poder nombrar un caso.
    CODIGO = {".sh", ".py", ".yaml", ".yml", ".json", ""}
    filtrados = []
    for d in ("cli", "hooks", "system"):
        for path in (ROOT / d).rglob("*"):
            if not path.is_file() or "generated" in path.parts:
                continue
            if path.suffix not in CODIGO:
                continue
            try:
                texto = path.read_text()
            except (UnicodeDecodeError, PermissionError):
                continue
            if re.search(r"\bherdr\b", texto, re.I):
                filtrados.append(str(path.relative_to(ROOT)))
    results.append(check(
        "el nucleo no nombra a Herdr fuera del registry (regla 38.5.5)",
        not filtrados, f"lo nombran: {filtrados}"))

    # ---------- el repo sigue en dry-run-only ----------

    sys_cfg = yaml.safe_load((ROOT / "config" / "system.yaml").read_text())
    results.append(check(
        "el repo queda en dry-run-only: su suite no puede depender de Herdr",
        sys_cfg["execution_mode"] == "dry-run-only",
        sys_cfg["execution_mode"]))

    reg = yaml.safe_load((ROOT / "config" / "extensions.yaml").read_text())
    results.append(check(
        "ExecutionAdapter sigue ligado a la implementacion de simulacion",
        reg["capabilities"]["ExecutionAdapter"]["implementation"]
        == "talos.adapter.exec_dryrun",
        reg["capabilities"]["ExecutionAdapter"]["implementation"]))

    # Cambiar de implementacion NO puede exigir tocar el nucleo (regla 37.4.3.6).
    box = pathlib.Path(tempfile.mkdtemp())
    for sub in ("config", "adapters", "tools", "schemas"):
        subprocess.run(["cp", "-R", str(ROOT / sub), str(box / sub)], check=True)
    (box / "hooks" / "generated").mkdir(parents=True)
    cfg = yaml.safe_load((box / "config" / "extensions.yaml").read_text())
    cfg["capabilities"]["ExecutionAdapter"] = {"implementation": "talos.adapter.herdr"}
    (box / "config" / "extensions.yaml").write_text(yaml.safe_dump(cfg))
    p = subprocess.run([sys.executable, str(box / "tools" / "build-registry.py")],
                       capture_output=True, text=True)
    tabla = (box / "hooks" / "generated" / "capabilities.tsv")
    results.append(check(
        "ligar ExecutionAdapter a herdr compila sin tocar el nucleo (37.4.3.6)",
        p.returncode == 0 and "talos.adapter.herdr" in tabla.read_text(),
        f"rc={p.returncode} {p.stderr[:140]}"))

    results.append(check(
        "la tabla lleva el binario y su rango para que doctor los reporte (37.4.5.6)",
        "herdr\t>=0.7.0\tTALOS_HERDR_BIN" in tabla.read_text(),
        [l for l in tabla.read_text().splitlines() if "herdr" in l][:1]))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks del adapter de Herdr")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
