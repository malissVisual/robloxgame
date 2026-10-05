#!/usr/bin/env python3
"""
Runs the logic test of the Mage's battle AI (server/Services/MageBrain.luau) in the standalone Luau CLI with the
Roblox stubs (roblox_stubs.luau): spell unlocks per level, target selection, attacks, no walking while anything is
in range, strong spells and mana, healing an ally, arena bounds, the reactions (avenger, overcharge, hop, counter-spell,
guardian, repel, pop rate limit) and cleanup.

    python3 tools/tests/run_magebrain_test.py [path to the luau binary]
"""
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

def strip(text):
    return text.replace("--!strict", "")

with tempfile.TemporaryDirectory() as tmp:
    shutil.copy(os.path.join(HERE, "roblox_stubs.luau"), os.path.join(tmp, "stubs.luau"))
    shutil.copy(os.path.join(HERE, "magebrain_test.luau"), os.path.join(tmp, "test.luau"))
    for name in ("MageConfig", "MageSpells", "MageTree"):
        text = strip(open(os.path.join(ROOT, "src/shared/Config/%s.luau" % name), encoding="utf-8").read())
        open(os.path.join(tmp, name + ".luau"), "w", encoding="utf-8").write('local Stubs = require("./stubs")\nlocal Color3 = Stubs.Color3\n' + text)
    source = open(os.path.join(ROOT, "src/server/Services/MageBrain.luau"), encoding="utf-8").read()
    marker = "local UP = Vector3.new(0, 1, 0)"
    head = '''local Stubs = require("./stubs")
local Vector3, CFrame, Instance, Enum, Color3, TweenInfo = Stubs.Vector3, Stubs.CFrame, Stubs.Instance, Stubs.Enum, Stubs.Color3, Stubs.TweenInfo
local TweenService, Debris, workspace, task = Stubs.TweenService, Stubs.Debris, Stubs.workspace, Stubs.task
local Config = require("./MageConfig")
local Spells = require("./MageSpells")
local Tree = require("./MageTree")
local Rig = { setMoving = function() end, attack = function() end, cast = function() end, raise = function() end }
'''
    open(os.path.join(tmp, "MageBrain_copy.luau"), "w", encoding="utf-8").write(strip(head + source[source.index(marker):]))
    result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(0 if "ALL CHECKS PASSED" in result.stdout else 1)
