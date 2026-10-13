#!/usr/bin/env python3
"""6.23: fill the uploaded career pictures' Roblox image ids into the game.

The owner uploads the 21 PNGs of art/career-thumbnails/ in Studio the same way as the job pictures
(design/job-thumbnails/NAHRAT-OBRAZKY.md, with the art/career-thumbnails folder) and sends the ids: lines of
"<name> rbxassetid://<number>", e.g. the Output of

    for _, d in workspace:GetDescendants() do if d:IsA("Decal") then print(d.Name, d.Texture) end end

Run from zombie-delivery/ with the lines in a file or on stdin:

    python3 tools/career-thumbnails/fill-ids.py ids.txt
    python3 tools/career-thumbnails/fill-ids.py < ids.txt
    python3 tools/career-thumbnails/fill-ids.py --dry-run ids.txt     (only report)

A name is a picture's key ("estate:elm"), its file ("estate_elm.png", the name Studio gives the upload) or its name in
the game ("Elm Bungalow", "Easy jobs"), any case. The id may be "rbxassetid://123", an asset URL ("...?id=123") or the
bare number (Copy Asset ID). Timestamps and the Output's "- Edit" / "- Studio" tails are ignored. It writes the ids
into src/shared/CareerArt.luau (CareerArt.Images) and the manifest's assets[].robloxImage, keeps the ids filled before,
and reports the lines it could not read and the pictures still missing. An id that is already a job picture's
(src/shared/JobThumbs.luau) is skipped (a line pasted from the wrong upload). Then run tools/career-thumbnails/check.py.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "art/career-thumbnails/manifest.json"
RUNTIME = ROOT / "src/shared/CareerArt.luau"
JOBS = ROOT / "src/shared/JobThumbs.luau"

ID_PATTERNS = (
    re.compile(r"rbxassetid://(\d+)", re.I),
    re.compile(r"https?://\S*?[?&]id=(\d+)", re.I),  # an asset URL (the name is what comes before it)
    re.compile(r"[?&]id=(\d+)", re.I),
    re.compile(r"(?<![\w:/.])(\d{6,})(?![\w.])"),  # a bare number (Copy Asset ID)
)
TIMESTAMP = re.compile(r"^\s*\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\s*")
LINE = re.compile(r'\t\["([^"]+)"\] = "([^"]*)",')


def key(text):
    """A name compared without case, the extension, punctuation, stars or spaces."""
    text = text.strip().replace("\\", "/").split("/")[-1]
    text = re.sub(r"\.(png|jpe?g)$", "", text, flags=re.I)
    return re.sub(r"[^a-z0-9]", "", text.lower())


def block(text, head):
    """The lines of a `<head> = { ... }` table: (start, end) offsets."""
    start = text.index(head) + len(head)
    return start, text.index("\n}", start)


def parse(lines, assets):
    """The (asset key, rbxassetid) pairs found, and the lines it could not read."""
    names = {}
    for asset in assets:
        for alias in (asset["id"], asset["file"], asset["name"]):
            names[key(alias)] = asset["id"]
    found, unread = [], []
    for raw in lines:
        line = TIMESTAMP.sub("", raw.strip().lstrip("\ufeff"))
        if not line:
            continue
        match = None
        for pattern in ID_PATTERNS:
            match = pattern.search(line)
            if match:
                break
        if not match:
            unread.append((raw.strip(), "no image id"))
            continue
        name = line[:match.start()].strip().rstrip(":=-,;\t ").strip()
        if not name:
            unread.append((raw.strip(), "no name before the id"))
            continue
        asset = names.get(key(name))
        if not asset:
            unread.append((raw.strip(), f'unknown career picture "{name}"'))
            continue
        found.append((asset, f"rbxassetid://{match.group(1)}"))
    return found, unread


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", nargs="?", help="the pasted lines (default: stdin)")
    parser.add_argument("--dry-run", action="store_true", help="only report, change nothing")
    args = parser.parse_args()
    text = Path(args.file).read_text(encoding="utf-8-sig") if args.file else sys.stdin.read()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = manifest["assets"]
    found, unread = parse(text.splitlines(), assets)
    source = JOBS.read_text(encoding="utf-8")
    start, end = block(source, "\nJobThumbs.Images = {\n")
    jobs = set(re.findall(r'"(rbxassetid://\d+)"', source[start:end]))

    ids = {}
    for asset, image in found:
        if image in jobs:
            print(f"! {asset}: {image} is a job picture's id (src/shared/JobThumbs.luau), not a career picture; skipped")
            continue
        if asset in ids and ids[asset] != image:
            print(f"! {asset}: two different ids ({ids[asset]}, {image}); the last one is used")
        ids[asset] = image
    changed = 0
    for asset in assets:
        image = ids.get(asset["id"])
        if image and asset["robloxImage"] != image:
            if asset["robloxImage"]:
                print(f"~ {asset['id']}: {asset['robloxImage']} -> {image}")
            asset["robloxImage"] = image
            changed += 1

    for line, why in unread:
        print(f"? not read ({why}): {line}")
    missing = [asset for asset in assets if not asset["robloxImage"]]
    print(f"{len(ids)} {'id' if len(ids) == 1 else 'ids'} read, {changed} new or changed; "
          f"{len(assets) - len(missing)} / {len(assets)} career pictures have an id.")
    if missing:
        print("Still missing: " + ", ".join(f"{asset['file']} ({asset['name']})" for asset in missing))
    if args.dry_run or not changed:
        if args.dry_run:
            print("(dry run: nothing written)")
        return 0
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    runtime = RUNTIME.read_text(encoding="utf-8")
    start, end = block(runtime, "\nCareerArt.Images = {\n")
    filled = {asset["id"]: asset["robloxImage"] for asset in assets}
    lines = []
    for line in runtime[start:end].split("\n"):
        match = LINE.fullmatch(line)
        assert match, f"unexpected line in CareerArt.Images: {line!r}"
        lines.append(f'\t["{match.group(1)}"] = "{filled.get(match.group(1), match.group(2))}",')
    RUNTIME.write_text(runtime[:start] + "\n".join(lines) + runtime[end:], encoding="utf-8")
    print("Written: src/shared/CareerArt.luau, art/career-thumbnails/manifest.json. Now run: python3 tools/career-thumbnails/check.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
