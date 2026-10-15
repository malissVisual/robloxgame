"""8.7 trading between players: the folder tools/phone-ui/trade.luau runs in (check.py runs its checks there):
offercardenv.py's folder (sandboxenv.py's: sandbox_mock.luau's recorder, the real client/SandboxHud.luau,
client/WarehouseUi.luau, client/CardKit.luau, client/TouchLayout.luau, client/MoveLayout.luau and the real shared modules,
shared/PlayerTradeRules.luau among them; the real client/OfferCard.luau on the recorder's clock and client/TopBlocks.luau)
with the real client/TradeUi.luau on the same recorder, and the check itself."""
from pathlib import Path

from offercardenv import offercard_env
from sandboxenv import HERE, PREFIX, ROOT, local


def trade_env(dest: Path):
    offercard_env(dest)
    (dest / "TradeUi.luau").write_text(PREFIX + local((ROOT / "src/client/TradeUi.luau").read_text()))
    (dest / "trade.luau").write_bytes((HERE / "trade.luau").read_bytes())
