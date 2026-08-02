#!/usr/bin/env python3
"""Ciclo de vida de los mensajes. Ver thalos-0.0.7.md 25.5 y mensajeria 8.

Las reglas 25.5.7, 25.5.8 y 25.5.9 estaban escritas desde 0.0.4 y NADIE las
implementaba: `expires_at` se escribia siempre en None, asi que ninguna
pregunta expiraba y ninguna escalaba. Una pregunta critica que nadie contesta
se quedaba OPEN para siempre y el sistema no se enteraba.
"""
import datetime
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "hooks" / "lib"))

import message  # noqa: E402


def check(label, cond, detail=""):
    if cond:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def caja():
    return pathlib.Path(tempfile.mkdtemp()) / "messages"


def envejecer(root, mid, segundos):
    """Mueve expires_at al pasado sin tocar nada mas."""
    f = pathlib.Path(root) / f"{mid}.json"
    m = json.loads(f.read_text())
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=segundos)
    m["expires_at"] = t.strftime("%Y-%m-%dT%H:%M:%SZ")
    f.write_text(json.dumps(m, indent=2) + "\n")


def leer(root, mid):
    return json.loads((pathlib.Path(root) / f"{mid}.json").read_text())


def main():
    results = []

    # ---------- 25.5.7: todo mensaje nace con plazo ----------
    d = caja()
    mid = message.enviar(d, "QUESTION", "role:Developer", "human:operator",
                         "r-1", "F001", "T01", "no puedo seguir")
    m = leer(d, mid)
    results.append(check(
        "un mensaje nuevo trae expires_at (regla 25.5.7)",
        m.get("expires_at"), f"expires_at={m.get('expires_at')!r}"))
    results.append(check(
        "y nace OPEN",
        m.get("state") == "OPEN", m.get("state")))

    # ---------- 25.5.8: vencido sin respuesta pasa a EXPIRED ----------
    envejecer(d, mid, 60)
    cambios = message.barrer(d)
    results.append(check(
        "el barrido marca EXPIRED lo vencido (regla 25.5.8)",
        leer(d, mid)["state"] == "EXPIRED", leer(d, mid)["state"]))
    results.append(check(
        "y reporta que cambio, para que quien llama pueda emitir el evento",
        any(c["id"] == mid for c in cambios), str(cambios)))

    # El barrido corre acoplado a comandos que ya ocurren: tiene que poder
    # correr muchas veces sin cambiar nada la segunda.
    results.append(check(
        "barrer dos veces no vuelve a reportar lo mismo (idempotente)",
        message.barrer(d) == [], str(message.barrer(d))))

    # ---------- 25.5.9: lo critico vencido escala ----------
    d2 = caja()
    esc = message.enviar(d2, "ESCALATION", "role:Developer", "human:operator",
                         "r-1", "F001", "T01", "necesito una decision")
    results.append(check(
        "una ESCALATION nace critical",
        leer(d2, esc)["critical"] is True))
    envejecer(d2, esc, 60)
    cambios = message.barrer(d2)
    results.append(check(
        "un critico vencido queda ESCALATED, no EXPIRED (regla 25.5.9)",
        leer(d2, esc)["state"] == "ESCALATED", leer(d2, esc)["state"]))
    results.append(check(
        "y se reporta como escalado para disparar el evento",
        any(c["id"] == esc and c["escalado"] for c in cambios), str(cambios)))

    # ---------- 8.1.4: los terminales no expiran ----------
    d3 = caja()
    for estado in ("ANSWERED", "CLOSED", "ESCALATED"):
        x = message.enviar(d3, "QUESTION", "a", "b", "r", "F001", "T01", "x")
        message.cerrar(d3, x, estado)
        envejecer(d3, x, 999)
        message.barrer(d3)
        results.append(check(
            f"{estado} es terminal y no expira (regla 8.1.4)",
            leer(d3, x)["state"] == estado, leer(d3, x)["state"]))

    # ---------- 8.2.5: expiracion perezosa ----------
    #
    # LA decision M-003. Sin esto, alguien mira un mensaje, ve que vencio hace
    # horas y lo ve OPEN porque el barrido todavia no paso. Dos verdades sobre
    # el mismo mensaje.
    d4 = caja()
    p = message.enviar(d4, "QUESTION", "a", "b", "r", "F001", "T01", "hola")
    envejecer(d4, p, 60)
    salida = subprocess.run(
        [sys.executable, str(ROOT / "hooks" / "lib" / "message.py"), "show",
         str(d4), p], capture_output=True, text=True)
    results.append(check(
        "un vencido NUNCA se muestra OPEN, aunque no haya corrido el barrido",
        '"OPEN"' not in salida.stdout and "EXPIRED" in salida.stdout,
        salida.stdout[:200]))
    results.append(check(
        "y la lectura lo deja escrito: no quedan dos verdades del mismo mensaje",
        leer(d4, p)["state"] == "EXPIRED", leer(d4, p)["state"]))

    # Lo mismo por el listado, que es por donde mira una persona.
    d5 = caja()
    q = message.enviar(d5, "QUESTION", "a", "b", "r", "F001", "T01", "hola")
    envejecer(d5, q, 60)
    salida = subprocess.run(
        [sys.executable, str(ROOT / "hooks" / "lib" / "message.py"), "list", str(d5)],
        capture_output=True, text=True)
    results.append(check(
        "el listado tampoco muestra OPEN lo que ya vencio",
        "OPEN" not in salida.stdout, salida.stdout[:200]))

    # ---------- STATUS_UPDATE ----------
    #
    # El canal declarado (mensajeria 6). Existe en el schema desde 0.0.5 y no
    # lo emitia nadie.
    d6 = caja()
    s = message.enviar(d6, "STATUS_UPDATE", "role:Developer", "thalos:core",
                       "r-1", "F001", "T01", "voy por la mitad")
    results.append(check(
        "STATUS_UPDATE se puede emitir y se persiste",
        leer(d6, s)["type"] == "STATUS_UPDATE"))
    results.append(check(
        "un STATUS_UPDATE no es critico: informa, no pide nada",
        leer(d6, s)["critical"] is False))

    # ---------- el plazo sale de config ----------
    v = subprocess.run(
        [sys.executable, str(ROOT / "hooks" / "lib" / "config.py"),
         str(ROOT / "config" / "communication.yaml"),
         "default_expiry_seconds", "0"], capture_output=True, text=True)
    results.append(check(
        "el plazo por defecto sale de communication.yaml, no del codigo",
        v.stdout.strip() == "3600", v.stdout.strip()))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks del ciclo de vida de mensajes")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
