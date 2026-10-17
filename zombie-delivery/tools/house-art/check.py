#!/usr/bin/env python3
"""7.2: the owner's Blender house (server/HouseMesh.luau) on the sandbox's house, no Studio.

Simulates the Roblox import of design/blender-house/roblox/ZDCHouseArt.fbx from its manifest (ZDCHouseArt.json: every
piece's box and every detail's, in the house's space, written by house.py): the importer turns the model a quarter
round, makes it 3 times bigger and moves it; HouseMesh must find the markers, undo that and dress the house.
(10.5: Marge's city house, built as World's buildHouse built it, went with the city; house.py TARGET "sandbox" only.)
8.1 SANDBOX: the sandbox's one house too, built by the real server/SandboxWorld.luau (the whole test world, on
tools/perf/world-mock.luau) with the same import in the Workspace. Checks:
  - shared/SandboxMap.luau's House box is house.py's; without the import the chalet as it is (nothing hidden, no mesh);
  - dressed: every piece once, where the model has it on the House box (House_sandbox_house, attribute Home), anchored
    and not physical; the chalet's parts hidden and shadowless, the same ones solid (the House box, the gable), the
    FrontDoor (attribute SandboxDoor, the moves' door) not; the walls on the box's faces;
  - the gable, re-cut across the house (SandboxScenery.Chalet.Pitch), under the model's roof at every point;
  - the FrontDoor on the model's door (across it, as wide and tall, just in front of its leaves); nothing of the model
    in the door's "Enter house" box (server/Moving.luau SB.site), the doorway's way out or on the path but its step
    (the path runs under it); the garden (the fence, the gate, the mailbox, the flower boxes) and the greeter's spot
    (server/MoveGreeters.luau, Config.MoveGreeters.Porch) clear of the model.
8.2.1: house.py's TARGET says which house the export is for (the manifest's "target"): "sandbox", the owner's big
house on The Old Farmstead (the sandbox checks above; Marge's then another size: left as World builds it), or "city",
Marge's (the checks above it; the sandbox's then another size: the chalet as it is).
8.3 the big move: the chalet's doors' leaves and its back door (server/SandboxWorld.luau): without the import the
doorways (FrontDoor, BackDoor) unseen behind their leaves and nothing else changed; the FrontDoor's two leaves
(FrontLeafWest, FrontLeafEast) and the BackLeaf in their doorways, door leaves that swing (shared/DoorSwing.luau:
DoorLeaf -1 / 1 / -1, each hinged at a jamb; DoorSwing 1, DoorDark), not solid; the BackDoor (attribute
SandboxBackDoor, the moves' second way in at SandboxMap's House.back) on the model's back door (across it, as wide and
tall, just outside its leaf), nothing of the model in its way out. 8.3 walk-in doors, dressed: the chalet's leaves
hidden with it, no door leaves; the model's doors copied as the leaves that swing (SandboxWorld.doorLeaves: the models
FrontDoorLeaf ×2, BackDoorLeaf) just in front of its doors' leaves, covering them, their backs on the wall's face,
hinged at the opening's sides (the back door's away from its handle), within its doorways (nothing of the model in
their way but the step under their foot and what runs across the doorway, its opening cut out).
8.5 walking through (Config.Moving.Doors Hall): the leaves (the chalet's and the copies) swing out of the house
(DoorSwing -1, seen against the dark doorway), and the doorways are walkable, with or without the import: the House box
collides with nothing and stops no ray, the house's "HouseSolid" pieces (unseen) are the box less a hall behind each
doorway (Hall Depth deep, the opening's width, the door's height), nothing of the house that collides in either hall
or its way out (the step, the model's door and the copies included), the walls either side of it, over it and past its
end solid; each hall lined dark ("DoorHall" parts in "DoorHalls", decoration) inside the house's box, in the hall.
8.5.1 (the owner: "the doors just disappear"): every leaf opens Config.Moving.Doors.Wide degrees (DoorAngle: past square,
never edge-on to a player walking up), swung open out of the house still clear of the model; the model's own doors
(house_door) stay drawn in their pockets and, open, the copies' dark doorway covers them from in front.

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
local Config = require("./Config")
local world = require("./SandboxWorldServer").build()
local H = SandboxMap.House
local h = H.house
local chalet = world:FindFirstChild("TheOldFarmstead")
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
-- 8.3 walk-in doors: a part's door leaf (its own attributes, or its model's: a copy of the model's door)
local function leafOf(d)
	local holder = d
	local parent = d.Parent
	if d:GetAttribute("DoorLeaf") == nil and parent and parent.ClassName == "Model" and parent:GetAttribute("DoorLeaf") ~= nil then
		holder = parent
	end
	local hinge = holder:GetAttribute("DoorLeaf")
	return if hinge == nil then "null" else string.format("%g", hinge), string.format("%g", holder:GetAttribute("DoorSwing") or 0),
		tostring(holder:GetAttribute("DoorDark") == true), if holder ~= d then holder.Name else "", string.format("%g", holder:GetAttribute("DoorAngle") or 0)
end
for _, d in (if chalet then chalet:GetDescendants() else {}) do
	if d:IsA("BasePart") then
		local shape = d.Shape
		local hinge, swing, dark, copy, angle = leafOf(d)
		print(string.format('PART {"class":"%s","name":"%s","own":%s,"shape":"%s","cf":%s,"size":[%.17g,%.17g,%.17g],"t":%g,"shadow":%s,"collide":%s,"query":%s,"touch":%s,"anchored":%s,"night":%s,"door":%s,"skin":%s,"back":%s,"leaf":%s,"swing":%s,"dark":%s,"copy":"%s","angle":%s}',
			d.ClassName, d.Name, tostring(own ~= nil and d.Parent == own), if shape then shape.Name else "", f(inverse * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z,
			d.Transparency or 0, tostring(d.CastShadow), tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Anchored),
			tostring(d:GetAttribute("NightLight") == true), tostring(d:GetAttribute("SandboxDoor") == true), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil),
			tostring(d:GetAttribute("SandboxBackDoor") == true), hinge, swing, dark, copy, angle))
	end
end
-- the door's "Enter house" box as server/Moving.luau SB.site makes it: 4 × 6 × 1, 0.9 out of House.door, 3.5 up
local out = G.CFrame.new(H.door.x, H.door.y, H.door.z) * G.CFrame.Angles(0, math.rad(H.door.yaw), 0)
print(string.format('ENTER {"cf":%s,"size":[4,6,1]}', f(inverse * out * G.CFrame.new(0, 3.5, -0.9))))
-- where the move's greeter stands (server/MoveGreeters.luau: Porch in the door's frame, +X right, -Z out), a body
local porch = Config.MoveGreeters.Porch
print(string.format('GREETER {"cf":%s,"size":[2.4,6,2.4]}', f(inverse * out * G.CFrame.new(porch[1], 3, porch[2]))))
-- the path kept clear from the curb to the door (SandboxScenery.Path), in the house's frame (yaw 0: only moved)
local P = SandboxScenery.Path
print(string.format('PATH {"x0":%.17g,"x1":%.17g,"z0":%.17g,"z1":%.17g,"yaw":%g}', P.x0 - h.x, P.x1 - h.x, P.z0 - h.z, P.z1 - h.z, H.door.yaw))
-- 8.5 walking through: the doors' halls' depth (Config.Moving.Doors.Hall); the doors' leaves (a model each: the
-- model's doors copied) swung open as client/WalkDoors.luau swings a model (whole, about its hinge: shared/DoorSwing.luau)
print(string.format('HALL {"depth":%.17g,"wide":%.17g}', Config.Moving.Doors.Hall.Depth, Config.Moving.Doors.Wide))
local DoorSwing = require("./DoorSwing")
for _, leaf in (if chalet then chalet:GetChildren() else {}) do
	local hinge, side, angle = DoorSwing.read(leaf:GetAttribute("DoorLeaf"), leaf:GetAttribute("DoorSwing"), leaf:GetAttribute("DoorAngle"), Config.Moving.Doors.Angle)
	local primary = if leaf.ClassName == "Model" then leaf.PrimaryPart else nil
	if hinge ~= nil and hinge ~= 0 and primary then
		local frame = primary.CFrame
		local s = DoorSwing.pieces(primary.Size.X, primary.Size.Z, hinge, side, angle)[1]
		local open = frame * G.CFrame.new(s.ox + s.hx, 0, s.oz + s.hz) * G.CFrame.Angles(0, s.yaw, 0) * G.CFrame.new(-s.hx, 0, -s.hz)
		local move = open * frame:Inverse()
		for _, d in leaf:GetChildren() do
			print(string.format('OPEN {"copy":"%s","name":"%s","cf":%s,"size":[%.17g,%.17g,%.17g]}', leaf.Name, d.Name, f(inverse * move * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z))
		end
	end
end
for finish in require("./HouseMeshWorld").Looks do
	print(string.format('LOOK {"finish":"%s"}', finish))
end
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
    # 8.1 SANDBOX: SandboxWorld and HouseMesh on the world mock (tests/run_tests.py's way), DayNight marking the lights
    shutil.copy(ROOT / "tools/perf/world-mock.luau", tmp / "WorldMock.luau")
    env = 'setfenv(1, require("./WorldMock").env)\n'
    text = (ROOT / "src/server/SandboxWorld.luau").read_text()
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', text).replace("require(script.Parent.HouseMesh)", 'require("./HouseMeshWorld")')
    text = text.replace("require(script.Parent.VillageWorld)", 'require("./VillageWorldServer")')  # 8.9: Jinočany's village
    text = text.replace("require(script.Parent.LobbyWorld)", 'require("./LobbyWorldServer")')  # 9.7: the lobby
    (tmp / "SandboxWorldServer.luau").write_text(env + text)
    # 9.7: the lobby (server/LobbyWorld.luau) with its dispatch kiosk's art (server/MoveSites.luau, DayNight a stand-in)
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', (ROOT / "src/server/MoveSites.luau").read_text())
    (tmp / "MoveSitesWorld.luau").write_text(env + text.replace("require(script.Parent.DayNight)", "{ nightLight = function() end }"))
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', (ROOT / "src/server/LobbyWorld.luau").read_text())
    text = text.replace("require(script.Parent.MoveSites)", 'require("./MoveSitesWorld")')
    text = text.replace("require(script.Parent.VillageWorld)", 'require("./VillageWorldServer")')
    (tmp / "LobbyWorldServer.luau").write_text(env + text)
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', (ROOT / "src/server/VillageWorld.luau").read_text())
    (tmp / "VillageWorldServer.luau").write_text(env + text)
    text = (ROOT / "src/server/HouseMesh.luau").read_text()
    text = text.replace("require(script.Parent.DayNight)", '{ nightLight = function(p) p:SetAttribute("NightLight", true) end }')
    (tmp / "HouseMeshWorld.luau").write_text(env + text)
    (tmp / "sandbox.luau").write_text(SANDBOX)


def run(luau: str, tmp: Path, mode: str, harness: str = "harness.luau"):
    r = subprocess.run([luau, harness, "-a", mode], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    out = {"HOUSE": [], "PART": [], "DRESS": [], "LOOK": [], "HOME": [], "ENTER": [], "PATH": [], "GREETER": [], "HALL": [], "OPEN": []}
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


def hinge_x(part):
    """8.3 walk-in doors: a door leaf's hinge, its end DoorLeaf (±1) along its own X: that end's x (the house's frame)."""
    c, r, s = part["cf"][:3], part["cf"][3:], part["size"]
    return c[0] + r[0] * part["leaf"] * s[0] / 2


def overlap(a, b, margin=0.005):
    return all(a[0][i] < b[1][i] - margin and b[0][i] < a[1][i] - margin for i in range(3))


def main():
    luau = str(Path(sys.argv[1]).resolve())
    manifest = json.loads((Path(sys.argv[2]) if len(sys.argv) > 2 else MANIFEST).read_text())  # (another export: its JSON)
    target = manifest.get("target", "city")
    assert target == "sandbox", f"house.py TARGET {target!r}: only the sandbox's house is left (10.5: Marge's went with the city)"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        sandbox_plain = run(luau, tmp, "none", "sandbox.luau")
        sandbox_art = run(luau, tmp, "art", "sandbox.luau")
    finishes = {name.rsplit("_", 1)[1] for name in manifest["pieces"]}
    looks = {l["finish"] for l in sandbox_art["LOOK"]}
    assert finishes <= looks, f"finishes without a look in HouseMesh.LOOKS: {sorted(finishes - looks)}"
    for p in manifest["pieces"].values():
        assert p["triangles"] <= 10000, p
    assert sandbox_art["META"]["moved"], "the imported model was not moved to ServerStorage"
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


def halls_check(result, W, H, D):
    """8.5 walking through: the doorways walkable (the House box not solid, its HouseSolid pieces the box less a hall
    behind each doorway, nothing solid in a hall or its way out, the walls round it solid), each hall lined dark."""
    depth = result["HALL"][0]["depth"]
    parts = result["PART"]
    body = next(p for p in parts if p["own"] and p["name"] == "House")
    assert not body["collide"] and not body["query"], ("the House box still solid", body["collide"], body["query"])
    solids = [p for p in parts if p["name"] == "HouseSolid"]
    assert len(solids) == 7 and all(p["own"] and p["collide"] and p["query"] and p["t"] == 1 for p in solids), \
        ("the house's solid pieces", len(solids))
    halls = []
    for name, side in (("FrontDoor", -1), ("BackDoor", 1)):
        lo, hi = aabb(next(p for p in parts if p["name"] == name))
        face = side * D / 2
        z0, z1 = (face, face + depth) if side < 0 else (face - depth, face)
        out = ([lo[0], 0.05, face - 5], [hi[0], hi[1], face]) if side < 0 else ([lo[0], 0.05, face], [hi[0], hi[1], face + 5])
        halls.append((name, [lo[0], 0.05, z0], [hi[0], hi[1], z1], out))
    volume = sum(p["size"][0] * p["size"][1] * p["size"][2] for p in solids)
    want = W * H * D - sum((b[0] - a[0]) * b[1] * (b[2] - a[2]) for _, a, b, _ in halls)  # (each hall from the ground up)
    assert abs(volume - want) < 0.05, ("the solid pieces are not the box less the halls", volume, want)
    for name, lo, hi, (o_lo, o_hi) in halls:
        for p in parts:  # (the chalet's and its garden's: the ground is the world's)
            if p["collide"]:
                assert not overlap((lo, hi), aabb(p)), (name, "a solid part in its hall", p["name"])
                assert not overlap((o_lo, o_hi), aabb(p)), (name, "a solid part in its way out", p["name"])
        z = (lo[2] + hi[2]) / 2
        far = hi[2] + 0.5 if lo[2] < 0 else lo[2] - 0.5
        for area in (([lo[0] - 1, 1, z - 0.5], [lo[0] - 0.5, 6, z + 0.5]), ([hi[0] + 0.5, 1, z - 0.5], [hi[0] + 1, 6, z + 0.5]),
                     ([lo[0] + 0.5, hi[1] + 0.5, z - 0.5], [hi[0] - 0.5, hi[1] + 1, z + 0.5]), ([lo[0] + 0.5, 1, far - 0.25], [hi[0] - 0.5, 6, far + 0.25])):
            assert any(overlap(area, aabb(p)) for p in solids), (name, "the house not solid round its hall", area)
    lining = [p for p in parts if p["name"] == "DoorHall"]
    assert len(lining) == 10, ("the halls' dark lining", len(lining))
    for p in lining:
        lo, hi = aabb(p)
        assert not (p["collide"] or p["query"] or p["shadow"]) and p["t"] == 0 and not p["own"], ("a hall's lining", p["collide"], p["query"])
        assert any(all(lo[i] >= a[i] - 0.06 and hi[i] <= b[i] + 1e-3 for i in range(3)) for _, a, b, _ in halls), ("a hall's lining outside its hall", lo, hi)


def sandbox_check(manifest, plain, art):
    """8.1 SANDBOX: The Old Farmstead (server/SandboxWorld.luau) on house.py's box, dressed by HouseMesh once imported."""
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
        # (8.3: the doorways unseen behind their leaves; 8.5 the house's solid pieces unseen)
        assert p["class"] != "MeshPart" and p["t"] == (1 if p["name"] in ("FrontDoor", "BackDoor", "HouseSolid") else 0), (p["name"], "changed without an import")
    # Dressed.
    house = art["HOUSE"][0]
    assert house["dressed"] and art["META"]["moved"], (house, art["META"], "not dressed, or the import left in the world")
    own = [p for p in art["PART"] if p["own"] and p["class"] != "MeshPart"]
    meshes = [p for p in art["PART"] if p["class"] == "MeshPart"]
    garden = [p for p in art["PART"] if not p["own"] and not p["copy"] and p["name"] != "DoorHall"]  # (8.3: the doors' copies, 8.5 the halls' lining checked on their own)
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
    assert solid == ["HouseSolid"] * 7 + ["Roof", "Roof"], (solid, "the solid parts: the house's solid pieces (8.5: the box less its doors' halls) and the gable only")
    for result in (plain, art):
        halls_check(result, W, H, D)
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
    # 8.3 the big move: the back door on the model's back door (across it, as wide and tall, just outside its leaf, out of
    # the back wall), the leaves in their doorways
    backs = [p for p in art["PART"] if p["back"]]
    assert len(backs) == 1 and backs[0]["name"] == "BackDoor" and backs[0]["own"] and not backs[0]["collide"], backs
    b_lo, b_hi = aabb(backs[0])
    back_leaf = [box_of(d) for d in details if d["name"].startswith("Křídlo dveří") and d["center"][2] > 0]
    assert len(back_leaf) == 1, ("the model's back door", len(back_leaf))
    k_lo, k_hi = back_leaf[0]
    assert abs((b_lo[0] + b_hi[0]) / 2 - (k_lo[0] + k_hi[0]) / 2) < 0.1 and abs((b_hi[0] - b_lo[0]) - (k_hi[0] - k_lo[0])) < 0.25 \
        and abs(b_lo[1] - k_lo[1]) < 0.3 and abs(b_hi[1] - k_hi[1]) < 0.3 and b_lo[2] >= k_hi[2] - 1e-3 and b_lo[2] - k_hi[2] < 0.5, \
        ("the BackDoor is not on the model's back door", b_lo, b_hi, k_lo, k_hi)
    # (8.3 walk-in doors: door leaves of shared/DoorSwing.luau, hinged at a jamb: DoorLeaf ±1 at that end of its own X)
    leaf_parts = {p["name"]: p for p in plain["PART"] if p["leaf"] is not None}
    assert sorted(leaf_parts) == ["BackLeaf", "FrontLeafEast", "FrontLeafWest"], sorted(leaf_parts)
    plain_ways = {p["name"]: p for p in plain["PART"] if p["name"] in ("FrontDoor", "BackDoor")}
    for name, jamb, way in (("FrontLeafWest", 0, "FrontDoor"), ("FrontLeafEast", 1, "FrontDoor"), ("BackLeaf", 1, "BackDoor")):
        p = leaf_parts[name]
        lo_, hi_ = aabb(p)
        w_lo, w_hi = aabb(plain_ways[way])
        assert p["leaf"] in (-1, 1) and p["swing"] == -1 and p["dark"] and not p["copy"] and p["own"] and not p["collide"] and p["t"] == 0 \
            and p["angle"] == plain["HALL"][0]["wide"], (name, p["leaf"], p["swing"], p["dark"], p["angle"])
        assert all(lo_[i] >= w_lo[i] - 0.05 and hi_[i] <= w_hi[i] + 0.05 for i in range(3)), (name, "not in its doorway", lo_, hi_, w_lo, w_hi)
        assert abs(hinge_x(p) - (w_lo, w_hi)[jamb][0]) < 0.1, (name, "not hinged at its jamb (west, east, the back door's east)", hinge_x(p))
    # Dressed: the chalet's leaves no door leaves (hidden with it); the model's doors copied as the leaves that swing,
    # in front of its doors' leaves (covering them, their backs on the wall's face), within the doorways, hinged at the
    # opening's sides (the back door's away from its handle), nothing of the model in their way but the step under their
    # foot and what runs across the doorway (its opening cut out).
    assert not [p["name"] for p in art["PART"] if p["own"] and p["leaf"] is not None], "a hidden chalet leaf still a door leaf"
    knobs = [box_of(d) for d in details if d["name"].startswith("Klika") and d["center"][2] > 0]
    knob_x = sum((b[0][0] + b[1][0]) / 2 for b in knobs) / len(knobs)
    copies = [p for p in art["PART"] if p["copy"]]
    for model, want, (m_lo, m_hi), face in (("FrontDoorLeaf", [-1, 1], (l_lo, l_hi), -D / 2), ("BackDoorLeaf", [-1], (k_lo, k_hi), D / 2)):
        parts = [p for p in copies if p["copy"] == model]
        bodies = sorted((p for p in parts if p["name"] == "DoorLeaf"), key=lambda p: p["leaf"])
        assert len(parts) == 8 * len(want) and [p["leaf"] for p in bodies] == want, (model, len(parts), [p["leaf"] for p in bodies])
        c_lo = [min(aabb(p)[0][i] for p in bodies) for i in range(3)]
        c_hi = [max(aabb(p)[1][i] for p in bodies) for i in range(3)]
        outward = -1 if face < 0 else 1
        near, far = (c_hi, c_lo) if face < 0 else (c_lo, c_hi)
        assert c_lo[0] <= m_lo[0] + 1e-3 and c_hi[0] >= m_hi[0] - 1e-3 and abs(c_lo[1] - m_lo[1]) < 0.05 and abs(c_hi[1] - m_hi[1]) < 0.05 \
            and abs(near[2] - face) < 0.01 and (near[2] - (m_lo if face < 0 else m_hi)[2]) * outward >= -1e-3 and (far[2] - face) * outward > 0, \
            (model, "not just in front of the model's door, covering it", c_lo, c_hi, m_lo, m_hi)
        for p in parts:
            lo_, hi_ = aabb(p)
            assert p["swing"] == -1 and p["dark"] and not (p["collide"] or p["query"] or p["touch"]) and p["anchored"] and p["t"] == 0 and not p["own"] \
                and p["angle"] == art["HALL"][0]["wide"], (model, p["name"], p["angle"])
            assert lo_[0] >= c_lo[0] - 1e-3 and hi_[0] <= c_hi[0] + 1e-3 and lo_[1] >= c_lo[1] - 1e-3 and hi_[1] <= c_hi[1] + 1e-3, (model, p["name"], "outside its leaf")
            clash = [d["name"] for d in details if overlap((lo_, hi_), box_of(d)) and not d["name"].startswith("Schod")
                     and not (box_of(d)[0][0] <= m_lo[0] and box_of(d)[1][0] >= m_hi[0])]
            assert not clash, (model, p["name"], "in the model", clash[:8])
        for p in bodies:
            side = c_lo[0] if p["leaf"] * (p["cf"][3]) < 0 else c_hi[0]  # (its hinge end: its own +X, turned or not)
            assert abs(hinge_x(p) - side) < 1e-3 and abs(hinge_x(p)) > 0.5, (model, "not hinged at the opening's side", hinge_x(p))
        if model == "BackDoorLeaf":
            assert (hinge_x(bodies[0]) - (c_lo[0] + c_hi[0]) / 2) * (knob_x - (c_lo[0] + c_hi[0]) / 2) < 0, \
                ("the back door's leaf hung on its handle's side", hinge_x(bodies[0]), knob_x)
        # 8.5.1: the model's own door stays drawn in its pocket (house_door: part of the mesh, never hidden); open, the
        # copies' dark doorway (client/WalkDoors.luau's DoorDark: each body's face in its middle plane) covers all of it
        # from in front, so it is never seen through the opened doorway
        mid = (c_lo[2] + c_hi[2]) / 2
        assert (mid - (m_lo if face < 0 else m_hi)[2]) * outward > 0 and c_lo[0] <= m_lo[0] + 1e-3 and c_hi[0] >= m_hi[0] - 1e-3 \
            and c_lo[1] <= m_lo[1] + 0.05 and c_hi[1] >= m_hi[1] - 0.05, (model, "its dark doorway does not cover the model's door from in front", mid)
    baked = [p for p in art["PART"] if p["name"] == "house_door"]
    assert len(baked) == 1 and baked[0]["t"] == 0, ("the model's doors (house_door) not drawn as they are", baked)
    # 8.5: swung open (as client/WalkDoors.luau swings them: out of the house), every copy wholly in front of its wall,
    # clear of the model (its portal, lantern, bushes) but the step under its foot, and clear of its doorway
    opened = art["OPEN"]
    assert len(opened) == len(copies), ("the copies swung open", len(opened), len(copies))
    for p in opened:
        lo_, hi_ = aabb(p)
        front = p["copy"] == "FrontDoorLeaf"
        assert (hi_[2] <= -D / 2 + 1e-3) if front else (lo_[2] >= D / 2 - 1e-3), (p["copy"], p["name"], "not out of the house when open", lo_, hi_)
        clash = [d["name"] for d in details if overlap((lo_, hi_), box_of(d)) and not d["name"].startswith("Schod")]
        assert not clash, (p["copy"], p["name"], "swung open into the model", clash[:8])
        m_lo, m_hi = (l_lo, l_hi) if front else (k_lo, k_hi)
        assert hi_[0] <= m_lo[0] + 0.2 or lo_[0] >= m_hi[0] - 0.2 or p["name"] != "DoorLeaf", (p["copy"], "open but across its doorway", lo_, hi_)
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
        ("the back door's way out", ([k_lo[0], 0.3, D / 2 + 0.25], [k_hi[0], k_hi[1], D / 2 + 6.25])),
        ("the path", ([path["x0"], 0.3, path["z0"]], [path["x1"], 5, min(path["z1"], skin)])),
        ("the greeter's spot", aabb(art["GREETER"][0])),
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
    return (f"Sandbox house PASS: The Old Farmstead on house.py's box ({W:.2f} × {H:.2f} × {D:.2f}) as SandboxWorld builds it: "
            f"without the import the chalet; dressed, all {len(meshes)} pieces in place on House_sandbox_house, anchored, not "
            f"physical; the chalet's {len(own)} parts hidden, the house's solid pieces (8.5: the box less its doors' dark halls, walkable) and the gable solid, the gable "
            f"({house['pitch']:g}°) under the roof ({worst:.2f} studs at the least); the FrontDoor on the model's door, 8.3 the "
            f"BackDoor on its back door, their three leaves shut in them hinged at a jamb (dressed: the model's doors copied as "
            f"{len(copies)} parts of three leaves in front of them, 8.5 swung open out of the house clear of the model, 8.5.1 past square, the model's own doors drawn behind their dark doorway; "
            f"both doorways walkable into their dark halls, with or without the import); the Enter house box, both ways out, "
            f"the path (under the step) and the greeter's spot clear; the garden's {len(garden)} parts clear of the model")


if __name__ == "__main__":
    main()
