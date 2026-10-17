#!/usr/bin/env python3
"""9.7 the lobby (the owner: "shrink the map and put things quite close together, so that it's one little lobby,
something smaller, like Dungeon Quest: there you go into a dungeon. Here you'll go into a house"): the sandbox's whole
visible world, a compact square you cross on foot in half a minute, as plain data and a picture.

Writes, next to this file:
  plan.json   the lobby's bounds, its plaza, the spawn, the ZDC dispatch, the four plots (their warehouses look south
              onto the plaza, as every warehouse always has: shared/WarehouseLayout.luau), the six house portals (each a
              gate in its house's style, its name, a glowing pad in front of it toward the plaza), the PAINT shop, the
              TOP MOVERS board, the Auction House's footprint (built only while Config.Auction.On), the fountain, the
              lamps and the trees; in SandboxMap's units and axes (studs; x east, z south: -z is north; a spot's yaw as
              SandboxMap's: 0 looks north, 90 west, 180 south, 270 east)
  plan.png    the same seen from above, north up, everything labelled

tools/lobby/sandboxmap.py writes plan.json into shared/SandboxMap.luau (its LOBBY section: SandboxMap.Lobby, and the
plots SandboxMap.Plots are made from it). The six places to empty are not here: each is a run zone of its own far off
(design/countryside/plan.py), at least FAR studs from the lobby. Nothing overlaps anything else: check() says.
Deterministic (no dice).

    python3 design/lobby/plan.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

OX, OZ = 1800, 0  # the lobby's middle on the map (the run zones are west of x 420: design/countryside/plan.py)
FAR = 1000  # a run zone at least this far from the lobby's bounds (design/countryside/plan.py checks it too)


def rect(x0, x1, z0, z1):
    return {"x0": x0, "x1": x1, "z0": z0, "z1": z1}


def spot(x, z, yaw, y=0):
    return {"x": x, "y": y, "z": z, "yaw": yaw}


# ── The square ─────────────────────────────────────────────────────────────────────────────────────────────────────

BOUNDS = rect(OX - 240, OX + 240, OZ - 200, OZ + 200)  # 480 × 400: a walk across in about half a minute
HEDGE = 2  # the hedge round it stands this far in from the bounds (the invisible walls on the bounds)
PLAZA = rect(OX - 165, OX + 165, OZ - 54, OZ + 150)  # the paved square in the middle

# The plots: four in a row along the north edge, every warehouse looking south onto the plaza (the warehouses' frame
# is only moved: shared/WarehouseLayout.luau). A plot is PLOT_W across, its warehouse's front wall at WALL, the plot
# BACK behind it (the Logistics Center is 84 deep) and FRONT in front of it (the bay painted round where the van stood).
PLOT_W, PLOT_STEP = 112, 116  # (the Logistics Center is 104 wide)
WALL = OZ - 100
BACK, FRONT = 90, 40
PLOT_X = [OX - 174, OX - 58, OX + 58, OX + 174]
PLOTS = [{"id": i + 1, "x": x, "wall": WALL, "rect": rect(x - PLOT_W / 2, x + PLOT_W / 2, WALL - BACK, WALL + FRONT)}
         for i, x in enumerate(PLOT_X)]

SPAWN = spot(OX, OZ + 10, 180, 3)  # the plaza's middle, looking south at the portals (SandboxBoot: a few studs apart)
SPAWN_APART = 6  # the players' spawns stand this far apart across the look
DISPATCH = spot(OX, OZ - 44, 180)  # the ZDC dispatch kiosk at the plaza's north edge, looking south
FOUNTAIN = {"x": OX, "z": OZ + 70, "r": 9}

# ── The six portals ────────────────────────────────────────────────────────────────────────────────────────────────

# house (SandboxMap.Houses' id), the gate's middle on the ground (x, z) and yaw (the way its front looks: toward the
# plaza). Its pad (PAD × PAD) lies PAD_OUT in front of the gate; its footprint (the gate, the facade behind it) is
# GATE_W across, from FACADE_BACK behind the gate's line to GATE_FRONT in front of it.
PORTALS = [
    ("pond_cabin", OX - 205, OZ + 0, 270),
    ("old_mill", OX - 205, OZ + 96, 270),
    ("sandbox_house", OX - 108, OZ + 176, 0),
    ("lone_house", OX + 108, OZ + 176, 0),
    ("forest_lodge", OX + 205, OZ + 96, 90),
    ("orchard_cottage", OX + 205, OZ + 0, 90),
]
NAMES = {"sandbox_house": "The Old Farmstead", "pond_cabin": "The Pond Cabin", "lone_house": "The Lone House",
         "forest_lodge": "The Forest Lodge", "old_mill": "The Old Mill", "orchard_cottage": "The Orchard Cottage"}
PAD, PAD_OUT = 14, 12
BACK_OUT = PAD / 2 + 4  # a party coming back lands this far past its pad's middle, off the pad, facing the plaza
GATE_W, FACADE_BACK, GATE_FRONT = 20, 13, 2
LOOK = {0: (0, -1), 90: (-1, 0), 180: (0, 1), 270: (1, 0)}  # the way a yaw looks (x, z)


def turned(cx, cz, yaw, u0, u1, v0, v1):
    """A rect in a portal's frame (u across, v out along its look) on the map."""
    lx, lz = LOOK[yaw]
    ux, uz = -lz, lx  # (across: its right as you look out of it)
    xs = [cx + ux * u + lx * v for u in (u0, u1) for v in (v0, v1)]
    zs = [cz + uz * u + lz * v for u in (u0, u1) for v in (v0, v1)]
    return rect(min(xs), max(xs), min(zs), max(zs))


def portals():
    out = []
    for house, x, z, yaw in PORTALS:
        lx, lz = LOOK[yaw]
        px, pz = x + lx * PAD_OUT, z + lz * PAD_OUT
        out.append({"house": house, "name": NAMES[house], "x": x, "z": z, "yaw": yaw,
                    "pad": rect(px - PAD / 2, px + PAD / 2, pz - PAD / 2, pz + PAD / 2),
                    "foot": turned(x, z, yaw, -GATE_W / 2, GATE_W / 2, -FACADE_BACK, GATE_FRONT),
                    "back": spot(px + lx * BACK_OUT, pz + lz * BACK_OUT, yaw, 3)})  # (where its party comes back: off its pad, facing the plaza)
    return out


# ── The shops ──────────────────────────────────────────────────────────────────────────────────────────────────────

# The PAINT shop (a booth: its prompt opens the PAINT shop's window, server/VanPaint.luau), the TOP MOVERS board
# (server/SandboxLeaders.luau: its spot, its footprint SandboxLeadersRules'), the Auction House (its front wall's middle
# looking out: Config.Auction.House.Spot; built only while Config.Auction.On, its place kept either way).
PAINT = {"spot": spot(OX + 206, OZ - 40, 90), "w": 22, "d": 12}  # (its front looks west into the plaza)
LEADERS = spot(OX - 206, OZ - 40, 270)  # (its face looks east into the plaza)
LEADERS_FOOT = (24, 5)  # (Config.SandboxLeaders.Board: Width + 2 Over across, 2 Run deep)
AUCTION = spot(OX, OZ + 156, 0)  # (its front looks north at the plaza)
AUCTION_FOOT = (52, 38, 4)  # (shared/AuctionHouseLayout.luau's site: across, deep, its steps out in front of the spot)

LAMPS = [(OX - 165, OZ - 54), (OX + 165, OZ - 54), (OX - 165, OZ + 150), (OX + 165, OZ + 150), (OX - 60, OZ - 54), (OX + 60, OZ - 54),
         (OX - 165, OZ + 48), (OX + 165, OZ + 48)]
TREES = [("linden", OX - 225, OZ + 180), ("oak", OX + 225, OZ + 180), ("birch", OX - 160, OZ + 186), ("birch", OX + 160, OZ + 186),
         ("linden", OX - 228, OZ + 140), ("oak", OX + 228, OZ + 140), ("birch", OX - 226, OZ - 30), ("birch", OX + 226, OZ - 30)]


def shops():
    p = PAINT["spot"]
    lx, lz = LOOK[p["yaw"]]
    paint = turned(p["x"], p["z"], p["yaw"], -PAINT["w"] / 2, PAINT["w"] / 2, -PAINT["d"], 0)
    l = LEADERS
    leaders = turned(l["x"], l["z"], l["yaw"], -LEADERS_FOOT[0] / 2, LEADERS_FOOT[0] / 2, -LEADERS_FOOT[1] / 2, LEADERS_FOOT[1] / 2)
    a = AUCTION
    auction = turned(a["x"], a["z"], a["yaw"], -AUCTION_FOOT[0] / 2, AUCTION_FOOT[0] / 2, -AUCTION_FOOT[1] + AUCTION_FOOT[2], AUCTION_FOOT[2])
    return {
        "paint": {"spot": p, "rect": paint, "stand": spot(p["x"] + lx * 4, p["z"] + lz * 4, (p["yaw"] + 180) % 360, 3)},
        "leaders": {"spot": l, "rect": leaders},
        "auction": {"spot": a, "rect": auction},
    }


# ── The checks ─────────────────────────────────────────────────────────────────────────────────────────────────────

def overlap(a, b, margin=0):
    return a["x0"] < b["x1"] + margin and b["x0"] < a["x1"] + margin and a["z0"] < b["z1"] + margin and b["z0"] < a["z1"] + margin


def inside(r, outer, margin=0):
    return r["x0"] >= outer["x0"] + margin - 1e-6 and r["x1"] <= outer["x1"] - margin + 1e-6 and r["z0"] >= outer["z0"] + margin - 1e-6 \
        and r["z1"] <= outer["z1"] - margin + 1e-6


def check(ps, sh):
    bad = []
    areas = [(f"plot {p['id']}", p["rect"]) for p in PLOTS]
    areas += [(f"portal {p['house']}", p["foot"]) for p in ps] + [(f"pad {p['house']}", p["pad"]) for p in ps]
    areas += [(f"shop {k}", v["rect"]) for k, v in sh.items()]
    areas.append(("dispatch", rect(DISPATCH["x"] - 4, DISPATCH["x"] + 4, DISPATCH["z"] - 3, DISPATCH["z"] + 3)))
    areas.append(("fountain", rect(FOUNTAIN["x"] - FOUNTAIN["r"], FOUNTAIN["x"] + FOUNTAIN["r"], FOUNTAIN["z"] - FOUNTAIN["r"], FOUNTAIN["z"] + FOUNTAIN["r"])))
    areas.append(("spawn", rect(SPAWN["x"] - 2 * SPAWN_APART, SPAWN["x"] + 2 * SPAWN_APART, SPAWN["z"] - 3, SPAWN["z"] + 3)))
    for i, (na, a) in enumerate(areas):
        if not inside(a, BOUNDS, HEDGE + 1):
            bad.append(f"{na} outside the lobby (or on its hedge)")
        for nb, b in areas[i + 1:]:
            if overlap(a, b, -1e-6):
                # (a portal's pad is in front of its own gate, a plot touches the next one)
                if na.split(" ")[1:] == nb.split(" ")[1:] and {na.split(" ")[0], nb.split(" ")[0]} == {"portal", "pad"}:
                    continue
                bad.append(f"{na} on {nb}")
    # the trees (their crowns 8 across at most) on none of them, in the bounds, off the hedge
    for kind, x, z in TREES:
        crown = rect(x - 4, x + 4, z - 4, z + 4)
        if not inside(crown, BOUNDS, HEDGE + 1):
            bad.append(f"the {kind} at {x}, {z} outside the lobby (or on its hedge)")
        for na, a in areas:
            if overlap(crown, a, 2):
                bad.append(f"the {kind} at {x}, {z} on {na}")
    # where a party comes back: in the lobby, off every pad (a body there would start a run again), facing the plaza
    for p in ps:
        b = p["back"]
        spot_rect = rect(b["x"] - 2, b["x"] + 2, b["z"] - 2, b["z"] + 2)
        if not inside(spot_rect, BOUNDS, HEDGE + 1):
            bad.append(f"{p['house']}'s back spot outside the lobby")
        for q in ps:
            if overlap(spot_rect, q["pad"], 1):
                bad.append(f"{p['house']}'s back spot on {q['house']}'s pad")
    # every pad 4 studs at least from the next (somebody on one is never on two), from the spawn and the dispatch
    for p in ps:
        for q in ps:
            if p is not q and overlap(p["pad"], q["pad"], 4):
                bad.append(f"pads {p['house']} and {q['house']} too close")
    # a portal for each of the six places, once
    if sorted(p["house"] for p in ps) != sorted(NAMES):
        bad.append("not one portal for each of the six places")
    # the plaza in the bounds; from corner to corner in under 45 s on foot (Config.Movement.Walk: 14 studs a second)
    if not inside(PLAZA, BOUNDS, HEDGE):
        bad.append("the plaza outside the lobby")
    across = math.hypot(BOUNDS["x1"] - BOUNDS["x0"], BOUNDS["z1"] - BOUNDS["z0"])
    if across / 14 >= 45:
        bad.append(f"the lobby too big to cross in 45 s ({across:.0f} studs corner to corner)")
    return bad


# ── The picture ────────────────────────────────────────────────────────────────────────────────────────────────────

S = 2.2  # px per stud
PANEL = 560
TOP = 130
W = int((BOUNDS["x1"] - BOUNDS["x0"]) * S) + PANEL + 40
H = max(int((BOUNDS["z1"] - BOUNDS["z0"]) * S) + TOP + 40, 1060)
COL = {
    "grass": (104, 146, 66), "plaza": (196, 188, 172), "plaza2": (176, 168, 152), "concrete": (200, 197, 190),
    "warehouse": (150, 160, 172), "hedge": (52, 96, 44), "label": (32, 32, 36), "accent": (240, 130, 40),
    "white": (250, 250, 250), "text2": (205, 205, 210), "water": (76, 140, 190), "tree": (48, 100, 46), "pad": (120, 220, 255),
    "gate": (110, 80, 56), "paint": (214, 72, 120), "board": (40, 70, 140), "auction": (226, 214, 186), "lamp": (60, 60, 64),
    "dispatch": (238, 140, 40),
}
STYLE = {  # the portals' colours in the picture (their houses' looks: server/LobbyWorld.luau's Config.Runs.Portal.Styles)
    "sandbox_house": (150, 60, 44), "pond_cabin": (120, 86, 56), "lone_house": (226, 214, 186), "forest_lodge": (96, 64, 40),
    "old_mill": (150, 148, 142), "orchard_cottage": (240, 236, 226),
}


def font(size, bold=False):
    for path in (f"/usr/share/fonts/opentype/inter/Inter-{'Bold' if bold else 'Medium'}.otf",
                 f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def P(x, z):
    return ((x - BOUNDS["x0"]) * S + 20, (z - BOUNDS["z0"]) * S + TOP)


def R(r):
    a, b = P(r["x0"], r["z0"]), P(r["x1"], r["z1"])
    return [a[0], a[1], b[0], b[1]]


def picture(ps, sh, path):
    img = Image.new("RGB", (W, H), (36, 38, 42))
    draw = ImageDraw.Draw(img)
    draw.rectangle(R(BOUNDS), fill=COL["grass"])
    b = R(BOUNDS)
    h = HEDGE * S
    draw.rectangle([b[0] + h - 3, b[1] + h - 3, b[2] - h + 3, b[3] - h + 3], outline=COL["hedge"], width=7)
    # the plaza: paving in squares
    pz = R(PLAZA)
    draw.rectangle(pz, fill=COL["plaza"])
    for x in range(int(PLAZA["x0"]), int(PLAZA["x1"]), 12):
        a, c = P(x, PLAZA["z0"]), P(x, PLAZA["z1"])
        draw.line([a, c], fill=COL["plaza2"], width=1)
    for z in range(int(PLAZA["z0"]), int(PLAZA["z1"]), 12):
        a, c = P(PLAZA["x0"], z), P(PLAZA["x1"], z)
        draw.line([a, c], fill=COL["plaza2"], width=1)
    # the plots and their warehouses (the Big Warehouse, level 4: 80 × 60; the Logistics Center's 104 × 84 dashed)
    for p in PLOTS:
        draw.rectangle(R(p["rect"]), fill=COL["concrete"])
        draw.rectangle(R(rect(p["x"] - 40, p["x"] + 40, p["wall"] - 60, p["wall"])), fill=COL["warehouse"], outline=(70, 76, 84), width=3)
        big = R(rect(p["x"] - 52, p["x"] + 52, p["wall"] - 84, p["wall"]))
        for k in range(int(big[0]), int(big[2]), 12):
            draw.line([k, big[1], k + 6, big[1]], fill=(90, 96, 104), width=2)
        door = R(rect(p["x"] - 13, p["x"] + 13, p["wall"] - 2, p["wall"]))
        draw.rectangle(door, fill=(60, 64, 70))
        draw.text(P(p["x"], p["wall"] - 36), f"PLOT {p['id']}", font=font(20, True), fill=(30, 34, 40), anchor="mm")
        draw.text(P(p["x"], p["wall"] - 20), "ZDC warehouse", font=font(15), fill=(30, 34, 40), anchor="mm")
        draw.text(P(p["x"], p["wall"] + 22), "the bay", font=font(14), fill=(110, 110, 110), anchor="mm")
    # the fountain, the dispatch, the spawn
    fx, fz = P(FOUNTAIN["x"], FOUNTAIN["z"])
    fr = FOUNTAIN["r"] * S
    draw.ellipse([fx - fr, fz - fr, fx + fr, fz + fr], fill=(150, 146, 140))
    draw.ellipse([fx - fr + 6, fz - fr + 6, fx + fr - 6, fz + fr - 6], fill=COL["water"])
    d = DISPATCH
    draw.rectangle(R(rect(d["x"] - 4, d["x"] + 4, d["z"] - 3, d["z"] + 3)), fill=COL["dispatch"], outline=(60, 40, 20), width=2)
    for k in range(-1, 2):
        sx, sz = P(SPAWN["x"] + k * SPAWN_APART, SPAWN["z"])
        draw.ellipse([sx - 6, sz - 6, sx + 6, sz + 6], fill=COL["white"], outline=COL["accent"], width=3)
    # the lamps and trees
    for x, z in LAMPS:
        cx, cz = P(x, z)
        draw.ellipse([cx - 4, cz - 4, cx + 4, cz + 4], fill=COL["lamp"])
    for kind, x, z in TREES:
        cx, cz = P(x, z)
        r = 9 * S
        draw.ellipse([cx - r + 3, cz - r + 4, cx + r + 3, cz + r + 4], fill=(30, 50, 30))
        draw.ellipse([cx - r, cz - r, cx + r, cz + r], fill=COL["tree"] if kind != "birch" else (92, 140, 70))
    # the shops
    draw.rectangle(R(sh["paint"]["rect"]), fill=COL["paint"], outline=(60, 20, 40), width=3)
    draw.rectangle(R(sh["leaders"]["rect"]), fill=COL["board"], outline=(20, 30, 60), width=3)
    ar = R(sh["auction"]["rect"])
    for k in range(int(ar[0]), int(ar[2]), 14):
        draw.line([k, ar[1], k + 7, ar[1]], fill=(120, 110, 90), width=3)
        draw.line([k, ar[3], k + 7, ar[3]], fill=(120, 110, 90), width=3)
    for k in range(int(ar[1]), int(ar[3]), 14):
        draw.line([ar[0], k, ar[0], k + 7], fill=(120, 110, 90), width=3)
        draw.line([ar[2], k, ar[2], k + 7], fill=(120, 110, 90), width=3)
    # the portals: the footprint (the facade, the gate), the glowing pad, the number
    for i, p in enumerate(ps):
        draw.rectangle(R(p["foot"]), fill=STYLE[p["house"]], outline=(40, 30, 24), width=3)
        lx, lz = LOOK[p["yaw"]]
        ux, uz = -lz, lx
        a, c = P(p["x"] - ux * GATE_W / 2, p["z"] - uz * GATE_W / 2), P(p["x"] + ux * GATE_W / 2, p["z"] + uz * GATE_W / 2)
        draw.line([a, c], fill=(30, 24, 20), width=6)
        pad = R(p["pad"])
        draw.rectangle([pad[0] - 4, pad[1] - 4, pad[2] + 4, pad[3] + 4], fill=(70, 150, 190))
        draw.rectangle(pad, fill=COL["pad"])
        cx, cz = (pad[0] + pad[2]) / 2, (pad[1] + pad[3]) / 2
        draw.ellipse([cx - 14, cz - 14, cx + 14, cz + 14], fill=COL["accent"], outline=COL["white"], width=2)
        draw.text((cx, cz), str(i + 1), font=font(18, True), fill=COL["white"], anchor="mm")
    # the labels
    def tag(x, z, text, sub=None, anchor=(0, 0)):
        f, fs = font(17, True), font(13)
        tw = max(draw.textlength(text, font=f), draw.textlength(sub, font=fs) if sub else 0)
        hh = 26 + (18 if sub else 0)
        px, py = P(x, z)
        px -= anchor[0] * (tw + 16)
        py -= anchor[1] * hh
        draw.rounded_rectangle([px, py, px + tw + 16, py + hh], 5, fill=COL["label"])
        draw.text((px + 8, py + 4), text, font=f, fill=COL["white"])
        if sub:
            draw.text((px + 8, py + 25), sub, font=fs, fill=COL["text2"])
    for i, p in enumerate(ps):
        lx, lz = LOOK[p["yaw"]]
        if p["yaw"] == 270:
            tag(p["x"] + 4, p["z"] + 14, f"{i + 1} {p['name']}", "portal · its pad")
        elif p["yaw"] == 90:
            tag(p["x"] - 4, p["z"] + 14, f"{i + 1} {p['name']}", "portal · its pad", (1, 0))
        elif p["x"] < OX:
            tag(p["x"] - 13, p["z"] - 6, f"{i + 1} {p['name']}", "portal · its pad", (1, 0.5))
        else:
            tag(p["x"] + 13, p["z"] - 6, f"{i + 1} {p['name']}", "portal · its pad", (0, 0.5))
    tag(DISPATCH["x"] + 10, DISPATCH["z"] - 2, "ZDC DISPATCH", "how runs work", (0, 0.5))
    tag(SPAWN["x"], SPAWN["z"] + 8, "SPAWN", None, (0.5, 0))
    tag(sh["paint"]["spot"]["x"] - 26, sh["paint"]["spot"]["z"] + 10, "PAINT SHOP", "your truck's colours", (1, 0))
    tag(LEADERS["x"] + 8, LEADERS["z"] + 8, "TOP MOVERS", "the board")
    tag(AUCTION["x"], AUCTION["z"] + 20, "AUCTION HOUSE", "its place (off for now)", (0.5, 0))
    tag(FOUNTAIN["x"], FOUNTAIN["z"] + 12, "fountain", None, (0.5, 0))
    # the title
    draw.rectangle([0, 0, W, TOP - 10], fill=(28, 30, 34))
    draw.text((24, 16), "ZOMBIE DELIVERY · THE LOBBY (SANDBOX, 9.7 RUNS)", font=font(40, True), fill=COL["white"])
    draw.text((24, 70), "Seen from above, north up. The whole visible world: the plaza, the spawn, the ZDC dispatch, the four warehouses, "
              "the shops and six portals.", font=font(19), fill=COL["text2"])
    # the legend
    lx = W - PANEL + 10
    y = TOP + 10
    draw.text((lx, y), "THE SIX PORTALS", font=font(24, True), fill=COL["white"])
    y += 40
    for i, p in enumerate(ps):
        draw.ellipse([lx, y + 2, lx + 26, y + 28], fill=COL["accent"])
        draw.text((lx + 13, y + 15), str(i + 1), font=font(16, True), fill=COL["white"], anchor="mm")
        draw.text((lx + 38, y + 3), p["name"], font=font(19, True), fill=COL["white"])
        y += 36
    y += 14
    draw.text((lx, y), "A RUN", font=font(24, True), fill=COL["white"])
    y += 36
    for text in ("Stand on a portal's pad: a 10 s countdown.", "The first on it is the host: picks the difficulty.",
                 "Everybody on the pad goes (4 at most), each", "with their own hired Danny.",
                 "In the house: carry the loot into the truck", "parked at its door. FINISH at the truck, or",
                 "the clock runs out: what is in the truck goes", "to the stock of whoever loaded it.",
                 "Then everybody fades back to their portal."):
        draw.text((lx, y), text, font=font(17), fill=COL["text2"])
        y += 26
    y += 14
    draw.text((lx, y), "LEGEND", font=font(24, True), fill=COL["white"])
    y += 36
    for colour, text in ((COL["pad"], "a portal's glowing pad"), (COL["plaza"], "the plaza (paved)"), (COL["concrete"], "a plot's concrete"),
                         (COL["warehouse"], "a warehouse (level 4; dashed: level 5)"), (COL["paint"], "the PAINT shop"),
                         (COL["board"], "the TOP MOVERS board"), (COL["hedge"], "the hedge round the lobby")):
        draw.rectangle([lx, y + 3, lx + 26, y + 23], fill=colour, outline=(20, 20, 20))
        draw.text((lx + 38, y + 2), text, font=font(17), fill=COL["white"])
        y += 30
    y += 10
    draw.text((lx, y), f"lobby {BOUNDS['x1'] - BOUNDS['x0']} × {BOUNDS['z1'] - BOUNDS['z0']} studs; the six run zones are", font=font(16), fill=COL["text2"])
    draw.text((lx, y + 22), f"{FAR}+ studs west of it (design/countryside/plan.png)", font=font(16), fill=COL["text2"])
    bx, by = 30, H - 40
    draw.line([bx, by, bx + 50 * S, by], fill=COL["white"], width=4)
    draw.line([bx, by - 8, bx, by + 8], fill=COL["white"], width=3)
    draw.line([bx + 50 * S, by - 8, bx + 50 * S, by + 8], fill=COL["white"], width=3)
    draw.text((bx + 50 * S + 10, by - 10), "50 studs", font=font(16), fill=COL["white"])
    nx, ny = W - PANEL - 20, H - 60
    draw.polygon([(nx, ny - 30), (nx - 14, ny + 8), (nx + 14, ny + 8)], fill=COL["accent"])
    draw.text((nx, ny + 24), "N", font=font(20, True), fill=COL["white"], anchor="mm")
    img.save(path, optimize=True)


def main():
    ps, sh = portals(), shops()
    bad = check(ps, sh)
    print("lobby plan check: " + ("all fine" if not bad else "BAD\n  " + "\n  ".join(bad)))
    plan = {
        "about": "The lobby (design/lobby/plan.py): the sandbox's whole visible world. Studs; x east, z south; yaw as SandboxMap "
                 "(0 north, 90 west, 180 south, 270 east).",
        "bounds": BOUNDS,
        "hedge": HEDGE,
        "far": FAR,
        "plaza": PLAZA,
        "spawn": SPAWN,
        "spawnApart": SPAWN_APART,
        "dispatch": DISPATCH,
        "fountain": FOUNTAIN,
        "plots": PLOTS,
        "portals": ps,
        "shops": sh,
        "lamps": [{"x": x, "z": z} for x, z in LAMPS],
        "trees": [{"kind": k, "x": x, "z": z} for k, x, z in TREES],
    }
    with open(os.path.join(HERE, "plan.json"), "w", encoding="utf-8") as out:
        json.dump(plan, out, ensure_ascii=False, indent=1)
    picture(ps, sh, os.path.join(HERE, "plan.png"))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
