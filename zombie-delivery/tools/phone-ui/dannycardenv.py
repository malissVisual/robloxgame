"""8.3 Danny for hire: the folder tools/phone-ui/dannycard.luau runs in (check.py runs its checks there,
dannycard_preview.py its scenes): sandboxenv.py's folder (sandbox_mock.luau's recorder, the real client/SandboxHud.luau,
client/SandboxTasksUi.luau, client/CardKit.luau, client/TouchLayout.luau, client/MoveLayout.luau and the real shared
modules) with the real client/MoveHelperCard.luau, client/MoveHelperHud.luau and client/TopBlocks.luau on the same
recorder (MoveHelperCard's RaycastParams the check's stand-in: mock.RaycastParams; 8.3 review: its clock the
recorder's, mock.now, as client/OfferCard.luau's: the tap that closed the card swallowed a moment), client/CarryGripUi.luau
a stand-in (its active(): the check's `open`), and the check itself. 8.5: client/DannyOrders.luau (Danny's clipboard,
orders mode) on the same recorder, its clock the recorder's too, and tools/phone-ui/dannyorders.luau (its line at the
bottom and its touch 📋 button) beside the card's check. 8.6: client/DannyBubble.luau (what Danny does, over his head)
on the same recorder (the card's check drives it: its words, its place over his name tag, its fade)."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def dannycard_env(dest: Path):
    sandbox_env(dest)
    for name in ("MoveHelperCard", "MoveHelperHud", "TopBlocks", "DannyOrders", "DannyBubble"):
        extra = "local RaycastParams = mock.RaycastParams\n" if name == "MoveHelperCard" else ""
        text = local((ROOT / f"src/client/{name}.luau").read_text())
        if name in ("MoveHelperCard", "DannyOrders"):
            assert "os.clock()" in text
            text = text.replace("os.clock()", "mock.now")  # (8.3 review: the recorder's clock)
        (dest / f"{name}.luau").write_text(PREFIX + extra + text)
    (dest / "CarryGripUi.luau").write_text("local M = { open = false }\nfunction M.active() return M.open end\nreturn M\n")
    for name in ("dannycard.luau", "dannyorders.luau"):
        (dest / name).write_bytes((HERE / name).read_bytes())
