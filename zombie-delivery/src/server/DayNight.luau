--!strict
-- Day and night (Config.DayNight). The server runs the clock: Lighting.ClockTime goes round once every
-- DayLength seconds (it replicates, so every client has the same sun and moon). It keeps the workspace attribute
-- "Night" (boolean, replicated) and switches every night light with it: the street lamps, the lit windows, the
-- headlights and tail lights of every car (server/World.luau and server/Vehicles.luau register them with
-- DayNight.nightLight). The look of the night (darker ambient, moonlight blue, the dusk glow) is drawn on every
-- client from the same clock (client/Weather.luau, Map.nightFactor), so nothing but the clock is sent each tick.
--
-- Jobs and Zombies ask DayNight.isNight() / DayNight.nightFactor() (more zombies, better pay at night); the admin
-- panel's time buttons call DayNight.setClock. Anything that sets Lighting.ClockTime directly works too: the clock
-- goes on from wherever it is.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)

local DayNight = {}

DayNight.Tag = "NightLight" -- CollectionService tag of everything that lights up at night
local TICK = 0.25 -- seconds between clock steps (the sun moves 0.0063 h per step: invisible)

local DIM_MATERIALS: { [string]: Enum.Material } = {
	Glass = Enum.Material.Glass,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Plastic = Enum.Material.Plastic,
}

local started = false

-- Is it night now (Config.DayNight NightFrom … NightTo)?
function DayNight.isNight(): boolean
	return Map.isNight(Lighting.ClockTime)
end

-- 0 in full day … 1 in deep night (smooth around dusk and dawn), for scaling the waves, roamers and pay.
function DayNight.nightFactor(): number
	return Map.nightFactor(Lighting.ClockTime)
end

-- The clock now (0 … 24).
function DayNight.hour(): number
	return Lighting.ClockTime
end

-- One night light on or off: a part turns Neon in its lit colour (or back to its dim colour and material), the
-- lights in it (and a tagged light itself) are switched.
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

local function nightNow(): boolean
	return workspace:GetAttribute("Night") == true
end

-- Registers a part that glows at night (a lamp head, a window, a headlight): Neon in `lit` at night, `dim` in
-- `dimMaterial` (default SmoothPlastic: Glass, SmoothPlastic, Metal, Plastic) by day. The Lights inside it go on and
-- off with it. Also takes a Light alone (it is only switched). Sets the right state at once.
function DayNight.nightLight(item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?)
	if item:IsA("BasePart") then
		if lit and dim then
			item:SetAttribute("LitColor", lit)
			item:SetAttribute("DimColor", dim)
		end
		if dimMaterial then
			item:SetAttribute("DimMaterial", dimMaterial)
		end
	end
	CollectionService:AddTag(item, DayNight.Tag)
	apply(item, nightNow())
end

local function switchAll(on: boolean)
	for _, item in CollectionService:GetTagged(DayNight.Tag) do
		apply(item, on)
	end
end

-- Keeps the Night attribute (and the lights) in step with the clock.
local function update()
	local night = DayNight.isNight()
	if workspace:GetAttribute("Night") ~= night then
		workspace:SetAttribute("Night", night)
		switchAll(night)
	end
end

-- Set the clock (the admin panel's time buttons). The lights follow at once.
function DayNight.setClock(hour: number)
	Lighting.ClockTime = hour % 24
	update()
end

function DayNight.start()
	if started then
		return
	end
	started = true
	Lighting.ClockTime = Config.DayNight.StartHour % 24
	workspace:SetAttribute("Night", DayNight.isNight())
	switchAll(nightNow())
	-- Lights registered by other code (or cloned in) take the current state.
	CollectionService:GetInstanceAddedSignal(DayNight.Tag):Connect(function(item)
		apply(item, nightNow())
	end)
	local hoursPerSecond = 24 / math.max(Config.DayNight.DayLength, 1)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = math.min(now - last, 2) -- a long server hitch does not skip an hour
			last = now
			Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
			update()
		end
	end)
end

return DayNight
