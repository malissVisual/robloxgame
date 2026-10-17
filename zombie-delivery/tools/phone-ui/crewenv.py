"""10.1 the helpers' crew: the folder tools/phone-ui/crew.luau runs in (check.py runs its checks there, crew_preview.py
its scenes): sandboxenv.py's folder (sandbox_mock.luau's recorder, the real client/CardKit.luau and the real shared
modules) with the real client/CrewUi.luau (the CREW window and the down ring) on the same recorder, and the check
itself."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def crew_env(dest: Path):
    sandbox_env(dest)
    crew = local((ROOT / "src/client/CrewUi.luau").read_text())
    assert "os.clock()" in crew
    (dest / "CrewUi.luau").write_text(PREFIX + crew.replace("os.clock()", "mock.now"))  # (the recorder's clock)
    (dest / "crew.luau").write_bytes((HERE / "crew.luau").read_bytes())
