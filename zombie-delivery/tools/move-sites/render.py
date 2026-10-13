#!/usr/bin/env python3
"""7.0: a preview sheet of the moves' world, as the real server/MoveSites.luau builds it (check.py's export on the
recorder, its checks first): the Wall's checkpoint at the depot from Bone St and from the yard, the Moving contracts
kiosk, the depot's banner, Marge's house on moving day and two evacuation spots, drawn with three.js in headless
Chromium (render.mjs, render.html) with the world round them (the depot's hall, Marge's street) and laid out with PIL.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/move-sites/render.py <luau> <three.module.min.js> <sheet.png>

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Chromium from
CHROMIUM (default /opt/pw-browsers/chromium).
"""
import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
sys.dont_write_bytecode = True  # (no __pycache__ next to check.py)
spec = importlib.util.spec_from_file_location("move_sites_check", HERE / "check.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def centre(records, kind_set):
    xs = [r["position"] for r in records if r["kind"] == "part" and r["set"] == kind_set]
    return [sum(p[i] for p in xs) / len(xs) for i in range(3)]


def views(records):
    """The cameras (eye, target, field of view, picture size, the sun's shadow box)."""
    s = records[-1]
    walk = s["walk"]
    cx, cz = s["dropOff"]
    bx, bz = s["board"]
    dx, dz = s["depot"]
    home = s["homes"][0]
    hx, hz = home["door"]
    fx, fz = home["facing"]
    out = []

    def add(name, eye, target, size, fov=45, shadow=70):
        out.append({"name": name, "eye": eye, "target": target, "size": size, "fov": fov, "shadow": shadow})

    add("checkpoint_street", [cx - 34, walk + 19, cz + 44], [cx + 2, walk + 6, cz - 4], [1200, 600], 50, 60)
    add("checkpoint_yard", [cx + 2, walk + 26, cz - 52], [cx - 3, walk + 3, cz + 1], [600, 380], 50, 60)
    add("banner", [dx + 6, walk + 9, dz + 34], [dx, walk + 15, dz - 8], [600, 380], 55, 60)
    add("board", [bx - 10.5, walk + 6.4, bz + 3.5], [bx, walk + 5, bz - 0.2], [600, 380], 45, 20)
    # Marge's house from the street: out of the door and a little to its right, looking back at it
    rx, rz = -fz, fx  # (the door's right, as it looks out)
    add("house", [hx + fx * 28 + rx * 7, walk + 10, hz + fz * 28 + rz * 7], [hx + fx * 7 - rx * 1.5, walk + 3, hz + fz * 7 - rz * 1.5], [600, 380], 52, 40)
    for n in (1, 3):
        p = centre(records, f"EvacuationSpot{n}")
        poster = next(r for r in records if r["kind"] == "part" and r["set"] == f"EvacuationSpot{n}" and r["name"] == "PosterBoard")
        r = poster["rotation"]
        ox, oz = -r[2], -r[8]  # its -Z (out to the street) in the world
        add(f"spot{n}", [p[0] + ox * 13 + oz * 5, walk + 5.5, p[2] + oz * 13 - ox * 5], [p[0], walk + 2.2, p[2]], [600, 380], 50, 25)
    return out


def sheet(renders: Path, records, output: Path):
    s = records[-1]
    head = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    counts = {}
    for r in records:
        if r["kind"] == "part":
            counts[r["set"]] = counts.get(r["set"], 0) + 1
    spots = sum(v for k, v in counts.items() if k.startswith("EvacuationSpot"))
    rows = [
        [("checkpoint_street", f"THE WALL · EVACUATION CHECKPOINT at the drop-off, from Bone St · {counts.get('checkpoint', 0)} parts")],
        [("checkpoint_yard", "…from the depot's yard (the army truck, the booth)"), ("banner", f"ZDC MOVING & EVACUATION over the hall's door · {counts.get('banner', 0)} parts")],
        [("board", f"MOVING CONTRACTS kiosk (its prompt on the corkboard) · {counts.get('board', 0)} parts"), ("house", f"Marge's House, 155 Willow Ln, on moving day · {counts.get('house_marge', 0)} parts")],
        [("spot1", "Evacuation spot: Bone St, across the avenue"), ("spot3", f"Evacuation spot: Willow Ln · 3 spots, {spots} parts")],
    ]
    width, title, pad = 1200, 64, 30
    heights = []
    for row in rows:
        h = max(Image.open(renders / f"{name}.png").size[1] for name, _ in row)
        heights.append(h)
    img = Image.new("RGB", (width, title + sum(h + pad for h in heights) + 10), (14, 16, 20))
    draw = ImageDraw.Draw(img)
    draw.text((16, 12), f"ZOMBIE DELIVERY 7.0 · THE MOVES' WORLD · {int(s['parts'])} parts (budget {int(s['budget'])})", fill=(242, 242, 240), font=head)
    draw.text((16, 42), "server/MoveSites.luau built on the recorder, three.js; grey: the world round it (context)", fill=(150, 156, 166), font=small)
    y = title
    for row, h in zip(rows, heights):
        x = 0
        for name, label in row:
            picture = Image.open(renders / f"{name}.png").convert("RGB")
            draw.text((x + 12, y + 6), label, fill=(240, 132, 44), font=font)
            img.paste(picture, (x, y + pad - 4))
            x += picture.size[0]
        y += h + pad
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output)
    print(f"Sheet: {len(rows)} rows -> {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--keep", type=Path, help="also keep the single renders in this folder")
    args = parser.parse_args()
    records = check.export(args.luau)
    bad = check.check(records)
    if bad:
        raise SystemExit("check.py fails first:\n  " + "\n  ".join(bad))
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        site = tmp / "site"
        site.mkdir()
        shutil.copy(HERE / "render.html", site / "render.html")
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        (tmp / "scene.json").write_text(json.dumps(records))
        (tmp / "views.json").write_text(json.dumps(views(records)))
        out = args.keep or (tmp / "renders")
        subprocess.run(["node", str(HERE / "render.mjs"), str(tmp / "scene.json"), str(tmp / "views.json"), str(out), str(site)], check=True)
        sheet(out, records, args.output)


if __name__ == "__main__":
    main()
