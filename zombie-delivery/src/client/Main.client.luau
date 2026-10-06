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
local AdminFly = require(Client.AdminFly)
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
local Stamina = require(Client.Stamina)
local Discovery = require(Client.Discovery)
local TutorialUi = require(Client.TutorialUi)
local Holster = require(Client.Holster)
local CarBoarding = require(Client.CarBoarding)
local LocationTag = require(Client.LocationTag)
local CareerUi = require(Client.CareerUi)
local RoadEventUi = require(Client.RoadEventUi)
local Phone = require(Client.Phone)
local CargoPrompts = require(Client.CargoPrompts)

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
safely("AdminFly", AdminFly.start) -- 4.5: the admin's fly, noclip and super jump (gated by player attributes)
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
safely("Stamina", Stamina.start) -- 3.7: the sprint's breath
safely("Discovery", Discovery.start) -- 3.7: the map you discover
safely("TutorialUi", TutorialUi.start) -- 3.7: the first-day tutorial
safely("Holster", Holster.start) -- 3.9: B holsters / draws the gun, V punches or strikes
safely("CarBoarding", CarBoarding.start) -- 3.10: getting in and out of a car (E at a door, E or Space in a seat)
safely("LocationTag", LocationTag.start) -- 4.3: the quiet caption that names the building you come up to
safely("CareerUi", CareerUi.start) -- 4.6: the CAREER window (C) and the level-up card
safely("RoadEventUi", RoadEventUi.start) -- 4.8: a road event's side pick-up offer (Y takes it)
safely("Phone", Phone.start) -- 5.0: the courier's phone (O, the PHONE action), Marge gives it in the tutorial
safely("CargoPrompts", CargoPrompts.start) -- 5.3 review: only your own job's prompts (another courier's pile is hidden)
safely("BusRide", require(Client.BusRide).start) -- 5.5: the city buses glide, the stop card, the ride banner (E: STOP), the job's bus hint
Shooting.notify = Hud.toast
Drive.notify = Hud.toast
Sounds.notify = Hud.toast
WeaponWheel.notify = Hud.toast
Hud.onWeaponWheel = WeaponWheel.openTouch -- 4.2, touch: a tap on the weapon line opens the wheel
Hud.onSound = Sounds.cycle
-- One window at a time: every HUD window, the leaderboard and the crew window close the others.
Hud.onCloseWindows = function()
	CrewPanel.close()
	EstateUi.close()
	BusinessUi.close()
	MissionsUi.close()
	GarageUi.close()
	DispatchUi.close()
	CareerUi.close()
	Phone.close()
end
CrewPanel.onOpen = Hud.closeWindows
EstateUi.onOpen = Hud.closeWindows
MissionsUi.onOpen = Hud.closeWindows
DispatchUi.onOpen = Hud.closeWindows
Hud.onJobs = DispatchUi.open -- (the depot counter and NEXT JOB must not close an open board; ✕ or J closes it)
Hud.onJobsKey = function() -- 4.0.2: J opens the board, J again closes it
	if DispatchUi.isOpen() then
		DispatchUi.close()
	else
		DispatchUi.open()
	end
end
GarageUi.onOpen = Hud.closeWindows
CareerUi.onOpen = Hud.closeWindows
Hud.onCareer = CareerUi.toggle
-- 5.0: the phone is one more window (it closes the others); its apps open the board, the career, the map.
Phone.onOpen = Hud.closeWindows
Phone.onBoard = DispatchUi.open
Phone.onCareer = CareerUi.open
-- 5.5: the HUD MENU's actions are phone apps (their windows open; the phone closes first), and MENU opens the phone.
Phone.onMissions = MissionsUi.toggle
Phone.onCrew = CrewPanel.toggle
Phone.onTop = Leaderboard.toggle
Phone.onEstate = EstateUi.toggleList
Phone.onSound = Sounds.cycle
Hud.onMenu = function(): boolean
	if not Phone.has() then
		return false -- (before Marge: the old list)
	end
	Phone.toggle()
	return true
end
Phone.boardOpen = DispatchUi.isOpen
Phone.notify = Hud.toast
Phone.blocked = function(): boolean -- (the NEW PHONE pop-up waits for Marge's dialog and a result or card)
	return TutorialUi.isOpen() or Hud.resultOpen() or MissionsUi.isOpen() or CareerUi.cardOpen()
end
-- 4.6: the level-up card waits for the DELIVERY result and a mission's cleared card (MissionsUi.isOpen counts it).
CareerUi.blocked = function(): boolean
	return Hud.resultOpen() or MissionsUi.isOpen()
end
Hud.onEstate = EstateUi.toggleList
Hud.onMissions = MissionsUi.toggle
MissionsUi.onFindCrew = CrewPanel.open
CameraRig.mouseNeeded = function(): boolean
	return CameraRig.windowOpen() or Phone.isOpen()
end
-- Every window but the phone (5.4.1: with only the phone open, the right mouse still turns the camera).
CameraRig.windowOpen = function(): boolean
	return Hud.anyWindowOpen() or AdminPanel.isOpen() or Leaderboard.isOpen() or CrewPanel.isOpen() or EstateUi.isOpen() or BusinessUi.isOpen() or MissionsUi.isOpen() or WeaponWheel.isOpen() or DispatchUi.isOpen() or GarageUi.isOpen()
		or CareerUi.isOpen() or CareerUi.cardOpen()
end
CameraRig.freeLook = function(): boolean
	return Phone.isOpen() and not CameraRig.windowOpen()
end
LocationTag.windowOpen = CameraRig.mouseNeeded -- 4.3: no location caption while a window is open

Net.get("State").OnClientEvent:Connect(function(state)
	Shooting.setState(state)
	Hud.setState(state)
	DispatchUi.setState(state)
	Menu.setState(state)
	CareerUi.setState(state)
	Phone.setState(state)
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
		Holster.setEnabled(true)
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
