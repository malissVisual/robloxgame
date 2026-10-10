--!strict
-- 5.1: Spoke & Chain's shop window (6.12.7: Dead End Motors' BIKES counter's; the shop window in client/Hud.luau
-- draws it with BikeShop.render under its tabs BIKES and GEAR; the counter's prompt, a display bike's "Look" and the
-- phone's SHOP app open it). The bikes are
-- Config.Cars entries with bike = true; the bike gear is Config.Gear bikeOnly (client/GearShop.luau draws it for your
-- bike). Presentation only: the server checks everything again (server/Shops.luau: "Buy" "car", "Equip" "bike",
-- "Gear").
--
-- BIKES: on top YOUR BIKE (the bike of choice, what it holds with its gear and your bag: shared/Transport.luau,
-- and whether you ride it or your car is the one you drive), then every bike as a slim contract row: its picture
-- (shared/Icons.luau Icons.bike, the emoji until uploaded), its name, level, price, speed, room and gear slots, what
-- it is, and the one action that fits: BUY (at the counter, from its level, with the money), EQUIP (an owned bike that
-- is not your bike of choice), YOUR BIKE, or a dim "🔒 LEVEL n". BikeShop.tab is its only state.
-- 5.1.1: a bike's badge (CarDef.badge: the E-Scooter's "⚡ ELECTRIC · STAND-UP") after its name; a standing one
-- (CarDef.stand) shows 🛴 until its picture is uploaded.
-- 5.8, the courier phone's look: YOUR BIKE is the phone's card (the red square and caps, the bike in big type, a thin
-- rule under it); BUY and EQUIP are the phone's red primary.
-- 6.18 wave 2, the UI kit (design/ui-kit/README.md): BikeShop.items gives the bikes to client/ShopView.luau and YOUR
-- BIKE is a chip; client/ShopWindow.luau draws the counter (its GEAR tab: client/GearShop.luau items, forBike).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Transport = require(Shared.Transport)
local Ui = require(script.Parent.Ui)
local CardKit = require(script.Parent.CardKit)
local ShopView = require(script.Parent.ShopView)

local BikeShop = {}

-- The window's open tab ("bikes" | "gear").
BikeShop.tab = "bikes"

local player = Players.LocalPlayer

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

-- What your bike holds with its gear and your bag (Transport mode "bike").
function BikeShop.room(state: any, bikeId: string): number
	local kit = if type(state.kit) == "table" then state.kit else {}
	return Transport.bike(Transport.bikeRoom(bikeId, if type(state.carGear) == "table" then state.carGear else nil), kit).room
end

-- 6.18 wave 2: the BIKES tab as items for client/ShopView.luau (the bike's picture, its name and badge, speed and room
-- in one line, the price big, the one action: BUY, EQUIP, YOUR BIKE, a level's lock; what it is on a tap; a display
-- bike's "Look" (`focus`) or your bike of choice is the hero) and YOUR BIKE as a chip ("🚲 CITY BIKE · 4 LIGHT").
function BikeShop.items(state: any, here: boolean, focus: string?): ({ ShopView.Item }, CardKit.Chip)
	local level = myLevel(state)
	local money = tonumber(state.money) or 0
	local mine = BikeShop.mine(state)
	local riding = type(state.car) == "string" and Transport.isBike(state.car)
	local out: { ShopView.Item } = {}
	local chip: CardKit.Chip = { name = "BikeChip", text = `🚲 NO BIKE YET · LV {Config.Jobs.Bike.Level}`, static = true }
	for _, def in BikeShop.bikes() do
		local owned = type(state.cars) == "table" and state.cars[def.id] == true
		local lvl = def.level or 1
		local id = def.id
		local item: ShopView.Item = {
			id = def.id,
			name = def.name,
			picture = ShopView.vehicle(def),
			fact = `⚡ {def.maxSpeed} · 📦 {def.capacity} · ⚙ {def.gearSlots or 0}{if def.badge then ` · {def.badge}` else ""}`,
			price = if owned then nil else def.price,
			forSale = not owned,
			owned = owned,
			current = def.id == focus,
			lines = { def.description, "Its own bag (a rack, a basket or a box + its gear) and your bag: light pieces only. No garage needed: MY BIKE brings it at once." },
		}
		if owned and def.id == mine then
			local room = BikeShop.room(state, def.id)
			chip.text = `🚲 {string.upper(def.name)} · {room} LIGHT{if riding then " · RIDING" else ""}`
			item.act = { text = "YOUR BIKE", on = false }
			item.fact = `✓ YOUR BIKE · {item.fact}`
			item.current = focus == nil or def.id == focus
		elseif owned then
			item.act = { text = "EQUIP", short = "EQUIP", on = true, kind = "good", run = function()
				Net.get("Equip"):FireServer("bike", id)
			end }
			item.fact = `✓ OWNED · {item.fact}`
		elseif level < lvl then
			item.lock = `🔒 LV {lvl}`
			item.act = { text = `🔒 LEVEL {lvl}`, on = false, why = `Opens at level {lvl}: deliveries give XP.` }
		else
			item.act = {
				text = `BUY {Ui.money(def.price)}`,
				on = here and money >= def.price,
				why = if not here then "Walk into the shop to buy here." else `Not enough money: {def.name} costs {Ui.money(def.price)}.`,
				run = function()
					Net.get("Buy"):FireServer("car", id)
				end,
			}
		end
		table.insert(out, item)
	end
	-- (one hero: a display bike's Look before your own bike)
	if focus then
		for _, item in out do
			if item.id ~= focus then
				item.current = nil
			end
		end
	end
	return out, chip
end

return BikeShop
