--!strict
-- 6.10, the E-Scooter's wheelie, the server's side. The riding is the owner's client's (client/Drive.luau through
-- shared/ScooterRide.luau: hold Shift, a gamepad's R1 or the touch WHEELIE button); every client draws it
-- (client/CarVisuals.luau pitches the deck back round its rear axle, client/BikeRider.luau sits the rider back).
-- The driver's client says up or down (the Wheelie remote, rate-limited: Config.Robust.Limits). Here it is checked
-- (the driver of a stand-up scooter, yours or a ZDC RIDE rental, rolling) and put on the scooter's model as the
-- attribute WheelieAt (the server time it went up; nil: on both wheels), and taken off again when the driver says so,
-- gets off, the scooter is gone or wrecked, or the balance ran out (Config.Scooter.Wheelie MaxSeconds, with
-- ServerSlack for the remote's trip).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)

local Wheelie = {}

local TICK = 0.25
local ROLLING = 1.5 -- studs/s the server must see (its copy of the speed lags the driver's; the client checks MinSpeed)

type Up = { player: Player, car: Vehicles.Car, at: number }

local active: { [Model]: Up } = {}
local started = false

local function drop(model: Model)
	active[model] = nil
	if model.Parent then
		model:SetAttribute("WheelieAt", nil)
	end
end

-- The scooter this player drives now (a stand-up one), or nil.
local function scooterOf(player: Player): Vehicles.Car?
	local car, driving = Vehicles.seatedIn(player)
	if not car or not driving or car.wrecked or car.model:GetAttribute("BikeStand") ~= true then
		return nil
	end
	return car
end

local function onWheelie(player: Player, up: any)
	if type(up) ~= "boolean" or not Net.limit(player, "Wheelie", Config.Robust.Limits.Wheelie) then
		return
	end
	local car = scooterOf(player)
	if not up then
		for model, entry in active do
			if entry.player == player then
				drop(model)
			end
		end
		return
	end
	if not car or active[car.model] or Vehicles.speed(car) < ROLLING then
		return
	end
	local now = workspace:GetServerTimeNow()
	active[car.model] = { player = player, car = car, at = now }
	car.model:SetAttribute("WheelieAt", now)
end

-- Every TICK: the wheelies that ended some other way, or ran out of balance.
local function check()
	local now = workspace:GetServerTimeNow()
	local cfg = Config.Scooter.Wheelie
	for model, entry in active do
		local car = entry.car
		if not model.Parent or car.wrecked or not entry.player.Parent or scooterOf(entry.player) ~= car
			or now - entry.at > cfg.MaxSeconds + cfg.ServerSlack then
			drop(model)
		end
	end
end

function Wheelie.start()
	if started then
		return
	end
	started = true
	Net.get("Wheelie").OnServerEvent:Connect(onWheelie)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < TICK or next(active) == nil then
			return
		end
		acc = 0
		check()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		for model, entry in active do
			if entry.player == player then
				drop(model)
			end
		end
	end)
end

return Wheelie
