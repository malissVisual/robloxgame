#!/usr/bin/env python3
"""9.x loot: a preview picture for the owner of the loot's look in a house: one piece of each rarity (and a Sofa a
Nightmare house rolled Epic) standing in a room, each wearing what the game draws on it: its Highlight in its tier's
colour (the edge, the soft fill; a Common none) and its stars' bubble (★ × its stars, near: its tier and value), the
loot toast and the tiers' legend under it.

The pieces are the real FurnitureLooks builders' parts (tools/furniture/render.py's export on the recorder), their
rarity, stars, value and words the real shared/LootRules.luau's and Config.Loot's / Config.Collection's (a small Luau
script in the same folder), drawn with three.js in headless Chromium (preview.html, preview.mjs). Not Roblox's
renderer: Roblox's Highlight and BillboardGui are drawn the way they look, the fonts are stand-ins (Montserrat).

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/loot/preview.py <luau> <three.module.min.js> \\
        <out.png> --fonts DIR

three.module.min.js: three.js's build (three@0.160 from npm: package/build/three.module.min.js); --fonts: a folder with
montserrat-500.woff2 and montserrat-700.woff2. Playwright and Chromium as for the other previews (CHROMIUM overrides
/opt/pw-browsers/chromium).
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools" / "furniture"))
from render import export  # noqa: E402  (every piece's parts, built by the real builders on the recorder)

# (id, the rarity it comes as, where it stands along the room, its caption); the last: a Nightmare house's roll
# (+X is the picture's left: the camera looks into the room from its front, -Z)
PIECES = (
    ("dining_chair", None, 21.5, "Common: no outline, ★ only"),
    ("sofa", None, 15.0, "Uncommon"),
    ("grandfather_clock", None, 7.6, "Rare"),
    ("arcade_cabinet", None, -0.6, "Epic (a collectible)"),
    ("knight_armour", None, -8.8, "Legendary (a collectible)"),
    ("sofa", "epic", -17.5, "Nightmare: this Sofa came Epic"),
)

FACTS = """local LootRules = require("./LootRules")
local CollectionRules = require("./CollectionRules")
local Config = require("./Config")
local out = {}
for _, raw in { ... } do
	local item, rolled = string.match(raw, "^([%w_]+):?(%w*)$")
	local def = CollectionRules.defOf(item)
	local own = CollectionRules.rarityOf(def)
	local rarity = if rolled ~= "" then rolled else own
	local value = LootRules.valueOf(def.value, own, rarity)
	local c = LootRules.color(rarity)
	table.insert(out, string.format('{"item":"%s","name":"%s","rarity":"%s","stars":%d,"value":%d,"starsText":"%s","info":"%s","head":"+ %s","money":"%s","outlined":%s,"color":[%d,%d,%d]}',
		item, def.name, rarity, LootRules.rank(rarity), value, LootRules.stars(rarity), LootRules.info(rarity, value), LootRules.tierName(rarity),
		LootRules.money(value), tostring(LootRules.outlined(rarity)), c[1], c[2], c[3]))
end
local tiers = {}
for _, id in Config.Collection.Order do
	local c = LootRules.color(id)
	table.insert(tiers, string.format('{"id":"%s","name":"%s","stars":"%s","outlined":%s,"color":[%d,%d,%d]}', id, LootRules.tierName(id), LootRules.stars(id), tostring(LootRules.outlined(id)), c[1], c[2], c[3]))
end
local L = Config.Loot
print(string.format('{"pieces":[%s],"tiers":[%s],"fill":%s,"edge":%s,"stars":{"text":%d,"detail":%d,"tall":%d,"pad":%d,"lift":%s}}',
	table.concat(out, ","), table.concat(tiers, ","), tostring(L.Outline.Fill), tostring(L.Outline.Edge), L.Stars.Text, L.Stars.Detail, L.Stars.Tall, L.Stars.Pad, tostring(L.Stars.Lift)))
"""

NOTES = {
    "common": "most of a house: no outline (the budget is for colour that means something)",
    "uncommon": "furniture worth $100 and more; the least a collectible comes as",
    "rare": "the piano, a gold record; Hard, Insane, Nightmare lift pieces here",
    "epic": "a collector's piece; Nightmare: at least one in every house",
    "legendary": "a find: about one house in 25 on Normal, one in three on Nightmare",
}

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("luau")
parser.add_argument("three", type=Path)
parser.add_argument("out", type=Path)
parser.add_argument("--fonts", type=Path, required=True, help="a folder with montserrat-500.woff2 and montserrat-700.woff2")
args = parser.parse_args()

with tempfile.TemporaryDirectory() as folder:
    tmp = Path(folder)
    scenes = export(args.luau, tmp, 1)
    items = {}
    for line in scenes.read_text().splitlines():
        scene = json.loads(line)
        if scene["kind"] == "item":
            items[scene["info"]["id"]] = scene
    (tmp / "facts.luau").write_text(FACTS)
    keys = [f"{item}:{rolled}" if rolled else item for item, rolled, _, _ in PIECES]
    facts = subprocess.run([str(Path(args.luau).resolve()), "facts.luau", "-a", *keys], cwd=tmp, capture_output=True, text=True)
    if facts.returncode:
        raise SystemExit("facts failed:\n" + facts.stdout + facts.stderr)
    known = json.loads(facts.stdout.strip().splitlines()[-1])
    pieces = []
    for (item, rolled, x, caption), fact in zip(PIECES, known["pieces"]):
        scene = items[item]
        pieces.append({**fact, "parts": scene["parts"], "size": scene["info"]["size"], "at": [x, 0, 0], "near": True, "caption": caption})
    toast = [p for p in pieces if p["item"] in ("grandfather_clock", "knight_armour")] + [pieces[-1]]
    data = {
        "title": "ZOMBIE DELIVERY 9.x · LOOT: EVERY PIECE'S RARITY AT A GLANCE",
        "subtitle": "its Highlight in its tier's colour (edge + soft fill, never through walls) and its stars; near: its tier and value. "
                    "The difficulty rolls on it: Easy a little worse, Normal as today, Hard / Insane / Nightmare better.",
        "pieces": pieces,
        "fill": known["fill"],
        "edge": known["edge"],
        "stars": known["stars"],
        "tiers": [{**t, "note": NOTES.get(t["id"], "")} for t in known["tiers"]],
        "toasts": [{"head": p["head"], "name": p["name"], "stars": p["starsText"], "value": p["money"], "color": p["color"]} for p in toast],
    }
    site = tmp / "site"
    site.mkdir()
    shutil.copy(HERE / "preview.html", site / "preview.html")
    shutil.copy(args.three.resolve(), site / "three.module.min.js")
    for weight in (500, 700):
        shutil.copy(args.fonts / f"montserrat-{weight}.woff2", site / f"montserrat-{weight}.woff2")
    (tmp / "data.json").write_text(json.dumps(data))
    subprocess.run(["node", str(HERE / "preview.mjs"), str(site), str(tmp / "data.json"), str(args.out.resolve())], check=True)
