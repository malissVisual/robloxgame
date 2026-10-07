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
--   Bag.places(mode, packRoom, rack, bagRoom)  6.0.1: the room by place for the bottom bar's carried strip: the hands
--                                        (Config.Cargo.HandsMax), the plastic bag, the backpack, the rack (a car run:
--                                        the hands only)
--   Bag.strip(carried, places, focus, max)  6.0.1: the strip's tiles: per place its pieces, then its free room; the
--                                        pieces the server has in the pack fill the bag first; a piece of another
--                                        order than `focus` is `other`; over `max` tiles the free room goes first,
--                                        then the last pieces (returns the tiles, how many went: "+N", and how many of
--                                        those were pieces)
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

local ORDER = { "hands", "bag", "pack", "rack", "vehicle" }

-- The pieces by where they are, in the order hands, (6.1) the bag in your hand, backpack, rack, vehicle; only the
-- places that hold something.
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
		bag = { "🛍", "In the bag in your hand" }, -- 6.1
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

-- 6.0.1, the bottom bar (client/Hotbar.luau): what you carry as small tiles, one a piece and one a free place.
export type Place = { where: string, room: number }
export type Tile = { where: string, piece: Piece?, other: boolean }

local PLACES = { "hands", "bag", "pack", "rack" }

-- The room by place, in the order hands, bag, backpack, rack. `packRoom` is the pieces over the hands (the payload's
-- packRoom / the PackRoom attribute: the backpack, the bag's extra and a bike's rack), `rack` the bike's part of it,
-- `bagRoom` the plastic bag's part (Transport.handsRoom − Transport.backpackRoom). A car run: the hands only.
function Bag.places(mode: string, packRoom: number, rack: number, bagRoom: number): { Place }
	local hands = Config.Cargo.HandsMax
	if mode == "car" then
		return { { where = "hands", room = hands }, { where = "bag", room = 0 }, { where = "pack", room = 0 }, { where = "rack", room = 0 } }
	end
	local onRack = math.max(0, math.floor(rack))
	local packOnly = math.max(0, math.floor(packRoom) - onRack)
	local bag = math.clamp(math.floor(bagRoom), 0, packOnly)
	return {
		{ where = "hands", room = hands },
		{ where = "bag", room = bag },
		{ where = "pack", room = packOnly - bag },
		{ where = "rack", room = onRack },
	}
end

-- The strip's tiles (see the header). The vehicle's pieces are not on it (the vehicle line says them).
function Bag.strip(carried: { Piece }?, places: { Place }, focus: number?, max: number): ({ Tile }, number, number)
	local room: { [string]: number } = {}
	local by: { [string]: { Piece } } = {}
	for _, where in PLACES do
		room[where] = 0
		by[where] = {}
	end
	for _, place in places do
		if room[place.where] then
			room[place.where] = math.max(0, math.floor(place.room))
		end
	end
	if type(carried) == "table" then
		for _, piece in carried do
			if type(piece) ~= "table" or piece.where == "vehicle" then
				continue
			end
			local where = if type(piece.where) == "string" and by[piece.where] then piece.where else "pack"
			if where == "pack" and #by.bag < room.bag then
				where = "bag" -- (the bag fills first: what you pick up drops straight in)
			end
			table.insert(by[where], piece)
		end
	end
	local tiles: { Tile } = {}
	for _, where in PLACES do
		for _, piece in by[where] do
			local other = focus ~= nil and type(piece.order) == "number" and piece.order ~= focus
			table.insert(tiles, { where = where, piece = piece, other = other })
		end
		for _ = #by[where] + 1, room[where] do
			table.insert(tiles, { where = where, piece = nil, other = false })
		end
	end
	local limit = math.max(2, math.floor(max))
	if #tiles <= limit then
		return tiles, 0, 0
	end
	local over = #tiles - (limit - 1) -- (one tile says "+N")
	local gone, pieces = 0, 0
	for index = #tiles, 1, -1 do
		if gone >= over then
			break
		end
		if tiles[index].piece == nil then
			table.remove(tiles, index)
			gone += 1
		end
	end
	while gone < over do
		table.remove(tiles)
		gone += 1
		pieces += 1
	end
	return tiles, gone, pieces
end

return Bag
