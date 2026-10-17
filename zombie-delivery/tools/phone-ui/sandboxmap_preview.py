#!/usr/bin/env python3
"""10.x the map: preview PNGs of the big map and a run's minimap as the real client/SandboxMapUi.luau,
client/SandboxMiniMap.luau and client/SandboxMapDraw.luau build them (sandboxmap.luau's scenes on sandbox_mock.luau's
recorder, its checks first): the lobby's map and a run's (the farmstead's real plan: plans.luau, sandboxmapenv.py) on
phones held sideways (844 x 390, 667 x 375), a computer (1280 x 800) and a big screen (1920 x 1080), and the minimap in a
run on each; drawn by sandbox_preview.mjs in headless Chromium.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/phone-ui/sandboxmap_preview.py <luau> <out dir> [--fonts DIR] [--only NAME ...]

--fonts: a folder with montserrat-500.woff2 / montserrat-700.woff2 (the Gotham stand-in). --only: the scenes to draw
(their names: map-lobby-1280x800, map-run-844x390, minimap-run-844x390 …; default all). Chromium from CHROMIUM (default
/opt/pw-browsers/chromium). Not Roblox's renderer: the fonts are stand-ins, the world behind a flat backdrop.
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
from sandboxmapenv import sandboxmap_env  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("luau")
parser.add_argument("out")
parser.add_argument("--fonts", help="a folder with montserrat-500.woff2 and montserrat-700.woff2")
parser.add_argument("--only", nargs="*", help="the scenes to draw (default: all)")
args = parser.parse_args()

with tempfile.TemporaryDirectory() as folder:
    dest = Path(folder)
    sandboxmap_env(dest, args.luau)
    out = subprocess.run([args.luau, "sandboxmap.luau", "-a", "dump"], cwd=dest, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    scenes = json.loads(out.stdout.strip().splitlines()[-1])
    if args.only:
        scenes = [s for s in scenes if s["name"] in args.only]
    (dest / "scenes.json").write_text(json.dumps(scenes))
    command = ["node", str(HERE / "sandbox_preview.mjs"), str(dest / "scenes.json"), str(Path(args.out).resolve())]
    if args.fonts:
        command.append(str(Path(args.fonts).resolve()))
    subprocess.run(command, check=True)
    for scene in scenes:
        print(Path(args.out).resolve() / f"{scene['name']}.png")
