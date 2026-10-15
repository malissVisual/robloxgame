"""Zombie Delivery: zařízení domu v Blenderu (8.9.1): kuchyně, koupelna, kachlová kamna a garáž.

Spuštění v Blenderu: záložka Scripting → Open → fixtures.py → Run Script (▶, nebo Alt+P). Skript postaví všech 15 druhů
zařízení, které dům ve hře staví z dílů (server/HouseInterior.luau, LOOKS): kuchyňskou linku, sporák, linku s dřezem,
horní skříňky, digestoř, rohovou lavici a její krátké rameno, svatý koutek, vanu, záchod, umyvadlo se zrcadlem,
kachlová kamna, ponk, regál a garážová vrata. Stojí v řadě v kolekci "Zařízení" a vedle jsou čtyři zařízené místnosti
(kuchyně, koupelna, obývák s kamny a garáž) na náhled.
Každý druh má přesně svou krabici ze hry (KONTRAKT.md): 1 jednotka = 1 stud, předek míří na -Y (do místnosti), záda na +Y
(ke zdi), spodek je na zemi. Kus na zdi (skříňky, digestoř, svatý koutek) má spodek krabice ve své výšce nad podlahou.

Bez Blenderu, jen s modulem bpy (pip install bpy):
    python fixtures.py -- --save fixtures.blend --export roblox --render složka --samples 96
    (--only druh,druh: render jen těchto druhů po jednom, bez místností)
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

# ───────────────────────────────────────────────────────────── NASTAVENÍ
EXPORT = False   # True = uloží ZDCFixtureArt.fbx pro hru do složky "roblox" vedle .blend souboru
GAP = 3.0        # mezera mezi druhy v řadě (studs)

# Druhy ze hry (KONTRAKT.md, shared/HouseLayout.luau): id, název, šířka (podél zdi), výška, hloubka, výška rámu v domě.
# Rozměry neměň: hra má stejné a kontrola tools/fixtures-art/check.py hlídá, že sedí.
KINDS = [
    ("counter", "Kuchyňská linka", 4.5, 3.0, 2.6, 0.0),
    ("stove", "Sporák", 3.0, 3.0, 2.6, 0.0),
    ("sink", "Linka s dřezem", 9.0, 3.0, 2.6, 0.0),
    ("cabinets", "Horní skříňky", 4.5, 3.0, 1.4, 6.4),
    ("hood", "Digestoř", 3.0, 2.2, 1.8, 7.0),
    ("corner_bench", "Rohová lavice", 7.0, 3.4, 1.6, 0.0),
    ("bench", "Krátká lavice", 2.4, 3.4, 1.6, 0.0),
    ("corner_shelf", "Svatý koutek", 2.2, 1.4, 2.2, 4.9),
    ("tub", "Vana", 7.2, 2.2, 3.4, 0.0),
    ("toilet", "Záchod", 1.8, 3.2, 2.8, 0.0),
    ("basin", "Umyvadlo", 2.6, 3.2, 1.8, 0.0),
    ("kachelofen", "Kachlová kamna", 6.0, 6.6, 3.2, 0.0),
    ("workbench", "Ponk", 6.4, 3.2, 2.4, 0.0),
    ("shelves", "Regál", 5.0, 7.0, 1.6, 0.0),
    ("garage_door", "Garážová vrata", 12.0, 8.5, 0.3, 0.0),
]
# Kam smí druh ze své krabice nahoru (nejvyšší bod nad spodkem krabice): tam, kam sahá i dnešní vzhled z dílů. Digestoř:
# komín až ke stropu (12 nad podlahou), umyvadlo: zrcadlo, ponk: děrovaná deska (a svěrák na desce), dřez a vana: baterie.
REACH = {"hood": 5.0, "basin": 6.9, "workbench": 5.5, "sink": 3.8, "tub": 2.8}

# Povrchy: jméno → (barva #RRGGBB, drsnost, kov, záře, materiál v Robloxu). Hra (server/FixtureMesh.luau) dá každému
# povrchu barvu a materiál. PALETTE: tyhle čtyři barví hra podle domu (dlaždice kamen, jejich horní patro, borovice lavic
# a polštář), barva tady je jen ukázka.
FINISHES = {
    "cabinet": ("#C69864", 0.6, 0, 0, "Wood"), "worktop": ("#8E6844", 0.5, 0, 0, "Wood"),
    "enamel": ("#EFE7D3", 0.22, 0, 0, "SmoothPlastic"), "blackglass": ("#1B1B1E", 0.12, 0, 0, "SmoothPlastic"),
    "chrome": ("#D7DBDF", 0.15, 1, 0, "Metal"), "steel": ("#B0B6BC", 0.32, 1, 0, "Metal"),
    "porcelain": ("#F4F2EC", 0.12, 0, 0, "SmoothPlastic"), "water": ("#86BED8", 0.05, 0, 0, "Glass"),
    "mirror": ("#C4D6E0", 0.02, 1, 0, "Glass"), "woodwork": ("#845836", 0.55, 0, 0, "Wood"),
    "candle": ("#F2EAD6", 0.6, 0, 0, "SmoothPlastic"), "flower": ("#C4704A", 0.9, 0, 0, "Fabric"),
    "tile": ("#406E54", 0.18, 0, 0, "SmoothPlastic"), "tile2": ("#577F68", 0.18, 0, 0, "SmoothPlastic"),
    "grout": ("#D6CDBB", 0.9, 0, 0, "SmoothPlastic"), "iron": ("#302C2A", 0.45, 0.7, 0, "Metal"),
    "glow": ("#FF8A3A", 0.5, 0, 6.0, "Neon"), "pine": ("#BA8652", 0.6, 0, 0, "Wood"),
    "cushion": ("#B03430", 0.95, 0, 0, "Fabric"), "wood": ("#AA8052", 0.6, 0, 0, "Wood"),
    "board": ("#BEA078", 0.85, 0, 0, "Cardboard"), "vise": ("#3C5A8C", 0.4, 0.4, 0, "Metal"),
    "metal": ("#787E84", 0.4, 0.8, 0, "Metal"), "card": ("#C49E6C", 0.9, 0, 0, "Cardboard"),
    "crate": ("#3C6EAA", 0.45, 0, 0, "SmoothPlastic"), "door": ("#C8CCCE", 0.35, 0.6, 0, "Metal"),
    "rubber": ("#1E1E20", 0.9, 0, 0, "Rubber"),
}
PALETTE = ("tile", "tile2", "pine", "cushion")
# Navíc pro hru: lesk (reflectance) a průhlednost (transparency) v Robloxu.
GAME = {"enamel": {"reflectance": 0.04}, "blackglass": {"reflectance": 0.12}, "chrome": {"reflectance": 0.3},
        "porcelain": {"reflectance": 0.08}, "water": {"transparency": 0.35}, "mirror": {"reflectance": 0.5},
        "tile": {"reflectance": 0.05}, "tile2": {"reflectance": 0.05}}
# Navíc pro Blender: lesk glazury a smaltu (Coat), voda propouští světlo (Transmission).
SPECIAL = {
    "enamel": {"Coat Weight": 0.7, "Coat Roughness": 0.05}, "porcelain": {"Coat Weight": 0.8, "Coat Roughness": 0.03},
    "tile": {"Coat Weight": 0.8, "Coat Roughness": 0.04}, "tile2": {"Coat Weight": 0.8, "Coat Roughness": 0.04},
    "blackglass": {"Coat Weight": 1.0, "Coat Roughness": 0.02},
    "water": {"Transmission Weight": 1.0, "IOR": 1.33},
}

M = {}
CUR = Vector()   # the origin of the kind being built (the bottom middle of its box)
COL = None       # its collection


def linear(hexcode):
    h = hexcode.lstrip("#")
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))


def materials():
    for name, (hexcode, rough, metal, emit, _) in FINISHES.items():
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
        glow = p.inputs.get("Emission Color") or p.inputs.get("Emission")
        glow.default_value = rgba if emit else (0, 0, 0, 1)
        p.inputs["Emission Strength"].default_value = emit
        for key, value in SPECIAL.get(name, {}).items():
            if p.inputs.get(key) is not None:
                p.inputs[key].default_value = value
        if FINISHES[name][4] == "Wood" and not m.node_tree.nodes.get("Grain"):
            grain(m, p, rgba)
        m["finish"] = name
        M[name] = m


def grain(m, p, rgba):
    """A wood finish's grain in Blender's renders (bands along x: a worktop's, a seat's planks; the game draws its own)."""
    nt = m.node_tree
    coords = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.name, wave.bands_direction = "Grain", "Y"
    for key, value in (("Scale", 1.6), ("Distortion", 1.6), ("Detail", 2.0), ("Detail Scale", 1.2)):
        wave.inputs[key].default_value = value
    nt.links.new(coords.outputs["Object"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = tuple(c * 0.86 for c in rgba[:3]) + (1,)
    ramp.color_ramp.elements[1].color = rgba
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])


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


SIDE_VIEW = Matrix.Rotation(math.pi / 2, 4, "Z")  # (side-view outlines: y, z, pushed along x)
TOP_VIEW = euler(rx=math.pi / 2)                   # (top-view outlines: x, -y, pushed along z: plate)
OUT_FRONT = euler(rx=math.pi / 2)                  # (a lathe's axis out of the front, -y)


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


def place(o, at, rot=None):
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix())
    return o


def box(name, size, at, finish, r=0.03, rot=None, seg=2):
    """A box with rounded edges (a Bevel modifier: `r` its width, `seg` its segments)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    sharpen(bm)
    o = place(obj(name, bm, finish), at, rot)
    return bevel(o, min(r, min(size) * 0.45), seg)


def chamfer(name, size, at, finish, c=0.02, rot=None):
    """A box with chamfered edges (built in: light, crisp)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=min(c, min(size) * 0.45), segments=1, affect="EDGES")
    return place(obj(name, bm, finish, smooth=False), at, rot)


def cyl(name, r, h, at, finish, axis="Z", seg=16, r2=None, edge=0.0, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    sharpen(bm)
    o = obj(name, bm, finish)
    turn = {"Z": Matrix(), "X": euler(ry=math.pi / 2), "Y": euler(rx=math.pi / 2)}[axis]
    o.matrix_world = Matrix.Translation(CUR + Vector(at)) @ (rot or Matrix()) @ turn
    return bevel(o, edge, 1)


def tube(name, a, b, r, finish, seg=8):
    a, b = CUR + Vector(a), CUR + Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=(b - a).length)
    sharpen(bm)
    o = obj(name, bm, finish)
    o.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat("Z", "Y").to_matrix().to_4x4()
    return o


def ball(name, r, at, finish, scale=(1, 1, 1), rot=None, seg=8, rings=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings or max(4, seg // 2), radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    return place(obj(name, bm, finish), at, rot)


def lathe(name, profile, at, finish, seg=16, scale=(1, 1), rot=None):
    """A turned shape: `profile` (radius, height) points spun round Z (a candlestick, a jug, a pedestal)."""
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in profile]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    es.append(bm.edges.new((vs[-1], vs[0])))
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=seg, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.scale(bm, vec=Vector((scale[0], scale[1], 1)), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharpen(bm, 50)
    return place(obj(name, bm, finish), at, rot)


def torus(name, R, r, at, finish, seg=24, ring_seg=6, rot=None):
    bm = bmesh.new()
    rim = [bm.verts.new((R + r * math.cos(a), 0, r * math.sin(a))) for a in (2 * math.pi * i / ring_seg for i in range(ring_seg))]
    es = [bm.edges.new((rim[i], rim[(i + 1) % ring_seg])) for i in range(ring_seg)]
    bmesh.ops.spin(bm, geom=rim + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=seg, use_merge=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return place(obj(name, bm, finish), at, rot)


def bezier(p0, p1, p2, p3, n=8):
    P = [Vector(p) for p in (p0, p1, p2, p3)]
    return [tuple(P[0] * (1 - t) ** 3 + P[1] * 3 * (1 - t) ** 2 * t + P[2] * 3 * (1 - t) * t * t + P[3] * t ** 3)
            for t in (k / n for k in range(n + 1))]


def sweep(name, pts, r, finish, seg=8):
    """A tube along a path (a tap's swan neck, a saw's handle)."""
    P = [CUR + Vector(p) for p in pts]
    n = len(P)
    T = [(P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized() for i in range(n)]
    ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((0, -1, 0))
    normal = (ref - T[0] * ref.dot(T[0])).normalized()
    bm = bmesh.new()
    rings = []
    for i in range(n):
        if i:
            normal = T[i - 1].rotation_difference(T[i]) @ normal
            normal = (normal - T[i] * normal.dot(T[i])).normalized()
        side = T[i].cross(normal)
        rings.append([bm.verts.new(P[i] + (normal * math.cos(a) + side * math.sin(a)) * r) for a in (2 * math.pi * k / seg for k in range(seg))])
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharpen(bm, 50)
    return obj(name, bm, finish)


def prism(name, outline, y0, y1, finish, r=0.03, seg=2, at=(0, 0, 0), rot=None, smooth=True):
    """A flat shape drawn in the front view (x, z points round its edge) and pushed back from y0 to y1; turned with
    SIDE_VIEW it is a side view (y, z) pushed along x, with TOP_VIEW a top view (plate)."""
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
    o = place(obj(name, bm, finish, smooth), at, rot)
    return bevel(o, r, seg)


def plate(name, pts, z0, z1, finish, r=0.02, seg=2, at=(0, 0, 0)):
    """A flat board drawn from above (x, y points round its edge), from z0 up to z1."""
    return prism(name, [(x, -y) for x, y in pts], z0, z1, finish, r=r, seg=seg, at=at, rot=TOP_VIEW)


def rr(hw, hd, r, z, n=4, cx=0.0, cy=0.0):
    """A ring round a rounded rectangle (half width hw, half depth hd, corners of radius r), counterclockwise."""
    r = max(0.002, min(r, hw - 0.001, hd - 0.001))
    pts = []
    for sx, sy, a0 in ((1, -1, -90), (1, 1, 0), (-1, 1, 90), (-1, -1, 180)):
        ox, oy = cx + sx * (hw - r), cy + sy * (hd - r)
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a), z))
    return pts


def oval(a, b, z, n=20, p=2.4, cy=0.0):
    """A ring round a superellipse (a toilet's bowl), counterclockwise from the front."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n - math.pi / 2
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2 / p), c), cy + b * math.copysign(abs(s) ** (2 / p), s), z))
    return pts


def rect(hw, front, back, z):
    """A rectangle ring against the wall (its back fixed), counterclockwise."""
    return [(hw, front, z), (hw, back, z), (-hw, back, z), (-hw, front, z)]


def loft(name, rings, finish, cap0=True, cap1=True, sharp=50, at=(0, 0, 0), rot=None, smooth=True):
    """A shell through rings of points (all the same count, counterclockwise from above): a tub, a basin, a hood. The
    faces turn as the rings go (up the outside, over a rim, down the inside), `cap0` closes the first ring (seen from
    below), `cap1` the last (seen from above)."""
    bm = bmesh.new()
    R = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for a, b in zip(R, R[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    caps = []
    if cap0:
        caps.append(bm.faces.new(list(reversed(R[0]))))
    if cap1:
        caps.append(bm.faces.new(R[-1]))
    if caps:
        bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    sharpen(bm, sharp)
    return place(obj(name, bm, finish, smooth), at, rot)


def tiles(name, origin, u, v, cols, rows, su, sv, finish, gap=0.04, relief=0.05, edge=0.04, dish=0.02, skip=()):
    """Raised tiles on a flat face: its corner `origin`, `u` along it (cols over `su`), `v` up it (rows over `sv`);
    the tiles stand out of it towards u × v. Each tile: a chamfered edge and a shallow dish (a Kachelofen's tile, a
    garage door's cassette); `skip` leaves out (col, row) tiles (a door there)."""
    O, U, V = Vector(origin), Vector(u).normalized(), Vector(v).normalized()
    N = U.cross(V)
    bm = bmesh.new()
    du, dv = su / cols, sv / rows
    for i in range(cols):
        for j in range(rows):
            if (i, j) in skip:
                continue
            u0, u1, v0, v1 = i * du + gap / 2, (i + 1) * du - gap / 2, j * dv + gap / 2, (j + 1) * dv - gap / 2

            def ring(inset, h):
                return [bm.verts.new(O + U * a + V * b + N * h) for a, b in
                        ((u0 + inset, v0 + inset), (u1 - inset, v0 + inset), (u1 - inset, v1 - inset), (u0 + inset, v1 - inset))]
            base, top = ring(0, 0), ring(edge, relief)
            for k in range(4):
                bm.faces.new((base[k], base[(k + 1) % 4], top[(k + 1) % 4], top[k]))
            if dish:
                inner = ring(edge + min(du, dv) * 0.12, relief - dish)
                for k in range(4):
                    bm.faces.new((top[k], top[(k + 1) % 4], inner[(k + 1) % 4], inner[k]))
                bm.faces.new(inner)
            else:
                bm.faces.new(top)
    return place(obj(name, bm, finish, smooth=False), (0, 0, 0))


def holed(name, x0, x1, y0, y1, hx0, hx1, hy0, hy1, z0, z1, finish, r=0.02, seg=2):
    """A slab with a rectangular hole (a worktop round its sink)."""
    bm = bmesh.new()

    def ring(z, xa, xb, ya, yb):
        return [bm.verts.new(p) for p in ((xa, ya, z), (xb, ya, z), (xb, yb, z), (xa, yb, z))]
    ob, ot, ib, it = ring(z0, x0, x1, y0, y1), ring(z1, x0, x1, y0, y1), ring(z0, hx0, hx1, hy0, hy1), ring(z1, hx0, hx1, hy0, hy1)
    for k in range(4):
        m = (k + 1) % 4
        bm.faces.new((ob[k], ob[m], ot[m], ot[k]))
        bm.faces.new((it[k], it[m], ib[m], ib[k]))
        bm.faces.new((ot[k], ot[m], it[m], it[k]))
        bm.faces.new((ib[k], ib[m], ob[m], ob[k]))
    sharpen(bm)
    return bevel(place(obj(name, bm, finish), (0, 0, 0)), r, seg)


def rect_frame(name, hw, hh, profile, finish, place_at):
    """A frame's moulding round a rectangle (half width hw, half height hh, in the front view round `place_at`):
    `profile` (inset from the outer edge, y) points round its section, mitred at the corners."""
    m = Matrix.Translation(CUR) @ place_at
    bm = bmesh.new()
    rings = []
    for inset, y in profile:
        w, h = hw - inset, hh - inset
        rings.append([bm.verts.new(m @ Vector((x, y, z))) for x, z in ((-w, -h), (w, -h), (w, h), (-w, h))])
    for i in range(len(rings)):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    sharpen(bm, 35)
    return obj(name, bm, finish)


def quads(name, rects, y, finish):
    """Flat little squares facing the front (-y) at depth y: (x0, z0, x1, z1) each (a pegboard's holes)."""
    bm = bmesh.new()
    for x0, z0, x1, z1 in rects:
        bm.faces.new([bm.verts.new(p) for p in ((x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1))])
    return place(obj(name, bm, finish, smooth=False), (0, 0, 0))


# ───────────────────────────────────────────────────────────── kuchyň
FRONT = -1.1      # the base cabinets' carcass front (y): doors on it, the worktop's lip out to -1.3
TOP = 2.84        # the carcass's top, the worktop's underside
WT = 2.975        # the worktop's top (a hair under the box: a sink's rim and drainer stand on it, flush with 3)


def front_panel(name, x0, x1, z0, z1, finish, frame=0.16, raised=True, t=0.06, y=FRONT):
    """A door or a drawer front on the carcass (from y back): a slab with chamfered edges, a frame round a sunk panel and
    (`raised`) a raised field in it."""
    w, h = x1 - x0, z1 - z0
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((w, t, h)), verts=bm.verts)
    face = next(f for f in bm.faces if f.normal.y < -0.99)
    bmesh.ops.bevel(bm, geom=face.verts[:] + face.edges[:], offset=0.012, segments=1, affect="EDGES")
    face = max((f for f in bm.faces if f.normal.y < -0.99), key=lambda f: f.calc_area())
    bmesh.ops.inset_individual(bm, faces=[face], thickness=frame, depth=0.0)
    bmesh.ops.inset_individual(bm, faces=[face], thickness=0.025, depth=-0.025)
    if raised:
        bmesh.ops.inset_individual(bm, faces=[face], thickness=min(0.1, w * 0.12), depth=0.022)
    return place(obj(name, bm, finish, smooth=False), ((x0 + x1) / 2, y - t / 2, (z0 + z1) / 2))


def knob(x, z, finish, y=FRONT - 0.06, r=0.06):
    """A turned wooden knob out of the front (from y forward 0.12)."""
    return lathe("Knoflík", [(0.0, 0), (r * 0.55, 0), (r * 0.5, 0.04), (r, 0.08), (r * 0.8, 0.12), (0.0, 0.12)], (x, y, z), finish,
                 seg=10, rot=OUT_FRONT)


def base_body(W, D, gaps=()):
    """The base cabinets' body: a dark plinth, the carcass (`gaps`: x ranges where it is lower, under a sink)."""
    box("Sokl", (W - 0.02, D - 0.3, 0.3), (0, 0.15, 0.15), "worktop", r=0.01, seg=1)
    deep, y = D / 2 - FRONT, (FRONT + D / 2) / 2
    x = -W / 2
    for a, b in sorted(gaps) + [(W / 2, W / 2)]:
        if a > x:
            box("Korpus", (a - x, deep, TOP - 0.3), ((x + a) / 2, y, (0.3 + TOP) / 2), "cabinet", r=0.02, seg=1)
        if b > a:
            box("Korpus", (b - a, deep, 2.3 - 0.3), ((a + b) / 2, y, (0.3 + 2.3) / 2), "cabinet", r=0.02, seg=1)
        x = b


def worktop(W, D, hole=None):
    """The scrubbed wooden worktop: a slab (round the sink's hole) and its lip along the front."""
    if hole:
        holed("Pracovní deska", -W / 2, W / 2, -D / 2 + 0.1, D / 2, *hole, TOP, WT, "worktop", r=0.02, seg=2)
    else:
        box("Pracovní deska", (W, D - 0.1, WT - TOP), (0, 0.05, (TOP + WT) / 2), "worktop", r=0.02, seg=2)
    box("Lišta desky", (W, 0.1, 0.28), (0, -D / 2 + 0.05, WT - 0.14), "worktop", r=0.03, seg=2)


def counter(W, H, D):
    base_body(W, D)
    worktop(W, D)
    cols = [(-W / 2 + 0.08, -0.03), (0.03, W / 2 - 0.08)]
    for i, (x0, x1) in enumerate(cols):
        front_panel("Šuplík", x0, x1, 2.2, 2.66, "cabinet", frame=0.08, raised=False)
        front_panel("Dvířka", x0, x1, 0.36, 2.14, "cabinet")
        knob((x0 + x1) / 2, 2.43, "worktop")
        knob(x1 - 0.22 if i == 0 else x0 + 0.22, 1.9, "worktop")


def sink(W, H, D):
    cy, hw, hd = -0.1, 1.0, 0.7          # the basin: its middle (y), its rim's half width and half depth
    base_body(W, D, gaps=[(-hw, hw)])
    worktop(W, D, hole=(-hw + 0.05, hw - 0.05, cy - hd + 0.05, cy + hd - 0.05))
    m, g = 0.08, 0.06
    cw = (W - 2 * m - 3 * g) / 4
    for i in range(4):
        x0 = -W / 2 + m + i * (cw + g)
        x1 = x0 + cw
        outer = i in (0, 3)
        front_panel("Šuplík" if outer else "Slepý šuplík", x0, x1, 2.2, 2.66, "cabinet", frame=0.08, raised=False)
        front_panel("Dvířka", x0, x1, 0.36, 2.14, "cabinet")
        if outer:
            knob((x0 + x1) / 2, 2.43, "worktop")
        knob(x1 - 0.22 if i < 2 else x0 + 0.22, 1.9, "worktop")
    # the steel basin set into the worktop: its rim on the top, the bowl down into the cabinet
    n = 3
    loft("Dřez", [rr(hw, hd, 0.16, WT, n, cy=cy), rr(hw, hd, 0.16, WT + 0.02, n, cy=cy), rr(hw - 0.07, hd - 0.07, 0.12, WT + 0.025, n, cy=cy),
                  rr(hw - 0.1, hd - 0.1, 0.1, WT - 0.005, n, cy=cy), rr(hw - 0.12, hd - 0.12, 0.1, 2.5, n, cy=cy),
                  rr(hw - 0.16, hd - 0.16, 0.08, 2.42, n, cy=cy), rr(hw - 0.24, hd - 0.24, 0.04, 2.4, n, cy=cy)], "steel", cap0=False)
    # the drainer beside it: a steel plate with ribs
    box("Odkapávač", (1.25, 2 * hd - 0.1, 0.015), (hw + 0.7, cy, WT + 0.0075), "steel", r=0.006, seg=1)
    for k in range(4):
        box("Žebro", (0.035, 2 * hd - 0.3, 0.01), (hw + 0.3 + k * 0.28, cy, WT + 0.02), "steel", r=0)
    # the swan-neck tap behind it and its two valves
    ty = 0.9
    cyl("Patka baterie", 0.09, 0.06, (0, ty, WT + 0.03), "steel", seg=10)
    neck = [(0, ty, WT + 0.03)] + [(0, ty, 3.38)] + [(0, ty - 0.26 + 0.26 * math.cos(a), 3.38 + 0.26 * math.sin(a))
                                                 for a in (math.pi * k / 6 for k in range(1, 7))] + [(0, ty - 0.52, 3.28)]
    sweep("Baterie", neck, 0.045, "steel", seg=7)
    for s in (-1, 1):
        cyl("Kohoutek", 0.055, 0.12, (s * 0.26, ty, WT + 0.06), "steel", seg=8)
        for turn in (0.4, 0.4 + math.pi / 2):
            box("Křížek", (0.24, 0.035, 0.035), (s * 0.26, ty, 3.14), "steel", r=0, rot=euler(rz=turn))


def stove(W, H, D):
    front = -1.12
    box("Sokl", (W - 0.1, D - 0.3, 0.25), (0, 0.15, 0.125), "blackglass", r=0.01, seg=1)
    box("Tělo sporáku", (W - 0.04, D / 2 - front, 2.65), (0, (front + D / 2) / 2, 0.25 + 1.325), "enamel", r=0.1, seg=3)
    box("Varná deska", (W - 0.1, D / 2 - front - 0.04, 0.06), (0, (front + D / 2) / 2, 2.93), "blackglass", r=0.02, seg=1)
    for y in (front + 0.025, D / 2 - 0.025):
        box("Rámeček", (W - 0.06, 0.03, 0.045), (0, y, 2.94), "chrome", r=0)
    for x in (-(W / 2 - 0.03), W / 2 - 0.03):
        box("Rámeček", (0.03, D / 2 - front - 0.05, 0.045), (x, (front + D / 2) / 2, 2.94), "chrome", r=0)
    for x in (-0.68, 0.68):
        torus("Hořák", 0.33, 0.02, (x, 0.1, 2.962), "chrome", seg=18, ring_seg=4)
        cyl("Plotýnka", 0.2, 0.03, (x, 0.1, 2.97), "blackglass", seg=14, edge=0.008)
    for x in (-0.85, 0.0, 0.85):
        cyl("Ovládací knoflík", 0.11, 0.1, (x, front - 0.05, 2.62), "blackglass", axis="Y", seg=12, edge=0.015)
        box("Ryska", (0.025, 0.012, 0.09), (x, front - 0.103, 2.66), "chrome", r=0)
    box("Lišta", (W - 0.3, 0.02, 0.04), (0, front - 0.01, 2.4), "chrome", r=0)
    box("Dvířka trouby", (W - 0.4, 0.06, 1.9), (0, front - 0.03, 0.32 + 0.95), "enamel", r=0.04, seg=2)
    box("Okénko trouby", (1.7, 0.02, 0.8), (0, front - 0.07, 1.25), "blackglass", r=0.08, seg=2)
    tube("Madlo", (-1.0, front - 0.145, 2.02), (1.0, front - 0.145, 2.02), 0.035, "chrome", 10)
    for x in (-0.92, 0.92):
        tube("Držák madla", (x, front - 0.05, 2.02), (x, front - 0.15, 2.02), 0.028, "chrome", 8)


def cabinets(W, H, D):
    back = D / 2
    hw = W / 2 - 0.2
    front = -0.5
    box("Korpus", (2 * hw, back - front, 2.58), (0, (front + back) / 2, 0.12 + 1.29), "cabinet", r=0.02, seg=1)
    loft("Spodní lišta", [rect(hw + 0.04, front - 0.06, back, 0.0), rect(hw + 0.05, front - 0.07, back, 0.04),
                          rect(hw + 0.05, front - 0.07, back, 0.1), rect(hw, front, back, 0.12)], "cabinet", sharp=30)
    prof = [(2.7, 0.0), (2.74, 0.0), (2.75, 0.025), (2.79, 0.04), (2.85, 0.07), (2.9, 0.12), (2.94, 0.17), (2.955, 0.2), (3.0, 0.2)]
    loft("Římsa", [rect(hw + o, front - o, back, z) for z, o in prof], "cabinet", sharp=30)
    g = 0.05
    dw = (2 * hw - 0.08 - g) / 2
    for i, x0 in enumerate((-hw + 0.04, -hw + 0.04 + dw + g)):
        front_panel("Dvířka", x0, x0 + dw, 0.2, 2.62, "cabinet", frame=0.17, y=front)
        knob(x0 + dw - 0.2 if i == 0 else x0 + 0.2, 0.45, "cabinet", y=front - 0.06)


def hood(W, H, D):
    b = D / 2
    rings = [rect(1.36, -0.76, b, 0.06), rect(1.42, -0.82, b, 0.0), rect(1.5, -0.9, b, 0.0), rect(1.5, -0.9, b, 0.2),
             rect(1.46, -0.86, b, 0.24), rect(0.72, 0.02, b, 1.05), rect(0.68, 0.06, b, 1.1), rect(0.68, 0.06, b, 1.2),
             rect(0.64, 0.1, b, 1.22), rect(0.64, 0.1, b, 3.4), rect(0.66, 0.08, b, 3.42), rect(0.66, 0.08, b, 3.5),
             rect(0.64, 0.1, b, 3.52), rect(0.64, 0.1, b, REACH["hood"])]
    bevel(loft("Kryt digestoře", rings, "steel", sharp=30), 0.015, 1, 30)
    box("Mřížka", (2.6, 1.42, 0.012), (0, 0.07, 0.066), "steel", r=0)
    for k in range(9):
        box("Lamela", (0.03, 1.38, 0.02), (-1.2 + k * 0.3, 0.07, 0.055), "steel", r=0)


# ───────────────────────────────────────────────────────────── rohová lavice (Eckbank) a svatý koutek
def eckbank(W, H, D, cushioned):
    """The kitchen's corner bench: its chest with panels under a plank seat, a panelled backrest and an end board on
    each side (the same at both ends: in a house the corner is at either end), and on the long leg two cushions."""
    t = 0.13
    hw = W / 2 - t
    box("Sokl", (2 * hw, 1.1, 0.1), (0, -0.05, 0.05), "pine", r=0.01, seg=1)
    box("Truhla", (2 * hw, 1.16, 1.28), (0, -0.08, 0.1 + 0.64), "pine", r=0.015, seg=1)
    n = max(1, round(2 * hw / 1.7))
    pw = (2 * hw - 0.22 * (n + 1)) / n
    for k in range(n):
        chamfer("Výplň", (pw, 0.05, 0.86), (-hw + 0.22 + pw / 2 + k * (pw + 0.22), -0.685, 0.75), "pine", c=0.045)
    for y0, y1, r in ((-0.8, -0.37, 0.06), (-0.35, 0.06, 0.0), (0.08, 0.5, 0.0)):
        if r:
            box("Sedák", (2 * hw, y1 - y0, 0.12), (0, (y0 + y1) / 2, 1.44), "pine", r=r, seg=2)
        else:
            chamfer("Sedák", (2 * hw, y1 - y0, 0.12), (0, (y0 + y1) / 2, 1.44), "pine", c=0.015)
    # the backrest: a board, its frame (rails and stiles) and raised panels, a rounded rail on top
    box("Opěradlo", (2 * hw, 0.1, 1.72), (0, 0.72, 1.5 + 0.86), "pine", r=0)
    box("Lišta opěradla", (2 * hw, 0.07, 0.16), (0, 0.635, 1.58), "pine", r=0.01, seg=1)
    box("Lišta opěradla", (2 * hw, 0.07, 0.18), (0, 0.635, 3.13), "pine", r=0.01, seg=1)
    nb = max(1, round(2 * hw / 1.6))
    sw = 0.16
    bw = (2 * hw - sw * (nb + 1)) / nb
    for k in range(nb + 1):
        box("Sloupek", (sw, 0.07, 1.39), (-hw + sw / 2 + k * (bw + sw), 0.635, 2.355), "pine", r=0)
    for k in range(nb):
        chamfer("Výplň opěradla", (bw, 0.04, 1.39), (-hw + sw + bw / 2 + k * (bw + sw), 0.65, 2.355), "pine", c=0.05)
    box("Madlo opěradla", (2 * hw, 0.3, 0.12), (0, 0.65, 3.28), "pine", r=0.05, seg=2)
    # the end boards: high at the back, a sweep down to an arm at the front, a foot
    curve = bezier((0.42, 3.4), (0.12, 3.4), (-0.05, 2.62), (-0.58, 2.6), 8)
    side = [(-0.77, 0.0), (0.8, 0.0), (0.8, 3.4)] + curve + [(-0.72, 2.57), (-0.79, 2.48), (-0.8, 2.35), (-0.8, 1.5),
                                                              (-0.74, 1.36), (-0.71, 0.45), (-0.77, 0.18)]
    for s in (-1, 1):
        prism("Bočnice", side, -t / 2, t / 2, "pine", r=0.03, seg=2, at=(s * (W / 2 - t / 2), 0, 0), rot=SIDE_VIEW)
    if cushioned:
        cw = (2 * hw - 0.06) / 2
        for s in (-1, 1):
            box("Polštář", (cw, 1.2, 0.2), (s * (cw / 2 + 0.015), -0.17, 1.6), "cushion", r=0.085, seg=3)
            for k in range(3):
                ball("Knoflík polštáře", 0.045, (s * (cw / 2 + 0.015) + (k - 1) * cw / 3.2, -0.17, 1.7), "cushion", scale=(1, 1, 0.45), seg=8)


def corner_bench(W, H, D):
    eckbank(W, H, D, True)


def bench(W, H, D):
    eckbank(W, H, D, False)


def bunch(x, y, turn, hand):
    """Dried flowers in a little jug with a handle (towards `hand`): thin brown stems fanned out, rust strawflowers,
    sprigs of cream ones and seed ears."""
    lathe("Džbánek", [(0.0, 0.12), (0.1, 0.12), (0.135, 0.2), (0.13, 0.31), (0.085, 0.4), (0.1, 0.45), (0.0, 0.45)], (x, y, 0), "candle", seg=10)
    hx, hy = hand
    sweep("Ucho džbánku", [(x + hx * 0.11, y + hy * 0.11, 0.39), (x + hx * 0.2, y + hy * 0.2, 0.37), (x + hx * 0.21, y + hy * 0.21, 0.27),
                           (x + hx * 0.13, y + hy * 0.13, 0.21)], 0.018, "candle", seg=4)
    for k in range(11):
        a = turn + k * 2 * math.pi / 11 + 0.3 * math.sin(k * 2.3)
        spread = 0.06 + 0.1 * ((k * 5) % 3) / 2
        h = 0.95 + 0.33 * ((k * 7) % 5) / 4
        ca, sa = math.cos(a), math.sin(a)
        tip = (x + ca * spread, y + sa * spread, h)
        sweep("Stonek", [(x + ca * 0.02, y + sa * 0.02, 0.43), (x + ca * spread * 0.4, y + sa * spread * 0.4, (0.43 + h) / 2), tip], 0.009, "woodwork", seg=3)
        kind = k % 4
        if kind in (0, 2):
            ball("Kvítek", 0.05 if kind == 0 else 0.042, tip, "flower", scale=(1, 1, 0.8), seg=6, rings=3)
        elif kind == 1:
            for j in range(3):
                b = a + j * 2.1
                ball("Kvítek", 0.028, (tip[0] + math.cos(b) * 0.035, tip[1] + math.sin(b) * 0.035, h - 0.02 * j), "candle", seg=5, rings=3)
        else:
            ball("Klas", 0.03, (tip[0], tip[1], h + 0.04), "woodwork", scale=(1, 1, 2.6), seg=5, rings=3)


def corner_shelf(W, H, D):
    """The Herrgottswinkel: a three-cornered board in its corner (the game's +X, +Z: here -x, +y), a candle on a turned
    candlestick in the corner and a jug of dried flowers on each side."""
    c = W / 2
    curve = bezier((c - 0.02, c - 0.02), (0.78, 0.12), (-0.12, -0.78), (-(c - 0.02), -(c - 0.02)), 10)
    outline = [(-c, c), (-c, -(c - 0.02))] + curve[::-1][1:-1] + [(c - 0.02, c)]
    plate("Police", outline, 0.0, 0.12, "woodwork", r=0.03, seg=2)
    plate("Lišta police", [(x * 0.97, y * 0.97) for x, y in outline], 0.12, 0.15, "woodwork", r=0.01, seg=1)
    # a crocheted doily under the candle and the jugs, its front edge scalloped
    edge = bezier((-1.0, -0.55), (-0.3, -0.5), (0.5, 0.3), (0.55, 1.0), 18)
    lace = [(x + 0.025 * (k % 2) * 0.707, y - 0.025 * (k % 2) * 0.707) for k, (x, y) in enumerate(edge)]
    plate("Dečka", [(-1.0, 1.0)] + lace[::-1], 0.15, 0.158, "candle", r=0)
    cx, cy = -0.62, 0.62
    lathe("Svícen", [(0.0, 0.15), (0.17, 0.15), (0.17, 0.19), (0.09, 0.23), (0.05, 0.32), (0.07, 0.41), (0.045, 0.46),
                     (0.11, 0.48), (0.11, 0.52), (0.0, 0.52)], (cx, cy, 0), "woodwork", seg=10)
    cyl("Svíčka", 0.065, 0.5, (cx, cy, 0.77), "candle", seg=10, edge=0.012)
    tube("Knot", (cx, cy, 1.02), (cx, cy, 1.07), 0.01, "woodwork", 4)
    bunch(-0.82, -0.12, 0.2, (0.0, -1.0))
    bunch(0.12, 0.82, 1.1, (1.0, 0.0))


# ───────────────────────────────────────────────────────────── koupelna
def tub(W, H, D):
    """A white roll-top tub on four feet, water in it, the tap on its end."""
    n = 5
    prof = [(3.2, 1.3, 0.95, 0.34), (3.3, 1.4, 1.0, 0.45), (3.42, 1.52, 1.08, 1.0), (3.5, 1.6, 1.15, 1.75), (3.52, 1.62, 1.17, 1.95),
            (3.56, 1.66, 1.2, 2.04), (3.55, 1.65, 1.19, 2.14), (3.51, 1.61, 1.16, 2.19), (3.46, 1.56, 1.12, 2.2),
            (3.41, 1.51, 1.08, 2.18), (3.38, 1.48, 1.06, 2.12), (3.36, 1.46, 1.04, 2.0), (3.24, 1.34, 0.95, 1.0),
            (3.08, 1.18, 0.85, 0.6), (2.9, 1.0, 0.72, 0.5)]
    loft("Vana", [rr(a, b, r, z, n) for a, b, r, z in prof], "porcelain")
    loft("Voda", [rr(3.335, 1.435, 1.03, 1.75, n)], "water", cap0=False)
    for sx in (-1, 1):
        for sy in (-1, 1):
            lathe("Nožka", [(0.0, 0), (0.2, 0), (0.25, 0.06), (0.21, 0.15), (0.14, 0.24), (0.17, 0.32), (0.25, 0.42), (0.0, 0.42)],
                  (sx * 2.45, sy * 0.78, 0), "chrome", seg=8)
    x = -3.47
    for s in (-1, 1):
        cyl("Sloupek baterie", 0.065, 0.32, (x, s * 0.3, 2.36), "chrome", seg=8)
        cyl("Kohoutek", 0.05, 0.08, (x, s * 0.3, 2.58), "chrome", seg=8)
        for turn in (0.3, 0.3 + math.pi / 2):
            box("Křížek", (0.26, 0.04, 0.04), (x, s * 0.3, 2.64), "chrome", r=0, rot=euler(rz=turn))
    tube("Baterie", (x, -0.32, 2.5), (x, 0.32, 2.5), 0.065, "chrome", 10)
    sweep("Výtok", [(x, 0, 2.5), (x + 0.14, 0, 2.62), (x + 0.34, 0, 2.64), (x + 0.52, 0, 2.56), (x + 0.6, 0, 2.42)], 0.05, "chrome")


def toilet(W, H, D):
    """A white toilet: its foot and bowl, the seat and the closed lid, the cistern against the wall."""
    cy = -0.08
    rings = [oval(0.42, 0.55, 0.0, cy=0.3), oval(0.44, 0.57, 0.05, cy=0.3), oval(0.38, 0.5, 0.15, cy=0.28), oval(0.36, 0.48, 0.6, cy=0.22),
             oval(0.42, 0.58, 0.95, cy=0.1), oval(0.58, 0.82, 1.18, cy=0.0), oval(0.68, 0.94, 1.42, cy=cy), oval(0.72, 0.98, 1.56, cy=cy),
             oval(0.71, 0.97, 1.62, cy=cy), oval(0.6, 0.84, 1.62, cy=cy), oval(0.56, 0.78, 1.55, cy=cy), oval(0.42, 0.58, 1.3, cy=cy - 0.05),
             oval(0.22, 0.3, 1.1, cy=cy - 0.1)]
    loft("Mísa", rings, "porcelain")
    loft("Prkénko a víko", [oval(0.7, 0.96, 1.62, cy=cy), oval(0.7, 0.96, 1.68, cy=cy), oval(0.68, 0.94, 1.69, cy=cy),
                            oval(0.67, 0.93, 1.74, cy=cy), oval(0.63, 0.88, 1.78, cy=cy)], "porcelain")
    box("Nádržka", (1.5, 0.56, 1.2), (0, 1.11, 1.8 + 0.6), "porcelain", r=0.08, seg=3)
    box("Víko nádržky", (1.58, 0.64, 0.1), (0, 1.07, 3.05), "porcelain", r=0.04, seg=2)
    cyl("Splachovadlo", 0.1, 0.05, (0, 1.07, 3.125), "porcelain", seg=12, edge=0.012)
    box("Hrdlo", (0.7, 0.4, 0.5), (0, 1.0, 1.55), "porcelain", r=0.08, seg=2)


def basin(W, H, D):
    """A pedestal basin with a mixer tap, a little shelf with a cup and a framed mirror over it (up to 6.9)."""
    lathe("Noha umyvadla", [(0.0, 0), (0.4, 0), (0.4, 0.06), (0.3, 0.16), (0.24, 0.55), (0.21, 1.4), (0.23, 2.0), (0.3, 2.35),
                            (0.34, 2.5), (0.0, 2.5)], (0, 0.15, 0), "porcelain", seg=14, scale=(1, 0.8))
    n = 4
    prof = [(1.0, 0.6, 0.45, 2.45, 0.05), (1.15, 0.75, 0.5, 2.62, 0.0), (1.25, 0.84, 0.55, 2.85, 0.0), (1.28, 0.87, 0.56, 3.0, 0.0),
            (1.27, 0.86, 0.55, 3.08, 0.0), (1.22, 0.81, 0.52, 3.1, 0.0), (1.1, 0.62, 0.45, 3.1, -0.1), (1.05, 0.57, 0.42, 3.04, -0.1),
            (0.85, 0.42, 0.35, 2.82, -0.1), (0.5, 0.25, 0.22, 2.68, -0.08)]
    loft("Umyvadlo", [rr(a, b, r, z, n, cy=c) for a, b, r, z, c in prof], "porcelain")
    cyl("Odtok", 0.07, 0.01, (0, -0.08, 2.685), "chrome", seg=10)
    ty = 0.66
    cyl("Patka baterie", 0.08, 0.05, (0, ty, 3.125), "chrome", seg=10)
    cyl("Baterie", 0.055, 0.28, (0, ty, 3.29), "chrome", seg=10, edge=0.01)
    sweep("Výtok", [(0, ty, 3.36), (0, ty - 0.14, 3.4), (0, ty - 0.28, 3.36), (0, ty - 0.33, 3.3)], 0.032, "chrome")
    box("Páčka", (0.05, 0.28, 0.04), (0, ty + 0.1, 3.47), "chrome", r=0.012, seg=1, rot=euler(rx=0.35))
    # the shelf under the mirror, a cup on it
    box("Polička", (1.5, 0.24, 0.05), (0, D / 2 - 0.12, 3.72), "porcelain", r=0.02, seg=1)
    for s in (-1, 1):
        box("Držák", (0.05, 0.16, 0.12), (s * 0.6, D / 2 - 0.08, 3.64), "chrome", r=0.01, seg=1)
    lathe("Kelímek", [(0.0, 3.745), (0.08, 3.745), (0.1, 4.0), (0.0, 4.0)], (0.42, D / 2 - 0.12, 0), "porcelain", seg=10)
    # the mirror in its frame
    prof = [(0.0, D / 2), (0.0, D / 2 - 0.06), (0.03, D / 2 - 0.085), (0.1, D / 2 - 0.095), (0.15, D / 2 - 0.075), (0.17, D / 2 - 0.045), (0.17, D / 2)]
    rect_frame("Rám zrcadla", 1.2, 1.5, prof, "porcelain", Matrix.Translation((0, 0, 5.4)))
    box("Zrcadlo", (2.1, 0.02, 2.7), (0, D / 2 - 0.035, 5.4), "mirror", r=0)


# ───────────────────────────────────────────────────────────── kachlová kamna (Kachelofen)
def kachelofen(W, H, D):
    """A chalet's tiled stove: a stone plinth, the lower tier of raised tiles under a ledge, the upper tier (a lighter
    glaze) under a moulded cornice, the iron fire door with the fire's glow through its slot, a warming door, a drying
    rail and the wooden bench along its front."""
    back = D / 2
    # the lower tier (y from -0.3 to the wall, x ±2.6, z 0.4 to 3.5)
    lf, lw, l0, l1 = -0.3, 2.6, 0.4, 3.5
    loft("Podstavec", [rect(lw + 0.12, lf - 0.12, back, 0.0), rect(lw + 0.12, lf - 0.12, back, 0.28), rect(lw + 0.06, lf - 0.06, back, 0.34),
                       rect(lw + 0.02, lf - 0.02, back, l0)], "grout", sharp=30)
    box("Jádro", (2 * lw, back - lf, l1 - l0), (0, (lf + back) / 2, (l0 + l1) / 2), "grout", r=0)
    door = {(2, 2), (2, 3)}
    tiles("Kachle", (-lw, lf, l0), (1, 0, 0), (0, 0, 1), 5, 4, 2 * lw, l1 - l0, "tile", skip=door)
    tiles("Kachle", (lw, lf, l0), (0, 1, 0), (0, 0, 1), 2, 4, back - lf, l1 - l0, "tile")
    tiles("Kachle", (-lw, back, l0), (0, -1, 0), (0, 0, 1), 2, 4, back - lf, l1 - l0, "tile")
    loft("Římsa spodní", [rect(lw + 0.02, lf - 0.02, back, l1), rect(lw + 0.1, lf - 0.1, back, l1 + 0.04), rect(lw + 0.16, lf - 0.16, back, l1 + 0.12),
                          rect(lw + 0.18, lf - 0.18, back, l1 + 0.2), rect(lw + 0.14, lf - 0.14, back, l1 + 0.25)], "tile", sharp=30)
    # the upper tier (y from 0.2, x ±2.0, z 3.75 to 6.0)
    uf, uw, u0, u1 = 0.2, 2.0, l1 + 0.25, 6.0
    box("Jádro", (2 * uw, back - uf, u1 - u0), (0, (uf + back) / 2, (u0 + u1) / 2), "grout", r=0)
    tiles("Kachle", (-uw, uf, u0), (1, 0, 0), (0, 0, 1), 5, 3, 2 * uw, u1 - u0, "tile2", skip={(2, 1)})
    tiles("Kachle", (uw, uf, u0), (0, 1, 0), (0, 0, 1), 2, 3, back - uf, u1 - u0, "tile2")
    tiles("Kachle", (-uw, back, u0), (0, -1, 0), (0, 0, 1), 2, 3, back - uf, u1 - u0, "tile2")
    prof = [(6.0, 0.02), (6.04, 0.06), (6.1, 0.08), (6.18, 0.14), (6.27, 0.24), (6.36, 0.34), (6.44, 0.4), (6.5, 0.42), (6.56, 0.42), (6.6, 0.38)]
    loft("Římsa", [rect(uw + o, uf - o, back, z) for z, o in prof], "tile", sharp=30)
    # the iron fire door (in the lower tier's middle column, its top two rows), the glow through its slot
    dz0, dz1 = l0 + 2 * (l1 - l0) / 4, l1
    face = lf - 0.05
    chamfer("Rám dvířek", (0.98, 0.07, dz1 - dz0 - 0.08), (0, face + 0.02, (dz0 + dz1) / 2), "iron", c=0.025)
    chamfer("Dvířka topeniště", (0.78, 0.06, 1.06), (0, face - 0.045, dz0 + 0.24 + 0.53), "iron", c=0.035)
    cyl("Růžice", 0.15, 0.04, (0, face - 0.09, dz0 + 0.86), "iron", axis="Y", seg=12, edge=0.012)
    for z in (dz0 + 0.42, dz0 + 1.12):
        cyl("Pant", 0.035, 0.16, (-0.41, face - 0.05, z), "iron", seg=8)
    box("Západka", (0.26, 0.05, 0.06), (0.25, face - 0.1, dz0 + 0.62), "iron", r=0.015, seg=1, rot=euler(ry=0.25))
    ball("Knoflík západky", 0.045, (0.37, face - 0.115, dz0 + 0.65), "iron", seg=8)
    sz = dz0 + 0.13
    rect_frame("Průduch", 0.34, 0.075, [(0.0, face - 0.02), (0.0, face - 0.045), (0.05, face - 0.045), (0.05, face - 0.02)], "iron",
               Matrix.Translation((0, 0, sz)))
    box("Žár", (0.6, 0.012, 0.1), (0, face - 0.025, sz), "glow", r=0)
    for x in (-0.15, 0.0, 0.15):
        box("Mřížka průduchu", (0.025, 0.02, 0.1), (x, face - 0.035, sz), "iron", r=0)
    # the warming door in the upper tier
    chamfer("Dvířka pícky", (0.66, 0.04, 0.6), (0, uf - 0.07, u0 + 0.75 + 0.375), "iron", c=0.02)
    ball("Knoflík pícky", 0.04, (0.22, uf - 0.11, u0 + 1.125), "iron", seg=8)
    # the drying rail along its front
    rz = 4.35
    tube("Tyč na sušení", (-2.5, -0.72, rz), (2.5, -0.72, rz), 0.055, "pine", 8)
    for x in (-1.75, 1.75):
        tube("Držák tyče", (x, uf - 0.04, rz), (x, -0.72, rz), 0.022, "iron", 6)
    # the bench along its front (y -1.6 to -0.52): planks on three shaped supports, an apron and a stretcher
    for y0, y1, r in ((-1.6, -1.25, 0.05), (-1.23, -0.88, 0.0), (-0.86, -0.52, 0.0)):
        if r:
            box("Prkno lavice", (W, y1 - y0, 0.12), (0, (y0 + y1) / 2, 1.44), "pine", r=r, seg=2)
        else:
            chamfer("Prkno lavice", (W, y1 - y0, 0.12), (0, (y0 + y1) / 2, 1.44), "pine", c=0.015)
    arch = [(-1.05 + 0.23 * math.cos(a), 0.36 * math.sin(a)) for a in (math.pi * k / 6 for k in range(7))]
    support = [(-1.52, 0.0)] + arch + [(-0.58, 0.0), (-0.58, 1.38), (-1.52, 1.38)]
    for x in (-2.82, 0.0, 2.82):
        prism("Podnož", support, -0.06, 0.06, "pine", r=0.015, seg=1, at=(x, 0, 0), rot=SIDE_VIEW)
    box("Lub", (W - 0.2, 0.07, 0.2), (0, -1.5, 1.28), "pine", r=0.01, seg=1)
    box("Příčka", (W - 0.3, 0.1, 0.12), (0, -1.05, 0.55), "pine", r=0.01, seg=1)


# ───────────────────────────────────────────────────────────── garáž
def workbench(W, H, D):
    """A garage workbench: a thick planked top on four legs, a low shelf with a toolbox and paint, a pegboard with
    tools over it (up to 5.5) and a vise on its front edge."""
    for k in range(4):
        chamfer("Deska ponku", (W, 0.598, 0.3), (0, -0.9 + k * 0.6, 3.05), "wood", c=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            chamfer("Noha", (0.3, 0.3, 2.9), (sx * 2.9, sy * 0.9, 1.45), "wood", c=0.025)
    for sy in (-1, 1):
        box("Lub", (5.5, 0.12, 0.28), (0, sy * 0.9, 2.76), "wood", r=0)
        box("Příčka", (5.5, 0.1, 0.14), (0, sy * 0.9, 0.62), "wood", r=0)
    for sx in (-1, 1):
        box("Lub", (0.12, 1.5, 0.28), (sx * 2.9, 0, 2.76), "wood", r=0)
        box("Příčka", (0.1, 1.5, 0.14), (sx * 2.9, 0, 0.62), "wood", r=0)
    for k in range(3):
        box("Polička", (5.6, 0.58, 0.08), (0, -0.6 + k * 0.6, 0.73), "wood", r=0)
    # on the shelf: a toolbox and two cans of paint
    chamfer("Kufřík", (1.3, 0.62, 0.52), (-1.6, -0.15, 0.77 + 0.26), "vise", c=0.03)
    box("Víko kufříku", (1.34, 0.66, 0.06), (-1.6, -0.15, 1.31), "vise", r=0.015, seg=1)
    sweep("Držadlo", [(-1.95, -0.15, 1.34), (-1.9, -0.15, 1.48), (-1.6, -0.15, 1.52), (-1.3, -0.15, 1.48), (-1.25, -0.15, 1.34)], 0.03, "steel", 6)
    for x, r, h in ((1.1, 0.26, 0.55), (1.75, 0.2, 0.42)):
        cyl("Plechovka", r, h, (x, 0.1, 0.77 + h / 2), "steel", seg=10)
    # the pegboard on the wall over the top, its frame, its holes and the tools on it
    pb, z0, z1 = D / 2, 3.2, REACH["workbench"]
    box("Děrovaná deska", (6.0, 0.08, z1 - z0), (0, pb - 0.04, (z0 + z1) / 2), "board", r=0)
    for x in (-3.04, 3.04):
        box("Rám desky", (0.1, 0.07, z1 - z0), (x, pb - 0.045, (z0 + z1) / 2), "wood", r=0)
    for z in (z0 + 0.05, z1 - 0.05):
        box("Rám desky", (6.18, 0.07, 0.1), (0, pb - 0.045, z), "wood", r=0)
    f = pb - 0.08
    holes = [(x - 0.035, z - 0.035, x + 0.035, z + 0.035) for x in (-2.7 + 0.36 * i for i in range(16)) for z in (z0 + 0.36 + 0.4 * j for j in range(5))]
    quads("Dírky", holes, f - 0.003, "vise")
    tf = f - 0.06
    # a hammer
    cyl("Násada kladiva", 0.045, 0.95, (-2.3, tf, 4.1), "wood", seg=8)
    box("Kladivo", (0.5, 0.12, 0.14), (-2.3, tf, 4.62), "steel", r=0)
    # a saw
    prism("Pila", [(-1.95, 4.8), (-0.7, 4.8), (-0.7, 4.38), (-1.95, 4.62)], tf - 0.01, tf + 0.01, "steel", r=0)
    prism("Rukojeť pily", [(-0.72, 4.3), (-0.42, 4.3), (-0.28, 4.48), (-0.28, 4.74), (-0.4, 4.9), (-0.72, 4.88)], tf - 0.05, tf + 0.05, "wood", r=0.02, seg=1)
    # wrenches
    for k, (x, ln) in enumerate(((0.05, 0.78), (0.3, 0.66), (0.52, 0.56))):
        top = 5.1
        box("Klíč", (0.07, 0.025, ln), (x, tf, top - ln / 2), "steel", r=0)
        cyl("Očko klíče", 0.07, 0.03, (x, tf, top - ln), "steel", axis="Y", seg=6)
        box("Čelist klíče", (0.16, 0.03, 0.1), (x, tf, top + 0.02), "steel", r=0)
    # screwdrivers
    for x in (1.0, 1.25, 1.5):
        cyl("Rukojeť šroubováku", 0.06, 0.36, (x, tf, 4.85), "wood", seg=7)
        cyl("Šroubovák", 0.018, 0.5, (x, tf, 4.42), "steel", seg=4)
    # pliers
    for turn in (0.18, -0.18):
        box("Kleště", (0.06, 0.03, 0.7), (2.05, tf, 4.5), "steel", r=0, rot=euler(ry=turn))
    # pegs (hooks) for the tools
    for x, z in ((-2.3, 4.45), (-1.6, 4.85), (-0.9, 4.85), (0.05, 5.15), (0.3, 5.15), (0.52, 5.15), (1.0, 5.07), (1.25, 5.07), (1.5, 5.07), (2.05, 4.9)):
        tube("Háček", (x, f, z), (x, tf - 0.06, z + 0.04), 0.014, "steel", 3)
    # the vise on the front edge (its jaws over the top, its handle inside the box)
    vx = 2.45
    chamfer("Svěrák", (0.6, 0.62, 0.1), (vx, -0.84, 3.25), "vise", c=0.02)
    chamfer("Čelist", (0.62, 0.3, 0.42), (vx, -0.62, 3.51), "vise", c=0.04)
    chamfer("Čelist", (0.62, 0.22, 0.38), (vx, -1.02, 3.49), "vise", c=0.04)
    box("Vedení", (0.24, 0.2, 0.14), (vx, -0.82, 3.37), "vise", r=0.01, seg=1)
    for y in (-0.785, -0.896):
        box("Lícnice", (0.62, 0.025, 0.12), (vx, y, 3.64), "steel", r=0)
    tube("Vřeteno", (vx, -1.17, 3.45), (vx, -0.92, 3.45), 0.035, "steel", 8)
    tube("Páka", (vx - 0.26, -1.165, 3.45), (vx + 0.26, -1.165, 3.45), 0.022, "steel", 6)
    for s in (-1, 1):
        ball("Kulička", 0.033, (vx + s * 0.27, -1.165, 3.45), "steel", seg=8)


def shelves(W, H, D):
    """Metal shelving: four angle-iron posts, four shelves with folded edges, cross braces, three bins (two blue crates and
    a cardboard box), more boxes and paint cans."""
    hw, hd, a, t = W / 2, D / 2, 0.18, 0.03
    for sx in (-1, 1):
        for sy in (-1, 1):
            L = [(0, 0), (a, 0), (a, t), (t, t), (t, a), (0, a)]
            pts = [(sx * (hw - x), sy * (hd - y)) for x, y in L]
            if sx * sy < 0:
                pts.reverse()
            plate("Stojna", pts, 0.0, H, "metal", r=0)
            box("Patka", (0.24, 0.24, 0.03), (sx * (hw - 0.12), sy * (hd - 0.12), 0.015), "metal", r=0)
    levels = [0.4, 2.3, 4.2, 6.1]
    for z in levels:
        loft("Police", [rect(hw - 0.03, -hd + 0.03, hd - 0.03, z + 0.045), rect(hw - 0.03, -hd + 0.03, hd - 0.03, z - 0.075),
                        rect(hw - 0.005, -hd + 0.005, hd - 0.005, z - 0.075), rect(hw - 0.005, -hd + 0.005, hd - 0.005, z + 0.075)], "metal", sharp=30)
    for z0, z1 in ((levels[0], levels[1]), (levels[2], levels[3])):
        ln = math.hypot(2 * hw - 0.2, z1 - z0)
        ang = math.atan2(z1 - z0, 2 * hw - 0.2)
        for s in (-1, 1):
            box("Vzpěra", (ln, 0.012, 0.06), (0, hd - 0.02, (z0 + z1) / 2), "metal", r=0, rot=euler(ry=s * ang))
    for sx in (-1, 1):
        for z0, z1 in ((levels[0], levels[1]), (levels[2], levels[3])):
            ln = math.hypot(2 * hd - 0.2, z1 - z0)
            ang = math.atan2(z1 - z0, 2 * hd - 0.2)
            for s in (-1, 1):
                box("Vzpěra", (0.012, ln, 0.06), (sx * (hw - 0.02), 0, (z0 + z1) / 2), "metal", r=0, rot=euler(rx=s * ang))

    def crate(x, z):
        n = 2
        loft("Přepravka", [rr(0.72, 0.58, 0.1, z, n, cx=x), rr(0.8, 0.64, 0.12, z + 1.12, n, cx=x), rr(0.83, 0.67, 0.13, z + 1.14, n, cx=x),
                           rr(0.83, 0.67, 0.13, z + 1.2, n, cx=x), rr(0.76, 0.6, 0.1, z + 1.2, n, cx=x), rr(0.7, 0.54, 0.08, z + 0.1, n, cx=x)], "crate")
        for s in (-1, 1):
            box("Úchyt", (0.4, 0.02, 0.12), (x, s * 0.665, z + 0.98), "crate", r=0)

    def carton(x, z, w, d, h, turn=0.0):
        box("Krabice", (w, d, h), (x, 0, z + h / 2), "card", r=0.02, seg=1, rot=euler(rz=turn))
        for s in (-1, 1):
            box("Klopa", (w - 0.04, d / 2 - 0.02, 0.02), (x, s * d / 4, z + h + 0.008), "card", r=0, rot=euler(rz=turn))
    top = [z + 0.075 for z in levels]
    crate(1.0, top[0])
    carton(-1.25, top[0], 1.0, 1.0, 0.8, 0.05)
    carton(0.1, top[1], 1.6, 1.3, 1.15)
    cyl("Plechovka", 0.24, 0.5, (-1.6, -0.1, top[1] + 0.25), "metal", seg=12)
    crate(-0.8, top[2])
    carton(1.3, top[2], 1.1, 1.1, 0.7, -0.06)
    for x, r in ((1.5, 0.25), (0.85, 0.22), (-1.4, 0.25)):
        cyl("Plechovka", r, 0.45, (x, 0.0, top[3] + 0.225), "metal", seg=12)
    carton(-0.35, top[3], 0.9, 1.0, 0.55, 0.08)


def garage_door(W, H, D):
    """A metal sectional door, closed: four sections with raised cassettes, a rubber seal, a handle and a lock."""
    seal = 0.08
    sh = (H - seal) / 4
    f = -0.1
    box("Těsnění", (W, 0.22, seal), (0, 0.0, seal / 2), "rubber", r=0.01, seg=1)
    for i in range(4):
        z0 = seal + i * sh
        chamfer("Segment", (W - 0.04, 0.24, sh - 0.025), (0, 0.02, z0 + sh / 2), "door", c=0.04)
        tiles("Kazety", (-(W - 0.04) / 2, f, z0), (1, 0, 0), (0, 0, 1), 6, 1, W - 0.04, sh - 0.025, "door", gap=0.36, relief=0.035,
              edge=0.07, dish=0.015)
    tube("Madlo", (0, f - 0.025, 0.85), (0, f - 0.025, 1.4), 0.024, "rubber", 8)
    for z in (0.88, 1.37):
        tube("Držák madla", (0, f, z), (0, f - 0.03, z), 0.02, "rubber", 6)
    cyl("Zámek", 0.06, 0.03, (0, f - 0.015, 1.62), "rubber", axis="Y", seg=10)


BUILD = {
    "counter": counter, "stove": stove, "sink": sink, "cabinets": cabinets, "hood": hood, "corner_bench": corner_bench,
    "bench": bench, "corner_shelf": corner_shelf, "tub": tub, "toilet": toilet, "basin": basin, "kachelofen": kachelofen,
    "workbench": workbench, "shelves": shelves, "garage_door": garage_door,
}


# ───────────────────────────────────────────────────────────── scéna
def clear_previous():
    for name in ("Zařízení", "Náhled"):
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
    for pool in (bpy.data.meshes, bpy.data.lights, bpy.data.cameras, bpy.data.materials):
        for block in list(pool):
            if block.users == 0:
                pool.remove(block)


def slots():
    """Each kind's origin in the row (x along the row, the boxes GAP apart)."""
    out, x = {}, 0.0
    for kind, _, w, h, d, _ in KINDS:
        out[kind] = Vector((x + w / 2, 0, 0))
        x += w + GAP
    return out


def build_all():
    global CUR, COL
    clear_previous()
    materials()
    root = bpy.data.collections.new("Zařízení")
    bpy.context.scene.collection.children.link(root)
    at = slots()
    for kind, name, w, h, d, up in KINDS:
        COL = bpy.data.collections.new("Z_" + kind)
        root.children.link(COL)
        CUR = at[kind]
        BUILD[kind](w, h, d)
        COL["size"] = (w, h, d)
        COL["origin"] = tuple(CUR)
        COL["height"] = up
    return at


def frame_points(kind):
    """Every vertex of the kind (modifiers applied) in its frame, Blender axes."""
    dg = bpy.context.evaluated_depsgraph_get()
    col = bpy.data.collections["Z_" + kind]
    origin = Vector(col["origin"])
    for o in col.objects:
        ev = o.evaluated_get(dg)
        for v in ev.data.vertices:
            yield o, o.matrix_world @ v.co - origin


def check_bounds():
    """How each kind fits its box: what sticks out in front, behind, at the sides, under or over (its REACH allowed)."""
    report = []
    for kind, _, w, h, d, _ in KINDS:
        lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
        for _, p in frame_points(kind):
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
        out = {"front": -d / 2 - lo.y, "back": hi.y - d / 2, "side": max(-w / 2 - lo.x, hi.x - w / 2), "under": -lo.z,
               "over": hi.z - REACH.get(kind, h)}
        report.append((kind, {k: round(v, 3) for k, v in out.items() if v > 1e-4}, round(hi.z, 3)))
    return report


# Preview rooms (the house's own layout, shared/HouseLayout.luau): a room's inner rect in the game's axes (x0, x1, z0, z1),
# its walls, windows (side, along, sill, width, height), its fixtures (kind, x, y, z, turn: the game's frame) and camera.
ROOMS = {
    "Kuchyně": {"base": (0, 40), "rect": (0, 16, 0, 20), "walls": "WSN", "floor": "planks", "wainscot": 3.6,
                "windows": [("S", 7.1, 4, 5, 4), ("N", 9.0, 4, 5, 4)],
                "fixtures": [("counter", 1.3, 0, 2.25, 270), ("stove", 1.3, 0, 6, 270), ("counter", 1.3, 0, 9.75, 270),
                             ("cabinets", 0.7, 6.4, 2.25, 270), ("hood", 0.9, 7.0, 6, 270), ("cabinets", 0.7, 6.4, 9.75, 270),
                             ("sink", 7.1, 0, 1.3, 180), ("corner_bench", 0.8, 0, 16.5, 270), ("bench", 2.8, 0, 19.2, 0),
                             ("corner_shelf", 1.1, 4.9, 18.9, 270)],
                "camera": ((15.6, 8.0, 12.5), (3.0, 3.0, 8.0), 15)},
    "Koupelna": {"base": (34, 40), "rect": (0, 12, 0, 10), "walls": "WNES", "unseen": "S", "floor": "bathtile", "wall": "bathplaster", "wainscot": 4.5,
                 "dado": "bathwall", "trim": False,
                 "windows": [("N", 3.6, 5.25, 3, 2.5)],
                 "fixtures": [("tub", 3.6, 0, 8.3, 0), ("toilet", 10.6, 0, 5.4, 90), ("basin", 0.9, 0, 4.0, 270)],
                 "camera": ((6.4, 7.4, -3.4), (5.6, 2.6, 6.2), 19)},
    "Obývák": {"base": (66, 40), "rect": (0, 14, 0, 14), "walls": "WNS", "floor": "planks", "wainscot": 3.6,
               "windows": [("N", 8.0, 4, 5, 4)],
               "fixtures": [("kachelofen", 1.6, 0, 7, 270)],
               "camera": ((10.6, 6.0, 1.8), (1.6, 3.4, 7.6), 24)},
    "Garáž": {"base": (104, 40), "rect": (0, 16, 0, 20), "walls": "WNSE", "floor": "concrete", "wall": "garagewall", "wainscot": 0,
              "windows": [],
              "fixtures": [("garage_door", 0.15, 0, 10, 270), ("workbench", 3.4, 0, 18.8, 0), ("shelves", 13.2, 0, 19.2, 0)],
              "camera": ((13.0, 7.6, 3.2), (5.4, 3.0, 15.0), 18)},
}


def game_to_blender(base, gx, gy, gz):
    return Vector((base[0] - gx, base[1] + gz, gy))


def room_materials():
    def nodes(name, colour, rough=0.8):
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.diffuse_color = (*linear(colour), 1)
        try:
            mat.use_nodes = True
        except Exception:
            pass
        nt = mat.node_tree
        for n in [n for n in nt.nodes if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL")]:
            nt.nodes.remove(n)
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        b.inputs["Base Color"].default_value = mat.diffuse_color
        b.inputs["Roughness"].default_value = rough
        return mat, nt, b

    def socket(sockets, name, kind):
        return next(x for x in sockets if x.name == name and x.type == kind)

    def bricks(name, c1, c2, mortar, width, height, gapsize, offset, rough, wall=False):
        mat, nt, b = nodes(name, c1, rough)
        coords = nt.nodes.new("ShaderNodeTexCoord")
        brick = nt.nodes.new("ShaderNodeTexBrick")
        brick.offset, brick.offset_frequency = offset, 2
        for key, value in (("Scale", 1.0), ("Mortar Size", gapsize), ("Mortar Smooth", 0.1), ("Bias", 0.0), ("Brick Width", width), ("Row Height", height)):
            brick.inputs[key].default_value = value
        brick.inputs["Color1"].default_value = (*linear(c1), 1)
        brick.inputs["Color2"].default_value = (*linear(c2), 1)
        brick.inputs["Mortar"].default_value = (*linear(mortar), 1)
        if wall:
            xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
            along = nt.nodes.new("ShaderNodeMath")
            uv = nt.nodes.new("ShaderNodeCombineXYZ")
            nt.links.new(coords.outputs["Object"], xyz.inputs["Vector"])
            nt.links.new(xyz.outputs["X"], along.inputs[0])
            nt.links.new(xyz.outputs["Y"], along.inputs[1])
            nt.links.new(along.outputs[0], uv.inputs["X"])
            nt.links.new(xyz.outputs["Z"], uv.inputs["Y"])
            nt.links.new(uv.outputs["Vector"], brick.inputs["Vector"])
        else:
            nt.links.new(coords.outputs["Object"], brick.inputs["Vector"])
        nt.links.new(brick.outputs["Color"], b.inputs["Base Color"])
        return mat, nt, b, coords, brick
    out = {}
    mat, nt, b, coords, brick = bricks("Room planks", "#9C6A42", "#B07A4C", "#4A3020", 4.5, 0.8, 0.015, 0.5, 0.45)
    grain = nt.nodes.new("ShaderNodeTexWave")
    grain.bands_direction = "Y"
    for key, value in (("Scale", 3.0), ("Distortion", 5.0), ("Detail", 3.0)):
        grain.inputs[key].default_value = value
    nt.links.new(coords.outputs["Object"], grain.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.8, 0.8, 0.8, 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
    socket(mix.inputs, "Factor", "VALUE").default_value = 0.5
    nt.links.new(grain.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(brick.outputs["Color"], socket(mix.inputs, "A", "RGBA"))
    nt.links.new(ramp.outputs["Color"], socket(mix.inputs, "B", "RGBA"))
    nt.links.new(socket(mix.outputs, "Result", "RGBA"), b.inputs["Base Color"])
    out["planks"] = mat
    out["bathtile"] = bricks("Room bath floor", "#D6E6EC", "#CCDDE4", "#9AA8AE", 1.0, 1.0, 0.03, 0.0, 0.2)[0]
    out["bathwall"] = bricks("Room bath wall", "#CFE0DC", "#C6D9D5", "#F2F2EE", 0.8, 0.8, 0.03, 0.0, 0.2, wall=True)[0]
    mat, nt, b = nodes("Room concrete", "#8A8A86", 0.9)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.6
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*linear("#7C7C78"), 1)
    ramp.color_ramp.elements[1].color = (*linear("#9A9A94"), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    out["concrete"] = mat
    for key, colour, rough in (("plaster", "#E2D8C6", 0.9), ("bathplaster", "#D4DEE0", 0.9), ("garagewall", "#A4A49E", 0.9), ("wainscot", "#B07A4A", 0.6),
                               ("trim", "#845836", 0.5), ("ceiling", "#CDAE84", 0.8), ("beam", "#6C482C", 0.7)):
        out[key] = nodes("Room " + key, colour, rough)[0]
    mat, nt, b = nodes("Room sky", "#9CC8F0", 0.5)
    b.inputs["Emission Color"].default_value = mat.diffuse_color
    b.inputs["Emission Strength"].default_value = 1.6
    out["sky"] = mat
    return out


def room_scene(name, spec, mats):
    col = bpy.data.collections.new(name)
    bpy.data.collections["Náhled"].children.link(col)
    base = spec["base"]
    x0, x1, z0, z1 = spec["rect"]

    def slab(label, g0, g1, mat):
        """A box between two game corners (x, y, z)."""
        a, b = game_to_blender(base, *g0), game_to_blender(base, *g1)
        lo, hi = Vector(map(min, a, b)), Vector(map(max, a, b))
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=hi - lo, verts=bm.verts)
        me = bpy.data.meshes.new(label)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        o = bpy.data.objects.new(label, me)
        col.objects.link(o)
        o.location = (lo + hi) / 2
        return o
    wt, Hc = 0.5, 12.0
    slab("Podlaha", (x0 - wt, -0.2, z0 - wt), (x1 + wt, 0, z1 + wt), mats[spec["floor"]])
    slab("Strop", (x0 - wt, Hc, z0 - wt), (x1 + wt, Hc + 0.3, z1 + wt), mats["ceiling"])
    wall = mats[spec.get("wall", "plaster")]
    sides = {"W": ((x0 - wt, 0, z0 - wt), (x0, Hc, z1 + wt)), "E": ((x1, 0, z0 - wt), (x1 + wt, Hc, z1 + wt)),
             "S": ((x0 - wt, 0, z0 - wt), (x1 + wt, Hc, z0)), "N": ((x0 - wt, 0, z1), (x1 + wt, Hc, z1 + wt))}
    for s in spec["walls"]:
        w = slab("Zeď", *sides[s], wall)
        if s in spec.get("unseen", ""):  # (the wall behind the camera: only the mirror sees it)
            w.visible_camera = False
            continue
        if spec["wainscot"]:
            inner = {"W": (x0, x0 + 0.08), "E": (x1 - 0.08, x1), "S": (z0, z0 + 0.08), "N": (z1 - 0.08, z1)}[s]
            dado = mats[spec.get("dado", "wainscot")]
            if s in "WE":
                slab("Obložení", (inner[0], 0, z0), (inner[1], spec["wainscot"], z1), dado)
                if spec.get("trim", True):
                    slab("Lišta", (inner[0] - (0.04 if s == "E" else 0), spec["wainscot"], z0), (inner[1] + (0.04 if s == "W" else 0), spec["wainscot"] + 0.12, z1), mats["trim"])
            else:
                slab("Obložení", (x0, 0, inner[0]), (x1, spec["wainscot"], inner[1]), dado)
                if spec.get("trim", True):
                    slab("Lišta", (x0, spec["wainscot"], inner[0] - (0.04 if s == "N" else 0)), (x1, spec["wainscot"] + 0.12, inner[1] + (0.04 if s == "S" else 0)), mats["trim"])
    if spec["floor"] == "planks":  # (a chalet's ceiling beams)
        for k in range(1, 4):
            z = z0 + (z1 - z0) * k / 4
            slab("Trám", (x0, Hc - 0.6, z - 0.3), (x1, Hc, z + 0.3), mats["beam"])
    for side, t, sill, w, h in spec["windows"]:
        if side in "NS":
            zz = z1 - 0.02 if side == "N" else z0 + 0.02
            d = -1 if side == "N" else 1
            slab("Okno", (t - w / 2, sill, zz - 0.01), (t + w / 2, sill + h, zz + 0.01), mats["sky"])
            for a, b in (((t - w / 2 - 0.25, sill - 0.25), (t + w / 2 + 0.25, sill)), ((t - w / 2 - 0.25, sill + h), (t + w / 2 + 0.25, sill + h + 0.25)),
                         ((t - w / 2 - 0.25, sill), (t - w / 2, sill + h)), ((t + w / 2, sill), (t + w / 2 + 0.25, sill + h)),
                         ((t - 0.06, sill), (t + 0.06, sill + h)), ((t - w / 2, sill + h * 0.62 - 0.06), (t + w / 2, sill + h * 0.62 + 0.06))):
                slab("Rám okna", (a[0], a[1], zz), (b[0], b[1], zz + d * 0.18), mats["trim"])
            slab("Parapet", (t - w / 2 - 0.35, sill - 0.3, zz), (t + w / 2 + 0.35, sill - 0.12, zz + d * 0.45), mats["trim"])
            lamp = bpy.data.objects.new("Světlo z okna", bpy.data.lights.new("Světlo z okna", "AREA"))
            col.objects.link(lamp)
            lamp.data.energy, lamp.data.size, lamp.data.color = 300, w, (1.0, 0.96, 0.9)
            lamp.location = game_to_blender(base, t, sill + h / 2, zz + d * 0.6)
            lamp.rotation_euler = (math.radians(90), 0, 0 if side == "N" else math.radians(180))
            try:
                lamp.visible_camera = False
            except AttributeError:
                pass
    for kind, gx, gy, gz, turn in spec["fixtures"]:
        src = bpy.data.collections["Z_" + kind]
        origin = Vector(src["origin"])
        move = Matrix.Translation(game_to_blender(base, gx, gy, gz)) @ Matrix.Rotation(math.radians(turn), 4, "Z") @ Matrix.Translation(-origin)
        for o in src.objects:
            c = o.copy()
            col.objects.link(c)
            c.matrix_world = move @ o.matrix_world
    sun = bpy.data.objects.new("Stropní světlo", bpy.data.lights.new("Stropní světlo", "AREA"))
    col.objects.link(sun)
    sun.data.shape, sun.data.size, sun.data.size_y = "RECTANGLE", (x1 - x0) * 0.6, (z1 - z0) * 0.6
    sun.data.energy = 9 * (x1 - x0) * (z1 - z0)
    sun.data.color = (1.0, 0.9, 0.78)
    sun.location = game_to_blender(base, (x0 + x1) / 2, Hc - 0.7, (z0 + z1) / 2)
    eye, target, lens = spec["camera"]
    fill = bpy.data.objects.new("Doplňkové světlo", bpy.data.lights.new("Doplňkové světlo", "POINT"))
    col.objects.link(fill)
    fill.data.energy, fill.data.color, fill.data.shadow_soft_size = 300, (1.0, 0.95, 0.9), 2.0
    fill.location = game_to_blender(base, *eye) + Vector((0, 0, 1.5))
    cam = bpy.data.objects.new("Kamera " + name, bpy.data.cameras.new("Kamera " + name))
    col.objects.link(cam)
    a, b = game_to_blender(base, *eye), game_to_blender(base, *target)
    cam.location = a
    cam.rotation_euler = (b - a).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    col["camera"] = cam.name
    return col


def studio(at):
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    world = scene.world or bpy.data.worlds.new("Fixtures world")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*linear("#A9B2BC"), 1)
    bg.inputs["Strength"].default_value = 0.5
    root = bpy.data.collections["Zařízení"]
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1)
    me = bpy.data.meshes.new("Podlaha katalogu")
    bm.to_mesh(me)
    bm.free()
    floor = bpy.data.materials.get("Catalogue floor") or bpy.data.materials.new("Catalogue floor")
    floor.diffuse_color = (*linear("#3A3F45"), 1)
    me.materials.append(floor)
    o = bpy.data.objects.new("Podlaha katalogu", me)
    root.objects.link(o)
    end = max(v.x for v in at.values()) + 8
    o.location = (end / 2 - 2, 0, -0.001)
    o.scale = (end / 2 + 6, 12, 1)
    sun = bpy.data.objects.new("Slunce", bpy.data.lights.new("Slunce", "SUN"))
    root.objects.link(sun)
    sun.data.energy, sun.data.angle = 3.0, math.radians(8)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    cam = bpy.data.objects.new("Kamera", bpy.data.cameras.new("Kamera"))
    root.objects.link(cam)
    scene.camera = cam
    target = Vector((end / 2 - 4, 0, 2.5))
    cam.location = target + Vector((-0.25, -1.0, 0.45)).normalized() * end * 0.62
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 35
    scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    return cam


def build_scenes():
    root = bpy.data.collections.new("Náhled")
    bpy.context.scene.collection.children.link(root)
    mats = room_materials()
    for name, spec in ROOMS.items():
        room_scene(name, spec, mats)


def render_all(folder, samples=96, only=None):
    """`only`: these kinds one by one (item-<kind>.png); else the four rooms and the preview made of them."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples, scene.cycles.use_denoising = samples, True
    os.makedirs(folder, exist_ok=True)
    cats = bpy.data.collections["Zařízení"]
    rooms = bpy.data.collections["Náhled"]
    cam = bpy.data.objects["Kamera"]
    if only:
        rooms.hide_render = True
        key = bpy.data.objects.get("Klíčové světlo") or bpy.data.objects.new("Klíčové světlo", bpy.data.lights.new("Klíčové světlo", "AREA"))
        if key.name not in cats.objects:
            cats.objects.link(key)
        key.visible_camera = False
        scene.render.resolution_x, scene.render.resolution_y = 640, 640
        for kind, _, w, h, d, _ in KINDS:
            if kind not in only:
                continue
            for c in cats.children:
                c.hide_render = c.name != "Z_" + kind
            top = h + max(0.0, REACH.get(kind, h) - h)
            size = max(w, top, d)
            target = Vector(cats.children["Z_" + kind]["origin"]) + Vector((0, 0, top / 2))
            cam.location = target + Vector((-0.6, -1.3, 0.55)).normalized() * 40
            cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
            cam.data.type, cam.data.ortho_scale = "ORTHO", size * 1.35
            key.location = target + Vector((-1.2, -1.4, 1.5)).normalized() * size * 2.2
            key.rotation_euler = (target - key.location).to_track_quat("-Z", "Y").to_euler()
            key.data.size, key.data.energy = size * 1.3, 30 * size * size
            scene.camera = cam
            scene.render.filepath = os.path.join(folder, f"item-{kind}.png")
            bpy.ops.render.render(write_still=True)
        for c in cats.children:
            c.hide_render = False
        rooms.hide_render = False
        cam.data.type = "PERSP"
        return
    cats.hide_render = True
    scene.render.resolution_x, scene.render.resolution_y = 1200, 800
    shots = []
    for name in ROOMS:
        for c in rooms.children:
            c.hide_render = c.name != name
        scene.camera = bpy.data.objects[rooms.children[name]["camera"]]
        path = os.path.join(folder, f"room-{len(shots) + 1}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        shots.append(path)
    for c in rooms.children:
        c.hide_render = False
    cats.hide_render = False
    scene.camera = cam
    compose(shots, os.path.join(folder, "fixtures-preview.png"))


def compose(paths, out, gutter=8):
    """The four rooms on one sheet, two by two."""
    import numpy as np
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p, check_existing=False)
        w, h = im.size
        a = np.empty(w * h * 4, dtype=np.float32)
        im.pixels.foreach_get(a)
        imgs.append(a.reshape(h, w, 4))
        bpy.data.images.remove(im)
    h, w = imgs[0].shape[:2]
    W, H = 2 * w + 3 * gutter, 2 * h + 3 * gutter
    sheet = np.ones((H, W, 4), dtype=np.float32)
    sheet[..., :3] = 0.12
    for i, a in enumerate(imgs):
        col, row = i % 2, 1 - i // 2   # (pixels go bottom up: the first row on top)
        y, x = gutter + row * (h + gutter), gutter + col * (w + gutter)
        sheet[y:y + h, x:x + w] = a
    img = bpy.data.images.new("fixtures-preview", W, H, alpha=False)
    img.pixels.foreach_set(sheet.ravel())
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


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


def game(v, origin):
    """Blender → the game's axes in a kind's frame (x right = here -x, y up = here z, z back = here y)."""
    return Vector((-(v.x - origin.x), v.z - origin.z, v.y - origin.y))


def bounds(points):
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return [round((a + b) / 2, 4) for a, b in zip(lo, hi)], [round(b - a, 4) for a, b in zip(lo, hi)]


def export_game(folder):
    """ZDCFixtureArt.fbx for the game: "<kind>_<finish>" pieces, the markers mark_o / mark_x / mark_y / mark_z (the game's
    axes, 10 studs each), "mark_<kind>" at each kind's frame origin and "mark_<kind>_box" at its box's corner (W / 2, H,
    D / 2 in its frame); the manifest ZDCFixtureArt.json (KONTRAKT.md) with the finishes for FixtureMesh.Looks."""
    os.makedirs(folder, exist_ok=True)
    temp = bpy.data.collections.new("Fixtures_Export")
    bpy.context.scene.collection.children.link(temp)
    dg = bpy.context.evaluated_depsgraph_get()
    pieces, details = {}, []
    for kind, *_ in KINDS:
        col = bpy.data.collections["Z_" + kind]
        origin = Vector(col["origin"])
        for o in col.objects:
            if o.type != "MESH":
                continue
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            if not me.polygons:
                continue
            centre, size = bounds([game(o.matrix_world @ v.co, origin) for v in me.vertices])
            details.append({"kind": kind, "name": o.name.split(".")[0], "finish": me.materials[0]["finish"], "center": centre, "size": size})
            split_by_finish(me, o.matrix_world.copy(), pieces, kind)
    made = []
    manifest = {"fixtures": {}, "pieces": {}, "details": details, "finishes": {}}
    for (kind, finish), meshes in sorted(pieces.items()):
        bm = bmesh.new()
        for piece in meshes:
            bm.from_mesh(piece)
        name = f"{kind}_{finish}"
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
        origin = Vector(bpy.data.collections["Z_" + kind]["origin"])
        centre, size = bounds([game(v.co, origin) for v in me.vertices])
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        manifest["pieces"][name] = {"kind": kind, "finish": finish, "center": centre, "size": size, "triangles": tris}
    marks = [("mark_o", (0, 0, 0)), ("mark_x", (-10, 0, 0)), ("mark_y", (0, 0, 10)), ("mark_z", (0, 10, 0))]
    for kind, _, w, h, d, _ in KINDS:
        origin = Vector(bpy.data.collections["Z_" + kind]["origin"])
        marks.append(("mark_" + kind, tuple(origin)))
        marks.append((f"mark_{kind}_box", tuple(origin + Vector((-w / 2, d / 2, h)))))
        names = sorted(n for n, p in manifest["pieces"].items() if p["kind"] == kind)
        manifest["fixtures"][kind] = {"size": [w, h, d], "pieces": names, "triangles": sum(manifest["pieces"][n]["triangles"] for n in names)}
    for name, at in marks:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.3)
        bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(M["iron"])
        o = bpy.data.objects.new(name, me)
        temp.objects.link(o)
        made.append(o)
    for name, (hexcode, _, _, _, material) in FINISHES.items():
        look = {"color": hexcode.upper(), "material": material, "palette": name in PALETTE}
        look.update(GAME.get(name, {}))
        manifest["finishes"][name] = look
    for o in bpy.context.scene.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.fbx(filepath=os.path.join(folder, "ZDCFixtureArt.fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="OFF", use_mesh_modifiers=True)
    with open(os.path.join(folder, "ZDCFixtureArt.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True, ensure_ascii=False)
    for o in list(temp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(temp)
    return manifest


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag):
        return argv[argv.index(flag) + 1] if flag in argv else None

    at = build_all()
    build_scenes()
    studio(at)
    report = check_bounds()
    for kind, out, top in report:
        if any(v > 0.02 for v in out.values()):
            print(f"WARNING {kind} sticks out of its box: {out}")
    source = globals().get("__file__", "")
    if os.path.isfile(source) and "fixtures.py" not in bpy.data.texts:
        bpy.data.texts.new("fixtures.py").write(open(source, encoding="utf-8").read())
    if arg("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--save")))
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        manifest = export_game(folder)
        for kind, info in manifest["fixtures"].items():
            print(f"  {kind:14s} {info['triangles']:5d} triangles  {', '.join(p[len(kind) + 1:] for p in info['pieces'])}")
        tris = sum(p["triangles"] for p in manifest["pieces"].values())
        print(f"ZDCFixtureArt: {len(manifest['pieces'])} pieces, {tris} triangles, the largest {max(p['triangles'] for p in manifest['pieces'].values())}")
    if arg("--render"):
        only = set(arg("--only").split(",")) if arg("--only") else None
        render_all(arg("--render"), int(arg("--samples") or 96), only)
    for kind, out, top in report:
        print(f"  {kind:14s} top {top:5.2f}  sticks out {out or '-'}")


main()
