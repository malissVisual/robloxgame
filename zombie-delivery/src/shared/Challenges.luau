--!strict
-- The challenges (3.1): goals across the whole game (kills, headshots, driving, missions, stars, places, secrets …),
-- each with a small reward (money, sometimes a title); every one of them done gives the rarest reward in the game
-- (Config.Rewards.Challenges: a gun nobody else has). Pure data and helpers: the server (server/Challenges.luau)
-- checks and pays them, the client (client/MissionsUi.luau, CHALLENGES tab) shows them, tests/challenges_test.luau
-- checks them.

local Config = require(script.Parent.Config)
local Missions = require(script.Parent.Missions)
local Levels = require(script.Parent.Levels)

local Challenges = {}

-- The counters the server keeps in profile.stats (only these are saved; server/Challenges.luau counts them).
Challenges.Counters = {
	"headshots", -- zombies killed by a headshot
	"brutes", -- brutes killed
	"bandits", -- bandits killed (on foot)
	"banditCars", -- bandit cars destroyed
	"runOvers", -- zombies run over with a car
	"carGunKills", -- kills with a car gun
	"gunnerKills", -- kills from a passenger seat
	"explosions", -- kills with explosions (launcher, molotov …)
	"distance", -- studs driven (as the driver)
	"waves", -- zombie waves lived through on a job
	"defends", -- HOLD OUT twists won
	"coopMissions", -- missions finished with at least one crew mate
	"nightMissions", -- missions finished at night
	"perfect", -- missions finished with 3 stars (each time)
	"rushes", -- missions with a fixed clock (timeLimit) finished
	"passengers", -- kids, patients and survivors brought (board pieces delivered)
	"horses", -- horses delivered
	"pieces", -- pieces of cargo delivered (any)
	"quietMissions", -- NO SHOOTING missions finished without a shot
} :: { string }

-- What a challenge measures: a counter above, or one of these read from the profile:
--   kills, deliveries, earned (profile), level (Levels), stars, missions (done), campaigns (done),
--   secrets (found), visited (places), titles (earned), properties (owned), cars (owned), weapons (owned)
export type ChallengeDef = {
	id: string,
	name: string,
	description: string,
	category: string, -- combat | driving | missions | explorer | coop | wealth
	stat: string,
	goal: number,
	money: number, -- paid once when done
	title: string?, -- a title earned with it
	hidden: boolean?, -- shown as ??? until done (a secret challenge)
}

-- [contract stub: stream "challenges-data" writes the list (about 40)]
Challenges.List = {
	{ id = "first_blood", name = "First Blood", description = "Kill 10 zombies.", category = "combat", stat = "kills", goal = 10, money = 200 },
	{ id = "headhunter", name = "Headhunter", description = "Kill 100 zombies with a headshot.", category = "combat", stat = "headshots", goal = 100, money = 2000, title = "Headhunter" },
} :: { ChallengeDef }

export type ProfileLike = {
	kills: number?,
	deliveries: number?,
	earned: number?,
	xp: number?,
	stats: { [string]: number }?,
	missions: { [string]: number }?,
	campaigns: { [string]: boolean }?,
	secrets: { [string]: boolean }?,
	visited: { [string]: boolean }?,
	titles: { [string]: boolean }?,
	properties: { [string]: boolean }?,
	cars: { [string]: boolean }?,
	weapons: { [string]: boolean }?,
	challenges: { [string]: boolean }?,
}

local function count(set: { [string]: any }?): number
	local n = 0
	local list: { [string]: any } = set or {}
	for _, value in list do
		if value then
			n += 1
		end
	end
	return n
end

-- The current value of a stat for a profile.
function Challenges.value(profile: ProfileLike, stat: string): number
	if stat == "kills" then
		return profile.kills or 0
	elseif stat == "deliveries" then
		return profile.deliveries or 0
	elseif stat == "earned" then
		return profile.earned or 0
	elseif stat == "level" then
		return Levels.levelFor(profile.xp or 0)
	elseif stat == "stars" then
		return (Missions.stars(profile.missions or {}))
	elseif stat == "missions" then
		return count(profile.missions)
	elseif stat == "campaigns" then
		local done = 0
		for _, campaign in Missions.Campaigns do
			local got, total = Missions.done(profile.missions or {}, campaign.id)
			if total > 0 and got >= total then
				done += 1
			end
		end
		return done
	elseif stat == "secrets" then
		return count(profile.secrets)
	elseif stat == "visited" then
		return count(profile.visited)
	elseif stat == "titles" then
		return count(profile.titles)
	elseif stat == "properties" then
		return count(profile.properties)
	elseif stat == "cars" then
		return count(profile.cars)
	elseif stat == "weapons" then
		return count(profile.weapons)
	end
	local stats = profile.stats
	return if stats then stats[stat] or 0 else 0
end

function Challenges.find(id: string): ChallengeDef?
	for _, def in Challenges.List do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- 0 … 1 toward the goal, and whether it is reached.
function Challenges.progress(def: ChallengeDef, profile: ProfileLike): (number, boolean)
	local value = Challenges.value(profile, def.stat)
	return math.clamp(value / def.goal, 0, 1), value >= def.goal
end

-- How many challenges are done (profile.challenges) out of all of them.
function Challenges.doneCount(profile: ProfileLike): (number, number)
	local done = 0
	for _, def in Challenges.List do
		if profile.challenges and profile.challenges[def.id] then
			done += 1
		end
	end
	return done, #Challenges.List
end

-- Every title the game can give: the campaigns', the secrets', the last challenge's and the challenges' own.
function Challenges.allTitles(): { string }
	local list: { string } = {}
	for _, campaign in Missions.Campaigns do
		local reward = Config.Rewards.Campaigns[campaign.id]
		if reward then
			table.insert(list, reward.title)
		end
	end
	table.insert(list, Config.Rewards.Secrets.title)
	for _, def in Challenges.List do
		if def.title then
			table.insert(list, def.title)
		end
	end
	table.insert(list, Config.Rewards.Challenges.title)
	return list
end

return Challenges
