#!/usr/bin/env python3
"""Extrae la tabla de transiciones desde la spec y la compila a formato plano.

La spec ES la fuente de verdad. Reescribir la tabla a mano en un YAML aparte
crearia dos versiones que pueden divergir, y la que gobierna la ejecucion no
seria la normativa. Aca se parsean directamente las tablas markdown de las
secciones 22.4 (programa) y 22.5 (feature).

Si alguien edita la spec, se regenera y el checker de deriva lo detecta.
Si alguien edita el archivo generado, el checker de deriva tambien lo detecta.

Salida: hooks/generated/transitions.tsv
Formato: <maquina>\\t<id>\\t<desde>\\t<hacia>\\t<gate>\\t<condicion>\\t<actor>\\t<evidencia>\\t<evento>
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = ROOT / "talos-0.0.7.md"
OUT = ROOT / "hooks" / "generated" / "transitions.tsv"

# Estados terminales, seccion 22.1 y 22.2. Regla 22.6.9: no tienen salida.
TERMINAL_PROGRAM = {"PROGRAM_DONE", "HALTED"}
TERMINAL_FEATURE = {"FEATURE_DONE", "FEATURE_FAILED", "FEATURE_ABANDONED"}


def extract_states(text, heading):
    """Los estados de una maquina salen del bloque txt que sigue al encabezado."""
    start = text.index(heading)
    block = re.search(r"```txt\n(.*?)\n```", text[start:], re.S)
    return [s.strip() for s in block.group(1).split("\n") if s.strip()]


def extract_table(text, heading):
    """Filas de la tabla markdown que sigue al encabezado, sin cabecera ni separador."""
    start = text.index(heading)
    end = text.index("###", start + len(heading))
    rows = []
    for line in text[start:end].split("\n"):
        line = line.strip()
        if not line.startswith("|") or set(line) <= set("|- "):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if cells[0] == "#":
            continue
        rows.append(cells)
    return rows


def clean(cell):
    """Quita el formato markdown: la tabla es prosa normativa, no datos limpios."""
    cell = re.sub(r"`([^`]*)`", r"\1", cell)
    cell = cell.replace("—", "-").strip()
    return cell or "-"


def evidence_list(cell):
    """La columna de evidencia trae tipos con calificadores entre parentesis."""
    cell = clean(cell)
    if cell == "-":
        return "-"
    kinds = []
    for item in cell.split(","):
        item = item.strip()
        if not item:
            continue
        # ProgramPlan, CheckRunSet(all pass), HumanDecision(retry) -> el tipo
        kind = re.match(r"([A-Za-z]+)", item)
        if kind and kind.group(1) not in kinds:
            kinds.append(kind.group(1))
    return ",".join(kinds) if kinds else "-"


def main():
    text = SPEC.read_text()

    prog_states = extract_states(text, "### 22.1. Máquina de programa")
    feat_states = extract_states(text, "### 22.2. Máquina de feature")
    gates = extract_states(text, "### 22.3. Gates")

    lines = [
        "# GENERADO por tools/build-transitions.py - NO EDITAR A MANO",
        "# fuente: talos-0.0.7.md secciones 22.4 y 22.5",
        "# formato: <maquina>\\t<id>\\t<desde>\\t<hacia>\\t<gate>\\t<condicion>\\t<actor>\\t<evidencia>\\t<evento>",
        "# Regla 22.6.1: una transicion debe existir aca para ser permitida.",
        "# Regla 22.6.2: toda transicion no listada se rechaza.",
        "",
    ]

    problems = []
    counts = {}

    for machine, heading, states, terminal in (
        ("program", "### 22.4. Tabla de transiciones — programa", prog_states, TERMINAL_PROGRAM),
        ("feature", "### 22.5. Tabla de transiciones — feature", feat_states, TERMINAL_FEATURE),
    ):
        rows = extract_table(text, heading)
        counts[machine] = len(rows)
        for cells in rows:
            tid, src, dst, gate, actor, ev, event = (cells + ["-"] * 7)[:7]
            tid, src, dst = clean(tid), clean(src), clean(dst)
            gate, actor, event = clean(gate), clean(actor), clean(event)

            # F27 usa "cualquier no terminal" como origen: es un comodin, no
            # un estado. Se preserva tal cual para que el checker lo expanda.
            src_key = "*" if src.startswith("cualquier") else src

            if src_key not in ("-", "*") and src_key not in states:
                problems.append(f"{machine} {tid}: estado origen desconocido: {src}")
            if dst not in states:
                problems.append(f"{machine} {tid}: estado destino desconocido: {dst}")
            if src_key in terminal:
                problems.append(f"{machine} {tid}: sale de un estado terminal (regla 22.6.9)")

            # La columna de gate mezcla el gate con sus condiciones:
            #   "PLAN_GATE=fail, attempts<max"      -> gate + condicion
            #   "READY_GATE + lease otorgado"       -> gate + condicion
            #   "timeout o attempts>=max"           -> condicion sin gate
            # Solo el nombre del gate se valida contra la seccion 22.3.
            found = re.search(r"\b([A-Z_]+_GATE)\b", gate)
            gate_name = found.group(1) if found else "-"
            if gate_name != "-" and gate_name not in gates:
                problems.append(f"{machine} {tid}: gate desconocido: {gate_name}")

            # La condicion es lo que el gate no cubre: intentos, leases,
            # timeouts. El checker de transiciones no la evalua; la registra
            # para que el GateEvaluator sepa que mas tiene que mirar.
            condition = gate if gate_name == "-" else gate.replace(gate_name, "", 1)
            condition = condition.strip(" ,+=") or "-"

            lines.append("\t".join([
                machine, tid, src_key, dst, gate_name, condition,
                actor, evidence_list(ev), event,
            ]))

    if problems:
        for p in problems:
            print(f"  FALLA {p}", file=sys.stderr)
        return 2

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n")

    print(f"escrito {OUT.relative_to(ROOT)}: "
          f"{counts['program']} transiciones de programa, {counts['feature']} de feature, "
          f"{len(prog_states)} + {len(feat_states)} estados, {len(gates)} gates")
    return 0


if __name__ == "__main__":
    sys.exit(main())
