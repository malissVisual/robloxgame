#!/usr/bin/env python3
"""7.0, the moves' world: builds it with the real server/MoveSites.luau on the recorder (export.luau, as Moving.start calls
it) and checks what comes out, in the world's own coordinates.

  * every piece of shared/MoveSiteLooks.luau built, nothing else, within Config.MoveSites.Budget parts (all of it: the
    checkpoint, the kiosk, the banner, each contract's house, the evacuation spots); finite numbers
  * every part anchored, CanTouch off, CanQuery only with CanCollide (decoration neither); the PointLights within
    Config.MoveSites.Lights, shadowless and switched by DayNight, every glowing part registered too
  * the text: drawn within MoveSiteLooks.textRange (Config.MoveSites.TextRange at least), 25-100 pixels a stud, scaled
  * the models as Moving needs them: MovingBoard (Persistent, its corkboard "Board" the prompt's part, within a stud of
    Config.Moving.Board), MovingDropOff (Persistent, the gantry's sign its PrimaryPart), the house's yard sign returned,
    the banner Persistent, each spot Atomic
  * 7.x farm move: each farm site (Walt's farmhouse and the dress at its Map.Places place): only the farmhouse's body
    solid, nothing on a door's way out to its van spot, on the van spot or on Walt's spot by the front door
  * 8.0 SANDBOX: the kiosk on every plot (MoveSites.plotBoard): Persistent, its corkboard "Board" (the prompt's part,
    solid, its attribute Plot) within a stud of the plot's board spot, every piece built with the city's flags, and
    nothing of it in the warehouse's roller door's way or where the van backs in to unload (the unload circle)
  * no blocking: nothing but paint in the truck's lane from Bone St into the drop-off's bay below the gantry's sign
    (Config.MoveSites.Clear), nothing of the checkpoint off the depot's block (the road), nothing solid at a house and
    nothing on the strip from its door out to the truck's kerb spot (Map.Home park) a body's height

    python3 zombie-delivery/tools/move-sites/check.py <luau> [--export scene.json]

--export writes the parts and the context (the depot's hall, Marge's house and street, a tower by each spot) for
render.py. The pure checks (the depot's own spots kept clear, the spots clear of the street props) are
tests/movesites_test.luau's.
"""
from pathlib import Path
import argparse
import json
import math
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
SHARED = ROOT / "src" / "shared"
HEAD = ('local M = require("./ItemMock")\n'
        'local Instance, Vector3, Color3, CFrame, Enum, UDim2 = M.Instance, M.Vector3, M.Color3, M.CFrame, M.Enum, M.UDim2\n'
        'local UDim = { new = function(a, b) return { a, b } end }\n'
        'local game = M.game\n')
# DayNight on the recorder: marks what registers (the lit colour of a glowing part).
NIGHT = ('{ nightLight = function(obj, lit, dim, material) obj:SetAttribute("NightLight", true); '
         'if lit then obj:SetAttribute("LitColor", lit) end end }')


def export(luau: str) -> list:
    """Every JSON line export.luau prints (parts, context, the summary last)."""
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        for source in SHARED.glob("*.luau"):
            text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
            (tmp / source.name).write_text(text)
        shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
        shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
        server = (ROOT / "src/server/MoveSites.luau").read_text()
        server = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', server)
        server = server.replace("require(script.Parent.DayNight)", NIGHT)
        assert "script.Parent" not in server, "MoveSites requires a server module the check does not stand in for"
        (tmp / "MoveSitesServer.luau").write_text(HEAD + server)
        depot = (ROOT / "src/server/BuildingLooks/Depot.luau").read_text().replace("require(script.Parent.Kit)", "{}")
        (tmp / "DepotLook.luau").write_text(depot)
        shutil.copy(HERE / "export.luau", tmp / "export.luau")
        result = subprocess.run([str(Path(luau).resolve()), "export.luau"], cwd=tmp, capture_output=True, text=True)
        if result.returncode != 0 or not result.stdout.strip():
            raise SystemExit("export failed:\n" + result.stdout[-3000:] + result.stderr[-3000:])
        return [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]


def box(p):
    """The part's axis-aligned box: (x0, x1, y0, y1, z0, z1)."""
    r, s, c = p["rotation"], p["size"], p["position"]
    half = [sum(abs(r[i * 3 + j]) * s[j] for j in range(3)) / 2 for i in range(3)]
    return c[0] - half[0], c[0] + half[0], c[1] - half[1], c[1] + half[1], c[2] - half[2], c[2] + half[2]


def check(records: list) -> list:
    """The failures (empty: all good)."""
    summary = records[-1]
    assert summary["kind"] == "summary"
    parts = [r for r in records if r["kind"] == "part"]
    bad = []

    def need(ok, what):
        if not ok:
            bad.append(what)

    # Every piece, nothing else, within the budget; finite.
    need(len(parts) == summary["pieces"], f"{len(parts)} parts built for {summary['pieces']} pieces")
    need(len(parts) <= summary["budget"], f"{len(parts)} parts over the budget {summary['budget']}")
    sets = {}
    for p in parts:
        sets.setdefault(p["set"], []).append(p)
        numbers = p["position"] + p["size"] + p["rotation"]
        need(all(isinstance(n, (int, float)) and math.isfinite(n) for n in numbers), f"{p['set']}.{p['name']}: numbers")
        need(all(n >= 0.04 for n in p["size"]), f"{p['set']}.{p['name']}: size")
    for name in ("board", "checkpoint", "banner", "house_marge", "EvacuationSpot1"):
        need(name in sets, f"no {name}")
    for farm in summary.get("farms", []):  # 7.x farm move
        need("farm_" + farm["id"] in sets, f"no farm_{farm['id']}")

    # The flags.
    lights = 0
    for p in parts:
        where = f"{p['set']}.{p['name']}"
        need(p["anchored"], where + " not anchored")
        need(not p["touch"], where + " CanTouch")
        need(p["query"] == p["collide"], where + " CanQuery without CanCollide (or the other way)")
        for light in p["lights"]:
            lights += 1
            need(light["night"] and not light["shadows"], where + ": its light not DayNight's or with shadows")
        if p.get("lit") is not None:
            need(p["night"], where + ": glows but DayNight does not know it")
        for w in p["words"]:
            need(w["range"] >= summary["textRange"] and 25 <= w["pps"] <= 100, f"{where}: text range {w['range']} / {w['pps']} px")
            need(len(w["lines"]) > 0 and all(line["text"] and line["scaled"] for line in w["lines"]), where + ": empty or unscaled text")
    need(0 < lights <= summary["lights"], f"{lights} lights (at most {summary['lights']})")

    # The models as Moving needs them.
    modes = summary["modes"]
    need(modes == {"board": "Persistent", "checkpoint": "Persistent", "banner": "Persistent", "spot": "Atomic"}, f"streaming {modes}")
    primary = summary["primary"]
    need(primary == {"board": "Board", "corkboard": "Board", "checkpoint": "CheckpointSign", "house": "YardSign", "farm": "YardSign"}, f"primary parts {primary}")
    for p in sets.get("board", []):
        if p["name"] == "Board":
            bx, bz = summary["board"]
            need(math.hypot(p["position"][0] - bx, p["position"][2] - bz) < 1 and p["collide"], "the corkboard off Config.Moving.Board (or not solid)")

    # 8.0 SANDBOX: the plots' kiosks.
    sandbox = [r for r in records if r["kind"] == "sandbox"]
    boards = summary.get("plotBoards", [])
    need(len(boards) == summary.get("plots") and len(boards) > 0, f"{len(boards)} plot kiosks for {summary.get('plots')} plots")
    for b in boards:
        where = b["name"]
        need(b["mode"] == "Persistent" and b["primary"] == "Board" and b["corkboard"] == "Board" and b["plot"] == b["id"],
             f"{where}: streaming {b['mode']}, primary {b['primary']}, Plot {b['plot']}")
        mine = [p for p in sandbox if p["set"] == f"plotboard{int(b['id'])}"]
        need(len(mine) == summary["boardPieces"], f"{where}: {len(mine)} parts for {summary['boardPieces']} pieces")
        (sx, sz), (dx, dz), (ux, uz, ur), (vx, vz) = b["spot"], b["door"], b["unload"], b["vanSpot"]
        for p in mine:
            name = f"{where}.{p['name']}"
            need(p["anchored"] and not p["touch"] and p["query"] == p["collide"], name + ": flags")
            x0, x1, y0, y1, z0, z1 = box(p)
            if p["name"] == "Board":
                need(math.hypot(p["position"][0] - sx, p["position"][2] - sz) < 1 and p["collide"], name + ": off the plot's board spot (or not solid)")
            # the roller door's opening (its width, from the wall out past the van's spot) and the unload circle stay clear
            half = summary["doorWidth"] / 2
            need(not (x1 > dx - half and x0 < dx + half and z1 > min(dz, vz) - 1 and z0 < max(dz, vz) + 1), name + ": in the roller door's way")
            cx, cz = min(max(ux, x0), x1), min(max(uz, z0), z1)
            need(math.hypot(cx - ux, cz - uz) > ur or y0 > summary["groundTop"] + 12, name + ": in the unload circle")

    # No blocking at the checkpoint: the lane in from Bone St (the bay and its kerb) under the sign; on the depot's block.
    walk, clear = summary["walk"], summary["clear"]
    (cx, cz), (w, d) = summary["dropOff"], summary["bay"]
    (dx, dz), half = summary["depot"], summary["block"] / 2
    paint = 0
    for p in sets.get("checkpoint", []):
        x0, x1, y0, y1, z0, z1 = box(p)
        if x1 > cx - w / 2 - 0.5 and x0 < cx + w / 2 + 0.5 and z1 > cz - d / 2 - 0.5 and z0 < cz + d / 2 + 4:
            if y1 <= walk + 0.2:
                paint += 1
                need(not p["collide"], f"checkpoint.{p['name']}: solid paint")
            else:
                need(y0 >= walk + clear - 0.4, f"checkpoint.{p['name']}: in the truck's lane ({y0 - walk:.1f} over the walk)")
        need(x0 >= dx - half - 0.01 and x1 <= dx + half + 0.01 and z0 >= dz - half - 0.01 and z1 <= dz + half + 0.01,
             f"checkpoint.{p['name']}: off the depot's block (on the road)")
    need(paint >= 9, f"the bay's paint: {paint} parts")
    # The people's walk line round the depot's block (TrafficLanes.SidewalkInset in from its curbs, a Body each side,
    # 1 … 5.5 over the walk: server/Traffic.luau's survey and its walkers): nothing of the checkpoint or the kiosk on it.
    ring, body = half - summary["inset"], summary["body"] + 0.2
    for p in sets.get("checkpoint", []) + sets.get("board", []):
        x0, x1, y0, y1, z0, z1 = box(p)
        if y1 <= walk + 1 or y0 >= walk + 5.5:
            continue
        x0, x1, z0, z1 = x0 - dx, x1 - dx, z0 - dz, z1 - dz
        for k in (-1, 1):
            on_x = z1 > k * ring - body and z0 < k * ring + body and x1 > -ring - body and x0 < ring + body
            on_z = x1 > k * ring - body and x0 < k * ring + body and z1 > -ring - body and z0 < ring + body
            need(not (on_x or on_z), f"{p['set']}.{p['name']}: on the people's walk line round the depot")

    # No blocking at the houses: nothing solid; nothing on the strip from the door to the park a body's height.
    road = summary["road"]
    for home in summary["homes"]:
        (hx, hz), (fx, fz), (px, pz) = home["door"], home["facing"], home["park"]
        depth = (px - hx) * fx + (pz - hz) * fz
        for p in sets.get("house_" + home["id"], []):
            where = f"house_{home['id']}.{p['name']}"
            need(not p["collide"], where + " solid")
            x0, x1, y0, y1, z0, z1 = box(p)
            # the box in the door's frame (out along the facing, across it): the corners' spans
            corners = [((x - hx) * fx + (z - hz) * fz, (x - hx) * -fz + (z - hz) * fx) for x in (x0, x1) for z in (z0, z1)]
            out0, out1 = min(c[0] for c in corners), max(c[0] for c in corners)
            side0, side1 = min(c[1] for c in corners), max(c[1] for c in corners)
            on_path = out1 > 0 and out0 < depth and side1 > -2.4 and side0 < 2.4
            need(not (on_path and y0 < walk + 7.5 and y1 > road + 0.2), f"{where}: on the path from the door to the truck's kerb")

    # 7.x farm move: a farm's site: only the farmhouse's body solid; nothing on a door's way out to its van spot, on the
    # van spot (the van 17 long, its back to the door) or on Walt's spot by the front door, a body's height
    for farm in summary.get("farms", []):
        ground, curb = farm["ground"], farm["curb"]
        for p in sets.get("farm_" + farm["id"], []):
            where = f"farm_{farm['id']}.{p['name']}"
            need(not p["collide"] or p["name"] == "FarmhouseBody", where + " solid")
            x0, x1, y0, y1, z0, z1 = box(p)
            if y0 >= ground + 7.5:
                continue
            for n, d in enumerate(farm["doors"]):
                (hx, hz), (fx, fz) = d["door"], d["facing"]
                corners = [((x - hx) * fx + (z - hz) * fz, (x - hx) * -fz + (z - hz) * fx) for x in (x0, x1) for z in (z0, z1)]
                out0, out1 = min(c[0] for c in corners), max(c[0] for c in corners)
                side0, side1 = min(c[1] for c in corners), max(c[1] for c in corners)
                half = d["width"] / 2 + 0.4
                need(not (out1 > 0.6 and out0 < curb - 8.5 and side1 > -half and side0 < half), f"{where}: on door {n + 1}'s way out")
                need(not (out1 > curb - 8.5 and out0 < curb + 8.5 and side1 > -4 and side0 < 4), f"{where}: on door {n + 1}'s van spot")
                if n == 0:
                    px, pz = farm["porch"][0], -farm["porch"][1]
                    need(not (side1 > px - 1.2 and side0 < px + 1.2 and out1 > pz - 1.2 and out0 < pz + 1.2), f"{where}: on Walt's spot")
    return bad


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("--export", type=Path, help="write the parts and the context here (JSON) for render.py")
    args = parser.parse_args()
    records = export(args.luau)
    bad = check(records)
    summary = records[-1]
    counts = {}
    for r in records:
        if r["kind"] == "part":
            counts[r["set"]] = counts.get(r["set"], 0) + 1
    if args.export:
        args.export.write_text(json.dumps(records))
    if bad:
        print("Move sites FAIL:")
        for line in bad:
            print("  " + line)
        raise SystemExit(1)
    print(f"Move sites PASS: {int(summary['parts'])} parts (budget {int(summary['budget'])}): " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    print(f"8.0 SANDBOX: {len(summary.get('plotBoards', []))} plot kiosks checked (their spot, flags, the roller door and the unload circle clear)")
    print("Flags, lights, text, streaming, the prompt's part, the truck's lane, the depot's walk line and the houses' paths checked")


if __name__ == "__main__":
    main()
