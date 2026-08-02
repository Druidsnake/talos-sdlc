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

# Cadena de resolucion de la seccion 43.3: los defaults del sistema primero, el
# override del proyecto despues. Estaba definida y no la implementaba nadie
# para el alcance de escritura, y el alcance de escritura es JUSTO lo que
# depende del proyecto: "donde vive el codigo" es una propiedad del layout, no
# de Thalos. Un Developer con write_paths src/** y tests/** no puede tocar
# app/ en un Next.js, y el sistema le pedia igual que implementara la pagina.
def raiz_proyecto():
    import os
    env = os.environ.get("THALOS_PROJECT_ROOT")
    if env:
        return pathlib.Path(env)
    # Vendoreado: ROOT es .thalos/ y el proyecto es su padre.
    return ROOT.parent if ROOT.name == ".thalos" else ROOT


OVERRIDES = raiz_proyecto() / "thalos.config" / "overrides.yaml"
OUT = ROOT / "hooks" / "generated" / "write-scope.rules"
OUT_ARTIFACTS = ROOT / "hooks" / "generated" / "role-output.tsv"


def aplicar_overrides(cfg):
    """Suma los write_paths que declare el proyecto. Devuelve (cfg, fuente).

    Regla 43.4.5: un override de proyecto NO PUEDE relajar una restriccion de
    policy. Aca eso significa que solo puede AGREGAR rutas permitidas: los
    forbidden_paths del sistema sobreviven intactos y siguen ganando, porque
    deny gana sobre allow. Un proyecto puede decir donde vive su codigo; no
    puede autorizarse a tocar spec/, .thalos/ ni la evidencia.
    """
    if not OVERRIDES.is_file():
        return cfg, "config/roles.yaml"
    try:
        ov = yaml.safe_load(OVERRIDES.read_text()) or {}
    except yaml.YAMLError as e:
        sys.exit(f"thalos.config/overrides.yaml no es YAML valido: {e}")

    roles_ov = (ov.get("roles") or {})
    tocados = []
    for role, spec in roles_ov.items():
        if role not in cfg["roles"]:
            sys.exit(f"thalos.config/overrides.yaml nombra un rol que no existe: {role}")
        # Se mira la CLAVE, no su contenido: forbidden_paths: [] es una lista
        # vacia -falsy- y era justo el intento de relajacion que se colaba.
        if "forbidden_paths" in (spec or {}):
            sys.exit(f"thalos.config/overrides.yaml intenta cambiar forbidden_paths de {role}: "
                     "un override no puede relajar una restriccion (regla 43.4.5)")
        extra = spec.get("write_paths") or []
        if not extra:
            continue
        # Se agregan, no se reemplazan: quitar un allow del sistema no es
        # ampliar el alcance, es otra cosa, y para eso esta el rol.
        actuales = cfg["roles"][role].get("write_paths") or []
        cfg["roles"][role]["write_paths"] = actuales + [g for g in extra if g not in actuales]
        tocados.append(role)
    if tocados:
        print(f"overrides del proyecto aplicados a: {', '.join(sorted(tocados))}")
    return cfg, "config/roles.yaml + thalos.config/overrides.yaml"


def main():
    cfg = yaml.safe_load(SRC.read_text())
    cfg, fuente = aplicar_overrides(cfg)
    lines = [
        "# GENERADO por tools/build-rules.py - NO EDITAR A MANO",
        f"# fuente: {fuente}",
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
