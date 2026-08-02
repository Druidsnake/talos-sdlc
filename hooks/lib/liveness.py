#!/usr/bin/env python3
"""Vitalidad de un agente. Ver thalos-mensajeria-0.0.1.md secciones 4 y 5.

LA REGLA QUE GOBIERNA ESTE ARCHIVO ES LA 3.6

    "Un hecho del sistema operativo DEBE prevalecer sobre un estado reportado."

El estado que publica el runtime es la MEMORIA DE LO QUE ALGUIEN DIJO, y
sobrevive a que ese alguien se muera. Medido contra la implementacion de
referencia del ExecutionAdapter: matando el proceso del agente y dejando el
shell vivo, el backend sigue publicando `working` indefinidamente y su
contador de cambios de estado queda congelado. Un maestro que le cree a ese
estado espera media hora a un fantasma.

Por eso decidir mirando solo `state` es el defecto, no la solucion. Lo que
distingue a un agente que trabaja de uno que murio trabajando es si su proceso
esta: foreground_process_group_id != shell_pid.

Y LA 4.3.1, QUE ES SU CONTRAPESO

    "No poder mirar no es estar muerto."

Los dos modos de fallar de este archivo NO son simetricos. No detectar una
muerte cuesta tiempo de espera; declarar muerto a un agente sano cuesta el
trabajo que estaba haciendo. Ante la duda se degrada al comportamiento
anterior -decidir por el estado- y nunca se inventa la muerte.

Es una unidad PURA: no habla con ningun backend ni con el disco. Recibe los
cuatro hechos que junto el adapter y devuelve un veredicto con su accion. El
nucleo no conoce -ni debe conocer- que implementacion los produjo.

USO
    liveness.py verdict <observacion-json> [--ack] [--expired]
                        [--blocked-samples N] [--blocked-confirm N]

SALIDA
    El nombre del veredicto como PRIMER token, para que un `case` de shell
    pueda ramificar sin parsear JSON (regla 11.1).

CODIGOS DE SALIDA
    Portan la CLASE DE ACCION, no la identidad del veredicto, y respetan la
    seccion 40.4 del nucleo (regla 11.2).

    0  no hay nada que hacer        ALIVE_WORKING, DONE
    2  precondition fallida         UNOBSERVABLE
    3  plazo agotado                EXPIRED
    4  escalacion requerida         WAITING_HUMAN
    5  hay que redespachar          DEAD, GONE, FAILED
"""
import json
import sys

# Regla 3.8: cada veredicto tiene EXACTAMENTE una accion. Un veredicto sin
# accion deja a quien llama sin saber que hacer, que es como estabamos.
ACCIONES = {
    "ALIVE_WORKING": "seguir observando",
    "DONE": "fin de turno: mirar si aparecio el entregable",
    "WAITING_HUMAN": "escalar a una persona con evidencia adjunta",
    "DEAD": "cortar la espera y redespachar",
    "FAILED": "cortar la espera y redespachar",
    "GONE": "liberar la referencia y redespachar",
    "UNOBSERVABLE": "esperar el ACK o reparar la integracion del runtime",
    "EXPIRED": "cortar, consumir presupuesto y escalar",
}

CODIGOS = {
    "ALIVE_WORKING": 0, "DONE": 0,
    "UNOBSERVABLE": 2,
    "EXPIRED": 3,
    "WAITING_HUMAN": 4,
    "DEAD": 5, "GONE": 5, "FAILED": 5,
}


def codigo_salida(veredicto):
    return CODIGOS.get(veredicto, 1)


def veredicto(obs, ack_confirmed=False, expired=False,
              blocked_samples=0, blocked_confirm_samples=3):
    """Aplica la tabla de decision de la seccion 5.2.

    obs son los cuatro hechos de observe_agent. El resto lo sabe Thalos porque
    el mando el encargo: el backend no puede saber si hubo ACK ni cuanto se
    lleva esperando.
    """
    estado = obs.get("state") or "unknown"

    # Precedencia de la seccion 5.4:
    #   EXPIRED > GONE > DEAD > WAITING_HUMAN > DONE > ALIVE_WORKING > UNOBSERVABLE

    if expired:
        return _r("EXPIRED", estado)

    # Mas fuerte que "no esta vivo": el panel entero se fue. Medido, ocurre en
    # menos de un segundo cuando muere el shell.
    if not obs.get("pane_exists", True):
        return _r("GONE", estado)

    # Regla 4.3.1.2: process_alive SOLO se lee si process_observed. Sin
    # observacion el campo no porta informacion y se decide por el estado.
    #
    # El default de process_observed es True para que una observacion vieja
    # -de un adapter que no declara el campo- no cambie de significado. El
    # default de process_alive es True porque la ausencia de evidencia de
    # muerte no es evidencia de muerte.
    observado = obs.get("process_observed", True)
    vivo = obs.get("process_alive", True)
    if observado and not vivo:
        # blocked sin proceso no es alguien esperando una decision: es una
        # sesion que fallo y dejo el estado colgado (regla 5.6.1).
        return _r("FAILED" if estado == "blocked" else "DEAD", estado)

    if estado == "blocked":
        # Regla 5.3.5: el runtime pasa por bloqueos momentaneos que resuelve
        # solo. Cortar en la primera lectura aborta a un agente que trabaja
        # bien, y eso ya paso. Hasta confirmar el umbral, sigue vivo.
        if blocked_samples >= blocked_confirm_samples:
            return _r("WAITING_HUMAN", estado)
        return _r("ALIVE_WORKING", estado)

    if estado in ("done", "idle"):
        # Decision M-004. El mismo valor crudo significa cosas opuestas segun
        # donde este el handshake: en reposo antes del encargo, o terminacion
        # despues. Esa diferencia la sabe Thalos y no el backend.
        return _r("DONE" if ack_confirmed else "UNOBSERVABLE", estado)

    if estado == "working":
        return _r("ALIVE_WORKING", estado)

    # unknown: el backend no tiene informacion, tipicamente porque al runtime
    # le falta la integracion que reporta estado. NO es un fallo del agente y
    # NO DEBE producir un veredicto negativo (regla 4.5.3).
    return _r("UNOBSERVABLE", estado)


def _r(nombre, estado):
    return {
        "veredicto": nombre,
        "accion": ACCIONES[nombre],
        "state": estado,
        "exit_code": CODIGOS[nombre],
        "corta_espera": nombre != "ALIVE_WORKING",
    }


def main(argv):
    if len(argv) < 3 or argv[1] != "verdict":
        print(__doc__.strip(), file=sys.stderr)
        return 1
    try:
        obs = json.loads(argv[2])
    except ValueError as exc:
        print(f"thalos: la observacion no es JSON valido: {exc}", file=sys.stderr)
        return 1

    ctx = {"ack_confirmed": False, "expired": False,
           "blocked_samples": 0, "blocked_confirm_samples": 3}
    rest = argv[3:]
    while rest:
        flag = rest[0]
        if flag == "--ack":
            ctx["ack_confirmed"] = True
            rest = rest[1:]
        elif flag == "--expired":
            ctx["expired"] = True
            rest = rest[1:]
        elif flag in ("--blocked-samples", "--blocked-confirm") and len(rest) > 1:
            clave = ("blocked_samples" if flag == "--blocked-samples"
                     else "blocked_confirm_samples")
            try:
                ctx[clave] = int(rest[1])
            except ValueError:
                print(f"thalos: {flag} espera un entero", file=sys.stderr)
                return 1
            rest = rest[2:]
        else:
            print(f"thalos: opcion desconocida: {flag}", file=sys.stderr)
            return 1

    r = veredicto(obs, **ctx)
    # El veredicto va PRIMERO para que `case $(...) in` funcione (regla 11.1).
    print(f"{r['veredicto']}\t{r['accion']}")
    return r["exit_code"]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
