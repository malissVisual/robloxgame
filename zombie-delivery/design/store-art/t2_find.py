"""Thumbnail 2: FIND RARE ITEMS. In the chalet's dim living room a moving box opens on a legendary find."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zdk
o = zdk.args()
zdk.reset(o["res"], o["samples"])
zdk.sky(zenith=(40, 70, 140), horizon=(120, 150, 200), strength=0.25)
room, col = zdk.append("furniture", "Room")
for ob in col.all_objects:
    if ob.type == "LIGHT":
        ob.data.energy *= 0.3
zdk.plane("Ceiling", (27, 19), (0, 40, 12), zdk.mat("Ceiling", (244, 240, 230), 0.9), rot=(180, 0, 0))
G = zdk.RARITY


def golden(col, color=(255, 214, 110)):
    """The appended piece's gold parts made a brighter, cleaner gold."""
    for ob in col.all_objects:
        for slot in getattr(ob, "material_slots", []):
            m = slot.material
            if m and m.use_nodes and any(k in m.name.lower() for k in ("gold", "brass", "gilt")):
                p = m.node_tree.nodes.get("Principled BSDF")
                if p:
                    p.inputs["Base Color"].default_value = zdk.lin(color)
                    p.inputs["Metallic"].default_value = 1.0
                    p.inputs["Roughness"].default_value = 0.22


# the box, open, its light pouring up; the trophy rising out of it
BX = (-2.0, 37.0)
zdk.moving_box((BX[0], BX[1], 0), (3.0, 2.8, 2.3), rot_z=10, open_top=True)
zdk.glow((BX[0], BX[1], 1.5), (255, 222, 150), energy=1400, size=0.8)
zdk.glow((BX[0] + 0.5, BX[1] - 1.8, 4.2), (255, 232, 180), energy=500, size=1.2)
tro, tcol = zdk.piece("furniture", "F_ski_trophy", (BX[0] + 0.05, BX[1] - 0.1, 2.75), rot_z=-14, scale=1.05)
golden(tcol)
zdk.mark("trophy", (BX[0], BX[1] - 0.1, 7.6))
zdk.aura((BX[0], BX[1] + 1.2, 4.6), 4.0, G["legendary"], strength=4.0)

# the hero beside it, astonished
zdk.avatar((2.6, 37.6, 0), rot_z=28, face="wow",
           pose={"arm_l": (-150, 0, -30), "arm_r": (-150, 0, 30), "lean": -6, "head": (-6, 0, 10)})

# more finds round the room, each glowing its rarity
zdk.piece("furniture", "F_zombie_safe", (-7.6, 40.0, 0), rot_z=30)
zdk.mark("safe", (-7.6, 40.0, 4.0))
zdk.aura((-7.6, 41.4, 2.0), 3.0, G["legendary"], strength=1.6)
zdk.glow((-6.8, 38.0, 2.4), G["legendary"], energy=200, size=1.0)
zdk.piece("furniture", "F_signed_guitar", (7.0, 39.6, 0), rot_z=-30, scale=1.1)
zdk.mark("guitar", (7.0, 39.6, 4.95))
zdk.aura((7.0, 40.8, 2.6), 3.0, G["epic"], strength=2.4)
zdk.glow((6.4, 37.8, 2.6), G["epic"], energy=200, size=1.0)
zdk.piece("furniture", "F_gramophone", (5.0, 34.8, 0), rot_z=-40, scale=0.9)
zdk.mark("gramophone", (5.0, 34.8, 2.55))
zdk.aura((5.0, 36.0, 1.5), 2.0, G["rare"], strength=2.0)
zdk.glow((4.8, 33.6, 1.8), G["rare"], energy=110, size=0.8)
zdk.moving_box((-6.0, 33.8, 0), (2.0, 2.0, 1.7), rot_z=-18)

# a cool rim from behind, a soft fill from the front
zdk.light("AREA", (-6, 46, 9), 500, (150, 180, 255), size=6, look=(0, 39, 4))
zdk.light("AREA", (3, 28, 6), 120, (255, 236, 214), size=6, look=(0, 38, 4))
zdk.camera((0.0, 24.6, 3.4), (0.0, 38, 4.4), lens=26)
zdk.render(o["out"])
