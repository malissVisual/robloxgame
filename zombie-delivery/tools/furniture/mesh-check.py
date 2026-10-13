#!/usr/bin/env python3
"""7.1: the moves' furniture in the owner's Blender models (server/FurnitureMesh.luau) on the real builders, without Studio.

Simulates the Roblox import of design/blender-furniture/roblox/ZDCFurnitureArt.fbx from its manifest
(ZDCFurnitureArt.json: every piece's box in its item's space, written by furniture.py): the importer turns the model a
quarter round, makes it 3 times bigger and moves it; FurnitureMesh must find the markers, undo that and dress every
piece FurnitureLooks.build makes (three variants each): each of the item's pieces once, where the model has it and inside
the item's box, welded to the Root and not physical, the Root untouched, the labels kept (their parts hidden), the
builders' other parts gone, within Config.Furniture.MaxParts, the palette finishes in the variant's colours. Then a
whole house (HouseInterior.build) dressed within Config.Furniture.InteriorMaxParts, and without the import every piece
left as FurnitureLooks makes it. Also: furniture.py's sizes are the catalogue's, every finish has a look.

    python3 zombie-delivery/tools/furniture/mesh-check.py <luau>
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
MANIFEST = ROOT / "design/blender-furniture/roblox/ZDCFurnitureArt.json"
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')
MOCKED = ("FurnitureLooks", "HouseLayout")
FACES = {"Front": (2, -1), "Back": (2, 1), "Left": (0, -1), "Right": (0, 1), "Top": (1, 1), "Bottom": (1, -1)}

# What the recorder lacks for FurnitureMesh: CFrame ± Vector3, CFrame.fromMatrix, MeshPart as a BasePart, a
# ServerStorage. Then the import (or none), FurnitureMesh, the checks' lines.
HARNESS = r'''
local M = require("./ItemMock")
local F = getmetatable(M.CFrame.identity)
F.__add = function(a, v) return setmetatable({ Position = a.Position + v, R = a.R }, F) end
F.__sub = function(a, v) return setmetatable({ Position = a.Position - v, R = a.R }, F) end
M.CFrame.fromMatrix = function(p, x, y, z) return setmetatable({ Position = p, R = { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z } }, F) end
local O = getmetatable(M.Instance.new("Part"))
local isA = O.IsA
O.IsA = function(self, c) if c == "BasePart" and self.ClassName == "MeshPart" then return true end return isA(self, c) end
local storage = M.Instance.new("Folder")
local get = M.game.GetService
M.game.GetService = function(self, name) if name == "ServerStorage" then return storage end return get(self, name) end
local MODE = (...)
local art = M.Instance.new("Model")
if MODE == "art" then
	art.Name = "ZDCFurnitureArt"
	art.Parent = M.workspace -- (as the importer leaves it: FurnitureMesh moves it to ServerStorage)
	-- The import: a quarter turn about up (Roblox's x → -z, z → x), 3 times the size, moved. The importer's own axes
	-- from Blender's: (x, z, -y).
	local K, MOVE = 3, M.Vector3.new(40, 3, -25)
	for _, row in require("./pieces") do
		local x, y, z = row[2], row[4], -row[3]
		local sx, sy, sz = row[5], row[7], row[6]
		local p = M.Instance.new("MeshPart")
		p.Name = row[1]
		p.CFrame = M.CFrame.new(z * K + MOVE.X, y * K + MOVE.Y, -x * K + MOVE.Z)
		p.Size = M.Vector3.new(sz * K, sy * K, sx * K)
		p.Anchored = true
		local skin = M.Instance.new("SurfaceAppearance")
		skin.Parent = p
		p.Parent = art
	end
end
local FurnitureLooks = require("./FurnitureLooks")
local FurnitureMesh = require("./FurnitureMesh")
local Config = require("./Config")
local function f(cf) local r = cf.R; return string.format("[%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g]", cf.Position.X, cf.Position.Y, cf.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]) end
local function c(col) return string.format("[%d,%d,%d]", math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5)) end
for name, look in FurnitureMesh.Looks do
	print(string.format('LOOK {"finish":"%s","color":%s}', name, if look.color then c(look.color) else "null"))
end
for _, id in FurnitureLooks.Order do
	print(string.format('ITEM {"id":"%s","size":[%g,%g,%g]}', id, FurnitureLooks.Items[id].size.X, FurnitureLooks.Items[id].size.Y, FurnitureLooks.Items[id].size.Z))
	for variant = 1, 3 do
		local model = FurnitureLooks.build(id, variant)
		local dressed = FurnitureMesh.dress(model, id, variant)
		local root = model.PrimaryPart
		local weldOf = {}
		for _, d in model:GetDescendants() do
			if d.ClassName == "WeldConstraint" then weldOf[d.Part1] = d.Part0 end
		end
		print(string.format('PIECE {"id":"%s","v":%d,"dressed":%s,"attr":%s,"root":{"cf":%s,"size":[%g,%g,%g],"t":%g,"collide":%s}}',
			id, variant, tostring(dressed), tostring(model:GetAttribute("MeshArt") == true), f(root.CFrame),
			root.Size.X, root.Size.Y, root.Size.Z, root.Transparency, tostring(root.CanCollide)))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				print(string.format('PART {"id":"%s","v":%d,"class":"%s","name":"%s","cf":%s,"size":[%g,%g,%g],"t":%g,"color":%s,"welded":%s,"label":%s,"face":"%s","collide":%s,"query":%s,"touch":%s,"massless":%s,"anchored":%s,"skin":%s}',
					id, variant, d.ClassName, d.Name, f(d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, d.Transparency or 0, c(d.Color), tostring(weldOf[d] == root),
					tostring(d:FindFirstChildWhichIsA("SurfaceGui") ~= nil), tostring(if d:FindFirstChildWhichIsA("SurfaceGui") then d:FindFirstChildWhichIsA("SurfaceGui").Face else ""), tostring(d.CanCollide), tostring(d.CanQuery), tostring(d.CanTouch),
					tostring(d.Massless), tostring(d.Anchored), tostring(d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil)))
			end
		end
		model:Destroy()
	end
end
-- A whole house, dressed.
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local plan = HouseLayout.plan(3, "house")
local interior, pieces = HouseInterior.build(plan, HouseInterior.slot(3))
local parts, dressed, total = 0, 0, 0
for _, d in interior:GetDescendants() do
	if d:IsA("BasePart") then parts += 1 end
end
for _, piece in pieces do
	total += 1
	if piece:GetAttribute("MeshArt") then dressed += 1 end
end
print(string.format('HOUSE {"parts":%d,"pieces":%d,"dressed":%d}', parts, total, dressed))
-- (FurnitureMesh found the import at the first piece it dressed)
print(string.format('META {"moved":%s,"maxParts":%d,"interiorMax":%d}', tostring(art.Parent == storage and MODE == "art"), Config.Furniture.MaxParts, Config.Furniture.InteriorMaxParts))
print("ALL DONE")
'''


def stage(tmp: Path, manifest: dict):
    for source in SHARED.glob("*.luau"):
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
        (tmp / source.name).write_text(PREFIX + text if source.stem in MOCKED else text)
    text = (ROOT / "src/server/HouseInterior.luau").read_text()
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', text)
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
    (tmp / "HouseInterior.luau").write_text(PREFIX + "local game = M.game\n" + text)
    text = (ROOT / "src/server/FurnitureMesh.luau").read_text()
    text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', text)
    (tmp / "FurnitureMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\nlocal warn = print\n" + text)
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    # Blender's coordinates of each piece's box (furniture.py: the item's cell, the game's x = Blender's -x, y = z, z = y).
    rows = []
    for name, p in manifest["pieces"].items():
        gx, gy, gz = p["center"]
        sx, sy, sz = p["size"]
        cx, cy, cz = manifest["items"][name.rsplit("_", 1)[0]]["cell"]
        rows.append([name, cx - gx, cy + gz, cz + gy, sx, sz, sy])
    for name, item in manifest["items"].items():
        cx, cy, cz = item["cell"]
        rows.append(["mark_" + name, cx, cy, cz, 0.3, 0.3, 0.3])
    for name, at in (("mark_o", (0, 0, 0)), ("mark_x", (-10, 0, 0)), ("mark_y", (0, 0, 10)), ("mark_z", (0, 10, 0))):
        rows.append([name, *at, 0.3, 0.3, 0.3])
    body = ",\n".join("{%s}" % ",".join([json.dumps(r[0])] + [repr(float(x)) for x in r[1:]]) for r in rows)
    (tmp / "pieces.luau").write_text("return {\n" + body + "\n}\n")
    (tmp / "harness.luau").write_text(HARNESS)


def run(luau: str, tmp: Path, mode: str):
    r = subprocess.run([luau, "harness.luau", "-a", mode], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0 and "ALL DONE" in r.stdout, r.stdout[-3000:] + r.stderr[-3000:]
    out = {"PIECE": [], "PART": [], "LOOK": [], "ITEM": []}
    for line in r.stdout.splitlines():
        kind, _, rest = line.partition(" ")
        if kind in out:
            out[kind].append(json.loads(rest))
        elif kind in ("META", "HOUSE"):
            out[kind] = json.loads(rest)
    return out


def box_in(part, bottom):
    """The part's box in its item's space (the Root at the origin, unturned; `bottom` its bottom's height)."""
    r = part["cf"][3:]
    size = [sum(abs(r[i * 3 + j]) * part["size"][j] for j in range(3)) for i in range(3)]
    return [part["cf"][0], part["cf"][1] - bottom, part["cf"][2]], size


def main():
    luau = str(Path(sys.argv[1]).resolve())
    manifest = json.loads(MANIFEST.read_text())
    finishes = {name.rsplit("_", 1)[1] for name in manifest["pieces"]}
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        stage(tmp, manifest)
        plain = run(luau, tmp, "none")
        art = run(luau, tmp, "art")
    looks = {l["finish"]: l["color"] for l in art["LOOK"]}
    missing = sorted(finishes - set(looks))
    assert not missing, f"finishes without a look in FurnitureMesh.LOOKS: {missing}"
    catalogue = {i["id"]: i["size"] for i in art["ITEM"]}
    assert set(catalogue) == set(manifest["items"]), (sorted(set(catalogue) ^ set(manifest["items"])), "furniture.py ITEMS ≠ FurnitureLooks.Order")
    for fid, size in catalogue.items():
        assert all(abs(a - b) < 1e-6 for a, b in zip(size, manifest["items"][fid]["size"])), (fid, size, manifest["items"][fid]["size"], "the sizes differ")
    # Without the import nothing changes.
    for piece in plain["PIECE"]:
        assert not piece["dressed"] and not piece["attr"], (piece["id"], "dressed without an import")
    assert not any(p["class"] == "MeshPart" for p in plain["PART"])
    assert plain["HOUSE"]["dressed"] == 0
    # With it, every piece dressed.
    meta = art["META"]
    assert meta["moved"], "the imported model was not moved to ServerStorage"
    parts_of = {}
    for p in art["PART"]:
        parts_of.setdefault((p["id"], p["v"]), []).append(p)
    by_item = {}
    for name, p in manifest["pieces"].items():
        by_item.setdefault(name.rsplit("_", 1)[0], {})[name] = p
    palette_colours = {}
    worst, labels = 0.0, 0
    for piece in art["PIECE"]:
        fid, v = piece["id"], piece["v"]
        want = by_item[fid]
        size = catalogue[fid]
        root = piece["root"]
        assert piece["dressed"] and piece["attr"], (fid, v, "not dressed")
        assert root["cf"][:3] == [0, 0, 0] and root["cf"][3:] == [1, 0, 0, 0, 1, 0, 0, 0, 1], (fid, "the Root moved")
        assert all(abs(a - b) < 1e-6 for a, b in zip(root["size"], size)) and root["t"] == 1 and root["collide"], (fid, "the Root changed")
        parts = parts_of.get((fid, v), [])
        assert len(parts) + 1 <= meta["maxParts"], (fid, v, len(parts) + 1, "parts over Config.Furniture.MaxParts")
        meshes = [p for p in parts if p["class"] == "MeshPart"]
        others = [p for p in parts if p["class"] != "MeshPart"]
        for p in others:
            assert p["label"] and p["t"] == 1, (fid, p["name"], "a builder's part left showing")
        names = [p["name"] for p in meshes]
        assert sorted(names) == sorted(want), (fid, v, sorted(set(names) ^ set(want)))
        for p in meshes:
            assert p["welded"] and not (p["collide"] or p["query"] or p["touch"]) and p["massless"] and not p["anchored"], (fid, p["name"], "physical or loose")
            assert not p["skin"], (fid, p["name"], "the importer's SurfaceAppearance kept")
            at, got = box_in(p, -size[1] / 2)
            w = want[p["name"]]
            assert all(abs(a - b) < 2e-3 for a, b in zip(at, w["center"])), (fid, p["name"], at, w["center"])
            assert all(abs(a - b) < 2e-3 for a, b in zip(got, w["size"])), (fid, p["name"], got, w["size"])
            lo = [at[0] - got[0] / 2, at[1] - got[1] / 2, at[2] - got[2] / 2]
            hi = [at[0] + got[0] / 2, at[1] + got[1] / 2, at[2] + got[2] / 2]
            over = max(-size[0] / 2 - lo[0], hi[0] - size[0] / 2, -lo[1], hi[1] - size[1], -size[2] / 2 - lo[2], hi[2] - size[2] / 2)
            worst = max(worst, over)
            assert over < 0.03, (fid, p["name"], f"sticks out of the box by {over:.3f}")
            finish = p["name"].rsplit("_", 1)[1]
            if looks[finish] is None:
                palette_colours.setdefault((fid, finish), set()).add(tuple(p["color"]))
            else:
                assert p["color"] == looks[finish], (fid, p["name"], p["color"], looks[finish])
        # A label's text (92 % × 80 % of its face) stays readable: no piece in front of it, and right behind it a piece of
        # the labelled part's own colour (a palette finish: any) that spans it.
        for label in (p for p in others if p["label"]):
            labels += 1
            axis, sign = FACES[label["face"]]
            at, got = box_in(label, -size[1] / 2)
            face = at[axis] + sign * got[axis] / 2
            text = {i: (at[i] - got[i] * (0.4 if i == 1 else 0.46), at[i] + got[i] * (0.4 if i == 1 else 0.46)) for i in range(3) if i != axis}
            behind = []
            for p in meshes:
                pat, pgot = box_in(p, -size[1] / 2)
                lo = [pat[i] - pgot[i] / 2 for i in range(3)]
                hi = [pat[i] + pgot[i] / 2 for i in range(3)]
                reach = sign * ((hi if sign > 0 else lo)[axis] - face)  # (> 0: in front of the label's face)
                if all(hi[i] > a and lo[i] < b for i, (a, b) in text.items()):
                    assert reach < 0.002, (fid, label["name"], label["face"], p["name"], f"covers the label by {reach:.3f}")
                if all(lo[i] <= a + 0.02 and hi[i] >= b - 0.02 for i, (a, b) in text.items()) and reach > -0.05:
                    behind.append((-reach, p))
            assert behind, (fid, label["name"], "no surface of the model right behind the label (it floats)")
            near = min(behind, key=lambda b: b[0])[1]
            finish = near["name"].rsplit("_", 1)[1]
            if looks[finish] is not None:
                diff = sum(abs(a - b) for a, b in zip(near["color"], label["color"]))
                assert diff < 60, (fid, label["name"], f"printed on {near['name']} {near['color']}, not its colour {label['color']}")
    same = [k for k, cols in palette_colours.items() if len(cols) < 2]
    assert not same, f"a palette finish in one colour for every variant: {same[:5]}"
    house = art["HOUSE"]
    assert house["dressed"] == house["pieces"] > 0, house
    assert house["parts"] <= meta["interiorMax"], (house, "parts over Config.Furniture.InteriorMaxParts")
    assert house["parts"] <= plain["HOUSE"]["parts"], (house["parts"], plain["HOUSE"]["parts"], "the dressed house has more parts")
    tris = sum(p["triangles"] for p in manifest["pieces"].values())
    print(f"Mesh furniture PASS: {len(catalogue)} items, {len(manifest['pieces'])} pieces ({tris} triangles, the largest "
          f"{max(p['triangles'] for p in manifest['pieces'].values())}) from a turned, scaled import on 3 variants each: in place "
          f"(at most {worst:.3f} out of a box), welded, not physical, {labels} labels kept readable, {len(palette_colours)} palette finishes in the "
          f"variant's colours; a house {house['parts']} parts dressed (FurnitureLooks' {plain['HOUSE']['parts']}); no import: unchanged")


if __name__ == "__main__":
    main()
