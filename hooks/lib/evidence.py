#!/usr/bin/env python3
"""Lee, verifica y produce evidencia. Ver talos-0.0.6.md seccion 23.

Existe porque la evidencia NO se puede leer con sed ni grep. Un payload que
contenga la clave "kind" hace que una expresion de linea agarre el valor
equivocado, y ahi una evidencia se hace pasar por otra: exactamente el ataque
que el modelo de evidencia existe para impedir.

FORMULA DEL DIGEST
    La regla 23.3.3 exige que el digest cubra payload y artifact_refs, pero no
    fija la serializacion. Se adopta la misma canonicalizacion que usan los
    adapters para la idempotency key (38.2.4): claves ordenadas, sin espacios.

        digest = "sha256:" + sha256(canonical_json({
            "artifact_refs": <artifact_refs o []>,
            "payload":       <payload o {}>
        }))

    Queda documentado aca porque es una decision de implementacion, no una
    lectura de la spec.

USO
    evidence.py read   <dir>            -> <kind>\\t<verifiable>\\t<digest_ok>\\t<id>
    evidence.py digest <archivo.json>   -> el digest que le corresponde
    evidence.py seal   <archivo.json>   -> reescribe el archivo con su digest
"""
import hashlib
import json
import pathlib
import sys


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))


def expected_digest(doc):
    """Regla 23.3.3: el digest cubre payload y artifact_refs, nada mas."""
    material = canonical({
        "artifact_refs": doc.get("artifact_refs") or [],
        "payload": doc.get("payload") or {},
    })
    return "sha256:" + hashlib.sha256(material.encode()).hexdigest()


def load(path):
    try:
        doc = json.loads(pathlib.Path(path).read_text())
    except (json.JSONDecodeError, OSError):
        return None
    return doc if isinstance(doc, dict) else None


def read_dir(directory):
    """Una linea por evidencia legible. La ilegible se omite: no es evidencia."""
    out = []
    d = pathlib.Path(directory)
    if not d.is_dir():
        return out
    for path in sorted(d.glob("*.json")):
        doc = load(path)
        if doc is None:
            continue
        kind = doc.get("kind")
        if not isinstance(kind, str) or not kind:
            continue

        # Regla 23.3.4: la evidencia verifiable:true tiene que poder
        # revalidarse. Un digest que no cuadra la invalida; no es una
        # evidencia distinta, es una evidencia rota.
        declared = doc.get("digest")
        digest_ok = isinstance(declared, str) and declared == expected_digest(doc)

        verifiable = doc.get("verifiable")
        out.append((
            kind,
            "true" if verifiable is True else "false",
            "true" if digest_ok else "false",
            str(doc.get("id") or path.stem),
        ))
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    cmd, target = argv[1], argv[2]

    if cmd == "read":
        for row in read_dir(target):
            print("\t".join(row))
        return 0

    if cmd == "digest":
        doc = load(target)
        if doc is None:
            print(f"talos: no se pudo leer {target}", file=sys.stderr)
            return 1
        print(expected_digest(doc))
        return 0

    if cmd == "seal":
        path = pathlib.Path(target)
        doc = load(target)
        if doc is None:
            print(f"talos: no se pudo leer {target}", file=sys.stderr)
            return 1
        doc["digest"] = expected_digest(doc)
        path.write_text(json.dumps(doc, ensure_ascii=False) + "\n")
        print(doc["digest"])
        return 0

    print(f"talos: subcomando desconocido: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
