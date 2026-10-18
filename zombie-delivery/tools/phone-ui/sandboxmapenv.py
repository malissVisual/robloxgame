"""10.x the map: the folder tools/phone-ui/sandboxmap.luau runs in (check.py runs its checks there, sandboxmap_preview.py
its scenes): runsenv.py's folder (sandbox_mock.luau's recorder, the real client/SandboxHud.luau, client/SandboxTasksUi.luau
and client/RunUi.luau, client/TouchLayout.luau, client/MoveLayout.luau, client/PadGlyph.luau, client/CardKit.luau and the
real shared modules) with the real client/SandboxMapData.luau, client/SandboxMapDraw.luau, client/SandboxMapUi.luau,
client/SandboxMiniMap.luau and client/TopBlocks.luau on the same recorder, client/SandboxGuide.luau a stand-in that
records goTo (M.guided), and plans.luau: the real shared/HouseLayout.luau plans of the farmstead and the pond cabin
(their MapPlan, shared/SandboxMapRules.luau encode, and their pieces' spots), made here by the Luau CLI on the tests'
recorder (tools/vehicle-preview/roblox-mock.luau, tools/fixtures/item-mock.luau) as server/HouseInterior.luau would."""
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from runsenv import runs_env
from sandboxenv import HERE, PREFIX, ROOT, local

# (the few Roblox types the modules make that the recorder has no stand-in for)
EXTRA = '''local RaycastParams = mock.RaycastParams or { new = function() return {} end }
'''

RECORDER = ("ItemLooks", "FurnitureLooks", "HouseLayout")
ITEM_PREFIX = ('local M = require("./ItemMock")\n'
               'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')
PLANS = '''local HouseLayout = require("./HouseLayout")
local Rules = require("./SandboxMapRules")
local out = {}
for _, entry in { { "big", 5, 9000 }, { "cabin", 3, 9600 } } do
	local plan = HouseLayout.plan(entry[2], entry[1])
	local code = Rules.encode(plan, { x = entry[3], y = 400, z = 9000, yaw = 0 })
	local spots = {}
	for _, s in plan.spots do
		local p = s.at.Position
		table.insert(spots, string.format("{ id = %d, item = %q, room = %q, x = %.2f, y = %.2f, z = %.2f }", s.id, s.item, s.room, p.X, p.Y, p.Z))
	end
	table.insert(out, string.format("%s = { code = %q, seed = %d, origin = { x = %d, y = 400, z = 9000 }, spots = { %s } }", entry[1], code, entry[2], entry[3], table.concat(spots, ", ")))
end
print("return { " .. table.concat(out, ", ") .. " }")
'''


def plans(luau: str) -> str:
    """The plans' module: the real HouseLayout on the tests' recorder (tests/run_tests.py's staging)."""
    shared = ROOT / "src" / "shared"
    with tempfile.TemporaryDirectory() as folder:
        t = Path(folder)
        for source in shared.glob("*.luau"):
            text = re.sub(r"require\(script\.Parent\.Layouts\.(\w+)\)", r'require("./\1")', source.read_text())
            text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
            (t / source.name).write_text((ITEM_PREFIX if source.stem in RECORDER else "") + text)
        for source in (shared / "Layouts").glob("*.luau"):
            text = re.sub(r"require\(script\.Parent\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
            (t / source.name).write_text(ITEM_PREFIX + text)
        shutil.copy(ROOT / "tools" / "vehicle-preview" / "roblox-mock.luau", t / "rbxmock.luau")
        shutil.copy(ROOT / "tools" / "fixtures" / "item-mock.luau", t / "ItemMock.luau")
        (t / "plans.luau").write_text(PLANS)
        out = subprocess.run([luau, "plans.luau"], cwd=t, capture_output=True, text=True, check=True)
        return out.stdout.strip().splitlines()[-1] + "\n"


def sandboxmap_env(dest: Path, luau: str):
    runs_env(dest)
    for name in ("SandboxMapData", "SandboxMapDraw", "SandboxMapUi", "SandboxMiniMap", "TopBlocks"):
        source = local((ROOT / f"src/client/{name}.luau").read_text())
        (dest / f"{name}.luau").write_text(PREFIX + EXTRA + source)
    (dest / "SandboxGuide.luau").write_text(
        'local M = require("./sandbox_mock")\nM.guided = {}\n'
        'return { goTo = function(at, label, seconds) table.insert(M.guided, { at = at, label = label, seconds = seconds }) end }\n')
    (dest / "plans.luau").write_text(plans(luau))
    (dest / "sandboxmap.luau").write_bytes((HERE / "sandboxmap.luau").read_bytes())
