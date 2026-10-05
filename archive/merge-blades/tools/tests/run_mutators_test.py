#!/usr/bin/env python3
"""
Runs the logic test of the wave twists (shared/Config/Mutators.luau) and the enemy formations
(shared/Config/Formations.luau) in the standalone Luau CLI with the Roblox stubs (roblox_stubs.luau): deterministic
selection, the slot schedule, no repeats within two waves, tag / exclusion / threat rules, every twist used, the coin
cap, the composition rewrites and the formation bounds.

    python3 tools/tests/run_mutators_test.py [path to the luau binary]
"""
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

def strip(text):
    return text.replace("--!strict", "")

with tempfile.TemporaryDirectory() as tmp:
    shutil.copy(os.path.join(HERE, "roblox_stubs.luau"), os.path.join(tmp, "stubs.luau"))
    shutil.copy(os.path.join(HERE, "mutators_test.luau"), os.path.join(tmp, "test.luau"))
    prefix = 'local Stubs = require("./stubs")\nlocal Color3, Vector3, Random = Stubs.Color3, Stubs.Vector3, Stubs.Random\n'
    balance = strip(open(os.path.join(ROOT, "src/shared/Config/Balance.luau"), encoding="utf-8").read())
    open(os.path.join(tmp, "Balance.luau"), "w", encoding="utf-8").write(prefix + balance)
    formations = strip(open(os.path.join(ROOT, "src/shared/Config/Formations.luau"), encoding="utf-8").read())
    open(os.path.join(tmp, "Formations.luau"), "w", encoding="utf-8").write(prefix + formations)
    source = open(os.path.join(ROOT, "src/shared/Config/Mutators.luau"), encoding="utf-8").read()
    marker = "local Mutators = {}"
    head = 'local Stubs = require("./stubs")\nlocal Color3, Random = Stubs.Color3, Stubs.Random\nlocal Balance = require("./Balance")\n'
    open(os.path.join(tmp, "Mutators.luau"), "w", encoding="utf-8").write(strip(head + source[source.index(marker):]))
    result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(0 if "ALL CHECKS PASSED" in result.stdout else 1)
