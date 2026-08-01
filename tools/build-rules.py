#!/usr/bin/env python3
"""Compila config/roles.yaml a un archivo plano que los hooks leen sin dependencias.

El YAML es la fuente de verdad, pero parsearlo en el camino caliente obligaria
a cada hook a tener un runtime con soporte de YAML. Se compila una vez y los
hooks quedan en POSIX shell puro.

Salida: hooks/generated/write-scope.rules
Formato: <rol>\\t<allow|deny>\\t<glob>
"""
import pathlib
import sys

try:
    import yaml
except ImportError:
    sys.exit("falta pyyaml: pip install pyyaml")

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "config" / "roles.yaml"
OUT = ROOT / "hooks" / "generated" / "write-scope.rules"
OUT_ARTIFACTS = ROOT / "hooks" / "generated" / "role-output.tsv"


def main():
    cfg = yaml.safe_load(SRC.read_text())
    lines = [
        "# GENERADO por tools/build-rules.py - NO EDITAR A MANO",
        f"# fuente: config/roles.yaml",
        "# formato: <rol>\\t<allow|deny>\\t<glob>",
        "# deny gana sobre allow. Sin allow que matchee, se deniega (fail-closed).",
        "",
    ]
    for role, spec in sorted(cfg["roles"].items()):
        for glob in spec.get("write_paths") or []:
            lines.append(f"{role}\tallow\t{glob}")
        for glob in spec.get("forbidden_paths") or []:
            lines.append(f"{role}\tdeny\t{glob}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n")

    rules = sum(1 for line in lines if "\t" in line)
    print(f"escrito {OUT.relative_to(ROOT)}: {rules} reglas, {len(cfg['roles'])} roles")

    # Contrato de salida por rol. Sin esto, "el rol entrega X" es una nota en
    # un YAML que nadie consulta al momento de recoger la evidencia.
    art = [
        "# GENERADO por tools/build-rules.py - NO EDITAR A MANO",
        "# fuente: config/roles.yaml (output_artifact)",
        "# formato: <rol>\\t<schema>\\t<plantilla-de-ruta>",
        "# La plantilla admite {feature_id} y {task_id}.",
        "",
    ]
    n_art = 0
    for role, spec in sorted(cfg["roles"].items()):
        oa = spec.get("output_artifact")
        if not oa:
            continue
        art.append(f"{role}\t{oa['schema']}\t{oa['path']}")
        n_art += 1
    OUT_ARTIFACTS.write_text("\n".join(art) + "\n")
    print(f"escrito {OUT_ARTIFACTS.relative_to(ROOT)}: {n_art} contratos de salida")
    return 0


if __name__ == "__main__":
    sys.exit(main())
