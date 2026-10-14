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
7.0: the moves' story (MoveStoryUi) with its hooks in the real MovingHud (movestory.luau, on missions_mock.luau).
7.0 review: the move's screen at 844 x 390 (MovingHud, MoveHelperHud, QuickChat, MoveLobbyUi: movehud.luau): nothing on
the touch buttons or on each other, a finger's sizes, the list a sheet, the keys, ESC, the GPS, a resize.
7.2: the maps' alpine look (the real MapView with MapStyle and AlpineLayout: mapview.luau on mapmock.luau): built once,
within Config.MapStyle.Budget, everything there in its order, nothing made frame after frame.
8.0 SANDBOX: the sandbox's HUD and the warehouse picker (the real SandboxHud and WarehouseUi: sandbox.luau on
sandbox_mock.luau) at 844 x 390, 1280 x 800 and 1920 x 1080: the money, the stock chip, the toasts, the picker on
"pick", DISPLAY / SELL / TAKE DOWN's requests, the 3D pictures capped, clear of the touch controls, texts that fit.
8.2: the STOCK list's bulk buttons (FILL BEST, the SELL… menu, TAKE ALL DOWN), the sort toggle, the search box and the
picker's too-big pieces at a small upgrade stand, on the same screens.
8.1 grip: the carry's timing check (the real CarryGripUi: carrygrip.luau, the folder from carrygripenv.py) at 844 x 390,
740 x 360, 1024 x 768 and 1280 x 800: the widget and the GRIP button clear of everything, one press, the outcomes.
8.1 SANDBOX: the UPGRADES desk's window (the real UpgradeUi: upgrades.luau on sandbox_mock.luau) on the same screens:
the cards, BUY's request, NEED without the money, MAX, the money from the State, closing, a phone's finger sizes.
8.2 SANDBOX: the collection book (the real CollectionBookUi and SandboxHud's 📖 BOOK chip: collectionbook.luau on
sandbox_mock.luau) on the same screens: the chip, the progress and the milestones, the tabs, found and unknown cards,
the 3D pictures capped (the silhouettes tinted), the toasts, C, closing, a phone's finger sizes.
8.2 SANDBOX: the daily tasks' TASKS chip and panel (the real SandboxTasksUi beside the real SandboxHud: sandboxtasks.luau
on sandbox_mock.luau) at 844 x 390, 1280 x 800 (the chat shut and open) and 1920 x 1080: the chip under the money, the
panel's rows, CLAIM's request, the toasts, closing, the texts fitting, a phone's finger sizes, clear of the controls.
8.3 SANDBOX: every device's way to the chips (the keys, the gamepad's D-pad glyphs and routes), the gamepad in every
sandbox window, the notices in the device's words and the first-time hints (sandboxpad.luau on sandbox_mock.luau).
8.5 SANDBOX: Danny's clipboard, orders mode (the real DannyOrders beside Danny's card and status line: dannyorders.luau):
the line at the bottom and the touch 📋 button at 844 x 390, 667 x 375, 1280 x 800 and 1920 x 1080, the keys, the outline.
8.3 SANDBOX: a showroom visitor's offer card (the real OfferCard: offercard.luau on sandbox_mock.luau) at 844 x 390,
1280 x 800 and 1920 x 1080: its words, clear of the chips and the touch controls, ACCEPT / DECLINE's requests (the id
only), the gamepad's selection on DECLINE and B, waiting under another window, the clock running out. 8.3 review:
another window opening only hides it (the offer waits); smaller phones (667 x 375, 740 x 360, 780 x 360).
8.3 keys: the sandbox's key hints on every device (the real KeyHints with SandboxPad's actions and PadGlyph's glyphs:
keyhints.luau, the folder from keyhintsenv.py); the grip check's words and R2's glyph (carrygrip.luau) and the guide's
words and the gamepad's B held (sandboxguide.luau) on a phone, a computer and a gamepad. 8.4: the guide's steps for
Danny for hire (hire him, give him a piece, a heavy piece's Lift) in the same scene.
8.3 SANDBOX: the PAINT shop's window (the real VanPaintUi: vanpaint.luau on sandbox_mock.luau) at 844 x 390, 1280 x 800
and 1920 x 1080: the swatches, the picture's looks, BUY / NEED / LOCKED / WEAR, the tabs, the money, closing, the gamepad.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys
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

# 7.0, the moves' story: the real client/MovingHud.luau with client/MoveStoryUi.luau (client/Portrait.luau,
# client/CardKit.luau, the real shared data) on missions_mock.luau's recorder (tools/phone-ui/movestory.luau adds the
# few stand-ins MovingHud needs): Marge's intro the first time, the contract card's CHAPTERS, START through the
# briefing, the client's thanks on the result card, the story card on a phone.
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
    for name in ("MovingHud", "MoveStoryUi", "Portrait", "CardKit", "TouchLayout", "MoveLayout", "TopBlocks", "PadGlyph"):  # (8.3 keys: PadGlyph)
        text = (ROOT / f"src/client/{name}.luau").read_text()
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
        (dest / f"{name}.luau").write_text(prefix + text)
    (dest / "ItemModel.luau").write_text("return { view = function() return nil end, has = function() return false end }")
    (dest / "EnemyOutline.luau").write_text("return { setXray = function() end }")  # 7.0 planning: the Guard's sight (MovingHud)
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Net", "Net"), ("MapView", "MapView"), ("Sounds", "Sounds"), ("DialogKeys", "MKeys"), ("Fade", "MFade")):
        (dest / f"{name}.luau").write_text(f'return require("./missions_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "movestory.luau"):
        (dest / name).write_bytes((Path(__file__).parent / name).read_bytes())
    subprocess.run([args.luau, "movestory.luau"], cwd=dest, check=True)

# 7.0 review: the move's screen on a phone held sideways (844 x 390) and a computer: the real client/MovingHud.luau,
# client/MoveHelperHud.luau, client/QuickChat.luau and client/MoveLobbyUi.luau (client/MoveLayout.luau, client/TopBlocks.luau,
# client/TouchLayout.luau, client/CardKit.luau, client/MoveStoryUi.luau, client/Portrait.luau) on missions_mock.luau's
# recorder; movehud.luau lays out what they made and checks that nothing lies on the touch buttons or on each other.
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
    for name in ("MovingHud", "MoveHelperHud", "QuickChat", "MoveLobbyUi", "MoveStoryUi", "Portrait", "CardKit", "TouchLayout", "MoveLayout", "TopBlocks", "PadGlyph"):  # (8.3 keys: PadGlyph)
        text = (ROOT / f"src/client/{name}.luau").read_text()
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
        (dest / f"{name}.luau").write_text(prefix + text)
    (dest / "ItemModel.luau").write_text("return { view = function() return nil end, has = function() return false end }")
    (dest / "EnemyOutline.luau").write_text("return { setXray = function() end }")
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Net", "Net"), ("MapView", "MapView"), ("Sounds", "Sounds"), ("DialogKeys", "MKeys"), ("Fade", "MFade")):
        (dest / f"{name}.luau").write_text(f'return require("./missions_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "movehud.luau"):
        (dest / name).write_bytes((Path(__file__).parent / name).read_bytes())
    subprocess.run([args.luau, "movehud.luau"], cwd=dest, check=True)

# 8.1 grip: the carry's timing check (client/CarryGripUi.luau with shared/CarryGrip.luau) on a phone held sideways
# (844 x 390), two more touch screens (740 x 360, a 1024 x 768 tablet) and a computer (1280 x 800), beside the move's
# panel, Danny's strip, the sandbox's guide line, the quick chat's button and the HUD's groups where client/Hud.luau puts
# them (tools/phone-ui/carrygrip.luau): the widget and the round GRIP button (80 px and more) clear of the touch buttons
# and everything else, the lift check and the wobble (their words, the needle, the zone), one press (the GRIP button,
# the widget, the left mouse button, F) sent once with its time, no press: a miss at the window's end, the server's
# outcomes (BALANCED!, SLIPPED BACK!, STAGGER!, DROPPED! with the real client/MoveSounds.luau's grip_slip and no second
# thud), a close, a door's fade, a stale outcome ignored, the tutorial's longer hint, no warnings
# (tools/phone-ui/carrygripenv.py builds the folder; carrygrip_preview.py draws the same scenes).
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from carrygripenv import carrygrip_env  # noqa: E402

with tempfile.TemporaryDirectory() as folder:
    carrygrip_env(Path(folder))
    subprocess.run([args.luau, "carrygrip.luau"], cwd=folder, check=True)

# 8.0 SANDBOX: the admin panel (client/AdminPanel.luau, its SANDBOX tab with shared/SandboxAdmin.luau;
# client/SandboxZones.luau recorded) on missions_mock.luau's recorder (tools/phone-ui/adminpanel.luau): the tab only in
# the sandbox world (first, and open by default there), every button's ("sandbox", id, target), SHOW ZONES on this
# screen only, the window and the buttons on a phone held sideways (844 x 390), no panel for a player who is no admin.
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
'''
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', (ROOT / "src/client/AdminPanel.luau").read_text())
    for name in ("AdminPanelOn", "AdminPanelOff", "AdminPanelGuest"):  # (three loads: Config.Sandbox.On is read as it loads)
        (dest / f"{name}.luau").write_text(prefix + text)
    (dest / "SandboxZones.luau").write_text('return require("./missions_mock").MZones')
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Net", "Net")):
        (dest / f"{name}.luau").write_text(f'return require("./missions_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "adminpanel.luau"):
        (dest / name).write_bytes((Path(__file__).parent / name).read_bytes())
    subprocess.run([args.luau, "adminpanel.luau"], cwd=dest, check=True)


# 7.2, the Alps on the maps: the real client/MapView.luau (shared/MapStyle.luau, AlpineLayout, Map, Roads, Explore and
# the rest of the real shared data) on mapmock.luau's recorder (missions_mock.luau's, the services, the camera, your
# character, Discovery's grid, DeviceBudget): tools/phone-ui/mapview.luau checks the paper map and the Alps (built once,
# within Config.MapStyle.Budget, everything there and in its order) and that the frame loop leaves them alone.
# (mapenv.py builds the folder; mapview_preview.py draws the same map's scenes.)
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mapenv import map_env  # noqa: E402

with tempfile.TemporaryDirectory() as folder:
    map_env(Path(folder))
    subprocess.run([args.luau, "mapview.luau"], cwd=folder, check=True)

# 8.0 SANDBOX, the guide: client/SandboxGuide.luau (shared/SandboxSteps.luau, SandboxMap) beside the real
# client/MovingHud.luau and client/MoveHelperHud.luau (TopBlocks, MoveLayout, TouchLayout) on missions_mock.luau's
# recorder: tools/phone-ui/sandboxguide.luau checks the hint line at 844 x 390 and on a computer (clear of the money at
# the top left, the move's panel, Danny's strip, Roblox's player list and the touch buttons; its ✕ and the 💡 chip a
# finger's size), every step's words and 3D target, the quiet steps, the ✕ and a held G, and nothing made loop after loop.
# (shared/WarehouseLayout.luau is the warehouse's: a stand-in the scene gives through Shared:FindFirstChild.)
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
    # (a module found at run time, shared/WarehouseLayout.luau: the stand-in's table)
    found = '''local __require = require
local function require(module) if type(module) == "table" and module.fakeModule ~= nil then return module.fakeModule end return __require(module) end
'''
    for name in ("SandboxGuide", "MovingHud", "MoveHelperHud", "MoveStoryUi", "Portrait", "CardKit", "TouchLayout", "MoveLayout", "TopBlocks", "PadGlyph"):  # (8.3 keys: PadGlyph)
        text = (ROOT / f"src/client/{name}.luau").read_text()
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
        (dest / f"{name}.luau").write_text(prefix + (found if name == "SandboxGuide" else "") + text)
    (dest / "ItemModel.luau").write_text("return { view = function() return nil end, has = function() return false end }")
    (dest / "EnemyOutline.luau").write_text("return { setXray = function() end }")
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Net", "Net"), ("MapView", "MapView"), ("Sounds", "Sounds"), ("DialogKeys", "MKeys"), ("Fade", "MFade")):
        (dest / f"{name}.luau").write_text(f'return require("./missions_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "sandboxguide.luau"):
        (dest / name).write_bytes((Path(__file__).parent / name).read_bytes())
    subprocess.run([args.luau, "sandboxguide.luau"], cwd=dest, check=True)
# 8.0 SANDBOX: the sandbox's HUD (client/SandboxHud.luau) and the warehouse picker (client/WarehouseUi.luau, with
# client/CardKit.luau, TouchLayout, MoveLayout and the real shared data; shared/FurnitureLooks.luau's catalogue loaded on
# the recorder) on sandbox_mock.luau's recorder (missions_mock.luau's, a layout, Hud's left column, the furniture's
# recorded models): tools/phone-ui/sandbox.luau on a phone (844 x 390), a computer (1280 x 800) and 1920 x 1080.
# 8.2: the STOCK list's FILL BEST / SELL… (its menu, asked first) / TAKE ALL DOWN, the sort toggle, the search box (a
# computer) and THE PICKER's "Too big for this stand" at a small upgrade stand, on the same screens.
# (sandboxenv.py builds the folder; sandbox_preview.py draws the same scenes.)
from sandboxenv import sandbox_env  # noqa: E402

with tempfile.TemporaryDirectory() as folder:
    sandbox_env(Path(folder))
    subprocess.run([args.luau, "sandbox.luau"], cwd=folder, check=True)
# 8.1 SANDBOX: the UPGRADES desk's window (client/UpgradeUi.luau, shared/UpgradeRules.luau) in the same folder:
# tools/phone-ui/upgrades.luau on a phone (844 x 390), a computer (1280 x 800) and 1920 x 1080.
with tempfile.TemporaryDirectory() as folder:
    sandbox_env(Path(folder))
    subprocess.run([args.luau, "upgrades.luau"], cwd=folder, check=True)
# 8.2 SANDBOX: the collection book (client/CollectionBookUi.luau, shared/CollectionBookRules.luau) and its 📖 BOOK chip
# in client/SandboxHud.luau, in the same folder: tools/phone-ui/collectionbook.luau on a phone (844 x 390, 667 x 375),
# a tablet (1024 x 768), a computer (1280 x 800) and 1920 x 1080.
with tempfile.TemporaryDirectory() as folder:
    sandbox_env(Path(folder))
    subprocess.run([args.luau, "collectionbook.luau"], cwd=folder, check=True)
# 8.2 SANDBOX: the daily tasks' TASKS chip and panel (client/SandboxTasksUi.luau beside client/SandboxHud.luau,
# shared/SandboxTasks.luau's views) in the same folder: tools/phone-ui/sandboxtasks.luau on a phone (844 x 390), a
# computer (1280 x 800, the chat shut and open) and 1920 x 1080.
with tempfile.TemporaryDirectory() as folder:
    sandbox_env(Path(folder))
    subprocess.run([args.luau, "sandboxtasks.luau"], cwd=folder, check=True)
# 8.3 SANDBOX: every device's way to the HUD's chips (client/PadGlyph.luau, shared/SandboxPad.luau: the keys, the
# gamepad's D-pad glyphs and routes, nothing on a phone), the gamepad in every sandbox window (the selection landing,
# kept inside, kept over a redraw, the book's cards and a maxed upgrade reachable, B), the notices in the device's words
# and the first-time hints (client/SandboxHintsUi.luau, shared/SandboxHints.luau) in the same folder:
# tools/phone-ui/sandboxpad.luau on a computer (1280 x 800) and a phone (844 x 390).
with tempfile.TemporaryDirectory() as folder:
    sandbox_env(Path(folder))
    subprocess.run([args.luau, "sandboxpad.luau"], cwd=folder, check=True)
# 8.3 SANDBOX: the PAINT shop's window (client/VanPaintUi.luau, shared/VanPaintRules.luau; its 3D picture recorded) in the
# same folder: tools/phone-ui/vanpaint.luau on a phone (844 x 390), a computer (1280 x 800) and 1920 x 1080.
with tempfile.TemporaryDirectory() as folder:
    sandbox_env(Path(folder))
    subprocess.run([args.luau, "vanpaint.luau"], cwd=folder, check=True)
# 8.3 Danny for hire: his card (client/MoveHelperCard.luau: HIRE, CLEAR QUEUE, the clicks and taps on him and on the
# pieces, the gamepad's prompts) and his status line (client/MoveHelperHud.luau with the card), beside the real
# SandboxHud and SandboxTasksUi, a stand-in move's panel and Hud's groups: tools/phone-ui/dannycard.luau on a phone
# (844 x 390), a computer (1280 x 800) and 1920 x 1080 (dannycardenv.py builds the folder; dannycard_preview.py draws
# the same scenes). 8.3 review: a tap beside the card is no tap in the world, the gamepad on it, its reach, the line's
# words on every device, smaller phones (667 x 375, 740 x 360, 780 x 360).
from dannycardenv import dannycard_env  # noqa: E402

with tempfile.TemporaryDirectory() as folder:
    dannycard_env(Path(folder))
    subprocess.run([args.luau, "dannycard.luau"], cwd=folder, check=True)
# 8.5 Danny's clipboard, orders mode (client/DannyOrders.luau: its line at the bottom, the touch 📋 button, the piece
# pointed at; Q, R1 / B, the status line's 📋 ORDERS) in the same folder: tools/phone-ui/dannyorders.luau at 844 x 390,
# 667 x 375, 1280 x 800 and 1920 x 1080, clear of the HUD's chips, the touch controls, the move's panel and Danny's strip.
with tempfile.TemporaryDirectory() as folder:
    dannycard_env(Path(folder))
    subprocess.run([args.luau, "dannyorders.luau"], cwd=folder, check=True)
# 8.3 the showroom's visitors: a visitor's offer card (client/OfferCard.luau) beside the real SandboxHud and
# SandboxTasksUi, a stand-in move's panel and Hud's groups: tools/phone-ui/offercard.luau on a phone (844 x 390), a
# computer (1280 x 800) and 1920 x 1080 (offercardenv.py builds the folder; offercard_preview.py draws the same scenes).
# 8.3 review: another window opening only hides it; smaller phones (667 x 375, 740 x 360, 780 x 360).
from offercardenv import offercard_env  # noqa: E402

with tempfile.TemporaryDirectory() as folder:
    offercard_env(Path(folder))
    subprocess.run([args.luau, "offercard.luau"], cwd=folder, check=True)
# 8.3 keys: the key hints (client/KeyHints.luau with shared/SandboxPad.luau's actions and client/PadGlyph.luau) in
# sandboxenv.py's folder (keyhintsenv.py: the real KeyHints, its HudContract, Holster and Drive stand-ins):
# tools/phone-ui/keyhints.luau on a computer (1280 x 800) with its keys and with a gamepad (the platform's glyphs, at
# once when it is picked up or put down), a console, a phone (none) and a phone with a gamepad; the city's strip as before.
from keyhintsenv import keyhints_env  # noqa: E402

with tempfile.TemporaryDirectory() as folder:
    keyhints_env(Path(folder))
    subprocess.run([args.luau, "keyhints.luau"], cwd=folder, check=True)
