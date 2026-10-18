#!/usr/bin/env python3
"""10.6 the floating islands (design/islands/plan.py): 3D views of the islands for the owner (design/islands/view-*.png),
from the game's own code, without Roblox.

The real server code builds the world on tools/perf/world-mock.luau (tools/sandbox-map/render.py's export: every island's
grass and rock, its place, the lobby with its plots and warehouses, the floating rocks, the clouds), the ZDC Sprinter's
parts model stands at the first spots of each place's van parking (design/islands/plan.py parking: a round's), and
tools/village/render.mjs draws each view with three.js in headless Chromium (tools/village/render.html: a perspective
camera, soft shadows, the sky's haze). The parts look only: no Blender imports, no signs' words.
  view-lobby          the lobby's island from over its south edge: its low hedge, its rim, the islands round it
  view-lobby-edge     from the lobby's north-west corner over its low hedge: the farm's and the lodge's islands
  view-lobby-east     from the lobby's east side over its low hedge: the mill's and the orchard's islands
  view-<id>           each map island from outside: its place on its top, its rock under it
  view-below          from under the islands, looking up at the lobby's rock and the others round it

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/islands/views.py <luau> <three.module.min.js> [--out DIR]

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Chromium from
CHROMIUM (default /opt/pw-browsers/chromium); --out defaults to design/islands.
"""
import argparse
import importlib.util
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(GAME / "tools" / "sandbox-map"))
sys.path.insert(0, str(GAME / "tools" / "vehicle-preview"))
import render as sandbox_map  # noqa: E402  (tools/sandbox-map/render.py: export_world)
import export_fleet  # noqa: E402

PLAN_PY = GAME / "design" / "islands" / "plan.py"
PLAN = json.loads((GAME / "design" / "islands" / "plan.json").read_text(encoding="utf-8"))
VANS = 6  # the vans shown at each place (the first of its round's parking)

CAPTIONS = {
    "farm": "The Old Farmstead's island: the barn, the tractor, the bales and the paddock",
    "pond": "The Pond Cabin's island: the pond with its jetty and boat",
    "lone": "The Lone House's island: its garden",
    "lodge": "The Forest Lodge's island: its forest round the clearing",
    "mill": "The Old Mill's island: its stream off the edge as a waterfall",
    "orchard": "The Orchard Cottage's island: the orchard rows and the beehives",
}


def shape_of(p):
    if p.get("class") == "WedgePart":
        return "Wedge"
    if p.get("class") == "CornerWedgePart":
        return "CornerWedge"
    if p.get("mesh") == "Sphere":
        return "Ellipsoid"
    if p.get("shape") in ("Cylinder", "Ball"):
        return p["shape"]
    return "Block"


def van_at(van, spot):
    """The van's parts (model space, its nose to -Z) at a spot { x, y, z, yaw } (Roblox's CFrame turn about Y)."""
    a = math.radians(spot["yaw"])
    c, s = math.cos(a), math.sin(a)
    out = []
    for p in van:
        px, py, pz = p["p"]
        r = p["r"]
        R = [c * r[0] + s * r[6], c * r[1] + s * r[7], c * r[2] + s * r[8], r[3], r[4], r[5],
             -s * r[0] + c * r[6], -s * r[1] + c * r[7], -s * r[2] + c * r[8]]
        out.append({**p, "p": [c * px + s * pz + spot["x"], py + spot["y"], -s * px + c * pz + spot["z"]], "r": R})
    return out


def plan_module():
    spec = importlib.util.spec_from_file_location("islands_plan", PLAN_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def views():
    """The shots: name, caption, camera from, to (studs on the map, y up), fov (vertical degrees)."""
    by_id = {i["id"]: i for i in PLAN["islands"]}
    lobby = by_id["lobby"]
    w = PLAN["islands"][0]["walls"]  # (the lobby's bounds: its low hedge on them)

    def between(eye, a, b, down):
        """A camera at `eye` looking between islands a and b (their middles), `down` degrees under the level."""
        da, db = [(i["x"] - eye[0], i["z"] - eye[2]) for i in (a, b)]
        na, nb = math.hypot(*da), math.hypot(*db)
        dx, dz = da[0] / na + db[0] / nb, da[1] / na + db[1] / nb
        n = math.hypot(dx, dz)
        return (eye[0] + dx / n * 600, eye[1] - 600 * math.tan(math.radians(down)), eye[2] + dz / n * 600)
    edge = (w["x0"] + 34, 11, w["z0"] + 40)  # (a player's camera: over and behind them)
    east = (w["x1"] - 24, 11, lobby["z"] + 5)
    out = [
        ("view-lobby", "The lobby's island from over its south edge: its low hedge and rim, the farm's, the lodge's and the mill's islands round it",
         (lobby["x"], 210, w["z1"] + 345), (lobby["x"], 0, lobby["z"] - 10), 55),
        ("view-lobby-edge", "From the lobby's north-west corner over its low hedge: the farm's island to the left, the Forest Lodge's to the right",
         edge, between(edge, by_id["farm"], by_id["lodge"], 3), 60),
        ("view-lobby-east", "From the lobby's east side over its low hedge: the Old Mill's island to the left, the Orchard Cottage's to the right",
         east, between(east, by_id["mill"], by_id["orchard"], 3), 60),
    ]
    spots = {s["island"]: s for s in PLAN["spots"]}
    for i in PLAN["islands"][1:]:
        s = spots[i["id"]]
        # (from the side its yard is on: the way out of its door, up a little, far enough to see its rock under it)
        a = math.radians(s["door"]["yaw"])
        lx, lz = -math.sin(a), -math.cos(a)
        side = math.radians(30)
        dx, dz = lx * math.cos(side) - lz * math.sin(side), lx * math.sin(side) + lz * math.cos(side)
        far = max(i["sx"], i["sz"]) * 1.05 + 120
        eye = (i["x"] + dx * far, i["top"] + far * 0.32, i["z"] + dz * far)
        look = (i["x"], i["top"] - i["depth"] * 0.25, i["z"])
        out.append((f"view-{i['id']}", CAPTIONS[i["id"]], eye, look, 45))
    out.append(("view-below", "From under the islands: the lobby's rock and the others round it, the clouds below",
                (lobby["x"] - 380, lobby["top"] - 205, lobby["z"] + 420), (lobby["x"] - 120, lobby["top"] - 60, lobby["z"] - 120), 60))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("--out", type=Path, default=GAME / "design" / "islands")
    args = parser.parse_args()
    luau = str(Path(args.luau).resolve())
    plan = plan_module()
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        sandbox_map.export_world(luau, tmp)
        export_fleet.export(luau, tmp / "fleet")
        world = json.loads((tmp / "world.json").read_text())
        sprinter = next(m for m in json.loads((tmp / "fleet" / "fleet.json").read_text()) if m["id"] == "sprinter" and not m.get("upgraded"))
        van = [{"p": p["position"], "r": p["rotation"], "s": p["size"], "c": [round(v * 255) for v in p["color"]], "t": 1 - p["opacity"],
                "mat": p["material"], "shape": "Cylinder" if p.get("shape") == "Cylinder" else "Ball" if p.get("shape") == "Ball" else
                "Wedge" if p["class"] == "WedgePart" else "Block"}
               for p in sprinter["parts"] if p["class"] in ("Part", "WedgePart", "CornerWedgePart") and p["opacity"] > 0.05]
        parts = [{"p": p["p"], "r": p["r"], "s": p["s"], "c": p["c"], "t": p["t"], "mat": p["mat"], "shape": shape_of(p)}
                 for p in world if not p["group"].startswith("Sandbox/Boundary") and p["t"] < 0.95]
        vans = []
        zones = {z["id"]: z for z in PLAN["zones"]}
        for s in PLAN["spots"]:
            for v in plan.parking(s["curb"], zones[s["id"]]["rect"], s["lot"])[:VANS]:
                vans += van_at(van, {"x": v["x"], "y": s["curb"]["y"], "z": v["z"], "yaw": v["yaw"]})
        shots = []
        for name, caption, eye, look, fov in views():
            shots.append({"name": name, "caption": caption, "subject": 0, "parts": parts + vans,
                          "view": {"w": 1920, "h": 1080, "from": list(eye), "to": list(look), "fov": fov, "fog": [1400, 5200]}})
        site = tmp / "site"
        site.mkdir()
        shutil.copy(GAME / "tools" / "village" / "render.html", site / "render.html")
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        (tmp / "shots.json").write_text(json.dumps(shots))
        args.out.mkdir(parents=True, exist_ok=True)
        subprocess.run(["node", str(GAME / "tools" / "village" / "render.mjs"), str(site), str(tmp / "shots.json"), str(args.out.resolve())], check=True)
    print(f"island views: {len(shots)} views in {args.out}")


if __name__ == "__main__":
    main()
