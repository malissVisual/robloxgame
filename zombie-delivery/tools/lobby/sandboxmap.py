#!/usr/bin/env python3
"""9.7 the lobby (design/lobby/plan.py; 10.4 one PLAY circle): design/lobby/plan.json as shared/SandboxMap.luau's LOBBY section, the data the
game builds. Nothing in the game reads plan.json: this writes it into the module once, as a Luau table, between the
lines "-- BEGIN LOBBY" and "-- END LOBBY" of src/shared/SandboxMap.luau (the rest of the module is left as it is; its
Plots are made from Lobby.plots). Deterministic: the same plan, the same lines.

    python3 zombie-delivery/tools/lobby/sandboxmap.py [--check]

--check writes nothing and fails when the section is not what the plan gives (tests/run_tests.py runs it that way).

What it writes (SandboxMap.Lobby):
  bounds      the lobby's square (the hedge HEDGE studs in from it, invisible walls on it)
  hedge       the hedge's inset
  far         studs from the bounds to every run zone at least (design/countryside/plan.py checks it)
  plaza       the paved square in the middle
  spawn       where a player appears (a Spot); spawnApart: the players' spawns this far apart across its look
  dispatch    the ZDC dispatch kiosk's foot (a Spot: its front's look)
  fountain    the fountain in the plaza (x, z, r)
  plots       the four plots: id, x (the warehouse's middle across), wall (its front wall's z: it looks south), rect
  play        10.4 the PLAY circle (one for every house: server/Parties.luau's party lobbies start the runs): x, z
              (its middle on the ground), r (its radius: config Runs.Play.Radius), back (a Spot just south of it,
              facing it: where a party comes back from a run, spread across; never in it)
  shops       paint (the PAINT shop's booth: spot, rect, stand: where you stand at its counter), leaders (the TOP
              MOVERS board: spot, rect), auction (the Auction House's front wall: spot, rect)
  lamps       the plaza's lamps ({ x, z })
  trees       the lobby's trees ({ kind, x, z }: VillageLooks' tree kinds)
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
PLAN = os.path.join(GAME, "design", "lobby", "plan.json")
TARGET = os.path.join(GAME, "src", "shared", "SandboxMap.luau")
BEGIN, END = "-- BEGIN LOBBY", "-- END LOBBY"


def num(v):
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    return repr(v)


def rect_text(r):
    return f"{{ x0 = {num(r['x0'])}, x1 = {num(r['x1'])}, z0 = {num(r['z0'])}, z1 = {num(r['z1'])} }}"


def spot_text(s):
    return f"{{ x = {num(s['x'])}, y = {num(s['y'])}, z = {num(s['z'])}, yaw = {num(s['yaw'])} }}"


def q(text):
    return json.dumps(text, ensure_ascii=False)


def section(plan):
    lines = [BEGIN + " (tools/lobby/sandboxmap.py writes these lines from design/lobby/plan.json: do not edit them)"]
    lines.append("SandboxMap.Lobby = {")
    lines.append(f"\tbounds = {rect_text(plan['bounds'])},")
    lines.append(f"\thedge = {num(plan['hedge'])},")
    lines.append(f"\tfar = {num(plan['far'])},")
    lines.append(f"\tplaza = {rect_text(plan['plaza'])},")
    lines.append(f"\tspawn = {spot_text(plan['spawn'])},")
    lines.append(f"\tspawnApart = {num(plan['spawnApart'])},")
    lines.append(f"\tdispatch = {spot_text(plan['dispatch'])},")
    f = plan["fountain"]
    lines.append(f"\tfountain = {{ x = {num(f['x'])}, z = {num(f['z'])}, r = {num(f['r'])} }},")
    lines.append("\tplots = {")
    for p in plan["plots"]:
        lines.append(f"\t\t{{ id = {num(p['id'])}, x = {num(p['x'])}, wall = {num(p['wall'])}, rect = {rect_text(p['rect'])} }},")
    lines.append("\t},")
    p = plan["play"]
    lines.append(f"\tplay = {{ x = {num(p['x'])}, z = {num(p['z'])}, r = {num(p['r'])}, back = {spot_text(p['back'])} }},")
    sh = plan["shops"]
    lines.append("\tshops = {")
    lines.append(f"\t\tpaint = {{ spot = {spot_text(sh['paint']['spot'])}, rect = {rect_text(sh['paint']['rect'])}, stand = {spot_text(sh['paint']['stand'])} }},")
    lines.append(f"\t\tleaders = {{ spot = {spot_text(sh['leaders']['spot'])}, rect = {rect_text(sh['leaders']['rect'])} }},")
    lines.append(f"\t\tauction = {{ spot = {spot_text(sh['auction']['spot'])}, rect = {rect_text(sh['auction']['rect'])} }},")
    lines.append("\t},")
    lines.append("\tlamps = { " + ", ".join(f"{{ x = {num(l['x'])}, z = {num(l['z'])} }}" for l in plan["lamps"]) + " },")
    lines.append("\ttrees = {")
    for t in plan["trees"]:
        lines.append(f"\t\t{{ kind = {q(t['kind'])}, x = {num(t['x'])}, z = {num(t['z'])} }},")
    lines.append("\t},")
    lines.append("} :: Lobby")
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
            print("lobby: shared/SandboxMap.luau's lobby section is not design/lobby/plan.json's: run tools/lobby/sandboxmap.py")
            sys.exit(1)
        print("lobby: shared/SandboxMap.luau's lobby section is design/lobby/plan.json's")
        return
    out = text[:found.start()] + new + text[found.end():]
    if out != text:
        open(TARGET, "w", encoding="utf-8").write(out)
    print(f"lobby: wrote the lobby section of {os.path.relpath(TARGET, GAME)} ({len(new.splitlines())} lines)")


if __name__ == "__main__":
    main()
