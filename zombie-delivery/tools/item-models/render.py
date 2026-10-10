#!/usr/bin/env python3
"""6.22: a contact sheet of every inventory thing's 3D look, as BAG & ITEMS and the bottom bar draw it.

Builds every look (shared/ItemLooks.luau ItemLooks.all: the guns, the bat, the fists, the consumables, the bags, the
vests, the cargo) with the real builders (ItemLooks, GunModels, CargoLooks, KitArt) on the recorder
(tools/fixtures/item-mock.luau over tools/vehicle-preview/roblox-mock.luau) in the Luau CLI (export.luau), renders
each with three.js in headless Chromium at the in-game camera and light (render.mjs, render.html) and lays them out
with their names and part counts.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/item-models/render.py <luau> <three.module.min.js> <sheet.png>

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Playwright and
Chromium as for the other previews (CHROMIUM overrides /opt/pw-browsers/chromium).
"""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
SHARED = ROOT / "src" / "shared"
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')
GROUPS = (("gun", "GUNS"), ("melee", "HANDS"), ("fists", "HANDS"), ("item", "ITEMS"), ("kit", "BAGS & VESTS"), ("cargo", "CARGO"))


def export(luau: str, tmp: Path) -> Path:
    for source in SHARED.glob("*.luau"):
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
        if source.stem in ("GunModels", "CargoLooks", "ItemLooks"):
            text = PREFIX + text
        (tmp / source.name).write_text(text)
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    shutil.copy(HERE / "export.luau", tmp / "export.luau")
    result = subprocess.run([str(Path(luau).resolve()), "export.luau"], cwd=tmp, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit("export failed:\n" + result.stdout[-2000:] + result.stderr)
    scenes = tmp / "scenes.jsonl"
    scenes.write_text(result.stdout)
    return scenes


def render(scenes: Path, three: Path, out: Path):
    site = scenes.parent / "site"
    site.mkdir()
    shutil.copy(HERE / "render.html", site / "render.html")
    shutil.copy(three, site / "three.module.min.js")
    subprocess.run(["node", str(HERE / "render.mjs"), str(scenes), str(out), str(site)], check=True)


def sheet(renders: Path, output: Path):
    labels = json.loads((renders / "labels.json").read_text())
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
    head = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    cell, cols, title = 200, 8, 46
    rows = []  # (group title, [names])
    for kind, group in GROUPS:
        names = [n for n in sorted(labels) if labels[n]["key"].split(":")[0] == kind]
        if rows and rows[-1][0] == group:
            rows[-1][1].extend(names)
        elif names:
            rows.append((group, names))
    height = sum(title + cell * ((len(names) + cols - 1) // cols) for _, names in rows) + 60
    img = Image.new("RGB", (cell * cols, height), (14, 16, 20))
    draw = ImageDraw.Draw(img)
    draw.text((16, 14), f"ZOMBIE DELIVERY 6.22 · EVERY THING HAS A LOOK · {len(labels)} models", fill=(242, 242, 240), font=head)
    y = 60
    for group, names in rows:
        draw.text((16, y + 12), group, fill=(215, 74, 70), font=font)
        y += title
        for i, name in enumerate(names):
            x, top = (i % cols) * cell, y + (i // cols) * cell
            picture = Image.open(renders / f"{name}.png").convert("RGB").resize((cell - 24, cell - 24))
            img.paste(picture, (x + 12, top + 2))
            info = labels[name]
            draw.text((x + 14, top + cell - 34), info["label"].upper()[:20], fill=(232, 234, 226), font=font)
            draw.text((x + 14, top + cell - 16), f"{info['key']} · {info['parts']} parts", fill=(150, 156, 166), font=small)
        y += cell * ((len(names) + cols - 1) // cols)
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output)
    print(f"Sheet: {len(labels)} models -> {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--keep", type=Path, help="also keep the single renders in this folder")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        scenes = export(args.luau, tmp)
        out = args.keep or (tmp / "renders")
        render(scenes, args.three.resolve(), out)
        sheet(out, args.output)
