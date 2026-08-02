#!/usr/bin/env python3
"""La tabla de decision de vitalidad. Ver thalos-mensajeria-0.0.1.md seccion 5.

Es una unidad PURA: no necesita agente, ni Herdr, ni red. Esa es la propiedad
que se verifica aca. Lo que el adapter aporta son cuatro hechos; decidir con
ellos no depende de nadie, y por eso se puede probar cada fila de la tabla.

Cada caso NEGATIVO corresponde a una regla normativa, no a un gusto.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "hooks" / "lib"))

import liveness  # noqa: E402


def obs(state="working", pane=True, alive=True, observado=True):
    return {"pane_exists": pane, "state": state, "state_change_seq": 1,
            "process_alive": alive, "process_observed": observado}


# (descripcion, observacion, contexto, veredicto esperado, regla)
CASOS = [
    # --- las filas de la tabla 5.2
    ("panel ausente", obs(pane=False), {}, "GONE", "5.2: el panel se fue con su proceso"),

    ("working con proceso vivo", obs("working"), {},
     "ALIVE_WORKING", "5.2: sigue observando"),

    ("working con proceso MUERTO", obs("working", alive=False), {},
     "DEAD", "4.3.2: process_alive falso prevalece sobre cualquier state"),

    ("blocked confirmado", obs("blocked"), {"blocked_samples": 3},
     "WAITING_HUMAN", "5.6.2: bloqueado con proceso vivo escala a persona"),

    ("blocked con proceso muerto", obs("blocked", alive=False), {},
     "FAILED", "5.6.1: bloqueado sin proceso es una sesion que fallo"),

    ("done con ACK confirmado", obs("done"), {"ack_confirmed": True},
     "DONE", "M-004: done tras ACK es terminacion de turno"),

    ("idle con ACK confirmado", obs("idle"), {"ack_confirmed": True},
     "DONE", "M-004: idle y done se clasifican juntos"),

    ("done SIN ACK", obs("done"), {},
     "UNOBSERVABLE", "5.3.7: sin ACK no termino nada, esta en reposo"),

    ("idle SIN ACK", obs("idle"), {},
     "UNOBSERVABLE", "M-004: el mismo valor crudo significa cosas opuestas"),

    ("unknown con proceso vivo", obs("unknown"), {},
     "UNOBSERVABLE", "4.5.2: unknown es 'el backend no sabe', no es fallo"),

    ("idle con proceso muerto", obs("idle", alive=False), {},
     "DEAD", "5.2: el proceso manda aunque el estado sea de reposo"),

    # --- precedencia (5.4)
    ("expirado gana sobre todo", obs("working"), {"expired": True},
     "EXPIRED", "5.3.2: EXPIRED tiene precedencia sobre todos"),

    ("panel ausente gana sobre proceso muerto", obs("working", pane=False, alive=False), {},
     "GONE", "5.3.3: GONE tiene precedencia sobre DEAD"),

    ("proceso muerto gana sobre el state", obs("done", alive=False),
     {"ack_confirmed": True},
     "DEAD", "5.3.4: DEAD prevalece sobre cualquier veredicto del state"),

    # --- regla 4.3.1: no poder mirar no es estar muerto
    ("proceso NO observado, estado working", obs("working", alive=False, observado=False), {},
     "ALIVE_WORKING", "4.3.1.2: sin observacion, process_alive no porta informacion"),

    ("proceso NO observado, estado done con ACK",
     obs("done", alive=False, observado=False), {"ack_confirmed": True},
     "DONE", "4.3.1.3: sin observacion se degrada al state, no se inventa la muerte"),

    # --- regla 5.3.5: un bloqueo momentaneo no es un bloqueo
    ("blocked en la PRIMERA muestra", obs("blocked"), {"blocked_samples": 1},
     "ALIVE_WORKING", "5.3.5: el runtime resuelve bloqueos momentaneos solo"),

    ("blocked en la segunda, con umbral 3", obs("blocked"), {"blocked_samples": 2},
     "ALIVE_WORKING", "5.3.5: todavia no alcanza el umbral configurado"),
]

# El codigo de salida lleva la CLASE DE ACCION, no el veredicto (seccion 11.2).
CODIGOS = {
    "ALIVE_WORKING": 0, "DONE": 0,
    "UNOBSERVABLE": 2,
    "EXPIRED": 3,
    "WAITING_HUMAN": 4,
    "DEAD": 5, "GONE": 5, "FAILED": 5,
}


def check(label, cond, detail=""):
    if cond:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def main():
    results = []

    for desc, o, ctx, esperado, regla in CASOS:
        got = liveness.veredicto(o, **ctx)
        results.append(check(
            f"{desc} -> {esperado}",
            got["veredicto"] == esperado,
            f"dio {got['veredicto']}; requisito: {regla}",
        ))

    # Todo veredicto tiene exactamente una accion (regla 3.8).
    for nombre in CODIGOS:
        results.append(check(
            f"{nombre} declara su accion",
            bool(liveness.ACCIONES.get(nombre)),
            "un veredicto sin accion deja a quien llama sin saber que hacer",
        ))

    # Los codigos de salida respetan la seccion 40.4 del nucleo.
    for nombre, code in CODIGOS.items():
        results.append(check(
            f"{nombre} sale con {code}",
            liveness.codigo_salida(nombre) == code,
            f"dio {liveness.codigo_salida(nombre)}",
        ))

    # La CLI imprime el veredicto como PRIMER token para que un case ramifique.
    p = subprocess.run(
        [sys.executable, str(ROOT / "hooks" / "lib" / "liveness.py"), "verdict",
         '{"pane_exists":true,"state":"working","process_alive":false,'
         '"process_observed":true,"state_change_seq":1}'],
        capture_output=True, text=True)
    results.append(check(
        "la CLI imprime el veredicto como primer token (regla 11.1)",
        p.stdout.split()[:1] == ["DEAD"], f"stdout={p.stdout[:80]!r}"))
    results.append(check(
        "y sale con la clase de accion, no con el veredicto (regla 11.2)",
        p.returncode == 5, f"rc={p.returncode}"))

    # Una observacion sin los campos nuevos no puede matar a nadie: un adapter
    # viejo no declara process_observed, y asumir la muerte seria una regresion.
    got = liveness.veredicto({"pane_exists": True, "state": "working"})
    results.append(check(
        "una observacion incompleta no produce DEAD",
        got["veredicto"] == "ALIVE_WORKING", str(got)))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks de la tabla de vitalidad")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
