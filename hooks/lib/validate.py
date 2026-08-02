#!/usr/bin/env python3
"""Valida un documento JSON o YAML contra un JSON Schema.

Implementacion de referencia del validador. Se resuelve por cascada desde
hooks/lib/resolve-validator.sh; cualquier otro validador que respete este
contrato puede reemplazarlo.

Uso:  validate.py <schema.json> <documento.json|yaml>
Sale: 0 valido / 1 invalido / 2 error de entrada
"""
import json
import pathlib
import sys


def main(argv):
    if len(argv) != 3:
        print("uso: validate.py <schema> <documento>", file=sys.stderr)
        return 2

    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        print("thalos: falta jsonschema", file=sys.stderr)
        return 2

    schema_path, doc_path = pathlib.Path(argv[1]), pathlib.Path(argv[2])

    try:
        schema = json.loads(schema_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"thalos: no se pudo leer el schema {schema_path}: {exc}", file=sys.stderr)
        return 2

    try:
        raw = doc_path.read_text()
        if doc_path.suffix in (".yaml", ".yml"):
            import yaml
            doc = yaml.safe_load(raw)
        else:
            doc = json.loads(raw)
    except ImportError:
        print("thalos: falta pyyaml para validar YAML", file=sys.stderr)
        return 2
    except (OSError, ValueError) as exc:
        print(f"thalos: no se pudo leer el documento {doc_path}: {exc}", file=sys.stderr)
        return 2

    errors = sorted(Draft202012Validator(schema).iter_errors(doc),
                    key=lambda e: list(e.path))
    for err in errors:
        loc = "/".join(str(p) for p in err.path) or "(raiz)"
        print(f"  {loc}: {err.message}", file=sys.stderr)

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
