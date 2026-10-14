#!/usr/bin/env python3
"""8.0.4: the warehouse's five Blender levels (design/blender-warehouse) against the sandbox's plot, without Studio.

Reads design/blender-warehouse/roblox/ZDCWarehouseArt.json (written by warehouse.py: each level's size, door, walls and
every detail's box, the level's origin the roller door's middle on the ground) and the game's plot (shared/SandboxMap's
plot 1, Config.Warehouse) and levels (8.3: Config.WarehouseLevels, shared/WarehouseLayout.luau's stands) through the Luau
CLI, and checks, for every level standing where the warehouse stands (its door on the plot's door):
  - 8.3: every level is the game's level (Config.WarehouseLevels: its size, its door, its roof's rise); level 4 is 8.0's
    warehouse (SandboxMap's plot warehouse, DoorWidth);
  - each level is bigger than the one before, its door at least as wide, and it stays inside the plot;
  - nothing of it stands where the plot needs room: the van's UNLOAD HERE bay (Config.Warehouse.Bay round the van's
    spot), the way in through the roller door, the Moving contracts board, the player's spawn;
  - the floor inside is clear for the stands (nothing standing on it but the floor), and its walls are listed (the
    boxes a game would collide with); 8.3: the game's stands at that level (WarehouseLayout.stands) stand on that floor;
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
local WarehouseLayout = require("./WarehouseLayout")
local p = SandboxMap.Plots[1]
local w = p.warehouse
local wall = p.door.z
local function out(z) return z - wall end -- (studs out of the front wall: the plot's door looks south, +z)
local levels = {}
for n, def in Config.WarehouseLevels.List do
	local stands = {}
	for _, s in WarehouseLayout.stands(p, n) do
		table.insert(stands, string.format("[%g,%g,%g,%g]", s.x - s.sx / 2 - p.door.x, s.x + s.sx / 2 - p.door.x, out(s.z - s.sz / 2), out(s.z + s.sz / 2)))
	end
	table.insert(levels, string.format('{"size":[%g,%g,%g],"door":[%g,%g],"rise":%g,"roof":"%s","stands":[%s]}', def.size[1], def.size[2], def.size[3],
		def.door[1], def.door[2], def.rise, def.roof, table.concat(stands, ",")))
end
print(string.format('{"x":%g,"wall":%g,"rect":[%g,%g,%g,%g],"size":[%g,%g,%g],"door":[%g,%g],"van":[%g,%g],"bay":[%g,%g],"board":[%g,%g],"spawn":[%g,%g],"levels":[%s]}',
	p.door.x, wall, p.rect.x0 - p.door.x, p.rect.x1 - p.door.x, out(p.rect.z0), out(p.rect.z1), w.sx, w.sy, w.sz,
	SandboxMap.DoorWidth, WarehouseLayout.door(p, 4).height, p.vanSpot.x - p.door.x, out(p.vanSpot.z),
	Config.Warehouse.Bay[1], Config.Warehouse.Bay[2], p.board.x - p.door.x, out(p.board.z), p.spawn.x - p.door.x, out(p.spawn.z), table.concat(levels, ",")))
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
    assert len(game["levels"]) == len(levels), (len(game["levels"]), "Config.WarehouseLevels' levels are not the model's")
    for n, lv in enumerate(levels, 1):
        W, H, D = lv["size"]
        dw, dh = lv["door"]
        mine = game["levels"][n - 1]
        assert mine["size"] == lv["size"] and mine["door"] == lv["door"] and mine["roof"] == lv["roof"] \
            and abs(lv["marks"]["top"][1] - (H if lv["roof"] == "shed" else H + mine["rise"])) < 1e-4, (n, mine, "Config.WarehouseLevels' level is not the model's")
        if n > 1:
            pw, _, pd = levels[n - 2]["size"]
            assert W > pw and D > pd and dw >= levels[n - 2]["door"][0], (n, "not bigger than the level before")
        rooms = dict(keep)
        # (the door to the van's back, as high as a carried piece; a sloped roof's box reaches lower than the roof does)
        rooms["the way in"] = ((-dw / 2, dw / 2), (0, game["van"][1] - 11), (0.25, min(dh - 0.5, 9)))
        rooms["the floor inside"] = ((-W / 2 + 1.5, W / 2 - 1.5), (-D + 1.5, -2), (0.25, min(H - 2, 8)))  # (along the walls: their own)
        # 8.3: the game's stands at this level stand on that floor, inside its walls (x across, out of the front wall)
        for k, (x0, x1, z0, z1) in enumerate(mine["stands"], 1):
            assert x0 >= -W / 2 + 1 - 1e-6 and x1 <= W / 2 - 1 + 1e-6 and z0 >= -D + 1 - 1e-6 and z1 <= -1 + 1e-6, (n, f"stand {k} outside the walls", (x0, x1, z0, z1))
            rooms[f"stand {k}"] = ((x0, x1), (z0, z1), (0.25, 8))
        for d in lv["details"]:
            x, z, y = footprint(d)
            assert x[0] >= rect[0] - 1e-3 and x[1] <= rect[1] + 1e-3 and z[0] >= rect[2] - 1e-3 and z[1] <= rect[3] + 1e-3, \
                (n, d["name"], x, z, "outside the plot")
            for room, (rx, rz, ry) in rooms.items():
                if hits(x, rx) and hits(z, rz) and hits(y, ry):
                    raise AssertionError((n, d["name"], f"stands in {room}", x, z, y))
        assert len(lv["collide"]) >= 5, (n, "its walls")
        tris = sum(p["triangles"] for p in manifest["pieces"].values() if p["level"] == n)
        lines.append(f"{n} {lv['name']} {W:g}×{H:g}×{D:g} door {dw:g}×{dh:g}, {len(mine['stands'])} stands ({tris} tris)")
    for p in manifest["pieces"].values():
        assert p["triangles"] <= 10000, p
    print("Warehouse levels PASS: " + "; ".join(lines) + f". Every level is Config.WarehouseLevels' (level 4 8.0's warehouse); "
          "every level on the plot, clear of the van's bay, the way in, the Moving board, the spawn, the floor for the stands "
          "and the game's stands at that level")


if __name__ == "__main__":
    main()
