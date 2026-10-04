--!strict
-- The missions (3.0): 10 campaigns of 10 story missions, 100 in all. A mission is a special job (Config.JobTypeDef,
-- played by server/Jobs.luau startMission) with a story around it: a briefing, a debrief line, twists
-- (Config.Missions.Twists), a reward for the first clear and a 1 – 3 star rating.
-- The campaigns unlock with the driver level; the missions of a campaign one after the other (the first is open,
-- each next one after the one before is done). Pure data and helpers: required by the server and the client, and by
-- tests/missions_test.luau.

local Config = require(script.Parent.Config)

local Missions = {}

export type Campaign = {
	id: string,
	name: string,
	client: string, -- who gives the missions ("Name, title")
	clientRole: string, -- their look (server/Npcs.luau role)
	icon: string, -- emoji
	color: { number }, -- RGB, the campaign's colour in the window
	level: number, -- the driver level that opens it
	pitch: string, -- one or two sentences: what this story is about
	reward: number, -- money for finishing all ten missions (once)
}

-- A mission: everything a JobTypeDef has (id = the mission id, mission = the same id), plus the story.
export type MissionDef = Config.JobTypeDef & {
	campaign: string,
	number: number, -- 1 … 10 in its campaign
	briefing: string, -- what the client says when you open it (two or three sentences, in character)
	debrief: string, -- what they say when it is done (one sentence)
	reward: number, -- money for the first clear (on top of the pay)
}

-- The ten stories, in the order they open.
Missions.Campaigns = {
	{ id = "dispatch", name = "First Shift", client = "Marge, the dispatcher", clientRole = "clerk", icon = "📦", color = { 255, 200, 70 }, level = 1, pitch = "Marge runs what is left of the city's dispatch office. Learn the streets, keep the parcels moving.", reward = 2500 },
	{ id = "clinic", name = "Code Red", client = "Dr. Novak, the clinic's doctor", clientRole = "doctor", icon = "🏥", color = { 240, 80, 80 }, level = 2, pitch = "The City Clinic is the last hospital open. Medicine, blood, vaccines and patients: every minute counts.", reward = 4000 },
	{ id = "market", name = "Empty Shelves", client = "Mr. Patel, FreshMart's owner", clientRole = "grocer", icon = "🛒", color = { 110, 200, 90 }, level = 3, pitch = "People are hungry. Fill the supermarket, the shelters and the soup kitchens before the city starves.", reward = 5500 },
	{ id = "firehouse", name = "Smoke and Sirens", client = "Chief Ramirez, Fire Station 9", clientRole = "officer", icon = "🚒", color = { 255, 120, 40 }, level = 4, pitch = "Fires, trapped survivors, dead pumps. The firefighters need a driver who does not panic.", reward = 7000 },
	{ id = "army", name = "Iron Supply", client = "Captain Reyes, the Military Base", clientRole = "soldier", icon = "🪖", color = { 130, 150, 90 }, level = 5, pitch = "The army holds the line at the base. Keep their guns fed, their trucks fuelled and their secrets safe.", reward = 9000 },
	{ id = "power", name = "Lights Out", client = "Engineer Volkov, the Power Plant", clientRole = "foreman", icon = "⚡", color = { 90, 180, 255 }, level = 6, pitch = "The grid is failing block by block. Batteries, generators and spare parts: bring the lights back.", reward = 11000 },
	{ id = "ranch", name = "Wild West End", client = "Walt, the rancher", clientRole = "rancher", icon = "🐴", color = { 200, 150, 90 }, level = 7, pitch = "Out west the bandits rule the roads. Walt's horses, the farm's food and a feud that ends with you.", reward = 13000 },
	{ id = "lab", name = "Patient Zero", client = "Dr. Ito, the Biotech Lab", clientRole = "doctor", icon = "🧪", color = { 160, 110, 255 }, level = 9, pitch = "Dr. Ito is close to a cure. Samples, explosives and things nobody should see: handle with care.", reward = 16000 },
	{ id = "underworld", name = "Dirty Money", client = "Vinnie, the fixer", clientRole = "banker", icon = "💰", color = { 230, 200, 60 }, level = 11, pitch = "Vinnie pays the best and asks no questions. Cash, gold, stolen art: everybody wants what is in your trunk.", reward = 20000 },
	{ id = "exodus", name = "Last Convoy", client = "Mayor Grant, City Hall", clientRole = "clerk", icon = "🚌", color = { 255, 255, 255 }, level = 13, pitch = "The city is falling. Get the survivors to the airfield and the lighthouse before the last plane and the last boat leave.", reward = 30000 },
} :: { Campaign }

-- Every mission, campaign by campaign (10 each), filled in by shared/Missions data below.
Missions.List = {} :: { MissionDef }

-- ── The missions ──────────────────────────────────────────────────────────
-- (stream "missions-data" writes all 100; one example here)
table.insert(Missions.List, {
	id = "dispatch_1",
	mission = "dispatch_1",
	campaign = "dispatch",
	number = 1,
	name = "Paper Trail",
	description = "Three parcels from the dispatch office to a family across town.",
	briefing = "New kid, huh? Fine. Three parcels, one address, no excuses. Carry them, load them, bring them. Easy.",
	debrief = "Huh. You did not crash. You might last a week.",
	reward = 300,
	vehicle = nil,
	employer = nil,
	pickups = 1,
	pickupAt = nil,
	drops = 1,
	dropAt = nil,
	loadTime = 3,
	unloadTime = 3,
	payPerStop = 40,
	tier = 1,
	cargo = "Parcels",
	pickupLabel = "PICK UP THE PARCELS AT",
	dropLabel = "DELIVER THE PARCELS TO",
	load = "carry",
	unload = "carry",
	items = 3,
	itemKind = "parcel",
	giver = "Marge, the dispatcher",
	receiver = "The Hendersons, a family",
	giverRole = "clerk",
	receiverRole = "townsperson",
	level = 1,
	twists = {},
})

-- ── Helpers ───────────────────────────────────────────────────────────────

local byId: { [string]: MissionDef } = {}
local indexed = 0
local function index(): { [string]: MissionDef }
	if indexed ~= #Missions.List then
		table.clear(byId)
		for _, def in Missions.List do
			byId[def.id] = def
		end
		indexed = #Missions.List
	end
	return byId
end

function Missions.find(id: string): MissionDef?
	return index()[id]
end

function Missions.findCampaign(id: string): Campaign?
	for _, campaign in Missions.Campaigns do
		if campaign.id == id then
			return campaign
		end
	end
	return nil
end

-- The missions of a campaign, in order.
function Missions.ofCampaign(campaignId: string): { MissionDef }
	local list = {}
	for _, def in Missions.List do
		if def.campaign == campaignId then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return a.number < b.number
	end)
	return list
end

-- Is the mission open for a player of `level` with `progress` ({ [mission id] = best stars })? Its campaign's level,
-- and the mission before it in the campaign done. Says why not.
function Missions.unlocked(id: string, progress: { [string]: number }, level: number): (boolean, string?)
	local def = Missions.find(id)
	if not def then
		return false, "Unknown mission."
	end
	local campaign = Missions.findCampaign(def.campaign)
	if campaign and level < campaign.level then
		return false, `{campaign.name} opens at level {campaign.level}.`
	end
	if def.level and level < def.level then
		return false, `This mission needs level {def.level}.`
	end
	if def.number > 1 then
		local before = `{def.campaign}_{def.number - 1}`
		if (progress[before] or 0) < 1 then
			return false, "Finish the mission before it first."
		end
	end
	return true, nil
end

-- The rating of a finished mission: condition 0 … 1 of the cargo, timeShare 0 … 1 of the clock left.
function Missions.rate(condition: number, timeShare: number): number
	local tuning = Config.Missions
	if condition < tuning.TwoStarCondition then
		return 1
	end
	if timeShare < tuning.ThreeStarTime then
		return 2
	end
	return 3
end

-- Stars collected: this campaign (or all with nil), and the most there are.
function Missions.stars(progress: { [string]: number }, campaignId: string?): (number, number)
	local got, most = 0, 0
	for _, def in Missions.List do
		if campaignId == nil or def.campaign == campaignId then
			got += math.clamp(progress[def.id] or 0, 0, 3)
			most += 3
		end
	end
	return got, most
end

-- Missions done (any rating) in a campaign, and how many it has.
function Missions.done(progress: { [string]: number }, campaignId: string): (number, number)
	local got, total = 0, 0
	for _, def in Missions.List do
		if def.campaign == campaignId then
			total += 1
			if (progress[def.id] or 0) >= 1 then
				got += 1
			end
		end
	end
	return got, total
end

-- How much more a mission pays for its twists (the product of Config.Missions.Twists pay).
function Missions.twistPay(def: Config.JobTypeDef): number
	local multiplier = 1
	local twists: { string } = def.twists or {}
	for _, twist in twists do
		local info = Config.Missions.Twists[twist]
		if info then
			multiplier *= info.pay
		end
	end
	return multiplier
end

return Missions
