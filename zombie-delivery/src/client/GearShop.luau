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
-- 6.18 wave 2, the UI kit (design/ui-kit/README.md): GearShop.items gives the pieces to client/ShopView.luau (the
-- icon, the name, INSTALLED / OWNED / its level in one line, the price big, the one action: BUY, INSTALL, REMOVE; the
-- description on a tap) and the slots as a chip; client/ShopWindow.luau draws them at Wrench Garage and the BIKES counter.

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
local CardKit = require(script.Parent.CardKit)
local ShopView = require(script.Parent.ShopView)

local GearShop = {}

local player = Players.LocalPlayer

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

-- Why a piece does not fit a car, in a few words (the button).
local function misfit(gear: Config.GearDef): string
	if gear.bikeOnly then
		return "NOT ON THIS BIKE" -- 5.1: the trailer and the Cargo Bike
	elseif gear.needs == "trolley" then
		return "VANS & TRUCKS"
	end
	return "NOT ON THIS CAR"
end

-- The gear of a vehicle as items for client/ShopView.luau (6.18 wave 2), the vehicle's slots as a chip ("⚙ SLOTS 1 / 2")
-- and, with no gear to show (no vehicle, no bike, the wrong counter, a company vehicle), the note that says so instead.
-- `here`: at the counter (only there the actions work). 5.1: `forBike` (the BIKES counter): the bike gear of `bikeId`.
function GearShop.items(state: any, here: boolean, forBike: boolean?, bikeId: string?): ({ ShopView.Item }, CardKit.Chip?, string?)
	local vehicleId: string? = if forBike then bikeId elseif type(state.car) == "string" then state.car else nil
	if vehicleId == nil then
		-- 5.0: you start on foot: no car, no gear to show (not the van's list with BUY buttons).
		if forBike then
			return {}, nil, "Bike gear goes on a bike of your own: buy one in the BIKES tab first."
		end
		return {}, nil, `Gear goes on a car of your own. Your first one: the Old Van from {Config.VanQuest.Where}.`
	end
	if not forBike and Transport.isBike(vehicleId) then
		return {}, nil, "You ride your bike: bike gear is at Dead End Motors' BIKES counter. CALL CAR for your car's gear."
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
	local chip: CardKit.Chip = { name = "SlotsChip", text = if company then "⚙ COMPANY VEHICLE" else `⚙ SLOTS {used} / {slots}`, static = true }
	local note = if company then "A company vehicle comes with what its job needs: no gear slots." else nil
	local out: { ShopView.Item } = {}
	for _, gear in Config.Gear do
		if (gear.bikeOnly == true) ~= (forBike == true) then
			continue -- (5.1: the bike gear at the BIKES counter, the car gear at Wrench Garage)
		end
		local now = Economy.gearState(carGear, carId, gear.id)
		local fits = not company and Economy.gearFits(carId, gear.id)
		local id = gear.id
		local item: ShopView.Item = {
			id = gear.id,
			name = gear.name,
			picture = { icon = Icons.gear(gear.id), emoji = gear.icon },
			fact = if now == "installed" then "✓ INSTALLED" elseif now == "owned" then "✓ OWNED · NOT INSTALLED" else `LV {gear.level} · ⚙ 1 SLOT`,
			price = if now == nil or now == "none" then gear.price else nil,
			forSale = fits and (now == nil or now == "none"),
			owned = now == "installed" or now == "owned",
			lines = { gear.description, "Buy a piece once for this vehicle, then install or remove it here for free. Each piece takes one gear slot." },
		}
		if company then
			item.act = { text = "COMPANY CAR", on = false }
		elseif not fits then
			item.act = { text = misfit(gear), on = false }
		elseif now == "installed" then
			item.act = { text = "REMOVE", short = "OFF", on = here, kind = "warn", why = "Walk into the shop to fit gear here.", run = function()
				send("remove", id)
			end }
		elseif now == "owned" then
			local free = used < slots
			item.act = { text = if free then "INSTALL" else "NO FREE SLOT", short = "FIT", on = free and here, kind = "good", why = if free then "Walk into the shop to fit gear here." else "No free gear slot: REMOVE a piece first.", run = function()
				send("install", id)
			end }
		elseif level < gear.level then
			item.lock = `🔒 LV {gear.level}`
			item.act = { text = `🔒 LEVEL {gear.level}`, on = false, why = `Opens at level {gear.level}: deliveries give XP.` }
		else
			item.act = {
				text = `BUY {Ui.money(gear.price)}`,
				on = here and money >= gear.price,
				why = if not here then "Walk into the shop to buy here." else `Not enough money: {gear.name} costs {Ui.money(gear.price)}.`,
				run = function()
					send("buy", id)
				end,
			}
		end
		table.insert(out, item)
	end
	return out, chip, note
end

return GearShop
