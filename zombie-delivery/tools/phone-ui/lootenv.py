"""9.x loot: the folder tools/phone-ui/loot.luau runs in (check.py runs its checks there, loot_preview.py its scenes):
sandboxenv.py's folder (sandbox_mock.luau's recorder, client/Hud.luau's column and toasts as sandbox_mock's Hud, the
real shared modules, shared/FurnitureLooks.luau's real catalogue) with the real client/LootStars.luau (its clock the
recorder's: mock.now) and client/LootOutline.luau on the same recorder, client/DeviceBudget.luau a stand-in that
follows the recorder's device (M.touch: a phone's share and reach, Config.Performance.Lite) and client/EnemyOutline.luau
a stand-in (M.enemies: the enemies outlined now; its onSqueeze kept for the check), and the check itself."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env

# (the few Roblox types the two modules make that the recorder has no stand-in for)
EXTRA = '''local NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
local RaycastParams = mock.RaycastParams or { new = function() return {} end }
'''


def loot_env(dest: Path):
    sandbox_env(dest)
    stars = local((ROOT / "src/client/LootStars.luau").read_text())
    assert "os.clock()" in stars
    (dest / "LootStars.luau").write_text(PREFIX + EXTRA + stars.replace("os.clock()", "mock.now"))
    outline = local((ROOT / "src/client/LootOutline.luau").read_text())
    assert "os.clock()" in outline
    (dest / "LootOutline.luau").write_text(PREFIX + EXTRA + outline.replace("os.clock()", "mock.now"))
    (dest / "DeviceBudget.luau").write_text(
        'local M = require("./sandbox_mock")\nlocal Lite = require("./Config").Performance.Lite\n'
        'return {\n'
        '\trange = function(studs) return if M.touch then studs * Lite.Range else studs end,\n'
        '\tcount = function(n) return if M.touch then math.max(1, math.floor(n * Lite.Count + 0.5)) else n end,\n'
        '}\n')
    (dest / "EnemyOutline.luau").write_text(
        'local M = require("./sandbox_mock")\nlocal E = { onSqueeze = nil }\n'
        'function E.drawn() return M.enemies or 0 end\nreturn E\n')
    (dest / "loot.luau").write_bytes((HERE / "loot.luau").read_bytes())
