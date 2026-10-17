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
-- visitor goes, nobody comes; no script error, no warning. 10.4 (the warehouse in two, Config.Showroom): the visitors
-- come for the SHOWROOM: Ann's pieces on show are on its plinths (her Showroom stands node at 3: the Garage's 2, the Big
-- warehouse's 4, the Logistics Center's 6), a piece in the collection hall brings nobody.
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
local born: { [any]: any } = {} -- where each came into the world
local spawn = Npcs.spawn
Npcs.spawn = function(look: any, at: any): any
	local model = spawn(look, at)
	if type(look) == "table" and type(look.title) == "string" and string.find(look.title, Config.MoveHelper.Title, 1, true) then
		return model -- (10.1 a helper of the crew: the one by Ann's warehouse door, server/HelperCrew.luau's; no visitor)
	end
	table.insert(bodies, model)
	born[model] = model.PrimaryPart.Position
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

-- the most in Ann's hall at each warehouse level and in the server, looked at every second of the run; and whether a
-- visitor ever stood inside her hall's walls, on a podium or at the desk (her plot's Site at its level: 8.3,
-- WarehouseLayout.site)
local Warehouse = E.module("Warehouse")
local Upgrades = E.module("Upgrades")
local ann: any = nil -- (she joins below)
local mostAt: { [number]: number } = {}
local mostAll = 0
local walled: string? = nil
local function siteAt(level: number): any
	return WarehouseLayout.site(plot1, level)
end
-- Is a point of Ann's warehouse at `level` in its walls, on one of her podiums or at the UPGRADES desk?
local function caughtAt(level: number, x: number, z: number): boolean
	local site = siteAt(level)
	local inside = WarehouseLayout.inside(site)
	if x <= inside.x0 or x >= inside.x1 or z <= inside.z0 or z >= inside.z1 then
		local box = WarehouseLayout.outline(site)
		return x > box.x0 and x < box.x1 and z > box.z0 and z < box.z1 -- (in its walls)
	end
	local stand = WarehouseLayout.standAt(site, x, z)
	local desk = WarehouseLayout.terminal(site)
	local own = stand ~= nil and ann ~= nil and (stand <= Collection.stands(ann) -- (10.4: or one of her showroom's plinths)
		or (stand > Config.Showroom.Base and stand <= Config.Showroom.Base + Collection.showStands(ann)))
	return own or (math.abs(x - desk.x) <= desk.sx / 2 and math.abs(z - desk.z) <= desk.sz / 2)
end
local function look()
	local level = Warehouse.level(1)
	mostAt[level] = math.max(mostAt[level] or 0, Visitors.count(1))
	mostAll = math.max(mostAll, Visitors.count())
	local inside = WarehouseLayout.inside(siteAt(level))
	for _, v in Visitors.list() do
		local p = v.model.PrimaryPart.Position
		if v.plot == 1 and p.X > inside.x0 and p.X < inside.x1 and p.Z > inside.z0 and p.Z < inside.z1
			and caughtAt(level, p.X, p.Z) and v.state ~= "in" and v.state ~= "out" then
			walled = walled or `{v.state} at {math.floor(p.X)},{math.floor(p.Z)} (level {level})`
		end
	end
end
local function run(seconds: number, until_: (() -> boolean)?): boolean
	for _ = 1, math.ceil(seconds) do
		E.advance(1)
		look()
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
local function standIn(level: number)
	local zone = WarehouseLayout.receiving(siteAt(level))
	return V3((zone.x0 + zone.x1) / 2 + 3, 3, (zone.z0 + zone.z1) / 2)
end
local function setLevel(level: number)
	Upgrades.admin(ann, `level{level}`)
	run(2, function()
		return Warehouse.level(1) == level
	end)
end
-- What a visitor that stops (looks, offers) must never stand in: the door path, the desk's spot, a podium.
local function stopsBad(level: number): string?
	local path = WarehouseLayout.doorPath(siteAt(level))
	local desk = WarehouseLayout.terminal(siteAt(level))
	for _, v in visitorsIn(1) do
		if v.state == "look" or v.state == "offer" then
			local p = v.model.PrimaryPart.Position
			if p.X > path.x0 and p.X < path.x1 and p.Z > path.z0 and p.Z < path.z1 then
				return "in the door path"
			end
			if math.abs(p.X - desk.x) < desk.sx / 2 + T.DeskClear - 0.5 and math.abs(p.Z - desk.z) < desk.sz / 2 + T.DeskClear - 0.5 then
				return "at the desk"
			end
			if WarehouseLayout.standAt(siteAt(level), p.X, p.Z) ~= nil then
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
-- (10.4: on the showroom's plinths, as many as she has; a piece too big for a plinth stays in the stock)
local function show(count: number)
	local shown = 0
	for _, entry in Collection.stock(ann) do
		if entry.stand then
			Collection.undisplay(ann, entry.uid)
		end
	end
	for _, entry in Collection.stock(ann) do
		if shown < math.min(count, Collection.showStands(ann)) and Collection.display(ann, entry.uid, Config.Showroom.Base + shown + 1) then
			shown += 1
		end
	end
	E.flush()
end

-- ── Ann: her warehouse (a new player's: the Garage), nothing on show ──────
ann = E.join(11, "Ann")
E.advance(2)
check("(Ann's warehouse: the Garage, level 1, 2 stands)", Warehouse.level(1) == 1 and Collection.stands(ann) == 2)
local annSave = PlayerData.get(ann) :: any
annSave.sandboxUpgrades.showstands = 3 -- (10.4: her showroom as big as each level has room for)
check("(10.4: her Garage's showroom: 2 plinths)", Collection.showStands(ann) == 2, Collection.showStands(ann))
E.place(ann, standIn(1))
run(90)
check("nothing on show: nobody comes, though Ann is in her warehouse", #bodies == 0 and Visitors.count() == 0)

-- ── The Garage: two pieces on show, one visitor at a time ─────────────────
local items = { "piano", "sofa", "armchair", "grandfather_clock", "bookshelf", "guitar" }
for _, item in items do
	Collection.add(ann, { item = item, condition = 1 })
end
E.flush()
-- 10.4: a piece in the collection hall only: nobody comes for it
Collection.display(ann, Collection.stock(ann)[1].uid, 1)
E.flush()
run(T.FirstWait[2] + T.Stagger * 3 + 5)
check("10.4: a piece in the collection hall only (none in the showroom): nobody comes", #bodies == 0 and Visitors.count() == 0, #bodies)
show(2)
check("10.4: … two in the showroom (the piano too big for a Garage plinth: the next pieces)", (function()
	local n = 0
	for _, entry in Collection.stock(ann) do
		n += if entry.stand and entry.stand > Config.Showroom.Base then 1 else 0
	end
	return n == 2
end)())
local names: { string } = {}
for _, entry in Collection.stock(ann) do
	table.insert(names, string.lower(entry.name))
end
local spawnedAt = E.clock
run(T.FirstWait[2] + T.Stagger * 3 + 1, function()
	return #bodies > 0
end)
check(`pieces on show, Ann at her Garage: a visitor within FirstWait s ({math.floor(E.clock - spawnedAt)} s)`, #bodies >= 1 and E.clock - spawnedAt <= T.FirstWait[2] + 1.5)
check("… its body in workspace.Npcs with its kind (attribute Visitor)", bodies[1].Parent ~= nil and Rules.kind(bodies[1]:GetAttribute("Visitor")) ~= nil)
local function entryChecks(level: number, body: any, label: string)
	local bay = WarehouseLayout.bay(plot1)
	local door = WarehouseLayout.door(siteAt(level))
	local legs = {}
	run(20, function()
		table.clear(legs)
		for _, s in sent do
			if s.npc == body then
				table.insert(legs, s.point)
			end
		end
		return #legs >= 2
	end)
	local startAt = born[body]
	local approach, threshold = legs[1], legs[2]
	check(`{label}: it walks in from beside the van (off the UNLOAD HERE bay), turns in behind its back and through the door's side`, approach ~= nil and threshold ~= nil
		and approach.Z > door.z and approach.Z < door.z + SandboxMap.VanGap and math.abs(approach.X - door.x) > bay.x1 - plot1.vanSpot.x
		and math.abs(threshold.X - door.x) <= door.width / 2 and math.abs(threshold.X - door.x) >= 2 and math.abs(threshold.Z - door.z) < 3
		and not (startAt.X > bay.x0 and startAt.X < bay.x1 and startAt.Z > bay.z0 and startAt.Z < bay.z1))
end
entryChecks(1, bodies[1], "the Garage")
local bad: string? = nil
local looked = run(120, function()
	bad = bad or stopsBad(1)
	return false
end)
check(`the Garage: one visitor at a time at most ({mostAt[1]}), stopping clear of the door path, the desk and the podiums`, (mostAt[1] or 0) == Rules.perHall(1)
	and Rules.perHall(1) == 1 and bad == nil, bad)

-- ── The Big warehouse (level 4): six pieces on show, a group ──────────────
setLevel(4)
check("(Ann's warehouse rebuilt at level 4: 12 stands)", Warehouse.level(1) == 4 and Collection.stands(ann) == 12)
E.place(ann, standIn(4))
show(6)
run(T.NearEvery[2] + T.Life, function()
	return Visitors.count(1) == 0
end)
local before = #bodies
run(T.NearEvery[2] + T.Stagger * 3 + 1, function()
	return #bodies > before
end)
run(T.Stagger * 3)
local group = #bodies - before
check(`level 4: a group of 1 – 3 ({group})`, group >= 1 and group <= 3)
entryChecks(4, bodies[before + 1], "level 4")

-- they look at pieces: a stop at a stand with a piece, one visitor a stand, a line about it now and then
looked = run(60, function()
	for _, v in visitorsIn(1) do
		if v.state == "look" then
			return true
		end
	end
	return false
end)
check("a visitor stops at a piece on show and looks at it", looked)
bad = nil
run(40, function()
	bad = bad or stopsBad(4)
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
	E.place(ann, standIn(4))
end
check(`at most PerHall in her hall by its level ({mostAt[1]} in the Garage, {mostAt[4]} at level 4), Cap ({T.Cap}) in the server, all along`,
	(mostAt[1] or 0) <= Rules.perHall(1) and (mostAt[4] or 0) <= Rules.perHall(4) and (mostAt[4] or 0) >= 1 and mostAll <= T.Cap, `{mostAt[4]} {mostAll}`)

-- ── A hall built again with visitors in it: a level bought, a level lost ───
T.Offer.Chance = 0
local function lookers(): number
	local n = 0
	for _, v in visitorsIn(1) do
		if v.state == "look" then
			n += 1
		end
	end
	return n
end
check("(visitors looking at pieces in the Big warehouse)", run(T.NearEvery[2] + 60, function()
	return lookers() > 0
end))
local inHall = Visitors.count(1)
setLevel(5)
local states: { [string]: boolean } = {}
for _, v in visitorsIn(1) do
	states[v.state] = true
end
check(`level 5 bought with {inHall} in the hall: rebuilt (the Logistics centre), every visitor on its way out on the new ways`, Warehouse.level(1) == 5
	and states.look == nil and states["in"] == nil and states.offer == nil)
run(T.Life, function()
	return Visitors.count(1) == 0
end)
check("… all gone out (none stuck)", Visitors.count(1) == 0)
for index = 1, 14 do
	Collection.add(ann, { item = items[(index - 1) % #items + 1], condition = 1 })
end
E.flush()
show(18)
check("(level 5: visitors at its showroom's far plinths, deep in the hall)", run(T.NearEvery[2] + 120, function()
	for _, v in visitorsIn(1) do
		if v.state == "look" and v.stand and v.stand >= Config.Showroom.Base + 5 then
			return true
		end
	end
	return false
end))
local deep: any = nil
for _, v in visitorsIn(1) do
	if v.state == "look" and v.stand and v.stand >= Config.Showroom.Base + 5 then
		deep = v.model
	end
end
setLevel(1)
local garage = WarehouseLayout.outline(siteAt(1))
local stillInside = false
for _, v in visitorsIn(1) do
	local p = v.model.PrimaryPart.Position
	if p.X > garage.x0 and p.X < garage.x1 and p.Z > garage.z0 and p.Z < garage.z1 and caughtAt(1, p.X, p.Z) then
		stillInside = true
	end
end
check("back to the Garage (the admin's level 1) with visitors deep in the hall: none left in its walls, on its podiums or at its desk; the one at a far plinth on its way out",
	Warehouse.level(1) == 1 and not stillInside and deep ~= nil and (deep.Parent == nil or (function()
		for _, v in visitorsIn(1) do
			if v.model == deep then
				return v.state == "out"
			end
		end
		return true
	end)()))
run(T.Life, function()
	return Visitors.count(1) == 0
end)
check("… all gone (none stuck)", Visitors.count(1) == 0)
check("no visitor ever stood inside her hall's walls, on a podium or at the desk (a look every second, every level)", walled == nil, walled)
setLevel(4)
show(6)
E.place(ann, standIn(4))
T.Offer.Chance = 2

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
E.place(ann, standIn(4))
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
show(4) -- (10.4: on the showroom's plinths)
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
