--!strict
-- 6.20, skills for levels (Config.Skills; design/skills/PROPOSAL.md): the points a level gives, what a set of ranks
-- costs, whether a rank may be bought, and what the ranks add up to. Pure Luau, tested in tests/skills_test.luau. The
-- server keeps the ranks (server/PlayerData.luau profile.skills: skill id → rank) and decides every purchase
-- (server/Skills.luau); the client reads the same ranks (the state's `skills`, the player attribute Skills: encode).
--
--   Skills.find(id)                    the Config.Skills entry and its branch, or nil
--   Skills.points(level)               the points a level gives: level − 1 (none at level 1)
--   Skills.rank(skills, id)            the rank held (0 none)
--   Skills.spent(skills)               the points the ranks cost
--   Skills.spentIn(skills, branch)     … in one branch (an apex opens at Config.Skills.ApexNeeds)
--   Skills.free(skills, level)         the points left to spend
--   Skills.canBuy(skills, level, id)   ok, why (the words the client shows: "Max rank", "🔒 6", "Need 2 points")
--   Skills.buy(skills, level, id)      a new table with the rank more, or nil and why
--   Skills.clean(saved, level)         a save's ranks checked: known ids, whole ranks within each skill's, an apex only
--                                      over its branch's need; over the level's points: none (every point back)
--   Skills.effect(skills, key)         every rank's `effect[key]` added up (0 none)
--   Skills.carDamage(skills, cause)    the share of a hit your vehicle takes (Tough Body; Stuntman: "ram" 0, "crash" ½)
--   Skills.describe(def, rank)         what `rank` ranks of a skill give, with the game's real numbers ("Sprint 7.5 s")
--   Skills.encode(skills) / decode(text)  the player attribute's text ("longBreath:2,toughBody:1")

local Config = require(script.Parent.Config)

local Skills = {}

export type Ranks = { [string]: number }

local byId: { [string]: { def: Config.SkillDef, branch: Config.SkillBranch } } = {}
for _, branch in Config.Skills.Branches do
	for _, def in branch.skills do
		byId[def.id] = { def = def, branch = branch }
	end
end

function Skills.find(id: any): (Config.SkillDef?, Config.SkillBranch?)
	local found = if type(id) == "string" then byId[id] else nil
	if not found then
		return nil, nil
	end
	return found.def, found.branch
end

function Skills.points(level: number): number
	if type(level) ~= "number" or level ~= level then
		return 0
	end
	return math.max(0, math.floor(level) - 1) * Config.Skills.PerLevel
end

function Skills.rank(skills: Ranks?, id: string): number
	local value = if skills then skills[id] else nil
	return if type(value) == "number" and value == value then math.max(0, math.floor(value)) else 0
end

function Skills.spentIn(skills: Ranks?, branchId: string): number
	local total = 0
	for _, branch in Config.Skills.Branches do
		if branch.id == branchId then
			for _, def in branch.skills do
				total += Skills.rank(skills, def.id) * def.cost
			end
		end
	end
	return total
end

function Skills.spent(skills: Ranks?): number
	local total = 0
	for _, branch in Config.Skills.Branches do
		total += Skills.spentIn(skills, branch.id)
	end
	return total
end

function Skills.free(skills: Ranks?, level: number): number
	return math.max(0, Skills.points(level) - Skills.spent(skills))
end

function Skills.canBuy(skills: Ranks?, level: number, id: string): (boolean, string?)
	local def, branch = Skills.find(id)
	if not def or not branch then
		return false, "Unknown skill"
	end
	if Skills.rank(skills, id) >= def.ranks then
		return false, "Max rank"
	end
	if def.apex and Skills.spentIn(skills, branch.id) < Config.Skills.ApexNeeds then
		return false, `🔒 {Config.Skills.ApexNeeds}`
	end
	local free = Skills.free(skills, level)
	if free < def.cost then
		return false, if def.cost == 1 then "Need a point" else `Need {def.cost} points`
	end
	return true, nil
end

function Skills.buy(skills: Ranks?, level: number, id: string): (Ranks?, string?)
	local ok, why = Skills.canBuy(skills, level, id)
	if not ok then
		return nil, why
	end
	local out: Ranks = {}
	if skills then
		for key, value in skills do
			out[key] = value
		end
	end
	out[id] = Skills.rank(skills, id) + 1
	return out, nil
end

function Skills.clean(saved: any, level: number): Ranks
	local out: Ranks = {}
	if type(saved) ~= "table" then
		return out
	end
	for _, branch in Config.Skills.Branches do
		for _, def in branch.skills do
			local value = saved[def.id]
			if not def.apex and type(value) == "number" and value == value and value >= 1 then
				out[def.id] = math.clamp(math.floor(value), 1, def.ranks)
			end
		end
		-- (an apex only once the rest of its branch opens it)
		for _, def in branch.skills do
			local value = saved[def.id]
			if def.apex and type(value) == "number" and value == value and value >= 1 and Skills.spentIn(out, branch.id) >= Config.Skills.ApexNeeds then
				out[def.id] = math.clamp(math.floor(value), 1, def.ranks)
			end
		end
	end
	if Skills.spent(out) > Skills.points(level) then
		return {} -- (the level went down, the admin's doing: every point back)
	end
	return out
end

function Skills.effect(skills: Ranks?, key: string): number
	local total = 0
	if not skills then
		return total
	end
	for id, rank in skills do
		local def = Skills.find(id)
		local per = if def then def.effect[key] else nil
		if per and type(rank) == "number" then
			total += per * math.max(0, math.floor(rank))
		end
	end
	return total
end

-- The share of a hit your vehicle takes: Tough Body's −carDamage, and with Stuntman nothing from running a zombie over
-- ("ram") and half of a ram by a bandit car ("crash"). Never below 0.
function Skills.carDamage(skills: Ranks?, cause: string?): number
	local share = math.max(0, 1 - Skills.effect(skills, "carDamage"))
	if Skills.effect(skills, "stuntman") > 0 then
		if cause == "ram" then
			return 0
		elseif cause == "crash" then
			share *= 0.5
		end
	end
	return share
end

-- "7.5" / "30.2" / "2": a number with at most one decimal.
local function short(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return tostring(math.floor(rounded))
	end
	return string.format("%.1f", rounded)
end

local function percent(share: number): string
	return `{math.floor(share * 100 + 0.5)}%`
end

-- What `rank` ranks of a skill give in all (0: what you have without it), with the game's real numbers.
function Skills.describe(def: Config.SkillDef, rank: number): string
	local n = math.max(0, math.floor(rank))
	local e = def.effect
	local function of(key: string): number
		return (e[key] or 0) * n
	end
	if e.hands then
		local hands = Config.Cargo.HandsMax
		return `Hands {hands + of("hands")} pieces · bag +{of("bag")}`
	elseif e.sprintTime then
		return `Sprint {short(Config.Movement.Stamina + of("sprintTime"))} s`
	elseif e.tips then
		return `Tips +{percent(of("tips"))} of the pay`
	elseif e.sprintSpeed then
		return `Sprint speed {short(Config.Movement.Sprint * (1 + of("sprintSpeed")))}`
	elseif e.express then
		return if n > 0 then `+{percent(of("express"))} pay in time` else "No bonus"
	elseif e.carDamage then
		return `Vehicle damage −{percent(of("carDamage"))}`
	elseif e.handling then
		local serve = 3
		for _, job in Config.JobTypes do
			if job.unload == "serve" then
				serve = job.unloadTime
				break
			end
		end
		return `Serve {short(serve * math.max(0, 1 - of("handling")))} s`
	elseif e.fuel then
		return `Fuel burnt −{percent(of("fuel"))}`
	elseif e.repair then
		return `Repair fee −{percent(of("repair"))}`
	elseif e.stuntman then
		return if n > 0 then "Zombies cost the car 0 · rams ½" else "Full damage"
	elseif e.punch then
		return `Punch {Config.Melee.Kinds.punch.damage + of("punch")} damage`
	elseif e.spread then
		return `Spread −{percent(of("spread"))} · recoil −{percent(of("recoil"))}`
	elseif e.health then
		return `Health {Config.Skills.BaseHealth + of("health")}`
	elseif e.regen then
		return if n > 0 then `Healing +{percent(of("regen"))} · free medkit` else "Healing as usual"
	elseif e.secondWind then
		return if n > 0 then `A lethal hit: {Config.Skills.SecondWindHealth} health` else "No second chance"
	end
	return def.text
end

function Skills.encode(skills: Ranks?): string
	local parts: { string } = {}
	for _, branch in Config.Skills.Branches do
		for _, def in branch.skills do
			local rank = Skills.rank(skills, def.id)
			if rank > 0 then
				table.insert(parts, `{def.id}:{rank}`)
			end
		end
	end
	return table.concat(parts, ",")
end

function Skills.decode(text: any): Ranks
	local out: Ranks = {}
	if type(text) ~= "string" then
		return out
	end
	for id, rank in string.gmatch(text, "(%w+):(%d+)") do
		local def = Skills.find(id)
		if def then
			out[id] = math.clamp(tonumber(rank) or 0, 0, def.ranks)
		end
	end
	return out
end

return Skills
