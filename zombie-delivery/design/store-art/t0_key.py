"""Thumbnail 0 (the title card): the Logistics Center at golden hour, the van unloading, the crew carrying a
legendary find in; the sky above is left for the DELIVEROS logo."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zdk
o = zdk.args()
zdk.reset(o["res"], o["samples"])
zdk.sky(zenith=(44, 108, 214), horizon=(196, 222, 248), strength=1.0)
zdk.sun(direction_from=(-0.8, -0.5, 0.36), strength=5.2, color=(255, 222, 176))
zdk.sun(direction_from=(0.6, 0.8, 0.4), strength=1.2, color=(200, 220, 255))
zdk.meadow()
wh, col = zdk.append("warehouse", "Level 5")
lo, hi = zdk.bounds(col.all_objects)
cx = (lo.x + hi.x) / 2
fy = lo.y  # (its front)
G = zdk.RARITY
zdk.plane("Yard", (150, 70), (cx, fy - 32, 0.02), zdk.noisy_mat("Concrete", (168, 166, 158), (186, 184, 176), scale=0.4))
zdk.road((cx, fy - 80, 0), 1400, width=20, rot_z=90)
zdk.mountains(center=(cx, fy), radius=1050, count=13, arc=(-80, 80), height=(320, 500), seed=11)
for i, (x, y) in enumerate(((-75, 10), (-90, 50), (78, 20), (95, 60), (-60, 90), (70, 100))):
    zdk.fir((cx + x, fy + y, 0), height=26 + (i % 3) * 6, seed=20 + i)
for i, (x, z) in enumerate(((-420, 300), (260, 340))):
    zdk.cloud((cx + x, fy + 1300, z), scale=1.7, seed=5 + i)

# the van backed up to the roller door, its back open
van, _ = zdk.sprinter((cx + 16, fy - 30, 0), rot_z=24)
zdk.moving_box((1.4, 7.2, 2.25), (2.2, 2.0, 2.0), rot_z=8, parent=van)
zdk.moving_box((-1.5, 7.5, 2.25), (2.0, 2.0, 1.8), rot_z=-6, parent=van)

# two of the crew carry a legendary find in (the two-person lift), glowing
SX, SY = cx + 1.0, fy - 47.0
zdk.piece("furniture", "F_trex_skull", (SX, SY, 2.0), rot_z=-8, scale=1.35)
zdk.aura((SX, SY + 2.6, 4.2), 5.0, G["legendary"], strength=2.6)
zdk.mark("skull", (SX, SY, 6.4))
zdk.glow((SX, SY - 2.5, 5.0), (255, 216, 140), energy=600, size=1.2)
zdk.avatar((SX + 4.6, SY - 0.4, 0), rot_z=-10, face="grin", shirt=(240, 132, 44), skin=(140, 96, 70), cap=None,
           pose={"arm_l": (-30, 50, 0), "arm_r": (-45, -10, 0), "leg_l": (16, 0, 0), "leg_r": (-16, 0, 0)})
zdk.avatar((SX - 4.6, SY + 0.2, 0), rot_z=4, face="wow", shirt=(46, 140, 92), skin=(250, 214, 170), cap=(30, 70, 140),
           pose={"arm_r": (-30, -50, 0), "arm_l": (-45, 10, 0), "leg_l": (-16, 0, 0), "leg_r": (16, 0, 0)})

# the owner in front, waving the camera in
zdk.avatar((cx - 35.5, fy - 69.0, 0), rot_z=-24, face="grin",
           pose={"arm_r": (-165, 0, 22), "arm_l": (-20, 0, -10), "head": (-6, 0, 0), "leg_l": (6, 0, 0), "leg_r": (-6, 0, 0)})
zdk.moving_box((cx - 41.0, fy - 66.5, 0), (2.4, 2.2, 2.0), rot_z=-14)
zdk.moving_box((cx - 40.6, fy - 66.6, 2.0), (1.8, 1.8, 1.5), rot_z=8)
zdk.moving_box((cx - 43.8, fy - 65.0, 0), (2.0, 2.0, 1.8), rot_z=22)

zdk.camera((cx - 40.0, fy - 95.0, 4.8), (cx - 2.0, fy, 24.0), lens=30)
zdk.render(o["out"])
