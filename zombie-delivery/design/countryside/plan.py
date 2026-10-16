#!/usr/bin/env python3
"""The countryside instead of the village (the owner: "all the family houses are gone; instead six different spots: by
the pond, on the farm, one house, somewhere else again; no towns, no villages"): the sandbox map as plain data and a
picture.

Writes, next to this file:
  plan.json   every road, spot, landmark, field, lawn, wood, stream and tree line, in SandboxMap's units and axes (studs;
              x east, z south: -z is north; a spot's yaw as SandboxMap's: 0 looks north, 90 west, 180 south, 270 east;
              a curb is the van's pivot as SandboxMap.House.curb: the Sprinter (21.8 long, 8 wide) its back 2 studs in
              from the edge of its yard nearest the door, its nose away from the door)
  plan.png    the same seen from above, north up, the six spots labelled

Open countryside with six separate places to empty, each its own spot with its own surroundings, joined to the depot
by country lanes (22 wide, narrower than Pražská's 28; each ends in a yard where the van turns round):
  1 The Old Farmstead    the farm: Pražská's end, unmoved; a barn, round bales and a haystack, a fenced paddock, a muck
                         heap and woodpile, an old tractor with its trailer, fields round it
  2 The Pond Cabin       by the pond (Pond Lane): a fishing cabin on its east shore, a jetty, reeds, a rowing boat, a bench
  3 The Lone House       one house alone (Hill Road): a family house by a country road among fields, its garden fenced,
                         a couple of trees, no neighbours
  4 The Forest Lodge     in a wood (Wood Lane): a forester's lodge in a clearing of the forest, a woodpile, a stump
  5 The Old Mill         on a stream (Mill Lane): the millrace past its right-hand side (west, seen facing its door),
                         a weir upstream, a footbridge downstream
  6 The Orchard Cottage  in the orchard (Orchard Lane): rows of fruit trees, beehives, a fence round it
The fixed things stay exactly where they are (shared/SandboxMap.luau): the four plots and Depot Row, Pražská, the
turnaround and the farmstead, the Auction House's site, the TOP MOVERS board, the signpost; the D5 at the east edge with
its cars; the railway along the south edge (a lone halt, under the D5). Nothing overlaps anything else: check() says.

tools/countryside/sandboxmap.py writes this plan into shared/SandboxMap.luau (its COUNTRYSIDE section); SandboxMap.Houses
is written by hand from `spots` (tests/sandboxhouses_test.luau holds them together). Deterministic (no dice).

    python3 design/countryside/plan.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

# ── The fixed world (shared/SandboxMap.luau, unchanged) ───────────────────────────────────────────────────────────

BOUNDS = {"x0": -1180, "x1": 420, "z0": -680, "z1": 760}
PLOT_X = [-195, -65, 65, 195]
PLOTS = [{"id": i + 1, "rect": {"x0": x - 60, "x1": x + 60, "z0": -230, "z1": -78},
          "warehouse": {"x": x, "z": -160, "sx": 80, "sz": 60}} for i, x in enumerate(PLOT_X)]
TURNAROUND = {"x": 0, "z": 470, "r": 34}
SHOULDER = 4  # SandboxScenery.Run: the gravel shoulder round every road
LANE = 22  # a country lane's width (Pražská and Depot Row are 28)
VAN_LENGTH, VAN_WIDTH = 21.8, 8.0  # the Sprinter (SprinterLooks.Length, Config.Sprinter.Width)
CURB_IN = 2 + 11  # a curb's pivot from its yard's edge: the van's back 2 in, its middle 11 on
DOOR_IN = 1.2  # a door spot from its box's front edge (the look's front wall 1.5 in, the door 0.3 out of it)
LOT_BACK = 6  # a lot reaches this far round its box (but its front: to its yard's edge, 10 out: the front garden)


def rect(x0, x1, z0, z1):
    return {"x0": x0, "x1": x1, "z0": z0, "z1": z1}


# Things that stand where they stand (not the plan's to move): the Auction House's site (shared/AuctionHouseLayout.luau
# site(), built while Config.Auction.On), the TOP MOVERS board (SandboxLeadersRules.spot(): Pražská's east edge + 26,
# Depot Row's south edge + 24, turned 45°; its footprint round it), the signpost at the crossroads.
FIXED = [
    {"id": "auction", "name": "Auction House", "rect": rect(132, 184, -26, 12)},
    {"id": "leaders", "name": "TOP MOVERS board", "rect": rect(26, 54, -36, -8)},
    {"id": "signpost", "name": "Signpost", "rect": rect(-34, -18, -42, -26)},
]

# ── The roads ──────────────────────────────────────────────────────────────────────────────────────────────────────

# name, rect, yard (the spot's turning yard at the lane's end: part of its lane, its name the lane's), fixed (today's).
# Pražská runs from Depot Row's north edge (z -74) as SandboxMap has it; a lane's rects only touch, never overlap.
ROADS = [
    ("Pražská", rect(-14, 14, -74, 470), False, True),
    ("Depot Row", rect(-270, 270, -74, -46), False, True),
    # west from Depot Row's end to the mill's yard (the forest's and the lone house's lanes turn off it)
    ("Mill Lane", rect(-1012, -270, -71, -49), False, False),
    ("Mill Lane", rect(-1066, -1012, -84, -36), True, False),
    # north off Mill Lane into the forest, to the lodge's clearing
    ("Wood Lane", rect(-951, -929, -404, -71), False, False),
    ("Wood Lane", rect(-967, -913, -452, -404), True, False),
    # north off Mill Lane between the fields, the lone house's pull-in on its west side at its end
    ("Hill Road", rect(-531, -509, -440, -71), False, False),
    ("Hill Road", rect(-583, -531, -460, -412), True, False),
    # north from Depot Row's east end past the plots, the cottage's yard at the orchard's edge
    ("Orchard Lane", rect(270, 292, -494, -46), False, False),
    ("Orchard Lane", rect(222, 270, -494, -446), True, False),
    # west off Pražská across the fields, then south to the pond
    ("Pond Lane", rect(-896, -14, 320, 342), False, False),
    ("Pond Lane", rect(-896, -874, 342, 446), False, False),
    ("Pond Lane", rect(-922, -874, 446, 494), True, False),
]

# ── The six spots ──────────────────────────────────────────────────────────────────────────────────────────────────

# id, name, the owner's words (Czech), street, look, kind, box (its footprint: sx along its front × sz deep, turned
# with its yaw), yaw (the way its front door looks). The farmstead's door, curb, lot and back door are today's.
SPOTS = [
    ("sandbox_house", "The Old Farmstead", "Statek (na farmě)", "Pražská", "farmstead", "big", rect(-22, 22, 523, 557), 0),
    ("pond_cabin", "The Pond Cabin", "Chata u rybníka", "Pond Lane", "cabin", "house", rect(-950, -932, 458, 482), 270),
    ("lone_house", "The Lone House", "Samota u cesty", "Hill Road", "old", "house", rect(-617, -593, -451, -421), 270),
    ("forest_lodge", "The Forest Lodge", "Hájovna v lese", "Wood Lane", "lodge", "house", rect(-954, -926, -484, -462), 180),
    ("old_mill", "The Old Mill", "Starý mlýn na potoce", "Mill Lane", "mill", "house", rect(-1072, -1048, -26, 0), 0),
    ("orchard_cottage", "The Orchard Cottage", "Chalupa v sadu", "Orchard Lane", "cottage", "house", rect(192, 212, -483, -457), 270),
]
FARMSTEAD = {"lot": rect(-60, 60, 504, 600), "door": {"x": 0, "z": 523, "yaw": 0}, "curb": {"x": 0, "z": 492, "yaw": 0},
             "back": {"x": 0, "z": 557, "yaw": 180}}
LOOK = {0: (0, -1), 90: (-1, 0), 180: (0, 1), 270: (1, 0)}  # the way a yaw looks (x, z)

# ── The landmarks (each spot's surroundings, the D5, the railway) ───────────────────────────────────────────────────

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
    # the map's: the D5 (its cars: client/VillageTraffic.luau), the railway under it and its lone halt
    ("d5", "D5 Motorway", "motorway", rect(330, 390, -680, 760), 90, None),
    ("railway", "Railway", "railway", rect(-1180, 330, 716, 728), 90, None),
    ("railway_east", "Railway", "railway", rect(390, 420, 716, 728), 270, None),
    ("halt", "Meadow Halt", "halt", rect(140, 220, 700, 716), 0, None),
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

# Fields: rect, kind (VillageLooks' crops), each 10 off a road's asphalt, clear of everything else.
FIELDS = [
    # the north, round the lone house
    (rect(-750, 20, -680, -520), "rapeseed"),
    (rect(-750, -635, -510, -250), "wheat"),
    (rect(-625, -541, -402, -250), "young"),
    (rect(-499, 20, -510, -240), "wheat"),
    (rect(-499, -280, -230, -81), "ploughed"),
    # between the forest and Mill Lane
    (rect(-1060, -961, -240, -94), "young"),
    (rect(-919, -541, -240, -81), "rapeseed"),
    # between Mill Lane and Pond Lane
    (rect(-1002, -660, -39, 310), "wheat"),
    (rect(-640, -300, -39, 310), "ploughed"),
    (rect(-280, -36, -36, 310), "rapeseed"),
    # the south: the pond's, the farm's
    (rect(-1150, -884, 570, 706), "young"),
    (rect(-864, -520, 352, 706), "ploughed"),
    (rect(-500, -180, 352, 706), "wheat"),
    (rect(-170, -48, 352, 450), "rapeseed"),
    (rect(-170, -66, 600, 706), "young"),
    # the east, between Pražská and the D5
    (rect(24, 296, 28, 300), "young"),
    (rect(48, 296, 310, 496), "rapeseed"),
    (rect(160, 296, 506, 690), "wheat"),
]

# Lawns (ground tiles of their own, flush with the meadow): the forest's floor (the forest less its clearings).
def forest_floor():
    out = []
    for wood in WOODS:
        r = wood["rect"]
        c = wood["clearings"][0]
        out += [rect(r["x0"], r["x1"], r["z0"], c["z0"]), rect(r["x0"], r["x1"], c["z1"], r["z1"]),
                rect(r["x0"], c["x0"], c["z0"], c["z1"]), rect(c["x1"], r["x1"], c["z0"], c["z1"])]
    return [{"kind": "forest", "rect": r} for r in out]


# Tree lines: polyline, kind: "windbreak" (VillageLooks' mix), "alley" (fruit trees along a road), "hedge" (a low hedge,
# CountryLooks), "fence" (a post-and-rail fence, CountryLooks).
TREE_LINES = [
    ([(312, -20), (312, 700)], "windbreak"),  # along the D5
    ([(-650, -27), (-650, 300)], "windbreak"),
    ([(-290, -27), (-290, 300)], "windbreak"),
    ([(-510, 362), (-510, 700)], "windbreak"),
    ([(-480, -515), (10, -515)], "windbreak"),
    ([(-497, -430), (-497, -92)], "alley"),  # along Hill Road
    ([(-860, 306), (-40, 306)], "alley"),  # along Pond Lane
    ([(-905, -79), (-560, -79)], "hedge"),  # along Mill Lane
    ([(-860, 349), (-180, 349)], "hedge"),  # along Pond Lane's south side
    ([(-170, 596), (-170, 700)], "hedge"),  # the farm's west field
    # the orchard's fence, its gate at the cottage
    ([(217, -495), (217, -650), (30, -650), (30, -300), (217, -300), (217, -445)], "fence"),
]


# ── The derived data ───────────────────────────────────────────────────────────────────────────────────────────────

def overlap(a, b, margin=0):
    return a["x0"] < b["x1"] + margin and b["x0"] < a["x1"] + margin and a["z0"] < b["z1"] + margin and b["z0"] < a["z1"] + margin


def grow(r, by):
    return rect(r["x0"] - by, r["x1"] + by, r["z0"] - by, r["z1"] + by)


def yard_of(street):
    return next(r for name, r, yard, _ in ROADS if name == street and yard)


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


def check(sp):
    """Everything the plan promises: returns the failures (empty: all fine)."""
    bad = []
    roads = [(name, r) for name, r, _, _ in ROADS]
    # every curb: the van on asphalt (its back, nose and corners), its back nearer the door
    def on_road(x, z):
        t = TURNAROUND
        return any(r["x0"] - 1e-6 <= x <= r["x1"] + 1e-6 and r["z0"] - 1e-6 <= z <= r["z1"] + 1e-6 for _, r in roads) \
            or math.hypot(x - t["x"], z - t["z"]) <= t["r"]
    for s in sp:
        c, d = s["curb"], s["door"]
        lx, lz = LOOK[c["yaw"]]
        hl, hw = VAN_LENGTH / 2, VAN_WIDTH / 2
        back, nose = (c["x"] - lx * hl, c["z"] - lz * hl), (c["x"] + lx * hl, c["z"] + lz * hl)
        px, pz = -lz * hw, lx * hw
        corners = [back, nose, (back[0] + px, back[1] + pz), (back[0] - px, back[1] - pz), (nose[0] + px, nose[1] + pz), (nose[0] - px, nose[1] - pz)]
        if not all(on_road(*p) for p in corners):
            bad.append(f"{s['id']}: the van off the asphalt")
        if math.hypot(back[0] - d["x"], back[1] - d["z"]) >= math.hypot(nose[0] - d["x"], nose[1] - d["z"]):
            bad.append(f"{s['id']}: the van's nose to the door")
    # the roads: none over another (they only touch)
    for i, (na, a) in enumerate(roads):
        for nb, b in roads[i + 1:]:
            if overlap(a, b, -1e-6) and {na, nb} != {"Pražská", "Depot Row"}:  # (Pražská from Depot Row's north edge)
                bad.append(f"roads {na} and {nb} over each other")
    # the areas that must never overlap: every road with its shoulder, the plots, the turnaround, the spots' boxes and
    # lots, the landmarks, the fields, the streams, the fixed things
    areas = [(f"road {n}", grow(r, SHOULDER)) for n, r in roads]
    areas += [(f"plot {p['id']}", p["rect"]) for p in PLOTS]
    t = TURNAROUND
    areas.append(("turnaround", rect(t["x"] - t["r"] - SHOULDER, t["x"] + t["r"] + SHOULDER, t["z"] - t["r"] - SHOULDER, t["z"] + t["r"] + SHOULDER)))
    areas += [(f"spot {s['id']}", s["box"]) for s in sp]
    areas += [(f"lot {s['id']}", s["lot"]) for s in sp]
    areas += [(f"landmark {l[0]}", l[3]) for l in LANDMARKS]
    areas += [(f"field {n}", f[0]) for n, f in enumerate(FIELDS)]
    areas += [(f"fixed {f['id']}", f["rect"]) for f in FIXED]
    for st in STREAMS:
        areas += [(f"stream {st['id']}", r) for r in stream_rects(st)]
    allowed = {
        # a lot reaches its yard's edge (the yard's shoulder over its front), the farmstead's the turnaround's ring
        ("road", "lot"), ("lot", "road"), ("turnaround", "lot"), ("lot", "turnaround"),
        ("spot", "lot"), ("lot", "spot"),
        # the roads meet each other, the turnaround is Pražská's end
        ("road", "road"), ("road", "turnaround"), ("turnaround", "road"),
        # a stream's squares overlap each other
        ("stream", "stream"),
    }
    crossing = {("landmark weir", "stream millrace"), ("landmark footbridge", "stream millrace"), ("landmark pond", "stream millrace"),
                ("spot old_mill", "stream millrace")}
    seen = set()
    for i, (na, a) in enumerate(areas):
        for nb, b in areas[i + 1:]:
            ka, kb = na.split(" ")[0], nb.split(" ")[0]
            if (ka, kb) in allowed or (na, nb) in crossing or (nb, na) in crossing:
                continue
            if na == nb:
                continue
            if overlap(a, b, -1e-6):
                key = (na, nb)
                if key not in seen:
                    seen.add(key)
                    bad.append(f"{na} on {nb}")
    # a spot's lot only on its own yard (the yard's shoulder), never another road
    for s in sp:
        for n, r in roads:
            if overlap(s["lot"], r, -1e-6) and not (s["fixed"] and n == "Pražská"):
                bad.append(f"lot {s['id']} on the asphalt of {n}")
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
    # the fields 10 off every road's asphalt
    for n, (f, _) in enumerate(FIELDS):
        for name, r in roads:
            if overlap(f, r, 10 - 1e-6):
                bad.append(f"field {n} within 10 of {name}")
    # inside the Bounds
    for name, r in areas:
        if r["x0"] < BOUNDS["x0"] - 1e-6 or r["x1"] > BOUNDS["x1"] + 1e-6 or r["z0"] < BOUNDS["z0"] - 1e-6 or r["z1"] > BOUNDS["z1"] + 1e-6:
            if not name.startswith("stream"):
                bad.append(f"{name} outside the Bounds")
    return bad


def connected():
    """Every lane reaches Depot Row (rects that touch along 20 studs or more)."""
    roads = [(n, r) for n, r, _, _ in ROADS]
    def joins(a, b):
        x = min(a["x1"], b["x1"]) - max(a["x0"], b["x0"])
        z = min(a["z1"], b["z1"]) - max(a["z0"], b["z0"])
        return (x >= -1e-6 and z >= 20) or (z >= -1e-6 and x >= 20)
    seen = {1}
    grew = True
    while grew:
        grew = False
        for i, (_, a) in enumerate(roads):
            if i in seen:
                continue
            if any(joins(a, roads[j][1]) for j in seen):
                seen.add(i)
                grew = True
    return [roads[i][0] for i in range(len(roads)) if i not in seen]


def lengths(sp):
    """The way from plot 1's spawn along the roads' middle lines to each spot's curb (studs, a Manhattan walk)."""
    out = {}
    for s in sp:
        c = s["curb"]
        sx, sz = -173, -112
        if s["street"] == "Pražská":
            d = abs(sx - 0) + abs(-60 - sz) + abs(c["z"] + 60)
        elif s["street"] == "Orchard Lane":
            d = abs(sx - 281) + abs(-60 - sz) + abs(c["z"] + 60) + abs(c["x"] - 281)
        elif s["street"] == "Pond Lane":
            d = abs(sx) + abs(-60 - sz) + (331 + 60) + abs(-885) + abs(c["z"] - 331) + abs(c["x"] + 885)
        elif s["street"] == "Mill Lane":
            d = abs(sx - c["x"]) + abs(-60 - sz) + abs(c["z"] + 60)
        else:
            lane = next(r for n, r, y, _ in ROADS if n == s["street"] and not y)
            lx = (lane["x0"] + lane["x1"]) / 2
            d = abs(sx - lx) + abs(-60 - sz) + abs(c["z"] + 60) + abs(c["x"] - lx)
        out[s["id"]] = round(d)
    return out


# ── The picture ────────────────────────────────────────────────────────────────────────────────────────────────────

S = 1.2  # px per stud
PANEL = 600  # the legend's width
TOP = 130
W = int((BOUNDS["x1"] - BOUNDS["x0"]) * S) + PANEL
H = int((BOUNDS["z1"] - BOUNDS["z0"]) * S) + TOP + 20

COL = {
    "wheat": (196, 178, 92), "young": (110, 156, 66), "rapeseed": (226, 208, 62), "ploughed": (138, 104, 72),
    "meadow": (112, 152, 72), "forest": (64, 98, 52), "asphalt": (52, 52, 56), "shoulder": (150, 142, 128),
    "concrete": (200, 197, 190), "warehouse": (150, 160, 172), "big": (132, 54, 40), "spot": (176, 78, 56),
    "water": (76, 140, 190), "tree": (40, 92, 40), "alley": (78, 132, 58), "hedge": (52, 96, 44), "fence": (140, 104, 70),
    "label": (32, 32, 36), "accent": (240, 130, 40), "white": (250, 250, 250), "rail": (120, 112, 100),
    "embank": (108, 134, 74), "text2": (205, 205, 210), "wood": (128, 92, 60), "hay": (214, 186, 110), "lot": (128, 168, 86),
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


def road_name(img, name, r):
    f = font(15, True)
    along_x = (r["x1"] - r["x0"]) > (r["z1"] - r["z0"])
    text = name.upper()
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


def trees_at(draw, x, z, r, colour):
    cx, cy = P(x, z)
    rr = r * S
    draw.ellipse([cx - rr + 2, cy - rr + 3, cx + rr + 2, cy + rr + 3], fill=(30, 50, 30))
    draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=colour)


def picture(sp, path):
    img = Image.new("RGB", (W, H), (36, 38, 42))
    draw = ImageDraw.Draw(img)
    draw.rectangle(R(BOUNDS), fill=COL["meadow"])
    for l in forest_floor():
        draw.rectangle(R(l["rect"]), fill=COL["forest"])
    for r, kind in FIELDS:
        box = R(r)
        draw.rectangle(box, fill=COL[kind])
        shade = tuple(max(0, c - 16) for c in COL[kind])
        if r["x1"] - r["x0"] >= r["z1"] - r["z0"]:
            for k in range(int(box[1]) + 6, int(box[3]) - 3, 11):
                draw.line([box[0] + 3, k, box[2] - 3, k], fill=shade, width=2)
        else:
            for k in range(int(box[0]) + 6, int(box[2]) - 3, 11):
                draw.line([k, box[1] + 3, k, box[3] - 3], fill=shade, width=2)
    # the woods' trees (a sketch of the jittered grid) and the orchard's rows
    for wood in WOODS:
        r = wood["rect"]
        n = 0
        for x in range(int(r["x0"]) + 14, int(r["x1"]) - 6, 28):
            for z in range(int(r["z0"]) + 14, int(r["z1"]) - 6, 28):
                n += 1
                jx, jz = (n * 37 % 11) - 5, (n * 53 % 11) - 5
                if any(c["x0"] - 6 <= x <= c["x1"] + 6 and c["z0"] - 6 <= z <= c["z1"] + 6 for c in wood["clearings"]):
                    continue
                if any(r2["x0"] - 18 <= x <= r2["x1"] + 18 and r2["z0"] - 18 <= z <= r2["z1"] + 18 for nm, r2, _, _ in ROADS):
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
    # tree lines, hedges, fences
    for points, kind in TREE_LINES:
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            if kind in ("hedge", "fence"):
                draw.line([P(ax, az), P(bx, bz)], fill=COL[kind], width=5 if kind == "hedge" else 3)
                continue
            step = 26 if kind == "alley" else 36
            n = max(1, int(math.hypot(bx - ax, bz - az) / step))
            for i in range(n + 1):
                trees_at(draw, ax + (bx - ax) * i / n, az + (bz - az) * i / n, 6 if kind == "alley" else 9, COL["alley" if kind == "alley" else "tree"])
    # the streams
    for st in STREAMS:
        pts = [P(x, z) for x, z in st["points"]]
        draw.line(pts, fill=(60, 110, 70), width=int(st["width"] * S) + 6, joint="curve")
        draw.line(pts, fill=COL["water"], width=int(st["width"] * S) + 1, joint="curve")
    # the landmarks
    for lid, name, kind, r, yaw, spot in LANDMARKS:
        box = R(r)
        if kind == "motorway":
            draw.rectangle([box[0], box[1], box[2], box[3]], fill=COL["embank"])
            draw.rectangle([box[0] + 10, box[1], box[2] - 10, box[3]], fill=COL["asphalt"])
            mid = (box[0] + box[2]) / 2
            draw.line([mid, box[1], mid, box[3]], fill=(200, 200, 200), width=3)
            for y in range(int(box[1]), int(box[3]), 40):
                draw.line([box[0] + 20, y, box[0] + 20, y + 18], fill=(230, 230, 230), width=2)
                draw.line([box[2] - 20, y, box[2] - 20, y + 18], fill=(230, 230, 230), width=2)
            draw.line([box[0] + 3, box[1], box[0] + 3, box[3]], fill=(150, 150, 150), width=4)
        elif kind == "railway":
            draw.rectangle(box, fill=COL["rail"])
            for x in range(int(box[0]), int(box[2]), 7):
                draw.line([x, box[1] + 2, x, box[3] - 2], fill=(90, 70, 50), width=2)
            draw.line([box[0], box[1] + 4, box[2], box[1] + 4], fill=(60, 60, 64), width=2)
            draw.line([box[0], box[3] - 4, box[2], box[3] - 4], fill=(60, 60, 64), width=2)
        elif kind == "halt":
            draw.rectangle(box, fill=(176, 174, 168), outline=(90, 90, 96), width=2)
            draw.rectangle([box[0] + 30, box[1] + 2, box[0] + 54, box[1] + 10], fill=(96, 70, 52))
        elif kind == "fishpond":
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
    # the plots
    for p in PLOTS:
        draw.rectangle(R(p["rect"]), fill=COL["concrete"])
        wh = p["warehouse"]
        draw.rectangle(R(rect(wh["x"] - wh["sx"] / 2, wh["x"] + wh["sx"] / 2, wh["z"] - wh["sz"] / 2, wh["z"] + wh["sz"] / 2)),
                       fill=COL["warehouse"], outline=(70, 76, 84), width=3)
    # the roads: shoulders, then the asphalt and the turnaround
    tx, ty = P(TURNAROUND["x"], TURNAROUND["z"])
    tr = TURNAROUND["r"] * S
    for _, r, _, _ in ROADS:
        x0, y0, x1, y1 = R(r)
        draw.rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 4], fill=COL["shoulder"])
    draw.ellipse([tx - tr - 4, ty - tr - 4, tx + tr + 4, ty + tr + 4], fill=COL["shoulder"])
    for _, r, _, _ in ROADS:
        draw.rectangle(R(r), fill=COL["asphalt"])
    draw.ellipse([tx - tr, ty - tr, tx + tr, ty + tr], fill=COL["asphalt"])
    for f in FIXED:
        if f["id"] == "auction":
            draw.rectangle(R(f["rect"]), fill=(226, 214, 186), outline=(40, 40, 44), width=2)
    # the spots: their lots, their boxes, the curb (the van's outline)
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
    seen = set()
    for name, r, yard, _ in ROADS:
        if not yard and name not in seen and name not in ("Depot Row",):
            seen.add(name)
            road_name(img, name, r)
    road_name(img, "Depot Row", ROADS[1][1])
    draw = ImageDraw.Draw(img)
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
    for p in PLOTS:
        x, y = at(p["warehouse"]["x"], p["warehouse"]["z"], -44, -10)
        draw.text((x, y), f"PLOT {p['id']}", font=font(16, True), fill=(30, 34, 40))
    # the spots' labels
    tag(draw, *at(-470, 450, 0, 0), "The Old Farmstead", "the farm: barn, bales, paddock, tractor", True, 1)
    tag(draw, *at(-1150, 590, 0, 0), "The Pond Cabin", "by the pond: jetty, reeds, a boat", True, 2)
    tag(draw, *at(-740, -400, 0, 0), "The Lone House", "one house alone by Hill Road", True, 3)
    tag(draw, *at(-1150, -650, 0, 0), "The Forest Lodge", "in a clearing of the forest", True, 4)
    tag(draw, *at(-1040, 40, 30, 0), "The Old Mill", "on the millrace: weir, footbridge", True, 5)
    tag(draw, *at(-60, -640, 0, 0), "The Orchard Cottage", "fruit trees, beehives, a fence", True, 6)
    tag(draw, *at(150, 640, 0, -10), "Meadow Halt", "the railway, under the D5")
    tag(draw, *at(250, -140, -10, 0), "D5", "its cars")
    tag(draw, *at(-500, -200, 0, 30), "Fields", "rapeseed, wheat, ploughed, young")
    tag(draw, *at(186, -36, 4, 10), "Auction House")
    # the title
    draw.rectangle([0, 0, W, TOP - 10], fill=(28, 30, 34))
    draw.text((24, 16), "ZOMBIE DELIVERY · THE COUNTRYSIDE (SANDBOX MAP)", font=font(40, True), fill=COL["white"])
    draw.text((24, 70), "Seen from above, north up. No village and no town: six places to empty, each on its own, "
              "joined to the depot by country lanes. Plots, Depot Row, Pražská and the farmstead stay where they are.",
              font=font(20), fill=COL["text2"])
    # the legend
    lx = W - PANEL + 24
    y = TOP + 10
    draw.text((lx, y), "THE SIX PLACES TO EMPTY", font=font(24, True), fill=COL["white"])
    y += 42
    lengths_ = lengths(sp)
    for i, s in enumerate(sp):
        draw.ellipse([lx, y + 2, lx + 26, y + 28], fill=COL["accent"])
        draw.text((lx + 13, y + 15), str(i + 1), font=font(16, True), fill=COL["white"], anchor="mm")
        draw.text((lx + 38, y), f"{s['name']} · {s['street']}", font=font(19, True), fill=COL["white"])
        draw.text((lx + 38, y + 26), f"{s['label']} · {s['look']} · about {lengths_[s['id']]} studs from plot 1", font=font(16), fill=COL["text2"])
        y += 60
    y += 10
    draw.text((lx, y), "LEGEND", font=font(24, True), fill=COL["white"])
    y += 40
    rows = [
        (COL["accent"], "the six places to empty (their box, the van's spot)"),
        (COL["lot"], "a place's lot (its garden)"),
        (COL["asphalt"], "roads: lanes 22 wide, each ends in a yard"),
        (COL["warehouse"], "the ZDC plots and warehouses (unchanged)"),
        (COL["forest"], "the forest's floor and trees"),
        (COL["water"], "the pond and the millrace"),
        (COL["rapeseed"], "rapeseed"), (COL["wheat"], "wheat"), (COL["ploughed"], "ploughed"), (COL["young"], "young crop"),
        (COL["hedge"], "hedges, windbreaks, fruit alleys"),
        (COL["fence"], "fences (orchard, paddock, garden)"),
        (COL["rail"], "the railway, a lone halt"),
    ]
    for colour, text in rows:
        draw.rectangle([lx, y + 3, lx + 26, y + 23], fill=colour, outline=(20, 20, 20))
        draw.text((lx + 38, y + 2), text, font=font(18), fill=COL["white"])
        y += 31
    y += 12
    draw.text((lx, y), f"map {BOUNDS['x1'] - BOUNDS['x0']} × {BOUNDS['z1'] - BOUNDS['z0']} studs, as before", font=font(17), fill=COL["text2"])
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
    bad = check(sp)
    alone = connected()
    if alone:
        bad.append("roads not joined to Depot Row: " + ", ".join(alone))
    print("plan check: " + ("all fine" if not bad else "BAD\n  " + "\n  ".join(bad)))
    plan = {
        "about": "The countryside instead of the village: the sandbox map (design/countryside/plan.py). Studs; x east, z south; "
                 "yaw as SandboxMap (0 north, 90 west, 180 south, 270 east). Fixed entries are today's SandboxMap data.",
        "bounds": BOUNDS,
        "plots": PLOTS,
        "turnaround": TURNAROUND,
        "fixed": FIXED,
        "roads": [{"name": n, "rect": r, "yard": y, "fixed": f} for n, r, y, f in ROADS],
        "spots": sp,
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
    picture(sp, os.path.join(HERE, "plan.png"))
    print("from plot 1 (studs along the roads): " + ", ".join(f"{k} {v}" for k, v in lengths(sp).items()))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
