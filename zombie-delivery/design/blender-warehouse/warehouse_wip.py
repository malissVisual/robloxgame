"""Zombie Delivery 8.x SANDBOX: sklad ZDC z vlnitého plechu (stojí na každém pozemku hráče) v Blenderu.

Spuštění v Blenderu: záložka Scripting → Open → warehouse.py → Run Script (▶, nebo Alt+P). Skript postaví sklad do
kolekcí "Sklad …": zdi z vlnitého plechu s oranžovým pruhem ZDC a betonovým soklem, sedlovou střechu se světlíky,
okapy a svody, otevřená rolovací vrata se sloupky, velkou ceduli ZDC, světla na zdech a uvnitř ocelové rámy (sloupy,
vazníky, vaznice), obklad stěn, lampy a betonovou podlahu (desky a spáry jen barvami). Když ho spustíš znovu, starý
sklad nejdřív smaže.

Rozměry jsou přesně ty, které má sklad ve hře (shared/WarehouseLayout.luau: 80 × 24 × 60 studů, hřeben o 8 výš,
vrata 26 × 16 uprostřed jižní zdi; 1 jednotka = 1 stud). Vrata míří na -Y (pohled zepředu = Numpad 1), střed spodku
skladu je v počátku. Stojany a pult UPGRADES v modelu nejsou: zůstávají z dílů hry (ukazují a prodávají věci), stejně
jako cedule s tvým jménem nad vraty, tabule STOCK a nápisy na podlaze. Kolekce "Hra (jen náhled)" je ukazuje jen pro
obrázek, do hry se z ní nic neexportuje.

Bez Blenderu, jen s modulem bpy (pip install bpy, Python 3.13):
    python warehouse.py -- --save warehouse.blend --export roblox --render složka --sheet warehouse-preview.png
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

# ───────────────────────────────────────────────────────────── NASTAVENÍ (změň a spusť znovu)
EXPORT = False       # True = po postavení uloží ZDCWarehouseArt.fbx pro hru do složky "roblox" vedle .blend souboru
LOGO, NAME = "ZDC", "ZOMBIE DELIVERY CO."    # nápisy na velké ceduli nad vraty

# Povrchy: jméno → (barva #RRGGBB, drsnost, kov, záře). Hra (server/WarehouseMesh.luau, tabulka LOOKS) dá každému
# povrchu svou barvu a materiál Robloxu: když tady barvu změníš, řekni Claudovi, ať ji přepíše i tam.
FINISHES = {
    "clad": ("#BCC2C8", 0.45, 0.5, 0),      # vlnitý plech zdí (plochy)
    "rib": ("#A0A7AF", 0.45, 0.5, 0),       # vlny plechu (o kousek tmavší)
    "orange": ("#F0842C", 0.5, 0, 0),       # pruh ZDC, rolovací vrata, rám cedule
    "concrete": ("#A8A69E", 0.9, 0, 0),     # sokl kolem skladu
    "trim": ("#2A2D32", 0.5, 0.3, 0),       # tmavé lemy: rohy, okapy, svody, štítová prkna, cedule, lampy
    "roof": ("#767C84", 0.45, 0.5, 0),      # střecha
    "roofin": ("#C9CCCB", 0.8, 0, 0),       # podhled střechy (zevnitř a pod přesahem)
    "skylight": ("#CFE3EA", 0.1, 0, 0),     # světlíky ve střeše (průsvitné)
    "steel": ("#4A4E56", 0.45, 0.6, 0),     # ocelové rámy uvnitř, kolejnice vrat
    "galv": ("#969CA0", 0.5, 0.6, 0),       # pozinkované vaznice pod střechou
    "liner": ("#D6D8D4", 0.8, 0, 0),        # obklad stěn uvnitř
    "seam": ("#B4B8B6", 0.8, 0, 0),         # spáry obkladu
    "kick": ("#8E8C86", 0.9, 0, 0),         # betonový sokl stěn uvnitř
    "floor": ("#969896", 0.85, 0, 0),       # betonová podlaha: tři odstíny desek a tmavé spáry
    "floor2": ("#8C8E8C", 0.85, 0, 0),
    "floor3": ("#A2A3A0", 0.85, 0, 0),
    "joint": ("#6C6E6E", 0.9, 0, 0),
    "rubber": ("#1A1B1D", 0.9, 0, 0),       # gumová lišta vrat, tmavé pozadí žaluzie
    "yellow": ("#F2C62A", 0.5, 0, 0),       # sloupky u vrat
    "white": ("#EEEEE8", 0.5, 0, 0),        # bílý nápis na ceduli
    "logo": ("#F0842C", 0.4, 0, 1.5),       # písmena ZDC (v noci svítí)
    "glow": ("#FFECC8", 0.4, 0, 6.0),       # světla na zdech (v noci svítí)
    "red": ("#C8322E", 0.5, 0, 0),          # požární zvonek
}

# ───────────────────────────────────────────────────────────── míry ze hry (NEMĚŇ: hra má stejná čísla)
# tools/warehouse/mesh-check.py hlídá, že sedí se shared/WarehouseLayout.luau, Config.Warehouse a SandboxMap.
W, H, D = 80.0, 24.0, 60.0      # sklad: šířka (východ-západ), výška zdí, hloubka (sever-jih); SandboxMap plot.warehouse
RIDGE = 8.0                     # hřeben nad zdmi (Config.Warehouse.Ridge)
WALL = 1.0                      # tloušťka zdí (WarehouseLayout.Wall)
DOOR_W, DOOR_H = 26.0, 16.0     # otvor vrat (SandboxMap.DoorWidth, Config.Warehouse.DoorHeight)
FLOOR_TOP = 0.05                # vršek podlahy (WarehouseLayout.FloorTop)
PLINTH = 1.4                    # betonový sokl
RIB = 2.5                       # vlny plechu od sebe (jako žebra dílů hry)
OVERHANG = 1.2                  # přesah střechy přes boční zdi (podél sklonu)
ROOF_T = 0.6                    # tloušťka střechy
FRAMES = (-25.0, -14.0, -3.0, 8.0, 19.0)   # ocelové rámy uvnitř (z hry: jih +), na nich lampy jako ve hře
LAMP_X, LAMP_Z = (-21.5, 0.0, 21.5), (-14.0, 8.0)
GLOW_TOP = 22.3                 # vršek svítícího disku lampy (díl hry, zůstává): stínidlo modelu sedí na něm
SKYLIGHTS = ((-21.0, -17.0), (-11.0, -7.0), (1.0, 5.0), (11.0, 15.0))   # světlíky (z od-do) na obou stranách střechy
SKY_U = (10.0, 30.0)            # ... a od-do po sklonu od hřebene

# ───────────────────────────────────────────────────────────── odvozené míry (souřadnice hry: x východ, y nahoru, z jih)
HX, HZ = W / 2, D / 2
TOP = H + RIDGE                         # 32: spodek střechy na hřebeni
TAN = RIDGE / HX                        # sklon střechy (0.2)
SLOPE = math.atan(TAN)
C, S = math.cos(SLOPE), math.sin(SLOPE)
ROOF_L = math.hypot(HX, RIDGE) + OVERHANG   # střecha od hřebene k okapu (po sklonu)
ROOF_Z = HZ + 1.0                       # střecha přesahuje štíty o 1
DECK = 0.35                             # plech střechy nad podhledem; vlny sahají do ROOF_T
INNER = HX - WALL                       # 39: líc boční zdi uvnitř
INNER_Z = HZ - WALL                     # 29: líc štítové zdi uvnitř
PIECES = "warehouse"                    # díly pro hru: warehouse_<povrch>
MARK = "WarehouseMark"                  # značky pro hru: WarehouseMark_o / _x / _y / _z / _b / _r

M = {}          # finish → material
COLS = {}       # collection key → collection


def linear(hexcode):
    h = hexcode.lstrip("#")
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))


def material(name, hexcode, rough, metal=0.0, emit=0.0, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
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
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        transmission = p.inputs.get("Transmission Weight") or p.inputs.get("Transmission")
        if transmission:
            transmission.default_value = 0.8
    return m


def materials():
    for name, (hexcode, rough, metal, emit) in FINISHES.items():
        m = material("W " + name, hexcode, rough, metal, emit, 0.45 if name == "skylight" else 1.0)
        m["finish"] = name
        M[name] = m


# ───────────────────────────────────────────────────────────── stavební kameny
# Everything is built in the game's axes (x east, y up, z south: the door's side) and turned into Blender's at the end
# of each object (Blender x = x, y = -z, z = y: the door looks at -Y).
def to_blender(p):
    return Vector((p[0], -p[2], p[1]))


def newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        n.x += (p.y - q.y) * (p.z + q.z)
        n.y += (p.z - q.z) * (p.x + q.x)
        n.z += (p.x - q.x) * (p.y + q.y)
    return n


class Part:
    """One Blender object being built: its vertices in the game's axes, its faces each with a finish, and the boxes of
    its details (the manifest's: tools/warehouse/mesh-check.py checks what they keep clear)."""

    def __init__(self, name, col):
        self.name, self.col = name, col
        self.verts, self.faces, self.fins, self.smooth, self.details = [], [], [], [], []

    def note(self, pts, finish, label=None):
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        self.details.append({"name": label or self.name, "finish": finish, "lo": lo, "hi": hi})

    def poly(self, pts, finish, out=None, smooth=False):
        pts = [Vector(p) for p in pts]
        if out is not None and newell(pts).dot(Vector(out)) < 0:
            pts.reverse()
        start = len(self.verts)
        self.verts.extend(pts)
        self.faces.append(list(range(start, start + len(pts))))
        self.fins.append(finish)
        self.smooth.append(smooth)

    def quad(self, pts, finish, out, label=None):
        self.poly(pts, finish, out)
        if label:
            self.note(pts, finish, label)

    def hexa(self, c, finish, skip=(), label=None):
        """Eight corners (the bottom ring 0-3, the top ring 4-7, in the same order): six faces, each turned out."""
        c = [Vector(p) for p in c]
        mid = sum(c, Vector()) / 8
        for key, idx in (("-z", (0, 1, 2, 3)), ("+z", (4, 5, 6, 7)), ("-y", (0, 1, 5, 4)), ("+x", (1, 2, 6, 5)),
                         ("+y", (2, 3, 7, 6)), ("-x", (3, 0, 4, 7))):
            if key not in skip:
                pts = [c[i] for i in idx]
                self.poly(pts, finish, sum(pts, Vector()) / 4 - mid)
        self.note(c, finish, label)

    def box(self, lo, hi, finish, skip=(), label=None):
        (x0, y0, z0), (x1, y1, z1) = [min(a, b) for a, b in zip(lo, hi)], [max(a, b) for a, b in zip(lo, hi)]
        self.hexa([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
                  finish, skip, label)

    def obox(self, centre, ax, ay, az, finish, label=None):
        """A box turned any way: its centre and three half axes."""
        o, ax, ay, az = Vector(centre), Vector(ax), Vector(ay), Vector(az)
        signs = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
        self.hexa([o + a * ax + b * ay + c * az for a, b, c in signs], finish, (), label)

    def beam(self, a, b, half_w, half_h, finish, up=(0, 1, 0), label=None):
        """A square bar from a to b."""
        a, b = Vector(a), Vector(b)
        along = (b - a) / 2
        side = along.cross(Vector(up)).normalized()
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        lift = side.cross(along).normalized()
        self.obox((a + b) / 2, along, side * half_w, lift * half_h, finish, label)

    def cyl(self, a, b, r, finish, seg=12, r2=None, caps=(True, True), label=None):
        """A cylinder (or a cone: r2 at b) from a to b, smooth round its side."""
        a, b = Vector(a), Vector(b)
        axis = (b - a).normalized()
        u = axis.cross(Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))).normalized()
        v = axis.cross(u)
        r2 = r if r2 is None else r2
        ring_a = [a + (u * math.cos(2 * math.pi * k / seg) + v * math.sin(2 * math.pi * k / seg)) * r for k in range(seg)]
        ring_b = [b + (u * math.cos(2 * math.pi * k / seg) + v * math.sin(2 * math.pi * k / seg)) * r2 for k in range(seg)]
        start = len(self.verts)
        self.verts.extend(ring_a + ring_b)
        mid = (a + b) / 2
        for k in range(seg):
            idx = [start + k, start + (k + 1) % seg, start + seg + (k + 1) % seg, start + seg + k]
            pts = [self.verts[i] for i in idx]
            if newell(pts).dot(sum(pts, Vector()) / 4 - mid) < 0:
                idx.reverse()
            self.faces.append(idx)
            self.fins.append(finish)
            self.smooth.append(True)
        if caps[0] and r > 1e-4:
            self.poly(ring_a, finish, -axis)
        if caps[1] and r2 > 1e-4:
            self.poly(ring_b, finish, axis)
        self.note(ring_a + ring_b, finish, label)

    def prism(self, tri, depth_lo, depth_hi, finish, label=None):
        """A triangle (x, y points) pushed along z from depth_lo to depth_hi."""
        lo = [Vector((x, y, depth_lo)) for x, y in tri]
        hi = [Vector((x, y, depth_hi)) for x, y in tri]
        mid = sum(lo + hi, Vector()) / 6
        self.poly(lo, finish, (0, 0, -1))
        self.poly(hi, finish, (0, 0, 1))
        for i in range(3):
            j = (i + 1) % 3
            pts = [lo[i], lo[j], hi[j], hi[i]]
            self.poly(pts, finish, sum(pts, Vector()) / 4 - mid)
        self.note(lo + hi, finish, label)

    def mesh(self, verts, faces, finish, label=None):
        """Faces as they come (their winding kept: the text's)."""
        start = len(self.verts)
        self.verts.extend(Vector(v) for v in verts)
        for f in faces:
            self.faces.append([start + i for i in f])
            self.fins.append(finish)
            self.smooth.append(False)
        self.note(verts, finish, label)

    def make(self, mats=None):
        mats = mats or M
        me = bpy.data.meshes.new(self.name)
        me.from_pydata([to_blender(v) for v in self.verts], [], self.faces)
        used = list(dict.fromkeys(self.fins))
        for f in used:
            me.materials.append(mats[f])
        index = {f: i for i, f in enumerate(used)}
        for p, fin, smooth in zip(me.polygons, self.fins, self.smooth):
            p.material_index = index[fin]
            p.use_smooth = smooth
        me.update()
        o = bpy.data.objects.new(self.name, me)
        self.col.objects.link(o)
        o["details"] = json.dumps(self.details)
        return o


def text_mesh(body, height, width, depth, bold=0.03):
    """Text as a mesh in the xy plane (centred, extruded ±depth / 2 along z), scaled to `height` tall and at most `width`
    wide; few curve steps so it stays light in Roblox. Returns (verts, triangles)."""
    cu = bpy.data.curves.new("text", "FONT")
    cu.body, cu.size, cu.align_x, cu.align_y = body, 1.0, "CENTER", "CENTER"
    cu.resolution_u, cu.offset, cu.extrude = 3, bold, depth / 2
    tmp = bpy.data.objects.new("text", cu)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    k = min(height / (max(ys) - min(ys)), width / (max(xs) - min(xs)))
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    verts = [((v.co.x - cx) * k, (v.co.y - cy) * k, v.co.z) for v in bm.verts]
    tris = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return verts, tris


# ───────────────────────────────────────────────────────────── vlnitý plech
# The trapezoid sheet's profile across one rib (from its middle, in parts of the rib pitch: a big rib in the middle, a
# small stiffener in each pan) and how far each point stands out of the wall (studs, for the walls' 0.3 deep ribs).
PROFILE = ((-0.5, 0.0), (-0.388, 0.0), (-0.364, 0.06), (-0.316, 0.06), (-0.292, 0.0), (-0.18, 0.0), (-0.1, 0.3),
           (0.1, 0.3), (0.18, 0.0), (0.292, 0.0), (0.316, 0.06), (0.364, 0.06), (0.388, 0.0), (0.5, 0.0))


def depth_at(u, first, pitch, height):
    k = math.floor((u - first) / pitch + 0.5)
    t = (u - (first + k * pitch)) / pitch
    for (t0, w0), (t1, w1) in zip(PROFILE, PROFILE[1:]):
        if t0 - 1e-9 <= t <= t1 + 1e-9:
            f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return (w0 + (w1 - w0) * f) * height / 0.3
    return 0.0


def corrugation(u0, u1, first, pitch=RIB, height=0.3, extra=()):
    """The sheet's profile from u0 to u1: [(u, out)], the ribs' middles at first + k * pitch."""
    cuts = {u0, u1}
    k0, k1 = math.floor((u0 - first) / pitch) - 1, math.ceil((u1 - first) / pitch) + 1
    for k in range(k0, k1 + 1):
        for t, _ in PROFILE:
            u = first + k * pitch + t * pitch
            if u0 + 1e-6 < u < u1 - 1e-6:
                cuts.add(u)
    cuts.update(e for e in extra if u0 + 1e-6 < e < u1 - 1e-6)
    out = []
    for u in sorted(cuts):
        if not out or u - out[-1][0] > 1e-6:
            out.append((u, depth_at(u, first, pitch, height)))
    return out


def wall_point(plane, at, out, u, v, w):
    return (u, v, at + out * w) if plane == "z" else (at + out * w, v, u)


def skin(part, plane, at, out, u0, u1, bottom, top, first, label):
    """The corrugated sheet on a wall's outer face: plane "z" (the wall at z = at, u = x) or "x" (at x = at, u = z), out ±1
    the way out of the building, from bottom(u) to top(u) high."""
    normal = (0, 0, out) if plane == "z" else (out, 0, 0)
    pts = []
    prof = corrugation(u0, u1, first, extra=(0.0,))
    for (ua, wa), (ub, wb) in zip(prof, prof[1:]):
        finish = "rib" if max(wa, wb) > 0.1 else "clad"
        quad = [wall_point(plane, at, out, ua, bottom(ua), wa), wall_point(plane, at, out, ub, bottom(ub), wb),
                wall_point(plane, at, out, ub, top(ub), wb), wall_point(plane, at, out, ua, top(ua), wa)]
        part.poly(quad, finish, normal)
        pts += quad
    part.note(pts, "clad", label)


def liner(part, plane, at, inward, u0, u1, bottom, top, first, label):
    """The wall's lining inside: flat on the wall's inner face, its panels' seams every rib, a concrete kick at the
    bottom and an orange band at the ZDC stripe's height (colours only: nothing stands out of the face)."""
    normal = (0, 0, inward) if plane == "z" else (inward, 0, 0)
    seams = [first + k * RIB for k in range(-40, 41)]
    cuts = {u0, u1, 0.0} if u0 < 0 < u1 else {u0, u1}
    for s in seams:
        for e in (s - 0.04, s + 0.04):
            if u0 + 1e-6 < e < u1 - 1e-6:
                cuts.add(e)
    cuts = sorted(cuts)
    rows = [(PLINTH, 5.2, "liner"), (5.2, 6.0, "orange"), (6.0, None, "liner")]
    if bottom < PLINTH:
        rows.insert(0, (bottom, PLINTH, "kick"))
    pts = []
    for ua, ub in zip(cuts, cuts[1:]):
        seam = any(abs((ua + ub) / 2 - s) < 0.04 for s in seams)
        for y0, y1, finish in rows:
            y0 = max(y0, bottom)
            ya0, yb0 = y0, y0
            ya1, yb1 = (top(ua), top(ub)) if y1 is None else (y1, y1)
            if ya1 <= y0 + 1e-6 and yb1 <= y0 + 1e-6:
                continue
            fin = "seam" if seam and finish == "liner" else finish
            quad = [wall_point(plane, at, 0, ua, ya0, 0), wall_point(plane, at, 0, ub, yb0, 0),
                    wall_point(plane, at, 0, ub, yb1, 0), wall_point(plane, at, 0, ua, ya1, 0)]
            part.poly(quad, fin, normal)
            pts += quad
    part.note(pts, "liner", label)


def gable(u):
    """The roof's underside over a wall's line (the gables' top): 32 at the ridge, 24 at the side walls."""
    return TOP - TAN * abs(u)


# ───────────────────────────────────────────────────────────── plášť: zdi, sokl, pruh, rohy
def shell():
    part = Part("Plášť", COLS["shell"])
    flat = lambda value: (lambda u: value)
    # the back (north) and the front (south) gable walls, the side walls; the front round the door: its two sides,
    # and over the door the header and gable (the door's rails cover the sheet's edges)
    rail = DOOR_W / 2 + 0.7
    skin(part, "z", -HZ, -1, -HX, HX, flat(PLINTH), gable, -HX + RIB / 2, "Zeď sever plech")
    skin(part, "z", HZ, 1, -HX, -rail, flat(PLINTH), gable, -HX + RIB / 2, "Zeď jih plech západ")
    skin(part, "z", HZ, 1, rail, HX, flat(PLINTH), gable, -HX + RIB / 2, "Zeď jih plech východ")
    skin(part, "z", HZ, 1, -rail, rail, flat(DOOR_H), gable, -HX + RIB / 2, "Zeď jih plech nad vraty")
    for side in (-1, 1):
        skin(part, "x", side * HX, side, -HZ, HZ, flat(PLINTH), flat(H), -HZ + RIB / 2, f"Zeď {'západ' if side < 0 else 'východ'} plech")
    # the concrete plinth and the ZDC stripe round the building (not across the door)
    for name, y0, y1, out, finish in (("Sokl", 0.0, PLINTH, 0.4, "concrete"), ("Pruh ZDC", 5.2, 6.0, 0.45, "orange")):
        part.box((-HX, y0, -HZ - out), (HX, y1, -HZ), finish, skip=("-y",), label=f"{name} sever")
        for side in (-1, 1):
            part.box((side * HX, y0, -HZ), (side * (HX + out), y1, HZ), finish, skip=("-y",), label=f"{name} bok")
            part.box((side * DOOR_W / 2, y0, HZ), (side * HX, y1, HZ + out), finish, skip=("-y",), label=f"{name} jih")
    # the corners' trims
    for sx in (-1, 1):
        for sz in (-1, 1):
            part.box((sx * HX - 0.55, 0, sz * HZ - 0.55), (sx * HX + 0.55, H, sz * HZ + 0.55), "trim", skip=("-y",), label="Roh")
    # the door's opening: its jambs and its head in the wall's thickness, the flashing over it outside
    for side in (-1, 1):
        x = side * DOOR_W / 2
        part.quad([(x, 0, INNER_Z), (x, DOOR_H, INNER_Z), (x, DOOR_H, HZ), (x, 0, HZ)], "trim", (-side, 0, 0), "Ostění vrat")
    part.quad([(-DOOR_W / 2, DOOR_H, INNER_Z), (DOOR_W / 2, DOOR_H, INNER_Z), (DOOR_W / 2, DOOR_H, HZ), (-DOOR_W / 2, DOOR_H, HZ)],
              "trim", (0, -1, 0), "Nadpraží vrat")
    part.box((-rail, DOOR_H, HZ), (rail, DOOR_H + 0.5, HZ + 0.45), "trim", label="Lišta nad vraty")
    # a louvre high in the back gable, a fire bell by the door
    part.box((-2.8, 26.4, -HZ - 0.34), (2.8, 29.0, -HZ - 0.3), "rubber", label="Žaluzie pozadí")
    for x0, x1, y0, y1 in ((-3.0, 3.0, 29.0, 29.2), (-3.0, 3.0, 26.2, 26.4), (-3.0, -2.8, 26.4, 29.0), (2.8, 3.0, 26.4, 29.0)):
        part.box((x0, y0, -HZ - 0.7), (x1, y1, -HZ - 0.25), "trim", label="Žaluzie rám")
    for k in range(5):
        y = 26.7 + 0.5 * k
        part.obox((0, y, -HZ - 0.5), (2.8, 0, 0), (0, 0.2, -0.2), (0, 0.02, 0.02), "trim", label="Žaluzie lamela")
    part.cyl((-17.0, 10.5, HZ + 0.3), (-17.0, 10.5, HZ + 0.75), 0.5, "red", seg=14, label="Požární zvonek")
    part.cyl((-17.0, 10.5, HZ + 0.75), (-17.0, 10.5, HZ + 0.85), 0.12, "trim", seg=8, label="Požární zvonek")
    part.make()

    lining = Part("Obklad uvnitř", COLS["inside"])
    under = gable
    liner(lining, "z", -INNER_Z, 1, -INNER, INNER, FLOOR_TOP, under, -HX, "Obklad sever")
    liner(lining, "z", INNER_Z, -1, -INNER, -DOOR_W / 2, FLOOR_TOP, under, -HX, "Obklad jih")
    liner(lining, "z", INNER_Z, -1, DOOR_W / 2, INNER, FLOOR_TOP, under, -HX, "Obklad jih")
    liner(lining, "z", INNER_Z, -1, -DOOR_W / 2, DOOR_W / 2, DOOR_H, under, -HX, "Obklad nad vraty")
    for side in (-1, 1):
        liner(lining, "x", side * INNER, -side, -INNER_Z, INNER_Z, FLOOR_TOP, lambda u: gable(INNER), -HZ, "Obklad bok")
    lining.make()


# ───────────────────────────────────────────────────────────── střecha
def roof_point(side, u, z, off):
    """A point of the roof: side -1 west, +1 east; u down the slope from the ridge (on the underside's line), off out
    of the underside (up and out)."""
    return Vector((side * (C * u + S * off), TOP - S * u + C * off, z))


def roof():
    part = Part("Střecha", COLS["roof"])
    rows = (0.0, SKY_U[0], SKY_U[1], ROOF_L)
    profile = corrugation(-ROOF_Z, ROOF_Z, -ROOF_Z + 1.0, pitch=2.0, height=ROOF_T - DECK,
                          extra=[z for pair in SKYLIGHTS for z in pair])
    columns = sorted({-ROOF_Z, ROOF_Z, *[z for pair in SKYLIGHTS for z in pair]})

    def hole(row, z0, z1):
        return row == 1 and any(a - 1e-6 <= z0 and z1 <= b + 1e-6 for a, b in SKYLIGHTS)
    for side in (-1, 1):
        down = Vector((side * C, -S, 0))
        up = Vector((side * S, C, 0))
        tag = "západ" if side < 0 else "východ"
        top_pts, under_pts = [], []
        # the sheet: its ribs run down the slope; the skylights' holes in the middle row
        for row in range(3):
            for (za, wa), (zb, wb) in zip(profile, profile[1:]):
                if hole(row, za, zb):
                    continue
                q = [roof_point(side, rows[row], za, DECK + wa), roof_point(side, rows[row], zb, DECK + wb),
                     roof_point(side, rows[row + 1], zb, DECK + wb), roof_point(side, rows[row + 1], za, DECK + wa)]
                part.poly(q, "roof", up)
                top_pts += q
            # the underside (the ceiling inside, the soffit under the overhang)
            for za, zb in zip(columns, columns[1:]):
                if hole(row, za, zb):
                    continue
                q = [roof_point(side, rows[row], za, 0), roof_point(side, rows[row], zb, 0),
                     roof_point(side, rows[row + 1], zb, 0), roof_point(side, rows[row + 1], za, 0)]
                part.poly(q, "roofin", -up)
                under_pts += q
            # the gable ends (under the barge boards)
            for end in (-1, 1):
                z = end * ROOF_Z
                part.poly([roof_point(side, rows[row], z, 0), roof_point(side, rows[row + 1], z, 0),
                           roof_point(side, rows[row + 1], z, DECK), roof_point(side, rows[row], z, DECK)], "trim", (0, 0, end))
        part.note(top_pts, "roof", f"Střecha {tag}")
        part.note(under_pts, "roofin", f"Podhled {tag}")
        # the eave's edge
        eave = []
        for (za, wa), (zb, wb) in zip(profile, profile[1:]):
            q = [roof_point(side, ROOF_L, za, 0), roof_point(side, ROOF_L, zb, 0),
                 roof_point(side, ROOF_L, zb, DECK + wb), roof_point(side, ROOF_L, za, DECK + wa)]
            part.poly(q, "trim", down)
            eave += q
        part.note(eave, "trim", f"Okraj střechy {tag}")
        # the skylights: the hole's sides, the panel in it
        for z0, z1 in SKYLIGHTS:
            u0, u1 = SKY_U
            for z, normal in ((z0, (0, 0, 1)), (z1, (0, 0, -1))):
                part.poly([roof_point(side, u0, z, 0), roof_point(side, u1, z, 0), roof_point(side, u1, z, DECK),
                           roof_point(side, u0, z, DECK)], "roof", normal)
            for u, normal in ((u0, down), (u1, -down)):
                for (za, wa), (zb, wb) in zip(profile, profile[1:]):
                    if z0 - 1e-6 <= za and zb <= z1 + 1e-6:
                        part.poly([roof_point(side, u, za, 0), roof_point(side, u, zb, 0), roof_point(side, u, zb, DECK + wb),
                                   roof_point(side, u, za, DECK + wa)], "roof", normal)
            centre = roof_point(side, (u0 + u1) / 2, (z0 + z1) / 2, 0.22)
            part.obox(centre, down * ((u1 - u0) / 2 - 0.01), up * 0.1, (0, 0, (z1 - z0) / 2 - 0.01), "skylight", f"Světlík {tag}")
        # the barge boards along the gables' edges
        for end in (-1, 1):
            centre = roof_point(side, ROOF_L / 2, end * (ROOF_Z + 0.15), 0.15)
            part.obox(centre, down * (ROOF_L / 2 + 0.02), up * 0.45, (0, 0, 0.15), "trim", "Štítové prkno")
        # the gutter under the eave (a U open at the top) and the downpipes at its ends
        x0, x1 = side * (HX + 0.5), side * (HX + 1.3)
        y0, y1 = 22.88, 23.68
        part.box((side * (HX + 1.2), y0, -ROOF_Z), (x1, y1, ROOF_Z), "trim", label="Okap")
        part.box((x0, y0, -ROOF_Z), (x1, y0 + 0.1, ROOF_Z), "trim", label="Okap")
        part.box((x0, y0, -ROOF_Z), (side * (HX + 0.6), 23.45, ROOF_Z), "trim", label="Okap")
        for end in (-1, 1):
            part.box((x0, y0, end * (ROOF_Z - 0.05)), (x1, 23.6, end * ROOF_Z), "trim", label="Okap čelo")
        for end in (-1, 1):
            x, z = side * (HX + 0.75), end * (HZ - 1.4)
            part.cyl((x, 0.55, z), (x, 22.95, z), 0.28, "trim", seg=12, caps=(False, False), label="Svod")
            part.cyl((x, 0.8, z), (x + side * 0.5, 0.2, z), 0.28, "trim", seg=12, label="Svod koleno")
            for y in (4.0, 10.0, 16.0, 21.5):
                part.box((side * (HX + 0.3), y - 0.08, z - 0.36), (side * (HX + 1.08), y + 0.08, z + 0.36), "trim", label="Svod objímka")
    # the ridge cap (an upturned V along the ridge)
    reach = 1.1
    crest = lambda x: TOP - TAN * abs(x) + ROOF_T / C
    outer = [(-reach, crest(reach) + 0.04), (0.0, TOP + 0.95), (reach, crest(reach) + 0.04)]
    inner = [(reach, crest(reach) - 0.04), (0.0, TOP + 0.87), (-reach, crest(reach) - 0.04)]
    ring = outer + inner
    z0, z1 = -ROOF_Z - 0.1, ROOF_Z + 0.1
    pts = []
    for i in range(6):
        (xa, ya), (xb, yb) = ring[i], ring[(i + 1) % 6]
        q = [(xa, ya, z0), (xb, yb, z0), (xb, yb, z1), (xa, ya, z1)]
        part.poly(q, "trim", (-(yb - ya), xb - xa, 0))  # (the ring runs clockwise: out is to the left)
        pts += q
    for z, normal in ((z0, (0, 0, -1)), (z1, (0, 0, 1))):
        for a, b, c, d in ((0, 1, 4, 5), (1, 2, 3, 4)):
            part.poly([(ring[k][0], ring[k][1], z) for k in (a, b, c, d)], "trim", normal)
    part.note(pts, "trim", "Hřebenáč")
    part.make()


# ───────────────────────────────────────────────────────────── vrata, sloupky, světla, cedule
def door():
    part = Part("Vrata", COLS["door"])
    half = DOOR_W / 2
    for side in (-1, 1):
        part.box((side * half, 0, HZ), (side * (half + 0.7), DOOR_H, HZ + 0.6), "steel", skip=("-y",), label="Kolejnice vrat")
        part.box((side * (half + 0.1), 0.2, HZ + 0.6), (side * (half + 0.6), DOOR_H - 0.2, HZ + 0.64), "rubber", label="Kolejnice vrat")
    # the door rolled up: its last slats and its bottom bar in the opening's top
    part.box((-half, 14.4, HZ - 0.62), (half, DOOR_H, HZ - 0.38), "orange", label="Lamely vrat")
    for y in (14.8, 15.2, 15.6):
        part.box((-half, y - 0.025, HZ - 0.65), (half, y + 0.025, HZ - 0.35), "trim", label="Lamely vrat")
    part.box((-half, 14.1, HZ - 0.725), (half, 14.4, HZ - 0.275), "rubber", label="Spodní lišta vrat")
    # the roll's box inside over the door, its end plates and its motor
    part.box((-half - 0.8, 16.2, 26.4), (half + 0.8, 18.8, INNER_Z - 0.02), "steel", label="Skříň navíjení")
    for side in (-1, 1):
        part.box((side * (half + 0.8), 16.1, 26.3), (side * (half + 1.0), 18.9, INNER_Z - 0.02), "trim", label="Skříň navíjení")
    part.cyl((half + 1.0, 17.2, 27.4), (half + 2.3, 17.2, 27.4), 0.55, "trim", seg=14, label="Motor vrat")
    part.box((half + 1.0, 16.5, 26.9), (half + 1.6, 17.9, 27.9), "steel", label="Motor vrat")
    # the bollards each side outside: yellow steel posts, a dome, two black bands
    for side in (-1, 1):
        x, z = side * (half + 1.8), HZ + 1.4
        part.cyl((x, 0, z), (x, 3.25, z), 0.5, "yellow", seg=16, caps=(False, False), label="Sloupek")
        part.cyl((x, 3.25, z), (x, 3.4, z), 0.5, "yellow", seg=16, r2=0.32, caps=(False, True), label="Sloupek")
        for y in (2.55, 2.95):
            part.cyl((x, y, z), (x, y + 0.2, z), 0.515, "rubber", seg=16, label="Sloupek pruh")
    part.make()


def wall_light(part, at, out, along, label):
    """A wall pack: its back plate on the ribs, the housing, its lens underneath (it glows at night)."""
    at, out, along = Vector(at), Vector(out), Vector(along)
    up = Vector((0, 1, 0))
    part.obox(at + out * 0.03, along * 0.75, up * 0.6, out * 0.03, "trim", label)
    part.obox(at + out * 0.36, along * 0.6, up * 0.4, out * 0.3, "trim", label)
    part.obox(at + out * 0.38 - up * 0.43, along * 0.5, up * 0.04, out * 0.24, "glow", label)  # (under the housing)


def lights():
    part = Part("Světla", COLS["lights"])
    y = 12.5
    for x in (-18.0, 18.0):
        wall_light(part, (x, y, HZ + 0.3), (0, 0, 1), (1, 0, 0), "Světlo na zdi jih")
        wall_light(part, (x, y, -HZ - 0.3), (0, 0, -1), (1, 0, 0), "Světlo na zdi sever")
    for side in (-1, 1):
        for z in (-15.0, 15.0):
            wall_light(part, (side * (HX + 0.3), y, z), (side, 0, 0), (0, 0, 1), "Světlo na zdi bok")
    # two floodlights over the owner's sign (the game writes your name on it)
    for x in (-7.0, 7.0):
        part.box((x - 0.08, 22.95, HZ + 0.3), (x + 0.08, 23.1, HZ + 1.2), "trim", label="Reflektor nad cedulí")
        part.box((x - 0.5, 22.7, HZ + 1.05), (x + 0.5, 23.1, HZ + 1.8), "trim", label="Reflektor nad cedulí")
        part.box((x - 0.42, 22.62, HZ + 1.12), (x + 0.42, 22.7, HZ + 1.72), "glow", label="Reflektor nad cedulí")
    # the hall's lamps: a shade over each glowing disc the game keeps (its light too), on the tie beam
    for z in LAMP_Z:
        for x in LAMP_X:
            part.cyl((x, GLOW_TOP, z), (x, 22.75, z), 1.45, "trim", seg=16, r2=0.45, label="Lampa")
            part.cyl((x, 22.75, z), (x, 23.0, z), 0.18, "trim", seg=8, caps=(False, False), label="Lampa závěs")
    part.make()


def sign():
    part = Part("Cedule ZDC", COLS["sign"])
    z = HZ + 0.1
    part.box((-10.0, 24.5, z), (10.0, 29.5, z + 0.4), "trim", label="Cedule ZDC")
    for x0, x1, y0, y1 in ((-10.15, 10.15, 29.5, 29.65), (-10.15, 10.15, 24.35, 24.5), (-10.15, -10.0, 24.5, 29.5), (10.0, 10.15, 24.5, 29.5)):
        part.box((x0, y0, z), (x1, y1, z + 0.5), "orange", label="Cedule ZDC rám")
    for body, finish, height, width, cy, depth in ((LOGO, "logo", 3.0, 14.0, 27.85, 0.3), (NAME, "white", 0.85, 17.5, 25.3, 0.06)):
        verts, tris = text_mesh(body, height, width, depth)
        front = z + 0.4
        part.mesh([(x, cy + y, front + depth / 2 + zz) for x, y, zz in verts], tris, finish, f"Nápis {body}")
    part.make()


# ───────────────────────────────────────────────────────────── uvnitř: rámy, vaznice, podlaha
def rafter_bottom(x):
    """The rafters' underside (1 deep under the roof's underside) over x."""
    return TOP - TAN * abs(x) - 1.0 / C


def frames():
    part = Part("Ocelové rámy", COLS["inside"])
    for n, zf in enumerate(FRAMES, 1):
        for side in (-1, 1):
            # the column: an I against the side wall, its base plate
            def xs(a, b):
                return side * a, side * b
            for a, b, w in ((38.0, 38.1, 0.35), (38.88, 38.98, 0.35), (38.1, 38.88, 0.04)):
                x0, x1 = xs(a, b)
                part.box((x0, FLOOR_TOP, zf - w), (x1, 24.3, zf + w), "steel", skip=("-y",), label=f"Rám {n} sloup")
            x0, x1 = xs(37.95, 38.98)
            part.box((x0, FLOOR_TOP, zf - 0.5), (x1, FLOOR_TOP + 0.1, zf + 0.5), "steel", skip=("-y",), label=f"Rám {n} patka")
            # the rafter under the roof, from the wall to the ridge
            down, up = Vector((side * C, -S, 0)), Vector((side * S, C, 0))
            reach = 38.98 / C
            for off0, off1, w in ((-0.1, -0.01, 0.35), (-0.92, -0.1, 0.04), (-1.0, -0.92, 0.35)):
                centre = roof_point(side, reach / 2, zf, (off0 + off1) / 2)
                part.obox(centre, down * (reach / 2), up * ((off1 - off0) / 2), (0, 0, w), "steel", f"Rám {n} vazník")
            # the haunch at the knee and its flange
            knee = [(side * 38.0, 20.8), (side * 38.0, rafter_bottom(38.0) + 0.05), (side * 33.0, rafter_bottom(33.0) + 0.05)]
            part.prism(knee, zf - 0.04, zf + 0.04, "steel", f"Rám {n} náběh")
            a, b = Vector((side * 38.0, 20.8, zf)), Vector((side * 33.0, rafter_bottom(33.0), zf))
            part.beam(a, b, 0.04, 0.35, "steel", up=(0, 0, 1), label=f"Rám {n} náběh")
            # the struts from the tie beam up to the rafter
            for x_tie, x_top in ((10.0, 4.5), (26.0, 20.0)):
                part.beam((side * x_tie, 23.8, zf), (side * x_top, rafter_bottom(x_top) + 0.1, zf), 0.15, 0.15, "steel",
                          up=(0, 0, 1), label=f"Rám {n} vzpěra")
        # the tie beam (an I across the hall, as high as the game's beam: the lamps hang from it) and the king post
        for y0, y1, w in ((23.0, 23.1, 0.4), (23.7, 23.8, 0.4), (23.1, 23.7, 0.04)):
            part.box((-38.0, y0, zf - w), (38.0, y1, zf + w), "steel", label=f"Rám {n} táhlo")
        part.box((-0.2, 23.8, zf - 0.2), (0.2, rafter_bottom(0.2) + 0.05, zf + 0.2), "steel", label=f"Rám {n} sloupek")
    # the purlins along the hall on the rafters
    for side in (-1, 1):
        down, up = Vector((side * C, -S, 0)), Vector((side * S, C, 0))
        for u in (1.0, 6.5, 12.0, 17.5, 23.0, 28.5, 34.0, 39.2):
            centre = roof_point(side, u, 0, -0.29)
            part.obox(centre, down * 0.1, up * 0.27, (0, 0, INNER_Z), "galv", "Vaznice")
    part.make()


def floor():
    """The concrete floor: one slab under the whole building, its top in 10 × 10 slabs of three shades with dark
    joints (colours only: the game's paint lies on it)."""
    part = Part("Podlaha", COLS["inside"])
    xs, zs = [-HX, HX], [-HZ, HZ]
    for i in range(1, 8):
        xs += [-HX + 10 * i - 0.05, -HX + 10 * i + 0.05]
    for j in range(1, 6):
        zs += [-HZ + 10 * j - 0.05, -HZ + 10 * j + 0.05]
    xs, zs = sorted(xs), sorted(zs)

    def shade(i, j):
        if i % 2 or j % 2:
            return "joint"
        return ("floor", "floor2", "floor3")[(i * 7 + j * 3 + (i * j) % 5) % 3]
    for i, (x0, x1) in enumerate(zip(xs, xs[1:])):
        for j, (z0, z1) in enumerate(zip(zs, zs[1:])):
            part.poly([(x0, FLOOR_TOP, z0), (x1, FLOOR_TOP, z0), (x1, FLOOR_TOP, z1), (x0, FLOOR_TOP, z1)], shade(i, j), (0, 1, 0))
    # the slab's edges, each the shade of the slab over it (so no shade's piece is flat: Roblox sizes a mesh by its box)
    last_i, last_j = len(xs) - 2, len(zs) - 2
    for i, (x0, x1) in enumerate(zip(xs, xs[1:])):
        for z, j, normal in ((-HZ, 0, (0, 0, -1)), (HZ, last_j, (0, 0, 1))):
            part.poly([(x0, 0, z), (x1, 0, z), (x1, FLOOR_TOP, z), (x0, FLOOR_TOP, z)], shade(i, j), normal)
    for j, (z0, z1) in enumerate(zip(zs, zs[1:])):
        for x, i, normal in ((-HX, 0, (-1, 0, 0)), (HX, last_i, (1, 0, 0))):
            part.poly([(x, 0, z0), (x, 0, z1), (x, FLOOR_TOP, z1), (x, FLOOR_TOP, z0)], shade(i, j), normal)
    part.note([(-HX, 0, -HZ), (HX, FLOOR_TOP, HZ)], "floor", "Podlaha")
    part.make()


def build():
    for key in list(COLS):
        COLS.pop(key)
    for name in [c.name for c in bpy.data.collections if c.name.startswith("Sklad")]:
        col = bpy.data.collections[name]
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(col)
    for name, kind in (("Cube", "MESH"), ("Light", "LIGHT"), ("Camera", "CAMERA")):
        o = bpy.data.objects.get(name)
        if o and o.type == kind:
            bpy.data.objects.remove(o, do_unlink=True)
    materials()
    for key, name in (("shell", "Sklad plášť"), ("roof", "Sklad střecha"), ("door", "Sklad vrata"), ("sign", "Sklad cedule"),
                      ("lights", "Sklad světla"), ("inside", "Sklad uvnitř")):
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
        COLS[key] = col
    shell()
    roof()
    door()
    lights()
    sign()
    frames()
    floor()


# ───────────────────────────────────────────────────────────── jen náhled: díly hry, okolí, kamery
def preview_scene():
    """What the game adds (only for the pictures, never exported): the stands, the UPGRADES desk, the signs it writes,
    the floor's paint, the lamps' glow discs; the plot, the meadow, a sky, the sun and two cameras."""
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    name = "Hra (jen náhled)"
    old = bpy.data.collections.get(name)
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(old)
    col = bpy.data.collections.new(name)
    sc.collection.children.link(col)
    P = {k: material("P " + k, *v) for k, v in {
        "grass": ("#7FA35A", 0.95), "pad": ("#B3B1AA", 0.9), "podium": ("#32353A", 0.6), "felt": ("#CAC4B8", 0.95),
        "paint": ("#F2C62A", 0.6), "board": ("#2A2D32", 0.5), "glow": ("#FFF4E0", 0.5, 0, 8.0), "screen": ("#F0842C", 0.4, 0, 2.0),
        "orange": ("#F0842C", 0.5), "white": ("#EEEEE8", 0.5, 0, 1.0), "grey": ("#B0B4BA", 0.5), "box": ("#C49E6C", 0.8),
    }.items()}
    keep = Part(name, col)
    keep.box((-75, -0.2, -80), (75, -0.001, 95), "grass")
    keep.box((-48, -0.1, -36), (48, 0.0, 70), "pad", skip=("-y",))
    # the stands (Config.Warehouse: 12, 4 a row, 10 × 10, an aisle of 5, the middle aisle 18, the receiving zone 9)
    for row in range(3):
        for x in (-29.0, -14.0, 14.0, 29.0):
            z = 10.0 - 15.0 * row
            keep.box((x - 5, FLOOR_TOP, z - 5), (x + 5, FLOOR_TOP + 0.9, z + 5), "podium")
            keep.box((x - 4.7, FLOOR_TOP + 0.9, z - 4.7), (x + 4.7, FLOOR_TOP + 1.0, z + 4.7), "felt")
    for x, z, sx, sy, sz in ((-29, 10, 3, 2.2, 2), (14, -5, 2.4, 3.4, 2.4), (29, -20, 4, 1.6, 3), (-14, -20, 2, 2.6, 2)):
        keep.box((x - sx / 2, 1.05, z - sz / 2), (x + sx / 2, 1.05 + sy, z + sz / 2), "box")
    # the floor's paint: the receiving zone and the middle aisle's lines
    y0, y1 = FLOOR_TOP, FLOOR_TOP + 0.04
    keep.box((-13, y0, 20.0), (13, y1, 20.4), "paint")
    keep.box((-13, y0, 28.6), (13, y1, 29.0), "paint")
    for side in (-1, 1):
        keep.box((side * 12.6, y0, 20), (side * 13, y1, 29), "paint")
        keep.box((side * 8.35, y0, -29), (side * 8.65, y1, 20), "paint")
    # the bay outside (UNLOAD HERE: 14 × 30 round the van's spot)
    for x0, x1, z0, z1 in ((-7, -6.5, 32, 62), (6.5, 7, 32, 62), (-7, 7, 32, 32.5), (-7, 7, 61.5, 62)):
        keep.box((x0, 0.0, z0), (x1, 0.06, z1), "paint")
    # the UPGRADES desk, its sign and the STOCK board on the back wall
    keep.box((-3.0, FLOOR_TOP, -29.0), (3.0, 3.05, -26.6), "board")
    keep.box((-3.2, 3.05, -29.0), (3.2, 3.25, -26.2), "grey")
    keep.box((-1.9, 4.1, -28.0), (1.9, 6.4, -27.7), "screen")
    keep.box((-6, 7.8, -29.0), (6, 10.2, -28.7), "board")
    keep.box((-11, 10.5, -29.0), (11, 16.5, -28.7), "board")
    # the owner's sign over the door
    keep.box((-12, 18.2, HZ + 0.3), (12, 21.8, HZ + 0.7), "board")
    for body, cy, h, z, finish in (("STOCK", 15.0, 1.6, -28.7, "orange"), ("YOUR NAME'S WAREHOUSE", 20.4, 1.4, HZ + 0.7, "white"),
                                   ("ZDC STORAGE · PLOT 1", 18.95, 0.55, HZ + 0.7, "orange"), ("UPGRADES", 9.0, 1.2, -28.7, "orange")):
        verts, tris = text_mesh(body, h, 20, 0.02)
        keep.mesh([(x, cy + y, z + 0.011 + zz) for x, y, zz in verts], tris, finish)  # (all read from the south side)
    # the lamps' glow discs (the game's: they stay, with their light)
    for z in LAMP_Z:
        for x in LAMP_X:
            keep.cyl((x, GLOW_TOP - 0.14, z), (x, GLOW_TOP, z), 1.3, "glow", seg=24)
    o = keep.make(P)
    del o["details"]
    # the hall's light for the picture (in the game: the glow discs' PointLights)
    for z in LAMP_Z:
        for x in LAMP_X:
            lamp = bpy.data.objects.new("Světlo lampy", bpy.data.lights.new("Světlo lampy", "POINT"))
            col.objects.link(lamp)
            lamp.data.energy, lamp.data.shadow_soft_size = 60000, 1.2
            lamp.data.color = (1.0, 0.93, 0.84)
            lamp.location = to_blender((x, GLOW_TOP - 0.6, z))
    world = sc.world or bpy.data.worlds.new("Sklad svět")
    sc.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*linear("#A9CBEA"), 1)
    bg.inputs["Strength"].default_value = 1.0
    sun = bpy.data.objects.new("Slunce", bpy.data.lights.new("Slunce", "SUN"))
    col.objects.link(sun)
    sun.data.energy, sun.data.angle = 3.6, math.radians(4)
    sun.rotation_euler = (-to_blender((-0.45, -1.0, -0.55)).normalized()).to_track_quat("Z", "Y").to_euler()
    for cam_name, eye, target, lens in (("Kamera venku", (78, 34, 92), (0, 11, 4), 32),
                                         ("Kamera uvnitř", (-6, 9.5, 27.5), (2, 9.0, -20), 16)):
        cam = bpy.data.objects.new(cam_name, bpy.data.cameras.new(cam_name))
        col.objects.link(cam)
        cam.location = to_blender(eye)
        cam.rotation_euler = (to_blender(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        cam.data.clip_end = 1000
    sc.camera = bpy.data.objects["Kamera venku"]
    sc.render.resolution_x, sc.render.resolution_y = 1200, 800
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass


def render_all(folder, samples=64, percent=100):
    sc = bpy.context.scene
    sc.render.resolution_percentage = percent
    sc.render.engine = "CYCLES"
    sc.cycles.samples, sc.cycles.use_denoising = samples, True
    sc.cycles.max_bounces = 6
    os.makedirs(folder, exist_ok=True)
    for name, file in (("Kamera venku", "warehouse-outside.png"), ("Kamera uvnitř", "warehouse-inside.png")):
        sc.camera = bpy.data.objects[name]
        sc.render.filepath = os.path.join(folder, file)
        bpy.ops.render.render(write_still=True)
    sc.camera = bpy.data.objects["Kamera venku"]


def sheet(folder, out):
    """warehouse-preview.png: the outside and the inside side by side (needs Pillow)."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("(bez Pillow: náhled se neskládá; pip install pillow)")
        return
    shots = [Image.open(os.path.join(folder, f)).convert("RGB") for f in ("warehouse-outside.png", "warehouse-inside.png")]
    w, h = shots[0].size
    canvas = Image.new("RGB", (2 * w + 30, h + 80), (26, 29, 33))
    draw = ImageDraw.Draw(canvas)

    def font(size):
        for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "C:/Windows/Fonts/arial.ttf"):
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
        return ImageFont.load_default()
    draw.rectangle((16, 16, 22, 54), fill=(240, 132, 44))
    draw.text((34, 14), f"ZDC WAREHOUSE · {W:g} × {H:g} × {D:g} · FROM BLENDER", font=font(30), fill=(236, 236, 236))
    for i, shot in enumerate(shots):
        canvas.paste(shot, (10 + i * (w + 10), 70))
    canvas.save(out)
    print("Náhled:", out)


# ───────────────────────────────────────────────────────────── export do hry
# Hra (Zombie Delivery): server/WarehouseMesh.luau najde v Roblox Studiu naimportovaný ZDCWarehouseArt.fbx a oblékne do
# něj sklad na každém pozemku. Díly se jmenují "warehouse_<povrch>" (povrch říká hře barvu a materiál; víc než 10 000
# trojúhelníků: "warehouse2_<povrch>" …). Značky WarehouseMark_o / _x / _y / _z ukazují hře, jak Roblox model při importu
# otočil a zvětšil (střed spodku skladu, 10 studů na východ, nahoru a na jih); _b je roh zdí (W / 2, H, D / 2) a _r
# hřeben: sklad, pro který je model udělaný. (Ne "mark_o": to hledají jiné modely, ať si je hra neplete.)
def game_axes(v):
    """Blender (x, y, z) → the game's (x east, y up, z south): (x, z, -y)."""
    return Vector((v.x, v.z, -v.y))


def split_by_finish(me, matrix, out):
    loops = len(me.loops)
    if not loops:
        return
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
        out.setdefault(names[k], []).append(piece)
    bm.free()


def bounds(points):
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return [round((a + b) / 2, 4) for a, b in zip(lo, hi)], [round(b - a, 4) for a, b in zip(lo, hi)]


def export_game(folder, budget=10000):
    """ZDCWarehouseArt.fbx and ZDCWarehouseArt.json for the game (NAVOD.md): the pieces by finish, the markers, every
    detail's box (the game's axes, from the building's bottom middle)."""
    os.makedirs(folder, exist_ok=True)
    temp = bpy.data.collections.new("Warehouse_Export")
    bpy.context.scene.collection.children.link(temp)
    dg = bpy.context.evaluated_depsgraph_get()
    pieces, details = {}, []
    for key in ("shell", "roof", "door", "sign", "lights", "inside"):
        for o in COLS[key].objects:
            if o.type != "MESH":
                continue
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            if not me.polygons:
                continue
            for d in json.loads(o.get("details", "[]")):
                centre = [round((a + b) / 2, 4) for a, b in zip(d["lo"], d["hi"])]
                size = [round(b - a, 4) for a, b in zip(d["lo"], d["hi"])]
                details.append({"name": d["name"], "finish": d["finish"], "center": centre, "size": size})
            split_by_finish(me, o.matrix_world.copy(), pieces)
    made = []
    manifest = {"box": [W, H, D], "ridge": RIDGE, "door": [DOOR_W, DOOR_H], "floorTop": FLOOR_TOP, "wall": WALL,
                "pieces": {}, "markers": {}, "details": details}
    for finish, meshes in sorted(pieces.items(), key=lambda kv: list(FINISHES).index(kv[0])):
        groups, tris = [[]], 0
        for piece in meshes:
            t = sum(len(p.vertices) - 2 for p in piece.polygons)
            if groups[-1] and tris + t > budget:
                groups.append([])
                tris = 0
            groups[-1].append(piece)
            tris += t
        for g, group in enumerate(groups):
            name = f"{PIECES}{'' if g == 0 else g + 1}_{finish}"
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
            centre, size = bounds([game_axes(v.co) for v in me.vertices])
            manifest["pieces"][name] = {"center": centre, "size": size, "triangles": sum(len(p.vertices) - 2 for p in me.polygons)}
    for piece_list in pieces.values():
        for piece in piece_list:
            bpy.data.meshes.remove(piece)
    marks = {"o": (0, 0, 0), "x": (10, 0, 0), "y": (0, 10, 0), "z": (0, 0, 10), "b": (HX, H, HZ), "r": (0, TOP, 0)}
    for key, at in marks.items():
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.3)
        bmesh.ops.translate(bm, vec=to_blender(at), verts=bm.verts)
        me = bpy.data.meshes.new(f"{MARK}_{key}")
        bm.to_mesh(me)
        bm.free()
        me.materials.append(M["trim"])
        o = bpy.data.objects.new(f"{MARK}_{key}", me)
        temp.objects.link(o)
        made.append(o)
        manifest["markers"][f"{MARK}_{key}"] = [float(c) for c in at]
    manifest["triangles"] = sum(p["triangles"] for p in manifest["pieces"].values())
    for o in bpy.context.scene.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.fbx(filepath=os.path.join(folder, "ZDCWarehouseArt.fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="OFF", use_mesh_modifiers=True)
    with open(os.path.join(folder, "ZDCWarehouseArt.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    for o in list(temp.objects):
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.meshes.remove(me)
    bpy.data.collections.remove(temp)
    return manifest


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag):
        return argv[argv.index(flag) + 1] if flag in argv else None

    build()
    preview_scene()
    source = globals().get("__file__", "")
    if os.path.isfile(source) and "warehouse.py" not in bpy.data.texts:
        bpy.data.texts.new("warehouse.py").write(open(source, encoding="utf-8").read())
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        manifest = export_game(folder)
        print(f"ZDCWarehouseArt: {len(manifest['pieces'])} pieces, {manifest['triangles']} triangles, the largest "
              f"{max(p['triangles'] for p in manifest['pieces'].values())}")
    if arg("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--save")), compress=True)
    if arg("--render"):
        render_all(arg("--render"), int(arg("--samples") or 64), int(arg("--percent") or 100))
        if arg("--sheet"):
            sheet(arg("--render"), arg("--sheet"))


main()
