"""The game icon's subject (transparent): the hero raises a legendary find over an open ZDC moving box."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import zdk
o = zdk.args()
sc = zdk.reset(o["res"], o["samples"])
sc.render.film_transparent = True
sc.render.image_settings.color_mode = "RGBA"
zdk.sky(zenith=(255, 214, 150), horizon=(255, 236, 200), strength=0.9)
zdk.sun(direction_from=(-0.5, -0.9, 0.7), strength=3.6, color=(255, 244, 228))
zdk.sun(direction_from=(0.8, 0.6, 0.3), strength=2.0, color=(255, 210, 150))  # (the gold rim)
G = zdk.RARITY

zdk.avatar((0.9, 0.6, 0), rot_z=-16, face="grin",
           pose={"arm_r": (-158, 0, 18), "arm_l": (-60, 0, 22), "head": (-6, 0, -6)})
h = zdk.hand("arm_r")
tro, tcol = zdk.piece("furniture", "F_ski_trophy", (h.x, h.y, h.z - 0.35), rot_z=-30, scale=1.15)
for ob in tcol.all_objects:
    for slot in ob.material_slots:
        m = slot.material
        if m and m.use_nodes and any(k in m.name.lower() for k in ("gold", "brass", "gilt")):
            p = m.node_tree.nodes["Principled BSDF"]
            p.inputs["Base Color"].default_value = zdk.lin((255, 214, 110))
            p.inputs["Roughness"].default_value = 0.2
zdk.glow((h.x - 0.4, h.y - 2.2, h.z + 2.0), (255, 226, 160), energy=500, size=1.2)
zdk.moving_box((-2.4, -2.4, 0.0), (2.8, 2.6, 2.2), rot_z=24, open_top=True)  # (low, left: its flaps clear of the face)
zdk.glow((-2.4, -2.4, 1.6), (255, 222, 150), energy=500, size=0.6)
zdk.camera((1.6, -15.5, 5.6), (2.0, 0, 5.9), lens=54)
zdk.render(o["out"])
