#!/usr/bin/env python3
"""PLAN_GATE: analiza un ProgramPlan. Ver thalos-0.0.7.md seccion 29.

Es una funcion pura de (plan, spec aprobado, config). No invoca modelos: la
regla 24.4.3 lo prohibe. Generar el plan es trabajo del Planner, que es un rol
agente; verificarlo es trabajo del gate, que es codigo.

Emite una razon por condicion evaluada, en el formato de la seccion 24.2:

    <code>\\t<pass|fail|skip>\\t<detalle>

USO
    plan.py check <plan.json> [manifest-del-spec.yaml]

SALIDA
    0  el plan pasa PLAN_GATE
    3  el plan lo falla
"""
import json
import pathlib
import sys

# Regla 29.6 mas la politica de aprobacion humana (secciones 36.5 y 47): un
# riesgo critical no puede avanzar sin humano. El plan que diga lo contrario
# esta incoherente consigo mismo.
RISK_REQUIRING_HUMAN = {"critical"}

# Riesgos que la seccion 20.1 espera que suban de tier. Un feature critical con
# tier fast es una contradiccion: el routing por capacidad no lo permite.
MIN_TIER_BY_RISK = {"critical": {"deep"}, "high": {"balanced", "deep"}}


def reason(code, status, detail=""):
    return (code, status, detail)


def find_cycles(features):
    """Regla 29.9: el grafo DEBE ser aciclico. Devuelve el primer ciclo."""
    graph = {f["id"]: list(f.get("depends_on") or []) for f in features}
    WHITE, GREY, BLACK = 0, 1, 2
    color = {n: WHITE for n in graph}
    stack = []

    def visit(node):
        color[node] = GREY
        stack.append(node)
        for dep in graph.get(node, []):
            if dep not in color:
                continue
            if color[dep] == GREY:
                return stack[stack.index(dep):] + [dep]
            if color[dep] == WHITE:
                found = visit(dep)
                if found:
                    return found
        color[node] = BLACK
        stack.pop()
        return None

    for node in graph:
        if color[node] == WHITE:
            found = visit(node)
            if found:
                return found
    return None


def spec_digest_of(manifest_path):
    """El digest que el manifest del spec declara, si esta aprobado."""
    if not manifest_path or not pathlib.Path(manifest_path).is_file():
        return None, None
    text = pathlib.Path(manifest_path).read_text()
    status = digest = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("status:"):
            status = line.split(":", 1)[1].strip().strip('"\'')
        elif line.startswith("digest:"):
            digest = line.split(":", 1)[1].strip().strip('"\'')
    return status, digest


def evaluate(plan, manifest_path=None):
    reasons = []
    features = plan.get("features") or []

    # Regla 29.1: el Planner solo corre tras SPEC_APPROVED. El plan queda
    # atado al digest del spec que lo origino; si el spec cambio, el plan
    # planifica sobre algo que ya no existe.
    status, digest = spec_digest_of(manifest_path)
    if manifest_path is None:
        reasons.append(reason("SPEC_LINK", "skip", "sin manifest para comparar"))
    elif status is None:
        reasons.append(reason("SPEC_LINK", "fail", "no se pudo leer el manifest del spec"))
    elif status != "approved":
        reasons.append(reason("SPEC_APPROVED", "fail", f"el spec esta en {status}, no approved"))
    else:
        reasons.append(reason("SPEC_APPROVED", "pass", "approved"))
        if digest and plan.get("spec_digest") == digest:
            reasons.append(reason("SPEC_DIGEST_MATCH", "pass", digest[:23] + "..."))
        else:
            reasons.append(reason(
                "SPEC_DIGEST_MATCH", "fail",
                "el plan no apunta al digest del spec aprobado"))

    # Ids unicos: dos features con el mismo id hacen ambiguo todo lo demas.
    ids = [f.get("id") for f in features]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    reasons.append(reason(
        "UNIQUE_FEATURE_IDS", "fail" if dupes else "pass",
        f"duplicados: {dupes}" if dupes else f"{len(ids)} features"))

    # Toda dependencia tiene que existir. Una dependencia colgada bloquea la
    # feature para siempre sin decir por que.
    known = set(ids)
    dangling = sorted({
        f"{f['id']}->{d}" for f in features
        for d in (f.get("depends_on") or []) if d not in known
    })
    reasons.append(reason(
        "DEPENDENCIES_RESOLVABLE", "fail" if dangling else "pass",
        f"sin destino: {dangling}" if dangling else "-"))

    # Regla 29.9: grafo aciclico.
    cycle = find_cycles(features) if not dangling else None
    if dangling:
        reasons.append(reason("ACYCLIC_GRAPH", "skip", "hay dependencias colgadas"))
    elif cycle:
        reasons.append(reason("ACYCLIC_GRAPH", "fail", " -> ".join(cycle)))
    else:
        reasons.append(reason("ACYCLIC_GRAPH", "pass", "sin ciclos"))

    # Una feature que depende de si misma es un ciclo de largo 1; el detector
    # lo cubre, pero conviene nombrarlo aparte porque suele ser un tipeo.
    self_dep = sorted({f["id"] for f in features
                       if f["id"] in (f.get("depends_on") or [])})
    if self_dep:
        reasons.append(reason("NO_SELF_DEPENDENCY", "fail", f"{self_dep}"))

    # Regla 29.6 + politica: riesgo critical exige aprobacion humana.
    sin_humano = sorted({
        f["id"] for f in features
        if f.get("risk") in RISK_REQUIRING_HUMAN
        and not f.get("human_approval_required")})
    reasons.append(reason(
        "CRITICAL_REQUIRES_HUMAN", "fail" if sin_humano else "pass",
        f"critical sin aprobacion humana: {sin_humano}" if sin_humano
        else "-"))

    # Regla 29.7 + seccion 20.1: el tier tiene que ser coherente con el riesgo.
    mal_tier = sorted({
        f"{f['id']}({f.get('risk')}/{f.get('capability_tier')})"
        for f in features
        if f.get("risk") in MIN_TIER_BY_RISK
        and f.get("capability_tier") not in MIN_TIER_BY_RISK[f["risk"]]})
    reasons.append(reason(
        "TIER_MATCHES_RISK", "fail" if mal_tier else "pass",
        f"tier insuficiente: {mal_tier}" if mal_tier else "-"))

    # Un plan sin ninguna feature ejecutable de entrada no arranca nunca.
    raiz = [f["id"] for f in features if not (f.get("depends_on") or [])]
    reasons.append(reason(
        "HAS_ENTRY_POINT", "pass" if raiz else "fail",
        f"features sin dependencias: {raiz}" if raiz
        else "toda feature depende de otra: el plan no puede empezar"))

    decision = "fail" if any(s == "fail" for _, s, _ in reasons) else "pass"
    return decision, reasons


def main(argv):
    if len(argv) < 3 or argv[1] != "check":
        print(__doc__.strip(), file=sys.stderr)
        return 2

    try:
        plan = json.loads(pathlib.Path(argv[2]).read_text())
    except (json.JSONDecodeError, OSError) as exc:
        print(f"PLAN_READABLE\tfail\t{exc}")
        return 3

    manifest = argv[3] if len(argv) > 3 else None
    decision, reasons = evaluate(plan, manifest)
    for code, status, detail in reasons:
        print(f"{code}\t{status}\t{detail}")
    return 0 if decision == "pass" else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
