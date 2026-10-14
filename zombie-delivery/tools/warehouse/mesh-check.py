#!/usr/bin/env python3
"""8.2 SANDBOX: the ZDC warehouse in the owner's Blender model (server/WarehouseMesh.luau) on the warehouses the real
server/Warehouse.luau builds, without Studio.

Simulates the Roblox import of design/blender-warehouse/roblox/ZDCWarehouseArt.fbx from its manifest
(ZDCWarehouseArt.json: every piece's box and every detail's in the building's frame, written by warehouse.py): the
importer turns the model a quarter round, makes it 3 times bigger, moves it and nests half of it in a sub-model. Then the
real server/Warehouse.luau (on tests/runtime/WarehouseRuntime.luau, as tests/warehouse_runtime_test.luau runs it, an
owner on plot 2) builds every plot's warehouse and hands each to the real WarehouseMesh. Checks:
  - the model is the layout's warehouse: warehouse.py's box, ridge, door, floor and walls are shared/WarehouseLayout.luau's
    (SandboxMap's plot, Config.Warehouse); every finish has a look; 15,000 – 30,000 triangles, at most 10,000 a piece,
    no flat piece;
  - without the import nothing changes (no mesh, nothing hidden);
  - with it the import leaves the world and every warehouse is dressed once (again: nothing more): every piece where the
    model has it on that plot, anchored, not physical, the importer's SurfaceAppearance gone, the lights' finishes night
    lights;
  - hidden: exactly the layout's visual pieces (WarehouseVisual: the shell, the roof, the door, the bollards, the ZDC
    sign, the floor, the hall's beams, posts and lamp housings), still colliding where they did; nothing else changed:
    the owner's sign and the STOCK board shown with their words, the stands, the desk, the paint, the lamps' glows and
    their lights, the prompts;
  - the model on the colliders: its walls' sheet on the walls' outer faces and its lining on their inner faces, its roof's
    underside on the roof slabs' underside, its floor on the floor; a shade over every lamp's glow;
  - the model keeps clear of everything the game keeps (no detail inside any part that stays), of the hall below 16 studs
    (but the columns along the side walls), of the way in through the door, of the front of the owner's sign, the STOCK
    board and the UPGRADES sign, and of the UNLOAD HERE bay;
  - a warehouse of another size or with no plot: left as it was.

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
BUDGET = (15000, 30000)
HIGH = 16.0  # the hall is the game's below this (the stands, the pieces on show, their tags, the desk, the boards)
SIDE = 37.9  # ... but along the side walls (|x| from here out: the columns)
# The layout's pieces that are only looks (the model draws them) and those that stay (they work or are written).
VISUAL = re.compile(r"^(Floor|WallBack|WallWest|WallEast|WallFrontWest|WallFrontEast|Header|Gable(Front|Back)(West|East)|"
                    r"Roof(West|East)|Barge(Front|Back)(West|East)|Gutter(West|East)|Downpipe(West|East)|RidgeCap|"
                    r"Rib(Back|Front|Header|West|East)\d+|(Plinth|Stripe)(Back|West|East|FrontWest|FrontEast)|"
                    r"Corner(Front|Back)(West|East)|DoorRail(West|East)|Bollard(West|East)|DoorCurtain|DoorBar|DoorHood|"
                    r"ZdcSign|Beam\d+|Post\d+(West|East)|Lamp\d+)$")
KEEP = re.compile(r"^(OwnerSign|StockBoard|UpgradeSign|LampGlow\d+|Stand\d+|StandTop\d+|Plate\d+|Terminal\w+|Spot\d+\w*|"
                  r"SpotText\d+|Receiving\w+|AisleLine\w+|Bay\w+)$")
WALLS = {  # a solid wall: the axis it is thin along, the sign of its outer face
    "WallBack": (2, -1), "WallWest": (0, -1), "WallEast": (0, 1), "WallFrontWest": (2, 1), "WallFrontEast": (2, 1), "Header": (2, 1),
}

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
		local p = M.Instance.new(if string.sub(row[1], 1, 13) == "WarehouseMark" then "Part" else "MeshPart")
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

for finish, look in WarehouseMesh.Looks do
	print(string.format('LOOK {"finish":"%s","night":%s}', finish, tostring(look.night ~= nil)))
end
-- The layout's numbers, each plot's relative to its warehouse's frame (its middle on the ground: only moved).
for _, plot in SandboxMap.Plots do
	local w = plot.warehouse
	local function rel(r) return { x0 = r.x0 - w.x, x1 = r.x1 - w.x, z0 = r.z0 - w.z, z1 = r.z1 - w.z } end
	local o = WarehouseLayout.outline(plot)
	local d = WarehouseLayout.door(plot)
	print(string.format('LAYOUT {"plot":%d,"x":%.6f,"z":%.6f,"size":[%.6f,%.6f,%.6f],"outline":%s,"top":%.6f,"door":[%.6f,%.6f,%.6f,%.6f],"floorTop":%.6f,"wall":%.6f,"inside":%s,"doorPath":%s,"bay":%s}',
		plot.id, w.x, w.z, w.sx, w.sy, w.sz, rect(rel(o)), o.top, d.x - w.x, d.z - w.z, d.width, d.height, WarehouseLayout.FloorTop,
		WarehouseLayout.Wall, rect(rel(WarehouseLayout.inside(plot))), rect(rel(WarehouseLayout.doorPath(plot))), rect(rel(WarehouseLayout.bay(plot)))))
end

local ana = W.player(101, "Ana", M.Vector3.new(-65, 3, -150))
W.claim(2, ana)
Warehouse.start()

local function count(model)
	local n = 0
	for _, d in model:GetDescendants() do if d.ClassName == "MeshPart" then n += 1 end end
	return n
end
local before = count(Warehouse.model(1))
local again = WarehouseMesh.dress(Warehouse.model(1))
local after = count(Warehouse.model(1))
-- a warehouse of another size, one with no plot: left as they are
local function stray(id)
	local model = M.Instance.new("Model")
	model:SetAttribute("Plot", id)
	local wall = M.Instance.new("Part")
	wall.Name = "WallBack"
	wall:SetAttribute(WarehouseMesh.Attribute, true)
	wall.Parent = model
	return model, wall
end
local w1 = SandboxMap.Plots[1].warehouse
w1.sx += 4
local wide, wideWall = stray(1)
local wideDressed = WarehouseMesh.dress(wide)
w1.sx -= 4
local lost, lostWall = stray(99)
local lostDressed = WarehouseMesh.dress(lost)
print(string.format('META {"moved":%s,"ready":%s,"again":%s,"before":%d,"after":%d,"wide":%s,"wideHidden":%s,"lost":%s,"lostHidden":%s}',
	tostring(art.Parent == storage and MODE == "art"), tostring(WarehouseMesh.ready()), tostring(again), before, after,
	tostring(wideDressed), tostring(wideWall.Transparency == 1 or wide:FindFirstChild("WarehouseMesh") ~= nil),
	tostring(lostDressed), tostring(lostWall.Transparency == 1 or lost:FindFirstChild("WarehouseMesh") ~= nil)))

for _, plot in SandboxMap.Plots do
	local model = Warehouse.model(plot.id)
	local base = M.CFrame.new(plot.warehouse.x, 0, plot.warehouse.z)
	print(string.format('PLOT {"plot":%d,"dressed":%s,"meshes":%d}', plot.id, tostring(model:GetAttribute("MeshArt") == true), count(model)))
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
			print(string.format('PART {"plot":%d,"class":"%s","name":"%s","parent":"%s","cf":%s,"size":[%.6f,%.6f,%.6f],"t":%g,"shadow":%s,"collide":%s,"query":%s,"touch":%s,"anchored":%s,"night":%s,"visual":%s,"skin":%s,"guis":[%s],"lights":%d,"prompts":%d,"color":[%.4f,%.4f,%.4f]}',
				plot.id, d.ClassName, d.Name, d.Parent.Name, f(base:Inverse() * d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, d.Transparency or 0,
				tostring(d.CastShadow), tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.Anchored),
				tostring(d:GetAttribute("NightLight") == true), tostring(d:GetAttribute(WarehouseMesh.Attribute) == true),
				tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil), table.concat(guis, ","), lights, prompts, d.Color.R, d.Color.G, d.Color.B))
		end
	end
end
print("ALL DONE")
'''


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
    text = text.replace("require(script.Parent.DayNight)", "{ nightLight = M.nightLight }")
    assert "script.Parent" not in text, "WarehouseMesh requires a module this check does not stage"
    (tmp / "WarehouseMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\nlocal warn = print\n" + text)
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
    # Blender's coordinates of each piece's box and each marker (warehouse.py: Blender x = x, y = -z, z = y).
    rows = []
    for name, p in manifest["pieces"].items():
        (gx, gy, gz), (sx, sy, sz) = p["center"], p["size"]
        rows.append([name, gx, -gz, gy, sx, sz, sy])
    for name, (gx, gy, gz) in manifest["markers"].items():
        rows.append([name, gx, -gz, gy, 0.3, 0.3, 0.3])
    body = ",\n".join("{%s}" % ",".join([json.dumps(r[0])] + [repr(float(x)) for x in r[1:]]) for r in rows)
    (tmp / "pieces.luau").write_text("return {\n" + body + "\n}\n")
    (tmp / "harness.luau").write_text(HARNESS)


def run(luau: str, tmp: Path, mode: str):
    r = subprocess.run([luau, "harness.luau", "-a", mode], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    out = {"LOOK": [], "LAYOUT": [], "PLOT": [], "PART": [], "WARN": []}
    for line in r.stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind == "WARN" or line.startswith("ZDCWarehouseArt:"):
            out["WARN"].append(line)
        elif kind in out:
            out[kind].append(json.loads(rest))
        elif kind == "META":
            out[kind] = json.loads(rest)
    return out


def aabb(part):
    """A part's box in its plot's frame (its cf is already there)."""
    r = part["cf"][3:]
    half = [sum(abs(r[i * 3 + j]) * part["size"][j] for j in range(3)) / 2 for i in range(3)]
    at = part["cf"][:3]
    return [at[i] - half[i] for i in range(3)], [at[i] + half[i] for i in range(3)]


def box_of(d):
    c, s = d["center"], d["size"]
    return [c[i] - s[i] / 2 for i in range(3)], [c[i] + s[i] / 2 for i in range(3)]


def overlap(a, b, margin=0.005):
    return all(a[0][i] < b[1][i] - margin and b[0][i] < a[1][i] - margin for i in range(3))


def close(a, b, eps=2e-3):
    return all(abs(x - y) < eps for x, y in zip(a, b))


def check_manifest(manifest, layout):
    lay = layout[0]
    W, H, D = manifest["box"]
    assert close((W, H, D), lay["size"], 1e-4), (manifest["box"], lay["size"], "warehouse.py's W, H, D are not the plot's warehouse")
    o = lay["outline"]
    assert close((o["x0"], o["x1"], o["z0"], o["z1"]), (-W / 2, W / 2, -D / 2, D / 2), 1e-4), ("the layout's outline", o)
    assert abs(H + manifest["ridge"] - lay["top"]) < 1e-4, (manifest["ridge"], lay["top"], "warehouse.py's RIDGE is not Config.Warehouse.Ridge")
    assert close(manifest["door"], lay["door"][2:], 1e-4) and close(lay["door"][:2], (0, D / 2), 1e-4), (manifest["door"], lay["door"])
    assert abs(manifest["floorTop"] - lay["floorTop"]) < 1e-6 and abs(manifest["wall"] - lay["wall"]) < 1e-6, (manifest["floorTop"], manifest["wall"], lay)
    for other in layout[1:]:
        assert close(other["size"], lay["size"]) and close(list(other["outline"].values()), list(o.values())) \
            and close(list(other["doorPath"].values()), list(lay["doorPath"].values())), ("the plots' warehouses differ", other["plot"])
    marks = manifest["markers"]
    want = {"WarehouseMark_o": [0, 0, 0], "WarehouseMark_x": [10, 0, 0], "WarehouseMark_y": [0, 10, 0], "WarehouseMark_z": [0, 0, 10],
            "WarehouseMark_b": [W / 2, H, D / 2], "WarehouseMark_r": [0, H + manifest["ridge"], 0]}
    assert set(marks) == set(want) and all(close(marks[k], v, 1e-6) for k, v in want.items()), marks
    pieces = manifest["pieces"]
    for name, p in pieces.items():
        assert re.fullmatch(r"warehouse\d*_[a-z0-9]+", name), (name, "not warehouse_<finish>")
        assert p["triangles"] <= 10000, (name, p["triangles"], "more than 10,000 triangles in one piece")
        assert min(p["size"]) >= 0.01, (name, p["size"], "a flat piece (Roblox sizes a mesh by its box)")
    tris = sum(p["triangles"] for p in pieces.values())
    assert tris == manifest["triangles"] and BUDGET[0] <= tris <= BUDGET[1], (tris, f"the budget is {BUDGET}")
    return tris


def main():
    luau = str(Path(sys.argv[1]).resolve())
    manifest = json.loads(MANIFEST.read_text())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        plain = run(luau, tmp, "none")
        art = run(luau, tmp, "art")
    tris = check_manifest(manifest, art["LAYOUT"])
    pieces = manifest["pieces"]
    finishes = {name.split("_", 1)[1] for name in pieces}
    looks = {l["finish"]: l["night"] for l in art["LOOK"]}
    assert not finishes - set(looks), ("finishes without a look in WarehouseMesh.Looks", sorted(finishes - set(looks)))
    plots = [p["plot"] for p in art["LAYOUT"]]

    # Without the import: nothing at all.
    meta = plain["META"]
    assert not (meta["ready"] or meta["moved"] or meta["again"] or meta["before"] or meta["after"]), meta
    assert not any(p["dressed"] or p["meshes"] for p in plain["PLOT"]), plain["PLOT"]
    for p in plain["PART"]:
        assert p["class"] != "MeshPart", (p["plot"], p["name"], "a mesh without the import")
    by_plain = {(p["plot"], p["name"]): p for p in plain["PART"]}
    assert len(by_plain) == len(plain["PART"]), "two parts of a warehouse share a name"

    # The layout's pieces: the visual ones exactly the looks, none of what stays.
    visual = {name for (plot, name), p in by_plain.items() if plot == plots[0] and p["visual"]}
    names = {name for (plot, name) in by_plain if plot == plots[0]}
    want_visual = {n for n in names if VISUAL.match(n)}
    assert visual == want_visual, ("the visual pieces", sorted(visual ^ want_visual)[:12])
    stray = sorted(n for n in names if not VISUAL.match(n) and not KEEP.match(n))
    assert not stray, ("pieces the check does not know (visual or kept?)", stray[:12])
    for name in ("OwnerSign", "StockBoard", "UpgradeSign", "LampGlow1", "Stand1", "TerminalDesk", "ReceivingText", "BayText"):
        assert name in names and name not in visual, (name, "must stay as it is")

    # With it: out of the world, every warehouse dressed once.
    meta = art["META"]
    assert meta["ready"] and meta["moved"], ("the import was not taken out of the world", meta)
    assert meta["again"] and meta["before"] == meta["after"] == len(pieces), ("dressing again added pieces", meta, len(pieces))
    assert not (meta["wide"] or meta["wideHidden"] or meta["lost"] or meta["lostHidden"]), ("dressed a warehouse of another size or none", meta)
    assert all(p["dressed"] and p["meshes"] == len(pieces) for p in art["PLOT"]) and len(art["PLOT"]) == len(plots), art["PLOT"]
    assert not art["WARN"], art["WARN"][:5]

    worst = 0.0
    for plot in plots:
        meshes = [p for p in art["PART"] if p["plot"] == plot and p["class"] == "MeshPart"]
        assert sorted(p["name"] for p in meshes) == sorted(pieces), (plot, sorted({p["name"] for p in meshes} ^ set(pieces)))
        for m in meshes:
            assert m["parent"] == "WarehouseMesh", (plot, m["name"], m["parent"])
            assert m["anchored"] and not (m["collide"] or m["query"] or m["touch"]), (plot, m["name"], "physical")
            assert not m["skin"], (plot, m["name"], "the importer's SurfaceAppearance kept")
            finish = m["name"].split("_", 1)[1]
            assert m["night"] == looks[finish], (plot, m["name"], "night light")
            lo, hi = aabb(m)
            want = pieces[m["name"]]
            at, size = [(a + b) / 2 for a, b in zip(lo, hi)], [b - a for a, b in zip(lo, hi)]
            worst = max(worst, max(abs(a - b) for a, b in zip(at, want["center"])))
            assert close(at, want["center"]) and close(size, want["size"]), (plot, m["name"], at, size, want)
        # Hidden: exactly the visual parts (still colliding where they did); everything else as built.
        for p in (p for p in art["PART"] if p["plot"] == plot and p["class"] != "MeshPart"):
            was = by_plain[(plot, p["name"])]
            for key in ("collide", "query", "touch", "anchored", "cf", "size", "lights", "prompts", "color"):
                assert p[key] == was[key], (plot, p["name"], key, "changed")
            if p["visual"]:
                assert p["t"] == 1 and p["shadow"] is False and all(g == "false" for g in p["guis"]), (plot, p["name"], "still seen")
            else:
                assert p["t"] == was["t"] and p["shadow"] == was["shadow"] and p["guis"] == was["guis"], (plot, p["name"], "changed")
        parts = {p["name"]: p for p in art["PART"] if p["plot"] == plot}
        for name in ("OwnerSign", "StockBoard", "UpgradeSign"):
            assert parts[name]["t"] == 0 and parts[name]["guis"] == ["true"], (plot, name, "its words not shown")
        assert parts["ZdcSign"]["guis"] == ["false"], (plot, "the parts' ZDC sign still shows its words")
        glows = [p for n, p in parts.items() if n.startswith("LampGlow")]
        assert glows and all(g["t"] == 0 and g["lights"] == 1 for g in glows), (plot, "a lamp's glow or its light lost")
        if plot == 2:
            assert sum(p["prompts"] for p in parts.values()) > 0, "the owner's prompts are gone"

    # The model on the colliders (one plot: they are the same, only moved).
    parts = {p["name"]: p for p in plain["PART"] if p["plot"] == plots[0]}
    details = manifest["details"]
    W, H, D = manifest["box"]
    floor_top = manifest["floorTop"]
    inner = [-W / 2 + 1, W / 2 - 1], [-D / 2 + 1, D / 2 - 1]
    linings = [box_of(d) for d in details if d["finish"] == "liner"]
    sheets = [box_of(d) for d in details if d["finish"] == "clad" and d["name"].endswith(("plech", "západ", "východ", "vraty"))]
    for name, (axis, out) in WALLS.items():
        lo, hi = aabb(parts[name])
        assert parts[name]["collide"], (name, "not solid")
        inner_plane, outer_plane = (lo[axis], hi[axis]) if out < 0 else (hi[axis], lo[axis])
        inner_plane, outer_plane = (hi[axis], lo[axis]) if out < 0 else (lo[axis], hi[axis])
        others = [i for i in range(3) if i != axis]
        # the lining on the wall's inner face, over all of it the hall sees
        face_lo = [max(lo[i], inner[0][0] if i == 0 else floor_top if i == 1 else inner[1][0]) for i in others]
        face_hi = [min(hi[i], inner[0][1] if i == 0 else 1e9 if i == 1 else inner[1][1]) for i in others]
        covered = any(abs(b[0][axis] - inner_plane) < 1e-3 and abs(b[1][axis] - inner_plane) < 1e-3
                      and all(b[0][i] <= fl + 1e-3 and b[1][i] >= fh - 1e-3 for i, fl, fh in zip(others, face_lo, face_hi)) for b in linings)
        assert covered, (name, "no lining on its inner face", inner_plane, face_lo, face_hi)
        # the sheet's back on the wall's outer face, along all of it (but behind the door's rails)
        on = [b for b in sheets if abs((b[1][axis] if out < 0 else b[0][axis]) - outer_plane) < 1e-3]
        along = 2 if axis == 0 else 0
        spans = sorted((b[0][along], b[1][along]) for b in on if b[0][1] < hi[1] - 0.1 and b[1][1] > lo[1] + 0.1)
        reach, gaps = lo[along], []
        for a, b in spans:
            if a > reach + 1e-3:
                gaps.append((reach, a))
            reach = max(reach, b)
        if reach < hi[along] - 1e-3:
            gaps.append((reach, hi[along]))
        assert spans and all(13 - 1e-3 <= abs(a) and abs(b) <= 13.7 + 1e-3 for a, b in gaps), (name, "the sheet does not cover its outer face", gaps)
    # the roof's underside on the slabs' underside, its sheet within the slabs
    for side, tag in ((-1, "západ"), (1, "východ")):
        slab = parts["RoofWest" if side < 0 else "RoofEast"]
        r, c, s = slab["cf"][3:], slab["cf"][:3], slab["size"]
        bottom = [[c[i] + r[i * 3] * a * s[0] / 2 - r[i * 3 + 1] * s[1] / 2 + r[i * 3 + 2] * b * s[2] / 2 for i in range(3)] for a in (-1, 1) for b in (-1, 1)]
        b_lo = [min(p[i] for p in bottom) for i in range(3)]
        b_hi = [max(p[i] for p in bottom) for i in range(3)]
        under = box_of(next(d for d in details if d["name"] == f"Podhled {tag}"))
        assert close(under[0], b_lo) and close(under[1], b_hi), (tag, "the roof's underside is not the slab's", under, b_lo, b_hi)
        top = box_of(next(d for d in details if d["name"] == f"Střecha {tag}"))
        s_lo, s_hi = aabb(slab)
        assert all(top[0][i] >= s_lo[i] - 0.01 and top[1][i] <= s_hi[i] + 0.01 for i in (0, 1)), (tag, "the roof's sheet outside its slab", top, s_lo, s_hi)
    # the floor on the floor
    f_lo, f_hi = aabb(parts["Floor"])
    model_floor = box_of(next(d for d in details if d["name"] == "Podlaha"))
    assert close(model_floor[0], f_lo) and close(model_floor[1], f_hi), ("the model's floor is not the floor", model_floor, f_lo, f_hi)
    # a shade over every lamp's glow
    shades = [box_of(d) for d in details if d["name"] == "Lampa"]
    for name, glow in ((n, p) for n, p in parts.items() if n.startswith("LampGlow")):
        g_lo, g_hi = aabb(glow)
        over = [b for b in shades if close([(b[0][i] + b[1][i]) / 2 for i in (0, 2)], [(g_lo[i] + g_hi[i]) / 2 for i in (0, 2)], 0.01)
                and abs(b[0][1] - g_hi[1]) < 0.01 and b[1][0] - b[0][0] >= g_hi[0] - g_lo[0]]
        assert len(over) == 1, (name, "no shade over it")

    # Clear: nothing of the model in a part the game keeps, in the hall below HIGH (but along the side walls), in the way
    # in, in front of the signs the game writes, on the bay.
    lay = next(l for l in art["LAYOUT"] if l["plot"] == plots[0])
    kept = [(n, aabb(p)) for n, p in parts.items() if not p["visual"]]
    path, bay = lay["doorPath"], lay["bay"]
    keep_clear = [
        ("the hall", ([inner[0][0], floor_top, inner[1][0]], [inner[0][1], HIGH, inner[1][1]])),
        ("the way in", ([path["x0"], 0.1, path["z0"]], [path["x1"], 14.0, path["z1"]])),
        ("the bay", ([bay["x0"], 0.1, bay["z0"]], [bay["x1"], 11.0, bay["z1"]])),
    ]
    for name, front in (("OwnerSign", 3.0), ("StockBoard", -1.5), ("UpgradeSign", -1.5)):
        lo, hi = aabb(parts[name])
        keep_clear.append((f"the front of {name}", ([lo[0], lo[1], hi[2] if front > 0 else lo[2] - abs(front)],
                                                    [hi[0], hi[1], hi[2] + front if front > 0 else hi[2] + abs(front)])))
    clashes = []
    for d in details:
        box = box_of(d)
        for name, area in kept:
            if overlap(box, area):
                clashes.append((d["name"], name))
        for name, area in keep_clear:
            along_wall = box[0][0] >= SIDE or box[1][0] <= -SIDE
            if overlap(box, area) and not (name == "the hall" and along_wall):
                clashes.append((d["name"], name))
    assert not clashes, f"the model where the game needs room: {clashes[:10]}"

    hidden = sum(1 for p in plain["PART"] if p["plot"] == plots[0] and p["visual"])
    print(f"Mesh warehouse PASS: {len(pieces)} pieces ({tris} triangles, the largest {max(p['triangles'] for p in pieces.values())}; "
          f"{W:g} × {H:g} × {D:g}, ridge {manifest['ridge']:g}, door {manifest['door'][0]:g} × {manifest['door'][1]:g}, the layout's) "
          f"from a turned, scaled import on the {len(plots)} warehouses Warehouse.luau builds: every piece in place (at most "
          f"{worst:.4f} off), anchored, not physical; the {hidden} visual parts hidden and still colliding, nothing else changed; the walls, "
          f"the roof and the floor on their colliders, a shade on each lamp; clear of the {len(kept)} kept parts, the hall, the way "
          f"in, the signs and the bay; again, another size, no plot, no import: unchanged")


if __name__ == "__main__":
    main()
