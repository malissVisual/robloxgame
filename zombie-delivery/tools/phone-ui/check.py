#!/usr/bin/env python3
"""Execute actual Phone/PhoneContract/PhoneRoute/OrdersUi against a narrow UI instance recorder.
This checks callbacks, construction, current server data, resizing and cleanup, not Studio layout or fonts.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("luau")
args = parser.parse_args()
with tempfile.TemporaryDirectory() as folder:
    dest = Path(folder)
    for source in (ROOT / "src/shared").glob("*.luau"):
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
        (dest / source.name).write_text(text)
    prefix = '''local mock = require("./mock")
local game, workspace, task = mock.game, mock.workspace, mock.task
local Enum, Vector2, Vector3, UDim, UDim2 = mock.Enum, mock.Vector2, mock.Vector3, mock.UDim, mock.UDim2
local Color3, TweenInfo, typeof, warn = mock.Color3, mock.TweenInfo, mock.typeof, mock.warn
'''
    for name in ("Phone", "PhoneContract", "PhoneLayout", "PhoneRoute", "OrdersUi"):
        text = (ROOT / f"src/client/{name}.luau").read_text()
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
        (dest / f"{name}.luau").write_text(prefix + text)
    for name in ("Ui", "Theme", "Net", "MapView", "KitShop", "CareerUi", "BagUi", "Sounds", "Discovery"):
        (dest / f"{name}.luau").write_text(f'return require("./mock").{name}')
    (dest / "HudContract.luau").write_text('return require("./mock").P')
    for name in ("mock.luau", "check.luau"):
        (dest / name).write_bytes((Path(__file__).parent / name).read_bytes())
    subprocess.run([args.luau, "check.luau"], cwd=dest, check=True)
