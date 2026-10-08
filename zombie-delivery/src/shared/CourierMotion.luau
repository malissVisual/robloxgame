--!strict
-- One R15 animation family for every courier. Pure selection uses actual velocity and humanoid state;
-- 5.9.2: the owning client picks the track (server/CharacterArt/Animate.client.luau, in the StarterCharacter that
-- server/CourierAvatar installs), while existing client arm/ride/interaction poses remain overlays.
local Motion = {}
Motion.Tick = 0.1
Motion.Fade = 0.18
Motion.Animations = {
	idle = "rbxassetid://507766388", walk = "rbxassetid://507777826", run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000", fall = "rbxassetid://507767968", climb = "rbxassetid://507765644",
	swim = "rbxassetid://507784897", swimidle = "rbxassetid://507785072", sit = "rbxassetid://2506281703",
}

-- 6.7: the stock tracks are paced for a body standing on this leg. A longer leg covers more ground with every step:
-- `stride` (Motion.stride: the body's leg / StockLeg; 1 when not given) slows the walk and the run to match, so the feet
-- do not slide. 6.8 review: the leg is measured on the rig (Motion.leg: hip → knee → ankle → sole, the realistic
-- courier's 2.8: 1.4; 6.7 took its HipHeight 2.2 for it, 1.1, and the feet slid).
Motion.StockLeg = 2

-- 6.8 review: the right leg of an R15 body, hip to sole (studs), from its rig attachments (the hip to the knee on the
-- thigh, the knee to the ankle on the shin, the ankle to the foot's bottom); nil when a piece is missing (an R6 body).
function Motion.leg(character: Instance): number?
	local thigh = character:FindFirstChild("RightUpperLeg")
	local shin = character:FindFirstChild("RightLowerLeg")
	local foot = character:FindFirstChild("RightFoot")
	local function at(part: Instance?, name: string): Vector3?
		local found = if part then part:FindFirstChild(name) else nil
		return if found and found:IsA("Attachment") then found.Position else nil
	end
	local hip, knee = at(thigh, "RightHipRigAttachment"), at(thigh, "RightKneeRigAttachment")
	local knee2, ankle = at(shin, "RightKneeRigAttachment"), at(shin, "RightAnkleRigAttachment")
	local ankle2 = at(foot, "RightAnkleRigAttachment")
	if not (hip and knee and knee2 and ankle and ankle2 and foot and foot:IsA("BasePart")) then
		return nil
	end
	return (hip - knee).Magnitude + (knee2 - ankle).Magnitude + math.max(0, ankle2.Y + foot.Size.Y / 2)
end

-- 6.8 review: how much longer than the stock one a leg's step is (`leg` studs, hip to sole; nil: the stock leg).
function Motion.stride(leg: number?): number
	return math.max(leg or Motion.StockLeg, 0.5) / Motion.StockLeg
end

function Motion.select(state: string, speed: number, vertical: number, seated: boolean, stride: number?): (string?, number)
	local legs = math.max(stride or 1, 0.25)
	if state == "Dead" then return nil, 1 end
	if seated or state == "Seated" then return "sit", 1 end
	if state == "Jumping" then return "jump", 1 end
	if state == "Freefall" then return "fall", 1 end
	if state == "Climbing" then return "climb", math.clamp(math.abs(vertical) / 5, 0, 2) end
	if state == "Swimming" then
		local amount = math.sqrt(speed * speed + vertical * vertical)
		return if amount > 1 then "swim" else "swimidle", math.clamp(amount / 10, 0.5, 2)
	end
	-- Physics/platform-stand interactions (ziplines) supply their own pose.
	if state == "Physics" or state == "PlatformStanding" or state == "Ragdoll" then return nil, 1 end
	if speed < 0.7 then return "idle", 1 end
	if speed < 18 then return "walk", math.clamp(speed / (12.8 * legs), 0.25, 2) end
	return "run", math.clamp(speed / (24 * legs), 0.5, 2)
end

return Motion
