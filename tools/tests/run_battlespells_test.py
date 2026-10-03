#!/usr/bin/env python3
"""
Runs the logic test of the fight's extra action (server/Services/BattleSpells.luau: reinforcements, the player's
meteor, the element wizards' signature spells) in the standalone Luau CLI with the Roblox stubs (roblox_stubs.luau).

    python3 tools/tests/run_battlespells_test.py [path to the luau binary]
"""
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

def strip(text):
    return text.replace("--!strict", "")

PREFIX = ('local Stubs = require("./stubs")\n'
          'local Color3, Vector3, CFrame, Enum, Instance, Random = Stubs.Color3, Stubs.Vector3, Stubs.CFrame, Stubs.Enum, Stubs.Instance, Stubs.Random\n')

with tempfile.TemporaryDirectory() as tmp:
    shutil.copy(os.path.join(HERE, "roblox_stubs.luau"), os.path.join(tmp, "stubs.luau"))
    shutil.copy(os.path.join(HERE, "battlespells_test.luau"), os.path.join(tmp, "test.luau"))
    for name, target in (("src/shared/Config/Wizards.luau", "Wizards.luau"), ("src/shared/Config/BattleSpells.luau", "Config.luau")):
        text = strip(open(os.path.join(ROOT, name), encoding="utf-8").read())
        open(os.path.join(tmp, target), "w", encoding="utf-8").write(PREFIX + text)
    source = open(os.path.join(ROOT, "src/server/Services/BattleSpells.luau"), encoding="utf-8").read()
    marker = "local UP = Vector3.new(0, 1, 0)"
    head = PREFIX + 'local Wizards = require("./Wizards")\nlocal Config = require("./Config")\n'
    open(os.path.join(tmp, "BattleSpells.luau"), "w", encoding="utf-8").write(strip(head + source[source.index(marker):]))
    result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(0 if "ALL CHECKS PASSED" in result.stdout else 1)
