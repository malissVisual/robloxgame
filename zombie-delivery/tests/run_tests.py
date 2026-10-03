#!/usr/bin/env python3
"""
Runs the logic test of the shared modules (Config, Economy, Map) in the standalone Luau CLI.

    python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
"""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(os.path.dirname(HERE), "src", "shared")
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

with tempfile.TemporaryDirectory() as tmp:
    for name in ("Config", "Economy", "Map"):
        source = open(os.path.join(SHARED, name + ".luau"), encoding="utf-8").read()
        source = source.replace("require(script.Parent.Config)", 'require("./Config")')
        open(os.path.join(tmp, name + ".luau"), "w", encoding="utf-8").write(source)
    shutil.copy(os.path.join(HERE, "logic_test.luau"), os.path.join(tmp, "test.luau"))
    result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    sys.exit(0 if "ALL CHECKS PASSED" in result.stdout else 1)
