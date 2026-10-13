#!/usr/bin/env python3
"""8.0 SANDBOX: the Sprinter in the owner's Blender model (server/SprinterMesh.luau) on a parts model, without Studio.

Simulates the Roblox import of design/blender-sprinter/roblox/ZDCSprinterArt.fbx from its manifest (ZDCSprinterArt.json:
every piece's box in the game's axes, written by sprinter.py): the importer turns the model a quarter round, makes it 3
times bigger, moves it and nests half of it in a sub-model. Then a sprinter car built by the contract the parts model
keeps (SprinterVisual looks, the door groups BackDoorL / BackDoorR / SideDoor / CabDoorL, a cab door found by its
DoorHinge, tyres on WheelMotors with a hub welded on, seats, prompts, colliders, a turned and moved car, one back door
open when it is dressed) is put into workspace.Cars and another straight into workspace. SprinterMesh.start() must take
the import out of the world, dress both through ChildAdded (and leave a ZDC Van alone): every piece once where the model
has it (the doors as if closed), welded to the BodyRoot, its door's moving part or each tyre (the wheel scaled to the
tyre, on the model's track), nothing physical, the lamps lit at night; hide exactly the looks (SprinterVisual, the tyres
and their hubs) and change nothing else. Dressing again adds nothing; without the import nothing changes at all.
Also: the model's measured sizes are the contract's (8.0 × 10.4 × 22.0, wheelbase 13.0, clearance 1.2, the bay 6.6 ×
7.6 × 14.0 on a floor at 2.4 starting 1.0 behind the 7-stud cab), the markers, the triangle budget, every finish a look.

    python3 zombie-delivery/tools/sprinter/mesh-check.py <luau>
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "design/blender-sprinter/roblox/ZDCSprinterArt.json"
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum\n'
          'local game, workspace, task = M.game, M.workspace, require("./Task")\nlocal warn = print\n')
# The contract (the owner's numbers; design/blender-sprinter/sprinter.py and the parts model use the same).
WANT = {"overall": [8.0, 10.4, 22.0], "wheelbase": 13.0, "clearance": 1.2, "floor": 2.4, "cab": 7.0,
        "bay": {"width": 6.6, "height": 7.6, "length": 14.0}}
GROUPS = ("Body", "CabDoorL", "CabDoorR", "SideDoor", "BackDoorL", "BackDoorR", "Wheel")
BUDGET = (15000, 30000)  # triangles of the model as the game shows it (the wheel four times)

TASK = r'''
local queue = {}
local Task = {}
function Task.defer(fn, ...) table.insert(queue, { fn, table.pack(...) }) end
function Task.flush()
	while #queue > 0 do
		local job = table.remove(queue, 1)
		job[1](table.unpack(job[2], 1, job[2].n))
	end
end
return Task
'''

HARNESS = r'''
local M = require("./ItemMock")
local Task = require("./Task")
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
-- ChildAdded: a signal per instance, fired when something is parented into it.
local signals = {}
local index, newindex = O.__index, O.__newindex
O.__index = function(self, k)
	if k == "ChildAdded" then
		local s = signals[self]
		if not s then
			s = { list = {} }
			s.Connect = function(sig, fn) table.insert(sig.list, fn); return { Disconnect = function() end } end
			signals[self] = s
		end
		return s
	end
	return index(self, k)
end
O.__newindex = function(self, k, v)
	newindex(self, k, v)
	if k == "Parent" and v and signals[v] then
		for _, fn in signals[v].list do fn(self) end
	end
end
-- GetAttributeChangedSignal: a signal per instance and attribute, fired by SetAttribute.
local attrSignals = {}
local setAttribute = O.SetAttribute
O.GetAttributeChangedSignal = function(self, name)
	attrSignals[self] = attrSignals[self] or {}
	local s = attrSignals[self][name]
	if not s then
		s = { list = {} }
		s.Connect = function(sig, fn)
			local entry = { fn = fn }
			table.insert(sig.list, entry)
			return { Disconnect = function() entry.fn = nil end }
		end
		attrSignals[self][name] = s
	end
	return s
end
O.SetAttribute = function(self, k, v)
	setAttribute(self, k, v)
	local s = attrSignals[self] and attrSignals[self][k]
	if s then
		for _, entry in table.clone(s.list) do if entry.fn then entry.fn() end end
	end
end
local storage = M.Instance.new("Folder")
storage.Name = "ServerStorage"
local get = M.game.GetService
M.game.GetService = function(self, name) if name == "ServerStorage" then return storage end return get(self, name) end
local MODE = (...)
local Config = require("./Config")
table.insert(Config.Cars, { id = "sprinter", style = "sprinter" }) -- (the parts model's Config.Cars entry, by the contract)

local art = M.Instance.new("Model")
if MODE == "art" then
	art.Name = "ZDCSprinterArt"
	art.Parent = M.workspace -- (as the importer leaves it: SprinterMesh moves it to ServerStorage)
	local nested = M.Instance.new("Model")
	nested.Name = "Group"
	nested.Parent = art
	-- The import: a quarter turn about up (x → -z, z → x), 3 times the size, moved.
	local K, MOVE = 3, M.Vector3.new(40, 3, -25)
	for n, row in require("./pieces") do
		local p = M.Instance.new("MeshPart")
		p.Name = row[1]
		p.CFrame = M.CFrame.new(row[4] * K + MOVE.X, row[3] * K + MOVE.Y, -row[2] * K + MOVE.Z)
		p.Size = M.Vector3.new(row[7] * K, row[6] * K, row[5] * K)
		p.Anchored = true
		local skin = M.Instance.new("SurfaceAppearance")
		skin.Parent = p
		p.Parent = if n % 2 == 0 then nested else art
	end
end

local V, C = M.Vector3.new, M.CFrame.new
local function part(name, size, cf, parent, props)
	local p = M.Instance.new(props and props.class or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	for k, v in props or {} do
		if k ~= "class" and k ~= "visual" then p[k] = v end
	end
	if props and props.visual then p:SetAttribute("SprinterVisual", true) end
	p.Parent = parent
	return p
end
local function weld(a, b)
	local w = M.Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
	return w
end
local function motor(name, p0, p1, c0, c1)
	local m = M.Instance.new("Motor6D")
	m.Name, m.Part0, m.Part1, m.C0, m.C1 = name, p0, p1, c0, c1
	m.Parent = p0
	return m
end
local closedOf = {} -- a door's moving part → where it is when closed

-- A sprinter by the contract: the ground under its middle at G.
local function buildCar(label, G, openBack)
	local at = function(x, y, z) return G * C(x, y, z) end
	local car = M.Instance.new("Model")
	car.Name = label
	local chassis = part("Chassis", V(7.6, 1.2, 22), at(0, 1.8, 0), car, { visual = true }) -- seen and colliding
	car.PrimaryPart = chassis
	local root = part("BodyRoot", V(0.4, 0.4, 0.4), chassis.CFrame, car, { Transparency = 1, CanCollide = false })
	motor("BodyRoll", chassis, root, C(0, -0.6, 0), C(0, -0.6, 0))
	weld(chassis, part("Hull", V(8, 0.3, 14), at(0, 2.25, 4), car, { Transparency = 1 }))
	local wall = part("BayWall", V(0.2, 7.6, 14), at(-3.4, 6.2, 4), car, { visual = true }) -- seen and colliding
	weld(chassis, wall)
	local shell = part("Shell", V(8, 8, 22), at(0, 6.4, 0), car, { visual = true, CanCollide = false })
	weld(root, shell)
	local decal = M.Instance.new("Decal")
	decal.Name = "Logo"
	decal.Parent = shell
	local gui = M.Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Enabled = true
	gui.Parent = shell
	local livery = M.Instance.new("Model")
	livery.Name = "Livery"
	livery:SetAttribute("SprinterVisual", true)
	livery.Parent = car
	weld(root, part("Stripe", V(0.05, 0.4, 20), at(-3.95, 4.5, 0), livery, { CanCollide = false }))
	weld(root, part("Badge", V(0.6, 0.6, 0.1), at(0, 3, -11), livery, { CanCollide = false }))
	local head = part("Headlight", V(1.2, 0.6, 0.2), at(-2.5, 3.1, -10.9), car, { visual = true, CanCollide = false })
	weld(root, head)
	local beam = M.Instance.new("SpotLight")
	beam.Name = "Beam"
	beam.Parent = head
	part("DriverSeat", V(2, 0.4, 2), at(-1.7, 3.7, -5.75), car, { class = "VehicleSeat", Transparency = 1, CanCollide = false })
	part("PassengerSeat", V(2, 0.4, 2), at(1.7, 3.7, -5.75), car, { class = "Seat", Transparency = 1, CanCollide = false })
	local spot = M.Instance.new("Attachment")
	spot.Name = "CargoDoor"
	spot.Parent = chassis
	local prompt = M.Instance.new("ProximityPrompt")
	prompt.Name = "BackPrompt"
	prompt.Parent = spot
	-- The doors (closed as built; the right back door is open when dressed if openBack).
	local function hinged(groupName, leafName, size, centre, hingeAt, joint, primary, open)
		local group = groupName and M.Instance.new("Model") or car
		if groupName then
			group.Name = groupName
			group.Parent = car
		end
		local leaf = part(leafName, size, at(centre.X, centre.Y, centre.Z), group, { visual = true, CanCollide = false })
		local c0 = C(hingeAt.X, hingeAt.Y - 1.8, hingeAt.Z)
		local c1 = C(hingeAt.X - centre.X, hingeAt.Y - centre.Y, hingeAt.Z - centre.Z)
		motor(joint, root, leaf, c0, c1)
		closedOf[leaf] = root.CFrame * c0 * c1:Inverse()
		if open then
			leaf.CFrame = root.CFrame * c0 * M.CFrame.Angles(0, math.rad(open), 0) * c1:Inverse()
		end
		if groupName then
			if primary then group.PrimaryPart = leaf end
			local panel = part("DoorCollider", V(size.X, size.Y, 0.1), leaf.CFrame, group, { Transparency = 1 }) -- (collides)
			weld(leaf, panel)
			local handle = part("Handle", V(0.5, 0.15, 0.1), leaf.CFrame * C(0, 0, 0.12), group, { visual = true, CanCollide = false })
			weld(leaf, handle)
			local a = M.Instance.new("Attachment")
			a.Name = "DoorPrompt"
			a.Parent = leaf
			local pr = M.Instance.new("ProximityPrompt")
			pr.Name = "Open"
			pr.Parent = a
		end
		return leaf
	end
	local doors = {
		BackDoorL = hinged("BackDoorL", "BackDoor", V(3.55, 7.6, 0.2), V(-1.8, 6.2, 10.9), V(-3.6, 6.2, 11.0), "BackHinge", true, nil),
		BackDoorR = hinged("BackDoorR", "BackDoor", V(3.55, 7.6, 0.2), V(1.8, 6.2, 10.9), V(3.6, 6.2, 11.0), "BackHinge", true, openBack and -100 or nil),
		SideDoor = hinged("SideDoor", "Panel", V(0.3, 7.5, 5.1), V(3.9, 5.76, -0.25), V(3.9, 5.76, -2.85), "SideSlide", false, nil),
		CabDoorL = hinged("CabDoorL", "CarDoor", V(0.2, 3.0, 3.6), V(-3.95, 4.5, -6.35), V(-3.95, 4.5, -8.55), "DoorHinge", false, nil),
		CabDoorR = hinged(nil, "CarDoor", V(0.2, 3.0, 3.6), V(3.95, 4.5, -6.35), V(3.95, 4.5, -8.55), "DoorHinge", false, nil),
	}
	-- A prompt that happens to share a door's name must not be taken for the door.
	local decoy = M.Instance.new("ProximityPrompt")
	decoy.Name = "SideDoor"
	decoy.Parent = spot
	-- The wheels: colliders, the tyres the clients spin (radius 1.3) and a hub welded to each.
	local tyres = {}
	for _, xz in { { -3.6, -6.5 }, { 3.6, -6.5 }, { -3.6, 6.5 }, { 3.6, 6.5 } } do
		local x, z = xz[1], xz[2]
		weld(chassis, part("WheelCollider", V(1, 2.6, 2.6), at(x, 1.3, z), car, { Transparency = 1 }))
		local tyre = part("Tyre", V(1.0, 2.6, 2.6), at(x, 1.3, z), car, { CanCollide = false, CanQuery = false, Massless = true })
		local m = motor("WheelMotor", chassis, tyre, C(x, -0.5, z), M.CFrame.identity)
		m:SetAttribute("Front", z < 0)
		weld(tyre, part("Hub", V(1.1, 1.3, 1.3), tyre.CFrame, car, { CanCollide = false }))
		table.insert(tyres, tyre)
	end
	return car, { doors = doors, root = root, tyres = tyres, G = G }
end

local function f(cf) local r = cf.R; return string.format("[%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f]", cf.Position.X, cf.Position.Y, cf.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]) end
local PROPS = { "Transparency", "CanCollide", "CanQuery", "CanTouch", "Massless", "Anchored", "CastShadow", "Enabled", "Name", "Size", "Color", "Material" }
local function snapshot(car)
	local snap = {}
	for _, d in car:GetDescendants() do
		local row = { parent = d.Parent, cf = d.CFrame, c0 = d.C0, c1 = d.C1, p0 = d.Part0, p1 = d.Part1 }
		for _, k in PROPS do row[k] = d[k] end
		snap[d] = row
	end
	return snap
end
local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or getmetatable(a) ~= getmetatable(b) then return a == b end
	if getmetatable(a) == F then return f(a) == f(b) end
	if rawget(a, "X") ~= nil then return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
	if rawget(a, "G") ~= nil then return a.R == b.R and a.G == b.G and a.B == b.B end
	return a == b
end
local function changes(label, car, snap)
	for d, row in snap do
		if d.Parent ~= row.parent then
			print(string.format('CHANGE {"car":"%s","name":"%s","class":"%s","prop":"Parent"}', label, d.Name, d.ClassName))
		end
		for _, k in { "cf", "c0", "c1", "p0", "p1" } do
			local now = ({ cf = d.CFrame, c0 = d.C0, c1 = d.C1, p0 = d.Part0, p1 = d.Part1 })[k]
			if not same(now, row[k]) then
				print(string.format('CHANGE {"car":"%s","name":"%s","class":"%s","prop":"%s"}', label, d.Name, d.ClassName, k))
			end
		end
		for _, k in PROPS do
			if not same(d[k], row[k]) then
				print(string.format('CHANGE {"car":"%s","name":"%s","class":"%s","prop":"%s","before":"%s","after":"%s","visual":%s,"parentName":"%s"}',
					label, d.Name, d.ClassName, k, tostring(row[k]), tostring(d[k]), tostring(d:GetAttribute("SprinterVisual") == true or (d.Parent and d.Parent:GetAttribute("SprinterVisual") == true) or false), d.Parent and d.Parent.Name or ""))
			end
		end
	end
end
local function report(label, car, info)
	local weldOf = {}
	for _, d in car:GetDescendants() do
		if d.ClassName == "WeldConstraint" then weldOf[d.Part1] = d.Part0 end
	end
	local names = {}
	for name, leaf in info.doors do names[leaf] = name end
	names[info.root] = "BodyRoot"
	for n, tyre in info.tyres do names[tyre] = "Tyre" .. n end
	for n, tyre in info.tyres do
		print(string.format('TYRE {"car":"%s","tyre":"Tyre%d","cf":%s,"size":[%g,%g,%g]}', label, n, f(info.G:Inverse() * tyre.CFrame), tyre.Size.X, tyre.Size.Y, tyre.Size.Z))
	end
	for _, d in car:GetDescendants() do
		if d.ClassName == "MeshPart" then
			local to = weldOf[d]
			local cf = d.CFrame
			if to and closedOf[to] then
				cf = closedOf[to] * to.CFrame:Inverse() * cf -- (as if its door were closed)
			end
			print(string.format('MESH {"car":"%s","name":"%s","to":"%s","cf":%s,"size":[%.6f,%.6f,%.6f],"collide":%s,"query":%s,"touch":%s,"massless":%s,"anchored":%s,"night":%s,"skin":%s,"parent":"%s"}',
				label, d.Name, to and (names[to] or to.Name) or "", f(info.G:Inverse() * cf), d.Size.X, d.Size.Y, d.Size.Z,
				tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Massless), tostring(d.Anchored),
				tostring(d:GetAttribute("NightLight") == true), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil), d.Parent.Name))
		end
	end
end
local function count(car)
	local n = 0
	for _, d in car:GetDescendants() do if d.ClassName == "MeshPart" then n += 1 end end
	return n
end

local SprinterMesh = require("./SprinterMesh")
for name, look in SprinterMesh.Looks do
	print(string.format('LOOK {"finish":"%s","lit":%s}', name, tostring(look.lit ~= nil)))
end
local cars = M.Instance.new("Folder")
cars.Name = "Cars"
cars.Parent = M.workspace
SprinterMesh.start()
local GA = C(40, 0.5, -12) * M.CFrame.Angles(0, math.rad(35), 0)
local GB = C(-70, 3, 25) * M.CFrame.Angles(0, math.rad(-120), 0)
local carA, infoA = buildCar("A", GA, false)
carA:SetAttribute("CarId", "sprinter")
local carB, infoB = buildCar("B", GB, true)
carB:SetAttribute("Sprinter", true)
local carC, infoC = buildCar("C", GA, false)
carC:SetAttribute("CarId", "zdcvan")
local GD = C(5, -2, 60) * M.CFrame.Angles(0, math.rad(200), 0)
local carD, infoD = buildCar("D", GD, false)
local snaps = { A = snapshot(carA), B = snapshot(carB), C = snapshot(carC), D = snapshot(carD) }
carA.Parent = cars -- (Vehicles.spawnAt: into workspace.Cars once built)
carB.Parent = M.workspace -- (no Cars folder: straight into workspace)
carC.Parent = cars
carD.Parent = cars -- (its CarId only after it is in the world)
Task.flush()
local dressedEarly = carD:GetAttribute("SprinterMesh") == true
carD:SetAttribute("CarId", "sprinter")
Task.flush()
local first = count(carA)
local again = SprinterMesh.dress(carA)
Task.flush()
print(string.format('META {"moved":%s,"ready":%s,"dressedA":%s,"dressedB":%s,"dressedC":%s,"dressedD":%s,"dressedEarly":%s,"again":%s,"countA":%d,"countA2":%d,"countB":%d,"countC":%d,"countD":%d}',
	tostring(art.Parent == storage and MODE == "art"), tostring(SprinterMesh.ready()), tostring(carA:GetAttribute("SprinterMesh") == true),
	tostring(carB:GetAttribute("SprinterMesh") == true), tostring(carC:GetAttribute("SprinterMesh") == true),
	tostring(carD:GetAttribute("SprinterMesh") == true), tostring(dressedEarly), tostring(again),
	first, count(carA), count(carB), count(carC), count(carD)))
report("A", carA, infoA)
report("B", carB, infoB)
report("D", carD, infoD)
changes("A", carA, snaps.A)
changes("B", carB, snaps.B)
changes("C", carC, snaps.C)
changes("D", carD, snaps.D)
print("ALL DONE")
'''


def stage(tmp: Path, manifest: dict):
    config = (ROOT / "src/shared/Config.luau").read_text()
    (tmp / "Config.luau").write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', config))
    text = (ROOT / "src/server/SprinterMesh.luau").read_text()
    text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', text)
    text = text.replace("require(script.Parent.DayNight)", "{ nightLight = M.nightLight }")
    assert "script.Parent" not in text, "SprinterMesh requires a module this check does not stage"
    (tmp / "SprinterMesh.luau").write_text(PREFIX + text)
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    (tmp / "Task.luau").write_text(TASK)
    rows = [[name, *p["center"], *p["size"]] for name, p in manifest["pieces"].items()]
    rows += [[name, *at, 0.3, 0.3, 0.3] for name, at in manifest["markers"].items()]
    body = ",\n".join("{%s}" % ",".join([json.dumps(r[0])] + [repr(float(x)) for x in r[1:]]) for r in rows)
    (tmp / "pieces.luau").write_text("return {\n" + body + "\n}\n")
    (tmp / "harness.luau").write_text(HARNESS)


def run(luau: str, tmp: Path, mode: str):
    r = subprocess.run([luau, "harness.luau", "-a", mode], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    out = {"MESH": [], "TYRE": [], "LOOK": [], "CHANGE": []}
    for line in r.stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind in out:
            out[kind].append(json.loads(rest))
        elif kind == "META":
            out[kind] = json.loads(rest)
    return out


def box(cf, size):
    """A part's box in its car's ground frame (cf already there): centre and axis-aligned size."""
    r = cf[3:]
    return cf[:3], [sum(abs(r[i * 3 + j]) * size[j] for j in range(3)) for i in range(3)]


def close(a, b, eps=2e-3):
    return all(abs(x - y) < eps for x, y in zip(a, b))


def check_manifest(manifest):
    d = manifest["dimensions"]
    for key in ("overall",):
        assert close(d[key], WANT[key], 1e-3), (key, d[key], WANT[key])
    for key in ("wheelbase", "clearance", "floor", "cab"):
        assert abs(d[key] - WANT[key]) < 1e-3, (key, d[key], WANT[key])
    for key, want in WANT["bay"].items():
        assert abs(d["bay"][key] - want) < 1e-3, ("bay", key, d["bay"][key], want)
    assert abs(d["bay"]["start"] - (d["cabWall"] + 1.0)) < 1e-3, ("the bay starts 1.0 behind the cab wall", d["bay"]["start"], d["cabWall"])
    assert abs(d["front"] + 11.0) < 1e-3 and abs(d["back"] - 11.0) < 1e-3 and abs(d["ground"]) < 1e-3, ("centred on the ground", d)
    assert abs(d["bay"]["end"] - d["back"]) < 1e-3, ("the bay runs to the back doors", d["bay"])
    pieces = manifest["pieces"]
    groups = {name.split("_")[0] for name in pieces}
    assert groups == set(GROUPS), ("groups", sorted(groups ^ set(GROUPS)))
    for name in pieces:
        assert re.fullmatch(r"[A-Za-z]+_[a-z]+", name), (name, "not <group>_<finish>")
    marks = manifest["markers"]
    assert close(marks["SprinterMark_o"], [0, 0, 0]) and close(marks["SprinterMark_x"], [10, 0, 0]) and close(marks["SprinterMark_y"], [0, 10, 0]) \
        and close(marks["SprinterMark_z"], [0, 0, 10]), marks
    rubber = pieces["Wheel_rubber"]
    assert close(marks["SprinterMark_w"], rubber["center"]), ("the wheel marker is the wheel's centre", marks["SprinterMark_w"], rubber["center"])
    assert abs(rubber["size"][1] / 2 - d["wheelRadius"]) < 1e-3 and abs(marks["SprinterMark_w"][1] - d["wheelRadius"]) < 1e-3, ("the wheel stands on the ground", rubber)
    assert abs(abs(marks["SprinterMark_w"][2]) - WANT["wheelbase"] / 2) < 1e-3, ("the axles at ±wheelbase / 2", marks["SprinterMark_w"])
    for name in ("BackDoorL", "BackDoorR", "SideDoor", "CabDoorL", "CabDoorR"):
        assert "pivot" in manifest["groups"][name], name
    seats = manifest["seats"]
    assert seats["driver"][0] < 0 < seats["passenger"][0], ("the driver sits on the left (-x)", seats)
    wheel = manifest["wheelTriangles"]
    shown = manifest["triangles"] + 3 * wheel
    assert BUDGET[0] <= shown <= BUDGET[1], (f"{shown} triangles as the game shows it (the wheel 4×), the budget is {BUDGET}")
    return shown


def check_config(luau: str):
    """Once the parts model's Config.Sprinter is merged: its numbers, where they name a size, are the contract's."""
    probe = 'local Config = require("./Config")\nlocal s = (Config :: any).Sprinter\nif type(s) ~= "table" then print("NONE") return end\n' \
            'for k, v in s do if type(v) == "number" then print(string.format("%s=%s", k, tostring(v))) end end\n'
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        config = (ROOT / "src/shared/Config.luau").read_text()
        (tmp / "Config.luau").write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', config))
        (tmp / "probe.luau").write_text(probe)
        r = subprocess.run([luau, "probe.luau"], cwd=tmp, capture_output=True, text=True)
    if r.returncode != 0 or r.stdout.strip() == "NONE":
        return "Config.Sprinter not there yet"
    numbers = dict(line.split("=", 1) for line in r.stdout.split() if "=" in line)
    known = {"width": 8.0, "height": 10.4, "length": 22.0, "wheelbase": 13.0, "clearance": 1.2, "floor": 2.4, "bayfloor": 2.4,
             "baywidth": 6.6, "bayheight": 7.6, "baylength": 14.0, "cab": 7.0, "cablength": 7.0}
    seen = []
    for key, value in numbers.items():
        want = known.get(key.lower().replace("_", ""))
        if want is not None:
            assert abs(float(value) - want) < 1e-6, (f"Config.Sprinter.{key} = {value}, the model has {want}")
            seen.append(key)
    return f"Config.Sprinter agrees ({', '.join(seen) or 'no size named'})"


def main():
    luau = str(Path(sys.argv[1]).resolve())
    manifest = json.loads(MANIFEST.read_text())
    shown = check_manifest(manifest)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        plain = run(luau, tmp, "none")
        art = run(luau, tmp, "art")
    pieces = manifest["pieces"]
    finishes = {name.split("_")[1] for name in pieces}
    looks = {l["finish"]: l["lit"] for l in art["LOOK"]}
    assert not finishes - set(looks), ("finishes without a look in SprinterMesh.Looks", sorted(finishes - set(looks)))
    # Without the import: nothing at all.
    meta = plain["META"]
    assert not meta["ready"] and not meta["moved"] and not (meta["dressedA"] or meta["dressedB"] or meta["dressedC"]), meta
    assert not meta["again"] and meta["countA"] == meta["countB"] == meta["countC"] == meta["countD"] == 0 and not meta["dressedD"], meta
    assert not plain["CHANGE"], ("changed without an import", plain["CHANGE"][:5])
    # With it: both sprinters dressed through ChildAdded, the van left alone, once.
    meta = art["META"]
    assert meta["ready"] and meta["moved"], ("the import was not taken out of the world", meta)
    assert meta["dressedA"] and meta["dressedB"] and not meta["dressedC"], meta
    assert meta["dressedD"] and not meta["dressedEarly"], ("a car named after it was parented", meta)
    assert meta["again"] and meta["countA"] == meta["countA2"], ("dressing again added pieces", meta)
    wheel_pieces = [n for n in pieces if n.startswith("Wheel_")]
    expected = len(pieces) - len(wheel_pieces) + 4 * len(wheel_pieces)
    assert meta["countA"] == meta["countB"] == meta["countD"] == expected and meta["countC"] == 0, (meta, expected)
    door_of = {"Body": "BodyRoot", "BackDoorL": "BackDoorL", "BackDoorR": "BackDoorR", "SideDoor": "SideDoor", "CabDoorL": "CabDoorL",
               "CabDoorR": "CabDoorR"}
    radius = manifest["dimensions"]["wheelRadius"]
    centre = manifest["markers"]["SprinterMark_w"]
    worst = 0.0
    for label in ("A", "B", "D"):
        meshes = [m for m in art["MESH"] if m["car"] == label]
        tyres = {t["tyre"]: t for t in art["TYRE"] if t["car"] == label}
        seen = {}
        for m in meshes:
            seen[m["name"]] = seen.get(m["name"], 0) + 1
            group = m["name"].split("_")[0]
            assert not (m["collide"] or m["query"] or m["touch"] or m["anchored"]) and m["massless"], (label, m["name"], "physical")
            assert not m["skin"], (label, m["name"], "the importer's SurfaceAppearance kept")
            assert m["parent"] == "SprinterMesh", (label, m["name"], m["parent"])
            finish = m["name"].split("_")[1]
            assert m["night"] == looks[finish], (label, m["name"], "lamp registration")
            at, size = box(m["cf"], m["size"])
            if group == "Wheel":
                tyre = tyres.get(m["to"])
                assert tyre, (label, m["name"], "not on a tyre", m["to"])
                k = tyre["size"][1] / (2 * radius)
                side = -1 if tyre["cf"][0] < 0 else 1
                want = pieces[m["name"]]
                off = [(want["center"][i] - centre[i]) * k for i in range(3)]
                if side > 0:
                    off = [-off[0], off[1], -off[2]]
                expect = [side * abs(centre[0]) + off[0], tyre["cf"][1] + off[1], tyre["cf"][2] + off[2]]
                worst = max(worst, max(abs(a - b) for a, b in zip(at, expect)))
                assert close(at, expect), (label, m["name"], m["to"], at, expect)
                assert close(size, [s * k for s in want["size"]]), (label, m["name"], size, want["size"], k)
            else:
                assert m["to"] == door_of[group], (label, m["name"], "welded to", m["to"], "not", door_of[group])
                want = pieces[m["name"]]
                worst = max(worst, max(abs(a - b) for a, b in zip(at, want["center"])))
                assert close(at, want["center"]), (label, m["name"], at, want["center"])
                assert close(size, want["size"]), (label, m["name"], size, want["size"])
        for name in pieces:
            assert seen.get(name, 0) == (4 if name.startswith("Wheel_") else 1), (label, name, seen.get(name, 0))
        # Hidden: exactly the looks (SprinterVisual parts and the Livery model's, the tyres, their hubs); nothing else changed.
        hidden = set()
        for c in (c for c in art["CHANGE"] if c["car"] == label):
            allowed = (c["prop"] == "Transparency" and c["after"] == "1") or (c["prop"] == "CastShadow" and c["after"] == "false") \
                or (c["prop"] == "Enabled" and c["class"] == "SurfaceGui" and c["after"] == "false")
            assert allowed, (label, "changed", c)
            if c["class"] in ("Decal", "SurfaceGui"):
                assert c.get("parentName") == "Shell", (label, "a decal or gui hidden on", c)
                continue
            looks_part = c.get("visual") or c["name"] in ("Tyre", "Hub")
            assert looks_part, (label, "hid a part that is not looks", c)
            hidden.add(c["name"])
        want_hidden = {"Chassis", "BayWall", "Shell", "Stripe", "Badge", "Headlight", "BackDoor", "Panel", "CarDoor", "Handle", "Tyre", "Hub"}
        assert hidden == want_hidden, (label, "hidden", sorted(hidden ^ want_hidden))
        props = {(c["name"], c["prop"]) for c in art["CHANGE"] if c["car"] == label}
        assert ("Logo", "Transparency") in props and ("Sign", "Enabled") in props, (label, "the hidden part's decal and gui still show")
    assert not [c for c in art["CHANGE"] if c["car"] == "C"], "the ZDC Van was changed"
    tris = manifest["triangles"]
    print(f"Mesh sprinter PASS: {len(pieces)} pieces in {len(GROUPS)} groups ({tris} triangles, {shown} as shown with 4 wheels; "
          f"8.0 × 10.4 × 22.0, wheelbase 13.0, clearance 1.2, bay 6.6 × 7.6 × 14.0 on 2.4) from a turned, scaled import on three "
          f"sprinters (in Cars, in workspace with a back door open, one named after it was parented): {expected} MeshParts each in place (at most {worst:.4f} off), "
          f"welded to the BodyRoot, the doors' moving parts and the tyres, nothing physical, the looks hidden and nothing else; "
          f"the van untouched; no import: unchanged. {check_config(luau)}")


if __name__ == "__main__":
    main()
