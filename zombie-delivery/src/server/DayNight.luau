--!strict
-- Day and night (Config.DayNight). The server runs the clock: Lighting.ClockTime goes round once every
-- DayLength seconds (it replicates, so every client has the same sun and moon). It keeps the workspace attribute
-- "Night" (boolean, replicated); the night lights (the street lamps, the lit windows, the headlights and tail lights of
-- every car: server/World.luau and server/Vehicles.luau register them with DayNight.nightLight, which tags them) take
-- the state they are registered in, and 5.7: every client restyles them itself when the Night attribute turns
-- (client/WorldFx.luau), so a dusk no longer rewrites thousands of parts from the server. The look of the night
-- (darker ambient, moonlight blue, the dusk glow) is drawn on every client from the same clock (client/Weather.luau,
-- Map.nightFactor), so nothing but the clock is sent.
-- 5.7: the clock is sent once a Config.LivingCity.Clock.SendEvery (Lighting.ClockTime and the workspace attribute
-- "ClockHour", with "ClockRate": hours a second); every client runs it smoothly in between (client/WorldFx.luau).
-- 5.7, the weather (shared/WeatherPlan.luau): now and then a rain or a fog, the workspace attribute "Weather"
-- ("clear" | "rain" | "fog"); DayNight.setWeather sets one (the admin panel can).
--
-- Jobs and Zombies ask DayNight.isNight() / DayNight.nightFactor() (more zombies, better pay at night); the admin
-- panel's time buttons call DayNight.setClock. Anything that sets Lighting.ClockTime directly works too: the clock
-- goes on from wherever it is.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local WeatherPlan = require(Shared.WeatherPlan)

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
-- The clock as the server runs it (Lighting.ClockTime is only written every SendEvery seconds) and what it last wrote.
local clock = 0
local written = -1
local writtenAt = 0

-- The clock now (0 … 24). (Before the clock starts: whatever Lighting holds.)
function DayNight.hour(): number
	return if started then clock else Lighting.ClockTime
end

-- Is it night now (Config.DayNight NightFrom … NightTo)?
function DayNight.isNight(): boolean
	return Map.isNight(DayNight.hour())
end

-- 0 in full day … 1 in deep night (smooth around dusk and dawn), for scaling the waves, roamers and pay.
function DayNight.nightFactor(): number
	return Map.nightFactor(DayNight.hour())
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

-- Sends the clock (Lighting.ClockTime and the ClockHour attribute the clients run on from).
local function send()
	written = clock
	writtenAt = os.clock()
	Lighting.ClockTime = clock
	workspace:SetAttribute("ClockHour", clock)
end

-- Keeps the Night attribute in step with the clock (5.7: the clients switch the lights, client/WorldFx.luau).
local function update()
	local night = Map.isNight(clock)
	if workspace:GetAttribute("Night") ~= night then
		workspace:SetAttribute("Night", night)
	end
end

-- Set the clock (the admin panel's time buttons). The lights follow at once.
function DayNight.setClock(hour: number)
	clock = hour % 24
	send()
	update()
end

-- ── The weather (5.7) ──────────────────────────────────────────────────────

local weatherUntil = 0 -- os.clock() when the current spell (or the calm, or the wait for a roll) ends
local weatherRand = Random.new()

local function setWeather(state: string, seconds: number)
	workspace:SetAttribute("Weather", state)
	weatherUntil = os.clock() + seconds
end

-- A rain, a fog or clear weather now (the admin panel): a spell lasts its usual minutes, clear weather its calm.
function DayNight.setWeather(state: string)
	if state ~= "rain" and state ~= "fog" then
		setWeather("clear", Config.LivingCity.Weather.Calm * 60)
		return
	end
	local _, seconds = WeatherPlan.roll(DayNight.isNight(), 0, weatherRand:NextNumber())
	setWeather(state, seconds)
end

function DayNight.weather(): string
	local state = workspace:GetAttribute("Weather")
	return if type(state) == "string" then state else "clear"
end

-- Every few seconds: a spell that is over turns clear (then a calm), clear weather rolls when its wait is over.
local function stepWeather()
	if os.clock() < weatherUntil then
		return
	end
	if DayNight.weather() ~= "clear" then
		setWeather("clear", Config.LivingCity.Weather.Calm * 60)
		return
	end
	local state, seconds = WeatherPlan.roll(DayNight.isNight(), weatherRand:NextNumber(), weatherRand:NextNumber())
	setWeather(state, seconds)
end

function DayNight.start()
	if started then
		return
	end
	started = true
	local hoursPerSecond = 24 / math.max(Config.DayNight.DayLength, 1)
	clock = Config.DayNight.StartHour % 24
	workspace:SetAttribute("ClockRate", hoursPerSecond)
	send()
	workspace:SetAttribute("Night", Map.isNight(clock))
	-- (the lights registered before the clock started take its state)
	for _, item in CollectionService:GetTagged(DayNight.Tag) do
		apply(item, nightNow())
	end
	-- Lights registered by other code (or cloned in) take the current state.
	CollectionService:GetInstanceAddedSignal(DayNight.Tag):Connect(function(item)
		apply(item, nightNow())
	end)
	setWeather("clear", Config.LivingCity.Weather.Calm * 60)
	local sendEvery = Config.LivingCity.Clock.SendEvery
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = math.min(now - last, 2) -- a long server hitch does not skip an hour
			last = now
			-- Somebody set Lighting.ClockTime directly: the clock goes on from there.
			if math.abs(Lighting.ClockTime - written) > 1e-3 then
				clock = Lighting.ClockTime % 24
				writtenAt = 0
			end
			clock = (clock + dt * hoursPerSecond) % 24
			if now - writtenAt >= sendEvery then
				send()
			end
			update()
			stepWeather()
		end
	end)
end

return DayNight
