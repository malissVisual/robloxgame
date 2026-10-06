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
--
-- Unlock kinds: tier (a danger level on the job board), job (a special job), car, stage (a stage of a car: id
-- "carId:stage", `car` its car id), gear (Config.Gear), gun, cargun, campaign (shared/Missions.luau), garage, estate
-- (homes and offices). Level 1 lists what you start with (the Pistol, the first jobs).
-- 5.0, the career starts on foot: foot (the ON FOOT runs of the board, Config.Jobs.Foot), kit (personal gear,
-- Config.Kit: the backpacks, the running shoes …), and soon (what the next release brings: the bikes at BIKE_LEVEL
-- until Config.Cars has a bike, then the bikes are ordinary car unlocks and the line goes by itself).

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Levels = require(script.Parent.Levels)
local Missions = require(script.Parent.Missions)

local Career = {}

export type Unlock = { kind: string, id: string, name: string, car: string? }
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
local ORDER: { [string]: number } = { foot = 0, tier = 1, job = 2, kit = 3, soon = 3, car = 3, stage = 4, gear = 5, gun = 6, cargun = 7, campaign = 8, garage = 9, estate = 10 }

-- 5.0: the level the bikes come at (5.1, the Spokes & Chains bike shop; the level 2 reward says so). Only a line on the
-- road until Config.Cars holds a bike (CarDef kind = "bike").
Career.BIKE_LEVEL = 2

-- Is there a bike in Config.Cars yet (5.1)?
local function hasBikes(): boolean
	for _, def in Config.Cars do
		if (def :: any).kind == "bike" then
			return true
		end
	end
	return false
end

local function add(list: { Unlock }, kind: string, id: string, name: string, car: string?)
	table.insert(list, { kind = kind, id = id, name = name, car = car })
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
		add(list, "soon", "bikes", "Bikes (coming in 5.1)")
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
		end
		if (def.level or 1) == level then
			add(list, "car", def.id, def.name)
		end
		local stages: { Config.StageDef } = def.stages or {}
		for n, stage in stages do
			if n > 1 and (stage.level or 1) == level then
				add(list, "stage", `{def.id}:{n - 1}`, stage.name, def.id)
			end
		end
	end
	for _, gear in Config.Gear do
		if gear.level == level then
			add(list, "gear", gear.id, gear.name)
		end
	end
	for _, def in Config.Weapons do
		if not def.earned and not def.exclusive and (def.level or 1) == level then
			add(list, "gun", def.id, def.name)
		end
	end
	for _, def in Config.CarGuns do
		if (def.level or 1) == level then
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

return Career
