--!strict
-- 8.1 carrying in two, the leader's side (the owner: "the way Danny helps me is weird: when I turn around he teleports.
-- When we carry something heavy and I need help, we must walk, like, backwards and slowly"). While your character
-- carries a piece with somebody on its other end (Danny or a crew mate: the character attribute PairTurn, the most
-- degrees a second its heading turns, set by server/Moving.luau setHands), your body no longer spins to face where you
-- walk (Humanoid.AutoRotate off): this turns it, and the piece welded in front of it, toward the way at PairTurn at
-- most, the shorter way round (shared/PairCarry.luau steer). A way behind you is walked backwards, facing the piece and
-- your partner, with no turn at all (client/GaitPose.luau's legs walk back: it reads the velocity in the body's frame);
-- a way ahead forwards, your partner backwards. While the heading turns the walk is slower (PairSteer.walk: × the
-- carry's CarrySpeed in client/CameraRig.luau). The far end's carrier is the server's (server/MoveHelper.luau,
-- server/PairHold.luau): only your input and your body's turn are this client's.
-- 8.3 (the owner: "he just jumps weirdly"): no jump while you carry a piece in two (Humanoid.Jump cleared every step
-- before the physics: Space, the touch button): a jump lifted the piece and, until the server aimed again, Danny with it.
-- Nothing is switched off, so nothing has to be given back (a bus ride's own jump lock stays the bus's).
-- 8.3 (the owner: "when I run, he just goes behind me with his arms stretched out"): nobody runs with a move's piece.
-- While your character carries one (MoveCarry) its walk is held at the server's CarrySpeed (× the admin's and the kit's
-- boosts, PairCarry.boost) every step before the physics, whatever wrote Humanoid.WalkSpeed (the sprint's bleed-off,
-- any other script); carrying it in two (the attribute CarryPair, server/Moving.luau setHands: the leader and a crew mate
-- at the far end alike) the run key or button does nothing and says Config.MoveHelper.RunHint once a carry
-- (PairSteer.refuseRun, client/CameraRig.luau: Shift, a gamepad's stick click, the touch SPRINT).
-- 9.0 (the owner, 8.9.3: "Danny carries better now, but only when I walk backwards. When I want to walk forwards,
-- Danny can't walk backwards"): your partner at the far end is the server's, so this screen shows them a moment late,
-- while the piece in your hands moves at once; walking forwards the piece ran into them before they stepped back here.
-- Now, every step: the walk eases in from standing (PairCarry.started, PairStart s), and that start waits while this
-- screen shows the partner nearer than their place (PairCarry.waits: their place the server's character attribute
-- PairFar, in your root's frame; they are PairWith: Danny's MoveHelperId, else a crew mate's UserId); your walk toward
-- them goes once this screen shows the piece reaching them (PairCarry.keep, Config.MoveHelper.PairKeep); and the far
-- end against a wall of the house (the server's PairWall) your walk into that wall goes (PairCarry.wall). The walk
-- changed so is this step's Humanoid:Move (the control script's own comes next frame).
-- 9.2 (the owner, 8.9.5: "the carrying is better, but it feels like it's harder to control … fix it so it's playable";
-- that start took 0.85 s in Studio, 2 s online): Danny at the far end of the piece you lead is YOURS to drive (his model's
-- PairLead your UserId: client/PairLead.luau, server/PairHold.luau lead). Nothing on your screen is late any more, so
-- none of 9.0's start, waits or keep holds your walk: it is the pair's carry speed at once, and the heading turns at
-- Config.MoveHelper.PairLead.Turn (120 degrees a second; the PairTurn attribute's 60 stays a crew mate's), the walk only
-- to PairLead.TurnWalk while it turns. The house's walls at his end are your own rays (PairLead.walk / turn: the part of
-- your walk or turn pushing his end further into a wall goes, along it stays), and after the turn this step sets his
-- goals from your piece (PairLead.step). A crew mate at the far end (the server holds their body) keeps 9.0's way.
--   PairSteer.steering()   does your body carry a piece in two now (CameraRig leaves AutoRotate off)
--   PairSteer.holding()    8.3 does your body hold a piece in two now (the leader or the far end: no run)
--   PairSteer.walk()       × the carry's walk now (1 when it does not steer)
--   PairSteer.cap()        8.3 the most your walk may be now (a move's piece in your hands: CarrySpeed × the boosts), nil
--   PairSteer.refuseRun()  8.3 the run asked while you hold a piece in two: RunHint once a carry (PairSteer.notify, else
--                          client/Hud.luau's toast)
--   PairSteer.step(dt)     one step (the PreSimulation's)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PairCarry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PairCarry"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PairLead = require(script.Parent:WaitForChild("PairLead")) -- 9.2 you drive Danny's end

local PairSteer = {}

PairSteer.notify = nil :: ((text: string) -> ())? -- 8.3 the hint's toast (nil: client/Hud.luau's)

local player = Players.LocalPlayer
local state = PairCarry.newSteer(0)
local steered: Humanoid? = nil -- the humanoid it steers (its AutoRotate off)
local factor = 1
local started = false
local hinted = false -- 8.3 RunHint said for this carry in two
local partner: Model? = nil -- 9.0 the far end's holder (PairWith), found once
local partnerId: number? = nil
local partnerLookAt = 0 -- 9.0 os.clock() of the last look for a holder not found (again PARTNER_AGAIN s later)
local PARTNER_AGAIN = 0.5

-- 9.0 the far end's holder as this screen shows it (PairWith: Danny's body in workspace.Npcs by its MoveHelper id, else
-- that player's character); nil: none, not streamed in (looked for again PARTNER_AGAIN s later).
local function partnerOf(id: any): Model?
	if type(id) ~= "number" then
		partner, partnerId = nil, nil
		return nil
	end
	local model = partner
	if not model or partnerId ~= id or not model.Parent then
		local now = os.clock()
		if partnerId == id and now - partnerLookAt < PARTNER_AGAIN then
			return nil
		end
		partnerLookAt = now
		model = nil
		local other = Players:GetPlayerByUserId(id)
		if other then
			model = other.Character
		else
			local folder = workspace:FindFirstChild("Npcs")
			for _, child in (if folder then folder:GetChildren() else {}) :: { Instance } do
				if child:IsA("Model") and child:GetAttribute("MoveHelper") == id then
					model = child
					break
				end
			end
		end
		partner, partnerId = model, id
	end
	return model
end

-- …its root (nil: none)
local function partnerRoot(id: any): BasePart?
	local model = partnerOf(id)
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- The most degrees a second the heading of what this body carries turns (nil: it carries nothing in two).
local function rateOf(character: Model?): number?
	local value = if character then character:GetAttribute("PairTurn") else nil
	return if type(value) == "number" and value > 0 then value else nil
end

function PairSteer.steering(): boolean
	return rateOf(player.Character) ~= nil
end

-- 8.3 a piece held in two: the leader (PairTurn) or the far end's holder (CarryPair: both, from the server)
local function pairOf(character: Model?): boolean
	return character ~= nil and (character:GetAttribute("CarryPair") == true or rateOf(character) ~= nil)
end

function PairSteer.holding(): boolean
	return pairOf(player.Character)
end

-- 8.3 the most this body may walk with a move's piece in its hands: the server's CarrySpeed × the boosts (nil: none).
local function capOf(character: Model?): number?
	if not character or character:GetAttribute("MoveCarry") == nil then
		return nil
	end
	local speed = character:GetAttribute("CarrySpeed")
	if type(speed) ~= "number" or speed ~= speed or speed < 0 then
		return nil
	end
	return speed * PairCarry.boost(player:GetAttribute("AdminSpeed"), character:GetAttribute("KitSpeed"))
end

function PairSteer.cap(): number?
	return capOf(player.Character)
end

function PairSteer.refuseRun()
	if hinted or not pairOf(player.Character) then
		return
	end
	hinted = true
	local text = Config.MoveHelper.RunHint
	local notify = PairSteer.notify
	if notify then
		notify(text)
		return
	end
	-- (found at run time: client/Hud.luau requires CameraRig, which requires this)
	pcall(function()
		local ok, hud = pcall(require, script.Parent:FindFirstChild("Hud") :: ModuleScript)
		if ok and type(hud) == "table" and type(hud.toast) == "function" then
			hud.toast(text)
		end
	end)
end

function PairSteer.walk(): number
	return if steered then factor else 1
end

-- Its humanoid turns itself to the way again.
local function letGo()
	local humanoid = steered
	steered = nil
	factor = 1
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
	end
end

function PairSteer.step(dt: number)
	local character = player.Character
	local rate = rateOf(character)
	local carried = character ~= nil and character:GetAttribute("MoveCarry") ~= nil
	if not character or (not rate and not carried) then
		-- (8.2 perf: the usual frame, nothing carried: two attribute reads, no lookups)
		if steered then
			letGo()
		end
		hinted = false
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and carried then
		-- 8.3 nobody runs with a move's piece: the walk held at CarrySpeed (× the boosts) right before the physics
		local cap = capOf(character)
		if cap and humanoid.WalkSpeed > cap + 1e-3 then
			humanoid.WalkSpeed = cap
		end
	end
	if not pairOf(character) then
		hinted = false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not rate or not humanoid or not root or not root:IsA("BasePart") or humanoid.SeatPart ~= nil or humanoid.Health <= 0 then
		if steered then
			letGo()
		end
		return
	end
	if steered ~= humanoid then
		letGo()
		steered = humanoid
		state.back = false
	end
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end
	if humanoid.Jump then
		humanoid.Jump = false -- (8.3: two carry it on the ground)
	end
	-- (the body is the truth: a door's trip turns it, and the heading goes on from there)
	local look = root.CFrame.LookVector
	local facing = PairCarry.yawOf(look.X, look.Z)
	state.heading = facing
	local move = humanoid.MoveDirection
	local x, z = move.X, move.Z
	-- 9.2 Danny's end yours to drive (client/PairLead.luau): nothing late, the walk at once, the walls your own rays
	local drive = PairLead.of(partnerOf(character:GetAttribute("PairWith")))
	local wait = false
	if drive then
		x, z = PairLead.walk(drive, x, z)
	else
		-- 9.0 the far end against a wall of the house (PairWall): that part of the walk into the wall goes
		local wall = character:GetAttribute("PairWall")
		if typeof(wall) == "Vector3" then
			x, z = PairCarry.wall(x, z, wall.X, wall.Z)
		end
		-- 9.0 never the piece pushed into your partner as this screen shows them (PairFar: their place, PairWith: them),
		-- the start waiting for them
		local far = character:GetAttribute("PairFar")
		local other = if typeof(far) == "Vector3" then partnerRoot(character:GetAttribute("PairWith")) else nil
		if other and typeof(far) == "Vector3" then
			local place = root.CFrame * far
			local ox, oz = place.X - root.Position.X, place.Z - root.Position.Z
			local length = math.sqrt(ox * ox + oz * oz)
			if length > 0.5 then
				ox, oz = ox / length, oz / length
				local gap = (other.Position.X - place.X) * ox + (other.Position.Z - place.Z) * oz
				wait = PairCarry.waits(x, z, ox, oz, gap)
				x, z = PairCarry.keep(x, z, ox, oz, gap)
			end
		end
	end
	if math.abs(x - move.X) + math.abs(z - move.Z) > 1e-4 then
		humanoid:Move(Vector3.new(x, 0, z), false) -- (this physics step's: the control script's own Move comes next frame)
	end
	if drive then
		-- 9.2 the pair's walk at once, the heading at PairLead.Turn, the part of its turn into a wall at his end gone
		local lead = Config.MoveHelper.PairLead
		factor = PairCarry.steer(state, x, z, dt, math.rad(lead.Turn), false, lead.TurnWalk)
		state.heading = PairLead.turn(drive, facing, state.heading)
	else
		-- 9.0 the walk eases in from standing (PairCarry.started: your screen shows your partner late)
		factor = PairCarry.steer(state, x, z, dt, math.rad(rate), wait) * PairCarry.started(state)
	end
	if math.abs(PairCarry.wrap(state.heading - facing)) > 1e-4 then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, state.heading, 0)
	end
	if drive then
		PairLead.step(drive, dt, root, humanoid) -- 9.2 his goals from your piece, turned already (before the physics)
	end
end

function PairSteer.start()
	if started then
		return
	end
	started = true
	RunService.PreSimulation:Connect(PairSteer.step)
end

return PairSteer
