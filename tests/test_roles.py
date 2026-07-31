"""Auditoria de coherencia entre config/roles.yaml, roles/*.md y schemas/.

La configuracion puede validar contra su schema y aun asi apuntar a archivos
que no existen. Estos checks detectan esa deriva.
"""
import json
import pathlib
import sys

import yaml
from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"

EXPECTED_ROLES = {"SpecAssistant", "Planner", "FeatureLead", "Developer", "Reviewer"}
VALID_TIERS = {"fast", "balanced", "deep", None}


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def main():
    results = []
    cfg = yaml.safe_load((ROOT / "config" / "roles.yaml").read_text())

    # 1. La config valida contra su propio schema
    schema = json.loads((SCHEMAS / "roles-config.schema.json").read_text())
    errors = list(Draft202012Validator(schema).iter_errors(cfg))
    results.append(check(
        "config/roles.yaml valida contra roles-config.schema.json",
        not errors,
        "; ".join(e.message[:90] for e in errors[:3]),
    ))

    roles = cfg.get("roles", {})

    # 2. Estan exactamente los cinco roles del nucleo 0.0.6
    results.append(check(
        "define exactamente los 5 roles agente de la seccion 18.1",
        set(roles) == EXPECTED_ROLES,
        f"encontrados: {sorted(roles)}",
    ))

    for name, role in sorted(roles.items()):
        # 3. El archivo de instrucciones existe
        instr = role.get("instructions")
        results.append(check(
            f"[{name}] instructions apunta a un archivo existente",
            bool(instr) and (ROOT / instr).is_file(),
            f"no existe: {instr}",
        ))

        # 4. El schema del artefacto de salida existe
        art = role.get("output_artifact")
        if art:
            schema_file = SCHEMAS / f"{art['schema']}.schema.json"
            results.append(check(
                f"[{name}] output_artifact.schema existe: {art['schema']}",
                schema_file.is_file(),
                f"no existe: {schema_file.name}",
            ))

        # 5. El tier minimo pertenece al dominio (null incluido)
        results.append(check(
            f"[{name}] role_minimum_tier en dominio ordenado o null",
            role.get("role_minimum_tier") in VALID_TIERS,
            f"valor invalido: {role.get('role_minimum_tier')!r}",
        ))

        # 6. Declara scope de escritura no vacio
        results.append(check(
            f"[{name}] declara write_paths no vacio",
            bool(role.get("write_paths")),
        ))

        # 7. write_paths y forbidden_paths no se contradicen
        w = set(role.get("write_paths") or [])
        f = set(role.get("forbidden_paths") or [])
        results.append(check(
            f"[{name}] write_paths y forbidden_paths no se solapan",
            not (w & f),
            f"solapan: {sorted(w & f)}",
        ))

    # 8. Separacion de roles: nadie escribe en src/ salvo Developer
    writers_src = [n for n, r in roles.items()
                   if any(p.startswith("src/") for p in (r.get("write_paths") or []))]
    results.append(check(
        "solo Developer escribe en src/",
        writers_src == ["Developer"],
        f"escriben en src/: {writers_src}",
    ))

    # 9. Separacion de roles: nadie escribe en spec/ salvo SpecAssistant
    writers_spec = [n for n, r in roles.items()
                    if any(p.startswith("spec/") for p in (r.get("write_paths") or []))]
    results.append(check(
        "solo SpecAssistant escribe en spec/",
        writers_spec == ["SpecAssistant"],
        f"escriben en spec/: {writers_spec}",
    ))

    # 10. Nadie tiene permiso de merge
    mergers = [n for n, r in roles.items()
               if "pr_merge" not in (r.get("forbidden_tools") or [])
               and "pr_merge" in (r.get("allowed_tools") or [])]
    results.append(check(
        "ningun rol agente puede mergear (MergeGate es codigo, no rol)",
        not mergers,
        f"pueden mergear: {mergers}",
    ))

    # 11. Todo archivo de roles/ esta referenciado por la config
    referenced = {r.get("instructions") for r in roles.values()}
    on_disk = {f"roles/{p.name}" for p in (ROOT / "roles").glob("*.md")
               if p.name != "README.md"}
    results.append(check(
        "no hay archivos huerfanos en roles/",
        on_disk <= referenced,
        f"sin referenciar: {sorted(on_disk - referenced)}",
    ))

    print()
    ok = sum(1 for r in results if r)
    print(f"{ok}/{len(results)} checks de coherencia")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
