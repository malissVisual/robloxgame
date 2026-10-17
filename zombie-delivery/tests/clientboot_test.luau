--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md), the client's boot: the real client/Main.client.luau (tests/run_tests.py
-- copies it as ClientMain.luau, a function of the globals it reads) runs on recorders: every module it requires is a
-- stand-in that takes any field, call or assignment and writes the calls down. Checked:
--   * 10.5 (only the sandbox is the game): Config.Sandbox.On = false starts the sandbox all the same;
--   * the sandbox (On = true): only the sandbox's systems start, none of the city's is even required; the sandbox's
--     own modules (SandboxHud, WarehouseUi, SandboxGuide: other workers') start only when they are there, one that
--     fails to load or has no start is skipped; 8.1: SandboxSounds (the sandbox's sounds) starts last, with or without
--     them; PLAY still fires the server's Play; the State reaches SandboxHud.setState; ESC closes the warehouse's picker; the picker frees the mouse; 8.3: the server's notices go
--     through SandboxHud.notice (in this device's words) when it has one, else straight to the HUD's toasts; 8.3:
--     SandboxLight (the eyes) starts after SandboxSounds; 8.3 review: another window opening only hides a visitor's
--     offer card (OfferCard.hide), ESC declines it (OfferCard.close); 8.7: TradePrompts (the trade prompts on your own
--     stands hidden) right after CargoPrompts, TradeUi (trading between players) a window like the others, the STOCK
--     list's 🏷 opening its price picker and the picker going back to the list; 10.5: nothing of the driving starts
--     (nobody drives since 10.0: no Drive, no boarding, no pedals, no car's sway, tyres or crashes). Run with
--     tests/run_tests.py.

local Config = require("./Config")
local ClientMain = require("./ClientMain")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- The game's client: walking, the camera and the body, the vans, the sounds, the admin, the run's horde, the moves
-- (8.3 the walk-in doors' leaves and arrival: WalkDoors), the HUD and the key hints; then its own modules.
local SANDBOX = {
	"ZombieAnimator", "CarVisuals", "Hud", "CameraRig", "ArmPose", "AdminPanel", "AdminFly",
	"Sounds", "Stamina", "GaitPose", "BodyLife", "KeyHints", "Unstuck", "PerfOverlay",
	"EnemyOutline", "ZombieLife", "ZombieFx", "MovingHud", "MoveHelperHud", "DannyBubble",
	"QuickChat", "CarryGripUi", "WalkDoors", "CargoPrompts", "TradePrompts", -- (8.3: WalkDoors, the doors' leaves swing and the trip's camera; 8.6: DannyBubble, what Danny does over his head; 8.7: TradePrompts)
}
local OWN = { "SandboxHud", "WarehouseUi", "SandboxGuide", "UpgradeUi", "CollectionBookUi", "SandboxTasksUi", "MoveHelperCard", "DannyOrders", "OfferCard", "VanPaintUi", "TradeUi" } -- (8.7: TradeUi, trading between players; 8.1: UpgradeUi, the UPGRADES desk's window; 8.2: CollectionBookUi, the collection book; SandboxTasksUi, the TASKS chip and panel; 8.3: MoveHelperCard, Danny's card: his list (10.1 no hire); 8.5: DannyOrders, Danny's clipboard, orders mode; OfferCard, a visitor's offer; VanPaintUi, the PAINT shop's window)
local LAST = { "SandboxSounds", "SandboxLight" } -- 8.1: the sandbox's sounds, after its own modules (client/SandboxSounds.luau); 8.3: the eyes (client/SandboxLight.luau)

-- The city's systems the sandbox must never require (the phone, the board, the windows, the maps, the tutorial, the
-- buses, the rentals, the zips, the guns and the hands, the throw, the chips and banners, the leaderboard, the weather,
-- the traffic, the animals, 10.5 the driving ...).
local CITY_ONLY = {
	"Phone", "MissionsUi", "DispatchUi", "EstateUi", "BusinessUi", "GarageUi", "CareerUi", "Discovery", "TutorialUi",
	"LocationTag", "RoadEventUi", "BusRide", "BusMapBoard", "RentalUi", "ZipRide", "Throw", "GrindChips", "EventBanner",
	"JobThumbUi", "ReadyCheck", "Leaderboard", "Weather", "Shooting", "Holster", "WeaponWheel", "Secrets",
	"AnimalAnimator", "TrafficAnimator", "BagSway", "ShopPropMotion", "SpeedLines", "SavingsLine",
	"ShopWindow", "RegularsApp", "SpecialOrderUi", "JobStartCard", "MapView", "CrewPanel", "MoveLobbyUi",
	"Drive", "CarBoarding", "CurbRide", "CarSway", "TyreFx", "CrashFx", "DrivePedals", "MoveStoryUi",
}

type Run = {
	calls: { string },
	args: { [string]: { any } },
	required: { [string]: boolean },
	order: { string },
	warnings: { string },
	modules: { [string]: any },
}

-- A stand-in: any field is another stand-in (the same one each time), an assignment is kept, a call is written down
-- (its path, its arguments) and gives a stand-in named after its first string argument (Net.get("Play") …).
local function proxy(run: Run, path: string): any
	local fields: { [any]: any } = {}
	return setmetatable({}, {
		__index = function(_, key)
			local value = fields[key]
			if value == nil then
				value = proxy(run, path .. "." .. tostring(key))
				fields[key] = value
			end
			return value
		end,
		__newindex = function(_, key, value)
			fields[key] = value
		end,
		__call = function(_, ...)
			local args = { ... }
			table.insert(run.calls, path)
			run.args[path] = args
			local label = ""
			for _, a in args do
				if type(a) == "string" then
					label = a
					break
				end
			end
			return proxy(run, path .. "(" .. label .. ")")
		end,
	})
end

-- One run of the client's Main. `own`: the sandbox's own modules that are there ("ok": a table recording its start and
-- setState, "bare": no start, "error": it fails to load); `windows`: what the open-window checks say.
local function boot(sandbox: boolean, own: { [string]: string }, warehouseOpen: boolean?): Run
	local run: Run = { calls = {}, args = {}, required = {}, order = {}, warnings = {}, modules = {} }
	Config.Sandbox.On = sandbox
	-- the windows' checks: nothing open but (maybe) the warehouse's picker
	for _, name in { "Hud", "AdminPanel", "MovingHud", "QuickChat" } do
		local module = proxy(run, name)
		module[if name == "Hud" then "anyWindowOpen" else "isOpen"] = function()
			return false
		end
		if name == "Hud" then
			module.resultOpen = function()
				return false
			end
		end
		run.modules[name] = module
	end
	for name, kind in own do
		if kind == "ok" then
			run.modules[name] = {
				start = function()
					table.insert(run.calls, name .. ".start")
				end,
				setState = function(_state: any)
					table.insert(run.calls, name .. ".setState")
				end,
				isOpen = function()
					return warehouseOpen == true
				end,
				close = function()
					table.insert(run.calls, name .. ".close")
				end,
				hide = if name == "OfferCard" then function() -- (8.3 review: hidden, the offer still waiting)
					table.insert(run.calls, name .. ".hide")
				end else nil,
				notice = if name == "SandboxHud" then function(_text: any) -- (8.3: the notices in this device's words)
					table.insert(run.calls, "SandboxHud.notice")
				end else nil,
				openPrice = if name == "TradeUi" then function(_entry: any) -- (8.7: the STOCK list's 🏷)
					table.insert(run.calls, "TradeUi.openPrice")
				end else nil,
				openStock = if name == "WarehouseUi" then function() -- (8.7: back from the price picker)
					table.insert(run.calls, "WarehouseUi.openStock")
				end else nil,
			}
		elseif kind == "bare" then
			run.modules[name] = {}
		end
	end
	local function stub(name: string, kind: string): any
		return {
			Name = name,
			kind = kind,
			IsA = function(_self: any, class: string): boolean
				return class == "ModuleScript"
			end,
		}
	end
	local clientStubs: { [string]: any } = {}
	local Client = setmetatable({
		FindFirstChild = function(_self: any, name: string): any
			return if own[name] then stub(name, "client") else nil
		end,
	}, {
		__index = function(_, name: string)
			local s = clientStubs[name]
			if not s then
				s = stub(name, "client")
				clientStubs[name] = s
			end
			return s
		end,
	})
	local Shared = setmetatable({}, {
		__index = function(_, name: string)
			return stub(name, "shared")
		end,
	})
	local fakeRequire = function(target: any): any
		local name = target.Name
		if target.kind == "shared" then
			if name == "Config" then
				return Config
			end
			run.required["Shared." .. name] = true
			return proxy(run, name)
		end
		if not run.required[name] then
			run.required[name] = true
			table.insert(run.order, name)
		end
		if own[name] == "error" then
			error(`{name} is broken`)
		end
		local module = run.modules[name]
		if module == nil then
			module = proxy(run, name)
			run.modules[name] = module
		end
		return module
	end
	local game = {
		GetService = function(_self: any, service: string): any
			assert(service == "ReplicatedStorage", service)
			return {
				WaitForChild = function(_rs: any, child: string): any
					assert(child == "Shared", child)
					return Shared
				end,
			}
		end,
	}
	local task = {
		spawn = function(fn: any, ...)
			fn(...)
		end,
		defer = function(fn: any, ...)
			fn(...)
		end,
		delay = function() end,
		wait = function()
			return 0
		end,
	}
	local warn = function(...)
		local parts = {}
		for _, part in { ... } do
			table.insert(parts, tostring(part))
		end
		table.insert(run.warnings, table.concat(parts, " "))
	end
	local Enum = { CameraType = { Custom = "Custom" } }
	ClientMain({ Parent = Client }, game, { CurrentCamera = {} }, fakeRequire, task, warn, Enum)
	return run
end

-- What a run started, in order: X.start (X.preload) of a module.
local function starts(run: Run): { string }
	local out = {}
	for _, call in run.calls do
		local name = string.match(call, "^(%w+)%.start$")
		if name then
			table.insert(out, name)
		end
		local preload = string.match(call, "^(%w+)%.preload$")
		if preload then
			table.insert(out, preload .. ".preload")
		end
	end
	return out
end

local function same(a: { string }, b: { string }): (boolean, string?)
	for i = 1, math.max(#a, #b) do
		if a[i] ~= b[i] then
			return false, `#{i}: {a[i] or "-"} ≠ {b[i] or "-"}`
		end
	end
	return true, nil
end

local function called(run: Run, path: string): boolean
	return table.find(run.calls, path) ~= nil
end

local function concat(...: { string }): { string }
	local out = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end

-- ── 10.5: no city any more (Config.Sandbox.On = false) ─────────────────────

do
	local run = boot(false, { SandboxHud = "ok", WarehouseUi = "ok", SandboxGuide = "ok", UpgradeUi = "ok", CollectionBookUi = "ok", SandboxTasksUi = "ok", MoveHelperCard = "ok", DannyOrders = "ok", OfferCard = "ok", VanPaintUi = "ok", TradeUi = "ok" }, true)
	local ok, where = same(starts(run), concat(SANDBOX, OWN, LAST))
	check("10.5: Config.Sandbox.On false starts the sandbox all the same", ok, where)
end

-- ── The sandbox (Config.Sandbox.On = true) ──────────────────────────────────

do
	local run = boot(true, { SandboxHud = "ok", WarehouseUi = "ok", SandboxGuide = "ok", UpgradeUi = "ok", CollectionBookUi = "ok", SandboxTasksUi = "ok", MoveHelperCard = "ok", DannyOrders = "ok", OfferCard = "ok", VanPaintUi = "ok", TradeUi = "ok" }, true)
	local ok, where = same(starts(run), concat(SANDBOX, OWN, LAST))
	check(`the sandbox starts its {#SANDBOX} systems, then SandboxHud, WarehouseUi, SandboxGuide, UpgradeUi, CollectionBookUi, SandboxTasksUi, MoveHelperCard, DannyOrders, OfferCard, VanPaintUi, TradeUi, then SandboxSounds and SandboxLight`, ok, where)
	local city: { string } = {}
	for _, name in CITY_ONLY do
		if run.required[name] then
			table.insert(city, name)
		end
	end
	check("the sandbox never requires a city system (the phone, the board, the maps, the guns ...)", #city == 0, table.concat(city, ", "))
	local allowed: { [string]: boolean } = { Menu = true }
	for _, name in concat(SANDBOX, OWN, LAST) do
		allowed[name] = true
	end
	local extra: { string } = {}
	for _, name in run.order do
		if not allowed[name] then
			table.insert(extra, name)
		end
	end
	check("… nor anything but its own systems and the start screen", #extra == 0, table.concat(extra, ", "))
	check("the sandbox: no warnings", #run.warnings == 0, table.concat(run.warnings, " | "))

	-- PLAY: the HUD, the camera, the sounds, the server's Play.
	local show = run.args["Menu.show"]
	check("the start screen shows with PLAY", show ~= nil and type(show[1]) == "function")
	if show and type(show[1]) == "function" then
		show[1]()
	end
	check("PLAY fires the server's Play", called(run, "Net.get(Play).FireServer"))
	check("PLAY shows the HUD, gives the camera back and turns the game's sounds on", called(run, "Hud.setVisible") and called(run, "CameraRig.setEnabled") and called(run, "Sounds.setInGame"))
	check("the client asks for its State", called(run, "Net.get(RequestState).FireServer"))
	local connect = run.args["Net.get(State).OnClientEvent.Connect"]
	check("the State is listened to", connect ~= nil and type(connect[2]) == "function")
	if connect and type(connect[2]) == "function" then
		connect[2]({ money = 100 })
	end
	check("the State reaches SandboxHud.setState (10.5: the start screen reads none of it)", called(run, "SandboxHud.setState") and not called(run, "Menu.setState"))
	local notice = run.args["Net.get(Notice).OnClientEvent.Connect"]
	check("the server's notices go through SandboxHud.notice (8.3: in this device's words)", notice ~= nil and notice[2] == run.modules.SandboxHud.notice and type(notice[2]) == "function")
	check("toasts for the sounds", run.modules.Sounds.notify == run.modules.Hud.toast)
	local close = run.modules.Hud.onCloseWindows
	check("ESC has a sandbox's close", type(close) == "function")
	if type(close) == "function" then
		close()
	end
	check("ESC closes the move's cards, the quick chat and the warehouse's picker", called(run, "MovingHud.closeAll") and called(run, "QuickChat.close") and called(run, "WarehouseUi.close"))
	check("… and the UPGRADES window (8.1 review)", called(run, "UpgradeUi.close"))
	check("… and 8.3 Danny's card (his list, 10.1 no hire: a window like the others, with its onOpen)", called(run, "MoveHelperCard.close") and type(run.modules.MoveHelperCard.onOpen) == "function")
	check("… and 8.3 the PAINT shop's window (a window like the others, with its onOpen)", called(run, "VanPaintUi.close") and type(run.modules.VanPaintUi.onOpen) == "function")
	check("… and 8.3 a visitor's offer card (a window like the others, with its onOpen; it waits while the camera's windowOpen says another is open)", called(run, "OfferCard.close")
		and type(run.modules.OfferCard.onOpen) == "function" and run.modules.OfferCard.covered == run.modules.CameraRig.windowOpen)
	check("… and 8.7 trading between players (TradeUi: a window like the others, with its onOpen; the camera's windowOpen counts it)", called(run, "TradeUi.close")
		and type(run.modules.TradeUi.onOpen) == "function")
	check("8.7: the STOCK list's 🏷 opens TradeUi's price picker, which goes back to the STOCK list", run.modules.WarehouseUi.onPrice == run.modules.TradeUi.openPrice
		and type(run.modules.TradeUi.openPrice) == "function" and run.modules.TradeUi.onBack == run.modules.WarehouseUi.openStock and type(run.modules.WarehouseUi.openStock) == "function")
	check("8.5 Danny's clipboard (orders mode) is no window: ESC never closes it, no onOpen; it steps aside under the camera's windowOpen",
		not called(run, "DannyOrders.close") and type(run.modules.DannyOrders.onOpen) ~= "function" and run.modules.DannyOrders.covered == run.modules.CameraRig.windowOpen)
	-- 8.1 review: opening a sandbox window closes the others, never itself (its onOpen runs once it counts as open)
	local onOpen = run.modules.UpgradeUi.onOpen
	check("the UPGRADES window has an onOpen", type(onOpen) == "function" and type(run.modules.WarehouseUi.onOpen) == "function")
	if type(onOpen) == "function" then
		table.clear(run.calls)
		run.modules.Hud.closeWindows = close -- (the real Hud.closeWindows ends in Hud.onCloseWindows)
		onOpen()
		check("… which closes the picker but not itself", called(run, "WarehouseUi.close") and not called(run, "UpgradeUi.close"))
	end
	local windowOpen = run.modules.CameraRig.windowOpen
	check("the warehouse's open picker frees the mouse (CameraRig.windowOpen)", type(windowOpen) == "function" and windowOpen() == true)
	check("… and so does every window the camera's mouseNeeded asks about", run.modules.CameraRig.mouseNeeded == windowOpen)
	local covered = run.modules.KeyHints.covered
	check("the key hints hide under a window", type(covered) == "function" and covered() == true)
end

do
	local run = boot(true, { SandboxHud = "ok", WarehouseUi = "ok", SandboxGuide = "ok" }, false)
	check("with the picker shut the mouse stays the camera's", run.modules.CameraRig.windowOpen() == false)
end

do -- 8.1 review: the UPGRADES window alone frees the mouse too (on PC the camera no longer holds it)
	local run = boot(true, { UpgradeUi = "ok" }, true)
	check("the open UPGRADES window frees the mouse (CameraRig.windowOpen)", run.modules.CameraRig.windowOpen() == true)
end

do -- 8.3 Danny's card (his list; 10.1 no hire) alone: open, it frees the mouse (its buttons are clicked); it closes the other windows
	local run = boot(true, { MoveHelperCard = "ok", WarehouseUi = "ok" }, true)
	check("8.3 Danny's open card frees the mouse (CameraRig.windowOpen)", run.modules.CameraRig.windowOpen() == true)
	local onOpen = run.modules.MoveHelperCard.onOpen
	if type(onOpen) == "function" then
		table.clear(run.calls)
		run.modules.Hud.closeWindows = run.modules.Hud.onCloseWindows
		onOpen()
	end
	check("… opening it closes the picker but not itself", type(onOpen) == "function" and called(run, "WarehouseUi.close") and not called(run, "MoveHelperCard.close"))
end

do -- 8.3 a visitor's offer card alone: open, it frees the mouse (ACCEPT / DECLINE are clicked); it closes the other windows
	local run = boot(true, { OfferCard = "ok", WarehouseUi = "ok" }, true)
	check("8.3 the open offer card frees the mouse (CameraRig.windowOpen)", run.modules.CameraRig.windowOpen() == true)
	local onOpen = run.modules.OfferCard.onOpen
	if type(onOpen) == "function" then
		table.clear(run.calls)
		run.modules.Hud.closeWindows = run.modules.Hud.onCloseWindows
		onOpen()
	end
	check("… opening it closes the picker but not itself", type(onOpen) == "function" and called(run, "WarehouseUi.close") and not called(run, "OfferCard.close"))
	-- 8.3 review: another window opening (no escape) only hides the offer, which keeps waiting; ESC declines it
	local close = run.modules.Hud.onCloseWindows
	run.modules.Hud.escaping = false
	table.clear(run.calls)
	close()
	check("8.3 review: another window opening (Hud.escaping false) only hides the offer card (OfferCard.hide: it waits), no DECLINE",
		called(run, "OfferCard.hide") and not called(run, "OfferCard.close") and called(run, "WarehouseUi.close"))
	run.modules.Hud.escaping = true
	table.clear(run.calls)
	close()
	check("… ESC or the Roblox menu (Hud.escaping) closes it: a DECLINE (OfferCard.close)", called(run, "OfferCard.close") and not called(run, "OfferCard.hide"))
end

do -- 8.3 the PAINT shop's window alone: open, it frees the mouse (its swatches are clicked); it closes the other windows
	local run = boot(true, { VanPaintUi = "ok", UpgradeUi = "ok" }, true)
	check("8.3 the open PAINT shop window frees the mouse (CameraRig.windowOpen)", run.modules.CameraRig.windowOpen() == true)
	local onOpen = run.modules.VanPaintUi.onOpen
	if type(onOpen) == "function" then
		table.clear(run.calls)
		run.modules.Hud.closeWindows = run.modules.Hud.onCloseWindows
		onOpen()
	end
	check("… opening it closes the UPGRADES window but not itself", type(onOpen) == "function" and called(run, "UpgradeUi.close") and not called(run, "VanPaintUi.close"))
end

do -- 8.8 the Auction House's window alone (a window like the others): open, it frees the mouse; it closes the others
	local run = boot(true, { AuctionUi = "ok", VanPaintUi = "ok" }, true)
	check("8.8 the Auction House's window starts with the sandbox's own modules, and frees the mouse while open", called(run, "AuctionUi.start") and run.modules.CameraRig.windowOpen() == true)
	local onOpen = run.modules.AuctionUi.onOpen
	if type(onOpen) == "function" then
		table.clear(run.calls)
		run.modules.Hud.closeWindows = run.modules.Hud.onCloseWindows
		onOpen()
	end
	check("… opening it closes the PAINT shop's window but not itself", type(onOpen) == "function" and called(run, "VanPaintUi.close") and not called(run, "AuctionUi.close"))
	run.modules.Hud.onCloseWindows()
	check("… ESC (the HUD's close) closes it like the others", called(run, "AuctionUi.close"))
end

do -- 10.1 the CREW window (CrewUi): one of the sandbox's own modules, a window like the others; never in the city
	local alone = boot(true, { CrewUi = "ok" }, true)
	check("10.1 the CREW window (CrewUi) starts with the sandbox's own modules", called(alone, "CrewUi.start"))
	check("… open, it frees the mouse (CameraRig.windowOpen counts it)", alone.modules.CameraRig.windowOpen() == true)
	local run = boot(true, { CrewUi = "ok", WarehouseUi = "ok" }, true)
	local onOpen = run.modules.CrewUi.onOpen
	if type(onOpen) == "function" then
		table.clear(run.calls)
		run.modules.Hud.closeWindows = run.modules.Hud.onCloseWindows
		onOpen()
	end
	check("… opening it closes the other windows (the picker) but not itself", type(onOpen) == "function" and called(run, "WarehouseUi.close") and not called(run, "CrewUi.close"))
	local shut = boot(true, { CrewUi = "ok" }, false)
	check("… shut: the mouse stays the camera's", shut.modules.CameraRig.windowOpen() == false)
	table.clear(shut.calls)
	shut.modules.Hud.onCloseWindows()
	check("… ESC closes it", called(shut, "CrewUi.close"))
end

do -- 9.x loot: the outlines and the stars start with the sandbox's own modules; the stars step aside under a window
	local run = boot(true, { LootOutline = "ok", LootStars = "ok", WarehouseUi = "ok" }, true)
	check("9.x loot: the outlines (LootOutline) and the stars (LootStars) start with the sandbox's own modules", called(run, "LootOutline.start") and called(run, "LootStars.start"))
	local covered = run.modules.LootStars.covered
	check("… the stars with Main's covered check (a window open: none)", covered == run.modules.CameraRig.windowOpen)
end

do -- 10.x the map: the big map (a window like the others) and a run's minimap start with the sandbox's own modules
	local run = boot(true, { SandboxMapUi = "ok", SandboxMiniMap = "ok", VanPaintUi = "ok" }, true)
	check("10.x the map: the big map (SandboxMapUi) and the minimap (SandboxMiniMap) start with the sandbox's own modules",
		called(run, "SandboxMapUi.start") and called(run, "SandboxMiniMap.start"))
	check("… the open big map frees the mouse (CameraRig.windowOpen)", run.modules.CameraRig.windowOpen() == true)
	local onOpen = run.modules.SandboxMapUi.onOpen
	if type(onOpen) == "function" then
		table.clear(run.calls)
		run.modules.Hud.closeWindows = run.modules.Hud.onCloseWindows
		onOpen()
	end
	check("… opening it closes the PAINT shop's window but not itself", type(onOpen) == "function" and called(run, "VanPaintUi.close") and not called(run, "SandboxMapUi.close"))
	run.modules.Hud.onCloseWindows()
	check("… ESC (the HUD's close) closes it like the others", called(run, "SandboxMapUi.close"))
	check("… the minimap with Main's covered check (a window open, the big map too: none)", run.modules.SandboxMiniMap.covered == run.modules.CameraRig.windowOpen)
	local alone = boot(true, { SandboxMapUi = "ok" }, false)
	check("… the big map shut: the mouse stays the camera's", alone.modules.CameraRig.windowOpen() == false)
end

do -- none of the sandbox's own modules there yet (the other workers' branches not merged)
	local run = boot(true, {})
	local ok, where = same(starts(run), concat(SANDBOX, LAST))
	check("without its own modules the sandbox starts the rest (its sounds and its eyes too)", ok, where)
	check("… with no warnings", #run.warnings == 0, table.concat(run.warnings, " | "))
	local close = run.modules.Hud.onCloseWindows
	local fine = pcall(close)
	check("… ESC still works", fine)
	check("… nothing frees the mouse", run.modules.CameraRig.windowOpen() == false)
	local connect = run.args["Net.get(State).OnClientEvent.Connect"]
	check("… the State does no harm", pcall(connect[2], { money = 5 }))
	local notice = run.args["Net.get(Notice).OnClientEvent.Connect"]
	check("… the server's notices are the HUD's toasts", notice ~= nil and notice[2] == run.modules.Hud.toast)
end

do -- one that fails to load, one without a start
	local run = boot(true, { SandboxHud = "error", WarehouseUi = "bare", SandboxGuide = "ok" })
	local ok, where = same(starts(run), concat(SANDBOX, { "SandboxGuide" }, LAST))
	check("a broken own module is skipped, one without start is left alone, the others start", ok, where)
	check("… the broken one says so in the Output", #run.warnings == 1 and string.find(run.warnings[1], "SandboxHud", 1, true) ~= nil, table.concat(run.warnings, " | "))
end

Config.Sandbox.On = true

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
