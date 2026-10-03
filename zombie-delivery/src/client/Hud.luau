--!strict
-- The whole interface: money, the car panel (health, speed), the active job (timer, distance, cargo condition),
-- the JOBS / GARAGE / CAR buttons, the job board, the garage (cars, guns, upgrades), the delivery result,
-- toasts, the FIRE button for touch screens and the way to the customer (a beacon and an arrow over the car).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Drive = require(script.Parent.Drive)
local Shooting = require(script.Parent.Shooting)

local C = Ui.Colors
local Hud = {}

local player = Players.LocalPlayer
local state: any = nil
local job: any = nil
local garageTab = "cars"

local gui = Ui.make("ScreenGui", {
	Name = "ZombieDeliveryHud",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

-- Every top-level panel gets a UIScale so the interface fits phones too.
local scales: { any } = {}
local function scaled(frame: any): any
	table.insert(scales, Ui.make("UIScale", {}, frame))
	return frame
end
local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local value = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.55, 1.1)
	for _, s in scales do
		s.Scale = value
	end
end

local function inDepot(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude < Config.City.SafeRadius
end

-- ── Money ──────────────────────────────────────────────────────────────────

local moneyPanel = scaled(Ui.panel(gui, UDim2.fromOffset(250, 66), UDim2.fromOffset(16, 16)))
Ui.padding(moneyPanel, 8)
local moneyLabel = Ui.label(moneyPanel, "$0", UDim2.new(1, 0, 0, 32), { TextColor3 = C.money, TextSize = 30, Font = Enum.Font.GothamBlack })
local statsLabel = Ui.label(moneyPanel, "", UDim2.new(1, 0, 0, 16), { Position = UDim2.fromOffset(0, 34), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })

-- ── Toasts ─────────────────────────────────────────────────────────────────

local toasts = Ui.make("Frame", {
	Size = UDim2.fromOffset(520, 200),
	Position = UDim2.new(0.5, 0, 0, 190),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
}, gui)
scaled(toasts)
Ui.list(toasts, true, 6, Enum.HorizontalAlignment.Center)

function Hud.toast(text: string)
	local label = Ui.label(toasts, text, UDim2.fromOffset(500, 34), {
		BackgroundTransparency = 0.25,
		BackgroundColor3 = C.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 18,
	})
	Ui.corner(label, 8)
	task.delay(3, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.45)
		label:Destroy()
	end)
end

-- ── Windows ────────────────────────────────────────────────────────────────

local windows: { any } = {}

local function closeWindows()
	for _, w in windows do
		w.Visible = false
	end
end

local function window(title: string, size: Vector2): (any, any)
	local frame = scaled(Ui.panel(gui, UDim2.fromOffset(size.X, size.Y), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)))
	frame.Visible = false
	frame.BackgroundTransparency = 0.05
	frame.ZIndex = 5
	Ui.stroke(frame, C.yellow, 2)
	Ui.label(frame, title, UDim2.new(1, -70, 0, 44), { Position = UDim2.fromOffset(18, 6), TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = C.yellow })
	local close = Ui.button(frame, "X", UDim2.fromOffset(40, 40), C.red, function()
		frame.Visible = false
	end)
	close.Position = UDim2.new(1, -50, 0, 8)
	local body = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -64),
		Position = UDim2.fromOffset(14, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, frame)
	Ui.list(body, true, 8)
	table.insert(windows, frame)
	return frame, body
end

local function card(parent: any, height: number, order: number): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, height),
		BackgroundColor3 = C.panelLight,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Ui.corner(frame, 10)
	return frame
end

-- ── Job board ──────────────────────────────────────────────────────────────

local jobsWindow, jobsBody = window("JOB BOARD", Vector2.new(560, 430))
local offersRemote = Net.get("RequestOffers")

local function showJobsMessage(text: string)
	Ui.clear(jobsBody)
	Ui.label(jobsBody, text, UDim2.new(1, -10, 0, 60), { TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center })
end

local function openJobs()
	closeWindows()
	jobsWindow.Visible = true
	if job then
		Ui.clear(jobsBody)
		Ui.label(jobsBody, `You are delivering {job.cargo} to {job.customer}. Finish it first, or give it up.`, UDim2.new(1, -10, 0, 60), { TextColor3 = C.text })
		Ui.button(jobsBody, "GIVE UP THIS DELIVERY", UDim2.fromOffset(280, 46), C.red, function()
			Net.get("CancelJob"):FireServer()
			jobsWindow.Visible = false
		end)
		return
	end
	showJobsMessage("Calling the dispatcher...")
	offersRemote:FireServer()
end

function Hud.setOffers(list: { any })
	if job then
		return
	end
	Ui.clear(jobsBody)
	for order, offer in list do
		local c = card(jobsBody, 96, order)
		local color = if offer.stars == 1 then C.green elseif offer.stars == 2 then C.yellow else C.red
		Ui.label(c, Ui.stars(offer.stars), UDim2.fromOffset(110, 30), { Position = UDim2.fromOffset(12, 6), TextColor3 = color, TextSize = 26 })
		Ui.label(c, `{offer.cargo} → {offer.customer}`, UDim2.new(1, -260, 0, 26), { Position = UDim2.fromOffset(120, 8), TextSize = 19 })
		Ui.label(c, `{offer.address} · {offer.distance} m · {Ui.clock(offer.time)}`, UDim2.new(1, -260, 0, 20), {
			Position = UDim2.fromOffset(120, 38),
			TextColor3 = C.dim,
			TextSize = 15,
			Font = Enum.Font.GothamMedium,
		})
		local danger = if offer.stars == 1 then "A few walkers." elseif offer.stars == 2 then "Runners, a horde at the door." else "Brutes. Big horde at the door."
		Ui.label(c, danger, UDim2.new(1, -260, 0, 20), { Position = UDim2.fromOffset(120, 62), TextColor3 = color, TextSize = 14, Font = Enum.Font.GothamMedium })
		Ui.label(c, Ui.money(offer.pay), UDim2.fromOffset(110, 30), { Position = UDim2.new(1, -240, 0, 30), TextColor3 = C.money, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right })
		local accept = Ui.button(c, "ACCEPT", UDim2.fromOffset(110, 46), C.green, function()
			Net.get("AcceptJob"):FireServer(offer.index)
			jobsWindow.Visible = false
		end)
		accept.Position = UDim2.new(1, -122, 0.5, -23)
	end
	local refresh = Ui.button(jobsBody, "NEW OFFERS", UDim2.fromOffset(180, 40), C.grey, function()
		showJobsMessage("Calling the dispatcher...")
		offersRemote:FireServer()
	end)
	refresh.LayoutOrder = 99
end

-- ── Garage ─────────────────────────────────────────────────────────────────

local garageWindow, garageBody = window("GARAGE", Vector2.new(680, 480))
local renderGarage: () -> ()

local function shopButton(parent: any, text: string, color: Color3, enabled: boolean, onClick: () -> ()): any
	local button = Ui.button(parent, text, UDim2.fromOffset(150, 46), if enabled then color else C.grey, function()
		if enabled then
			onClick()
		end
	end)
	button.AutoButtonColor = enabled
	button.Position = UDim2.new(1, -162, 0.5, -23)
	button.TextSize = 16
	return button
end

local function tabButton(parent: any, text: string, id: string)
	local selected = garageTab == id
	local button = Ui.button(parent, text, UDim2.fromOffset(140, 38), if selected then C.yellow else C.grey, function()
		garageTab = id
		renderGarage()
	end)
	button.TextColor3 = if selected then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
end

renderGarage = function()
	Ui.clear(garageBody)
	if not state then
		return
	end
	local tabs = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundTransparency = 1, LayoutOrder = 0 }, garageBody)
	Ui.list(tabs, false, 8)
	tabButton(tabs, "CARS", "cars")
	tabButton(tabs, "GUNS", "guns")
	tabButton(tabs, "UPGRADES", "upgrades")
	local depot = inDepot()
	Ui.label(garageBody, if depot then "You are in the depot: buy, equip and upgrade." else "Drive back to the depot (the green circle) to shop.", UDim2.new(1, -10, 0, 22), {
		LayoutOrder = 1,
		TextColor3 = if depot then C.green else C.red,
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
	})
	local money = state.money

	if garageTab == "cars" then
		for order, def in Config.Cars do
			local c = card(garageBody, 84, order + 1)
			Ui.label(c, def.name, UDim2.new(1, -190, 0, 26), { Position = UDim2.fromOffset(14, 6), TextSize = 21, Font = Enum.Font.GothamBlack })
			Ui.label(c, `Speed {def.maxSpeed} · Health {def.health} · Ram x{def.ramPower}`, UDim2.new(1, -190, 0, 20), {
				Position = UDim2.fromOffset(14, 34),
				TextColor3 = C.yellow,
				TextSize = 15,
			})
			Ui.label(c, def.description, UDim2.new(1, -190, 0, 20), { Position = UDim2.fromOffset(14, 56), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
			if state.car == def.id then
				shopButton(c, "DRIVING", C.grey, false, function() end)
			elseif state.cars[def.id] then
				shopButton(c, "EQUIP", C.blue, depot, function()
					Net.get("Equip"):FireServer("car", def.id)
				end)
			else
				shopButton(c, `BUY {Ui.money(def.price)}`, C.green, depot and money >= def.price, function()
					Net.get("Buy"):FireServer("car", def.id)
				end)
			end
		end
	elseif garageTab == "guns" then
		for order, def in Config.Weapons do
			local c = card(garageBody, 84, order + 1)
			Ui.label(c, def.name, UDim2.new(1, -190, 0, 26), { Position = UDim2.fromOffset(14, 6), TextSize = 21, Font = Enum.Font.GothamBlack })
			local pellets = if def.pellets > 1 then ` x{def.pellets}` else ""
			Ui.label(c, `Damage {def.damage}{pellets} · {def.fireRate} shots/s · Range {def.range}`, UDim2.new(1, -190, 0, 20), {
				Position = UDim2.fromOffset(14, 34),
				TextColor3 = C.yellow,
				TextSize = 15,
			})
			Ui.label(c, def.description, UDim2.new(1, -190, 0, 20), { Position = UDim2.fromOffset(14, 56), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
			if state.weapon == def.id then
				shopButton(c, "MOUNTED", C.grey, false, function() end)
			elseif state.weapons[def.id] then
				shopButton(c, "MOUNT", C.blue, true, function()
					Net.get("Equip"):FireServer("weapon", def.id)
				end)
			else
				shopButton(c, `BUY {Ui.money(def.price)}`, C.green, depot and money >= def.price, function()
					Net.get("Buy"):FireServer("weapon", def.id)
				end)
			end
		end
	else
		for order, def in Config.Upgrades do
			local c = card(garageBody, 84, order + 1)
			local level = Economy.level(state.upgrades, def.id)
			Ui.label(c, def.name, UDim2.new(1, -190, 0, 26), { Position = UDim2.fromOffset(14, 6), TextSize = 21, Font = Enum.Font.GothamBlack })
			Ui.label(c, string.rep("■", level) .. string.rep("□", def.maxLevel - level) .. `  Lv {level}/{def.maxLevel}`, UDim2.new(1, -190, 0, 20), {
				Position = UDim2.fromOffset(14, 34),
				TextColor3 = C.yellow,
				TextSize = 16,
			})
			Ui.label(c, def.description, UDim2.new(1, -190, 0, 20), { Position = UDim2.fromOffset(14, 56), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
			local cost = Economy.upgradeCost(def.id, level)
			if cost then
				shopButton(c, `UPGRADE {Ui.money(cost)}`, C.green, depot and money >= cost, function()
					Net.get("Upgrade"):FireServer(def.id)
				end)
			else
				shopButton(c, "MAX", C.grey, false, function() end)
			end
		end
	end
end

local function openGarage()
	closeWindows()
	garageWindow.Visible = true
	renderGarage()
end

-- ── Delivery result ────────────────────────────────────────────────────────

local resultWindow, resultBody = window("DELIVERY", Vector2.new(420, 390))

function Hud.showResult(result: any)
	closeWindows()
	Ui.clear(resultBody)
	resultWindow.Visible = true
	local function line(text: string, value: string?, color: Color3?, order: number)
		local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 28), BackgroundTransparency = 1, LayoutOrder = order }, resultBody)
		Ui.label(row, text, UDim2.new(1, -110, 1, 0), { TextColor3 = color or C.text, TextSize = 18 })
		if value then
			Ui.label(row, value, UDim2.new(0, 110, 1, 0), { Position = UDim2.new(1, -110, 0, 0), TextColor3 = color or C.money, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right })
		end
	end
	if result.success then
		local payout = result.payout
		line("DELIVERED!", nil, C.green, 1)
		line(`{result.cargo} for {result.customer}`, nil, C.dim, 2)
		line("Pay", Ui.money(payout.base), nil, 3)
		line(`Cargo condition {math.floor(result.condition * 100 + 0.5)}%`, Ui.money(payout.conditionPay), nil, 4)
		line("Speed bonus", "+" .. Ui.money(payout.fastBonus), nil, 5)
		line(`Zombies killed ({result.kills})`, "+" .. Ui.money(payout.killBonus), nil, 6)
		line("TOTAL", Ui.money(payout.total), C.yellow, 7)
	else
		line("DELIVERY FAILED", nil, C.red, 1)
		Ui.label(resultBody, result.reason or "", UDim2.new(1, -10, 0, 60), { LayoutOrder = 2, TextColor3 = C.text })
	end
	local ok = Ui.button(resultBody, "OK", UDim2.fromOffset(160, 44), C.blue, function()
		resultWindow.Visible = false
	end)
	ok.LayoutOrder = 10
	local next = Ui.button(resultBody, "NEXT JOB", UDim2.fromOffset(160, 44), C.green, function()
		resultWindow.Visible = false
		openJobs()
	end)
	next.LayoutOrder = 11
end

-- ── Buttons ────────────────────────────────────────────────────────────────

local side = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(150, 190),
	Position = UDim2.new(1, -16, 0.42, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	BackgroundTransparency = 1,
}, gui))
Ui.list(side, true, 10)
Ui.button(side, "JOBS", UDim2.fromOffset(150, 54), C.yellow, function()
	if jobsWindow.Visible then
		jobsWindow.Visible = false
	else
		openJobs()
	end
end).TextColor3 = Color3.new(0, 0, 0)
Ui.button(side, "GARAGE", UDim2.fromOffset(150, 54), C.blue, function()
	if garageWindow.Visible then
		garageWindow.Visible = false
	else
		openGarage()
	end
end)
Ui.button(side, "CAR", UDim2.fromOffset(150, 54), C.grey, function()
	Net.get("SpawnCar"):FireServer()
end)

-- FIRE for touch screens (auto-aim).
local fire = scaled(Ui.make("TextButton", {
	Size = UDim2.fromOffset(110, 110),
	Position = UDim2.new(1, -40, 1, -190),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = C.red,
	Text = "FIRE",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBlack,
	TextSize = 26,
	Visible = false,
	AutoButtonColor = true,
}, gui))
Ui.corner(fire, 55)
Ui.stroke(fire, Color3.new(0, 0, 0), 3)
fire.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		Shooting.setAutoHeld(true)
	end
end)
fire.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		Shooting.setAutoHeld(false)
	end
end)

-- ── Car panel ──────────────────────────────────────────────────────────────

local carPanel = scaled(Ui.panel(gui, UDim2.fromOffset(380, 78), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1)))
Ui.padding(carPanel, 10)
local carName = Ui.label(carPanel, "", UDim2.new(0.6, 0, 0, 24), { TextSize = 20, Font = Enum.Font.GothamBlack })
local speedLabel = Ui.label(carPanel, "", UDim2.new(0.4, 0, 0, 24), {
	Position = UDim2.fromScale(0.6, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.yellow,
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
})
local healthBack, healthFill = Ui.bar(carPanel, UDim2.new(1, 0, 0, 18), C.green)
healthBack.Position = UDim2.fromOffset(0, 32)
local healthText = Ui.label(healthBack, "", UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, ZIndex = 2 })
local hint = Ui.label(gui, "", UDim2.fromOffset(600, 22), {
	Position = UDim2.new(0.5, 0, 1, -104),
	AnchorPoint = Vector2.new(0.5, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.dim,
	TextSize = 15,
	TextStrokeTransparency = 0.5,
	Font = Enum.Font.GothamMedium,
})

-- ── Job panel ──────────────────────────────────────────────────────────────

local jobPanel = scaled(Ui.panel(gui, UDim2.fromOffset(470, 112), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0)))
jobPanel.Visible = false
Ui.padding(jobPanel, 10)
Ui.stroke(jobPanel, C.yellow, 2)
local jobTitle = Ui.label(jobPanel, "", UDim2.new(1, -90, 0, 24), { TextSize = 19, Font = Enum.Font.GothamBlack })
local jobTimer = Ui.label(jobPanel, "", UDim2.new(0, 90, 0, 24), {
	Position = UDim2.new(1, -90, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 24,
	Font = Enum.Font.GothamBlack,
})
local jobInfo = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 20), { Position = UDim2.fromOffset(0, 28), TextColor3 = C.dim, TextSize = 15, Font = Enum.Font.GothamMedium })
local conditionBack, conditionFill = Ui.bar(jobPanel, UDim2.new(1, 0, 0, 16), C.yellow)
conditionBack.Position = UDim2.fromOffset(0, 54)
local conditionText = Ui.label(conditionBack, "", UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, ZIndex = 2 })
local jobKills = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 18), { Position = UDim2.fromOffset(0, 74), TextColor3 = C.red, TextSize = 14 })

-- ── The way to the customer ────────────────────────────────────────────────

local guide = Instance.new("Folder")
guide.Name = "DeliveryGuide"
guide.Parent = workspace

local function guidePart(name: string, size: Vector3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = C.yellow
	p.Size = size
	p.Transparency = transparency
	p.Parent = guide
	return p
end

local beacon = guidePart("Beacon", Vector3.new(240, 5, 5), 0.55)
beacon.Shape = Enum.PartType.Cylinder
local ring = guidePart("Ring", Vector3.new(0.2, Config.Jobs.DeliverRadius * 2, Config.Jobs.DeliverRadius * 2), 0.5)
ring.Shape = Enum.PartType.Cylinder
local label = guidePart("Label", Vector3.new(0.2, 0.2, 0.2), 1)
local labelGui = Ui.make("BillboardGui", { Size = UDim2.fromOffset(220, 60), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000 }, label)
local labelText = Ui.label(labelGui, "", UDim2.fromScale(1, 1), {
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.yellow,
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
	TextStrokeTransparency = 0.2,
})
-- The arrow over the car: a shaft and two sides of a head, pointing along -Z of its frame.
local arrowParts = {
	{ part = guidePart("ArrowShaft", Vector3.new(0.6, 0.4, 3.6), 0), offset = CFrame.new(0, 0, 0.8) },
	{ part = guidePart("ArrowLeft", Vector3.new(0.6, 0.4, 2.6), 0), offset = CFrame.lookAt(Vector3.new(-0.84, 0, -0.6), Vector3.new(0, 0, -1.6)) },
	{ part = guidePart("ArrowRight", Vector3.new(0.6, 0.4, 2.6), 0), offset = CFrame.lookAt(Vector3.new(0.84, 0, -0.6), Vector3.new(0, 0, -1.6)) },
}
local HIDDEN = CFrame.new(0, -1000, 0)

local function hideGuide()
	beacon.CFrame = HIDDEN
	ring.CFrame = HIDDEN
	label.CFrame = HIDDEN
	for _, a in arrowParts do
		a.part.CFrame = HIDDEN
	end
end
hideGuide()

local function myPosition(): Vector3?
	local car = Drive.myCar()
	if car and car.PrimaryPart then
		return car.PrimaryPart.Position
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

-- ── Updates ────────────────────────────────────────────────────────────────

function Hud.setState(newState: any)
	state = newState
	moneyLabel.Text = Ui.money(state.money)
	statsLabel.Text = `Deliveries {state.deliveries} · Kills {state.kills}`
	if garageWindow.Visible then
		renderGarage()
	end
end

function Hud.setJob(newJob: any)
	job = newJob
	jobPanel.Visible = job ~= nil
	if not job then
		hideGuide()
		return
	end
	jobTitle.Text = `{Ui.stars(job.stars)}  {job.cargo} → {job.customer}`
	conditionFill.Size = UDim2.fromScale(math.clamp(job.condition, 0, 1), 1)
	conditionFill.BackgroundColor3 = if job.condition > 0.6 then C.yellow elseif job.condition > 0.3 then Color3.fromRGB(255, 140, 40) else C.red
	conditionText.Text = `Cargo condition {math.floor(job.condition * 100 + 0.5)}%`
	jobKills.Text = `Zombies killed: {job.kills}   ·   Pay {Ui.money(job.pay)}`
	local p = job.position
	beacon.CFrame = CFrame.new(p + Vector3.new(0, 120, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.CFrame = CFrame.new(p + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	label.CFrame = CFrame.new(p + Vector3.new(0, 10, 0))
end

local lastDepot: boolean? = nil

RunService.RenderStepped:Connect(function()
	-- The car.
	local car = Drive.myCar()
	local driving = Drive.isDriving()
	if car then
		local def = Economy.findCar(tostring(car:GetAttribute("CarId")))
		carName.Text = if def then def.name else "Car"
		local health = (car:GetAttribute("Health") or 0) :: number
		local maxHealth = math.max(1, (car:GetAttribute("MaxHealth") or 1) :: number)
		local share = math.clamp(health / maxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(share, 1)
		healthFill.BackgroundColor3 = if share > 0.5 then C.green elseif share > 0.25 then Color3.fromRGB(255, 160, 40) else C.red
		healthText.Text = `{math.ceil(health)} / {math.floor(maxHealth)}`
		local chassis = car.PrimaryPart
		local v = if chassis then chassis.AssemblyLinearVelocity else Vector3.zero
		speedLabel.Text = `{math.floor(Vector3.new(v.X, 0, v.Z).Magnitude)} km/h`
	else
		carName.Text = "No car"
		speedLabel.Text = ""
		healthFill.Size = UDim2.fromScale(0, 1)
		healthText.Text = "Press CAR to get one"
	end

	local touch = UserInputService.TouchEnabled
	fire.Visible = driving and touch
	local depot = inDepot()
	if depot then
		hint.Text = "DEPOT · your car is repaired here · GARAGE to shop"
		hint.TextColor3 = C.green
	elseif driving and not touch then
		hint.Text = "Drive: WASD · Shoot: hold left mouse · Auto-aim: hold F · Exit: Space"
		hint.TextColor3 = C.dim
	elseif not car then
		hint.Text = "Press CAR to call your car"
		hint.TextColor3 = C.dim
	elseif not driving then
		hint.Text = "Walk to your car and press E to drive"
		hint.TextColor3 = C.dim
	else
		hint.Text = ""
	end
	if depot ~= lastDepot then
		lastDepot = depot
		if garageWindow.Visible then
			renderGarage()
		end
	end

	-- The job.
	if job then
		local left = job.endsAt - workspace:GetServerTimeNow()
		jobTimer.Text = Ui.clock(left)
		jobTimer.TextColor3 = if left < 15 then C.red else C.text
		local position = myPosition()
		local target: Vector3 = job.position
		if position then
			local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
			local distance = math.floor(flat.Magnitude)
			jobInfo.Text = `{job.address} · {distance} m · stop in the yellow circle`
			labelText.Text = `{job.customer}\n{distance} m`
			if car and car.PrimaryPart and flat.Magnitude > 1 then
				local origin = car.PrimaryPart.Position + Vector3.new(0, 11, 0)
				local frame = CFrame.lookAt(origin, origin + flat.Unit)
				for _, a in arrowParts do
					a.part.CFrame = frame * a.offset
				end
			else
				for _, a in arrowParts do
					a.part.CFrame = HIDDEN
				end
			end
		end
	end
end)

function Hud.start()
	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

return Hud
