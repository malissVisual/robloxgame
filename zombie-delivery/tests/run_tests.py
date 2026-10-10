#!/usr/bin/env python3
"""
Runs the logic tests of the pure shared modules (Config, Economy, Map, Roads, Icons, Levels, TrafficLanes, Crossings, SoundSheet, Missions, Challenges, Melee, Boarding, BuddyBrain, Goal, Tasks, 6.14: Regulars, SpecialOrders, 6.15: LiveEvents, 6.17: JobPick ...) in the
standalone Luau CLI: every tests/*_test.luau file, each must print "ALL CHECKS PASSED".

    python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
"""
import glob, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(os.path.dirname(HERE), "src", "shared")
PURE = ("Config", "Economy", "Map", "FootbridgeShape", "Explore", "Roads", "Icons", "Levels", "TrafficLanes", "Crossings", "SoundSheet", "Cast", "NpcLooks", "Missions", "Challenges", "TutorialSteps", "Melee", "Boarding", "Freight", "LocationTags", "BuddyBrain", "Career", "JobRules", "Transport", "VanQuest", "KitFit", "RiderPose", "Bag", "Deliveries", "FuelMath", "Residents", "BusLines", "Shortcuts", "RentalDocks", "ZipLines", "Gestures", "FootEvents", "TowerLooks", "StreetProps", "WeatherPlan", "InteractPose", "Armour", "Throws", "RunCycle", "Holding", "BagSwing", "BagFill", "Goal", "BodyMotion", "AvatarLook", "ScooterRide", "CurbShape", "Tasks", "SoundPlan", "Style", "StyleLooks", "JobQueue", "JobThumbs", "MissionArt", "AnalyticsPlan", "RenderBudget", "Shift", "Regulars", "SpecialOrders", "Readiness", "OutlinePick", "MissionPlan", "LiveEvents", "ShotFeel", "SkyGrade", "Suspension", "DriveFeel", "ZombieStyle", "JobPick", "CardLayout", "ShopPick")
luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"

ok = True
with tempfile.TemporaryDirectory() as tmp:
    for name in PURE:
        source = open(os.path.join(SHARED, name + ".luau"), encoding="utf-8").read()
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
        open(os.path.join(tmp, name + ".luau"), "w", encoding="utf-8").write(source)
    # 3.7: the client's pure modules (no Roblox at their top level) that a test requires.
    for name in ("Stamina", "TouchLayout", "PhoneLayout", "MissionsLayout"):
        shutil.copy(os.path.join(os.path.dirname(SHARED), "client", name + ".luau"), os.path.join(tmp, name + ".luau"))
    shutil.copy(os.path.join(SHARED, "CourierMotion.luau"), os.path.join(tmp, "CourierMotion.luau"))
    shutil.copy(os.path.join(os.path.dirname(SHARED), "server", "CharacterArt", "Geometry.luau"), os.path.join(tmp, "CharacterGeometry.luau"))
    # 6.4: the kit art (pure: the bags' pieces, tests/bags_test.luau)
    shutil.copy(os.path.join(os.path.dirname(SHARED), "server", "KitArt", "Geometry.luau"), os.path.join(tmp, "KitGeometry.luau"))
    for path in sorted(glob.glob(os.path.join(HERE, "*_test.luau"))):
        shutil.copy(path, os.path.join(tmp, "test.luau"))
        print(f"== {os.path.basename(path)}")
        result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        if "ALL CHECKS PASSED" not in result.stdout:
            ok = False
# 3.3: the car bodies (server/Vehicles.luau STYLES, not loadable outside Roblox) read as text: every Config.Cars style
# has a body; every dealer car's body takes cargo and has a back that opens (the 3.2 loading).
# 3.4: every car's capacity (Config.Cars capacity) is exactly its body's cargo slots (the slot list of cargo(...)).
# 5.1: the bikes (CarDef.bike) are exempt from the back; their body must be a bike's (Style.bike) with slots = capacity.
# 3.5: every stage of a car (Config.Cars stages) holds exactly its look's slots (Vehicles.luau LOOKS[look].slots; stage
# 0 / no look: the body's), every look a stage names exists, and a dealer car holds at least 2 at its last stage.
def slot_count(body, key="cargo = cargo("):
    start = body.find(key)
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

def entries(text):
    blocks = {}
    for match in re.finditer(r"^\t(\w+) = \{\n(.*?)^\t\},?$", text, re.S | re.M):
        blocks[match.group(1)] = match.group(2)
    return blocks

def styles_check():
    root = os.path.dirname(HERE)
    config = open(os.path.join(root, "src", "shared", "Config.luau"), encoding="utf-8").read()
    vehicles = open(os.path.join(root, "src", "server", "Vehicles.luau"), encoding="utf-8").read()
    blocks = entries(vehicles[vehicles.index("local STYLES"):vehicles.index("local CHASSIS_HEIGHT")])
    looks_at = vehicles.index("local LOOKS")
    looks = entries(vehicles[looks_at:vehicles.index("\n}\n", looks_at) + 3])
    cars = config[config.index("Config.Cars = {"):config.index("} :: { CarDef }")]
    bad = []
    stages_seen = 0
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
        most = count
        for line in re.findall(r"^\t\t\t\{ name = .*$", entry, re.M):
            stages_seen += 1
            name = re.search(r'name = "([^"]+)"', line).group(1)
            held = int(re.search(r"\bcapacity = (\d+)", line).group(1))
            look = re.search(r'\blook = "(\w+)"', line)
            if look is None:
                slots = count
            elif look.group(1) not in looks:
                bad.append(f"{car_id} {name}: no look {look.group(1)}")
                continue
            else:
                slots = slot_count(looks[look.group(1)], "slots = {")
                # 4.0: a look that stretches the body belongs to a style that says where it grows (split = z).
                if "stretch = " in looks[look.group(1)] and "split = " not in body:
                    bad.append(f"{car_id} {name}: look {look.group(1)} stretches, style {style} has no split")
            if slots != held:
                bad.append(f"{car_id} {name}: capacity {held} but {slots} cargo slots")
            most = max(most, slots)
        if "company = true" in entry:
            continue
        # 5.1: a bike (bike = true) has no back that opens (you load its rack or box straight away) and may hold one
        # piece; its slots are its capacity (checked above). Its style says so (bike = true in the body).
        if re.search(r"\bbike = true", entry):
            if count < 1:
                bad.append(f"{car_id}: a bike without cargo slots")
            if not re.search(r"\bbike = true", body):
                bad.append(f"{car_id}: a bike on style {style}, which is not a bike body")
            continue
        if count < 1 or most < 2:
            bad.append(f"{car_id}: {count} cargo slots, {most} at its last stage")
        if "back = " not in body:
            bad.append(f"{car_id}: no back")
    print("== styles: " + (f"every car has a body, every dealer car cargo slots and a back, every capacity its slots ({len(blocks)} styles, {len(looks)} stage looks, {stages_seen} stages)" if not bad else "; ".join(bad)))
    return not bad

if not styles_check():
    ok = False

# 6.12, the clerks: the looks' clerks (Config.Cosmetics.Counters) are server/ShopClerks.luau's people at those shops,
# and their "Style" prompt's keys (R, the gamepad's L2) stay free: nothing else in src binds them.
def clerks_check():
    root = os.path.dirname(HERE)
    config = open(os.path.join(root, "src", "shared", "Config.luau"), encoding="utf-8").read()
    clerks = open(os.path.join(root, "src", "server", "ShopClerks.luau"), encoding="utf-8").read()
    start = config.index("\tCounters = {")
    counters = dict(re.findall(r'^\t\t(\w+) = \{ clerk = "(\w+)"', config[start:config.index("} :: { [string]: CosmeticCounter }", start)], re.M))
    people = dict(re.findall(r'^\t(\w+) = \{ name = "(\w+)"', clerks, re.M))
    bad = [f"{shop}: {name} in Config.Cosmetics.Counters, {people.get(shop)} in ShopClerks" for shop, name in counters.items() if people.get(shop) != name]
    if not counters:
        bad.append("no Counters in Config.Cosmetics")
    if "STYLE_KEY = Enum.KeyCode.R " not in clerks or "STYLE_PAD = Enum.KeyCode.ButtonL2 " not in clerks:
        bad.append("ShopClerks: the Style prompt's keys moved; update tests/run_tests.py")
    for folder, _, files in os.walk(os.path.join(root, "src")):
        for name in files:
            if name.endswith(".luau") and name != "ShopClerks.luau":
                if re.search(r"Enum\.KeyCode\.(R|ButtonL2)\b", open(os.path.join(folder, name), encoding="utf-8").read()):
                    bad.append(f"{name} binds R or L2, the clerks' Style prompt's keys")
    print("== clerks: " + (f"the looks' clerks are ShopClerks' people ({', '.join(f'{k} {v}' for k, v in counters.items())}); R and L2 only for their Style prompt" if not bad else "; ".join(bad)))
    return not bad

if not clerks_check():
    ok = False

# 6.13, analytics: every money reason the server passes (PlayerData.addMoney / spend, Analytics.money) is one of
# shared/AnalyticsPlan.luau's Sources or Sinks, and every custom event it names (Analytics.event, custom) one of its
# Events: a typo would only show as "Other" or a refused event in the dashboard, never here otherwise.
def analytics_check():
    root = os.path.dirname(HERE)
    plan = open(os.path.join(root, "src", "shared", "AnalyticsPlan.luau"), encoding="utf-8").read()
    def keys(name):
        start = plan.index(f"AnalyticsPlan.{name} = {{")
        return set(re.findall(r"^\t(\w+) = \"", plan[start:plan.index("\n}", start)], re.M))
    sources, sinks = keys("Sources"), keys("Sinks")
    start = plan.index("AnalyticsPlan.Events = {")
    events = set(re.findall(r'^\t"(\w+)",', plan[start:plan.index("\n}", start)], re.M))
    # 6.13 review: the game reaches Analytics only through PlayerData.track (the hooks Analytics.start registers) and
    # PlayerData.onMoney; only Main.server (inside `safely`) and Admin (inside a pcall) require the module.
    analytics = open(os.path.join(root, "src", "server", "Analytics.luau"), encoding="utf-8").read()
    start = analytics.index("PlayerData.analytics = {")
    hooks = set(re.findall(r"^\t\t(\w+) = Analytics\.", analytics[start:analytics.index("\n\t}", start)], re.M))
    bad, reasons, named, tracked = [], 0, 0, 0
    for folder, _, files in os.walk(os.path.join(root, "src", "server")):
        for name in sorted(files):
            if not name.endswith(".luau"):
                continue
            for number, line in enumerate(open(os.path.join(folder, name), encoding="utf-8"), 1):
                code = line.split("--", 1)[0]
                money = re.search(r"\b(addMoney|spend|tellMoney)\(.*?\"(\w+)\"", code) or re.search(r"\b(track)\(\"money\", [^\"]*\"(\w+)\"", code)
                if money:
                    reasons += 1
                    allowed = sources if money.group(1) == "addMoney" else sinks if money.group(1) == "spend" else sources | sinks
                    if money.group(2) not in allowed:
                        bad.append(f"{name}:{number}: money reason {money.group(2)} ({money.group(1)})")
                event = re.search(r"(?:\.event|\bcustom)\(\w+, \"(\w+)\"", code) or re.search(r"\btrack\(\"event\", \w+, \"(\w+)\"", code)
                if event:
                    named += 1
                    if event.group(1) not in events:
                        bad.append(f"{name}:{number}: event {event.group(1)}")
                hook = re.search(r"\btrack\(\"(\w+)\"", code)
                if hook:
                    tracked += 1
                    if hook.group(1) not in hooks:
                        bad.append(f"{name}:{number}: PlayerData.track(\"{hook.group(1)}\") is no hook of Analytics.start")
                if re.search(r"require\((?:script\.Parent|Server)\.Analytics\)", code) and name not in ("Main.server.luau", "Admin.luau"):
                    bad.append(f"{name}:{number}: requires Analytics (use PlayerData.track: the game must not depend on it)")
    print("== analytics: " + (f"{reasons} money reasons, {named} event names and {tracked} hook calls in src/server, all known ({len(sources)} sources, {len(sinks)} sinks, {len(events)} events, {len(hooks)} hooks)" if not bad else "; ".join(bad)))
    return not bad

if not analytics_check():
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
