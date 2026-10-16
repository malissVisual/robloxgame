"""The second icon's subject (transparent): an open ZDC moving box glowing gold, the legendary trophy rising out."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zdk
o = zdk.args()
sc = zdk.reset(o["res"], o["samples"])
sc.render.film_transparent = True
sc.render.image_settings.color_mode = "RGBA"
zdk.sky(zenith=(255, 220, 160), horizon=(255, 238, 210), strength=0.9)
zdk.sun(direction_from=(-0.5, -0.9, 0.8), strength=3.4, color=(255, 244, 228))
zdk.sun(direction_from=(0.8, 0.5, 0.3), strength=1.8, color=(255, 210, 150))
G = zdk.RARITY
zdk.moving_box((0, 0, 0), (3.6, 3.2, 2.6), rot_z=-24, open_top=True)
zdk.glow((0, 0, 1.8), (255, 224, 150), energy=900, size=0.8)
tro, tcol = zdk.piece("furniture", "F_ski_trophy", (0.05, 0.0, 2.85), rot_z=-30, scale=1.35)
for ob in tcol.all_objects:
    for slot in ob.material_slots:
        m = slot.material
        if m and m.use_nodes and any(k in m.name.lower() for k in ("gold", "brass", "gilt")):
            p = m.node_tree.nodes["Principled BSDF"]
            p.inputs["Base Color"].default_value = zdk.lin((255, 214, 110))
            p.inputs["Roughness"].default_value = 0.2
zdk.glow((0.4, -2.4, 5.2), (255, 232, 180), energy=380, size=1.2)
zdk.aura((0.0, 1.6, 5.0), 4.6, G["legendary"], strength=3.0)
zdk.camera((0.0, -16.5, 8.0), (0.0, 0.0, 3.8), lens=50)
zdk.render(o["out"])
