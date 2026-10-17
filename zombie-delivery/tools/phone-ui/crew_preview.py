#!/usr/bin/env python3
"""10.1 the helpers' crew: preview PNGs of the CREW window and the down ring as the real client/CrewUi.luau builds them
(crew.luau's scenes on sandbox_mock.luau's recorder, its checks first): the window on a phone held sideways (844 x 390,
the touch controls drawn) and a computer (1280 x 800), the window with your pick in hospital, and the ring over a
helper down in a run (its BillboardGui drawn where his body lies); drawn by sandbox_preview.mjs in headless Chromium.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/phone-ui/crew_preview.py <luau> <out dir> [--fonts DIR]

--fonts: a folder with montserrat-500.woff2 / montserrat-700.woff2 (the Gotham stand-in). Chromium from CHROMIUM
(default /opt/pw-browsers/chromium). Not Roblox's renderer: the fonts are stand-ins.
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
from crewenv import crew_env  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("luau")
parser.add_argument("out")
parser.add_argument("--fonts", help="a folder with montserrat-500.woff2 and montserrat-700.woff2")
args = parser.parse_args()

with tempfile.TemporaryDirectory() as folder:
    dest = Path(folder)
    crew_env(dest)
    out = subprocess.run([args.luau, "crew.luau", "-a", "dump"], cwd=dest, capture_output=True, text=True)
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
