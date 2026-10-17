#!/usr/bin/env python3
"""9.x loot: preview PNGs of the stars over a house's pieces and the loot toast as the real client/LootStars.luau builds
them (loot.luau's scenes on sandbox_mock.luau's recorder, its checks first): a phone held sideways (844 x 390: the
stars, then the toast of a Rare piece picked up) and a computer (1280 x 800), the BillboardGuis drawn where they stand
over their pieces (a stand-in camera; the pieces as boxes named in their tier's colour) under the HUD's column, beside
Roblox's touch controls; drawn by sandbox_preview.mjs in headless Chromium.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/phone-ui/loot_preview.py <luau> <out dir> [--fonts DIR]

--fonts: a folder with montserrat-500.woff2 / montserrat-700.woff2 (the Gotham stand-in). Chromium from CHROMIUM
(default /opt/pw-browsers/chromium). Not Roblox's renderer: the fonts are stand-ins, the world a flat backdrop.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from lootenv import loot_env  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("luau")
parser.add_argument("out")
parser.add_argument("--fonts", help="a folder with montserrat-500.woff2 and montserrat-700.woff2")
args = parser.parse_args()

with tempfile.TemporaryDirectory() as folder:
    dest = Path(folder)
    loot_env(dest)
    out = subprocess.run([args.luau, "loot.luau", "-a", "dump"], cwd=dest, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    scenes = json.loads(out.stdout.strip().splitlines()[-1])
    (dest / "scenes.json").write_text(json.dumps(scenes))
    command = ["node", str(HERE / "sandbox_preview.mjs"), str(dest / "scenes.json"), str(Path(args.out).resolve())]
    if args.fonts:
        command.append(str(Path(args.fonts).resolve()))
    subprocess.run(command, check=True)
    for scene in scenes:
        print(Path(args.out).resolve() / f"{scene['name']}.png")
