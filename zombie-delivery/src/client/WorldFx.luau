--!strict
-- 5.7, the world's moving lights, only on this client (started by client/Weather.luau):
--   * The night lights: server/DayNight.luau only turns the workspace attribute "Night"; here every part tagged
--     "NightLight" (the street lamps, the lit windows, the cars' lights …) is restyled: Neon in its LitColor at night,
--     its DimColor and DimMaterial by day, its lights on and off. A dusk or a dawn restyles the lights near the camera
--     first (within Config.LivingCity.Lights RestyleNear: RestyleNearPerFrame a frame), then the far ones lazily
--     (RestyleFarPerFrame a frame), so it never stutters; a light that streams in or is registered later takes the
--     state at once; a light whose tag is taken away (a wrecked car) goes dark.
--   * The clock: the server sends it once a second (the workspace attributes ClockHour and ClockRate); here it runs
--     smoothly in between, Lighting.ClockTime written only when it moved Config.LivingCity.Clock Step hours (5.9.2:
--     every write re-lights and re-shadows the world; 0.01 h is a fraction of a degree of the sun, never a visible jump).
--   * The lighthouse's two beams sweep round at night (the parts tagged "LighthouseBeam": their Hub and Beam
--     attributes), the radio mast's beacon blinks ("RadioBeacon").
--   * A few broken street lamps ("BrokenLamp") flicker at night, the red flares on the streets ("Flare") burn
--     unsteadily, only within FlickerRange of the camera (each flare's light looked up once).
--   * 6.13.1, the light budget (a phone: design/performance/REPORT.md): the night lights' real lights (a lamp's pool on
--     the road, a window's glow, a headlight's beam) are expensive to draw, so only the nearest ones shine:
--     RenderBudget.choose (Config.Performance MaxLights within LightRange of the camera; a phone or a tablet its Lite
--     numbers, client/DeviceBudget.luau), chosen again every LightEvery seconds. A vehicle's lights go together (both
--     headlights or neither); one that shines keeps shining a little past the range and the count (LightHoldRange,
--     LightHoldExtra: nothing blinks at the edge); a light fades in and out over LightFade seconds (its Brightness; a
--     broken lamp's flicker snaps). Every lamp still glows (its part turns Neon); the far ones just light nothing.
--     Every Light found in or as a night light takes part (found when it is restyled or streams in), whoever switches it
--     (a server write that lights one over the budget is put out again).
--   * 6.16, a soft haze around the street lamps at night: the nearest few lamps that shine within the budget glow
--     faintly (Config.Atmosphere.Halo: one ParticleEmitter in the lamp's head, a few big soft particles; none on a phone
--     by default), chosen again with the budget.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RenderBudget = require(Shared:WaitForChild("RenderBudget"))
local DeviceBudget = require(script.Parent.DeviceBudget)

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

-- ── 6.13.1: the light budget ───────────────────────────────────────────────

local Performance = Config.Performance
local VEHICLE_FOLDERS: { [string]: boolean } = { Cars = true, BanditCars = true, Traffic = true, Buses = true }

local budget = {
	lights = {} :: { Light }, -- every Light of a night light seen (the gone ones dropped at the next choice)
	known = {} :: { [Light]: boolean },
	shining = {} :: { [Light]: boolean }, -- within the budget at the last choice
	group = {} :: { [Light]: Instance }, -- what it goes with: its vehicle's model, else the light itself
	full = {} :: { [Light]: number }, -- its own brightness (it fades from and to it)
	target = {} :: { [Light]: boolean }, -- on or off, as this client last decided
	fades = {} :: { [Light]: Tween },
	held = {} :: { [Instance]: number }, -- a broken lamp out right now (its part: until when), startMoving's
	chosenAt = 0,
}

-- A vehicle's lights go together: the model right under workspace.Cars / BanditCars / Traffic / Buses.
local function groupOf(light: Light): Instance
	local node: Instance? = light.Parent
	while node do
		local parent = node.Parent
		if parent and parent.Parent == workspace and VEHICLE_FOLDERS[parent.Name] then
			return node
		end
		node = parent
	end
	return light
end

local function register(light: Light)
	if not budget.known[light] then
		budget.known[light] = true
		table.insert(budget.lights, light)
		budget.group[light] = groupOf(light)
		budget.full[light] = if light.Brightness > 0 then light.Brightness else 1
	end
end

-- Forgets a light (gone, or no night light any more): its fade stopped, its own brightness back.
local function forget(light: Light)
	local fading = budget.fades[light]
	if fading then
		fading:Cancel()
		budget.fades[light] = nil
	end
	local full = budget.full[light]
	if full and light.Parent then
		light.Brightness = full
	end
	budget.known[light] = nil
	budget.shining[light] = nil
	budget.group[light] = nil
	budget.full[light] = nil
	budget.target[light] = nil
end

-- Where a light shines from: its part, or its attachment (a bike's lamp).
local function lightAt(light: Light): Vector3?
	local parent = light.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

-- A light on or off: its Brightness fades over LightFade seconds (snap: at once), off at the end of a fade out.
local function fade(light: Light, on: boolean, snap: boolean)
	local running = budget.fades[light]
	if running then
		running:Cancel()
		budget.fades[light] = nil
	end
	local full = budget.full[light] or 1
	if snap or Performance.LightFade <= 0 then
		light.Brightness = full
		light.Enabled = on
		return
	end
	if on then
		if not light.Enabled then
			light.Brightness = 0
			light.Enabled = true
		elseif math.abs(light.Brightness - full) < 1e-3 then
			return
		end
	elseif not light.Enabled then
		light.Brightness = full
		return
	end
	local made = TweenService:Create(light, TweenInfo.new(Performance.LightFade), { Brightness = if on then full else 0 })
	budget.fades[light] = made
	made.Completed:Connect(function(state: Enum.PlaybackState)
		if budget.fades[light] ~= made then
			return
		end
		budget.fades[light] = nil
		if state == Enum.PlaybackState.Completed and not on and budget.target[light] == false then
			light.Enabled = false
			light.Brightness = full
		end
	end)
	made:Play()
end

-- One Light of a night light on or off: on only within the budget (and not a broken lamp flickering out). snap: no fade
-- (the flicker).
local function switch(light: Light, on: boolean, snap: boolean?)
	register(light)
	local want = on and budget.shining[light] == true and budget.held[light.Parent :: Instance] == nil
	if budget.target[light] ~= want then
		budget.target[light] = want
		fade(light, want, snap == true)
	elseif not want and light.Enabled and not budget.fades[light] then
		fade(light, false, true) -- (a server write lit it again: out at once)
	elseif want and not light.Enabled then
		fade(light, true, snap == true) -- (a server write put it out)
	end
end

-- 6.16: a soft haze around the street lamps at night (Config.Atmosphere.Halo): the Count nearest lamp heads (World's
-- lamp(): a part "Lamp" with its SpotLight) whose light shines within the budget, within Range of the camera, not a
-- broken one, get one faint glowing puff (a ParticleEmitter in the head, a few big soft particles that barely move); a
-- phone or a tablet Lite of them. Looked at with the light budget; the rest are taken away (by day: all of them).
local halos: { [BasePart]: ParticleEmitter } = {}
local HALO = Config.Atmosphere.Halo

local function newHalo(head: BasePart): ParticleEmitter
	local lit = head:GetAttribute("LitColor")
	local glow = Instance.new("ParticleEmitter")
	glow.Name = "LampHaze"
	glow.Texture = "rbxasset://textures/particles/smoke_main.dds"
	glow.Color = ColorSequence.new(if typeof(lit) == "Color3" then lit else Color3.fromRGB(255, 214, 150))
	glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, HALO.Transparency), NumberSequenceKeypoint.new(0.7, HALO.Transparency), NumberSequenceKeypoint.new(1, 1) })
	glow.Size = NumberSequence.new(HALO.Size * 0.85, HALO.Size)
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.Lifetime = NumberRange.new(3, 4)
	glow.Rate = 1
	glow.Speed = NumberRange.new(0)
	glow.Rotation = NumberRange.new(0, 360)
	glow.RotSpeed = NumberRange.new(-8, 8)
	glow.LockedToPart = true
	glow.ZOffset = 0.5
	glow.Parent = head
	return glow
end

local function hazeLamps(eye: Vector3, night: boolean)
	local most = if DeviceBudget.lite then HALO.Lite else HALO.Count
	local near: { { head: BasePart, distance: number } } = {}
	if night and most > 0 then
		for _, light in budget.lights do
			local head = light.Parent
			if budget.shining[light] and light:IsA("SpotLight") and head and head:IsA("BasePart") and head.Name == "Lamp" and not CollectionService:HasTag(head, "BrokenLamp") then
				local distance = (head.Position - eye).Magnitude
				if distance <= HALO.Range then
					table.insert(near, { head = head, distance = distance })
				end
			end
		end
		table.sort(near, function(a, b)
			return a.distance < b.distance
		end)
	end
	local keep: { [BasePart]: boolean } = {}
	for n = 1, math.min(most, #near) do
		keep[near[n].head] = true
	end
	for head, glow in halos do
		if not keep[head] then
			halos[head] = nil
			glow:Destroy()
		end
	end
	for head in keep do
		if not halos[head] then
			halos[head] = newHalo(head)
		end
	end
end

-- Every LightEvery seconds: the nearest within range shine (a vehicle's lights together, a little hold at the edge),
-- the rest fade out.
local function chooseLights()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local kept: { Light } = {}
	local seen: { [Light]: boolean } = {}
	local units: { RenderBudget.Unit } = {}
	local members: { [number]: { Light } } = {}
	local unitOf: { [Instance]: number } = {}
	for _, light in budget.lights do
		if seen[light] then
			continue -- (listed twice: forgotten and found again in between)
		end
		local at = if budget.known[light] and light.Parent then lightAt(light) else nil
		if at then
			seen[light] = true
			table.insert(kept, light)
			local key = budget.group[light] or light
			local distance = (at - eye).Magnitude
			local index: number = unitOf[key] or 0
			if index == 0 then
				table.insert(units, { distance = distance, size = 0, on = false })
				index = #units
				unitOf[key] = index
				members[index] = {}
			end
			local unit = units[index]
			unit.distance = math.min(unit.distance, distance)
			unit.size += 1
			unit.on = unit.on or budget.shining[light] == true
			table.insert(members[index], light)
		elseif budget.known[light] then
			forget(light) -- (gone: streamed out, destroyed)
		end
	end
	budget.lights = kept
	local most, range = RenderBudget.numbers(DeviceBudget.lite)
	local chosen = RenderBudget.choose(units, most, range)
	local night = nightNow()
	for index, list in members do
		local on = chosen[index] == true
		for _, light in list do
			if on then
				budget.shining[light] = true
			else
				budget.shining[light] = nil
			end
			switch(light, night)
		end
	end
	hazeLamps(eye, night) -- 6.16
end

-- How many Lights of the night lights this client knows and how many shine now (the admin's overlay).
function WorldFx.lightCount(): (number, number)
	local shining = 0
	for _, light in budget.lights do
		if light.Enabled and light.Parent then
			shining += 1
		end
	end
	return #budget.lights, shining
end

-- One night light on or off (the same as the server's DayNight: the part, its lights, or a tagged light itself). snap:
-- its lights at once, no fade (a broken lamp's flicker).
local function apply(item: Instance, on: boolean, snap: boolean?)
	if item:IsA("Light") then
		switch(item, on, snap)
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
			switch(child, on, snap)
		end
	end
end

-- A light whose tag was taken away: dark for good (its colour only if it still shows the lit one: the server may have
-- painted it since, a burnt-out car).
local function darken(item: Instance)
	if item:IsA("Light") then
		forget(item)
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
			forget(child)
			child.Enabled = false
		end
	end
end

-- A tagged set kept as a list (added and removed with the tag, streaming included).
local function watch(tag: string, list: { Instance }, removed: ((Instance) -> ())?)
	local function add(item: Instance)
		if not table.find(list, item) then
			table.insert(list, item)
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
		if removed then
			removed(item)
		end
	end)
end

-- ── The night lights ───────────────────────────────────────────────────────

-- Where a night light is (a light: its part's place), or nil.
local function placeOf(item: Instance): Vector3?
	if item:IsA("BasePart") then
		return item.Position
	end
	local parent = item.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function startRestyle()
	-- 5.9.2: two queues, the lights near the camera first (a few a frame), then the far ones (fewer a frame).
	local near: { Instance } = {}
	local far: { Instance } = {}
	local nearAt, farAt = 1, 1
	local state = nightNow()
	local function restart()
		state = nightNow()
		near, far = {}, {}
		nearAt, farAt = 1, 1
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else nil
		local range = Tuning.RestyleNear
		for _, item in CollectionService:GetTagged(NIGHT_TAG) do
			local at = if eye then placeOf(item) else nil
			if at and eye and (at - eye).Magnitude <= range then
				table.insert(near, item)
			else
				table.insert(far, item)
			end
		end
	end
	restart()
	workspace:GetAttributeChangedSignal("Night"):Connect(restart)
	CollectionService:GetInstanceAddedSignal(NIGHT_TAG):Connect(function(item)
		apply(item, nightNow())
	end)
	CollectionService:GetInstanceRemovedSignal(NIGHT_TAG):Connect(darken)
	local function run(queue: { Instance }, from: number, count: number): number
		local last = math.min(#queue, from + count - 1)
		for n = from, last do
			local item = queue[n]
			-- (one that left in the meantime, or lost its tag, is skipped)
			if item.Parent and CollectionService:HasTag(item, NIGHT_TAG) then
				pcall(apply, item, state)
			end
		end
		return last + 1
	end
	local every = Config.Performance.LightEvery
	RunService.Heartbeat:Connect(function()
		if nearAt <= #near then
			nearAt = run(near, nearAt, Tuning.RestyleNearPerFrame)
		elseif farAt <= #far then
			farAt = run(far, farAt, Tuning.RestyleFarPerFrame)
		end
		-- 6.13.1: the light budget, a few times a second
		local now = os.clock()
		if now - budget.chosenAt >= every then
			budget.chosenAt = now
			chooseLights()
		end
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
		-- 5.9.2: written only when it moved a step (either way round the clock; a jump back is written at once too).
		local moved = math.abs(Lighting.ClockTime - now)
		if math.min(moved, 24 - moved) >= Config.LivingCity.Clock.Step then
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
	local flareLights: { [Instance]: PointLight? } = {} -- 5.9.2: each flare's light, looked up once
	watch("LighthouseBeam", beams)
	watch("RadioBeacon", beacons)
	watch("BrokenLamp", broken)
	watch("Flare", flares, function(item)
		flareLights[item] = nil
	end)
	local angle = 0
	local blinkClock, flickerClock = 0, 0
	local beaconOn = true
	local dark = budget.held -- a broken lamp that is out right now: until when (os.clock; 6.13.1: the budget leaves it out)
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
		local range = DeviceBudget.range(Tuning.FlickerRange) -- (6.13.1: closer on a phone)
		for _, lamp in broken do
			if not lamp:IsA("BasePart") then
				continue
			end
			local near = night and (lamp.Position - eye).Magnitude < range
			local outUntil = dark[lamp]
			if outUntil then
				if not near or now >= outUntil then
					dark[lamp] = nil
					apply(lamp, night, true)
				end
			elseif near and rand:NextNumber() < 0.07 then
				dark[lamp] = now + rand:NextNumber(0.05, 0.5)
				apply(lamp, false, true)
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
					local light: PointLight? = flareLights[flare]
					if not light or light.Parent ~= flare then
						light = flare:FindFirstChildOfClass("PointLight")
						flareLights[flare] = light
					end
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
