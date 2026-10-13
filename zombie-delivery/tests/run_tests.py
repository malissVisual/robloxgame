#!/usr/bin/env python3
"""
Runs the logic tests of the pure shared modules (Config, Economy, Map, Roads, Icons, Levels, TrafficLanes, Crossings, SoundSheet, Missions, Challenges, Melee, Boarding, BuddyBrain, Goal, Tasks, 6.14: Regulars, SpecialOrders, 6.15: LiveEvents, 6.17: JobPick ...) in the
standalone Luau CLI: every tests/*_test.luau file, each must print "ALL CHECKS PASSED".

    python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
"""
import glob, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(os.path.dirname(HERE), "src", "shared")
PURE = ("Config", "ZombieKinds", "Economy", "Map", "FootbridgeShape", "Explore", "Roads", "Icons", "Levels", "TrafficLanes", "Crossings", "SoundSheet", "Cast", "NpcLooks", "Missions", "Challenges", "TutorialSteps", "Melee", "Boarding", "Freight", "LocationTags", "BuddyBrain", "Career", "JobRules", "Transport", "VanQuest", "KitFit", "RiderPose", "Bag", "Deliveries", "FuelMath", "Residents", "BusLines", "Shortcuts", "RentalDocks", "ZipLines", "Gestures", "FootEvents", "TowerLooks", "StreetProps", "WeatherPlan", "InteractPose", "Armour", "Throws", "RunCycle", "Holding", "BagSwing", "BagFill", "Goal", "BodyMotion", "AvatarLook", "ScooterRide", "CurbShape", "Tasks", "SoundPlan", "Style", "StyleLooks", "JobQueue", "JobThumbs", "MissionArt", "AnalyticsPlan", "RenderBudget", "Shift", "Regulars", "SpecialOrders", "Readiness", "OutlinePick", "MissionPlan", "LiveEvents", "ShotFeel", "SkyGrade", "Suspension", "DriveFeel", "ZombieStyle", "JobPick", "CardLayout", "ShopPick", "Skills", "Inventory", "KitArt", "CareerArt", "CarUpright", "SpawnSpot", "Gait", "MovingRules", "MoveStory", "MoveHelperBrain", "MoveRoles")
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
    # 7.0 review: client/MoveLayout.luau (pure, it requires TouchLayout: tests/movelayout_test.luau)
    source = open(os.path.join(os.path.dirname(SHARED), "client", "MoveLayout.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
    open(os.path.join(tmp, "MoveLayout.luau"), "w", encoding="utf-8").write(source)
    shutil.copy(os.path.join(SHARED, "CourierMotion.luau"), os.path.join(tmp, "CourierMotion.luau"))
    shutil.copy(os.path.join(os.path.dirname(SHARED), "server", "CharacterArt", "Geometry.luau"), os.path.join(tmp, "CharacterGeometry.luau"))
    # 6.4: the kit art (pure: the bags' pieces, tests/bags_test.luau)
    shutil.copy(os.path.join(SHARED, "KitArt.luau"), os.path.join(tmp, "KitGeometry.luau"))  # (6.22: moved to shared)
    shutil.copy(os.path.join(os.path.dirname(SHARED), "server", "BikeArt", "Geometry.luau"), os.path.join(tmp, "BikeGeometry.luau"))  # 6.19
    # 6.22: the inventory's looks (tests/itemlooks_test.luau) built by the real builders on a recorder: the vehicle
    # preview's Roblox mock and tools/fixtures/item-mock.luau's few additions, the builders' globals taken from it.
    tools = os.path.join(os.path.dirname(HERE), "tools")
    shutil.copy(os.path.join(tools, "vehicle-preview", "roblox-mock.luau"), os.path.join(tmp, "rbxmock.luau"))
    shutil.copy(os.path.join(tools, "fixtures", "item-mock.luau"), os.path.join(tmp, "ItemMock.luau"))
    prefix = 'local M = require("./ItemMock")\nlocal Instance, Vector3, CFrame, Color3, Enum, UDim2 = M.Instance, M.Vector3, M.CFrame, M.Color3, M.Enum, M.UDim2\n'
    # 7.0 (the moving prototype): the furniture and the house plans are made of Vector3s and CFrames, so they load on
    # the same recorder (tests/furniture_test.luau, tests/houselayout_test.luau).
    for name in ("GunModels", "CargoLooks", "ItemLooks", "FurnitureLooks", "HouseLayout"):
        source = open(os.path.join(SHARED, name + ".luau"), encoding="utf-8").read()
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
        open(os.path.join(tmp, name + ".luau"), "w", encoding="utf-8").write(prefix + source)
    # 7.0 (the moving prototype): the real server/HouseInterior.luau (tests/houseinterior_test.luau) on the recorder,
    # its shared modules the copies above, the recorder's `game`.
    source = open(os.path.join(os.path.dirname(SHARED), "server", "HouseInterior.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
    source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
    open(os.path.join(tmp, "HouseInterior.luau"), "w", encoding="utf-8").write(prefix + "local game = M.game\n" + source)
    # Its server/FurnitureMesh.luau (the owner's Blender furniture: no import in the recorder, so FurnitureLooks' look).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "FurnitureMesh.luau"), encoding="utf-8").read()
    source = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', source)
    open(os.path.join(tmp, "FurnitureMesh.luau"), "w", encoding="utf-8").write(prefix + "local game, workspace = M.game, M.workspace\n" + source)
    # 6.23 (Codex's codex/cargo-missions-fix): the real server/Cargo.luau as CargoServer.luau for
    # tests/cargo_runtime_test.luau: its server modules, Net and services from tests/runtime/CargoRuntime.luau (on the
    # same recorder as CargoLooks), its shared modules the copies above.
    shutil.copy(os.path.join(HERE, "runtime", "CargoRuntime.luau"), os.path.join(tmp, "CargoRuntime.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "Cargo.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    source = re.sub(r"require\(script\.Parent\.(\w+)\)", r"E.\1", source)
    head = ('local E = require("./CargoRuntime")\nlocal M = E.Mock\nlocal game, workspace, task = E.game, M.workspace, E.task\n'
            'local Instance, Vector3, Color3, CFrame, Enum = M.Instance, M.Vector3, M.Color3, M.CFrame, M.Enum\n'
            'local Random, RaycastParams, UDim2, TweenInfo, typeof = M.Random, M.RaycastParams, M.UDim2, M.TweenInfo, M.typeof\n')
    open(os.path.join(tmp, "CargoServer.luau"), "w", encoding="utf-8").write(head + source)
    # 7.0: the real server/Moving.luau as MovingServer.luau for tests/moving_runtime_test.luau: its server modules, Net,
    # the services and a fake of the house art from tests/runtime/MovingRuntime.luau (on the same recorder), its shared
    # modules (Config, Economy, Map, MovingRules) the copies above; os.clock and the server time are the test's.
    shutil.copy(os.path.join(HERE, "runtime", "MovingRuntime.luau"), os.path.join(tmp, "MovingRuntime.luau"))
    # 7.0, the depot's helper: the real server/MoveHelper.luau as MoveHelperServer.luau on the same fakes (MovingServer
    # requires it; tests/movehelper_runtime_test.luau drives it with its own walk: no physics, no pathfinding here).
    # 7.0 planning: the real server/MoveLobby.luau as MoveLobbyServer.luau the same way (the lobby and the quick chat;
    # Moving requires it).
    head = ('local E = require("./MovingRuntime")\nlocal M = E.Mock\nlocal game, workspace, task, os = E.game, M.workspace, E.task, E.os\n'
            'local Instance, Vector3, Color3, CFrame, Enum = M.Instance, M.Vector3, M.Color3, M.CFrame, M.Enum\n'
            'local RaycastParams, OverlapParams, UDim2, UDim, typeof = M.RaycastParams, M.OverlapParams, M.UDim2, M.UDim, M.typeof\n'
            'local warn = function(...) print("WARN", ...) end\n')
    built_as = {"MoveHelper": "MoveHelperServer", "MoveLobby": "MoveLobbyServer"}
    for module, built in (("Moving", "MovingServer"), ("MoveHelper", "MoveHelperServer"), ("MoveLobby", "MoveLobbyServer")):
        source = open(os.path.join(os.path.dirname(SHARED), "server", module + ".luau"), encoding="utf-8").read()
        source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
        source = source.replace("require(script.Parent.MoveSites)", 'require("./MoveSitesServer")')  # 7.0: the real one (below)
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", lambda m: f'require("./{built_as[m[1]]}")' if m[1] in built_as else f"E.{m[1]}", source)
        open(os.path.join(tmp, built + ".luau"), "w", encoding="utf-8").write(head + source)
    # 7.0, the moves' world: the real server/MoveSites.luau as MoveSitesServer.luau (Moving builds its board, drop-off and
    # houses with it) on the same recorder, DayNight the recorder's nightLight; shared/MoveSiteLooks.luau (pure) for it
    # and for tests/movesites_test.luau.
    looks = open(os.path.join(SHARED, "MoveSiteLooks.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "MoveSiteLooks.luau"), "w", encoding="utf-8").write(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', looks))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "MoveSites.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
    source = source.replace("require(script.Parent.DayNight)", "{ nightLight = M.nightLight }")
    open(os.path.join(tmp, "MoveSitesServer.luau"), "w", encoding="utf-8").write(head + source)
    for path in sorted(glob.glob(os.path.join(HERE, "*_test.luau"))):
        shutil.copy(path, os.path.join(tmp, "test.luau"))
        print(f"== {os.path.basename(path)}")
        result = subprocess.run([luau, "test.luau"], cwd=tmp, capture_output=True, text=True)
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        if result.returncode != 0 or "ALL CHECKS PASSED" not in result.stdout:
            ok = False
# 6.22: shared/ItemLooks.luau's Finish (the bags' and vests' colours on the client) agrees with
# server/ModelArt/Builder.luau's FINISH (the server-only builder of the kit worn on the character).
def finish_check():
    root = os.path.dirname(HERE)
    builder = open(os.path.join(root, "src", "server", "ModelArt", "Builder.luau"), encoding="utf-8").read()
    looks = open(os.path.join(root, "src", "shared", "ItemLooks.luau"), encoding="utf-8").read()
    pattern = re.compile(r"^\t(\w+) = \{ color = \{ (\d+), (\d+), (\d+) \}, material = (?:Enum\.Material\.(\w+)|\"(\w+)\") \},", re.M)
    server = {m.group(1): (m.group(2), m.group(3), m.group(4), m.group(5)) for m in pattern.finditer(builder)}
    block = looks[looks.index("ItemLooks.Finish = {"):]
    block = block[:block.index("\n}")]
    client = {m.group(1): (m.group(2), m.group(3), m.group(4), m.group(6)) for m in pattern.finditer(block)}
    bad = [name for name, value in client.items() if server.get(name) != value]
    if not client or bad:
        print("FAIL  ItemLooks.Finish differs from Builder's FINISH: " + ", ".join(bad or ["(none read)"]))
        return False
    print(f"ok    ItemLooks.Finish agrees with Builder's FINISH ({len(client)} finishes)")
    return True

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
    return len(re.findall(r"Vector3\.new|bikeArt\(", body[open_at:end]))  # (6.19: a bike's slots at its art's scale)

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
if not finish_check():  # 6.22
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

# 6.24: every require in src resolves to a ModuleScript where Rojo puts it (tools/check-requires.py: a module that
# moved, like 6.22's KitArt, or a typo shows here instead of as "X is not a valid member of Folder" in Studio).
requires = subprocess.run([sys.executable, os.path.join(os.path.dirname(HERE), "tools", "check-requires.py")], capture_output=True, text=True)
sys.stdout.write(requires.stdout + requires.stderr)
if requires.returncode != 0:
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
