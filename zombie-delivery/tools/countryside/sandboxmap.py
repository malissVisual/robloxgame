#!/usr/bin/env python3
"""The countryside (design/countryside/plan.py): design/countryside/plan.json as shared/SandboxMap.luau's map section, the
data the game builds. Nothing in the game reads plan.json: this writes it into the module once, as a Luau table, between
the lines "-- BEGIN COUNTRYSIDE" and "-- END COUNTRYSIDE" of src/shared/SandboxMap.luau (the rest of the module, its
Houses among it, is left as it is). Deterministic: the same plan, the same lines.

    python3 zombie-delivery/tools/countryside/sandboxmap.py [--check]

--check writes nothing and fails when the section is not what the plan gives (tests/run_tests.py runs it that way).

What it writes:
  Bounds      plan.bounds
  Roads       Pražská and Depot Row first, as SandboxMap always had them (read by name and by number; Pražská from
              Depot Row's north edge, z -74: the junction is Depot Row's asphalt), then the plan's lanes in its order
              (a lane's rects share its name; yard = true for a spot's turning yard at its end); lane = true for a
              road narrower than a main road and for a yard (its lane's)
  Landmarks   plan.landmarks: id, name, kind, rect, yaw (the way its front looks)
  Fields      plan.fields (the plan keeps them off every road, spot, lot and landmark; none over another or a plot)
  Lawns       plan.lawns: ground tiles of their own (kind, rect): the forest's floor
  TreeLines   plan.treeLines: windbreaks and fruit alleys (trees), hedges and fences
  Woods       plan.woods: a wood's rect (its trees on a jittered grid) and its clearings (no tree)
  Orchard     plan.orchard: the orchard's rect (its fruit trees in rows)
  Streams     plan.streams: a stream's water `width` wide along its middle line's points
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
PLAN = os.path.join(GAME, "design", "countryside", "plan.json")
TARGET = os.path.join(GAME, "src", "shared", "SandboxMap.luau")
BEGIN, END = "-- BEGIN COUNTRYSIDE", "-- END COUNTRYSIDE"

FIXED_ORDER = ["Pražská", "Depot Row"]  # Roads[1], Roads[2], as they always were
MAIN_WIDTH = 28  # a road this wide is a main road (Depot Row, Pražská); the narrower ones are lanes


def num(v):
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    return repr(v)


def rect_text(r):
    return f"x0 = {num(r['x0'])}, x1 = {num(r['x1'])}, z0 = {num(r['z0'])}, z1 = {num(r['z1'])}"


def q(text):
    return json.dumps(text, ensure_ascii=False)


def overlap(a, b):
    return a["x0"] < b["x1"] and b["x0"] < a["x1"] and a["z0"] < b["z1"] and b["z0"] < a["z1"]


def points_text(points):
    return ", ".join(f"{{ x = {num(p['x'])}, z = {num(p['z'])} }}" for p in points)


def section(plan):
    lines = [BEGIN + " (tools/countryside/sandboxmap.py writes these lines from design/countryside/plan.json: do not edit them)"]
    lines.append(f"SandboxMap.Bounds = {{ {rect_text(plan['bounds'])} }} :: Rect")

    # the roads: Pražská and Depot Row first, then the lanes in the plan's order
    roads = sorted([r for r in plan["roads"] if r["name"] in FIXED_ORDER], key=lambda r: FIXED_ORDER.index(r["name"]))
    roads += [r for r in plan["roads"] if r["name"] not in FIXED_ORDER]
    if [r["name"] for r in roads[:2]] != FIXED_ORDER:
        raise SystemExit("sandboxmap: the plan has no Pražská or no Depot Row")
    lines.append("SandboxMap.Roads = {")
    for road in roads:
        r = road["rect"]
        lane = road["yard"] or min(r["x1"] - r["x0"], r["z1"] - r["z0"]) < MAIN_WIDTH  # (a yard: its lane's)
        lines.append(f"\t{{ name = {q(road['name'])}, {rect_text(r)}, lane = {'true' if lane else 'false'}, yard = {'true' if road['yard'] else 'false'} }},")
    lines.append("} :: { Road }")

    lines.append("SandboxMap.Landmarks = {")
    for l in plan["landmarks"]:
        lines.append(f"\t{{ id = {q(l['id'])}, name = {q(l['name'])}, kind = {q(l['kind'])}, {rect_text(l['rect'])}, yaw = {num(l['yaw'])} }},")
    lines.append("} :: { Landmark }")

    fixed = [p["rect"] for p in plan["plots"]] + [s["lot"] for s in plan["spots"] if s.get("fixed")]
    lines.append("SandboxMap.Fields = {")
    for n, f in enumerate(plan["fields"]):
        for block in fixed:
            if overlap(f["rect"], block):
                raise SystemExit(f"sandboxmap: field {n + 1} on a plot or the farmstead's lot")
        for m, g in enumerate(plan["fields"]):
            if m > n and overlap(f["rect"], g["rect"]):
                raise SystemExit(f"sandboxmap: fields {n + 1} and {m + 1} over each other")
        lines.append(f"\t{{ kind = {q(f['kind'])}, {rect_text(f['rect'])} }},")
    lines.append("} :: { Field }")

    lines.append("SandboxMap.Lawns = {")
    for l in plan["lawns"]:
        lines.append(f"\t{{ kind = {q(l['kind'])}, {rect_text(l['rect'])} }},")
    lines.append("} :: { Lawn }")

    lines.append("SandboxMap.TreeLines = {")
    for t in plan["treeLines"]:
        lines.append(f"\t{{ kind = {q(t['kind'])}, points = {{ {points_text(t['points'])} }} }},")
    lines.append("} :: { TreeLine }")

    lines.append("SandboxMap.Woods = {")
    for w in plan["woods"]:
        clear = ", ".join(f"{{ {rect_text(c)} }}" for c in w["clearings"])
        lines.append(f"\t{{ id = {q(w['id'])}, {rect_text(w['rect'])}, clearings = {{ {clear} }} }},")
    lines.append("} :: { Wood }")
    lines.append(f"SandboxMap.Orchard = {{ {rect_text(plan['orchard'])} }} :: Rect")

    lines.append("SandboxMap.Streams = {")
    for s in plan["streams"]:
        lines.append(f"\t{{ id = {q(s['id'])}, width = {num(s['width'])}, points = {{ {points_text(s['points'])} }} }},")
    lines.append("} :: { Stream }")
    lines.append(END)
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    plan = json.load(open(PLAN, encoding="utf-8"))
    text = open(TARGET, encoding="utf-8").read()
    found = re.search(r"^" + re.escape(BEGIN) + r".*?^" + re.escape(END) + r"$", text, re.M | re.S)
    if not found:
        raise SystemExit(f"sandboxmap: no '{BEGIN}' … '{END}' lines in {TARGET}")
    new = "\n".join(section(plan))
    if args.check:
        if found.group(0) != new:
            print("sandboxmap: shared/SandboxMap.luau's countryside section is not plan.json's: run tools/countryside/sandboxmap.py")
            sys.exit(1)
        print("sandboxmap: shared/SandboxMap.luau's countryside section is plan.json's")
        return
    out = text[:found.start()] + new + text[found.end():]
    if out != text:
        open(TARGET, "w", encoding="utf-8").write(out)
    print(f"sandboxmap: wrote the countryside section of {os.path.relpath(TARGET, GAME)} ({len(new.splitlines())} lines)")


if __name__ == "__main__":
    main()
