--!strict
-- Zombie Delivery: the client. Starts the car controller, the gun, the zombie animations and the interface,
-- and passes the server's messages to them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Client = script.Parent
local Drive = require(Client.Drive)
local Shooting = require(Client.Shooting)
local ZombieAnimator = require(Client.ZombieAnimator)
local Hud = require(Client.Hud)

Drive.start()
Shooting.start()
ZombieAnimator.start()
Hud.start()

Net.get("State").OnClientEvent:Connect(function(state)
	Shooting.setState(state)
	Hud.setState(state)
end)
Net.get("Job").OnClientEvent:Connect(Hud.setJob)
Net.get("Offers").OnClientEvent:Connect(Hud.setOffers)
Net.get("DeliveryResult").OnClientEvent:Connect(Hud.showResult)
Net.get("Notice").OnClientEvent:Connect(Hud.toast)

Net.get("RequestState"):FireServer()
