#!/usr/bin/env python3
"""8.2 SANDBOX: the ZDC warehouse in the owner's Blender model (server/WarehouseMesh.luau) on the warehouses the game
builds, without Studio. 8.3: on every level of the warehouse (design/warehouse-levels/KONTRAKT.md).

Simulates the Roblox import of design/blender-warehouse/roblox/ZDCWarehouseArt.fbx (all five levels) from its manifest
(ZDCWarehouseArt.json, written by warehouse.py: every piece's box, each level's markers, walls, props and details, from
the level's origin): the importer turns the model a quarter round, makes it 3 times bigger, moves it and nests half of
it in a sub-model. The FBX is not exported again (the owner keeps the import they have): warehouse.py and the manifest
are what the game must fit.

8.2, the real server/Warehouse.luau (on tests/runtime/WarehouseRuntime.luau, as tests/warehouse_runtime_test.luau runs
it, an owner on plot 2) builds every plot's warehouse (each at its Model's level: its attribute Level, 4 when it has
none) and hands each to the real WarehouseMesh:
  - without the import nothing changes (no mesh, nothing hidden);
  - with it the import leaves the world and every warehouse is dressed once (again: nothing more) with its level only:
    every piece where the model has it on that plot, anchored, not physical, the importer's SurfaceAppearance gone; an
    unseen solid block on each of the level's props; hidden: exactly the layout's visual pieces (WarehouseVisual),
    still colliding where they did, the glows' lights still there; nothing else changed (the owner's sign and the STOCK
    board shown with their words, the stands, the desk, the paint, the prompts);
  - a warehouse of another size, a level whose door is not the import's, a warehouse with no plot: left as they were.
8.3, every level 1 … 5 on every plot: its Site (WarehouseLayout.site(plot, n)) built from WarehouseLayout.pieces(site) as
server/Warehouse.luau's build makes its parts (its lines are checked to be unchanged), handed to the real WarehouseMesh
(the Model's Level n):
  - the level's markers (its box, door and roof top) are the Site's (outline, door, warehouse.sy) and Config's level;
    every plot's Site is the same, only moved (the front wall, the door and the bay where level 4's are);
  - dressed with that level: every piece in place, anchored, not physical, its props' unseen solid blocks; the visual
    parts hidden, the solid ones still solid, nothing else changed (as above);
  - the game's solid walls inside the model's walls, its wedges (the gables, a shed's sloping side walls) inside the
    model's gables and sloping walls, its roof under the model's roof at every point (as tools/house-art/check.py
    checks the house's gable; the model's roof, gables and sloping walls rebuilt exactly from warehouse.py, each checked
    against the export's box of it), every other unseen solid part inside a detail of the model (a bollard in its
    post); the model's walls, gables and sloping walls all collide where they stand; the model's floor at the floor's
    top, under the whole hall;
  - each game lamp's light just under one of the model's lamps;
  - nothing of the model in a part the game keeps (the stands, the desk, the signs, the floor's paint, the bay), nor
    where the game needs room: the open hall (as high as the door, a stud under the back wall's top at most), the
    doorway and the way in (as high as the door, 14 at most: over that the model's own orange band hangs in front of
    the big levels' door tops), the UNLOAD HERE bay, over each stand (the catalogue's tallest piece on it and its tag
    over that, server/Warehouse.luau's), at the UPGRADES desk and before it, in front of the owner's sign, the STOCK
    board and the UPGRADES sign (the model's roof there by its exact underside, not by the box round it).
8.2's WarehouseMesh (its level Config.Warehouse.ArtLevel, its size the plain plot's) dresses a level's Site with the Site
in the plot's place for the call; 8.3's reads the Model's Level and the Site itself.
Every problem is listed (the level, the piece, the numbers), not only the first.

    python3 zombie-delivery/tools/warehouse/mesh-check.py <luau>
"""
import json
import math
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
EPS = 0.005  # the check's tolerance everywhere (studs)
BAY_HIGH = 11.0  # the UNLOAD HERE bay's room up (the van)
# The doorway's and the way in's room up: 14 (a carried wardrobe, a tall player: tests/warehouse_test.luau's), a lower
# door's height (over 14 the model's own orange band hangs in front of levels 4's and 5's door tops: the FBX's)
WAY_HIGH = 14.0
# The layout's pieces that are only looks (the model draws them) and those that stay (they work or are written).
VISUAL = re.compile(r"^(Floor|WallBack|WallWest|WallEast|WallSlope(West|East)|WallFrontWest|WallFrontEast|Header|"
                    r"Gable(Front|Back)(West|East)|Roof|Roof(West|East)|Barge(Front|Back)(West|East)|Gutter(West|East|Back)|"
                    r"Downpipe(West|East)|RidgeCap|Rib(Back|Front|Header|West|East)\d+|(Plinth|Stripe)(Back|West|East|FrontWest|FrontEast)|"
                    r"Corner(Front|Back)(West|East)|DoorRail(West|East)|Bollard(West|East)|DoorCurtain|DoorBar|DoorHood|"
                    r"ZdcSign|Beam\d+|Post\d+(West|East)|Lamp\d+|LampGlow\d+)$")
KEEP = re.compile(r"^(OwnerSign|StockBoard|UpgradeSign|Stand\d+|StandTop\d+|Plate\d+|Terminal\w+|Spot\d+\w*|"
                  r"SpotText\d+|Receiving\w+|AisleLine\w+|Bay\w+|"
                  r"ShowCarpet\d+|ShowFloorText\d+|HallFloorText\d+|(Show|Hall)Sign\d+(Wire(West|East))?)$")  # (10.4: the showroom and the hall)
WALLS = ("WallBack", "WallWest", "WallEast", "WallFrontWest", "WallFrontEast", "Header")
ROOFS = re.compile(r"^Roof(West|East)?$")
# The model's roof itself (its underside is rebuilt exactly below): its export box is only a box round a turned slab.
ROOF_DETAILS = ("Střecha", "Klenutá střecha")
# server/Warehouse.luau's lines the harness copies (its build of a layout piece, the stand's tag): if they change,
# change the harness with them.
WAREHOUSE_LINES = (
    'local p: BasePart = if d.shape == "Wedge" then Instance.new("WedgePart") else Instance.new("Part")',
    "p.Size = Vector3.new(d.size[1], d.size[2], d.size[3])",
    "p.CFrame = CFrame.new(d.at[1], d.at[2], d.at[3])",
    "* CFrame.Angles(0, math.rad(d.yaw or 0), 0)",
    "* CFrame.Angles(math.rad(d.pitch or 0), 0, math.rad(d.roll or 0))",
    "p.CanCollide = d.solid == true",
    "p.CanQuery = d.solid == true",
    "p.CastShadow = d.shadow == true",
    "p.Transparency = d.transparency or 0",
    "p:SetAttribute(WarehouseMesh.Attribute, d.visual)",
    "p.Shape = Enum.PartType.Cylinder",
    "WarehouseMesh.dress(model)",
    'model:SetAttribute("Plot", plot.id)',
)
TAG_LINES = ("tag.Size = UDim2.fromScale(7, 1.6) -- (studs)", "local top = WarehouseLayout.FloorTop + T.StandHeight + now.height",
             "local TAG_REACH, TAG_UNDER = 3.5, 0.9",
             "local roof = WarehouseLayout.ceiling(state.site, stand.podium.Position.Z - TAG_REACH) - TAG_UNDER",
             "stand.tag.StudsOffsetWorldSpace = Vector3.new(0, math.min(top + 1.3, roof) - stand.podium.Position.Y, 0)")
# a stand's tag: its width and height (studs), its middle over the piece's top, and (8.3) its middle at most this far
# under the hall's roof where its half width reaches back (WarehouseLayout.ceiling: a Garage's low back slope)
TAG = (7.0, 1.6, 1.3, 0.9)

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
local OLD = __OLD__ -- (8.2's WarehouseMesh: its level Config.Warehouse.ArtLevel, its size the plain plot's)

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
local FurnitureLooks = require("./FurnitureLooks")
local Config = require("./Config")
local function f(cf) local r = cf.R; return string.format("[%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f]", cf.Position.X, cf.Position.Y, cf.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]) end
local function rect(r, w) return string.format('{"x0":%.6f,"x1":%.6f,"z0":%.6f,"z1":%.6f}', r.x0 - w.x, r.x1 - w.x, r.z0 - w.z, r.z1 - w.z) end
local function list(t) local out = {} for _, v in t do table.insert(out, string.format("%.6f", v)) end return "[" .. table.concat(out, ",") .. "]" end

for finish in WarehouseMesh.Looks do
	print(string.format('LOOK {"finish":"%s"}', finish))
end
local tallest = 0
for _, id in FurnitureLooks.Order do
	tallest = math.max(tallest, FurnitureLooks.Items[id].size.Y)
end
print(string.format('META0 {"tallest":%.6f,"fit":%.6f,"levels":%d,"free":%s}', tallest, WarehouseLayout.Fit, WarehouseLayout.Levels,
	tostring(Config.Warehouse.FreeLevel or "null")))

-- A Site's numbers from its warehouse's middle on the ground (every one looks south: only moved); its world middle too.
local function layout(plot, tag, site)
	local w = site.warehouse
	local n = WarehouseLayout.levelOf(site)
	local def = WarehouseLayout.level(n)
	local o = WarehouseLayout.outline(site)
	local d = WarehouseLayout.door(site)
	local stands = {}
	for _, s in WarehouseLayout.stands(site, WarehouseLayout.capacity(n)) do
		table.insert(stands, string.format("[%.6f,%.6f,%.6f,%.6f,%.6f,%.6f]", s.x - w.x, s.z - w.z, s.sx, s.sz, s.y, WarehouseLayout.ceiling(site, s.z - 3.5)))
	end
	local t = WarehouseLayout.terminal(site)
	print(string.format('LAYOUT {"plot":%d,"tag":"%s","level":%d,"world":[%.6f,%.6f],"size":[%.6f,%.6f,%.6f],"outline":%s,"top":%.6f,"door":[%.6f,%.6f,%.6f,%.6f],"floorTop":%.6f,"wall":%.6f,"inside":%s,"doorPath":%s,"receiving":%s,"bay":%s,"stands":[%s],"count":%d,"capacity":%d,"terminal":[%.6f,%.6f,%.6f,%.6f,%.6f,%.6f],"def":{"name":"%s","size":%s,"door":%s,"roof":"%s","rise":%.6f,"stands":%d}}',
		plot.id, tag, n, w.x, w.z, w.sx, w.sy, w.sz, rect(o, w), o.top, d.x - w.x, d.z - w.z, d.width, d.height,
		WarehouseLayout.FloorTop, WarehouseLayout.Wall, rect(WarehouseLayout.inside(site), w), rect(WarehouseLayout.doorPath(site), w),
		rect(WarehouseLayout.receiving(site), w), rect(WarehouseLayout.bay(site), w), table.concat(stands, ","), WarehouseLayout.count(n),
		WarehouseLayout.capacity(n), t.x - w.x, t.z - w.z, t.sx, t.sz, t.y, t.yaw, def.name, list(def.size), list(def.door), def.roof, def.rise, def.stands))
end
for _, plot in SandboxMap.Plots do
	layout(plot, "plain", plot)
	for n = 1, WarehouseLayout.Levels do
		layout(plot, "L" .. n, WarehouseLayout.site(plot, n))
	end
end

local ana = W.player(101, "Ana", M.Vector3.new(-65, 3, -150))
-- (8.3's runtime has the players' upgrades: Ana's warehouse at level 4, the free plots at Config.Warehouse.FreeLevel)
local leveled = type(W.levels) == "table" and type(W.upgrade) == "function"
if leveled then
	W.levels[ana] = { warehouse = 3 }
end
W.claim(2, ana)
Warehouse.start()
local folder = M.workspace:FindFirstChild("Warehouses")

local function count(model)
	local n = 0
	for _, d in model:GetDescendants() do if d.ClassName == "MeshPart" or d.Name:sub(1, 14) == "WarehouseSolid" then n += 1 end end
	return n
end
local function levelOf(model)
	local n = model:GetAttribute("Level")
	return if type(n) == "number" then n else 4
end

-- What makes WarehouseMesh dress a Model at level n of plot `id` (8.3's: the Model's Level; 8.2's: ArtLevel and, with
-- OLD, the Site in the plot's place for the call), undone after.
local function withLevel(id, n, model, site, fn)
	local keep = { folder:GetAttribute("Level" .. id), Config.Warehouse.ArtLevel, SandboxMap.Plots[id] }
	model:SetAttribute("Plot", id)
	model:SetAttribute("Level", n)
	folder:SetAttribute("Level" .. id, n)
	Config.Warehouse.ArtLevel = n
	if OLD and site then SandboxMap.Plots[id] = site end
	local result = fn()
	SandboxMap.Plots[id] = keep[3]
	Config.Warehouse.ArtLevel = keep[2]
	folder:SetAttribute("Level" .. id, keep[1])
	return result
end

local before = count(Warehouse.model(1))
local again = WarehouseMesh.dress(Warehouse.model(1))
local after = count(Warehouse.model(1))
-- a warehouse of another size, a level whose door is not the import's, one with no plot: left as they are
local function stray()
	local model = M.Instance.new("Model")
	local wall = M.Instance.new("Part")
	wall.Name = "WallBack"
	wall:SetAttribute(WarehouseMesh.Attribute, true)
	wall.Parent = model
	return model, wall
end
local function untouched(model, wall)
	return wall.Transparency ~= 1 and model:FindFirstChild("WarehouseMesh") == nil and model:GetAttribute("MeshArt") == nil
end
local levels = Config.Warehouse.Levels
local w1 = SandboxMap.Plots[1].warehouse
local wide, wideWall = stray()
w1.sx += 4
levels[4].size[1] += 4
local wideDressed = withLevel(1, 4, wide, nil, function() return WarehouseMesh.dress(wide) end)
w1.sx -= 4
levels[4].size[1] -= 4
local other, otherWall = stray()
levels[5].door[1] -= 2
local otherDressed = withLevel(1, 5, other, nil, function() return WarehouseMesh.dress(other) end)
levels[5].door[1] += 2
local lost, lostWall = stray()
local lostDressed = withLevel(99, 4, lost, nil, function() return WarehouseMesh.dress(lost) end)
print(string.format('META {"moved":%s,"ready":%s,"again":%s,"before":%d,"after":%d,"strays":%s}',
	tostring(art.Parent == storage and MODE == "art"), tostring(WarehouseMesh.ready()), tostring(again), before, after,
	tostring(not (wideDressed or otherDressed or lostDressed) and untouched(wide, wideWall) and untouched(other, otherWall) and untouched(lost, lostWall))))

local function dump(model, plot, tag, base)
	print(string.format('PLOT {"plot":%d,"tag":"%s","dressed":%s,"level":%d,"worn":%s,"meshes":%d}', plot, tag, tostring(model:GetAttribute("MeshArt") == true),
		levelOf(model), tostring(model:GetAttribute("WarehouseLevel") or "null"), count(model)))
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
			print(string.format('PART {"plot":%d,"tag":"%s","class":"%s","shape":"%s","name":"%s","parent":"%s","cf":%s,"size":[%.6f,%.6f,%.6f],"t":%g,"shadow":%s,"collide":%s,"query":%s,"touch":%s,"anchored":%s,"visual":%s,"skin":%s,"guis":[%s],"lights":%d,"prompts":%d,"color":[%.4f,%.4f,%.4f]}',
				plot, tag, d.ClassName, tostring(d.Shape or ""), d.Name, d.Parent.Name, f(base:Inverse() * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, d.Transparency or 0,
				tostring(d.CastShadow), tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Anchored),
				tostring(d:GetAttribute(WarehouseMesh.Attribute) == true), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil),
				table.concat(guis, ","), lights, prompts, d.Color.R, d.Color.G, d.Color.B))
		end
	end
end

-- 8.2: the warehouses server/Warehouse.luau built, each at its Model's level
for _, plot in SandboxMap.Plots do
	local model = Warehouse.model(plot.id)
	local site = WarehouseLayout.site(plot, levelOf(model))
	dump(model, plot.id, "real", M.CFrame.new(site.warehouse.x, 0, site.warehouse.z))
end
if leveled then
	-- 8.3: Ana buys the Logistics Center: her plot rebuilt at level 5 (a new Model) and dressed anew
	W.upgrade(ana, { warehouse = 4 })
	local model = Warehouse.model(2)
	local site = WarehouseLayout.site(2, levelOf(model))
	dump(model, 2, "rebuilt", M.CFrame.new(site.warehouse.x, 0, site.warehouse.z))
end
print(string.format('META1 {"leveled":%s}', tostring(leveled)))

-- 8.3: every level on every plot, its parts as server/Warehouse.luau's build makes them (WAREHOUSE_LINES)
local function build(parent, d)
	local p = M.Instance.new(if d.shape == "Wedge" then "WedgePart" else "Part")
	p.Name = d.name
	p.Size = M.Vector3.new(d.size[1], d.size[2], d.size[3])
	p.CFrame = M.CFrame.new(d.at[1], d.at[2], d.at[3]) * M.CFrame.Angles(0, math.rad(d.yaw or 0), 0) * M.CFrame.Angles(math.rad(d.pitch or 0), 0, math.rad(d.roll or 0))
	p.Color = M.Color3.fromRGB(d.color[1], d.color[2], d.color[3])
	p.Material = d.material
	p.Anchored = true
	p.CanCollide = d.solid == true
	p.CanQuery = d.solid == true
	p.CanTouch = false
	p.CastShadow = d.shadow == true
	p.Transparency = d.transparency or 0
	p:SetAttribute(WarehouseMesh.Attribute, d.visual)
	if d.shape == "Cylinder" then
		p.Shape = "Cylinder"
	end
	for _, w in d.words or {} do
		local gui = M.Instance.new("SurfaceGui")
		gui.Name = "Words" .. w.face
		gui.Parent = p
	end
	if d.light then
		M.Instance.new("PointLight").Parent = p
	end
	p.Parent = parent
	return p
end
for _, plot in SandboxMap.Plots do
	for n = 1, WarehouseLayout.Levels do
		local site = WarehouseLayout.site(plot, n)
		local model = M.Instance.new("Model")
		for _, d in WarehouseLayout.pieces(site) do
			build(model, d)
		end
		model.WorldPivot = M.CFrame.new(site.warehouse.x, 0, site.warehouse.z)
		-- (in the Warehouses folder in the plot's warehouse's place while it is dressed)
		local real = Warehouse.model(plot.id)
		model.Name = real.Name
		real.Parent = nil
		model.Parent = folder
		withLevel(plot.id, n, model, site, function() return WarehouseMesh.dress(model) end)
		model.Parent = nil
		real.Parent = folder
		dump(model, plot.id, "L" .. n, M.CFrame.new(site.warehouse.x, 0, site.warehouse.z))
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
    mesh = (server / "WarehouseMesh.luau").read_text()
    text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', mesh)
    assert "script.Parent" not in text, "WarehouseMesh requires a module this check does not stage"
    (tmp / "WarehouseMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\nlocal warn = function(...) print(\"WARN\", ...) end\n" + text)
    text = (server / "Warehouse.luau").read_text()
    for line in ("local WarehouseMesh = require(script.Parent.WarehouseMesh)",) + WAREHOUSE_LINES + TAG_LINES:
        assert line in text, f"server/Warehouse.luau changed ({line!r}): change this check's harness with it"
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
    # (8.2's WarehouseMesh, before the levels are a player's: it knows no Site)
    old = "WarehouseLayout.site(" not in mesh
    (tmp / "harness.luau").write_text(HARNESS.replace("__OLD__", "true" if old else "false"))
    return old


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
        elif kind in ("META", "META0", "META1"):
            out[kind] = json.loads(rest)
    return out


# ── Geometry (the warehouse's frame: its middle on the ground, x east, y up, z south to the door) ─────────────────

def aabb(part):
    """A part's box in its warehouse's frame (its cf is already there)."""
    r = part["cf"][3:]
    half = [sum(abs(r[i * 3 + j]) * part["size"][j] for j in range(3)) / 2 for i in range(3)]
    at = part["cf"][:3]
    return [at[i] - half[i] for i in range(3)], [at[i] + half[i] for i in range(3)]


def vertices(part):
    """A part's corners (a WedgePart's six: its slope from its bottom front edge, -Z, up to its top back edge, +Z)."""
    c, r, s = part["cf"][:3], part["cf"][3:], part["size"]
    if part["class"] == "WedgePart":
        local = [(dx, -0.5, dz) for dx in (-0.5, 0.5) for dz in (-0.5, 0.5)] + [(dx, 0.5, 0.5) for dx in (-0.5, 0.5)]
    else:
        local = [(dx, dy, dz) for dx in (-0.5, 0.5) for dy in (-0.5, 0.5) for dz in (-0.5, 0.5)]
    return [[c[i] + sum(r[i * 3 + j] * l[j] * s[j] for j in range(3)) for i in range(3)] for l in local]


def placed(box, depth):
    """A box from the level's origin (x right seen from outside, z into the building) in the warehouse's frame (its
    middle on the ground, x east, z south): the door on the south wall's middle, turned round."""
    (gx, gy, gz), (sx, sy, sz) = box["center"], box["size"]
    c = [-gx, gy, depth / 2 - gz]
    return [c[0] - sx / 2, c[1] - sy / 2, c[2] - sz / 2], [c[0] + sx / 2, c[1] + sy / 2, c[2] + sz / 2]


def overlap(a, b, margin=EPS):
    return all(a[0][i] < b[1][i] - margin and b[0][i] < a[1][i] - margin for i in range(3))


def inside(a, b, eps=1e-3):
    return all(b[0][i] - eps <= a[0][i] and a[1][i] <= b[1][i] + eps for i in range(3))


def in_box(p, b, eps=1e-3):
    return all(b[0][i] - eps <= p[i] <= b[1][i] + eps for i in range(3))


def close(a, b, eps=2e-3):
    return all(abs(x - y) < eps for x, y in zip(a, b))


def fmt(v):
    return "(" + ", ".join(f"{x:.3f}" for x in v) + ")"


def rot(axis, a):
    c, s = math.cos(a), math.sin(a)
    return {"x": [[1, 0, 0], [0, c, -s], [0, s, c]], "y": [[c, 0, s], [0, 1, 0], [-s, 0, c]]}[axis]


class Shell:
    """warehouse.py's roof, gables and a shed's sloping side walls for one level, exactly (roofing() and building():
    the slabs 0.4 thick, a stud over the walls all round, a gable's slab 0.25 over its ridge line, the barrel's arc in 28
    flat pieces 0.6 past the walls; the gables and sloping walls a stud thick). The export only has a box round each of
    them; verify() matches these boxes to it. Points are the warehouse's frame; Blender's from the level's origin: x the
    same, y = D / 2 - z, z = y."""

    def __init__(self, level):
        W, H, D = level["size"]
        self.W, self.H, self.D, self.kind = W, H, D, level["roof"]
        hw, over, wall, thick = W / 2, 1.0, 1.0, 0.4
        back = next(d for d in level["details"] if re.sub(r"\.\d+$", "", d["name"]) == "Zadní zeď")["size"][1]
        self.back = back  # (the hall's lowest wall: a shed's back wall)
        self.rise = H - back if self.kind == "shed" else level["marks"]["top"][1] - H
        self.slabs, self.prisms = [], []
        rise = self.rise

        def frame(p):
            return [p[0], p[2], D / 2 - p[1]]

        def box(size, at, R):
            return [frame([at[i] + sum(R[i][j] * size[j] * d[j] for j in range(3)) for i in range(3)])
                    for d in [(x, y, z) for x in (-0.5, 0.5) for y in (-0.5, 0.5) for z in (-0.5, 0.5)]]
        if self.kind == "shed":
            a = math.atan2(rise, D)
            at = (0, D / 2, (H + back) / 2 + 0.2)
            self.slabs.append(("Střecha", box((W + 2 * over, (D + 2 * over) / math.cos(a), thick), at, rot("x", -a))))
            # the slab's underside: a plane falling to the back, between its end faces
            self.cover = (-(hw + over), hw + over, D / 2 - (D + over - thick / 2 * math.sin(a)), D / 2 + over + thick / 2 * math.sin(a))
            self.under = lambda x, z: at[2] - ((D / 2 - z) - D / 2) * math.tan(a) - thick / 2 / math.cos(a)
            for s in (-1, 1):
                x0, x1 = sorted((s * hw, s * (hw - wall)))
                self.prisms.append(("Boční zeď štít", "x", (x0, x1), [(0, back), (D, back), (0, H)]))
        elif self.kind == "gable":
            half = hw + over
            a = math.atan2(rise, hw)
            for s in (-1, 1):
                at = (s * half / 2, D / 2, H + rise - (half / 2) * math.tan(a) + 0.25)
                self.slabs.append(("Střecha", box((half / math.cos(a), D + 2 * over, thick), at, rot("y", s * a))))
            reach = half - thick / 2 * math.sin(a)
            self.cover = (-reach, reach, -D / 2 - over, D / 2 + over)
            self.under = lambda x, z: H + rise + 0.25 - abs(x) * math.tan(a) - thick / 2 / math.cos(a)
            tri = [(-hw, H), (hw, H), (0, H + rise)]
            self.prisms += [("Štít", "y", (0, wall), tri), ("Štít", "y", (D - wall, D), tri)]
        else:  # barrel
            r = (hw * hw + rise * rise) / (2 * rise)
            cz, a0, seg = H + rise - r, math.asin(hw / r), 28
            angles = [-a0 + 2 * a0 * k / seg for k in range(seg + 1)]
            arc = [(r * math.sin(t), cz + r * math.cos(t)) for t in angles]
            outer = [(x + math.sin(t) * thick, z + math.cos(t) * thick) for (x, z), t in zip(arc, angles)]
            self.slabs.append(("Klenutá střecha", [frame((x, y, z)) for x, z in arc + outer for y in (-0.6, D + 0.6)]))
            self.cover = (arc[0][0], arc[-1][0], -D / 2 - 0.6, D / 2 + 0.6)

            def under(x, z):
                for (x1, z1), (x2, z2) in zip(arc, arc[1:]):
                    if x1 - 1e-9 <= x <= x2 + 1e-9:
                        return z1 + (z2 - z1) * (x - x1) / (x2 - x1)
                return math.inf
            self.under = under
            self.prisms += [("Štít", "y", (0, wall), arc), ("Štít", "y", (D - wall, D), arc)]

    def covered(self, x, z, eps=1e-3):
        c = self.cover
        return c[0] - eps <= x <= c[1] + eps and c[2] - eps <= z <= c[3] + eps

    def verify(self, details):
        """Each rebuilt piece's box against the export's (1e-3: the manifest has 4 decimals)."""
        out = []
        for name, pts in self.slabs + [(p[0], self.prism_points(p)) for p in self.prisms]:
            lo = [min(p[i] for p in pts) for i in range(3)]
            hi = [max(p[i] for p in pts) for i in range(3)]
            boxes = [d["box"] for d in details if d["name"] == name]
            off = min((max(abs(a - b) for a, b in zip(lo + hi, d[0] + d[1])) for d in boxes), default=math.inf)
            if off > 1e-3:
                out.append(f"{name}: warehouse.py's piece rebuilt here is {fmt(lo)} … {fmt(hi)}, the export's is {off:.4f} off")
        return out

    def prism_points(self, p, grid=0):
        """A gable's or a sloping wall's corners (grid > 0: points all over it too)."""
        _, axis, (d0, d1), poly = p
        pts = list(poly)
        if grid:
            us = [u for u, _ in poly]
            for i in range(grid + 1):
                u = min(us) + (max(us) - min(us)) * i / grid
                low, high = self._span(poly, u)
                for j in range(grid + 1):
                    pts.append((u, low + (high - low) * j / grid))
        out = []
        for d in (d0, d1) if not grid else [d0 + (d1 - d0) * k / 4 for k in range(5)]:
            for u, v in pts:
                out.append([u, v, self.D / 2 - d] if axis == "y" else [d, v, self.D / 2 - u])
        return out

    @staticmethod
    def _span(poly, u):
        vs = []
        n = len(poly)
        for i in range(n):
            (u1, v1), (u2, v2) = poly[i], poly[(i + 1) % n]
            if min(u1, u2) - 1e-9 <= u <= max(u1, u2) + 1e-9:
                vs += [v1] if u1 == u2 else [v1 + (v2 - v1) * (u - u1) / (u2 - u1)]
                if u1 == u2:
                    vs.append(v2)
        return min(vs), max(vs)

    def in_prism(self, p, point, eps=1e-3):
        _, axis, (d0, d1), poly = p
        x, y, z = point
        depth, u, v = (self.D / 2 - z, x, y) if axis == "y" else (x, self.D / 2 - z, y)
        if not (min(d0, d1) - eps <= depth <= max(d0, d1) + eps):
            return False
        n = len(poly)
        area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
        sign = 1 if area > 0 else -1
        for i in range(n):
            (u1, v1), (u2, v2) = poly[i], poly[(i + 1) % n]
            length = math.hypot(u2 - u1, v2 - v1)
            if length < 1e-12:
                continue
            if sign * ((u2 - u1) * (v - v1) - (v2 - v1) * (u - u1)) / length < -eps:
                return False
        return True

    def roof_low(self, lo, hi):
        """The model roof's lowest underside over a box's top (nil: no roof over it). Its underside is concave and
        depends on one axis only, so the least is at a corner of the box's top clipped to the roof."""
        c = self.cover
        x0, x1, z0, z1 = max(lo[0], c[0]), min(hi[0], c[1]), max(lo[2], c[2]), min(hi[2], c[3])
        if x0 > x1 or z0 > z1:
            return None
        return min(self.under(x, z) for x in (x0, x1) for z in (z0, z1))


# ── The import ───────────────────────────────────────────────────────────────

class Problems:
    def __init__(self):
        self.items = []

    def add(self, where, text):
        self.items.append(f"{where}: {text}")

    def check(self, ok, where, text):
        if not ok:
            self.add(where, text)
        return ok


def check_import(manifest, looks, problems):
    for name, p in manifest["pieces"].items():
        where = f"import {name}"
        problems.check(re.fullmatch(r"lvl\d+[a-z]?_[a-z0-9]+", name), where, "not lvl<N>_<finish>")
        problems.check(p["triangles"] <= 10000, where, f"{p['triangles']} triangles in one piece (at most 10,000)")
        problems.check(min(p["size"]) >= 0.01, where, f"a flat piece {p['size']} (Roblox sizes a mesh by its box)")
        problems.check(name.split("_", 1)[1] in looks, where, "a finish without a look in WarehouseMesh.Looks")


def details_of(level, D):
    # (Blender numbers a name again in another level: "Střecha.005")
    return [dict(d, name=re.sub(r"\.\d+$", "", d["name"]), box=placed(d, D)) for d in level["details"]]


# ── 8.2: the warehouses server/Warehouse.luau builds ─────────────────────────

def check_real(manifest, plain, art, problems):
    meta = plain["META"]
    problems.check(not (meta["ready"] or meta["moved"] or meta["again"] or meta["before"] or meta["after"]) and meta["strays"],
                   "no import", f"something happened without the import: {meta}")
    meta = art["META"]
    problems.check(meta["ready"] and meta["moved"], "import", f"the import was not taken out of the world: {meta}")
    problems.check(meta["strays"], "strays", "dressed a warehouse of another size, a level of another door or one with no plot")
    problems.check(meta["again"] and meta["before"] == meta["after"], "again", f"dressing a warehouse again added pieces: {meta}")
    problems.check(not art["WARN"], "warnings", f"{art['WARN'][:4]}")
    levels = {}
    for result, mode in ((plain, "plain"), (art, "art")):
        for p in result["PLOT"]:
            if p["tag"] in ("real", "rebuilt"):
                levels[(mode, p["plot"], p["tag"])] = p
    if art["META1"]["leveled"]:
        # (8.3's runtime: the owner's warehouse at level 4, the free plots at FreeLevel, the owner's level 5 rebuilt)
        free = plain["META0"]["free"]
        for (mode, plot, tag), p in sorted(levels.items()):
            want = 5 if tag == "rebuilt" else 4 if plot == 2 else free
            problems.check(p["level"] == want, f"{tag} plot {plot}", f"built at level {p['level']}, not {want}")
        problems.check(("art", 2, "rebuilt") in levels, "rebuilt plot 2", "the owner's warehouse not rebuilt on an upgrade")
    for (mode, plot, tag), p in sorted(levels.items()):
        where = f"{tag} plot {plot} (level {p['level']})"
        n = p["level"]
        lv = manifest["levels"][str(n)]
        pieces = {k: v for k, v in manifest["pieces"].items() if v["level"] == n}
        if mode == "plain":
            problems.check(not p["dressed"] and not p["meshes"], where, "dressed without the import")
            continue
        problems.check(p["dressed"] and p["meshes"] == len(pieces) + len(lv["solids"]) and p["worn"] in (n, "null"), where,
                       f"not dressed once with its level: {p}")
        problems.check(levels[("plain", plot, tag)]["level"] == n, where, "its level changed when dressed")
        check_dressed(where, n, lv, pieces, plain, art, tag, plot, problems)
        if plot == 2:
            parts = [q for q in art["PART"] if q["tag"] == tag and q["plot"] == 2]
            problems.check(sum(q["prompts"] for q in parts) > 0, where, "the owner's prompts are gone")
    return sorted((plot, p["level"]) for (mode, plot, tag), p in levels.items() if mode == "art" and tag == "real"), \
        [p["level"] for (mode, plot, tag), p in levels.items() if mode == "art" and tag == "rebuilt"]


def check_dressed(where, n, lv, pieces, plain, art, tag, plot, problems):
    """One warehouse dressed with level n: its pieces in place, the props' blocks, the visual parts hidden, the rest as
    built. Returns the largest offset of a piece."""
    D = lv["size"][2]
    mine = [p for p in art["PART"] if p["tag"] == tag and p["plot"] == plot]
    was = {p["name"]: p for p in plain["PART"] if p["tag"] == tag and p["plot"] == plot}
    meshes = [p for p in mine if p["parent"] == "WarehouseMesh" and p["class"] == "MeshPart"]
    names = sorted(p["name"] for p in meshes)
    if not problems.check(names == sorted(pieces), where, f"the pieces dressed are not level {n}'s: {sorted(set(names) ^ set(pieces))[:6]}"):
        return 0.0
    worst = 0.0
    for m in meshes:
        problems.check(m["anchored"] and not (m["collide"] or m["query"] or m["touch"]), where, f"{m['name']} physical")
        problems.check(not m["skin"], where, f"{m['name']}: the importer's SurfaceAppearance kept")
        lo, hi = aabb(m)
        want = placed(pieces[m["name"]], D)
        off = max(abs(a - b) for a, b in zip(lo + hi, want[0] + want[1]))
        worst = max(worst, off)
        problems.check(off < 2e-3, where, f"{m['name']} at {fmt(lo)} … {fmt(hi)}, the model has it at {fmt(want[0])} … {fmt(want[1])}")
    # (one block a prop, in any order: the importer's order of the pieces is its own)
    blocks = [p for p in mine if p["parent"] == "WarehouseMesh" and p["class"] == "Part"]
    if problems.check(sorted(b["name"] for b in blocks) == sorted(f"WarehouseSolid{k}" for k in range(1, len(lv["solids"]) + 1)), where,
                      f"{len(blocks)} solid blocks for the level's {len(lv['solids'])} props"):
        boxes = [placed(box, D) for box in lv["solids"]]
        for b in blocks:
            problems.check(b["anchored"] and b["collide"] and b["query"] and not b["touch"] and b["t"] == 1, where, f"the prop's block {b['name']} is not an unseen solid block")
            lo, hi = aabb(b)
            match = [k for k, want in enumerate(boxes) if close(lo, want[0]) and close(hi, want[1])]
            if problems.check(match, where, f"{b['name']} at {fmt(lo)} … {fmt(hi)} is on none of the level's props"):
                boxes.pop(match[0])
    for p in (p for p in mine if p["parent"] != "WarehouseMesh"):
        before = was.get(p["name"])
        if not problems.check(before is not None, where, f"{p['name']}: a part the plain warehouse does not have"):
            continue
        for key in ("collide", "query", "touch", "anchored", "cf", "size", "lights", "prompts", "color"):
            problems.check(p[key] == before[key], where, f"{p['name']}: its {key} changed when dressed")
        if p["visual"]:
            problems.check(p["t"] == 1 and p["shadow"] is False and all(g is False for g in p["guis"]), where, f"{p['name']} still seen")
        else:
            problems.check(p["t"] == before["t"] and p["shadow"] == before["shadow"] and p["guis"] == before["guis"], where, f"{p['name']} changed")
    parts = {p["name"]: p for p in mine}
    for name in ("OwnerSign", "StockBoard", "UpgradeSign"):
        problems.check(name in parts and parts[name]["t"] == 0 and parts[name]["guis"] == [True], where, f"{name}: its words not shown")
    if "ZdcSign" in parts:
        problems.check(parts["ZdcSign"]["guis"] == [False], where, "the parts' ZDC sign still shows its words")
    glows = [p for k, p in parts.items() if k.startswith("LampGlow")]
    problems.check(glows and all(g["lights"] == 1 for g in glows), where, "a lamp's light lost")
    return worst


# ── 8.3: every level on its Site ─────────────────────────────────────────────

def check_layouts(manifest, out, problems):
    """Every plot's Sites: Config's levels, the model's, only moved; the front wall, the door and the bay where they
    always are; a plain Plot is level 4."""
    lays = {(l["plot"], l["tag"]): l for l in out["LAYOUT"]}
    plots = sorted({l["plot"] for l in out["LAYOUT"]})
    keys = ("size", "outline", "top", "door", "floorTop", "inside", "doorPath", "receiving", "bay", "stands", "count", "capacity", "terminal")
    for n in range(1, 6):
        lay = lays[(plots[0], f"L{n}")]
        where = f"level {n}"
        level = manifest["levels"][str(n)]
        W, H, D = level["size"]
        problems.check(lay["level"] == n, where, f"WarehouseLayout.site(plot, {n}) is level {lay['level']}")
        d = lay["def"]
        problems.check(close(d["size"], (W, H, D), 1e-6) and close(d["door"], level["door"], 1e-6) and d["roof"] == level["roof"], where,
                       f"Config.Warehouse.Levels[{n}] ({d['size']}, door {d['door']}, {d['roof']}) is not the Blender level ({level['size']}, door {level['door']}, {level['roof']})")
        problems.check(close(lay["size"], (W, H, D), 1e-6), where, f"the Site's warehouse is {lay['size']}, the level {level['size']}")
        o = lay["outline"]
        problems.check(close((o["x0"], o["x1"], o["z0"], o["z1"]), (-W / 2, W / 2, -D / 2, D / 2), 1e-6), where, f"the outline {o}")
        marks = level["marks"]
        problems.check(close(marks["box"], (W / 2, H, D), 1e-4) and close(marks["door"], (level["door"][0] / 2, level["door"][1], 0), 1e-4), where, f"the markers {marks}")
        problems.check(abs(marks["top"][1] - lay["top"]) < 1e-4, where, f"the model's top {marks['top'][1]}, the Site's outline top {lay['top']}")
        problems.check(close(level["door"], lay["door"][2:], 1e-6) and close(lay["door"][:2], (0, D / 2), 1e-6), where, f"the door {lay['door']}, the level's {level['door']}")
        problems.check(abs(level["floorTop"] - lay["floorTop"]) < 1e-6, where, f"the model's floor top {level['floorTop']}, WarehouseLayout.FloorTop {lay['floorTop']}")
        problems.check(lay["count"] == d["stands"] and len(lay["stands"]) == lay["capacity"], where, f"{lay['count']} big stands of {lay['capacity']}, Config's {d['stands']}")
        for plot in plots:
            other = lays[(plot, f"L{n}")]
            problems.check(all(other[k] == lay[k] for k in keys), f"level {n}, plot {plot}", f"its Site is not plot {plots[0]}'s moved")
            four = lays[(plot, "L4")]
            front = other["world"][1] + other["size"][2] / 2
            problems.check(abs(front - (four["world"][1] + four["size"][2] / 2)) < 1e-6 and abs(other["world"][0] - four["world"][0]) < 1e-6,
                           f"level {n}, plot {plot}", "its front wall is not where level 4's is")
            world = lambda l, r: (r["x0"] + l["world"][0], r["x1"] + l["world"][0], r["z0"] + l["world"][1], r["z1"] + l["world"][1])
            problems.check(close(world(other, other["bay"]), world(four, four["bay"]), 1e-6), f"level {n}, plot {plot}", "the UNLOAD HERE bay moved")
            problems.check(abs(other["door"][1] + other["world"][1] - (four["door"][1] + four["world"][1])) < 1e-6, f"level {n}, plot {plot}", "the door moved")
    for plot in plots:
        plain, four = lays[(plot, "plain")], lays[(plot, "L4")]
        problems.check(plain["level"] == 4 and all(plain[k] == four[k] for k in keys), f"plot {plot}", "a plain Plot is not level 4's Site")
    return lays, plots


def check_level(n, manifest, lays, plots, plain, art, meta0, problems):
    where = f"level {n}"
    tag = f"L{n}"
    level = manifest["levels"][str(n)]
    W, H, D = level["size"]
    lay = lays[(plots[0], tag)]
    pieces = {k: v for k, v in manifest["pieces"].items() if v["level"] == n}
    solids = level["solids"]
    details = details_of(level, D)
    shell = Shell(level)
    for text in shell.verify(details):
        problems.add(f"{where} (warehouse.py)", text)

    # Without the import: as built. The visual pieces exactly the looks, none of what stays.
    for p in plain["PLOT"]:
        if p["tag"] == tag:
            problems.check(not p["dressed"] and not p["meshes"], f"{where}, plot {p['plot']}", "dressed without the import")
    parts = {p["name"]: p for p in plain["PART"] if p["tag"] == tag and p["plot"] == plots[0]}
    problems.check(len(parts) == len([p for p in plain["PART"] if p["tag"] == tag and p["plot"] == plots[0]]), where, "two parts share a name")
    for plot in plots[1:]:
        mine = {p["name"]: p for p in plain["PART"] if p["tag"] == tag and p["plot"] == plot}
        problems.check(mine.keys() == parts.keys() and all(close(mine[k]["cf"], parts[k]["cf"], 1e-6) and mine[k]["size"] == parts[k]["size"] for k in parts),
                       f"{where}, plot {plot}", f"its parts are not plot {plots[0]}'s moved")
    visual = {k for k, p in parts.items() if p["visual"]}
    want = {k for k in parts if VISUAL.match(k)}
    problems.check(visual == want, where, f"the visual pieces: {sorted(visual ^ want)[:8]}")
    stray = sorted(k for k in parts if not VISUAL.match(k) and not KEEP.match(k))
    problems.check(not stray, where, f"pieces the check does not know (visual or kept?): {stray[:8]}")
    for name in ("OwnerSign", "StockBoard", "UpgradeSign", "Stand1", "TerminalDesk", "ReceivingText", "BayText"):
        problems.check(name in parts and name not in visual, where, f"{name} must be there and stay as it is")

    # With it: every plot dressed with the level.
    worst = 0.0
    for p in art["PLOT"]:
        if p["tag"] != tag:
            continue
        w = f"{where}, plot {p['plot']}"
        problems.check(p["dressed"] and p["level"] == n and p["meshes"] == len(pieces) + len(solids) and p["worn"] in (n, "null"), w,
                       f"not dressed with level {n} (dressed {p['dressed']}, worn {p['worn']}, {p['meshes']} meshes of {len(pieces) + len(solids)})")
        worst = max(worst, check_dressed(w, n, level, pieces, plain, art, tag, p["plot"], problems))

    # The model on the colliders.
    walls = [placed(b, D) for b in level["collide"]]
    for name in WALLS:
        if not problems.check(name in parts and parts[name]["collide"], where, f"{name}: not there or not solid"):
            continue
        wall = aabb(parts[name])
        fits = any(inside(wall, b) and any(abs((b[1][i] - b[0][i]) - (wall[1][i] - wall[0][i])) < 1e-3 and wall[1][i] - wall[0][i] < 1.5 for i in (0, 2)) for b in walls)
        problems.check(fits, where, f"{name} {fmt(wall[0])} … {fmt(wall[1])} is not inside a wall of the model (as thick)")
    game_walls = [aabb(parts[k]) for k in WALLS if k in parts]
    for b in walls:  # (and no wall of the model where nothing collides)
        pts = [[b[k][0], b[j][1], b[i][2]] for k in (0, 1) for j in (0, 1) for i in (0, 1)] + [[(b[0][i] + b[1][i]) / 2 for i in range(3)]]
        problems.check(all(any(in_box(p, g) for g in game_walls) for p in pts), where, f"a wall of the model nothing collides with: {fmt(b[0])} … {fmt(b[1])}")
    hidden_solid = {k: p for k, p in parts.items() if p["visual"] and p["collide"]}
    wedges = {k: p for k, p in hidden_solid.items() if p["class"] == "WedgePart"}
    for name, p in wedges.items():
        pts = vertices(p)
        homes = [pr for pr in shell.prisms if all(shell.in_prism(pr, q) for q in pts)]
        if not homes:
            out = [q for q in pts if not any(shell.in_prism(pr, q) for pr in shell.prisms)]
            problems.add(where, f"{name} (a wedge, solid) not inside a gable or sloping wall of the model: its corner(s) {', '.join(fmt(q) for q in out[:3])}")
    if shell.kind != "barrel":  # (the barrel's gables rise over the game's own gable: out of reach, 28 studs up)
        for pr in shell.prisms:
            pts = shell.prism_points(pr, grid=8)
            loose = [q for q in pts if not any(shell_in_wedge(w, q) for w in wedges.values()) and not any(in_box(q, g) for g in game_walls)]
            problems.check(not loose, where, f"the model's {pr[0]} ({pr[1]} {pr[2][0]:g} … {pr[2][1]:g}) does not collide all over, e.g. at {fmt(loose[0]) if loose else ''}")
    # the roof under the model's roof at every point (its parts are convex and the model's underside concave: their
    # corners say it), the gables and sloping walls too
    under_worst = math.inf
    roofs = {k: p for k, p in hidden_solid.items() if ROOFS.match(k)}
    problems.check(roofs, where, "no solid roof")
    for name, p in list(roofs.items()) + list(wedges.items()):
        corners = vertices(p)
        out = [q for q in corners if not shell.covered(q[0], q[2])]
        if out:
            c = shell.cover
            far = max(max(c[0] - q[0], q[0] - c[1], c[2] - q[2], q[2] - c[3]) for q in out)
            problems.add(where, f"{name}: {len(out)} corner(s) past the model's roof, up to {far:.3f} (e.g. {fmt(out[0])}; the roof reaches x {c[0]:.3f} … {c[1]:.3f}, z {c[2]:.3f} … {c[3]:.3f})")
        c = shell.cover
        inn = [(shell.under(min(max(q[0], c[0]), c[1]), min(max(q[2], c[2]), c[3])) - q[1], q) for q in corners]
        margin, q = min(inn)
        under_worst = min(under_worst, margin)
        if margin < -EPS:
            problems.add(where, f"{name}: up to {-margin:.3f} over the model's roof's underside (its corner {fmt(q)}, the underside {margin + q[1]:.3f} there)")
    # every other unseen solid part inside a piece of the model (a bollard in its post)
    known = set(WALLS) | set(wedges) | set(roofs) | {"Floor"}
    for name, p in hidden_solid.items():
        if name in known:
            continue
        box = aabb(p)
        home = [d for d in details if inside(box, d["box"]) or (p["shape"] == "Cylinder" and round_in(box, d["box"]))]
        problems.check(home, where, f"{name} (solid, unseen) {fmt(box[0])} … {fmt(box[1])} is not inside anything of the model: an invisible thing to bump into")
    floor = aabb(parts["Floor"])
    floors = [d["box"] for d in details if d["name"].startswith("Podlaha")]
    problems.check(floors and all(abs(f[1][1] - lay["floorTop"]) < 1e-4 for f in floors) and abs(floor[1][1] - lay["floorTop"]) < 1e-6, where,
                   f"the model's floor is not at the floor's top {[f[1][1] for f in floors]}")
    hall = lay["inside"]
    problems.check(any(f[0][0] <= hall["x0"] + 1e-3 and f[1][0] >= hall["x1"] - 1e-3 and f[0][2] <= hall["z0"] + 1e-3 and f[1][2] >= hall["z1"] - 1e-3 for f in floors),
                   where, "the model's floor does not cover the hall")
    lamps = [d["box"] for d in details if d["finish"] == "glow"]
    glows = {k: aabb(p) for k, p in parts.items() if k.startswith("LampGlow")}
    for name, glow in glows.items():
        over = [b for b in lamps if abs((b[0][0] + b[1][0]) / 2 - (glow[0][0] + glow[1][0]) / 2) < 0.05
                and abs((b[0][2] + b[1][2]) / 2 - (glow[0][2] + glow[1][2]) / 2) < 0.05 and 0 <= b[0][1] - glow[1][1] <= 1.5]
        problems.check(len(over) == 1, where, f"{name}: no lamp of the model just over its light (the glow {fmt(glow[0])} … {fmt(glow[1])})")

    # Clear: nothing of the model in a part the game keeps, nor where the game needs room.
    kept = [(k, ("box", *aabb(p))) for k, p in parts.items() if not p["visual"]]
    rooms = rooms_of(lay, parts, meta0, shell.back)
    clashes = []
    things = [(d["name"], d["box"]) for d in details if d["name"] not in ROOF_DETAILS] + [(f"the prop's block {k}", placed(b, D)) for k, b in enumerate(solids, 1)]
    for room_name, room in kept + rooms:
        for thing, box in things:
            if room_overlap(room, box):
                clashes.append(f"{thing} {fmt(box[0])} … {fmt(box[1])} in {room_name}")
        low = roof_low(shell, room)
        if low is not None and room_top(room) > low + EPS:
            clashes.append(f"the model's roof (its underside {low:.3f}) in {room_name} (up to {room_top(room):.3f})")
    for c in clashes:
        problems.add(where, c)
    hidden = sum(1 for p in parts.values() if p["visual"])
    return (f"level {n} {lay['def']['name']} ({len(pieces)} pieces, {W:g} × {H:g} × {D:g}, door {level['door'][0]:g} × {level['door'][1]:g}, "
            f"{lay['count']}/{lay['capacity']} stands): pieces at most {worst:.4f} off, {hidden} parts hidden, the roof "
            f"{under_worst:.3f} under the model's at the least, {len(glows)} lamps, clear of {len(kept)} kept parts and {len(rooms)} rooms")


def round_in(box, piece, eps=1e-3):
    """A round part (a Cylinder) in a round piece of the model (warehouse.py's cylinders have flats: 14 round a post):
    the same middle and length, the piece as wide as the part across one way and at least cos 15° of it the other."""
    size = [box[1][i] - box[0][i] for i in range(3)]
    other = [piece[1][i] - piece[0][i] for i in range(3)]
    if any(abs((box[0][i] + box[1][i]) / 2 - (piece[0][i] + piece[1][i]) / 2) > eps for i in range(3)):
        return False
    for axis in range(3):
        cross = [i for i in range(3) if i != axis]
        if abs(size[axis] - other[axis]) <= eps and abs(size[cross[0]] - size[cross[1]]) <= eps:
            wide = sorted(other[i] for i in cross)
            return wide[1] >= size[cross[0]] - eps and wide[0] >= size[cross[0]] * math.cos(math.radians(15)) - eps
    return False


def shell_in_wedge(wedge, q, eps=1e-3):
    """Is the point inside a WedgePart (its local frame: x across, the slope from (-Y, -Z) up to (+Y, +Z))?"""
    c, r, s = wedge["cf"][:3], wedge["cf"][3:], wedge["size"]
    d = [q[i] - c[i] for i in range(3)]
    l = [sum(r[i * 3 + j] * d[i] for i in range(3)) for j in range(3)]  # (the inverse of a turn: its transpose)
    if any(abs(l[j]) > s[j] / 2 + eps for j in range(3)):
        return False
    # under the slope: (y + sy/2) / sy <= (z + sz/2) / sz
    return (l[1] + s[1] / 2) * s[2] <= (l[2] + s[2] / 2) * s[1] + eps * max(s[1], s[2])


def rooms_of(lay, parts, meta0, back):
    """Where the game needs room, as ("box", lo, hi) or ("disc", (x, z), r, y0, y1) (a stand's tag turns to the camera:
    7 wide round its middle)."""
    floor_top = lay["floorTop"]
    hall, path, bay = lay["inside"], lay["doorPath"], lay["bay"]
    door_high = lay["door"][3]
    high = min(door_high, back - 1.0)
    way = min(door_high, WAY_HIGH)
    rooms = [
        (f"the open hall (1.5 in from the walls, up to {high:g}: as high as the door, a stud under the back wall's top at most)",
         ("box", [hall["x0"] + 1.5, floor_top, hall["z0"] + 1.5], [hall["x1"] - 1.5, high, hall["z1"] - 1.5])),
        (f"the doorway and the way in (up to {way:g})", ("box", [path["x0"], 0.1, path["z0"]], [path["x1"], way, path["z1"]])),
        ("the UNLOAD HERE bay", ("box", [bay["x0"], 0.1, bay["z0"]], [bay["x1"], BAY_HIGH, bay["z1"]])),
    ]
    tallest, fit = meta0["tallest"], meta0["fit"]
    width, high, over, under = TAG
    for k, (x, z, sx, sz, top, ceiling) in enumerate(lay["stands"], 1):
        piece = top + tallest
        rooms.append((f"stand {k}'s piece (the tallest, {tallest:g})", ("box", [x - sx / 2 + fit / 2, floor_top, z - sz / 2 + fit / 2], [x + sx / 2 - fit / 2, piece, z + sz / 2 - fit / 2])))
        middle = min(piece + over, ceiling - under)  # (server/Warehouse.luau's refresh: under the roof where it reaches back)
        rooms.append((f"stand {k}'s tag", ("disc", (x, z), width / 2, middle - high / 2, middle + high / 2)))
    tx, tz, tsx, tsz, ty, yaw = lay["terminal"]
    fx, fz = -math.sin(math.radians(yaw)), -math.cos(math.radians(yaw))  # (the way it faces)
    lo, hi = [tx - tsx / 2, floor_top, tz - tsz / 2], [tx + tsx / 2, ty + 4.0, tz + tsz / 2]
    reach = [lo[0] + min(0, 2 * fx), lo[1], lo[2] + min(0, 2 * fz)], [hi[0] + max(0, 2 * fx), hi[1], hi[2] + max(0, 2 * fz)]
    rooms.append(("the UPGRADES desk and 2 before it", ("box", *reach)))
    for name, front in (("OwnerSign", 3.0), ("StockBoard", 1.5), ("UpgradeSign", 1.5)):
        p = parts[name]
        r = p["cf"][3:]
        normal = [-r[2], -r[5], -r[8]]  # (its Front face: -Z)
        lo, hi = aabb(p)
        face = [hi[i] if normal[i] > 0.5 else lo[i] if normal[i] < -0.5 else None for i in range(3)]
        a = [lo[i] if face[i] is None else min(face[i], face[i] + front * normal[i]) for i in range(3)]
        b = [hi[i] if face[i] is None else max(face[i], face[i] + front * normal[i]) for i in range(3)]
        rooms.append((f"the front of {name} ({front:g})", ("box", a, b)))
    return rooms


def room_overlap(room, box, margin=EPS):
    if room[0] == "box":
        return overlap((room[1], room[2]), box, margin)
    _, (x, z), r, y0, y1 = room
    if not (box[0][1] < y1 - margin and y0 < box[1][1] - margin):
        return False
    dx = max(box[0][0] - x, 0, x - box[1][0])
    dz = max(box[0][2] - z, 0, z - box[1][2])
    return math.hypot(dx, dz) < r - margin


def room_top(room):
    return room[2][1] if room[0] == "box" else room[4]


def roof_low(shell, room):
    if room[0] == "box":
        return shell.roof_low(room[1], room[2])
    _, (x, z), r, y0, y1 = room
    # (the model's underside depends on x only, or on z only for a shed: the least over the disc is at its ends)
    c = shell.cover
    pts = [(min(max(x + dx, c[0]), c[1]), min(max(z + dz, c[2]), c[3])) for dx, dz in ((r, 0), (-r, 0), (0, r), (0, -r), (0, 0))]
    if not shell.covered(x, z, eps=r):
        return None
    return min(shell.under(px, pz) for px, pz in pts)


def main():
    luau = str(Path(sys.argv[1]).resolve())
    manifest = json.loads(MANIFEST.read_text())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        old = stage(tmp, manifest)
        plain = run(luau, tmp, "none")
        art = run(luau, tmp, "art")
    problems = Problems()
    looks = {l["finish"] for l in art["LOOK"]}
    check_import(manifest, looks, problems)
    real, rebuilt = check_real(manifest, plain, art, problems)
    lays, plot_ids = check_layouts(manifest, plain, problems)
    lines = [check_level(n, manifest, lays, plot_ids, plain, art, plain["META0"], problems) for n in range(1, 6)]
    tris = sum(p["triangles"] for p in manifest["pieces"].values())
    if problems.items:
        for text in problems.items:
            print("  " + text)
        tally = {}
        for text in problems.items:
            key = text.split(":")[0].split(",")[0]
            tally[key] = tally.get(key, 0) + 1
        print(f"Mesh warehouse FAIL: {len(problems.items)} problem(s) (listed above: " + ", ".join(f"{k} {v}" for k, v in tally.items()) + ")")
        sys.exit(1)
    for line in lines:
        print("  " + line)
    print(f"Mesh warehouse PASS: all 5 levels ({len(manifest['pieces'])} pieces, {tris} triangles) from a turned, scaled import on "
          f"their Sites on {len(plot_ids)} plots and on the {len(real)} warehouses Warehouse.luau builds (levels "
          f"{', '.join(str(n) for _, n in real)}{'; the owner rebuilt at ' + str(rebuilt[0]) if rebuilt else ''})"
          f"{' (8.2 WarehouseMesh)' if old else ''}: "
          f"in place, the visual parts hidden, the walls, gables and roof inside the model's, the lamps under its lamps, "
          f"its details clear of what the game keeps; again, another size, another door, no plot, no import: unchanged")


if __name__ == "__main__":
    main()
