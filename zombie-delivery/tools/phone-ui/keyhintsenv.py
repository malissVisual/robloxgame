"""8.3 keys: the folder tools/phone-ui/keyhints.luau runs in (check.py runs its checks there): sandboxenv.py's folder
(sandbox_mock.luau's recorder, the real client/PadGlyph.luau and the real shared modules, shared/SandboxPad.luau's
actions among them) with the real client/KeyHints.luau and the stand-ins it needs (client/HudContract.luau's colours and
text, client/Holster.luau's hand, client/Drive.luau's seat: sandbox_mock's KeyHintsP, KeyHintsHolster and
KeyHintsDrive, which the check sets before it loads KeyHints), and the check itself."""
from pathlib import Path

from sandboxenv import HERE, PREFIX, ROOT, local, sandbox_env


def keyhints_env(dest: Path):
    sandbox_env(dest)
    (dest / "KeyHints.luau").write_text(PREFIX + local((ROOT / "src/client/KeyHints.luau").read_text()))
    for name, field in (("HudContract", "KeyHintsP"), ("Holster", "KeyHintsHolster"), ("Drive", "KeyHintsDrive")):
        (dest / f"{name}.luau").write_text(f'return require("./sandbox_mock").{field}')
    (dest / "keyhints.luau").write_bytes((HERE / "keyhints.luau").read_bytes())
