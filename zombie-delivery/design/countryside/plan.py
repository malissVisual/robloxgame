#!/usr/bin/env python3
"""The countryside instead of the village (the owner: "all the family houses are gone; instead six different spots: by
the pond, on the farm, one house, somewhere else again; no towns, no villages"); 9.7 runs (the owner: "like Dungeon
Quest: from the lobby you go into a house"): the six places to empty as run zones, the sandbox's map as plain data and a
picture.

Writes, next to this file:
  plan.json   every yard, spot, zone, landmark, lawn, wood, stream and tree line, in SandboxMap's units and axes (studs;
              x east, z south: -z is north; a spot's yaw as SandboxMap's: 0 looks north, 90 west, 180 south, 270 east;
              a curb is the van's pivot as SandboxMap.House.curb: the Sprinter (21.8 long, 8 wide) its back 2 studs in
              from the edge of its yard nearest the door, its nose away from the door)
  plan.png    the same seen from above, north up, the six zones labelled

9.7 runs: there is no driving any more. The lobby (design/lobby/plan.py, at least FAR studs east of every zone) is the
whole visible world; each of the six places to empty is a run zone of its own, out of sight of the lobby and of each
other (MIN_APART studs between two zones at least, their tall screen hedges): a fenced yard and garden round its
house, its surroundings its scenery, the truck parked at its curb (in its yard: the lanes' yards stay, the lanes are
gone; the farmstead's yard where Pražská's end and its turnaround were). A run's party arrives at its `arrive` spot in
the front yard, facing the door. Nothing else of the old map stays: no plots, no Depot Row or Pražská, no lanes, no
fields, no D5, no railway (the lobby has the plots, the TOP MOVERS board and the Auction House's site).
  1 The Old Farmstead    the farm: a barn, round bales and a haystack, a fenced paddock, a muck heap and woodpile, an
                         old tractor with its trailer
  2 The Pond Cabin       by the pond: a fishing cabin on its east shore, a jetty, reeds, a rowing boat, a bench
  3 The Lone House       one house alone: a family house, its garden fenced, a couple of trees, no neighbours
  4 The Forest Lodge     in a wood: a forester's lodge in a clearing of the forest, a woodpile, a stump
  5 The Old Mill         on a stream: the millrace past its right-hand side (west, seen facing its door), a weir
                         upstream, a footbridge downstream
  6 The Orchard Cottage  in the orchard: rows of fruit trees, beehives, a fence round it
Nothing overlaps anything else: check() says.

tools/countryside/sandboxmap.py writes this plan into shared/SandboxMap.luau (its COUNTRYSIDE section); SandboxMap.Houses
is written by hand from `spots` (tests/sandboxhouses_test.luau holds them together). Deterministic (no dice).

    python3 design/countryside/plan.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

# ── The world ──────────────────────────────────────────────────────────────────────────────────────────────────

# (9.7: the Bounds reach east round the lobby, design/lobby/plan.json: the meadow under both, the invisible walls on them)
BOUNDS = {"x0": -1180, "x1": 2080, "z0": -680, "z1": 760}
VIEW = {"x0": -1180, "x1": 420, "z0": -680, "z1": 760}  # (the picture: the zones' part of the map)
SHOULDER = 4  # SandboxScenery.Run: the gravel shoulder round every yard
VAN_LENGTH, VAN_WIDTH = 21.8, 8.0  # the Sprinter (SprinterLooks.Length, Config.Sprinter.Width)
CURB_IN = 2 + 11  # a curb's pivot from its yard's edge: the van's back 2 in, its middle 11 on
DOOR_IN = 1.2  # a door spot from its box's front edge (the look's front wall 1.5 in, the door 0.3 out of it)
LOT_BACK = 6  # a lot reaches this far round its box (but its front: to its yard's edge, 10 out: the front garden)
ARRIVE = 10  # a run's party arrives this far out of the front door, facing it (SandboxMap.Zones' arrive)
MIN_APART = 200  # studs between two zones at least (their screens out of each other's sight)
FAR = 1000  # studs from the lobby's bounds to every zone at least (design/lobby/plan.py's FAR)


def rect(x0, x1, z0, z1):
    return {"x0": x0, "x1": x1, "z0": z0, "z1": z1}


LOBBY_PLAN = os.path.join(os.path.dirname(HERE), "lobby", "plan.json")
LOBBY = json.load(open(LOBBY_PLAN, encoding="utf-8"))["bounds"] if os.path.exists(LOBBY_PLAN) else rect(1560, 2040, -200, 200)

# ── The yards ──────────────────────────────────────────────────────────────────────────────────────────────────────

# name (the road its spot stood on: the spot's street, the words' "on Pond Lane"), rect: each spot's yard, where its
# truck stands (asphalt, a gravel shoulder round it). The lanes that led to them are gone (9.7: no driving); the
# farmstead's yard is where Pražská's end and its turnaround were.
ROADS = [
    ("Pražská", rect(-30, 30, 452, 504)),
    ("Mill Lane", rect(-1066, -1012, -84, -36)),
    ("Wood Lane", rect(-967, -913, -452, -404)),
    ("Hill Road", rect(-583, -531, -460, -412)),
    ("Orchard Lane", rect(222, 270, -494, -446)),
    ("Pond Lane", rect(-922, -874, 446, 494)),
]

# ── The six spots ──────────────────────────────────────────────────────────────────────────────────────────────────

# id, name, the owner's words (Czech), street, look, kind (its inside's plan: shared/HouseLayout.luau's kind, its
# contract's in Config.Moving.Sandbox.Houses: the farmstead the big house, the lone house a family house, the other
# four shared/Layouts/Countryside.luau's own), box (its footprint: sx along its front × sz deep, turned with its yaw),
# yaw (the way its front door looks). The farmstead's door, curb, lot and back door are today's.
SPOTS = [
    ("sandbox_house", "The Old Farmstead", "Statek (na farmě)", "Pražská", "farmstead", "big", rect(-22, 22, 523, 557), 0),
    ("pond_cabin", "The Pond Cabin", "Chata u rybníka", "Pond Lane", "cabin", "cabin", rect(-950, -932, 458, 482), 270),
    ("lone_house", "The Lone House", "Samota u cesty", "Hill Road", "old", "house", rect(-617, -593, -451, -421), 270),
    ("forest_lodge", "The Forest Lodge", "Hájovna v lese", "Wood Lane", "lodge", "lodge", rect(-954, -926, -484, -462), 180),
    ("old_mill", "The Old Mill", "Starý mlýn na potoce", "Mill Lane", "mill", "mill", rect(-1072, -1048, -26, 0), 0),
    ("orchard_cottage", "The Orchard Cottage", "Chalupa v sadu", "Orchard Lane", "cottage", "cottage", rect(192, 212, -483, -457), 270),
]
FARMSTEAD = {"lot": rect(-60, 60, 504, 600), "door": {"x": 0, "z": 523, "yaw": 0}, "curb": {"x": 0, "z": 492, "yaw": 0},
             "back": {"x": 0, "z": 557, "yaw": 180}}
LOOK = {0: (0, -1), 90: (-1, 0), 180: (0, 1), 270: (1, 0)}  # the way a yaw looks (x, z)

# ── The landmarks (each spot's surroundings; 9.7: the D5, the railway and its halt are gone) ───────────────────────────────────────────────────

# id, name, kind, rect, yaw (its front's look), spot (whose surroundings; None: the map's)
LANDMARKS = [
    # the farm
    ("barn", "The Barn", "barn", rect(-144, -88, 500, 548), 270, "sandbox_house"),
    ("tractor", "The Old Tractor", "tractor", rect(-170, -106, 460, 490), 270, "sandbox_house"),
    ("bales", "The Stackyard", "bales", rect(82, 150, 508, 572), 0, "sandbox_house"),
    ("paddock", "The Paddock", "paddock", rect(-56, 64, 618, 690), 0, "sandbox_house"),
    ("muckheap", "The Muck Heap", "muckheap", rect(-144, -100, 560, 590), 270, "sandbox_house"),
    # the pond
    ("pond", "The Fish Pond", "fishpond", rect(-1160, -957, 380, 560), 270, "pond_cabin"),
    # the lone house
    ("garden", "The Garden", "garden", rect(-625, -583, -510, -466), 270, "lone_house"),
    # the forest lodge
    ("woodyard", "The Woodpile", "woodyard", rect(-999, -973, -480, -456), 180, "forest_lodge"),
    # the mill
    ("weir", "The Weir", "weir", rect(-1088, -1068, -134, -122), 0, "old_mill"),
    ("footbridge", "The Footbridge", "footbridge", rect(-1090, -1066, 12, 20), 0, "old_mill"),
    # the orchard cottage
    ("apiary", "The Beehives", "apiary", rect(150, 186, -432, -414), 270, "orchard_cottage"),
]

# The streams: the millrace from the forest past the mill into the pond (its water `width` wide on its middle line).
STREAMS = [
    {"id": "millrace", "width": 8, "points": [(-1110, -676), (-1096, -560), (-1104, -440), (-1090, -320), (-1092, -200),
                                              (-1078, -134), (-1078, 10), (-1082, 120), (-1070, 250), (-1060, 386)]},
]

# The fish pond's three rounds and its jetty as shared/CountryLooks.luau lays them (POND, JETTY there: across, along,
# radius as shares of its frame's half sides), for the picture.
POND = [(0, 0.135, 0.889), (-0.333, -0.462, 0.556), (0.511, 0, 0.467)]
JETTY = -0.333

# The woods: the forest (its trees on a jittered grid, Config.Country.Woods) and the lodge's clearing in it (no tree).
WOODS = [{"id": "forest", "rect": rect(-1160, -760, -672, -250), "clearings": [rect(-1005, -895, -500, -392)]}]
# The orchard: fruit trees in rows (VillageLooks.orchard), the cottage on its east edge.
ORCHARD = rect(30, 216, -650, -300)

# Fields: none any more (9.7: the fields lay between the lanes; a zone's view ends at its screen hedge).
FIELDS = []

# Lawns (ground tiles of their own, flush with the meadow): the forest's floor (the forest less its clearings).
def forest_floor():
    out = []
    for wood in WOODS:
        r = wood["rect"]
        c = wood["clearings"][0]
        out += [rect(r["x0"], r["x1"], r["z0"], c["z0"]), rect(r["x0"], r["x1"], c["z1"], r["z1"]),
                rect(r["x0"], c["x0"], c["z0"], c["z1"]), rect(c["x1"], r["x1"], c["z0"], c["z1"])]
    return [{"kind": "forest", "rect": r} for r in out]


# ── 9.7 The run zones ──────────────────────────────────────────────────────────────────────────────────────────

# spot id → its zone: the fenced area round its house (its yard, its lot, its surroundings), a screen hedge on its edge
# (CountryLooks' "screen": tall, solid) and invisible walls on it (server/SandboxWorld.luau): nobody wanders off.
ZONES = {
    "sandbox_house": rect(-190, 170, 440, 712),
    "pond_cabin": rect(-1170, -860, 368, 580),
    "lone_house": rect(-650, -515, -525, -395),
    "forest_lodge": rect(-1015, -885, -512, -386),
    "old_mill": rect(-1112, -995, -150, 46),
    "orchard_cottage": rect(108, 292, -548, -384),
}


def screen_line(r):
    return [(r["x0"], r["z0"]), (r["x1"], r["z0"]), (r["x1"], r["z1"]), (r["x0"], r["z1"]), (r["x0"], r["z0"])]


# Tree lines: polyline, kind: "windbreak" (VillageLooks' mix), "alley" (fruit trees along a road), "hedge" (a low hedge,
# CountryLooks), "fence" (a post-and-rail fence, CountryLooks), 9.7 "screen" (a zone's tall screen hedge, CountryLooks).
# (9.7: the lanes' windbreaks, alleys and hedges are gone with the lanes.)
TREE_LINES = [
    # the orchard's fence, its gate at the cottage
    ([(217, -495), (217, -650), (30, -650), (30, -300), (217, -300), (217, -445)], "fence"),
] + [(screen_line(ZONES[sid]), "screen") for sid in ZONES]


# ── The derived data ───────────────────────────────────────────────────────────────────────────────────────────────

def overlap(a, b, margin=0):
    return a["x0"] < b["x1"] + margin and b["x0"] < a["x1"] + margin and a["z0"] < b["z1"] + margin and b["z0"] < a["z1"] + margin


def grow(r, by):
    return rect(r["x0"] - by, r["x1"] + by, r["z0"] - by, r["z1"] + by)


def yard_of(street):
    return next(r for name, r in ROADS if name == street)


def spots():
    """The six spots: the farmstead's today's, the others' door (DOOR_IN in from the box's front edge), curb (CURB_IN in
    from the yard's edge nearest the door, its nose away), lot (the box, LOT_BACK round it, its front to the yard)."""
    out = []
    for sid, name, label, street, look, kind, box, yaw in SPOTS:
        s = {"id": sid, "name": name, "label": label, "street": street, "look": look, "kind": kind, "box": box, "yaw": yaw}
        if sid == "sandbox_house":
            s.update(FARMSTEAD)
            s["fixed"] = True
            out.append(s)
            continue
        ox, oz = LOOK[yaw]
        mx, mz = (box["x0"] + box["x1"]) / 2, (box["z0"] + box["z1"]) / 2
        yard = yard_of(street)
        lot = grow(box, LOT_BACK)
        if yaw == 0:
            door = {"x": mx, "z": box["z0"] + DOOR_IN, "yaw": 0}
            curb = {"x": mx, "z": yard["z1"] - CURB_IN, "yaw": 0}
            lot["z0"] = yard["z1"]
        elif yaw == 180:
            door = {"x": mx, "z": box["z1"] - DOOR_IN, "yaw": 180}
            curb = {"x": mx, "z": yard["z0"] + CURB_IN, "yaw": 180}
            lot["z1"] = yard["z0"]
        elif yaw == 90:
            door = {"x": box["x0"] + DOOR_IN, "z": mz, "yaw": 90}
            curb = {"x": yard["x1"] - CURB_IN, "z": mz, "yaw": 90}
            lot["x0"] = yard["x1"]
        else:
            door = {"x": box["x1"] - DOOR_IN, "z": mz, "yaw": 270}
            curb = {"x": yard["x0"] + CURB_IN, "z": mz, "yaw": 270}
            lot["x1"] = yard["x0"]
        s.update({"door": door, "curb": curb, "lot": lot})
        s["fixed"] = False
        out.append(s)
    # the mill's lot stops at its wall on the millrace (its west side: the water there)
    for s in out:
        if s["id"] == "old_mill":
            s["lot"]["x0"] = s["box"]["x0"]
    return out


def zones(sp):
    """9.7 the run zones: each spot's zone (its rect) and where its party arrives (ARRIVE out of the front door, facing
    it)."""
    out = []
    for s in sp:
        d = s["door"]
        ox, oz = LOOK[d["yaw"]]
        out.append({"id": s["id"], "rect": ZONES[s["id"]],
                    "arrive": {"x": d["x"] + ox * ARRIVE, "y": 3, "z": d["z"] + oz * ARRIVE, "yaw": (d["yaw"] + 180) % 360}})
    return out


def stream_rects(stream, extra=0):
    """A stream's water as small squares along its middle line (for the overlap checks)."""
    out = []
    half = stream["width"] / 2 + extra
    pts = stream["points"]
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        length = math.hypot(bx - ax, bz - az)
        n = max(1, int(length / 2))
        for i in range(n + 1):
            x, z = ax + (bx - ax) * i / n, az + (bz - az) * i / n
            out.append(rect(x - half, x + half, z - half, z + half))
    return out


def check(sp, zs):
    """Everything the plan promises: returns the failures (empty: all fine)."""
    bad = []
    roads = list(ROADS)
    # every curb: the van on its yard's asphalt (its back, nose and corners), its back nearer the door
    def on_road(x, z):
        return any(r["x0"] - 1e-6 <= x <= r["x1"] + 1e-6 and r["z0"] - 1e-6 <= z <= r["z1"] + 1e-6 for _, r in roads)
    for s in sp:
        c, d = s["curb"], s["door"]
        lx, lz = LOOK[c["yaw"]]
        hl, hw = VAN_LENGTH / 2, VAN_WIDTH / 2
        back, nose = (c["x"] - lx * hl, c["z"] - lz * hl), (c["x"] + lx * hl, c["z"] + lz * hl)
        px, pz = -lz * hw, lx * hw
        corners = [back, nose, (back[0] + px, back[1] + pz), (back[0] - px, back[1] - pz), (nose[0] + px, nose[1] + pz), (nose[0] - px, nose[1] - pz)]
        if not all(on_road(*p) for p in corners):
            bad.append(f"{s['id']}: the van off its yard")
        if math.hypot(back[0] - d["x"], back[1] - d["z"]) >= math.hypot(nose[0] - d["x"], nose[1] - d["z"]):
            bad.append(f"{s['id']}: the van's nose to the door")
    # the yards: none over another
    for i, (na, a) in enumerate(roads):
        for nb, b in roads[i + 1:]:
            if overlap(a, b, SHOULDER * 2):
                bad.append(f"yards {na} and {nb} too close")
    # the areas that must never overlap: every yard with its shoulder, the spots' boxes and lots, the landmarks, the
    # streams
    areas = [(f"road {n}", grow(r, SHOULDER)) for n, r in roads]
    areas += [(f"spot {s['id']}", s["box"]) for s in sp]
    areas += [(f"lot {s['id']}", s["lot"]) for s in sp]
    areas += [(f"landmark {l[0]}", l[3]) for l in LANDMARKS]
    for st in STREAMS:
        areas += [(f"stream {st['id']}", r) for r in stream_rects(st)]
    allowed = {("road", "lot"), ("lot", "road"), ("spot", "lot"), ("lot", "spot"), ("stream", "stream")}
    crossing = {("landmark weir", "stream millrace"), ("landmark footbridge", "stream millrace"), ("landmark pond", "stream millrace"),
                ("spot old_mill", "stream millrace")}
    seen = set()
    for i, (na, a) in enumerate(areas):
        for nb, b in areas[i + 1:]:
            ka, kb = na.split(" ")[0], nb.split(" ")[0]
            if (ka, kb) in allowed or (na, nb) in crossing or (nb, na) in crossing or na == nb:
                continue
            if overlap(a, b, -1e-6):
                key = (na, nb)
                if key not in seen:
                    seen.add(key)
                    bad.append(f"{na} on {nb}")
    # a spot's lot only on its own yard (the yard's shoulder), never another
    for s in sp:
        for n, r in roads:
            if overlap(s["lot"], r, -1e-6) and n != s["street"]:
                bad.append(f"lot {s['id']} on the yard of {n}")
    # the mill's millrace runs past its right-hand side (seen facing its front door from outside): its west wall
    mill = next(s for s in sp if s["id"] == "old_mill")
    ox, oz = LOOK[mill["yaw"]]
    # (somebody outside facing the door looks (-ox, -oz); in x-east, z-south axes the right of a look (fx, fz) is
    # (-fz, fx): here (oz, -ox), west for a door looking north)
    rx = oz
    b = mill["box"]
    side = (b["x0"] if rx < 0 else b["x1"]) if rx != 0 else None
    near = min(abs(x - side) for st in STREAMS for x, z in st["points"] if b["z0"] - 30 <= z <= b["z1"] + 30) if side is not None else 99
    # (its water's edge 2 studs off the wall: its bed's bank, 1.5 wide, clear of the wall)
    if side is None or near > STREAMS[0]["width"] / 2 + 2.5:
        bad.append("the millrace is not past the mill's right-hand side")
    # 9.7 the zones: one a spot; each holds its spot's box, lot, yard (and its shoulder), its van, its landmarks and its
    # arrival spot, clear of its screen; none over another, MIN_APART apart, FAR from the lobby, all in the Bounds
    def holds(outer, r, margin):
        return r["x0"] >= outer["x0"] + margin and r["x1"] <= outer["x1"] - margin and r["z0"] >= outer["z0"] + margin and r["z1"] <= outer["z1"] - margin
    for z in zs:
        s = next(x for x in sp if x["id"] == z["id"])
        r = z["rect"]
        things = [("box", s["box"]), ("lot", s["lot"]), ("yard", grow(yard_of(s["street"]), SHOULDER))]
        things += [(f"landmark {l[0]}", l[3]) for l in LANDMARKS if l[5] == s["id"]]
        a = z["arrive"]
        things.append(("arrive", rect(a["x"] - 4, a["x"] + 4, a["z"] - 4, a["z"] + 4)))
        for name, t in things:
            if not holds(r, t, 4):
                bad.append(f"zone {z['id']}: its {name} not inside it")
        if not holds(BOUNDS, r, 0):
            bad.append(f"zone {z['id']} outside the Bounds")
        dx = max(LOBBY["x0"] - r["x1"], r["x0"] - LOBBY["x1"], 0)
        dz = max(LOBBY["z0"] - r["z1"], r["z0"] - LOBBY["z1"], 0)
        if math.hypot(dx, dz) < FAR:
            bad.append(f"zone {z['id']} within {FAR} of the lobby")
    for i, a in enumerate(zs):
        for b in zs[i + 1:]:
            ra, rb = a["rect"], b["rect"]
            dx = max(ra["x0"] - rb["x1"], rb["x0"] - ra["x1"], 0)
            dz = max(ra["z0"] - rb["z1"], rb["z0"] - ra["z1"], 0)
            if math.hypot(dx, dz) < MIN_APART:
                bad.append(f"zones {a['id']} and {b['id']} only {math.hypot(dx, dz):.0f} apart")
    # every landmark in its spot's zone (a landmark of the map's own: none any more)
    for l in LANDMARKS:
        if l[5] is None:
            bad.append(f"landmark {l[0]} belongs to no zone")
    return bad


# ── The picture ────────────────────────────────────────────────────────────────────────────────────────────────────

S = 1.2  # px per stud
PANEL = 600  # the legend's width
TOP = 130
W = int((VIEW["x1"] - VIEW["x0"]) * S) + PANEL
H = int((VIEW["z1"] - VIEW["z0"]) * S) + TOP + 20

COL = {
    "meadow": (112, 152, 72), "forest": (64, 98, 52), "asphalt": (52, 52, 56), "shoulder": (150, 142, 128), "big": (132, 54, 40),
    "spot": (176, 78, 56), "water": (76, 140, 190), "tree": (40, 92, 40), "alley": (78, 132, 58), "hedge": (52, 96, 44),
    "fence": (140, 104, 70), "label": (32, 32, 36), "accent": (240, 130, 40), "white": (250, 250, 250), "text2": (205, 205, 210),
    "wood": (128, 92, 60), "hay": (214, 186, 110), "lot": (128, 168, 86), "screen": (34, 74, 34), "out": (84, 110, 66),
    "zone": (120, 162, 80),
}


def font(size, bold=False):
    for path in (f"/usr/share/fonts/opentype/inter/Inter-{'Bold' if bold else 'Medium'}.otf",
                 f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def P(x, z):
    return ((x - VIEW["x0"]) * S, (z - VIEW["z0"]) * S + TOP)


def R(r):
    a, b = P(r["x0"], r["z0"]), P(r["x1"], r["z1"])
    return [a[0], a[1], b[0], b[1]]


def tag(draw, x, y, text, sub=None, accent=False, number=None):
    f, fs = font(22, True), font(16)
    lead = 34 if number else 0
    tw = max(draw.textlength(text, font=f), draw.textlength(sub, font=fs) if sub else 0) + lead
    h = 34 + (22 if sub else 0)
    draw.rounded_rectangle([x, y, x + tw + 20, y + h], 6, fill=COL["accent"] if accent else COL["label"])
    if number:
        draw.ellipse([x + 7, y + 6, x + 33, y + 32], fill=COL["white"])
        draw.text((x + 20, y + 19), str(number), font=font(18, True), fill=COL["accent"] if accent else COL["label"], anchor="mm")
    draw.text((x + 10 + lead, y + 5), text, font=f, fill=COL["white"])
    if sub:
        draw.text((x + 10 + lead, y + 32), sub, font=fs, fill=COL["white"] if accent else COL["text2"])


def trees_at(draw, x, z, r, colour):
    cx, cy = P(x, z)
    rr = r * S
    draw.ellipse([cx - rr + 2, cy - rr + 3, cx + rr + 2, cy + rr + 3], fill=(30, 50, 30))
    draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=colour)


def near_zone(x, z, zs, margin):
    return any(r["x0"] - margin <= x <= r["x1"] + margin and r["z0"] - margin <= z <= r["z1"] + margin for r in (q["rect"] for q in zs))


def picture(sp, zs, path):
    img = Image.new("RGB", (W, H), (36, 38, 42))
    draw = ImageDraw.Draw(img)
    draw.rectangle(R(VIEW), fill=COL["out"])
    for z in zs:
        draw.rectangle(R(z["rect"]), fill=COL["zone"])
    for l in forest_floor():
        draw.rectangle(R(l["rect"]), fill=COL["forest"])
    # the woods' trees (a sketch of the jittered grid) and the orchard's rows: the ones the zones see
    for wood in WOODS:
        r = wood["rect"]
        n = 0
        for x in range(int(r["x0"]) + 14, int(r["x1"]) - 6, 28):
            for z in range(int(r["z0"]) + 14, int(r["z1"]) - 6, 28):
                n += 1
                jx, jz = (n * 37 % 11) - 5, (n * 53 % 11) - 5
                if any(c["x0"] - 6 <= x <= c["x1"] + 6 and c["z0"] - 6 <= z <= c["z1"] + 6 for c in wood["clearings"]):
                    continue
                if any(abs(x - px) < 16 and abs(z - pz) < 70 for st in STREAMS for px, pz in st["points"]):
                    continue
                trees_at(draw, x + jx, z + jz, 11, COL["tree"] if n % 4 else (70, 120, 60))
    o = ORCHARD
    for x in range(int(o["x0"]) + 18, int(o["x1"]) - 10, 36):
        for z in range(int(o["z0"]) + 16, int(o["z1"]) - 10, 32):
            if 180 <= x <= 230 and -500 <= z <= -440:
                continue
            if 140 <= x <= 196 and -440 <= z <= -406:
                continue
            trees_at(draw, x, z, 8, COL["alley"])
    # the streams
    for st in STREAMS:
        pts = [P(x, z) for x, z in st["points"]]
        draw.line(pts, fill=(60, 110, 70), width=int(st["width"] * S) + 6, joint="curve")
        draw.line(pts, fill=COL["water"], width=int(st["width"] * S) + 1, joint="curve")
    # the landmarks
    for lid, name, kind, r, yaw, spot in LANDMARKS:
        box = R(r)
        if kind == "fishpond":
            # (its three rounds and its jetty as shared/CountryLooks.luau lays them: shares of its frame, its front east)
            cx, cz = (r["x0"] + r["x1"]) / 2, (r["z0"] + r["z1"]) / 2
            hw, hd = (r["z1"] - r["z0"]) / 2, (r["x1"] - r["x0"]) / 2  # (yaw 270: its width along z, its depth along x)
            half = min(hw, hd)
            rounds = [(cx + v * hd, cz - u * hw, k * half) for u, v, k in POND]
            for x, z, rad in rounds:
                a, b = P(x - rad - 4, z - rad - 4), P(x + rad + 4, z + rad + 4)
                draw.ellipse([a[0], a[1], b[0], b[1]], fill=(92, 120, 62))
            for x, z, rad in rounds:
                a, b = P(x - rad, z - rad), P(x + rad, z + rad)
                draw.ellipse([a[0], a[1], b[0], b[1]], fill=COL["water"])
            jz = cz - JETTY * hw
            draw.rectangle(R(rect(cx + hd - 38, cx + hd - 10, jz - 2, jz + 2)), fill=(150, 110, 70))
        elif kind == "barn":
            draw.rectangle(box, fill=(120, 58, 44), outline=(50, 30, 24), width=3)
            draw.line([box[0] + 4, (box[1] + box[3]) / 2, box[2] - 4, (box[1] + box[3]) / 2], fill=(70, 36, 28), width=3)
        elif kind == "paddock":
            draw.rectangle(box, fill=(126, 166, 80), outline=COL["fence"], width=3)
        elif kind == "bales":
            for i in range(6):
                x, z = r["x0"] + 12 + (i % 3) * 20, r["z0"] + 14 + (i // 3) * 22
                a, b = P(x - 6, z - 4), P(x + 6, z + 4)
                draw.ellipse([a[0], a[1], b[0], b[1]], fill=COL["hay"], outline=(150, 120, 60))
            a, b = P(r["x1"] - 22, r["z1"] - 22), P(r["x1"] - 6, r["z1"] - 6)
            draw.ellipse([a[0], a[1], b[0], b[1]], fill=(200, 170, 96), outline=(140, 110, 56), width=2)
        elif kind == "tractor":
            draw.rectangle(R(rect(r["x1"] - 18, r["x1"] - 2, r["z0"] + 8, r["z1"] - 8)), fill=(190, 40, 34))
            draw.rectangle(R(rect(r["x0"] + 4, r["x1"] - 24, r["z0"] + 5, r["z1"] - 5)), fill=(120, 110, 96))
        elif kind == "garden":
            draw.rectangle(box, fill=COL["lot"], outline=COL["fence"], width=2)
            for x, z in ((r["x0"] + 10, r["z0"] + 12), (r["x1"] - 12, r["z0"] + 14), (r["x0"] + 14, r["z1"] - 10)):
                trees_at(draw, x, z, 7, COL["alley"])
        elif kind == "apiary":
            for i in range(5):
                x = r["x0"] + 4 + i * 7
                draw.rectangle(R(rect(x, x + 4, r["z0"] + 6, r["z0"] + 11)), fill=(236, 196, 60))
        elif kind in ("woodyard", "muckheap"):
            draw.rectangle(box, fill=COL["wood"] if kind == "woodyard" else (98, 76, 56))
        elif kind in ("weir", "footbridge"):
            draw.rectangle(box, fill=(150, 150, 146) if kind == "weir" else (150, 110, 70))
        else:
            draw.rectangle(box, fill=(150, 150, 150))
    # the orchard's fence and the zones' screens
    for points, kind in TREE_LINES:
        if kind == "fence":
            draw.line([P(x, z) for x, z in points], fill=COL["fence"], width=3)
    for z in zs:
        b = R(z["rect"])
        draw.rectangle(b, outline=COL["screen"], width=6)
    # the yards: shoulders, then the asphalt
    for _, r in ROADS:
        x0, y0, x1, y1 = R(r)
        draw.rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 4], fill=COL["shoulder"])
    for _, r in ROADS:
        draw.rectangle(R(r), fill=COL["asphalt"])
    # the spots: their lots, their boxes, the curb (the van's outline), where the party arrives
    for i, s in enumerate(sp):
        draw.rectangle(R(s["lot"]), fill=COL["lot"])
    for i, s in enumerate(sp):
        draw.rectangle(R(s["box"]), fill=COL["big"] if i == 0 else COL["spot"], outline=(60, 30, 24), width=2)
        c = s["curb"]
        lx, lz = LOOK[c["yaw"]]
        hl, hw = VAN_LENGTH / 2, VAN_WIDTH / 2
        x0, x1 = sorted((c["x"] - lx * hl - abs(lz) * hw, c["x"] + lx * hl + abs(lz) * hw))
        z0, z1 = sorted((c["z"] - lz * hl - abs(lx) * hw, c["z"] + lz * hl + abs(lx) * hw))
        draw.rectangle(R(rect(x0, x1, z0, z1)), outline=(250, 250, 250), width=2)
        nx, nz = P(c["x"] + lx * hl, c["z"] + lz * hl)
        draw.ellipse([nx - 3, nz - 3, nx + 3, nz + 3], fill=(250, 250, 250))
    for z in zs:
        ax, az = P(z["arrive"]["x"], z["arrive"]["z"])
        draw.ellipse([ax - 4, az - 4, ax + 4, az + 4], fill=(120, 220, 255), outline=(20, 60, 90))
    # the spots' rings and numbers
    fn = font(20, True)
    for i, s in enumerate(sp):
        b = R(s["box"])
        draw.rectangle([b[0] - 5, b[1] - 5, b[2] + 5, b[3] + 5], outline=COL["accent"], width=5)
        cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        draw.ellipse([cx - 15, cy - 15, cx + 15, cy + 15], fill=COL["accent"], outline=COL["white"], width=2)
        draw.text((cx, cy), str(i + 1), font=fn, fill=COL["white"], anchor="mm")

    def at(x, z, dx=0, dy=0):
        px, py = P(x, z)
        return px + dx, py + dy
    # the zones' labels
    tag(draw, *at(-470, 470, 0, 0), "The Old Farmstead", "the farm: barn, bales, paddock, tractor", True, 1)
    tag(draw, *at(-1150, 600, 0, 0), "The Pond Cabin", "by the pond: jetty, reeds, a boat", True, 2)
    tag(draw, *at(-740, -380, 0, 0), "The Lone House", "one house alone, its garden", True, 3)
    tag(draw, *at(-1150, -650, 0, 0), "The Forest Lodge", "in a clearing of the forest", True, 4)
    tag(draw, *at(-980, 60, 10, 0), "The Old Mill", "on the millrace: weir, footbridge", True, 5)
    tag(draw, *at(-60, -640, 0, 0), "The Orchard Cottage", "fruit trees, beehives, a fence", True, 6)
    tag(draw, *at(140, -100, 0, 0), "→ the lobby", f"{LOBBY['x0'] - 420:.0f}+ studs further east")
    # the title
    draw.rectangle([0, 0, W, TOP - 10], fill=(28, 30, 34))
    draw.text((24, 16), "ZOMBIE DELIVERY · THE SIX RUN ZONES (SANDBOX, 9.7)", font=font(40, True), fill=COL["white"])
    draw.text((24, 70), "Seen from above, north up. Each place to empty in its own zone behind a tall screen hedge, out of sight of the "
              "others; the truck parked at its door. The lobby lies far to the east.", font=font(20), fill=COL["text2"])
    # the legend
    lx = W - PANEL + 24
    y = TOP + 10
    draw.text((lx, y), "THE SIX RUN ZONES", font=font(24, True), fill=COL["white"])
    y += 42
    for i, s in enumerate(sp):
        z = next(q for q in zs if q["id"] == s["id"])
        r = z["rect"]
        draw.ellipse([lx, y + 2, lx + 26, y + 28], fill=COL["accent"])
        draw.text((lx + 13, y + 15), str(i + 1), font=font(16, True), fill=COL["white"], anchor="mm")
        draw.text((lx + 38, y), s["name"], font=font(19, True), fill=COL["white"])
        draw.text((lx + 38, y + 26), f"{s['label']} · {s['look']} · zone {r['x1'] - r['x0']:.0f} × {r['z1'] - r['z0']:.0f}", font=font(16), fill=COL["text2"])
        y += 60
    y += 10
    draw.text((lx, y), "LEGEND", font=font(24, True), fill=COL["white"])
    y += 40
    rows = [
        (COL["accent"], "the six places to empty (their box, the truck's spot)"),
        (COL["zone"], "a run zone (fenced: a tall screen hedge, walls)"),
        (COL["lot"], "a place's lot (its garden)"),
        (COL["asphalt"], "its yard: the truck stands there, at its door"),
        ((120, 220, 255), "where the party arrives, facing the door"),
        (COL["forest"], "the forest's floor and trees"),
        (COL["water"], "the pond and the millrace"),
        (COL["fence"], "fences (orchard, paddock, garden)"),
        (COL["out"], "outside every zone: the meadow (nobody goes there)"),
    ]
    for colour, text in rows:
        draw.rectangle([lx, y + 3, lx + 26, y + 23], fill=colour, outline=(20, 20, 20))
        draw.text((lx + 38, y + 2), text, font=font(18), fill=COL["white"])
        y += 31
    y += 12
    draw.text((lx, y), f"zones {MIN_APART}+ studs apart, {FAR}+ from the lobby", font=font(17), fill=COL["text2"])
    # the scale bar and north
    bx, by = W - PANEL + 24, H - 90
    draw.line([bx, by, bx + 100 * S, by], fill=COL["white"], width=4)
    draw.line([bx, by - 8, bx, by + 8], fill=COL["white"], width=3)
    draw.line([bx + 100 * S, by - 8, bx + 100 * S, by + 8], fill=COL["white"], width=3)
    draw.text((bx, by + 12), "100 studs", font=font(16), fill=COL["white"])
    nx, ny = W - 80, H - 100
    draw.polygon([(nx, ny - 34), (nx - 16, ny + 10), (nx + 16, ny + 10)], fill=COL["accent"])
    draw.text((nx, ny + 28), "N", font=font(22, True), fill=COL["white"], anchor="mm")
    draw.text((W - PANEL + 24, H - 40), "Drawn from plan.json (design/countryside/plan.py).", font=font(14), fill=COL["text2"])
    img.save(path, optimize=True)


def main():
    sp = spots()
    zs = zones(sp)
    bad = check(sp, zs)
    print("plan check: " + ("all fine" if not bad else "BAD\n  " + "\n  ".join(bad)))
    plan = {
        "about": "The countryside's six run zones (9.7): the sandbox map's places to empty (design/countryside/plan.py). Studs; x "
                 "east, z south; yaw as SandboxMap (0 north, 90 west, 180 south, 270 east). The lobby: design/lobby/plan.json.",
        "bounds": BOUNDS,
        "roads": [{"name": n, "rect": r, "yard": True} for n, r in ROADS],
        "spots": sp,
        "zones": zs,
        "landmarks": [{"id": i, "name": n, "kind": k, "rect": r, "yaw": y, "spot": s} for i, n, k, r, y, s in LANDMARKS],
        "streams": [{"id": s["id"], "width": s["width"], "points": [{"x": x, "z": z} for x, z in s["points"]]} for s in STREAMS],
        "woods": WOODS,
        "orchard": ORCHARD,
        "fields": [{"rect": r, "kind": k} for r, k in FIELDS],
        "lawns": forest_floor(),
        "treeLines": [{"points": [{"x": x, "z": z} for x, z in pts], "kind": k} for pts, k in TREE_LINES],
    }
    with open(os.path.join(HERE, "plan.json"), "w", encoding="utf-8") as out:
        json.dump(plan, out, ensure_ascii=False, indent=1)
    picture(sp, zs, os.path.join(HERE, "plan.png"))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
