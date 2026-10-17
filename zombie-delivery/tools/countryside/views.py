#!/usr/bin/env python3
"""9.4 the countryside (design/countryside/plan.py): 3D views of the six places to empty for the owner
(design/countryside/view-*.png), from the game's own code, without Roblox.

The real server code builds the world on tools/perf/world-mock.luau (tools/sandbox-map/render.py's export: the map, the
kiosks, the warehouses, the TOP MOVERS board), the ZDC Sprinter's parts model stands at each place's curb
(tools/vehicle-preview/export_fleet.py), and tools/village/render.mjs draws each view with three.js in headless Chromium
(tools/village/render.html: a warm afternoon, a perspective camera, soft shadows, a light haze). The parts look only: no
Blender imports (the farmstead is its stand-in chalet; 9.5 the other five in their own looks, VillageLooks.house's
cabin, old family house, lodge, mill and cottage).

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/countryside/views.py <luau> <three.module.min.js> [--out DIR]

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Chromium from
CHROMIUM (default /opt/pw-browsers/chromium); --out defaults to design/countryside.
"""
import argparse
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

# The views: name, caption, the place whose curb gets a van, the camera (from, to: studs on the map, y up), its fov.
VIEWS = [
    ("view-farm", "The Old Farmstead: the farm", "sandbox_house", (150, 70, 430), (-40, 2, 560), 50),
    ("view-pond", "The Pond Cabin: the jetty, the boat, the reeds", "pond_cabin", (-860, 45, 590), (-990, 2, 470), 50),
    ("view-mill", "The Old Mill: the millrace past it, the weir, the footbridge", "old_mill", (-1175, 40, -95), (-1064, 3, -30), 52),
    ("view-forest", "The Forest Lodge: its clearing in the forest", "forest_lodge", (-880, 70, -330), (-950, 2, -465), 52),
    ("view-orchard", "The Orchard Cottage: the orchard, the beehives", "orchard_cottage", (320, 60, -360), (180, 2, -470), 52),
    ("view-lone", "The Lone House: alone by Hill Road among the fields", "lone_house", (-470, 55, -330), (-600, 2, -450), 52),
]


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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("--out", type=Path, default=GAME / "design" / "countryside")
    args = parser.parse_args()
    luau = str(Path(args.luau).resolve())
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        sandbox_map.export_world(luau, tmp)
        export_fleet.export(luau, tmp / "fleet")
        world = json.loads((tmp / "world.json").read_text())
        facts = json.loads((tmp / "facts.json").read_text())
        sprinter = next(m for m in json.loads((tmp / "fleet" / "fleet.json").read_text()) if m["id"] == "sprinter" and not m.get("upgraded"))
        van = [{"p": p["position"], "r": p["rotation"], "s": p["size"], "c": [round(v * 255) for v in p["color"]], "t": 1 - p["opacity"],
                "mat": p["material"], "shape": "Cylinder" if p.get("shape") == "Cylinder" else "Ball" if p.get("shape") == "Ball" else
                "Wedge" if p["class"] == "WedgePart" else "Block"}
               for p in sprinter["parts"] if p["class"] in ("Part", "WedgePart", "CornerWedgePart") and p["opacity"] > 0.05]
        parts = [{"p": p["p"], "r": p["r"], "s": p["s"], "c": p["c"], "t": p["t"], "mat": p["mat"], "shape": shape_of(p)}
                 for p in world if not p["group"].startswith("Sandbox/Boundary") and p["t"] < 0.95]
        curbs = {}
        for name in ("house",):
            curbs["sandbox_house"] = facts[name]["curb"]
        spots = json.loads((GAME / "design" / "countryside" / "plan.json").read_text(encoding="utf-8"))["spots"]
        for s in spots:
            curbs[s["id"]] = {"x": s["curb"]["x"], "y": 0.4, "z": s["curb"]["z"], "yaw": s["curb"]["yaw"]}
        shots = []
        for name, caption, spot, eye, look, fov in VIEWS:
            shots.append({"name": name, "caption": caption, "subject": 0, "parts": parts + van_at(van, curbs[spot]),
                          "view": {"w": 1920, "h": 1080, "from": list(eye), "to": list(look), "fov": fov}})
        site = tmp / "site"
        site.mkdir()
        shutil.copy(GAME / "tools" / "village" / "render.html", site / "render.html")
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        (tmp / "shots.json").write_text(json.dumps(shots))
        args.out.mkdir(parents=True, exist_ok=True)
        subprocess.run(["node", str(GAME / "tools" / "village" / "render.mjs"), str(site), str(tmp / "shots.json"), str(args.out.resolve())], check=True)
    print(f"countryside views: {len(VIEWS)} views in {args.out}")


if __name__ == "__main__":
    main()
