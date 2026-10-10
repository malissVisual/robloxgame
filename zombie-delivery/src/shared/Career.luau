--!strict
-- 4.6, the career: the road from level 1 to Config.Levels.MaxLevel as one list, built from Config (and the campaigns
-- of shared/Missions.luau). Pure Luau, tested in tests/career_test.luau; the CAREER window and the level-up card
-- (client/CareerUi.luau) draw it, server/PlayerData.luau gives the rewards with Career.pending.
--
--   Career.road()                 { { level, xp, rank, unlocks = { { kind, id, name, car? } }, reward } } for 1 … Max
--   Career.unlocksAt(level)       what one level opens (the same list a road row has)
--   Career.reward(level)          Config.Levels.Rewards[level] (nil at level 1)
--   Career.rewardParts(reward)    the reward in words: { "$1,500", "2 Medkits", "Hi-Vis Orange paint", … }
--   Career.summary(unlocks, max)  a short line: "Box Truck, ★★★ Dangerous jobs, Hunting Rifle …"
--   Career.pending(level, given)  the levels 2 … level whose reward is not in `given` yet (profile.levelRewards)
--   Career.reached(level)         the keys of levels 2 … level (a save from before 4.6: given, never paid)
--   Career.gearLevel(gear)        5.7: the level a piece of gear shows at on the road (car gear: never before a car)
--   Career.grantKit(reward, kit)  5.7: a reward's kit (Config.Kit) marked owned in `kit` (profile.kit); the money to pay
--                                 instead when it was owned already (0 otherwise)
--
-- Unlock kinds: tier (a danger level on the job board), job (a special job), car, stage (a stage of a car: id
-- "carId:stage", `car` its car id), gear (Config.Gear), gun, cargun, campaign (shared/Missions.luau), garage, estate
-- (homes and offices). Level 1 lists what you start with (the Pistol, the first jobs).
-- 5.0, the career starts on foot: foot (the ON FOOT runs of the board, Config.Jobs.Foot), kit (personal gear,
-- Config.Kit: the bags, the vests …). 5.1: bike (a bike of Config.Cars at its level, "at Config.BikeShop.Shop":
-- 6.12.7: Dead End Motors; before Config.Cars has one, a line "Bikes at …" at BIKE_LEVEL); the bike gear is gear.
-- 6.12.14: a gun you buy says where ("SMG at Lead & Co.'s range", Config.GunRange.Shop); the starter pistol only its name.
-- 6.14 (the owner: progress was confusing; the level-up should say what is new AND where it is):
--   Career.whereOf(unlock)        where an unlock is found: a place for the GPS (a Map.Shops / Map.Landmarks id) or
--                                 the window that opens it, and the place in words (client/CareerUi.luau's level-up
--                                 card: GPS / MISSIONS / ESTATE buttons; client/Hud.luau's small banner)
-- 6.19 (at the end of this file): the guns and the cars a mission unlocks instead of a level:
--   Career.missionLock(def, progress)  the mission id still to finish before `def` is sold, else nil
--   Career.missionUnlocks(id)    what finishing a mission unlocks ({ Unlock }); Career.unlocksLine(id) "🔓 Unlocks: SMG";
--                                Career.newLines(id) the cleared card's "🔓 NEW: SMG at Lead & Co." (and its place)

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Levels = require(script.Parent.Levels)
local Map = require(script.Parent.Map)
local Missions = require(script.Parent.Missions)
local Transport = require(script.Parent.Transport)

local Career = {}

export type Unlock = { kind: string, id: string, name: string, car: string? }
-- 6.14: `place` a Map.Shops / Map.Landmarks id (the GPS goes there), else `window` what opens it ("missions",
-- "estate", "jobs"); `label` the place in words ("Earl's Used Wheels", "Dead End Motors' BIKES counter").
export type Where = { place: string?, window: string?, label: string }
export type Step = {
	level: number,
	xp: number, -- the total XP that reaches it (Levels.xpFor)
	rank: string, -- the rank from this level on (Levels.rank)
	newRank: boolean, -- a new rank starts at this level (Config.Levels.Ranks)
	unlocks: { Unlock },
	reward: Config.LevelReward?,
}

-- The order of the kinds in a row: the job board first, then the vehicles and the gear, the guns, the stories, the
-- real estate.
local ORDER: { [string]: number } = { foot = 0, tier = 1, job = 2, kit = 3, bike = 3, car = 3, stage = 4, gear = 5, gun = 6, cargun = 7, campaign = 8, garage = 9, estate = 10 }

-- 5.0: the level the bikes come at (5.1: the bike counter, Config.BikeShop; the BIKE runs, Config.Jobs.Bike.Level).
Career.BIKE_LEVEL = Config.Jobs.Bike.Level

-- Is there a bike in Config.Cars (5.1)?
local function hasBikes(): boolean
	for _, def in Config.Cars do
		if def.bike then
			return true
		end
	end
	return false
end

local function add(list: { Unlock }, kind: string, id: string, name: string, car: string?)
	table.insert(list, { kind = kind, id = id, name = name, car = car })
end

-- 5.7: the level a piece of gear shows at on the road: its own, but a car's gear (not bikeOnly: the Hand Trolley at 3)
-- never before the first car (Config.VanQuest's car, level 4): nothing to put it in before that.
function Career.gearLevel(gear: Config.GearDef): number
	if gear.bikeOnly then
		return gear.level
	end
	local first: Config.CarDef? = nil
	for _, def in Config.Cars do
		if def.id == Config.VanQuest.Car then
			first = def
		end
	end
	return math.max(gear.level, if first then first.level or 1 else 1)
end

-- What one level opens.
function Career.unlocksAt(level: number): { Unlock }
	local list: { Unlock } = {}
	-- 5.0: the on-foot runs (Config.Jobs.Foot, always from level 1) and the personal gear.
	local foot = (Config.Jobs :: any).Foot
	local footLevel = if type(foot) == "table" and type(foot.level) == "number" then foot.level else 1
	if footLevel == level then
		add(list, "foot", "foot", "On-foot runs: letters, medicine, pizza")
	end
	for _, kit in Config.Kit do
		if kit.level == level then
			add(list, "kit", kit.id, kit.name)
		end
	end
	if level == Career.BIKE_LEVEL and not hasBikes() then
		add(list, "bike", "bikes", `Bikes at {Config.BikeShop.Shop}`)
	end
	for index, tier in Config.Jobs.Tiers do
		if tier.level == level then
			-- 4.7: a tier with a licence (Config.Jobs.Licences) says what else it needs.
			local licence: { tier: number, level: number, jobs: number, atTier: number }? = nil
			for _, def in Config.Jobs.Licences do
				if def.tier == index then
					licence = def
				end
			end
			local needs = if licence then ` (licence: {licence.jobs} jobs rated ★★+ at {string.rep("★", licence.atTier)})` else ""
			add(list, "tier", tostring(index), `{string.rep("★", tier.stars)} {tier.name} jobs{needs}`)
		end
	end
	for _, def in Config.JobTypes do
		if def.mission == nil and Economy.jobLevel(def, def.tier) == level and (def.level ~= nil or Economy.onBoard(def)) then
			local employer = if def.employer and not def.board then Economy.findEmployer(def.employer) else nil
			add(list, "job", def.id, if employer then `{def.name} ({employer.name})` else def.name)
		end
	end
	for _, def in Config.Cars do
		if def.company then
			continue
		elseif def.bike then
			-- 5.1: a bike, at the bike counter (no stages; 6.12.7: Dead End Motors' BIKES counter).
			if (def.level or 1) == level then
				add(list, "bike", def.id, `{def.name} at {Config.BikeShop.Shop}`)
			end
			continue
		end
		if def.mission == nil and (def.level or 1) == level then -- (6.19: a car a mission unlocks is on its mission's list)
			-- 5.0: the Old Van is not the dealer's: "Old Van: Earl's Used Wheels (Marge's quest at level 4)".
			add(list, "car", def.id, if def.id == Config.VanQuest.Car then `{def.name}: {Config.VanQuest.Where}` else def.name)
		end
		local stages: { Config.StageDef } = def.stages or {}
		for n, stage in stages do
			if n > 1 and (stage.level or 1) == level then
				add(list, "stage", `{def.id}:{n - 1}`, stage.name, def.id)
			end
		end
	end
	for _, gear in Config.Gear do
		if Career.gearLevel(gear) == level then
			add(list, "gear", gear.id, gear.name)
		end
	end
	for _, def in Config.Weapons do
		if not def.earned and not def.exclusive and def.mission == nil and (def.level or 1) == level then
			add(list, "gun", def.id, if def.starter then def.name else `{def.name} at {Config.GunRange.Shop}`)
		end
	end
	for _, def in Config.CarGuns do
		if def.mission == nil and (def.level or 1) == level then
			add(list, "cargun", def.id, def.name)
		end
	end
	for _, campaign in Missions.Campaigns do
		if campaign.level == level then
			add(list, "campaign", campaign.id, campaign.name)
		end
	end
	for _, def in Config.Estate.Properties do
		if (def.level or 1) == level then
			add(list, if def.kind == "garage" then "garage" else "estate", def.id, def.name)
		end
	end
	-- (a stable sort: the kinds in ORDER, the Config order inside a kind)
	local position: { [Unlock]: number } = {}
	for index, unlock in list do
		position[unlock] = index
	end
	table.sort(list, function(a: Unlock, b: Unlock): boolean
		local ka, kb = ORDER[a.kind] or 99, ORDER[b.kind] or 99
		if ka ~= kb then
			return ka < kb
		end
		return position[a] < position[b]
	end)
	return list
end

-- What reaching a level gives (nil at level 1 and above the top).
function Career.reward(level: number): Config.LevelReward?
	return Config.Levels.Rewards[level]
end

-- The whole road, level 1 first.
function Career.road(): { Step }
	local steps: { Step } = {}
	local previous = ""
	for level = 1, Config.Levels.MaxLevel do
		local rank = Levels.rank(level)
		table.insert(steps, {
			level = level,
			xp = Levels.xpFor(level),
			rank = rank,
			newRank = rank ~= previous,
			unlocks = Career.unlocksAt(level),
			reward = Career.reward(level),
		})
		previous = rank
	end
	return steps
end

-- "$15,000".
function Career.money(amount: number): string
	local text = tostring(math.floor(math.abs(amount)))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

-- 5.7: a reward's piece of personal gear (Config.Kit), or nil.
function Career.kitOf(reward: Config.LevelReward?): Config.KitDef?
	local id = if reward then reward.kit else nil
	if id then
		for _, def in Config.Kit do
			if def.id == id then
				return def
			end
		end
	end
	return nil
end

-- 5.7: gives a reward's kit: marked owned in `kit` (profile.kit). Owned already: its price is paid instead (returned,
-- the caller adds it); 0 otherwise.
function Career.grantKit(reward: Config.LevelReward?, kit: { [string]: boolean }): number
	local def = Career.kitOf(reward)
	if not def then
		return 0
	elseif kit[def.id] then
		return def.price
	end
	kit[def.id] = true
	return 0
end

-- A reward in words, money first.
function Career.rewardParts(reward: Config.LevelReward?): { string }
	local parts: { string } = {}
	if not reward then
		return parts
	end
	if reward.money and reward.money > 0 then
		table.insert(parts, Career.money(reward.money))
	end
	if reward.items then
		for _, def in Config.Items do
			local count = reward.items[def.id]
			if count and count > 0 then
				table.insert(parts, `{count} {def.name}{if count == 1 then "" else "s"}`)
			end
		end
	end
	local kit = Career.kitOf(reward)
	if kit then
		table.insert(parts, if kit.extra then `the {kit.name} for this game` else `the {kit.name}`) -- 5.7 (6.23: a bag is per game)
	end
	if reward.paint then
		local paint = Economy.findPaint(reward.paint)
		table.insert(parts, `{if paint then paint.name else reward.paint} paint`)
	end
	if reward.title then
		table.insert(parts, `the title “{reward.title}”`)
	end
	return parts
end

-- A short line of the first `max` unlocks' names (stages of cars you do not own left out when `owned` is given),
-- "…" when there are more.
function Career.summary(unlocks: { Unlock }, max: number, owned: { [string]: boolean }?): string
	local names: { string } = {}
	local more = false
	for _, unlock in unlocks do
		if unlock.kind == "stage" and owned and not owned[unlock.car or ""] then
			continue
		end
		if #names >= max then
			more = true
			break
		end
		table.insert(names, unlock.name)
	end
	return table.concat(names, ", ") .. (if more then " …" else "")
end

-- 6.14: where an unlock is found (see Where above), nil for what needs no trip (the starter pistol, the starter bag):
--   bike, bike gear  Dead End Motors' BIKES counter (Map.Shops.bikes)
--   car              the Old Van at Earl's Used Wheels (Map.VanSeller, the landmark "earl"), the others Dead End Motors
--   stage, car gear, car gun   Wrench Garage
--   gun              Lead & Co.'s range;  kit  its shop (Transport.kitShop: the gear stall's two counters, the bat the range)
--   job              an employer's: their place (its landmark); a board job: JOBS
--   tier, foot       JOBS (the job board);  campaign  MISSIONS;  garage, estate  ESTATE
function Career.whereOf(unlock: Unlock): Where?
	local kind = unlock.kind
	-- ("Dead End Motors' BIKES counter": the possessive of a name ending in s)
	local bikes = `{Config.BikeShop.Shop}{if string.sub(Config.BikeShop.Shop, -1) == "s" then "'" else "'s"} BIKES counter`
	local function shop(id: string, label: string?): Where
		local entry = Map.Shops[id]
		return { place = id, label = label or (if entry then entry.name else id) }
	end
	if kind == "bike" then
		return shop("bikes", bikes)
	elseif kind == "car" then
		if unlock.id == Config.VanQuest.Car then
			return { place = "earl", label = Config.VanQuest.Place }
		end
		return shop("dealer")
	elseif kind == "stage" or kind == "cargun" then
		return shop("mechanic")
	elseif kind == "gear" then
		local gear = Economy.findGear(unlock.id)
		if gear and gear.bikeOnly then
			return shop("bikes", bikes)
		end
		return shop("mechanic")
	elseif kind == "gun" then
		local gun = Economy.findWeapon(unlock.id)
		if gun and (gun.starter or Economy.rewardOnly(gun)) then
			return nil
		end
		return shop("guns", Config.GunRange.Shop)
	elseif kind == "kit" then
		local kit = Transport.findKit(unlock.id)
		if not kit or kit.starter then
			return nil
		end
		local id = Transport.kitShop(kit)
		return shop(id, if id == "guns" then Config.GunRange.Shop else nil)
	elseif kind == "job" then
		for _, def in Config.JobTypes do
			if def.id == unlock.id and def.employer and not def.board then
				local employer = Economy.findEmployer(def.employer)
				if employer then
					return { place = employer.id, label = employer.name }
				end
			end
		end
		return { window = "jobs", label = "JOBS" }
	elseif kind == "tier" or kind == "foot" then
		return { window = "jobs", label = "JOBS" }
	elseif kind == "campaign" then
		return { window = "missions", label = "MISSIONS" }
	elseif kind == "garage" or kind == "estate" then
		return { window = "estate", label = "ESTATE" }
	end
	return nil
end

-- 6.14: an unlock's own short name, without where it is ("Old Van", "SMG", "School Run").
function Career.shortName(unlock: Unlock): string
	local name = unlock.name
	local cut = #name + 1
	for _, mark in { " at ", ": ", " (" } do
		local at = string.find(name, mark, 1, true)
		if at and at < cut then
			cut = at
		end
	end
	return string.sub(name, 1, cut - 1)
end

-- 6.14, the level-up card's rows: the unlocks grouped by where they are. The places first, with the GPS (`places` at
-- most; the vehicles, then the guns, the kit, the stages, the gear and the employers' jobs: a level-4 player wants
-- Earl's van more than a school bus), then MISSIONS for a new chapter and ESTATE for a garage or a home; `max` rows in
-- all. (The card leaves out the stages of cars you do not own before it asks.)
export type WhereRow = { place: string?, window: string?, label: string, names: { string }, id: string? }
local WHERE_ORDER: { [string]: number } = { car = 1, bike = 2, gun = 3, kit = 4, stage = 5, gear = 6, cargun = 7, job = 8 }

function Career.whereRows(unlocks: { Unlock }, places: number, max: number): { WhereRow }
	local sorted = table.clone(unlocks)
	local position: { [Unlock]: number } = {}
	for index, unlock in unlocks do
		position[unlock] = index
	end
	table.sort(sorted, function(a: Unlock, b: Unlock): boolean
		local x, y = WHERE_ORDER[a.kind] or 50, WHERE_ORDER[b.kind] or 50
		if x ~= y then
			return x < y
		end
		return position[a] < position[b]
	end)
	local placed: { WhereRow } = {}
	local missions: WhereRow? = nil
	local estate: WhereRow? = nil
	for _, unlock in sorted do
		local where = Career.whereOf(unlock)
		if not where then
			continue
		end
		local name = Career.shortName(unlock)
		if where.place then
			local found: WhereRow? = nil
			for _, row in placed do
				if row.place == where.place then
					found = row
				end
			end
			if found then
				table.insert(found.names, name)
			elseif #placed < places then
				table.insert(placed, { place = where.place, label = where.label, names = { name } })
			end
		elseif where.window == "missions" and not missions then
			missions = { window = "missions", label = where.label, names = { name }, id = unlock.id }
		elseif where.window == "estate" then
			if estate then
				table.insert(estate.names, name)
			else
				estate = { window = "estate", label = where.label, names = { name } }
			end
		end
	end
	local rows: { WhereRow } = {}
	for _, row in placed do
		if #rows < max then
			table.insert(rows, row)
		end
	end
	if missions and #rows < max then
		table.insert(rows, missions)
	end
	if estate and #rows < max then
		table.insert(rows, estate)
	end
	return rows
end

-- The levels 2 … `level` whose reward has not been given (`given`: profile.levelRewards, level → true by its
-- string key), lowest first.
function Career.pending(level: number, given: { [string]: boolean }): { number }
	local out: { number } = {}
	for n = 2, math.min(math.floor(level), Config.Levels.MaxLevel) do
		if Config.Levels.Rewards[n] and not given[tostring(n)] then
			table.insert(out, n)
		end
	end
	return out
end

-- The keys of levels 2 … `level` (a save from before 4.6: those rewards count as given, nothing is paid back).
function Career.reached(level: number): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for n = 2, math.min(math.floor(level), Config.Levels.MaxLevel) do
		out[tostring(n)] = true
	end
	return out
end

-- ── 6.19, the guns and the cars a mission unlocks ─────────────────────────────
-- The owner: the guns and the cars come with the story, not the level. A Config.Cars / Weapons / CarGuns def with a
-- `mission` (a shared/Missions.luau id) is sold once that mission is done (any rating); its `level` is that mission's
-- (the order, the fuel tier) and the road above leaves it out: it is on its mission's list instead. A save that owns
-- one keeps it. server/Shops.luau refuses the buy ("Finish Mail Call first."), the shops show the lock with a
-- MISSIONS button (client/ShopWindow.luau), MISSIONS shows "🔓 Unlocks: SMG" (client/MissionsUi.luau) and the cleared
-- card "🔓 NEW: SMG at Lead & Co." with the GPS.

-- The mission a def waits for (its `mission`), or nil.
function Career.missionOf(def: any): string?
	local id = if type(def) == "table" then def.mission else nil
	return if type(id) == "string" then id else nil
end

-- A mission's name ("Mail Call"), its id when unknown.
function Career.missionName(id: string): string
	local def = Missions.find(id)
	return if def then def.name else id
end

-- The mission still between you and buying `def` (`progress`: profile.missions, id → best rating), nil when open.
function Career.missionLock(def: any, progress: { [string]: number }?): string?
	local id = Career.missionOf(def)
	if id and not Missions.cleared(progress, id) then
		return id
	end
	return nil
end

-- "Finish Mail Call".
function Career.lockText(id: string): string
	return `Finish {Career.missionName(id)}`
end

-- What finishing one mission unlocks, in Config order (the cars, the guns, the car guns), as road unlocks (a gun says
-- where: "SMG at Lead & Co."; Career.whereOf finds the shop).
function Career.missionUnlocks(id: string): { Unlock }
	local list: { Unlock } = {}
	for _, def in Config.Cars do
		if def.mission == id and not def.company and not def.bike then
			add(list, "car", def.id, def.name)
		end
	end
	for _, def in Config.Weapons do
		if def.mission == id then
			add(list, "gun", def.id, `{def.name} at {Config.GunRange.Shop}`)
		end
	end
	for _, def in Config.CarGuns do
		if def.mission == id then
			add(list, "cargun", def.id, def.name)
		end
	end
	return list
end

-- MISSIONS' line for a mission: "🔓 Unlocks: SMG" ("🔓 Unlocks: Courier Van, High-Roof Van"), nil for nothing.
function Career.unlocksLine(id: string): string?
	local names: { string } = {}
	for _, unlock in Career.missionUnlocks(id) do
		table.insert(names, Career.shortName(unlock))
	end
	return if #names > 0 then `🔓 Unlocks: {table.concat(names, ", ")}` else nil
end

-- The cleared card's lines, one a shop: { text = "🔓 NEW: SMG at Lead & Co.", place = "guns" (the GPS goes there),
-- label = "Lead & Co." }.
export type NewLine = { text: string, place: string?, label: string }
function Career.newLines(id: string): { NewLine }
	local out: { NewLine } = {}
	for _, row in Career.whereRows(Career.missionUnlocks(id), 3, 3) do
		table.insert(out, { text = `🔓 NEW: {table.concat(row.names, ", ")} at {row.label}`, place = row.place, label = row.label })
	end
	return out
end

return Career
