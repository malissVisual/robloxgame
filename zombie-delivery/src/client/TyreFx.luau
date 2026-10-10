--!strict
-- 6.16, the tyres (the owner: "dust and smoke from the wheels, skid marks"): what a car's wheels throw, by the ground
-- under it (a ray down a few times a second: shared/DriveFeel.luau surface) and how hard they work (DriveFeel.strain from
-- client/CarSway.luau's motion): dust off grass and dirt, snow spray in the winter and on the lake's ice, a light smoke
-- on asphalt on a hard brake, a fast sharp turn, a slide or a hard launch; then dark skid marks on the asphalt behind
-- the wheels (all four on a hard brake, the rear ones in a turn), fading out after a few seconds (Config.DriveFeel
-- Tyres, Skids). Every player's car and bike (client/CarVisuals.luau's perCar hook), within Tyres.Range of the camera.
-- Cheap: the emitters are a small pool (a kit of an Attachment and a ParticleEmitter for each rear wheel) lent to the
-- nearest Tyres.Cars cars that throw something (yours first) and taken back when they stop; a rate is written only when
-- it changes. The marks are a ring of at most Skids.Count anchored strips (the oldest is used again), faded a few times
-- a second. A phone (DeviceBudget.lite): only your own car, Tyres.Lite of the particles, Skids.Lite of the marks; on
-- its lowest graphics (1 … 3) nothing at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DriveFeel = require(Shared:WaitForChild("DriveFeel"))
local Map = require(Shared:WaitForChild("Map"))

local CarSway = require(script.Parent.CarSway)
local CarVisuals = require(script.Parent.CarVisuals)
local DeviceBudget = require(script.Parent.DeviceBudget)

local TyreFx = {}

local Tyres = Config.DriveFeel.Tyres
local Skids = Config.DriveFeel.Skids
local GROUND_MINE = 0.12 -- seconds between the rays down under your car …
local GROUND_OTHERS = 0.3 -- … and under another one
local ASSIGN_EVERY = 0.3 -- seconds between the looks at which cars get the emitters
local QUIET = 2.2 -- seconds a kit stays on a car after it stops (its last puffs live out)
local JUMP = 6 -- studs: a wheel further than this from its mark's end since the last frame starts a new one
local FADE_EVERY = 0.25 -- seconds between the marks' fades
local LIFT = 0.04 -- studs a mark floats over the ground (no flicker with the road)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

type Wheel = {
	offset: Vector3, -- where it touches the ground, in the chassis' space
	width: number,
	rear: boolean,
	last: Vector3?, -- where its mark reached
	mark: Part?, -- the strip it lengthens now
	markFrom: Vector3?,
}
type Kit = { attachments: { Attachment }, emitters: { ParticleEmitter }, kind: string, rate: number, quietAt: number }
type Track = {
	wheels: { Wheel },
	kit: Kit?,
	surface: string, -- "road", "dirt", "snow" or "air"
	groundAt: number,
	seenAt: number,
	distance: number,
	mine: boolean,
	busy: boolean, -- it throws something now (wants a kit)
	marking: boolean, -- its wheels lay marks now
	chassis: BasePart,
}
type Mark = { part: Part, born: number, opacity: number, live: boolean }

local tracks: { [Model]: Track } = {}
local free: { Kit } = {}
local kitCount = 0
local marks: { Mark } = {}
local markOf: { [Part]: Mark } = {}
local nextMark = 1
local markFolder: Folder? = nil
local clocks = { assign = 0, fade = 0, quality = -math.huge }
local tier = { low = false } -- a phone on its lowest graphics
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

-- A phone on its lowest graphics (the saved slider at 1 … 3) gets nothing (looked at every few seconds).
local function lowTier(): boolean
	local now = os.clock()
	if now - clocks.quality > 5 then
		clocks.quality = now
		local low = false
		if DeviceBudget.lite then
			pcall(function()
				local saved = UserSettings().GameSettings.SavedQualityLevel
				low = saved ~= Enum.SavedQualitySetting.Automatic and saved.Value <= 3
			end)
		end
		tier.low = low
	end
	return tier.low
end

local function wheelsOf(chassis: BasePart): { Wheel }
	local list: { Wheel } = {}
	local frame = chassis.CFrame
	for _, child in chassis:GetChildren() do
		if child:IsA("Motor6D") and child.Name == "WheelMotor" then
			local part0, tyre = child.Part0, child.Part1
			if part0 and tyre then
				local radius = (child:GetAttribute("Radius") or 1.3) :: number
				local centre = frame:PointToObjectSpace((part0.CFrame * child.C0).Position)
				table.insert(list, {
					offset = centre - Vector3.new(0, radius, 0),
					width = math.clamp(tyre.Size.X * 0.7, 0.2, 1),
					rear = child:GetAttribute("Front") ~= true,
					last = nil,
					mark = nil,
					markFrom = nil,
				})
			end
		end
	end
	return list
end

-- ── The particles ──────────────────────────────────────────────────────────

local function look(emitter: ParticleEmitter, kind: string)
	if kind == "dust" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(146, 124, 96), Color3.fromRGB(176, 160, 134))
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 3.2) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(0.9, 1.5)
		emitter.Speed = NumberRange.new(2, 4.5)
		emitter.SpreadAngle = Vector2.new(35, 20)
		emitter.Acceleration = Vector3.new(0, 1.2, 0)
		emitter.Drag = 1.5
	elseif kind == "snow" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(242, 246, 252))
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1.4) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(5, 8)
		emitter.SpreadAngle = Vector2.new(40, 25)
		emitter.Acceleration = Vector3.new(0, -14, 0)
		emitter.Drag = 1
	else
		emitter.Color = ColorSequence.new(Color3.fromRGB(212, 212, 216), Color3.fromRGB(236, 236, 238))
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 5) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(1.2, 2)
		emitter.Speed = NumberRange.new(1.5, 3)
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.Acceleration = Vector3.new(0, 1.6, 0)
		emitter.Drag = 1.2
	end
end

local function newKit(): Kit
	local kit: Kit = { attachments = {}, emitters = {}, kind = "", rate = 0, quietAt = 0 }
	for n = 1, 2 do
		local at = Instance.new("Attachment")
		at.Name = "TyreFx"
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "TyreFx"
		emitter.Texture = SMOKE
		emitter.EmissionDirection = Enum.NormalId.Back -- out behind the wheel
		emitter.LightInfluence = 1
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-25, 25)
		emitter.VelocityInheritance = 0
		emitter.Rate = 0
		emitter.Parent = at
		kit.attachments[n] = at
		kit.emitters[n] = emitter
	end
	kitCount += 1
	return kit
end

-- Back to the pool (or dropped: its attachments went with a car that is gone).
local function release(track: Track)
	local kit = track.kit
	if not kit then
		return
	end
	track.kit = nil
	local ok = true
	for n, at in kit.attachments do
		kit.emitters[n].Rate = 0
		if not pcall(function()
			at.Parent = nil
		end) then
			ok = false
		end
	end
	kit.rate = 0
	if ok then
		table.insert(free, kit)
	else
		kitCount -= 1
	end
end

local function takeKit(most: number): Kit?
	local kit = table.remove(free)
	if kit then
		return kit
	elseif kitCount < most then
		return newKit()
	end
	-- all lent: the quiet one furthest away gives its kit up (its last puffs end early)
	local giver: Track? = nil
	local far = -1
	for _, other in tracks do
		if other.kit and not other.busy and other.distance > far then
			giver, far = other, other.distance
		end
	end
	if not giver then
		return nil
	end
	release(giver)
	return table.remove(free)
end

local function lend(track: Track, most: number): boolean
	local kit = takeKit(most)
	if not kit then
		return false
	end
	local rear: { Wheel } = {}
	for _, wheel in track.wheels do
		if wheel.rear then
			table.insert(rear, wheel)
		end
	end
	for n, at in kit.attachments do
		local wheel = rear[n]
		if wheel then
			at.Position = wheel.offset + Vector3.new(0, 0.25, 0.35)
			local ok = pcall(function()
				at.Parent = track.chassis
			end)
			if not ok then
				kitCount -= 1 -- (its car is going: the kit goes with it)
				return false
			end
		end
	end
	kit.kind = ""
	kit.rate = 0
	track.kit = kit
	return true
end

local function setKit(kit: Kit, kind: string, rate: number)
	if kind ~= kit.kind then
		kit.kind = kind
		for _, emitter in kit.emitters do
			look(emitter, kind)
		end
	end
	if math.abs(rate - kit.rate) >= 0.5 or (rate == 0) ~= (kit.rate == 0) then
		if rate == 0 then
			kit.quietAt = os.clock()
		end
		kit.rate = rate
		for n, emitter in kit.emitters do
			emitter.Rate = if kit.attachments[n].Parent then rate else 0
		end
	end
end

-- Which cars hold the emitters: the busy ones, yours first, then the nearest (a phone: yours only).
local function assign()
	local most = if lowTier() then 0 elseif DeviceBudget.lite then 1 else Tyres.Cars
	local now = os.clock()
	local wanted: { Track } = {}
	for car, track in tracks do
		if car.Parent == nil or now - track.seenAt > 1 then
			release(track)
			if car.Parent == nil then
				tracks[car] = nil
			end
		elseif track.busy and (track.mine or not DeviceBudget.lite) then
			table.insert(wanted, track)
		elseif track.kit and track.kit.rate == 0 and now - track.kit.quietAt > QUIET then
			release(track) -- quiet a while: back to the pool
		end
	end
	table.sort(wanted, function(a: Track, b: Track): boolean
		if a.mine ~= b.mine then
			return a.mine
		end
		return a.distance < b.distance
	end)
	for n, track in wanted do
		if n > most then
			release(track)
		elseif not track.kit then
			lend(track, most)
		end
	end
end

-- ── The skid marks ─────────────────────────────────────────────────────────

local function markCap(): number
	if lowTier() then
		return 0
	end
	return if DeviceBudget.lite then math.floor(Skids.Count * Skids.Lite) else Skids.Count
end

local function takeMark(opacity: number): Part?
	local cap = markCap()
	if cap <= 0 then
		return nil
	end
	local folder = markFolder
	if not folder or folder.Parent ~= workspace then
		local made = Instance.new("Folder")
		made.Name = "SkidMarks"
		made.Parent = workspace
		folder = made
		markFolder = made
		table.clear(marks)
		table.clear(markOf)
		nextMark = 1
	end
	if nextMark > cap then
		nextMark = 1
	end
	local mark = marks[nextMark]
	if not mark then
		local part = Instance.new("Part")
		part.Name = "SkidMark"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(20, 20, 22)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = folder
		mark = { part = part, born = 0, opacity = 0, live = false }
		marks[nextMark] = mark
		markOf[part] = mark
	end
	nextMark += 1
	mark.born = os.clock()
	mark.opacity = opacity
	mark.live = true
	mark.part.Transparency = 1 - opacity
	return mark.part
end

local function lay(part: Part, from: Vector3, to: Vector3, width: number, up: Vector3)
	local length = (to - from).Magnitude
	part.Size = Vector3.new(width, 0.02, length + width * 0.5)
	part.CFrame = CFrame.lookAt((from + to) / 2, to, up)
end

local function fade()
	local now = os.clock()
	for _, mark in marks do
		if mark.live then
			local age = now - mark.born
			if age >= Skids.Life then
				mark.live = false
				mark.part.Transparency = 1
			elseif age >= Skids.FadeFrom then
				local left = 1 - DriveFeel.ramp(age, Skids.FadeFrom, Skids.Life)
				mark.part.Transparency = 1 - mark.opacity * left
			end
		end
	end
end

local function skid(track: Track, frame: CFrame, strength: number, braking: boolean)
	local up = frame.UpVector
	for _, wheel in track.wheels do
		if strength <= 0 or not (wheel.rear or braking) then
			wheel.last, wheel.mark, wheel.markFrom = nil, nil, nil
			continue
		end
		local at = frame:PointToWorldSpace(wheel.offset) + up * LIFT
		local last = wheel.last
		if not last then
			wheel.last = at
			continue
		end
		local step = at - last
		if step.Magnitude < Skids.Step then
			continue
		elseif step.Magnitude > JUMP then
			wheel.last, wheel.mark, wheel.markFrom = at, nil, nil -- (a hitch, a jump of the picture: no long strip)
			continue
		end
		local mark, from = wheel.mark, wheel.markFrom
		if mark and from and mark.Parent and (at - from).Magnitude <= Skids.Length
			and (at - from).Unit:Dot(step.Unit) > 0.985 and (markOf[mark] and markOf[mark].live) then
			lay(mark, from, at, wheel.width, up) -- lengthened while it runs straight
		else
			local made = takeMark(Skids.Opacity * (0.55 + 0.45 * strength))
			if made then
				lay(made, last, at, wheel.width, up)
			end
			wheel.mark, wheel.markFrom = made, last
		end
		wheel.last = at
	end
end

-- ── Every car, every frame ─────────────────────────────────────────────────

local function step(car: Model, chassis: BasePart, _dt: number, distance: number, mine: boolean)
	local track = tracks[car]
	local range = if lowTier() then -1 elseif DeviceBudget.lite then (if mine then Tyres.Range else -1) else Tyres.Range
	if distance > range then
		if track then
			track.busy = false
			if track.kit then
				setKit(track.kit, track.kit.kind, 0)
			end
		end
		return
	end
	local motion = CarSway.motion(car)
	if not motion then
		return
	end
	local now = os.clock()
	local t: Track
	if track and track.chassis == chassis then
		t = track
	else
		if track then
			release(track)
		end
		t = {
			wheels = wheelsOf(chassis),
			kit = nil,
			surface = "air",
			groundAt = -math.huge,
			seenAt = now,
			distance = distance,
			mine = mine,
			busy = false,
			marking = false,
			chassis = chassis,
		}
		tracks[car] = t
	end
	t.seenAt, t.distance, t.mine = now, distance, mine

	-- The ground under it, a few times a second.
	if now - t.groundAt > (if mine then GROUND_MINE else GROUND_OTHERS) then
		t.groundAt = now
		rayParams.FilterDescendantsInstances = { car }
		local at = chassis.Position
		local hit = workspace:Raycast(at, Vector3.new(0, -7, 0), rayParams)
		t.surface = if hit then DriveFeel.surface(hit.Material.Name, Map.isWinter(at.X, at.Z), Map.onIce(at.X, at.Z)) else "air"
	end

	local forward = motion.forward
	local direction = if math.abs(forward) > 1 then math.sign(forward) else 0
	local decel = math.max(0, -motion.accel * direction)
	local speedUp = if direction == 0 then math.abs(motion.accel) else math.max(0, motion.accel * direction)
	local strain = DriveFeel.strain(forward, decel, motion.lateral, motion.slide, speedUp)
	local kind, rate, marking = "smoke", 0, 0
	if t.surface ~= "air" then
		kind, rate, marking = DriveFeel.tyres(t.surface, forward, strain)
	end
	if DeviceBudget.lite then
		rate *= Tyres.Lite
	end
	t.busy = rate > 0
	local kit = t.kit
	if kit then
		setKit(kit, kind, rate)
	end
	if marking > 0 or t.marking then
		local braking = DriveFeel.strain(forward, decel, 0, 0, 0) >= Skids.From
		skid(t, chassis.CFrame, marking, braking)
	end
	t.marking = marking > 0
end

function TyreFx.start()
	table.insert(CarVisuals.perCar, step)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - clocks.assign >= ASSIGN_EVERY then
			clocks.assign = now
			assign()
		end
		if now - clocks.fade >= FADE_EVERY then
			clocks.fade = now
			fade()
		end
	end)
end

return TyreFx
