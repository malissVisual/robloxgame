--!strict
-- 6.14, get ready for the mission (the owner: "You and a friend do delivery jobs, and zombies and bandits try to stop
-- you. It should feel like 'okay, let's go get ready for that mission'. Jobs are just the obvious daily work: you grind,
-- then you save up for something, and then you can progress in the mission."). Pure Luau (no Roblox services):
-- tests/readiness_test.luau; client/ReadyCheck.luau fills the input and draws the answers.
--
-- Readiness.evaluate(input) reads what the client knows (the State remote: money, cars, the car, its stage and gear,
-- the items, the kit, the guns, the van quest; the Missions remote's state: the progress, the crew; the XP; Marge's
-- tutorial) and answers three questions:
--   * Which mission is next (Readiness.nextMission): the first story chapter not finished (Missions.Campaigns' order,
--     the DUO side story left out) and its next mission (Missions.nextUp): where the MISSIONS window opens, and one
--     step further when that chapter waits for a level (the window still shows the finished one then). With every story
--     chapter done: the DUO chapter's next; with that done too, the first mission short of ★★★ (a replay for stars);
--     nil when every star is yours.
--   * What it needs (`checks`, the READY CHECK's rows; the required ones first, what server/Missions.luau refusal()
--     asks for):
--       level     its driver level (Missions.levelOf; a replay plays at any level)
--       vehicle   a car of your own, driven (a bike won't do; the server asks for it even when the mission lends its
--                 vehicle): Earl's Old Van first (Config.VanQuest), shown below its level too: save up early
--       cargo     room for its pieces in that car at its stage (Economy.capacity, the Roof Rack's slots for light
--                 pieces too), unless the mission lends a vehicle: another car of yours that holds them, else the
--                 car's next stage that does (Wrench Garage), else the cheapest dealer car that does
--       partner   a DUO mission: a member in your crew (Config.Missions.Duo.MinCrew)
--     and what would help (`required = false`, never blocking; Config.Readiness): a friend on a co-op mission, a vest
--     and a two-handed gun on a hard one (HardTier), a medkit, a repair kit once you drive. At most MaxRows rows.
--   * What to save up for (`goal`): the first row not done that costs money (required first), with your money.
-- `quiet`: Marge's first day runs (or the phone is not yours yet): the HUD's savings line and the READY toast wait.
-- The words every surface uses are here too (Readiness.status, goalLine, workLine, resultLine, readyToast …).

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Levels = require(script.Parent.Levels)
local Missions = require(script.Parent.Missions)
local VanQuest = require(script.Parent.VanQuest)
local Armour = require(script.Parent.Armour)
local Transport = require(script.Parent.Transport)

local Readiness = {}

export type Input = {
	xp: number?, -- the driver's XP (the Xp attribute, else the state's)
	level: number?, -- the driver level (else from the XP)
	money: number?,
	progress: { [string]: number }?, -- the Missions state: best stars per mission
	cars: { [string]: boolean }?, -- the vehicles you own (state.cars)
	car: string?, -- the one CAR / MY BIKE brings (state.car: what a mission is driven in)
	lastCar: string?, -- the car CALL CAR brings back (state.lastCar)
	carUpgrades: { [string]: { [string]: number } }?, -- every car's levels, its stage among them (state.carUpgrades)
	carGear: any?, -- every car's gear (state.carGear: the Roof Rack's slots)
	crewSize: number?, -- the members of your own crew (the Missions state)
	crewOwner: string?, -- your crew leader's name while you are in somebody else's crew
	kit: { [string]: boolean }?, -- personal gear (the vests)
	weapons: { [string]: boolean }?, -- the guns you own
	items: { [string]: number }?, -- medkits, repair kits …
	vanQuest: string?, -- Earl's van: nil, "open" or "done" (state.vanQuest)
	tutorial: string?, -- Marge's first day: her phase while it runs (nil, or "done", when it is over)
	phone: boolean?, -- the phone is yours (false: her first day has not given it yet)
	mission: string?, -- a mission id to check instead of the next one (the tests; a window's pick)
}

export type Check = {
	id: string, -- level | vehicle | cargo | partner | friend | vest | gun | medkit | repair
	icon: string,
	text: string, -- the headline: "Reach level 4", "A van of your own"
	detail: string?, -- how and where: "Old Van at Earl's Used Wheels · $1,800 · level 4"
	done: boolean,
	required: boolean,
	have: number?, -- the XP or the money you have toward it
	need: number?, -- the XP of the level, or the price
	cost: number?, -- the money it takes (a savings goal)
	name: string?, -- what is bought ("Old Van", "Work Van"): the goal's name
	place: string?, -- a Map.Shops / Map.Landmarks id for the GPS
	action: string?, -- "gps" | "invite" | "jobs" | "garage" | "missions"
	level: number?, -- the driver level it can be bought at
}

export type MissionInfo = {
	id: string,
	name: string,
	chapter: string, -- the chapter's title ("First Shift")
	campaign: string,
	icon: string,
	number: number, -- its step in the chapter
	total: number, -- the chapter's missions
	level: number,
	tier: number,
	coop: boolean,
	duo: boolean,
	replay: boolean, -- done before: played again for stars
	lends: string?, -- the vehicle it lends (Config.Cars id)
	description: string,
}

export type Goal = { id: string, icon: string, name: string, have: number, need: number, left: number, place: string?, afford: boolean }

export type Result = {
	mission: MissionInfo?,
	checks: { Check },
	ready: boolean, -- every required row is done
	done: number, -- required rows done
	required: number, -- required rows
	goal: Goal?,
	quiet: boolean,
}

-- Where a place id is, in the words the rows use (the ids: Map.Shops / Map.Landmarks).
local PLACES: { [string]: string } = {
	earl = Config.VanQuest.Place,
	dealer = Config.BikeShop.Shop,
	bikes = `{Config.BikeShop.Shop}{if string.sub(Config.BikeShop.Shop, -1) == "s" then "'" else "'s"} BIKES counter`,
	mechanic = "Wrench Garage",
	supplies = "the gear stall",
	bags = "the gear stall",
	guns = Config.GunRange.Shop,
}

-- The phases of Marge's first day that keep the HUD's savings line and the READY toast away (server/Tutorial.luau).
local QUIET_PHASES: { [string]: boolean } = { wait = true, welcome = true, tour = true, board = true, job = true, retry = true }

-- "$1,250".
local function money(amount: number): string
	local digits = tostring(math.floor(math.max(0, amount) + 0.5))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end
Readiness.money = money

-- "12,480".
local function number(amount: number): string
	return string.sub(money(amount), 2)
end

function Readiness.placeName(id: string?): string?
	return if id then PLACES[id] else nil
end

-- The next mission and why it is the one: "story" (the next story chapter's next), "duo" (the side story, once every
-- story chapter is done), "replay" (all done: the first short of ★★★), or nil when every star is yours.
function Readiness.nextMission(progress: { [string]: number }?): (Missions.MissionDef?, string?)
	local record = progress or {}
	for _, campaign in Missions.Campaigns do
		if not campaign.duo then
			local def = Missions.nextUp(record, campaign.id)
			if def then
				return def, "story"
			end
		end
	end
	for _, campaign in Missions.Campaigns do
		if campaign.duo then
			local def = Missions.nextUp(record, campaign.id)
			if def then
				return def, "duo"
			end
		end
	end
	for _, def in Missions.List do
		if (record[def.id] or 0) < 3 then
			return def, "replay"
		end
	end
	return nil, nil
end

-- Marge's first day (or no phone yet): nothing of this pushes itself on the screen.
function Readiness.quiet(input: Input): boolean
	return (input.tutorial ~= nil and QUIET_PHASES[input.tutorial] == true) or input.phone == false
end

-- A car of `cars` that is not a bike (its id), the equipped one first, then the one CALL CAR brings back.
local function ownCar(input: Input): string?
	local cars = input.cars or {}
	for pass = 1, 2 do
		local id = if pass == 1 then input.car else input.lastCar
		local def = if id then Economy.findCar(id) else nil
		if def and not def.bike and cars[def.id] == true then
			return def.id
		end
	end
	for _, def in Config.Cars do
		if cars[def.id] == true and not def.bike then
			return def.id
		end
	end
	return nil
end

-- How many pieces of this mission's cargo a car holds now (its stage, its gear: the Roof Rack for light pieces).
local function holds(input: Input, carId: string, look: string?): number
	return Economy.capacity(carId, Economy.carLevels(input.carUpgrades, carId), Economy.installedGear(input.carGear, carId), look)
end

-- The first stage of `carId` after `stage` that holds `need` (and what the stages up to it cost together: they are
-- built one after the other), or nil.
local function stageFor(carId: string, stage: number, need: number, extra: number): (Config.StageDef?, number, number)
	local cost, level = 0, 1
	for n = stage + 1, Economy.maxStage(carId) do
		local def = Economy.stageDef(carId, n)
		if not def then
			break
		end
		cost += def.price
		level = math.max(level, def.level or 1)
		if def.capacity + extra >= need then
			return def, cost, level
		end
	end
	return nil, 0, 1
end

-- The cheapest vehicle you do not own that holds `need` at some stage (its price and the stages up to it).
local function dealerFor(input: Input, need: number): (Config.CarDef?, Config.StageDef?, number, number)
	local cars = input.cars or {}
	local best: Config.CarDef?, bestStage: Config.StageDef?, bestCost, bestLevel = nil, nil, math.huge, 1
	for _, def in Config.Cars do
		if def.company or def.bike or cars[def.id] then
			continue
		end
		local cost, level, stage = def.price, def.level or 1, nil
		if def.capacity < need then
			local found, more, at = stageFor(def.id, 0, need, 0)
			if not found then
				continue
			end
			stage, cost, level = found, cost + more, math.max(level, at)
		end
		if cost < bestCost then
			best, bestStage, bestCost, bestLevel = def, stage, cost, level
		end
	end
	return best, bestStage, if best then bestCost else 0, bestLevel
end

-- The vehicle to buy when you own no car: Earl's Old Van while his quest is not done, else the dealer's cheapest.
local function firstCar(input: Input, level: number): Config.CarDef
	local van = VanQuest.def()
	local cars = input.cars or {}
	if VanQuest.status(input.vanQuest, cars[van.id] == true, level) ~= "done" then
		return van
	end
	local cheapest: Config.CarDef? = nil
	for _, def in Config.Cars do
		if not def.company and not def.bike and def.id ~= van.id and (cheapest == nil or def.price < (cheapest :: Config.CarDef).price) then
			cheapest = def
		end
	end
	return cheapest or van
end

local function placeOf(carId: string): string
	return if VanQuest.isQuestCar(carId) then "earl" else "dealer"
end

-- " · level 5" when you are below it, else "".
local function levelNote(needed: number?, level: number): string
	return if needed and needed > level then ` · level {needed}` else ""
end

-- ── The checks ────────────────────────────────────────────────────────────

local function levelCheck(def: Missions.MissionDef, campaign: Missions.Campaign?, xp: number, level: number): Check
	local needed = math.max(def.level or 1, if campaign then campaign.level else 1)
	local done = level >= needed
	return {
		id = "level",
		icon = "⬆",
		text = if done then `Level {needed}` else `Reach level {needed}`,
		detail = if done then "Your driver level is high enough" else `{number(xp)} / {number(Levels.xpFor(needed))} XP`,
		done = done,
		required = true,
		have = xp,
		need = Levels.xpFor(needed),
		action = if done then nil else "jobs",
		level = needed,
	}
end

local function vehicleCheck(input: Input, level: number): Check
	local equipped = input.car
	local drives = equipped ~= nil and not Transport.isBike(equipped)
	if drives then
		local carId = equipped :: string
		local def = Economy.findCar(carId)
		return {
			id = "vehicle",
			icon = "🚐",
			text = "A vehicle of your own",
			detail = `Your {if def then Economy.carTitle(carId, Economy.carLevels(input.carUpgrades, carId)) else carId}`,
			done = true,
			required = true,
		}
	end
	if ownCar(input) then
		-- (a car of yours waits while you ride a bike: the mission needs the car)
		return {
			id = "vehicle",
			icon = "🚐",
			text = "Your car, not the bike",
			detail = "CALL CAR on your phone's GARAGE: a bike won't do for a mission",
			done = false,
			required = true,
			action = "garage",
		}
	end
	local def = firstCar(input, level)
	local cash = math.max(0, input.money or 0)
	local quest = VanQuest.isQuestCar(def.id)
	return {
		id = "vehicle",
		icon = "🚐",
		text = if quest then "A van of your own" else "A vehicle of your own",
		detail = `{def.name} at {PLACES[placeOf(def.id)]} · {money(def.price)}{levelNote(def.level, level)}`,
		done = false,
		required = true,
		have = cash,
		need = def.price,
		cost = def.price,
		name = def.name,
		place = placeOf(def.id),
		action = "gps",
		level = def.level,
	}
end

-- Room for the mission's pieces (nil: it needs none, or it lends its vehicle, or the car you would buy holds them).
local function cargoCheck(input: Input, def: Missions.MissionDef, level: number): Check?
	local need = Economy.cargoNeed(def.load, def.items)
	if def.vehicle or need <= 0 then
		return nil
	end
	local kind = Config.Cargo.Kinds[def.itemKind]
	local look = if kind then kind.look else def.itemKind
	local cash = math.max(0, input.money or 0)
	local equipped = input.car
	local drives = equipped ~= nil and not Transport.isBike(equipped)
	local carId = if drives then equipped else ownCar(input)
	local text = `Room for {need} pieces`
	if not carId then
		-- No car yet: the vehicle row buys one; this row only when that one would still be too small.
		local first = firstCar(input, level)
		if first.capacity >= need then
			return nil
		end
		local stage, cost, at = stageFor(first.id, 0, need, 0)
		if stage then
			return { id = "cargo", icon = "📦", text = `A vehicle for {need} pieces`, detail = `then build the {first.name} up to a {stage.name} at Wrench Garage · {money(cost)}{levelNote(at, level)}`, done = false, required = true, have = cash, need = cost, cost = cost, name = stage.name, place = "mechanic", action = "gps", level = at }
		end
		local other, otherStage, price, at2 = dealerFor(input, need)
		if other then
			return { id = "cargo", icon = "📦", text = `A vehicle for {need} pieces`, detail = `the {other.name}{if otherStage then ` as a {otherStage.name}` else ""} at {PLACES[placeOf(other.id)]} · {money(price)}{levelNote(at2, level)}`, done = false, required = true, have = cash, need = price, cost = price, name = other.name, place = placeOf(other.id), action = "gps", level = at2 }
		end
		return nil
	end
	local mine = carId :: string
	local car = Economy.findCar(mine)
	local room = holds(input, mine, look)
	local carName = if car then car.name else mine
	if room >= need then
		return { id = "cargo", icon = "📦", text = text, detail = `Your {carName} holds {room}`, done = true, required = true }
	end
	text = `A vehicle for {need} pieces`
	-- Another car of yours that holds them now: free, swap at a garage.
	for _, other in Config.Cars do
		if other.id ~= mine and not other.bike and (input.cars or {})[other.id] == true then
			local otherRoom = holds(input, other.id, look)
			if otherRoom >= need then
				return { id = "cargo", icon = "📦", text = text, detail = `Your {carName} holds {room}: take your {other.name} (holds {otherRoom}) · GARAGE`, done = false, required = true, action = "garage", name = other.name }
			end
		end
	end
	-- The car's own next stage that holds them (the Roof Rack's slots stay with it).
	local stageNow = Economy.stageOf(mine, Economy.carLevels(input.carUpgrades, mine))
	local rack = room - Economy.stageCapacity(mine, stageNow)
	local stage, cost, at = stageFor(mine, stageNow, need, rack)
	if stage and car and not car.company then
		return { id = "cargo", icon = "📦", text = text, detail = `Your {carName} holds {room}: build it up to a {stage.name} at Wrench Garage · {money(cost)}{levelNote(at, level)}`, done = false, required = true, have = cash, need = cost, cost = cost, name = stage.name, place = "mechanic", action = "gps", level = at }
	end
	local other, otherStage, price, at2 = dealerFor(input, need)
	if other then
		return { id = "cargo", icon = "📦", text = text, detail = `Your {carName} holds {room}: the {other.name}{if otherStage then ` as a {otherStage.name}` else ""} at {PLACES[placeOf(other.id)]} · {money(price)}{levelNote(at2, level)}`, done = false, required = true, have = cash, need = price, cost = price, name = other.name, place = placeOf(other.id), action = "gps", level = at2 }
	end
	return { id = "cargo", icon = "📦", text = text, detail = `Your {carName} holds {room}`, done = false, required = true }
end

local function inCrew(input: Input): boolean
	return input.crewOwner ~= nil or (input.crewSize or 0) >= Config.Missions.Duo.MinCrew
end

-- The cheapest piece of kit with armour (a vest), the cheapest buyable two-handed gun (both at or under `upTo` when
-- one is, else the first at all).
local function cheapestVest(upTo: number): Config.KitDef?
	local best: Config.KitDef? = nil
	for _, def in Config.Kit do
		if (def.armour or 0) > 0 and (best == nil or (def.level <= upTo and def.price < (best :: Config.KitDef).price)) then
			best = def
		end
	end
	return best
end

local function cheapestLongGun(upTo: number): Config.WeaponDef?
	local best: Config.WeaponDef? = nil
	for _, def in Config.Weapons do
		if def.oneHanded or def.starter or Economy.rewardOnly(def) then
			continue
		end
		local b = best
		if b == nil or ((def.level or 1) <= upTo and ((b.level or 1) > upTo or def.price < b.price)) then
			best = def
		end
	end
	return best
end

local function ownsLongGun(weapons: { [string]: boolean }?): boolean
	for _, def in Config.Weapons do
		if not def.oneHanded and weapons and weapons[def.id] == true then
			return true
		end
	end
	return false
end

local function itemCheck(input: Input, id: string, icon: string, wanted: number, why: string): Check?
	local def = Economy.findItem(id)
	if not def or wanted <= 0 then
		return nil
	end
	local have = math.max(0, math.floor((input.items or {})[id] or 0))
	local missing = math.max(0, wanted - have)
	local cost = missing * def.price
	return {
		id = id,
		icon = icon,
		text = if wanted == 1 then `A {string.lower(def.name)}` else `{wanted} {string.lower(def.name)}s`,
		detail = if missing == 0 then `You carry {have}` else `{why} · {money(cost)} at {PLACES.supplies}`,
		done = missing == 0,
		required = false,
		have = math.max(0, input.money or 0),
		need = if missing > 0 then cost else nil,
		cost = if missing > 0 then cost else nil,
		name = def.name,
		place = if missing > 0 then "supplies" else nil,
		action = if missing > 0 then "gps" else nil,
	}
end

-- What would help (never blocking), in the order they matter.
local function recommended(input: Input, def: Missions.MissionDef, level: number, drives: boolean): { Check }
	local tuning = Config.Readiness
	local list: { Check } = {}
	local cash = math.max(0, input.money or 0)
	if def.coop and not def.duo then
		local pay = math.floor(Config.Missions.CoopPayPerMember * 100 + 0.5)
		local crewed = inCrew(input)
		table.insert(list, { id = "friend", icon = "🤝", text = "Bring a friend", detail = if crewed then "Your crew rides with you: co-op pays more" else `Co-op pays +{pay}% for every friend in your crew`, done = crewed, required = false, action = if crewed then nil else "invite" })
	end
	if def.tier >= tuning.HardTier then
		local upTo = math.max(level, def.level or 1)
		if Armour.share(input.kit or {}) > 0 then
			local best = Armour.best(input.kit or {})
			table.insert(list, { id = "vest", icon = "🦺", text = "A vest", detail = `Your {if best then best.name else "vest"} takes {Armour.percent(input.kit or {})}% off every hit`, done = true, required = false })
		else
			local vest = cheapestVest(upTo)
			if vest then
				table.insert(list, { id = "vest", icon = "🦺", text = "A vest", detail = `{vest.name} at {PLACES[Transport.kitShop(vest)] or PLACES.supplies} · {money(vest.price)}{levelNote(vest.level, level)}`, done = false, required = false, have = cash, need = vest.price, cost = vest.price, name = vest.name, place = Transport.kitShop(vest), action = "gps", level = vest.level })
			end
		end
		if ownsLongGun(input.weapons) then
			table.insert(list, { id = "gun", icon = "🔫", text = "A two-handed gun", detail = "Yours: for the fights on foot at the stops", done = true, required = false })
		else
			local gun = cheapestLongGun(upTo)
			if gun then
				table.insert(list, { id = "gun", icon = "🔫", text = "A two-handed gun", detail = `{gun.name} at {PLACES.guns} · {money(gun.price)}{levelNote(gun.level, level)}`, done = false, required = false, have = cash, need = gun.price, cost = gun.price, name = gun.name, place = "guns", action = "gps", level = gun.level })
			end
		end
	end
	local medkit = itemCheck(input, "medkit", "➕", tuning.Medkits, "Heals you fully, at once")
	if medkit then
		table.insert(list, medkit)
	end
	if drives or Economy.ownsCar(input.cars) then
		local repair = itemCheck(input, "repair", "🔧", tuning.RepairKits, "Fixes 40% of your car on the road")
		if repair then
			table.insert(list, repair)
		end
	end
	return list
end

-- What the next mission (or input.mission) needs, what would help, and what to save up for. See the header.
function Readiness.evaluate(input: Input): Result
	local tuning = Config.Readiness
	local progress = input.progress or {}
	local xp = math.max(0, input.xp or 0)
	local level = input.level or Levels.levelFor(xp)
	local quiet = Readiness.quiet(input)
	local def: Missions.MissionDef?, kind: string? = nil, nil
	if input.mission then
		def = Missions.find(input.mission)
		kind = if def and (progress[def.id] or 0) >= 1 then "replay" else "story"
	else
		def, kind = Readiness.nextMission(progress)
	end
	if not def then
		return { mission = nil, checks = {}, ready = false, done = 0, required = 0, goal = nil, quiet = quiet }
	end
	local mission = def :: Missions.MissionDef
	local campaign = Missions.findCampaign(mission.campaign)
	local replay = kind == "replay"
	local info: MissionInfo = {
		id = mission.id,
		name = mission.name,
		chapter = if campaign then campaign.name else mission.campaign,
		campaign = mission.campaign,
		icon = if campaign then campaign.icon else "📦",
		number = mission.number,
		total = Missions.size(mission.campaign),
		level = math.max(mission.level or 1, if campaign then campaign.level else 1),
		tier = mission.tier,
		coop = mission.coop == true,
		duo = mission.duo == true,
		replay = replay,
		lends = mission.vehicle,
		description = mission.description,
	}
	-- The required rows (server/Missions.luau refusal: the level, a car of your own, the room, a partner).
	local required: { Check } = {}
	if not replay then
		table.insert(required, levelCheck(mission, campaign, xp, level))
	end
	local vehicle = vehicleCheck(input, level)
	table.insert(required, vehicle)
	local cargo = cargoCheck(input, mission, level)
	if cargo then
		table.insert(required, cargo)
	end
	if mission.duo then
		local crewed = inCrew(input)
		table.insert(required, { id = "partner", icon = "👥", text = "A partner in your crew", detail = if crewed then "Your crew is with you" else "DUO: Rosa & Rico only work with two · INVITE a friend", done = crewed, required = true, action = if crewed then nil else "invite" })
	end
	-- What would help: the ones not done first, as many as fit.
	local helps = recommended(input, mission, level, vehicle.done)
	local open: { Check }, closed: { Check } = {}, {}
	for _, check in helps do
		table.insert(if check.done then closed else open, check)
	end
	local checks: { Check } = table.clone(required)
	for _, list in { open, closed } do
		for _, check in list do
			if #checks < tuning.MaxRows then
				table.insert(checks, check)
			end
		end
	end
	local done = 0
	for _, check in required do
		if check.done then
			done += 1
		end
	end
	-- The savings goal: the first row not done that costs money (never a medkit or a repair kit: Config.Readiness.NotGoals,
	-- pocket money is nothing to save up for).
	local goal: Goal? = nil
	local cash = math.max(0, input.money or 0)
	for _, check in checks do
		local cost = check.cost
		if not check.done and cost and cost > 0 and not tuning.NotGoals[check.id] then
			goal = { id = check.id, icon = check.icon, name = check.name or check.text, have = cash, need = cost, left = math.max(0, cost - cash), place = check.place, afford = cash >= cost }
			break
		end
	end
	return { mission = info, checks = checks, ready = done == #required, done = done, required = #required, goal = goal, quiet = quiet }
end

-- ── The words ─────────────────────────────────────────────────────────────

-- "✔" done, "✖" a required one missing, "☆" a recommended one missing.
function Readiness.mark(check: Check): string
	return if check.done then "✔" elseif check.required then "✖" else "☆"
end

-- A row in one line: "A van of your own → Old Van at Earl's Used Wheels · $1,800".
function Readiness.line(check: Check): string
	return if check.detail and not check.done then `{check.text} → {check.detail}` else check.text
end

-- "READY · START", or "2 of 3 ready".
function Readiness.status(result: Result): string
	if not result.mission then
		return "ALL DONE"
	end
	return if result.ready then "READY · START" else `{result.done} of {result.required} ready`
end

-- "First Shift · 1/6", a replay "Replay for stars · First Shift", the DUO side story "DUO · Partners in Crime · 2/6".
function Readiness.chapterLine(mission: MissionInfo?): string
	if not mission then
		return "Every mission done"
	end
	if mission.replay then
		return `Replay for stars · {mission.chapter}`
	end
	return `{if mission.duo then "DUO · " else ""}{mission.chapter} · {mission.number}/{mission.total}`
end

-- "Old Van · $640 / $1,800".
function Readiness.goalLine(goal: Goal): string
	return `{goal.name} · {money(goal.have)} / {money(goal.need)}`
end

-- The HUD's savings line under the cash: "🚐 Old Van  $640 / $1,800"; affordable: "🚐 Old Van  ✓ buy it · $1,800".
function Readiness.hudLine(goal: Goal): string
	if goal.afford then
		return `{goal.icon} {goal.name}  ✓ buy it · {money(goal.need)}`
	end
	return `{goal.icon} {goal.name}  {money(goal.have)} / {money(goal.need)}`
end

-- "$1,160 to go", or "✓ you can buy it".
function Readiness.toGo(goal: Goal): string
	return if goal.left > 0 then `{money(goal.left)} to go` else "✓ you can buy it"
end

-- The WORK tile's goal line: "Earn for the Old Van · $1,160 to go", or "Buy the Old Van now · $1,800".
function Readiness.workLine(goal: Goal?): string?
	if not goal then
		return nil
	end
	return if goal.left > 0 then `Earn for the {goal.name} · {money(goal.left)} to go` else `Buy the {goal.name} now · {money(goal.need)}`
end

-- The job result's line: "+$85 · $1,160 to go for the Old Van" (`after`: your money with this pay in it).
function Readiness.resultLine(pay: number, goal: Goal?, after: number): string?
	if not goal or pay <= 0 then
		return nil
	end
	local left = math.max(0, goal.need - after)
	return if left > 0 then `+{money(pay)} · {money(left)} to go for the {goal.name}` else `+{money(pay)} · enough for the {goal.name} now`
end

-- The one-time toast when the next mission is ready: "Ready for Paper Trail · open MISSIONS (U)".
function Readiness.readyToast(mission: MissionInfo, touch: boolean?): string
	return `Ready for {mission.name} · open MISSIONS{if touch then "" else " (U)"}`
end

-- A short key of what the READY CHECK shows (not the money): it is drawn again only when this changes.
function Readiness.key(result: Result): string
	local parts: { string } = { if result.mission then result.mission.id else "-" }
	for _, check in result.checks do
		table.insert(parts, `{check.id}:{if check.done then 1 else 0}:{check.cost or 0}:{check.detail or ""}`)
	end
	return table.concat(parts, "|")
end

return Readiness
