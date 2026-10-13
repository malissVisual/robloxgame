#!/usr/bin/env python3
"""7.0, the moving prototype: pictures of the furniture and of one house's inside, for the owner.

Builds every piece (shared/FurnitureLooks.luau) and a house (shared/HouseLayout.luau planned, server/HouseInterior.luau
built) with the real builders on the recorder (tools/fixtures/item-mock.luau over tools/vehicle-preview/roblox-mock.luau)
in the Luau CLI (export.luau), renders them with three.js in headless Chromium (render.mjs, render.html) and lays out:
  - a contact sheet of every piece by room: its name, class, weight, value, size, parts, ★ and fragile;
  - the house from straight above (a floor plan, the rooms named, the ★ pieces marked) beside a 3/4 cutaway.
7.x the farm: with --farm-pieces and/or --farm-interior also Walt's farm (shared/Layouts/Farm.luau): the farm's pieces
on a sheet of their own (by the farm's rooms; the house's sheet keeps the house's), the farm from above and as a 3/4
cutaway (the hay wagon, the one big-door piece, marked).

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/furniture/render.py <luau> <three.module.min.js> \\
        <furniture-sheet.png> <house-interior.png> [--seed N] [--keep DIR] \\
        [--farm-pieces farm-pieces.png] [--farm-interior farm-interior.png] [--farm-seed N]

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Playwright and
Chromium as for the other previews (CHROMIUM overrides /opt/pw-browsers/chromium).
"""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
SHARED = ROOT / "src" / "shared"
PREFIX = ('local M = require("./ItemMock")\n'
          'local Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n')
MOCKED = ("FurnitureLooks", "HouseLayout", "Farm")
ROOMS = (("living", "LIVING ROOM"), ("kitchen", "KITCHEN"), ("bedroom", "BEDROOM"), ("kids", "KID'S ROOM"),
         ("bath", "BATHROOM"), ("hall", "HALL"), ("garage", "GARAGE"))
# 7.x the farm: its pieces' rooms (on its sheet) and its plan's rooms (on its pictures)
FARM_ROOMS = (("stable", "STABLE"), ("barn", "THRESHING FLOOR"), ("workshop", "WORKSHOP"), ("yard", "YARD"),
              ("pantry", "PANTRY"), ("kitchen", "KITCHEN"), ("living", "STUBE (LIVING ROOM)"))
FARM_PLAN_ROOMS = {"mudroom": "MUD ROOM", "stube": "STUBE", "kitchen": "KITCHEN", "bedroom": "BEDROOM", "pantry": "PANTRY",
                   "yard": "YARD", "stable": "STABLE", "barn": "THRESHING FLOOR", "workshop": "WORKSHOP"}
CLASS_COLOR = {"hand": (126, 196, 120), "both": (240, 180, 70), "pair": (232, 96, 84)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans{}.ttf"


def font(size, bold=False):
    return ImageFont.truetype(FONT.format("-Bold" if bold else ""), size)


def export(luau: str, tmp: Path, seed: int, farm_seed=None) -> Path:
    for source in list(SHARED.glob("*.luau")) + list(SHARED.glob("Layouts/*.luau")):  # (7.x: the farm's layout too)
        text = re.sub(r"require\(script\.Parent\.(?:Parent\.|Layouts\.)?(\w+)\)", r'require("./\1")', source.read_text())
        (tmp / source.name).write_text(PREFIX + text if source.stem in MOCKED else text)
    text = (ROOT / "src/server/HouseInterior.luau").read_text()
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', text)
    (tmp / "HouseInterior.luau").write_text(PREFIX + "local game = M.game\n" + text)
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    shutil.copy(HERE / "export.luau", tmp / "export.luau")
    extra = [str(farm_seed)] if farm_seed is not None else []
    result = subprocess.run([str(Path(luau).resolve()), "export.luau", "-a", str(seed)] + extra, cwd=tmp, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit("export failed:\n" + result.stdout[-2000:] + result.stderr)
    scenes = tmp / "scenes.jsonl"
    scenes.write_text(result.stdout)
    return scenes


def render(scenes: Path, three: Path, out: Path):
    site = scenes.parent / "site"
    site.mkdir(exist_ok=True)
    shutil.copy(HERE / "render.html", site / "render.html")
    shutil.copy(three, site / "three.module.min.js")
    subprocess.run(["node", str(HERE / "render.mjs"), str(scenes), str(out), str(site)], check=True)


def outlined(draw, xy, text, fnt, fill, outline=(14, 16, 20), width=2, anchor="mm"):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor, stroke_width=width, stroke_fill=outline)


def sheet(renders: Path, output: Path, farm=False):
    labels = json.loads((renders / "labels.json").read_text())["items"]
    labels = {n: info for n, info in labels.items() if bool(info.get("farm")) == farm}  # (7.x: the farm's on its own sheet)
    cols, cell, caption, head = 6, 260, 66, 40
    rows = []
    for room, title in (FARM_ROOMS if farm else ROOMS):
        names = [n for n in sorted(labels) if labels[n]["room"] == room]
        if names:
            rows.append((title, names))
    height = 84 + sum(head + (cell + caption) * ((len(names) + cols - 1) // cols) for _, names in rows) + 40
    img = Image.new("RGB", (cols * cell + 32, height), (14, 16, 20))
    draw = ImageDraw.Draw(img)
    title = f"WALT'S FARM · THE FARM PIECES ({len(labels)} pieces)" if farm else f"THE FURNITURE ({len(labels)} pieces)"
    draw.text((16, 14), f"ZOMBIE DELIVERY 7.0 · MOVING PROTOTYPE · {title}", fill=(242, 242, 240), font=font(24, True))
    draw.text((16, 48), "class: HAND one hand · BOTH two hands, slower · PAIR two players (or drag it)    ★ sentimental (the client's must-have)"
              + ("    BIG DOOR: only through the barn doors" if farm else ""),
              fill=(150, 156, 166), font=font(14))
    y = 84
    for title, names in rows:
        draw.text((16, y + 10), title, fill=(215, 74, 70), font=font(17, True))
        y += head
        for i, name in enumerate(names):
            info = labels[name]
            x, top = 16 + (i % cols) * cell, y + (i // cols) * (cell + caption)
            picture = Image.open(renders / f"{name}.png").convert("RGB").resize((cell - 12, cell - 12), Image.LANCZOS)
            img.paste(picture, (x + 6, top))
            ty = top + cell - 6
            label = info["label"].upper()
            draw.text((x + 8, ty), label, fill=(240, 240, 236), font=font(15, True))
            if info["sentimental"]:
                draw.text((x + 12 + draw.textlength(label, font=font(15, True)), ty - 1), "★", fill=(250, 204, 60), font=font(16, True))
            cls = info["class"]
            line = f"{cls.upper()} · wt {info['weight']} · ${info['value']}"
            draw.text((x + 8, ty + 21), line, fill=CLASS_COLOR[cls], font=font(13, True))
            if info["fragile"]:
                draw.text((x + 14 + draw.textlength(line, font=font(13, True)), ty + 21), "FRAGILE", fill=(120, 190, 240), font=font(12, True))
            if info.get("bigDoor"):
                draw.text((x + 14 + draw.textlength(line, font=font(13, True)), ty + 21), "BIG DOOR", fill=(240, 150, 70), font=font(12, True))
            s = info["size"]
            draw.text((x + 8, ty + 40), f"{s[0]:g} × {s[1]:g} × {s[2]:g} studs · {info['parts']} parts", fill=(140, 146, 156), font=font(12))
        y += (cell + caption) * ((len(names) + cols - 1) // cols)
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output)
    print(f"Sheet: {len(labels)} pieces -> {output}")


def house(renders: Path, output: Path, key="house"):
    data = json.loads((renders / "labels.json").read_text())[key]
    info = data["info"]
    farm = key == "farm"
    top = Image.open(renders / f"{key}-top.png").convert("RGB")
    iso = Image.open(renders / f"{key}-iso.png").convert("RGB")
    head, foot, gap = 76, 150, 16
    width = top.width + iso.width + gap * 3
    img = Image.new("RGB", (width, head + max(top.height, iso.height) + foot), (14, 16, 20))
    img.paste(top, (gap, head))
    img.paste(iso, (gap * 2 + top.width, head))
    draw = ImageDraw.Draw(img)
    stars = [s for s in info["spots"] if s["star"]]
    place = "WALT'S FARM (chapter 1, Hold Your Horses)" if farm else "MARGE'S HOUSE (prologue)"
    draw.text((gap, 14), f"ZOMBIE DELIVERY 7.0 · {place} · seed {info['seed']}{' · mirrored' if info['mirrored'] else ''}",
              fill=(242, 242, 240), font=font(24, True))
    size = (info["max"][0] - info["min"][0], info["max"][2] - info["min"][2])
    exits = f" · {len(info.get('exits', []))} exits: the front door below, the barn doors (big loads) at the top" if farm else ", the front door below it"
    draw.text((gap, 48), f"{len(info['rooms'])} rooms · {len(info['spots'])} pieces ({len(stars)} ★) · {size[0]:.0f} × {size[1]:.0f} studs · "
              f"{info['parts']} parts with the furniture · the orange figure: a player (5.2 studs) at the entry{exits}",
              fill=(150, 156, 166), font=font(14))
    # the plan: room names, the ★ pieces
    names = dict(FARM_PLAN_ROOMS) if farm else {r: t for r, t in ROOMS}
    names["corridor"] = "CORRIDOR"
    for room in data["top"]["rooms"]:
        x, y = room["at"]
        outlined(draw, (gap + x, head + y), names.get(room["id"], room["id"].upper()), font(17, True), (250, 250, 246), width=3)
    big = {s["id"] for s in info["spots"] if s.get("bigDoor")}
    for spot in data["top"]["spots"]:
        if spot["star"] or spot["id"] in big:
            x, y = spot["at"]
            text, colour = ("★ " + spot["label"], (250, 204, 60)) if spot["star"] else (spot["label"] + " (big door)", (240, 150, 70))
            outlined(draw, (gap + x, head + y - 16), text, font(14, True), colour, width=3)
    for spot in data["iso"]["spots"]:
        if spot["star"]:
            x, y = spot["at"]
            outlined(draw, (gap * 2 + top.width + x, head + y - 30), "★", font(26, True), (250, 204, 60), width=3)
    draw.text((gap, head + top.height + 4), "FROM ABOVE (walls cut at 7.6 studs)", fill=(215, 74, 70), font=font(14, True))
    draw.text((gap * 2 + top.width, head + iso.height + 4), "3/4 CUTAWAY FROM THE FRONT (ceiling off, walls cut at 6.2)", fill=(215, 74, 70), font=font(14, True))
    # the pieces by room
    y = head + max(top.height, iso.height) + 30
    lines = []
    rooms_line = []
    for room, title in (FARM_PLAN_ROOMS.items() if farm else ROOMS):
        pieces = [s for s in info["spots"] if s.get("room") == room]
        if pieces:
            rooms_line.append(f"{title}: " + ", ".join(("★ " if s["star"] else "") + s["label"] for s in pieces))
    text = "   ".join(rooms_line)
    # wrap to the picture's width
    words, line = text.split(" "), ""
    for word in words:
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=font(13)) > width - 2 * gap:
            lines.append(line)
            line = word
        else:
            line = trial
    lines.append(line)
    for n, line in enumerate(lines[:6]):
        draw.text((gap, y + n * 19), line, fill=(200, 204, 210), font=font(13))
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output)
    print(f"{'Farm' if farm else 'House'}: seed {info['seed']}, {len(info['spots'])} pieces -> {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("sheet", type=Path)
    parser.add_argument("house", type=Path)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--keep", type=Path, help="also keep the single renders in this folder")
    parser.add_argument("--farm-pieces", type=Path, help="7.x: also the farm's pieces' sheet here")
    parser.add_argument("--farm-interior", type=Path, help="7.x: also the farm from above and as a cutaway here")
    parser.add_argument("--farm-seed", type=int, default=1)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        farm = args.farm_pieces is not None or args.farm_interior is not None
        scenes = export(args.luau, tmp, args.seed, args.farm_seed if farm else None)
        out = args.keep or (tmp / "renders")
        render(scenes, args.three.resolve(), out)
        sheet(out, args.sheet)
        house(out, args.house)
        if args.farm_pieces:
            sheet(out, args.farm_pieces, farm=True)
        if args.farm_interior:
            house(out, args.farm_interior, key="farm")
