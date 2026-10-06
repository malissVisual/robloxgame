-- Logic test of 5.3, the deliveries from real places (shared/Deliveries.luau, Config.Jobs.Businesses `to` / `hours` /
-- `peak`, Config.Jobs.Places, the newspaper round: Config.Jobs.Round, JobRules.round*): every business that has a
-- storefront sends from it, every B2C delivery goes to a home's door, the hours and the evening peak, the spots of the
-- stops (pile 8 – 20 studs from the park, the clerk at the door), the round's doors and its pay.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local JobRules = require("./JobRules")
local Deliveries = require("./Deliveries")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function dist(a: { x: number, z: number }, b: { x: number, z: number }): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- A fixed sequence of "random" numbers (the same run every time).
local function dice(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local byId: { [string]: Config.BusinessDef } = {}
for _, business in Config.Jobs.Businesses do
	byId[business.id] = business
end

-- The hours ----------------------------------------------------------------------------------------

check("inHours: a day range", Deliveries.inHours({ 4, 12 }, 6) and not Deliveries.inHours({ 4, 12 }, 12) and not Deliveries.inHours({ 4, 12 }, 3.9))
check("inHours: over midnight", Deliveries.inHours({ 18, 4 }, 23) and Deliveries.inHours({ 18, 4 }, 1) and not Deliveries.inHours({ 18, 4 }, 12))
check("inHours: none = round the clock", Deliveries.inHours(nil, 3))
check("the bakery bakes in the morning", Deliveries.open(byId.bakery, 6) and not Deliveries.open(byId.bakery, 20))
check("the paper comes in the morning", Deliveries.open(byId.news, 7) and not Deliveries.open(byId.news, 15))
check("the pizzas: any time, the evening pays more", Deliveries.open(byId.pizzeria, 3) and Deliveries.peak(byId.pizzeria, 21) > 1 and Deliveries.peak(byId.pizzeria, 12) == 1)
check("burgers and noodles pay more at night", Deliveries.peak(byId.burgers, 23) > 1 and Deliveries.peak(byId.noodles, 2) > 1)
for hour = 0, 23 do
	for tier = 1, 2 do
		local found = false
		for _, business in Config.Jobs.Businesses do
			if table.find(business.tiers, tier) and Deliveries.open(business, hour + 0.5) then
				found = true
			end
		end
		if not found then
			check(`a ★{tier} business is open at {hour}:30`, false)
		end
	end
end
check("every car tier has an open business at every hour", true)

-- The storefronts and the targets -------------------------------------------------------------------

local B2C = { pizzeria = true, bakery = true, post = true, pharmacy = true, supermarket = true, burgers = true, noodles = true, cafe = true, news = true, flowers = true, icecream = true, electronics = true, pawnshop = true, hardware = true, cake = true }
for id in B2C do
	local business = byId[id]
	check(`{id}: it has a storefront`, business ~= nil and #Map.venuesOf(id) > 0)
	check(`{id}: it delivers somewhere real`, business ~= nil and #Deliveries.targets(business) > 0)
end
check("the electronics go to apartments", (function()
	for _, target in Deliveries.targets(byId.electronics) do
		if target.kind ~= "apartment" then
			return false
		end
	end
	return true
end)())
check("the hardware goes to houses and the Harbor", (function()
	local kinds: { [string]: boolean } = {}
	for _, target in Deliveries.targets(byId.hardware) do
		kinds[target.kind] = true
		if target.kind == "harbor" and (target.person == nil or target.address.district ~= "Harbor") then
			return false
		end
	end
	return kinds.house == true and kinds.harbor == true and kinds.apartment == nil
end)())
check("the bakery also supplies the café and the burger bar (their own people take it)", (function()
	local venues = 0
	for _, target in Deliveries.targets(byId.bakery) do
		if target.kind == "venue" then
			venues += 1
			if not target.person or (target.person.name ~= byId.cafe.giver.name and target.person.name ~= byId.burgers.giver.name) then
				return false
			end
		end
	end
	return venues == 2
end)())
check("a business with no `to` (the lab) has no targets", #Deliveries.targets(byId.lab) == 0)

-- The spots: a venue's and a home's address carry their door, pile and park.
local spotProblem: string? = nil
for _, venue in Map.Venues do
	local address = Deliveries.venueAddress(venue)
	local spot = Deliveries.spotOf(address)
	if address ~= Deliveries.venueAddress(venue) then
		spotProblem = `{venue.id}: a new address every call`
	elseif not spot or spot.venue ~= venue or spot.kind ~= "venue" then
		spotProblem = `{venue.id}: no spot`
	elseif address.x ~= venue.park.x or address.z ~= venue.park.z then
		spotProblem = `{venue.id}: the address is not the park`
	elseif dist(venue.pile, venue.park) < 8 or dist(venue.pile, venue.park) > 20 then
		spotProblem = `{venue.id}: pile {dist(venue.pile, venue.park)} from the park`
	elseif venue.built and (not spot.clerk or dist(spot.clerk, venue.door) > 6) then
		spotProblem = `{venue.id}: the clerk is not at the door`
	elseif not string.find(address.name, venue.name, 1, true) then
		spotProblem = `{venue.id}: the address does not name it ({address.name})`
	end
end
for _, home in Map.Homes do
	local address = Deliveries.homeAddress(home)
	local spot = Deliveries.spotOf(address)
	if not spot or spot.home ~= home or spot.kind ~= "home" or address.name ~= home.name then
		spotProblem = `{home.id}: no spot`
	elseif dist(home.pile, home.door) > 4 then
		spotProblem = `{home.id}: the pile is not at the door`
	end
end
check("every venue and home address has its spot (door, pile, park; the clerk at the door)", spotProblem == nil, spotProblem)
check("an ordinary address has no spot", Deliveries.spotOf(Map.addresses()[1]) == nil)
check("the street a storefront faces", Deliveries.street(Map.venue("luigis") :: Map.Venue) ~= "")

-- The nearest storefront within reach.
local luigis = Map.venue("luigis") :: Map.Venue
check("venueFor: Luigi's from next door", Deliveries.venueFor(byId.pizzeria, luigis.park.x + 40, luigis.park.z, 300, nil) == luigis)
check("venueFor: nothing that far", Deliveries.venueFor(byId.pizzeria, luigis.park.x + 4000, luigis.park.z, 300, nil) == nil)
check("venueFor: a business without a storefront has none", Deliveries.venueFor(byId.lab, 0, 0, 1e9, nil) == nil)

-- A drop in the band (else the closest to it), never one to avoid.
local r = dice(7)
local bandOk, avoidOk = true, true
for _ = 1, 40 do
	local target = Deliveries.dropFor(byId.pizzeria, luigis.park.x, luigis.park.z, 100, 500, {}, r, nil)
	if not target then
		bandOk = false
		break
	end
	local d = Map.manhattan(luigis.park.x, luigis.park.z, target.address.x, target.address.z)
	if d < 100 or d > 500 then
		bandOk = false
	end
	local again = Deliveries.dropFor(byId.pizzeria, luigis.park.x, luigis.park.z, 100, 500, { target.address }, r, nil)
	if again and again.address == target.address then
		avoidOk = false
	end
end
check("dropFor: a home 100 – 500 studs from Luigi's", bandOk)
check("dropFor: never an address to avoid", avoidOk)
local far = Deliveries.dropFor(byId.pizzeria, luigis.park.x, luigis.park.z, 99000, 99999, {}, r, nil)
check("dropFor: nothing in the band gives the closest", far ~= nil)
local onFoot = function(address: Map.Address): boolean
	return Config.Jobs.Foot.Districts[address.district] == true
end
check("dropFor: `allow` keeps the Harbor out", (function()
	for _ = 1, 30 do
		local target = Deliveries.dropFor(byId.hardware, 0, 0, 0, 5000, {}, r, onFoot)
		if target and target.kind == "harbor" then
			return false
		end
	end
	return true
end)())

-- The tutorial: the Post Office is near the depot, a home close to it.
local post = Map.venuesOf("post")[1]
check("the Post Office is within the tutorial's pick-up reach of the depot", post ~= nil and Map.manhattan(0, 0, post.park.x, post.park.z) <= Config.Jobs.TutorialPickupMax)

-- The newspaper round ------------------------------------------------------------------------------

local Round = Config.Jobs.Round
local news = Map.venuesOf(Round.Business)[1]
check("the round's print shop is The Daily Undead", news ~= nil and news.id == "dailyundead")
check("the round's numbers", Round.Papers[1] >= 8 and Round.Papers[2] <= 12 and Round.Papers[1] <= Round.Papers[2] and Round.SureToss < Round.TossRange)
local function streetsOf(doors: { Deliveries.Door }): number
	local seen: { [string]: boolean } = {}
	local n = 0
	for _, door in doors do
		local key = `{door.home.district}:{door.home.street}`
		if not seen[key] then
			seen[key] = true
			n += 1
		end
	end
	return n
end
for _, case in { { "foot", Round.FootReach }, { "bike", Round.BikeReach } } do
	local mode, reach = case[1] :: string, case[2] :: number
	local rr = dice(11)
	local smallest, largest, mostStreets, totalOk, homesOk = math.huge, 0, 0, true, true
	for _ = 1, 30 do
		local doors = Deliveries.round(news, reach, rr, onFoot)
		local papers = 0
		local seen: { [Map.Home]: boolean } = {}
		for _, door in doors do
			papers += door.papers
			if seen[door.home] or door.papers < 1 then
				homesOk = false
			end
			seen[door.home] = true
		end
		if papers > Round.Papers[2] then
			totalOk = false
		end
		smallest = math.min(smallest, papers)
		largest = math.max(largest, papers)
		mostStreets = math.max(mostStreets, streetsOf(doors))
	end
	print(`  {mode} rounds: {smallest} – {largest} papers, {mostStreets} streets at most`)
	check(`{mode}: a round has {Round.Papers[1]} – {Round.Papers[2]} papers`, totalOk and smallest >= Round.Papers[1], smallest)
	check(`{mode}: every door once, a paper or more each`, homesOk)
	check(`{mode}: one or two streets (a third only to fill the bundle)`, mostStreets <= Round.Streets + 1, mostStreets)
end
check("an apartment entrance takes FlatPapers", (function()
	for _, door in Deliveries.round(news, Round.BikeReach, dice(3), nil) do
		if door.home.kind == "apartment" and door.papers ~= Round.FlatPapers and door.papers ~= 1 then
			return false
		end
	end
	return true
end)())
check("roundPay grows with the papers and the route; a bike pays more", JobRules.roundPay(10, 800) > JobRules.roundPay(8, 800) and JobRules.roundPay(10, 1200) > JobRules.roundPay(10, 400) and JobRules.roundPay(10, 800, true) > JobRules.roundPay(10, 800) and JobRules.roundPay(10, 800) % 5 == 0)
check("roundTime: the walk takes longer than the ride", JobRules.roundTime(1000, 8) > JobRules.roundTime(1000, 8, true) and JobRules.roundTime(0, 8) >= Round.TimeBase + 8 * Round.TimePerDoor)
check("roundTip: only with no miss", JobRules.roundTip(0) == Round.NoMissTip and JobRules.roundTip(1) == 0)
check("tossMiss: sure up close, a chance from afar", JobRules.tossMiss(Round.SureToss) == 0 and JobRules.tossMiss(Round.TossRange) == Round.MissAtRange and JobRules.tossMiss((Round.SureToss + Round.TossRange) / 2) > 0)
check("a round never stacks", not JobRules.stackable({ mode = "foot", tier = 1, special = false, mission = false, tutorial = false, duo = false, carried = true, round = true }))

-- Every business's look is light or not on purpose: the food a backpack carries, the big ones in the hands.
check("the newspaper is light and fits the backpack", Config.Cargo.LightLooks.newspaper == true and Config.Cargo.PackLooks.newspaper == true)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
