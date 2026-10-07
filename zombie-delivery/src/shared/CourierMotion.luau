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

function Motion.select(state: string, speed: number, vertical: number, seated: boolean): (string?, number)
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
	if speed < 18 then return "walk", math.clamp(speed / 12.8, 0.25, 2) end
	return "run", math.clamp(speed / 24, 0.5, 2)
end

return Motion
