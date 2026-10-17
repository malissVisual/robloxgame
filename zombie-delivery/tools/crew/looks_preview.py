#!/usr/bin/env python3
"""10.1 the helpers' crew: a preview picture for the owner of how each helper looks in the world (Danny and the four
new ones: Bruno, Zip, Gus, Lucy), side by side with their name tags ("Bruno" / "Strong · ZDC Moving"), each one's
icon, role, health, pace and what he does under him.

The looks are the real shared/CrewRules.luau look (the mover's look from shared/NpcLooks.luau, with the kind's own
shirt, trousers, hat, apron or vest, sleeves, boots and shoes from Config.Crew.Kinds; the skin and the hair from the
name), read by a small Luau script; the bodies are drawn as Roblox's classic R15 block body, dressed the way
server/Npcs.luau's dress() puts the clothes on (the same sizes and places), with three.js in headless Chromium
(looks.html, looks.mjs). Not Roblox's renderer: the fonts are stand-ins (Montserrat), the body a block stand-in.

    NODE_PATH=/opt/node22/lib/node_modules python3 zombie-delivery/tools/crew/looks_preview.py <luau> <three.module.min.js> \\
        <out.png> --fonts DIR

three.module.min.js: three.js's build (three@0.160 from npm: package/build/three.module.min.js); --fonts: a folder with
montserrat-500.woff2 and montserrat-700.woff2. Playwright and Chromium as for the other previews (CHROMIUM overrides
/opt/pw-browsers/chromium).
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

FACTS = """local Config = require("./Config")
local CrewRules = require("./CrewRules")
local function encode(value)
	local t = type(value)
	if t == "table" then
		if #value > 0 then
			local parts = {}
			for _, v in value do
				table.insert(parts, encode(v))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, v in value do
			table.insert(parts, encode(tostring(k)) .. ":" .. encode(v))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return '"' .. string.gsub(value, '[%c"\\\\]', function(ch)
			return string.format("\\\\u%04x", string.byte(ch))
		end) .. '"'
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	end
	return "null"
end
local out = {}
for _, id in Config.Crew.Order do
	local def = CrewRules.def(id)
	table.insert(out, { id = id, look = CrewRules.look(id), icon = def.Icon, role = def.Role, ability = def.Ability,
		health = def.Health, speed = def.Speed, carry = CrewRules.carryText(id) })
end
print(encode(out))
"""

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("luau")
parser.add_argument("three", type=Path)
parser.add_argument("out", type=Path)
parser.add_argument("--fonts", type=Path, required=True, help="a folder with montserrat-500.woff2 and montserrat-700.woff2")
args = parser.parse_args()

with tempfile.TemporaryDirectory() as folder:
    tmp = Path(folder)
    for source in (ROOT / "src/shared").glob("*.luau"):
        text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source.read_text())
        (tmp / source.name).write_text(text)
    (tmp / "facts.luau").write_text(FACTS)
    facts = subprocess.run([str(Path(args.luau).resolve()), "facts.luau"], cwd=tmp, capture_output=True, text=True)
    if facts.returncode:
        raise SystemExit("facts failed:\n" + facts.stdout + facts.stderr)
    crew = json.loads(facts.stdout.strip().splitlines()[-1])
    data = {
        "title": "ZOMBIE DELIVERY 10.1 · THE HELPERS' CREW",
        "subtitle": "Danny is free and everybody's from the start; rescue the others in runs (tied to a chair in some houses). "
                    "One comes into each run: your pick in the CREW window.",
        "crew": crew,
    }
    site = tmp / "site"
    site.mkdir()
    shutil.copy(HERE / "looks.html", site / "looks.html")
    shutil.copy(args.three.resolve(), site / "three.module.min.js")
    for weight in (500, 700):
        shutil.copy(args.fonts / f"montserrat-{weight}.woff2", site / f"montserrat-{weight}.woff2")
    (tmp / "data.json").write_text(json.dumps(data))
    subprocess.run(["node", str(HERE / "looks.mjs"), str(site), str(tmp / "data.json"), str(args.out.resolve())], check=True)
