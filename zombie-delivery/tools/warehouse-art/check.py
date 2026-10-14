#!/usr/bin/env python3
"""8.0.4: the warehouse's five Blender levels (design/blender-warehouse) against the sandbox's plot, without Studio.

Reads design/blender-warehouse/roblox/ZDCWarehouseArt.json (written by warehouse.py: each level's size, door, walls and
every detail's box, the level's origin the roller door's middle on the ground) and the game's plot (shared/SandboxMap's
plot 1, Config.Warehouse) through the Luau CLI, and checks, for every level standing where the warehouse stands (its
door on the plot's door):
  - level 4 is the game's warehouse today (SandboxMap's plot warehouse, DoorWidth, Config.Warehouse.DoorHeight);
  - each level is bigger than the one before, its door at least as wide, and it stays inside the plot;
  - nothing of it stands where the plot needs room: the van's UNLOAD HERE bay (Config.Warehouse.Bay round the van's
    spot), the way in through the roller door, the Moving contracts board, the player's spawn;
  - the floor inside is clear for the stands (nothing standing on it but the floor), and its walls are listed (the
    boxes a game would collide with);
  - at most 10,000 triangles a piece.

    python3 zombie-delivery/tools/warehouse-art/check.py <luau>
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "src" / "shared"
MANIFEST = ROOT / "design/blender-warehouse/roblox/ZDCWarehouseArt.json"

PLOT = r'''
local SandboxMap = require("./SandboxMap")
local Config = require("./Config")
local p = SandboxMap.Plots[1]
local w = p.warehouse
local wall = p.door.z
local function out(z) return z - wall end -- (studs out of the front wall: the plot's door looks south, +z)
print(string.format('{"x":%g,"wall":%g,"rect":[%g,%g,%g,%g],"size":[%g,%g,%g],"door":[%g,%g],"van":[%g,%g],"bay":[%g,%g],"board":[%g,%g],"spawn":[%g,%g]}',
	p.door.x, wall, p.rect.x0 - p.door.x, p.rect.x1 - p.door.x, out(p.rect.z0), out(p.rect.z1), w.sx, w.sy, w.sz,
	SandboxMap.DoorWidth, Config.Warehouse.DoorHeight, p.vanSpot.x - p.door.x, out(p.vanSpot.z),
	Config.Warehouse.Bay[1], Config.Warehouse.Bay[2], p.board.x - p.door.x, out(p.board.z), p.spawn.x - p.door.x, out(p.spawn.z)))
'''


def plot(luau: str) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for source in SHARED.glob("*.luau"):
            (tmp / source.name).write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text()))
        (tmp / "plot.luau").write_text(PLOT)
        r = subprocess.run([luau, "plot.luau"], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
    return json.loads(r.stdout.strip().splitlines()[-1])


def footprint(detail):
    """A detail's box on the plot: x across (east +, as the plot's), out of the front wall (south +), up."""
    (gx, gy, gz), (sx, sy, sz) = detail["center"], detail["size"]
    # (the manifest's game axes: x right = Blender's -x, z back into the building; Blender's x is east on the plot)
    return (-gx - sx / 2, -gx + sx / 2), (-gz - sz / 2, -gz + sz / 2), (gy - sy / 2, gy + sy / 2)


def hits(a, b, margin=0.01):
    return a[0] < b[1] - margin and b[0] < a[1] - margin


def main():
    luau = str(Path(sys.argv[1]).resolve())
    game = plot(luau)
    manifest = json.loads(MANIFEST.read_text())
    levels = [manifest["levels"][k] for k in sorted(manifest["levels"], key=int)]
    assert len(levels) == 5, len(levels)
    four = levels[3]
    assert four["size"] == game["size"], (four["size"], game["size"], "level 4 is not the game's warehouse")
    assert four["door"] == game["door"], (four["door"], game["door"], "level 4's door is not the game's")
    rect = game["rect"]  # x0, x1 (across), and out of the wall: z0 (the back: negative), z1 (the front)
    hw, length = game["bay"][0] / 2, game["bay"][1]
    keep = {
        "the van's bay": ((game["van"][0] - hw, game["van"][0] + hw), (game["van"][1] - length / 2, game["van"][1] + length / 2), (0.25, 12)),
        "the Moving board": ((game["board"][0] - 2.5, game["board"][0] + 2.5), (game["board"][1] - 0.5, game["board"][1] + 1.5), (0, 9)),  # (a stud out of the wall)
        "the spawn": ((game["spawn"][0] - 2, game["spawn"][0] + 2), (game["spawn"][1] - 2, game["spawn"][1] + 2), (0, 7)),
    }
    lines = []
    for n, lv in enumerate(levels, 1):
        W, H, D = lv["size"]
        dw, dh = lv["door"]
        if n > 1:
            pw, _, pd = levels[n - 2]["size"]
            assert W > pw and D > pd and dw >= levels[n - 2]["door"][0], (n, "not bigger than the level before")
        rooms = dict(keep)
        # (the door to the van's back, as high as a carried piece; a sloped roof's box reaches lower than the roof does)
        rooms["the way in"] = ((-dw / 2, dw / 2), (0, game["van"][1] - 11), (0.25, min(dh - 0.5, 9)))
        rooms["the floor inside"] = ((-W / 2 + 1.5, W / 2 - 1.5), (-D + 1.5, -2), (0.25, min(H - 2, 8)))  # (along the walls: their own)
        for d in lv["details"]:
            x, z, y = footprint(d)
            assert x[0] >= rect[0] - 1e-3 and x[1] <= rect[1] + 1e-3 and z[0] >= rect[2] - 1e-3 and z[1] <= rect[3] + 1e-3, \
                (n, d["name"], x, z, "outside the plot")
            for room, (rx, rz, ry) in rooms.items():
                if hits(x, rx) and hits(z, rz) and hits(y, ry):
                    raise AssertionError((n, d["name"], f"stands in {room}", x, z, y))
        assert len(lv["collide"]) >= 5, (n, "its walls")
        tris = sum(p["triangles"] for p in manifest["pieces"].values() if p["level"] == n)
        lines.append(f"{n} {lv['name']} {W:g}×{H:g}×{D:g} door {dw:g}×{dh:g} ({tris} tris)")
    for p in manifest["pieces"].values():
        assert p["triangles"] <= 10000, p
    print("Warehouse levels PASS: " + "; ".join(lines) + f". Level 4 is the game's warehouse; every level on the plot, clear "
          "of the van's bay, the way in, the Moving board, the spawn and the floor for the stands")


if __name__ == "__main__":
    main()
