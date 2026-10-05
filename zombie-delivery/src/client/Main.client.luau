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
local Weather = require(Client.Weather)
local CameraRig = require(Client.CameraRig)
local ArmPose = require(Client.ArmPose)
local AdminPanel = require(Client.AdminPanel)
local AnimalAnimator = require(Client.AnimalAnimator)
local Leaderboard = require(Client.Leaderboard)
local CrewPanel = require(Client.CrewPanel)
local EstateUi = require(Client.EstateUi)
local BusinessUi = require(Client.BusinessUi)
local TrafficAnimator = require(Client.TrafficAnimator)
local Sounds = require(Client.Sounds)
local MissionsUi = require(Client.MissionsUi)
local WeaponWheel = require(Client.WeaponWheel)
local DispatchUi = require(Client.DispatchUi)
local Secrets = require(Client.Secrets)
local GarageUi = require(Client.GarageUi)

-- Every part starts on its own: one that fails (see the Output) does not take the others down.
local function safely(name: string, start: () -> ())
	local ok, err = pcall(function()
		start()
	end)
	if not ok then
		warn(`[Client] {name} failed to start: {err}`)
	end
end
safely("Drive", Drive.start)
safely("Shooting", Shooting.start)
safely("ZombieAnimator", ZombieAnimator.start)
safely("CarVisuals", CarVisuals.start)
safely("Weather", Weather.start)
safely("Hud", Hud.start)
safely("CameraRig", CameraRig.start)
safely("ArmPose", ArmPose.start)
safely("AdminPanel", AdminPanel.start)
safely("AnimalAnimator", AnimalAnimator.start)
safely("Leaderboard", Leaderboard.start)
safely("CrewPanel", CrewPanel.start)
safely("EstateUi", EstateUi.start)
safely("BusinessUi", BusinessUi.start)
safely("TrafficAnimator", TrafficAnimator.start)
safely("Sounds", Sounds.start)
safely("MissionsUi", MissionsUi.start)
safely("WeaponWheel", WeaponWheel.start)
safely("DispatchUi", DispatchUi.start)
safely("Secrets", Secrets.start)
safely("GarageUi", GarageUi.start) -- 3.4: the garage window, your garages' prompts, the repair timer
Shooting.notify = Hud.toast
Drive.notify = Hud.toast
Sounds.notify = Hud.toast
WeaponWheel.notify = Hud.toast
Hud.onSound = Sounds.cycle
-- One window at a time: every HUD window, the leaderboard and the crew window close the others.
Hud.onCloseWindows = function()
	CrewPanel.close()
	EstateUi.close()
	BusinessUi.close()
	MissionsUi.close()
	GarageUi.close()
	DispatchUi.close()
end
CrewPanel.onOpen = Hud.closeWindows
EstateUi.onOpen = Hud.closeWindows
MissionsUi.onOpen = Hud.closeWindows
DispatchUi.onOpen = Hud.closeWindows
Hud.onJobs = DispatchUi.open -- (the depot counter and NEXT JOB must not close an open board; ESC or ✕ closes it)
GarageUi.onOpen = Hud.closeWindows
Hud.onEstate = EstateUi.toggleList
Hud.onMissions = MissionsUi.toggle
MissionsUi.onFindCrew = CrewPanel.open
CameraRig.mouseNeeded = function(): boolean
	return Hud.anyWindowOpen() or AdminPanel.isOpen() or Leaderboard.isOpen() or CrewPanel.isOpen() or EstateUi.isOpen() or BusinessUi.isOpen() or MissionsUi.isOpen() or WeaponWheel.isOpen() or DispatchUi.isOpen() or GarageUi.isOpen()
end

Net.get("State").OnClientEvent:Connect(function(state)
	Shooting.setState(state)
	Hud.setState(state)
	DispatchUi.setState(state)
	Menu.setState(state)
end)
Net.get("Job").OnClientEvent:Connect(Hud.setJob)
Net.get("Offers").OnClientEvent:Connect(DispatchUi.setOffers)
Net.get("DeliveryResult").OnClientEvent:Connect(Hud.showResult)
Net.get("Notice").OnClientEvent:Connect(Hud.toast)
Net.get("OpenShop").OnClientEvent:Connect(Hud.openShop)
Net.get("Boost").OnClientEvent:Connect(Drive.boost)

local function play()
	pcall(function()
		Hud.setVisible(true)
		CameraRig.setEnabled(true)
		Sounds.setInGame(true)
	end)
	Net.get("Play"):FireServer()
end
local ok, err = pcall(function()
	Menu.show(play)
end)
if not ok then
	-- No start screen: straight into the game.
	warn(`[Client] the start screen failed: {err}`)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	play()
end

Net.get("RequestState"):FireServer()
