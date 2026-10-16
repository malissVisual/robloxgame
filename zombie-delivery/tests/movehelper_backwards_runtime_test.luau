-- 9.0 carrying in two with Danny, walked FORWARDS (the owner, 8.9.3: "I noticed Danny carries better now, but only when
-- I walk backwards. When I want to walk forwards, Danny can't walk backwards"; then "and he still teleports", his
-- screenshot: Danny standing inside the Sofa at its far end, The Old Farmstead). The real server/Moving.luau,
-- server/MoveHelper.luau and server/PairHold.luau on tests/runtime/MovingRuntime.luau's fakes, the game's lead
-- (Config.MoveHelper.HoldLead), and Danny's hold the GAME's: MoveHelper.gameMover's keep and free (server/PairHold.luau's
-- constraints on his root), played here as Roblox plays them every frame (1/60 s): his root toward the AlignPosition's
-- goal along the ground at its MaxVelocity, his height toward the lift's, his turn toward the AlignOrientation's at its
-- MaxAngularVelocity; PairHold's own step every Heartbeat, MoveHelper's every Tick. The piece is welded to Sol (its frame
-- from her root kept every frame). Sol's client is client/PairSteer.luau's step (shared/PairCarry.luau: the wall, the
-- start waiting for him, never the piece pushed into him as her screen shows him, the walk eased in, the heading
-- turned). Her screen shows the piece at once (welded to her body, her own) and Danny as the server had him
-- Brain.leadTime(ping) s before (the lead's own model of her screen). Two networks: Studio's (ping 0, where the owner
-- plays) and an online one (ping 0.15 s).
-- Two pieces at their real sizes (shared/FurnitureLooks.luau): the Sofa (7.2 × 3.2) and the Dining Table (6.0 × 3.8).
-- Sol lifts each with Danny, faces him across it and walks FORWARDS (he must step backwards), straight, then on a
-- curve both ways, stops; then backwards (he follows), and stops.
--   * no constraint of his hold reaches into Sol's assembly (the piece welded to her root): his AlignPosition and
--     AlignOrientation have one attachment, his own, their goals set by the server (a constraint between his body and
--     her piece makes one mechanism of the two: one network owner for both, his server-owned body and her own fighting)
--   * on the server his body never goes into the piece (his chest, his root's half depth before it, outside the
--     piece's end face along his end's axis), never a step longer than his top speed × dt (no snap), his end never
--     another one
--   * on her screen the piece never runs into his body (FORWARDS: the start, the walk, the turns, the stop) by more
--     than `screen` studs, nor does he stand in it after a stop; his hands within `keep` studs of its edge once a walk
--     is under way (his body never in the piece: following her his hands reach on, Config.MoveHelper.Edge.Reach)
--   * her walk under way (90% of the pair's) within `under` s of a start, forwards and backwards, and no stall after
--   * facing the piece all the way (never his back to it), his legs stepping backwards while his end walks away from
--     the piece (Npcs.stride < 0, MoveHelperBrain.holdLegs), forwards while it walks toward it
-- On 8.9.3's code (both constraints' Attachment1 on the piece, his lead 2.26 studs toward the piece's middle following
-- her at a ping of 0.15 s, the walk at once from standing): 2 constraints reach into her assembly; on the server his
-- chest 2.16 studs inside the Sofa after she walked backwards and stopped (the screenshot); walking forwards the piece
-- 2.42 studs into his body on her screen.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local Map = require("./Map")
local Rules = require("./MovingRules")
local Brain = require("./MoveHelperBrain")
local PairCarry = require("./PairCarry") -- (client/PairSteer.luau's steering)
local FurnitureLooks = require("./FurnitureLooks")

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
local FRAME = 1 / 60
local TICK = 6 -- frames between two of his steps (Config.MoveHelper.Tick 0.1 s)
-- the networks: Sol's ping; the most the piece comes into his body on her screen, his hands off its edge once under way,
-- the seconds her walk takes to get under way
type Net = { name: string, ping: number, screen: number, keep: number, under: number }
local STUDIO: Net = { name = "Studio, ping 0", ping = 0, screen = 0.3, keep = 0.75, under = 1.2 }
local ONLINE: Net = { name = "online, ping 0.15 s", ping = 0.15, screen = 0.35, keep = 1.75, under = 2.5 }
local net = STUDIO
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
H.HoldLead.Base, H.HoldLead.Ping = E.gameLead.Base, E.gameLead.Ping -- (the game's lead)
T.Doors.Walk = false -- (the walk-in doors off: these walks stay in the house)
local SOFA = FurnitureLooks.Items.sofa.size
local TABLE = FurnitureLooks.Items.dining_table.size
E.items.sofa.size = V3(SOFA.X, SOFA.Y, SOFA.Z) -- (the runtime's sofa and slab at the real Sofa's and Dining Table's sizes)
E.items.slab.size = V3(TABLE.X, TABLE.Y, TABLE.Z)
E.items.slab.name = "Dining Table"

local home = Map.home(T.Contracts[1].home) :: any
local door = V3(home.door.x, 3, home.door.z)
local facing = V3(home.facing.x, 0, home.facing.z)
local outside = door + facing * 3
E.truckAt = V3(home.door.x + 30, 2, home.door.z - 20)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0)
end

-- His own walk (to her call): straight toward the point, speed × dt a step. Holding: the game's keep and free.
local gameMover = MoveHelper.gameMover
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
	keep = gameMover.keep,
	free = gameMover.free,
})

local sol = E.player(44, "Sol", V3(Map.Depot.x, 3, Map.Depot.z))
sol.GetNetworkPing = function()
	return net.ping
end
Moving.useArt(E.art)
Moving.start()
local heartbeat = E.game:GetService("RunService").Heartbeat

local function promptIn(model: any, action: string?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and (action == nil or d.ActionText == action or string.find(tostring(d.ActionText), action, 1, true) == 1) then
			return d
		end
	end
	return nil
end
local function itemModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function flat(v: any): any
	return V3(v.X, 0, v.Z)
end
local function yawOf(frame: any): number
	local look = frame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end
local danny: any = nil
local function holding(): boolean
	return select(2, Rules.holding(danny.s.move, danny.id)) == "helper"
end

-- Roblox's constraints on his root, one frame: the goal of each (one attachment: its own Position / CFrame; two: its
-- Attachment1 where its part is now), his root toward it at its top speed.
local function goalOf(c: any): any?
	if c.props.Mode == "OneAttachment" then
		return if c.ClassName == "AlignOrientation" then c.props.CFrame else CF(c.props.Position.X, c.props.Position.Y, c.props.Position.Z)
	end
	local a1 = c.props.Attachment1
	local part = a1 and a1.props.Parent
	return if part then part.CFrame * (a1.props.CFrame or CF()) else nil
end
local function physics(dt: number)
	local body = danny and danny.body
	local grip = body and body.grip
	if not grip or grip.align.props.Parent == nil or grip.align.props.Enabled == false then
		return
	end
	local root = body.root
	local here = root.CFrame
	local p = here.Position
	local x, y, z = p.X, p.Y, p.Z
	local goal = goalOf(grip.align)
	if goal then
		local dx, dz = goal.Position.X - x, goal.Position.Z - z
		local d = math.sqrt(dx * dx + dz * dz)
		local most = grip.align.MaxVelocity * dt
		if d > most then
			dx, dz = dx / d * most, dz / d * most
		end
		x, z = x + dx, z + dz
	end
	local lift = grip.lift
	if lift then
		local most = lift.MaxVelocity * dt
		y += math.clamp(lift.props.Position.Y - y, -most, most)
	end
	local yaw = yawOf(here)
	local turn = goalOf(grip.orient)
	if turn then
		yaw = PairCarry.turn(yaw, yawOf(turn), grip.orient.MaxAngularVelocity, dt)
	end
	root.CFrame = CF(x, y, z) * M.CFrame.Angles(0, yaw, 0)
end

-- One frame: Sol's walk (`before`), physics, then the scripts (PairHold's Heartbeat; his loop every TICK frames, the
-- move's every 2 TICK); `after`: the frame as it is drawn.
local frames = 0
local function frame(before: (() -> ())?, after: (() -> ())?)
	frames += 1
	E.clock += FRAME
	if before then
		before()
	end
	physics(FRAME)
	heartbeat:Fire(FRAME)
	if frames % TICK == 0 then
		MoveHelper.step(TICK * FRAME)
		if frames % (2 * TICK) == 0 then
			Moving.step()
		end
	end
	if after then
		after()
	end
end
local function run(seconds: number, done: (() -> boolean)?, before: (() -> ())?, after: (() -> ())?): boolean
	for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
		frame(before, after)
		if done and done() then
			return true
		end
	end
	return done == nil
end

local started = Moving.admin(sol, "start")
check("a solo move starts", string.find(started, "started", 1, true) ~= nil, started)
Moving.step()
danny = MoveHelper.find(sol)
E.request(sol, "helper", "hire")
check("Danny comes, Sol hires him", danny ~= nil and danny.body ~= nil and danny.hirer == sol)
local body = danny.body
local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
E.place(sol, outside)
promptIn(site, "Enter house").Triggered:Fire(sol)
local character = sol.Character

-- One carry on network `with`: Sol at the piece's +X end facing it, her Lift calls Danny, he walks to the far end and
-- up it goes; then Sol walks forwards (toward him), on a curve, stops, walks backwards, stops.
local function carry(spot: number, name: string, size: any, with: Net)
	net = with
	local late = math.floor(Brain.leadTime(net.ping) / FRAME + 0.5) -- (frames her screen shows him late)
	local title = `{name} ({net.name})`
	local model = itemModel(spot)
	local root = model.PrimaryPart
	local lying = root.CFrame
	local at = lying * V3(size.X / 2 + 1.5, 0, 0)
	E.rootOf(sol).CFrame = M.CFrame.lookAt(V3(at.X, E.rootOf(sol).Position.Y, at.Z), V3(lying.X, E.rootOf(sol).Position.Y, lying.Z))
	Config.CarryGrip.On = true -- (as in the game: his arrival opens no lift check, the steady walk)
	promptIn(model, "Lift").Triggered:Fire(sol)
	local up = run(30, holding)
	Config.CarryGrip.On = false
	check(`{title}: Sol's Lift calls Danny, up it goes with him at its far end`, up and character:GetAttribute("MoveCarry") == spot)
	local weld = E.rootOf(sol).CFrame:ToObjectSpace(root.CFrame)
	local function follow()
		root.CFrame = E.rootOf(sol).CFrame * weld
	end
	follow()
	run(1, nil, follow) -- (he settles at his end)
	local axis = danny.holdEnd -- (his end in the piece's frame: decided at the lift)
	local out = axis.Unit -- (his end's way out of the piece's middle)
	local half = math.abs(out.X) * size.X / 2 + math.abs(out.Z) * size.Z / 2 -- (the piece's half length along it)
	local wide = math.abs(out.Z) * size.X / 2 + math.abs(out.X) * size.Z / 2 -- (…and across it)
	local place = half + H.Standoff -- (his root's place out of the middle along it)
	local front = body.root.Size.Z / 2 -- (his chest before his root)

	-- the hold's constraints: none with an attachment outside his own body
	local grip = body.grip
	local reaching: { string } = {}
	for _, c in body.root:GetChildren() do
		if c.ClassName == "AlignPosition" or c.ClassName == "AlignOrientation" then
			local a1 = c.props.Attachment1
			if c.props.Mode ~= "OneAttachment" and a1 and a1.props.Parent and not a1.props.Parent:IsDescendantOf(body.model) then
				table.insert(reaching, `{c.ClassName} → {a1.props.Parent.Name}`)
			end
		end
	end
	check(`9.0 {title}: no constraint of his hold reaches into Sol's assembly (one attachment, his own; the server sets their goals)`,
		grip ~= nil and #reaching == 0, `{#reaching}: {table.concat(reaching, ", ")}`)
	check(`9.0 {title}: Sol's client knows him (PairWith: his id) and his place (PairFar, in her root's frame: the far end of the piece)`,
		character:GetAttribute("PairWith") == danny.id and M.typeof(character:GetAttribute("PairFar")) == "Vector3"
		and (flat(E.rootOf(sol).CFrame * character:GetAttribute("PairFar")) - flat(root.CFrame * (out * place))).Magnitude < 0.6,
		character:GetAttribute("PairFar"))

	-- Sol's walk, frame by frame: `wx, wz` the way she wants (her stick, a world direction) for `seconds`
	local truth = E.rootOf(sol).CFrame
	local steer = PairCarry.newSteer(yawOf(truth))
	local seen: { any } = {} -- (his root, frame by frame: her screen shows the one `late` frames back)
	local reaches: { number } = {} -- (…and his hands' reach on)
	local phase: any = nil
	local lastRoot = body.root.Position
	local strides = #E.strides
	local edge = H.Edge
	local function reachNow(): number -- (his hands' reach on past the edge's usual place: his CarryAt)
		local carryAt = body.model:GetAttribute("CarryAt")
		return if M.typeof(carryAt) == "Vector3" then -carryAt.Z - (H.Standoff + edge.Depth / 2) else 0
	end
	local function measure()
		local frameNow = root.CFrame -- (the piece: the same on her screen and on the server)
		table.insert(seen, body.root.CFrame)
		table.insert(reaches, reachNow())
		phase.reach = math.max(phase.reach, reaches[#reaches])
		local shown = seen[math.max(1, #seen - late)]
		local shownReach = reaches[math.max(1, #reaches - late)]
		-- his chest against the piece's end face, along his end's axis and beside it
		local function into(r: any): (number, number)
			local p = frameNow:PointToObjectSpace(r.Position)
			local along = p.X * out.X + p.Z * out.Z
			local aside = math.abs(p.X * out.Z - p.Z * out.X)
			return if aside < wide then half - (along - front) else 0, along - place
		end
		local deep = into(body.root.CFrame)
		local shownDeep, off = into(shown)
		phase.deep = math.max(phase.deep, deep)
		phase.shownDeep = math.max(phase.shownDeep, shownDeep)
		if phase.frames >= 45 then -- (under way: 0.75 s into the leg; his hands off the edge: his body's off less their reach)
			phase.off = math.max(phase.off, math.abs(off - shownReach))
		end
		-- a step no longer than his top speed × dt (no snap)
		local moved = (flat(body.root.Position) - flat(lastRoot)).Magnitude
		phase.jump = math.max(phase.jump, moved - (grip.align.MaxVelocity * FRAME + 1e-6))
		lastRoot = body.root.Position
		-- facing the piece's middle
		local toPiece = flat(frameNow.Position - body.root.Position)
		if toPiece.Magnitude > 0.5 then
			phase.facing = math.min(phase.facing, body.root.CFrame.LookVector:Dot(toPiece.Unit))
		end
		if danny.holdEnd ~= axis then
			phase.flips += 1
		end
		-- his legs: at his steps, against his end's own way along its axis (away from the piece: backwards)
		for n = strides + 1, #E.strides do
			local s = E.strides[n]
			if s.npc == body.model then
				local endWay = flat(frameNow.Rotation * out) -- (his end's way out of the piece, in the world)
				local v = flat(V3(danny.trail.evx, 0, danny.trail.evz))
				local along = v:Dot(endWay.Unit)
				if math.abs(along) >= H.HoldLegs.From * 2 and math.abs(along) >= 0.7 * v.Magnitude then -- (his end mostly along its axis)
					phase.legs += 1
					if (along > 0 and s.speed > 0) or (along < 0 and s.speed < 0) then
						phase.wrongLegs += 1
					end
				end
			end
		end
		strides = #E.strides
		phase.frames += 1
	end
	local phases: { any } = {}
	local function leg(label: string, wx: number, wz: number, seconds: number)
		phase = { label = label, deep = 0, shownDeep = 0, off = 0, jump = 0, facing = 1, flips = 0, legs = 0, wrongLegs = 0, frames = 0,
			upAt = math.huge, dip = 1, reach = 0 }
		table.insert(phases, phase)
		run(seconds, nil, function()
			-- client/PairSteer.luau's step on her screen: the wall (PairWall), the start waiting for him and never the
			-- piece pushed into him as her screen shows him (PairFar, PairWith), the walk eased in, the heading turned
			steer.heading = yawOf(truth)
			local x, z = wx, wz
			local wall = character:GetAttribute("PairWall")
			if M.typeof(wall) == "Vector3" then
				x, z = PairCarry.wall(x, z, wall.X, wall.Z)
			end
			local far = character:GetAttribute("PairFar")
			local shown = seen[math.max(1, #seen - late)]
			local wait = false
			if M.typeof(far) == "Vector3" and shown and character:GetAttribute("PairWith") == danny.id then
				local farAt = truth * far
				local ox, oz = farAt.X - truth.Position.X, farAt.Z - truth.Position.Z
				local length = math.sqrt(ox * ox + oz * oz)
				if length > 0.5 then
					ox, oz = ox / length, oz / length
					local gap = (shown.Position.X - farAt.X) * ox + (shown.Position.Z - farAt.Z) * oz
					wait = PairCarry.waits(x, z, ox, oz, gap)
					x, z = PairCarry.keep(x, z, ox, oz, gap)
				end
			end
			local factor = PairCarry.steer(steer, x, z, FRAME, math.rad(H.PairTurn), wait) * PairCarry.started(steer)
			local speed = (character:GetAttribute("CarrySpeed") or 0) * factor
			if wx * wx + wz * wz > 0.5 then -- (her walk's share of the pair's: when it got under way, the least after)
				local share = math.sqrt(x * x + z * z) * factor
				if phase.upAt == math.huge and share >= 0.9 then
					phase.upAt = phase.frames * FRAME
				elseif phase.upAt < math.huge then
					phase.dip = math.min(phase.dip, share)
				end
			end
			truth = CF(truth.Position + V3(x, 0, z) * speed * FRAME) * M.CFrame.Angles(0, steer.heading, 0)
			E.rootOf(sol).CFrame = truth
			follow()
		end, measure)
	end
	local f = truth.LookVector -- (toward him across the piece)
	local fx, fz = f.X, f.Z
	local rx, rz = -fz, fx -- (her right)
	local s2 = math.sqrt(0.5)
	leg("forwards", fx, fz, 3.5)
	leg("stop", 0, 0, 1)
	leg("forwards, a curve right", (fx + rx) * s2, (fz + rz) * s2, 2.5)
	leg("forwards, a curve left", (fx - rx) * s2, (fz - rz) * s2, 2.5)
	leg("stop", 0, 0, 1)
	leg("backwards", -fx, -fz, 3)
	leg("stop", 0, 0, 1.5)
	local worst = { deep = 0, shownDeep = 0, off = 0, jump = 0, facing = 1, flips = 0, legs = 0, wrongLegs = 0, upAt = 0, dip = 1, reach = 0 }
	local rows: { string } = {}
	for _, p in phases do
		local straight = p.label == "forwards" or p.label == "backwards"
		for key, value in worst do
			if key == "facing" then
				worst.facing = math.min(value, p.facing)
			elseif key == "upAt" or key == "dip" then
				if straight then -- (a curve's turn slows the walk: PairTurnWalk)
					worst.upAt = math.max(worst.upAt, p.upAt)
					worst.dip = math.min(worst.dip, p.dip)
				end
			elseif key == "flips" or key == "legs" or key == "wrongLegs" then
				worst[key] = value + p[key]
			else
				worst[key] = math.max(value, p[key])
			end
		end
		table.insert(rows, string.format("%s: in it %.2f, on her screen %.2f, hands off the edge %.2f, under way %s s, facing %.2f, legs %d/%d wrong",
			p.label, p.deep, p.shownDeep, p.off, if p.upAt < math.huge then string.format("%.2f", p.upAt) else "-", p.facing, p.wrongLegs, p.legs))
	end
	print(`   {title}, Danny shown {Brain.leadTime(net.ping)} s late on her screen:\n      ` .. table.concat(rows, "\n      "))
	check(`9.0 {title}: on the server his body never goes into the piece (his chest outside its end face), forwards, on a curve, backwards, stopping`,
		worst.deep <= 0.02, string.format("%.2f studs in", worst.deep))
	check(`9.0 {title}: on Sol's screen the piece never runs into his body by more than {net.screen} studs (walking forwards: he steps back in time), nor is he left in it at a stop`,
		worst.shownDeep <= net.screen, string.format("%.2f studs in", worst.shownDeep))
	check(`9.0 {title}: on her screen he keeps his end once a walk is under way (his hands within {net.keep} studs of its edge; reaching on {edge.Reach} studs at most)`,
		worst.off <= net.keep and worst.reach <= edge.Reach + 0.05, string.format("%.2f studs off, %.2f reach", worst.off, worst.reach))
	check(`9.0 {title}: her walk under way (90% of the pair's) within {net.under} s, forwards and backwards, and no stall after (80% at least)`,
		worst.upAt <= net.under and worst.dip >= 0.8, string.format("%.2f s, %.2f after", worst.upAt, worst.dip))
	check(`9.0 {title}: never a step longer than his top speed (no snap), his end never another one`, worst.jump <= 1e-3 and worst.flips == 0,
		string.format("%.3f studs over, %d flips", worst.jump, worst.flips))
	check(`9.0 {title}: he faces the piece all the way (never his back to it)`, worst.facing >= 0.9, string.format("%.2f", worst.facing))
	check(`9.0 {title}: his legs step backwards while his end walks away from the piece, forwards while it comes toward it (Npcs.stride)`,
		worst.legs >= 20 and worst.wrongLegs == 0, `{worst.wrongLegs} of {worst.legs} the wrong way`)
	E.Net.get("PutDown").OnServerEvent:Fire(sol)
	run(0.5)
	check(`{title}: down: both pairs of hands free, his hold's constraints gone, Sol's PairWith / PairFar / PairWall gone`,
		character:GetAttribute("MoveCarry") == nil and not holding() and body.grip == nil and character:GetAttribute("PairWith") == nil
		and character:GetAttribute("PairFar") == nil and character:GetAttribute("PairWall") == nil)
	return model
end

carry(3, "the Sofa", SOFA, STUDIO)
carry(3, "the Sofa", SOFA, ONLINE)
carry(6, "the Dining Table", TABLE, STUDIO)
carry(6, "the Dining Table", TABLE, ONLINE)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
