--!strict
-- 5.0: how a player gets cargo around — on foot, by bike (5.1) or by car — and how much they can take. Pure: the server
-- (server/Transport.luau Transport.of) and the client fill in a `Kit` (the personal gear owned, Config.Kit) and the
-- vehicle's capacity; everything that used to read the car's capacity (the board, Jobs' room checks, Cargo's hands)
-- asks here instead, so a player without a car can work.
--
-- On foot your hands hold Config.Cargo.HandsMax light pieces; a backpack (Config.Kit `room`) is the room of the hands
-- and the back together: the best one you own counts (the Big Backpack's 4 beats the Courier Backpack's 3). The
-- pieces over the hands ride in the pack (server/Cargo.luau: packRoom). The shoes' `speed` multiplies the walk and the
-- sprint (the character attribute KitSpeed, client/CameraRig.luau), the jacket's `warm` the food's freshness drain.
--
--   Transport.findKit(id)      the Config.Kit entry, or nil
--   Transport.handsRoom(kit)   light pieces you carry on foot: max(HandsMax, the best backpack's room) + the kit's
--                              `extra` (6.0: the plastic bag, Config.Kit "bag": it adds up with a backpack)
--   Transport.packRoom(kit)    of those, the ones in the pack (handsRoom − HandsMax)
--   Transport.speedMult(kit)   the walk / sprint multiplier (the best shoes; 1 = none)
--   Transport.warm(kit)        the food's freshness drain multiplier while you carry it (the best jacket; 1 = none)
--   Transport.foot(kit)        Info on foot
--   Transport.car(room)        Info in a car that holds `room` pieces
--
-- 5.1, the bike (Config.Cars with bike = true, sold at Spoke & Chain): light pieces only, the bike's own room and its
-- bike gear's (Economy.capacity) plus your pack (packRoom: the hands hold nothing while you ride, the pieces ride in
-- the pack and the bike's slots); the kit's walk speed does not count on a bike.
--   Transport.isBike(carId)    is this Config.Cars id a bike (CarDef.bike)?
--   Transport.bikeRoom(carId, carGear)  what a bike holds with its installed bike gear (profile.carGear), no pack
--   Transport.bike(room, kit)  Info on a bike that holds `room` pieces (bikeRoom) with this kit
--
-- Pure Luau (tests/transport_test.luau).

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Transport = {}

export type Mode = "foot" | "bike" | "car"
export type Kit = { [string]: boolean } -- Config.Kit ids owned (personal gear: backpacks, shoes …)
export type Info = {
	mode: Mode,
	room: number, -- pieces you can take on one order (hands + backpack on foot; the vehicle's room otherwise)
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

-- How many light pieces you carry in your hands and on your back (Config.Cargo.HandsMax + the best backpack's room).
-- 6.0: + every owned piece's `extra` (the plastic bag's 2), on top of the best backpack.
function Transport.handsRoom(kit: Kit): number
	local room = Config.Cargo.HandsMax
	local extra = 0
	for _, def in Config.Kit do
		if kit[def.id] == true and def.room then
			room = math.max(room, math.floor(def.room))
		end
		if kit[def.id] == true and def.extra then
			extra += math.max(0, math.floor(def.extra))
		end
	end
	return room + extra
end

-- 6.0 review: the hands and the best backpack only (no bag's extra): what a backpack you might buy is compared with.
function Transport.backpackRoom(kit: Kit): number
	local room = Config.Cargo.HandsMax
	for _, def in Config.Kit do
		if kit[def.id] == true and def.room then
			room = math.max(room, math.floor(def.room))
		end
	end
	return room
end

-- The pieces of handsRoom that ride in the pack (not in the hands).
function Transport.packRoom(kit: Kit): number
	return math.max(0, Transport.handsRoom(kit) - Config.Cargo.HandsMax)
end

-- The walk / sprint multiplier from the kit (running shoes …). 6.0: a piece below 1 (the Heavy Armour) slows you: the
-- best speed-up times the slowest slow-down.
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

-- The food's freshness drain while you carry it (a thermal jacket < 1).
function Transport.warm(kit: Kit): number
	local mult = 1
	for _, def in Config.Kit do
		if kit[def.id] == true and def.warm then
			mult = math.min(mult, math.max(0, def.warm))
		end
	end
	return mult
end

-- On foot with this kit.
function Transport.foot(kit: Kit): Info
	return { mode = "foot", room = Transport.handsRoom(kit), lightOnly = true, speedMult = Transport.speedMult(kit) }
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
function Transport.bike(room: number, kit: Kit): Info
	return { mode = "bike", room = math.max(0, math.floor(room)) + Transport.packRoom(kit), lightOnly = true, speedMult = 1 }
end

return Transport
