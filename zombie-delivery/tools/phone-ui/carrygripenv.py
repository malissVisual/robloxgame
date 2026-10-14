"""8.1 grip: the folder tools/phone-ui/carrygrip.luau runs in (check.py runs its checks there, carrygrip_preview.py its
scenes): the real shared modules, the real client/CarryGripUi.luau with client/MoveSounds.luau, client/MovingHud.luau,
client/MoveHelperHud.luau, client/QuickChat.luau (client/MoveStoryUi.luau, client/Portrait.luau, client/CardKit.luau,
client/TouchLayout.luau, client/MoveLayout.luau, client/TopBlocks.luau; 8.3 keys: client/PadGlyph.luau) on missions_mock.luau's recorder, the Ui, Theme,
Net, MapView, Sounds, DialogKeys and Fade stand-ins. CarryGripUi's and MoveSounds' os.clock is the check's own clock
(mock.os: carrygrip.luau's M.clock, moved on by its frames), so every timing is the same each run."""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PREFIX = '''local mock = require("./missions_mock")
local game, workspace, task = mock.game, mock.workspace, mock.task
local Enum, Vector2, Vector3, UDim, UDim2 = mock.Enum, mock.Vector2, mock.Vector3, mock.UDim, mock.UDim2
local Color3, TweenInfo, typeof, warn = mock.Color3, mock.TweenInfo, mock.typeof, mock.warn
local Instance, CFrame, ColorSequence = mock.Instance, mock.CFrame, mock.ColorSequence
local NumberSequence, NumberSequenceKeypoint = mock.NumberSequence, mock.NumberSequenceKeypoint
'''


def local(text: str) -> str:
    return re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)


def carrygrip_env(dest: Path):
    for source in (ROOT / "src/shared").glob("*.luau"):
        (dest / source.name).write_text(local(source.read_text()))
    for name in ("CarryGripUi", "MoveSounds", "MovingHud", "MoveHelperHud", "QuickChat", "MoveStoryUi", "Portrait", "CardKit", "TouchLayout", "MoveLayout", "TopBlocks", "PadGlyph"):  # (8.3 keys: PadGlyph)
        clock = "local os = mock.os or os\n" if name in ("CarryGripUi", "MoveSounds") else ""
        (dest / f"{name}.luau").write_text(PREFIX + clock + local((ROOT / f"src/client/{name}.luau").read_text()))
    (dest / "ItemModel.luau").write_text("return { view = function() return nil end, has = function() return false end }")
    (dest / "EnemyOutline.luau").write_text("return { setXray = function() end }")
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Net", "Net"), ("MapView", "MapView"), ("Sounds", "Sounds"), ("DialogKeys", "MKeys"), ("Fade", "MFade"),
                        ("CameraRig", "MCamera")):
        (dest / f"{name}.luau").write_text(f'return require("./missions_mock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "carrygrip.luau"):
        (dest / name).write_bytes((HERE / name).read_bytes())
