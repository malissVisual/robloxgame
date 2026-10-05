--!strict
-- The city's crosswalks and traffic lights (Zombie Delivery 3.9), as plain numbers: where server/World.luau paints
-- the zebra stripes and stands the light poles, where the pedestrians cross (server/Traffic.luau) and what colour a
-- light shows at a moment. Pure Luau (no Roblox types), so tests/traffic_test.luau runs it outside Roblox.
--
-- Crosswalks. People cross a street only between two blocks of the same district, from a corner of their sidewalk
-- ring (shared/TrafficLanes.luau, SidewalkInset inside the block) straight over to the facing corner. That line runs
-- Distance studs from the middle of the junction next to it, just outside the junction box: a crosswalk Width
-- studs wide is painted there, across the whole road. None on a cargo spot (Map.CargoSpots).
--
-- Traffic lights. At every four-way junction inside a district (the edge ones, where the bridges, highways and
-- country roads come in, keep the give-way): one fixed cycle for every junction, shifted by a per-junction offset
-- (not all switch at once). Axis 1 is the traffic along X, axis 2 along Z:
--   axis 1 green (LightGreen), amber (LightAmber), all red (LightAllRed), axis 2 green, amber, all red, again.
-- The time is workspace:GetServerTimeNow(), so every client draws the colours itself (client/TrafficAnimator.luau)
-- and the server only uses the same function for the cars; nothing is sent over the network.
-- People walk over a street while its traffic is red (the cross traffic's green), when enough of it is left.

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local TrafficLanes = require(script.Parent.TrafficLanes)

local Crossings = {}

export type Junction = {
	x: number,
	z: number,
	offset: number, -- seconds added to the time (0 .. cycle)
	district: string,
}

export type Crosswalk = {
	x: number, -- the middle, on the road's centre line
	z: number,
	alongX: boolean, -- the road it crosses runs along X (its traffic is axis 1; people walk along Z over it)
	jx: number, -- the junction it lies next to
	jz: number,
	light: number, -- that junction's index in Crossings.junctions() (0: no lights)
}

export type LightState = "green" | "amber" | "red"

-- From the middle of a junction to the middle of its crosswalks (the sidewalk ring's corners line up with it).
Crossings.Distance = Map.RoadWidth / 2 + TrafficLanes.SidewalkInset
Crossings.Width = 6 -- along the road
Crossings.StripeWidth = 2.4 -- across the road
Crossings.Stripes = { -12.5, -7.5, -2.5, 2.5, 7.5, 12.5 } -- the stripes' middles across the road (none on the centre line)
-- A light pole stands on a block corner this far along both roads from the junction's middle (NE and SW corners;
-- the street lamps stand on the SE ones).
Crossings.PoleCorner = Map.RoadWidth / 2 + 1.5
-- The lit lens moves in its housing: red on top, amber in the middle, green below (studs from the middle).
Crossings.LensSlot = { red = 1.15, amber = 0, green = -1.15 } :: { [string]: number }
Crossings.Tag = "TrafficLight" -- CollectionService tag of the lenses (server/World.luau, client/TrafficAnimator.luau)
Crossings.LensColor = { red = { 255, 46, 36 }, amber = { 255, 176, 40 }, green = { 80, 255, 130 } } :: { [string]: { number } }

local function key(x: number, z: number): string
	return `{math.floor(x + 0.5)},{math.floor(z + 0.5)}`
end

-- ── The light cycle ────────────────────────────────────────────────────────

-- Seconds of one whole cycle.
function Crossings.cycle(): number
	local t = Config.Traffic
	return 2 * (t.LightGreen + t.LightAmber + t.LightAllRed)
end

-- What the light shows to traffic along an axis (1: along X, 2: along Z) at `time` (+ the junction's offset), and
-- how many seconds that lasts still.
function Crossings.state(time: number, offset: number, axis: number): (LightState, number)
	local t = Config.Traffic
	local green, amber = t.LightGreen, t.LightAmber
	local cycle = Crossings.cycle()
	local u = (time + offset) % cycle
	if axis == 2 then
		u = (u - cycle / 2) % cycle
	end
	if u < green then
		return "green", green - u
	elseif u < green + amber then
		return "amber", green + amber - u
	end
	return "red", cycle - u
end

-- How long the traffic along an axis stays stopped still (0 when it is not red).
function Crossings.redFor(time: number, offset: number, axis: number): number
	local state, left = Crossings.state(time, offset, axis)
	return if state == "red" then left else 0
end

-- May somebody step onto the crosswalk now, to be over before its traffic gets green?
function Crossings.walk(time: number, offset: number, alongX: boolean): boolean
	return Crossings.redFor(time, offset, if alongX then 1 else 2) >= Config.Traffic.CrossTime
end

-- ── Where ──────────────────────────────────────────────────────────────────

local junctionList: { Junction }? = nil
local junctionIndex: { [string]: number } = {}
local crosswalkList: { Crosswalk }? = nil
local crosswalkIndex: { [string]: Crosswalk } = {}

-- The junctions with traffic lights (built on the first call).
function Crossings.junctions(): { Junction }
	local cached = junctionList
	if cached then
		return cached
	end
	local list: { Junction } = {}
	local cycle = Crossings.cycle()
	for _, d in Map.Districts do
		-- The roads between the blocks (not the district's outer ring): road k runs between block k and k + 1.
		for kx = d.i0, d.i1 - 1 do
			for kz = d.j0, d.j1 - 1 do
				local x, z = d.ox + (kx + 0.5) * Map.Cell, d.oz + (kz + 0.5) * Map.Cell
				local shift = (kx * 3 + kz * 5) % 8
				table.insert(list, { x = x, z = z, offset = shift * cycle / 8, district = d.id })
				junctionIndex[key(x, z)] = #list
			end
		end
	end
	junctionList = list
	return list
end

-- The traffic-light junction at this point (its index), if one is there.
function Crossings.junctionAt(x: number, z: number): number?
	Crossings.junctions()
	return junctionIndex[key(x, z)]
end

local function onCargoSpot(c: Crosswalk): boolean
	-- the crosswalk's box (across the road × along it), 4 studs around it
	local halfAcross = Map.RoadWidth / 2 + 4
	local halfAlong = Crossings.Width / 2 + 4
	local function inside(px: number, pz: number): boolean
		local dx, dz = math.abs(px - c.x), math.abs(pz - c.z)
		if c.alongX then
			return dx <= halfAlong and dz <= halfAcross
		end
		return dx <= halfAcross and dz <= halfAlong
	end
	for _, spot in Map.CargoSpots do
		if inside(spot.park.x, spot.park.z) or inside(spot.pile.x, spot.pile.z) then
			return true
		end
	end
	return false
end

-- Every crosswalk (built on the first call).
function Crossings.crosswalks(): { Crosswalk }
	local cached = crosswalkList
	if cached then
		return cached
	end
	Crossings.junctions()
	local list: { Crosswalk } = {}
	local cell = Map.Cell
	local reach = Map.BlockSize / 2 - TrafficLanes.SidewalkInset -- from a block's middle to its ring's corners
	local function add(x: number, z: number, alongX: boolean, jx: number, jz: number)
		local c: Crosswalk = { x = x, z = z, alongX = alongX, jx = jx, jz = jz, light = junctionIndex[key(jx, jz)] or 0 }
		if not onCargoSpot(c) then
			table.insert(list, c)
			crosswalkIndex[key(x, z)] = c
		end
	end
	for _, d in Map.Districts do
		-- Over the roads along Z between block (i, j) and (i + 1, j): at both ends of the block.
		for i = d.i0, d.i1 - 1 do
			for j = d.j0, d.j1 do
				local x, cz = d.ox + (i + 0.5) * cell, d.oz + j * cell
				add(x, cz - reach, false, x, cz - cell / 2)
				add(x, cz + reach, false, x, cz + cell / 2)
			end
		end
		-- Over the roads along X between block (i, j) and (i, j + 1).
		for j = d.j0, d.j1 - 1 do
			for i = d.i0, d.i1 do
				local cx, z = d.ox + i * cell, d.oz + (j + 0.5) * cell
				add(cx - reach, z, true, cx - cell / 2, z)
				add(cx + reach, z, true, cx + cell / 2, z)
			end
		end
	end
	crosswalkList = list
	return list
end

-- The crosswalk whose middle is at this point (the middle of a crossing from corner to corner), if there is one.
function Crossings.at(x: number, z: number): Crosswalk?
	Crossings.crosswalks()
	return crosswalkIndex[key(x, z)]
end

-- The traffic lane graph's nodes that have traffic lights: node → junction index.
function Crossings.nodeLights(g: TrafficLanes.Graph): { [number]: number }
	local map: { [number]: number } = {}
	for n = 1, #g.x do
		local index = Crossings.junctionAt(g.x[n], g.z[n])
		if index and #g.out[n] == 4 then
			map[n] = index
		end
	end
	return map
end

-- The light axis of a directed lane edge (1: along X, 2: along Z).
function Crossings.axisOf(dx: number, dz: number): number
	return if math.abs(dx) >= math.abs(dz) then 1 else 2
end

return Crossings
