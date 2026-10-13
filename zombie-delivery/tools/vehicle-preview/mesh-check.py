#!/usr/bin/env python3
"""6.25: the ZDC Van in the owner's Blender model (server/VanMesh.luau) on the real factory, without Studio.

Simulates the Roblox import of design/blender-van/roblox/ZDCVanArt.fbx from its manifest (ZDCVanArt.json: every
piece's box in the game's axes, written by van.py): the importer turns the model a quarter round, makes it 3 times
bigger and moves it; VanMesh must find the markers, undo that and dress a ZDC Van: every piece once where the model
has it (the wheel on each of the four tyres), the doors on their hinged panels, nothing colliding, the factory's own
look hidden. Run: python3 tools/vehicle-preview/mesh-check.py <luau>
"""
from pathlib import Path
import json, subprocess, sys, tempfile
from export_fleet import prepare_modules, ROOT

MANIFEST = ROOT / "design/blender-van/roblox/ZDCVanArt.json"
HARNESS = r'''
local Mock = require("./roblox-mock")
local F = getmetatable(Mock.CFrame.identity)
F.__add = function(a, v) return setmetatable({ Position = a.Position + v, R = a.R }, F) end
F.__sub = function(a, v) return setmetatable({ Position = a.Position - v, R = a.R }, F) end
Mock.CFrame.fromMatrix = function(p, x, y, z) return setmetatable({ Position = p, R = { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z } }, F) end
local O = getmetatable(Mock.Instance.new("Part"))
local isA = O.IsA
O.IsA = function(self, c) if c == "BasePart" and self.ClassName == "MeshPart" then return true end return isA(self, c) end
local storage = Mock.Instance.new("Folder")
local get = Mock.game.GetService
Mock.game.GetService = function(self, name) if name == "ServerStorage" then return storage end return get(self, name) end
local art = Mock.Instance.new("Model")
art.Name = "ZDCVanArt"
art.Parent = Mock.workspace -- (as the importer leaves it: VanMesh moves it to ServerStorage)
-- The import: a quarter turn about up (x → -z, z → x), 3 times the size, moved.
local K, MOVE = 3, Mock.Vector3.new(40, 3, -25)
for _, row in require("./pieces") do
	local p = Mock.Instance.new("MeshPart")
	p.Name = row[1]
	p.CFrame = Mock.CFrame.new(row[4] * K + MOVE.X, row[3] * K + MOVE.Y, -row[2] * K + MOVE.Z)
	p.Size = Mock.Vector3.new(row[7] * K, row[6] * K, row[5] * K)
	p.Anchored = true
	p.Parent = art
end
local Vehicles = require("./Vehicles")
local Config = require("./Config")
local def
for _, d in Config.Cars do if d.id == "zdcvan" then def = d end end
local built = Vehicles.__testBuild(def, Mock.Color3.fromRGB(217, 204, 176), Mock.CFrame.identity, false, nil, false, 0, 0)
local ids, n = {}, 0
local function id(x) if not x then return 0 end if not ids[x] then n += 1; ids[x] = n end return ids[x] end
local function f(cf) local r = cf.R; return string.format("[%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g]", cf.Position.X, cf.Position.Y, cf.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]) end
local weldOf = {}
for _, d in built.model:GetDescendants() do
	if d.ClassName == "WeldConstraint" then weldOf[d.Part1] = d.Part0 end
end
local painted = {}
for _, p in built.paintParts do painted[p] = true end
print("META " .. string.format('{"meshart":"%s","moved":%s}', tostring(built.model:GetAttribute("MeshArt")), tostring(art.Parent == storage)))
for _, d in built.model:GetDescendants() do
	if d:IsA("BasePart") then
		print(string.format('PART {"id":%d,"class":"%s","name":"%s","cf":%s,"size":[%g,%g,%g],"t":%g,"to":%d,"collide":%s,"query":%s,"touch":%s,"massless":%s,"paint":%s}',
			id(d), d.ClassName, d.Name, f(d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, d.Transparency or 0, id(weldOf[d]),
			tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Massless), tostring(painted[d] == true)))
	elseif d.ClassName == "Motor6D" then
		print(string.format('MOTOR {"name":"%s","p1":%d}', d.Name, id(d.Part1)))
	end
end
print("ALL DONE")
'''


def main():
    luau = str(Path(sys.argv[1]).resolve())
    manifest = json.loads(MANIFEST.read_text())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        prepare_modules(tmp)
        rows = ",\n".join("{%s}" % ",".join([json.dumps(k)] + [repr(float(x)) for x in (*p["center"], *p["size"])]) for k, p in manifest.items())
        (tmp / "pieces.luau").write_text("return {\n" + rows + "\n}\n")
        (tmp / "harness.luau").write_text(HARNESS)
        r = subprocess.run([luau, "harness.luau"], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    lines = r.stdout.splitlines()
    meta = json.loads(next(l[5:] for l in lines if l.startswith("META ")))
    parts = [json.loads(l[5:]) for l in lines if l.startswith("PART ")]
    motors = [json.loads(l[6:]) for l in lines if l.startswith("MOTOR ")]
    assert meta["meshart"] == "zdcvan" and meta["moved"], meta
    by_id = {p["id"]: p for p in parts}
    hinged = {m["p1"] for m in motors if m["name"] in ("DoorHinge", "BackHinge")}
    tyres = {p["id"] for p in parts if p["name"] == "Tyre"}
    chassis = next(p for p in parts if p["name"] == "Chassis")
    root = next(p for p in parts if p["name"] == "BodyRoot")
    ground_y = chassis["cf"][1] + chassis["size"][1] / 2 - 2.1  # (VanMesh: the chassis top over the ground in the model)
    meshes = [p for p in parts if p["class"] == "MeshPart"]
    pieces = {k: v for k, v in manifest.items() if not k.startswith("mark_")}
    count = {}
    for p in meshes:
        count[p["name"]] = count.get(p["name"], 0) + 1
        assert not (p["collide"] or p["query"] or p["touch"]) and p["massless"], (p["name"], "physical")
        group = p["name"].split("_")[0]
        to = by_id.get(p["to"])
        if group in ("body", "kit"):
            assert to is root, (p["name"], "not on the BodyRoot")
        elif group == "wheel":
            assert p["to"] in tyres, (p["name"], "not on a tyre")
        else:
            assert p["to"] in hinged, (p["name"], "not on a hinged door")
        assert p["paint"] == p["name"].endswith("_paint"), (p["name"], "paint list")
        if group != "wheel":
            # Back in the car's axes the piece's box is the model's (the import's quarter turn and scale undone).
            want = pieces[p["name"]]
            r = p["cf"][3:]
            size = [sum(abs(r[i * 3 + j]) * p["size"][j] for j in range(3)) for i in range(3)]
            at = [p["cf"][0], p["cf"][1] - ground_y, p["cf"][2]]
            assert all(abs(a - b) < 2e-3 for a, b in zip(at, want["center"])), (p["name"], at, want["center"])
            assert all(abs(a - b) < 2e-3 for a, b in zip(size, want["size"])), (p["name"], size, want["size"])
    for name in pieces:
        assert count.get(name, 0) == (4 if name.startswith("wheel_") else 1), (name, count.get(name, 0))
    for p in parts:
        if p["name"] in ("Chassis", "Tyre", "CarDoor", "BackDoor", "Headlight", "Taillight", "Cabin", "Body", "DoorTrim", "BackTrim"):
            assert p["t"] == 1, (p["name"], "the factory's own look shows through")
    # Each wheel sits on its tyre's axle, its rim outward.
    for tyre in (p for p in parts if p["name"] == "Tyre"):
        rims = [p for p in meshes if p["name"] == "wheel_rim" and p["to"] == tyre["id"]]
        assert len(rims) == 1 and abs(rims[0]["cf"][1] - tyre["cf"][1]) < 1e-3 and abs(rims[0]["cf"][2] - tyre["cf"][2]) < 1e-3, tyre["cf"]
        assert abs(abs(rims[0]["cf"][0]) - 2.82) < 0.05, rims[0]["cf"][0]
    tris = sum(v["triangles"] for v in pieces.values())
    print(f"Mesh van PASS: {len(pieces)} pieces ({tris} triangles, the largest {max(v['triangles'] for v in pieces.values())}) "
          f"on a ZDC Van from a turned, scaled import: {len(meshes)} MeshParts in place, doors on their {len(hinged)} hinges, "
          f"the wheel on 4 tyres, nothing physical, the factory's look hidden")


if __name__ == "__main__":
    main()
