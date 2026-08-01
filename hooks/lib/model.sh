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

# talos_role_minimum_tier <rol>
# El piso de capacidad que el rol exige por si mismo (seccion 20.4). Vacio si
# el rol no declara minimo: ahi se resuelve enteramente por esfuerzo y riesgo.
talos_role_minimum_tier() {
    _rm_py=$(talos_python 2>/dev/null) || return 1
    _rm_root="${TALOS_PROJECT_ROOT:-.}"
    _rm_sys="${TALOS_SYSTEM_ROOT:-$_rm_root}"
    for _rm_f in "$_rm_sys/config/roles.yaml" \
                 "$_rm_root/.talos/config/roles.yaml" \
                 "$_rm_root/config/roles.yaml"; do
        [ -f "$_rm_f" ] || continue
        "$_rm_py" - "$_rm_f" "$1" <<'PYEOF' && return 0
import sys
try:
    import yaml
except ImportError:
    raise SystemExit(1)
cfg = yaml.safe_load(open(sys.argv[1]).read()) or {}
r = (cfg.get("roles") or {}).get(sys.argv[2])
if not isinstance(r, dict):
    raise SystemExit(1)
t = r.get("role_minimum_tier")
print(t if t else "")
PYEOF
    done
    return 1
}

# talos_tier_resolve <feature_id> <rol>
#
# Algoritmo de la seccion 20.5:
#
#   candidates = [tier por esfuerzo/riesgo de la feature, minimo del rol]
#   tier = max(los que no son null)      orden total: fast < balanced < deep
#
# max(), no min(): un rol que exige deep no baja porque la feature sea de
# riesgo bajo. La regla 20.5.7 lo dice sin ambiguedad -el routing NO DEBE
# consultar costo-, asi que abaratar por aca seria romperla.
talos_tier_resolve() {
    _tr_feat=$(talos_tier_of_feature "$1" 2>/dev/null || echo "")
    _tr_rol=""
    [ -n "${2:-}" ] && _tr_rol=$(talos_role_minimum_tier "$2" 2>/dev/null || echo "")

    _tr_max=""
    for _tr_c in "$_tr_feat" "$_tr_rol"; do
        [ -n "$_tr_c" ] || continue
        case "$_tr_c" in
            fast) _tr_n=1 ;; balanced) _tr_n=2 ;; deep) _tr_n=3 ;;
            # Fuera del dominio ordenado no participa: la regla 20.5.1 solo
            # permite max() sobre valores del dominio.
            *) continue ;;
        esac
        case "$_tr_max" in
            "")       _tr_max="$_tr_c"; _tr_maxn="$_tr_n" ;;
            *) [ "$_tr_n" -gt "$_tr_maxn" ] && { _tr_max="$_tr_c"; _tr_maxn="$_tr_n"; } ;;
        esac
    done
    [ -n "$_tr_max" ] || return 1
    printf '%s' "$_tr_max"
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
