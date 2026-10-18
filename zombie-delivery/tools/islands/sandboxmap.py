#!/usr/bin/env python3
"""10.8 the floating islands (design/islands/plan.py): design/islands/plan.json as shared/SandboxMap.luau's ISLANDS
section, the data the game builds. Nothing in the game reads plan.json: this writes it into the module once, as Luau
tables, between the lines "-- BEGIN ISLANDS" and "-- END ISLANDS" of src/shared/SandboxMap.luau (the rest of the module,
its LOBBY section among it, is left as it is). It replaces 9.x's countryside section (design/countryside/plan.py's) and
the Houses written by hand from it. Deterministic: the same plan, the same lines.

    python3 zombie-delivery/tools/islands/sandboxmap.py [--check]

--check writes nothing and fails when the section is not what the plan gives (tests/run_tests.py runs it that way).

What it writes:
  Islands     plan.islands: one per island, the lobby's first: id, house (the place it holds; none: the lobby), name,
              x, z (its top's middle), sx, sz (its top's size), top (its top's height), depth (from its top to the tip
              of the rock under it), rect (its top's rect), walls (the walled area on it: the lobby's bounds, a map
              island's run zone), home (the spot the fall catch puts you back on), look (its grass, dirt, stone and
              rock colours), seed (its rock's dice)
  Rocks       plan.rocks: the decorative floating rocks (x, z, top, size, depth, seed)
  Bounds      plan.bounds: round every island and rock (nothing of the world outside them)
  Roads       each place's yard (its van parking: a round's vans side by side and in rows), named after the road its
              place stood on (yard = true, lane = true)
  Landmarks   plan.landmarks: id, name, kind, rect, yaw (the way its front looks)
  Fields      plan.fields (none)
  Lawns       plan.lawns: ground tiles of their own (kind, rect): the lodge's forest floor
  TreeLines   plan.treeLines: the orchard's fence, a windbreak, every map island's low rim hedge on its walls
  Woods       plan.woods: a wood's rect (its trees on a jittered grid) and its clearings (no tree)
  Orchard     plan.orchard: the orchard's rect (its fruit trees in rows)
  Streams     plan.streams: a stream's water `width` wide along its middle line's points (the millrace: off its island's
              edge as a waterfall)
  Zones       plan.zones: each place's walled area on its island (invisible walls and a low hedge on its edge) by its
              house's id, and where a run's party arrives (a Spot in its front yard, facing the door)
  Houses      plan.spots: the six places to empty (id, name, street, kind, look, island, box, lot, house: its walls'
              box, yaw, door, curb, back: the farmstead's back door); every y on its island's top
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
PLAN = os.path.join(GAME, "design", "islands", "plan.json")
TARGET = os.path.join(GAME, "src", "shared", "SandboxMap.luau")
BEGIN, END = "-- BEGIN ISLANDS", "-- END ISLANDS"


def num(v):
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    if isinstance(v, float):
        v = round(v, 4)
        if v.is_integer():
            v = int(v)
    return repr(v)


def rect_text(r):
    return f"x0 = {num(r['x0'])}, x1 = {num(r['x1'])}, z0 = {num(r['z0'])}, z1 = {num(r['z1'])}"


def spot_text(s):
    return f"{{ x = {num(s['x'])}, y = {num(s['y'])}, z = {num(s['z'])}, yaw = {num(s['yaw'])} }}"


def rgb(c):
    return "{ " + ", ".join(num(v) for v in c) + " }"


def q(text):
    return json.dumps(text, ensure_ascii=False)


def points_text(points):
    return ", ".join(f"{{ x = {num(p['x'])}, z = {num(p['z'])} }}" for p in points)


def section(plan):
    lines = [BEGIN + " (tools/islands/sandboxmap.py writes these lines from design/islands/plan.json: do not edit them)"]
    lines.append("SandboxMap.Islands = {")
    for i in plan["islands"]:
        house = f"house = {q(i['house'])}, " if i.get("house") else ""
        look = i["look"]
        lines.append(f"\t{{ id = {q(i['id'])}, {house}name = {q(i['name'])}, x = {num(i['x'])}, z = {num(i['z'])}, sx = {num(i['sx'])}, sz = {num(i['sz'])}, "
                     f"top = {num(i['top'])}, depth = {num(i['depth'])}, rect = {{ {rect_text(i['rect'])} }}, walls = {{ {rect_text(i['walls'])} }}, "
                     f"home = {spot_text(i['home'])}, look = {{ grass = {rgb(look['grass'])}, dirt = {rgb(look['dirt'])}, stone = {rgb(look['stone'])}, "
                     f"rock = {rgb(look['rock'])} }}, seed = {num(i['seed'])} }},")
    lines.append("} :: { Island }")
    lines.append("SandboxMap.Rocks = {")
    for r in plan["rocks"]:
        lines.append(f"\t{{ x = {num(r['x'])}, z = {num(r['z'])}, top = {num(r['top'])}, size = {num(r['size'])}, depth = {num(r['depth'])}, seed = {num(r['seed'])} }},")
    lines.append("} :: { Rock }")
    lines.append(f"SandboxMap.Bounds = {{ {rect_text(plan['bounds'])} }} :: Rect")

    lines.append("SandboxMap.Roads = {")
    for road in plan["roads"]:
        lines.append(f"\t{{ name = {q(road['name'])}, {rect_text(road['rect'])}, lane = true, yard = true }},")
    lines.append("} :: { Road }")

    lines.append("SandboxMap.Landmarks = {")
    for l in plan["landmarks"]:
        lines.append(f"\t{{ id = {q(l['id'])}, name = {q(l['name'])}, kind = {q(l['kind'])}, {rect_text(l['rect'])}, yaw = {num(l['yaw'])} }},")
    lines.append("} :: { Landmark }")

    lines.append("SandboxMap.Fields = {")
    for f in plan["fields"]:
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

    lines.append("SandboxMap.Zones = {")
    for z in plan["zones"]:
        lines.append(f"\t{{ id = {q(z['id'])}, rect = {{ {rect_text(z['rect'])} }}, arrive = {spot_text(z['arrive'])} }},")
    lines.append("} :: { Zone }")

    lines.append("SandboxMap.Houses = {")
    for s in plan["spots"]:
        h = s["house"]
        back = f", back = {spot_text(s['back'])}" if s.get("back") else ""
        lines.append(f"\t{{ id = {q(s['id'])}, name = {q(s['name'])}, street = {q(s['street'])}, kind = {q(s['kind'])}, look = {q(s['look'])}, "
                     f"island = {q(s['island'])}, box = {{ {rect_text(s['box'])} }}, lot = {{ {rect_text(s['lot'])} }}, "
                     f"house = {{ x = {num(h['x'])}, y = {num(h['y'])}, z = {num(h['z'])}, sx = {num(h['sx'])}, sy = {num(h['sy'])}, sz = {num(h['sz'])} }}, "
                     f"yaw = {num(s['yaw'])}, door = {spot_text(s['door'])}, curb = {spot_text(s['curb'])}{back} }},")
    lines.append("} :: { House }")
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
        raise SystemExit(f"islands: no '{BEGIN}' … '{END}' lines in {TARGET}")
    new = "\n".join(section(plan))
    if args.check:
        if found.group(0) != new:
            print("islands: shared/SandboxMap.luau's islands section is not design/islands/plan.json's: run tools/islands/sandboxmap.py")
            sys.exit(1)
        print("islands: shared/SandboxMap.luau's islands section is design/islands/plan.json's")
        return
    out = text[:found.start()] + new + text[found.end():]
    if out != text:
        open(TARGET, "w", encoding="utf-8").write(out)
    print(f"islands: wrote the islands section of {os.path.relpath(TARGET, GAME)} ({len(new.splitlines())} lines)")


if __name__ == "__main__":
    main()
