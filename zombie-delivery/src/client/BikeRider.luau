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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- The rider's pose this frame. crank: the bike's crank angle (radians, client/CarVisuals.luau); stand (5.1.1): the
-- E-Scooter's standing rider (the crank does nothing then).
function BikeRider.pose(character: Model, crank: number, stand: boolean?)
	local waist = find(character, BODY[1])
	if not waist then
		return -- not an R15 body: the plain sit
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
	local pose = RiderPose.pose(stand == true, crank)
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
	for _, joint in posed do
		if written[joint] then
			layer(joint, nil)
		end
		written[joint] = nil
		animated[joint] = nil
	end
end

-- Is this character posed as a rider now?
function BikeRider.riding(character: Model): boolean
	return riders[character] ~= nil
end

return BikeRider
