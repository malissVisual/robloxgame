--!strict
-- The missions (3.0), told as story chapters (6.8): every client (shared/Cast.luau) has ONE chapter of six missions
-- that follow each other, each briefing picking up where the last debrief stopped, and a finale that pays the
-- chapter's big reward. A mission is a special job (Config.JobTypeDef, played by server/Jobs.luau startMission) with a
-- story around it: a briefing, a debrief line, twists (Config.Missions.Twists), a first-time reward and a 1 – 3 star
-- rating. Pure data and helpers: required by the server, the client and tests/missions*_test.luau.
--
-- 6.8, the chapters (the owner: "I want to see who I go to for a set of missions, and the sets should tell a story,
-- one mission after another; a mission pays its rewards once, after that only something small"):
--   * Campaign.clientId names the client (Cast); the chapter is the campaign's missions in their `number` order
--     (1 … 6). Only the NEXT one (the first not done) can be started; the later ones say "Finish 'X' first", the
--     done ones replay (Missions.unlocked / statusOf).
--   * The mission ids stay what 3.0 – 6.7 saved ("clinic_7"): the chapters kept six of the ten old missions of every
--     campaign, in their old order, so a save's ratings still mean the same missions. The four others of each are
--     retired (Missions.isRetired: their saved stars stay in the save, nothing counts them); a chapter's first and
--     last missions are the old first and finale, so `finished` (the finale done) means what it meant.
--   * First time vs replay: the first clear pays the mission's reward and the first-clear XP (server/Missions.luau),
--     the chapter's finale the campaign's reward (money, and Config.Rewards.Campaigns' gun or paint and title, once);
--     a replay pays Config.Missions.ReplayPay of the job's pay and ReplayXp of its XP, nothing else
--     (Missions.replayPay / replayXp, server/Jobs.luau).
--   * The chain stays 3.2's: every story chapter `requires` the one before it (Exodus all nine), then its level; the
--     missions' levels grow inside a chapter from the campaign's level to the next one's (Missions.levelOf).
--   * The DUO chapter (Rosa & Rico, Campaign.duo, every mission duo = true and coop = true) needs a partner at START
--     (Config.Missions.Duo, server/Missions.luau). It is a side story: nothing in the main chain requires it.

local Config = require(script.Parent.Config)
local Cast = require(script.Parent.Cast)

local Missions = {}

export type Campaign = {
	id: string,
	name: string, -- the chapter's title ("Code Red")
	clientId: string, -- 6.8: the client (shared/Cast.luau): their name, role line, place and look (the portrait)
	client: string, -- who gives the missions ("Doctor Ellie, the City Clinic"), from the Cast
	clientRole: string, -- their look (an NPC role, shared/NpcLooks.luau), from the Cast
	partnerId: string?, -- 6.8: a second face in the portrait (the DUO twins)
	icon: string, -- emoji
	color: { number }, -- RGB, the chapter's colour (the portrait's background, the rules)
	level: number, -- the driver level that opens it
	pitch: string, -- two or three sentences: what this story is about
	reward: number, -- money for the finale (the whole chapter done, once)
	requires: { string }?, -- campaigns whose finale must be done before this one opens
	duo: boolean?, -- 3.2: a DUO chapter: every mission only with a partner (Config.Missions.Duo)
}

-- A mission: everything a JobTypeDef has (id = the mission id, mission = the same id), plus the story.
export type MissionDef = Config.JobTypeDef & {
	campaign: string,
	number: number, -- 6.8: its step in the chapter, 1 … 6 (the id keeps the 3.0 number: "clinic_7" is step 5)
	briefing: string, -- what the client says when you open it (two to four sentences, in character)
	debrief: string, -- what they say when it is done (it leads into the next mission)
	reward: number, -- money for the first clear (on top of the pay)
	-- 3.2, the switches twist: where the two-lever gate stands. "drop" (the default) = the last drop, "pickup" =
	-- every pick-up (server/Jobs.luau, server/DuoGates.luau).
	gates: string?,
}

-- 3.2: how many levels the DUO chapter's missions span (a side story: not tied to the next story chapter).
local DUO_SPAN = 4
-- 6.8: the ids every campaign had before the chapters (<campaign>_1 … _10); the ones not in a chapter are retired.
local OLD_SIZE = 10

-- A campaign's client from the Cast (its name line and its look).
local function client(id: string): (string, string)
	local person = Cast.find(id)
	return if person then person.label else id, if person then person.look else "townsperson"
end

local function campaign(info: { [string]: any }): Campaign
	local label, look = client(info.clientId)
	info.client = label
	info.clientRole = look
	return (info :: any) :: Campaign
end

-- The chapters, in the order they open (each `requires` the one before it; the DUO chapter only First Shift).
Missions.Campaigns = {
	campaign({ id = "dispatch", name = "First Shift", clientId = "marge", icon = "📦", color = { 255, 200, 70 }, level = 4, reward = 2500,
		pitch = "Marge runs Dead End Dispatch, the last courier office in a city that ate its own post office. Your van is new and the streets are not: keep the parcels moving, and find out who wants the dispatch shut." }),
	campaign({ id = "clinic", name = "Code Red", clientId = "ellie", icon = "🏥", color = { 240, 80, 80 }, level = 5, reward = 4000, requires = { "dispatch" },
		pitch = "The City Clinic is the last hospital still open, and Doctor Ellie runs it on coffee and spite. Pills, patients, power, and then a strain of the virus nobody has seen before." }),
	campaign({ id = "market", name = "Empty Shelves", clientId = "raj", icon = "🛒", color = { 110, 200, 90 }, level = 6, reward = 5500, requires = { "clinic" },
		pitch = "FreshMart has been open for thirty-two years, and Raj won't let the apocalypse close it. The shelves are empty, the farm road belongs to bandits, and a man called Tusk wants the city's food for himself." }),
	campaign({ id = "duo", name = "Partners in Crime", clientId = "rosa", partnerId = "rico", icon = "🤝", color = { 236, 92, 60 }, level = 6, reward = 7500, requires = { "dispatch" }, duo = true,
		pitch = "Rosa plans, Rico jokes, and neither of them ever works alone. Every job is made for two: pieces two of you carry, gates two of you open. Bring a partner, and help them settle a score with Tusk." }),
	campaign({ id = "firehouse", name = "Smoke and Sirens", clientId = "carlos", icon = "🚒", color = { 255, 120, 40 }, level = 7, reward = 7000, requires = { "market" },
		pitch = "Fire Station 9 has the last working engine in the city, and Chief Carlos needs a driver who doesn't panic. Hoses, fuel, dynamite and foam, until the whole east side goes up." }),
	campaign({ id = "army", name = "Iron Supply", clientId = "maria", icon = "🪖", color = { 130, 150, 90 }, level = 9, reward = 9000, requires = { "firehouse" },
		pitch = "The army holds the line at the Military Base, and the scouts say the big horde is coming down from the mountains. Ammo, food, dynamite and eyes on the coast: get the base ready before it hits." }),
	campaign({ id = "power", name = "Lights Out", clientId = "ivan", icon = "⚡", color = { 90, 180, 255 }, level = 10, reward = 11000, requires = { "army" },
		pitch = "The grid is failing block by block, and Engineer Ivan holds it together with spare parts and stubbornness. Turbines, batteries, copper thieves and a plant that wants to boil over: bring the lights back." }),
	campaign({ id = "ranch", name = "Wild West End", clientId = "walt", icon = "🐴", color = { 200, 150, 90 }, level = 11, reward = 13000, requires = { "power" },
		pitch = "Out west the Rust Riders rule the roads, and Walt's ranch is the last thing between them and the farms. Horses, feed, rustlers and rifles: a feud that ends with you." }),
	campaign({ id = "lab", name = "Patient Zero", clientId = "hiro", icon = "🧪", color = { 160, 110, 255 }, level = 12, reward = 16000, requires = { "ranch" },
		pitch = "Doctor Hiro's booster buys a bitten person one day. He wants a cure. Equipment, freezers, power, and the woman who was bitten on day one and never turned: handle with care." }),
	campaign({ id = "underworld", name = "Dirty Money", clientId = "vinnie", icon = "💰", color = { 230, 200, 60 }, level = 13, reward = 20000, requires = { "lab" },
		pitch = "Vinnie runs Second Life Pawn, pays the best and asks no questions. Ticking boxes, dirty cash, stolen paintings and a rival with a boat: everybody wants what is in your trunk." }),
	campaign({ id = "exodus", name = "Last Convoy", clientId = "ruth", icon = "🚌", color = { 235, 235, 240 }, level = 14, reward = 30000, requires = { "dispatch", "clinic", "market", "firehouse", "army", "power", "ranch", "lab", "underworld" },
		pitch = "Mayor Ruth says it out loud: the city is lost. The cure has to get out, and so do the people. The plans, the fuel, the seed vault, her own kids, the last boat and the last plane." }),
} :: { Campaign }

-- Every mission, chapter by chapter, filled in by the data below.
Missions.List = {} :: { MissionDef }

-- ── The missions ──────────────────────────────────────────────────────────
-- Written compactly: a Spec is a MissionDef without what add() derives: the id ("<campaign>_<id>", id = the 3.0
-- number, kept for the saves), the step (`number`, the order of the add() calls), the level (Missions.levelOf) and
-- loadTime / unloadTime (3 s, a serve stop 4 s). giver / receiver may be a Cast id ("ellie"): then the label and the
-- look come from the Cast. Notes for whoever writes more:
--   * pickupAt only with pickups = 1 (every pick-up would be at that place); pickups = 0: the vehicle starts loaded.
--   * dropAt is the LAST drop's place; the drops before it are addresses on the way.
--   * a rush (timeLimit) starts at an address near you (no pickupAt) and never has defend.
--   * horse = lead (livestock truck); kid / patient / survivor = board; serve = street selling (icebox, pizza,
--     bread, soup) after a carry load.
--   * lift and gunner are crew twists: their missions are coop. defend needs defendTime.
--   * labels: the pick-up label ends with AT (" at <place>" is added), the drop label is followed by the place.
--   * a DUO mission (any mission of the DUO chapter) is co-op too; pair needs carrying; switches puts its gate at
--     the last drop (gates = "pickup": at every pick-up).
--   * the pieces must fit a car the player can have at the mission's level (tests/capacity_test.luau); five and
--     more say "load" in the description.

type Spec = {
	id: number,
	name: string,
	level: number?, -- an override; computed by add() (Missions.levelOf) without it
	tier: number,
	reward: number,
	coop: boolean?,
	gates: string?,
	twists: { string },
	defendTime: number?,
	description: string,
	briefing: string,
	debrief: string,
	vehicle: string?,
	load: string,
	unload: string,
	itemKind: string,
	items: number,
	cargo: string,
	pickups: number,
	pickupAt: string?,
	drops: number,
	dropAt: string?,
	loadTime: number?,
	unloadTime: number?,
	payPerStop: number,
	timeLimit: number?,
	banditBoost: number?,
	pickupLabel: string,
	dropLabel: string,
	giver: string, -- a Cast id, or "Name, title" for somebody who only shows up here
	giverRole: string?, -- the look of a giver who is not in the Cast
	receiver: string,
	receiverRole: string?,
}

local function campaignById(campaignId: string): Campaign?
	for _, entry in Missions.Campaigns do
		if entry.id == campaignId then
			return entry
		end
	end
	return nil
end

-- How many missions a chapter has (counted as add() goes; complete once this module has loaded).
local sizes: { [string]: number } = {}

-- The levels a chapter's missions span: from its own level (mission 1) to the next story chapter's (its finale;
-- MaxLevel after the last one). The DUO chapter is a side story: its own level + DUO_SPAN.
local function levelSpan(campaignId: string): (number, number)
	local campaigns = Missions.Campaigns
	local maxLevel = Config.Levels.MaxLevel
	for index, entry in campaigns do
		if entry.id ~= campaignId then
			continue
		end
		if entry.duo then
			return entry.level, math.min(maxLevel, entry.level + DUO_SPAN)
		end
		for after = index + 1, #campaigns do
			local following = campaigns[after]
			if not following.duo then
				return entry.level, math.clamp(following.level, entry.level, maxLevel)
			end
		end
		return entry.level, math.max(entry.level, maxLevel)
	end
	return 1, 1
end

-- The driver level a chapter's mission at step `number` needs: from the chapter's level (step 1) up to the top of its
-- span (the finale), rounded down (6.8: the story itself carries you there, tests/levels_test.luau; First Shift
-- 4 → 5: steps 1 – 5 at level 4, the finale at 5). `size` defaults to the chapter's length.
function Missions.levelOf(campaignId: string, number: number, size: number?): number
	local low, high = levelSpan(campaignId)
	local count = math.max(2, size or sizes[campaignId] or 6)
	local share = (math.clamp(number, 1, count) - 1) / (count - 1)
	return low + math.floor((high - low) * share + 1e-6)
end

-- A giver / receiver: a Cast id gives its label and look; anything else is written by hand (with its role).
local function person(text: string, role: string?): (string, string)
	local known = Cast.find(text)
	if known then
		return known.label, known.look
	end
	return text, role or "townsperson"
end

local pendingLevels: { MissionDef } = {}

local function add(campaignId: string, spec: Spec)
	local id = `{campaignId}_{spec.id}`
	local info = campaignById(campaignId)
	local duo = info ~= nil and info.duo == true
	local step = (sizes[campaignId] or 0) + 1
	sizes[campaignId] = step
	local giver, giverRole = person(spec.giver, spec.giverRole)
	local receiver, receiverRole = person(spec.receiver, spec.receiverRole)
	local def: MissionDef = {
		id = id,
		mission = id,
		campaign = campaignId,
		number = step,
		name = spec.name,
		description = spec.description,
		briefing = spec.briefing,
		debrief = spec.debrief,
		reward = spec.reward,
		vehicle = spec.vehicle,
		employer = nil,
		pickups = spec.pickups,
		pickupAt = spec.pickupAt,
		drops = spec.drops,
		dropAt = spec.dropAt,
		loadTime = spec.loadTime or 3,
		unloadTime = spec.unloadTime or (if spec.unload == "serve" then 4 else 3),
		payPerStop = spec.payPerStop,
		tier = spec.tier,
		cargo = spec.cargo,
		pickupLabel = spec.pickupLabel,
		dropLabel = spec.dropLabel,
		load = spec.load,
		unload = spec.unload,
		items = spec.items,
		itemKind = spec.itemKind,
		giver = giver,
		receiver = receiver,
		giverRole = giverRole,
		receiverRole = receiverRole,
		timeLimit = spec.timeLimit,
		banditBoost = spec.banditBoost,
		level = spec.level, -- (filled in once the chapter's length is known, below the data)
		twists = spec.twists,
		defendTime = spec.defendTime,
		coop = if spec.coop or duo then true else nil,
		duo = if duo then true else nil,
		gates = spec.gates,
	}
	table.insert(Missions.List, def)
	if spec.level == nil then
		table.insert(pendingLevels, def)
	end
end

-- ── 1. First Shift (Marge, the dispatcher) ───────────────────────────────
-- Your first week with a van: parcels, the post office's lost mail, a birthday, files the bandits want, the bandits'
-- answer (every van's tires slashed), and the dispatch moving into the Stadium Shelter.
do
	add("dispatch", {
		id = 1, name = "Paper Trail", tier = 1, reward = 400, twists = {},
		description = "Two parcels from a sorting room to a family across town. Your first run with the van.",
		briefing = "So you're the one with the van. Good, because the last courier had a bicycle and a lot of optimism. Two parcels, one family across town. Carry them, load them, bring them. Easy.",
		debrief = "Huh. You came back. With the van. The bar is low, but you cleared it.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "parcel", items = 2, cargo = "Parcels",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = nil, payPerStop = 40,
		pickupLabel = "PICK UP THE PARCELS AT", dropLabel = "DELIVER THE PARCELS TO",
		giver = "marge", receiver = "Jenny's family", receiverRole = "townsperson",
	})
	add("dispatch", {
		id = 2, name = "Mail Call", tier = 1, reward = 550, twists = {},
		description = "Two sacks of old mail for two streets that have not seen a letter since the outbreak.",
		briefing = "Jenny's family told the whole street a real courier came by, and now Otto is at my desk. He kept two sacks of letters since the post office burned down in week two. Two streets, two sacks. People want their mail, even the bills. Especially the bills, weirdly.",
		debrief = "Edna got a postcard from her son. She cried. I did not. Shut up. Oh, and one of those letters was a party invitation.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "mail", items = 2, cargo = "Mail Sacks",
		pickups = 1, pickupAt = nil, drops = 2, dropAt = nil, payPerStop = 50,
		pickupLabel = "LOAD THE MAIL SACKS AT", dropLabel = "DROP THE MAIL AT",
		giver = "otto", receiver = "Edna, a neighbour", receiverRole = "townsperson",
	})
	add("dispatch", {
		id = 3, name = "Birthday Emergency", tier = 1, reward = 700, twists = { "spotless" },
		description = "Two birthday cakes from the bakery to a party, on a four minute clock. Not a smudge.",
		briefing = "That invitation was from Timmy's mom: he turns eight today, and she asked for a courier, not a miracle. Rosie baked two cakes. Four minutes to the party, and if the frosting so much as smudges, don't bother coming back.",
		debrief = "Timmy says it was the best cake of the apocalypse. His uncle Percy works at City Hall, by the way. He'd like a word with you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "cake", items = 2, cargo = "Birthday Cakes",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = nil, payPerStop = 60, timeLimit = 240,
		pickupLabel = "PICK UP THE CAKES AT", dropLabel = "DELIVER THE CAKES TO",
		giver = "rosie", receiver = "Timmy's mom, at the party", receiverRole = "townsperson",
	})
	add("dispatch", {
		id = 8, name = "Dead Letter Office", tier = 2, reward = 900, twists = { "hunted" },
		description = "Files from City Hall to Precinct 13. Bandit cars hunt you the whole way.",
		briefing = "Timmy's uncle Percy found files at City Hall on who sold the army's food to the bandits. Detective Sue at Precinct 13 wants them. So does every bandit with a car. Drive fast, don't stop, and don't read them.",
		debrief = "Sue made two arrests before lunch. Somebody out there is very angry with my courier. Welcome to the job.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "documents", items = 2, cargo = "Secret Files",
		pickups = 1, pickupAt = "cityhall", drops = 1, dropAt = "police", payPerStop = 160,
		pickupLabel = "PICK UP THE FILES AT", dropLabel = "HAND THE FILES TO",
		giver = "percy", receiver = "sue",
	})
	add("dispatch", {
		id = 9, name = "Wheels of Commerce", tier = 2, reward = 1200, coop = true, twists = { "guarded" },
		description = "Two tire stacks from the Harbor Warehouse: one for a van on its rims in town, one to the Gas Station. Hordes at every stop.",
		briefing = "Last night somebody slashed the tires of every van in my yard. I wonder who. Rocco at the Harbor Warehouse still has tires, and Tony at the Gas Station still has a jack. Both have a horde parked outside. Bring friends with big guns.",
		debrief = "Every van back on the road, and the bandits know we don't scare. My dispatch board finally has colour on it again. And I have news.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tires", items = 2, cargo = "Tires",
		pickups = 1, pickupAt = "warehouse", drops = 2, dropAt = "gas", loadTime = 4, payPerStop = 200,
		pickupLabel = "LOAD THE TIRES AT", dropLabel = "DROP THE TIRES AT",
		giver = "rocco", receiver = "tony",
	})
	add("dispatch", {
		id = 10, name = "Rush Hour of the Dead", tier = 3, reward = 2000, coop = true, twists = { "defend", "gunner" }, defendTime = 45,
		description = "The dispatch moves into the Stadium Shelter: two old sorting rooms to empty, then the stadium's gate to hold.",
		briefing = "The news: Dead End Dispatch gets a desk inside the Stadium Shelter, behind real walls. Everything left in our two old sorting rooms moves there today, and a crowd that big brings the dead running. Load up, then hold the gate while Coach Dan's people carry it in. This is the big one, rookie.",
		debrief = "Every letter is behind the stadium walls. You're not a rookie anymore, you're a courier. Doctor Ellie at the clinic asked me for my best driver. I gave her your number.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "parcel", items = 2, cargo = "The Last Mail",
		pickups = 2, pickupAt = nil, drops = 1, dropAt = "stadium", payPerStop = 220,
		pickupLabel = "EMPTY THE SORTING ROOM AT", dropLabel = "DELIVER THE MAIL TO",
		giver = "Ben, a sorting clerk", giverRole = "clerk", receiver = "dan",
	})
end

-- ── 2. Code Red (Doctor Ellie, the City Clinic) ─────────────────────────────
-- Heart pills, a heart attack, the generators, three patients with the same fever, a new strain's samples and the
-- booster for the whole Stadium Shelter.
do
	add("clinic", {
		id = 1, name = "House Call", tier = 1, reward = 550, twists = {},
		description = "Heart pills from the Corner Pharmacy to an old lady who will not leave her house.",
		briefing = "Marge says you're her best driver, which is either a compliment or a warning. Greta's heart pills ran out and she won't leave her house. Petra at the Corner Pharmacy has two boxes behind the counter. Hurry: she's ninety-one and very rude when she's scared.",
		debrief = "Greta says you were late. That means she's feeling better. Her neighbour, on the other hand...",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "medicine", items = 2, cargo = "Heart Pills",
		pickups = 1, pickupAt = "pharmacy", drops = 1, dropAt = nil, payPerStop = 50,
		pickupLabel = "PICK UP THE MEDICINE AT", dropLabel = "BRING THE MEDICINE TO",
		giver = "petra", receiver = "Greta, a patient at home", receiverRole = "townsperson",
	})
	add("clinic", {
		id = 2, name = "Code Blue", tier = 1, reward = 700, twists = {},
		description = "A heart attack across town: the ambulance, the patient, the clinic. Three minutes.",
		briefing = "Greta's neighbour just collapsed in his kitchen, and no, he was not bitten, I checked over the radio. Take the ambulance, sirens on, three minutes. He walks slowly, so park close and be patient. Ha. Patient.",
		debrief = "Stable. Thanks to you. And to me. Mostly to me. Now, about my lights...",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 1, cargo = "Patient",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "clinic", payPerStop = 80, timeLimit = 180,
		pickupLabel = "PICK UP THE PATIENT AT", dropLabel = "RUSH THE PATIENT TO",
		giver = "Ingrid, his wife", giverRole = "townsperson", receiver = "ada",
	})
	add("clinic", {
		id = 4, name = "Many Hands", tier = 2, reward = 950, coop = true, twists = { "lift" },
		description = "Two backup generators for the operating room. Each one is a two-person carry.",
		briefing = "The backup generator coughed and died while I was stitching up Greta's neighbour. Rocco at the Harbor Warehouse has two spares, each heavier than a cow. Bring a friend, or my operating room stays lit by phone flashlights.",
		debrief = "Lights on, machines beeping. The most beautiful sound in the world. It lasted one quiet hour.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "generator", items = 2, cargo = "Generators",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "clinic", loadTime = 5, unloadTime = 5, payPerStop = 150,
		pickupLabel = "LOAD THE GENERATORS AT", dropLabel = "CARRY THEM INTO",
		giver = "rocco", receiver = "Igor, the clinic's janitor", receiverRole = "worker",
	})
	add("clinic", {
		id = 5, name = "Ambulance Chaser", tier = 2, reward = 1200, coop = true, twists = { "gunner" },
		description = "Three emergency calls, three homes, the same fever. One ambulance; the crew in the back shoots.",
		briefing = "Three calls at once, three homes, the same fever in all of them. That's not a coincidence, that's a pattern, and I hate patterns. One of you drives the ambulance, the rest sit in the back and keep the biters off the stretchers.",
		debrief = "Three in, three alive, and all three were bitten by the same kind of runner. Faster. Meaner. Something new is out there.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 3, cargo = "Patients",
		pickups = 3, pickupAt = nil, drops = 1, dropAt = "clinic", payPerStop = 160,
		pickupLabel = "PICK UP THE PATIENT AT", dropLabel = "BRING THE PATIENTS TO",
		giver = "Grace's family, worried", giverRole = "townsperson", receiver = "ada",
	})
	add("clinic", {
		id = 7, name = "Quarantine Zone", tier = 3, reward = 1500, twists = { "guarded" },
		description = "Blood samples of the new strain, from a trapped nurse to the Biotech Lab. Hordes at both ends.",
		briefing = "Nurse Kim followed the fever to a block in the east and took blood samples of the new strain. Now she's hiding in a corner shop with a horde outside. Get her samples to Doctor Hiro at the Biotech Lab before the horde gets bored and comes in.",
		debrief = "Kim is safe, and Doctor Hiro says the samples are fascinating. I hate it when he says fascinating. He says he can make something with them.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "sample", items = 3, cargo = "Blood Samples",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "lab", payPerStop = 220,
		pickupLabel = "COLLECT THE SAMPLES AT", dropLabel = "DELIVER THE SAMPLES TO",
		giver = "kim", receiver = "hiro",
	})
	add("clinic", {
		id = 10, name = "Code Red", tier = 3, reward = 2600, coop = true, twists = { "spotless", "defend" }, defendTime = 60,
		description = "The booster for the whole city: the lab, two field clinics, the Stadium Shelter. Keep it intact and hold the line.",
		briefing = "Doctor Hiro turned Kim's samples into a booster that keeps a bite from turning for a whole day. Four coolers: two field clinics on the way, then the Stadium Shelter, where two thousand people wait. Keep the coolers whole, and when you get there, hold the line while we vaccinate.",
		debrief = "Two thousand people with a fighting chance. Today, you were the medicine. Raj from FreshMart called: the shelter is fed on hope, and the hope is running out.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "vaccine", items = 4, cargo = "Booster Shots",
		pickups = 1, pickupAt = "lab", drops = 3, dropAt = "stadium", payPerStop = 300,
		pickupLabel = "LOAD THE VACCINE AT", dropLabel = "DELIVER THE VACCINE TO",
		giver = "hiro", receiver = "ada",
	})
end

-- ── 3. Empty Shelves (Raj, FreshMart) ──────────────────────────────
-- Groceries, warm bread from an ice cream truck, potatoes the bandits want, seedlings for the blighted farm, Tusk's
-- price war and the city's ration.
do
	add("market", {
		id = 1, name = "Stock Up", tier = 1, reward = 600, twists = {},
		description = "FreshMart's order from the Harbor Warehouse. The eggs are in there somewhere.",
		briefing = "Welcome, welcome! Doctor Ellie says you deliver miracles; I need groceries, which are harder. My order is at the Harbor Warehouse, three bags. Carry them carefully, the eggs are in there somewhere.",
		debrief = "Eggs: intact. You: hired. Have a free banana. Now, the bread.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "groceries", items = 3, cargo = "Groceries",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "market", payPerStop = 60,
		pickupLabel = "PICK UP THE GROCERIES AT", dropLabel = "DELIVER THE GROCERIES TO",
		giver = "rocco", receiver = "raj",
	})
	add("market", {
		id = 2, name = "Bread Line", tier = 1, reward = 800, twists = {},
		description = "Warm bread sold from Frosty's ice cream truck at three corners. Hold still while they buy.",
		briefing = "Rosie's ovens work again, but people are too scared to walk to the bakery. Frosty lent us his truck. It still plays the ice cream song, sorry. Park at three corners and sell the bread while it's warm.",
		debrief = "Everybody got a loaf. One man cried into his baguette. Beautiful. Bread, yes. Potatoes, no: the farm road is the problem.",
		vehicle = "icecream", load = "carry", unload = "serve", itemKind = "bread", items = 6, cargo = "Warm Bread",
		pickups = 1, pickupAt = nil, drops = 3, dropAt = nil, payPerStop = 70,
		pickupLabel = "LOAD THE BREAD AT", dropLabel = "SELL BREAD AT",
		giver = "rosie", receiver = "Hungry neighbours", receiverRole = "townsperson",
	})
	add("market", {
		id = 3, name = "Farm to Table", tier = 2, reward = 1000, twists = { "hunted" },
		description = "Potatoes from the Old Farm in the monster truck. Tusk's bandits hunt you all the way back.",
		briefing = "Old Man Jed dug up a whole field of potatoes, and the bandits heard about it. They work for a man called Tusk now, and they'll come at you from everywhere. Take Jed's monster truck, and drive over anything that says 'hand it over'.",
		debrief = "Potatoes! Real potatoes! Tonight, everybody eats fries. Jed says the next field won't grow without help, though.",
		vehicle = "monster", load = "carry", unload = "carry", itemKind = "sack", items = 5, cargo = "Potatoes",
		pickups = 1, pickupAt = "farm", drops = 1, dropAt = "market", loadTime = 4, payPerStop = 130,
		pickupLabel = "LOAD THE POTATOES AT", dropLabel = "DELIVER THE POTATOES TO",
		giver = "jed", receiver = "raj",
	})
	add("market", {
		id = 7, name = "Seeds of Hope", tier = 2, reward = 1300, twists = { "spotless" },
		description = "Blight-proof seedlings from the Biotech Lab to the Old Farm. Smooth roads only.",
		briefing = "Jed's soil has the blight. Doctor Hiro grew seedlings that survive it. If they reach the Old Farm in one piece, next year we have tomatoes. If they don't, next year we have regret. Smooth roads only, please.",
		debrief = "Jed planted them already. He talks to them. I think that's normal for farmers. Bad news, though: Tusk is back.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "plants", items = 4, cargo = "Seedlings",
		pickups = 1, pickupAt = "lab", drops = 1, dropAt = "farm", payPerStop = 170,
		pickupLabel = "PICK UP THE SEEDLINGS AT", dropLabel = "DELIVER THE SEEDLINGS TO",
		giver = "hiro", receiver = "jed",
	})
	add("market", {
		id = 9, name = "Price War", tier = 3, reward = 1700, twists = { "hunted" }, banditBoost = 1.5,
		description = "Four crates of canned food from the docks. Tusk's bandits want FreshMart closed.",
		briefing = "Tusk wants FreshMart closed, so he can sell canned beans at fifty dollars a can. A ship brought four crates for me to the Harbor Docks, and Tusk knows it. Don't let him win, my friend.",
		debrief = "Beans are back to one dollar. Tusk is crying in his truck. Now for the big one.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "crate", items = 4, cargo = "Canned Food",
		pickups = 1, pickupAt = "docks", drops = 1, dropAt = "market", payPerStop = 250,
		pickupLabel = "LOAD THE CRATES AT", dropLabel = "DELIVER THE CRATES TO",
		giver = "rocco", receiver = "raj",
	})
	add("market", {
		id = 10, name = "Empty Shelves", tier = 3, reward = 2800, coop = true, twists = { "guarded", "defend" }, defendTime = 50,
		description = "The city's ration in the big truck: two shelters, then FreshMart's doors to hold.",
		briefing = "The city's ration for a month sits in the Harbor Warehouse, and every horde in the harbor is sitting on it. Load the big truck, feed two shelters on the way, then hold FreshMart's doors while we fill the shelves. Today, nobody goes hungry.",
		debrief = "Shelves full, city fed. My father would be proud. My accountant is confused. Chief Carlos says the smoke over the east side gets worse every day.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "groceries", items = 10, cargo = "Rations",
		pickups = 1, pickupAt = "warehouse", drops = 3, dropAt = "market", loadTime = 4, unloadTime = 4, payPerStop = 300,
		pickupLabel = "LOAD THE RATIONS AT", dropLabel = "DELIVER THE RATIONS TO",
		giver = "rocco", receiver = "raj",
	})
end

-- ── 4. Partners in Crime (Rosa & Rico, the twins) · DUO ──────────────────
-- Only with a partner: a jukebox for two, the Water Works' two-lever gate, the bank's two keys, plasma on the clock,
-- Tusk's stolen mortars and, at last, Tusk's whole medicine hoard.
do
	add("duo", {
		id = 1, name = "Double Act", tier = 2, reward = 900, twists = { "pair" },
		description = "The twins' old diner jukebox to the Survivor Camp. Too heavy for one: you lift it together or not at all.",
		briefing = "Rosa here, and the one grinning is Rico. We're twins, we're couriers, and we never take a job alone. Rule one: nothing heavy moves unless both of you are on it. Our old diner's jukebox goes to the Survivor Camp. Show us you can lift together.",
		debrief = "Rico: Not a scratch on the jukebox. Rosa: And not one argument. You two are hired. Next: the camp's water.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "furniture", items = 2, cargo = "Jukebox and Speakers",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "camp", loadTime = 5, unloadTime = 5, payPerStop = 110,
		pickupLabel = "LOAD THE JUKEBOX AT", dropLabel = "CARRY IT INTO",
		giver = "rico", receiver = "martha",
	})
	add("duo", {
		id = 2, name = "Flood Gate", tier = 2, reward = 1100, twists = { "switches" },
		description = "Chlorine for the Water Works. Its old yard gate only opens when two levers far apart are pulled at once.",
		briefing = "Rosa: The camp's jukebox works. The camp's water does not: the Water Works is out of chlorine. Rico: Catch is, the yard gate has two levers twenty steps apart. Two people awake on every shift, the old engineer said. Rosa: One of you on each lever, pull on three. Not on four. On three.",
		debrief = "Rosa: Clean water by tonight. Rico: And you only counted to four once. Progress. Rosa: The mayor heard about us.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "barrel", items = 3, cargo = "Chlorine Barrels",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "waterworks", payPerStop = 130,
		pickupLabel = "LOAD THE CHLORINE AT", dropLabel = "DELIVER THE CHLORINE TO",
		giver = "rocco", receiver = "hugo",
	})
	add("duo", {
		id = 4, name = "Two Keys", tier = 3, reward = 1400, twists = { "switches", "hunted" }, gates = "pickup",
		description = "The city's emergency fund from the bank vault: two keys turned at once, then bandits all the way to City Hall.",
		briefing = "Rosa: The First Zombie Bank's vault opens with two keys turned at the same moment, on two desks far apart. Rico: Gordon, the manager, hates us, so naturally he gave us both keys. Rosa: Mayor Ruth wants the emergency fund at City Hall, and every bandit with wheels wants it more. Turn the keys, load the cash, drive like you stole it. You didn't. Legally.",
		debrief = "Rico: The mayor counted it twice. Rosa: Then she counted us. We're on the city's list of trusted people now. Short list. Rico: And the fund already has a job.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "cash", items = 3, cargo = "Emergency Fund",
		pickups = 1, pickupAt = "bank", drops = 1, dropAt = "cityhall", payPerStop = 200,
		pickupLabel = "LOAD THE CASH AT", dropLabel = "DELIVER THE FUND TO",
		giver = "gordon", receiver = "percy",
	})
	add("duo", {
		id = 7, name = "Cold Hands", tier = 3, reward = 1800, twists = { "pair" },
		description = "Freezers of blood plasma from a dark house to the City Clinic: two carriers, five minutes before it thaws.",
		briefing = "Rico: The emergency fund bought blood plasma, and the plasma sits in a doctor's house that just lost power. Rosa: Five minutes before it thaws, and every freezer is a two-person carry. Don't even think about leaving your partner behind. Rico: Run, lift, drive, lift. Breathe later.",
		debrief = "Rosa: Doctor Ellie says that plasma saves a dozen people this week. Rico: A man called Tusk says he wants it back. Rosa: Tusk can wait in line.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "icebox", items = 2, cargo = "Blood Plasma",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "clinic", loadTime = 4, unloadTime = 4, payPerStop = 240, timeLimit = 300,
		pickupLabel = "PICK UP THE FREEZERS AT", dropLabel = "RUSH THE PLASMA TO",
		giver = "Neil, a neighbour", giverRole = "townsperson", receiver = "ada",
	})
	add("duo", {
		id = 9, name = "Mirror Run", tier = 4, reward = 2400, twists = { "pair", "gunner" },
		description = "Tusk stole the base's mortar crates. Take them back two hands per crate, and shoot from the seats all the way.",
		briefing = "Rico: Tusk stole a stack of mortar crates from the Military Base and parked them in a garage across town. Rosa: Every crate is a two-person lift, and his boys patrol the streets. Rico: So you lift together, you ride together, and whoever isn't driving shoots. Rosa: Captain Maria pays well. Tusk does not forgive. Be quick.",
		debrief = "Rosa: Maria saluted us. Rico: Tusk sent us a postcard. It just says 'soon'. Rosa: Then let's get there first.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "ammo", items = 4, cargo = "Mortar Crates",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "base", loadTime = 4, unloadTime = 4, payPerStop = 340,
		pickupLabel = "TAKE BACK THE CRATES AT", dropLabel = "DELIVER THE CRATES TO",
		giver = "Dusty, a looter gone honest", giverRole = "townsperson", receiver = "roy",
	})
	add("duo", {
		id = 10, name = "Partners in Crime", tier = 4, reward = 3800, twists = { "pair", "switches" },
		description = "Tusk's medicine hoard from two hideouts, a drop on the way, then the stadium's two-lever gate. Lift together, pull together.",
		briefing = "Rosa: Tusk has been hoarding the city's medicine in two hideouts and selling it back one pill at a time. Tonight we take all of it. Rico: The crates are heavy, so you carry them together. Some go to a field post on the way, the rest to the Stadium Shelter. Rosa: The stadium's loading gate opens with two levers, and Tusk's men will be right behind you. This is what we trained you for, partners.",
		debrief = "Rico: The whole city has its medicine back. Rosa: And Tusk has an empty garage and a bad mood. Partners, it was an honour.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "medicine", items = 8, cargo = "Tusk's Medicine Hoard",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "stadium", loadTime = 4, unloadTime = 4, payPerStop = 380,
		pickupLabel = "RAID THE STASH AT", dropLabel = "DELIVER THE MEDICINE TO",
		giver = "Mona, Tusk's ex-accountant", giverRole = "clerk", receiver = "dan",
	})
end

-- ── 5. Smoke and Sirens (Chief Carlos, Fire Station 9) ──────────────────
-- Hoses, two burning blocks, diesel the bandits want, a firebreak for Jed's farm, an oil fire at the Power Plant and
-- the east side in flames.
do
	add("firehouse", {
		id = 1, name = "Hose Down", tier = 2, reward = 800, twists = {},
		description = "Couplings and patch kits from the Harbor Warehouse to Fire Station 9.",
		briefing = "Raj says you don't panic. Good, because my hoses have more holes than a zombie's alibi. Rocco at the Harbor Warehouse has three boxes of couplings and patch kits. Bring them to Station 9 and you get to slide down the pole. Once.",
		debrief = "Hoses fixed. Go slide down the pole, that's an order. And don't unpack: the bell's ringing.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tools", items = 3, cargo = "Hose Gear",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "firestation", payPerStop = 100,
		pickupLabel = "PICK UP THE GEAR AT", dropLabel = "DELIVER THE GEAR TO",
		giver = "rocco", receiver = "duke",
	})
	add("firehouse", {
		id = 2, name = "Smoke Eaters", tier = 2, reward = 1000, twists = {},
		description = "The school bus, two burning blocks, four people on the street. Five minutes before the roofs fall.",
		briefing = "Two apartment blocks are burning and the people got out onto the street. Grab the school bus and pick them up before the smoke brings every zombie in the district. Five minutes, then the roofs come down.",
		debrief = "Four people out, zero people toasted. Good driving. Bad news: the engines drank the last of the diesel getting there.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 4, cargo = "Survivors",
		pickups = 2, pickupAt = nil, drops = 1, dropAt = "firestation", payPerStop = 130, timeLimit = 300,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Sami, a neighbour", giverRole = "townsperson", receiver = "duke",
	})
	add("firehouse", {
		id = 3, name = "Fuel the Engines", tier = 2, reward = 1200, twists = { "hunted" },
		description = "Diesel barrels from the Harbor Fuel Depot to the fire engines. Bandits hunt the fuel truck.",
		briefing = "My engines drink diesel like I drink coffee, and we're both running on empty. Hank at the Harbor Fuel Depot has barrels, and the bandits know fuel is worth more than gold now. They'll hunt you the whole way. Don't let them siphon my trucks.",
		debrief = "Tanks full. Coffee next, please. Then trouble: a grass fire is crawling toward the Old Farm.",
		vehicle = "fueltruck", load = "carry", unload = "carry", itemKind = "barrel", items = 4, cargo = "Diesel",
		pickups = 1, pickupAt = "fueldepot", drops = 1, dropAt = "firestation", payPerStop = 150,
		pickupLabel = "LOAD THE FUEL AT", dropLabel = "REFUEL THE ENGINES AT",
		giver = "hank", receiver = "duke",
	})
	add("firehouse", {
		id = 5, name = "Firebreak", tier = 3, reward = 1500, coop = true, twists = { "quiet" },
		description = "Dynamite from the Train Yard to blast a firebreak at the Old Farm. Every shot costs condition.",
		briefing = "A grass fire is crawling toward Old Man Jed's farm, and Raj's potatoes with it. We blast a firebreak, which means you haul dynamite from the Train Yard. Do not shoot. I mean it. Not even at the really ugly ones.",
		debrief = "Boom, on purpose this time. The farm is safe. Now the Power Plant is on fire, because of course it is.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 3, cargo = "Dynamite",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "farm", payPerStop = 220,
		pickupLabel = "LOAD THE DYNAMITE AT", dropLabel = "DELIVER THE DYNAMITE TO",
		giver = "gus", receiver = "jed",
	})
	add("firehouse", {
		id = 9, name = "Oil Fire", tier = 4, reward = 2000, coop = true, twists = { "guarded" },
		description = "A big load: five drums of foam concentrate for an oil fire at the Power Plant. Hordes at both ends.",
		briefing = "The Power Plant has an oil fire, and water only makes it worse. Rocco has foam concentrate, and the plant has a horde that wandered in to warm up. Five drums, so bring something big. Clear them, deliver the foam, and nobody breathe the smoke.",
		debrief = "Fire's out. Engineer Ivan owes me one, and I will collect. But look east: the whole side of town is glowing.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "crate", items = 5, cargo = "Fire Foam",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "powerplant", payPerStop = 300,
		pickupLabel = "LOAD THE FOAM AT", dropLabel = "DELIVER THE FOAM TO",
		giver = "rocco", receiver = "ivan",
	})
	add("firehouse", {
		id = 10, name = "Smoke and Sirens", tier = 4, reward = 3400, coop = true, twists = { "defend", "gunner" }, defendTime = 60,
		description = "The east side burns: two rooftops of survivors, a safe house, and the stadium gate to hold.",
		briefing = "Half of the east side is on fire, and people are trapped between the flames and the dead. We take the bus, we go in, we pick up everyone we find. At the stadium you hold the gate until the last of them is inside. Station 9 leaves no one behind.",
		debrief = "Eight lives today. You're one of us now: there's a helmet with your name on it. Captain Maria watched the whole thing from the base. She wants you.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 8, cargo = "Survivors",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "stadium", payPerStop = 340,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Tess, a survivor", giverRole = "townsperson", receiver = "dan",
	})
end

-- ── 6. Iron Supply (Captain Maria, the Military Base) ────────────────────
-- The big horde is coming: ammo, hot stew for the checkpoints, the north tunnel collapsed, the scout chopper down,
-- a radar on the Lighthouse and the night it hits.
do
	add("army", {
		id = 1, name = "Ammo Run", tier = 2, reward = 1100, twists = {},
		description = "Ammo from the Harbor Docks to the base in the army's armored truck.",
		briefing = "Chief Carlos says you drive like a soldier and talk like a civilian. I can work with that. The big horde is coming down from the mountains, and my men are down to harsh language. The ammo came in at the Harbor Docks: take the armored truck through the tunnel.",
		debrief = "Ammo received. You may now salute. Badly, like a civilian. Next problem: my men are starving.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "ammo", items = 4, cargo = "Ammo Crates",
		pickups = 1, pickupAt = "docks", drops = 1, dropAt = "base", payPerStop = 150,
		pickupLabel = "LOAD THE AMMO AT", dropLabel = "DELIVER THE AMMO TO",
		giver = "rocco", receiver = "roy",
	})
	add("army", {
		id = 2, name = "Mess Hall", tier = 2, reward = 1300, twists = {},
		description = "A truckload of hot stew (six big pots) from a diner, served from your window at three army checkpoints.",
		briefing = "My checkpoints have eaten cold beans for a month, and a hungry soldier aims badly. A diner in town cooks hot stew, six pots the size of oil drums: bring a truck. Stop at three checkpoints and serve it from your window. Hold still while they eat. They're armed.",
		debrief = "The men say it's the best stew they've ever had. They're lying, but they're happy. Now we close the north tunnel.",
		vehicle = nil, load = "carry", unload = "serve", itemKind = "soup", items = 6, cargo = "Hot Stew",
		pickups = 1, pickupAt = nil, drops = 3, dropAt = nil, unloadTime = 5, payPerStop = 140,
		pickupLabel = "PICK UP THE STEW AT", dropLabel = "SERVE STEW AT",
		giver = "Dolores, the diner cook", giverRole = "cook", receiver = "Soldiers at the checkpoint", receiverRole = "soldier",
	})
	add("army", {
		id = 3, name = "Boom Sticks", tier = 3, reward = 1600, twists = { "quiet" },
		description = "Dynamite from the Train Yard to the base, to collapse the north tunnel. No shooting.",
		briefing = "My engineers will collapse the north tunnel before the horde gets through it. They need dynamite, and Gus at the Train Yard has a stash. No shooting near the cargo, civilian. Not one round. If you blow up, I have to do paperwork.",
		debrief = "Tunnel's down, you're still in one piece. Paperwork avoided. Then the radio crackled: our scout chopper is down.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 4, cargo = "Dynamite",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "base", payPerStop = 220,
		pickupLabel = "LOAD THE DYNAMITE AT", dropLabel = "DELIVER THE DYNAMITE TO",
		giver = "gus", receiver = "roy",
	})
	add("army", {
		id = 4, name = "Wounded in Action", tier = 3, reward = 1900, coop = true, twists = { "gunner" },
		description = "The scout chopper down at the Old Airfield: three wounded to the clinic. The crew rides shotgun.",
		briefing = "Corporal Danny took the chopper up to count the horde and came down hard at the Old Airfield. Three of my people are hurt and can't hold a rifle. You drive the ambulance, your friends ride shotgun. City Clinic. Nobody gets left behind.",
		debrief = "All three will walk again. Danny counted the horde before he crashed. I wish he hadn't told me the number.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 3, cargo = "Wounded Soldiers",
		pickups = 1, pickupAt = "airfield", drops = 1, dropAt = "clinic", payPerStop = 250,
		pickupLabel = "PICK UP THE WOUNDED AT", dropLabel = "BRING THE WOUNDED TO",
		giver = "danny", receiver = "ada",
	})
	add("army", {
		id = 9, name = "Eyes in the Sky", tier = 4, reward = 2600, twists = { "spotless" },
		description = "Fragile radar parts from the airfield to the top of the Lighthouse.",
		briefing = "No chopper means no eyes, so we build a radar post on the Lighthouse to watch the coast road. Danny salvaged the parts at the airfield, and they're fragile. One pothole too many and we're blind again.",
		debrief = "Radar's up. We can see them coming now. All of them. Tonight's the night, soldier.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 3, cargo = "Radar Parts",
		pickups = 1, pickupAt = "airfield", drops = 1, dropAt = "lighthouse", payPerStop = 330,
		pickupLabel = "LOAD THE RADAR PARTS AT", dropLabel = "DELIVER THE PARTS TO",
		giver = "danny", receiver = "tom",
	})
	add("army", {
		id = 10, name = "Iron Supply", tier = 4, reward = 4200, coop = true, twists = { "defend", "hunted" }, defendTime = 75,
		description = "The last ammo in two gun shops, hunted all the way, and the base gate to hold while it's unloaded.",
		briefing = "The radar says the horde reaches the base tonight. Two gun shops in town still have ammo, and every bandit gang wants it too. Load up, punch through, and at the base, hold the gate while my men stock the walls. This is it, soldier.",
		debrief = "The line held, and you held it with us. I've seen generals with less nerve. Engineer Ivan says the fighting knocked out half the grid. He's asking for you.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "ammo", items = 8, cargo = "Ammo Crates",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "base", payPerStop = 380,
		pickupLabel = "LOAD THE AMMO AT", dropLabel = "DELIVER THE AMMO TO",
		giver = "Mack, the gun store owner", giverRole = "shopkeeper", receiver = "roy",
	})
end

-- ── 7. Lights Out (Engineer Ivan, the Power Plant) ─────────────────────
-- The turbine after the oil fire, life-support batteries, the blackout at sunset, the copper thieves who caused it,
-- cooling water for a plant at full power and the stadium's lights.
do
	add("power", {
		id = 1, name = "Spare Parts", tier = 2, reward = 1200, twists = {},
		description = "Three toolboxes from the Harbor Warehouse for a turbine that sounds like a dying walrus.",
		briefing = "Comrade courier! Chief Carlos put out my fire, and now turbine three makes a noise like a dying walrus. I need three toolboxes from Rocco at the Harbor Warehouse. Quickly, before the walrus dies.",
		debrief = "Walrus fixed. The turbine sings again, like opera. But the clinic is on batteries, and batteries do not sing.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tools", items = 3, cargo = "Toolboxes",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "powerplant", payPerStop = 160,
		pickupLabel = "PICK UP THE TOOLBOXES AT", dropLabel = "DELIVER THE TOOLS TO",
		giver = "rocco", receiver = "ivan",
	})
	add("power", {
		id = 2, name = "Battery Life", tier = 2, reward = 1400, twists = { "spotless" },
		description = "Battery packs for a home breathing machine and the clinic's life support. Cracked ones leak.",
		briefing = "The clinic's life support runs on battery packs between blackouts. Full packs are fragile, and cracked ones leak acid. Two for a family with a sick grandpa on the way, two for Doctor Ellie. Gentle, like eggs. Electric eggs.",
		debrief = "Grandpa's breathing machine hums again. So does my heart. Now, please, nobody touch the grid before sunset.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "battery", items = 4, cargo = "Battery Packs",
		pickups = 1, pickupAt = "powerplant", drops = 2, dropAt = "clinic", payPerStop = 170,
		pickupLabel = "PICK UP THE BATTERIES AT", dropLabel = "DELIVER THE BATTERIES TO",
		giver = "ivan", receiver = "ada",
	})
	add("power", {
		id = 6, name = "Blackout", tier = 3, reward = 1700, twists = { "night" },
		description = "The grid is down after dark: your car is loaded, three homes on breathing machines, five minutes.",
		briefing = "Somebody touched the grid. It went down at sunset, and three homes have people on breathing machines. Your car is already loaded, I packed it myself. Five minutes. In the dark. With the dead. Go!",
		debrief = "Three machines humming, three people breathing. And now I know why it failed: somebody stole the copper out of my transformers.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "battery", items = 3, cargo = "Battery Packs",
		pickups = 0, pickupAt = nil, drops = 3, dropAt = nil, payPerStop = 240, timeLimit = 300,
		pickupLabel = "PICK UP THE BATTERIES AT", dropLabel = "DELIVER BATTERIES TO",
		giver = "ivan", receiver = "Leon, in the dark", receiverRole = "townsperson",
	})
	add("power", {
		id = 7, name = "Copper Thieves", tier = 3, reward = 2100, coop = true, twists = { "hunted", "gunner" },
		description = "Transformer parts from the Train Yard. Copper thieves hunt you, the passengers hunt them.",
		briefing = "Bandits strip my transformers to sell the copper: that is why the lights died. Gus found new parts at the Train Yard, but the thieves are watching, and they will hunt you. Friends in the passenger seats: teach them that copper is expensive.",
		debrief = "Parts delivered. The thieves are now very afraid of passenger seats. The plant runs at full power again. Maybe too full.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 4, cargo = "Transformer Parts",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "powerplant", payPerStop = 270,
		pickupLabel = "LOAD THE PARTS AT", dropLabel = "DELIVER THE PARTS TO",
		giver = "gus", receiver = "ivan",
	})
	add("power", {
		id = 8, name = "Cooling Water", tier = 4, reward = 2800, coop = true, twists = { "guarded" },
		description = "A truckload of treated water: six barrels for the overheating boilers. Hordes at both ends.",
		briefing = "Full power means hot boilers, and hot boilers mean the plant becomes a very large firework. Six barrels of treated water from Hugo at the Water Works, a truckload, and hordes at both ends, because I am unlucky.",
		debrief = "Temperature normal. City not exploded. Today is a good day. And now I have enough power for my big idea.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "water", items = 6, cargo = "Treated Water",
		pickups = 1, pickupAt = "waterworks", drops = 1, dropAt = "powerplant", loadTime = 4, unloadTime = 4, payPerStop = 320,
		pickupLabel = "LOAD THE WATER AT", dropLabel = "DELIVER THE WATER TO",
		giver = "hugo", receiver = "ivan",
	})
	add("power", {
		id = 10, name = "Lights Out", tier = 4, reward = 4800, coop = true, twists = { "lift", "defend" }, defendTime = 60,
		description = "Four huge generators to light the Stadium Shelter. Carry them in pairs, hold the stadium while they're wired.",
		briefing = "My big idea: four huge generators to light the Stadium Shelter and the streets around it, so nobody there sleeps in the dark again. They're the heaviest things I own. Bring a crew to carry, and hold the stadium while I wire them in. When the lights come on, the dead will come to look.",
		debrief = "The stadium is lit, and the whole city can see it glowing. Hope, comrade. Even Walt saw it from his ranch, and Walt never calls anybody. He called.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "generator", items = 4, cargo = "Generators",
		pickups = 1, pickupAt = "powerplant", drops = 2, dropAt = "stadium", loadTime = 5, unloadTime = 5, payPerStop = 380,
		pickupLabel = "LOAD THE GENERATORS AT", dropLabel = "DELIVER THE GENERATORS TO",
		giver = "ivan", receiver = "dan",
	})
end

-- ── 8. Wild West End (Walt, the rancher) ─────────────────────────────────
-- Two mares for the Riding School, oats the Rust Riders want, Thunder spooked by their raid, the stolen mares at
-- night, rifles for the walls and the last raid.
do
	add("ranch", {
		id = 1, name = "Saddle Up", tier = 2, reward = 1400, twists = {},
		description = "Lead two mares into the livestock truck and out at the Riverside Riding School.",
		briefing = "Howdy, partner. Saw your stadium lights from my porch. Two of my mares are going to the Riding School: they teach the kids to ride, and a horse is quieter than a car out there. Lead 'em in gentle. They kick harder than zombies.",
		debrief = "Emma says they settled right in. You've got soft hands, partner. Now, the feed: that's where the Rust Riders come in.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 2, cargo = "Mares",
		pickups = 1, pickupAt = "ranch", drops = 1, dropAt = "stables", payPerStop = 180,
		pickupLabel = "LEAD THE HORSES IN AT", dropLabel = "LEAD THE HORSES OUT AT",
		giver = "jesse", receiver = "emma",
	})
	add("ranch", {
		id = 2, name = "Feed Run", tier = 2, reward = 1600, twists = { "hunted" },
		description = "Six sacks of oats from the Old Farm in the monster truck. The Rust Riders hunt every feed truck.",
		briefing = "My horses eat more than a bunkhouse of cowboys, and the Rust Riders hit every feed truck on the west road. Old Man Jed has six sacks of oats. Take his monster truck and drive like the devil's on your tail. Because he will be.",
		debrief = "Oats in the barn, Rust Riders in the ditch. Good day's work. Bad night, though: they shot up the Riding School.",
		vehicle = "monster", load = "carry", unload = "carry", itemKind = "sack", items = 6, cargo = "Oats",
		pickups = 1, pickupAt = "farm", drops = 1, dropAt = "ranch", loadTime = 4, payPerStop = 190,
		pickupLabel = "LOAD THE OATS AT", dropLabel = "DELIVER THE OATS TO",
		giver = "jed", receiver = "jesse",
	})
	add("ranch", {
		id = 3, name = "Horse Whisperer", tier = 3, reward = 1900, twists = { "spotless" },
		description = "Thunder, Walt's spooked stallion, home from the Riding School without a scratch.",
		briefing = "The Rust Riders shot up the Riding School last night, and Thunder, my old stallion, won't let anybody near him. He trusts slow drivers. Bring him home without a scratch, or he'll never get in a truck again.",
		debrief = "Thunder's home, eating apples like nothing happened. My two mares aren't, though. The Rust Riders took 'em.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 1, cargo = "Thunder",
		pickups = 1, pickupAt = "stables", drops = 1, dropAt = "ranch", payPerStop = 220,
		pickupLabel = "LEAD THE STALLION IN AT", dropLabel = "LEAD HIM HOME TO",
		giver = "emma", receiver = "walt",
	})
	add("ranch", {
		id = 5, name = "Moonlight Rustlers", tier = 3, reward = 2300, twists = { "night" },
		description = "The two stolen mares, hidden in the Old Farm's barn. Only fools move horses by daylight.",
		briefing = "Jed spotted my two stolen mares in his old barn: the Rust Riders hid 'em there. Only fools move horses in daylight with bandits watching, so we go at night. Quiet-like.",
		debrief = "Both mares home. The rustlers will wake up to an empty barn and a bad mood. They'll come for the ranch now. Time to get ready.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 2, cargo = "Stolen Mares",
		pickups = 1, pickupAt = "farm", drops = 1, dropAt = "ranch", payPerStop = 250,
		pickupLabel = "LEAD THE HORSES IN AT", dropLabel = "LEAD THE HORSES OUT AT",
		giver = "jed", receiver = "walt",
	})
	add("ranch", {
		id = 8, name = "Showdown", tier = 4, reward = 3000, coop = true, twists = { "guarded" },
		description = "Rifles from Precinct 13's lockup for the ranch's walls. The dead camp on its steps.",
		briefing = "The Rust Riders sent word: they're coming for the ranch. Officer Nate at Precinct 13 will lend us rifles from the lockup, if you can get through the dead camped on its steps. Bring a posse.",
		debrief = "Rifles on the walls. Let 'em come. And they will: they just burned the Riding School's stables.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "weapons", items = 4, cargo = "Rifles",
		pickups = 1, pickupAt = "police", drops = 1, dropAt = "ranch", payPerStop = 320,
		pickupLabel = "LOAD THE RIFLES AT", dropLabel = "DELIVER THE RIFLES TO",
		giver = "Officer Nate, Precinct 13", giverRole = "officer", receiver = "jesse",
	})
	add("ranch", {
		id = 10, name = "Wild West End", tier = 4, reward = 5400, coop = true, twists = { "defend", "hunted" }, defendTime = 75,
		description = "The last of the herd from the burned stables, hunted by the Rust Riders, and the ranch to hold.",
		briefing = "This is it, partner. The Rust Riders burned the Riding School's stables, and the last of my herd is waiting there. Leave one horse at a safe barn on the way, bring the other home, then hold the ranch with me. They're coming for everything I've got.",
		debrief = "The Rust Riders are done. The west is ours again. You're family now, partner. Doctor Hiro rode out here asking for the best driver in the city. Reckon that's you.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 2, cargo = "The Last Herd",
		pickups = 1, pickupAt = "stables", drops = 2, dropAt = "ranch", payPerStop = 380,
		pickupLabel = "LEAD THE HORSES IN AT", dropLabel = "LEAD THE HORSES OUT AT",
		giver = "emma", receiver = "walt",
	})
end

-- ── 9. Patient Zero (Doctor Hiro, the Biotech Lab) ───────────────────────────
-- Equipment guarded by the faculty, Frosty's freezers, batteries the Crimson Syndicate wants, the woman bitten on
-- day one, the trial doses at night and the first cure: enough for one camp.
do
	add("lab", {
		id = 2, name = "Lab Rats", tier = 2, reward = 1700, twists = { "guarded" },
		description = "Modern lab equipment from a university office, guarded by what used to be the faculty.",
		briefing = "My booster buys a bitten person one day. I want forever, and for that my microscopes from the stone age won't do. A university office downtown still has four crates of modern equipment, guarded by what used to be the faculty. Please be respectful. They had tenure.",
		debrief = "New equipment. I can see the virus now. It's ugly. Thank you. Next, I need somewhere cold to keep it.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 4, cargo = "Lab Equipment",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "lab", payPerStop = 220,
		pickupLabel = "PICK UP THE EQUIPMENT AT", dropLabel = "DELIVER THE EQUIPMENT TO",
		giver = "Alan, a professor", giverRole = "teacher", receiver = "hiro",
	})
	add("lab", {
		id = 5, name = "Deep Freeze", tier = 3, reward = 2000, coop = true, twists = { "lift" },
		description = "Frosty's industrial freezers to the lab, carried in pairs. They still smell of strawberry.",
		briefing = "My lab freezer broke, and the only industrial freezers left in the city are at Frosty's. They are enormous, and they still smell of strawberry. Carry them with a partner. Alone, you'll crawl.",
		debrief = "The freezers work. My cultures now smell of strawberry. Science is strange. The sequencer is next, and it is hungry.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "icebox", items = 4, cargo = "Freezers",
		pickups = 1, pickupAt = "frosty", drops = 1, dropAt = "lab", loadTime = 5, unloadTime = 5, payPerStop = 290,
		pickupLabel = "LOAD THE FREEZERS AT", dropLabel = "DELIVER THE FREEZERS TO",
		giver = "molly", receiver = "hiro",
	})
	add("lab", {
		id = 7, name = "Power Hungry", tier = 4, reward = 2500, twists = { "hunted" }, banditBoost = 1.5,
		description = "Battery packs for the sequencer. The Crimson Syndicate sends cars to stop the research.",
		briefing = "My sequencer eats power like a teenager eats pizza. Engineer Ivan charged four battery packs for me, but a rival outfit, the Crimson Syndicate, wants my research stopped. They'll send cars. Many cars.",
		debrief = "Sequencer running. The Syndicate is a few cars short. Fascinating, in a violent way. And the sequencer found her: Patient Zero.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "battery", items = 4, cargo = "Battery Packs",
		pickups = 1, pickupAt = "powerplant", drops = 1, dropAt = "lab", payPerStop = 330,
		pickupLabel = "LOAD THE BATTERIES AT", dropLabel = "DELIVER THE BATTERIES TO",
		giver = "ivan", receiver = "Yuki, the lab assistant", receiverRole = "doctor",
	})
	add("lab", {
		id = 8, name = "Patient Zero", tier = 4, reward = 3000, coop = true, twists = { "guarded", "spotless" },
		description = "The first person ever bitten, hiding at the Old Airfield. The hordes follow her. Bring her in unhurt.",
		briefing = "We found her: the woman who was bitten on day one and never turned. She's hiding at the Old Airfield, Corporal Danny is keeping her company, and the hordes are drawn to her, nobody knows why. Bring her to me unhurt. Everything depends on it.",
		debrief = "Patient Zero is safe, and the cure is in her blood. I can feel it. Now the formula has to survive a night drive.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 1, cargo = "Patient Zero",
		pickups = 1, pickupAt = "airfield", drops = 1, dropAt = "lab", payPerStop = 360,
		pickupLabel = "PICK UP THE PATIENT AT", dropLabel = "BRING THE PATIENT TO",
		giver = "danny", receiver = "hiro",
	})
	add("lab", {
		id = 9, name = "Midnight Formula", tier = 4, reward = 3800, twists = { "night", "spotless" },
		description = "The first trial doses, stable only in the cold of the night: two volunteers and the clinic.",
		briefing = "The first trial doses from her blood. They only stay stable in the cold of the night, so you deliver after dark: two volunteers at home, then Doctor Ellie's clinic. If a single cooler breaks I start over, and I don't want to start over.",
		debrief = "All three volunteers are on their feet. It works. It actually works. Now: how much of it can I make?",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "vaccine", items = 3, cargo = "Trial Doses",
		pickups = 1, pickupAt = "lab", drops = 3, dropAt = "clinic", payPerStop = 370,
		pickupLabel = "LOAD THE TRIAL DOSES AT", dropLabel = "DELIVER A DOSE TO",
		giver = "hiro", receiver = "ellie",
	})
	add("lab", {
		id = 10, name = "The Cure", tier = 4, reward = 7000, coop = true, twists = { "defend", "spotless" }, defendTime = 90,
		description = "The biggest load yet, eight coolers of the cure: two homes, then the Survivor Camp to hold until every dose is given.",
		briefing = "Everything I could make: eight coolers of the cure. Two homes on the way, then the Survivor Camp, the biggest crowd we have. When the dead smell that many people in one place, they'll come in waves. Hold the camp until every dose is given. And don't drop anything. Please.",
		debrief = "The camp is cured. The rest of the city is not: this lab made enough for one camp, and it can't make more. The cure has to leave the city. A man called Vinnie says he can move anything. I don't like him. I need him.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "vaccine", items = 8, cargo = "The Cure",
		pickups = 1, pickupAt = "lab", drops = 3, dropAt = "camp", payPerStop = 420,
		pickupLabel = "LOAD THE CURE AT", dropLabel = "DELIVER THE CURE TO",
		giver = "hiro", receiver = "hal",
	})
end

-- ── 10. Dirty Money (Vinnie, the fixer) ───────────────────────────────────
-- A ticking box, laundered cash, paintings stolen from the stealers, hardware for Blackrock, a rival's boat and
-- Vinnie's own way out (his pier, left to the mayor's boats).
do
	add("underworld", {
		id = 1, name = "No Questions Asked", tier = 2, reward = 2000, twists = { "quiet" },
		description = "A ticking box is already in your trunk. Bring it to the bank, and don't fire a gun near it.",
		briefing = "Kid, the doctor says you don't open boxes. I like that. There's a box in your trunk already. It ticks. Don't ask why it ticks. Bring it to my associate at the bank, and whatever you do, don't fire a gun anywhere near it.",
		debrief = "It was a clock. A very expensive clock. Or was it? Don't ask. Gordon liked it so much, he has a job for you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "parcel", items = 1, cargo = "A Ticking Box",
		pickups = 0, pickupAt = nil, drops = 1, dropAt = "bank", payPerStop = 220,
		pickupLabel = "PICK UP THE BOX AT", dropLabel = "DELIVER THE BOX TO",
		giver = "vinnie", receiver = "gordon",
	})
	add("underworld", {
		id = 2, name = "Laundry Day", tier = 3, reward = 2400, twists = { "hunted" }, banditBoost = 1.5,
		description = "Four sacks of cash from the bank to two laundromats. The Crimson Syndicate smells money.",
		briefing = "Two laundromats on the east side clean my money, and Gordon has four sacks for them to wash. The Crimson Syndicate sniffs cash from a mile away, so they'll be all over you. Keep the sacks dry, kid.",
		debrief = "Squeaky clean money. My accountant says thanks. The Syndicate does not. Let's give them something to really cry about.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "cash", items = 4, cargo = "Dirty Cash",
		pickups = 1, pickupAt = "bank", drops = 2, dropAt = nil, payPerStop = 260,
		pickupLabel = "LOAD THE CASH AT", dropLabel = "DROP THE CASH AT",
		giver = "gordon", receiver = "Mama Lu, the laundromat owner", receiverRole = "shopkeeper",
	})
	add("underworld", {
		id = 4, name = "Art Appreciation", tier = 3, reward = 2900, twists = { "spotless" },
		description = "Three priceless paintings the Syndicate stole from the museum, to a buyer's boat at Lighthouse Point. Not a scratch.",
		briefing = "The Crimson Syndicate stole three paintings from the city museum, and they keep them in a flat downtown with the window open. Now they're mine. A buyer waits on a boat at Lighthouse Point. Not a scratch on the canvas, or the buyer walks.",
		debrief = "The buyer cried. Art does that. So does the price. The Syndicate wants a war now. Good: my partners need hardware.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "painting", items = 3, cargo = "Paintings",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "lighthouse", payPerStop = 300,
		pickupLabel = "PICK UP THE PAINTINGS AT", dropLabel = "DELIVER THE PAINTINGS TO",
		giver = "Lefty, a lookout", giverRole = "townsperson", receiver = "Julian, an art buyer", receiverRole = "banker",
	})
	add("underworld", {
		id = 5, name = "Heavy Business", tier = 4, reward = 3500, coop = true, twists = { "lift" },
		description = "A big load: five heavy cases of hardware from the Harbor Warehouse to Blackrock Prison. Bring the muscle.",
		briefing = "My business partners run Blackrock Prison now, and the Syndicate is knocking on their walls. Five cases of hardware wait at the Harbor Warehouse, where my man Bruno keeps a corner. Heavy stuff, so bring a muscle or two.",
		debrief = "My partners are grateful. Grateful partners are good partners. Now: the Syndicate's boss keeps a boat at the docks. Keeps. For now.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "weapons", items = 5, cargo = "Hardware",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "prison", loadTime = 5, unloadTime = 5, payPerStop = 320,
		pickupLabel = "LOAD THE CASES AT", dropLabel = "DELIVER THE CASES TO",
		giver = "Bruno, Vinnie's man", giverRole = "worker", receiver = "Big Sal, the yard boss", receiverRole = "guard",
	})
	add("underworld", {
		id = 8, name = "Fireworks", tier = 4, reward = 4400, coop = true, twists = { "quiet", "guarded" },
		description = "Dynamite for the Syndicate boss's boat at the Harbor Docks. Hordes at both ends, and no shooting near the crates.",
		briefing = "The Syndicate's boss keeps his boat at the Harbor Docks. I want it gone, quietly, with a big bang. Dynamite from the Train Yard, a horde at both ends, and no shooting near the crates. Use your crew, use your car, use your imagination.",
		debrief = "Beautiful boom. I could see it from my penthouse. The Syndicate is finished, and so is this city, kid. Time for Vinnie to leave.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 4, cargo = "Dynamite",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "docks", payPerStop = 360,
		pickupLabel = "LOAD THE DYNAMITE AT", dropLabel = "DELIVER THE DYNAMITE TO",
		giver = "Spike, a yard hand", giverRole = "worker", receiver = "Fingers, the demolition guy", receiverRole = "worker",
	})
	add("underworld", {
		id = 10, name = "Dirty Money", tier = 4, reward = 8500, coop = true, twists = { "defend", "hunted" }, defendTime = 75, banditBoost = 2,
		description = "Vinnie's last two stashes, a cut for his mother, and the pier at Lighthouse Point to hold.",
		briefing = "The city's going down and I'm going out on a yacht. My last two stashes are hidden in town. Collect them, drop a cut at my mother's, God bless her, and bring the rest to Lighthouse Point. Every gang left wants a piece. Hold the pier while my boys load the yacht, and you'll never have to work again. In the good way.",
		debrief = "Pleasure doing business, kid. If anybody asks, you never met me. And tell the mayor her boats can use my pier. Consider it a donation.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "cash", items = 8, cargo = "Vinnie's Fortune",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "lighthouse", payPerStop = 420,
		pickupLabel = "COLLECT THE STASH AT", dropLabel = "DELIVER THE MONEY TO",
		giver = "Lefty, a lookout", giverRole = "townsperson", receiver = "vinnie",
	})
end

-- ── 11. Last Convoy (Mayor Ruth, City Hall) ─────────────────────────────
-- The evacuation plan, fuel for the last plane, the cure's formula and the seed vault on the boat, the mayor's own
-- kids, the last boat and the last convoy.
do
	add("exodus", {
		id = 1, name = "Evacuation Plan", tier = 2, reward = 2600, twists = {},
		description = "The printed evacuation plans from City Hall to Precinct 13, before word gets out.",
		briefing = "Fellow citizen, I'll be honest with you: the city is lost. Doctor Hiro's cure has to be made somewhere safe, and our people have to get out with it. The evacuation plans are printed, and the police must have them before word gets out and the panic starts. Three briefcases to Precinct 13. Keep this between us.",
		debrief = "The police have the plan. Now we need fuel, a boat, a plane and a miracle. And you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "documents", items = 3, cargo = "Evacuation Plans",
		pickups = 1, pickupAt = "cityhall", drops = 1, dropAt = "police", payPerStop = 260,
		pickupLabel = "PICK UP THE PLANS AT", dropLabel = "DELIVER THE PLANS TO",
		giver = "percy", receiver = "sue",
	})
	add("exodus", {
		id = 3, name = "Fuel for the Flight", tier = 3, reward = 3100, twists = { "quiet" },
		description = "The depot's last leaking barrels to the evacuation plane. One spark and it's over: no shooting.",
		briefing = "The last plane at the Old Airfield needs fuel, and Hank's last barrels leak like a sieve. One spark and the fuel truck becomes a small sun. No shooting, not a single bullet. Drive around the dead, not through them.",
		debrief = "Tanks full, and you still have all your fingers. Captain Jo says the plane will fly. Now, what goes on the boat.",
		vehicle = "fueltruck", load = "carry", unload = "carry", itemKind = "barrel", items = 6, cargo = "Jet Fuel",
		pickups = 1, pickupAt = "fueldepot", drops = 1, dropAt = "airfield", payPerStop = 330,
		pickupLabel = "LOAD THE FUEL AT", dropLabel = "REFUEL THE PLANE AT",
		giver = "hank", receiver = "jo",
	})
	add("exodus", {
		id = 7, name = "Seed Vault", tier = 3, reward = 3700, twists = { "spotless" },
		description = "The cure's formula and seedlings of every crop left, from the lab to the boat at Lighthouse Point. Every tray whole.",
		briefing = "Doctor Hiro packed the cure's formula with seedlings of every crop we have left. Wherever we land, they're our future. The boat at Lighthouse Point takes them, at Vinnie's old pier. Every tray must arrive whole.",
		debrief = "Our future is on the boat. It sounds dramatic, but it's true. Now, something personal.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "plants", items = 4, cargo = "The Seed Vault",
		pickups = 1, pickupAt = "lab", drops = 1, dropAt = "lighthouse", payPerStop = 380,
		pickupLabel = "LOAD THE SEEDLINGS AT", dropLabel = "DELIVER THE SEEDLINGS TO",
		giver = "hiro", receiver = "tom",
	})
	add("exodus", {
		id = 8, name = "The Mayor's Kids", tier = 4, reward = 4500, coop = true, twists = { "hunted" },
		description = "The mayor's own kids from Sunny Hill School to the plane, in the armored truck. Bandits want a hostage.",
		briefing = "My own kids are at Sunny Hill School with the last class. The bandits know who I am, and they'd love a hostage. Take the armored truck. Please. I'm asking as a mother, not as a mayor.",
		debrief = "My kids are on the plane. I... thank you. I owe you everything. Now the hardest part.",
		vehicle = "armored", load = "board", unload = "board", itemKind = "kid", items = 3, cargo = "The Mayor's Kids",
		pickups = 1, pickupAt = "school", drops = 1, dropAt = "airfield", payPerStop = 400,
		pickupLabel = "PICK UP THE KIDS AT", dropLabel = "BRING THE KIDS TO",
		giver = "amy", receiver = "jo",
	})
	add("exodus", {
		id = 9, name = "Last Boat", tier = 4, reward = 6000, coop = true, twists = { "guarded", "defend" }, defendTime = 60,
		description = "The last people from the Stadium Shelter to the last boat. Hordes at both ends, the pier to hold.",
		briefing = "The last boat leaves Lighthouse Point at dawn. Bring the last people from the Stadium Shelter, and hold the pier while they board. The dead are thick at both ends. This is the part they'll write songs about.",
		debrief = "The boat is out. They're singing on deck. Off key, but singing. One more run, driver. The last one.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 6, cargo = "The Last Survivors",
		pickups = 1, pickupAt = "stadium", drops = 1, dropAt = "lighthouse", payPerStop = 420,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "dan", receiver = "tom",
	})
	add("exodus", {
		id = 10, name = "Last Convoy", tier = 4, reward = 11000, coop = true, twists = { "defend", "gunner" }, defendTime = 90,
		description = "Three hideouts, a field post for the sick, the last plane. Hold the runway until it's in the air.",
		briefing = "This is the end of the city and the start of something else. The last survivors hide in three places. Fill the bus, drop the sick ones at the field post, and bring the rest to the airfield. When the engines start, every dead thing for miles will come running. Hold them off until the plane is up. Then get on board yourself.",
		debrief = "Wheels up. The city is behind us, and the cure is with us. You're the reason anyone made it out. Thank you, driver.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 10, cargo = "The Last Convoy",
		pickups = 3, pickupAt = nil, drops = 2, dropAt = "airfield", payPerStop = 480,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Tess, a survivor", giverRole = "townsperson", receiver = "jo",
	})
end

-- Every chapter's length is known now: the levels.
for _, def in pendingLevels do
	def.level = Missions.levelOf(def.campaign, def.number)
end
table.clear(pendingLevels)

-- ── Helpers ───────────────────────────────────────────────────────────────

local byId: { [string]: MissionDef } = {}
local chapters: { [string]: { MissionDef } } = {}
for _, def in Missions.List do
	byId[def.id] = def
	local list = chapters[def.campaign]
	if not list then
		list = {}
		chapters[def.campaign] = list
	end
	table.insert(list, def)
end
for _, list in chapters do
	table.sort(list, function(a, b)
		return a.number < b.number
	end)
end

function Missions.find(id: string): MissionDef?
	return byId[id]
end

function Missions.findCampaign(id: string): Campaign?
	return campaignById(id)
end

-- The missions of a chapter, in order (a fresh list: callers may change it).
function Missions.ofCampaign(campaignId: string): { MissionDef }
	return table.clone((chapters[campaignId] or {}) :: { MissionDef })
end

-- How many missions a chapter has.
function Missions.size(campaignId: string): number
	local list = chapters[campaignId]
	return if list then #list else 0
end

-- A chapter's finale (its last mission), or nil.
function Missions.finale(campaignId: string): MissionDef?
	local list = chapters[campaignId]
	return if list then list[#list] else nil
end

-- 6.8: the client of a chapter (shared/Cast.luau), and the partner of the DUO twins.
function Missions.clientOf(campaignId: string): (Cast.Person?, Cast.Person?)
	local entry = campaignById(campaignId)
	if not entry then
		return nil, nil
	end
	return Cast.find(entry.clientId), if entry.partnerId then Cast.find(entry.partnerId) else nil
end

-- 6.8: the short name a lock line uses for a chapter: its client's ("Marge"; the twins: "Rosa & Rico").
function Missions.clientName(campaignId: string): string
	local main, partner = Missions.clientOf(campaignId)
	if main and partner then
		return `{main.name} & {partner.name}`
	end
	return if main then main.name else campaignId
end

-- 6.8: is this a mission id of 3.0 – 6.7 that no chapter tells any more ("dispatch_4")? The save keeps its stars
-- (server/PlayerData.luau), nothing counts them.
function Missions.isRetired(id: string): boolean
	if byId[id] then
		return false
	end
	local campaignId, number = string.match(id, "^(%a+)_(%d+)$")
	local n = tonumber(number)
	return campaignId ~= nil and campaignById(campaignId) ~= nil and n ~= nil and n >= 1 and n <= OLD_SIZE
end

-- Has the player done this mission (any rating)? Their first clear is behind them: it replays.
function Missions.cleared(progress: { [string]: number }?, id: string): boolean
	return progress ~= nil and (progress[id] or 0) >= 1
end

-- 6.8: what a replay pays of `amount` (Config.Missions.ReplayPay, to $5), and of `xp` (ReplayXp).
function Missions.replayPay(amount: number): number
	return math.max(0, math.floor(amount * Config.Missions.ReplayPay / 5 + 0.5) * 5)
end

function Missions.replayXp(xp: number): number
	return math.max(0, math.floor(xp * Config.Missions.ReplayXp + 0.5))
end

-- 6.8: what finishing a mission gives a player with `progress` (best ratings) and `rewarded` (the chapters whose
-- reward was paid: profile.campaigns), at `stars`. The server (server/Missions.luau credit) pays it; nothing here
-- changes the tables. The first clear: the mission's reward and the first-clear XP bonus (`xpBonus` × the job's XP);
-- a replay: none of that (the job's own small pay: Jobs, Missions.replayPay). A new best rating pays StarBonus a star
-- either way (once per star). The clear that completes the chapter pays its reward, once.
export type Credit = {
	first: boolean,
	replay: boolean,
	best: number, -- the best rating after it
	newStars: number,
	reward: number, -- the first clear's money
	starBonus: number,
	xpBonus: number, -- the share of the job's XP given on top (Config.Missions.FirstClearXp - 1; 0 on a replay)
	chapterDone: boolean, -- this clear finished the chapter now (its reward: chapterReward, and Config.Rewards.Campaigns)
	chapterReward: number,
}

function Missions.creditFor(progress: { [string]: number }, rewarded: { [string]: boolean }, id: string, stars: number): Credit?
	local def = Missions.find(id)
	if not def then
		return nil
	end
	local tuning = Config.Missions
	local before = math.clamp(progress[id] or 0, 0, 3)
	local best = math.max(before, math.clamp(math.floor(stars), 1, 3))
	local first = before < 1
	local chapterDone, chapterReward = false, 0
	local entry = Missions.findCampaign(def.campaign)
	if entry and not rewarded[entry.id] then
		local all = true
		for _, other in (chapters[entry.id] or {}) :: { MissionDef } do
			if other.id ~= id and (progress[other.id] or 0) < 1 then
				all = false
				break
			end
		end
		if all then
			chapterDone, chapterReward = true, entry.reward
		end
	end
	return {
		first = first,
		replay = not first,
		best = best,
		newStars = best - before,
		reward = if first then math.max(0, def.reward) else 0,
		starBonus = (best - before) * tuning.StarBonus,
		xpBonus = if first then math.max(0, tuning.FirstClearXp - 1) else 0,
		chapterDone = chapterDone,
		chapterReward = chapterReward,
	}
end

-- Is a chapter's finale done (what `requires` asks for)?
function Missions.finished(progress: { [string]: number }, campaignId: string): boolean
	local last = Missions.finale(campaignId)
	return last ~= nil and (progress[last.id] or 0) >= 1
end

-- The chapters a chapter still waits for (its `requires` whose finale is not done), in order. Empty = none.
function Missions.missing(campaignId: string, progress: { [string]: number }): { Campaign }
	local list: { Campaign } = {}
	local entry = Missions.findCampaign(campaignId)
	local requires: { string } = if entry and entry.requires then entry.requires else {}
	for _, id in requires do
		local required = Missions.findCampaign(id)
		if required and not Missions.finished(progress, id) then
			table.insert(list, required)
		end
	end
	return list
end

-- Why a list of missing chapters keeps one shut: "Finish Marge's chapter first." (more than one: "… (and 3 more).").
function Missions.missingText(missing: { Campaign }): string
	local first = missing[1]
	if not first then
		return ""
	end
	local who = Missions.clientName(first.id)
	if #missing == 1 then
		return `Finish {who}'s chapter first.`
	end
	return `Finish {who}'s chapter first (and {#missing - 1} more).`
end

-- Has the player cleared any mission of a chapter (started it, maybe before 3.2 had the prerequisites)?
function Missions.started(progress: { [string]: number }, campaignId: string): boolean
	for _, def in (chapters[campaignId] or {}) :: { MissionDef } do
		if (progress[def.id] or 0) >= 1 then
			return true
		end
	end
	return false
end

-- Is a chapter open for a player of `level` with `progress`? The chapters it requires done (their finales), then
-- its level. Says why not. A chapter already started stays open (a 3.1 save: no prerequisites, an older curve).
function Missions.campaignOpen(campaignId: string, progress: { [string]: number }, level: number): (boolean, string?)
	local entry = Missions.findCampaign(campaignId)
	if not entry then
		return false, "Unknown campaign."
	end
	if Missions.started(progress, campaignId) then
		return true, nil
	end
	local missing = Missions.missing(campaignId, progress)
	if #missing > 0 then
		return false, Missions.missingText(missing)
	end
	if level < entry.level then
		return false, `{Missions.clientName(campaignId)}'s chapter opens at level {entry.level}.`
	end
	return true, nil
end

-- 6.8: the NEXT mission of a chapter: the first one not done yet, in order (nil when all are done).
function Missions.nextUp(progress: { [string]: number }, campaignId: string): MissionDef?
	for _, def in (chapters[campaignId] or {}) :: { MissionDef } do
		if (progress[def.id] or 0) < 1 then
			return def
		end
	end
	return nil
end

-- Can the player start this mission now? 6.8: its chapter open; a mission done replays (at any level); a new one only
-- when it is the chapter's next (every mission before it done: "Finish 'X' first.") and at its level. Says why not.
function Missions.unlocked(id: string, progress: { [string]: number }, level: number): (boolean, string?)
	local def = Missions.find(id)
	if not def then
		return false, "Unknown mission."
	end
	local open, why = Missions.campaignOpen(def.campaign, progress, level)
	if not open then
		return false, why
	end
	if (progress[id] or 0) >= 1 then
		return true, nil
	end
	local nextDef = Missions.nextUp(progress, def.campaign)
	if nextDef and nextDef ~= def then
		return false, `Finish "{nextDef.name}" first.`
	end
	if def.level and level < def.level then
		return false, `This mission needs level {def.level}.`
	end
	return true, nil
end

-- 6.8: a mission as the story path shows it: "done" (it replays), "next" (start it), "locked" (with the short reason:
-- "Level 7", "Finish 'Mail Call' first", "Finish Marge's chapter first").
function Missions.statusOf(id: string, progress: { [string]: number }, level: number): (string, string?)
	local def = Missions.find(id)
	if not def then
		return "locked", "Unknown mission"
	end
	if (progress[id] or 0) >= 1 then
		return "done", nil
	end
	local open, why = Missions.unlocked(id, progress, level)
	if open then
		return "next", nil
	end
	local nextDef = Missions.nextUp(progress, def.campaign)
	local chapterOpen = Missions.campaignOpen(def.campaign, progress, level)
	if chapterOpen and nextDef and nextDef ~= def then
		return "locked", `Finish "{nextDef.name}" first`
	end
	if chapterOpen and def.level and level < def.level then
		return "locked", `Level {def.level}`
	end
	return "locked", if why then string.gsub(why, "%.$", "") else "Locked"
end

-- 6.8: a chapter's card: whether it is open and the short reason when not ("Level 6", "Finish Raj's chapter
-- first"), the missions done / all, the next one, and whether it is new (open, nothing done) or done (every one).
export type ChapterState = { open: boolean, why: string?, done: number, total: number, nextId: string?, new: boolean, complete: boolean }

function Missions.chapterState(campaignId: string, progress: { [string]: number }, level: number): ChapterState
	local open, why = Missions.campaignOpen(campaignId, progress, level)
	local done, total = Missions.done(progress, campaignId)
	local nextDef = Missions.nextUp(progress, campaignId)
	local entry = Missions.findCampaign(campaignId)
	local short = why
	if not open and entry and #Missions.missing(campaignId, progress) == 0 then
		short = `Level {entry.level}`
	elseif short then
		short = string.gsub(short, "%.$", "")
	end
	return {
		open = open,
		why = if open then nil else short,
		done = done,
		total = total,
		nextId = if nextDef then nextDef.id else nil,
		new = open and done == 0,
		complete = total > 0 and done >= total,
	}
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

-- Stars collected: this chapter (or all with nil), and the most there are. 6.8: `storyOnly` leaves the DUO chapter
-- out (the challenges that ask for everything: a solo player can finish them).
function Missions.stars(progress: { [string]: number }, campaignId: string?, storyOnly: boolean?): (number, number)
	local got, most = 0, 0
	for _, def in Missions.List do
		if (campaignId == nil or def.campaign == campaignId) and not (storyOnly and def.duo) then
			got += math.clamp(progress[def.id] or 0, 0, 3)
			most += 3
		end
	end
	return got, most
end

-- Missions done (any rating) in a chapter, and how many it has.
function Missions.done(progress: { [string]: number }, campaignId: string): (number, number)
	local got, total = 0, 0
	for _, def in (chapters[campaignId] or {}) :: { MissionDef } do
		total += 1
		if (progress[def.id] or 0) >= 1 then
			got += 1
		end
	end
	return got, total
end

-- 6.8: missions done (any rating) of all the chapters (`storyOnly`: not the DUO one), and how many there are. Retired
-- ids in a save do not count.
function Missions.doneCount(progress: { [string]: number }, storyOnly: boolean?): (number, number)
	local got, total = 0, 0
	for _, def in Missions.List do
		if not (storyOnly and def.duo) then
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
