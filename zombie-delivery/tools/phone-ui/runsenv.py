"""9.7 runs: the folder tools/phone-ui/runs.luau runs in (check.py runs its checks there): sandboxenv.py's folder
(sandbox_mock.luau's recorder, the real client/SandboxHud.luau, client/SandboxTasksUi.luau, client/TouchLayout.luau,
client/MoveLayout.luau and the real shared modules) with the real client/RunUi.luau (the results card) on the same
recorder, and the check itself. 10.x danger: the real client/RunDangerUi.luau (the run's danger strip, the horde's
banner) and client/TopBlocks.luau (the move's panel it goes under) there too. 10.4: the real client/PlayUi.luau (the PLAY
panel and the lobby bar: RunUi starts it) and its own check, tools/phone-ui/play.luau (play_env). 10.5 rounds: the real
client/RoundUi.luau (the round's banner, table and feed); 10.6 snatching: the real client/TugUi.luau (a tug of war's
panel); both in PLAY: the panel's QUICK ROUND and the banner's LEAVE QUEUE (play.luau)."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def runs_env(dest: Path):
    sandbox_env(dest)
    for name in ("RunUi", "PlayUi", "RunDangerUi", "TopBlocks", "RoundUi", "TugUi"):  # (10.x danger: RunDangerUi, TopBlocks; 10.4: PlayUi; 10.5 rounds: RoundUi; 10.6 snatching: TugUi)
        (dest / f"{name}.luau").write_text(PREFIX + local((ROOT / f"src/client/{name}.luau").read_text()))
    (dest / "runs.luau").write_bytes((HERE / "runs.luau").read_bytes())


def play_env(dest: Path):
    runs_env(dest)
    (dest / "play.luau").write_bytes((HERE / "play.luau").read_bytes())
