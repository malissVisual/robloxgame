#!/usr/bin/env python3
"""8.2: count what the 8.x SANDBOX puts in the world, without Roblox (design/performance/REPORT.md, section 9).

Two runs of the real server code on the Luau CLI:
  * tools/perf/sandbox-count.luau on tools/perf/world-mock.luau (world_count.py's preparation, the real server/Npcs):
    server/SandboxWorld.luau's map, the four Moving contracts kiosks (server/MoveSites.luau), the four warehouses
    (server/Warehouse.luau: four owners, every display stand open and full of the heaviest pieces, 8.3: each on a stand
    it fits, WarehouseLayout.fits, so a big piece only on a big stand; Collection, SandboxPlots and Upgrades are
    stand-ins written here), the house's inside while a move runs (server/HouseInterior.luau:
    the largest of 24 plans of the sandbox's house's kind, 8.3 the big plan), Danny (server/Npcs.luau on the stand-in's
    classic R15) and 8.3's showroom visitors (server/Visitors.luau's bodies: Config.Visitors.Cap of them, every kind's
    look, each with the box of a sale);
  * tools/perf/van-count.luau on tools/vehicle-preview/roblox-mock.luau (export_fleet.py's preparation): the sandbox's
    van (Config.Sandbox.Van, the ZDC Sprinter's parts model) at every stage, by day (its night lights out).
Each piece's row (tools/perf/census.luau): parts, MeshParts, visible / see-through / invisible parts, shadow casters
(and the small ones under RenderBudget's size rule), lights (and those with Shadows on), SurfaceGuis and BillboardGuis
(and those drawn at any distance), ParticleEmitters, Beams, fire / smoke / sparkles, decals, ProximityPrompts;
the client's own 3D (client/SandboxGuide.luau's path and marker) read from its source. Then the worst case: 4 players,
every warehouse a Logistics Center (8.3: level 5, the biggest, More stands at its top) with its 32 stands full, 4 vans, a
move running with the inside and Danny, the server's cap of visitors. The players' own avatars, the
greeters on the porch and the owner's Blender imports (the Sprinter, the furniture, the chalet) are not in it. 8.3 the
big move: its inside is counted for every player at once too (4 moves running: a worst case past the one move's).
8.9 Jinočany: the map is the village's now (server/VillageWorld.luau: world/Village, world/Motorway, world/Far); then the
map with 8.8's Auction House (built once Config.Auction.On) against SandboxScenery.Budget: over it, the run fails.

    python3 tools/perf/sandbox_count.py <path to the luau binary> [zombie-delivery dir]

(Another checkout's zombie-delivery dir counts that one's src: the before of a change.)
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "vehicle-preview"))
import world_count  # noqa: E402
import export_fleet  # noqa: E402

PLAYERS = 4  # the sandbox's plots (Config.Sandbox.MaxPlayers): one van each

COLLECTION = """-- (tools/perf/sandbox_count.py: server/Collection.luau's stand-in: the owners' stock, set by the counter)
local C = {}
local stock, stands = {}, {}
function C.__own(player, entries, count)
	stock[player] = entries
	stands[player] = count
end
function C.stock(player) return stock[player] or {} end
function C.stands(player) return stands[player] or 32 end
function C.incomePerMinute() return 0 end
function C.boost() return 1 end
function C.marketIncome() return 1 end -- (8.3: the market's hot kinds, server/Warehouse.luau's tags)
function C.onChanged() end
function C.openPicker() end
function C.undisplay() return true end
function C.sell() return 0 end
return C
"""
PLOTS = """-- (tools/perf/sandbox_count.py: server/SandboxPlots.luau's stand-in: every plot owned)
local P = {}
local owners = {}
function P.__own(id, player) owners[id] = player end
function P.owner(id) return owners[id] end
function P.onChanged() end
return P
"""
UPGRADES = ("local U = {}\nfunction U.open() end\nfunction U.onChanged() end\n"
            "function U.levels() return { warehouse = 4, stands = 4 } end -- (8.3: the worst case, the Logistics Center, More stands at its top)\n"
            "return U\n")

COLUMNS = [
    ("parts", "parts"), ("meshParts", "MeshParts"), ("visible", "visible"), ("seeThrough", "see-through"),
    ("hidden", "invisible"), ("shadows", "cast shadow"), ("smallShadows", "small casters"), ("lights", "lights"), ("lightsOn", "lights on"),
    ("lightsShadowed", "lights w/ shadows"), ("surfaceGuis", "SurfaceGuis"), ("surfaceGuisFar", "SurfaceGuis any distance"),
    ("billboards", "BillboardGuis"), ("billboardsFar", "BillboardGuis any distance"), ("particles", "ParticleEmitters"),
    ("beams", "Beams"), ("effects", "fire/smoke"), ("decals", "decals"), ("prompts", "prompts"),
]


def run(luau, cwd):
    result = subprocess.run([luau, "main.luau"], cwd=cwd, capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(f"sandbox_count: the run in {cwd} failed")
    return result.stdout


def world_rows(luau, game):
    with tempfile.TemporaryDirectory() as out:
        world_count.prepare(game, out, people=True)
        shutil.copy(os.path.join(HERE, "sandbox-count.luau"), os.path.join(out, "main.luau"))
        shutil.copy(os.path.join(HERE, "census.luau"), os.path.join(out, "census.luau"))
        for name, text in (("Collection", COLLECTION), ("SandboxPlots", PLOTS), ("Upgrades", UPGRADES)):
            open(os.path.join(out, "server", name + ".luau"), "w", encoding="utf-8").write(text)
        has = os.path.exists(os.path.join(game, "src", "shared", "AuctionHouseLayout.luau"))
        open(os.path.join(out, "has-auction.luau"), "w", encoding="utf-8").write(f"return {'true' if has else 'false'}\n")
        return run(luau, out)


def map_budget(rows, game):
    """8.9 Jinočany: the map (SandboxWorld's, the village built) with the Auction House (once Config.Auction.On) against
    SandboxScenery.Budget; False when over it."""
    scenery = open(os.path.join(game, "src", "shared", "SandboxScenery.luau"), encoding="utf-8").read()
    budget = int(re.search(r"^SandboxScenery\.Budget = (\d+)", scenery, re.M).group(1))
    world = sum(row.get("parts", 0) for label, row in rows.items() if label.startswith("world/"))
    auction = rows.get("auction", {}).get("parts", 0)
    total = world + auction
    print()
    print(f"INFO budget\tthe map {world:,} parts, with the Auction House (once Config.Auction.On) {total:,}, "
          f"of SandboxScenery.Budget {budget:,}: {budget - total:,} left" + ("" if total <= budget else " — OVER BUDGET"))
    return total <= budget


def van_rows(luau, game):
    export_fleet.ROOT = Path(game)  # (its modules from this game's src: an older checkout counts as it was)
    with tempfile.TemporaryDirectory() as out:
        export_fleet.prepare_modules(Path(out))
        shutil.copy(os.path.join(HERE, "census.luau"), os.path.join(out, "census.luau"))
        shutil.copy(os.path.join(HERE, "van-count.luau"), os.path.join(out, "main.luau"))
        return run(luau, out)


def guide_row(game):
    """client/SandboxGuide.luau's 3D: MAX_POINTS - 1 Beams (the path) and one BillboardGui (the chevron, any distance)."""
    source = open(os.path.join(game, "src", "client", "SandboxGuide.luau"), encoding="utf-8").read()
    points = int(re.search(r"local MAX_POINTS = (\d+)", source).group(1))
    row = {key: 0 for key, _ in COLUMNS}
    row["beams"] = points - 1
    row["billboards"] = 1
    far = re.search(r"MaxDistance = (\d+)", source[source.index("SandboxGuideMarker"):])
    row["billboardsFar"] = 1 if far is None or int(far.group(1)) >= 10000 else 0
    return row


def parse(text, rows, notes):
    for line in text.splitlines():
        if line.startswith("ROW "):
            label, body = line[4:].split("\t", 1)
            rows[label] = json.loads(body)
        elif line.startswith("INFO ") or line.startswith("MODES ") or line.startswith("DETAIL "):
            notes.append(line)


def add(total, row, times=1):
    for key, _ in COLUMNS:
        total[key] = total.get(key, 0) + row.get(key, 0) * times


def table(entries):
    head = "| piece | " + " | ".join(name for _, name in COLUMNS) + " |"
    lines = [head, "|" + "---|" * (len(COLUMNS) + 1)]
    for label, row in entries:
        lines.append(f"| {label} | " + " | ".join(f"{row.get(key, 0):,}" for key, _ in COLUMNS) + " |")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    luau = os.path.abspath(sys.argv[1])
    game = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(HERE))
    rows, notes = {}, []
    parse(world_rows(luau, game), rows, notes)
    parse(van_rows(luau, game), rows, notes)
    rows["client/SandboxGuide"] = guide_row(game)

    world = {}
    for label, row in rows.items():
        if label.startswith("world/"):
            add(world, row)
    van = rows["van/stage0"]
    entries = [(label, row) for label, row in rows.items() if label.startswith("world/")]
    entries.append(("**the map (SandboxWorld)**", world))
    entries += [
        ("kiosks (4)", rows["kiosks"]),
        ("warehouses (4): the halls, level 5, 32 stands each", rows["warehouses/building"]),
        ("warehouses (4): every stand full (32 pieces on show each)", rows["warehouses/shown"]),
        ("a van (Sprinter, stage 0)", van),
        ("the house's inside (largest plan)", rows["interior"]),
        ("Danny", rows["danny"]),
        ("8.3 visitors (the server's cap, each with a sale's box)", rows["visitors"]),
        ("client: SandboxGuide", rows["client/SandboxGuide"]),
    ]
    worst = {}
    add(worst, world)
    add(worst, rows["kiosks"])
    add(worst, rows["warehouses/building"])
    add(worst, rows["warehouses/shown"])
    add(worst, van, PLAYERS)
    add(worst, rows["interior"])
    add(worst, rows["danny"])
    add(worst, rows["visitors"])
    add(worst, rows["client/SandboxGuide"])
    entries.append((f"**worst case** ({PLAYERS} players, every stand full, {PLAYERS} vans, a move with the inside and Danny, the visitors)", worst))
    # 8.3: every player on a move of their own at once (each a big plan's inside and a Danny)
    every = dict(worst)
    add(every, rows["interior"], PLAYERS - 1)
    add(every, rows["danny"], PLAYERS - 1)
    entries.append((f"**every player on a move** ({PLAYERS} big insides, {PLAYERS} Dannys, the rest as the worst case)", every))
    print(table(entries))
    print()
    for label, row in rows.items():
        if label.startswith("van/") and label != "van/stage0":
            print(f"INFO {label}\t{row['parts']} parts, {row['shadows']} cast shadow, {row['lights']} lights")
    for note in notes:
        print(note)
    if not map_budget(rows, game):
        sys.exit(1)


if __name__ == "__main__":
    main()
