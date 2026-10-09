-- 6.12.15, the Lantern Garden and the footbridge (shared/Map.luau Map.Garden, Map.Footbridge): the garden on Last Stop's
-- old block (0, -1) north of the Central Park, in the safe zone, a landmark; the footbridge over Bone St mid-block,
-- far from the junctions, their lights and crosswalks, no bus stop, street prop or zip line by it; its beams at least
-- the tallest vehicle + 3 over the street and the sidewalks; its ramps no steeper than the curb (every person walks up
-- it, every bike and scooter rides it), their landings flat and joined; nothing of the garden or the footbridge on
-- the sidewalk band (the people's walk line) or on a road, nothing of the garden under the ramps or in its paths.
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
check("the footbridge crosses the road between the two (Bone St)", Map.onRoad(F.x, roadZ) and F.z0 < roadZ and F.z1 > roadZ)
check("it spans both sidewalks and the road: its ends inside the lawns", F.z0 <= G.z + lawn and F.z1 >= P.z - lawn and F.z0 > G.z + lawn - 2 and F.z1 < P.z - lawn + 2)
local outer = F.width / 2 + F.beam + 1.2 -- (the arches over its beams)
local nearestCross = math.huge
for _, jx in { P.x - CELL / 2, P.x + CELL / 2 } do
	nearestCross = math.min(nearestCross, math.abs(F.x - jx) - Map.RoadWidth / 2 - outer)
end
check("mid-block: 40 studs and more from the cross streets' edges", math.abs(F.x - P.x) <= 10 and nearestCross >= 40, nearestCross)
local farFromCrossings = true
for _, c in Crossings.crosswalks() do
	if math.abs(c.x - F.x) < 40 and math.abs(c.z - roadZ) < 40 then
		farFromCrossings = false
	end
end
for _, j in Crossings.junctions() do
	if math.abs(j.x - F.x) < 60 and math.abs(j.z - roadZ) < 20 then
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
local zipsClear = true
local archTop = F.deck + F.camber + F.arch + 1
for _, line in ZipLines.lines() do
	for k = 0, 60 do
		local x, y, z = ZipLines.cable(line, k / 60)
		if Map.footbridgeGap(x, z) < 6 and y < archTop + 6 then
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

-- ── Clearance ──────────────────────────────────────────────────────────────

local under = F.deck - F.thick -- the beams' underside at the span's ends (the camber only lifts it)
local lowest = math.huge
for k = 0, 100 do
	local z = F.z0 + (F.z1 - F.z0) * k / 100
	lowest = math.min(lowest, Map.footbridgeDeck(z) - F.thick)
end
print(string.format("  the beams' underside: %.2f at the ends, %.2f in the middle; the tallest vehicle %.1f", under, Map.footbridgeDeck(roadZ) - F.thick, F.tallest))
check("the camber lifts the middle (an arched bridge) and nowhere lowers the deck", lowest >= under - 1e-9 and Map.footbridgeDeck(roadZ) >= F.deck + F.camber - 1e-9 and F.camber > 0)
check("the tallest vehicle: the Box Truck with the Roof Launcher, 12.6 (the whole fleet: tools/vehicle-preview/check_fleet.py)", F.tallest >= 12.6)
check("over the road: the tallest vehicle + 3 and more", lowest - Map.RoadTop >= F.tallest + 3, lowest - Map.RoadTop)
check("over the sidewalks too (a vehicle drives up the curb): the tallest + 3 and more", lowest - Map.WalkTop >= F.tallest + 3, lowest - Map.WalkTop)
check("and a person walks under its landings on the lawn", under - Map.WalkTop > 8)

-- ── The ramps ──────────────────────────────────────────────────────────────

local function inLawn(x0: number, z0: number, x1: number, z1: number, cx: number, cz: number): boolean
	return x0 >= cx - lawn and x1 <= cx + lawn and z0 >= cz - lawn and z1 <= cz + lawn
end
for name, ramp in F.ramps do
	local home = if name == "park" then P else G
	local first = ramp[1]
	check(`{name}: its first landing at the span's end, at the deck's height`, first.kind == "landing" and first.ya == F.deck and first.yb == F.deck
		and math.abs((first.ax + first.bx) / 2 - F.x) < 1e-6 and (math.abs(first.az - F.z1) < 1e-6 or math.abs(first.az - F.z0) < 1e-6))
	local steepest, joined, inside, wide = 0, true, true, true
	for n, piece in ramp do
		local run = math.sqrt((piece.bx - piece.ax) ^ 2 + (piece.bz - piece.az) ^ 2)
		local axisAligned = math.abs(piece.ax - piece.bx) < 1e-6 or math.abs(piece.az - piece.bz) < 1e-6
		if piece.kind == "ramp" then
			steepest = math.max(steepest, math.abs(piece.ya - piece.yb) / run)
			wide = wide and piece.width >= 5
		else
			joined = joined and piece.ya == piece.yb and run >= 6.5 and piece.width >= 6.5
		end
		-- its band in plan (a flight's beams outside its walkway) inside its park's lawn
		local half = piece.width / 2 + (if piece.kind == "ramp" then F.beam else 0)
		local x0 = if axisAligned and math.abs(piece.ax - piece.bx) < 1e-6 then piece.ax - half else math.min(piece.ax, piece.bx)
		local x1 = if axisAligned and math.abs(piece.ax - piece.bx) < 1e-6 then piece.ax + half else math.max(piece.ax, piece.bx)
		local z0 = if math.abs(piece.az - piece.bz) < 1e-6 then piece.az - half else math.min(piece.az, piece.bz)
		local z1 = if math.abs(piece.az - piece.bz) < 1e-6 then piece.az + half else math.max(piece.az, piece.bz)
		inside = inside and axisAligned and inLawn(x0, z0, x1, z1, home.x, home.z) and not Map.onRoad((x0 + x1) / 2, (z0 + z1) / 2)
		local nextPiece = ramp[n + 1]
		if nextPiece then
			-- the next piece starts where this one ends: at its height, on its edge (a flight ends on a landing's edge, a
			-- landing's edge is where the next flight starts)
			joined = joined and math.abs(nextPiece.ya - piece.yb) < 1e-6
			local landingPiece = if piece.kind == "landing" then piece else nextPiece
			local flightPiece = if piece.kind == "landing" then nextPiece else piece
			local lx, lz = (landingPiece.ax + landingPiece.bx) / 2, (landingPiece.az + landingPiece.bz) / 2
			local px, pz = if piece.kind == "landing" then flightPiece.ax else flightPiece.bx, if piece.kind == "landing" then flightPiece.az else flightPiece.bz
			joined = joined and math.abs(math.max(math.abs(px - lx), math.abs(pz - lz)) - landingPiece.width / 2) < 1e-6
		end
	end
	local last = ramp[#ramp]
	print(string.format("  %s: the ramps at %.3f (%.1f°), the curb's %.3f", name, steepest, math.deg(math.atan(steepest)), CurbShape.Slope))
	check(`{name}: no steeper than the curb (every person walks up it, every bike and scooter rides it)`, steepest > 0 and steepest <= CurbShape.Slope and math.deg(math.atan(steepest)) <= 14.05, steepest)
	check(`{name}: flat landings big enough to turn a bike on, every piece joined to the next`, joined)
	check(`{name}: a walkway a bike fits on`, wide)
	check(`{name}: down to the ground`, last.kind == "ramp" and math.abs(last.yb - Map.WalkTop) < 1e-9)
	check(`{name}: all of it inside its park's lawn (off the sidewalk band, off the road)`, inside)
end
local foot = F.ramps.park[#F.ramps.park]
check("the park's ramp comes down onto the park's east path (from the ring to the sidewalk)", math.abs(foot.bz - P.z) <= 4 and foot.bx > P.x + P.pond + 1.5 + P.ring)
check("the garden's ramp is the park's turned half round (one design)", #F.ramps.garden == #F.ramps.park and F.ramps.garden[2].ax == 2 * F.x - F.ramps.park[2].ax)
local gfoot = F.ramps.garden[#F.ramps.garden]
local reached = false
for _, box in G.paths do
	local u, v = gfoot.bx - G.x, gfoot.bz - G.z
	if u >= box.u0 - 0.1 and u <= box.u1 + 0.1 and math.abs(math.max(box.v0 - v, 0, v - box.v1)) <= 2.5 then
		reached = true
	end
end
check("the garden's ramp comes down by a path", reached)

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
