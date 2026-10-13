"""7.2: the folder tools/phone-ui/mapview.luau runs in (check.py runs its checks there, mapview_preview.py its scenes):
the real shared modules, the real client/MapView.luau on mapmock.luau's recorder (missions_mock.luau's, the services,
the camera, your character, Discovery's grid, DeviceBudget) and the Ui, Theme, Discovery and DeviceBudget stand-ins."""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PREFIX = '''local mock = require("./mapmock")
local game, workspace, task = mock.game, mock.workspace, mock.task
local Enum, Vector2, Vector3, UDim, UDim2 = mock.Enum, mock.Vector2, mock.Vector3, mock.UDim, mock.UDim2
local Color3, TweenInfo, typeof, warn = mock.Color3, mock.TweenInfo, mock.typeof, mock.warn
local Instance, CFrame, ColorSequence = mock.Instance, mock.CFrame, mock.ColorSequence
local NumberSequence, NumberSequenceKeypoint = mock.NumberSequence, mock.NumberSequenceKeypoint
'''


def map_env(dest: Path):
    def local(text: str) -> str:
        return re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)

    for source in (ROOT / "src/shared").glob("*.luau"):
        (dest / source.name).write_text(local(source.read_text()))
    (dest / "MapView.luau").write_text(PREFIX + local((ROOT / "src/client/MapView.luau").read_text()))
    # a second MapView (built from the server's summary) and MapStyle with the recorder's Instance (its publish)
    (dest / "MapViewServer.luau").write_text(PREFIX + local((ROOT / "src/client/MapView.luau").read_text()))
    (dest / "MapStyleServer.luau").write_text(PREFIX + local((ROOT / "src/shared/MapStyle.luau").read_text()))
    for name, field in (("Ui", "MUi"), ("Theme", "MTheme"), ("Discovery", "Discovery"), ("DeviceBudget", "DeviceBudget")):
        (dest / f"{name}.luau").write_text(f'return require("./mapmock").{field}')
    for name in ("mock.luau", "missions_mock.luau", "mapmock.luau", "mapview.luau"):
        (dest / name).write_bytes((HERE / name).read_bytes())
