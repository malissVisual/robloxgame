"""Zombie Delivery: nábytek pro stěhování (7.0 MOVES) v Blenderu.

Spuštění v Blenderu: záložka Scripting → Open → furniture.py → Run Script (▶, nebo Alt+P). Skript postaví všech 36 kusů
nábytku ze hry (shared/FurnitureLooks.luau) v mřížce do kolekce "Furniture" a vedle zařízený obývák (scéna "Room").
Každý kus má přesně rozměry ze hry (Root box): 1 jednotka = 1 stud, předek míří na -Y, spodek kusu je na zemi.

Bez Blenderu, jen s modulem bpy (pip install bpy):
    python furniture.py -- --save furniture.blend --render složka --export složka
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

# ───────────────────────────────────────────────────────────── NASTAVENÍ
EXPORT = False   # True = uloží ZDCFurnitureArt.fbx pro hru do složky "roblox" vedle .blend souboru
CELL = 10.0      # rozestup kusů v mřížce (studs)
COLUMNS = 6

# Katalog ze hry (shared/FurnitureLooks.luau Items): id, název, šířka X, výška Y, hloubka Z. tools/furniture/mesh-check.py
# hlídá, že sedí se hrou.
ITEMS = [
    ("sofa", "Sofa", 7.2, 3.4, 3.2), ("armchair", "Armchair", 3.4, 3.4, 3.2), ("tv", "Old TV", 3.4, 3.9, 2.4),
    ("coffee_table", "Coffee Table", 4.2, 1.85, 2.4), ("floor_lamp", "Floor Lamp", 1.4, 5.2, 1.4),
    ("bookshelf", "Bookshelf", 4.2, 6.6, 1.6), ("painting", "Painting", 3.0, 2.4, 0.4), ("plant", "Potted Plant", 1.8, 3.6, 1.8),
    ("piano", "Upright Piano", 5.2, 4.6, 2.2), ("grandfather_clock", "Grandfather Clock", 2.0, 7.2, 1.4),
    ("record_player", "Old Record Player", 2.3, 4.8, 2.0), ("fridge", "Fridge", 3.0, 6.4, 2.8), ("microwave", "Microwave", 2.2, 1.3, 1.5),
    ("dining_table", "Dining Table", 6.0, 3.3, 3.8), ("dining_chair", "Chair", 1.8, 3.8, 1.8), ("dishes_box", "Box of Dishes", 2.0, 2.0, 2.0),
    ("radio", "Kitchen Radio", 1.6, 1.1, 0.8), ("bed", "Double Bed", 5.4, 3.6, 7.4), ("wardrobe", "Wardrobe", 4.4, 7.0, 2.2),
    ("nightstand", "Nightstand", 1.8, 2.4, 1.6), ("dresser", "Dresser", 3.8, 3.2, 1.8), ("mirror", "Standing Mirror", 1.8, 5.0, 1.0),
    ("photo_album", "Family Photos", 1.8, 1.6, 1.4), ("kids_bed", "Kid's Bed", 3.6, 3.0, 6.2), ("rocking_horse", "Rocking Horse", 3.8, 3.2, 1.4),
    ("toy_box", "Toy Chest", 3.0, 2.4, 1.8), ("desk", "Kid's Desk", 3.6, 3.2, 2.0), ("guitar", "Guitar", 1.5, 4.0, 0.8),
    ("washing_machine", "Washing Machine", 2.8, 3.4, 2.8), ("laundry_basket", "Laundry Basket", 1.8, 1.6, 1.4),
    ("coat_rack", "Coat Rack", 1.5, 5.6, 1.5), ("shoe_cabinet", "Shoe Cabinet", 3.2, 2.9, 1.4), ("bicycle", "Bicycle", 5.4, 3.1, 1.2),
    ("toolbox", "Toolbox", 2.0, 1.25, 1.0), ("lawn_mower", "Lawn Mower", 2.2, 3.2, 4.2), ("box", "Moving Box", 2.0, 1.8, 2.0),
]

# Povrchy: jméno → (barva #RRGGBB, drsnost, kov, záře). Hra (server/FurnitureMesh.luau) dá každému povrchu barvu
# a materiál; fabric, fabric2, wood, wood2, paint, accent a appliance mění barvu podle varianty kusu (jako ve hře).
FINISHES = {
    "fabric": ("#367C80", 0.9, 0, 0), "fabric2": ("#465C8C", 0.9, 0, 0), "wood": ("#B08052", 0.55, 0, 0),
    "wood2": ("#7A5236", 0.5, 0, 0), "paint": ("#78AAD2", 0.45, 0, 0), "accent": ("#ECC446", 0.45, 0, 0),
    "appliance": ("#EEEEEA", 0.3, 0, 0), "cream": ("#F4EEDE", 0.8, 0, 0), "brass": ("#CCA448", 0.3, 1, 0),
    "steel": ("#AAB0B4", 0.35, 1, 0), "chrome": ("#D7DBDF", 0.15, 1, 0), "dark": ("#242428", 0.6, 0, 0),
    "white": ("#F6F4EE", 0.5, 0, 0), "glass": ("#28343E", 0.05, 0, 0), "mirror": ("#C4D6E0", 0.02, 1, 0),
    "leather": ("#6E3C28", 0.6, 0, 0), "card": ("#C49E6C", 0.9, 0, 0), "tape": ("#DEC8A0", 0.5, 0, 0),
    "rubber": ("#18181A", 0.9, 0, 0), "ceramic": ("#F6F4EE", 0.15, 0, 0), "terracotta": ("#B8603E", 0.8, 0, 0),
    "soil": ("#463224", 1.0, 0, 0), "leaf": ("#40824A", 0.6, 0, 0), "leaf2": ("#62A452", 0.6, 0, 0),
    "gold": ("#C8A046", 0.35, 1, 0), "sky": ("#8CBEE6", 0.7, 0, 0), "grass": ("#6EA05A", 0.8, 0, 0),
    "sun": ("#FAD26E", 0.6, 0, 0), "book1": ("#AA3430", 0.7, 0, 0), "book2": ("#34568C", 0.7, 0, 0),
    "book3": ("#3C784C", 0.7, 0, 0), "book4": ("#D6AA3C", 0.7, 0, 0), "glow": ("#FFECC8", 0.5, 0, 3.0),
    "red": ("#C8322E", 0.45, 0, 0), "wicker": ("#BE9664", 0.9, 0, 0), "black": ("#141416", 0.4, 0, 0),
}

M = {}
CUR = Vector()   # the origin of the piece being built (the bottom middle of its box)
COL = None       # its collection


def linear(hexcode):
    h = hexcode.lstrip("#")
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))


def materials():
    for name, (hexcode, rough, metal, emit) in FINISHES.items():
        m = bpy.data.materials.get("F " + name) or bpy.data.materials.new("F " + name)
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
        if name == "glass":
            p.inputs["Alpha"].default_value = 0.75
        glow = p.inputs.get("Emission Color") or p.inputs.get("Emission")
        glow.default_value = rgba if emit else (0, 0, 0, 1)
        p.inputs["Emission Strength"].default_value = emit
        m["finish"] = name
        M[name] = m


# ───────────────────────────────────────────────────────────── stavební kameny (souřadnice od spodku středu kusu)
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


def box(name, size, at, finish, r=0.04, rot=None, seg=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix())
    return bevel(o, min(r, min(size) * 0.45), seg)


def cushion(name, size, at, finish, rot=None):
    """A soft cushion: a box rounded hard all round."""
    return box(name, size, at, finish, r=min(size) * 0.32, rot=rot, seg=4)


def cyl(name, r, h, at, finish, axis="Z", seg=24, r2=None, edge=0.02, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    sharpen(bm)
    o = obj(name, bm, finish)
    turn = {"Z": Matrix(), "X": euler(ry=math.pi / 2), "Y": euler(rx=math.pi / 2)}[axis]
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix()) @ turn
    return bevel(o, edge, 2)


def tube(name, a, b, r, finish, seg=12):
    a, b = CUR + Vector(a), CUR + Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=(b - a).length)
    sharpen(bm)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat("Z", "Y").to_matrix().to_4x4()
    return o


def ball(name, r, at, finish, scale=(1, 1, 1), rot=None, seg=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix())
    return o


def lathe(name, profile, at, finish, seg=32, scale=(1, 1), rot=None, closed=True):
    """A turned shape: `profile` (radius, height) points spun round Z (a pot, a lamp shade, a table leg)."""
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in profile]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    if closed:
        es.append(bm.edges.new((vs[-1], vs[0])))
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=seg, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.scale(bm, vec=Vector((scale[0], scale[1], 1)), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharpen(bm, 50)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix())
    return o


def torus(name, R, r, at, finish, axis="Z", seg=32, ring_seg=10, arc=2 * math.pi, rot=None):
    """A ring (a tyre, a rocker's arc: `arc` < 2π leaves an open arc)."""
    bm = bmesh.new()
    rim = [bm.verts.new((R + r * math.cos(a), 0, r * math.sin(a))) for a in (2 * math.pi * i / ring_seg for i in range(ring_seg))]
    es = [bm.edges.new((rim[i], rim[(i + 1) % ring_seg])) for i in range(ring_seg)]
    full = abs(arc - 2 * math.pi) < 1e-6
    res = bmesh.ops.spin(bm, geom=rim + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=arc, steps=seg, use_merge=full)
    if not full:
        bmesh.ops.contextual_create(bm, geom=[e for e in bm.edges if e.is_boundary and all(v in rim for v in e.verts)])
        last = [e for e in res["geom_last"] if isinstance(e, bmesh.types.BMEdge)]
        bmesh.ops.contextual_create(bm, geom=last)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj(name, bm, finish)
    turn = {"Z": Matrix(), "X": euler(ry=math.pi / 2), "Y": euler(rx=math.pi / 2)}[axis]
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix()) @ turn
    return o


def legs4(name, x, y, h, r, finish, taper=0.75, z0=0.0):
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(name, r, h, (sx * x, sy * y, z0 + h / 2), finish, r2=r * taper, seg=12, edge=0.01, rot=None)


def books(name, x0, x1, y, z, depth, height, n_seed=0):
    """A row of book spines from x0 to x1 standing on z, their fronts at y (the front of the shelf)."""
    widths = [0.18, 0.24, 0.14, 0.3, 0.2, 0.16, 0.26, 0.22]
    x, k = x0, n_seed
    while x < x1 - 0.12:
        w = min(widths[k % len(widths)], x1 - x)
        hgt = height * (0.72 + 0.28 * ((k * 37) % 10) / 10)
        lean = euler(ry=-0.18) if k % 9 == 7 and x + w + 0.3 < x1 else None
        box(name, (w - 0.02, depth, hgt), (x + w / 2, y + depth / 2, z + hgt / 2), f"book{k % 4 + 1}", r=0.015, rot=lean)
        x += w + (0.12 if lean else 0)
        k += 1


# ───────────────────────────────────────────────────────────── kusy nábytku
def sofa(W, H, D, armchair=False):
    arm, back_d = 0.62, 0.62
    legs4("Leg", W / 2 - 0.35, D / 2 - 0.35, 0.35, 0.09, "wood2")
    box("Frame", (W - 0.3, D - 0.3, 0.85), (0, 0.05, 0.35 + 0.425), "fabric", r=0.12, seg=3)
    seats = 1 if armchair else 3
    inner = W - 2 * arm
    for i in range(seats):
        x = -inner / 2 + inner * (i + 0.5) / seats
        cushion("Seat cushion", (inner / seats - 0.06, D - back_d - 0.2, 0.55), (x, -back_d / 2 + 0.05 - 0.05, 1.2 + 0.27), "fabric")
        cushion("Back cushion", (inner / seats - 0.08, back_d, 1.7), (x, D / 2 - back_d / 2 - 0.1, 2.15), "fabric",
                rot=euler(rx=-0.12))
    for s in (-1, 1):
        cushion("Arm", (arm, D - 0.1, 1.95), (s * (W / 2 - arm / 2), 0, 0.35 + 0.98), "fabric")
    box("Back", (W - 0.1, 0.35, 2.95), (0, D / 2 - 0.2, 0.35 + 2.95 / 2), "fabric", r=0.14, seg=3)
    if not armchair:
        for s in (-1, 1):
            cushion("Pillow", (0.95, 0.35, 0.95), (s * (inner / 2 - 0.65), D / 2 - back_d - 0.15, 2.3), "fabric2",
                    rot=euler(rx=-0.25, ry=s * 0.25))
    else:
        cushion("Pillow", (0.95, 0.35, 0.85), (0, D / 2 - back_d - 0.12, 2.15), "fabric2", rot=euler(rx=-0.25))


def tv(W, H, D):
    for sx in (-1, 1):
        for sy in (-1, 1):
            tube("Leg", (sx * 1.05, sy * 0.65, 0.9), (sx * 1.33, sy * 0.93, 0.04), 0.06, "wood2", 8)
    box("Cabinet", (W - 0.05, D - 0.3, 2.55), (0, 0.1, 0.9 + 1.275), "wood", r=0.18, seg=3)
    f = -(D - 0.3) / 2 + 0.1
    box("Bezel", (2.35, 0.1, 2.0), (-0.42, f - 0.03, 2.2), "dark", r=0.25, seg=4)
    box("Screen", (2.1, 0.12, 1.72), (-0.42, f - 0.06, 2.2), "glass", r=0.28, seg=4)
    box("Panel", (0.62, 0.08, 2.0), (1.22, f - 0.03, 2.2), "dark", r=0.05)
    for z in (2.85, 2.35):
        cyl("Knob", 0.15, 0.12, (1.22, f - 0.11, z), "chrome", axis="Y", seg=16)
    for z in (1.7, 1.5):
        box("Grille", (0.46, 0.04, 0.06), (1.22, f - 0.08, z), "brass", r=0.01)
    ball("Antenna base", 0.18, (0, 0.2, 3.45), "dark", scale=(1, 1, 0.6))
    for s in (-1, 1):
        tube("Antenna", (0, 0.2, 3.5), (s * 0.55, 0.25, H - 0.03), 0.025, "chrome", 6)


def coffee_table(W, H, D):
    top = H - 0.1
    box("Top", (W, D, 0.16), (0, 0, top - 0.08), "wood", r=0.06, seg=3)
    box("Apron", (W - 0.4, D - 0.4, 0.22), (0, 0, top - 0.27), "wood2", r=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            lathe("Leg", [(0.001, 0), (0.07, 0), (0.1, 0.25), (0.12, top - 0.5), (0.08, top - 0.16), (0.001, top - 0.16)],
                  (sx * (W / 2 - 0.3), sy * (D / 2 - 0.3), 0), "wood2", seg=12)
    box("Shelf", (W - 0.6, D - 0.6, 0.08), (0, 0, 0.4), "wood", r=0.02)
    box("Magazine", (1.0, 0.75, 0.04), (-0.9, 0.1, top + 0.02), "book2", r=0.01, rot=euler(rz=0.2))
    box("Magazine", (0.9, 0.7, 0.03), (-0.85, 0.12, top + 0.055), "book4", r=0.01, rot=euler(rz=-0.15))
    cyl("Coaster", 0.2, 0.03, (1.1, -0.2, top + 0.015), "wood2", seg=16, edge=0)


def floor_lamp(W, H, D):
    lathe("Base", [(0.001, 0), (0.62, 0), (0.6, 0.08), (0.3, 0.16), (0.08, 0.2), (0.001, 0.2)], (0, 0, 0), "brass", seg=32)
    cyl("Pole", 0.045, 3.9, (0, 0, 0.2 + 1.95), "brass", seg=10, edge=0)
    lathe("Shade", [(0.42, 4.05), (0.68, 3.95), (0.69, 3.95), (0.68, 3.97), (0.43, 5.15), (0.41, 5.15)], (0, 0, 0), "cream", seg=32, closed=False)
    lathe("Shade inside", [(0.66, 3.97), (0.41, 5.12)], (0, 0, 0), "glow", seg=32, closed=False)
    ball("Bulb", 0.16, (0, 0, 4.3), "glow")
    tube("Pull chain", (0.2, 0, 4.25), (0.2, 0, 3.7), 0.012, "brass", 4)


def bookshelf(W, H, D):
    t = 0.14
    for s in (-1, 1):
        box("Side", (t, D, H - 0.05), (s * (W / 2 - t / 2), 0, (H - 0.05) / 2), "wood", r=0.03)
    box("Top", (W, D, t + 0.04), (0, 0, H - (t + 0.04) / 2), "wood", r=0.04)
    box("Plinth", (W - 2 * t, D - 0.1, 0.4), (0, -0.04, 0.2), "wood2", r=0.02)
    box("Back", (W - 2 * t, 0.06, H - 0.3), (0, D / 2 - 0.05, H / 2), "wood2", r=0)
    levels = [0.4, 1.95, 3.45, 4.95]
    for i, z in enumerate(levels):
        box("Shelf", (W - 2 * t, D - 0.08, 0.1), (0, -0.02, z), "wood", r=0.02)
        if i < 3:
            books("Book", -W / 2 + t + 0.05, W / 2 - t - (1.0 if i == 1 else 0.05), -D / 2 + 0.15, z + 0.05, D - 0.35, 1.25, i * 5)
    lathe("Vase", [(0.001, 0), (0.2, 0), (0.28, 0.35), (0.12, 0.8), (0.16, 0.95), (0.001, 0.92)], (W / 2 - t - 0.5, -0.05, 2.0), "terracotta", seg=20)
    books("Book", -W / 2 + t + 0.1, -W / 2 + t + 1.4, -D / 2 + 0.15, 5.0, D - 0.35, 1.1, 11)
    lathe("Pot", [(0.001, 0), (0.25, 0), (0.3, 0.45), (0.001, 0.45)], (W / 2 - t - 0.6, 0, 5.0), "white", seg=16)
    for k in range(6):
        a = k * 1.05
        ball("Leaf", 0.32, (W / 2 - t - 0.6 + math.cos(a) * 0.25, math.sin(a) * 0.18, 5.65 + (k % 2) * 0.2), "leaf2" if k % 2 else "leaf",
             scale=(1, 0.45, 0.35), rot=euler(ry=0.6 * math.cos(a), rz=a))


def painting(W, H, D):
    f = 0.24
    box("Backing", (W - 0.3, 0.08, H - 0.3), (0, 0.12, H / 2), "wood2", r=0)
    for s in (-1, 1):
        box("Frame", (f, 0.3, H), (s * (W / 2 - f / 2), -0.02, H / 2), "gold", r=0.06, seg=3)
        box("Frame", (W, 0.3, f), (0, -0.02, H / 2 + s * (H / 2 - f / 2)), "gold", r=0.06, seg=3)
    iw, ih = W - 2 * f, H - 2 * f
    box("Sky", (iw, 0.05, ih), (0, 0.07, H / 2), "sky", r=0)
    ball("Sun", 0.28, (0.7, 0.03, H / 2 + 0.45), "sun", scale=(1, 0.1, 1))
    for x, r, hgt in ((-0.55, 0.7, 0.7), (0.6, 0.62, 0.5)):
        lathe("Hill", [(0.001, 0), (1, 0), (0.85, 0.35), (0.55, 0.62), (0.001, 0.72)], (x, 0.04, f), "grass", seg=24, scale=(r, 0.06),
              rot=Matrix.Diagonal((1, 1, hgt / 0.72, 1)))
    cyl("Trunk", 0.05, 0.5, (-0.8, 0.0, f + 0.75), "wood2", seg=8, edge=0)
    ball("Crown", 0.3, (-0.8, -0.0, f + 1.1), "leaf", scale=(1, 0.12, 1.1))


def plant(W, H, D):
    lathe("Pot", [(0.001, 0), (0.5, 0), (0.62, 0.95), (0.7, 1.0), (0.7, 1.15), (0.62, 1.15), (0.58, 1.05), (0.001, 1.05)], (0, 0, 0), "terracotta", seg=32)
    cyl("Soil", 0.56, 0.06, (0, 0, 1.07), "soil", seg=24, edge=0)
    for k in range(9):
        a = k * 2 * math.pi / 9 + (0.3 if k % 2 else 0)
        reach = 0.3 + 0.1 * (k % 3)
        top = 2.0 + 0.55 * ((k * 5) % 4) / 3
        tip = Vector((math.cos(a) * reach, math.sin(a) * reach, top))
        tube("Stem", (0, 0, 1.05), tuple(tip * 0.92 + Vector((0, 0, 0.05))), 0.03, "leaf", 6)
        ball("Leaf", 0.42, tuple(tip), "leaf2" if k % 3 else "leaf", scale=(1, 0.42, 0.16),
             rot=Matrix.Rotation(a, 4, "Z") @ euler(ry=-0.5))
    ball("Leaf", 0.4, (0, 0, H - 0.4), "leaf2", scale=(0.45, 0.2, 1.0))


def piano(W, H, D):
    body_d = 1.35
    by = D / 2 - body_d / 2
    box("Body", (W - 0.12, body_d, H - 0.1), (0, by, (H - 0.1) / 2), "wood2", r=0.06, seg=3)
    box("Lid", (W - 0.02, body_d + 0.04, 0.12), (0, by - 0.02, H - 0.06), "wood2", r=0.04)
    box("Fall board", (W - 0.5, 0.5, 0.35), (0, by - body_d / 2 - 0.15, 2.85), "wood2", r=0.06, rot=euler(rx=0.35))
    box("Key bed", (W - 0.3, 0.9, 0.3), (0, -D / 2 + 0.45, 2.35), "wood2", r=0.04)
    box("Keys", (W - 0.6, 0.7, 0.1), (0, -D / 2 + 0.4, 2.55), "white", r=0.01)
    n = 22
    for i in range(n):
        if i % 7 in (2, 6):
            continue
        x = -(W - 0.6) / 2 + (W - 0.6) * (i + 1) / (n + 1)
        box("Black key", (0.08, 0.38, 0.1), (x, -D / 2 + 0.55, 2.64), "black", r=0.01)
    box("Music desk", (2.0, 0.08, 0.7), (0, by - body_d / 2 - 0.08, 3.4), "wood2", r=0.02, rot=euler(rx=-0.25))
    box("Sheet", (0.8, 0.02, 0.55), (-0.3, by - body_d / 2 - 0.14, 3.42), "cream", r=0, rot=euler(rx=-0.25))
    for s in (-1, 1):
        box("Cheek", (0.2, D - 0.1, 2.55), (s * (W / 2 - 0.1), 0.05, 1.27), "wood2", r=0.06, seg=3)
        lathe("Toe", [(0.001, 0), (0.12, 0), (0.12, 0.12), (0.001, 0.12)], (s * (W / 2 - 0.11), -D / 2 + 0.18, 0), "brass", seg=10)
        cyl("Candle holder", 0.08, 0.05, (s * 1.45, by - body_d / 2 - 0.05, 3.1), "brass", seg=10)
    for x in (-0.25, 0, 0.25):
        box("Pedal", (0.12, 0.35, 0.06), (x, by - body_d / 2 - 0.15, 0.3), "brass", r=0.02)
    box("Lower panel", (W - 0.6, 0.06, 1.8), (0, by - body_d / 2 - 0.02, 1.2), "wood", r=0.02)


def grandfather_clock(W, H, D):
    box("Plinth", (W, D, 0.9), (0, 0, 0.45), "wood2", r=0.06)
    box("Waist", (W - 0.35, D - 0.25, 4.0), (0, 0.04, 0.9 + 2.0), "wood", r=0.05)
    box("Door glass", (W - 0.85, 0.05, 3.2), (0, -(D - 0.25) / 2 + 0.03, 3.0), "glass", r=0.02)
    tube("Pendulum rod", (0, -0.25, 4.6), (0, -0.25, 2.2), 0.025, "brass", 6)
    cyl("Pendulum", 0.3, 0.05, (0, -0.25, 2.1), "brass", axis="Y", seg=24)
    box("Waist band", (W - 0.15, D - 0.1, 0.2), (0, 0, 4.95), "wood2", r=0.04)
    hd = D - 0.2
    fy = -hd / 2
    box("Hood", (W - 0.05, hd, 1.6), (0, 0, 5.05 + 0.8), "wood", r=0.06)
    cyl("Face", 0.6, 0.06, (0, fy - 0.01, 5.85), "cream", axis="Y", seg=40)
    torus("Bezel", 0.62, 0.045, (0, fy - 0.03, 5.85), "brass", axis="Y", seg=40, ring_seg=8)
    for k in range(12):
        a = k * math.pi / 6
        box("Mark", (0.05, 0.02, 0.12), (math.sin(a) * 0.48, fy - 0.045, 5.85 + math.cos(a) * 0.48), "black", r=0, rot=euler(ry=a))
    box("Hand", (0.05, 0.02, 0.42), (0.1, fy - 0.055, 6.02), "black", r=0, rot=euler(ry=0.5))
    box("Hand", (0.05, 0.02, 0.3), (-0.08, fy - 0.055, 5.76), "black", r=0, rot=euler(ry=2.3))
    box("Crown", (W, D - 0.1, 0.12), (0, 0, 6.71), "wood2", r=0.04)
    cyl("Arch", 0.55, hd - 0.1, (0, 0, 6.62), "wood2", axis="Y", seg=24, edge=0.03)
    for s in (-1, 1):
        lathe("Finial", [(0.001, 0), (0.1, 0), (0.06, 0.12), (0.001, 0.12)], (s * (W / 2 - 0.15), 0, 6.77), "brass", seg=10)
        cyl("Column", 0.08, 1.5, (s * (W / 2 - 0.15), fy + 0.05, 5.85), "wood2", seg=10)


def record_player(W, H, D):
    cab = 2.6
    box("Cabinet", (W, D, cab - 0.2), (0, 0, 0.2 + (cab - 0.2) / 2), "wood2", r=0.08, seg=3)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl("Foot", 0.12, 0.2, (sx * (W / 2 - 0.25), sy * (D / 2 - 0.25), 0.1), "brass", seg=10)
    box("Front", (W - 0.4, 0.05, 1.5), (0, -D / 2 + 0.02, 1.2), "fabric2", r=0.05)
    box("Top", (W, D, 0.12), (0, 0, cab), "wood", r=0.04)
    cyl("Platter", 0.82, 0.08, (-0.1, -0.15, cab + 0.1), "dark", seg=40)
    cyl("Record", 0.78, 0.03, (-0.1, -0.15, cab + 0.15), "black", seg=40)
    cyl("Label", 0.25, 0.035, (-0.1, -0.15, cab + 0.16), "red", seg=24, edge=0)
    tube("Tone arm", (0.85, 0.65, cab + 0.25), (0.15, -0.05, cab + 0.22), 0.03, "chrome", 6)
    cyl("Arm base", 0.12, 0.2, (0.85, 0.65, cab + 0.1), "chrome", seg=12)
    tube("Horn neck", (0.85, 0.65, cab + 0.25), (0.25, 0.4, 3.0), 0.07, "brass", 10)
    k = 0.78
    horn = lathe("Horn", [(0.08, 0.0), (0.12 * k, 0.3), (0.22 * k, 0.65), (0.42 * k, 0.95), (0.75 * k, 1.18), (0.92 * k, 1.28),
                          (0.9 * k, 1.3), (0.73 * k, 1.2), (0.4 * k, 0.97), (0.2 * k, 0.67), (0.1 * k, 0.32), (0.06, 0.0)],
                 (0, 0, 0), "brass", seg=32)
    horn.matrix_world = Matrix.Translation(CUR + Vector((0.2, 0.35, 3.0))) @ euler(rx=0.55, rz=0.2)


def fridge(W, H, D):
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl("Foot", 0.1, 0.15, (sx * (W / 2 - 0.3), sy * (D / 2 - 0.3), 0.075), "dark", seg=10)
    box("Body", (W, D - 0.3, H - 0.15), (0, 0.15, 0.15 + (H - 0.15) / 2), "appliance", r=0.35, seg=4)
    f = -(D - 0.3) / 2 + 0.15
    box("Freezer door", (W - 0.1, 0.12, 1.85), (0, f - 0.06, H - 0.1 - 0.95), "appliance", r=0.12, seg=3)
    box("Door", (W - 0.1, 0.12, H - 2.55), (0, f - 0.06, 0.2 + (H - 2.55) / 2 + 0.05), "appliance", r=0.12, seg=3)
    for z0, z1 in ((H - 1.6, H - 0.45), (2.3, 4.0)):
        tube("Handle", (W / 2 - 0.35, f - 0.22, z0), (W / 2 - 0.35, f - 0.22, z1), 0.06, "chrome", 10)
        for z in (z0, z1):
            tube("Handle post", (W / 2 - 0.35, f - 0.22, z), (W / 2 - 0.35, f - 0.08, z), 0.05, "chrome", 8)
    box("Badge", (0.7, 0.03, 0.18), (-0.6, f - 0.13, H - 0.45), "chrome", r=0.03)
    box("Kick plate", (W - 0.4, 0.05, 0.2), (0, f - 0.02, 0.28), "chrome", r=0.02)


def microwave(W, H, D):
    box("Body", (W, D - 0.2, H - 0.06), (0, 0.1, 0.06 + (H - 0.06) / 2), "appliance", r=0.12, seg=3)
    f = -(D - 0.2) / 2 + 0.1
    box("Door", (1.45, 0.06, H - 0.3), (-0.3, f - 0.02, H / 2 + 0.02), "dark", r=0.05)
    box("Window", (1.15, 0.04, H - 0.55), (-0.33, f - 0.045, H / 2 + 0.02), "glass", r=0.06, seg=3)
    box("Handle", (0.08, 0.1, H - 0.45), (0.38, f - 0.09, H / 2 + 0.02), "chrome", r=0.03)
    box("Panel", (0.5, 0.04, H - 0.3), (0.75, f - 0.02, H / 2 + 0.02), "dark", r=0.03)
    box("Display", (0.36, 0.03, 0.14), (0.75, f - 0.04, H - 0.32), "glow", r=0.01)
    for z in (0.75, 0.52, 0.3):
        for x in (0.65, 0.85):
            box("Button", (0.12, 0.04, 0.1), (x, f - 0.04, z), "steel", r=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl("Foot", 0.07, 0.06, (sx * (W / 2 - 0.2), sy * (D / 2 - 0.2), 0.03), "rubber", seg=8, edge=0)


def dining_table(W, H, D):
    H = H - 0.03
    box("Top", (W, D, 0.2), (0, 0, H - 0.1), "wood", r=0.08, seg=3)
    box("Apron", (W - 0.6, D - 0.6, 0.35), (0, 0, H - 0.37), "wood2", r=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            lathe("Leg", [(0.001, 0), (0.12, 0), (0.15, 0.3), (0.1, 0.6), (0.16, 1.1), (0.12, 2.0), (0.15, H - 0.55), (0.15, H - 0.2), (0.001, H - 0.2)],
                  (sx * (W / 2 - 0.45), sy * (D / 2 - 0.45), 0), "wood2", seg=16)
    box("Runner", (W - 1.5, 0.9, 0.025), (0, 0, H + 0.0125), "fabric2", r=0.005)


def dining_chair(W, H, D):
    seat_z = 1.75
    for sx in (-1, 1):
        cyl("Front leg", 0.09, seat_z, (sx * (W / 2 - 0.2), -D / 2 + 0.2, seat_z / 2), "wood", r2=0.07, seg=10)
        box("Back post", (0.16, 0.16, H - 0.05), (sx * (W / 2 - 0.2), D / 2 - 0.2, (H - 0.05) / 2), "wood", r=0.05, rot=euler(rx=-0.04))
    box("Seat", (W - 0.1, D - 0.1, 0.16), (0, 0, seat_z), "wood", r=0.05, seg=3)
    cushion("Seat pad", (W - 0.35, D - 0.45, 0.22), (0, -0.1, seat_z + 0.17), "fabric")
    box("Top rail", (W - 0.3, 0.14, 0.5), (0, D / 2 - 0.2, H - 0.35), "wood", r=0.06, seg=3)
    for x in (-0.4, 0, 0.4):
        cyl("Spindle", 0.05, H - seat_z - 0.65, (x, D / 2 - 0.2, seat_z + (H - seat_z - 0.65) / 2 + 0.08), "wood", seg=8)
    for sy in (-1, 1):
        tube("Stretcher", (-W / 2 + 0.2, sy * (D / 2 - 0.2), 0.55), (W / 2 - 0.2, sy * (D / 2 - 0.2), 0.55), 0.04, "wood", 6)


def dishes_box(W, H, D):
    box("Body", (1.85, 1.95, 1.5), (0, 0, 0.75), "card", r=0.03)
    box("Tape", (0.45, 0.02, 0.14), (0, -0.98, 1.43), "tape", r=0)  # (a short fold: the game prints FRAGILE · KITCHEN below)
    for s in (-1, 1):
        a = s * 0.12
        box("Flap", (0.04, 1.85, 0.48), (s * 0.925 + math.sin(a) * 0.24, 0, 1.5 + math.cos(a) * 0.24), "card", r=0.01, rot=euler(ry=a))
    for n in (-1, 0, 1):
        cyl("Plate", 0.5, 0.06, (n * 0.12, n * 0.3, 1.5), "ceramic" if n else "paint", axis="Y", seg=28,
            rot=euler(rz=0.12 * n))


def radio(W, H, D):
    box("Body", (W, D - 0.12, 0.9), (0, 0.06, 0.45), "accent", r=0.2, seg=4)
    f = -(D - 0.12) / 2 + 0.06
    box("Face", (W - 0.25, 0.04, 0.62), (0, f - 0.01, 0.45), "cream", r=0.08)
    cyl("Speaker", 0.27, 0.04, (-0.38, f - 0.03, 0.45), "fabric2", axis="Y", seg=24)
    torus("Speaker ring", 0.28, 0.022, (-0.38, f - 0.04, 0.45), "chrome", axis="Y", seg=24, ring_seg=6)
    box("Dial", (0.55, 0.03, 0.24), (0.36, f - 0.03, 0.56), "glow", r=0.04)
    for x in (0.2, 0.52):
        cyl("Knob", 0.08, 0.06, (x, f - 0.06, 0.28), "chrome", axis="Y", seg=12)
    for x in (-0.5, 0.5):
        tube("Handle post", (x, 0.06, 0.85), (x, 0.06, 1.04), 0.035, "chrome", 8)
    tube("Handle", (-0.53, 0.06, 1.04), (0.53, 0.06, 1.04), 0.04, "chrome", 8)


def bed(W, H, D, kids=False):
    paint = "paint" if kids else "wood"
    leg = 0.45 if not kids else 0.35
    frame_z = leg + 0.4
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Leg", (0.3, 0.3, leg), (sx * (W / 2 - 0.2), sy * (D / 2 - 0.2), leg / 2), paint, r=0.04)
    box("Frame", (W - 0.05, D - 0.3, 0.45), (0, -0.05, leg + 0.22), paint, r=0.06)
    head_h = H - 0.05
    box("Headboard", (W, 0.25, head_h - leg), (0, D / 2 - 0.125, leg + (head_h - leg) / 2), paint, r=0.1, seg=3)
    if kids:
        for s in (-1, 1):
            ball("Post top", 0.15, (s * (W / 2 - 0.15), D / 2 - 0.15, H - 0.17), "accent")
        cyl("Star", 0.35, 0.05, (0, D / 2 - 0.27, H - 0.75), "accent", axis="Y", seg=5, edge=0)
    else:
        cushion("Head pad", (W - 0.6, 0.18, head_h - frame_z - 0.6), (0, D / 2 - 0.3, frame_z + (head_h - frame_z) / 2 + 0.1), "fabric2")
    foot_h = 1.5 if not kids else 1.6
    box("Footboard", (W, 0.22, foot_h), (0, -D / 2 + 0.11, foot_h / 2), paint, r=0.08, seg=3)
    mattress_z = frame_z + 0.3
    cushion("Mattress", (W - 0.35, D - 0.6, 0.6), (0, 0.0, mattress_z), "white")
    duvet_d = D * (0.62 if not kids else 0.66)
    cushion("Duvet", (W - 0.15, duvet_d, 0.35), (0, -D / 2 + 0.32 + duvet_d / 2, mattress_z + 0.38), "fabric")
    cushion("Duvet fold", (W - 0.2, 0.55, 0.3), (0, -D / 2 + 0.32 + duvet_d - 0.1, mattress_z + 0.5), "white")
    for s in ((-1, 1) if not kids else (0,)):
        cushion("Pillow", (1.9 if not kids else 1.7, 0.95, 0.42), (s * 1.15, D / 2 - 0.95, mattress_z + 0.48), "white", rot=euler(rx=-0.25))
    if kids:
        ball("Teddy", 0.28, (0.9, D / 2 - 1.0, mattress_z + 0.65), "wicker")
        ball("Teddy head", 0.2, (0.9, D / 2 - 1.0, mattress_z + 1.0), "wicker")
    else:
        cushion("Throw", (W - 0.1, 0.9, 0.12), (0, -D / 2 + 0.9, mattress_z + 0.62), "fabric2")


def wardrobe(W, H, D):
    box("Plinth", (W - 0.2, D - 0.2, 0.35), (0, 0.05, 0.175), "wood2", r=0.03)
    box("Carcass", (W - 0.06, D - 0.45, H - 0.65), (0, 0.225, 0.35 + (H - 0.65) / 2), "wood", r=0.05)
    f = -(D - 0.45) / 2 + 0.225
    box("Crown", (W, D - 0.2, 0.3), (0, 0.1, H - 0.15), "wood2", r=0.08, seg=3)
    for s in (-1, 1):
        x = s * (W / 4)
        box("Door", (W / 2 - 0.12, 0.08, H - 1.0), (x, f - 0.04, 0.35 + (H - 0.65) / 2), "wood", r=0.04)
        for z, h in ((4.6, 2.6), (1.85, 2.2)):
            box("Panel", (W / 2 - 0.65, 0.05, h), (x, f - 0.1, z), "wood2", r=0.06, seg=3)
        ball("Knob", 0.08, (s * 0.25, f - 0.15, 3.3), "brass")


def nightstand(W, H, D):
    legs4("Leg", W / 2 - 0.2, D / 2 - 0.2, 0.45, 0.06, "wood2")
    box("Body", (W - 0.06, D - 0.2, 1.5), (0, 0.1, 0.45 + 0.75), "wood", r=0.05)
    f = -(D - 0.2) / 2 + 0.1
    box("Drawer", (W - 0.3, 0.05, 0.55), (0, f - 0.02, 1.62), "wood2", r=0.03)
    box("Door", (W - 0.3, 0.05, 0.7), (0, f - 0.02, 0.88), "wood2", r=0.03)
    for z in (1.62, 0.88):
        ball("Knob", 0.06, (0, f - 0.07, z), "brass")
    box("Top", (W - 0.02, D - 0.12, 0.1), (0, 0.06, 2.0), "wood", r=0.04)
    box("Clock", (0.6, 0.35, 0.32), (0.35, 0.05, 2.21), "accent", r=0.1, seg=3)
    cyl("Clock face", 0.12, 0.02, (0.35, -0.13, 2.21), "cream", axis="Y", seg=20, edge=0)
    lathe("Glass", [(0.001, 0), (0.1, 0), (0.12, 0.3), (0.001, 0.28)], (-0.45, -0.05, 2.05), "glass", seg=16)


def dresser(W, H, D):
    legs4("Leg", W / 2 - 0.25, D / 2 - 0.25, 0.4, 0.08, "wood2")
    top = H - 0.3
    box("Body", (W - 0.1, D - 0.2, top - 0.5), (0, 0.1, 0.4 + (top - 0.5) / 2), "wood", r=0.05)
    f = -(D - 0.2) / 2 + 0.1
    box("Top", (W, D, 0.15), (0, 0, top - 0.075), "wood2", r=0.05)
    for z in (0.85, 1.55, 2.25):
        for x in (-W / 4, W / 4):
            box("Drawer", (W / 2 - 0.2, 0.05, 0.6), (x, f - 0.02, z), "wood", r=0.04)
            box("Pull", (0.45, 0.06, 0.07), (x, f - 0.07, z), "brass", r=0.02)
    box("Doily", (1.2, 0.8, 0.01), (0.6, 0.0, top + 0.005), "cream", r=0)
    box("Jewelry box", (0.6, 0.4, 0.25), (-1.0, 0.0, top + 0.125), "red", r=0.06)


def mirror(W, H, D):
    for s in (-1, 1):
        box("Foot", (0.18, D, 0.15), (s * 0.75, 0, 0.075), "wood2", r=0.05, seg=3)
        box("Post", (0.16, 0.16, H - 0.4), (s * 0.75, 0.1, (H - 0.4) / 2 + 0.1), "wood2", r=0.05)
        ball("Finial", 0.12, (s * 0.75, 0.1, H - 0.15), "brass")
    frame = lathe("Frame", [(0.001, -0.06), (1.0, -0.06), (1.0, 0.06), (0.001, 0.06)], (0, 0, 0), "wood", seg=48, scale=(0.62, 1.0))
    frame.matrix_world = Matrix.Translation(CUR + Vector((0, 0.02, 2.75))) @ euler(rx=math.pi / 2) @ Matrix.Diagonal((1, 1.95, 1, 1))
    glass = lathe("Glass", [(0.001, 0.065), (0.9, 0.065), (0.9, 0.075), (0.001, 0.075)], (0, 0, 0), "mirror", seg=48, scale=(0.62, 1.0))
    glass.matrix_world = Matrix.Translation(CUR + Vector((0, 0.02, 2.75))) @ euler(rx=math.pi / 2) @ Matrix.Diagonal((1, 1.95, 1, 1))
    for s in (-1, 1):
        cyl("Pivot", 0.06, 0.18, (s * 0.67, 0.1, 2.75), "brass", axis="X", seg=10)


def photo_album(W, H, D):
    box("Box", (1.8, 1.39, 0.9), (0, 0.005, 0.45), "card", r=0.02)
    box("Inside", (1.7, 1.28, 0.02), (0, 0, 0.88), "soil", r=0)
    for n in range(3):
        box("Album", (0.32, 1.1, 1.25), (-0.55 + n * 0.38, 0.05, 0.72), ("leather", "book2", "book3")[n], r=0.04, rot=euler(ry=(n - 1) * 0.05))
    box("Photo", (0.6, 0.06, 0.75), (0.5, -0.25, 1.15), "white", r=0.01, rot=euler(rx=0.2, ry=0.1))
    box("Picture", (0.45, 0.02, 0.5), (0.5, -0.29, 1.2), "sky", r=0, rot=euler(rx=0.2, ry=0.1))


def rocking_horse(W, H, D):
    # The rockers: arcs of a big circle under the horse, their ends up.
    for s in (-1, 1):
        pts = []
        for k in range(25):
            a = -0.58 + 1.16 * k / 24
            pts.append((math.sin(a) * 3.2, s * 0.55, 3.32 - math.cos(a) * 3.2 + 0.08))
        for a, b in zip(pts, pts[1:]):
            tube("Rocker", a, b, 0.09, "wood2", 8)
    for x in (-0.7, 0.7):
        tube("Cross bar", (x, -0.55, 0.15), (x, 0.55, 0.15), 0.06, "wood2", 8)
        for s in (-1, 1):
            tube("Leg", (x, s * 0.55, 0.15), (x * 0.8, s * 0.22, 1.75), 0.08, "wood", 8)
    ball("Body", 0.75, (0, 0, 2.05), "wood", scale=(1.35, 0.62, 0.62))
    tube("Neck", (0.75, 0, 2.2), (1.15, 0, 2.85), 0.24, "wood", 12)
    ball("Head", 0.36, (1.35, 0, 2.87), "wood", scale=(1.25, 0.65, 0.8), rot=euler(ry=0.45))
    for s in (-1, 1):
        ball("Ear", 0.1, (1.15, s * 0.12, 3.01), "wood2", scale=(0.6, 0.5, 1.4))
        ball("Eye", 0.05, (1.5, s * 0.2, 2.95), "black")
    for k in range(6):
        ball("Mane", 0.14, (0.75 + k * 0.1, 0, 2.45 + k * 0.12), "accent", scale=(0.8, 0.6, 1.0))
    tube("Tail", (-1.0, 0, 2.15), (-1.55, 0, 1.6), 0.09, "accent", 8)
    box("Saddle", (0.75, 0.95, 0.15), (-0.05, 0, 2.5), "red", r=0.06, seg=3)
    tube("Handle", (1.1, -0.45, 2.62), (1.1, 0.45, 2.62), 0.05, "brass", 8)


def toy_box(W, H, D):
    box("Body", (2.96, 1.79, 1.7), (0, 0.005, 0.85), "paint", r=0.05)
    for z in (0.15, 1.55):
        box("Band", (2.98, 1.795, 0.14), (0, 0.003, z), "accent", r=0.03)
    for s in (-1, 1):
        box("Handle", (0.04, 0.5, 0.15), (s * 1.48, 0, 1.15), "dark", r=0.015)
    lid = box("Lid", (3.0, 1.7, 0.2), (0, 0, 0), "paint", r=0.06)
    lid.matrix_world = Matrix.Translation(CUR + Vector((0, 0.8, 1.7))) @ euler(rx=-0.25) @ Matrix.Translation(Vector((0, -0.85, 0.1)))
    ball("Teddy", 0.32, (0.65, 0.3, 1.92), "wicker")
    for s in (-1, 1):
        ball("Teddy ear", 0.11, (0.65 + s * 0.22, 0.3, 2.2), "wicker")
    ball("Teddy snout", 0.1, (0.65, 0.02, 1.9), "cream")
    ball("Ball", 0.28, (-0.7, 0.25, 1.85), "red")


def desk(W, H, D):
    box("Top", (W, D, 0.15), (0, 0, 2.3), "paint", r=0.05)
    box("Drawer unit", (1.3, D - 0.3, 2.2), (W / 2 - 0.7, 0.1, 1.1), "paint", r=0.04)
    f = -(D - 0.3) / 2 + 0.1
    for z in (1.75, 1.15, 0.5):
        box("Drawer", (1.15, 0.04, 0.5), (W / 2 - 0.7, f - 0.02, z), "accent", r=0.03)
        ball("Knob", 0.06, (W / 2 - 0.7, f - 0.08, z), "white")
    for sy in (-1, 1):
        box("Leg", (0.15, 0.15, 2.22), (-W / 2 + 0.15, sy * (D / 2 - 0.15), 1.11), "paint", r=0.04)
    box("Hutch", (W, 0.3, 0.8), (0, D / 2 - 0.15, 2.375 + 0.4), "paint", r=0.04)
    box("Hutch shelf", (W - 0.2, 0.5, 0.08), (0, D / 2 - 0.3, 2.9), "accent", r=0.02)
    books("Book", -W / 2 + 0.2, -W / 2 + 1.3, D / 2 - 0.55, 2.94, 0.45, 0.25, 3)
    lathe("Pencil cup", [(0.001, 0), (0.14, 0), (0.15, 0.38), (0.12, 0.38), (0.12, 0.03), (0.001, 0.03)], (0.9, -0.3, 2.375), "red", seg=16)
    for k, f in enumerate(("accent", "paint", "book3")):
        tube("Pencil", (0.9 + 0.04 * (k - 1), -0.3, 2.42), (0.9 + 0.08 * (k - 1), -0.3 + 0.04 * k, 2.92), 0.025, f, 6)
    box("Notebook", (0.8, 0.6, 0.04), (-0.4, -0.2, 2.395), "book2", r=0.01, rot=euler(rz=0.15))


def guitar(W, H, D):
    body = lathe("Body", [(0.001, -0.2), (0.62, -0.2), (0.62, 0.2), (0.001, 0.2)], (0, 0, 0), "wood", seg=40)
    body.matrix_world = Matrix.Translation(CUR + Vector((0, 0, 0.75))) @ euler(rx=math.pi / 2) @ Matrix.Diagonal((1.15, 1.15, 1, 1))
    upper = lathe("Upper bout", [(0.001, -0.2), (0.52, -0.2), (0.52, 0.2), (0.001, 0.2)], (0, 0, 0), "wood", seg=36)
    upper.matrix_world = Matrix.Translation(CUR + Vector((0, 0, 1.7))) @ euler(rx=math.pi / 2)
    cyl("Sound hole", 0.2, 0.02, (0, -0.21, 1.6), "black", axis="Y", seg=24, edge=0)
    torus("Rosette", 0.23, 0.02, (0, -0.215, 1.6), "cream", axis="Y", seg=24, ring_seg=6)
    box("Bridge", (0.55, 0.06, 0.12), (0, -0.22, 0.75), "wood2", r=0.02)
    box("Neck", (0.22, 0.14, 1.65), (0, -0.05, 2.2 + 0.8), "wood2", r=0.04)
    box("Fretboard", (0.2, 0.04, 1.75), (0, -0.14, 2.2 + 0.85), "black", r=0.01)
    box("Headstock", (0.3, 0.12, 0.5), (0, -0.04, H - 0.28), "wood2", r=0.05, rot=euler(rx=0.15))
    for s in (-1, 1):
        for z in (H - 0.42, H - 0.28, H - 0.14):
            cyl("Tuner", 0.03, 0.12, (s * 0.2, -0.02, z), "chrome", axis="X", seg=8, edge=0)
    for k in range(6):
        x = -0.07 + k * 0.028
        tube("String", (x, -0.17, 0.78), (x, -0.17, H - 0.55), 0.004, "chrome", 3)
    cyl("Strap button", 0.04, 0.06, (0, 0, 0.05), "black", seg=8, edge=0)


def washing_machine(W, H, D):
    box("Body", (W, D - 0.3, H - 0.1), (0, 0.15, 0.1 + (H - 0.1) / 2), "appliance", r=0.18, seg=3)
    f = -(D - 0.3) / 2 + 0.15
    box("Panel", (W - 0.1, 0.06, 0.6), (0, f - 0.01, H - 0.4), "appliance", r=0.05)
    box("Drawer", (0.75, 0.06, 0.35), (-0.85, f - 0.05, H - 0.4), "white", r=0.04)
    cyl("Dial", 0.18, 0.12, (0.85, f - 0.07, H - 0.4), "chrome", axis="Y", seg=20)
    box("Display", (0.55, 0.03, 0.2), (0.15, f - 0.05, H - 0.4), "glass", r=0.03)
    torus("Door ring", 0.78, 0.09, (0, f - 0.09, 1.45), "chrome", axis="Y", seg=40, ring_seg=8)
    cyl("Door glass", 0.72, 0.08, (0, f - 0.05, 1.45), "glass", axis="Y", seg=40)
    cyl("Drum", 0.55, 0.05, (0, f + 0.25, 1.45), "steel", axis="Y", seg=32, edge=0)
    box("Handle", (0.12, 0.08, 0.35), (0.72, f - 0.17, 1.45), "chrome", r=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl("Foot", 0.09, 0.1, (sx * (W / 2 - 0.3), sy * (D / 2 - 0.3), 0.05), "dark", seg=8, edge=0)


def laundry_basket(W, H, D):
    sx = W / 2 / 0.9
    sy = D / 2 / 0.9
    lathe("Basket", [(0.001, 0), (0.72, 0), (0.88, 1.15), (0.9, 1.15), (0.9, 1.2), (0.84, 1.2), (0.68, 0.08), (0.001, 0.08)],
          (0, 0, 0), "wicker", seg=32, scale=(sx * 0.98, sy * 0.98))
    for z in (0.35, 0.7, 1.0):
        r = 0.72 + 0.16 * z / 1.15
        torus("Weave", r, 0.03, (0, 0, z), "wood2", seg=32, ring_seg=6, rot=Matrix.Diagonal((sx * 0.99, sy * 0.99, 1, 1)))
    for s in (-1, 1):
        box("Handle", (0.08, 0.45, 0.14), (s * 0.86 * sx, 0, 1.05), "wood2", r=0.03)
    for k, (x, y, f) in enumerate(((-0.25, 0.0, "fabric"), (0.25, 0.1, "white"), (0.0, -0.15, "fabric2"), (0.3, -0.2, "red"))):
        cushion("Laundry", (0.85, 0.6, 0.38), (x, y, 1.2 + 0.08 * (k % 2)), f, rot=euler(rz=0.6 * k, rx=0.15))


def coat_rack(W, H, D):
    for k in range(3):
        a = k * 2 * math.pi / 3
        tube("Foot", (0, 0, 0.6), (math.cos(a) * 0.68, math.sin(a) * 0.68, 0.04), 0.05, "wood2", 8)
        ball("Toe", 0.06, (math.cos(a) * 0.68, math.sin(a) * 0.68, 0.06), "brass")
    cyl("Pole", 0.07, H - 0.35, (0, 0, (H - 0.35) / 2 + 0.05), "wood2", seg=12)
    lathe("Top", [(0.001, 0), (0.1, 0), (0.12, 0.12), (0.001, 0.3)], (0, 0, H - 0.32), "wood2", seg=12)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        tube("Hook", (0, 0, H - 0.75), (math.cos(a) * 0.45, math.sin(a) * 0.45, H - 0.5), 0.035, "brass", 6)
        ball("Hook end", 0.05, (math.cos(a) * 0.45, math.sin(a) * 0.45, H - 0.48), "brass")
    coat = lathe("Coat", [(0.12, 0.0), (0.36, -0.3), (0.46, -1.4), (0.5, -2.2), (0.001, -2.2)], (0, 0, 0), "fabric2", seg=16, scale=(1.0, 0.55))
    coat.matrix_world = Matrix.Translation(CUR + Vector((0.2, -0.2, H - 0.55))) @ euler(rz=0.4)
    ball("Hat", 0.3, (-0.3, 0.25, H - 0.4), "dark", scale=(1, 1, 0.55))
    cyl("Hat brim", 0.42, 0.04, (-0.3, 0.25, H - 0.55), "dark", seg=20, edge=0)
    tube("Scarf", (-0.35, -0.3, H - 0.55), (-0.45, -0.4, H - 1.6), 0.09, "red", 8)


def shoe_cabinet(W, H, D):
    box("Body", (W - 0.06, D - 0.25, H - 0.75), (0, 0.125, 0.2 + (H - 0.75) / 2), "paint", r=0.05)
    f = -(D - 0.25) / 2 + 0.125
    box("Plinth", (W - 0.2, D - 0.4, 0.2), (0, 0.15, 0.1), "dark", r=0.02)
    box("Top", (W, D - 0.1, 0.1), (0, 0.05, H - 0.55 + 0.05), "wood", r=0.04)
    for s in (-1, 1):
        for z in (1.35, 0.65):
            box("Flap", (W / 2 - 0.15, 0.05, 0.85), (s * W / 4, f - 0.03, z), "paint", r=0.04, rot=euler(rx=0.05))
        for z in (1.68, 0.98):
            box("Pull", (0.4, 0.06, 0.05), (s * W / 4, f - 0.09, z), "brass", r=0.02)
    for k, x in enumerate((-0.9, -0.55, 0.6, 0.95)):
        shoe = ball("Shoe", 0.25, (x, 0.0, H - 0.4), "leather" if k < 2 else "red", scale=(0.55, 1.5, 0.55))
        box("Sole", (0.26, 0.75, 0.06), (x, 0.0, H - 0.47), "rubber", r=0.02)


def bicycle(W, H, D):
    for x in (-1.6, 1.6):
        torus("Tyre", 0.95, 0.09, (x, 0, 1.05), "rubber", axis="Y", seg=36, ring_seg=8)
        torus("Rim", 0.86, 0.035, (x, 0, 1.05), "chrome", axis="Y", seg=36, ring_seg=6)
        cyl("Hub", 0.08, 0.2, (x, 0, 1.05), "chrome", axis="Y", seg=12, edge=0)
        for k in range(8):
            a = k * math.pi / 8
            tube("Spoke", (x + math.cos(a) * 0.85, 0, 1.05 + math.sin(a) * 0.85), (x - math.cos(a) * 0.85, 0, 1.05 - math.sin(a) * 0.85), 0.01, "steel", 3)
    crank = Vector((0.0, 0, 1.0))
    seat_top = Vector((-0.45, 0, 2.35))
    head_top = Vector((1.2, 0, 2.4))
    head_low = Vector((1.35, 0, 1.95))
    for a, b in ((crank, seat_top), (seat_top, head_top), (crank, head_low), (crank, Vector((-1.6, 0, 1.05))), (seat_top, Vector((-1.6, 0, 1.05)))):
        tube("Frame", tuple(a), tuple(b), 0.065, "paint", 10)
    tube("Fork", tuple(head_low), (1.6, 0, 1.05), 0.05, "paint", 8)
    tube("Head tube", tuple(head_low), tuple(head_top), 0.075, "paint", 10)
    tube("Stem", tuple(head_top), (1.15, 0, 2.75), 0.04, "chrome", 8)
    tube("Handlebar", (1.05, -0.55, 2.8), (1.05, 0.55, 2.8), 0.035, "chrome", 8)
    for s in (-1, 1):
        tube("Grip", (1.05, s * 0.4, 2.8), (1.05, s * 0.58, 2.8), 0.05, "rubber", 8)
    tube("Seat post", tuple(seat_top), (-0.52, 0, 2.75), 0.035, "chrome", 8)
    box("Saddle", (0.65, 0.3, 0.14), (-0.5, 0, 2.86), "leather", r=0.06, seg=3)
    cyl("Chainring", 0.3, 0.04, (0, 0.12, 1.0), "steel", axis="Y", seg=24, edge=0)
    for s in (-1, 1):
        tube("Crank", (0, s * 0.15, 1.0), (s * 0.3, s * 0.2, 1.0 - s * 0.3), 0.03, "steel", 6)
        box("Pedal", (0.25, 0.18, 0.05), (s * 0.3, s * 0.3, 1.0 - s * 0.3), "dark", r=0.02)
    for x in (-1.6, 1.6):
        torus("Mudguard", 1.02, 0.03, (x, 0, 1.05), "paint", axis="Y", seg=20, ring_seg=4, arc=2.2,
              rot=euler(ry=-(math.pi - 2.2) / 2 - (0.0 if x > 0 else 0.0)))
    box("Basket", (0.6, 0.55, 0.4), (1.45, 0, 2.55), "wicker", r=0.05)


def toolbox(W, H, D):
    box("Body", (W - 0.04, D - 0.1, 0.82), (0, 0.05, 0.41), "red", r=0.06, seg=3)
    box("Lid", (W - 0.02, D - 0.08, 0.2), (0, 0.04, 0.92), "red", r=0.06, seg=3)
    for s in (-1, 1):
        box("Latch", (0.22, 0.05, 0.3), (s * 0.6, -D / 2 + 0.03, 0.8), "steel", r=0.02)
        tube("Handle post", (s * 0.4, 0, 1.02), (s * 0.4, 0, 1.2), 0.04, "dark", 6)
    tube("Handle", (-0.42, 0, 1.2), (0.42, 0, 1.2), 0.05, "dark", 8)
    box("Label", (0.5, 0.02, 0.2), (0, -D / 2 + 0.04, 0.45), "steel", r=0.01)


def lawn_mower(W, H, D):
    box("Deck", (2.0, 2.0, 0.55), (0, -1.0, 0.65), "paint", r=0.2, seg=3)
    for x in (-0.97, 0.97):
        for y in (-1.75, -0.2):
            cyl("Wheel", 0.36, 0.25, (x, y, 0.36), "rubber", axis="X", seg=20)
            cyl("Hub", 0.15, 0.27, (x, y, 0.36), "steel", axis="X", seg=12, edge=0)
    cyl("Engine", 0.5, 0.65, (0, -1.0, 1.25), "dark", seg=24)
    cyl("Engine top", 0.42, 0.12, (0, -1.0, 1.62), "steel", seg=24)
    cyl("Cap", 0.12, 0.1, (0.2, -0.9, 1.73), "red", seg=12, edge=0)
    for s in (-1, 1):
        tube("Handle", (s * 0.75, 0.0, 0.85), (s * 0.75, 1.9, 3.05), 0.06, "dark", 8)
    tube("Grip", (-0.8, 1.95, 3.08), (0.8, 1.95, 3.08), 0.07, "rubber", 8)
    cushion("Bag", (1.4, 1.3, 1.0), (0, 0.85, 1.05), "fabric2", rot=euler(rx=0.15))
    box("Bag frame", (1.5, 0.1, 1.1), (0, 0.2, 1.05), "dark", r=0.03)


def moving_box(W, H, D):
    box("Body", (1.95, 1.95, 1.76), (0, 0, 0.88), "card", r=0.03)
    box("Tape", (0.45, 1.97, 0.02), (0, 0, 1.765), "tape", r=0)
    for y in (-0.985, 0.985):
        box("Tape", (0.45, 0.02, 0.16), (0, y, 1.68), "tape", r=0)  # (short folds: THIS SIDE UP is printed on the back)
    box("Tag", (0.88, 0.01, 0.48), (-0.45, -0.985, 0.95), "white", r=0)  # (the game's +x: the label FurnitureLooks prints on it)


BUILD = {
    "sofa": sofa, "armchair": lambda W, H, D: sofa(W, H, D, True), "tv": tv, "coffee_table": coffee_table,
    "floor_lamp": floor_lamp, "bookshelf": bookshelf, "painting": painting, "plant": plant, "piano": piano,
    "grandfather_clock": grandfather_clock, "record_player": record_player, "fridge": fridge, "microwave": microwave,
    "dining_table": dining_table, "dining_chair": dining_chair, "dishes_box": dishes_box, "radio": radio, "bed": bed,
    "wardrobe": wardrobe, "nightstand": nightstand, "dresser": dresser, "mirror": mirror, "photo_album": photo_album,
    "kids_bed": lambda W, H, D: bed(W, H, D, True), "rocking_horse": rocking_horse, "toy_box": toy_box, "desk": desk,
    "guitar": guitar, "washing_machine": washing_machine, "laundry_basket": laundry_basket, "coat_rack": coat_rack,
    "shoe_cabinet": shoe_cabinet, "bicycle": bicycle, "toolbox": toolbox, "lawn_mower": lawn_mower, "box": moving_box,
}


# ───────────────────────────────────────────────────────────── scéna
def clear_previous():
    for name in ("Furniture", "Room"):
        root = bpy.data.collections.get(name)
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
    for pool in (bpy.data.meshes, bpy.data.lights, bpy.data.cameras):
        for block in list(pool):
            if block.users == 0:
                pool.remove(block)


def cell(index):
    return Vector(((index % COLUMNS) * CELL, -(index // COLUMNS) * CELL, 0))


def build_all():
    global CUR, COL
    clear_previous()
    materials()
    root = bpy.data.collections.new("Furniture")
    bpy.context.scene.collection.children.link(root)
    report = []
    for i, (fid, name, w, h, d) in enumerate(ITEMS):
        COL = bpy.data.collections.new("F_" + fid)
        root.children.link(COL)
        CUR = cell(i)
        BUILD[fid](w, h, d)
        COL["size"] = (w, h, d)
        COL["origin"] = tuple(CUR)
        report.append(check_bounds(fid, w, h, d))
    return report


def bounds(col, dg):
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in col.objects:
        ev = o.evaluated_get(dg)
        for v in ev.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def check_bounds(fid, w, h, d):
    """How the piece fits its box in the game (X wide, Y deep here, Z tall): what sticks out, how much it fills."""
    dg = bpy.context.evaluated_depsgraph_get()
    lo, hi = bounds(COL, dg)
    lo -= CUR
    hi -= CUR
    over = max(lo.x * -1 - w / 2, hi.x - w / 2, lo.y * -1 - d / 2, hi.y - d / 2, -lo.z, hi.z - h, 0)
    return fid, round(over, 3), (round(hi.x - lo.x, 2), round(hi.z - lo.z, 2), round(hi.y - lo.y, 2))


ROOM = [  # the living room in the preview: id, where (x, y on the floor), turn (degrees, 0: facing -Y), up
    ("sofa", (0, 7.0), 0, 0), ("painting", (0, 8.75), 0, 4.1), ("coffee_table", (0, 3.4), 0, 0), ("armchair", (-5.6, 4.0), 60, 0),
    ("floor_lamp", (-4.4, 7.7), 0, 0), ("bookshelf", (-12.15, 1.5), 90, 0), ("plant", (4.7, 7.8), 0, 0),
    ("tv", (8.4, 3.2), -60, 0), ("grandfather_clock", (9.6, 8.2), 0, 0), ("record_player", (-9.0, 7.8), 0, 0),
    ("radio", (-12.15, 1.5), 90, 6.65),
]


def room_scene():
    """A furnished living room next to the catalogue: linked copies of the pieces in a room with walls and a window."""
    col = bpy.data.collections.new("Room")
    bpy.context.scene.collection.children.link(col)
    base = Vector((0, 40, 0))
    def slab(name, size, at, finish, mat=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat or M[finish])
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.location = base + Vector(at)
        return o
    def nodes(name, colour):
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*linear(colour), 1)
        try:
            mat.use_nodes = True
        except Exception:
            pass
        nt = mat.node_tree
        return mat, nt, next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    def socket(sockets, name, kind):
        return next(x for x in sockets if x.name == name and x.type == kind)
    # Planks: a brick pattern in the floor's own coordinates (studs), each plank its own tone, a fine grain over it.
    floor, nt, bsdf = nodes("Room floor", "#9C6A42")
    coords = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset, brick.offset_frequency = 0.5, 2
    for key, value in (("Scale", 1.0), ("Mortar Size", 0.015), ("Mortar Smooth", 0.2), ("Bias", 0.0), ("Brick Width", 4.5), ("Row Height", 0.8)):
        brick.inputs[key].default_value = value
    brick.inputs["Color1"].default_value = (*linear("#8E5C37"), 1)
    brick.inputs["Color2"].default_value = (*linear("#B07A4C"), 1)
    brick.inputs["Mortar"].default_value = (*linear("#4A3020"), 1)
    nt.links.new(coords.outputs["Object"], brick.inputs["Vector"])
    grain = nt.nodes.new("ShaderNodeTexWave")
    grain.bands_direction = "Y"
    grain.inputs["Scale"].default_value = 3.0
    grain.inputs["Distortion"].default_value = 5.0
    grain.inputs["Detail"].default_value = 3.0
    nt.links.new(coords.outputs["Object"], grain.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.78, 0.78, 0.78, 1)
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(grain.outputs["Fac"], ramp.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
    socket(mix.inputs, "Factor", "VALUE").default_value = 0.6
    nt.links.new(brick.outputs["Color"], socket(mix.inputs, "A", "RGBA"))
    nt.links.new(ramp.outputs["Color"], socket(mix.inputs, "B", "RGBA"))
    nt.links.new(socket(mix.outputs, "Result", "RGBA"), bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.4
    # Wallpaper: soft stripes (x + y: along each wall), two sage greens.
    paper, nt, pb = nodes("Room wallpaper", "#C9D4BC")
    coords = nt.nodes.new("ShaderNodeTexCoord")
    xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coords.outputs["Object"], xyz.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(xyz.outputs["X"], add.inputs[0])
    nt.links.new(xyz.outputs["Y"], add.inputs[1])
    wave = nt.nodes.new("ShaderNodeMath")
    wave.operation = "SINE"
    times = nt.nodes.new("ShaderNodeMath")
    times.operation = "MULTIPLY"
    times.inputs[1].default_value = 4.0
    nt.links.new(add.outputs[0], times.inputs[0])
    nt.links.new(times.outputs[0], wave.inputs[0])
    stripes = nt.nodes.new("ShaderNodeValToRGB")
    stripes.color_ramp.interpolation = "CONSTANT"
    stripes.color_ramp.elements[0].color = (*linear("#C9D4BC"), 1)
    stripes.color_ramp.elements[1].position = 0.55
    stripes.color_ramp.elements[1].color = (*linear("#B9C7AA"), 1)
    nt.links.new(wave.outputs[0], stripes.inputs["Fac"])
    nt.links.new(stripes.outputs["Color"], pb.inputs["Base Color"])
    pb.inputs["Roughness"].default_value = 0.9
    # The sky through the window: a soft daylight glow.
    def glow(name, colour, strength):
        mat, nt, b = nodes(name, colour)
        b.inputs["Base Color"].default_value = mat.diffuse_color
        b.inputs["Emission Color"].default_value = mat.diffuse_color
        b.inputs["Emission Strength"].default_value = strength
        return mat
    sky = glow("Room sky", "#6FA8E0", 0.55)
    garden = glow("Room garden", "#5E9A4E", 0.35)
    hedge = glow("Room hedge", "#3F7A3E", 0.3)
    slab("Room floor", (27, 19, 0.2), (0, 0, -0.1), None, floor)
    slab("Back wall", (27, 0.5, 12), (0, 9.25, 6), None, paper)
    slab("Left wall", (0.5, 19, 12), (-13.25, 0, 6), None, paper)
    slab("Baseboard", (27, 0.12, 0.5), (0, 8.95, 0.25), "white")
    slab("Baseboard", (0.12, 19, 0.5), (-12.95, 0, 0.25), "white")
    slab("Picture rail", (27, 0.1, 0.15), (0, 8.95, 8.5), "white")
    slab("Wainscot", (27, 0.1, 3.0), (0, 8.96, 1.5), "cream")
    slab("Wainscot", (0.1, 19, 3.0), (-12.96, 0, 1.5), "cream")
    slab("Chair rail", (27, 0.16, 0.14), (0, 8.92, 3.0), "white")
    slab("Chair rail", (0.16, 19, 0.14), (-12.92, 0, 3.0), "white")
    slab("Right wall", (0.5, 19, 12), (13.25, 0, 6), None, paper)
    slab("Baseboard", (0.12, 19, 0.5), (12.95, 0, 0.25), "white")
    slab("Wainscot", (0.1, 19, 3.0), (12.96, 0, 1.5), "cream")
    slab("Chair rail", (0.16, 19, 0.14), (12.92, 0, 3.0), "white")
    for s in (-1, 1):  # the frame round the opening (4 by 4)
        slab("Window frame", (4.6, 0.25, 0.3), (5.0, 8.9, 5.6 + s * 2.15), "white")
        slab("Window frame", (0.3, 0.25, 4.0), (5.0 + s * 2.15, 8.9, 5.6), "white")
    slab("Window", (4.0, 0.1, 4.0), (5.0, 8.97, 5.6), None, sky)
    slab("Garden", (4.0, 0.02, 0.9), (5.0, 8.91, 4.05), None, garden)  # (the view: a lawn and a hedge under the sky)
    slab("Hedge", (4.0, 0.02, 0.35), (5.0, 8.912, 4.62), None, hedge)
    slab("Mullion", (0.15, 0.2, 4.0), (5.0, 8.9, 5.6), "white")
    slab("Mullion", (4.0, 0.2, 0.15), (5.0, 8.9, 5.6), "white")
    slab("Sill", (5.2, 0.6, 0.2), (5.0, 8.75, 3.25), "white")
    for s in (-1, 1):
        slab("Curtain", (1.1, 0.25, 6.0), (5.0 + s * 2.9, 8.7, 5.4), "fabric2")
    slab("Rug", (10, 6.5, 0.06), (0, 3.6, 0.03), "fabric")
    slab("Rug field", (9.0, 5.5, 0.07), (0, 3.6, 0.035), "cream")
    for fid, (x, y), turn, up in ROOM:
        src = bpy.data.collections["F_" + fid]
        origin = Vector(src["origin"])
        move = Matrix.Translation(base + Vector((x, y, up))) @ Matrix.Rotation(math.radians(turn), 4, "Z") @ Matrix.Translation(-origin)
        for o in src.objects:
            c = o.copy()
            col.objects.link(c)
            c.matrix_world = move @ o.matrix_world
    # Its daylight through the window, a warm ceiling light and its own camera (F12 with "Room camera" active).
    lamp = bpy.data.objects.new("Window light", bpy.data.lights.new("Window light", "AREA"))
    col.objects.link(lamp)
    lamp.data.energy, lamp.data.size = 900, 4
    lamp.data.color = (1.0, 0.95, 0.85)
    lamp.location = base + Vector((5.0, 8.2, 5.6))
    lamp.rotation_euler = (math.radians(90), 0, math.radians(180))
    try:
        lamp.visible_camera = False  # (the window's light, not a white square in front of it)
    except AttributeError:
        pass
    fill = bpy.data.objects.new("Ceiling light", bpy.data.lights.new("Ceiling light", "POINT"))
    col.objects.link(fill)
    fill.data.energy, fill.data.color = 2500, (1.0, 0.88, 0.7)
    fill.location = base + Vector((0, 3.0, 10.5))
    cam = bpy.data.objects.new("Room camera", bpy.data.cameras.new("Room camera"))
    col.objects.link(cam)
    aim(cam, base + Vector((-0.3, 5.0, 2.6)), Vector((0.32, -1.0, 0.42)), 19.5)
    cam.data.lens = 24
    return base


def studio():
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    world = scene.world or bpy.data.worlds.new("Furniture world")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*linear("#A9B2BC"), 1)
    bg.inputs["Strength"].default_value = 0.6
    col = bpy.data.collections["Furniture"]
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60)
    me = bpy.data.meshes.new("Floor")
    bm.to_mesh(me)
    bm.free()
    floor = bpy.data.materials.get("Furniture floor") or bpy.data.materials.new("Furniture floor")
    floor.diffuse_color = (*linear("#3A3F45"), 1)
    me.materials.append(floor)
    o = bpy.data.objects.new("Floor", me)
    col.objects.link(o)
    o.location = (CELL * (COLUMNS - 1) / 2, -CELL * 2.5, -0.001)
    sun = bpy.data.objects.new("Studio sun", bpy.data.lights.new("Studio sun", "SUN"))
    col.objects.link(sun)
    sun.data.energy, sun.data.angle = 3.0, math.radians(8)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    col.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    aim(cam, Vector((CELL * 2.5, -CELL * 2.5, 2)), Vector((-1, -1.4, 1.0)), 70)
    return cam


def aim(cam, target, direction, distance, ortho=None):
    cam.location = target + direction.normalized() * distance
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type, cam.data.ortho_scale = "ORTHO", ortho
    else:
        cam.data.type, cam.data.lens = "PERSP", 35


def render_all(folder, samples=48):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples, scene.cycles.use_denoising = samples, True
    os.makedirs(folder, exist_ok=True)
    cam = scene.camera
    cats = bpy.data.collections["Furniture"].children
    room = bpy.data.collections.get("Room")
    # The catalogue: one piece at a time, the others hidden.
    scene.render.resolution_x, scene.render.resolution_y = 520, 520
    if room:
        room.hide_render = True
    for i, (fid, name, w, h, d) in enumerate(ITEMS):
        for c in cats:
            c.hide_render = c.name != "F_" + fid
        size = max(w, h, d)
        aim(cam, cell(i) + Vector((0, 0, h / 2)), Vector((-0.75, -1.25, 0.7)), 40, ortho=size * 1.45)
        scene.render.filepath = os.path.join(folder, f"item-{i:02d}-{fid}.png")
        bpy.ops.render.render(write_still=True)
    for c in cats:
        c.hide_render = False
    # The furnished living room.
    if room:
        room.hide_render = False
        for c in cats:
            c.hide_render = True
        bpy.data.objects["Floor"].hide_render = True
        scene.render.resolution_x, scene.render.resolution_y = 1800, 1100
        scene.camera = bpy.data.objects["Room camera"]
        scene.render.filepath = os.path.join(folder, "room.png")
        bpy.ops.render.render(write_still=True)
        scene.camera = cam
        bpy.data.objects["Floor"].hide_render = False
        for c in cats:
            c.hide_render = False


# ───────────────────────────────────────────────────────────── export do hry
def split_by_finish(me, matrix, out, group):
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
    names = [m["finish"] for m in me.materials]
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


def export_game(folder):
    """ZDCFurnitureArt.fbx for the game: "<id>_<finish>" pieces, a marker "mark_<id>" at each piece's origin (the bottom
    middle of its box) and mark_o / mark_x / mark_y / mark_z (the game's axes: x right = here -x, y up, z back = here +y)."""
    os.makedirs(folder, exist_ok=True)
    temp = bpy.data.collections.new("Furniture_Export")
    bpy.context.scene.collection.children.link(temp)
    dg = bpy.context.evaluated_depsgraph_get()
    pieces = {}
    for fid, *_ in ITEMS:
        for o in bpy.data.collections["F_" + fid].objects:
            if o.type == "MESH":
                me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
                split_by_finish(me, o.matrix_world.copy(), pieces, fid)
    made, manifest = [], {"items": {}, "pieces": {}}
    for (fid, finish), meshes in sorted(pieces.items()):
        bm = bmesh.new()
        for piece in meshes:
            bm.from_mesh(piece)
        me = bpy.data.meshes.new(f"{fid}_{finish}")
        bm.to_mesh(me)
        bm.free()
        normals = [0.0] * (len(me.loops) * 3)
        me.attributes["nrm"].data.foreach_get("vector", normals)
        for p in me.polygons:
            p.use_smooth = True
        me.normals_split_custom_set([normals[i:i + 3] for i in range(0, len(normals), 3)])
        for name in ("nrm", "fin"):
            if me.attributes.get(name):
                me.attributes.remove(me.attributes[name])
        me.materials.append(M[finish])
        o = bpy.data.objects.new(f"{fid}_{finish}", me)
        temp.objects.link(o)
        made.append(o)
        origin = Vector(bpy.data.collections["F_" + fid]["origin"])
        pts = [Vector((-(v.co.x - origin.x), v.co.z, v.co.y - origin.y)) for v in me.vertices]
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        manifest["pieces"][o.name] = {"center": [round((a + b) / 2, 4) for a, b in zip(lo, hi)], "size": [round(b - a, 4) for a, b in zip(lo, hi)],
                                      "triangles": sum(len(p.vertices) - 2 for p in me.polygons)}
    marks = [("mark_o", (0, 0, 0)), ("mark_x", (-10, 0, 0)), ("mark_y", (0, 0, 10)), ("mark_z", (0, 10, 0))]
    for i, (fid, name, w, h, d) in enumerate(ITEMS):
        marks.append(("mark_" + fid, tuple(cell(i))))
        manifest["items"][fid] = {"size": [w, h, d], "cell": list(cell(i))}
    for name, at in marks:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.3)
        bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(M["dark"])
        o = bpy.data.objects.new(name, me)
        temp.objects.link(o)
        made.append(o)
    for o in bpy.context.scene.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.fbx(filepath=os.path.join(folder, "ZDCFurnitureArt.fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="OFF", use_mesh_modifiers=True)
    with open(os.path.join(folder, "ZDCFurnitureArt.json"), "w", encoding="utf-8") as f:
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
    room_scene()
    studio()
    for fid, over, filled in report:
        if over > 0.02:
            print(f"WARNING {fid} sticks out of its box by {over}")
    source = globals().get("__file__", "")
    if os.path.isfile(source) and "furniture.py" not in bpy.data.texts:
        bpy.data.texts.new("furniture.py").write(open(source, encoding="utf-8").read())
    if arg("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--save")))
    if arg("--render"):
        render_all(arg("--render"), int(arg("--samples") or 48))
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        manifest = export_game(folder)
        tris = sum(p["triangles"] for p in manifest["pieces"].values())
        print(f"ZDCFurnitureArt: {len(manifest['pieces'])} pieces, {tris} triangles, the largest {max(p['triangles'] for p in manifest['pieces'].values())}")
    for fid, over, filled in report:
        print(f"  {fid:18s} fills {filled}  sticks out {over}")


main()
