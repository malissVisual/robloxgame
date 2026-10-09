"""Audit delivery thumbnail coverage against Config and verify the original PNG assets."""

import hashlib
import json
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "art/job-thumbnails"


def run():
    manifest = json.loads((ART / "manifest.json").read_text())
    config = (ROOT / "src/shared/Config.luau").read_text()
    jobs = config[config.index("Config.Jobs = {"):]
    businesses = jobs.split("\n\tBusinesses = {", 1)[1].split("\n\t} :: { BusinessDef }", 1)[0]
    types = config.split("Config.JobTypes = {", 1)[1].split("\n} :: { JobTypeDef }", 1)[0]
    expected = {
        "ordinary": set(re.findall(r'^\t\t\tid = "([^"]+)"', businesses, re.M)),
        "special": set(re.findall(r'^\t\tid = "([^"]+)"', types, re.M)),
    }
    assert expected["ordinary"] and expected["special"], "Config definition extraction failed"
    for kind, ids in expected.items():
        mapped = set(manifest[kind])
        assert mapped == ids, f"{kind}: missing {ids - mapped}, extra {mapped - ids}"
    assets = manifest["assets"]
    keys = {asset["id"] for asset in assets}
    assert len(keys) == len(assets), "Duplicate asset id"
    referenced = set(manifest["ordinary"].values()) | set(manifest["special"].values())
    referenced.update((manifest["round"], manifest["tutorial"]))
    assert keys == referenced, f"Missing/unused pictures: {keys ^ referenced}"
    assert manifest["ordinary"]["cake"] == manifest["ordinary"]["bakery"]
    assert manifest["ordinary"]["lab"] == manifest["ordinary"]["samples"]
    assert manifest["round"] == manifest["ordinary"]["news"]
    files = set()
    hashes = set()
    for asset in assets:
        assert asset["file"] == asset["id"] + ".png", "Unsafe/unexpected file path"
        filename = ART / asset["file"]
        assert filename.is_file(), f"Missing {filename}"
        with Image.open(filename) as picture:
            assert picture.format == "PNG"
            picture.load()
            width, height = picture.size
            assert width >= 900 and height >= 500, f"Too small: {filename}"
            assert 1.70 < width / height < 1.90, f"Not a wide tile: {filename}"
            assert asset["width"] == width and asset["height"] == height
        digest = hashlib.sha256(filename.read_bytes()).hexdigest()
        assert digest == asset["sha256File"], f"Original image changed: {filename}"
        assert digest not in hashes, f"Duplicate picture under different businesses: {filename}"
        hashes.add(digest)
        files.add(filename.name)
        assert asset["robloxImage"] == "" or re.fullmatch(r"rbxassetid://\d+", asset["robloxImage"])
    assert files == {p.name for p in ART.glob("*.png")}, "Uncatalogued PNG"
    print(f"PASS: {len(assets)} original PNGs cover {len(expected['ordinary'])} ordinary definitions, "
          f"{len(expected['special'])} special types, the paper round and the tutorial.")
    return manifest


if __name__ == "__main__":
    run()
