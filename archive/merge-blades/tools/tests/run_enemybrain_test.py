#!/usr/bin/env python3
"""
Runs the logic test of the enemy brains (server/Services/EnemyBrain.luau) in the standalone Luau CLI with the Roblox
stubs (roblox_stubs.luau): the brute's telegraphed charge (lane hazards, locked line, impact, dizzy, the Mage's trip),
the archer's single scurry and focus fire, the shaman's mend and its interrupt, the grunt's war cry, the brute's
guard taunt, the boss slam timing / radius, the Chief's summon, the treasure goblin's flight.

    python3 tools/tests/run_enemybrain_test.py [path to the luau binary]
"""
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

def strip(text):
    return text.replace("--!strict", "")

with tempfile.TemporaryDirectory() as tmp:
    shutil.copy(os.path.join(HERE, "roblox_stubs.luau"), os.path.join(tmp, "stubs.luau"))
    shutil.copy(os.path.join(HERE, "enemybrain_test.luau"), os.path.join(tmp, "test.luau"))
    balance = strip(open(os.path.join(ROOT, "src/shared/Config/Balance.luau"), encoding="utf-8").read())
    open(os.path.join(tmp, "Balance.luau"), "w", encoding="utf-8").write(balance)
    config = strip(open(os.path.join(ROOT, "src/shared/Config/EnemyAI.luau"), encoding="utf-8").read())
    config = config.replace('require(script.Parent.Balance)', 'require("./Balance")')
    open(os.path.join(tmp, "EnemyAI.luau"), "w", encoding="utf-8").write('local Stubs = require("./stubs")\nlocal Color3 = Stubs.Color3\n' + config)
    source = open(os.path.join(ROOT, "src/server/Services/EnemyBrain.luau"), encoding="utf-8").read()
    marker = "local UP = Vector3.new(0, 1, 0)"
    head = '''local Stubs = require("./stubs")
local Vector3, CFrame, Instance, Enum, Color3, TweenInfo = Stubs.Vector3, Stubs.CFrame, Stubs.Instance, Stubs.Enum, Stubs.Color3, Stubs.TweenInfo
local TweenService, Debris, task = Stubs.TweenService, Stubs.Debris, Stubs.task
local Config = require("./EnemyAI")
local Rig = { setMoving = function() end, attack = function() end, cast = function() end, raise = function() end, die = function() return false end }
'''
    open(os.path.join(tmp, "EnemyBrain_copy.luau"), "w", encoding="utf-8").write(strip(head + source[source.index(marker):]))
    result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(0 if "ALL CHECKS PASSED" in result.stdout else 1)
