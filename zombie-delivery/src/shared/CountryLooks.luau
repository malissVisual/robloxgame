--!strict
-- 9.4 SANDBOX, the countryside (design/countryside/plan.py, plan.json): the art kit of the six spots' surroundings, the
-- railway, the hedges, fences and the stream, as plain numbers, the way shared/VillageLooks.luau gives the houses, the
-- D5, the trees and the fields (its Piece, its frames, its trees). Pure (no Roblox at its top level:
-- tests/countrylooks_test.luau runs it in the Luau CLI); shared/VillageScenery.luau lays it out on the map,
-- server/VillageWorld.luau makes the parts. Its colours, budgets and tuning are Config.Country's. Nothing of a village:
-- no street, no shop, no chapel.
--
-- A landmark comes in its own frame (VillageLooks.frame): its origin on the ground in the middle of its box, +Y up, +Z
-- out of its front (the way its yaw looks), +X to the right of somebody facing it; w along X, d along Z (its box turned
-- with its yaw); VillageLooks.place puts its pieces on the map. Every piece is inside its box, nothing under the ground.
-- The lines and the stream come on the map (their frame the map's).
--   The landmarks (SandboxMap.Landmarks' kinds, CountryLooks.landmark):
--     "barn"        the farm's barn: a plank body on a stone plinth, a slate gable roof (its gable to the front), the big
--                   double doors, the hayloft door
--     "tractor"     an old red tractor (its bonnet, cab, big rear and small front wheels, exhaust) and its trailer with a
--                   load of hay behind it
--     "bales"       the stackyard: round bales in a pyramid, two on end, a long haystack round its pole (its rounded
--                   top's lower half in its straight sides and under the ground: the one piece that reaches under it)
--     "paddock"     a post-and-rail fence round it (its gate at the front left open), a water trough
--     "muckheap"    the muck heap with a fork in it, a woodpile under a plank roof, a wheelbarrow
--     "fishpond"    the pond: three round waters on their grassy banks, reeds, a jetty out from the front (its cabin's)
--                   shore, a rowing boat by it, a bench, two willows
--     "garden"      the lone house's garden: a fence round it (its gate on the house's side), two fruit trees and a birch,
--                   vegetable beds, a washing line, a bench
--     "woodyard"    the lodge's woodpile under its roof, a stump with an axe in it, a chopping block, split logs, a
--                   sawhorse with a log
--     "weir"        a stone sill across the stream, the pool behind it, the foam below, two boulders
--     "footbridge"  plank deck on two stone abutments across the stream, its posts and rails
--     "apiary"      five beehives on their stands, each its colour
--     "railway"     the ballast, the sleepers and the two rails along its length (along Z), the portal of the underpass
--                   at its back (-Z: the D5's embankment); kept on every client (chunk "far")
--     "halt"        the lone halt: the platform and its edge, a ramp up, a shelter with its bench, the MEADOW HALT sign,
--                   a lamp
--     "spring"      10.6 the mill's spring: a round pool on its grassy bank, stones round it but on its front (+Z: where
--                   its stream leaves), reeds
--     "waterfall"   10.6 a stream off its island's edge: the edge across its middle (its +Z out over the sky), the water
--                   going over it, the fall down the island's side (Config.Country.Waterfall: Drop studs down, Wide), a
--                   thinner strand beside it, the spray at its foot; the one landmark that hangs under the ground
--   The lines (SandboxMap.TreeLines' kinds that are not trees, CountryLooks.line): "hedge" (a low hedge along each
--   segment: 10.6 every map island's rim hedge on its walls), "fence" (a post-and-rail fence: its posts Lines.Post apart
--   at most, two rails); 9.7's "screen" (a run zone's tall screen hedge) went with the run zones in 10.6
--   The stream (SandboxMap.Streams, CountryLooks.stream): its bed (Bank wider each side) and its water along each
--   segment, a hair higher every other one (no two tops on one plane where they meet)
--   The far view (CountryLooks.farRails): the railway going on past the Bounds at the ends it meets them
--
--   CountryLooks.landmark(kind, box, yaw, seed)   a landmark's pieces in its frame
--   CountryLooks.line(kind, points, seed)         a hedge's or a fence's pieces on the map
--   CountryLooks.stream(points, width, seed)      a stream's pieces on the map
--   CountryLooks.farRails(rails, bounds)          the railway past the Bounds (rails: the railway landmarks' boxes)
--   CountryLooks.budget(kind)                     the most parts a landmark of the kind may give
--   CountryLooks.Landmarks, CountryLooks.Lines    the kinds it knows

local Config = require(script.Parent.Config)
local VillageLooks = require(script.Parent.VillageLooks)

local CountryLooks = {}

type Piece = VillageLooks.Piece
type Box = VillageLooks.Box
type Frame = VillageLooks.Frame

local C = Config.Country
local P = C.Palette

CountryLooks.Landmarks = { "barn", "tractor", "bales", "paddock", "muckheap", "fishpond", "garden", "woodyard", "weir", "footbridge", "apiary", "railway", "halt", "spring", "waterfall" }
CountryLooks.Lines = { "hedge", "fence" }

-- A roof's numbers (as VillageLooks' houses): its overhang over the walls and the gables, its slabs' thickness.
local EAVE, VERGE, SLAB = 0.9, 0.7, 0.45

-- ── Small tools ────────────────────────────────────────────────────────────

local M = 2147483647

-- The dice: a Lehmer generator (VillageLooks' own), stirred first so near seeds part ways.
local function dice(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % (M - 1) + 1
	for _ = 1, 3 do
		state = (state * 48271) % M
	end
	return function(): number
		state = (state * 48271) % M
		return (state - 1) / (M - 1)
	end
end

local function pick<T>(roll: () -> number, list: { T }): T
	return list[math.floor(roll() * #list) % #list + 1]
end

type More = { shape: string?, turn: { number }?, solid: boolean?, alpha: number?, tag: string?, text: string?, ground: boolean? }
type Kit = { out: { Piece }, chunk: string }

local function put(k: Kit, name: string, size: { number }, at: { number }, color: { number }, material: string, more: More?): Piece
	local m: More = more or {}
	local p: Piece = {
		name = name,
		shape = m.shape or "Block",
		size = size,
		at = at,
		yaw = 0,
		turn = m.turn,
		color = color,
		material = material,
		solid = m.solid == true,
		alpha = m.alpha,
		tag = m.tag,
		text = m.text,
		unit = nil,
		ground = m.ground,
		chunk = k.chunk,
	}
	table.insert(k.out, p)
	return p
end

local SOLID: More = { solid = true }
local LYING: More = { shape = "Cylinder" } -- (a cylinder lies along its own X)
local STANDING: More = { shape = "Cylinder", turn = { 0, 0, 90 } } -- (… stood up: along Y)

-- A tree of a landmark (its trunk and crown in the landmark's frame: VillageLooks' tree).
local function tree(k: Kit, kind: string, x: number, z: number, seed: number)
	for _, p in VillageLooks.tree(kind, x, z, seed, k.chunk) do
		table.insert(k.out, p)
	end
end

-- A bench (seat, back, two legs) at (x, z) looking `facing` degrees about Y from +Z (VillageLooks' bench).
local function bench(k: Kit, x: number, z: number, facing: number)
	local a = math.rad(facing)
	local function at(u: number, y: number, v: number): { number }
		return { x + math.cos(a) * u + math.sin(a) * v, y, z - math.sin(a) * u + math.cos(a) * v }
	end
	local turn = { 0, facing, 0 }
	put(k, "BenchSeat", { 6, 0.35, 1.6 }, at(0, 1.9, 0), P.Bench, "WoodPlanks", { turn = turn, solid = true })
	put(k, "BenchBack", { 6, 1.5, 0.25 }, at(0, 2.8, -0.75), P.Bench, "WoodPlanks", { turn = turn })
	for _, s in { -1, 1 } do
		put(k, "BenchLeg", { 0.35, 2, 1.5 }, at(s * 2.6, 1, -0.05), P.Iron, "Metal", { turn = turn })
	end
end

-- A gable roof over a body W wide (X) and D deep (Z), its walls h high, its middle at z = zc, its ridge from the front
-- to the back (its gable to the front): the attic's two wedges in the walls' colour, the two slabs (EAVE over the
-- walls, VERGE over the gables) and the ridge (VillageLooks' "z" roof). Returns the rise over the walls.
local function gable(k: Kit, W: number, D: number, h: number, zc: number, pitch: number, wall: { number }, roof: { number }, material: string): number
	local half = W / 2
	local rise = half * math.tan(pitch)
	local deg = math.deg(pitch)
	local L = (half + EAVE) / math.cos(pitch)
	local y = h + rise - (L / 2) * math.sin(pitch) + (SLAB / 2) * math.cos(pitch)
	local out = (L / 2) * math.cos(pitch) + (SLAB / 2) * math.sin(pitch)
	local top = h + rise + SLAB * math.cos(pitch) + 0.2
	for _, s in { 1, -1 } do
		put(k, "Gable", { D, rise, half }, { s * half / 2, h + rise / 2, zc }, wall, "WoodPlanks", { shape = "Wedge", turn = { 0, -s * 90, 0 }, solid = true })
	end
	for _, s in { 1, -1 } do
		put(k, "Roof", { L, SLAB, D + 2 * VERGE }, { s * out, y, zc }, roof, material, { turn = { 0, 0, -s * deg }, solid = true })
	end
	put(k, "Ridge", { 1, 0.5, D + 2 * VERGE + 0.2 }, { 0, top, zc }, roof, material)
	return rise
end

-- A straight run of one piece from (ax, az) to (bx, bz) along X or Z, `y` its middle's height.
local function run(k: Kit, name: string, ax: number, az: number, bx: number, bz: number, y: number, tall: number, thick: number, color: { number }, material: string)
	local along = math.abs(bx - ax) >= math.abs(bz - az)
	local length = if along then math.abs(bx - ax) else math.abs(bz - az)
	put(k, name, if along then { length, tall, thick } else { thick, tall, length }, { (ax + bx) / 2, y, (az + bz) / 2 }, color, material)
end

-- A post-and-rail fence along X / Z runs in a frame: posts `step` apart at most (one where two runs meet), two rails.
local function railFence(k: Kit, runs: { { number } }, step: number, prefix: string)
	local seen: { [string]: boolean } = {}
	local tall = C.Lines.Rails[2] + 0.5
	for _, r in runs do
		local ax, az, bx, bz = r[1], r[2], r[3], r[4]
		local length = math.max(math.abs(bx - ax), math.abs(bz - az))
		local n = math.max(1, math.ceil(length / step - 1e-9))
		for i = 0, n do
			local x, z = ax + (bx - ax) * i / n, az + (bz - az) * i / n
			local key = `{math.floor(x * 10 + 0.5)}_{math.floor(z * 10 + 0.5)}`
			if not seen[key] then
				seen[key] = true
				put(k, prefix .. "Post", { 0.5, tall, 0.5 }, { x, tall / 2, z }, P.Post, "Wood")
			end
		end
		for _, y in C.Lines.Rails do
			run(k, prefix .. "Rail", ax, az, bx, bz, y, 0.35, 0.25, P.Fence, "WoodPlanks")
		end
	end
end

-- ── The farm ───────────────────────────────────────────────────────────────

-- "barn": the body on its plinth, the gable roof (its gable to the front), the doors and the hayloft door (11 parts).
local function barn(k: Kit, f: Frame, roll: () -> number)
	local B = P.Barn
	local W, D, h = f.w - 4, f.d - 6, 13
	local zf = f.d / 2 - 3
	local zc = zf - D / 2
	put(k, "Barn", { W, h, D }, { 0, h / 2, zc }, B.Wall, "WoodPlanks", SOLID)
	put(k, "Plinth", { W + 0.4, 1, D + 0.4 }, { 0, 0.5, zc }, P.Stone, "Cobblestone", SOLID)
	local rise = gable(k, W, D, h, zc, math.rad(40), B.Wall, B.Roof, "Slate")
	local dw, dh = W * 0.22, 10
	for _, s in { -1, 1 } do
		put(k, "BarnDoor", { dw, dh, 0.3 }, { s * dw / 2, dh / 2, zf + 0.15 }, B.Door, "WoodPlanks")
	end
	put(k, "DoorLintel", { 2 * dw + 1.2, 0.8, 0.4 }, { 0, dh + 0.4, zf + 0.2 }, B.Trim, "Wood")
	put(k, "Hayloft", { 5, 4.2, 0.3 }, { 0, h + math.min(4.5, rise * 0.3) + 2.1, zf + 0.15 }, B.Loft, "WoodPlanks")
end

-- "tractor": the tractor at the front (its nose to +Z) and its trailer of hay behind it (18 parts).
local function tractor(k: Kit, f: Frame, roll: () -> number)
	local T, R = P.Tractor, P.Trailer
	local zn = f.d / 2 - 3 -- (its nose)
	put(k, "Bonnet", { 4.4, 3.4, 8 }, { 0, 3.9, zn - 4 }, T.Body, "SmoothPlastic", SOLID)
	put(k, "Chassis", { 3.6, 1.4, 16 }, { 0, 2.0, zn - 8 }, T.Dark, "Metal", SOLID)
	put(k, "Cab", { 5.8, 5.2, 5.6 }, { 0, 7.2, zn - 13.5 }, T.Glass, "Glass", { alpha = 0.35, solid = true })
	put(k, "CabRoof", { 6.6, 0.5, 6.4 }, { 0, 10.05, zn - 13.5 }, T.Body, "SmoothPlastic")
	for _, s in { -1, 1 } do
		put(k, "RearWheel", { 1.8, 7.6, 7.6 }, { s * 3.9, 3.8, zn - 14 }, T.Tyre, "Fabric", { shape = "Cylinder", solid = true })
		put(k, "FrontWheel", { 1.2, 4, 4 }, { s * 3, 2, zn - 3 }, T.Tyre, "Fabric", { shape = "Cylinder", solid = true })
	end
	put(k, "Exhaust", { 0.4, 3.4, 0.4 }, { 1.4, 7.2, zn - 3.5 }, T.Dark, "Metal")
	local tz = zn - 34 -- (the trailer's middle)
	put(k, "Drawbar", { 0.5, 0.5, 6 }, { 0, 2.2, zn - 19 }, P.Iron, "Metal")
	put(k, "TrailerBed", { 8, 0.6, 24 }, { 0, 2.9, tz }, R.Bed, "WoodPlanks", SOLID)
	for _, s in { -1, 1 } do
		put(k, "TrailerSide", { 0.3, 2.2, 24 }, { s * 3.85, 4.3, tz }, R.Side, "WoodPlanks")
		put(k, "TrailerEnd", { 8, 2.2, 0.3 }, { 0, 4.3, tz + s * 11.85 }, R.Side, "WoodPlanks")
		put(k, "TrailerWheel", { 1.4, 4, 4 }, { s * 4.5, 2, tz }, T.Tyre, "Fabric", { shape = "Cylinder", solid = true })
	end
	put(k, "HayLoad", { 7.2, 3, 22 }, { 0, 4.7, tz }, P.Hay[1], "Grass")
end

-- "bales": round bales lying in a pyramid (four, three on them), two on end, the long haystack round its pole (12 parts).
local function bales(k: Kit, f: Frame, roll: () -> number)
	local bx, bz = -f.w / 2 + 14, -f.d / 2 + 12
	for i = 0, 3 do
		put(k, "Bale", { 4.6, 5.6, 5.6 }, { bx, 2.8, bz + i * 5.8 }, P.Hay[i % 2 + 1], "Grass", { shape = "Cylinder", solid = true })
	end
	for i = 0, 2 do
		put(k, "Bale", { 4.6, 5.6, 5.6 }, { bx, 7.6, bz + 2.9 + i * 5.8 }, P.Hay[(i + 1) % 2 + 1], "Grass", { shape = "Cylinder", solid = true })
	end
	for i = 0, 1 do
		put(k, "Bale", { 4.6, 5.6, 5.6 }, { 4 + i * 7, 2.3, -6 + i * 2 }, P.Hay[i + 1], "Grass", { shape = "Cylinder", turn = { 0, 0, 90 }, solid = true })
	end
	local hx, hz = f.w / 2 - 14, f.d / 2 - 16
	-- (the stack's straight sides 3 high, its rounded top on them: the ellipsoid as wide as the sides at its middle)
	put(k, "Haystack", { 12, 3, 22 }, { hx, 1.5, hz }, P.Hay[2], "Grass", SOLID)
	put(k, "HaystackTop", { 12, 11, 22 }, { hx, 3, hz }, P.Hay[1], "Grass", { shape = "Ellipsoid" })
	put(k, "HayPole", { 0.4, 14, 0.4 }, { hx, 7, hz }, P.Post, "Wood")
end

-- "paddock": its post-and-rail fence round it (the gate at the front's middle open), a water trough.
local function paddock(k: Kit, f: Frame, roll: () -> number)
	local a, b, gate = f.w / 2 - 0.6, f.d / 2 - 0.6, 6
	railFence(k, {
		{ -a, -b, a, -b },
		{ -a, -b, -a, b },
		{ a, -b, a, b },
		{ -a, b, -gate, b },
		{ gate, b, a, b },
	}, 20, "Paddock")
	put(k, "Trough", { 8, 1.6, 2.6 }, { f.w / 2 - 14, 0.8, -f.d / 2 + 10 }, P.Trough, "Metal")
	put(k, "TroughWater", { 7.2, 0.1, 1.8 }, { f.w / 2 - 14, 1.5, -f.d / 2 + 10 }, P.Water, "Glass")
end

-- "muckheap": the muck heap (two wedges back to back) with a fork, the woodpile under its roof, a wheelbarrow (9 parts).
local function muckheap(k: Kit, f: Frame, roll: () -> number)
	put(k, "Muck", { 14, 4.4, 6 }, { -6, 2.2, -7 }, P.Muck, "Ground", { shape = "Wedge", turn = { 0, 180, 0 }, solid = true })
	put(k, "Muck", { 14, 4.4, 6 }, { -6, 2.2, -13 }, P.Muck, "Ground", { shape = "Wedge", solid = true })
	put(k, "Pitchfork", { 0.2, 5, 0.2 }, { -3, 3.6, -10 }, P.Post, "Wood", { turn = { 20, 0, 0 } })
	put(k, "Woodpile", { 16, 4.2, 3.4 }, { 6, 2.1, 8 }, P.Log, "WoodPlanks", SOLID)
	put(k, "WoodpileEnds", { 16, 4.2, 0.1 }, { 6, 2.1, 9.75 }, P.LogEnd, "Wood")
	put(k, "WoodpileRoof", { 17, 0.3, 4.4 }, { 6, 4.6, 8 }, P.Post, "WoodPlanks")
	put(k, "Barrow", { 2.6, 1, 4 }, { 11, 1.6, -10 }, P.Steel, "Metal")
	put(k, "BarrowWheel", { 0.4, 1.6, 1.6 }, { 11, 0.8, -12.6 }, P.Tractor.Tyre, "Fabric", LYING)
	put(k, "BarrowHandles", { 2.2, 0.2, 2.8 }, { 11, 1.4, -6.8 }, P.Post, "Wood")
end

-- ── The pond ───────────────────────────────────────────────────────────────

-- A round of water (or of its bank): a flat cylinder stood up, its top at `top`.
local function disc(k: Kit, name: string, x: number, z: number, r: number, top: number, thick: number, color: { number }, material: string)
	put(k, name, { thick, 2 * r, 2 * r }, { x, top - thick / 2, z }, color, material, STANDING)
end

-- "fishpond": three round waters on their grassy banks (each its own height: no two tops on one plane), reeds in the
-- shallows, the jetty out from the front shore, the rowing boat by it, a bench, two willows (32 parts). Its rounds are
-- shares of its frame (half: the smaller half side); the jetty JETTY across from the middle (9.5 review: 0, on the
-- middle line: the Pond Cabin stands across from it, the jetty out from its own shore behind it; was a third of the way
-- along the shore), its shore end SHORE in from the front edge on the bank.
local POND = { { 0, 0.135, 0.889 }, { -0.333, -0.462, 0.556 }, { 0.511, 0, 0.467 } } -- (x / (w / 2), z / (d / 2), r / half)
local JETTY, SHORE = 0, 6
local function fishpond(k: Kit, f: Frame, roll: () -> number)
	local hw, hd = f.w / 2, f.d / 2
	local half = math.min(hw, hd)
	local rounds: { { number } } = {}
	for n, p in POND do
		local x, z, r = p[1] * hw, p[2] * hd, p[3] * half
		table.insert(rounds, { x, z, r })
		disc(k, "PondBank", x, z, r + (if n == 1 then 4 else 1.8), 0.2 - (n - 1) * 0.02, 0.16, P.Bank, "Grass")
	end
	for n, r in rounds do
		disc(k, "Water", r[1], r[2], r[3], 0.34 - (n - 1) * 0.02, 0.24, P.Water, "Glass")
	end
	-- reeds in the shallows round the rims
	for _, at in { { 1, 200 }, { 1, 245 }, { 2, 150 }, { 2, 205 }, { 3, 70 } } do
		local r = rounds[at[1]]
		local a = math.rad(at[2])
		put(k, "Reeds", { 4.6, 7, 4.6 }, { r[1] + math.cos(a) * (r[3] - 2), 3.5, r[2] + math.sin(a) * (r[3] - 2) }, pick(roll, P.Reeds), "LeafyGrass", { shape = "Ellipsoid" })
	end
	-- the jetty from the front shore out over the water, on four posts
	local jx, z1 = JETTY * hw, hd - SHORE
	put(k, "Jetty", { 4, 0.35, 28 }, { jx, 0.75, z1 - 14 }, P.Jetty, "WoodPlanks", SOLID)
	for _, s in { -1, 1 } do
		for _, z in { z1 - 26, z1 - 14 } do
			put(k, "JettyPost", { 0.5, 1.1, 0.5 }, { jx + s * 1.6, 0.55, z }, P.Post, "Wood")
		end
	end
	-- the rowing boat moored by its end
	local bx, bz = jx - 5, z1 - 22
	put(k, "BoatFloor", { 3.2, 0.3, 8 }, { bx, 0.45, bz }, P.BoatInside, "WoodPlanks")
	for _, s in { -1, 1 } do
		put(k, "BoatSide", { 0.25, 0.9, 8 }, { bx + s * 1.475, 0.9, bz }, P.Boat, "WoodPlanks")
		put(k, "BoatEnd", { 3.2, 0.9, 0.25 }, { bx, 0.9, bz + s * 3.875 }, P.Boat, "WoodPlanks")
		put(k, "Oar", { 0.18, 0.12, 6.5 }, { bx + s * 0.9, 1.05, bz + 0.4 }, P.Jetty, "Wood")
	end
	put(k, "BoatSeat", { 2.9, 0.2, 0.9 }, { bx, 1.05, bz - 1.5 }, P.BoatInside, "WoodPlanks")
	bench(k, jx - 14, hd - 7, 180) -- (on the front shore, looking over the water)
	local willow = Config.Village.Trees.willow
	local inset = willow.Height[2] * willow.Wide / 2 + 1 -- (the biggest willow's crown inside the box)
	tree(k, "willow", -(hw - inset), hd - inset - 1, math.floor(roll() * 999983) + 1)
	tree(k, "willow", hw - inset, hd - inset - 11, math.floor(roll() * 999983) + 2)
end

-- ── The lone house, the lodge, the mill, the cottage ───────────────────────

-- "garden": its fence (the gate on the house's side, -X), two fruit trees and a birch, three vegetable beds, a washing
-- line, a bench (26 parts).
local function garden(k: Kit, f: Frame, roll: () -> number)
	local a, b = f.w / 2 - 0.5, f.d / 2 - 0.5
	local H = 3
	run(k, "GardenFence", a, -b, a, b, H / 2, H, 0.25, P.Fence, "WoodPlanks")
	run(k, "GardenFence", -a, b, a, b, H / 2, H, 0.25, P.Fence, "WoodPlanks")
	run(k, "GardenFence", -a, -b, a, -b, H / 2, H, 0.25, P.Fence, "WoodPlanks")
	run(k, "GardenFence", -a, -b, -a, -2.5, H / 2, H, 0.25, P.Fence, "WoodPlanks")
	run(k, "GardenFence", -a, 2.5, -a, b, H / 2, H, 0.25, P.Fence, "WoodPlanks")
	tree(k, "fruit", 10, -12, math.floor(roll() * 999983) + 1)
	tree(k, "fruit", 12, 10, math.floor(roll() * 999983) + 2)
	tree(k, "birch", -13, -3, math.floor(roll() * 999983) + 3)
	for i = 0, 2 do
		put(k, "VegBed", { 13, 0.3, 2.4 }, { -3, 0.15, 3 + i * 3.6 }, P.Soil, "Ground")
		put(k, "Vegetables", { 12, 0.6, 1.2 }, { -3, 0.6, 3 + i * 3.6 }, P.Veg, "LeafyGrass")
	end
	for _, z in { -18, -6 } do
		put(k, "LinePost", { 0.3, 6, 0.3 }, { -6, 3, z }, P.Post, "Wood")
	end
	put(k, "WashingLine", { 0.08, 0.08, 12 }, { -6, 5.8, -12 }, P.Line, "SmoothPlastic")
	for n, z in { -15, -10 } do
		put(k, "Washing", { 0.1, 2.2, 1.8 }, { -6, 4.65, z }, P.Washing[n], "Fabric")
	end
	bench(k, -17, 13, 90)
end

-- "woodyard": the woodpile under its roof, a stump with an axe in it, a chopping block, split logs, a sawhorse with a
-- log on it (13 parts).
local function woodyard(k: Kit, f: Frame, roll: () -> number)
	put(k, "Woodpile", { 16, 4.4, 3.4 }, { -2, 2.2, -8 }, P.Log, "WoodPlanks", SOLID)
	put(k, "WoodpileEnds", { 16, 4.4, 0.1 }, { -2, 2.2, -6.25 }, P.LogEnd, "Wood")
	put(k, "WoodpileRoof", { 17, 0.3, 4.6 }, { -2, 4.7, -8 }, P.Post, "WoodPlanks")
	put(k, "Stump", { 2, 3.2, 3.2 }, { 6, 1, 4 }, P.Stump, "Wood", { shape = "Cylinder", turn = { 0, 0, 90 }, solid = true })
	put(k, "AxeHandle", { 0.25, 2.8, 0.25 }, { 6.3, 3.1, 4.2 }, P.LogEnd, "Wood", { turn = { 0, 0, -18 } })
	put(k, "AxeHead", { 1, 0.5, 0.18 }, { 6.8, 4.3, 4.2 }, P.Steel, "Metal")
	put(k, "ChoppingBlock", { 1.4, 2.6, 2.6 }, { -5, 0.7, 5 }, P.Stump, "Wood", { shape = "Cylinder", turn = { 0, 0, 90 }, solid = true })
	for i = 0, 1 do
		put(k, "Log", { 5, 1.1, 1.1 }, { 2, 0.55, 8.4 + i * 1.3 }, P.Log, "Wood", LYING)
	end
	put(k, "SawhorseBeam", { 4.2, 0.45, 0.45 }, { -8, 2.6, 1 }, P.Post, "Wood")
	for _, s in { -1, 1 } do
		put(k, "SawhorseLeg", { 0.3, 2.4, 2.2 }, { -8 + s * 1.6, 1.2, 1 }, P.Post, "Wood")
	end
	put(k, "Log", { 5.5, 1, 1 }, { -8, 3.3, 1 }, P.Log, "Wood", LYING)
end

-- "weir": the stone sill across the stream (along X), the pool behind it (+Z: upstream), the foam below, two boulders
-- (5 parts).
local function weir(k: Kit, f: Frame, roll: () -> number)
	put(k, "WeirSill", { f.w - 4, 1.0, 1.6 }, { 0, 0.5, 0 }, P.Stone, "Cobblestone", SOLID)
	put(k, "WeirPool", { 8, 0.2, 4.6 }, { 0, 0.35, 2.7 }, P.Water, "Glass")
	put(k, "WeirFoam", { 8.6, 0.06, 3 }, { 0, 0.3, -2.4 }, P.Foam, "SmoothPlastic", { alpha = 0.2 })
	for _, s in { -1, 1 } do
		put(k, "Boulder", { 3.2, 2, 3.2 }, { s * (f.w / 2 - 2), 1, 0 }, P.Stone, "Slate", { shape = "Ellipsoid" })
	end
end

-- "footbridge": its plank deck on two stone abutments (along X, across the stream), four posts, two rails (9 parts).
local function footbridge(k: Kit, f: Frame, roll: () -> number)
	local L = f.w - 2
	for _, s in { -1, 1 } do
		put(k, "Abutment", { 2.4, 1, 4.6 }, { s * (L / 2 - 0.2), 0.5, 0 }, P.Stone, "Cobblestone", SOLID)
	end
	put(k, "Deck", { L, 0.4, 4 }, { 0, 1.2, 0 }, P.Jetty, "WoodPlanks", SOLID)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			put(k, "BridgePost", { 0.3, 2.4, 0.3 }, { sx * (L / 2 - 0.6), 2.6, sz * 1.85 }, P.Post, "Wood")
		end
	end
	for _, sz in { -1, 1 } do
		put(k, "BridgeRail", { L - 1, 0.25, 0.25 }, { 0, 3.6, sz * 1.85 }, P.Fence, "Wood")
	end
end

-- "apiary": five hives along Z on their stands, each its colour, a roof on each (15 parts).
local function apiary(k: Kit, f: Frame, roll: () -> number)
	local n = 5
	local gap = math.min(7, (f.d - 4) / n)
	for i = 0, n - 1 do
		local z = (i - (n - 1) / 2) * gap
		put(k, "HiveStand", { 2.6, 1, 2.6 }, { 0, 0.5, z }, P.Post, "Wood")
		put(k, "Hive", { 2.4, 2.6, 2.4 }, { 0, 2.3, z }, P.Hives[i % #P.Hives + 1], "WoodPlanks", SOLID)
		put(k, "HiveRoof", { 3, 0.4, 3 }, { 0, 3.8, z }, P.HiveRoof, "Metal")
	end
end

-- ── 10.6 The spring and the waterfall ───────────────────────────────────────

-- "spring": its grassy bank and the round pool in it (each its own height: no two tops on one plane), Spring.Stones
-- stones round its rim but on its front (+Z: its stream leaves there), two clumps of reeds (9 parts).
local function spring(k: Kit, f: Frame, roll: () -> number)
	local S = C.Spring
	local r = math.min(f.w, f.d) / 2 - 1
	disc(k, "SpringBank", 0, 0, r, 0.2, 0.16, P.Bank, "Grass")
	disc(k, "SpringPool", 0, 0, r - S.Bank, 0.36, 0.24, P.Water, "Glass")
	for n = 1, S.Stones do
		-- (round the rim from its left to its right the long way: never over the stream at +Z, angle 90°)
		local a = math.rad(90 + 40 + (n - 0.5) / S.Stones * 280 + (roll() - 0.5) * 12)
		local size = 1.6 + roll() * 1.6
		put(k, "SpringStone", { size * 1.3, size * 0.8, size }, { math.cos(a) * (r - 1), size * 0.4, math.sin(a) * (r - 1) }, P.Stone, "Slate", { shape = "Ellipsoid" })
	end
	for _, side in { -1, 1 } do
		put(k, "Reeds", { 3.6, 6, 3.6 }, { side * (r - 3) * 0.7, 3, -(r - 3) * 0.7 }, pick(roll, P.Reeds), "LeafyGrass", { shape = "Ellipsoid" })
	end
end

-- "waterfall": the island's edge across its middle (z 0), +Z out over the sky: the water going over the edge, its foam on
-- the lip, the fall down the island's side (Waterfall.Drop down, Wide), a thinner strand beside it, the spray at its foot
-- (5 parts; decoration, see-through water).
local function waterfall(k: Kit, f: Frame, roll: () -> number)
	local F = C.Waterfall
	local water = { math.min(255, P.Water[1] + 40), math.min(255, P.Water[2] + 50), math.min(255, P.Water[3] + 50) }
	put(k, "FallLip", { F.Wide, 0.12, f.d / 2 + 1 }, { 0, C.Streams.Water + 0.02, -(f.d / 2 + 1) / 2 + 1 }, P.Water, "Glass")
	put(k, "FallFoam", { F.Wide + 1, 0.3, 1.4 }, { 0, C.Streams.Water + 0.1, 0.4 }, P.Foam, "SmoothPlastic", { alpha = 0.2 })
	put(k, "Waterfall", { F.Wide, F.Drop, 0.4 }, { 0, -F.Drop / 2 + 0.2, 1.1 }, water, "Glass", { alpha = 0.25 })
	put(k, "FallStrand", { F.Wide * 0.35, F.Drop * 0.7, 0.3 }, { F.Wide * 0.55 * (if roll() < 0.5 then -1 else 1), -F.Drop * 0.35, 1.6 }, water, "Glass", { alpha = 0.4 })
	put(k, "FallSpray", { F.Mist, F.Mist * 0.6, F.Mist }, { 0, -F.Drop + 1, 2.5 }, P.Foam, "SmoothPlastic", { shape = "Ellipsoid", alpha = 0.55 })
end

-- ── The railway ────────────────────────────────────────────────────────────

-- "railway": the ballast, the sleepers and the two rails along Z, the underpass's portal at its back (-Z) (8 parts).
local function railway(k: Kit, f: Frame, roll: () -> number)
	local d = f.d
	put(k, "Ballast", { 10, 0.6, d }, { 0, 0.3, 0 }, P.Ballast, "Pebble", SOLID)
	put(k, "Sleepers", { 7.2, 0.14, d }, { 0, 0.67, 0 }, P.Sleepers, "Wood")
	for _, s in { -1, 1 } do
		put(k, "Rail", { 0.45, 0.4, d }, { s * 2.4, 0.94, 0 }, P.Rail, "Metal")
		put(k, "PortalWall", { 1.4, 6.2, 2 }, { s * 5.2, 3.1, -d / 2 + 1 }, P.Concrete, "Concrete", SOLID)
	end
	put(k, "PortalLintel", { 11.8, 1.4, 2 }, { 0, 6.9, -d / 2 + 1 }, P.Concrete, "Concrete", SOLID)
	put(k, "Underpass", { 9, 6.2, 0.2 }, { 0, 3.1, -d / 2 + 0.1 }, P.Opening, "SmoothPlastic")
end

-- "halt": the platform (its edge to -Z, the track's side), the ramp up at its +X end, the shelter with its bench, the
-- MEADOW HALT sign (its words to +Z), a lamp (11 parts).
local function halt(k: Kit, f: Frame, roll: () -> number)
	local len = f.w - 10
	local px = -5 -- (the platform's middle: the ramp at its +X end)
	put(k, "Platform", { len, 1.2, 10 }, { px, 0.6, -2 }, P.Platform, "Concrete", SOLID)
	put(k, "PlatformEdge", { len, 0.06, 0.5 }, { px, 1.23, -6.6 }, P.Edge, "SmoothPlastic")
	put(k, "Ramp", { 10, 1.2, 8 }, { px + len / 2 + 4, 0.6, -2 }, P.Platform, "Concrete", { shape = "Wedge", turn = { 0, -90, 0 }, solid = true })
	put(k, "ShelterWall", { 12, 6, 0.4 }, { -24, 4.2, 2.6 }, P.Shelter, "Brick", SOLID)
	put(k, "ShelterRoof", { 13, 0.4, 5 }, { -24, 7.4, 0.6 }, P.ShelterRoof, "Metal")
	put(k, "ShelterBench", { 8, 0.4, 1.4 }, { -24, 2.2, 1.6 }, P.Bench, "WoodPlanks")
	for _, s in { -1, 1 } do
		put(k, "SignPost", { 0.3, 6, 0.3 }, { 14 + s * 4.6, 3, 4.6 }, P.Iron, "Metal")
	end
	put(k, "HaltSign", { 10, 1.8, 0.3 }, { 14, 5.2, 4.8 }, P.Sign, "SmoothPlastic", { tag = "sign", text = "MEADOW HALT" })
	put(k, "LampPost", { 0.4, 7.2, 0.4 }, { 26, 4.8, 1 }, P.Iron, "Metal", SOLID)
	put(k, "Lamp", { 1.4, 0.5, 1.4 }, { 26, 8.6, 1 }, P.Iron, "Metal")
end

local KINDS: { [string]: (Kit, Frame, () -> number) -> () } = {
	barn = barn,
	tractor = tractor,
	bales = bales,
	paddock = paddock,
	muckheap = muckheap,
	fishpond = fishpond,
	garden = garden,
	woodyard = woodyard,
	weir = weir,
	footbridge = footbridge,
	apiary = apiary,
	railway = railway,
	halt = halt,
	spring = spring,
	waterfall = waterfall,
}

function CountryLooks.landmark(kind: string, box: Box, yaw: number, seed: number): { Piece }
	local build = KINDS[kind]
	if not build then
		error(`CountryLooks.landmark: no landmark kind "{kind}"`)
	end
	local f = VillageLooks.frame(box, yaw)
	local k: Kit = { out = {}, chunk = if kind == "railway" then "far" else VillageLooks.chunkOf(f.x, f.z) }
	build(k, f, dice(seed))
	return k.out
end

function CountryLooks.budget(kind: string): number
	return C.Budget[kind] or 0
end

-- ── The lines and the stream (on the map) ──────────────────────────────────

-- A piece's turn about Y that lays its own X along (dx, dz) on the map.
local function heading(dx: number, dz: number): { number }
	return { 0, math.deg(math.atan2(-dz, dx)), 0 }
end

-- A hedge (each segment one piece, a little longer at a bend, every other a hair taller: no two tops on one plane) or a
-- post-and-rail fence (its posts Lines.Post apart at most, one at each bend; two rails) along a polyline on the map.
function CountryLooks.line(kind: string, points: { { x: number, z: number } }, seed: number): { Piece }
	local out: { Piece } = {}
	if kind == "hedge" then
		local H = C.Lines.Hedge
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local dx, dz = b.x - a.x, b.z - a.z
			local length = math.sqrt(dx * dx + dz * dz)
			local k: Kit = { out = out, chunk = VillageLooks.chunkOf((a.x + b.x) / 2, (a.z + b.z) / 2) }
			local tall = H.Height + (i % 2) * 0.15
			put(k, "Hedge", { length + (if #points > 2 then H.Width else 0), tall, H.Width }, { (a.x + b.x) / 2, tall / 2, (a.z + b.z) / 2 }, P.Hedge, "LeafyGrass", { turn = heading(dx, dz) })
		end
	elseif kind == "fence" then
		local seen: { [string]: boolean } = {}
		local tall = C.Lines.Rails[2] + 0.5
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local dx, dz = b.x - a.x, b.z - a.z
			local length = math.sqrt(dx * dx + dz * dz)
			local k: Kit = { out = out, chunk = VillageLooks.chunkOf((a.x + b.x) / 2, (a.z + b.z) / 2) }
			local n = math.max(1, math.ceil(length / C.Lines.Post - 1e-9))
			for j = 0, n do
				local x, z = a.x + dx * j / n, a.z + dz * j / n
				local key = `{math.floor(x * 10 + 0.5)}_{math.floor(z * 10 + 0.5)}`
				if not seen[key] then
					seen[key] = true
					put({ out = out, chunk = VillageLooks.chunkOf(x, z) }, "FencePostCountry", { 0.5, tall, 0.5 }, { x, tall / 2, z }, P.Post, "Wood")
				end
			end
			for _, y in C.Lines.Rails do
				put(k, "FenceRailCountry", { length, 0.35, 0.25 }, { (a.x + b.x) / 2, y, (a.z + b.z) / 2 }, P.Fence, "WoodPlanks", { turn = heading(dx, dz) })
			end
		end
	else
		error(`CountryLooks.line: no line kind "{kind}"`)
	end
	return out
end

type Layer = { name: string, wide: number, top: number, thick: number, color: { number }, material: string }

-- A stream along its middle line: each segment's bed (Bank wider each side, its top BankTop) and its water (its top
-- Water), both reaching on past a bend so the next one's ends meet them (every other one a hair higher there), the
-- first and the last ending at their points.
function CountryLooks.stream(points: { { x: number, z: number } }, width: number, seed: number): { Piece }
	local S = C.Streams
	local out: { Piece } = {}
	local n = #points - 1
	for i = 1, n do
		local a, b = points[i], points[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local length = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / length, dz / length
		local k: Kit = { out = out, chunk = VillageLooks.chunkOf((a.x + b.x) / 2, (a.z + b.z) / 2) }
		local lift = (i % 2) * 0.02
		local layers: { Layer } = {
			{ name = "StreamBed", wide = width + 2 * S.Bank, top = S.BankTop + lift, thick = 0.1, color = P.Bed, material = "Ground" },
			{ name = "Water", wide = width, top = S.Water + lift, thick = 0.12, color = P.Water, material = "Glass" },
		}
		for _, layer in layers do
			local before = if i > 1 then layer.wide / 2 else 0
			local after = if i < n then layer.wide / 2 else 0
			local mid = (after - before) / 2 -- (the piece's middle off the segment's)
			put(k, layer.name, { length + before + after, layer.thick, layer.wide }, { (a.x + b.x) / 2 + ux * mid, layer.top - layer.thick / 2, (a.z + b.z) / 2 + uz * mid },
				layer.color, layer.material, { turn = heading(dx, dz) })
		end
	end
	return out
end

-- The railway going on past the Bounds (Far.Rails studs) from each railway landmark that meets their west or east edge:
-- its ballast and two rails (the far view's: chunk "far").
function CountryLooks.farRails(rails: { Box }, bounds: Box): { Piece }
	local out: { Piece } = {}
	local k: Kit = { out = out, chunk = "far" }
	local reach = C.Far.Rails
	for _, r in rails do
		local z = (r.z0 + r.z1) / 2
		for _, side in { { r.x0, bounds.x0, -1 }, { r.x1, bounds.x1, 1 } } do
			if math.abs(side[1] - side[2]) < 1e-6 then
				local x = side[2] + side[3] * reach / 2
				put(k, "FarBallast", { reach, 0.6, 10 }, { x, 0.3, z }, P.Ballast, "Pebble")
				for _, s in { -1, 1 } do
					put(k, "FarRail", { reach, 0.4, 0.45 }, { x, 0.94, z + s * 2.4 }, P.Rail, "Metal")
				end
			end
		end
	end
	return out
end

return CountryLooks
