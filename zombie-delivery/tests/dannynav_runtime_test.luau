-- 9.0 Danny inside the real houses (the owner, 8.9: "Danny can't walk around things logically. He goes to take things
-- through the wall: he can't get to the thing, he got stuck on the wall because he can't walk around it. He must not take
-- things through walls (that's funny), and neither may the player. And he must come to the thing nicely and take it into
-- his hands properly, with an animation"; his screenshot: "Going for: Chair" at a wall, "Danny · 1 / 2 / 3" through the
-- walls). The real server/Moving.luau and server/MoveHelper.luau on tests/runtime/MovingRuntime.luau's fakes
-- (Config.Sandbox.On) with the real art (shared/FurnitureLooks.luau, shared/HouseLayout.luau, server/HouseInterior.luau
-- and its shell's real wall parts): a move into each of Jinočany's six houses, The Old Farmstead (the big house, 8.5.2
-- roomy) and the five family houses, each with another layout (the back row's order, mirrored or not). His walk is a
-- straight step toward the point he is given (useMover: his way's corners), the rays at the interior's walls the
-- runtime's (a ray against the parts' boxes).
--   * his ways on the server's own grid (the move's plan, the real pieces where they stand): from his way in to every
--     piece of the house a spot beside it, and every leg of his way there clear of the shell's real wall parts (a ray
--     along it at his chest) and in the rooms and the doorways
--   * a pick through a wall is refused: Ann behind a wall from a piece, within the prompt's reach: no pick ("You can't
--     reach the X through the wall."), the piece's prompts need a line of sight (RequiresLineOfSight)
--   * Danny put at that same spot behind the wall with the piece given to him: he never takes it from there; he walks
--     round through the doorways (no step across a wall, never out of the rooms, never stuck: 9.3 no stuck spell at all)
--     and takes it from its own side, within Pick.Arm of it, his chest's ray to it clear of the walls; his pick-up:
--     turned to it (Npcs.face), the bend with both hands on it ("lift", the Carrying attributes on its place while it
--     still stands), then his, gliding up into his hands over steps (anchored, its weld off, never snapped), welded
--     again at his hold; carried out and loaded
--   * the 🧑‍🔧 markers over his list's pieces: never on top (AlwaysOnTop off), MarkFar studs at most
--   * (the big house) PUT IT DOWN: "setdown", the piece glides down to the floor over steps, then on the ground, its
--     condition kept; a piece boxed in by others: refused at once ("Danny can't get to the X: clear a way to it first.")
math.randomseed(90)
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Rules = require("./MovingRules")
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

local T = Config.Moving
local H = Config.MoveHelper
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
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

-- His walk: straight toward the point he is given (his way's next corner), speed × dt a step.
MoveHelper.useMover({
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local step = math.min(length, speed * dt)
			root.CFrame = CF(here.X + way.X / length * step, here.Y, here.Z + way.Z / length * step)
		end
		body.walking = true
	end,
	halt = function(body: any)
		body.walking = false
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

local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and d.ActionText ~= nil and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function told(player: any, text: string, from: number): boolean
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) then
			return true
		end
	end
	return false
end
local function pieceRect(s: any): HouseRoute.Rect
	local ex, ez = HouseLayout.extent(s.item, s.turn)
	local p = s.at.Position
	return { x0 = p.X - ex / 2, z0 = p.Z - ez / 2, x1 = p.X + ex / 2, z1 = p.Z + ez / 2 }
end

-- Every layout of the family house: the first seed of each back-row order, mirrored or not (the five houses take five).
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
			break -- (four orders, mirrored or not: all of them)
		end
	end
	return list
end

-- ── The walk's watch (every step of his) ─────────────────────────────────────

type Watch = {
	h: any,
	grid: HouseRoute.Grid,
	origin: any,
	spot: number,
	last: any?,
	crossed: number,
	outRoom: number,
	why: string?,
	stuck: number,
	hold: any?, -- his hold in his root's frame (his pick-up's), the piece kept there after it (the mock's weld does nothing)
	faced: boolean, -- turned to it before the take
	bent: boolean, -- "lift" before the take
	hands: boolean, -- the Carrying attributes on it while it still stood (state home)
	tookAt: any?, -- his root at the take
	glide: { any }, -- the piece's place at each step of the glide
	anchored: boolean, -- …anchored all the glide, its weld off
	welded: boolean, -- its weld on again after
}
local watch: Watch? = nil
local acts0, faces0 = 0, 0

local function observe(w: Watch)
	local h = w.h
	local body = h.body
	if not body then
		return
	end
	local at = body.root.Position
	local inside = (at - w.origin.Position).Magnitude < 400
	local lp = if inside then w.origin:PointToObjectSpace(at) else nil
	local last = w.last
	if lp and last then
		for _, wall in w.grid.walls do
			if HouseRoute.cuts(last.X, last.Z, lp.X, lp.Z, wall) then
				w.crossed += 1
				w.why = `({math.floor(last.X)},{math.floor(last.Z)}) → ({math.floor(lp.X)},{math.floor(lp.Z)})`
			end
		end
		if not HouseRoute.inside(w.grid, lp.X, lp.Z) then
			w.outRoom += 1
		end
	end
	w.last = lp
	w.stuck = math.max(w.stuck, h.stuckFor)
	local model = built[#built].pieces[w.spot]
	local spot, role = Rules.holding(h.s.move, h.id)
	local handle = h.handle
	if not w.tookAt then
		if handle and handle.spot == w.spot and handle.phase == "bend" and h.s.move.things[w.spot].state == "home" then
			local carryAt = body.model:GetAttribute("CarryAt")
			local real = body.root.CFrame:PointToObjectSpace(model.PrimaryPart.Position)
			w.hands = w.hands or (body.model:GetAttribute("Carrying") ~= nil and carryAt ~= nil and (carryAt - real).Magnitude < 0.1)
		end
		if spot == w.spot and role == "carrier" then
			w.tookAt = at
			for k = faces0 + 1, #E.faces do
				local f = E.faces[k]
				w.faced = w.faced or (f.npc == body.model and (f.at - model.PrimaryPart.Position).Magnitude < 0.5)
			end
			for k = acts0 + 1, #E.acts do
				local a = E.acts[k]
				w.bent = w.bent or (a.npc == body.model and a.kind == "lift")
			end
		end
	end
	if handle and handle.kind == "pick" and handle.spot == w.spot and handle.phase == "lift" then
		w.hold = handle.to
		table.insert(w.glide, model.PrimaryPart.Position)
		local weld = handle.weld
		w.anchored = w.anchored and model.PrimaryPart.Anchored == true and weld ~= nil and weld.Enabled == false
	elseif spot == w.spot and role == "carrier" and not handle and w.hold then
		if #w.glide > 0 and not w.welded then
			local weld = nil
			for _, child in model.PrimaryPart:GetChildren() do
				if child.ClassName == "WeldConstraint" and child.Part0 == body.root then
					weld = child
				end
			end
			local there = (model.PrimaryPart.Position - (body.root.CFrame * w.hold).Position).Magnitude < 0.05
			w.welded = weld ~= nil and weld.Enabled ~= false and model.PrimaryPart.Anchored == false and there
		end
		model.PrimaryPart.CFrame = body.root.CFrame * w.hold -- (the weld's stand-in: in his hands as he walks)
	end
end

local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		if watch then
			observe(watch)
		end
		if index % 2 == 0 then
			Moving.step()
		end
		if done and done() then
			Moving.step()
			return true
		end
	end
	Moving.step()
	return done == nil
end

-- The real shell's wall parts: is any of them between two points (a ray along the line, at `y`)?
local function wallPartBetween(model: any, a: any, b: any): boolean
	local shell = model:FindFirstChild("Shell")
	local params = M.RaycastParams.new()
	params.FilterType = "Include"
	local walls: { any } = {}
	for _, part in shell:GetChildren() do
		if part.Name == "Wall" then
			table.insert(walls, part)
		end
	end
	params.FilterDescendantsInstances = walls
	return E.sightRay(a, b - a, params) ~= nil
end

-- A piece Danny takes alone (one hand or both, it fits the van) against an inside wall of its room, and a spot across
-- that wall in the next room, 1.6 studs past it, open on his grid (nobody stands in a piece there) and near enough
-- for the piece's prompt: (spot, x, z in the plan) or nil.
local function behindWall(plan: any, grid: HouseRoute.Grid, move: any): (any, number?, number?)
	for _, s in plan.spots do
		local def = FurnitureLooks.Items[s.item]
		if (def.class ~= "hand" and def.class ~= "both") or not Rules.canLoad(move, s.id) then
			continue
		end
		local rect = pieceRect(s)
		local p = s.at.Position
		for _, f in plan.faces do
			if f.room ~= s.room or f.outer or f.header then
				continue
			end
			local n = f.normal
			local alongX = math.abs(n.Z) > 0.5 -- (a wall along X: its normal along Z)
			local face = if alongX then (if n.Z > 0 then f.max.Z else f.min.Z) else (if n.X > 0 then f.max.X else f.min.X)
			local gap = if alongX then (p.Z - face) * n.Z else (p.X - face) * n.X
			local depth = (if alongX then rect.z1 - rect.z0 else rect.x1 - rect.x0) / 2
			local along = if alongX then p.X else p.Z
			local a0, a1 = if alongX then f.min.X else f.min.Z, if alongX then f.max.X else f.max.Z
			if gap < 0 or gap - depth > 0.8 or along < a0 + 0.8 or along > a1 - 0.8 then
				continue
			end
			local past = gap + plan.wall + 1.6
			local qx = if alongX then p.X else p.X - n.X * past
			local qz = if alongX then p.Z - n.Z * past else p.Z
			if HouseRoute.inside(grid, qx, qz) and HouseRoute.open(grid, qx, qz) and not HouseRoute.sees(grid, qx, qz, p.X, p.Z)
				and math.sqrt((qx - p.X) ^ 2 + (qz - p.Z) ^ 2) <= T.Reach.Item + math.max(def.size.X, def.size.Z) / 2 + 2 then
				return s, qx, qz
			end
		end
	end
	return nil, nil, nil
end

-- ── A move into each house ───────────────────────────────────────────────────

local houseSeeds = variants("house")
local bigSeed = variants("big")[3]
local Houses = SandboxMap.Houses
local plots = SandboxMap.Plots

local function moveInto(index: number, house: any, seed: number): (any, any, any)
	local plot = plots[(index - 1) % #plots + 1]
	local p = E.player(100 + index, `Crew{index}`, V3(plot.spawn.x, 3, plot.spawn.z))
	E.plots[p] = plot
	E.profiles[p] = { money = 5000, sandboxHouse = house.id, sandboxHouseSeed = seed }
	local started = Moving.admin(p, "start")
	local b = built[#built]
	check(`{house.name}: a move into it (its plan of kind "{house.kind}", seed {seed}{if b and b.plan.mirrored then ", mirrored" else ""})`,
		string.find(started, "started", 1, true) ~= nil and b ~= nil and b.plan.kind == house.kind and b.plan.seed == seed, started)
	Moving.step()
	local danny = MoveHelper.find(p)
	local truck = E.cars[p]
	truck.chassis.CFrame = CF(house.curb.x, 2, house.curb.z) * M.CFrame.Angles(0, math.rad(house.curb.yaw), 0)
	truck.model:SetAttribute("BackOpen", true)
	E.request(p, "helper", "hire")
	run(0.6)
	return p, danny, b
end

-- A click on a piece with the clipboard out by `p`, from in front of it (its room).
local function give(p: any, model: any)
	local was = E.rootOf(p).Position
	E.place(p, model.PrimaryPart.Position + model.PrimaryPart.CFrame.LookVector * 1.5)
	p.Character:SetAttribute("ClipboardHeld", true)
	E.request(p, "helper", "assign", model)
	E.place(p, was)
end

for index, house in Houses do
	local seed = if house.kind == "big" then bigSeed else houseSeeds[(index - 2) % #houseSeeds + 1]
	local p, danny, b = moveInto(index, house, seed)
	if not danny or not b then
		check(`{house.name}: Danny with the move`, false)
		continue
	end
	local plan, origin = b.plan, b.origin
	local live = danny.route -- (the server's: MoveHelper's grid of the move's plan, blocked with the real pieces)
	local grid = HouseRoute.grid(plan) :: HouseRoute.Grid -- (the test's own, for its geometry: the plan, its pieces at home)
	local rects: { HouseRoute.Rect } = {}
	for _, s in plan.spots do
		table.insert(rects, pieceRect(s))
	end
	HouseRoute.block(grid, rects)
	local y = origin.Position.Y + 3
	-- (the same walls and fixtures cell for cell; the pieces' cells the same but for a hair's float at his radius's edge;
	-- 9.3 and the built interior's collidable parts the plan does not have: a cell the plan leaves open closed only by one
	-- of those, HouseRoute.solid's rects after the plan's own solids)
	local differ, unexplained = 0, 0
	for k = 1, if live then #live.open else 0 do
		local plain = live.open[k] ~= grid.open[k] and live.still[k] == grid.still[k]
		differ += if plain then 1 else 0
		if live.still[k] ~= grid.still[k] then
			local x, z = grid.x0 + ((k - 1) % grid.nx) * grid.step, grid.z0 + ((k - 1) // grid.nx) * grid.step
			local built = false
			for n = #grid.solids + 1, #live.solids do
				built = built or HouseRoute.toRect(x, z, live.solids[n]) < live.radius
			end
			unexplained += if live.still[k] == 1 or not built then 1 else 0
		end
	end
	check(`{house.name}: his grid is the move's plan's (the walls, the fixtures, the pieces where they stand) and the built parts' (9.3)`, live ~= nil
		and #live.walls == #grid.walls and unexplained == 0 and differ <= #grid.open / 500, `{differ} {unexplained}`)

	-- his ways on the server's own grid, to every piece, against the shell's real wall parts
	local ways = live or grid
	local bad: string? = if live then nil else "no grid of his"
	local spots = 0
	for _, way in danny.ways do
		local entry = origin:PointToObjectSpace(way.entryIn.Position)
		for _, s in plan.spots do
			local x, z = HouseRoute.reach(ways, entry.X, entry.Z, pieceRect(s))
			local points = if x and z then HouseRoute.path(ways, entry.X, entry.Z, x, z) else nil
			if not points then
				bad = bad or `#{s.id} {s.item}: no way`
				continue
			end
			spots += 1
			local ax, az = entry.X, entry.Z
			for _, q in points do
				local a, c = origin * V3(ax, 1, az), origin * V3(q.x, 1, q.z)
				if wallPartBetween(b.model, V3(a.X, y + 1, a.Z), V3(c.X, y + 1, c.Z)) then
					bad = bad or `#{s.id} {s.item}: a leg through a wall part`
				end
				for k = 0, 8 do
					if not HouseRoute.inside(grid, ax + (q.x - ax) * k / 8, az + (q.z - az) * k / 8) then
						bad = bad or `#{s.id} {s.item}: a leg out of the rooms`
					end
				end
				ax, az = q.x, q.z
			end
		end
	end
	check(`{house.name}: from his way{if #danny.ways > 1 then "s" else ""} in, a way to every piece ({spots}), no leg through the shell's wall parts, all in the rooms and doorways`,
		bad == nil and spots == #plan.spots * #danny.ways, bad)

	-- a pick through a wall: refused for the player
	local s, qx, qz = behindWall(plan, grid, danny.s.move)
	if not s or not qx or not qz then
		check(`{house.name}: a piece against an inside wall, a spot behind it`, false)
		Moving.admin(p, "end")
		continue
	end
	local model = b.pieces[s.id]
	local name = FurnitureLooks.Items[s.item].name
	local behind = origin * V3(qx, 0, qz)
	E.place(p, V3(behind.X, y, behind.Z))
	local noticeAt = #E.messages
	local pick = promptIn(model, "Pick up")
	pick.Triggered:Fire(p)
	check(`{house.name}: Crew{index} behind the {s.room}'s wall from the {name} (within the prompt's reach): no pick through the wall, told so`,
		danny.s.move.things[s.id].state == "home" and p.Character:GetAttribute("MoveCarry") == nil
		and told(p, `You can't reach the {name} through the wall.`, noticeAt), E.lastNotice(p))
	check(`{house.name}: …its prompts need a line of sight (Pick up, Help lift)`, pick.RequiresLineOfSight == true and promptIn(model, "Help lift").RequiresLineOfSight == true)

	-- Danny put at that spot behind the wall, the piece given to him
	danny.body.root.CFrame = CF(behind.X, y, behind.Z)
	E.place(p, origin * V3(0, 3, 6)) -- (Crew in the hall, out of his way)
	give(p, model)
	E.place(p, origin * V3(0, 3, 6))
	local mark = model.PrimaryPart:FindFirstChild("DannyMark")
	check(`{house.name}: the {name} on his list: its 🧑‍🔧 marker never on top (no wall shows it), drawn {H.MarkFar} studs at most`, #danny.queue == 1 and mark ~= nil
		and mark.AlwaysOnTop == false and mark.MaxDistance == H.MarkFar and H.MarkFar <= 80, mark and mark.AlwaysOnTop)
	acts0, faces0 = #E.acts, #E.faces
	local w: Watch = { h = danny, grid = grid, origin = origin, spot = s.id, last = nil, crossed = 0, outRoom = 0, why = nil, stuck = 0, hold = nil, faced = false,
		bent = false, hands = false, tookAt = nil, glide = {}, anchored = true, welded = false }
	watch = w
	local took = run(90, function()
		return w.tookAt ~= nil and danny.handle == nil
	end)
	local at = if w.tookAt then origin:PointToObjectSpace(w.tookAt) else V3(qx, 0, qz)
	local rect = pieceRect(s)
	local mx, mz = (rect.x0 + rect.x1) / 2, (rect.z0 + rect.z1) / 2
	local reachAt = HouseRoute.toRect(at.X, at.Z, rect)
	local chest = (w.tookAt or behind) + V3(0, 1, 0)
	check(`{house.name}: Danny never takes the {name} through the wall: he walks round and takes it from its side`, took and HouseRoute.sees(grid, at.X, at.Z, mx, mz)
		and not wallPartBetween(b.model, chest, model.PrimaryPart.Position) and (at.X - qx) ^ 2 + (at.Z - qz) ^ 2 > 4, `{took} at ({at.X}, {at.Z})`)
	check(`{house.name}: …beside it at arm's length (within Pick.Arm of its footprint: {math.floor(reachAt * 100) / 100})`, reachAt <= H.Pick.Arm)
	check(`{house.name}: …his walk: no step across a wall, never out of the rooms and doorways, never stuck (9.3: no stuck spell to a new way, let alone his ways out)`, w.crossed == 0 and w.outRoom == 0
		and w.stuck < H.Unstuck.Repath, `{w.crossed} {w.why} {w.outRoom} {w.stuck}`)
	check(`{house.name}: …his pick-up: turned to it, then the bend ("lift") with both hands on it as it stands`, w.faced and w.bent and w.hands, `{w.faced} {w.bent} {w.hands}`)
	local glide = w.glide
	local smooth = #glide >= 3
	local hold = if w.hold then danny.body.root.CFrame * w.hold else nil
	for k = 2, #glide do
		smooth = smooth and hold ~= nil and (glide[k] - hold.Position).Magnitude < (glide[k - 1] - hold.Position).Magnitude
	end
	local home = s.at.Position
	local first = glide[1]
	check(`{house.name}: …it glides up into his hands over {#glide} steps (anchored, its weld off; never snapped), welded at his hold after`, smooth and w.anchored and w.welded
		and first ~= nil and ((origin * home) - first).Magnitude < 0.3, `{#glide} {w.anchored} {w.welded}`)
	local loaded = run(150, function()
		return danny.s.move.things[s.id].state == "truck"
	end)
	watch = nil
	check(`{house.name}: …carried out of the house (no wall crossed on the way) and loaded`, loaded and w.crossed == 0 and w.outRoom == 0 and w.stuck < H.Unstuck.Repath,
		danny.s.move.things[s.id].state)

	if house.kind == "big" then
		-- PUT IT DOWN: his setting down, the other way of his pick-up
		local other: any = nil
		for _, t in plan.spots do
			local def = FurnitureLooks.Items[t.item]
			if not other and t.id ~= s.id and (def.class == "hand" or def.class == "both") and danny.s.move.things[t.id].state == "home" and Rules.canLoad(danny.s.move, t.id) then
				other = t
			end
		end
		local second = b.pieces[other.id]
		danny.body.root.CFrame = CF(origin.Position.X, y, origin.Position.Z + 6)
		give(p, second)
		local w2: Watch = { h = danny, grid = grid, origin = origin, spot = other.id, last = nil, crossed = 0, outRoom = 0, why = nil, stuck = 0, hold = nil,
			faced = false, bent = false, hands = false, tookAt = nil, glide = {}, anchored = true, welded = false }
		watch = w2
		local up = run(90, function()
			return w2.tookAt ~= nil and danny.handle == nil
		end)
		local condition = danny.s.move.things[other.id].condition
		local acts = #E.acts
		E.request(p, "helper", "putdown")
		watch = nil
		local heights: { number } = {}
		local anchored = true
		for _ = 1, 10 do
			if not danny.handle then
				break
			end
			table.insert(heights, second.PrimaryPart.Position.Y)
			anchored = anchored and second.PrimaryPart.Anchored == true
			run(0.1)
		end
		local down = #heights >= 3
		for k = 2, #heights do
			down = down and heights[k] < heights[k - 1]
		end
		local setdown = false
		for k = acts + 1, #E.acts do
			setdown = setdown or (E.acts[k].npc == danny.body.model and E.acts[k].kind == "setdown")
		end
		local size = FurnitureLooks.Items[other.item].size
		check(`{house.name}: PUT IT DOWN: "setdown", the {FurnitureLooks.Items[other.item].name} glides down to the floor over {#heights} steps (anchored), then on the ground there, its condition kept`,
			up and setdown and down and anchored and danny.s.move.things[other.id].state == "ground" and danny.s.move.things[other.id].condition == condition
			and math.abs(second.PrimaryPart.Position.Y - (origin.Position.Y + size.Y / 2)) < 0.05 and danny.body.model:GetAttribute("Carrying") == nil,
			`{up} {setdown} {down} {anchored} {danny.s.move.things[other.id].state}`)

		-- a piece boxed in by others: refused at once
		local target: any = nil
		for _, t in plan.spots do
			local def = FurnitureLooks.Items[t.item]
			if not target and def.class == "hand" and danny.s.move.things[t.id].state == "home" and math.max(def.size.X, def.size.Z) <= 1.6 then
				target = t
			end
		end
		local tr = pieceRect(target)
		local cx, cz = (tr.x0 + tr.x1) / 2, (tr.z0 + tr.z1) / 2
		local hx, hz = (tr.x1 - tr.x0) / 2 + 0.2, (tr.z1 - tr.z0) / 2 + 0.2
		-- (a frame round it: two pieces at its west and east as long as it is, two at its north and south as long as it
		-- and the side pieces together: no corner open; each at least 0.6 thick, so no spot of his outside is within
		-- Route.Stand of it)
		local sides: { any } = {}
		local ends: { any } = {}
		local thickest = 0
		for _, t in plan.spots do
			local def = FurnitureLooks.Items[t.item]
			local long, thick = math.max(def.size.X, def.size.Z), math.min(def.size.X, def.size.Z)
			if t.id ~= target.id and danny.s.move.things[t.id].state == "home" and #sides < 2 and thick >= 0.6 and thick <= 1.6 and long >= 2 * hz + 0.2 then
				table.insert(sides, t)
				thickest = math.max(thickest, thick)
			end
		end
		for _, t in plan.spots do
			local def = FurnitureLooks.Items[t.item]
			local long, thick = math.max(def.size.X, def.size.Z), math.min(def.size.X, def.size.Z)
			if t.id ~= target.id and not table.find(sides, t) and danny.s.move.things[t.id].state == "home" and #ends < 2 and thick >= 0.6
				and long >= 2 * (hx + thickest) + 0.2 then
				table.insert(ends, t)
			end
		end
		local blockers = { ends[1], ends[2], sides[1], sides[2] }
		for k, t in blockers do
			local def = FurnitureLooks.Items[t.item]
			local thick = math.min(def.size.X, def.size.Z)
			local alongX = def.size.X >= def.size.Z -- (its long side along its own X)
			local bx, bz, turn = cx, cz, 0
			if k == 1 or k == 2 then -- (north and south: the long side along X)
				bz = cz + (if k == 1 then 1 else -1) * (hz + thick / 2)
				turn = if alongX then 0 else math.pi / 2
			else -- (west and east: the long side along Z)
				bx = cx + (if k == 3 then 1 else -1) * (hx + thick / 2)
				turn = if alongX then math.pi / 2 else 0
			end
			local at = origin * V3(bx, def.size.Y / 2, bz)
			b.pieces[t.id].PrimaryPart.CFrame = CF(at.X, at.Y, at.Z) * M.CFrame.Angles(0, turn, 0)
		end
		local boxed = b.pieces[target.id]
		local before = #danny.queue
		noticeAt = #E.messages
		give(p, boxed)
		local boxedName = FurnitureLooks.Items[target.item].name
		check(`{house.name}: the {boxedName} boxed in by four pieces (no gap he fits through): refused at once, "Danny can't get to the {boxedName}: clear a way to it first."`,
			#blockers == 4 and #danny.queue == before and boxed:GetAttribute("DannyQueue") == nil
			and told(p, `Danny can't get to the {boxedName}: clear a way to it first.`, noticeAt), `{#blockers} {E.lastNotice(p)}`)
	end
	Moving.admin(p, "end")
	Moving.step()
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
