#!/usr/bin/env python3
"""9.7 the lobby (the owner: "shrink the map and put things quite close together, so that it's one little lobby,
something smaller, like Dungeon Quest: there you go into a dungeon. Here you'll go into a house"; 10.4: "make the map
smaller, and on the map just one circle where you'd stand, like PLAY, and you'd create a lobby"): the sandbox's whole
visible world, a tight square where everything is a few seconds' walk apart, as plain data and a picture.

Writes, next to this file:
  plan.json   the lobby's bounds, its plaza, the spawn, the Deliveros dispatch, the four plots (their warehouses look
              south onto the plaza, as every warehouse always has: shared/WarehouseLayout.luau), 10.4 the one PLAY
              circle in the plaza (step in: the PLAY panel, a party's lobby, a run: server/Parties.luau) and where a
              party comes back from a run (just off it, facing it: never in it), the PAINT shop, the TOP MOVERS board,
              the Auction House's footprint (built only while Config.Auction.On), the fountain, the lamps and the
              trees; in SandboxMap's units and axes (studs; x east, z south: -z is north; a spot's yaw as SandboxMap's:
              0 looks north, 90 west, 180 south, 270 east)
  plan.png    the same seen from above, north up, everything labelled

tools/lobby/sandboxmap.py writes plan.json into shared/SandboxMap.luau (its LOBBY section: SandboxMap.Lobby, and the
plots SandboxMap.Plots are made from it). The six places to empty are not here: 10.8 each is on a floating island of its
own round the lobby's island (design/islands/plan.py: the lobby island is these bounds and a rim of grass round them),
its walls at least FAR studs from the lobby's bounds. Nothing overlaps anything else: check() says. Deterministic (no
dice).

    python3 design/lobby/plan.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

OX, OZ = 1800, 0  # the lobby's middle across (10.8 the other islands round it: design/islands/plan.py)
FAR = 300  # 10.8: every other island's walls at least this far from the lobby's bounds (design/islands/plan.py checks it)


def rect(x0, x1, z0, z1):
    return {"x0": x0, "x1": x1, "z0": z0, "z1": z1}


def spot(x, z, yaw, y=0):
    return {"x": x, "y": y, "z": z, "yaw": yaw}


# ── The square ─────────────────────────────────────────────────────────────────────────────────────────────────────

# 10.4: 456 × 226 studs (9.7: 480 × 400): as wide as the four plots side by side need (the Logistics Center, level 5,
# is 104 × 84: config Warehouse.Levels), as deep as a plot and the plaza in front of it
BOUNDS = rect(OX - 228, OX + 228, OZ - 128, OZ + 98)
HEDGE = 2  # the hedge round it stands this far in from the bounds (2.6 thick; the invisible walls on the bounds)
CLEAR = HEDGE + 3  # everything this far in from the bounds at least: off the hedge, a stud and more to spare
PLAZA = rect(OX - 200, OX + 200, OZ + 6, OZ + 92)  # the paved square in front of the plots

# The plots: four in a row along the north edge, every warehouse looking south onto the plaza (the warehouses' frame
# is only moved: shared/WarehouseLayout.luau). A plot is PLOT_W across (the Logistics Center's 104 and 3 each side),
# its warehouse's front wall at WALL, the plot BACK behind it (the Logistics Center is 84 deep) and FRONT in front of it
# (the bay painted round where the van stood: 30 long, from 2 off the wall).
PLOT_W, PLOT_STEP = 110, 112
WALL = OZ - 33
BACK, FRONT = 90, 36
PLOT_X = [OX - 168, OX - 56, OX + 56, OX + 168]
PLOTS = [{"id": i + 1, "x": x, "wall": WALL, "rect": rect(x - PLOT_W / 2, x + PLOT_W / 2, WALL - BACK, WALL + FRONT)}
         for i, x in enumerate(PLOT_X)]

# 10.4 the PLAY circle (config Runs.Play.Radius is the same r): its middle in the plaza, a glowing ring on the ground
# with PLAY over it (server/LobbyWorld.luau). A party back from a run lands BACK_OUT studs south of its edge, facing it
# (spread across, config Runs.Apart: never in it).
PLAY = {"x": OX, "z": OZ + 44, "r": 16}
BACK_OUT = 8
PLAY_BACK = spot(PLAY["x"], PLAY["z"] + PLAY["r"] + BACK_OUT, 0, 3)
SPAWN = spot(OX, OZ + 80, 0, 3)  # the plaza's south part, looking north at the PLAY circle (SandboxBoot: a few apart)
SPAWN_APART = 6  # the players' spawns stand this far apart across the look
DISPATCH = spot(OX - 40, PLAY["z"], 270)  # the Deliveros dispatch kiosk west of the circle, looking east at it
FOUNTAIN = {"x": OX - 170, "z": OZ + 48, "r": 9}
NAMES = {"sandbox_house": "The Old Farmstead", "pond_cabin": "The Pond Cabin", "lone_house": "The Lone House",
         "forest_lodge": "The Forest Lodge", "old_mill": "The Old Mill", "orchard_cottage": "The Orchard Cottage"}
LOOK = {0: (0, -1), 90: (-1, 0), 180: (0, 1), 270: (1, 0)}  # the way a yaw looks (x, z)


def turned(cx, cz, yaw, u0, u1, v0, v1):
    """A rect in a spot's frame (u across, v out along its look) on the map."""
    lx, lz = LOOK[yaw]
    ux, uz = -lz, lx  # (across: its right as you look out of it)
    xs = [cx + ux * u + lx * v for u in (u0, u1) for v in (v0, v1)]
    zs = [cz + uz * u + lz * v for u in (u0, u1) for v in (v0, v1)]
    return rect(min(xs), max(xs), min(zs), max(zs))


def play():
    r = PLAY["r"]
    return {"x": PLAY["x"], "z": PLAY["z"], "r": r, "back": PLAY_BACK}


def circle_rect(p, grow=0):
    return rect(p["x"] - p["r"] - grow, p["x"] + p["r"] + grow, p["z"] - p["r"] - grow, p["z"] + p["r"] + grow)


# ── The shops ──────────────────────────────────────────────────────────────────────────────────────────────────────

# The PAINT shop (a booth: its prompt opens the PAINT shop's window, server/VanPaint.luau), the TOP MOVERS board
# (server/SandboxLeaders.luau: its spot, its footprint SandboxLeadersRules'), the Auction House (its front wall's middle
# looking out: Config.Auction.House.Spot; built only while Config.Auction.On, its place kept either way). 10.4: round
# the PLAY circle, each a few seconds from it: the dispatch and the board west of it, the PAINT shop and the Auction
# House east of it, their fronts to it.
PAINT = {"spot": spot(OX + 64, PLAY["z"], 90), "w": 22, "d": 12}  # (its front looks west at the circle)
LEADERS = spot(OX - 120, OZ + 50, 270)  # (its face looks east across the plaza at the spawn)
LEADERS_FOOT = (24, 5)  # (Config.SandboxLeaders.Board: Width + 2 Over across, 2 Run deep)
AUCTION = spot(OX + 130, PLAY["z"], 90)  # (its front looks west at the circle)
AUCTION_FOOT = (52, 38, 4)  # (shared/AuctionHouseLayout.luau's site: across, deep, its steps out in front of the spot)

LAMPS = [(OX - 200, OZ + 6), (OX + 200, OZ + 6), (OX - 200, OZ + 92), (OX + 200, OZ + 92), (OX - 90, OZ + 6), (OX + 90, OZ + 6),
         (OX - 90, OZ + 92), (OX + 90, OZ + 92)]
TREES = [("linden", OX - 214, OZ + 20), ("oak", OX + 214, OZ + 20), ("birch", OX - 214, OZ + 52), ("birch", OX + 214, OZ + 52),
         ("oak", OX - 214, OZ + 84), ("linden", OX + 214, OZ + 84)]


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


def walk(ax, az, bx, bz):
    """Seconds on foot from one point to another (Config.Movement.Walk: 14 studs a second)."""
    return math.hypot(bx - ax, bz - az) / 14


def check(p, sh):
    bad = []
    areas = [(f"plot {q['id']}", q["rect"]) for q in PLOTS]
    areas.append(("the PLAY circle", circle_rect(p, 1)))
    areas += [(f"shop {k}", v["rect"]) for k, v in sh.items()]
    areas.append(("dispatch", rect(DISPATCH["x"] - 4, DISPATCH["x"] + 4, DISPATCH["z"] - 3, DISPATCH["z"] + 3)))
    areas.append(("fountain", rect(FOUNTAIN["x"] - FOUNTAIN["r"], FOUNTAIN["x"] + FOUNTAIN["r"], FOUNTAIN["z"] - FOUNTAIN["r"], FOUNTAIN["z"] + FOUNTAIN["r"])))
    areas.append(("spawn", rect(SPAWN["x"] - 2 * SPAWN_APART, SPAWN["x"] + 2 * SPAWN_APART, SPAWN["z"] - 3, SPAWN["z"] + 3)))
    back = p["back"]
    areas.append(("the party's way back", rect(back["x"] - 6, back["x"] + 6, back["z"] - 2, back["z"] + 2)))
    for i, (na, a) in enumerate(areas):
        if not inside(a, BOUNDS, CLEAR):
            bad.append(f"{na} outside the lobby (or on its hedge)")
        for nb, b in areas[i + 1:]:
            if overlap(a, b, -1e-6):
                bad.append(f"{na} on {nb}")
    # the trees (their crowns 8 across at most) on none of them, in the bounds, off the hedge
    for kind, x, z in TREES:
        crown = rect(x - 4, x + 4, z - 4, z + 4)
        if not inside(crown, BOUNDS, CLEAR):
            bad.append(f"the {kind} at {x}, {z} outside the lobby (or on its hedge)")
        for na, a in areas:
            if overlap(crown, a, 2):
                bad.append(f"the {kind} at {x}, {z} on {na}")
    # the circle on the plaza; the way back off it (a body there would only open the PLAY panel again), facing it
    if not inside(circle_rect(p), PLAZA, 4):
        bad.append("the PLAY circle not on the plaza")
    if back["z"] - 2 < p["z"] + p["r"] + 2 or back["yaw"] != 0:
        bad.append("the party's way back on the PLAY circle (or not facing it)")
    # the plaza in the bounds; a few seconds' walk: the spawn to the circle, the circle to every warehouse's door and
    # to every shop
    if not inside(PLAZA, BOUNDS, HEDGE):
        bad.append("the plaza outside the lobby")
    if walk(SPAWN["x"], SPAWN["z"], p["x"], p["z"]) > 4:
        bad.append("the spawn too far from the PLAY circle")
    for q in PLOTS:
        if walk(p["x"], p["z"], q["x"], q["wall"]) > 14:
            bad.append(f"plot {q['id']}'s door too far from the PLAY circle")
    for k, v in sh.items():
        s = v["spot"]
        if walk(p["x"], p["z"], s["x"], s["z"]) > 10:
            bad.append(f"the {k} too far from the PLAY circle")
    across = math.hypot(BOUNDS["x1"] - BOUNDS["x0"], BOUNDS["z1"] - BOUNDS["z0"])
    if across / 14 >= 40:
        bad.append(f"the lobby too big to cross in 40 s ({across:.0f} studs corner to corner)")
    return bad


# ── The picture ────────────────────────────────────────────────────────────────────────────────────────────────────

S = 2.6  # px per stud
PANEL = 560
TOP = 130
W = int((BOUNDS["x1"] - BOUNDS["x0"]) * S) + PANEL + 40
H = max(int((BOUNDS["z1"] - BOUNDS["z0"]) * S) + TOP + 40, 860)
COL = {
    "grass": (104, 146, 66), "plaza": (196, 188, 172), "plaza2": (176, 168, 152), "concrete": (200, 197, 190),
    "warehouse": (150, 160, 172), "hedge": (52, 96, 44), "label": (32, 32, 36), "accent": (240, 130, 40),
    "white": (250, 250, 250), "text2": (205, 205, 210), "water": (76, 140, 190), "tree": (48, 100, 46), "play": (90, 210, 255),
    "paint": (214, 72, 120), "board": (40, 70, 140), "auction": (226, 214, 186), "lamp": (60, 60, 64),
    "dispatch": (238, 140, 40), "back": (255, 206, 92),
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


def picture(p, sh, path):
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
    for q in PLOTS:
        draw.rectangle(R(q["rect"]), fill=COL["concrete"])
        draw.rectangle(R(rect(q["x"] - 40, q["x"] + 40, q["wall"] - 60, q["wall"])), fill=COL["warehouse"], outline=(70, 76, 84), width=3)
        big = R(rect(q["x"] - 52, q["x"] + 52, q["wall"] - 84, q["wall"]))
        for k in range(int(big[0]), int(big[2]), 12):
            draw.line([k, big[1], k + 6, big[1]], fill=(90, 96, 104), width=2)
        for k in range(int(big[1]), int(big[3]), 12):
            draw.line([big[0], k, big[0], k + 6], fill=(90, 96, 104), width=2)
            draw.line([big[2], k, big[2], k + 6], fill=(90, 96, 104), width=2)
        door = R(rect(q["x"] - 13, q["x"] + 13, q["wall"] - 2, q["wall"]))
        draw.rectangle(door, fill=(60, 64, 70))
        draw.text(P(q["x"], q["wall"] - 36), f"PLOT {q['id']}", font=font(22, True), fill=(30, 34, 40), anchor="mm")
        draw.text(P(q["x"], q["wall"] - 20), "Deliveros warehouse", font=font(15), fill=(30, 34, 40), anchor="mm")
        draw.text(P(q["x"], q["wall"] + 22), "the bay", font=font(14), fill=(110, 110, 110), anchor="mm")
    # the fountain, the dispatch, the spawn
    fx, fz = P(FOUNTAIN["x"], FOUNTAIN["z"])
    fr = FOUNTAIN["r"] * S
    draw.ellipse([fx - fr, fz - fr, fx + fr, fz + fr], fill=(150, 146, 140))
    draw.ellipse([fx - fr + 6, fz - fr + 6, fx + fr - 6, fz + fr - 6], fill=COL["water"])
    d = DISPATCH
    draw.rectangle(R(rect(d["x"] - 3, d["x"] + 3, d["z"] - 4, d["z"] + 4)), fill=COL["dispatch"], outline=(60, 40, 20), width=2)
    for k in range(-1, 2):
        sx, sz = P(SPAWN["x"] + k * SPAWN_APART, SPAWN["z"])
        draw.ellipse([sx - 6, sz - 6, sx + 6, sz + 6], fill=COL["white"], outline=COL["accent"], width=3)
    # the PLAY circle: its dark rim, the glowing ring, PLAY in it; the way back (gold dots: a party of four)
    cx, cz = P(p["x"], p["z"])
    r = p["r"] * S
    draw.ellipse([cx - r - 4, cz - r - 4, cx + r + 4, cz + r + 4], fill=(34, 40, 48))
    draw.ellipse([cx - r, cz - r, cx + r, cz + r], fill=COL["play"])
    inner = (p["r"] - 1.6) * S
    draw.ellipse([cx - inner, cz - inner, cx + inner, cz + inner], fill=(58, 92, 116))
    draw.text((cx, cz), "PLAY", font=font(24, True), fill=COL["white"], anchor="mm")
    for k in range(4):
        across = (1 if k % 2 == 1 else -1) * math.ceil(k / 2) * 3.5
        bx, bz = P(p["back"]["x"] + across, p["back"]["z"])
        draw.ellipse([bx - 4, bz - 4, bx + 4, bz + 4], fill=COL["back"], outline=(60, 40, 20), width=1)
    # the lamps and trees
    for x, z in LAMPS:
        lx, lz = P(x, z)
        draw.ellipse([lx - 4, lz - 4, lx + 4, lz + 4], fill=COL["lamp"])
    for kind, x, z in TREES:
        tx, tz = P(x, z)
        tr = 9 * S
        draw.ellipse([tx - tr + 3, tz - tr + 4, tx + tr + 3, tz + tr + 4], fill=(30, 50, 30))
        draw.ellipse([tx - tr, tz - tr, tx + tr, tz + tr], fill=COL["tree"] if kind != "birch" else (92, 140, 70))
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
    tag(p["x"] + p["r"] + 3, p["z"] - p["r"] - 2, "PLAY", "step in: a lobby, a run", (0, 1))
    tag(p["back"]["x"] - 9, p["back"]["z"], "BACK FROM A RUN", None, (1, 0.5))
    tag(DISPATCH["x"] - 6, DISPATCH["z"] - 8, "DISPATCH", "how runs work", (1, 1))
    tag(SPAWN["x"], SPAWN["z"] + 6, "SPAWN", None, (0.5, 0))
    tag(sh["paint"]["spot"]["x"] + 6, sh["paint"]["spot"]["z"] + 13, "PAINT SHOP", "your truck's colours", (0, 0))
    tag(LEADERS["x"] - 4, LEADERS["z"] + 14, "TOP MOVERS", "the board", (0.5, 0))
    tag(AUCTION["x"] + 17, AUCTION["z"] + 28, "AUCTION HOUSE", "its place (off for now)", (0.5, 0))
    tag(FOUNTAIN["x"], FOUNTAIN["z"] + 12, "fountain", None, (0.5, 0))
    # the title
    draw.rectangle([0, 0, W, TOP - 10], fill=(28, 30, 34))
    draw.text((24, 16), "DELIVEROS · THE LOBBY (10.4: ONE PLAY CIRCLE)", font=font(40, True), fill=COL["white"])
    draw.text((24, 70), "Seen from above, north up. The whole visible world: the four warehouses, the plaza, the PLAY circle, "
              "the dispatch and the shops.", font=font(19), fill=COL["text2"])
    # the legend
    lx = W - PANEL + 10
    y = TOP + 10
    draw.text((lx, y), "PLAY: A PARTY'S LOBBY", font=font(24, True), fill=COL["white"])
    y += 40
    for text in ("Step into the glowing PLAY circle: the PLAY", "panel opens. CREATE A LOBBY (a house, a",
                 "difficulty, public or friends only) or JOIN", "an open one (4 players at most).",
                 "In the lobby: everybody READY, the host", "presses START: 5 s, then the run.",
                 "While you wait, walk anywhere (your", "warehouse too): only LEAVE leaves.",
                 "After the run the party lands beside", "the circle (the gold dots), never in it."):
        draw.text((lx, y), text, font=font(17), fill=COL["text2"])
        y += 26
    y += 14
    draw.text((lx, y), "A FEW SECONDS' WALK", font=font(24, True), fill=COL["white"])
    y += 36
    for text, secs in (("the spawn → PLAY", walk(SPAWN["x"], SPAWN["z"], p["x"], p["z"])),
                       ("PLAY → the nearer warehouses", walk(p["x"], p["z"], PLOTS[1]["x"], WALL)),
                       ("PLAY → the outer warehouses", walk(p["x"], p["z"], PLOTS[0]["x"], WALL)),
                       ("PLAY → the PAINT shop", walk(p["x"], p["z"], PAINT["spot"]["x"], PAINT["spot"]["z"]))):
        draw.text((lx, y), f"{text}: {secs:.1f} s", font=font(17), fill=COL["text2"])
        y += 26
    y += 14
    draw.text((lx, y), "LEGEND", font=font(24, True), fill=COL["white"])
    y += 36
    for colour, text in ((COL["play"], "the PLAY circle (glowing ring)"), (COL["plaza"], "the plaza (paved)"), (COL["concrete"], "a plot's concrete"),
                         (COL["warehouse"], "a warehouse (level 4; dashed: level 5)"), (COL["paint"], "the PAINT shop"),
                         (COL["board"], "the TOP MOVERS board"), (COL["hedge"], "the hedge round the lobby")):
        draw.rectangle([lx, y + 3, lx + 26, y + 23], fill=colour, outline=(20, 20, 20))
        draw.text((lx + 38, y + 2), text, font=font(17), fill=COL["white"])
        y += 30
    y += 10
    draw.text((lx, y), f"lobby {BOUNDS['x1'] - BOUNDS['x0']} × {BOUNDS['z1'] - BOUNDS['z0']} studs (9.7: 480 × 400) on its island; the six", font=font(16), fill=COL["text2"])
    draw.text((lx, y + 22), f"other islands {FAR}+ studs off it (design/islands/plan.png)", font=font(16), fill=COL["text2"])
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
    p, sh = play(), shops()
    bad = check(p, sh)
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
        "play": p,
        "shops": sh,
        "lamps": [{"x": x, "z": z} for x, z in LAMPS],
        "trees": [{"kind": k, "x": x, "z": z} for k, x, z in TREES],
    }
    with open(os.path.join(HERE, "plan.json"), "w", encoding="utf-8") as out:
        json.dump(plan, out, ensure_ascii=False, indent=1)
    picture(p, sh, os.path.join(HERE, "plan.png"))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
