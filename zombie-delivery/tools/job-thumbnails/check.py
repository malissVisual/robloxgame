"""Audit delivery thumbnail coverage against Config and verify the original PNG assets.
6.12.11: and that the game's runtime map, src/shared/JobThumbs.luau, agrees with the manifest (ids, order, uploaded
image ids, names, the job mappings)."""

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
    runtime(manifest)
    print(f"PASS: {len(assets)} original PNGs cover {len(expected['ordinary'])} ordinary definitions, "
          f"{len(expected['special'])} special types, the paper round and the tutorial; "
          f"src/shared/JobThumbs.luau agrees ({sum(1 for a in assets if a['robloxImage'])} / {len(assets)} uploaded).")
    return manifest


def block(source, name):
    """The `JobThumbs.<name> = { ... }` table of src/shared/JobThumbs.luau as its lines, in order."""
    start = source.index(f"\nJobThumbs.{name} = {{\n") + len(f"\nJobThumbs.{name} = {{\n")
    return source[start:source.index("\n}", start)].splitlines()


def runtime(manifest):
    """6.12.11: the game's runtime map (src/shared/JobThumbs.luau) agrees with the manifest: the same pictures in the
    same order, the same uploaded ids (tools/job-thumbnails/fill-ids.py writes both), names and job mappings."""
    source = (ROOT / "src/shared/JobThumbs.luau").read_text(encoding="utf-8")
    images = [re.fullmatch(r'\t(\w+) = "([^"]*)",', line).groups() for line in block(source, "Images")]
    wanted = [(asset["id"], asset["robloxImage"]) for asset in manifest["assets"]]
    assert images == wanted, ("JobThumbs.Images differs from the manifest's assets / robloxImage: "
                              + (str(sorted(set(images) ^ set(wanted))) if set(images) != set(wanted) else "not in the manifest's order"))
    names = dict(re.fullmatch(r'\t(\w+) = \{ name = "([^"]+)", emoji = "[^"]+" \},', line).groups() for line in block(source, "Assets"))
    assert names == {asset["id"]: asset["name"] for asset in manifest["assets"]}, "JobThumbs.Assets names differ from the manifest's"
    for kind, table in (("ordinary", "Ordinary"), ("special", "Special")):
        mapped = dict(re.fullmatch(r'\t(\w+) = "(\w+)",', line).groups() for line in block(source, table))
        assert mapped == manifest[kind], f"JobThumbs.{table} differs from the manifest's {kind}: {set(mapped.items()) ^ set(manifest[kind].items())}"
    for key, field in (("round", "Round"), ("tutorial", "Tutorial")):
        found = re.search(rf'^JobThumbs\.{field} = "(\w+)"', source, re.M)
        assert found and found.group(1) == manifest[key], f"JobThumbs.{field} differs from the manifest's {key}"


if __name__ == "__main__":
    run()
