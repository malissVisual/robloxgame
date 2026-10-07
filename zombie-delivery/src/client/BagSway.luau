--!strict
-- 6.1: the plastic bag in a courier's hand swings behind them (the owner's wish: "the bag just flutters behind you"), on
-- every player's character within Config.Courier.Bag.Range of the camera (yours always), every frame in
-- RunService.PreSimulation. The only writer of the BagSwing joint's Transform (server/KitWear.luau hangs KitBagPivot from
-- the left hand by that Motor6D; client/SprintPose.luau no longer touches it).
--
-- shared/BagSwing.luau is the pendulum: a damped spring driven by the grip's real acceleration (it trails when you start,
-- swings forward when you stop, out on a turn) and the speed's air (it leans back at a run), a flutter and a twist at
-- speed. Here its tilt becomes a world orientation: the bag's broad sides along your facing (its +X to your right, as it
-- hangs), its up axis leaning away from where its bottom has gone, turned about the handles by the twist; the Transform
-- is that orientation seen from the grip (the hand · C0), straight from the hand's frame each frame. (6.0 built it from
-- the pivot's last solved CFrame and its old Transform: any frame the pivot was not solved again compounded the
-- error; with the step jolt at 8 Hz and the flutter on top, the bag jittered and blinked.)
-- A character's joint is looked up once (again when it leaves the body, every LOOK seconds while it has none); out of
-- range or gone, the joint goes back to the identity once and its swing is forgotten.
-- 6.4: each bag swings with its own tuning (the pivot's Bag attribute, Config.Courier.Bags): a tote a little slower,
-- the thermal and the padded bag heavy and boxy, the duffel slow with hardly any flutter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BagSwing = require(Shared.BagSwing)
local Bodies = require(script.Parent.Bodies)

local BagSway = {}

local B = Config.Courier.Bag
local LOOK = 0.4 -- seconds between the looks for a bag on a character that has none
local SWEEP = 5 -- seconds between the clean-ups of the characters that are gone

-- 6.4: every bag's own swing (Config.Courier.Bags over Bag: the bigger, the heavier), made once per bag id. The pivot's
-- Bag attribute (server/KitWear.luau) names the bag in that hand.
local tunings: { [string]: BagSwing.Tuning } = {}
local function tuningOf(pivot: Instance?): BagSwing.Tuning
	local id = if pivot then pivot:GetAttribute("Bag") else nil
	local key = if type(id) == "string" then id else Config.Courier.BagKit
	local made = tunings[key]
	if not made then
		made = BagSwing.tuning(B :: any, Config.Courier.Bags[key])
		tunings[key] = made
	end
	return made
end

type Rec = {
	joint: Motor6D?,
	hand: BasePart?,
	state: BagSwing.State,
	nextLook: number,
	written: boolean, -- a Transform of ours is on the joint
	tuning: BagSwing.Tuning, -- 6.4: this bag's swing
}

local recs: { [Model]: Rec } = {}
local sweptAt = 0
local handVec = { 0, 0, 0 } -- (reused every frame)
local bodyVec = { 0, 0, 0 }

-- The bag's joint on this character (nil without a bag: in a seat, stowed, another hand).
local function find(character: Model): (Motor6D?, BasePart?)
	local pivot = character:FindFirstChild("KitBagPivot")
	local joint = if pivot then pivot:FindFirstChild("BagSwing") else nil
	if joint and joint:IsA("Motor6D") then
		local hand = joint.Part0
		if hand and hand:IsA("BasePart") then
			return joint, hand
		end
	end
	return nil, nil
end

-- Our Transform off the joint (it hangs as the hand holds it), the swing forgotten.
local function release(rec: Rec)
	local joint = rec.joint
	if joint and rec.written and joint.Parent then
		joint.Transform = CFrame.identity
	end
	rec.written = false
	rec.joint, rec.hand = nil, nil
	rec.state = BagSwing.new()
end

local function forget(character: Model)
	local rec = recs[character]
	if rec then
		release(rec)
		recs[character] = nil
	end
end

local function step(dt: number)
	local me = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local now = os.clock()
	for _, player in Bodies.players() do
		local character = player.Character
		if not character then
			continue
		end
		local humanoid, root = Bodies.of(character)
		if not humanoid or not root or (player ~= me and eye ~= nil and (root.Position - eye).Magnitude > B.Range) then
			if recs[character] then
				forget(character)
			end
			continue
		end
		local rec = recs[character]
		if not rec then
			rec = { joint = nil, hand = nil, state = BagSwing.new(), nextLook = 0, written = false, tuning = tuningOf(nil) }
			recs[character] = rec
		end
		local joint, hand = rec.joint, rec.hand
		if joint and (joint.Parent == nil or not hand or hand.Parent ~= character) then
			release(rec) -- (the bag went: put away, rebuilt)
			joint, hand = nil, nil
		end
		if not joint then
			if now < rec.nextLook then
				continue
			end
			rec.nextLook = now + LOOK
			joint, hand = find(character)
			if not joint or not hand then
				continue
			end
			rec.joint, rec.hand = joint, hand
			rec.tuning = tuningOf((joint :: Motor6D).Parent) -- 6.4: the bag that hangs there (a new one is a new joint)
		end
		local grip = (hand :: BasePart).CFrame * (joint :: Motor6D).C0
		local at = grip.Position
		handVec[1], handVec[2], handVec[3] = at.X, at.Y, at.Z
		local velocity = root.AssemblyLinearVelocity
		bodyVec[1], bodyVec[2], bodyVec[3] = velocity.X, velocity.Y, velocity.Z
		local tx, tz, twist = BagSwing.step(rec.state, dt, handVec, bodyVec, rec.tuning)
		-- The world orientation: your facing, the twist about the handles, tilted away from where the bottom went.
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local facing = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		local right = facing:Cross(Vector3.yAxis)
		local want = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis) * CFrame.Angles(0, twist, 0)
		local size = math.sqrt(tx * tx + tz * tz)
		if size > 1e-4 then
			-- (the bottom moved toward (tx, tz): the up axis leans the other way; axis = bottom's way × up)
			local axis = Vector3.new(tx / size, 0, tz / size):Cross(Vector3.yAxis)
			want = CFrame.fromAxisAngle(axis, size) * want
		end
		local transform = grip.Rotation:Inverse() * want
		if transform == transform then -- (never a NaN on a joint)
			(joint :: Motor6D).Transform = transform
			rec.written = true
		end
	end
	if now - sweptAt > SWEEP then
		sweptAt = now
		for character in recs do
			if not character.Parent then
				recs[character] = nil
			end
		end
	end
end

function BagSway.start()
	RunService.PreSimulation:Connect(step)
end

return BagSway
