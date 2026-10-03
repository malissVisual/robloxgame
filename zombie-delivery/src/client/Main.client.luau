--!strict
-- Zombie Delivery: the client. The start screen first; PLAY starts the interface and asks the server for the car.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Client = script.Parent
local Drive = require(Client.Drive)
local Shooting = require(Client.Shooting)
local ZombieAnimator = require(Client.ZombieAnimator)
local CarVisuals = require(Client.CarVisuals)
local Hud = require(Client.Hud)
local Menu = require(Client.Menu)

Drive.start()
Shooting.start()
ZombieAnimator.start()
CarVisuals.start()
Hud.start()

Net.get("State").OnClientEvent:Connect(function(state)
	Shooting.setState(state)
	Hud.setState(state)
	Menu.setState(state)
end)
Net.get("Job").OnClientEvent:Connect(Hud.setJob)
Net.get("Offers").OnClientEvent:Connect(Hud.setOffers)
Net.get("DeliveryResult").OnClientEvent:Connect(Hud.showResult)
Net.get("Notice").OnClientEvent:Connect(Hud.toast)
Net.get("OpenShop").OnClientEvent:Connect(Hud.openShop)
Net.get("Boost").OnClientEvent:Connect(Drive.boost)

Menu.show(function()
	Hud.setVisible(true)
	Net.get("Play"):FireServer()
end)

Net.get("RequestState"):FireServer()
