#!/usr/bin/env python3
"""8.9.1: server/FixtureMesh.luau's Looks from the blender model's finishes (design/blender-fixtures/KONTRAKT.md).

Reads the finishes from the manifest ZDCFixtureArt.json ("finishes": name → color, material, palette, reflectance,
transparency) or straight from fixtures.py (its FINISHES, GAME and PALETTE tables, before an export), and prints the
LOOKS table as FixtureMesh.luau has it; --write puts it into FixtureMesh.luau in place of the one there.
tools/fixtures-art/check.py fails when the two differ.

    python3 zombie-delivery/tools/fixtures-art/looks.py [ZDCFixtureArt.json | fixtures.py] [--write]
"""
import ast
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "design/blender-fixtures/roblox/ZDCFixtureArt.json"
MESH = ROOT / "src/server/FixtureMesh.luau"
# The palette finishes take the colour of these parts of the fixture (the first one it has), as the house rolled it.
SOURCES = {"tile": ("Stove",), "tile2": ("Upper",), "pine": ("Seat", "StoveBench"), "cushion": ("Cushion",)}
START = "local LOOKS: { [string]: Look } = {"


def literal(text: str, name: str):
    """A top-level `NAME = <literal>` of a Python file (fixtures.py imports bpy: it is read, not run)."""
    match = re.search(rf"^{name} = ", text, re.M)
    if not match:
        return None
    tree = ast.parse(text[match.start():].split("\n\n")[0])
    return ast.literal_eval(tree.body[0].value)


def finishes_of(path: Path) -> dict:
    if path.suffix == ".py":
        text = path.read_text(encoding="utf-8")
        table, extra, palette = literal(text, "FINISHES"), literal(text, "GAME") or {}, literal(text, "PALETTE") or ()
        out = {}
        for name, (hexcode, _, _, _, material) in table.items():
            out[name] = {"color": hexcode.upper(), "material": material, "palette": name in palette, **extra.get(name, {})}
        return out
    return json.loads(path.read_text(encoding="utf-8"))["finishes"]


def lua(finishes: dict) -> str:
    lines = [START]
    for name, look in finishes.items():
        fields = [f'color = hex("{look["color"].lstrip("#").upper()}")', f"material = M.{look['material']}"]
        if look.get("palette"):
            fields.append("palette = { " + ", ".join(f'"{p}"' for p in SOURCES[name]) + " }")
        for key in ("transparency", "reflectance"):
            if look.get(key):
                fields.append(f"{key} = {look[key]:g}")
        lines.append(f"\t{name} = {{ {', '.join(fields)} }},")
    lines.append("}")
    return "\n".join(lines)


def main():
    args = [a for a in sys.argv[1:] if a != "--write"]
    source = Path(args[0]) if args else MANIFEST
    block = lua(finishes_of(source))
    if "--write" not in sys.argv:
        print(block)
        return
    text = MESH.read_text(encoding="utf-8")
    start = text.index(START)
    end = text.index("\n}\n", start) + 2
    MESH.write_text(text[:start] + block + text[end:], encoding="utf-8")
    print(f"FixtureMesh.Looks: {len(finishes_of(source))} finishes from {source.name}")


if __name__ == "__main__":
    main()
