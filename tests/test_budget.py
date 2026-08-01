"""Auditoria de presupuestos. Ver talos-0.0.6.md seccion 33.

La regla que gobierna estos checks es la 33.8: si el presupuesto impide usar el
tier requerido, Talos DEBE escalar en lugar de degradar silenciosamente el
modelo. La implementacion ingenua hace lo prohibido -"no me alcanza para deep,
uso balanced"- y eso no se detecta mirando el resultado: el numero cierra.
"""
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "hooks" / "lib"))
import budget as b  # noqa: E402


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def proyecto(features, consumos=None, costos=None):
    d = pathlib.Path(tempfile.mkdtemp())
    (d / "orchestration").mkdir()
    (d / "orchestration" / "program-plan.json").write_text(json.dumps({
        "schema_version": 1, "project": "t", "spec_digest": "sha256:" + "c" * 64,
        "created_by": "role:Planner", "created_at": "2026-08-01T00:00:00Z",
        "features": features}))
    for fid, c in (consumos or {}).items():
        fd = d / "orchestration" / "features" / fid
        fd.mkdir(parents=True)
        (fd / "state.json").write_text(json.dumps({
            "schema_version": 1, "feature_id": fid, "state": "FEATURE_IN_PROGRESS",
            "last_event_seq": 0, "updated_at": "2026-08-01T00:00:00Z",
            "budget_consumed": c}))
    if costos:
        # Formato de models-config.schema.json, no uno propio. El costo por
        # invocacion sale de cost_per_mtok_* y de la estimacion de tokens que
        # declara budget.py, no de un numero suelto.
        (d / "config").mkdir(exist_ok=True)
        lineas = ["version: 1", "tiers:"]
        for tier, mtok_in in costos.items():
            lineas += [f"  {tier}:", f"    model: modelo-{tier}",
                       f"    cost_per_mtok_input: {mtok_in}",
                       f"    cost_per_mtok_output: 0"]
        (d / "config" / "models.yaml").write_text("\n".join(lineas) + "\n")
    return d


def feat(fid, tier="fast", budget=None, **kw):
    f = {"id": fid, "title": fid, "effort": "medium", "risk": "low",
         "capability_tier": tier, "human_approval_required": False,
         "depends_on": []}
    if budget:
        f["budget"] = budget
    f.update(kw)
    return f


def main():
    results = []

    # ---------- lo que el presupuesto NO puede hacer ----------

    src = (ROOT / "hooks" / "lib" / "budget.py").read_text()
    results.append(check(
        "el presupuesto no elige tier: no hay sustitucion por uno mas barato",
        "ORDEN_TIER" in src and "capacidades distintas" in src,
        "un tier mas alto no se sustituye por uno mas bajo aunque salga mas barato"))
    results.append(check(
        "el modulo nombra explicitamente la regla 33.8",
        "33.8" in src and "degradar silenciosamente" in src))

    # El costo sale del schema, no de un formato inventado. Tener dos verdades
    # sobre la misma cosa es como empiezan a divergir.
    results.append(check(
        "el costo se lee del formato de models-config.schema.json",
        "cost_per_mtok_input" in src and "_cost_usd:" not in src,
        "un schema existe para no tener dos verdades sobre la misma cosa"))

    # Ningun camino del codigo devuelve un tier distinto del pedido.
    results.append(check(
        "ninguna funcion devuelve un tier alternativo",
        "return tier" not in src and "tier_sugerido" not in src
        and "downgrade" not in src.lower()))

    # ---------- dentro y fuera de limite ----------

    p = proyecto([feat("F001", budget={"max_cost_usd": 5.0, "max_iterations": 3})],
                 {"F001": {"cost_usd": 1.0, "iterations": 1, "wall_minutes": 2}})
    filas, peor = b.evaluar(p)
    results.append(check("dentro del limite no frena nada", peor == 0, f"peor={peor}"))

    p = proyecto([feat("F001", budget={"max_cost_usd": 5.0, "max_iterations": 3})],
                 {"F001": {"cost_usd": 9.0, "iterations": 1, "wall_minutes": 2}})
    filas, peor = b.evaluar(p)
    results.append(check("un costo excedido frena (regla 33.4)",
                         peor == 3 and "cost_usd" in filas[0]["excedidos"], f"{filas}"))

    p = proyecto([feat("F001", budget={"max_cost_usd": 5.0, "max_iterations": 3})],
                 {"F001": {"cost_usd": 1.0, "iterations": 9, "wall_minutes": 2}})
    filas, peor = b.evaluar(p)
    results.append(check("las iteraciones tambien cuentan (regla 33.3)",
                         peor == 3 and "iterations" in filas[0]["excedidos"]))

    # ---------- el caso 33.8 ----------
    #
    # Dentro del limite total, pero sin saldo para UNA invocacion del tier que
    # el plan pidio. La respuesta correcta es escalar, no bajar el tier.

    p = proyecto([feat("F002", tier="deep", budget={"max_cost_usd": 1.0})],
                 {"F002": {"cost_usd": 0.0, "iterations": 0, "wall_minutes": 0}},
                 costos={"deep": 15.0, "balanced": 4.0, "fast": 0.5})
    filas, peor = b.evaluar(p)
    results.append(check(
        "sin saldo para el tier requerido, escala (regla 33.8)",
        peor == 4 and filas[0]["estado"] == "tier_inasequible", f"{filas}"))
    results.append(check(
        "y NO reporta un tier alternativo aunque balanced entrase en el saldo",
        filas[0]["tier"] == "deep" and "sugerido" not in json.dumps(filas),
        f"{filas[0]}"))

    # Con saldo suficiente para el tier pedido, sigue.
    p = proyecto([feat("F002", tier="deep", budget={"max_cost_usd": 5.0})],
                 {"F002": {"cost_usd": 0.0, "iterations": 0, "wall_minutes": 0}},
                 costos={"deep": 15.0})
    filas, peor = b.evaluar(p)
    results.append(check("con saldo para el tier pedido, no frena",
                         peor == 0 and filas[0]["tier_asequible"] is True))

    # Sin costos declarados no se inventa un numero.
    p = proyecto([feat("F002", tier="deep", budget={"max_cost_usd": 0.01})],
                 {"F002": {"cost_usd": 0.0, "iterations": 0, "wall_minutes": 0}})
    filas, peor = b.evaluar(p)
    results.append(check(
        "sin costos declarados la asequibilidad queda indeterminada, no aprobada",
        filas[0]["tier_asequible"] is None and peor == 0,
        f"{filas[0]}"))

    # ---------- ausencia de limite ----------

    p = proyecto([feat("F003")], {"F003": {"cost_usd": 999, "iterations": 99, "wall_minutes": 999}})
    filas, peor = b.evaluar(p)
    results.append(check(
        "sin limites declarados no se frena, pero se marca la ausencia",
        peor == 0 and filas[0]["sin_limite"], f"{filas[0]}"))
    results.append(check(
        "y el reporte dice que un presupuesto ausente es una decision que nadie tomo",
        "decision que nadie tomo" in src))

    # ---------- consumo acumulativo ----------

    p = proyecto([feat("F001", budget={"max_cost_usd": 5.0})],
                 {"F001": {"cost_usd": 0, "iterations": 0, "wall_minutes": 0}})
    b.consumir(p, "F001", 1.5, 1, 10)
    c = b.consumir(p, "F001", 2.0, 2, 5)
    results.append(check("el consumo se acumula, no se pisa",
                         c["cost_usd"] == 3.5 and c["iterations"] == 3
                         and c["wall_minutes"] == 15, f"{c}"))

    # ---------- el loop respeta el presupuesto ----------

    run_src = (ROOT / "cli" / "commands" / "run.sh").read_text()
    # Se compara contra el bucle PRINCIPAL, no contra cualquier `while [`: el
    # de parseo de argumentos aparece antes y hacia pasar la comparacion sin
    # probar nada.
    bucle = run_src.index('while [ "$paso" -lt')
    llamada = run_src.index("if ! presupuesto_ok")
    results.append(check(
        "el loop verifica el presupuesto DENTRO del bucle, no solo al arrancar",
        llamada > bucle,
        "el loop es justamente lo que puede gastar sin que nadie mire"))
    results.append(check(
        "y frena en vez de seguir (regla 33.4)",
        "el loop pausa (regla 33.4)" in run_src))
    results.append(check(
        "ante tier inasequible el loop escala, no baja el tier",
        "Bajar el tier no es una opcion" in run_src))

    # ---------- el consumo deja evento ----------

    cmd = (ROOT / "cli" / "commands" / "budget.sh").read_text()
    results.append(check(
        "todo consumo se registra como evento (regla 33.6)",
        "talos.budget.consumed" in cmd,
        "sin evento el gasto no es reconstruible desde el event log"))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks de presupuestos")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
