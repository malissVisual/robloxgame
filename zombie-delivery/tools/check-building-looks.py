#!/usr/bin/env python3
"""Validate present building blueprints with Luau, without Roblox or a game server.

Checks structural budgets, finite sizes/colors, footprint limits, entry/cargo
clearance, sign clearance and the renderer's non-colliding decoration contract.
"""
from pathlib import Path
import argparse
import json
import math
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "src/server/BuildingLooks"
# The first six (Codex, 4.0.4) have their entries here; later blueprints declare theirs (Blueprint.entries).
KNOWN = {"depot", "dealer", "guns", "mechanic", "supplies", "warehouse"}

def projected_size(size, rotation):
    x,y,z=map(math.radians,rotation)
    sx,cx,sy,cy,sz,cz=math.sin(x),math.cos(x),math.sin(y),math.cos(y),math.sin(z),math.cos(z)
    rows=((cy*cz,-cy*sz,sy),(cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy),(sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy))
    return tuple(sum(abs(axis[i])*size[i] for i in range(3)) for axis in rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("luau")
    parser.add_argument("--blueprints", type=Path, default=DATA, help="Validate staged blueprints before integrating World")
    args = parser.parse_args()
    assert all(abs(a-b)<1e-8 for a,b in zip(projected_size([4,.1,.1],[0,0,90]),[.1,4,.1]))
    blueprints = [p for p in sorted(args.blueprints.glob("*.luau")) if p.name != "Kit.luau"]
    renderer = (DATA / "Kit.luau").read_text()
    assert "context.deco(context.part(" in renderer and "item.CanTouch = false" in renderer
    assert "Heartbeat" not in re.sub(r"--[^\n]*", "", renderer.split("function Kit.build", 1)[1])
    assert "CanCollide = true" not in renderer
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for path in [DATA / "Kit.luau"] + blueprints:
            source = path.read_text().replace("require(script.Parent.Kit)", 'require("./Kit")')
            (tmp / path.name).write_text(source)
        mock_prefix = 'local Mock = require("./roblox-mock")\nlocal Instance, Vector3, Color3, CFrame, UDim2, Enum = Mock.Instance, Mock.Vector3, Mock.Color3, Mock.CFrame, Mock.UDim2, Mock.Enum\n'
        (tmp / "Kit.luau").write_text(mock_prefix + renderer)
        for name in ("roblox-mock", "render-check"):
            (tmp / (name + ".luau")).write_text((ROOT / "tools/fixtures" / (name + ".luau")).read_text())
        for name in ("Map", "Config"):
            source = (ROOT / "src/shared" / (name + ".luau")).read_text()
            source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
            (tmp / (name + ".luau")).write_text(source)
        names = ", ".join('require("./' + p.stem + '")' for p in blueprints)
        (tmp / "blueprint-list.luau").write_text("return {" + names + "}\n")
        (tmp / "run.luau").write_text('''local function encode(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) == "table" then
        local out = {}
        if #value > 0 then
            for _, v in value do table.insert(out, encode(v)) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, v in value do table.insert(out, encode(k) .. ":" .. encode(v)) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    error("Unsupported blueprint value")
end
local Map = require("./Map")
local warehouseZ = 0
for _, place in Map.Places do
    if place.id == "warehouse" then warehouseZ = place.z end
end
local openX = warehouseZ - Map.CargoSpots.warehouse.pile.z
local doors = { openX - 48, openX - 24, openX }
for _, blueprint in {''' + names + '''} do
    if type(blueprint) == "function" then
        blueprint = blueprint(doors)
        blueprint.doorCenters = doors
    end
    print(encode(blueprint))
end
''')
        result = subprocess.run([str(Path(args.luau).resolve()), "run.luau"], cwd=tmp, text=True, capture_output=True, check=True)
        rendered = subprocess.run([str(Path(args.luau).resolve()), "render-check.luau"], cwd=tmp, text=True, capture_output=True, check=True)
        print(rendered.stdout, end="")
    counts = {}
    for line in result.stdout.splitlines():
        data = json.loads(line)
        id_ = data["id"]
        assert id_ not in counts, (id_, "duplicate id")
        details = data["details"]
        assert 1 <= len(details) <= 80, (id_, "part budget")
        names = set()
        beams = 0
        for d in details:
            assert d["name"] not in names, (id_, d["name"])
            names.add(d["name"])
            for key in ["position", "size", "color"]:
                assert len(d[key]) == 3 and all(isinstance(n, (int, float)) and math.isfinite(n) for n in d[key]), (id_, key)
            assert all(.04 <= n <= 2048 for n in d["size"]), (id_, d["name"], "size")
            assert all(0 <= n <= 255 for n in d["color"])
            assert 0 <= d.get("transparency", 0) <= 1
            x, y, z = d["position"]
            rotation=d.get("rotation",[0,0,0])
            assert len(rotation)==3 and all(math.isfinite(n) for n in rotation)
            w, h, depth = projected_size(d["size"],rotation)
            # Details remain on/within the original building and its close overhang.
            assert abs(x) + w / 2 <= data["width"] / 2 + 1.5, (id_, d["name"], "side spill")
            assert abs(z) + depth / 2 <= data["depth"] / 2 + 4, (id_, d["name"], "front/back spill")
            assert y - h / 2 >= -.1, (id_, d["name"], "below ground")
            assert y + h / 2 <= data["height"] + 6, (id_, d["name"], "roof budget")
            # Anything across a front opening is a canopy above a tall van, or a thin ground marking.
            in_front = z - depth / 2 <= -data["depth"] / 2 + 1
            widths = {"depot": 72, "dealer": 16, "guns": 12, "mechanic": 34, "supplies": 12}
            door = widths.get(id_)
            crossing = door is not None and abs(x) - w / 2 < door / 2
            if in_front and crossing:
                clear = {"depot": 14, "dealer": 12, "guns": 10, "mechanic": 15, "supplies": 10}[id_]
                assert y - h / 2 >= clear or y + h / 2 <= .4, (id_, d["name"], "entry clearance")
            # A blueprint's own openings (Blueprint.entries: { center x, width, clear height }): kept clear like the doors.
            if id_ not in KNOWN and in_front:
                for center, width, clear in data.get("entries", []):
                    if abs(x - center) < (w + width) / 2:
                        assert y - h / 2 >= clear or y + h / 2 <= .4, (id_, d["name"], "entry clearance")
            if id_ == "warehouse" and in_front:
                entries = [(c, 16, 14) for c in data["doorCenters"]] + [(40, 4, 7)]
                for center, width, clear in entries:
                    if abs(x - center) < (w + width) / 2:
                        assert y - h / 2 >= clear or y + h / 2 <= .4, (id_, d["name"], "dock/office clearance")
                if abs(x + 12) < (w + 40) / 2:
                    assert y + h / 2 <= 16.6 or y - h / 2 >= 20.6, (id_, d["name"], "warehouse sign clearance")
            # Existing asset signs grow upward from the old board; don't cover their front plane.
            if in_front and abs(x) - w / 2 < 30:
                assert y + h / 2 <= data["height"] + .8, (id_, d["name"], "name board clearance")
            if "beam" in d:
                assert d.get("night") is True and 0 < d["beam"] <= 40
                beams += 1
            assert d.get("material", "Metal") in {"Metal", "Concrete", "Brick", "Glass", "SmoothPlastic", "Wood", "WoodPlanks", "Slate", "CorrodedMetal", "Rubber"}
        assert beams <= 2, (id_, "light budget")
        counts[id_] = len(details)
    print("Building geometry PASS:", counts or "renderer foundation (no building blueprint yet)")
    print("Footprints, entry/name-board clearance, part/light budgets, nonblocking renderer and finite data checked")


if __name__ == "__main__":
    main()
