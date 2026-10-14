"""8.3 the showroom's visitors: the folder tools/phone-ui/offercard.luau runs in (check.py runs its checks there,
offercard_preview.py its scenes): sandboxenv.py's folder (sandbox_mock.luau's recorder, the real client/SandboxHud.luau,
client/SandboxTasksUi.luau, client/TouchLayout.luau, client/MoveLayout.luau and the real shared modules) with the real
client/OfferCard.luau (its clock the recorder's: mock.now, as client/SandboxHintsUi.luau's) and client/TopBlocks.luau on
the same recorder, and the check itself."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def offercard_env(dest: Path):
    sandbox_env(dest)
    card = local((ROOT / "src/client/OfferCard.luau").read_text())
    assert "os.clock()" in card
    (dest / "OfferCard.luau").write_text(PREFIX + card.replace("os.clock()", "mock.now"))
    (dest / "TopBlocks.luau").write_text(PREFIX + local((ROOT / "src/client/TopBlocks.luau").read_text()))
    (dest / "offercard.luau").write_bytes((HERE / "offercard.luau").read_bytes())
