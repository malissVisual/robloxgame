#!/usr/bin/env python3
"""8.3: the sandbox's map from above for the owner's guide (design/sandbox/GUIDE.md, design/sandbox/map.png).

The real server code builds the world on tools/perf/world-mock.luau (world_count.py's preparation; export.luau):
server/SandboxWorld.luau's map, the four kiosks (server/MoveSites.luau plotBoard), the four warehouses (server/Warehouse.luau;
plot n at warehouse level n, plot 1 with two pieces on its stands; Collection, SandboxPlots, Upgrades and PlayerData are
stand-ins written here) and the TOP MOVERS board (server/SandboxLeaders.luau). The van is the ZDC Sprinter's parts model
(tools/vehicle-preview/export_fleet.py) at every plot's vanSpot. render.mjs draws it with three.js in headless Chromium
(render.html) and compose.js lays out the sheet: the overview, plot 1 up close (its warehouse's roof off) and the labels
(their spots from shared/SandboxMap.luau and SandboxLeadersRules.spot). The parts look only: no Blender imports.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/sandbox-map/render.py <luau> <three.module.min.js> <out.png> [--fonts DIR] [--label TEXT]

three.module.min.js: three.js's build (e.g. three@0.160 from npm: package/build/three.module.min.js); --fonts: a folder with
montserrat-500/700/800.woff2 (else the browser's sans); --label: the version in the footer. Chromium from CHROMIUM
(default /opt/pw-browsers/chromium).
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parent.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(GAME / "tools" / "perf"))
sys.path.insert(0, str(GAME / "tools" / "vehicle-preview"))
import world_count  # noqa: E402
import export_fleet  # noqa: E402

COLLECTION = """-- (tools/sandbox-map/render.py: server/Collection.luau's stand-in)
local C = {}
local stock, stands = {}, {}
function C.__own(player, entries, count) stock[player] = entries; stands[player] = count end
function C.stock(player) return stock[player] or {} end
function C.stands(player) return stands[player] or 2 end
function C.incomePerMinute() return 0 end
function C.boost() return 1 end
function C.marketIncome() return 1 end
function C.onChanged() end
function C.openPicker() end
function C.undisplay() return true end
function C.sell() return 0 end
return C
"""
PLOTS = """-- (tools/sandbox-map/render.py: server/SandboxPlots.luau's stand-in: every plot owned)
local P = {}
local owners = {}
function P.__own(id, player) owners[id] = player end
function P.owner(id) return owners[id] end
function P.of(player) for id, p in owners do if p == player then return id end end return nil end
function P.onChanged() end
return P
"""
UPGRADES = """-- (tools/sandbox-map/render.py: server/Upgrades.luau's stand-in: each owner's warehouse level)
local U = {}
local levels = {}
function U.__own(player, level) levels[player] = level end
function U.open() end
function U.onChanged() end
function U.warehouseLevel(player) return levels[player] or 1 end
return U
"""
PLAYERDATA = """-- (tools/sandbox-map/render.py: server/PlayerData.luau's stand-in for SandboxLeaders: no saves)
local D = {}
D.Changed = { Connect = function() return { Disconnect = function() end } end }
function D.get() return nil end
return D
"""


def export_world(luau: str, out: Path):
    with tempfile.TemporaryDirectory() as folder:
        world_count.prepare(str(GAME), folder, people=True)
        shutil.copy(HERE / "export.luau", Path(folder) / "main.luau")
        for name, text in (("Collection", COLLECTION), ("SandboxPlots", PLOTS), ("Upgrades", UPGRADES), ("PlayerData", PLAYERDATA)):
            (Path(folder) / "server" / f"{name}.luau").write_text(text, encoding="utf-8")
        result = subprocess.run([luau, "main.luau"], cwd=folder, capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        raise SystemExit(result.stdout[-4000:] + result.stderr[-4000:] + "\nsandbox-map: the export failed")
    parts, facts = [], None
    for line in result.stdout.splitlines():
        if line.startswith("PART "):
            parts.append(json.loads(line[5:]))
        elif line.startswith("FACTS "):
            facts = json.loads(line[6:])
    if not parts or facts is None:
        raise SystemExit(result.stdout[-4000:] + "\nsandbox-map: no parts or no facts")
    (out / "world.json").write_text(json.dumps(parts))
    (out / "facts.json").write_text(json.dumps(facts))
    return len(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("luau")
    parser.add_argument("three", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fonts", type=Path, help="a folder with montserrat-500/700/800.woff2")
    parser.add_argument("--label", default="", help="the version in the footer")
    args = parser.parse_args()
    luau = str(Path(args.luau).resolve())
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        count = export_world(luau, tmp)
        export_fleet.export(luau, tmp / "fleet")
        site = tmp / "site"
        site.mkdir()
        for name in ("render.html", "compose.js"):
            shutil.copy(HERE / name, site / name)
        shutil.copy(args.three.resolve(), site / "three.module.min.js")
        if args.fonts:
            for font in args.fonts.resolve().glob("montserrat-*.woff2"):
                shutil.copy(font, site / font.name)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["node", str(HERE / "render.mjs"), str(tmp / "world.json"), str(tmp / "facts.json"),
                        str(tmp / "fleet" / "fleet.json"), str(args.output.resolve()), str(site), args.label], check=True)
    print(f"sandbox-map: {count} parts of the world")


if __name__ == "__main__":
    main()
