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
-- 6.19 (the owner: "the bike doesn't fit, the legs ... make it visible how he pedals"): the seated rider is posed
-- ABSOLUTE too (no more thighs pumping over the sit, which stuck out like a chair's): the body moved on its Root joint
-- until the hips sit on the art's Saddle point (measured every frame, like the scooter's deck), the upper body leaning
-- over the bars, each foot ON its pedal round the crank (RiderPose.legIk: hip -> knee -> ankle to the pedal point
-- from the bike's CrankAxis and the crank's own LeftPedal / RightPedal points at this frame's crank angle, the knees
-- forward; the ankle keeps the foot on the pedal), the hands on the grips (RiderPose.armIk). The bikes' art is built
-- to the classic R15 (server/BikeArt/Geometry.luau Scale). Everybody's client poses every rider near its camera.

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
	{ "RightFoot", "RightAnkle" }, -- 6.19: the feet on the pedals
	{ "LeftFoot", "LeftAnkle" },
}

local written: { [Instance]: CFrame } = {}
local animated: { [Instance]: CFrame } = {}
local riders: { [Model]: { any } } = {} -- the joints posed on each rider (released on the way off)
local lifts: { [Model]: number } = {} -- 5.8.2: a standing rider's Root lift (studs), corrected toward the deck
local seats: { [Model]: Vector3 } = {} -- 6.19: a pedalling rider's Root offset (studs), corrected toward the saddle
type Legs = { thigh: number, shin: number, ankle: number, upper: number, lower: number }
local legs: { [Model]: Legs } = {} -- 6.19: the rider's bone lengths (measured once a ride)
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

-- 6.19: a leg's bones (hip->knee, knee->ankle, the ankle over the sole) and an arm's, from the rig attachments.
local function bonesOf(character: Model): Legs
	local thighPart = character:FindFirstChild("RightUpperLeg")
	local shinPart = character:FindFirstChild("RightLowerLeg")
	local foot = character:FindFirstChild("RightFoot")
	local h, k = attachmentAt(thighPart, "RightHipRigAttachment"), attachmentAt(thighPart, "RightKneeRigAttachment")
	local k2, a = attachmentAt(shinPart, "RightKneeRigAttachment"), attachmentAt(shinPart, "RightAnkleRigAttachment")
	local a2 = attachmentAt(foot, "RightAnkleRigAttachment")
	local thigh = if h and k then (h - k).Magnitude elseif thighPart and thighPart:IsA("BasePart") then thighPart.Size.Y * 0.7 else 0.8
	local shin = if k2 and a then (k2 - a).Magnitude elseif shinPart and shinPart:IsA("BasePart") then shinPart.Size.Y * 0.8 else 0.9
	local ankle = if a2 and foot and foot:IsA("BasePart") then math.max(0.05, a2.Y + foot.Size.Y / 2) else 0.2
	local upper, lower = armLengths(character, "Right")
	return { thigh = math.max(thigh, 0.3), shin = math.max(shin, 0.3), ankle = ankle, upper = upper, lower = lower }
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

-- 6.19: the arms to the grips (absolute; RiderPose.armIk), unless the rider aims (ArmPose has the arms then).
local function gripArms(character: Model, frame: BasePart, bones: Legs, reach: number, inward: number, elbow: number)
	if character:GetAttribute("Aiming") == true then
		for _, pair in ARMS do
			local joint = find(character, pair)
			if joint and written[joint] then
				layer(joint, nil)
				absolute[joint] = nil
			end
		end
		return
	end
	local torso = character:FindFirstChild("UpperTorso")
	for index, side in { "Right", "Left" } do
		local point = frame:FindFirstChild(side .. "Grip")
		local upperArm = character:FindFirstChild(side .. "UpperArm")
		local at = upperArm and upperArm:FindFirstChild(side .. "ShoulderRigAttachment")
		local pitch, yaw, bend = reach, if side == "Right" then inward else -inward, elbow
		if point and point:IsA("Attachment") and at and at:IsA("Attachment") and torso and torso:IsA("BasePart") then
			local d = torso.CFrame:VectorToObjectSpace(point.WorldPosition - at.WorldPosition)
			pitch, yaw, bend = RiderPose.armIk(d.X, d.Y, d.Z, bones.upper, bones.lower)
		end
		put(find(character, ARMS[index * 2 - 1]), CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0))
		put(find(character, ARMS[index * 2]), CFrame.Angles(bend, 0, 0))
	end
end

-- 6.19: the pedalling rider (a bike's saddle), absolute; false when the bike's points are missing (the old layered
-- pose then).
local function posePedalling(character: Model, crank: number): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local car = seat and seat.Parent
	local frame = car and car:FindFirstChild("BikeFrame")
	local crankPart = car and car:FindFirstChild("Crank")
	local lower = character:FindFirstChild("LowerTorso")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (frame and frame:IsA("BasePart") and crankPart and lower and lower:IsA("BasePart") and rootPart and rootPart:IsA("BasePart")) then
		return false
	end
	local saddle, axis = frame:FindFirstChild("Saddle"), frame:FindFirstChild("CrankAxis")
	if not (saddle and saddle:IsA("Attachment") and axis and axis:IsA("Attachment")) then
		return false
	end
	local r = RiderPose.Ride
	local bones = legs[character]
	if not bones then
		bones = bonesOf(character)
		legs[character] = bones
	end
	local bike = frame.CFrame
	-- The hips onto the saddle: the Root joint moves the body by half of what the last frame missed.
	local hipR = lower:FindFirstChild("RightHipRigAttachment")
	local hipL = lower:FindFirstChild("LeftHipRigAttachment")
	if not (hipR and hipR:IsA("Attachment") and hipL and hipL:IsA("Attachment")) then
		return false
	end
	local want = bike:PointToWorldSpace(saddle.Position + Vector3.new(0, r.HipUp, r.HipBack))
	local miss = rootPart.CFrame:VectorToObjectSpace(want - (hipR.WorldPosition + hipL.WorldPosition) / 2)
	local offset = (seats[character] or Vector3.zero) + miss * 0.5
	if offset.Magnitude > 3 then
		offset = offset.Unit * 3
	end
	seats[character] = offset
	put(Joints.find(lower, "Root"), CFrame.new(offset))
	put(find(character, BODY[1]), CFrame.Angles(r.Lean, 0, 0))
	-- Each foot on its pedal: the pedal's point turned with the crank about the bike's crank axis.
	for index, side in { "Right", "Left" } do
		local pedal = crankPart:FindFirstChild(side .. "Pedal")
		local hip = if side == "Right" then hipR else hipL
		if not (pedal and pedal:IsA("Attachment") and hip:IsA("Attachment")) then
			continue
		end
		local onFrame = axis.Position + CFrame.Angles(crank, 0, 0):PointToWorldSpace(pedal.Position)
		local target = bike:PointToWorldSpace(onFrame + Vector3.new(0, r.PedalTop + bones.ankle, r.AnkleBack))
		local d = (lower.CFrame * hip.CFrame):PointToObjectSpace(target)
		local pitch, roll, knee = RiderPose.legIk(d.X, d.Y, d.Z, bones.thigh, bones.shin)
		local own = if side == "Right" then crank else crank + math.pi
		put(find(character, BODY[index * 2]), CFrame.Angles(0, 0, roll) * CFrame.Angles(pitch, 0, 0))
		put(find(character, BODY[index * 2 + 1]), CFrame.Angles(knee, 0, 0))
		put(find(character, BODY[5 + index]), CFrame.Angles(RiderPose.ankle(pitch, knee, own), 0, 0))
	end
	local p = RiderPose.Pedal
	gripArms(character, frame, bones, p.Reach, p.Inward, p.Elbow)
	return true
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
	local list = riders[character]
	local root = Joints.find(character:FindFirstChild("LowerTorso"), "Root")
	if root and not table.find(list, root) then
		table.insert(list, root) -- (6.19: released with the rest on the way off)
	end
	if posePedalling(character, crank) then
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
	seats[character] = nil
	legs[character] = nil
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
