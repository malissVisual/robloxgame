#!/usr/bin/env python3
"""8.9 Jinočany, step 1 (design/jinocany/NAVRH.md §2): design/jinocany/plan.json as shared/SandboxMap.luau's village
section, the map's data the game builds. Nothing in the game reads plan.json: this writes it into the module once, as a
Luau table, between the lines "-- BEGIN JINOCANY" and "-- END JINOCANY" of src/shared/SandboxMap.luau (the rest of the
module is left as it is). Deterministic: the same plan, the same lines.

    python3 zombie-delivery/tools/village/sandboxmap.py [--check] [--step N]

--check writes nothing and fails when the section is not what the plan gives (tests/run_tests.py runs it that way);
--step: the plan's step to write (1, the default: the step the game builds).

What it writes (the step's entries, steps before it included):
  Bounds      plan.bounds
  Roads       the step's roads: Pražská and Depot Row first, as today's SandboxMap had them (their indices 1 and 2 are
              read by name and by number; Pražská from Depot Row's north edge, z -74: the junction is Depot Row's
              asphalt), then the plan's order; lane = true for a village lane (narrower than a main road: no centre line)
  Village     plan.houses of the step but the ones to empty (plan.enter: the moves' houses, SandboxMap.Houses): id, street,
              kind, box, yaw, the door and the curb
  Landmarks   plan.landmarks of the step but the orchard (its trees: Orchard): id, name, kind, rect
  Fields      plan.fields, each cut back off the fixed lots (the plots, the farmstead's) and two fields over each other
              cut apart, so no two ground tiles share a plane (each time the one cut that loses the least)
  Lawns       plan.village: the built-up area's gardens and lawns
  TreeLines   plan.treeLines
  Orchard     the orchard landmark's rect

ADJUST below changes a plan entry on the way, each with its reason.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
PLAN = os.path.join(GAME, "design", "jinocany", "plan.json")
TARGET = os.path.join(GAME, "src", "shared", "SandboxMap.luau")
BEGIN, END = "-- BEGIN JINOCANY", "-- END JINOCANY"

# Today's two roads, as shared/SandboxMap.luau had them before the village (the plan copies them, Pražská from Depot
# Row's south edge): the order and Pražská's north end stay.
FIXED_ROADS = [
    {"name": "Pražská", "x0": -14, "x1": 14, "z0": -74, "z1": 470},
    {"name": "Depot Row", "x0": -270, "x1": 270, "z0": -74, "z1": -46},
]
MAIN_WIDTH = 28  # a road this wide is a main road (Depot Row, Pražská, Hlavní, Hornická); the narrower ones are lanes

# Changes to the plan's entries on the way into the game, each with its reason.
ADJUST = {
    # The TOP MOVERS board (shared/SandboxLeadersRules.luau spot: Pražská's east edge + 26, Depot Row's south edge + 24,
    # turned 45°) reaches x 52 with its roof: the drugstore's car park and lamp would stand in it from x 40.
    ("landmark", "drugstore"): {"x0": 56},
}


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


def area(r):
    return (r["x1"] - r["x0"]) * (r["z1"] - r["z0"])


def cut(field, block):
    """The field less the block, as one rect: the cut along one of the block's edges that keeps the most of it."""
    best = None
    for side, edge in (("x1", block["x0"]), ("x0", block["x1"]), ("z1", block["z0"]), ("z0", block["z1"])):
        r = dict(field)
        r[side] = edge
        if r["x1"] > r["x0"] and r["z1"] > r["z0"] and not overlap(r, block):
            area = (r["x1"] - r["x0"]) * (r["z1"] - r["z0"])
            if best is None or area > best[0]:
                best = (area, r)
    if best is None:
        raise SystemExit(f"sandboxmap: no cut of the field {field} keeps a rect clear of {block}")
    return best[1]


def section(plan, step):
    lines = [BEGIN + " (tools/village/sandboxmap.py writes these lines from design/jinocany/plan.json: do not edit them)"]
    b = plan["bounds"]
    lines.append(f"SandboxMap.Bounds = {{ {rect_text(b)} }} :: Rect")

    # the roads: today's two first, then the plan's of the step
    roads = [dict(r) for r in FIXED_ROADS]
    names = {r["name"] for r in roads}
    for road in plan["roads"]:
        if road["step"] <= step and road["name"] not in names:
            roads.append({"name": road["name"], **road["rect"]})
    lines.append("SandboxMap.Roads = {")
    for r in roads:
        lane = min(r["x1"] - r["x0"], r["z1"] - r["z0"]) < MAIN_WIDTH
        lines.append(f"\t{{ name = {q(r['name'])}, {rect_text(r)}, lane = {'true' if lane else 'false'} }},")
    lines.append("} :: { Road }")

    # the decorative houses (the ones to empty are the moves': SandboxMap.Houses)
    entering = {h["id"] for h in plan["enter"]}
    lines.append("SandboxMap.Village = {")
    for h in plan["houses"]:
        if h["step"] <= step and h["id"] not in entering:
            d, c = h["door"], h["curb"]
            lines.append(f"\t{{ id = {q(h['id'])}, street = {q(h['street'])}, kind = {q(h['kind'])}, {rect_text(h['box'])}, yaw = {num(h['yaw'])}, "
                         f"door = {{ x = {num(d['x'])}, z = {num(d['z'])} }}, curb = {{ x = {num(c['x'])}, z = {num(c['z'])} }} }},")
    lines.append("} :: { VillageHouse }")

    # the landmarks (the orchard is its trees: Orchard)
    orchard = None
    lines.append("SandboxMap.Landmarks = {")
    for l in plan["landmarks"]:
        if l["step"] > step:
            continue
        r = dict(l["rect"])
        r.update(ADJUST.get(("landmark", l["id"]), {}))
        if l["kind"] == "orchard":
            orchard = r
            continue
        lines.append(f"\t{{ id = {q(l['id'])}, name = {q(l['name'])}, kind = {q(l['kind'])}, {rect_text(r)} }},")
    lines.append("} :: { Landmark }")

    # the fields: off the fixed lots and the fields before them
    fixed = [p["rect"] for p in plan["plots"]] + [plan["bigHouse"]["lot"]]
    done = []
    for f in plan["fields"]:
        r = dict(f["rect"])
        for block in fixed:
            if overlap(r, block):
                r = cut(r, block)
        for d in done:
            if overlap(r, d["rect"]):
                # (two fields over each other: the one cut that loses the less, this field's or the earlier one's)
                mine, theirs = cut(r, d["rect"]), cut(d["rect"], r)
                if area(r) - area(mine) <= area(d["rect"]) - area(theirs):
                    r = mine
                else:
                    d["rect"] = theirs
        done.append({"kind": f["kind"], "rect": r})
    lines.append("SandboxMap.Fields = {")
    for f in done:
        lines.append(f"\t{{ kind = {q(f['kind'])}, {rect_text(f['rect'])} }},")
    lines.append("} :: { Field }")

    v = plan["village"]
    lines.append(f"SandboxMap.Lawns = {{ {{ {rect_text(v)} }} }} :: {{ Rect }}")
    lines.append("SandboxMap.TreeLines = {")
    for t in plan["treeLines"]:
        points = ", ".join(f"{{ x = {num(p['x'])}, z = {num(p['z'])} }}" for p in t["points"])
        lines.append(f"\t{{ kind = {q(t['kind'])}, points = {{ {points} }} }},")
    lines.append("} :: { TreeLine }")
    if orchard is None:
        raise SystemExit("sandboxmap: the plan has no orchard")
    lines.append(f"SandboxMap.Orchard = {{ {rect_text(orchard)} }} :: Rect")
    lines.append(END)
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--step", type=int, default=1)
    args = parser.parse_args()
    plan = json.load(open(PLAN, encoding="utf-8"))
    text = open(TARGET, encoding="utf-8").read()
    found = re.search(r"^" + re.escape(BEGIN) + r".*?^" + re.escape(END) + r"$", text, re.M | re.S)
    if not found:
        raise SystemExit(f"sandboxmap: no '{BEGIN}' … '{END}' lines in {TARGET}")
    new = "\n".join(section(plan, args.step))
    if args.check:
        if found.group(0) != new:
            print("sandboxmap: shared/SandboxMap.luau's village section is not plan.json's: run tools/village/sandboxmap.py")
            sys.exit(1)
        print("sandboxmap: shared/SandboxMap.luau's village section is plan.json's")
        return
    out = text[:found.start()] + new + text[found.end():]
    if out != text:
        open(TARGET, "w", encoding="utf-8").write(out)
    print(f"sandboxmap: wrote the village section of {os.path.relpath(TARGET, GAME)} (step {args.step}, {len(new.splitlines())} lines)")


if __name__ == "__main__":
    main()
