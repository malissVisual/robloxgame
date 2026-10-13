#!/usr/bin/env python3
"""7.0, the moving prototype: pictures of the furniture and of one house's inside, for the owner.

Builds every piece (shared/FurnitureLooks.luau) and a house (shared/HouseLayout.luau planned, server/HouseInterior.luau
built) with the real builders on the recorder (tools/fixtures/item-mock.luau over tools/vehicle-preview/roblox-mock.luau)
in the Luau CLI (export.luau), renders them with three.js in headless Chromium (render.mjs, render.html) and lays out:
  - a contact sheet of every piece by room: its name, class, weight, value, size, parts, ★ and fragile (--only: just
    these ids, e.g. the 7.x alpine pieces);
  - the house from straight above (a floor plan, the rooms named, the ★ pieces marked) beside a 3/4 cutaway;
  - 7.x alpine, --inside PNG: the house at eye level (the living room's Kachelofen, the kitchen's corner bench, the hall
    toward the front door, the bedroom's wall) over the 3/4 cutaway.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/furniture/render.py <luau> <three.module.min.js> \\
        <furniture-sheet.png> <house-interior.png> [--seed N] [--keep DIR] [--only ID,ID] [--inside PNG]

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
MOCKED = ("FurnitureLooks", "HouseLayout")
ROOMS = (("living", "LIVING ROOM"), ("kitchen", "KITCHEN"), ("bedroom", "BEDROOM"), ("kids", "KID'S ROOM"),
         ("bath", "BATHROOM"), ("hall", "HALL"), ("garage", "GARAGE"))
CLASS_COLOR = {"hand": (126, 196, 120), "both": (240, 180, 70), "pair": (232, 96, 84)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans{}.ttf"


def font(size, bold=False):
    return ImageFont.truetype(FONT.format("-Bold" if bold else ""), size)


def export(luau: str, tmp: Path, seed: int) -> Path:
    for source in SHARED.glob("*.luau"):
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
        (tmp / source.name).write_text(PREFIX + text if source.stem in MOCKED else text)
    text = (ROOT / "src/server/HouseInterior.luau").read_text()
    text = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', text)
    (tmp / "HouseInterior.luau").write_text(PREFIX + "local game = M.game\n" + text)
    shutil.copy(ROOT / "tools/vehicle-preview/roblox-mock.luau", tmp / "rbxmock.luau")
    shutil.copy(ROOT / "tools/fixtures/item-mock.luau", tmp / "ItemMock.luau")
    shutil.copy(HERE / "export.luau", tmp / "export.luau")
    result = subprocess.run([str(Path(luau).resolve()), "export.luau", "-a", str(seed)], cwd=tmp, capture_output=True, text=True)
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
    house = next(json.loads(line) for line in scenes.read_text().splitlines() if '"kind":"house"' in line)
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


def sheet(renders: Path, output: Path, only: list | None = None):
    labels = json.loads((renders / "labels.json").read_text())["items"]
    cols, cell, caption, head = 6, 260, 66, 40
    rows = []
    if only:
        # just these, in one grid in catalogue order, each captioned with its room
        labels = {name: info for name, info in labels.items() if info["id"] in only}
        cols = min(cols, 4, len(labels)) or 1
        rooms = dict(ROOMS)
        rows.append(("BY ROOM: " + " · ".join(sorted({rooms[info["room"]] for info in labels.values()})), sorted(labels)))
    for room, title in ROOMS if not only else ():
        names = [n for n in sorted(labels) if labels[n]["room"] == room]
        if names:
            rows.append((title, names))
    height = 84 + sum(head + (cell + caption) * ((len(names) + cols - 1) // cols) for _, names in rows) + 40
    img = Image.new("RGB", (cols * cell + 32, height), (14, 16, 20))
    draw = ImageDraw.Draw(img)
    title = f"THE ALPINE PIECES ({len(labels)})" if only else f"THE FURNITURE ({len(labels)} pieces)"
    draw.text((16, 14), f"ZOMBIE DELIVERY · MOVING · {title}", fill=(242, 242, 240), font=font(24, True))
    draw.text((16, 48), "HAND one hand · BOTH two hands, slower · PAIR two players (or drag it)    ★ sentimental (a ★ candidate)",
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
            s = info["size"]
            where, unit = (f"{info['room']} · ", "") if only else ("", " studs")
            draw.text((x + 8, ty + 40), f"{where}{s[0]:g} × {s[1]:g} × {s[2]:g}{unit} · {info['parts']} parts", fill=(140, 146, 156), font=font(12))
        y += (cell + caption) * ((len(names) + cols - 1) // cols)
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output)
    print(f"Sheet: {len(labels)} pieces -> {output}")


def house(renders: Path, output: Path):
    data = json.loads((renders / "labels.json").read_text())["house"]
    info = data["info"]
    top = Image.open(renders / "house-top.png").convert("RGB")
    iso = Image.open(renders / "house-iso.png").convert("RGB")
    head, foot, gap = 76, 150, 16
    width = top.width + iso.width + gap * 3
    img = Image.new("RGB", (width, head + max(top.height, iso.height) + foot), (14, 16, 20))
    img.paste(top, (gap, head))
    img.paste(iso, (gap * 2 + top.width, head))
    draw = ImageDraw.Draw(img)
    stars = [s for s in info["spots"] if s["star"]]
    draw.text((gap, 14), f"ZOMBIE DELIVERY 7.0 · MARGE'S HOUSE (prologue) · seed {info['seed']}{' · mirrored' if info['mirrored'] else ''}",
              fill=(242, 242, 240), font=font(24, True))
    size = (info["max"][0] - info["min"][0], info["max"][2] - info["min"][2])
    draw.text((gap, 48), f"{len(info['rooms'])} rooms · {len(info['spots'])} pieces ({len(stars)} ★) · {size[0]:.0f} × {size[1]:.0f} studs · "
              f"{info['parts']} parts with the furniture · the orange figure: a player (5.2 studs) at the entry, the front door below it",
              fill=(150, 156, 166), font=font(14))
    # the plan: room names, the ★ pieces
    names = {r: t for r, t in ROOMS}
    names["corridor"] = "CORRIDOR"
    for room in data["top"]["rooms"]:
        x, y = room["at"]
        outlined(draw, (gap + x, head + y), names.get(room["id"], room["id"].upper()), font(17, True), (250, 250, 246), width=3)
    for spot in data["top"]["spots"]:
        if spot["star"]:
            x, y = spot["at"]
            outlined(draw, (gap + x, head + y - 16), "★ " + spot["label"], font(14, True), (250, 204, 60), width=3)
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
    for room, title in ROOMS:
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
    print(f"House: seed {info['seed']}, {len(info['spots'])} pieces -> {output}")


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
    parser.add_argument("--inside", type=Path, help="7.x alpine: the house at eye level into this picture")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        scenes = export(args.luau, tmp, args.seed)
        out = args.keep or (tmp / "renders")
        views = inside_views(scenes) if args.inside else None
        render(scenes, args.three.resolve(), out, views)
        sheet(out, args.sheet, args.only.split(",") if args.only else None)
        house(out, args.house)
        if args.inside:
            inside(out, views, args.inside)
