--!strict
-- 5.6, the alley shortcuts (Config.Shortcuts), as plain numbers: where a lit path cuts straight through a Downtown
-- block, from one street to the street on the other side. server/Shortcuts.luau builds them (World's build list);
-- tests/shortcuts_test.luau checks them. Pure Luau.
--
-- An alley runs where two neighbouring lots of an ordinary block (Map.lots: the same on every server) are both open,
-- a lawn ("grass") or a parking lot ("parking"): down the middle of a column of lots (a = 0 or 1, both rows: the path
-- runs along Z, from the north street to the south one) or of a row (b = 0 or 1: along X). Never through a tower, a
-- home or a storefront: those lots are not open. The path covers the two lots (from the lots' outer edges,
-- DowntownInset in from each curb); at each end a low fence across it (hop it: Config.Shortcuts.FenceHeight), a lamp on
-- each lot beside the path and a SHORTCUT sign by one mouth, on the sidewalk off the people's walk line.
-- Picked with Map.lcg among every such pair: one alley a block, none in the safe zone, none whose mouth (where it meets
-- the sidewalk, on the curb) is within Config.Shortcuts.Clear of a home's or a storefront's door, pile or park, a
-- cargo spot, an employer's board, a bus stop's kerb, a gas station or a place.
--
--   Shortcuts.alleys()            every alley (cached)
--   Shortcuts.nearMouth(x, z, r)  is an alley's mouth (on the curb) within r of (x, z)?

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local BusLines = require(script.Parent.BusLines)

local Shortcuts = {}

export type Point = { x: number, z: number }
export type Alley = {
	id: number,
	name: string, -- "Shortcut · Oak St → Elm St"
	district: string,
	i: number, -- the block
	j: number,
	alongX: boolean, -- the path runs along X (from the west street to the east one); else along Z
	x0: number, -- the path's ends (the lots' outer edges, DowntownInset in from each curb)
	z0: number,
	x1: number,
	z1: number,
	width: number,
	mouths: { Point }, -- where it meets the sidewalk, on the curb (two)
	fences: { Point }, -- the two fences across it (just inside each lot's outer edge)
	lamps: { Point }, -- a lamp on each lot, beside the path
	sign: Point, -- the SHORTCUT sign, on the sidewalk beside the first mouth
	lots: { Map.Lot }, -- the two open lots
}

local BLOCK = Map.BlockSize
local INSET = Map.DowntownInset

local function open(lot: Map.Lot?): boolean
	return lot ~= nil and (lot.kind == "grass" or lot.kind == "parking")
end

-- Is (x, z) clear of everything an alley's mouth must keep away from?
local function clearAt(x: number, z: number): boolean
	local r = Config.Shortcuts.Clear
	local function near(px: number, pz: number, radius: number): boolean
		return (x - px) ^ 2 + (z - pz) ^ 2 < radius * radius
	end
	if Map.isSafe(x, z) then
		return false
	end
	for _, home in Map.Homes do
		if near(home.door.x, home.door.z, r) or near(home.pile.x, home.pile.z, r) or near(home.park.x, home.park.z, r) then
			return false
		end
	end
	for _, venue in Map.Venues do
		if near(venue.door.x, venue.door.z, r) or near(venue.pile.x, venue.pile.z, r) or near(venue.park.x, venue.park.z, r) then
			return false
		end
	end
	for _, spot in Map.CargoSpots do
		if near(spot.park.x, spot.park.z, r) or near(spot.pile.x, spot.pile.z, r) then
			return false
		end
	end
	for _, spot in Map.EmployerSpots do
		if near(spot.x, spot.z, r) then
			return false
		end
	end
	for _, place in Map.Places do
		if near(place.x, place.z, Map.FreeRadius) then
			return false
		end
	end
	for _, stop in BusLines.allStops() do
		if near(stop.kx, stop.kz, r + 6) then
			return false
		end
	end
	for _, station in Map.GasStations do
		if near(station.x, station.z, 50) then
			return false
		end
	end
	return true
end

local cache: { Alley }? = nil

function Shortcuts.alleys(): { Alley }
	if cache then
		return cache
	end
	local tuning = Config.Shortcuts
	local d = Map.districtById("downtown")
	local rand = Map.lcg(Config.City.Seed + 56)
	type Candidate = { alley: Alley, key: number }
	local candidates: { Candidate } = {}
	for i = d.i0, d.i1 do
		for j = d.j0, d.j1 do
			if Map.special(d.id, i, j) then
				continue
			end
			local lots: { [string]: Map.Lot } = {}
			for _, lot in Map.lotsAt(d.id, i, j) do
				lots[`{lot.a}{lot.b}`] = lot
			end
			local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
			local half = BLOCK / 2
			-- (every block rolls the same dice, whatever it holds)
			local rolls = { rand(), rand(), rand(), rand() }
			for n = 1, 4 do
				-- n 1, 2: the columns a = 0, 1 (the path along Z); n 3, 4: the rows b = 0, 1 (along X)
				local alongX = n > 2
				local k = (n - 1) % 2
				local first = if alongX then lots[`0{k}`] else lots[`{k}0`]
				local second = if alongX then lots[`1{k}`] else lots[`{k}1`]
				if not (open(first) and open(second)) or not first or not second then
					continue
				end
				local across = if alongX then first.z else first.x -- the path's middle line
				local function at(along: number, side: number): Point
					return if alongX then { x = along, z = across + side } else { x = across + side, z = along }
				end
				local mid = if alongX then cx else cz
				local mouths = { at(mid - half, 0), at(mid + half, 0) }
				if not (clearAt(mouths[1].x, mouths[1].z) and clearAt(mouths[2].x, mouths[2].z)) then
					continue
				end
				local x0, z0 = if alongX then mid - half + INSET else across, if alongX then across else mid - half + INSET
				local x1, z1 = if alongX then mid + half - INSET else across, if alongX then across else mid + half - INSET
				local side = tuning.Width / 2 + 1.2
				local alley: Alley = {
					id = 0,
					name = "",
					district = d.id,
					i = i,
					j = j,
					alongX = alongX,
					x0 = x0,
					z0 = z0,
					x1 = x1,
					z1 = z1,
					width = tuning.Width,
					mouths = mouths,
					fences = { at(mid - half + INSET + 0.6, 0), at(mid + half - INSET - 0.6, 0) },
					lamps = { at(mid - BLOCK / 4, side), at(mid + BLOCK / 4, -side) },
					sign = at(mid - half + INSET - 1.4, side + 0.4),
					lots = { first, second },
				}
				table.insert(candidates, { alley = alley, key = rolls[n] })
			end
		end
	end
	table.sort(candidates, function(p: Candidate, q: Candidate): boolean
		return p.key < q.key
	end)
	local list: { Alley } = {}
	local used: { [string]: boolean } = {}
	for _, candidate in candidates do
		local alley = candidate.alley
		local block = `{alley.i},{alley.j}`
		if used[block] or #list >= tuning.Count then
			continue
		end
		used[block] = true
		alley.id = #list + 1
		alley.name = `Shortcut {alley.id}`
		table.insert(list, alley)
	end
	cache = list
	return list
end

-- Is an alley's mouth (on the curb) within r of (x, z)?
function Shortcuts.nearMouth(x: number, z: number, r: number): boolean
	for _, alley in Shortcuts.alleys() do
		for _, mouth in alley.mouths do
			if (x - mouth.x) ^ 2 + (z - mouth.z) ^ 2 < r * r then
				return true
			end
		end
	end
	return false
end

return Shortcuts
