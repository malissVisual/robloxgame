#!/usr/bin/env python3
"""8.0 SANDBOX: preview PNGs of the sandbox's HUD and the warehouse picker as the real client/SandboxHud.luau and
client/WarehouseUi.luau build them (sandbox.luau's scenes on sandbox_mock.luau's recorder, its checks first): on a
phone held sideways (844 x 390, the touch controls drawn), a computer (1280 x 800) and a big screen (1920 x 1080):
the HUD with toasts, THE PICKER, the SELL question, the STOCK list; drawn by sandbox_preview.mjs in headless Chromium.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/phone-ui/sandbox_preview.py <luau> <out dir> [--fonts DIR]

--fonts: a folder with montserrat-500.woff2 / montserrat-700.woff2 (the Gotham stand-in). Chromium from CHROMIUM
(default /opt/pw-browsers/chromium). Not Roblox's renderer: the fonts are stand-ins and a 3D picture is drawn as its emoji.
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
from sandboxenv import sandbox_env  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("luau")
parser.add_argument("out")
parser.add_argument("--fonts", help="a folder with montserrat-500.woff2 and montserrat-700.woff2")
parser.add_argument("--scenes", default="sandbox.luau", help="the scene script (8.1: upgrades.luau, the UPGRADES window)")
args = parser.parse_args()

with tempfile.TemporaryDirectory() as folder:
    dest = Path(folder)
    sandbox_env(dest)
    out = subprocess.run([args.luau, args.scenes, "-a", "dump"], cwd=dest, capture_output=True, text=True)
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
