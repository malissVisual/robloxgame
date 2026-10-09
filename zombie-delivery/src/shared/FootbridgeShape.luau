--!strict
-- 6.12.16, the footbridge over Bone St (shared/Map.luau Map.Footbridge) as plain numbers: every piece of it (its size,
-- where it is, its turn, its colour and whether it is solid). server/Footbridge.luau makes a part of each;
-- tests/garden_test.luau scans them (nothing in the walkway, no step in the walking surface, the clearance over the
-- street). Pure: no Roblox in it.
--
--   the walking surface  plank boxes along the curved centre line (Map.Footbridge.line), each a straight chord: short
--                        on the turns, so that where two meet the step is under a tenth of a stud across the whole
--                        walkway, and each a little longer than its chord where the turn opens a gap (the joins
--                        overlap: solid); level across, as steep along as the line
--   the railings         on both edges, outside the walkway: a vermilion kick board (no wheel rolls off), a hand rail,
--                        posts between them with brass caps, a red paper lantern on a post now and then (lit at night)
--   the span             between the gates, over the sidewalks and the road: a taiko-bridge hump (Map.Footbridge.hump),
--                        a dark timber girder on each outer face, deeper toward the middle (an arch), vermilion ribs on
--                        it; nothing under it but the street
--   the gates            a vermilion torii at each end of the span, on the deck's outriggers: posts outside the
--                        railings, the crossbeams more than Map.Footbridge.headroom over the walkway, a paper lantern
--                        hanging from each end of the top beam
--   under the ramps      timber bents (two posts and a cap beam) where the ramp is high enough, never on a path
--   the park's foot      a lantern post on the lawn beside it
--   under the low ramps  (6.12.16 review) where a ramp is lower than Map.Footbridge.low (9) over the ground: a planted
--                        bed (soil, shrubs, flowers) closed by clipped hedges along both edges and across its high end,
--                        too tall for anyone to get between them and the ramp (nobody walks or rides under it there)
-- Solid (CanCollide): the walking surface, the railings and the beds' hedges; everything else is decoration (no
-- collision, no ray hits).
local Map = require(script.Parent.Map)

local FootbridgeShape = {}

export type Vec = { number }
export type Piece = {
	name: string,
	size: Vec, -- along its right, up and back
	at: Vec, -- its middle
	right: Vec,
	up: Vec,
	back: Vec,
	color: Vec, -- 0 … 255
	material: string,
	solid: boolean, -- CanCollide: the walking surface and the railings
	walk: boolean, -- the walking surface
	shape: string?, -- "Cylinder" (along its right) or "Ball"
	glow: string?, -- lit at night: "paper" (a paper lantern) or "glass" (a post lantern)
	light: number?, -- a real light too: its range
}

local PLANKS = { 150, 110, 74 }
local TIMBER = { 86, 60, 42 }
local VERMILION = { 196, 62, 42 }
local BRASS = { 206, 166, 74 }
local INK = { 34, 30, 28 } -- the gates' top beams, their posts' sleeves, the lanterns' caps
local PAPER = { 214, 64, 46 }
local GLASS = { 232, 222, 196 }

local SLAB = Map.Footbridge.slab -- the walking surface's planks on the ramps (on the span Map.Footbridge.thick)
local KICK = 1 -- the kick board's top over the walking surface
local DECK_EDGE = 0.3 -- the planks reach this far under the kick boards
local KICK_THICK = 0.25
local RAIL_THICK = 0.3
local POST = 0.42
local CLEAR = 0.04 -- the railings stand this far out of the walkway (their pieces are straight: on a turn they lean in a hair)
local GIRDER = 0.35 -- the span's girders' thickness, outside the kick boards
FootbridgeShape.Slab = SLAB

type Frame = { x: number, y: number, z: number, dx: number, dz: number }

local function add(out: { Piece }, name: string, size: Vec, at: Vec, right: Vec, up: Vec, back: Vec, color: Vec, material: string, solid: boolean, walk: boolean?): Piece
	local p: Piece = { name = name, size = size, at = at, right = right, up = up, back = back, color = color, material = material, solid = solid, walk = walk == true }
	table.insert(out, p)
	return p
end

-- A box whose middle line runs from a to b (its right level, across the line), `w` across and `h` high, lifted `lift`
-- along its up off that line (-h / 2: its top on the line), `ea` / `eb` longer than the line at a / b.
local function beam(out: { Piece }, name: string, a: Vec, b: Vec, w: number, h: number, lift: number, ea: number, eb: number, color: Vec, material: string, solid: boolean, walk: boolean?): Piece
	local vx, vy, vz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local length = math.sqrt(vx * vx + vy * vy + vz * vz)
	local lx, ly, lz = vx / length, vy / length, vz / length
	local flat = math.sqrt(lx * lx + lz * lz)
	local rx, rz = -lz / flat, lx / flat
	local ux, uy, uz = -ly * rz, -lz * rx + lx * rz, ly * rx -- (the back, -look, across the right)
	local shift = (eb - ea) / 2
	local at = { (a[1] + b[1]) / 2 + lx * shift + ux * lift, (a[2] + b[2]) / 2 + ly * shift + uy * lift, (a[3] + b[3]) / 2 + lz * shift + uz * lift }
	return add(out, name, { w, h, length + ea + eb }, at, { rx, 0, rz }, { ux, uy, uz }, { -lx, -ly, -lz }, color, material, solid, walk)
end

-- The frame of the centre line at s, and a point of it: `o` to the left (- to the right), `h` up, `a` along.
local function frameAt(s: number): Frame
	local x, y, z, dx, dz = Map.footbridgeAt(s)
	return { x = x, y = y, z = z, dx = dx, dz = dz }
end
local function point(f: Frame, o: number, h: number, a: number): Vec
	return { f.x + f.dz * o + f.dx * a, f.y + h, f.z - f.dx * o + f.dz * a }
end

-- A piece standing in frame f: its right across the walkway (to the left), its up up, its back along the way.
local function standing(out: { Piece }, name: string, f: Frame, o: number, h: number, a: number, size: Vec, color: Vec, material: string, solid: boolean): Piece
	return add(out, name, size, point(f, o, h, a), { f.dz, 0, -f.dx }, { 0, 1, 0 }, { f.dx, 0, f.dz }, color, material, solid)
end

-- An upright cylinder (its axis up) or a ball at `at`.
local function upright(out: { Piece }, name: string, at: Vec, length: number, diameter: number, color: Vec, material: string): Piece
	local p = add(out, name, { length, diameter, diameter }, at, { 0, 1, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, color, material, false)
	p.shape = "Cylinder"
	return p
end
local function ball(out: { Piece }, name: string, at: Vec, diameter: number, color: Vec, material: string): Piece
	local p = add(out, name, { diameter, diameter, diameter }, at, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, color, material, false)
	p.shape = "Ball"
	return p
end

-- A red paper lantern, its middle at `at` (`size` its diameter): the paper (lit at night), a black cap over and under.
local function paperLantern(out: { Piece }, at: Vec, size: number, light: number?)
	local paper = upright(out, "PaperLantern", at, size * 1.2, size, PAPER, "SmoothPlastic")
	paper.glow = "paper"
	paper.light = light
	for _, dy in { 1, -1 } do
		upright(out, "LanternCap", { at[1], at[2] + dy * (size * 0.6 + 0.06), at[3] }, 0.14, size * 0.62, INK, "Wood")
	end
end

-- ── Where things may stand ──────────────────────────────────────────────────

-- Is (x, z) on the lawn of the park or the garden (`margin` in from its edge)?
local function onLawn(x: number, z: number, margin: number): boolean
	local lawn = Map.BlockSize / 2 - Map.Park.walk - margin
	for _, home in { { x = Map.Park.x, z = Map.Park.z }, { x = Map.Garden.x, z = Map.Garden.z } } do
		if math.abs(x - home.x) <= lawn and math.abs(z - home.z) <= lawn then
			return true
		end
	end
	return false
end

-- The distance from the park's middle across its pond's octagon (its flat sides to the streets and the corners).
local function octagon(u: number, v: number): number
	local d = 0
	for k = 0, 7 do
		d = math.max(d, u * math.cos(k * math.pi / 4) + v * math.sin(k * math.pi / 4))
	end
	return d
end

-- Is (x, z) on (or within `r` of) a path of the park (the ring round the pond, the paths to the sides' middles and to
-- the corners, as far as Map.Park.corners reaches) or of the garden (Map.Garden.paths)?
function FootbridgeShape.onPath(x: number, z: number, r: number): boolean
	local P = Map.Park
	local u, v = x - P.x, z - P.z
	if math.abs(u) <= Map.BlockSize / 2 and math.abs(v) <= Map.BlockSize / 2 then
		local ringIn, ringOut = P.pond + 1.5, P.pond + 1.5 + P.ring
		local d = octagon(u, v)
		if d >= ringIn - r and d <= ringOut + r then
			return true
		end
		for k = 0, 7 do
			local angle = k * math.pi / 4
			local along = u * math.cos(angle) + v * math.sin(angle)
			local across = math.abs(-u * math.sin(angle) + v * math.cos(angle))
			local half = if k % 2 == 0 then 2.5 else 2 -- (the side paths 5 wide, the corner ones 4)
			local reach = if k % 2 == 0 then Map.BlockSize / 2 - P.walk else P.corners[(k - 1) // 2 + 1]
			if along > ringOut - 0.5 - r and along < reach + r and across <= half + r then
				return true
			end
		end
		return false
	end
	local G = Map.Garden
	u, v = x - G.x, z - G.z
	for _, box in G.paths do
		if u > box.u0 - r and u < box.u1 + r and v > box.v0 - r and v < box.v1 + r then
			return true
		end
	end
	return false
end

-- May a post `r` thick stand at (x, z): on a lawn, off the park's and the garden's paths, ponds and lanterns?
local function clear(x: number, z: number, r: number): boolean
	if not onLawn(x, z, r + 0.3) or FootbridgeShape.onPath(x, z, r) then
		return false
	end
	local P = Map.Park
	local u, v = x - P.x, z - P.z
	if math.abs(u) <= Map.BlockSize / 2 and math.abs(v) <= Map.BlockSize / 2 then
		return octagon(u, v) > P.pond + 1.5 + r -- (off the pond and its coping)
	end
	local G = Map.Garden
	u, v = x - G.x, z - G.z
	for _, disc in G.pond do
		if (u - disc.u) ^ 2 + (v - disc.v) ^ 2 < (disc.r + r) ^ 2 then
			return false
		end
	end
	for _, l in G.lanterns do
		if (u - l.u) ^ 2 + (v - l.v) ^ 2 < (1.7 + r) ^ 2 then
			return false
		end
	end
	return true
end
FootbridgeShape.clear = clear

-- ── The walking surface ─────────────────────────────────────────────────────

-- The line's points where the walking surface's boxes meet: each box as long as it may be (6 at most) while the turn
-- it covers keeps the step where it meets the next one under 0.05 across the walkway (the grade times the walkway's
-- half times the turn) and the line's height stays within 0.03 of its chord.
function FootbridgeShape.joints(): { number }
	local F = Map.Footbridge
	local line = F.line
	local function fits(i: number, j: number): boolean
		local a, b = line[i], line[j]
		if math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) > 6 then
			return false
		end
		local turn, steep = 0, 0
		for m = i, j - 1 do
			turn += math.abs(line[m].k) * (line[m + 1].s - line[m].s)
			steep = math.max(steep, math.abs(line[m].g))
		end
		if turn * (F.width / 2 + DECK_EDGE) * math.max(steep, 0.02) > 0.05 or turn > 0.2 then
			return false
		end
		for m = i + 1, j - 1 do
			local f = (line[m].s - a.s) / (b.s - a.s)
			if math.abs(line[m].y - (a.y + (b.y - a.y) * f)) > 0.03 then
				return false
			end
		end
		return true
	end
	local list = { 1 }
	local i = 1
	while i < #line do
		local j = i + 1
		while j < #line and fits(i, j + 1) do
			j += 1
		end
		table.insert(list, j)
		i = j
	end
	return list
end

-- How much longer than its chord a box ends at a joint where the line turns by `turn` (so its outer corner reaches
-- the next box's: no gap), and a hair more (the boxes overlap).
local function overlap(halfWidth: number, turn: number): number
	return halfWidth * math.tan(turn / 2) + 0.02
end
local function heading(a: Vec, b: Vec): number
	return math.atan2(b[3] - a[3], b[1] - a[1])
end
local function turnBetween(a: number, b: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return math.abs(d)
end

local function walkway(out: { Piece })
	local F = Map.Footbridge
	local line = F.line
	local joints = FootbridgeShape.joints()
	local centre: { Vec } = {}
	for _, i in joints do
		table.insert(centre, { line[i].x, line[i].y, line[i].z })
	end
	local half = F.width / 2 + DECK_EDGE
	for n = 1, #centre - 1 do
		local a, b = centre[n], centre[n + 1]
		local here = heading(a, b)
		local ea = if n > 1 then overlap(half, turnBetween(heading(centre[n - 1], a), here)) else 0
		local eb = if n + 1 < #centre then overlap(half, turnBetween(here, heading(b, centre[n + 2]))) else 0
		local a0, b0 = line[joints[n]], line[joints[n + 1]]
		local thick = if b0.s > F.street[1] and a0.s < F.street[2] then F.thick else SLAB
		beam(out, "Deck", a, b, 2 * half, thick, -thick / 2, ea, eb, PLANKS, "WoodPlanks", true, true)
	end
end

-- ── The railings ────────────────────────────────────────────────────────────

-- The line's points where the railings' pieces meet (their posts): 5 apart at most, a turn of 0.26 at most, the
-- line's height within 0.04 of the chord.
function FootbridgeShape.posts(): { number }
	local F = Map.Footbridge
	local line = F.line
	local gates: { [number]: boolean } = {} -- (a post at each gate: the span's girders start there)
	for _, s in F.gates do
		gates[math.floor(s / F.step + 0.5) + 1] = true
	end
	local list = { 1 }
	local i = 1
	while i < #line do
		local j = i + 1
		while j < #line and not gates[j] do
			local a, b = line[i], line[j + 1]
			local ok = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) <= 5
			local turn = 0
			for m = i, j do
				turn += math.abs(line[m].k) * (line[m + 1].s - line[m].s)
			end
			ok = ok and turn <= 0.26
			for m = i + 1, j do
				local f = (line[m].s - a.s) / (b.s - a.s)
				ok = ok and math.abs(line[m].y - (a.y + (b.y - a.y) * f)) <= 0.04
			end
			if not ok then
				break
			end
			j += 1
		end
		table.insert(list, j)
		i = j
	end
	return list
end

-- The chord along one edge from point i to point j of the line, `o` out from the centre line on `side` (1: left),
-- `h` over the walking surface: pushed out as far as needed for no point of it to come inside `o` where the edge
-- turns (the chord cuts the curve on a turn's outside).
local function edgeChord(i: number, j: number, side: number, o: number, h: number): (Vec, Vec)
	local line = Map.Footbridge.line
	local a, b = line[i], line[j]
	local function ends(off: number): (Vec, Vec)
		return { a.x + a.dz * side * off, a.y + h, a.z - a.dx * side * off }, { b.x + b.dz * side * off, b.y + h, b.z - b.dx * side * off }
	end
	local p, q = ends(o)
	local inside = 0
	for m = i + 1, j - 1 do
		local c = line[m]
		local f = (c.s - a.s) / (b.s - a.s)
		local px, pz = p[1] + (q[1] - p[1]) * f, p[3] + (q[3] - p[3]) * f
		local off = ((px - c.x) * c.dz - (pz - c.z) * c.dx) * side
		inside = math.max(inside, o - off)
	end
	if inside > 0 then
		p, q = ends(o + inside)
	end
	return p, q
end

local function railings(out: { Piece }, lanternAt: { [number]: number })
	local F = Map.Footbridge
	local line = F.line
	local posts = FootbridgeShape.posts()
	local inner = F.width / 2
	for n = 1, #posts - 1 do
		local i, j = posts[n], posts[n + 1]
		for _, side in { 1, -1 } do
			local a, b = edgeChord(i, j, side, inner + CLEAR + KICK_THICK / 2, 0)
			beam(out, "KickBoard", a, b, KICK_THICK, KICK + SLAB, (KICK - SLAB) / 2, 0.12, 0.12, VERMILION, "Wood", true)
			a, b = edgeChord(i, j, side, inner + CLEAR + RAIL_THICK / 2, F.rail - 0.15)
			beam(out, "Railing", a, b, RAIL_THICK, 0.3, 0, 0.15, 0.15, VERMILION, "Wood", true)
		end
	end
	-- the posts (a brass cap on every other one), a paper lantern on some
	for n, i in posts do
		local c = line[i]
		local f: Frame = { x = c.x, y = c.y, z = c.z, dx = c.dx, dz = c.dz }
		for _, side in { 1, -1 } do
			local height = F.rail + 0.3 + SLAB
			standing(out, "RailPost", f, side * (inner + CLEAR + POST / 2), height / 2 - SLAB, 0, { POST, height, POST }, VERMILION, "Wood", true)
			if lanternAt[n] == side then
				local top = F.rail + 0.3
				standing(out, "LanternArm", f, side * (inner + CLEAR + POST / 2 + 0.3), top + 0.1, 0, { 0.7, 0.18, 0.18 }, TIMBER, "Wood", false)
				paperLantern(out, point(f, side * (inner + CLEAR + 0.75), top + 0.95, 0), 0.95)
			elseif n % 2 == 1 then
				ball(out, "RailCap", point(f, side * (inner + CLEAR + POST / 2), F.rail + 0.3 + POST / 2, 0), POST, BRASS, "Metal")
			end
		end
	end
end

-- Which posts carry a paper lantern (and on which side): every fifth or so, the sides taking turns, none by a gate or
-- at a foot, and only where the lantern hangs over a lawn or high over the street.
local function lanternPosts(): { [number]: number }
	local F = Map.Footbridge
	local line = F.line
	local posts = FootbridgeShape.posts()
	local chosen: { [number]: number } = {}
	local side, last = 1, -math.huge
	for n, i in posts do
		local c = line[i]
		local nearGate = math.abs(c.s - F.gates[1]) < 4 or math.abs(c.s - F.gates[2]) < 4
		if c.s - last >= 13 and c.s > 3 and c.s < F.length - 3 and not nearGate then
			for _, try in { side, -side } do
				local o = try * (F.width / 2 + 1.3)
				local x, z = c.x + c.dz * o, c.z - c.dx * o
				if onLawn(x, z, 0.5) or c.y > F.deck - 1 then
					chosen[n], side, last = try, -try, c.s
					break
				end
			end
		end
	end
	return chosen
end

-- ── The span: its girders and ribs ──────────────────────────────────────────

-- The girders' underside at s (between the gates): the structure's at the span's ends (Map.Footbridge.thick under the
-- walking surface), deeper toward the middle as the hump rises (an arch on each outer face).
function FootbridgeShape.girderBottom(s: number): number
	local F = Map.Footbridge
	local _, y = Map.footbridgeAt(s)
	return y - F.thick - 0.55 * math.max(0, y - F.deck)
end

local function girders(out: { Piece })
	local F = Map.Footbridge
	local line = F.line
	local posts = FootbridgeShape.posts()
	local o = F.width / 2 + CLEAR + KICK_THICK + GIRDER / 2
	for n = 1, #posts - 1 do
		local i, j = posts[n], posts[n + 1]
		local a0, b0 = line[i], line[j]
		if a0.s >= F.gates[1] - 0.5 and b0.s <= F.gates[2] + 0.5 then
			for _, side in { 1, -1 } do
				local ba, bb = FootbridgeShape.girderBottom(a0.s), FootbridgeShape.girderBottom(b0.s)
				local a, b = edgeChord(i, j, side, o, 0)
				a[2], b[2] = ba, bb
				local h = math.max(a0.y - ba, b0.y - bb) - 0.04
				beam(out, "Girder", a, b, GIRDER, h, h / 2, 0.1, 0.1, TIMBER, "Wood", false)
				if n % 2 == 0 then
					local f: Frame = { x = a0.x, y = a0.y, z = a0.z, dx = a0.dx, dz = a0.dz }
					local depth = a0.y - ba
					standing(out, "Rib", f, side * (o + GIRDER / 2 + 0.06), -depth / 2 - 0.02, 0, { 0.12, depth - 0.1, 0.32 }, VERMILION, "Wood", false)
				end
			end
		end
	end
end

-- ── The gates ───────────────────────────────────────────────────────────────

-- A vermilion torii across the walkway at s, its posts on outriggers outside the railings: everything of it over the
-- walkway is higher than Map.Footbridge.headroom over the walking surface.
local function gate(out: { Piece }, s: number, lit: boolean)
	local F = Map.Footbridge
	local f = frameAt(s)
	local post = F.gatePost
	local function across(name: string, width: number, h: number, high: number, deep: number, color: Vec, material: string)
		standing(out, name, f, 0, h, 0, { width, high, deep }, color, material, false)
	end
	across("GateBeam", 2 * (post + 0.8), -0.3, 0.5, 0.9, TIMBER, "Wood") -- (the outriggers under the deck)
	for _, side in { 1, -1 } do
		upright(out, "GatePost", point(f, side * post, 6, 0), 13, 1, VERMILION, "Wood")
		upright(out, "GateSleeve", point(f, side * post, 0.3, 0), 1.6, 1.2, INK, "Wood")
	end
	across("GateTie", 2 * (post + 1.4), F.headroom + 1.05, 0.7, 0.55, VERMILION, "Wood") -- (nuki)
	across("GateStrut", 0.5, F.headroom + 1.85, 1, 0.4, VERMILION, "Wood")
	across("GatePlaque", 2, F.headroom + 1.85, 1.4, 0.2, INK, "Wood")
	across("GateBand", 2 * (post + 2.2), F.headroom + 2.6, 0.5, 0.9, VERMILION, "Wood") -- (shimaki)
	across("GateLintel", 2 * (post + 2.2), F.headroom + 3.15, 0.6, 1.3, INK, "Wood") -- (kasagi)
	for _, side in { 1, -1 } do
		-- its ends turned up (out along the lintel and a little up), and a paper lantern hanging under each end
		local reach = post + 2.2
		local tilt = math.rad(12)
		local c, sn = math.cos(tilt), math.sin(tilt)
		local lx, lz = f.dz * side, -f.dx * side -- (out on this side)
		local right = { c * lx, sn, c * lz }
		local up = { -sn * lx, c, -sn * lz }
		local back = { right[2] * up[3] - right[3] * up[2], right[3] * up[1] - right[1] * up[3], right[1] * up[2] - right[2] * up[1] }
		add(out, "GateLintelEnd", { 2.3, 0.6, 1.3 }, point(f, side * (reach + 1.1), F.headroom + 3.15 + 0.24, 0), right, up, back, INK, "Wood", false)
		local middle = F.headroom + 1.2 -- (the lantern's middle; it hangs outside the posts, never over the walkway)
		standing(out, "LanternCord", f, side * (reach - 0.6), middle + 1.16, 0, { 0.08, 0.5, 0.08 }, TIMBER, "Wood", false)
		paperLantern(out, point(f, side * (reach - 0.6), middle, 0), 1.3, if lit and side == 1 then 26 else nil)
	end
end

-- ── Under the ramps ─────────────────────────────────────────────────────────

-- Timber bents every 8.5 studs or so where the ramp is high enough to stand on posts, from each foot to its gate (moved
-- along a little, or left out, where a post would stand on a path).
local function bents(out: { Piece })
	local F = Map.Footbridge
	local feet = { { from = 0, way = 1, stop = F.gates[1] - 3 }, { from = F.length, way = -1, stop = F.length - F.gates[2] - 3 } }
	for _, foot in feet do
		local d = 7
		while d < foot.stop do
			local placed = false
			for _, shift in { 0, 1, -1, 2, -2, 3, -3 } do
				local s = foot.from + foot.way * (d + shift)
				local f = frameAt(s)
				local under = f.y - SLAB
				if under - Map.WalkTop >= 2.6 then
					local ok = true
					for _, side in { 1, -1 } do
						local p = point(f, side * 4.7, 0, 0)
						ok = ok and clear(p[1], p[3], 0.5)
					end
					for o = -4.5, 4.5, 0.5 do -- (and no path under its cap beam either)
						local p = point(f, o, 0, 0)
						ok = ok and clear(p[1], p[3], 0)
					end
					if ok then
						for _, side in { 1, -1 } do
							local height = under - Map.WalkTop
							standing(out, "Post", f, side * 4.7, -SLAB - height / 2, 0, { 0.7, height, 0.7 }, TIMBER, "Wood", false)
						end
						standing(out, "BentCap", f, 0, -SLAB - 0.22, 0, { 2 * (F.width / 2 + DECK_EDGE) + 0.3, 0.45, 0.7 }, TIMBER, "Wood", false)
						placed = true
						break
					end
				end
			end
			d += if placed then 8.5 else 2
		end
	end
end

-- ── The park's foot ─────────────────────────────────────────────────────────

-- A lantern post on the lawn beside the park's foot, toward the park's middle (the garden's foot has its stone
-- lantern): a real light.
local function footLantern(out: { Piece })
	local F = Map.Footbridge
	local foot = F.feet.park
	local ax, az = -foot.dz, foot.dx -- (across the way down)
	if ax * (Map.Park.x - foot.x) + az * (Map.Park.z - foot.z) < 0 then
		ax, az = -ax, -az
	end
	local reach = F.width / 2 + F.edge + 1.6
	local x, z = foot.x - foot.dx * 1.5 + ax * reach, foot.z - foot.dz * 1.5 + az * reach
	local w = Map.WalkTop
	add(out, "LanternPost", { 0.5, 6.4, 0.5 }, { x, w + 3.2, z }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, TIMBER, "Wood", false)
	local glass = add(out, "PostLantern", { 1, 1.3, 1 }, { x, w + 7.05, z }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, GLASS, "Glass", false)
	glass.glow = "glass"
	glass.light = 24
	add(out, "PostLanternRoof", { 1.6, 0.3, 1.6 }, { x, w + 7.85, z }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, TIMBER, "Wood", false)
end

-- ── Under the low ramps: a planted bed ──────────────────────────────────────

local SOIL = { 82, 62, 46 }
local BOX = { 46, 78, 46 } -- (the clipped hedges: the garden's hedge's green)
local LEAVES = { 58, 96, 52 }
local FLOWERS = { { 226, 64, 70 }, { 236, 132, 190 }, { 246, 244, 236 }, { 246, 206, 70 } }
local BED_GAP = 4.2 -- the most room left between a hedge's top and the ramp over it (nobody, 5.9 tall, gets in there)

-- The line's points where the bed's pieces meet: `most` studs apart at most, a turn of 0.3 at most.
local function bedJoints(from: number, to: number, most: number): { number }
	local F = Map.Footbridge
	local line = F.line
	local list = { from }
	local i = from
	while i < to do
		local j = i + 1
		while j < to do
			local a, b = line[i], line[j + 1]
			local turn = 0
			for m = i, j do
				turn += math.abs(line[m].k) * (line[m + 1].s - line[m].s)
			end
			if math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) > most or turn > 0.3 then
				break
			end
			j += 1
		end
		table.insert(list, j)
		i = j
	end
	return list
end

-- Where the ramps are lower than Map.Footbridge.low over the ground (Map.Footbridge.beds, from each foot), nobody walks
-- or rides under them: the ground under the walkway is a planted bed (soil, shrubs and flowers) closed by clipped
-- hedges along both edges and across its high end, each as tall as leaves at most BED_GAP between its top and the ramp
-- (and never touching it). The hedges are solid.
local function beds(out: { Piece })
	local F = Map.Footbridge
	local line = F.line
	local w = Map.WalkTop
	local half = F.width / 2 + DECK_EDGE
	local function headroom(i: number): number
		return line[i].y - SLAB - w
	end
	local function hedgeHeight(room: number): number
		return math.min(math.max(room - BED_GAP, 1.2), room - 0.12)
	end
	for _, bed in F.beds do
		local first = math.floor(bed[1] / F.step + 0.5) + 1
		local last = math.floor(bed[2] / F.step + 0.5) + 1
		-- (from where there is room under the ramp to the bed's high end)
		local lowEnd, highEnd = first, last
		if headroom(first) < headroom(last) then
			while lowEnd < last and headroom(lowEnd) < 0.5 do
				lowEnd += 1
			end
		else
			lowEnd, highEnd = last, first
			while lowEnd > first and headroom(lowEnd) < 0.5 do
				lowEnd -= 1
			end
		end
		local a0, a1 = math.min(lowEnd, highEnd), math.max(lowEnd, highEnd)
		-- the soil, chord by chord (overlapping where the line turns)
		local joints = bedJoints(a0, a1, 5)
		for n = 1, #joints - 1 do
			local a, b = line[joints[n]], line[joints[n + 1]]
			local turn = math.abs(math.atan2(a.dx * b.dz - a.dz * b.dx, a.dx * b.dx + a.dz * b.dz))
			local e = half * math.tan(turn / 2) + 0.05
			beam(out, "BedSoil", { a.x, w + 0.06, a.z }, { b.x, w + 0.06, b.z }, 2 * half, 0.12, -0.06, e, e, SOIL, "Ground", false)
		end
		-- the hedges along both edges, chord by chord (each level, under the lowest of the ramp over it)
		joints = bedJoints(a0, a1, 2.5)
		for n = 1, #joints - 1 do
			local i, j = joints[n], joints[n + 1]
			local room = math.min(headroom(i), headroom(j))
			local high = hedgeHeight(room)
			for _, side in { 1, -1 } do
				local a, b = edgeChord(i, j, side, F.width / 2 - 0.1, 0)
				a[2], b[2] = w, w
				beam(out, "BedHedge", a, b, 0.8, high, high / 2, 0.25, 0.25, BOX, "Grass", true)
			end
		end
		-- across its high end
		local top = line[highEnd]
		local f: Frame = { x = top.x, y = w, z = top.z, dx = top.dx, dz = top.dz }
		local endHigh = hedgeHeight(headroom(highEnd))
		standing(out, "BedHedge", f, 0, endHigh / 2, 0, { 2 * half - 0.2, endHigh, 0.8 }, BOX, "Grass", true)
		-- shrubs and flowers in it, the sides taking turns
		local side = 1
		for n = 2, #joints - 1, 2 do
			local c = line[joints[n]]
			local room = headroom(joints[n])
			if room > 1.4 then
				local size = math.min(2.2, room - 0.3)
				local g: Frame = { x = c.x, y = w, z = c.z, dx = c.dx, dz = c.dz }
				ball(out, "BedShrub", point(g, side * 2.4, size * 0.4, 0), size, LEAVES, "Grass")
				ball(out, "BedFlowers", point(g, -side * 1.4, 0.45, 0.6), 0.9, FLOWERS[n % #FLOWERS + 1], "SmoothPlastic")
				side = -side
			end
		end
	end
end

-- Every piece of the footbridge.
function FootbridgeShape.pieces(): { Piece }
	local F = Map.Footbridge
	local out: { Piece } = {}
	walkway(out)
	railings(out, lanternPosts())
	girders(out)
	gate(out, F.gates[1], true)
	gate(out, F.gates[2], true)
	bents(out)
	beds(out)
	footLantern(out)
	return out
end

return FootbridgeShape
