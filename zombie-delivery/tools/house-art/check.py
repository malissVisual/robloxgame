#!/usr/bin/env python3
"""7.2: the house a move empties in the owner's Blender model (server/HouseMesh.luau), on the house as the game builds it.

8.0.5: house.py's TARGET says which house the export is for (the manifest's "target"): "sandbox", the sandbox's The Old
Chalet (built here as server/SandboxWorld.luau builds it from shared/ChaletLooks.luau, its garden and the greeter's
porch round it), or "city", Marge's 155 Willow Ln (World's buildHouse box house). For a sandbox export the checks are
the same as below with the chalet's pieces for the box house's, the garden's flower boxes, gate, mailbox and the
greeter (Config.MoveGreeters.Porch) for the moving-day dress, its roof under SandboxMap.House.house's height, and the
chalet's own roof (over its walls) not colliding any more.

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

    python3 zombie-delivery/tools/house-art/check.py <luau> [another export's ZDCHouseArt.json]
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
SANDBOX_LINES = (  # server/SandboxWorld.luau's house(), which the harness copies for a sandbox export
    'for _, piece in ChaletLooks.house(spec) do',
    'if piece.name == "Fence" then',
    'p.Name = "FrontDoor"',
    'p:SetAttribute("SandboxDoor", true)',
    '(require(mesh) :: any).dress(model, H.id)',
    'for n, spot in { { gx - 10.5, gz + 2.2 }, { gx + 10.5, gz + 2.2 }, { gx - 5.8, door.z - 2.4 }, { gx + 5.8, door.z - 2.4 } } do',
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
	if k == "LookVector" then local r = cf.R; return V3(-r[3], -r[6], -r[9]) end
	return rawget(F, k)
end
local O = getmetatable(M.Instance.new("Part"))
local isA = O.IsA
O.IsA = function(self, c) if c == "BasePart" and (self.ClassName == "MeshPart" or self.ClassName == "WedgePart") then return true end return isA(self, c) end
local storage = M.Instance.new("Folder")
local get = M.game.GetService
M.game.GetService = function(self, name) if name == "ServerStorage" then return storage end return get(self, name) end
local MODE, TARGET = ...
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
-- The sandbox's The Old Chalet as server/SandboxWorld.luau builds it (its pieces and its garden's things in a Folder).
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local ChaletLooks = require("./ChaletLooks")
local Config = require("./Config")
local function chalet()
	local H, S = SandboxMap.House, SandboxScenery
	local model = M.Instance.new("Model")
	model.Name = "TheOldChalet"
	model:SetAttribute("SandboxHouse", H.id)
	local door = H.door
	local frame = M.CFrame.new(door.x, door.y, door.z) * M.CFrame.Angles(0, math.rad(door.yaw), 0)
	local lot = H.lot
	local spec = { w = H.house.sx, d = H.house.sz, h = S.Chalet.Walls, lot = lot.x1 - lot.x0, front = (lot.x1 - lot.x0) / 2 - (door.z - lot.z0),
		seed = S.Chalet.Seed, render = S.Chalet.Render, shade = S.Chalet.Shade }
	for _, piece in ChaletLooks.house(spec) do
		if piece.name == "Fence" then
			continue
		end
		local turn = piece.turn or { 0, 0, 0 }
		local p = M.Instance.new(if piece.shape == "Wedge" then "WedgePart" else "Part")
		p.Name = piece.name
		p.Size = M.Vector3.new(piece.size[1], piece.size[2], piece.size[3])
		p.CFrame = frame * M.CFrame.new(piece.at[1], piece.at[2], piece.at[3]) * M.CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
		p.CanCollide, p.CanQuery = piece.solid == true, piece.solid == true
		if piece.name == "Door" then
			p.Name = "FrontDoor"
			p:SetAttribute("SandboxDoor", true)
			p.CanCollide = false
		end
		p.Parent = model
	end
	local garden = M.Instance.new("Folder")
	garden.Name = "Garden"
	garden.Parent = model
	local G = S.Garden
	local gx, gz = door.x, G.Front
	local things = {}
	local function thing(name, size, x, y, z)
		table.insert(things, { name = name, size = size, cf = M.CFrame.new(x - door.x, y - door.y, z - door.z) })
		local p = M.Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.CanCollide = name, size, M.CFrame.new(x, y, z), false
		p.Parent = garden
	end
	for n, spot in { { gx - 10.5, gz + 2.2 }, { gx + 10.5, gz + 2.2 }, { gx - 5.8, door.z - 2.4 }, { gx + 5.8, door.z - 2.4 } } do
		thing("FlowerBox" .. n, M.Vector3.new(2.8, 1.8, 1.2), spot[1], 0.9, spot[2])
	end
	for _, side in { -1, 1 } do
		thing("GatePost", M.Vector3.new(0.9, 11, 0.9), gx + side * G.Gate, 5.5, gz)
	end
	thing("GateBeam", M.Vector3.new(2 * G.Gate + 1.6, 2.4, 1), gx, 10.4, gz)
	thing("Mailbox", M.Vector3.new(1.9, 4.6, 1.9), gx - G.Gate - 3.5, 2.3, gz - 1.4)
	local porch = Config.MoveGreeters.Porch
	thing("Greeter", M.Vector3.new(2, 6, 2), door.x + porch[1], 3, door.z + porch[2]) -- (+X right, -Z out: the frame's)
	thing("EnterDoor", M.Vector3.new(4, 6, 1), door.x, 3.5, door.z - 0.9)
	return model, frame, frame * M.CFrame.new(0, 0, H.house.sz / 2), things, { w = H.house.sx, h = S.Chalet.Walls, d = H.house.sz }
end
local function report(tag, id)
	local model, frame, body, things, box
	if id == SandboxMap.House.id then
		model, frame, body, things, box = chalet()
	else
		local lot = lotOf(id)
		assert(lot, "no lot for " .. id)
		model, frame, body = build(lot)
		box = { w = lot.w, h = lot.h, d = lot.d }
	end
	local dressed = HouseMesh.dress(model, id)
	local base = body -- (the house's bottom middle)
	print(string.format('HOUSE {"tag":"%s","id":"%s","dressed":%s,"attr":%s,"box":[%g,%g,%g]}', tag, id, tostring(dressed),
		tostring(model:GetAttribute("MeshArt") == true), box.w, box.h, box.d))
	if things then
		local back = M.CFrame.new(0, 0, box.d / 2):Inverse()
		for _, t in things do
			print(string.format('DRESS {"name":"%s","cf":%s,"size":[%g,%g,%g]}', t.name, f(back * t.cf), t.size.X, t.size.Y, t.size.Z))
		end
		print(string.format('SANDBOX {"top":%g,"door":%s}', SandboxMap.House.house.y + SandboxMap.House.house.sy,
			tostring(model:FindFirstChild("FrontDoor") ~= nil and model:FindFirstChild("FrontDoor"):GetAttribute("SandboxDoor") == true)))
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Parent == model then
			print(string.format('PART {"tag":"%s","class":"%s","name":"%s","cf":%s,"size":[%g,%g,%g],"t":%g,"shadow":%s,"collide":%s,"query":%s,"touch":%s,"anchored":%s,"night":%s,"color":%s,"skin":%s}',
				tag, d.ClassName, d.Name, f(base:Inverse() * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, d.Transparency or 0, tostring(d.CastShadow),
				tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Anchored), tostring(d:GetAttribute("NightLight") == true),
				c(d.Color), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil)))
		end
	end
	if tag == "main" and not things then
		-- The moving day's things (server/MoveSites.luau: the door's frame) and the door's Enter house box (server/Moving.luau).
		local lot = lotOf(id)
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
if TARGET == "sandbox" then
	report("main", SandboxMap.House.id)
	report("size", "home_suburbs_2_0_00") -- (listed: Marge's, another size)
else
	report("main", "home_suburbs_2_0_00")
	HouseMesh.Homes.home_suburbs_2_0_01 = true -- (listed, another size)
	report("size", "home_suburbs_2_0_01")
end
report("other", "home_suburbs_2_0_10") -- (not listed)
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


def run(luau: str, tmp: Path, mode: str, target: str):
    r = subprocess.run([luau, "harness.luau", "-a", mode, target], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    out = {"HOUSE": [], "PART": [], "DRESS": [], "LOOK": []}
    for line in r.stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind in out:
            out[kind].append(json.loads(rest))
        elif kind in ("META", "SANDBOX"):
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
    sandbox_world = (ROOT / "src/server/SandboxWorld.luau").read_text()
    for line in SANDBOX_LINES:
        assert line in sandbox_world, f"server/SandboxWorld.luau's house changed ({line!r}): change this check's harness with it"
    manifest = json.loads((Path(sys.argv[2]) if len(sys.argv) > 2 else MANIFEST).read_text())  # (another export: its JSON)
    target = manifest.get("target", "city")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        plain = run(luau, tmp, "none", target)
        art = run(luau, tmp, "art", target)
        scattered = run(luau, tmp, "scattered", target)
    finishes = {name.rsplit("_", 1)[1] for name in manifest["pieces"]}
    looks = {l["finish"] for l in art["LOOK"]}
    assert finishes <= looks, f"finishes without a look in HouseMesh.LOOKS: {sorted(finishes - looks)}"
    for p in manifest["pieces"].values():
        assert p["triangles"] <= 10000, p
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
    top = main_house["box"][1]
    if target == "sandbox":
        assert "House" in [p["name"] for p in own] and "FrontDoor" in [p["name"] for p in own] and art["SANDBOX"]["door"], "the chalet's House box or its FrontDoor"
    else:
        assert sorted(p["name"] for p in own) == ["Door", "House", "Roof", "Roof", "Window", "Window"], [p["name"] for p in own]
    for p in own:
        assert p["t"] == 1 and p["shadow"] is False, (p["name"], "still seen")
        over = aabb(p)[0][1] >= top - 0.05
        if p["name"] == "House":
            assert p["collide"] and p["query"], "the House box stopped colliding"
        elif over:
            assert not p["collide"] and not p["query"], (p["name"], "over the walls and still colliding (it would poke through the roof)")
        elif target == "city":
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
    wedges = [aabb(p) for p in own if p["name"] == "Roof"]  # (the chalet's: its gable's two halves)
    w_lo = [min(b[0][i] for b in wedges) for i in range(3)]
    w_hi = [max(b[1][i] for b in wedges) for i in range(3)]
    assert roof_lo[0] <= w_lo[0] + 0.25 and roof_hi[0] >= w_hi[0] - 0.25 and roof_lo[2] <= w_lo[2] + 0.25 and roof_hi[2] >= w_hi[2] - 0.25, (roof_lo, roof_hi, w_lo, w_hi)
    if target == "city":
        assert roof_hi[1] >= w_hi[1], (roof_hi, w_hi, "the old roof pokes through")
    else:
        highest = max(box_of(d)[1][1] for d in details)
        assert highest <= art["SANDBOX"]["top"] + 0.05, (highest, art["SANDBOX"]["top"], "over SandboxMap.House.house's height")
    # Nothing where the move puts its things or in the door's Enter house box.
    clashes = []
    for thing in art["DRESS"]:
        a = aabb(thing)
        for d in details:
            if overlap(a, box_of(d)):
                clashes.append((thing["name"], d["name"]))
    assert not clashes, f"the model is where the move puts its things: {clashes[:8]}"
    tris = sum(p["triangles"] for p in manifest["pieces"].values())
    print(f"Mesh house PASS ({target}): {len(manifest['pieces'])} pieces ({tris} triangles, the largest "
          f"{max(p['triangles'] for p in manifest['pieces'].values())}) on {main_house['id']} ({W:.2f} × {H:.2f} × {D:.2f}, "
          f"the map's) from a turned, scaled import: every piece in place, anchored, not physical; the house's own parts "
          f"hidden, the box still colliding, nothing over the walls colliding; the walls on its box, "
          f"{'the roof under the house box' if target == 'sandbox' else 'the roof over its wedges'}; clear of the {len(art['DRESS'])} "
          f"{'garden things, the greeter and the door' if target == 'sandbox' else 'moving-day things and the door'}; other houses and no import: unchanged")


if __name__ == "__main__":
    main()
