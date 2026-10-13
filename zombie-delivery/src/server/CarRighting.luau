--!strict
-- 6.26 (6.24's BikeRighting, now every vehicle of a player: the cars, the vans, the trucks, the bikes, the E-Scooter),
-- a vehicle knocked over gets back up. Why it is needed: the steering's AngularVelocity "Steer" (server/Vehicles.luau)
-- holds every turn still, the pitch and the roll too, with about eight times the torque gravity has on a car propped
-- on one end, so a car that something tipped (the owner's screenshot: a ZDC Van 20–25° nose down, a back wheel in the
-- air) never falls back onto its wheels by itself, parked or driven. Every Config.CarUpright.Check seconds the server
-- looks at every vehicle in the world (ridden, its driver's client runs its physics; parked, the server: the numbers
-- below reach both). Down (shared/CarUpright.luau CarUpright.down: on its back at any speed; slow and tipped past its
-- kind's Tilt, or past its Lean with a wheel in the air: the rays under its wheels, Vehicles.wheelContacts) for Hold
-- seconds, its AlignOrientation "Righting" (Vehicles.righting) turns it back onto its wheels, level with the ground
-- under them (or straight up), facing where it pointed, at most TurnRate rad/s, and the Steer lets go meanwhile (its
-- MaxTorque 0: it would hold the turn back up still too). Within Settled degrees of that level both are as they were.
-- Still down after Give seconds (wedged against something) it is stood up where it lies at once, nudged to free room
-- if something is there (Vehicles.standUp). Never a car on a repair lift, an anchored one (nothing to turn) or one a
-- chauffeur drives (server/CarCall.luau: righted after the hand-over). The decisions are shared/CarUpright.luau's
-- (pure, tested). In Studio every vehicle that went down says so in the Output (how far, a wheel's gap, ridden or
-- parked), to find what tipped it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CarUpright = require(Shared.CarUpright)
local Vehicles = require(script.Parent.Vehicles)

local CarRighting = {}

local Cfg = Config.CarUpright
local UP: CarUpright.Vec = { 0, 1, 0 }

type Watch = {
	state: CarUpright.State,
	car: Vehicles.Car,
	steer: number?, -- the Steer's MaxTorque while it is let go (nil: not let go)
	up: CarUpright.Vec, -- the level it is turned back to (the ground's up under its wheels, or straight up)
}

local watches: { [Model]: Watch } = {}

type Kind = typeof(Cfg.Kinds.car)

local function kindOf(car: Vehicles.Car): Kind
	return if Vehicles.isBike(car) then Cfg.Kinds.bike else Cfg.Kinds.car
end

local function vec(v: Vector3): CarUpright.Vec
	return { v.X, v.Y, v.Z }
end

-- Which way it points on the ground (flat), however it lies.
local function headingOf(chassis: BasePart): Vector3
	local frame = chassis.CFrame
	local look, up = frame.LookVector, frame.UpVector
	local x, z = CarUpright.heading(look.X, look.Y, look.Z, up.X, up.Z)
	return Vector3.new(x, 0, z)
end

-- What a ray looking for the ground under a wheel must not see: the vehicles, the people, the zombies, the loot.
local function rayParams(): RaycastParams
	local list: { Instance } = {}
	for _, name in { "Cars", "Traffic", "BanditCars", "Npcs", "Zombies", "Animals", "Loot", "Showroom" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

-- Under its wheels: the most any of them is over the ground under it (Probe when a ray finds none) and the ground's
-- up there (nil when a ray found none or the ground is steeper than Level).
local function underWheels(car: Vehicles.Car): (number, CarUpright.Vec?)
	local frame = car.chassis.CFrame
	local params = rayParams()
	local gap, points = 0, {} :: { CarUpright.Vec }
	for _, contact in Vehicles.wheelContacts(car) do
		local at = frame * contact
		local hit = workspace:Raycast(at + Vector3.new(0, Cfg.Probe / 2, 0), Vector3.new(0, -Cfg.Probe, 0), params)
		if hit then
			gap = math.max(gap, at.Y - hit.Position.Y)
			table.insert(points, vec(hit.Position))
		else
			gap = math.max(gap, Cfg.Probe)
		end
	end
	local up = if #points == 4 then CarUpright.groundUp(points) else nil
	if up and CarUpright.angle(up, UP) > Cfg.Level then
		up = nil
	end
	return gap, up
end

-- Turn it back up: Righting on toward the ground's level (its heading kept), the Steer let go.
local function begin(watch: Watch, gap: number)
	local car = watch.car
	local chassis = car.chassis
	local righting = Vehicles.righting(car)
	if not righting then
		return
	end
	local kind = kindOf(car)
	local _, ground = underWheels(car)
	local up = ground or UP
	watch.up = up
	local heading = headingOf(chassis)
	local look, right = CarUpright.facing(heading.X, heading.Z, up)
	righting.CFrame = CFrame.fromMatrix(Vector3.zero, Vector3.new(right[1], right[2], right[3]), Vector3.new(up[1], up[2], up[3]), -Vector3.new(look[1], look[2], look[3]))
	righting.Responsiveness = kind.Responsiveness
	righting.MaxAngularVelocity = kind.TurnRate
	righting.MaxTorque = chassis.AssemblyMass * kind.Torque
	righting.Enabled = true
	local steer = chassis:FindFirstChild("Steer")
	if steer and steer:IsA("AngularVelocity") and watch.steer == nil then
		watch.steer = steer.MaxTorque
		steer.MaxTorque = 0
	end
	if RunService:IsStudio() then
		local frame = chassis.CFrame
		print(string.format("[CarRighting] %s went down (its top %.0f° off upright, rolled %.0f°, a wheel %.1f studs over the ground, %.1f studs/s, %s) for %.1f s: turning it back onto its wheels",
			car.model.Name, CarUpright.tilt(frame.UpVector.Y), CarUpright.roll(frame.RightVector.Y, frame.UpVector.Y), gap,
			Vehicles.speed(car), if car.seat.Occupant then "driven" else "parked", kind.Hold))
	end
end

-- Back as it was: Righting off, the Steer's hold back.
local function finish(watch: Watch)
	local chassis = watch.car.chassis
	local righting = chassis:FindFirstChild("Righting")
	if righting and righting:IsA("AlignOrientation") then
		righting.Enabled = false
	end
	local steer = chassis:FindFirstChild("Steer")
	local torque = watch.steer
	if steer and steer:IsA("AngularVelocity") and torque then
		steer.MaxTorque = torque
	end
	watch.steer = nil
	watch.up = UP
end

local function look()
	local now = os.clock()
	local seen: { [Model]: boolean } = {}
	for _, car in Vehicles.all() do
		local chassis = car.chassis
		if not chassis.Parent then
			continue
		end
		local found = watches[car.model]
		local watch: Watch = if found and found.car == car then found else { state = CarUpright.new(), car = car, steer = nil, up = UP }
		watches[car.model] = watch
		seen[car.model] = true
		if car.repairing or chassis.Anchored or car.chauffeured then
			-- (on a lift: nothing to turn; a chauffeur's: the server drives it, righted after the hand-over)
			if watch.steer ~= nil or watch.state.righting then
				finish(watch)
			end
			watch.state = CarUpright.new()
			continue
		end
		local kind = kindOf(car)
		local frame = chassis.CFrame
		local tilt = CarUpright.tilt(frame.UpVector.Y)
		local speed = Vehicles.speed(car)
		local gap = 0
		if not watch.state.righting and tilt > kind.Lean and tilt <= kind.Tilt and speed < Cfg.Slow then
			gap = underWheels(car) -- (the rays only for one slow and tilted: on a ramp, or resting on its nose)
		end
		local down = CarUpright.down(tilt, speed, gap, kind, Cfg.Slow, Cfg.Gap)
		local settled = CarUpright.angle(vec(frame.UpVector), watch.up) <= kind.Settled
		local action = CarUpright.step(watch.state, down, settled, now, kind.Hold, kind.Give)
		if action == "start" then
			begin(watch, gap)
		elseif action == "stop" then
			finish(watch)
		elseif action == "fallback" then
			finish(watch)
			if RunService:IsStudio() then
				print(`[CarRighting] {car.model.Name} did not come up in {kind.Give} s (wedged?): stood up where it lies`)
			end
			Vehicles.standUp(car, headingOf(chassis))
		end
	end
	-- The vehicles gone (parked away, wrecked, rebuilt): forgotten, a turn still running stopped.
	for model, watch in watches do
		if not seen[model] then
			if watch.steer ~= nil or watch.state.righting then
				finish(watch)
			end
			watches[model] = nil
		end
	end
end

function CarRighting.start()
	local nextAt = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextAt then
			return
		end
		nextAt = now + Cfg.Check
		look()
	end)
end

return CarRighting
