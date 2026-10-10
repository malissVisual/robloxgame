--!strict
-- 6.18 wave 2, the shops' counters in the UI kit's look (the owner, after 6.17's JOBS: "I need it unified so the phone
-- looks like that, and the other popups too"). client/Hud.luau's shop window (its chrome: the shop's name, its glyph,
-- the footer with your money) calls ShopWindow.render for its body; what each counter sells is drawn by
-- client/ShopView.luau (a hero card, compact rows, the details on a tap):
--   dealer    Dead End Motors' CARS counter: the cars (a display car's "Look" is the hero: `focus`), YOUR CAR, IN GARAGE,
--             🔒 SOLD PRIVATELY (Earl's Old Van), the level, a campaign first, 🅿 NEEDS A GARAGE, BUY (the Buy remote)
--   guns      Lead & Co.'s range: tabs GUNS (EQUIP, IN HAND, STARTER, the earned and the reward guns last), UPGRADES
--             (the gun tracks: the Upgrade remote) and MELEE (the bat: client/KitShop.luau)
--   bikes     the BIKES counter: tabs BIKES (client/BikeShop.luau) and GEAR (client/GearShop.luau, the bike gear)
--   bags      ZDC Bags: the bags (client/KitShop.luau), YOUR ROOM a chip
--   supplies  Last Stop Supplies: tabs ITEMS (BUY 1 on the button, BUY 5 in the details; the car items once you own a
--             car) and KIT (client/KitShop.luau)
--   mechanic  Wrench Garage: tabs UPGRADES (your car's STAGE as the hero, its tracks), GEAR (client/GearShop.luau), PAINT
--             (APPLY, BUY; the reward paints last) and CAR GUNS (INSTALLED, CAN'T MOUNT, BUY)
-- The words that were notes are now a chip, one short line, or an item's details. Every action keeps its remote (Buy,
-- Equip, Upgrade, Paint, Kit, Gear) and the server checks everything again (server/Shops.luau). Presentation only;
-- moved out of Hud.luau (its 200-register limit) with the 3.x – 6.7 rules it kept (the stats words: carStats, gunStats).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Icons = require(Shared.Icons)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local CardKit = require(script.Parent.CardKit)
local ShopView = require(script.Parent.ShopView)
local KitShop = require(script.Parent.KitShop)
local GearShop = require(script.Parent.GearShop)
local BikeShop = require(script.Parent.BikeShop)

local C = CardKit.Color
local ShopWindow = {}

type Item = ShopView.Item
type Act = ShopView.Act

-- What Hud lends a render: the shop, the state, at the counter or not, your level, its window and its body.
export type Ctx = {
	shopId: string,
	focus: string?, -- a display car's / bike's id ("Look"), or a tab the phone asked for
	state: any,
	here: boolean,
	level: number,
	frame: Instance,
	body: Instance,
	toast: (text: string) -> (),
	redraw: () -> (),
	findEmployer: (id: string?) -> any,
	goal: string?, -- the savings goal's name (client/ReadyCheck.luau)
}

-- The open tabs (the guns' and Wrench Garage's; the bikes' and the supplies' are BikeShop.tab and KitShop.tab).
ShopWindow.gunTab = "guns"
ShopWindow.mechanicTab = "upgrades"

-- 3.5: with a car's own levels its stage's numbers (the stage's name first); without (the dealer's catalog) the room
-- it has from stage 0 to its last stage.
function ShopWindow.carStats(def: Config.CarDef, levels: { [string]: number }?): string
	if levels then
		local stats = Economy.carStats(def.id, levels)
		local stage = Economy.stageDef(def.id, Economy.stageOf(def.id, levels))
		local prefix = if stage and stage.name ~= def.name then `{stage.name} · ` else ""
		local pallets = Economy.palletsOf(def.id, Economy.stageOf(def.id, levels)) -- 4.0
		return `{prefix}Speed {math.floor(stats.maxSpeed + 0.5)} · Health {stats.health} · 📦 {Economy.capacity(def.id, levels)} slots{if pallets > 0 then ` · {pallets} pallet{if pallets > 1 then "s" else ""}` else ""}`
	end
	local most = Economy.maxCapacity(def.id)
	local pallets = Economy.palletsOf(def.id, Economy.maxStage(def.id)) -- 4.0: what it takes at its last stage
	return `Speed {def.maxSpeed} · Health {def.health} · Ram x{def.ramPower} · 📦 {if most > def.capacity then `{def.capacity} → {most}` else def.capacity} slots{if pallets > 0 then ` · {pallets} pallet{if pallets > 1 then "s" else ""}` else ""}`
end

-- Damage, rate, range (and pellets, blast) of a hand gun or a car gun.
function ShopWindow.gunStats(def: { damage: number, pellets: number, fireRate: number, range: number, splash: number }): string
	local pellets = if def.pellets > 1 then ` x{def.pellets}` else ""
	local splash = if def.splash > 0 then ` · Blast {def.splash}` else ""
	return `Damage {def.damage}{pellets} · {def.fireRate}/s · Range {def.range}{splash}`
end

-- A gun's one facts line: "💥 18 x6 · 2/s · ↔ 60".
function ShopWindow.gunFact(def: { damage: number, pellets: number, fireRate: number, range: number }): string
	return `💥 {def.damage}{if def.pellets > 1 then ` x{def.pellets}` else ""} · {def.fireRate}/s · ↔ {def.range}`
end

-- The cars a car gun fits on (CarDef.mount), by name.
local function mountableCars(): string
	local names = {}
	for _, def in Config.Cars do
		if def.mount then
			table.insert(names, def.name)
		end
	end
	return table.concat(names, ", ")
end

-- 3.1: how a reward is earned (Config.Rewards): its chip and its words.
local function rewardHow(exclusive: string): (string, string)
	if exclusive == "challenges" then
		return "???", "a secret reward"
	elseif exclusive == "secrets" then
		return "REWARD", "find every lost package"
	elseif exclusive == "career" then
		return "REWARD", "a career level (CAREER, C)" -- 4.6: Config.Levels.Rewards
	end
	for _, campaign in require(Shared.Missions).Campaigns do
		if campaign.id == exclusive then
			return "REWARD", `finish {campaign.name}`
		end
	end
	return "REWARD", "a reward"
end

-- 3.2: a def may need a campaign finished first (`requires`: a campaign id or a list of them; the server checks it
-- too). The first one not finished yet, as "Finish Iron Supply", else nil.
local function needs(state: any, def: any, owned: boolean): string?
	local list: any = def.requires
	if owned or list == nil then
		return nil
	end
	if type(list) == "string" then
		list = { list }
	end
	if type(list) ~= "table" then
		return nil
	end
	local Missions = require(Shared.Missions)
	for _, id in list do
		if type(id) ~= "string" or (type(state.campaigns) == "table" and state.campaigns[id] == true) then
			continue
		end
		local missions = Missions.ofCampaign(id)
		local finale = missions[#missions]
		if not (finale and type(state.missions) == "table" and state.missions[finale.id]) then
			local campaign = Missions.findCampaign(id)
			return `Finish {if campaign then campaign.name else id}`
		end
	end
	return nil
end

-- The shared shapes of an action: a grey one that only says (`why`), a level's lock, a campaign's, and BUY.
local function shut(text: string, why: string?): Act
	return { text = text, on = false, why = why }
end

local function levelLock(item: Item, level: number)
	item.lock = `🔒 LV {level}`
	item.act = shut(`🔒 LEVEL {level}`, `Opens at level {level}: deliveries give XP.`)
end

local function campaignLock(item: Item, need: string)
	item.lock = "🔒 STORY"
	item.act = shut(`🔒 {string.upper(need)}`, `{need} first: it opens with that campaign (MISSIONS, U).`)
end

local function buy(ctx: Ctx, name: string, price: number, fire: () -> (), text: string?, short: string?): Act
	local money = tonumber(ctx.state.money) or 0
	local why = if not ctx.here then "Walk into the shop to buy here."
		elseif money < price then `Not enough money: {name} costs {Ui.money(price)}.`
		else nil
	return { text = text or `BUY {Ui.money(price)}`, short = short, on = ctx.here and money >= price, why = why, run = fire }
end

-- A reward nobody can buy (3.1): gold, its chip as the lock, how to earn it.
local function rewardItem(item: Item, exclusive: string)
	local chip, how = rewardHow(exclusive)
	item.special = true
	item.price = nil
	item.lock = if chip == "???" then "??? SECRET" else "🏆 REWARD"
	item.act = shut(string.upper(how), `Never sold: {how}.`)
	table.insert(item.lines or {}, 1, `Never sold: {how}.`)
end

-- ── The counters ─────────────────────────────────────────────────────────────

local function dealer(ctx: Ctx): ({ Item }, string?)
	local state = ctx.state
	-- 3.4: every car you own takes a garage slot (the company vehicles none); a new one needs a free one.
	local owned = 0
	for id, yes in state.cars do
		local def = Economy.findCar(id)
		if yes and def and not def.company and not def.bike then -- (5.1: a bike needs no garage slot)
			owned += 1
		end
	end
	local Players = game:GetService("Players")
	local full = owned >= (tonumber(Players.LocalPlayer:GetAttribute("CarSlots")) or Config.Estate.BaseCarSlots)
	local items: { Item } = {}
	for _, def in Config.Cars do
		if def.company or def.bike then
			continue -- (5.1: the bikes are the BIKES counter's)
		end
		local mine = state.cars[def.id] == true
		local most = Economy.maxCapacity(def.id)
		local item: Item = {
			id = def.id,
			name = def.name,
			picture = ShopView.vehicle(def),
			fact = `📦 {if most > def.capacity then `{def.capacity}→{most}` else def.capacity} · ⚡ {def.maxSpeed} · ❤ {def.health}{if def.role then ` · {string.upper(def.role)}` else ""}`,
			price = def.price,
			forSale = true,
			current = def.id == ctx.focus,
			owned = mine,
			lines = { ShopWindow.carStats(def), def.description, "Every car builds up in stages at Wrench Garage (📦 from → to)." },
		}
		if def.role then
			table.insert(item.lines :: { string }, 2, `Role: {def.role}.`)
		end
		-- 5.0: the Old Van is sold privately (Config.VanQuest: Earl, Marge's quest), not here.
		local private = def.id == Config.VanQuest.Car and not mine
		local lock = if mine then nil elseif (def.level or 1) > ctx.level then (def.level or 1) else nil
		local need = needs(state, def, mine)
		if state.car == def.id then
			item.act = shut("YOUR CAR")
			item.fact = `✓ YOUR CAR · {item.fact}`
		elseif mine then
			item.act = shut("IN GARAGE", "Switch cars at one of your garages (🅿 GARAGE), or at the depot lot for your starting van.")
			item.fact = `✓ IN GARAGE · {item.fact}`
		elseif private then
			item.forSale = false
			item.lock = "🔒 EARL"
			item.act = shut("🔒 SOLD PRIVATELY", `{Config.VanQuest.DealerNote} {Config.VanQuest.Seller} sells it at {Config.VanQuest.Place}, far out west.`)
		elseif lock then
			levelLock(item, lock)
		elseif need then
			campaignLock(item, need)
		elseif full then
			item.act = shut("🅿 NEEDS A GARAGE", "No free garage slot. Buy or rent a garage (ESTATE, H) first.")
		else
			local id = def.id
			item.act = buy(ctx, def.name, def.price, function()
				Net.get("Buy"):FireServer("car", id)
			end)
		end
		table.insert(items, item)
	end
	return items, "Bikes: the BIKES counter next door (Kip)."
end

-- One hand gun (6.7: the starter pistol says STARTER; a reward says how to earn it).
local function gunItem(ctx: Ctx, def: Config.WeaponDef): Item
	local state = ctx.state
	local mine = state.weapons[def.id] == true
	local item: Item = {
		id = def.id,
		name = def.name,
		picture = { icon = Icons.weapon(def.id), emoji = "🔫" },
		fact = ShopWindow.gunFact(def) .. (if def.oneHanded then " · 1-HAND" else ""),
		price = if def.starter or Economy.rewardOnly(def) then nil else def.price,
		forSale = not def.starter and not Economy.rewardOnly(def),
		owned = mine,
		lines = { ShopWindow.gunStats(def) .. (if def.pierce then ` · Pierces {def.pierce}` else "") .. (if def.oneHanded then " · One-handed: it fires out of a car window too" else ""), def.description },
	}
	local exclusive = def.exclusive
	if exclusive and exclusive == "challenges" and not mine then
		-- The gun nobody else has: nothing given away.
		item.name = "???"
		item.picture = { emoji = "❔" }
		item.fact = "💥 ??? · ???/s · ↔ ???"
		item.lines = { "Nobody has ever seen it. Some say it waits for the courier who does everything." }
	end
	local lock = if mine or Economy.rewardOnly(def) or def.starter then nil elseif (def.level or 1) > ctx.level then (def.level or 1) else nil
	local need = if Economy.rewardOnly(def) then nil else needs(state, def, mine)
	if exclusive and mine then
		item.special = true
		item.ribbon = "★ EXCLUSIVE"
	end
	if exclusive and not mine then
		rewardItem(item, exclusive)
	elseif state.weapon == def.id then
		item.act = shut("IN HAND")
		item.fact = `✓ IN HAND · {item.fact}`
	elseif mine then
		local id = def.id
		item.act = { text = "EQUIP", short = "EQUIP", on = true, kind = "good", run = function()
			Net.get("Equip"):FireServer("weapon", id)
		end }
		item.fact = `✓ OWNED · {item.fact}`
	elseif def.earned then
		-- Not for sale: you earn it by working.
		local employer = ctx.findEmployer(def.earned)
		item.lock = "🔒 WORK"
		item.act = shut(`EARNED AT {string.upper(if employer then employer.name else def.earned)}`, `Not for sale: work for {if employer then employer.name else def.earned} to earn it.`)
	elseif def.starter then
		item.act = shut("STARTER") -- 6.7: never sold (the server gives a missing one back)
	elseif lock then
		levelLock(item, lock)
	elseif need then
		campaignLock(item, need)
	else
		local id = def.id
		item.act = buy(ctx, def.name, def.price, function()
			Net.get("Buy"):FireServer("weapon", id)
		end)
	end
	return item
end

-- A gun or car track of Config.Upgrades (its level's pips, UPGRADE $X, MAX).
local function trackItem(ctx: Ctx, def: Config.UpgradeDef, levels: { [string]: number }, blocked: string?): Item
	local level = Economy.level(levels, def.id)
	local cost = Economy.upgradeCost(def.id, level)
	local item: Item = {
		id = `up_{def.id}`,
		name = def.name,
		picture = { emoji = if def.car then "🔧" else "⬆️" },
		fact = string.rep("■", level) .. string.rep("□", def.maxLevel - level) .. `  LV {level}/{def.maxLevel}`,
		price = cost,
		value = if cost then nil else "MAX",
		valueColor = if cost then nil else C.gold,
		forSale = cost ~= nil and blocked == nil,
		lines = { def.description },
	}
	if blocked then
		item.act = shut(blocked)
	elseif cost then
		local id = def.id
		item.act = buy(ctx, def.name, cost, function()
			Net.get("Upgrade"):FireServer(id)
		end, `UPGRADE {Ui.money(cost)}`, "UP")
	else
		item.act = shut("MAX")
	end
	return item
end

local function guns(ctx: Ctx): ({ Item }, string?)
	local state = ctx.state
	local items: { Item } = {}
	if ShopWindow.gunTab == "upgrades" then
		for _, def in Config.Upgrades do
			if not def.car then
				table.insert(items, trackItem(ctx, def, state.upgrades, nil)) -- (the car tracks: Wrench Garage)
			end
		end
		return items, "Every gun you own, the car guns too."
	elseif ShopWindow.gunTab == "melee" then
		return KitShop.items(state, ctx.here, "guns"), "Melee: when the gun is away (fists or the bag), V."
	end
	-- The guns for sale (the starter first), then the earned and the reward-only ones (last: locked).
	for _, def in Config.Weapons do
		table.insert(items, gunItem(ctx, def))
	end
	return items, "One-handed guns fire out of a car window too. Try them on the lanes outside."
end

local function supplies(ctx: Ctx): ({ Item }, string?)
	local state = ctx.state
	if KitShop.currentTab(state) == "kit" then
		return KitShop.items(state, ctx.here, "supplies"), nil
	end
	local items: { Item } = {}
	local money = tonumber(state.money) or 0
	for _, def in Config.Items do
		-- 6.7: the car-only items once you own a car (Economy.itemShown; the server sells them only then)
		if not Economy.itemShown(def, state.cars) then
			continue
		end
		local have = state.items[def.id] or 0
		local id = def.id
		local one = buy(ctx, def.name, def.price, function()
			Net.get("Buy"):FireServer("item", id, 1)
		end, `BUY 1  {Ui.money(def.price)}`)
		if have >= def.max then
			one = shut("FULL", `You carry the most: {def.max}.`)
		end
		local five: Act = {
			text = `BUY 5  {Ui.money(def.price * 5)}`,
			on = ctx.here and money >= def.price * 5 and have + 5 <= def.max,
			why = if have + 5 > def.max then `You carry at most {def.max}.` else (one.why or `Not enough money for 5: {Ui.money(def.price * 5)}.`),
			run = function()
				Net.get("Buy"):FireServer("item", id, 5)
			end,
			name = "BuyFive",
		}
		table.insert(items, {
			id = def.id,
			name = def.name,
			picture = { icon = Icons.item(def.id), emoji = def.icon },
			fact = `×{have} of {def.max} · {Ui.money(def.price)} each`,
			price = def.price,
			forSale = true,
			act = one,
			more = { five },
			lines = { def.description, `You have {have} (at most {def.max}).` },
		})
	end
	return items, if Economy.ownsCar(state.cars) then nil else "Car items show here once you own a car."
end

local function mechanic(ctx: Ctx): ({ Item }, string?, string?, { CardKit.Chip }?)
	local state = ctx.state
	local tab = ShopWindow.mechanicTab
	if tab == "gear" then
		local items, chip, note = GearShop.items(state, ctx.here, false, nil)
		return items, nil, note, if chip then { chip } else nil -- 4.6: the car's gear and its slots
	end
	local carDef = Economy.findCar(state.car)
	local items: { Item } = {}
	if tab == "carguns" then
		-- One gun on the roof of the car you have equipped; the driver fires it.
		local canMount = carDef ~= nil and carDef.mount == true
		local carGuns = state.carGuns or {}
		local installed: string? = if canMount then carGuns[state.car] else nil
		for _, def in Config.CarGuns do
			local lock = if installed == def.id or (def.level or 1) <= ctx.level then nil else (def.level or 1)
			local need = needs(state, def, installed == def.id)
			local item: Item = {
				id = def.id,
				name = def.name,
				picture = { emoji = "🔫" },
				fact = ShopWindow.gunFact(def),
				price = def.price,
				forSale = canMount,
				current = installed == def.id,
				owned = installed == def.id,
				lines = { ShopWindow.gunStats(def), def.description, "On the roof; the driver fires it. A new one replaces the old one (no refund)." },
			}
			if installed == def.id then
				item.act = shut("INSTALLED")
			elseif not canMount then
				item.act = shut("CAN'T MOUNT", `This vehicle can't carry a gun. Car guns fit: {mountableCars()}.`)
			elseif lock then
				levelLock(item, lock)
			elseif need then
				campaignLock(item, need)
			else
				local id = def.id
				item.act = buy(ctx, def.name, def.price, function()
					Net.get("Buy"):FireServer("cargun", id)
				end)
			end
			table.insert(items, item)
		end
		local carName = if carDef then carDef.name else "car"
		return items, nil, if canMount then nil else `Your {carName} can't carry a gun.`, { { name = "CarChip", text = `🔫 {string.upper(carName)}`, static = true } }
	elseif tab == "paint" then
		local current = state.carPaint[state.car] or "factory"
		for _, def in Config.Paints do
			local swatch = if def.color then Color3.fromRGB(def.color[1], def.color[2], def.color[3]) elseif carDef then Color3.fromRGB(carDef.color[1], carDef.color[2], carDef.color[3]) else C.grey
			local mine = state.paints[def.id] == true
			local item: Item = {
				id = `paint_{def.id}`,
				name = def.name,
				picture = { emoji = "🎨", face = swatch },
				fact = (if mine then "✓ OWNED" elseif def.exclusive then "NEVER SOLD" else "PAINT") .. (if def.material then ` · {string.upper(def.material)}` else ""),
				price = if mine or def.exclusive then nil else def.price,
				forSale = not def.exclusive,
				owned = mine,
				lines = { "Bought paints are yours for every car." },
			}
			local id = def.id
			local exclusive = def.exclusive
			if exclusive and mine then
				item.special = true
				item.ribbon = "★ EXCLUSIVE"
			end
			if exclusive and not mine then
				rewardItem(item, exclusive)
			elseif current == def.id then
				item.act = shut("ON YOUR CAR")
				item.fact = `✓ ON YOUR CAR{if def.material then ` · {string.upper(def.material)}` else ""}`
			elseif mine then
				item.act = { text = "APPLY", short = "APPLY", on = ctx.here, kind = "good", why = "Walk into the shop to paint here.", run = function()
					Net.get("Paint"):FireServer(id)
				end }
			else
				item.act = buy(ctx, def.name, def.price, function()
					Net.get("Paint"):FireServer(id)
				end)
			end
			table.insert(items, item)
		end
		return items, nil, nil, { { name = "CarChip", text = `🎨 {string.upper(if carDef then carDef.name else "car")}`, static = true } }
	end
	-- UPGRADES: 3.3: the car tracks belong to the equipped car (its own levels, shown on it); the gun tracks to every gun.
	local carOk = carDef ~= nil and Economy.canUpgrade(carDef.id)
	local carLevels = Economy.carLevels(state.carUpgrades, state.car)
	local note: string? = nil
	if not carOk then
		-- 5.0: on foot, no vehicle yet
		note = if carDef then `Your {carDef.name} is a company vehicle: it can't be upgraded.` else `No vehicle yet: the Old Van comes from {Config.VanQuest.Where}.`
	end
	-- 3.5: the STAGE: the car's next stage (its new look, its room, before → after) or its last one.
	if carOk and carDef and Economy.maxStage(carDef.id) > 0 then
		local stage = Economy.stageOf(carDef.id, carLevels)
		local last = Economy.maxStage(carDef.id)
		local now = Economy.stageDef(carDef.id, stage)
		local nextStage = Economy.stageDef(carDef.id, stage + 1)
		local pips = string.rep("■", stage) .. string.rep("□", last - stage)
		local nowName = if now then now.name else carDef.name
		local item: Item = {
			id = "stage",
			name = if nextStage then `STAGE {stage + 1}/{last}: {nextStage.name}` else `STAGE {stage}/{last}: {nowName}`,
			picture = ShopView.vehicle(carDef),
			fact = `{pips}  📦 {Economy.capacity(carDef.id, carLevels)}{if nextStage then ` → {nextStage.capacity}` else ""}`,
			current = true,
			forSale = nextStage ~= nil,
		}
		if nextStage then
			local after = table.clone(carLevels)
			after.stage = stage + 1
			local a, b = Economy.carStats(carDef.id, carLevels), Economy.carStats(carDef.id, after)
			item.price = nextStage.price
			item.lines = { `{nowName} → {nextStage.name}: adds {nextStage.adds}.`, `📦 {Economy.capacity(carDef.id, carLevels)} → {nextStage.capacity} slots · Health {a.health} → {b.health} · Speed {math.floor(a.maxSpeed + 0.5)} → {math.floor(b.maxSpeed + 0.5)}` }
			if (nextStage.level or 1) > ctx.level then
				levelLock(item, nextStage.level or 1)
			else
				item.act = buy(ctx, nextStage.name, nextStage.price, function()
					Net.get("Upgrade"):FireServer("stage")
				end, `STAGE UP {Ui.money(nextStage.price)}`, "UP")
			end
		else
			item.value = "MAX"
			item.valueColor = C.gold
			item.lines = { `Your {carDef.name} is all it can be. More room needs a bigger vehicle (Dead End Motors).` }
			item.act = shut("LAST STAGE")
		end
		table.insert(items, item)
	end
	for _, def in Config.Upgrades do
		if not def.car then
			continue -- (6.7: the gun tracks are sold at Lead & Co.)
		end
		local blocked = if not carOk then "COMPANY CAR" elseif not Economy.upgradeFits(state.car, def.id) then "VANS & TRUCKS" else nil -- 4.0: the Hand Trolley
		table.insert(items, trackItem(ctx, def, carLevels, blocked))
	end
	local chips: { CardKit.Chip }? = if carOk then { { name = "CarChip", text = `🚐 {string.upper(Economy.carTitle(state.car, carLevels))} · 📦 {Economy.capacity(state.car, carLevels)}`, static = true } } else nil
	return items, "Repairs: drive into a repair bay here, get out and wait.", note, chips
end

-- ── The window's body ───────────────────────────────────────────────────────

local TABS: { [string]: { { string } } } = {
	guns = { { "guns", "GUNS" }, { "upgrades", "UPGRADES" }, { "melee", "MELEE" } },
	bikes = { { "bikes", "BIKES" }, { "gear", "GEAR" } },
	supplies = { { "items", "ITEMS" }, { "kit", "KIT" } },
	mechanic = { { "upgrades", "UPGRADES" }, { "gear", "GEAR" }, { "paint", "PAINT" }, { "carguns", "CAR GUNS" } },
}

local function currentTab(ctx: Ctx): string?
	local id = ctx.shopId
	if id == "guns" then
		return ShopWindow.gunTab
	elseif id == "bikes" then
		return BikeShop.tab
	elseif id == "supplies" then
		return KitShop.currentTab(ctx.state)
	elseif id == "mechanic" then
		return ShopWindow.mechanicTab
	end
	return nil
end

local function pickTab(ctx: Ctx, tab: string)
	local id = ctx.shopId
	if id == "guns" then
		ShopWindow.gunTab = tab
	elseif id == "bikes" then
		BikeShop.tab = tab
	elseif id == "supplies" then
		KitShop.tab = tab
	elseif id == "mechanic" then
		ShopWindow.mechanicTab = tab
	end
	ShopView.home(`shop:{id}`)
	ctx.redraw()
end

-- Draws the counter `ctx.shopId` into `ctx.body` (Hud cleared it). Returns the gamepad's first stop.
function ShopWindow.render(ctx: Ctx): any
	local state = ctx.state
	local id = ctx.shopId
	local items: { Item } = {}
	local foot: string? = nil
	local note: string? = nil
	local chips: { CardKit.Chip }? = nil
	if id == "dealer" then
		items, foot = dealer(ctx)
	elseif id == "guns" then
		items, foot = guns(ctx)
	elseif id == "bikes" then
		if BikeShop.tab == "gear" then
			local chip
			items, chip, note = GearShop.items(state, ctx.here, true, BikeShop.mine(state))
			chips = if chip then { chip } else nil
		else
			local chip
			items, chip = BikeShop.items(state, ctx.here, ctx.focus)
			chips = { chip }
		end
	elseif id == "bags" then
		items = KitShop.items(state, ctx.here, "bags")
		chips = { KitShop.roomChip(state) }
		foot = "One bag at a time: the one IN USE counts. Bought once, kept for good."
	elseif id == "supplies" then
		items, foot = supplies(ctx)
		if KitShop.currentTab(state) == "kit" then
			chips = { KitShop.roomChip(state) }
		end
	elseif id == "mechanic" then
		items, foot, note, chips = mechanic(ctx)
	end
	local money = tonumber(state.money) or 0
	local allChips: { CardKit.Chip } = { { name = "CashChip", text = Ui.money(money), ink = C.money, face = C.goodFace, static = true } }
	local extra: { CardKit.Chip } = chips or {}
	for _, chip in extra do
		table.insert(allChips, chip)
	end
	local tabs = TABS[id]
	local size = ShopView.measure(ctx.body, Vector2.new(640, 420))
	return ShopView.draw(ctx.body, {
		key = `shop:{id}`,
		items = items,
		money = money,
		goal = ctx.goal,
		side = CardKit.Layout.side(size.X),
		room = size.Y,
		order = 0,
		tabs = if tabs then { tabs = tabs, selected = currentTab(ctx) or tabs[1][1], onPick = function(tab: string)
			pickTab(ctx, tab)
		end } else nil,
		chips = allChips,
		note = if not ctx.here then "Walk into the shop to buy here." else note,
		noteColor = if not ctx.here then CardKit.Color.runInk else nil,
		section = nil,
		foot = foot,
		redraw = ctx.redraw,
		toast = ctx.toast,
	})
end

return ShopWindow
