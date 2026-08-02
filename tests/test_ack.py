#!/usr/bin/env python3
"""El ACK observado. Ver thalos-mensajeria-0.0.1.md seccion 7.

Se ejercita hooks/lib/ack.sh contra un ExecutionAdapter de mentira, porque lo
que hay que probar no es que Herdr funcione sino que Thalos SEPA SI EL ENCARGO
ENTRO. Antes no lo sabia: prompt_agent devolvia 0 y el paso reportaba exito
aunque el agente no se hubiera enterado de nada.
"""
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


def escenario(observaciones, prompt_rc=0, cuenta=None):
    """Corre thalos_ack_send con un adapter falso.

    observaciones es la lista de respuestas que devuelve observe_agent, en
    orden. cuenta, si se pasa, es un archivo donde cada prompt deja una marca:
    es lo que permite contar reenvios reales en vez de creerle a la salida.
    """
    d = pathlib.Path(tempfile.mkdtemp())
    obs_file = d / "obs"
    obs_file.write_text("\n".join(observaciones) + "\n")

    # Sustituye a thalos_capability_run: el adapter no importa, importa el
    # protocolo. Cada llamada a observe_agent consume una linea del guion.
    stub = d / "stub.sh"
    stub.write_text(f"""
thalos_capability_run() {{
    _op="$2"
    if [ "$_op" = observe_agent ]; then
        _n=$(cat {d}/idx 2>/dev/null || echo 1)
        sed -n "${{_n}}p" {obs_file}
        echo $(( _n + 1 )) > {d}/idx
    else
        {"echo x >> " + str(cuenta) if cuenta else ":"}
        echo '{{"status":"created"}}'
        return {prompt_rc}
    fi
}}
""")
    script = f"""
set -e
. {stub}
. {ROOT}/hooks/lib/ack.sh
thalos_ack_send target-de-prueba "hola"
"""
    p = subprocess.run(["sh", "-c", script], capture_output=True, text=True,
                       env={**os.environ, "THALOS_SYSTEM_ROOT": str(ROOT)})
    return p.returncode


VIVO = '{"pane_exists":true,"state":"idle","state_change_seq":10}'
MOVIDO = '{"pane_exists":true,"state":"working","state_change_seq":11}'
QUIETO = '{"pane_exists":true,"state":"idle","state_change_seq":10}'


def main():
    results = []

    # El encargo entra: el estado cambia despues del envio.
    rc = escenario([VIVO, MOVIDO])
    results.append(check(
        "hay ACK cuando el agente cambia de estado tras el envio",
        rc == 0, f"rc={rc}; requisito 7.2.1: el ACK es una transicion"))

    # El contador se mueve aunque el nombre del estado sea el mismo. Pasa
    # cuando el agente ya estaba working y vuelve a working por otro evento.
    rc = escenario([VIVO, '{"pane_exists":true,"state":"idle","state_change_seq":99}'])
    results.append(check(
        "hay ACK cuando se mueve el contador aunque el estado se llame igual",
        rc == 0, f"rc={rc}"))

    # EL caso que no se detectaba: se envio y no paso nada.
    cuenta = pathlib.Path(tempfile.mkdtemp()) / "n"
    rc = escenario([QUIETO] * 200, cuenta=cuenta)
    results.append(check(
        "sin transicion, NOT_DELIVERED en vez de exito silencioso",
        rc == 1, f"rc={rc}; requisito 7.3: el encargo no llego"))

    # Regla 7.3.2: hereda max_attempts. Reenviar es seguro porque no llego.
    reenvios = len(cuenta.read_text().split()) if cuenta.exists() else 0
    results.append(check(
        "reintenta hasta max_attempts antes de rendirse (regla 7.3.2)",
        reenvios == 3, f"envio {reenvios} veces, config dice 3"))

    # Un adapter que ni pudo enviar no es lo mismo que un encargo que no entro.
    rc = escenario([VIVO, QUIETO], prompt_rc=5)
    results.append(check(
        "un fallo de envio sale 5, distinto de NOT_DELIVERED",
        rc == 5, f"rc={rc}"))

    # LA CONTRACARA. Un ExecutionAdapter que no implementa observe_agent no
    # devuelve ni estado ni contador: no hay contra que comparar. Leer esa
    # falta de senal como falta de entrega abortaba despachos que funcionaban,
    # que es peor que no detectar uno perdido. Misma leccion que la 4.3.1.
    cuenta2 = pathlib.Path(tempfile.mkdtemp()) / "n"
    rc = escenario(['{"status":"ok","result":{}}'] * 10, cuenta=cuenta2)
    results.append(check(
        "un adapter que no observa NO convierte el despacho en NOT_DELIVERED",
        rc == 0, f"rc={rc}; sin senal se degrada, no se inventa el fallo"))
    envios = len(cuenta2.read_text().split()) if cuenta2.exists() else 0
    results.append(check(
        "y no reenvia el encargo por una senal que nunca iba a llegar",
        envios == 1, f"envio {envios} veces"))

    # En simulacion nadie procesa: exigir ACK volveria NOT_DELIVERED toda
    # corrida dry-run, que es el modo en que hoy se valida Thalos entero.
    d = pathlib.Path(tempfile.mkdtemp())
    stub = d / "stub.sh"
    stub.write_text("""
thalos_capability_run() {
    if [ "$2" = observe_agent ]; then
        echo '{"pane_exists":true,"state":"idle","state_change_seq":1}'
    else
        echo '{"status":"created","dry_run":true}'
    fi
}
""")
    p = subprocess.run(
        ["sh", "-c", f". {stub}\n. {ROOT}/hooks/lib/ack.sh\n"
                     f"thalos_ack_send t 'x'"],
        capture_output=True, text=True,
        env={**os.environ, "THALOS_SYSTEM_ROOT": str(ROOT)})
    results.append(check(
        "en dry-run no se exige ACK: nadie procesa el encargo",
        p.returncode == 0, f"rc={p.returncode}"))

    # ---------- persistencia del ACK ----------
    #
    # Se consulta DESPUES del despacho, desde otro proceso. Sin persistirlo, un
    # `done` en reposo y un `done` de terminacion son el mismo byte.
    proj = pathlib.Path(tempfile.mkdtemp())
    (proj / "orchestration" / "features" / "F001").mkdir(parents=True)
    base = (f". {ROOT}/hooks/lib/agent-ref.sh\n")
    env = {**os.environ, "THALOS_PROJECT_ROOT": str(proj)}

    p = subprocess.run(["sh", "-c", base + "thalos_agent_ack_is F001"],
                       capture_output=True, env=env)
    results.append(check("sin despacho no hay ACK registrado", p.returncode != 0))

    p = subprocess.run(
        ["sh", "-c", base + "thalos_agent_ack_set F001; thalos_agent_ack_is F001"],
        capture_output=True, env=env)
    results.append(check("el ACK queda persistido (regla 7.2.2)", p.returncode == 0))

    p = subprocess.run(
        ["sh", "-c", base + "thalos_agent_ref_clear F001; thalos_agent_ack_is F001"],
        capture_output=True, env=env)
    results.append(check(
        "soltar el agente borra su ACK: el proximo encargo empieza limpio",
        p.returncode != 0))

    # ---------- el lector de configuracion ----------
    sys.path.insert(0, str(ROOT / "hooks" / "lib"))
    import config as cfg  # noqa: E402

    v = cfg.leer(ROOT / "config" / "reliability.yaml",
                 "reliability.operations.agent_prompt.max_attempts", 0)
    results.append(check(
        "lee una clave anidada sin confundirla con sus homonimas",
        v == 3, f"dio {v}; max_attempts aparece en siete operaciones distintas"))

    v = cfg.leer(ROOT / "config" / "no-existe.yaml", "a.b", "porDefecto")
    results.append(check(
        "un archivo ausente devuelve el default en vez de romper",
        v == "porDefecto", f"dio {v}"))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks del ACK observado")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
