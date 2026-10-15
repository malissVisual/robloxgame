#!/usr/bin/env python3
"""8.7.1: the house's fixtures in the owner's Blender model (server/FixtureMesh.luau) on real interiors, without Studio.

Simulates the Roblox import of design/blender-fixtures/roblox/ZDCFixtureArt.fbx from its manifest (ZDCFixtureArt.json:
every piece's box in its kind's frame, written by fixtures.py; design/blender-fixtures/KONTRAKT.md): the importer turns
the model a quarter round, makes it 3 times bigger and moves it; FixtureMesh must find the markers, undo that and dress
every fixture server/HouseInterior.luau builds (shared/HouseLayout.luau plans of a few seeds of the kinds "house" and
"big", and a farm). Checks:
  - the manifest: every kind of the contract's table at its size, every piece "<kind>_<finish>" a finish of
    FixtureMesh.Looks (and the manifest's "finishes", when it has them, FixtureMesh.Looks exactly: the colours,
    materials, palette, shine and see-through; tools/fixtures-art/looks.py --write copies them), at most 10,000 triangles a
    piece, about 1,500 a kind (the Kachelofen 3,000);
  - every fixture of every kind dressed (its Model "Fixture_<kind>", attribute Fixture, MeshArt), every piece of the
    kind once, where the manifest has it in the fixture's frame (the import's turn and scale undone);
  - the fixture's solid parts kept where they were, still colliding and queried, hidden and shadowless; the others
    gone; no mesh physical (anchored, no collision, no query, no touch) nor wearing the importer's SurfaceAppearance;
  - the palette finishes (tile, tile2, pine, cushion) in the colour of the part the house rolled (Stove, Upper, Seat or
    StoveBench, Cushion), every other finish its look's;
  - every piece inside its kind's box but the reaches today's look has (the sink's and the tub's taps, the stove's
    burners, the workbench's pegboard and vise) and the contract's (the basin's mirror to 6.9, the hood's flue to the
    ceiling, the corner shelf's candle and flowers up to the wall decor), never into the room in front of the box nor
    into the wall behind it (0.05), nothing through the ceiling;
  - the interiors within their part budgets (Config.Furniture.InteriorMaxParts, Big.InteriorMaxParts, Farm's) with the
    dress; a Neon piece (the fire's glow) at most Config.SandboxLight.Caps.NeonArea on its biggest face;
  - the rest of the interior unchanged by the dress; the farm's counters (another size) and its own Kachelofen as they
    were;
  - no import, an import physics threw about (one piece turned), a mirrored one: every interior exactly as without it;
    a fixture of another size (the import's counter box 0.2 off, a direct dress of a wrong size): its parts as they
    were, the other kinds dressed.
Until the blender agent's manifest exists (design/blender-fixtures/roblox/ZDCFixtureArt.json) the check runs on a
stand-in made here from the contract's table (plain boxes, standin_manifest below: a test fixture, not the model).

    python3 zombie-delivery/tools/fixtures-art/check.py <luau> [ZDCFixtureArt.json | --standin]
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "src" / "shared"
MANIFEST = ROOT / "design/blender-fixtures/roblox/ZDCFixtureArt.json"
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')
MOCKED = ("FurnitureLooks", "HouseLayout", "Farm")
# The contract's table: kind → its box (along the wall, height, depth).
KINDS = {
    "counter": (4.5, 3, 2.6), "stove": (3, 3, 2.6), "sink": (9, 3, 2.6), "cabinets": (4.5, 3, 1.4), "hood": (3, 2.2, 1.8),
    "corner_bench": (7, 3.4, 1.6), "bench": (2.4, 3.4, 1.6), "corner_shelf": (2.2, 1.4, 2.2), "tub": (7.2, 2.2, 3.4),
    "toilet": (1.8, 3.2, 2.8), "basin": (2.6, 3.2, 1.8), "kachelofen": (6, 6.6, 3.2), "workbench": (6.4, 3.2, 2.4),
    "shelves": (5, 7, 1.6), "garage_door": (12, 8.5, 0.3),
}
PALETTE = {"tile": ("Stove",), "tile2": ("Upper",), "pine": ("Seat", "StoveBench"), "cushion": ("Cushion",)}
TRIANGLES = {"kind": 3000, "kachelofen": 4000, "piece": 10000}  # (8.7.1: the lead relaxed the contract's 1,500: the whole model about 22,000)
BASIN_MIRROR = 6.9  # the contract: the basin's mirror up to y 6.9 in its frame
TOL = 0.05  # the contract's: into the wall behind (and here: into the room in front) at most this
RUNS = {  # mode → the interiors it builds (kind, seed)
    "none": [("house", s) for s in (1, 2, 3, 4, 5)] + [("big", s) for s in (1, 2, 3)] + [("farm", 1)],
    "art": [("house", s) for s in (1, 2, 3, 4, 5)] + [("big", s) for s in (1, 2, 3)] + [("farm", 1)],
    "scattered": [("house", 1), ("big", 1)],
    "mirrored": [("house", 2), ("big", 2)],
    "wrongbox": [("house", 3), ("big", 3)],
}


def standin_manifest() -> dict:
    """A stand-in ZDCFixtureArt.json from the contract's table: plain boxes per kind (a couple of finishes each, the
    palette ones among them, some of the allowed reaches). A test fixture until fixtures.py's manifest exists."""
    boxes = {}  # kind → [(finish, name, (cx, cy, cz), (sx, sy, sz))]

    def add(kind, finish, name, c, s):
        boxes.setdefault(kind, []).append((finish, name, c, s))

    for kind in ("counter", "sink"):
        w, h, d = KINDS[kind]
        add(kind, "cabinet", "Skříňka", (0, 1.4, 0.075), (w, 2.8, d - 0.15))
        add(kind, "worktop", "Pracovní deska", (0, 2.9, 0), (w, 0.2, d))
    add("sink", "steel", "Dřez", (0, 3.01, -0.1), (1.8, 0.06, 1.3))
    add("sink", "chrome", "Baterie", (0, 3.4, 0.75), (0.15, 0.8, 0.15))
    w, h, d = KINDS["stove"]
    add("stove", "enamel", "Sporák", (0, 1.45, 0), (w, 2.9, d))
    add("stove", "blackglass", "Varná deska", (0, 2.95, 0.05), (w - 0.2, 0.1, d - 0.3))
    add("stove", "iron", "Dvířka trouby", (0, 1.3, -d / 2 + 0.05), (w - 0.5, 1.5, 0.08))
    w, h, d = KINDS["cabinets"]
    add("cabinets", "cabinet", "Horní skříňky", (0, h / 2, 0), (w, h, d))
    w, h, d = KINDS["hood"]
    add("hood", "steel", "Digestoř", (0, 0.3, 0), (w, 0.6, d))
    add("hood", "steel", "Komín digestoře", (0, 0.6 + 4.4 / 2, d * 0.2), (w * 0.45, 4.4, d * 0.55))  # (to the ceiling)
    w, h, d = KINDS["corner_bench"]
    add("corner_bench", "pine", "Sedák", (0, 0.75, -0.15), (w, 1.5, d - 0.3))
    add("corner_bench", "pine", "Opěradlo", (0, (1.5 + h) / 2, d / 2 - 0.15), (w, h - 1.5, 0.3))
    add("corner_bench", "cushion", "Polštář", (0, 1.58, -0.25), (w - 0.3, 0.16, d - 0.6))
    w, h, d = KINDS["bench"]
    add("bench", "pine", "Lavice", (0, h / 2, 0), (w, h, d))
    w, h, d = KINDS["corner_shelf"]
    add("corner_shelf", "woodwork", "Polička", (0, 0.075, 0), (w, 0.15, d))
    add("corner_shelf", "candle", "Svíčka", (w / 2 - 0.45, 0.6, d / 2 - 0.45), (0.3, 0.9, 0.3))
    add("corner_shelf", "flower", "Sušené květiny", (w / 2 - 0.5, 0.95, d / 2 - 1.05), (0.7, 1.6, 0.7))  # (over its box)
    w, h, d = KINDS["tub"]
    add("tub", "porcelain", "Vana", (0, h / 2, 0), (w, h, d))
    add("tub", "water", "Voda", (0, h - 0.2, 0), (w - 0.6, 0.06, d - 0.6))
    add("tub", "chrome", "Baterie", (w / 2 - 0.6, h + 0.3, d / 2 - 0.4), (0.3, 0.6, 0.3))  # (today's tap, over the tub)
    w, h, d = KINDS["toilet"]
    add("toilet", "porcelain", "Záchod", (0, 1.55, 0), (1.6, 3.1, d))
    add("toilet", "chrome", "Splachování", (0, 3.15, d / 2 - 0.35), (0.2, 0.1, 0.2))
    w, h, d = KINDS["basin"]
    add("basin", "porcelain", "Umyvadlo", (0, 1.55, 0), (w, 3.1, d))
    add("basin", "chrome", "Baterie", (0, 3.35, d / 2 - 0.3), (0.15, 0.5, 0.15))
    add("basin", "mirror", "Zrcadlo", (0, 5.4, d / 2 - 0.12), (2.1, 2.7, 0.05))
    add("basin", "woodwork", "Rám zrcadla", (0, 5.4, d / 2 - 0.05), (2.4, 3.0, 0.1))
    w, h, d = KINDS["kachelofen"]
    add("kachelofen", "tile", "Kachle", (0, 1.85, 0.65), (w - 0.8, 3.7, 1.9))
    add("kachelofen", "tile2", "Horní patro", (0, 4.9, 0.9), (w - 2, 2.4, 1.4))
    add("kachelofen", "grout", "Římsa", (0, 6.35, 0.75), (w - 1.6, 0.5, 1.7))
    add("kachelofen", "iron", "Dvířka", (0, 2.4, -0.35), (1.3, 1.1, 0.1))
    add("kachelofen", "glow", "Žhavá škvíra", (0, 2.15, -0.42), (0.9, 0.14, 0.05))
    add("kachelofen", "pine", "Lavice u kamen", (0, 0.75, -1.05), (w, 1.5, 1.1))
    w, h, d = KINDS["workbench"]
    add("workbench", "wood", "Ponk", (0, h / 2, 0), (w, h, d))
    add("workbench", "board", "Děrovaná deska", (0, h + 2.1, d / 2 - 0.06), (w, 3.4, 0.12))
    add("workbench", "vise", "Svěrák", (w / 2 - 0.6, h + 0.25, -d / 2 + 0.4), (0.7, 0.5, 0.6))
    w, h, d = KINDS["shelves"]
    add("shelves", "metal", "Regál", (0, h / 2, 0), (w, h, d))
    add("shelves", "card", "Krabice", (-0.1, 2.98, 0), (3.4, 5.0, d - 0.3))
    w, h, d = KINDS["garage_door"]
    add("garage_door", "door", "Vrata", (0, h / 2, 0), (w, h, d))
    add("garage_door", "rubber", "Drážky", (0, h / 2, -d / 2 + 0.03), (w, h / 3 + 0.12, 0.06))
    manifest = {"fixtures": {}, "pieces": {}, "details": [], "standin": True}
    for kind, rows in boxes.items():
        names = []
        for finish, name, c, s in rows:
            manifest["details"].append({"kind": kind, "name": name, "finish": finish, "center": list(c), "size": list(s)})
            piece = f"{kind}_{finish}"
            lo = [c[i] - s[i] / 2 for i in range(3)]
            hi = [c[i] + s[i] / 2 for i in range(3)]
            have = manifest["pieces"].get(piece)
            if have:  # (one mesh per kind and finish: the boxes' union)
                lo = [min(lo[i], have["center"][i] - have["size"][i] / 2) for i in range(3)]
                hi = [max(hi[i], have["center"][i] + have["size"][i] / 2) for i in range(3)]
            else:
                names.append(piece)
            tris = (have["triangles"] if have else 0) + 12
            manifest["pieces"][piece] = {"kind": kind, "finish": finish, "center": [(a + b) / 2 for a, b in zip(lo, hi)],
                                         "size": [b - a for a, b in zip(lo, hi)], "triangles": tris}
        manifest["fixtures"][kind] = {"size": list(KINDS[kind]), "pieces": names,
                                      "triangles": sum(manifest["pieces"][n]["triangles"] for n in names)}
    return manifest


# What the recorder lacks for FixtureMesh (as tools/furniture/mesh-check.py): CFrame ± Vector3, CFrame.fromMatrix, its
# axes, MeshPart as a BasePart, a ServerStorage. Then the import (or none), the interiors, the checks' lines.
HARNESS = r'''
local M = require("./ItemMock")
local F = getmetatable(M.CFrame.identity)
F.__add = function(a, v) return setmetatable({ Position = a.Position + v, R = a.R }, F) end
F.__sub = function(a, v) return setmetatable({ Position = a.Position - v, R = a.R }, F) end
M.CFrame.fromMatrix = function(p, x, y, z) return setmetatable({ Position = p, R = { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z } }, F) end
local V3 = M.Vector3.new
F.__index = function(cf, k)
	if k == "RightVector" then local r = cf.R; return V3(r[1], r[4], r[7]) end
	if k == "UpVector" then local r = cf.R; return V3(r[2], r[5], r[8]) end
	return rawget(F, k)
end
local O = getmetatable(M.Instance.new("Part"))
local isA = O.IsA
O.IsA = function(self, c) if c == "BasePart" and self.ClassName == "MeshPart" then return true end return isA(self, c) end
local storage = M.Instance.new("Folder")
local get = M.game.GetService
M.game.GetService = function(self, name) if name == "ServerStorage" then return storage end return get(self, name) end
local MODE, SPEC = ...
local art = M.Instance.new("Model")
if MODE ~= "none" then
	art.Name = "ZDCFixtureArt"
	art.Parent = M.workspace -- (as the importer leaves it: FixtureMesh moves it to ServerStorage)
	-- The import: a quarter turn about up (Roblox's x → -z, z → x), 3 times the size, moved. The importer's own axes
	-- from Blender's: (x, z, -y). Mirrored: the world's z the other way.
	local K, MOVE = 3, M.Vector3.new(-37, 6, 52)
	local flip = if MODE == "mirrored" then -1 else 1
	local turned = false
	for _, row in require("./pieces") do
		local name = row[1]
		local x, y, z = row[2], row[4], -row[3]
		local sx, sy, sz = row[5], row[7], row[6]
		if MODE == "wrongbox" and name == "mark_counter_box" then
			x -= 0.1 -- (the counter's box 0.2 wider than the plan's)
		end
		local p = M.Instance.new(if string.sub(name, 1, 5) == "mark_" then "Part" else "MeshPart")
		p.Name = name
		p.CFrame = M.CFrame.new(z * K + MOVE.X, y * K + MOVE.Y, (-x * K + MOVE.Z) * flip)
		p.Size = M.Vector3.new(sz * K, sy * K, sx * K)
		p.Anchored = false -- (as Studio's Import 3D leaves them)
		if MODE == "scattered" and not turned and p.ClassName == "MeshPart" then
			turned = true
			p.CFrame = p.CFrame * M.CFrame.Angles(0.5, 0.2, 0) -- (thrown about by physics before the game read it)
		end
		local skin = M.Instance.new("SurfaceAppearance")
		skin.Parent = p
		p.Parent = art
	end
end
local FixtureMesh = require("./FixtureMesh")
local HouseInterior = require("./HouseInterior")
local HouseLayout = require("./HouseLayout")
local Config = require("./Config")
local function f(cf) local r = cf.R; return string.format("[%.6f,%.6f,%.6f,%.7f,%.7f,%.7f,%.7f,%.7f,%.7f,%.7f,%.7f,%.7f]", cf.Position.X, cf.Position.Y, cf.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]) end
local function c(col) return string.format("[%d,%d,%d]", math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5)) end
local function v(x) return string.format("[%.6f,%.6f,%.6f]", x.X, x.Y, x.Z) end
local function b(x) return tostring(x == true) end
if MODE == "none" then
	for name, look in FixtureMesh.Looks do
		local palette = {}
		for _, p in look.palette or {} do table.insert(palette, string.format("%q", p)) end
		print(string.format('LOOK {"finish":"%s","color":%s,"material":"%s","palette":[%s],"t":%g,"r":%g}', name, c(look.color), tostring(look.material),
			table.concat(palette, ","), look.transparency or 0, look.reflectance or 0))
	end
	for kind in FixtureMesh.Kinds do
		print(string.format('KIND {"kind":"%s"}', kind))
	end
end
for spec in string.gmatch(SPEC, "[^;]+") do
	local kind, seed = string.match(spec, "^(%a+):(%d+)$")
	seed = tonumber(seed)
	local run = kind .. ":" .. seed
	local plan = HouseLayout.plan(seed, kind)
	local origin = HouseInterior.slot(({ house = 0, big = 10, farm = 20 })[kind] + seed) -- (the same place in every run)
	local interior = HouseInterior.build(plan, origin)
	local decor = interior:FindFirstChild("Decor")
	local byKind, extra = {}, 0
	for _, child in decor:GetChildren() do
		if child.ClassName == "Model" and child:GetAttribute("Fixture") ~= nil then
			local list = byKind[child:GetAttribute("Fixture")] or {}
			byKind[child:GetAttribute("Fixture")] = list
			table.insert(list, child)
		elseif child.ClassName == "Model" and string.sub(child.Name, 1, 8) == "Fixture_" then
			extra += 1
		end
	end
	local fid, seen, owner = 0, {}, {}
	local used = {}
	for _, fx in plan.fixtures do
		if FixtureMesh.Kinds[fx.kind] then
			used[fx.kind] = (used[fx.kind] or 0) + 1
			local model = (byKind[fx.kind] or {})[used[fx.kind]]
			fid += 1
			print(string.format('FIX {"run":"%s","fid":%d,"kind":"%s","has":%s,"name":"%s","attr":"%s","dressed":%s,"at":%s,"size":%s,"origin":%s,"parent":"%s"}',
				run, fid, fx.kind, b(model ~= nil), if model then model.Name else "", tostring(if model then model:GetAttribute("Fixture") else ""),
				b(model ~= nil and model:GetAttribute("MeshArt") == true), f(origin * fx.at), v(fx.size), v(origin.Position), if model and model.Parent then model.Parent.Name else ""))
			if model then
				seen[model] = true
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						owner[d] = fid
						print(string.format('PART {"run":"%s","fid":%d,"class":"%s","name":"%s","cf":%s,"size":%s,"t":%g,"color":%s,"material":"%s","collide":%s,"query":%s,"touch":%s,"anchored":%s,"shadow":%s,"skin":%s}',
							run, fid, d.ClassName, d.Name, f(d.CFrame), v(d.Size), d.Transparency or 0, c(d.Color), tostring(d.Material), b(d.CanCollide), b(d.CanQuery),
							b(d.CanTouch), b(d.Anchored), b(d.CastShadow), b(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil)))
					end
				end
			end
		end
	end
	for _, list in byKind do
		for _, model in list do
			extra += if seen[model] then 0 else 1
		end
	end
	local parts = 0
	for _, d in interior:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			-- (every part of the interior, to compare runs: its fixture's id or 0, what it is, where, how it looks)
			print(string.format("ALL\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%g\t%s\t%s\t%s\t%s\t%s", run, owner[d] or 0, d.ClassName, d.Name, f(d.CFrame), v(d.Size),
				c(d.Color), d.Transparency or 0, tostring(d.Material), b(d.CanCollide), b(d.CanQuery), b(d.CastShadow), tostring(d.Shape)))
		end
	end
	print(string.format('RUN {"run":"%s","kind":"%s","parts":%d,"extra":%d,"ceiling":%g,"origin":%s}', run, kind, parts, extra, plan.ceiling, v(origin.Position)))
	interior:Destroy()
end
-- A fixture of another size and a kind the model does not make, dressed straight: left as they were.
local probe = M.Instance.new("Model")
local solid = M.Instance.new("Part")
solid.Name, solid.CanCollide = "Cabinet", true
solid.Parent = probe
local loose = M.Instance.new("Part")
loose.Name, loose.CanCollide = "Basin", false
loose.Parent = probe
local wrong = FixtureMesh.dress(probe, "counter", M.CFrame.new(1, 2, 3), M.Vector3.new(4.4, 3, 2.6))
local unknown = FixtureMesh.dress(probe, "rug", M.CFrame.new(1, 2, 3), M.Vector3.new(3, 0.08, 2))
print(string.format('PROBE {"wrong":%s,"unknown":%s,"children":%d,"t":%g,"has":%s}', b(wrong), b(unknown), #probe:GetChildren(), solid.Transparency, b(FixtureMesh.has("counter"))))
local F_ = Config.Furniture
print(string.format('META {"moved":%s,"house":%d,"big":%d,"farm":%d,"neonArea":%g,"ceiling":%g,"decor":%g,"shelf":%g}', b(art.Parent == storage and MODE ~= "none"),
	F_.InteriorMaxParts, F_.Big.InteriorMaxParts, F_.Farm.InteriorMaxParts, Config.SandboxLight.Caps.NeonArea, F_.Ceiling, F_.Alpine.Decor, F_.Alpine.Shelf[2]))
print("ALL DONE")
'''


def stage(tmp: Path, manifest: dict):
    for source in list(SHARED.glob("*.luau")) + list(SHARED.glob("Layouts/*.luau")):
        text = re.sub(r"require\(script\.Parent\.(?:Parent\.|Layouts\.)?(\w+)\)", r'require("./\1")', source.read_text())
        (tmp / source.name).write_text(PREFIX + text if source.stem in MOCKED else text)
    text = (ROOT / "src/server/HouseInterior.luau").read_text()
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', text)
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
    (tmp / "HouseInterior.luau").write_text(PREFIX + "local game = M.game\n" + text)
    for module in ("FurnitureMesh", "FixtureMesh"):
        text = (ROOT / "src/server" / (module + ".luau")).read_text()
        text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', text)
        (tmp / (module + ".luau")).write_text(PREFIX + "local game, workspace = M.game, M.workspace\nlocal warn = print\n" + text)
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    # Blender's coordinates of each piece's box: each kind in a cell of its own along a row (the game's x = Blender's
    # -x, y = z, z = y), its markers at the cell (the frame's origin) and at the box's corner (W / 2, H, D / 2).
    cells = {kind: (-30.0 * i, 12.0, 0.5) for i, kind in enumerate(sorted(manifest["fixtures"]))}
    rows = []
    for name, p in manifest["pieces"].items():
        gx, gy, gz = p["center"]
        sx, sy, sz = p["size"]
        cx, cy, cz = cells[p["kind"]]
        rows.append([name, cx - gx, cy + gz, cz + gy, sx, sz, sy])
    for kind, fx in manifest["fixtures"].items():
        cx, cy, cz = cells[kind]
        w, h, d = fx["size"]
        rows.append(["mark_" + kind, cx, cy, cz, 0.3, 0.3, 0.3])
        rows.append(["mark_" + kind + "_box", cx - w / 2, cy + d / 2, cz + h, 0.3, 0.3, 0.3])
    for name, at in (("mark_o", (0, 0, 0)), ("mark_x", (-10, 0, 0)), ("mark_y", (0, 0, 10)), ("mark_z", (0, 10, 0))):
        rows.append([name, *at, 0.3, 0.3, 0.3])
    body = ",\n".join("{%s}" % ",".join([json.dumps(r[0])] + [repr(float(x)) for x in r[1:]]) for r in rows)
    (tmp / "pieces.luau").write_text("return {\n" + body + "\n}\n")
    (tmp / "harness.luau").write_text(HARNESS)


def run(luau: str, tmp: Path, mode: str):
    spec = ";".join(f"{k}:{s}" for k, s in RUNS[mode])
    r = subprocess.run([luau, "harness.luau", "-a", mode, spec], cwd=tmp, capture_output=True, text=True)
    if r.returncode != 0 or "ALL DONE" not in r.stdout:
        raise SystemExit(f"FAIL  the {mode} run did not finish:\n" + r.stdout[-3000:] + r.stderr[-3000:])
    out = {"LOOK": [], "KIND": [], "FIX": [], "PART": [], "RUN": [], "ALL": [], "said": []}
    for line in r.stdout.splitlines():
        if line.startswith("ALL\t"):
            out["ALL"].append(line.split("\t")[1:])
            continue
        kind, _, rest = line.partition(" ")
        if kind in out and kind != "ALL":
            out[kind].append(json.loads(rest))
        elif kind in ("META", "PROBE"):
            out[kind] = json.loads(rest)
        elif line.startswith("ZDCFixtureArt:"):
            out["said"].append(line)
    return out


def rel_box(cf, size, frame):
    """A part's box in a fixture's frame: its centre and its extents along the frame's axes (both CFrames as the
    harness prints them: the position, then the rotation row by row)."""
    fp, fr = frame[:3], frame[3:]
    pp, pr = cf[:3], cf[3:]
    d = [pp[i] - fp[i] for i in range(3)]
    centre = [sum(fr[j * 3 + i] * d[j] for j in range(3)) for i in range(3)]  # Rᵀ d
    rot = [[sum(fr[k * 3 + i] * pr[k * 3 + j] for k in range(3)) for j in range(3)] for i in range(3)]  # Rᵀ R'
    ext = [sum(abs(rot[i][j]) * size[j] for j in range(3)) for i in range(3)]
    return centre, ext


def made_for(fix):
    """Is this fixture (a FIX line) in its Model and of its kind's size (the contract's), so the model dresses it?"""
    return fix["has"] and all(abs(a - b) <= TOL for a, b in zip(fix["size"], KINDS[fix["kind"]]))


def colour_of(entry):
    """A finish's colour in the manifest's "finishes" (a "#RRGGBB" string, an [r, g, b] list, a dict holding one, or a
    tuple whose first item is one); None when it has none."""
    if isinstance(entry, str) and re.fullmatch(r"#?[0-9A-Fa-f]{6}", entry):
        h = entry.lstrip("#")
        return [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    if isinstance(entry, list) and len(entry) == 3 and all(isinstance(x, (int, float)) for x in entry):
        return [round(x * 255) if all(x <= 1 for x in entry) and any(isinstance(x, float) for x in entry) else int(x) for x in entry]
    if isinstance(entry, dict):
        for key in ("color", "colour", "hex", "rgb"):
            if key in entry:
                return colour_of(entry[key])
    if isinstance(entry, (list, tuple)) and entry:
        return colour_of(entry[0])
    return None


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    luau = str(Path(args[0]).resolve())
    source = args[1] if len(args) > 1 else None
    if source == "--standin" or (source is None and not MANIFEST.exists()):
        manifest, which = standin_manifest(), "the stand-in (the contract's table, plain boxes)"
    else:
        path = Path(source) if source else MANIFEST
        manifest, which = json.loads(path.read_text()), f"{path.name}" + ("" if path == MANIFEST else f" ({path})")
    failures = []

    def check(ok, text, detail=""):
        print(("PASS  " if ok else "FAIL  ") + text + ("" if ok or not detail else f"  ({detail})"))
        if not ok:
            failures.append(text)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        out = {mode: run(luau, tmp, mode) for mode in RUNS}
    none, art = out["none"], out["art"]
    looks = {l["finish"]: l for l in none["LOOK"]}
    meta = art["META"]

    # ── the manifest ──
    fixtures, pieces = manifest.get("fixtures", {}), manifest.get("pieces", {})
    missing = sorted(set(KINDS) - set(fixtures))
    unknown = sorted(set(fixtures) - set(KINDS))
    sizes = [k for k in KINDS if k in fixtures and any(abs(a - b) > 1e-6 for a, b in zip(fixtures[k]["size"], KINDS[k]))]
    check(not missing and not unknown and not sizes, f"the manifest's {len(fixtures)} kinds are the contract's, each at its size",
          f"missing {missing}, not the contract's {unknown}, another size {[(k, fixtures[k]['size'], KINDS[k]) for k in sizes]}")
    check(set(KINDS) == {k["kind"] for k in none["KIND"]}, "FixtureMesh.Kinds is the contract's table", sorted({k["kind"] for k in none["KIND"]} ^ set(KINDS)))
    bad_names = [n for n, p in pieces.items() if f"{p.get('kind')}_{p.get('finish')}" != n or n not in fixtures.get(p.get("kind"), {}).get("pieces", [])]
    bad_names += [n for k, fx in fixtures.items() for n in fx.get("pieces", []) if n not in pieces]
    check(not bad_names, f"every piece is named <kind>_<finish> and listed with its kind ({len(pieces)} pieces)", bad_names[:8])
    finishes = {p["finish"] for p in pieces.values()}
    check(not finishes - set(looks), f"every finish of the model has a look in FixtureMesh.Looks ({len(finishes)} finishes)", sorted(finishes - set(looks)))
    palette = [f for f, names in PALETTE.items() if f not in looks or tuple(looks[f]["palette"]) != names]
    fixed = [f for f, l in looks.items() if f not in PALETTE and l["palette"]]
    check(not palette and not fixed, "the palette finishes take the rolled colours (tile ← Stove, tile2 ← Upper, pine ← Seat / StoveBench, cushion ← Cushion), no other",
          f"{palette} {fixed}")
    if "finishes" in manifest:
        differ = []
        for name, entry in manifest["finishes"].items():
            want, look = colour_of(entry), looks.get(name)
            if not look or (want is not None and want != look["color"]):
                differ.append(f"{name} {want} vs {look and look['color']}")
            elif isinstance(entry, dict):
                if "material" in entry and entry["material"] != look["material"]:
                    differ.append(f"{name} {entry['material']} vs {look['material']}")
                if "palette" in entry and bool(entry["palette"]) != bool(look["palette"]):
                    differ.append(f"{name} palette {entry['palette']} vs {look['palette']}")
                for key, mine in (("reflectance", "r"), ("transparency", "t")):
                    if abs(float(entry.get(key, 0)) - look[mine]) > 1e-6:
                        differ.append(f"{name} {key} {entry.get(key, 0)} vs {look[mine]}")
        extra = sorted(set(looks) - set(manifest["finishes"]))
        check(not differ and not extra, f"FixtureMesh.Looks is the manifest's {len(manifest['finishes'])} finishes (fixtures.py's FINISHES; "
              "tools/fixtures-art/looks.py --write copies them)", "; ".join(differ[:8]) + (f" not in the manifest: {extra}" if extra else ""))
    over_piece = [(n, p["triangles"]) for n, p in pieces.items() if p.get("triangles", 0) > TRIANGLES["piece"]]
    tris = {k: sum(pieces[n].get("triangles", 0) for n in fx.get("pieces", []) if n in pieces) for k, fx in fixtures.items()}
    over_kind = [(k, t) for k, t in tris.items() if t > TRIANGLES.get(k, TRIANGLES["kind"])]
    check(not over_piece and not over_kind, f"triangles: at most {TRIANGLES['kind']} a kind (the Kachelofen {TRIANGLES['kachelofen']}), "
          f"{TRIANGLES['piece']} a piece (the most: {max(tris.items(), key=lambda t: t[1]) if tris else '-'})", f"kinds {over_kind}, pieces {over_piece}")

    # ── no import: today's fixtures in their models ──
    fix_none = {(f["run"], f["fid"]): f for f in none["FIX"]}
    parts_none = {}
    for p in none["PART"]:
        parts_none.setdefault((p["run"], p["fid"]), []).append(p)
    houses = [f for f in none["FIX"] if not f["run"].startswith("farm")]
    missing_model = [f"{f['run']} {f['kind']}" for f in houses if not f["has"] or f["parent"] != "Decor" or f["name"] != "Fixture_" + f["kind"] or f["attr"] != f["kind"]]
    check(houses and not missing_model and all(r["extra"] == 0 for r in none["RUN"]),
          f"no import: every fixture of the {len([r for r in none['RUN'] if not r['run'].startswith('farm')])} houses in its Model Fixture_<kind> in Decor (attribute Fixture), {len(houses)} fixtures",
          missing_model[:6])
    sized = [f"{f['run']} {f['kind']} {f['size']}" for f in houses if not made_for(f)]
    check(not sized, "every fixture of the houses at its kind's size (the contract's table)", sized[:6])
    farm_fix = [f for f in none["FIX"] if f["run"].startswith("farm")]
    check(any(f["kind"] == "kachelofen" and not f["has"] for f in farm_fix) and all(f["has"] for f in farm_fix if f["kind"] != "kachelofen")
          and {f["kind"] for f in farm_fix if not made_for(f)} == {"kachelofen", "counter", "sink"},
          "the farm: its own Kachelofen loose in Decor (FARM_LOOKS), its counter and sink (another size) and its workshop's workbench in their models",
          [(f["kind"], f["has"], f["size"]) for f in farm_fix])
    check(not any(a[2] == "MeshPart" for a in none["ALL"]) and not any(f["dressed"] for f in none["FIX"]) and not none["PROBE"]["has"],
          "no import: no mesh, nothing dressed")
    budgets = {"house": meta["house"], "big": meta["big"], "farm": meta["farm"]}
    counts = {r["run"]: r["parts"] for r in none["RUN"]}
    over = [(r["run"], r["parts"], budgets[r["kind"]]) for r in none["RUN"] if r["parts"] > budgets[r["kind"]]]
    check(not over, f"no import: every interior within its budget ({', '.join(f'{k} {v}' for k, v in sorted(counts.items()))})", over)
    # today's look's own reach, kind by kind, in its frame (the allowed region beyond the box)
    today = {}
    frame_y = {}
    for key, fx in fix_none.items():
        if not fx["has"] or fx["run"].startswith("farm"):
            continue
        frame_y[fx["kind"]] = fx["at"][1] - fx["origin"][1]
        for p in parts_none.get(key, []):
            c, e = rel_box(p["cf"], p["size"], fx["at"])
            lo, hi = [c[i] - e[i] / 2 for i in range(3)], [c[i] + e[i] / 2 for i in range(3)]
            t = today.setdefault(fx["kind"], [lo, hi])
            today[fx["kind"]] = [[min(t[0][i], lo[i]) for i in range(3)], [max(t[1][i], hi[i]) for i in range(3)]]

    # ── the manifest's pieces in their boxes ──
    reach = {"basin": BASIN_MIRROR, "hood": meta["ceiling"] - frame_y.get("hood", 7.0),
             "corner_shelf": meta["decor"] - meta["shelf"]}  # (the mirror; the flue to the ceiling; the candle and flowers under the wall decor)
    out_of_box, worst = [], 0.0
    for name, p in pieces.items():
        kind = p["kind"]
        if kind not in KINDS:
            continue
        w, h, d = KINDS[kind]
        t = today.get(kind, [[-w / 2, 0, -d / 2], [w / 2, h, d / 2]])
        lo = [p["center"][i] - p["size"][i] / 2 for i in range(3)]
        hi = [p["center"][i] + p["size"][i] / 2 for i in range(3)]
        x_out = max(-max(w / 2, -t[0][0]) - lo[0], hi[0] - max(w / 2, t[1][0]))
        y_out = max(min(0, t[0][1]) - lo[1], hi[1] - max(h, t[1][1], reach.get(kind, 0)))
        z_out = max(-d / 2 - lo[2], hi[2] - d / 2)  # (never into the room in front, nor into the wall behind)
        o = max(x_out, y_out, z_out)
        worst = max(worst, x_out, z_out)
        if o > TOL:
            out_of_box.append(f"{name} out by {o:.3f} (x {x_out:.3f}, y {y_out:.3f}, z {z_out:.3f})")
    check(not out_of_box, f"every piece in its kind's box but the allowed reaches (the basin's mirror to {BASIN_MIRROR}, the hood's flue to "
          f"{reach['hood']:.1f}, the corner shelf to {reach['corner_shelf']:.1f}, today's taps, burners, pegboard and vise), "
          f"never more than {TOL} into the room or the wall", "; ".join(out_of_box[:6]))
    neon = []
    for name, p in pieces.items():
        if looks.get(p["finish"], {}).get("material") == "Neon":
            s = p["size"]
            area = max(s[0] * s[1], s[1] * s[2], s[0] * s[2])
            if area > meta["neonArea"]:
                neon.append(f"{name} {area:.2f} studs²")
    neon_pieces = [n for n, p in pieces.items() if looks.get(p["finish"], {}).get("material") == "Neon"]
    check(not neon, f"Neon stays small: {len(neon_pieces)} glowing pieces, each at most {meta['neonArea']} studs² a face", neon)

    # ── the import: every fixture dressed ──
    check(meta["moved"], "the import taken out of the Workspace into ServerStorage")
    fix_art = {(f["run"], f["fid"]): f for f in art["FIX"]}
    parts_art = {}
    for p in art["PART"]:
        parts_art.setdefault((p["run"], p["fid"]), []).append(p)
    undressed, misplaced, physical, solid_bad, colour_bad, ceiling_bad = [], [], [], [], [], []
    dressed = 0
    ceilings = {r["run"]: r["ceiling"] + r["origin"][1] for r in art["RUN"]}
    def rest(rows, keep):
        return sorted("\t".join(r) for r in rows if keep(r))

    def same_fixture(o, fx):
        return rest(o["ALL"], lambda r: r[0] == fx["run"] and r[1] == str(fx["fid"])) == rest(none["ALL"], lambda r: r[0] == fx["run"] and r[1] == str(fx["fid"]))

    kept_others = []
    for key, fx in fix_art.items():
        before = parts_none.get(key, [])
        if not made_for(fix_none[key]):
            if fx["dressed"] or not same_fixture(art, fx):
                kept_others.append(f"{fx['run']} {fx['kind']} {fx['size']}")
            continue
        if not fx["has"] or not fx["dressed"]:
            undressed.append(f"{fx['run']} {fx['kind']}")
            continue
        dressed += 1
        want = manifest["fixtures"][fx["kind"]]["pieces"]
        meshes = [p for p in parts_art.get(key, []) if p["class"] == "MeshPart"]
        others = [p for p in parts_art.get(key, []) if p["class"] != "MeshPart"]
        if sorted(p["name"] for p in meshes) != sorted(want):
            misplaced.append(f"{fx['run']} {fx['kind']}: pieces {sorted(set(p['name'] for p in meshes) ^ set(want))}")
        for p in meshes:
            c, e = rel_box(p["cf"], p["size"], fx["at"])
            m = pieces.get(p["name"])
            if not m or any(abs(c[i] - m["center"][i]) > 2e-3 or abs(e[i] - m["size"][i]) > 2e-3 for i in range(3)):
                misplaced.append(f"{fx['run']} {p['name']} at {[round(x, 3) for x in c]} {[round(x, 3) for x in e]}")
            if not p["anchored"] or p["collide"] or p["query"] or p["touch"] or p["skin"]:
                physical.append(f"{fx['run']} {p['name']}")
            top = p["cf"][1] + sum(abs(p["cf"][6 + j]) * p["size"][j] for j in range(3)) / 2  # (its rotation's second row: up)
            if top > ceilings[fx["run"]] + TOL:
                ceiling_bad.append(f"{fx['run']} {p['name']} {top - ceilings[fx['run']]:.2f} over the ceiling")
            finish = p["name"].rsplit("_", 1)[1]
            look = looks.get(finish)
            if look:
                expect = look["color"]
                for source in look["palette"]:
                    found = [q for q in before if q["name"] == source]
                    if found:
                        expect = found[0]["color"]
                        break
                if p["color"] != expect or p["material"] != look["material"] and not (look["material"] == "Neon" and p["material"] == "SmoothPlastic"):
                    colour_bad.append(f"{fx['run']} {p['name']} {p['color']} {p['material']}, not {expect} {look['material']}")
        kept = sorted((q["name"], tuple(round(x, 4) for x in q["cf"]), tuple(round(x, 4) for x in q["size"])) for q in before if q["collide"])
        left = sorted((q["name"], tuple(round(x, 4) for x in q["cf"]), tuple(round(x, 4) for x in q["size"])) for q in others)
        if kept != left or any(q["t"] != 1 or q["shadow"] or not q["collide"] or not q["query"] for q in others):
            solid_bad.append(f"{fx['run']} {fx['kind']}: kept {[k[0] for k in left]}, solid {[k[0] for k in kept]}")
    runs = [r for r in art["RUN"] if not r["run"].startswith("farm")]
    farm_dressed = [f["kind"] for f in art["FIX"] if f["run"].startswith("farm") and f["dressed"]]
    check(not undressed and dressed == len(houses) + len(farm_dressed), f"the import: every fixture of the {len(runs)} houses dressed ({len(houses)} fixtures of "
          f"{len(set(f['kind'] for f in houses))} kinds), the farm's of a house's size too ({', '.join(farm_dressed) or 'none'})", undressed[:6])
    check(not misplaced, "every piece of its kind once, where the manifest has it in the fixture's frame (the import's turn and scale undone)", misplaced[:6])
    check(not solid_bad, "the solid parts kept where they were, hidden and shadowless, still colliding and queried; the others gone", solid_bad[:4])
    check(not physical, "no mesh physical (anchored; no collision, query or touch) nor wearing the importer's SurfaceAppearance", physical[:6])
    check(not colour_bad, "the palette finishes in the colours the house rolled (Stove, Upper, Seat / StoveBench, Cushion), the others their look's", colour_bad[:6])
    check(not ceiling_bad, "nothing of the model through the ceiling", ceiling_bad[:6])
    over = [(r["run"], r["parts"], budgets[r["kind"]]) for r in art["RUN"] if r["parts"] > budgets[r["kind"]]]
    dressed_counts = ", ".join(f"{r['run']} {r['parts']} (was {counts.get(r['run'])})" for r in art["RUN"])
    check(not over, f"dressed: every interior within its budget ({dressed_counts}; house {budgets['house']}, big {budgets['big']}, farm {budgets['farm']})", over)
    # the rest of the interior unchanged; the farm's counter and sink (another size) and Kachelofen as they were
    same_rest = all(rest(art["ALL"], lambda r, run=r_["run"]: r[0] == run and r[1] == "0") == rest(none["ALL"], lambda r, run=r_["run"]: r[0] == run and r[1] == "0")
                    for r_ in art["RUN"])
    check(same_rest, "dressed: the rest of every interior exactly as without the import")
    check(not kept_others, "a fixture of another size (the farm's counter and sink) exactly as without the import", kept_others[:6])

    # ── refused imports and sizes: as today ──
    for mode, what in (("scattered", "an import physics threw about (one piece turned)"), ("mirrored", "a mirrored import")):
        o = out[mode]
        same = all(rest(o["ALL"], lambda r, run=r_["run"]: r[0] == run) == rest(none["ALL"], lambda r, run=r_["run"]: r[0] == run) for r_ in o["RUN"])
        check(same and not any(f["dressed"] for f in o["FIX"]) and not o["PROBE"]["has"], f"{what}: refused, every interior exactly as without it",
              o["said"][:2])
    o = out["wrongbox"]
    counters = [f for f in o["FIX"] if f["kind"] == "counter"]
    same_counters = all(same_fixture(o, f) for f in counters)
    others_dressed = all(f["dressed"] for f in o["FIX"] if f["kind"] != "counter")
    check(counters and same_counters and not any(f["dressed"] for f in counters) and others_dressed,
          f"a kind of another size (the import's counter 0.2 wider): its {len(counters)} counters as they were, the other kinds dressed")
    probes = [out[m]["PROBE"] for m in RUNS]
    check(all(not p["wrong"] and not p["unknown"] and p["children"] == 2 and p["t"] == 0 for p in probes),
          "a direct dress of a wrong size or of a kind the model does not make: false, left as it was")

    pieces_n = len(pieces)
    tri_total = sum(p.get("triangles", 0) for p in pieces.values())
    if failures:
        print(f"Fixture mesh FAIL: {len(failures)} check(s) failed on {which}")
        sys.exit(1)
    print(f"Fixture mesh PASS on {which}: {len(fixtures)} kinds, {pieces_n} pieces ({tri_total} triangles) from a turned, scaled import "
          f"dressing {dressed} fixtures in {len(runs)} houses (in place, solid parts kept, nothing physical, at most {max(worst, 0):.3f} "
          f"past a box's sides); within budgets; refused scattered, mirrored, wrong-sized: as today")


if __name__ == "__main__":
    main()
