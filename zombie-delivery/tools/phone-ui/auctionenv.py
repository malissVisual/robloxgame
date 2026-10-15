"""8.8 SANDBOX, the auction: the folder tools/phone-ui/auction.luau runs in (check.py runs its checks there): sandboxenv.py's
folder (sandbox_mock.luau's recorder, the real client/SandboxHud.luau, client/WarehouseUi.luau, client/CardKit.luau,
client/TouchLayout.luau, client/MoveLayout.luau and the real shared modules, shared/AuctionRules.luau and
shared/AuctionHouseLayout.luau among them) with the real client/AuctionUi.luau on the same recorder, and the check
itself (`luau auction.luau -a dump` prints its scenes as JSON, the shape sandbox_preview.mjs draws)."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def auction_env(dest: Path):
    sandbox_env(dest)
    (dest / "AuctionUi.luau").write_text(PREFIX + local((ROOT / "src/client/AuctionUi.luau").read_text()))
    (dest / "auction.luau").write_bytes((HERE / "auction.luau").read_bytes())
