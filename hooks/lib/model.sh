#!/bin/sh
# Resolucion capability_tier -> modelo concreto. Ver talos-0.0.6.md 20.3.
#
# El nucleo NO conoce identificadores de modelo: conoce tiers. La unica fuente
# de la traduccion es config/models.yaml, igual que config/extensions.yaml es
# la unica fuente de capacidad -> adapter. Leer esa tabla no es conocer un
# modelo, del mismo modo que el resolvedor de capacidades no "conoce" adapters
# por leer capabilities.tsv.
#
# El TIER lo elige el plan por el RIESGO de la feature. Esta capa solo
# traduce; no decide, no abarata y no sustituye un tier por otro (reglas 33.7
# y 33.8).
#
# Uso:  . hooks/lib/model.sh
#       talos_model_for_tier fast     -> "<modelo>\t<proveedor>"
#       talos_tier_of_feature F001    -> "fast"

# talos_model_for_tier <tier>
# Emite "<modelo>\t<proveedor>". Sale 1 si no hay tabla o el tier no esta.
talos_model_for_tier() {
    _mt_py=$(talos_python 2>/dev/null) || return 1
    _mt_root="${TALOS_PROJECT_ROOT:-.}"
    _mt_sys="${TALOS_SYSTEM_ROOT:-$_mt_root}"
    for _mt_f in "$_mt_root/config/models.yaml" \
                 "$_mt_root/.talos/config/models.yaml" \
                 "$_mt_sys/config/models.yaml"; do
        [ -f "$_mt_f" ] || continue
        "$_mt_py" - "$_mt_f" "$1" <<'PYEOF' && return 0
import sys
try:
    import yaml
except ImportError:
    raise SystemExit(1)
try:
    cfg = yaml.safe_load(open(sys.argv[1]).read()) or {}
except yaml.YAMLError:
    raise SystemExit(1)
t = (cfg.get("tiers") or {}).get(sys.argv[2])
if not isinstance(t, dict) or not t.get("model"):
    raise SystemExit(1)
print(f"{t['model']}\t{t.get('provider', '')}")
PYEOF
    done
    return 1
}

# talos_tier_of_feature <feature_id>
# El tier que el PLAN le puso a la feature. Sin plan o sin feature, sale 1: no
# se inventa un tier, porque inventarlo es elegir capacidad por defecto en vez
# de por riesgo.
talos_tier_of_feature() {
    _tf_py=$(talos_python 2>/dev/null) || return 1
    _tf_plan="${TALOS_PROJECT_ROOT:-.}/orchestration/program-plan.json"
    [ -f "$_tf_plan" ] || return 1
    "$_tf_py" - "$_tf_plan" "$1" <<'PYEOF'
import json, sys
plan = json.loads(open(sys.argv[1]).read())
f = next((x for x in plan.get("features", []) if x.get("id") == sys.argv[2]), None)
if not f or not f.get("capability_tier"):
    raise SystemExit(1)
print(f["capability_tier"])
PYEOF
}
