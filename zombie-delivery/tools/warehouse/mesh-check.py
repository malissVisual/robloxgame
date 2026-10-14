#!/usr/bin/env python3
"""8.2 SANDBOX: the ZDC warehouse in the owner's Blender model (server/WarehouseMesh.luau) on the warehouses the real
server/Warehouse.luau builds, without Studio.

Simulates the Roblox import of design/blender-warehouse/roblox/ZDCWarehouseArt.fbx (all five levels) from its manifest
(ZDCWarehouseArt.json, written by warehouse.py: every piece's box, each level's markers, walls, props and details, from
the level's origin): the importer turns the model a quarter round, makes it 3 times bigger, moves it and nests half of
it in a sub-model. Then the real server/Warehouse.luau (on tests/runtime/WarehouseRuntime.luau, as
tests/warehouse_runtime_test.luau runs it, an owner on plot 2) builds every plot's warehouse and hands each to the real
WarehouseMesh. Checks:
  - the level the warehouses wear (WarehouseMesh.level: Config.Warehouse.ArtLevel) is the layout's warehouse: its box,
    door, ridge and floor are shared/WarehouseLayout.luau's (SandboxMap's plot, Config.Warehouse); every finish has a
    look; at most 10,000 triangles a piece, no flat piece;
  - without the import nothing changes (no mesh, nothing hidden);
  - with it the import leaves the world and every warehouse is dressed once (again: nothing more) with that level only:
    every piece where the model has it on that plot (its door on the plot's door), anchored, not physical, the
    importer's SurfaceAppearance gone; an unseen solid block on each of the level's props (the office annex);
  - hidden: exactly the layout's visual pieces (WarehouseVisual: the shell, the roof, the door, the bollards, the ZDC
    sign, the floor, the hall's beams, posts, lamp housings and glows), still colliding where they did, the glows' lights
    still there; nothing else changed: the owner's sign and the STOCK board shown with their words, the stands, the
    desk, the paint, the prompts;
  - the model on the colliders: its walls are the walls that collide, its gables over theirs, its roof over the roof
    slabs, its floor the floor (its top the paint's bottom); a lamp of the model over every lamp's light;
  - the model keeps clear of everything the game keeps (no detail inside any part that stays), of the stands (up to
    16 studs: the pieces on show and their tags), the UPGRADES desk, the open hall, the way in through the door, the
    front of the owner's sign, the STOCK board and the UPGRADES sign, and the UNLOAD HERE bay;
  - a warehouse of another size, a level of another size, a warehouse with no plot: left as they were.

    python3 zombie-delivery/tools/warehouse/mesh-check.py <luau>
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
MANIFEST = ROOT / "design/blender-warehouse/roblox/ZDCWarehouseArt.json"
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')
HIGH = 16.0  # the stands' room up (the pieces on show and their tags)
# The layout's pieces that are only looks (the model draws them) and those that stay (they work or are written).
VISUAL = re.compile(r"^(Floor|WallBack|WallWest|WallEast|WallFrontWest|WallFrontEast|Header|Gable(Front|Back)(West|East)|"
                    r"Roof(West|East)|Barge(Front|Back)(West|East)|Gutter(West|East)|Downpipe(West|East)|RidgeCap|"
                    r"Rib(Back|Front|Header|West|East)\d+|(Plinth|Stripe)(Back|West|East|FrontWest|FrontEast)|"
                    r"Corner(Front|Back)(West|East)|DoorRail(West|East)|Bollard(West|East)|DoorCurtain|DoorBar|DoorHood|"
                    r"ZdcSign|Beam\d+|Post\d+(West|East)|Lamp\d+|LampGlow\d+)$")
KEEP = re.compile(r"^(OwnerSign|StockBoard|UpgradeSign|Stand\d+|StandTop\d+|Plate\d+|Terminal\w+|Spot\d+\w*|"
                  r"SpotText\d+|Receiving\w+|AisleLine\w+|Bay\w+)$")
WALLS = ("WallBack", "WallWest", "WallEast", "WallFrontWest", "WallFrontEast", "Header")

HARNESS = r'''
local M = require("./ItemMock")
local F = getmetatable(M.CFrame.identity)
F.__add = function(a, v) return setmetatable({ Position = a.Position + v, R = a.R }, F) end
F.__sub = function(a, v) return setmetatable({ Position = a.Position - v, R = a.R }, F) end
M.CFrame.fromMatrix = function(p, x, y, z) return setmetatable({ Position = p, R = { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z } }, F) end
local O = getmetatable(M.Instance.new("Part"))
local isA = O.IsA
O.IsA = function(self, c)
	if c == "BasePart" and self.ClassName == "MeshPart" then return true end
	return isA(self, c)
end
O.FindFirstChild = function(self, name, recursive)
	for _, c in self.children do if c.Name == name then return c end end
	if recursive then
		for _, c in self.children do
			local found = c:FindFirstChild(name, true)
			if found then return found end
		end
	end
	return nil
end
local storage = M.Instance.new("Folder")
storage.Name = "ServerStorage"
local get = M.game.GetService
M.game.GetService = function(self, name) if name == "ServerStorage" then return storage end return get(self, name) end
local MODE = (...)

local art = M.Instance.new("Model")
if MODE == "art" then
	art.Name = "ZDCWarehouseArt"
	art.Parent = M.workspace -- (as the importer leaves it: Main.server / WarehouseMesh move it to ServerStorage)
	local nested = M.Instance.new("Model")
	nested.Name = "Group"
	nested.Parent = art
	-- The import: Blender's (x, y, z) are the importer's (x, z, -y); a quarter turn about up (x → -z, z → x), 3 times
	-- the size, moved.
	local K, MOVE = 3, M.Vector3.new(-30, 2, 55)
	for n, row in require("./pieces") do
		local x, y, z = row[2], row[4], -row[3]
		local sx, sy, sz = row[5], row[7], row[6]
		local p = M.Instance.new(if string.sub(row[1], 1, 5) == "mark_" then "Part" else "MeshPart")
		p.Name = row[1]
		p.CFrame = M.CFrame.new(z * K + MOVE.X, y * K + MOVE.Y, -x * K + MOVE.Z)
		p.Size = M.Vector3.new(sz * K, sy * K, sx * K)
		M.Instance.new("SurfaceAppearance").Parent = p
		p.Parent = if n % 2 == 0 then nested else art
	end
end

local W = require("./WarehouseRuntime")
local Warehouse = require("./WarehouseServer")
local WarehouseMesh = require("./WarehouseMesh")
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")
local Config = require("./Config")
local function f(cf) local r = cf.R; return string.format("[%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f]", cf.Position.X, cf.Position.Y, cf.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]) end
local function rect(r) return string.format('{"x0":%.6f,"x1":%.6f,"z0":%.6f,"z1":%.6f}', r.x0, r.x1, r.z0, r.z1) end

for finish in WarehouseMesh.Looks do
	print(string.format('LOOK {"finish":"%s"}', finish))
end
-- The layout's numbers, each plot's from its warehouse's middle on the ground (every one looks south: only moved).
for _, plot in SandboxMap.Plots do
	local w = plot.warehouse
	local function rel(r) return { x0 = r.x0 - w.x, x1 = r.x1 - w.x, z0 = r.z0 - w.z, z1 = r.z1 - w.z } end
	local o = WarehouseLayout.outline(plot)
	local d = WarehouseLayout.door(plot)
	local stands = {}
	for _, s in WarehouseLayout.stands(plot, WarehouseLayout.capacity()) do
		table.insert(stands, string.format("[%.6f,%.6f,%.6f,%.6f]", s.x - w.x, s.z - w.z, s.sx, s.sz))
	end
	local t = WarehouseLayout.terminal(plot)
	print(string.format('LAYOUT {"plot":%d,"level":%d,"size":[%.6f,%.6f,%.6f],"outline":%s,"top":%.6f,"door":[%.6f,%.6f,%.6f,%.6f],"floorTop":%.6f,"wall":%.6f,"inside":%s,"doorPath":%s,"bay":%s,"stands":[%s],"terminal":[%.6f,%.6f,%.6f,%.6f,%.6f]}',
		plot.id, WarehouseMesh.level(plot.id), w.sx, w.sy, w.sz, rect(rel(o)), o.top, d.x - w.x, d.z - w.z, d.width, d.height,
		WarehouseLayout.FloorTop, WarehouseLayout.Wall, rect(rel(WarehouseLayout.inside(plot))), rect(rel(WarehouseLayout.doorPath(plot))),
		rect(rel(WarehouseLayout.bay(plot))), table.concat(stands, ","), t.x - w.x, t.z - w.z, t.sx, t.sz, t.y))
end

local ana = W.player(101, "Ana", M.Vector3.new(-65, 3, -150))
W.claim(2, ana)
Warehouse.start()

local function count(model)
	local n = 0
	for _, d in model:GetDescendants() do if d.ClassName == "MeshPart" or d.Name:sub(1, 14) == "WarehouseSolid" then n += 1 end end
	return n
end
local before = count(Warehouse.model(1))
local again = WarehouseMesh.dress(Warehouse.model(1))
local after = count(Warehouse.model(1))
-- a warehouse of another size, a level of another size, one with no plot: left as they are
local function stray(id)
	local model = M.Instance.new("Model")
	model:SetAttribute("Plot", id)
	local wall = M.Instance.new("Part")
	wall.Name = "WallBack"
	wall:SetAttribute(WarehouseMesh.Attribute, true)
	wall.Parent = model
	return model, wall
end
local function untouched(model, wall)
	return wall.Transparency ~= 1 and model:FindFirstChild("WarehouseMesh") == nil and model:GetAttribute("MeshArt") == nil
end
local w1 = SandboxMap.Plots[1].warehouse
w1.sx += 4
local wide, wideWall = stray(1)
local wideDressed = WarehouseMesh.dress(wide)
w1.sx -= 4
local chosen = Config.Warehouse.ArtLevel
Config.Warehouse.ArtLevel = if chosen == 5 then 4 else 5
local other, otherWall = stray(1)
local otherDressed = WarehouseMesh.dress(other)
Config.Warehouse.ArtLevel = chosen
local lost, lostWall = stray(99)
local lostDressed = WarehouseMesh.dress(lost)
print(string.format('META {"moved":%s,"ready":%s,"again":%s,"before":%d,"after":%d,"strays":%s}',
	tostring(art.Parent == storage and MODE == "art"), tostring(WarehouseMesh.ready()), tostring(again), before, after,
	tostring(not (wideDressed or otherDressed or lostDressed) and untouched(wide, wideWall) and untouched(other, otherWall) and untouched(lost, lostWall))))

for _, plot in SandboxMap.Plots do
	local model = Warehouse.model(plot.id)
	local base = M.CFrame.new(plot.warehouse.x, 0, plot.warehouse.z)
	print(string.format('PLOT {"plot":%d,"dressed":%s,"level":%s,"meshes":%d}', plot.id, tostring(model:GetAttribute("MeshArt") == true),
		tostring(model:GetAttribute("WarehouseLevel") or "null"), count(model)))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local guis, lights, prompts = {}, 0, 0
			for _, c in d:GetChildren() do
				if c.ClassName == "SurfaceGui" then table.insert(guis, tostring(c.Enabled ~= false)) end
				if c.ClassName == "PointLight" then lights += 1 end
			end
			for _, c in d:GetDescendants() do
				if c.ClassName == "ProximityPrompt" then prompts += 1 end
			end
			print(string.format('PART {"plot":%d,"class":"%s","name":"%s","parent":"%s","cf":%s,"size":[%.6f,%.6f,%.6f],"t":%g,"shadow":%s,"collide":%s,"query":%s,"touch":%s,"anchored":%s,"visual":%s,"skin":%s,"guis":[%s],"lights":%d,"prompts":%d,"color":[%.4f,%.4f,%.4f]}',
				plot.id, d.ClassName, d.Name, d.Parent.Name, f(base:Inverse() * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, d.Transparency or 0,
				tostring(d.CastShadow), tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Anchored),
				tostring(d:GetAttribute(WarehouseMesh.Attribute) == true), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil),
				table.concat(guis, ","), lights, prompts, d.Color.R, d.Color.G, d.Color.B))
		end
	end
end
print("ALL DONE")
'''


def to_blender(origin, g):
    """A point from a level's origin (the export's game axes: x = Blender's -x, y = z, z = y) to Blender's."""
    gx, gy, gz = origin[0] + g[0], origin[1] + g[1], origin[2] + g[2]
    return [-gx, gz, gy]


def stage(tmp: Path, manifest: dict):
    """The real modules on the recorder, as tests/run_tests.py stages server/Warehouse.luau for its runtime test."""
    for source in SHARED.glob("*.luau"):
        (tmp / source.name).write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text()))
    for name in ("GunModels", "CargoLooks", "ItemLooks", "FurnitureLooks", "HouseLayout"):
        text = (SHARED / f"{name}.luau").read_text()
        text = re.sub(r"require\(script\.Parent\.Layouts\.(\w+)\)", r'require("./\1")', text)
        (tmp / f"{name}.luau").write_text(PREFIX + re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text))
    for path in sorted((SHARED / "Layouts").glob("*.luau")):
        (tmp / path.name).write_text(PREFIX + re.sub(r"require\(script\.Parent\.Parent\.(\w+)\)", r'require("./\1")', path.read_text()))
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    for name in ("MovingRuntime", "WarehouseRuntime"):
        shutil.copy(ROOT / f"tests/runtime/{name}.luau", tmp / f"{name}.luau")
    server = ROOT / "src" / "server"
    text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', (server / "FurnitureMesh.luau").read_text())
    (tmp / "FurnitureMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\n" + text)
    text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', (server / "WarehouseMesh.luau").read_text())
    assert "script.Parent" not in text, "WarehouseMesh requires a module this check does not stage"
    (tmp / "WarehouseMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\nlocal warn = function(...) print(\"WARN\", ...) end\n" + text)
    text = (server / "Warehouse.luau").read_text()
    for line in ("local WarehouseMesh = require(script.Parent.WarehouseMesh)", "WarehouseMesh.dress(model)",
                 "p:SetAttribute(WarehouseMesh.Attribute, d.visual)"):
        assert line in text, f"server/Warehouse.luau lost its hook ({line!r})"
    text = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "W.Net" if m[1] == "Net" else f'require("./{m[1]}")', text)
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", lambda m: f'require("./{m[1]}")' if m[1] in ("FurnitureMesh", "WarehouseMesh") else f"W.{m[1]}", text)
    head = ('local W = require("./WarehouseRuntime")\nlocal M = W.Mock\nlocal game, workspace, task, os = W.game, M.workspace, W.task, W.os\n'
            'local Instance, Vector3, Color3, CFrame, Enum, UDim2, UDim = M.Instance, M.Vector3, M.Color3, M.CFrame, M.Enum, M.UDim2, M.UDim\n'
            'local warn = function(...) print("WARN", ...) end\n')
    (tmp / "WarehouseServer.luau").write_text(head + text)
    # The import as warehouse.py exports it: every level's pieces, markers and props' boxes, in Blender's coordinates.
    rows = []
    for name, p in manifest["pieces"].items():
        origin = manifest["levels"][str(p["level"])]["origin"]
        sx, sy, sz = p["size"]
        rows.append([name, *to_blender(origin, p["center"]), sx, sz, sy])
    for name, at in (("mark_o", [0, 0, 0]), ("mark_x", [-10, 0, 0]), ("mark_y", [0, 0, 10]), ("mark_z", [0, 10, 0])):
        rows.append([name, *at, 0.3, 0.3, 0.3])
    for lid, lv in manifest["levels"].items():
        rows.append([f"mark_lvl{lid}", *to_blender(lv["origin"], [0, 0, 0]), 0.3, 0.3, 0.3])
        for key, at in lv["marks"].items():
            rows.append([f"mark_lvl{lid}_{key}", *to_blender(lv["origin"], at), 0.3, 0.3, 0.3])
        for k, box in enumerate(lv["solids"], 1):
            sx, sy, sz = box["size"]
            rows.append([f"collide_lvl{lid}_{k}", *to_blender(lv["origin"], box["center"]), sx, sz, sy])
    body = ",\n".join("{%s}" % ",".join([json.dumps(r[0])] + [repr(float(x)) for x in r[1:]]) for r in rows)
    (tmp / "pieces.luau").write_text("return {\n" + body + "\n}\n")
    (tmp / "harness.luau").write_text(HARNESS)


def run(luau: str, tmp: Path, mode: str):
    r = subprocess.run([luau, "harness.luau", "-a", mode], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    out = {"LOOK": [], "LAYOUT": [], "PLOT": [], "PART": [], "WARN": []}
    for line in r.stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind == "WARN":
            out["WARN"].append(line)
        elif kind in out:
            out[kind].append(json.loads(rest))
        elif kind == "META":
            out[kind] = json.loads(rest)
    return out


def aabb(part):
    """A part's box in its plot's warehouse frame (its cf is already there)."""
    r = part["cf"][3:]
    half = [sum(abs(r[i * 3 + j]) * part["size"][j] for j in range(3)) / 2 for i in range(3)]
    at = part["cf"][:3]
    return [at[i] - half[i] for i in range(3)], [at[i] + half[i] for i in range(3)]


def placed(box, depth):
    """A box from the level's origin (x right seen from outside, z into the building) in the warehouse's frame (its
    middle on the ground, x east, z south): the door on the south wall's middle, turned round."""
    (gx, gy, gz), (sx, sy, sz) = box["center"], box["size"]
    c = [-gx, gy, depth / 2 - gz]
    return [c[0] - sx / 2, c[1] - sy / 2, c[2] - sz / 2], [c[0] + sx / 2, c[1] + sy / 2, c[2] + sz / 2]


def overlap(a, b, margin=0.005):
    return all(a[0][i] < b[1][i] - margin and b[0][i] < a[1][i] - margin for i in range(3))


def inside(a, b, eps=1e-3):
    return all(b[0][i] - eps <= a[0][i] and a[1][i] <= b[1][i] + eps for i in range(3))


def close(a, b, eps=2e-3):
    return all(abs(x - y) < eps for x, y in zip(a, b))


def check_level(manifest, lay, looks):
    """The level the warehouses wear is the layout's warehouse."""
    level = manifest["levels"][str(lay["level"])]
    W, H, D = level["size"]
    assert close((W, H, D), lay["size"], 1e-4), (lay["level"], level["size"], lay["size"], "this level is not the plot's warehouse")
    o = lay["outline"]
    assert close((o["x0"], o["x1"], o["z0"], o["z1"]), (-W / 2, W / 2, -D / 2, D / 2), 1e-4), ("the layout's outline", o)
    marks = level["marks"]
    assert close(marks["box"], (W / 2, H, D), 1e-4) and close(marks["door"], (level["door"][0] / 2, level["door"][1], 0), 1e-4), marks
    assert abs(marks["top"][1] - lay["top"]) < 1e-4, (marks["top"], lay["top"], "the level's ridge is not Config.Warehouse.Ridge")
    assert close(level["door"], lay["door"][2:], 1e-4) and close(lay["door"][:2], (0, D / 2), 1e-4), (level["door"], lay["door"])
    assert abs(level["floorTop"] - lay["floorTop"]) < 1e-6, (level["floorTop"], lay["floorTop"], "the floor's top is not WarehouseLayout.FloorTop")
    pieces = manifest["pieces"]
    for name, p in pieces.items():
        assert re.fullmatch(r"lvl\d+[a-z]?_[a-z0-9]+", name), (name, "not lvl<N>_<finish>")
        assert p["triangles"] <= 10000, (name, p["triangles"], "more than 10,000 triangles in one piece")
        assert min(p["size"]) >= 0.01, (name, p["size"], "a flat piece (Roblox sizes a mesh by its box)")
        finish = name.split("_", 1)[1]
        assert finish in looks, (name, "a finish without a look in WarehouseMesh.Looks")
    return level


def main():
    luau = str(Path(sys.argv[1]).resolve())
    manifest = json.loads(MANIFEST.read_text())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        plain = run(luau, tmp, "none")
        art = run(luau, tmp, "art")
    looks = {l["finish"] for l in art["LOOK"]}
    lay = art["LAYOUT"][0]
    for other in art["LAYOUT"][1:]:
        assert other["level"] == lay["level"] and close(other["size"], lay["size"]) and close(list(other["outline"].values()), list(lay["outline"].values())) \
            and close(list(other["doorPath"].values()), list(lay["doorPath"].values())) and other["stands"] == lay["stands"], ("the plots' warehouses differ", other["plot"])
    level = check_level(manifest, lay, looks)
    W, H, D = level["size"]
    lid = lay["level"]
    pieces = {n: p for n, p in manifest["pieces"].items() if p["level"] == lid}
    solids = level["solids"]
    plots = [p["plot"] for p in art["LAYOUT"]]

    # Without the import: nothing at all.
    meta = plain["META"]
    assert not (meta["ready"] or meta["moved"] or meta["again"] or meta["before"] or meta["after"]) and meta["strays"], meta
    assert not any(p["dressed"] or p["meshes"] for p in plain["PLOT"]), plain["PLOT"]
    for p in plain["PART"]:
        assert p["class"] != "MeshPart" and p["parent"] != "WarehouseMesh", (p["plot"], p["name"], "dressed without the import")
    by_plain = {(p["plot"], p["name"]): p for p in plain["PART"]}
    assert len(by_plain) == len(plain["PART"]), "two parts of a warehouse share a name"

    # The layout's pieces: the visual ones exactly the looks, none of what stays.
    names = {name for (plot, name) in by_plain if plot == plots[0]}
    visual = {name for name in names if by_plain[(plots[0], name)]["visual"]}
    want_visual = {n for n in names if VISUAL.match(n)}
    assert visual == want_visual, ("the visual pieces", sorted(visual ^ want_visual)[:12])
    stray = sorted(n for n in names if not VISUAL.match(n) and not KEEP.match(n))
    assert not stray, ("pieces the check does not know (visual or kept?)", stray[:12])
    for name in ("OwnerSign", "StockBoard", "UpgradeSign", "Stand1", "TerminalDesk", "ReceivingText", "BayText"):
        assert name in names and name not in visual, (name, "must stay as it is")

    # With it: out of the world, every warehouse dressed once with the level.
    meta = art["META"]
    assert meta["ready"] and meta["moved"], ("the import was not taken out of the world", meta)
    assert meta["strays"], ("dressed a warehouse of another size, a level of another size or one with no plot", meta)
    assert meta["again"] and meta["before"] == meta["after"] == len(pieces) + len(solids), ("dressing again added pieces", meta, len(pieces))
    assert all(p["dressed"] and p["level"] == lid and p["meshes"] == len(pieces) + len(solids) for p in art["PLOT"]) and len(art["PLOT"]) == len(plots), art["PLOT"]
    assert not art["WARN"], art["WARN"][:5]

    worst = 0.0
    for plot in plots:
        mine = [p for p in art["PART"] if p["plot"] == plot and p["parent"] == "WarehouseMesh"]
        meshes = [p for p in mine if p["class"] == "MeshPart"]
        assert sorted(p["name"] for p in meshes) == sorted(pieces), (plot, sorted({p["name"] for p in meshes} ^ set(pieces))[:8])
        for m in meshes:
            assert m["anchored"] and not (m["collide"] or m["query"] or m["touch"]), (plot, m["name"], "physical")
            assert not m["skin"], (plot, m["name"], "the importer's SurfaceAppearance kept")
            lo, hi = aabb(m)
            want = placed(pieces[m["name"]], D)
            worst = max(worst, max(abs(a - b) for a, b in zip(lo + hi, want[0] + want[1])))
            assert close(lo, want[0]) and close(hi, want[1]), (plot, m["name"], lo, hi, want)
        blocks = sorted((p for p in mine if p["class"] == "Part"), key=lambda p: p["name"])
        assert len(blocks) == len(solids), (plot, "the props' solid blocks", len(blocks), len(solids))
        for k, (b, box) in enumerate(zip(blocks, solids), 1):
            assert b["name"] == f"WarehouseSolid{k}" and b["anchored"] and b["collide"] and b["query"] and not b["touch"] and b["t"] == 1, (plot, b)
            lo, hi = aabb(b)
            want = placed(box, D)
            assert close(lo, want[0]) and close(hi, want[1]), (plot, b["name"], lo, hi, want)
        # Hidden: exactly the visual parts (still colliding where they did); everything else as built.
        for p in (p for p in art["PART"] if p["plot"] == plot and p["parent"] != "WarehouseMesh"):
            was = by_plain[(plot, p["name"])]
            for key in ("collide", "query", "touch", "anchored", "cf", "size", "lights", "prompts", "color"):
                assert p[key] == was[key], (plot, p["name"], key, "changed")
            if p["visual"]:
                assert p["t"] == 1 and p["shadow"] is False and all(g is False for g in p["guis"]), (plot, p["name"], "still seen")
            else:
                assert p["t"] == was["t"] and p["shadow"] == was["shadow"] and p["guis"] == was["guis"], (plot, p["name"], "changed")
        parts = {p["name"]: p for p in art["PART"] if p["plot"] == plot}
        for name in ("OwnerSign", "StockBoard", "UpgradeSign"):
            assert parts[name]["t"] == 0 and parts[name]["guis"] == [True], (plot, name, "its words not shown")
        assert parts["ZdcSign"]["guis"] == [False], (plot, "the parts' ZDC sign still shows its words")
        glows = [p for n, p in parts.items() if n.startswith("LampGlow")]
        assert glows and all(g["lights"] == 1 for g in glows), (plot, "a lamp's light lost")
        if plot == 2:
            assert sum(p["prompts"] for p in parts.values()) > 0, "the owner's prompts are gone"

    # The model on the colliders (one plot: they are the same, only moved).
    parts = {p["name"]: p for p in plain["PART"] if p["plot"] == plots[0]}
    # (Blender numbers a name again in another level: "Střecha.005")
    details = [dict(d, name=re.sub(r"\.\d+$", "", d["name"]), box=placed(d, D)) for d in level["details"]]
    walls = [placed(b, D) for b in level["collide"]]
    floor_top = lay["floorTop"]
    for name in WALLS:
        wall = aabb(parts[name])
        assert parts[name]["collide"], (name, "not solid")
        assert any(inside(wall, b) and any(abs(b[1][i] - b[0][i] - (wall[1][i] - wall[0][i])) < 1e-3 and wall[1][i] - wall[0][i] < 1.5 for i in (0, 2)) for b in walls), \
            (name, "no wall of the model where it collides", wall)
    for b in walls:  # (and no wall of the model where nothing collides)
        pts = [[b[k][0], b[j][1], b[i][2]] for k in (0, 1) for j in (0, 1) for i in (0, 1)] + [[(b[0][i] + b[1][i]) / 2 for i in range(3)]]
        assert all(any(inside((p, p), aabb(parts[n])) for n in WALLS) for p in pts), ("a wall of the model nothing collides with", b)
    for end, tag in ((-1, "Back"), (1, "Front")):
        wedges = [aabb(parts[f"Gable{tag}{s}"]) for s in ("West", "East")]
        lo = [min(w[0][i] for w in wedges) for i in range(3)]
        hi = [max(w[1][i] for w in wedges) for i in range(3)]
        gables = [d["box"] for d in details if d["name"].startswith("Štít") and overlap(d["box"], (lo, hi), -1e-3)]
        assert any(g[0][0] <= lo[0] + 1e-3 and g[1][0] >= hi[0] - 1e-3 and g[1][1] >= hi[1] - 1e-3 for g in gables), (tag, "no gable of the model over the gable that collides")
    roofs = [d["box"] for d in details if d["name"] == "Střecha"]
    for name in ("RoofWest", "RoofEast"):
        slab = aabb(parts[name])
        assert any(r[0][0] <= slab[0][0] + 0.3 and r[1][0] >= slab[1][0] - 0.3 and r[0][2] <= slab[0][2] + 1e-3 and r[1][2] >= slab[1][2] - 1e-3 for r in roofs), (name, "not under the model's roof")
    assert max(r[1][1] for r in roofs) >= lay["top"], "the model's roof under the ridge"
    floors = [d["box"] for d in details if d["name"].startswith("Podlaha")]
    assert all(abs(f[1][1] - floor_top) < 1e-4 for f in floors), ("the model's floor is not at the floor's top", [f[1][1] for f in floors])
    hall = lay["inside"]
    assert any(f[0][0] <= hall["x0"] + 1e-3 and f[1][0] >= hall["x1"] - 1e-3 and f[0][2] <= hall["z0"] + 1e-3 and f[1][2] >= hall["z1"] - 1e-3 for f in floors), "the model's floor does not cover the hall"
    lamps = [d["box"] for d in details if d["finish"] == "glow"]
    for name, glow in ((n, aabb(p)) for n, p in parts.items() if n.startswith("LampGlow")):
        over = [b for b in lamps if abs((b[0][0] + b[1][0]) / 2 - (glow[0][0] + glow[1][0]) / 2) < 0.05
                and abs((b[0][2] + b[1][2]) / 2 - (glow[0][2] + glow[1][2]) / 2) < 0.05 and 0 <= b[0][1] - glow[1][1] <= 1.5]
        assert len(over) == 1, (name, "no lamp of the model over its light", glow)

    # Clear: nothing of the model in a part the game keeps, nor where the game needs room.
    kept = [(n, aabb(p)) for n, p in parts.items() if not p["visual"]]
    path, bay = lay["doorPath"], lay["bay"]
    rooms = [
        ("the open hall", ([hall["x0"] + 1.5, floor_top, hall["z0"] + 1.5], [hall["x1"] - 1.5, HIGH, hall["z1"] - 1.5])),
        ("the way in", ([path["x0"], 0.1, path["z0"]], [path["x1"], 14.0, path["z1"]])),
        ("the bay", ([bay["x0"], 0.1, bay["z0"]], [bay["x1"], 11.0, bay["z1"]])),
    ]
    for k, (x, z, sx, sz) in enumerate(lay["stands"], 1):
        rooms.append((f"stand {k}", ([x - sx / 2, floor_top, z - sz / 2], [x + sx / 2, HIGH, z + sz / 2])))
    tx, tz, tsx, tsz, ty = lay["terminal"]
    rooms.append(("the UPGRADES desk", ([tx - tsx / 2, floor_top, tz - tsz / 2], [tx + tsx / 2, ty + 4.0, tz + tsz / 2 + 2.0])))
    for name, front in (("OwnerSign", 3.0), ("StockBoard", -1.5), ("UpgradeSign", -1.5)):
        lo, hi = aabb(parts[name])
        z = (hi[2], hi[2] + front) if front > 0 else (hi[2], hi[2] - front)
        rooms.append((f"the front of {name}", ([lo[0], lo[1], z[0]], [hi[0], hi[1], z[1]])))
    clashes = []
    for d in details + [{"name": f"collide {k}", "box": placed(b, D)} for k, b in enumerate(solids, 1)]:
        for name, area in kept + rooms:
            if overlap(d["box"], area):
                clashes.append((d["name"], name))
    assert not clashes, f"the model where the game needs room: {clashes[:10]}"

    hidden = sum(1 for p in plain["PART"] if p["plot"] == plots[0] and p["visual"])
    tris = sum(p["triangles"] for p in pieces.values())
    print(f"Mesh warehouse PASS: level {lid} ({level['name']}, {len(pieces)} pieces, {tris} triangles, the largest "
          f"{max(p['triangles'] for p in pieces.values())}; {W:g} × {H:g} × {D:g}, door {level['door'][0]:g} × {level['door'][1]:g}, "
          f"ridge {lay['top']:g}: the layout's) from a turned, scaled import on the {len(plots)} warehouses Warehouse.luau builds: "
          f"every piece in place (at most {worst:.4f} off), anchored, not physical, {len(solids)} prop(s) solid; the {hidden} visual "
          f"parts hidden and still colliding, nothing else changed; its walls, gables, roof, floor and lamps on the game's; clear "
          f"of the {len(kept)} kept parts, the stands, the desk, the hall, the way in, the signs and the bay; again, another size, "
          f"another level, no plot, no import: unchanged")


if __name__ == "__main__":
    main()
