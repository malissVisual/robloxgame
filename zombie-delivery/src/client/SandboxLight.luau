--!strict
-- 8.3 SANDBOX, the eyes (the owner: "in the house I cannot see my own character, it is so bright; walking into the
-- warehouse is a flashbang"): the screen eases to the place you are in, the way eyes adapt. Where you are is what the
-- sandbox's sounds already use (shared/SoundPlan.luau sandboxPlace: client/MoveSounds.luau inside, the interiors far
-- off the map, a plot's warehouse: its own level's walls, workspace.Warehouses' Level<id>) and any Sprinter's walk-in
-- bay (its BayLight: shared/SandboxLightRules.luau inBay).
-- Each place's look is Config.SandboxLight.Places' (shared/SandboxLightRules.luau look):
--   * Lighting.ExposureCompensation: the map's (Config.SandboxLight.Sky.Exposure) plus the place's;
--   * one bloom, SandboxBloom (any other BloomEffect in Lighting, e.g. the place template's "Bloom", is switched off on
--     this screen: the picture is never bloomed twice);
--   * a colour grade of its own, SandboxEyes, over the server's SandboxGrade (outdoors it changes nothing);
--   * the sun rays, SandboxSunRays (none indoors; the template's SunRays off the same way).
-- A new place's look comes in over Config.SandboxLight.Ease s (95 %), never at once (SandboxLightRules.ease, one step
-- at most Step s long): walking into a hall never flashes. Where you are is looked at every Every s; the easing writes
-- only while it moves. 8.3: while a door's trip keeps the screen black (client/Fade.luau isDark; the server sends where
-- you are before the fade in) a new place comes in at once: the fade in shows it as it stays, no second change after. A phone or a tablet (client/DeviceBudget.luau lite) blooms LiteBloom as much. Everything here is
-- this screen's own (made on the client, never sent anywhere).
--
--   SandboxLight.start()   once (client/Main.client.luau, the sandbox's list); nothing outside the sandbox
--   SandboxLight.place()   where the eyes think you are ("outdoors" | "house" | "warehouse" | "van")

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SandboxLightRules = require(Shared.SandboxLightRules)

local DeviceBudget = require(script.Parent.DeviceBudget)
local Fade = require(script.Parent.Fade) -- (8.3: a door's trip's black: the eyes adapt at once behind it)
local MoveSounds = require(script.Parent.MoveSounds) -- (8.1: are you in the move's house)

local SandboxLight = {}

local L = Config.SandboxLight
local BAY_EVERY = 1 -- s between two looks for the Sprinters' bays (vans come, go and stream)
local BAY_NEAR = 30 -- studs: a bay farther than this from you is not looked into

local player = Players.LocalPlayer
local started = false
local placeNow = "outdoors"

type Effects = { bloom: BloomEffect, grade: ColorCorrectionEffect, rays: SunRaysEffect }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(math.clamp(c[1], 0, 255), math.clamp(c[2], 0, 255), math.clamp(c[3], 0, 255))
end

-- Our own effects in Lighting (this screen's: made here, never replicated).
local function makeEffects(): Effects
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SandboxBloom"
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SandboxEyes"
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "SandboxSunRays"
	rays.Spread = L.RaySpread
	bloom.Parent = Lighting
	grade.Parent = Lighting
	rays.Parent = Lighting
	return { bloom = bloom, grade = grade, rays = rays }
end

-- Another bloom or sun rays in Lighting (the place template's): off on this screen, ours does it.
local function quiet(effects: Effects, item: Instance)
	if item == effects.bloom or item == effects.rays then
		return
	end
	if item:IsA("BloomEffect") or item:IsA("SunRaysEffect") then
		pcall(function()
			(item :: PostEffect).Enabled = false
		end)
	end
end

local function write(effects: Effects, look: SandboxLightRules.Look)
	Lighting.ExposureCompensation = math.clamp(look.exposure, -3, 3)
	local bloom = effects.bloom
	bloom.Intensity = look.bloom
	bloom.Size = math.clamp(look.size, 0, 56)
	bloom.Threshold = math.clamp(look.threshold, 0.8, 4)
	bloom.Enabled = look.bloom > 0.001
	local grade = effects.grade
	grade.Brightness = look.brightness
	grade.Contrast = look.contrast
	grade.Saturation = look.saturation
	grade.TintColor = rgb(look.tint)
	local rays = effects.rays
	rays.Intensity = look.rays
	rays.Enabled = look.rays > 0.001
end

-- ── Where you are ─────────────────────────────────────────────────────────────

local bays: { Attachment } = {}
local found: { [Instance]: Attachment } = setmetatable({}, { __mode = "k" }) :: any -- a car → its bay's light, once found

local function lookForBays()
	table.clear(bays)
	local cars = workspace:FindFirstChild("Cars")
	if not cars then
		return
	end
	for _, car in cars:GetChildren() do
		local spot = found[car]
		if not spot or not spot:IsDescendantOf(car) then
			local look = car:FindFirstChild("BayLight", true) -- (server/Vehicles.luau: on a Sprinter's chassis; looked
			-- for again only while a car has none: another van, or its chassis not streamed in yet)
			spot = if look and look:IsA("Attachment") then look else nil
			found[car] = spot :: any
		end
		if spot then
			table.insert(bays, spot)
		end
	end
end

local function inVan(at: Vector3): boolean
	for _, spot in bays do
		if spot.Parent then
			local frame = spot.WorldCFrame
			if (frame.Position - at).Magnitude <= BAY_NEAR then
				local rel = frame:PointToObjectSpace(at)
				if SandboxLightRules.inBay(rel.X, rel.Y, rel.Z) then
					return true
				end
			end
		end
	end
	return false
end

-- Your body's middle (else the camera's focus: the start screen, a respawn).
local function where(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

-- 8.3: a plot's warehouse level, 1 … 5 (server/Warehouse.luau's attribute Level<id> on workspace.Warehouses; nil: not
-- there yet, SoundPlan takes 4): its hall is that level's building. The keys made once a plot.
local levelKeys: { [number]: string } = {}
local function warehouseLevel(plotId: number): number?
	local halls = workspace:FindFirstChild("Warehouses")
	if not halls then
		return nil
	end
	local key = levelKeys[plotId]
	if not key then
		key = `Level{plotId}`
		levelKeys[plotId] = key
	end
	local level = halls:GetAttribute(key)
	return if type(level) == "number" then level else nil
end

local function placeOf(): string
	local at = where()
	if not at then
		return placeNow
	end
	local inside = MoveSounds.inside()
	return SandboxLightRules.place(at.X, at.Y, at.Z, inside, not inside and inVan(at), warehouseLevel)
end

function SandboxLight.place(): string
	return placeNow
end

-- ── The loop ──────────────────────────────────────────────────────────────────

function SandboxLight.start()
	if started then
		return
	end
	started = true
	local effects = makeEffects()
	for _, item in Lighting:GetChildren() do
		quiet(effects, item)
	end
	Lighting.ChildAdded:Connect(function(item: Instance)
		quiet(effects, item)
	end)
	placeNow = placeOf()
	local target = SandboxLightRules.look(placeNow, DeviceBudget.lite)
	local shown = SandboxLightRules.copy(target) -- (the first look at once: the start screen is up)
	write(effects, shown)
	local settled = true
	local clock, bayClock = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		bayClock += dt
		if bayClock >= BAY_EVERY then
			bayClock = 0
			lookForBays()
		end
		if clock >= L.Every then
			clock = 0
			placeNow = placeOf()
			local want = SandboxLightRules.look(placeNow, DeviceBudget.lite) -- (lite: the admin's LITE switch too)
			if not SandboxLightRules.settled(want, target) then
				target = want -- (a new place, even half way into the last one: on from where the eyes are)
				settled = false
			elseif settled and math.abs(Lighting.ExposureCompensation - shown.exposure) > 0.01 then
				write(effects, shown) -- (somebody else wrote the exposure, e.g. the map's lighting again: ours back)
			end
		end
		if settled then
			return
		end
		if Fade.isDark() then
			-- (8.3 a door's trip, client/Fade.luau: the screen black, the eyes are there at once: the fade in shows the
			-- new place as it will stay, no second change after it)
			shown = SandboxLightRules.copy(target)
			settled = true
			write(effects, shown)
			return
		end
		shown = SandboxLightRules.ease(shown, target, dt)
		if SandboxLightRules.settled(shown, target) then
			shown = SandboxLightRules.copy(target)
			settled = true
		end
		write(effects, shown)
	end)
end

return SandboxLight
