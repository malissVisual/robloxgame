#!/usr/bin/env python3
"""6.12.13: fill the uploaded mission chapters' pictures' Roblox image ids into the game.

Codex draws one picture per story chapter (design/mission-art/BRIEF.md: art/mission-art/<campaignId>.png). The owner
uploads them in Studio the same way as the job pictures (design/job-thumbnails/NAHRAT-OBRAZKY.md, with the
art/mission-art folder; design/mission-art/NAHRAT-OBRAZKY.md once Codex writes it) and sends the ids: lines of
"<name> rbxassetid://<number>", e.g. the Output of

    for _, d in workspace:GetDescendants() do if d:IsA("Decal") then print(d.Name, d.Texture) end end

Run from zombie-delivery/ with the lines in a file or on stdin:

    python3 tools/mission-art/fill-ids.py ids.txt
    python3 tools/mission-art/fill-ids.py < ids.txt
    python3 tools/mission-art/fill-ids.py --dry-run ids.txt     (only report)

A name is a chapter's campaign id ("clinic"), its file ("clinic.png") or the chapter's name ("Code Red"; the
manifest's names too when it exists), any case. The id may be "rbxassetid://123", an asset URL ("...?id=123") or the
bare number (Copy Asset ID). Timestamps and the Output's "- Edit" / "- Studio" tails are ignored.

It writes the ids into src/shared/MissionArt.luau (MissionArt.Images) and, when they exist, the manifest's
assets[].robloxImage (art/mission-art/manifest.json) and design/mission-art/upload.csv. It keeps the ids filled
before, and reports the lines it could not read and the chapters still missing. An id that is already a job picture's
(src/shared/JobThumbs.luau) is skipped: the job pictures share names with the chapters ("clinic", "army", "ranch",
"lab"), so a line pasted from the wrong upload is caught. Then run tools/mission-art/check.py (Codex's, with the art).
"""

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "src/shared/MissionArt.luau"
MISSIONS = ROOT / "src/shared/Missions.luau"
JOBS = ROOT / "src/shared/JobThumbs.luau"
MANIFEST = ROOT / "art/mission-art/manifest.json"
UPLOAD = ROOT / "design/mission-art/upload.csv"

ID_PATTERNS = (
    re.compile(r"rbxassetid://(\d+)", re.I),
    re.compile(r"https?://\S*?[?&]id=(\d+)", re.I),  # an asset URL (the name is what comes before it)
    re.compile(r"[?&]id=(\d+)", re.I),
    re.compile(r"(?<![\w:/.])(\d{6,})(?![\w.])"),  # a bare number (Copy Asset ID)
)
TIMESTAMP = re.compile(r"^\s*\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\s*")
LINE = re.compile(r'\t(\w+) = "([^"]*)",(?:\s*--.*)?')


def key(text):
    """A name compared without case, the extension, punctuation or spaces."""
    text = text.strip().replace("\\", "/").split("/")[-1]
    text = re.sub(r"\.(png|jpe?g)$", "", text, flags=re.I)
    return re.sub(r"[^a-z0-9]", "", text.lower())


def block(path, table):
    """The `<table> = { ... }` block of a Luau file: (text, start, end, [(id, value)])."""
    text = path.read_text(encoding="utf-8")
    head = f"\n{table} = {{\n"
    start = text.index(head) + len(head)
    end = text.index("\n}", start)
    rows = []
    for line in text[start:end].split("\n"):
        match = LINE.fullmatch(line)
        assert match, f"unexpected line in {table} ({path.name}): {line!r}"
        rows.append(match.groups())
    return text, start, end, rows


def chapters():
    """The chapters in the game: [{id, file, name, robloxImage}] in MissionArt.Images' order (the chapters' names
    from shared/Missions.luau, the manifest's names as aliases when it exists)."""
    names = dict(re.findall(r'campaign\(\{ id = "(\w+)", name = "([^"]+)"', MISSIONS.read_text(encoding="utf-8")))
    _, _, _, rows = block(RUNTIME, "MissionArt.Images")
    return [{"id": cid, "file": f"{cid}.png", "name": names.get(cid, cid), "robloxImage": image} for cid, image in rows]


def parse(lines, assets, aliases):
    """The (chapter id, rbxassetid) pairs found, and the lines it could not read."""
    names = {}
    for asset in assets:
        for alias in (asset["id"], asset["file"], asset["name"], *aliases.get(asset["id"], ())):
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
            unread.append((raw.strip(), f'unknown chapter picture "{name}"'))
            continue
        found.append((asset, f"rbxassetid://{match.group(1)}"))
    return found, unread


def write_runtime(ids):
    text, start, end, _ = block(RUNTIME, "MissionArt.Images")
    lines = text[start:end].split("\n")
    for index, line in enumerate(lines):
        match = LINE.fullmatch(line)
        if match.group(1) in ids:
            lines[index] = f'\t{match.group(1)} = "{ids[match.group(1)]}",'
    RUNTIME.write_text(text[:start] + "\n".join(lines) + text[end:], encoding="utf-8")


def write_upload(ids):
    rows = list(csv.reader(io.StringIO(UPLOAD.read_text(encoding="utf-8"))))
    for row in rows[1:]:
        if len(row) >= 3 and row[0] in ids:
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
    assets = chapters()
    known = {asset["id"] for asset in assets}
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.is_file() else None
    aliases = {}
    if manifest:
        for asset in manifest.get("assets", []):
            if asset.get("id") in known:
                aliases[asset["id"]] = [value for value in (asset.get("file"), asset.get("name")) if value]
            else:
                print(f"! the manifest's {asset.get('id')!r} is no chapter in src/shared/MissionArt.luau; it is left as it is")
    found, unread = parse(text.splitlines(), assets, aliases)
    jobs = {image for _, image in block(JOBS, "JobThumbs.Images")[3] if image}

    ids = {}
    for asset, image in found:
        if image in jobs:
            print(f"! {asset}: {image} is a job picture's id (src/shared/JobThumbs.luau), not a chapter picture; skipped")
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
    done = len(assets) - len(missing)
    print(f"{len(ids)} {'id' if len(ids) == 1 else 'ids'} read, {changed} new or changed; {done} / {len(assets)} chapters have a picture id.")
    if missing:
        print("Still missing: " + ", ".join(f"{asset['id']} ({asset['file']}, {asset['name']})" for asset in missing))
    if args.dry_run:
        print("(dry run: nothing written)")
        return 0
    filled = {asset["id"]: asset["robloxImage"] for asset in assets if asset["robloxImage"]}
    written = []
    if changed:
        write_runtime(filled)
        written.append("src/shared/MissionArt.luau")
    if manifest is not None:
        touched = False
        for asset in manifest.get("assets", []):
            image = filled.get(asset.get("id"))
            if image and asset.get("robloxImage") != image:
                asset["robloxImage"] = image
                touched = True
        if touched:
            MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            written.append("art/mission-art/manifest.json")
    if UPLOAD.is_file() and filled:
        before = UPLOAD.read_text(encoding="utf-8")
        write_upload(filled)
        if UPLOAD.read_text(encoding="utf-8") != before:
            written.append("design/mission-art/upload.csv")
    if written:
        print("Written: " + ", ".join(written) + "."
              + (" Now run: python3 tools/mission-art/check.py" if (ROOT / "tools/mission-art/check.py").is_file() else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
