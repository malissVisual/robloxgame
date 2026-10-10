--!strict
-- 5.3, the bag: where every piece you carry is (your inventory). Pure Luau, shared by server/Cargo.luau, server/Jobs.luau
-- (the bike's own room on a run), client/BagUi.luau, client/Hotbar.luau's CARRYING pill and the HUD's chip on the
-- contract ticket; tested in tests/bag_test.luau.
--
-- 6.6, one carrying item (the owner: "the backpacks, the bag and the bike work weirdly"): no backpack any more, so no
-- "fits a backpack" either (5.3's Config.Cargo.PackLooks are gone). Three places for a light piece: your hands
-- (Config.Cargo.HandsMax), your bag (the active one, while it is your hand: shared/Transport.luau bagRoom) and, on a
-- run with a bike, the bike's own bag (its rack, basket or box: Info.rack). A heavy piece only ever goes in the hands.
-- A newspaper round's papers ride in its satchel (where = "pack").
--
--   Bag.fitsBag(look)                    6.3: does it go into a bag (yours or the bike's)? Every light look
--                                        (Config.Cargo.LightLooks: a bouquet, a cake, groceries too), never a heavy one
--   Bag.rack(mode, riding, bikeRoom)     the bike's own bag on a run (`bikeRoom`: Transport.bikeRoom, what the bike and
--                                        its bike gear hold): a bike run's, or a foot run's while you ride (`riding`:
--                                        the bike is your vehicle now); 0 walking, a car run or no bike
--   Bag.plural(name)                     "pizza stack" → "pizza stacks" (the words of Config.Jobs.Businesses and
--                                        Config.Cargo.Kinds, else an "s")
--   Bag.line(carried)                    the HUD's chip: "📦 2 newspapers · 1 pizza stack" (nil when you carry nothing)
--   Bag.groups(carried, mode)            the pieces by where they are (hands, bag, the bike, the satchel, vehicle),
--                                        for BagUi
--   Bag.places(mode, packRoom, rack, bagRoom, hands?)  6.0.1: the room by place for the bottom bar: the hands
--                                        (Config.Cargo.HandsMax), the bag (`bagRoom`), the bike's bag (`rack`) and a
--                                        round's satchel (what `packRoom` holds over those; a car run: the hands only)
--   Bag.strip(carried, places, focus, max)  6.0.1: the strip's tiles: per place its pieces, then its free room; a
--                                        piece the server has in the pack without a place yet fills the bag first; a
--                                        piece of another order than `focus` is `other`; over `max` tiles the free
--                                        room goes first, then the last pieces (returns the tiles, how many went:
--                                        "+N", and how many of those were pieces)
--
-- `carried` is the job payload's (server/Jobs.luau carriedInfo): { order, look, name, where, dest, place } a piece,
-- where = "hands" | "bag" | "rack" (6.6: the bike's own bag) | "pack" (a round's satchel) | "vehicle".

local Config = require(script.Parent.Config)

local Bag = {}

export type Piece = { order: number?, look: string?, name: string?, where: string?, dest: string?, place: string? }
export type Group = { where: string, icon: string, title: string, pieces: { Piece } }

-- 6.3 (the owner: "things don't go into the bag"): a bag takes every light piece. 6.6: the bike's bag too.
function Bag.fitsBag(look: string?): boolean
	return look ~= nil and Config.Cargo.LightLooks[look] == true
end

function Bag.rack(mode: string, riding: boolean, bikeRoom: number?): number
	if bikeRoom == nil or not (mode == "bike" or (mode == "foot" and riding)) then
		return 0
	end
	return math.max(0, math.floor(bikeRoom))
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
	return "📦 " .. table.concat(parts, " · ")
end

-- The groups' order and their marks (the hotbar's pill uses the same marks: ✋ 🛍 🚲).
local ORDER = { "hands", "bag", "rack", "pack", "vehicle" }
Bag.Marks = { hands = "✋", bag = "🛍", rack = "🚲", pack = "📰", vehicle = "🚚" } :: { [string]: string }

-- The pieces by where they are, in the order hands, (6.1) the bag, (6.6) the bike's bag, a round's satchel, vehicle;
-- only the places that hold something. An unknown place goes with the satchel's.
function Bag.groups(carried: { Piece }?, _mode: string?): { Group }
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
	local titles: { [string]: string } = {
		hands = "In your hands",
		bag = "In your bag",
		rack = "In your bike's bag", -- 6.6 (its rack, basket or box)
		pack = "In your satchel", -- a newspaper round's papers
		vehicle = "In your vehicle",
	}
	local out: { Group } = {}
	for _, where in ORDER do
		local list = by[where]
		if list and #list > 0 then
			table.insert(out, { where = where, icon = Bag.Marks[where], title = titles[where], pieces = list })
		end
	end
	return out
end

-- 6.0.1, the bottom bar (client/Hotbar.luau): what you carry, a piece and a free place each.
export type Place = { where: string, room: number }
export type Tile = { where: string, piece: Piece?, other: boolean }

local PLACES = { "hands", "bag", "rack", "pack" }

-- The room by place, in the order hands, bag, the bike's bag, the satchel. `packRoom` is the room over the hands (the
-- payload's packRoom / the PackRoom attribute: the bag's, the bike's bag and a round's satchel), `rack` the bike's part
-- of it, `bagRoom` the bag's part. A car run: the hands only. 6.20: `handsRoom` the hands' room (Strong Back's extra,
-- Config.Skills; nil = Config.Cargo.HandsMax).
function Bag.places(mode: string, packRoom: number, rack: number, bagRoom: number, handsRoom: number?): { Place }
	local hands = handsRoom or Config.Cargo.HandsMax
	if mode == "car" then
		return { { where = "hands", room = hands }, { where = "bag", room = 0 }, { where = "rack", room = 0 }, { where = "pack", room = 0 } }
	end
	local total = math.max(0, math.floor(packRoom))
	local onBike = math.clamp(math.floor(rack), 0, total)
	local bag = math.clamp(math.floor(bagRoom), 0, total - onBike)
	return {
		{ where = "hands", room = hands },
		{ where = "bag", room = bag },
		{ where = "rack", room = onBike },
		{ where = "pack", room = total - onBike - bag },
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
