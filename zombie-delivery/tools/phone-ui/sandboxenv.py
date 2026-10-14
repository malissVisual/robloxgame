"""8.0 SANDBOX: the folder tools/phone-ui/sandbox.luau runs in (check.py runs its checks there, sandbox_preview.py its
scenes): the real shared modules (shared/FurnitureLooks.luau loaded on the recorder for its catalogue), the real
client/SandboxHud.luau, client/WarehouseUi.luau, client/CardKit.luau, client/TouchLayout.luau and client/MoveLayout.luau
on sandbox_mock.luau's recorder (missions_mock.luau's), the Ui, Theme, Hud, Juice and ItemModel stand-ins, and a second
SandboxHud (SandboxHudAlone) that finds no client/Hud.luau (its own column and toasts). 8.1: client/UpgradeUi.luau and
tools/phone-ui/upgrades.luau (the UPGRADES desk's window) there too. 8.2: client/CollectionBookUi.luau and
tools/phone-ui/collectionbook.luau (the collection book) there too."""
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
    for name in ("SandboxHud", "WarehouseUi", "CardKit", "TouchLayout", "MoveLayout", "UpgradeUi", "CollectionBookUi"):  # (8.1: UpgradeUi; 8.2: CollectionBookUi)
        (dest / f"{name}.luau").write_text(PREFIX + local((ROOT / f"src/client/{name}.luau").read_text()))
    alone = PREFIX + local((ROOT / "src/client/SandboxHud.luau").read_text())
    assert 'require("./Hud")' in alone
    (dest / "SandboxHudAlone.luau").write_text(alone.replace('require("./Hud")', 'require("./NoHud")'))
    (dest / "NoHud.luau").write_text("return {}")
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Hud", "Hud"), ("Juice", "Juice"), ("ItemModel", "ItemModel")):
        (dest / f"{name}.luau").write_text(f'return require("./sandbox_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "sandbox_mock.luau", "sandbox.luau", "upgrades.luau", "collectionbook.luau"):
        (dest / name).write_bytes((HERE / name).read_bytes())
