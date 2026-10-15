#!/usr/bin/env python3
"""8.9: the Jinočany village's looks for the owner (design/jinocany/looks/*.png), without Roblox.

shared/VillageLooks.luau (the real one, with shared/Config.luau and design/jinocany/plan.json as Luau) builds every shot
in the Luau CLI (export.luau): each house kind alone (the old Czech family house with either roof, two of the six to
empty, a terraced row and the one with a house to empty, the new builds), each landmark (the chapel green, the chapel,
the pond, the Corner Drugstore, the D5, Hornická's barrier, Stavebniny Sýkorka for step 2), the trees and the field
tiles, a street of the step-1 village (Hlavní and the green) and all of it from above with the far view. render.mjs
draws them with three.js in headless Chromium (render.html: a warm summer afternoon) and this lays out four sheets:

    houses.png     the houses        landmarks.png   the landmarks, the trees, the fields
    street.png     Hlavní and the green, step 1        village.png     the whole step-1 village and the far view

The roads, the lawns and today's warehouses, farmstead and Auction House are drawn from plan.json as plain shapes for
the picture only (the village does not build them).

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/village/preview.py <luau> <three.module.min.js> [--out DIR]

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); Chromium from
CHROMIUM (default /opt/pw-browsers/chromium); --out defaults to design/jinocany/looks.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]
SHARED = GAME / "src" / "shared"
PLAN = GAME / "design" / "jinocany" / "plan.json"
sys.dont_write_bytecode = True

BG = (29, 33, 39)
INK = (236, 238, 240)
SOFT = (170, 178, 188)


def luau_value(v):
    """plan.json's values as a Luau expression."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "{ " + ", ".join(luau_value(x) for x in v) + " }"
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            key = k if re.fullmatch(r"[A-Za-z_]\w*", k) else "[" + json.dumps(k, ensure_ascii=False) + "]"
            items.append(f"{key} = {luau_value(x)}")
        return "{ " + ", ".join(items) + " }"
    return "nil"


def export(luau: str, folder: Path):
    for name in ("Config", "VillageLooks"):
        source = (SHARED / f"{name}.luau").read_text(encoding="utf-8")
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
        (folder / f"{name}.luau").write_text(source, encoding="utf-8")
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    plan["lines"] = plan["treeLines"]
    plan["fixed"] = plan.get("fixedBuildings", [])
    (folder / "Plan.luau").write_text("return " + luau_value(plan) + "\n", encoding="utf-8")
    shutil.copy(HERE / "export.luau", folder / "main.luau")
    result = subprocess.run([luau, "main.luau"], cwd=folder, capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        raise SystemExit(result.stdout[-3000:] + result.stderr[-3000:] + "\nvillage preview: the export failed")
    shots = [json.loads(line[5:]) for line in result.stdout.splitlines() if line.startswith("SHOT ")]
    if not shots:
        raise SystemExit(result.stdout[-3000:] + "\nvillage preview: no shots")
    return shots


def font(size, bold=False):
    for name in (("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"), ("LiberationSans-Bold.ttf" if bold else "LiberationSans-Regular.ttf")):
        for folder in ("/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation"):
            path = Path(folder) / name
            if path.exists():
                return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def sheet(title, note, tiles, columns, out: Path):
    """tiles: [(image, caption)] laid out `columns` a row under a title."""
    pad, head, cap = 22, 96, 34
    tw, th = tiles[0][0].size
    rows = (len(tiles) + columns - 1) // columns
    width = pad + columns * (tw + pad)
    height = head + rows * (th + cap + pad) + pad // 2
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)
    draw.text((pad, 18), title, font=font(34, True), fill=INK)
    draw.text((pad, 62), note, font=font(17), fill=SOFT)
    for i, (tile, caption) in enumerate(tiles):
        x = pad + (i % columns) * (tw + pad)
        y = head + (i // columns) * (th + cap + pad)
        img.paste(tile, (x, y))
        draw.text((x + 2, y + th + 7), caption, font=font(17), fill=INK)
    img.save(out, optimize=True)
    print(f"village preview: {out} ({width} × {height})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("--out", type=Path, default=GAME / "design" / "jinocany" / "looks")
    args = parser.parse_args()
    luau = str(Path(args.luau).resolve())
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        stage = folder / "stage"
        stage.mkdir()
        shots = export(luau, stage)
        site = folder / "site"
        site.mkdir()
        shutil.copy(HERE / "render.html", site / "render.html")
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        (folder / "shots.json").write_text(json.dumps(shots), encoding="utf-8")
        renders = folder / "renders"
        subprocess.run(["node", str(HERE / "render.mjs"), str(site), str(folder / "shots.json"), str(renders)], check=True)
        by = {s["name"]: (Image.open(renders / f"{s['name']}.png").convert("RGB"), s["caption"]) for s in shots}
        args.out.mkdir(parents=True, exist_ok=True)
        houses = [by[n] for n in by if n.startswith(("old", "rich", "row", "modern"))]
        marks = [by[n] for n in ("green", "chapel", "pond", "shop", "motorway", "barrier", "hardware", "trees", "fields") if n in by]
        sheet("Jinočany: domy (VillageLooks.house)",
              "Český rodinný dům se štukem, taškovou střechou, komínem, okny v rámech, plotem a brankou; řadovky jedním tělem; novostavby. "
              "Každý dům nejvýš 15 dílů, domy ke stěhování nejvýš 25.", houses, 4, args.out / "houses.png")
        sheet("Jinočany: místa, stromy a pole (VillageLooks.landmark, tree, field)",
              "Náves s kaplí, rybník, drogerie (vymyšlená), D5, konec Hornické, Stavebniny Sýkorka (krok 2); lípy, duby, břízy, topoly, "
              "vrby a ovocné stromy; pole v barvách plodin. Nic alpského.", marks, 3, args.out / "landmarks.png")
        for name, title in (("street", "Jinočany: Hlavní a náves (krok 1)"), ("village", "Jinočany: celá vesnice v kroku 1 a obzor")):
            image, caption = by[name]
            sheet(title, caption, [(image, "")], 1, args.out / f"{name}.png")


if __name__ == "__main__":
    main()
