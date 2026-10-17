-- 7.1, the Hauptplatz and the footbridge (shared/Map.luau Map.Square, Map.Footbridge; 6.12.15's garden_test): the square
-- on Last Stop's old block (0, -1) north of the Central Park, in the safe zone, a landmark, nothing Japanese left; the
-- footbridge over Bone St mid-block, far from the junctions, their lights and crosswalks, no bus stop, street prop or
-- zip line by it; nothing of the square or the footbridge on the sidewalk band (the people's walk line) or on a road
-- below the clearance, nothing of the square under the ramps, every thing of it on its cobbles and apart.
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
local G, P, F = Map.Square, Map.Park, Map.Footbridge
local lawn = HALF - G.walk

-- ── The square on its block ────────────────────────────────────────────────

check("the square is Last Stop's old block (0, -1), north of the park across Bone St", Map.special("downtown", G.i, G.j) == "square" and G.i == 0 and G.j == -1
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
check("a landmark (the map, the GPS, the location tag): Hauptplatz, a place with the fountain's icon", landmark ~= nil and landmark.name == "Hauptplatz" and landmark.kind == "place"
	and landmark.icon == "⛲" and landmark.x == G.x and landmark.z == G.z)
local tag = nil
for _, t in LocationTags.build() do
	if t.id == G.id then
		tag = t
	end
end
check("its location tag: HAUPTPLATZ · SAFE ZONE", tag ~= nil and tag.sub == "SAFE ZONE")
check("the fountain is no pond (a solid rim, nobody swims or sinks)", G.fountain.rim >= 1 and not Map.inPond(G.x + G.fountain.u, Map.WalkTop, G.z + G.fountain.v))
-- 7.1 (the Alps, step 1: "only the Japanese part goes"): nothing Japanese left in its words
local words = string.lower(G.name .. " " .. G.gasthof.name .. " " .. (if landmark then landmark.description else ""))
local japanese = false
for _, word in { "japan", "torii", "lantern garden", "sakura", "cherry", "koi", "pagoda", "pavilion", "shrine", "zen", "bonsai" } do
	japanese = japanese or string.find(words, word, 1, true) ~= nil
end
check("nothing Japanese in its name, its Gasthof's or its line on the map's list", not japanese and not (landmark and string.find(landmark.icon, "🏮", 1, true)))

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
	and onLawn(F.feet.square.x, F.feet.square.z, half))
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
check("no bus stop under it, by it or by the square's kerb", stopsClear)
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
check("no zip line through it or on the square", zipsClear)
local docksClear = true
for _, dock in RentalDocks.docks() do
	if Map.footbridgeGap(dock.x, dock.z) < 8 or (math.abs(dock.x - G.x) <= HALF and math.abs(dock.z - G.z) <= HALF) then
		docksClear = false
	end
end
check("no rental dock under it or on the square", docksClear)
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
check("a hump: up all the way to the middle over the road, down all the way after it", rising and F.hump > 1 and math.abs(crest - F.deck - F.hump) < 1e-6)

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
check("timber railings all along both edges: a kick board and a hand rail just outside the walkway everywhere", railed)

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
check(`the walking space empty: nothing at all within the walkway up to {F.headroom} over it (the arch's timbers gone; the portals' beams and roofs above it, their posts outside the railings)`, #intruders == 0, #intruders)
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

local pf, gf = F.feet.park, F.feet.square
local _, footY = Map.footbridgeAt(0)
local _, squareY = Map.footbridgeAt(F.length)
check("both feet on the ground (Map.WalkTop)", math.abs(footY - Map.WalkTop) < 1e-6 and math.abs(squareY - Map.WalkTop) < 1e-6)
check("the park's foot comes down onto the park's east path (from the ring to the sidewalk), the way down onto it", pf.x - half > P.x + P.pond + 1.5 + P.ring and pf.x + half <= P.x + lawn
	and math.abs(math.abs(pf.z - P.z) - 2.5) <= 0.2 and pf.dz * (P.z - pf.z) > 0)
check("the square's half is the park's turned half round the middle (one design)", math.abs(gf.x - (2 * F.x - pf.x)) < 1e-6 and math.abs(gf.z - (2 * F.z - pf.z)) < 1e-6)
local reached = false
for _, box in G.paths do
	local u, v = gf.x - G.x, gf.z - G.z
	if u >= box.u0 - 0.1 and u <= box.u1 + 0.1 and math.abs(math.max(box.v0 - v, 0, v - box.v1)) <= 1 then
		reached = true
	end
end
check("the square's foot comes down onto its cobbles", reached)
local postsOk = true
for _, piece in pieces do
	if piece.name == "Post" then
		postsOk = postsOk and FootbridgeShape.clear(piece.at[1], piece.at[3], 0.35)
	end
end
check("the ramps' posts on the lawns, off every path, the pond, the square's cobbles, lamps, trees and planters", postsOk)
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

-- A thing of the square at (u, v) reaching r around: inside the lawn (off the sidewalk band), off the roads, clear of
-- the footbridge's ramps by `clear`.
local function placed(name: string, u: number, v: number, r: number, clear: number): boolean
	local x, z = G.x + u, G.z + v
	local ok = math.abs(u) + r <= lawn and math.abs(v) + r <= lawn and not Map.onRoad(x, z) and Map.footbridgeGap(x, z) >= r + clear
	if not ok then
		print(`  {name} at ({u}, {v}): lawn {lawn - math.max(math.abs(u), math.abs(v)) - r}, footbridge {Map.footbridgeGap(x, z) - r}`)
	end
	return ok
end
-- (u, v) on the cobbles with r of them around it (inside one of Map.Square.paths)
local function onCobbles(u: number, v: number, r: number): boolean
	for _, box in G.paths do
		if u - r >= box.u0 and u + r <= box.u1 and v - r >= box.v0 and v + r <= box.v1 then
			return true
		end
	end
	return false
end
local function inBox(u: number, v: number, list: { Map.SquareBox }): boolean
	for _, box in list do
		if u > box.u0 and u < box.u1 and v > box.v0 and v < box.v1 then
			return true
		end
	end
	return false
end
-- The cobbles and the green strip tile the lawn: every spot in one of them and never in both.
local tiled, overlap = true, false
for u = -lawn + 0.5, lawn - 0.5, 1 do
	for v = -lawn + 0.5, lawn - 0.5, 1 do
		local a, b = inBox(u, v, G.paths), inBox(u, v, G.greens)
		tiled = tiled and (a or b)
		overlap = overlap or (a and b)
	end
end
check("the cobbles and the green strip under the ramp tile the lawn (every spot one or the other, never both)", tiled and not overlap)
local underRamp = true
for _, p in F.line do
	local x, z = p.x - G.x, p.z - G.z
	if math.abs(x) < lawn - 0.5 and math.abs(z) < lawn - 0.5 and p.y - FootbridgeShape.Slab - Map.WalkTop < F.low and p.s < F.length - 3 and p.s > 3 then
		underRamp = underRamp and inBox(x, z, G.greens)
	end
end
check("the ramp's low part runs over the green strip only (its bed there), never over the cobbles", underRamp)

-- Every thing of the square: where it stands, how far it reaches (in plan) and whether it stands on the cobbles.
type Thing = { name: string, u: number, v: number, r: number, cobbles: boolean }
local things: { Thing } = {}
local Fo, M, Gh = G.fountain, G.maypole, G.gasthof
table.insert(things, { name = "the fountain", u = Fo.u, v = Fo.v, r = Fo.r + 0.8, cobbles = true })
table.insert(things, { name = "the maypole", u = M.u, v = M.v, r = 2.6, cobbles = true })
for _, t in G.tables do
	table.insert(things, { name = "a café table", u = t.u, v = t.v, r = 3.3, cobbles = true })
end
for _, b in G.benches do
	table.insert(things, { name = "a bench", u = b.u + b.du * 0.4, v = b.v + b.dv * 0.4, r = 3, cobbles = true })
end
for _, l in G.lamps do
	table.insert(things, { name = "a lamp", u = l.u, v = l.v, r = 0.9, cobbles = true })
end
for _, p in G.planters do
	table.insert(things, { name = "a planter", u = p.u, v = p.v, r = p.length / 2 + 0.2, cobbles = true })
end
for _, t in G.trees do
	table.insert(things, { name = "a linden", u = t.u, v = t.v, r = (t.size or 8) / 2, cobbles = true })
end
local ok = true
for _, t in things do
	ok = placed(t.name, t.u, t.v, t.r, 0.5) and (not t.cobbles or onCobbles(t.u, t.v, math.min(t.r, 1))) and ok
end
-- the signs by the lawn's edge: their board (6.4 wide, its posts 3.2 either side) along it, all of it on the lawn
for _, s in G.signs do
	local along = if s.nu ~= 0 then s.v else s.u
	local out = if s.nu ~= 0 then s.u else s.v
	ok = math.abs(along) + 3.6 <= lawn and math.abs(out) + 0.5 <= lawn and Map.footbridgeGap(G.x + s.u, G.z + s.v) > 6 and ok
	table.insert(things, { name = "a sign", u = s.u - s.nu * 0.3, v = s.v - s.nv * 0.3, r = 0.8, cobbles = false })
end
-- the Gasthof: its walls and its eaves on the cobbles inside the lawn, clear of the footbridge
local eave = 1.8
ok = Gh.u0 - eave >= -lawn and Gh.u1 + eave <= lawn and Gh.v0 - eave >= -lawn and Gh.v1 + eave <= lawn and onCobbles((Gh.u0 + Gh.u1) / 2, (Gh.v0 + Gh.v1) / 2, 0)
	and Map.footbridgeGap(G.x + (Gh.u0 + Gh.u1) / 2, G.z + Gh.v1) > 30 and ok
check("every thing of the square inside its lawn (off the sidewalk band and the roads), clear of the footbridge's ramps, on its cobbles", ok)
-- apart: no two of them reach into each other, and none into the Gasthof or its door's way out
local apart = true
local doorU = (Gh.u0 + Gh.u1) / 2
for n, a in things do
	for m = n + 1, #things do
		local b = things[m]
		if math.sqrt((a.u - b.u) ^ 2 + (a.v - b.v) ^ 2) < a.r + b.r - 0.6 then
			apart = false
			print(`  {a.name} at ({a.u}, {a.v}) and {b.name} at ({b.u}, {b.v}) too close`)
		end
	end
	local nu = math.clamp(a.u, Gh.u0 - eave, Gh.u1 + eave)
	local nv = math.clamp(a.v, Gh.v0 - eave, Gh.v1 + eave)
	if math.sqrt((a.u - nu) ^ 2 + (a.v - nv) ^ 2) < a.r - 0.6 and a.name ~= "a sign" then
		apart = false
		print(`  {a.name} at ({a.u}, {a.v}) under the Gasthof`)
	end
	if math.abs(a.u - doorU) < 2.6 + a.r and a.v - a.r < Gh.v1 + 8 and a.v + a.r > Gh.v1 then
		apart = false
		print(`  {a.name} at ({a.u}, {a.v}) in the Gasthof's door's way out`)
	end
end
check("apart: nothing reaches into anything else, the Gasthof or the way out of its door", apart)
-- the café tables in front of the Gasthof (its Schanigarten), the fountain in the open middle
local terrace = #G.tables >= 3
for _, t in G.tables do
	terrace = terrace and t.u > Gh.u0 and t.u < Gh.u1 and t.v - Gh.v1 >= 4 and t.v - Gh.v1 <= 10
end
check("the café tables under their umbrellas in front of the Gasthof (4 to 10 studs out from its front)", terrace)
-- a way in from every sidewalk: a spot on the lawn's edge on the cobbles, away from the ramp and the Gasthof
local entrances = 0
for _, side in { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } do
	local found = false
	for t = -lawn + 3, lawn - 3, 1 do
		local u, v = if side[1] ~= 0 then side[1] * (lawn - 0.5) else t, if side[2] ~= 0 then side[2] * (lawn - 0.5) else t
		local inGasthof = u > Gh.u0 - eave and u < Gh.u1 + eave and v > Gh.v0 - eave and v < Gh.v1 + eave
		if inBox(u, v, G.paths) and not inGasthof and Map.footbridgeGap(G.x + u, G.z + v) > 6 then
			found = true
		end
	end
	entrances += if found then 1 else 0
end
check("a way in onto the cobbles from every sidewalk (no hedge, no gate: an open square)", entrances == 4, entrances)
local lit = 0
for _, l in G.lamps do
	lit += if l.lit then 1 else 0
end
check("gas lamps all round, a few real lights among them (the light budget)", #G.lamps >= 4 and lit >= 2 and lit <= 4, lit)
check("a HAUPTPLATZ · SAFE ZONE board by every sidewalk, facing out", #G.signs == 4 and (function()
	for _, s in G.signs do
		if math.abs(s.nu) + math.abs(s.nv) ~= 1 or (s.u * s.nu + s.v * s.nv) < lawn - 2 then
			return false
		end
	end
	return true
end)())

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
