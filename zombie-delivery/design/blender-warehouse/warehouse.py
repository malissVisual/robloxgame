"""Zombie Delivery: sklad ZDC v pěti úrovních (level 1 až 5) v Blenderu.

Spuštění v Blenderu: záložka Scripting → Open → warehouse.py → Run Script (▶, nebo Alt+P). Skript postaví vedle sebe
pět budov, od malé garáže (level 1) po logistické centrum (level 5), každou větší. Všechny mají otevřená vrata
uprostřed přední zdi (tam couvá dodávka) a prázdnou podlahu uvnitř, kam hra staví stojany se sbírkou.

Míry jsou ve studech (1 jednotka = 1 stud). Předek budovy míří na -Y, počátek každé úrovně je uprostřed vrat na zemi
(vnější líc přední zdi). Level 4 má přesně míry dnešního skladu ve hře (80 × 24 × 60, vrata 26 × 16) a level 5 se
ještě vejde na pozemek (120 × 152).

8.2: hra (server/WarehouseMesh.luau) obléká do levelu 4 sklad z dílů na každém pozemku (Config.Warehouse.ArtLevel).
Proto sedí na díly hry: zdi tlusté 1 stud jako ve hře, podlaha nahoře ve výšce 0,05 (pod nápisy na podlaze), vazníky
a světla v hale tam, kde jsou lampy hry, sloupky u vrat tam, kde jsou sloupky hry. Kontrola
tools/warehouse/mesh-check.py to hlídá.

Bez Blenderu, jen s modulem bpy (pip install bpy):
    python warehouse.py -- --save warehouse.blend --render složka --export složka
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

# ───────────────────────────────────────────────────────────── NASTAVENÍ
EXPORT = False   # True = uloží ZDCWarehouseArt.fbx pro hru do složky "roblox" vedle .blend souboru
GAP = 18         # mezera mezi budovami v řadě (studs)

# Úrovně: šířka W (napříč), hloubka D (dozadu), výška zdí H, vrata (šířka, výška), střecha, plášť, kolik stojanů
# se dovnitř vejde (návrh pro hru).
LEVELS = [
    {"id": 1, "name": "Garáž", "W": 26, "D": 22, "H": 12, "door": (14, 9.5), "roof": "shed", "rise": 2.5, "wall": "plaster", "stands": 2},
    {"id": 2, "name": "Dílna", "W": 40, "D": 30, "H": 15, "door": (18, 12), "roof": "gable", "rise": 4.5, "wall": "metal", "stands": 4},
    {"id": 3, "name": "Sklad", "W": 58, "D": 42, "H": 19, "door": (22, 14), "roof": "gable", "rise": 6, "wall": "plinth", "stands": 8},
    {"id": 4, "name": "Velký sklad", "W": 80, "D": 60, "H": 24, "door": (26, 16), "roof": "gable", "rise": 8, "wall": "twotone", "stands": 12,
     # (8.2: the game's hall: its tie beams' and lamps' places, studs in from the front wall; the game dresses this level)
     "trusses": (11, 22, 33, 44, 55), "lamps": [(x, z) for z in (22, 44) for x in (-21.5, 0.0, 21.5)]},
    {"id": 5, "name": "Logistické centrum", "W": 104, "D": 84, "H": 28, "door": (26, 18), "roof": "barrel", "rise": 10, "wall": "twotone", "stands": 20},
]

# Povrchy: jméno → (barva #RRGGBB, drsnost, kov, záře).
FINISHES = {
    "plaster": ("#D8D4CC", 0.85, 0, 0), "metal": ("#8E9AA6", 0.5, 0.6, 0), "metal2": ("#6F7C88", 0.5, 0.6, 0),
    "concrete": ("#A7A39B", 0.9, 0, 0), "floor": ("#9C9A94", 0.8, 0, 0), "orange": ("#E8762B", 0.5, 0, 0),
    "trim": ("#EDEBE6", 0.6, 0, 0), "steel": ("#5A6068", 0.4, 0.8, 0), "dark": ("#2A2D31", 0.6, 0, 0),
    "roof": ("#4B5057", 0.6, 0.3, 0), "glass": ("#2F4252", 0.05, 0, 0), "glasslit": ("#BFD6E2", 0.1, 0, 0.6),
    "skylight": ("#D8E6EA", 0.2, 0, 0.4), "glow": ("#FFF1D6", 0.5, 0, 3.0), "yellow": ("#F2C230", 0.5, 0, 0),
    "door": ("#C9CCD0", 0.5, 0.4, 0), "wood": ("#9A7550", 0.8, 0, 0), "rubber": ("#1A1A1C", 0.9, 0, 0),
    "solar": ("#1E2E4A", 0.15, 0.3, 0), "green": ("#4F7F3B", 0.8, 0, 0), "red": ("#C8322E", 0.5, 0, 0),
    "white": ("#F6F4EE", 0.5, 0, 0), "zinc": ("#9BA2A6", 0.35, 1, 0),
    # 8.2: the concrete floor's slabs in three shades and their joints (colours only)
    "floor2": ("#94928C", 0.8, 0, 0), "floor3": ("#A6A49E", 0.8, 0, 0), "joint": ("#74726E", 0.9, 0, 0),
}

T = 1.0          # the walls' thickness (8.2: the game's, WarehouseLayout.Wall)
FLOOR = 0.05     # the floor's top (8.2: the game's WarehouseLayout.FloorTop: its paint and stands lie on it)
M = {}
SOLIDS = []      # 8.2: the level being built: its things outside the walls that collide (the game makes their boxes)
COL = None
ORIGIN = Vector()  # the level being built: the roller door's middle on the ground, the front wall's outer face


def linear(hexcode):
    h = hexcode.lstrip("#")
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))


def materials():
    for name, (hexcode, rough, metal, emit) in FINISHES.items():
        m = bpy.data.materials.get("W " + name) or bpy.data.materials.new("W " + name)
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


# ───────────────────────────────────────────────────────────── stavební kameny (souřadnice od počátku úrovně)
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


def sharpen(bm, degrees=40):
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(degrees):
            e.smooth = False


def box(name, size, at, finish, r=0.0, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    sharpen(bm)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation(ORIGIN + Vector(at)) @ (rot or Matrix())
    if r > 0:
        b = o.modifiers.new("Bevel", "BEVEL")
        b.width, b.segments, b.limit_method, b.angle_limit = min(r, min(size) * 0.45), 1, "ANGLE", math.radians(40)
        b.harden_normals, b.use_clamp_overlap = True, True
    return o


def span(name, x0, x1, y0, y1, z0, z1, finish, r=0.0):
    """A block between two corners (from x0, y0, z0 to x1, y1, z1)."""
    return box(name, (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), finish, r)


def cyl(name, r, h, at, finish, axis="Z", seg=16, r2=None, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    sharpen(bm)
    o = obj(name, bm, finish)
    turn = {"Z": Matrix(), "X": euler(ry=math.pi / 2), "Y": euler(rx=math.pi / 2)}[axis]
    o.matrix_world = Matrix.Translation(ORIGIN + Vector(at)) @ (rot or Matrix()) @ turn
    return o


def tube(name, a, b, r, finish, seg=10):
    a, b = ORIGIN + Vector(a), ORIGIN + Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=(b - a).length)
    sharpen(bm)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat("Z", "Y").to_matrix().to_4x4()
    return o


def prism(name, pts, depth_axis, d0, d1, finish):
    """A flat shape (points in the plane across `depth_axis`) given thickness from d0 to d1 along it."""
    bm = bmesh.new()
    def place(p, d):
        a, b = p
        return {"y": (a, d, b), "x": (d, a, b)}[depth_axis]
    front = [bm.verts.new(place(p, d0)) for p in pts]
    back = [bm.verts.new(place(p, d1)) for p in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharpen(bm, 30)
    o = obj(name, bm, finish, smooth=False)
    o.matrix_world = Matrix.Translation(ORIGIN)
    return o


def text(name, body, size, at, finish, depth=0.25, face="front"):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = depth / 2
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    cu.materials.append(M[finish])
    o = bpy.data.objects.new(name, cu)
    COL.objects.link(o)
    turn = {"front": euler(rx=math.pi / 2), "left": euler(rx=math.pi / 2) @ euler(ry=-math.pi / 2)}[face]
    o.matrix_world = Matrix.Translation(ORIGIN + Vector(at)) @ turn
    return o


# ───────────────────────────────────────────────────────────── jedna budova
def ribs(name, axis, fixed, a0, a1, z0, z1, finish, top=None, step=1.6, out=0.16):
    """Corrugation: vertical ribs on a wall's face. axis "x": a wall along x at y = fixed (out = its outward
    direction's sign × depth); "y": along y at x = fixed. top(a) clips each rib's top (gables)."""
    n = int((a1 - a0) / step)
    pad = ((a1 - a0) - n * step) / 2
    for k in range(n + 1):
        a = a0 + pad + k * step
        t = z1 if top is None else min(z1, top(a))
        if t - z0 < 0.3:
            continue
        if axis == "x":
            box(name, (0.34, abs(out), t - z0), (a, fixed + out / 2, (z0 + t) / 2), finish)
        else:
            box(name, (abs(out), 0.34, t - z0), (fixed + out / 2, a, (z0 + t) / 2), finish)


def windows_row(wall, positions, z0, z1, w, lv):
    """Windows on a wall (frames and glass on both faces: dark outside, lit inside)."""
    W, D = lv["W"], lv["D"]
    for p in positions:
        if wall in ("left", "right"):
            x = (-W / 2 if wall == "left" else W / 2)
            s = -1 if wall == "left" else 1
            span("Okno rám", x + s * -0.05, x + s * 0.12, p - w / 2 - 0.2, p + w / 2 + 0.2, z0 - 0.2, z1 + 0.2, "trim")
            span("Okno sklo", x + s * 0.12, x + s * 0.16, p - w / 2, p + w / 2, z0, z1, "glass")
            span("Okno příčka", x + s * 0.16, x + s * 0.2, p - 0.06, p + 0.06, z0, z1, "trim")
            span("Okno uvnitř", x - s * (T + 0.02), x - s * (T + 0.06), p - w / 2, p + w / 2, z0, z1, "glasslit")
        else:  # the back wall
            y = D
            span("Okno rám", p - w / 2 - 0.2, p + w / 2 + 0.2, y - 0.05, y + 0.12, z0 - 0.2, z1 + 0.2, "trim")
            span("Okno sklo", p - w / 2, p + w / 2, y + 0.12, y + 0.16, z0, z1, "glass")
            span("Okno příčka", p - 0.06, p + 0.06, y + 0.16, y + 0.2, z0, z1, "trim")
            span("Okno uvnitř", p - w / 2, p + w / 2, y - T - 0.02, y - T - 0.06, z0, z1, "glasslit")


def floor(lv):
    """8.2: the floor inside as concrete slabs (10 × 10 from the door's middle and the front wall) in three shades with
    dark joints, its top at FLOOR (the game's paint and stands lie on it). Colours only: one flat top, its edges each
    the shade over them (so no shade's piece for the game is flat: Roblox sizes a mesh by its box)."""
    W, D = lv["W"], lv["D"]
    x0, x1, y0, y1 = -W / 2 + T, W / 2 - T, T, D - T
    xs, ys = {x0, x1}, {y0, y1}
    for k in range(-20, 21):
        for e in (10 * k - 0.05, 10 * k + 0.05):
            if x0 < e < x1:
                xs.add(e)
            if y0 < e < y1:
                ys.add(e)
    xs, ys = sorted(xs), sorted(ys)

    def shade(i, j):
        if abs((xs[i] + xs[i + 1]) / 2 - round((xs[i] + xs[i + 1]) / 20) * 10) < 0.06 or \
                abs((ys[j] + ys[j + 1]) / 2 - round((ys[j] + ys[j + 1]) / 20) * 10) < 0.06:
            return "joint"
        a, b = math.floor((xs[i] + xs[i + 1]) / 20), math.floor((ys[j] + ys[j + 1]) / 20)
        return ("floor", "floor2", "floor3")[(a * 7 + b * 3 + (a * b) % 5) % 3]
    finishes = ["floor", "floor2", "floor3", "joint"]
    bm = bmesh.new()
    faces = []

    def quad(pts, finish):
        f = bm.faces.new([bm.verts.new(p) for p in pts])
        f.material_index = finishes.index(finish)
        faces.append(f)
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            quad([(xs[i], ys[j], FLOOR), (xs[i + 1], ys[j], FLOOR), (xs[i + 1], ys[j + 1], FLOOR), (xs[i], ys[j + 1], FLOOR)], shade(i, j))
    for i in range(len(xs) - 1):
        for j, y in ((0, y0), (len(ys) - 2, y1)):
            quad([(xs[i], y, 0), (xs[i + 1], y, 0), (xs[i + 1], y, FLOOR), (xs[i], y, FLOOR)], shade(i, j))
    for j in range(len(ys) - 1):
        for i, x in ((0, x0), (len(xs) - 2, x1)):
            quad([(x, ys[j], 0), (x, ys[j + 1], 0), (x, ys[j + 1], FLOOR), (x, ys[j], FLOOR)], shade(i, j))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if abs(f.calc_center_median().z - FLOOR) < 1e-6:
            if f.normal.z < 0:
                f.normal_flip()
        elif f.normal.dot(f.calc_center_median() - Vector(((x0 + x1) / 2, (y0 + y1) / 2, 0))) < 0:
            f.normal_flip()
    me = bpy.data.meshes.new("Podlaha")
    bm.to_mesh(me)
    bm.free()
    for f in finishes:
        me.materials.append(M[f])
    o = bpy.data.objects.new("Podlaha", me)
    COL.objects.link(o)
    o.matrix_world = Matrix.Translation(ORIGIN)
    return o


def prop(name, x0, x1, y0, y1, z0, z1, finish):
    """8.2: a thing outside the walls that one bumps into: its block, and its box for the game's collision."""
    span(name, x0, x1, y0, y1, z0, z1, finish)
    SOLIDS.append([min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1)])


def building(lv):
    W, D, H = lv["W"], lv["D"], lv["H"]
    dw, dh = lv["door"]
    roof, rise, kind = lv["roof"], lv["rise"], lv["wall"]
    hw = W / 2
    # The heights of the walls' tops: a shed roof falls to the back; the others are level.
    back_h = H - rise if roof == "shed" else H
    collide = []
    SOLIDS.clear()

    def solid(name, x0, x1, y0, y1, z0, z1, finish):
        span(name, x0, x1, y0, y1, z0, z1, finish)
        collide.append([x0, x1, y0, y1, z0, z1])
    core = "plaster" if kind == "plaster" else "metal"
    # Floor and walls (the front wall in three pieces round the open roller door).
    floor(lv)
    solid("Zadní zeď", -hw, hw, D - T, D, 0, back_h, core)
    if roof == "shed":
        for s in (-1, 1):
            x0, x1 = sorted((s * hw, s * (hw - T)))
            solid("Boční zeď", x0, x1, 0, D, 0, back_h, core)
            prism("Boční zeď štít", [(0, back_h), (D, back_h), (0, H)], "x", x0, x1, core)
    else:
        for s in (-1, 1):
            x0, x1 = sorted((s * hw, s * (hw - T)))
            solid("Boční zeď", x0, x1, 0, D, 0, H, core)
    solid("Přední zeď", -hw, -dw / 2, 0, T, 0, H, core)
    solid("Přední zeď", dw / 2, hw, 0, T, 0, H, core)
    solid("Nadpraží", -dw / 2, dw / 2, 0, T, dh, H, core)
    # The cladding.
    plinth = {"plaster": 0.9, "metal": 0.6, "plinth": 3.0, "twotone": 2.2}[kind]
    span("Sokl", -hw - 0.12, -dw / 2, -0.12, T, 0, plinth, "concrete")
    span("Sokl", dw / 2, hw + 0.12, -0.12, T, 0, plinth, "concrete")
    span("Sokl", -hw - 0.12, hw + 0.12, D - T, D + 0.12, 0, plinth, "concrete")
    for s in (-1, 1):
        x0, x1 = sorted((s * (hw + 0.12), s * (hw - T)))
        span("Sokl", x0, x1, 0, D, 0, plinth, "concrete")
    span("Podlaha vrat", -dw / 2, dw / 2, 0, T, 0, FLOOR, "floor")  # (no step at the door)
    if kind == "plaster":
        for x in (-hw, hw):
            s_ = 1 if x > 0 else -1
            span("Roh", x - s_ * 0.6, x + s_ * 0.06, -0.06, 0.6, plinth, H - 0.5, "trim")
            span("Roh", x - s_ * 0.6, x + s_ * 0.06, D - 0.6, D + 0.06, plinth, back_h, "trim")
        span("Římsa", -hw - 0.2, hw + 0.2, -0.2, 0.3, H - 0.5, H, "trim")
    else:
        band = (H * 0.62, H * 0.62 + 2.2) if kind == "twotone" else None

        def wall_ribs(axis, fixed, a0, a1, z0, z1, out, top=None):
            if band:
                ribs("Plech", axis, fixed, a0, a1, z0, min(z1, band[0]), "metal", out=out, top=top)
                ribs("Pruh", axis, fixed, a0, a1, band[0], min(z1, band[1]), "orange", out=out, top=top)
                ribs("Plech", axis, fixed, a0, a1, band[1], z1, "metal", out=out, top=top)
            else:
                ribs("Plech", axis, fixed, a0, a1, z0, z1, "metal2", out=out, top=top)
        wall_ribs("x", 0, -hw + 0.3, -dw / 2 - 0.9, plinth, H, -0.16)
        wall_ribs("x", 0, dw / 2 + 0.9, hw - 0.3, plinth, H, -0.16)
        wall_ribs("x", 0, -dw / 2 - 0.9, dw / 2 + 0.9, dh + 1.2, H, -0.16)
        wall_ribs("x", D, -hw + 0.3, hw - 0.3, plinth, back_h, 0.16)
        for s in (-1, 1):
            wall_ribs("y", s * hw, 0.3, D - 0.3, plinth, H, s * 0.16)
        for x in (-hw, hw):
            for y in (0, D):
                span("Roh", x - 0.3, x + 0.3, y - 0.3, y + 0.3, plinth, H, "orange" if kind != "metal" else "trim")
    # The roller door: its frame, the rails, the rolled-up curtain in its box over the opening.
    frame = "trim" if kind == "plaster" else "orange"
    for s in (-1, 1):  # (all of it beside and over the opening: the door stays its full width)
        span("Rám vrat", s * dw / 2, s * (dw / 2 + 0.7), -0.35, T, 0, dh + 0.35, frame)
        span("Kolejnice", s * (dw / 2 + 0.05), s * (dw / 2 + 0.25), T, T + 0.4, 0, dh, "steel")
    span("Rám vrat", -dw / 2 - 0.7, dw / 2 + 0.7, -0.35, T, dh, dh + 0.5, frame)
    if roof == "shed":  # a garage: its sectional door lies open under the ceiling
        span("Vrata", -dw / 2 + 0.2, dw / 2 - 0.2, T + 0.3, T + 0.3 + dh, dh + 0.2, dh + 0.45, "door")
        for k in range(1, 5):
            span("Vrata spára", -dw / 2 + 0.2, dw / 2 - 0.2, T + 0.3 + k * dh / 5 - 0.05, T + 0.3 + k * dh / 5 + 0.05, dh + 0.17, dh + 0.2, "steel")
    else:
        cyl("Roleta", 0.9, dw - 0.2, (0, T + 1.0, dh + 0.95), "door", axis="X", seg=20)
        span("Box rolety", -dw / 2 - 0.1, dw / 2 + 0.1, T + 0.1, T + 2.0, dh + 1.85, dh + 2.05, "steel")
    # The way in: hazard posts either side of the door (from level 3), the dock bumpers.
    if lv["id"] >= 3:
        for s in (-1, 1):
            cyl("Sloupek", 0.5, 3.4, (s * (dw / 2 + 1.8), -1.4, 1.7), "yellow", seg=14)  # (8.2: where the game's stand)
            span("Nárazník", s * (dw / 2 + 0.4) - 0.4, s * (dw / 2 + 0.4) + 0.4, -0.7, -0.35, 0.6, 2.2, "rubber")
    # Lamps over the door.
    lx, lz = (dw / 2 + 1.6, dh - 1.6) if roof == "shed" else (dw / 2 + 2.0, dh + 1.4)
    for s in (-1, 1):
        span("Lampa", s * lx - 0.5, s * lx + 0.5, -0.9, 0, lz, lz + 0.4, "dark")
        span("Lampa světlo", s * lx - 0.4, s * lx + 0.4, -0.85, -0.05, lz - 0.08, lz + 0.02, "glow")
    roofing(lv, back_h)
    inside(lv, back_h)
    extras(lv)
    return collide, list(SOLIDS)


def roofing(lv, back_h):
    W, D, H = lv["W"], lv["D"], lv["H"]
    roof, rise = lv["roof"], lv["rise"]
    hw, over = W / 2, 1.0
    if roof == "shed":
        run = D + 2 * over
        drop = rise * run / D
        angle = math.atan2(rise, D)
        box("Střecha", (W + 2 * over, run / math.cos(angle), 0.4), (0, D / 2, (H + back_h) / 2 + 0.2), "roof", rot=euler(rx=-angle))
        box("Atika", (W + 2 * over + 0.2, 0.3, 0.7), (0, -over, H + over * rise / D + 0.3), "trim")
        cyl("Okap", 0.18, W + 2.2, (0, D + over + 0.2, back_h - over * rise / D - 0.15), "zinc", axis="X", seg=10)
        for s in (-1, 1):
            tube("Svod", (s * (hw - 0.4), D + 0.25, 0.3), (s * (hw - 0.4), D + 0.25, back_h - 0.5), 0.12, "zinc")
        return
    if roof == "gable":
        half = W / 2 + over
        angle = math.atan2(rise, W / 2)
        slope = half / math.cos(angle)
        for s in (-1, 1):
            turn = euler(ry=s * angle)
            centre = (s * half / 2, D / 2, H + rise - (half / 2) * math.tan(angle) + 0.25)
            box("Střecha", (slope, D + 2 * over, 0.4), centre, "roof", rot=turn)
            # standing seams down the slope, a skylight strip from level 3
            n = int((D + 2 * over) / 2.0)
            for k in range(n + 1):
                y = -over + k * (D + 2 * over) / n
                box("Lem", (slope, 0.18, 0.14), (centre[0], y, centre[2] + 0.27 / math.cos(angle)), "metal2", rot=turn)
            if lv["id"] >= 3:
                box("Světlík", (slope * 0.18, D * 0.8, 0.12), (s * half * 0.55, D / 2, H + rise - half * 0.55 * math.tan(angle) + 0.5), "skylight", rot=turn)
            cyl("Okap", 0.2, D + 2.4, (s * (half + 0.15), D / 2, H - over * math.tan(angle) - 0.05), "zinc", axis="Y", seg=10)
            for y in (0.4, D - 0.4):
                tube("Svod", (s * (hw + 0.2), y, 0.3), (s * (hw + 0.2), y, H - 0.6), 0.14, "zinc")
                tube("Svod", (s * (hw + 0.2), y, H - 0.6), (s * (half + 0.15), y if y < 1 else y, H - over * math.tan(angle) - 0.2), 0.14, "zinc")
        box("Hřeben", (0.9, D + 2 * over + 0.2, 0.35), (0, D / 2, H + rise + 0.62), "metal2")
        for y, face in ((0, -1), (D, 1)):
            prism("Štít", [(-hw, H), (hw, H), (0, H + rise)], "y", y if face > 0 else 0, y - T if face > 0 else T, "metal")
            ribs("Plech štítu", "x", y, -hw + 0.3, hw - 0.3, H, H + rise, "metal2", out=0.16 * face, top=lambda a: H + rise * (1 - abs(a) / hw) - 0.15)
            box("Lišta štítu", (math.hypot(hw, rise) + 0.4, 0.3, 0.3), (-hw / 2, y + face * 0.25, H + rise / 2 + 0.2), "trim", rot=euler(ry=-angle))
            box("Lišta štítu", (math.hypot(hw, rise) + 0.4, 0.3, 0.3), (hw / 2, y + face * 0.25, H + rise / 2 + 0.2), "trim", rot=euler(ry=angle))
        return
    # barrel: a vaulted roof (an arc across the width) behind a parapet
    r = (hw * hw + rise * rise) / (2 * rise)
    cz = H + rise - r
    a0 = math.asin(hw / r)
    seg = 28
    bm = bmesh.new()
    rows = []
    for k in range(seg + 1):
        a = -a0 + 2 * a0 * k / seg
        x, z = r * math.sin(a), cz + r * math.cos(a)
        nx, nz = math.sin(a), math.cos(a)
        rows.append([bm.verts.new((x + nx * dz, y, z + nz * dz)) for y in (-0.6, D + 0.6) for dz in (0.0, 0.4)])
    for k in range(seg):
        a, b = rows[k], rows[k + 1]
        bm.faces.new((a[1], b[1], b[3], a[3]))  # top
        bm.faces.new((a[0], a[2], b[2], b[0]))  # underside
        bm.faces.new((a[0], b[0], b[1], a[1]))  # front edge
        bm.faces.new((a[2], a[3], b[3], b[2]))  # back edge
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj("Klenutá střecha", bm, "roof")
    o.matrix_world = Matrix.Translation(ORIGIN)
    for k in range(1, int(D / 3)):
        y = k * D / int(D / 3)
        pts = []
        for j in range(seg + 1):
            a = -a0 + 2 * a0 * j / seg
            pts.append((r * math.sin(a) * 1.0, cz + r * math.cos(a) + 0.4))
        for j in range(seg):
            (x1, z1), (x2, z2) = pts[j], pts[j + 1]
            box("Lem", (math.hypot(x2 - x1, z2 - z1) + 0.02, 0.16, 0.12), ((x1 + x2) / 2, y, (z1 + z2) / 2 + 0.06), "metal2",
                rot=euler(ry=-math.atan2(z2 - z1, x2 - x1)))
    for y, face in ((0, -1), (D, 1)):
        pts = [(-hw, H)] + [(r * math.sin(-a0 + 2 * a0 * j / seg), cz + r * math.cos(-a0 + 2 * a0 * j / seg)) for j in range(seg + 1)] + [(hw, H)]
        prism("Štít", pts[1:-1], "y", (y - T) if face > 0 else 0.0, y if face > 0 else T, "metal")
    for s in (-1, 1):
        span("Atika", s * hw - 0.4, s * hw + 0.4, -0.4, D + 0.4, H, H + 1.2, "trim")
    for y in (-0.4, D):
        span("Atika", -hw - 0.4, hw + 0.4, y, y + 0.4, H, H + 1.2, "trim")


def inside(lv, back_h):
    """Under the roof: steel trusses (from level 2) and the hall's lights."""
    W, D, H = lv["W"], lv["D"], lv["H"]
    hw = W / 2
    if lv["roof"] == "shed":
        span("Trám", -hw + T, hw - T, D * 0.5 - 0.3, D * 0.5 + 0.3, back_h - 0.6, back_h - 0.1, "wood")
        span("Světlo", -1.8, 1.8, D * 0.5 - 0.3, D * 0.5 + 0.3, back_h - 0.85, back_h - 0.6, "glow")
        return
    n = max(2, int(D / 10))
    trusses = lv.get("trusses") or [k * D / n for k in range(1, n)]
    for y in trusses:
        span("Vazník", -hw + T, hw - T, y - 0.25, y + 0.25, H - 0.6, H - 0.1, "steel")
        for s in (-1, 1):
            span("Sloupek vazníku", s * hw * 0.5 - 0.15, s * hw * 0.5 + 0.15, y - 0.2, y + 0.2, H - 0.1, H + lv["rise"] * 0.45, "steel")
        if "lamps" not in lv:
            for x in [i * W / 4 - hw + W / 8 for i in range(4)]:
                span("Světlo", x - 1.6, x + 1.6, y - 0.35, y + 0.35, H - 1.0, H - 0.6, "glow")
    for x, y in lv.get("lamps", ()):  # (8.2: over the game's lamps, whose light shines from just under them)
        span("Světlo", x - 1.6, x + 1.6, y - 0.35, y + 0.35, H - 1.0, H - 0.6, "glow")


def extras(lv):
    W, D, H, lid = lv["W"], lv["D"], lv["H"], lv["id"]
    dw, dh = lv["door"]
    hw = W / 2
    # the ZDC sign: a plate on the garage, big letters in the gable / over the door from level 2
    if lid == 1:
        span("Cedule", -3.0, 3.0, -0.25, 0, dh + 0.6, dh + 1.6, "orange")
        text("Nápis ZDC", "ZDC", 0.9, (0, -0.3, dh + 1.1), "white", depth=0.1)
        # a side door, a window, a bin
        span("Dveře", hw - 0.02, hw + 0.12, 5.0, 8.4, 0.15, 7.2, "door")
        span("Dveře rám", hw - 0.02, hw + 0.08, 4.8, 8.6, 0.15, 7.4, "trim")
        windows_row("left", [D / 2], 4.0, 7.5, 4.0, lv)
        prop("Popelnice", -hw - 2.6, -hw - 0.6, 2.0, 4.0, 0, 3.0, "green")
        span("Víko", -hw - 2.7, -hw - 0.5, 1.9, 4.1, 3.0, 3.25, "dark")
        return
    top = H + (lv["rise"] * 0.55 if lv["roof"] == "gable" else 0)
    size = {2: 3.2, 3: 4.2, 4: 6.0, 5: 7.0}[lid]
    zl = (H + lv["rise"] * 0.42) if lv["roof"] == "gable" else (H + lv["rise"] * 0.42)
    text("Nápis ZDC", "ZDC", size, (0, -0.35, zl), "orange", depth=0.4)
    if lid >= 3:
        text("Nápis podtitul", "STORAGE" if lid < 5 else "LOGISTICS", size * 0.28, (0, -0.35, zl - size * 0.62), "white", depth=0.2)
    # a personnel door on the front, right of the roller door, with its canopy
    px = dw / 2 + 4.5
    span("Dveře", px - 1.8, px + 1.8, -0.12, 0.02, 0.15, 7.3, "door")
    span("Dveře rám", px - 2.1, px + 2.1, -0.18, 0.02, 0.15, 7.6, "trim")
    span("Stříška", px - 2.6, px + 2.6, -1.8, 0.0, 7.9, 8.15, "steel")
    # windows down the sides (and the back)
    count = {2: 3, 3: 4, 4: 5, 5: 7}[lid]
    ys = [D * (k + 0.5) / count for k in range(count)]
    zw = (H * 0.45, H * 0.45 + 3.2) if lid < 4 else (H * 0.55, H * 0.55 + 3.6)
    windows_row("left", ys, zw[0], zw[1], 4.2, lv)
    windows_row("right", ys, zw[0], zw[1], 4.2, lv)
    if lid >= 3:
        windows_row("back", [-W / 4, W / 4], zw[0], zw[1], 5.0, lv)
    if lid == 2:  # pallets and barrels outside
        for k in range(3):
            prop("Paleta", -hw - 4.5, -hw - 1.0, 3 + k * 4.2, 6.6 + k * 4.2, 0, 0.6, "wood")
        prop("Paleta", -hw - 4.5, -hw - 1.0, 3, 6.6, 0.6, 1.2, "wood")
        for k in range(3):
            cyl("Sud", 0.9, 2.6, (-hw - 2.5, D - 3 - k * 2.1, 1.3), "red" if k != 1 else "steel", seg=14)
            SOLIDS.append([-hw - 3.4, -hw - 1.6, D - 3 - k * 2.1 - 0.9, D - 3 - k * 2.1 + 0.9, 0, 2.6])
    if lid == 4:  # the office annex on the left, glazed, and the roof's air units
        ax0, ax1 = -hw - 14, -hw
        prop("Kancelář", ax0, ax1, 0.5, 16, 0, 11, "plaster")
        span("Kancelář střecha", ax0 - 0.4, ax1, 0.1, 16.4, 11, 11.6, "trim")
        span("Kancelář okno", ax0 + 1.0, ax1 - 1.0, 0.36, 0.5, 4.0, 9.5, "glass")
        span("Kancelář okno", ax0 - 0.14, ax0, 2.0, 14.5, 4.0, 9.5, "glass")
        for x in (ax0 + 4.5, ax0 + 9.0):
            span("Příčka", x - 0.1, x + 0.1, 0.3, 0.4, 4.0, 9.5, "trim")
        span("Kancelář dveře", ax0 + 1.2, ax0 + 4.2, 0.3, 0.5, 0.15, 7.0, "glass")
        for x in (-12, 12):
            span("Klimatizace", x - 2.5, x + 2.5, D * 0.6 - 2, D * 0.6 + 2, H + lv["rise"] * (1 - abs(x) / hw) - 0.2, H + lv["rise"] * (1 - abs(x) / hw) + 2.4, "steel")
    if lid == 5:  # a glazed office corner, docks either side, solar panels, flags, planters
        for x in (29.0, -36.0):  # (the Moving contracts board stands at x -24, a stud out from the wall: kept clear)
            span("Dokovací vrata", x - 5, x + 5, -0.1, 0.02, 1.4, 12, "door")
            for k in range(1, 7):
                span("Spára", x - 5, x + 5, -0.14, -0.1, 1.4 + k * 1.5, 1.45 + k * 1.5, "steel")
            span("Límec doku", x - 5.8, x + 5.8, -1.6, 0.0, 12, 13.2, "rubber")
            for e in (-1, 1):
                span("Límec doku", x + e * 5.4 - 0.4, x + e * 5.4 + 0.4, -1.6, 0.0, 1.4, 12, "rubber")
            prop("Rampa", x - 6, x + 6, -3.0, 0.0, 0, 1.4, "concrete")
        gx0 = hw - 15
        span("Prosklení", gx0, hw - 0.6, -0.2, -0.05, 3.0, H - 2.5, "glass")
        for k in range(1, 4):
            span("Sloupek fasády", gx0 + k * 3.6 - 0.12, gx0 + k * 3.6 + 0.12, -0.32, -0.05, 3.0, H - 2.5, "trim")
        for z in (3.0, 11.5, H - 2.5):
            span("Pás fasády", gx0, hw - 0.6, -0.32, -0.05, z - 0.25, z + 0.25, "trim")
        for col in range(4):
            for row in range(3):
                x = -hw + 12 + col * 22
                y = 12 + row * 22
                r_ = (lv["rise"] ** 2 + hw ** 2) / (2 * lv["rise"])
                cz = H + lv["rise"] - r_
                z = cz + math.sqrt(max(0.0, r_ * r_ - x * x)) + 1.0
                tilt = math.asin(max(-1, min(1, x / r_)))
                box("Solární panel", (14, 18, 0.25), (x, y, z), "solar", rot=euler(ry=-tilt))
        for k, colour in enumerate(("orange", "white", "orange")):
            fx = -hw + 4 + k * 4
            cyl("Stožár", 0.18, 16, (fx, -6, 8), "steel", seg=8)
            span("Vlajka", fx + 0.2, fx + 4.2, -6.06, -5.94, 12.5, 15.2, colour)
        for x in (-hw + 3, 44.0):
            prop("Truhlík", x - 2.5, x + 2.5, -4.5, -1.5, 0, 1.2, "concrete")
            span("Keře", x - 2.2, x + 2.2, -4.2, -1.8, 1.2, 2.4, "green")


# ───────────────────────────────────────────────────────────── stavba všech úrovní
def lineup():
    """Each level's origin in the row: left to right, bigger and bigger."""
    x, out = 0.0, []
    for lv in LEVELS:
        x += lv["W"] / 2 + (14 if lv["id"] == 4 else 0)
        out.append(Vector((x, 0, 0)))
        x += lv["W"] / 2 + GAP
    shift = (out[0].x + out[-1].x) / 2
    return [v - Vector((shift, 0, 0)) for v in out]


def build_all():
    global COL, ORIGIN
    root = bpy.data.collections.get("Warehouses")
    if root:
        for c in [root] + list(root.children_recursive):
            for o in list(c.objects):
                bpy.data.objects.remove(o, do_unlink=True)
        for c in list(root.children_recursive):
            bpy.data.collections.remove(c)
        bpy.data.collections.remove(root)
    for name, kind in (("Cube", "MESH"), ("Light", "LIGHT"), ("Camera", "CAMERA")):
        o = bpy.data.objects.get(name)
        if o and o.type == kind:
            bpy.data.objects.remove(o, do_unlink=True)
    materials()
    root = bpy.data.collections.new("Warehouses")
    bpy.context.scene.collection.children.link(root)
    report = {}
    for lv, at in zip(LEVELS, lineup()):
        COL = bpy.data.collections.new(f"Level {lv['id']}")
        root.children.link(COL)
        COL["origin"] = list(at)
        ORIGIN = at
        report[lv["id"]] = building(lv)
    return report


# ───────────────────────────────────────────────────────────── scéna a render
def scene():
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    col = bpy.data.collections.get("Yard") or bpy.data.collections.new("Yard")
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    world = sc.world or bpy.data.worlds.new("Warehouse world")
    sc.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*linear("#A9C6E0"), 1)
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

    def slab(name, size, at, m):
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
    slab("Tráva", (900, 500, 0.2), (0, 60, -0.12), mat("Yard grass", "#6E9A52"))
    for lv, at in zip(LEVELS, lineup()):
        extra = 14 if lv["id"] == 4 else 0
        slab(f"Plocha {lv['id']}", (lv["W"] + 16 + extra, lv["D"] + 34, 0.1), (at.x - extra / 2, lv["D"] / 2 - 8, -0.04), mat("Yard concrete", "#B9B5AD"))
    slab("Silnice", (900, 22, 0.12), (0, -36, 0.0), mat("Yard road", "#3E4044"))
    sun = bpy.data.objects.new("Slunce", bpy.data.lights.new("Slunce", "SUN"))
    col.objects.link(sun)
    sun.data.energy, sun.data.angle = 3.4, math.radians(6)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    cams = [("Kamera řada", (28, 40, 14), (0.12, -1.0, 0.42), 430, 30)]
    for lv, at in zip(LEVELS, lineup()):
        reach = max(lv["W"], lv["D"]) * 1.55 + 22
        cams.append((f"Kamera level {lv['id']}", (at.x, lv["D"] * 0.42, lv["H"] * 0.55), (0.75, -1.0, 0.55), reach, 40))
    for name, target, direction, distance, lens in cams:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        col.objects.link(cam)
        cam.location = Vector(target) + Vector(direction).normalized() * distance
        cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        cam.data.clip_end = 3000
    sc.camera = bpy.data.objects["Kamera řada"]
    sc.render.resolution_x, sc.render.resolution_y = 1800, 760
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
    sc.render.resolution_x, sc.render.resolution_y = 2400, 1000
    sc.camera = bpy.data.objects["Kamera řada"]
    sc.render.filepath = os.path.join(folder, "levels.png")
    bpy.ops.render.render(write_still=True)
    sc.render.resolution_x, sc.render.resolution_y = 1000, 700
    for lv in LEVELS:
        sc.camera = bpy.data.objects[f"Kamera level {lv['id']}"]
        sc.render.filepath = os.path.join(folder, f"level-{lv['id']}.png")
        bpy.ops.render.render(write_still=True)
    sc.camera = bpy.data.objects["Kamera řada"]


# ───────────────────────────────────────────────────────────── export do hry
def split_by_finish(me, matrix, out, group, fallback):
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
    names = [m["finish"] if m else fallback for m in me.materials]
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
        out.setdefault((group, names[k]), []).append(piece)
    bm.free()


def level_marks(lv):
    """8.2: a level's markers from its origin (Blender's axes): the building's corner (W / 2 to the right, D in, H up),
    the door's corner (half its width, its height) and the roof's top over the door."""
    W, D, H = lv["W"], lv["D"], lv["H"]
    dw, dh = lv["door"]
    top = H if lv["roof"] == "shed" else H + lv["rise"]
    return {"box": Vector((-W / 2, D, H)), "door": Vector((-dw / 2, 0, dh)), "top": Vector((0, 0, top))}


def game(v, origin):
    """Blender → the game's axes, from a level's origin (x right = here -x, y up = here z, z back = here y)."""
    d = v - origin
    return Vector((-d.x, d.z, d.y))


def bounds(points):
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return [round((a + b) / 2, 4) for a, b in zip(lo, hi)], [round(b - a, 4) for a, b in zip(lo, hi)]


def export_game(folder, report, budget=10000):
    """ZDCWarehouseArt.fbx: "lvl<N>_<finish>" pieces (past `budget` triangles "lvl<N>b_<finish>" …), a marker
    "mark_lvl<N>" at each level's origin (the roller door's middle on the ground) and mark_o / mark_x / mark_y / mark_z.
    8.2 (server/WarehouseMesh.luau dresses the game's warehouse with a level): each level's "mark_lvl<N>_box" (W / 2 to
    the right, H up, D in: the building it is), "mark_lvl<N>_door" (the door's corner: its half width, its height) and
    "mark_lvl<N>_top" (the roof's top over the door), and "collide_lvl<N>_<k>": a box for each thing outside its walls
    that one bumps into (the game makes an unseen solid block of it).
    The manifest: each level's size, door, stands, the boxes that collide (its walls; 8.2: "solids", its props'),
    its markers (8.2: "marks") and the pieces (game axes, from the level's origin)."""
    os.makedirs(folder, exist_ok=True)
    temp = bpy.data.collections.new("Warehouse_Export")
    bpy.context.scene.collection.children.link(temp)
    dg = bpy.context.evaluated_depsgraph_get()
    pieces, manifest = {}, {"levels": {}, "pieces": {}}
    origins = {}
    for lv in LEVELS:
        col = bpy.data.collections[f"Level {lv['id']}"]
        origin = Vector(col["origin"])
        origins[lv["id"]] = origin
        lo, hi = [1e9] * 3, [-1e9] * 3
        details = []
        for o in col.objects:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            if not me.polygons:
                continue
            pts = [game(o.matrix_world @ v.co, origin) for v in me.vertices]
            for g in pts:
                lo = [min(a, b) for a, b in zip(lo, g)]
                hi = [max(a, b) for a, b in zip(hi, g)]
            centre, size = bounds(pts)
            details.append({"name": o.name, "finish": o.material_slots[0].material["finish"], "center": centre, "size": size})
            split_by_finish(me, o.matrix_world.copy(), pieces, lv["id"], o.material_slots[0].material["finish"])
        walls, props = report[lv["id"]]

        def boxes_of(spans):
            out = []
            for x0, x1, y0, y1, z0, z1 in spans:
                a, b = game(origin + Vector((x0, y0, z0)), origin), game(origin + Vector((x1, y1, z1)), origin)
                out.append({"center": [round((p + q) / 2, 4) for p, q in zip(a, b)], "size": [round(abs(p - q), 4) for p, q in zip(a, b)]})
            return out
        manifest["levels"][str(lv["id"])] = {
            "name": lv["name"], "size": [lv["W"], lv["H"], lv["D"]], "door": list(lv["door"]), "roof": lv["roof"],
            "stands": lv["stands"], "bounds": {"min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi]},
            "collide": boxes_of(walls), "solids": boxes_of(props), "details": details, "floorTop": FLOOR,
            "marks": {k: [round(-v.x, 4), round(v.z, 4), round(v.y, 4)] for k, v in level_marks(lv).items()},
        }
    made = []
    for (lid, finish), meshes in sorted(pieces.items()):
        groups, tris = [[]], 0
        for piece in meshes:
            t = sum(len(p.vertices) - 2 for p in piece.polygons)
            if groups[-1] and tris + t > budget:
                groups.append([])
                tris = 0
            groups[-1].append(piece)
            tris += t
        for g, group in enumerate(groups):
            name = f"lvl{lid}{'' if g == 0 else chr(ord('a') + g)}_{finish}"
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
            centre, size = bounds([game(v.co, origins[lid]) for v in me.vertices])
            manifest["pieces"][name] = {"level": lid, "center": centre, "size": size, "triangles": sum(len(p.vertices) - 2 for p in me.polygons)}
    marks = [("mark_o", Vector((0, 0, 0))), ("mark_x", Vector((-10, 0, 0))), ("mark_y", Vector((0, 0, 10))), ("mark_z", Vector((0, 10, 0)))]
    marks += [(f"mark_lvl{lid}", at) for lid, at in origins.items()]
    for lv in LEVELS:  # 8.2: its building, door and roof top; its props' boxes
        marks += [(f"mark_lvl{lv['id']}_{k}", origins[lv["id"]] + v) for k, v in level_marks(lv).items()]
    for lv in LEVELS:
        for k, (x0, x1, y0, y1, z0, z1) in enumerate(report[lv["id"]][1], 1):
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=Vector((x1 - x0, y1 - y0, z1 - z0)), verts=bm.verts)
            bmesh.ops.translate(bm, vec=origins[lv["id"]] + Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)), verts=bm.verts)
            name = f"collide_lvl{lv['id']}_{k}"
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(M["dark"])
            o = bpy.data.objects.new(name, me)
            temp.objects.link(o)
            made.append(o)
    for name, at in marks:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.3)
        bmesh.ops.translate(bm, vec=at, verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(M["dark"])
        o = bpy.data.objects.new(name, me)
        temp.objects.link(o)
        made.append(o)
    for o in bpy.context.scene.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.fbx(filepath=os.path.join(folder, "ZDCWarehouseArt.fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="OFF", use_mesh_modifiers=True)
    for lid, at in origins.items():
        manifest["levels"][str(lid)]["origin"] = [round(-at.x, 4), 0, 0]  # (its marker in the export's game axes)
    with open(os.path.join(folder, "ZDCWarehouseArt.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    for o in list(temp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(temp)
    return manifest


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag):
        return argv[argv.index(flag) + 1] if flag in argv else None

    report = build_all()
    scene()
    source = globals().get("__file__", "")
    if os.path.isfile(source) and "warehouse.py" not in bpy.data.texts:
        bpy.data.texts.new("warehouse.py").write(open(source, encoding="utf-8").read())
    if arg("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--save")))
    if arg("--render"):
        render_all(arg("--render"), int(arg("--samples") or 64))
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        manifest = export_game(folder, report)
        for lid, lv in sorted(manifest["levels"].items()):
            tris = sum(p["triangles"] for p in manifest["pieces"].values() if p["level"] == int(lid))
            print(f"  level {lid} {lv['name']:20s} {lv['size']} door {lv['door']}: {tris} triangles, {len(lv['collide'])} walls, {len(lv['solids'])} props")
        print(f"ZDCWarehouseArt: {len(manifest['pieces'])} pieces, {sum(p['triangles'] for p in manifest['pieces'].values())} triangles")


main()
