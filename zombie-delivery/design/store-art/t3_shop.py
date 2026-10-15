"""Thumbnail 3: BUILD YOUR WAREHOUSE. Inside the Logistics Center the collection stands on show and earns."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zdk
o = zdk.args()
zdk.reset(o["res"], o["samples"])
zdk.sky(zenith=(60, 120, 220), horizon=(196, 222, 246), strength=0.8)
zdk.sun(direction_from=(-0.5, -0.7, 0.6), strength=3.0)
zdk.meadow()
wh, col = zdk.append("warehouse", "Level 5")
lo, hi = zdk.bounds(col.all_objects)
cx = (lo.x + hi.x) / 2
G = zdk.RARITY

# the hall's light
for ix in (-30, 0, 30):
    for iy in (16, 40, 64):
        zdk.light("AREA", (cx + ix, iy, 24), 5200, (255, 246, 232), size=18, look=(cx + ix, iy, 0))

# the stands: 3 rows of 4, the 8.3 collectibles on show, each stand's trim in its rarity
SHOW = [
    [("F_signed_guitar", "epic", 1.5, -10), ("F_trex_skull", "legendary", 1.5, 25), ("F_ski_trophy", "legendary", 1.6, -15),
     ("F_gramophone", "rare", 1.6, -40)],
    [("F_zombie_safe", "legendary", 1.4, 25), ("F_crystal_chandelier", "epic", 1.6, 0), ("F_golden_horseshoe", "rare", 1.8, -10),
     ("F_alphorn", "epic", 1.1, 30)],
    [("F_antique_typewriter", "uncommon", 2.0, 15), ("F_pocket_watch", "rare", 2.2, 0), ("F_carved_bear", "uncommon", 1.7, -10),
     ("F_vintage_camera", "uncommon", 1.5, -20)],
]
podium = zdk.mat("Podium", (70, 74, 82), 0.45)
top_m = zdk.mat("Podium top", (226, 228, 232), 0.35)
for r, row in enumerate(SHOW):
    y = 22 + r * 12.5
    for c, (name, rarity, scale, rot) in enumerate(row):
        x = cx + (-19.5 + c * 13)
        zdk.box("Stand", (8.0, 8.0, 1.2), (x, y, 0), podium, bevel=0.15, origin=(0, 0, -1))
        zdk.box("Stand top", (7.4, 7.4, 0.1), (x, y, 1.2), top_m, bevel=0.05, origin=(0, 0, -1))
        trim = zdk.mat("Trim " + rarity, G[rarity], 0.4, emit=G[rarity], emit_strength=6.0)
        zdk.box("Trim", (8.08, 8.08, 0.16), (x, y, 0.95), trim, origin=(0, 0, 0))
        _, pcol = zdk.piece("furniture", name, (x, y, 1.3), rot_z=rot, scale=scale)
        lo2, hi2 = zdk.bounds(pcol.all_objects)
        zdk.mark(f"{name}|{rarity}", (x, y, hi2.z + 0.9))
        zdk.light("SPOT", (x, y - 4, 16), 2600 if rarity == "legendary" else 1600, G[rarity], size=0.8, look=(x, y, 2))
        if rarity in ("legendary", "epic"):
            zdk.aura((x, y + 3.6, 3.6), 4.2, G[rarity], strength=2.2 if rarity == "legendary" else 1.6)

# the owner, proud of it
zdk.avatar((cx + 7.6, 9.8, 0), rot_z=-26, face="grin",
           pose={"arm_l": (-160, 0, -25), "arm_r": (-160, 0, 25), "head": (-6, 0, 0)})
zdk.light("AREA", (cx + 2, -4, 12), 2500, (255, 240, 224), size=16, look=(cx + 4, 20, 3))

zdk.camera((cx - 1.5, 0.0, 6.2), (cx + 1.0, 36, 4.3), lens=21)
zdk.render(o["out"])
