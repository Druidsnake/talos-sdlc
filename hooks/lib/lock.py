#!/usr/bin/env python3
"""LockManager: leases con TTL y fencing token. Ver thalos-0.0.7.md seccion 32.

Un lock es un lease: una concesion con expiracion. La correccion respecto de
0.0.4 es justamente esta: sin expiracion, un proceso que muere deja el recurso
bloqueado para siempre.

`generation` ES el fencing token (32.3). Se incrementa cada vez que un lease
expira, para que un propietario zombi no pueda completar una operacion despues
de haber perdido el lease.

USO
    lock.py acquire <locks.json> <recurso> <feature> <run> <razon> [ttl]
    lock.py release <locks.json> <lease_id>
    lock.py heartbeat <locks.json> <lease_id>
    lock.py list <locks.json>
    lock.py expire <locks.json>          barre los vencidos y sube generation

SALIDA
    0  ok
    1  el recurso esta tomado por otro (hay que serializar)
    2  error de uso
"""
import datetime
import json
import pathlib
import sys

DEFAULT_TTL = 300


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse(ts):
    return datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=datetime.timezone.utc)


def load(path):
    p = pathlib.Path(path)
    if not p.is_file():
        return {"schema_version": 1, "leases": []}
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return {"schema_version": 1, "leases": []}


def save(path, doc):
    pathlib.Path(path).write_text(json.dumps(doc, indent=2) + "\n")


def sweep(doc):
    """Regla 32.2.5 y 32.2.6: al vencer, el lease cae y generation sube.

    La generation vencida se conserva por recurso para que el siguiente lease
    arranque por encima: es lo que impide que un propietario zombi con el token
    viejo complete una operacion.
    """
    vivos, vencidos = [], []
    t = now()
    for lease in doc.get("leases", []):
        if parse(lease["expires_at"]) <= t:
            vencidos.append(lease)
        else:
            vivos.append(lease)
    doc["leases"] = vivos
    if vencidos:
        gens = doc.setdefault("_expired_generations", {})
        for lease in vencidos:
            r = lease["resource"]
            gens[r] = max(gens.get(r, 0), lease["generation"]) + 1
    return vencidos


def next_generation(doc, resource):
    return max(doc.get("_expired_generations", {}).get(resource, 0), 0) + 1


def acquire(path, resource, feature, run, reason, ttl=DEFAULT_TTL):
    doc = load(path)
    expirados = sweep(doc)

    for lease in doc["leases"]:
        if lease["resource"] != resource:
            continue
        # La regla 32.4.1 habla de DOS features compitiendo. Una feature en
        # conflicto consigo misma no es eso: es la misma corrida reintentando.
        # Sin esta excepcion, un reintento tras una caida deja a la feature
        # afuera de su propio recurso hasta que venza el TTL.
        if lease["owner_feature"] == feature and lease["owner_run"] == run:
            save(path, doc)
            return lease, expirados, None
        # Distinto duenio, o la misma feature en otra corrida: ahi si se
        # serializa. Una corrida anterior puede seguir viva, y el fencing token
        # existe justamente porque no se puede saber desde aca.
        save(path, doc)
        return None, expirados, lease

    t = now()
    lease = {
        "lease_id": f"lk-{feature}-{t.strftime('%Y%m%d%H%M%S')}",
        "resource": resource,
        "owner_feature": feature,
        "owner_run": run,
        "reason": reason,
        "acquired_at": iso(t),
        "expires_at": iso(t + datetime.timedelta(seconds=ttl)),
        "last_heartbeat_at": iso(t),
        "ttl_seconds": ttl,
        "generation": next_generation(doc, resource),
    }
    doc["leases"].append(lease)
    save(path, doc)
    return lease, expirados, None


def release(path, lease_id):
    doc = load(path)
    antes = len(doc["leases"])
    doc["leases"] = [x for x in doc["leases"] if x["lease_id"] != lease_id]
    save(path, doc)
    return antes != len(doc["leases"])


def heartbeat(path, lease_id):
    """Regla 32.2.4: el heartbeat extiende expires_at."""
    doc = load(path)
    sweep(doc)
    for lease in doc["leases"]:
        if lease["lease_id"] == lease_id:
            t = now()
            lease["last_heartbeat_at"] = iso(t)
            lease["expires_at"] = iso(
                t + datetime.timedelta(seconds=lease["ttl_seconds"]))
            save(path, doc)
            return lease
    save(path, doc)
    return None


def clean_for_schema(doc):
    """locks.schema.json no admite propiedades extra."""
    return {"schema_version": doc.get("schema_version", 1),
            "leases": doc.get("leases", [])}


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    cmd, path = argv[1], argv[2]

    if cmd == "acquire":
        if len(argv) < 7:
            print("uso: acquire <locks> <recurso> <feature> <run> <razon> [ttl]",
                  file=sys.stderr)
            return 2
        ttl = int(argv[7]) if len(argv) > 7 else DEFAULT_TTL
        lease, expirados, conflicto = acquire(
            path, argv[3], argv[4], argv[5], argv[6], ttl)
        for e in expirados:
            print(f"EXPIRED\t{e['lease_id']}\t{e['resource']}", file=sys.stderr)
        if conflicto:
            print(f"CONFLICT\t{conflicto['resource']}\t{conflicto['owner_feature']}"
                  f"\t{conflicto['expires_at']}", file=sys.stderr)
            return 1
        print(json.dumps(lease))
        return 0

    if cmd == "release":
        return 0 if release(path, argv[3]) else 1

    if cmd == "heartbeat":
        lease = heartbeat(path, argv[3])
        if lease is None:
            return 1
        print(json.dumps(lease))
        return 0

    if cmd == "expire":
        doc = load(path)
        for e in sweep(doc):
            print(f"{e['lease_id']}\t{e['resource']}\t{e['owner_feature']}")
        save(path, doc)
        return 0

    if cmd == "list":
        doc = load(path)
        sweep(doc)
        save(path, doc)
        for x in doc["leases"]:
            print(f"{x['lease_id']}\t{x['resource']}\t{x['owner_feature']}"
                  f"\t{x['expires_at']}\t{x['generation']}")
        return 0

    print(f"thalos: subcomando desconocido: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
