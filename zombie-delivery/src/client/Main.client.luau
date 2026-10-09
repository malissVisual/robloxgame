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
safely("BusMapBoard", require(Client.BusMapBoard).start) -- 6.3: the bus map on the nearest stop's board, YOU ARE HERE
safely("RentalUi", require(Client.RentalUi).start) -- 5.6: ZDC RIDE's Rent / Return prompts, each player the one that fits
safely("ZipRide", require(Client.ZipRide).start) -- 5.6: riding the zip lines, the riders' pose and trolley; 6.10: a jump on a start platform grabs it
require(Client.ZipRide).notify = Hud.toast
safely("SprintPose", require(Client.SprintPose).start) -- 6.0: the sprint's stride and pumping arms
safely("BodyLife", require(Client.BodyLife).start) -- 6.7: the breath, the weight shift, the head, blinks, the landing, the flinch, the walk
safely("BagSway", require(Client.BagSway).start) -- 6.1: the bag in the hand swings on a spring (its only writer)
safely("KeyHints", function() -- 6.1: the quiet key hints under the top buttons (F1 folds them)
	task.spawn(require(Client.KeyHints).start)
end)
safely("Throw", require(Client.Throw).start) -- 6.0: hold X at a home's door to throw the delivery (the dotted arc, TRICKSHOT)
safely("Unstuck", require(Client.Unstuck).start) -- 6.0.1: lifts your courier out of the ground if it ever sinks in (and says why)
safely("CurbRide", require(Client.CurbRide).start) -- 6.10: up the kerb's slope at speed without a hop off its top
safely("ShopPropMotion", require(Client.ShopPropMotion).start) -- 6.11: the bank's coin spins, Luigi's pizza slice bobs
safely("PerfOverlay", require(Client.PerfOverlay).start) -- 6.13.1: the admin's performance overlay (the P panel's WORLD tab)
safely("GrindChips", require(Client.GrindChips).start) -- 6.14: ON A ROLL and SHIFT 3/5 at the top, SHIFT DONE
AdminPanel.onPerformance = require(Client.PerfOverlay).toggle
AdminPanel.performanceOn = require(Client.PerfOverlay).isOn
require(Client.Throw).notify = Hud.toast
Shooting.notify = Hud.toast
Holster.notify = Hud.toast -- 6.1: what you hold (keys 1 / 2 / 3)
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
	if not (Hud.escaping and Phone.appOpen()) then
		Phone.close() -- (6.0.1 review: ESC with an app open goes back to the phone's home, the phone handles it)
	end
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
DispatchUi.onDetails = function() -- 6.12.8: YOUR RUN's DETAILS on J's board: the phone's ORDERS, as before
	DispatchUi.close()
	Phone.open("orders")
end
Phone.onCareer = CareerUi.open
-- 5.5: the HUD MENU's actions are phone apps (their windows open; the phone closes first), and MENU opens the phone.
Phone.onMissions = function() -- 6.8: MORE → MISSIONS always opens it (on the chapter you are at)
	MissionsUi.open()
end
Phone.missionInfo = MissionsUi.summary -- 6.12.5: the MISSIONS tile on the phone's home
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
Hud.onCrewBadge = Phone.setCrewInvites -- 6.5 review: crew invitations on the phone's MORE tile
Phone.onUnread = Hud.setPhoneUnread -- 6.5: the unread dot on PHONE [Q] top right (the phone's own action: touch only)
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
-- 6.0.1: not while an app is open in the phone's popup (the mouse is needed there).
CameraRig.freeLook = function(): boolean
	return Phone.isOpen() and not Phone.appOpen() and not CameraRig.windowOpen()
end
LocationTag.windowOpen = CameraRig.mouseNeeded -- 4.3: no location caption while a window is open
-- 6.0.1: the bottom bar (client/Hotbar.luau: the items 1-5 and what you carry) hides while a window, the phone or a
-- dialog (Marge's, the delivery result) covers the game.
require(Client.Hotbar).covered = function(): boolean
	return CameraRig.mouseNeeded() or TutorialUi.isOpen() or Hud.resultOpen()
end
require(Client.KeyHints).covered = require(Client.Hotbar).covered -- 6.1: the key hints hide the same way

Net.get("State").OnClientEvent:Connect(function(state)
	Shooting.setState(state)
	require(Client.KeyHints).setState(state) -- 6.1
	-- 6.1 (6.4: any bag, the server's state.bag; one that stays is slung on the back, never set down)
	local bagDef = if type(state) == "table" and type(state.bag) == "string" then require(Shared.Transport).findKit(state.bag) else nil
	Holster.setBag(bagDef ~= nil, bagDef ~= nil and bagDef.stays == true)
	Holster.setBat(type(state) == "table" and require(Shared.Melee).hasBat(state.kit)) -- 6.7: V swings the bat
	Hud.setState(state)
	DispatchUi.setState(state)
	Menu.setState(state)
	CareerUi.setState(state)
	Phone.setState(state)
end)
Net.get("Job").OnClientEvent:Connect(Hud.setJob)
Net.get("Offers").OnClientEvent:Connect(DispatchUi.setOffers)
Net.get("DeliveryResult").OnClientEvent:Connect(Hud.showResult)
require(Client.RegularsApp).start(Hud.toast) -- 6.14: a regulars' tier reached (the State): a toast and a sting
require(Client.SpecialOrderUi).start(Hud.toast) -- 6.14: a golden or a regular's order on the board: a toast and a sting
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
