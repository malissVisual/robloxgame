#!/usr/bin/env python3
"""6.24: a contact sheet of the gait's key poses (shared/Gait.luau on the classic R15's block body).

    python3 tools/character-art/gait_sheet.py <luau binary> <out.png> [--side]

gait-sheet.luau runs the real module through walk / run / idle / jump scenarios; this draws each pose's body parts as
shaded boxes (a three-quarter view; --side: from the right), the ground line and the title. Needs Pillow."""
import argparse
import json
import math
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent

COLORS = {
    "Head": (218, 166, 119), "UpperTorso": (52, 56, 62), "LowerTorso": (44, 48, 56),
    "LeftUpperArm": (52, 56, 62), "RightUpperArm": (52, 56, 62), "LeftLowerArm": (218, 166, 119),
    "RightLowerArm": (218, 166, 119), "LeftHand": (218, 166, 119), "RightHand": (218, 166, 119),
    "LeftUpperLeg": (44, 48, 56), "RightUpperLeg": (44, 48, 56), "LeftLowerLeg": (44, 48, 56),
    "RightLowerLeg": (44, 48, 56), "LeftFoot": (24, 24, 26), "RightFoot": (24, 24, 26),
}
RIGHT_SIDE = (196, 40, 38)  # the right leg and arm a touch red: which is which
CELL = [220, 270]
SCALE = [30]  # pixels a stud


def export(luau):
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        for name in ("Config", "RunCycle", "BodyMotion", "Gait"):
            text = (ROOT / "src/shared" / f"{name}.luau").read_text()
            (tmp / f"{name}.luau").write_text(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', text))
        shutil.copy(ROOT / "src/server/CharacterArt/Geometry.luau", tmp / "CharacterGeometry.luau")
        shutil.copy(HERE / "gait-sheet.luau", tmp / "sheet.luau")
        result = subprocess.run([str(Path(luau).resolve()), "sheet.luau"], cwd=tmp, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
    return [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]


def view(side):
    # The camera's right, up and toward-the-viewer axes (world).
    if side:
        yaw, tilt = math.radians(90), math.radians(4)
    else:
        yaw, tilt = math.radians(58), math.radians(14)
    right = (math.cos(yaw), 0.0, -math.sin(yaw))
    back = (math.sin(yaw) * math.cos(tilt), math.sin(tilt), math.cos(yaw) * math.cos(tilt))
    up = (back[1] * right[2] - back[2] * right[1], back[2] * right[0] - back[0] * right[2], back[0] * right[1] - back[1] * right[0])
    return right, up, back


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def faces(part):
    cf, (sx, sy, sz) = part["cf"], part["size"]
    r = [cf[0:3], cf[3:6], cf[6:9]]
    p = cf[9:12]

    def world(x, y, z):
        return tuple(r[k][0] * x + r[k][1] * y + r[k][2] * z + p[k] for k in range(3))

    hx, hy, hz = sx / 2, sy / 2, sz / 2
    out = []
    for axis in range(3):
        for sign in (-1, 1):
            n = [0.0, 0.0, 0.0]
            n[axis] = sign
            normal = tuple(r[k][0] * n[0] + r[k][1] * n[1] + r[k][2] * n[2] for k in range(3))
            corners = []
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                c = [0.0, 0.0, 0.0]
                c[axis] = sign
                others = [k for k in range(3) if k != axis]
                c[others[0]], c[others[1]] = a, b
                corners.append(world(c[0] * hx, c[1] * hy, c[2] * hz))
            out.append((normal, corners))
    return out


def draw_pose(img, pose, origin, side):
    d = ImageDraw.Draw(img)
    right, up, back = view(side)
    light = (0.35, 0.8, 0.5)
    ox, oy = origin
    # (the body's middle over the cell's middle, the ground under it)
    cx = sum(dot(p["cf"][9:12], right) for p in pose["parts"]) / len(pose["parts"])
    gy = pose["ground"] + pose.get("rooty", 0)  # (a body in the air drawn over its own spot: the ground under the root)

    def to2d(pt):
        return ox + (dot(pt, right) - cx) * SCALE[0], oy - (dot(pt, up) - gy * up[1]) * SCALE[0]

    # the ground: a line under the feet (a body in the air: dotted, it stands that high over it)
    lift = pose.get("lift", 0)
    if abs(lift) < 0.05:
        d.line([(ox - 90, oy), (ox + 90, oy)], fill=(150, 150, 150), width=1)
    else:
        for x in range(-90, 90, 8):
            d.line([(ox + x, oy), (ox + x + 4, oy)], fill=(170, 170, 170), width=1)
        d.text((ox + 40, oy + 2), f"{lift:+.1f} studs", fill=(120, 120, 120))
    polys = []
    for part in pose["parts"]:
        base = COLORS.get(part["name"], (120, 120, 120))
        if part["name"].startswith("Right") and part["name"] not in ("RightHand", "RightLowerArm"):
            base = tuple(int(0.75 * c + 0.25 * k) for c, k in zip(base, RIGHT_SIDE))
        for normal, corners in faces(part):
            if dot(normal, back) <= 0.01:
                continue
            depth = sum(dot(c, back) for c in corners) / 4
            shade = 0.45 + 0.55 * max(0.0, dot(normal, light) / math.sqrt(dot(light, light)))
            color = tuple(min(255, int(c * shade + 18)) for c in base)
            polys.append((depth, [to2d(c) for c in corners], color))
    polys.sort(key=lambda t: t[0])
    for _, pts, color in polys:
        d.polygon(pts, fill=color, outline=(20, 20, 20))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("luau")
    parser.add_argument("out", type=Path)
    parser.add_argument("--side", action="store_true", help="from the right instead of three-quarters")
    parser.add_argument("--only", help="draw only the poses whose title has one of these words (comma-separated), larger")
    args = parser.parse_args()
    poses = export(args.luau)
    cols = 6
    if args.only:
        words = [w.strip().lower() for w in args.only.split(",")]
        poses = [p for p in poses if any(w in p["title"].lower() for w in words)]
        CELL[0], CELL[1], SCALE[0] = 360, 440, 52
        cols = min(cols, max(1, len(poses)))
    rows = math.ceil(len(poses) / cols)
    img = Image.new("RGB", (cols * CELL[0], rows * CELL[1] + 30), (236, 236, 232))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 13)
        small = ImageFont.truetype("DejaVuSans.ttf", 11)
    except OSError:
        font = small = ImageFont.load_default()
    d.text((8, 8), "Zombie Delivery 6.24 · the gait (shared/Gait.luau) on the classic R15 block body · right side tinted red",
           fill=(30, 30, 30), font=font)
    for k, pose in enumerate(poses):
        col, row = k % cols, k // cols
        x0, y0 = col * CELL[0], 30 + row * CELL[1]
        d.rectangle([x0 + 2, y0 + 2, x0 + CELL[0] - 3, y0 + CELL[1] - 3], outline=(200, 200, 196))
        draw_pose(img, pose, (x0 + CELL[0] / 2, y0 + CELL[1] - 50), args.side)
        d.text((x0 + 8, y0 + CELL[1] - 40), pose["title"], fill=(20, 20, 20), font=font)
        if pose["note"]:
            d.text((x0 + 8, y0 + CELL[1] - 22), pose["note"], fill=(90, 90, 90), font=small)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    img.save(args.out)
    print(f"{len(poses)} poses -> {args.out}")


if __name__ == "__main__":
    main()
