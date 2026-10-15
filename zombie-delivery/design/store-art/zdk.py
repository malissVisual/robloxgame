"""ZDC store art kit: shared Blender helpers for the Roblox thumbnails and the icon.

Builds scenes from the game's own Blender models (design/blender-*/*.blend: the ZDC Sprinter, the chalet, the
warehouse levels, the furniture and the collectibles) plus a few things of its own: an alpine sky, a meadow, snowy
mountains, fir trees, moving boxes and a classic blocky Roblox-style avatar in the ZDC crew's clothes.
Rendered with Cycles on the CPU (no GPU needed). Units are studs, Z up.
"""
import math
import os
import random
import sys

import bpy  # (first: bmesh comes with it)
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("ZDC_REPO", os.path.abspath(os.path.join(HERE, "..", "..")))
DESIGN = os.path.join(REPO, "design")
BLENDS = {
    "sprinter": os.path.join(DESIGN, "blender-sprinter", "sprinter.blend"),
    "warehouse": os.path.join(DESIGN, "blender-warehouse", "warehouse.blend"),
    "house": os.path.join(DESIGN, "blender-house", "house.blend"),
    "furniture": os.path.join(DESIGN, "blender-furniture", "furniture.blend"),
}

# The game's colours (sRGB 0-255)
ZDC_RED = (196, 30, 36)
CHARCOAL = (38, 40, 44)
CREAM = (236, 228, 210)
ORANGE = (240, 132, 44)
RARITY = {"common": (178, 182, 188), "uncommon": (92, 196, 104), "rare": (70, 144, 240), "epic": (178, 96, 236),
          "legendary": (255, 178, 36)}  # (Config.Collection.Tiers' colours)


def args():
    """--res W H --samples N --out PATH after "--" on the command line."""
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"res": (1920, 1080), "samples": 96, "out": os.path.join(HERE, "out.png")}
    i = 0
    while i < len(a):
        if a[i] == "--res":
            opts["res"] = (int(a[i + 1]), int(a[i + 2]))
            i += 3
        elif a[i] == "--samples":
            opts["samples"] = int(a[i + 1])
            i += 2
        elif a[i] == "--out":
            opts["out"] = a[i + 1]
            i += 2
        else:
            i += 1
    return opts


def lin(c):
    """sRGB 0-255 → linear RGBA."""
    def f(v):
        v = v / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


# ── the scene ────────────────────────────────────────────────────────────────

def reset(res, samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 3
    sc.cycles.transparent_max_bounces = 12
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.view_settings.view_transform = "AgX"
    for look in ("AgX - Punchy", "AgX - Medium High Contrast", "Punchy"):
        try:
            sc.view_settings.look = look
            break
        except TypeError:
            continue
    return sc


MARKS = {}


def mark(name, at):
    """A point the finishing step labels (a rarity tag, a price): kept with its place on the picture."""
    MARKS[name] = tuple(at)


def render(path):
    """Renders (unless --marks-only) and writes the marks' places on the picture (0…1 from the top left) to .json."""
    import json
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    out = {}
    for name, at in MARKS.items():
        v = world_to_camera_view(sc, sc.camera, Vector(at))
        out[name] = [round(v.x, 4), round(1 - v.y, 4)]
    with open(os.path.splitext(path)[0] + ".json", "w") as f:
        json.dump(out, f, indent=1)
    if "--marks-only" in sys.argv:
        print("marks", out)
        return
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def camera(at, look, lens=35, shift=(0, 0)):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    cam_data.shift_x, cam_data.shift_y = shift
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(at)
    cam.rotation_euler = (Vector(look) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def sky(zenith=(70, 130, 220), horizon=(196, 222, 246), strength=1.0, ground=(120, 150, 110)):
    """A stylised gradient sky (the light it gives is the ambient light)."""
    w = bpy.data.worlds.new("Sky")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -0.15
    mr.inputs["From Max"].default_value = 0.75
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, lin(ground)
    els[1].position, els[1].color = 1.0, lin(zenith)
    e = els.new(0.17)
    e.color = lin(horizon)
    e2 = els.new(0.15)
    e2.color = lin(horizon)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs[0])
    return w


def sun(direction_from=(-0.6, -0.8, 0.55), strength=4.0, color=(255, 240, 214), angle=2.5):
    d = bpy.data.lights.new("Sun", "SUN")
    d.energy = strength
    d.color = lin(color)[:3]
    d.angle = math.radians(angle)
    o = bpy.data.objects.new("Sun", d)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_euler = (-Vector(direction_from)).to_track_quat("-Z", "Y").to_euler()
    return o


def light(kind, at, energy, color=(255, 255, 255), size=1.0, look=None, name="Light"):
    d = bpy.data.lights.new(name, kind)
    d.energy = energy
    d.color = lin(color)[:3]
    if kind == "AREA":
        d.size = size
    elif kind in ("POINT", "SPOT"):
        d.shadow_soft_size = size
    o = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(at)
    if look is not None:
        o.rotation_euler = (Vector(look) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
    return o


# ── materials ────────────────────────────────────────────────────────────────

_mats = {}


def mat(name, color, rough=0.6, metal=0.0, emit=None, emit_strength=0.0, alpha=1.0, spec=0.4):
    key = (name, tuple(color), rough, metal, emit, emit_strength, alpha)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = lin(color)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    for k in ("Specular IOR Level", "Specular"):
        if k in p.inputs:
            p.inputs[k].default_value = spec
            break
    if emit is not None:
        p.inputs["Emission Color"].default_value = lin(emit)
        p.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1:
        p.inputs["Alpha"].default_value = alpha
    _mats[key] = m
    return m


def image_mat(name, path, rough=0.7):
    """A decal: the image's colour, its alpha cut out."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path)
    tex.extension = "CLIP"
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], p.inputs["Alpha"])
    p.inputs["Roughness"].default_value = rough
    return m


def noisy_mat(name, a, b, scale=0.05, rough=0.9, detail=4):
    """Two colours mixed by noise (grass, gravel, asphalt)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = lin(a)
    ramp.color_ramp.elements[1].color = lin(b)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.7
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    return m


def mountain_mat(snowline=0.55, haze=(190, 214, 240)):
    """Rock below, snow above (by the height in the object's own box)."""
    m = bpy.data.materials.new("Mountain")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 6
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "MULTIPLY_ADD"
    add.inputs[1].default_value = 0.12
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, lin((70, 110, 80))
    els[1].position, els[1].color = 1.0, lin((250, 252, 255))
    e = els.new(snowline - 0.02)
    e.color = lin((128, 140, 160))
    e2 = els.new(snowline)
    e2.color = lin((240, 244, 250))
    e3 = els.new(0.25)
    e3.color = lin((106, 124, 128))
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(tc.outputs["Generated"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], add.inputs[0])
    nt.links.new(sep.outputs["Z"], add.inputs[2])
    nt.links.new(add.outputs[0], ramp.inputs["Fac"])
    cam = nt.nodes.new("ShaderNodeCameraData")
    far = nt.nodes.new("ShaderNodeMapRange")
    far.inputs["From Min"].default_value = 300
    far.inputs["From Max"].default_value = 1600
    far.inputs["To Min"].default_value = 0.15
    far.inputs["To Max"].default_value = 0.45
    nt.links.new(cam.outputs["View Distance"], far.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[7].default_value = lin(haze)
    nt.links.new(far.outputs["Result"], mix.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], mix.inputs[6])
    nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    nt.links.new(mix.outputs[2], p.inputs["Emission Color"])
    p.inputs["Emission Strength"].default_value = 0.2
    p.inputs["Roughness"].default_value = 0.95
    return m


# ── meshes ───────────────────────────────────────────────────────────────────

def link(o, parent=None, col=None):
    (col or bpy.context.scene.collection).objects.link(o)
    if parent is not None:
        o.parent = parent
    return o


def empty(name="Root", at=(0, 0, 0), rot_z=0.0, scale=1.0, parent=None):
    o = bpy.data.objects.new(name, None)
    link(o, parent)
    o.location = Vector(at)
    o.rotation_euler.z = math.radians(rot_z)
    o.scale = (scale, scale, scale)
    return o


def box(name, size, at=(0, 0, 0), material=None, bevel=0.0, segments=3, parent=None, rot=(0, 0, 0), origin=(0, 0, 0)):
    """A box of `size` whose point `origin` (in -1…1 of each half size) sits at `at`."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = size
    ox, oy, oz = origin
    for v in bm.verts:
        v.co = Vector((v.co.x * sx - ox * sx / 2, v.co.y * sy - oy * sy / 2, v.co.z * sz - oz * sz / 2))
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    link(o, parent)
    o.location = Vector(at)
    o.rotation_euler = tuple(math.radians(r) for r in rot)
    if material:
        me.materials.append(material)
    if bevel > 0:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "NONE"
        mod.harden_normals = True
        for poly in me.polygons:
            poly.use_smooth = True
    return o


def plane(name, size, at=(0, 0, 0), material=None, rot=(0, 0, 0), parent=None):
    me = bpy.data.meshes.new(name)
    sx, sy = size
    me.from_pydata([(-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0), (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0)], [], [(0, 1, 2, 3)])
    me.uv_layers.new()
    for i, uv in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
        me.uv_layers[0].data[i].uv = uv
    o = bpy.data.objects.new(name, me)
    link(o, parent)
    o.location = Vector(at)
    o.rotation_euler = tuple(math.radians(r) for r in rot)
    if material:
        me.materials.append(material)
    return o


def cylinder(name, r, h, at=(0, 0, 0), material=None, verts=24, parent=None, rot=(0, 0, 0), r2=None):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=h)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, h / 2))
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    o = bpy.data.objects.new(name, me)
    link(o, parent)
    o.location = Vector(at)
    o.rotation_euler = tuple(math.radians(v) for v in rot)
    if material:
        me.materials.append(material)
    return o


def text(name, body, size, at=(0, 0, 0), material=None, rot=(90, 0, 0), extrude=0.02, parent=None, font=None,
         align="CENTER"):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = align
    cu.align_y = "CENTER"
    if font:
        cu.font = bpy.data.fonts.load(font, check_existing=True)
    o = bpy.data.objects.new(name, cu)
    link(o, parent)
    o.location = Vector(at)
    o.rotation_euler = tuple(math.radians(r) for r in rot)
    if material:
        cu.materials.append(material)
    return o


# ── the land ─────────────────────────────────────────────────────────────────

def meadow(size=3000, at=(0, 0, 0)):
    g = plane("Meadow", (size, size), at, noisy_mat("Grass", (86, 150, 70), (122, 178, 82), scale=0.02))
    return g


def road(at, length, width=22, rot_z=0.0):
    r = plane("Road", (width, length), (at[0], at[1], 0.03), noisy_mat("Asphalt", (58, 60, 66), (74, 76, 82), scale=0.3),
              rot=(0, 0, rot_z))
    return r


def mountains(center=(0, 0), radius=900, count=11, seed=3, height=(260, 420), arc=(-70, 70), facing=0.0):
    """A ring of snowy peaks along an arc (degrees, 0 = +Y) round `center`."""
    rnd = random.Random(seed)
    m = mountain_mat()
    out = []
    for i in range(count):
        t = i / max(1, count - 1)
        a = math.radians(facing + arc[0] + (arc[1] - arc[0]) * t + rnd.uniform(-4, 4))
        d = radius * rnd.uniform(0.9, 1.15)
        h = rnd.uniform(*height)
        r = h * rnd.uniform(1.0, 1.5)
        me = bpy.data.meshes.new("Peak")
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, segments=9, radius1=r, radius2=0, depth=h)
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, h / 2))
        bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=2, use_grid_fill=True)
        for v in bm.verts:
            if v.co.z > 1:
                k = rnd.uniform(-0.1, 0.1) * r
                v.co.x += k
                v.co.y += rnd.uniform(-0.1, 0.1) * r
                v.co.z += rnd.uniform(-0.06, 0.06) * h
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new("Peak", me)
        link(o)
        o.location = (center[0] + math.sin(a) * d, center[1] + math.cos(a) * d, -5)
        o.rotation_euler.z = rnd.uniform(0, 6.28)
        me.materials.append(m)
        out.append(o)
    return out


def fir(at, height=26, seed=0):
    rnd = random.Random(seed)
    root = empty("Fir", at)
    cylinder("Trunk", height * 0.05, height * 0.25, (0, 0, 0), mat("Bark", (96, 66, 44), 0.9), parent=root, verts=8)
    green = mat("Needles", (38, 92, 56), 0.85)
    for i, (z, r) in enumerate(((0.18, 0.36), (0.42, 0.28), (0.64, 0.19))):
        cylinder("Crown", height * r, height * 0.42, (0, 0, height * z), green, verts=10, parent=root, r2=0.0)
    root.rotation_euler.z = rnd.uniform(0, 6.28)
    s = rnd.uniform(0.85, 1.15)
    root.scale = (s, s, s)
    return root


def cloud(at, scale=1.0, seed=0):
    rnd = random.Random(seed)
    root = empty("Cloud", at, scale=scale)
    white = mat("Cloud", (255, 255, 255), 1.0, emit=(255, 255, 255), emit_strength=0.25)
    for i in range(7):
        r = rnd.uniform(14, 26)
        me = bpy.data.meshes.new("Puff")
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=r)
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = True
        o = bpy.data.objects.new("Puff", me)
        link(o, root)
        o.location = (rnd.uniform(-40, 40), rnd.uniform(-8, 8), rnd.uniform(-4, 10))
        o.scale = (1.3, 1.0, 0.75)
        me.materials.append(white)
    return root


# ── the game's models ────────────────────────────────────────────────────────

HIDE = ("Cutters", "Volumes", "Studio", "cutters", "Yard", "Garden")


def append(kind, colname):
    """Append one collection (with its children) from a repo .blend; returns a root empty all its parts hang on."""
    with bpy.data.libraries.load(BLENDS[kind], link=False) as (src, dst):
        dst.collections = [colname]
    col = dst.collections[0]
    bpy.context.scene.collection.children.link(col)
    for c in [col] + list(col.children_recursive):
        if any(h in c.name for h in HIDE):
            c.hide_render = True
            c.hide_viewport = True
    root = empty(colname + " root")
    for o in col.all_objects:
        if o.parent is None:
            o.parent = root
    return root, col


def bounds(objs):
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    bpy.context.view_layer.update()
    for o in objs:
        if o.type not in ("MESH", "CURVE", "FONT") or o.hide_render:
            continue
        if any(c.hide_render for c in o.users_collection):
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def piece(kind, colname, at=(0, 0, 0), rot_z=0.0, scale=1.0):
    """A model centred on its footprint, standing on `at`."""
    root, col = append(kind, colname)
    lo, hi = bounds(col.all_objects)
    mid = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for o in root.children:
        o.location -= mid
    root.location = Vector(at)
    root.rotation_euler.z = math.radians(rot_z)
    root.scale = (scale, scale, scale)
    return root, col


def sprinter(at, rot_z=0.0, back_open=True, side_open=False):
    """The ZDC Sprinter (its nose at -Y before turning): back doors open like the game's walk-in van."""
    root, col = append("sprinter", "Sprinter")
    objs = {o.name.split(".")[0]: o for o in col.all_objects}
    if back_open:
        if "BackDoorL" in objs:
            objs["BackDoorL"].rotation_euler.z = math.radians(-105)
        if "BackDoorR" in objs:
            objs["BackDoorR"].rotation_euler.z = math.radians(105)
    root.location = Vector(at)
    root.rotation_euler.z = math.radians(rot_z)
    return root, col


# ── moving boxes ─────────────────────────────────────────────────────────────

def moving_box(at, size=(2.0, 2.0, 1.8), rot_z=0.0, parent=None, open_top=False, logo=True):
    card = mat("Cardboard", (196, 150, 98), 0.85)
    tape = mat("Tape", (214, 176, 120), 0.35)
    red = mat("ZDC red", ZDC_RED, 0.5)
    root = empty("Box", at, rot_z, parent=parent)
    sx, sy, sz = size
    if open_top:
        t = 0.06
        box("Floor", (sx, sy, t), (0, 0, 0), card, origin=(0, 0, -1), parent=root)
        for x in (-1, 1):
            box("Side", (t, sy, sz), (x * (sx / 2 - t / 2), 0, 0), card, origin=(0, 0, -1), parent=root)
        for y in (-1, 1):
            box("Side", (sx, t, sz), (0, y * (sy / 2 - t / 2), 0), card, origin=(0, 0, -1), parent=root)
        for x, rot in ((-1, -115), (1, 115)):
            f = box("Flap", (sx / 2, sy * 0.98, t), (x * sx / 2, 0, sz), card, origin=(-x, 0, -1), parent=root)
            f.rotation_euler.y = math.radians(rot * -x / abs(x) * -1)
        for y, rot in ((-1, 120), (1, -120)):
            f = box("Flap", (sx * 0.98, sy / 2, t), (0, y * sy / 2, sz), card, origin=(0, -y, -1), parent=root)
            f.rotation_euler.x = math.radians(-rot * -1)
    else:
        box("Carton", (sx, sy, sz), (0, 0, 0), card, bevel=0.04, origin=(0, 0, -1), parent=root)
        box("Tape", (sx * 0.22, sy + 0.02, 0.02), (0, 0, sz), tape, origin=(0, 0, 0), parent=root)
        box("Tape side", (sx * 0.22, 0.02, sz * 0.3), (0, -sy / 2 - 0.005, sz * 0.85), tape, parent=root)
    if logo:
        text("Logo", "ZDC", min(sx, sz) * 0.32, (0, -sy / 2 - 0.02, sz * 0.45), red, rot=(90, 0, 0), extrude=0.005,
             parent=root, font=os.path.join(HERE, "fonts", "LilitaOne-Regular.ttf"))
    return root


# ── the avatar ───────────────────────────────────────────────────────────────

FACES = {}


def face_png(kind):
    """A Roblox-ish face drawn with PIL (transparent), cached as a PNG next to this file."""
    if kind in FACES:
        return FACES[kind]
    from PIL import Image, ImageDraw
    n = 512
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ink = (24, 22, 24, 255)
    ey = 200
    if kind in ("happy", "grin"):
        for x in (170, 342):
            d.ellipse((x - 30, ey - 46, x + 30, ey + 46), fill=ink)
            d.ellipse((x - 14, ey - 32, x + 4, ey - 10), fill=(255, 255, 255, 255))
        if kind == "grin":
            d.chord((140, 250, 372, 430), 0, 180, fill=ink)
            d.chord((176, 262, 336, 330), 0, 180, fill=(255, 255, 255, 255))
            d.ellipse((216, 360, 296, 420), fill=(214, 82, 92, 255))
        else:
            d.arc((160, 250, 352, 380), 20, 160, fill=ink, width=22)
    elif kind == "wow":
        for x in (170, 342):
            d.ellipse((x - 40, ey - 54, x + 40, ey + 54), fill=(255, 255, 255, 255), outline=ink, width=10)
            d.ellipse((x - 22, ey - 22, x + 22, ey + 30), fill=ink)
            d.ellipse((x - 10, ey - 14, x + 2, ey - 2), fill=(255, 255, 255, 255))
        d.arc((120, 90, 220, 150), 200, 340, fill=ink, width=16)
        d.arc((292, 90, 392, 150), 200, 340, fill=ink, width=16)
        d.ellipse((206, 300, 306, 430), fill=ink)
        d.ellipse((226, 360, 286, 420), fill=(214, 82, 92, 255))
    elif kind == "determined":
        for x in (170, 342):
            d.ellipse((x - 28, ey - 36, x + 28, ey + 40), fill=ink)
            d.ellipse((x - 12, ey - 24, x + 2, ey - 8), fill=(255, 255, 255, 255))
        d.line((120, 130, 214, 156), fill=ink, width=20)
        d.line((298, 156, 392, 130), fill=ink, width=20)
        d.chord((176, 290, 336, 400), 0, 180, fill=ink)
        d.rectangle((186, 300, 326, 322), fill=(255, 255, 255, 255))
    import tempfile
    path = os.path.join(tempfile.gettempdir(), f"zdc_face_{kind}.png")
    im.save(path)
    FACES[kind] = path
    return path


def avatar(at, rot_z=0.0, skin=(234, 184, 146), shirt=ZDC_RED, pants=CHARCOAL, face="happy", cap=CHARCOAL,
           pose=None, logo=True, scale=1.0, shoes=(30, 30, 34)):
    """A classic blocky avatar (head 1.2, torso 2 x 2 x 1, limbs 1 x 2 x 1; 5.2 studs tall), facing -Y before turning.
    pose: degrees {"arm_l": (x, y, z), "arm_r": …, "leg_l": …, "leg_r": …, "head": …, "lean": x}; arm (-90, 0, 0)
    points forward."""
    pose = pose or {}
    root = empty("Avatar", at, rot_z, scale=scale)
    skin_m = mat("Skin", skin, 0.55)
    shirt_m = mat("Shirt", shirt, 0.7)
    pants_m = mat("Pants", pants, 0.75)
    shoe_m = mat("Shoes", shoes, 0.6)
    hips = empty("Hips", (0, 0, 2.0), parent=root)
    lean = pose.get("lean", 0)
    hips.rotation_euler.x = math.radians(lean)
    torso = box("Torso", (2.0, 1.0, 2.0), (0, 0, 0), shirt_m, bevel=0.08, origin=(0, 0, -1), parent=hips)
    if logo:
        text("Logo", "ZDC", 0.62, (0, -0.52, 1.22), mat("Logo white", (250, 250, 250), 0.5), rot=(90, 0, 0),
             extrude=0.01, parent=torso, font=os.path.join(HERE, "fonts", "LilitaOne-Regular.ttf"))
    neck = empty("Neck", (0, 0, 2.0), parent=hips)
    neck.rotation_euler = tuple(math.radians(v) for v in pose.get("head", (0, 0, 0)))
    H = 1.5  # (the thumbnails' head: a little bigger than the game's 1.2)
    box("Head", (H, H, H), (0, 0, 0), skin_m, bevel=0.28, segments=4, origin=(0, 0, -1), parent=neck)
    plane("Face", (H * 0.92, H * 0.92), (0, -H / 2 - 0.006, H * 0.47), image_mat("Face " + face, face_png(face)), rot=(90, 0, 0),
          parent=neck)
    if cap:
        cap_m = mat("Cap", cap, 0.6)
        box("Cap", (H + 0.08, H + 0.08, 0.5), (0, 0, H * 0.82), cap_m, bevel=0.2, segments=4, origin=(0, 0, -1), parent=neck)
        box("Brim", (H * 0.9, 0.8, 0.09), (0, -H / 2 - 0.3, H * 0.86), cap_m, bevel=0.03, parent=neck)
        text("Cap logo", "ZDC", 0.32, (0, -H / 2 - 0.045, H * 0.82 + 0.25), mat("ZDC red", ZDC_RED, 0.5), rot=(90, 0, 0),
             extrude=0.005, parent=neck, font=os.path.join(HERE, "fonts", "LilitaOne-Regular.ttf"))
    for side, key in ((-1, "arm_l"), (1, "arm_r")):
        sh = empty("Shoulder", (side * 1.5, 0, 1.75), parent=hips)
        LAST[key] = sh
        sh.rotation_euler = tuple(math.radians(v) for v in pose.get(key, (0, 0, side * -4)))
        box("Sleeve", (0.98, 0.98, 0.9), (0, 0, 0.25), shirt_m, bevel=0.06, origin=(0, 0, 1), parent=sh)
        box("Arm", (0.94, 0.94, 1.35), (0, 0, -0.62), skin_m, bevel=0.1, origin=(0, 0, 1), parent=sh)
    for side, key in ((-1, "leg_l"), (1, "leg_r")):
        hp = empty("Hip", (side * 0.5, 0, 0.05), parent=hips)
        hp.rotation_euler = tuple(math.radians(v) for v in pose.get(key, (0, 0, 0)))
        box("Leg", (0.98, 0.98, 1.75), (0, 0, 0), pants_m, bevel=0.06, origin=(0, 0, 1), parent=hp)
        box("Shoe", (1.0, 1.1, 0.32), (0, -0.05, -1.72), shoe_m, bevel=0.08, origin=(0, 0, 1), parent=hp)
    return root


LAST = {}  # the last avatar's shoulders (hand())


def hand(key="arm_r"):
    """Where the last avatar's hand (its arm's end) is in the world."""
    bpy.context.view_layer.update()
    return LAST[key].matrix_world @ Vector((0, 0, -2.0))


def glow(at, color, energy=600, size=2.0):
    """A coloured light where a precious piece stands (the post step adds the bloom)."""
    return light("POINT", at, energy, color, size, name="Glow")


def aura(at, radius, color, strength=6.0, facing=(0, -1, 0)):
    """A soft glowing disc behind a precious piece (a radial gradient of light, see-through at its rim)."""
    m = bpy.data.materials.new("Aura")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (2, 2, 1)
    mp.inputs["Location"].default_value = (-1, -1, 0)
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    ramp.color_ramp.interpolation = "EASE"
    mid = ramp.color_ramp.elements.new(0.3)
    mid.color = (0.18, 0.18, 0.18, 1)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = lin(color)
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    o = plane("Aura", (radius * 2, radius * 2), at, m)
    o.rotation_euler = Vector(facing).to_track_quat("Z", "Y").to_euler()
    o.visible_shadow = False
    return o
