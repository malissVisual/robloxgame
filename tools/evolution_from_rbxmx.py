#!/usr/bin/env python3
"""
evolution_from_rbxmx.py — turns the 30 "*_L##_*.rbxmx" R15 models (one per merge level of a class: the Knight's
Evolution_L##, the Archer's Archer_L##) into Luau data modules the game rebuilds the characters from
(src/shared/SoldierRig.luau, buildEvolution).

Usage:
    python tools/evolution_from_rbxmx.py <models dir> <target dir> [class label]
    python tools/evolution_from_rbxmx.py design/KnightEvolution src/shared/StageModels/KnightEvolution Knight
    python tools/evolution_from_rbxmx.py design/ArcherEvolution/modely src/shared/StageModels/ArcherEvolution Archer
The level names come from prehled-levelu.csv in the models dir or the one above it.

Every model is a complete R15 rig (16 body parts incl. HumanoidRootPart, 15 Motor6D joints) with its gear as
Parts / WedgeParts welded to a body part. The output keeps, per level: the body parts (size, CFrame, color,
material), the joints (Part0, Part1, C0, C1), every gear part (its body part, its CFrame relative to that body
part, size, color, material, shape, transparency, reflectance) and how high the model reaches over the head.
Every level is its own module (named after its era, e.g. Pravek_L03), plus an index module (init.luau) that loads a level on demand.
"""

import csv
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

BODY = [
    "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
PER_MODULE = 1 # one module per level: a level with 250+ parts is ~50 KB of source, five of them would pass Roblox's script size limit
ERAS = ["Pravek", "Starovek", "Stredovek", "Prumysl", "Moderni", "Budoucnost"]


def num(value: float) -> str:
    value = round(value, 3)
    if value == int(value):
        return str(int(value))
    return ("%.3f" % value).rstrip("0").rstrip(".")


def text(element, path, default=None):
    node = element.find(path)
    return node.text if node is not None else default


def vec3(node):
    return [float(node.find(axis).text) for axis in "XYZ"]


def cframe(node):
    pos = vec3(node)
    rot = [float(node.find(k).text) for k in ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")]
    return pos, rot


def is_identity(rot):
    return all(abs(a - b) < 1e-4 for a, b in zip(rot, (1, 0, 0, 0, 1, 0, 0, 0, 1)))


def cf_literal(pos, rot):
    if is_identity(rot):
        return "P(%s, %s, %s)" % tuple(num(v) for v in pos)
    return "CF(%s)" % ", ".join(num(v) for v in pos + rot)


# ── matrix helpers (row-major 3x3) ──

def mat_mul(a, b):
    return [sum(a[r * 3 + k] * b[k * 3 + c] for k in range(3)) for r in range(3) for c in range(3)]


def mat_t(a):
    return [a[0], a[3], a[6], a[1], a[4], a[7], a[2], a[5], a[8]]


def mat_vec(a, v):
    return [sum(a[r * 3 + k] * v[k] for k in range(3)) for r in range(3)]


def relative(parent, child):
    """child in parent's space: parent^-1 * child."""
    ppos, prot = parent
    cpos, crot = child
    inv = mat_t(prot)
    pos = mat_vec(inv, [c - p for c, p in zip(cpos, ppos)])
    rot = mat_mul(inv, crot)
    return pos, rot


def color_of(props):
    packed = props.find("Color3uint8[@name='Color3uint8']")
    if packed is not None:
        value = int(packed.text)
        return ((value >> 16) & 255, (value >> 8) & 255, value & 255)
    c = props.find("Color3[@name='Color']")
    if c is not None:
        return tuple(int(round(float(c.find(k).text) * 255)) for k in "RGB")
    return (163, 162, 165)


def part_fields(props, cls):
    size = vec3(props.find("Vector3[@name='size']"))
    color = color_of(props)
    material = int(text(props, "token[@name='Material']", "272"))
    transparency = float(text(props, "float[@name='Transparency']", "0"))
    reflectance = float(text(props, "float[@name='Reflectance']", "0"))
    shape = text(props, "token[@name='shape']")
    extra = []
    if cls == "WedgePart":
        extra.append("wedge = true")
    elif shape is not None and shape != "1":
        extra.append("shape = %s" % shape)
    if transparency:
        extra.append("t = %s" % num(transparency))
    if reflectance:
        extra.append("r = %s" % num(reflectance))
    return size, color, material, extra


def read_names(source_dir):
    """prehled-levelu.csv next to the models: level -> (name, description)."""
    names = {}
    path = os.path.join(source_dir, "prehled-levelu.csv")
    if not os.path.exists(path):
        path = os.path.join(os.path.dirname(os.path.abspath(source_dir)), "prehled-levelu.csv")
    if not os.path.exists(path):
        return names
    with open(path, encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            try:
                names[int(row["Level"])] = (row["Název"].strip(), row.get("Nové vybavení", "").strip())
            except (KeyError, ValueError):
                continue
    return names


def convert(path, names):
    root = ET.parse(path).getroot()
    model = root.find("Item")
    by_ref = {}
    for item in model.iter("Item"):
        by_ref[item.get("referent")] = item

    def name_of(item):
        return text(item, "Properties/string[@name='Name']")

    level = 0
    for value in model.findall("Item[@class='IntValue']"):
        if name_of(value) == "Level":
            node = value.find("Properties/int64[@name='Value']")
            if node is None:
                node = value.find("Properties/int[@name='Value']")
            level = int(node.text) if node is not None else 0
    if level <= 0:
        match = re.search(r"_L(\d+)_", os.path.basename(path))
        level = int(match.group(1)) if match else 0
    era, appearance = "", ""
    for value in model.findall("Item[@class='StringValue']"):
        if name_of(value) == "Era":
            era = text(value, "Properties/string[@name='Value']", "") or ""
        elif name_of(value) == "Appearance":
            appearance = text(value, "Properties/string[@name='Value']", "") or ""

    bodies = {}
    joints = []
    for item in model.findall("Item"):
        nm = name_of(item)
        if item.get("class") == "Part" and nm in BODY:
            props = item.find("Properties")
            bodies[nm] = {"cf": cframe(props.find("CoordinateFrame[@name='CFrame']")), "props": props, "item": item}
            for motor in item.findall("Item[@class='Motor6D']"):
                mp = motor.find("Properties")
                p0 = name_of(by_ref[text(mp, "Ref[@name='Part0']")])
                p1 = name_of(by_ref[text(mp, "Ref[@name='Part1']")])
                joints.append((name_of(motor), p0, p1, cframe(mp.find("CoordinateFrame[@name='C0']")), cframe(mp.find("CoordinateFrame[@name='C1']"))))
    missing = [b for b in BODY if b not in bodies]
    if missing:
        raise SystemExit("%s: body parts missing: %s" % (path, missing))

    head_cf = bodies["Head"]["cf"]
    head_top = head_cf[0][1] + vec3(bodies["Head"]["props"].find("Vector3[@name='size']"))[1] / 2
    max_y = head_top
    gear = []
    for folder in model.findall("Item[@class='Folder']"):
        for item in folder.iter("Item"):
            cls = item.get("class")
            if cls not in ("Part", "WedgePart"):
                continue
            props = item.find("Properties")
            cf = cframe(props.find("CoordinateFrame[@name='CFrame']"))
            limb = None
            for weld in item.findall("Item[@class='Weld']") + item.findall("Item[@class='WeldConstraint']"):
                wp = weld.find("Properties")
                for key in ("Part0", "Part1"):
                    ref = text(wp, "Ref[@name='%s']" % key)
                    other = by_ref.get(ref)
                    if other is not None and name_of(other) in bodies and other is not item:
                        limb = name_of(other)
            if limb is None:
                # No weld to a body part: the nearest body part by position.
                limb = min(bodies, key=lambda b: sum((a - c) ** 2 for a, c in zip(bodies[b]["cf"][0], cf[0])))
            rel = relative(bodies[limb]["cf"], cf)
            size, color, material, extra = part_fields(props, cls)
            light = item.find("Item[@class='PointLight']")
            if light is not None:
                lp = light.find("Properties")
                lc = lp.find("Color3[@name='Color']")
                rgb = tuple(int(round(float(lc.find(k).text) * 255)) for k in "RGB") if lc is not None else color
                extra.append("light = { %d, %d, %d, %s, %s }" % (rgb[0], rgb[1], rgb[2], num(float(text(lp, "float[@name='Range']", "8"))), num(float(text(lp, "float[@name='Brightness']", "1")))))
            max_y = max(max_y, cf[0][1] + max(size) / 2)
            gear.append((limb, rel, size, color, material, extra))

    name, desc = names.get(level, ("Level %d" % level, appearance))
    rows = []
    rows.append("\t[%d] = {" % level)
    rows.append('\t\tname = "%s", era = "%s",' % (name.replace('"', ''), era.replace('"', '')))
    rows.append('\t\tdesc = "%s",' % (desc or appearance).replace('"', ''))
    rows.append("\t\ttop = %s, -- the name label this high over the head" % num(max_y - head_cf[0][1] + 0.9))
    rows.append("\t\tbody = {")
    for nm in BODY:
        props = bodies[nm]["props"]
        size, color, material, extra = part_fields(props, "Part")
        pos, rot = bodies[nm]["cf"]
        rows.append('\t\t\t{ "%s", %s, V(%s), C(%d, %d, %d), %d%s },' % (
            nm, cf_literal(pos, rot), ", ".join(num(v) for v in size), color[0], color[1], color[2], material,
            (", { " + ", ".join(extra) + " }") if extra else ""))
    rows.append("\t\t},")
    rows.append("\t\tjoints = {")
    for jn, p0, p1, c0, c1 in joints:
        rows.append('\t\t\t{ "%s", "%s", "%s", %s, %s },' % (jn, p0, p1, cf_literal(*c0), cf_literal(*c1)))
    rows.append("\t\t},")
    rows.append("\t\tgear = {")
    for limb, rel, size, color, material, extra in gear:
        rows.append('\t\t\t{ "%s", %s, V(%s), C(%d, %d, %d), %d%s },' % (
            limb, cf_literal(*rel), ", ".join(num(v) for v in size), color[0], color[1], color[2], material,
            (", { " + ", ".join(extra) + " }") if extra else ""))
    rows.append("\t\t},")
    rows.append("\t},")
    return level, rows, len(gear)


HEADER = """--!strict
-- GENERATED by tools/evolution_from_rbxmx.py from the %s R15 evolution models (levels %d-%d).
-- Do not edit by hand: change the models and run the tool again.
-- Every level is a complete R15 character: its body parts (model space, feet on y = 0, facing -Z), its
-- 15 joints and its gear welded to the body parts (CFrame relative to the body part).
--   P(x, y, z) = a CFrame without rotation · CF(12 numbers) = a full CFrame
--   body / gear entry: { part name or body part, CFrame, size, color, material (Enum.Material value), extra? }
--   extra: { shape = Enum.PartType value, wedge = true, t = transparency, r = reflectance, light = { r, g, b, range, brightness } }

local V = Vector3.new
local C = Color3.fromRGB
local P = CFrame.new
local CF = CFrame.new

return {
"""


def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        sys.exit(1)
    source_dir, target_dir = sys.argv[1], sys.argv[2]
    class_label = sys.argv[3] if len(sys.argv) == 4 else "Knight"
    files = sorted(glob.glob(os.path.join(source_dir, "*_L[0-9][0-9]_*.rbxmx")))
    if not files:
        raise SystemExit("no *_L##_*.rbxmx in " + source_dir)
    os.makedirs(target_dir, exist_ok=True)

    names = read_names(source_dir)
    levels = {}
    total_gear = 0
    for path in files:
        level, rows, gear_count = convert(path, names)
        levels[level] = rows
        total_gear += gear_count

    count = max(levels)
    modules = []
    for start in range(1, count + 1, PER_MODULE):
        end = min(start + PER_MODULE - 1, count)
        era_index = (start - 1) // 5
        era_name = ERAS[era_index] if era_index < len(ERAS) else "Era%d" % (era_index + 1)
        module = "%s_L%02d" % (era_name, start) if start == end else "%s_%02d_%02d" % (era_name, start, end)
        lines = [HEADER % (class_label, start, end)]
        for level in range(start, end + 1):
            if level in levels:
                lines.extend(levels[level])
        lines.append("}")
        lines.append("")
        with open(os.path.join(target_dir, module + ".luau"), "w", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(lines))
        modules.append((module, start, end))

    index = [
        "--!strict",
        "-- GENERATED by tools/evolution_from_rbxmx.py. The %d merge levels of the %s (the R15 evolution," % (count, class_label),
        "-- from prehistory to the year 3000), one module per level; a module is loaded the first time",
        "-- its level is asked for.",
        "",
        "local Evolution = {}",
        "",
        "Evolution.Count = %d" % count,
        "",
        "local MODULES = {",
    ]
    for module, start, end in modules:
        index.append('\t{ first = %d, last = %d, name = "%s" },' % (start, end, module))
    index.extend([
        "}",
        "",
        "local loaded: { [string]: any } = {}",
        "",
        "-- The data of a level (see the module header for the shape), or nil.",
        "function Evolution.level(level: number): any",
        "\tfor _, entry in MODULES do",
        "\t\tif level >= entry.first and level <= entry.last then",
        "\t\t\tlocal data = loaded[entry.name]",
        "\t\t\tif not data then",
        "\t\t\t\tdata = require(script:FindFirstChild(entry.name) :: ModuleScript) :: any",
        "\t\t\t\tloaded[entry.name] = data",
        "\t\t\tend",
        "\t\t\treturn data[level]",
        "\t\tend",
        "\tend",
        "\treturn nil",
        "end",
        "",
        "return Evolution",
        "",
    ])
    with open(os.path.join(target_dir, "init.luau"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(index))

    # Names and eras for the README / the rank names.
    print("%d levels, %d gear parts -> %s (%d modules + init.luau)" % (count, total_gear, target_dir, len(modules)))


if __name__ == "__main__":
    main()
