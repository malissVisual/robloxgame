#!/usr/bin/env python3
"""
Runs the logic tests of the pure shared modules (Config, Economy, Map, Roads, Icons) in the standalone Luau CLI: every
tests/*_test.luau file, each must print "ALL CHECKS PASSED".

    python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
"""
import glob, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(os.path.dirname(HERE), "src", "shared")
PURE = ("Config", "Economy", "Map", "Roads", "Icons", "Levels", "TrafficLanes")
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

ok = True
with tempfile.TemporaryDirectory() as tmp:
    for name in PURE:
        source = open(os.path.join(SHARED, name + ".luau"), encoding="utf-8").read()
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
        open(os.path.join(tmp, name + ".luau"), "w", encoding="utf-8").write(source)
    for path in sorted(glob.glob(os.path.join(HERE, "*_test.luau"))):
        shutil.copy(path, os.path.join(tmp, "test.luau"))
        print(f"== {os.path.basename(path)}")
        result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        if "ALL CHECKS PASSED" not in result.stdout:
            ok = False
print("ALL TEST FILES PASSED" if ok else "SOME TEST FILES FAILED")
sys.exit(0 if ok else 1)
