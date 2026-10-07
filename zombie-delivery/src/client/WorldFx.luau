--!strict
-- 5.7, the world's moving lights, only on this client (started by client/Weather.luau):
--   * The night lights: server/DayNight.luau only turns the workspace attribute "Night"; here every part tagged
--     "NightLight" (the street lamps, the lit windows, the cars' lights …) is restyled: Neon in its LitColor at night,
--     its DimColor and DimMaterial by day, its lights on and off. A dusk or a dawn restyles Config.LivingCity.Lights
--     RestylePerFrame parts a frame (no hitch); a light that streams in or is registered later takes the state at once;
--     a light whose tag is taken away (a wrecked car) goes dark.
--   * The clock: the server sends it once a second (the workspace attributes ClockHour and ClockRate); here it runs
--     smoothly in between (Lighting.ClockTime every frame), so the sun and the night look never step.
--   * The lighthouse's two beams sweep round at night (the parts tagged "LighthouseBeam": their Hub and Beam
--     attributes), the radio mast's beacon blinks ("RadioBeacon").
--   * A few broken street lamps ("BrokenLamp") flicker at night, the red flares on the streets ("Flare") burn
--     unsteadily, only within FlickerRange of the camera.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldFx = {}

local NIGHT_TAG = "NightLight" -- (server/DayNight.luau DayNight.Tag)
local Tuning = Config.LivingCity.Lights

local DIM_MATERIALS: { [string]: Enum.Material } = {
	Glass = Enum.Material.Glass,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Plastic = Enum.Material.Plastic,
}

local function nightNow(): boolean
	return workspace:GetAttribute("Night") == true
end

-- One night light on or off (the same as the server's DayNight: the part, its lights, or a tagged light itself).
local function apply(item: Instance, on: boolean)
	if item:IsA("Light") then
		item.Enabled = on
		return
	end
	if item:IsA("BasePart") then
		local lit, dim = item:GetAttribute("LitColor"), item:GetAttribute("DimColor")
		if typeof(lit) == "Color3" and typeof(dim) == "Color3" then
			item.Color = if on then lit else dim
		end
		local dimMaterial = item:GetAttribute("DimMaterial")
		item.Material = if on then Enum.Material.Neon else (if type(dimMaterial) == "string" and DIM_MATERIALS[dimMaterial] then DIM_MATERIALS[dimMaterial] else Enum.Material.SmoothPlastic)
	end
	for _, child in item:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = on
		end
	end
end

-- A light whose tag was taken away: dark for good (its colour only if it still shows the lit one: the server may have
-- painted it since, a burnt-out car).
local function darken(item: Instance)
	if item:IsA("Light") then
		item.Enabled = false
		return
	end
	if not item:IsA("BasePart") then
		return
	end
	if item.Material == Enum.Material.Neon then
		local dimMaterial = item:GetAttribute("DimMaterial")
		item.Material = if type(dimMaterial) == "string" and DIM_MATERIALS[dimMaterial] then DIM_MATERIALS[dimMaterial] else Enum.Material.SmoothPlastic
	end
	local lit, dim = item:GetAttribute("LitColor"), item:GetAttribute("DimColor")
	if typeof(lit) == "Color3" and typeof(dim) == "Color3" and item.Color == lit then
		item.Color = dim
	end
	for _, child in item:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = false
		end
	end
end

-- A tagged set kept as a list (added and removed with the tag, streaming included).
local function watch(tag: string, list: { Instance }, added: ((Instance) -> ())?)
	local function add(item: Instance)
		if not table.find(list, item) then
			table.insert(list, item)
		end
		if added then
			added(item)
		end
	end
	for _, item in CollectionService:GetTagged(tag) do
		add(item)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(item)
		local at = table.find(list, item)
		if at then
			table.remove(list, at)
		end
	end)
end

-- ── The night lights ───────────────────────────────────────────────────────

local function startRestyle()
	local queue: { Instance } = {}
	local cursor = 1
	local state = nightNow()
	local function restart()
		state = nightNow()
		queue = CollectionService:GetTagged(NIGHT_TAG)
		cursor = 1
	end
	restart()
	workspace:GetAttributeChangedSignal("Night"):Connect(restart)
	CollectionService:GetInstanceAddedSignal(NIGHT_TAG):Connect(function(item)
		apply(item, nightNow())
	end)
	CollectionService:GetInstanceRemovedSignal(NIGHT_TAG):Connect(darken)
	RunService.Heartbeat:Connect(function()
		if cursor > #queue then
			return
		end
		local last = math.min(#queue, cursor + Tuning.RestylePerFrame - 1)
		for n = cursor, last do
			local item = queue[n]
			-- (one that left in the meantime, or lost its tag, is skipped)
			if item.Parent and CollectionService:HasTag(item, NIGHT_TAG) then
				pcall(apply, item, state)
			end
		end
		cursor = last + 1
	end)
end

-- ── The clock ──────────────────────────────────────────────────────────────

local function startClock()
	local base: number? = nil
	local baseAt = 0
	local function take()
		local hour = workspace:GetAttribute("ClockHour")
		if type(hour) == "number" then
			base = hour
			baseAt = os.clock()
		end
	end
	take()
	workspace:GetAttributeChangedSignal("ClockHour"):Connect(take)
	RunService:BindToRenderStep("ZombieDeliveryClock", Enum.RenderPriority.First.Value, function()
		local hour = base
		local rate = workspace:GetAttribute("ClockRate")
		if hour == nil or type(rate) ~= "number" then
			return -- (an older server: Lighting.ClockTime replicates as it is)
		end
		-- Runs on from the last time the server sent it (never more than a few seconds ahead: a lost update waits).
		local now = (hour + rate * math.min(os.clock() - baseAt, 3)) % 24
		if math.abs(Lighting.ClockTime - now) > 1e-4 then
			Lighting.ClockTime = now
		end
	end)
end

-- ── The beams, the beacon, the broken lamps, the flares ────────────────────

local function startMoving()
	local beams: { Instance } = {}
	local beacons: { Instance } = {}
	local broken: { Instance } = {}
	local flares: { Instance } = {}
	watch("LighthouseBeam", beams)
	watch("RadioBeacon", beacons)
	watch("BrokenLamp", broken)
	watch("Flare", flares)
	local angle = 0
	local blinkClock, flickerClock = 0, 0
	local beaconOn = true
	local dark: { [Instance]: number } = {} -- a broken lamp that is out right now: until when (os.clock)
	local rand = Random.new()
	RunService.Heartbeat:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local night = nightNow()
		-- The lighthouse's beams.
		angle = (angle + dt * 1.1) % (2 * math.pi)
		for _, beam in beams do
			if not beam:IsA("BasePart") then
				continue
			end
			local want = if night then 0.75 else 1
			if beam.Transparency ~= want then
				beam.Transparency = want
			end
			local hub = beam:GetAttribute("Hub")
			local n = beam:GetAttribute("Beam")
			if night and typeof(hub) == "Vector3" and type(n) == "number" then
				beam.CFrame = CFrame.new(hub) * CFrame.Angles(0, angle + n * math.pi, 0) * CFrame.new(0, 0, -41)
			end
		end
		-- The radio mast's beacon.
		blinkClock += dt
		if blinkClock >= 0.8 then
			blinkClock = 0
			beaconOn = not beaconOn
			for _, beacon in beacons do
				if beacon:IsA("BasePart") then
					beacon.Transparency = if beaconOn then 0 else 0.8
				end
			end
		end
		-- The broken lamps and the flares, a few times a second, near the camera.
		flickerClock += dt
		if flickerClock < 0.06 then
			return
		end
		flickerClock = 0
		local now = os.clock()
		local range = Tuning.FlickerRange
		for _, lamp in broken do
			if not lamp:IsA("BasePart") then
				continue
			end
			local near = night and (lamp.Position - eye).Magnitude < range
			local outUntil = dark[lamp]
			if outUntil then
				if not near or now >= outUntil then
					dark[lamp] = nil
					apply(lamp, night)
				end
			elseif near and rand:NextNumber() < 0.07 then
				dark[lamp] = now + rand:NextNumber(0.05, 0.5)
				apply(lamp, false)
			end
		end
		for lamp in dark do
			if not lamp.Parent then
				dark[lamp] = nil
			end
		end
		if night then
			for _, flare in flares do
				if flare:IsA("BasePart") and (flare.Position - eye).Magnitude < range then
					local light = flare:FindFirstChildOfClass("PointLight")
					if light then
						light.Brightness = 1.1 + rand:NextNumber() * 0.9
					end
				end
			end
		end
	end)
end

local started = false

function WorldFx.start()
	if started then
		return
	end
	started = true
	startClock()
	startRestyle()
	startMoving()
end

return WorldFx
