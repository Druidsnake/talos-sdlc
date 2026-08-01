"""Auditoria del adapter de GitHub: CoordinationAdapter productivo.

Paso 11 de la ruta de implementacion (seccion 51).

Ningun check necesita gh instalado ni toca un repositorio real. Se usa un gh de
mentira con estado en disco, que imita lo que GitHub hace y lo que NO hace:
acepta crear dos issues identicos, porque GitHub no conoce claves de
idempotencia. Eso es lo que obliga al adapter a reconciliar (regla 38.2.6).
"""
import json
import pathlib
import subprocess
import sys
import tempfile

import yaml
from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
ADAPTER = ROOT / "adapters" / "github"


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def fake_gh(store, version="2.90.0", authed=True, repo="acme/demo"):
    """gh de mentira con estado.

    Guarda los issues creados en un archivo y los devuelve en `issue list`.
    NO deduplica: crear dos veces el mismo titulo produce dos issues, igual
    que GitHub. Si el adapter no reconcilia, el test lo ve.

    MODELA EL RETRASO DEL INDICE: con --search NO devuelve nada, porque el
    indice de busqueda de GitHub no es inmediatamente consistente. Un adapter
    que reconcilie por --search pasa contra un doble amable y duplica issues
    contra el remoto real; eso paso, y este doble existe para que no vuelva a
    pasar.
    """
    d = pathlib.Path(tempfile.mkdtemp())
    p = d / "gh"
    p.write_text(f"""#!/bin/sh
STORE={store}
case "$1" in
  --version) echo "gh version {version} (2026-01-01)" ; exit 0 ;;
  auth) exit {0 if authed else 1} ;;
  repo) echo '{repo}' ; exit 0 ;;
esac
if [ "$1" = issue ] && [ "$2" = list ]; then
  usa_search=0
  shift 2
  while [ $# -gt 0 ]; do
    [ "$1" = "--search" ] && usa_search=1
    shift
  done
  # El indice de busqueda no ve lo recien creado.
  [ "$usa_search" = 1 ] && {{ echo '[]' ; exit 0 ; }}
  [ -f "$STORE" ] || {{ echo '[]' ; exit 0 ; }}
  printf '['
  sep=""
  while read -r n k; do
    [ -z "$n" ] && continue
    printf '%s{{"number":%s,"body":"<!-- talos-idempotency-key: %s -->"}}' "$sep" "$n" "$k"
    sep=","
  done < "$STORE"
  printf ']\\n'
  exit 0
fi
if [ "$1" = issue ] && [ "$2" = create ]; then
  body=""
  shift 2
  while [ $# -gt 0 ]; do
    [ "$1" = "--body" ] && body="$2"
    shift
  done
  n=$(( $(wc -l < "$STORE" 2>/dev/null || echo 0) + 1 ))
  key=$(printf '%s' "$body" | sed -n 's/.*talos-idempotency-key: \\([a-f0-9]*\\).*/\\1/p')
  printf '%s %s\\n' "$n" "$key" >> "$STORE"
  echo "https://github.com/{repo}/issues/$n"
  exit 0
fi
if [ "$1" = issue ] && [ "$2" = view ]; then
  echo "https://github.com/{repo}/issues/$3"
  exit 0
fi
echo '{{}}'
""")
    p.chmod(0o755)
    return p


def run_adapter(op, args=None, env=None):
    e = {"PATH": "/usr/bin:/bin", "HOME": str(pathlib.Path.home()),
         "TALOS_PROJECT_ROOT": tempfile.mkdtemp(),
         "TALOS_RUN_ID": "r-1", "TALOS_FEATURE_ID": "F001"}
    if env:
        e.update(env)
    cmd = [str(ADAPTER / "run.sh"), op]
    if args is not None:
        cmd.append(json.dumps(args))
    p = subprocess.run(cmd, capture_output=True, text=True, env=e)
    return p.returncode, p.stdout, p.stderr


def main():
    results = []

    # ---------- manifiesto ----------

    man = yaml.safe_load((ADAPTER / "adapter.yaml").read_text())
    errors = list(Draft202012Validator(
        json.loads((SCHEMAS / "adapter-manifest.schema.json").read_text())
    ).iter_errors(man))
    results.append(check("adapters/github/adapter.yaml valida contra su schema",
                         not errors, "; ".join(e.message[:80] for e in errors[:3])))

    results.append(check(
        "implementa CoordinationAdapter con el id de la seccion 38.3",
        man["id"] == "talos.adapter.github" and man["implements"] == "CoordinationAdapter"))

    dry = yaml.safe_load((ROOT / "adapters" / "coord_dryrun" / "adapter.yaml").read_text())
    ops_g = {o["name"] for o in man["operations"]}
    ops_d = {o["name"] for o in dry["operations"]}
    results.append(check(
        "expone exactamente las operaciones de CoordinationAdapter (38.4)",
        ops_g == ops_d, f"difieren: {ops_g ^ ops_d}"))

    idem_g = {o["name"]: o.get("idempotency") for o in man["operations"]}
    idem_d = {o["name"]: o.get("idempotency") for o in dry["operations"]}
    results.append(check(
        "la idempotencia por operacion coincide con la del contrato",
        idem_g == idem_d,
        f"{ {k: (idem_g[k], idem_d.get(k)) for k in idem_g if idem_g[k] != idem_d.get(k)} }"))

    # merge_pr no se reintenta solo: repetir un merge no es inofensivo.
    merge = [o for o in man["operations"] if o["name"] == "merge_pr"][0]
    results.append(check(
        "merge_pr no se reintenta automaticamente",
        merge.get("max_attempts") == 1, f"max_attempts={merge.get('max_attempts')}"))

    # ---------- preconditions ----------

    store = pathlib.Path(tempfile.mkdtemp()) / "issues"
    store.write_text("")
    gh = fake_gh(str(store))

    code, out, err = run_adapter("health", env={"TALOS_GH_BIN": str(gh)})
    results.append(check("health pasa con gh autenticado y repo resuelto",
                         code == 0 and '"healthy":true' in out, f"exit={code} {out[:120]}{err[:120]}"))
    results.append(check("un adapter productivo NO reporta dry_run:true",
                         '"dry_run":false' in out, out[:140]))

    viejo = fake_gh(str(store), version="1.14.0")
    code, out, err = run_adapter("health", env={"TALOS_GH_BIN": str(viejo)})
    results.append(check("RECHAZA una version de gh fuera de rango (37.4.5.3)",
                         code == 2 and "1.14.0" in err, f"exit={code} {err[:120]}"))

    sin_auth = fake_gh(str(store), authed=False)
    code, out, err = run_adapter("health", env={"TALOS_GH_BIN": str(sin_auth)})
    results.append(check("RECHAZA cuando gh no esta autenticado",
                         code == 2 and "autenticar" in err, f"exit={code} {err[:120]}"))

    code, out, err = run_adapter("health")
    results.append(check("sin gh en ningun paso de la cascada sale 2",
                         code == 2 and "no esta instalado" in err, f"exit={code}"))
    results.append(check("el error nombra los tres pasos de la cascada",
                         "TALOS_GH_BIN" in err and ".talos/bin/gh" in err and "PATH" in err))

    # ---------- reconciliacion (regla 38.2.6) ----------
    #
    # Lo que se prueba aca no es que el ledger local funcione, sino que el
    # adapter consulte el REMOTO antes de crear. GitHub no tiene claves de
    # idempotencia: si el adapter confia solo en su cache, un ledger perdido o
    # un segundo proceso producen issues duplicados.

    store2 = pathlib.Path(tempfile.mkdtemp()) / "issues"
    store2.write_text("")
    gh2 = fake_gh(str(store2))
    proj = tempfile.mkdtemp()
    env2 = {"TALOS_GH_BIN": str(gh2), "TALOS_PROJECT_ROOT": proj,
            "TALOS_RUN_ID": "r-1", "TALOS_FEATURE_ID": "F001"}

    c1, o1, _ = run_adapter("create_issue", {"title": "F001: modelo", "body": "x"}, env=env2)
    results.append(check("create_issue crea el issue la primera vez",
                         c1 == 0 and '"status":"created"' in o1, o1[:160]))

    c2, o2, _ = run_adapter("create_issue", {"title": "F001: modelo", "body": "x"}, env=env2)
    results.append(check("un reintento devuelve already_exists",
                         c2 == 0 and '"status":"already_exists"' in o2, o2[:160]))

    results.append(check(
        "el backend recibio UNA sola creacion",
        len([x for x in store2.read_text().splitlines() if x.strip()]) == 1,
        f"issues en el backend: {store2.read_text().strip()!r}"))

    # El caso que separa reconciliar de cachear: se borra el ledger local. Si
    # el adapter solo miraba su cache, aca crea un duplicado.
    ledger = pathlib.Path(proj) / "orchestration" / "dry-run" / "ledger.tsv"
    if ledger.exists():
        ledger.unlink()
    c3, o3, _ = run_adapter("create_issue", {"title": "F001: modelo", "body": "x"}, env=env2)
    results.append(check(
        "SIN ledger local sigue reconciliando contra el remoto (regla 38.2.6)",
        '"status":"already_exists"' in o3, o3[:160]))
    results.append(check(
        "y el backend sigue con UN solo issue",
        len([x for x in store2.read_text().splitlines() if x.strip()]) == 1,
        f"issues: {store2.read_text().strip()!r}"))

    # Argumentos distintos son otro recurso.
    run_adapter("create_issue", {"title": "F002: auth", "body": "y"}, env=env2)
    results.append(check(
        "argumentos semanticos distintos si crean un issue nuevo",
        len([x for x in store2.read_text().splitlines() if x.strip()]) == 2,
        f"issues: {store2.read_text().strip()!r}"))

    # La key incrustada es la que permite encontrarlo despues.
    # El doble devuelve vacio ante --search. Si el adapter volviera a usarlo,
    # todos los checks de reconciliacion de arriba fallarian.
    fuente = (ADAPTER / "run.sh").read_text()
    # Se mira la INVOCACION, no cualquier mencion: el comentario que explica
    # por que no usar --search tiene que poder nombrarlo.
    invoca_search = any(
        "--search" in l and not l.lstrip().startswith("#")
        for l in fuente.splitlines())
    results.append(check(
        "la reconciliacion NO depende del indice de busqueda de GitHub",
        not invoca_search,
        "el indice no es inmediatamente consistente: un reintento duplica"))

    results.append(check(
        "la idempotency key queda incrustada en el issue para poder buscarla",
        all(len(l.split()[1]) == 64 for l in store2.read_text().splitlines() if l.strip()),
        store2.read_text().strip()[:120]))

    # ---------- forma de retorno ----------

    r1 = json.loads(o1)
    results.append(check(
        "la respuesta mutante trae status, resource_ref e idempotency_key (38.2.3)",
        {"status", "resource_ref", "idempotency_key"} <= set(r1), f"{sorted(r1)}"))
    results.append(check(
        "resource_ref trae la url del issue creado",
        r1["resource_ref"].get("url", "").startswith("https://"), f"{r1['resource_ref']}"))
    results.append(check(
        "created y already_exists comparten la misma key",
        r1["idempotency_key"] == json.loads(o2)["idempotency_key"]))

    # ---------- el repo sigue sin ligarlo ----------

    reg = yaml.safe_load((ROOT / "config" / "extensions.yaml").read_text())
    results.append(check(
        "CoordinationAdapter sigue ligado a la simulacion en este repo",
        reg["capabilities"]["CoordinationAdapter"]["implementation"]
        == "talos.adapter.coord_dryrun",
        reg["capabilities"]["CoordinationAdapter"]["implementation"]))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks del adapter de GitHub")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
