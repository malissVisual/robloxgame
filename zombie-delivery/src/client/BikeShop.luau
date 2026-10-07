--!strict
-- 5.1: Spoke & Chain's shop window (the shop window in client/Hud.luau draws it with BikeShop.render under its tabs
-- BIKES and GEAR; the counter's prompt, a display bike's "Look" and the phone's SHOP app open it). The bikes are
-- Config.Cars entries with bike = true; the bike gear is Config.Gear bikeOnly (client/GearShop.luau draws it for your
-- bike). Presentation only: the server checks everything again (server/Shops.luau: "Buy" "car", "Equip" "bike",
-- "Gear").
--
-- BIKES: on top YOUR BIKE (the bike of choice, what it holds with its gear and your backpack: shared/Transport.luau,
-- and whether you ride it or your car is the one you drive), then every bike as a slim contract row: its picture
-- (shared/Icons.luau Icons.bike, the emoji until uploaded), its name, level, price, speed, room and gear slots, what
-- it is, and the one action that fits: BUY (at the counter, from its level, with the money), EQUIP (an owned bike that
-- is not your bike of choice), YOUR BIKE, or a dim "🔒 LEVEL n". BikeShop.tab is its only state.
-- 5.1.1: a bike's badge (CarDef.badge: the E-Scooter's "⚡ ELECTRIC · STAND-UP") after its name; a standing one
-- (CarDef.stand) shows 🛴 until its picture is uploaded.
-- 5.8, the courier phone's look: YOUR BIKE is the phone's card (the red square and caps, the bike in big type, a thin
-- rule under it); BUY and EQUIP are the phone's red primary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Transport = require(Shared.Transport)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local GearShop = require(script.Parent.GearShop)

local BikeShop = {}

-- The window's open tab ("bikes" | "gear").
BikeShop.tab = "bikes"

local player = Players.LocalPlayer
local ROW_H = 96
local BUTTON_W = 150

local function myLevel(state: any): number
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and type(state.xp) == "number" then
		xp = state.xp
	end
	return Levels.levelFor(xp or 0)
end

-- The bikes of Config.Cars, in their order.
function BikeShop.bikes(): { Config.CarDef }
	local list: { Config.CarDef } = {}
	for _, def in Config.Cars do
		if def.bike then
			table.insert(list, def)
		end
	end
	return list
end

-- Your bike of choice in the state (the one you ride, else state.bike while you own it, else your first bike).
function BikeShop.mine(state: any): string?
	if not state or type(state.cars) ~= "table" then
		return nil
	end
	if type(state.car) == "string" and Transport.isBike(state.car) then
		return state.car
	end
	if type(state.bike) == "string" and state.cars[state.bike] and Transport.isBike(state.bike) then
		return state.bike
	end
	for _, def in BikeShop.bikes() do
		if state.cars[def.id] then
			return def.id
		end
	end
	return nil
end

-- What your bike holds with its gear and your backpack (Transport mode "bike").
function BikeShop.room(state: any, bikeId: string): number
	local kit = if type(state.kit) == "table" then state.kit else {}
	return Transport.bike(Transport.bikeRoom(bikeId, if type(state.carGear) == "table" then state.carGear else nil), kit).room
end

local function action(row: any, text: string, kind: P.ButtonKind, onClick: () -> ())
	local button = P.button(row, text, UDim2.fromOffset(BUTTON_W, 40), kind, if kind == "off" then function() end else onClick)
	button.Position = UDim2.new(1, -BUTTON_W - 12, 0.5, -20)
	button.TextSize = 14
	return button
end

-- 5.8, the courier phone's tag line (design/phone-ui/): the small red square and the caps label, over a head.
local function tagLine(parent: Instance, text: string, order: number): any
	local row = Ui.make("Frame", { Name = "Tag", Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	P.marker(row, 8, { Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5) })
	P.caps(row, text, UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(16, 0), TextStrokeTransparency = 1 })
	return row
end

-- YOUR BIKE: the head of the BIKES tab.
local function head(body: Instance, state: any)
	local box = Ui.make("Frame", { Name = "YourBike", Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, body)
	Ui.list(box, true, 4)
	local mine = BikeShop.mine(state)
	local def: Config.CarDef? = nil
	for _, bike in BikeShop.bikes() do
		if bike.id == mine then
			def = bike
		end
	end
	tagLine(box, if def then "Your bike" else "Bikes · light runs, faster", 1)
	local riding = type(state.car) == "string" and Transport.isBike(state.car)
	local line: string
	if def then
		local room = BikeShop.room(state, def.id)
		line = `🚲 {string.upper(def.name)} · {room} LIGHT {if room == 1 then "PIECE" else "PIECES"}{if riding then " · RIDING" else ""}`
	else
		line = `🚲 NO BIKE YET · FROM LEVEL {Config.Jobs.Bike.Level}`
	end
	P.text(box, line, UDim2.new(1, 0, 0, 30), { Font = Theme.DisplayFont, TextSize = 22, TextStrokeTransparency = 1, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	local about = if def and not riding and type(state.car) == "string"
		then "Your car is the one you drive now: MY BIKE on your phone gets you on the bike (CALL CAR brings the car back)."
		elseif def then "Its room is its own + its bike gear (the GEAR tab) + your backpack: the hands hold nothing while you ride. Light pieces only. It needs no garage and comes to you at once (MY BIKE)."
		else "A bike is faster than walking and carries more: its room, a basket or panniers, and your backpack. It opens the BIKE runs on the board. No garage needed."
	Ui.label(box, about, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, TextColor3 = P.ink2, TextSize = 14, Font = Theme.Font })
	P.rule(box, UDim2.new(1, 0, 0, 1), { LayoutOrder = 4 })
end

-- The BIKES tab.
local function bikesTab(body: Instance, state: any, here: boolean, focus: string?)
	head(body, state)
	local level = myLevel(state)
	local money = tonumber(state.money) or 0
	local mine = BikeShop.mine(state)
	local list = BikeShop.bikes()
	if #list == 0 then
		Ui.label(body, "The bikes are on their way from the warehouse. Come back soon.", UDim2.new(1, -12, 0, 30), { LayoutOrder = 3, TextColor3 = P.ink2, TextSize = 14, Font = Theme.Font })
		return
	end
	for order, def in list do
		local owned = type(state.cars) == "table" and state.cars[def.id] == true
		local row = P.row(body, ROW_H, order + 2, def.id == mine or def.id == focus)
		Ui.icon(row, Icons.bike(def.id), if def.stand then "🛴" else "🚲", UDim2.fromOffset(44, 44), {
			Position = UDim2.fromOffset(12, ROW_H / 2 - 22),
			ImageColor3 = P.ink,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local left = 66
		local width = UDim2.new(1, -(left + BUTTON_W + 24), 0, 22)
		local badge = if def.badge then `  <font size="12" color="{P.hex(P.warn)}">{def.badge}</font>` else ""
		Ui.label(row, def.name .. badge, width, { Position = UDim2.fromOffset(left, 8), TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink, RichText = true, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local lvl = def.level or 1
		local status = if owned then `<font color="{P.hex(P.good)}">✓ OWNED</font>`
			elseif level < lvl then `<font color="{P.hex(P.warn)}">LEVEL {lvl}</font>`
			else `{def.gearSlots or 0} GEAR {if (def.gearSlots or 0) == 1 then "SLOT" else "SLOTS"}`
		Ui.label(row, `Level {lvl} · {Ui.money(def.price)} · Speed {def.maxSpeed} · 📦 {def.capacity} · {status}`, UDim2.new(1, -(left + BUTTON_W + 24), 0, 18), {
			Position = UDim2.fromOffset(left, 32),
			TextSize = 13,
			Font = Theme.HeadingFont,
			TextColor3 = P.ink2,
			RichText = true,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Ui.label(row, def.description, UDim2.new(1, -(left + BUTTON_W + 24), 0, 36), { Position = UDim2.fromOffset(left, 52), TextSize = 13, Font = Theme.Font, TextColor3 = P.ink2, TextYAlignment = Enum.TextYAlignment.Top })
		if owned and def.id == mine then
			action(row, "YOUR BIKE", "off", function() end)
		elseif owned then
			action(row, "EQUIP", "primary", function()
				Net.get("Equip"):FireServer("bike", def.id)
			end)
		elseif level < lvl then
			action(row, `🔒 LEVEL {lvl}`, "off", function() end)
		else
			action(row, `BUY {Ui.money(def.price)}`, if here and money >= def.price then "primary" else "off", function()
				Net.get("Buy"):FireServer("car", def.id)
			end)
		end
	end
end

-- Draws the open tab into `body` (the shop's scrolling body, a vertical list; Hud clears it and puts the tabs at
-- LayoutOrder 0 first). `here`: at the counter (only there BUY and the gear work). `focus`: a bike id to mark (a
-- display bike's "Look").
function BikeShop.render(body: Instance, state: any, here: boolean, focus: string?)
	if BikeShop.tab == "gear" then
		GearShop.render(body, state, here, true, BikeShop.mine(state))
		return
	end
	bikesTab(body, state, here, focus)
end

return BikeShop
