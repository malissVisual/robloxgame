-- 8.2 e2e: the whole SANDBOX loop with the REAL modules together, for two players at once (and three more at the end).
-- tests/run_tests.py stages the real server modules SandboxE2E lists in E.real (SandboxBoot, SandboxWorld, HouseMesh,
-- PlayerData, SandboxPlots, Collection, CollectionBook, Warehouse with WarehouseMesh, Upgrades, SandboxTasks, SandboxLeaders,
-- Analytics, SandboxAnalytics, Moving with MoveLobby, MoveHelper, MoveGreeters, PairHold and MoveSites, HouseInterior,
-- FurnitureMesh; 9.7 LobbyWorld and Runs) and
-- shared/Net.luau on tests/runtime/SandboxE2E.luau's Roblox stand-in: only Roblox (its services, AnalyticsService
-- recorded) and the physics-heavy modules (Vehicles, Zombies, Npcs, Crew, Hand) are mocked; see its header. The clock is
-- the test's: the modules' own loops run (the moves' tick, the doors, Danny, the pads, the payouts, the tasks, the
-- autosave). 9.7 RUNS: the lobby → a portal's pad → the run in the house → loaded → FINISH → the stock, all of it real.
--   0. The real boot (SandboxBoot.start): the map, the services, the plots, the warehouses, the moves, 9.7 the lobby
--      (its six portals, their pads and signs, the ZDC dispatch, the PAINT shop's booth) and the runs; no kiosk on the
--      plots; no Baseplate.
--   1. Ann and Bob join: plots 1 and 2, a new sandbox save each ($500), their warehouses' signs, the states; 8.3: their
--      warehouses are garages (level 1: 2 stands); 9.7 both in the lobby's plaza.
--   2. PLAY: 9.7 no van in the lobby (the truck waits at a run's house; CAR says so).
--   3. 9.7 the portals: Ann onto the farmstead's pad (the pad panel: she the host, the countdown, Easy and Normal open,
--      Hard locked), her pick; the countdown over: her run (her truck parked at the curb, locked, she faded over to the
--      house's front yard, the portal IN USE), Danny for hire. Bob onto the farmstead's pad: IN USE; onto the Pond
--      Cabin's: his own run at the same time. 8.8 no roles: none on the move; the van's Loads hold no time (step 6).
--   4. The truck at the chalet's curb, the back doors open, the front door's walk-in zone: the dwell, the fade, inside
--      (8.3: the chalet's leaves open before the fade, the move FadeOut + Margin s after it, the arrival a step past the
--      door facing in, the leaves shut again Shut s later). 8.5 walking through: from 14 studs out on through the door
--      without a stop (no dwell): the way in clear of anything that collides (the House box no more), the leaf fully
--      open before she reached the doorway, the fade out as her root crossed its threshold while she walked on, the move
--      before her walk reached the end of its dark hall; the chalet's doorways walkable (HouseSolid, the halls' lining).
--   5. A sturdy two-hands piece through the grip lift check: a crew mate's answer does nothing, a forged "ok" is a miss
--      (a knock), the client's "ok" with a good press time lifts it balanced; a wobble answered (steady), one missed (a
--      stagger).
--   6. Out through the doorway, loaded at the back doors; a one-hand piece loaded from inside the walk-in bay. 8.5: out by
--      walking on through the doorway inside with the piece (the fade as she crossed its threshold, the way onto the
--      porch clear, the move before its wall of daylight).
--   7. 9.7 FINISH at the truck (the host's prompt): everything in it into HER stock at once (Collection.add: item,
--      variant, condition, name: the very look the piece had), into the book; the results card (the pieces, their
--      rarity, who got them, the value), Hard unlocked; EndHold s later back in the lobby by the portal, the truck gone.
--      A second run (the house refilled): one more piece. Bob: a death mid-carry, the respawn by his truck, his FINISH.
--   8. The warehouse: Display opens the picker, the client's display, the stand's model and tag; a move to another
--      stand, Take down; the refusals (a stand you haven't got, junk, a taken stand, another player's piece).
--   9. 60 s on the clock: the income (CollectionIncome). The player list's $ / $/min / collection, the TOP MOVERS board.
--  10. UPGRADES: More stands locked in the garage, the ZDC Warehouse without the money refused; 8.3: the warehouse
--      bought to the Big Warehouse (each level a rebuild, her pieces kept on their stands, the new desk's prompt); More
--      stands (14), the new stand 13 shows a piece; Showroom lights (× 1.1).
--  11. Sell at the stand (hold F); the bulk buttons: TAKE ALL DOWN, SELL… (duplicates; nothing else to sell), FILL BEST.
--  12. The runs' ends: the daily tasks counted the trips home, the sales and the income (a done one claimed); the
--      analytics' funnel steps fired once each, the moves' events.
--  13. Ann leaves and comes back: the collection on its stands, the upgrades, the book, the tasks, every dollar, 9.7 her
--      runs' unlocks; no van in the lobby (CAR says so); the engine bought (her next truck wears it: step 20); Danny's
--      training; 8.3: her warehouse level kept, then the Logistics Center (level 5) with every piece still on its stand.
--  14. Bob cannot use Ann's stands or desk; 9.7 his own run from a pad, GIVE UP with nothing loaded.
--  14b. 8.7 trading between players: at Ann's stand Bob has Make an offer (tagged for client/TradePrompts.luau: hidden
--      from her), its composer, his offer on her card, her ACCEPT: the money and the piece moved (the fee gone), the
--      stand free; Ann's Set price (her FOR SALE sign on the tag for everybody), Bob's Buy $X, its question, BUY.
--  15. A full server: the fifth player waits for a plot (9.7: in the plaza; a run refused: no warehouse), gets Bob's
--      when he leaves.
--  16. A full warehouse at a run's end.
--  17. Leaving mid-run with a piece in the truck: the run ends, the piece home in her save; coming back. Last: the
--      all-time best in its OrderedDataStore.
--  18. 8.3 the market: the state carries the day's hot and cold kinds; a hot piece on a stand: its tag shows the hot
--      income (Warehouse's hook), sold at the stand for the hot price, the analytics' "hot". Every price and income the
--      steps above expect is the market's (CollectionRules / StockPlan with Collection.market): any day passes.
--  19. 8.3 the PAINT shop: 9.7 the lobby's booth (no van needed), the window, a paint bought, worn by the truck of her
--      next run.
--  20. 8.3 the big move: 9.7 Ann's run at Hard (opened by her first run, kept in her save across her leave), the big
--      plan (Config.Furniture.Big), round the house to its back door, in by it, a piece out by its doorway inside (the
--      real plan's second way out), loaded, FINISH: Insane opened. 8.3 walk-in doors: the back door's leaves (the map's,
--      the interior's) swing open as she walks up to them, the fade as the front door's. 8.5: in and out by the back
--      door walking through it without a stop, as by the front door.
--  21. 9.7 a party run: four onto a pad one after the other (the first the host; Hard refused to her, a non-host's
--      pick nothing; she steps off: the next one the host, the countdown going on; back on: last in the line), a fifth
--      waits (MaxParty 4; IN USE for her); the party in the house's front yard, the host's truck; three of them load a
--      piece each, one LEAVEs THE RUN alone (back to the lobby, her piece still counts), the others vote: the end, each
--      piece in its loader's stock, a results card for everybody, Hard opened for the host (not for the one who left).
--  22. 9.7 the clock runs out: the run ends late by itself, the truck's load home, the next difficulty opened.
--  23. 9.7 the host leaves the game mid-run: the run ends for the party, each piece home to its loader.
-- A real bug found here keeps its check as TODO(bug) (printed, not counted): see the report with this commit.
math.randomseed(8202) -- (the houses' seeds, the grip checks' zones, the analytics' sampling: the same run every time)

local E = require("./SandboxE2E")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local CarryGrip = require("./CarryGrip")
local CollectionRules = require("./CollectionRules")
local WarehouseLayout = require("./WarehouseLayout")
local FurnitureLooks = require("./FurnitureLooks")
local SprinterLooks = require("./SprinterLooks")
local TaskRules = require("./SandboxTasks") -- (shared/SandboxTasks.luau, the pure rules)
local Plan = require("./AnalyticsPlan")
local StockPlan = require("./StockPlan")
local Market = require("./Market") -- (8.3: the day's hot and cold kinds)
local SoundPlan = require("./SoundPlan") -- (8.3: "in the house" for the eyes and the sounds)
-- 10.x danger: the runs' hazards are tests/danger_test.luau's and tests/danger_runtime_test.luau's: none on this loop's
-- straight walks (a creaky patch under a carried piece drops it, the plaster knocks it); its locks, vault and zombies
-- stay (H.choose leaves their pieces be)
for _, level in Config.Runs.Danger do
	level.Creak, level.Puddle, level.Plaster = 0, 0, 0
end

local failures = 0
local todos: { string } = {}
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
-- A check that a known bug fails today (TODO(bug)): printed, kept, not counted; it says so when the bug is gone.
local function todo(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name .. "  (TODO(bug) passes now: make it a check)")
	else
		table.insert(todos, name)
		print("TODO(bug) " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local V3 = E.Mock.Vector3.new
local workspace = E.workspace
local House = SandboxMap.House
local plots = SandboxMap.Plots
local H: any = {} -- the test's helpers (one register: the -O0 limit counts the chunk's locals)
local S: any = {} -- what one step leaves for the next

-- ── The boot ──────────────────────────────────────────────────────────────

-- the day: one whose daily tasks for Ann (UserId 11) hold "trips" (2) and "sell" and whose weekly is "w_income" (the
-- picks are seeded by the day and the UserId), at noon UTC
do
	local first = TaskRules.dayOf(E.wall)
	local chosen: number? = nil
	for score = 3, 1, -1 do
		for day = first, first + 3000 do
			local saved = TaskRules.fresh(11, day * 86400 + 43200, { offer = true }) -- (8.3: the visitors are off here: never their task)
			local has: { [string]: number } = {}
			for _, slot in saved.daily do
				has[slot.id] = slot.target
			end
			local got = (if has.trips == 2 then 1 else 0) + (if has.sell then 1 else 0) + (if saved.weekly and saved.weekly.id == "w_income" then 1 else 0)
			if got >= score and has.trips ~= nil then
				chosen = day
				break
			end
		end
		if chosen then
			break
		end
	end
	E.wall = (chosen or first) * 86400 + 43200
	S.day = chosen
end

local baseplate = E.Mock.Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Parent = workspace
local Boot = E.module("SandboxBoot")
local PlayerData = E.module("PlayerData")
local Collection = E.module("Collection")
local Book = E.module("CollectionBook")
local Warehouse = E.module("Warehouse")
local Upgrades = E.module("Upgrades")
local Tasks = E.module("SandboxTasks")
local Moving = E.module("Moving")
local MoveHelper = E.module("MoveHelper")
local SandboxPlots = E.module("SandboxPlots")
local Vehicles = E.fakes.Vehicles
H.Runs = E.module("Runs") -- 9.7: the runs (the portals' pads, the parties)
H.Danger = E.module("RunDanger") -- 10.x: a run's danger (its vault's sealed pieces, its locked rooms: tests/danger_*_test.luau)
MoveHelper.useMover(E.mover) -- (no pathfinding in the CLI: Danny walks straight)

local queued: { any } = {}
Config.Visitors.On = false -- (8.3: the showroom's visitors off here: tests/visitors_runtime_test.luau drives them)
Boot.start(function(player: any)
	table.insert(queued, player)
end)
E.advance(1)
-- every money change (PlayerData.onMoney: Analytics' hook, SandboxAnalytics' wrap, and this record after them)
local money: { { player: any, delta: number, reason: string?, sku: string? } } = {}
do
	local before = PlayerData.onMoney
	PlayerData.onMoney = function(player: any, delta: number, reason: string?, sku: string?)
		table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
		if before then
			before(player, delta, reason, sku)
		end
	end
end
function H.paid(player: any, reason: string, from: number?): number
	local sum = 0
	for index = (from or 0) + 1, #money do
		local m = money[index]
		if m.player == player and m.reason == reason then
			sum += m.delta
		end
	end
	return sum
end

do
	local started = false
	for _, line in E.printed do
		started = started or string.find(line, "SANDBOX is running", 1, true) ~= nil
	end
	local failed = {}
	for _, line in E.warnings do
		if string.find(line, "failed to start", 1, true) or string.find(line, "not in this build", 1, true) then
			table.insert(failed, line)
		end
	end
	check("0. the real boot: every service started (no \"failed to start\", no module missing)", started and #failed == 0 and #E.errors == 0,
		table.concat(failed, " | ") .. table.concat(E.errors, " | "))
	local moves = workspace:FindFirstChild("Moves")
	local warehouses = workspace:FindFirstChild("Warehouses")
	check("…the map (workspace.Sandbox), the four warehouses, the Cars folder; 9.7 no kiosk on the plots; no Baseplate", workspace:FindFirstChild("Sandbox") ~= nil
		and warehouses ~= nil and #warehouses:GetChildren() == 4 and moves ~= nil and moves:FindFirstChild("MovingBoard1") == nil
		and moves:FindFirstChild("MovingBoard4") == nil and workspace:FindFirstChild("Cars") ~= nil and rawget(baseplate, "destroyed") == true)
	local lobby = workspace:FindFirstChild("Sandbox"):FindFirstChild("Lobby")
	local portals = lobby and lobby:FindFirstChild("Portals")
	local portalsOk = portals ~= nil and #portals:GetChildren() == #SandboxMap.Lobby.portals
	for _, portal in SandboxMap.Lobby.portals do
		local model = portals and portals:FindFirstChild(`Portal_{portal.house}`)
		local pad = model and model:FindFirstChild("RunPad")
		local sign = model and model:FindFirstChild("GateSign")
		local words = sign and sign:FindFirstChild("Words")
		local line = words and words:FindFirstChild("Status")
		local status = if line then line.Text else ""
		local title = words and words:FindFirstChild("Title")
		portalsOk = portalsOk and model ~= nil and model:GetAttribute("RunPortal") == portal.house and pad ~= nil and pad:GetAttribute("RunPad") == portal.house
			and pad.CanCollide == false and status == "WALK ONTO THE PAD" and title ~= nil and title.Text == string.upper(portal.name)
	end
	check("9.7 …the lobby (workspace.Sandbox.Lobby, Persistent): six portals, each its house's (RunPortal), its glowing pad (RunPad, no collision), its sign (its name, WALK ONTO THE PAD)",
		lobby ~= nil and lobby.ModelStreamingMode == E.Mock.Enum.ModelStreamingMode.Persistent and portalsOk)
	local dispatch: any = nil
	for _, d in lobby:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.Name == "DispatchPrompt" then
			dispatch = d
		end
	end
	check("9.7 …the ZDC dispatch kiosk on the plaza, its \"How runs work\" (server/Runs.luau's)", dispatch ~= nil and dispatch.ActionText == "How runs work"
		and dispatch.Parent:GetAttribute("RunDispatch") == true)
	local door, back: any, any = nil, nil
	local farmstead = workspace:FindFirstChild("Sandbox"):FindFirstChild("TheOldFarmstead") -- (six houses: the stand-ins have doors of their own)
	for _, d in farmstead:GetDescendants() do
		if d:GetAttribute("SandboxDoor") then
			door = d
		elseif d:GetAttribute("SandboxBackDoor") then
			back = d
		end
	end
	check("…8.3: the chalet's back door (SandboxBackDoor) in its back wall where SandboxMap puts it", back ~= nil
		and V3(back.Position.X - House.back.x, 0, back.Position.Z - House.back.z).Magnitude < 1)
	check("…the chalet's front door (SandboxDoor) where SandboxMap puts it", door ~= nil and V3(door.Position.X - House.door.x, 0, door.Position.Z - House.door.z).Magnitude < 2)
	-- 8.3 walk-in doors: the chalet's doors' leaves (server/SandboxWorld.luau doorLeaves: no import here, its own)
	local leaves: { [string]: any } = {}
	for _, d in farmstead:GetDescendants() do
		if d:GetAttribute("DoorLeaf") ~= nil and (d.Name == "FrontLeafWest" or d.Name == "FrontLeafEast" or d.Name == "BackLeaf") then
			leaves[d.Name] = d
		end
	end
	local leavesOk = true
	for name, hinge in { FrontLeafWest = -1, FrontLeafEast = 1, BackLeaf = -1 } do
		local leaf = leaves[name]
		local by = if name == "BackLeaf" then back else door
		leavesOk = leavesOk and leaf ~= nil and by ~= nil and leaf:GetAttribute("DoorLeaf") == hinge and leaf:GetAttribute("DoorSwing") == -1
			and leaf:GetAttribute("DoorDark") == true and leaf.CanCollide == false and V3(leaf.Position.X - by.Position.X, 0, leaf.Position.Z - by.Position.Z).Magnitude < 2
	end
	S.frontDoor = door
	S.frontLeaf, S.backLeaf = leaves.FrontLeafEast, leaves.BackLeaf
	check("8.3 …the doors' leaves door leaves (FrontLeafWest, FrontLeafEast, BackLeaf: DoorLeaf -1 / 1 / -1 at their jambs; 8.5 DoorSwing -1: out of the house; DoorDark: a dark doorway behind them), never colliding",
		leavesOk and door ~= nil and door.CanCollide == false and door:GetAttribute("DoorLeaf") == nil)
	-- 8.5 walking through: the chalet's House box no longer what you bump into (its HouseSolid pieces, the box less a hall
	-- behind each doorway, collide instead), the halls lined dark
	local box, solids, lining = nil :: any, 0, 0
	for _, d in farmstead:GetDescendants() do
		if d.Name == "House" and d:IsA("BasePart") and d.Parent and d.Parent.Name == "House_" .. House.id then
			box = d
		elseif d.Name == "HouseSolid" and d.CanCollide then
			solids += 1
		elseif d.Name == "DoorHall" and not d.CanCollide then
			lining += 1
		end
	end
	check("8.5 …the chalet's doorways walkable: its House box collides with nothing (7 HouseSolid pieces do, the box less its two doors' halls), each hall lined dark",
		box ~= nil and box.CanCollide == false and box.CanQuery == false and solids == 7 and lining == 10, `{solids} {lining}`)
	check("…the sandbox's own DataStore (Config.Sandbox.Store); analytics on (a live server)", E.storeName == Config.Sandbox.Store and Config.Analytics.Enabled)
	check("(a day whose tasks for Ann hold trips, sell and the weekly income)", S.day ~= nil)
end

-- ── The helpers ───────────────────────────────────────────────────────────

function H.flat(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
function H.yawLook(yaw: number): any
	local r = math.rad(yaw)
	return V3(-math.sin(r), 0, -math.cos(r))
end
function H.textsOf(model: any): { string }
	local list = {}
	for _, d in model:GetDescendants() do
		if d.ClassName == "TextLabel" and type(d.Text) == "string" and d.Text ~= "" then
			table.insert(list, d.Text)
		end
	end
	return list
end
function H.anyText(model: any, word: string): boolean
	for _, text in H.textsOf(model) do
		if string.find(text, word, 1, true) then
			return true
		end
	end
	return false
end
function H.profileOf(player: any): any
	return PlayerData.get(player)
end
function H.groundAt(at: any): any
	return V3(at.X, E.groundY(at.X, at.Z) + 3, at.Z)
end
function H.entryFor(entries: { any }, item: string): any
	for _, entry in entries do
		if entry.item == item then
			return entry
		end
	end
	return nil
end
function H.byUid(entries: { any }, uid: string): any
	for _, entry in entries do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end
-- Roblox's AnalyticsService calls (the real server/Analytics.luau's): custom events by name, the onboarding steps.
function H.events(name: string, player: any?): { any }
	local out = {}
	for _, call in E.analytics do
		if call.method == "LogCustomEvent" and call.args[2] == name and (player == nil or call.args[1] == player) then
			table.insert(out, call.args)
		end
	end
	return out
end
function H.steps(userId: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, call in E.analytics do
		if call.method == "LogOnboardingFunnelStepEvent" and call.args[1].UserId == userId then
			out[call.args[3]] = (out[call.args[3]] or 0) + 1
		end
	end
	return out
end
-- The player's daily tasks now (the real server's view) and one row by its id ("trips", "sell", "w_income" …).
function H.task(player: any, id: string): any
	local view = Tasks.state(player)
	if not view then
		return nil
	end
	for _, row in view.daily do
		if row.id == id then
			return row
		end
	end
	return if view.weekly and view.weekly.id == id then view.weekly else nil
end

-- The client: answers its grip checks with a good press (when `auto`), like client/CarryGripUi.luau's press: at the
-- zone's middle by its own clock, the answer arriving a ping (E.ping, the players' GetNetworkPing) later.
S.auto = {}
function H.client(player: any): (string, ...any) -> ()
	return function(remote: string, kind: any, what: any, payload: any)
		if remote == "Moving" and kind == "grip" and what == "open" and S.auto[player] then
			local gripCheck = CarryGrip.fromWire(payload)
			if not gripCheck then
				return
			end
			local press = CarryGrip.firstHit(gripCheck)
			local id = payload.id
			E.task.delay(press + E.ping, function() -- (pressed at `press` by its clock; the answer reaches the server a ping later)
				if player.Parent then
					E.fire(player, "Moving", "grip", id, "ok", press)
				end
			end)
		end
	end
end
function H.doorOf(van: any): any
	return van.chassis:FindFirstChild("CargoDoor")
end
function H.stateOf(player: any): any
	E.fire(player, "Moving", "state")
	local last = E.lastOf(player, "Moving", "state")
	return last and last[2]
end
function H.itemOf(player: any, spot: number): any
	for _, item in (H.stateOf(player) or { items = {} }).items do
		if item.spot == spot then
			return item
		end
	end
	return nil
end
-- six houses: the house of `player`'s move (its state's contract, a SandboxMap.Houses id).
function H.houseOf(player: any): any
	local view = H.stateOf(player)
	return SandboxMap.house(view and view.contract) or House
end
-- 9.7 runs: the middle of a house's portal's pad in the lobby (SandboxMap.Lobby.portals), a root's height up.
function H.padAt(house: string): any
	local pad = (SandboxMap.portal(house) :: any).pad
	return H.groundAt(V3((pad.x0 + pad.x1) / 2, 0, (pad.z0 + pad.z1) / 2))
end
-- The portal's sign's status line (its SurfaceGui "Words": server/Runs.luau paints it) and its pad.
function H.portal(house: string): (string, any)
	local model = workspace:FindFirstChild("Sandbox"):FindFirstChild("Lobby"):FindFirstChild("Portals"):FindFirstChild(`Portal_{house}`)
	local sign = model and model:FindFirstChild("GateSign")
	local words = sign and sign:FindFirstChild("Words")
	local status = words and words:FindFirstChild("Status")
	return if status then status.Text else "", model and model:FindFirstChild("RunPad")
end
-- `players` walk onto `house`'s pad one after the other (the first its host, picking `difficulty`), the countdown runs
-- out: the run, the party faded over to the house's front yard. → the run (Runs.runOf) or nil.
function H.run(players: { any }, house: string, difficulty: string?): any
	for _, p in players do
		E.walk(p, H.padAt(house))
	end
	E.advance(Config.Runs.Every + 0.05)
	if difficulty then
		E.advance(0.3) -- (the Runs remote's rate limit)
		E.fire(players[1], "Runs", { kind = "difficulty", id = difficulty })
	end
	local started = E.waitUntil(function(): boolean
		return H.Runs.runOf(players[1]) ~= nil
	end, Config.Runs.Countdown + 1)
	E.advance(Config.Runs.Fade.Out + 0.3) -- (the jump: the fade out, then over)
	return if started then H.Runs.runOf(players[1]) else nil
end
-- The host's FINISH at the truck (its "Finish the run" prompt, held, from beside the truck's driver's side) → the
-- results card ({ kind = "result" }: Runs') or nil, and the prompt's ok and why.
function H.finishRun(player: any, van: any): (any, boolean, string?)
	local prompt = E.promptIn(van.chassis, "Finish the run")
	if not prompt then
		return nil, false, "no FINISH prompt"
	end
	local at = #E.sent
	local by = E.promptAt(prompt)
	local mid = van.chassis.Position
	local out = V3(by.X - mid.X, 0, by.Z - mid.Z).Unit -- (out of the truck's side, at the prompt)
	E.walk(player, H.groundAt(V3(by.X + out.X * 2.5, 0, by.Z + out.Z * 2.5)))
	local ok, why = E.trigger(prompt, player)
	E.advance(0.5)
	return E.lastKind(player, "Runs", "result", at), ok, why
end
-- The run's end over: EndHold s, the fade back to the lobby.
function H.backHome()
	E.advance(Config.Runs.EndHold + Config.Runs.Fade.Out + 0.5)
end
function H.behindVan(van: any, out: number): any
	local back = van.chassis.CFrame:PointToObjectSpace(H.doorOf(van).WorldPosition)
	return H.groundAt(van.chassis.CFrame * V3(0, 0, back.Z + out))
end
-- The back doors open or shut (its BackPrompt from behind the van).
function H.setBack(player: any, van: any, open: boolean): boolean
	if Vehicles.backOpen(van) == open then
		return true
	end
	E.walk(player, H.behindVan(van, 3))
	E.trigger(Vehicles.backPrompt(van), player)
	return Vehicles.backOpen(van) == open
end
function H.isInside(player: any): boolean
	return E.interiorAt(E.rootOf(player).Position) ~= nil
end
S.into = {} -- player → the flat way into the house from its door (where they came in facing)
S.rooms = {} -- player → the origin of the interior they last walked into
S.trip = {} -- 8.5 player → their last walk through a door: { at, v, clock, moved } where their root was, its walk and the clock as the fade out reached them; the clock of the move (its fade in)
-- 8.5 walking through: walks the player along `points` without a stop (E.walk's steps at their walk), their client's
-- fades watched (S.trip: where they were, their walk and the clock as the fade out came, the clock of the fade in: the
-- move); false when the game did not move them on the way (no trip).
function H.walkThrough(player: any, points: { any }): boolean
	local client = E.clients[player]
	S.trip[player] = nil
	E.clients[player] = function(remote: string, kind: any, a: any, ...: any)
		local trip = S.trip[player]
		if remote == "Moving" and kind == "fade" and a == "out" and trip == nil then
			local root = E.rootOf(player)
			S.trip[player] = { at = root.Position, v = root.AssemblyLinearVelocity, clock = E.clock, moved = nil }
		elseif remote == "Moving" and kind == "fade" and a == "in" and trip and trip.moved == nil then
			trip.moved = E.clock
		end
		if client then
			return client(remote, kind, a, ...)
		end
		return nil
	end
	local moved = not E.walkPath(player, points)
	E.clients[player] = client
	return moved
end
-- 8.5: the parts that collide in the flat box round the line from `from` to `to` (`half` either side of it, a body's
-- height over the ground from `from`'s feet), but the players' bodies and the floors under their feet: their names.
function H.solidOn(from: any, to: any, half: number): { string }
	local way = V3(to.X - from.X, 0, to.Z - from.Z)
	local length = way.Magnitude
	local along = way / length
	local across = V3(-along.Z, 0, along.X)
	local feet = from.Y - 3
	local hit: { string } = {}
	local bodies: { any } = {}
	for _, player in E.Players:GetPlayers() do
		if player.Character then
			table.insert(bodies, player.Character)
		end
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			local mine = false
			for _, body in bodies do
				mine = mine or d:IsDescendantOf(body)
			end
			local rel = d.Position - from
			if mine or math.abs(rel:Dot(across)) > half + 30 or rel:Dot(along) < -30 or rel:Dot(along) > length + 30 then
				continue -- (a body's own, or far off the way)
			end
			-- the part's box against the way's box: its corners' spans along, across and up overlap the way's
			local s, cf = d.Size, d.CFrame
			local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
			for _, x in { -0.5, 0.5 } do
				for _, y in { -0.5, 0.5 } do
					for _, z in { -0.5, 0.5 } do
						local p = cf * V3(x * s.X, y * s.Y, z * s.Z) - from
						local q = { p:Dot(along), p:Dot(across), p.Y + from.Y - feet }
						for i = 1, 3 do
							lo[i], hi[i] = math.min(lo[i], q[i]), math.max(hi[i], q[i])
						end
					end
				end
			end
			if lo[1] < length - 1e-3 and hi[1] > 1e-3 and lo[2] < half - 1e-3 and hi[2] > -half + 1e-3 and lo[3] < 5.5 and hi[3] > 0.3 then
				table.insert(hit, d.Name)
			end
		end
	end
	return hit
end
-- Walks up to the chalet's front door and on through it (8.5: from beyond its approach into its dark hall, no stop:
-- the leaf open on the way, the fade as she crosses the threshold, the move in the dark), inside. six houses: the front
-- door of the house of their move (H.houseOf), a stand-in's as the farmstead's.
function H.enterHouse(player: any): boolean
	local h = H.houseOf(player)
	local facing = H.yawLook(h.door.yaw)
	local door = V3(h.door.x, h.door.y + 3, h.door.z)
	E.walk(player, door + facing * 14)
	H.walkThrough(player, { door - facing * (Config.Moving.Doors.Hall.Depth - 1) })
	local inside = E.waitUntil(function(): boolean
		return H.isInside(player)
	end, 3)
	if inside then
		E.advance(0.3)
		local look = E.rootOf(player).CFrame.LookVector
		S.into[player] = V3(look.X, 0, look.Z).Unit
		S.rooms[player] = E.interiorAt(E.rootOf(player).Position)
	end
	return inside
end
-- Walks out by the interior's front-door way ("LeaveDoor" by the player's interior): up to it, then on through its
-- doorway onto the porch without a stop (8.5: the fade as they cross its threshold, the move in the dark).
function H.leaveHouse(player: any): boolean
	local origin = E.interiorAt(E.rootOf(player).Position)
	local exit: any = nil
	for _, d in workspace:FindFirstChild("Moves"):GetChildren() do
		if d.Name == "LeaveDoor" and origin and (d.Position - origin.Position).Magnitude < 400 then
			exit = d
		end
	end
	if not exit then
		return false
	end
	local inside = exit.Position - V3(0, 3.5, 0)
	local way = S.into[player] or V3(0, 0, 1)
	local up = V3(0, Config.Furniture.EntryUp, 0)
	S.leftBy = { at = inside, way = way } -- (8.5: the doorway's threshold inside, a root's height up, and the way in)
	if not E.walk(player, inside + way * 5 + up) then
		return not H.isInside(player)
	end
	H.walkThrough(player, { inside - way * 5 + up }) -- (onto the porch: 6 studs past the wall)
	return E.waitUntil(function(): boolean
		return not H.isInside(player)
	end, 3)
end
-- The model of the move's piece at `spot` (its prompts are the player's move's: 9.7 a party member's, its host's).
function H.pieceOf(player: any, spot: number): any
	local run = H.Runs.runOf(player)
	local owner = if run then run.host.UserId else player.UserId
	for _, d in workspace:FindFirstChild("Moves"):GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not rawget(d, "destroyed") then
			local root = d.PrimaryPart
			local prompt = root and E.promptIn(root, "", function(p: any): boolean
				return p:GetAttribute("MoveOwner") == owner
			end)
			if prompt then
				return d
			end
		end
	end
	return nil
end
-- 10.x danger: is the piece at `spot` of the player's run in its vault (sealed) or in a room behind a door still locked?
function H.dangerous(player: any, spot: number): boolean
	local st = H.Danger.stateFor(player)
	if not st then
		return false
	end
	if st.sealed[spot] then
		return true
	end
	local room: string? = nil
	for _, planned in st.s.plan.spots do
		if planned.id == spot then
			room = planned.room
		end
	end
	for _, lock in st.locks do
		if not lock.open and table.find(lock.plan.behind, room) then
			return true
		end
	end
	return false
end
-- A piece at home in the player's house that `fits` (by its def): the first in the state's order → item, model, def
-- (10.x: never one in the run's vault or behind a locked door).
function H.choose(player: any, fits: (any, any) -> boolean): (any, any, any)
	for _, item in H.stateOf(player).items do
		local model = H.pieceOf(player, item.spot)
		local id = model and model:GetAttribute("FurnitureId")
		local def = id and FurnitureLooks.Items[id]
		if item.state == "home" and def and fits(item, def) and not H.dangerous(player, item.spot) then
			return item, model, def
		end
	end
	return nil, nil, nil
end
-- A piece's look: its visible parts' colours, sorted (FurnitureLooks.build colours a piece by its variant). The pieces
-- carried out are remembered so: their stock entries (item, variant) must build the same look, and so must the model a
-- stand shows (the house's variant all the way to the warehouse).
function H.signature(model: any): string
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Transparency or 0) < 1 then
			local c = d.Color
			table.insert(list, string.format("%.3f,%.3f,%.3f", c.R, c.G, c.B))
		end
	end
	table.sort(list)
	return table.concat(list, " ")
end
S.picked = {}
function H.remember(model: any)
	table.insert(S.picked, { item = model:GetAttribute("FurnitureId"), look = H.signature(model) })
end
function H.lookOk(item: string, look: string): boolean
	for _, p in S.picked do
		if p.item == item and p.look == look then
			return true
		end
	end
	return false
end
-- Walks up to a piece (beside it, on the floor; inside or out).
function H.walkTo(player: any, model: any)
	local origin = E.interiorAt(E.rootOf(player).Position)
	local at = model.PrimaryPart.Position
	local floor = (if origin then origin.Position.Y else E.groundY(at.X, at.Z)) + Config.Furniture.EntryUp
	local toward = V3(E.rootOf(player).Position.X - at.X, 0, E.rootOf(player).Position.Z - at.Z)
	toward = if toward.Magnitude > 1e-3 then toward.Unit else V3(1, 0, 0)
	local size = model.PrimaryPart.Size
	E.walk(player, V3(at.X, floor, at.Z) + toward * (math.max(size.X, size.Z) / 2 + 1.5))
end
function H.lastGrip(player: any, from: number, what: string?): any
	local list = E.received(player, "Moving", from)
	for index = #list, 1, -1 do
		local args = list[index]
		if args[1] == "grip" and args[2] == (what or "open") then
			return args[3]
		end
	end
	return nil
end
-- Picks a piece up (a piece with a grip through its lift check, answered by the client: auto).
function H.pickUp(player: any, model: any): boolean
	H.walkTo(player, model)
	local prompt = E.promptIn(model.PrimaryPart, "Pick up") or E.promptIn(model.PrimaryPart, "Lift")
	local ok = E.trigger(prompt, player)
	E.advance(3)
	return ok and player.Character:GetAttribute("MoveCarry") == model:GetAttribute("MoveSpot")
end
-- Loads what the player carries at the van's open back (the doors' Load).
function H.loadAtBack(player: any, van: any): (boolean, string?)
	E.walk(player, H.behindVan(van, 2))
	E.advance(0.3)
	return E.trigger(E.promptIn(H.doorOf(van), "Load"), player)
end
-- A point in the walk-in bay at z (the van's frame): its floor (the chassis' top) + a body's root height.
function H.bayPoint(van: any, z: number): any
	local at = van.chassis.Position
	return van.chassis.CFrame * V3(0, SprinterLooks.Top - (at.Y - E.groundY(at.X, at.Z)) + 3, z)
end
function H.inBay(van: any, model: any): boolean
	local p = van.chassis.CFrame:PointToObjectSpace(model.PrimaryPart.Position)
	local bay = SprinterLooks.Bay
	return p.X > bay.x0 and p.X < bay.x1 and p.Z > bay.z0 and p.Z < bay.z1 and p.Y > 0
end
-- One load (at the house of their run, its truck at the curb): the back open, in, a piece that `fits` out and loaded,
-- the back shut → item, model.
function H.fetch(player: any, van: any, fits: (any, any) -> boolean): (any, any)
	H.setBack(player, van, true)
	if not H.enterHouse(player) then
		return nil, nil
	end
	local item, model = H.choose(player, fits)
	if not item then
		return nil, nil
	end
	H.remember(model)
	if not (H.pickUp(player, model) and H.leaveHouse(player) and (H.loadAtBack(player, van))) then
		return nil, nil
	end
	H.setBack(player, van, false)
	return item, model
end
-- The warehouse: a stand's prompt (and its anchor), walking to a stand's front by the roller door.
function H.standPrompt(plotId: number, index: number, action: string): (any, any)
	local podium = Warehouse.model(plotId):FindFirstChild(`Stand{index}`)
	local anchor = podium and podium:FindFirstChild("Prompts")
	return anchor and anchor:FindFirstChild(action), anchor
end
-- 8.3: the plot at the level its warehouse is built at now (WarehouseLayout.site: that level's stands)
function H.siteOf(plotId: number): any
	return WarehouseLayout.site(plots[plotId], Warehouse.level(plotId))
end
function H.toStand(player: any, plot: any, index: number)
	local spot = WarehouseLayout.stand(H.siteOf(plot.id), index)
	local _, anchor = H.standPrompt(plot.id, index, "Display")
	local front = anchor.WorldPosition + H.yawLook(spot.yaw) * 3
	local floor = WarehouseLayout.FloorTop + 3
	E.walk(player, V3(plot.door.x, floor, plot.door.z + 4))
	E.walk(player, V3(plot.door.x, floor, plot.door.z - 6))
	E.walk(player, V3(front.X, floor, front.Z))
end
-- A Collection request from the client and the Notice it got back ("" for none).
function H.request(player: any, message: any): string
	E.advance(0.3) -- (the remote's rate limit)
	local at = #E.sent
	E.fire(player, "Collection", message)
	return E.lastNotice(player, at)
end
function H.buy(player: any, id: string, level: number): string
	E.advance(0.3)
	local at = #E.sent
	E.fire(player, "Upgrades", { kind = "buy", id = id, level = level })
	return E.lastNotice(player, at)
end
function H.rebuilt()
	E.advance(Config.Warehouse.Rebuild + 0.1)
end

-- ── 1. Two players join ───────────────────────────────────────────────────

local ann = E.join(11, "Ann")
local bob = E.join(22, "Bob")
E.clients[ann] = H.client(ann)
E.clients[bob] = H.client(bob)
do
	check("1. Ann gets plot 1, Bob plot 2 (the player attribute Plot, SandboxPlots)", ann:GetAttribute("Plot") == 1 and bob:GetAttribute("Plot") == 2
		and SandboxPlots.of(ann) == plots[1] and SandboxPlots.of(bob) == plots[2] and SandboxPlots.owner(1) == ann)
	check("…a new sandbox save each, read and saveable ($" .. Config.Sandbox.StartMoney .. ")", H.profileOf(ann) ~= nil
		and H.profileOf(ann).money == Config.Sandbox.StartMoney and PlayerData.loaded(ann) and H.profileOf(bob) ~= nil and PlayerData.loaded(bob))
	local annAt, bobAt = Boot.spawnSpot(ann), Boot.spawnSpot(bob)
	check("…9.7 each in the lobby's plaza (SandboxBoot's spawn: Lobby.spawn, apart by their plots), holstered", H.flat(E.rootOf(ann).Position, V3(annAt.x, 0, annAt.z)) < 0.5
		and H.flat(E.rootOf(bob).Position, V3(bobAt.x, 0, bobAt.z)) < 0.5 and SandboxMap.inLobby(annAt.x, annAt.z) and H.flat(V3(annAt.x, 0, annAt.z), V3(bobAt.x, 0, bobAt.z)) > 1
		and ann.Character:GetAttribute("Holstered") == true, E.rootOf(ann).Position)
	E.advance(0.5)
	check("…their warehouses' signs say whose they are; the others FOR RENT", H.anyText(Warehouse.model(1), "Ann") and H.anyText(Warehouse.model(2), "Bob")
		and H.anyText(Warehouse.model(3), "FOR RENT"))
	local state = E.lastKind(ann, "Collection", "state")
	check("…the collection's state (an empty stock, 8.3: the garage's 2 stands, no income) and the upgrades' (the money)", state ~= nil and #state.stock == 0
		and state.stands == WarehouseLayout.count(1) and state.income == 0 and E.lastKind(ann, "Upgrades", "state") ~= nil
		and E.lastKind(ann, "Upgrades", "state").money == Config.Sandbox.StartMoney)
	local folder = workspace:FindFirstChild("Warehouses")
	check("8.3: new players, so their warehouses are garages (level 1: the Model's Level, workspace.Warehouses' Level1 / Level2, the player attribute WarehouseLevel); a free plot too",
		Warehouse.level(1) == 1 and Warehouse.level(2) == 1 and Warehouse.model(1):GetAttribute("Level") == 1 and folder:GetAttribute("Level1") == 1
			and folder:GetAttribute("Level2") == 1 and ann:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute) == 1
			and bob:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute) == 1 and Warehouse.level(3) == Config.Warehouse.FreeLevel
			and Warehouse.model(1):FindFirstChild("Stand2") ~= nil and Warehouse.model(1):FindFirstChild("Stand3") == nil)
	local book = E.lastKind(ann, "CollectionBook", "state")
	local tasks = E.lastKind(ann, "SandboxTasks", "state")
	check("…the book's state (nothing found) and the day's tasks (3 dailies, a weekly)", book ~= nil and next(book.book) == nil and tasks ~= nil
		and #tasks.daily == Config.SandboxTasks.Daily and tasks.weekly ~= nil)
	check("…the client's State queued (Main's queueState on PlayerData.Changed)", table.find(queued, ann) ~= nil and table.find(queued, bob) ~= nil)
	check("…the analytics' funnel: Joined once each", H.steps(11).Joined == 1 and H.steps(22).Joined == 1)
end

-- ── 2. PLAY ───────────────────────────────────────────────────────────────

local annVan: any, bobVan: any = nil, nil -- (9.7: their trucks come with their runs, step 3)
do
	E.fire(ann, "Play")
	E.advance(1)
	E.fire(bob, "Play")
	E.advance(1)
	local cars = workspace:FindFirstChild("Cars")
	check("2. PLAY: 9.7 no van in the lobby (the truck waits at a run's house): none out, the van hers all the same (profile.car the Sprinter)", Vehicles.get(ann) == nil
		and Vehicles.get(bob) == nil and (cars == nil or #cars:GetChildren() == 0) and H.profileOf(ann).car == Config.Sandbox.Van, H.profileOf(ann).car)
	check("…she is still in the plaza, on foot", E.humanoidOf(ann).SeatPart == nil and SandboxMap.inLobby(E.rootOf(ann).Position.X, E.rootOf(ann).Position.Z))
	local calls = #E.vehicleCalls
	E.fire(ann, "Play")
	E.advance(1)
	check("…a second PLAY changes nothing", Vehicles.get(ann) == nil and #E.vehicleCalls == calls)
	check("…the analytics' funnel: PressedPlay once", H.steps(11).PressedPlay == 1)
	local carAt = #E.sent
	E.fire(ann, "SpawnCar")
	E.advance(0.5)
	check("…CAR in the lobby: no van comes, she is told why", Vehicles.get(ann) == nil and E.heard(ann, "No vans in the lobby", carAt), E.lastNotice(ann, carAt))
end

-- ── 3. The portals: a pad, the difficulty, the countdown, the run ─────────

do
	local R = Config.Runs
	local Runs = H.Runs
	local padAt = #E.sent
	E.walk(ann, H.padAt(House.id))
	E.advance(R.Every + 0.05)
	local pad = E.lastKind(ann, "Runs", "pad", padAt)
	check("3. Ann onto the farmstead's pad: the pad panel (Runs' pad view): she the host, the countdown, Normal by default, Easy and Normal open",
		pad ~= nil and pad.house == House.id and pad.mine == true and pad.host == 11 and pad.left > 0 and pad.left <= R.Countdown and pad.difficulty == R.Default
		and table.concat(pad.open, ",") == "easy,normal" and pad.max == R.MaxParty and pad.going == 1, pad and `{pad.left} {pad.difficulty} {table.concat(pad.open or {}, ",")}`)
	local status, glow = H.portal(House.id)
	check("…its sign counts down (STARTING IN …, 1/4), its pad glows Waiting", string.find(status, "STARTING IN", 1, true) ~= nil and string.find(status, "1/4", 1, true) ~= nil
		and glow ~= nil and math.abs(glow.Color.R - R.Portal.Waiting[1] / 255) < 1e-3 and math.abs(glow.Color.G - R.Portal.Waiting[2] / 255) < 1e-3, status)
	local lockedAt = #E.sent
	E.advance(0.3)
	E.fire(ann, "Runs", { kind = "difficulty", id = "hard" })
	E.advance(0.3)
	check("NEG. Hard picked (not open to her yet: no run finished at Normal): refused, told why, the pad still Normal", E.heard(ann, "Finish a run", lockedAt)
		and Runs.padOf(House.id).difficulty == "normal")
	E.fire(ann, "Runs", { kind = "difficulty", id = "easy" })
	E.advance(R.Every + 0.05)
	check("…Easy (open): the pad's difficulty, her panel says so", Runs.padOf(House.id).difficulty == "easy" and E.lastKind(ann, "Runs", "pad").difficulty == "easy")
	E.advance(0.3)
	E.fire(ann, "Runs", { kind = "difficulty", id = "normal" })
	E.advance(0.3)
	E.fire(bob, "Runs", { kind = "difficulty", id = "easy" })
	E.advance(0.3)
	check("NEG. …Bob's pick (no pad's host): nothing changes", Runs.padOf(House.id).difficulty == "normal")
	local fadeAt = #E.sent
	local started = E.waitUntil(function(): boolean
		return Runs.runOf(ann) ~= nil
	end, R.Countdown + 1)
	E.advance(R.Fade.Out + 0.3)
	annVan = Vehicles.get(ann)
	local run = Runs.runOf(ann)
	check("…the countdown over: Ann's run on the farmstead at Normal (Runs.runOf: she the host, alone)", started and run ~= nil and run.house == House.id
		and run.difficulty == "normal" and #run.party == 1 and run.host == ann)
	check("…her own Sprinter parked at the farmstead's curb, its back to the front door, locked (RunParked: no Drive, its seat Disabled)", annVan ~= nil
		and annVan.id == Config.Sandbox.Van and H.flat(annVan.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 0.5
		and H.doorOf(annVan).WorldPosition.Z > annVan.chassis.Position.Z and annVan.model:GetAttribute(R.Truck.Attribute) == true and annVan.seat.Disabled == true,
		annVan and annVan.chassis.Position)
	local zone = SandboxMap.zone(House.id) :: SandboxMap.Zone
	local fades = {}
	for _, args in E.received(ann, "Moving", fadeAt) do
		if args[1] == "fade" then
			table.insert(fades, args[2])
		end
	end
	check("…faded over (out, then in) to the house's front yard (its zone's arrival spot), facing its door", fades[1] == "out" and fades[#fades] == "in"
		and H.flat(E.rootOf(ann).Position, V3(zone.arrive.x, 0, zone.arrive.z)) < 0.5 and E.rootOf(ann).CFrame.LookVector:Dot(H.yawLook(zone.arrive.yaw)) > 0.99
		and SandboxMap.zoneAt(E.rootOf(ann).Position.X, E.rootOf(ann).Position.Z) == zone, E.rootOf(ann).Position)
	E.advance(R.Every + 0.05)
	status = H.portal(House.id)
	local farmstead = workspace:FindFirstChild("Sandbox"):FindFirstChild("TheOldFarmstead")
	check("…the farmstead's portal IN USE (its sign), the map's house marked RunDifficulty normal (traps, zombies and the loot read it)",
		string.find(status, "IN USE", 1, true) ~= nil and Runs.inUse(House.id) and farmstead ~= nil and farmstead:GetAttribute("RunDifficulty") == "normal", status)
	local runView = E.lastKind(ann, "Runs", "run")
	check("…Runs' run view on her client (she the host, Normal, alone: nobody to vote)", runView ~= nil and runView.mine == true and runView.difficulty == "normal"
		and runView.members == 1 and runView.house == House.id)
	local view = H.stateOf(ann)
	S.annMove = view.id
	local F = Config.Moving.Sandbox.Houses[House.id]
	check("…the move: the run's (its difficulty, she the host), its clock the farmstead's × Normal's, no horde", view.run ~= nil and view.run.difficulty == "normal"
		and view.run.mine == true and view.hordeAt == nil and math.abs(view.endsAt - E.now - F.Time) < 2, view.endsAt - E.now)
	check("…8.8: no role on the move (no MoveRole; the state's team: only the van's call, not made yet)", ann:GetAttribute("MoveRole") == nil
		and view.team.role == nil and view.team.called == false)
	check("…Danny comes with her crew of one, for hire (8.3), his id for his card", MoveHelper.find(ann) ~= nil and MoveHelper.find(ann).hirer == nil
		and ann:GetAttribute("MoveHelperId") == MoveHelper.find(ann).id)
	E.fire(ann, "Moving", "helper", "van")
	check("…the old orders are gone (WAIT AT VAN: nothing): not hired, he leaves her pieces to her, his price on her status line",
		ann:GetAttribute("MoveHelper") == "offer" and type(ann:GetAttribute("MoveHelperPrice")) == "number" and #MoveHelper.find(ann).queue == 0, ann:GetAttribute("MoveHelper"))
	check("…the analytics: FirstContract once, MoveStarted (solo)", H.steps(11).FirstContract == 1 and #H.events("MoveStarted", ann) == 1)
	-- Bob: the farmstead's pad IN USE; the Pond Cabin's: his own run at the same time
	local inUseAt = #E.sent
	E.walk(bob, H.padAt(House.id))
	E.advance(R.Every * 3)
	check("NEG. Bob onto the farmstead's pad while Ann's run is on: IN USE (told once), no pad panel, no line", E.heard(bob, "is in use", inUseAt)
		and E.lastKind(bob, "Runs", "pad", inUseAt) == nil and Runs.padOf(House.id).host == nil and Runs.runOf(bob) == nil)
	local cabin = SandboxMap.Houses[2]
	E.walk(bob, H.padAt(cabin.id))
	started = E.waitUntil(function(): boolean
		return Runs.runOf(bob) ~= nil
	end, R.Countdown + 2)
	E.advance(R.Fade.Out + 0.3)
	bobVan = Vehicles.get(bob)
	local bobView = H.stateOf(bob)
	local own = Config.Moving.Sandbox.Houses[cabin.id]
	check(`…Bob's run on {cabin.name} at the same time (a {own.Kind}, its own clock): his own move, his own truck at its curb, his own Danny`, started
		and bobView ~= nil and bobView.id ~= view.id and bobView.contract == cabin.id and own.Kind == "cabin" and bobVan ~= nil and bobVan ~= annVan
		and H.flat(bobVan.chassis.Position, V3(cabin.curb.x, 0, cabin.curb.z)) < 0.5 and MoveHelper.find(bob) ~= nil and MoveHelper.find(bob) ~= MoveHelper.find(ann)
		and math.abs(bobView.endsAt - E.now - own.Time) < 2 and H.stateOf(ann).id == view.id, bobView and bobView.contract)
end

-- ── 4–6. Ann at the chalet: the door, the grip, the load ─────────────────

do
	check("4. Ann at the chalet: her truck at its curb already (9.7: parked there by the run, no drive), its back to the front door",
		H.flat(annVan.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 0.5 and H.doorOf(annVan).WorldPosition.Z > annVan.chassis.Position.Z, annVan.chassis.Position)
	check("…got out and opened the back doors (Vehicles' BackPrompt: hers, on foot, hands free)", H.setBack(ann, annVan, true), E.lastNotice(ann))
	-- 8.3: what her client sees of the trip, on the clock (the fade's messages, her body then, the leaf), and when the
	-- chalet's leaf opened
	local D = Config.Moving.Doors
	local door = S.frontLeaf
	-- (9.7: she landed in the front yard facing the door, within its approach: its leaf opened for her; back out of the
	-- approach first, the leaf shut again, then on through the door)
	E.walk(ann, V3(House.door.x, House.door.y + 3, House.door.z) + H.yawLook(House.door.yaw) * 14)
	E.waitUntil(function(): boolean
		return door:GetAttribute("DoorOpen") ~= true
	end, D.Shut + 2)
	local seen: { any } = {}
	local openedAt: number? = nil
	local opening = door:GetAttributeChangedSignal("DoorOpen"):Connect(function()
		if door:GetAttribute("DoorOpen") == true and openedAt == nil then
			openedAt = E.clock
		end
	end)
	local client = E.clients[ann]
	E.clients[ann] = function(remote: string, kind: any, a: any, b: any, c: any, ...: any)
		if remote == "Moving" and kind == "fade" then
			table.insert(seen, { what = a, at = E.clock, seconds = b, arrival = c, root = E.rootOf(ann).Position, open = door:GetAttribute("DoorOpen") })
		end
		return client(remote, kind, a, b, c, ...)
	end
	local fadeAt = #E.sent
	local wayIn = { from = V3(House.door.x, 3, House.door.z) + H.yawLook(House.door.yaw) * 14, to = V3(House.door.x, 3, House.door.z) - H.yawLook(House.door.yaw) * (D.Hall.Depth - 1) }
	local solidIn = H.solidOn(wayIn.from, wayIn.to, 1)
	check("…walked up to the front door and on through it without a stop (8.5): inside, no E", H.enterHouse(ann), E.rootOf(ann).Position)
	E.clients[ann] = client
	opening:Disconnect()
	-- 8.5 walking through (the owner: "so it doesn't feel like I bumped into the door, but I keep walking smoothly")
	local trip = S.trip[ann]
	local facing = H.yawLook(House.door.yaw)
	local foot = V3(House.door.x, 3, House.door.z)
	local along = if trip then (trip.at - foot):Dot(facing) else math.huge -- (studs out of the door's face; < 0 in its doorway)
	local speed = if trip then trip.v:Dot(-facing) else 0
	check("8.5 the way in clear: nothing that collides from 14 studs out of the door through its doorway to its dark hall's end (a body's width and height)",
		#solidIn == 0, table.concat(solidIn, ", "))
	check("8.5 the trip by walking through: the fade out came while she walked on at her walk, as her root crossed the door's threshold (no dwell, no stop)",
		trip ~= nil and speed > E.walkSpeed(ann) * 0.9 and along <= 2.5 and along >= -2, `{along} out, {speed} studs/s`)
	local reach = if trip and speed > 0 then trip.clock + along / speed else 0 -- (when her walk took her to the door's face)
	check("8.5 the leaf fully open before she reached the doorway (open Open s, with the network's moment, before her walk got there)",
		openedAt ~= nil and trip ~= nil and (openedAt :: number) + D.Open + 0.15 <= reach, openedAt and reach - (openedAt :: number))
	local last = seen[#seen]
	local walked = if trip and last then along - speed * (last.at - trip.clock) else math.huge -- (where her walk had taken her as she was moved)
	check("8.5 …and the move came while her walk went on into the house's dark hall, before its end (Hall.Depth)", last ~= nil and last.what == "in"
		and walked >= -(D.Hall.Depth - 0.5) and walked < 0, walked)
	local out, back = seen[1], seen[#seen]
	check("8.3 the chalet's leaf swung open as she walked up to it, open Open s before the fade out started (and still open then)", openedAt ~= nil
		and out ~= nil and out.what == "out" and out.open == true and out.at - (openedAt or 0) >= D.Open - 1e-6, out and openedAt and out.at - openedAt)
	check("8.3 the move landed FadeOut + Margin s after the fade out (FadeOut s of it on her screen): black when she was moved", out ~= nil and back ~= nil
		and out.seconds == D.FadeOut and back.what == "in" and back.seconds == D.FadeIn and back.at - out.at >= D.FadeOut + D.Margin - 1e-6
		and back.at - out.at <= D.FadeOut + D.Margin + 0.1, back and out and back.at - out.at)
	local arrival = if back then back.arrival else nil
	local exit: any = nil
	for _, d in workspace:FindFirstChild("Moves"):GetChildren() do
		if d.Name == "LeaveDoor" and S.rooms[ann] and (d.Position - S.rooms[ann].Position).Magnitude < 400 then
			exit = d
		end
	end
	local past = if arrival and exit then (arrival.at - (exit.Position - V3(0, 3.5, 0))):Dot(V3(0, 0, 1)) else 0
	check("8.3 the fade in: where she is (the client's black lasts until it sees her there), a step past the door inside, facing into the house",
		type(arrival) == "table" and (arrival.at - back.root).Magnitude < 1e-3 and arrival.look:Dot(V3(0, 0, 1)) > 0.99 and arrival.dark == D.Dark
		and arrival.wait == D.Wait and past > D.Depth and past < Config.Furniture.EntryIn + 1, past)
	check("8.3 …the chalet's leaf shuts again Shut s after its zone emptied", E.waitUntil(function(): boolean
		return door:GetAttribute("DoorOpen") == false
	end, D.Shut + 1))
	local fades = {}
	for _, args in E.received(ann, "Moving", fadeAt) do
		if args[1] == "fade" then
			table.insert(fades, args[2])
		end
	end
	check("…through the fade (out, then in); the move's state says inside", fades[1] == "out" and fades[#fades] == "in" and H.stateOf(ann).inside == true,
		table.concat(fades, ","))
	check("…the analytics: EnteredHouse once", H.steps(11).EnteredHouse == 1)
end

do
	-- 5. The grip: a sturdy two-hands piece (CarryGrip.kind "both": a missed wobble staggers it, never drops it at once).
	local piece, model, def = H.choose(ann, function(_item: any, d: any): boolean
		return d.class == "both" and not d.fragile and CarryGrip.kind(d.class, d.fragile, false, nil) ~= nil
	end)
	check("5. (a sturdy two-hands piece in Ann's house)", piece ~= nil, "none")
	S.annBig, S.annBigModel, S.annBigDef = piece, model, def
	H.remember(model)
	H.walkTo(ann, model)
	local prompt = E.promptIn(model.PrimaryPart, "Pick up")
	local openAt = #E.sent
	local ok, why = E.trigger(prompt, ann)
	local wire = H.lastGrip(ann, openAt)
	local gripCheck = wire and CarryGrip.fromWire(wire)
	check("…Pick up opens a lift check (the server's), not a lift", ok and wire ~= nil and gripCheck ~= nil and gripCheck.what == "lift"
		and H.itemOf(ann, piece.spot).state == "home" and ann.Character:GetAttribute("MoveCarry") == nil, why)
	local good = if gripCheck then CarryGrip.firstHit(gripCheck) else 0
	E.fire(bob, "Moving", "grip", wire and wire.id, "ok", good)
	check("…Bob's \"ok\" to Ann's check does nothing (only your own open check counts)", H.lastGrip(ann, openAt, "result") == nil
		and H.lastGrip(bob, openAt, "result") == nil and H.itemOf(ann, piece.spot).state == "home")
	local condition0 = H.itemOf(ann, piece.spot).condition
	E.fire(ann, "Moving", "grip", wire and wire.id, "ok", good) -- (at once: a press the server's clock could not have seen yet)
	local forged = H.lastGrip(ann, openAt, "result")
	local knock = Config.CarryGrip.Lift.Knock
	check("NEG. a forged grip success (\"ok\" with a press time ahead of the server's clock) is refused: a miss, it slips back down",
		forged ~= nil and forged.outcome == "knock" and H.itemOf(ann, piece.spot).state == "home" and ann.Character:GetAttribute("MoveCarry") == nil,
		forged and forged.outcome)
	check("…and takes its knock (" .. math.floor(knock * 100 + 0.5) .. "%)",
		math.abs(H.itemOf(ann, piece.spot).condition - math.floor((condition0 - knock) * 100 + 0.5) / 100) < 0.011, `{condition0} → {H.itemOf(ann, piece.spot).condition}`)
	E.advance(Config.CarryGrip.Lift.Again + 0.1)
	openAt = #E.sent
	E.trigger(prompt, ann)
	wire = H.lastGrip(ann, openAt)
	gripCheck = wire and CarryGrip.fromWire(wire)
	good = if gripCheck then CarryGrip.firstHit(gripCheck) else 0
	E.advance(good + E.ping) -- (the client presses when the needle is in the middle of the zone; its answer a ping later)
	E.fire(ann, "Moving", "grip", wire and wire.id, "ok", good)
	local balanced = H.lastGrip(ann, openAt, "result")
	check("…the client's \"ok\" with a good press time: BALANCED, lifted", balanced ~= nil and balanced.outcome == "balanced"
		and ann.Character:GetAttribute("MoveCarry") == piece.spot and H.itemOf(ann, piece.spot).state == "carried", balanced and balanced.outcome)
	check("…the grip on the carry (CarryGrip) and the steady walk", ann.Character:GetAttribute("CarryGrip") ~= nil and type(ann.Character:GetAttribute("CarrySpeed")) == "number")
	local replayAt = #E.sent
	E.fire(ann, "Moving", "grip", wire and wire.id, "ok", good)
	check("…the same answer again does nothing", H.lastGrip(ann, replayAt, "result") == nil and ann.Character:GetAttribute("MoveCarry") == piece.spot)
	S.auto[ann] = true -- (the wobbles on the way: her client answers them)

	-- 6. Out through the doorway; a wobble answered, one missed; loaded at the back doors.
	check("6. carried out through the doorway (8.5: walked on through it inside, no stop): outside with the piece", H.leaveHouse(ann)
		and ann.Character:GetAttribute("MoveCarry") == piece.spot, E.rootOf(ann).Position)
	-- 8.5 the way out as the way in: the fade out as her walk (the carry's) took her across the doorway's threshold inside,
	-- the porch clear before her and the move before she reached its end (its wall of daylight, Wall + 6 studs out)
	do
		local trip, by = S.trip[ann], S.leftBy
		local along = if trip then (trip.at - by.at):Dot(by.way) else math.huge
		local speed = if trip then -trip.v:Dot(by.way) else 0
		local moved: number? = if trip then trip.moved else nil
		local stop = Config.Furniture.Wall + 6 - 0.5
		local solid = H.solidOn(by.at + by.way * 5, by.at - by.way * stop, 1)
		check("8.5 …out by walking through: the fade out while she walked on with the piece, as her root crossed the doorway's threshold inside; the way onto the porch clear",
			trip ~= nil and speed > 0.5 * E.walkSpeed(ann) and along <= 2.5 and along >= -2 and #solid == 0, `{along}, {speed} studs/s; {table.concat(solid, ", ")}`)
		local walked = if trip and moved then along - speed * (moved - trip.clock) else -math.huge
		check("8.5 …the move before her walk reached the porch's end (its wall of daylight)", walked >= -stop and walked < 0, walked)
	end
	check("…the piece came along (welded in front of her)", H.flat(model.PrimaryPart.Position, E.rootOf(ann).Position) < 8, model.PrimaryPart.Position)
	local wobbleAt = #E.sent
	local opened = Moving.gripCheck(ann)
	E.advance(3)
	local steady = H.lastGrip(ann, wobbleAt, "result")
	check("…a WOBBLE! on the way (Moving.gripCheck): her client's good press keeps it STEADY", opened and steady ~= nil and steady.outcome == "steady"
		and ann.Character:GetAttribute("MoveCarry") == piece.spot, steady and steady.outcome)
	S.auto[ann] = false
	local missAt = #E.sent
	local before = H.itemOf(ann, piece.spot).condition
	Moving.gripCheck(ann)
	local wobble = H.lastGrip(ann, missAt)
	E.advance((if wobble then wobble.window else 3) + Config.CarryGrip.Server.Grace + 0.5)
	local missed = H.lastGrip(ann, missAt, "result")
	check("…a wobble left unanswered (her client quiet): the server's own miss, a STAGGER (a knock), still in her hands", missed ~= nil
		and missed.outcome == "stagger" and ann.Character:GetAttribute("MoveCarry") == piece.spot and H.itemOf(ann, piece.spot).condition < before,
		missed and missed.outcome)
	S.auto[ann] = true
	E.advance(Config.CarryGrip.Miss.SlowFor)
	local loaded, whyLoad = H.loadAtBack(ann, annVan)
	check("…loaded at the open back doors: in the van, in its bay", loaded and H.itemOf(ann, piece.spot).state == "truck"
		and ann.Character:GetAttribute("MoveCarry") == nil and H.inBay(annVan, model) and E.heard(ann, "loaded"), whyLoad or E.lastNotice(ann))
	check("…the analytics: FirstPieceInVan once", H.steps(11).FirstPieceInVan == 1)
end

do
	-- a one-hand piece (no grip), loaded from inside the walk-in bay
	check("(back in)", H.enterHouse(ann))
	local small, model = H.choose(ann, function(_item: any, d: any): boolean
		return d.class == "hand" and not d.fragile
	end)
	check("(a one-hand sturdy piece in Ann's house)", small ~= nil)
	S.annSmall, S.annSmallModel = small, model
	H.remember(model)
	local noGripAt = #E.sent
	check("…a one-hand sturdy piece lifts at once (no grip check)", H.pickUp(ann, model) and H.lastGrip(ann, noGripAt) == nil, E.lastNotice(ann))
	check("(out with it)", H.leaveHouse(ann))
	E.walk(ann, H.behindVan(annVan, 3))
	E.walk(ann, H.bayPoint(annVan, SprinterLooks.Bay.z1 - 2), Config.Movement.Walk * 0.5) -- (up the step, into the bay)
	E.walk(ann, H.bayPoint(annVan, (SprinterLooks.Bay.z0 + SprinterLooks.Bay.z1) / 2), Config.Movement.Walk * 0.5)
	E.advance(0.3)
	local bay = annVan.chassis:FindFirstChild("MoveLoadBay")
	local bayLoad = bay and bay:FindFirstChildOfClass("ProximityPrompt")
	local doorLoad = E.promptIn(H.doorOf(annVan), "Load")
	check("…inside the walk-in bay: the bay's own Load (the doors' waits)", bayLoad ~= nil and bayLoad.Enabled and not doorLoad.Enabled)
	check("…8.8: no wait at either Load (no role needed: no hold, no MoveQuick)", bayLoad ~= nil and bayLoad.HoldDuration == 0 and doorLoad.HoldDuration == 0
		and bayLoad:GetAttribute("MoveQuick") == nil and doorLoad:GetAttribute("MoveQuick") == nil)
	local ok = E.trigger(bayLoad, ann)
	check("…loaded from inside the bay", ok and H.itemOf(ann, small.spot).state == "truck" and H.inBay(annVan, model) and H.stateOf(ann).counts.out == 2,
		E.lastNotice(ann))
	E.walk(ann, H.bayPoint(annVan, SprinterLooks.Bay.z1 - 1), Config.Movement.Walk * 0.5)
	E.walk(ann, H.behindVan(annVan, 4))
	check("…the back doors shut again", H.setBack(ann, annVan, false))
end

-- ── 7a. Bob at his house (two runs at once) ───────────────────────────────

do
	-- Bob: a piece through his grip (his client answers), a death on the way, the respawn by his truck, loaded.
	S.auto[bob] = true
	local bobHouse = H.houseOf(bob)
	check("Bob: at his own place (The Pond Cabin), his truck at its curb (its back to its door)", bobHouse == SandboxMap.Houses[2]
		and H.flat(bobVan.chassis.Position, V3(bobHouse.curb.x, 0, bobHouse.curb.z)) < 0.5
		and H.flat(H.doorOf(bobVan).WorldPosition, V3(bobHouse.door.x, 0, bobHouse.door.z)) < H.flat(bobVan.chassis.Position, V3(bobHouse.door.x, 0, bobHouse.door.z)), bobVan.chassis.Position)
	check("(Bob's back open)", H.setBack(bob, bobVan, true), E.lastNotice(bob))
	check("(Bob in)", H.enterHouse(bob))
	check("…two houses at once: Bob's interior is another slot than Ann's (her run still on)", S.rooms[bob] ~= nil and S.rooms[ann] ~= nil
		and S.rooms[bob] ~= S.rooms[ann] and H.stateOf(ann) ~= nil and H.stateOf(ann).counts.out == 2)
	local piece, model = H.choose(bob, function(_i: any, d: any): boolean
		return d.class ~= "pair" and CarryGrip.kind(d.class, d.fragile, false, nil) ~= nil
	end)
	H.remember(model)
	S.bobPiece = piece
	check("Bob lifts a piece (a grip check answered by his client, if it has one)", piece ~= nil and H.pickUp(bob, model), E.lastNotice(bob))
	check("(Bob out)", H.leaveHouse(bob))
	local outOf = H.yawLook(bobHouse.door.yaw)
	E.walk(bob, H.groundAt(V3(bobHouse.door.x, 0, bobHouse.door.z) + outOf * 10 + V3(-outOf.Z, 0, outOf.X) * 6))
	local before = H.itemOf(bob, piece.spot).condition
	E.humanoidOf(bob).Health = 0
	E.advance(0.3)
	local dropped = H.itemOf(bob, piece.spot)
	check("…Bob dies carrying it: it goes down outside (the death's knock), out of his hands", dropped.state == "ground" and dropped.condition < before
		and bob.Character:GetAttribute("MoveCarry") == nil, `{dropped.state} {before} → {dropped.condition}`)
	E.advance(5) -- (Players.RespawnTime)
	E.spawn(bob)
	E.advance(1)
	check("…his new body stands by his truck's back (SandboxBoot's spawn → Moving.respawnAt), not in the lobby",
		H.flat(E.rootOf(bob).Position, H.doorOf(bobVan).WorldPosition) < 10 and not SandboxMap.inLobby(E.rootOf(bob).Position.X, E.rootOf(bob).Position.Z), E.rootOf(bob).Position)
	check("…still in his run (Runs.runOf)", H.Runs.runOf(bob) ~= nil and H.Runs.runOf(bob).host == bob)
	check("(he lifts it again where it lies: its lift check, his client's answer)", H.pickUp(bob, model), E.lastNotice(bob))
	-- 8.1 review: a wobble still open when he loads it counts as a miss (Grip.forfeit), the piece goes in all the same
	E.walk(bob, H.behindVan(bobVan, 2))
	E.advance(0.3)
	S.auto[bob] = false
	local openAt = #E.sent
	local opened = Moving.gripCheck(bob)
	local held = H.itemOf(bob, piece.spot).condition
	local loaded = E.trigger(E.promptIn(H.doorOf(bobVan), "Load"), bob)
	E.advance(0.5)
	local forfeit = H.lastGrip(bob, openAt, "result")
	check("8.1 review: a WOBBLE! still open when he loads it is a miss (a stagger, a fragile piece's drop: its knock), the piece in the truck",
		opened and loaded and forfeit ~= nil and (forfeit.outcome == "stagger" or forfeit.outcome == "drop") and H.itemOf(bob, piece.spot).state == "truck"
		and H.itemOf(bob, piece.spot).condition < held, forfeit and forfeit.outcome)
	S.auto[bob] = true
	H.setBack(bob, bobVan, false)
end

-- ── 7. FINISH at the truck: the run's end, everything home ────────────────

do
	local big = S.annBigModel
	E.advance(1)
	check("7. the loaded truck at the house: nothing home before the run's end (no trip at a plot: nobody drives)", H.stateOf(ann).trips == 0
		and #Collection.stock(ann) == 0 and #Collection.stock(bob) == 0 and H.stateOf(ann).counts.out == 2)
	check("…the load in the bay (welded to the truck)", H.inBay(annVan, big))
	local tripAt = #E.sent
	local result, ok, why = H.finishRun(ann, annVan)
	local stock = Collection.stock(ann)
	check("…FINISH at the truck (its \"Finish the run\" prompt: the host's): the run over, both pieces into HER stock at once", ok and #stock == 2
		and #Collection.stock(bob) == 0 and H.Runs.runOf(ann) == nil and Moving.busy(ann) == nil, why or E.lastNotice(ann))
	local entry = H.entryFor(stock, S.annBigDef.id)
	check("…Collection.add with the piece's item, name, condition (the move's) and a uid", entry ~= nil and entry.name == S.annBigDef.name
		and type(entry.condition) == "number" and type(entry.uid) == "string" and entry.stand == nil, entry and entry.condition)
	local looked = #stock > 0
	for _, e in stock do
		looked = looked and H.lookOk(e.item, H.signature(FurnitureLooks.build(e.item, e.variant)))
	end
	check("…with the house's variant: each entry (item, variant) builds the very look the piece had in the house", looked)
	check("…the pieces left the truck (their models gone), no pay per piece", rawget(big, "destroyed") == true and rawget(S.annSmallModel, "destroyed") == true
		and H.paid(ann, "MovePay") == 0)
	local worth = 0
	for _, e in stock do
		worth += CollectionRules.valueOf(e) * e.condition
	end
	local named = result ~= nil and #result.pieces == 2
	for _, piece in (if result then result.pieces else {}) do
		named = named and piece.by == "Ann" and piece.to == 11 and type(piece.rarity) == "string" and type(piece.name) == "string"
	end
	check("9.7 …the results card (Runs' \"result\"): the farmstead at Normal, done, 2 pieces (each its rarity, who got it), their value, hers all",
		result ~= nil and result.house == House.id and result.difficulty == "normal" and result.phase == "done" and result.count == 2 and result.mine == 2
		and math.abs(result.value - worth) <= 2 and result.mineValue == result.value and named, result and `{result.count} {result.value} vs {worth}`)
	local unlocked = E.lastKind(ann, "Runs", "unlocked", tripAt)
	check("9.7 …a run finished at Normal opens Hard: told so (\"unlocked\"), the card says it, her save's runUnlocked 3",
		unlocked ~= nil and unlocked.id == "hard" and result ~= nil and result.opened == "hard" and H.profileOf(ann).runUnlocked == 3)
	E.advance(0.2)
	local pushed = E.lastKind(ann, "Collection", "state")
	check("…the collection's state went to her client (2 in stock)", pushed ~= nil and #pushed.stock == 2)
	-- 8.2: the book
	local book = Book.book(ann)
	local bookState = E.lastKind(ann, "CollectionBook", "state", tripAt)
	check("8.2 book: both pieces are in Ann's book (found once), her client told they are new", book ~= nil and book[S.annBigDef.id] ~= nil
		and book[S.annBigDef.id].n == 1 and book[stock[1].item] ~= nil and book[stock[2].item] ~= nil and bookState ~= nil and #bookState.new == 2,
		bookState and #bookState.new)
	check("…nothing in Bob's", next(Book.book(bob) or {}) == nil)
	-- 8.2: the tasks and the analytics
	local trips = H.task(ann, "trips")
	check("8.2 tasks: \"trips\" counts the run's load home (1 of " .. (if trips then tostring(trips.target) else "?") .. ")", trips ~= nil and trips.progress == 1, trips and trips.progress)
	local rare = 0
	for _, e in stock do
		local d = CollectionRules.defOf(e.item)
		rare += if d and (d :: any).rarity then 1 else 0
	end
	check("8.2 analytics: a CollectibleFound for each collectible that came home (" .. rare .. ")", #H.events("CollectibleFound", ann) == rare)
	check("8.2 analytics: FirstTripHome once, one CollectionAdded for the load (2 pieces)", H.steps(11).FirstTripHome == 1
		and #H.events("CollectionAdded", ann) == 1 and H.events("CollectionAdded", ann)[1][3] == 2)
	H.backHome()
	local portal = SandboxMap.portal(House.id) :: SandboxMap.Portal
	check("9.7 …EndHold s later: back in the lobby by the farmstead's portal (its back spot), the truck gone, Danny gone, the portal free again",
		H.flat(E.rootOf(ann).Position, V3(portal.back.x, 0, portal.back.z)) < 0.5 and SandboxMap.inLobby(E.rootOf(ann).Position.X, E.rootOf(ann).Position.Z)
		and Vehicles.get(ann) == nil and MoveHelper.find(ann) == nil and not H.Runs.inUse(House.id) and (H.portal(House.id)) == "WALK ONTO THE PAD", E.rootOf(ann).Position)
end

do
	-- Bob's FINISH (his run went on meanwhile: Ann's end is hers)
	check("…Bob's run went on through Ann's end (his own: his piece still in his truck)", H.Runs.runOf(bob) ~= nil and H.itemOf(bob, S.bobPiece.spot).state == "truck")
	local result = H.finishRun(bob, bobVan)
	check("…Bob's FINISH: his piece in HIS stock and book, Ann's untouched; his card his own (1 piece)", #Collection.stock(bob) == 1 and #Collection.stock(ann) == 2
		and Book.book(bob)[Collection.stock(bob)[1].item] ~= nil and result ~= nil and result.count == 1 and result.mine == 1 and result.pieces[1].by == "Bob",
		result and result.count)
	H.backHome()
	check("…back in the lobby by the Pond Cabin's portal", SandboxMap.inLobby(E.rootOf(bob).Position.X, E.rootOf(bob).Position.Z) and Vehicles.get(bob) == nil)
end

do
	-- a second run: the farmstead again (refilled: something came home), one more piece, FINISH
	local seedWas = S.annMove
	local run = H.run({ ann }, House.id)
	annVan = Vehicles.get(ann)
	check("(Ann's second run: the farmstead again, a new move; her truck back at its curb)", run ~= nil and H.stateOf(ann).id ~= seedWas and annVan ~= nil
		and H.flat(annVan.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 0.5)
	local item = H.fetch(ann, annVan, function(_i: any, d: any): boolean
		return d.class == "hand" and not d.fragile
	end)
	check("(a third piece fetched and loaded)", item ~= nil and H.itemOf(ann, item.spot).state == "truck", E.lastNotice(ann))
	local tripAt = #E.sent
	local result = H.finishRun(ann, annVan)
	check("…FINISH: 3 in her stock; the card 1 piece (no new difficulty: Hard opened already)", #Collection.stock(ann) == 3 and result ~= nil and result.count == 1
		and result.opened == nil and E.lastKind(ann, "Runs", "unlocked", tripAt) == nil, result and result.count)
	local trips = H.task(ann, "trips")
	local done = E.lastKind(ann, "SandboxTasks", "done", tripAt)
	check("8.2 tasks: \"trips\" 2" .. (if trips and trips.target == 2 then ", done: her client told" else ""), trips ~= nil and trips.progress == math.min(2, trips.target)
		and (trips.target ~= 2 or (done ~= nil and trips.done)), trips and `{trips.progress}/{trips.target}`)
	H.backHome()
end

-- ── 8. The warehouse: the picker, a display, the stand's model ───────────

local annStock = Collection.stock(ann)
table.sort(annStock, function(a: any, b: any): boolean
	return CollectionRules.income(a, 1, Collection.market(ann)) > CollectionRules.income(b, 1, Collection.market(ann))
end)
do
	H.toStand(ann, plots[1], 1)
	local pickAt = #E.sent
	local ok, why = E.trigger(H.standPrompt(1, 1, "Display"), ann)
	local pick = E.lastKind(ann, "Collection", "pick", pickAt)
	local listed = E.lastKind(ann, "Collection", "state", pickAt)
	check("8. Ann's empty stand 1: Display opens the picker on her client (the stock listed with its worth)", ok and pick ~= nil and pick.stand == 1
		and listed ~= nil and #listed.stock == 3 and type(listed.stock[1].income) == "number" and type(listed.stock[1].price) == "number", why)
	E.fire(ann, "Collection", { kind = "display", uid = annStock[1].uid, stand = 1 })
	H.rebuilt()
	local shown = Warehouse.shown(1, 1)
	local spot = WarehouseLayout.stand(H.siteOf(1), 1) -- (8.3: the garage's stand 1)
	check("…the picker's DISPLAY (the remote): the piece's model stands on stand 1", shown ~= nil and shown:GetAttribute("Uid") == annStock[1].uid
		and H.flat(shown:GetPivot().Position, V3(spot.x, 0, spot.z)) < 0.1 and shown:IsDescendantOf(workspace), shown and shown:GetPivot().Position)
	local tag = Warehouse.model(1):FindFirstChild("Stand1"):FindFirstChild("Tag")
	check("…its tag shows its name and \"+$…/min\"; Display off, Take down / Sell on", tag ~= nil and tag.Enabled and H.anyText(tag, annStock[1].name)
		and H.anyText(tag, "/min") and not H.standPrompt(1, 1, "Display").Enabled and H.standPrompt(1, 1, "TakeDown").Enabled and H.standPrompt(1, 1, "Sell").Enabled)
	check("…in her stock it stands on 1; Bob's warehouse shows nothing of hers", H.byUid(Collection.stock(ann), annStock[1].uid).stand == 1 and Warehouse.shown(2, 1) == nil)
	E.advance(0.3)
	H.toStand(ann, plots[1], 2)
	E.trigger(H.standPrompt(1, 2, "Display"), ann)
	E.fire(ann, "Collection", { kind = "display", uid = annStock[2].uid, stand = 2 })
	H.rebuilt()
	check("…a second piece on stand 2", Warehouse.shown(1, 2) ~= nil and Warehouse.shown(1, 2):GetAttribute("Uid") == annStock[2].uid)
	check("…each stand shows the very piece that came out of the house (its look: the house's variant)",
		H.lookOk(annStock[1].item, H.signature(Warehouse.shown(1, 1))) and H.lookOk(annStock[2].item, H.signature(Warehouse.shown(1, 2))))
	check("…the analytics: FirstPieceOnShow once, CollectionDisplayed for each", H.steps(11).FirstPieceOnShow == 1 and #H.events("CollectionDisplayed", ann) == 2)
	-- Take down (its prompt) sends a piece back to the stock; a piece on show put on another stand moves there (8.3: the
	-- garage has two stands, so the move goes to the one Take down emptied)
	E.advance(0.5) -- (Warehouse's double-press guard after her Display there)
	local downAt = #E.sent
	local down = E.trigger(H.standPrompt(1, 2, "TakeDown"), ann)
	H.rebuilt()
	check("…Take down at stand 2: back in her stock, the stand empty", down and E.heard(ann, "is back in your stock", downAt)
		and H.byUid(Collection.stock(ann), annStock[2].uid).stand == nil and Warehouse.shown(1, 2) == nil and Warehouse.shown(1, 1) ~= nil)
	check("…a piece on show put on another stand moves there (stand 1 empty, stand 2 shows it)", H.request(ann, { kind = "display", uid = annStock[1].uid, stand = 2 }) == ""
		and (function(): boolean
			H.rebuilt()
			return Warehouse.shown(1, 1) == nil and Warehouse.shown(1, 2) ~= nil and Warehouse.shown(1, 2):GetAttribute("Uid") == annStock[1].uid
				and H.standPrompt(1, 1, "Display").Enabled and H.byUid(Collection.stock(ann), annStock[1].uid).stand == 2
		end)())
	H.request(ann, { kind = "display", uid = annStock[1].uid, stand = 1 })
	H.rebuilt()
	H.request(ann, { kind = "display", uid = annStock[2].uid, stand = 2 })
	H.rebuilt()
	check("(on stands 1 and 2 again)", Warehouse.shown(1, 1) ~= nil and Warehouse.shown(1, 1):GetAttribute("Uid") == annStock[1].uid
		and Warehouse.shown(1, 2) ~= nil and Warehouse.shown(1, 2):GetAttribute("Uid") == annStock[2].uid)

	-- the refusals (the remote is the client's: anything can come)
	local third = annStock[3]
	check("NEG. display on a stand she doesn't have (8.3: 3, the garage has 2): refused", H.request(ann, { kind = "display", uid = third.uid, stand = 3 }) == "There's no such display stand."
		and H.byUid(Collection.stock(ann), third.uid).stand == nil)
	local junk = true
	for _, stand in { 0, -1, 21, 1.5, "1", 0 / 0, math.huge } do
		junk = junk and H.request(ann, { kind = "display", uid = third.uid, stand = stand }) == "There's no such display stand."
	end
	check("…nor 0, -1, 21, 1.5, \"1\", NaN, inf", junk and H.byUid(Collection.stock(ann), third.uid).stand == nil)
	check("…nor a stand that shows a piece already", string.find(H.request(ann, { kind = "display", uid = third.uid, stand = 1 }), "already shows", 1, true) ~= nil)
	local bobStock = Collection.stock(bob)
	S.bobUid = bobStock[1].uid
	check("NEG. Bob's display of Ann's piece: not in his stock (her stand keeps it)", H.request(bob, { kind = "display", uid = annStock[1].uid, stand = 1 }) == "That piece isn't in your stock."
		and Warehouse.shown(1, 1):GetAttribute("Uid") == annStock[1].uid and Warehouse.shown(2, 1) == nil)
	check("…his own piece goes to HIS warehouse's stand 1, not hers", H.request(bob, { kind = "display", uid = bobStock[1].uid, stand = 1 }) == ""
		and (function(): boolean
			H.rebuilt()
			return Warehouse.shown(2, 1) ~= nil and Warehouse.shown(2, 1):GetAttribute("Uid") == bobStock[1].uid and Warehouse.shown(1, 1):GetAttribute("Uid") == annStock[1].uid
		end)())
end

-- ── 9. The income ─────────────────────────────────────────────────────────

do
	local rate = Collection.incomePerMinute(ann)
	local market = Collection.market(ann) -- (8.3: a hot kind earns more)
	local expected = CollectionRules.income(annStock[1], 1, market) + CollectionRules.income(annStock[2], 1, market)
	check("9. her income a minute: the two pieces on show (CollectionRules.income, the market's)", rate > 0 and math.abs(rate - expected) < 1e-9, `{rate} vs {expected}`)
	S.rate = rate
	local incomeAt = #money
	local was = H.profileOf(ann).money
	local weekly = H.task(ann, "w_income")
	local weeklyWas = if weekly then weekly.progress else 0
	-- (60 s, or as long as two whole dollars take: 10.x the run's vault and locked rooms leave her the plainer pieces)
	local wait = math.max(60, math.ceil(120 / math.max(rate, 1e-3) / Config.Collection.Tick) * Config.Collection.Tick)
	E.advance(wait)
	local got = H.paid(ann, "CollectionIncome", incomeAt)
	check(`…{wait} s on the clock: paid as CollectionIncome at that rate (whole dollars; the payout every {Config.Collection.Tick} s)`,
		got > 0 and got >= math.floor(rate * (wait - 10) / 60) - 1 and got <= rate * (wait + 10) / 60 + 1 and H.profileOf(ann).money - was == got, `{got} at {rate}/min`)
	local only = true
	for index = incomeAt + 1, #money do
		if money[index].player == ann then
			only = only and money[index].reason == "CollectionIncome"
		end
	end
	check("…every dollar of it CollectionIncome; the analytics: FirstIncome once", only and H.steps(11).FirstIncome == 1)
	weekly = H.task(ann, "w_income")
	check("8.2 tasks: the weekly \"w_income\" counts what the stands paid", weekly ~= nil and weekly.progress - weeklyWas == got, weekly and `{weekly.progress - weeklyWas} vs {got}`)
end

-- 8.2 SandboxLeaders: the player list's columns and the TOP MOVERS board (Roblox replicates them: no remote)
do
	local Leaders = E.module("SandboxLeaders")
	local Rules = require("./SandboxLeadersRules")
	local L = Config.SandboxLeaders
	H.Leaders = Leaders
	local function columns(player: any): (any, string)
		local folder = player:FindFirstChild("leaderstats")
		if not folder then
			return nil, "no leaderstats"
		end
		local money, income, worth = folder:FindFirstChild(L.Stats.Money), folder:FindFirstChild(L.Stats.Income), folder:FindFirstChild(L.Stats.Collection)
		local profile = H.profileOf(player)
		local want = { math.floor(profile.money), Rules.perMinute(Collection.incomePerMinute(player)), math.floor(Rules.summary(Collection.stock(player)).value) }
		local got = { money and money.Value, income and income.Value, worth and worth.Value }
		local city = folder:FindFirstChild("Level") or folder:FindFirstChild("Money") or folder:FindFirstChild("Deliveries")
		return got[1] == want[1] and got[2] == want[2] and got[3] == want[3] and city == nil, `{got[1]}/{got[2]}/{got[3]} vs {want[1]}/{want[2]}/{want[3]}`
	end
	E.advance(L.Every + 0.1)
	local annOk, annSaid = columns(ann)
	local bobOk, bobSaid = columns(bob)
	check("8.2 leaders: Ann's player list says her $, $/min and collection worth (the city's columns gone)", annOk, annSaid)
	check("…Bob's too (his own numbers)", bobOk, bobSaid)
	local before = (ann:FindFirstChild("leaderstats") :: any):FindFirstChild(L.Stats.Money).Value
	PlayerData.addMoney(ann, 7, "Admin")
	E.advance(L.Every + 0.1)
	check("…a money change reaches the list within Every s", (ann:FindFirstChild("leaderstats") :: any):FindFirstChild(L.Stats.Money).Value
		== math.floor(H.profileOf(ann).money) and math.floor(H.profileOf(ann).money) >= before + 7)
	E.advance(L.BoardEvery + 0.1)
	local rows = Leaders.rows()
	local board = Leaders.board()
	check("…the TOP MOVERS board: both ranked by what their collection is worth, the top one's name on it", #rows == 2 and rows[1].value >= rows[2].value
		and rows[1].rank == 1 and board ~= nil and board:IsDescendantOf(workspace) and H.anyText(board, rows[1].name), `{#rows} rows`)
	S.annWorth = math.floor(Rules.summary(Collection.stock(ann)).value)
end

-- ── 10. UPGRADES ──────────────────────────────────────────────────────────

do
	local deskAt = Warehouse.terminal(1):FindFirstChild("Prompts")
	E.walk(ann, V3(deskAt.WorldPosition.X, WarehouseLayout.FloorTop + 3, deskAt.WorldPosition.Z + 3))
	local openAt = #E.sent
	local ok, why = E.trigger(deskAt:FindFirstChild("Upgrades"), ann)
	check("10. the UPGRADES desk opens her window (the state, then open)", ok and E.lastKind(ann, "Upgrades", "open", openAt) ~= nil
		and E.lastKind(ann, "Upgrades", "state", openAt) ~= nil, why)
	local poor = H.profileOf(ann).money
	local poorAt = #money
	local WP, SP = Config.SandboxUpgrades.List.warehouse.prices, Config.SandboxUpgrades.List.stands.prices -- (8.3 economy: Config's prices)
	local said = H.buy(ann, "stands", 1)
	check("NEG. 8.3: More stands in her garage: refused with the lock's reason (\"Needs the Big Warehouse\"), nothing taken, nothing changed", said == "Needs the Big Warehouse"
		and H.profileOf(ann).money - poor == H.paid(ann, "CollectionIncome", poorAt) and Upgrades.levels(ann).stands == nil and Collection.stands(ann) == WarehouseLayout.count(1), said)
	said = H.buy(ann, "warehouse", 1)
	check("NEG. the ZDC Warehouse (the Workshop) without the money: refused, nothing taken, nothing changed", poor < WP[1] and string.find(said, `costs {WarehouseLayout.money(WP[1])}`, 1, true) ~= nil
		and H.profileOf(ann).money - poor == H.paid(ann, "CollectionIncome", poorAt) and Upgrades.levels(ann).warehouse == nil and Warehouse.level(1) == 1, said)
	PlayerData.addMoney(ann, 250000, "Admin") -- (the admin panel's money button: PlayerData.addMoney; 8.3 economy: every level below)
	local rich = H.profileOf(ann).money
	local spentAt = #money
	local garage = Warehouse.model(1)
	H.buy(ann, "warehouse", 1)
	H.rebuilt()
	local function onTheirStands(): boolean -- (her two pieces on stands 1 and 2, at the spots of the level built now)
		local site = H.siteOf(1)
		for index = 1, 2 do
			local model = Warehouse.shown(1, index)
			local where = WarehouseLayout.stand(site, index)
			if not (model and model:GetAttribute("Uid") == annStock[index].uid and model:IsDescendantOf(Warehouse.model(1))
				and H.flat(model:GetPivot().Position, V3(where.x, 0, where.z)) < 0.1 and H.byUid(Collection.stock(ann), annStock[index].uid).stand == index) then
				return false
			end
		end
		return true
	end
	check(`8.3: …with the money: the Workshop bought ({WarehouseLayout.money(WP[1])}, the reason Upgrade): her plot rebuilt (a new Model at Level 2, the garage gone), 4 stands, WarehouseLevel 2`,
		Upgrades.levels(ann).warehouse == 1 and H.paid(ann, "Upgrade", spentAt) == -WP[1] and E.lastKind(ann, "Upgrades", "bought") ~= nil and Warehouse.model(1) ~= garage
			and not garage:IsDescendantOf(workspace) and Warehouse.model(1):IsDescendantOf(workspace) and Warehouse.level(1) == 2 and Warehouse.model(1):GetAttribute("Level") == 2
			and workspace:FindFirstChild("Warehouses"):GetAttribute("Level1") == 2 and Collection.stands(ann) == 4 and Warehouse.isOpen(1, 4)
			and ann:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute) == 2 and E.lastKind(ann, "Collection", "state").stands == 4)
	check("8.3: …her two pieces still on stands 1 and 2, standing at the Workshop's spots; the income the same", onTheirStands() and math.abs(Collection.incomePerMinute(ann) - S.rate) < 1e-9)
	E.advance(0.1)
	check("…the window's state shows the money left; the analytics' UpgradeBought; FirstUpgrade (step 10) waits for FirstSale (9): the funnel is in order",
		E.lastKind(ann, "Upgrades", "state").money == rich - WP[1] + H.paid(ann, "CollectionIncome", spentAt) and #H.events("UpgradeBought", ann) == 1 and H.steps(11).FirstUpgrade == nil)
	H.buy(ann, "warehouse", 2)
	H.buy(ann, "warehouse", 3)
	H.rebuilt()
	check("8.3: …the Storehouse, then the Big Warehouse (level 4, the warehouse of 8.0 – 8.2): 12 stands, her pieces on 1 and 2 at its spots",
		Upgrades.levels(ann).warehouse == 3 and Warehouse.level(1) == 4 and Collection.stands(ann) == 12 and Warehouse.isOpen(1, 12) and not Warehouse.isOpen(1, 13)
			and onTheirStands() and ann:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute) == 4 and H.paid(ann, "Upgrade", spentAt) == -(WP[1] + WP[2] + WP[3]))
	local deskNow = Warehouse.terminal(1):FindFirstChild("Prompts")
	E.walk(ann, V3(deskNow.WorldPosition.X, WarehouseLayout.FloorTop + 3, deskNow.WorldPosition.Z + 3))
	local againAt = #E.sent
	local deskOk, deskWhy = E.trigger(deskNow:FindFirstChild("Upgrades"), ann)
	check("8.3: …the rebuilt warehouse's UPGRADES desk: her prompt (the old desk's gone), it opens her window", deskOk and deskNow ~= deskAt and not deskAt:IsDescendantOf(workspace)
		and E.lastKind(ann, "Upgrades", "open", againAt) ~= nil, deskWhy)
	rich = H.profileOf(ann).money
	spentAt = #money
	H.buy(ann, "stands", 1)
	check(`…with the money: More stands 1 bought ({WarehouseLayout.money(SP[1])}, the reason Upgrade): 14 stands`, Upgrades.levels(ann).stands == 1 and Collection.stands(ann) == 14
		and H.profileOf(ann).money - rich == -SP[1] + H.paid(ann, "CollectionIncome", spentAt) and H.paid(ann, "Upgrade", spentAt) == -SP[1] and E.lastKind(ann, "Upgrades", "bought") ~= nil)
	H.rebuilt()
	check("…the warehouse opens stands 13 and 14 (15 still a painted spot); the collection's state says 14", Warehouse.isOpen(1, 13) and Warehouse.isOpen(1, 14)
		and not Warehouse.isOpen(1, 15) and E.lastKind(ann, "Collection", "state").stands == 14)
	check("…the income unchanged by stands alone", math.abs(Collection.incomePerMinute(ann) - S.rate) < 1e-9)
	local secondAt = #money
	H.buy(ann, "stands", 1)
	check("…a second click on the same card buys once", Upgrades.levels(ann).stands == 1 and H.paid(ann, "Upgrade", secondAt) == 0)
	local third = annStock[3]
	local fits = WarehouseLayout.fits(13, (FurnitureLooks.Items[third.item] :: any).size, 4) -- (the Big Warehouse's small 13)
	S.thirdOn13 = fits
	if fits then
		check("…the new stand 13 takes her third piece, its model there", H.request(ann, { kind = "display", uid = third.uid, stand = 13 }) == ""
			and (function(): boolean
				H.rebuilt()
				return Warehouse.shown(1, 13) ~= nil and Warehouse.shown(1, 13):GetAttribute("Uid") == third.uid
			end)())
	else
		check("…the new small stand 13 refuses her too-big third piece (Collection says which stands)",
			string.find(H.request(ann, { kind = "display", uid = third.uid, stand = 13 }), "too big", 1, true) ~= nil)
	end
	local before = Collection.incomePerMinute(ann)
	H.buy(ann, "lights", 1)
	H.rebuilt()
	local after = Collection.incomePerMinute(ann)
	check("…Showroom lights 1: the income × 1.1", Upgrades.levels(ann).lights == 1 and math.abs(after / before - 1.1) < 1e-6 and Collection.boost(ann) > 1.09,
		`{before} → {after}`)
	local tag = Warehouse.model(1):FindFirstChild("Stand1"):FindFirstChild("Tag")
	local boosted = CollectionRules.income(H.byUid(Collection.stock(ann), annStock[1].uid), Collection.boost(ann), Collection.market(ann))
	check("…the stand's tag shows the new $/min", H.anyText(tag, WarehouseLayout.money(boosted)) or H.anyText(tag, string.format("%.1f", boosted))
		or H.anyText(tag, tostring(math.floor(boosted * 10 + 0.5) / 10)), table.concat(H.textsOf(tag), " | "))
end

-- ── 11. Selling: at a stand, and the STOCK list's bulk buttons ────────────

do
	local entry = H.byUid(Collection.stock(ann), annStock[2].uid)
	local price = CollectionRules.sell(entry, Collection.market(ann)) -- (8.3: the market's price)
	local sellTask = H.task(ann, "sell")
	local sellWas = if sellTask then sellTask.progress else 0
	H.toStand(ann, plots[1], 2)
	local saleAt = #money
	local sentAt = #E.sent
	local ok = E.trigger(H.standPrompt(1, 2, "Sell"), ann) -- (hold F: its HoldDuration on the clock)
	H.rebuilt()
	local sold = E.lastKind(ann, "Collection", "sold", sentAt)
	check("11. Sell at stand 2: paid its price (CollectionSale), the sold message, out of her stock", ok and H.paid(ann, "CollectionSale", saleAt) == price
		and sold ~= nil and sold.money == price and #Collection.stock(ann) == 2, `{H.paid(ann, "CollectionSale", saleAt)} vs {price}`)
	check("…the stand empty again (its model gone, Display back); the analytics: FirstSale once, then the waiting FirstUpgrade, CollectionSold", Warehouse.shown(1, 2) == nil
		and H.standPrompt(1, 2, "Display").Enabled and H.steps(11).FirstSale == 1 and H.steps(11).FirstUpgrade == 1 and #H.events("CollectionSold", ann) == 1)
	sellTask = H.task(ann, "sell")
	check("8.2 tasks: \"sell\" counts the sale ($" .. price .. ")", sellTask ~= nil and sellTask.progress - sellWas == math.min(price, sellTask.target - sellWas),
		sellTask and `{sellTask.progress - sellWas}`)
	S.sellWas = sellWas

	-- ↩ TAKE ALL DOWN, 💰 SELL… duplicates (one more of her best piece's item, the admin's FILL STOCK: Collection.add), ⭐ FILL BEST
	local downAt = #E.sent
	E.advance(1.1) -- (Config.Robust.Limits.CollectionBulk)
	E.fire(ann, "Collection", { kind = "undisplayall" })
	local bulk = E.lastKind(ann, "Collection", "bulk", downAt)
	H.rebuilt()
	local up = 0
	for _, e in Collection.stock(ann) do
		up += if e.stand ~= nil then 1 else 0
	end
	check("8.2 bulk: TAKE ALL DOWN: every piece back in the stock, the stands empty", bulk ~= nil and bulk.action == "undisplayall" and up == 0
		and Warehouse.shown(1, 1) == nil and Collection.incomePerMinute(ann) == 0, bulk and bulk.count)
	local twin = Collection.add(ann, { item = annStock[1].item, variant = 1, condition = 0.5 })
	E.advance(0.2)
	local bookN = Book.book(ann)[annStock[1].item].n
	local pieces = {}
	local market = Collection.market(ann) -- (8.3: the market's prices, one piece after the other)
	for _, e in Collection.stock(ann) do
		local v = CollectionRules.view(e, Collection.boost(ann), market)
		table.insert(pieces, { uid = v.uid, item = v.item, stand = v.stand, got = v.got, rarity = v.rarity, income = v.income, price = v.price, broken = v.broken, condition = v.condition, base = v.base })
	end
	local plan = StockPlan.toSell(pieces, "duplicates")
	local planUids = {} -- (8.4 review: the confirm sends the pieces it listed; the server sells exactly those)
	for _, piece in plan do
		table.insert(planUids, piece.uid)
	end
	local staleAt = #E.sent
	E.advance(1.1)
	E.fire(ann, "Collection", { kind = "sellmany", filter = "duplicates", uids = { annStock[1].uid } })
	check("NEG. 8.4 review: SELL… listing a piece its filter does not take now (the best one, kept): refused, nothing sold", E.heard(ann, "stock changed", staleAt)
		and H.byUid(Collection.stock(ann), twin) ~= nil and H.byUid(Collection.stock(ann), annStock[1].uid) ~= nil)
	local saleAt2, sentAt2 = #money, #E.sent
	E.advance(1.1)
	E.fire(ann, "Collection", { kind = "sellmany", filter = "duplicates", uids = planUids })
	local soldMany = E.lastKind(ann, "Collection", "sold", sentAt2)
	check("8.2 bulk: SELL… duplicates sells the worse twin only, at the price the window shows (StockPlan)", #plan == 1 and plan[1].uid == twin
		and soldMany ~= nil and soldMany.count == 1 and soldMany.money == StockPlan.price(plan, market) and H.paid(ann, "CollectionSale", saleAt2) == StockPlan.price(plan, market)
		and H.byUid(Collection.stock(ann), twin) == nil and H.byUid(Collection.stock(ann), annStock[1].uid) ~= nil, soldMany and soldMany.money)
	check("…the book still counts both found (a sale takes nothing out of it)", Book.book(ann)[annStock[1].item].n == bookN and bookN == 2)
	sellTask = H.task(ann, "sell")
	check("8.2 tasks: \"sell\" counts the bulk sale too", sellTask ~= nil and sellTask.progress == math.min(sellTask.target, sellWas + price + StockPlan.price(plan, market)),
		sellTask and sellTask.progress)
	local refusedAt = #E.sent
	E.advance(1.1)
	E.fire(ann, "Collection", { kind = "sellmany", filter = "everything" })
	check("NEG. SELL… with a filter that isn't one: refused (nothing sold)", E.heard(ann, "Choose what to sell", refusedAt) and #Collection.stock(ann) == 2)
	local fillAt = #E.sent
	E.advance(1.1)
	E.fire(ann, "Collection", { kind = "fillbest" })
	H.rebuilt()
	local filled = E.lastKind(ann, "Collection", "bulk", fillAt)
	local onStands = 0
	for _, e in Collection.stock(ann) do
		onStands += if e.stand ~= nil then 1 else 0
	end
	check("8.2 bulk: FILL BEST puts both pieces up (the best first), their models on the stands", filled ~= nil and filled.action == "fillbest" and filled.count == 2
		and onStands == 2 and Warehouse.shown(1, H.byUid(Collection.stock(ann), annStock[1].uid).stand) ~= nil, filled and filled.count)
	local againAt = #E.sent
	E.advance(1.1)
	E.fire(ann, "Collection", { kind = "fillbest" })
	check("…again: nothing left to put up (refused, why)", E.lastKind(ann, "Collection", "bulk", againAt) == nil and E.lastNotice(ann, againAt) ~= "")
	if S.thirdOn13 then
		H.request(ann, { kind = "display", uid = annStock[3].uid, stand = 13 }) -- (back to the upgrade stand: the rejoin checks it)
		H.rebuilt()
	end
end

-- ── 12. The runs' ends: the tasks and the analytics ───────────────────────

do
	E.advance(0.5)
	local collectibles = 0
	for _, entry in annStock do
		local d = CollectionRules.defOf(entry.item)
		collectibles += if d and (d :: any).rarity then 1 else 0
	end
	-- (the twin the admin's FILL STOCK gave her came after her runs: never counted as found on one)
	check("12. 8.2 analytics: one CollectibleFound for every collectible her runs brought home (" .. collectibles .. ")",
		#H.events("CollectibleFound", ann) == collectibles, #H.events("CollectibleFound", ann))
	check("…her trucks gone, Danny gone; MoveDone, MoveFinished and MoveFinishedValue once a run (2), MoveGaveUp never", Vehicles.get(ann) == nil
		and MoveHelper.find(ann) == nil and #H.events("MoveDone", ann) == 2 and #H.events("MoveFinished", ann) == 2 and #H.events("MoveFinishedValue", ann) == 2
		and #H.events("MoveGaveUp", ann) == 0, `{#H.events("MoveDone", ann)} {#H.events("MoveFinished", ann)} {#H.events("MoveFinishedValue", ann)}`)
	local steps = H.steps(11)
	local once = true
	for index, step in Plan.SandboxSteps do
		once = once and steps[step.name] == 1
		local _ = index
	end
	check("8.2 analytics: Ann's ten funnel steps, each logged exactly once, in order", once, (function(): string
		local list = {}
		for _, step in Plan.SandboxSteps do
			table.insert(list, `{step.name}={steps[step.name] or 0}`)
		end
		return table.concat(list, " ")
	end)())
	local trips = H.task(ann, "trips")
	if trips and trips.done and not trips.claimed then
		local claimAt, paidAt = #E.sent, #money
		local slot = 0
		for index, row in Tasks.state(ann).daily do
			if row.id == "trips" then
				slot = index
			end
		end
		E.fire(ann, "SandboxTasks", { kind = "claim", slot = slot })
		check("8.2 tasks: the done \"trips\" claimed: its reward paid (SandboxTask), once", E.lastKind(ann, "SandboxTasks", "claimed", claimAt) ~= nil
			and H.paid(ann, "SandboxTask", paidAt) == trips.money and H.task(ann, "trips").claimed)
		E.advance(0.5)
		local twiceAt = #money
		E.fire(ann, "SandboxTasks", { kind = "claim", slot = slot })
		check("…claimed again: nothing more", H.paid(ann, "SandboxTask", twiceAt) == 0)
	end
	check("…Bob's run ended too (his piece home); nobody in a run", H.Runs.runOf(bob) == nil and H.Runs.runOf(ann) == nil and #Collection.stock(bob) == 1)
	E.advance(2)
end

-- ── 13. Leave and come back ───────────────────────────────────────────────

local ann2: any = nil
do
	local kept = Collection.stock(ann)
	local levels = Upgrades.levels(ann)
	local keptMoney = H.profileOf(ann).money
	local keptBook = Book.book(ann)
	local keptTasks = Tasks.state(ann)
	local keptAt = #money
	E.leave(ann)
	H.rebuilt()
	local save = E.saves["Player_11"]
	check("13. Ann leaves: her save written (the collection, the upgrades, the book, the tasks, each with its flag; the lock released)", save ~= nil
		and save.collectionKept == true and save.sandboxUpgradesKept == true and type(save.collection) == "table" and #save.collection.entries == #kept
		and save.lock == nil and save.sandboxUpgrades.stands == 1 and type(save.collectionBook) == "table" and type(save.sandboxTasks) == "table"
		and save.warehouseLevelKept == true and save.sandboxUpgrades.warehouse == 3) -- (8.3: her warehouse level with its flag)
	check("…with every dollar: what her stands earned up to the moment she left (Collection's leave payout before the leave save)",
		save ~= nil and save.money == keptMoney + H.paid(ann, "CollectionIncome", keptAt), save and `{save.money} vs {keptMoney} + {H.paid(ann, "CollectionIncome", keptAt)}`)
	check("…her plot is free (FOR RENT), her pieces leave the warehouse with her; 8.3: the garage again (FreeLevel)", SandboxPlots.owner(1) == nil and H.anyText(Warehouse.model(1), "FOR RENT")
		and Warehouse.shown(1, 1) == nil and Warehouse.level(1) == Config.Warehouse.FreeLevel)
	local joinAt = #money
	ann2 = E.join(11, "Ann")
	E.clients[ann2] = H.client(ann2)
	H.rebuilt()
	local back = Collection.stock(ann2)
	local same = #back == #kept
	for _, entry in kept do
		local b = H.byUid(back, entry.uid)
		same = same and b ~= nil and b.item == entry.item and b.stand == entry.stand and math.abs(b.condition - entry.condition) < 1e-9
	end
	check("…back: plot 1 again, her collection as it was (every uid, item, condition, stand: the upgrade stand too)", ann2:GetAttribute("Plot") == 1 and same,
		`{#back} vs {#kept}`)
	check("…her upgrades (14 stands, the lights) and her money", Upgrades.levels(ann2).stands == levels.stands and Upgrades.levels(ann2).lights == levels.lights
		and Collection.stands(ann2) == 14 and Collection.boost(ann2) > 1.09 and H.profileOf(ann2).money - save.money == H.paid(ann2, "CollectionIncome", joinAt))
	check("8.3: …her Big Warehouse again (her plot rebuilt at her saved level once the save loaded; no migration: the flag), WarehouseLevel 4",
		Upgrades.levels(ann2).warehouse == 3 and Warehouse.level(1) == 4 and Warehouse.model(1):GetAttribute("Level") == 4
			and ann2:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute) == 4 and H.anyText(Warehouse.model(1), "Ann"))
	local shownAll = true
	for _, entry in back do
		if entry.stand then
			local model = Warehouse.shown(1, entry.stand)
			shownAll = shownAll and model ~= nil and model:GetAttribute("Uid") == entry.uid
		end
	end
	check("…her pieces on their stands again", shownAll)
	local stateBack = E.lastKind(ann2, "Collection", "state")
	check("…her client hears it all again (14 stands, every piece)", stateBack ~= nil and stateBack.stands == 14 and #stateBack.stock == #kept)
	local bookBack = Book.book(ann2)
	local sameBook = bookBack ~= nil
	for item, found in keptBook do
		sameBook = sameBook and bookBack[item] ~= nil and bookBack[item].n == found.n
	end
	check("8.2 book: kept (every piece found, how often)", sameBook and E.lastKind(ann2, "CollectionBook", "state") ~= nil)
	local tasksBack = Tasks.state(ann2)
	local sameTasks = tasksBack ~= nil and #tasksBack.daily == #keptTasks.daily
	for index, row in keptTasks.daily do
		sameTasks = sameTasks and tasksBack.daily[index].id == row.id and tasksBack.daily[index].progress == row.progress and tasksBack.daily[index].claimed == row.claimed
	end
	check("8.2 tasks: kept (the same picks, their progress, the claims)", sameTasks)
	check("8.2 analytics: no funnel step logged twice for her (they are in her save)", (function(): boolean
		for _, n in H.steps(11) do
			if n ~= 1 then
				return false
			end
		end
		return true
	end)())
end

do
	check("9.7 …her runs' unlocks kept (runUnlocked 3: Hard open; the save's flag, no migration)", H.profileOf(ann2).runUnlocked == 3
		and E.saves["Player_11"].runUnlockedKept == true)
	E.fire(ann2, "Play")
	E.advance(1)
	check("…PLAY: no van in the lobby (her truck comes with her next run)", Vehicles.get(ann2) == nil)
	H.buy(ann2, "engine", 1)
	check("…Van engine 1 bought (her next truck wears it as it comes: step 20)", Upgrades.levels(ann2).engine == 1)
	H.buy(ann2, "danny", 1)
	check("…Danny's training 1: her player's DannyTraining (MoveHelper reads it)", ann2:GetAttribute(Config.SandboxUpgrades.Danny) == 1)
	E.advance(1)
	local carAt = #E.sent
	E.fire(ann2, "SpawnCar")
	E.advance(0.5)
	check("…CAR in the lobby: no van comes, said why", Vehicles.get(ann2) == nil and E.heard(ann2, "No vans in the lobby", carAt), E.lastNotice(ann2, carAt))
end

-- 8.3: the Logistics Center (the warehouse's top level): her plot rebuilt once more, every piece on its stand
do
	local before = Warehouse.model(1)
	local placed = {}
	for _, entry in Collection.stock(ann2) do
		if entry.stand then
			placed[entry.uid] = entry.stand
		end
	end
	local spentAt = #money
	local said = H.buy(ann2, "warehouse", 4)
	H.rebuilt()
	local site = H.siteOf(1)
	local kept, shown = next(placed) ~= nil, true
	for uid, at in placed do
		local model = Warehouse.shown(1, at)
		local where = WarehouseLayout.stand(site, at)
		kept = kept and H.byUid(Collection.stock(ann2), uid).stand == at
		shown = shown and model ~= nil and model:GetAttribute("Uid") == uid and H.flat(model:GetPivot().Position, V3(where.x, 0, where.z)) < 0.1
	end
	local topPrice = Config.SandboxUpgrades.List.warehouse.prices[4] -- (8.3 economy: Config's)
	check(`8.3: the Logistics Center bought ({WarehouseLayout.money(topPrice)}): a new Model at Level 5, 24 big stands + her More stands' 2, WarehouseLevel 5`, said == ""
		and H.paid(ann2, "Upgrade", spentAt) == -topPrice and Warehouse.model(1) ~= before and not before:IsDescendantOf(workspace) and Warehouse.level(1) == 5
		and Collection.stands(ann2) == 26 and Warehouse.isOpen(1, 26) and not Warehouse.isOpen(1, 27) and ann2:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute) == 5, said)
	check("8.3: …every piece still on its stand (the one on stand 13 too: a big stand there now), standing at the level's spots", kept and shown)
	local top = H.buy(ann2, "warehouse", 5)
	check("8.3: …the ZDC Warehouse at its top: refused, says so", top == "ZDC Warehouse is at its top level." and Warehouse.level(1) == 5, top)
end

-- ── 14. Bob cannot use Ann's stands or desk; a run of his own ───────────

do
	local first = Collection.stock(ann2)
	table.sort(first, function(a: any, b: any): boolean
		return (a.stand or 99) < (b.stand or 99)
	end)
	local stand = first[1].stand :: number
	H.toStand(bob, plots[1], stand)
	local heardAt = #E.sent
	E.trigger(H.standPrompt(1, stand, "TakeDown"), bob)
	E.advance(0.5)
	check("14. Bob at Ann's stand: Take down tells him whose warehouse it is, her piece stays", E.heard(bob, "This is Ann's warehouse.", heardAt)
		and H.byUid(Collection.stock(ann2), first[1].uid).stand == stand and Warehouse.shown(1, stand) ~= nil)
	heardAt = #E.sent
	local salesAt = #money
	local was = H.profileOf(ann2).money
	E.trigger(H.standPrompt(1, stand, "Sell"), bob)
	E.advance(0.5)
	check("…Sell: the same; nothing sold, nobody paid (her stands only earn)", E.heard(bob, "This is Ann's warehouse.", heardAt) and #Collection.stock(ann2) == #first
		and H.paid(ann2, "CollectionSale", salesAt) == 0 and H.paid(bob, "CollectionSale", salesAt) == 0
		and H.profileOf(ann2).money - was == H.paid(ann2, "CollectionIncome", salesAt) and E.lastKind(bob, "Collection", "sold", heardAt) == nil
		and E.lastKind(ann2, "Collection", "sold", heardAt) == nil)
	local empty = 1
	while Warehouse.shown(1, empty) ~= nil do
		empty += 1
	end
	heardAt = #E.sent
	H.toStand(bob, plots[1], empty)
	E.trigger(H.standPrompt(1, empty, "Display"), bob)
	E.advance(0.5)
	check("…an empty stand's Display: no picker for him (nor for her)", E.heard(bob, "This is Ann's warehouse.", heardAt) and E.lastKind(bob, "Collection", "pick", heardAt) == nil
		and E.lastKind(ann2, "Collection", "pick", heardAt) == nil)
	check("…her stands' prompts are hers (CargoOwner: the client hides them from him)", H.standPrompt(1, stand, "Sell"):GetAttribute("CargoOwner") == 11
		and H.standPrompt(1, empty, "Display"):GetAttribute("CargoOwner") == 11)
	local desk = Warehouse.terminal(1):FindFirstChild("Prompts")
	E.walk(bob, V3(desk.WorldPosition.X, WarehouseLayout.FloorTop + 3, desk.WorldPosition.Z + 3))
	heardAt = #E.sent
	E.trigger(desk:FindFirstChild("Upgrades"), bob)
	E.advance(0.5)
	check("…her UPGRADES desk: no window for him, her levels untouched", E.heard(bob, "This is Ann's warehouse.", heardAt)
		and E.lastKind(bob, "Upgrades", "open", heardAt) == nil and Upgrades.levels(ann2).stands == 1)
	-- 9.7: a run of his own from the lobby's pad (the Lone House's), Ann's things untouched; GIVE UP with nothing loaded
	E.advance(1.1)
	local lone = SandboxMap.Houses[3]
	local run = H.run({ bob }, lone.id)
	check("…Bob's next run (the Lone House's pad): his own, HIS truck at its curb; Ann in no run, no van of hers", run ~= nil and run.host == bob
		and run.house == lone.id and Vehicles.get(bob) ~= nil and H.flat(Vehicles.get(bob).chassis.Position, V3(lone.curb.x, 0, lone.curb.z)) < 0.5
		and Vehicles.get(ann2) == nil and H.Runs.runOf(ann2) == nil)
	E.fire(bob, "Moving", "giveup")
	E.advance(2)
	check("…GIVE UP with nothing loaded: called off, MoveGaveUp (how far: started), his run over", #H.events("MoveGaveUp", bob) == 1 and H.Runs.runOf(bob) == nil
		and Moving.busy(bob) == nil)
	H.backHome()
end

-- ── 14b. 8.7: trading between players ────────────────────────────────────

do
	local Rules = require("./PlayerTradeRules")
	local T = Config.PlayerTrade
	local shown = {}
	for _, entry in Collection.stock(ann2) do
		if entry.stand then
			table.insert(shown, entry)
		end
	end
	table.sort(shown, function(a: any, b: any): boolean
		return a.stand < b.stand
	end)
	local first = shown[1]
	H.profileOf(bob).money = 100000
	H.toStand(bob, plots[1], first.stand)
	local offerPrompt = H.standPrompt(1, first.stand, "MakeOffer")
	local pricePrompt = H.standPrompt(1, first.stand, "SetPrice")
	check("14b. Ann's piece on show: Make an offer for everybody else (tagged with her UserId: hidden from her), her own Set price (CargoOwner)",
		offerPrompt ~= nil and offerPrompt.Enabled == true and offerPrompt:GetAttribute(T.SellerAttribute) == 11 and offerPrompt:GetAttribute("CargoOwner") == nil
		and pricePrompt ~= nil and pricePrompt:GetAttribute("CargoOwner") == 11 and H.standPrompt(1, first.stand, "Buy").Enabled == false)
	local at = #E.sent
	local ok, why = E.trigger(offerPrompt, bob)
	E.advance(0.3)
	local compose = Rules.readPiece(E.lastKind(bob, "PlayerTrade", "compose", at))
	check("…Bob's Make an offer: the composer (the piece, its value, the bounds)", ok and compose ~= nil and compose.uid == first.uid and compose.seller == 11
		and compose.value == Rules.value(first), why)
	local price = Rules.presets((compose :: any).value)[3].price
	at = #E.sent
	local moneyAt = #money
	local annMoney, bobMoney = H.profileOf(ann2).money, H.profileOf(bob).money
	E.fire(bob, "PlayerTrade", { kind = "offer", seller = 11, uid = first.uid, stand = first.stand, price = price })
	E.advance(0.3)
	local card = E.lastKind(ann2, "PlayerTrade", "offer", at)
	check("…SEND: Ann's offer card (a player's) and her toast", card ~= nil and card.player == true and card.price == price and E.heard(ann2, "offers", at))
	E.fire(ann2, "PlayerTrade", { kind = "answer", id = card and card.id, accept = true })
	E.advance(0.5)
	local fee = Rules.fee(price)
	local bobHas = nil
	for _, entry in Collection.stock(bob) do
		if entry.item == first.item and entry.got >= first.got and entry.stand == nil then
			bobHas = entry
		end
	end
	check("…ACCEPT: the piece Bob's (in his stock), the money moved, the 8 % fee gone", H.byUid(Collection.stock(ann2), first.uid) == nil and bobHas ~= nil
		and H.paid(bob, "PlayerBuy", moneyAt) == -price and H.paid(ann2, "PlayerSale", moneyAt) == price and H.paid(ann2, "TradeFee", moneyAt) == -fee
		and H.profileOf(bob).money == bobMoney - price and H.profileOf(ann2).money - annMoney - H.paid(ann2, "CollectionIncome", moneyAt) == price - fee)
	H.rebuilt()
	check("…her stand free (no piece, no prompts for it)", Warehouse.shown(1, first.stand) == nil and offerPrompt.Enabled == false)
	-- the FOR SALE sign: Ann's Set price, the tag, Bob's Buy $X, its question, BUY
	local second = shown[2]
	if second then
		H.toStand(ann2, plots[1], second.stand)
		at = #E.sent
		E.trigger(H.standPrompt(1, second.stand, "SetPrice"), ann2)
		E.advance(0.3)
		local picker = Rules.readPiece(E.lastKind(ann2, "PlayerTrade", "pricing", at))
		local sign = Rules.clamp(Rules.value(second) * 2, Rules.value(second))
		E.fire(ann2, "PlayerTrade", { kind = "price", uid = second.uid, price = sign })
		H.rebuilt()
		local tag = Warehouse.model(1):FindFirstChild(`Stand{second.stand}`):FindFirstChild("Tag")
		local line = tag and tag:FindFirstChild("Back") and tag:FindFirstChild("Back"):FindFirstChild("Line3")
		local buy = H.standPrompt(1, second.stand, "Buy")
		check("…Ann's Set price: her picker; SET: the sign on her tag for everybody, Bob's Buy $X", picker ~= nil and picker.uid == second.uid
			and line ~= nil and line.Visible == true and line.Text == `🏷 FOR SALE {WarehouseLayout.money(sign)}` and buy.Enabled == true
			and buy.ActionText == `Buy {WarehouseLayout.money(sign)}`)
		H.toStand(bob, plots[1], second.stand)
		E.advance(0.5)
		at = #E.sent
		moneyAt = #money
		E.trigger(buy, bob)
		E.advance(0.3)
		local question = Rules.readPiece(E.lastKind(bob, "PlayerTrade", "confirm", at))
		E.fire(bob, "PlayerTrade", { kind = "buy", seller = 11, uid = second.uid, stand = second.stand, price = question and question.price })
		E.advance(0.5)
		check("…Bob's Buy $X: the question, BUY: the piece his, the sign's price paid", question ~= nil and question.price == sign
			and H.byUid(Collection.stock(ann2), second.uid) == nil and H.paid(bob, "PlayerBuy", moneyAt) == -sign and H.paid(ann2, "TradeFee", moneyAt) == -Rules.fee(sign))
		H.rebuilt()
	end
end

-- ── 15. A full server: the fifth player waits for a plot ──────────────────

local cid = E.join(33, "Cid")
local dee = E.join(44, "Dee")
local eve = E.join(55, "Eve")
E.clients[cid] = H.client(cid)
S.auto[cid] = true
do
	E.advance(3.5) -- (SandboxBoot's wait for a plot before it stands a body at the fallback)
	check("15. Cid and Dee get plots 3 and 4; Eve, the fifth, none", cid:GetAttribute("Plot") == 3 and dee:GetAttribute("Plot") == 4 and eve:GetAttribute("Plot") == nil
		and SandboxPlots.of(eve) == nil)
	local L = SandboxMap.Lobby
	check("…9.7 Eve stands in the lobby's plaza, its middle (SandboxBoot's spawn without a plot)", H.flat(E.rootOf(eve).Position, V3(L.spawn.x, 0, L.spawn.z)) < 1, E.rootOf(eve).Position)
	E.fire(eve, "Play")
	E.advance(1)
	check("…her PLAY: no van either", Vehicles.get(eve) == nil)
	check("…the upgrades refuse her (no warehouse of her own)", string.find(H.buy(eve, "danny", 1), "warehouse of your own", 1, true) ~= nil)
	local refusedAt = #E.sent
	local orchard = SandboxMap.Houses[6].id
	E.walk(eve, H.padAt(orchard))
	E.waitUntil(function(): boolean
		return E.heard(eve, "could not start", refusedAt)
	end, Config.Runs.Countdown + 2)
	E.walk(eve, H.groundAt(V3(L.spawn.x, 0, L.spawn.z)))
	check("…9.7 a run from a pad refused: no warehouse of her own (nowhere to bring the loot), told why; no truck left behind, the portal free", H.Runs.runOf(eve) == nil
		and E.heard(eve, "no warehouse", refusedAt) and Vehicles.get(eve) == nil and not H.Runs.inUse(orchard), E.lastNotice(eve, refusedAt))
	-- two pieces in her stock (the admin's FILL STOCK: Collection.add); her STOCK list (B) opens anywhere: its FILL BEST, and
	-- the picker's display through the remote
	Collection.add(eve, { item = "radio", condition = 1, variant = 1 })
	local toolbox = Collection.add(eve, { item = "toolbox", condition = 1, variant = 1 })
	E.advance(1.1)
	local fillAt = #E.sent
	E.fire(eve, "Collection", { kind = "fillbest" })
	local up = 0
	for _, entry in Collection.stock(eve) do
		up += if entry.stand ~= nil then 1 else 0
	end
	check("NEG. without a warehouse Eve's FILL BEST puts nothing on show (Collection.hasWarehouse, as Upgrades.buy asks for one)",
		up == 0 and E.lastNotice(eve, fillAt) ~= "", `{up} on show, {Collection.incomePerMinute(eve)}/min`)
	E.advance(1.1)
	E.fire(eve, "Collection", { kind = "undisplayall" })
	local said = H.request(eve, { kind = "display", uid = toolbox, stand = 1 })
	check("NEG. without a warehouse Eve cannot put a piece on show through the remote either (it would earn on a warehouse she has not got)",
		said ~= "" and Collection.incomePerMinute(eve) == 0, `"{said}", {Collection.incomePerMinute(eve)}/min`)
	E.leave(bob)
	H.rebuilt()
	check("…Bob leaves: his plot goes to Eve, who waited (8.0.1), its sign hers", eve:GetAttribute("Plot") == 2 and SandboxPlots.owner(2) == eve
		and H.anyText(Warehouse.model(2), "Eve"))
	local shown = Warehouse.shown(2, 1)
	check("…his piece left warehouse 2 with him", shown == nil or shown:GetAttribute("Uid") ~= S.bobUid)
	check("…the upgrades take her now (only the money says no)", string.find(H.buy(eve, "danny", 1), "costs", 1, true) ~= nil)
end

-- ── 16. A full warehouse at a run's end ───────────────────────────────────

do
	E.fire(cid, "Play")
	E.advance(1.1)
	local lodge = SandboxMap.Houses[4]
	local run = H.run({ cid }, lodge.id)
	local van = Vehicles.get(cid)
	check(`16. (Cid's run, from {lodge.name}'s pad)`, run ~= nil and van ~= nil and H.stateOf(cid) ~= nil and H.houseOf(cid) == lodge)
	local item = H.fetch(cid, van, function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	check("(Cid carries a piece out and loads it)", item ~= nil and H.itemOf(cid, item.spot).state == "truck", E.lastNotice(cid))
	local maxStock = Config.Collection.MaxStock
	Config.Collection.MaxStock = #Collection.stock(cid) -- (his warehouse full: Collection.add refuses)
	local tripAt = #E.sent
	local result = H.finishRun(cid, van)
	Config.Collection.MaxStock = maxStock
	check("…FINISH with a full warehouse: the piece could not be stored (said so), the warehouse full", #Collection.stock(cid) == 0
		and E.heard(cid, "could not be stored", tripAt) and E.heard(cid, "warehouse is full", tripAt), E.lastNotice(cid))
	check("…not in his book either (only what came into the stock)", next(Book.book(cid) or {}) == nil)
	check("…the results card: nothing came home (called off), the next difficulty not opened", result ~= nil and result.count == 0 and result.phase == "cancelled"
		and result.opened == nil and H.profileOf(cid).runUnlocked == Config.Runs.Open, result and `{result.count} {result.phase}`)
	H.backHome()
end

-- ── 17. Leaving mid-run, a piece in the truck ────────────────────────────

do
	E.fire(dee, "Play")
	E.clients[dee] = H.client(dee)
	S.auto[dee] = true
	E.advance(1.1)
	local cottage = SandboxMap.Houses[6]
	H.run({ dee }, cottage.id)
	local van = Vehicles.get(dee)
	local first = H.fetch(dee, van, function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	local result = H.finishRun(dee, van)
	check(`17. (Dee's first run on {cottage.name}: 1 piece in her stock)`, first ~= nil and result ~= nil and result.count == 1 and #Collection.stock(dee) == 1)
	H.backHome()
	H.run({ dee }, cottage.id)
	van = Vehicles.get(dee)
	local second = H.fetch(dee, van, function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	check("(her second run: a piece in her truck)", second ~= nil and H.itemOf(dee, second.spot).state == "truck")
	local interiors = 0
	for _, d in workspace:FindFirstChild("Moves"):GetChildren() do
		interiors += if d.ClassName == "Model" and E.interiorAt(d:GetPivot().Position) ~= nil then 1 else 0
	end
	local events = #E.analytics
	E.leave(dee)
	E.advance(Config.Moving.Fade + 1)
	local after = 0
	for _, d in workspace:FindFirstChild("Moves"):GetChildren() do
		after += if d.ClassName == "Model" and E.interiorAt(d:GetPivot().Position) ~= nil then 1 else 0
	end
	local save = E.saves["Player_44"]
	check("…Dee leaves mid-run: her run ends (its interior taken down, the slot free), Danny gone, the portal free", after == interiors - 1 and MoveHelper.find(dee) == nil
		and not H.Runs.inUse(cottage.id))
	check("9.7 …what was in her truck went home all the same: her save keeps both pieces", save ~= nil and #save.collection.entries == 2, save and #save.collection.entries)
	local finished = 0
	for index = events + 1, #E.analytics do
		local call = E.analytics[index]
		if call.method == "LogCustomEvent" and call.args[1] == dee and (call.args[2] == "MoveFinished" or call.args[2] == "MoveGaveUp") then
			finished += 1
		end
	end
	check("…the analytics: the run's end once (MoveFinished: pieces came home)", finished == 1, finished)
	local dee2 = E.join(44, "Dee")
	S.dee = dee2 -- (8.3: step 18's)
	H.rebuilt()
	check("…back: plot 4, her two pieces, no run (in the lobby)", dee2:GetAttribute("Plot") == 4 and #Collection.stock(dee2) == 2
		and H.stateOf(dee2) == nil and Moving.busy(dee2) == nil and H.Runs.runOf(dee2) == nil
		and SandboxMap.inLobby(E.rootOf(dee2).Position.X, E.rootOf(dee2).Position.Z))
end

-- 8.2 SandboxLeaders' all-time best: in its OrderedDataStore (at most every AllTime.Every s), only ever up
do
	local L = Config.SandboxLeaders.AllTime
	E.advance(L.Every + 1)
	local stored = (E.ordered[L.Store] or {})["11"]
	check("8.2 leaders: Ann's all-time best in the OrderedDataStore (a whole number, at least her worth at step 9, the server's best; not lowered by her sales)",
		type(stored) == "number" and stored >= S.annWorth and stored == H.Leaders.best(11), `{stored} vs {S.annWorth}, best {H.Leaders.best(11)}`)
end


-- ── 18. 8.3: the market ────────────────────────────────────────────────────

do
	local dee = S.dee
	local day = Market.dayOf(E.wall)
	local picks = Market.pick(day)
	local stateAt = #E.sent
	E.fire(dee, "Collection", { kind = "state" })
	local state = E.lastKind(dee, "Collection", "state", stateAt)
	check("18. the market: Dee's state carries today's hot and cold kinds (the day's picks, the same on every server)", state ~= nil and state.market ~= nil and state.market.day == day
		and table.concat(state.market.hot, ",") == table.concat(picks.hot, ",") and table.concat(state.market.cold, ",") == table.concat(picks.cold, ","))
	local hotKind = picks.hot[1] -- (furniture: the collectible comes last in the catalogue's order)
	local uid = Collection.add(dee, { item = hotKind, variant = 1, condition = 0.9 }) :: string -- (the admin's FILL STOCK way)
	E.advance(0.2)
	H.toStand(dee, plots[4], 2)
	E.advance(1.1)
	check("…a hot piece on stand 2 (the remote)", H.request(dee, { kind = "display", uid = uid, stand = 2 }) == "")
	H.rebuilt()
	local entry = H.byUid(Collection.stock(dee), uid)
	local market = Collection.market(dee)
	local hot = CollectionRules.income(entry, Collection.boost(dee), market)
	local tag = Warehouse.model(4):FindFirstChild("Stand2"):FindFirstChild("Tag")
	check(`…its stand's tag shows the hot income (× {Config.Market.HotIncome}: Warehouse's hook, Collection.marketIncome)`, math.abs(hot - CollectionRules.income(entry, Collection.boost(dee)) * Config.Market.HotIncome) < 1e-9
		and (H.anyText(tag, WarehouseLayout.money(hot)) or H.anyText(tag, string.format("%.1f", hot))), table.concat(H.textsOf(tag), " | "))
	local price = CollectionRules.sell(entry, market)
	local saleAt, sentAt = #money, #E.sent
	E.trigger(H.standPrompt(4, 2, "Sell"), dee)
	H.rebuilt()
	local sold = E.lastKind(dee, "Collection", "sold", sentAt)
	local events = H.events("CollectionSold", dee)
	local fields = events[#events] and events[#events][4]
	check(`…sold at the stand for the hot price (× {Config.Market.HotSell}), the analytics' CollectionSold says "hot"`, sold ~= nil and sold.money == price and H.paid(dee, "CollectionSale", saleAt) == price
		and price == math.floor(CollectionRules.sell(entry) * Config.Market.HotSell + 0.5) and type(fields) == "table" and fields.CustomField02 == "hot", `{price} {fields and fields.CustomField02}`)
	local after = Collection.market(dee) :: any
	check("…her demand for that kind: 1 sold today", after.demand[hotKind] ~= nil and after.demand[hotKind].n == 1 and after.demand[hotKind].sold == 1)
end

-- ── 19. 8.3: the PAINT shop ───────────────────────────────────────────────

do
	local dee = S.dee
	local booth: any = nil
	for _, d in workspace:FindFirstChild("Sandbox"):GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d:GetAttribute("PaintShop") == true then
			booth = d
		end
	end
	check("19. the PAINT shop: 9.7 the lobby's booth, its counter's \"Paint your truck\" (no van needed)", booth ~= nil and booth.Enabled == true
		and booth.ActionText == "Paint your truck" and SandboxMap.inLobby(E.promptAt(booth).X, E.promptAt(booth).Z))
	local stand = SandboxMap.Lobby.shops.paint.stand
	E.walk(dee, H.groundAt(V3(stand.x, 0, stand.z)))
	local sentAt = #E.sent
	local ok, why = E.trigger(booth, dee)
	check("…pressed there: the window opens (the state, then \"open\")", ok and E.lastKind(dee, "VanPaint", "state", sentAt) ~= nil and E.lastKind(dee, "VanPaint", "open", sentAt) ~= nil, why)
	PlayerData.addMoney(dee, 1000, "Admin")
	local paidAt = #money
	E.advance(0.5)
	E.fire(dee, "VanPaint", { kind = "buy", id = "white" })
	E.advance(0.1)
	check("…BUY Arctic white: $300 taken (the reason VanPaint), bought", H.paid(dee, "VanPaint", paidAt) == -300 and E.lastKind(dee, "VanPaint", "bought", sentAt) ~= nil)
	local run = H.run({ dee }, House.id)
	E.advance(Config.VanPaint.Prompt.Every + 0.1)
	local van = Vehicles.get(dee)
	check("…her next run's truck at the house wears it (VanPaint white, PaintColor)", run ~= nil and van ~= nil and van.model:GetAttribute("VanPaint") == "white"
		and van.model:GetAttribute("PaintColor") ~= nil, van and van.model:GetAttribute("VanPaint"))
	E.fire(dee, "Moving", "giveup")
	H.backHome()
end

-- ── 20. 8.3 the big move: the back door ────────────────────────────────────
-- Ann (back since step 13) on a new run of the farmstead at Hard (opened by her first run, kept in her save): the big
-- plan (Config.Furniture.Big) with its two ways out; round the house to its back door (House.back, the back wall: the
-- walk-in zone, the fade) to the corridor's east end inside, a piece out by that doorway, out behind the house facing
-- the garden, round to the truck's back, loaded, FINISH: Insane opened.
do
	E.advance(1.1)
	local R = Config.Runs
	local run = H.run({ ann2 }, House.id, "hard")
	local van = Vehicles.get(ann2)
	local F = Config.Moving.Sandbox.Houses[House.id]
	local view = H.stateOf(ann2)
	local hard = (require("./RunRules").def("hard") :: any)
	check("20. 9.7 Ann's run at Hard (open to her: her save's), the farmstead's clock × Hard's time (" .. hard.time .. ")", run ~= nil and run.difficulty == "hard"
		and view ~= nil and view.run.difficulty == "hard" and math.abs(view.endsAt - E.now - F.Time * hard.time) < 2, view and view.endsAt - E.now)
	check("…8.3: the big plan's pieces (Config.Furniture.Big.Spots and collectibles)", view ~= nil and view.counts.total >= Config.Furniture.Big.Spots[1], view and view.counts.total)
	check("…8.1 her truck wears Van engine 1 as it comes (SpeedMult 1.05: Upgrades tunes every van of hers)", van ~= nil
		and math.abs((van.model:GetAttribute("SpeedMult") or 0) - 1.05) < 1e-9, van and van.model:GetAttribute("SpeedMult"))
	check("(at the chalet's curb, the back open)", H.setBack(ann2, van, true), E.lastNotice(ann2))
	E.advance(R.Every)
	local out = H.yawLook(House.back.yaw)
	local backAt = V3(House.back.x, House.back.y + 3, House.back.z)
	local side = V3(House.house.x + House.house.sx / 2 + 8, 3, 0) -- (round the house's east side)
	E.walk(ann2, V3(side.X, 3, House.door.z - 4))
	E.walk(ann2, V3(side.X, 3, backAt.Z + 8))
	-- (8.3 walk-in doors: the back door's leaf, the map's BackLeaf, swings open as she walks up to it, before the fade)
	local backLeaf = S.backLeaf
	local backOpenAt: number? = nil
	local backOpening = backLeaf:GetAttributeChangedSignal("DoorOpen"):Connect(function()
		if backLeaf:GetAttribute("DoorOpen") == true and backOpenAt == nil then
			backOpenAt = E.clock
		end
	end)
	local fadeFrom = #E.sent
	E.walk(ann2, backAt + out * 8)
	local hallEnd = backAt - out * (Config.Moving.Doors.Hall.Depth - 1)
	local solidIn = H.solidOn(backAt + out * 8, hallEnd, 1)
	H.walkThrough(ann2, { hallEnd }) -- (8.5: on through it into its dark hall, no stop)
	local inside = E.waitUntil(function(): boolean
		return H.isInside(ann2)
	end, 3)
	backOpening:Disconnect()
	-- 8.5 walking through the back door as the front one: its way clear, the fade as her root crossed its threshold while
	-- she walked on, its leaf fully open before she got there, the move before the end of its dark hall
	do
		local D = Config.Moving.Doors
		local trip = S.trip[ann2]
		local along = if trip then (trip.at - backAt):Dot(out) else math.huge
		local speed = if trip then -trip.v:Dot(out) else 0
		local reach = if trip and speed > 0 then trip.clock + along / speed else 0
		local walked = if trip and trip.moved then along - speed * (trip.moved - trip.clock) else math.huge
		check("8.5 the back door walked through: its way in clear (nothing that collides from 8 studs out to its dark hall's end), the fade out as she crossed its threshold walking on",
			#solidIn == 0 and trip ~= nil and speed > E.walkSpeed(ann2) * 0.9 and along <= 2.5 and along >= -2, `{table.concat(solidIn, ", ")}; {along} out, {speed} studs/s`)
		check("…its leaf (BackLeaf) fully open before she reached it; the move before the end of its dark hall", backOpenAt ~= nil and (backOpenAt :: number) + D.Open + 0.15 <= reach
			and walked >= -(D.Hall.Depth - 0.5) and walked < 0, `{backOpenAt and reach - (backOpenAt :: number)} {walked}`)
	end
	local backFades = {}
	for _, args in E.received(ann2, "Moving", fadeFrom) do
		if args[1] == "fade" then
			table.insert(backFades, args[2])
		end
	end
	check("8.3 the back door's leaf (BackLeaf) swung open as she walked up to it, then the fade out and in, as the front door's", backOpenAt ~= nil
		and backFades[1] == "out" and backFades[2] == "in", table.concat(backFades, ", "))
	local origin = E.interiorAt(E.rootOf(ann2).Position)
	local exit2: any = nil
	for _, d in workspace:FindFirstChild("Moves"):GetChildren() do
		if d.Name == "LeaveDoor2" and origin and (d.Position - origin.Position).Magnitude < 400 then
			exit2 = d
		end
	end
	local into = E.rootOf(ann2).CFrame.LookVector
	check("…walked into the back door's zone: inside, by the corridor's east end (the plan's second way in), facing into the house",
		inside and exit2 ~= nil and H.flat(E.rootOf(ann2).Position, exit2.Position) < Config.Furniture.EntryIn + 1 and into.X < -0.9,
		E.rootOf(ann2).Position)
	S.into[ann2] = V3(into.X, 0, into.Z).Unit
	local here, view = E.rootOf(ann2).Position, H.stateOf(ann2)
	check("…in the house for her eyes and her sounds (the state's inside: SoundPlan.sandboxPlace \"house\")", view ~= nil and view.inside == true
		and SoundPlan.sandboxPlace(here.X, here.Y, here.Z, view.inside) == "house")
	local piece, model = H.choose(ann2, function(_i: any, d: any): boolean
		return d.class == "hand" and not d.fragile
	end)
	check("(a one-hand piece of the big plan in her hands)", piece ~= nil and H.pickUp(ann2, model), E.lastNotice(ann2))
	local door = exit2.Position - V3(0, 3.5, 0)
	local up = V3(0, Config.Furniture.EntryUp, 0)
	-- (8.3 walk-in doors: the interior's back door leaf, server/HouseInterior.luau's BackLeaf, swings open as she walks
	-- up to it inside)
	local innerLeaf: any = nil
	for _, d in workspace:GetDescendants() do
		if d.Name == "BackLeaf" and d:GetAttribute("DoorLeaf") ~= nil and H.flat(d.Position, exit2.Position) < 6 then
			innerLeaf = d
		end
	end
	local innerOpen = false
	local innerOpening = if innerLeaf then innerLeaf:GetAttributeChangedSignal("DoorOpen"):Connect(function()
		innerOpen = innerOpen or innerLeaf:GetAttribute("DoorOpen") == true
	end) else nil
	E.walk(ann2, door + S.into[ann2] * 5 + up)
	local porchStop = Config.Furniture.Wall + 6 - 0.5 -- (its porch's wall of daylight: 6 past the wall, the root half a stud off it)
	local solidOut = H.solidOn(door + S.into[ann2] * 5, door - S.into[ann2] * porchStop, 1)
	H.walkThrough(ann2, { door - S.into[ann2] * 5 + up }) -- (8.5: on through its doorway onto its porch, no stop)
	local outAgain = E.waitUntil(function(): boolean
		return not H.isInside(ann2)
	end, 3)
	if innerOpening then
		innerOpening:Disconnect()
	end
	do
		local trip = S.trip[ann2]
		local into = S.into[ann2]
		local along = if trip then (trip.at - door):Dot(into) else math.huge
		local speed = if trip then -trip.v:Dot(into) else 0
		local walked = if trip and trip.moved then along - speed * (trip.moved - trip.clock) else -math.huge
		check("8.5 …and out by it walking through: its way onto the porch clear, the fade out as she crossed its threshold inside with the piece, the move before the porch's end",
			#solidOut == 0 and trip ~= nil and speed > 0.5 * E.walkSpeed(ann2) and along <= 2.5 and along >= -2 and walked >= -porchStop and walked < 0,
			`{table.concat(solidOut, ", ")}; {along}, {speed} studs/s, {walked}`)
	end
	check("8.3 …the interior's back door leaf (BackLeaf: DoorLeaf 1, out onto its porch) swung open as she walked up to it", innerLeaf ~= nil and innerOpen
		and innerLeaf:GetAttribute("DoorLeaf") == 1 and innerLeaf:GetAttribute("DoorSwing") == -1)
	local at = E.rootOf(ann2).Position
	check("…carried out by the back door (walked into its doorway's zone inside): out behind the house, 4 south of the door, facing the garden, the piece with her",
		outAgain and math.abs(H.flat(at, V3(House.back.x, 0, House.back.z)) - 4) < 0.6 and E.rootOf(ann2).CFrame.LookVector.Z > 0.9
		and ann2.Character:GetAttribute("MoveCarry") == piece.spot, at)
	local outView = H.stateOf(ann2)
	check("…outdoors again for her eyes and her sounds", outView ~= nil and outView.inside ~= true and SoundPlan.sandboxPlace(at.X, at.Y, at.Z, false) == "outdoors")
	E.walk(ann2, V3(side.X, 3, backAt.Z + 8)) -- (round the house again, to the van)
	E.walk(ann2, V3(side.X, 3, House.door.z - 4))
	local loaded, why = H.loadAtBack(ann2, van)
	check("…loaded at the truck's back", loaded and H.itemOf(ann2, piece.spot).state == "truck", why or E.lastNotice(ann2))
	H.setBack(ann2, van, false)
	local before = #Collection.stock(ann2)
	local tripAt = #E.sent
	local result = H.finishRun(ann2, van)
	check("…FINISH: the piece in her stock; finished at Hard: Insane opened (runUnlocked 4)", #Collection.stock(ann2) == before + 1 and result ~= nil
		and result.count == 1 and result.opened == "insane" and E.lastKind(ann2, "Runs", "unlocked", tripAt) ~= nil and H.profileOf(ann2).runUnlocked == 4,
		result and result.opened)
	H.backHome()
end

-- ── 21. 9.7 a party run: the pad's line, the host, MaxParty, loads, LEAVE THE RUN, the vote ──
-- Eve (plot 2 since Bob left), Cid, Dee and Ann onto the Old Mill's pad: Eve the host (Easy and Normal open to her; Hard
-- refused), her pick; she steps off: Cid the host, the countdown going on; she steps back on: behind the others. Fay, a
-- sixth player (no plot), steps on fifth: MaxParty (4) go, she stays (IN USE). In the run: everybody in the mill's front
-- yard, one truck (the host's); Dee, Ann and Eve each load a piece; Eve LEAVEs THE RUN alone (back to the lobby, her
-- piece still in the truck); Dee's vote, then Ann's: the run ends; each piece in its loader's stock (Eve's too), every one
-- of them a results card, Hard opened for the host who had it locked (not for Eve, who left).
do
	local R = Config.Runs
	local Runs = H.Runs
	local mill = SandboxMap.Houses[5]
	local dee = S.dee
	local fay = E.join(66, "Fay")
	E.advance(4) -- (SandboxBoot's wait for a plot: none for her, then the plaza)
	for _, p in { ann2, cid, dee, eve, fay } do
		E.clients[p] = H.client(p)
		S.auto[p] = true
	end
	-- (each a few studs off the pad: they step on one after the other within the countdown)
	local pad = (SandboxMap.portal(mill.id) :: any).pad
	local pmid = V3((pad.x0 + pad.x1) / 2, 3, (pad.z0 + pad.z1) / 2)
	local beside = V3(pad.x1 + 6, 3, pmid.Z) -- (east of it: the plaza's side)
	for n, p in { eve, cid, dee, ann2, fay } do
		E.place(p, beside + V3(n * 1.5, 0, 0))
	end
	E.advance(R.Every * 3)
	local before = { eve = H.profileOf(eve).runUnlocked, cid = H.profileOf(cid).runUnlocked, dee = H.profileOf(dee).runUnlocked, ann = H.profileOf(ann2).runUnlocked }
	local padAt = #E.sent
	E.walk(eve, pmid)
	E.advance(R.Every + 0.05)
	E.walk(cid, pmid + V3(2, 0, 2))
	E.walk(dee, pmid + V3(-2, 0, 2))
	E.walk(ann2, pmid + V3(2, 0, -2))
	E.advance(R.Every + 0.05)
	local eveView, cidView = E.lastKind(eve, "Runs", "pad", padAt), E.lastKind(cid, "Runs", "pad", padAt)
	check("21. the Old Mill's pad: Eve first (the host: hers to pick), Cid, Dee and Ann behind her in the line, one countdown", eveView ~= nil and eveView.mine == true
		and eveView.place == 1 and cidView ~= nil and cidView.mine == false and cidView.place == 2 and cidView.host == eve.UserId and #Runs.padOf(mill.id).order == 4
		and table.concat(eveView.open, ",") == "easy,normal", eveView and eveView.place)
	local lockedAt = #E.sent
	E.advance(0.3)
	E.fire(eve, "Runs", { kind = "difficulty", id = "insane" })
	E.advance(0.3)
	check("NEG. …Eve's Insane (locked for her): refused, the pad still Normal", E.heard(eve, "Finish a run", lockedAt) and Runs.padOf(mill.id).difficulty == "normal")
	E.fire(ann2, "Runs", { kind = "difficulty", id = "insane" })
	E.advance(0.3)
	check("NEG. …Ann's Insane (open to her, but she is not the host): nothing", Runs.padOf(mill.id).difficulty == "normal")
	local endsAt = Runs.padOf(mill.id).endsAt
	E.walk(eve, beside + V3(-1, 0, 0))
	E.advance(R.Every + 0.05)
	check("Eve steps off: Cid is the host now (his panel says so), the countdown goes on, Normal (open to him)", Runs.padOf(mill.id).host == cid.UserId
		and E.lastKind(cid, "Runs", "pad").mine == true and Runs.padOf(mill.id).endsAt == endsAt and Runs.padOf(mill.id).difficulty == "normal"
		and E.lastKind(eve, "Runs", "pad").house == nil)
	E.walk(eve, pmid + V3(-2, 0, -2))
	E.walk(fay, pmid)
	E.advance(R.Every + 0.05)
	local fayView = E.lastKind(fay, "Runs", "pad")
	check(`…Eve back on it: at the end of the line (4th); Fay 5th: {R.MaxParty} go, she waits (her panel: place 5)`, table.concat(Runs.padOf(mill.id).order, ",")
		== `{cid.UserId},{dee.UserId},{ann2.UserId},{eve.UserId},{fay.UserId}` and fayView ~= nil and fayView.place == 5 and fayView.going == R.MaxParty,
		table.concat(Runs.padOf(mill.id).order, ","))
	local started = E.waitUntil(function(): boolean
		return Runs.runOf(cid) ~= nil
	end, R.Countdown + 1)
	local inUseAt = #E.sent
	E.advance(R.Fade.Out + 0.3)
	local run = Runs.runOf(cid)
	local van = Vehicles.get(cid)
	local zone = SandboxMap.zone(mill.id) :: SandboxMap.Zone
	local landed = true
	for _, p in { cid, dee, ann2, eve } do
		landed = landed and Runs.runOf(p) ~= nil and SandboxMap.zoneAt(E.rootOf(p).Position.X, E.rootOf(p).Position.Z) == zone
			and H.flat(E.rootOf(p).Position, V3(zone.arrive.x, 0, zone.arrive.z)) <= R.Apart * 2 + 0.5
	end
	check("…the countdown over: the four in the run (Cid the host, Normal), all four in the mill's front yard by its door, apart; Fay not", started and run ~= nil
		and run.host == cid and #run.party == 4 and run.difficulty == "normal" and landed and Runs.runOf(fay) == nil
		and SandboxMap.inLobby(E.rootOf(fay).Position.X, E.rootOf(fay).Position.Z))
	E.advance(R.Every * 2)
	check("NEG. …Fay, still on the pad: IN USE (told), no run of her own", E.heard(fay, "is in use", inUseAt) and Runs.runOf(fay) == nil and Moving.busy(fay) == nil)
	E.walk(fay, beside + V3(8, 0, 0)) -- (off the pad)
	check("…one truck, the host's, at the mill's curb; the move one for all four (its crew), each sees its state", van ~= nil and Vehicles.get(dee) == nil
		and H.flat(van.chassis.Position, V3(mill.curb.x, 0, mill.curb.z)) < 0.5 and H.stateOf(dee) ~= nil and H.stateOf(dee).id == H.stateOf(cid).id
		and H.stateOf(eve).id == H.stateOf(cid).id and E.lastKind(ann2, "Runs", "run").members == 4)
	check("(Cid opens the truck's back)", H.setBack(cid, van, true), E.lastNotice(cid))
	local loads: { [string]: any } = {}
	for _, p in { dee, ann2, eve } do
		local ok = H.enterHouse(p)
		local item, model = H.choose(p, function(_i: any, d: any): boolean
			return d.class ~= "pair"
		end)
		if ok and item and H.pickUp(p, model) and H.leaveHouse(p) and (H.loadAtBack(p, van)) then
			loads[p.Name] = item
		end
	end
	check("…Dee, Ann and Eve each carry a piece out and load it into the truck", loads.Dee ~= nil and loads.Ann ~= nil and loads.Eve ~= nil
		and H.itemOf(cid, loads.Dee.spot).state == "truck" and H.itemOf(cid, loads.Ann.spot).state == "truck" and H.itemOf(cid, loads.Eve.spot).state == "truck",
		`{loads.Dee ~= nil} {loads.Ann ~= nil} {loads.Eve ~= nil}: {E.lastNotice(dee)} | {E.lastNotice(ann2)} | {E.lastNotice(eve)}`)
	local stocks = { dee = #Collection.stock(dee), ann = #Collection.stock(ann2), eve = #Collection.stock(eve), cid = #Collection.stock(cid) }
	local leaveAt = #E.sent
	E.advance(0.3)
	E.fire(eve, "Runs", { kind = "leave" })
	E.advance(0.5)
	check("LEAVE THE RUN: Eve out of it alone (told; her run view gone), the others still in it", Runs.runOf(eve) == nil and E.heard(eve, "You leave the run", leaveAt)
		and E.lastKind(eve, "Runs", "run", leaveAt) ~= nil and E.lastKind(eve, "Runs", "run", leaveAt).house == nil and Runs.runOf(cid) ~= nil and #Runs.runOf(cid).party == 3
		and E.heard(dee, "Eve left the run", leaveAt))
	E.advance(R.LeaveHold + R.Fade.Out + 0.5)
	local portal = SandboxMap.portal(mill.id) :: SandboxMap.Portal
	check("…LeaveHold s later she is back in the lobby by the mill's portal; her piece still in the truck", H.flat(E.rootOf(eve).Position, V3(portal.back.x, 0, portal.back.z)) < 0.5
		and H.itemOf(cid, loads.Eve.spot).state == "truck")
	local voteAt = #E.sent
	E.fire(dee, "Runs", { kind = "vote" })
	E.advance(0.5)
	check("Dee votes to finish: 1 of 2 (Ann not yet), everybody told; the run goes on", Runs.runOf(cid) ~= nil and E.heard(cid, "wants to finish (1/2", voteAt)
		and E.lastKind(dee, "Runs", "run").voted == true)
	local endAt = #E.sent
	E.fire(ann2, "Runs", { kind = "vote" })
	E.advance(0.5)
	check("…Ann's vote too: the party voted, the run over for all", Runs.runOf(cid) == nil and Runs.runOf(dee) == nil and Runs.runOf(ann2) == nil and Moving.busy(cid) == nil)
	check("…each piece in its loader's stock: Dee's to Dee, Ann's to Ann, Eve's to Eve (she left the run, not the game); nothing to Cid",
		#Collection.stock(dee) == stocks.dee + 1 and #Collection.stock(ann2) == stocks.ann + 1 and #Collection.stock(eve) == stocks.eve + 1 and #Collection.stock(cid) == stocks.cid,
		`{#Collection.stock(dee) - stocks.dee} {#Collection.stock(ann2) - stocks.ann} {#Collection.stock(eve) - stocks.eve} {#Collection.stock(cid) - stocks.cid}`)
	local cards = {}
	for _, p in { cid, dee, ann2, eve } do
		cards[p.Name] = E.lastKind(p, "Runs", "result", endAt)
	end
	check("…a results card for every one of them (Eve's too): 3 pieces, who got each, yours apart (Cid's none, Dee's one)", cards.Cid ~= nil and cards.Dee ~= nil
		and cards.Ann ~= nil and cards.Eve ~= nil and cards.Cid.count == 3 and cards.Cid.mine == 0 and cards.Dee.mine == 1 and cards.Ann.mine == 1 and cards.Eve.mine == 1
		and cards.Cid.phase == "done" and string.find(cards.Cid.why, "voted", 1, true) ~= nil, cards.Cid and `{cards.Cid.count} {cards.Cid.phase}`)
	check("…finished at Normal: Hard opened for Cid (his first), nothing new for Dee and Ann (open already), nothing for Eve (she left)",
		H.profileOf(cid).runUnlocked == 3 and before.cid == 2 and cards.Cid.opened == "hard" and H.profileOf(dee).runUnlocked == before.dee
		and H.profileOf(ann2).runUnlocked == before.ann and H.profileOf(eve).runUnlocked == before.eve and cards.Eve.opened == nil)
	H.backHome()
	local home = true
	for _, p in { cid, dee, ann2 } do
		home = home and SandboxMap.inLobby(E.rootOf(p).Position.X, E.rootOf(p).Position.Z)
	end
	check("…EndHold s later: the three back in the lobby by the mill's portal, the truck gone, the portal free", home and Vehicles.get(cid) == nil and not Runs.inUse(mill.id))
	S.fay = fay
end

-- ── 22. 9.7 the clock runs out ─────────────────────────────────────────────

do
	local R = Config.Runs
	local lone = SandboxMap.Houses[3]
	local run = H.run({ cid }, lone.id, "hard")
	local van = Vehicles.get(cid)
	local view = H.stateOf(cid)
	local hard = (require("./RunRules").def("hard") :: any)
	check(`22. Cid's run at Hard (opened by step 21): {lone.name}'s clock × Hard's time`, run ~= nil and run.difficulty == "hard" and view ~= nil
		and math.abs(view.endsAt - E.now - Config.Moving.Sandbox.Houses[lone.id].Time * hard.time) < 2, view and view.endsAt - E.now)
	local item = H.fetch(cid, van, function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	check("(a piece in his truck)", item ~= nil and H.itemOf(cid, item.spot).state == "truck")
	local had = #Collection.stock(cid)
	check("(the admin's SKIP CLOCK: a minute left)", string.find(Moving.admin(cid, "time"), "minute", 1, true) ~= nil)
	local endAt = #E.sent
	E.advance(62)
	local card = E.lastKind(cid, "Runs", "result", endAt)
	check("…the clock runs out: the run ends by itself (late), what was in the truck went home", H.Runs.runOf(cid) == nil and #Collection.stock(cid) == had + 1
		and card ~= nil and card.phase == "late" and string.find(card.why, "Time's up", 1, true) ~= nil and card.count == 1, card and card.phase)
	check("…late is finished too: Insane opened for him", H.profileOf(cid).runUnlocked == 4 and card ~= nil and card.opened == "insane")
	H.backHome()
	E.advance(R.Every)
end

-- ── 23. 9.7 the host leaves the game mid-run ──────────────────────────────

do
	local cabin = SandboxMap.Houses[2]
	local dee = S.dee
	local pad = (SandboxMap.portal(cabin.id) :: any).pad
	local pmid = V3((pad.x0 + pad.x1) / 2, 3, (pad.z0 + pad.z1) / 2)
	E.place(dee, pmid + V3(pad.x1 - pmid.X + 4, 0, 0))
	E.place(ann2, pmid + V3(pad.x1 - pmid.X + 6, 0, 0))
	E.advance(0.3)
	local run = H.run({ dee, ann2 }, cabin.id)
	local van = Vehicles.get(dee)
	check(`23. Dee's run on {cabin.name} with Ann in her party`, run ~= nil and run.host == dee and #run.party == 2 and van ~= nil)
	check("(Dee opens the back)", H.setBack(dee, van, true))
	local ok = H.enterHouse(ann2)
	local item, model = H.choose(ann2, function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	check("(Ann loads a piece)", ok and item ~= nil and H.pickUp(ann2, model) and H.leaveHouse(ann2) and (H.loadAtBack(ann2, van)) and H.itemOf(ann2, item.spot).state == "truck")
	local had = #Collection.stock(ann2)
	local leftAt = #E.sent
	E.leave(dee)
	E.advance(0.5)
	local card = E.lastKind(ann2, "Runs", "result", leftAt)
	check("Dee (the host) leaves the game: the run ends for Ann (told: the host left), her piece in HER stock, her results card", H.Runs.runOf(ann2) == nil
		and E.heard(ann2, "the host) left", leftAt) and #Collection.stock(ann2) == had + 1 and card ~= nil and card.count == 1 and card.mine == 1, card and card.count)
	H.backHome()
	check("…EndHold s later Ann is back in the lobby, the Pond Cabin's portal free", SandboxMap.inLobby(E.rootOf(ann2).Position.X, E.rootOf(ann2).Position.Z)
		and not H.Runs.inUse(cabin.id))
end

-- ── The run ───────────────────────────────────────────────────────────────

do
	check("no script error in any thread (E.errors)", #E.errors == 0, table.concat(E.errors, "\n"))
	local seen: { [string]: boolean } = {}
	local lines: { string } = {}
	for _, line in E.warnings do
		if not seen[line] then
			seen[line] = true
			table.insert(lines, line)
		end
	end
	if #lines > 0 then
		print("warnings (" .. #E.warnings .. ", " .. #lines .. " different):")
		for index = 1, math.min(#lines, 20) do
			print("  " .. lines[index])
		end
	end
	local unknown = {}
	for name in E.unknownServices do
		table.insert(unknown, name)
	end
	if #unknown > 0 then
		print("services the stand-in does not know (permissive): " .. table.concat(unknown, ", "))
	end
	print(string.format("simulated %.0f s of play", E.clock - 100))
	if #todos > 0 then
		print(`{#todos} TODO(bug) check(s) kept: {table.concat(todos, " | ")}`)
	end
	if failures == 0 then
		print("ALL CHECKS PASSED")
	else
		print(`{failures} CHECK(S) FAILED`)
	end
end
