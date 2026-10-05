-- Logic test of the 3.7 job board (server/Jobs.luau, Config.Jobs): what the timed board, its ★ → ★★★★ order, the
-- clock of an offer taken from farther away and the tutorial's first delivery rely on in Config, Economy and Map.
-- (Jobs.luau itself needs Roblox; these are the rules and the data it builds on.)
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Map = require("./Map")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Jobs = Config.Jobs
local Tiers = Jobs.Tiers

-- The timer -----------------------------------------------------------------------------

check("the board refreshes on a sane timer (30 s … 10 min)", Jobs.RefreshSeconds >= 30 and Jobs.RefreshSeconds <= 600, Jobs.RefreshSeconds)

-- The order: by stars, the specials at theirs ----------------------------------------------

local ordered = true
for index, tier in Tiers do
	if tier.stars ~= index then
		ordered = false
	end
	local before = Tiers[index - 1]
	if before and before.level > tier.level then
		ordered = false
	end
end
check("tier n is n stars and the levels never go down (★ first = the easiest first)", ordered)

local specialsFit = true
local specials = 0
for _, jobType in Config.JobTypes do
	if Economy.onBoard(jobType) and not jobType.mission then
		specials += 1
		if not Tiers[jobType.tier] then
			specialsFit = false
		end
	end
end
check("every board special has a star place on the board", specials > 0 and specialsFit, specials)

-- The board's order, as server/Jobs.luau boardOrder sorts it: stars, level, ordinary before special, then made order.
type Card = { tier: number, level: number, special: boolean, id: number }
local function boardOrder(a: Card, b: Card): boolean
	if a.tier ~= b.tier then
		return a.tier < b.tier
	end
	if a.level ~= b.level then
		return a.level < b.level
	end
	if a.special ~= b.special then
		return b.special
	end
	return a.id < b.id
end
local cards: { Card } = {
	{ tier = 3, level = 5, special = true, id = 1 }, -- a Cash Transport (locked for a new driver)
	{ tier = 1, level = 1, special = true, id = 2 }, -- a Pizza Rush
	{ tier = 1, level = 1, special = false, id = 3 },
	{ tier = 2, level = 2, special = false, id = 4 },
	{ tier = 3, level = 4, special = false, id = 5 },
	{ tier = 4, level = 7, special = false, id = 6 },
}
table.sort(cards, boardOrder)
local ids = {}
for _, card in cards do
	table.insert(ids, card.id)
end
check("the board reads ★ delivery, ★ special, ★★, ★★★, ★★★ special, ★★★★", table.concat(ids, ",") == "3,2,4,5,1,6", table.concat(ids, ","))

-- An offer taken from farther away: the extra clock is the job's own time rule -----------------

local exact = true
for _, distance in { 300, 800, 1500 } do
	for _, extra in { 0, 100, 650 } do
		local rule = Economy.timeLimit(distance + extra) - Economy.timeLimit(distance)
		local added = math.floor(extra * Jobs.TimePerStud + 0.5)
		if math.abs(rule - added) > 1 then
			exact = false
		end
	end
end
check("the extra clock for a longer drive matches Economy.timeLimit (± 1 s rounding)", exact)

-- The tutorial's first delivery ---------------------------------------------------------------

local van = Config.Cars[1]
local vanSlots = Economy.capacity(van.id, {})
check("the starting car is the Old Van", van.name == "Old Van", van.name)
check("the tutorial's pieces fit the Old Van and a ★ delivery", Jobs.TutorialPieces >= 1 and Economy.cargoNeed("carry", Jobs.TutorialPieces) <= vanSlots and Jobs.TutorialPieces <= Jobs.EasyMaxPieces, `{Jobs.TutorialPieces} pieces, {vanSlots} slots`)

local easy = 0
for _, business in Jobs.Businesses do
	local people = business.kind == "kid" or business.kind == "patient" or business.kind == "survivor"
	if table.find(business.tiers, 1) and not people and business.kind ~= "horse" and Config.Cargo.Kinds[business.kind] then
		easy += 1
	end
end
check("there are ★ businesses with carried pieces for the tutorial", easy > 0, easy)
check("a ★ delivery has no modifier and no bulk order", Tiers[1].modifierChance == 0 and (Jobs.BulkChance[1] or 0) == 0)
check("the tutorial's pick-up band is a band", Jobs.TutorialPickupMax >= Jobs.PickupMinDistance and Jobs.TutorialPickupMax <= Jobs.PickupMaxDistance)
check("the tutorial's drop stays in the ★ band", Jobs.TutorialDropMax >= Tiers[1].minDistance and Jobs.TutorialDropMax <= Tiers[1].maxDistance)
check("a few tries for the shortest one", Jobs.TutorialTries >= 1 and Jobs.TutorialTries <= 20)

-- From the depot (Map.Shops.depot: 0, 0) there are pick-ups in the band, and drops in the band from them.
local depot = Map.Shops.depot
local pickups, routes = 0, 0
for _, address in Map.addresses() do
	if address.poi then
		continue
	end
	local d = Map.manhattan(depot.x, depot.z, address.x, address.z)
	if d >= Jobs.PickupMinDistance and d <= Jobs.TutorialPickupMax then
		pickups += 1
		for _, drop in Map.addresses() do
			local leg = Map.manhattan(address.x, address.z, drop.x, drop.z)
			if drop ~= address and not drop.poi and leg >= Tiers[1].minDistance and leg <= Jobs.TutorialDropMax then
				routes += 1
				break
			end
		end
	end
end
check("addresses around the depot for the tutorial's pick-up", pickups >= 3, pickups)
check("and from them a short drop", routes >= 3, routes)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
