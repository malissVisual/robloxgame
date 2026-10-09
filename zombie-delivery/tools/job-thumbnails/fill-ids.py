#!/usr/bin/env python3
"""6.12.11: fill the uploaded job pictures' Roblox image ids into the game.

The owner uploads the 25 PNGs of art/job-thumbnails/ in Studio and sends the ids
(design/job-thumbnails/NAHRAT-OBRAZKY.md): lines of "<name> rbxassetid://<number>", e.g. the Output of

    for _, d in workspace:GetDescendants() do if d:IsA("Decal") then print(d.Name, d.Texture) end end

Run from zombie-delivery/ with the lines in a file or on stdin:

    python3 tools/job-thumbnails/fill-ids.py ids.txt
    python3 tools/job-thumbnails/fill-ids.py < ids.txt
    python3 tools/job-thumbnails/fill-ids.py --dry-run ids.txt     (only report)

A name is a picture's id ("pizzeria"), its file ("pizzeria.png") or its business ("Luigi's Pizza"), any case. The id
may be "rbxassetid://123", an asset URL ("...?id=123") or the bare number (Copy Asset ID). Timestamps and the Output's
"- Edit" / "- Studio" tails are ignored. It writes the ids into src/shared/JobThumbs.luau (JobThumbs.Images), the
manifest's assets[].robloxImage and design/job-thumbnails/upload.csv, keeps the ids filled before, and reports the
lines it could not read and the pictures still missing. Then run tools/job-thumbnails/check.py.
"""

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "art/job-thumbnails/manifest.json"
RUNTIME = ROOT / "src/shared/JobThumbs.luau"
UPLOAD = ROOT / "design/job-thumbnails/upload.csv"

ID_PATTERNS = (
    re.compile(r"rbxassetid://(\d+)", re.I),
    re.compile(r"https?://\S*?[?&]id=(\d+)", re.I),  # an asset URL (the name is what comes before it)
    re.compile(r"[?&]id=(\d+)", re.I),
    re.compile(r"(?<![\w:/.])(\d{6,})(?![\w.])"),  # a bare number (Copy Asset ID)
)
TIMESTAMP = re.compile(r"^\s*\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\s*")


def key(text):
    """A name compared without case, the extension, punctuation or spaces."""
    text = text.strip().replace("\\", "/").split("/")[-1]
    text = re.sub(r"\.(png|jpe?g)$", "", text, flags=re.I)
    return re.sub(r"[^a-z0-9]", "", text.lower())


def parse(lines, assets):
    """The (asset id, rbxassetid) pairs found, and the lines it could not read."""
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
            unread.append((raw.strip(), f'unknown picture "{name}"'))
            continue
        found.append((asset, f"rbxassetid://{match.group(1)}"))
    return found, unread


def write_runtime(ids):
    text = RUNTIME.read_text(encoding="utf-8")
    head = "\nJobThumbs.Images = {\n"
    start = text.index(head) + len(head)
    end = text.index("\n}", start)
    lines = text[start:end].split("\n")
    for index, line in enumerate(lines):
        match = re.fullmatch(r'\t(\w+) = "([^"]*)",', line)
        assert match, f"unexpected line in JobThumbs.Images: {line!r}"
        if match.group(1) in ids:
            lines[index] = f'\t{match.group(1)} = "{ids[match.group(1)]}",'
    RUNTIME.write_text(text[:start] + "\n".join(lines) + text[end:], encoding="utf-8")


def write_upload(ids):
    rows = list(csv.reader(io.StringIO(UPLOAD.read_text(encoding="utf-8"))))
    for row in rows[1:]:
        if row and row[0] in ids:
            row[2] = ids[row[0]]
    out = io.StringIO()
    csv.writer(out, lineterminator="\n").writerows(rows)
    UPLOAD.write_text(out.getvalue(), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", nargs="?", help="the pasted lines (default: stdin)")
    parser.add_argument("--dry-run", action="store_true", help="only report, change nothing")
    args = parser.parse_args()
    text = Path(args.file).read_text(encoding="utf-8-sig") if args.file else sys.stdin.read()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = manifest["assets"]
    found, unread = parse(text.splitlines(), assets)

    ids = {}
    for asset, image in found:
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
    done = len(assets) - len(missing)
    print(f"{len(ids)} {'id' if len(ids) == 1 else 'ids'} read, {changed} new or changed; {done} / {len(assets)} pictures have an id.")
    if missing:
        print("Still missing: " + ", ".join(f"{asset['id']} ({asset['file']}, {asset['name']})" for asset in missing))
    if args.dry_run:
        print("(dry run: nothing written)")
        return 0
    if changed:
        MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        filled = {asset["id"]: asset["robloxImage"] for asset in assets if asset["robloxImage"]}
        write_runtime(filled)
        write_upload(filled)
        print("Written: src/shared/JobThumbs.luau, art/job-thumbnails/manifest.json, design/job-thumbnails/upload.csv."
              " Now run: python3 tools/job-thumbnails/check.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
