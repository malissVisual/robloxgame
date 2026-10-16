"""9.1 the drive pedals: the folder tools/phone-ui/drivepedals.luau runs in (check.py runs its checks there,
drivepedals_preview.py its scenes): offercardenv.py's folder (sandbox_mock.luau's recorder, the real client/PadGlyph.luau,
client/TouchLayout.luau, client/OfferCard.luau, client/TopBlocks.luau and the real shared modules, shared/PedalRules.luau
among them) with the real client/DrivePedals.luau, client/Drive.luau's stand-in (sandbox_mock's PedalDrive, which the
check sets before it loads DrivePedals: the seat, your car, the speed, the foot, what setPedal was given) and the check
itself."""
from pathlib import Path

from offercardenv import offercard_env
from sandboxenv import HERE, PREFIX, ROOT, local


def drivepedals_env(dest: Path):
    offercard_env(dest)
    (dest / "DrivePedals.luau").write_text(PREFIX + local((ROOT / "src/client/DrivePedals.luau").read_text()))
    (dest / "Drive.luau").write_text('return require("./sandbox_mock").PedalDrive')
    (dest / "drivepedals.luau").write_bytes((HERE / "drivepedals.luau").read_bytes())
