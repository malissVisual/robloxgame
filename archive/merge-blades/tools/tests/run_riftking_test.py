#!/usr/bin/env python3
"""
Runs the logic test of the Rift King fight (server/Services/RiftKing.luau) in the standalone Luau CLI, with small
Roblox stubs (roblox_stubs.luau) instead of the engine: attack timings, locked warnings, dodge windows, one hit per
impact, the jump over the shockwave, safe paths between meteors, enrage, stagger and the cleanup.

    python3 tools/tests/run_riftking_test.py [path to the luau binary]

It copies RiftKing.luau into a temp folder with its Roblox requires swapped for the stubs and runs riftking_test.luau.
Not a Studio playtest: the model, animations and rendering are not covered here.
"""
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

with tempfile.TemporaryDirectory() as tmp:
    source = open(os.path.join(ROOT, "src/server/Services/RiftKing.luau"), encoding="utf-8").read()
    marker = "local UP = Vector3.new(0, 1, 0)"
    head = '''local Stubs = require("./stubs")
local Vector3, CFrame, Instance, Enum, Color3, ColorSequence, NumberSequence, TweenInfo = Stubs.Vector3, Stubs.CFrame, Stubs.Instance, Stubs.Enum, Stubs.Color3, Stubs.ColorSequence, Stubs.NumberSequence, Stubs.TweenInfo
local Players, TweenService, Debris = Stubs.Players, Stubs.TweenService, Stubs.Debris
local Config = require("./Config_RiftKing")
local Net, Rig, Plots = Stubs.Net, Stubs.Rig, Stubs.Plots
'''
    copy = (head + source[source.index(marker):]).replace("--!strict", "")
    open(os.path.join(tmp, "RiftKing_copy.luau"), "w", encoding="utf-8").write(copy)
    shutil.copy(os.path.join(ROOT, "src/shared/Config/RiftKing.luau"), os.path.join(tmp, "Config_RiftKing.luau"))
    shutil.copy(os.path.join(HERE, "roblox_stubs.luau"), os.path.join(tmp, "stubs.luau"))
    shutil.copy(os.path.join(HERE, "riftking_test.luau"), os.path.join(tmp, "test.luau"))
    result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(0 if "ALL CHECKS PASSED" in result.stdout else 1)
