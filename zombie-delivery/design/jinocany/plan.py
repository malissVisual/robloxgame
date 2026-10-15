#!/usr/bin/env python3
"""Jinočany instead of the Alps (design/jinocany/NAVRH.md): the proposed sandbox map as plain data and a picture.

Writes, next to this file:
  plan.json   every road, lot, house, landmark, field and tree line of the proposal, in SandboxMap's units and axes
              (studs; x east, z south: -z is north; a spot's yaw as SandboxMap's: 0 looks north, 90 west, 180 south,
              270 east; a curb is the van's pivot as SandboxMap.House.curb: the Sprinter (22 long) across the road,
              its back 2 studs in from the house's edge of it, its nose away from the door)
  plan.png    the same seen from above, north up, with the owner's labels in Czech

The fixed data of today's sandbox (shared/SandboxMap.luau: the four plots and their warehouses, Depot Row, Main Street,
the turnaround and the big house) is copied here unchanged: the village is laid round it. Nothing in the game reads
this file; it is a plan. Deterministic (no dice): the same output on every run.

    python3 design/jinocany/plan.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

# ── The world ──────────────────────────────────────────────────────────────────────────────────────────────────────

BOUNDS = {"x0": -1180, "x1": 420, "z0": -680, "z1": 760}

# Today's sandbox (shared/SandboxMap.luau), unchanged.
PLOT_X = [-195, -65, 65, 195]
PLOTS = [{"id": i + 1, "rect": {"x0": x - 60, "x1": x + 60, "z0": -230, "z1": -78},
          "warehouse": {"x": x, "z": -160, "sx": 80, "sz": 60}} for i, x in enumerate(PLOT_X)]
TURNAROUND = {"x": 0, "z": 470, "r": 34}
BIG_HOUSE = {"id": "sandbox_house", "lot": {"x0": -60, "x1": 60, "z0": 504, "z1": 600},
             "house": {"x": 0, "z": 540, "sx": 44, "sz": 34}, "door": {"x": 0, "z": 523, "yaw": 0},
             "curb": {"x": 0, "z": 492, "yaw": 0}}

# Roads: name, rect, step (1 the first map, 2 / 3 later), fixed (today's, unchanged).
ROADS = [
    ("Depot Row", -270, 270, -74, -46, 1, True),
    ("Pražská", -14, 14, -46, 470, 1, True),  # today's Main Street, renamed
    ("Hlavní", -1000, -270, -74, -46, 1, False),
    ("Hornická", -1180, -1000, -74, -46, 1, False),
    ("Školní", -572, -548, -470, -74, 1, False),
    ("Lidická", -392, -368, -470, -74, 1, False),
    ("Na Pouštce", -832, -808, -470, -74, 1, False),
    ("Severní", -1024, -300, -494, -470, 2, False),
    ("Žižkova", -1024, -1000, -500, -74, 2, False),
    ("Fibichova", -632, -608, -46, 300, 1, False),
    ("Smetanova", -460, -436, -46, 300, 1, False),
    ("Mirešická", -912, -14, 300, 324, 1, False),
    ("Tylova", -912, -888, -46, 300, 3, False),
    ("Čapkova", -1120, -912, 150, 174, 3, False),
]

# Landmarks: id, the owner's Czech label, the game's English name, rect, step, kind.
LANDMARKS = [
    ("green", "Náves s kaplí", "The Chapel Green", (-800, -584, -190, -80), 1, "green"),
    ("chapel", "kaple", "Chapel", (-712, -688, -164, -124), 1, "chapel"),
    ("drugstore", "drogerie", "Corner Drugstore", (40, 120, -20, 40), 1, "shop"),
    ("pond", "Malý rybník", "Little Pond", (50, 210, 145, 255), 1, "pond"),
    ("orchard", "ovocný sad", "The Orchard", (-400, -70, 20, 260), 1, "orchard"),
    ("school", "škola", "Jinočany School", (-536, -420, -380, -300), 2, "school"),
    ("pitch", "hřiště", "Village Pitch", (-790, -610, -440, -330), 2, "pitch"),
    ("hardware", "Stavebniny Sýkorka", "Sýkorka Building Supplies", (-990, -850, -630, -545), 2, "hardware"),
    ("hardware_lot", "parkoviště", "Car park", (-990, -850, -545, -505), 2, "lot"),
    ("site", "staveniště", "Building site", (-1150, -930, 190, 300), 3, "site"),
    ("d5", "dálnice D5 (kulisa)", "D5 Motorway", (330, 390, -680, 760), 1, "motorway"),
    ("railway", "železnice (kulisa)", "Railway", (-1180, 420, 694, 706), 3, "railway"),
    ("station", "zastávka Zbuzany", "Zbuzany stop", (150, 290, 672, 690), 3, "station"),
]

# Fields (the crops' colours on the ground): rect, kind.
FIELDS = [
    ((-1180, 420, -680, -505), "wheat"),
    ((-1180, -1030, -505, 360), "rapeseed"),
    ((-1180, -620, 340, 680), "rapeseed"),
    ((-620, -40, 340, 680), "ploughed"),
    ((-40, 330, 620, 680), "wheat"),
    ((-280, 330, -505, -250), "young"),
    ((230, 330, 60, 620), "young"),
    ((-1180, 420, 710, 760), "young"),
]
VILLAGE = (-1030, -280, -505, 330)  # the built-up area's gardens and lawns

# Tree lines and alleys: polyline, kind ("windbreak": a field's edge, "alley": fruit trees along a road out).
TREE_LINES = [
    ([(-1180, 340), (-40, 340)], "windbreak"),
    ([(-1040, -500), (-1040, 330)], "windbreak"),
    ([(-1180, -96), (-1030, -96)], "alley"),
    ([(-1180, -24), (-1030, -24)], "alley"),
    ([(-36, 330), (-36, 460)], "alley"),
    ([(36, 300), (36, 460)], "alley"),
    ([(-280, -505), (300, -505)], "windbreak"),
    ([(300, -505), (300, 660)], "windbreak"),
]

# ── The houses ─────────────────────────────────────────────────────────────────────────────────────────────────────

# Per street: which sides get houses, the house's kind, the spacing along it, the setback from the road's edge.
# kind: "old" a Czech family house with a garden (tiles), "row" terraced (groups of four), "modern" a new build (flat roof)
SIZES = {"old": (30, 24), "row": (18, 26), "modern": (28, 22)}
STREETS = [
    ("Hlavní", ("n", "s"), "old", 46, 12),
    ("Školní", ("w", "e"), "old", 44, 12),
    ("Lidická", ("w", "e"), "old", 44, 12),
    ("Na Pouštce", ("w", "e"), "old", 44, 12),
    ("Severní", ("s",), "old", 46, 12),
    ("Žižkova", ("e",), "old", 46, 12),
    ("Fibichova", ("w", "e"), "row", 18, 10),
    ("Smetanova", ("w", "e"), "row", 18, 10),
    ("Mirešická", ("n",), "old", 46, 12),
    ("Tylova", ("w",), "modern", 42, 12),
    ("Čapkova", ("n",), "modern", 42, 12),
]
ROW_GROUP, ROW_GAP = 4, 16  # terraced houses: four together, then a gap

# The six houses to empty in step 1 (the big house is today's, the rest the nearest house to these points).
ENTER_AT = [(-450, -100), (-700, -20), (-525, -230), (-345, -300), (-480, 160)]


def rect(x0, x1, z0, z1):
    return {"x0": x0, "x1": x1, "z0": z0, "z1": z1}


def hits(a, b, margin=0):
    return a["x0"] < b["x1"] + margin and b["x0"] < a["x1"] + margin and a["z0"] < b["z1"] + margin and b["z0"] < a["z1"] + margin


def inside(a, box):
    return a["x0"] >= box["x0"] and a["x1"] <= box["x1"] and a["z0"] >= box["z0"] and a["z1"] <= box["z1"]


def build():
    roads = [{"name": n, "rect": rect(x0, x1, z0, z1), "step": s, "fixed": f} for n, x0, x1, z0, z1, s, f in ROADS]
    landmarks = [{"id": i, "label": l, "name": n, "rect": rect(*r), "step": s, "kind": k} for i, l, n, r, s, k in LANDMARKS]
    blocked = [r["rect"] for r in roads] + [l["rect"] for l in landmarks if l["kind"] not in ("motorway",)]
    blocked += [p["rect"] for p in PLOTS] + [BIG_HOUSE["lot"], rect(-280, 330, -250, 330)]  # the zone and Pražská's side
    by_name = {r["name"]: r for r in roads}
    houses = []
    for street, sides, kind, step_along, setback in STREETS:
        road = by_name[street]
        r = road["rect"]
        w, d = SIZES[kind]
        along_x = (r["x1"] - r["x0"]) > (r["z1"] - r["z0"])
        lo, hi = (r["x0"], r["x1"]) if along_x else (r["z0"], r["z1"])
        for side in sides:
            n, t = 0, lo + 30 + w / 2
            while t <= hi - 30 - w / 2:
                if along_x:
                    cx = t
                    cz = r["z0"] - setback - d / 2 if side == "n" else r["z1"] + setback + d / 2
                    box = rect(cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2)
                    yaw = 180 if side == "n" else 0
                    door = {"x": cx, "z": box["z1"] if side == "n" else box["z0"], "yaw": yaw}
                    curb = {"x": cx, "z": r["z0"] + 13 if side == "n" else r["z1"] - 13, "yaw": yaw}
                else:
                    cz = t
                    cx = r["x0"] - setback - d / 2 if side == "w" else r["x1"] + setback + d / 2
                    box = rect(cx - d / 2, cx + d / 2, cz - w / 2, cz + w / 2)
                    yaw = 270 if side == "w" else 90
                    door = {"x": box["x1"] if side == "w" else box["x0"], "z": cz, "yaw": yaw}
                    curb = {"x": r["x0"] + 13 if side == "w" else r["x1"] - 13, "z": cz, "yaw": yaw}
                gap = 0
                if kind == "row":
                    n += 1
                    gap = ROW_GAP if n % ROW_GROUP == 0 else 0
                ok = inside(box, rect(VILLAGE[0] - 120, VILLAGE[1], VILLAGE[2], VILLAGE[3]))
                ok = ok and not any(hits(box, b, 4) for b in blocked)
                ok = ok and not any(hits(box, h["box"], 0 if kind == "row" else 6) for h in houses)
                if ok:
                    houses.append({"id": f"{street}_{side}_{len(houses) + 1}", "street": street, "kind": kind, "box": box,
                                   "yaw": yaw, "door": door, "curb": curb, "step": road["step"], "enter": False})
                t += step_along + gap
    # the houses to empty in step 1: today's big house first, then the nearest to each point
    enter = [{"id": BIG_HOUSE["id"], "name": "The Old Farmstead", "label": "Statek (dnešní velký dům)", "kind": "big",
              "box": rect(-22, 22, 523, 557), "door": BIG_HOUSE["door"], "curb": BIG_HOUSE["curb"], "fixed": True}]
    for px, pz in ENTER_AT:
        best = min((h for h in houses if not h["enter"] and h["kind"] != "modern"),
                   key=lambda h: (((h["box"]["x0"] + h["box"]["x1"]) / 2 - px) ** 2 + ((h["box"]["z0"] + h["box"]["z1"]) / 2 - pz) ** 2))
        best["enter"] = True
        best["step"] = 1
        enter.append({"id": best["id"], "name": f"{best['street']} house", "label": f"dům, {best['street']}",
                      "kind": "house", "box": best["box"], "door": best["door"], "curb": best["curb"], "fixed": False})
    return roads, landmarks, houses, enter


# ── The picture ────────────────────────────────────────────────────────────────────────────────────────────────────

S = 1.2  # px per stud
PANEL = 560  # the legend's width
TOP = 130
W = int((BOUNDS["x1"] - BOUNDS["x0"]) * S) + PANEL
H = int((BOUNDS["z1"] - BOUNDS["z0"]) * S) + TOP + 20

COL = {
    "wheat": (196, 178, 92), "young": (110, 156, 66), "rapeseed": (226, 208, 62), "ploughed": (138, 104, 72),
    "village": (126, 170, 84), "asphalt": (52, 52, 56), "shoulder": (150, 142, 128), "concrete": (200, 197, 190),
    "warehouse": (150, 160, 172), "old": (176, 78, 56), "row": (194, 104, 64), "modern": (110, 114, 122),
    "big": (132, 54, 40), "water": (76, 140, 190), "pitch": (60, 150, 70), "tree": (40, 92, 40), "alley": (70, 124, 54),
    "green": (104, 160, 78), "label": (32, 32, 36), "accent": (240, 130, 40), "white": (250, 250, 250),
    "site": (178, 150, 110), "rail": (120, 112, 100), "embank": (108, 134, 74), "text2": (205, 205, 210),
}


def font(size, bold=False):
    for path in (f"/usr/share/fonts/opentype/inter/Inter-{'Bold' if bold else 'Medium'}.otf",
                 f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def P(x, z):
    return ((x - BOUNDS["x0"]) * S, (z - BOUNDS["z0"]) * S + TOP)


def R(r):
    a, b = P(r["x0"], r["z0"]), P(r["x1"], r["z1"])
    return [a[0], a[1], b[0], b[1]]


def tag(draw, x, y, text, sub=None, accent=False):
    f, fs = font(22, True), font(16)
    tw = max(draw.textlength(text, font=f), draw.textlength(sub, font=fs) if sub else 0)
    h = 34 + (22 if sub else 0)
    draw.rounded_rectangle([x, y, x + tw + 20, y + h], 6, fill=COL["accent"] if accent else COL["label"])
    draw.text((x + 10, y + 5), text, font=f, fill=COL["white"])
    if sub:
        draw.text((x + 10, y + 32), sub, font=fs, fill=COL["white"] if accent else COL["text2"])


def street_name(img, road):
    r = road["rect"]
    f = font(15, True)
    along_x = (r["x1"] - r["x0"]) > (r["z1"] - r["z0"])
    text = road["name"].upper()
    probe = ImageDraw.Draw(img)
    tw = int(probe.textlength(text, font=f)) + 8
    label = Image.new("RGBA", (tw, 20), (0, 0, 0, 0))
    ImageDraw.Draw(label).text((4, 1), text, font=f, fill=(235, 235, 235, 255))
    x0, y0, x1, y1 = R(r)
    if along_x:
        img.paste(label, (int((x0 + x1) / 2 - tw / 2), int((y0 + y1) / 2 - 10)), label)
    else:
        label = label.rotate(90, expand=True)
        img.paste(label, (int((x0 + x1) / 2 - 10), int((y0 + y1) / 2 - tw / 2)), label)


def picture(roads, landmarks, houses, enter, path):
    img = Image.new("RGB", (W, H), (36, 38, 42))
    draw = ImageDraw.Draw(img)
    # the ground: fields, then the village's gardens
    draw.rectangle(R(BOUNDS), fill=COL["young"])
    for (x0, x1, z0, z1), kind in FIELDS:
        box = R(rect(x0, x1, z0, z1))
        draw.rectangle(box, fill=COL[kind])
        for k in range(int(box[1]), int(box[3]), 9):  # the crop's rows
            shade = tuple(max(0, c - 14) for c in COL[kind])
            draw.line([box[0], k, box[2], k], fill=shade, width=2)
    draw.rectangle(R(rect(*VILLAGE)), fill=COL["village"])
    draw.rectangle(R(rect(-280, 330, -250, 330)), fill=COL["village"])
    # tree lines
    for points, kind in TREE_LINES:
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            n = max(1, int(math.hypot(bx - ax, bz - az) / (22 if kind == "alley" else 16)))
            for i in range(n + 1):
                cx, cy = P(ax + (bx - ax) * i / n, az + (bz - az) * i / n)
                rr = 7 if kind == "alley" else 9
                draw.ellipse([cx - rr + 3, cy - rr + 4, cx + rr + 3, cy + rr + 4], fill=(30, 50, 30))
                draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=COL[kind if kind == "alley" else "tree"])
    # landmarks under the roads
    for l in landmarks:
        box, k = R(l["rect"]), l["kind"]
        if k == "motorway":
            draw.rectangle([box[0] - 24, box[1], box[2] + 24, box[3]], fill=COL["embank"])
            draw.rectangle(box, fill=COL["asphalt"])
            mid = (box[0] + box[2]) / 2
            draw.line([mid, box[1], mid, box[3]], fill=(200, 200, 200), width=3)
            for y in range(int(box[1]), int(box[3]), 40):
                draw.line([box[0] + 15, y, box[0] + 15, y + 18], fill=(230, 230, 230), width=2)
                draw.line([box[2] - 15, y, box[2] - 15, y + 18], fill=(230, 230, 230), width=2)
            draw.line([box[0] - 10, box[1], box[0] - 10, box[3]], fill=(150, 150, 150), width=4)  # the noise wall
        elif k == "railway":
            draw.rectangle([box[0], box[1] - 4, box[2], box[3] + 4], fill=COL["rail"])
            for x in range(int(box[0]), int(box[2]), 8):
                draw.line([x, box[1] - 2, x, box[3] + 2], fill=(90, 70, 50), width=2)
            draw.line([box[0], box[1] + 3, box[2], box[1] + 3], fill=(60, 60, 64), width=2)
            draw.line([box[0], box[3] - 3, box[2], box[3] - 3], fill=(60, 60, 64), width=2)
        elif k == "orchard":
            draw.rectangle(box, fill=COL["green"])
            for gx in range(int(box[0]) + 16, int(box[2]) - 8, 34):
                for gy in range(int(box[1]) + 16, int(box[3]) - 8, 34):
                    draw.ellipse([gx - 9 + 2, gy - 9 + 3, gx + 9 + 2, gy + 9 + 3], fill=(40, 60, 36))
                    draw.ellipse([gx - 9, gy - 9, gx + 9, gy + 9], fill=COL["alley"])
        elif k == "pond":
            draw.ellipse(box, fill=COL["water"], outline=(60, 110, 60), width=6)
        elif k == "green":
            draw.rectangle(box, fill=COL["green"])
            for cx, cz in ((-790, -180), (-610, -180), (-790, -92), (-610, -92), (-760, -110), (-740, -175)):
                px, py = P(cx, cz)
                draw.ellipse([px - 11, py - 11, px + 11, py + 11], fill=COL["tree"])
            px, py = P(-640, -105)
            draw.line([px, py - 12, px, py + 12], fill=(240, 240, 240), width=4)
            draw.line([px - 7, py - 5, px + 7, py - 5], fill=(240, 240, 240), width=4)
        elif k == "chapel":
            draw.rectangle(box, fill=(236, 230, 214), outline=(90, 90, 96), width=3)
            draw.rectangle([box[0] + 6, box[1] - 10, box[2] - 6, box[1] + 10], fill=(90, 96, 104))
        elif k == "pitch":
            draw.rectangle(box, fill=COL["pitch"], outline=COL["white"], width=3)
            mx = (box[0] + box[2]) / 2
            draw.line([mx, box[1], mx, box[3]], fill=COL["white"], width=2)
            draw.ellipse([mx - 18, (box[1] + box[3]) / 2 - 18, mx + 18, (box[1] + box[3]) / 2 + 18], outline=COL["white"], width=2)
        elif k == "site":
            draw.rectangle(box, fill=COL["site"], outline=(230, 200, 60), width=3)
            for i in range(0, int(box[2] - box[0]), 26):
                draw.line([box[0] + i, box[3], box[0] + i + 20, box[1]], fill=(160, 132, 96), width=2)
        elif k == "lot":
            draw.rectangle(box, fill=(110, 110, 114))
            for x in range(int(box[0]) + 8, int(box[2]), 16):
                draw.line([x, box[1] + 4, x, box[1] + 22], fill=(220, 220, 220), width=1)
        elif k == "station":
            draw.rectangle(box, fill=(170, 170, 176), outline=(90, 90, 96), width=2)
        else:  # shop, school, hardware
            fill = {"shop": (210, 72, 86), "school": (196, 150, 90), "hardware": (120, 140, 160)}[k]
            draw.rectangle(box, fill=fill, outline=(40, 40, 44), width=3)
    # the zone's concrete and the plots
    for p in PLOTS:
        draw.rectangle(R(p["rect"]), fill=COL["concrete"])
        wh = p["warehouse"]
        draw.rectangle(R(rect(wh["x"] - wh["sx"] / 2, wh["x"] + wh["sx"] / 2, wh["z"] - wh["sz"] / 2, wh["z"] + wh["sz"] / 2)),
                       fill=COL["warehouse"], outline=(70, 76, 84), width=3)
    # roads (the shoulders, the asphalt, the turnaround)
    for road in roads:
        x0, y0, x1, y1 = R(road["rect"])
        draw.rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 4], fill=COL["shoulder"])
    tx, ty = P(TURNAROUND["x"], TURNAROUND["z"])
    tr = TURNAROUND["r"] * S
    draw.ellipse([tx - tr - 4, ty - tr - 4, tx + tr + 4, ty + tr + 4], fill=COL["shoulder"])
    for road in roads:
        draw.rectangle(R(road["rect"]), fill=COL["asphalt"])
    draw.ellipse([tx - tr, ty - tr, tx + tr, ty + tr], fill=COL["asphalt"])
    # the big house's lot and house
    draw.rectangle(R(BIG_HOUSE["lot"]), fill=(150, 190, 110), outline=(200, 200, 190), width=2)
    # houses
    for h in houses:
        draw.rectangle(R(h["box"]), fill=COL[h["kind"]], outline=(60, 34, 28), width=2)
        if h["kind"] in ("old", "row"):  # the ridge
            b = R(h["box"])
            if h["yaw"] in (0, 180):
                draw.line([b[0] + 3, (b[1] + b[3]) / 2, b[2] - 3, (b[1] + b[3]) / 2], fill=(120, 50, 36), width=2)
            else:
                draw.line([(b[0] + b[2]) / 2, b[1] + 3, (b[0] + b[2]) / 2, b[3] - 3], fill=(120, 50, 36), width=2)
    draw.rectangle(R(enter[0]["box"]), fill=COL["big"], outline=(60, 30, 24), width=3)
    for road in roads:
        street_name(img, road)
    draw = ImageDraw.Draw(img)
    # the houses to empty (step 1): an orange ring and their number
    fn = font(20, True)
    for i, e in enumerate(enter):
        b = R(e["box"])
        draw.rectangle([b[0] - 5, b[1] - 5, b[2] + 5, b[3] + 5], outline=COL["accent"], width=5)
        cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        draw.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=COL["accent"], outline=COL["white"], width=2)
        draw.text((cx, cy), str(i + 1), font=fn, fill=COL["white"], anchor="mm")
    # labels
    def at(x, z, dx=0, dy=0):
        px, py = P(x, z)
        return px + dx, py + dy
    for p in PLOTS:
        x, y = at(p["warehouse"]["x"], p["warehouse"]["z"], -36, -18)
        draw.text((x, y), f"SKLAD {p['id']}", font=font(16, True), fill=(30, 34, 40))
    tag(draw, *at(-270, -300, 0, -70), "Haly u D5 = 4 sklady ZDC", "pozemky, sklady i dodávky jako dnes")
    tag(draw, *at(-790, -260, 0, 0), "Náves s kaplí a křížem", "střed vesnice, nástěnka zakázek")
    tag(draw, *at(80, 470, 0, -10), "Statek = dnešní velký dům", "na konci Pražské, u polí")
    tag(draw, *at(60, 260, 0, 6), "Malý rybník")
    tag(draw, *at(130, 40, 0, 4), "Drogerie (vymyšlený obchod)")
    tag(draw, *at(-536, -380, 0, -46), "Škola · krok 2", "velké stěhování pro 2+ hráče")
    tag(draw, *at(-790, -440, 0, -46), "Hřiště · krok 2")
    tag(draw, *at(-840, -630, 10, -44), "Stavebniny Sýkorka · krok 2", "místo Ptáčka: barvy a výbava dodávky")
    tag(draw, *at(-1150, 300, 0, 10), "Nová zástavba · krok 3", "lidé se nastěhovávají")
    tag(draw, *at(150, 690, -300, -60), "Železnice a zastávka Zbuzany · krok 3")
    tag(draw, *at(300, -660, -330, 0), "D5: kulisa, jezdí po ní auta")
    tag(draw, *at(-1175, 10, 0, 6), "Hornická: konec mapy", "ROAD CLOSED")
    tag(draw, *at(-330, 120, 0, 0), "Ovocný sad", "kulisa, schované předměty")
    tag(draw, *at(-1150, 420, 0, 0), "Pole: řepka, obilí, oranice", "rovina místo hor")
    # title
    draw.rectangle([0, 0, W, TOP - 10], fill=(28, 30, 34))
    draw.text((24, 16), "ZOMBIE DELIVERY · JINOČANY MÍSTO ALP (NÁVRH)", font=font(40, True), fill=COL["white"])
    draw.text((24, 70), "Mapa sandboxu shora, sever nahoře. Sklady, Depot Row, Pražská (dnešní Main Street) a velký dům "
              "zůstávají přesně na místě; vesnice se staví kolem nich.", font=font(20), fill=COL["text2"])
    # the legend
    lx = W - PANEL + 24
    y = TOP + 10
    draw.text((lx, y), "LEGENDA", font=font(26, True), fill=COL["white"])
    y += 44
    rows = [
        (COL["accent"], "1–6  domy ke stěhování v kroku 1"),
        (COL["old"], "rodinné domy se zahradou (staré jádro)"),
        (COL["row"], "řadové domy (Fibichova, Smetanova)"),
        (COL["modern"], "nové domy (krok 3)"),
        (COL["warehouse"], "sklady ZDC hráčů (beze změny)"),
        (COL["asphalt"], "silnice (názvy ulic jako v Jinočanech)"),
        (COL["rapeseed"], "řepka"), (COL["wheat"], "obilí"), (COL["ploughed"], "oranice"),
        (COL["tree"], "stromořadí, ovocné aleje"),
    ]
    for colour, text in rows:
        draw.rectangle([lx, y + 3, lx + 26, y + 23], fill=colour, outline=(20, 20, 20))
        draw.text((lx + 38, y + 2), text, font=font(18), fill=COL["white"])
        y += 32
    y += 14
    draw.text((lx, y), "DOMY KE STĚHOVÁNÍ (KROK 1)", font=font(20, True), fill=COL["white"])
    y += 34
    for i, e in enumerate(enter):
        draw.text((lx, y), f"{i + 1}  {e['label']}", font=font(18), fill=COL["white"])
        y += 28
    y += 14
    draw.text((lx, y), "KROKY", font=font(20, True), fill=COL["white"])
    y += 34
    for line in ("1  Hlavní, náves, staré jádro, řadovky,", "    6 domů ke stěhování, D5 a pole",
                 "2  Severní, Žižkova, škola, hřiště,", "    Stavebniny Sýkorka, další domy",
                 "3  nová zástavba (nastěhování),", "    vlak a zastávka Zbuzany"):
        draw.text((lx, y), line, font=font(18), fill=COL["white"])
        y += 27
    y += 14
    stats = f"{len(houses) + 1} domů ve vesnici, {len(enter)} ke stěhování v kroku 1"
    draw.text((lx, y), stats, font=font(17), fill=COL["text2"])
    y += 26
    draw.text((lx, y), f"mapa {BOUNDS['x1'] - BOUNDS['x0']} × {BOUNDS['z1'] - BOUNDS['z0']} studů (dnes 680 × 920)",
              font=font(17), fill=COL["text2"])
    # the scale bar and north
    bx, by = W - PANEL + 24, H - 90
    draw.line([bx, by, bx + 100 * S, by], fill=COL["white"], width=4)
    draw.line([bx, by - 8, bx, by + 8], fill=COL["white"], width=3)
    draw.line([bx + 100 * S, by - 8, bx + 100 * S, by + 8], fill=COL["white"], width=3)
    draw.text((bx, by + 12), "100 studů", font=font(16), fill=COL["white"])
    nx, ny = W - 80, H - 100
    draw.polygon([(nx, ny - 34), (nx - 16, ny + 10), (nx + 16, ny + 10)], fill=COL["accent"])
    draw.text((nx, ny + 28), "S", font=font(22, True), fill=COL["white"], anchor="mm")
    draw.text((W - PANEL + 24, H - 40), "Nakresleno z plan.json (design/jinocany/plan.py). Nic z toho zatím není ve hře.",
              font=font(14), fill=COL["text2"])
    img.save(path, optimize=True)


def check(roads, houses, enter):
    """Every house's van spot: the Sprinter's back and nose on asphalt, its back nearer the door. Returns the failures."""
    def on_road(x, z):
        t = TURNAROUND
        return any(r["rect"]["x0"] <= x <= r["rect"]["x1"] and r["rect"]["z0"] <= z <= r["rect"]["z1"] for r in roads) \
            or math.hypot(x - t["x"], z - t["z"]) <= t["r"]
    bad = []
    seen = set()
    for h in enter + houses:
        if h["id"] in seen:
            continue
        seen.add(h["id"])
        c, d = h["curb"], h["door"]
        yaw = math.radians(c["yaw"])
        lx, lz = -math.sin(yaw), -math.cos(yaw)  # yaw 0 looks north (-z)
        back, nose = (c["x"] - lx * 11, c["z"] - lz * 11), (c["x"] + lx * 11, c["z"] + lz * 11)
        if not (on_road(*back) and on_road(*nose)
                and math.hypot(back[0] - d["x"], back[1] - d["z"]) < math.hypot(nose[0] - d["x"], nose[1] - d["z"])):
            bad.append(h["id"])
    return len(seen), bad


def main():
    roads, landmarks, houses, enter = build()
    checked, bad = check(roads, houses, enter)
    print(f"van spots checked on {checked} houses: {'all fine' if not bad else 'BAD ' + ', '.join(bad)}")
    plan = {
        "about": "Jinočany instead of the Alps: the proposed sandbox map (design/jinocany/NAVRH.md). Studs; x east, z south; "
                 "yaw as SandboxMap (0 north, 90 west, 180 south, 270 east). Fixed entries are today's SandboxMap data.",
        "bounds": BOUNDS,
        "plots": PLOTS,
        "turnaround": TURNAROUND,
        "bigHouse": BIG_HOUSE,
        "roads": roads,
        "landmarks": landmarks,
        "fields": [{"rect": rect(*r), "kind": k} for r, k in FIELDS],
        "village": rect(*VILLAGE),
        "treeLines": [{"points": [{"x": x, "z": z} for x, z in pts], "kind": k} for pts, k in TREE_LINES],
        "houses": houses,
        "enter": enter,
    }
    with open(os.path.join(HERE, "plan.json"), "w", encoding="utf-8") as out:
        json.dump(plan, out, ensure_ascii=False, indent=1)
    picture(roads, landmarks, houses, enter, os.path.join(HERE, "plan.png"))
    kinds = {}
    for h in houses:
        kinds[h["kind"]] = kinds.get(h["kind"], 0) + 1
    by_step = {}
    for h in houses:
        by_step[h["step"]] = by_step.get(h["step"], 0) + 1
    print(f"houses {len(houses)} (+ the big house): {kinds}; by step {by_step}")
    print("enter:", ", ".join(f"{e['id']} {e['label']}" for e in enter))


if __name__ == "__main__":
    main()
