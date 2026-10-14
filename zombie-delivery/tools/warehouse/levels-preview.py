#!/usr/bin/env python3
"""8.3 SANDBOX: a preview sheet of the warehouse's five levels as the game builds them WITHOUT the owner's Blender import
(the parts buildings: shared/WarehouseLayout.luau's pieces at each level, Config.WarehouseLevels), each on a plot with
its display stands full of pieces (boxes of the real furniture sizes, coloured by rarity), from outside (the door, the
owner's sign) and from above with the roof off (the stands, the receiving zone, the UPGRADES desk). Drawn with three.js
in headless Chromium by tools/move-sites/render.mjs and render.html, laid out with PIL.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/warehouse/levels-preview.py <luau> <three.module.min.js> <out dir>

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Chromium from
CHROMIUM (default /opt/pw-browsers/chromium). Writes <out dir>/warehouse-levels.png (and each view's PNG beside it).
"""
import argparse
import json
import math
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "src" / "shared"
RENDERER = ROOT / "tools" / "move-sites"
GAP = 160  # studs between two levels' plots in the scene
FONTS = {"Black": "GothamBlack", "Bold": "GothamBold", "Medium": "GothamMedium"}
# the pieces on show: the catalogue's biggest and best-loved (their X, Y, Z: shared/FurnitureLooks.luau), by rarity
SHOWN = [("piano", (5.2, 4.6, 2.2), (178, 96, 236)), ("grandfather_clock", (2.0, 7.2, 1.4), (178, 96, 236)), ("bed", (5.4, 3.6, 7.4), (70, 144, 240)),
         ("sofa", (7.2, 3.4, 3.2), (70, 144, 240)), ("fridge", (3.0, 6.4, 2.8), (70, 144, 240)), ("record_player", (2.3, 4.8, 2.0), (178, 96, 236)),
         ("dining_table", (6.0, 3.3, 3.8), (92, 196, 104)), ("wardrobe", (4.4, 7.0, 2.2), (92, 196, 104)), ("tv", (3.4, 3.9, 2.4), (70, 144, 240)),
         ("armchair", (3.4, 3.4, 3.2), (92, 196, 104)), ("bookshelf", (4.2, 6.6, 1.6), (92, 196, 104)), ("lawn_mower", (2.2, 3.2, 4.2), (92, 196, 104))]

EXPORT = r'''
local WarehouseLayout = require("./WarehouseLayout")
local SandboxMap = require("./SandboxMap")
local Config = require("./Config")
local plot = SandboxMap.Plots[1]
local out = {}
local function num(n) return string.format("%.5f", n) end
local function list(t) local s = {} for i, v in t do s[i] = num(v) end return "[" .. table.concat(s, ",") .. "]" end
local function str(s) return '"' .. string.gsub(s, '[%c"\\]', function(c) return string.format("\\u%04x", string.byte(c)) end) .. '"' end
for n, def in Config.WarehouseLevels.List do
	for _, p in WarehouseLayout.pieces(plot, n) do
		local words = {}
		local faces = p.words
		if p.name == "OwnerSign" then
			faces = { { face = "Front", lit = true, lines = WarehouseLayout.ownerLines("Pavel", plot.id) } }
		elseif p.name == "StockBoard" then
			faces = { { face = "Front", lit = true, lines = WarehouseLayout.stockLines(3, 41.5, def.stands, def.stands) } }
		end
		for _, w in faces or {} do
			local lines = {}
			for _, l in w.lines do
				table.insert(lines, string.format('{"text":%s,"color":%s,"size":%s,"font":%s}', str(l.text), list(l.color), num(l.size), str(l.font or "Medium")))
			end
			table.insert(words, string.format('{"face":%s,"lines":[%s]}', str(w.face), table.concat(lines, ",")))
		end
		table.insert(out, string.format('{"level":%d,"name":%s,"group":%s,"at":%s,"size":%s,"yaw":%s,"pitch":%s,"roll":%s,"color":%s,"material":%s,"shape":%s,"t":%s,"words":[%s]}',
			n, str(p.name), str(p.group), list(p.at), list(p.size), num(p.yaw or 0), num(p.pitch or 0), num(p.roll or 0), list(p.color), str(p.material),
			str(p.shape or "Block"), num(p.transparency or 0), table.concat(words, ",")))
	end
	local stands = {}
	for _, s in WarehouseLayout.stands(plot, n) do
		table.insert(stands, string.format('{"x":%s,"y":%s,"z":%s}', num(s.x), num(s.y), num(s.z)))
	end
	local box = WarehouseLayout.box(plot, n)
	local o = WarehouseLayout.outline(plot, n)
	table.insert(out, string.format('{"level":%d,"meta":true,"name":%s,"stands":[%s],"box":%s,"top":%s,"parts":%d}', n, str(def.name), table.concat(stands, ","),
		list({ box.x, box.z, box.sx, box.sy, box.sz }), num(o.top), #WarehouseLayout.pieces(plot, n)))
end
local p = plot
print(string.format('{"plot":{"door":[%s,%s],"rect":[%s,%s,%s,%s],"van":[%s,%s]},"rows":[%s]}', num(p.door.x), num(p.door.z), num(p.rect.x0), num(p.rect.x1), num(p.rect.z0), num(p.rect.z1),
	num(p.vanSpot.x), num(p.vanSpot.z), table.concat(out, ",")))
'''


def export(luau: str) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for source in SHARED.glob("*.luau"):
            (tmp / source.name).write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text()))
        (tmp / "export.luau").write_text(EXPORT)
        r = subprocess.run([luau, "export.luau"], cwd=tmp, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
    return json.loads(r.stdout.strip().splitlines()[-1])


def rotation(yaw, pitch, roll):
    """Roblox's Angles(0, yaw, 0) * Angles(pitch, 0, roll) (shared/WarehouseLayout.luau turn), row by row."""
    y, x, z = math.radians(yaw), math.radians(pitch), math.radians(roll)
    ry = [[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]]
    rx = [[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]]
    rz = [[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    r = mul(ry, mul(rx, rz))
    return [r[i][j] for i in range(3) for j in range(3)]


def records(data, roofless: bool):
    plot = data["plot"]
    out = []
    for n in range(1, 6):
        dx = (n - 1) * GAP
        x0, x1, z0, z1 = plot["rect"]
        # the plot's concrete pad and the meadow round it (context)
        out.append({"kind": "context", "name": "Pad", "position": [(x0 + x1) / 2 + dx, -0.5, (z0 + z1) / 2], "rotation": rotation(0, 0, 0),
                    "size": [x1 - x0, 1, z1 - z0], "color": [185, 181, 173], "material": "Concrete"})
        out.append({"kind": "context", "name": "Meadow", "position": [(x0 + x1) / 2 + dx, -0.62, (z0 + z1) / 2 + 40], "rotation": rotation(0, 0, 0),
                    "size": [x1 - x0 + 40, 1, z1 - z0 + 160], "color": [104, 150, 78], "material": "Grass"})
        out.append({"kind": "context", "name": "Road", "position": [(x0 + x1) / 2 + dx, -0.3, z1 + 14], "rotation": rotation(0, 0, 0),
                    "size": [x1 - x0 + 40, 0.8, 28], "color": [70, 72, 76], "material": "Asphalt"})
    for row in data["rows"]:
        n, dx = row["level"], (row["level"] - 1) * GAP
        if row.get("meta"):
            for k, s in enumerate(row["stands"]):
                key, size, color = SHOWN[k % len(SHOWN)]
                out.append({"kind": "part", "name": f"Shown{k}", "position": [s["x"] + dx, s["y"] + size[1] / 2, s["z"]], "rotation": rotation(0, 0, 0),
                            "size": list(size), "color": list(color), "material": "SmoothPlastic"})
            continue
        if roofless and (row["group"] == "roof" or row["name"].startswith(("Gable", "Beam", "Lamp", "DoorHood", "DoorPanel", "ZdcSign", "Cornice", "Header", "Post"))):
            continue
        words = [{"face": w["face"], "lines": [dict(l, font=FONTS.get(l["font"], "GothamMedium")) for l in w["lines"]]} for w in row["words"]]
        out.append({"kind": "part", "name": row["name"], "position": [row["at"][0] + dx, row["at"][1], row["at"][2]],
                    "rotation": rotation(row["yaw"], row["pitch"], row["roll"]), "size": row["size"], "color": row["color"], "material": row["material"],
                    "shape": row["shape"], "transparency": row["t"], "words": words})
    return out


def views(data, kind: str):
    out = []
    for row in data["rows"]:
        if not row.get("meta"):
            continue
        n, dx = row["level"], (row["level"] - 1) * GAP
        bx, bz, W, H, D = row["box"]
        cx = bx + dx
        if kind == "outside":
            reach = max(W, D) * 0.9 + 26
            eye = [cx - reach * 0.75, H * 0.9 + reach * 0.42, bz + D / 2 + reach * 0.95]
            target = [cx + W * 0.05, H * 0.42, bz + D * 0.12]
            out.append({"name": f"level{n}-outside", "eye": eye, "target": target, "size": [800, 520], "fov": 42, "shadow": max(W, D) + 30})
        else:
            reach = max(W, D * 1.2) + 12
            eye = [cx, reach * 1.05 + 10, bz + D * 0.52 + reach * 0.42]
            target = [cx, 0, bz + D * 0.08]
            out.append({"name": f"level{n}-above", "eye": eye, "target": target, "size": [800, 520], "fov": 44, "shadow": max(W, D) + 30})
    return out


def sheet(renders: Path, data, output: Path):
    head = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 17)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    metas = [r for r in data["rows"] if r.get("meta")]
    w, h, label, pad = 800, 520, 34, 12
    img = Image.new("RGB", (2 * w + 3 * pad, 70 + len(metas) * (h + label + pad)), (16, 18, 22))
    draw = ImageDraw.Draw(img)
    draw.text((pad, 12), "ZOMBIE DELIVERY 8.3 · THE WAREHOUSE'S FIVE LEVELS (the parts buildings, no Blender import)", fill=(242, 242, 240), font=head)
    draw.text((pad, 44), "shared/WarehouseLayout.luau at each level on plot 1, its stands full (boxes of the real furniture sizes); left: outside, right: from above, the roof off",
              fill=(150, 156, 166), font=small)
    y = 70
    for row in metas:
        n = row["level"]
        _, _, W, H, D = row["box"]
        draw.text((pad, y + 6), f"LEVEL {n} · {row['name'].upper()} · {W:g} × {H:g} × {D:g} · {len(row['stands'])} stands · {row['parts']} parts", fill=(240, 132, 44), font=font)
        for k, kind in enumerate(("outside", "above")):
            picture = Image.open(renders / f"level{n}-{kind}.png").convert("RGB")
            img.paste(picture, (pad + k * (w + pad), y + label))
        y += h + label + pad
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output)
    print(f"Sheet: {len(metas)} levels -> {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    data = export(str(Path(args.luau).resolve()))
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        site = tmp / "site"
        site.mkdir()
        shutil.copy(RENDERER / "render.html", site / "render.html")
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        for kind, roofless in (("outside", False), ("above", True)):
            (tmp / f"{kind}.json").write_text(json.dumps(records(data, roofless)))
            (tmp / f"{kind}-views.json").write_text(json.dumps(views(data, kind)))
            subprocess.run(["node", str(RENDERER / "render.mjs"), str(tmp / f"{kind}.json"), str(tmp / f"{kind}-views.json"), str(args.out), str(site)], check=True)
    sheet(args.out, data, args.out / "warehouse-levels.png")


if __name__ == "__main__":
    main()
