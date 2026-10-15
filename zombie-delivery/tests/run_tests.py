#!/usr/bin/env python3
"""
Runs the logic tests of the pure shared modules (Config, Economy, Map, Roads, Icons, Levels, TrafficLanes, Crossings, SoundSheet, Missions, Challenges, Melee, Boarding, BuddyBrain, Goal, Tasks, 6.14: Regulars, SpecialOrders, 6.15: LiveEvents, 6.17: JobPick ...) in the
standalone Luau CLI: every tests/*_test.luau file, each must print "ALL CHECKS PASSED".

    python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
"""
import glob, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(os.path.dirname(HERE), "src", "shared")
PURE = ("Config", "ZombieKinds", "Economy", "Map", "FootbridgeShape", "Explore", "Roads", "Icons", "Levels", "TrafficLanes", "Crossings", "SoundSheet", "Cast", "NpcLooks", "Missions", "Challenges", "TutorialSteps", "Melee", "Boarding", "Freight", "LocationTags", "BuddyBrain", "Career", "JobRules", "Transport", "VanQuest", "KitFit", "RiderPose", "Bag", "Deliveries", "FuelMath", "Residents", "BusLines", "Shortcuts", "RentalDocks", "ZipLines", "Gestures", "FootEvents", "TowerLooks", "StreetProps", "WeatherPlan", "InteractPose", "Armour", "Throws", "RunCycle", "Holding", "BagSwing", "BagFill", "Goal", "BodyMotion", "AvatarLook", "ScooterRide", "CurbShape", "Tasks", "SoundPlan", "Style", "StyleLooks", "JobQueue", "JobThumbs", "MissionArt", "AnalyticsPlan", "RenderBudget", "Shift", "Regulars", "SpecialOrders", "Readiness", "OutlinePick", "MissionPlan", "LiveEvents", "ShotFeel", "SkyGrade", "Suspension", "DriveFeel", "ZombieStyle", "JobPick", "CardLayout", "ShopPick", "Skills", "Inventory", "KitArt", "CareerArt", "CarUpright", "SpawnSpot", "Gait", "MovingRules", "MoveStory", "MoveHelperBrain", "MoveRoles", "CarryGrip", "ChaletLooks", "AlpineLayout", "SandboxMap", "SandboxAdmin", "CollectionRules", "SandboxSteps", "WarehouseLayout", "SprinterLooks")
PURE += ("SandboxScenery",)  # 8.0 sandbox, the map (tests/sandboxworld_test.luau)
PURE += ("PairCarry",)  # 8.1 carrying in two: the leader's steering (tests/paircarry_test.luau)
PURE += ("UpgradeRules",)  # 8.1 sandbox, the upgrades (tests/upgrades_test.luau)
PURE += ("CollectionBookRules",)  # 8.2 sandbox, the collection book (tests/collectionbook_test.luau)
PURE += ("StockPlan",)  # 8.2 sandbox, the STOCK list's bulk buttons and orders (tests/stockplan_test.luau)
PURE += ("SandboxTasks",)  # 8.2 sandbox, the daily tasks (tests/sandboxtasks_test.luau)
PURE += ("SandboxLeadersRules",)  # 8.2 sandbox, showing off (tests/sandboxleaders_test.luau)
PURE += ("SandboxPad", "SandboxHints")  # 8.3 sandbox, every device's way to the chips and the first-time hints (tests/sandboxpad_test.luau, tests/sandboxhints_test.luau)
PURE += ("Market",)  # 8.3 sandbox, the market: hot and cold kinds, the demand (tests/market_test.luau)
PURE += ("AuctionRules", "AuctionHouseLayout")  # 8.8 sandbox, the auction: its rules and the Auction House (tests/auction_test.luau, tests/auctionhouse_test.luau)
PURE += ("Visitors",)  # 8.3 sandbox, the showroom's visitors: who, when, where they walk, the offers' prices (tests/visitors_test.luau)
PURE += ("VanPaintRules",)  # 8.3 sandbox, the PAINT shop: the catalogue, the prices, the looks, the save (tests/vanpaint_test.luau)
PURE += ("SandboxLightRules",)  # 8.3 sandbox, the light (tests/sandboxlight_test.luau, tests/sandboxlight_runtime_test.luau)
PURE += ("DoorSwing",)  # 8.3 walk-in doors: a door leaf's swing (tests/doorswing_test.luau)
PURE += ("SandboxBadgeRules",)  # 8.3 sandbox, the Roblox badges (tests/sandboxbadges_test.luau, tests/sandboxbadges_runtime_test.luau)
PURE += ("SaveGuard",)  # 8.3 saves: what a save writes, checked; the unknown keys kept (tests/saveguard_test.luau, tests/saving_runtime_test.luau)
PURE += ("ClipboardRules",)  # 8.5 Danny's clipboard, orders mode (tests/clipboard_test.luau, tests/clipboard_runtime_test.luau)
PURE += ("PlayerTradeRules",)  # 8.7 sandbox, trading between players (tests/playertrade_test.luau, tests/playertrade_runtime_test.luau)
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
    # 8.0 SANDBOX: the client's real client/Main.client.luau as ClientMain.luau, a function of the globals it reads, so
    # tests/clientboot_test.luau runs it on recorders (the city's start list unchanged, the sandbox's only its own).
    source = open(os.path.join(os.path.dirname(SHARED), "client", "Main.client.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "ClientMain.luau"), "w", encoding="utf-8").write(
        "return function(script: any, game: any, workspace: any, require: any, task: any, warn: any, Enum: any)\n" + source + "\nend\n")
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
        source = re.sub(r"require\(script\.Parent\.Layouts\.(\w+)\)", r'require("./\1")', source)  # 7.x: the farm's layout
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
        open(os.path.join(tmp, name + ".luau"), "w", encoding="utf-8").write(prefix + source)
    # 8.3: shared/VanLook.luau (the PAINT shop paints a van: Roblox instances) on the same recorder, with its typeof
    # (tests/vanpaint_runtime_test.luau; the sandbox's e2e paints its vans with it too).
    source = open(os.path.join(SHARED, "VanLook.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
    open(os.path.join(tmp, "VanLook.luau"), "w", encoding="utf-8").write(prefix + "local typeof = M.typeof\n" + source)
    # 7.x: shared/Layouts (Farm.luau: Walt's farm, HouseLayout's kind "farm"; tests/farmlayout_test.luau) next to them,
    # on the same recorder, their script.Parent.Parent.X requires the copies above
    for path in sorted(glob.glob(os.path.join(SHARED, "Layouts", "*.luau"))):
        source = open(path, encoding="utf-8").read()
        source = re.sub(r"require\(script\.Parent\.Parent\.(\w+)\)", r'require("./\1")', source)
        open(os.path.join(tmp, os.path.basename(path)), "w", encoding="utf-8").write(prefix + source)
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
    # 8.0 SANDBOX: the real server/Main.server.luau and server/SandboxBoot.luau as MainServer.luau and
    # SandboxBootServer.luau for tests/boot_runtime_test.luau: each source wrapped in a function (the test runs it once
    # per world: the sandbox's, the city's), its Roblox globals and `require` tests/runtime/BootRuntime.luau's recorders,
    # bound again at every run; Config, Economy and SandboxMap the real copies above.
    shutil.copy(os.path.join(HERE, "runtime", "BootRuntime.luau"), os.path.join(tmp, "BootRuntime.luau"))
    bind = ('local E = require("./BootRuntime")\nreturn function()\n'
            'local game, workspace, script, task, require, warn, print = E.game, E.workspace, E.script, E.task, E.require, E.warn, E.print\n'
            'local Instance, CFrame, Vector3 = E.Instance, E.CFrame, E.Vector3\n')
    for module, built in (("Main.server", "MainServer"), ("SandboxBoot", "SandboxBootServer")):
        source = open(os.path.join(os.path.dirname(SHARED), "server", module + ".luau"), encoding="utf-8").read()
        source = re.sub(r"^export type ", "type ", source, flags=re.M)  # (only at a module's top level)
        open(os.path.join(tmp, built + ".luau"), "w", encoding="utf-8").write(bind + source + "\nend\n")
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
    # 7.0 greeters: the real server/MoveGreeters.luau as MoveGreetersServer.luau the same way (the client on the porch, the
    # soldier at the Wall, Marge at the kiosk; Moving requires it; tests/movegreeters_runtime_test.luau drives it).
    # 8.1 carrying in two: the real server/PairHold.luau as PairHoldServer.luau the same way (Danny's hold and a crew
    # mate's at a piece's far end; MoveHelper and Moving require it).
    built_as = {"MoveHelper": "MoveHelperServer", "MoveLobby": "MoveLobbyServer", "MoveGreeters": "MoveGreetersServer", "PairHold": "PairHoldServer"}
    for module, built in (("Moving", "MovingServer"), ("MoveHelper", "MoveHelperServer"), ("MoveLobby", "MoveLobbyServer"), ("MoveGreeters", "MoveGreetersServer"), ("PairHold", "PairHoldServer")):
        source = open(os.path.join(os.path.dirname(SHARED), "server", module + ".luau"), encoding="utf-8").read()
        source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
        source = source.replace("require(script.Parent.MoveSites)", 'require("./MoveSitesServer")')  # 7.0: the real one (below)
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", lambda m: f'require("./{built_as[m[1]]}")' if m[1] in built_as else f"E.{m[1]}", source)
        open(os.path.join(tmp, built + ".luau"), "w", encoding="utf-8").write(head + source)
    # 8.5.1 (the owner: "Danny STILL goes through the van"): the REAL vehicle factory, server/Vehicles.luau and its art
    # builders staged as tools/vehicle-preview/export_fleet.py stages them, on the same recorder (rbxmock: ItemMock's,
    # so MovingRuntime's), each under a RealVan name: tests/movehelper_realvan_runtime_test.luau builds the Sprinter the
    # game builds (its hull, its seats and doors, their attachments) into the moves' runtime and rides Danny round it.
    # Net, World and PlayerData empty (nothing of them is used to build), DayNight the recorder's night light;
    # RealVanVehicles.__testBuild / __testStyle / __testDoors are its build, styleFor and doorsOf.
    real_van = {"Vehicles": "src/server/Vehicles.luau", "Builder": "src/server/VehicleArt/Builder.luau", "Geometry": "src/server/VehicleArt/Geometry.luau",
                "BikeGeometry": "src/server/BikeArt/Geometry.luau", "ScooterGeometry": "src/server/ScooterArt/Geometry.luau",
                "ModelBuilder": "src/server/ModelArt/Builder.luau", "VanMesh": "src/server/VanMesh.luau"}
    real_prefix = ('local Mock = require("./rbxmock")\nlocal game, workspace, Instance, Vector3, Vector2, Color3, CFrame, Enum, PhysicalProperties, UDim2, typeof = '
                   'Mock.game, Mock.workspace, Mock.Instance, Mock.Vector3, Mock.Vector2, Mock.Color3, Mock.CFrame, Mock.Enum, Mock.PhysicalProperties, Mock.UDim2, Mock.typeof\n')
    for name in ("Net", "World", "PlayerData"):
        open(os.path.join(tmp, "RealVan" + name + ".luau"), "w", encoding="utf-8").write("return {}\n")
    open(os.path.join(tmp, "RealVanDayNight.luau"), "w", encoding="utf-8").write('local Mock = require("./rbxmock")\nreturn { nightLight = Mock.nightLight }\n')
    for name, path in real_van.items():
        source = open(os.path.join(os.path.dirname(HERE), path), encoding="utf-8").read()
        source = source.replace("require(script.Parent.BikeArt.Geometry)", 'require("./RealVanBikeGeometry")')
        source = source.replace("require(script.Parent.ModelArt.Builder)", 'require("./RealVanModelBuilder")')
        source = source.replace("require(script.Parent.ScooterArt.Geometry)", 'require("./RealVanScooterGeometry")')
        source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: f'require("./RealVan{m[1]}")' if m[1] == "Net" else f'require("./{m[1]}")', source)
        source = re.sub(r"require\(script\.Parent\.(?:VehicleArt\.)?(\w+)\)", r'require("./RealVan\1")', source)
        if name == "Vehicles":
            source = re.sub(r"^return Vehicles$", "Vehicles.__testBuild = build\nVehicles.__testStyle = styleFor\nVehicles.__testDoors = doorsOf\nreturn Vehicles", source, flags=re.M)
        open(os.path.join(tmp, "RealVan" + name + ".luau"), "w", encoding="utf-8").write(real_prefix + source)
    # 8.5.1 (Danny's hand on the van's door; the house's doors opening nicely): the real client/ArmPose.luau and
    # client/WalkDoors.luau as ArmPoseClient.luau and WalkDoorsClient.luau for tests/armpose_npc_test.luau and
    # tests/walkdoors_test.luau, their Roblox globals and their client modules tests/runtime/ClientRuntime.luau's, their
    # shared modules the copies above and shared/Joints.luau.
    shutil.copy(os.path.join(HERE, "runtime", "ClientRuntime.luau"), os.path.join(tmp, "ClientRuntime.luau"))
    shutil.copy(os.path.join(SHARED, "Joints.luau"), os.path.join(tmp, "Joints.luau"))
    client_head = ('local E = require("./ClientRuntime")\nlocal game, workspace, CFrame, Vector3, Color3, Enum, Instance, os = '
                   'E.game, E.workspace, E.CFrame, E.Vector3, E.Color3, E.Enum, E.Instance, E.os\n')
    for module, built in (("ArmPose", "ArmPoseClient"), ("WalkDoors", "WalkDoorsClient")):
        source = open(os.path.join(os.path.dirname(SHARED), "client", module + ".luau"), encoding="utf-8").read()
        source = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\):WaitForChild\("(\w+)"\)\)', r'require("./\1")', source)
        source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
        source = re.sub(r"require\(script\.Parent\.(\w+)\)", r"E.\1", source)
        open(os.path.join(tmp, built + ".luau"), "w", encoding="utf-8").write(client_head + source)
    # 8.3 (Danny's hops): the real server/Npcs.luau as NpcsServer.luau for tests/npcs_runtime_test.luau, one line on
    # top: setfenv to tests/runtime/NpcsRuntime.luau's environment (its services, a person's body on the item recorder,
    # a require that gives the Shared copies above for ReplicatedStorage.Shared's modules).
    shutil.copy(os.path.join(HERE, "runtime", "NpcsRuntime.luau"), os.path.join(tmp, "NpcsRuntime.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "Npcs.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "NpcsServer.luau"), "w", encoding="utf-8").write('setfenv(1, require("./NpcsRuntime").env)\n' + source)
    # 8.3: the real client/PairSteer.luau (the leader's side of carrying in two) as PairSteerClient.luau for
    # tests/pairsteer_test.luau: a function of the globals it reads (the test's game, a require that gives the PairCarry
    # copy above, the recorder's CFrame).
    source = open(os.path.join(os.path.dirname(SHARED), "client", "PairSteer.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "PairSteerClient.luau"), "w", encoding="utf-8").write(
        "return function(game: any, require: any, CFrame: any)\n" + source + "\nend\n")
    # 7.0, the moves' world: the real server/MoveSites.luau as MoveSitesServer.luau (Moving builds its board, drop-off and
    # houses with it) on the same recorder, DayNight the recorder's nightLight; shared/MoveSiteLooks.luau (pure) for it
    # and for tests/movesites_test.luau.
    looks = open(os.path.join(SHARED, "MoveSiteLooks.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "MoveSiteLooks.luau"), "w", encoding="utf-8").write(re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', looks))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "MoveSites.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
    source = source.replace("require(script.Parent.DayNight)", "{ nightLight = M.nightLight }")
    open(os.path.join(tmp, "MoveSitesServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.5 Danny's clipboard (orders mode): the real server/Clipboard.luau as ClipboardServer.luau on the same fakes
    # (tests/clipboard_runtime_test.luau runs it beside the real Moving and MoveHelper), its art built by the real
    # server/ModelArt/Builder.luau (ClipboardBuilder.luau) on the same recorder, its shared modules the copies above.
    source = open(os.path.join(os.path.dirname(SHARED), "server", "ModelArt", "Builder.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "ClipboardBuilder.luau"), "w", encoding="utf-8").write(head + source)
    source = open(os.path.join(os.path.dirname(SHARED), "server", "Clipboard.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    source = source.replace("require(script.Parent.ModelArt.Builder)", 'require("./ClipboardBuilder")')
    open(os.path.join(tmp, "ClipboardServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.0 sandbox, the warehouse: the real server/Warehouse.luau as WarehouseServer.luau for
    # tests/warehouse_runtime_test.luau: SandboxPlots, Collection, Net and the services from tests/runtime/WarehouseRuntime.luau
    # (on MovingRuntime's recorder and players), FurnitureMesh the copy above, its shared modules the copies.
    shutil.copy(os.path.join(HERE, "runtime", "WarehouseRuntime.luau"), os.path.join(tmp, "WarehouseRuntime.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "Warehouse.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "W.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    source = re.sub(r"require\(script\.Parent\.(\w+)\)", lambda m: f'require("./{m[1]}")' if m[1] in ("FurnitureMesh", "WarehouseMesh") else f"W.{m[1]}", source)
    warehouse_head = ('local W = require("./WarehouseRuntime")\nlocal M = W.Mock\nlocal game, workspace, task, os = W.game, M.workspace, W.task, W.os\n'
                      'local Instance, Vector3, Color3, CFrame, Enum, UDim2, UDim = M.Instance, M.Vector3, M.Color3, M.CFrame, M.Enum, M.UDim2, M.UDim\n'
                      'local warn = function(...) print("WARN", ...) end\n')
    open(os.path.join(tmp, "WarehouseServer.luau"), "w", encoding="utf-8").write(warehouse_head + source)
    # 8.2: its server/WarehouseMesh.luau (the owner's Blender warehouse) on the same recorder: no import there, so every
    # warehouse stays as built (tools/warehouse/mesh-check.py dresses them with one).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "WarehouseMesh.luau"), encoding="utf-8").read()
    source = re.sub(r'require\(ReplicatedStorage:WaitForChild\("Shared"\)\.(\w+)\)', r'require("./\1")', source)
    storage = ('local storage = M.Instance.new("Folder")\n'
               'local game = { GetService = function(_, name) if name == "ServerStorage" then return storage end return M.game:GetService(name) end }\n'
               'local workspace = M.workspace\n')
    open(os.path.join(tmp, "WarehouseMesh.luau"), "w", encoding="utf-8").write(prefix + storage + source)
    # 7.1 review: the real server/Alpine.luau as AlpineServer.luau on tools/perf/world-mock.luau (WorldMock.luau) for
    # tests/alpinebuild_test.luau (the forests stand on World's parts only; SkipInStudio), its shared modules the copies.
    shutil.copy(os.path.join(tools, "perf", "world-mock.luau"), os.path.join(tmp, "WorldMock.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "Alpine.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
    open(os.path.join(tmp, "AlpineServer.luau"), "w", encoding="utf-8").write('setfenv(1, require("./WorldMock").env)\n' + source)
    # 8.0 SANDBOX: the real server/Admin.luau as AdminServer.luau for tests/adminsandbox_runtime_test.luau (the SANDBOX
    # tab's "sandbox" command: a non-admin refused, the checks, the rate limit, each button): its server modules, Net and
    # the services from tests/runtime/AdminRuntime.luau (on the item recorder), its shared modules the copies above.
    shutil.copy(os.path.join(HERE, "runtime", "AdminRuntime.luau"), os.path.join(tmp, "AdminRuntime.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "Admin.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    source = re.sub(r"require\(Server\.(\w+)\)", r"E.\1", source)
    head = ('local E = require("./AdminRuntime")\nlocal M = E.Mock\nlocal game, workspace, task, os, script = E.game, E.workspace, E.task, E.os, E.script\n'
            'local Instance, Vector3, CFrame, Enum, Random, RaycastParams, typeof = M.Instance, M.Vector3, M.CFrame, E.Enum, E.Random, E.RaycastParams, M.typeof\n'
            'local warn = function(...) print("WARN", ...) end\n')
    open(os.path.join(tmp, "AdminServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.0 SANDBOX, the collection: the real server/PlayerData.luau and server/Collection.luau as PlayerDataServer.luau and
    # CollectionServer.luau for tests/collection_runtime_test.luau, on tests/runtime/CollectionRuntime.luau's few services
    # (players who join and leave, a DataStore that keeps what JSON would, the test's clock, a fake Net); their shared
    # modules the copies above (shared/CollectionRules.luau on FurnitureLooks' recorder copy).
    shutil.copy(os.path.join(HERE, "runtime", "CollectionRuntime.luau"), os.path.join(tmp, "CollectionRuntime.luau"))
    head = ('local E = require("./CollectionRuntime")\n'
            'local game, task, os, Instance, warn, Enum = E.game, E.task, E.os, E.Instance, E.warn, E.Enum\n')
    for module in ("PlayerData", "Collection"):
        source = open(os.path.join(os.path.dirname(SHARED), "server", module + ".luau"), encoding="utf-8").read()
        source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
        source = source.replace("require(script.Parent.PlayerData)", 'require("./PlayerDataServer")')
        open(os.path.join(tmp, module + "Server.luau"), "w", encoding="utf-8").write(head + source)
    # 8.1 SANDBOX, the upgrades: the real server/Upgrades.luau as UpgradesServer.luau for tests/upgrades_runtime_test.luau
    # on the same runtime: its PlayerData and Collection the real ones above, SandboxPlots the runtime's fake (its plotOf),
    # `workspace` the runtime's (a Cars folder whose vans come with Runtime.addCar).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "Upgrades.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    source = source.replace("require(script.Parent.PlayerData)", 'require("./PlayerDataServer")')
    source = source.replace("require(script.Parent.Collection)", 'require("./CollectionServer")')
    source = source.replace("require(script.Parent.SandboxPlots)", "E.SandboxPlots")
    open(os.path.join(tmp, "UpgradesServer.luau"), "w", encoding="utf-8").write(head + "local workspace = E.workspace\n" + source)
    # 8.2 SANDBOX, the collection book: the real server/CollectionBook.luau as CollectionBookServer.luau for
    # tests/collectionbook_runtime_test.luau on the same runtime (its PlayerData and Collection the real ones above).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "CollectionBook.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    source = source.replace("require(script.Parent.PlayerData)", 'require("./PlayerDataServer")')
    source = source.replace("require(script.Parent.Collection)", 'require("./CollectionServer")')
    open(os.path.join(tmp, "CollectionBookServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.3 SANDBOX, the PAINT shop: the real server/VanPaint.luau as VanPaintServer.luau for tests/vanpaint_runtime_test.luau
    # on the same runtime (its PlayerData the real one above) and tests/runtime/VanPaintRuntime.luau's few additions (a
    # CollectionService, a prompt's Triggered, the vans: a fake Vehicles); shared/VanLook.luau the recorder's copy above.
    shutil.copy(os.path.join(HERE, "runtime", "VanPaintRuntime.luau"), os.path.join(tmp, "VanPaintRuntime.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "VanPaint.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    source = source.replace("require(script.Parent.PlayerData)", 'require("./PlayerDataServer")')
    source = source.replace("require(script.Parent.Vehicles)", "P.Vehicles")
    source = source.replace("require(script.Parent.SandboxPlots)", "E.SandboxPlots")
    assert "script.Parent" not in source, "server/VanPaint.luau requires a module tests/run_tests.py does not give it"
    paint_head = ('local P = require("./VanPaintRuntime")\nlocal E, M = P.E, P.Mock\n'
                  'local game, task, os, warn, Instance = P.game, E.task, E.os, E.warn, P.Instance\n'
                  'local Vector3, CFrame, Color3, Enum, typeof = M.Vector3, M.CFrame, M.Color3, M.Enum, M.typeof\n')
    open(os.path.join(tmp, "VanPaintServer.luau"), "w", encoding="utf-8").write(paint_head + source)
    # 8.2 SANDBOX, analytics: the real server/Analytics.luau and server/SandboxAnalytics.luau as AnalyticsServer.luau and
    # SandboxAnalyticsServer.luau for tests/sandboxanalytics_runtime_test.luau on the same runtime: PlayerData and
    # Collection the real ones above, Moving the test's fake (E.Moving: its listeners' registration), AnalyticsService the
    # test's recorder (through E.game's GetService), Roblox's Enum the few names Analytics sends.
    enums = ('local Enum: any = { AnalyticsEconomyFlowType = { Source = "Source", Sink = "Sink" }, '
             'AnalyticsProgressionType = { Start = "Start", Complete = "Complete", Fail = "Fail" } }\n')
    for module in ("Analytics", "SandboxAnalytics"):
        source = open(os.path.join(os.path.dirname(SHARED), "server", module + ".luau"), encoding="utf-8").read()
        source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
        source = source.replace("require(script.Parent.PlayerData)", 'require("./PlayerDataServer")')
        source = source.replace("require(script.Parent.Collection)", 'require("./CollectionServer")')
        source = source.replace("require(script.Parent.Moving)", "E.Moving")
        open(os.path.join(tmp, module + "Server.luau"), "w", encoding="utf-8").write(head + enums + source)
    # 8.2 SANDBOX, the daily tasks: the real server/SandboxTasks.luau as SandboxTasksServer.luau for
    # tests/sandboxtasks_runtime_test.luau on the same runtime: its PlayerData, Collection and Upgrades the real ones
    # above, Moving and MoveHelper tests/runtime/SandboxTasksRuntime.luau's stand-ins (their hooks, Danny's find).
    shutil.copy(os.path.join(HERE, "runtime", "SandboxTasksRuntime.luau"), os.path.join(tmp, "SandboxTasksRuntime.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "SandboxTasks.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    for module, built in (("PlayerData", '"./PlayerDataServer"'), ("Collection", '"./CollectionServer"'), ("Upgrades", '"./UpgradesServer"')):
        source = source.replace(f"require(script.Parent.{module})", f"require({built})")
    for module in ("Moving", "MoveHelper"):
        source = source.replace(f"require(script.Parent.{module})", f'require("./SandboxTasksRuntime").{module}')
    assert "script.Parent" not in source, "server/SandboxTasks.luau requires a module tests/run_tests.py does not give it"
    open(os.path.join(tmp, "SandboxTasksServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.3 SANDBOX, the showroom visitors' offers: the real server/VisitorOffers.luau as VisitorOffersServer.luau for
    # tests/visitoroffers_runtime_test.luau on the same runtime (its PlayerData, Collection and SandboxTasks the real ones
    # above).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "VisitorOffers.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    for module, built in (("PlayerData", '"./PlayerDataServer"'), ("Collection", '"./CollectionServer"'), ("SandboxTasks", '"./SandboxTasksServer"')):
        source = source.replace(f"require(script.Parent.{module})", f"require({built})")
    assert "script.Parent" not in source, "server/VisitorOffers.luau requires a module tests/run_tests.py does not give it"
    open(os.path.join(tmp, "VisitorOffersServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.7 SANDBOX, trading between players: the real server/PlayerTrade.luau as PlayerTradeServer.luau for
    # tests/playertrade_runtime_test.luau on the same runtime (its PlayerData, Collection, CollectionBook, VisitorOffers
    # and SandboxBadges the real ones above and below).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "PlayerTrade.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    for module, built in (("PlayerData", '"./PlayerDataServer"'), ("Collection", '"./CollectionServer"'), ("CollectionBook", '"./CollectionBookServer"'),
                          ("VisitorOffers", '"./VisitorOffersServer"'), ("SandboxBadges", '"./SandboxBadgesServer"')):
        source = source.replace(f"require(script.Parent.{module})", f"require({built})")
    assert "script.Parent" not in source, "server/PlayerTrade.luau requires a module tests/run_tests.py does not give it"
    open(os.path.join(tmp, "PlayerTradeServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.3 SANDBOX, the Roblox badges: the real server/SandboxBadges.luau as SandboxBadgesServer.luau for
    # tests/sandboxbadges_runtime_test.luau on the same runtime: its PlayerData, Collection and Upgrades the real ones
    # above, Moving and SandboxLeaders the test's stand-ins (E.Moving: its onResult; E.SandboxLeaders: the board's rows),
    # BadgeService the test's fake (through E.game's GetService).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "SandboxBadges.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", lambda m: "E.Net" if m[1] == "Net" else f'require("./{m[1]}")', source)
    for module, built in (("PlayerData", '"./PlayerDataServer"'), ("Collection", '"./CollectionServer"'), ("Upgrades", '"./UpgradesServer"')):
        source = source.replace(f"require(script.Parent.{module})", f"require({built})")
    for module in ("Moving", "SandboxLeaders"):
        source = source.replace(f"require(script.Parent.{module})", f"E.{module}")
    assert "script.Parent" not in source, "server/SandboxBadges.luau requires a module tests/run_tests.py does not give it"
    open(os.path.join(tmp, "SandboxBadgesServer.luau"), "w", encoding="utf-8").write(head + source)
    # 8.2 SANDBOX, showing off: the real server/SandboxLeaders.luau as SandboxLeadersServer.luau for
    # tests/sandboxleaders_runtime_test.luau on the same runtime (its PlayerData and Collection the real ones above) and
    # tests/runtime/LeadersRuntime.luau's few additions (an OrderedDataStore, UDim2 / UDim / Vector2, a game giving it).
    shutil.copy(os.path.join(HERE, "runtime", "LeadersRuntime.luau"), os.path.join(tmp, "LeadersRuntime.luau"))
    source = open(os.path.join(os.path.dirname(SHARED), "server", "SandboxLeaders.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
    source = source.replace("require(script.Parent.PlayerData)", 'require("./PlayerDataServer")')
    source = source.replace("require(script.Parent.Collection)", 'require("./CollectionServer")')
    leaders_head = ('local L = require("./LeadersRuntime")\nlocal E, M = L.E, L.E.Mock\n'
                    'local game, task, os, warn, workspace = L.game, E.task, E.os, E.warn, E.workspace\n'
                    'local Instance, Vector3, Vector2, CFrame, Color3, Enum, UDim2, UDim = E.Instance, M.Vector3, M.Vector2, M.CFrame, M.Color3, M.Enum, L.UDim2, L.UDim\n')
    open(os.path.join(tmp, "SandboxLeadersServer.luau"), "w", encoding="utf-8").write(leaders_head + source)
    # 8.0 sandbox, the map: the real server/SandboxWorld.luau as SandboxWorldServer.luau on the same mock for
    # tests/sandboxworld_test.luau, its shared modules the copies above.
    source = open(os.path.join(os.path.dirname(SHARED), "server", "SandboxWorld.luau"), encoding="utf-8").read()
    source = re.sub(r"require\(Shared\.(\w+)\)", r'require("./\1")', source)
    source = source.replace("require(script.Parent.HouseMesh)", 'require("./HouseMeshServer")')
    open(os.path.join(tmp, "SandboxWorldServer.luau"), "w", encoding="utf-8").write('setfenv(1, require("./WorldMock").env)\n' + source)
    # 8.1: its server/HouseMesh.luau on the same mock as HouseMeshServer.luau (no import there: the chalet stays; DayNight
    # a stand-in), and the owner's Blender house as numbers for the test (HouseArt.luau, from
    # design/blender-house/roblox/ZDCHouseArt.json, house.py's manifest: the box it was made for, its front door's
    # leaves, its top; the house's frame: the bottom's middle, -Z the front). tools/house-art/check.py dresses it.
    source = open(os.path.join(os.path.dirname(SHARED), "server", "HouseMesh.luau"), encoding="utf-8").read()
    source = source.replace("require(script.Parent.DayNight)", "{ nightLight = function() end }")
    open(os.path.join(tmp, "HouseMeshServer.luau"), "w", encoding="utf-8").write('setfenv(1, require("./WorldMock").env)\n' + source)
    art = json.load(open(os.path.join(os.path.dirname(HERE), "design", "blender-house", "roblox", "ZDCHouseArt.json"), encoding="utf-8"))
    leaves = [d for d in art["details"] if d["name"].startswith("Křídlo dveří") and d["center"][2] < 0]
    lo = [min(d["center"][i] - d["size"][i] / 2 for d in leaves) for i in range(3)]
    hi = [max(d["center"][i] + d["size"][i] / 2 for d in leaves) for i in range(3)]
    top = max(p["center"][1] + p["size"][1] / 2 for p in art["pieces"].values())
    # (8.3 the big move: its back door's leaf too, the one in the back wall: +Z; none in a city export: the front's)
    backs = [d for d in art["details"] if d["name"].startswith("Křídlo dveří") and d["center"][2] > 0] or leaves
    b_lo = [min(d["center"][i] - d["size"][i] / 2 for d in backs) for i in range(3)]
    b_hi = [max(d["center"][i] + d["size"][i] / 2 for d in backs) for i in range(3)]
    # (8.3 walk-in doors: where its back door's handle is across it, its knob's X: the leaf hangs on the other side)
    knobs = [d["center"][0] for d in art["details"] if d["name"].startswith("Klika") and d["center"][2] > 0] or [0]
    open(os.path.join(tmp, "HouseArt.luau"), "w", encoding="utf-8").write(
        "return { box = { %r, %r, %r }, door = { x0 = %r, x1 = %r, y0 = %r, y1 = %r, z0 = %r, z1 = %r }, top = %r, "
        "back = { x0 = %r, x1 = %r, y0 = %r, y1 = %r, z0 = %r, z1 = %r }, backKnob = %r }\n"
        % (*art["box"], lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], top, b_lo[0], b_hi[0], b_lo[1], b_hi[1], b_lo[2], b_hi[2], sum(knobs) / len(knobs)))
    # 8.8: the Jinočany plan (design/jinocany/plan.json: the village the sandbox becomes) as JinocanyPlan.luau for
    # tests/auctionhouse_test.luau: the Auction House stands on none of its roads, landmarks, fields, houses or tree lines.
    plan = json.load(open(os.path.join(os.path.dirname(HERE), "design", "jinocany", "plan.json"), encoding="utf-8"))
    def rect(r):
        return "{ x0 = %r, x1 = %r, z0 = %r, z1 = %r }" % (r["x0"], r["x1"], r["z0"], r["z1"])
    areas = [("road " + r["name"], r["rect"]) for r in plan["roads"]] + [(l["id"], l["rect"]) for l in plan["landmarks"]]
    areas += [("field " + f["kind"], f["rect"]) for f in plan["fields"]] + [("house " + h["id"], h["box"]) for h in plan["houses"] + plan["enter"]]
    lines = ["\t{ name = %s, rect = %s }," % (json.dumps(name, ensure_ascii=False), rect(r)) for name, r in areas]
    trees = ["\t{ %s }," % ", ".join("{ %r, %r }" % (p["x"], p["z"]) for p in t["points"]) for t in plan["treeLines"]]
    open(os.path.join(tmp, "JinocanyPlan.luau"), "w", encoding="utf-8").write(
        "return {\nbounds = %s,\nareas = {\n%s\n},\ntreeLines = {\n%s\n},\n}\n" % (rect(plan["bounds"]), "\n".join(lines), "\n".join(trees)))
    # 8.0.1 review: the real server/SandboxPlots.luau as SandboxPlotsServer.luau for tests/sandboxplots_runtime_test.luau:
    # a function of the globals it reads (the test's own Players, ReplicatedStorage and task, and a `require` that gives
    # the real SandboxMap copy above).
    source = open(os.path.join(os.path.dirname(SHARED), "server", "SandboxPlots.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "SandboxPlotsServer.luau"), "w", encoding="utf-8").write(
        "return function(game: any, task: any, require: any)\n" + source + "\nend\n")
    # 8.2 e2e: the whole sandbox loop with the REAL modules together (tests/sandbox_e2e_runtime_test.luau). The server
    # modules SandboxE2E.luau lists in E.real (the boot, the map, PlayerData, the plots, the collection, the warehouse,
    # the upgrades, the moves and theirs) and shared/Net.luau as E2E<Name>.luau, unchanged but for one line on top:
    # setfenv to tests/runtime/SandboxE2E.luau's environment (its game, workspace, script, task, os and require: no
    # module gains a local, no require is rewritten). Their shared modules are the copies above; a server module not in
    # E.real is one of SandboxE2E's fakes (E.fakes) or an error that names it.
    harness = open(os.path.join(HERE, "runtime", "SandboxE2E.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "SandboxE2E.luau"), "w", encoding="utf-8").write(harness)
    start = harness.index("E.real = {")
    e2e_env = 'setfenv(1, require("./SandboxE2E").env)\n'
    for module in re.findall(r"(\w+) = true", harness[start:harness.index("}", start)]):
        source = open(os.path.join(os.path.dirname(SHARED), "server", module + ".luau"), encoding="utf-8").read()
        open(os.path.join(tmp, "E2E" + module + ".luau"), "w", encoding="utf-8").write(e2e_env + source)
    source = open(os.path.join(SHARED, "Net.luau"), encoding="utf-8").read()
    open(os.path.join(tmp, "E2ENet.luau"), "w", encoding="utf-8").write(e2e_env + source)
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
    # 7.x (one car): the bodies nobody owns any more (Config.AmbientCars: the traffic's vans at every stage, the buses,
    # the company vehicles) are checked the same way: the world still builds them
    ambient_at = config.index("Config.AmbientCars = {")
    cars += config[ambient_at:config.index("} :: { CarDef }", ambient_at)]
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
    # PlayerData.onMoney; only Main.server (inside `safely`) and Admin (inside a pcall) require the module (8.0: and
    # SandboxBoot, the sandbox's Main, inside its `safely`).
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
                if re.search(r"require\((?:script\.Parent|Server)\.Analytics\)", code) and name not in ("Main.server.luau", "Admin.luau", "SandboxBoot.luau"):
                    bad.append(f"{name}:{number}: requires Analytics (use PlayerData.track: the game must not depend on it)")
    print("== analytics: " + (f"{reasons} money reasons, {named} event names and {tracked} hook calls in src/server, all known ({len(sources)} sources, {len(sinks)} sinks, {len(events)} events, {len(hooks)} hooks)" if not bad else "; ".join(bad)))
    return not bad

if not analytics_check():
    ok = False

# 7.1 review: a new server answers PLAY and has its lighting before the Alps' terrain is built. World.build lights the
# world before its last piece starts the Alps (the cheap part only: Alpine.start), and Main.server.luau defers
# World.buildLate (the terrain's fills, the forests) right after World.build, before the PLAY listener.
def alps_order_check():
    root = os.path.dirname(HERE)
    world = open(os.path.join(root, "src", "server", "World.luau"), encoding="utf-8").read()
    main = open(os.path.join(root, "src", "server", "Main.server.luau"), encoding="utf-8").read()
    bad = []
    start, late = world.find("function World.build()"), world.find("function World.buildLate()")
    build = world[start:late] if 0 <= start < late else ""
    light, alps = build.find('piece("lighting"'), build.find("Alpine).start(")
    if "Alpine).build(" in world:
        bad.append("World.luau builds all of the Alps at once (Alpine.build)")
    if light < 0 or alps < 0 or light > alps:
        bad.append("World.build: the lighting before the Alps' start")
    built, deferred, play = main.find("World.build()"), main.find("task.defer(World.buildLate)"), main.find('Net.get("Play").OnServerEvent')
    if min(built, deferred, play) < 0 or not built < deferred < play:
        bad.append("Main.server.luau: task.defer(World.buildLate) right after World.build(), before the PLAY listener")
    print("== alps order: " + ("the lighting before the Alps, their terrain and forests deferred past PLAY" if not bad else "; ".join(bad)))
    return not bad

if not alps_order_check():
    ok = False

# 8.0 SANDBOX: the HUD's city parts stay hidden in the sandbox (client/Hud.luau ── Sandbox ──, read as text: the HUD is
# Roblox's through and through) and the key hints show the move's keys and the car's only (client/KeyHints.luau
# sandboxLines). What the client starts there: tests/clientboot_test.luau.
def sandbox_hud_check():
    root = os.path.dirname(HERE)
    hud = open(os.path.join(root, "src", "client", "Hud.luau"), encoding="utf-8").read()
    bad = []
    at = hud.find("function view.sandbox()")
    body = hud[at:hud.index("\nend\n", at)] if at >= 0 else ""
    if not body:
        bad.append("client/Hud.luau has no view.sandbox")
    cash = re.search(r'local (\w+) = leftStack:FindFirstChild\("Cash"\)', body)
    if not cash or f"{cash.group(1)}.Visible = false" not in body or 'Name = "Cash"' not in hud:
        bad.append("view.sandbox does not hide the cash line (the money, the level, the XP bar)")
    for text, what in (('Hud.topSlot("job").Visible = false', "the NEXT card and the contract group (the job slot)"),
                       ("hudButtons.more.Visible = false", "PHONE / MENU"), ("view.menu.Visible = false", "MENU's list"),
                       ("weaponBar.Visible = false", "the weapon line"), ("fire.Visible = false", "FIRE"),
                       ("for _, button in view.touchHands do", "the touch hands"), ("LEFT_H = ", "the left column's room for the minimap")):
        if text not in body:
            bad.append(f"view.sandbox does not hide {what}")
    start = hud[hud.index("function Hud.start()"):]
    lines = start[:start.index("\nend\n")].split("\n")

    # Is the line holding `needle` inside an `if not Config.Sandbox.On then` (its nearest less indented line above)?
    def city_only(needle):
        for i, line in enumerate(lines):
            if needle in line:
                depth = len(line) - len(line.lstrip("\t"))
                for above in reversed(lines[:i]):
                    if above.strip() and not above.strip().startswith("--") and len(above) - len(above.lstrip("\t")) < depth:
                        return above.strip() == "if not Config.Sandbox.On then"
        return False
    for needle, what in (("Hotbar).start(gui)", "the bottom bar (the hands, the city's items)"), ("view.goal.start()", "the NEXT card's remotes"),
                         ("MapView.start(gui, leftStack)", "the minimap and the big map")):
        if not city_only(needle):
            bad.append(f"Hud.start starts {what} in the sandbox too")
    if not any(line.strip() == "view.sandbox()" for line in lines):
        bad.append("Hud.start never calls view.sandbox()")
    for text, what in (("fire.Visible = touch and not Config.Sandbox.On", "FIRE comes back every frame"),
                       ("touchHands.melee.Visible = not seatedNow and not holding and not Config.Sandbox.On", "PUNCH comes back"),
                       ("Holster.armed() and not Config.Sandbox.On", "DRAW comes back"),
                       ("view.goal.quiet() or Config.Sandbox.On)", "the job board's marker shows"),
                       ("if processed or Config.Sandbox.On then", "the keys J, M, I, Y and 1-9 work")):
        if text not in hud:
            bad.append(f"in the sandbox {what}")
    keys = open(os.path.join(root, "src", "client", "KeyHints.luau"), encoding="utf-8").read()
    at = keys.find("local function sandboxLines(")
    chips = re.findall(r'chipText\("([^"]+)", "([^"]+)"', keys[at:keys.index("\nend\n", at)]) if at >= 0 else []
    city = [f"[{key}] {word}" for key, word in chips if key not in ("W/S", "A/D", "H", "E", "G", "LMB/F", "O", "T", "LMB", "Q")]  # (8.5: Danny's clipboard, LMB and Q)
    if not chips or city or "if Config.Sandbox.On then\n\t\treturn sandboxLines(" not in keys:
        bad.append("KeyHints: the sandbox's keys are not the move's and the car's only" + (f" ({', '.join(city)})" if city else ""))
    print("== sandbox hud: " + (f"the HUD hides its city parts in the sandbox, the key hints show {len(chips)} move and car keys" if not bad else "; ".join(bad)))
    return not bad

if not sandbox_hud_check():
    ok = False

# 7.2 review: two server wirings the Luau tests cannot run. PlayerData.save writes the one-car flag into `rewards` too
# (an older server drops unknown fields but keeps that table's short keys: Economy.vanMigrated reads either mark), and
# the Tutorial remote's ("story", key) marks only a card's key (MoveStory.isCardKey): a chapter done is the server's.
def review72_check():
    root = os.path.dirname(HERE)
    data = open(os.path.join(root, "src", "server", "PlayerData.luau"), encoding="utf-8").read()
    tutorial = open(os.path.join(root, "src", "server", "Tutorial.luau"), encoding="utf-8").read()
    bad = []
    start = data.find("function PlayerData.save(")
    save = data[start:data.find("\nend\n", start)] if start >= 0 else ""
    if "profile.rewards[Config.CompanyVan.Flag] = true" not in save:
        bad.append("PlayerData.save: the one-car flag into rewards too")
    start = tutorial.find('if action == "story" then')
    story = tutorial[start:tutorial.find("return", start)] if start >= 0 else ""
    if "isCardKey(arg)" not in story or "PlayerData.markStory(player, arg)" not in story:
        bad.append("Tutorial: the story action marks only MoveStory.isCardKey keys")
    print("== 7.2 review: " + ("the one-car flag saved into rewards too; the client marks only story cards" if not bad else "; ".join(bad)))
    return not bad

if not review72_check():
    ok = False

# 8.0.2: the owner's Blender imports leave the Workspace before anything can yield (Import 3D leaves their parts loose:
# the sandbox builds no Marge's house, so ZDCHouseArt fell apart over the plots).
def imports_first_check():
    main = open(os.path.join(os.path.dirname(HERE), "src", "server", "Main.server.luau"), encoding="utf-8").read()
    names = ("ZDCFurnitureArt", "ZDCHouseArt", "ZDCVanArt", "ZDCSprinterArt", "ZDCWarehouseArt")
    first = main.find("ServerStorage")
    wait = main.find(":WaitForChild(")
    good = first >= 0 and wait >= 0 and first < wait and all(main.find(f'"{n}"') < wait for n in names)
    print("== imports first: " + ("the Blender imports leave the Workspace before the server waits for anything" if good else "Main.server must move the imports out of the Workspace first"))
    return good

if not imports_first_check():
    ok = False

# 8.1 SANDBOX, the upgrades: Danny's training is a one-line hook in server/MoveHelper.luau's walk (go: his speed ×
# MoveHelperBrain.trained of the move's owner; tests/upgrades_test.luau checks trained itself).
def upgrades_hooks_check():
    helper = open(os.path.join(os.path.dirname(HERE), "src", "server", "MoveHelper.luau"), encoding="utf-8").read()
    start = helper.find("local function go(")
    body = helper[start:helper.find("\nend\n", start)] if start >= 0 else ""
    good = "speed *= Brain.trained(h.s.owner)" in body
    print("== upgrades hooks: " + ("Danny walks × his training (MoveHelper's go)" if good else "server/MoveHelper.luau's go lost Danny's training (speed *= Brain.trained(h.s.owner))"))
    return good

if not upgrades_hooks_check():
    ok = False

# 8.3 SANDBOX: the gamepad's D-pad (← the STOCK list, → the book, ↓ the TASKS panel: Config's StockPad / Pad,
# shared/SandboxPad.luau) is free in the sandbox: no module the sandbox's client starts (client/Main.client.luau's
# sandbox block: what it requires, its own modules) reads a D-pad button itself, none of the city's D-pad users (the
# weapon wheel ↑, the phone ↓, the hands ← →) is started there, no prompt of the server's (GamepadKeyCode) is on the
# D-pad, and the three chips are on three different D-pad buttons, never ↑ (Roblox's emote wheel).
def pad_check():
    root = os.path.dirname(HERE)
    client = os.path.join(root, "src", "client")
    main = open(os.path.join(client, "Main.client.luau"), encoding="utf-8").read()
    start = main.index("if Config.Sandbox.On then")
    block = main[start:main.index("\nend\n", start)]
    started = set(re.findall(r"require\(Client\.(\w+)\)", block))
    own = re.search(r"for _, name in \{([^}]*)\} do", block)
    started |= set(re.findall(r'"(\w+)"', own.group(1))) if own else set()
    bad = []
    for name in sorted(started):
        path = os.path.join(client, name + ".luau")
        if os.path.exists(path) and re.search(r"KeyCode\.DPad\w+", open(path, encoding="utf-8").read()):
            bad.append(f"client/{name}.luau reads the D-pad")
    for city in ("Holster", "WeaponWheel", "Phone"):
        if city in started:
            bad.append(f"the sandbox starts {city} (a D-pad user of the city's)")
    for folder, _, files in os.walk(os.path.join(root, "src", "server")):
        for name in files:
            if name.endswith(".luau") and re.search(r"GamepadKeyCode\s*=\s*Enum\.KeyCode\.DPad", open(os.path.join(folder, name), encoding="utf-8").read()):
                bad.append(f"server/{name}: a prompt on the D-pad")
    config = open(os.path.join(root, "src", "shared", "Config.luau"), encoding="utf-8").read()
    pads = re.findall(r'^\t(?:StockPad|Pad) = "(\w+)"', config, re.M)
    if len(pads) != 3 or len(set(pads)) != 3 or any(not p.startswith("DPad") or p == "DPadUp" for p in pads):
        bad.append(f"the chips' pads {pads}: three different D-pad buttons, never DPadUp")
    print("== sandbox D-pad: " + (f"free for the chips ({', '.join(pads)}): none of the {len(started)} modules the sandbox starts reads it, no prompt on it" if not bad else "; ".join(bad)))
    return not bad

if not pad_check():
    ok = False

# 8.5.1: the server's and the client's BuildStamp equal Config.Version (they find a Studio left with old scripts).
def build_stamp_check():
    root = os.path.dirname(HERE)
    config = open(os.path.join(root, "src", "shared", "Config.luau"), encoding="utf-8").read()
    version = re.search(r'^Config\.Version = "([^"]+)"', config, re.M)
    bad = []
    for side in ("server", "client"):
        path = os.path.join(root, "src", side, "BuildStamp.luau")
        stamp = re.search(r'^return "([^"]+)"', open(path, encoding="utf-8").read(), re.M) if os.path.exists(path) else None
        if not version or not stamp or stamp.group(1) != version.group(1):
            bad.append(f"{side}/BuildStamp.luau is {stamp.group(1) if stamp else 'missing'}, Config.Version {version.group(1) if version else '?'}")
    print("== build stamps: " + (f"server and client at {version.group(1)}" if not bad else "; ".join(bad)))
    return not bad

if not build_stamp_check():
    ok = False

# 6.24: every require in src resolves to a ModuleScript where Rojo puts it (tools/check-requires.py: a module that
# moved, like 6.22's KitArt, or a typo shows here instead of as "X is not a valid member of Folder" in Studio).
requires = subprocess.run([sys.executable, os.path.join(os.path.dirname(HERE), "tools", "check-requires.py")], capture_output=True, text=True)
sys.stdout.write(requires.stdout + requires.stderr)
if requires.returncode != 0:
    ok = False

# 8.0 sandbox: the Sprinter in the owner's Blender model (server/SprinterMesh.luau): tools/sprinter/mesh-check.py imports
# design/blender-sprinter/roblox/ZDCSprinterArt.json's pieces (turned, scaled) and dresses sprinters built by the parts
# model's contract; the model's measured sizes are the contract's.
sprinter = subprocess.run([sys.executable, os.path.join(os.path.dirname(HERE), "tools", "sprinter", "mesh-check.py"), shutil.which(luau) or luau], capture_output=True, text=True)
print("== sprinter mesh: " + ((sprinter.stdout.strip().splitlines() or ["?"])[-1][:160] if sprinter.returncode == 0 else "FAIL\n" + sprinter.stdout[-1500:] + sprinter.stderr[-1500:]))
if sprinter.returncode != 0:
    ok = False

# 8.2 sandbox: the ZDC warehouse in the owner's Blender model (server/WarehouseMesh.luau): tools/warehouse/mesh-check.py
# imports design/blender-warehouse/roblox/ZDCWarehouseArt.json's pieces (turned, scaled) and dresses the warehouses the
# real server/Warehouse.luau builds; the model's sizes are the layout's, its visual parts hidden, the rest untouched.
warehouse = subprocess.run([sys.executable, os.path.join(os.path.dirname(HERE), "tools", "warehouse", "mesh-check.py"), shutil.which(luau) or luau], capture_output=True, text=True)
print("== warehouse mesh: " + ((warehouse.stdout.strip().splitlines() or ["?"])[-1][:160] if warehouse.returncode == 0 else "FAIL\n" + warehouse.stdout[-1500:] + warehouse.stderr[-1500:]))
if warehouse.returncode != 0:
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
