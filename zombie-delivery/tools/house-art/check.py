#!/usr/bin/env python3
"""7.2: Marge's house in the owner's Blender model (server/HouseMesh.luau) on a house built as World builds it, no Studio.

Simulates the Roblox import of design/blender-house/roblox/ZDCHouseArt.fbx from its manifest (ZDCHouseArt.json: every
piece's box and every detail's, in the house's space, written by house.py): the importer turns the model a quarter
round, makes it 3 times bigger and moves it; HouseMesh must find the markers, undo that and dress each house of
HouseMesh.Homes, built here with server/World.luau's buildHouse parts (the House box, the two Roof wedges, the Door,
two Windows; World's own lines are checked to be unchanged). Checks:
  - house.py's box is the house's on the map (shared/Map.luau's lot) and every finish has a look;
  - every piece once, where the model has it (the import's turn and scale undone), anchored and not physical;
  - the house's own parts invisible and shadowless, still colliding where they did; the lantern a night light;
  - the walls stand on the House box's faces (nothing to walk through, no invisible wall) and the roof covers the
    wedges;
  - nothing of the model where the move puts its things (shared/MoveSiteLooks.luau's moving-day dress: MOVING DAY over
    the door, the boxes and the rug by it, the signs) nor in the door's "Enter house" box (server/Moving.luau);
  - at most 10,000 triangles a piece; a house not listed, one of another size, no import, an import physics threw about
    (a piece turned): left as World builds it.
8.1 SANDBOX: the sandbox's one house too, built by the real server/SandboxWorld.luau (the whole test world, on
tools/perf/world-mock.luau) with the same import in the Workspace. Checks:
  - shared/SandboxMap.luau's House box is house.py's; without the import the chalet as it is (nothing hidden, no mesh);
  - dressed: every piece once, where the model has it on the House box (House_sandbox_house, attribute Home), anchored
    and not physical; the chalet's parts hidden and shadowless, the same ones solid (the House box, the gable), the
    FrontDoor (attribute SandboxDoor, the moves' door) not; the walls on the box's faces;
  - the gable, re-cut across the house (SandboxScenery.Chalet.Pitch), under the model's roof at every point;
  - the FrontDoor on the model's door (across it, as wide and tall, just in front of its leaves); nothing of the model
    in the door's "Enter house" box (server/Moving.luau SB.site), the doorway's way out or on the path but its step
    (the path runs under it); the garden (the fence, the gate, the mailbox, the flower boxes) clear of the model.

    python3 zombie-delivery/tools/house-art/check.py <luau>
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
MANIFEST = ROOT / "design/blender-house/roblox/ZDCHouseArt.json"
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')
# World's buildHouse lines the harness copies (if World changes them, change the harness with it).
WORLD_LINES = (
    # (7.x merge: since 7.1 a Suburbs house is a chalet, server/Chalets.luau on the same w × h × d "House" box; the
    # harness still builds the box house HouseMesh dresses: the box, the model, the dress call are what it relies on)
    'house.Name = "House_" .. home.id',
    'house:SetAttribute("Home", home.id)',
    'require(script.Parent.Chalets).house(house, frame, {',
    'HouseMesh.dress(house, home.id)',
)
ROOF_LINES = (
    'part(parent, "Roof", Vector3.new(w, h, half), frame * CFrame.new(0, h / 2, -half / 2), color, Enum.Material.Slate).Shape = Enum.PartType.Wedge',
    'part(parent, "Roof", Vector3.new(w, h, half), frame * CFrame.new(0, h / 2, half / 2) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Slate).Shape = Enum.PartType.Wedge',
)

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
O.IsA = function(self, c) if c == "BasePart" and (self.ClassName == "MeshPart" or self.ClassName == "WedgePart") then return true end return isA(self, c) end
local storage = M.Instance.new("Folder")
local get = M.game.GetService
M.game.GetService = function(self, name) if name == "ServerStorage" then return storage end return get(self, name) end
local MODE = (...)
local art = M.Instance.new("Model")
if MODE == "art" or MODE == "scattered" then
	art.Name = "ZDCHouseArt"
	art.Parent = M.workspace -- (as the importer leaves it: HouseMesh moves it to ServerStorage)
	-- The import: a quarter turn about up (Roblox's x → -z, z → x), 3 times the size, moved. The importer's own axes
	-- from Blender's: (x, z, -y).
	local K, MOVE = 3, M.Vector3.new(-30, 2, 55)
	for _, row in require("./pieces") do
		local x, y, z = row[2], row[4], -row[3]
		local sx, sy, sz = row[5], row[7], row[6]
		local p = M.Instance.new(if string.sub(row[1], 1, 5) == "mark_" then "Part" else "MeshPart")
		p.Name = row[1]
		p.CFrame = M.CFrame.new(z * K + MOVE.X, y * K + MOVE.Y, -x * K + MOVE.Z)
		p.Size = M.Vector3.new(sz * K, sy * K, sx * K)
		p.Anchored = false -- (as Studio's Import 3D leaves them)
		if MODE == "scattered" and row[1] == "house_door" then
			p.CFrame = p.CFrame * M.CFrame.Angles(0.5, 0.2, 0) -- (thrown about by physics before the game read it)
		end
		local skin = M.Instance.new("SurfaceAppearance")
		skin.Parent = p
		p.Parent = art
	end
end
local Map = require("./Map")
local Looks = require("./MoveSiteLooks")
local HouseMesh = require("./HouseMesh")
local function f(cf) local r = cf.R; return string.format("[%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g]", cf.Position.X, cf.Position.Y, cf.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]) end
local function c(col) return string.format("[%d,%d,%d]", math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5)) end
local function lotOf(id)
	for _, lots in Map.lots("suburbs") do
		for _, lot in lots do
			if lot.home and lot.home.id == id then
				return lot
			end
		end
	end
	return nil
end
-- One house as World's buildHouse makes its own parts (the box, gableRoof's two wedges, the door, two windows).
local function build(lot)
	local home = lot.home
	local facing = M.Vector3.new(lot.facing.x, 0, lot.facing.z)
	local door = M.Vector3.new(home.door.x, Map.WalkTop, home.door.z)
	local frame = M.CFrame.lookAt(door, door + facing)
	local w, d, h = lot.w, lot.d, lot.h
	local body = frame * M.CFrame.new(0, 0, d / 2)
	local model = M.Instance.new("Model")
	model.Name = "House_" .. home.id
	local function part(name, size, cf, class, collide)
		local p = M.Instance.new(class)
		p.Name, p.Size, p.CFrame, p.CanCollide, p.CanQuery = name, size, cf, collide, collide
		p.Parent = model
		return p
	end
	part("House", M.Vector3.new(w, h, d), body * M.CFrame.new(0, h / 2, 0), "Part", true)
	local roof = body * M.CFrame.new(0, h, 0)
	local half = (d + 2) / 2
	part("Roof", M.Vector3.new(w + 2, 6, half), roof * M.CFrame.new(0, 3, -half / 2), "WedgePart", true)
	part("Roof", M.Vector3.new(w + 2, 6, half), roof * M.CFrame.new(0, 3, half / 2) * M.CFrame.Angles(0, math.pi, 0), "WedgePart", true)
	part("Door", M.Vector3.new(4, 7, 0.4), frame * M.CFrame.new(0, 3.5, -0.2), "Part", true)
	for _, x in { -w / 3, w / 3 } do
		part("Window", M.Vector3.new(4, 3.5, 0.3), frame * M.CFrame.new(x, h * 0.55, -0.15), "Part", false)
	end
	return model, frame, body
end
local function report(tag, id)
	local lot = lotOf(id)
	assert(lot, "no lot for " .. id)
	local model, frame, body = build(lot)
	local dressed = HouseMesh.dress(model, id)
	local base = body -- (the house's bottom middle)
	print(string.format('HOUSE {"tag":"%s","id":"%s","dressed":%s,"attr":%s,"box":[%g,%g,%g]}', tag, id, tostring(dressed),
		tostring(model:GetAttribute("MeshArt") == true), lot.w, lot.h, lot.d))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			print(string.format('PART {"tag":"%s","class":"%s","name":"%s","cf":%s,"size":[%g,%g,%g],"t":%g,"shadow":%s,"collide":%s,"query":%s,"touch":%s,"anchored":%s,"night":%s,"color":%s,"skin":%s}',
				tag, d.ClassName, d.Name, f(base:Inverse() * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, d.Transparency or 0, tostring(d.CastShadow),
				tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Anchored), tostring(d:GetAttribute("NightLight") == true),
				c(d.Color), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil)))
		end
	end
	if tag == "main" then
		-- The moving day's things (server/MoveSites.luau: the door's frame) and the door's Enter house box (server/Moving.luau).
		local back = M.CFrame.new(0, 0, lot.d / 2):Inverse()
		for _, p in Looks.house("Marge's House", Looks.parkDepth(lot.home)) do
			local r = p.rotation or { 0, 0, 0 }
			local cf = M.CFrame.new(p.at[1], p.at[2], p.at[3]) * M.CFrame.Angles(0, math.rad(p.yaw or 0), 0) * M.CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
			print(string.format('DRESS {"name":"%s","cf":%s,"size":[%g,%g,%g]}', p.name, f(back * cf), p.size[1], p.size[2], p.size[3]))
		end
		print(string.format('DRESS {"name":"EnterDoor","cf":%s,"size":[4,6,1]}', f(back * M.CFrame.new(0, 3.5, -0.9))))
	end
end
for finish, look in HouseMesh.Looks do
	print(string.format('LOOK {"finish":"%s"}', finish))
end
for id in HouseMesh.Homes do
	print(string.format('HOME {"id":"%s"}', id))
end
report("main", "home_suburbs_2_0_00") -- (Marge's; the sandbox's house: sandbox.luau)
report("other", "home_suburbs_2_0_10") -- (not listed)
HouseMesh.Homes.home_suburbs_2_0_01 = true -- (listed, another size)
report("size", "home_suburbs_2_0_01")
print(string.format('META {"moved":%s}', tostring(art.Parent == storage and MODE == "art")))
print("ALL DONE")
'''

# 8.1 SANDBOX: the real server/SandboxWorld.luau builds the test world (on tools/perf/world-mock.luau, as
# tests/sandboxworld_test.luau runs it) with the real HouseMesh, the import (the same turned, scaled one) in its Workspace.
SANDBOX = r'''
local W = require("./WorldMock")
local G = W.globals
local MODE = (...)
local storage = W.game:GetService("ServerStorage")
local art = G.Instance.new("Model")
if MODE == "art" then
	art.Name = "ZDCHouseArt"
	art.Parent = W.workspace
	local K, MOVE = 3, G.Vector3.new(-30, 2, 55)
	for _, row in require("./pieces") do
		local x, y, z = row[2], row[4], -row[3]
		local sx, sy, sz = row[5], row[7], row[6]
		local p = G.Instance.new(if string.sub(row[1], 1, 5) == "mark_" then "Part" else "MeshPart")
		p.Name = row[1]
		p.CFrame = G.CFrame.new(z * K + MOVE.X, y * K + MOVE.Y, -x * K + MOVE.Z)
		p.Size = G.Vector3.new(sz * K, sy * K, sx * K)
		p.Anchored = true
		G.Instance.new("SurfaceAppearance").Parent = p
		p.Parent = art
	end
end
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local world = require("./SandboxWorldServer").build()
local H = SandboxMap.House
local h = H.house
local chalet = world:FindFirstChild("TheOldChalet")
local own = chalet and chalet:FindFirstChild("House_" .. H.id)
-- the house's frame: its box's bottom middle, -Z out of the front door
local base = G.CFrame.new(h.x, h.y, h.z) * G.CFrame.Angles(0, math.rad(H.door.yaw), 0)
local inverse = base:Inverse()
local function f(cf)
	local list = {}
	for _, v in { cf:GetComponents() } do
		table.insert(list, string.format("%.17g", v))
	end
	return "[" .. table.concat(list, ",") .. "]"
end
print(string.format('HOUSE {"dressed":%s,"model":%s,"box":[%.17g,%.17g,%.17g],"pitch":%.17g}', tostring(own ~= nil and own:GetAttribute("MeshArt") == true),
	tostring(own ~= nil and own:IsA("Model") and own:GetAttribute("Home") == H.id and own.Parent == chalet), h.sx, h.sy, h.sz, SandboxScenery.Chalet.Pitch))
for _, d in (if chalet then chalet:GetDescendants() else {}) do
	if d:IsA("BasePart") then
		local shape = d.Shape
		print(string.format('PART {"class":"%s","name":"%s","own":%s,"shape":"%s","cf":%s,"size":[%.17g,%.17g,%.17g],"t":%g,"shadow":%s,"collide":%s,"query":%s,"touch":%s,"anchored":%s,"night":%s,"door":%s,"skin":%s}',
			d.ClassName, d.Name, tostring(own ~= nil and d.Parent == own), if shape then shape.Name else "", f(inverse * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z,
			d.Transparency or 0, tostring(d.CastShadow), tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Anchored),
			tostring(d:GetAttribute("NightLight") == true), tostring(d:GetAttribute("SandboxDoor") == true), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil)))
	end
end
-- the door's "Enter house" box as server/Moving.luau SB.site makes it: 4 × 6 × 1, 0.9 out of House.door, 3.5 up
local out = G.CFrame.new(H.door.x, H.door.y, H.door.z) * G.CFrame.Angles(0, math.rad(H.door.yaw), 0)
print(string.format('ENTER {"cf":%s,"size":[4,6,1]}', f(inverse * out * G.CFrame.new(0, 3.5, -0.9))))
-- the path kept clear from the curb to the door (SandboxScenery.Path), in the house's frame (yaw 0: only moved)
local P = SandboxScenery.Path
print(string.format('PATH {"x0":%.17g,"x1":%.17g,"z0":%.17g,"z1":%.17g,"yaw":%g}', P.x0 - h.x, P.x1 - h.x, P.z0 - h.z, P.z1 - h.z, H.door.yaw))
print(string.format('META {"moved":%s}', tostring(art.Parent == storage and MODE == "art")))
print("ALL DONE")
'''


def stage(tmp: Path, manifest: dict):
    for source in SHARED.glob("*.luau"):
        (tmp / source.name).write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text()))
    text = (ROOT / "src/server/HouseMesh.luau").read_text()
    text = text.replace("require(script.Parent.DayNight)", '{ nightLight = function(p) p:SetAttribute("NightLight", true) end }')
    (tmp / "HouseMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\nlocal warn = print\n" + text)
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    # Blender's coordinates of each piece's box (house.py: the game's x = Blender's -x, y = z, z = y).
    rows = []
    for name, p in manifest["pieces"].items():
        gx, gy, gz = p["center"]
        sx, sy, sz = p["size"]
        rows.append([name, -gx, gz, gy, sx, sz, sy])
    w, h, d = manifest["box"]
    for name, at in (("mark_o", (0, 0, 0)), ("mark_x", (-10, 0, 0)), ("mark_y", (0, 0, 10)), ("mark_z", (0, 10, 0)), ("mark_box", (-w / 2, d / 2, h))):
        rows.append([name, *at, 0.3, 0.3, 0.3])
    body = ",\n".join("{%s}" % ",".join([json.dumps(r[0])] + [repr(float(x)) for x in r[1:]]) for r in rows)
    (tmp / "pieces.luau").write_text("return {\n" + body + "\n}\n")
    (tmp / "harness.luau").write_text(HARNESS)
    # 8.1 SANDBOX: SandboxWorld and HouseMesh on the world mock (tests/run_tests.py's way), DayNight marking the lights
    shutil.copy(ROOT / "tools/perf/world-mock.luau", tmp / "WorldMock.luau")
    env = 'setfenv(1, require("./WorldMock").env)\n'
    text = (ROOT / "src/server/SandboxWorld.luau").read_text()
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', text).replace("require(script.Parent.HouseMesh)", 'require("./HouseMeshWorld")')
    (tmp / "SandboxWorldServer.luau").write_text(env + text)
    text = (ROOT / "src/server/HouseMesh.luau").read_text()
    text = text.replace("require(script.Parent.DayNight)", '{ nightLight = function(p) p:SetAttribute("NightLight", true) end }')
    (tmp / "HouseMeshWorld.luau").write_text(env + text)
    (tmp / "sandbox.luau").write_text(SANDBOX)


def run(luau: str, tmp: Path, mode: str, harness: str = "harness.luau"):
    r = subprocess.run([luau, harness, "-a", mode], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    out = {"HOUSE": [], "PART": [], "DRESS": [], "LOOK": [], "HOME": [], "ENTER": [], "PATH": []}
    for line in r.stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind in out:
            out[kind].append(json.loads(rest))
        elif kind == "META":
            out[kind] = json.loads(rest)
    return out


def aabb(part):
    r = part["cf"][3:]
    size = [sum(abs(r[i * 3 + j]) * part["size"][j] for j in range(3)) for i in range(3)]
    at = part["cf"][:3]
    return [at[i] - size[i] / 2 for i in range(3)], [at[i] + size[i] / 2 for i in range(3)]


def box_of(detail):
    c, s = detail["center"], detail["size"]
    return [c[i] - s[i] / 2 for i in range(3)], [c[i] + s[i] / 2 for i in range(3)]


def overlap(a, b, margin=0.005):
    return all(a[0][i] < b[1][i] - margin and b[0][i] < a[1][i] - margin for i in range(3))


def main():
    luau = str(Path(sys.argv[1]).resolve())
    world = (ROOT / "src/server/World.luau").read_text()
    for line in WORLD_LINES + ROOF_LINES:
        assert line in world, f"server/World.luau's buildHouse changed ({line!r}): change this check's harness with it"
    manifest = json.loads(MANIFEST.read_text())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        plain = run(luau, tmp, "none")
        art = run(luau, tmp, "art")
        sandbox_plain = run(luau, tmp, "none", "sandbox.luau")
        sandbox_art = run(luau, tmp, "art", "sandbox.luau")
        scattered = run(luau, tmp, "scattered")
    finishes = {name.rsplit("_", 1)[1] for name in manifest["pieces"]}
    looks = {l["finish"] for l in art["LOOK"]}
    assert finishes <= looks, f"finishes without a look in HouseMesh.LOOKS: {sorted(finishes - looks)}"
    for p in manifest["pieces"].values():
        assert p["triangles"] <= 10000, p
    assert sorted(h["id"] for h in art["HOME"]) == ["home_suburbs_2_0_00", "sandbox_house"], (art["HOME"], "HouseMesh.Homes: Marge's and the sandbox's")
    houses = {h["tag"]: h for h in art["HOUSE"]}
    main_house = houses["main"]
    W, H, D = manifest["box"]
    assert all(abs(a - b) < 1e-3 for a, b in zip(main_house["box"], (W, H, D))), \
        (main_house["box"], manifest["box"], "house.py's W, H, D are not the house's on the map: change them in house.py and export again")
    # Without the import, a house not listed, a house of another size: World's look.
    for h in plain["HOUSE"] + [houses["other"], houses["size"]]:
        assert not h["dressed"] and not h["attr"], (h, "dressed")
    for p in plain["PART"] + [p for p in art["PART"] if p["tag"] in ("other", "size")]:
        assert p["class"] != "MeshPart" and p["t"] == 0, (p["tag"], p["name"], "changed")
    for h in scattered["HOUSE"]:
        assert not h["dressed"], (h, "dressed from an import physics had thrown about")
    assert art["META"]["moved"], "the imported model was not moved to ServerStorage"
    assert main_house["dressed"] and main_house["attr"], main_house
    parts = [p for p in art["PART"] if p["tag"] == "main"]
    own = [p for p in parts if p["class"] != "MeshPart"]
    meshes = [p for p in parts if p["class"] == "MeshPart"]
    assert sorted(p["name"] for p in own) == ["Door", "House", "Roof", "Roof", "Window", "Window"], [p["name"] for p in own]
    for p in own:
        assert p["t"] == 1 and p["shadow"] is False, (p["name"], "still seen")
        assert p["collide"] == (p["name"] != "Window"), (p["name"], "its collision changed")
    assert sorted(p["name"] for p in meshes) == sorted(manifest["pieces"]), sorted(set(p["name"] for p in meshes) ^ set(manifest["pieces"]))
    for p in meshes:
        assert p["anchored"] and not (p["collide"] or p["query"] or p["touch"]), (p["name"], "physical")
        assert not p["skin"], (p["name"], "the importer's SurfaceAppearance kept")
        assert p["night"] == p["name"].endswith("_glow"), (p["name"], "night light")
        lo, hi = aabb(p)
        want = manifest["pieces"][p["name"]]
        at = [(a + b) / 2 for a, b in zip(lo, hi)]
        size = [b - a for a, b in zip(lo, hi)]
        assert all(abs(a - b) < 2e-3 for a, b in zip(at, want["center"])), (p["name"], at, want["center"])
        assert all(abs(a - b) < 2e-3 for a, b in zip(size, want["size"])), (p["name"], size, want["size"])
    # The walls on the box's faces, the roof over the wedges.
    details = manifest["details"]
    walls = next(d for d in details if d["name"] == "Zdi")
    lo, hi = box_of(walls)
    assert all(abs(a - b) < 1e-3 for a, b in zip((lo[0], hi[0], lo[2], hi[2], lo[1]), (-W / 2, W / 2, -D / 2, D / 2, 0))) and hi[1] >= H, (lo, hi)
    tiles = [box_of(d) for d in details if d["finish"] in ("tile", "tile2")]
    roof_lo = [min(b[0][i] for b in tiles) for i in range(3)]
    roof_hi = [max(b[1][i] for b in tiles) for i in range(3)]
    wedges = [aabb(p) for p in own if p["name"] == "Roof"]
    w_lo = [min(b[0][i] for b in wedges) for i in range(3)]
    w_hi = [max(b[1][i] for b in wedges) for i in range(3)]
    assert roof_lo[0] <= w_lo[0] + 0.25 and roof_hi[0] >= w_hi[0] - 0.25 and roof_lo[2] <= w_lo[2] + 0.25 and roof_hi[2] >= w_hi[2] - 0.25, (roof_lo, roof_hi, w_lo, w_hi)
    assert roof_hi[1] >= w_hi[1], (roof_hi, w_hi, "the old roof pokes through")
    # Nothing where the move puts its things or in the door's Enter house box.
    clashes = []
    for thing in art["DRESS"]:
        a = aabb(thing)
        for d in details:
            if overlap(a, box_of(d)):
                clashes.append((thing["name"], d["name"]))
    assert not clashes, f"the model is where the move puts its things: {clashes[:8]}"
    tris = sum(p["triangles"] for p in manifest["pieces"].values())
    print(f"Mesh house PASS: {len(manifest['pieces'])} pieces ({tris} triangles, the largest "
          f"{max(p['triangles'] for p in manifest['pieces'].values())}) on {main_house['id']} ({W:.2f} × {H:.2f} × {D:.2f}, "
          f"the map's) from a turned, scaled import: every piece in place, anchored, not physical; the house's own parts "
          f"hidden and still colliding; the walls on its box, the roof over its wedges; clear of the {len(art['DRESS'])} moving-day "
          f"things and the door; other houses and no import: unchanged")
    print(sandbox_check(manifest, sandbox_plain, sandbox_art))


def corners(part):
    """A part's eight corners (its cf: the position, then the rotation's rows)."""
    c, r, s = part["cf"][:3], part["cf"][3:], part["size"]
    out = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                local = (dx * s[0], dy * s[1], dz * s[2])
                out.append([c[i] + sum(r[i * 3 + j] * local[j] for j in range(3)) for i in range(3)])
    return out


def wedge_top(part, steps=24):
    """Points on a wedge's slope (a WedgePart's: from its bottom front edge, its -Z, up to its top back edge, its +Z)."""
    c, r, s = part["cf"][:3], part["cf"][3:], part["size"]
    out = []
    for a in range(steps + 1):
        for b in range(steps + 1):
            u, t = a / steps - 0.5, b / steps
            local = (u * s[0], -s[1] / 2 + t * s[1], -s[2] / 2 + t * s[2])
            out.append([c[i] + sum(r[i * 3 + j] * local[j] for j in range(3)) for i in range(3)])
    return out


def sandbox_check(manifest, plain, art):
    """8.1 SANDBOX: The Old Chalet (server/SandboxWorld.luau) on house.py's box, dressed by HouseMesh once imported."""
    W, H, D = manifest["box"]
    details = manifest["details"]
    for result in (plain, art):
        house = result["HOUSE"][0]
        assert house["model"], "the sandbox house's parts are not in a Model House_sandbox_house (attribute Home)"
        assert all(abs(a - b) < 1e-4 for a, b in zip(house["box"], (W, H, D))), \
            (house["box"], "shared/SandboxMap.luau's House box is not house.py's: HouseMesh would not dress it")
    # No import: the chalet as it is.
    assert not plain["HOUSE"][0]["dressed"], "dressed without an import"
    for p in plain["PART"]:
        assert p["class"] != "MeshPart" and p["t"] == 0, (p["name"], "changed without an import")
    # Dressed.
    house = art["HOUSE"][0]
    assert house["dressed"] and art["META"]["moved"], (house, art["META"], "not dressed, or the import left in the world")
    own = [p for p in art["PART"] if p["own"] and p["class"] != "MeshPart"]
    meshes = [p for p in art["PART"] if p["class"] == "MeshPart"]
    garden = [p for p in art["PART"] if not p["own"]]
    assert all(p["own"] for p in meshes), "a piece of the model outside House_sandbox_house"
    assert sorted(p["name"] for p in meshes) == sorted(manifest["pieces"]), sorted(set(p["name"] for p in meshes) ^ set(manifest["pieces"]))
    for p in meshes:
        assert p["anchored"] and not (p["collide"] or p["query"] or p["touch"]), (p["name"], "physical")
        assert not p["skin"], (p["name"], "the importer's SurfaceAppearance kept")
        assert p["night"] == p["name"].endswith("_glow"), (p["name"], "night light")
        lo, hi = aabb(p)
        want = manifest["pieces"][p["name"]]
        assert all(abs((a + b) / 2 - w) < 2e-3 for a, b, w in zip(lo, hi, want["center"])), (p["name"], lo, hi, want["center"])
        assert all(abs((b - a) - w) < 2e-3 for a, b, w in zip(lo, hi, want["size"])), (p["name"], lo, hi, want["size"])
    plain_own = sorted((p["name"], p["collide"]) for p in plain["PART"] if p["own"])
    assert sorted((p["name"], p["collide"]) for p in own) == plain_own, "the chalet's parts or their collision changed when dressed"
    for p in own:
        assert p["t"] == 1 and p["shadow"] is False, (p["name"], "still seen")
    solid = sorted(p["name"] for p in own if p["collide"])
    assert solid == ["House", "Roof", "Roof"], (solid, "the solid parts: the House box and the gable only")
    # The walls on the House box's faces.
    body = next(p for p in own if p["name"] == "House")
    lo, hi = aabb(body)
    walls_lo, walls_hi = box_of(next(d for d in details if d["name"] == "Zdi"))
    assert all(abs(a - b) < 1e-3 for a, b in zip((lo[0], hi[0], lo[2], hi[2], lo[1]), (walls_lo[0], walls_hi[0], walls_lo[2], walls_hi[2], walls_lo[1]))) \
        and walls_hi[1] >= hi[1], (lo, hi, walls_lo, walls_hi)
    # The gable across the house, over the walls' top and under the roof's tiles and ridge at every point of its slopes.
    roof = [box_of(d) for d in details if d["finish"] in ("tile", "tile2", "tile3") and not d["name"].startswith(("Vikýř", "Komín"))]
    wedges = [p for p in own if p["name"] == "Roof"]
    assert all(p["shape"] == "Wedge" for p in wedges), [p["shape"] for p in wedges]
    worst = None
    for wedge in wedges:
        assert all(c[1] >= H - 1e-3 for c in corners(wedge)), ("a gable wedge under the walls' top", corners(wedge))
        for x, y, z in wedge_top(wedge):
            over = [b for b in roof if b[0][0] - 1e-3 <= x <= b[1][0] + 1e-3 and b[0][2] - 1e-3 <= z <= b[1][2] + 1e-3]
            assert over, ("a point of the gable not under the roof", (x, y, z))
            margin = min(b[0][1] for b in over) - y
            worst = margin if worst is None else min(worst, margin)
    assert worst is not None and worst >= 0, (worst, "the re-cut gable pokes through the roof: is SandboxScenery.Chalet.Pitch house.py's PITCH?")
    # The FrontDoor on the model's door.
    doors = [p for p in art["PART"] if p["door"]]
    assert len(doors) == 1 and doors[0]["name"] == "FrontDoor" and doors[0]["own"] and not doors[0]["collide"], doors
    lo, hi = aabb(doors[0])
    leaves = [box_of(d) for d in details if d["name"].startswith("Křídlo dveří") and d["center"][2] < 0]
    l_lo = [min(b[0][i] for b in leaves) for i in range(3)]
    l_hi = [max(b[1][i] for b in leaves) for i in range(3)]
    assert abs((lo[0] + hi[0]) / 2 - (l_lo[0] + l_hi[0]) / 2) < 0.1 and abs((hi[0] - lo[0]) - (l_hi[0] - l_lo[0])) < 0.25 \
        and abs(lo[1] - l_lo[1]) < 0.25 and abs(hi[1] - l_hi[1]) < 0.25 and hi[2] <= l_lo[2] + 1e-3 and l_lo[2] - hi[2] < 0.5, \
        ("the FrontDoor is not on the model's door", lo, hi, l_lo, l_hi)
    # Nothing of the model in the door's Enter house box, the doorway's way out (6 studs, over the step) or on the path
    # (the path runs under the step); the garden clear of the model.
    path = art["PATH"][0]
    assert path["yaw"] == 0, path
    # (from the front wall's skin out, 0.25: its bands, plinth and portal stand on it, the plinth's box across the
    # doorway, its opening cut out; the path 6 wide a body high, 5: by the door the lantern hangs over its edge from
    # 5.1 up, outside the doorway, what is carried in or out passes through the doorway's way out)
    skin = -D / 2 - 0.25
    keep = [
        ("the Enter house box", aabb(art["ENTER"][0])),
        ("the doorway's way out", ([l_lo[0], 0.3, skin - 6], [l_hi[0], l_hi[1], skin])),
        ("the path", ([path["x0"], 0.3, path["z0"]], [path["x1"], 5, min(path["z1"], skin)])),
    ]
    for name, area in keep:
        clash = [d["name"] for d in details if overlap(area, box_of(d))]
        assert not clash, f"the model in {name}: {clash[:8]}"
    clashes = []
    for p in garden:
        a = aabb(p)
        for d in details:
            if overlap(a, box_of(d)) and not (p["name"] == "Path" and d["name"].startswith("Schod")):
                clashes.append((p["name"], d["name"]))
    assert not clashes, f"the garden in the model: {clashes[:8]}"
    return (f"Sandbox house PASS: The Old Chalet on house.py's box ({W:.2f} × {H:.2f} × {D:.2f}) as SandboxWorld builds it: "
            f"without the import the chalet; dressed, all {len(meshes)} pieces in place on House_sandbox_house, anchored, not "
            f"physical; the chalet's {len(own)} parts hidden, the House box and the gable still solid, the gable "
            f"({house['pitch']:g}°) under the roof ({worst:.2f} studs at the least); the FrontDoor on the model's door; the Enter "
            f"house box, the way out and the path clear (the path under the step); the garden's {len(garden)} parts clear of the model")


if __name__ == "__main__":
    main()
