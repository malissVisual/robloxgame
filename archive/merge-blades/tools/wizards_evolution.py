#!/usr/bin/env python3
"""
wizards_evolution.py: builds the ELEMENT WIZARDS (Fire, Ice, Storm, Nature, Shadow, Arcane), 16 merge levels each,
as Luau data modules in the evolution shape (src/shared/SoldierRig.luau, buildEvolution), plus preview sheets.

The look follows the "Merge Wizardi 1–16" design (Claude Design canvas): a robed wizard with a pointed hat whose
gear grows with the level, the same milestones for every element, and the element in the colors and the head of
the staff:
     1-3  apprentice: a short wand with a spark, plain robe and hat
     4    a real staff with the element head, a beard, a belt, trims on the robe and the hat
     7    a cape, shoulder pads, a rune circle on the ground
    10    a metal staff, glowing eyes, a star on the hat tip, floating orbs (10, 11, 12), an orb in the left hand (8+)
    11    gold trims and pads
    13    wings of light, a crown on the hat, a second rune circle
    16    a halo, a golden staff, a golden rune circle
The rarity frames of the design (bronze 1-5, silver 6-10, gold 11-15, legend 16) are the trim / pad / staff metals.

Usage:
    python3 tools/wizards_evolution.py            # writes src/shared/StageModels/WizardEvolution + previews
    python3 tools/wizards_evolution.py --no-png   # only the Luau modules

Everything is authored in model space (feet on y = 0, facing -Z, the R15 body of the Mage's level 1) and turned
into CFrames relative to the body part the piece is welded to (or to the hand that holds it).
"""

import math
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "shared", "StageModels", "WizardEvolution")
PREVIEW = os.path.join(ROOT, "design", "WizardEvolution")
LEVELS = 16

# Materials (Enum.Material values) and shapes (Enum.PartType values).
PLASTIC, NEON, FABRIC, METAL, WOOD, GLASS, ICE, GRASS, SLATE, MARBLE = 272, 288, 1312, 1088, 512, 1568, 1536, 1280, 800, 784
BALL, BLOCK, CYLINDER = 0, 1, 2

SKIN = (241, 201, 165)
GOLD = (242, 193, 78)
SILVER = (201, 204, 214)
BRONZE = (176, 112, 62)
WOODC = (122, 74, 36)
DARKWOOD = (86, 52, 28)

ELEMENTS = {
    # robe, dark (cape / brim / shade), accent (trims up to 10), glow (aura, wings), sig (the element's own light),
    # eye (glowing eyes 10+), word (the level names)
    "Fire": dict(robe=(194, 54, 27), dark=(110, 24, 12), accent=(255, 154, 46), glow=(255, 106, 31), sig=(255, 194, 59), eye=(255, 224, 138), word="Flame"),
    "Ice": dict(robe=(61, 143, 209), dark=(29, 74, 120), accent=(191, 233, 255), glow=(111, 211, 255), sig=(226, 248, 255), eye=(191, 242, 255), word="Frost"),
    "Storm": dict(robe=(75, 79, 184), dark=(38, 40, 106), accent=(255, 225, 77), glow=(143, 155, 255), sig=(255, 225, 77), eye=(255, 243, 160), word="Storm"),
    "Nature": dict(robe=(63, 154, 69), dark=(29, 84, 38), accent=(198, 232, 107), glow=(123, 224, 127), sig=(166, 227, 90), eye=(217, 255, 158), word="Grove"),
    "Shadow": dict(robe=(74, 42, 106), dark=(32, 15, 46), accent=(180, 140, 255), glow=(138, 77, 255), sig=(207, 174, 255), eye=(217, 184, 255), word="Shadow"),
    "Arcane": dict(robe=(138, 63, 201), dark=(74, 28, 116), accent=(255, 122, 224), glow=(214, 123, 255), sig=(255, 209, 245), eye=(255, 196, 242), word="Arcane"),
}
ORDER = ["Fire", "Ice", "Storm", "Nature", "Shadow", "Arcane"]
TITLES = ["Apprentice", "Novice", "Initiate", "Adept", "Conjurer", "Sorcerer", "Magus", "High Magus", "Master",
          "Grandmaster", "Archmage", "Exalted Archmage", "Warden", "Sage", "Avatar", "Legend"]


# ── math ─────────────────────────────────────────────────────────────────────────────────────────────────────
def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


I3 = np.eye(3)
UPRIGHT = rz(math.pi / 2)  # a Cylinder's axis is X: this stands it up


def axis_x_to(d):
    """A rotation whose X axis points along d (for cylinders along a path)."""
    x = np.array(d, float)
    x /= np.linalg.norm(x)
    ref = np.array([0, 0, 1.0]) if abs(x[2]) < 0.9 else np.array([1.0, 0, 0])
    y = np.cross(ref, x)
    y /= np.linalg.norm(y)
    z = np.cross(x, y)
    return np.column_stack([x, y, z])


def cf_from(vals):
    """A Roblox CFrame.new(x, y, z, R00 … R22) → (pos, R)."""
    if len(vals) == 3:
        return np.array(vals, float), I3.copy()
    p = np.array(vals[:3], float)
    R = np.array(vals[3:], float).reshape(3, 3)
    return p, R


# ── the body (the Mage's level 1 R15 rig; the joints are kept as they are) ────────────────────────────────────
BODY = [
    ("HumanoidRootPart", (0, 3.35, 0), (2, 2, 1)),
    ("LowerTorso", (0, 2.575, 0), (1.5, 0.45, 0.8)),
    ("UpperTorso", (0, 3.5, 0), (1.6, 1.4, 0.85)),
    ("Head", (0, 4.85, 0), (1.3, 1.3, 1.25)),
    ("LeftUpperArm", (-1.111, 3.798, -0.092, 0.985, 0.159, -0.071, -0.174, 0.9, -0.401, 0, 0.407, 0.914), (0.55, 0.85, 0.55)),
    ("LeftLowerArm", (-1.176, 3.429, -0.693, 0.985, 0.012, -0.173, -0.174, 0.069, -0.982, 0, 0.998, 0.07), (0.5, 0.8, 0.5)),
    ("LeftHand", (-1.18, 3.185, -1.159, 1, 0, 0, 0, 0.883, -0.469, 0, 0.469, 0.883), (0.5, 0.45, 0.5)),
    ("RightUpperArm", (1.109, 3.786, -0.062, 0.988, -0.15, 0.043, 0.156, 0.949, -0.272, 0, 0.276, 0.961), (0.55, 0.85, 0.55)),
    ("RightLowerArm", (1.198, 3.222, -0.563, 0.988, -0.073, 0.138, 0.156, 0.464, -0.872, 0, 0.883, 0.469), (0.5, 0.8, 0.5)),
    ("RightHand", (1.224, 2.809, -0.872), (0.5, 0.45, 0.5)),
    ("LeftUpperLeg", (-0.4, 1.825, 0), (0.65, 1.05, 0.65)),
    ("LeftLowerLeg", (-0.4, 0.8, 0), (0.6, 1, 0.6)),
    ("LeftFoot", (-0.4, 0.15, -0.12), (0.65, 0.3, 0.95)),
    ("RightUpperLeg", (0.4, 1.825, 0), (0.65, 1.05, 0.65)),
    ("RightLowerLeg", (0.4, 0.8, 0), (0.6, 1, 0.6)),
    ("RightFoot", (0.4, 0.15, -0.12), (0.65, 0.3, 0.95)),
]
HOST = {name: cf_from(cf) for name, cf, _ in BODY}
SIZE = {name: size for name, _, size in BODY}

JOINTS = """\t\t\t{ "Root", "HumanoidRootPart", "LowerTorso", P(0, -0.775, 0), P(0, 0, 0) },
\t\t\t{ "Waist", "LowerTorso", "UpperTorso", P(0, 0.225, 0), P(0, -0.7, 0) },
\t\t\t{ "Neck", "UpperTorso", "Head", P(0, 0.7, 0), P(0, -0.65, 0) },
\t\t\t{ "LeftShoulder", "UpperTorso", "LeftUpperArm", CF(-1.075, 0.5, 0, 0.985, 0.159, -0.071, -0.174, 0.9, -0.401, 0, 0.407, 0.914), P(0, 0.225, 0) },
\t\t\t{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", CF(0, -0.375, 0, 1, 0, 0, 0, 0.469, -0.883, 0, 0.883, 0.469), P(0, 0.45, 0) },
\t\t\t{ "LeftWrist", "LeftLowerArm", "LeftHand", CF(0, -0.35, 0, 0.985, -0.153, 0.082, 0.012, 0.529, 0.849, -0.173, -0.835, 0.523), P(0, 0.25, 0) },
\t\t\t{ "RightShoulder", "UpperTorso", "RightUpperArm", CF(1.075, 0.5, 0, 0.988, -0.15, 0.043, 0.156, 0.949, -0.272, 0, 0.276, 0.961), P(0, 0.225, 0) },
\t\t\t{ "RightElbow", "RightUpperArm", "RightLowerArm", CF(0, -0.375, 0, 1, 0, 0, 0, 0.695, -0.719, 0, 0.719, 0.695), P(0, 0.45, 0) },
\t\t\t{ "RightWrist", "RightLowerArm", "RightHand", CF(0, -0.35, 0, 0.988, 0.156, 0, -0.073, 0.464, 0.883, 0.138, -0.872, 0.469), P(0, 0.25, 0) },
\t\t\t{ "LeftHip", "LowerTorso", "LeftUpperLeg", P(-0.4, -0.275, 0), P(0, 0.475, 0) },
\t\t\t{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", P(0, -0.525, 0), P(0, 0.5, 0) },
\t\t\t{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", P(0, -0.5, 0), P(0, 0.15, 0.12) },
\t\t\t{ "RightHip", "LowerTorso", "RightUpperLeg", P(0.4, -0.275, 0), P(0, 0.475, 0) },
\t\t\t{ "RightKnee", "RightUpperLeg", "RightLowerLeg", P(0, -0.525, 0), P(0, 0.5, 0) },
\t\t\t{ "RightAnkle", "RightLowerLeg", "RightFoot", P(0, -0.5, 0), P(0, 0.15, 0.12) },"""

HAND_R = HOST["RightHand"][0]
HAND_L = HOST["LeftHand"][0]
HEAD = HOST["Head"][0]


class Piece:
    __slots__ = ("host", "pos", "R", "size", "color", "mat", "shape", "t", "light", "wedge", "slot")

    def __init__(self, host, pos, size, color, mat, R=None, shape=BLOCK, t=0.0, light=None, wedge=False, slot="gear"):
        self.host, self.pos, self.size = host, np.array(pos, float), np.array(size, float)
        self.R = I3.copy() if R is None else np.array(R, float)
        self.color, self.mat, self.shape, self.t, self.light, self.wedge, self.slot = color, mat, shape, t, light, wedge, slot


def lerp(a, b, f):
    return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3))


# ── one wizard ──────────────────────────────────────────────────────────────────────────────────────────────
def build(element, lv):
    E = ELEMENTS[element]
    t = (lv - 1) / 15
    out = []
    add = lambda host, pos, size, color, mat, **kw: out.append(Piece(host, pos, size, color, mat, **kw)) or out[-1]

    trim = GOLD if lv >= 11 else E["accent"]
    pad = GOLD if lv >= 11 else SILVER
    metal = GOLD if lv == 16 else (SILVER if lv >= 10 else BRONZE)
    beard_c = (236, 232, 242) if lv >= 9 else (150, 112, 82)

    # ── the robe: the skirt in four widening bands hides the legs; an open front, a hem, a belt
    bands = 4
    top_y, bot_y = 2.62, 0.32
    w0, w1 = 1.62, 2.0 + 0.35 * t
    d0, d1 = 0.92, 1.22 + 0.2 * t
    for i in range(bands):
        f0, f1 = i / bands, (i + 1) / bands
        y0, y1 = top_y - (top_y - bot_y) * f0, top_y - (top_y - bot_y) * f1
        w = w0 + (w1 - w0) * (f0 + f1) / 2
        d = d0 + (d1 - d0) * (f0 + f1) / 2
        add("LowerTorso", (0, (y0 + y1) / 2, 0.02), (w, y0 - y1 + 0.02, d), E["robe"], FABRIC)
        add("LowerTorso", (0, (y0 + y1) / 2, 0.02 - d / 2 - 0.005), (0.34 + 0.12 * f1, y0 - y1 + 0.02, 0.02), E["dark"], FABRIC)
    add("UpperTorso", (0, 3.5, 0), (1.68, 1.42, 0.92), E["robe"], FABRIC)
    # the V collar
    for side in (-1, 1):
        add("UpperTorso", (0.17 * side, 3.86, -0.47), (0.12, 0.72, 0.03), trim if lv >= 4 else E["dark"], FABRIC, R=rz(-side * 0.42))
    add("UpperTorso", (0, 3.68, -0.465), (0.22, 0.5, 0.02), E["dark"], FABRIC)
    if lv >= 4:
        add("LowerTorso", (0, bot_y + 0.06, 0.02), (w1 + 0.04, 0.12, d1 + 0.04), trim, FABRIC)  # the hem
        for side in (-1, 1):  # the trims of the open front
            add("LowerTorso", (side * 0.26, (top_y + bot_y) / 2, 0.02 - d1 / 2 + 0.05), (0.06, top_y - bot_y, 0.03), trim, FABRIC, R=rz(side * 0.05))
        add("LowerTorso", (0, 2.76, 0), (1.76, 0.2, 1.0), E["dark"], FABRIC)  # the belt
        add("LowerTorso", (0, 2.76, -0.51), (0.24, 0.24, 0.05), trim, METAL)
        add("LowerTorso", (0, 2.76, -0.54), (0.11, 0.11, 0.03), E["sig"], NEON)
        # a pouch on the belt
        add("LowerTorso", (-0.62, 2.55, -0.36), (0.3, 0.32, 0.2), E["dark"], FABRIC, R=ry(0.3))
    # the sleeves: wide cuffs at the wrists
    for arm in ("LeftLowerArm", "RightLowerArm"):
        p, R = HOST[arm]
        add(arm, p + R @ np.array([0, -0.27, 0]), (0.7, 0.3, 0.7), E["robe"], FABRIC, R=R)
        add(arm, p + R @ np.array([0, -0.43, 0]), (0.74, 0.07, 0.74), trim if lv >= 4 else E["dark"], FABRIC, R=R)
    for arm in ("LeftUpperArm", "RightUpperArm"):
        p, R = HOST[arm]
        add(arm, p, (0.6, 0.88, 0.6), E["robe"], FABRIC, R=R)

    # ── shoulder pads (7+) and the cape (7+)
    if lv >= 7:
        for side in (-1, 1):
            add("UpperTorso", (side * 0.92, 4.17, 0), (0.72, 0.36, 0.98), pad, METAL, R=rz(-side * 0.32))
            add("UpperTorso", (side * 0.92, 4.06, 0), (0.78, 0.12, 1.04), E["dark"], FABRIC, R=rz(-side * 0.32))
            if lv >= 13:
                add("UpperTorso", (side * 0.98, 4.24, -0.5), (0.18, 0.18, 0.18), E["sig"], NEON, shape=BALL)
        cape_len = 3.65
        tilt = rx(0.09)
        add("UpperTorso", (0, 4.2 - cape_len / 2, 0.62), (1.95 + 0.25 * t, cape_len, 0.07), E["dark"], FABRIC, R=tilt)
        add("UpperTorso", (0, 4.2 - cape_len + 0.06, 0.62 + 0.16), (1.97 + 0.25 * t, 0.12, 0.09), trim, FABRIC, R=tilt)
        if lv >= 11:  # a lining in the element color shows at the edges
            for side in (-1, 1):
                add("UpperTorso", (side * (0.98 + 0.125 * t), 4.2 - cape_len / 2, 0.6), (0.06, cape_len, 0.08), E["accent"], FABRIC, R=tilt)
    if lv >= 10:  # the high collar behind the head
        add("UpperTorso", (0, 4.42, 0.36), (1.3, 0.62, 0.08), E["dark"], FABRIC, R=rx(-0.35))
        add("UpperTorso", (0, 4.72, 0.47), (1.32, 0.07, 0.1), trim, FABRIC, R=rx(-0.35))

    # ── the face
    hx, hy, hz = HEAD
    eye = E["eye"] if lv >= 10 else (34, 24, 20)
    for side in (-1, 1):
        add("Head", (side * 0.24, hy + 0.06, -0.63), (0.17, 0.2, 0.04), (250, 250, 252) if lv < 10 else eye, PLASTIC if lv < 10 else NEON)
        if lv < 10:
            add("Head", (side * 0.24, hy + 0.05, -0.655), (0.09, 0.12, 0.03), eye, PLASTIC)
        add("Head", (side * 0.25, hy + 0.23, -0.64), (0.3, 0.06, 0.05), beard_c if lv >= 4 else (92, 60, 38), PLASTIC, R=rz(-side * 0.12))
    add("Head", (0, hy - 0.08, -0.68), (0.16, 0.24, 0.12), (226, 184, 150), PLASTIC)  # nose
    for side in (-1, 1):  # hair at the sides
        add("Head", (side * 0.63, hy - 0.05, 0.1), (0.1, 0.7, 0.9), beard_c if lv >= 4 else (92, 60, 38), PLASTIC)
    if lv >= 4:
        length = 0.3 + (lv - 4) * 0.06
        add("Head", (0, hy - 0.26 - length / 2, -0.52), (0.78, length, 0.3), beard_c, FABRIC)
        add("Head", (0, hy - 0.26 - length - 0.09, -0.5), (0.42, 0.18, 0.24), beard_c, FABRIC)
        for side in (-1, 1):
            add("Head", (side * 0.2, hy - 0.22, -0.69), (0.4, 0.11, 0.1), beard_c, FABRIC, R=rz(side * 0.25))
    else:
        add("Head", (0, hy - 0.3, -0.63), (0.26, 0.05, 0.04), (140, 70, 64), PLASTIC)  # mouth

    # ── the hat: a brim and a cone of cylinders that bends back at the tip
    brim_y = hy + 0.56
    add("Head", (0, brim_y, 0.02), (0.12, 2.0 + 0.6 * t, 2.0 + 0.6 * t), E["dark"], FABRIC, R=UPRIGHT, shape=CYLINDER)
    H = 1.25 + 1.0 * t
    base_r = 0.78 + 0.08 * t
    bend_z, bend_x = 0.35 + 0.35 * t, 0.15 + 0.2 * t
    n = 6
    path = lambda f: np.array([bend_x * f ** 2.2, brim_y + 0.04 + H * f, 0.02 + bend_z * f ** 2.2])
    for i in range(n):
        a, b = path(i / n), path((i + 1) / n)
        r = base_r * (1 - (i + 0.5) / n * 0.86)
        d = b - a
        add("Head", (a + b) / 2, (np.linalg.norm(d) * 1.08, 2 * r, 2 * r), E["robe"], FABRIC, R=axis_x_to(d), shape=CYLINDER)
    tip = path(1.0) + np.array([0, 0.05, 0])
    if lv >= 4:
        add("Head", (0, brim_y + 0.14, 0.02), (0.2, 2 * base_r * 1.02, 2 * base_r * 1.02), trim, FABRIC, R=UPRIGHT, shape=CYLINDER)
    if lv >= 13:  # the crown on the band
        for k in range(8):
            ang = k / 8 * math.tau
            px, pz = math.sin(ang) * base_r * 0.98, 0.02 - math.cos(ang) * base_r * 0.98
            add("Head", (px, brim_y + 0.38, pz), (0.14, 0.32, 0.06), GOLD, METAL, R=ry(-ang))
        add("Head", (0, brim_y + 0.26, 0.02 - base_r - 0.02), (0.2, 0.2, 0.08), E["sig"], NEON, R=rz(math.pi / 4))
    if lv >= 10:  # a star on the tip
        s = 0.3 + 0.12 * (lv - 10) / 6
        add("Head", tip, (s, s, 0.08), E["sig"], NEON, R=rz(math.pi / 4))
        add("Head", tip, (s * 0.7, s * 0.7, 0.1), E["sig"], NEON)
    else:
        add("Head", tip, (0.16, 0.16, 0.16), E["robe"], FABRIC, shape=BALL)

    # ── the halo (16): a big ring of golden lights behind the wizard
    if lv == 16:
        for k in range(28):
            ang = k / 28 * math.tau
            add("UpperTorso", (math.cos(ang) * 1.75, hy + 0.35 + math.sin(ang) * 1.75, 0.95), (0.2, 0.2, 0.2), (255, 226, 122), NEON, shape=BALL)

    # ── wings of light (13+)
    if lv >= 13:
        span = 1.0 + 0.25 * (lv - 13)
        for side in (-1, 1):
            for k, (ang, ln) in enumerate([(0.55, 2.2), (0.95, 1.9), (1.35, 1.5), (1.75, 1.1)]):
                L = ln * span
                R = rz(-side * ang)
                base = np.array([side * 0.35, 4.0, 0.62])
                center = base + R @ np.array([0, L / 2, 0])
                add("UpperTorso", center, (0.55 - 0.06 * k, L, 0.05), E["glow"], NEON, R=R, t=0.4)
                add("UpperTorso", center + np.array([0, 0, 0.01]), (0.1, L * 0.92, 0.06), E["sig"], NEON, R=R, t=0.15)

    # ── floating orbs (10, 11, 12) and the rune circles (7+, 13+): on the root, so they stay still
    orbs = [(-1.95, 3.9, 0.3), (1.95, 1.3, 0.5), (-1.85, 1.15, -0.6)]
    for k in range(min(3, max(0, lv - 9))):
        add("HumanoidRootPart", orbs[k], (0.42, 0.42, 0.42), E["glow"], NEON, shape=BALL, t=0.15)
        add("HumanoidRootPart", orbs[k], (0.56, 0.56, 0.56), E["sig"], GLASS, shape=BALL, t=0.6)
    if lv >= 7:
        circle_c = (255, 226, 122) if lv == 16 else E["accent"]
        n_seg, rad = 14, 1.65
        for k in range(n_seg):
            ang = k / n_seg * math.tau
            add("HumanoidRootPart", (math.cos(ang) * rad, 0.04, math.sin(ang) * rad), (2 * rad * math.sin(math.pi / n_seg) * 0.82, 0.04, 0.1), circle_c, NEON, R=ry(-ang - math.pi / 2), t=0.3)
        for k in range(4):  # runes inside
            ang = k / 4 * math.tau + math.pi / 4
            add("HumanoidRootPart", (math.cos(ang) * 1.3, 0.04, math.sin(ang) * 1.3), (0.22, 0.04, 0.22), circle_c, NEON, R=ry(ang), t=0.35)
    if lv >= 13:
        n_seg, rad = 22, 2.25
        for k in range(n_seg):
            ang = k / n_seg * math.tau
            add("HumanoidRootPart", (math.cos(ang) * rad, 0.03, math.sin(ang) * rad), (0.28, 0.035, 0.08), E["glow"], NEON, R=ry(-ang - math.pi / 2), t=0.3)

    # ── the weapon (right hand)
    hxr, hyr, hzr = HAND_R
    if lv <= 3:
        top = hyr + 1.0 + 0.12 * lv
        add("RightHand", (hxr, (hyr - 0.25 + top) / 2, hzr), ((top - hyr + 0.25), 0.13, 0.13), WOODC, WOOD, R=UPRIGHT, shape=CYLINDER, slot="weapon")
        g = 0.2 + 0.06 * lv
        if lv >= 2:
            for side in (-1, 1):
                add("RightHand", (hxr + side * 0.07, top + 0.02, hzr), (0.05, 0.22, 0.05), BRONZE, METAL, R=rz(side * 0.4), slot="weapon")
        add("RightHand", (hxr, top + g / 2, hzr), (g, g, g), E["sig"], NEON, shape=BALL, slot="weapon", light=(*E["glow"], 6, 1.2))
    else:
        top = 5.25 + 0.9 * t
        bottom = 0.12
        shaft_c = WOODC if lv < 10 else metal
        shaft_m = WOOD if lv < 10 else METAL
        thick = 0.17 + 0.06 * t
        add("RightHand", (hxr, (bottom + top) / 2, hzr), (top - bottom, thick, thick), shaft_c, shaft_m, R=UPRIGHT, shape=CYLINDER, slot="weapon")
        add("RightHand", (hxr, bottom + 0.1, hzr), (0.22, thick + 0.06, thick + 0.06), metal, METAL, R=UPRIGHT, shape=CYLINDER, slot="weapon")
        if lv >= 6:  # grip wraps
            for k in range(3):
                add("RightHand", (hxr, hyr + 0.45 + k * 0.16, hzr), (0.07, thick + 0.05, thick + 0.05), E["dark"] if lv < 10 else E["accent"], FABRIC, R=UPRIGHT, shape=CYLINDER, slot="weapon")
        add("RightHand", (hxr, top - 0.05, hzr), (0.16, thick + 0.1, thick + 0.1), metal, METAL, R=UPRIGHT, shape=CYLINDER, slot="weapon")
        hs = 0.75 + 0.55 * t
        staff_head(add, element, E, lv, np.array([hxr, top + 0.38 * hs, hzr]), hs, metal)

    # ── the offhand (8+): a floating orb over the left palm
    if lv >= 8:
        hp, hR = HOST["LeftHand"]
        s = 0.42 + 0.18 * (lv - 8) / 8
        c = hp + np.array([0, 0.62 + s / 2, -0.05])
        add("LeftHand", c, (s, s, s), E["glow"], NEON, shape=BALL, slot="offhand", t=0.1, light=(*E["glow"], 5, 1))
        add("LeftHand", c, (s * 1.35, s * 1.35, s * 1.35), E["sig"], GLASS, shape=BALL, slot="offhand", t=0.65)
        if lv >= 14:
            add("LeftHand", c, (0.05, s * 1.9, s * 1.9), trim, NEON, R=rx(0.5) @ ry(math.pi / 2) @ UPRIGHT, shape=CYLINDER, slot="offhand", t=0.55)

    # the label floats 0.9 over the highest piece (as tools/evolution_from_rbxmx.py measures it); the floating halo
    # and wings do not count
    max_y = hy + SIZE["Head"][1] / 2
    for p in out:
        if p.mat == NEON and p.host in ("UpperTorso", "HumanoidRootPart"):
            continue
        max_y = max(max_y, p.pos[1] + (np.abs(p.R) @ p.size)[1] / 2)
    return out, round(max_y - hy + 0.9, 3)


def staff_head(add, element, E, lv, c, hs, metal):
    """The head of the staff, centered on c (model space), at size hs."""
    W = lambda pos, size, color, mat, **kw: add("RightHand", pos, size, color, mat, slot="weapon", **kw)
    core_light = (*E["glow"], 8, 1.4 + 0.04 * lv)
    big = lv >= 10
    if element == "Fire":
        for k in range(3):  # the iron cradle
            ang = k / 3 * math.tau
            R = ry(ang) @ rz(0.45)
            W(c + ry(ang) @ np.array([0.18 * hs, -0.18 * hs, 0]), (0.07 * hs, 0.55 * hs, 0.07 * hs), (60, 50, 50) if lv < 10 else metal, METAL, R=R)
        W(c, (0.5 * hs,) * 3, E["glow"], NEON, shape=BALL, light=core_light)
        for k, (dy, s, col) in enumerate([(0.3, 0.38, (255, 140, 40)), (0.55, 0.26, (255, 194, 59)), (0.75, 0.15, (255, 236, 160))]):
            W(c + np.array([0.02 * k, dy * hs, 0.03 * k]), (s * hs,) * 3, col, NEON, shape=BALL, t=0.1)
        if big:
            for side in (-1, 1):
                W(c + np.array([side * 0.28 * hs, 0.25 * hs, 0]), (0.12 * hs, 0.42 * hs, 0.12 * hs), (255, 150, 50), NEON, R=rz(-side * 0.5), t=0.15)
    elif element == "Ice":
        W(c + np.array([0, 0.15 * hs, 0]), (0.36 * hs, 0.95 * hs, 0.36 * hs), E["accent"], GLASS, R=ry(math.pi / 4), t=0.25)
        W(c + np.array([0, 0.15 * hs, 0]), (0.18 * hs, 0.7 * hs, 0.18 * hs), E["glow"], NEON, R=ry(math.pi / 4), light=core_light)
        W(c + np.array([0, 0.66 * hs, 0]), (0.22 * hs, 0.22 * hs, 0.22 * hs), E["sig"], ICE, R=ry(math.pi / 4) @ rx(math.pi / 4))
        n = 4 if big else 2
        for k in range(n):
            ang = k / n * math.tau + 0.4
            R = ry(ang) @ rz(0.55)
            W(c + ry(ang) @ np.array([0.24 * hs, -0.05 * hs, 0]), (0.14 * hs, 0.5 * hs, 0.14 * hs), E["accent"], ICE, R=R, t=0.15)
    elif element == "Storm":
        ring = 12
        for k in range(ring):  # a ring around the core, in the XY plane
            ang = k / ring * math.tau
            W(c + np.array([math.cos(ang) * 0.42 * hs, math.sin(ang) * 0.42 * hs, 0]), (0.1 * hs, 0.24 * hs, 0.1 * hs), metal if lv >= 10 else (90, 96, 120), METAL, R=rz(ang))
        W(c, (0.42 * hs,) * 3, E["sig"], NEON, shape=BALL, light=core_light)
        bolt = [(0.0, 0.62, 0.5), (0.1, 0.9, -0.6), (0.0, 1.15, 0.5)]
        for dx, dy, a in bolt:
            W(c + np.array([dx * hs, dy * hs, 0]), (0.08 * hs, 0.34 * hs, 0.08 * hs), E["sig"], NEON, R=rz(a))
        if big:
            for side in (-1, 1):
                W(c + np.array([side * 0.62 * hs, 0.1 * hs, 0]), (0.07 * hs, 0.3 * hs, 0.07 * hs), E["sig"], NEON, R=rz(side * 0.9))
    elif element == "Nature":
        for k in range(4):  # branches growing around the orb
            ang = k / 4 * math.tau + 0.3
            R = ry(ang) @ rz(0.38)
            W(c + ry(ang) @ np.array([0.2 * hs, -0.05 * hs, 0]), (0.09 * hs, 0.75 * hs, 0.09 * hs), DARKWOOD if lv < 10 else (110, 76, 40), WOOD, R=R)
        W(c, (0.44 * hs,) * 3, E["glow"], NEON, shape=BALL, light=core_light)
        leaves = 6 if big else 4
        for k in range(leaves):
            ang = k / leaves * math.tau
            R = ry(ang) @ rx(-0.6)
            W(c + ry(ang) @ np.array([0, 0.28 * hs, -0.33 * hs]), (0.24 * hs, 0.05 * hs, 0.36 * hs), (86, 178, 74), GRASS, R=R)
        if big:
            for k in range(3):
                ang = k / 3 * math.tau + 0.5
                W(c + ry(ang) @ np.array([0, 0.42 * hs, -0.24 * hs]), (0.12 * hs,) * 3, (255, 150, 210), NEON, shape=BALL)
    elif element == "Shadow":
        for k in range(7):  # a crescent moon around the core
            a = -1.2 + k / 6 * 2.4
            s = 0.24 - abs(k - 3) * 0.04
            W(c + np.array([-math.cos(a) * 0.38 * hs, math.sin(a) * 0.38 * hs + 0.05 * hs, 0]), (s * hs,) * 3, E["accent"], NEON, shape=BALL, t=0.05)
        W(c, (0.34 * hs,) * 3, E["glow"], NEON, shape=BALL, light=core_light)
        spikes = 4 if big else 2
        for k in range(spikes):
            a = (k - (spikes - 1) / 2) * 0.45
            R = rz(a)
            W(c + R @ np.array([0, 0.48 * hs, 0]), (0.08 * hs, 0.42 * hs, 0.08 * hs), (24, 14, 34), SLATE, R=R)
    else:  # Arcane
        for a in (0, math.pi / 4):  # an eight-pointed star
            W(c, (0.5 * hs, 0.5 * hs, 0.08 * hs), E["accent"], NEON, R=rz(a))
        W(c, (0.3 * hs,) * 3, E["sig"], NEON, shape=BALL, light=core_light)
        rings = 2 if big else 1
        for r in range(rings):
            n = 10
            rad = (0.5 + 0.16 * r) * hs
            tilt = rx(0.5 + r * 0.9)
            for k in range(n):
                ang = k / n * math.tau
                W(c + tilt @ np.array([math.cos(ang) * rad, 0, math.sin(ang) * rad]), (0.08 * hs,) * 3, E["glow"], NEON, shape=BALL)


# ── output ──────────────────────────────────────────────────────────────────────────────────────────────────
def num(v):
    v = round(float(v), 3)
    if v == 0:
        v = 0.0
    if v == int(v):
        return str(int(v))
    return ("%.3f" % v).rstrip("0").rstrip(".")


def cf_text(pos, R):
    if np.allclose(R, I3, atol=1e-4):
        return "P(%s, %s, %s)" % tuple(num(x) for x in pos)
    return "CF(%s)" % ", ".join(num(x) for x in list(pos) + list(R.reshape(-1)))


def relative(piece):
    hp, hR = HOST[piece.host]
    return hR.T @ (piece.pos - hp), hR.T @ piece.R


def entry_text(piece, host_label):
    pos, R = relative(piece)
    extra = []
    if piece.shape != BLOCK:
        extra.append("shape = %d" % piece.shape)
    if piece.wedge:
        extra.append("wedge = true")
    if piece.t:
        extra.append("t = %s" % num(piece.t))
    if piece.light:
        extra.append("light = { %s }" % ", ".join(num(x) for x in piece.light))
    tail = (", { %s }" % ", ".join(extra)) if extra else ""
    return '\t\t\t{ "%s", %s, V(%s), C(%d, %d, %d), %d%s },' % (
        host_label, cf_text(pos, R), ", ".join(num(x) for x in piece.size), *piece.color, piece.mat, tail)


def body_text(E):
    lines = []
    for name, cf, size in BODY:
        pos, R = HOST[name]
        if name == "HumanoidRootPart":
            color, mat, tail = SKIN, PLASTIC, ", { t = 1 }"
        elif name in ("Head", "LeftHand", "RightHand"):
            color, mat, tail = SKIN, PLASTIC, ""
        elif "Foot" in name:
            color, mat, tail = (52, 36, 30), FABRIC, ""
        elif "Leg" in name:
            color, mat, tail = E["dark"], FABRIC, ""
        else:
            color, mat, tail = E["robe"], FABRIC, ""
        lines.append('\t\t\t{ "%s", %s, V(%s), C(%d, %d, %d), %d%s },' % (name, cf_text(pos, R), ", ".join(num(x) for x in size), *color, mat, tail))
    return "\n".join(lines)


def module_text(element, lv, pieces, top):
    E = ELEMENTS[element]
    gear = [p for p in pieces if p.slot == "gear"]
    weapon = [p for p in pieces if p.slot == "weapon"]
    offhand = [p for p in pieces if p.slot == "offhand"]
    parts = [
        "--!strict",
        "-- GENERATED by tools/wizards_evolution.py: the %s wizard, merge level %d. Do not edit by hand: change the" % (element, lv),
        "-- tool and run it again. The shape is the one of StageModels/MageEvolution (SoldierRig.buildEvolution).",
        "",
        "local V = Vector3.new",
        "local C = Color3.fromRGB",
        "local P = CFrame.new",
        "local CF = CFrame.new",
        "",
        "return {",
        '\tname = "%s %s",' % (E["word"], TITLES[lv - 1]),
        '\telement = "%s",' % element,
        "\ttop = %s, -- the name label this high over the head" % num(top),
        "\tbody = {",
        body_text(E),
        "\t},",
        "\tjoints = {",
        JOINTS,
        "\t},",
        "\tgear = {",
        "\n".join(entry_text(p, p.host) for p in gear),
        "\t},",
        "\tweapon = {",
        "\n".join(entry_text(p, "RightHand") for p in weapon),
        "\t},",
        "\toffhand = {",
        "\n".join(entry_text(p, "LeftHand") for p in offhand),
        "\t},",
        "}",
        "",
    ]
    return "\n".join(parts)


INIT = '''--!strict
-- GENERATED by tools/wizards_evolution.py. THE ELEMENT WIZARDS: Fire, Ice, Storm, Nature, Shadow and Arcane, 16 merge
-- levels each (the "Merge Wizardi 1–16" design), one module per element and level (<Element>_L##), loaded the
-- first time it is asked for. A wizard type (Config/Wizards.luau) names its element in `evolution`; SoldierRig
-- builds these instead of the Mage's evolution for it.

local WizardEvolution = {}

WizardEvolution.Count = %d
WizardEvolution.Elements = { %s }

local loaded: { [string]: any } = {}

function WizardEvolution.has(element: string?): boolean
	return element ~= nil and table.find(WizardEvolution.Elements, element) ~= nil
end

-- The data of the element's level (the shape of StageModels/MageEvolution), or nil.
function WizardEvolution.level(element: string, level: number): any
	if not WizardEvolution.has(element) then
		return nil
	end
	local name = string.format("%%s_L%%02d", element, math.clamp(math.floor(level), 1, WizardEvolution.Count))
	local data = loaded[name]
	if not data then
		local module = script:FindFirstChild(name)
		if not module then
			return nil
		end
		data = require(module :: ModuleScript) :: any
		loaded[name] = data
	end
	return data
end

return WizardEvolution
''' % (LEVELS, ", ".join('"%s"' % e for e in ORDER))


# ── previews ────────────────────────────────────────────────────────────────────────────────────────────────
def world_pieces(pieces):
    """Every piece and body part in model space: (pos, R, size, color, shape, alpha)."""
    E = None
    items = []
    for p in pieces:
        items.append((p.pos, p.R, p.size, p.color, p.shape, 1 - p.t if p.t < 1 else 0))
    return items


def render_sheet(element, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Polygon, Circle

    E = ELEMENTS[element]
    fig, axes = plt.subplots(2, 8, figsize=(24, 8.4), facecolor="#121018")
    view = ry(math.radians(-28)) # a 3/4 view (from the front left)
    light = np.array([0.4, 0.7, -0.6])
    light /= np.linalg.norm(light)
    cube = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
    faces = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
    normals = [(-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1)]
    for lv in range(1, LEVELS + 1):
        ax = axes[(lv - 1) // 8][(lv - 1) % 8]
        ax.set_facecolor("#121018")
        pieces, _ = build(element, lv)
        items = []
        for name, cf, size in BODY:
            if name == "HumanoidRootPart":
                continue
            pos, R = HOST[name]
            col = SKIN if name in ("Head", "LeftHand", "RightHand") else ((52, 36, 30) if "Foot" in name else (E["dark"] if "Leg" in name else E["robe"]))
            items.append((pos, R, np.array(size), col, BLOCK, 1.0))
        for p in pieces:
            items.append((p.pos, p.R, p.size, p.color, p.shape, max(0.15, 1 - p.t)))
        polys = []
        for pos, R, size, col, shape, alpha in items:
            M = view @ R
            P0 = view @ pos
            base = np.array(col) / 255
            if shape == BALL:
                polys.append((P0[2], "c", (-P0[0], P0[1]), size[0] / 2, base, alpha))
                continue
            corners = (cube * size) @ M.T + P0
            for f, nrm in zip(faces, normals):
                nw = M @ np.array(nrm, float)
                if nw[2] > 0.05:  # facing away (the camera looks along +Z)
                    continue
                shade = 0.45 + 0.55 * max(0.0, float(np.dot(nw, light)))
                pts = corners[list(f)]
                polys.append((pts[:, 2].mean(), "p", [(-x, y) for x, y, _ in pts], None, np.clip(base * shade, 0, 1), alpha))
        polys.sort(key=lambda q: -q[0])
        for depth, kind, pts, r, col, alpha in polys:
            if kind == "c":
                ax.add_patch(Circle(pts, r, facecolor=col, edgecolor="none", alpha=alpha))
            else:
                ax.add_patch(Polygon(pts, closed=True, facecolor=col, edgecolor=col * 0.85, linewidth=0.2, alpha=alpha))
        ax.set_xlim(-3, 3)
        ax.set_ylim(-0.3, 8.2)
        ax.set_aspect("equal")
        ax.axis("off")
        ax.set_title("%d · %s %s" % (lv, E["word"], TITLES[lv - 1]), color="#efe6d2", fontsize=9)
    fig.suptitle("%s wizards · levels 1-16" % element, color=np.array(E["accent"]) / 255, fontsize=16)
    fig.tight_layout()
    fig.savefig(path, dpi=80, facecolor=fig.get_facecolor())
    plt.close(fig)


def main():
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".luau"):
            os.remove(os.path.join(OUT, old))
    with open(os.path.join(OUT, "init.luau"), "w", encoding="utf-8") as fh:
        fh.write(INIT)
    stats = []
    for element in ORDER:
        for lv in range(1, LEVELS + 1):
            pieces, top = build(element, lv)
            text = module_text(element, lv, pieces, top)
            with open(os.path.join(OUT, "%s_L%02d.luau" % (element, lv)), "w", encoding="utf-8") as fh:
                fh.write(text)
            stats.append((element, lv, len(pieces), len(text)))
    print("modules:", len(stats), " parts per wizard: %d … %d, largest module %d chars"
          % (min(s[2] for s in stats), max(s[2] for s in stats), max(s[3] for s in stats)))
    if "--no-png" not in sys.argv:
        os.makedirs(PREVIEW, exist_ok=True)
        for element in ORDER:
            render_sheet(element, os.path.join(PREVIEW, "%s_1-16.png" % element))
        print("previews in", PREVIEW)


if __name__ == "__main__":
    main()
