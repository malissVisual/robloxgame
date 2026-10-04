--!strict
-- Character joints. Classic rigs (R6, our blocky bodies, R15 before 2026) join their parts with Motor6Ds. Since
-- Roblox's Avatar Joint Upgrade (on by default in every place since mid-2026) an R15 character's joints are
-- AnimationConstraints instead: the same names in the same parts and a writable Transform, but C0 / C1 / Part0 /
-- Part1 are read-only aliases and IsA("Motor6D") is false. These helpers work with both kinds.

local Joints = {}

function Joints.isJoint(i: Instance): boolean
	return i:IsA("AnimationConstraint") or i:IsA("Motor6D")
end

-- The joint called `name` in `part`. While Roblox swaps a fresh character's Motor6Ds for AnimationConstraints,
-- both can exist for a moment under the same name: the AnimationConstraint wins.
function Joints.find(part: Instance?, name: string): any
	if not part then
		return nil
	end
	local found: Instance? = nil
	for _, child in part:GetChildren() do
		if child.Name == name then
			if child:IsA("AnimationConstraint") then
				return child
			elseif child:IsA("Motor6D") then
				found = child
			end
		end
	end
	return found
end

-- The part an attachment (or a bone) sits in.
local function partOf(i: Instance?): BasePart?
	if not i then
		return nil
	end
	if i:IsA("BasePart") then
		return i
	end
	return i:FindFirstAncestorWhichIsA("BasePart")
end
Joints.partOf = partOf

-- A joint's two ends: its attachments (the R15 rig attachments; nil when a Motor6D has none) and its two parts.
function Joints.ends(j: Instance): (Attachment?, Attachment?, BasePart?, BasePart?)
	if j:IsA("AnimationConstraint") then
		local a0: Attachment? = j.Attachment0
		local a1: Attachment? = j.Attachment1
		return a0, a1, partOf(a0), partOf(a1)
	elseif j:IsA("Motor6D") then
		local p0: BasePart? = j.Part0
		local p1: BasePart? = j.Part1
		local a0 = if p0 then p0:FindFirstChild(j.Name .. "RigAttachment") else nil
		local a1 = if p1 then p1:FindFirstChild(j.Name .. "RigAttachment") else nil
		return if a0 and a0:IsA("Attachment") then a0 else nil, if a1 and a1:IsA("Attachment") then a1 else nil, p0, p1
	end
	return nil, nil, nil, nil
end

-- Two transforms are the same (the engine may store a written value a hair differently).
function Joints.same(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4
		and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

return Joints
