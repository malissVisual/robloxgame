--!strict
-- The missions (3.0): story campaigns of 10 missions each (3.2: ten story campaigns and the DUO campaign, 110 in all).
-- A mission is a special job (Config.JobTypeDef, played by server/Jobs.luau startMission) with a story around it: a
-- briefing, a debrief line, twists (Config.Missions.Twists), a reward for the first clear and a 1 – 3 star rating.
-- The missions of a campaign open one after the other (the first is open, each next one after the one before is done).
-- Pure data and helpers: required by the server and the client, and by tests/missions_test.luau.
--
-- 3.2, a real progression:
--   * every campaign `requires` the one before it in the story (Exodus all nine): their finale (mission 10) done
--     first, and its own driver level too (Missions.unlocked / campaignOpen say what is missing);
--   * the missions' levels grow inside a campaign, from the campaign's level (mission 1) to the next story
--     campaign's level (mission 10), computed in add() (Missions.levelOf), so the rank matters all the way;
--   * the DUO campaign (Campaign.duo, every mission duo = true and coop = true): only with a crew
--     (Config.Missions.Duo, server/Missions.luau checks it at START), with the twists made for two: pair (heavy
--     pieces only move with two, server/Cargo.luau Info.pair) and switches (two levers pulled together open the
--     stop's gate, server/DuoGates.luau). MissionDef.gates says where the gate stands.

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
	requires: { string }?, -- 3.2: campaigns whose finale (mission 10) must be done before this one opens
	duo: boolean?, -- 3.2: a DUO campaign: every mission only with a crew (Config.Missions.Duo)
}

-- A mission: everything a JobTypeDef has (id = the mission id, mission = the same id), plus the story.
export type MissionDef = Config.JobTypeDef & {
	campaign: string,
	number: number, -- 1 … 10 in its campaign
	briefing: string, -- what the client says when you open it (two or three sentences, in character)
	debrief: string, -- what they say when it is done (one sentence)
	reward: number, -- money for the first clear (on top of the pay)
	-- 3.2, the switches twist: where the two-lever gate stands. "drop" (the default) = the last drop, "pickup" =
	-- every pick-up (server/Jobs.luau, server/DuoGates.luau).
	gates: string?,
}

-- 3.2: the missions of a campaign; its finale is the last one (FINALE), the one `requires` asks for.
local FINALE = 10
-- 3.2: how many levels a DUO campaign's missions span (it is a side story: not tied to the next story campaign).
local DUO_SPAN = 4

-- The stories, in the order they open (3.2: each `requires` the one before it; the DUO campaign only First Shift).
Missions.Campaigns = {
	{ id = "dispatch", name = "First Shift", client = "Marge, the dispatcher", clientRole = "clerk", icon = "📦", color = { 255, 200, 70 }, level = 1, pitch = "Marge runs what is left of the city's dispatch office. Learn the streets, keep the parcels moving.", reward = 2500 },
	{ id = "clinic", name = "Code Red", client = "Dr. Novak, the clinic's doctor", clientRole = "doctor", icon = "🏥", color = { 240, 80, 80 }, level = 2, pitch = "The City Clinic is the last hospital open. Medicine, blood, vaccines and patients: every minute counts.", reward = 4000, requires = { "dispatch" } },
	{ id = "market", name = "Empty Shelves", client = "Mr. Patel, FreshMart's owner", clientRole = "grocer", icon = "🛒", color = { 110, 200, 90 }, level = 4, pitch = "People are hungry. Fill the supermarket, the shelters and the soup kitchens before the city starves.", reward = 5500, requires = { "clinic" } },
	{ id = "duo", name = "Partners in Crime", client = "Rosa & Rico, the twins", clientRole = "townsperson", icon = "🤝", color = { 236, 92, 60 }, level = 4, pitch = "Rosa plans, Rico jokes, and neither of them ever works alone. Jobs for two pairs of hands, two keys and two levers: bring a partner, or don't come at all.", reward = 7500, requires = { "dispatch" }, duo = true },
	{ id = "firehouse", name = "Smoke and Sirens", client = "Chief Ramirez, Fire Station 9", clientRole = "officer", icon = "🚒", color = { 255, 120, 40 }, level = 6, pitch = "Fires, trapped survivors, dead pumps. The firefighters need a driver who does not panic.", reward = 7000, requires = { "market" } },
	{ id = "army", name = "Iron Supply", client = "Captain Reyes, the Military Base", clientRole = "soldier", icon = "🪖", color = { 130, 150, 90 }, level = 8, pitch = "The army holds the line at the base. Keep their guns fed, their trucks fuelled and their secrets safe.", reward = 9000, requires = { "firehouse" } },
	{ id = "power", name = "Lights Out", client = "Engineer Volkov, the Power Plant", clientRole = "foreman", icon = "⚡", color = { 90, 180, 255 }, level = 9, pitch = "The grid is failing block by block. Batteries, generators and spare parts: bring the lights back.", reward = 11000, requires = { "army" } },
	{ id = "ranch", name = "Wild West End", client = "Walt, the rancher", clientRole = "rancher", icon = "🐴", color = { 200, 150, 90 }, level = 10, pitch = "Out west the bandits rule the roads. Walt's horses, the farm's food and a feud that ends with you.", reward = 13000, requires = { "power" } },
	{ id = "lab", name = "Patient Zero", client = "Dr. Ito, the Biotech Lab", clientRole = "doctor", icon = "🧪", color = { 160, 110, 255 }, level = 12, pitch = "Dr. Ito is close to a cure. Samples, explosives and things nobody should see: handle with care.", reward = 16000, requires = { "ranch" } },
	{ id = "underworld", name = "Dirty Money", client = "Vinnie, the fixer", clientRole = "banker", icon = "💰", color = { 230, 200, 60 }, level = 13, pitch = "Vinnie pays the best and asks no questions. Cash, gold, stolen art: everybody wants what is in your trunk.", reward = 20000, requires = { "lab" } },
	{ id = "exodus", name = "Last Convoy", client = "Mayor Grant, City Hall", clientRole = "clerk", icon = "🚌", color = { 255, 255, 255 }, level = 14, pitch = "The city is falling. Get the survivors to the airfield and the lighthouse before the last plane and the last boat leave.", reward = 30000, requires = { "dispatch", "clinic", "market", "firehouse", "army", "power", "ranch", "lab", "underworld" } },
} :: { Campaign }

-- Every mission, campaign by campaign (10 each), filled in by shared/Missions data below.
Missions.List = {} :: { MissionDef }

-- ── The missions ──────────────────────────────────────────────────────────
-- Written compactly: a Spec is a MissionDef without the fields add() derives (id = mission = "<campaign>_<number>",
-- campaign) and with loadTime / unloadTime optional (3 s, a serve stop 4 s). Notes for whoever adds more:
--   * pickupAt only with pickups = 1 (every pick-up would be at that place); pickups = 0: the vehicle starts loaded.
--   * dropAt is the LAST drop's place; the drops before it are addresses on the way.
--   * a rush (timeLimit) starts at an address near you (no pickupAt) and never has defend.
--   * horse = lead (livestock truck); kid / patient / survivor = board; serve = street selling (icebox, pizza,
--     bread, soup) after a carry load.
--   * lift and gunner are crew twists: their missions are coop. defend needs defendTime.
--   * labels: the pick-up label ends with AT (" at <place>" is added), the drop label is followed by the place.
--   * 3.2: no level in a Spec: add() computes it (Missions.levelOf) unless the Spec overrides it. A DUO mission
--     (duo = true, or any mission of a DUO campaign) is co-op too; pair needs carrying; switches puts its gate at the
--     last drop (gates = "pickup": at every pick-up).

type Spec = {
	number: number,
	name: string,
	level: number?, -- 3.2: an override; computed by add() (Missions.levelOf) without it
	tier: number,
	reward: number,
	coop: boolean?,
	duo: boolean?, -- 3.2: only with a crew (the DUO campaign)
	gates: string?, -- 3.2: the switches twist's gate: "drop" (default) | "pickup"
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
	giver: string,
	giverRole: string,
	receiver: string,
	receiverRole: string,
}

local function campaignById(campaignId: string): Campaign?
	for _, campaign in Missions.Campaigns do
		if campaign.id == campaignId then
			return campaign
		end
	end
	return nil
end

-- 3.2: the levels a campaign's missions span: from its own level (mission 1) to the next story campaign's (mission
-- 10; MaxLevel after the last one). A DUO campaign is a side story: its own level + DUO_SPAN.
local function levelSpan(campaignId: string): (number, number)
	local campaigns = Missions.Campaigns
	local maxLevel = Config.Levels.MaxLevel
	for index, campaign in campaigns do
		if campaign.id ~= campaignId then
			continue
		end
		if campaign.duo then
			return campaign.level, math.min(maxLevel, campaign.level + DUO_SPAN)
		end
		for after = index + 1, #campaigns do
			local following = campaigns[after]
			if not following.duo then
				return campaign.level, math.clamp(following.level, campaign.level, maxLevel)
			end
		end
		return campaign.level, math.max(campaign.level, maxLevel)
	end
	return 1, 1
end

-- 3.2: the driver level a campaign's mission `number` (1 … FINALE) needs: evenly from the campaign's level to the
-- top of its span, rounded (First Shift 1 → 2: missions 1 – 5 at level 1, 6 – 10 at level 2).
function Missions.levelOf(campaignId: string, number: number): number
	local low, high = levelSpan(campaignId)
	local share = (math.clamp(number, 1, FINALE) - 1) / (FINALE - 1)
	return low + math.floor((high - low) * share + 0.5)
end

local function add(campaign: string, spec: Spec)
	local id = `{campaign}_{spec.number}`
	local info = campaignById(campaign)
	local duo = spec.duo == true or (info ~= nil and info.duo == true)
	local def: MissionDef = {
		id = id,
		mission = id,
		campaign = campaign,
		number = spec.number,
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
		giver = spec.giver,
		receiver = spec.receiver,
		giverRole = spec.giverRole,
		receiverRole = spec.receiverRole,
		timeLimit = spec.timeLimit,
		banditBoost = spec.banditBoost,
		level = spec.level or Missions.levelOf(campaign, spec.number),
		twists = spec.twists,
		defendTime = spec.defendTime,
		coop = if spec.coop or duo then true else nil,
		duo = if duo then true else nil,
		gates = spec.gates,
	}
	table.insert(Missions.List, def)
end

-- ── 1. First Shift (Marge, the dispatcher) ───────────────────────────────
-- Learning the trade: parcels, mail, a cake, a piano, the radio, pizza at night, the first crew job, files the
-- bandits want, tires for the city's vans, and the last mail day at the Stadium Shelter.
do
	add("dispatch", {
		number = 1, name = "Paper Trail", tier = 1, reward = 300, twists = {},
		description = "Three parcels from a sorting room to a family across town.",
		briefing = "New kid, huh? Fine. Three parcels, one address, no excuses. Carry them, load them, bring them. Easy.",
		debrief = "Huh. You did not crash. You might last a week.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "parcel", items = 3, cargo = "Parcels",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = nil, payPerStop = 40,
		pickupLabel = "PICK UP THE PARCELS AT", dropLabel = "DELIVER THE PARCELS TO",
		giver = "Marge, the dispatcher", giverRole = "clerk", receiver = "The Hendersons, a family", receiverRole = "townsperson",
	})
	add("dispatch", {
		number = 2, name = "Mail Call", tier = 1, reward = 350, twists = {},
		description = "Four sacks of old mail for three streets that have not seen a letter since the outbreak.",
		briefing = "The post office burned down in week two, but the mail kept piling up in our back room. Four sacks, three streets. People want their letters, even the bills. Especially the bills, weirdly.",
		debrief = "Mrs. Fisher got a postcard from her son. She cried. I did not. Shut up.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "mail", items = 4, cargo = "Mail Sacks",
		pickups = 1, pickupAt = nil, drops = 3, dropAt = nil, payPerStop = 50,
		pickupLabel = "LOAD THE MAIL SACKS AT", dropLabel = "DROP THE MAIL AT",
		giver = "Otto, the old postman", giverRole = "worker", receiver = "Mrs. Fisher, a neighbour", receiverRole = "townsperson",
	})
	add("dispatch", {
		number = 3, name = "Birthday Emergency", tier = 1, reward = 450, twists = { "spotless" },
		description = "Two birthday cakes from the bakery to a party, on a four minute clock. Not a smudge.",
		briefing = "Little Timmy turns eight today and I am not letting the zombies cancel his party. Two cake boxes from Rosie's bakery, four minutes. If the frosting so much as smudges, don't bother coming back.",
		debrief = "Timmy says it was the best cake of the apocalypse. High praise.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "cake", items = 2, cargo = "Birthday Cakes",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = nil, payPerStop = 60, timeLimit = 240,
		pickupLabel = "PICK UP THE CAKES AT", dropLabel = "DELIVER THE CAKES TO",
		giver = "Rosie, the baker", giverRole = "cook", receiver = "Timmy's mom, at the party", receiverRole = "townsperson",
	})
	add("dispatch", {
		number = 4, name = "Two Pairs of Hands", tier = 2, reward = 600, coop = true, twists = { "lift" },
		description = "A piano and two wardrobes in the Big Move truck. Heavy: carry them in pairs.",
		briefing = "My sister wants grandma's piano and two wardrobes in her new place. Big Move lends the truck, but those things weigh a ton. Bring a friend, or bring a lot of patience.",
		debrief = "The piano is in, and only slightly out of tune. Like my sister.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "furniture", items = 3, cargo = "Furniture",
		pickups = 1, pickupAt = "movers", drops = 1, dropAt = nil, loadTime = 5, unloadTime = 5, payPerStop = 120,
		pickupLabel = "LOAD THE FURNITURE AT", dropLabel = "CARRY IT INTO THE HOUSE AT",
		giver = "Kofi, Big Move Movers", giverRole = "mover", receiver = "Gina, Marge's sister", receiverRole = "townsperson",
	})
	add("dispatch", {
		number = 5, name = "Radio Silence", tier = 2, reward = 700, twists = { "guarded" },
		description = "Spare parts for the Radio Station's transmitter. A horde waits at both ends.",
		briefing = "The Radio Station went quiet last night, and that is how people hear which roads are safe. The tech needs three crates of parts from the old electronics store. Fair warning: the dead love the hum of those transmitters.",
		debrief = "We're back on air. The first request was 'Highway to Hell'. Cute.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 3, cargo = "Radio Parts",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "radio", payPerStop = 140,
		pickupLabel = "PICK UP THE RADIO PARTS AT", dropLabel = "DELIVER THE PARTS TO",
		giver = "Sal, the electronics dealer", giverRole = "shopkeeper", receiver = "DJ Luna, the radio host", receiverRole = "clerk",
	})
	add("dispatch", {
		number = 6, name = "Pizza Night", tier = 2, reward = 750, twists = { "night" },
		description = "Luigi's night pizzas, sold from your window at three street corners. After dark only.",
		briefing = "Luigi only bakes after sundown now. He says the zombies can't smell garlic in the dark. Load his pizzas and sell them at three corners. Keep the engine running and your eyes open.",
		debrief = "Sold out! Luigi wants you every night now. I told him you're expensive.",
		vehicle = nil, load = "carry", unload = "serve", itemKind = "pizza", items = 6, cargo = "Night Pizza",
		pickups = 1, pickupAt = nil, drops = 3, dropAt = nil, payPerStop = 100,
		pickupLabel = "LOAD THE PIZZAS AT", dropLabel = "SELL PIZZA AT",
		giver = "Luigi, the pizza chef", giverRole = "cook", receiver = "Hungry night owls", receiverRole = "townsperson",
	})
	add("dispatch", {
		number = 7, name = "Riding Shotgun", tier = 2, reward = 850, coop = true, twists = { "gunner" },
		description = "Two pick-ups and two drops through runner country. Your passengers shoot, every kill pays triple.",
		briefing = "Two pick-ups, two drops, and a pack of runners on every corner in between. You drive, your friends lean out of the windows and shoot. I pay a bonus for every head they pop from the passenger seat.",
		debrief = "Your crew shoots better than my last three drivers drove.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "parcel", items = 5, cargo = "Express Parcels",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = nil, payPerStop = 130,
		pickupLabel = "PICK UP THE PARCELS AT", dropLabel = "DELIVER THE PARCELS TO",
		giver = "Ben, a sorting clerk", giverRole = "clerk", receiver = "Customers who paid extra", receiverRole = "townsperson",
	})
	add("dispatch", {
		number = 8, name = "Dead Letter Office", tier = 2, reward = 1000, twists = { "hunted" },
		description = "Files from City Hall to Precinct 13. Bandit cars hunt you the whole way.",
		briefing = "City Hall found the files on who sold the army's food to the bandits. Precinct 13 wants them, and so does every bandit with a car. Drive fast, don't stop, and don't read them.",
		debrief = "Somebody's going to jail. Somebody's very angry at you. Welcome to the job.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "documents", items = 2, cargo = "Secret Files",
		pickups = 1, pickupAt = "cityhall", drops = 1, dropAt = "police", payPerStop = 160,
		pickupLabel = "PICK UP THE FILES AT", dropLabel = "HAND THE FILES TO",
		giver = "Mr. Pruitt, the city clerk", giverRole = "clerk", receiver = "Detective Shaw", receiverRole = "officer",
	})
	add("dispatch", {
		number = 9, name = "Wheels of Commerce", tier = 3, reward = 1200, coop = true, twists = { "guarded" },
		description = "Six tire stacks from the Harbor Warehouse to a garage and the Gas Station. Hordes at every stop.",
		briefing = "Half the city's vans are standing on their rims. The Harbor Warehouse still has tires, the Gas Station has a mechanic, and both have a horde parked outside. Bring friends with big guns.",
		debrief = "Forty vans back on the road. My dispatch board finally has colour on it again.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tires", items = 6, cargo = "Tires",
		pickups = 1, pickupAt = "warehouse", drops = 2, dropAt = "gas", loadTime = 4, payPerStop = 200,
		pickupLabel = "LOAD THE TIRES AT", dropLabel = "DROP THE TIRES AT",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Tony, the pump attendant", receiverRole = "attendant",
	})
	add("dispatch", {
		number = 10, name = "Rush Hour of the Dead", tier = 3, reward = 1500, coop = true, twists = { "defend", "gunner" }, defendTime = 45,
		description = "The last mail day: two sorting rooms, three drops, and the Stadium Shelter's gate to hold.",
		briefing = "The last mail day. Everything left in the sorting rooms goes out before they seal the Stadium Shelter for good. The dead will smell the crowd when you get there, so hold the gate while they unload. This is the big one, rookie.",
		debrief = "You're not a rookie anymore. You're a courier. Now go home and sleep, you look terrible.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "parcel", items = 6, cargo = "The Last Mail",
		pickups = 2, pickupAt = nil, drops = 3, dropAt = "stadium", payPerStop = 220,
		pickupLabel = "COLLECT THE LAST PARCELS AT", dropLabel = "DELIVER THE PARCELS TO",
		giver = "Ben, a sorting clerk", giverRole = "clerk", receiver = "Coach Daniels, the shelter warden", receiverRole = "guard",
	})
end

-- ── 2. Code Red (Dr. Novak, the City Clinic) ─────────────────────────────
-- Pills, a heart attack, vaccines, a dead generator, three patients at once, the night ward, a quarantine block,
-- a siege, a looted pharmacy and the booster for the whole city.
do
	add("clinic", {
		number = 1, name = "House Call", tier = 1, reward = 400, twists = {},
		description = "Heart pills from the Corner Pharmacy to an old lady who will not leave her house.",
		briefing = "Mrs. Gruber's heart pills ran out yesterday and she won't leave her house. The Corner Pharmacy has two boxes behind the counter. Please hurry. She's ninety-one and very rude when she's scared.",
		debrief = "Mrs. Gruber says you were late. That means she's feeling better.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "medicine", items = 2, cargo = "Heart Pills",
		pickups = 1, pickupAt = "pharmacy", drops = 1, dropAt = nil, payPerStop = 50,
		pickupLabel = "PICK UP THE MEDICINE AT", dropLabel = "BRING THE MEDICINE TO",
		giver = "Petra, the pharmacist", giverRole = "shopkeeper", receiver = "Mrs. Gruber, a patient at home", receiverRole = "townsperson",
	})
	add("clinic", {
		number = 2, name = "Code Blue", tier = 1, reward = 450, twists = {},
		description = "A heart attack across town: the ambulance, the patient, the clinic. Three minutes.",
		briefing = "A man collapsed in his kitchen, and no, he was not bitten, I checked over the radio. Take the ambulance, sirens on, three minutes. He walks slowly, so park close and be patient. Ha. Patient.",
		debrief = "Stable. Thanks to you. And to me. Mostly to me.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 1, cargo = "Patient",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "clinic", payPerStop = 80, timeLimit = 180,
		pickupLabel = "PICK UP THE PATIENT AT", dropLabel = "RUSH THE PATIENT TO",
		giver = "Mrs. Lindqvist, his wife", giverRole = "townsperson", receiver = "Nurse Ada", receiverRole = "nurse",
	})
	add("clinic", {
		number = 3, name = "Cold Chain", tier = 2, reward = 650, twists = { "spotless" },
		description = "Vaccine coolers from the Biotech Lab to a doctor's home and the clinic. Keep them in good shape.",
		briefing = "The Biotech Lab made a batch of tetanus shots, and half the city has been stepping on rusty nails. The coolers must arrive in good shape or the vaccine is useless. Drive like your grandmother is in the back.",
		debrief = "Every cooler intact. You'd make a decent surgeon. Terrible bedside manner, though.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "vaccine", items = 4, cargo = "Tetanus Shots",
		pickups = 1, pickupAt = "lab", drops = 2, dropAt = "clinic", payPerStop = 120,
		pickupLabel = "LOAD THE COOLERS AT", dropLabel = "DELIVER THE COOLERS TO",
		giver = "Dr. Ito, the lab chief", giverRole = "doctor", receiver = "Nurse Ada", receiverRole = "nurse",
	})
	add("clinic", {
		number = 4, name = "Many Hands", tier = 2, reward = 800, coop = true, twists = { "lift" },
		description = "Two backup generators for the operating room. Each one is a two-person carry.",
		briefing = "The clinic's backup generator coughed and died in the middle of surgery. The Harbor Warehouse has two spares, each heavier than a cow. Bring a friend, so my operating room isn't lit by phone flashlights again.",
		debrief = "Lights on, machines beeping. The most beautiful sound in the world.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "generator", items = 2, cargo = "Generators",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "clinic", loadTime = 5, unloadTime = 5, payPerStop = 150,
		pickupLabel = "LOAD THE GENERATORS AT", dropLabel = "CARRY THEM INTO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Igor, the clinic's janitor", receiverRole = "worker",
	})
	add("clinic", {
		number = 5, name = "Ambulance Chaser", tier = 2, reward = 900, coop = true, twists = { "gunner" },
		description = "Three emergency calls, three homes, one ambulance. The crew in the back shoots.",
		briefing = "Three calls at once, three patients in three homes. One of you drives the ambulance, the rest sit in the back and keep the biters off the stretchers. Shooting from an ambulance is unethical, technically. Do it anyway.",
		debrief = "Three in, three alive. The Hippocratic Oath is flexible in an apocalypse.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 3, cargo = "Patients",
		pickups = 3, pickupAt = nil, drops = 1, dropAt = "clinic", payPerStop = 160,
		pickupLabel = "PICK UP THE PATIENT AT", dropLabel = "BRING THE PATIENTS TO",
		giver = "The Okafor family, worried", giverRole = "townsperson", receiver = "Nurse Ada", receiverRole = "nurse",
	})
	add("clinic", {
		number = 6, name = "Night Nurse", tier = 2, reward = 950, twists = { "night" },
		description = "Medicine bags from the clinic to three feverish homes, after dark only.",
		briefing = "Fevers spike after midnight, and that's when people call. Nurse Ada packed three bags for three homes. The night shift pays better. It also has more teeth.",
		debrief = "Everybody's sleeping now. Except us. Coffee?",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "medicine", items = 3, cargo = "Medicine Bags",
		pickups = 1, pickupAt = "clinic", drops = 3, dropAt = nil, payPerStop = 150,
		pickupLabel = "PICK UP THE MEDICINE BAGS AT", dropLabel = "DELIVER A BAG TO",
		giver = "Nurse Ada", giverRole = "nurse", receiver = "The Petrovs, feverish", receiverRole = "townsperson",
	})
	add("clinic", {
		number = 7, name = "Quarantine Zone", tier = 3, reward = 1100, twists = { "guarded" },
		description = "Blood samples of a new strain, from a trapped nurse to the lab. Hordes at both ends.",
		briefing = "A block in the east has a new strain: faster, meaner. A brave nurse took blood samples and is hiding in the corner shop. Get them to the lab before the horde around her gets bored and comes in.",
		debrief = "Dr. Ito says the samples are fascinating. I hate it when he says fascinating.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "sample", items = 3, cargo = "Blood Samples",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "lab", payPerStop = 220,
		pickupLabel = "COLLECT THE SAMPLES AT", dropLabel = "DELIVER THE SAMPLES TO",
		giver = "Nurse Kim, trapped", giverRole = "nurse", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("clinic", {
		number = 8, name = "Siege at the Ward", tier = 3, reward = 1300, coop = true, twists = { "defend" }, defendTime = 40,
		description = "Four rescued people from Fire Station 9 to the clinic, then hold the entrance while they get in.",
		briefing = "The firefighters pulled four people out of a burning building, and now they need my ward. A horde followed the smoke right to my doors. Bring them in, then hold the entrance while they shuffle inside.",
		debrief = "Four more beds full. I've never been so happy to run out of beds.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 4, cargo = "Patients",
		pickups = 1, pickupAt = "firestation", drops = 1, dropAt = "clinic", payPerStop = 240,
		pickupLabel = "PICK UP THE PATIENTS AT", dropLabel = "BRING THE PATIENTS TO",
		giver = "Chief Ramirez, Fire Station 9", giverRole = "officer", receiver = "Nurse Ada", receiverRole = "nurse",
	})
	add("clinic", {
		number = 9, name = "Pharmacy Run", tier = 3, reward = 1500, coop = true, twists = { "guarded" },
		description = "Six boxes of antibiotics from the overrun pharmacy to a home and the Survivor Camp.",
		briefing = "The Corner Pharmacy was overrun last night, but the stock room is still locked. Petra will open it if you clear the street. The Survivor Camp has been out of antibiotics for a week, and frankly, out of patience too.",
		debrief = "The camp sends a thank-you card. It's a drawing of you shooting a zombie. Very lifelike.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "medicine", items = 6, cargo = "Antibiotics",
		pickups = 1, pickupAt = "pharmacy", drops = 2, dropAt = "camp", loadTime = 4, payPerStop = 260,
		pickupLabel = "LOAD THE MEDICINE AT", dropLabel = "DELIVER THE MEDICINE TO",
		giver = "Petra, the pharmacist", giverRole = "shopkeeper", receiver = "Doc Holloway, the camp medic", receiverRole = "doctor",
	})
	add("clinic", {
		number = 10, name = "Code Red", tier = 3, reward = 2000, coop = true, twists = { "spotless", "defend" }, defendTime = 60,
		description = "The booster for the whole city: lab, two clinics, the Stadium Shelter. Keep it intact and hold the line.",
		briefing = "Dr. Ito has done it: a booster that keeps a bite from turning for a whole day. Six coolers, two field clinics on the way, then the Stadium Shelter, where two thousand people wait. Keep the coolers safe, and when you get there, hold the line while we vaccinate.",
		debrief = "Two thousand people with a fighting chance. Today, you were the medicine.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "vaccine", items = 6, cargo = "Booster Shots",
		pickups = 1, pickupAt = "lab", drops = 3, dropAt = "stadium", payPerStop = 300,
		pickupLabel = "LOAD THE VACCINE AT", dropLabel = "DELIVER THE VACCINE TO",
		giver = "Dr. Ito, the lab chief", giverRole = "doctor", receiver = "Nurse Ada", receiverRole = "nurse",
	})
end

-- ── 3. Empty Shelves (Mr. Patel, FreshMart) ──────────────────────────────
-- Groceries, warm bread from an ice cream truck, potatoes the Rust Riders want, a thawing freezer, water, soup
-- under fire, seedlings, a supermarket sweep, a price war and the city's ration.
do
	add("market", {
		number = 1, name = "Stock Up", tier = 1, reward = 450, twists = {},
		description = "FreshMart's order from the Harbor Warehouse. The eggs are in there somewhere.",
		briefing = "Welcome, welcome! FreshMart has been open for thirty-two years, and no apocalypse is closing it. My order is at the Harbor Warehouse, four bags. Carry them carefully, the eggs are in there somewhere.",
		debrief = "Eggs: intact. You: hired. Have a free banana.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "groceries", items = 4, cargo = "Groceries",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "market", payPerStop = 60,
		pickupLabel = "PICK UP THE GROCERIES AT", dropLabel = "DELIVER THE GROCERIES TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Mr. Patel, FreshMart's owner", receiverRole = "grocer",
	})
	add("market", {
		number = 2, name = "Bread Line", tier = 1, reward = 500, twists = {},
		description = "Warm bread sold from Frosty's ice cream truck at three corners. Hold still while they buy.",
		briefing = "Rosie's ovens work again, but people are too scared to walk to the bakery. Frosty lent us his truck. It still plays the ice cream song, sorry. Park at three corners and sell the bread while it's warm.",
		debrief = "Everybody got a loaf. One man cried into his baguette. Beautiful.",
		vehicle = "icecream", load = "carry", unload = "serve", itemKind = "bread", items = 6, cargo = "Warm Bread",
		pickups = 1, pickupAt = nil, drops = 3, dropAt = nil, payPerStop = 70,
		pickupLabel = "LOAD THE BREAD AT", dropLabel = "SELL BREAD AT",
		giver = "Rosie, the baker", giverRole = "cook", receiver = "Hungry neighbours", receiverRole = "townsperson",
	})
	add("market", {
		number = 3, name = "Farm to Table", tier = 2, reward = 700, twists = { "hunted" },
		description = "Potatoes from the Old Farm in the monster truck. The Rust Riders hunt you all the way back.",
		briefing = "Old Man Jenkins dug up the potatoes, and the Rust Riders heard about it. They'll come at you from everywhere, all the way back. Take his monster truck, and drive over anything that says 'hand it over'.",
		debrief = "Potatoes! Real potatoes! Tonight, everybody eats fries.",
		vehicle = "monster", load = "carry", unload = "carry", itemKind = "sack", items = 5, cargo = "Potatoes",
		pickups = 1, pickupAt = "farm", drops = 1, dropAt = "market", loadTime = 4, payPerStop = 130,
		pickupLabel = "LOAD THE POTATOES AT", dropLabel = "DELIVER THE POTATOES TO",
		giver = "Old Man Jenkins, the farmer", giverRole = "farmer", receiver = "Mr. Patel, FreshMart's owner", receiverRole = "grocer",
	})
	add("market", {
		number = 4, name = "Cold Storage", tier = 2, reward = 800, twists = {},
		description = "Frozen food from a dead basement freezer to FreshMart, five minutes before it thaws.",
		briefing = "The FreshMart freezers are fixed, but the frozen food is still in Mrs. Kowalski's basement, and her power just died. Five minutes before it all thaws. Go, go, go!",
		debrief = "Still frozen. You're faster than my nephew, and he has a bicycle.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "icebox", items = 4, cargo = "Frozen Food",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "market", payPerStop = 140, timeLimit = 300,
		pickupLabel = "PICK UP THE ICE BOXES AT", dropLabel = "DELIVER THE ICE BOXES TO",
		giver = "Mrs. Kowalski, a neighbour", giverRole = "townsperson", receiver = "Mr. Patel, FreshMart's owner", receiverRole = "grocer",
	})
	add("market", {
		number = 5, name = "Water Rights", tier = 2, reward = 900, coop = true, twists = { "lift" },
		description = "Fifty-litre water jugs from the Water Works to a thirsty street and the Survivor Camp.",
		briefing = "The taps at the Survivor Camp have run dry. The Water Works fills big jugs, fifty litres each: heavy for one, light for two. Bring a friend, and leave a few jugs on a thirsty street on the way.",
		debrief = "The camp kids had a water fight. With drinking water. I'll allow it, once.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "water", items = 6, cargo = "Drinking Water",
		pickups = 1, pickupAt = "waterworks", drops = 2, dropAt = "camp", loadTime = 4, unloadTime = 4, payPerStop = 160,
		pickupLabel = "FILL THE JUGS AT", dropLabel = "DELIVER THE WATER TO",
		giver = "Hugo, the waterworks keeper", giverRole = "worker", receiver = "Marta, the camp leader", receiverRole = "townsperson",
	})
	add("market", {
		number = 6, name = "Soup's On", tier = 2, reward = 950, coop = true, twists = { "gunner" },
		description = "Lentil soup from the school kitchen, served at three corners. The passengers keep the line safe.",
		briefing = "The school kitchen cooked two hundred bowls of my famous lentil soup. You park, people come with their bowls, and while you serve, your friends shoot from the windows. Nobody waits in line for zombies. Well, nobody alive.",
		debrief = "Two hundred bowls, two hundred smiles, one complaint about too much cumin. There is no such thing.",
		vehicle = nil, load = "carry", unload = "serve", itemKind = "soup", items = 6, cargo = "Lentil Soup",
		pickups = 1, pickupAt = "school", drops = 3, dropAt = nil, unloadTime = 5, payPerStop = 150,
		pickupLabel = "LOAD THE SOUP AT", dropLabel = "SERVE SOUP AT",
		giver = "Chef Bertrand, the school cook", giverRole = "cook", receiver = "Hungry neighbours", receiverRole = "townsperson",
	})
	add("market", {
		number = 7, name = "Seeds of Hope", tier = 2, reward = 1100, twists = { "spotless" },
		description = "Blight-proof seedlings from the Biotech Lab to the Old Farm. Smooth roads only.",
		briefing = "Dr. Ito grew seedlings that survive the blight. If they reach the Old Farm in one piece, next year we have tomatoes. If they don't, next year we have regret. Smooth roads only, please.",
		debrief = "Jenkins planted them already. He talks to them. I think that's normal for farmers.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "plants", items = 4, cargo = "Seedlings",
		pickups = 1, pickupAt = "lab", drops = 1, dropAt = "farm", payPerStop = 170,
		pickupLabel = "PICK UP THE SEEDLINGS AT", dropLabel = "DELIVER THE SEEDLINGS TO",
		giver = "Dr. Ito, the lab chief", giverRole = "doctor", receiver = "Old Man Jenkins, the farmer", receiverRole = "farmer",
	})
	add("market", {
		number = 8, name = "Supermarket Sweep", tier = 3, reward = 1300, coop = true, twists = { "guarded" },
		description = "Two abandoned shops with full shelves, hordes inside, the Stadium Shelter waiting.",
		briefing = "Two shops in the north were abandoned with full shelves. Full! Shelves! The hordes moved in, so bring a crew and clear them out. Everything goes to the Stadium Shelter.",
		debrief = "The shelter has a full pantry for the first time. I may frame the receipt.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "groceries", items = 6, cargo = "Groceries",
		pickups = 2, pickupAt = nil, drops = 1, dropAt = "stadium", payPerStop = 220,
		pickupLabel = "GRAB THE GROCERIES AT", dropLabel = "DELIVER THE GROCERIES TO",
		giver = "Dusty, a looter gone honest", giverRole = "townsperson", receiver = "Coach Daniels, the shelter warden", receiverRole = "guard",
	})
	add("market", {
		number = 9, name = "Price War", tier = 3, reward = 1500, twists = { "hunted" }, banditBoost = 1.5,
		description = "Five crates of canned food from the docks. Big Earl's bandits want FreshMart closed.",
		briefing = "Big Earl and his bandits want FreshMart closed, so they can sell canned beans at fifty dollars a can. A ship brought five crates to the docks for me, and Earl knows it. Don't let him win, my friend.",
		debrief = "Beans are back to one dollar. Big Earl is crying in his truck.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "crate", items = 5, cargo = "Canned Food",
		pickups = 1, pickupAt = "docks", drops = 1, dropAt = "market", payPerStop = 250,
		pickupLabel = "LOAD THE CRATES AT", dropLabel = "DELIVER THE CRATES TO",
		giver = "Rocco, the dock foreman", giverRole = "worker", receiver = "Mr. Patel, FreshMart's owner", receiverRole = "grocer",
	})
	add("market", {
		number = 10, name = "Empty Shelves", tier = 3, reward = 2200, coop = true, twists = { "guarded", "defend" }, defendTime = 50,
		description = "The city's ration in the big truck: two shelters, then FreshMart's doors to hold.",
		briefing = "The whole city's ration for a month is in the Harbor Warehouse, and every horde in the harbor is sitting on it. Load the big truck, feed two shelters on the way, then hold FreshMart's doors while we fill the shelves. Today, nobody goes hungry.",
		debrief = "Shelves full, city fed. My father would be proud. My accountant is confused.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "groceries", items = 10, cargo = "Rations",
		pickups = 1, pickupAt = "warehouse", drops = 3, dropAt = "market", loadTime = 4, unloadTime = 4, payPerStop = 300,
		pickupLabel = "LOAD THE RATIONS AT", dropLabel = "DELIVER THE RATIONS TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Mr. Patel, FreshMart's owner", receiverRole = "grocer",
	})
end

-- ── 4. Smoke and Sirens (Chief Ramirez, Fire Station 9) ──────────────────
-- Hoses, a burning block, diesel the bandits want, the rescue cutters, dynamite for a firebreak, water at night,
-- runaway kids, a fragile radio repeater, an oil fire and the east side in flames.
do
	add("firehouse", {
		number = 1, name = "Hose Down", tier = 2, reward = 600, twists = {},
		description = "Couplings and patch kits from the Harbor Warehouse to Fire Station 9.",
		briefing = "Rookie, my hoses have more holes than a zombie's alibi. The Harbor Warehouse has three boxes of couplings and patch kits. Bring them to Station 9 and you get to slide down the pole. Once.",
		debrief = "Hoses fixed. Go slide down the pole. That's an order.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tools", items = 3, cargo = "Hose Gear",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "firestation", payPerStop = 100,
		pickupLabel = "PICK UP THE GEAR AT", dropLabel = "DELIVER THE GEAR TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Firefighter Duke", receiverRole = "officer",
	})
	add("firehouse", {
		number = 2, name = "Smoke Eaters", tier = 2, reward = 700, twists = {},
		description = "The school bus, two burning blocks, four people on the street. Five minutes before the roofs fall.",
		briefing = "Two apartment blocks are burning and the people got out onto the street. Grab the school bus and pick them up before the smoke brings every zombie in the district. Five minutes, then the roofs come down.",
		debrief = "Four people out, zero people toasted. Good driving, rookie.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 4, cargo = "Survivors",
		pickups = 2, pickupAt = nil, drops = 1, dropAt = "firestation", payPerStop = 130, timeLimit = 300,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Mr. Haddad, a neighbour", giverRole = "townsperson", receiver = "Firefighter Duke", receiverRole = "officer",
	})
	add("firehouse", {
		number = 3, name = "Fuel the Engines", tier = 2, reward = 850, twists = { "hunted" },
		description = "Diesel barrels from the Harbor Fuel Depot to the fire engines. Bandits hunt the fuel truck.",
		briefing = "Our engines drink diesel like I drink coffee, and we're both running on empty. The bandits know fuel is worth more than gold now, so they'll hunt you the whole way. Don't let them siphon my trucks.",
		debrief = "Tanks full. Coffee next, please.",
		vehicle = "fueltruck", load = "carry", unload = "carry", itemKind = "barrel", items = 4, cargo = "Diesel",
		pickups = 1, pickupAt = "fueldepot", drops = 1, dropAt = "firestation", payPerStop = 150,
		pickupLabel = "LOAD THE FUEL AT", dropLabel = "REFUEL THE ENGINES AT",
		giver = "Hank, the depot worker", giverRole = "worker", receiver = "Firefighter Duke", receiverRole = "officer",
	})
	add("firehouse", {
		number = 4, name = "Jaws of Life", tier = 2, reward = 950, coop = true, twists = { "lift" },
		description = "The heavy hydraulic cutters from the station to two crash sites. Carry them in pairs.",
		briefing = "Two crash sites, people pinned in their cars. The hydraulic cutters are heavy beasts, so take a partner: one person carries slow, two carry fast. Speed saves lives.",
		debrief = "Two drivers cut out of two wrecks. That's what this job is about.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tools", items = 4, cargo = "Rescue Cutters",
		pickups = 1, pickupAt = "firestation", drops = 2, dropAt = nil, loadTime = 5, unloadTime = 5, payPerStop = 170,
		pickupLabel = "LOAD THE RESCUE GEAR AT", dropLabel = "BRING THE GEAR TO",
		giver = "Firefighter Duke", giverRole = "officer", receiver = "A trapped driver", receiverRole = "townsperson",
	})
	add("firehouse", {
		number = 5, name = "Firebreak", tier = 3, reward = 1100, coop = true, twists = { "quiet" },
		description = "Dynamite from the Train Yard to blast a firebreak at the Old Farm. Every shot costs condition.",
		briefing = "A grass fire is crawling toward the Old Farm. We blast a firebreak, which means you're hauling dynamite from the Train Yard. Do not shoot. I mean it. Not even at the really ugly ones.",
		debrief = "Boom, on purpose this time. The farm is safe.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 3, cargo = "Dynamite",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "farm", payPerStop = 220,
		pickupLabel = "LOAD THE DYNAMITE AT", dropLabel = "DELIVER THE DYNAMITE TO",
		giver = "Gus, the yard foreman", giverRole = "foreman", receiver = "Old Man Jenkins, the farmer", receiverRole = "farmer",
	})
	add("firehouse", {
		number = 6, name = "Night Watch", tier = 3, reward = 1200, twists = { "night" },
		description = "Water jugs for three streets with dry hydrants, before the night's fires start.",
		briefing = "The hydrants in the old town are dry, and night is when the fires start: candles, cooking fires, idiots with flamethrowers. Leave water on three streets so people can put out the small fires before they get big.",
		debrief = "Quiet night. The best kind. Thank you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "water", items = 6, cargo = "Fire Water",
		pickups = 1, pickupAt = "waterworks", drops = 3, dropAt = nil, payPerStop = 200,
		pickupLabel = "LOAD THE WATER AT", dropLabel = "DROP THE WATER AT",
		giver = "Hugo, the waterworks keeper", giverRole = "worker", receiver = "Mrs. Abara, the block captain", receiverRole = "townsperson",
	})
	add("firehouse", {
		number = 7, name = "Lost and Found", tier = 3, reward = 1300, coop = true, twists = { "gunner" },
		description = "Three kids who ran home at the fire alarm, back to school in the bus. The passengers shoot.",
		briefing = "The fire alarm at the school went off and three kids ran home on their own. Their parents are hiding them in three houses. Pick them up in the bus, your friends shoot from the windows, and nobody tells Principal Moore we lost them.",
		debrief = "Three kids, counted twice. Principal Moore never needs to know.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "kid", items = 3, cargo = "Kids",
		pickups = 3, pickupAt = nil, drops = 1, dropAt = "school", payPerStop = 220,
		pickupLabel = "PICK UP THE KID AT", dropLabel = "BRING THE KIDS TO",
		giver = "Mr. Sato, a worried parent", giverRole = "townsperson", receiver = "Ms. Parker, the teacher", receiverRole = "teacher",
	})
	add("firehouse", {
		number = 8, name = "Ladder 9", tier = 3, reward = 1500, twists = { "spotless" },
		description = "A delicate radio repeater from the Radio Station to the fire station. One bad bump and it's scrap.",
		briefing = "Our radio repeater is fried, so every call goes to the wrong station. The Radio Station built us a new one. It's delicate, like my feelings. If it rattles too hard in your trunk, it's scrap.",
		debrief = "Calls coming in clear. I can hear the dispatcher yawning. Perfect.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 3, cargo = "Radio Repeater",
		pickups = 1, pickupAt = "radio", drops = 1, dropAt = "firestation", payPerStop = 240,
		pickupLabel = "PICK UP THE REPEATER AT", dropLabel = "DELIVER THE REPEATER TO",
		giver = "DJ Luna, the radio host", giverRole = "clerk", receiver = "Firefighter Duke", receiverRole = "officer",
	})
	add("firehouse", {
		number = 9, name = "Oil Fire", tier = 4, reward = 1800, coop = true, twists = { "guarded" },
		description = "Foam concentrate for an oil fire at the Power Plant. Hordes at the warehouse and at the plant.",
		briefing = "The Power Plant has an oil fire, and water makes it worse. The warehouse has foam concentrate, and the plant has a horde that wandered in to warm up. Clear them, deliver the foam, and nobody breathe the smoke.",
		debrief = "Fire's out. Volkov owes me one, and I will collect.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "crate", items = 5, cargo = "Fire Foam",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "powerplant", payPerStop = 300,
		pickupLabel = "LOAD THE FOAM AT", dropLabel = "DELIVER THE FOAM TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Engineer Volkov", receiverRole = "foreman",
	})
	add("firehouse", {
		number = 10, name = "Smoke and Sirens", tier = 4, reward = 2800, coop = true, twists = { "defend", "gunner" }, defendTime = 60,
		description = "The east side burns: two rooftops of survivors, a safe house, and the stadium gate to hold.",
		briefing = "Half of the east side is on fire, and people are trapped between the flames and the dead. We take the bus, we go in, we pick up everyone we find. At the stadium you hold the gate until the last of them is inside. Station 9 leaves no one behind.",
		debrief = "Eight lives today. You're one of us now. There's a helmet with your name on it.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 8, cargo = "Survivors",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "stadium", payPerStop = 340,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Ms. Rivera, a survivor", giverRole = "townsperson", receiver = "Coach Daniels, the shelter warden", receiverRole = "guard",
	})
end

-- ── 5. Iron Supply (Captain Reyes, the Military Base) ────────────────────
-- Ammo, hot stew at the checkpoints, dynamite for the tunnel, a downed chopper, letters from home, the heavy
-- weapons, fuel for the planes, classified files, a radar and the night before the big horde.
do
	add("army", {
		number = 1, name = "Ammo Run", tier = 2, reward = 800, twists = {},
		description = "Ammo from the Harbor Docks to the base in the army's armored truck.",
		briefing = "Civilian, my men are down to harsh language. The ammo came in at the Harbor Docks. Take the armored truck through the tunnel and bring it to the base. Don't stop for hitchhikers.",
		debrief = "Ammo received. You may now salute. Badly, like a civilian.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "ammo", items = 4, cargo = "Ammo Crates",
		pickups = 1, pickupAt = "docks", drops = 1, dropAt = "base", payPerStop = 150,
		pickupLabel = "LOAD THE AMMO AT", dropLabel = "DELIVER THE AMMO TO",
		giver = "Rocco, the dock foreman", giverRole = "worker", receiver = "Sergeant Hayes", receiverRole = "soldier",
	})
	add("army", {
		number = 2, name = "Mess Hall", tier = 2, reward = 900, twists = {},
		description = "Hot stew from a diner, served from your window at three army checkpoints.",
		briefing = "My checkpoints have eaten cold beans for a month and morale is lower than a crawler. A diner in town cooks hot stew. Pick it up, stop at three checkpoints and serve it from your window. Hold still while they eat. They're armed.",
		debrief = "The men say it's the best stew they've ever had. They're lying, but they're happy.",
		vehicle = nil, load = "carry", unload = "serve", itemKind = "soup", items = 6, cargo = "Hot Stew",
		pickups = 1, pickupAt = nil, drops = 3, dropAt = nil, unloadTime = 5, payPerStop = 140,
		pickupLabel = "PICK UP THE STEW AT", dropLabel = "SERVE STEW AT",
		giver = "Dolores, the diner cook", giverRole = "cook", receiver = "Soldiers at the checkpoint", receiverRole = "soldier",
	})
	add("army", {
		number = 3, name = "Boom Sticks", tier = 3, reward = 1100, twists = { "quiet" },
		description = "Dynamite from the Train Yard to the base, to collapse the north tunnel. No shooting.",
		briefing = "My engineers need dynamite to collapse the north tunnel before the big horde gets through. The Train Yard has a stash. No shooting near the cargo, civilian. Not one round. If you blow up, I have to do paperwork.",
		debrief = "Tunnel's down, you're still in one piece. Paperwork avoided.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 4, cargo = "Dynamite",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "base", payPerStop = 220,
		pickupLabel = "LOAD THE DYNAMITE AT", dropLabel = "DELIVER THE DYNAMITE TO",
		giver = "Gus, the yard foreman", giverRole = "foreman", receiver = "Sergeant Hayes", receiverRole = "soldier",
	})
	add("army", {
		number = 4, name = "Wounded in Action", tier = 3, reward = 1300, coop = true, twists = { "gunner" },
		description = "A chopper down at the Old Airfield: three wounded soldiers to the clinic. The crew rides shotgun.",
		briefing = "A chopper went down at the Old Airfield. Three of my boys are hurt and can't hold a rifle. You drive the ambulance, your friends ride shotgun. Bring them to the City Clinic. Nobody gets left behind.",
		debrief = "All three will walk again. I owe you a beer. Army beer. Sorry in advance.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 3, cargo = "Wounded Soldiers",
		pickups = 1, pickupAt = "airfield", drops = 1, dropAt = "clinic", payPerStop = 250,
		pickupLabel = "PICK UP THE WOUNDED AT", dropLabel = "BRING THE WOUNDED TO",
		giver = "Corporal Diaz, the pilot", giverRole = "soldier", receiver = "Nurse Ada", receiverRole = "nurse",
	})
	add("army", {
		number = 5, name = "Mail From Home", tier = 3, reward = 1400, twists = { "night" },
		description = "Weeks of letters for the soldiers. The night patrol opens the gate after dark only.",
		briefing = "Letters from home have been stuck in a post room in town for weeks. My men haven't heard from their families since spring. The night patrol opens the gate after dark only. Bring the sacks.",
		debrief = "Private Jones found out he's a father. He fainted. Good fainting, though.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "mail", items = 3, cargo = "Letters From Home",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "base", payPerStop = 220,
		pickupLabel = "PICK UP THE MAIL AT", dropLabel = "DELIVER THE MAIL TO",
		giver = "Otto, the old postman", giverRole = "worker", receiver = "Private Jones", receiverRole = "soldier",
	})
	add("army", {
		number = 6, name = "Lock and Load", tier = 3, reward = 1600, coop = true, twists = { "lift" },
		description = "Precinct 13's heavy weapons lockers to the base. Each case is a two-person carry.",
		briefing = "Precinct 13 is giving us their heavy weapons lockers. Each case weighs as much as a private. Carry them in pairs, or carry them slowly while the dead catch up. Your choice.",
		debrief = "Armory stocked. The base is a fortress now.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "weapons", items = 4, cargo = "Weapons Cases",
		pickups = 1, pickupAt = "police", drops = 1, dropAt = "base", loadTime = 5, unloadTime = 5, payPerStop = 260,
		pickupLabel = "LOAD THE WEAPONS AT", dropLabel = "DELIVER THE WEAPONS TO",
		giver = "Sergeant Kowalczyk, the desk sergeant", giverRole = "officer", receiver = "Sergeant Hayes", receiverRole = "soldier",
	})
	add("army", {
		number = 7, name = "Fuel Convoy", tier = 3, reward = 1800, coop = true, twists = { "guarded" },
		description = "Six barrels of aviation fuel from the depot to the Old Airfield. Hordes at both ends.",
		briefing = "The airfield is our way out if the base falls, and the planes are dry. The depot has six barrels, and both ends of the trip are crawling with hordes. Take a crew. Shoot everything that's walking and shouldn't be.",
		debrief = "Planes fuelled. Our escape route is open, thanks to you.",
		vehicle = "fueltruck", load = "carry", unload = "carry", itemKind = "barrel", items = 6, cargo = "Aviation Fuel",
		pickups = 1, pickupAt = "fueldepot", drops = 1, dropAt = "airfield", payPerStop = 280,
		pickupLabel = "LOAD THE FUEL AT", dropLabel = "REFUEL THE PLANES AT",
		giver = "Hank, the depot worker", giverRole = "worker", receiver = "Corporal Diaz, the pilot", receiverRole = "soldier",
	})
	add("army", {
		number = 8, name = "Classified", tier = 4, reward = 2200, twists = { "hunted" },
		description = "Briefcases from the Biotech Lab to the base. Every bandit in the city wants them.",
		briefing = "The lab has files on what really started all this. Bandits will pay anything for them, and they've heard you're the driver. Pick up the briefcases. Don't open them. Don't stop.",
		debrief = "Files secure. Forget you ever saw them. That's an order, civilian.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "documents", items = 2, cargo = "Classified Files",
		pickups = 1, pickupAt = "lab", drops = 1, dropAt = "base", payPerStop = 320,
		pickupLabel = "PICK UP THE BRIEFCASES AT", dropLabel = "DELIVER THE BRIEFCASES TO",
		giver = "Dr. Ito, the lab chief", giverRole = "doctor", receiver = "Captain Reyes", receiverRole = "soldier",
	})
	add("army", {
		number = 9, name = "Eyes in the Sky", tier = 4, reward = 2500, twists = { "spotless" },
		description = "Fragile radar parts from the airfield to the top of the Lighthouse.",
		briefing = "We're building a radar post on the Lighthouse to see the hordes coming along the coast. The parts are at the airfield, and they're fragile. One pothole too many and we're blind again.",
		debrief = "Radar's up. We can see them coming now. That's comforting. Mostly.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 3, cargo = "Radar Parts",
		pickups = 1, pickupAt = "airfield", drops = 1, dropAt = "lighthouse", payPerStop = 330,
		pickupLabel = "LOAD THE RADAR PARTS AT", dropLabel = "DELIVER THE PARTS TO",
		giver = "Corporal Diaz, the pilot", giverRole = "soldier", receiver = "Old Tom, the lighthouse keeper", receiverRole = "townsperson",
	})
	add("army", {
		number = 10, name = "Iron Supply", tier = 4, reward = 3500, coop = true, twists = { "defend", "hunted" }, defendTime = 75,
		description = "The last ammo in two gun shops, hunted all the way, and the base gate to hold while it's unloaded.",
		briefing = "The big horde comes down from the mountains tonight or tomorrow. Two gun shops in town still have ammo, and every bandit gang wants it too. Load up, punch through, and at the base, hold the gate while my men stock the walls. This is it, soldier.",
		debrief = "The line held. You held it. Captain Reyes salutes you.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "ammo", items = 8, cargo = "Ammo Crates",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "base", payPerStop = 380,
		pickupLabel = "LOAD THE AMMO AT", dropLabel = "DELIVER THE AMMO TO",
		giver = "Mack, the gun store owner", giverRole = "shopkeeper", receiver = "Sergeant Hayes", receiverRole = "soldier",
	})
end

-- ── 6. Lights Out (Engineer Volkov, the Power Plant) ─────────────────────
-- Tools, life-support batteries, generators for the bingo, valves, a blast at the river intake, the blackout,
-- copper thieves, cooling water, the control room and the stadium's lights.
do
	add("power", {
		number = 1, name = "Spare Parts", tier = 2, reward = 900, twists = {},
		description = "Three toolboxes from the Harbor Warehouse for a turbine that sounds like a dying walrus.",
		briefing = "Comrade courier! Turbine three is making a noise like a dying walrus. I need three toolboxes from the Harbor Warehouse. Quickly, before the walrus dies.",
		debrief = "Walrus fixed. The turbine sings again. Like opera.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tools", items = 3, cargo = "Toolboxes",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "powerplant", payPerStop = 160,
		pickupLabel = "PICK UP THE TOOLBOXES AT", dropLabel = "DELIVER THE TOOLS TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Engineer Volkov", receiverRole = "foreman",
	})
	add("power", {
		number = 2, name = "Battery Life", tier = 2, reward = 1000, twists = { "spotless" },
		description = "Battery packs for a home breathing machine and the clinic's life support. Cracked ones leak.",
		briefing = "The clinic's life support runs on battery packs between blackouts. Full packs are fragile, and cracked ones leak acid. Two for a family with a sick grandpa on the way, two for the clinic. Gentle, like eggs. Electric eggs.",
		debrief = "Grandpa's breathing machine hums again. So does my heart.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "battery", items = 4, cargo = "Battery Packs",
		pickups = 1, pickupAt = "powerplant", drops = 2, dropAt = "clinic", payPerStop = 170,
		pickupLabel = "PICK UP THE BATTERIES AT", dropLabel = "DELIVER THE BATTERIES TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Nurse Ada", receiverRole = "nurse",
	})
	add("power", {
		number = 3, name = "Bingo Night", tier = 3, reward = 1200, coop = true, twists = { "lift" },
		description = "Two generators for two retirement homes. Each weighs more than Volkov's mother-in-law.",
		briefing = "Two retirement homes have no light, no heat, and no TV for the bingo. Each generator weighs more than my mother-in-law. Take a strong friend. Or two.",
		debrief = "Bingo night is back. The old ladies want to adopt you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "generator", items = 2, cargo = "Generators",
		pickups = 1, pickupAt = "powerplant", drops = 2, dropAt = nil, loadTime = 5, unloadTime = 5, payPerStop = 220,
		pickupLabel = "LOAD THE GENERATORS AT", dropLabel = "DELIVER A GENERATOR TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Mrs. Albescu, the bingo caller", receiverRole = "townsperson",
	})
	add("power", {
		number = 4, name = "Pipe Dream", tier = 3, reward = 1300, twists = { "guarded" },
		description = "Spare valves from the Water Works for the cracked cooling pipes. The dead nest by the warm pipes.",
		briefing = "The cooling pipes are cracked, and the Water Works has my spare valves. A horde has made a nest at both places. They like the warm pipes. Clear them, bring the valves.",
		debrief = "Pipes sealed. The dead are cold again. Good.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tools", items = 4, cargo = "Valves",
		pickups = 1, pickupAt = "waterworks", drops = 1, dropAt = "powerplant", payPerStop = 230,
		pickupLabel = "LOAD THE VALVES AT", dropLabel = "DELIVER THE VALVES TO",
		giver = "Hugo, the waterworks keeper", giverRole = "worker", receiver = "Engineer Volkov", receiverRole = "foreman",
	})
	add("power", {
		number = 5, name = "Clogged", tier = 3, reward = 1500, twists = { "quiet" },
		description = "Dynamite to blow the wreck blocking the river intake at the Water Works. Don't shoot.",
		briefing = "A pile of wrecked cars, and worse, blocks the river intake at the Water Works. We blow it up. You bring the dynamite. If you shoot, we blow you up instead. Nobody wants that.",
		debrief = "Intake clear, river flowing. Excellent explosion. Nine out of ten.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 3, cargo = "Dynamite",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "waterworks", payPerStop = 250,
		pickupLabel = "LOAD THE DYNAMITE AT", dropLabel = "DELIVER THE DYNAMITE TO",
		giver = "Gus, the yard foreman", giverRole = "foreman", receiver = "Hugo, the waterworks keeper", receiverRole = "worker",
	})
	add("power", {
		number = 6, name = "Blackout", tier = 3, reward = 1600, twists = { "night" },
		description = "The grid is down after dark: your car is loaded, three homes on breathing machines, five minutes.",
		briefing = "The grid went down at sunset, and three homes have people on breathing machines. Your car is already loaded, I packed it myself. Five minutes. In the dark. With the dead. Go!",
		debrief = "Three machines humming, three people breathing. Now go breathe yourself.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "battery", items = 6, cargo = "Battery Packs",
		pickups = 0, pickupAt = nil, drops = 3, dropAt = nil, payPerStop = 240, timeLimit = 300,
		pickupLabel = "PICK UP THE BATTERIES AT", dropLabel = "DELIVER BATTERIES TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Mr. Okoro, in the dark", receiverRole = "townsperson",
	})
	add("power", {
		number = 7, name = "Copper Thieves", tier = 3, reward = 1800, coop = true, twists = { "hunted", "gunner" },
		description = "Transformer parts from the Train Yard. Copper thieves hunt you, the passengers hunt them.",
		briefing = "Bandits are stripping my transformers to sell the copper. I found new parts at the Train Yard, but the thieves are watching, and they will hunt you. Friends in the passenger seats: teach them that copper is expensive.",
		debrief = "Parts delivered. The thieves are now very afraid of passenger seats.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 4, cargo = "Transformer Parts",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "powerplant", payPerStop = 270,
		pickupLabel = "LOAD THE PARTS AT", dropLabel = "DELIVER THE PARTS TO",
		giver = "Gus, the yard foreman", giverRole = "foreman", receiver = "Engineer Volkov", receiverRole = "foreman",
	})
	add("power", {
		number = 8, name = "Cooling Water", tier = 4, reward = 2200, coop = true, twists = { "guarded" },
		description = "Eight jugs of treated water for the overheating boilers. Hordes at both ends.",
		briefing = "The boilers are overheating. If they overheat more, the plant becomes a very large firework. Eight jugs of treated water from the Water Works, and hordes at both ends, because I am unlucky.",
		debrief = "Temperature normal. City not exploded. Today is a good day.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "water", items = 8, cargo = "Treated Water",
		pickups = 1, pickupAt = "waterworks", drops = 1, dropAt = "powerplant", loadTime = 4, unloadTime = 4, payPerStop = 320,
		pickupLabel = "LOAD THE WATER AT", dropLabel = "DELIVER THE WATER TO",
		giver = "Hugo, the waterworks keeper", giverRole = "worker", receiver = "Engineer Volkov", receiverRole = "foreman",
	})
	add("power", {
		number = 9, name = "Control Room", tier = 4, reward = 2600, twists = { "spotless" },
		description = "Hand-built control boards for the grid computers in City Hall's basement. Delicate as snowflakes.",
		briefing = "The grid's control computers sit in City Hall's basement, and they are older than me. I built new boards, delicate as snowflakes. One bad bump and the whole city stays dark.",
		debrief = "Control room online. I can light any street with one click. I feel like a god. A tired god.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 3, cargo = "Control Boards",
		pickups = 1, pickupAt = "powerplant", drops = 1, dropAt = "cityhall", payPerStop = 330,
		pickupLabel = "PICK UP THE CONTROL BOARDS AT", dropLabel = "DELIVER THE BOARDS TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Mr. Pruitt, the city clerk", receiverRole = "clerk",
	})
	add("power", {
		number = 10, name = "Lights Out", tier = 4, reward = 4000, coop = true, twists = { "lift", "defend" }, defendTime = 60,
		description = "Four huge generators to light the Stadium Shelter. Carry them in pairs, hold the stadium while they're wired.",
		briefing = "The main grid is gone, but four big generators can light the Stadium Shelter and the streets around it. They're the heaviest things I own. Bring a crew to carry, and hold the stadium while I wire them in. When the lights come on, the dead will come to look.",
		debrief = "The stadium is lit. From the plant I can see it glowing. The whole city can. Hope, comrade.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "generator", items = 4, cargo = "Generators",
		pickups = 1, pickupAt = "powerplant", drops = 2, dropAt = "stadium", loadTime = 5, unloadTime = 5, payPerStop = 380,
		pickupLabel = "LOAD THE GENERATORS AT", dropLabel = "DELIVER THE GENERATORS TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Coach Daniels, the shelter warden", receiverRole = "guard",
	})
end

-- ── 7. Wild West End (Walt, the rancher) ─────────────────────────────────
-- Two mares, oats the Rust Riders want, a spooked stallion, the fence, stolen horses at night, tractor tires,
-- Walt's life savings, rifles for the showdown, the long drive and the last raid.
do
	add("ranch", {
		number = 1, name = "Saddle Up", tier = 2, reward = 1000, twists = {},
		description = "Lead two mares into the livestock truck and out at the Riverside Riding School.",
		briefing = "Howdy, partner. Two of my mares are going to the Riding School. They teach the kids to ride, and a horse is quieter than a car out there. Lead 'em in gentle. They kick harder than zombies.",
		debrief = "Emma says they settled right in. You've got soft hands, partner.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 2, cargo = "Mares",
		pickups = 1, pickupAt = "ranch", drops = 1, dropAt = "stables", payPerStop = 180,
		pickupLabel = "LEAD THE HORSES IN AT", dropLabel = "LEAD THE HORSES OUT AT",
		giver = "Jesse, the ranch hand", giverRole = "rancher", receiver = "Emma, the riding instructor", receiverRole = "rider",
	})
	add("ranch", {
		number = 2, name = "Feed Run", tier = 2, reward = 1100, twists = { "hunted" },
		description = "Six sacks of oats from the Old Farm in the monster truck. The Rust Riders hunt every feed truck.",
		briefing = "My horses eat more than a bunkhouse of cowboys, and the Rust Riders hit every feed truck on the west road. Jenkins has six sacks of oats. Take his monster truck and drive like the devil's on your tail. Because he will be.",
		debrief = "Oats in the barn, Rust Riders in the ditch. Good day's work.",
		vehicle = "monster", load = "carry", unload = "carry", itemKind = "sack", items = 6, cargo = "Oats",
		pickups = 1, pickupAt = "farm", drops = 1, dropAt = "ranch", loadTime = 4, payPerStop = 190,
		pickupLabel = "LOAD THE OATS AT", dropLabel = "DELIVER THE OATS TO",
		giver = "Old Man Jenkins, the farmer", giverRole = "farmer", receiver = "Jesse, the ranch hand", receiverRole = "rancher",
	})
	add("ranch", {
		number = 3, name = "Horse Whisperer", tier = 3, reward = 1300, twists = { "spotless" },
		description = "Thunder, Walt's spooked stallion, home from the Riding School without a scratch.",
		briefing = "Thunder, my old stallion, got spooked by a horde and won't let anybody near him at the Riding School. He trusts slow drivers. Bring him home without a scratch, or he'll never get in a truck again.",
		debrief = "Thunder's home, eating apples like nothing happened. Horses. Gotta love 'em.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 1, cargo = "Thunder",
		pickups = 1, pickupAt = "stables", drops = 1, dropAt = "ranch", payPerStop = 220,
		pickupLabel = "LEAD THE STALLION IN AT", dropLabel = "LEAD HIM HOME TO",
		giver = "Emma, the riding instructor", giverRole = "rider", receiver = "Walt, the rancher", receiverRole = "rancher",
	})
	add("ranch", {
		number = 4, name = "Fence Line", tier = 3, reward = 1400, coop = true, twists = { "gunner" },
		description = "Fencing tools across bandit country to the ranch. Walt pays for every varmint the passengers drop.",
		briefing = "The west fence is down, and the dead wander right into my paddock. The fencing tools are at the Harbor Warehouse, a long ride through bandit country. Bring partners to ride shotgun. I pay for every varmint they drop.",
		debrief = "Fence up, varmints down. Y'all can ride with me any day.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tools", items = 4, cargo = "Fencing Tools",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "ranch", payPerStop = 240,
		pickupLabel = "LOAD THE FENCING TOOLS AT", dropLabel = "DELIVER THE TOOLS TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Jesse, the ranch hand", receiverRole = "rancher",
	})
	add("ranch", {
		number = 5, name = "Moonlight Rustlers", tier = 3, reward = 1600, twists = { "night" },
		description = "Two stolen horses hidden in the Old Farm's barn. Only fools move horses by daylight.",
		briefing = "Rustlers stole two of my horses and hid 'em in the Old Farm's barn. Jenkins tipped me off. Only fools move horses in daylight with bandits watching, so we go at night. Quiet-like.",
		debrief = "Both horses home. The rustlers will wake up to an empty barn and a bad mood.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 2, cargo = "Stolen Horses",
		pickups = 1, pickupAt = "farm", drops = 1, dropAt = "ranch", payPerStop = 250,
		pickupLabel = "LEAD THE HORSES IN AT", dropLabel = "LEAD THE HORSES OUT AT",
		giver = "Old Man Jenkins, the farmer", giverRole = "farmer", receiver = "Walt, the rancher", receiverRole = "rancher",
	})
	add("ranch", {
		number = 6, name = "Wagon Wheels", tier = 3, reward = 1700, coop = true, twists = { "lift" },
		description = "Heavy tractor tires from the Train Yard. Each one is a two-person job.",
		briefing = "My trucks are on their last legs. The Train Yard has a stack of heavy tractor tires. Each one's a two-man job, unless you like rolling 'em by yourself while the dead chew on your boots.",
		debrief = "New boots for the trucks. Er, tires. You know what I mean.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tires", items = 6, cargo = "Tractor Tires",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "ranch", loadTime = 4, unloadTime = 4, payPerStop = 260,
		pickupLabel = "LOAD THE TIRES AT", dropLabel = "DELIVER THE TIRES TO",
		giver = "Gus, the yard foreman", giverRole = "foreman", receiver = "Jesse, the ranch hand", receiverRole = "rancher",
	})
	add("ranch", {
		number = 7, name = "Gold Rush", tier = 4, reward = 2000, twists = { "hunted" }, banditBoost = 2,
		description = "Walt's life savings from the bank to the ranch in the armored truck. Every bandit west of the river knows.",
		briefing = "I'm buying the land next door, and the seller only takes cash. My life savings are in the bank downtown. Every bandit west of the river will know the moment you open that vault. The army lent us their armored truck. Use it.",
		debrief = "Land bought. The ranch is twice as big now. Come for Sunday dinner.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "cash", items = 3, cargo = "Life Savings",
		pickups = 1, pickupAt = "bank", drops = 1, dropAt = "ranch", payPerStop = 300,
		pickupLabel = "LOAD THE CASH AT", dropLabel = "DELIVER THE CASH TO",
		giver = "Mr. Gold, the bank manager", giverRole = "banker", receiver = "Walt, the rancher", receiverRole = "rancher",
	})
	add("ranch", {
		number = 8, name = "Showdown", tier = 4, reward = 2300, coop = true, twists = { "guarded" },
		description = "Rifles from Precinct 13's lockup for the ranch's walls. The dead camp on its steps.",
		briefing = "The Rust Riders sent word: they're coming for the ranch. The lockup at Precinct 13 has rifles, if you can get through the dead camped on its steps. Bring a posse.",
		debrief = "Rifles on the walls. Let 'em come.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "weapons", items = 4, cargo = "Rifles",
		pickups = 1, pickupAt = "police", drops = 1, dropAt = "ranch", payPerStop = 320,
		pickupLabel = "LOAD THE RIFLES AT", dropLabel = "DELIVER THE RIFLES TO",
		giver = "Sergeant Kowalczyk, the desk sergeant", giverRole = "officer", receiver = "Jesse, the ranch hand", receiverRole = "rancher",
	})
	add("ranch", {
		number = 9, name = "The Long Drive", tier = 4, reward = 2700, coop = true, twists = { "gunner" },
		description = "Two horses on a long road: one for a homestead, one for the Survivor Camp's scouts.",
		briefing = "The Survivor Camp needs horses for scouting, and a homestead on the way wants one too. Two horses, two stops, a long road through bandit land. Your partners shoot from the cab. The horses don't like gunfire, but they like bandits less.",
		debrief = "A scout on horseback at the camp. Prettiest sight I've seen in years.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 2, cargo = "Horses",
		pickups = 1, pickupAt = "ranch", drops = 2, dropAt = "camp", payPerStop = 330,
		pickupLabel = "LEAD THE HORSES IN AT", dropLabel = "LEAD THE HORSES OUT AT",
		giver = "Jesse, the ranch hand", giverRole = "rancher", receiver = "Marta, the camp leader", receiverRole = "townsperson",
	})
	add("ranch", {
		number = 10, name = "Wild West End", tier = 4, reward = 4500, coop = true, twists = { "defend", "hunted" }, defendTime = 75,
		description = "The last of the herd from the burned stables, hunted by the Rust Riders, and the ranch to hold.",
		briefing = "This is it, partner. The Rust Riders burned the Riding School's stables, and the last of my herd is waiting there. Bring the last two home, leave one at a safe barn on the way, then hold the ranch with me. They're coming for everything I've got.",
		debrief = "The Rust Riders are done. The west is ours again. You're family now, partner.",
		vehicle = "livestock", load = "lead", unload = "lead", itemKind = "horse", items = 2, cargo = "The Last Herd",
		pickups = 1, pickupAt = "stables", drops = 2, dropAt = "ranch", payPerStop = 380,
		pickupLabel = "LEAD THE HORSES IN AT", dropLabel = "LEAD THE HORSES OUT AT",
		giver = "Emma, the riding instructor", giverRole = "rider", receiver = "Walt, the rancher", receiverRole = "rancher",
	})
end

-- ── 8. Patient Zero (Dr. Ito, the Biotech Lab) ───────────────────────────
-- Miracle blood, microscopes guarded by the faculty, a prisoner who doesn't turn, nitro, Frosty's freezers, three
-- nests, a rival syndicate, the first one bitten, the trial doses and the cure.
do
	add("lab", {
		number = 1, name = "Specimen Jar", tier = 2, reward = 1200, twists = { "spotless" },
		description = "Blood of a patient who was bitten and did not turn, from the clinic to the lab. Intact.",
		briefing = "Dr. Novak has two blood samples from a patient who was bitten and did not turn. Fascinating. If the cases crack, the samples are worthless and we've wasted a miracle. Drive smoothly.",
		debrief = "The samples are perfect. Perfectly fascinating.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "sample", items = 2, cargo = "Miracle Blood",
		pickups = 1, pickupAt = "clinic", drops = 1, dropAt = "lab", payPerStop = 200,
		pickupLabel = "PICK UP THE SAMPLES AT", dropLabel = "DELIVER THE SAMPLES TO",
		giver = "Dr. Novak, the clinic's doctor", giverRole = "doctor", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("lab", {
		number = 2, name = "Lab Rats", tier = 2, reward = 1400, twists = { "guarded" },
		description = "Modern lab equipment from a university office, guarded by what used to be the faculty.",
		briefing = "My microscopes are from the stone age. A university office downtown still has four crates of modern equipment, guarded by what used to be the faculty. Please be respectful. They had tenure.",
		debrief = "New equipment. I can see the virus now. It's ugly. Thank you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 4, cargo = "Lab Equipment",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "lab", payPerStop = 220,
		pickupLabel = "PICK UP THE EQUIPMENT AT", dropLabel = "DELIVER THE EQUIPMENT TO",
		giver = "Professor Lang, a survivor", giverRole = "teacher", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("lab", {
		number = 3, name = "Subject Seven", tier = 3, reward = 1600, twists = { "night" },
		description = "A bitten prisoner who never turned, from Blackrock Prison to the lab. He is calm only at night.",
		briefing = "A prisoner at Blackrock was bitten three weeks ago and still hasn't turned. He's calm only after dark. In daylight he screams. Bring him to me at night, gently. He is my best hope and my worst roommate.",
		debrief = "Subject Seven is resting. He asked for pudding. Fascinating.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 1, cargo = "Subject Seven",
		pickups = 1, pickupAt = "prison", drops = 1, dropAt = "lab", payPerStop = 260,
		pickupLabel = "PICK UP THE PATIENT AT", dropLabel = "BRING THE PATIENT TO",
		giver = "Warden Cole, Blackrock Prison", giverRole = "guard", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("lab", {
		number = 4, name = "Unstable Compounds", tier = 3, reward = 1900, twists = { "quiet", "spotless" },
		description = "Nitro compound from the Power Plant: no shots, no potholes, or it's over.",
		briefing = "I need the plant's leftover nitro compound for the centrifuge. Yes, the explosive kind. It reacts to shocks, so no potholes. It reacts to gunfire, so no gunfire. Honestly, it reacts to everything. Like my ex-wife.",
		debrief = "Compound received, nothing exploded. My eyebrows thank you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 3, cargo = "Nitro Compound",
		pickups = 1, pickupAt = "powerplant", drops = 1, dropAt = "lab", payPerStop = 280,
		pickupLabel = "LOAD THE COMPOUND AT", dropLabel = "DELIVER THE COMPOUND TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("lab", {
		number = 5, name = "Deep Freeze", tier = 3, reward = 2000, coop = true, twists = { "lift" },
		description = "Frosty's industrial freezers to the lab, carried in pairs. They still smell of strawberry.",
		briefing = "The lab freezer broke, and the only industrial freezers left in the city are at Frosty's. They are enormous, and they still smell of strawberry. Carry them with a partner. Alone, you'll crawl.",
		debrief = "The freezers work. My cultures now smell of strawberry. Science is strange.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "icebox", items = 4, cargo = "Freezers",
		pickups = 1, pickupAt = "frosty", drops = 1, dropAt = "lab", loadTime = 5, unloadTime = 5, payPerStop = 290,
		pickupLabel = "LOAD THE FREEZERS AT", dropLabel = "DELIVER THE FREEZERS TO",
		giver = "Molly, at the counter", giverRole = "icecream", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("lab", {
		number = 6, name = "Field Samples", tier = 4, reward = 2300, coop = true, twists = { "guarded", "gunner" },
		description = "Tissue samples of three strains from three nests. Hordes everywhere, the passengers thin them out.",
		briefing = "I need tissue samples of three different strains from three nests across the city. My field assistants have the cases ready, but they're surrounded. Drive in, grab, drive out, and let your passengers thin the herd. For science.",
		debrief = "Three strains, three clues. One step closer.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "sample", items = 4, cargo = "Tissue Samples",
		pickups = 3, pickupAt = nil, drops = 1, dropAt = "lab", payPerStop = 320,
		pickupLabel = "COLLECT THE SAMPLES AT", dropLabel = "DELIVER THE SAMPLES TO",
		giver = "Kenji, the field assistant", giverRole = "doctor", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("lab", {
		number = 7, name = "Power Hungry", tier = 4, reward = 2500, twists = { "hunted" }, banditBoost = 1.5,
		description = "Battery packs for the sequencer. The Crimson Syndicate sends cars to stop the research.",
		briefing = "My sequencer eats power like a teenager eats pizza. The plant charged five battery packs for me, but a rival outfit, the Crimson Syndicate, wants my research stopped. They'll send cars. Many cars.",
		debrief = "Sequencer running. The Syndicate is a few cars short. Fascinating, in a violent way.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "battery", items = 5, cargo = "Battery Packs",
		pickups = 1, pickupAt = "powerplant", drops = 1, dropAt = "lab", payPerStop = 330,
		pickupLabel = "LOAD THE BATTERIES AT", dropLabel = "DELIVER THE BATTERIES TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Kenji, the field assistant", receiverRole = "doctor",
	})
	add("lab", {
		number = 8, name = "Patient Zero", tier = 4, reward = 2900, coop = true, twists = { "guarded", "spotless" },
		description = "The first person ever bitten, hiding at the Old Airfield. The hordes follow her. Bring her in unhurt.",
		briefing = "We found her. The woman who was bitten on day one. She's hiding at the Old Airfield and doesn't want to be found, and the hordes are drawn to her, nobody knows why. Bring her to me unhurt. Everything depends on it.",
		debrief = "Patient Zero is safe. The cure is in her blood. I can feel it.",
		vehicle = "ambulance", load = "board", unload = "board", itemKind = "patient", items = 1, cargo = "Patient Zero",
		pickups = 1, pickupAt = "airfield", drops = 1, dropAt = "lab", payPerStop = 360,
		pickupLabel = "PICK UP THE PATIENT AT", dropLabel = "BRING THE PATIENT TO",
		giver = "Corporal Diaz, the pilot", giverRole = "soldier", receiver = "Dr. Ito, the lab chief", receiverRole = "doctor",
	})
	add("lab", {
		number = 9, name = "Midnight Formula", tier = 4, reward = 3200, twists = { "night", "spotless" },
		description = "The first trial doses, stable only in the cold of the night: two volunteers and the clinic.",
		briefing = "The first trial doses. They only stay stable in the cold of the night, so you deliver after dark. Two volunteers at home, then the clinic. If a single cooler breaks I start over, and I don't want to start over.",
		debrief = "All three trials have started. Now we wait. I hate waiting.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "vaccine", items = 3, cargo = "Trial Doses",
		pickups = 1, pickupAt = "lab", drops = 3, dropAt = "clinic", payPerStop = 370,
		pickupLabel = "LOAD THE TRIAL DOSES AT", dropLabel = "DELIVER A DOSE TO",
		giver = "Dr. Ito, the lab chief", giverRole = "doctor", receiver = "Dr. Novak, the clinic's doctor", receiverRole = "doctor",
	})
	add("lab", {
		number = 10, name = "The Cure", tier = 4, reward = 6000, coop = true, twists = { "defend", "spotless" }, defendTime = 90,
		description = "Eight coolers of the cure: two homes, then the Survivor Camp to hold until every dose is given.",
		briefing = "It works. It actually works. Eight coolers of the cure: two homes on the way, then the Survivor Camp, the biggest crowd we have. When the dead smell that many people in one place they'll come in waves. Hold the camp until every dose is given. And don't drop anything. Please.",
		debrief = "The camp is cured. The world just had its first real morning in years. Thank you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "vaccine", items = 8, cargo = "The Cure",
		pickups = 1, pickupAt = "lab", drops = 3, dropAt = "camp", payPerStop = 420,
		pickupLabel = "LOAD THE CURE AT", dropLabel = "DELIVER THE CURE TO",
		giver = "Dr. Ito, the lab chief", giverRole = "doctor", receiver = "Doc Holloway, the camp medic", receiverRole = "doctor",
	})
end

-- ── 9. Dirty Money (Vinnie, the fixer) ───────────────────────────────────
-- A ticking box, laundered cash, a jailbreak, stolen art, hardware for Blackrock, an ice cream front, the ledger,
-- fireworks at the docks, a fortune for a pilot and the yacht.
do
	add("underworld", {
		number = 1, name = "No Questions Asked", tier = 2, reward = 1500, twists = { "quiet" },
		description = "A ticking box is already in your trunk. Bring it to the bank, and don't fire a gun near it.",
		briefing = "Kid, there's a box in your trunk. Don't ask how it got there. It ticks. Don't ask why it ticks. Bring it to my associate at the bank, and whatever you do, don't fire a gun anywhere near it.",
		debrief = "It was a clock. A very expensive clock. Or was it? Don't ask.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "parcel", items = 1, cargo = "A Ticking Box",
		pickups = 0, pickupAt = nil, drops = 1, dropAt = "bank", payPerStop = 220,
		pickupLabel = "PICK UP THE BOX AT", dropLabel = "DELIVER THE BOX TO",
		giver = "Vinnie, the fixer", giverRole = "banker", receiver = "Mr. Gold, the bank manager", receiverRole = "banker",
	})
	add("underworld", {
		number = 2, name = "Laundry Day", tier = 3, reward = 1800, twists = { "hunted" }, banditBoost = 1.5,
		description = "Four sacks of cash from the bank to two laundromats. The Rust Riders smell money.",
		briefing = "Two laundromats on the east side clean my money. They need four sacks to wash. The Rust Riders sniff cash from a mile away, so they'll be all over you. Keep the sacks dry, kid.",
		debrief = "Squeaky clean money. My accountant says thanks.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "cash", items = 4, cargo = "Dirty Cash",
		pickups = 1, pickupAt = "bank", drops = 2, dropAt = nil, payPerStop = 260,
		pickupLabel = "LOAD THE CASH AT", dropLabel = "DROP THE CASH AT",
		giver = "Mr. Gold, the bank manager", giverRole = "banker", receiver = "Mama Rosa, the laundromat owner", receiverRole = "shopkeeper",
	})
	add("underworld", {
		number = 3, name = "Bail Day", tier = 3, reward = 2000, coop = true, twists = { "gunner" },
		description = "Two of Vinnie's boys out of a courthouse window and onto a plane. Five minutes. The crew shoots.",
		briefing = "Two of my boys just walked out of a courthouse window, and the cops aren't happy about it. Pick 'em up at the back door and get 'em to the airfield, the plane leaves in five minutes. Your friends shoot anything that follows.",
		debrief = "My boys are on the plane. Nobody saw nothing. Capisce?",
		vehicle = nil, load = "board", unload = "board", itemKind = "survivor", items = 2, cargo = "Vinnie's Boys",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "airfield", payPerStop = 280, timeLimit = 300,
		pickupLabel = "PICK UP THE BOYS AT", dropLabel = "BRING THE BOYS TO",
		giver = "Lefty, a lookout", giverRole = "townsperson", receiver = "Ace, a smuggler pilot", receiverRole = "worker",
	})
	add("underworld", {
		number = 4, name = "Art Appreciation", tier = 3, reward = 2400, twists = { "night", "spotless" },
		description = "Three priceless paintings from City Hall to a buyer's boat at Lighthouse Point. At night, without a scratch.",
		briefing = "City Hall has three paintings worth more than this whole city, and the mayor won't miss them, he's busy. A buyer waits on a boat at Lighthouse Point. At night nobody sees. Not a scratch on the canvas, or the buyer walks.",
		debrief = "The buyer cried. Art does that. So does the price.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "painting", items = 3, cargo = "Paintings",
		pickups = 1, pickupAt = "cityhall", drops = 1, dropAt = "lighthouse", payPerStop = 300,
		pickupLabel = "PICK UP THE PAINTINGS AT", dropLabel = "DELIVER THE PAINTINGS TO",
		giver = "Mr. Pruitt, the city clerk", giverRole = "clerk", receiver = "Mr. Delacroix, an art buyer", receiverRole = "banker",
	})
	add("underworld", {
		number = 5, name = "Heavy Business", tier = 4, reward = 2600, coop = true, twists = { "lift" },
		description = "Five cases of hardware from the Harbor Warehouse to Blackrock Prison. Bring the muscle.",
		briefing = "My business partners run Blackrock Prison now, and they need protection. Five cases of hardware from the Harbor Warehouse. Heavy stuff, so bring a muscle or two.",
		debrief = "My partners are grateful. Grateful partners are good partners.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "weapons", items = 5, cargo = "Hardware",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "prison", loadTime = 5, unloadTime = 5, payPerStop = 320,
		pickupLabel = "LOAD THE CASES AT", dropLabel = "DELIVER THE CASES TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Big Sal, the yard boss", receiverRole = "guard",
	})
	add("underworld", {
		number = 6, name = "Two Scoops", tier = 4, reward = 2800, twists = { "guarded" },
		description = "Sell ice cream at three corners in a rival's territory. He parked his hordes there.",
		briefing = "I bought Frosty's. Don't ask. Ice cream trucks make a great front: sell scoops at three corners, and the corners are all in my rival's territory. He parked his hordes there. Smile, sell, survive.",
		debrief = "Best quarter the ice cream business ever had. Two scoops for you, on the house.",
		vehicle = "icecream", load = "carry", unload = "serve", itemKind = "icebox", items = 6, cargo = "Ice Cream",
		pickups = 1, pickupAt = "frosty", drops = 3, dropAt = nil, payPerStop = 300,
		pickupLabel = "LOAD THE ICE CREAM AT", dropLabel = "SELL ICE CREAM AT",
		giver = "Molly, at the counter", giverRole = "icecream", receiver = "Customers with a sweet tooth", receiverRole = "kid",
	})
	add("underworld", {
		number = 7, name = "The Ledger", tier = 4, reward = 3000, twists = { "hunted" },
		description = "Vinnie's ledger from a detective's apartment to the bank vault. Four minutes, hunted.",
		briefing = "A detective has my ledger. Every name, every deal. Tonight his apartment is empty and his window is open. Grab the briefcase and get it into the bank's vault in four minutes, before half the city comes looking for it.",
		debrief = "Ledger in the vault. The detective will find a nice fruit basket instead.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "documents", items = 1, cargo = "The Ledger",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "bank", payPerStop = 330, timeLimit = 240,
		pickupLabel = "GRAB THE BRIEFCASE AT", dropLabel = "DELIVER THE BRIEFCASE TO",
		giver = "Lefty, a lookout", giverRole = "townsperson", receiver = "Mr. Gold, the bank manager", receiverRole = "banker",
	})
	add("underworld", {
		number = 8, name = "Fireworks", tier = 4, reward = 3400, coop = true, twists = { "quiet", "guarded" },
		description = "Dynamite for a rival's boat at the Harbor Docks. Hordes at both ends, and no shooting near the crates.",
		briefing = "My rival keeps his boat at the Harbor Docks. I want it gone, quietly, with a big bang. Dynamite from the Train Yard, a horde at both ends, and no shooting near the crates. Use your crew, use your car, use your imagination.",
		debrief = "Beautiful boom. I could see it from my penthouse.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tnt", items = 4, cargo = "Dynamite",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "docks", payPerStop = 360,
		pickupLabel = "LOAD THE DYNAMITE AT", dropLabel = "DELIVER THE DYNAMITE TO",
		giver = "Gus, the yard foreman", giverRole = "foreman", receiver = "Fingers, the demolition guy", receiverRole = "worker",
	})
	add("underworld", {
		number = 9, name = "Golden Handshake", tier = 4, reward = 3800, coop = true, twists = { "hunted", "gunner" }, banditBoost = 2,
		description = "Six sacks of gold in the armored truck to a pilot at the Old Airfield. Every gang knows.",
		briefing = "I'm paying a pilot to fly my fortune out of here, so six sacks of gold go to the Old Airfield in the armored truck. Every gang in the city knows. Every single one. Bring shooters, kid. The best you know.",
		debrief = "The plane is loaded. You're in my will now. Small print, but you're in it.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "cash", items = 6, cargo = "Gold",
		pickups = 1, pickupAt = "bank", drops = 1, dropAt = "airfield", payPerStop = 380,
		pickupLabel = "LOAD THE GOLD AT", dropLabel = "DELIVER THE GOLD TO",
		giver = "Mr. Gold, the bank manager", giverRole = "banker", receiver = "Ace, a smuggler pilot", receiverRole = "worker",
	})
	add("underworld", {
		number = 10, name = "Dirty Money", tier = 4, reward = 7500, coop = true, twists = { "defend", "hunted" }, defendTime = 75, banditBoost = 2,
		description = "Vinnie's last two stashes, a cut for his mother, and the pier at Lighthouse Point to hold.",
		briefing = "The city's going down and I'm going out on a yacht. My last two stashes are hidden in town. Collect them, drop a cut at my mother's, God bless her, and bring the rest to Lighthouse Point. Every gang wants a piece. Hold the pier while my boys load the yacht, and you'll never have to work again. In the good way.",
		debrief = "Pleasure doing business, kid. If anybody asks, you never met me.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "cash", items = 8, cargo = "Vinnie's Fortune",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "lighthouse", payPerStop = 420,
		pickupLabel = "COLLECT THE STASH AT", dropLabel = "DELIVER THE MONEY TO",
		giver = "Lefty, a lookout", giverRole = "townsperson", receiver = "Vinnie, the fixer", receiverRole = "banker",
	})
end

-- ── 10. Last Convoy (Mayor Grant, City Hall) ─────────────────────────────
-- The evacuation plan, the first families, fuel for the plane, the lighthouse lamp, the prison, landing gear, the
-- seed vault, the mayor's own kids, the last boat and the last convoy.
do
	add("exodus", {
		number = 1, name = "Evacuation Plan", tier = 2, reward = 2000, twists = {},
		description = "The printed evacuation plans from City Hall to Precinct 13, before word gets out.",
		briefing = "Fellow citizen, I'll be honest with you: the city is lost. The evacuation plans are printed, and the police must have them before word gets out and the panic starts. Three briefcases to Precinct 13. Keep this between us.",
		debrief = "The police have the plan. Now we just need a miracle. And you.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "documents", items = 3, cargo = "Evacuation Plans",
		pickups = 1, pickupAt = "cityhall", drops = 1, dropAt = "police", payPerStop = 260,
		pickupLabel = "PICK UP THE PLANS AT", dropLabel = "DELIVER THE PLANS TO",
		giver = "Mr. Pruitt, the city clerk", giverRole = "clerk", receiver = "Detective Shaw", receiverRole = "officer",
	})
	add("exodus", {
		number = 2, name = "Roll Call", tier = 2, reward = 2300, coop = true, twists = { "gunner" },
		description = "Three families who won't leave until they see a bus. The bus, the crew at the windows, the stadium.",
		briefing = "Three families refuse to leave their homes until they see a bus. So: a bus. Pick them up, your friends cover the windows, and bring everyone to the Stadium Shelter for registration.",
		debrief = "Six more names on the list. Every name counts.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 6, cargo = "Families",
		pickups = 3, pickupAt = nil, drops = 1, dropAt = "stadium", payPerStop = 300,
		pickupLabel = "PICK UP THE FAMILY AT", dropLabel = "BRING THE FAMILIES TO",
		giver = "Mrs. Abara, the block captain", giverRole = "townsperson", receiver = "Coach Daniels, the shelter warden", receiverRole = "guard",
	})
	add("exodus", {
		number = 3, name = "Fuel for the Flight", tier = 3, reward = 2600, twists = { "quiet" },
		description = "The depot's last leaking barrels to the evacuation plane. One spark and it's over: no shooting.",
		briefing = "The last plane needs fuel, and the depot's last barrels leak like a sieve. One spark and the fuel truck becomes a small sun. No shooting, not a single bullet. Drive around the dead, not through them.",
		debrief = "Tanks full, and you still have all your fingers. Excellent.",
		vehicle = "fueltruck", load = "carry", unload = "carry", itemKind = "barrel", items = 6, cargo = "Jet Fuel",
		pickups = 1, pickupAt = "fueldepot", drops = 1, dropAt = "airfield", payPerStop = 330,
		pickupLabel = "LOAD THE FUEL AT", dropLabel = "REFUEL THE PLANE AT",
		giver = "Hank, the depot worker", giverRole = "worker", receiver = "Captain Ellis, the last pilot", receiverRole = "officer",
	})
	add("exodus", {
		number = 4, name = "Keep the Light On", tier = 3, reward = 2900, twists = { "night" },
		description = "New lamp parts for Lighthouse Point, so the night's evacuation boats miss the rocks.",
		briefing = "The evacuation boats come at night, and the lighthouse lamp is broken. Without it they'll hit the rocks. Volkov rebuilt the parts. Bring them tonight, the keeper can only test the lamp in the dark.",
		debrief = "The light is turning. Tonight, the boats find their way.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "electronics", items = 3, cargo = "Lamp Parts",
		pickups = 1, pickupAt = "powerplant", drops = 1, dropAt = "lighthouse", payPerStop = 340,
		pickupLabel = "PICK UP THE LAMP PARTS AT", dropLabel = "DELIVER THE PARTS TO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "Old Tom, the lighthouse keeper", receiverRole = "townsperson",
	})
	add("exodus", {
		number = 5, name = "No One Left Behind", tier = 3, reward = 3200, coop = true, twists = { "guarded" },
		description = "Blackrock's guards and the inmates who held the walls with them, from the prison to the camp.",
		briefing = "Blackrock Prison's guards, and the inmates who helped them hold the walls, are trapped in there together. They're people too, and they've earned a seat. The prison and the camp are both swarmed. Bring a crew.",
		debrief = "Guards and prisoners side by side at the camp. Strange times make good neighbours.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 6, cargo = "Survivors",
		pickups = 1, pickupAt = "prison", drops = 1, dropAt = "camp", payPerStop = 360,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Warden Cole, Blackrock Prison", giverRole = "guard", receiver = "Marta, the camp leader", receiverRole = "townsperson",
	})
	add("exodus", {
		number = 6, name = "Landing Gear", tier = 4, reward = 3500, coop = true, twists = { "lift" },
		description = "Plane tires from the Train Yard for the cargo plane. Alone you crawl, with friends you fly.",
		briefing = "The big cargo plane has flat tires, and a plane tire weighs as much as a small car. The Train Yard has a stack. Alone you'll crawl. With friends you'll fly. Literally, if this works.",
		debrief = "The plane is standing tall. One more step closer.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "tires", items = 8, cargo = "Plane Tires",
		pickups = 1, pickupAt = "trainyard", drops = 1, dropAt = "airfield", loadTime = 5, unloadTime = 5, payPerStop = 380,
		pickupLabel = "LOAD THE TIRES AT", dropLabel = "DELIVER THE TIRES TO",
		giver = "Gus, the yard foreman", giverRole = "foreman", receiver = "Captain Ellis, the last pilot", receiverRole = "officer",
	})
	add("exodus", {
		number = 7, name = "Seed Vault", tier = 4, reward = 3800, twists = { "spotless" },
		description = "Seedlings of every crop left, from the lab to the boat at Lighthouse Point. Every tray whole.",
		briefing = "Dr. Ito saved seedlings of every crop we have left. Wherever we land, they're our future. The boat at Lighthouse Point takes them. Every tray must arrive whole.",
		debrief = "Our future is on the boat. It sounds dramatic, but it's true.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "plants", items = 4, cargo = "The Seed Vault",
		pickups = 1, pickupAt = "lab", drops = 1, dropAt = "lighthouse", payPerStop = 380,
		pickupLabel = "LOAD THE SEEDLINGS AT", dropLabel = "DELIVER THE SEEDLINGS TO",
		giver = "Dr. Ito, the lab chief", giverRole = "doctor", receiver = "Old Tom, the lighthouse keeper", receiverRole = "townsperson",
	})
	add("exodus", {
		number = 8, name = "The Mayor's Kids", tier = 4, reward = 4500, coop = true, twists = { "hunted" },
		description = "The mayor's own kids from Sunny Hill School to the plane, in the armored truck. Bandits want a hostage.",
		briefing = "My own kids are at Sunny Hill School with the last class. The bandits know who I am, and they'd love a hostage. Take the armored truck. Please. I'm asking as a father, not as a mayor.",
		debrief = "My kids are on the plane. I... thank you. I owe you everything.",
		vehicle = "armored", load = "board", unload = "board", itemKind = "kid", items = 3, cargo = "The Mayor's Kids",
		pickups = 1, pickupAt = "school", drops = 1, dropAt = "airfield", payPerStop = 400,
		pickupLabel = "PICK UP THE KIDS AT", dropLabel = "BRING THE KIDS TO",
		giver = "Ms. Parker, the teacher", giverRole = "teacher", receiver = "Captain Ellis, the last pilot", receiverRole = "officer",
	})
	add("exodus", {
		number = 9, name = "Last Boat", tier = 4, reward = 5500, coop = true, twists = { "guarded", "defend" }, defendTime = 60,
		description = "The last people from the Stadium Shelter to the last boat. Hordes at both ends, the pier to hold.",
		briefing = "The last boat leaves Lighthouse Point at dawn. Bring the last people from the stadium, and hold the pier while they board. The dead are thick at both ends. This is the part they'll write songs about.",
		debrief = "The boat is out. They're singing on deck. Off key, but singing.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 6, cargo = "The Last Survivors",
		pickups = 1, pickupAt = "stadium", drops = 1, dropAt = "lighthouse", payPerStop = 420,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Coach Daniels, the shelter warden", giverRole = "guard", receiver = "Old Tom, the lighthouse keeper", receiverRole = "townsperson",
	})
	add("exodus", {
		number = 10, name = "Last Convoy", tier = 4, reward = 10000, coop = true, twists = { "defend", "gunner" }, defendTime = 90,
		description = "Three hideouts, the camp medic, the last plane. Hold the runway until it's in the air.",
		briefing = "This is the end of the city and the start of something else. The last survivors hide in three places. Fill the bus, drop the sick ones with the camp medic, and bring the rest to the airfield. When the engines start, every dead thing for miles will come running. Hold them off until the plane is up. Then get on board yourself.",
		debrief = "Wheels up. The city is behind us. You're the reason anyone made it out. Thank you, driver.",
		vehicle = "bus", load = "board", unload = "board", itemKind = "survivor", items = 10, cargo = "The Last Convoy",
		pickups = 3, pickupAt = nil, drops = 2, dropAt = "airfield", payPerStop = 480,
		pickupLabel = "PICK UP THE SURVIVORS AT", dropLabel = "BRING THE SURVIVORS TO",
		giver = "Ms. Rivera, a survivor", giverRole = "townsperson", receiver = "Captain Ellis, the last pilot", receiverRole = "officer",
	})
end

-- ── 11. Partners in Crime (Rosa & Rico, the twins) · DUO ──────────────────
-- 3.2, only with a crew: a jukebox for two, a flood gate with two levers, a shotgun wedding, a bank vault with two
-- keys, a transformer coil, the prison armory behind the precinct's two-man gate, a freezer of plasma on the clock,
-- two fenced substations, Big Earl's stolen mortars and, at last, Big Earl's whole medicine hoard.
do
	add("duo", {
		number = 1, name = "Double Act", tier = 2, reward = 700, duo = true, coop = true, twists = { "pair" },
		description = "The twins' old diner jukebox to the Survivor Camp. Too heavy for one: you lift it together or not at all.",
		briefing = "Rosa here, and the one grinning is Rico. We're twins, we're couriers, and we never take a job alone. Rule one: nothing heavy moves unless both of you are on it. Our diner's jukebox goes to the Survivor Camp. Show us you can lift together.",
		debrief = "Rico: Not a scratch on the jukebox. Rosa: And not one argument. You two are hired.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "furniture", items = 2, cargo = "Jukebox and Speakers",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "camp", loadTime = 5, unloadTime = 5, payPerStop = 110,
		pickupLabel = "LOAD THE JUKEBOX AT", dropLabel = "CARRY IT INTO",
		giver = "Rico, Rosa's twin", giverRole = "townsperson", receiver = "Marta, the camp leader", receiverRole = "townsperson",
	})
	add("duo", {
		number = 2, name = "Flood Gate", tier = 2, reward = 800, duo = true, coop = true, twists = { "switches" },
		description = "Chlorine for the Water Works. Its old yard gate only opens when two levers far apart are pulled at once.",
		briefing = "Rosa: The Water Works is out of chlorine, so the camp drinks swamp. Rico: Catch is, the old engineer built the yard gate with two levers twenty steps apart. Two people awake on every shift, he said. Rosa: One of you on each lever, pull on three. Not on four. On three.",
		debrief = "Rosa: Clean water by tonight. Rico: And you only counted to four once. Progress.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "barrel", items = 3, cargo = "Chlorine Barrels",
		pickups = 1, pickupAt = "warehouse", drops = 1, dropAt = "waterworks", payPerStop = 130,
		pickupLabel = "LOAD THE CHLORINE AT", dropLabel = "DELIVER THE CHLORINE TO",
		giver = "Rocco, the warehouse boss", giverRole = "foreman", receiver = "Hugo, the waterworks keeper", receiverRole = "worker",
	})
	add("duo", {
		number = 3, name = "Shotgun Wedding", tier = 2, reward = 950, duo = true, coop = true, twists = { "lift", "gunner" },
		description = "Cousin Lola's wedding at the Stadium Shelter: heavy crates of party gear, one of you driving, one riding shotgun.",
		briefing = "Rico: Our cousin Lola is getting married at the Stadium Shelter, apocalypse or not. Rosa: The tables and the champagne crates weigh a ton, so carry them together or crawl. Rico: And on the way, one drives and one rides shotgun. A shotgun wedding! I've waited all year to say that.",
		debrief = "Rosa: Lola cried, the groom cried, Rico cried. Rico: It was the onions in the buffet.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "crate", items = 4, cargo = "Wedding Gear",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "stadium", loadTime = 5, unloadTime = 5, payPerStop = 150,
		pickupLabel = "LOAD THE WEDDING GEAR AT", dropLabel = "DELIVER THE GEAR TO",
		giver = "Lola, the bride", giverRole = "townsperson", receiver = "Coach Daniels, the shelter warden", receiverRole = "guard",
	})
	add("duo", {
		number = 4, name = "Two Keys", tier = 3, reward = 1100, duo = true, coop = true, twists = { "switches", "hunted" }, gates = "pickup",
		description = "The city's emergency fund from the bank vault: two keys turned at once, then bandits all the way to City Hall.",
		briefing = "Rosa: The First Zombie Bank's vault opens with two keys turned at the same moment, on two desks far apart. Rico: The manager hates us, so naturally she gave us both keys. Rosa: The mayor wants the emergency fund at City Hall, and every bandit with wheels wants it more. Turn the keys, load the cash, drive like you stole it. You didn't. Legally.",
		debrief = "Rico: The mayor counted it twice. Rosa: Then he counted us. We're on the city's list of trusted people now. Short list.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "cash", items = 3, cargo = "Emergency Fund",
		pickups = 1, pickupAt = "bank", drops = 1, dropAt = "cityhall", payPerStop = 200,
		pickupLabel = "LOAD THE CASH AT", dropLabel = "DELIVER THE FUND TO",
		giver = "Ms. Kline, the bank manager", giverRole = "banker", receiver = "Mr. Pruitt, the city clerk", receiverRole = "clerk",
	})
	add("duo", {
		number = 5, name = "Heavy Current", tier = 3, reward = 1300, duo = true, coop = true, twists = { "pair", "guarded" },
		description = "Transformer coils from the Power Plant to the Radio Station. Two carriers per coil, and a horde at both ends.",
		briefing = "Rico: The Radio Station blew its transformer. Volkov has spare coils at the Power Plant, and each one weighs more than my car. Rosa: Both of you on a coil, every step, or it doesn't move. And both places are crawling with the dead. Rico: So one carries while the other shoots... no, wait. You both carry. Good luck.",
		debrief = "Rosa: DJ Luna dedicated a song to you two. Rico: 'Lean on Me'. She's not subtle.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "generator", items = 2, cargo = "Transformer Coils",
		pickups = 1, pickupAt = "powerplant", drops = 1, dropAt = "radio", loadTime = 5, unloadTime = 5, payPerStop = 230,
		pickupLabel = "LOAD THE COILS AT", dropLabel = "CARRY THE COILS INTO",
		giver = "Engineer Volkov", giverRole = "foreman", receiver = "DJ Luna, the radio host", receiverRole = "clerk",
	})
	add("duo", {
		number = 6, name = "Lock Step", tier = 3, reward = 1500, duo = true, coop = true, twists = { "switches", "defend" }, defendTime = 45,
		description = "Blackrock's armory to Precinct 13. At the precinct, hold the yard, then pull both gate levers together.",
		briefing = "Rosa: Blackrock Prison is emptying its armory before the walls fall, and Precinct 13 wants every gun in it. Rico: The precinct yard has a two-lever gate, a two-man rule from the old days. Rosa: When you get there, the dead will already be waiting. Hold them off, then pull both levers together. Then, and only then, unload.",
		debrief = "Rico: Detective Shaw says the precinct never had a smoother delivery. Rosa: She says that to everybody. Rico: She has never said that to anybody.",
		vehicle = "armored", load = "carry", unload = "carry", itemKind = "weapons", items = 4, cargo = "Prison Armory",
		pickups = 1, pickupAt = "prison", drops = 1, dropAt = "police", payPerStop = 250,
		pickupLabel = "LOAD THE WEAPONS AT", dropLabel = "DELIVER THE WEAPONS TO",
		giver = "Warden Cole, Blackrock Prison", giverRole = "guard", receiver = "Detective Shaw", receiverRole = "officer",
	})
	add("duo", {
		number = 7, name = "Cold Hands", tier = 3, reward = 1700, duo = true, coop = true, twists = { "pair" },
		description = "Freezers full of blood plasma from a dark house to the City Clinic: two carriers, five minutes before it thaws.",
		briefing = "Rico: A doctor's house went dark, and his freezers are full of blood plasma. Rosa: Five minutes before it thaws. Every freezer is a two-person carry, so don't even think about leaving your partner behind. Rico: Run, lift, drive, lift. Breathe later.",
		debrief = "Rosa: Dr. Novak says that plasma saves a dozen people this week. Rico: I say we earned a nap.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "icebox", items = 2, cargo = "Blood Plasma",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "clinic", loadTime = 4, unloadTime = 4, payPerStop = 240, timeLimit = 300,
		pickupLabel = "PICK UP THE FREEZERS AT", dropLabel = "RUSH THE PLASMA TO",
		giver = "Mr. Lindgren, a neighbour", giverRole = "townsperson", receiver = "Nurse Ada", receiverRole = "nurse",
	})
	add("duo", {
		number = 8, name = "Crossed Wires", tier = 4, reward = 2000, duo = true, coop = true, twists = { "switches", "guarded" }, gates = "pickup",
		description = "Battery banks from two fenced substations to the Power Plant. Every fence has a two-lever gate and a horde inside.",
		briefing = "Rosa: Two substations still have charged battery banks, both behind fences with twin-lever gates. Rico: Safety rules: nobody gets electrocuted alone. Rosa: Both yards are full of dead linemen who forgot the rules. Clear them, pull together, load up, and bring the batteries to Volkov.",
		debrief = "Rico: Six blocks got their lights back. Rosa: And one dead lineman got his hard hat back. Long story.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "battery", items = 6, cargo = "Battery Banks",
		pickups = 2, pickupAt = nil, drops = 1, dropAt = "powerplant", payPerStop = 300,
		pickupLabel = "LOAD THE BATTERIES AT", dropLabel = "DELIVER THE BATTERIES TO",
		giver = "Pedro, a lineman", giverRole = "worker", receiver = "Engineer Volkov", receiverRole = "foreman",
	})
	add("duo", {
		number = 9, name = "Mirror Run", tier = 4, reward = 2400, duo = true, coop = true, twists = { "pair", "gunner" },
		description = "Big Earl stole the base's mortar crates. Take them back two hands per crate, and shoot from the seats all the way.",
		briefing = "Rico: Big Earl stole a stack of mortar crates from the Military Base and parked them in a garage across town. Rosa: Every crate is a two-person lift, and Earl's boys patrol the streets. Rico: So you lift together, you ride together, and whoever isn't driving shoots. Rosa: Captain Reyes pays well. Earl does not forgive. Be quick.",
		debrief = "Rosa: Reyes saluted us. Rico: Earl sent us a postcard. It just says 'soon'. Rosa: Then let's get there first.",
		vehicle = nil, load = "carry", unload = "carry", itemKind = "ammo", items = 4, cargo = "Mortar Crates",
		pickups = 1, pickupAt = nil, drops = 1, dropAt = "base", loadTime = 4, unloadTime = 4, payPerStop = 340,
		pickupLabel = "TAKE BACK THE CRATES AT", dropLabel = "DELIVER THE CRATES TO",
		giver = "Dusty, a looter gone honest", giverRole = "townsperson", receiver = "Sergeant Hayes", receiverRole = "soldier",
	})
	add("duo", {
		number = 10, name = "Partners in Crime", tier = 4, reward = 3500, duo = true, coop = true, twists = { "pair", "switches" },
		description = "Big Earl's medicine hoard from two hideouts, a drop on the way, then the stadium's two-lever gate. Lift together, pull together.",
		briefing = "Rosa: Big Earl has been hoarding the city's medicine in two hideouts and selling it back one pill at a time. Tonight we take all of it. Rico: The crates are heavy, so you carry them together. Some go to a field post on the way, the rest to the Stadium Shelter. Rosa: The stadium's loading gate opens with two levers, and Earl's men will be right behind you. This is what we trained you for, partners.",
		debrief = "Rico: The whole city has its medicine back. Rosa: And Big Earl has an empty garage and a bad mood. Partners, it was an honour.",
		vehicle = "movingtruck", load = "carry", unload = "carry", itemKind = "medicine", items = 8, cargo = "Earl's Medicine Hoard",
		pickups = 2, pickupAt = nil, drops = 2, dropAt = "stadium", loadTime = 4, unloadTime = 4, payPerStop = 380,
		pickupLabel = "RAID THE STASH AT", dropLabel = "DELIVER THE MEDICINE TO",
		giver = "Mona, Earl's ex-accountant", giverRole = "clerk", receiver = "Coach Daniels, the shelter warden", receiverRole = "guard",
	})
end

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

-- 3.2: is a campaign's finale (mission FINALE, the one `requires` asks for) done?
function Missions.finished(progress: { [string]: number }, campaignId: string): boolean
	return (progress[`{campaignId}_{FINALE}`] or 0) >= 1
end

-- 3.2: the campaigns a campaign still waits for (its `requires` whose finale is not done), in order. Empty = none.
function Missions.missing(campaignId: string, progress: { [string]: number }): { Campaign }
	local list: { Campaign } = {}
	local campaign = Missions.findCampaign(campaignId)
	local requires: { string } = if campaign and campaign.requires then campaign.requires else {}
	for _, id in requires do
		local required = Missions.findCampaign(id)
		if required and not Missions.finished(progress, id) then
			table.insert(list, required)
		end
	end
	return list
end

-- 3.2: why a list of missing campaigns keeps one shut: "Finish First Shift's finale first." (more than one: "… and
-- 3 more campaigns").
function Missions.missingText(missing: { Campaign }): string
	local first = missing[1]
	if not first then
		return ""
	end
	if #missing == 1 then
		return `Finish {first.name}'s finale first.`
	end
	return `Finish {first.name}'s finale first (and {#missing - 1} more {if #missing == 2 then "campaign" else "campaigns"}).`
end

-- 3.2: has the player cleared any mission of a campaign (started it, maybe before 3.2 had the prerequisites)?
function Missions.started(progress: { [string]: number }, campaignId: string): boolean
	for number = 1, FINALE do
		if (progress[`{campaignId}_{number}`] or 0) >= 1 then
			return true
		end
	end
	return false
end

-- 3.2: is a campaign open for a player of `level` with `progress`? The campaigns it requires done (their finales),
-- then its level. Says why not. A campaign already started stays open (a 3.1 save: no prerequisites, an older curve).
function Missions.campaignOpen(campaignId: string, progress: { [string]: number }, level: number): (boolean, string?)
	local campaign = Missions.findCampaign(campaignId)
	if not campaign then
		return false, "Unknown campaign."
	end
	if Missions.started(progress, campaignId) then
		return true, nil
	end
	local missing = Missions.missing(campaignId, progress)
	if #missing > 0 then
		return false, Missions.missingText(missing)
	end
	if level < campaign.level then
		return false, `{campaign.name} opens at level {campaign.level}.`
	end
	return true, nil
end

-- Is the mission open for a player of `level` with `progress` ({ [mission id] = best stars })? Its campaign (3.2: the
-- campaigns it requires finished, its level), the mission's own level, and the mission before it in the campaign
-- done. Says why not. A mission already cleared needs no level (replays for stars on a 3.1 save).
function Missions.unlocked(id: string, progress: { [string]: number }, level: number): (boolean, string?)
	local def = Missions.find(id)
	if not def then
		return false, "Unknown mission."
	end
	local open, why = Missions.campaignOpen(def.campaign, progress, level)
	if not open then
		return false, why
	end
	if def.level and level < def.level and (progress[id] or 0) < 1 then
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
