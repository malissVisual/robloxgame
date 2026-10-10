--!strict
-- 5.0: how a player gets cargo around — on foot, by bike (5.1) or by car — and how much they can take. Pure: the server
-- (server/Transport.luau Transport.of) and the client fill in a `Kit` (the personal gear owned, Config.Kit) and the
-- vehicle's capacity; everything that used to read the car's capacity (the board, Jobs' room checks, Cargo's hands)
-- asks here instead, so a player without a car can work.
--
-- On foot your hands hold Config.Cargo.HandsMax light pieces and your bag (the active one, below) its `extra`. 6.6, one
-- carrying item: no backpacks any more (Config.RetiredKit: a save that owned one is paid back once, packRefund). The
-- pieces over the hands ride in the bag (server/Cargo.luau's pack). A piece's `speed` multiplies the walk and the
-- sprint (the character attribute KitSpeed, client/CameraRig.luau). (6.7: the Thermal Jacket and its `warm` are gone;
-- 6.12.2: the Running Shoes and their +10% too, Config.RetiredKit: only the Heavy Armour's slow-down is left.)
--
--   Transport.findKit(id)      the Config.Kit entry, or nil
--   Transport.handsRoom(kit, bag)  light pieces you carry on foot: HandsMax + the active bag's `extra` (6.4: ONE bag,
--                              the active one, never the sum of the bags you own; 6.6: room = hands + bag)
--   Transport.packRoom(kit, bag)  of those, the ones over the hands: the bag's (6.6: bagRoom)
--   Transport.packRefund(savedKit, flag)  6.6: the money a save's retired backpacks (Config.RetiredKit) are worth, and
--                              their names (a save's kit table; anything else: 0, none); 6.7: `flag` picks the retired
--                              pieces of one save mark ("noPacks" the default, "noJacket", 6.12.2: "noShoes")
--   Transport.retiredRefunds(saved)  6.7: a save's refunds by flag ({ noPacks = n, noJacket = n, noShoes = n }: once each)
--   Transport.tipShare(kit)    6.7: the tip share of the kit (the Courier Vest's Config.Kit tips; 0 = none)
--   Transport.kitShop(def)     6.7: the Map.Shops id that sells a piece (its `shop`, else "bags" / "supplies")
--
-- 6.4, the bags (Config.Kit pieces with `extra`: the plastic bag, the tote, the thermal, the padded messenger, the
-- duffel). `bag` everywhere is the player's choice (profile.activeBag; the client gets the server's answer as the
-- state's `bag`): nil, or one not owned, means the best one owned. The server decides (server/Transport.luau bagOf).
--   Transport.isBag(def)       is this Config.Kit piece a bag (it has `extra`)?
--   Transport.bestBag(kit)     the bag owned with the most room (a tie: the later one in Config.Kit), or nil
--   Transport.activeBag(kit, bag)  the bag in your hand: `bag` when it is a bag you own, else bestBag
--   Transport.bagRoom(kit, bag)    its room (0 without a bag): the one number Cargo, Jobs, the hotbar and the shop use
--   Transport.bagWarm(kit, bag)    food in it cools × this (the thermal bag; 1 = none)
--   Transport.bagPadded(kit, bag)  fragile pieces in it are safe (the padded messenger)?
--   Transport.bagBreath(kit, bag)  the sprint drains the breath × this while it is your hand (the duffel; 1 = none)
-- (Every bag's point: you sprint with your deliveries. Pieces in a bag are never in your hands.)
-- 6.23, bags for each game (Config.BagShop): the bags are bought for one game and kept in the server's profile.bags
-- (never saved), not in the saved kit. The functions above take any table whose bag ids are the bags you have: the
-- server passes profile.bags, the client the state's kit (the server's withBags).
--   Transport.withBags(kit, bags)   the kit as it is this game: kit's pieces that are no bags + the bags of `bags`
--   Transport.startBags(tutorialDone)  the bags a game starts with: Config.BagShop.Free while the tutorial is ahead
--   Transport.bagRefund(saved)      an old save's payback for the bags it owned for good (Config.BagShop.Refund):
--                                   money and names; only a real save without Config.BagShop.Flag (else 0)
--   Transport.perGame(def)          is this piece bought for each game (a bag)?
--   Transport.mixWarm(share, bagWarm)  the drain multiplier of an order whose `share` of pieces with you is in a
--                              warm bag: 1 − share × (1 − bagWarm)
--   Transport.speedMult(kit)   the walk / sprint multiplier (the best speed-up × the slowest piece; 1 = none)
--   Transport.foot(kit)        Info on foot
--   Transport.car(room)        Info in a car that holds `room` pieces
--
-- 5.1, the bike (Config.Cars with bike = true, sold at Dead End Motors' BIKES counter): light pieces only, the bike's own room and its
-- bike gear's (Economy.capacity) plus your bag (packRoom: the hands hold nothing while you ride, the pieces ride in
-- your bag and the bike's own bag, 6.6); the kit's walk speed does not count on a bike.
--   Transport.isBike(carId)    is this Config.Cars id a bike (CarDef.bike)?
--   Transport.bikeRoom(carId, carGear)  what a bike holds with its installed bike gear (profile.carGear): 6.6, the
--                              bike's own bag (its rack, basket or box), your bag not counted
--   Transport.bike(room, kit, bag)  Info on a bike that holds `room` pieces (bikeRoom) with this kit
--
-- Pure Luau (tests/transport_test.luau).

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Transport = {}

export type Mode = "foot" | "bike" | "car"
export type Kit = { [string]: boolean } -- Config.Kit ids owned (personal gear: bags, shoes, vests …)
export type Info = {
	mode: Mode,
	room: number, -- pieces you can take on one order (hands + bag on foot; a bike's bag + yours; a car's room)
	lightOnly: boolean, -- only Config.Cargo.LightLooks (on foot, on a bike)
	speedMult: number, -- walk / ride speed multiplier from the kit (1 = none)
}

function Transport.findKit(id: string): Config.KitDef?
	for _, def in Config.Kit do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- 6.4: a bag is a Config.Kit piece with `extra` (its room in the hand).
function Transport.isBag(def: Config.KitDef?): boolean
	return def ~= nil and def.extra ~= nil
end

-- 6.4: the bag you own with the most room; a tie goes to the later one in Config.Kit (the pricier: the padded messenger
-- over the thermal bag). Nil without a bag.
function Transport.bestBag(kit: Kit): Config.KitDef?
	local best: Config.KitDef? = nil
	for _, def in Config.Kit do
		if kit[def.id] == true and def.extra and (best == nil or def.extra >= (best.extra or 0)) then
			best = def
		end
	end
	return best
end

-- 6.4: the bag in your hand: your choice when it is a bag you own, else the best one (nil without a bag).
function Transport.activeBag(kit: Kit, bag: string?): Config.KitDef?
	if bag ~= nil and kit[bag] == true then
		local def = Transport.findKit(bag)
		if def and def.extra then
			return def
		end
	end
	return Transport.bestBag(kit)
end

-- 6.4: the active bag's room (0 without one). Never the sum of the bags you own.
function Transport.bagRoom(kit: Kit, bag: string?): number
	local def = Transport.activeBag(kit, bag)
	return if def and def.extra then math.max(0, math.floor(def.extra)) else 0
end

-- 6.4: the active bag's perks (only while it is your hand: the callers check that).
function Transport.bagWarm(kit: Kit, bag: string?): number
	local def = Transport.activeBag(kit, bag)
	return if def and def.bagWarm then math.clamp(def.bagWarm, 0, 1) else 1
end

function Transport.bagPadded(kit: Kit, bag: string?): boolean
	local def = Transport.activeBag(kit, bag)
	return def ~= nil and def.padded == true
end

function Transport.bagBreath(kit: Kit, bag: string?): number
	local def = Transport.activeBag(kit, bag)
	return if def and def.bagBreath then math.clamp(def.bagBreath, 1, 3) else 1
end

-- 6.4: an order's food drain multiplier when `share` (0 … 1) of its pieces with you rides in a bag that cools × bagWarm.
function Transport.mixWarm(share: number, bagWarm: number): number
	local s = math.clamp(if share == share then share else 0, 0, 1)
	return 1 - s * (1 - math.clamp(bagWarm, 0, 1))
end

-- How many light pieces you carry on foot: your hands (Config.Cargo.HandsMax) + the bag's `extra`. 6.4: the active
-- bag's only (`bag`: the choice, nil = the best owned), never every bag's. 6.6: no backpack: room = hands + bag.
function Transport.handsRoom(kit: Kit, bag: string?): number
	return Config.Cargo.HandsMax + Transport.bagRoom(kit, bag)
end

-- The pieces of handsRoom that ride over the hands: 6.6, the bag's.
function Transport.packRoom(kit: Kit, bag: string?): number
	return Transport.bagRoom(kit, bag)
end

-- 6.6: what a save's retired backpacks (Config.RetiredKit, owned in its kit table) are worth, and their names in
-- Config.RetiredKit's order. Anything that is not a table: 0 and none. 6.7: only the retired pieces of one save flag
-- (`flag`: "noPacks", the default, for the backpacks; "noJacket" for the Thermal Jacket), each paid back once by it.
function Transport.packRefund(savedKit: any, flag: string?): (number, { string })
	local money = 0
	local names: { string } = {}
	if type(savedKit) ~= "table" then
		return money, names
	end
	local mark = flag or "noPacks"
	for _, def in Config.RetiredKit do
		if def.flag == mark and savedKit[def.id] == true then
			money += math.max(0, math.floor(def.price))
			table.insert(names, def.name)
		end
	end
	return money, names
end

-- The walk / sprint multiplier from the kit (6.12.2: no Running Shoes any more). 6.0: a piece below 1 (the Heavy
-- Armour) slows you: the best speed-up times the slowest slow-down.
function Transport.speedMult(kit: Kit): number
	local mult, slow = 1, 1
	for _, def in Config.Kit do
		if kit[def.id] == true and def.speed then
			mult = math.max(mult, def.speed)
			slow = math.min(slow, def.speed)
		end
	end
	return mult * slow
end

-- 6.7: what a save is paid back for its retired kit, by save flag (Config.RetiredKit flag: { noPacks = 550, noJacket =
-- 300 }): only a real save (its money is set: not a lock-only record of a new player) that has no such flag yet, only
-- the flags with money in them. server/PlayerData.luau adds it once (every save is written with the flags after).
function Transport.retiredRefunds(saved: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(saved) ~= "table" or saved.money == nil then
		return out
	end
	for _, def in Config.RetiredKit do
		local flag = def.flag
		if saved[flag] ~= true and out[flag] == nil then
			local money = Transport.packRefund(saved.kit, flag)
			if money > 0 then
				out[flag] = money
			end
		end
	end
	return out
end

-- 6.7: the share of an order's pay your kit adds as the customer's tip (Config.Kit tips: the Courier Vest's 0.05; the
-- best piece owned counts; 0 without one). (The Thermal Jacket's `warm` and Transport.warm are gone with it.)
function Transport.tipShare(kit: Kit): number
	local share = 0
	for _, def in Config.Kit do
		if kit[def.id] == true and def.tips then
			share = math.max(share, math.clamp(def.tips, 0, 1))
		end
	end
	return share
end

-- 6.23: the kit as it is this game: every piece of `kit` that is no bag (a bag there is ignored: bags are never kept
-- for good) and every bag of `bags` (the ones bought this game). A new table.
function Transport.withBags(kit: Kit, bags: Kit?): Kit
	local out: Kit = {}
	for _, def in Config.Kit do
		local from = if Transport.isBag(def) then bags else kit
		if from and from[def.id] == true then
			out[def.id] = true
		end
	end
	return out
end

-- 6.23: is a piece bought for each game (a bag)?
function Transport.perGame(def: Config.KitDef?): boolean
	return Transport.isBag(def)
end

-- 6.23: the bags a game starts with: the free one (Config.BagShop.Free) while the tutorial is ahead, else none.
function Transport.startBags(tutorialDone: boolean): Kit
	local out: Kit = {}
	local free = Config.BagShop.Free
	if not tutorialDone and free and Transport.isBag(Transport.findKit(free)) then
		out[free] = true
	end
	return out
end

-- 6.23: what an old save is paid back for the bags it owned for good (its kit's bags, each at Config.BagShop.Refund:
-- the price it was sold at), and their names in Config.Kit's order. Only a real save (its money is set) without the
-- Config.BagShop.Flag mark; anything else: 0 and none. (The plastic bag was free: 0.)
-- 6.23 review: was this bag a level reward the save already had (Config.Levels.Rewards `kit`)? Then it was free, or its
-- price was paid out instead: nothing to pay back. A save without levelRewards (before 4.6) counts as rewarded.
local function rewarded(saved: any, id: string): boolean
	for level, reward in Config.Levels.Rewards do
		if type(reward) == "table" and reward.kit == id then
			local given = saved.levelRewards
			if type(given) ~= "table" or given[tostring(level)] == true then
				return true
			end
		end
	end
	return false
end

function Transport.bagRefund(saved: any): (number, { string })
	local names: { string } = {}
	if type(saved) ~= "table" or saved.money == nil or saved[Config.BagShop.Flag] == true or type(saved.kit) ~= "table" then
		return 0, names
	end
	local money = 0
	for _, def in Config.Kit do
		if Transport.isBag(def) and saved.kit[def.id] == true and not rewarded(saved, def.id) then
			local paid = math.max(0, math.floor(Config.BagShop.Refund[def.id] or 0))
			money += paid
			if paid > 0 then
				table.insert(names, def.name)
			end
		end
	end
	return money, names
end

-- 6.7: the shop that sells a piece of kit (a Map.Shops id): its own `shop` (the bat: "guns"), else a bag at ZDC Bags
-- ("bags"), the rest at Last Stop Supplies ("supplies").
function Transport.kitShop(def: Config.KitDef): string
	return def.shop or (if Transport.isBag(def) then "bags" else "supplies")
end

-- On foot with this kit (6.4: and this bag choice).
function Transport.foot(kit: Kit, bag: string?): Info
	return { mode = "foot", room = Transport.handsRoom(kit, bag), lightOnly = true, speedMult = Transport.speedMult(kit) }
end

-- In a car that holds `room` pieces (Economy.capacity with its stage and gear).
function Transport.car(room: number): Info
	return { mode = "car", room = math.max(0, math.floor(room)), lightOnly = false, speedMult = 1 }
end

-- 5.1: is this car id a bike (Config.Cars bike = true)?
function Transport.isBike(carId: string?): boolean
	if carId == nil then
		return false
	end
	local def = Economy.findCar(carId)
	return def ~= nil and def.bike == true
end

-- 5.1: what a bike holds itself: its capacity and its installed bike gear's room (carGear: profile.carGear); 0 for
-- anything that is not a bike.
function Transport.bikeRoom(carId: string?, carGear: Economy.CarGear?): number
	if carId == nil or not Transport.isBike(carId) then
		return 0
	end
	return Economy.capacity(carId, nil, Economy.installedGear(carGear, carId), nil)
end

-- 5.1: on a bike that holds `room` pieces (Transport.bikeRoom), with this kit: + the pack, light pieces only.
function Transport.bike(room: number, kit: Kit, bag: string?): Info
	return { mode = "bike", room = math.max(0, math.floor(room)) + Transport.packRoom(kit, bag), lightOnly = true, speedMult = 1 }
end

return Transport
