#!/usr/bin/env python3
"""Redespachar tiene que ENTREGAR. Ver thalos-0.0.7.md 38.2.

EL DEFECTO

La idempotency key es sha256(run:feature:op:canonical(args)) y el encargo que
arma `feature work` es determinista para una feature+task dada. Un redespacho
producia la MISMA key, el ledger devolvia already_exists y el prompt NUNCA se
enviaba: el agente nuevo no recibia nada, jamas.

Medido en vivo contra herdr + opencode: mismo texto -> already_exists sin
enviar; texto distinto -> created. Antes del ACK observado esto se reportaba
como "ok trabajo entregado" y despues se esperaba el presupuesto entero por un
entregable que no podia aparecer.

QUE LO ARREGLA

La generacion del agente. Es un identificador de la INSTANCIA de despacho:
constante entre reintentos del mismo encargo -asi que la deduplicacion sigue
protegiendo lo que tiene que proteger- y distinto tras un redespacho.

No es un timestamp ni un valor no determinista, asi que no viola la regla
38.2.5. Es el mismo patron que la seccion 32.3 usa para los leases.
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def check(label, cond, detail=""):
    if cond:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def sh(script, proj):
    return subprocess.run(
        ["sh", "-c", f". {ROOT}/hooks/lib/agent-ref.sh\n{script}"],
        capture_output=True, text=True,
        env={**os.environ, "THALOS_PROJECT_ROOT": str(proj)})


def key(run, feat, op, args):
    """La formula exacta de la regla 38.2.4, para comparar claves."""
    p = subprocess.run(
        ["sh", "-c",
         f'. {ROOT}/adapters/lib/adapter.sh\n'
         f'thalos_idempotency_key "{run}" "{feat}" "{op}" \'{args}\''],
        capture_output=True, text=True)
    return p.stdout.strip()


def main():
    results = []
    proj = pathlib.Path(tempfile.mkdtemp())
    (proj / "orchestration" / "features" / "F001").mkdir(parents=True)

    # ---------- la generacion ----------

    sh("thalos_agent_ref_write F001 ad.herdr agente1 w1:p1 ref1", proj)
    g1 = sh("thalos_agent_ref_field F001 generation", proj).stdout.strip()
    results.append(check(
        "el primer despacho deja una generacion",
        g1.isdigit() and int(g1) >= 1, f"generation={g1!r}"))

    # Releer no la mueve: dedup dentro del mismo despacho tiene que seguir
    # funcionando, o se pierde la proteccion contra el doble envio.
    g1b = sh("thalos_agent_ref_field F001 generation", proj).stdout.strip()
    results.append(check(
        "leerla dos veces da lo mismo: un reintento sigue deduplicando",
        g1 == g1b, f"{g1} vs {g1b}"))

    sh("thalos_agent_ref_clear F001", proj)
    sh("thalos_agent_ref_write F001 ad.herdr agente1 w1:p2 ref2", proj)
    g2 = sh("thalos_agent_ref_field F001 generation", proj).stdout.strip()
    results.append(check(
        "un redespacho la incrementa aunque el agente se llame igual",
        g2.isdigit() and int(g2) > int(g1), f"{g1} -> {g2}"))

    results.append(check(
        "soltar el agente NO borra el contador: si no, volveria a empezar en 1",
        int(g2) == int(g1) + 1, f"{g1} -> {g2}"))

    # ---------- el efecto sobre la clave ----------

    a1 = json.dumps({"target": "agente1", "text": "hace la tarea",
                     "agent_generation": g1}, sort_keys=True)
    a2 = json.dumps({"target": "agente1", "text": "hace la tarea",
                     "agent_generation": g2}, sort_keys=True)
    k1, k2 = key("r-1", "F001", "prompt_agent", a1), key("r-1", "F001", "prompt_agent", a2)
    results.append(check(
        "el mismo encargo en dos despachos da claves DISTINTAS",
        k1 and k2 and k1 != k2, f"{k1[:16]} vs {k2[:16]}"))
    results.append(check(
        "y el mismo encargo en el mismo despacho da la MISMA clave",
        k1 == key("r-1", "F001", "prompt_agent", a1), "el reintento debe deduplicar"))

    # ---------- el camino real: dos entregas, no una ----------
    #
    # Lo que fallaba de verdad. Un adapter espia cuenta los envios: sin la
    # generacion, el segundo despacho no producia ninguno.
    lab = pathlib.Path(tempfile.mkdtemp())
    cuenta = lab / "envios"
    stub = lab / "stub.sh"
    stub.write_text(f"""
thalos_capability_run() {{
    if [ "$2" = observe_agent ]; then
        _n=$(cat {lab}/seq 2>/dev/null || echo 0); _n=$((_n + 1))
        echo "$_n" > {lab}/seq
        echo '{{"pane_exists":true,"state":"idle","state_change_seq":'"$_n"'}}'
    else
        echo "$3" >> {cuenta}
        echo '{{"status":"created"}}'
    fi
}}
""")
    script = f"""
. {stub}
. {ROOT}/hooks/lib/ack.sh
thalos_ack_send agente1 "hace la tarea" 1
thalos_ack_send agente1 "hace la tarea" 2
"""
    subprocess.run(["sh", "-c", script], capture_output=True, text=True,
                   env={**os.environ, "THALOS_SYSTEM_ROOT": str(ROOT)})
    envios = cuenta.read_text().splitlines() if cuenta.exists() else []
    results.append(check(
        "dos despachos producen dos envios, no uno",
        len(envios) == 2, f"envios={len(envios)}"))
    results.append(check(
        "y cada envio lleva su generacion en los semantic_args",
        len(envios) == 2 and '"agent_generation":"1"' in envios[0]
        and '"agent_generation":"2"' in envios[1],
        f"{envios}"))

    # ---------- at_most_once REGISTRA, NO SUPRIME (regla 38.2.7) ----------
    #
    # La raiz de verdad. El manifiesto declara prompt_agent at_most_once, o sea
    # que el adapter NO PUEDE garantizar idempotencia; y el ledger la suprimia
    # igual. Un adapter que suprime esta fingiendo la garantia que acaba de
    # declarar que no puede dar.
    #
    # El caso que lo destapa no es el redespacho sino el mismo encargo dos
    # veces dentro del MISMO despacho: `thalos run` llama a `feature work` en
    # bucle, y la segunda vuelta se descartaba en silencio. Con el ACK
    # observado eso pasa a reportar NOT_DELIVERED sobre un agente vivo, que es
    # peor: aborta a alguien que estaba trabajando.
    box = pathlib.Path(tempfile.mkdtemp())
    (box / "orchestration").mkdir(parents=True)
    args = '{"target":"a1","text":"hace la tarea","agent_generation":"1"}'
    script = (
        f'. {ROOT}/adapters/lib/adapter.sh\n'
        f'THALOS_ADAPTER_SIMULATED=1\n'
        f'thalos_run_at_most_once prompt_agent r-1 F001 \'{args}\' id '
        f'printf \'{{"id":"x"}}\'\n'
        f'thalos_run_at_most_once prompt_agent r-1 F001 \'{args}\' id '
        f'printf \'{{"id":"x"}}\'\n')
    p = subprocess.run(["sh", "-c", script], capture_output=True, text=True,
                       env={**os.environ, "THALOS_PROJECT_ROOT": str(box)})
    creados = p.stdout.count('"status":"created"')
    results.append(check(
        "el mismo encargo dos veces se ENVIA dos veces (regla 38.2.7)",
        creados == 2,
        f'created={creados}, already_exists={p.stdout.count("already_exists")}'),
    )

    ledger = list(box.rglob("ledger.tsv"))
    entradas = (ledger[0].read_text().count("prompt_agent") if ledger else 0)
    results.append(check(
        "y las dos quedan registradas: sin rastro no hay auditoria",
        entradas == 2, f"entradas={entradas}"))

    # Lo que SI se deduplica no cambia: una operacion que declara idempotencia
    # sigue protegida, que es para lo que existe el ledger.
    script = (
        f'. {ROOT}/adapters/lib/adapter.sh\n'
        f'THALOS_ADAPTER_SIMULATED=1\n'
        f'thalos_mutate create_workspace r-1 F001 \'{{"label":"x"}}\' \'{{"id":"w1"}}\'\n'
        f'thalos_mutate create_workspace r-1 F001 \'{{"label":"x"}}\' \'{{"id":"w1"}}\'\n')
    box2 = pathlib.Path(tempfile.mkdtemp())
    (box2 / "orchestration").mkdir(parents=True)
    p = subprocess.run(["sh", "-c", script], capture_output=True, text=True,
                       env={**os.environ, "THALOS_PROJECT_ROOT": str(box2)})
    results.append(check(
        "una operacion idempotente SIGUE deduplicando: no se rompio esa proteccion",
        p.stdout.count('"status":"already_exists"') == 1,
        p.stdout.replace("\n", " ")[:150]))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks del redespacho")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
