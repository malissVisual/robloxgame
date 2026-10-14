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
--   PairSteer.start()      its step before every physics step (client/CameraRig.luau's start, on a computer and on a
--                          touch screen)
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

local PairSteer = {}

PairSteer.notify = nil :: ((text: string) -> ())? -- 8.3 the hint's toast (nil: client/Hud.luau's)

local player = Players.LocalPlayer
local state = PairCarry.newSteer(0)
local steered: Humanoid? = nil -- the humanoid it steers (its AutoRotate off)
local factor = 1
local started = false
local hinted = false -- 8.3 RunHint said for this carry in two

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
	factor = PairCarry.steer(state, move.X, move.Z, dt, math.rad(rate))
	if math.abs(PairCarry.wrap(state.heading - facing)) > 1e-4 then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, state.heading, 0)
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
