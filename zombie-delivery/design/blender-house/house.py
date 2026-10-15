"""Zombie Delivery: klasický evropský rodinný dům v Blenderu, místo domu, ze kterého se stěhuje.

Spuštění v Blenderu: záložka Scripting → Open → house.py → Run Script (▶, nebo Alt+P). Skript postaví dům do kolekce
"House": omítnuté zdi s rohovými kvádry a soklem, bílé šambrány, parapety a okna s křížem, truhlíky s muškáty,
dvoukřídlé zelené dveře, sedlovou střechu z pálených tašek s vikýři, komíny, okapy a svody.

TARGET vybírá, který dům ve hře nahradí: "sandbox" = The Old Farmstead v testovacím světě (44 × 14,5 × 34, střecha do
výšky 26), "city" = dům Marge ve městě (155 Willow Ln). Rozměry jsou přesně ty, které má dům ve hře (krabice HOUSE:
šířka W, výška zdí H, hloubka D; 1 jednotka = 1 stud). Předek domu míří na -Y, střed spodku domu je v počátku. Ve
městě hra na zeď s dveřmi věší transparent MOVING DAY a staví krabice a srolovaný koberec, proto tam nejsou truhlíky
v přízemí; v sandboxu stojí před dveřmi vítající postava a zahradní truhlíky.

Bez Blenderu, jen s modulem bpy (pip install bpy):
    python house.py -- --save house.blend --render složka --export složka
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

# ───────────────────────────────────────────────────────────── NASTAVENÍ
EXPORT = False   # True = uloží ZDCHouseArt.fbx pro hru do složky "roblox" vedle .blend souboru

TARGET = "sandbox"   # "sandbox" = The Old Farmstead v sandboxu, "city" = dům Marge ve městě

# Dům pro každý cíl: krabice ve hře (W, H, D), sklon střechy (None: co nejstrmější pod výškou "top"), přesah střechy
# vpředu a vzadu, okna (polohy podél zdí), vikýře, komíny (x, y na zadním svahu), keře u vchodu.
# tools/house-art/check.py hlídá, že krabice sedí se hrou (SandboxMap.House / Map.Homes).
TARGETS = {
    "sandbox": {  # shared/SandboxMap.luau House.house (44 × 14,5 × 34), střecha pod 26; sklon = SandboxScenery.Chalet.Pitch
        "box": (44.0, 14.5, 34.0), "pitch": None, "top": 26.0, "eave": 1.2,
        "front": [-19.0, -13.0, -7.0, 7.0, 13.0, 19.0], "front_flowers": True, "upper": 9.4, "small": 10.2,
        "back": [-19.0, -13.0, -7.0, 7.0, 13.0, 19.0], "back_upper": [-19.0, -13.0, -7.0, 0.0, 7.0, 13.0, 19.0],
        "side": [-12.0, -5.0, 5.0, 12.0], "attic": [-3.5, 3.5], "dormers": [-13.0, 0.0, 13.0],
        "chimneys": [(-15.0, 6.0), (12.0, 6.0)], "bushes": [-20.4, 20.4], "lantern": 3.1,
    },
    "city": {  # shared/Map.luau: dům home_suburbs_2_0_00
        "box": (20.3572, 12.5980, 17.5669), "pitch": 42, "top": None, "eave": 1.0,
        "front": [-6.4, 6.4], "front_flowers": False, "upper": 8.6, "small": 9.9,
        "back": [-6.4, 6.4], "back_upper": [-6.4, 0.0, 6.4],
        "side": [-4.2, 4.2], "attic": [0.0], "dormers": [0.0],
        "chimneys": [(4.6, 1.4)], "bushes": [-8.6, 8.6], "lantern": 3.1,
    },
}
LAYOUT = TARGETS[TARGET]
W, H, D = LAYOUT["box"]
EAVE = LAYOUT["eave"]   # přesah střechy vpředu a vzadu
VERGE = 0.8             # přesah střechy na štítech


def steepest(top):
    """The steepest pitch whose ridge tile stays under `top`."""
    for tenth in range(600, 50, -1):
        a = math.radians(tenth / 10)
        ridge = H - 0.25 + (D / 2 + EAVE) * math.tan(a) + 0.25 / math.cos(a) + 0.44
        if ridge <= top - 0.05:
            return tenth / 10
    return 10.0


PITCH = LAYOUT["pitch"] or steepest(LAYOUT["top"])   # sklon střechy (stupně)

# Povrchy: jméno → (barva #RRGGBB, drsnost, kov, záře). Hra (server/HouseMesh.luau) dá každému povrchu barvu
# a materiál Robloxu.
FINISHES = {
    "plaster": ("#E8D3A2", 0.85, 0, 0), "trim": ("#F3F0E8", 0.6, 0, 0), "stone": ("#8D8A84", 0.9, 0, 0),
    "stone2": ("#E3DCCB", 0.85, 0, 0), "tile": ("#B5502E", 0.7, 0, 0), "tile2": ("#A44629", 0.7, 0, 0),
    "tile3": ("#8C3A22", 0.7, 0, 0), "soffit": ("#7A5A3E", 0.7, 0, 0), "door": ("#2F5E45", 0.5, 0, 0),
    "brass": ("#C9A44C", 0.3, 1, 0), "glass": ("#2E3C48", 0.05, 0, 0), "zinc": ("#9BA2A6", 0.35, 1, 0),
    "black": ("#1C1C1E", 0.5, 0, 0), "glow": ("#FFE2A8", 0.5, 0, 3.0), "wood2": ("#6B4A2F", 0.7, 0, 0),
    "red": ("#D1372F", 0.6, 0, 0), "leaf": ("#3E7A38", 0.7, 0, 0), "shrub": ("#4F7F3B", 0.8, 0, 0),
    "curtain": ("#EEE7D8", 0.9, 0, 0),
}

M = {}
COL = None       # the collection being built into
CUT = None       # the hidden cutters the walls' Booleans take out (window and door openings)

T = math.tan(math.radians(PITCH))
C = math.cos(math.radians(PITCH))
S = math.sin(math.radians(PITCH))
SLAB = 0.25                 # the roof's boards
Y_E = D / 2 + EAVE          # the eaves, out from the middle
Z_EB = H - 0.25             # the boards' underside at the eaves
Z_RB = Z_EB + Y_E * T       # ... at the ridge
Z_RT = Z_RB + SLAB / C      # the boards' top at the ridge
KNEE = 0.9                  # the walls go this far over H, into the roof's boards
ROOF_L = Y_E / C            # eaves to ridge, along the slope


def linear(hexcode):
    h = hexcode.lstrip("#")
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))


def materials():
    for name, (hexcode, rough, metal, emit) in FINISHES.items():
        m = bpy.data.materials.get("H " + name) or bpy.data.materials.new("H " + name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        rgba = (*linear(hexcode), 1.0)
        m.diffuse_color = rgba
        p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        p.inputs["Base Color"].default_value = rgba
        p.inputs["Roughness"].default_value = rough
        p.inputs["Metallic"].default_value = metal
        glow = p.inputs.get("Emission Color") or p.inputs.get("Emission")
        glow.default_value = rgba if emit else (0, 0, 0, 1)
        p.inputs["Emission Strength"].default_value = emit
        m["finish"] = name
        M[name] = m


# ───────────────────────────────────────────────────────────── stavební kameny (souřadnice od středu spodku domu)
def obj(name, bm, finish, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M[finish])
    for p in me.polygons:
        p.use_smooth = smooth
    o = bpy.data.objects.new(name, me)
    COL.objects.link(o)
    return o


def euler(rx=0.0, ry=0.0, rz=0.0):
    from mathutils import Euler
    return Euler((rx, ry, rz)).to_matrix().to_4x4()


def bevel(o, width, segments=2, angle=40):
    if width <= 0:
        return o
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width, b.segments, b.limit_method, b.angle_limit = width, segments, "ANGLE", math.radians(angle)
    b.harden_normals, b.use_clamp_overlap = True, True
    return o


def sharpen(bm, degrees=40):
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(degrees):
            e.smooth = False


def box(name, size, at, finish, r=0.03, rot=None, seg=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation(Vector(at)) @ (rot or Matrix())
    if r < 0.02 and W > 30:
        return o  # (a big house's window frames and bars: sharp, a quarter of the triangles)
    return bevel(o, min(r, min(size) * 0.45), seg or (1 if r <= 0.03 else 2))  # (small edges: one bevel segment)


def cyl(name, r, h, at, finish, axis="Z", seg=16, r2=None, edge=0.0, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    sharpen(bm)
    o = obj(name, bm, finish)
    turn = {"Z": Matrix(), "X": euler(ry=math.pi / 2), "Y": euler(rx=math.pi / 2)}[axis]
    o.matrix_world = Matrix.Translation(Vector(at)) @ (rot or Matrix()) @ turn
    return bevel(o, edge, 2)


def tube(name, a, b, r, finish, seg=10):
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=(b - a).length)
    sharpen(bm)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat("Z", "Y").to_matrix().to_4x4()
    return o


def ball(name, r, at, finish, scale=(1, 1, 1), seg=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation(Vector(at))
    return o


def cutter(name, size, at):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    CUT.objects.link(o)
    o.location = at
    o.display_type, o.hide_render = "WIRE", True
    return o


def openings(o):
    b = o.modifiers.new("Okna a dveře", "BOOLEAN")
    b.operation, b.operand_type, b.collection, b.solver = "DIFFERENCE", "COLLECTION", CUT, "EXACT"
    return o


# ───────────────────────────────────────────────────────────── zdi: souřadnice na zdi
# A wall's frame: u along it (to the right, seen from outside), v up, w out of it. Front: the street side (-Y).
WALLS = {
    "front": (lambda u, v, w: Vector((u, -D / 2 - w, v)), "y"),
    "back": (lambda u, v, w: Vector((-u, D / 2 + w, v)), "y"),
    "right": (lambda u, v, w: Vector((W / 2 + w, u, v)), "x"),   # (+X, seen from the front: the right-hand gable)
    "left": (lambda u, v, w: Vector((-W / 2 - w, -u, v)), "x"),
}


def wbox(wall, name, su, sv, w0, w1, u, v, finish, r=0.03):
    """A block on a wall: su along it, sv tall, from w0 to w1 out of it, centred at (u, v)."""
    at, normal = WALLS[wall]
    sw = w1 - w0
    size = (su, sw, sv) if normal == "y" else (sw, su, sv)
    return box(name, size, at(u, v, (w0 + w1) / 2), finish, r=r)


def wcut(wall, name, su, sv, u, v):
    at, normal = WALLS[wall]
    size = (su, 0.65, sv) if normal == "y" else (0.65, su, sv)
    return cutter(name, size, at(u, v, -0.35 + 0.65 / 2))


def window(wall, u, vb, ow, oh, keystone=False, flowers=False, tag="Okno"):
    """An opening ow × oh from height vb: its pocket in the wall, a white frame with a cross, the glass, the white
    surround (šambrána), a stone sill, a keystone, a planter of geraniums under it."""
    vt = vb + oh
    wcut(wall, f"{tag} řez", ow, oh, u, vb + oh / 2)
    tf = 0.16
    for side in (-1, 1):
        wbox(wall, f"{tag} rám", tf, oh, -0.34, -0.2, u + side * (ow / 2 - tf / 2), vb + oh / 2, "trim", r=0.01)
    for v in (vb + tf / 2, vt - tf / 2):
        wbox(wall, f"{tag} rám", ow - 2 * tf, tf, -0.34, -0.2, u, v, "trim", r=0.01)
    wbox(wall, f"{tag} sklo", ow - 2 * tf + 0.02, oh - 2 * tf + 0.02, -0.34, -0.32, u, vb + oh / 2, "glass", r=0)
    inner = ow - 2 * tf
    for side in (-1, 1):  # (net curtains, drawn to the sides)
        wbox(wall, f"{tag} záclona", inner * 0.2, oh - 2 * tf, -0.32, -0.315, u + side * (inner / 2 - inner * 0.1), vb + oh / 2, "curtain", r=0)
    wbox(wall, f"{tag} příčka", 0.1, oh - 2 * tf, -0.31, -0.21, u, vb + oh / 2, "trim", r=0.01)
    wbox(wall, f"{tag} příčka", ow - 2 * tf, 0.1, -0.31, -0.21, u, vb + oh * 0.64, "trim", r=0.01)
    # The surround on the wall's face, the sill under it.
    sw = 0.24
    for side in (-1, 1):
        wbox(wall, f"{tag} šambrána", sw, oh + 0.3, -0.04, 0.05, u + side * (ow / 2 + sw / 2 - 0.02), vb + (oh + 0.3) / 2, "trim", r=0.015)
    wbox(wall, f"{tag} šambrána", ow + 2 * sw - 0.04, 0.3, -0.04, 0.05, u, vt + 0.13, "trim", r=0.015)
    if keystone:
        wbox(wall, f"{tag} klenák", 0.42, 0.5, -0.04, 0.1, u, vt + 0.2, "stone2", r=0.02)
    wbox(wall, f"{tag} parapet", ow + 0.5, 0.14, -0.08, 0.32, u, vb - 0.07, "stone", r=0.02)
    if flowers:
        wbox(wall, f"{tag} truhlík", ow + 0.1, 0.42, 0.05, 0.55, u, vb - 0.42, "wood2", r=0.03)
        at, _ = WALLS[wall]
        n = 7
        for k in range(n):
            du = (k - (n - 1) / 2) * (ow / n)
            seg = 6 if W > 30 else 8
            ball(f"{tag} listí", 0.21, at(u + du, vb - 0.13, 0.3 + (0.06 if k % 2 else -0.04)), "leaf", scale=(1.1, 1.0, 0.8), seg=seg)
            ball(f"{tag} muškát", 0.14, at(u + du + 0.12, vb + 0.02 + (0.05 if k % 2 else 0), 0.34), "red", seg=seg)


# ───────────────────────────────────────────────────────────── dům
def walls():
    # The body (its top KNEE into the roof's boards) and the plinth, the openings cut out of both.
    openings(box("Zdi", (W, D, H + KNEE), (0, 0, (H + KNEE) / 2), "plaster", r=0))
    openings(box("Sokl", (W + 0.12, D + 0.12, 1.0), (0, 0, 0.5), "stone", r=0.02))
    # The gables over the side walls, the roof's underside over them.
    yb = Y_E - (H + KNEE - (Z_EB - 0.02)) / T
    apex = Z_RB - 0.02
    bm = bmesh.new()
    pts = []
    for x in (-W / 2, W / 2):
        pts.append([bm.verts.new((x, -yb, H + KNEE)), bm.verts.new((x, yb, H + KNEE)), bm.verts.new((x, 0, apex))])
    (a0, a1, a2), (b0, b1, b2) = pts
    bm.faces.new((a0, a2, a1))
    bm.faces.new((b0, b1, b2))
    bm.faces.new((a0, a1, b1, b0))
    bm.faces.new((a1, a2, b2, b1))
    bm.faces.new((a2, a0, b0, b2))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    openings(obj("Štíty", bm, "plaster", smooth=False))
    # The bands: between the floors, under the eaves (front and back) and across the gables.
    for wall, length in (("front", W), ("back", W), ("right", D), ("left", D)):
        wbox(wall, "Kordonová římsa", length + 0.24, 0.3, -0.1, 0.12, 0, 7.6, "trim", r=0.03)
    for wall in ("front", "back"):
        wbox(wall, "Hlavní římsa", W + 0.4, 0.55, -0.1, 0.2, 0, H + 0.075, "trim", r=0.04)
    for wall in ("right", "left"):
        wbox(wall, "Římsa štítu", D + 0.24, 0.3, -0.1, 0.12, 0, H + 0.15, "trim", r=0.03)
    # The quoins up the four corners: long and short blocks in turn.
    corners = (("front", W / 2, "right"), ("front", -W / 2, "left"), ("back", W / 2, "left"), ("back", -W / 2, "right"))
    for wall, edge, side in corners:
        sign = 1 if edge > 0 else -1
        side_edge = (D / 2) * (1 if (wall == "front") == (side == "left") else -1)
        v, k = 1.05, 0
        while v + 0.8 < H - 0.05:
            if 7.3 < v + 0.8 and v < 7.95:
                v = 7.95  # (the band runs through here)
                continue
            a, b = (0.8, 0.5) if k % 2 == 0 else (0.5, 0.8)
            wbox(wall, "Rohový kvádr", a, 0.8, -0.2, 0.06, edge - sign * a / 2, v + 0.4, "stone2", r=0.03)
            wbox(side, "Rohový kvádr", b, 0.8, -0.2, 0.06, side_edge - (1 if side_edge > 0 else -1) * b / 2, v + 0.4, "stone2", r=0.03)
            v += 0.86
            k += 1


def fronts():
    L = LAYOUT
    upper = L["upper"]
    # The street side: the door in the middle (the game's door: 4 wide, 7 tall), windows either side on both floors,
    # their planters upstairs (and downstairs where nothing stands in front of the wall), a small one over the door.
    door("front", 0, 4.0, 6.85, double=True)
    for u in L["front"]:
        window("front", u, 3.2, 2.8, 3.6, keystone=True, flowers=L["front_flowers"])
        window("front", u, upper, 2.8, 3.0, flowers=True)
    window("front", 0, L["small"], 1.6, 1.6, tag="Okénko")
    lantern("front", L["lantern"])
    for u in L["bushes"]:
        at, _ = WALLS["front"]
        ball("Keř", 0.85, at(u, 0.7, 0.95), "shrub", scale=(1.15, 1.0, 0.85), seg=12)
    # The garden side: a back door, windows.
    door("back", 0, 3.0, 6.8, double=False)
    for u in L["back"]:
        window("back", u, 3.2, 2.8, 3.6)
    for u in L["back_upper"]:
        window("back", u, upper, 2.8, 3.0)
    # The gable sides: windows on both floors, planters downstairs, attic windows in the gable.
    for wall in ("right", "left"):
        for u in L["side"]:
            window(wall, u, 3.2, 2.8, 3.6, keystone=True, flowers=True)
            window(wall, u, upper, 2.8, 3.0)
        for u in L["attic"]:
            window(wall, u, H + 2.6, 1.8, 2.2, tag="Půdní okno")


def door(wall, u, ow, oh, double):
    vb = 0.15
    wcut(wall, "Dveře řez", ow, oh, u, vb + oh / 2)
    leaves = 2 if double else 1
    lw = ow / leaves
    for k in range(leaves):
        cu = u - ow / 2 + lw * (k + 0.5)
        wbox(wall, "Křídlo dveří", lw - 0.04, oh - 0.03, -0.34, -0.22, cu, vb + oh / 2, "door", r=0.02)
        wbox(wall, "Kazeta", lw - 0.6, 2.3, -0.22, -0.18, cu, vb + 1.8, "door", r=0.04)
        wbox(wall, "Kazeta", lw - 0.6, 0.8, -0.22, -0.18, cu, vb + oh - 0.75, "door", r=0.04)
        wbox(wall, "Sklo dveří", lw - 0.75, 1.9, -0.23, -0.2, cu, vb + 4.35, "glass", r=0)
        wbox(wall, "Mřížka", 0.08, 1.9, -0.2, -0.17, cu, vb + 4.35, "door", r=0.01)
        wbox(wall, "Mřížka", lw - 0.75, 0.08, -0.2, -0.17, cu, vb + 4.35, "door", r=0.01)
        at, _ = WALLS[wall]
        hu = cu + (lw / 2 - 0.3) * (1 if k == 0 and double else -1)
        cyl("Klika", 0.07, 0.22, at(hu, vb + 3.1, -0.11), "brass", axis="Y", seg=8)
        wbox(wall, "Klika", 0.38, 0.07, -0.08, -0.02, hu - 0.12 * (1 if k == 0 and double else -1), vb + 3.1, "brass", r=0.02)
    # The stone portal and the step.
    for side in (-1, 1):
        wbox(wall, "Portál", 0.45, oh + vb, -0.05, 0.08, u + side * (ow / 2 + 0.225), (oh + vb) / 2, "stone2", r=0.03)
    wbox(wall, "Portál", ow + 0.9, 0.4, -0.05, 0.08, u, oh + vb + 0.2, "stone2", r=0.03)
    wbox(wall, "Schod", ow + 1.0, 0.18, -0.35, 1.0, u, 0.09, "stone", r=0.03)


def lantern(wall, u):
    wbox(wall, "Lucerna držák", 0.14, 0.14, 0.0, 0.55, u, 6.15, "black", r=0.01)
    wbox(wall, "Lucerna", 0.55, 0.95, 0.45, 1.0, u, 5.6, "black", r=0.02)
    wbox(wall, "Lucerna světlo", 0.43, 0.72, 0.51, 0.94, u, 5.6, "glow", r=0)
    at, _ = WALLS[wall]
    cyl("Lucerna stříška", 0.44, 0.3, at(u, 6.22, 0.72), "black", seg=4, r2=0.03, rot=euler(rz=math.pi / 4))


def slope(side):
    """The slope's directions: up it (eaves to ridge) and out of it. side -1: the front slope, +1: the back."""
    up = Vector((0, -side * C, S))
    out = Vector((0, side * S, C))
    return up, out


def on_roof(side, x, u, off):
    """A point on the roof: x along the ridge, u up the slope from the eaves, off out of the boards' underside."""
    up, out = slope(side)
    return Vector((x, side * Y_E, Z_EB)) + up * u + out * off


def slope_turn(side):
    return euler(rx=math.radians(PITCH)) if side < 0 else euler(rz=math.pi) @ euler(rx=math.radians(PITCH))


def tile_row(name, side, u0, length, x0, x1, finish, amp=0.09, lift=0.12, period=None, steps=None):
    """One course of pantiles: a wavy strip up the slope from u0, its lower edge lifted (the course under it shows)."""
    up, out = slope(side)
    big = W > 30  # (a big house: coarser waves, the same look from the street, a third of the triangles)
    period = period or (1.3 if big else 1.0)
    steps = steps or (3 if big else 6)
    n = max(1, round((x1 - x0) / period))
    lam = (x1 - x0) / n
    xs = [x0 + (x1 - x0) * i / (n * steps) for i in range(n * steps + 1)]

    def wave(x):
        return amp * (0.5 - 0.5 * math.cos(2 * math.pi * (x - x0) / lam))
    bm = bmesh.new()
    low = [bm.verts.new(on_roof(side, x, u0, SLAB + 0.02 + wave(x) + lift)) for x in xs]
    high = [bm.verts.new(on_roof(side, x, u0 + length, SLAB + 0.02 + wave(x))) for x in xs]
    foot = [bm.verts.new(on_roof(side, x, u0, SLAB)) for x in xs]
    tops, lips = [], []
    for i in range(len(xs) - 1):
        tops.append(bm.faces.new((low[i], low[i + 1], high[i + 1], high[i])))
        lips.append(bm.faces.new((foot[i], foot[i + 1], low[i + 1], low[i])))
    for faces, want in ((tops, out), (lips, -up)):
        for f in faces:
            f.normal_update()
            if f.normal.dot(want) < 0:
                f.normal_flip()
    bm.normal_update()
    sharpen(bm, 35)
    return obj(name, bm, finish)


def roof():
    x0, x1 = -W / 2 - VERGE, W / 2 + VERGE
    span = x1 - x0
    for side in (-1, 1):
        up, out = slope(side)
        # The boards (their underside is the soffit), the tiles in courses, the fascia and the gutter at the eaves.
        length = ROOF_L + 0.3
        centre = on_roof(side, 0, length / 2, SLAB / 2)
        box("Bednění", (span, length, SLAB), centre, "soffit", r=0, rot=slope_turn(side))
        pitch, course = 0.7, 0.82
        k, u = 0, 0.0
        while u < ROOF_L - 0.15:
            tile_row("Tašky", side, u, min(course, ROOF_L + 0.05 - u), x0, x1, "tile" if k % 2 == 0 else "tile2")
            k += 1
            u += pitch
        for x in (x0 - 0.06, x1 + 0.06):
            box("Štítové prkno", (0.12, length, 0.62), on_roof(side, x, length / 2, 0.22), "soffit", r=0.02, rot=slope_turn(side))
        y = side * (Y_E + 0.13)
        box("Čelní prkno", (span + 0.24, 0.12, 0.5), (0, y, Z_EB + 0.05), "trim", r=0.02)
        cyl("Okap", 0.17, span + 0.3, (0, side * (Y_E + 0.3), Z_EB - 0.12), "zinc", axis="X", seg=12)
        for x in (W / 2 - 0.35, -W / 2 + 0.35):
            wall_y = side * (D / 2 + 0.22)
            tube("Svod", (x, wall_y, 0.25), (x, wall_y, H - 1.0), 0.11, "zinc")
            tube("Svod", (x, wall_y, H - 1.0), (x, side * (Y_E + 0.3), Z_EB - 0.3), 0.11, "zinc")
            tube("Svod", (x, wall_y, 0.25), (x, side * (D / 2 + 0.55), 0.12), 0.11, "zinc")
    # The ridge tiles.
    cyl("Hřebenáč", 0.34, span + 0.12, (0, 0, Z_RT + 0.1), "tile3", axis="X", seg=16)
    for x in (x0 - 0.06, x1 + 0.06):
        ball("Hřebenáč konec", 0.34, (x, 0, Z_RT + 0.1), "tile3", seg=12)
    for x in LAYOUT["dormers"]:
        dormer(x)
    for x, y in LAYOUT["chimneys"]:
        chimney(x, y)


def roof_top(y):
    """The tiles' top over a point of the roof (y from the middle: the ridge is at 0)."""
    return Z_EB + (Y_E - abs(y)) * T + SLAB / C + 0.25


def dormer(x0=0.0):
    """A gabled dormer on the street slope: its plastered cheeks, its window, its own little roof, deep enough for its
    ridge to end inside the main roof."""
    yf = -D / 2 + 2.0
    half = 1.7
    top = H + 5.4
    bottom = Z_EB + (Y_E - abs(yf)) * T - 0.2  # (under the main roof's boards at its front)
    ridge_top = top + half - 0.05 + 0.22 * math.sqrt(2) + 0.26
    back = Y_E - (ridge_top - Z_EB - SLAB / C - 0.25) / T  # (where the main roof is over its ridge)
    depth = max(5.0, -back - yf + 0.3)
    openings(box("Vikýř", (2 * half, depth, top - bottom), (x0, yf + depth / 2, (top + bottom) / 2), "plaster", r=0))
    # Its window on its front (a wall frame at y = yf, like the front's).
    WALLS["dormer"] = (lambda u, v, w: Vector((x0 + u, yf - w, v)), "y")
    window("dormer", 0, H + 3.2, 1.6, 1.7, tag="Vikýř okno")
    wbox("dormer", "Vikýř římsa", 2 * half + 0.3, 0.25, -0.1, 0.12, 0, top - 0.1, "trim", r=0.02)
    # Its gable over the window and its roof (45°), both reaching back into the main roof.
    apex = half - 0.05
    bm = bmesh.new()
    a = [bm.verts.new((x0 - half, yf, top)), bm.verts.new((x0 + half, yf, top)), bm.verts.new((x0, yf, top + apex))]
    b = [bm.verts.new((v.co.x, yf + depth, v.co.z)) for v in a]
    bm.faces.new((a[0], a[1], a[2]))
    bm.faces.new((b[0], b[2], b[1]))
    bm.faces.new((a[0], b[0], b[1], a[1]))
    bm.faces.new((a[1], b[1], b[2], a[2]))
    bm.faces.new((a[2], b[2], b[0], a[0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj("Vikýř štít", bm, "plaster", smooth=False)
    reach = half + 0.3                       # the ridge to the eaves, across
    length = reach * math.sqrt(2)            # ... along the slope
    thick = 0.22
    lift = thick / 2 * math.sqrt(0.5)
    ridge = top + apex                       # the boards' underside at the ridge
    for side in (-1, 1):
        turn = euler(ry=side * math.radians(45))
        cx = x0 + side * (reach / 2 + lift)
        cz = ridge - reach / 2 + lift
        box("Vikýř střecha", (length, depth + 0.4, thick), (cx, yf + depth / 2 - 0.2, cz), "tile2", r=0.02, rot=turn)
        surface = ridge + thick * math.sqrt(2)  # the boards' top over the ridge line
        for k in range(3):
            x = 0.45 + 0.55 * k
            box("Vikýř tašky", (0.14, depth + 0.4, 0.1), (x0 + side * x, yf + depth / 2 - 0.2, surface - x + 0.03), "tile", r=0.02, rot=turn)
        box("Vikýř prkno", (length, 0.1, 0.34), (cx, yf - 0.42, cz - 0.03), "trim", r=0.02, rot=turn)
    cyl("Vikýř hřebenáč", 0.16, depth + 0.4, (x0, yf + depth / 2 - 0.2, ridge + thick * math.sqrt(2) - 0.02), "tile3", axis="Y", seg=12)


def chimney(x, y):
    top = Z_RT + 2.5
    if LAYOUT["top"]:
        top = min(top, LAYOUT["top"] - 0.75)  # (its cap under the house's height in the game)
    base = roof_top(y) - 2.0
    box("Komín", (1.3, 1.3, top - base), (x, y, (top + base) / 2), "plaster", r=0.02)
    box("Komín římsa", (1.46, 1.46, 0.28), (x, y, top - 0.41), "stone2", r=0.03)
    box("Komín hlava", (1.42, 1.42, 0.14), (x, y, top + 0.07), "stone2", r=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Komín sloupek", (0.15, 0.15, 0.4), (x + sx * 0.5, y + sy * 0.5, top + 0.34), "stone2", r=0.01)
    box("Komín stříška", (1.7, 1.7, 0.14), (x, y, top + 0.6), "tile3", r=0.02)


def build():
    global COL, CUT
    for name in ("House", "House cutters"):
        old = bpy.data.collections.get(name)
        if old:
            for o in list(old.objects):
                bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.collections.remove(old)
    for name, kind in (("Cube", "MESH"), ("Light", "LIGHT"), ("Camera", "CAMERA")):
        o = bpy.data.objects.get(name)
        if o and o.type == kind:
            bpy.data.objects.remove(o, do_unlink=True)
    materials()
    COL = bpy.data.collections.new("House")
    bpy.context.scene.collection.children.link(COL)
    CUT = bpy.data.collections.new("House cutters")
    bpy.context.scene.collection.children.link(CUT)
    COL["box"] = [W, H, D]
    walls()
    fronts()
    roof()
    bpy.context.view_layer.layer_collection.children["House cutters"].hide_viewport = True


# ───────────────────────────────────────────────────────────── scéna a render
def scene():
    """Grass, the path to the street, a sky, the sun and two cameras (the 3/4 view and the street view)."""
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    col = bpy.data.collections.get("Garden") or bpy.data.collections.new("Garden")
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    world = sc.world or bpy.data.worlds.new("House world")
    sc.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*linear("#9CC3E6"), 1)
    bg.inputs["Strength"].default_value = 0.9

    def mat(name, colour, rough=0.9):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.diffuse_color = (*linear(colour), 1)
        try:
            m.use_nodes = True
        except Exception:
            pass
        p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        p.inputs["Base Color"].default_value = m.diffuse_color
        p.inputs["Roughness"].default_value = rough
        return m

    def plane(name, size, at, m):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(m)
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.location = at
        return o
    k = max(W / 20.3572, 1.0)  # (the scene and the cameras grow with the house)
    plane("Trávník", (90 * k, 90 * k, 0.2), (0, -6 * k, -0.1), mat("Garden grass", "#5E8A44"))
    plane("Chodník k domu", (3 + 3 * (k > 1), 7.0 * k, 0.1), (0, -D / 2 - 3.5 * k, 0.05), mat("Garden path", "#B0ACA4"))
    plane("Chodník", (90 * k, 5, 0.12), (0, -D / 2 - 9.5 * k, 0.06), mat("Garden sidewalk", "#9A968E"))
    sun = bpy.data.objects.new("Slunce", bpy.data.lights.new("Slunce", "SUN"))
    col.objects.link(sun)
    sun.data.energy, sun.data.angle = 3.2, math.radians(6)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-38))
    for name, target, direction, distance, lens in (("Kamera", (0, 0, 10.0 * k ** 0.5), (1.0, -1.45, 0.62), 57 * k, 40),
                                                     ("Kamera ulice", (0, 0, 10.5 * k ** 0.5), (0.0, -1.0, 0.16), 54 * k, 40)):
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        col.objects.link(cam)
        cam.location = Vector(target) + Vector(direction).normalized() * distance
        cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
    sc.camera = bpy.data.objects["Kamera"]
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            sc.render.engine = engine
            break
        except TypeError:
            continue
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass


def render_all(folder, samples=64):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples, sc.cycles.use_denoising = samples, True
    os.makedirs(folder, exist_ok=True)
    for name, file in (("Kamera", "house-34.png"), ("Kamera ulice", "house-front.png")):
        sc.camera = bpy.data.objects[name]
        sc.render.filepath = os.path.join(folder, file)
        bpy.ops.render.render(write_still=True)
    sc.camera = bpy.data.objects["Kamera"]


# ───────────────────────────────────────────────────────────── export do hry
def split_by_finish(me, matrix, out, fallback):
    loops = len(me.loops)
    flat = [0.0] * (loops * 3)
    me.corner_normals.foreach_get("vector", flat)
    turn = matrix.to_3x3().inverted_safe().transposed()
    world = []
    for i in range(loops):
        n = turn @ Vector(flat[i * 3:i * 3 + 3])
        n.normalize()
        world.extend(n)
    attr = me.attributes.get("nrm") or me.attributes.new("nrm", "FLOAT_VECTOR", "CORNER")
    attr.data.foreach_set("vector", world)
    names = [m["finish"] if m else fallback for m in me.materials]  # (a Boolean's cut faces: the object's own finish)
    fin = me.attributes.get("fin") or me.attributes.new("fin", "INT", "FACE")
    fin.data.foreach_set("value", [p.material_index for p in me.polygons])
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    layer = bm.faces.layers.int.get("fin")
    for k in sorted({f[layer] for f in bm.faces}):
        part = bm.copy()
        player = part.faces.layers.int.get("fin")
        bmesh.ops.delete(part, geom=[f for f in part.faces if f[player] != k], context="FACES")
        piece = bpy.data.meshes.new("piece")
        part.to_mesh(piece)
        part.free()
        out.setdefault(names[k], []).append(piece)
    bm.free()


def game(v):
    """Blender → the game's axes (x right = here -x, y up = here z, z back = here y)."""
    return Vector((-v.x, v.z, v.y))


def bounds(points):
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return [round((a + b) / 2, 4) for a, b in zip(lo, hi)], [round(b - a, 4) for a, b in zip(lo, hi)]


def export_game(folder, budget=10000):
    """ZDCHouseArt.fbx for the game: "house_<finish>" pieces (more than `budget` triangles: "house2_<finish>" too ...)
    and the markers mark_o / mark_x / mark_y / mark_z (the origin and 10 studs along the game's axes) and mark_box (the
    box's corner: W / 2 right, H up, D / 2 back). The manifest has the pieces' boxes and every detail's (game axes)."""
    os.makedirs(folder, exist_ok=True)
    temp = bpy.data.collections.new("House_Export")
    bpy.context.scene.collection.children.link(temp)
    dg = bpy.context.evaluated_depsgraph_get()
    pieces, details = {}, []
    for o in COL.objects:
        if o.type != "MESH":
            continue
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        if not me.polygons:
            continue
        centre, size = bounds([game(o.matrix_world @ v.co) for v in me.vertices])
        finish = o.material_slots[0].material["finish"]
        details.append({"name": o.name, "finish": finish, "center": centre, "size": size})
        split_by_finish(me, o.matrix_world.copy(), pieces, finish)
    made, manifest = [], {"target": TARGET, "box": [W, H, D], "pitch": PITCH, "pieces": {}, "details": details}
    for finish, meshes in sorted(pieces.items()):
        groups, tris = [[]], 0
        for piece in meshes:
            t = sum(len(p.vertices) - 2 for p in piece.polygons)
            if groups[-1] and tris + t > budget:
                groups.append([])
                tris = 0
            groups[-1].append(piece)
            tris += t
        for g, group in enumerate(groups):
            name = f"house{'' if g == 0 else g + 1}_{finish}"
            bm = bmesh.new()
            for piece in group:
                bm.from_mesh(piece)
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            normals = [0.0] * (len(me.loops) * 3)
            me.attributes["nrm"].data.foreach_get("vector", normals)
            for p in me.polygons:
                p.use_smooth = True
            me.normals_split_custom_set([normals[i:i + 3] for i in range(0, len(normals), 3)])
            for attr in ("nrm", "fin"):
                if me.attributes.get(attr):
                    me.attributes.remove(me.attributes[attr])
            me.materials.append(M[finish])
            o = bpy.data.objects.new(name, me)
            temp.objects.link(o)
            made.append(o)
            centre, size = bounds([game(v.co) for v in me.vertices])
            manifest["pieces"][name] = {"center": centre, "size": size, "triangles": sum(len(p.vertices) - 2 for p in me.polygons)}
    marks = [("mark_o", (0, 0, 0)), ("mark_x", (-10, 0, 0)), ("mark_y", (0, 0, 10)), ("mark_z", (0, 10, 0)), ("mark_box", (-W / 2, D / 2, H))]
    for name, at in marks:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.3)
        bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(M["black"])
        o = bpy.data.objects.new(name, me)
        temp.objects.link(o)
        made.append(o)
    for o in bpy.context.scene.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.fbx(filepath=os.path.join(folder, "ZDCHouseArt.fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="OFF", use_mesh_modifiers=True)
    with open(os.path.join(folder, "ZDCHouseArt.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    for o in list(temp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(temp)
    return manifest


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag):
        return argv[argv.index(flag) + 1] if flag in argv else None

    build()
    scene()
    source = globals().get("__file__", "")
    if os.path.isfile(source) and "house.py" not in bpy.data.texts:
        bpy.data.texts.new("house.py").write(open(source, encoding="utf-8").read())
    if arg("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--save")))
    if arg("--render"):
        render_all(arg("--render"), int(arg("--samples") or 64))
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        manifest = export_game(folder)
        tris = sum(p["triangles"] for p in manifest["pieces"].values())
        print(f"ZDCHouseArt: {len(manifest['pieces'])} pieces, {tris} triangles, the largest {max(p['triangles'] for p in manifest['pieces'].values())}")


main()
