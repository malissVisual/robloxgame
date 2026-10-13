"""Zombie Delivery: dodávka (van) pro Blender.

Spuštění v Blenderu: nahoře záložka Scripting → Open → vyber van.py → Run Script (▶, nebo Alt+P).
Skript postaví dodávku do kolekce "Van". Když ho spustíš znovu, starou dodávku nejdřív smaže, takže si můžeš
v části NASTAVENÍ měnit barvy a čísla a zkoušet. F12 = render, Home v 3D okně = ukaž celou dodávku.

Míry jsou ve studech jako Old Van ve hře (13 dlouhá, 6,6 široká): 1 jednotka v Blenderu = 1 stud.
Předek míří na -Y (pohled zepředu = Numpad 1). Každá část je samostatný objekt s čitelným jménem.

Bez Blenderu, jen s modulem bpy (pip install bpy):
    python van.py -- --save van.blend --render složka --export složka
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

# ───────────────────────────────────────────────────────────── NASTAVENÍ (změň a spusť znovu)
PAINT = "#D9CCB0"      # lak karoserie (béžová ZDC)
STRIPE = "#B3261E"     # pruh a logo
TRIM = "#202326"       # černé plasty: nárazníky, lemy blatníků, kliky, zrcátka
RIM = "#B9BDC1"        # disky kol
GLASS = "#16212A"      # okna
LOGO, NAME, SLOGAN = "ZDC", "ZOMBIE DELIVERY CO.", "WE DELIVER. THEY DON'T."
PLATE = "ZDC 01"       # SPZ
KIT = True             # výbava na apokalypsu: rám vpředu, střešní nosič, rezerva, kanystry, světla na střeše
EXPORT = False         # True = po postavení uloží FBX pro Roblox do složky "roblox" vedle uloženého .blend souboru

LENGTH, WIDTH, HEIGHT = 13.0, 6.6, 6.6   # délka, šířka a výška střechy (studs)
WHEEL = 1.3            # poloměr kola
BEVEL = 0.14           # zaoblení hran karoserie (modifikátor Bevel na objektu Body)

# ───────────────────────────────────────────────────────────── odvozené míry
L, W, H = LENGTH, WIDTH, HEIGHT
F, R = -L / 2, L / 2           # předek (-Y) a záď (+Y)
Z0 = 0.9                       # spodek karoserie
BELT = 3.6                     # linie oken: nad ní se boky naklání dovnitř
SLOPE = 0.10                   # o kolik se bok nakloní na 1 stud výšky
TILT = math.atan(SLOPE)
AXLE_F, AXLE_R = F + 1.8, R - 1.8   # nápravy (jako ve hře: délka/2 - kolo - 0,5)
ARCH = WHEEL + 0.3             # poloměr podběhu
TRACK = W / 2 - 0.48           # střed kola od osy auta
HOOD_FRONT, HOOD_BACK = (F + 0.35, 3.12), (F + 2.45, BELT)
SHIELD_TOP = (F + 3.7, H - 0.8)     # horní hrana čelního skla

M = {}      # materiály
CUT = None  # kolekce řezů (okna a spáry vyřezané modifikátorem Boolean)


def linear(hexcode):
    """#RRGGBB (jak ho znáš z malování) → lineární barva, se kterou počítá Blender."""
    h = hexcode.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, color, rough=0.5, metal=0.0, coat=0.0, emit=0.0):
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
    m["palette"] = color   # export do Robloxu: barva čtverečku v paletě
    return m


def materials():
    M.update(
        paint=material("Van Paint", PAINT, 0.38, coat=0.35),
        stripe=material("Van Stripe", STRIPE, 0.4, coat=0.35),
        trim=material("Van Trim", TRIM, 0.6),
        rubber=material("Van Rubber", "#111213", 0.85),
        glass=material("Van Glass", GLASS, 0.04, coat=1.0),
        chrome=material("Van Chrome", "#D5D9DD", 0.15, metal=1.0),
        rim=material("Van Rim", RIM, 0.35, metal=0.6),
        under=material("Van Underbody", "#2A2C2E", 0.9),
        plate=material("Van Plate", "#F1EFE6", 0.45),
        head=material("Van Headlight", "#FFF4DC", 0.2, emit=4.0),
        amber=material("Van Indicator", "#FF8A10", 0.3, emit=1.2),
        red=material("Van Taillight", "#D0140F", 0.3, emit=1.2),
        gun=material("Van Gunmetal", "#3B3E42", 0.45, metal=0.6),
        can_red=material("Van Jerry Can Red", "#A3221A", 0.5),
        can_olive=material("Van Jerry Can Olive", "#4E5A2A", 0.6),
        wood=material("Van Wood", "#8A6238", 0.8),
        floor=material("Van Studio Floor", "#41464C", 0.85),
    )


# ───────────────────────────────────────────────────────────── pomocníci
def collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def clear_previous():
    """Smaže dodávku z minulého spuštění (kolekce Van) a startovní kostku, světlo a kameru Blenderu."""
    root = bpy.data.collections.get("Van")
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


def bevel(o, width, segments=2):
    """Modifikátor Bevel: zakulatí hrany (změň Amount/Segments v panelu Modifiers)."""
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width, b.segments = width, segments
    b.limit_method, b.angle_limit = "ANGLE", math.radians(40)
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
    o = mesh_object(name, bm, [mat], col)
    o.matrix_world = place(at)
    if round:
        bevel(o, round)
    return o


def tube(name, a, b, r, mat, col, seg=14):
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=(b - a).length)
    sharpen(bm)
    o = mesh_object(name, bm, [mat], col)
    o.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat("Z", "Y").to_matrix().to_4x4()
    return o


def disc(name, center, axis, r, depth, mat, col, seg=20):
    c, d = Vector(center), Vector(axis).normalized() * depth / 2
    return tube(name, c - d, c + d, r, mat, col, seg)


def ball(name, at, r, mat, col):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=r)
    o = mesh_object(name, bm, [mat], col)
    o.location = at
    return o


def prism(name, outline, to3d, out, back, front, mat, col, radius=0.0, smooth=False):
    """Plochý tvar (`outline` 2D) položený na plochu auta funkcí `to3d`, vysunutý podél `out` od `back` do `front`."""
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
    if radius:
        ups = set(top)
        sides = [e for e in bm.edges if (e.verts[0] in ups) != (e.verts[1] in ups)]
        bmesh.ops.bevel(bm, geom=sides, offset=radius, segments=4, profile=0.5, affect="EDGES", clamp_overlap=True)
    return mesh_object(name, bm, [mat], col, smooth)


def cutter(name, outline, to3d, out, depth, mat, radius=0.0):
    """Řez do karoserie (okno, spára, mřížka): kolekce Van_Cutters, Boolean na objektu Body."""
    o = prism(name, outline, to3d, out, -depth, depth, mat, CUT, radius)
    o.display_type, o.hide_render = "WIRE", True
    return o


def text(name, body, size, matrix, mat, col, lift=0.006):
    """Nápis převedený na plochou síť (nízké rozlišení, ať má model v Robloxu málo trojúhelníků)."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body, cu.size, cu.align_x, cu.align_y = body, size, "CENTER", "CENTER"
    cu.resolution_u, cu.offset = 2, size * 0.025
    tmp = bpy.data.objects.new(name, cu)
    col.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    me.materials.clear()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    o.matrix_world = matrix @ Matrix.Translation((0, 0, lift))
    return o


def half_width(z):
    return W / 2 - SLOPE * max(0.0, z - BELT)


def side_point(side, y, z):
    return Vector((side * half_width(z), y, z))


def side_normal(side, upper):
    return Vector((side * math.cos(TILT), 0, math.sin(TILT))) if upper else Vector((side, 0, 0))


def side_frame(side, y, z, lift=0.0):
    """Matice pro díl na boku: x po směru čtení (zleva doprava při pohledu na bok), z ven z auta."""
    out = side_normal(side, z > BELT)
    return frame(side_point(side, y, z) + out * lift, (0, side, 0), out)


def seam_on(to3d, out, a, b, w=0.05, depth=0.05):
    """Tenká spára mezi dveřmi: řez podél úsečky a → b."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    p, e = Vector((-d.y, d.x)) * w / 2, d * w / 2
    cutter("Seam", [a - e - p, b + e - p, b + e + p, a - e + p], to3d, out, depth, M["rubber"])


def side_seam(side, a, b):
    """Spára na boku; nad linií oken je bok šikmý, proto se úsečka na té linii rozdělí."""
    (y0, z0), (y1, z1) = a, b
    if (z0 - BELT) * (z1 - BELT) < -1e-9:
        t = (BELT - z0) / (z1 - z0)
        m = (y0 + (y1 - y0) * t, BELT)
        side_seam(side, a, m)
        side_seam(side, m, b)
        return
    upper = (z0 + z1) / 2 > BELT
    seam_on(lambda q: side_point(side, q[0], q[1]), side_normal(side, upper), a, b)


def front_point(q):
    return Vector((q[0], F, q[1]))


def rear_point(q):
    return Vector((q[0], R, q[1]))


def hood_point(q):
    (y0, z0), (y1, z1) = HOOD_FRONT, HOOD_BACK
    return Vector((q[0], q[1], z0 + (q[1] - y0) * (z1 - z0) / (y1 - y0)))


def hood_normal():
    (y0, z0), (y1, z1) = HOOD_FRONT, HOOD_BACK
    return Vector((0, -(z1 - z0), y1 - y0)).normalized()


def shield_point(x, s, lift=0.0):
    """Bod na čelním skle: x do strany, s = 0 dole … 1 nahoře."""
    (y0, z0), (y1, z1) = HOOD_BACK, SHIELD_TOP
    n = Vector((0, -(z1 - z0), y1 - y0)).normalized()
    return Vector((x, y0 + (y1 - y0) * s, z0 + (z1 - z0) * s)) + n * lift


# ───────────────────────────────────────────────────────────── karoserie
def profile():
    """Obrys dodávky z boku (y, z): od předního spodku nahoru přes střechu, dolů po zádi a zpět spodkem s podběhy."""
    top = [(F, Z0), (F, 2.7), HOOD_FRONT, HOOD_BACK, SHIELD_TOP, (F + 4.05, H - 0.3), (F + 4.55, H),
           (R - 0.25, H), (R, H - 0.3), (R, BELT), (R, Z0)]

    def arch(ya):
        a0, n = math.asin((Z0 - WHEEL) / ARCH), 14
        return [(ya + ARCH * math.cos(a0 + (math.pi - 2 * a0) * k / n), WHEEL + ARCH * math.sin(a0 + (math.pi - 2 * a0) * k / n))
                for k in range(n + 1)]

    return top + arch(AXLE_R) + arch(AXLE_F), 3, 9   # + body linie oken vpředu a vzadu


def body_shell(col):
    pts, belt_front, belt_rear = profile()
    n = len(pts)
    bm = bmesh.new()
    weight = bm.edges.layers.float.get("bevel_weight_edge") or bm.edges.layers.float.new("bevel_weight_edge")
    rows = {s: [bm.verts.new((s * half_width(z), y, z)) for y, z in pts] for s in (-1, 1)}
    around = []
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((rows[-1][i], rows[-1][j], rows[1][j], rows[1][i]))
        f.material_index = 3 if i > belt_rear else 0   # spodek a podběhy tmavé
        around.append(f)
    for s in (-1, 1):
        r = rows[s]
        bm.faces.new(r[belt_front:belt_rear + 1])           # bok nad linií oken (šikmý)
        bm.faces.new(r[belt_rear:] + r[:belt_front + 1])    # bok pod ní (svislý, s podběhy)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Bevel jen na vybraných hranách: obrys boků a ostré zlomy profilu. Okraje podběhů ne (zakryje je plastový lem
    # a kulatý podběh blízko předku by se se zaoblením přední hrany překřížil).
    for i in range(n):
        j = (i + 1) % n
        if i <= belt_rear or pts[i][1] == pts[j][1] == Z0:
            for s in (-1, 1):
                bm.edges.get((rows[s][i], rows[s][j]))[weight] = 1.0
    for i in range(belt_rear + 2):
        a = Vector(pts[i]) - Vector(pts[i - 1])
        b = Vector(pts[(i + 1) % n]) - Vector(pts[i])
        if a.angle(b) > math.radians(20):
            bm.edges.get((rows[-1][i], rows[1][i]))[weight] = 1.0
    # Čelní sklo: plocha se zapustí dovnitř, kolem zůstane gumový rámeček.
    shield = around[belt_front]
    outer = set(shield.edges)
    ring = bmesh.ops.inset_individual(bm, faces=[shield], thickness=0.2, depth=-0.07, use_even_offset=True)["faces"]
    shield.material_index = 1
    for f in ring:
        f.material_index = 2
        for e in f.edges:
            if e not in outer:
                e[weight], e.smooth = 0.0, False
    o = mesh_object("Body", bm, [M["paint"], M["glass"], M["trim"], M["under"]], col)
    b = o.modifiers.new("Bevel", "BEVEL")
    b.limit_method, b.width, b.segments, b.use_clamp_overlap = "WEIGHT", BEVEL, 3, True
    cut = o.modifiers.new("Okna a spary", "BOOLEAN")
    cut.operation, cut.operand_type, cut.collection, cut.solver = "DIFFERENCE", "COLLECTION", CUT, "EXACT"
    cut.material_mode = "TRANSFER"
    wn = o.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.mode, wn.weight, wn.keep_sharp = "FACE_AREA", 80, True
    return o


def arch_flare(name, side, ya, col):
    """Plastový lem podběhu."""
    a0, n = math.asin((Z0 - WHEEL) / ARCH), 18
    bm = bmesh.new()
    rings = []
    for k in range(n + 1):
        a = a0 + (math.pi - 2 * a0) * k / n
        rings.append([bm.verts.new((side * x, ya + r * math.cos(a), WHEEL + r * math.sin(a)))
                      for x, r in ((W / 2 - 0.08, ARCH - 0.03), (W / 2 - 0.08, ARCH + 0.2), (W / 2 + 0.1, ARCH + 0.2), (W / 2 + 0.08, ARCH - 0.03))])
    for k in range(n):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_object(name, bm, [M["trim"]], col)
    bevel(o, 0.04)
    return o


def pieces(y0, y1, gaps, gap=0.07):
    """Rozdělí pruh od y0 do y1 tak, aby nepřecházel přes spáry dveří."""
    out, start = [], y0
    for g in sorted(gaps):
        if y0 < g < y1:
            out.append((start, g - gap))
            start = g + gap
    out.append((start, y1))
    return out


def body(col):
    shell = body_shell(col)
    door_front, door_back = -2.85, -0.45
    slide_front, slide_back = -0.25, 2.85
    top = H - 0.45
    rake = (SHIELD_TOP[0] - HOOD_BACK[0]) / (SHIELD_TOP[1] - HOOD_BACK[1])   # sklon sloupku A (dy na dz)
    knee = BELT + (door_front - 0.3 - HOOD_BACK[0]) / rake                   # kde spára dveří uhne podél sloupku
    corner = door_front + (top - knee) * rake
    for s in (-1, 1):
        # Dveře řidiče / spolujezdce a jejich okno.
        side_seam(s, (door_front, Z0 - 0.1), (door_front, knee))
        side_seam(s, (door_front, knee), (corner, top))
        side_seam(s, (corner, top), (door_back, top))
        side_seam(s, (door_back, top), (door_back, Z0 - 0.1))
        win_top, win_bottom = top - 0.4, BELT + 0.35
        cutter("Door window", [(door_front + 0.28, win_bottom), (door_back - 0.28, win_bottom), (door_back - 0.28, win_top),
                               (door_front + 0.28 + (win_top - knee) * rake, win_top), (door_front + 0.28, knee)],
               lambda q, s=s: side_point(s, q[0], q[1]), side_normal(s, True), 0.07, M["glass"], radius=0.15)
        box("Door handle", (0.08, 0.5, 0.13), side_frame(s, door_back - 0.55, 3.2, 0.04) @ Matrix.Rotation(math.pi / 2, 4, "Z"), M["trim"], col, 0.03)
        # Lem podběhů, ochranné lišty, pruh.
        for ya in (AXLE_F, AXLE_R):
            arch_flare("Arch flare", s, ya, col)
        gaps = [door_front, door_back] + ([slide_front, slide_back] if s > 0 else [])
        for y0, y1 in pieces(door_front + 0.12, slide_back - 0.05, gaps):
            box("Rub strip", (0.1, y1 - y0, 0.3), (s * (W / 2 + 0.04), (y0 + y1) / 2, 1.45), M["trim"], col, 0.04)
        stripe = pieces(-4.1, R - 0.16, gaps)
        for k, (y0, y1) in enumerate(stripe):
            outline = [(y0, 3.18), (y1, 3.18), (y1, 3.42), (y0 + (0.3 if k == 0 else 0), 3.42)]
            prism("Stripe", outline, lambda q, s=s: side_point(s, q[0], q[1]), (s, 0, 0), -0.01, 0.012, M["stripe"], col)
        # Nápisy na nákladovém prostoru.
        yc = (slide_front + R) / 2 + 0.1
        text("Logo", LOGO, 1.5, side_frame(s, yc, 5.2), M["stripe"], col)
        text("Name", NAME, 0.5, side_frame(s, yc, 4.3), M["trim"], col)
        text("Slogan", SLOGAN, 0.32, side_frame(s, yc, 3.9), M["trim"], col)
        # Zrcátko.
        tube("Mirror arm", (s * (half_width(4.05) - 0.05), -3.25, 4.05), (s * 3.85, -3.25, 4.12), 0.06, M["trim"], col)
        box("Mirror", (0.22, 0.5, 0.85), (s * 3.95, -3.2, 4.4), M["trim"], col, 0.07)
        box("Mirror glass", (0.15, 0.02, 0.72), (s * 3.95, -2.94, 4.4), M["chrome"], col, 0)
        # Schůdky a lapače bláta.
        box("Step", (0.4, 1.7, 0.1), (s * (W / 2 + 0.1), (door_front + door_back) / 2, 0.82), M["trim"], col, 0.03)
        for ya in (AXLE_F, AXLE_R):
            box("Mud flap", (0.85, 0.06, 0.55), (s * TRACK, ya + 1.58, 0.64), M["rubber"], col, 0.02)
    # Posuvné dveře vpravo, víčko nádrže vlevo.
    side_seam(1, (slide_front, Z0 - 0.1), (slide_front, top))
    side_seam(1, (slide_front, top), (slide_back, top))
    side_seam(1, (slide_back, top), (slide_back, Z0 - 0.1))
    box("Sliding door handle", (0.08, 0.5, 0.13), side_frame(1, slide_front + 0.55, 3.2, 0.04) @ Matrix.Rotation(math.pi / 2, 4, "Z"), M["trim"], col, 0.03)
    box("Sliding door step", (0.4, 2.6, 0.1), (W / 2 + 0.1, (slide_front + slide_back) / 2, 0.82), M["trim"], col, 0.03)
    disc("Fuel cap", (-(W / 2 + 0.01), 2.3, 2.2), (1, 0, 0), 0.24, 0.05, M["trim"], col)

    # Předek: maska, světla, nárazník, SPZ, kapota, stěrače.
    cutter("Grille", [(-1.5, 1.8), (1.5, 1.8), (1.5, 2.5), (-1.5, 2.5)], front_point, (0, -1, 0), 0.07, M["trim"], radius=0.12)
    for z in (1.98, 2.15, 2.32):
        box("Grille bar", (2.9, 0.06, 0.07), (0, F + 0.03, z), M["chrome"], col, 0.02)
    disc("Badge", (0, F - 0.02, 2.15), (0, 1, 0), 0.25, 0.05, M["chrome"], col)
    disc("Badge red", (0, F - 0.035, 2.15), (0, 1, 0), 0.19, 0.05, M["stripe"], col)
    for s in (-1, 1):
        box("Headlight bezel", (1.15, 0.06, 0.72), (s * 2.27, F - 0.01, 2.15), M["chrome"], col, 0.06)
    box("Front bumper", (W + 0.3, 0.55, 0.75), (0, F - 0.2, 1.12), M["trim"], col, 0.12)
    box("Front plate", (1.7, 0.04, 0.4), (0, F - 0.49, 1.15), M["plate"], col, 0.02)
    text("Front plate text", PLATE, 0.3, frame((0, F - 0.51, 1.15), (1, 0, 0), (0, -1, 0)), M["trim"], col)
    for s in (-1, 1):
        disc("Fog light ring", (s * 2.45, F - 0.48, 1.08), (0, 1, 0), 0.18, 0.04, M["chrome"], col)
        x = s * 2.95
        seam_on(hood_point, hood_normal(), (x, HOOD_FRONT[0] + 0.25), (x, HOOD_BACK[0] - 0.12))
    seam_on(hood_point, hood_normal(), (-2.95, HOOD_FRONT[0] + 0.25), (2.95, HOOD_FRONT[0] + 0.25))
    for x0, x1 in ((-2.55, -0.35), (0.0, 2.2)):
        tube("Wiper", shield_point(x0, 0.12, 0.02), shield_point(x1, 0.24, 0.02), 0.035, M["trim"], col, 8)

    # Záď: zadní dveře, okna, světla, SPZ, nárazník, výfuk.
    door_top = H - 0.42
    edge = lambda z: half_width(z) - 0.6
    seam_on(rear_point, (0, 1, 0), (0, Z0 - 0.1), (0, door_top))
    for s in (-1, 1):
        seam_on(rear_point, (0, 1, 0), (s * edge(Z0), Z0 - 0.1), (s * edge(BELT), BELT))
        seam_on(rear_point, (0, 1, 0), (s * edge(BELT), BELT), (s * edge(door_top), door_top))
        x0, x1 = sorted((s * 0.28, s * 2.2))
        cutter("Rear window", [(x0, 4.2), (x1, 4.2), (x1, 5.85), (x0, 5.85)], rear_point, (0, 1, 0), 0.07, M["glass"], radius=0.15)
        for z in (1.6, 5.2):
            box("Hinge", (0.22, 0.1, 0.4), (s * edge(z), R + 0.04, z), M["trim"], col, 0.03)
    seam_on(rear_point, (0, 1, 0), (-edge(door_top), door_top), (edge(door_top), door_top))
    box("Rear door handle", (0.5, 0.08, 0.13), (0.55, R + 0.04, 3.15), M["trim"], col, 0.03)
    box("Rear plate", (1.7, 0.04, 0.4), (0, R + 0.03, 1.8), M["plate"], col, 0.02)
    text("Rear plate text", PLATE, 0.3, frame((0, R + 0.05, 1.8), (-1, 0, 0), (0, 1, 0)), M["trim"], col)
    box("Rear bumper", (W + 0.3, 0.6, 0.7), (0, R + 0.2, 1.05), M["trim"], col, 0.12)
    box("Bumper step", (2.2, 0.45, 0.04), (0, R + 0.25, 1.42), M["rubber"], col, 0.01)
    tube("Exhaust", (-2.0, R - 0.9, 0.55), (-2.0, R + 0.55, 0.55), 0.1, M["chrome"], col)

    # Střecha a podvozek.
    for y in (0.3, 1.5, 2.7, 3.9, 5.1):
        box("Roof rib", (2 * half_width(H) - 0.8, 0.18, 0.06), (0, y, H + 0.01), M["paint"], col, 0.02)
    box("Antenna base", (0.16, 0.3, 0.08), (-2.3, -1.5, H + 0.03), M["trim"], col, 0.02)
    tube("Antenna", (-2.3, -1.5, H), (-2.3, -1.0, H + 1.3), 0.025, M["trim"], col, 8)
    for ya in (AXLE_F, AXLE_R):
        tube("Axle", (-TRACK + 0.3, ya, WHEEL), (TRACK - 0.3, ya, WHEEL), 0.12, M["under"], col)
    ball("Differential", (0, AXLE_R, WHEEL), 0.35, M["under"], col)
    box("Fuel tank", (1.4, 2.2, 0.5), (-1.6, 1.4, 0.62), M["under"], col, 0.08)
    return shell


def lights(col):
    for s in (-1, 1):
        box("Headlight", (1.03, 0.08, 0.6), (s * 2.27, F - 0.04, 2.15), M["head"], col, 0.08)
        box("Indicator", (0.3, 0.08, 0.6), (s * 3.0, F - 0.03, 2.15), M["amber"], col, 0.05)
        disc("Fog light", (s * 2.45, F - 0.5, 1.08), (0, 1, 0), 0.14, 0.05, M["head"], col)
        x = s * 2.96
        box("Tail light", (0.42, 0.1, 1.2), (x, R + 0.03, 2.9), M["red"], col, 0.05)
        box("Rear indicator", (0.42, 0.1, 0.45), (x, R + 0.03, 2.05), M["amber"], col, 0.05)
        box("Rear reflector", (0.5, 0.04, 0.12), (s * 2.9, R + 0.51, 1.05), M["red"], col, 0.01)
    box("Third brake light", (1.0, 0.06, 0.13), (0, R + 0.02, H - 0.55), M["red"], col, 0.02)


# ───────────────────────────────────────────────────────────── kola
def wheel_mesh():
    k = WHEEL / 1.3
    bm = bmesh.new()

    def spin(outline, pick):
        before = set(bm.faces)
        vs = [bm.verts.new((x * k, 0.0, r * k)) for x, r in outline]
        es = [bm.edges.new((vs[i], vs[(i + 1) % len(vs)])) for i in range(len(vs))]
        bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(1, 0, 0), angle=2 * math.pi, steps=32, use_merge=True)
        for f in set(bm.faces) - before:
            c = f.calc_center_median()
            f.material_index = pick(c.x / k, math.hypot(c.y, c.z) / k)

    # Pneumatika s drážkami vzorku (průřez x, poloměr) a disk s nábojem.
    spin([(-0.5, 0.92), (-0.5, 1.02), (-0.48, 1.12), (-0.43, 1.21), (-0.36, 1.27), (-0.3, 1.3), (-0.17, 1.3), (-0.17, 1.25),
          (-0.11, 1.25), (-0.11, 1.3), (0.11, 1.3), (0.11, 1.25), (0.17, 1.25), (0.17, 1.3), (0.3, 1.3), (0.36, 1.27),
          (0.43, 1.21), (0.48, 1.12), (0.5, 1.02), (0.5, 0.92)], lambda x, r: 0)
    spin([(0.36, 0.94), (0.36, 0.87), (0.27, 0.82), (0.21, 0.73), (0.2, 0.55), (0.25, 0.47), (0.25, 0.33), (0.19, 0.27),
          (0.19, 0.17), (0.29, 0.16), (0.31, 0.0), (-0.28, 0.13), (-0.3, 0.82), (-0.36, 0.87), (-0.36, 0.94)],
         lambda x, r: 2 if r < 0.18 and x > 0.15 else 1)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)

    def parts(count, radius, x, r, depth, seg, index):
        for i in range(count):
            a = 2 * math.pi * i / count
            before = set(bm.faces)
            bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r * k, radius2=r * k, depth=depth * k,
                                  matrix=Matrix.Translation((x * k, radius * k * math.cos(a), radius * k * math.sin(a))) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
            for f in set(bm.faces) - before:
                f.material_index = index

    parts(5, 0.39, 0.27, 0.05, 0.07, 6, 2)     # matice
    parts(6, 0.64, 0.215, 0.09, 0.02, 10, 3)  # otvory v disku
    sharpen(bm, 40)
    me = bpy.data.meshes.new("Wheel")
    bm.to_mesh(me)
    bm.free()
    for m in (M["rubber"], M["rim"], M["chrome"], M["trim"]):
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    return me


def wheels(col):
    me = wheel_mesh()
    for name, x, y in (("Wheel_FL", -TRACK, AXLE_F), ("Wheel_FR", TRACK, AXLE_F), ("Wheel_RL", -TRACK, AXLE_R), ("Wheel_RR", TRACK, AXLE_R)):
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.location = (x, y, WHEEL)
        o.rotation_euler.z = math.pi if x < 0 else 0.0   # vnější strana disku ven
    return me


# ───────────────────────────────────────────────────────────── výbava na apokalypsu
def kit(col, light_col, wheel):
    g = M["gun"]
    y = F - 0.72
    for s in (-1, 1):
        x = s * 1.6
        tube("Bull bar post", (x, y, 0.85), (x, y, 2.75), 0.09, g, col)
        tube("Bull bar mount", (x, y, 0.95), (x, F - 0.3, 0.95), 0.08, g, col)
        tube("Bull bar wing", (x, y, 2.75), (s * 2.95, y + 0.25, 2.75), 0.09, g, col)
        tube("Bull bar wing", (s * 2.95, y + 0.25, 2.75), (s * 2.95, y + 0.25, 1.6), 0.09, g, col)
        tube("Bull bar wing", (s * 2.95, y + 0.25, 1.6), (s * 2.95, F - 0.42, 1.35), 0.09, g, col)
        for p in ((x, y, 2.75), (s * 2.95, y + 0.25, 2.75), (s * 2.95, y + 0.25, 1.6)):
            ball("Bull bar joint", p, 0.09, g, col)
    tube("Bull bar top", (-1.6, y, 2.75), (1.6, y, 2.75), 0.09, g, col)
    tube("Bull bar middle", (-1.6, y, 1.8), (1.6, y, 1.8), 0.08, g, col)
    # Střešní nosič s nákladem.
    z = H + 0.45
    y0, y1 = 0.0, R - 0.4
    for s in (-1, 1):
        tube("Roof rack rail", (s * 2.55, y0, z), (s * 2.55, y1, z), 0.07, g, col)
        for yy in (0.3, 3.0, 5.8):
            box("Roof rack foot", (0.18, 0.3, 0.42), (s * 2.55, yy, H + 0.2), g, col, 0.03)
    for i in range(6):
        yy = y0 + (y1 - y0) * i / 5
        tube("Roof rack bar", (-2.55, yy, z), (2.55, yy, z), 0.055, g, col)
    spare = bpy.data.objects.new("Spare wheel", wheel)
    col.objects.link(spare)
    spare.matrix_world = Matrix.Translation((-1.2, 4.6, z + 0.06 + 0.5 * WHEEL / 1.3)) @ Matrix.Rotation(-math.pi / 2, 4, "Y")
    for x, m in ((0.9, M["can_red"]), (1.5, M["can_olive"])):
        box("Jerry can", (0.5, 1.0, 1.2), (x, 4.6, z + 0.06 + 0.6), m, col, 0.06)
        box("Jerry can handle", (0.12, 0.5, 0.12), (x, 4.45, z + 0.06 + 1.26), g, col, 0.03)
    box("Crate", (1.8, 1.4, 0.9), (1.0, 2.2, z + 0.06 + 0.45), M["wood"], col, 0.04)
    box("Light bar", (3.6, 0.12, 0.1), (0, 0.0, z + 0.08), g, col, 0.02)
    for x in (-1.35, -0.45, 0.45, 1.35):
        disc("Roof light", (x, -0.15, z + 0.25), (0, 1, 0), 0.22, 0.24, M["trim"], col)
        disc("Roof light lens", (x, -0.28, z + 0.25), (0, 1, 0), 0.17, 0.04, M["head"], light_col)


# ───────────────────────────────────────────────────────────── scéna, světla, kamera
VIEWS = {   # pozice kamery pro náhledy
    "front": (-16.5, -21.0, 8.0),
    "rear": (17.0, 19.5, 8.5),
    "side": (24.0, -1.0, 4.2),
}


def studio(col):
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"   # 1 jednotka = 1 stud (doporučení Robloxu pro export FBX)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60)
    mesh_object("Floor", bm, [M["floor"]], col, False)
    target = bpy.data.objects.new("Camera target", None)
    col.objects.link(target)
    target.location = (0, 0.3, 2.8)
    cam = bpy.data.objects.new("Van camera", bpy.data.cameras.new("Van camera"))
    col.objects.link(cam)
    cam.data.lens = 50
    cam.location = VIEWS["front"]
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
        o.rotation_euler = (target.location - Vector(at)).to_track_quat("-Z", "Y").to_euler()
        return o

    lamp("Sun", "SUN", (-9, -14, 18), 3.2)
    lamp("Fill light", "AREA", (16, 8, 9), 2200, 12)
    lamp("Rim light", "AREA", (4, 20, 12), 1500, 8)
    world = scene.world or bpy.data.worlds.new("Van world")
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


def build():
    global CUT
    clear_previous()
    materials()
    root = bpy.data.collections.new("Van")
    bpy.context.scene.collection.children.link(root)
    cols = {k: collection("Van_" + k, root) for k in ("Body", "Wheels", "Lights", "Kit", "Cutters", "Studio")}
    CUT = cols["Cutters"]
    body(cols["Body"])
    lights(cols["Lights"])
    me = wheels(cols["Wheels"])
    if KIT:
        kit(cols["Kit"], cols["Lights"], me)
    studio(cols["Studio"])
    layer = bpy.context.view_layer.layer_collection.children["Van"].children["Van_Cutters"]
    layer.hide_viewport = True   # řezy jsou schované, Boolean je ale používá
    show_in_viewport()
    source = globals().get("__file__", "")
    if os.path.isfile(source) and "van.py" not in bpy.data.texts:   # skript přibalený do .blend (záložka Scripting)
        bpy.data.texts.new("van.py").write(open(source, encoding="utf-8").read())
    return cols


# ───────────────────────────────────────────────────────────── náhledy a export do Robloxu
def render_views(folder, samples=96):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples, scene.cycles.use_denoising = samples, True
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    os.makedirs(folder, exist_ok=True)
    cam = scene.camera
    for name, at in VIEWS.items():
        cam.location = at
        scene.render.filepath = os.path.join(folder, f"van-{name}.png")
        bpy.ops.render.render(write_still=True)
    cam.location = VIEWS["front"]


LIGHT_GROUPS = {"Van Headlight": "Lights_White", "Van Indicator": "Lights_Amber", "Van Taillight": "Lights_Red"}


def export_roblox(folder):
    """FBX pro Roblox: Body, Kit a 4 kola s jednou malou texturou palety; světla zvlášť podle barvy (dej jim Neon)."""
    os.makedirs(folder, exist_ok=True)
    dg = bpy.context.evaluated_depsgraph_get()
    groups = {"Body": list(bpy.data.collections["Van_Body"].objects)}
    if KIT:
        groups["Kit"] = list(bpy.data.collections["Van_Kit"].objects)
    for o in bpy.data.collections["Van_Wheels"].objects:
        groups[o.name] = [o]
    for o in bpy.data.collections["Van_Lights"].objects:
        groups.setdefault(LIGHT_GROUPS[o.active_material.name], []).append(o)
    # Paleta: každý materiál dostane čtvereček 8×8 px v obrázku 64×64.
    used = []
    for name, objs in groups.items():
        for o in objs:
            if not name.startswith("Lights"):
                for slot in o.material_slots:
                    if slot.material and slot.material not in used:
                        used.append(slot.material)
    for c in CUT.objects:
        for slot in c.material_slots:
            if slot.material not in used:
                used.append(slot.material)
    size, cells = 64, 8
    image = bpy.data.images.new("van_palette", size, size)
    pixels = [0.0] * (size * size * 4)
    spot = {}
    for i, m in enumerate(used):
        cx, cy = i % cells, i // cells
        spot[m.name] = ((cx + 0.5) / cells, (cy + 0.5) / cells)
        h = m["palette"].lstrip("#")
        rgb = [int(h[j:j + 2], 16) / 255 for j in (0, 2, 4)]
        for py in range(cy * 8, cy * 8 + 8):
            for px in range(cx * 8, cx * 8 + 8):
                pixels[(py * size + px) * 4:(py * size + px) * 4 + 4] = (*rgb, 1.0)
    image.pixels = pixels
    image.filepath_raw = os.path.join(folder, "van_palette.png")
    image.file_format = "PNG"
    image.save()
    palette = bpy.data.materials.new("VanPalette")
    try:
        palette.use_nodes = True
    except Exception:
        pass
    tex = palette.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = next(n for n in palette.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    palette.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    temp = bpy.data.collections.new("Van_Export")
    bpy.context.scene.collection.children.link(temp)
    taken = [o for o in bpy.data.objects if o.name in groups]   # uvolni jména (Body, Wheel_FL …) pro díly v FBX
    for o in taken:
        o.name += "_src"
    made, report = [], []
    for name, objs in groups.items():
        light = name.startswith("Lights")
        parts = []
        for o in objs:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            while me.uv_layers:
                me.uv_layers.remove(me.uv_layers[0])
            uv = me.uv_layers.new(name="UVMap")
            slots = list(me.materials)
            for poly in me.polygons:
                u, v = spot.get(slots[poly.material_index].name, (0.5, 0.5)) if slots and not light else (0.5, 0.5)
                for li in poly.loop_indices:
                    uv.data[li].uv = (u, v)
                poly.material_index = 0
            keep = o.active_material if light else palette
            me.materials.clear()
            me.materials.append(keep)
            t = bpy.data.objects.new(o.name + "_part", me)
            temp.objects.link(t)
            t.matrix_world = o.matrix_world
            parts.append(t)
        pivot = objs[0].matrix_world.translation if name.startswith("Wheel") else Vector()
        base = bpy.data.objects.new(name, bpy.data.meshes.new(name))
        temp.objects.link(base)
        base.location = pivot
        bpy.context.view_layer.update()
        with bpy.context.temp_override(active_object=base, object=base, selected_objects=parts + [base], selected_editable_objects=parts + [base]):
            bpy.ops.object.join()
        made.append(base)
        report.append((name, sum(len(p.vertices) - 2 for p in base.data.polygons)))
    for o in bpy.context.scene.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.fbx(filepath=os.path.join(folder, "van.fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", path_mode="COPY", embed_textures=True,
                             mesh_smooth_type="OFF", use_mesh_modifiers=True)
    for o in list(temp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(temp)
    for o in taken:
        o.name = o.name[:-4]
    return report


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build()

    def arg(flag):
        return argv[argv.index(flag) + 1] if flag in argv else None

    if arg("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--save")))
    if arg("--render"):
        render_views(arg("--render"), int(arg("--samples") or 96))
    folder = arg("--export") or (EXPORT and os.path.join(os.path.dirname(bpy.data.filepath) or os.path.expanduser("~"), "roblox"))
    if folder:
        for name, tris in export_roblox(folder):
            print(f"{name}: {tris} triangles")
        print("FBX pro Roblox:", os.path.join(os.path.abspath(folder), "van.fbx"))


main()
