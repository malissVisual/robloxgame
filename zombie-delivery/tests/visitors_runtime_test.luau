-- 8.3 SANDBOX, the showroom's visitors on the real boot: tests/runtime/SandboxE2E.luau's stand-in with the REAL
-- server/SandboxBoot.luau, PlayerData, SandboxPlots, Collection, Warehouse, Upgrades, SandboxTasks, server/Visitors.luau
-- and server/VisitorOffers.luau (E2E<Name>.luau through tests/run_tests.py); Npcs is the stand-in's body with a walker
-- here (a leg takes its length / Config.Visitors.Walk s, then the body stands at its end), the dice a fixed stream
-- (Visitors.useRandom), the clock the test's. Checked: the boot starts the visitors; nobody comes to a warehouse with
-- nothing on show; the owner at their warehouse with pieces on show: a group of 1 – 3 within FirstWait s, walking in
-- beside the van through the door's side (off the van's bay, never stopping in the door path or at the desk), looking at
-- pieces on show (one visitor a stand) and saying so; at most PerHall in a hall, Cap in the server, at all times; an
-- offer from a visitor at a piece (the card's message, the toast, the bubble with the price), ACCEPT through the remote:
-- sold at the offer, the visitor with a box on its way out and gone; DECLINE: it moves on; the clock run out: it moves
-- on; a player stepping up to a visitor that looks: it moves on; the owner away: a group every AwayEvery s at most and
-- no offers; every piece taken down: nobody new; the owner leaving: their visitors go; Config.Visitors.On false: every
-- visitor goes, nobody comes; no script error, no warning.
-- Run: python3 tests/run_tests.py [path to the luau binary]
math.randomseed(8303)

local E = require("./SandboxE2E")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")
local Rules = require("./Visitors")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Visitors
local V3 = E.Mock.Vector3.new
local CF = E.Mock.CFrame
local workspace = E.workspace
local task = E.globals.task
local plot1 = SandboxMap.Plots[1]

-- ── The walker and the record of the visitors' bodies ─────────────────────
local Npcs = E.fakes.Npcs
local walks: { [any]: number } = {}
local sent: { { npc: any, point: any } } = {} -- every leg a visitor was sent along
local bodies: { any } = {} -- every visitor's body spawned
local spawn = Npcs.spawn
Npcs.spawn = function(look: any, at: any): any
	local model = spawn(look, at)
	table.insert(bodies, model)
	return model
end
Npcs.walkTo = function(npc: any, point: any, arrived: any, _timeout: any, _options: any)
	local root = npc.PrimaryPart
	local token = (walks[npc] or 0) + 1
	walks[npc] = token
	table.insert(sent, { npc = npc, point = point })
	local here = root.Position
	local d = math.sqrt((point.X - here.X) ^ 2 + (point.Z - here.Z) ^ 2)
	task.delay(d / T.Walk, function()
		if walks[npc] ~= token or not npc.Parent then
			return
		end
		root.CFrame = CF.new(point.X, here.Y, point.Z)
		if arrived then
			arrived(true)
		end
	end)
end

local Boot = E.module("SandboxBoot")
local Collection = E.module("Collection")
local Visitors = E.module("Visitors")
local Offers = E.module("VisitorOffers")
local PlayerData = E.module("PlayerData")

local seed = 83031
Visitors.useRandom(function(): number
	seed = (seed * 48271) % 2147483647
	return seed / 2147483647
end)

Boot.start(function() end)
E.advance(1)
do
	local failed = {}
	for _, line in E.warnings do
		if string.find(line, "failed to start", 1, true) or string.find(line, "not in this build", 1, true) then
			table.insert(failed, line)
		end
	end
	check("the boot starts the visitors (no \"failed to start\", no module missing)", #failed == 0 and #E.errors == 0, table.concat(failed, " | ") .. table.concat(E.errors, " | "))
end

-- the most in a hall and in the server, looked at every second of the run
local most, mostAll = 0, 0
local function run(seconds: number, until_: (() -> boolean)?): boolean
	for _ = 1, math.ceil(seconds) do
		E.advance(1)
		most = math.max(most, Visitors.count(1))
		mostAll = math.max(mostAll, Visitors.count())
		if until_ and until_() then
			return true
		end
	end
	return false
end
local function visitorsIn(id: number): { any }
	local out = {}
	for _, v in Visitors.list() do
		if v.plot == id then
			table.insert(out, v)
		end
	end
	return out
end

-- ── Ann: her warehouse, nothing on show ───────────────────────────────────
local ann = E.join(11, "Ann")
E.advance(2)
local receiving = WarehouseLayout.receiving(plot1)
E.place(ann, V3((receiving.x0 + receiving.x1) / 2 + 6, 3, (receiving.z0 + receiving.z1) / 2))
run(90)
check("nothing on show: nobody comes, though Ann is in her warehouse", #bodies == 0 and Visitors.count() == 0)

-- ── Pieces on show, Ann in her hall: a group comes ────────────────────────
local items = { "piano", "sofa", "armchair", "grandfather_clock", "bookshelf", "guitar" }
for index, item in items do
	Collection.add(ann, { item = item, condition = 1 })
	E.flush()
	local stock = Collection.stock(ann)
	Collection.display(ann, stock[#stock].uid, index)
end
E.flush()
local names: { string } = {}
for _, entry in Collection.stock(ann) do
	table.insert(names, string.lower(entry.name))
end
local spawnedAt = E.clock
run(T.FirstWait[2] + T.Stagger * 3 + 1, function()
	return #bodies > 0
end)
check(`pieces on show, Ann at her warehouse: visitors within FirstWait s ({math.floor(E.clock - spawnedAt)} s)`, #bodies >= 1 and E.clock - spawnedAt <= T.FirstWait[2] + 1.5)
run(T.Stagger * 3)
local group = #bodies
check(`… a group of 1 – 3 ({group}), the bodies in workspace.Npcs with their kind (attribute Visitor)`, group >= 1 and group <= 3 and bodies[1].Parent ~= nil
	and Rules.kind(bodies[1]:GetAttribute("Visitor")) ~= nil)
local bay = WarehouseLayout.bay(plot1)
local door = WarehouseLayout.door(plot1)
local firstLeg: any = nil
for _, s in sent do
	if s.npc == bodies[1] then
		firstLeg = s.point
		break
	end
end
local startAt = bodies[1].PrimaryPart.Position
check("… it walks in beside the van (off the UNLOAD HERE bay) through the door's side", firstLeg ~= nil and math.abs(firstLeg.X - door.x) <= door.width / 2
	and math.abs(firstLeg.X - door.x) >= 2 and math.abs(firstLeg.Z - door.z) < 3
	and not (startAt.X > bay.x0 and startAt.X < bay.x1 and startAt.Z > bay.z0 and startAt.Z < bay.z1))

-- they look at pieces: a stop at a stand with a piece, one visitor a stand, a line about it now and then
local looked = run(60, function()
	for _, v in visitorsIn(1) do
		if v.state == "look" then
			return true
		end
	end
	return false
end)
check("a visitor stops at a piece on show and looks at it", looked)
local path = WarehouseLayout.doorPath(plot1)
local desk = WarehouseLayout.terminal(plot1)
local function stopsBad(): string?
	for _, v in visitorsIn(1) do
		if v.state == "look" or v.state == "offer" then
			local p = v.model.PrimaryPart.Position
			if p.X > path.x0 and p.X < path.x1 and p.Z > path.z0 and p.Z < path.z1 then
				return "in the door path"
			end
			if math.abs(p.X - desk.x) < desk.sx / 2 + T.DeskClear - 0.5 and math.abs(p.Z - desk.z) < desk.sz / 2 + T.DeskClear - 0.5 then
				return "at the desk"
			end
			if WarehouseLayout.standAt(plot1, p.X, p.Z) ~= nil then
				return "on a podium"
			end
		end
	end
	local seen: { [number]: boolean } = {}
	for _, v in visitorsIn(1) do
		if v.stand and (v.state == "look" or v.state == "offer" or v.state == "in") then
			if seen[v.stand] then
				return "two at one stand"
			end
			seen[v.stand] = true
		end
	end
	return nil
end
local bad: string? = nil
run(40, function()
	bad = bad or stopsBad()
	return false
end)
check("… never stopping in the door path, at the desk or on a podium; one visitor a stand", bad == nil, bad)
local talked = false
for _, line in E.said do
	for _, name in names do
		if string.find(line, name, 1, true) then
			talked = true
		end
	end
end
check("… saying something about a piece now and then (\"Ooh, a …!\")", talked, E.said[1])

-- ── An offer, ACCEPT ───────────────────────────────────────────────────────
T.Offer.Chance = 2 -- (every visitor at a stop offers when it may: × its kind's chance, at most 1)
local offered = run(240, function()
	return Offers.current(ann) ~= nil
end)
local offer = Offers.current(ann)
check("an offer comes (Ann in her hall within reach)", offered and offer ~= nil)
if offer then
	local card = E.lastKind(ann, "Visitors", "offer")
	check("… the card's message and the toast", card ~= nil and card.id == offer.id and card.price == offer.price
		and E.heard(ann, Rules.toast(offer.who, offer.price, offer.name)))
	local bubble = false
	for _, line in E.said do
		bubble = bubble or string.find(line, Rules.say("offer", 0, offer.name, offer.price) and tostring(offer.price) or "", 1, true) ~= nil
	end
	local offerer: any = nil
	for _, v in visitorsIn(1) do
		if v.state == "offer" then
			offerer = v
		end
	end
	check("… the visitor waits at the piece, its bubble names the price", offerer ~= nil and offerer.stand == offer.stand and bubble)
	local before = (PlayerData.get(ann) :: any).money
	E.fire(ann, "Visitors", { kind = "accept", id = offer.id })
	E.advance(0.5)
	local after = (PlayerData.get(ann) :: any).money
	local still = false
	for _, entry in Collection.stock(ann) do
		still = still or entry.uid == offer.uid
	end
	check("ACCEPT: Ann paid the offer, the piece sold", after - before >= offer.price and not still, after - before)
	check("… the visitor carries a box", offerer ~= nil and offerer.model:FindFirstChild("VisitorBox") ~= nil)
	run(4)
	local state = "done"
	for _, v in Visitors.list() do
		if v.model == offerer.model then
			state = v.state
		end
	end
	check("… and goes (out)", state == "out" or state == "done", state)
	run(60, function()
		return offerer.model.Parent == nil
	end)
	check("… gone once out (its body removed)", offerer.model.Parent == nil)
end

-- ── DECLINE, the clock running out ─────────────────────────────────────────
local function nextOffer(): any
	run(240, function()
		return Offers.current(ann) ~= nil
	end)
	return Offers.current(ann)
end
local declined = nextOffer()
check("another offer (Every s later)", declined ~= nil)
if declined then
	local moneyBefore = (PlayerData.get(ann) :: any).money
	E.fire(ann, "Visitors", { kind = "decline", id = declined.id })
	run(3)
	local stillOffering = false
	for _, v in visitorsIn(1) do
		stillOffering = stillOffering or v.state == "offer"
	end
	check("DECLINE: no sale, the visitor moves on", Offers.current(ann) == nil and not stillOffering and (PlayerData.get(ann) :: any).money - moneyBefore < declined.price)
end
local expiring = nextOffer()
check("one more offer", expiring ~= nil)
if expiring then
	run(T.Offer.Expire + 1)
	local stillOffering = false
	for _, v in visitorsIn(1) do
		stillOffering = stillOffering or v.state == "offer"
	end
	check("not answered: its clock runs out, the visitor moves on", Offers.current(ann) == nil and not stillOffering)
end
T.Offer.Chance = 0 -- (no more offers: the visitors only look)

-- ── A player stepping up to a visitor that looks ──────────────────────────
local looker: any = nil
run(120, function()
	for _, v in visitorsIn(1) do
		if v.state == "look" then
			looker = v
			return true
		end
	end
	return false
end)
check("(a visitor looking at a piece)", looker ~= nil)
if looker then
	local at = looker.model.PrimaryPart.Position
	E.place(ann, V3(at.X + 1, 3, at.Z))
	run(1)
	local state = "done"
	for _, v in Visitors.list() do
		if v.model == looker.model then
			state = v.state
		end
	end
	check("… Ann steps up to it: it moves on (never in a player's way)", state ~= "look", state)
	E.place(ann, V3((receiving.x0 + receiving.x1) / 2 + 6, 3, (receiving.z0 + receiving.z1) / 2))
end
check(`at most PerHall ({T.PerHall}) in her hall, Cap ({T.Cap}) in the server, all along`, most <= T.PerHall and mostAll <= T.Cap and most >= 1, `{most} {mostAll}`)

-- ── Ann away: a group every AwayEvery s at most, no offers ────────────────
T.Offer.Chance = 2
E.place(ann, V3(SandboxMap.House.door.x, 3, SandboxMap.House.door.z + 6))
run(T.NearEvery[2] + T.Life) -- (the group already due comes; everybody in the hall gone by now)
local away = #bodies
local anyOffer = false
run(T.AwayEvery[1] * 2, function()
	anyOffer = anyOffer or Offers.current(ann) ~= nil
	return false
end)
local groups = #bodies - away
check(`Ann away ({T.AwayEvery[1] * 2} s): {groups} visitors came (two groups of 3 at most), no offer`, groups <= 6 and not anyOffer, groups)
T.Offer.Chance = 0.35

-- ── Every piece taken down: nobody new ────────────────────────────────────
E.place(ann, V3((receiving.x0 + receiving.x1) / 2 + 6, 3, (receiving.z0 + receiving.z1) / 2))
for _, entry in Collection.stock(ann) do
	if entry.stand then
		Collection.undisplay(ann, entry.uid)
	end
end
E.flush()
run(T.Life + 5)
local empty = #bodies
run(T.AwayEvery[2] + 30)
check("every piece taken down: the visitors there go, nobody new comes", #bodies == empty and Visitors.count(1) == 0)

-- ── The owner leaves; the switch ──────────────────────────────────────────
for index, entry in Collection.stock(ann) do
	if index <= 4 then
		Collection.display(ann, entry.uid, index)
	end
end
E.flush()
run(30, function()
	return Visitors.count(1) > 0
end)
check("(pieces on show again: visitors again)", Visitors.count(1) > 0)
Config.Visitors.On = false
run(T.Life)
check("Config.Visitors.On false: every visitor goes, nobody comes", Visitors.count() == 0)
local offCount = #bodies
run(120)
check("… for good", #bodies == offCount)
Config.Visitors.On = true
run(30, function()
	return Visitors.count(1) > 0
end)
check("(on again: they come back)", Visitors.count(1) > 0)
E.leave(ann)
run(T.Life)
check("Ann leaves: her visitors go", Visitors.count(1) == 0)

check("no script error in any thread", #E.errors == 0, table.concat(E.errors, "\n"))
local warned = {}
for _, line in E.warnings do
	if string.find(line, "Visitors", 1, true) then
		table.insert(warned, line)
	end
end
check("no warning from the visitors", #warned == 0, warned[1])
print(string.format("simulated %.0f s, %d visitors came", E.clock - 100, #bodies))
if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
