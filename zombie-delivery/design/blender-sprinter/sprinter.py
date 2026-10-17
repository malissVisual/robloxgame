"""Zombie Delivery 8.0 SANDBOX: ZDC Sprinter (velká dodávka s vysokou střechou, do které se dá vejít) pro Blender.

Spuštění v Blenderu: nahoře záložka Scripting → Open → vyber sprinter.py → Run Script (▶, nebo Alt+P).
Skript postaví dodávku do kolekce "Sprinter". Když ho spustíš znovu, starou dodávku nejdřív smaže, takže si můžeš
v části NASTAVENÍ měnit barvy a nápisy a zkoušet. F12 = render, Home v 3D okně = ukaž celou dodávku.

Míry jsou ve studech přesně jako Sprinter ve hře: 8,0 široký, 10,4 vysoký, 22,0 dlouhý, rozvor 13,0, světlá výška 1,2;
nákladový prostor uvnitř 6,6 široký, 7,6 vysoký a 14,0 dlouhý, jeho podlaha 2,4 nad zemí; kabina = předních 7 studů.
1 jednotka v Blenderu = 1 stud. Předek míří na -Y (pohled zepředu = Numpad 1). Levý bok (řidič) je +X, pravý bok
(posuvné dveře) je -X. Zadní dveře BackDoorL / BackDoorR, posuvné SideDoor a dveře kabiny CabDoorL / CabDoorR jsou
samostatné objekty s počátkem v pantu (otoč je klávesou R Z), ať se dají otvírat.

Bez Blenderu, jen s modulem bpy (pip install bpy, Python 3.13):
    python sprinter.py -- --save sprinter.blend --export roblox --render složka --sheet sprinter-preview.png
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

# ───────────────────────────────────────────────────────────── NASTAVENÍ (změň a spusť znovu)
PAINT = "#D9CCB0"      # lak karoserie (béžová Deliveros, jako ZDC Van)
STRIPE = "#B3261E"     # pruhy a logo
TRIM = "#202326"       # černé plasty: nárazníky, lemy blatníků, lišty, kliky, zrcátka
RIM = "#B9BDC1"        # disky kol
GLASS = "#16212A"      # okna
PLYWOOD = "#B8996C"    # překližka na stěnách nákladového prostoru
LOGO, NAME, SLOGAN = "DELIVEROS", "MOVING & STORAGE", "MOVE · FIND · GROW"   # (8.9: the game is Deliveros, not ZDC)
BADGE = "D"            # písmeno ve znaku na masce
PLATE = "DLV 08"       # SPZ
EXPORT = False         # True = po postavení uloží FBX pro Roblox do složky "roblox" vedle uloženého .blend souboru

# ───────────────────────────────────────────────────────────── míry ze hry (NEMĚŇ: hra má stejná čísla)
# Sprinter ve hře (Config.Sprinter, STYLES.sprinter) má stejné rozměry: díly, kolize i tenhle model musí sedět.
LENGTH, WIDTH, HEIGHT = 22.0, 8.0, 10.4    # celkem: délka, šířka (bez zrcátek), výška střechy
WHEELBASE, CLEARANCE = 13.0, 1.2           # rozvor, světlá výška (spodek karoserie)
CAB = 7.0                                  # kabina = předních 7 studů
BAY_WIDTH, BAY_HEIGHT, BAY_LENGTH = 6.6, 7.6, 14.0   # nákladový prostor uvnitř
FLOOR = 2.4                                # podlaha nákladového prostoru (a kabiny) nad zemí
WHEEL, TRACK = 1.2, 3.45                   # poloměr kola, střed kola od osy auta

# ───────────────────────────────────────────────────────────── odvozené míry
F, R = -LENGTH / 2, LENGTH / 2       # předek (přední nárazník) a záď (zadní dveře a nárazník)
CAB_WALL = F + CAB                   # -4.0: zadní stěna kabiny
BAY_FRONT = CAB_WALL + 1.0           # -3.0: nákladový prostor začíná 1 stud za ní (přepážka)
BAY_BACK = BAY_FRONT + BAY_LENGTH    # 11.0: běží až k zadním dveřím
BAY_X = BAY_WIDTH / 2                # 3.3: stěny prostoru (líc překližky)
CEIL = FLOOR + BAY_HEIGHT            # 10.0: strop prostoru
LINING = 0.12                        # tloušťka překližky
HOLLOW = BAY_X + LINING              # 3.42: plech za překližkou
CAB_HOLLOW = 3.45                    # vnitřek kabiny (do stran)
AXLE_F, AXLE_R = -WHEELBASE / 2, WHEELBASE / 2
SIDE = WIDTH / 2 - 0.1               # 3.9: bok karoserie; lišty a lemy podběhů sahají na WIDTH / 2
BELT = 5.2                           # linie oken: nad ní se boky naklání dovnitř
TUMBLE = 0.052                       # o kolik se bok nakloní na 1 stud výšky
ARCH = WHEEL + 0.35                  # poloměr podběhu
GAP = 0.03                           # polovina spáry kolem dveří
RIGHT, LEFT = -1, 1                  # pravý bok je v Blenderu -X (posuvné dveře), levý +X (řidič)

# Čelní sklo (y, z): spodek a vršek. Dveře kabiny: přední hrana svisle do KNEE, pak podél sloupku A.
WIND_BASE, WIND_TOP = (-9.0, 4.95), (-7.2, 9.3)
RAKE = (WIND_TOP[0] - WIND_BASE[0]) / (WIND_TOP[1] - WIND_BASE[1])
CAB_DOOR_FRONT, CAB_DOOR_BACK, CAB_DOOR_BOTTOM, CAB_DOOR_TOP, CAB_KNEE = -8.55, -4.15, 2.98, 9.1, 4.22
# Posuvné dveře vpravo (y od, do; z spodek, vršek) a o kolik vyjedou ven a dozadu.
SLIDE_FRONT, SLIDE_BACK, SLIDE_BOTTOM, SLIDE_TOP = -2.85, 2.35, 1.97, 9.55
SLIDE_OUT, SLIDE_TRAVEL = 0.35, 5.0
# Zadní dveře: panty na ±BACK_HINGE, spodek (těsně nad podlahou), vršek, zaoblení horního rohu, tloušťka.
BACK_HINGE, BACK_BOTTOM, BACK_TOP, BACK_ROUND, BACK_THICK = 3.6, FLOOR + 0.02, 10.05, 0.35, 0.2
BACK_IN = R - BACK_THICK             # 10.8: vnitřní líc zavřených zadních dveří
FACE = R - 0.01                      # vnější líc zadních dveří (nápisy na nich nevystoupí za záď)
SEAT_X, SEAT_Y, SEAT_TOP = 1.7, -5.75, 3.9   # sedadla: do strany, kde, horní plocha sedáku

# Obrys karoserie: řezy podél auta (y, vršek, poloviční šířka, spodek, poloměr horních hran).
STATIONS = [
    (-10.65, 3.70, 3.10, 1.35, 0.45),   # čelo s maskou
    (-10.58, 4.00, 3.35, 1.28, 0.50),
    (-10.42, 4.22, 3.58, 1.22, 0.55),
    (-10.15, 4.38, 3.75, 1.20, 0.60),
    (-9.75, 4.56, 3.86, 1.20, 0.60),
    (-9.35, 4.76, 3.90, 1.20, 0.60),
    (WIND_BASE[0], WIND_BASE[1], 3.90, 1.20, 0.55),      # spodek čelního skla
    (-8.10, 7.125, 3.90, 1.20, 0.50),
    (WIND_TOP[0], WIND_TOP[1], 3.90, 1.20, 0.50),        # vršek čelního skla
    (-6.85, 9.78, 3.90, 1.20, 0.55),
    (-6.35, 10.12, 3.90, 1.20, 0.60),
    (-5.70, 10.33, 3.90, 1.20, 0.60),
    (-5.00, HEIGHT, 3.90, 1.20, 0.60),                   # vysoká střecha
    (10.75, HEIGHT, 3.90, 1.20, 0.60),
    (10.90, 10.36, 3.87, 1.20, 0.60),
    (10.97, 10.30, 3.82, 1.20, 0.58),
    (R, 10.22, 3.74, 1.20, 0.55),                        # záď
]
SHELL_FRONT = STATIONS[0][0]

M = {}        # materiály
COLS = {}     # kolekce
CUT = None    # kolekce řezů karoserie (okna, dveře, dutý vnitřek: modifikátor Boolean na objektu Body)
SHELL = None  # síť karoserie bez řezů (z ní jsou i dveře a lampy)


def linear(hexcode):
    """#RRGGBB (jak ho znáš z malování) → lineární barva, se kterou počítá Blender."""
    h = hexcode.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, color, rough=0.5, metal=0.0, coat=0.0, emit=0.0, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    rgba = (*linear(color), 1.0)
    m.diffuse_color, m.roughness, m.metallic = rgba, rough, metal   # barvy v pohledu Solid
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    p.inputs["Base Color"].default_value = rgba
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if "Coat Weight" in p.inputs:
        p.inputs["Coat Weight"].default_value = coat
    glow = p.inputs.get("Emission Color") or p.inputs.get("Emission")
    glow.default_value = rgba if emit else (0, 0, 0, 1)
    p.inputs["Emission Strength"].default_value = emit
    p.inputs["Alpha"].default_value = alpha
    m["palette"] = color
    return m


def materials():
    M.update(
        paint=material("Sprinter Paint", PAINT, 0.36, coat=0.4),
        stripe=material("Sprinter Stripe", STRIPE, 0.4, coat=0.35),
        trim=material("Sprinter Trim", TRIM, 0.6),
        rubber=material("Sprinter Rubber", "#111213", 0.85),
        glass=material("Sprinter Glass", GLASS, 0.04, coat=1.0, alpha=0.55),
        chrome=material("Sprinter Chrome", "#D5D9DD", 0.15, metal=1.0),
        rim=material("Sprinter Rim", RIM, 0.35, metal=0.6),
        under=material("Sprinter Underbody", "#2A2C2E", 0.9),
        plate=material("Sprinter Plate", "#F1EFE6", 0.45),
        head=material("Sprinter Headlight", "#FFF4DC", 0.2, emit=3.0),
        amber=material("Sprinter Indicator", "#FF8A10", 0.3, emit=1.0),
        red=material("Sprinter Taillight", "#D0140F", 0.3, emit=1.0),
        inside=material("Sprinter Inside", "#2B2D31", 0.8),
        seat=material("Sprinter Seat", "#3A3C40", 0.9),
        ply=material("Sprinter Plywood", PLYWOOD, 0.75),
        floor=material("Sprinter Floor", "#4A3A2C", 0.7),
        rail=material("Sprinter Rail", "#A9AEB3", 0.35, metal=0.8),
        inner=material("Sprinter Inner", "#C9C4B8", 0.6),
        lamp=material("Sprinter Ceiling Light", "#FFF6E2", 0.2, emit=6.0),
        studio=material("Sprinter Studio Floor", "#41464C", 0.85),
    )


# ───────────────────────────────────────────────────────────── pomocníci
def collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def clear_previous():
    """Smaže dodávku z minulého spuštění (kolekce Sprinter) a startovní kostku, světlo a kameru Blenderu."""
    root = bpy.data.collections.get("Sprinter")
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
    for pool in (bpy.data.meshes, bpy.data.curves, bpy.data.lights, bpy.data.cameras):
        for block in list(pool):
            if block.users == 0:
                pool.remove(block)


def sharpen(bm, degrees=45):
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(degrees):
            e.smooth = False


def mesh_object(name, bm, mats, col, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = smooth
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    return o


def bevel(o, width, segments=2, angle=40):
    """Modifikátor Bevel: zakulatí hrany (změň Amount/Segments v panelu Modifiers)."""
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width, b.segments = width, segments
    b.limit_method, b.angle_limit = "ANGLE", math.radians(angle)
    b.harden_normals, b.use_clamp_overlap = True, True
    return b


def place(at):
    return at if isinstance(at, Matrix) else Matrix.Translation(Vector(at))


def frame(center, x, z):
    """Matice s osou x a z (y dopočítá), aby díl ležel na šikmé ploše."""
    x, z = Vector(x).normalized(), Vector(z).normalized()
    m = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    m.translation = Vector(center)
    return m


def box(name, size, at, mat, col, round=0.04):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    o = mesh_object(name, bm, [mat], col, smooth=bool(round))
    o.matrix_world = place(at)
    if round:
        bevel(o, round)
    return o


def span_box(name, lo, hi, mat, col, round=0.0):
    """Kvádr mezi dvěma protějšími rohy."""
    lo, hi = Vector(map(min, lo, hi)), Vector(map(max, lo, hi))
    return box(name, hi - lo, (lo + hi) / 2, mat, col, round)


def tube(name, a, b, r, mat, col, seg=12):
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=(b - a).length)
    sharpen(bm)
    o = mesh_object(name, bm, [mat], col)
    o.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat("Z", "Y").to_matrix().to_4x4()
    return o


def disc(name, center, axis, r, depth, mat, col, seg=18):
    c, d = Vector(center), Vector(axis).normalized() * depth / 2
    return tube(name, c - d, c + d, r, mat, col, seg)


def prism(name, outline, to3d, out, back, front, mat, col, smooth=False):
    """Plochý tvar (`outline` 2D) položený na plochu funkcí `to3d`, vysunutý podél `out` od `back` do `front`."""
    out = Vector(out)
    bm = bmesh.new()
    top = [bm.verts.new(to3d(p) + out * front) for p in outline]
    bottom = [bm.verts.new(to3d(p) + out * back) for p in outline]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[i], bottom[i], bottom[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, [mat], col, smooth)


def cutter(name, outline, to3d, out, back, front, mat):
    """Řez do karoserie (okno, spára, dutý vnitřek): kolekce Sprinter_Cutters, Boolean na objektu Body."""
    o = prism(name, outline, to3d, out, back, front, mat, CUT)
    o.display_type, o.hide_render = "WIRE", True
    return o


def volume(name, outline, to3d, out, back, front):
    """Pomocný objem (schovaný): z karoserie z něj vznikají dveře a lampy."""
    o = prism(name, outline, to3d, out, back, front, M["inside"], COLS["Volumes"])
    o.display_type, o.hide_render = "WIRE", True
    return o


def rounded(x0, z0, x1, z1, r, seg=4):
    """Obdélník se zaoblenými rohy (2D obrys)."""
    pts = []
    for cx, cz, a0 in ((x1 - r, z0 + r, -90), (x1 - r, z1 - r, 0), (x0 + r, z1 - r, 90), (x0 + r, z0 + r, 180)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def text(name, body, size, matrix, mat, col, lift=0.006, fit=None):
    """Nápis převedený na plochou síť (nízké rozlišení, ať má model v Robloxu málo trojúhelníků). fit: nejvýš tak
    široký (studů); delší nápis se celý zmenší."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body, cu.size, cu.align_x, cu.align_y = body, size, "CENTER", "CENTER"
    cu.resolution_u, cu.offset = 2, size * 0.025
    tmp = bpy.data.objects.new(name, cu)
    col.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    xs = [v.co.x for v in me.vertices]
    if fit and xs and max(xs) - min(xs) > fit:
        me.transform(Matrix.Scale(fit / (max(xs) - min(xs)), 4))
    me.materials.clear()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    o.matrix_world = matrix @ Matrix.Translation((0, 0, lift))
    return o


def bake(o):
    """Použije modifikátory objektu (Boolean, Bevel …): zůstane obyčejná síť."""
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = o.data
    o.modifiers.clear()
    o.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return o


def attach(child, parent):
    """Přidělá díl k dveřím (otáčí se s nimi), na místě, kde je."""
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_basis.inverted()   # (dveře jsou nahoře: basis = svět, i před přepočtem scény)


def half_width(z, hw=SIDE):
    return hw - TUMBLE * max(0.0, z - BELT)


def side_point(side, y, z):
    return Vector((side * half_width(z), y, z))


def side_normal(side, upper):
    t = math.atan(TUMBLE)
    return Vector((side * math.cos(t), 0, math.sin(t))) if upper else Vector((side, 0, 0))


def side_frame(side, y, z, lift=0.0):
    """Matice pro díl na boku: x po směru čtení (zleva doprava při pohledu na bok), z ven z auta."""
    out = side_normal(side, z > BELT)
    return frame(side_point(side, y, z) + out * lift, (0, side, 0), out)


def top_at(y):
    """Výška vršku karoserie v místě y (kapota, čelní sklo, střecha)."""
    for (y0, z0, *_), (y1, z1, *_) in zip(STATIONS, STATIONS[1:]):
        if y0 <= y <= y1:
            return z0 + (z1 - z0) * (y - y0) / (y1 - y0)
    return STATIONS[-1][1]


def cab_front(z):
    """Přední hrana dveří kabiny (y) ve výšce z: svisle do KNEE, pak podél sloupku A."""
    return CAB_DOOR_FRONT if z <= CAB_KNEE else CAB_DOOR_FRONT + (z - CAB_KNEE) * RAKE


# ───────────────────────────────────────────────────────────── karoserie
def ring(station):
    """Jeden řez karoserií (x, z): spodek, bok (nad linií oken nakloněný), zaoblená hrana, vršek."""
    y, zt, hw, zb, rt = station
    rb = 0.18
    side_top = zt - rt
    belt = BELT if side_top > BELT + 0.05 else (zb + rb + side_top) / 2
    hw_top = hw - TUMBLE * max(0.0, side_top - BELT)
    half = []
    for a in (-90, -45, 0):
        r = math.radians(a)
        half.append((hw - rb + rb * math.cos(r), zb + rb + rb * math.sin(r)))
    half.append((hw, belt))
    for k in range(6):
        a = math.radians(90 * k / 5)
        half.append((hw_top - rt + rt * math.cos(a), side_top + rt * math.sin(a)))
    pts = [(0.0, zb)] + half + [(0.0, zt)] + [(-x, z) for x, z in reversed(half)]
    return [Vector((x, y, z)) for x, z in pts]


def shell_mesh():
    """Karoserie jako jedno těleso: řezy STATIONS spojené k sobě, čelo a záď zavřené. Spodek je tmavý."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in ring(s)] for s in STATIONS]
    for a, b in zip(rings, rings[1:]):
        n = len(a)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.material_index = 1 if f.normal.z < -0.7 else 0
    sharpen(bm, 40)
    me = bpy.data.meshes.new("Sprinter shell")
    bm.to_mesh(me)
    bm.free()
    for m in (M["paint"], M["under"]):
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    return me


def shell_modifiers(o):
    bevel(o, 0.05, 2, 35)


def finish_normals(o):
    wn = o.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.mode, wn.weight, wn.keep_sharp = "FACE_AREA", 80, True


def from_shell(name, col, operands, at=None, keep=None):
    """Díl karoserie: průnik karoserie s objemem `keep` (dveře, lampa) bez řezů `operands`, s počátkem v `at`."""
    me = SHELL.copy()
    me.name = name
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    shell_modifiers(o)
    if keep is not None:
        b = o.modifiers.new("Keep", "BOOLEAN")
        b.operation, b.solver, b.object, b.material_mode = "INTERSECT", "EXACT", keep, "TRANSFER"
    for k, c in enumerate(operands):
        b = o.modifiers.new(f"Cut {k}", "BOOLEAN")
        b.operation, b.solver, b.object, b.material_mode = "DIFFERENCE", "EXACT", c, "TRANSFER"
    finish_normals(o)
    bake(o)
    if at is not None:
        at = Vector(at)
        o.data.transform(Matrix.Translation(-at))
        o.location = at
    return o


def skin(name, keep, mat, col, thick=0.05):
    """Lampa, která sedí na karoserii: kus jejího povrchu uvnitř objemu `keep`, vystouplý o `thick`."""
    me = SHELL.copy()
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    s = o.modifiers.new("Skin", "SOLIDIFY")
    s.thickness, s.offset, s.use_even_offset = thick, 1.0, True
    b = o.modifiers.new("Keep", "BOOLEAN")
    b.operation, b.solver, b.object = "INTERSECT", "EXACT", keep
    bake(o)
    o.data.materials.clear()
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.material_index = 0
    return o


def cab_outline(m):
    """Obrys dveří kabiny z boku (y, z), m > 0 o tolik větší (otvor v karoserii), m < 0 menší (dveře)."""
    top_front = cab_front(CAB_DOOR_TOP)
    return [(CAB_DOOR_FRONT - m, CAB_DOOR_BOTTOM - m), (CAB_DOOR_BACK + m, CAB_DOOR_BOTTOM - m),
            (CAB_DOOR_BACK + m, CAB_DOOR_TOP + m), (top_front - m, CAB_DOOR_TOP + m), (CAB_DOOR_FRONT - m, CAB_KNEE)]


def slide_outline(m):
    return rounded(SLIDE_FRONT - m, SLIDE_BOTTOM - m, SLIDE_BACK + m, SLIDE_TOP + m, 0.28)


def back_outline(m, inner=None):
    """Zadní dveře z pohledu zezadu (x, z). inner None: otvor pro obě křídla, jinak jedno křídlo (x > 0) od `inner`.
    Vnější hrana se nad linií oken naklání jako boky, horní vnější roh je zaoblený."""
    outer, bottom, top, r = BACK_HINGE + m, BACK_BOTTOM - m, BACK_TOP + m, BACK_ROUND + m
    lean = lambda z: outer - TUMBLE * max(0.0, z - BELT)
    half = [(lean(bottom), bottom), (lean(BELT), BELT)]
    cx, cz = lean(top - r) - r, top - r
    for k in range(6):
        a = math.radians(90 * k / 5)
        half.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    if inner is not None:
        return half + [(inner, top), (inner, bottom)]
    return half + [(-x, z) for x, z in reversed(half)]


def window_outline():
    """Okno dveří kabiny (y, z): dole vpředu malý zub dolů (jako Sprinter), vpředu podél sloupku A."""
    y5 = cab_front(5.0)
    return [(y5 + 0.3, 5.0), (y5 + 1.05, 5.0), (y5 + 1.45, 5.5), (CAB_DOOR_BACK - 0.3, 5.5), (CAB_DOOR_BACK - 0.3, 8.8),
            (cab_front(8.8) + 0.3, 8.8)]


def windscreen_point(q, lift=0.0):
    """Bod na čelním skle: q = (x, s), s = 0 dole … 1 nahoře."""
    (y0, z0), (y1, z1) = WIND_BASE, WIND_TOP
    n = Vector((0, -(z1 - z0), y1 - y0)).normalized()
    return Vector((q[0], y0 + (y1 - y0) * q[1], z0 + (z1 - z0) * q[1])) + n * lift


def windscreen_normal():
    (y0, z0), (y1, z1) = WIND_BASE, WIND_TOP
    return Vector((0, -(z1 - z0), y1 - y0)).normalized()


def windscreen_outline():
    pts = []
    for (x0, s0), (x1, s1) in (((-3.0, 0.06), (3.0, 0.06)), ((2.82, 0.95), (-2.82, 0.95))):
        pts += [(x0, s0), (x1, s1)]
    return pts


def hood_point(q):
    return Vector((q[0], q[1], top_at(q[1])))


def seam(name, a, b, to3d, out, w=0.05, depth=0.05):
    """Tenká spára (žlábek) podél úsečky a → b."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    p, e = Vector((-d.y, d.x)) * w / 2, d * w / 2
    cutter(name, [a - e - p, b + e - p, b + e + p, a - e + p], to3d, out, -depth, depth, M["rubber"])


def cutters():
    """Všechno, co se z karoserie vyřízne: dutá kabina a nákladový prostor, otvory pro dveře, okna, podběhy, maska."""
    across = lambda q: Vector((0, q[0], q[1]))
    # Nákladový prostor: od přepážky dozadu skrz záď (tam ho zavřou zadní dveře), horní rohy zaoblené.
    bay = [(-HOLLOW, FLOOR - 0.1), (HOLLOW, FLOOR - 0.1)]
    for cx, a0 in ((HOLLOW - 0.5, 0), (-HOLLOW + 0.5, 90)):
        bay += [(cx + 0.5 * math.cos(math.radians(a0 + 15 * k)), CEIL - 0.5 + 0.5 * math.sin(math.radians(a0 + 15 * k))) for k in range(7)]
    cutter("Cargo bay", bay, lambda q: Vector((q[0], 0, q[1])), (0, 1, 0), BAY_FRONT - LINING, R + 0.6, M["inner"])
    # Kabina: pod čelním sklem a střechou, vzadu stěna kabiny.
    n = Vector((0.924, -0.382)) * 0.3   # 0,3 dovnitř od čelního skla
    cab = [(-8.9, FLOOR), (CAB_WALL, FLOOR), (CAB_WALL, CEIL), (-5.4, CEIL), (-6.0, CEIL - 0.05), (-6.6, CEIL - 0.25),
           (WIND_TOP[0] + n.x, WIND_TOP[1] + n.y), (WIND_BASE[0] + n.x, WIND_BASE[1] + n.y), (-8.9, 4.6)]
    cutter("Cab", cab, across, (1, 0, 0), -CAB_HOLLOW, CAB_HOLLOW, M["inside"])
    # Otvory pro dveře (o spáru větší než dveře).
    for s in (LEFT, RIGHT):
        cutter("Cab door opening", cab_outline(GAP), across, (1, 0, 0), s * 3.40, s * 4.6, M["inside"])
    cutter("Sliding door opening", slide_outline(GAP), across, (1, 0, 0), RIGHT * 3.38, RIGHT * 4.6, M["inside"])
    cutter("Back door opening", back_outline(GAP), lambda q: Vector((q[0], 0, q[1])), (0, 1, 0), BACK_IN - 0.02, R + 0.6,
           M["rubber"])
    # Čelní sklo (skrz do kabiny; sklo je samostatný díl).
    cutter("Windscreen", rounded(-2.98, 0.06, 2.98, 0.95, 0.06, 2), windscreen_point, windscreen_normal(), -0.7, 0.3,
           M["rubber"])
    # Podběhy kol: válce jen vně stěn (dovnitř nákladového prostoru nesahají).
    for ya in (AXLE_F, AXLE_R):
        for s in (LEFT, RIGHT):
            arch = [(ARCH * math.cos(2 * math.pi * k / 32), ARCH * math.sin(2 * math.pi * k / 32)) for k in range(32)]
            cutter("Wheel arch", arch, lambda q, ya=ya: Vector((0, ya + q[0], WHEEL + q[1])), (1, 0, 0), s * 3.47, s * 4.6,
                   M["under"])
    # Maska chladiče (mělká), spáry kapoty, zadní světla zapuštěná do sloupků (nevystoupí za záď).
    front = lambda q: Vector((q[0], SHELL_FRONT, q[1]))
    cutter("Grille", rounded(-1.85, 2.5, 1.85, 3.5, 0.15), front, (0, -1, 0), -0.15, 0.3, M["trim"])
    for x in (-3.0, 3.0):
        seam("Hood seam", (x, -10.25), (x, -9.12), hood_point, (0, 0, 1))
    back = lambda q: Vector((q[0], R, q[1]))
    for s in (LEFT, RIGHT):
        x0, x1 = sorted((s * (BACK_HINGE + 0.06), s * 3.95))
        cutter("Tail light", rounded(x0, 3.3, x1, 5.7, 0.06, 2), back, (0, 1, 0), -0.035, 0.4, M["red"])
        cutter("Rear indicator", rounded(x0, 2.6, x1, 3.22, 0.06, 2), back, (0, 1, 0), -0.035, 0.4, M["amber"])
    cutter("Third brake light", rounded(-0.6, 10.09, 0.6, 10.17, 0.03, 1), back, (0, 1, 0), -0.03, 0.4, M["red"])


def body(col):
    """Karoserie Body: těleso s modifikátory Bevel (zaoblení), Boolean (řezy z kolekce Sprinter_Cutters), WeightedNormal."""
    o = bpy.data.objects.new("Body", SHELL)
    col.objects.link(o)
    shell_modifiers(o)
    cut = o.modifiers.new("Okna, dvere a vnitrek", "BOOLEAN")
    cut.operation, cut.operand_type, cut.collection, cut.solver = "DIFFERENCE", "COLLECTION", CUT, "EXACT"
    cut.material_mode = "TRANSFER"
    finish_normals(o)
    return o


def arch_flare(name, side, ya, col):
    """Plastový lem podběhu (sahá na WIDTH / 2)."""
    a0, n = math.asin((CLEARANCE - WHEEL) / ARCH), 18
    bm = bmesh.new()
    rings = []
    for k in range(n + 1):
        a = a0 + (math.pi - 2 * a0) * k / n
        rings.append([bm.verts.new((side * x, ya + r * math.cos(a), WHEEL + r * math.sin(a)))
                      for x, r in ((SIDE - 0.08, ARCH - 0.03), (SIDE - 0.08, ARCH + 0.2), (WIDTH / 2, ARCH + 0.2), (WIDTH / 2 - 0.02, ARCH - 0.03))])
    for k in range(n):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_object(name, bm, [M["trim"]], col)
    bevel(o, 0.03)
    return o


def band(name, side, y0, y1, z0, z1, mat, col, front=None, back=None):
    """Pruh na boku (pod linií oken svislý) od y0 do y1; front / back: šikmá hrana (y podle výšky z)."""
    f = front or (lambda z: y0)
    b = back or (lambda z: y1)
    outline = [(f(z0), z0), (b(z0), z0), (b(z1), z1), (f(z1), z1)]
    return prism(name, outline, lambda q: side_point(side, q[0], q[1]), side_normal(side, (z0 + z1) / 2 > BELT), -0.01, 0.012,
                 mat, col)


def side_bands(side, z0, z1, mat, name, y0, y1, groups):
    """Pruh podél celého boku rozdělený na spárách dveří: díly na dveřích patří dveřím."""
    gaps = [(lambda z: cab_front(z) - GAP, lambda z: cab_front(z) + GAP, "cab"), (lambda z: CAB_DOOR_BACK - GAP, lambda z: CAB_DOOR_BACK + GAP, None)]
    if side == RIGHT:
        gaps += [(lambda z: SLIDE_FRONT - GAP, lambda z: SLIDE_FRONT + GAP, "slide"), (lambda z: SLIDE_BACK - GAP, lambda z: SLIDE_BACK + GAP, None)]
    pieces, start, owner = [], (lambda z: y0), None
    for stop, resume, nxt in gaps:
        pieces.append((start, stop, owner))
        start, owner = resume, nxt
    pieces.append((start, lambda z: y1, owner))
    return [band(name, side, 0, 0, z0, z1, mat, groups[owner], front=f, back=b) for f, b, owner in pieces]


# ───────────────────────────────────────────────────────────── dveře
def cab_doors():
    """Dveře kabiny: vyříznuté z karoserie, okno, klika, zrcátko. Počátek = pant na přední hraně."""
    across = lambda q: Vector((0, q[0], q[1]))
    doors = {}
    for s, name in ((LEFT, "CabDoorL"), (RIGHT, "CabDoorR")):
        col = COLS[name]
        keep = volume(f"{name} volume", cab_outline(-GAP), across, (1, 0, 0), s * 3.43, s * 4.6)
        win = volume(f"{name} window", window_outline(), across, (1, 0, 0), s * 3.0, s * 4.6)
        hinge = Vector((s * SIDE, CAB_DOOR_FRONT, (CAB_DOOR_BOTTOM + CAB_KNEE) / 2))
        door = from_shell(name, col, [bpy.data.objects["Cab"], win], hinge, keep)
        glass = prism("Door glass", window_outline(), lambda q, s=s: side_point(s, q[0], q[1]), side_normal(s, True), -0.16, -0.12,
                      M["glass"], col)
        handle = box("Door handle", (0.13, 0.55, 0.06), side_frame(s, CAB_DOOR_BACK - 0.6, 4.55, 0.035) @ Matrix.Rotation(math.pi / 2, 4, "Z"),
                     M["trim"], col, 0.03)
        arm = tube("Mirror arm", (s * 3.72, -7.7, 6.35), (s * 4.32, -7.95, 6.5), 0.07, M["trim"], col)
        head = box("Mirror", (0.26, 0.55, 1.55), (s * 4.42, -8.0, 7.05), M["trim"], col, 0.08)
        mirror = box("Mirror glass", (0.17, 0.02, 1.35), (s * 4.42, -7.72, 7.05), M["chrome"], col, 0)
        for part in (glass, handle, arm, head, mirror):
            attach(part, door)
        doors[name] = door
    return doors


def sliding_door():
    """Posuvné dveře vpravo: vyříznuté z karoserie, uvnitř překližka a lišta na upínání. Počátek = přední hrana."""
    col = COLS["SideDoor"]
    across = lambda q: Vector((0, q[0], q[1]))
    keep = volume("SideDoor volume", slide_outline(-GAP), across, (1, 0, 0), RIGHT * 3.40, RIGHT * 4.6)
    pivot = Vector((RIGHT * SIDE, SLIDE_FRONT, (SLIDE_BOTTOM + SLIDE_TOP) / 2))
    door = from_shell("SideDoor", col, [bpy.data.objects["Cargo bay"]], pivot, keep)
    parts = [
        span_box("Door lining", (-HOLLOW, SLIDE_FRONT + 0.1, FLOOR + 0.05), (-BAY_X, SLIDE_BACK - 0.1, 7.4), M["ply"], col),
        span_box("Door rail", (-BAY_X, SLIDE_FRONT + 0.15, 4.22), (-BAY_X + 0.06, SLIDE_BACK - 0.15, 4.38), M["rail"], col),
        span_box("Door rail", (-BAY_X, SLIDE_FRONT + 0.15, 6.82), (-BAY_X + 0.06, SLIDE_BACK - 0.15, 6.98), M["rail"], col),
        span_box("Door pull", (-BAY_X, SLIDE_FRONT + 0.35, 4.9), (-BAY_X + 0.1, SLIDE_FRONT + 0.6, 5.9), M["trim"], col),
        box("Sliding door handle", (0.13, 0.55, 0.06), side_frame(RIGHT, SLIDE_FRONT + 0.65, 4.55, 0.035) @ Matrix.Rotation(math.pi / 2, 4, "Z"),
            M["trim"], col, 0.03),
    ]
    for part in parts:
        attach(part, door)
    return door


def back_doors():
    """Zadní dveře: dvě křídla s okny, uvnitř překližka. Počátek = pant na vnější hraně."""
    doors = {}
    for s, name in ((LEFT, "BackDoorL"), (RIGHT, "BackDoorR")):
        col = COLS[name]
        to3d = lambda q, s=s: Vector((s * q[0], 0, q[1]))
        leaf = prism(name, back_outline(0.0, 0.02), to3d, (0, 1, 0), BACK_IN, FACE, M["paint"], col, smooth=True)
        bevel(leaf, 0.035, 2, 50)
        win = volume(f"{name} window", rounded(0.35, 7.25, 3.12, 9.55, 0.2), to3d, (0, 1, 0), BACK_IN - 0.2, R + 0.2)
        handle_cut = volume(f"{name} handle recess", rounded(0.3, 5.0, 1.0, 5.35, 0.08, 2), to3d, (0, 1, 0), FACE - 0.04, R + 0.2) if s == RIGHT else None
        for k, c in enumerate(c for c in (win, handle_cut) if c):
            b = leaf.modifiers.new(f"Cut {k}", "BOOLEAN")
            b.operation, b.solver, b.object = "DIFFERENCE", "EXACT", c
        finish_normals(leaf)
        bake(leaf)
        for p in leaf.data.polygons:
            p.use_smooth = True
        hinge = Vector((s * BACK_HINGE, R, (BACK_BOTTOM + BACK_TOP) / 2))
        leaf.data.transform(Matrix.Translation(-hinge))
        leaf.location = hinge
        parts = [
            prism("Rear glass", rounded(0.37, 7.27, 3.10, 9.53, 0.19), to3d, (0, 1, 0), R - 0.13, R - 0.1, M["glass"], col),
            span_box("Door lining", (s * 0.2, BACK_IN - 0.05, 2.6), (s * 3.3, BACK_IN, 6.9), M["ply"], col),
            span_box("Door bar", (s * 0.25, BACK_IN - 0.08, 6.95), (s * 3.25, BACK_IN, 7.1), M["rail"], col),
        ]
        if s == RIGHT:
            parts.append(span_box("Rear door handle", (s * 0.4, FACE - 0.03, 5.12), (s * 0.9, FACE - 0.01, 5.24), M["chrome"], col))
            parts.append(span_box("Inner handle", (s * 0.35, BACK_IN - 0.12, 5.0), (s * 0.9, BACK_IN - 0.05, 5.35), M["trim"], col))
        # Pruhy a nápisy přes záď.
        for z0, z1 in ((4.35, 4.75), (4.88, 4.98)):
            parts.append(prism("Stripe", [(0.1, z0), (3.45, z0), (3.45, z1), (0.1, z1)], to3d, (0, 1, 0), FACE - 0.01, FACE + 0.007,
                               M["stripe"], col))
        back = lambda x, z: frame((x, FACE, z), (-1, 0, 0), (0, 1, 0))
        if s == LEFT:
            parts.append(text("Logo", LOGO, 1.45, back(1.8, 5.95), M["stripe"], col, lift=0.008, fit=2.9))
        else:
            parts.append(text("Slogan", SLOGAN, 0.42, back(-1.8, 5.95), M["trim"], col, lift=0.008, fit=2.9))
        for part in parts:
            attach(part, leaf)
        doors[name] = leaf
    return doors


# ───────────────────────────────────────────────────────────── výbava karoserie
def details(col, groups):
    """Nárazníky, maska, světla, lišty, pruhy, nápisy, stěrače, SPZ."""
    # Předek: maska, logo, světla (sedí na tvaru karoserie), nárazník, SPZ.
    for z in (2.75, 3.0, 3.25):
        box("Grille bar", (3.6, 0.06, 0.08), (0, SHELL_FRONT - 0.02, z), M["chrome"], col, 0.02)
    disc("Badge ring", (0, SHELL_FRONT - 0.07, 3.0), (0, 1, 0), 0.3, 0.06, M["chrome"], col)
    disc("Badge", (0, SHELL_FRONT - 0.09, 3.0), (0, 1, 0), 0.24, 0.06, M["stripe"], col)
    text("Badge text", BADGE, 0.3, frame((0, SHELL_FRONT - 0.125, 3.0), (1, 0, 0), (0, -1, 0)), M["plate"], col, lift=0.0)
    front = lambda q: Vector((q[0], 0, q[1]))
    for s in (LEFT, RIGHT):
        sx = lambda pts, s=s: [(s * x, z) for x, z in pts] if s > 0 else [(s * x, z) for x, z in reversed(pts)]
        lamp = volume("Headlight volume", sx([(1.95, 2.78), (3.45, 2.78), (3.45, 3.62), (1.95, 3.52)]), front, (0, 1, 0), -11.2, -9.9)
        skin("Headlight", lamp, M["head"], col)
        ind = volume("Indicator volume", sx([(3.48, 2.85), (4.2, 2.95), (4.2, 3.55), (3.48, 3.62)]), front, (0, 1, 0), -11.2, -9.6)
        skin("Indicator", ind, M["amber"], col)
        rim = volume("Headlight housing volume", sx([(1.85, 2.68), (4.2, 2.83), (4.2, 3.67), (1.85, 3.62)]), front, (0, 1, 0), -11.2, -9.5)
        skin("Headlight housing", rim, M["trim"], col, 0.025)   # černý rámeček kolem světel
        disc("Fog light", (s * 3.0, -10.975, 1.62), (0, 1, 0), 0.2, 0.04, M["head"], col)
        disc("Fog light ring", (s * 3.0, -10.955, 1.62), (0, 1, 0), 0.26, 0.04, M["chrome"], col)
    for x in (-1.3, 0.0, 1.3):   # obrysová světla nahoře na čele vysoké střechy
        marker = volume("Roof marker volume", [(x - 0.22, 9.9), (x + 0.22, 9.9), (x + 0.22, 10.3), (x - 0.22, 10.3)], front, (0, 1, 0), -7.3, -5.8)
        skin("Roof marker", marker, M["amber"], col, 0.04)
    span_box("Front bumper", (-3.95, -10.94, CLEARANCE), (3.95, -10.4, 2.45), M["trim"], col, 0.2)
    span_box("Bumper intake", (-1.9, -10.97, 1.38), (1.9, -10.92, 1.62), M["rubber"], col)
    span_box("Front plate", (-0.8, -10.995, 1.82), (0.8, -10.955, 2.2), M["plate"], col)
    text("Front plate text", PLATE, 0.28, frame((0, -10.995, 2.01), (1, 0, 0), (0, -1, 0)), M["trim"], col, lift=0.005)
    for x0, x1 in ((-2.6, -0.3), (0.2, 2.5)):
        tube("Wiper", windscreen_point((x0, 0.1), 0.03), windscreen_point((x1, 0.22), 0.03), 0.035, M["trim"], col, 8)
    glass = prism("Windscreen glass", rounded(-2.97, 0.065, 2.97, 0.945, 0.06, 2), windscreen_point, windscreen_normal(), -0.12, -0.08,
                  M["glass"], col)
    # Záď: nárazník se schůdkem, SPZ, odrazky.
    span_box("Rear bumper", (-3.95, 10.4, CLEARANCE), (3.95, 10.96, 2.25), M["trim"], col, 0.2)
    span_box("Bumper step", (-2.0, 10.45, 2.25), (2.0, 10.94, 2.3), M["rubber"], col)
    span_box("Rear plate", (-0.8, 10.955, 1.55), (0.8, 10.995, 1.93), M["plate"], col)
    text("Rear plate text", PLATE, 0.28, frame((0, 10.995, 1.74), (-1, 0, 0), (0, 1, 0)), M["trim"], col, lift=0.005)
    for s in (LEFT, RIGHT):
        span_box("Rear reflector", (s * 3.2, 10.96, 1.66), (s * 3.75, 10.99, 1.82), M["red"], col)
    # Boky: lemy podběhů, ochranné lišty, pruhy, nápisy, lišta posuvných dveří, víčko nádrže.
    for s in (LEFT, RIGHT):
        for ya in (AXLE_F, AXLE_R):
            arch_flare("Arch flare", s, ya, col)
        rub = [(-9.2, AXLE_F - ARCH - 0.25), (AXLE_F + ARCH + 0.25, AXLE_R - ARCH - 0.25), (AXLE_R + ARCH + 0.25, 10.7)]
        for y0, y1 in rub:
            cuts = [(y0, y1)]
            if s == RIGHT and y0 < SLIDE_FRONT < y1:
                cuts = [(y0, SLIDE_FRONT - GAP), (SLIDE_FRONT + GAP, SLIDE_BACK - GAP), (SLIDE_BACK + GAP, y1)]
            for a, b in cuts:
                on_door = s == RIGHT and SLIDE_FRONT < (a + b) / 2 < SLIDE_BACK
                o = prism("Rub strip", rounded(a, 2.05, b, 2.5, 0.08, 2), lambda q, s=s: side_point(s, q[0], q[1]), (s, 0, 0), -0.02, 0.1,
                          M["trim"], groups["slide"] if on_door else col, smooth=True)
                bevel(o, 0.025, 2)
        for z0, z1 in ((4.35, 4.75), (4.88, 4.98)):
            side_bands(s, z0, z1, M["stripe"], "Stripe", -9.3, 10.8, groups)
        yc = 4.0 if s == LEFT else (SLIDE_BACK + R) / 2 + 0.1
        text("Logo", LOGO, 2.2, side_frame(s, yc, 7.6), M["stripe"], col, fit=6.4)
        text("Name", NAME, 0.62, side_frame(s, yc, 6.4), M["trim"], col, fit=6.4)
        text("Slogan", SLOGAN, 0.42, side_frame(s, yc, 5.8), M["trim"], col, fit=6.4)
    span_box("Sliding door sill", (RIGHT * HOLLOW, SLIDE_FRONT, SLIDE_BOTTOM - GAP), (RIGHT * (SIDE - 0.02), SLIDE_BACK, SLIDE_BOTTOM),
             M["rail"], col)   # hliníkový práh pod posuvnými dveřmi (schod do nákladového prostoru)
    prism("Slide rail cover", [(SLIDE_BACK + 0.12, 5.12), (9.4, 5.12), (9.4, 5.3), (SLIDE_BACK + 0.12, 5.3)],
          lambda q: side_point(RIGHT, q[0], q[1]), (RIGHT, 0, 0), -0.01, 0.05, M["trim"], col)
    disc("Fuel cap", (LEFT * (SIDE + 0.02), -3.5, 3.6), (1, 0, 0), 0.26, 0.05, M["trim"], col)
    return glass


def interior(col):
    """Nákladový prostor (podlaha, překližka, lišty na upínání, žebra, světla) a kabina (palubní deska, volant, sedadla)."""
    # Podlaha přesně 6,6 × 14,0 na výšce 2,4 a úchyty na upínání u stěn.
    span_box("Cargo floor", (-BAY_X, BAY_FRONT, FLOOR - 0.1), (BAY_X, BAY_BACK, FLOOR), M["floor"], col)
    for k in range(6):
        y = BAY_FRONT + 1.2 + k * 2.3
        for s in (LEFT, RIGHT):
            span_box("Tie-down", (s * (BAY_X - 0.05), y - 0.2, FLOOR), (s * (BAY_X - 0.33), y + 0.2, FLOOR + 0.05), M["rail"], col)
    # Překližka: přepážka a boky po panelech (vpravo jen za posuvnými dveřmi), nad ní žebra plechu.
    span_box("Bulkhead lining", (-BAY_X, BAY_FRONT - LINING, FLOOR), (BAY_X, BAY_FRONT, CEIL - 0.3), M["ply"], col)
    for s in (LEFT, RIGHT):
        y0 = BAY_FRONT if s == LEFT else SLIDE_BACK + GAP + 0.02
        count = 6 if s == LEFT else 4
        width = (BACK_IN - y0 - (count - 1) * 0.04) / count
        for k in range(count):
            a = y0 + k * (width + 0.04)
            span_box("Wall lining", (s * BAY_X, a, FLOOR), (s * HOLLOW, a + width, 7.4), M["ply"], col)
            if k:
                span_box("Wall rib", (s * BAY_X, a - 0.12, 7.4), (s * HOLLOW, a + 0.08, CEIL - 0.45), M["inner"], col)
        for z in (4.3, 6.9):
            span_box("Wall rail", (s * (BAY_X - 0.06), y0 + 0.1, z - 0.08), (s * BAY_X, BACK_IN - 0.1, z + 0.08), M["rail"], col)
    for y in (-0.7, 1.6, 3.9, 6.2, 8.5):
        span_box("Roof rib", (-2.9, y - 0.1, CEIL - 0.1), (2.9, y + 0.1, CEIL), M["inner"], col)
    for y in (0.45, 7.35):
        span_box("Ceiling light frame", (-0.32, y - 0.85, CEIL - 0.08), (0.32, y + 0.85, CEIL), M["trim"], col)
        span_box("Ceiling light", (-0.25, y - 0.78, CEIL - 0.11), (0.25, y + 0.78, CEIL - 0.08), M["lamp"], col)
    # Kabina.
    span_box("Cab floor", (-CAB_HOLLOW, -8.9, FLOOR), (CAB_HOLLOW, CAB_WALL, FLOOR + 0.06), M["rubber"], col)
    box("Dashboard", (2 * CAB_HOLLOW - 0.1, 1.2, 2.5), (0, -8.45, FLOOR + 1.25), M["inside"], col, 0.12)
    box("Dashboard top", (2 * CAB_HOLLOW - 0.3, 0.9, 0.35), (0, -8.35, FLOOR + 2.55), M["inside"], col, 0.12)
    box("Instruments", (1.5, 0.45, 0.4), (LEFT * SEAT_X, -7.95, FLOOR + 2.75), M["inside"], col, 0.1)
    box("Console", (1.0, 1.0, 1.6), (0, -7.4, FLOOR + 0.8), M["inside"], col, 0.1)
    tube("Gear lever", (0, -7.2, FLOOR + 1.6), (0, -7.0, FLOOR + 2.2), 0.05, M["inside"], col, 8)
    ball = bmesh.new()
    bmesh.ops.create_uvsphere(ball, u_segments=10, v_segments=6, radius=0.12)
    mesh_object("Gear knob", ball, [M["trim"]], col).location = (0, -7.0, FLOOR + 2.25)
    tube("Steering column", (LEFT * SEAT_X, -8.0, FLOOR + 1.9), (LEFT * SEAT_X, -7.35, FLOOR + 2.65), 0.07, M["inside"], col, 8)
    wheel_ring(col)
    for x in (LEFT * SEAT_X, RIGHT * SEAT_X):
        box("Seat base", (1.1, 1.2, SEAT_TOP - 0.45 - FLOOR), (x, SEAT_Y, (FLOOR + SEAT_TOP - 0.45) / 2), M["inside"], col, 0.03)
        box("Seat", (1.7, 1.7, 0.45), (x, SEAT_Y, SEAT_TOP - 0.225), M["seat"], col, 0.14)
        box("Seat back", (1.7, 0.4, 2.7), Matrix.Translation((x, -4.78, SEAT_TOP + 1.3)) @ Matrix.Rotation(math.radians(-10), 4, "X"),
            M["seat"], col, 0.14)
        box("Headrest", (1.1, 0.35, 0.6), (x, -4.58, SEAT_TOP + 3.0), M["seat"], col, 0.12)


def wheel_ring(col):
    bm = bmesh.new()
    rim = [bm.verts.new((0.55 + 0.06 * math.cos(a), 0, 0.06 * math.sin(a))) for a in (2 * math.pi * i / 6 for i in range(6))]
    es = [bm.edges.new((rim[i], rim[(i + 1) % 6])) for i in range(6)]
    bmesh.ops.spin(bm, geom=rim + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=2 * math.pi, steps=20, use_merge=True)
    o = mesh_object("Steering wheel", bm, [M["inside"]], col)
    o.matrix_world = Matrix.Translation((LEFT * SEAT_X, -7.3, FLOOR + 2.72)) @ Vector((0, -0.6, 1)).to_track_quat("Z", "Y").to_matrix().to_4x4()


# ───────────────────────────────────────────────────────────── kola
def wheel_mesh():
    k = WHEEL / 1.3
    bm = bmesh.new()

    def spin(outline, pick):
        before = set(bm.faces)
        vs = [bm.verts.new((x * k, 0.0, r * k)) for x, r in outline]
        es = [bm.edges.new((vs[i], vs[(i + 1) % len(vs)])) for i in range(len(vs))]
        bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(1, 0, 0), angle=2 * math.pi, steps=24, use_merge=True)
        for f in set(bm.faces) - before:
            c = f.calc_center_median()
            f.material_index = pick(c.x / k, math.hypot(c.y, c.z) / k)

    # Pneumatika (průřez x, poloměr) a ocelový disk s nábojem.
    spin([(-0.5, 0.92), (-0.5, 1.02), (-0.48, 1.12), (-0.43, 1.21), (-0.36, 1.27), (-0.3, 1.3), (-0.12, 1.3), (-0.12, 1.25),
          (0.12, 1.25), (0.12, 1.3), (0.3, 1.3), (0.36, 1.27), (0.43, 1.21), (0.48, 1.12), (0.5, 1.02), (0.5, 0.92)], lambda x, r: 0)
    spin([(0.36, 0.94), (0.36, 0.87), (0.27, 0.82), (0.21, 0.73), (0.2, 0.55), (0.25, 0.47), (0.25, 0.33), (0.19, 0.27),
          (0.19, 0.17), (0.29, 0.16), (0.31, 0.0), (-0.28, 0.13), (-0.3, 0.82), (-0.36, 0.87), (-0.36, 0.94)],
         lambda x, r: 2 if r < 0.18 and x > 0.15 else 1)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    for i in range(6):
        a = 2 * math.pi * i / 6
        before = set(bm.faces)
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.05 * k, radius2=0.05 * k, depth=0.07 * k,
                              matrix=Matrix.Translation((0.27 * k, 0.39 * k * math.cos(a), 0.39 * k * math.sin(a))) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
        for f in set(bm.faces) - before:
            f.material_index = 2
    sharpen(bm, 40)
    me = bpy.data.meshes.new("Wheel")
    bm.to_mesh(me)
    bm.free()
    for m in (M["rubber"], M["rim"], M["chrome"]):
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    return me


def wheels(col):
    me = wheel_mesh()
    for name, x, y in (("Wheel_FL", LEFT * TRACK, AXLE_F), ("Wheel_FR", RIGHT * TRACK, AXLE_F), ("Wheel_RL", LEFT * TRACK, AXLE_R),
                       ("Wheel_RR", RIGHT * TRACK, AXLE_R)):
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.location = (x, y, WHEEL)
        o.rotation_euler.z = math.pi if x < 0 else 0.0   # vnější strana disku ven


# ───────────────────────────────────────────────────────────── scéna, světla, kamera
VIEWS = {   # pozice kamery pro náhledy: (kamera, cíl, ohnisko, rozlišení, dveře)
    "front": ((-27.0, -33.0, 12.5), (0.0, -0.6, 4.4), 50, (1720, 1075), "closed"),
    "rear": ((15.0, 30.0, 10.5), (0.0, 3.0, 4.8), 42, (848, 530), "back"),
    "side": ((-30.0, -4.0, 7.5), (0.0, 1.0, 4.6), 42, (848, 530), "side"),
}


def studio(col):
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"   # 1 jednotka = 1 stud (doporučení Robloxu pro export FBX)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=90)
    mesh_object("Studio floor", bm, [M["studio"]], col, False)
    target = bpy.data.objects.new("Camera target", None)
    col.objects.link(target)
    target.location = VIEWS["front"][1]
    cam = bpy.data.objects.new("Sprinter camera", bpy.data.cameras.new("Sprinter camera"))
    col.objects.link(cam)
    cam.data.lens = 50
    cam.location = VIEWS["front"][0]
    track = cam.constraints.new("TRACK_TO")
    track.target, track.track_axis, track.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    scene.camera = cam

    def lamp(name, kind, at, energy, size=None):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        if kind == "SUN":
            data.angle = math.radians(6)
        if size:
            data.size = size
        o = bpy.data.objects.new(name, data)
        col.objects.link(o)
        o.location = at
        o.rotation_euler = (Vector((0, 0, 4)) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
        return o

    lamp("Sun", "SUN", (-12, -18, 24), 3.2)
    lamp("Fill light", "AREA", (24, 10, 13), 4200, 18)
    lamp("Rim light", "AREA", (6, 30, 16), 3000, 12)
    lamp("Bay light", "POINT", (0, 4.0, 8.6), 260)
    world = scene.world or bpy.data.worlds.new("Sprinter world")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    nt = world.node_tree
    nt.nodes.clear()
    sky, dark = nt.nodes.new("ShaderNodeBackground"), nt.nodes.new("ShaderNodeBackground")
    sky.inputs["Color"].default_value, sky.inputs["Strength"].default_value = (*linear("#9AA6B4"), 1), 0.7
    dark.inputs["Color"].default_value = (*linear("#15181B"), 1)
    path, mix, out = nt.nodes.new("ShaderNodeLightPath"), nt.nodes.new("ShaderNodeMixShader"), nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(sky.outputs["Background"], mix.inputs[1])
    nt.links.new(dark.outputs["Background"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
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


def show_in_viewport():
    """V Blenderu přepne 3D okno na Material Preview, ať je vidět barva."""
    screen = getattr(bpy.context, "screen", None)
    for area in (screen.areas if screen else []):
        if area.type == "VIEW_3D":
            area.spaces[0].shading.type = "MATERIAL"


DOOR_GROUPS = ("CabDoorL", "CabDoorR", "SideDoor", "BackDoorL", "BackDoorR")


def build():
    global CUT, SHELL
    clear_previous()
    materials()
    root = bpy.data.collections.new("Sprinter")
    bpy.context.scene.collection.children.link(root)
    for k in ("Body",) + DOOR_GROUPS + ("Wheels", "Cutters", "Volumes", "Studio"):
        COLS[k] = collection("Sprinter_" + k, root)
    CUT = COLS["Cutters"]
    SHELL = shell_mesh()
    cutters()
    body(COLS["Body"])
    doors = cab_doors()
    doors["SideDoor"] = sliding_door()
    doors.update(back_doors())
    # Pruhy na posuvných dveřích vzniknou rovnou v jejich kolekci; ty na dveřích kabiny přesune adopt().
    groups = {None: COLS["Body"], "cab": COLS["Body"], "slide": COLS["SideDoor"]}
    details(COLS["Body"], groups)
    interior(COLS["Body"])
    wheels(COLS["Wheels"])
    studio(COLS["Studio"])
    adopt(doors)
    for name in ("Cutters", "Volumes"):
        bpy.context.view_layer.layer_collection.children["Sprinter"].children["Sprinter_" + name].hide_viewport = True
    show_in_viewport()
    source = globals().get("__file__", "")
    if os.path.isfile(source) and "sprinter.py" not in bpy.data.texts:   # skript přibalený do .blend (záložka Scripting)
        bpy.data.texts.new("sprinter.py").write(open(source, encoding="utf-8").read())
    return doors


def world_center(o):
    return sum((o.matrix_world @ Vector(c) for c in o.bound_box), Vector()) / 8


def adopt(doors):
    """Díly výbavy, které leží na dveřích (pruhy, lišty), patří těm dveřím: přesune je do jejich kolekce a přidělá."""
    for o in list(COLS["Body"].objects):
        if o.name.startswith(("Stripe", "Rub strip")):
            c = world_center(o)
            for s, name in ((LEFT, "CabDoorL"), (RIGHT, "CabDoorR")):
                if s * c.x > 3.5 and CAB_DOOR_BOTTOM < c.z < CAB_DOOR_TOP and cab_front(c.z) < c.y < CAB_DOOR_BACK:
                    move(o, doors[name], name)
    for o in list(COLS["SideDoor"].objects):
        if o.parent is None and o is not doors["SideDoor"]:
            attach(o, doors["SideDoor"])


def move(o, door, name):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    COLS[name].objects.link(o)
    attach(o, door)


# ───────────────────────────────────────────────────────────── náhledy
def pose(doors, which):
    """Otevře dveře pro náhled: "back" = zadní křídla, "side" = posuvné dveře, jinak vše zavřené."""
    doors["BackDoorL"].rotation_euler.z = math.radians(-105) if which == "back" else 0.0
    doors["BackDoorR"].rotation_euler.z = math.radians(105) if which == "back" else 0.0
    slid = doors["SideDoor"]
    base = Vector((RIGHT * SIDE, SLIDE_FRONT, (SLIDE_BOTTOM + SLIDE_TOP) / 2))
    slid.location = base + (Vector((RIGHT * SLIDE_OUT, SLIDE_TRAVEL, 0)) if which == "side" else Vector())
    bpy.context.view_layer.update()


def render_views(doors, folder, samples=64):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples, scene.cycles.use_denoising = samples, True
    os.makedirs(folder, exist_ok=True)
    cam = scene.camera
    target = bpy.data.objects["Camera target"]
    for name, (at, look, lens, (w, h), which) in VIEWS.items():
        pose(doors, which)
        cam.location, target.location, cam.data.lens = at, look, lens
        scene.render.resolution_x, scene.render.resolution_y = w, h
        scene.render.filepath = os.path.join(folder, f"sprinter-{name}.png")
        bpy.ops.render.render(write_still=True)
    pose(doors, "closed")
    cam.location, target.location, cam.data.lens = VIEWS["front"][0], VIEWS["front"][1], VIEWS["front"][2]


def sheet(folder, out):
    """Složí náhled sprinter-preview.png ze tří renderů (potřebuje Pillow)."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("(bez Pillow: náhled se neskládá; pip install pillow)")
        return
    canvas = Image.new("RGB", (1800, 1780), (26, 29, 33))
    draw = ImageDraw.Draw(canvas)

    def font(size, bold=False):
        for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                     "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"):
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
        return ImageFont.load_default()

    draw.rectangle((40, 34, 46, 84), fill=(179, 38, 30))
    draw.text((62, 30), "DELIVEROS SPRINTER / BLENDER", font=font(38), fill=(236, 236, 236))
    draw.text((64, 80), f"design/blender-sprinter/sprinter.py · {WIDTH} × {HEIGHT} × {LENGTH} studs · bay {BAY_WIDTH} × {BAY_HEIGHT} × "
                        f"{BAY_LENGTH} · roblox/ZDCSprinterArt.fbx", font=font(21), fill=(150, 156, 164))
    for name, xy in (("front", (40, 110)), ("rear", (40, 1210)), ("side", (912, 1210))):
        path = os.path.join(folder, f"sprinter-{name}.png")
        if os.path.exists(path):
            canvas.paste(Image.open(path).convert("RGB"), xy)
    canvas.save(out)
    print("Náhled:", out)


# ───────────────────────────────────────────────────────────── export do Robloxu (hra)
# Hra (Zombie Delivery): server/SprinterMesh.luau najde v Roblox Studiu naimportovaný ZDCSprinterArt.fbx a oblékne do něj
# každý Sprinter. Díly se jmenují "<skupina>_<povrch>": skupina Body (karoserie, vnitřek, světla), CabDoorL / CabDoorR
# (dveře kabiny), SideDoor (posuvné dveře), BackDoorL / BackDoorR (zadní křídla), Wheel (levé přední kolo, hra ho dá na
# všechna čtyři); povrch říká hře barvu a materiál. Značky SprinterMark_o / _x / _y / _z / _w ukazují hře, jak Roblox
# model při importu otočil a zvětšil: počátek (zem pod středem auta), +X ve hře (pravý bok, tady -X), nahoru, dozadu,
# střed kola. (Ne "mark_o": to hledají ZDCVanArt a ZDCFurnitureArt, ať si modely nepletou.)
FINISHES = {
    "Sprinter Paint": "paint", "Sprinter Stripe": "stripe", "Sprinter Trim": "trim", "Sprinter Rubber": "rubber",
    "Sprinter Glass": "glass", "Sprinter Chrome": "chrome", "Sprinter Rim": "rim", "Sprinter Underbody": "under",
    "Sprinter Plate": "plate", "Sprinter Headlight": "head", "Sprinter Indicator": "amber", "Sprinter Taillight": "red",
    "Sprinter Inside": "inside", "Sprinter Seat": "seat", "Sprinter Plywood": "ply", "Sprinter Floor": "floor",
    "Sprinter Rail": "rail", "Sprinter Inner": "inner", "Sprinter Ceiling Light": "lamp",
}
GROUPS = {"Body": "Body", "CabDoorL": "CabDoorL", "CabDoorR": "CabDoorR", "SideDoor": "SideDoor", "BackDoorL": "BackDoorL",
          "BackDoorR": "BackDoorR"}
MARK = "SprinterMark"


def game_axes(v):
    """Blender (x, y, z) → hra (x doprava, y nahoru, z dozadu): (-x, z, y)."""
    return Vector((-v.x, v.z, v.y))


def evaluated(o, dg):
    return bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)


def split_by_finish(me, matrix, out, group):
    """Rozdělí síť podle povrchu do out[(skupina, povrch)]; normály rohů se zachovají (atribut nrm)."""
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
    names = [FINISHES[m.name] if m else "trim" for m in me.materials] or ["trim"]
    fin = me.attributes.get("fin") or me.attributes.new("fin", "INT", "FACE")
    fin.data.foreach_set("value", [names.index(names[p.material_index]) if p.material_index < len(names) else 0 for p in me.polygons])
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


def measure(sources, doors):
    """Změří hotový model (zavřené dveře) a vrátí rozměry pro hru a kontrolu mesh-check.py."""
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    mlo, mhi = Vector(lo), Vector(hi)
    bottom = 1e9
    tris, verts = [], []
    for group, me, matrix, name in sources:
        pts = [matrix @ v.co for v in me.vertices]
        if not pts:
            continue
        base = len(verts)
        verts.extend(pts)
        me.calc_loop_triangles()
        tris.extend([tuple(base + i for i in t.vertices) for t in me.loop_triangles])
        for p in pts:
            mlo, mhi = Vector(map(min, mlo, p)), Vector(map(max, mhi, p))
            if not name.startswith("Mirror"):
                lo, hi = Vector(map(min, lo, p)), Vector(map(max, hi, p))
            if group != "Wheel":
                bottom = min(bottom, p.z)
    for o in bpy.data.collections["Sprinter_Wheels"].objects:   # všechna čtyři kola (do hry jde jen jedno)
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo, hi = Vector(map(min, lo, p)), Vector(map(max, hi, p))
    tree = BVHTree.FromPolygons(verts, tris)

    def hit(origin, direction):
        found = tree.ray_cast(Vector(origin), Vector(direction))
        return found[0]

    floor_hit = hit((0, 5.0, 6.0), (0, 0, -1))
    ceil_hit = hit((0, 5.0, 6.0), (0, 0, 1))
    left_hit, right_hit = hit((0, 5.0, 6.0), (1, 0, 0)), hit((0, 5.0, 6.0), (-1, 0, 0))
    front_hit, back_hit = hit((1.0, 4.0, 3.0), (0, -1, 0)), hit((1.0, 4.0, 3.0), (0, 1, 0))   # (x = 0 is the doors' gap)
    cab_wall = hit((0, -6.0, 9.0), (0, 1, 0))
    floor_piece = next((me, matrix) for group, me, matrix, name in sources if name == "Cargo floor")
    fy = [(floor_piece[1] @ v.co).y for v in floor_piece[0].vertices]
    wheel_y = sorted({round(o.location.y, 4) for o in bpy.data.collections["Sprinter_Wheels"].objects})
    r4 = lambda x: round(x, 4)
    return {
        "overall": [r4(hi.x - lo.x), r4(hi.z - lo.z), r4(hi.y - lo.y)],
        "overallWithMirrors": [r4(mhi.x - mlo.x), r4(mhi.z - mlo.z), r4(mhi.y - mlo.y)],
        "ground": r4(lo.z),
        "front": r4(lo.y), "back": r4(hi.y),
        "wheelbase": r4(wheel_y[-1] - wheel_y[0]),
        "wheelRadius": WHEEL,
        "clearance": r4(bottom),
        "floor": r4(floor_hit.z),
        "bay": {"width": r4(left_hit.x - right_hit.x), "height": r4(ceil_hit.z - floor_hit.z), "length": r4(max(fy) - min(fy)),
                "start": r4(front_hit.y), "end": r4(max(fy)), "lengthDoorsClosed": r4(back_hit.y - front_hit.y)},
        "cabWall": r4(cab_wall.y),
        "cab": r4(cab_wall.y - lo.y),
    }


def export_game(folder, doors):
    """ZDCSprinterArt.fbx a ZDCSprinterArt.json pro hru (návod: NAVOD.md)."""
    os.makedirs(folder, exist_ok=True)
    pose(doors, "closed")
    temp = bpy.data.collections.new("Sprinter_GameExport")
    bpy.context.scene.collection.children.link(temp)
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    sources = []
    for key, group in GROUPS.items():
        for o in COLS[key].objects:
            if o.type == "MESH":
                sources.append((group, evaluated(o, dg), o.matrix_world.copy(), o.name))
    wheel = bpy.data.objects["Wheel_FL"]
    sources.append(("Wheel", evaluated(wheel, dg), wheel.matrix_world.copy(), wheel.name))
    dims = measure(sources, doors)
    pieces = {}
    for group, me, matrix, _ in sources:
        split_by_finish(me, matrix, pieces, group)
    pivots = {name: doors[name].matrix_world.translation.copy() for name in DOOR_GROUPS}
    pivots["Wheel"] = wheel.matrix_world.translation.copy()
    made = []
    for (group, finish), meshes in sorted(pieces.items()):
        bm = bmesh.new()
        for piece in meshes:
            bm.from_mesh(piece)
        me = bpy.data.meshes.new(f"{group}_{finish}")
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
        me.materials.append(bpy.data.materials.get(next(k for k, v in FINISHES.items() if v == finish)))
        o = bpy.data.objects.new(f"{group}_{finish}", me)
        temp.objects.link(o)
        pivot = pivots.get(group)
        if pivot is not None:   # dveře: počátek v pantu, kolo: ve středu (v Robloxu na tom nezáleží, v Blenderu ano)
            me.transform(Matrix.Translation(-pivot))
            o.location = pivot
        made.append(o)
    markers = {"o": Vector((0, 0, 0)), "x": Vector((-10, 0, 0)), "y": Vector((0, 0, 10)), "z": Vector((0, 10, 0)),
               "w": wheel.matrix_world.translation.copy()}
    for key, at in markers.items():
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.3)
        bmesh.ops.translate(bm, vec=at, verts=bm.verts)
        made.append(mesh_object(f"{MARK}_{key}", bm, [M["trim"]], temp, False))
    for o in bpy.context.scene.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.fbx(filepath=os.path.join(folder, "ZDCSprinterArt.fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="OFF", use_mesh_modifiers=True)
    manifest = {"pieces": {}, "markers": {}, "groups": {}, "dimensions": dims}
    total = 0
    for o in made:
        if o.name.startswith(MARK):
            continue
        pts = [game_axes(o.matrix_world @ v.co) for v in o.data.vertices]
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        n = sum(len(p.vertices) - 2 for p in o.data.polygons)
        total += n
        manifest["pieces"][o.name] = {"center": [round((a + b) / 2, 4) for a, b in zip(lo, hi)], "size": [round(b - a, 4) for a, b in zip(lo, hi)],
                                      "triangles": n}
    for key, at in markers.items():
        manifest["markers"][f"{MARK}_{key}"] = [round(c, 4) for c in game_axes(at)]
    hinge = lambda name: [round(c, 4) for c in game_axes(pivots[name])]
    manifest["groups"] = {
        "Body": {"on": "the body (BodyRoot, else the chassis)"},
        "CabDoorL": {"pivot": hinge("CabDoorL"), "move": "hinge, vertical axis, the front edge"},
        "CabDoorR": {"pivot": hinge("CabDoorR"), "move": "hinge, vertical axis, the front edge"},
        "SideDoor": {"pivot": hinge("SideDoor"), "move": f"slides {SLIDE_OUT} out (+x) and {SLIDE_TRAVEL} back (+z)"},
        "BackDoorL": {"pivot": hinge("BackDoorL"), "move": "hinge, vertical axis, the outer edge"},
        "BackDoorR": {"pivot": hinge("BackDoorR"), "move": "hinge, vertical axis, the outer edge"},
        "Wheel": {"pivot": hinge("Wheel"), "radius": WHEEL, "move": "the front left wheel; the game puts it on every tyre"},
    }
    manifest["seats"] = {"driver": [round(-LEFT * SEAT_X, 4), SEAT_TOP, SEAT_Y], "passenger": [round(-RIGHT * SEAT_X, 4), SEAT_TOP, SEAT_Y]}
    manifest["triangles"] = total
    manifest["wheelTriangles"] = sum(v["triangles"] for k, v in manifest["pieces"].items() if k.startswith("Wheel_"))
    with open(os.path.join(folder, "ZDCSprinterArt.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    for o in list(temp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(temp)
    for _, me, _, _ in sources:
        bpy.data.meshes.remove(me)
    return manifest


def report(manifest):
    d = manifest["dimensions"]
    print(f"ZDCSprinterArt: {len(manifest['pieces'])} dílů, {manifest['triangles']} trojúhelníků "
          f"(kolo {manifest['wheelTriangles']}, ve hře 4×)")
    print(f"  celkem {d['overall']} (se zrcátky {d['overallWithMirrors']}), rozvor {d['wheelbase']}, světlá výška {d['clearance']}")
    print(f"  nákladový prostor {d['bay']}, podlaha {d['floor']}, kabina {d['cab']} (stěna kabiny {d['cabWall']})")
    want = {"overall": [WIDTH, HEIGHT, LENGTH], "wheelbase": WHEELBASE, "clearance": CLEARANCE, "floor": FLOOR, "cab": CAB}
    off = lambda got, v: any(abs(a - b) > 1e-3 for a, b in zip(got, v)) if isinstance(v, list) else abs(got - v) > 1e-3
    bad = [k for k, v in want.items() if off(d[k], v)]
    bay = d["bay"]
    if abs(bay["width"] - BAY_WIDTH) > 1e-3 or abs(bay["height"] - BAY_HEIGHT) > 1e-3 or abs(bay["length"] - BAY_LENGTH) > 1e-3:
        bad.append("bay")
    if abs(bay["start"] - (d["cabWall"] + 1.0)) > 1e-3:
        bad.append("bay start")
    print("  rozměry sedí" if not bad else f"  POZOR, nesedí: {bad}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    doors = build()

    def arg(flag):
        return argv[argv.index(flag) + 1] if flag in argv else None

    if arg("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--save")))
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        manifest = export_game(folder, doors)
        report(manifest)
        print("FBX pro hru:", os.path.join(os.path.abspath(folder), "ZDCSprinterArt.fbx"))
    if arg("--render"):
        render_views(doors, arg("--render"), int(arg("--samples") or 64))
        if arg("--sheet"):
            sheet(arg("--render"), os.path.abspath(arg("--sheet")))


main()
