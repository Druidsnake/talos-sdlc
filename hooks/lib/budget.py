#!/usr/bin/env python3
"""Presupuestos. Ver talos-0.0.6.md seccion 33.

LA REGLA QUE GOBIERNA ESTE ARCHIVO ES LA 33.8

    "Si el presupuesto impide usar el tier requerido, Talos DEBE escalar en
     lugar de degradar silenciosamente el modelo."

Y la 33.7:

    "El presupuesto NO DEBE influir en el routing por capacidad; DEBE limitar
     la ejecucion."

La implementacion ingenua hace exactamente lo prohibido: "no me alcanza para
deep, uso balanced". Eso es degradacion silenciosa. El plan pidio deep porque
la feature tiene riesgo, no porque sobrara plata: bajarle el tier resuelve el
numero y rompe la razon.

Aca el presupuesto solo puede hacer dos cosas: dejar seguir, o frenar. Nunca
elegir un modelo distinto.

USO
    budget.py check <raiz> [feature_id]
    budget.py consume <raiz> <feature_id> <cost_usd> <iterations> <wall_minutes>

SALIDA
    0  dentro del presupuesto
    3  excedido: hay que pausar o escalar (regla 33.4)
    4  el presupuesto no alcanza para el tier requerido: escalar (regla 33.8)
"""
import json
import pathlib
import sys

# Orden de capacidad, no de precio. Un tier mas alto no se puede sustituir por
# uno mas bajo aunque salga mas barato: son capacidades distintas (seccion 20.1).
ORDEN_TIER = ["fast", "balanced", "deep"]


def cargar(p, default=None):
    try:
        return json.loads(pathlib.Path(p).read_text())
    except (json.JSONDecodeError, OSError):
        return default


def estado(root, fid):
    return cargar(root / "orchestration" / "features" / fid / "state.json", {}) or {}


def costo_estimado_tier(root, tier, tokens_por_invocacion=100_000):
    """Costo estimado de una invocacion del tier, segun config/models.yaml.

    Lee la estructura que define models-config.schema.json -tiers.<tier> con
    cost_per_mtok_input y cost_per_mtok_output- y no un formato propio. Un
    schema existe para no tener dos verdades sobre la misma cosa.

    Sin ese dato no se inventa un numero: se devuelve None y la asequibilidad
    queda indeterminada, no aprobada.

    tokens_por_invocacion es una estimacion declarada, no una medicion. Sirve
    para comparar contra un presupuesto; el consumo real se registra aparte.
    """
    try:
        import yaml
    except ImportError:
        return None
    for cand in ("config/models.yaml", ".talos/config/models.yaml"):
        f = root / cand
        if not f.is_file():
            continue
        try:
            cfg = yaml.safe_load(f.read_text()) or {}
        except yaml.YAMLError:
            return None
        t = ((cfg.get("tiers") or {}).get(tier) or {})
        ent = t.get("cost_per_mtok_input")
        sal = t.get("cost_per_mtok_output")
        if ent is None and sal is None:
            return None
        # Se asume una salida de un decimo de la entrada: es una estimacion
        # declarada, no una medicion, y esta puesta aca para poder revisarla.
        mtok = tokens_por_invocacion / 1_000_000
        return (ent or 0) * mtok + (sal or 0) * mtok * 0.1
    return None


def evaluar(root, fid=None):
    plan = cargar(root / "orchestration" / "program-plan.json", {}) or {}
    feats = plan.get("features", [])
    if fid:
        feats = [f for f in feats if f.get("id") == fid]

    filas = []
    peor = 0
    for f in feats:
        b = f.get("budget") or {}
        st = estado(root, f["id"])
        c = st.get("budget_consumed") or {}
        tier = f.get("capability_tier")

        limites = {
            "cost_usd": b.get("max_cost_usd"),
            "iterations": b.get("max_iterations"),
            "wall_minutes": b.get("max_wall_minutes"),
        }
        consumido = {
            "cost_usd": c.get("cost_usd", 0),
            "iterations": c.get("iterations", 0),
            "wall_minutes": c.get("wall_minutes", 0),
        }

        excedidos = [k for k, lim in limites.items()
                     if lim is not None and consumido[k] > lim]
        # Estar justo en el limite no es estar dentro: es no tener nada mas.
        # Reportarlo como "ok" hace que quien lea el numero crea que puede
        # seguir, y despues el sistema se planta sin explicacion.
        agotados = [k for k, lim in limites.items()
                    if lim is not None and consumido[k] == lim]

        # Regla 33.8: si el presupuesto no da para el tier que el plan pidio,
        # se ESCALA. No se elige otro tier: el routing por capacidad no se
        # negocia con el presupuesto (regla 33.7).
        tier_asequible = None
        costo = costo_estimado_tier(root, tier) if tier else None
        if costo is not None and limites["cost_usd"] is not None:
            restante = limites["cost_usd"] - consumido["cost_usd"]
            tier_asequible = restante >= costo

        estado_fila = "ok"
        if excedidos:
            estado_fila = "excedido"
            peor = max(peor, 3)
        elif agotados:
            estado_fila = "agotado"
            peor = max(peor, 3)
        elif tier_asequible is False:
            estado_fila = "tier_inasequible"
            peor = max(peor, 4)

        filas.append({
            "feature": f["id"], "tier": tier, "estado": estado_fila,
            "limites": limites, "consumido": consumido,
            "excedidos": excedidos, "agotados": agotados,
            "tier_asequible": tier_asequible,
            "sin_limite": all(v is None for v in limites.values()),
        })

    return filas, peor


def render(filas, peor):
    print("talos")
    print()
    if not filas:
        print("  no hay features con presupuesto declarado")
        print("  Un presupuesto ausente no es un presupuesto infinito: es una")
        print("  decision que nadie tomo. Ver seccion 33.5.")
        return
    print(f"  {'FEATURE':<8} {'TIER':<9} {'ESTADO':<18} CONSUMIDO / LIMITE")
    for r in filas:
        lim, con = r["limites"], r["consumido"]
        def par(k, suf=""):
            l = lim[k]
            return f"{con[k]}{suf}/{l if l is not None else '-'}{suf if l is not None else ''}"
        marca = {"ok": "ok  ", "excedido": "FALL", "agotado": "FALL",
                 "tier_inasequible": "ESC "}[r["estado"]]
        print(f"  {marca} {r['feature']:<7} {str(r['tier'] or '-'):<9} {r['estado']:<18} "
              f"usd {par('cost_usd')}  iter {par('iterations')}  min {par('wall_minutes')}")
        if r["sin_limite"]:
            print("           sin limites declarados")
        for k in r["excedidos"]:
            print(f"           excedido: {k}")
        for k in r.get("agotados", []):
            print(f"           agotado: {k} llego a su limite, no queda margen")
        if r["tier_asequible"] is False:
            print(f"           el saldo no alcanza para el tier {r['tier']}")
            print("           se ESCALA: el tier no se degrada (reglas 33.7 y 33.8)")
    print()
    if peor == 3:
        print("  Presupuesto agotado o excedido. Talos pausa o escala (regla 33.4).")
    elif peor == 4:
        print("  El presupuesto no alcanza para el tier requerido.")
        print("  Escalar es la unica salida: bajar el tier resolveria el numero")
        print("  y romperia la razon por la que el plan lo pidio.")
    else:
        print("  dentro del presupuesto")


def consumir(root, fid, costo, iters, minutos):
    """Regla 33.6: todo consumo de presupuesto DEBE registrarse como evento.

    Aca solo se actualiza la proyeccion; el evento lo emite quien llama, que
    es el unico que sabe en que contexto ocurrio.
    """
    p = root / "orchestration" / "features" / fid / "state.json"
    st = cargar(p, None)
    if st is None:
        return None
    c = st.setdefault("budget_consumed", {})
    c["cost_usd"] = round(c.get("cost_usd", 0) + float(costo), 6)
    c["iterations"] = c.get("iterations", 0) + int(iters)
    c["wall_minutes"] = c.get("wall_minutes", 0) + int(minutos)
    p.write_text(json.dumps(st, indent=2) + "\n")
    return c


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    cmd, root = argv[1], pathlib.Path(argv[2])

    if cmd == "check":
        fid = argv[3] if len(argv) > 3 and not argv[3].startswith("-") else None
        filas, peor = evaluar(root, fid)
        if "--format" in argv and "json" in argv:
            print(json.dumps({"filas": filas, "peor": peor}, indent=2, ensure_ascii=False))
        else:
            render(filas, peor)
        return peor

    if cmd == "consume":
        if len(argv) < 7:
            print("uso: consume <raiz> <feature> <usd> <iter> <min>", file=sys.stderr)
            return 2
        c = consumir(root, argv[3], argv[4], argv[5], argv[6])
        if c is None:
            print(f"talos: {argv[3]} no tiene estado", file=sys.stderr)
            return 2
        print(json.dumps(c))
        _, peor = evaluar(root, argv[3])
        return peor

    print(f"talos: subcomando desconocido: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
