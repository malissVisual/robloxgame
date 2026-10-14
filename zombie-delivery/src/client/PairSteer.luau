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
--   PairSteer.start()      its step before every physics step (client/CameraRig.luau's start, on a computer and on a
--                          touch screen)
--   PairSteer.steering()   does your body carry a piece in two now (CameraRig leaves AutoRotate off)
--   PairSteer.walk()       × the carry's walk now (1 when it does not steer)
--   PairSteer.step(dt)     one step (the PreSimulation's)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PairCarry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PairCarry"))

local PairSteer = {}

local player = Players.LocalPlayer
local state = PairCarry.newSteer(0)
local steered: Humanoid? = nil -- the humanoid it steers (its AutoRotate off)
local factor = 1
local started = false

-- The most degrees a second the heading of what this body carries turns (nil: it carries nothing in two).
local function rateOf(character: Model?): number?
	local value = if character then character:GetAttribute("PairTurn") else nil
	return if type(value) == "number" and value > 0 then value else nil
end

function PairSteer.steering(): boolean
	return rateOf(player.Character) ~= nil
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
	if not rate or not character then
		-- (8.2 perf: the usual frame, nothing carried in two: one attribute read, no lookups)
		if steered then
			letGo()
		end
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.SeatPart ~= nil or humanoid.Health <= 0 then
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
