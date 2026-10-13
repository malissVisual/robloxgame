--!strict
-- 6.24, a bike knocked over gets back up (the owner's screenshot: a bike lying flat on its side, its rider on it).
-- The safety net under server/Vehicles.luau's fixes (6.24 there: the pedal bikes' hull boxes only take hits, the
-- rider's body never collides with its bike): whatever else knocks a bike over (a car, a fall, a horde), it does not
-- stay down. Every Config.BikeUpright.Check seconds the server looks at every bike in the world (a player's own, a ZDC
-- RIDE rental; ridden, the rider's client runs its physics, parked, the server: the numbers below reach both):
-- tipped over (its top more than Tilt degrees off upright: on its side, on its back, on its nose) for Hold seconds,
-- its AlignOrientation "Righting" (server/Vehicles.luau, off until then) turns it back onto its wheels, facing where
-- it pointed, at most TurnRate rad/s, and the steering's AngularVelocity "Steer" lets go meanwhile (its MaxTorque 0:
-- it holds every roll still, the bike's turn back up too). Within Settled degrees of upright again both are as they
-- were (KeepUpright holds it from there). Still down after Give seconds (wedged against something) it is stood up
-- where it lies at once (Vehicles.standUp). The decisions are shared/BikeUpright.luau's (pure, tested). In Studio
-- every bike that went over says so in the Output (how far it rolled, ridden or parked), to find what knocked it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BikeUpright = require(Shared.BikeUpright)
local Vehicles = require(script.Parent.Vehicles)

local BikeRighting = {}

local Cfg = Config.BikeUpright

type Watch = {
	state: BikeUpright.State,
	car: Vehicles.Car,
	steer: number?, -- the Steer's MaxTorque while it is let go (nil: not let go)
}

local watches: { [Model]: Watch } = {}

-- Which way the bike points on the ground (flat), however it lies.
local function headingOf(chassis: BasePart): Vector3
	local frame = chassis.CFrame
	local look, up = frame.LookVector, frame.UpVector
	local x, z = BikeUpright.heading(look.X, look.Y, look.Z, up.X, up.Z)
	return Vector3.new(x, 0, z)
end

local function constraint(chassis: BasePart, name: string): Instance?
	return chassis:FindFirstChild(name)
end

-- Turn it back up: Righting on toward upright (its heading kept), the Steer let go.
local function begin(watch: Watch)
	local chassis = watch.car.chassis
	local righting = constraint(chassis, "Righting")
	if not righting or not righting:IsA("AlignOrientation") then
		return
	end
	local heading = headingOf(chassis)
	righting.CFrame = CFrame.lookAt(Vector3.zero, heading)
	righting.MaxTorque = chassis.AssemblyMass * Cfg.Torque
	righting.Enabled = true
	local steer = constraint(chassis, "Steer")
	if steer and steer:IsA("AngularVelocity") and watch.steer == nil then
		watch.steer = steer.MaxTorque
		steer.MaxTorque = 0
	end
	if RunService:IsStudio() then
		local frame = chassis.CFrame
		print(string.format("[BikeRighting] %s lay over (rolled %.0f°, its top %.0f° off upright, %s) for %.1f s: turning it back up",
			watch.car.model.Name, BikeUpright.roll(frame.RightVector.Y, frame.UpVector.Y), BikeUpright.tilt(frame.UpVector.Y),
			if watch.car.seat.Occupant then "ridden" else "parked", Cfg.Hold))
	end
end

-- Back as it was: Righting off, the Steer's hold back.
local function finish(watch: Watch)
	local chassis = watch.car.chassis
	local righting = constraint(chassis, "Righting")
	if righting and righting:IsA("AlignOrientation") then
		righting.Enabled = false
	end
	local steer = constraint(chassis, "Steer")
	local torque = watch.steer
	if steer and steer:IsA("AngularVelocity") and torque then
		steer.MaxTorque = torque
	end
	watch.steer = nil
end

local function look()
	local now = os.clock()
	local seen: { [Model]: boolean } = {}
	for _, car in Vehicles.all() do
		local chassis = car.chassis
		if not Vehicles.isBike(car) or not chassis.Parent then
			continue
		end
		local found = watches[car.model]
		local watch: Watch = if found and found.car == car then found else { state = BikeUpright.new(), car = car, steer = nil }
		watches[car.model] = watch
		seen[car.model] = true
		if car.repairing or chassis.Anchored then
			-- (on a lift: nothing to turn; anything running stops)
			if watch.steer ~= nil or watch.state.righting then
				finish(watch)
			end
			watch.state = BikeUpright.new()
			continue
		end
		local upY = chassis.CFrame.UpVector.Y
		local action = BikeUpright.step(watch.state, BikeUpright.tipped(upY, Cfg.Tilt), BikeUpright.settled(upY, Cfg.Settled), now, Cfg.Hold, Cfg.Give)
		if action == "start" then
			begin(watch)
		elseif action == "stop" then
			finish(watch)
		elseif action == "fallback" then
			finish(watch)
			if RunService:IsStudio() then
				print(`[BikeRighting] {car.model.Name} did not come up in {Cfg.Give} s (wedged?): stood up where it lies`)
			end
			Vehicles.standUp(car, headingOf(chassis))
		end
	end
	-- The bikes gone (parked away, wrecked, rebuilt): forgotten, a turn still running stopped.
	for model, watch in watches do
		if not seen[model] then
			if watch.steer ~= nil or watch.state.righting then
				finish(watch)
			end
			watches[model] = nil
		end
	end
end

function BikeRighting.start()
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

return BikeRighting
