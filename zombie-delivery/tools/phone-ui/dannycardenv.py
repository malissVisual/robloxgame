"""8.3 Danny's orders: the folder tools/phone-ui/dannycard.luau runs in (check.py runs its checks there,
dannycard_preview.py its scenes): sandboxenv.py's folder (sandbox_mock.luau's recorder, the real client/SandboxHud.luau,
client/SandboxTasksUi.luau, client/CardKit.luau, client/TouchLayout.luau, client/MoveLayout.luau and the real shared
modules) with the real client/MoveHelperCard.luau, client/MoveHelperHud.luau and client/TopBlocks.luau on the same
recorder, and the check itself."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def dannycard_env(dest: Path):
    sandbox_env(dest)
    for name in ("MoveHelperCard", "MoveHelperHud", "TopBlocks"):
        (dest / f"{name}.luau").write_text(PREFIX + local((ROOT / f"src/client/{name}.luau").read_text()))
    (dest / "dannycard.luau").write_bytes((HERE / "dannycard.luau").read_bytes())
