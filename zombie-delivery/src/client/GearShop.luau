--!strict
-- 4.6: Wrench Garage's GEAR tab (the mechanic's shop window in client/Hud.luau draws it with GearShop.render): the
-- gear of the car you drive (Config.Gear; profile.carGear in the state). The car's gear slots on top ("SLOTS 1 / 2",
-- a pip each), then every piece as a slim contract row: its name, its level and price, OWNED / INSTALLED or not
-- bought, what it does, and the one action that fits: BUY (from its level: "LEVEL 4" until then), INSTALL (free, into
-- a free slot), REMOVE (free: it stays the car's). The server checks everything again (server/Shops.luau, the "Gear"
-- remote). Presentation only, no state of its own.
-- 5.8, the courier phone's look: the head is the phone's card (the red square and caps, SLOTS in big type, a thin rule
-- under it); BUY and INSTALL are the phone's red primary.
-- 5.1: the car gear only (GearDef.bikeOnly is not shown here; riding your bike: a note sends you to the BIKES counter).
-- The BIKES counter's GEAR tab (client/BikeShop.luau; Spoke & Chain's until 6.12.7) draws the bike gear for your bike
-- with the same rows (forBike).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Icons = require(Shared.Icons)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Transport = require(Shared.Transport)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)

local GearShop = {}

local player = Players.LocalPlayer
local ROW_H = 92
local BUTTON_W = 150

local function myLevel(state: any): number
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and type(state.xp) == "number" then
		xp = state.xp
	end
	return Levels.levelFor(xp or 0)
end

local function send(action: string, id: string)
	Net.get("Gear"):FireServer(action, id)
end

-- The row's action on its right (like the shop's other cards): "primary" the one clear action (5.8: the phone's red
-- face), "quiet" an outline, "off" a dim face whose words say why not.
local function action(row: any, text: string, kind: P.ButtonKind, onClick: () -> ())
	local button = P.button(row, text, UDim2.fromOffset(BUTTON_W, 40), kind, if kind == "off" then function() end else onClick)
	button.Position = UDim2.new(1, -BUTTON_W - 12, 0.5, -20)
	button.TextSize = 14
	return button
end

-- Why a piece does not fit a car, in a few words (the button).
local function misfit(gear: Config.GearDef): string
	if gear.bikeOnly then
		return "NOT ON THIS BIKE" -- 5.1: the trailer and the Cargo Bike
	elseif gear.needs == "trolley" then
		return "VANS & TRUCKS"
	end
	return "NOT ON THIS CAR"
end

-- 5.8, the courier phone's tag line (design/phone-ui/): the small red square and the caps label, over a head.
local function tagLine(parent: Instance, text: string, order: number): any
	local row = Ui.make("Frame", { Name = "Tag", Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	P.marker(row, 8, { Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5) })
	P.caps(row, text, UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(16, 0), TextStrokeTransparency = 1 })
	return row
end

-- A note instead of the rows (no vehicle, no bike, the wrong shop).
local function note(body: Instance, title: string, text: string)
	local none = Ui.make("Frame", { Name = "GearSlots", Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, body)
	Ui.list(none, true, 4)
	tagLine(none, title, 1)
	Ui.label(none, text, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextColor3 = P.ink2, TextSize = 14, Font = Theme.Font })
end

-- Draws the GEAR tab into `body` (the shop's scrolling body, a vertical list; Hud clears it first). `here`: at the
-- counter (only there the actions work). 5.1: `forBike` (the BIKES counter): the bike gear of `bikeId` (your bike).
function GearShop.render(body: Instance, state: any, here: boolean, forBike: boolean?, bikeId: string?)
	local vehicleId: string? = if forBike then bikeId elseif type(state.car) == "string" then state.car else nil
	if vehicleId == nil then
		-- 5.0: you start on foot: no car, no gear to show (not the van's list with BUY buttons).
		if forBike then
			note(body, "Bike gear · no bike yet", "Bike gear goes on a bike of your own: buy one in the BIKES tab first.")
		else
			note(body, "Gear · no vehicle yet", `Gear goes on a car of your own, and you are still on foot. Your first one: the Old Van from {Config.VanQuest.Where}.`)
		end
		return
	end
	if not forBike and Transport.isBike(vehicleId) then
		note(body, "Gear · you ride your bike", "A bike takes bike gear, at the BIKES counter of Dead End Motors. For your car's gear, CALL CAR on your phone first.")
		return
	end
	local carId: string = vehicleId
	local carDef = Economy.findCar(carId)
	local carGear: Economy.CarGear = if type(state.carGear) == "table" then state.carGear else {}
	local levels = Economy.carLevels(state.carUpgrades, carId)
	local stage = Economy.stageOf(carId, levels)
	local slots = Economy.gearSlots(carId, stage)
	local used = Economy.gearUsed(carGear, carId)
	local company = carDef == nil or not Economy.canUpgrade(carId)
	local level = myLevel(state)
	local money = tonumber(state.money) or 0

	-- The car and its gear slots: a pip for each, filled while a piece is in it.
	local head = Ui.make("Frame", { Name = "GearSlots", Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, body)
	Ui.list(head, true, 4)
	tagLine(head, if company then "Gear · company vehicle" else `Gear for your {Economy.carTitle(carId, levels)}`, 1)
	local line = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, head)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, line)
	P.text(line, `SLOTS  {used} / {slots}`, UDim2.fromOffset(0, 30), { AutomaticSize = Enum.AutomaticSize.X, Font = Theme.DisplayFont, TextSize = 22, TextStrokeTransparency = 1, LayoutOrder = 1 })
	for n = 1, slots do
		local pip = Ui.make("Frame", {
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = if n <= used then P.ink else P.surface,
			BackgroundTransparency = if n <= used then 0 else 0.4,
			BorderSizePixel = 0,
			LayoutOrder = 1 + n,
		}, line)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.2 }, pip)
	end
	local explain = if company then "A company vehicle comes with what its job needs: no gear slots. Take one of your own cars out of your garage."
		elseif forBike then "Buy a piece once for this bike, then fit or remove it here for free. Each piece takes a gear slot and holds more light pieces."
		else "Buy a piece once for this car, then install or remove it here for free. Each piece takes one gear slot; bigger cars and later stages have more."
	Ui.label(head, explain, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, TextColor3 = if company then P.danger else P.ink2, TextSize = 14, Font = Theme.Font })
	P.rule(head, UDim2.new(1, 0, 0, 1), { LayoutOrder = 4 })

	for order, gear in Config.Gear do
		if (gear.bikeOnly == true) ~= (forBike == true) then
			continue -- (5.1: the bike gear at the BIKES counter, the car gear at Wrench Garage)
		end
		local now = Economy.gearState(carGear, carId, gear.id)
		local fits = not company and Economy.gearFits(carId, gear.id)
		local row = P.row(body, ROW_H, order + 1, now == "installed")
		Ui.icon(row, Icons.gear(gear.id), gear.icon, UDim2.fromOffset(40, 40), { Position = UDim2.fromOffset(14, ROW_H / 2 - 20), ImageColor3 = P.ink, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center })
		local left = 64
		Ui.label(row, gear.name, UDim2.new(1, -(left + BUTTON_W + 24), 0, 22), { Position = UDim2.fromOffset(left, 8), TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local status = if now == "installed" then `<font color="{P.hex(P.good)}">INSTALLED</font>`
			elseif now == "owned" then "OWNED · NOT INSTALLED"
			elseif level < gear.level then `<font color="{P.hex(P.warn)}">LEVEL {gear.level}</font>`
			else "NOT BOUGHT"
		Ui.label(row, `Level {gear.level} · {Ui.money(gear.price)} · {status}`, UDim2.new(1, -(left + BUTTON_W + 24), 0, 18), {
			Position = UDim2.fromOffset(left, 32),
			TextSize = 13,
			Font = Theme.HeadingFont,
			TextColor3 = P.ink2,
			RichText = true,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Ui.label(row, gear.description, UDim2.new(1, -(left + BUTTON_W + 24), 0, 34), { Position = UDim2.fromOffset(left, 52), TextSize = 13, Font = Theme.Font, TextColor3 = P.ink2, TextYAlignment = Enum.TextYAlignment.Top })
		if company then
			action(row, "COMPANY CAR", "off", function() end)
		elseif not fits then
			action(row, misfit(gear), "off", function() end)
		elseif now == "installed" then
			action(row, "REMOVE", if here then "quiet" else "off", function()
				send("remove", gear.id)
			end)
		elseif now == "owned" then
			local free = used < slots
			action(row, if free then "INSTALL" else "NO FREE SLOT", if free and here then "primary" else "off", function()
				send("install", gear.id)
			end)
		elseif level < gear.level then
			action(row, `🔒 LEVEL {gear.level}`, "off", function() end)
		else
			action(row, `BUY {Ui.money(gear.price)}`, if here and money >= gear.price then "primary" else "off", function()
				send("buy", gear.id)
			end)
		end
	end
end

return GearShop
