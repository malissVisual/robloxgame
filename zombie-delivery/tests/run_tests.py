#!/usr/bin/env python3
"""
Runs the logic tests of the pure shared modules (Config, Economy, Map, Roads, Icons, Levels, TrafficLanes, SoundSheet, Missions, Challenges) in the
standalone Luau CLI: every tests/*_test.luau file, each must print "ALL CHECKS PASSED".

    python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
"""
import glob, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(os.path.dirname(HERE), "src", "shared")
PURE = ("Config", "Economy", "Map", "Roads", "Icons", "Levels", "TrafficLanes", "SoundSheet", "Missions", "Challenges")
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
# 3.3: the car bodies (server/Vehicles.luau STYLES, not loadable outside Roblox) read as text: every Config.Cars style
# has a body; every dealer car's body takes cargo (at least 2 slots) and has a back that opens (the 3.2 loading).
# 3.4: every car's capacity (Config.Cars capacity) is exactly its body's cargo slots (the slot list of cargo(...)).
def slot_count(body):
    start = body.find("cargo = cargo(")
    if start < 0:
        return 0
    open_at = body.index("{", start)
    depth, end = 0, open_at
    for end in range(open_at, len(body)):
        if body[end] == "{":
            depth += 1
        elif body[end] == "}":
            depth -= 1
            if depth == 0:
                break
    return len(re.findall(r"Vector3\.new", body[open_at:end]))

def styles_check():
    root = os.path.dirname(HERE)
    config = open(os.path.join(root, "src", "shared", "Config.luau"), encoding="utf-8").read()
    vehicles = open(os.path.join(root, "src", "server", "Vehicles.luau"), encoding="utf-8").read()
    table = vehicles[vehicles.index("local STYLES"):vehicles.index("local CHASSIS_HEIGHT")]
    blocks = {}
    for match in re.finditer(r"^\t(\w+) = \{\n(.*?)^\t\},?$", table, re.S | re.M):
        blocks[match.group(1)] = match.group(2)
    cars = config[config.index("Config.Cars = {"):config.index("} :: { CarDef }")]
    bad = []
    for entry in re.findall(r"^\t\{\n(.*?)^\t\},?$", cars, re.S | re.M):
        car_id = re.search(r'\bid = "(\w+)"', entry).group(1)
        style = re.search(r'\bstyle = "(\w+)"', entry).group(1)
        body = blocks.get(style)
        if body is None:
            bad.append(f"{car_id}: no style {style}")
            continue
        count = slot_count(body)
        capacity = re.search(r"\bcapacity = (\d+)", entry)
        if not capacity:
            bad.append(f"{car_id}: no capacity")
        elif int(capacity.group(1)) != count:
            bad.append(f"{car_id}: capacity {capacity.group(1)} but {count} cargo slots in style {style}")
        if "company = true" in entry:
            continue
        if count < 2:
            bad.append(f"{car_id}: {count} cargo slots")
        if "back = " not in body:
            bad.append(f"{car_id}: no back")
    print("== styles: " + (f"every car has a body, every dealer car cargo slots and a back, every capacity its slots ({len(blocks)} styles)" if not bad else "; ".join(bad)))
    return not bad

if not styles_check():
    ok = False

# Every module must compile the way Roblox compiles it: the Luau compiler (luau-compile, next to the luau binary)
# catches what the type checker does not, e.g. more than 200 locals in one function ("Out of local registers").
# -O0 -g2 like Roblox Studio: without optimization constants take registers too, so this is the strict check.
compiler = os.path.join(os.path.dirname(os.path.abspath(luau)), "luau-compile") if os.path.dirname(luau) else (shutil.which("luau-compile") or "")
if compiler and os.path.exists(compiler):
    src = os.path.join(os.path.dirname(HERE), "src")
    bad = 0
    for root, _, files in os.walk(src):
        for name in sorted(files):
            if name.endswith(".luau"):
                path = os.path.join(root, name)
                result = subprocess.run([compiler, "--null", "-O0", "-g2", path], capture_output=True, text=True)  # the strictest: how Studio compiles
                if result.returncode != 0 or "Error" in result.stdout + result.stderr:
                    bad += 1
                    print(f"COMPILE FAIL  {os.path.relpath(path, src)}: {(result.stdout + result.stderr).strip()}")
    print(f"== compile: {'every module compiles' if bad == 0 else f'{bad} module(s) do not compile'}")
    if bad:
        ok = False
else:
    print("== compile: luau-compile not found next to the luau binary, skipped")
print("ALL TEST FILES PASSED" if ok else "SOME TEST FILES FAILED")
sys.exit(0 if ok else 1)
