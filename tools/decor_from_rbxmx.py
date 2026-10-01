#!/usr/bin/env python3
"""
decor_from_rbxmx.py — turns a designed arena (.rbxmx saved from Roblox Studio / Claude Design, one
top-level Model with a Model per prop) into a Luau data module the game builds the arena look from.

Usage:
    python tools/decor_from_rbxmx.py design/TrainingArena1.rbxmx src/server/Services/DecorData/TrainingArena1.luau

Expected input: a top-level Model with the model "ArenaFloor" (the floor and its ring discs) and any
number of prop models (EntranceArch, WoodenFence, Torch, ...). Only ONE copy of every prop is stored
(the first one that is not rotated); the game places copies of it where it wants (see ArenaDecor.luau).
Every stored part is relative to its model's anchor: the middle of the model in x / z and the floor
(the top of the ArenaFloor) in y. Output per part: name, size, cf (relative CFrame), color, material,
shape, transparency, reflectance, an optional light (PointLight) and optional text on the faces of
the part (SurfaceGui + TextLabel).
"""

import sys
import xml.etree.ElementTree as ET


def text(element, path, default=None):
    node = element.find(path)
    return node.text if node is not None else default


def number(value: float) -> str:
    value = round(value, 4)
    if value == 0:
        return "0"
    return str(int(value)) if value == int(value) else str(value)


def color_of(packed: int):
    return ((packed >> 16) & 255, (packed >> 8) & 255, packed & 255)


def rgb_float(element):
    return tuple(round(float(element.find(a).text) * 255) for a in "RGB")


def part_data(part):
    props = part.find("Properties")
    frame = props.find("CoordinateFrame")
    position = [float(frame.find(a).text) for a in "XYZ"]
    rotation = [float(frame.find(a).text) for a in ["R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]]
    size = [float(props.find(f"Vector3[@name='size']/{a}").text) for a in "XYZ"]
    data = {
        "name": text(props, "string[@name='Name']"),
        "size": size,
        "position": position,
        "rotation": rotation,
        "color": color_of(int(text(props, "Color3uint8[@name='Color3uint8']"))),
        "material": int(text(props, "token[@name='Material']", "272")),
        "shape": text(props, "token[@name='shape']"),
        "transparency": float(text(props, "float[@name='Transparency']", "0")),
        "reflectance": float(text(props, "float[@name='Reflectance']", "0")),
        "collide": text(props, "bool[@name='CanCollide']", "true") == "true",
        "light": None,
        "guis": [],
    }
    for child in part.findall("Item"):
        cls = child.get("class")
        cprops = child.find("Properties")
        if cls == "PointLight":
            data["light"] = {
                "color": rgb_float(cprops.find("Color3[@name='Color']")),
                "brightness": float(text(cprops, "float[@name='Brightness']", "1")),
                "range": float(text(cprops, "float[@name='Range']", "8")),
            }
        elif cls == "SurfaceGui":
            label = child.find("Item[@class='TextLabel']")
            if label is not None:
                lprops = label.find("Properties")
                data["guis"].append({
                    "face": int(text(cprops, "token[@name='Face']", "5")),
                    "text": text(lprops, "string[@name='Text']", ""),
                    "color": rgb_float(lprops.find("Color3[@name='TextColor3']")),
                    "stroke": rgb_float(lprops.find("Color3[@name='TextStrokeColor3']")),
                    "font": text(lprops, "Font[@name='FontFace']/Family/url", ""),
                })
    return data


def is_identity(rotation):
    return all(abs(a - b) < 1e-4 for a, b in zip(rotation, [1, 0, 0, 0, 1, 0, 0, 0, 1]))


def bounds(parts):
    lo = [min(p["position"][i] - p["size"][i] / 2 for p in parts) for i in range(3)]
    hi = [max(p["position"][i] + p["size"][i] / 2 for p in parts) for i in range(3)]
    return lo, hi


def rgb(c):
    return f"C({c[0]}, {c[1]}, {c[2]})"


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    source, target = sys.argv[1], sys.argv[2]
    top = ET.parse(source).getroot().find("Item")

    floor_model = None
    props = {}
    for model in top.findall("Item"):
        name = text(model, "Properties/string[@name='Name']")
        parts = [part_data(p) for p in model.findall("Item[@class='Part']")]
        if name == "ArenaFloor":
            floor_model = parts
            continue
        # Keep the first copy whose parts are all unrotated (or the first copy if all are rotated).
        unrotated = all(is_identity(p["rotation"]) for p in parts)
        if name not in props or (unrotated and not props[name][1]):
            props[name] = (parts, unrotated)

    assert floor_model, "no ArenaFloor model"
    ground = max(p["position"][1] + p["size"][1] / 2 for p in floor_model if p["size"][0] > 10 and p["size"][1] < 2)
    base = [p for p in floor_model if p["size"][0] > 10 and p["size"][1] < 2][0]
    rings = [p for p in floor_model if p is not base]

    out = [
        "--!strict",
        f"-- GENERATED by tools/decor_from_rbxmx.py from {source.replace(chr(92), '/').split('/')[-1]}.",
        "-- Do not edit by hand: change the design and run the tool again.",
        "-- Every part is relative to its model's anchor (middle in x / z, the floor level in y, facing +z).",
        "",
        "local V = Vector3.new",
        "local C = Color3.fromRGB",
        "local CF = CFrame.new",
        "",
        "export type Light = { color: Color3, brightness: number, range: number }",
        "export type Gui = { face: number, text: string, color: Color3, stroke: Color3, font: string }",
        "export type Part = {",
        "\tname: string,",
        "\tsize: Vector3,",
        "\tcf: CFrame,",
        "\tcolor: Color3,",
        "\tmaterial: number, -- an Enum.Material value",
        "\tshape: number?, -- an Enum.PartType value",
        "\ttransparency: number?,",
        "\treflectance: number?,",
        "\tcollide: boolean?,",
        "\tlight: Light?,",
        "\tguis: { Gui }?,",
        "}",
        "",
        "return {",
        f"\tfloorColor = {rgb(base['color'])},",
        f"\tfloorMaterial = {base['material']},",
        "\t-- The round marks in the middle of the floor (thin discs, outermost first).",
        "\trings = {",
    ]
    for ring in sorted(rings, key=lambda p: -p["size"][1]):
        out.append(f"\t\t{{ diameter = {number(ring['size'][1])}, thickness = {number(ring['size'][0])}, color = {rgb(ring['color'])}, material = {ring['material']} }},")
    out.append("\t},")
    out.append("\tmodels = {")

    for name, (parts, _) in props.items():
        lo, hi = bounds(parts)
        cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
        out.append(f"\t\t{name} = {{")
        for p in parts:
            x, y, z = p["position"][0] - cx, p["position"][1] - ground, p["position"][2] - cz
            frame = f"CF({number(x)}, {number(y)}, {number(z)})" if is_identity(p["rotation"]) else \
                f"CF({number(x)}, {number(y)}, {number(z)}, {', '.join(number(v) for v in p['rotation'])})"
            fields = [f'name = "{p["name"]}"', f"size = V({', '.join(number(v) for v in p['size'])})", f"cf = {frame}", f"color = {rgb(p['color'])}", f"material = {p['material']}"]
            if p["shape"] is not None:
                fields.append(f"shape = {p['shape']}")
            if p["transparency"]:
                fields.append(f"transparency = {number(p['transparency'])}")
            if p["reflectance"]:
                fields.append(f"reflectance = {number(p['reflectance'])}")
            if not p["collide"]:
                fields.append("collide = false")
            if p["light"]:
                l = p["light"]
                fields.append(f"light = {{ color = {rgb(l['color'])}, brightness = {number(l['brightness'])}, range = {number(l['range'])} }}")
            if p["guis"]:
                guis = ", ".join(
                    f'{{ face = {g["face"]}, text = "{g["text"]}", color = {rgb(g["color"])}, stroke = {rgb(g["stroke"])}, font = "{g["font"]}" }}'
                    for g in p["guis"]
                )
                fields.append(f"guis = {{ {guis} }}")
            out.append("\t\t\t{ " + ", ".join(fields) + " },")
        out.append("\t\t},")
    out.append("\t},")
    out.append("}")
    out.append("")

    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out))
    print(f"{len(props)} props, {sum(len(p[0]) for p in props.values())} parts, {len(rings)} rings -> {target}")


if __name__ == "__main__":
    main()
