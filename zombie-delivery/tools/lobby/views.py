#!/usr/bin/env python3
"""9.7 the lobby (design/lobby/plan.py): 3D views of the lobby for the owner (design/lobby/view-*.png), from the game's
own code, without Roblox. 10.4: the smaller lobby, its one PLAY circle in the plaza (no portals).

The real server code builds the world on tools/perf/world-mock.luau (tools/sandbox-map/render.py's export: the map with
the lobby, server/LobbyWorld.luau's plaza, PLAY circle, dispatch and PAINT shop, the kiosks, the warehouses, the TOP MOVERS
board) and tools/village/render.mjs draws each view with three.js in headless Chromium (tools/village/render.html: a warm
afternoon, a perspective camera, soft shadows, a light haze). The parts look only: no signs' words (the word PLAY over the
circle is a BillboardGui: not drawn; the one on its floor is), no Blender imports.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/lobby/views.py <luau> <three.module.min.js> [--out DIR]

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Chromium from
CHROMIUM (default /opt/pw-browsers/chromium); --out defaults to design/lobby.
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(GAME / "tools" / "sandbox-map"))
sys.path.insert(0, str(GAME / "tools" / "islands"))
import render as sandbox_map  # noqa: E402  (tools/sandbox-map/render.py: export_world)
from views import shape_of  # noqa: E402  (tools/islands/views.py: a part's shape for render.html)

# The lobby's middle (design/lobby/plan.py OX, OZ: its bounds' middle): the views are placed from it.
BOUNDS = json.loads((GAME / "design" / "lobby" / "plan.json").read_text(encoding="utf-8"))["bounds"]
OX, OZ = (BOUNDS["x0"] + BOUNDS["x1"]) / 2, (BOUNDS["z0"] + BOUNDS["z1"]) / 2

# The views: name, caption, the camera (from, to: studs from the lobby's middle, y up), its fov.
VIEWS = [  # (10.4: the PLAY circle at (0, 59) from the middle, the spawn at (0, 95), the plots' front walls at z -18)
    ("view-overview", "The lobby from the south: the plaza with the PLAY circle, the four plots and their warehouses", (0, 210, 330), (0, 0, -10), 55),
    ("view-plaza", "From the spawn: the PLAY circle in the plaza, the plots behind it", (0, 14, 108), (0, 3, 40), 62),
    ("view-play", "The PLAY circle close: its glowing ring, PLAY written on its floor, its four lit posts", (26, 11, 86), (0, 2, 59), 55),
    ("view-plots", "The four plots along the north edge, the DISPATCH kiosk and the PLAY circle in front", (0, 50, 105), (0, 6, -70), 60),
    ("view-west", "The west side: the fountain, the TOP MOVERS board and the DISPATCH kiosk", (-40, 28, 100), (-150, 4, 58), 58),
    ("view-paint", "The east side: the PAINT shop's booth by plots 3 and 4 (the Auction House east of it is not in this export)", (20, 28, 100), (100, 4, 55), 58),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("--out", type=Path, default=GAME / "design" / "lobby")
    args = parser.parse_args()
    luau = str(Path(args.luau).resolve())
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        sandbox_map.export_world(luau, tmp)
        world = json.loads((tmp / "world.json").read_text())
        near = 900  # (only what stands near the lobby: 10.8 the other islands are hundreds of studs off it)
        parts = [{"p": p["p"], "r": p["r"], "s": p["s"], "c": p["c"], "t": p["t"], "mat": p["mat"], "shape": shape_of(p)}
                 for p in world if not p["group"].startswith("Sandbox/Boundary") and p["t"] < 0.95
                 and abs(p["p"][0] - OX) < near and abs(p["p"][2] - OZ) < near]
        shots = []
        for name, caption, eye, look, fov in VIEWS:
            shots.append({"name": name, "caption": caption, "subject": 0, "parts": parts,
                          "view": {"w": 1920, "h": 1080, "from": [OX + eye[0], eye[1], OZ + eye[2]],
                                   "to": [OX + look[0], look[1], OZ + look[2]], "fov": fov}})
        site = tmp / "site"
        site.mkdir()
        shutil.copy(GAME / "tools" / "village" / "render.html", site / "render.html")
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        (tmp / "shots.json").write_text(json.dumps(shots))
        args.out.mkdir(parents=True, exist_ok=True)
        subprocess.run(["node", str(GAME / "tools" / "village" / "render.mjs"), str(site), str(tmp / "shots.json"), str(args.out.resolve())], check=True)
    print(f"lobby views: {len(VIEWS)} views in {args.out}")


if __name__ == "__main__":
    main()
