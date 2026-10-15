"""Thumbnail 1: MOVE HOUSES. The crew empties the chalet into the ZDC Sprinter under the Alps."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zdk
o = zdk.args()
zdk.reset(o["res"], o["samples"])
zdk.sky(zenith=(48, 112, 214), horizon=(186, 216, 246))
zdk.sun(direction_from=(-0.8, -0.45, 0.5), strength=4.5, color=(255, 232, 200))
zdk.meadow()
zdk.sun(direction_from=(0.7, 0.8, 0.45), strength=1.6, color=(220, 232, 255))  # (the rim from behind)
zdk.road((0, -40, 0), 1200, width=18, rot_z=90)
# gravel path from the chalet's door
zdk.plane("Path", (6, 40), (-18, 14, 0.02), zdk.noisy_mat("Gravel", (176, 170, 158), (198, 192, 180), scale=0.8))

# the chalet and the land round it
zdk.piece("house", "House", (-18, 54, 0))
for i, (x, y) in enumerate(((-58, 40), (-70, 70), (32, 72), (52, 46), (70, 90), (-46, 96), (8, 110), (95, 40))):
    zdk.fir((x, y, 0), height=24 + (i % 3) * 5, seed=i)
zdk.mountains(center=(0, 0), radius=1000, count=13, arc=(-75, 75), height=(300, 480), seed=7)
for i, (x, z) in enumerate(((-380, 260), (160, 300), (520, 230))):
    zdk.cloud((x, 1300, z), scale=1.6, seed=i)

# the van, its back open toward the camera, half loaded
van, _ = zdk.sprinter((19.5, 17, 0), rot_z=146)
zdk.moving_box((1.5, 7.0, 2.25), (2.2, 2.0, 2.0), rot_z=8, parent=van)
zdk.moving_box((-1.6, 7.6, 2.25), (2.0, 2.0, 1.8), rot_z=-6, parent=van)
zdk.moving_box((1.4, 7.2, 4.27), (1.8, 1.8, 1.5), rot_z=20, parent=van)
arm, _ = zdk.piece("furniture", "F_armchair", (0, 2.5, 2.25), rot_z=180)
arm.parent = van
arm.location = (0, 2.5, 2.25)

# the crew: two carry the sofa (the two-person lift), the hero brings a box
zdk.piece("furniture", "F_sofa", (-5.0, 3.0, 1.55), rot_z=4)
zdk.avatar((-0.7, 3.0, 0), rot_z=8, face="grin", shirt=(240, 132, 44), skin=(140, 96, 70), cap=None,
           pose={"arm_l": (-25, 48, 0), "arm_r": (-40, -8, 0), "leg_l": (16, 0, 0), "leg_r": (-16, 0, 0), "head": (0, 0, -8)})
zdk.avatar((-9.3, 3.5, 0), rot_z=2, face="determined", shirt=(46, 140, 92), skin=(250, 214, 170), cap=(30, 70, 140),
           pose={"arm_r": (-25, -48, 0), "arm_l": (-40, 8, 0), "leg_l": (-16, 0, 0), "leg_r": (16, 0, 0), "head": (0, 0, 8)})
hero = zdk.avatar((5.6, -6.8, 0), rot_z=22, face="grin",
                  pose={"arm_l": (-62, 0, 8), "arm_r": (-62, 0, -8), "leg_l": (24, 0, 0), "leg_r": (-24, 0, 0), "head": (4, 0, 0)})
zdk.moving_box((0, -1.55, 1.75), (2.2, 1.6, 1.5), parent=hero)

# what waits on the lawn by the van
zdk.moving_box((12.5, 3.0, 0), (2.0, 2.0, 1.8), rot_z=-12)
zdk.moving_box((14.6, 2.0, 0), (1.6, 1.6, 1.4), rot_z=20)
zdk.moving_box((12.7, 3.1, 1.8), (1.5, 1.5, 1.3), rot_z=4)
zdk.piece("furniture", "F_floor_lamp", (-14.5, 6.0, 0), rot_z=0)
zdk.piece("furniture", "F_plant", (10.0, 5.0, 0), rot_z=0)
zdk.moving_box((-15.0, 2.5, 0), (2.0, 2.0, 1.8), rot_z=10)

zdk.camera((0.0, -19.5, 3.9), (1.0, 10, 6.0), lens=24)
zdk.render(o["out"])
