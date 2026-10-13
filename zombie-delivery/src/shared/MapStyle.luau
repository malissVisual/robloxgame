--!strict
-- 7.2, the Alps on the maps: what the minimap and the big map (client/MapView.luau) draw of the valley's alpine look,
-- worked out from Map (the bounds, the water, the snowfield, the villages) and AlpineLayout (the ring's cones, the
-- forests, the meadows, the huts, the West Pass) as plain numbers in world studs. Pure (no Roblox at its top level):
-- MapView turns it into frames once, tools/phone-ui/mapview.luau checks it and its budgets (Config.MapStyle has the
-- numbers and the colours). Everything is read when asked, so a new Map.Bounds, a new lake or new villages (the Alps'
-- step 2) are drawn without a change here.
--
--   MapStyle.extent()              the drawn area: Map.Bounds with Config.MapStyle.Margin round it
--   MapStyle.rgb(name)             a colour of Config.MapStyle.Colors as { r, g, b } (Blocks: by district style)
--   MapStyle.waters(extent)        the river (on through the ring's gorges), the sea, the lakes: rectangles, clipped
--   MapStyle.winter(extent?)       the snowfield (Map.Winter; before the Alps' step 2 north of Map.WinterZ, west of the
--                                  river), on into the ring where it reaches the bounds
--   MapStyle.mountain(extent)      the old mountain with its tunnel (Map.Mountain) while it stands in the drawn area
--   MapStyle.peaks(ring)           the big map's peaks, back to front
--   MapStyle.relief(ring)          the minimap's discs (the cones' grassy feet, rock and snow), back to front
--   MapStyle.forestRuns(forest)    the forest bands (a row's run of forest squares)
--   MapStyle.meadows(forest)       the wildflower meadows; MapStyle.huts(forest) the hay barns and huts
--   MapStyle.passes(ring)          the closed roads out of the valley (the West Pass)
--   MapStyle.villages()            the villages' labels (Map.Villages when Map names them; the Altstadt placeholder)
--   MapStyle.plan(ring, forest)    all of the ring's and the forest's above, for both maps
--   MapStyle.encode(plan) / .decode(text)   a plan packed into a short string and back (nil: not one for these bounds)
--   MapStyle.summary(), .publish(parent)    the server: this place's plan packed, in a StringValue for the clients

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local AlpineLayout = require(script.Parent.AlpineLayout)

local MapStyle = {}

local S = Config.MapStyle

export type Extent = { x0: number, z0: number, x1: number, z1: number }
-- kind: river | sea | lake | ice (a frozen lake); round: the corners' radius in studs (math.huge: fully round)
export type Rect = { kind: string, x0: number, z0: number, x1: number, z1: number, round: number, name: string? }
-- A peak on the big map: the middle of its foot line (x, z), the way its top points from there (ox, oz: up the map),
-- its height (`half`: half its foot, a right-angled peak), its snow cap's height (0: none), its shadow side (sx, sz:
-- the face away from the light, from the west or the north); side: north | south | east | west (the margin it stands
-- in); depth: 0 the front row … 1 the farthest back (its rock fades toward the paper).
export type Peak = {
	x: number,
	z: number,
	ox: number,
	oz: number,
	sx: number,
	sz: number,
	half: number,
	cap: number,
	winter: boolean,
	side: string,
	row: string,
	cone: string,
	depth: number,
}
-- A disc seen from above (kind: foot | rock | snow | winter | mount).
export type Disc = { kind: string, x: number, z: number, r: number }
-- A forest band: a row's run of forest squares from x0 to x1, its middle at z.
export type Run = { x0: number, x1: number, z: number, cells: number, snowy: boolean }
export type Spot = { x: number, z: number }
export type Hut = { x: number, z: number, kind: string }
export type Pass = { id: string, name: string, x: number, z: number, nx: number, nz: number, width: number, from: number, face: number, text: string }
-- placeholder: no village data from Map (the Altstadt over its district's name; district: that district's id)
export type Village = { name: string, x: number, z: number, district: string?, sub: string?, placeholder: boolean }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MapStyle.extent(): Extent
	local B = Map.Bounds
	local m = S.Margin
	return { x0 = B.x0 - m, z0 = B.z0 - m, x1 = B.x1 + m, z1 = B.z1 + m }
end

function MapStyle.rgb(name: string, style: string?): { number }
	local colors = S.Colors
	if name == "Blocks" then
		local blocks = colors.Blocks :: { [string]: { number } }
		return blocks[style or "downtown"] or blocks.downtown
	end
	return colors[name] :: { number }
end

-- A rectangle of Map's (x0, z0, x1, z1), or an ellipse's (x, z, rx, rz), else nil.
local function boxOf(v: any): (number?, number?, number?, number?)
	if type(v) ~= "table" then
		return nil, nil, nil, nil
	end
	if type(v.x0) == "number" and type(v.x1) == "number" and type(v.z0) == "number" and type(v.z1) == "number" then
		return math.min(v.x0, v.x1), math.min(v.z0, v.z1), math.max(v.x0, v.x1), math.max(v.z0, v.z1)
	end
	if type(v.x) == "number" and type(v.z) == "number" and type(v.rx) == "number" and type(v.rz) == "number" then
		return v.x - v.rx, v.z - v.rz, v.x + v.rx, v.z + v.rz
	end
	return nil, nil, nil, nil
end

-- The water on the map: the river (through the gorges to the drawn area's edges: it comes out of the mountains), the
-- sea, the frozen lake, the alpine lake (Map.AlpineLake, an ellipse: fully round) and any Map.Lakes; each clipped to
-- the drawn area, nothing that falls outside it (step 2's stand-ins for the old sea and lake lie far off the valley).
function MapStyle.waters(extent: Extent): { Rect }
	local list: { Rect } = {}
	local function add(kind: string, x0: number, z0: number, x1: number, z1: number, round: number, name: string?)
		x0, z0 = math.max(x0, extent.x0), math.max(z0, extent.z0)
		x1, z1 = math.min(x1, extent.x1), math.min(z1, extent.z1)
		if x1 - x0 >= 1 and z1 - z0 >= 1 then
			table.insert(list, { kind = kind, x0 = x0, z0 = z0, x1 = x1, z1 = z1, round = round, name = name })
		end
	end
	local M = Map :: any
	local river = M.River
	if type(river) == "table" and type(river.x0) == "number" and type(river.x1) == "number" then
		add("river", river.x0, extent.z0, river.x1, extent.z1, 0)
	end
	local sea = M.Sea
	if type(sea) == "table" and type(sea.x0) == "number" then
		add("sea", sea.x0, extent.z0, extent.x1, extent.z1, 0)
	end
	local fx0, fz0, fx1, fz1 = boxOf(M.Lake)
	if fx0 and fz0 and fx1 and fz1 then
		add("ice", fx0, fz0, fx1, fz1, 40, "Frozen Lake")
	end
	local lakes: { any } = {}
	if M.AlpineLake ~= nil then
		table.insert(lakes, M.AlpineLake)
	end
	if type(M.Lakes) == "table" then
		for _, lake in M.Lakes do
			table.insert(lakes, lake)
		end
	end
	for _, lake in lakes do
		local x0, z0, x1, z1 = boxOf(lake)
		if x0 and z0 and x1 and z1 then
			local name = if type(lake.name) == "string" then lake.name else "Alpine Lake"
			add(if lake.frozen == true then "ice" else "lake", x0, z0, x1, z1, math.huge, name)
		end
	end
	return list
end

-- The snowfield in the valley (Map.Winter; before step 2 everything north of Map.WinterZ west of the river), clipped
-- to Map.Bounds; nil without one. With `extent`, where it reaches the bounds it goes on to the drawn area's edge (the
-- ring's feet are snow there too).
function MapStyle.winter(extent: Extent?): Rect?
	local M = Map :: any
	local B = Map.Bounds
	local x0, z0, x1, z1 = boxOf(M.Winter)
	if not (x0 and z0 and x1 and z1) and type(M.WinterZ) == "number" and type(M.River) == "table" then
		x0, z0, x1, z1 = B.x0, B.z0, M.River.x0, M.WinterZ
	end
	if not (x0 and z0 and x1 and z1) then
		return nil
	end
	x0, z0, x1, z1 = math.max(x0, B.x0), math.max(z0, B.z0), math.min(x1, B.x1), math.min(z1, B.z1)
	if x1 - x0 < 1 or z1 - z0 < 1 then
		return nil
	end
	if extent then
		x0 = if x0 <= B.x0 then extent.x0 else x0
		z0 = if z0 <= B.z0 then extent.z0 else z0
		x1 = if x1 >= B.x1 then extent.x1 else x1
		z1 = if z1 >= B.z1 then extent.z1 else z1
	end
	return { kind = "winter", x0 = x0, z0 = z0, x1 = x1, z1 = z1, round = 0 }
end

-- The old mountain with the tunnel through it (Map.Mountain), while it stands in the drawn area.
function MapStyle.mountain(extent: Extent): Disc?
	local m = (Map :: any).Mountain
	if type(m) ~= "table" or type(m.x) ~= "number" or type(m.z) ~= "number" or type(m.radius) ~= "number" then
		return nil
	end
	if m.x < extent.x0 or m.x > extent.x1 or m.z < extent.z0 or m.z > extent.z1 then
		return nil
	end
	return { kind = "mount", x = m.x, z = m.z, r = m.radius }
end

-- ── The ring ───────────────────────────────────────────────────────────────

local function sideOf(c: AlpineLayout.Cone): string
	if math.abs(c.nz) >= math.abs(c.nx) then
		return if c.nz < 0 then "north" else "south"
	end
	return if c.nx < 0 then "west" else "east"
end

-- The big map's peaks: every cone of the ring (the shoulders, the lower summits beside a big peak, only east and
-- west: there they fill the range) as a shaded peak in the margin round the bounds, its foot line nearer the valley
-- for the front row and farther out for the back row (by how far out its cone stands), its height by its cone's
-- (Config.MapStyle.Peaks). They stand up the map (the north's rise away from the valley, the south's toward it, never
-- into it; east and west wide enough to overlap into one range, their inner feet a little over the valley's edge).
-- Back to front: by the foot line, down the map (a lower peak stands in front of the ones over it).
function MapStyle.peaks(ring: AlpineLayout.Ring): { Peak }
	local P = S.Peaks
	local box = ring.box
	local m = S.Margin
	local cones: { AlpineLayout.Cone } = {}
	local dLow, dHigh, hLow, hHigh = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ring.cones do
		local side = sideOf(c)
		if c.row ~= "shoulder" or side == "west" or side == "east" then
			table.insert(cones, c)
			local d = AlpineLayout.boxDistance(box, c.x, c.z)
			dLow, dHigh = math.min(dLow, d), math.max(dHigh, d)
			hLow, hHigh = math.min(hLow, c.height), math.max(hHigh, c.height)
		end
	end
	local list: { Peak } = {}
	for _, c in cones do
		local d = AlpineLayout.boxDistance(box, c.x, c.z)
		local t = if dHigh > dLow then (d - dLow) / (dHigh - dLow) else 0
		local u = if hHigh > hLow then (c.height - hLow) / (hHigh - hLow) else 1
		local half = m * lerp(P.Height[1], P.Height[2], u)
		local side = sideOf(c)
		local x, z
		if side == "north" or side == "south" then
			x = math.clamp(c.x, box.x0 - m, box.x1 + m)
			if side == "north" then
				z = box.z0 - m * lerp(P.Base.north[1], P.Base.north[2], t)
				half = math.min(half, z - (box.z0 - m) - m * 0.02) -- (its top stays on the paper)
			else
				z = box.z1 + m * lerp(P.Base.south[1], P.Base.south[2], t)
				half = math.min(half, z - box.z1 - m * 0.04) -- (never up into the valley)
			end
		else
			local out = m * lerp(P.Base.side[1], P.Base.side[2], t)
			half = math.min(half, m * P.Side, out + m * P.Into) -- (its inner foot at most Into × Margin into the valley)
			x = if side == "west" then box.x0 - out else box.x1 + out
			z = math.clamp(c.z + half / 3, box.z0 - m + half, box.z1 + m) -- (its middle by its cone's)
		end
		local cap = 0
		if c.winter then
			cap = half * P.Winter
		elseif c.snow < c.height then
			cap = half * math.clamp((c.height - c.snow) / c.height, P.Cap[1], P.Cap[2])
		end
		-- (up the map, lit from the west: its east face in the shadow)
		table.insert(list, { x = x, z = z, ox = 0, oz = -1, sx = 1, sz = 0, half = half, cap = cap, winter = c.winter, side = side, row = c.row, cone = c.id, depth = t })
	end
	table.sort(list, function(a: Peak, b: Peak): boolean
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.x < b.x
	end)
	return list
end

-- The layer of a cone over height y (1 at the floor … its last), nil over its top.
local function layerOver(c: AlpineLayout.Cone, y: number): number?
	local i = math.max(1, math.floor((y - c.floor) / Config.Alpine.Layer) + 1)
	return if i <= #c.radii then i else nil
end

-- The minimap's mountains seen from above: for every cone that reaches within Relief.Reach of the bounds its grassy
-- foot, its rock from the grass line up and its snow from the snow line up (a winter cone: snow from its foot, its rock
-- bands, its top), each a disc round that layer's middle (the lean moves it), the ones that reach within Reach of the
-- bounds (the farthest the minimap sees from inside them). Back to front like the terrain's fills: the back row, the
-- shoulders, the closers, the front row.
function MapStyle.relief(ring: AlpineLayout.Ring): { Disc }
	local R = S.Relief
	local box = ring.box
	local order = { back = 1, shoulder = 2, closer = 3, pass = 3, front = 4 }
	local cones: { AlpineLayout.Cone } = {}
	for _, c in ring.cones do
		local foot = c.radii[1]
		if foot and AlpineLayout.boxDistance(box, c.x, c.z) - foot <= R.Reach then
			table.insert(cones, c)
		end
	end
	table.sort(cones, function(a: AlpineLayout.Cone, b: AlpineLayout.Cone): boolean
		local oa, ob = order[a.row] or 0, order[b.row] or 0
		if oa ~= ob then
			return oa < ob
		end
		return a.id < b.id
	end)
	local list: { Disc } = {}
	local function add(kind: string, c: AlpineLayout.Cone, i: number?)
		if i == nil then
			return
		end
		local r = c.radii[i]
		local x, z = AlpineLayout.layerAt(c, i)
		if kind == "snow" and r < R.MinSnow or AlpineLayout.boxDistance(box, x, z) - r > R.Reach then
			return -- (too small, or never in the minimap's sight from inside the bounds)
		end
		local made: Disc = { kind = kind, x = x, z = z, r = r }
		table.insert(list, made)
	end
	for _, c in cones do
		if c.winter then
			add("winter", c, 1)
			add("rock", c, layerOver(c, c.height * 0.3))
			add("snow", c, layerOver(c, c.height * 0.62))
		else
			add("foot", c, 1)
			add("rock", c, layerOver(c, c.green))
			if c.snow < math.huge then
				add("snow", c, layerOver(c, c.snow))
			end
		end
	end
	return list
end

-- ── The forests ────────────────────────────────────────────────────────────

-- The valley's forests (the trees off the ring's slopes) as bands: the trees binned in Forest.Cell squares over
-- Map.Bounds, a square with Forest.Min trees or more is forest, every row's run of forest squares one band (a snowy
-- run apart from a green one: the winter's trees).
function MapStyle.forestRuns(forest: AlpineLayout.Forest): { Run }
	local F = S.Forest
	local B = Map.Bounds
	local cell = F.Cell
	local cols = math.max(1, math.ceil((B.x1 - B.x0) / cell))
	local rows = math.max(1, math.ceil((B.z1 - B.z0) / cell))
	local count: { [number]: number } = {}
	local snowy: { [number]: number } = {}
	for _, t in forest.trees do
		if t.slope then
			continue
		end
		local cx, cz = math.floor((t.x - B.x0) / cell), math.floor((t.z - B.z0) / cell)
		if cx < 0 or cx >= cols or cz < 0 or cz >= rows then
			continue
		end
		local key = cz * cols + cx
		count[key] = (count[key] or 0) + 1
		if t.snowy then
			snowy[key] = (snowy[key] or 0) + 1
		end
	end
	local list: { Run } = {}
	for cz = 0, rows - 1 do
		local cx = 0
		while cx < cols do
			local key = cz * cols + cx
			local n = count[key] or 0
			if n < F.Min then
				cx += 1
				continue
			end
			local white = (snowy[key] or 0) * 2 > n
			local from = cx
			while cx < cols do
				local k = cz * cols + cx
				local m = count[k] or 0
				if m < F.Min or ((snowy[k] or 0) * 2 > m) ~= white then
					break
				end
				cx += 1
			end
			table.insert(list, { x0 = B.x0 + from * cell, x1 = B.x0 + cx * cell, z = B.z0 + (cz + 0.5) * cell, cells = cx - from, snowy = white })
		end
	end
	return list
end

function MapStyle.meadows(forest: AlpineLayout.Forest): { Spot }
	local list: { Spot } = {}
	for _, patch in forest.patches do
		table.insert(list, { x = patch.x, z = patch.z })
	end
	return list
end

function MapStyle.huts(forest: AlpineLayout.Forest): { Hut }
	local list: { Hut } = {}
	for _, hut in forest.huts do
		table.insert(list, { x = hut.x, z = hut.z, kind = hut.kind })
	end
	return list
end

-- The roads out of the valley that end at a closed tunnel (Config.Alpine.Portals: the West Pass): where the road meets
-- the bounds, its way out, how wide, where it starts inside (x or z), the tunnel's mouth (face studs out) and the sign.
function MapStyle.passes(ring: AlpineLayout.Ring): { Pass }
	local list: { Pass } = {}
	for _, p in ring.portals do
		table.insert(list, { id = p.id, name = p.name, x = p.x, z = p.z, nx = p.nx, nz = p.nz, width = p.width, from = p.from, face = p.face, text = "ROAD CLOSED" })
	end
	return list
end

-- ── The villages ───────────────────────────────────────────────────────────

-- The villages' labels: Map.Villages when Map names them (a list of { name, x, z } or name → { x, z }), sorted by name;
-- while none is the Altstadt, its placeholder over its district's name (Config.MapStyle.Altstadt).
function MapStyle.villages(): { Village }
	local list: { Village } = {}
	local named = (Map :: any).Villages
	if type(named) == "table" then
		for key, v in named do
			if type(v) == "table" and type(v.x) == "number" and type(v.z) == "number" then
				local name = if type(v.name) == "string" then v.name elseif type(key) == "string" then key else nil
				if name then
					table.insert(list, { name = name, x = v.x, z = v.z, placeholder = false })
				end
			end
		end
	end
	table.sort(list, function(a: Village, b: Village): boolean
		return a.name < b.name
	end)
	local A = S.Altstadt
	for _, v in list do
		if string.lower(v.name) == string.lower(A.Name) then
			return list
		end
	end
	for _, d in Map.Districts do
		if d.id == A.District then
			local x0, x1, z0 = Map.districtEdges(d)
			table.insert(list, { name = A.Name, x = (x0 + x1) / 2, z = z0 - 60, district = d.id, sub = d.name, placeholder = true })
		end
	end
	return list
end

-- ── The plan and the server's summary ──────────────────────────────────────

-- Everything the maps draw of the ring and the forest (MapView builds its layers from it).
export type Plan = { peaks: { Peak }, relief: { Disc }, runs: { Run }, meadows: { Spot }, huts: { Hut }, passes: { Pass } }

function MapStyle.plan(ring: AlpineLayout.Ring, forest: AlpineLayout.Forest): Plan
	return {
		peaks = MapStyle.peaks(ring),
		relief = MapStyle.relief(ring),
		runs = MapStyle.forestRuns(forest),
		meadows = MapStyle.meadows(forest),
		huts = MapStyle.huts(forest),
		passes = MapStyle.passes(ring),
	}
end

-- The summary: a plan packed into a short string (the server works the ring and the forest out anyway; every client
-- reads this instead of working them out again). Every number is three digits of base 64 (−131072 … 131071) in tenths
-- of a stud (a peak's depth in thousandths, the kinds as small codes) after the version and a header: the bounds and
-- the margin it was made for (a client with other ones works the plan out itself), then how many of each.
MapStyle.Name = "MapStyle" -- (the StringValue in ReplicatedStorage)
local VERSION = "MS1"
local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
local BIAS = 131072
local VALUE: { [number]: number } = {}
for k = 1, #DIGITS do
	VALUE[string.byte(DIGITS, k)] = k - 1
end
local DISCS = { "foot", "rock", "snow", "winter", "mount" }
local SIDES = { "north", "east", "south", "west" }
local HUTS = { "barn", "hut" }
local function codeOf(list: { string }, value: string): number
	return table.find(list, value) or 1
end
-- A unit vector's code (0 up the map, 1 east, 2 down, 3 west).
local function wayCode(x: number, z: number): number
	return if z < 0 then 0 elseif x > 0 then 1 elseif z > 0 then 2 else 3
end
local WAYS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

function MapStyle.encode(plan: Plan): string
	local out: { string } = { VERSION }
	local function put(v: number, scale: number)
		local n = math.clamp(math.floor(v * scale + 0.5), -BIAS, BIAS - 1) + BIAS
		local a, b, c = n // 4096 + 1, (n // 64) % 64 + 1, n % 64 + 1
		table.insert(out, string.sub(DIGITS, a, a) .. string.sub(DIGITS, b, b) .. string.sub(DIGITS, c, c))
	end
	local B = Map.Bounds
	for _, v in { B.x0, B.z0, B.x1, B.z1, S.Margin } do
		put(v, 1)
	end
	for _, list in { plan.peaks, plan.relief, plan.runs, plan.meadows, plan.huts, plan.passes } :: { { any } } do
		put(#list, 1)
	end
	for _, p in plan.peaks do
		put(p.x, 10)
		put(p.z, 10)
		put(p.half, 10)
		put(p.cap, 10)
		put(p.depth, 1000)
		put(wayCode(p.ox, p.oz) * 4 + wayCode(p.sx, p.sz), 1)
		put(codeOf(SIDES, p.side) * 2 + (if p.winter then 1 else 0), 1)
	end
	for _, d in plan.relief do
		put(codeOf(DISCS, d.kind), 1)
		put(d.x, 10)
		put(d.z, 10)
		put(d.r, 10)
	end
	for _, run in plan.runs do
		put(run.x0, 10)
		put(run.x1, 10)
		put(run.z, 10)
		put(run.cells, 1)
		put(if run.snowy then 1 else 0, 1)
	end
	for _, spot in plan.meadows do
		put(spot.x, 10)
		put(spot.z, 10)
	end
	for _, hut in plan.huts do
		put(hut.x, 10)
		put(hut.z, 10)
		put(codeOf(HUTS, hut.kind), 1)
	end
	for _, pass in plan.passes do
		local index = 0
		for k, p in Config.Alpine.Portals do
			if p.id == pass.id then
				index = k
			end
		end
		for _, v in { index, pass.x, pass.z, pass.nx, pass.nz, pass.width, pass.from, pass.face } do
			put(v, 10)
		end
	end
	return table.concat(out)
end

-- The plan back from a summary; nil when it is not one, or one made for other bounds or another margin.
function MapStyle.decode(text: string): Plan?
	if type(text) ~= "string" or string.sub(text, 1, #VERSION) ~= VERSION or (#text - #VERSION) % 3 ~= 0 then
		return nil
	end
	local at = #VERSION + 1
	local function take(scale: number): number
		local a, b, c = string.byte(text, at, at + 2)
		at += 3
		local va, vb, vc = VALUE[a or 0], VALUE[b or 0], VALUE[c or 0]
		if va == nil or vb == nil or vc == nil then
			error("not a summary")
		end
		return (va * 4096 + vb * 64 + vc - BIAS) / scale
	end
	local ok, plan = pcall(function(): Plan?
		local B = Map.Bounds
		if take(1) ~= B.x0 or take(1) ~= B.z0 or take(1) ~= B.x1 or take(1) ~= B.z1 or take(1) ~= S.Margin then
			return nil
		end
		local counts = {}
		for k = 1, 6 do
			counts[k] = take(1)
		end
		local need = 11 + counts[1] * 7 + counts[2] * 4 + counts[3] * 5 + counts[4] * 2 + counts[5] * 3 + counts[6] * 8
		if #text ~= #VERSION + 3 * need then
			return nil
		end
		local made: Plan = { peaks = {}, relief = {}, runs = {}, meadows = {}, huts = {}, passes = {} }
		for _ = 1, counts[1] do
			local x, z, half, cap, depth = take(10), take(10), take(10), take(10), take(1000)
			local ways, side = take(1), take(1)
			local o, s = WAYS[ways // 4 + 1], WAYS[ways % 4 + 1]
			table.insert(made.peaks, {
				x = x,
				z = z,
				ox = o[1],
				oz = o[2],
				sx = s[1],
				sz = s[2],
				half = half,
				cap = cap,
				winter = side % 2 == 1,
				side = SIDES[side // 2] or "north",
				row = "",
				cone = "",
				depth = depth,
			})
		end
		for _ = 1, counts[2] do
			local kind = DISCS[take(1)] or "rock"
			table.insert(made.relief, { kind = kind, x = take(10), z = take(10), r = take(10) })
		end
		for _ = 1, counts[3] do
			table.insert(made.runs, { x0 = take(10), x1 = take(10), z = take(10), cells = take(1), snowy = take(1) == 1 })
		end
		for _ = 1, counts[4] do
			table.insert(made.meadows, { x = take(10), z = take(10) })
		end
		for _ = 1, counts[5] do
			local x, z = take(10), take(10)
			table.insert(made.huts, { x = x, z = z, kind = HUTS[take(1)] or "hut" })
		end
		for _ = 1, counts[6] do
			local portal = Config.Alpine.Portals[math.floor(take(10) + 0.5)]
			local x, z, nx, nz, width, from, face = take(10), take(10), take(10), take(10), take(10), take(10), take(10)
			if portal then
				table.insert(made.passes, { id = portal.id, name = portal.name, x = x, z = z, nx = nx, nz = nz, width = width, from = from, face = face, text = "ROAD CLOSED" })
			end
		end
		return made
	end)
	return if ok then plan else nil
end

-- The summary of this place's ring and forest (AlpineLayout's, cached: server/Alpine.luau builds from the same).
function MapStyle.summary(): string
	return MapStyle.encode(MapStyle.plan(AlpineLayout.ring(), AlpineLayout.forest()))
end

-- The server (server/Main.server.luau, before World.build): the summary in a StringValue in `parent`
-- (ReplicatedStorage) for every client's maps (client/MapView.luau). A failure only warns: the clients then work the
-- plan out themselves, and the world is built all the same.
function MapStyle.publish(parent: Instance)
	local ok, made = pcall(MapStyle.summary)
	if not ok then
		warn(`[MapStyle] no summary for the maps: {made}`)
		return
	end
	local found = parent:FindFirstChild(MapStyle.Name)
	local value: StringValue = if found and found:IsA("StringValue") then found else Instance.new("StringValue")
	value.Name = MapStyle.Name
	value.Value = made
	value.Parent = parent
end

return MapStyle
