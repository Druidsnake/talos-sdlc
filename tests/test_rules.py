"""Auditoria del registro de reglas.

Criterio 3 de system/00-enforcement.md: la auditoria de mapeo se ejecuta
automaticamente y falla si encuentra un DEBE sin mecanismo.

La parte central de esa auditoria la hace el schema (mecanismo 1): una regla
con mecanismo 9 o 10 y nivel DEBE no valida. Acá se verifica lo que el schema
no puede ver: que las implementaciones citadas existan de verdad.
"""
import json
import pathlib
import sys

import yaml
from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
DUROS = range(1, 6)
MEDIOS = range(6, 9)
BLANDOS = range(9, 11)

MECANISMOS = {
    1: "validacion de schema",
    2: "hook bloqueante pre-accion",
    3: "check de CI",
    4: "git hook",
    5: "proteccion de rama",
    6: "hook post-accion con reversion",
    7: "presencia obligatoria de artefacto",
    8: "aislamiento de permisos",
    9: "inyeccion de contexto por rol",
    10: "instruccion en .md",
}


def fuerza(mecanismo):
    if mecanismo in DUROS:
        return "dura"
    if mecanismo in MEDIOS:
        return "media"
    return "blanda"


def main():
    results = []

    def check(label, ok, detail=""):
        results.append(ok)
        if ok:
            print(f"  ok    {label}")
        else:
            print(f"  FALLA {label}")
            if detail:
                print(f"        {detail}")

    registry = yaml.safe_load((ROOT / "system" / "rules.yaml").read_text())
    schema = json.loads((ROOT / "schemas" / "rules-registry.schema.json").read_text())

    # 1. El registro valida. Aca vive la auditoria del criterio 3.
    errors = list(Draft202012Validator(schema).iter_errors(registry))
    check("system/rules.yaml valida contra rules-registry.schema.json",
          not errors,
          "; ".join(f"{list(e.path)}: {e.message[:80]}" for e in errors[:3]))

    rules = registry.get("rules", [])
    check("el registro no esta vacio", bool(rules))

    # 2. Ids unicos
    ids = [r["id"] for r in rules]
    check("los ids de regla son unicos",
          len(ids) == len(set(ids)),
          f"duplicados: {sorted({i for i in ids if ids.count(i) > 1})}")

    # 3. Ningun DEBE con respaldo blando. Redundante con el schema, a proposito:
    #    si alguien afloja el schema, este check sigue de pie.
    malos = [r["id"] for r in rules
             if r["nivel_normativo"] in ("DEBE", "NO_DEBE")
             and r["mecanismo"] in BLANDOS]
    check("ningun DEBE apoyado solo en mecanismo blando",
          not malos,
          f"reglas mal clasificadas: {malos}")

    # 4. Las implementaciones citadas existen en disco
    for rule in rules:
        if rule["mecanismo"] > 8:
            continue
        faltan = [p for p in rule.get("implementacion", [])
                  if not (ROOT / p).exists()]
        check(f"[{rule['id']}] sus implementaciones existen",
              not faltan,
              f"no existen: {faltan}")

    # 5. Lo no forzable declara al menos una estrategia de guia
    for rule in rules:
        if rule["mecanismo"] in BLANDOS:
            check(f"[{rule['id']}] declara estrategia de guia",
                  bool(rule.get("estrategia_guia")))

    # 6. Toda regla apunta a una fuente
    for rule in rules:
        ref = rule.get("spec_ref", "")
        archivo = ref.split("#")[0]
        check(f"[{rule['id']}] su spec_ref apunta a un archivo existente",
              bool(archivo) and (ROOT / archivo).exists(),
              f"no existe: {archivo}")

    # Reporte de cobertura
    print()
    print("  cobertura por fuerza:")
    for nivel in ("dura", "media", "blanda"):
        n = sum(1 for r in rules if fuerza(r["mecanismo"]) == nivel)
        print(f"    {nivel:7} {n:3} reglas")
    print()
    print("  reglas por mecanismo:")
    for mec in sorted({r["mecanismo"] for r in rules}):
        n = sum(1 for r in rules if r["mecanismo"] == mec)
        print(f"    {mec:2}  {MECANISMOS[mec]:35} {n:3}")

    print()
    ok = sum(1 for r in results if r)
    print(f"{ok}/{len(results)} checks del registro de reglas")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
