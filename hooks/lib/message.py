#!/usr/bin/env python3
"""Comunicacion entre roles. Ver talos-0.0.7.md seccion 25.

La seccion 25 estaba especificada entera -tipos, estados, canales, expiracion,
escalacion- y no la implementaba nadie: lo unico que la mencionaba era el
init.sh que creaba orchestration/messages/ vacio. La consecuencia se veia
corriendo: un agente contestaba "no puedo por X", Talos esperaba un archivo que
no llegaba, agotaba el plazo y reportaba "termino sin dejar entregable". El
motivo existia y se perdia.

LA ESTRUCTURA LA PONE TALOS, EL CONTENIDO PUEDE SER RUIDO.

La regla 25.1.1 pide comunicacion estructurada. Exigirle esa estructura al
agente es lo que rompe la comunicacion: si contesta distinto, se pierde. Aca la
estructura es del sobre -quien, a quien, sobre que, en que hilo- y el cuerpo es
lo que haya dicho, tal cual. Un mensaje ilegible entregado es infinitamente mas
util que uno perfecto que nunca se escribio.

USO
    message.py send <dir> <tipo> <de> <para> <run> <feature> <task> <archivo-cuerpo>
    message.py list <dir> [estado]
    message.py show <dir> <id>
    message.py close <dir> <id> <estado>
"""
import json
import pathlib
import sys
import datetime

TIPOS = {"TASK_REQUEST", "TASK_RESPONSE", "QUESTION", "ANSWER",
         "REVIEW_REQUEST", "REVIEW_RESPONSE", "FIX_REQUEST", "FIX_RESPONSE",
         "STATUS_UPDATE", "ESCALATION", "APPROVAL_REQUEST", "APPROVAL_RESPONSE",
         "SPEC_ASSIST_REQUEST", "SPEC_ASSIST_RESPONSE"}
ESTADOS = {"OPEN", "ACKED", "ANSWERED", "CLOSED", "EXPIRED", "ESCALATED"}

# Regla 25.5.1: payload de 16 KB como maximo. Lo que se pase se recorta y el
# original queda como artefacto referenciado, que es lo que manda la 25.5.2:
# el contexto extenso se referencia, no se transporta.
LIMITE = 16 * 1024


def ahora():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def dir_mensajes(root):
    d = pathlib.Path(root)
    d.mkdir(parents=True, exist_ok=True)
    return d


def enviar(root, tipo, de, para, run, feature, task, cuerpo, hilo=None,
           en_respuesta_a=None, refs=None):
    if tipo not in TIPOS:
        raise SystemExit(f"talos: tipo de mensaje desconocido: {tipo}")
    d = dir_mensajes(root)
    seq = len(list(d.glob("msg-*.json"))) + 1
    mid = f"msg-{seq:04d}-{tipo.lower()}"
    artefactos = list(refs or [])

    texto = cuerpo or ""
    if len(texto.encode("utf-8")) > LIMITE:
        # Regla 25.5.2: no se rechaza ni se trunca en silencio. Se persiste
        # entero y el mensaje referencia el archivo.
        gordo = d / f"{mid}.body.txt"
        gordo.write_text(texto)
        artefactos.append(str(gordo))
        texto = texto.encode("utf-8")[:LIMITE].decode("utf-8", "ignore")

    msg = {
        "id": mid,
        "thread_id": hilo or mid,
        "in_reply_to": en_respuesta_a,
        "type": tipo,
        "from": de,
        "to": para,
        "run_id": run,
        "feature_id": feature or None,
        "task_id": task or None,
        "state": "OPEN",
        "critical": tipo in ("ESCALATION", "APPROVAL_REQUEST"),
        "artifact_refs": artefactos,
        "evidence_refs": [],
        "payload": {"text": texto},
        "payload_bytes": len(json.dumps({"text": texto}).encode("utf-8")),
        "created_at": ahora(),
        "expires_at": None,
    }
    (d / f"{mid}.json").write_text(json.dumps(msg, indent=2, ensure_ascii=False) + "\n")
    print(mid)
    return mid


def cargar_todos(root):
    d = pathlib.Path(root)
    out = []
    for f in sorted(d.glob("msg-*.json")) if d.is_dir() else []:
        try:
            out.append(json.loads(f.read_text()))
        except (json.JSONDecodeError, OSError):
            continue
    return out


def listar(root, estado=None):
    for m in cargar_todos(root):
        if estado and m.get("state") != estado:
            continue
        texto = (m.get("payload") or {}).get("text", "").replace("\n", " ")
        print(f"{m['id']}\t{m['state']}\t{m['type']}\t{m['from']} -> {m['to']}"
              f"\t{m.get('feature_id') or '-'}\t{texto[:70]}")


def mostrar(root, mid):
    for m in cargar_todos(root):
        if m["id"] == mid:
            print(json.dumps(m, indent=2, ensure_ascii=False))
            return 0
    print(f"talos: no existe el mensaje {mid}", file=sys.stderr)
    return 2


def cerrar(root, mid, estado):
    if estado not in ESTADOS:
        raise SystemExit(f"talos: estado desconocido: {estado}")
    d = pathlib.Path(root)
    f = d / f"{mid}.json"
    if not f.is_file():
        print(f"talos: no existe el mensaje {mid}", file=sys.stderr)
        return 2
    m = json.loads(f.read_text())
    m["state"] = estado
    f.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
    return 0


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    cmd, root = argv[1], argv[2]
    if cmd == "send":
        tipo, de, para, run, feature, task, archivo = argv[3:10]
        hilo = argv[10] if len(argv) > 10 else None
        responde = argv[11] if len(argv) > 11 else None
        cuerpo = pathlib.Path(archivo).read_text() if pathlib.Path(archivo).is_file() else archivo
        enviar(root, tipo, de, para, run, feature, task, cuerpo, hilo, responde)
        return 0
    if cmd == "list":
        listar(root, argv[3] if len(argv) > 3 else None)
        return 0
    if cmd == "show":
        return mostrar(root, argv[3])
    if cmd == "close":
        return cerrar(root, argv[3], argv[4])
    print(f"talos: subcomando desconocido: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
