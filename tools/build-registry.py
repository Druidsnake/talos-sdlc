#!/usr/bin/env python3
"""Compila el extension registry a un archivo plano que el nucleo lee sin YAML.

Mismo criterio que tools/build-rules.py: el YAML es la fuente de verdad, pero
parsearlo en el camino caliente obligaria a cada consumidor a tener un runtime
con soporte de YAML. Se compila una vez y el resolver queda en POSIX shell.

Este archivo generado contiene ids de adapters concretos, pero NO viola la
regla 37.4.3.5: es una proyeccion del registry, igual que state.json es una
proyeccion del event log. La regla prohibe que el nucleo *nombre* una
implementacion, no que lea la que el registry declara.

Salida: hooks/generated/capabilities.tsv
Formato: <capacidad>\\t<required|optional>\\t<implementacion|->\\t<dir|->
"""
import pathlib
import sys

try:
    import yaml
except ImportError:
    sys.exit("falta pyyaml: pip install pyyaml")

ROOT = pathlib.Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "config" / "extensions.yaml"
ADAPTERS = ROOT / "adapters"
OUT = ROOT / "hooks" / "generated" / "capabilities.tsv"

# Clasificacion de talos-0.0.6.md 37.4.2. Vive aca y no en el YAML porque es
# normativa del nucleo, no configuracion: el usuario no puede degradar una
# capacidad requerida a opcional editando su config.
REQUIRED = [
    "FileSystemAdapter",
    "ModelProviderAdapter",
    "ExecutionAdapter",
    "CoordinationAdapter",
    "CIAdapter",
]
OPTIONAL = [
    "RoutingStrategy",
    "RoleRegistry",
    "Validator",
    "Reporter",
    "MemoryAdapter",
]


def adapter_index():
    """id declarado en cada manifiesto -> directorio que lo contiene."""
    index = {}
    for manifest in sorted(ADAPTERS.glob("*/adapter.yaml")):
        data = yaml.safe_load(manifest.read_text())
        aid = data.get("id")
        if not aid:
            sys.exit(f"{manifest.relative_to(ROOT)}: sin campo id")
        if aid in index:
            sys.exit(f"id duplicado entre adapters: {aid}")
        index[aid] = manifest.parent.relative_to(ROOT).as_posix()
    return index


def main():
    cfg = yaml.safe_load(REGISTRY.read_text())
    caps = cfg.get("capabilities") or {}
    index = adapter_index()

    lines = [
        "# GENERADO por tools/build-registry.py - NO EDITAR A MANO",
        "# fuente: config/extensions.yaml + adapters/*/adapter.yaml",
        "# formato: <capacidad>\\t<required|optional>\\t<implementacion|->\\t<dir|->",
        "# Cero implementaciones de una capacidad required falla en PRECONDITION_GATE",
        "# (regla 37.4.3.2). Cero de una optional es estado valido (regla 37.4.3.4).",
        "",
    ]

    problems = []
    for cap in REQUIRED + OPTIONAL:
        kind = "required" if cap in REQUIRED else "optional"
        binding = caps.get(cap)
        impl = (binding or {}).get("implementation") if isinstance(binding, dict) else None

        if not impl:
            if kind == "required":
                problems.append(f"{cap}: capacidad REQUERIDA sin implementacion")
            lines.append(f"{cap}\t{kind}\t-\t-")
            continue

        directory = index.get(impl)
        if directory is None:
            problems.append(f"{cap}: la implementacion {impl} no existe bajo adapters/")
            directory = "-"
        lines.append(f"{cap}\t{kind}\t{impl}\t{directory}")

    # La regla 37.4.3.3 -dos o mas implementaciones de la misma capacidad son
    # ambiguedad- ya queda cubierta en dos lugares antes de llegar aca:
    #
    #   - adapter_index() aborta si dos manifiestos declaran el mismo id,
    #   - extension-registry.schema.json admite una sola clave por capacidad,
    #     asi que el registry no puede ligar dos implementaciones a la vez.
    #
    # Tener varios adapters distintos que implementen la misma capacidad NO es
    # ambiguedad: son alternativas disponibles. La ambiguedad seria ligar dos,
    # y eso el schema no lo permite expresar.

    if problems:
        for p in problems:
            print(f"  FALLA {p}", file=sys.stderr)
        return 2

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n")

    bound_n = sum(1 for line in lines if "\t" in line and not line.endswith("\t-\t-"))
    print(f"escrito {OUT.relative_to(ROOT)}: {bound_n} capacidades ligadas, "
          f"{len(REQUIRED)} requeridas, {len(OPTIONAL)} opcionales")
    return 0


if __name__ == "__main__":
    sys.exit(main())
