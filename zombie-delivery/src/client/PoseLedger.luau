--!strict
-- 6.7: the one book of the characters' joint poses on this client, shared by the pose layers that write the R15 joints'
-- Transform in RunService.PreSimulation (client/ArmPose.luau, client/SprintPose.luau, client/BodyLife.luau; never C0:
-- shared/Joints.luau). Several layers now move the same joint (the waist: the carry's lean, the run, the breath, the
-- flinch); each composing on what it read as "the animation" would pile the others' poses up on a frame the Animator
-- skips (a far body is animated less often). The book keeps, per joint and frame, the animation's own value:
--   PoseLedger.base(joint)    the animation's value this frame (the Animator's, or its last one when it left the joint
--                             alone this frame: the joint still holds what was written last)
--   PoseLedger.now(joint)     the value so far this frame: the base, or what a layer wrote over it before this one
--   PoseLedger.write(joint, value)  the joint's Transform, the frame's value from now on
--   PoseLedger.release(joint) a layer lets go: when nobody wrote the joint this frame it goes back to the base (the rest
--                             pose where nothing animates it: a bob or a dip never stays on the Root joint)
-- A frame starts in RunService.PreAnimation (before the Animator, before every PreSimulation layer). The layers run in
-- any order; each composes on now(). Joints that left their body are forgotten now and then.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Joints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Joints"))

local PoseLedger = {}

type Entry = { frame: number, base: CFrame, final: CFrame?, wrote: boolean }

local entries: { [Instance]: Entry } = {}
local frame = 0
local started = false
local sweptAt = 0
local SWEEP = 5 -- seconds between the clean-ups of the joints that are gone

local function sweep()
	local now = os.clock()
	if now - sweptAt < SWEEP then
		return
	end
	sweptAt = now
	for joint in entries do
		if not joint.Parent then
			entries[joint] = nil
		end
	end
end

local function start()
	if started then
		return
	end
	started = true
	RunService.PreAnimation:Connect(function()
		frame += 1
		sweep()
	end)
end

-- The joint's entry for this frame.
local function entry(joint: any): Entry
	start()
	local e = entries[joint]
	if e and e.frame == frame then
		return e
	end
	local live: CFrame = joint.Transform
	if not e then
		local made: Entry = { frame = frame, base = live, final = nil, wrote = false }
		entries[joint] = made
		return made
	end
	e.frame = frame
	e.wrote = false
	local final = e.final
	if not (final and Joints.same(live, final)) then
		e.base = live -- (the Animator, or a writer outside the book, set it this frame)
	end
	return e
end

function PoseLedger.base(joint: any): CFrame
	return entry(joint).base
end

function PoseLedger.now(joint: any): CFrame
	local e = entry(joint)
	if e.wrote then
		return joint.Transform
	end
	return e.base
end

function PoseLedger.write(joint: any, value: CFrame)
	local e = entry(joint)
	joint.Transform = value
	e.final = value
	e.wrote = true
end

function PoseLedger.release(joint: any)
	local e = entries[joint]
	if not e then
		return
	end
	entry(joint)
	if not e.wrote then
		if e.final and joint.Parent then
			joint.Transform = e.base
		end
		e.final = nil
	end
end

-- Did a layer write this joint this frame?
function PoseLedger.written(joint: any): boolean
	local e = entries[joint]
	return e ~= nil and e.frame == frame and e.wrote
end

return PoseLedger
