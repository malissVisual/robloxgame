"""Zombie Delivery: nábytek pro stěhování (7.0 MOVES) v Blenderu.

Spuštění v Blenderu: záložka Scripting → Open → furniture.py → Run Script (▶, nebo Alt+P). Skript postaví všech 36 kusů
nábytku ze hry (shared/FurnitureLooks.luau) a 12 sběratelských kousků z 8.0 SANDBOXu (FurnitureLooks.Collectibles: trofej,
rádio, glóbus … rytířská zbroj) v mřížce do kolekce "Furniture" a vedle zařízený obývák (scéna "Room").
Každý kus má přesně rozměry ze hry (Root box): 1 jednotka = 1 stud, předek míří na -Y, spodek kusu je na zemi.

Bez Blenderu, jen s modulem bpy (pip install bpy):
    python furniture.py -- --save furniture.blend --render složka --export složka
    (--only id,id: render jen těchto kusů; --only collectibles: 12 sběratelských kousků pro collectibles-preview.png)
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
    # 8.0 SANDBOX: sběratelské kousky (FurnitureLooks.Collectibles; vzácnost v komentáři)
    ("bowling_trophy", "Bowling Trophy", 1.4, 2.8, 1.0), ("vintage_radio", "Vintage Radio", 1.8, 2.0, 1.2),  # uncommon
    ("old_globe", "Old Globe", 1.6, 2.6, 1.6), ("stag_head", "Mounted Stag Head", 3.2, 3.4, 1.7),  # uncommon
    ("gold_record", "Gold Record", 2.2, 2.6, 0.4), ("ship_bottle", "Ship in a Bottle", 2.2, 1.35, 0.9),  # rare
    ("jewellery_box", "Grandma's Jewellery Box", 1.7, 1.2, 1.1),  # rare
    ("antique_vase", "Antique Vase", 1.4, 2.8, 1.4), ("arcade_cabinet", "Arcade Cabinet", 2.8, 6.0, 3.0),  # epic
    ("jukebox", "Jukebox", 3.4, 5.4, 2.5),  # epic
    ("oil_painting", "Oil Painting", 4.8, 3.8, 0.6), ("knight_armour", "Knight's Armour", 2.6, 6.8, 1.8),  # legendary
    # 8.3: dalších 12 sběratelských kousků (tři od každé vzácnosti)
    ("antique_typewriter", "Antique Typewriter", 1.8, 1.2, 1.6), ("vintage_camera", "Vintage Camera", 1.6, 4.4, 1.6),  # uncommon
    ("carved_bear", "Carved Wooden Bear", 1.8, 3.3, 1.4),  # uncommon
    ("gramophone", "Gramophone", 1.8, 2.8, 2.2), ("pocket_watch", "Grandpa's Pocket Watch", 1.0, 1.5, 1.0),  # rare
    ("golden_horseshoe", "Golden Horseshoe", 1.6, 2.0, 0.8),  # rare
    ("crystal_chandelier", "Crystal Chandelier", 2.4, 2.6, 2.4), ("alphorn", "Alphorn", 7.2, 1.8, 1.4),  # epic
    ("signed_guitar", "Signed Guitar", 1.6, 4.4, 1.2),  # epic
    ("ski_trophy", "Golden Ski Trophy", 2.2, 3.6, 1.2), ("trex_skull", "T. Rex Skull", 4.2, 3.2, 1.8),  # legendary
    ("zombie_safe", "Zombie-Proof Safe", 2.6, 3.4, 2.4),  # legendary
]
COLLECTIBLES = [fid for fid, *_ in ITEMS[36:]]
NEW_83 = [fid for fid, *_ in ITEMS[48:]]  # (8.3: the twelve new ones, for their own preview: --only new83)

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
    # 8.0 sběratelské kousky: leštěné zlato (gilt), samet, lak, neon, srst, paroží, mramor, porcelán a kobalt, žhavé trubice
    # jukeboxu (amber, ember), čiré sklo (crystal), moře a pergamen glóbu, barvy obrazu (peach, rock, slate).
    # gilt, velvet, lacquer, neon a fur mění ve hře barvu podle varianty (FurnitureLooks.Palettes).
    "gilt": ("#D9AD52", 0.16, 1, 0), "velvet": ("#8E1C2E", 1.0, 0, 0), "lacquer": ("#6E1820", 0.12, 0, 0),
    "neon": ("#50C8FF", 0.4, 0, 0.7), "fur": ("#80543A", 1.0, 0, 0), "bone": ("#DCCDA8", 0.5, 0, 0),
    "marble": ("#E8E4DC", 0.15, 0, 0), "porcelain": ("#F4F2EA", 0.08, 0, 0), "cobalt": ("#27448F", 0.12, 0, 0),
    "amber": ("#FF9A3C", 0.4, 0, 0.7), "ember": ("#FF4A32", 0.4, 0, 0.7), "crystal": ("#EEF6F4", 0.02, 0, 0),
    "ocean": ("#5E8FA8", 0.3, 0, 0), "parchment": ("#E6D3A3", 0.7, 0, 0), "peach": ("#F2B48C", 0.8, 0, 0),
    "rock": ("#8A8DAE", 0.8, 0, 0), "slate": ("#5E6682", 0.8, 0, 0),
    # 8.3: zkamenělá kost lebky T. rexe
    "fossil": ("#B49A72", 0.85, 0, 0),
}
# Navíc k povrchům: lesk laku a glazury (Coat), sklo, které propouští světlo (Transmission), sametový lesk (Sheen).
SPECIAL = {
    "crystal": {"Transmission Weight": 1.0, "IOR": 1.45, "Thin Wall": True},  # (a pane or a bottle's wall: no lens) "lacquer": {"Coat Weight": 1.0, "Coat Roughness": 0.04},
    "porcelain": {"Coat Weight": 0.8, "Coat Roughness": 0.03}, "cobalt": {"Coat Weight": 0.8, "Coat Roughness": 0.03},
    "marble": {"Coat Weight": 0.6, "Coat Roughness": 0.05}, "ocean": {"Coat Weight": 0.5, "Coat Roughness": 0.08},
    "velvet": {"Sheen Weight": 1.0, "Sheen Roughness": 0.35}, "fur": {"Sheen Weight": 0.6, "Sheen Roughness": 0.5},
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
        for key, value in SPECIAL.get(name, {}).items():
            if p.inputs.get(key) is not None:
                p.inputs[key].default_value = value
        m["finish"] = name
        M[name] = m


# ───────────────────────────────────────────────────────────── stavební kameny (souřadnice od spodku středu kusu)
def obj(name, bm, finish, smooth=True):
    """`finish`: one finish, or a list (the faces' material_index picks one: the globe's sea and land)."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for f in ([finish] if isinstance(finish, str) else finish):
        me.materials.append(M[f])
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
    if r <= 0:
        sharpen(bm)  # (no bevel: flat faces, not a box shaded round like a pebble; a thin pane of glass stays flat)
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


def ball(name, r, at, finish, scale=(1, 1, 1), rot=None, seg=16, rings=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings or max(6, seg // 2), radius=r)
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



# Další stavební kameny (8.0 sběratelské kousky): křivky, trubky po křivce, vytažené tvary, rámy obrazů, pixelová grafika.
def bezier(p0, p1, p2, p3, n=12):
    """Points along a cubic Bézier curve (a handle's ear, a cabriole leg's S)."""
    P = [Vector(p) for p in (p0, p1, p2, p3)]
    return [tuple(P[0] * (1 - t) ** 3 + P[1] * 3 * (1 - t) ** 2 * t + P[2] * 3 * (1 - t) * t * t + P[3] * t ** 3)
            for t in (k / n for k in range(n + 1))]


def spline(points, n=4):
    """A smooth path through `points` (Catmull-Rom, `n` steps from one to the next)."""
    P = [Vector(p) for p in points]
    out = []
    for i in range(len(P) - 1):
        a, b, c, d = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for k in range(n):
            t = k / n
            out.append(tuple(0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t ** 3)))
    out.append(tuple(P[-1]))
    return out


def arc(cx, cz, r, a0, a1, n, rz=None):
    """Points (x, z) of the front view on an arc (angles in radians, 0: +x, π/2: up); `rz` an ellipse's height."""
    rz = r if rz is None else rz
    return [(cx + r * math.cos(a0 + (a1 - a0) * k / n), cz + rz * math.sin(a0 + (a1 - a0) * k / n)) for k in range(n + 1)]


def sweep(name, pts, r, finish, seg=10, r1=None, scale=(1.0, 1.0), closed=False, smooth=True):
    """A tube along a path (a handle, an antler, a bubble tube): `r` one radius, or a list (one per point), or tapering
    to `r1`; `scale` (across, up) makes its section an oval; `closed` joins its ends into a ring."""
    P = [CUR + Vector(p) for p in pts]
    n = len(P)
    if isinstance(r, (list, tuple)):
        R = list(r)
    elif r1 is not None:
        R = [r + (r1 - r) * i / max(1, n - 1) for i in range(n)]
    else:
        R = [r] * n
    T = []
    for i in range(n):
        t = (P[(i + 1) % n] - P[i - 1]) if closed else (P[min(i + 1, n - 1)] - P[max(i - 1, 0)])
        T.append(t.normalized())
    ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((0, -1, 0))
    normal = (ref - T[0] * ref.dot(T[0])).normalized()
    bm = bmesh.new()
    rings = []
    for i in range(n):
        if i:
            normal = T[i - 1].rotation_difference(T[i]) @ normal
            normal = (normal - T[i] * normal.dot(T[i])).normalized()
        side = T[i].cross(normal)
        rings.append([bm.verts.new(P[i] + (normal * math.cos(a) * scale[1] + side * math.sin(a) * scale[0]) * R[i])
                      for a in (2 * math.pi * k / seg for k in range(seg))])
    for i in range(n if closed else n - 1):
        a, b = rings[i], rings[(i + 1) % n]
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharpen(bm, 50)
    return obj(name, bm, finish, smooth)


def prism(name, outline, y0, y1, finish, r=0.03, seg=2, at=(0, 0, 0), rot=None):
    """A flat shape drawn in the front view (x, z points round its edge) and pushed back from y0 to y1: a radio's arch, a
    shield, a cabinet's side (turned with `rot`)."""
    pts = []
    for p in outline:
        if not pts or (Vector(p) - Vector(pts[-1])).length > 1e-5:
            pts.append(p)
    if (Vector(pts[0]) - Vector(pts[-1])).length < 1e-5:
        pts.pop()
    bm = bmesh.new()
    front = [bm.verts.new((x, y0, z)) for x, z in pts]
    back = [bm.verts.new((x, y1, z)) for x, z in pts]
    caps = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    sharpen(bm)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix())
    return bevel(o, r, seg)


def layer(name, outline, y, finish, depth=0.003):
    """A layer of paint on a canvas: a flat shape `depth` thick, its face at y."""
    return prism(name, outline, y - depth, y, finish, r=0)


def rect_frame(name, hw, hh, profile, finish, place=None):
    """A picture frame's moulding round a rectangle (half width hw, half height hh, in the front view round `place`'s
    origin): `profile` (inset from the outer edge, y) points round its section, mitred at the corners."""
    place = Matrix.Translation(CUR) @ (place or Matrix())
    bm = bmesh.new()
    rings = []
    for inset, y in profile:
        w, h = hw - inset, hh - inset
        rings.append([bm.verts.new(place @ Vector((x, y, z))) for x, z in ((-w, -h), (w, -h), (w, h), (-w, h))])
    for i in range(len(rings)):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharpen(bm, 35)
    return obj(name, bm, finish)


def sprite(name, rows, px, finish, place):
    """Pixel art (rows of "#"): each run of pixels one flat quad facing -Y, drawn round `place`'s origin."""
    place = Matrix.Translation(CUR) @ place
    bm = bmesh.new()
    w, h = max(len(row) for row in rows), len(rows)
    for j, row in enumerate(rows):
        i = 0
        while i < len(row):
            if row[i] != "#":
                i += 1
                continue
            k = i
            while k < len(row) and row[k] == "#":
                k += 1
            x0, x1, z0, z1 = (i - w / 2) * px, (k - w / 2) * px, (h / 2 - j - 1) * px, (h / 2 - j) * px
            bm.faces.new([bm.verts.new(place @ Vector(v)) for v in ((x0, 0, z0), (x1, 0, z0), (x1, 0, z1), (x0, 0, z1))])
            i = k
    return obj(name, bm, finish, smooth=False)


def towards(direction):
    """A turn that points +Z along `direction`."""
    return Vector(direction).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()


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


# ───────────────────────────────────────────────────────────── 8.0 sběratelské kousky (FurnitureLooks.Collectibles)
# Vzácné kusy, které se objeví v domě vedle nábytku: zlato se leskne (gilt), sklo je čiré (crystal), jukebox žhne.
# Nápisy (LEAGUE CHAMPION, 1,000,000 SOLD, HIT PARADE, název hry na automatu …) tiskne hra na štítky; pod každým je díl
# modelu v barvě štítku (mosaz, krémová, neon) a před ním nic (tools/furniture/mesh-check.py to hlídá).
def bowling_trophy(W, H, D):
    """A league champion's trophy: the marble base, the wooden step with its plate, the gold loving cup and its lid,
    a bowling pin on top, the champion's own ball beside it."""
    box("Base", (1.4, 1.0, 0.2), (0, 0, 0.1), "marble", r=0.05, seg=3)
    box("Base top", (1.24, 0.88, 0.12), (0, 0, 0.26), "marble", r=0.04, seg=3)
    box("Step", (1.1, 0.8, 0.3), (0, 0, 0.47), "wood2", r=0.05, seg=3)
    box("Plate", (0.8, 0.02, 0.2), (0, -0.41, 0.5), "brass", r=0.006)  # (the game prints LEAGUE CHAMPION on it)
    lathe("Stem", [(0.001, 0.62), (0.25, 0.62), (0.25, 0.655), (0.2, 0.69), (0.11, 0.76), (0.07, 0.84), (0.065, 0.93),
                   (0.12, 0.98), (0.12, 1.03), (0.065, 1.08), (0.055, 1.28), (0.09, 1.36), (0.16, 1.42), (0.001, 1.44)],
          (0, 0, 0), "gilt", seg=20)
    lathe("Cup", [(0.001, 1.4), (0.2, 1.42), (0.31, 1.5), (0.4, 1.63), (0.43, 1.8), (0.42, 1.95), (0.405, 2.02),
                  (0.445, 2.06), (0.445, 2.09), (0.001, 2.09)], (0, 0, 0), "gilt", seg=28)
    torus("Cup bead", 0.41, 0.018, (0, 0, 1.68), "gilt", seg=28, ring_seg=4)
    lathe("Lid", [(0.001, 2.09), (0.42, 2.09), (0.42, 2.115), (0.37, 2.15), (0.26, 2.21), (0.12, 2.255), (0.07, 2.3),
                  (0.001, 2.3)], (0, 0, 0), "gilt", seg=24)
    for s in (-1, 1):
        sweep("Handle", bezier((s * 0.4, 0, 1.96), (s * 0.7, 0, 2.02), (s * 0.68, 0, 1.56), (s * 0.33, 0, 1.53), 14), 0.032, "gilt", seg=6)
    lathe("Pin", [(0.001, 2.3), (0.055, 2.3), (0.085, 2.36), (0.105, 2.44), (0.1, 2.52), (0.072, 2.6), (0.046, 2.65),
                  (0.048, 2.69), (0.064, 2.73), (0.06, 2.77), (0.035, 2.795), (0.001, 2.8)], (0, 0, 0), "white", seg=16)
    for z, R in ((2.612, 0.065), (2.642, 0.05)):
        torus("Pin stripe", R, 0.011, (0, 0, z), "red", seg=16, ring_seg=4)
    centre = Vector((0.4, -0.15, 0.62 + 0.23))
    ball("Ball", 0.23, tuple(centre), "lacquer", seg=20)
    for d in ((-0.25, -0.75, 0.6), (0.05, -0.8, 0.6), (-0.1, -0.55, 0.83)):
        n = Vector(d).normalized()
        cyl("Finger hole", 0.032, 0.012, tuple(centre + n * 0.226), "black", seg=8, edge=0, rot=towards(n))


def vintage_radio(W, H, D):
    """A 1930s cathedral radio: the dark wooden case under its arch with a lighter veneered face, half columns at its
    corners, the grille cloth behind gothic fretwork, the dial that glows amber, three bakelite knobs."""
    box("Plinth", (1.8, 1.2, 0.15), (0, 0, 0.075), "wood2", r=0.04, seg=3)
    prism("Case", [(-0.8, 0.15), (0.8, 0.15)] + arc(0, 1.1, 0.8, 0, math.pi, 28, rz=0.86), -0.5, 0.5, "wood2", r=0.06, seg=3)
    prism("Face", [(-0.69, 0.22), (0.69, 0.22)] + arc(0, 1.1, 0.69, 0, math.pi, 24, rz=0.76), -0.508, -0.496, "wood", r=0.008, seg=1)
    window = arc(0.42, 1.0, 0.08, -math.pi / 2, 0, 4) + arc(0, 1.22, 0.5, 0, math.pi, 22, rz=0.6) + arc(-0.42, 1.0, 0.08, math.pi, 1.5 * math.pi, 4)
    prism("Grille cloth", window, -0.515, -0.49, "wicker", r=0)
    sweep("Trim", [(x, -0.522, z) for x, z in window], 0.03, "wood2", seg=6, closed=True)
    y = -0.54
    for x in (-0.25, 0, 0.25):
        top = 1.22 + 0.6 * math.sqrt(max(0.0, 1 - (x / 0.5) ** 2)) - 0.03
        sweep("Fret", [(x, y, 0.95), (x, y, top)], 0.02, "wood2", seg=6)
    for x0, x1, peak in ((-0.5, -0.25, 1.46), (-0.25, 0, 1.56), (0, 0.25, 1.56), (0.25, 0.5, 1.46)):
        m = (x0 + x1) / 2
        sweep("Fret arch", [(x0, y, 1.3), (x0 + 0.02, y, 1.38), (m - 0.05, y, peak - 0.04), (m, y, peak), (m + 0.05, y, peak - 0.04),
                            (x1 - 0.02, y, 1.38), (x1, y, 1.3)], 0.018, "wood2", seg=6)
    torus("Rose", 0.09, 0.018, (0, y, 1.68), "wood2", axis="Y", seg=16, ring_seg=4)
    torus("Dial bezel", 0.15, 0.025, (0, -0.522, 0.66), "brass", axis="Y", seg=24, ring_seg=4)
    cyl("Dial", 0.135, 0.03, (0, -0.51, 0.66), "amber", axis="Y", seg=28, edge=0)
    box("Needle", (0.012, 0.01, 0.12), (0.03, -0.53, 0.69), "black", r=0, rot=euler(ry=-0.4))
    for x in (-0.48, 0, 0.48):
        lathe("Knob", [(0.001, 0), (0.09, 0), (0.1, 0.025), (0.085, 0.065), (0.06, 0.08), (0.001, 0.085)], (x, -0.5, 0.34),
              "black", seg=12, rot=euler(rx=math.pi / 2))
    for s in (-1, 1):
        cyl("Column", 0.06, 0.9, (s * 0.8, -0.5, 0.15 + 0.45), "wood", seg=10, edge=0)
        ball("Capital", 0.075, (s * 0.8, -0.5, 1.1), "wood", seg=10, rings=6)


LAND = [  # the old globe's continents (longitude, latitude), roughly
    [(-165, 68), (-140, 70), (-115, 72), (-95, 73), (-80, 68), (-65, 60), (-55, 50), (-68, 44), (-76, 38), (-81, 31), (-80, 25),
     (-90, 29), (-97, 26), (-97, 20), (-90, 16), (-83, 9), (-78, 8), (-86, 14), (-95, 16), (-105, 21), (-112, 29), (-118, 34),
     (-124, 42), (-125, 49), (-135, 57), (-150, 60), (-165, 60)],
    [(-80, 9), (-72, 12), (-62, 10), (-50, 0), (-35, -5), (-38, -15), (-42, -23), (-48, -28), (-58, -38), (-65, -42), (-68, -52),
     (-74, -50), (-73, -38), (-71, -25), (-70, -18), (-76, -14), (-81, -5)],
    [(-17, 21), (-16, 28), (-9, 35), (10, 37), (20, 32), (32, 31), (35, 28), (43, 12), (51, 11), (42, -2), (40, -15), (35, -24),
     (32, -29), (20, -35), (17, -29), (13, -17), (12, -6), (9, 4), (-5, 5), (-12, 7), (-17, 14)],
    [(-10, 36), (-9, 43), (-2, 44), (-4, 48), (2, 51), (8, 54), (10, 58), (5, 62), (15, 69), (25, 71), (40, 67), (60, 70), (75, 73),
     (100, 77), (130, 72), (160, 70), (180, 68), (178, 62), (163, 57), (156, 51), (142, 54), (135, 44), (128, 35), (122, 31),
     (120, 23), (108, 18), (106, 10), (100, 13), (99, 7), (95, 16), (90, 22), (80, 12), (77, 8), (72, 21), (66, 25), (57, 26),
     (52, 18), (44, 12), (35, 28), (34, 36), (27, 37), (23, 37), (20, 40), (12, 44), (15, 38), (8, 44), (3, 43), (-5, 36)],
    [(114, -22), (122, -17), (130, -12), (137, -12), (142, -11), (146, -19), (153, -26), (150, -37), (141, -38), (131, -31), (115, -34)],
    [(-55, 60), (-43, 60), (-22, 70), (-20, 80), (-35, 83), (-60, 82), (-72, 77), (-60, 70)],
    [(43, -12), (50, -15), (47, -25), (44, -24)], [(-6, 50), (2, 51), (-2, 58), (-6, 58)],
    [(130, 31), (140, 35), (142, 42), (141, 45), (139, 40), (132, 34)], [(109, 1), (118, 7), (119, 0), (116, -4), (110, -3)],
    [(95, 5), (104, -2), (106, -6), (100, -3)],
]


def globe_land(radius, turn):
    """The continents as smooth shapes lying on the globe (LAND's outlines cut into small triangles, each corner put on
    a sphere of `radius`; `turn` degrees of longitude to the camera)."""
    bm = bmesh.new()
    for poly in LAND:
        pts = []
        for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
            n = max(1, int(math.hypot(x1 - x0, y1 - y0) / 8))
            pts += [(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n) for k in range(n)]
        bm.faces.new([bm.verts.new((lon, lat, 0)) for lon, lat in pts])
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY", ngon_method="EAR_CLIP")
    for _ in range(8):  # (no long edge: a long one would cut under the sea)
        long = [e for e in bm.edges if e.calc_length() > 15.0]
        if not long:
            break
        bmesh.ops.subdivide_edges(bm, edges=long, cuts=1)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY", ngon_method="BEAUTY")
    for v in bm.verts:
        lon, lat = math.radians(v.co.x - turn), math.radians(v.co.y)
        v.co = Vector((math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))) * radius
    bm.normal_update()
    bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.normal.dot(f.calc_center_median()) < 0])
    return bm


def old_globe(W, H, D):
    """A library globe: the turned stand on three cabriole legs, the horizon ring and its paper band on three arms,
    the brass meridian and its pivots, the globe tilted like the earth (Europe and Africa to the front)."""
    lathe("Column", [(0.001, 0.36), (0.14, 0.36), (0.16, 0.41), (0.13, 0.49), (0.075, 0.57), (0.06, 0.7), (0.09, 0.78),
                     (0.11, 0.82), (0.08, 0.88), (0.06, 0.98), (0.085, 1.04), (0.15, 1.08), (0.15, 1.12), (0.001, 1.12)],
          (0, 0, 0), "wood", seg=16)
    lathe("Cradle", [(0.001, 1.12), (0.07, 1.12), (0.08, 1.17), (0.06, 1.17), (0.05, 1.14), (0.001, 1.14)], (0, 0, 0), "brass", seg=12)
    for k in range(3):
        a = math.pi / 2 + k * 2 * math.pi / 3
        c, s = math.cos(a), math.sin(a)
        sweep("Leg", bezier((0.08 * c, 0.08 * s, 0.46), (0.42 * c, 0.42 * s, 0.56), (0.5 * c, 0.5 * s, 0.06), (0.68 * c, 0.68 * s, 0.05), 10),
              0.065, "wood", seg=6, r1=0.04)
        ball("Toe", 0.05, (0.7 * c, 0.7 * s, 0.05), "brass", seg=8, rings=5)
        b = a + math.pi / 3
        c, s = math.cos(b), math.sin(b)
        sweep("Arm", bezier((0.1 * c, 0.1 * s, 1.1), (0.5 * c, 0.5 * s, 1.1), (0.78 * c, 0.78 * s, 1.4), (0.74 * c, 0.74 * s, 1.83), 10),
              0.03, "wood", seg=5)
    lathe("Horizon", [(0.68, 1.83), (0.8, 1.83), (0.8, 1.865), (0.68, 1.865)], (0, 0, 0), "wood", seg=32)
    lathe("Horizon paper", [(0.695, 1.865), (0.785, 1.865), (0.785, 1.869), (0.695, 1.869)], (0, 0, 0), "parchment", seg=32)
    for k in range(12):
        a = k * math.pi / 6
        box("Tick", (0.04, 0.008, 0.003), (math.cos(a) * 0.765, math.sin(a) * 0.765, 1.8695), "black", r=0, rot=euler(rz=a))
    tilt = Matrix.Translation(CUR + Vector((0, 0, 1.85))) @ euler(ry=0.41)  # (the earth's tilt, to the side)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=0.65)
    for f in bm.faces:  # (Antarctica: the sphere's own bottom rings)
        f.material_index = 1 if f.calc_center_median().z < -0.6 else 0
    obj("Globe", bm, ["ocean", "parchment"]).matrix_world = tilt
    obj("Continents", globe_land(0.66, GLOBE_TURN), "parchment").matrix_world = tilt
    torus("Meridian", 0.695, 0.022, (0, 0, 1.85), "brass", axis="Y", seg=32, ring_seg=5)
    axis = Vector((math.sin(0.41), 0, math.cos(0.41)))
    for s in (-1, 1):
        cyl("Pivot", 0.028, 0.07, tuple(Vector((0, 0, 1.85)) + axis * s * 0.675), "brass", seg=10, edge=0, rot=towards(axis))
        ball("Pivot cap", 0.035, tuple(Vector((0, 0, 1.85)) + axis * s * 0.725), "brass", seg=8, rings=5)


GLOBE_TURN = 136  # (degrees: which longitude faces the catalogue's camera)


def stag_head(W, H, D):
    """A hunting lodge's stag on its oak shield, stood on its foot board: the neck and the head looking a little down,
    glass eyes, the ears, the antlers (a beam with brow, bez and trez tines and a crown fork), the brass plate."""
    box("Foot", (1.2, 0.95, 0.12), (0, 0.37, 0.06), "wood2", r=0.03)
    right = spline([(0, 0.13), (0.3, 0.19), (0.52, 0.38), (0.63, 0.7), (0.65, 1.1), (0.63, 1.45), (0.56, 1.7), (0.42, 1.88),
                    (0.22, 1.97), (0, 2.0)], 3)
    shield = right + [(-x, z) for x, z in reversed(right[1:-1])]
    prism("Shield", shield, 0.695, 0.845, "wood", r=0.035, seg=2)
    sweep("Moulding", [(x * 0.9, 0.702, 1.065 + (z - 1.065) * 0.92) for x, z in shield[::2]], 0.025, "wood", seg=6, closed=True)
    box("Plate", (0.7, 0.02, 0.18), (0, 0.685, 0.45), "brass", r=0.005)  # (the game prints ALPSPITZE 1931 on it)
    sweep("Neck", bezier((0, 0.72, 1.22), (0, 0.4, 1.25), (0, 0.12, 1.5), (0, -0.04, 1.8), 8), 0.4, "fur", seg=16, r1=0.29, scale=(0.85, 1.12))
    ball("Skull", 0.3, (0, -0.06, 1.95), "fur", scale=(0.95, 1.1, 0.9), seg=16)
    sweep("Snout", bezier((0, -0.16, 1.93), (0, -0.4, 1.86), (0, -0.55, 1.7), (0, -0.66, 1.56), 8), 0.22, "fur", seg=14, r1=0.12, scale=(0.78, 1.0))
    ball("Muzzle", 0.135, (0, -0.68, 1.55), "fur", scale=(0.9, 1.0, 0.85), seg=12)
    ball("Nose", 0.075, (0, -0.775, 1.55), "black", scale=(1.2, 0.7, 0.8), seg=10, rings=6)
    for s in (-1, 1):
        ball("Eye", 0.05, (s * 0.23, -0.27, 1.9), "black", seg=10, rings=6)
        ball("Ear", 0.2, (s * 0.36, 0.0, 2.12), "fur", scale=(0.5, 0.22, 1.0), rot=euler(ry=s * 0.9), seg=10, rings=6)
        ball("Inner ear", 0.15, (s * 0.37, -0.035, 2.12), "bone", scale=(0.4, 0.1, 0.9), rot=euler(ry=s * 0.9), seg=8, rings=5)
        beam = spline([(s * 0.13, 0.0, 2.16), (s * 0.35, 0.05, 2.33), (s * 0.62, 0.1, 2.5), (s * 0.92, 0.16, 2.72), (s * 1.15, 0.2, 2.98),
                       (s * 1.28, 0.2, 3.22)], 3)
        sweep("Antler", beam, 0.075, "bone", seg=7, r1=0.032)
        torus("Burr", 0.075, 0.025, beam[0], "bone", seg=10, ring_seg=4, rot=towards(Vector(beam[1]) - Vector(beam[0])))
        for k, mid, tip in ((2, (s * 0.08, -0.22, 0.15), (s * 0.12, -0.38, 0.32)), (6, (s * 0.02, -0.2, 0.22), (s * 0.0, -0.28, 0.42)),
                            (10, (s * -0.02, -0.12, 0.25), (s * -0.05, -0.15, 0.43)), (12, (s * 0.12, 0.05, 0.12), (s * 0.18, 0.08, 0.2))):
            base = Vector(beam[k])
            sweep("Tine", spline([tuple(base), tuple(base + Vector(mid)), tuple(base + Vector(tip))], 3), 0.045, "bone", seg=5, r1=0.012)


def gold_record(W, H, D):
    """A gold disc award in its lacquered shadow box: the velvet mount, the gold record with its grooves and label (open,
    no glass dulling the gold), the gilt fillet; the engraved plate on the frame's wide base; cardboard corners and a
    strut for the move."""
    rect_frame("Frame", 1.07, 1.285, [(0, 0.1), (0, -0.08), (0.015, -0.115), (0.05, -0.13), (0.1, -0.125), (0.14, -0.105),
                                      (0.17, -0.085), (0.17, 0.1)], "lacquer", place=Matrix.Translation((0, 0, 1.315)))
    box("Base panel", (1.82, 0.23, 0.48), (0, -0.015, 0.44), "lacquer", r=0.01)
    rect_frame("Fillet", 0.9, 0.885, [(0, 0.04), (0, -0.1), (0.02, -0.11), (0.04, -0.1), (0.04, 0.04)], "gilt",
               place=Matrix.Translation((0, 0, 1.545)))
    box("Mount", (1.8, 0.02, 1.77), (0, 0.05, 1.545), "velvet", r=0)
    grooves = []
    for k in range(7):
        r = 0.66 - k * 0.06
        grooves += [(r, 0.026), (r - 0.03, 0.021)]
    lathe("Record", [(0.001, 0.0), (0.7, 0.0), (0.7, 0.018), (0.69, 0.026)] + grooves + [(0.235, 0.024), (0.001, 0.024)],
          (0, 0.04, 1.545), "gilt", seg=32, rot=euler(rx=math.pi / 2))
    cyl("Label", 0.215, 0.008, (0, 0.009, 1.545), "accent", axis="Y", seg=28, edge=0)
    cyl("Hole", 0.025, 0.004, (0, 0.003, 1.545), "black", axis="Y", seg=12, edge=0)
    box("Plate", (1.2, 0.03, 0.3), (0, -0.145, 0.45), "brass", r=0.008)  # (the game prints 1,000,000 SOLD on it)
    for s in (-1, 1):
        box("Corner", (0.3, 0.29, 0.3), (s * 0.95, -0.005, 0.15), "card", r=0.02)
    box("Strut", (0.3, 0.04, 2.0), (0, 0.135, 1.0), "card", r=0.01, rot=euler(rx=0.045))


def ship_bottle(W, H, D):
    """Grandad's ship in a bottle on its cradle stand: a three-master under sail on a putty sea, the cork sealed in red
    wax, the brass plaque on the stand."""
    box("Base", (1.8, 0.7, 0.12), (0, 0, 0.06), "wood", r=0.035, seg=3)
    box("Plaque", (0.5, 0.012, 0.07), (0, -0.355, 0.06), "brass", r=0.004)
    side = Matrix.Rotation(math.pi / 2, 4, "Z")  # (an outline drawn as y, z and pushed along x)
    for x in (-0.55, 0.42):
        prism("Cradle", [(-0.3, 0.12), (0.3, 0.12)] + arc(0, 0.85, 0.42, -0.775, -math.pi + 0.775, 10), -0.06, 0.06, "wood2",
              r=0.015, seg=1, at=(x, 0, 0), rot=side)
    along = euler(ry=math.pi / 2)
    lathe("Bottle", [(0.001, 0.07), (0.15, 0.035), (0.34, 0.0), (0.39, 0.02), (0.4, 0.08), (0.4, 1.22), (0.385, 1.33), (0.33, 1.44),
                     (0.22, 1.54), (0.155, 1.62), (0.14, 1.72), (0.142, 1.8), (0.158, 1.82), (0.158, 1.86), (0.14, 1.875),
                     (0.118, 1.875), (0.118, 1.64), (0.18, 1.55), (0.3, 1.44), (0.36, 1.33), (0.378, 1.22), (0.378, 0.08),
                     (0.36, 0.04), (0.15, 0.06), (0.001, 0.095)], (-0.92, 0, 0.85), "crystal", seg=24, rot=along)
    lathe("Cork", [(0.001, 1.7), (0.112, 1.7), (0.122, 1.88), (0.118, 1.95), (0.001, 1.95)], (-0.92, 0, 0.85), "wicker", seg=16, rot=along)
    lathe("Seal", [(0.001, 1.93), (0.13, 1.93), (0.14, 1.96), (0.12, 2.0), (0.001, 2.0)], (-0.92, 0, 0.85), "red", seg=16, rot=along)
    prism("Sea", arc(0, 0.85, 0.365, -0.75, -math.pi + 0.75, 14), -0.3, 0.82, "ocean", r=0.02, rot=side)
    for x, y in ((-0.75, 0.1), (-0.05, -0.15), (0.2, 0.12), (-0.6, -0.16), (0.12, -0.02)):
        ball("Wave", 0.09, (x, y, 0.6), "ocean", scale=(1.6, 1, 0.35), seg=8, rings=4)
    ball("Hull", 0.4, (-0.27, 0, 0.6), "lacquer", scale=(1, 0.24, 0.3), seg=16)
    box("Deck", (0.62, 0.15, 0.02), (-0.25, 0, 0.71), "wood2", r=0.005)
    box("Stern castle", (0.16, 0.12, 0.08), (-0.56, 0, 0.74), "lacquer", r=0.01)
    tube("Bowsprit", (0.08, 0, 0.72), (0.32, 0, 0.82), 0.01, "wood2", 6)
    for x, h in ((0.0, 0.42), (-0.25, 0.48), (-0.5, 0.38)):
        cyl("Mast", 0.011, h, (x, 0, 0.72 + h / 2), "wood2", seg=6, edge=0)
        for z0, z1, hw in ((0.76, 0.72 + h * 0.5, 0.13), (0.72 + h * 0.56, 0.72 + h * 0.88, 0.1)):
            sail(x, z0, z1, hw, 0.05)
            for z in (z0, z1):
                cyl("Yard", 0.006, 2 * hw + 0.04, (x + 0.01, 0, z), "wood2", axis="Y", seg=5, edge=0)
        box("Pennant", (0.08, 0.004, 0.03), (x - 0.04, 0, 0.72 + h - 0.02), "red", r=0)
    bm = bmesh.new()
    for off in (-0.002, 0.002):
        vs = [bm.verts.new(CUR + Vector(v)) for v in ((0.01, off, 1.05), (0.3, off, 0.82), (0.04, off, 0.79))]
        bm.faces.new(vs if off < 0 else list(reversed(vs)))
    obj("Jib", bm, "cream", smooth=False)


def sail(x, z0, z1, hw, bulge):
    """A square sail billowing to the bow (+x): two thin sheets (both sides show)."""
    bm = bmesh.new()
    for off, flip in ((0.0, False), (-0.004, True)):
        grid = [[bm.verts.new(CUR + Vector((x + off + 0.012 + bulge * (1 - (u / hw) ** 2) * math.sin(math.pi * v), u, z0 + (z1 - z0) * v)))
                 for u in (-hw, -hw / 2, 0, hw / 2, hw)] for v in (0, 0.5, 1)]
        for i in range(2):
            for j in range(4):
                f = [grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]]
                bm.faces.new(list(reversed(f)) if flip else f)
    obj("Sail", bm, "cream")


def jewellery_box(W, H, D):
    """Grandma's jewellery box, its lid open: the lacquered case on gilt ball feet, its gilt bands, a drawer and a
    mother-of-pearl inlay, the velvet tray with ring rolls and two rings, her pearls spilling over the front, the oval
    mirror in the lid, the music box's ballerina and its key."""
    for sx in (-1, 1):
        for sy in (-0.42, 0.22):
            ball("Foot", 0.05, (sx * 0.68, sy, 0.05), "gilt", seg=8, rings=5)
    box("Case", (1.5, 0.75, 0.42), (0, -0.1, 0.29), "lacquer", r=0.035, seg=3)
    for z in (0.1, 0.482):
        box("Band", (1.53, 0.78, 0.035), (0, -0.1, z), "gilt", r=0.012)
    box("Drawer", (1.1, 0.02, 0.15), (0, -0.48, 0.22), "lacquer", r=0.008)
    ball("Pull", 0.04, (0, -0.505, 0.22), "gilt", seg=8, rings=5)
    cyl("Inlay", 0.06, 0.008, (0, -0.477, 0.37), "ceramic", axis="Y", seg=20, edge=0, rot=Matrix.Diagonal((3.2, 1, 1, 1)))
    sweep("Inlay rim", [(0.205 * math.cos(a), -0.48, 0.37 + 0.072 * math.sin(a)) for a in (2 * math.pi * k / 24 for k in range(24))],
          0.01, "gilt", seg=4, closed=True)
    box("Tray", (1.42, 0.68, 0.03), (0, -0.1, 0.505), "velvet", r=0.01)
    for y in (-0.32, -0.22):
        cyl("Ring roll", 0.045, 0.6, (-0.33, y, 0.545), "velvet", axis="X", seg=12, edge=0)
    for x, stone in ((-0.45, "crystal"), (-0.2, "red")):
        torus("Ring", 0.055, 0.011, (x, -0.27, 0.6), "gilt", axis="Y", seg=16, ring_seg=4)
        ball("Stone", 0.03, (x, -0.27, 0.665), stone, seg=8, rings=4, scale=(1, 1, 1.25))
    hinge = Matrix.Translation((0, 0.275, 0.5)) @ euler(rx=-0.2)  # the lid open on the case's back top edge, leaning back
    lid = box("Lid", (1.5, 0.07, 0.68), (0, 0, 0), "lacquer", r=0.03, seg=3)
    lid.matrix_world = Matrix.Translation(CUR) @ hinge @ Matrix.Translation((0, 0.035, 0.34))
    band = box("Lid band", (1.53, 0.075, 0.035), (0, 0, 0), "gilt", r=0.012)
    band.matrix_world = Matrix.Translation(CUR) @ hinge @ Matrix.Translation((0, 0.035, 0.66))
    glass = cyl("Mirror", 0.24, 0.006, (0, 0, 0), "mirror", seg=40, edge=0)
    glass.matrix_world = Matrix.Translation(CUR) @ hinge @ Matrix.Translation((0, -0.003, 0.36)) @ Matrix.Diagonal((1.9, 1, 1, 1)) @ euler(rx=math.pi / 2)
    sweep("Mirror frame", [tuple(hinge @ Vector((0.47 * math.cos(a), -0.008, 0.36 + 0.252 * math.sin(a)))) for a in (2 * math.pi * k / 32 for k in range(32))],
          0.018, "gilt", seg=5, closed=True)
    pearls = spline([(0.55, -0.2, 0.535), (0.47, -0.4, 0.535), (0.44, -0.475, 0.5), (0.44, -0.505, 0.4), (0.4, -0.51, 0.31),
                     (0.32, -0.505, 0.36), (0.28, -0.5, 0.45), (0.26, -0.47, 0.515), (0.3, -0.33, 0.54), (0.45, -0.25, 0.54)], 6)
    path = [Vector(p) for p in pearls]
    left, step = 0.0, 0.054
    for a, b in zip(path, path[1:]):
        seg_len = (b - a).length
        while left <= seg_len:
            ball("Pearl", 0.026, tuple(a + (b - a) * (left / seg_len)), "ceramic", seg=6, rings=4)
            left += step
        left -= seg_len
    ball("Pendant", 0.035, (0.4, -0.508, 0.255), "red", scale=(1, 0.7, 1.25), seg=8, rings=5)
    bx, by = 0.15, 0.0  # the ballerina on her spindle, in front of the mirror
    cyl("Spindle base", 0.06, 0.012, (bx, by, 0.526), "gilt", seg=16, edge=0)
    cyl("Spindle", 0.012, 0.06, (bx, by, 0.55), "gilt", seg=8, edge=0)
    tube("Leg", (bx, by, 0.58), (bx, by, 0.705), 0.011, "ceramic", 6)
    tube("Thigh", (bx + 0.01, by, 0.7), (bx + 0.06, by, 0.655), 0.011, "ceramic", 6)
    tube("Shin", (bx + 0.06, by, 0.655), (bx + 0.012, by, 0.62), 0.009, "ceramic", 6)
    lathe("Tutu", [(0.025, 0.695), (0.09, 0.688), (0.1, 0.698), (0.085, 0.712), (0.025, 0.725)], (bx, by, 0), "accent", seg=14)
    ball("Bodice", 0.03, (bx, by, 0.75), "accent", scale=(0.9, 0.7, 1.4), seg=8, rings=5)
    ball("Head", 0.022, (bx, by, 0.815), "ceramic", seg=8, rings=5)
    for s in (-1, 1):
        sweep("Arm", spline([(bx + s * 0.025, by, 0.775), (bx + s * 0.05, by, 0.82), (bx + s * 0.02, by, 0.86)], 3), 0.006, "ceramic", seg=5)
    cyl("Key", 0.012, 0.06, (0.78, -0.1, 0.3), "brass", axis="X", seg=8, edge=0)
    for s in (-1, 1):
        torus("Key bow", 0.028, 0.007, (0.815, -0.1, 0.3 + s * 0.032), "brass", axis="X", seg=12, ring_seg=4)


VASE = [(0.001, 0.24), (0.3, 0.24), (0.312, 0.26), (0.3, 0.3), (0.285, 0.32), (0.33, 0.4), (0.45, 0.6), (0.58, 0.85),
        (0.645, 1.1), (0.65, 1.25), (0.62, 1.42), (0.53, 1.6), (0.4, 1.76), (0.27, 1.9), (0.205, 2.02), (0.19, 2.15), (0.2, 2.3),
        (0.24, 2.45), (0.3, 2.57), (0.33, 2.64), (0.335, 2.675)]  # the vase's outside (radius, height); then its mouth inside
VASE_MOUTH = [(0.3, 2.685), (0.28, 2.66), (0.22, 2.55), (0.17, 2.42), (0.001, 2.38)]


def vase_radius(z):
    for (r0, z0), (r1, z1) in zip(VASE[4:], VASE[5:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return VASE[-1][0]


def antique_vase(W, H, D):
    """A blue-and-white porcelain baluster vase on its carved rosewood stand: lotus petals round the foot, peonies on a
    scrolling vine round the belly, a cloud collar on the shoulder, banana leaves up the neck, cobalt bands between,
    the gilt rim and two gilt mask-and-ring handles."""
    lathe("Stand top", [(0.001, 0.18), (0.5, 0.18), (0.53, 0.2), (0.52, 0.235), (0.48, 0.24), (0.001, 0.24)], (0, 0, 0), "wood2", seg=24)
    lathe("Apron", [(0.44, 0.1), (0.48, 0.1), (0.5, 0.18), (0.44, 0.18)], (0, 0, 0), "wood2", seg=24)
    torus("Base ring", 0.55, 0.03, (0, 0, 0.03), "wood2", seg=24, ring_seg=4)
    for k in range(5):
        a = math.pi / 2 + k * 2 * math.pi / 5
        c, s = math.cos(a), math.sin(a)
        sweep("Foot", bezier((0.46 * c, 0.46 * s, 0.15), (0.57 * c, 0.57 * s, 0.15), (0.61 * c, 0.61 * s, 0.07), (0.55 * c, 0.55 * s, 0.03), 6),
              0.042, "wood2", seg=5, r1=0.03)
    lathe("Body", VASE + VASE_MOUTH, (0, 0, 0), "porcelain", seg=24)
    paint, white = bmesh.new(), bmesh.new()

    def on(bm, theta, z, off=0.005):
        r = vase_radius(z) + off
        return bm.verts.new(CUR + Vector((r * math.cos(theta), r * math.sin(theta), z)))

    def patch(theta, z0, z1, width, shape, rows=4, cols=2):
        """A painted shape on the porcelain: rows from z0 to z1 (down when z1 < z0), `width` × shape(v) to each side."""
        grid = []
        for i in range(rows + 1):
            v = i / rows
            z = z0 + (z1 - z0) * v
            w = width * max(0.03, shape(v))
            grid.append([on(paint, theta + (-1 + 2 * j / cols) * w / vase_radius(z), z) for j in range(cols + 1)])
        for i in range(rows):
            for j in range(cols):
                f = [grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]]
                paint.faces.new(f if z1 > z0 else list(reversed(f)))

    def band(za, zb, n=32):
        lo = [on(paint, 2 * math.pi * k / n, za) for k in range(n)]
        hi = [on(paint, 2 * math.pi * k / n, zb) for k in range(n)]
        for k in range(n):
            paint.faces.new((lo[k], lo[(k + 1) % n], hi[(k + 1) % n], hi[k]))

    def flower(bm, theta, zc, size, lobes, off):
        centre = on(bm, theta, zc, off)
        ring = []
        for k in range(30):
            phi = 2 * math.pi * k / 30
            rho = size * (0.74 + 0.26 * math.cos(lobes * phi))
            dz = rho * math.sin(phi)
            ring.append(on(bm, theta + rho * math.cos(phi) / vase_radius(zc + dz), zc + dz, off))
        for k in range(30):
            bm.faces.new((centre, ring[k], ring[(k + 1) % 30]))

    for za, zb in ((0.335, 0.355), (0.665, 0.69), (1.5, 1.525), (1.985, 2.015), (2.47, 2.495)):
        band(za, zb)
    for k in range(12):  # lotus petals round the foot
        patch(2 * math.pi * k / 12, 0.37, 0.64, 0.085, lambda v: (1 - v * v) * (0.7 + 0.3 * math.sin(math.pi * v)))
    for k in range(8):  # the cloud collar hanging from the shoulder
        patch(2 * math.pi * (k + 0.5) / 8, 1.49, 1.3, 0.16, lambda v: (1 - v ** 3) * (0.55 + 0.45 * math.sin(math.pi * v)))
    for k in range(8):  # banana leaves up the neck
        patch(2 * math.pi * k / 8, 2.03, 2.44, 0.07, lambda v: math.sin(math.pi * (0.15 + 0.85 * v)) ** 0.8 * (1 - v ** 3), rows=5)
    front = -2.1  # (the peony that faces the catalogue's camera)
    for k in range(4):
        theta = front + k * math.pi / 2
        flower(paint, theta, 1.08, 0.17, 5, 0.006)
        flower(white, theta, 1.08, 0.06, 5, 0.009)
        flower(paint, theta, 1.08, 0.022, 1, 0.011)
    obj("Pattern", paint, "cobalt")
    obj("Flower hearts", white, "porcelain")
    vine = []
    for k in range(40):
        theta = front + 2 * math.pi * k / 40
        z = 1.08 + 0.16 * math.sin(4 * (theta - front))  # (through every peony's heart, up and down between them)
        r = vase_radius(z) + 0.004
        vine.append((r * math.cos(theta), r * math.sin(theta), z))
    sweep("Vine", vine, 0.012, "cobalt", seg=4, closed=True)
    torus("Rim", 0.318, 0.016, (0, 0, 2.678), "gilt", seg=28, ring_seg=4)
    for s in (-1, 1):
        ball("Mask", 0.045, (s * 0.2, 0, 2.21), "gilt", scale=(0.6, 1, 1.1), seg=8, rings=6)
        torus("Ring", 0.065, 0.012, (s * 0.232, 0, 2.135), "gilt", axis="X", seg=12, ring_seg=4)


CRAB = ["..#.....#..", "...#...#...", "..#######..", ".##.###.##.", "###########", "#.#######.#", "#.#.....#.#", "...##.##..."]
SQUID = ["...##...", "..####..", ".######.", "##.##.##", "########", "..#..#..", ".#.##.#.", "#.#..#.#"]
OCTOPUS = ["....####....", ".##########.", "############", "###..##..###", "############", "...##..##...", "..##.##.##..", "##........##"]
SHIP = [".....#.....", "....###....", ".#########.", "###########", "###########"]
UFO = ["....######....", "..##########..", ".############.", "##.##.##.##.##", "##############", "..###..##..###"]
BUNKER = ["...######...", "..########..", ".##########.", "############", "####....####", "###......###"]


def arcade_cabinet(W, H, D):
    """An eighties upright arcade machine: painted side panels with white stripes, the black cabinet, the control panel
    jutting out with its stick and six buttons, the coin door and its lit slots, the screen tilted back in its bezel with
    a game of space invaders on it, the lit marquee (the game prints the game's name on it)."""
    turn = Matrix.Rotation(math.pi / 2, 4, "Z")  # (side-view outlines: y, z, pushed along x)
    side = [(1.45, 0.0), (1.45, 5.72), (1.18, 5.99), (-0.715, 5.99), (-0.715, 5.12), (-0.5, 5.05), (-0.69, 3.36), (-0.715, 3.3), (-0.715, 0.0)]
    for s in (-1, 1):
        y0, y1 = sorted((-s * 1.39, -s * 1.29))
        prism("Side", side, y0, y1, "accent", r=0.03, rot=turn)
        a, b = sorted((-s * 1.4, -s * 1.39))
        prism("Stripe", [(1.42, 0.85), (1.42, 1.25), (-0.6, 3.15), (-0.6, 2.75)], a, b, "white", r=0, rot=turn)
        prism("Stripe", [(1.42, 1.45), (1.42, 1.65), (-0.55, 3.5), (-0.55, 3.3)], a, b, "white", r=0, rot=turn)
    box("Body", (2.58, 2.1, 2.9), (0, 0.37, 1.45), "black", r=0.02)
    box("Kick plate", (2.4, 0.02, 0.25), (0, -0.69, 0.16), "steel", r=0.01)
    box("Coin door", (0.9, 0.03, 1.0), (0, -0.695, 1.45), "steel", r=0.02)
    for x in (-0.18, 0.18):
        box("Coin slot", (0.14, 0.012, 0.22), (x, -0.712, 1.7), "neon", r=0.004)
        box("Coin return", (0.16, 0.02, 0.1), (x, -0.715, 1.3), "red", r=0.01, seg=1)
    prism("Control panel", [(-0.68, 2.86), (-1.4, 2.86), (-1.45, 2.91), (-1.45, 3.07), (-1.41, 3.12), (-0.68, 3.33)], -1.4, 1.4,
          "black", r=0.025, rot=turn)
    box("Panel trim", (2.8, 0.03, 0.17), (0, -1.46, 2.99), "steel", r=0.01)
    slope = euler(rx=0.28)

    def deck(x, y):  # a point on the control panel's sloping top, and the turn to stand on it
        return Vector((x, y, 3.12 + (y + 1.41) * 0.21 / 0.73))

    up = Vector((0, -math.sin(0.28), math.cos(0.28)))
    base = deck(-0.6, -1.08)
    cyl("Stick base", 0.1, 0.02, tuple(base), "steel", seg=16, edge=0.005, rot=slope)
    cyl("Stick", 0.022, 0.28, tuple(base + up * 0.14), "steel", seg=8, edge=0, rot=slope)
    ball("Stick top", 0.08, tuple(base + up * 0.3), "red", seg=10)
    for i, y in enumerate((-1.16, -0.94)):
        for j, colour in enumerate(("red", "sun", "cobalt")):
            lathe("Button", [(0.001, 0), (0.075, 0), (0.07, 0.035), (0.001, 0.045)], tuple(deck(0.05 + j * 0.24 + i * 0.06, y)), colour, seg=12, rot=slope)
    for x in (-0.28, -0.08):
        box("Start", (0.12, 0.08, 0.03), tuple(deck(x, -0.8)), "white", r=0.01, rot=slope)
    prism("Head", [(-0.665, 3.3), (-0.485, 5.06), (-0.6, 5.12), (-0.6, 5.95), (1.42, 5.95), (1.42, 3.3)], -1.29, 1.29, "dark", r=0.02, rot=turn)
    box("Top", (2.8, 1.91, 0.05), (0, 0.245, 5.975), "dark", r=0.015)
    box("Marquee lip", (2.58, 0.1, 0.06), (0, -0.66, 5.17), "dark", r=0.01)
    box("Marquee", (2.5, 0.12, 0.6), (0, -0.66, 5.5), "neon", r=0.015)  # (the game prints the game's name on it)
    tilt = math.atan2(0.18, 1.76)
    normal = Vector((0, -math.cos(tilt), math.sin(tilt)))
    screen = Matrix.Translation(Vector((0, -0.573, 4.2)) + normal * 0.012) @ euler(rx=-tilt)
    rect_frame("Bezel", 1.08, 0.86, [(0, 0.0), (0, -0.03), (0.04, -0.04), (0.12, -0.02), (0.12, 0.0)], "dark", place=screen)
    box("Screen", (1.9, 0.02, 1.45), (0, 0, 0), "glass", r=0.03).matrix_world = Matrix.Translation(CUR) @ screen
    for row, (rows, z) in enumerate(((SQUID, 0.5), (CRAB, 0.3), (OCTOPUS, 0.1))):
        for col in range(5):
            sprite("Invader", rows, 0.018, "neon", screen @ Matrix.Translation((-0.62 + col * 0.31 + (row % 2) * 0.05, -0.012, z)))
    sprite("Ufo", UFO, 0.016, "red", screen @ Matrix.Translation((0.45, -0.012, 0.66)))
    for x in (-0.55, 0.0, 0.55):
        sprite("Bunker", BUNKER, 0.016, "leaf2", screen @ Matrix.Translation((x, -0.012, -0.36)))
    sprite("Ship", SHIP, 0.018, "glow", screen @ Matrix.Translation((-0.2, -0.012, -0.58)))
    sprite("Shot", ["#", "#", "#", "#"], 0.016, "glow", screen @ Matrix.Translation((-0.2, -0.012, -0.2)))


def jukebox(W, H, D):
    """A forties jukebox: the wooden cabinet under its round top, the bubble tubes glowing amber and red up the sides and
    round the arch, the dome window over the record rack and the turntable (lit warm from behind), the title strip (the
    game prints HIT PARADE on it) and the selector keys, the lit medallion and the chrome grille, the coin slot."""
    box("Plinth", (3.4, 2.36, 0.3), (0, 0.06, 0.15), "wood2", r=0.05, seg=2)
    box("Body", (2.9, 2.1, 3.05), (0, 0.05, 0.3 + 1.525), "wood", r=0.04, seg=2)
    prism("Crown", [(-1.45, 3.3), (1.45, 3.3)] + arc(0, 3.85, 1.45, 0, math.pi, 24), 0.3, 1.1, "wood", r=0.04, seg=1)
    ro, ri, cz = 1.7, 1.3, 3.7
    prism("Frame", [(ri, 0.3), (ro, 0.3)] + arc(0, cz, ro, 0, math.pi, 28) + [(-ro, 0.3), (-ri, 0.3)] + arc(0, cz, ri, math.pi, 0, 24),
          -1.1, 1.0, "wood2", r=0.05, seg=2)
    for rho, finish in ((1.42, "amber"), (1.58, "ember")):
        path = [(rho, -1.12, 0.42), (rho, -1.12, 1.6), (rho, -1.12, 2.8)]
        path += [(rho * math.cos(a), -1.12, cz + rho * math.sin(a)) for a in (math.pi * k / 26 for k in range(27))]
        path += [(-rho, -1.12, 2.8), (-rho, -1.12, 1.6), (-rho, -1.12, 0.42)]
        sweep("Bubble tube", path, 0.065, finish, seg=8)
        for s in (-1, 1):
            cyl("Ferrule", 0.075, 0.12, (s * rho, -1.12, 0.42), "chrome", seg=10, edge=0)
    window = [(-1.25, 3.35), (1.25, 3.35)] + arc(0, cz, 1.25, 0, math.pi, 30)
    prism("Window", window, -1.06, -1.04, "crystal", r=0)
    prism("Backlight", window, 0.3, 0.32, "glow", r=0)
    sweep("Window light", [(1.27, -1.0, 3.38)] + [(1.27 * math.cos(a), -1.0, cz + 1.27 * math.sin(a)) for a in (math.pi * k / 24 for k in range(25))]
          + [(-1.27, -1.0, 3.38)], 0.03, "glow", seg=6)
    for k in range(5):
        x = -0.3 + k * 0.15
        cyl("Record", 0.42, 0.012, (x, -0.25, 4.15), "black", axis="X", seg=18, edge=0)
        cyl("Label", 0.13, 0.016, (x, -0.25, 4.15), "accent", axis="X", seg=10, edge=0)
    cyl("Rack", 0.03, 0.8, (0, -0.25, 4.15), "chrome", axis="X", seg=8, edge=0)
    cyl("Platter", 0.38, 0.04, (0, -0.6, 3.37), "chrome", seg=24, edge=0)
    cyl("Record", 0.37, 0.015, (0, -0.6, 3.398), "black", seg=24, edge=0)
    cyl("Label", 0.12, 0.017, (0, -0.6, 3.4), "accent", seg=16, edge=0)
    cyl("Arm base", 0.06, 0.12, (0.62, -0.35, 3.41), "chrome", seg=10, edge=0)
    sweep("Tone arm", spline([(0.62, -0.35, 3.47), (0.5, -0.66, 3.47), (0.24, -0.8, 3.44)], 3), 0.016, "chrome", seg=6)
    box("Trim", (2.6, 0.06, 0.08), (0, -1.12, 3.3), "chrome", r=0.02, seg=1)
    box("Titles", (2.2, 0.1, 0.4), (0, -1.15, 2.95), "cream", r=0.01)  # (the game prints HIT PARADE on it)
    rect_frame("Title bezel", 1.14, 0.24, [(0, 0.0), (0, -0.04), (0.02, -0.045), (0.04, -0.035), (0.04, 0.0)], "chrome",
               place=Matrix.Translation((0, -1.15, 2.95)))
    box("Key bank", (2.2, 0.04, 0.24), (0, -1.12, 2.58), "chrome", r=0.01, seg=1)
    for k in range(10):
        box("Key", (0.15, 0.08, 0.13), (-0.9 + k * 0.2, -1.18, 2.58), "white", r=0)
    grille = [(-1.0, 0.55), (1.0, 0.55)] + arc(0, 1.95, 1.0, 0, math.pi, 24, rz=0.45)
    prism("Grille", grille, -1.02, -1.0, "wicker", r=0)
    for k in range(7):
        x = -0.75 + k * 0.25
        top = 1.95 + 0.45 * math.sqrt(1 - x * x) - 0.03
        sweep("Grille bar", [(x, -1.05, 0.58), (x, -1.05, top)], 0.02, "chrome", seg=6)
    cyl("Medallion", 0.24, 0.04, (0, -1.07, 1.45), "amber", axis="Y", seg=24, edge=0)
    torus("Medallion ring", 0.25, 0.03, (0, -1.08, 1.45), "chrome", axis="Y", seg=24, ring_seg=4)
    box("Base trim", (3.0, 0.04, 0.05), (0, -1.12, 0.33), "chrome", r=0.01, seg=1)
    box("Coin plate", (0.18, 0.04, 0.35), (1.5, -1.12, 2.5), "chrome", r=0.02, seg=1)
    box("Coin slot", (0.02, 0.01, 0.12), (1.5, -1.145, 2.55), "black", r=0)


def oil_painting(W, H, D):
    """An old master's alpine sunset in a carved, gilded frame with a linen liner: the evening sky glowing peach and
    gold, the low sun, two ranges with snow on their peaks, the lake and its reflection, the far shore's forest, a meadow,
    fir trees, a chalet with lit windows; the gallery's brass picture light over it (glowing), the title plate on the
    frame (the game prints ALPINE GLOW, 1886 on it), cardboard corners and a strut for the move."""
    place = Matrix.Translation((0, 0, 1.85))
    rect_frame("Frame", 2.4, 1.75, [(0, 0.12), (0, -0.06), (0.02, -0.1), (0.05, -0.13), (0.09, -0.14), (0.13, -0.13), (0.16, -0.1),
                                    (0.24, -0.065), (0.3, -0.07), (0.34, -0.1), (0.37, -0.11), (0.4, -0.09), (0.43, -0.05),
                                    (0.45, -0.035), (0.45, 0.12)], "gilt", place=place)
    rect_frame("Liner", 1.96, 1.31, [(0, 0.04), (0, -0.03), (0.12, -0.012), (0.12, 0.04)], "cream", place=place)
    box("Canvas", (3.7, 0.02, 2.4), (0, 0.03, 1.85), "sky", r=0)
    layer("Glow", [(-1.84, 1.55), (1.84, 1.55), (1.84, 2.25), (1.0, 2.38), (0.0, 2.3), (-1.0, 2.4), (-1.84, 2.22)], 0.018, "peach")
    layer("Glow", [(-1.84, 1.55), (1.84, 1.55), (1.84, 1.95), (0.9, 2.05), (-0.2, 1.98), (-1.84, 1.9)], 0.016, "sun")
    layer("Sun", arc(-0.45, 2.42, 0.15, 0, 2 * math.pi, 24)[:-1], 0.015, "glow")
    far = [(-1.84, 1.55), (1.84, 1.55), (1.84, 1.95), (1.6, 2.05), (1.35, 2.3), (1.15, 2.15), (0.95, 2.4), (0.72, 2.62), (0.5, 2.38),
           (0.3, 2.45), (0.1, 2.25), (-0.15, 2.33), (-0.4, 2.1), (-0.7, 2.2), (-1.0, 2.05), (-1.3, 2.12), (-1.6, 1.98), (-1.84, 2.02)]
    layer("Range", far, 0.013, "rock")
    near = [(-1.84, 1.55), (0.2, 1.55), (-0.1, 1.75), (-0.35, 1.95), (-0.55, 2.05), (-0.8, 2.32), (-0.95, 2.45), (-1.15, 2.3),
            (-1.4, 2.18), (-1.6, 2.0), (-1.84, 1.9)]
    layer("Mountain", near, 0.01, "slate")
    for peak, a, b, y in (((0.72, 2.62), (0.5, 2.38), (0.95, 2.4), 0.012), ((1.35, 2.3), (1.15, 2.15), (1.6, 2.05), 0.012),
                          ((0.3, 2.45), (0.1, 2.25), (0.5, 2.38), 0.012), ((-0.95, 2.45), (-1.15, 2.3), (-0.8, 2.32), 0.009)):
        P, A, B = Vector(peak), Vector(a), Vector(b)
        L, R = P + (A - P) * 0.4, P + (B - P) * 0.4
        cap = [tuple(P), tuple(L), tuple(L.lerp(R, 0.25) + Vector((0, 0.03))), tuple(L.lerp(R, 0.5) - Vector((0, 0.02))),
               tuple(L.lerp(R, 0.75) + Vector((0, 0.03))), tuple(R)]
        layer("Snow", cap, y, "white")
        layer("Alpenglow", [tuple(P), tuple(P.lerp(B, 0.25)), tuple(P.lerp(B, 0.25) - Vector((0.05, 0.03)))], y - 0.0005, "peach", depth=0.002)
    layer("Lake", [(-1.84, 1.25), (1.84, 1.25), (1.84, 1.58), (-1.84, 1.58)], 0.008, "ocean")
    layer("Reflection", [(-0.52, 1.3), (-0.38, 1.3), (-0.41, 1.565), (-0.49, 1.565)], 0.0075, "sun")
    layer("Shore", [(0.3, 1.56), (1.84, 1.56), (1.84, 1.66), (1.5, 1.7), (1.2, 1.64), (0.9, 1.69), (0.6, 1.63), (0.3, 1.6)], 0.007, "leaf")
    layer("Meadow", [(-1.84, 0.66), (1.84, 0.66), (1.84, 1.2), (1.3, 1.32), (0.7, 1.26), (0.1, 1.15), (-0.6, 1.22), (-1.2, 1.35),
                     (-1.84, 1.3)], 0.006, "grass")
    layer("Shade", [(-1.84, 0.66), (0.2, 0.66), (-0.3, 0.85), (-1.0, 0.95), (-1.84, 1.0)], 0.0055, "leaf")
    for x, b, h in ((1.15, 1.15, 0.62), (1.42, 1.1, 0.82), (1.66, 1.12, 0.7), (1.3, 0.95, 0.5)):
        layer("Fir", [(x - 0.15, b), (x + 0.15, b), (x + 0.06, b + 0.38 * h), (x + 0.11, b + 0.38 * h), (x, b + h),
                      (x - 0.11, b + 0.38 * h), (x - 0.06, b + 0.38 * h)], 0.005, "leaf")
    layer("Chalet", [(-0.85, 1.12), (-0.55, 1.12), (-0.55, 1.3), (-0.85, 1.3)], 0.005, "wood2")
    layer("Roof", [(-0.92, 1.28), (-0.48, 1.28), (-0.7, 1.43)], 0.0045, "red")
    for x in (-0.79, -0.61):
        layer("Window", [(x - 0.03, 1.18), (x + 0.03, 1.18), (x + 0.03, 1.24), (x - 0.03, 1.24)], 0.0045, "glow", depth=0.001)
    for cx, cz, out in ((-2.175, 3.375, (1, -1)), (2.175, 3.375, (-1, -1)), (-2.175, 1.85, (1, 0)), (2.175, 1.85, (-1, 0))):
        ornament(cx, cz, out)
    box("Plate", (0.9, 0.08, 0.18), (0, -0.14, 0.24), "brass", r=0.01)  # (the game prints ALPINE GLOW, 1886 on it)
    for s in (-1, 1):
        box("Corner", (0.46, 0.358, 0.5), (s * 2.17, 0, 0.25), "card", r=0.02)
    box("Strut", (0.4, 0.05, 3.0), (0, 0.2, 1.6), "card", r=0.01, rot=euler(rx=0.0467))
    sweep("Lamp arm", spline([(0, 0.06, 3.56), (0, 0.04, 3.68), (0, -0.06, 3.74), (0, -0.17, 3.72)], 3), 0.022, "gold", seg=6)
    cyl("Lamp", 0.075, 1.5, (0, -0.22, 3.7), "gold", axis="X", seg=16)
    for s in (-1, 1):
        cyl("Lamp end", 0.085, 0.03, (s * 0.76, -0.22, 3.7), "gold", axis="X", seg=16, edge=0)
    box("Lamp glow", (1.36, 0.06, 0.012), (0, -0.23, 3.619), "glow", r=0)


def ornament(cx, cz, out):
    """A carved shell on the gilded frame: a boss and three lobes fanning towards `out` (x, z)."""
    centre = Vector((cx, -0.14, cz))
    ball("Boss", 0.06, tuple(centre), "gilt", scale=(1, 0.55, 1), seg=8, rings=5)
    base = math.atan2(out[1], out[0])
    for k in (-1, 0, 1):
        a = base + k * 0.6
        d = Vector((math.cos(a), 0, math.sin(a)))
        ball("Lobe", 0.085, tuple(centre + d * 0.09), "gilt", scale=(1, 0.38, 0.42), rot=euler(ry=-a), seg=8, rings=5)


def knight_armour(W, H, D):
    """A suit of polished plate armour on its oak plinth: sabatons, greaves, knee cops, cuisses, the fauld and tassets, a
    belt, the breastplate with its gilt ridge and edges, the gorget, the pauldrons, the arms, the gauntlets resting on a
    longsword stood point down; the bascinet with its beaked visor and a velvet plume; a shield in the house's colours
    with a gilt chevron leaning on the plinth."""
    box("Plinth", (2.0, 1.6, 0.25), (0, 0, 0.125), "wood2", r=0.05, seg=2)
    box("Plinth top", (1.8, 1.4, 0.1), (0, 0, 0.3), "wood2", r=0.03, seg=1)
    for s in (-1, 1):
        x = s * 0.3
        sweep("Sabaton", spline([(x, 0.14, 0.47), (x, -0.05, 0.47), (x * 1.08, -0.3, 0.44), (x * 1.1, -0.47, 0.4)], 3), 0.14, "steel",
              seg=8, r1=0.04, scale=(1.0, 0.75))
        lathe("Greave", [(0.001, 0.5), (0.13, 0.5), (0.145, 0.62), (0.15, 0.82), (0.18, 1.12), (0.17, 1.38), (0.14, 1.62), (0.13, 1.74),
                         (0.001, 1.74)], (x, 0, 0), "chrome", seg=12, scale=(1, 0.95))
        ball("Poleyn", 0.165, (x, -0.04, 1.8), "chrome", scale=(1, 1.1, 0.85), seg=12, rings=7)
        ball("Poleyn wing", 0.12, (x + s * 0.14, -0.06, 1.8), "chrome", scale=(0.35, 1, 1), seg=8, rings=5)
        lathe("Cuisse", [(0.001, 1.86), (0.17, 1.86), (0.2, 2.15), (0.23, 2.55), (0.24, 2.8), (0.001, 2.8)], (x, 0, 0), "chrome",
              seg=12, scale=(1, 0.95))
        box("Tasset", (0.44, 0.06, 0.3), (s * 0.3, -0.43, 2.62), "chrome", r=0.025, seg=1, rot=euler(rx=0.15))
        box("Tasset", (0.4, 0.06, 0.26), (s * 0.31, -0.46, 2.38), "chrome", r=0.025, seg=1, rot=euler(rx=0.2))
    lathe("Fauld", [(0.001, 2.74), (0.56, 2.74), (0.6, 2.8), (0.555, 2.85), (0.555, 2.89), (0.585, 2.95), (0.535, 2.99), (0.535, 3.03),
                    (0.555, 3.09), (0.5, 3.14), (0.001, 3.14)], (0, 0, 0), "chrome", seg=16, scale=(1, 0.72))
    lathe("Breastplate", [(0.001, 3.1), (0.5, 3.1), (0.52, 3.3), (0.6, 3.7), (0.63, 4.0), (0.62, 4.3), (0.55, 4.6), (0.42, 4.8),
                          (0.28, 4.9), (0.001, 4.9)], (0, 0, 0), "chrome", seg=18, scale=(1, 0.7))
    sweep("Ridge", spline([(0, -0.357, 3.2), (0, -0.406, 3.6), (0, -0.441, 4.0), (0, -0.42, 4.4), (0, -0.336, 4.75)], 3), 0.018, "gilt", seg=5)
    oval = Matrix.Diagonal((1, 0.72, 1, 1))
    torus("Belt", 0.53, 0.035, (0, 0, 3.2), "leather", seg=18, ring_seg=4, rot=oval)
    box("Buckle", (0.14, 0.03, 0.1), (0, -0.39, 3.2), "gilt", r=0.01, seg=1)
    torus("Neck edge", 0.3, 0.02, (0, 0, 4.88), "gilt", seg=16, ring_seg=4, rot=Matrix.Diagonal((1, 0.75, 1, 1)))
    lathe("Gorget", [(0.22, 4.85), (0.34, 4.86), (0.33, 4.93), (0.29, 4.95), (0.3, 5.0), (0.26, 5.08), (0.22, 5.1)], (0, 0, 0), "steel", seg=14)
    for s in (-1, 1):
        shoulder = euler(ry=s * 0.5)
        lathe("Pauldron", [(0.001, 0.3), (0.16, 0.28), (0.27, 0.2), (0.34, 0.08), (0.36, -0.02), (0.33, -0.03), (0.345, -0.12),
                           (0.31, -0.13), (0.32, -0.22), (0.27, -0.23), (0.25, -0.1), (0.001, 0.0)], (s * 0.62, 0, 4.66), "chrome",
              seg=14, scale=(1, 1.05), rot=shoulder)
        torus("Pauldron edge", 0.3, 0.018, (s * 0.62, 0, 4.66), "gilt", seg=14, ring_seg=4,
              rot=shoulder @ Matrix.Translation((0, 0, -0.222)) @ Matrix.Diagonal((1, 1.05, 1, 1)))
        shoulder_pt, elbow, wrist = Vector((s * 0.84, 0.0, 4.4)), Vector((s * 0.9, -0.1, 3.75)), Vector((s * 0.22, -0.55, 3.5))
        sweep("Rerebrace", [tuple(shoulder_pt), tuple(elbow)], 0.14, "chrome", seg=10, r1=0.12)
        ball("Couter", 0.15, tuple(elbow), "chrome", seg=10, rings=6)
        ball("Couter wing", 0.12, (s * 1.02, -0.12, 3.75), "chrome", scale=(0.3, 1, 1), seg=8, rings=5)
        sweep("Vambrace", spline([tuple(elbow), (s * 0.6, -0.42, 3.6), tuple(wrist)], 2), 0.12, "chrome", seg=10, r1=0.085)
        sweep("Cuff", [tuple(wrist), tuple(wrist + (elbow - wrist) * 0.2)], 0.09, "steel", seg=10, r1=0.135)
        ball("Gauntlet", 0.11, (s * 0.11, -0.62, 3.55), "steel", scale=(1.1, 1.0, 0.85), seg=10, rings=6)
    ball("Pommel", 0.075, (0, -0.62, 3.75), "gilt", scale=(1, 0.6, 1), seg=10, rings=6)
    cyl("Grip", 0.04, 0.45, (0, -0.62, 3.47), "leather", seg=8, edge=0)
    sweep("Guard", spline([(-0.38, -0.62, 3.12), (-0.3, -0.62, 3.2), (0, -0.62, 3.22), (0.3, -0.62, 3.2), (0.38, -0.62, 3.12)], 2),
          0.03, "gilt", seg=5)
    lathe("Blade", [(0.001, 0.36), (0.07, 0.62), (0.085, 1.4), (0.09, 3.16), (0.001, 3.18)], (0, -0.62, 0), "chrome", seg=4, scale=(1, 0.22))
    lathe("Helm", [(0.001, 5.1), (0.25, 5.1), (0.3, 5.25), (0.32, 5.5), (0.3, 5.72), (0.22, 5.9), (0.1, 5.98), (0.001, 6.0)],
          (0, 0.03, 0), "chrome", seg=16)
    sweep("Visor", [(0, -0.12, 5.56), (0, -0.33, 5.52), (0, -0.5, 5.47)], [0.25, 0.17, 0.04], "chrome", seg=12, scale=(1.0, 1.15))
    for s in (-1, 1):
        box("Eye slit", (0.15, 0.03, 0.022), (s * 0.1, -0.235, 5.73), "black", r=0, rot=euler(rx=-0.55, ry=s * 0.25))
        for k in range(3):
            ball("Breath", 0.014, (s * 0.07, -0.36 - k * 0.04, 5.41 + k * 0.005), "black", seg=6, rings=4)
    sweep("Crest", spline([(0, -0.2, 5.88), (0, -0.05, 5.99), (0, 0.15, 5.97), (0, 0.3, 5.85)], 3), 0.022, "gilt", seg=5)
    for dx, top in ((0.0, 6.5), (-0.1, 6.36), (0.1, 6.36)):
        path = spline([(dx * 0.3, 0.08, 5.96), (dx * 0.8, 0.22, 6.25), (dx * 1.3, 0.42, top - 0.05), (dx * 1.6, 0.6, top), (dx * 1.8, 0.72, top - 0.12)], 2)
        radii = [0.035 + 0.11 * math.sin(math.pi * min(0.95, 0.08 + i / (len(path) - 1))) * (1 if dx == 0 else 0.75) for i in range(len(path))]
        sweep("Plume", path, radii, "velvet", seg=8, scale=(0.75, 1.0))
    right = [(0, 0.01), (0.18, 0.13), (0.33, 0.36), (0.42, 0.66), (0.45, 0.96), (0.45, 1.21)]
    shield = right + [(-x, z) for x, z in reversed(right[1:])]
    lean = Matrix.Translation((0.62, -0.855, 0.0)) @ euler(rz=-0.2) @ euler(rx=-0.2)
    prism("Shield", shield, -0.04, 0.04, "velvet", r=0.015, rot=lean)
    prism("Chevron", [(-0.33, 0.58), (0, 0.92), (0.33, 0.58), (0.33, 0.45), (0, 0.79), (-0.33, 0.45)], -0.048, -0.038, "gilt", r=0, rot=lean)
    sweep("Shield edge", [tuple(lean @ Vector((x * 0.9, -0.045, 0.62 + (z - 0.62) * 0.92))) for x, z in shield], 0.022, "gilt", seg=5, closed=True)


# ───────────────────────────────────────────────────────────── 8.3 sběratelské kousky (dalších 12)
# Tři od každé vzácnosti: alpské věci chaty (vyřezávaný medvěd, alpský roh, lyžařská trofej), dědovy poklady a dva
# legendární vtipy stěhovací firmy ve světě zombií (lebka T. rexe v garáži, sejf odolný proti zombiím v ložnici).
# Nápisy (THE END?, WELCOME, NEVER LATE · 1908, GOOD LUCK, THE ROLLING BONES, DOWNHILL CHAMPION 1964,
# T. REX · 66 MILLION YEARS, ZOMBIE-PROOF) tiskne hra; pod každým je díl modelu a před ním nic. Osa x je tu zrcadlem
# osy X ve hře (díl vpravo tady je vpravo i při pohledu zepředu ve hře), proto mají nesouměrné kusy x obrácené proti
# FurnitureLooks.luau.
SIDE_VIEW = Matrix.Rotation(math.pi / 2, 4, "Z")  # (side-view outlines: y, z, pushed along x)
OUT_FRONT = euler(rx=math.pi / 2)  # (a lathe's axis out of the front, -y)


def antique_typewriter(W, H, D):
    """A 1920s typewriter: the black frame with its gold pinstripes, four rows of round keys on their stems sloping to the
    front and the space bar, the two ribbon spools under their chrome covers, the platen and its knurled knobs, the
    carriage return lever, the paper rest, and the last page of somebody's novel in it (the game prints THE END? on it)."""
    side = [(-0.76, 0.04), (-0.76, 0.2), (-0.7, 0.26), (-0.12, 0.56), (-0.02, 0.66), (0.08, 0.72), (0.6, 0.72), (0.72, 0.64),
            (0.76, 0.5), (0.76, 0.04)]
    prism("Body", side, -0.74, 0.74, "lacquer", r=0.05, seg=2, rot=SIDE_VIEW)
    stripe = [(-0.66, 0.2), (-0.62, 0.27), (-0.13, 0.5), (0.06, 0.64), (0.58, 0.64), (0.67, 0.56), (0.67, 0.2), (-0.66, 0.2)]
    for s in (-1, 1):
        sweep("Pinstripe", [(s * 0.745, y, z) for y, z in stripe], 0.008, "gilt", seg=4)
        for sy in (-1, 1):
            cyl("Foot", 0.06, 0.04, (s * 0.64, sy * 0.64, 0.02), "rubber", seg=10, edge=0.01)

    def deck(y):  # the keyboard's slope (the body's outline from (-0.7, 0.26) to (-0.12, 0.56))
        return 0.26 + (y + 0.7) * 0.3 / 0.58
    for row, y in enumerate((-0.62, -0.47, -0.32, -0.18)):
        for k in range(10):
            x = -0.61 + k * 0.135 + row * 0.03
            if abs(x) > 0.68:
                continue
            z = deck(y)
            cyl("Key stem", 0.012, 0.09, (x, y + 0.02, z + 0.04), "chrome", seg=6, edge=0)
            cyl("Key", 0.055, 0.03, (x, y, z + 0.1), "cream", seg=10, edge=0)
    box("Space bar", (0.8, 0.07, 0.04), (0, -0.715, 0.3), "cream", r=0.015, seg=1)
    for s in (-1, 1):
        box("Space arm", (0.03, 0.12, 0.03), (s * 0.3, -0.66, 0.285), "chrome", r=0)
    box("Carriage", (1.62, 0.34, 0.05), (0, 0.42, 0.745), "lacquer", r=0.015)
    cyl("Platen", 0.14, 1.56, (0, 0.42, 0.79), "rubber", axis="X", seg=24, edge=0.02)
    for s in (-1, 1):
        cyl("Platen end", 0.15, 0.04, (s * 0.78, 0.42, 0.79), "chrome", axis="X", seg=24, edge=0.01)
        lathe("Knob", [(0.001, 0.0), (0.15, 0.0), (0.17, 0.02), (0.17, 0.08), (0.15, 0.1), (0.001, 0.1)], (s * 0.8, 0.42, 0.79),
              "black", seg=20, rot=euler(ry=s * math.pi / 2))
        cyl("Ribbon", 0.12, 0.03, (s * 0.48, 0.18, 0.735), "red", seg=20, edge=0)
        cyl("Spool cover", 0.14, 0.02, (s * 0.48, 0.18, 0.76), "chrome", seg=20, edge=0.005)
    box("Ribbon guide", (0.9, 0.012, 0.03), (0, 0.27, 0.8), "red", r=0)
    box("Card holder", (1.2, 0.012, 0.04), (0, 0.27, 0.86), "chrome", r=0)
    sweep("Return lever", spline([(0.8, 0.32, 0.84), (0.79, 0.15, 0.9), (0.72, -0.08, 0.92)], 3), 0.018, "chrome", seg=6)
    ball("Lever tip", 0.03, (0.72, -0.09, 0.92), "black", seg=8, rings=5)
    box("Page", (1.1, 0.02, 0.25), (0, 0.44, 1.075), "white", r=0)  # (the game prints THE END? on it)
    box("Page", (1.1, 0.02, 0.22), (0, 0.575, 0.86), "white", r=0)
    box("Paper rest", (1.4, 0.025, 0.32), (0, 0.62, 1.0), "steel", r=0.01, rot=euler(rx=-0.3))


def vintage_camera(W, H, D):
    """A photographer's wooden field camera on its tripod: the legs (two rails each, a brass clamp and spike), the brass
    head, the bed and its focusing rails and knobs, the pleated bellows between the front and back standards, the brass
    lens, and the black cloth he hid under thrown over the back."""
    apex = Vector((0, 0, 3.32))
    for fx, fy in ((0.68, -0.4), (-0.68, -0.4), (0, 0.72)):
        foot = Vector((fx, fy, 0.05))
        d = foot - apex
        across = d.cross(Vector((0, 0, 1))).normalized() * 0.035
        for s in (-1, 1):
            tube("Leg", tuple(apex + d * 0.04 + across * s), tuple(foot + across * s * 0.3), 0.025, "wood", 6)
        cyl("Clamp", 0.05, 0.06, tuple(apex + d * 0.55), "brass", seg=12, edge=0, rot=towards(d))
        cyl("Spike", 0.03, 0.08, tuple(foot), "brass", seg=8, r2=0.004, edge=0, rot=towards(d))
    cyl("Head", 0.25, 0.12, (0, 0, 3.36), "brass", seg=24, edge=0.015)
    box("Bed", (0.9, 1.3, 0.08), (0, 0, 3.46), "wood", r=0.02)
    for s in (-1, 1):
        box("Rail", (0.05, 1.2, 0.03), (s * 0.3, 0, 3.515), "brass", r=0.008, seg=1)
        cyl("Focus", 0.07, 0.08, (s * 0.49, -0.3, 3.46), "brass", axis="X", seg=14, edge=0.01)
    box("Back", (1.0, 0.22, 0.9), (0, 0.5, 3.95), "wood", r=0.03)
    for k in range(9):
        t = k / 8
        grow = 0.06 if k % 2 == 0 else 0.0
        box("Bellows", (0.66 + 0.16 * t + grow, 0.08, 0.6 + 0.14 * t + grow), (0, -0.25 + t * 0.62, 3.92), "lacquer", r=0.012, seg=1)
    box("Front", (0.9, 0.14, 0.85), (0, -0.34, 3.93), "wood", r=0.03)
    box("Lens board", (0.6, 0.03, 0.6), (0, -0.42, 3.92), "black", r=0.01, seg=1)
    lathe("Lens", [(0.001, 0.0), (0.2, 0.0), (0.2, 0.03), (0.165, 0.045), (0.16, 0.2), (0.18, 0.22), (0.185, 0.28), (0.15, 0.29),
                   (0.001, 0.29)], (0, -0.43, 3.92), "brass", seg=24, rot=OUT_FRONT)
    cyl("Lens glass", 0.14, 0.01, (0, -0.725, 3.92), "glass", axis="Y", seg=24, edge=0)
    torus("Aperture ring", 0.172, 0.012, (0, -0.6, 3.92), "black", axis="Y", seg=20, ring_seg=4)
    box("Shutter lever", (0.12, 0.02, 0.03), (0.2, -0.57, 4.06), "chrome", r=0.005, rot=euler(ry=0.4))
    cushion("Cloth", (1.2, 0.16, 0.75), (0, 0.69, 4.0), "dark")
    cushion("Cloth", (0.9, 0.12, 0.6), (0.05, 0.72, 3.45), "dark", rot=euler(ry=0.08))


def carved_bear(W, H, D):
    """A chainsaw-carved bear out of a larch log on its stump: the round belly and chest with their carved fur, the head,
    the snout and the black nose, the ears, the arms holding up the chalet's welcome sign (the game prints WELCOME on
    it), the claws over its top edge."""
    lathe("Stump", [(0.001, 0.0), (0.61, 0.0), (0.63, 0.04), (0.61, 0.41), (0.57, 0.45), (0.001, 0.45)], (0, 0.02, 0), "wood2", seg=24)
    for R in (0.18, 0.34, 0.5):
        torus("Growth ring", R, 0.008, (0, 0.02, 0.452), "wood2", seg=24, ring_seg=3)
    ball("Belly", 0.55, (0, 0.12, 1.5), "wood", scale=(1.0, 0.92, 1.05), seg=20)
    ball("Chest", 0.48, (0, 0.1, 2.12), "wood", scale=(1.0, 0.92, 1.0), seg=20)
    ball("Head", 0.36, (0, 0.06, 2.82), "wood", scale=(1.0, 0.95, 0.95), seg=18)
    ball("Snout", 0.19, (0, -0.32, 2.72), "wood", scale=(0.9, 1.15, 0.8), seg=14)
    ball("Nose", 0.075, (0, -0.52, 2.78), "black", scale=(1.25, 0.8, 0.8), seg=10, rings=6)
    sweep("Mouth", [(-0.09, -0.47, 2.63), (0, -0.5, 2.61), (0.09, -0.47, 2.63)], 0.012, "black", seg=4)
    for s in (-1, 1):
        ball("Eye", 0.04, (s * 0.15, -0.26, 2.95), "black", seg=8, rings=5)
        ball("Ear", 0.13, (s * 0.27, 0.12, 3.13), "wood", scale=(1.0, 0.55, 1.0), seg=12)
        sweep("Leg", [(s * 0.27, 0.12, 0.42), (s * 0.28, 0.1, 0.8), (s * 0.27, 0.1, 1.1)], 0.21, "wood", seg=14, r1=0.19)
        ball("Foot", 0.2, (s * 0.27, 0.0, 0.52), "wood", scale=(1.0, 1.3, 0.6), seg=12)
        sweep("Arm", spline([(s * 0.42, 0.05, 2.28), (s * 0.6, -0.08, 2.05), (s * 0.57, -0.32, 1.9)], 3), 0.15, "wood", seg=12, r1=0.12)
        ball("Paw", 0.14, (s * 0.55, -0.44, 1.86), "wood", scale=(1.0, 1.0, 0.9), seg=12)
        for k in (-1, 0, 1):
            ball("Claw", 0.025, (s * 0.55 + k * 0.055, -0.55, 1.93), "cream", scale=(1.0, 1.0, 1.6), seg=6, rings=4)
        # the chainsaw's cuts: the fur in rows of short grooves down the chest and belly
        for k in range(4):
            z = 2.35 - k * 0.18
            x = s * (0.12 + 0.05 * (k % 2))
            sweep("Carving", [(x, -0.37, z), (x + s * 0.08, -0.35, z - 0.08)], 0.012, "wood2", seg=4)
        for k in range(3):
            z = 1.62 - k * 0.2
            x = s * (0.16 + 0.06 * (k % 2))
            sweep("Carving", [(x, -0.42, z), (x + s * 0.09, -0.4, z - 0.09)], 0.012, "wood2", seg=4)
    box("Sign", (1.6, 0.08, 0.5), (0, -0.6, 1.62), "parchment", r=0.02)  # (the game prints WELCOME on it)


def gramophone(W, H, D):
    """A wind-up gramophone: the wooden cabinet with its corner pillars, panel and badge, the crank, the turntable's felt
    and a shellac record, the tone arm from the elbow at the back to the sound box on the record, and the big flower horn
    flaring out over it (its petals' seams in brass)."""
    box("Plinth", (1.4, 1.4, 0.1), (0, 0.35, 0.05), "wood2", r=0.03)
    box("Cabinet", (1.3, 1.3, 0.62), (0, 0.35, 0.41), "wood", r=0.03)
    box("Lid", (1.38, 1.38, 0.08), (0, 0.35, 0.76), "wood2", r=0.025)
    box("Panel", (0.9, 0.02, 0.36), (0, -0.31, 0.42), "wood2", r=0.01)
    box("Badge", (0.22, 0.012, 0.08), (0, -0.322, 0.53), "brass", r=0.005)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl("Pillar", 0.045, 0.62, (sx * 0.62, 0.35 + sy * 0.62, 0.41), "wood2", seg=10, edge=0)
    cyl("Crank shaft", 0.03, 0.16, (-0.72, 0.35, 0.5), "chrome", axis="X", seg=10, edge=0)
    sweep("Crank", [(-0.79, 0.35, 0.5), (-0.83, 0.35, 0.45), (-0.83, 0.35, 0.35)], 0.022, "chrome", seg=6)
    cyl("Crank grip", 0.035, 0.1, (-0.84, 0.35, 0.33), "black", axis="X", seg=10, edge=0)
    cyl("Felt", 0.5, 0.03, (0, 0.35, 0.815), "velvet", seg=32, edge=0)
    grooves = []
    for k in range(6):
        r = 0.44 - k * 0.045
        grooves += [(r, 0.016), (r - 0.022, 0.012)]
    lathe("Record", [(0.001, 0.0), (0.46, 0.0), (0.46, 0.012)] + grooves + [(0.15, 0.014), (0.001, 0.014)], (0, 0.35, 0.83), "black", seg=32)
    cyl("Label", 0.14, 0.006, (0, 0.35, 0.847), "accent", seg=20, edge=0)
    cyl("Spindle", 0.012, 0.05, (0, 0.35, 0.86), "chrome", seg=6, edge=0)
    cyl("Elbow", 0.07, 0.5, (0, 0.9, 1.05), "gilt", seg=14, edge=0.01)
    sweep("Tone arm", spline([(0, 0.9, 0.95), (0.05, 0.6, 0.98), (0.12, 0.25, 0.97), (0.15, 0.1, 0.94)], 3), 0.03, "gilt", seg=10, r1=0.022)
    cyl("Sound box", 0.11, 0.05, (0.15, 0.05, 0.93), "chrome", axis="Y", seg=20, edge=0.01)
    cyl("Needle", 0.006, 0.06, (0.15, 0.03, 0.87), "steel", seg=4, edge=0)
    # the horn: an exponential flare from the elbow's top to its rim, open (its inside back down to the neck)
    p0 = Vector((0, 0.9, 1.3))
    d = Vector((0, -1.45, 0.7)).normalized()
    out = [(0.07 * math.exp(1.555 * 1.6 * k / 12), 1.6 * k / 12) for k in range(13)]
    lip = [(0.86, 1.61), (0.865, 1.625), (0.845, 1.632)]
    inside = [(r - 0.02, t + 0.006) for r, t in reversed(out)]
    lathe("Horn", out + lip + inside, tuple(p0), "gilt", seg=32, rot=towards(d))
    u = Vector((1, 0, 0))
    v = d.cross(u).normalized()
    for k in range(8):  # the seams between its petals
        a = math.pi / 8 + k * math.pi / 4
        rim = []
        for t in (0.5, 0.75, 1.0, 1.2, 1.4, 1.58):
            r = 0.07 * math.exp(1.555 * t) + 0.004
            rim.append(tuple(p0 + d * t + (u * math.cos(a) + v * math.sin(a)) * r))
        sweep("Petal seam", rim, 0.009, "brass", seg=4)


def pocket_watch(W, H, D):
    """Grandpa's gold pocket watch hung on its brass stand under a glass dome: the wooden base and its plate (the game
    prints NEVER LATE · 1908 on it), the velvet cushion, the watch's case, bezel, dial, numerals and hands, its crown and
    bow, and its chain of little links draped down to a fob on the cushion."""
    box("Base", (0.95, 0.95, 0.16), (0, 0, 0.08), "wood2", r=0.03, seg=3)
    box("Base top", (0.86, 0.86, 0.06), (0, 0, 0.19), "wood2", r=0.02)
    box("Plate", (0.6, 0.02, 0.13), (0, -0.485, 0.1), "brass", r=0.005)  # (the game prints NEVER LATE · 1908 on it)
    lathe("Cushion", [(0.001, 0.22), (0.36, 0.22), (0.39, 0.24), (0.38, 0.27), (0.3, 0.29), (0.001, 0.295)], (0, 0, 0), "velvet", seg=28)
    top = [(max(0.001, 0.4 * math.cos(a)), 1.06 + 0.4 * math.sin(a)) for a in (math.pi / 2 * k / 8 for k in range(1, 9))]
    inner = [(max(0.001, 0.385 * math.cos(a)), 1.06 + 0.385 * math.sin(a)) for a in (math.pi / 2 * k / 8 for k in range(8, 0, -1))]
    lathe("Dome", [(0.4, 0.26), (0.4, 1.06)] + top + inner + [(0.385, 1.06), (0.385, 0.27)], (0, 0, 0), "crystal", seg=36)
    torus("Dome rim", 0.405, 0.02, (0, 0, 0.27), "brass", seg=36, ring_seg=4)
    ball("Dome knob", 0.04, (0, 0, 1.455), "brass", seg=10, rings=6)
    cyl("Post", 0.022, 0.66, (0, 0.18, 0.62), "brass", seg=10, edge=0)
    cyl("Post foot", 0.06, 0.03, (0, 0.18, 0.31), "brass", seg=14, edge=0)
    sweep("Hook", spline([(0, 0.18, 0.94), (0, 0.13, 1.02), (0, 0.05, 1.04), (0, 0.0, 1.0)], 3), 0.014, "brass", seg=6)
    lathe("Case", [(0.001, -0.06), (0.25, -0.06), (0.275, -0.045), (0.285, 0.0), (0.275, 0.045), (0.25, 0.06), (0.001, 0.06)],
          (0, 0, 0.62), "gilt", seg=32, rot=OUT_FRONT)
    torus("Bezel", 0.245, 0.016, (0, -0.062, 0.62), "gilt", axis="Y", seg=32, ring_seg=4)
    cyl("Dial", 0.235, 0.006, (0, -0.064, 0.62), "cream", axis="Y", seg=32, edge=0)
    for k in range(12):
        a = k * math.pi / 6
        box("Numeral", (0.012, 0.004, 0.035 if k % 3 == 0 else 0.022), (0.19 * math.sin(a), -0.068, 0.62 + 0.19 * math.cos(a)), "black", r=0,
            rot=euler(ry=a))
    torus("Seconds", 0.045, 0.004, (0, -0.068, 0.53), "black", axis="Y", seg=16, ring_seg=3)
    for angle, length, width in ((math.radians(300), 0.12, 0.018), (math.radians(60), 0.18, 0.012)):  # (ten past ten)
        box("Hand", (width, 0.004, length), (math.sin(angle) * length / 2, -0.072, 0.62 + math.cos(angle) * length / 2), "black", r=0,
            rot=euler(ry=angle))
    cyl("Centre", 0.012, 0.01, (0, -0.075, 0.62), "gilt", axis="Y", seg=8, edge=0)
    cyl("Pendant", 0.03, 0.05, (0, 0, 0.92), "gilt", seg=10, edge=0)
    lathe("Crown", [(0.001, 0.94), (0.045, 0.94), (0.05, 0.96), (0.05, 0.99), (0.04, 1.0), (0.001, 1.0)], (0, 0, 0), "gilt", seg=14)
    torus("Bow", 0.075, 0.012, (0, 0, 1.03), "gilt", axis="Y", seg=20, ring_seg=4)
    path = [Vector(p) for p in spline([(0.06, -0.02, 0.97), (0.22, -0.12, 0.75), (0.29, -0.19, 0.5), (0.25, -0.26, 0.33),
                                       (0.12, -0.28, 0.31), (-0.04, -0.24, 0.31)], 4)]
    left, step, k = 0.0, 0.04, 0
    for a, b in zip(path, path[1:]):
        seg_len = (b - a).length
        while left <= seg_len:
            twist = euler(rz=math.pi / 2) if k % 2 else Matrix()
            torus("Chain link", 0.022, 0.006, tuple(a + (b - a) * (left / seg_len)), "gilt", seg=8, ring_seg=3,
                  rot=towards(b - a) @ twist @ euler(rx=math.pi / 2))
            left += step
            k += 1
        left -= seg_len
    cyl("Fob", 0.05, 0.012, (-0.1, -0.23, 0.302), "gilt", seg=16, edge=0)
    box("Fob bar", (0.1, 0.012, 0.012), (-0.06, -0.24, 0.31), "gilt", r=0)


def golden_horseshoe(W, H, D):
    """A lucky golden horseshoe, its ends up so the luck stays in: its grooved web and nail holes and calkins, on velvet on
    an arched oak board, a four-leaf clover inside it, a red bow on top; the board in its foot with an engraved plate
    (the game prints GOOD LUCK on it)."""
    box("Foot", (1.6, 0.76, 0.15), (0, 0, 0.075), "wood2", r=0.03, seg=3)
    box("Plate", (0.9, 0.02, 0.11), (0, -0.39, 0.075), "brass", r=0.004)  # (the game prints GOOD LUCK on it)
    prism("Board", [(-0.65, 0.15), (0.65, 0.15)] + arc(0, 1.6, 0.65, 0, math.pi, 20, rz=0.3), 0.16, 0.28, "wood", r=0.03, seg=2)
    prism("Velvet", [(-0.52, 0.32), (0.52, 0.32)] + arc(0, 1.6, 0.52, 0, math.pi, 18, rz=0.2), 0.14, 0.165, "velvet", r=0)
    u = [(-0.44, 1.62), (-0.47, 1.3), (-0.48, 1.0), (-0.42, 0.78), (-0.25, 0.64), (0, 0.6), (0.25, 0.64), (0.42, 0.78), (0.48, 1.0),
         (0.47, 1.3), (0.44, 1.62)]
    shoe = spline([(x, 0.09, z) for x, z in u], 3)
    sweep("Shoe", shoe, 0.09, "gilt", seg=12, scale=(1.0, 0.5))
    groove = spline([(x * 0.98, 0.043, 0.02 + z * 0.985) for x, z in u[1:-1]], 3)
    sweep("Groove", groove, 0.022, "gold", seg=6, scale=(1.0, 0.35))
    for k, (x, z) in enumerate(((-0.47, 1.36), (-0.48, 1.12), (-0.45, 0.9), (-0.34, 0.72), (0.34, 0.72), (0.45, 0.9), (0.48, 1.12),
                                (0.47, 1.36))):
        cyl("Nail hole", 0.018, 0.012, (x, 0.036, z), "black", axis="Y", seg=8, edge=0)
    for s in (-1, 1):
        box("Calkin", (0.18, 0.12, 0.08), (s * 0.44, 0.09, 1.64), "gilt", r=0.02)
        torus("Bow loop", 0.09, 0.025, (s * 0.1, 0.12, 1.84), "red", axis="Y", seg=16, ring_seg=5, rot=Matrix.Diagonal((1.3, 1, 0.7, 1)))
        sweep("Bow tail", [(s * 0.02, 0.12, 1.82), (s * 0.08, 0.12, 1.7), (s * 0.12, 0.12, 1.6)], 0.03, "red", seg=6, scale=(1.0, 0.25))
    ball("Bow knot", 0.045, (0, 0.11, 1.84), "red", seg=10, rings=6)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        ball("Clover leaf", 0.07, (0.075 * math.cos(a), 0.13, 1.18 + 0.075 * math.sin(a)), "leaf2", scale=(1.0, 0.25, 1.0), seg=10, rings=6)
    sweep("Clover stem", [(0, 0.13, 1.16), (0.03, 0.13, 1.02), (0.08, 0.13, 0.95)], 0.012, "leaf", seg=5)


def crystal_chandelier(W, H, D):
    """A small crystal chandelier taken down for the move, resting on a padded moving ring: the crystal ball and the gilt
    bowl, the turned column, six curving arms with their drip pans, candles and flame bulbs, a crystal drop under each,
    swags of crystal beads between them, crystal spikes round the top of the column, the chain and the ceiling rose."""
    torus("Moving ring", 0.42, 0.14, (0, 0, 0.14), "fabric", seg=24, ring_seg=6)
    ball("Crystal ball", 0.18, (0, 0, 0.46), "crystal", seg=16)
    lathe("Bowl", [(0.001, 0.62), (0.05, 0.62), (0.09, 0.7), (0.2, 0.86), (0.33, 0.98), (0.36, 1.04), (0.34, 1.07), (0.12, 1.08),
                   (0.08, 1.12), (0.001, 1.12)], (0, 0, 0), "gilt", seg=24)
    lathe("Column", [(0.001, 1.1), (0.08, 1.1), (0.1, 1.16), (0.06, 1.24), (0.05, 1.45), (0.09, 1.55), (0.1, 1.62), (0.06, 1.72),
                     (0.045, 1.95), (0.07, 2.02), (0.08, 2.1), (0.05, 2.16), (0.03, 2.25), (0.001, 2.25)], (0, 0, 0), "gilt", seg=16)
    reach = 1.06
    for k in range(6):
        a = k * math.pi / 3
        c, s = math.cos(a), math.sin(a)
        sweep("Arm", spline([(c * r, s * r, z) for r, z in ((0.3, 1.0), (0.5, 0.97), (0.75, 1.05), (0.95, 1.2), (reach, 1.32))], 3), 0.03,
              "gilt", seg=6)
        x, y = reach * c, reach * s
        lathe("Drip pan", [(0.001, 1.31), (0.05, 1.31), (0.12, 1.36), (0.12, 1.38), (0.04, 1.37), (0.001, 1.37)], (x, y, 0), "gilt", seg=10)
        cyl("Candle", 0.035, 0.14, (x, y, 1.44), "cream", seg=10, edge=0)
        ball("Flame bulb", 0.05, (x, y, 1.56), "glow", scale=(1.0, 1.0, 1.6), seg=8, rings=5)
        ball("Bead", 0.025, (x * 1.0, y * 1.0, 1.27), "crystal", seg=6, rings=4)
        ball("Drop", 0.05, (x, y, 1.18), "crystal", scale=(1.0, 1.0, 1.9), seg=4, rings=2)
        # a swag of beads from this arm to the next, sagging between them
        b = a + math.pi / 3
        ends = [Vector((0.7 * math.cos(a), 0.7 * math.sin(a), 1.02)), Vector((0.7 * math.cos(b), 0.7 * math.sin(b), 1.02))]
        mid = (ends[0] + ends[1]) / 2 * 1.02
        mid.z = 0.86
        swag = [Vector(p) for p in spline([tuple(ends[0]), tuple(mid), tuple(ends[1])], 6)]
        left = 0.0
        for p, q in zip(swag, swag[1:]):
            seg_len = (q - p).length
            while left <= seg_len:
                ball("Bead", 0.022, tuple(p + (q - p) * (left / seg_len)), "crystal", seg=5, rings=3)
                left += 0.07
            left -= seg_len
        cyl("Spike", 0.03, 0.16, (0.11 * c, 0.11 * s, 2.13), "crystal", seg=6, r2=0.002, edge=0,
            rot=towards((c, s, 1.2)))
    for k, z in enumerate((2.28, 2.33, 2.38)):
        torus("Chain link", 0.03, 0.009, (0, 0, z), "gilt", axis="Y" if k % 2 else "X", seg=10, ring_seg=3)
    lathe("Ceiling rose", [(0.001, 2.42), (0.06, 2.42), (0.2, 2.5), (0.24, 2.57), (0.24, 2.6), (0.001, 2.6)], (0, 0, 0), "gilt", seg=20)


def alphorn(W, H, D):
    """An alphorn lying on its two trestles: the long spruce tube widening from the mouthpiece to the upturned bell (the
    bell here on the left, as in the game), the cane bindings round the tube, the painted band on the bell with its
    edelweiss, the dark rim."""
    for x in (2.2, -1.2):  # (the game's x -2.2 and 1.2)
        for s in (-1, 1):
            tube("Trestle leg", (x, s * 0.6, 0.02), (x, s * 0.12, 0.46), 0.035, "wood2", 6)
        box("Brace", (0.06, 0.9, 0.05), (x, 0, 0.2), "wood2", r=0.01, seg=1)
        box("Cradle", (0.14, 0.36, 0.1), (x, 0, 0.5), "wood2", r=0.02)
    pts, radii = [], []
    for x, r in ((3.42, 0.05), (2.6, 0.055), (1.6, 0.065), (0.6, 0.078), (-0.4, 0.092), (-1.4, 0.108), (-2.3, 0.13)):
        pts.append((x, 0, 0.62))
        radii.append(r)
    cx, cz, R = -2.3, 1.3, 0.68  # (the bend up into the bell: a quarter circle)
    for k in range(1, 9):
        a = -math.pi / 2 - (math.pi / 2) * k / 8
        pts.append((cx + R * math.cos(a), 0, cz + R * math.sin(a)))
        radii.append(0.13 + 0.17 * k / 8)
    sweep("Tube", pts, radii, "wood", seg=18)

    def radius_at(x):  # the straight tube's radius at x
        for (x0, *_), (x1, *_), r0, r1 in zip(pts, pts[1:7], radii, radii[1:7]):
            if x1 <= x <= x0:
                return r0 + (r1 - r0) * (x0 - x) / (x0 - x1)
        return radii[0]
    for x in (2.85, 0.35, -1.75):  # the cane bindings, two rings each
        for dx in (-0.025, 0.025):
            torus("Binding", radius_at(x + dx) + 0.006, 0.014, (x + dx, 0, 0.62), "wicker", axis="X", seg=18, ring_seg=4)
    lathe("Mouthpiece", [(0.001, 0.0), (0.06, 0.0), (0.075, 0.03), (0.07, 0.06), (0.045, 0.08), (0.045, 0.16), (0.001, 0.16)],
          (3.59, 0, 0.62), "wood2", seg=16, rot=euler(ry=-math.pi / 2))
    lathe("Bell", [(0.3, 1.3), (0.33, 1.42), (0.4, 1.55), (0.5, 1.67), (0.58, 1.75), (0.59, 1.775), (0.565, 1.77), (0.48, 1.68),
                   (0.38, 1.56), (0.31, 1.44), (0.28, 1.31)], (-2.98, 0, 0), "wood", seg=36)
    lathe("Band", [(0.349, 1.44), (0.408, 1.55), (0.433, 1.58), (0.425, 1.583), (0.4, 1.553), (0.341, 1.443)], (-2.98, 0, 0), "paint", seg=36)
    torus("Rim", 0.575, 0.02, (-2.98, 0, 1.765), "wood2", seg=36, ring_seg=4)
    for k in range(6):  # edelweiss painted round the band
        a = k * math.pi / 3 + 0.3
        c, s = math.cos(a), math.sin(a)
        centre = Vector((-2.98 + 0.405 * c, 0.405 * s, 1.515))
        outward = Vector((c, s, -0.55)).normalized()
        ball("Edelweiss", 0.03, tuple(centre + outward * 0.006), "white", scale=(1.0, 1.0, 1.0), seg=8, rings=5)
        ball("Edelweiss heart", 0.012, tuple(centre + outward * 0.03), "sun", seg=6, rings=4)


def signature(x0, z0, width, wiggle, loops, y=-0.186):
    """A signature in silver marker on the guitar: a slanted cursive scribble from (x0, z0) along +x, its loops and an
    underline."""
    pts = []
    for k in range(29):
        t = k / 28
        a = 2 * math.pi * loops * t
        pts.append((x0 + width * t + 0.035 * math.cos(a) * (1 - t * 0.5), y, z0 + wiggle * math.sin(a) + 0.04 * t))
    sweep("Signature", pts, 0.006, "white", seg=4)
    sweep("Signature", [(x0 + 0.02, y, z0 - 0.07), (x0 + width * 0.6, y, z0 - 0.085), (x0 + width * 1.05, y, z0 - 0.06)], 0.005, "white", seg=4)


def signed_guitar(W, H, D):
    """An electric guitar signed by The Rolling Bones, on its stand on a display plinth: the single-cut body with its
    cream binding, pickguard, two humbuckers, bridge and tailpiece, four gold knobs and the switch, the neck with its
    frets and inlays, the headstock and its tuners, the strings; the band's signatures and a heart in silver marker; the
    plinth's plate (the game prints THE ROLLING BONES on it)."""
    box("Plinth", (1.6, 1.1, 0.25), (0, 0, 0.125), "dark", r=0.04, seg=3)
    box("Plate", (0.9, 0.02, 0.14), (0, -0.56, 0.125), "brass", r=0.005)  # (the game prints THE ROLLING BONES on it)
    tube("Upright", (0, 0.42, 0.25), (0, 0.42, 3.22), 0.04, "black", 12)
    sweep("Yoke", spline([(-0.14, 0.0, 3.36), (-0.14, 0.22, 3.27), (0, 0.42, 3.22), (0.14, 0.22, 3.27), (0.14, 0.0, 3.36)], 3), 0.025, "black", seg=8)
    for s in (-1, 1):
        sweep("Cradle arm", spline([(0, 0.42, 0.3), (s * 0.25, 0.2, 0.33), (s * 0.35, -0.12, 0.38), (s * 0.35, -0.22, 0.46)], 3), 0.025,
              "black", seg=8)
        ball("Pad", 0.045, (s * 0.35, -0.22, 0.47), "rubber", seg=10, rings=6)
        ball("Yoke pad", 0.04, (s * 0.14, 0.0, 3.37), "rubber", seg=10, rings=6)
    # the body: the lower bout, the waist, the upper bout's horn and the cutaway on the right, round the left
    outline = [(0.68 * math.cos(a), 1.08 + 0.68 * math.sin(a)) for a in (math.radians(d) for d in range(-90, 30, 10))]
    outline += [(0.46, 1.56)]
    outline += [(-0.07 + 0.48 * math.cos(a), 1.82 + 0.48 * math.sin(a)) for a in (math.radians(d) for d in (-15, 0, 15, 28))]
    outline += [(0.34, 2.06), (0.27, 2.06), (0.2, 2.0), (0.15, 2.02), (0.13, 2.17)]
    outline += [(-0.07 + 0.48 * math.cos(a), 1.82 + 0.48 * math.sin(a)) for a in (math.radians(d) for d in range(70, 210, 10))]
    outline += [(-0.5, 1.56)]
    outline += [(0.68 * math.cos(a), 1.08 + 0.68 * math.sin(a)) for a in (math.radians(d) for d in range(150, 270, 10))]
    prism("Body", outline, -0.18, 0.06, "lacquer", r=0.04, seg=2)
    sweep("Binding", [(x * 1.0, -0.182, z) for x, z in outline], 0.012, "cream", seg=5, closed=True)
    prism("Pickguard", [(-0.14, 1.12), (-0.3, 1.06), (-0.46, 1.2), (-0.5, 1.5), (-0.4, 1.7), (-0.22, 1.68)], -0.2, -0.185, "cream", r=0)
    for z in (1.18, 1.6):
        box("Pickup ring", (0.48, 0.02, 0.21), (0, -0.19, z), "black", r=0.01, seg=1)
        box("Pickup", (0.42, 0.04, 0.15), (0, -0.2, z), "chrome", r=0.012)
    box("Bridge", (0.46, 0.05, 0.06), (0, -0.2, 0.98), "chrome", r=0.01)
    box("Tailpiece", (0.4, 0.05, 0.07), (0, -0.2, 0.84), "chrome", r=0.015)
    for x, z in ((-0.32, 0.78), (-0.52, 0.86), (-0.36, 0.98), (-0.56, 1.06)):
        lathe("Knob", [(0.001, 0.0), (0.065, 0.0), (0.06, 0.03), (0.05, 0.06), (0.001, 0.065)], (x, -0.18, z), "gold", seg=12, rot=OUT_FRONT)
    cyl("Switch", 0.02, 0.08, (-0.32, -0.21, 2.02), "chrome", axis="Y", seg=8, edge=0)
    ball("Switch tip", 0.025, (-0.32, -0.25, 2.02), "cream", seg=8, rings=5)
    box("Neck", (0.24, 0.12, 1.9), (0, -0.04, 3.1), "wood2", r=0.03)
    box("Fretboard", (0.2, 0.02, 1.9), (0, -0.11, 3.1), "dark", r=0.005)
    box("Nut", (0.21, 0.03, 0.03), (0, -0.115, 4.04), "cream", r=0.005)
    z, gap = 4.03, 0.17
    for k in range(14):
        z -= gap
        gap *= 0.944
        box("Fret", (0.2, 0.008, 0.01), (0, -0.124, z), "chrome", r=0)
        if k + 1 in (3, 5, 7, 9, 12):
            box("Inlay", (0.13, 0.004, 0.05), (0, -0.121, z + gap * 0.5), "cream", r=0)
    prism("Headstock", [(-0.2, 4.0), (0.2, 4.0), (0.21, 4.3), (0.1, 4.37), (0.0, 4.33), (-0.1, 4.37), (-0.21, 4.3)], -0.08, 0.02, "dark",
          r=0.02, seg=1)
    for s in (-1, 1):
        for z in (4.1, 4.19, 4.28):
            cyl("Tuner", 0.035, 0.06, (s * 0.24, -0.03, z), "chrome", axis="X", seg=10, edge=0)
            cyl("String post", 0.014, 0.04, (s * 0.13, -0.1, z), "chrome", axis="Y", seg=6, edge=0)
    for k in range(6):
        x0, x1 = -0.1 + k * 0.04, -0.07 + k * 0.028
        tube("String", (x0, -0.232, 0.87), (x1, -0.13, 4.03), 0.0035, "chrome", 4)
    signature(0.12, 0.86, 0.38, 0.05, 3.0)
    signature(-0.55, 1.36, 0.3, 0.04, 2.5)
    signature(0.08, 1.95, 0.22, 0.035, 2.0)
    heart = [(0.2 + 0.07 * (math.sin(t) ** 3), -0.186, 1.4 + 0.06 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16)
             for t in (2 * math.pi * k / 24 for k in range(24))]
    sweep("Heart", heart, 0.006, "white", seg=4, closed=True)


def ski_trophy(W, H, D):
    """The downhill champion's trophy: the marble base, the wooden step with its gilt trim and plate (the game prints
    DOWNHILL CHAMPION 1964 on it), a pair of old wooden racing skis crossed behind (red stripes, cable bindings, the tips
    curled), a gold mountain, and on its top a gold skier in a tuck with poles under the arms."""
    box("Base", (2.2, 1.2, 0.26), (0, 0, 0.13), "marble", r=0.04, seg=3)
    box("Base top", (2.06, 1.06, 0.08), (0, 0, 0.3), "marble", r=0.03, seg=2)
    box("Step", (1.6, 0.8, 0.31), (0, 0, 0.495), "wood2", r=0.04, seg=3)
    box("Step trim", (1.62, 0.82, 0.03), (0, 0, 0.66), "gilt", r=0.01, seg=1)
    box("Plate", (1.2, 0.02, 0.18), (0, -0.41, 0.475), "brass", r=0.006)  # (the game prints DOWNHILL CHAMPION 1964 on it)
    for s, y in ((-1, 0.3), (1, 0.36)):
        up = Vector((s * math.sin(0.3), 0, math.cos(0.3)))
        centre = Vector((0, y, 2.1))
        path = [centre + up * t for t in (-1.45, -0.9, -0.3, 0.3, 0.9, 1.25)]
        path += [centre + up * 1.36 + Vector((0, 0.05, 0)), centre + up * 1.42 + Vector((0, 0.13, 0))]
        sweep("Ski", [tuple(p) for p in path], 0.1, "wood", seg=8, scale=(1.0, 0.25))
        sweep("Ski stripe", [tuple(p + Vector((0, -0.026, 0))) for p in path[:6]], 0.02, "red", seg=4, scale=(1.0, 0.2))
        at = centre + up * 0.35
        box("Toe iron", (0.24, 0.07, 0.07), tuple(at + Vector((0, -0.04, 0))), "steel", r=0.01, rot=euler(ry=-s * 0.3))
        box("Strap", (0.25, 0.08, 0.05), tuple(at + Vector((0, -0.04, -0.12))), "leather", r=0.01, rot=euler(ry=-s * 0.3))
    lathe("Mountain", [(0.001, 0.66), (0.5, 0.66), (0.48, 0.7), (0.38, 0.86), (0.27, 1.04), (0.17, 1.2), (0.08, 1.31), (0.001, 1.34)],
          (0, 0, 0), "gilt", seg=24)
    for a in (0.6, 2.4, 4.3):
        ball("Rock", 0.12, (0.36 * math.cos(a), 0.36 * math.sin(a), 0.82), "gilt", scale=(1.0, 0.8, 0.7), seg=10, rings=6)
    for s in (-1, 1):
        x = s * 0.09
        box("Skier ski", (0.07, 0.85, 0.025), (x, -0.05, 1.37), "gilt", r=0.01, seg=1)
        sweep("Ski tip", [(x, -0.47, 1.37), (x, -0.52, 1.39), (x, -0.55, 1.43)], 0.03, "gilt", seg=6, scale=(1.0, 0.3))
        ball("Boot", 0.06, (x, 0.08, 1.42), "gilt", scale=(0.8, 1.4, 0.9), seg=10)
        sweep("Shin", [(x, 0.08, 1.44), (x, -0.08, 1.6)], 0.05, "gilt", seg=10, r1=0.055)
        sweep("Thigh", [(x, -0.08, 1.6), (x * 1.1, 0.14, 1.74)], 0.06, "gilt", seg=10, r1=0.07)
        sweep("Arm", spline([(s * 0.15, -0.12, 1.84), (s * 0.12, -0.26, 1.76), (s * 0.06, -0.33, 1.74)], 2), 0.035, "gilt", seg=8, r1=0.03)
        ball("Glove", 0.035, (s * 0.05, -0.35, 1.74), "gilt", seg=8, rings=6)
        tube("Pole", (s * 0.06, -0.33, 1.72), (s * 0.3, 0.42, 1.48), 0.01, "chrome", 6)
        torus("Basket", 0.04, 0.008, (s * 0.28, 0.36, 1.5), "chrome", seg=12, ring_seg=3, rot=towards((s * 0.24, 0.75, -0.24)))
    ball("Hips", 0.13, (0, 0.14, 1.76), "gilt", scale=(1.1, 1.0, 0.8), seg=14)
    sweep("Torso", [(0, 0.12, 1.78), (0, -0.05, 1.82), (0, -0.18, 1.82)], [0.14, 0.15, 0.12], "gilt", seg=14, scale=(1.1, 0.8))
    ball("Head", 0.1, (0, -0.26, 1.88), "gilt", seg=14)
    torus("Goggles", 0.07, 0.012, (0, -0.33, 1.9), "gilt", axis="Y", seg=14, ring_seg=3, rot=Matrix.Diagonal((1.3, 1, 0.6, 1)))


def tapered(o, width, front=None):
    """Narrows a prism made from y -1 … 1 (its local y) to ±width(x): a skull narrow at the snout, wide at the back.
    `front`: (out, depth) puts it on the front side instead, from -width(x) - out to -width(x) + depth (a hole's lining)."""
    for v in o.data.vertices:
        w = width(v.co.x)
        if front is None:
            v.co.y = w * v.co.y
        else:
            v.co.y = -w - front[0] if v.co.y < 0 else -w + front[1]
    return o


def trex_skull(W, H, D):
    """A Tyrannosaurus rex skull (a museum's cast; the snout to the right, as the game's to its left) on two steel rods
    on its black plinth: the skull narrow at the snout and wide behind the eyes, its holes (the nostril, the big one in
    front of the eye, the eye, the one behind it), the brow bosses, the lower jaw and its hole, the rows of teeth; the
    plinth's plate (the game prints T. REX · 66 MILLION YEARS on it)."""
    box("Plinth", (4.0, 1.6, 0.34), (0, 0, 0.17), "dark", r=0.04, seg=3)
    box("Plinth top", (3.8, 1.4, 0.06), (0, 0, 0.37), "dark", r=0.02)
    box("Plate", (1.6, 0.02, 0.2), (0, -0.81, 0.2), "brass", r=0.006)  # (the game prints T. REX · 66 MILLION YEARS on it)
    for x, top in ((-0.9, 1.1), (0.9, 1.43)):
        cyl("Rod", 0.04, top - 0.4, (x, 0, (top + 0.4) / 2), "steel", seg=12, edge=0)
        cyl("Rod foot", 0.12, 0.04, (x, 0, 0.42), "steel", seg=16, edge=0.01)
        box("Bracket", (0.24, 0.36, 0.04), (x, 0, top), "steel", r=0.01, seg=1)

    def skull_w(x):  # its half width: 0.6 behind the eyes, 0.24 at the snout's tip
        return 0.6 if x <= -0.9 else 0.6 - 0.36 * (x + 0.9) / 2.88

    def jaw_w(x):
        return 0.45 if x <= -0.9 else 0.45 - 0.25 * (x + 0.9) / 2.82
    skull = spline([(1.98, 1.72), (1.9, 1.98), (1.65, 2.2), (1.2, 2.42), (0.6, 2.6), (0.05, 2.78), (-0.45, 2.95), (-0.85, 2.92),
                    (-1.35, 2.82), (-1.8, 2.66), (-2.05, 2.35), (-2.06, 1.95), (-1.85, 1.6), (-1.5, 1.52), (-0.9, 1.58), (-0.2, 1.6),
                    (0.5, 1.6), (1.2, 1.62), (1.75, 1.64), (1.98, 1.72)], 2)
    tapered(prism("Skull", skull, -1.0, 1.0, "fossil", r=0.08, seg=2), skull_w)
    jaw = spline([(1.92, 1.6), (1.4, 1.5), (0.6, 1.36), (-0.2, 1.2), (-1.0, 1.06), (-1.6, 1.04), (-1.92, 1.2), (-1.9, 1.45),
                  (-1.6, 1.55), (-0.8, 1.56), (0.2, 1.57), (1.2, 1.58), (1.92, 1.6)], 2)
    tapered(prism("Jaw", jaw, -1.0, 1.0, "fossil", r=0.06, seg=2), jaw_w)
    holes = ((-0.55, 2.42, 0.2, 0.24, skull_w), (0.35, 2.12, 0.42, 0.17, skull_w), (1.65, 2.2, 0.13, 0.07, skull_w),
             (-1.35, 2.05, 0.26, 0.22, skull_w), (-1.25, 1.3, 0.22, 0.08, jaw_w))
    for cx, cz, rx, rz, width in holes:
        ring = [(cx + rx * math.cos(a), cz + rz * math.sin(a)) for a in (2 * math.pi * k / 16 for k in range(16))]
        for side in (-1, 1):
            hole = tapered(prism("Hole", ring, -1.0, 1.0, "black", r=0), width, front=(0.012, 0.06))
            if side > 0:
                for v in hole.data.vertices:
                    v.co.y = -v.co.y
                hole.data.flip_normals()
    for side in (-1, 1):
        ball("Brow boss", 0.16, (-0.55, side * 0.42, 2.8), "fossil", scale=(1.0, 0.7, 0.8), seg=12)
        for k in range(11):  # the upper teeth, biggest in the middle of the snout
            x = 1.82 - k * 0.17
            size = 0.13 + 0.08 * math.sin(math.pi * (k + 1) / 12)
            cyl("Tooth", 0.035, size, (x, side * (skull_w(x) - 0.07), 1.62 - size / 2 + 0.02), "cream", seg=6, r2=0.003, edge=0,
                rot=euler(rx=math.pi) @ euler(ry=0.15))
        for k in range(9):
            x = 1.7 - k * 0.18
            size = 0.1 + 0.05 * math.sin(math.pi * (k + 1) / 10)
            cyl("Tooth", 0.03, size, (x, side * (jaw_w(x) - 0.06), 1.56 + size / 2 - 0.02), "cream", seg=6, r2=0.003, edge=0)


def zombie_safe(W, H, D):
    """Grandma's zombie-proof safe: the painted steel body with its rivets on a plinth under a cap, the door with its gap
    and gold pinstripe, the three-spoke handle, the combination dial and its index, three barrel hinges, a chain round it
    all with a gold padlock, claw marks scraped to the bare steel down one side, and the maker's plate (the game prints
    ZOMBIE-PROOF on it)."""
    box("Plinth", (2.5, 2.2, 0.25), (0, 0.1, 0.125), "dark", r=0.04, seg=2)
    box("Body", (2.4, 2.1, 2.95), (0, 0.1, 1.725), "lacquer", r=0.07, seg=3)
    box("Cap", (2.5, 2.2, 0.2), (0, 0.1, 3.3), "dark", r=0.05, seg=2)
    box("Door", (1.9, 0.08, 2.35), (0, -0.99, 1.6), "lacquer", r=0.03, seg=2)
    rect_frame("Door gap", 0.975, 1.2, [(0, 0.0), (0, -0.015), (0.03, -0.015), (0.03, 0.0)], "black", place=Matrix.Translation((0, -0.955, 1.6)))
    rect_frame("Pinstripe", 0.88, 1.1, [(0, 0.0), (0, -0.006), (0.02, -0.006), (0.02, 0.0)], "gilt", place=Matrix.Translation((0, -1.03, 1.6)))
    box("Plate", (1.5, 0.12, 0.3), (0, -0.99, 3.0), "brass", r=0.02)  # (the game prints ZOMBIE-PROOF on it)
    for s in (-1, 1):
        for k in range(9):
            ball("Rivet", 0.03, (s * 1.12, -0.955, 0.45 + k * 0.31), "dark", seg=8, rings=4)
    # the handle (the game's x 0.3: here -0.3): a hub and three spokes out of it, a knob at each end
    lathe("Hub", [(0.001, 0.0), (0.17, 0.0), (0.17, 0.04), (0.13, 0.08), (0.1, 0.12), (0.001, 0.12)], (-0.3, -1.03, 1.75), "chrome", seg=24,
          rot=OUT_FRONT)
    for n in range(3):
        a = math.pi / 2 + n * 2 * math.pi / 3
        tip = (-0.3 - 0.5 * math.cos(a), -1.12, 1.75 + 0.5 * math.sin(a))
        tube("Spoke", (-0.3, -1.12, 1.75), tip, 0.03, "chrome", 10)
        ball("Knob", 0.07, tip, "chrome", seg=12)
    lathe("Dial", [(0.001, 0.0), (0.21, 0.0), (0.21, 0.03), (0.19, 0.06), (0.17, 0.08), (0.001, 0.08)], (0.4, -1.03, 2.25), "chrome", seg=32,
          rot=OUT_FRONT)
    cyl("Dial face", 0.15, 0.006, (0.4, -1.114, 2.25), "cream", axis="Y", seg=28, edge=0)
    for k in range(20):
        a = k * math.pi / 10
        box("Dial tick", (0.008, 0.004, 0.03 if k % 5 == 0 else 0.018), (0.4 + 0.125 * math.sin(a), -1.118, 2.25 + 0.125 * math.cos(a)), "black",
            r=0, rot=euler(ry=a))
    cyl("Dial knob", 0.05, 0.05, (0.4, -1.13, 2.25), "black", axis="Y", seg=14, edge=0)
    box("Dial index", (0.012, 0.01, 0.05), (0.4, -1.04, 2.5), "red", r=0)
    for z in (0.8, 1.6, 2.4):  # (the game's x -0.97)
        cyl("Hinge", 0.06, 0.28, (0.97, -1.0, z), "chrome", seg=12, edge=0.01)
        ball("Hinge cap", 0.05, (0.97, -1.0, z + 0.15), "chrome", seg=8, rings=5)

    def chain(a, b, step=0.13):
        a, b = Vector(a), Vector(b)
        n = max(1, round((b - a).length / step))
        d = (b - a).normalized()
        for k in range(n + 1):
            twist = euler(rz=math.pi / 2) if k % 2 else Matrix()
            torus("Chain link", 0.065, 0.014, tuple(a + (b - a) * (k / n)), "steel", seg=8, ring_seg=3, rot=towards(d) @ twist @ euler(rx=math.pi / 2))
    chain((-1.15, -1.09, 0.95), (1.15, -1.09, 0.95))
    for s in (-1, 1):
        chain((s * 1.22, -0.98, 0.95), (s * 1.22, 1.1, 0.95))
    prism("Padlock", [(-0.15, 0.62), (0.15, 0.62), (0.15, 0.9), (0.12, 0.96), (-0.12, 0.96), (-0.15, 0.9)], -1.19, -1.07, "gold", r=0.02)
    torus("Shackle", 0.09, 0.022, (0, -1.13, 0.96), "chrome", axis="Y", seg=16, ring_seg=5, arc=math.pi)
    cyl("Keyhole", 0.025, 0.008, (0, -1.195, 0.78), "black", axis="Y", seg=10, edge=0)
    for z0, y0 in ((2.55, -0.45), (2.6, -0.2), (2.52, 0.05), (2.45, 0.3)):  # (the game's +X side: here -x)
        pts = [(-1.204, y0 + 0.08 * t, z0 - 0.75 * t - 0.05 * math.sin(math.pi * t)) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
        sweep("Claw mark", pts, 0.022, "steel", seg=5, r1=0.006, scale=(0.3, 1.0))


BUILD = {
    "sofa": sofa, "armchair": lambda W, H, D: sofa(W, H, D, True), "tv": tv, "coffee_table": coffee_table,
    "floor_lamp": floor_lamp, "bookshelf": bookshelf, "painting": painting, "plant": plant, "piano": piano,
    "grandfather_clock": grandfather_clock, "record_player": record_player, "fridge": fridge, "microwave": microwave,
    "dining_table": dining_table, "dining_chair": dining_chair, "dishes_box": dishes_box, "radio": radio, "bed": bed,
    "wardrobe": wardrobe, "nightstand": nightstand, "dresser": dresser, "mirror": mirror, "photo_album": photo_album,
    "kids_bed": lambda W, H, D: bed(W, H, D, True), "rocking_horse": rocking_horse, "toy_box": toy_box, "desk": desk,
    "guitar": guitar, "washing_machine": washing_machine, "laundry_basket": laundry_basket, "coat_rack": coat_rack,
    "shoe_cabinet": shoe_cabinet, "bicycle": bicycle, "toolbox": toolbox, "lawn_mower": lawn_mower, "box": moving_box,
    "bowling_trophy": bowling_trophy, "vintage_radio": vintage_radio, "old_globe": old_globe, "stag_head": stag_head,
    "gold_record": gold_record, "ship_bottle": ship_bottle, "jewellery_box": jewellery_box, "antique_vase": antique_vase,
    "arcade_cabinet": arcade_cabinet, "jukebox": jukebox, "oil_painting": oil_painting, "knight_armour": knight_armour,
    "antique_typewriter": antique_typewriter, "vintage_camera": vintage_camera, "carved_bear": carved_bear,
    "gramophone": gramophone, "pocket_watch": pocket_watch, "golden_horseshoe": golden_horseshoe,
    "crystal_chandelier": crystal_chandelier, "alphorn": alphorn, "signed_guitar": signed_guitar, "ski_trophy": ski_trophy,
    "trex_skull": trex_skull, "zombie_safe": zombie_safe,
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
    rows = -(-len(ITEMS) // COLUMNS)
    o.location = (CELL * (COLUMNS - 1) / 2, -CELL * (rows - 1) / 2, -0.001)
    o.scale = (1.0, rows / 5, 1.0)
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
    aim(cam, Vector((CELL * 2.5, -CELL * (rows - 1) / 2, 2)), Vector((-1, -1.4, 1.0)), 70 * rows / 6)
    return cam


def aim(cam, target, direction, distance, ortho=None):
    cam.location = target + direction.normalized() * distance
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type, cam.data.ortho_scale = "ORTHO", ortho
    else:
        cam.data.type, cam.data.lens = "PERSP", 35


def showcase_lights():
    """A soft key light from the front left and a rim light from behind (each piece's own, moved with the camera), so
    gold, chrome and glass catch highlights; not seen by the camera."""
    lights = []
    for name, energy, size in (("Key light", 1.0, 1.0), ("Rim light", 0.7, 0.6)):
        o = bpy.data.objects.get(name)
        if not o:
            o = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
            bpy.data.collections["Furniture"].objects.link(o)
            o.data.color = (1.0, 0.98, 0.95) if name == "Key light" else (0.9, 0.95, 1.0)
            for ray in ("visible_camera", "visible_transmission"):  # (not seen, nor through glass)
                try:
                    setattr(o, ray, False)
                except AttributeError:
                    pass
        lights.append((o, energy, size))
    return lights


def render_all(folder, samples=48, only=None):
    """Renders every piece (`only`: just these ids, and no living room) as item-NN-<id>.png, then the living room."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples, scene.cycles.use_denoising = samples, True
    os.makedirs(folder, exist_ok=True)
    cam = scene.camera
    cats = bpy.data.collections["Furniture"].children
    room = bpy.data.collections.get("Room")
    lights = showcase_lights()
    # The catalogue: one piece at a time, the others hidden.
    scene.render.resolution_x, scene.render.resolution_y = 520, 520
    if room:
        room.hide_render = True
    for i, (fid, name, w, h, d) in enumerate(ITEMS):
        if only and fid not in only:
            continue
        for c in cats:
            c.hide_render = c.name != "F_" + fid
        size = max(w, h, d)
        target = cell(i) + Vector((0, 0, h / 2))
        aim(cam, target, Vector((-0.75, -1.25, 0.7)), 40, ortho=size * 1.45)
        for (lamp, energy, scale), way in zip(lights, (Vector((-1.3, -1.2, 1.6)), Vector((1.4, 1.6, 1.2)))):
            lamp.location = target + way.normalized() * size * 2.2
            lamp.rotation_euler = (target - lamp.location).to_track_quat("-Z", "Y").to_euler()
            lamp.data.size = size * 1.2 * scale
            lamp.data.energy = 28 * energy * size * size
            lamp.hide_render = False
        scene.render.filepath = os.path.join(folder, f"item-{i:02d}-{fid}.png")
        bpy.ops.render.render(write_still=True)
    for lamp, *_ in lights:
        lamp.hide_render = True
    for c in cats:
        c.hide_render = False
    if only:
        return
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
        only = set(arg("--only").split(",")) if arg("--only") else None
        if only and "collectibles" in only:  # (--only collectibles: all 24; --only new83: 8.3's twelve)
            only |= set(COLLECTIBLES)
        if only and "new83" in only:
            only |= set(NEW_83)
        render_all(arg("--render"), int(arg("--samples") or 48), only)
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        manifest = export_game(folder)
        tris = sum(p["triangles"] for p in manifest["pieces"].values())
        print(f"ZDCFurnitureArt: {len(manifest['pieces'])} pieces, {tris} triangles, the largest {max(p['triangles'] for p in manifest['pieces'].values())}")
    for fid, over, filled in report:
        print(f"  {fid:18s} fills {filled}  sticks out {over}")


main()
