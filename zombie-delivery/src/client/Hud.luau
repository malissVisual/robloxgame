--!strict
-- The interface: money, the minimap (client/MapView.luau), the car panel (health, speed, nitro), the active job
-- (stage, timer, distance, cargo condition, loading bar), the JOBS / MAP / BAG / CAR buttons, the hotbar (items,
-- keys 1-5), the job board, the shops (opened by their counters), the backpack, the delivery result, toasts,
-- the FIRE button for touch screens and the way to the target (a beacon, a circle and an arrow over the car).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Drive = require(script.Parent.Drive)
local Shooting = require(script.Parent.Shooting)
local MapView = require(script.Parent.MapView)

local C = Ui.Colors
local Hud = {}

local player = Players.LocalPlayer
local state: any = nil
local job: any = nil

local gui = Ui.make("ScreenGui", {
	Name = "ZombieDeliveryHud",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
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

local function myRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearShop(shop: string): boolean
	local root = myRoot()
	local info = Map.Shops[shop]
	return root ~= nil and info ~= nil and Vector3.new(root.Position.X - info.x, 0, root.Position.Z - info.z).Magnitude < Map.ShopRadius
end

-- ── Money ──────────────────────────────────────────────────────────────────

local moneyPanel = scaled(Ui.panel(gui, UDim2.fromOffset(210, 66), UDim2.fromOffset(16, 16)))
Ui.padding(moneyPanel, 8)
local moneyLabel = Ui.label(moneyPanel, "$0", UDim2.new(1, 0, 0, 32), { TextColor3 = C.money, TextSize = 30, Font = Enum.Font.GothamBlack })
local statsLabel = Ui.label(moneyPanel, "", UDim2.new(1, 0, 0, 16), { Position = UDim2.fromOffset(0, 34), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })

-- ── Toasts ─────────────────────────────────────────────────────────────────

local toasts = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(520, 200),
	Position = UDim2.new(0.5, 0, 0, 200),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
}, gui))
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

type Window = { frame: any, body: any, title: any }

local function window(title: string, size: Vector2): Window
	local frame = scaled(Ui.panel(gui, UDim2.fromOffset(size.X, size.Y), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)))
	frame.Visible = false
	frame.BackgroundTransparency = 0.05
	frame.ZIndex = 5
	Ui.stroke(frame, C.yellow, 2)
	local titleLabel = Ui.label(frame, title, UDim2.new(1, -70, 0, 44), { Position = UDim2.fromOffset(18, 6), TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = C.yellow })
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
	return { frame = frame, body = body, title = titleLabel }
end

local function card(parent: any, height: number, order: number, highlight: boolean?): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, height),
		BackgroundColor3 = C.panelLight,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Ui.corner(frame, 10)
	if highlight then
		Ui.stroke(frame, C.yellow, 3)
	end
	return frame
end

-- name / stats / description on the left of a card.
local function cardText(c: any, name: string, stats: string, description: string, left: number?)
	local x = left or 14
	Ui.label(c, name, UDim2.new(1, -190 - x, 0, 26), { Position = UDim2.fromOffset(x, 6), TextSize = 21, Font = Enum.Font.GothamBlack })
	Ui.label(c, stats, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 34), TextColor3 = C.yellow, TextSize = 15 })
	Ui.label(c, description, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 56), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
end

local function cardButton(parent: any, text: string, color: Color3, enabled: boolean, onClick: () -> (), slot: number?): any
	local button = Ui.button(parent, text, UDim2.fromOffset(150, 40), if enabled then color else C.grey, function()
		if enabled then
			onClick()
		end
	end)
	button.AutoButtonColor = enabled
	button.TextSize = 16
	local n = slot or 0
	button.Position = UDim2.new(1, -162, 0, if n == 0 then 22 else 2 + (n - 1) * 44)
	return button
end

local function tabs(parent: any, list: { { string } }, selected: string, onPick: (string) -> ())
	local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundTransparency = 1, LayoutOrder = 0 }, parent)
	Ui.list(row, false, 8)
	for _, entry in list do
		local on = entry[1] == selected
		local button = Ui.button(row, entry[2], UDim2.fromOffset(140, 38), if on then C.yellow else C.grey, function()
			onPick(entry[1])
		end)
		button.TextColor3 = if on then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	end
end

local function note(parent: any, text: string, color: Color3, order: number)
	Ui.label(parent, text, UDim2.new(1, -10, 0, 22), { LayoutOrder = order, TextColor3 = color, TextSize = 15, Font = Enum.Font.GothamMedium })
end

-- ── Job board ──────────────────────────────────────────────────────────────

local jobs = window("JOB BOARD", Vector2.new(600, 470))
local offersRemote = Net.get("RequestOffers")

local function jobsMessage(text: string)
	Ui.clear(jobs.body)
	Ui.label(jobs.body, text, UDim2.new(1, -10, 0, 60), { TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center })
end

local function openJobs()
	closeWindows()
	jobs.frame.Visible = true
	if job then
		Ui.clear(jobs.body)
		Ui.label(jobs.body, `You are delivering {job.cargo} to {job.customer}. Finish it first, or give it up.`, UDim2.new(1, -10, 0, 60), { TextColor3 = C.text })
		Ui.button(jobs.body, "GIVE UP THIS DELIVERY", UDim2.fromOffset(280, 46), C.red, function()
			Net.get("CancelJob"):FireServer()
			jobs.frame.Visible = false
		end)
		return
	end
	jobsMessage("Calling the dispatcher...")
	offersRemote:FireServer()
end

local STAR_COLORS = { C.green, C.yellow, C.red, Color3.fromRGB(200, 80, 255) }

function Hud.setOffers(list: { any })
	if job then
		return
	end
	Ui.clear(jobs.body)
	for order, offer in list do
		local color = STAR_COLORS[offer.stars] or C.red
		local c = card(jobs.body, if offer.jobType then 126 else 104, order, offer.jobType ~= nil)
		Ui.label(c, string.rep("★", offer.stars), UDim2.fromOffset(110, 26), { Position = UDim2.fromOffset(12, 6), TextColor3 = color, TextSize = 24 })
		Ui.label(c, offer.tierName:upper(), UDim2.fromOffset(110, 18), { Position = UDim2.fromOffset(12, 32), TextColor3 = color, TextSize = 14 })
		if offer.modifier then
			local chip = Ui.label(c, offer.modifier.name, UDim2.fromOffset(100, 22), {
				Position = UDim2.fromOffset(12, 56),
				BackgroundTransparency = 0,
				BackgroundColor3 = C.red,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 13,
			})
			Ui.corner(chip, 6)
		end
		local headline = if offer.jobType then `{offer.jobType.name}: {offer.cargo}` else `{offer.cargo} → {offer.customer}`
		Ui.label(c, headline, UDim2.new(1, -260, 0, 24), { Position = UDim2.fromOffset(124, 6), TextSize = 18, TextColor3 = if offer.jobType then Color3.fromRGB(130, 200, 255) else C.text })
		Ui.label(c, `First: {offer.first}`, UDim2.new(1, -260, 0, 18), { Position = UDim2.fromOffset(124, 32), TextColor3 = Color3.fromRGB(130, 200, 255), TextSize = 14, Font = Enum.Font.GothamMedium })
		Ui.label(c, `{offer.stops} stops · last: {offer.address}, {offer.district} · {offer.distance} m · {Ui.clock(offer.time)}`, UDim2.new(1, -260, 0, 18), {
			Position = UDim2.fromOffset(124, 52),
			TextColor3 = C.dim,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
		})
		if offer.modifier then
			Ui.label(c, offer.modifier.description, UDim2.new(1, -260, 0, 18), { Position = UDim2.fromOffset(124, 74), TextColor3 = C.red, TextSize = 13, Font = Enum.Font.GothamMedium })
		end
		if offer.jobType then
			local extra = if offer.vehicle then `Company vehicle: {offer.vehicle}. ` else ""
			Ui.label(c, extra .. offer.jobType.description, UDim2.new(1, -260, 0, 34), { Position = UDim2.fromOffset(124, if offer.modifier then 92 else 74), TextColor3 = C.dim, TextSize = 13, Font = Enum.Font.GothamMedium })
		end
		Ui.label(c, Ui.money(offer.pay), UDim2.fromOffset(110, 30), { Position = UDim2.new(1, -244, 0, 36), TextColor3 = C.money, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right })
		local accept = Ui.button(c, "ACCEPT", UDim2.fromOffset(110, 46), C.green, function()
			Net.get("AcceptJob"):FireServer(offer.index)
			jobs.frame.Visible = false
		end)
		accept.Position = UDim2.new(1, -122, 0.5, -23)
	end
	local refresh = Ui.button(jobs.body, "NEW OFFERS", UDim2.fromOffset(180, 40), C.grey, function()
		jobsMessage("Calling the dispatcher...")
		offersRemote:FireServer()
	end)
	refresh.LayoutOrder = 99
end

-- ── Shops ──────────────────────────────────────────────────────────────────

local shop = window("SHOP", Vector2.new(700, 500))
local shopId = "dealer"
local shopFocus: string? = nil
local mechanicTab = "upgrades"

local function carStats(def: Config.CarDef): string
	return `Speed {def.maxSpeed} · Health {def.health} · Ram x{def.ramPower}`
end

local function renderShop()
	Ui.clear(shop.body)
	if not state then
		return
	end
	local money = state.money
	local here = nearShop(shopId)
	shop.title.Text = (Map.Shops[shopId] and Map.Shops[shopId].name or "SHOP"):upper()
	if not here then
		note(shop.body, "Walk into the shop to buy here.", C.red, 1)
	end
	if shopId == "dealer" then
		for order, def in Config.Cars do
			if def.company then
				continue
			end
			local c = card(shop.body, 84, order + 1, def.id == shopFocus)
			cardText(c, def.name, carStats(def), def.description)
			if state.car == def.id then
				cardButton(c, "YOUR CAR", C.grey, false, function() end)
			elseif state.cars[def.id] then
				cardButton(c, "TAKE IT", C.blue, here, function()
					Net.get("Equip"):FireServer("car", def.id)
				end)
			else
				cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
					Net.get("Buy"):FireServer("car", def.id)
				end)
			end
		end
	elseif shopId == "depot" then
		note(shop.body, "Your cars. Buy new ones at Dead End Motors (next door, east).", C.dim, 1)
		for order, def in Config.Cars do
			if not state.cars[def.id] or def.company then
				continue
			end
			local c = card(shop.body, 84, order + 1)
			cardText(c, def.name, carStats(def), def.description)
			if state.car == def.id then
				cardButton(c, "DRIVING", C.grey, false, function() end)
			else
				cardButton(c, "TAKE IT", C.blue, here, function()
					Net.get("Equip"):FireServer("car", def.id)
				end)
			end
		end
	elseif shopId == "guns" then
		for order, def in Config.Weapons do
			local c = card(shop.body, 84, order + 1)
			local pellets = if def.pellets > 1 then ` x{def.pellets}` else ""
			local splash = if def.splash > 0 then ` · Blast {def.splash}` else ""
			cardText(c, def.name, `Damage {def.damage}{pellets} · {def.fireRate}/s · Range {def.range}{splash}`, def.description)
			if state.weapon == def.id then
				cardButton(c, "IN HAND", C.grey, false, function() end)
			elseif state.weapons[def.id] then
				cardButton(c, "EQUIP", C.blue, true, function()
					Net.get("Equip"):FireServer("weapon", def.id)
				end)
			else
				cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
					Net.get("Buy"):FireServer("weapon", def.id)
				end)
			end
		end
	elseif shopId == "supplies" then
		for order, def in Config.Items do
			local c = card(shop.body, 90, order + 1)
			local have = state.items[def.id] or 0
			Ui.label(c, def.icon, UDim2.fromOffset(50, 50), { Position = UDim2.fromOffset(10, 18), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
			cardText(c, def.name, `{Ui.money(def.price)} each · you have {have}/{def.max}`, def.description, 70)
			cardButton(c, `BUY 1  {Ui.money(def.price)}`, C.green, here and money >= def.price and have < def.max, function()
				Net.get("Buy"):FireServer("item", def.id, 1)
			end, 1)
			cardButton(c, `BUY 5  {Ui.money(def.price * 5)}`, C.green, here and money >= def.price * 5 and have + 5 <= def.max, function()
				Net.get("Buy"):FireServer("item", def.id, 5)
			end, 2)
		end
	elseif shopId == "mechanic" then
		tabs(shop.body, { { "upgrades", "UPGRADES" }, { "paint", "PAINT" } }, mechanicTab, function(id)
			mechanicTab = id
			renderShop()
		end)
		if mechanicTab == "upgrades" then
			note(shop.body, "Upgrades work for every car you own. Your car is repaired for free in here.", C.dim, 1)
			for order, def in Config.Upgrades do
				local c = card(shop.body, 84, order + 1)
				local level = Economy.level(state.upgrades, def.id)
				cardText(c, def.name, string.rep("■", level) .. string.rep("□", def.maxLevel - level) .. `  Lv {level}/{def.maxLevel}`, def.description)
				local cost = Economy.upgradeCost(def.id, level)
				if cost then
					cardButton(c, `UPGRADE {Ui.money(cost)}`, C.green, here and money >= cost, function()
						Net.get("Upgrade"):FireServer(def.id)
					end)
				else
					cardButton(c, "MAX", C.grey, false, function() end)
				end
			end
		else
			local carDef = Economy.findCar(state.car)
			note(shop.body, `Paint for your {if carDef then carDef.name else "car"}. Bought paints are yours for every car.`, C.dim, 1)
			local current = state.carPaint[state.car] or "factory"
			for order, def in Config.Paints do
				local c = card(shop.body, 70, order + 1)
				local swatchColor = if def.color then Color3.fromRGB(def.color[1], def.color[2], def.color[3]) elseif carDef then Color3.fromRGB(carDef.color[1], carDef.color[2], carDef.color[3]) else C.grey
				local swatch = Ui.make("Frame", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(12, 13), BackgroundColor3 = swatchColor }, c)
				Ui.corner(swatch, 8)
				Ui.stroke(swatch, Color3.new(0, 0, 0), 2)
				Ui.label(c, def.name, UDim2.new(1, -260, 0, 26), { Position = UDim2.fromOffset(70, 8), TextSize = 20, Font = Enum.Font.GothamBlack })
				Ui.label(c, if state.paints[def.id] then "Owned" else Ui.money(def.price), UDim2.new(1, -260, 0, 20), { Position = UDim2.fromOffset(70, 36), TextColor3 = C.yellow, TextSize = 15 })
				if current == def.id then
					cardButton(c, "ON YOUR CAR", C.grey, false, function() end).Position = UDim2.new(1, -162, 0, 15)
				elseif state.paints[def.id] then
					cardButton(c, "APPLY", C.blue, here, function()
						Net.get("Paint"):FireServer(def.id)
					end).Position = UDim2.new(1, -162, 0, 15)
				else
					cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
						Net.get("Paint"):FireServer(def.id)
					end).Position = UDim2.new(1, -162, 0, 15)
				end
			end
		end
	end
end

function Hud.openShop(id: string, focus: string?)
	if id == "jobs" then
		openJobs()
		return
	end
	closeWindows()
	shopId = id
	shopFocus = focus
	shop.frame.Visible = true
	renderShop()
end

-- ── Backpack ───────────────────────────────────────────────────────────────

local backpack = window("BACKPACK", Vector2.new(640, 480))
local backpackTab = "items"

local function useItem(id: string)
	local count = if state then state.items[id] or 0 else 0
	if count <= 0 then
		local def = Economy.findItem(id)
		Hud.toast(`No {if def then def.name else id} left. Buy more at Last Stop Supplies.`)
		return
	end
	Net.get("UseItem"):FireServer(id, Shooting.aimPoint())
end

local function renderBackpack()
	Ui.clear(backpack.body)
	if not state then
		return
	end
	tabs(backpack.body, { { "items", "ITEMS" }, { "cars", "CARS" }, { "guns", "GUNS" } }, backpackTab, function(id)
		backpackTab = id
		renderBackpack()
	end)
	if backpackTab == "items" then
		for order, def in Config.Items do
			local c = card(backpack.body, 84, order + 1)
			local have = state.items[def.id] or 0
			Ui.label(c, def.icon, UDim2.fromOffset(50, 50), { Position = UDim2.fromOffset(10, 16), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
			cardText(c, `{def.name}  x{have}`, `Key {order}`, def.description, 70)
			cardButton(c, "USE", C.green, have > 0, function()
				useItem(def.id)
			end)
		end
	elseif backpackTab == "cars" then
		note(backpack.body, "Switch cars at the depot garage, buy new ones at Dead End Motors.", C.dim, 1)
		for order, def in Config.Cars do
			if state.cars[def.id] and not def.company then
				local c = card(backpack.body, 84, order + 1)
				cardText(c, def.name, carStats(def), def.description)
				if state.car == def.id then
					cardButton(c, "DRIVING", C.grey, false, function() end)
				end
			end
		end
	else
		for order, def in Config.Weapons do
			if state.weapons[def.id] then
				local c = card(backpack.body, 84, order + 1)
				cardText(c, def.name, `Damage {def.damage} · {def.fireRate}/s · Range {def.range}`, def.description)
				if state.weapon == def.id then
					cardButton(c, "IN HAND", C.grey, false, function() end)
				else
					cardButton(c, "EQUIP", C.blue, true, function()
						Net.get("Equip"):FireServer("weapon", def.id)
					end)
				end
			end
		end
	end
end

local function toggleBackpack()
	if backpack.frame.Visible then
		backpack.frame.Visible = false
	else
		closeWindows()
		backpack.frame.Visible = true
		renderBackpack()
	end
end

-- ── Delivery result ────────────────────────────────────────────────────────

local result = window("DELIVERY", Vector2.new(430, 420))

function Hud.showResult(r: any)
	closeWindows()
	Ui.clear(result.body)
	result.frame.Visible = true
	local function line(text: string, value: string?, color: Color3?, order: number)
		local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 28), BackgroundTransparency = 1, LayoutOrder = order }, result.body)
		Ui.label(row, text, UDim2.new(1, -110, 1, 0), { TextColor3 = color or C.text, TextSize = 18 })
		if value then
			Ui.label(row, value, UDim2.new(0, 110, 1, 0), { Position = UDim2.new(1, -110, 0, 0), TextColor3 = color or C.money, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right })
		end
	end
	if r.success and r.rider then
		line("CREW DELIVERY!", nil, C.green, 1)
		line(`You helped {r.driver} deliver {r.cargo}.`, nil, C.dim, 2)
		line("Your share", Ui.money(r.total), C.yellow, 3)
	elseif r.success then
		local payout = r.payout
		line("DELIVERED!", nil, C.green, 1)
		line(`{r.cargo} for {r.customer}`, nil, C.dim, 2)
		line("Pay", Ui.money(payout.base), nil, 3)
		line(`Cargo condition {math.floor(r.condition * 100 + 0.5)}%`, Ui.money(payout.conditionPay), nil, 4)
		line("Speed bonus", "+" .. Ui.money(payout.fastBonus), nil, 5)
		line(`Zombies killed ({r.kills})`, "+" .. Ui.money(payout.killBonus), nil, 6)
		if r.crew > 0 then
			line(`Crew bonus ({r.crew} riding)`, "+" .. Ui.money(r.crewBonus), nil, 7)
		end
		line("TOTAL", Ui.money(r.total), C.yellow, 8)
	else
		line("DELIVERY FAILED", nil, C.red, 1)
		Ui.label(result.body, r.reason or "", UDim2.new(1, -10, 0, 60), { LayoutOrder = 2, TextColor3 = C.text })
	end
	local ok = Ui.button(result.body, "OK", UDim2.fromOffset(160, 44), C.blue, function()
		result.frame.Visible = false
	end)
	ok.LayoutOrder = 10
	local next = Ui.button(result.body, "NEXT JOB", UDim2.fromOffset(160, 44), C.green, function()
		result.frame.Visible = false
		openJobs()
	end)
	next.LayoutOrder = 11
end

-- ── Buttons ────────────────────────────────────────────────────────────────

local side = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(150, 250),
	Position = UDim2.new(1, -16, 0.42, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	BackgroundTransparency = 1,
}, gui))
Ui.list(side, true, 10)
Ui.button(side, "JOBS  [J]", UDim2.fromOffset(150, 52), C.yellow, function()
	if jobs.frame.Visible then
		jobs.frame.Visible = false
	else
		openJobs()
	end
end).TextColor3 = Color3.new(0, 0, 0)
Ui.button(side, "MAP  [M]", UDim2.fromOffset(150, 52), Color3.fromRGB(150, 90, 200), function()
	MapView.toggle()
end)
Ui.button(side, "BAG  [B]", UDim2.fromOffset(150, 52), C.blue, toggleBackpack)
Ui.button(side, "CAR", UDim2.fromOffset(150, 52), C.grey, function()
	Net.get("SpawnCar"):FireServer()
end)

-- ── Hotbar ─────────────────────────────────────────────────────────────────

local hotbar = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(5 * 64 + 4 * 8, 64),
	Position = UDim2.new(0.5, 0, 1, -112),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundTransparency = 1,
}, gui))
Ui.list(hotbar, false, 8)
local hotbarCounts: { [string]: any } = {}
for index, def in Config.Items do
	local slot = Ui.make("TextButton", {
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		Text = def.icon,
		TextSize = 30,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		LayoutOrder = index,
		AutoButtonColor = true,
	}, hotbar)
	Ui.corner(slot, 10)
	Ui.stroke(slot, C.yellow, 1.5)
	Ui.label(slot, tostring(index), UDim2.fromOffset(16, 16), { Position = UDim2.fromOffset(4, 2), TextSize = 13, TextColor3 = C.yellow })
	hotbarCounts[def.id] = Ui.label(slot, "0", UDim2.new(1, -6, 0, 16), {
		Position = UDim2.new(0, 0, 1, -18),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	slot.Activated:Connect(function()
		useItem(def.id)
	end)
end

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
local hint = Ui.label(gui, "", UDim2.fromOffset(640, 22), {
	Position = UDim2.new(0.5, 0, 1, -182),
	AnchorPoint = Vector2.new(0.5, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.dim,
	TextSize = 15,
	TextStrokeTransparency = 0.5,
	Font = Enum.Font.GothamMedium,
})

-- ── Job panel ──────────────────────────────────────────────────────────────

local jobPanel = scaled(Ui.panel(gui, UDim2.fromOffset(500, 150), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0)))
jobPanel.Visible = false
Ui.padding(jobPanel, 10)
Ui.stroke(jobPanel, C.yellow, 2)
local jobTitle = Ui.label(jobPanel, "", UDim2.new(1, -90, 0, 24), { TextSize = 18, Font = Enum.Font.GothamBlack })
local jobTimer = Ui.label(jobPanel, "", UDim2.new(0, 90, 0, 24), {
	Position = UDim2.new(1, -90, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 24,
	Font = Enum.Font.GothamBlack,
})
local jobStage = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 22), { Position = UDim2.fromOffset(0, 28), TextSize = 17, Font = Enum.Font.GothamBlack })
local jobInfo = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 20), { Position = UDim2.fromOffset(0, 52), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
local conditionBack, conditionFill = Ui.bar(jobPanel, UDim2.new(1, 0, 0, 16), C.yellow)
conditionBack.Position = UDim2.fromOffset(0, 78)
local conditionText = Ui.label(conditionBack, "", UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, ZIndex = 2 })
local jobKills = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 18), { Position = UDim2.fromOffset(0, 100), TextColor3 = C.red, TextSize = 14 })

-- Loading / unloading bar in the middle of the screen.
local loadBack, loadFill = Ui.bar(gui, UDim2.fromOffset(320, 26), Color3.fromRGB(110, 190, 255))
scaled(loadBack)
loadBack.AnchorPoint = Vector2.new(0.5, 0.5)
loadBack.Position = UDim2.fromScale(0.5, 0.62)
loadBack.Visible = false
local loadText = Ui.label(loadBack, "", UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, ZIndex = 2, Font = Enum.Font.GothamBlack })

-- ── The way to the target ──────────────────────────────────────────────────

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
local labelGui = Ui.make("BillboardGui", { Size = UDim2.fromOffset(240, 60), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000 }, label)
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
local PICKUP_COLOR = Color3.fromRGB(110, 190, 255)

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
	local car = Drive.seatedCar() or Drive.myCar()
	if car and car.PrimaryPart then
		return car.PrimaryPart.Position
	end
	local root = myRoot()
	return if root then root.Position else nil
end

-- ── Updates ────────────────────────────────────────────────────────────────

function Hud.setState(newState: any)
	state = newState
	moneyLabel.Text = Ui.money(state.money)
	statsLabel.Text = `Deliveries {state.deliveries} · Kills {state.kills}`
	for id, count in hotbarCounts do
		count.Text = tostring(state.items[id] or 0)
	end
	if shop.frame.Visible then
		renderShop()
	end
	if backpack.frame.Visible then
		renderBackpack()
	end
end

function Hud.setJob(newJob: any)
	job = newJob
	jobPanel.Visible = job ~= nil
	if not job then
		hideGuide()
		loadBack.Visible = false
		MapView.setTarget(nil)
		return
	end
	local pickup = job.stage == "pickup"
	local modifier = if job.modifier then `  [{job.modifier.name}]` else ""
	local name = if job.jobType then job.jobType.name else `{job.cargo} → {job.customer}`
	jobTitle.Text = `{string.rep("★", job.stars)}  {name}{modifier}`
	jobStage.Text = `{job.stopIndex}/{job.stopCount}  {job.stopLabel}`
	jobStage.TextColor3 = if pickup then PICKUP_COLOR else C.yellow
	conditionFill.Size = UDim2.fromScale(math.clamp(job.condition, 0, 1), 1)
	conditionFill.BackgroundColor3 = if job.condition > 0.6 then C.yellow elseif job.condition > 0.3 then Color3.fromRGB(255, 140, 40) else C.red
	conditionText.Text = `Cargo condition {math.floor(job.condition * 100 + 0.5)}%`
	jobKills.Text = `Zombies killed: {job.kills}   ·   Pay {Ui.money(job.pay)}`
	local color = if pickup then PICKUP_COLOR else C.yellow
	for _, p in { beacon, ring } do
		p.Color = color
	end
	for _, a in arrowParts do
		a.part.Color = color
	end
	labelText.TextColor3 = color
	local p = job.position
	beacon.CFrame = CFrame.new(p + Vector3.new(0, 120, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.CFrame = CFrame.new(p + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	label.CFrame = CFrame.new(p + Vector3.new(0, 10, 0))
	MapView.setTarget(p)
	-- Loading / unloading progress.
	local progress = job.progress or 0
	loadBack.Visible = progress > 0
	loadFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	loadText.Text = if pickup then "LOADING... hold still" elseif job.cargo == "Ice Cream" then "SELLING ICE CREAM... hold still" else "UNLOADING... hold them off!"
end

function Hud.setVisible(visible: boolean)
	gui.Enabled = visible
	MapView.setVisible(visible)
end

local lastShop: string? = nil

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	-- The car.
	local car = Drive.myCar()
	local seatedIn, driving = Drive.seatedCar()
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
		speedLabel.Text = (if Drive.boosting() then "⚡ " else "") .. `{math.floor(Vector3.new(v.X, 0, v.Z).Magnitude)} km/h`
	else
		carName.Text = "No car"
		speedLabel.Text = ""
		healthFill.Size = UDim2.fromScale(0, 1)
		healthText.Text = "Press CAR to get one"
	end

	local touch = UserInputService.TouchEnabled
	fire.Visible = seatedIn ~= nil and touch
	-- Which shop am I in?
	local inShop: string? = nil
	for id in Map.Shops do
		if nearShop(id) and id ~= "depot" then
			inShop = id
		end
	end
	local root = myRoot()
	local safe = root ~= nil and Map.isSafe(root.Position.X, root.Position.Z)
	if inShop then
		hint.Text = `{Map.Shops[inShop].name}: walk to the counter and press E`
		hint.TextColor3 = C.green
	elseif seatedIn and not driving then
		hint.Text = "Riding along: hold left mouse to shoot (F auto-aim), Space to get out"
		hint.TextColor3 = Color3.fromRGB(140, 210, 255)
	elseif safe and not job then
		hint.Text = "SAFE ZONE · shops around the depot · JOBS to start a delivery"
		hint.TextColor3 = C.green
	elseif driving and not touch then
		hint.Text = "WASD drive · hold left mouse shoot · F auto-aim · 1-5 items · Space get out"
		hint.TextColor3 = C.dim
	elseif not car then
		hint.Text = "Press CAR to call your car"
		hint.TextColor3 = C.dim
	elseif not seatedIn then
		hint.Text = "Walk to your car and press E to drive"
		hint.TextColor3 = C.dim
	else
		hint.Text = ""
	end
	if inShop ~= lastShop then
		lastShop = inShop
		if shop.frame.Visible then
			renderShop()
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
			local verb = if job.stage == "pickup" then "load" else "unload"
			jobInfo.Text = `{distance} m · stop in the circle and hold still to {verb}`
			labelText.Text = (if job.stage == "pickup" then `PICK UP\n` else `{job.customer}\n`) .. `{distance} m`
			local arrowFrom = seatedIn or car
			if arrowFrom and arrowFrom.PrimaryPart and flat.Magnitude > 1 then
				local origin = arrowFrom.PrimaryPart.Position + Vector3.new(0, 11, 0)
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
	MapView.start(gui, scaled)
	-- Keys.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not gui.Enabled or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.M then
			MapView.toggle()
		elseif key == Enum.KeyCode.J then
			if jobs.frame.Visible then
				jobs.frame.Visible = false
			else
				openJobs()
			end
		elseif key == Enum.KeyCode.B then
			toggleBackpack()
		else
			local numbers = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
			local index = table.find(numbers, key)
			if index and Config.Items[index] then
				useItem(Config.Items[index].id)
			end
		end
	end)
end

return Hud
