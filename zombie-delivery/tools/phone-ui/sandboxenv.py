"""8.0 SANDBOX: the folder tools/phone-ui/sandbox.luau runs in (check.py runs its checks there, sandbox_preview.py its
scenes): the real shared modules (shared/FurnitureLooks.luau loaded on the recorder for its catalogue), the real
client/SandboxHud.luau, client/WarehouseUi.luau, client/CardKit.luau, client/TouchLayout.luau and client/MoveLayout.luau
on sandbox_mock.luau's recorder (missions_mock.luau's), the Ui, Theme, Hud and Juice stand-ins, and a second
SandboxHud (SandboxHudAlone) that finds no client/Hud.luau (its own column and toasts). 8.1: client/UpgradeUi.luau and
tools/phone-ui/upgrades.luau (the UPGRADES desk's window) there too. 8.2: client/CollectionBookUi.luau and
tools/phone-ui/collectionbook.luau (the collection book), client/SandboxTasksUi.luau and tools/phone-ui/sandboxtasks.luau
(the TASKS chip and panel), client/Sounds.luau the recorder's (what it plays). 8.3: client/PadGlyph.luau (the chips'
keys and the gamepad's D-pad) and client/SandboxHintsUi.luau (the first-time hints, on the recorder's clock M.now: a
check moves it, so they never come by themselves in the other checks) for real, client/CarryGripUi.luau and
client/MovingHud.luau stand-ins (M.gripActive: a grip check shows; M.moveCard: the move's card) for what covers the
screen, and tools/phone-ui/sandboxpad.luau (every device's way to the chips, the gamepad in the windows, the hints).
8.3: client/VanPaintUi.luau and tools/phone-ui/vanpaint.luau (the PAINT shop's window), its 3D picture
client/VanPaintPreview.luau a recorder (M.paintShows: what it was asked to show)."""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PREFIX = '''local mock = require("./sandbox_mock")
local game, workspace, task = mock.game, mock.workspace, mock.task
local Enum, Vector2, Vector3, UDim, UDim2 = mock.Enum, mock.Vector2, mock.Vector3, mock.UDim, mock.UDim2
local Color3, TweenInfo, typeof, warn = mock.Color3, mock.TweenInfo, mock.typeof, mock.warn
local Instance, CFrame, ColorSequence = mock.Instance, mock.CFrame, mock.ColorSequence
local NumberSequence, NumberSequenceKeypoint = mock.NumberSequence, mock.NumberSequenceKeypoint
'''
# (shared/FurnitureLooks.luau's catalogue needs Roblox's types where it loads: the recorder's, without sandbox_mock)
SHARED_PREFIX = PREFIX.replace('require("./sandbox_mock")', 'require("./missions_mock")')


def local(text: str) -> str:
    return re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)


def sandbox_env(dest: Path):
    for source in (ROOT / "src/shared").glob("*.luau"):
        (dest / source.name).write_text(local(source.read_text()))
    (dest / "FurnitureLooksReal.luau").write_text(SHARED_PREFIX + local((ROOT / "src/shared/FurnitureLooks.luau").read_text()))
    for name in ("FurnitureLooks", "ItemLooks", "Net"):
        (dest / f"{name}.luau").write_text(f'return require("./sandbox_mock").{name}')
    for name in ("SandboxHud", "WarehouseUi", "CardKit", "TouchLayout", "MoveLayout", "UpgradeUi", "CollectionBookUi", "SandboxTasksUi", "PadGlyph", "VanPaintUi"):  # (8.1: UpgradeUi; 8.2: CollectionBookUi, SandboxTasksUi; 8.3: PadGlyph, VanPaintUi)
        (dest / f"{name}.luau").write_text(PREFIX + local((ROOT / f"src/client/{name}.luau").read_text()))
    hints = local((ROOT / "src/client/SandboxHintsUi.luau").read_text())
    assert "os.clock()" in hints
    (dest / "SandboxHintsUi.luau").write_text(PREFIX + hints.replace("os.clock()", "mock.now"))  # (8.3: the recorder's clock)
    (dest / "CarryGripUi.luau").write_text('return require("./sandbox_mock").Grip')  # (8.3: a grip check, M.gripActive)
    # (8.3: the PAINT shop's 3D picture recorded: what it was asked to show, how often it was dropped)
    (dest / "VanPaintPreview.luau").write_text(
        'local M = require("./sandbox_mock")\nM.paintShows = {}\n'
        'return { show = function(holder, look) table.insert(M.paintShows, { holder = holder, look = look }) return true end,\n'
        '\trelease = function() M.paintReleased = (M.paintReleased or 0) + 1 end,\n'
        '\tclear = function() M.paintCleared = (M.paintCleared or 0) + 1 end }\n')
    (dest / "MovingHud.luau").write_text('return require("./sandbox_mock").MoveCards')  # (8.3: the move's cards, M.moveCard)
    alone = PREFIX + local((ROOT / "src/client/SandboxHud.luau").read_text())
    assert 'require("./Hud")' in alone
    (dest / "SandboxHudAlone.luau").write_text(alone.replace('require("./Hud")', 'require("./NoHud")'))
    (dest / "NoHud.luau").write_text("return {}")
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Hud", "Hud"), ("Juice", "Juice"), ("Sounds", "Sounds")):
        (dest / f"{name}.luau").write_text(f'return require("./sandbox_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "sandbox_mock.luau", "sandbox.luau", "upgrades.luau", "collectionbook.luau", "sandboxtasks.luau", "sandboxpad.luau", "vanpaint.luau"):
        (dest / name).write_bytes((HERE / name).read_bytes())
