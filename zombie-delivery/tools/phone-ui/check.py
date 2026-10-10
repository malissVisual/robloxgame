#!/usr/bin/env python3
"""Execute actual Phone/PhoneContract/PhoneRoute/PhonePopup/OrdersUi (6.12: TasksApp) against a narrow UI instance recorder.
This checks callbacks, construction, current server data, resizing and cleanup, not Studio layout or fonts.
6.8: then the MISSIONS window (MissionsUi, MissionsLayout, Portrait; 6.12.13: MissionArtUi) the same way (missions.luau).
6.14: ReadyCheck (NEXT MISSION, the READY CHECK), Gps and SavingsLine (the HUD's savings line) run for real too.
6.18 wave 2: ShopView (the kit's list screens) and BagUi (BAG & ITEMS) run for real too.
6.18 wave 2: PhoneMore (CAREER, BANK, MESSAGES, SETTINGS in the UI kit) runs for real; the MISSIONS window with CardKit.
6.21: the bottom bar (Hotbar) runs for real too (hotbar.luau: a computer's bar and a touch screen's).
6.22: ItemModel (every thing's 3D model in a ViewportFrame) runs for real in both, over a recorded shared/ItemLooks
(mock.luau's ItemLooks: a model a key, a key that fails to build to see the icon come back).
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
local NumberSequence, NumberSequenceKeypoint = mock.NumberSequence, mock.NumberSequenceKeypoint
local CFrame = mock.CFrame
'''
    # 6.22: the looks' builders are Roblox's (tests/itemlooks_test.luau builds them): the recorder's stand-in here
    (dest / "ItemLooks.luau").write_text('return require("./mock").ItemLooks')
    for name in ("Phone", "PhoneContract", "PhoneLayout", "PhoneRoute", "PhoneApps", "PhoneMotion", "PhonePopup", "OrdersUi", "TasksApp", "StyleApp", "JobThumbUi", "JobsView", "CardKit", "PhoneHome", "RegularsApp", "SpecialOrderUi", "ReadyCheck", "Gps", "SavingsLine", "ShopView", "BagUi", "PhoneMore", "SkillsView", "ItemModel"):
        text = (ROOT / f"src/client/{name}.luau").read_text()
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
        (dest / f"{name}.luau").write_text(prefix + text)
    for name in ("Ui", "Theme", "Net", "MapView", "KitShop", "CareerUi", "Sounds", "Discovery", "Hotbar", "StylePreview"):
        (dest / f"{name}.luau").write_text(f'return require("./mock").{name}')
    (dest / "HudContract.luau").write_text('return require("./mock").P')
    (dest / "Holster.luau").write_text('return require("./mock").Holster')  # 6.21: what is in your hand
    # 6.21: the bottom bar (client/Hotbar.luau) for real, twice: a computer's (HotbarLive) and a touch screen's
    # (HotbarTouch: it reads Ui.touchLayout when it loads); hotbar.luau drives them. The phone checks keep mock.Hotbar.
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', (ROOT / "src/client/Hotbar.luau").read_text())
    for name in ("HotbarLive", "HotbarTouch"):
        (dest / f"{name}.luau").write_text(prefix + text)
    for name in ("mock.luau", "check.luau", "hotbar.luau"):
        (dest / name).write_bytes((Path(__file__).parent / name).read_bytes())
    subprocess.run([args.luau, "check.luau"], cwd=dest, check=True)
    subprocess.run([args.luau, "hotbar.luau"], cwd=dest, check=True)

# 6.8: the MISSIONS window (client/MissionsUi.luau with client/MissionsLayout.luau and client/Portrait.luau, the real
# shared data) against missions_mock.luau's fuller stand-ins: the clients, the chapter, START, the locks, a replay,
# a phone's narrow layout, the banner, the cleared card (tools/phone-ui/missions.luau); 6.12.13: the chapter's picture
# banner (client/MissionArtUi.luau with client/JobThumbUi.luau's keepRatio).
with tempfile.TemporaryDirectory() as folder:
    dest = Path(folder)
    for source in (ROOT / "src/shared").glob("*.luau"):
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
        (dest / source.name).write_text(text)
    prefix = '''local mock = require("./missions_mock")
local game, workspace, task = mock.game, mock.workspace, mock.task
local Enum, Vector2, Vector3, UDim, UDim2 = mock.Enum, mock.Vector2, mock.Vector3, mock.UDim, mock.UDim2
local Color3, TweenInfo, typeof, warn = mock.Color3, mock.TweenInfo, mock.typeof, mock.warn
local Instance, CFrame, ColorSequence = mock.Instance, mock.CFrame, mock.ColorSequence
local NumberSequence, NumberSequenceKeypoint = mock.NumberSequence, mock.NumberSequenceKeypoint
'''
    for name in ("MissionsUi", "MissionsLayout", "Portrait", "MissionArtUi", "JobThumbUi", "CardKit"):
        text = (ROOT / f"src/client/{name}.luau").read_text()
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
        (dest / f"{name}.luau").write_text(prefix + text)
    (dest / "ItemModel.luau").write_text("return { view = function() return nil end, has = function() return false end }")  # 6.22
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Hud", "MHud"), ("CrewPanel", "MCrewPanel"), ("DialogKeys", "MDialogKeys"), ("Net", "Net")):
        (dest / f"{name}.luau").write_text(f'return require("./missions_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "missions.luau"):
        (dest / name).write_bytes((Path(__file__).parent / name).read_bytes())
    subprocess.run([args.luau, "missions.luau"], cwd=dest, check=True)
