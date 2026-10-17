#!/usr/bin/env python3
"""9.5: the countryside's spots for the owner (design/countryside/spots/*.png), without Roblox.

The real shared/VillageLooks.luau, shared/Layouts/Countryside.luau (through shared/HouseLayout.luau), shared/
FurnitureLooks.luau and server/HouseInterior.luau build every shot in the Luau CLI on the recorder (export.luau, staged
here as tests/run_tests.py stages them): the four spots' houses (the Pond Cabin, the Forest Lodge, the Old Mill, the
Orchard Cottage), each spot's inside from straight above with its furniture, and the countryside's own pieces.
tools/village/render.mjs draws them with three.js in headless Chromium (tools/village/render.html), and this lays out:

    looks.png               the four houses, from the front right and the front left
    plan-<kind>.png         each inside from above (the front door at the bottom: as you come in), its rooms and
                            pieces named (★ the client's, a collectible's rarity)
    pieces.png              the countryside's own pieces (Config.Furniture.Pieces)

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/spots/preview.py <luau> <three.module.min.js> [--out DIR]

three.module.min.js: three.js's build (e.g. three@0.160: package/build/three.module.min.js); Chromium from CHROMIUM
(default /opt/pw-browsers/chromium); --out defaults to design/countryside/spots.
"""
import argparse
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]
SRC = GAME / "src"
SHARED = SRC / "shared"
VILLAGE = GAME / "tools" / "village"
sys.dont_write_bytecode = True

BG = (29, 33, 39)
INK = (236, 238, 240)
SOFT = (170, 178, 188)
RARITY = {"uncommon": (110, 200, 120), "rare": (90, 160, 240), "epic": (190, 120, 240), "legendary": (250, 190, 60)}
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')


def stage(folder: Path):
    """The modules as tests/run_tests.py stages them: the pure ones as they are, the furniture, the plans and the
    interior on the recorder."""
    on_recorder = {"FurnitureLooks", "HouseLayout"}
    for path in sorted(SHARED.glob("*.luau")):
        source = path.read_text(encoding="utf-8")
        source = re.sub(r"require\(script\.Parent\.Layouts\.(\w+)\)", r'require("./\1")', source)
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
        (folder / path.name).write_text((PREFIX if path.stem in on_recorder else "") + source, encoding="utf-8")
    for path in sorted((SHARED / "Layouts").glob("*.luau")):
        source = re.sub(r"require\(script\.Parent\.Parent\.(\w+)\)", r'require("./\1")', path.read_text(encoding="utf-8"))
        (folder / path.name).write_text(PREFIX + source, encoding="utf-8")
    shutil.copy(GAME / "tools" / "vehicle-preview" / "roblox-mock.luau", folder / "rbxmock.luau")
    shutil.copy(GAME / "tools" / "fixtures" / "item-mock.luau", folder / "ItemMock.luau")
    source = (SRC / "server" / "HouseInterior.luau").read_text(encoding="utf-8")
    source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
    source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
    (folder / "HouseInterior.luau").write_text(PREFIX + "local game = M.game\n" + source, encoding="utf-8")
    source = (SRC / "server" / "FurnitureMesh.luau").read_text(encoding="utf-8")
    source = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', source)
    (folder / "FurnitureMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\n" + source, encoding="utf-8")
    source = (SRC / "server" / "FixtureMesh.luau").read_text(encoding="utf-8")
    source = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', source)
    storage = ('local storage = M.Instance.new("Folder")\n'
               'local game = { GetService = function(_, name) if name == "ServerStorage" then return storage end return M.game:GetService(name) end }\n'
               'local workspace = M.workspace\n')
    (folder / "FixtureMesh.luau").write_text(PREFIX + storage + source, encoding="utf-8")
    shutil.copy(HERE / "export.luau", folder / "main.luau")


def export(luau: str, folder: Path):
    stage(folder)
    result = subprocess.run([luau, "main.luau"], cwd=folder, capture_output=True, text=True, timeout=900)
    if result.returncode != 0:
        raise SystemExit(result.stdout[-3000:] + result.stderr[-3000:] + "\nspots preview: the export failed")
    shots = [json.loads(line[5:]) for line in result.stdout.splitlines() if line.startswith("SHOT ")]
    labels = [json.loads(line[7:]) for line in result.stdout.splitlines() if line.startswith("LABELS ")]
    if not shots:
        raise SystemExit(result.stdout[-3000:] + "\nspots preview: no shots")
    return shots, labels


def font(size, bold=False):
    for name in (("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"), ("LiberationSans-Bold.ttf" if bold else "LiberationSans-Regular.ttf")):
        for folder in ("/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation"):
            path = Path(folder) / name
            if path.exists():
                return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def sheet(title, note, tiles, columns, out: Path, caption_size=17, note_size=17):
    """tiles: [(image, caption)] laid out `columns` a row under a title."""
    pad, cap = 22, 34
    tw, th = tiles[0][0].size
    rows = (len(tiles) + columns - 1) // columns
    width = pad + columns * (tw + pad)
    # the note wrapped to the sheet's width, the tiles under its last line
    small = font(note_size)
    measure = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    lines, line = [], ""
    for word in note.split(" "):
        wider = (line + " " + word).strip()
        if line and measure.textlength(wider, font=small) > width - 2 * pad:
            lines.append(line)
            line = word
        else:
            line = wider
    lines.append(line)
    step = note_size + 6
    head = 62 + len(lines) * step + 12
    height = head + rows * (th + cap + pad) + pad // 2
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)
    draw.text((pad, 18), title, font=font(34, True), fill=INK)
    for n, text in enumerate(lines):
        draw.text((pad, 62 + n * step), text, font=small, fill=SOFT)
    for i, (tile, caption) in enumerate(tiles):
        x = pad + (i % columns) * (tw + pad)
        y = head + (i // columns) * (th + cap + pad)
        img.paste(tile, (x, y))
        draw.text((x + 2, y + th + 7), caption, font=font(caption_size), fill=INK)
    img.save(out, optimize=True)
    print(f"spots preview: {out} ({width} × {height})")


def tag(draw, x, y, text, fill, size=15, bold=False):
    """A label centred on (x, y) on a dark plate."""
    f = font(size, bold)
    box = draw.textbbox((0, 0), text, font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    draw.rounded_rectangle((x - w / 2 - 5, y - h / 2 - 4, x + w / 2 + 5, y + h / 2 + 5), radius=5, fill=(20, 22, 26, 200))
    draw.text((x - w / 2, y - h / 2 - box[1] + 1), text, font=f, fill=fill)


def plan_image(render: Image.Image, label: dict) -> Image.Image:
    """The top-down render with its rooms' and pieces' names (the camera straight down from `height` with `fov`: +Z up
    the picture, +X to its left, as you see the house coming in by its front door at the bottom)."""
    w, h = label["w"], label["h"]
    scale = h / (2 * label["height"] * math.tan(math.radians(label["fov"]) / 2))
    mx, mz = label["mid"]

    def at(x, z):
        return w / 2 - (x - mx) * scale, h / 2 - (z - mz) * scale

    img = render.convert("RGBA")
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(over)
    for room in label["rooms"]:
        x, y = at(room["x"], room["z"])
        tag(draw, x, y + 8, room["text"], (255, 236, 170), 16, True)
    for s in label["spots"]:
        x, y = at(s["x"], s["z"])
        text = s["text"] + (" ★" if s["star"] else "")
        tag(draw, x, y, text, RARITY.get(s["rarity"], INK), 13)
    x, y = at(0, -2.5)
    tag(draw, x, y + 6, "FRONT DOOR", (150, 230, 160), 15, True)
    return Image.alpha_composite(img, over).convert("RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("--out", type=Path, default=GAME / "design" / "countryside" / "spots")
    args = parser.parse_args()
    luau = str(Path(args.luau).resolve())
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        staged = folder / "stage"
        staged.mkdir()
        shots, labels = export(luau, staged)
        site = folder / "site"
        site.mkdir()
        shutil.copy(VILLAGE / "render.html", site / "render.html")
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        (folder / "shots.json").write_text(json.dumps(shots), encoding="utf-8")
        renders = folder / "renders"
        subprocess.run(["node", str(VILLAGE / "render.mjs"), str(site), str(folder / "shots.json"), str(renders)], check=True)
        by = {s["name"]: (Image.open(renders / f"{s['name']}.png").convert("RGB"), s["caption"]) for s in shots}
        args.out.mkdir(parents=True, exist_ok=True)
        looks = [by[n] for n in by if n.startswith("look-")]
        sheet("The countryside's spots: the houses",
              "VillageLooks.house: the Pond Cabin, the Forest Lodge, the Old Mill (its wheel on the right), the Orchard Cottage.",
              looks, 2, args.out / "looks.png")
        for label in labels:
            image, caption = by[label["name"]]
            plan = plan_image(image, label)
            sheet(label["title"], caption + ". From straight above, the front door at the bottom (as you come in); ★ the client's; "
                  "a collectible in its rarity's colour (uncommon green, rare blue, epic violet, legendary gold).", [(plan, "")], 1,
                  args.out / f"{label['name']}.png", note_size=15)
        pieces = [by[n] for n in by if n.startswith("piece-")]
        sheet("The countryside's own pieces (FurnitureLooks, Config.Furniture.Pieces)",
              "The Pond Cabin's, the Forest Lodge's, the Old Mill's and the Orchard Cottage's things to carry: who carries it, its weight (of 10), its value.",
              pieces, 6, args.out / "pieces.png", caption_size=12)


if __name__ == "__main__":
    main()
