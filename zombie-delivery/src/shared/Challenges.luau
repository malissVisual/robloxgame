--!strict
-- The challenges (3.1): goals across the whole game (kills, headshots, driving, missions, stars, places, secrets …),
-- each with a small reward (money, sometimes a title); every one of them done gives the rarest reward in the game
-- (Config.Rewards.Challenges: a gun nobody else has). Pure data and helpers: the server (server/Challenges.luau)
-- checks and pays them, the client (client/MissionsUi.luau, CHALLENGES tab) shows them, tests/challenges_test.luau
-- checks them.

local Config = require(script.Parent.Config)
local Missions = require(script.Parent.Missions)
local Levels = require(script.Parent.Levels)
local Map = require(script.Parent.Map)

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

-- The categories, in the order the CHALLENGES tab shows them.
Challenges.Categories = {
	{ id = "combat", name = "Combat" },
	{ id = "driving", name = "Driving" },
	{ id = "missions", name = "Missions" },
	{ id = "explorer", name = "Explorer" },
	{ id = "coop", name = "Co-op" },
	{ id = "wealth", name = "Wealth" },
} :: { { id: string, name: string } }

-- The goals that depend on the game's data (they grow with it, the descriptions follow).
local MISSIONS_TOTAL = #Missions.List -- 110 (3.2: with the DUO campaign)
local CAMPAIGNS_TOTAL = #Missions.Campaigns -- 11 (ten stories and the DUO campaign)
local _, STARS_TOTAL = Missions.stars({}) -- 330 (3 per mission)
local PLACES_TOTAL = #Map.Places -- 29
local MAX_LEVEL = Config.Levels.MaxLevel -- 15
local SECRETS_TOTAL = #Map.Secrets -- 30 (the lost packages)

-- The list, category by category, easy to hard. Money runs from 200 (minutes) to 20,000 (the long game); about ten
-- give a title, four are hidden (??? until done). There is no "every challenge" challenge: finishing all of them is
-- Config.Rewards.Challenges itself (Dead End).
Challenges.List = {
	-- ── Combat ──
	{ id = "first_blood", name = "First Blood", description = "Kill 10 zombies.", category = "combat", stat = "kills", goal = 10, money = 200 },
	{ id = "sharpshooter", name = "Sharpshooter", description = "Kill 25 zombies with a headshot.", category = "combat", stat = "headshots", goal = 25, money = 500 },
	{ id = "bigger_they_are", name = "The Bigger They Are", description = "Bring down 10 brutes.", category = "combat", stat = "brutes", goal = 10, money = 800 },
	{ id = "bandit_bounty", name = "Bandit Bounty", description = "Take out 25 bandits on foot.", category = "combat", stat = "bandits", goal = 25, money = 1500 },
	{ id = "demolition", name = "Demolition Crew", description = "Get 50 kills with explosions: grenades, molotovs, anything that goes boom.", category = "combat", stat = "explosions", goal = 50, money = 1500 },
	{ id = "horde_breaker", name = "Horde Breaker", description = "Kill 500 zombies.", category = "combat", stat = "kills", goal = 500, money = 2000 },
	{ id = "headhunter", name = "Headhunter", description = "Kill 250 zombies with a headshot.", category = "combat", stat = "headshots", goal = 250, money = 4000, title = "Headhunter" },
	{ id = "giant_slayer", name = "Giant Slayer", description = "Bring down 100 brutes.", category = "combat", stat = "brutes", goal = 100, money = 6000, title = "Giant Slayer" },
	{ id = "undertaker", name = "The Undertaker", description = "Kill 5,000 zombies.", category = "combat", stat = "kills", goal = 5000, money = 15000, title = "The Undertaker" },

	-- ── Driving ──
	{ id = "sunday_driver", name = "Sunday Driver", description = "Drive 25,000 studs.", category = "driving", stat = "distance", goal = 25000, money = 300 },
	{ id = "speed_bump", name = "Speed Bump", description = "Run over 50 zombies.", category = "driving", stat = "runOvers", goal = 50, money = 600 },
	{ id = "highway_patrol", name = "Highway Patrol", description = "Wreck 10 bandit cars.", category = "driving", stat = "banditCars", goal = 10, money = 2000 },
	{ id = "mounted_mayhem", name = "Mounted Mayhem", description = "Get 100 kills with a car gun.", category = "driving", stat = "carGunKills", goal = 100, money = 2500 },
	{ id = "long_haul", name = "Long Haul", description = "Drive 250,000 studs.", category = "driving", stat = "distance", goal = 250000, money = 3000 },
	{ id = "road_warrior", name = "Road Warrior", description = "Drive 1,000,000 studs.", category = "driving", stat = "distance", goal = 1000000, money = 12000, title = "Road Warrior" },

	-- ── Missions ──
	{ id = "on_the_clock", name = "On the Clock", description = "Finish 5 different missions.", category = "missions", stat = "missions", goal = 5, money = 500 },
	{ id = "story_time", name = "Story Time", description = "Finish 1 whole campaign (all of its missions).", category = "missions", stat = "campaigns", goal = 1, money = 1000 },
	{ id = "night_shift", name = "Night Shift", description = "Finish 15 missions at night.", category = "missions", stat = "nightMissions", goal = 15, money = 2000 },
	{ id = "hold_the_line", name = "Hold the Line", description = "Win 10 HOLD OUT fights.", category = "missions", stat = "defends", goal = 10, money = 2000 },
	{ id = "wave_rider", name = "Wave Rider", description = "Live through 100 zombie waves on a job.", category = "missions", stat = "waves", goal = 100, money = 2000 },
	{ id = "trusted_courier", name = "Trusted Courier", description = "Finish 25 different missions.", category = "missions", stat = "missions", goal = 25, money = 2500 },
	{ id = "flawless", name = "Flawless", description = "Finish 25 missions with 3 stars.", category = "missions", stat = "perfect", goal = 25, money = 2500 },
	{ id = "star_collector", name = "Star Collector", description = "Collect 100 mission stars.", category = "missions", stat = "stars", goal = 100, money = 3000 },
	{ id = "top_of_the_ladder", name = "Top of the Ladder", description = `Reach level {MAX_LEVEL}, the very top.`, category = "missions", stat = "level", goal = MAX_LEVEL, money = 10000 },
	{ id = "legendary_courier", name = "Legendary Courier", description = `Finish all {MISSIONS_TOTAL} missions.`, category = "missions", stat = "missions", goal = MISSIONS_TOTAL, money = 15000, title = "Legendary Courier" },
	{ id = "city_saviour", name = "Saviour of the City", description = `Finish all {CAMPAIGNS_TOTAL} campaigns.`, category = "missions", stat = "campaigns", goal = CAMPAIGNS_TOTAL, money = 20000 },
	{ id = "three_star_general", name = "Three-Star General", description = `Collect all {STARS_TOTAL} stars: 3 on every mission.`, category = "missions", stat = "stars", goal = STARS_TOTAL, money = 20000, title = "Three-Star General" },
	-- hidden: odd feats, ??? until done
	{ id = "ghost", name = "Ghost Courier", description = "Finish 1 NO SHOOTING mission without firing a single shot.", category = "missions", stat = "quietMissions", goal = 1, money = 2000, title = "The Ghost", hidden = true },
	{ id = "horse_whisperer", name = "Horse Whisperer", description = "Deliver 25 horses.", category = "missions", stat = "horses", goal = 25, money = 2500, title = "Horse Whisperer", hidden = true },
	{ id = "against_the_clock", name = "Against the Clock", description = "Finish 10 missions with the clock ticking.", category = "missions", stat = "rushes", goal = 10, money = 3000, hidden = true },

	-- ── Explorer ──
	{ id = "sightseer", name = "Sightseer", description = "Discover 5 places.", category = "explorer", stat = "visited", goal = 5, money = 300 },
	{ id = "lost_and_found", name = "Lost and Found", description = "Find 1 lost package.", category = "explorer", stat = "secrets", goal = 1, money = 300 },
	{ id = "package_sniffer", name = "Package Sniffer", description = "Find 10 lost packages.", category = "explorer", stat = "secrets", goal = 10, money = 2500 },
	{ id = "cartographer", name = "Cartographer", description = `Discover all {PLACES_TOTAL} places.`, category = "explorer", stat = "visited", goal = PLACES_TOTAL, money = 5000, title = "Cartographer" },
	{ id = "every_last_box", name = "Every Last Box", description = `Find all {SECRETS_TOTAL} lost packages.`, category = "explorer", stat = "secrets", goal = SECRETS_TOTAL, money = 10000 },

	-- ── Co-op ──
	{ id = "better_together", name = "Better Together", description = "Finish 1 mission with a crew mate.", category = "coop", stat = "coopMissions", goal = 1, money = 300 },
	{ id = "riding_shotgun", name = "Riding Shotgun", description = "Get 50 kills from a passenger seat.", category = "coop", stat = "gunnerKills", goal = 50, money = 1500 },
	{ id = "crew_chief", name = "Crew Chief", description = "Finish 25 missions with a crew mate.", category = "coop", stat = "coopMissions", goal = 25, money = 4000, title = "Crew Chief" },

	-- ── Wealth ──
	{ id = "first_paycheck", name = "First Paycheck", description = "Earn $10,000.", category = "wealth", stat = "earned", goal = 10000, money = 300 },
	{ id = "home_sweet_home", name = "Home Sweet Home", description = "Buy 1 property.", category = "wealth", stat = "properties", goal = 1, money = 1000 },
	{ id = "car_collector", name = "Car Collector", description = "Own 5 cars.", category = "wealth", stat = "cars", goal = 5, money = 2000 },
	{ id = "millionaire", name = "Millionaire", description = "Earn $1,000,000.", category = "wealth", stat = "earned", goal = 1000000, money = 10000, title = "Millionaire", hidden = true },
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
