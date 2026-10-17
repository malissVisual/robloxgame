-- 9.0 carrying in two with Danny, walked FORWARDS (the owner, 8.9.3: "I noticed Danny carries better now, but only when
-- I walk backwards. When I want to walk forwards, Danny can't walk backwards"; then "and he still teleports", his
-- screenshot: Danny standing inside the Sofa at its far end, The Old Farmstead). 9.2 (the owner, 8.9.5: "the carrying
-- is better, but it feels like it's harder to control … fix it so it's playable"; 8.9.4 held her walk back to hide his
-- lateness on her screen: its start took 0.85 s in Studio, 2 s online): SOL DRIVES HIS END. The real server/Moving.luau,
-- server/MoveHelper.luau and server/PairHold.luau on tests/runtime/MovingRuntime.luau's fakes, Danny's hold the GAME's
-- (MoveHelper.gameMover's keep and free: server/PairHold.luau's constraints on his root), and Sol's client the real
-- client/PairLead.luau (E.leadClient: PairLeadClient.luau) with client/PairSteer.luau's drive branch around it (her walk,
-- PairLead.walk, the heading at PairLead.Turn, PairLead.turn, then PairLead.step). His body is Sol's to simulate
-- (SetNetworkOwner(Sol)): her client sets his constraints' goals every frame before the physics, and the physics here
-- plays Roblox's constraints every frame (1/60 s) on what SHE set: his root toward the AlignPosition's goal along the
-- ground at its MaxVelocity, his height toward the lift's, his turn toward the AlignOrientation's at its
-- MaxAngularVelocity; her own walk is the same physics step (the piece welded to her root moves with it). The server's
-- PairHold Heartbeat and MoveHelper's step (every Tick) run as in the game and must write none of his goals.
-- Her screen shows her own simulation: the piece AND Danny with no lag at any ping (the ping only delays the server's
-- and the others' view of both, together). Two networks all the same: Studio's (ping 0) and an online one (0.15 s).
-- Two pieces at their real sizes (shared/FurnitureLooks.luau): the Sofa (7.2 × 3.2) and the Dining Table (6.0 × 3.8).
-- Sol lifts each with Danny, faces him across it and walks FORWARDS (he must step backwards), straight, then on a
-- curve both ways, stops; then backwards (he follows), and stops.
--   * his body hers (NetworkOwner, his model's PairLead / PairLeadAt / PairLeadPiece; her PairWith, no PairFar, no
--     PairWall), no constraint of his hold reaches into her assembly, the server writes none of his goals meanwhile
--   * he never stands inside the piece (his chest outside its end face along his end's axis), and on her screen he is
--     at his end with ~0 lag once a walk is under way (his root within `lag` studs of his place every frame)
--   * her walk at the pair's carry speed from the very first frame, forwards and backwards, and never held after (8.9.4:
--     eased in over PairStart, waiting for him)
--   * facing the piece all the way, his legs stepping backwards while his end walks away from the piece (Npcs.stride <
--     0, MoveHelperBrain.holdLegs), forwards while it walks toward it; never a step more than his place's own + the
--     glide (no snap); his humanoid kept in the Physics state by her client
--   * an exploit: her client flings him 20 studs off: the server takes him back (MoveHelperBrain.leadKept), holds him
--     itself, walks him back to his end at its hold's speed (never put there)
--   * out of the front door with it (the trip far off the interior): he comes through at his end at once, still hers
--   * down: his constraints gone, his body the server's again, standing (Running), her PairWith gone
-- (On 8.9.4's code: his body the server's, the start eased over PairStart, her screen showed him 0.06 – 0.21 s late.)
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local Map = require("./Map")
local Rules = require("./MovingRules")
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
local L = H.PairLead
local FRAME = 1 / 60
local TICK = 6 -- frames between two of his steps (Config.MoveHelper.Tick 0.1 s)
-- the networks: Sol's ping (the server's view of her client's world that late; her screen her own)
type Net = { name: string, ping: number }
local STUDIO: Net = { name = "Studio, ping 0", ping = 0 }
local ONLINE: Net = { name = "online, ping 0.15 s", ping = 0.15 }
local LAG = 0.12 -- studs: the most his root is off his place on her screen once a walk is under way
local net = STUDIO
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
H.HoldLead.Base, H.HoldLead.Ping = E.gameLead.Base, E.gameLead.Ping -- (the game's lead: a drive needs none)
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
local lead = E.leadClient(sol) -- 9.2 Sol's client/PairLead.luau

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
-- Attachment1 where its part is now), his root toward it at its top speed. (9.2: what Sol's client set while she drives
-- him; the server's after it took him back.)
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

-- One frame: Sol's client (`before`: her walk and turn, his goals), physics (his body toward them; her walk is in
-- `before`'s end: the same step), then the server's scripts (PairHold's Heartbeat; his loop every TICK frames, the
-- move's every 2 TICK), which must write none of his goals while she drives him; `after`: the frame as it is drawn.
local frames = 0
local serverWrote = 0 -- (frames the server wrote his goals while Sol drove him)
local function frame(before: (() -> ())?, after: (() -> ())?)
	frames += 1
	E.clock += FRAME
	if before then
		before()
	end
	physics(FRAME)
	local grip = danny and danny.body and danny.body.grip
	local driven = grip ~= nil and danny.body.root.NetworkOwner == sol
	local was = if grip then grip.align.props.Position else nil
	local wasLift = if grip and grip.lift then grip.lift.props.Position else nil
	local wasMax = if grip then grip.align.MaxVelocity else nil
	heartbeat:Fire(FRAME)
	if frames % TICK == 0 then
		MoveHelper.step(TICK * FRAME)
		if frames % (2 * TICK) == 0 then
			Moving.step()
		end
	end
	if driven and grip and grip.align.props.Parent ~= nil and danny.body.root.NetworkOwner == sol and (grip.align.props.Position ~= was
		or (grip.lift and grip.lift.props.Position ~= wasLift) or grip.align.MaxVelocity ~= wasMax) then
		serverWrote += 1
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
check("Danny comes, Sol's from the start (10.1 free)", danny ~= nil and danny.body ~= nil and danny.hirer == sol)
local body = danny.body
local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
E.place(sol, outside)
promptIn(site, "Enter house").Triggered:Fire(sol)
local character = sol.Character
local humanoid = character:FindFirstChildOfClass("Humanoid")

-- Sol's client, one frame (client/PairSteer.luau's drive branch): her stick (wx, wz) → the walk, the part into a wall at
-- his end gone (PairLead.walk), the heading at PairLead.Turn toward it (PairLead.turn), the piece turned with her root
-- (the weld moves at once), his goals from it (PairLead.step), then her walk this physics step. Returns × the pair's
-- walk (nil: no drive: she has nothing to drive).
local truth: any = nil
local steer: any = nil
local follow: () -> () = function() end
local function client(wx: number, wz: number): number?
	local drive = lead.of(body.model)
	if not drive then
		return nil
	end
	local x, z = lead.walk(drive, wx, wz)
	local facingNow = yawOf(truth)
	steer.heading = facingNow
	local factor = PairCarry.steer(steer, x, z, FRAME, math.rad(L.Turn), false, L.TurnWalk)
	steer.heading = lead.turn(drive, facingNow, steer.heading)
	truth = CF(truth.Position) * M.CFrame.Angles(0, steer.heading, 0)
	E.rootOf(sol).CFrame = truth
	follow()
	local speed = (character:GetAttribute("CarrySpeed") or 0) * factor
	local velocity = V3(x, 0, z) * speed
	E.rootOf(sol).AssemblyLinearVelocity = velocity
	lead.step(drive, FRAME, E.rootOf(sol), humanoid) -- (before the physics: the piece a frame on by her velocity)
	truth = CF(truth.Position + velocity * FRAME) * truth.Rotation -- (her walk: this physics step)
	E.rootOf(sol).CFrame = truth
	follow()
	return factor
end

-- One carry on network `with`: Sol at the piece's +X end facing it, her Lift calls Danny, he walks to the far end and
-- up it goes; then Sol walks forwards (toward him), on a curve, stops, walks backwards, stops.
local function carry(spot: number, name: string, size: any, with: Net, fling: boolean?, door: boolean?)
	net = with
	local title = `{name} ({net.name})`
	local model = itemModel(spot)
	local root = model.PrimaryPart
	local lying = root.CFrame
	local at = lying * V3(size.X / 2 + 1.5, 0, 0)
	E.rootOf(sol).CFrame = M.CFrame.lookAt(V3(at.X, E.rootOf(sol).Position.Y, at.Z), V3(lying.X, E.rootOf(sol).Position.Y, lying.Z))
	E.rootOf(sol).AssemblyLinearVelocity = V3(0, 0, 0)
	Config.CarryGrip.On = true -- (as in the game: his arrival opens no lift check, the steady walk)
	promptIn(model, "Lift").Triggered:Fire(sol)
	local up = run(30, holding)
	Config.CarryGrip.On = false
	check(`{title}: Sol's Lift calls Danny, up it goes with him at its far end`, up and character:GetAttribute("MoveCarry") == spot)
	local weld = E.rootOf(sol).CFrame:ToObjectSpace(root.CFrame)
	follow = function()
		root.CFrame = E.rootOf(sol).CFrame * weld
	end
	truth = E.rootOf(sol).CFrame
	steer = PairCarry.newSteer(yawOf(truth))
	follow()
	run(1, nil, function()
		client(0, 0) -- (standing: her client drives him to his end, a glide)
	end) -- (he settles at his end)
	local axis = danny.holdEnd -- (his end in the piece's frame: decided at the lift)
	local out = axis.Unit -- (his end's way out of the piece's middle)
	local half = math.abs(out.X) * size.X / 2 + math.abs(out.Z) * size.Z / 2 -- (the piece's half length along it)
	local wide = math.abs(out.Z) * size.X / 2 + math.abs(out.X) * size.Z / 2 -- (…and across it)
	local place = half + H.Standoff -- (his root's place out of the middle along it)
	local front = body.root.Size.Z / 2 -- (his chest before his root)

	-- his body hers to drive; the hold's constraints: none with an attachment outside his own body
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
	check(`9.0 {title}: no constraint of his hold reaches into Sol's assembly (one attachment, his own; no reaction force)`,
		grip ~= nil and #reaching == 0 and grip.align.ReactionForceEnabled == false and grip.orient.ReactionTorqueEnabled == false,
		`{#reaching}: {table.concat(reaching, ", ")}`)
	local value = body.model:FindFirstChild("PairLeadPiece")
	local leadAt = body.model:GetAttribute("PairLeadAt")
	check(`9.2 {title}: his body is Sol's to drive (SetNetworkOwner(Sol); PairLead her UserId, PairLeadAt his place, PairLeadPiece the piece)`,
		body.root.NetworkOwner == sol and body.model:GetAttribute("PairLead") == sol.UserId and M.typeof(leadAt) == "CFrame"
		and value ~= nil and value.Value == root and (flat(root.CFrame * leadAt.Position) - flat(root.CFrame * (out * place))).Magnitude < 0.05,
		`{body.root.NetworkOwner} / {body.model:GetAttribute("PairLead")}`)
	check(`9.2 {title}: Sol's client knows him (PairWith: his id) and needs nothing late (no PairFar, no PairWall)`,
		character:GetAttribute("PairWith") == danny.id and character:GetAttribute("PairFar") == nil and character:GetAttribute("PairWall") == nil)
	check(`9.2 {title}: his humanoid in the Physics state, her client keeping it`, body.humanoid.State == "Physics")

	-- Sol's walk, frame by frame: `wx, wz` the way she wants (her stick, a world direction) for `seconds`
	local phase: any = nil
	local lastRoot = body.root.Position
	local lastPlace = flat(root.CFrame * (out * place))
	local strides = #E.strides
	local tickAt = body.root.Position -- (his root at the last of his steps: his end's way between two)
	local tickPlace = flat(root.CFrame * (out * place))
	local function measure()
		local frameNow = root.CFrame -- (the piece: her screen's, the server's a ping later alike)
		local placeNow = flat(frameNow * (out * place))
		-- his chest against the piece's end face, along his end's axis and beside it
		local p = frameNow:PointToObjectSpace(body.root.Position)
		local along = p.X * out.X + p.Z * out.Z
		local aside = math.abs(p.X * out.Z - p.Z * out.X)
		local deep = if aside < wide then half - (along - front) else 0
		phase.deep = math.max(phase.deep, deep)
		if phase.frames >= 6 then -- (under way: a tenth of a second into the leg)
			phase.lag = math.max(phase.lag, (flat(body.root.Position) - placeNow).Magnitude)
		end
		-- a step no longer than his place's own + the glide (no snap)
		local moved = (flat(body.root.Position) - flat(lastRoot)).Magnitude
		phase.jump = math.max(phase.jump, moved - ((placeNow - lastPlace).Magnitude + L.Glide * FRAME + 0.02))
		lastRoot, lastPlace = body.root.Position, placeNow
		-- facing the piece's middle
		local toPiece = flat(frameNow.Position - body.root.Position)
		if toPiece.Magnitude > 0.5 then
			phase.facing = math.min(phase.facing, body.root.CFrame.LookVector:Dot(toPiece.Unit))
		end
		if danny.holdEnd ~= axis then
			phase.flips += 1
		end
		-- his legs: at his steps, against his end's own way along its axis between two of them (away from the piece:
		-- backwards)
		if #E.strides > strides then
			local endWay = flat(frameNow.Rotation * out) -- (his end's way out of the piece, in the world)
			local v = (placeNow - tickPlace) / (TICK * FRAME)
			local alongWay = v:Dot(endWay.Unit)
			for n = strides + 1, #E.strides do
				local s = E.strides[n]
				if s.npc == body.model and math.abs(alongWay) >= H.HoldLegs.From * 2 and math.abs(alongWay) >= 0.7 * v.Magnitude then
					phase.legs += 1
					if (alongWay > 0 and s.speed > 0) or (alongWay < 0 and s.speed < 0) then
						phase.wrongLegs += 1
					end
				end
			end
			strides = #E.strides
			tickAt, tickPlace = body.root.Position, placeNow
		end
		if body.humanoid.State ~= "Physics" then
			phase.state += 1
		end
		phase.frames += 1
	end
	local phases: { any } = {}
	local function leg(label: string, wx: number, wz: number, seconds: number)
		phase = { label = label, deep = 0, lag = 0, jump = 0, facing = 1, flips = 0, legs = 0, wrongLegs = 0, frames = 0, first = nil, least = 1,
			state = 0 }
		table.insert(phases, phase)
		run(seconds, nil, function()
			local factor = client(wx, wz) or 0
			if wx * wx + wz * wz > 0.5 then -- (her walk's share of the pair's: from the first frame on)
				phase.first = phase.first or factor
				phase.least = math.min(phase.least, factor)
			end
		end, measure)
	end
	local f = truth.LookVector -- (toward him across the piece)
	local fx, fz = f.X, f.Z
	local rx, rz = -fz, fx -- (her right)
	local s2 = math.sqrt(0.5)
	leg("forwards", fx, fz, 3.5)
	body.humanoid.State = "Running" -- (his state machine slipped on her client: hers to put back)
	leg("stop", 0, 0, 1)
	leg("forwards, a curve right", (fx + rx) * s2, (fz + rz) * s2, 2.5)
	leg("forwards, a curve left", (fx - rx) * s2, (fz - rz) * s2, 2.5)
	leg("stop", 0, 0, 1)
	local b = truth.LookVector -- (her facing now: straight behind her)
	leg("backwards", -b.X, -b.Z, 3)
	leg("stop", 0, 0, 1.5)
	if door then
		-- 9.2 out of the front door with it (Leave house: the trip puts Sol and her piece outside at once, far off the
		-- interior): his place far off, her client puts him there (PairLead.Jump; the server's snap too), still hers
		local origin = E.interiors[#E.interiors]
		local exitAt = origin * V3(0, 3, 0.5)
		run(5, function()
			return (flat(E.rootOf(sol).Position) - flat(exitAt)).Magnitude < 5
		end, function()
			local to = flat(exitAt - truth.Position)
			local unit = if to.Magnitude > 1e-3 then to.Unit else V3(0, 0, 0)
			client(unit.X, unit.Z)
		end)
		local inside = E.rootOf(sol).Position
		promptIn(workspace, "Leave house").Triggered:Fire(sol)
		truth = E.rootOf(sol).CFrame
		follow()
		local came = run(1, function()
			return (flat(body.root.Position) - flat(root.CFrame * (out * place))).Magnitude < 0.05
		end, function()
			client(0, 0)
		end)
		check(`9.2 {title}: out of the front door with it: he comes through at his end at once, his body still hers to drive (no take-back)`,
			(E.rootOf(sol).Position - inside).Magnitude > 200 and came and holding() and body.root.NetworkOwner == sol
			and body.model:GetAttribute("PairLead") == sol.UserId, (E.rootOf(sol).Position - inside).Magnitude)
		lastRoot, lastPlace = body.root.Position, flat(root.CFrame * (out * place))
		tickPlace, strides = lastPlace, #E.strides
		local o = truth.LookVector
		leg("outside, forwards", o.X, o.Z, 2)
		leg("stop", 0, 0, 1)
	end
	local worst = { deep = 0, lag = 0, jump = 0, facing = 1, flips = 0, legs = 0, wrongLegs = 0, first = 1, least = 1, state = 0 }
	local rows: { string } = {}
	for _, p in phases do
		local straight = p.label == "forwards" or p.label == "backwards"
		worst.deep, worst.lag, worst.jump = math.max(worst.deep, p.deep), math.max(worst.lag, p.lag), math.max(worst.jump, p.jump)
		worst.facing = math.min(worst.facing, p.facing)
		worst.flips, worst.legs, worst.wrongLegs, worst.state = worst.flips + p.flips, worst.legs + p.legs, worst.wrongLegs + p.wrongLegs, worst.state + p.state
		if straight then -- (a curve's turn slows the walk: PairLead.TurnWalk)
			worst.first = math.min(worst.first, p.first or 0)
			worst.least = math.min(worst.least, p.least)
		end
		table.insert(rows, string.format("%s: in it %.2f, off his place on her screen %.3f, walk %s at once, facing %.2f, legs %d/%d wrong",
			p.label, p.deep, p.lag, if p.first then string.format("%.2f", p.first) else "-", p.facing, p.wrongLegs, p.legs))
	end
	print(`   {title}, Danny driven by her client (0 s late on her screen):\n      ` .. table.concat(rows, "\n      "))
	check(`9.0 {title}: his body never goes into the piece (his chest outside its end face), forwards, on a curve, backwards, stopping`,
		worst.deep <= 0.02, string.format("%.2f studs in", worst.deep))
	check(`9.2 {title}: on her screen he is at his end with ~0 lag once a walk is under way (within {LAG} studs of his place every frame)`,
		worst.lag <= LAG, string.format("%.3f studs off", worst.lag))
	check(`9.2 {title}: her walk at the pair's carry speed from the very first frame, forwards and backwards (no PairStart, no wait), never held after`,
		worst.first >= 0.999 and worst.least >= 0.999, string.format("%.2f at once, %.2f the least", worst.first, worst.least))
	check(`9.0 {title}: never a step more than his place's own and the glide (no snap), his end never another one`, worst.jump <= 1e-3 and worst.flips == 0,
		string.format("%.3f studs over, %d flips", worst.jump, worst.flips))
	check(`9.0 {title}: he faces the piece all the way (never his back to it)`, worst.facing >= 0.9, string.format("%.2f", worst.facing))
	check(`9.0 {title}: his legs step backwards while his end walks away from the piece, forwards while it comes toward it (Npcs.stride)`,
		worst.legs >= 20 and worst.wrongLegs == 0, `{worst.wrongLegs} of {worst.legs} the wrong way`)
	check(`9.2 {title}: the server wrote none of his goals while she drove him; his humanoid kept in Physics by her client (a slip put back at once)`,
		serverWrote == 0 and worst.state <= 1, `{serverWrote} frames written, {worst.state} frames not in Physics`)
	if door then
		check(`9.2 {title}: …and outside, after a walk and a stop, still hers to drive (the server's look found nothing wrong, his height its own again)`,
			body.root.NetworkOwner == sol and body.model:GetAttribute("PairLead") == sol.UserId and holding()
			and math.abs(danny.holdOffset.Y - (body.root.Position.Y - root.Position.Y)) < H.HoldStep)
	end
	if fling then
		-- an exploit: her client flings his body 20 studs off his end (his constraints hers to aim) every frame
		local flung = 0
		local taken = run(4, function()
			return body.root.NetworkOwner ~= sol
		end, function()
			if body.root.NetworkOwner == sol then
				local away = (root.CFrame * (out * place)) + V3(20, 0, 0)
				body.grip.align.Position = away
				body.grip.align.MaxVelocity = L.Rigid
				flung += 1
			end
		end)
		check(`9.2 {title}: an exploit flings him 20 studs off his end: within PairLead.Grace s the server takes his body back (PairLead gone, the drive off, PairFar again)`,
			taken and flung * FRAME <= L.Grace + 0.25 and body.model:GetAttribute("PairLead") == nil and body.model:FindFirstChild("PairLeadPiece") == nil
			and lead.of(body.model) == nil and holding(), `{flung * FRAME} s`)
		local over, lastAt = 0, body.root.Position
		local back = run(6, function()
			return (flat(body.root.Position) - flat(root.CFrame * (out * place))).Magnitude < 0.3
		end, nil, function()
			local moved = (flat(body.root.Position) - flat(lastAt)).Magnitude
			over = math.max(over, moved - (body.grip.align.MaxVelocity * FRAME + 1e-6))
			lastAt = body.root.Position
		end)
		check(`9.2 {title}: …the server's hold walks him back to his end at its top speed (never put there), still holding`,
			back and over <= 1e-6 and holding() and character:GetAttribute("PairFar") ~= nil, string.format("%.3f over", over))
	end
	E.Net.get("PutDown").OnServerEvent:Fire(sol)
	run(0.5)
	check(`{title}: down: both pairs of hands free, his hold's constraints gone, his body the server's again, standing; Sol's PairWith / PairFar / PairWall gone`,
		character:GetAttribute("MoveCarry") == nil and not holding() and body.grip == nil and body.root.NetworkOwner == false
		and body.model:GetAttribute("PairLead") == nil and body.humanoid.State == "Running" and character:GetAttribute("PairWith") == nil
		and character:GetAttribute("PairFar") == nil and character:GetAttribute("PairWall") == nil)
	return model
end

carry(3, "the Sofa", SOFA, STUDIO, true)
carry(3, "the Sofa", SOFA, ONLINE)
carry(6, "the Dining Table", TABLE, STUDIO)
carry(6, "the Dining Table", TABLE, ONLINE, false, true)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
