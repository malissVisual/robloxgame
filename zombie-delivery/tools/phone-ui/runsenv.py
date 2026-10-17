"""9.7 runs: the folder tools/phone-ui/runs.luau runs in (check.py runs its checks there): sandboxenv.py's folder
(sandbox_mock.luau's recorder, the real client/SandboxHud.luau, client/SandboxTasksUi.luau, client/TouchLayout.luau,
client/MoveLayout.luau and the real shared modules) with the real client/RunUi.luau (the pad panel and the results card)
on the same recorder, and the check itself. 10.x danger: the real client/RunDangerUi.luau (the run's danger strip, the
horde's banner) and client/TopBlocks.luau (the move's panel it goes under) there too."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def runs_env(dest: Path):
    sandbox_env(dest)
    (dest / "RunUi.luau").write_text(PREFIX + local((ROOT / "src/client/RunUi.luau").read_text()))
    for name in ("RunDangerUi", "TopBlocks", "RoundUi"):  # (10.x danger; 10.5 rounds: RoundUi)
        (dest / f"{name}.luau").write_text(PREFIX + local((ROOT / f"src/client/{name}.luau").read_text()))
    (dest / "runs.luau").write_bytes((HERE / "runs.luau").read_bytes())
