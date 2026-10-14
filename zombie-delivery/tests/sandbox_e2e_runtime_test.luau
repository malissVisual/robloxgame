-- 8.2 e2e: the whole SANDBOX loop with the REAL modules together, for two players at once (and three more at the end).
-- tests/run_tests.py stages the real server modules SandboxE2E lists in E.real (SandboxBoot, SandboxWorld, HouseMesh,
-- PlayerData, SandboxPlots, Collection, CollectionBook, Warehouse with WarehouseMesh, Upgrades, SandboxTasks, SandboxLeaders,
-- Analytics, SandboxAnalytics, Moving with MoveLobby, MoveHelper, MoveGreeters, PairHold and MoveSites, HouseInterior,
-- FurnitureMesh) and
-- shared/Net.luau on tests/runtime/SandboxE2E.luau's Roblox stand-in: only Roblox (its services, AnalyticsService
-- recorded) and the physics-heavy modules (Vehicles, Zombies, Npcs, Crew, Hand) are mocked; see its header. The clock is
-- the test's: the modules' own loops run (the moves' tick, the doors, Danny, the lobby, the payouts, the tasks, the
-- autosave).
--   0. The real boot (SandboxBoot.start): the map, the services, the plots, the warehouses, the moves; no Baseplate.
--   1. Ann and Bob join: plots 1 and 2, a new sandbox save each ($500), their warehouses' signs, the states.
--   2. PLAY: the van at the plot's vanSpot (its back doors in the unload circle), you at the spawn.
--   3. The contract at your plot's kiosk, START (the lobby), LAUNCH: two moves at once (two houses, two interiors),
--      Danny for each (told to wait at the van). Bob at Ann's kiosk gets only his own card.
--   4. The van to the chalet's curb, the back doors open, the front door's walk-in zone: the dwell, the fade, inside.
--   5. A sturdy two-hands piece through the grip lift check: a crew mate's answer does nothing, a forged "ok" is a miss
--      (a knock), the client's "ok" with a good press time lifts it balanced; a wobble answered (steady), one missed (a
--      stagger).
--   6. Out through the doorway, loaded at the back doors; a one-hand piece loaded from inside the walk-in bay.
--   7. Home: no trip at another player's plot; backed into your circle: trip 1 (Collection.add: item, variant, condition,
--      name: the very look the piece had), into the book; trip 2 nose-in. Bob: a death mid-carry, the respawn by his
--      van, his trip.
--   8. The warehouse: Display opens the picker, the client's display, the stand's model and tag; a move to another
--      stand, Take down; the refusals (a stand you haven't got, junk, a taken stand, another player's piece).
--   9. 60 s on the clock: the income (CollectionIncome). The player list's $ / $/min / collection, the TOP MOVERS board.
--  10. UPGRADES: without the money refused; More stands (14), the new stand 13 shows a piece; Showroom lights (× 1.1).
--  11. Sell at the stand (hold F); the bulk buttons: TAKE ALL DOWN, SELL… (duplicates; nothing else to sell), FILL BEST.
--  12. FINISH: the result card says what came home; the daily tasks counted the trips, the sales and the income (a done
--      one claimed); the analytics' funnel steps fired once each, the moves' events.
--  13. Ann leaves and comes back: the collection on its stands, the upgrades, the book, the tasks, every dollar; the
--      engine on her van and on one CAR brings later; Danny's training.
--  14. Bob cannot use Ann's stands or desk; her kiosk opens only his own move.
--  15. A full server: the fifth player waits for a plot, gets Bob's when he leaves.
--  16. A full warehouse at a trip.
--  17. Leaving mid-move with a piece in the van; coming back. Last: the all-time best in its OrderedDataStore.
--  18. 8.3 the market: the state carries the day's hot and cold kinds; a hot piece on a stand: its tag shows the hot
--      income (Warehouse's hook), sold at the stand for the hot price, the analytics' "hot". Every price and income the
--      steps above expect is the market's (CollectionRules / StockPlan with Collection.market): any day passes.
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
	check("…the map (workspace.Sandbox), the four warehouses, a kiosk on every plot, the Cars folder; no Baseplate", workspace:FindFirstChild("Sandbox") ~= nil
		and warehouses ~= nil and #warehouses:GetChildren() == 4 and moves ~= nil and moves:FindFirstChild("MovingBoard1") ~= nil
		and moves:FindFirstChild("MovingBoard4") ~= nil and workspace:FindFirstChild("Cars") ~= nil and rawget(baseplate, "destroyed") == true)
	local door: any = nil
	for _, d in workspace:GetDescendants() do
		if d:GetAttribute("SandboxDoor") then
			door = d
		end
	end
	check("…the chalet's front door (SandboxDoor) where SandboxMap puts it", door ~= nil and V3(door.Position.X - House.door.x, 0, door.Position.Z - House.door.z).Magnitude < 2)
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
function H.play(player: any): any
	E.fire(player, "Play")
	E.advance(1)
	return Vehicles.get(player)
end
function H.doorOf(van: any): any
	return van.chassis:FindFirstChild("CargoDoor")
end
function H.inCircle(at: any, plot: any): boolean
	return H.flat(at, V3(plot.unload.x, 0, plot.unload.z)) <= plot.unload.r
end
function H.kiosk(plot: any): (any, any)
	local model = workspace:FindFirstChild("Moves"):FindFirstChild(`MovingBoard{plot.id}`)
	return model:FindFirstChild("Board"), E.promptIn(model, "Moving contracts")
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
-- Walks to a plot's kiosk and uses its "Moving contracts" prompt: the card (or nil), the prompt's ok and why.
function H.takeContract(player: any, plot: any): (any, boolean, string?)
	local board, prompt = H.kiosk(plot)
	local before = #E.sent
	E.walk(player, H.groundAt(board.Position + V3(0, 0, 4)))
	local ok, why = E.trigger(prompt, player)
	local card = E.lastOf(player, "Moving", "contract", before)
	return card and card[2], ok, why
end
-- START, LAUNCH (solo) and Danny told to wait at the van.
function H.launch(player: any)
	E.fire(player, "Moving", "start", House.id)
	E.fire(player, "MoveLobby", "launch")
	E.advance(0.5)
	E.fire(player, "Moving", "helper", "van") -- (8.3: WAIT AT VAN, his command card's)
end
-- The van's middle along the roads: out of the plot, Depot Row, Main Street, round the turnaround to the curb, backed
-- toward the chalet's door (its nose north).
function H.toHouse(plot: any): { any }
	return {
		{ x = plot.vanSpot.x, z = -60, yaw = 180 },
		{ x = 0, z = -60, yaw = 270 },
		{ x = 0, z = 466, yaw = 180 },
		{ x = 14, z = 480, yaw = 90 },
		{ x = House.curb.x, z = House.curb.z, yaw = House.curb.yaw },
	}
end
-- Home: Main Street north, Depot Row to the plot, then backed in (nose south, the back doors to the roller door) or
-- nose-in (nose north).
function H.toPlot(plot: any, noseIn: boolean): { any }
	return {
		{ x = 0, z = 470, yaw = 0 },
		{ x = 0, z = -60, yaw = 0 },
		{ x = plot.vanSpot.x, z = -60, yaw = if plot.vanSpot.x < 0 then 90 else 270 },
		if noseIn then { x = plot.unload.x, z = plot.unload.z + 8, yaw = 0 } else { x = plot.vanSpot.x, z = plot.vanSpot.z, yaw = 180 },
	}
end
function H.behindVan(van: any, out: number): any
	local back = van.chassis.CFrame:PointToObjectSpace(H.doorOf(van).WorldPosition)
	return H.groundAt(van.chassis.CFrame * V3(0, 0, back.Z + out))
end
function H.drive(player: any, van: any, points: { any })
	E.seat(player, van)
	E.drive(van, points, 45)
	E.unseat(player)
	E.advance(0.3)
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
-- Walks up to the chalet's front door and stands in its zone facing it: the dwell, the fade, inside.
function H.enterHouse(player: any): boolean
	local facing = H.yawLook(House.door.yaw)
	local door = V3(House.door.x, House.door.y + 3, House.door.z)
	E.walk(player, door + facing * 6)
	E.walk(player, door + facing * 1.5)
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
-- Walks out by the interior's front-door way ("LeaveDoor" by the player's interior), facing it.
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
	if not E.walk(player, inside + way * 5 + up) then
		return not H.isInside(player)
	end
	E.walk(player, inside + way * 1.5 + up)
	return E.waitUntil(function(): boolean
		return not H.isInside(player)
	end, 3)
end
-- The model of the move's piece at `spot` (its prompts are the player's move's).
function H.pieceOf(player: any, spot: number): any
	for _, d in workspace:FindFirstChild("Moves"):GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not rawget(d, "destroyed") then
			local root = d.PrimaryPart
			local prompt = root and E.promptIn(root, "", function(p: any): boolean
				return p:GetAttribute("MoveOwner") == player.UserId
			end)
			if prompt then
				return d
			end
		end
	end
	return nil
end
-- A piece at home in the player's house that `fits` (by its def): the first in the state's order → item, model, def.
function H.choose(player: any, fits: (any, any) -> boolean): (any, any, any)
	for _, item in H.stateOf(player).items do
		local model = H.pieceOf(player, item.spot)
		local id = model and model:GetAttribute("FurnitureId")
		local def = id and FurnitureLooks.Items[id]
		if item.state == "home" and def and fits(item, def) then
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
-- One trip's load: to the chalet, the back open, in, a piece that `fits` out and loaded, the back shut → item, model.
function H.fetch(player: any, van: any, plot: any, fits: (any, any) -> boolean): (any, any)
	H.drive(player, van, H.toHouse(plot))
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
function H.toStand(player: any, plot: any, index: number)
	local spot = WarehouseLayout.stand(plot, index)
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
	check("…each at their plot's spawn, holstered (SandboxBoot's standAtHome)", H.flat(E.rootOf(ann).Position, V3(plots[1].spawn.x, 0, plots[1].spawn.z)) < 0.5
		and H.flat(E.rootOf(bob).Position, V3(plots[2].spawn.x, 0, plots[2].spawn.z)) < 0.5 and ann.Character:GetAttribute("Holstered") == true,
		E.rootOf(ann).Position)
	E.advance(0.5)
	check("…their warehouses' signs say whose they are; the others FOR RENT", H.anyText(Warehouse.model(1), "Ann") and H.anyText(Warehouse.model(2), "Bob")
		and H.anyText(Warehouse.model(3), "FOR RENT"))
	local state = E.lastKind(ann, "Collection", "state")
	check("…the collection's state (an empty stock, 12 stands, no income) and the upgrades' (the money)", state ~= nil and #state.stock == 0
		and state.stands == Config.Warehouse.Stands and state.income == 0 and E.lastKind(ann, "Upgrades", "state") ~= nil
		and E.lastKind(ann, "Upgrades", "state").money == Config.Sandbox.StartMoney)
	local book = E.lastKind(ann, "CollectionBook", "state")
	local tasks = E.lastKind(ann, "SandboxTasks", "state")
	check("…the book's state (nothing found) and the day's tasks (3 dailies, a weekly)", book ~= nil and next(book.book) == nil and tasks ~= nil
		and #tasks.daily == Config.SandboxTasks.Daily and tasks.weekly ~= nil)
	check("…the client's State queued (Main's queueState on PlayerData.Changed)", table.find(queued, ann) ~= nil and table.find(queued, bob) ~= nil)
	check("…the analytics' funnel: Joined once each", H.steps(11).Joined == 1 and H.steps(22).Joined == 1)
end

-- ── 2. PLAY ───────────────────────────────────────────────────────────────

local annVan = H.play(ann)
local bobVan = H.play(bob)
do
	check("2. PLAY: Ann's ZDC Sprinter at her vanSpot, nose to the street, its back doors in the unload circle", annVan ~= nil and annVan.id == Config.Sandbox.Van
		and H.flat(annVan.chassis.Position, V3(plots[1].vanSpot.x, 0, plots[1].vanSpot.z)) < 0.5 and annVan.chassis.CFrame.LookVector.Z > 0.99
		and H.inCircle(H.doorOf(annVan).WorldPosition, plots[1]), annVan and annVan.chassis.Position)
	check("…she is not in it, still at the spawn; told where it is", E.humanoidOf(ann).SeatPart == nil
		and H.flat(E.rootOf(ann).Position, V3(plots[1].spawn.x, 0, plots[1].spawn.z)) < 0.5 and E.heard(ann, "parked at your warehouse"), E.lastNotice(ann))
	check("…Bob's at his own vanSpot; both in workspace.Cars with their owner and the engine's SpeedMult (level 0: 1)", bobVan ~= nil and bobVan ~= annVan
		and H.flat(bobVan.chassis.Position, V3(plots[2].vanSpot.x, 0, plots[2].vanSpot.z)) < 0.5 and annVan.model.Parent == workspace:FindFirstChild("Cars")
		and annVan.model:GetAttribute("OwnerId") == 11 and annVan.model:GetAttribute("SpeedMult") == 1)
	local calls = #E.vehicleCalls
	E.fire(ann, "Play")
	E.advance(1)
	check("…a second PLAY brings no second van", Vehicles.get(ann) == annVan and #E.vehicleCalls == calls)
	check("…the analytics' funnel: PressedPlay once", H.steps(11).PressedPlay == 1)
end

-- ── 3. The contract at your plot's kiosk, START, LAUNCH ──────────────────

do
	local card, ok, why = H.takeContract(ann, plots[1])
	check("3. Ann at her kiosk: the contract card, The Old Chalet, free to start", ok and card ~= nil and card.id == House.id and card.busy == nil
		and card.items > 0 and card.story == false, why or (card and card.busy))
	local before = #E.sent
	E.fire(ann, "Moving", "start", House.id)
	local lobby = E.lastOf(ann, "MoveLobby", "lobby", before)
	check("…START opens the planning lobby (solo: LAUNCH at once)", lobby ~= nil and lobby[2] ~= nil and lobby[2].canLaunch == true, E.lastNotice(ann))
	before = #E.sent
	E.fire(ann, "MoveLobby", "launch")
	E.advance(0.5)
	check("…LAUNCH: the move starts with her own Sprinter where it stands", E.heard(ann, "Move started", before) and Vehicles.get(ann) == annVan, E.lastNotice(ann))
	local view = H.stateOf(ann)
	S.annMove = view.id
	check("…its drop-off is her plot's unload circle; no horde; the clock runs", view.drop == "your warehouse" and view.dropOff.x == plots[1].unload.x
		and view.dropOff.z == plots[1].unload.z and view.hordeAt == nil and view.endsAt > E.now)
	check("…Danny joins her crew of one, on AUTO (8.3), his id for his command card", MoveHelper.find(ann) ~= nil and MoveHelper.find(ann).mode == "auto"
		and ann:GetAttribute("MoveHelperId") == MoveHelper.find(ann).id)
	E.fire(ann, "Moving", "helper", "van")
	check("…told to WAIT AT VAN (8.3: his command card's order): he leaves her pieces to her", ann:GetAttribute("MoveHelper") == "van", ann:GetAttribute("MoveHelper"))
	check("…the analytics: FirstContract once, MoveStarted (solo)", H.steps(11).FirstContract == 1 and #H.events("MoveStarted", ann) == 1)
	local bobCard = H.takeContract(bob, plots[2])
	H.launch(bob)
	local bobView = H.stateOf(bob)
	check("…Bob's move too, at the same time: his own, his plot's drop-off, his own Danny", bobCard ~= nil and bobView ~= nil and bobView.id ~= view.id
		and bobView.dropOff.x == plots[2].unload.x and Vehicles.get(bob) == bobVan and MoveHelper.find(bob) ~= nil and MoveHelper.find(bob) ~= MoveHelper.find(ann))
	-- 14 (the board): Bob at Ann's kiosk sees only his own move (any kiosk opens YOUR contract: KONTRAKT), Ann's untouched
	local atAnn = H.takeContract(bob, plots[1])
	check("14. Bob at Ann's kiosk: only his own card (busy: he is on his move), nothing of Ann's", atAnn ~= nil and atAnn.busy == "You are on a move already."
		and H.stateOf(ann).id == view.id, atAnn and atAnn.busy)
	before = #E.sent
	E.fire(bob, "Moving", "start", House.id)
	check("…his START there is refused; Ann's move goes on as it was", E.lastOf(bob, "MoveLobby", "lobby", before) == nil and H.stateOf(ann).id == view.id
		and H.stateOf(ann).counts.out == 0)
end

-- ── 4–6. Ann: to the chalet, the door, the grip, the load ─────────────────

do
	H.drive(ann, annVan, H.toHouse(plots[1]))
	check("4. Ann drove her van to the chalet's curb, its back to the front door", H.flat(annVan.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 0.5
		and H.doorOf(annVan).WorldPosition.Z > annVan.chassis.Position.Z, annVan.chassis.Position)
	check("…got out and opened the back doors (Vehicles' BackPrompt: hers, on foot, hands free)", H.setBack(ann, annVan, true), E.lastNotice(ann))
	local fadeAt = #E.sent
	check("…walked up to the front door and stood in its zone facing it: in after the dwell, no E", H.enterHouse(ann), E.rootOf(ann).Position)
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
	check("6. carried out through the doorway (walked into its zone inside): outside with the piece", H.leaveHouse(ann)
		and ann.Character:GetAttribute("MoveCarry") == piece.spot, E.rootOf(ann).Position)
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
	local ok = E.trigger(bayLoad, ann)
	check("…loaded from inside the bay", ok and H.itemOf(ann, small.spot).state == "truck" and H.inBay(annVan, model) and H.stateOf(ann).counts.out == 2,
		E.lastNotice(ann))
	E.walk(ann, H.bayPoint(annVan, SprinterLooks.Bay.z1 - 1), Config.Movement.Walk * 0.5)
	E.walk(ann, H.behindVan(annVan, 4))
	check("…the back doors shut again before driving", H.setBack(ann, annVan, false))
end

-- ── 7. Home: the trips ────────────────────────────────────────────────────

do
	local big = S.annBigModel
	local from = big.PrimaryPart.Position
	H.drive(ann, annVan, { { x = 0, z = 470, yaw = 0 }, { x = 0, z = -60, yaw = 0 }, { x = plots[2].vanSpot.x, z = -60, yaw = 90 }, { x = plots[2].unload.x, z = plots[2].unload.z + 8, yaw = 0 } })
	E.advance(1)
	check("7. the loaded van at Bob's plot (in his unload circle): no trip", H.stateOf(ann).trips == 0 and #Collection.stock(ann) == 0 and #Collection.stock(bob) == 0
		and H.stateOf(ann).counts.out == 2)
	check("…the load rode along in the bay (welded to the van)", H.inBay(annVan, big) and H.flat(big.PrimaryPart.Position, from) > 100)
	local tripAt = #E.sent
	H.drive(ann, annVan, { { x = plots[2].vanSpot.x, z = -60, yaw = 0 }, { x = plots[1].vanSpot.x, z = -60, yaw = 90 }, { x = plots[1].vanSpot.x, z = plots[1].vanSpot.z, yaw = 180 } })
	E.advance(1)
	local stock = Collection.stock(ann)
	check("…backed into her own unload circle: trip 1, both pieces into HER stock", H.stateOf(ann).trips == 1 and #stock == 2 and E.heard(ann, "Trip 1 home", tripAt)
		and #Collection.stock(bob) == 0, E.lastNotice(ann))
	local entry = H.entryFor(stock, S.annBigDef.id)
	check("…Collection.add with the piece's item, name, condition (the move's) and a uid", entry ~= nil and entry.name == S.annBigDef.name
		and math.abs(entry.condition - H.itemOf(ann, S.annBig.spot).condition) < 0.006 and type(entry.uid) == "string" and entry.stand == nil, entry and entry.condition)
	local looked = #stock > 0
	for _, e in stock do
		looked = looked and H.lookOk(e.item, H.signature(FurnitureLooks.build(e.item, e.variant)))
	end
	check("…with the house's variant: each entry (item, variant) builds the very look the piece had in the house", looked)
	check("…the pieces left the van (their models gone), no pay per piece", rawget(big, "destroyed") == true and rawget(S.annSmallModel, "destroyed") == true
		and H.paid(ann, "MovePay") == 0)
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
	check("8.2 tasks: \"trips\" counts the trip (1 of " .. (if trips then tostring(trips.target) else "?") .. ")", trips ~= nil and trips.progress == 1, trips and trips.progress)
	local rare = 0
	for _, e in stock do
		local d = CollectionRules.defOf(e.item)
		rare += if d and (d :: any).rarity then 1 else 0
	end
	check("8.2 analytics: a CollectibleFound for each collectible that came home (" .. rare .. ")", #H.events("CollectibleFound", ann) == rare)
	check("8.2 analytics: FirstTripHome once, one CollectionAdded for the trip (2 pieces)", H.steps(11).FirstTripHome == 1
		and #H.events("CollectionAdded", ann) == 1 and H.events("CollectionAdded", ann)[1][3] == 2)
end

do
	-- trip 2: back for one more, home nose-in
	local item = H.fetch(ann, annVan, plots[1], function(_i: any, d: any): boolean
		return d.class == "hand" and not d.fragile
	end)
	check("(a third piece fetched and loaded)", item ~= nil and H.itemOf(ann, item.spot).state == "truck", E.lastNotice(ann))
	local tripAt = #E.sent
	H.drive(ann, annVan, H.toPlot(plots[1], true))
	E.advance(1)
	check("…trip 2 home nose-in (the van's middle in the circle, its back out of it): 3 in her stock",
		H.stateOf(ann).trips == 2 and #Collection.stock(ann) == 3 and E.heard(ann, "Trip 2 home", tripAt)
		and not H.inCircle(H.doorOf(annVan).WorldPosition, plots[1]) and H.inCircle(annVan.chassis.Position, plots[1]), E.lastNotice(ann))
	local trips = H.task(ann, "trips")
	local done = E.lastKind(ann, "SandboxTasks", "done", tripAt)
	check("8.2 tasks: \"trips\" 2" .. (if trips and trips.target == 2 then ", done: her client told" else ""), trips ~= nil and trips.progress == math.min(2, trips.target)
		and (trips.target ~= 2 or (done ~= nil and trips.done)), trips and `{trips.progress}/{trips.target}`)
end

do
	-- Bob: a piece through his grip (his client answers), a death on the way, the respawn by his van, loaded, home.
	S.auto[bob] = true
	H.drive(bob, bobVan, H.toHouse(plots[2]))
	check("Bob: at the chalet's curb too", H.flat(bobVan.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 0.5)
	check("(Bob's back open)", H.setBack(bob, bobVan, true), E.lastNotice(bob))
	check("(Bob in)", H.enterHouse(bob))
	check("…two houses at once: Bob's interior is another slot than Ann's (her move still runs)", S.rooms[bob] ~= nil and S.rooms[ann] ~= nil
		and S.rooms[bob] ~= S.rooms[ann] and H.stateOf(ann) ~= nil and H.stateOf(ann).trips == 2)
	local piece, model = H.choose(bob, function(_i: any, d: any): boolean
		return d.class ~= "pair" and CarryGrip.kind(d.class, d.fragile, false, nil) ~= nil
	end)
	H.remember(model)
	check("Bob lifts a piece (a grip check answered by his client, if it has one)", piece ~= nil and H.pickUp(bob, model), E.lastNotice(bob))
	check("(Bob out)", H.leaveHouse(bob))
	E.walk(bob, H.groundAt(V3(House.door.x + 6, 0, House.door.z - 10)))
	local before = H.itemOf(bob, piece.spot).condition
	E.humanoidOf(bob).Health = 0
	E.advance(0.3)
	local dropped = H.itemOf(bob, piece.spot)
	check("…Bob dies carrying it: it goes down outside (the death's knock), out of his hands", dropped.state == "ground" and dropped.condition < before
		and bob.Character:GetAttribute("MoveCarry") == nil, `{dropped.state} {before} → {dropped.condition}`)
	E.advance(5) -- (Players.RespawnTime)
	E.spawn(bob)
	E.advance(1)
	check("…his new body stands by his van's back (SandboxBoot's spawn → Moving.respawnAt), not at home",
		H.flat(E.rootOf(bob).Position, H.doorOf(bobVan).WorldPosition) < 10 and not H.inCircle(E.rootOf(bob).Position, plots[2]), E.rootOf(bob).Position)
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
	check("8.1 review: a WOBBLE! still open when he loads it is a miss (a stagger, a fragile piece's drop: its knock), the piece in the van",
		opened and loaded and forfeit ~= nil and (forfeit.outcome == "stagger" or forfeit.outcome == "drop") and H.itemOf(bob, piece.spot).state == "truck"
		and H.itemOf(bob, piece.spot).condition < held, forfeit and forfeit.outcome)
	S.auto[bob] = true
	H.setBack(bob, bobVan, false)
	H.drive(bob, bobVan, H.toPlot(plots[2], false))
	E.advance(1)
	check("…Bob's trip: his piece in HIS stock and book, Ann's untouched", H.stateOf(bob).trips == 1 and #Collection.stock(bob) == 1 and #Collection.stock(ann) == 3
		and Book.book(bob)[Collection.stock(bob)[1].item] ~= nil)
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
	local spot = WarehouseLayout.stand(plots[1], 1)
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
	-- a piece on show put on another stand moves there; Take down (its prompt) sends it back to the stock
	check("…a piece on show put on another stand moves there (stand 1 empty, stand 3 shows it)", H.request(ann, { kind = "display", uid = annStock[1].uid, stand = 3 }) == ""
		and (function(): boolean
			H.rebuilt()
			return Warehouse.shown(1, 1) == nil and Warehouse.shown(1, 3) ~= nil and Warehouse.shown(1, 3):GetAttribute("Uid") == annStock[1].uid
				and H.standPrompt(1, 1, "Display").Enabled and H.byUid(Collection.stock(ann), annStock[1].uid).stand == 3
		end)())
	H.request(ann, { kind = "display", uid = annStock[1].uid, stand = 1 })
	H.rebuilt()
	local downAt = #E.sent
	local down = E.trigger(H.standPrompt(1, 2, "TakeDown"), ann)
	H.rebuilt()
	check("…Take down at stand 2: back in her stock, the stand empty", down and E.heard(ann, "is back in your stock", downAt)
		and H.byUid(Collection.stock(ann), annStock[2].uid).stand == nil and Warehouse.shown(1, 2) == nil and Warehouse.shown(1, 1) ~= nil)
	H.request(ann, { kind = "display", uid = annStock[2].uid, stand = 2 })
	H.rebuilt()
	check("(on stand 2 again)", Warehouse.shown(1, 2) ~= nil and Warehouse.shown(1, 2):GetAttribute("Uid") == annStock[2].uid)

	-- the refusals (the remote is the client's: anything can come)
	local third = annStock[3]
	check("NEG. display on a stand she doesn't have (13 of 12): refused", H.request(ann, { kind = "display", uid = third.uid, stand = 13 }) == "There's no such display stand."
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
	E.advance(60)
	local got = H.paid(ann, "CollectionIncome", incomeAt)
	check("…60 s on the clock: paid as CollectionIncome at that rate (whole dollars; the payout every " .. Config.Collection.Tick .. " s)",
		got > 0 and got >= math.floor(rate * 50 / 60) - 1 and got <= rate * 70 / 60 + 1 and H.profileOf(ann).money - was == got, `{got} at {rate}/min`)
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
	local said = H.buy(ann, "stands", 1)
	check("NEG. More stands without the money: refused, nothing taken, nothing changed", poor < 1000 and string.find(said, "costs $1,000", 1, true) ~= nil
		and H.profileOf(ann).money - poor == H.paid(ann, "CollectionIncome", poorAt) and Upgrades.levels(ann).stands == nil and Collection.stands(ann) == Config.Warehouse.Stands, said)
	PlayerData.addMoney(ann, 20000, "Admin") -- (the admin panel's money button: PlayerData.addMoney)
	local rich = H.profileOf(ann).money
	local spentAt = #money
	H.buy(ann, "stands", 1)
	check("…with the money: More stands 1 bought ($1,000, the reason Upgrade): 14 stands", Upgrades.levels(ann).stands == 1 and Collection.stands(ann) == 14
		and H.profileOf(ann).money - rich == -1000 + H.paid(ann, "CollectionIncome", spentAt) and H.paid(ann, "Upgrade", spentAt) == -1000 and E.lastKind(ann, "Upgrades", "bought") ~= nil)
	E.advance(0.1)
	check("…the window's state shows the money left; the analytics' UpgradeBought; FirstUpgrade (step 10) waits for FirstSale (9): the funnel is in order",
		E.lastKind(ann, "Upgrades", "state").money == rich - 1000 + H.paid(ann, "CollectionIncome", spentAt) and #H.events("UpgradeBought", ann) == 1 and H.steps(11).FirstUpgrade == nil)
	H.rebuilt()
	check("…the warehouse opens stands 13 and 14 (15 still a painted spot); the collection's state says 14", Warehouse.isOpen(1, 13) and Warehouse.isOpen(1, 14)
		and not Warehouse.isOpen(1, 15) and E.lastKind(ann, "Collection", "state").stands == 14)
	check("…the income unchanged by stands alone", math.abs(Collection.incomePerMinute(ann) - S.rate) < 1e-9)
	local secondAt = #money
	H.buy(ann, "stands", 1)
	check("…a second click on the same card buys once", Upgrades.levels(ann).stands == 1 and H.paid(ann, "Upgrade", secondAt) == 0)
	local third = annStock[3]
	local fits = WarehouseLayout.fits(13, (FurnitureLooks.Items[third.item] :: any).size)
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
	local saleAt2, sentAt2 = #money, #E.sent
	E.advance(1.1)
	E.fire(ann, "Collection", { kind = "sellmany", filter = "duplicates" })
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

-- ── 12. FINISH; the tasks and the analytics of the move ───────────────────

do
	local resultAt = #E.sent
	E.fire(ann, "Moving", "finish")
	local result = E.lastOf(ann, "Moving", "result", resultAt)
	local card = result and result[2]
	check("12. FINISH: the result card says what came home: 3 pieces over 2 trips, no pay, no XP", card ~= nil and card.how == "done" and card.home ~= nil
		and card.home.pieces == 3 and card.trips == 2 and card.money == 0 and card.xp == 0 and card.pay == 0, card and card.home and card.home.pieces)
	local worth = 0
	for _, entry in annStock do
		worth += CollectionRules.valueOf(entry) * entry.condition
	end
	check("…its value is what the three pieces were worth as they came home (the stock's)", card ~= nil and math.abs(card.home.value - worth) <= 1.5,
		card and `{card.home.value} vs {worth}`)
	E.advance(0.5)
	local collectibles = 0
	for _, entry in annStock do
		local d = CollectionRules.defOf(entry.item)
		collectibles += if d and (d :: any).rarity then 1 else 0
	end
	-- (and the twin the admin's FILL STOCK gave her while the move ran, when it is a collectible: SandboxAnalytics reads every
	-- new piece in the stock during a move as found on it)
	local twin = CollectionRules.defOf(annStock[1].item)
	local twins = if twin and (twin :: any).rarity then 1 else 0
	check("8.2 analytics: one CollectibleFound for every collectible her move brought home (" .. collectibles .. ", the admin's twin " .. twins .. ")",
		#H.events("CollectibleFound", ann) == collectibles + twins, #H.events("CollectibleFound", ann))
	check("…the van's prompts gone, Danny gone; MoveDone, MoveFinished and MoveFinishedValue once (MoveGaveUp never)", annVan.chassis:FindFirstChild("MoveLoadBay") == nil
		and MoveHelper.find(ann) == nil and #H.events("MoveDone", ann) == 1 and #H.events("MoveFinished", ann) == 1 and #H.events("MoveFinishedValue", ann) == 1
		and #H.events("MoveGaveUp", ann) == 0)
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
	check("…Bob's move goes on (his own)", H.stateOf(bob) ~= nil and H.stateOf(bob).trips == 1)
	E.advance(2)
	resultAt = #E.sent
	E.fire(bob, "Moving", "finish")
	local bobResult = E.lastOf(bob, "Moving", "result", resultAt)
	check("…Bob's FINISH: 1 piece home", bobResult ~= nil and bobResult[2].home.pieces == 1)
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
		and save.lock == nil and save.sandboxUpgrades.stands == 1 and type(save.collectionBook) == "table" and type(save.sandboxTasks) == "table")
	check("…with every dollar: what her stands earned up to the moment she left (Collection's leave payout before the leave save)",
		save ~= nil and save.money == keptMoney + H.paid(ann, "CollectionIncome", keptAt), save and `{save.money} vs {keptMoney} + {H.paid(ann, "CollectionIncome", keptAt)}`)
	check("…her plot is free (FOR RENT), her pieces leave the warehouse with her", SandboxPlots.owner(1) == nil and H.anyText(Warehouse.model(1), "FOR RENT")
		and Warehouse.shown(1, 1) == nil)
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
	local van = H.play(ann2)
	check("…PLAY: her van at her vanSpot again (the old one went with her)", van ~= nil and H.flat(van.chassis.Position, V3(plots[1].vanSpot.x, 0, plots[1].vanSpot.z)) < 0.5
		and #workspace:FindFirstChild("Cars"):GetChildren() == 2)
	H.buy(ann2, "engine", 1)
	check("…Van engine 1: her van's SpeedMult 1.05 (Upgrades tunes every van of hers), Bob's untouched", math.abs((van.model:GetAttribute("SpeedMult") or 0) - 1.05) < 1e-9
		and Vehicles.get(bob).model:GetAttribute("SpeedMult") == 1, van.model:GetAttribute("SpeedMult"))
	H.buy(ann2, "danny", 1)
	check("…Danny's training 1: her player's DannyTraining (MoveHelper reads it)", ann2:GetAttribute(Config.SandboxUpgrades.Danny) == 1)
	E.advance(1)
	E.fire(ann2, "SpawnCar")
	E.advance(0.5)
	local again = Vehicles.get(ann2)
	check("…CAR (SandboxBoot's callVan → parkVan): a new van at her vanSpot, tuned as it comes (workspace.Cars' ChildAdded)", again ~= nil and again ~= van
		and math.abs((again.model:GetAttribute("SpeedMult") or 0) - 1.05) < 1e-9 and H.flat(again.chassis.Position, V3(plots[1].vanSpot.x, 0, plots[1].vanSpot.z)) < 0.5,
		again and again.model:GetAttribute("SpeedMult"))
	S.annVan2 = again
end

-- ── 14. Bob cannot use Ann's stands or desk; her kiosk opens his own move ─

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
	-- the kiosks are everybody's (KONTRAKT: any of them opens YOUR contract): Bob's LAUNCH at Ann's is his own move
	E.advance(1.1)
	local card = H.takeContract(bob, plots[1])
	check("…Ann's kiosk after his FINISH: his own card, free to start", card ~= nil and card.busy == nil, card and card.busy)
	E.fire(bob, "Moving", "start", House.id)
	E.fire(bob, "MoveLobby", "launch")
	E.advance(0.5)
	local state = H.stateOf(bob)
	check("…LAUNCH there: his move, HIS van where it stands, home = HIS plot; Ann's van and plot untouched", state ~= nil and state.dropOff.x == plots[2].unload.x
		and Vehicles.get(bob) == bobVan and Vehicles.get(ann2) == S.annVan2 and H.flat(S.annVan2.chassis.Position, V3(plots[1].vanSpot.x, 0, plots[1].vanSpot.z)) < 0.5)
	E.fire(bob, "Moving", "giveup")
	E.advance(2)
	check("…GIVE UP with nothing home: MoveGaveUp (how far: started)", #H.events("MoveGaveUp", bob) == 1)
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
	check("…Eve stands on Depot Row in front of plot 1 (SandboxBoot's fallback)", H.flat(E.rootOf(eve).Position, V3(plots[1].spawn.x, 0, -50)) < 1, E.rootOf(eve).Position)
	local van = H.play(eve)
	check("…her PLAY: her van on Depot Row (no vanSpot of hers)", van ~= nil and van.chassis.Position.Z > -74 and van.chassis.Position.Z < -46, van and van.chassis.Position)
	check("…the upgrades refuse her (no warehouse of her own)", string.find(H.buy(eve, "danny", 1), "warehouse of your own", 1, true) ~= nil)
	E.advance(1.1)
	local card = H.takeContract(eve, plots[1])
	check("…a kiosk's card says she has no warehouse (START refused)", card ~= nil and string.find(tostring(card.busy), "no warehouse", 1, true) ~= nil, card and card.busy)
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

-- ── 16. A full warehouse at a trip ────────────────────────────────────────

do
	local van = H.play(cid)
	E.advance(1.1)
	local card = H.takeContract(cid, plots[3])
	H.launch(cid)
	check("16. (Cid's move, from his kiosk)", card ~= nil and H.stateOf(cid) ~= nil)
	local item = H.fetch(cid, van, plots[3], function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	check("(Cid carries a piece out and loads it)", item ~= nil and H.itemOf(cid, item.spot).state == "truck", E.lastNotice(cid))
	local maxStock = Config.Collection.MaxStock
	Config.Collection.MaxStock = #Collection.stock(cid) -- (his warehouse full: Collection.add refuses)
	local tripAt = #E.sent
	H.drive(cid, van, H.toPlot(plots[3], false))
	E.advance(1)
	check("…home with a full warehouse: the trip says the piece could not be stored, the warehouse that it is full", H.stateOf(cid).trips == 1
		and #Collection.stock(cid) == 0 and E.heard(cid, "could not be stored", tripAt) and E.heard(cid, "warehouse is full", tripAt), E.lastNotice(cid))
	check("…not in his book either (only what came into the stock)", next(Book.book(cid) or {}) == nil)
	local resultAt = #E.sent
	E.fire(cid, "Moving", "finish")
	local result = E.lastOf(cid, "Moving", "result", resultAt)
	Config.Collection.MaxStock = maxStock
	check("…FINISH: the refused piece never came home (lost), so there is nothing to finish with: no result card, told why",
		result == nil and E.heard(cid, "Nothing delivered yet", resultAt), result and `home.pieces = {result[2].home.pieces}`)
	E.fire(cid, "Moving", "giveup") -- (his move off, as GIVE UP does)
	E.advance(1)
end

-- ── 17. Leaving mid-move, a piece in the van ─────────────────────────────

do
	local van = H.play(dee)
	E.clients[dee] = H.client(dee)
	S.auto[dee] = true
	E.advance(1.1)
	H.takeContract(dee, plots[4])
	H.launch(dee)
	local first = H.fetch(dee, van, plots[4], function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	H.drive(dee, van, H.toPlot(plots[4], false))
	E.advance(1)
	check("17. (Dee's trip 1 home: 1 piece in her stock)", first ~= nil and H.stateOf(dee).trips == 1 and #Collection.stock(dee) == 1)
	local second = H.fetch(dee, van, plots[4], function(_i: any, d: any): boolean
		return d.class ~= "pair"
	end)
	check("(a second piece in her van)", second ~= nil and H.itemOf(dee, second.spot).state == "truck")
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
	check("…Dee leaves mid-move: her move ends (its interior taken down, the slot free), Danny gone", after == interiors - 1 and MoveHelper.find(dee) == nil)
	check("…her save keeps what came home (1 piece); the one still in the van is lost", save ~= nil and #save.collection.entries == 1)
	local finished = 0
	for index = events + 1, #E.analytics do
		local call = E.analytics[index]
		if call.method == "LogCustomEvent" and call.args[1] == dee and (call.args[2] == "MoveFinished" or call.args[2] == "MoveGaveUp") then
			finished += 1
		end
	end
	check("…the analytics: the move's end once (MoveFinished: pieces came home)", finished == 1, finished)
	local dee2 = E.join(44, "Dee")
	S.dee = dee2 -- (8.3: step 18's)
	H.rebuilt()
	check("…back: plot 4, her one piece, no move running (a fresh contract at her kiosk)", dee2:GetAttribute("Plot") == 4 and #Collection.stock(dee2) == 1
		and H.stateOf(dee2) == nil and Moving.busy(dee2) == nil)
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
