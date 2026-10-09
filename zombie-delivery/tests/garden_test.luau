-- 6.12.15, the Lantern Garden and the footbridge (shared/Map.luau Map.Garden, Map.Footbridge): the garden on Last Stop's
-- old block (0, -1) north of the Central Park, in the safe zone, a landmark; the footbridge over Bone St mid-block,
-- far from the junctions, their lights and crosswalks, no bus stop, street prop or zip line by it; nothing of the garden
-- or the footbridge on the sidewalk band (the people's walk line) or on a road below the clearance, nothing of the
-- garden under the ramps or in its paths.
-- 6.12.16, the footbridge wider, curved and clear to walk: every piece it is built of (shared/FootbridgeShape.luau) is
-- scanned. The walkway 10 wide between the railings, the railings all along both edges; nothing at all in the walking
-- space (the walkway up to 9 studs over it) but the walking surface; every turn 12 studs and wider on the centre line;
-- no steeper than the curb (14°) on the centre line and on a turn's inside edge; the walking surface continuous (no
-- gap, no step over 0.1); every piece over a sidewalk or the road the tallest vehicle + 3 over the walk; the feet on a
-- path in each park.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Map = require("./Map")
local CurbShape = require("./CurbShape")
local BusLines = require("./BusLines")
local Crossings = require("./Crossings")
local StreetProps = require("./StreetProps")
local ZipLines = require("./ZipLines")
local RentalDocks = require("./RentalDocks")
local LocationTags = require("./LocationTags")
local TrafficLanes = require("./TrafficLanes")
local FootbridgeShape = require("./FootbridgeShape")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local CELL, HALF = Map.Cell, Map.BlockSize / 2
local G, P, F = Map.Garden, Map.Park, Map.Footbridge
local lawn = HALF - G.walk

-- ── The garden on its block ────────────────────────────────────────────────

check("the garden is Last Stop's old block (0, -1), north of the park across Bone St", Map.special("downtown", G.i, G.j) == "garden" and G.i == 0 and G.j == -1
	and G.x == G.i * CELL and G.z == G.j * CELL and G.x == P.x and G.z == P.z - CELL)
local d, bi, bj = Map.blockAt(G.x, G.z)
check("its middle is on its block", d ~= nil and d.id == "downtown" and bi == G.i and bj == G.j)
local safe = true
for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
	safe = safe and Map.isSafe(G.x + c[1] * HALF, G.z + c[2] * HALF)
end
check("the whole block is in the safe zone", safe)
check("Last Stop's old building is gone (no Map.LastStop), the block's dice as before (no lots)", (Map :: any).LastStop == nil and #Map.lotsAt("downtown", G.i, G.j) == 0
	and not Map.wasOrdinary("downtown", G.i, G.j))
check("its sidewalk band as wide as the park's (the walk line and its detours)", G.walk == P.walk and G.walk >= TrafficLanes.SidewalkInset + TrafficLanes.Body)
check("its own dice", G.seed ~= P.seed and G.seed ~= Config.City.Seed)
local landmark: Map.Landmark? = nil
for _, l in Map.Landmarks do
	if l.id == G.id then
		landmark = l
	end
end
check("a landmark (the map, the GPS, the location tag): Lantern Garden, a place", landmark ~= nil and landmark.name == "Lantern Garden" and landmark.kind == "place"
	and landmark.x == G.x and landmark.z == G.z)
local tag = nil
for _, t in LocationTags.build() do
	if t.id == G.id then
		tag = t
	end
end
check("its location tag: LANTERN GARDEN · SAFE ZONE", tag ~= nil and tag.sub == "SAFE ZONE")
check("the pond is shallow (not deeper than a step: nobody swims or sinks in it)", G.water > 0 and G.water <= 0.6 and not Map.inPond(G.x + G.pond[1].u, Map.WalkTop, G.z + G.pond[1].v))

-- ── The footbridge over Bone St ────────────────────────────────────────────

local roadZ = (P.z + G.z) / 2
local half = F.width / 2 + F.edge -- (the structure's half width)
local CLEAR = Map.WalkTop + F.tallest + 3 -- (nothing lower than this over a sidewalk or a road)
check("the footbridge crosses the road between the two (Bone St): its middle over the road's centre line", Map.onRoad(F.x, F.z) and math.abs(F.z - roadZ) < 1e-6
	and math.abs(F.x - P.x) <= 10)
local function onLawn(x: number, z: number, margin: number): boolean
	for _, home in { P, G } do
		if math.abs(x - home.x) <= lawn - margin and math.abs(z - home.z) <= lawn - margin then
			return true
		end
	end
	return false
end
-- the part over the street: from the first point whose structure reaches off a lawn to the last
local spanX0, spanX1, streetOk = math.huge, -math.huge, true
for _, p in F.line do
	local off = false
	for _, o in { -half, half } do
		off = off or not onLawn(p.x + p.dz * o, p.z - p.dx * o, 0)
	end
	if off then
		spanX0, spanX1 = math.min(spanX0, p.x - half), math.max(spanX1, p.x + half)
		streetOk = streetOk and p.s >= F.street[1] - 1e-6 and p.s <= F.street[2] + 1e-6 and p.y >= F.deck - 1e-6
	end
end
local nearestCross = math.huge
for _, jx in { P.x - CELL / 2, P.x + CELL / 2 } do
	nearestCross = math.min(nearestCross, math.abs(jx - spanX0) - Map.RoadWidth / 2, math.abs(jx - spanX1) - Map.RoadWidth / 2)
end
print(string.format("  over the street from x %.1f to %.1f: %.1f studs from the cross streets' edges", spanX0, spanX1, nearestCross))
check("mid-block: over the street 30 studs and more from the cross streets' edges", nearestCross >= 30, nearestCross)
check("its ends on the lawns: only the span (between Map.Footbridge.street) reaches off them, at the deck's height and more", streetOk and onLawn(F.feet.park.x, F.feet.park.z, half)
	and onLawn(F.feet.garden.x, F.feet.garden.z, half))
local farFromCrossings = true
for _, c in Crossings.crosswalks() do
	if Map.footbridgeGap(c.x, c.z) < 25 then
		farFromCrossings = false
	end
end
for _, j in Crossings.junctions() do
	if Map.footbridgeGap(j.x, j.z) < 45 then
		farFromCrossings = false
	end
end
check("no crosswalk and no traffic light near it", farFromCrossings)
local stopsClear = true
for _, stop in BusLines.allStops() do
	if Map.footbridgeGap(stop.x, stop.z) < 25 or Map.footbridgeGap(stop.kx, stop.kz) < 25 then
		stopsClear = false
	end
	if (stop.kx > G.x - HALF and stop.kx < G.x + HALF and math.abs(stop.kz - G.z) <= HALF + 1) then
		stopsClear = false
	end
end
check("no bus stop under it, by it or by the garden's kerb", stopsClear)
local propsClear = true
for _, block in StreetProps.blocks() do
	for _, prop in block.props do
		if Map.footbridgeGap(prop.x, prop.z) < 12 then
			propsClear = false
		end
	end
end
check("no street prop under it or by it", propsClear)

-- every piece of it (shared/FootbridgeShape.luau: server/Footbridge.luau builds exactly these), its box in the world
local pieces = FootbridgeShape.pieces()
type Box = { piece: FootbridgeShape.Piece, lo: { number }, hi: { number } }
local boxes: { Box } = {}
local topOfAll = -math.huge
for _, piece in pieces do
	local lo, hi = {}, {}
	for axis = 1, 3 do
		local reach = math.abs(piece.right[axis]) * piece.size[1] / 2 + math.abs(piece.up[axis]) * piece.size[2] / 2 + math.abs(piece.back[axis]) * piece.size[3] / 2
		lo[axis], hi[axis] = piece.at[axis] - reach, piece.at[axis] + reach
	end
	table.insert(boxes, { piece = piece, lo = lo, hi = hi })
	topOfAll = math.max(topOfAll, hi[2])
end
local zipsClear = true
for _, line in ZipLines.lines() do
	for k = 0, 60 do
		local x, y, z = ZipLines.cable(line, k / 60)
		if Map.footbridgeGap(x, z) < 6 and y < topOfAll + 6 then
			zipsClear = false
		end
	end
	for _, lot in { line.start, line.finish } do
		if lot.i == G.i and lot.j == G.j then
			zipsClear = false
		end
	end
end
check("no zip line through it or on the garden", zipsClear)
local docksClear = true
for _, dock in RentalDocks.docks() do
	if Map.footbridgeGap(dock.x, dock.z) < 8 or (math.abs(dock.x - G.x) <= HALF and math.abs(dock.z - G.z) <= HALF) then
		docksClear = false
	end
end
check("no rental dock under it or on the garden", docksClear)
local solidOk, lights = true, 0
local SOLID = { Deck = true, KickBoard = true, Railing = true, RailPost = true, BedHedge = true } -- (and the hedges round the beds under the low ramps)
for _, piece in pieces do
	solidOk = solidOk and (piece.solid == (SOLID[piece.name] == true)) and (piece.walk == (piece.name == "Deck"))
	lights += if piece.light then 1 else 0
end
print(`  {#pieces} pieces, {lights} lights`)
check("solid: the walking surface, the railings and the hedges under the low ramps only (the rest is decoration); a few real lights (the light budget)", solidOk and lights >= 2 and lights <= 4, lights)

-- ── Clearance ──────────────────────────────────────────────────────────────

local lowestOver, lowestPiece = math.huge, ""
local lawnsOk = true
for _, box in boxes do
	local inside = false
	for _, home in { P, G } do
		if box.lo[1] >= home.x - lawn and box.hi[1] <= home.x + lawn and box.lo[3] >= home.z - lawn and box.hi[3] <= home.z + lawn then
			inside = true
		end
	end
	if not inside then
		if box.lo[2] < lowestOver then
			lowestOver, lowestPiece = box.lo[2], box.piece.name
		end
		lawnsOk = lawnsOk and box.lo[2] >= CLEAR
	end
end
print(string.format("  the lowest over a sidewalk or the road: %.2f (%s); the deck there %.2f, %.2f under it; the tallest vehicle %.1f", lowestOver, lowestPiece, F.deck, F.thick, F.tallest))
check("the tallest vehicle: the Box Truck with the Roof Launcher, 12.6 (the whole fleet: tools/vehicle-preview/check_fleet.py)", F.tallest >= 12.6)
check("over the road and the sidewalks (a vehicle drives up the curb): every piece the tallest vehicle + 3 and more over the walk", lawnsOk and lowestOver >= CLEAR
	and F.deck - F.thick - Map.WalkTop >= F.tallest + 3 and F.thick >= FootbridgeShape.Slab - 1e-9, lowestOver - Map.WalkTop)
local rising = true
for i = 2, #F.line do
	local a, b = F.line[i - 1], F.line[i]
	rising = rising and (if b.s <= F.middle + 1e-6 then b.y >= a.y - 1e-9 else b.y <= a.y + 1e-9)
end
local _, crest = Map.footbridgeAt(F.middle)
print(string.format("  the walking surface: %.2f at the street's edges, %.2f in the middle (a hump of %.2f)", F.deck, crest, F.hump))
check("a taiko-bridge hump: up all the way to the middle over the road, down all the way after it", rising and F.hump > 1 and math.abs(crest - F.deck - F.hump) < 1e-6)

-- ── The walkway: wide, curved, not too steep ───────────────────────────────

check("a walkway 10 studs wide and more between the railings (two people side by side, and a scooter)", F.width >= 10)
-- the railings run all along both edges, their inner faces on the walkway's edge: a point just outside the edge is in a
-- kick board (half a stud up) and in a hand rail (at its height) everywhere
local function inside(piece: FootbridgeShape.Piece, x: number, y: number, z: number, grow: number): boolean
	local vx, vy, vz = x - piece.at[1], y - piece.at[2], z - piece.at[3]
	for axis, v in { piece.right, piece.up, piece.back } do
		if math.abs(vx * v[1] + vy * v[2] + vz * v[3]) > piece.size[axis] / 2 + grow then
			return false
		end
	end
	return true
end
local nearPieces: { [number]: { FootbridgeShape.Piece } } = {} -- (by the line's points, every piece reaching within 7 of one)
for _, box in boxes do
	for i, p in F.line do
		if p.x >= box.lo[1] - 7 and p.x <= box.hi[1] + 7 and p.z >= box.lo[3] - 7 and p.z <= box.hi[3] + 7 then
			nearPieces[i] = nearPieces[i] or {}
			table.insert(nearPieces[i], box.piece)
		end
	end
end
local railed = true
for i = 3, #F.line - 2, 2 do
	local p = F.line[i]
	for _, side in { 1, -1 } do
		for _, want in { { name = "KickBoard", o = F.width / 2 + 0.2, h = 0.5 }, { name = "Railing", o = F.width / 2 + 0.2, h = F.rail - 0.15 } } do
			local x, z = p.x + p.dz * side * want.o, p.z - p.dx * side * want.o
			local found = false
			for _, piece in nearPieces[i] or {} do
				found = found or (piece.name == want.name and inside(piece, x, p.y + want.h, z, 0))
			end
			railed = railed and found
		end
	end
end
check("vermilion railings all along both edges: a kick board and a hand rail just outside the walkway everywhere", railed)

-- Nothing at all in the walking space: from the walking surface up to Map.Footbridge.headroom over it, across the whole
-- walkway, no piece (decorative or not) but the walking surface itself; every piece sampled through its box.
local intruders: { string } = {}
local function nearest(x: number, z: number, from: number, to: number): number
	local best, at = math.huge, from
	for i = math.max(1, from), math.min(#F.line, to) do
		local p = F.line[i]
		local d = (p.x - x) ^ 2 + (p.z - z) ^ 2
		if d < best then
			best, at = d, i
		end
	end
	return at
end
for _, box in boxes do
	local piece = box.piece
	if not piece.walk then
		local centre = nearest(piece.at[1], piece.at[3], 1, #F.line)
		local reach = math.ceil((math.sqrt(piece.size[1] ^ 2 + piece.size[2] ^ 2 + piece.size[3] ^ 2) / 2 + 8) / F.step)
		local n = {}
		for axis = 1, 3 do
			n[axis] = math.max(1, math.ceil(piece.size[axis] / 0.2))
		end
		local hit = false
		for a = 0, n[1] do
			for b = 0, n[2] do
				for c = 0, n[3] do
					if hit then
						break
					end
					local u, v, w = (a / n[1] - 0.5) * piece.size[1], (b / n[2] - 0.5) * piece.size[2], (c / n[3] - 0.5) * piece.size[3]
					-- (a ball's or a cylinder's points only: inside it, not its box's corners)
					local round = if piece.shape == "Ball" then (u / piece.size[1]) ^ 2 + (v / piece.size[2]) ^ 2 + (w / piece.size[3]) ^ 2
						elseif piece.shape == "Cylinder" then (v / piece.size[2]) ^ 2 + (w / piece.size[3]) ^ 2
						else 0
					if round > 0.25 + 1e-9 then
						continue
					end
					local x = piece.at[1] + piece.right[1] * u + piece.up[1] * v + piece.back[1] * w
					local y = piece.at[2] + piece.right[2] * u + piece.up[2] * v + piece.back[2] * w
					local z = piece.at[3] + piece.right[3] * u + piece.up[3] * v + piece.back[3] * w
					local i = nearest(x, z, centre - reach, centre + reach)
					local p = F.line[i]
					local along = (x - p.x) * p.dx + (z - p.z) * p.dz
					local o = (x - p.x) * p.dz - (z - p.z) * p.dx
					local _, surface = Map.footbridgeAt(p.s + along)
					if math.abs(o) < F.width / 2 - 0.03 and y > surface + 0.12 and y < surface + F.headroom and p.s + along > 0 and p.s + along < F.length then
						hit = true
					end
				end
			end
		end
		if hit then
			table.insert(intruders, `{piece.name} at ({math.floor(piece.at[1] * 10) / 10}, {math.floor(piece.at[2] * 10) / 10}, {math.floor(piece.at[3] * 10) / 10})`)
		end
	end
end
if #intruders > 0 then
	print("  in the walkway: " .. table.concat(intruders, "; ", 1, math.min(#intruders, 8)))
end
check(`the walking space empty: nothing at all within the walkway up to {F.headroom} over it (the arch's timbers gone; the gates' beams above it, their posts outside the railings)`, #intruders == 0, #intruders)
local gateOk = true
for _, s in F.gates do
	gateOk = gateOk and (math.abs(s - F.street[1]) < 1e-6 or math.abs(s - F.street[2]) < 1e-6)
end
check("a gate at each end of the span, its posts outside the railings", #F.gates == 2 and gateOk and F.gatePost - 0.5 > F.width / 2 + F.edge)

-- The turns: every one 12 studs and wider on the centre line (a bike or a scooter rounds it), measured from the line too.
local widest, tightest = 0, math.huge
for _, piece in F.plan do
	if piece.kind == "arc" then
		tightest = math.min(tightest, piece.radius)
	end
end
local measured = math.huge
for i = 9, #F.line - 8, 4 do
	local a, b = F.line[i - 8], F.line[i + 8]
	local turn = math.abs(math.atan2(a.dx * b.dz - a.dz * b.dx, a.dx * b.dx + a.dz * b.dz))
	if turn > 1e-6 then
		measured = math.min(measured, (b.s - a.s) / turn)
	end
	widest = math.max(widest, math.abs(F.line[i].k))
end
print(string.format("  the tightest turn: %.1f on the centre line (measured %.1f); %d turns", tightest, measured, #F.plan // 2))
check("it curves: every turn 12 studs and wider on the centre line, a soft S over the street", tightest >= 12 and measured >= 12 - 0.05 and widest <= 1 / 12 + 1e-9 and F.radius >= 12)

-- The slopes: as steep as the curb at most (14°), on the centre line and on the inside edge of the turns too; the
-- walking surface's boxes too.
local steepest, steepestInside = 0, 0
for _, p in F.line do
	steepest = math.max(steepest, math.abs(p.g))
	steepestInside = math.max(steepestInside, math.abs(p.g) / (1 - math.abs(p.k) * F.width / 2))
end
local steepestPiece = 0
for _, piece in pieces do
	if piece.walk then
		steepestPiece = math.max(steepestPiece, math.abs(piece.back[2]) / math.sqrt(piece.back[1] ^ 2 + piece.back[3] ^ 2))
	end
end
print(string.format("  the slopes: %.1f° on the centre line, %.1f° on a turn's inside edge, %.1f° the steepest plank; the curb's %.1f°", math.deg(math.atan(steepest)),
	math.deg(math.atan(steepestInside)), math.deg(math.atan(steepestPiece)), math.deg(CurbShape.Angle)))
check("no steeper than the curb anywhere on the walkway (every person walks up it, every bike and scooter rides it)", steepest > 0.1 and steepest <= CurbShape.Slope + 1e-9
	and steepestInside <= CurbShape.Slope + 1e-6 and steepestPiece <= CurbShape.Slope + 1e-3 and math.deg(math.atan(steepestInside)) <= 14.05)

-- Continuity: the walking surface under every spot of the walkway (a ray down through the solid planks), every 0.05
-- along it, across it every half stud: never missing, never off the line's height by more than 0.1, and no step over 0.1
-- between two spots side by side (a Humanoid does not trip, a wheel rolls on).
local walkNear: { [number]: { FootbridgeShape.Piece } } = {}
for i, list in nearPieces do
	walkNear[i] = {}
	for _, piece in list do
		if piece.walk then
			table.insert(walkNear[i], piece)
		end
	end
end
local function topAt(x: number, z: number, below: number, i: number): number?
	local best: number? = nil
	for _, piece in walkNear[i] or {} do
		-- a ray down: where it meets the box's top face (its up axis' +half plane), if inside the box
		local up = piece.up
		if math.abs(up[2]) > 1e-6 then
			local h = piece.size[2] / 2
			local y = piece.at[2] + (h - (x - piece.at[1]) * up[1] - (z - piece.at[3]) * up[3]) / up[2]
			if y <= below and inside(piece, x, y, z, 1e-6) and (best == nil or y > (best :: number)) then
				best = y
			end
		end
	end
	return best
end
local missing, worstOff, worstStep, rays = 0, 0, 0, 0
local across = {}
for k = 0, 20 do
	table.insert(across, -F.width / 2 + 0.05 + k * (F.width - 0.1) / 20)
end
local previous: { number? } = {}
local s = 0
while s <= F.length do
	local x, y, z, dx, dz = Map.footbridgeAt(s)
	local i = math.clamp(math.floor(s / F.step + 0.5) + 1, 1, #F.line)
	local row: { number? } = {}
	for k, o in across do
		local top = topAt(x + dz * o, z - dx * o, y + 0.5, i)
		rays += 1
		row[k] = top
		if top == nil then
			missing += 1
		else
			worstOff = math.max(worstOff, math.abs(top - y))
			local before = previous[k]
			if before then
				worstStep = math.max(worstStep, math.abs(top - before))
			end
			local side = row[k - 1]
			if side then
				worstStep = math.max(worstStep, math.abs(top - side))
			end
		end
	end
	previous = row
	s += 0.05
end
print(string.format("  the walking surface: %d spots, %d missing, %.3f off the line at most, the biggest step %.3f", rays, missing, worstOff, worstStep))
check("continuous: no gap, no bump, no step over 0.1 between the planks (the joins overlap: solid)", missing == 0 and worstOff <= 0.1 and worstStep <= 0.1, worstStep)

-- ── The ramps' feet ─────────────────────────────────────────────────────────

local pf, gf = F.feet.park, F.feet.garden
local _, footY = Map.footbridgeAt(0)
local _, gardenY = Map.footbridgeAt(F.length)
check("both feet on the ground (Map.WalkTop)", math.abs(footY - Map.WalkTop) < 1e-6 and math.abs(gardenY - Map.WalkTop) < 1e-6)
check("the park's foot comes down onto the park's east path (from the ring to the sidewalk), the way down onto it", pf.x - half > P.x + P.pond + 1.5 + P.ring and pf.x + half <= P.x + lawn
	and math.abs(math.abs(pf.z - P.z) - 2.5) <= 0.2 and pf.dz * (P.z - pf.z) > 0)
check("the garden's half is the park's turned half round the middle (one design)", math.abs(gf.x - (2 * F.x - pf.x)) < 1e-6 and math.abs(gf.z - (2 * F.z - pf.z)) < 1e-6)
local reached = false
for _, box in G.paths do
	local u, v = gf.x - G.x, gf.z - G.z
	if u >= box.u0 - 0.1 and u <= box.u1 + 0.1 and math.abs(math.max(box.v0 - v, 0, v - box.v1)) <= 1 then
		reached = true
	end
end
check("the garden's foot comes down onto a path", reached)
local postsOk = true
for _, piece in pieces do
	if piece.name == "Post" then
		postsOk = postsOk and FootbridgeShape.clear(piece.at[1], piece.at[3], 0.35)
	end
end
check("the ramps' posts on the lawns, off every path, pond and lantern", postsOk)
-- Under the walkway where the ramp is lower than Map.Footbridge.low (9) over the ground: no path and no open ground. A
-- path runs under it only where it is higher (the park's north path under its north run); the park's path to its
-- north-east corner ends before the ramp's turn there. The low ground is a planted bed, closed by solid clipped hedges
-- along both edges and across its high end, whose tops leave too little room under the ramp for anyone (5.9 tall).
local overPath, pathsLow, uncovered, unsealed, bedLength = math.huge, 0, 0, 0, 0
local function hedgeAt(i: number, x: number, y: number, z: number): FootbridgeShape.Piece?
	for _, piece in nearPieces[i] or {} do
		if piece.name == "BedHedge" and piece.solid and inside(piece, x, y, z, 0.05) then
			return piece
		end
	end
	return nil
end
for i, p in F.line do
	local room = p.y - FootbridgeShape.Slab - Map.WalkTop
	for o = -half + 0.1, half - 0.1, 0.5 do
		local x, z = p.x + p.dz * o, p.z - p.dx * o
		if onLawn(x, z, 0) and FootbridgeShape.onPath(x, z, 0) and p.s > 3 and p.s < F.length - 3 then
			overPath = math.min(overPath, room)
			pathsLow += if room < F.low then 1 else 0
		end
		if room > 0.5 and room < F.low and math.abs(o) < F.width / 2 - 0.5 then
			local soil = false
			for _, piece in nearPieces[i] or {} do
				soil = soil or (piece.name == "BedSoil" and inside(piece, x, Map.WalkTop + 0.03, z, 0))
			end
			uncovered += if soil then 0 else 1
		end
	end
	if room > 0.5 and room < F.low then
		bedLength += F.step
		for _, side in { 1, -1 } do
			local o = side * (F.width / 2 - 0.1)
			local x, z = p.x + p.dz * o, p.z - p.dx * o
			local hedge = hedgeAt(i, x, Map.WalkTop + 0.15, z)
			local top = if hedge then hedge.at[2] + hedge.size[2] / 2 else -math.huge
			if not hedge or p.y - FootbridgeShape.Slab - top > 5 or top >= p.y - FootbridgeShape.Slab then
				unsealed += 1
			end
		end
	end
end
-- each bed closed at its high end: a hedge across the walkway there
for _, bed in F.beds do
	local high = if bed[1] < F.middle and bed[2] < F.middle then bed[2] else bed[1]
	local x, y, z = Map.footbridgeAt(high)
	local i = math.floor(high / F.step + 0.5) + 1
	for _, o in { -3, 0, 3 } do
		local _, _, _, dx, dz = Map.footbridgeAt(high)
		local hedge = hedgeAt(i, x + dz * o, Map.WalkTop + 1, z - dx * o)
		if not hedge or (y - FootbridgeShape.Slab) - (hedge.at[2] + hedge.size[2] / 2) > 5 then
			unsealed += 1
		end
	end
end
print(string.format("  under the low ramps (lower than %d): %.1f studs of planted bed; where a path runs under a ramp it is %.1f over it", F.low, bedLength, overPath))
check(`no path and no open ground under the walkway where it is lower than {F.low} over the ground: a planted bed, closed by hedges (nobody gets under it)`,
	pathsLow == 0 and overPath >= F.low and uncovered == 0 and unsealed == 0 and bedLength > 60 and Map.Park.corners[4] < Map.Park.corners[1] - 5,
	`{pathsLow} path spots, {uncovered} bare, {unsealed} open`)

-- ── Nothing in the way ─────────────────────────────────────────────────────

-- A thing of the garden at (u, v) reaching r around: inside the lawn (off the sidewalk band), off the roads, clear of
-- the footbridge's ramps by `clear`.
local function placed(name: string, u: number, v: number, r: number, clear: number): boolean
	local x, z = G.x + u, G.z + v
	local ok = math.abs(u) + r <= lawn and math.abs(v) + r <= lawn and not Map.onRoad(x, z) and Map.footbridgeGap(x, z) >= r + clear
	if not ok then
		print(`  {name} at ({u}, {v}): lawn {lawn - math.max(math.abs(u), math.abs(v)) - r}, footbridge {Map.footbridgeGap(x, z) - r}`)
	end
	return ok
end
local function onPath(u: number, v: number, r: number): boolean
	for _, box in G.paths do
		if u + r > box.u0 and u - r < box.u1 and v + r > box.v0 and v - r < box.v1 then
			return true
		end
	end
	return false
end
local function inPond(u: number, v: number, r: number): boolean
	for _, disc in G.pond do
		if math.sqrt((u - disc.u) ^ 2 + (v - disc.v) ^ 2) < disc.r + r then
			return true
		end
	end
	return false
end
local ok = true
for _, disc in G.pond do
	ok = placed("the pond", disc.u, disc.v, disc.r + 1.6, 1) and ok
end
ok = placed("the waterfall", G.waterfall.u, G.waterfall.v - 2.6, 4.2, 1) and ok
ok = placed("the pavilion", G.pavilion.u, G.pavilion.v, G.pavilion.size / 2 + 2, 1) and ok
local R = G.gravel
for _, corner in { { R.u0, R.v0 }, { R.u1, R.v0 }, { R.u0, R.v1 }, { R.u1, R.v1 } } do
	ok = placed("the raked gravel", corner[1], corner[2], 0.4, 1) and ok
end
for _, stone in G.rocks do
	local reach = (stone.size or 2) * 1.3 -- (its outer raked ring)
	ok = stone.u - reach >= R.u0 and stone.u + reach <= R.u1 and stone.v - reach >= R.v0 and stone.v + reach <= R.v1 and ok
end
for _, l in G.lanterns do
	ok = placed("a lantern", l.u, l.v, 1.7, 0.5) and not onPath(l.u, l.v, 1.1) and not inPond(l.u, l.v, 2) and ok
end
for _, c in G.cherries do
	ok = placed("a cherry tree", c.u, c.v, 5.5, 0) and not onPath(c.u, c.v, 0.6) and not inPond(c.u, c.v, 1.5) and ok
end
for _, b in G.bamboo do
	ok = placed("a bamboo clump", b.u, b.v, 2, 0.5) and not onPath(b.u, b.v, 2) and ok
end
for _, s in G.shrubs do
	ok = placed("an azalea", s.u, s.v, (s.size or 2.4) / 2, 0.5) and not onPath(s.u, s.v, (s.size or 2.4) / 2) and not inPond(s.u, s.v, 1) and ok
end
for _, b in G.benches do
	ok = placed("a bench", b.u, b.v, 3, 0.5) and not onPath(b.u, b.v, 1) and not inPond(b.u, b.v, 2) and ok
end
ok = placed("the wash basin", G.basin.u, G.basin.v, 1.6, 0.5) and not onPath(G.basin.u, G.basin.v, 1) and ok
for _, box in G.paths do
	ok = math.max(math.abs(box.u0), math.abs(box.u1), math.abs(box.v0), math.abs(box.v1)) <= lawn and ok
end
check("everything of the garden inside its lawn (off the sidewalk band and the roads), clear of the footbridge's ramps, off its paths and out of its pond", ok)
local gatesOk = #G.gates == 4
for _, gate in G.gates do
	local onLine = math.abs(math.abs(if gate.nu ~= 0 then gate.u else gate.v) - (lawn - G.hedge)) < 1e-6 and (if gate.nu ~= 0 then gate.u * gate.nu else gate.v * gate.nv) > 0
	local reachedGate = false
	for _, box in G.paths do
		if gate.u >= box.u0 - 0.1 and gate.u <= box.u1 + 0.1 and gate.v >= box.v0 - 0.1 and gate.v <= box.v1 + 0.1 then
			reachedGate = true
		end
	end
	gatesOk = gatesOk and onLine and reachedGate and Map.footbridgeGap(G.x + gate.u, G.z + gate.v) > 6
end
check("a gate on each side (on the hedge's line, a path to it, away from the ramp): entrances from every sidewalk", gatesOk)
check("the hedge inside the lawn", G.hedge >= 0.6 and lawn - G.hedge + 0.6 <= lawn)
local lit = 0
for _, l in G.lanterns do
	lit += if l.lit then 1 else 0
end
check("stone lanterns all round, a few real lights among them (the light budget)", #G.lanterns >= 8 and lit >= 2 and lit <= 4, lit)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
