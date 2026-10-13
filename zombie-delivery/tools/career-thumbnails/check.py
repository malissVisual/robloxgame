#!/usr/bin/env python3
"""6.23: audit the career pictures (Codex's codex/career-thumbnails scenes in art/career-thumbnails/) against the game.

Checks that every job board danger tier (Config.Jobs.Tiers) and every property (Config.Estate.Properties: a garage is
garage:<id>, a home or an office estate:<id>) has exactly one manifest asset and one PNG, no uncatalogued PNG; each
file is a real PNG matching its width, height and sha256File, about 16:9 and at least 900 px wide, no byte copy of
another or of a job picture; robloxImage is "" or rbxassetid://<digits>; and src/shared/CareerArt.luau's
CareerArt.Images has the same keys in the same order with the same robloxImage values. Prints one PASS line.

    python3 tools/career-thumbnails/check.py          (from zombie-delivery/)
"""

import hashlib
import json
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "art/career-thumbnails"


def expected_keys():
    """The keys today's Config needs: tier:1 … tier:n, then the properties' (garage:<id> / estate:<id>)."""
    config = (ROOT / "src/shared/Config.luau").read_text(encoding="utf-8")
    jobs = config[config.index("Config.Jobs = {"):]
    tiers = jobs.split("\n\tTiers = {", 1)[1].split("\n\t}", 1)[0]
    count = len(re.findall(r"\{[^{}]*\bstars = \d", tiers))
    estate = config[config.index("Config.Estate = {"):]
    properties = estate.split("\n\tProperties = {", 1)[1].split("\n\t} :: { EstateDef }", 1)[0]
    defs = re.findall(r'\bid = "([^"]+)",[^\n]*?\bkind = "([^"]+)"', properties)
    assert count >= 1 and defs, "Config extraction failed (Jobs.Tiers / Estate.Properties)"
    keys = {f"tier:{n}" for n in range(1, count + 1)}
    keys.update(f"{'garage' if kind == 'garage' else 'estate'}:{pid}" for pid, kind in defs)
    return keys, count, len(defs)


def runtime_images():
    source = (ROOT / "src/shared/CareerArt.luau").read_text(encoding="utf-8")
    head = "\nCareerArt.Images = {\n"
    start = source.index(head) + len(head)
    lines = source[start:source.index("\n}", start)].splitlines()
    return [re.fullmatch(r'\t\["([^"]+)"\] = "([^"]*)",', line).groups() for line in lines]


def run():
    manifest = json.loads((ART / "manifest.json").read_text(encoding="utf-8"))
    assets = manifest["assets"]
    keys = [asset["id"] for asset in assets]
    assert len(set(keys)) == len(keys), "Duplicate asset id"
    wanted, tiers, properties = expected_keys()
    assert set(keys) == wanted, f"missing {sorted(wanted - set(keys))}, extra {sorted(set(keys) - wanted)}"
    jobs = {hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT / "art/job-thumbnails").glob("*.png")}
    hashes = set()
    for asset in assets:
        kind, _, rest = asset["id"].partition(":")
        assert asset["kind"] == kind and asset["file"] == f"{kind}_{rest}.png", f"Unexpected file name: {asset['file']}"
        filename = ART / asset["file"]
        assert filename.is_file(), f"Missing {filename}"
        with Image.open(filename) as picture:
            assert picture.format == "PNG", f"Not a PNG: {filename}"
            picture.load()
            width, height = picture.size
        assert (asset["width"], asset["height"]) == (width, height), f"Size differs from the manifest: {filename}"
        assert width >= 900 and 1.70 < width / height < 1.90, f"Not a wide picture: {filename}"
        digest = hashlib.sha256(filename.read_bytes()).hexdigest()
        assert digest == asset["sha256File"], f"Original image changed: {filename}"
        assert digest not in hashes, f"Duplicate picture: {filename}"
        assert digest not in jobs, f"A job picture's copy: {filename}"
        hashes.add(digest)
        assert asset["robloxImage"] == "" or re.fullmatch(r"rbxassetid://\d+", asset["robloxImage"]), asset["id"]
    files = {asset["file"] for asset in assets}
    assert files == {p.name for p in ART.glob("*.png")}, f"Uncatalogued PNG: {sorted({p.name for p in ART.glob('*.png')} - files)}"
    images = runtime_images()
    assert images == [(asset["id"], asset["robloxImage"]) for asset in assets], (
        "src/shared/CareerArt.luau CareerArt.Images differs from the manifest's assets / robloxImage (keys, order or ids)")
    uploaded = sum(1 for asset in assets if asset["robloxImage"])
    print(f"PASS: {len(assets)} career PNGs cover the {tiers} danger tiers and the {properties} properties; "
          f"src/shared/CareerArt.luau agrees ({uploaded} / {len(assets)} uploaded).")


if __name__ == "__main__":
    run()
