#!/usr/bin/env python3
"""7.1, the Alps: a preview of shared/AlpineLayout.luau (the same numbers server/Alpine.luau builds) without Roblox.

  * a top-down overview PNG: the ring of mountains (its terrain's top, shaded, by material: grass, rock, limestone,
    snow, glacier) and the forests, meadows and huts drawn over the map's roads, districts, yards and water;
  * optionally a 3/4 view of one stretch (the West Pass, the Old Farm and the west mountains by default) drawn with
    three.js in headless Chromium (view.mjs, view.html): the terrain's layers as a height field, the trees, the huts,
    the portal and its barrier.

    python3 zombie-delivery/tools/alpine-preview/render.py <luau> <overview.png> [--view <view.png> --three <three.module.min.js>]

The 3/4 view needs Playwright (NODE_PATH, e.g. /opt/node22/lib/node_modules) and Chromium (CHROMIUM, default
/opt/pw-browsers/chromium); three.module.min.js is three.js's build (e.g. three@0.160 from npm).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]
SHARED = GAME / "src" / "shared"

MATERIALS = {
    0: None,
    1: "Grass",
    2: "Rock",
    3: "Limestone",
    4: "Snow",
    5: "Glacier",
    6: "Ground",
}


def export(luau, out, args=()):
    """Copy the pure shared modules next to export.luau (their requires made plain) and run it."""
    for name in ("Config", "Map", "AlpineLayout"):
        src = (SHARED / f"{name}.luau").read_text(encoding="utf-8")
        src = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', src)
        (out / f"{name}.luau").write_text(src, encoding="utf-8")
    shutil.copy(HERE / "export.luau", out / "export.luau")
    result = subprocess.run([luau, "export.luau", *(["-a", *map(str, args)] if args else [])], cwd=out, capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        raise SystemExit(result.stdout + result.stderr)
    return json.loads(result.stdout.strip().splitlines()[-1])


def font(size, bold=False):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def overview(data, path):
    g = data["wide"]
    nx, nz, cell = g["nx"], g["nz"], g["cell"]
    X0, Z0 = g["x0"], g["z0"]
    heights = np.array(g["h"], dtype=float).reshape(nz, nx)
    mats = np.array(g["m"], dtype=int).reshape(nz, nx)
    colors = {k: np.array(v, dtype=float) for k, v in data["colors"].items()}
    box = data["box"]
    river, sea = data["river"], data["sea"]
    bounds = data["bounds"]

    # The ground first: the valley's grass, the winter's snow, the water, the void outside the world's ground.
    xs = X0 + np.arange(nx) * cell
    zs = Z0 + np.arange(nz) * cell
    XX, ZZ = np.meshgrid(xs, zs)
    img = np.zeros((nz, nx, 3))
    img[:] = (52, 58, 52)
    ground = (XX > bounds[0] - 700) & (XX < bounds[2] + 700) & (ZZ > bounds[1] - 700) & (ZZ < bounds[3] + 700)
    img[ground] = (96, 138, 60)
    winter = ground & (ZZ < data["winterZ"]) & (XX < river[0])
    img[winter] = (232, 236, 240)
    water = ((XX > river[0]) & (XX < river[1]) | (XX > sea) & (XX < bounds[2] + 250)) & (ZZ > bounds[1] - 300) & (ZZ < bounds[3] + 300)
    img[water] = (64, 120, 150)
    lake = data["lake"]
    img[(XX > lake[0]) & (XX < lake[2]) & (ZZ > lake[1]) & (ZZ < lake[3])] = (178, 214, 232)

    # The ring: by material, shaded (light from the north-west, high).
    terrain = heights > -900
    hz = np.where(terrain, heights, 0.0)
    gx = np.gradient(hz, cell, axis=1)
    gz = np.gradient(hz, cell, axis=0)
    normal = np.dstack([-gx, np.ones_like(gx), -gz])
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    light = np.array([-0.55, 0.75, -0.45])
    light /= np.linalg.norm(light)
    shade = np.clip(np.einsum("ijk,k->ij", normal, light), 0, 1)
    shade = 0.45 + 0.75 * shade
    for code, name in MATERIALS.items():
        if name is None or name not in colors:
            continue
        sel = terrain & (mats == code)
        img[sel] = colors[name]
    img[terrain] *= shade[terrain][:, None]
    # (a hint of height: the summits a touch lighter)
    img[terrain] += np.clip(hz[terrain] / 700.0, 0, 1)[:, None] * 18
    img = np.clip(img, 0, 255).astype(np.uint8)

    scale = 0.24  # pixels a stud
    W, H = int(nx * cell * scale), int(nz * cell * scale)
    pic = Image.fromarray(img, "RGB").resize((W, H), Image.BILINEAR)
    margin_top, margin_side, margin_bottom = 110, 40, 150
    sheet = Image.new("RGB", (W + 2 * margin_side, H + margin_top + margin_bottom), (18, 20, 24))
    sheet.paste(pic, (margin_side, margin_top))
    d = ImageDraw.Draw(sheet, "RGBA")

    def P(x, z):
        return margin_side + (x - X0) * scale, margin_top + (z - Z0) * scale

    # The map: the districts, the yards, the homes' lots, the roads.
    for x0, z0, x1, z1, name in data["districts"]:
        d.rectangle([P(x0, z0), P(x1, z1)], fill=(150, 146, 136, 230), outline=(90, 88, 84))
    for x0, z0, x1, z1, name in data["yards"]:
        d.rectangle([P(x0, z0), P(x1, z1)], fill=(176, 160, 128, 220), outline=(110, 98, 76))
    for x0, z0, x1, z1, name in data["plots"]:
        d.rectangle([P(x0, z0), P(x1, z1)], fill=(214, 196, 160, 220), outline=(120, 100, 70))
    mx, mz, mr = data["mountain"]
    d.ellipse([P(mx - mr, mz - mr), P(mx + mr, mz + mr)], fill=(124, 120, 112, 255), outline=(80, 78, 74))
    for ax, az, bx, bz, width, kind in data["roads"]:
        w = max(1, int(width * scale))
        color = (60, 60, 64) if kind != "ice" else (150, 190, 210)
        d.line([P(ax, az), P(bx, bz)], fill=color, width=w)

    # The portal's road and its barrier, the waterfall.
    for entry in data["portals"]:
        for part in entry["parts"]:
            if part["name"] in ("PassRoad",):
                half = part["sx"] / 2
                p = entry["portal"]
                vx, vz = -p["nz"], p["nx"]
                L = part["sz"] / 2
                ux, uz = p["nx"], p["nz"]
                cx, cz = part["x"], part["z"]
                corners = [
                    P(cx + ux * L + vx * half, cz + uz * L + vz * half),
                    P(cx + ux * L - vx * half, cz + uz * L - vz * half),
                    P(cx - ux * L - vx * half, cz - uz * L - vz * half),
                    P(cx - ux * L + vx * half, cz - uz * L + vz * half),
                ]
                d.polygon(corners, fill=(60, 60, 64))
            if part["name"] == "Barrier":
                x, y = P(part["x"], part["z"])
                d.rectangle([x - 2, y - 2, x + 2, y + 2], fill=(230, 60, 50))
    for part in data["waterfall"]:
        x, y = P(part["x"], part["z"])
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(200, 235, 250, 255), outline=(80, 150, 190))

    # The forests: every tree, its canopy to scale (at least a dot).
    tree_colors = data["treeColors"]
    for x, y, z, h, variant, snowy, slope, yaw in data["trees"]:
        r = max(1.3, h * 0.19 * scale)
        c = tree_colors[variant - 1]
        c = tuple(int(v * (0.85 if slope else 1.0)) for v in c)
        if snowy:
            c = (150, 170, 160)
        cx, cy = P(x, z)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c + (255,))
    for patch in data["patches"]:
        for fx, fz, size, color in patch["flowers"]:
            cx, cy = P(fx, fz)
            d.ellipse([cx - 1.2, cy - 1.2, cx + 1.2, cy + 1.2], fill=tuple(color) + (255,))
    for entry in data["huts"]:
        hut = entry["hut"]
        cx, cy = P(hut["x"], hut["z"])
        d.rectangle([cx - 3.5, cy - 3.5, cx + 3.5, cy + 3.5], fill=(120, 80, 50), outline=(250, 230, 200))

    # The box (the world's walls) as a dashed line.
    bx0, bz0 = P(box[0], box[1])
    bx1, bz1 = P(box[2], box[3])
    for a, b in (((bx0, bz0), (bx1, bz0)), ((bx1, bz0), (bx1, bz1)), ((bx1, bz1), (bx0, bz1)), ((bx0, bz1), (bx0, bz0))):
        length = ((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5
        steps = int(length // 10)
        for k in range(0, steps, 2):
            t0, t1 = k / steps, min((k + 1) / steps, 1)
            d.line([(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0), (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)], fill=(255, 210, 90, 200), width=2)

    # Labels.
    small, mid, big = font(15), font(18, True), font(30, True)

    def label(text, x, z, f=small, fill=(255, 255, 255)):
        px, py = P(x, z)
        w = d.textlength(text, font=f)
        d.text((px - w / 2, py - f.size / 2), text, font=f, fill=fill, stroke_width=3, stroke_fill=(15, 18, 22))

    for x0, z0, x1, z1, name in data["districts"]:
        label(name.upper(), (x0 + x1) / 2, (z0 + z1) / 2, mid)
    for x0, z0, x1, z1, name in data["yards"]:
        if name in ("Military Base", "Ski Lodge", "Old Farm", "Old Airfield", "Blackrock Prison", "Lighthouse Point", "Silver Spur Ranch"):
            label(name, (x0 + x1) / 2, z1 + 40, small, (255, 236, 200))
    label("Mount Rot", mx, mz, small)
    for p in data["portals"]:
        q = p["portal"]
        label("WEST PASS · ROAD CLOSED", q["x"] + 330, q["z"] + 80, mid, (255, 120, 100))
    for gorge in data["gorges"]:
        label("river gorge", gorge["x"] + 260, gorge["z"] + gorge["nz"] * 200, small, (190, 230, 255))
    if data["waterfall"]:
        w0 = data["waterfall"][0]
        label("waterfall", w0["x"] - 210, w0["z"] - 120, small, (190, 230, 255))
    label("ALPINE LAKE (the old sea)", (sea + box[2]) / 2 + 90, -1650, small, (190, 230, 255))

    s = data["stats"]
    title = "Zombie Delivery 7.1 · The Alps, step 1B: mountains and forests (top-down, north up)"
    d.text((margin_side, 22), title, font=big, fill=(255, 255, 255))
    d.text((margin_side, 66), "From shared/AlpineLayout.luau (the numbers server/Alpine.luau builds). Dashed: the world's walls (Map.Bounds), nothing you play on moved.", font=small, fill=(190, 196, 204))
    lines = [
        f"Mountains: {s['cones']} terrain cones (front row 250–420, back row 480–700 studs, shoulders, gorge closers, the pass), {s['fills']} terrain fills, "
        f"{s['volume'] / 1e9:.1f} billion studs³, {s['glaciers']} glaciers, {s['scree']} scree fans, {s['silhouettes']} far silhouettes.",
        f"Forests: {s['trees']} trees × 4 parts (spruce and fir, snowy in the winter), {s['patches']} wildflower meadows, {s['huts']} hay barns and huts; "
        f"{s['parts']} parts in all.",
        f"The ring holds the box: a car {'cannot' if s['sealedCar'] else 'CAN'} get out over ground lower than the seal; "
        f"{'not even swimming' if s['sealedSwim'] else 'BUT swimming can'} (the river's gorges and the lake are closed).",
    ]
    y = H + margin_top + 18
    for line in lines:
        d.text((margin_side, y), line, font=small, fill=(220, 224, 230))
        y += 26
    # A legend.
    lx = margin_side
    y += 8
    for name, color in (("grass", data["colors"]["Grass"]), ("rock", data["colors"]["Rock"]), ("limestone", data["colors"]["Limestone"]), ("snow", data["colors"]["Snow"]), ("glacier", data["colors"]["Glacier"]), ("spruce / fir", tree_colors[1]), ("road", (60, 60, 64)), ("district", (150, 146, 136)), ("yard / place", (176, 160, 128))):
        d.rectangle([lx, y, lx + 18, y + 18], fill=tuple(color), outline=(230, 230, 230))
        d.text((lx + 24, y), name, font=small, fill=(220, 224, 230))
        lx += 34 + d.textlength(name, font=small) + 14
    sheet.save(path)
    print(f"wrote {path} ({sheet.width} × {sheet.height})")


def view(data, path, three):
    work = Path(tempfile.mkdtemp())
    try:
        shutil.copy(HERE / "view.html", work / "view.html")
        shutil.copy(three, work / "three.module.min.js")
        (work / "scene.json").write_text(json.dumps(data))
        result = subprocess.run(["node", str(HERE / "view.mjs"), str(work), str(path)], capture_output=True, text=True, timeout=900, env=dict(os.environ))
        print(result.stdout + result.stderr)
        if result.returncode != 0:
            raise SystemExit("the 3/4 view failed")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("luau")
    parser.add_argument("overview")
    parser.add_argument("--view")
    parser.add_argument("--three")
    parser.add_argument("--stretch", nargs=5, type=float, help="x0 z0 x1 z1 cell of the 3/4 view")
    parser.add_argument("--camera", nargs=7, type=float, help="eye x y z, target x y z, field of view of the 3/4 view")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        data = export(os.path.abspath(args.luau), Path(tmp), args.stretch or ())
    if args.camera:
        c = args.camera
        data["camera"] = {"eye": c[0:3], "target": c[3:6], "fov": c[6]}
    print(json.dumps(data["stats"]))
    overview(data, args.overview)
    if args.view:
        if not args.three:
            raise SystemExit("--view needs --three <three.module.min.js>")
        view(data, os.path.abspath(args.view), os.path.abspath(args.three))


if __name__ == "__main__":
    main()
