#!/usr/bin/env python3
"""7.0, the moving prototype: pictures of the furniture and of one house's inside, for the owner.

Builds every piece (shared/FurnitureLooks.luau) and a house (shared/HouseLayout.luau planned, server/HouseInterior.luau
built) with the real builders on the recorder (tools/fixtures/item-mock.luau over tools/vehicle-preview/roblox-mock.luau)
in the Luau CLI (export.luau), renders them with three.js in headless Chromium (render.mjs, render.html) and lays out:
  - a contact sheet of every piece by room: its name, class, weight, value, size, parts, ★ and fragile (--only: just
    these ids, e.g. the 7.x alpine pieces, under --title; 8.0: a collectible's rarity in its picture's corner);
  - the house from straight above (a floor plan, the rooms named, the ★ pieces marked, 8.0: the collectibles ◆ in their
    rarity's colour) beside a 3/4 cutaway;
  - 7.x alpine, --inside PNG: the house at eye level (the living room's Kachelofen, the kitchen's corner bench, the hall
    toward the front door, the bedroom's wall) over the 3/4 cutaway.
7.x the farm: with --farm-pieces and/or --farm-interior also Walt's farm (shared/Layouts/Farm.luau): the farm's pieces
on a sheet of their own (by the farm's rooms; the house's sheet keeps the house's), the farm from above and as a 3/4
cutaway (the hay wagon, the one big-door piece, marked).

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/furniture/render.py <luau> <three.module.min.js> \\
        <furniture-sheet.png> <house-interior.png> [--seed N] [--keep DIR] [--only ID,ID] [--title TEXT] [--inside PNG] \\
        [--farm-pieces farm-pieces.png] [--farm-interior farm-interior.png] [--farm-seed N]

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Playwright and
Chromium as for the other previews (CHROMIUM overrides /opt/pw-browsers/chromium).
"""
import argparse
import json
import math
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
# 8.0 collectibles: a piece's rarity, its tag on the sheet
RARITY_COLOR = {"uncommon": (120, 210, 120), "rare": (96, 168, 255), "epic": (196, 120, 250), "legendary": (255, 178, 52)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans{}.ttf"


def font(size, bold=False):
    return ImageFont.truetype(FONT.format("-Bold" if bold else ""), size)


def export(luau: str, tmp: Path, seed: int, farm_seed=None) -> Path:
    for source in list(SHARED.glob("*.luau")) + list(SHARED.glob("Layouts/*.luau")):  # (7.x: the farm's layout too)
        text = re.sub(r"require\(script\.Parent\.(?:Parent\.|Layouts\.)?(\w+)\)", r'require("./\1")', source.read_text())
        (tmp / source.name).write_text(PREFIX + text if source.stem in MOCKED else text)
    text = (ROOT / "src/server/HouseInterior.luau").read_text()
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', text)
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text)
    (tmp / "HouseInterior.luau").write_text(PREFIX + "local game = M.game\n" + text)
    # (its server/FurnitureMesh.luau: no Blender import in the recorder, so the pictures show FurnitureLooks' own look)
    text = (ROOT / "src/server/FurnitureMesh.luau").read_text()
    text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', text)
    (tmp / "FurnitureMesh.luau").write_text(PREFIX + "local game, workspace = M.game, M.workspace\n" + text)
    # 8.9.1: HouseInterior's server/FixtureMesh.luau (the owner's Blender fixtures), a ServerStorage of its own: no
    # fixtures import here, so the fixtures keep their parts (tools/fixtures-art/check.py dresses them with one)
    text = (ROOT / "src/server/FixtureMesh.luau").read_text()
    text = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', text)
    (tmp / "FixtureMesh.luau").write_text(PREFIX + 'local storage = M.Instance.new("Folder")\n'
                                          'local game = { GetService = function(_, name) if name == "ServerStorage" then return storage end return M.game:GetService(name) end }\n'
                                          "local workspace = M.workspace\n" + text)
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


def render(scenes: Path, three: Path, out: Path, views: list | None = None):
    site = scenes.parent / "site"
    site.mkdir(exist_ok=True)
    shutil.copy(HERE / "render.html", site / "render.html")
    shutil.copy(three, site / "three.module.min.js")
    command = ["node", str(HERE / "render.mjs"), str(scenes), str(out), str(site)]
    if views:
        (scenes.parent / "views.json").write_text(json.dumps(views))
        command.append(str(scenes.parent / "views.json"))
    subprocess.run(command, check=True)


def inside_views(scenes: Path) -> list:
    """7.x alpine: where to stand and look for the eye-level pictures (the plan's frame: +Z into the house)."""
    house = next(json.loads(line) for line in scenes.read_text().splitlines()
                 if '"kind":"house"' in line and '"layout":"farm"' not in line)  # (the house's, not the farm's)
    info = house["info"]
    rooms = {r["id"]: r for r in info["rooms"]}
    fixtures = info["fixtures"]
    eye_y = 5.4

    def clamp(room, x, z, margin=1.5):
        r = rooms[room]
        return [min(max(x, r["min"][0] + margin), r["max"][0] - margin), eye_y, min(max(z, r["min"][2] + margin), r["max"][2] - margin)]

    def facing(f):  # the way a fixture faces into its room (its front, -Z, turned)
        a = math.radians(f["turn"])
        return -math.sin(a), -math.cos(a)

    def first(kind):
        return next((f for f in fixtures if f["kind"] == kind), None)

    views = []
    stove = first("kachelofen")
    if stove:
        # from the room's corner farthest from the stove and the antlers, at the two of them
        p, r = stove["position"], rooms[stove["room"]]
        antlers = next((f for f in fixtures if f["kind"] == "antlers" and f["room"] == stove["room"]), None)
        q = antlers["position"] if antlers else p
        mx, mz = (p[0] + q[0]) / 2, (p[2] + q[2]) / 2
        corners = [(x, z) for x in (r["min"][0], r["max"][0]) for z in (r["min"][2], r["max"][2])]
        cx, cz = max(corners, key=lambda c: (c[0] - p[0]) ** 2 + (c[1] - p[2]) ** 2 + (c[0] - q[0]) ** 2 + (c[1] - q[2]) ** 2)
        views.append({"name": "living", "title": "THE STUBE: THE KACHELOFEN, THE ANTLERS, THE BEAMS",
                      "eye": clamp(stove["room"], cx, cz, 2.5), "target": [mx, 5.0, mz]})
    shelf = first("corner_shelf")
    if shelf:
        p, s, a = shelf["position"], shelf["size"], math.radians(shelf["turn"])
        # its corner: (+X, +Z) of its frame
        cx = p[0] + math.cos(a) * s[0] / 2 + math.sin(a) * s[2] / 2
        cz = p[2] - math.sin(a) * s[0] / 2 + math.cos(a) * s[2] / 2
        r = rooms[shelf["room"]]
        mx, mz = (r["min"][0] + r["max"][0]) / 2, (r["min"][2] + r["max"][2]) / 2
        views.append({"name": "kitchen", "title": "THE KITCHEN: CORNER BENCH, HERRGOTTSWINKEL",
                      "eye": clamp(shelf["room"], cx + (mx - cx) * 0.8, cz + (mz - cz) * 0.8), "target": [cx, 3.8, cz]})
    hall = rooms.get("hall")
    if hall:
        views.append({"name": "hall", "title": "THE HALL: THE FRONT DOOR'S PAINTED LEAVES",
                      "eye": [0, eye_y, hall["max"][2] - 1.5], "target": [0, 4.4, -4]})
    picture = next((f for f in fixtures if f["kind"] == "picture" and f["room"] == "bedroom"), None)
    if picture:
        p, (dx, dz) = picture["position"], facing(picture)
        views.append({"name": "bedroom", "title": "THE BEDROOM: AN ALPINE PICTURE OVER THE PANELLING",
                      "eye": clamp(picture["room"], p[0] + dx * 14 + dz * 4, p[2] + dz * 14 - dx * 4), "target": [p[0], 6.4, p[2]]})
    return views


def outlined(draw, xy, text, fnt, fill, outline=(14, 16, 20), width=2, anchor="mm"):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor, stroke_width=width, stroke_fill=outline)


def sheet(renders: Path, output: Path, farm=False, only: list | None = None, title: str | None = None):
    labels = json.loads((renders / "labels.json").read_text())["items"]
    if not only:
        labels = {n: info for n, info in labels.items() if bool(info.get("farm")) == farm}  # (7.x: the farm's on its own sheet)
    cols, cell, caption, head = 6, 260, 66, 40
    rows = []
    if only:
        # just these, in one grid in catalogue order, each captioned with its room
        labels = {name: info for name, info in labels.items() if info["id"] in only}
        cols = min(cols, 4, len(labels)) or 1
        rooms = dict(FARM_ROOMS) | dict(ROOMS)
        rows.append(("BY ROOM: " + " · ".join(sorted({rooms.get(info["room"], info["room"].upper()) for info in labels.values()})), sorted(labels)))
    for room, title in (FARM_ROOMS if farm else ROOMS) if not only else ():
        names = [n for n in sorted(labels) if labels[n]["room"] == room]
        if names:
            rows.append((title, names))
    height = 84 + sum(head + (cell + caption) * ((len(names) + cols - 1) // cols) for _, names in rows) + 40
    img = Image.new("RGB", (cols * cell + 32, height), (14, 16, 20))
    draw = ImageDraw.Draw(img)
    if title:
        title = f"{title.upper()} ({len(labels)})"
    elif only:
        title = f"THE ALPINE PIECES ({len(labels)})"
    elif farm:
        title = f"WALT'S FARM · THE FARM PIECES ({len(labels)} pieces)"
    else:
        title = f"THE FURNITURE ({len(labels)} pieces)"
    draw.text((16, 14), f"ZOMBIE DELIVERY · MOVING · {title}", fill=(242, 242, 240), font=font(24, True))
    draw.text((16, 48), "HAND one hand · BOTH two hands, slower · PAIR two players (or drag it)    ★ sentimental (a ★ candidate)"
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
            if info.get("rarity"):  # (8.0 collectibles: the rarity in the picture's corner)
                outlined(draw, (x + 12, top + 8), info["rarity"].upper(), font(14, True), RARITY_COLOR.get(info["rarity"], (240, 240, 236)), anchor="la")
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
            where, unit = (f"{info['room']} · ", "") if only else ("", " studs")
            draw.text((x + 8, ty + 40), f"{where}{s[0]:g} × {s[1]:g} × {s[2]:g}{unit} · {info['parts']} parts", fill=(140, 146, 156), font=font(12))
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
    rarity_of = {s["id"]: s.get("rarity") for s in info["spots"]}  # (8.0 collectibles: marked in their rarity's colour)
    for spot in data["top"]["spots"]:
        rarity = rarity_of.get(spot["id"])
        if spot["star"] or spot["id"] in big or rarity:
            x, y = spot["at"]
            if spot["star"]:
                text, colour = "★ " + spot["label"], (250, 204, 60)
            elif rarity:
                text, colour = f"◆ {spot['label']} ({rarity})", RARITY_COLOR.get(rarity, (240, 240, 236))
            else:
                text, colour = spot["label"] + " (big door)", (240, 150, 70)
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
            rooms_line.append(f"{title}: " + ", ".join(("★ " if s["star"] else "◆ " if s.get("rarity") else "") + s["label"] for s in pieces))
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


def inside(renders: Path, views: list, output: Path):
    """7.x alpine: the eye-level views two by two, the 3/4 cutaway under them."""
    data = json.loads((renders / "labels.json").read_text())["house"]
    info = data["info"]
    shots = [(v, Image.open(renders / f"inside-{v['name']}.png").convert("RGB")) for v in views]
    cell_w, cell_h = 900, 600
    gap, head, caption = 16, 76, 30
    rows = (len(shots) + 1) // 2
    iso = Image.open(renders / "house-iso.png").convert("RGB")
    iso = iso.resize((2 * cell_w + gap, int(iso.height * (2 * cell_w + gap) / iso.width)), Image.LANCZOS)
    width = 2 * cell_w + 3 * gap
    height = head + rows * (cell_h + caption + gap) + iso.height + caption + gap
    img = Image.new("RGB", (width, height), (14, 16, 20))
    draw = ImageDraw.Draw(img)
    draw.text((gap, 14), f"ZOMBIE DELIVERY 7.x · MARGE'S HOUSE AS A CHALET · seed {info['seed']}{' · mirrored' if info['mirrored'] else ''}",
              fill=(242, 242, 240), font=font(24, True))
    draw.text((gap, 48), f"{len(info['spots'])} pieces · {info['parts']} parts with the furniture · eye level (5.4 studs), the ceiling lights on",
              fill=(150, 156, 166), font=font(14))
    for n, (view, shot) in enumerate(shots):
        x = gap + (n % 2) * (cell_w + gap)
        y = head + (n // 2) * (cell_h + caption + gap)
        img.paste(shot.resize((cell_w, cell_h), Image.LANCZOS), (x, y))
        draw.text((x, y + cell_h + 6), view["title"], fill=(215, 74, 70), font=font(15, True))
    y = head + rows * (cell_h + caption + gap)
    img.paste(iso, (gap, y))
    draw.text((gap, y + iso.height + 6), "3/4 CUTAWAY FROM THE FRONT (ceiling off, walls cut at 6.2: the beams and the wall decor above the cut)",
              fill=(215, 74, 70), font=font(15, True))
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output)
    print(f"Inside: seed {info['seed']}, {len(shots)} views -> {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("sheet", type=Path)
    parser.add_argument("house", type=Path)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--keep", type=Path, help="also keep the single renders in this folder")
    parser.add_argument("--only", help="the contact sheet of just these piece ids (comma separated)")
    parser.add_argument("--title", help="8.0: the --only sheet's title (default: the alpine pieces)")
    parser.add_argument("--inside", type=Path, help="7.x alpine: the house at eye level into this picture")
    parser.add_argument("--farm-pieces", type=Path, help="7.x: also the farm's pieces' sheet here")
    parser.add_argument("--farm-interior", type=Path, help="7.x: also the farm from above and as a cutaway here")
    parser.add_argument("--farm-seed", type=int, default=1)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        farm = args.farm_pieces is not None or args.farm_interior is not None
        scenes = export(args.luau, tmp, args.seed, args.farm_seed if farm else None)
        out = args.keep or (tmp / "renders")
        views = inside_views(scenes) if args.inside else None
        render(scenes, args.three.resolve(), out, views)
        sheet(out, args.sheet, only=args.only.split(",") if args.only else None, title=args.title)
        house(out, args.house)
        if args.inside:
            inside(out, views, args.inside)
        if args.farm_pieces:
            sheet(out, args.farm_pieces, farm=True)
        if args.farm_interior:
            house(out, args.farm_interior, key="farm")
