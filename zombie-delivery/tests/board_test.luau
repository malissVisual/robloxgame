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

-- The tutorial's first delivery (5.0: on foot, two letters on one street) ------------------------------------

local Foot = Jobs.Foot
check("the tutorial's letters fit your two hands", Jobs.TutorialPieces >= 1 and Jobs.TutorialPieces <= Config.Cargo.HandsMax, Jobs.TutorialPieces)
check("the post office sends the letters (a light look, ★)", (function()
	for _, business in Jobs.Businesses do
		if business.id == "post" then
			return Config.Cargo.LightLooks[business.look] == true
		end
	end
	return false
end)())
check("the tutorial's pick-up band is a band", Jobs.TutorialPickupMax >= Foot.PickupMin and Jobs.TutorialPickupMax <= Jobs.PickupMaxDistance)
check("the tutorial's drop is a short walk", Foot.TutorialDrop >= Foot.MinDistance and Foot.TutorialDrop <= Foot.MaxDistance)
check("a few tries for the shortest one", Jobs.TutorialTries >= 1 and Jobs.TutorialTries <= 20)

-- From the depot (Map.Shops.depot: 0, 0) there are foot pick-ups in the band (Downtown, the Suburbs), and drops on foot
-- from them.
local depot = Map.Shops.depot
local pickups, routes = 0, 0
for _, address in Map.addresses() do
	if address.poi or not Foot.Districts[address.district] then
		continue
	end
	local d = Map.manhattan(depot.x, depot.z, address.x, address.z)
	if d >= Foot.PickupMin and d <= Jobs.TutorialPickupMax then
		pickups += 1
		for _, drop in Map.addresses() do
			local leg = Map.manhattan(address.x, address.z, drop.x, drop.z)
			if drop ~= address and not drop.poi and Foot.Districts[drop.district] and leg >= Foot.MinDistance and leg <= Foot.TutorialDrop then
				routes += 1
				break
			end
		end
	end
end
check("addresses around the depot for the tutorial's pick-up", pickups >= 3, pickups)
check("and from them a short walk to the drop", routes >= 3, routes)

-- 5.0: the ON FOOT section: from the depot and from the Suburbs there are foot jobs in the band.
for _, from in { { x = depot.x, z = depot.z, name = "the depot" }, { x = 0, z = 900, name = "the Suburbs" } } do
	local near, far = 0, 0
	for _, address in Map.addresses() do
		if address.poi or not Foot.Districts[address.district] then
			continue
		end
		local d = Map.manhattan(from.x, from.z, address.x, address.z)
		if d <= Foot.PickupMax + Foot.PickupWiden then
			near += 1 -- (none within PickupMax around the depot's safe zone: Jobs widens the band)
		end
		if d >= Foot.MinDistance and d <= Foot.MaxDistance then
			far += 1
		end
	end
	check(`foot jobs around {from.name}: pick-ups and drops`, near >= 8 and far >= 2, `{near} near, {far} in the band`)
end
local harbor = 0
for _, address in Map.addresses() do
	if Foot.Districts[address.district] and address.x > Map.River.x0 then
		harbor += 1
	end
end
check("the foot districts never reach across the river", harbor == 0, harbor)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
