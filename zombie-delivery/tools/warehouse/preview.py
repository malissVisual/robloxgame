"""8.2: design/blender-warehouse/warehouse-preview.png: the warehouse as the game shows it once ZDCWarehouseArt is imported:
the Blender model's level (Config.Warehouse.ArtLevel, 4) with what the game keeps in it (the stands, the UPGRADES desk,
the STOCK board, the owner's sign, the floor's paint, the bay), from outside and from inside. Needs bpy (pip install
bpy, Python 3.13) and Pillow:

    python tools/warehouse/preview.py -- --out design/blender-warehouse/warehouse-preview.png --samples 64

It runs design/blender-warehouse/warehouse.py (all five levels), hides the other levels and adds the game's parts
(only for the picture: shared/WarehouseLayout.luau's numbers, Config.Warehouse's 12 stands).
"""
import math
import os
import runpy
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "design/blender-warehouse/warehouse.py"
LEVEL = 4
FLOOR_TOP = 0.05


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def arg(flag, default=None):
        return argv[argv.index(flag) + 1] if flag in argv else default
    return arg("--out", str(ROOT / "design/blender-warehouse/warehouse-preview.png")), int(arg("--samples", "64")), int(arg("--percent", "100"))


def linear(hexcode):
    h = hexcode.lstrip("#")
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)))


def material(name, hexcode, rough=0.8, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    rgba = (*linear(hexcode), 1.0)
    p.inputs["Base Color"].default_value = rgba
    p.inputs["Roughness"].default_value = rough
    if emit:
        (p.inputs.get("Emission Color") or p.inputs.get("Emission")).default_value = rgba
        p.inputs["Emission Strength"].default_value = emit
    return m


def main():
    out, samples, percent = args()
    sys.argv = [str(SCRIPT), "--"]  # (build only: no save, no export)
    runpy.run_path(str(SCRIPT), run_name="warehouse")
    sc = bpy.context.scene
    origin = Vector(bpy.data.collections[f"Level {LEVEL}"]["origin"])
    # (the game's looks are smooth plastic but the trusses, rails and gutters: server/WarehouseMesh.luau LOOKS)
    for m in bpy.data.materials:
        if m.name.startswith("W ") and m.get("finish") not in ("steel", "zinc") and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    n.inputs["Metallic"].default_value = 0.0
    for c in bpy.data.collections:
        if c.name.startswith("Level ") and c.name != f"Level {LEVEL}":
            c.hide_render = True
    hz = 30.0

    def at(x, y, z):
        """The game's warehouse frame (its middle on the ground, x east, z south: the door's side) → Blender's."""
        return Vector((origin.x + x, hz - z, y))

    col = bpy.data.collections.new("Hra (jen náhled)")
    sc.collection.children.link(col)
    mats = {k: material("P " + k, *v) for k, v in {
        "podium": ("#32353A", 0.6), "felt": ("#CAC4B8", 0.95), "paint": ("#F2C62A", 0.6), "board": ("#2A2D32", 0.5),
        "screen": ("#F0842C", 0.4, 2.0), "orange": ("#F0842C", 0.5, 1.0), "white": ("#EEEEE8", 0.5, 1.5), "grey": ("#B0B4BA", 0.5),
        "box": ("#C49E6C", 0.8), "pad": ("#B9B5AD", 0.9),
    }.items()}

    def block(name, lo, hi, finish):
        a, b = at(*lo), at(*hi)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector([abs(p - q) for p, q in zip(a, b)]), verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mats[finish])
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.location = (a + b) / 2
        return o

    def words(name, body, centre, height, finish):
        cu = bpy.data.curves.new(name, "FONT")
        cu.body, cu.size, cu.align_x, cu.align_y, cu.extrude = body, height, "CENTER", "CENTER", 0.01
        cu.materials.append(mats[finish])
        o = bpy.data.objects.new(name, cu)
        col.objects.link(o)
        o.location = at(*centre)
        o.rotation_euler = (math.pi / 2, 0, 0)  # (upright, read from the south)
    # the plot's concrete under and round the warehouse
    block("Pozemek", (-60, -0.06, -60), (60, -0.01, 82), "pad")
    # the stands (Config.Warehouse: 12, 4 a row, 10 × 10, an aisle of 5, the middle aisle 18, the receiving zone 9)
    for row in range(3):
        for x in (-29.0, -14.0, 14.0, 29.0):
            z = 10.0 - 15.0 * row
            block("Stojan", (x - 5, FLOOR_TOP, z - 5), (x + 5, FLOOR_TOP + 0.9, z + 5), "podium")
            block("Stojan", (x - 4.7, FLOOR_TOP + 0.9, z - 4.7), (x + 4.7, FLOOR_TOP + 1.0, z + 4.7), "felt")
    for x, z, sx, sy, sz in ((-29, 10, 3, 2.2, 2), (14, -5, 2.4, 3.4, 2.4), (29, -20, 4, 1.6, 3), (-14, -20, 2, 2.6, 2), (14, 10, 3, 1.4, 4)):
        block("Věc na stojanu", (x - sx / 2, 1.05, z - sz / 2), (x + sx / 2, 1.05 + sy, z + sz / 2), "box")
    # the floor's paint: the receiving zone and the middle aisle's lines; the bay outside
    y0, y1 = FLOOR_TOP, FLOOR_TOP + 0.04
    block("Čára", (-13, y0, 20.0), (13, y1, 20.4), "paint")
    block("Čára", (-13, y0, 28.6), (13, y1, 29.0), "paint")
    for side in (-1, 1):
        block("Čára", (side * 12.6, y0, 20), (side * 13, y1, 29), "paint")
        block("Čára", (side * 8.35, y0, -29), (side * 8.65, y1, 20), "paint")
    for x0, x1, z0, z1 in ((-7, -6.5, 32, 62), (6.5, 7, 32, 62), (-7, 7, 32, 32.5), (-7, 7, 61.5, 62)):
        block("Čára", (x0, 0.0, z0), (x1, 0.06, z1), "paint")
    # the UPGRADES desk, its sign and the STOCK board on the back wall; the owner's sign over the door
    block("Pult", (-3.0, FLOOR_TOP, -29.0), (3.0, 3.05, -26.6), "board")
    block("Pult", (-3.2, 3.05, -29.0), (3.2, 3.25, -26.2), "grey")
    block("Monitor", (-1.9, 4.1, -28.0), (1.9, 6.4, -27.7), "screen")
    block("UPGRADES", (-6, 7.8, -29.0), (6, 10.2, -28.7), "board")
    block("STOCK", (-11, 10.5, -29.0), (11, 16.5, -28.7), "board")
    block("Cedule majitele", (-12, 18.2, hz + 0.3), (12, 21.8, hz + 0.7), "board")
    words("Nápis", "STOCK", (0, 15.0, -28.68), 1.8, "orange")
    words("Nápis", "7 pieces in stock · $42/min", (0, 12.6, -28.68), 0.9, "white")
    words("Nápis", "UPGRADES", (0, 9.0, -28.68), 1.2, "orange")
    words("Nápis", "YOUR NAME'S WAREHOUSE", (0, 20.4, hz + 0.72), 1.6, "white")
    words("Nápis", "ZDC STORAGE · PLOT 1", (0, 18.95, hz + 0.72), 0.6, "orange")
    # the hall's light (in the game: the PointLights of the lamps WarehouseLayout lays out)
    for z in (-14.0, 8.0):
        for x in (-21.5, 0.0, 21.5):
            lamp = bpy.data.objects.new("Světlo lampy", bpy.data.lights.new("Světlo lampy", "POINT"))
            col.objects.link(lamp)
            lamp.data.energy, lamp.data.shadow_soft_size, lamp.data.color = 14000, 1.5, (1.0, 0.93, 0.84)
            lamp.location = at(x, 22.2, z)
    # two cameras: outside from the south-west (the door, the ZDC letters, the office), inside from the door
    for name, eye, target, lens in (("Náhled venku", (-86, 30, 96), (-6, 11, 2), 30), ("Náhled uvnitř", (-6, 9.5, 27.5), (2, 8.5, -20), 16)):
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        col.objects.link(cam)
        cam.location = at(*eye)
        cam.rotation_euler = (at(*target) - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens, cam.data.clip_end = lens, 3000
    sc.render.engine = "CYCLES"
    sc.cycles.samples, sc.cycles.use_denoising, sc.cycles.max_bounces = samples, True, 6
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 1200, 800, percent
    folder = Path(out).with_suffix("")
    folder.mkdir(parents=True, exist_ok=True)
    shots = []
    for name in ("Náhled venku", "Náhled uvnitř"):
        sc.camera = bpy.data.objects[name]
        sc.render.filepath = str(folder / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        shots.append(sc.render.filepath)
    from PIL import Image, ImageDraw, ImageFont
    images = [Image.open(p).convert("RGB") for p in shots]
    w, h = images[0].size
    canvas = Image.new("RGB", (2 * w + 30, h + 80), (26, 29, 33))
    draw = ImageDraw.Draw(canvas)
    font = None
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "C:/Windows/Fonts/arial.ttf"):
        if os.path.exists(path):
            font = ImageFont.truetype(path, max(14, int(30 * percent / 100)))
            break
    draw.rectangle((16, 16, 22, 54), fill=(232, 118, 43))
    draw.text((34, 14), f"ZDC WAREHOUSE · LEVEL {LEVEL} IN THE GAME · 80 × 24 × 60 · FROM BLENDER", font=font or ImageFont.load_default(), fill=(236, 236, 236))
    for i, image in enumerate(images):
        canvas.paste(image, (10 + i * (w + 10), 70))
    canvas.save(out)
    for p in shots:
        os.remove(p)
    folder.rmdir()
    print("Preview:", out)


main()
