"""8.9: the folder tools/phone-ui/sandboxhints.luau runs in (check.py runs its checks there): dannycardenv.py's folder
(sandbox_mock.luau's recorder, the real client/SandboxHud.luau, client/SandboxTasksUi.luau, client/SandboxHintsUi.luau on
the recorder's clock, client/MoveHelperCard.luau, client/MoveHelperHud.luau, client/DannyOrders.luau,
client/TopBlocks.luau, client/TouchLayout.luau, client/MoveLayout.luau and the real shared modules) with the real
client/OfferCard.luau (its clock the recorder's: mock.now) and client/TradeUi.luau on the same recorder, and the check
itself."""
from pathlib import Path

from dannycardenv import dannycard_env
from sandboxenv import HERE, PREFIX, ROOT, local


def sandboxhints_env(dest: Path):
    dannycard_env(dest)
    card = local((ROOT / "src/client/OfferCard.luau").read_text())
    assert "os.clock()" in card
    (dest / "OfferCard.luau").write_text(PREFIX + card.replace("os.clock()", "mock.now"))
    (dest / "TradeUi.luau").write_text(PREFIX + local((ROOT / "src/client/TradeUi.luau").read_text()))
    (dest / "sandboxhints.luau").write_bytes((HERE / "sandboxhints.luau").read_bytes())
