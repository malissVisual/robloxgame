-- Logic test of 4.0's freight and equipment (shared/Freight.luau, Config.Cargo, Config.JobTypes "freightrun",
-- shared/Map.luau FreightDocks / ReceivingDocks): who takes what on a trolley or a jack, the walks, the room in a
-- vehicle, where the pallets stand in one, the tools going home, the job card's tip, the Freight Run and its docks.
-- Works with and without Stream V's Freight Truck / Economy.palletsOf (the checks that need them are guarded).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Freight = require("./Freight")
local Map = require("./Map")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Tuning = Config.Cargo

-- The numbers ----------------------------------------------------------------------

check("a trolley takes 4 pieces, a pallet uses 4 slots", Tuning.TrolleyPieces == 4 and Tuning.PalletSlots == 4)
check("the walks: walk > empty trolley > loaded trolley > jack", Config.Movement.Walk > Tuning.TrolleySpeed
	and Tuning.TrolleySpeed > Tuning.TrolleyLoadedSpeed and Tuning.TrolleyLoadedSpeed > Tuning.JackSpeed and Tuning.JackSpeed >= 4,
	`{Tuning.TrolleySpeed} / {Tuning.TrolleyLoadedSpeed} / {Tuning.JackSpeed}`)
check("about 10 empty, 8.5 loaded, 6 with the jack", math.abs(Tuning.TrolleySpeed - 10) <= 1 and math.abs(Tuning.TrolleyLoadedSpeed - 8.5) <= 1 and math.abs(Tuning.JackSpeed - 6) <= 1)
check("a trolley left goes home after 60 s, a jack after a while", Tuning.TrolleyReturnSeconds == 60 and Tuning.JackReturnSeconds >= 30)
check("the pallet is a cargo kind", Tuning.Kinds.pallet ~= nil and Tuning.Kinds.pallet.look == "pallet")
check("a pallet is not light", not Tuning.LightLooks.pallet)
check("handling a pallet takes time", (Tuning.TimePerPiece.pallet or 0) > Tuning.TimePerPiece.carry)

-- Who takes what --------------------------------------------------------------------

local function max(kind: string, look: string, tool: string?, lift: boolean?, pair: boolean?): number
	return Freight.handsMax(kind, look, lift, pair, tool)
end
check("a pallet never by hand", max("pallet", "pallet", nil) == 0)
check("a pallet on a jack: one", max("pallet", "pallet", "jack") == 1)
check("a pallet not on a trolley", max("pallet", "pallet", "trolley") == 0)
check("a crate not on a jack", max("crate", "crate", "jack") == 0)
check("four crates on a trolley", max("crate", "crate", "trolley") == 4)
check("four parcels on a trolley", max("crate", "parcel", "trolley") == 4)
check("no horse on a trolley", max("horse", "horse", "trolley") == 0)
check("no people on a trolley", max("kid", "kid", "trolley") == 0 and max("patient", "patient", "trolley") == 0 and max("survivor", "survivor", "trolley") == 0)
check("no trolley on a lift or pair job", max("crate", "crate", "trolley", true) == 0 and max("crate", "crate", "trolley", nil, true) == 0)
check("the hands as in 3.7: two light, one heavy", max("crate", "parcel", nil) == Tuning.HandsMax and max("crate", "crate", nil) == 1 and max("horse", "horse", nil) == 1)
check("a light piece on a lift job: one", max("crate", "parcel", nil, true) == 1)
check("every refusal says why", string.find(Freight.refusal("pallet", nil, nil, nil), "pallet jack", 1, true) ~= nil
	and string.find(Freight.refusal("crate", nil, nil, "jack"), "only lifts pallets", 1, true) ~= nil
	and string.find(Freight.refusal("crate", true, nil, "trolley"), "by hand", 1, true) ~= nil)
check("the prompt's words for a pallet by hand", Freight.refusal("pallet", nil, nil, nil) == "Too heavy: use a pallet jack.")

-- The walks and the room -------------------------------------------------------------

check("the walk with an empty / loaded trolley, the jack", Freight.walkSpeed("trolley", 0) == Tuning.TrolleySpeed
	and Freight.walkSpeed("trolley", 3) == Tuning.TrolleyLoadedSpeed and Freight.walkSpeed("jack", 1) == Tuning.JackSpeed)
check("pallet room", Freight.palletRoom(3, 1) == 2 and Freight.palletRoom(1, 1) == 0 and Freight.palletRoom(0, 0) == 0 and Freight.palletRoom(1, 3) == 0)
check("piece room", Freight.pieceRoom(4, 1) == 3 and Freight.pieceRoom(2, 2) == 0 and Freight.pieceRoom(2, 5) == 0)

-- Where the pallets stand in a vehicle -----------------------------------------------

-- A box like the Moving Truck's: three rows of two on the floor, a second layer above.
local truck = {
	{ x = -1.8, y = 0.6, z = -0.6 }, { x = 1.8, y = 0.6, z = -0.6 }, { x = -1.8, y = 0.6, z = 2.8 }, { x = 1.8, y = 0.6, z = 2.8 },
	{ x = -1.8, y = 0.6, z = 6.2 }, { x = 1.8, y = 0.6, z = 6.2 }, { x = -1.8, y = 4.2, z = -0.6 }, { x = 1.8, y = 4.2, z = -0.6 },
}
local spots = Freight.palletSpots(truck, 2)
check("two pallets, two spots", #spots == 2)
check("the first pallet at the front 2×2 group's middle, on the floor", math.abs(spots[1].x) < 0.01 and math.abs(spots[1].y - 0.6) < 0.01 and math.abs(spots[1].z - 1.1) < 0.01, `{spots[1].x}, {spots[1].y}, {spots[1].z}`)
check("the second one behind it", spots[2].z > spots[1].z + 3.5, spots[2].z)
check("no slots, no spots", #Freight.palletSpots({}, 2) == 0 and #Freight.palletSpots(truck, 0) == 0)
-- The Freight Truck's way: slots 1–4, 5–8, 9–12 are its three pallet bays.
local bays = {}
for bay = 0, 2 do
	for _, x in { -1.8, 1.8 } do
		for _, dz in { 0, 3.4 } do
			table.insert(bays, { x = x, y = 0.5, z = -4 + bay * 7 + dz })
		end
	end
end
local three = Freight.palletSpots(bays, 3)
check("a pallet bay per four slots", #three == 3 and math.abs(three[1].z - -2.3) < 0.01 and math.abs(three[2].z - 4.7) < 0.01 and math.abs(three[3].z - 11.7) < 0.01,
	`{three[1] and three[1].z}, {three[2] and three[2].z}, {three[3] and three[3].z}`)
-- A small van: only one 2×2 group, a second pallet in a row behind (generic for a trailer later).
local van = { { x = -1.6, y = 0.5, z = 0 }, { x = 1.6, y = 0.5, z = 0 }, { x = -1.6, y = 0.5, z = 3.4 }, { x = 1.6, y = 0.5, z = 3.4 } }
local two = Freight.palletSpots(van, 2)
check("past the slot groups the pallets go on in a row", #two == 2 and two[2].z > two[1].z)

-- On the trolley ---------------------------------------------------------------------

local one = Freight.trolleyStack({ 2 })
check("one piece in the middle of the toe plate", #one == 1 and one[1].x == 0 and one[1].y == 0)
local four = Freight.trolleyStack({ 2, 1.5, 2, 1.5 })
check("four: two side by side, two on top", #four == 4 and four[1].x < 0 and four[2].x > 0 and four[3].y == 2 and four[4].y == 1.5 and four[1].y == 0)

-- Going home -------------------------------------------------------------------------

check("a trolley goes home after 60 s with nobody near", Freight.returnsHome("trolley", 61, true) and not Freight.returnsHome("trolley", 30, true))
check("never with somebody near", not Freight.returnsHome("trolley", 600, false) and not Freight.returnsHome("jack", 600, false))
check("a jack after its own while", Freight.returnsHome("jack", Tuning.JackReturnSeconds, true))

-- The job card's tip ------------------------------------------------------------------

check("a trolley helps from 4 pieces", Freight.trolleyTip("crate", 4, "carry") ~= nil and Freight.trolleyTip("crate", 3, "carry") == nil)
check("no tip for horses, people, pallets", Freight.trolleyTip("horse", 4, "lead") == nil and Freight.trolleyTip("kid", 6, "board") == nil and Freight.trolleyTip("pallet", 3, "pallet") == nil)

-- How many pallets a vehicle takes (Stream V: Economy.palletsOf) ------------------------

local hasPallets = type((Economy :: any).palletsOf) == "function"
check("palletsOf is a number for every car", (function()
	for _, def in Config.Cars do
		local n = Freight.palletsOf(def.id, 0)
		if type(n) ~= "number" or n < 0 then
			return false
		end
	end
	return Freight.palletsOf("no such car", 0) == 0
end)())
if hasPallets and Economy.findCar("freight") then
	check("the Freight Truck takes 3 pallets", Freight.palletsOf("freight", 0) == 3, Freight.palletsOf("freight", 0))
	check("a vehicle takes the Freight Run's 3 pallets", Freight.maxPallets("freight") >= 3)
else
	print("skip  the Freight Truck (Stream V) is not here yet")
end
local lock, button = Freight.lockText(2, "Old Van", 0)
check("the lock says what it needs", string.find(lock, "takes 2 pallets", 1, true) ~= nil and string.find(lock, "takes no pallets", 1, true) ~= nil and button == "🚚 NEEDS 2 PALLETS", lock)

-- The Freight Run ----------------------------------------------------------------------

local job = Economy.findJobType("freightrun")
check("the Freight Run is a job type", job ~= nil)
if job then
	check("pallets on a jack both ways", job.load == "pallet" and job.unload == "pallet" and job.itemKind == "pallet")
	check("1 – 3 pallets", job.items == 3)
	check("on the board, no lent vehicle, no employer", Economy.onBoard(job) and job.vehicle == nil and job.employer == nil and job.board == true)
	check("about ★★★", job.tier == 3)
	check("good pay", job.payPerStop * 2 + Tuning.PalletPay >= 500, job.payPerStop)
	check("a level that can be reached", Economy.jobLevel(job, job.tier) >= Config.Jobs.Tiers[job.tier].level and Economy.jobLevel(job, job.tier) <= Config.Levels.MaxLevel)
	check("no cargo slots counted the hand way (the pallets lock it)", Economy.cargoNeed(job.load, job.items) == 0)
	check("loaded at the warehouse's docks", job.pickupAt == "warehouse" and Map.FreightDocks.warehouse ~= nil)
	check("its people", Config.Jobs.People.freightrun ~= nil)
	local drops = job.dropChoices or {}
	check("two or three receiving docks", #drops >= 2 and #drops <= 3, #drops)
	for _, id in drops do
		check(`drop {id}: a receiving dock, a place, a receiver`, Map.ReceivingDocks[id] ~= nil and Map.CargoSpots[id] ~= nil and Config.Jobs.FreightReceivers[id] ~= nil)
	end
end

-- The docks -------------------------------------------------------------------------------

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end
local function inside(x: number, z: number, box: { x0: number, z0: number, x1: number, z1: number }, margin: number): boolean
	return x >= box.x0 + margin and x <= box.x1 - margin and z >= box.z0 + margin and z <= box.z1 - margin
end
local hub = Map.FreightDocks.warehouse
if hub then
	local d, bi, bj = Map.blockAt(hub.giver.x, hub.giver.z)
	check("the hub is on the warehouse's block", d ~= nil and Map.special(d.id, bi, bj) == "warehouse")
	check("two loading docks", #hub.docks == 2)
	check("the dock floor is a truck's floor", hub.height >= 2 and hub.height <= 3)
	check("the foreman stands on the dock", inside(hub.giver.x, hub.giver.z, hub.platform, 0.5))
	local spot = Map.CargoSpots.warehouse
	for n, dock in hub.docks do
		local pd, pi, pj = Map.blockAt(dock.park.x, dock.park.z)
		check(`dock {n}: its bay on the block, off the road`, pd == d and pi == bi and pj == bj)
		check(`dock {n}: the truck backs up to the dock edge`, dist(dock.park.x, dock.park.z, dock.edge.x, dock.edge.z) >= 12 and dist(dock.park.x, dock.park.z, dock.edge.x, dock.edge.z) <= Config.Jobs.DeliverRadius
			and math.abs(dock.edge.x - hub.platform.x0) < 0.01)
		check(`dock {n}: room for the job's pallets on the dock floor`, #dock.staging >= job.items and (function()
			for _, s in dock.staging do
				if not inside(s.x, s.z, hub.platform, 2) then
					return false
				end
			end
			for a = 1, #dock.staging do
				for b = a + 1, #dock.staging do
					if dist(dock.staging[a].x, dock.staging[a].z, dock.staging[b].x, dock.staging[b].z) < 4.4 then
						return false
					end
				end
			end
			return true
		end)())
		check(`dock {n}: the old mission's door stays clear`, spot ~= nil and dist(dock.park.x, dock.park.z, spot.park.x, spot.park.z) > 20 and math.abs(dock.edge.z - spot.pile.z) > 14)
	end
	check("the docks' bays apart", dist(hub.docks[1].park.x, hub.docks[1].park.z, hub.docks[2].park.x, hub.docks[2].park.z) >= 14)
	check("two pallet-jack spots on the dock floor", #hub.jacks == 2 and inside(hub.jacks[1].x, hub.jacks[1].z, hub.platform, 1) and inside(hub.jacks[2].x, hub.jacks[2].z, hub.platform, 1))
	check("the lost package is off the docks", (function()
		for _, secret in Map.Secrets do
			if secret.place == "warehouse" then
				if inside(secret.x, secret.z, hub.platform, -4) then
					return false
				end
				for _, dock in hub.docks do
					if dist(secret.x, secret.z, dock.park.x, dock.park.z) < 14 then
						return false
					end
				end
			end
		end
		return true
	end)())
end
for id, dock in Map.ReceivingDocks do
	local spot = Map.CargoSpots[id]
	check(`receiving dock {id}: by its place's cargo spot`, spot ~= nil and dist(dock.receiver.x, dock.receiver.z, spot.pile.x, spot.pile.z) <= 30)
	check(`receiving dock {id}: room for 3 pallets`, #dock.spots >= 3 and (function()
		for a = 1, #dock.spots do
			for b = a + 1, #dock.spots do
				if dist(dock.spots[a].x, dock.spots[a].z, dock.spots[b].x, dock.spots[b].z) < 4.4 then
					return false
				end
			end
		end
		return true
	end)())
	local yard = Map.inYard(dock.receiver.x, dock.receiver.z)
	local d, bi, bj = Map.blockAt(dock.receiver.x, dock.receiver.z)
	local own = (yard ~= nil and yard.id == id) or (d ~= nil and Map.special(d.id, bi, bj) == id)
	check(`receiving dock {id}: on its own block or yard`, own)
	check(`receiving dock {id}: its jack nearby`, dist(dock.jack.x, dock.jack.z, dock.receiver.x, dock.receiver.z) <= 25)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
