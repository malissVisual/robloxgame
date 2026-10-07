--!strict
-- 5.1: the rider on a bike (the DriverSeat of a car with the attribute Bike, server/Vehicles.luau). Over the sit
-- animation: the upper body leans a little forward, both arms reach forward to the grips (the elbows soft) and the
-- legs pump with the crank, the thighs lowered toward the pedals. client/CarVisuals.luau calls BikeRider.pose every
-- frame for each rider near the camera (with the bike's crank angle) and BikeRider.release when they get off or go
-- out of range. Everybody sees the same pose from the same crank.
-- The pose goes into the R15 joints' Transform (shared/Joints.luau: Motor6Ds or AnimationConstraints; C0 is never
-- written), laid ON TOP of what the Animator wrote this frame. A joint the Animator left alone this frame still holds
-- our value: its last animated value is the base then, so the pose never piles up on itself. While the rider aims a
-- gun (the Aiming attribute: client/ArmPose.luau raises the arms) the arms are left to the aim. R6 bodies keep the
-- plain sit.
-- 5.1.1, the E-Scooter (the car's attribute BikeStand): the rider STANDS on the deck (its DriverSeat sits a hip's
-- height over it): the legs straightened out of the sit, a slight forward lean, both hands on the bar, no pedalling.
-- The angles of both poses are shared/RiderPose.luau's (pure, tested).
-- 5.8.2: the standing rider is posed ABSOLUTE (from the rest pose, not on top of the sit animation, which bent the legs
-- through the deck and threw the arms up on some avatars): straight legs, the body raised or lowered on its Root joint
-- until the lower foot rests on the scooter's Deck point (measured every frame, so any leg length stands right), and
-- the hands on the bar's LeftGrip / RightGrip points (RiderPose.armIk, a two-bone reach).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Joints = require(Shared:WaitForChild("Joints"))
local RiderPose = require(Shared:WaitForChild("RiderPose"))

local BikeRider = {}

-- The joints posed: { part, joint }.
local ARMS = {
	{ "RightUpperArm", "RightShoulder" },
	{ "RightLowerArm", "RightElbow" },
	{ "LeftUpperArm", "LeftShoulder" },
	{ "LeftLowerArm", "LeftElbow" },
}
local BODY = {
	{ "UpperTorso", "Waist" },
	{ "RightUpperLeg", "RightHip" },
	{ "RightLowerLeg", "RightKnee" },
	{ "LeftUpperLeg", "LeftHip" },
	{ "LeftLowerLeg", "LeftKnee" },
}

local written: { [Instance]: CFrame } = {}
local animated: { [Instance]: CFrame } = {}
local riders: { [Model]: { any } } = {} -- the joints posed on each rider (released on the way off)
local lifts: { [Model]: number } = {} -- 5.8.2: a standing rider's Root lift (studs), corrected toward the deck
local absolute: { [Instance]: boolean } = {} -- 5.9.1: the joints posed absolute (given back to the rest pose, not a sit)
local watching: RBXScriptConnection? = nil -- 5.9.1: lets go of riders whose scooter vanished under them


-- The animation's own value of a joint this frame.
local function baseOf(joint: any): CFrame
	local live: CFrame = joint.Transform
	local mine = written[joint]
	if mine and Joints.same(live, mine) then
		return animated[joint] or CFrame.identity
	end
	animated[joint] = live
	return live
end

-- `rotation` on top of the animation; nil gives the joint back.
local function layer(joint: any, rotation: CFrame?)
	if not joint or not joint.Parent then
		return
	end
	local base = baseOf(joint)
	if not rotation then
		joint.Transform = base
		written[joint] = nil
		animated[joint] = nil
		return
	end
	local out = base * rotation
	joint.Transform = out
	written[joint] = out
end

local function find(character: Model, pair: { string }): any
	return Joints.find(character:FindFirstChild(pair[1]), pair[2])
end

-- 5.8.2: an absolute joint value (the rest pose times `rotation`), written over whatever the Animator wrote.
local function put(joint: any, value: CFrame)
	if not joint or not joint.Parent then
		return
	end
	if not written[joint] then
		animated[joint] = joint.Transform
	end
	joint.Transform = value
	written[joint] = value
	absolute[joint] = true
end

-- A world point of the scooter's art (an Attachment under its BikeFrame), or `fallback` in the BikeFrame's space.
local function artPoint(character: Model, name: string, fallback: Vector3): Vector3?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local car = seat and seat.Parent
	local frame = car and car:FindFirstChild("BikeFrame")
	if not frame or not frame:IsA("BasePart") then
		return nil
	end
	local point = frame:FindFirstChild(name)
	if point and point:IsA("Attachment") then
		return point.WorldPosition
	end
	return frame.CFrame:PointToWorldSpace(fallback)
end

local function attachmentAt(part: Instance?, name: string): Vector3?
	local a = part and part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else nil
end

-- An arm's two bone lengths from its rig attachments (shoulder→elbow, elbow→wrist→grip), else from the part sizes.
local function armLengths(character: Model, side: string): (number, number)
	local upperArm = character:FindFirstChild(side .. "UpperArm")
	local lowerArm = character:FindFirstChild(side .. "LowerArm")
	local hand = character:FindFirstChild(side .. "Hand")
	local s0, e0 = attachmentAt(upperArm, side .. "ShoulderRigAttachment"), attachmentAt(upperArm, side .. "ElbowRigAttachment")
	local e1, w1 = attachmentAt(lowerArm, side .. "ElbowRigAttachment"), attachmentAt(lowerArm, side .. "WristRigAttachment")
	local w2, g2 = attachmentAt(hand, side .. "WristRigAttachment"), attachmentAt(hand, side .. "GripAttachment")
	local upper = if s0 and e0 then (s0 - e0).Magnitude elseif upperArm and upperArm:IsA("BasePart") then upperArm.Size.Y else 1.2
	local lower = if e1 and w1 then (e1 - w1).Magnitude elseif lowerArm and lowerArm:IsA("BasePart") then lowerArm.Size.Y else 1.1
	if w2 and g2 then
		lower += (w2 - g2).Magnitude
	end
	return math.max(upper, 0.3), math.max(lower, 0.3)
end

-- The lowest point of the feet now (world Y), or nil.
local function feetBottom(character: Model): number?
	local low: number? = nil
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = character:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local y = foot.Position.Y - foot.Size.Y / 2
			low = if low then math.min(low, y) else y
		end
	end
	return low
end

-- 5.8.2: the standing rider (the E-Scooter), absolute.
local function poseStanding(character: Model)
	local u = RiderPose.Upright
	-- The legs: straight under the body, the front foot a touch ahead, the knees soft; a slight lean over the bar.
	put(find(character, BODY[1]), CFrame.Angles(u.Lean, 0, 0))
	put(find(character, BODY[2]), CFrame.Angles(-u.Stagger, 0, 0))
	put(find(character, BODY[3]), CFrame.Angles(u.Knee, 0, 0))
	put(find(character, BODY[4]), CFrame.Angles(u.Stagger, 0, 0))
	put(find(character, BODY[5]), CFrame.Angles(u.Knee, 0, 0))
	-- The feet onto the deck: the Root joint lifts (or lowers) the body by what the last frame missed.
	local root = Joints.find(character:FindFirstChild("LowerTorso"), "Root")
	local deck = artPoint(character, "Deck", Vector3.new(0, 0.59, -0.2))
	local bottom = feetBottom(character)
	local lift = lifts[character] or 0
	if deck and bottom then
		lift = math.clamp(lift + (deck.Y - bottom) * 0.5, -2, 2)
	end
	lifts[character] = lift
	if root then
		put(root, CFrame.new(0, lift, 0))
	end
	-- The hands on the bar (a reach per arm), unless the rider aims (ArmPose has the arms then).
	if character:GetAttribute("Aiming") == true then
		for _, pair in ARMS do
			local joint = find(character, pair)
			if joint and written[joint] then
				layer(joint, nil)
			end
		end
		return
	end
	local torso = character:FindFirstChild("UpperTorso")
	for index, side in { "Right", "Left" } do
		local shoulder = find(character, ARMS[index * 2 - 1])
		local elbow = find(character, ARMS[index * 2])
		local grip = artPoint(character, side .. "Grip", Vector3.new(if side == "Right" then 0.52 else -0.52, 3.45, -1.5))
		local upperArm = character:FindFirstChild(side .. "UpperArm")
		local at = upperArm and upperArm:FindFirstChild(side .. "ShoulderRigAttachment")
		local pitch, yaw, bend = u.Reach, if side == "Right" then u.Inward else -u.Inward, u.Elbow
		if grip and at and at:IsA("Attachment") and torso and torso:IsA("BasePart") then
			local d = torso.CFrame:VectorToObjectSpace(grip - at.WorldPosition)
			local upper, lower = armLengths(character, side)
			pitch, yaw, bend = RiderPose.armIk(d.X, d.Y, d.Z, upper, lower)
		end
		put(shoulder, CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0))
		put(elbow, CFrame.Angles(bend, 0, 0))
	end
end

-- The rider's pose this frame. crank: the bike's crank angle (radians, client/CarVisuals.luau); stand (5.1.1): the
-- E-Scooter's standing rider (the crank does nothing then).
function BikeRider.pose(character: Model, crank: number, stand: boolean?)
	local waist = find(character, BODY[1])
	if not waist then
		return -- not an R15 body: the plain sit
	end
	if not watching then
		-- 5.9.1: a rider whose seat went away without a goodbye (the scooter returned or wrecked under them, the model
		-- gone before client/CarVisuals.luau saw them get off) is let go here.
		watching = RunService.Heartbeat:Connect(function()
			for rider in riders do
				local humanoid = rider:FindFirstChildOfClass("Humanoid")
				local seat = humanoid and humanoid.SeatPart
				local car = seat and seat.Parent
				if not rider.Parent or not humanoid or humanoid.Health <= 0 or not car or car:GetAttribute("Bike") ~= true then
					BikeRider.release(rider)
				end
			end
		end)
	end
	if not riders[character] then
		local posed: { any } = {}
		for _, list in { ARMS, BODY } do
			for _, pair in list do
				local joint = find(character, pair)
				if joint then
					table.insert(posed, joint)
				end
			end
		end
		riders[character] = posed
	end
	if stand == true then
		local list = riders[character]
		local root = Joints.find(character:FindFirstChild("LowerTorso"), "Root")
		if root and not table.find(list, root) then
			table.insert(list, root) -- (released with the rest on the way off)
		end
		poseStanding(character)
		return
	end
	local pose = RiderPose.pose(false, crank)
	layer(waist, CFrame.Angles(pose.waist.x, 0, 0))
	layer(find(character, BODY[2]), CFrame.Angles(pose.rightHip.x, 0, 0))
	layer(find(character, BODY[3]), CFrame.Angles(pose.rightKnee.x, 0, 0))
	layer(find(character, BODY[4]), CFrame.Angles(pose.leftHip.x, 0, 0))
	layer(find(character, BODY[5]), CFrame.Angles(pose.leftKnee.x, 0, 0))
	local arms = character:GetAttribute("Aiming") ~= true
	for n, pair in ARMS do
		local joint = find(character, pair)
		if not arms then
			if joint and written[joint] then
				layer(joint, nil)
			end
		elseif n == 1 then
			layer(joint, CFrame.Angles(0, pose.rightShoulder.y, 0) * CFrame.Angles(pose.rightShoulder.x, 0, 0))
		elseif n == 3 then
			layer(joint, CFrame.Angles(0, pose.leftShoulder.y, 0) * CFrame.Angles(pose.leftShoulder.x, 0, 0))
		else
			layer(joint, CFrame.Angles(pose.elbow.x, 0, 0))
		end
	end
end

-- Off the bike (or out of range): every joint back to the animation.
function BikeRider.release(character: Model)
	local posed = riders[character]
	if not posed then
		return
	end
	riders[character] = nil
	lifts[character] = nil
	for _, joint in posed do
		if absolute[joint] then
			-- 5.9.1: back to the rest pose (the Animator writes over it next frame where it animates; the Root joint it
			-- may not animate at all: a lift or a sit's drop must not stay, the body would stand sunk or floating).
			if joint.Parent then
				joint.Transform = CFrame.identity
			end
		elseif written[joint] then
			layer(joint, nil)
		end
		written[joint] = nil
		animated[joint] = nil
		absolute[joint] = nil
	end
end

-- Is this character posed as a rider now?
function BikeRider.riding(character: Model): boolean
	return riders[character] ~= nil
end

return BikeRider
