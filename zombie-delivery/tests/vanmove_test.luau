-- 7.x van moves and the farm move's pure parts: shared/MovingRules.luau's trips (deliver: everything in the van and on its
-- hitch, late after the clock; lose: a lost van's load; setBed), the hitch (a piece too big for the bed that may be
-- towed: one at a time, Unload takes it off last), the pay over the trips (late ones at LateShare, the contract's pay);
-- shared/HouseLayout.luau's ways (exitsOf, entries, exitsFor: the farm's hay wagon by the barn doors only);
-- shared/MoveHelperBrain.luau routeVia (Danny's nearest way he may take); shared/NpcLooks.luau's Walt; MoveStory's ★
-- lines. Run with tests/run_tests.py.
local Rules = require("./MovingRules")
local Config = require("./Config")
local Brain = require("./MoveHelperBrain")
local HouseLayout = require("./HouseLayout")
local NpcLooks = require("./NpcLooks")
local MoveStory = require("./MoveStory")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Moving
local P = T.Pay
local ME = 1
local defs: { [string]: Rules.ItemDef } = {
	lamp = { id = "lamp", name = "Lamp", icon = "💡", size = { X = 1, Y = 3, Z = 1 }, class = "hand", weight = 1, value = 40, fragile = false, room = "living" },
	clock = { id = "clock", name = "Clock", icon = "🕰", size = { X = 1.5, Y = 4, Z = 1 }, class = "both", weight = 6, value = 400, fragile = false, room = "hall" },
	wagon = { id = "wagon", name = "Hay Wagon", icon = "🛞", size = { X = 6.4, Y = 4.8, Z = 9.6 }, class = "pair", weight = 9, value = 650, fragile = false, room = "barn", tow = true },
	slab = { id = "slab", name = "Slab", icon = "🪨", size = { X = 6.4, Y = 4.8, Z = 9.6 }, class = "pair", weight = 9, value = 100, fragile = false, room = "barn" },
}
local spots: { Rules.Spot } = {
	{ id = 1, item = "lamp", room = "living", star = false },
	{ id = 2, item = "clock", room = "hall", star = true },
	{ id = 3, item = "wagon", room = "barn", star = false },
	{ id = 4, item = "slab", room = "barn", star = false },
	{ id = 5, item = "lamp", room = "living", star = false },
}
local V = T.Beds[T.Van]
local VAN: Rules.Bed = { width = V.Width, length = V.Length, height = V.Height, cell = V.Cell }

-- The van's bay ---------------------------------------------------------------------------------------------------------------

check("the ZDC Van's bay: 6.2 wide, 6.4 long, 4.3 tall (its cargo box less its walls), smaller than the old truck's", V.Width == 6.2 and V.Length == 6.4 and V.Height == 4.3
	and V.Width * V.Length * V.Height < T.Beds.movingtruck.Width * T.Beds.movingtruck.Length * T.Beds.movingtruck.Height)

-- The hitch ---------------------------------------------------------------------------------------------------------------------

local move = Rules.newMove(spots, defs, VAN, 0, 600, 120, 1.25)
check("a contract's own horde time and pay on the move", move.hordeAt == 120 and move.pay == 1.25 and move.trips == 0 and Rules.due(move, 600 - 121) == nil
	and Rules.due(move, 600 - 120) == "horde")
check("the hay wagon may be towed (its def), the slab not", move.things[3].tow == true and move.things[4].tow ~= true)
Rules.pick(move, 4, ME)
local at, why = Rules.load(move, ME)
check("too big for the van and not towable: no room, still in your hands", at == nil and why == "noroom" and move.things[4].state == "carried")
Rules.release(move, ME)
Rules.pick(move, 3, ME)
at, why = Rules.load(move, ME)
check("too big for the bed and towable: on the hitch", at ~= nil and at.hitch == true and move.hitch == 3 and move.things[3].state == "truck" and Rules.fill(move.packing) == 0)
local wagon2 = Rules.newMove({ { id = 1, item = "wagon", room = "barn", star = false }, { id = 2, item = "wagon", room = "barn", star = false } }, defs, VAN, 0, 600)
Rules.pick(wagon2, 1, ME)
Rules.load(wagon2, ME)
Rules.pick(wagon2, 2, ME)
at, why = Rules.load(wagon2, ME)
check("one on the hitch at a time", at == nil and why == "hitched" and #Rules.whyText("hitched") > 0)
Rules.pick(move, 2, ME)
Rules.load(move, ME)
check("Unload takes the bed's last one first", Rules.lastOut(move) == 2)
local out = Rules.unload(move, ME)
Rules.load(move, ME)
check("…and the hitch's once the bed is empty", out == 2 and (function()
	local m = Rules.newMove(spots, defs, VAN, 0, 600)
	Rules.pick(m, 3, ME)
	Rules.load(m, ME)
	local took = Rules.unload(m, ME)
	return took == 3 and m.hitch == nil and m.things[3].state == "carried"
end)())

-- Trips -------------------------------------------------------------------------------------------------------------------------

local c = Rules.counts(move)
check("in the van: the clock and the wagon", c.out == 2 and c.delivered == 0 and c.starsOut == 1)
local delivered = Rules.deliver(move, 100)
c = Rules.counts(move)
check("trip 1 at the Wall: both delivered (the hitch too), the bed empty again, one trip", #delivered == 2 and c.delivered == 2 and c.starsDelivered == 1 and c.out == 0
	and move.trips == 1 and move.hitch == nil and #move.packing.placed == 0 and move.things[2].late == false)
check("an empty van delivers nothing: no trip", #Rules.deliver(move, 200) == 0 and move.trips == 1)
Rules.pick(move, 1, ME)
Rules.load(move, ME)
local lost = Rules.lose(move)
c = Rules.counts(move)
check("the van lost: what was in it is lost (condition 0), the bed empty", #lost == 1 and move.things[1].state == "lost" and move.things[1].condition == 0 and c.lost == 1
	and #move.packing.placed == 0)
Rules.setBed(move, { width = 7, length = 10, height = 7.4, cell = 0.5 })
check("another car's bed (the van called again): empty, its own size", move.packing.cols == 14 and move.packing.rows == 20 and #move.packing.placed == 0)
Rules.pick(move, 5, ME)
Rules.load(move, ME)
Rules.deliver(move, 700) -- (after the clock ran out at 600: late)
check("a trip after the clock: delivered late", move.things[5].state == "delivered" and move.things[5].late == true and move.trips == 2)
local r = Rules.result(move, "late", 700)
local onTime = (400 * P.Star + 650) * P.Scale * 1.25
local late = 40 * P.Scale * 1.25 * P.LateShare
check("the pay: every trip's things, the late one at LateShare, × the contract's pay, the lost one nothing", r.delivered == 3 and math.abs(r.base + r.starBonus - (onTime + late)) < 1e-6
	and r.total == math.floor(onTime + late + 0.5) and r.stars <= 3, r.total)
check("only what reached the Wall pays: the van's load at the end does not", (function()
	local m = Rules.newMove(spots, defs, VAN, 0, 600)
	Rules.pick(m, 2, ME)
	Rules.load(m, ME)
	return Rules.result(m, "done", 300).total == 0 and Rules.result(m, "done", 300).delivered == 0
end)())
check("the card's estimate × the contract's pay", Rules.estimate(spots, defs, 1.25) == math.floor((40 + 400 * P.Star + 650 + 100 + 40) * P.Scale * 1.25 + 0.5))

-- The farm's ways (shared/HouseLayout.luau) ------------------------------------------------------------------------------------

local farm = HouseLayout.plan(1921, "farm")
local house = HouseLayout.plan(1955, "house")
local exits = HouseLayout.exitsOf(farm)
local entries = HouseLayout.entries(farm)
check("the farm's ways: the front door and the barn doors; a house's: its front door", #exits == 2 and #entries == 2 and #HouseLayout.exitsOf(house) == 1
	and #HouseLayout.entries(house) == 1 and HouseLayout.entries(house)[1] == house.entry)
local barnIn = entries[2].Position
check("in by the barn doors: EntryIn in from its doorway, facing into the barn, at EntryUp", entries[1] == farm.entry
	and math.abs((barnIn - exits[2]).Magnitude - Config.Furniture.EntryIn) < 1e-6 and math.abs(barnIn.Y - Config.Furniture.EntryUp) < 1e-6
	and barnIn.Z < exits[2].Z)
local wagonExits = HouseLayout.exitsFor(farm, "hay_wagon")
local saddleExits = HouseLayout.exitsFor(farm, "thunders_saddle")
check("the hay wagon (bigDoor) by the barn doors only, the saddle by either, a house's piece by its front door", #wagonExits == 1 and wagonExits[1] == 2
	and #saddleExits == 2 and #HouseLayout.exitsFor(house, "sofa") == 1)

-- Danny's way (MoveHelperBrain.routeVia) ----------------------------------------------------------------------------------------

local front = { outX = 0, outZ = -10, inX = 0, inZ = 0 }
local barnDoors = { outX = -100, outZ = 20, inX = 0, inZ = 80 }
local cost, which = Brain.routeVia(true, 0, 70, false, -100, 40, { front, barnDoors })
check("routeVia: from the barn to the van at the barn: by the barn doors", which == 2 and math.abs(cost - (10 + 20)) < 1e-6, `{cost} {which}`)
cost, which = Brain.routeVia(true, 0, 5, false, 0, -30, { front, barnDoors })
check("…from the farmhouse to the van at its door: by the front door", which == 1 and math.abs(cost - (5 + 20)) < 1e-6)
_, which = Brain.routeVia(true, 0, 5, false, -100, 40, { front, barnDoors }, { 2 })
check("…only the ways he may take (the allowed ones)", which == 2)
check("…a single door is routeCost", (Brain.routeVia(false, 0, -30, true, 0, 5, { front })) == Brain.routeCost(false, 0, -30, true, 0, 5, front))

-- Walt, his lines -------------------------------------------------------------------------------------------------------------

local walt = NpcLooks.person("walt", "rancher", "Walt", "Client")
check("Walt's look: the rancher's hat and boots, a check shirt (no vest), a moustache, grey hair", walt.hat == "cowboy" and walt.boots == true and walt.plaid ~= nil
	and walt.vest == nil and walt.moustache ~= nil and walt.hair ~= nil and walt.name == "Walt")
check("Marge as the dispatcher, anybody else their role's look", NpcLooks.person("marge", "clerk", "Marge").vest ~= nil and NpcLooks.person("ellie", "doctor", "Ellie").coat ~= nil)
local greeter = MoveStory.greeterOf("walt") :: MoveStory.Greeter
check("Walt's ★ lines: Thunder's saddle its own, another ★ piece his star line", MoveStory.starLine(greeter, "thunders_saddle") == "Easy with Thunder's saddle!"
	and MoveStory.starLine(greeter, "nothing") == greeter.star and MoveStory.starLine(MoveStory.greeterOf("marge") :: MoveStory.Greeter, "grandfather_clock") == "Careful with that!")
-- 8.0 SANDBOX: the Sprinter's walk-in bay, the sandbox's house ------------------------------------------------------------

local FurnitureLooks = require("./FurnitureLooks")
local SandboxMap = require("./SandboxMap")
local SP = T.Beds.sprinter
local SPRINTER: Rules.Bed = { width = SP.Width, length = SP.Length, height = SP.Height, cell = SP.Cell }
check("the Sprinter's bay: 6.6 wide, 7.6 tall, 14 long, walk-in, its back from the van's doors; far bigger than the ZDC Van's", SP ~= nil and SP.Width == 6.6
	and SP.Height == 7.6 and SP.Length == 14 and SP.WalkIn == true and type(SP.Back) == "number" and SP.Cell >= 0.4 and SP.Cell <= 0.5
	and SP.Width * SP.Length * SP.Height > 2.5 * V.Width * V.Length * V.Height)
check("…the ZDC Van's bay is no walk-in one (the city's game as it was)", V.WalkIn ~= true and V.Back == nil)
do
	local lying, missing = {}, {}
	local farm: { [string]: boolean } = {}
	for _, id in FurnitureLooks.FarmPieces do
		farm[id] = true
	end
	for _, id in FurnitureLooks.Order do
		local def = FurnitureLooks.Items[id]
		local size = { X = def.size.X, Y = def.size.Y, Z = def.size.Z }
		local empty = Rules.newPacking(SP.Width, SP.Length, SP.Height, SP.Cell)
		if not Rules.fit(empty, size, def.fragile, false) then
			table.insert(lying, id)
		end
		if not Rules.room(empty, size, def.class ~= "hand") then
			table.insert(missing, id)
		end
		if not farm[id] and table.find(lying, id) then
			table.insert(missing, `{id} (a house piece lying)`)
		end
	end
	check("every piece goes into the empty Sprinter (the farm's hay wagon too); every house piece standing", #missing == 0, table.concat(missing, ", "))
end
do -- a whole house (shared/HouseLayout.luau plan) loaded piece after piece: the Sprinter takes far more than the ZDC Van
	local defs2: { [string]: Rules.ItemDef } = {}
	for id, def in FurnitureLooks.Items do
		defs2[id] = { id = id, name = def.name, icon = def.icon, size = { X = def.size.X, Y = def.size.Y, Z = def.size.Z }, class = def.class, weight = def.weight, value = def.value,
			fragile = def.fragile, room = def.room, tow = def.bigDoor == true }
	end
	local function loaded(seed: number, bed: Rules.Bed): number
		local plan = HouseLayout.plan(seed, "house")
		local list: { Rules.Spot } = {}
		for _, spot in plan.spots do
			table.insert(list, { id = spot.id, item = spot.item, room = spot.room, star = spot.star })
		end
		local m = Rules.newMove(list, defs2, bed, 0, 600)
		local n = 0
		for _, spot in m.order do
			Rules.pick(m, spot, ME)
			if Rules.load(m, ME) then
				n += 1
			else
				Rules.release(m, ME)
			end
		end
		return n
	end
	local sprinter, van = loaded(7, SPRINTER), loaded(7, VAN)
	-- (8.0 merge: a house holds 2 – 4 small collectibles now, which both bays take: the ratio is a little lower)
	check("a whole house loaded in one go: the Sprinter takes far more than the ZDC Van", sprinter >= 1.3 * van and sprinter >= 12, `{sprinter} vs {van}`)
end
check("a new seed is a new house (the sandbox refills it every move)", (function()
	local a, b = HouseLayout.plan(101, "house"), HouseLayout.plan(202, "house")
	local same = #a.spots == #b.spots
	for index, spot in a.spots do
		local other = b.spots[index]
		if not other or other.item ~= spot.item or (other.at.Position - spot.at.Position).Magnitude > 0.01 then
			same = false
		end
	end
	return not same
end)())
check("the sandbox's house: SandboxMap.House's id and name, 20 minutes, no horde and no roamers by default (no guns), switches kept",
	SandboxMap.House.id == "sandbox_house" and SandboxMap.House.name == "The Old Chalet" and T.Sandbox.Time == 20 * 60 and T.Sandbox.Horde == false
	and T.Sandbox.Roam == 0 and T.Sandbox.HordeAt > 0 and T.Sandbox.HordeAt < T.Sandbox.Time and #T.Sandbox.Blurb <= Config.MoveStory.Limits.Blurb)
check("the sandbox's van is the Sprinter, its bed set", Config.Sandbox.Van == "sprinter" and T.Beds[Config.Sandbox.Van] ~= nil)
check("the house's front door looks out to the road, the van's curb between them (its back to the door)", (function()
	local h = SandboxMap.House
	local road = SandboxMap.Turnaround
	return h.door.yaw == 0 and h.curb.yaw == 0 and h.curb.z < h.door.z and math.abs(h.curb.z - road.z) <= road.r and h.door.z - h.curb.z > SP.Length / 2
end)())

check("Walt's lines fit their bubbles", (function()
	local L = Config.MoveStory.Limits.Bubble
	for _, text in greeter.hello do
		if #text > L then
			return false
		end
	end
	for _, text in greeter.stars or {} do
		if #text > L then
			return false
		end
	end
	return #greeter.star <= L and #greeter.horde <= L and #greeter.leave <= L and #greeter.hello >= 2 and #greeter.hello <= 3
end)())

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
