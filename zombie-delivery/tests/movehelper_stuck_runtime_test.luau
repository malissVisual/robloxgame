-- 9.3 Danny stuck, audited (the owner, 8.9.5: "Danny still annoys me. He takes it completely like a robot. For example,
-- he runs for 2 seconds and then on the spot he somehow teleports around … fix it so it's playable"). The real
-- server/Moving.luau and server/MoveHelper.luau on tests/runtime/MovingRuntime.luau's fakes (Config.Sandbox.On) with the
-- real art (shared/FurnitureLooks.luau, shared/HouseLayout.luau, server/HouseInterior.luau and its fixtures' parts as
-- the game builds them, server/FixtureMesh.luau's without the import): a move into each of SandboxMap.Houses (The Old
-- Farmstead and the five other places to empty, 9.5 each of its own kind: its contract's, the map's). His body is
-- Config.MoveHelper.Body (Roblox's classic R15: a capsule Radius round his root; his collidable parts from Hip to Height
-- over the floor; StepUp the highest rise a Humanoid walks onto with its Jumping state off, an assumption), swept
-- against every collidable part of the built
-- interior (CanCollide: the shell's walls, the fixtures' solid parts, the pieces' roots): a part in his way above StepUp
-- is a hit (over Hip his torso's: a collision; under it a step higher than he climbs).
--   * the sweep, along his ways on the server's grid (HouseRoute.path): from each way in (where the door puts him) to
--     every piece's spot (HouseRoute.reach) and from it back out of the door, and between many open points; walked as
--     8.9.5 walked them (straight at his way's next corner, on to the next one a stud before it: the cause, measured on
--     the plan's grid) and as 9.3 walks them (HouseRoute.ahead's point on the server's grid, ordered again every
--     Walk.Reorder s or within Walk.Near of it, the humanoid straight at it between, slowing into the goal): 9.3 no hit,
--     never nearer than Walk.Clear to anything; every piece a spot, StandFar off at most, clear of every part; the door's
--     arrival spot and the doorway he walks into clear of every part
--   * real runs: four pieces of each house given to him and carried out (his list, his pick-up, the door both ways, the
--     van's back), his walk a Humanoid's stand-in that never goes deeper into a collidable part of the interior than it is
--     (blocked: it slides along the part's side or stands): no hit, never a stuck spell, never put anywhere but through
--     the doors, each door walked into fading out and out of it fading in (the mover's fade; out of the house with a piece
--     in his hands the piece fades with him), outside never in the
--     house's walls; Studio's Output lines (MoveHelper.diagnose): "[Danny] teleport door <studs> studs at (x, y, z)" a
--     trip, never "[Danny] stuck"
-- 8.9.5 measured with this test before the fix (the same seeds): 1,130 swept steps of the 8.9.5 walk within his body of
-- a wall (0.35 studs off at the closest; 4 a low piece's step), the grid's own legs 0.95 studs off a garage door's leaf the
-- plan does not know; in the real runs a 3.9 s stuck spell and a 0.35-stud nudge on the spot, 48 door trips, all popped.
-- 9.5 measured with this test on the countryside's map: The Forest Lodge's walk 1.09 studs off a doorway's jamb at the
-- closest, on the first leg of his way from where the door puts him (a quarter stud off his cell's middle: the leg the
-- way was pulled from began there, not where he stood; HouseRoute.path now steps onto the cell first when it must).
math.randomseed(93)
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Rules = require("./MovingRules")
local Brain = require("./MoveHelperBrain")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local HouseRoute = require("./HouseRoute")
local SandboxMap = require("./SandboxMap")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local H = Config.MoveHelper
local W = H.Walk
local BODY = H.Body
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (no roamers near)
end

-- the real art
local built: { any } = {}
Moving.useArt({
	looks = FurnitureLooks,
	layout = HouseLayout,
	interior = {
		slot = HouseInterior.slot,
		build = function(plan: any, origin: any): (any, any)
			E.built += 1
			table.insert(E.interiors, origin)
			local model, pieces = HouseInterior.build(plan, origin)
			table.insert(built, { model = model, plan = plan, origin = origin, pieces = pieces })
			return model, pieces
		end,
		destroy = function(model: any)
			E.destroyed += 1
			HouseInterior.destroy(model)
		end,
	},
})

-- ── The built geometry ────────────────────────────────────────────────────────

-- A collidable part: its full name, its frame and half size along its own X and Z (`upright`: turned about Y only),
-- its world box (x0 … z1) and its height (y0 … y1).
type Solid = { name: string, frame: any, hx: number, hz: number, y0: number, y1: number, x0: number, x1: number, z0: number, z1: number, upright: boolean }

local function fullName(part: any, top: any): string
	local names: { string } = {}
	local node = part
	while node and node ~= top do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	table.insert(names, 1, top.Name)
	return table.concat(names, ".")
end

-- The model's collidable parts in his body's height (StepUp … Height over `floor`).
local function solidsOf(model: any, floor: number): { Solid }
	local list: { Solid } = {}
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") or d.CanCollide == false then
			continue
		end
		local r = d.CFrame.R
		local s = d.Size
		local ex = math.abs(r[1]) * s.X + math.abs(r[2]) * s.Y + math.abs(r[3]) * s.Z
		local ey = math.abs(r[4]) * s.X + math.abs(r[5]) * s.Y + math.abs(r[6]) * s.Z
		local ez = math.abs(r[7]) * s.X + math.abs(r[8]) * s.Y + math.abs(r[9]) * s.Z
		local p = d.CFrame.Position
		if p.Y + ey / 2 <= floor + BODY.StepUp or p.Y - ey / 2 >= floor + BODY.Height then
			continue
		end
		table.insert(list, { name = fullName(d, model), frame = d.CFrame, hx = s.X / 2, hz = s.Z / 2, y0 = p.Y - ey / 2, y1 = p.Y + ey / 2,
			x0 = p.X - ex / 2, x1 = p.X + ex / 2, z0 = p.Z - ez / 2, z1 = p.Z + ez / 2, upright = math.abs(math.abs(r[5]) - 1) < 1e-6 })
	end
	return list
end

-- 2D: studs from (px, pz) to the segment, and from the segment (ax, az)-(bx, bz) to the rect [x0, x1] × [z0, z1].
local function segPoint(ax: number, az: number, bx: number, bz: number, px: number, pz: number): number
	local dx, dz = bx - ax, bz - az
	local l2 = dx * dx + dz * dz
	local t = if l2 > 1e-12 then math.clamp(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1) else 0
	local qx, qz = ax + dx * t - px, az + dz * t - pz
	return math.sqrt(qx * qx + qz * qz)
end
local function pointRect(px: number, pz: number, x0: number, z0: number, x1: number, z1: number): number
	return math.sqrt(math.max(x0 - px, 0, px - x1) ^ 2 + math.max(z0 - pz, 0, pz - z1) ^ 2)
end
local function segRect(ax: number, az: number, bx: number, bz: number, x0: number, z0: number, x1: number, z1: number): number
	if HouseRoute.cuts(ax, az, bx, bz, { x0 = x0, z0 = z0, x1 = x1, z1 = z1 }) then
		return 0
	end
	local best = math.min(pointRect(ax, az, x0, z0, x1, z1), pointRect(bx, bz, x0, z0, x1, z1))
	for _, c in { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } } do
		best = math.min(best, segPoint(ax, az, bx, bz, c[1], c[2]))
	end
	return best
end
local function solidGap(s: Solid, a: any, b: any): number
	if s.upright then
		local pa, pb = s.frame:PointToObjectSpace(a), s.frame:PointToObjectSpace(b)
		return segRect(pa.X, pa.Z, pb.X, pb.Z, -s.hx, -s.hz, s.hx, s.hz)
	end
	return segRect(a.X, a.Z, b.X, b.Z, s.x0, s.z0, s.x1, s.z1)
end

-- What a sweep found: steps swept, hits (collisions with his torso, steps higher than he climbs), the closest it came
-- to a part and the parts hit (by full name).
type Hits = { steps: number, body: number, step: number, least: number, parts: { [string]: number } }
local function newHits(): Hits
	return { steps = 0, body = 0, step = 0, least = math.huge, parts = {} }
end

-- His body from a to b (world; the floor at `floor`): every part within Radius of his way (in his height) a hit.
local function sweep(solids: { Solid }, a: any, b: any, floor: number, hits: Hits)
	hits.steps += 1
	local r = BODY.Radius
	local sx0, sx1 = math.min(a.X, b.X) - 3, math.max(a.X, b.X) + 3
	local sz0, sz1 = math.min(a.Z, b.Z) - 3, math.max(a.Z, b.Z) + 3
	for _, s in solids do
		if s.x1 < sx0 or s.x0 > sx1 or s.z1 < sz0 or s.z0 > sz1 then
			continue
		end
		local d = solidGap(s, a, b)
		hits.least = math.min(hits.least, d)
		if d < r - 1e-3 then
			if s.y1 > floor + BODY.Hip then
				hits.body += 1
			else
				hits.step += 1
			end
			hits.parts[s.name] = (hits.parts[s.name] or 0) + 1
		end
	end
end
local function add(into: Hits, from: Hits)
	into.steps += from.steps
	into.body += from.body
	into.step += from.step
	into.least = math.min(into.least, from.least)
	for k, v in from.parts do
		into.parts[k] = (into.parts[k] or 0) + v
	end
end
local function partsOf(hits: Hits): string
	local names: { string } = {}
	for name, n in hits.parts do
		table.insert(names, `{name} ×{n}`)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

-- ── His walks along a way (`points` { { x, z } } in the plan's frame; the server looks every 0.1 s, the humanoid walks
-- straight at the point it was ordered to between, 1/30 s at a time); the trail's points at every look ──────────────

local SPEED = Config.Movement.Walk * H.Speed -- (his walk to a piece)

-- 8.9.5: ordered at his way's next corner (again when it moved 1.5 studs), on to the next one a stud before it.
local function walk895(points: { any }, fx: number, fz: number): { any }
	local trail: { any } = { { x = fx, z = fz } }
	local x, z = fx, fz
	local index = 1
	local ox, oz, ordered = fx, fz, false
	for _ = 1, 3000 do
		while index < #points and (points[index].x - x) ^ 2 + (points[index].z - z) ^ 2 < 1 do
			index += 1
		end
		local p = points[index]
		if not ordered or (p.x - ox) ^ 2 + (p.z - oz) ^ 2 > 1.5 * 1.5 then
			ox, oz, ordered = p.x, p.z, true
		end
		for _ = 1, 3 do
			local dx, dz = ox - x, oz - z
			local l = math.sqrt(dx * dx + dz * dz)
			if l > 1e-6 then
				local step = math.min(l, SPEED / 30)
				x, z = x + dx / l * step, z + dz / l * step
			end
		end
		table.insert(trail, { x = x, z = z })
		if index >= #points and (p.x - x) ^ 2 + (p.z - z) ^ 2 < 1e-6 then
			break
		end
	end
	return trail
end

-- 9.3 (server/MoveHelper.luau's go and mover): aimed at HouseRoute.ahead's point every look, ordered again every
-- Walk.Reorder s (or within Walk.Near of the point it was ordered to), slowing into the goal (MoveHelperBrain.ease).
local function walk93(g: any, points: { any }, fx: number, fz: number): { any }
	local trail: { any } = { { x = fx, z = fz } }
	local x, z = fx, fz
	local index = 1
	local ox, oz, orderedAt = fx, fz, -math.huge
	local reach = math.clamp(SPEED * W.Lead, W.Ahead, W.AheadMost)
	local left = math.huge
	for look = 1, 3000 do
		local t = look * 0.1
		local ax, az
		ax, az, index, left = HouseRoute.ahead(g, points, index, x, z, reach, W.Clear)
		local moved = math.sqrt((ax - ox) ^ 2 + (az - oz) ^ 2)
		if orderedAt == -math.huge or moved > 4 or (moved > 0.2 and (t - orderedAt >= W.Reorder or (ox - x) ^ 2 + (oz - z) ^ 2 < W.Near * W.Near)) then
			ox, oz, orderedAt = ax, az, t
		end
		local pace = SPEED * Brain.ease(left)
		for _ = 1, 3 do
			local dx, dz = ox - x, oz - z
			local l = math.sqrt(dx * dx + dz * dz)
			if l > 1e-6 then
				local step = math.min(l, pace / 30)
				x, z = x + dx / l * step, z + dz / l * step
			end
		end
		table.insert(trail, { x = x, z = z })
		if left < 0.05 and (ox - x) ^ 2 + (oz - z) ^ 2 < 1e-6 then
			break
		end
	end
	return trail
end

-- His walk in the real runs (a Humanoid's stand-in): toward the point he is given at his speed, 1/30 s at a time, never
-- deeper into a collidable part of the interior than he is (within Radius of it in his height); blocked, he slides along
-- its side (the larger way of the step's two) or stands. His fades counted (the door's out and in; a fade-over in). His
-- way outside PathfindingService's stand-in: round the house's box (its walls, the doors' halls aside), Margin off it
-- (MoveHelperBrain.roundVan's way round a box: Roblox's paths keep his agent's radius off the house's solid parts).
local active: { solids: { Solid }, box: any? }? = nil
local fadesOut, fadesIn, appears, fadesWith = 0, 0, 0, 0
local function clearanceAt(at: any): number
	local a = active
	if not a then
		return math.huge
	end
	local least = math.huge
	for _, s in a.solids do
		if s.x1 < at.X - 3 or s.x0 > at.X + 3 or s.z1 < at.Z - 3 or s.z0 > at.Z + 3 then
			continue
		end
		least = math.min(least, solidGap(s, at, at))
	end
	return least
end
MoveHelper.useMover({
	appear = function(_body: any)
		appears += 1
	end,
	fade = function(_body: any, out: boolean, _seconds: number, with: any?)
		if out then
			fadesOut += 1
			fadesWith += if with and with:GetAttribute("FurnitureId") ~= nil then 1 else 0
		else
			fadesIn += 1
		end
	end,
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		for _ = 1, math.max(1, math.floor(dt * 30 + 0.5)) do
			local way = V3(to.X - here.X, 0, to.Z - here.Z)
			local length = way.Magnitude
			if length < 1e-6 then
				break
			end
			local step = math.min(length, speed / 30)
			local now = math.min(BODY.Radius, clearanceAt(here))
			local goal = here + way / length * step
			if clearanceAt(goal) < now - 1e-4 then
				local sx, sz = way.X / length * step, way.Z / length * step
				local a = here + (if math.abs(sx) >= math.abs(sz) then V3(sx, 0, 0) else V3(0, 0, sz))
				local c = here + (if math.abs(sx) >= math.abs(sz) then V3(0, 0, sz) else V3(sx, 0, 0))
				goal = if clearanceAt(a) >= now - 1e-4 then a elseif clearanceAt(c) >= now - 1e-4 then c else here
			end
			here = goal
		end
		root.CFrame = CF(here.X, here.Y, here.Z)
		body.walking = true
	end,
	halt = function(body: any)
		body.walking = false
	end,
	route = function(_body: any, from: any, to: any): { any }?
		local a = active
		local box = a and a.box
		if not box then
			return { from, to }
		end
		local cx, cz = (box.x0 + box.x1) / 2, (box.z0 + box.z1) / 2
		local hx, hz = (box.x1 - box.x0) / 2, (box.z1 - box.z0) / 2
		local points = { from }
		local x, z, gx, gz = from.X - cx, from.Z - cz, to.X - cx, to.Z - cz
		for _ = 1, 6 do
			local nx, nz = Brain.roundVan(x, z, gx, gz, hx, hz, 0.5, H.PathRadius + BODY.Radius)
			table.insert(points, V3(nx + cx, from.Y, nz + cz))
			if math.abs(nx - gx) < 1e-6 and math.abs(nz - gz) < 1e-6 then
				break
			end
			x, z = nx, nz
		end
		return points
	end,
})
E.carId = "sprinter"
Moving.parkVan = function(player: any, spot: any, _seat: boolean, carId: string?): (string?, any)
	local old = E.cars[player]
	if old then
		old.model:Destroy()
	end
	local car = E.makeCar(player, carId or Config.Sandbox.Van, V3(spot.x, 2, spot.z))
	E.cars[player] = car
	return nil, car
end
Moving.start()
-- 9.5 the countryside: the six places of the map, each with its contract (Config.Moving.Sandbox.Houses) of its own kind,
-- the map's (no stand-in: every kind a place of its own)
do
	local kinds: { [string]: boolean } = {}
	local ok = #SandboxMap.Houses == 6
	for _, house in SandboxMap.Houses do
		local own = Config.Moving.Sandbox.Houses[house.id]
		ok = ok and own ~= nil and own.Kind == house.kind
		kinds[house.kind] = true
	end
	check("the six places of the map, each with its contract of its own kind: the big house, a family house, the cabin, the lodge, the mill, the cottage",
		ok and kinds.big and kinds.house and kinds.cabin and kinds.lodge and kinds.mill and kinds.cottage == true)
end
local lines: { string } = {}
MoveHelper.diagnose(true, function(line: string)
	table.insert(lines, line)
end)

local function pieceRect(s: any): HouseRoute.Rect
	local ex, ez = HouseLayout.extent(s.item, s.turn)
	local p = s.at.Position
	return { x0 = p.X - ex / 2, z0 = p.Z - ez / 2, x1 = p.X + ex / 2, z1 = p.Z + ez / 2 }
end

-- Every layout of the family house (dannynav's): the first seed of each back-row order, mirrored or not.
local function variants(kind: string): { number }
	local found: { [string]: boolean } = {}
	local list: { number } = {}
	for seed = 1, 400 do
		local plan = HouseLayout.plan(seed, kind)
		local ids: { string } = {}
		local back: { any } = {}
		for _, room in plan.rooms do
			if room.min.Z > plan.rooms[1].max.Z + 1 and room.id ~= "corridor" then
				table.insert(back, room)
			end
		end
		table.sort(back, function(a: any, b: any): boolean
			return a.min.X < b.min.X
		end)
		for _, room in back do
			table.insert(ids, room.id)
		end
		local key = table.concat(ids, ",") .. (if plan.mirrored then "|m" else "")
		if not found[key] then
			found[key] = true
			table.insert(list, seed)
		end
		if #list == 8 then
			break
		end
	end
	return list
end

-- ── Each house ────────────────────────────────────────────────────────────────

local houseSeeds = variants("house")
local bigSeed = variants("big")[3]
local plots = SandboxMap.Plots
local all = { old = newHits(), new = newHits(), oldLegs = newHits(), newLegs = newHits(), runs = newHits() }
local totals = { pops = 0, trips = 0, faded = 0, stuck = 0, noSpot = 0 }

for index, house in SandboxMap.Houses do
	local seed = if house.kind == "big" then bigSeed else houseSeeds[(index - 2) % #houseSeeds + 1]
	local plot = plots[(index - 1) % #plots + 1]
	local p = E.player(300 + index, `Crew{index}`, V3(plot.spawn.x, 3, plot.spawn.z))
	E.plots[p] = plot
	E.profiles[p] = { money = 5000, sandboxHouse = house.id, sandboxHouseSeed = seed }
	Moving.admin(p, "start")
	local b = built[#built]
	Moving.step()
	local danny = MoveHelper.find(p)
	local truck = E.cars[p]
	truck.chassis.CFrame = CF(house.curb.x, 2, house.curb.z) * M.CFrame.Angles(0, math.rad(house.curb.yaw), 0)
	truck.model:SetAttribute("BackOpen", true)
	E.place(p, V3(plot.spawn.x, 3, plot.spawn.z + 3000)) -- (out of sight: Danny is put at the van at the house, faded in)
	for _ = 1, 10 do
		E.clock += 0.1
		MoveHelper.step(0.1)
	end
	if not danny or not b or not danny.route then
		check(`{house.name}: Danny with the move, his grid`, false)
		continue
	end
	local plan, origin = b.plan, b.origin
	check(`{house.name}: its move's plan of its own kind ("{house.kind}", its contract's)`, plan.kind == house.kind, plan.kind)
	local floor = origin.Position.Y
	local y = floor + 3
	local solids = solidsOf(b.model, floor)
	local live = danny.route -- (the server's grid: the plan, the built parts, the pieces where they stand)
	local old = HouseRoute.grid(plan) :: HouseRoute.Grid -- (8.9.5's: the plan's alone, legs on open cells only)
	local rects: { HouseRoute.Rect } = {}
	for _, s in plan.spots do
		table.insert(rects, pieceRect(s))
	end
	HouseRoute.block(old, rects)
	local function world(x: number, z: number): any
		local w = origin * V3(x, 0, z)
		return V3(w.X, y, w.Z)
	end
	local hits = { old = newHits(), new = newHits(), oldLegs = newHits(), newLegs = newHits() }
	local function swept(trail: { any }, into: Hits)
		for k = 2, #trail do
			sweep(solids, world(trail[k - 1].x, trail[k - 1].z), world(trail[k].x, trail[k].z), floor, into)
		end
	end
	-- a way from (fx, fz) to (tx, tz): walked both ways, its legs swept
	local function both(fx: number, fz: number, tx: number, tz: number)
		local before = HouseRoute.path(old, fx, fz, tx, tz)
		if before then
			swept(walk895(before, fx, fz), hits.old)
			local legs = { { x = fx, z = fz } }
			for _, q in before do
				table.insert(legs, q)
			end
			swept(legs, hits.oldLegs)
		end
		local now = HouseRoute.path(live, fx, fz, tx, tz)
		if now then
			swept(walk93(live, now, fx, fz), hits.new)
			local legs = { { x = fx, z = fz } }
			for _, q in now do
				table.insert(legs, q)
			end
			swept(legs, hits.newLegs)
		end
	end
	-- from each way in (where the door puts him) to every piece's spot, and back out of the door
	local noSpot, standBad, arriveBad = 0, 0, 0
	for _, way in danny.ways do
		local arrive = way.entryIn.Position + way.entryIn.LookVector * 1.5
		local ap = origin:PointToObjectSpace(arrive)
		local exitP = origin:PointToObjectSpace(way.exitIn)
		local through = way.exitIn - way.entryIn.LookVector * W.DoorIn -- (the doorway he walks into as he fades out)
		local arriveGap = math.huge
		for _, s in solids do
			arriveGap = math.min(arriveGap, solidGap(s, arrive, arrive), solidGap(s, through, through))
		end
		arriveBad += if arriveGap < BODY.Radius then 1 else 0
		for _, s in plan.spots do
			local x, z = HouseRoute.reach(live, ap.X, ap.Z, pieceRect(s))
			if not x or not z then
				noSpot += 1
				continue
			end
			local spot = world(x, z)
			local gap = math.huge
			for _, part in solids do
				gap = math.min(gap, solidGap(part, spot, spot))
			end
			standBad += if gap < BODY.Radius or HouseRoute.toRect(x, z, pieceRect(s)) > H.Route.StandFar + 1e-6 then 1 else 0
			both(ap.X, ap.Z, x, z)
			both(x, z, exitP.X, exitP.Z)
		end
	end
	-- between open points of the server's grid
	local opens: { number } = {}
	for k = 1, #live.open do
		if live.open[k] == 1 then
			table.insert(opens, k)
		end
	end
	for _ = 1, 30 do
		local a, c = opens[math.random(#opens)], opens[math.random(#opens)]
		local ax, az = live.x0 + ((a - 1) % live.nx) * live.step, live.z0 + ((a - 1) // live.nx) * live.step
		local cx, cz = live.x0 + ((c - 1) % live.nx) * live.step, live.z0 + ((c - 1) // live.nx) * live.step
		both(ax, az, cx, cz)
	end
	for key, h in hits do
		add((all :: any)[key], h)
	end
	totals.noSpot += noSpot
	local closed = 0
	for k = 1, #live.still do
		closed += if live.still[k] ~= old.still[k] then 1 else 0
	end
	print(string.format("AUDIT %s: 8.9.5's walk %d steps, %d hits (%d steps higher than %.1f), %.2f studs off at the closest; its grid's legs %d hits, %.2f off",
		house.name, hits.old.steps, hits.old.body + hits.old.step, hits.old.step, BODY.StepUp, hits.old.least, hits.oldLegs.body + hits.oldLegs.step, hits.oldLegs.least))
	print(string.format("      9.3's walk %d steps, %d hits, %.2f studs off at the closest; its grid's legs %d hits, %.2f off; the built parts closed %d cells",
		hits.new.steps, hits.new.body + hits.new.step, hits.new.least, hits.newLegs.body + hits.newLegs.step, hits.newLegs.least, closed))
	if hits.old.body + hits.old.step > 0 then
		print("      8.9.5's hits: " .. partsOf(hits.old))
	end
	check(`{house.name}: 9.3's walk along his ways (to every piece and out, between open points) touches no collidable part, Walk.Clear off at least`,
		hits.new.body + hits.new.step == 0 and hits.newLegs.body + hits.newLegs.step == 0 and hits.new.least >= W.Clear - 0.01, `{partsOf(hits.new)} {hits.new.least}`)
	check(`{house.name}: every piece a spot to take it from (HouseRoute.reach), StandFar off at most, clear of every part`, noSpot == 0 and standBad == 0,
		`{noSpot} {standBad}`)
	check(`{house.name}: where the door puts him and the doorway he walks into clear of every part`, arriveBad == 0, arriveBad)

	-- real runs: four pieces given to him, carried out
	active = { solids = solids, box = house.box }
	local spawn = E.task.spawn
	local function now(callback: any, ...: any) -- (his path outside in the background: at once here)
		callback(...)
	end
	local walked = newHits()
	local trips, pops, worstStuck, outsideBad = 0, 0, 0, 0
	local out0, in0, appear0, lines0, with0 = fadesOut, fadesIn, appears, #lines, fadesWith
	local teleports0 = table.clone(danny.teleports)
	local given = 0
	local entry = origin:PointToObjectSpace(danny.ways[1].entryIn.Position)
	local order = table.clone(plan.spots)
	table.sort(order, function(a: any, c: any): boolean
		return (a.at.Position - entry).Magnitude > (c.at.Position - entry).Magnitude
	end)
	local box = house.box
	local halls: { any } = {}
	for _, way in danny.ways do
		table.insert(halls, V3(way.door.X, 0, way.door.Z))
	end
	for _, s in order do
		local def = FurnitureLooks.Items[s.item]
		if given >= 4 or (def.class ~= "hand" and def.class ~= "both") or not Rules.canLoad(danny.s.move, s.id) or danny.s.move.things[s.id].state ~= "home" then
			continue
		end
		given += 1
		local model = b.pieces[s.id]
		local was = E.rootOf(p).Position
		E.place(p, model.PrimaryPart.Position + model.PrimaryPart.CFrame.LookVector * 1.5)
		p.Character:SetAttribute("ClipboardHeld", true)
		E.request(p, "helper", "assign", model)
		E.place(p, was)
		local last = danny.body.root.Position
		for _ = 1, 1500 do
			E.clock += 0.1
			E.task.spawn = now
			MoveHelper.step(0.1)
			E.task.spawn = spawn
			Moving.step()
			local body = danny.body
			if not body then
				break
			end
			local now = body.root.Position
			local inA, inB = (last - origin.Position).Magnitude < 400, (now - origin.Position).Magnitude < 400
			if inA ~= inB then
				trips += 1
			elseif (now - last).Magnitude > Config.Movement.Walk * H.Sprint * 0.1 + 0.1 then
				pops += 1
			elseif inB then
				sweep(solids, last, now, floor, walked)
			else
				-- outside: never in the house's walls (its box, but for the door's hall he walks into)
				local inBox = now.X > box.x0 + BODY.Radius and now.X < box.x1 - BODY.Radius and now.Z > box.z0 + BODY.Radius and now.Z < box.z1 - BODY.Radius
				local hall = false
				for _, foot in halls do
					hall = hall or (V3(now.X, 0, now.Z) - foot).Magnitude <= Config.Moving.Doors.Hall.Depth
				end
				outsideBad += if inBox and not hall then 1 else 0
			end
			worstStuck = math.max(worstStuck, danny.stuckFor)
			if Rules.holding(danny.s.move, danny.id) == s.id and danny.handle == nil then
				model.PrimaryPart.CFrame = body.root.CFrame * CF(0, 0, -2) -- (the weld's stand-in: in his hands as he walks)
			end
			last = now
			if danny.s.move.things[s.id].state == "truck" then
				break
			end
		end
	end
	active = nil
	local put: { string } = {}
	for why, n in danny.teleports do
		local more = n - (teleports0[why] or 0)
		if more > 0 and why ~= "door" then
			table.insert(put, `{why} ×{more}`)
		end
	end
	local doorLines, stuckLines = 0, 0
	for k = lines0 + 1, #lines do
		doorLines += if string.find(lines[k], "[Danny] teleport door ", 1, true) == 1 then 1 else 0
		stuckLines += if string.find(lines[k], "[Danny] stuck ", 1, true) == 1 then 1 else 0
	end
	local doors = (danny.teleports.door or 0) - (teleports0.door or 0)
	add(all.runs, walked)
	totals.pops += pops + #put
	totals.trips += trips
	totals.faded += math.min(fadesOut - out0, fadesIn - in0)
	totals.stuck = math.max(totals.stuck, worstStuck)
	print(string.format("RUN %s: %d pieces carried out, %d steps (%d hits, %.2f studs off at the closest), %d door trips (faded out %d, in %d), put elsewhere: %s, stuck %.1f s at most",
		house.name, given, walked.steps, walked.body + walked.step, walked.least, trips, fadesOut - out0, fadesIn - in0, if #put > 0 then table.concat(put, ", ") else "never",
		worstStuck))
	check(`{house.name}: four pieces carried out by a walk that never goes into a part: no hit, never a stuck spell (Unstuck.Repath s)`,
		given == 4 and walked.body + walked.step == 0 and worstStuck < H.Unstuck.Repath, `{given} {partsOf(walked)} {worstStuck}`)
	check(`{house.name}: …never put anywhere but through the doors (no pop, no nudge, no fade-over), outside never in the house's walls`,
		pops == 0 and #put == 0 and appears == appear0 and outsideBad == 0, `{pops} {table.concat(put, ", ")} {appears - appear0} {outsideBad}`)
	check(`{house.name}: …each door walked into fading out and out of it fading in (the players' walk-in doors; out with a piece: it fades with him), every trip a "[Danny] teleport door" line`,
		trips == 8 and doors == trips and fadesOut - out0 == trips and fadesIn - in0 == trips and fadesWith - with0 == given and doorLines == trips and stuckLines == 0,
		`{trips} {doors} {fadesOut - out0} {fadesIn - in0} {fadesWith - with0} {doorLines} {stuckLines}`)
	Moving.admin(p, "end")
	Moving.step()
end

print(string.format("AUDIT ALL: 8.9.5's walk %d steps, %d hits (%d steps), %.2f studs off at the closest; its grid's legs %d hits, %.2f off",
	all.old.steps, all.old.body + all.old.step, all.old.step, all.old.least, all.oldLegs.body + all.oldLegs.step, all.oldLegs.least))
print(string.format("AUDIT ALL: 9.3's walk %d steps, %d hits, %.2f studs off at the closest; its grid's legs %d hits, %.2f off",
	all.new.steps, all.new.body + all.new.step, all.new.least, all.newLegs.body + all.newLegs.step, all.newLegs.least))
print(string.format("RUN ALL: %d steps, %d hits, %d door trips (%d faded both ways), %d put elsewhere, stuck %.1f s at most",
	all.runs.steps, all.runs.body + all.runs.step, totals.trips, totals.faded, totals.pops, totals.stuck))
check("the six houses (9.5: every countryside kind among them): 8.9.5's walk measured hitting walls (the cause), 9.3's none", all.old.body > 0 and all.new.body + all.new.step == 0 and totals.noSpot == 0)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
