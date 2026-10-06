--!strict
-- 5.3, the bag: what fits in a backpack and where every piece you carry is (your inventory). Pure Luau, shared by
-- server/Cargo.luau (packFits, the rack), server/Jobs.luau (how many pieces an order may have, room checks),
-- client/BagUi.luau and the HUD's chip on the contract ticket; tested in tests/bag_test.luau.
--
-- A light piece (Config.Cargo.LightLooks) either fits a backpack (Config.Cargo.PackLooks: mail, newspapers,
-- documents, medicine, pizza, burger bags, noodle boxes, pastries, bread, small parcels) or it does not (a bouquet, a
-- cake, an electronics box, groceries, ice cream): then it rides in your hands, or on a bike's rack, basket or box (the
-- e-scooter's rack takes one), never in the backpack.
--
--   Bag.fits(look)                       does a piece of this look go into a backpack?
--   Bag.room(look, mode, room, rack)     how many pieces of this look one order may have: `room` (what you carry:
--                                        hands + backpack on foot, the bike's room + the backpack by bike, the car's)
--                                        for a piece that fits the backpack; else the hands on foot, the bike's own
--                                        room (`rack`) by bike; a car takes its whole room
--   Bag.rack(mode, riding, bikeRoom, packRoom)   5.3 review: the bike's own room (rack, basket, box) a run has: a
--                                        bike run's, or a foot run's while you ride (`riding`); 0 walking or no bike
--   Bag.makeRoom(held, max, free)        5.3 review: how many of the looks in your hands go into the backpack so the
--                                        hands (`max` with the next piece) take a piece that does not fit it (0: none)
--   Bag.plural(name)                     "pizza stack" → "pizza stacks" (the words of Config.Jobs.Businesses and
--                                        Config.Cargo.Kinds, else an "s")
--   Bag.line(carried)                    the HUD's chip: "🎒 2 newspapers · 1 pizza stack" (nil when you carry nothing)
--   Bag.groups(carried, mode)            the pieces by where they are (hands, backpack, rack, vehicle), for BagUi
--
-- `carried` is the job payload's (server/Jobs.luau carriedInfo): { order, look, name, where, dest, place } a piece,
-- where = "hands" | "pack" | "rack" | "vehicle".

local Config = require(script.Parent.Config)

local Bag = {}

export type Piece = { order: number?, look: string?, name: string?, where: string?, dest: string?, place: string? }
export type Group = { where: string, icon: string, title: string, pieces: { Piece } }

function Bag.fits(look: string?): boolean
	return look ~= nil and Config.Cargo.PackLooks[look] == true
end

function Bag.room(look: string?, mode: string, room: number, rack: number?): number
	local all = math.max(0, math.floor(room))
	if mode == "car" or Bag.fits(look) then
		return all
	end
	if mode == "bike" then
		return math.min(all, math.max(0, math.floor(rack or 0)))
	end
	return math.min(all, Config.Cargo.HandsMax)
end

function Bag.rack(mode: string, riding: boolean, bikeRoom: number?, packRoom: number): number
	if bikeRoom == nil or not (mode == "bike" or (mode == "foot" and riding)) then
		return 0
	end
	return math.max(0, math.floor(bikeRoom - packRoom))
end

function Bag.makeRoom(held: { string? }, max: number, free: number): number
	local need = #held - max + 1
	if need <= 0 then
		return 0
	end
	local fits = 0
	for _, look in held do
		if Bag.fits(look) then
			fits += 1
		end
	end
	if fits < need or free < need then
		return 0
	end
	return need
end

local plurals: { [string]: string }? = nil

function Bag.plural(name: string): string
	local known: { [string]: string } = plurals or {}
	if not plurals then
		for _, business in Config.Jobs.Businesses do
			known[business.piece] = business.plural
		end
		for _, kind in Config.Cargo.Kinds do
			known[kind.piece] = kind.plural
		end
		plurals = known
	end
	local found = known[name]
	if found then
		return found
	end
	if string.sub(name, -1) == "s" or string.sub(name, -1) == "x" or string.sub(name, -2) == "sh" or string.sub(name, -2) == "ch" then
		return name .. "es"
	end
	return name .. "s"
end

-- "2 newspapers · 1 pizza stack" from the pieces' names, in the order they first come; three kinds at most, then
-- "+N more".
function Bag.line(carried: { Piece }?): string?
	if type(carried) ~= "table" or #carried == 0 then
		return nil
	end
	local names: { string } = {}
	local counts: { [string]: number } = {}
	for _, piece in carried do
		local name = if type(piece) == "table" and type(piece.name) == "string" then piece.name else "piece"
		if not counts[name] then
			table.insert(names, name)
		end
		counts[name] = (counts[name] or 0) + 1
	end
	local parts: { string } = {}
	local more = 0
	for index, name in names do
		local count = counts[name]
		if index <= 3 then
			table.insert(parts, `{count} {if count == 1 then name else Bag.plural(name)}`)
		else
			more += count
		end
	end
	if more > 0 then
		table.insert(parts, `+{more} more`)
	end
	return "🎒 " .. table.concat(parts, " · ")
end

local ORDER = { "hands", "pack", "rack", "vehicle" }

-- The pieces by where they are, in the order hands, backpack, rack, vehicle; only the places that hold something.
-- `mode` names the rack (an e-scooter's or a bike's: "bike"; nil: "Rack").
function Bag.groups(carried: { Piece }?, mode: string?): { Group }
	local by: { [string]: { Piece } } = {}
	if type(carried) == "table" then
		for _, piece in carried do
			if type(piece) == "table" then
				local where = if type(piece.where) == "string" and table.find(ORDER, piece.where) then piece.where else "pack"
				local list = by[where] or {}
				by[where] = list
				table.insert(list, piece)
			end
		end
	end
	local titles: { [string]: { string } } = {
		hands = { "✋", "In your hands" },
		pack = { "🎒", "In your backpack" },
		rack = { "🚲", if mode == "bike" then "On your bike" else "On the rack" },
		vehicle = { "🚚", "In your vehicle" },
	}
	local out: { Group } = {}
	for _, where in ORDER do
		local list = by[where]
		if list and #list > 0 then
			table.insert(out, { where = where, icon = titles[where][1], title = titles[where][2], pieces = list })
		end
	end
	return out
end

return Bag
