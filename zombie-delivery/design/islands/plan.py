#!/usr/bin/env python3
"""10.6 the floating islands (the owner: "the world is made of blocks: the lobby is one big block, each map a smaller
block that holds only that map ... floating islands in the sky: grass on top, dirt and stone sides with tapering rock
underneath, sky all round and below, the other islands seen in the distance from the lobby"; "travel by a fade"):
the sandbox's world as islands in the sky, as plain data and a picture.

Writes, next to this file:
  plan.json   one entry per island (`islands`: id, the house it holds (none: the lobby), name, its top's middle x, z
              and size sx × sz, its top's height `top`, its `depth` (top to the tip of the rock under it), the walled
              area on it (`walls`), the spot the fall catch puts you back on (`home`), its `look` (the grass, dirt,
              stone and rock colours) and its dice); the decorative floating `rocks`; and every map island's place in
              the countryside plan's shape (design/countryside/plan.py, 9.x, which this plan replaces): `bounds`,
              `roads` (each place's yard: its van parking), `spots` (the six places to empty: box, yaw, door, curb,
              lot; y on its island's top), `zones` (the walled area of each map island and where a run's party
              arrives), `landmarks`, `streams`, `woods`, `orchard`, `fields`, `lawns`, `treeLines` (the orchard's
              fence, a windbreak, every map island's low rim hedge); in SandboxMap's units and axes (studs; x east, z
              south: -z is north; y up; a spot's yaw as SandboxMap's: 0 looks north, 90 west, 180 south, 270 east)
  plan.png    the same seen from above (north up, every island and its place, the first vans of a round parked) and
              from the side (every island at its height, the lobby's and the fall catch's lines)

tools/islands/sandboxmap.py writes plan.json into shared/SandboxMap.luau (its ISLANDS section: SandboxMap.Islands, Rocks,
Bounds, Roads, Landmarks, Fields, Lawns, TreeLines, Woods, Orchard, Streams, Zones and Houses). The lobby's own layout is
design/lobby/plan.py's (its bounds here: the lobby island is them and a rim of grass round them).

Each map island is laid out in its own frame (ISLANDS: its things' rects round its local origin) and put at `centre`
(its top's middle): redesign one by moving its things, nothing else moves. check() says whether everything holds:
  * no two islands within GAP of each other (nobody jumps across); every map island VIEW from the lobby (seen from it);
    the lobby the biggest; their tops at varying heights, from LOW to HIGH over the lobby (the vans' ground rays:
    server/Vehicles.luau groundY looks down from 90 over the road to under the lobby's level); every island's bottom
    over DESTROY (workspace.FallenPartsDestroyHeight: Config.Islands.Destroy); none near the city's mountain
  * every place's things inside its walls with MARGIN, its walls inside its island with RIM; nothing on anything else
    (the yards with their shoulders, the boxes, the lots, the landmarks, the streams; the countryside's rules)
  * VANS: a server-wide round parks every player's van at the place's curb, side by side and in rows behind it (its
    nose's way: shared/RoundRules.luau parking on the rounds branch, its numbers PARK = Config.Rounds.Park): at least
    VANS.Count clear spots on every map island (inside its walls, off the house's lot, on no landmark, tree, stream or
    orchard), that many on its yard's asphalt
  * the mill's stream past its right-hand side and off its island's edge (the waterfall)
Deterministic (no dice).

    python3 design/islands/plan.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOBBY_PLAN = os.path.join(os.path.dirname(HERE), "lobby", "plan.json")
LOBBY = json.load(open(LOBBY_PLAN, encoding="utf-8"))

# ── The numbers ───────────────────────────────────────────────────────────────────────────────────────────────────

GAP = 250  # studs between two islands' tops at least (no jump, no glide gets across)
VIEW = (400, 1500)  # every map island's middle this far from the lobby's (seen from its edge, in the haze's reach)
LOW, HIGH = 6, 80  # a map island's top this high over the lobby's at least, at most (server/Vehicles.luau groundY)
SPREAD = 40  # the tops' heights apart, the highest from the lowest, at least ("at varying heights")
DESTROY = -1000  # workspace.FallenPartsDestroyHeight (Config.Islands.Destroy): under every island's bottom
FALL = 120  # ... and this far under the lowest bottom at least (the fall catch has caught a body long before)
MOUNTAIN = {"x": 300, "z": -1700, "r": 295}  # the city's mountain (shared/Map.luau Mountain + 30): groundY gives up there
RIM = 10  # a map island's grass beyond its walls at least (its rim hedge on the walls)
LOBBY_RIM = 18  # the lobby island's grass beyond the lobby's bounds (its hedge in from them)
MARGIN = 4  # a place's things inside its walls by this much at least
SHOULDER = 4  # SandboxScenery.Run: the gravel shoulder round every yard
VAN_LENGTH, VAN_WIDTH = 21.8, 8.0  # the Sprinter (SprinterLooks.Length, Config.Sprinter.Width)
CURB_IN = 2 + 11  # a curb's pivot from its yard's edge: the van's back 2 in, its middle 11 on
DOOR_IN = 1.2  # a door spot from its box's front edge (the look's front wall 1.5 in, the door 0.3 out of it)
LOT_BACK = 6  # a lot reaches this far round its box (but its front: to its yard's edge, 10 out: the front garden)
ARRIVE = 10  # a run's party arrives this far out of the front door, facing it (SandboxMap.Zones' arrive)
WALLS_HIGH = 10  # a place's walls' height (the farmstead's the owner's Blender house's 14.5)
# A round's vans (Config.Rounds.Park on the rounds branch: Across studs apart side by side, the rows Along apart behind
# the curb's, Cols × Rows looked at, Margin off the walls; a Sprinter with its mirrors Width wide, Length long) and how
# many must find a clear spot on every map island (the server's 16 players)
PARK = {"Across": 13, "Along": 28, "Cols": 17, "Rows": 5, "Margin": 10, "Width": 9.6, "Length": 22}
VANS = 16
LOOK = {0: (0, -1), 90: (-1, 0), 180: (0, 1), 270: (1, 0)}  # the way a yaw looks (x, z)


def rect(x0, x1, z0, z1):
    return {"x0": x0, "x1": x1, "z0": z0, "z1": z1}


def grow(r, by):
    return rect(r["x0"] - by, r["x1"] + by, r["z0"] - by, r["z1"] + by)


def moved(r, dx, dz):
    return rect(r["x0"] + dx, r["x1"] + dx, r["z0"] + dz, r["z1"] + dz)


def size_of(r):
    return r["x1"] - r["x0"], r["z1"] - r["z0"]


def mid(r):
    return (r["x0"] + r["x1"]) / 2, (r["z0"] + r["z1"]) / 2


def overlap(a, b, margin=0):
    return a["x0"] < b["x1"] + margin and b["x0"] < a["x1"] + margin and a["z0"] < b["z1"] + margin and b["z0"] < a["z1"] + margin


def holds(outer, r, margin=0):
    return r["x0"] >= outer["x0"] + margin - 1e-6 and r["x1"] <= outer["x1"] - margin + 1e-6 and r["z0"] >= outer["z0"] + margin - 1e-6 \
        and r["z1"] <= outer["z1"] - margin + 1e-6


def gap(a, b):
    dx = max(a["x0"] - b["x1"], b["x0"] - a["x1"], 0)
    dz = max(a["z0"] - b["z1"], b["z0"] - a["z1"], 0)
    return math.hypot(dx, dz)


def spot(x, z, yaw, y):
    return {"x": x, "y": y, "z": z, "yaw": yaw}


# ── The islands ───────────────────────────────────────────────────────────────────────────────────────────────────

# The lobby island: design/lobby/plan.py's bounds and LOBBY_RIM of grass round them, its top the lobby's ground (y 0:
# SandboxMap.GroundTop; everything of the lobby stands on it as ever).
LB = LOBBY["bounds"]
LOBBY_ISLAND = {
    "id": "lobby", "name": "The Lobby", "top": 0, "depth": 170, "seed": 11,
    "look": {"grass": [96, 138, 60], "dirt": [118, 88, 60], "stone": [132, 126, 118], "rock": [104, 98, 92]},
}

# The six map islands, each in its own frame (studs round its local origin; x east, z south): the house (its box, its
# yaw: the way its front door looks; its yard, the van parking in front of the door: the lot's front edge 10 out of
# the box's front), its landmarks (id, name, kind, rect, yaw: shared/CountryLooks.luau's kinds), the walled area
# (`zone`), its woods (a rect and its clearing: no tree there), its orchard and the orchard's fence, its stream (its
# middle line, `width` wide), its tree lines, and where its top's middle lands on the map (`centre`), its top's height
# (`top`, over the lobby's), its depth (to the tip of the rock under it) and its look.
ISLANDS = [
    {  # 1 the farm: the farmstead (the owner's Blender house), its barn, muck heap, stackyard, old tractor, paddock
        "id": "farm", "house": "sandbox_house", "name": "The Old Farmstead", "label": "Statek (na farmě)", "street": "Pražská",
        "look": "farmstead", "kind": "big", "box": rect(-22, 22, -40, -6), "yaw": 0, "yard": rect(-64, 64, -115, -59),
        # (the farmstead's own lot, door, curb and back door as ever, round its box: its front garden 19 deep)
        "farmstead": {"lot": rect(-60, 60, -59, 37), "door": (0, -40), "curb": (0, -71), "back": (0, -6)},
        "landmarks": [
            ("barn", "The Barn", "barn", rect(-150, -94, -56, -8), 270),
            ("muckheap", "The Muck Heap", "muckheap", rect(-150, -106, 4, 34), 270),
            ("bales", "The Stackyard", "bales", rect(82, 150, -40, 24), 0),
            ("tractor", "The Old Tractor", "tractor", rect(90, 154, 40, 70), 270),
            ("paddock", "The Paddock", "paddock", rect(-40, 60, 44, 102), 0),
        ],
        "zone": rect(-180, 180, -124, 112), "rim": 12,
        "centre": (1100, -620), "top": 28, "depth": 150, "seed": 21,
        "colors": {"grass": [108, 142, 62], "dirt": [124, 90, 58], "stone": [138, 130, 120], "rock": [108, 100, 92]},
    },
    {  # 2 by the pond: the fishing cabin on its shore, the jetty, the boat, the reeds
        "id": "pond", "house": "pond_cabin", "name": "The Pond Cabin", "label": "Chata u rybníka", "street": "Pond Lane",
        "look": "cabin", "kind": "cabin", "box": rect(-20, -2, -12, 12), "yaw": 270, "yard": rect(8, 64, -64, 64),
        "landmarks": [("pond", "The Fish Pond", "fishpond", rect(-230, -27, -90, 90), 270)],
        "zone": rect(-240, 72, -100, 100), "rim": 12,
        "centre": (1060, 380), "top": 10, "depth": 120, "seed": 22,
        "colors": {"grass": [88, 140, 66], "dirt": [112, 86, 58], "stone": [126, 124, 118], "rock": [98, 96, 92]},
    },
    {  # 3 one house alone: the family house, its garden, a few trees
        "id": "lone", "house": "lone_house", "name": "The Lone House", "label": "Samota u cesty", "street": "Hill Road",
        "look": "old", "kind": "house", "box": rect(-40, -16, -15, 15), "yaw": 270, "yard": rect(-6, 50, -64, 64),
        "landmarks": [("garden", "The Garden", "garden", rect(-54, -12, -72, -28), 270)],
        "lines": [([(-68, -10), (-68, 66)], "windbreak")],
        "zone": rect(-84, 60, -80, 80), "rim": 12,
        "centre": (1900, 690), "top": 52, "depth": 110, "seed": 23,
        "colors": {"grass": [102, 146, 64], "dirt": [122, 92, 62], "stone": [140, 134, 124], "rock": [110, 104, 96]},
    },
    {  # 4 in a wood: the forester's lodge in its clearing, the woodpile
        "id": "lodge", "house": "forest_lodge", "name": "The Forest Lodge", "label": "Hájovna v lese", "street": "Wood Lane",
        "look": "lodge", "kind": "lodge", "box": rect(-14, 14, -40, -18), "yaw": 180, "yard": rect(-64, 64, -8, 48),
        "landmarks": [("woodyard", "The Woodpile", "woodyard", rect(-62, -36, -46, -22), 180)],
        "woods": {"id": "forest", "rect": rect(-130, 130, -118, 100), "clearings": [rect(-78, 78, -62, 66)]},
        "zone": rect(-130, 130, -118, 100), "rim": 12,
        "centre": (1950, -770), "top": 74, "depth": 140, "seed": 24,
        "colors": {"grass": [76, 114, 54], "dirt": [104, 80, 56], "stone": [118, 116, 110], "rock": [92, 90, 86]},
    },
    {  # 5 on a stream: the watermill, its millrace past its right-hand side (west) from the spring, the weir, off the
        # island's west edge over the footbridge as a waterfall
        "id": "mill", "house": "old_mill", "name": "The Old Mill", "label": "Starý mlýn na potoce", "street": "Mill Lane",
        "look": "mill", "kind": "mill", "box": rect(-12, 12, -10, 16), "yaw": 0, "yard": rect(-64, 64, -76, -20),
        "landmarks": [
            ("spring", "The Spring", "spring", rect(-34, -2, 66, 96), 0),
            ("weir", "The Weir", "weir", rect(-28, -8, 34, 46), 180),
            ("footbridge", "The Footbridge", "footbridge", rect(-90, -82, -22, 2), 90),
            ("waterfall", "The Waterfall", "waterfall", rect(-132, -112, -18, -2), 90),  # (the island's edge across its middle)
        ],
        "stream": {"id": "millrace", "width": 8, "points": [(-18, 76), (-18, 40), (-18, -10), (-60, -10), (-121.5, -10)]},
        "zone": rect(-110, 110, -86, 102), "rim": 12, "gap": (-16, -4),  # (the rim hedge's gap where the water leaves)
        "centre": (2610, -440), "top": 40, "depth": 120, "seed": 25,
        "colors": {"grass": [92, 136, 62], "dirt": [116, 88, 60], "stone": [130, 128, 122], "rock": [100, 98, 94]},
    },
    {  # 6 in the orchard: the cottage, rows of fruit trees behind their fence, the beehives
        "id": "orchard", "house": "orchard_cottage", "name": "The Orchard Cottage", "label": "Chalupa v sadu", "street": "Orchard Lane",
        "look": "cottage", "kind": "cottage", "box": rect(-20, 0, -13, 13), "yaw": 270, "yard": rect(10, 66, -64, 64),
        "landmarks": [("apiary", "The Beehives", "apiary", rect(-30, 6, 32, 50), 270)],
        "orchard": rect(-180, -36, -90, 90),
        "lines": [([(-34, -10), (-34, -92), (-182, -92), (-182, 92), (-34, 92), (-34, 10)], "fence")],
        "zone": rect(-192, 78, -102, 102), "rim": 12,
        "centre": (2620, 420), "top": 18, "depth": 120, "seed": 26,
        "colors": {"grass": [112, 152, 70], "dirt": [126, 94, 62], "stone": [142, 136, 126], "rock": [112, 106, 98]},
    },
]

# The decorative floating rocks (nothing stands on them): a rock's middle x, z, its top, its width and how far it
# hangs down, its dice (shared/IslandLooks.luau rock).
ROCKS = [
    (836, -836, 40, 26, 34, 1), (1330, -440, 18, 18, 24, 2), (2150, -910, 88, 22, 30, 3), (2780, -290, 54, 20, 26, 4),
    (2416, 604, 30, 24, 30, 5), (2830, 270, 6, 16, 22, 6), (1770, 820, 64, 18, 24, 7), (826, 566, 22, 22, 28, 8),
    (1500, 190, 14, 20, 26, 9), (2110, -230, 26, 16, 22, 10), (1500, -240, -18, 24, 30, 11),
]


# ── The world from the frames ─────────────────────────────────────────────────────────────────────────────────────

def lobby_island():
    """The lobby island: the lobby's bounds and LOBBY_RIM round them, its walls the bounds, its home the spawn."""
    top = grow(LB, LOBBY_RIM)
    cx, cz = mid(top)
    sx, sz = size_of(top)
    s = LOBBY["spawn"]
    i = dict(LOBBY_ISLAND)
    i.update({"x": cx, "z": cz, "sx": sx, "sz": sz, "rect": top, "walls": dict(LB), "home": dict(s)})
    return i


def placed(isl):
    """A map island in the world: its frame's offset (the top's middle at `centre`) and its top's rect."""
    top_local = grow(isl["zone"], isl["rim"])
    lx, lz = mid(top_local)
    dx, dz = isl["centre"][0] - lx, isl["centre"][1] - lz
    return dx, dz, moved(top_local, dx, dz)


def build():
    """Every island, spot, zone, yard, landmark, stream, wood, the orchard, lawn and tree line in the world."""
    islands, spots, zones, roads, landmarks, streams, woods, lawns, lines = [lobby_island()], [], [], [], [], [], [], [], []
    orchard = None
    for isl in ISLANDS:
        dx, dz, top = placed(isl)
        T = isl["top"]
        box, yard = moved(isl["box"], dx, dz), moved(isl["yard"], dx, dz)
        yaw = isl["yaw"]
        mx, mz = mid(box)
        if "farmstead" in isl:
            f = isl["farmstead"]
            lot = moved(f["lot"], dx, dz)
            door = spot(f["door"][0] + dx, f["door"][1] + dz, 0, T)
            curb = spot(f["curb"][0] + dx, f["curb"][1] + dz, 0, T + 0.4)
            back = spot(f["back"][0] + dx, f["back"][1] + dz, 180, T)
            house = {"x": mx, "y": T, "z": mz, "sx": box["x1"] - box["x0"], "sy": 14.5, "sz": box["z1"] - box["z0"]}
        else:
            lot = grow(box, LOT_BACK)
            if yaw == 0:
                door, curb = spot(mx, box["z0"] + DOOR_IN, 0, T), spot(mx, yard["z1"] - CURB_IN, 0, T + 0.4)
                lot["z0"] = yard["z1"]
            elif yaw == 180:
                door, curb = spot(mx, box["z1"] - DOOR_IN, 180, T), spot(mx, yard["z0"] + CURB_IN, 180, T + 0.4)
                lot["z1"] = yard["z0"]
            elif yaw == 90:
                door, curb = spot(box["x0"] + DOOR_IN, mz, 90, T), spot(yard["x1"] - CURB_IN, mz, 90, T + 0.4)
                lot["x0"] = yard["x1"]
            else:
                door, curb = spot(box["x1"] - DOOR_IN, mz, 270, T), spot(yard["x0"] + CURB_IN, mz, 270, T + 0.4)
                lot["x1"] = yard["x0"]
            if isl["house"] == "old_mill":
                lot["x0"] = box["x0"]  # (the mill's lot stops at its wall on the millrace: its west side)
            back = None
            house = {"x": mx, "y": T, "z": mz, "sx": box["x1"] - box["x0"], "sy": WALLS_HIGH, "sz": box["z1"] - box["z0"]}
        s = {"id": isl["house"], "name": isl["name"], "label": isl["label"], "street": isl["street"], "look": isl["look"], "kind": isl["kind"],
             "island": isl["id"], "box": box, "yaw": yaw, "door": door, "curb": curb, "lot": lot, "house": house}
        if back:
            s["back"] = back
        spots.append(s)
        roads.append({"name": isl["street"], "rect": yard, "yard": True})
        ox, oz = LOOK[door["yaw"]]
        zone = moved(isl["zone"], dx, dz)
        arrive = spot(door["x"] + ox * ARRIVE, door["z"] + oz * ARRIVE, (door["yaw"] + 180) % 360, T + 3)
        zones.append({"id": isl["house"], "island": isl["id"], "rect": zone, "arrive": arrive})
        for lid, name, kind, r, lyaw in isl["landmarks"]:
            landmarks.append({"id": lid, "name": name, "kind": kind, "rect": moved(r, dx, dz), "yaw": lyaw, "spot": isl["house"], "island": isl["id"]})
        if "stream" in isl:
            st = isl["stream"]
            streams.append({"id": st["id"], "width": st["width"], "island": isl["id"], "points": [(x + dx, z + dz) for x, z in st["points"]]})
        if "woods" in isl:
            w = isl["woods"]
            wr = moved(w["rect"], dx, dz)
            cl = [moved(c, dx, dz) for c in w["clearings"]]
            woods.append({"id": w["id"], "rect": wr, "clearings": cl})
            c = cl[0]
            for r in (rect(wr["x0"], wr["x1"], wr["z0"], c["z0"]), rect(wr["x0"], wr["x1"], c["z1"], wr["z1"]),
                      rect(wr["x0"], c["x0"], c["z0"], c["z1"]), rect(c["x1"], wr["x1"], c["z0"], c["z1"])):
                lawns.append({"kind": "forest", "rect": r})
        if "orchard" in isl:
            orchard = moved(isl["orchard"], dx, dz)
        for pts, kind in isl.get("lines", []):
            lines.append({"kind": kind, "points": [(x + dx, z + dz) for x, z in pts]})
        # the low hedge on its walls (decoration: the walls stop you), a gap where a stream leaves the island
        q = zone
        if "gap" in isl:
            g0, g1 = isl["gap"][0] + dz, isl["gap"][1] + dz
            pts = [(q["x0"], g0), (q["x0"], q["z0"]), (q["x1"], q["z0"]), (q["x1"], q["z1"]), (q["x0"], q["z1"]), (q["x0"], g1)]
        else:
            pts = [(q["x0"], q["z0"]), (q["x1"], q["z0"]), (q["x1"], q["z1"]), (q["x0"], q["z1"]), (q["x0"], q["z0"])]
        lines.append({"kind": "hedge", "points": pts})
        cx, cz = isl["centre"]
        islands.append({"id": isl["id"], "house": isl["house"], "name": isl["name"], "x": cx, "z": cz, "sx": top["x1"] - top["x0"],
                        "sz": top["z1"] - top["z0"], "rect": top, "top": T, "depth": isl["depth"], "walls": zone, "home": arrive,
                        "look": isl["colors"], "seed": isl["seed"]})
    rocks = [{"x": x, "z": z, "top": t, "size": w, "depth": d, "seed": n} for x, z, t, w, d, n in ROCKS]
    lo = [min(i["rect"]["x0"] for i in islands), min(i["rect"]["z0"] for i in islands)]
    hi = [max(i["rect"]["x1"] for i in islands), max(i["rect"]["z1"] for i in islands)]
    for r in rocks:
        lo = [min(lo[0], r["x"] - r["size"]), min(lo[1], r["z"] - r["size"])]
        hi = [max(hi[0], r["x"] + r["size"]), max(hi[1], r["z"] + r["size"])]
    bounds = rect(math.floor(lo[0] / 20) * 20 - 40, math.ceil(hi[0] / 20) * 20 + 40, math.floor(lo[1] / 20) * 20 - 40, math.ceil(hi[1] / 20) * 20 + 40)
    return {"islands": islands, "spots": spots, "zones": zones, "roads": roads, "landmarks": landmarks, "streams": streams, "woods": woods,
            "orchard": orchard, "lawns": lawns, "lines": lines, "rocks": rocks, "bounds": bounds}


# ── A round's parking (shared/RoundRules.luau parking on the rounds branch, PARK its numbers) ────────────────────────

def axes(yaw):
    a = math.radians(yaw)
    return -math.sin(a), -math.cos(a), math.cos(a), -math.sin(a)  # look x, z; right x, z


def van_rect(x, z, lx, lz, length=PARK["Length"], width=PARK["Width"]):
    hw, hl = width / 2, length / 2
    ex = abs(lx) * hl + abs(lz) * hw
    ez = abs(lz) * hl + abs(lx) * hw
    return rect(x - ex, x + ex, z - ez, z + ez)


def parking(curb, zone, house):
    """The vans' spots at a place: the curb's own first, then beside it, then the rows behind it (the way its nose
    looks), every one inside the walls (PARK Margin off them) and off the house's lot; at most Cols × Rows."""
    lx, lz, rx, rz = axes(curb["yaw"])
    half = PARK["Cols"] // 2
    found = []
    for row in range(PARK["Rows"]):
        for col in range(-half, half + 1):
            x = curb["x"] + rx * col * PARK["Across"] + lx * row * PARK["Along"]
            z = curb["z"] + rz * col * PARK["Across"] + lz * row * PARK["Along"]
            r = van_rect(x, z, lx, lz)
            if not holds(zone, r, PARK["Margin"]) or overlap(r, house, -1e-6):
                continue
            found.append((row * (half + 1) * 2 + abs(col) * 2 + (1 if col < 0 else 0), {"x": x, "z": z, "yaw": curb["yaw"], "rect": r}))
    found.sort(key=lambda f: f[0])
    return [f[1] for f in found]


# ── The checks ────────────────────────────────────────────────────────────────────────────────────────────────────

def stream_rects(stream, extra=0):
    """A stream's water as small squares along its middle line (for the overlap checks)."""
    out = []
    half = stream["width"] / 2 + extra
    pts = stream["points"]
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(bx - ax, bz - az) / 2))
        for i in range(n + 1):
            x, z = ax + (bx - ax) * i / n, az + (bz - az) * i / n
            out.append(rect(x - half, x + half, z - half, z + half))
    return out


def check(w):
    bad = []
    islands = w["islands"]
    lobby = islands[0]
    by_id = {i["id"]: i for i in islands}
    # the islands: apart, the lobby's the biggest, seen from it, their heights, their bottoms, off the mountain
    for n, a in enumerate(islands):
        for b in islands[n + 1:]:
            if gap(a["rect"], b["rect"]) < GAP:
                bad.append(f"islands {a['id']} and {b['id']} only {gap(a['rect'], b['rect']):.0f} apart")
        if a["top"] - a["depth"] <= DESTROY + FALL:
            bad.append(f"island {a['id']}: its bottom under the fall catch's reach")
        r = a["rect"]
        dx = max(r["x0"] - MOUNTAIN["x"], MOUNTAIN["x"] - r["x1"], 0)
        dz = max(r["z0"] - MOUNTAIN["z"], MOUNTAIN["z"] - r["z1"], 0)
        if math.hypot(dx, dz) < MOUNTAIN["r"] + 100:
            bad.append(f"island {a['id']} by the city's mountain")
        if not holds(a["rect"], a["walls"], RIM - 1e-6 if a is not lobby else LOBBY_RIM):
            bad.append(f"island {a['id']}: its walls not {RIM} studs inside its top")
        if not holds(w["bounds"], a["rect"], 0):
            bad.append(f"island {a['id']} outside the Bounds")
    area = lambda i: i["sx"] * i["sz"]
    for i in islands[1:]:
        if area(i) >= area(lobby) or max(i["sx"], i["sz"]) >= max(lobby["sx"], lobby["sz"]) or min(i["sx"], i["sz"]) > min(lobby["sx"], lobby["sz"]):
            bad.append(f"island {i['id']} as big as the lobby's")
        d = math.hypot(i["x"] - lobby["x"], i["z"] - lobby["z"])
        if not VIEW[0] <= d <= VIEW[1]:
            bad.append(f"island {i['id']} {d:.0f} studs from the lobby (not {VIEW[0]} – {VIEW[1]})")
        if not LOW <= i["top"] - lobby["top"] <= HIGH:
            bad.append(f"island {i['id']}: its top {i['top']} not {LOW} – {HIGH} over the lobby's")
    for z in w["zones"]:  # (design/lobby/plan.py's FAR: every other island's walls that far from the lobby's bounds)
        if gap(z["rect"], LB) < LOBBY["far"]:
            bad.append(f"the walls of {z['id']} within {LOBBY['far']} of the lobby")
    tops = [i["top"] for i in islands[1:]]
    if len(set(tops)) < len(tops) or max(tops) - min(tops) < SPREAD:
        bad.append("the map islands' tops not at varying heights")
    # the rocks: off every island and each other
    for n, r in enumerate(w["rocks"]):
        box = rect(r["x"] - r["size"], r["x"] + r["size"], r["z"] - r["size"], r["z"] + r["size"])
        for i in islands:
            if gap(box, i["rect"]) < 30:
                bad.append(f"rock {n + 1} by island {i['id']}")
        for m, s in enumerate(w["rocks"][n + 1:]):
            if math.hypot(r["x"] - s["x"], r["z"] - s["z"]) < r["size"] + s["size"] + 20:
                bad.append(f"rocks {n + 1} and {n + m + 2} on each other")
        if r["top"] - r["depth"] <= DESTROY + FALL:
            bad.append(f"rock {n + 1} too low")
    # every place on its island: its things inside its walls, nothing on anything else
    for s in w["spots"]:
        isl = by_id[s["island"]]
        zone = next(z for z in w["zones"] if z["id"] == s["id"])
        q = zone["rect"]
        yard = next(r["rect"] for r in w["roads"] if r["name"] == s["street"])
        marks = [l for l in w["landmarks"] if l["spot"] == s["id"]]
        things = [("box", s["box"]), ("lot", s["lot"]), ("yard", grow(yard, SHOULDER))]
        things += [(f"landmark {l['id']}", l["rect"]) for l in marks if l["kind"] != "waterfall"]
        a = zone["arrive"]
        things.append(("arrive", rect(a["x"] - 4, a["x"] + 4, a["z"] - 4, a["z"] + 4)))
        for st in w["streams"]:
            if st["island"] == isl["id"]:  # (its points but its last: that one at the island's edge, where it falls off)
                things += [(f"stream {st['id']}", rect(x - st["width"] / 2, x + st["width"] / 2, z - st["width"] / 2, z + st["width"] / 2))
                           for x, z in st["points"][:-1]]
        for wd in w["woods"]:
            if holds(isl["rect"], wd["rect"]):
                things.append(("woods", wd["rect"]))
        if w["orchard"] and holds(isl["rect"], w["orchard"]):
            things.append(("orchard", w["orchard"]))
        for name, t in things:
            if not holds(q, t, MARGIN if name != "woods" else 0):
                bad.append(f"{s['id']}: its {name} not inside its walls")
        # the curb: the van on its yard's asphalt, its back nearer the door
        c, d = s["curb"], s["door"]
        lx, lz = LOOK[c["yaw"]]
        hl, hw = VAN_LENGTH / 2, VAN_WIDTH / 2
        back, nose = (c["x"] - lx * hl, c["z"] - lz * hl), (c["x"] + lx * hl, c["z"] + lz * hl)
        px, pz = -lz * hw, lx * hw
        for p in (back, nose, (back[0] + px, back[1] + pz), (back[0] - px, back[1] - pz), (nose[0] + px, nose[1] + pz), (nose[0] - px, nose[1] - pz)):
            if not (yard["x0"] - 1e-6 <= p[0] <= yard["x1"] + 1e-6 and yard["z0"] - 1e-6 <= p[1] <= yard["z1"] + 1e-6):
                bad.append(f"{s['id']}: the van off its yard")
                break
        if math.hypot(back[0] - d["x"], back[1] - d["z"]) >= math.hypot(nose[0] - d["x"], nose[1] - d["z"]):
            bad.append(f"{s['id']}: the van's nose to the door")
        # nothing on anything else (the countryside's rules: a lot on its own yard and its box, the mill on its race)
        areas = [("road", grow(yard, SHOULDER)), ("spot", s["box"]), ("lot", s["lot"])]
        areas += [(f"landmark {l['id']}", l["rect"]) for l in marks]
        for st in w["streams"]:
            if st["island"] == isl["id"]:
                areas += [(f"stream", r) for r in stream_rects(st)]
        ok_pairs = {("road", "lot"), ("lot", "road"), ("spot", "lot"), ("lot", "spot"), ("stream", "stream"), ("spot", "stream"), ("stream", "spot")}
        crossing = {"landmark weir", "landmark footbridge", "landmark spring", "landmark waterfall", "landmark pond"}
        seen = set()
        for n, (na, ra) in enumerate(areas):
            for nb, rb in areas[n + 1:]:
                if (na, nb) in ok_pairs or na == nb or ({na, nb} & crossing and "stream" in (na, nb)):
                    continue
                if overlap(ra, rb, -1e-6) and (na, nb) not in seen:
                    seen.add((na, nb))
                    bad.append(f"{s['id']}: {na} on {nb}")
        # a round's vans: VANS clear spots at least, that many on the yard's asphalt
        spots = parking(c, q, s["lot"])
        solid = [l["rect"] for l in marks if l["kind"] not in ("waterfall",)] + [s["box"]]
        for wd in w["woods"]:
            if holds(isl["rect"], wd["rect"]):
                solid.append(("woods", wd))
        if w["orchard"] and holds(isl["rect"], w["orchard"]):
            solid.append(grow(w["orchard"], 2))
        water = [r for st in w["streams"] if st["island"] == isl["id"] for r in stream_rects(st, 1.5)]

        def clear(v):
            for o in solid:
                if isinstance(o, tuple):
                    wd = o[1]
                    if overlap(v["rect"], wd["rect"], -1e-6) and not any(holds(c2, v["rect"]) for c2 in wd["clearings"]):
                        return False
                elif overlap(v["rect"], o, -1e-6):
                    return False
            return not any(overlap(v["rect"], r, -1e-6) for r in water)
        free = [v for v in spots if clear(v)]
        paved = [v for v in free if holds(yard, v["rect"])]
        s["vans"] = len(free)
        s["paved"] = len(paved)
        if len(free) < VANS or len(paved) < VANS:
            bad.append(f"{s['id']}: room for {len(free)} vans ({len(paved)} on its yard), not {VANS}")
    # the mill's millrace past its right-hand side (seen facing its door from outside: west) and off the island's edge
    mill = next(s for s in w["spots"] if s["id"] == "old_mill")
    st = next(x for x in w["streams"] if x["id"] == "millrace")
    b = mill["box"]
    near = min(abs(x - b["x0"]) for x, z in st["points"] if b["z0"] - 30 <= z <= b["z1"] + 30)
    if near > st["width"] / 2 + 2.5:
        bad.append("the millrace is not past the mill's right-hand side")
    isl = by_id[mill["island"]]
    ex, ez = st["points"][-1]
    if abs(ex - isl["rect"]["x0"]) > 1:
        bad.append("the millrace does not run off its island's edge")
    fall = next(l for l in w["landmarks"] if l["kind"] == "waterfall")
    if not (fall["rect"]["x0"] < isl["rect"]["x0"] < fall["rect"]["x1"] and fall["rect"]["z0"] < ez < fall["rect"]["z1"]):
        bad.append("the waterfall not where the millrace leaves the island")
    return bad


# ── The picture ───────────────────────────────────────────────────────────────────────────────────────────────────

S = 0.62  # px per stud (the top view)
PANEL = 560
TOP = 120
SIDE = 300  # the side view's height (px)
COL = {
    "sky": (150, 196, 232), "sky2": (196, 222, 242), "edge": (122, 92, 62), "label": (32, 32, 36), "white": (250, 250, 250),
    "text2": (205, 205, 210), "accent": (240, 130, 40), "asphalt": (60, 60, 64), "box": (176, 78, 56), "big": (132, 54, 40), "lot": (128, 168, 86),
    "water": (76, 140, 190), "tree": (48, 100, 46), "fruit": (88, 140, 66), "hedge": (44, 80, 38), "fence": (150, 112, 74), "van": (250, 250, 250),
    "plaza": (196, 188, 172), "plot": (200, 197, 190), "warehouse": (150, 160, 172), "play": (90, 210, 255), "rock": (128, 120, 112), "mark": (150, 110, 80),
}


def font(size, bold=False):
    for path in (f"/usr/share/fonts/opentype/inter/Inter-{'Bold' if bold else 'Medium'}.otf",
                 f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def picture(w, path):
    B = w["bounds"]
    vw, vh = int((B["x1"] - B["x0"]) * S), int((B["z1"] - B["z0"]) * S)
    W, H = vw + PANEL + 60, TOP + vh + 40 + SIDE + 40
    img = Image.new("RGB", (W, H), (28, 30, 34))
    draw = ImageDraw.Draw(img)

    def P(x, z):
        return ((x - B["x0"]) * S + 30, (z - B["z0"]) * S + TOP)

    def R(r, grow_px=0):
        a, b = P(r["x0"], r["z0"]), P(r["x1"], r["z1"])
        return [a[0] - grow_px, a[1] - grow_px, b[0] + grow_px, b[1] + grow_px]

    # the sky (a soft gradient) under the top view
    x0, y0, x1, y1 = R(B)
    for k in range(int(y1 - y0)):
        t = k / max(1, y1 - y0)
        c = tuple(int(COL["sky"][j] * (1 - t) + COL["sky2"][j] * t) for j in range(3))
        draw.line([x0, y0 + k, x1, y0 + k], fill=c)
    # the rocks
    for r in w["rocks"]:
        cx, cz = P(r["x"], r["z"])
        rr = r["size"] / 2 * S
        draw.polygon([(cx - rr, cz - rr * 0.6), (cx + rr * 0.8, cz - rr), (cx + rr, cz + rr * 0.5), (cx - rr * 0.4, cz + rr)], fill=COL["rock"], outline=(90, 84, 78))
    # the islands: the dirt edge, the grass, the walls' hedge
    for i in w["islands"]:
        draw.rectangle(R(i["rect"], 3), fill=tuple(i["look"]["dirt"]))
        draw.rectangle(R(i["rect"]), fill=tuple(i["look"]["grass"]))
    for i in w["islands"][1:]:
        draw.rectangle(R(i["walls"]), outline=COL["hedge"], width=3)
    # the lobby's own things (design/lobby/plan.json)
    draw.rectangle(R(LOBBY["plaza"]), fill=COL["plaza"])
    for q in LOBBY["plots"]:
        draw.rectangle(R(q["rect"]), fill=COL["plot"])
        draw.rectangle(R(rect(q["x"] - 40, q["x"] + 40, q["wall"] - 60, q["wall"])), fill=COL["warehouse"])
    p = LOBBY["play"]
    cx, cz = P(p["x"], p["z"])
    rr = p["r"] * S
    draw.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=COL["play"])
    draw.rectangle(R(LB), outline=COL["hedge"], width=3)
    # the places: lawns, woods, orchard, streams, landmarks, yards, lots, boxes, vans
    for l in w["lawns"]:
        draw.rectangle(R(l["rect"]), fill=(70, 104, 52))
    for wd in w["woods"]:
        r = wd["rect"]
        n = 0
        for x in range(int(r["x0"]) + 14, int(r["x1"]) - 6, 26):
            for z in range(int(r["z0"]) + 14, int(r["z1"]) - 6, 26):
                n += 1
                if any(c["x0"] - 4 <= x <= c["x1"] + 4 and c["z0"] - 4 <= z <= c["z1"] + 4 for c in wd["clearings"]):
                    continue
                tx, tz = P(x + (n * 37 % 9) - 4, z + (n * 53 % 9) - 4)
                draw.ellipse([tx - 6, tz - 6, tx + 6, tz + 6], fill=COL["tree"])
    o = w["orchard"]
    if o:
        for x in range(int(o["x0"]) + 18, int(o["x1"]) - 10, 36):
            for z in range(int(o["z0"]) + 16, int(o["z1"]) - 10, 32):
                tx, tz = P(x, z)
                draw.ellipse([tx - 4, tz - 4, tx + 4, tz + 4], fill=COL["fruit"])
    for line in w["lines"]:
        if line["kind"] == "fence":
            draw.line([P(x, z) for x, z in line["points"]], fill=COL["fence"], width=2)
        elif line["kind"] == "windbreak":
            for x, z in line["points"]:
                tx, tz = P(x, z)
                draw.ellipse([tx - 6, tz - 6, tx + 6, tz + 6], fill=COL["tree"])
    for st in w["streams"]:
        draw.line([P(x, z) for x, z in st["points"]], fill=COL["water"], width=max(3, int(st["width"] * S)))
    for l in w["landmarks"]:
        r = l["rect"]
        if l["kind"] == "fishpond":
            draw.ellipse(R(r), fill=COL["water"], outline=(92, 120, 62), width=2)
        elif l["kind"] == "paddock":
            draw.rectangle(R(r), outline=COL["fence"], width=2)
        elif l["kind"] == "spring":
            draw.ellipse(R(r), fill=COL["water"], outline=(150, 148, 142), width=2)
        elif l["kind"] == "waterfall":
            a = P(r["x0"], (r["z0"] + r["z1"]) / 2)
            draw.polygon([(a[0], a[1] - 5), (a[0] - 10, a[1]), (a[0], a[1] + 5)], fill=COL["water"])
        else:
            draw.rectangle(R(r), fill=COL["mark"], outline=(70, 50, 34))
    for road in w["roads"]:
        draw.rectangle(R(road["rect"]), fill=COL["asphalt"])
    for s in w["spots"]:
        draw.rectangle(R(s["lot"]), fill=COL["lot"])
    for n, s in enumerate(w["spots"]):
        draw.rectangle(R(s["box"]), fill=COL["big"] if n == 0 else COL["box"], outline=(60, 30, 24))
        zone = next(z for z in w["zones"] if z["id"] == s["id"])
        for v in parking(s["curb"], zone["rect"], s["lot"])[:VANS]:
            draw.rectangle(R(v["rect"]), outline=COL["van"], width=1)
        a = zone["arrive"]
        ax, az = P(a["x"], a["z"])
        draw.ellipse([ax - 3, az - 3, ax + 3, az + 3], fill=(120, 220, 255))

    def tag(x, y, text, sub=None, anchor=(0, 0)):
        f, fs = font(16, True), font(13)
        tw = max(draw.textlength(text, font=f), draw.textlength(sub, font=fs) if sub else 0)
        hh = 24 + (18 if sub else 0)
        x -= anchor[0] * (tw + 14)
        y -= anchor[1] * hh
        draw.rounded_rectangle([x, y, x + tw + 14, y + hh], 5, fill=COL["label"])
        draw.text((x + 7, y + 3), text, font=f, fill=COL["white"])
        if sub:
            draw.text((x + 7, y + 23), sub, font=fs, fill=COL["text2"])
    for n, i in enumerate(w["islands"]):
        r = i["rect"]
        x, y = P((r["x0"] + r["x1"]) / 2, r["z0"])
        sub = f"top {i['top']:+d} · {i['sx']:.0f} × {i['sz']:.0f}"
        if i.get("house"):
            s = next(q for q in w["spots"] if q["id"] == i["house"])
            sub += f" · {s['vans']} vans"
        tag(x, y - 6, f"{n}. {i['name']}" if n else i["name"].upper(), sub, (0.5, 1))
    # the side view: every island from the side at its height, one beside the other (its width and its height to the
    # same scale), the lobby's ground and the clouds under them
    sy0 = TOP + vh + 40
    draw.rectangle([30, sy0, 30 + vw, sy0 + SIDE], fill=COL["sky2"])
    ytop, ybot = 150, -250
    room = vw - 60
    total = sum(i["sx"] for i in w["islands"])
    k = min((SIDE - 60) / (ytop - ybot), (room - 16 * (len(w["islands"]) - 1)) / total)  # px per stud, up and across

    def SY(y):
        return sy0 + 30 + (ytop - y) * k
    lines = ((0, "", (200, 160, 60)), (-230, "the soft clouds below", (250, 252, 255)))  # (y 0's words in the heading)
    for y, text, colour in lines:
        draw.line([30, SY(y), 30 + vw, SY(y)], fill=colour, width=2)
    gapx = (room - total * k) / (len(w["islands"]) - 1)
    a = 50
    for n, i in enumerate(w["islands"]):
        b = a + i["sx"] * k
        t, d = i["top"], i["depth"]
        draw.rectangle([a, SY(t), b, SY(t - 2)], fill=tuple(i["look"]["grass"]))
        draw.rectangle([a + 1, SY(t - 2), b - 1, SY(t - 8)], fill=tuple(i["look"]["dirt"]))
        draw.rectangle([a + 3, SY(t - 8), b - 3, SY(t - 22)], fill=tuple(i["look"]["stone"]))
        draw.polygon([(a + 5, SY(t - 22)), (b - 5, SY(t - 22)), ((a + b) / 2 + (b - a) * 0.06, SY(t - d))], fill=tuple(i["look"]["rock"]))
        up = 30 if n % 2 == 1 else 0  # (staggered: a narrow island's words clear of its neighbours')
        draw.text(((a + b) / 2, SY(t) - 26 - up), i["name"], font=font(13, True), fill=(30, 30, 34), anchor="mm")
        draw.text(((a + b) / 2, SY(t) - 11 - up), f"top {t:+d}, bottom {t - d:+d}", font=font(12), fill=(60, 60, 64), anchor="mm")
        a = b + gapx
    for y, text, colour in [line for line in lines if line[1]]:  # (their words over the islands, on a strip of sky)
        box = draw.textbbox((24 + vw, SY(y) + 3), text, font=font(13, True), anchor="ra")
        draw.rectangle([box[0] - 4, box[1] - 2, box[2] + 2, box[3] + 2], fill=COL["sky2"])
        draw.text((24 + vw, SY(y) + 3), text, font=font(13, True), fill=(60, 60, 64), anchor="ra")
    draw.text((36, sy0 + 6), f"FROM THE SIDE (to scale, {1 / k:.1f} studs a px; the gold line y 0): fall off an island, back on its top; "
              f"workspace.FallenPartsDestroyHeight {DESTROY}", font=font(13, True), fill=(40, 40, 44))
    # the title and the legend
    draw.rectangle([0, 0, W, TOP - 14], fill=(22, 24, 28))
    draw.text((24, 14), "DELIVEROS · THE FLOATING ISLANDS (10.6)", font=font(38, True), fill=COL["white"])
    draw.text((24, 64), "Seen from above, north up, and from the side. The lobby the biggest island, the six places each on an island of its own, "
              "at their own heights; a fade takes you across.", font=font(18), fill=COL["text2"])
    lx = vw + 80
    y = TOP + 6
    draw.text((lx, y), "THE ISLANDS", font=font(24, True), fill=COL["white"])
    y += 40
    lobby = w["islands"][0]
    for n, i in enumerate(w["islands"]):
        d = math.hypot(i["x"] - lobby["x"], i["z"] - lobby["z"])
        draw.text((lx, y), f"{n}. {i['name']}" if n else i["name"], font=font(18, True), fill=COL["white"])
        sub = f"{i['sx']:.0f} × {i['sz']:.0f} studs, top {i['top']:+d}, {i['depth']} deep"
        if n:
            s = next(q for q in w["spots"] if q["id"] == i["house"])
            sub += f", {d:.0f} from the lobby, {s['vans']} vans"
        draw.text((lx, y + 24), sub, font=font(14), fill=COL["text2"])
        y += 56
    y += 10
    draw.text((lx, y), "LEGEND", font=font(24, True), fill=COL["white"])
    y += 38
    for colour, text in ((COL["asphalt"], "a place's yard: the round's van parking"), (COL["van"], "the first 16 vans of a round"),
                         (COL["lot"], "a place's lot (its garden)"), (COL["hedge"], "the low hedge and the walls on an island's rim"),
                         ((120, 220, 255), "where a run's party arrives, facing the door"), (COL["water"], "the pond, the spring, the millrace"),
                         (COL["rock"], "the floating rocks (decoration)")):
        draw.rectangle([lx, y + 3, lx + 24, y + 21], fill=colour, outline=(20, 20, 20))
        draw.text((lx + 36, y + 2), text, font=font(16), fill=COL["white"])
        y += 28
    y += 10
    for text in (f"Islands {GAP}+ studs apart (no jump across); every map", f"island {VIEW[0]} – {VIEW[1]} studs from the lobby (in view).",
                 "Fall off an island: back on its top by a fade.", "Drawn from plan.json (design/islands/plan.py)."):
        draw.text((lx, y), text, font=font(15), fill=COL["text2"])
        y += 22
    bx, by = 40, TOP + vh - 30
    draw.line([bx, by, bx + 100 * S, by], fill=COL["white"], width=4)
    draw.text((bx + 100 * S + 8, by - 9), "100 studs", font=font(14), fill=COL["white"])
    img.save(path, optimize=True)


def main():
    w = build()
    bad = check(w)
    print("islands plan check: " + ("all fine" if not bad else "BAD\n  " + "\n  ".join(bad)))
    plan = {
        "about": "The floating islands (design/islands/plan.py): the sandbox's world. Studs; x east, z south, y up; yaw as SandboxMap "
                 "(0 north, 90 west, 180 south, 270 east). The lobby's own layout: design/lobby/plan.json.",
        "destroy": DESTROY,
        "vans": VANS,
        "park": PARK,
        "islands": w["islands"],
        "rocks": w["rocks"],
        "bounds": w["bounds"],
        "roads": w["roads"],
        "spots": [{k: v for k, v in s.items()} for s in w["spots"]],
        "zones": w["zones"],
        "landmarks": w["landmarks"],
        "streams": [{"id": s["id"], "width": s["width"], "island": s["island"], "points": [{"x": x, "z": z} for x, z in s["points"]]} for s in w["streams"]],
        "woods": w["woods"],
        "orchard": w["orchard"],
        "fields": [],
        "lawns": w["lawns"],
        "treeLines": [{"kind": l["kind"], "points": [{"x": x, "z": z} for x, z in l["points"]]} for l in w["lines"]],
    }
    with open(os.path.join(HERE, "plan.json"), "w", encoding="utf-8") as out:
        json.dump(plan, out, ensure_ascii=False, indent=1)
    picture(w, os.path.join(HERE, "plan.png"))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
