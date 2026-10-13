#!/usr/bin/env python3
"""7.2: a preview sheet of the maps' alpine look, as the real client/MapView.luau builds it (mapview.luau's scenes on
mapmock.luau's recorder, its checks first): the big map open and the minimap on a computer (1280 x 800) and on a
phone held sideways (844 x 390), the minimap at the West Pass, in town, in the north and in the south; drawn by
mapview_preview.mjs in headless Chromium and laid out with PIL (the minimaps also enlarged).

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/phone-ui/mapview_preview.py <luau> <sheet.png> [--font montserrat.woff2]

Chromium from CHROMIUM (default /opt/pw-browsers/chromium). Not Roblox's renderer: fonts and TextScaled are stand-ins.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from mapenv import map_env  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("luau")
parser.add_argument("sheet")
parser.add_argument("--font", help="a woff2 for the GothamBold / GothamBlack stand-in (e.g. Montserrat)")
args = parser.parse_args()

with tempfile.TemporaryDirectory() as folder:
    dest = Path(folder)
    map_env(dest)
    out = subprocess.run([args.luau, "mapview.luau", "-a", "dump"], cwd=dest, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    scenes = json.loads(out.stdout.strip().splitlines()[-1])
    (dest / "scenes.json").write_text(json.dumps(scenes))
    shots = dest / "shots"
    command = ["node", str(HERE / "mapview_preview.mjs"), str(dest / "scenes.json"), str(shots)]
    if args.font:
        command.append(args.font)
    subprocess.run(command, check=True)
    images = {scene["name"]: Image.open(shots / f"{scene['name']}.png").convert("RGB") for scene in scenes}

    # The minimap's box on each screen (Hud's left stack, mapview.luau's scene()): 200 x 150 under the turn line.
    def minimap(name: str, touch: bool):
        image = images[name]
        x, y = (12, 64) if touch else (16, image.height - 330)
        return image.crop((x - 6, y - 6, x + 206, y + 180)).resize((424, 372), Image.LANCZOS)

    gap = 16
    rows = [
        [images["computer-big"].resize((960, 600), Image.LANCZOS), images["computer-mini-pass"].resize((960, 600), Image.LANCZOS)],
        [images["phone-big"], images["phone-mini-town"]],
        [minimap("computer-mini-pass", False), minimap("phone-mini-town", True), minimap("mini-north", True), minimap("mini-south", True)],
    ]
    labels = [
        ["1280 x 800: the big map (M)", "1280 x 800: the minimap at the West Pass"],
        ["844 x 390: the big map", "844 x 390: the minimap in town"],
        ["the minimap at the West Pass (x2)", "in town: the Hauptplatz (x2)", "the north-west's winter peaks (x2)", "the south-east: the sea, the peaks (x2)"],
    ]
    width = max(sum(i.width for i in row) + gap * (len(row) + 1) for row in rows)
    height = sum(max(i.height for i in row) + 28 for row in rows) + gap * (len(rows) + 1)
    sheet = Image.new("RGB", (width, height), (24, 26, 30))
    draw = ImageDraw.Draw(sheet)
    y = gap
    for row, names in zip(rows, labels):
        x = gap
        for image, label in zip(row, names):
            draw.text((x, y), label, fill=(230, 230, 226))
            sheet.paste(image, (x, y + 20))
            x += image.width + gap
        y += max(i.height for i in row) + 28 + gap
    sheet.save(args.sheet)
    print("wrote", args.sheet, sheet.size)
