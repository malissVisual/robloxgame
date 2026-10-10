-- 5.0, Earl's van (shared/VanQuest.luau, Config.VanQuest, Map.VanSeller): the first vehicle is bought from Earl at
-- Earl's Used Wheels, far out on the West Highway, once Marge tells you about him at the van's level. The quest's
-- states, who may buy, Earl's words, and the lot on the map (in a yard of its own, off the roads, far from Downtown,
-- next to the West Highway, the landmark). Run with tests/run_tests.py.
local Config = require("./Config")
local Map = require("./Map")
local Career = require("./Career")
local VanQuest = require("./VanQuest")
local Icons = require("./Icons")
local LocationTags = require("./LocationTags")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local van = VanQuest.def()
local LEVEL, PRICE = van.level or 1, van.price

-- The quest car -------------------------------------------------------------------------------------------------

check("Earl sells the Old Van, level 4, $5,400 (6.19: $1,800 × Prices.Vehicles)", van.id == "van" and Config.VanQuest.Car == "van" and LEVEL == 4 and PRICE == 5400)
check("level and price come from the car", VanQuest.level() == LEVEL and VanQuest.price() == PRICE)
check("only the van is the quest car", VanQuest.isQuestCar("van") and not VanQuest.isQuestCar("courier") and not VanQuest.isQuestCar(nil))
check("the price in words", VanQuest.priceText() == "$5,400" and VanQuest.promptText() == "Buy the van ($5,400)", VanQuest.promptText())

-- The states ----------------------------------------------------------------------------------------------------

check("below the level: locked", VanQuest.status(nil, false, LEVEL - 1) == "locked")
check("at the level: open (even before Marge texts)", VanQuest.status(nil, false, LEVEL) == "open")
check("told: open", VanQuest.status("open", false, LEVEL + 3) == "open")
check("bought: done", VanQuest.status("done", true, LEVEL) == "done" and VanQuest.status(nil, true, 1) == "done")
check("Marge texts at the level, once", VanQuest.shouldOpen(nil, false, LEVEL) and VanQuest.shouldOpen(nil, false, LEVEL + 5)
	and not VanQuest.shouldOpen("open", false, LEVEL) and not VanQuest.shouldOpen("done", false, LEVEL))
check("not below the level, not with a van", not VanQuest.shouldOpen(nil, false, LEVEL - 1) and not VanQuest.shouldOpen(nil, true, LEVEL))

-- Buying --------------------------------------------------------------------------------------------------------

local function info(changes: { [string]: any }): VanQuest.BuyInfo
	local base: { [string]: any } = { distance = 5, level = LEVEL, quest = "open", ownsVan = false, money = PRICE }
	for key, value in changes do
		base[key] = value
	end
	return (base :: any) :: VanQuest.BuyInfo
end
local function why(changes: { [string]: any }): string?
	local ok, reason = VanQuest.canBuy(info(changes))
	return if ok then "ok" else reason
end
check("everything right: sold", why({}) == "ok")
check("exactly the money is enough", why({ money = PRICE }) == "ok" and why({ money = PRICE - 1 }) == "money")
check("too far from Earl", why({ distance = Config.VanQuest.Range + 0.5 }) == "far" and why({ distance = 0 / 0 }) == "far"
	and why({ distance = math.huge }) == "far")
check("below the level", why({ level = LEVEL - 1 }) == "level")
check("Marge has not sent you yet", select(2, VanQuest.canBuy({ distance = 5, level = LEVEL, quest = nil, ownsVan = false, money = PRICE })) == "quest")
check("one van per player", why({ ownsVan = true }) == "owned" and why({ quest = "done" }) == "owned")
check("far wins over money (no words across the lot)", why({ distance = 99, money = 0 }) == "far")

-- Earl's words --------------------------------------------------------------------------------------------------

check("no money: 'Come back with $5,400, kid.'", VanQuest.sellerLine("money") == "Come back with $5,400, kid.", VanQuest.sellerLine("money"))
check("sold: the keys", VanQuest.sellerLine(nil) == Config.VanQuest.Keys)
check("too early, already sold", VanQuest.sellerLine("level") == Config.VanQuest.TooYoung and VanQuest.sellerLine("owned") == Config.VanQuest.Sold)
check("Marge's texts as the owner wrote them", Config.VanQuest.Unlock == "A guy out west is selling his old van. Cheap-ish. Go see Earl — I put him on your GPS."
	and string.find(Config.VanQuest.Bought, "★ car jobs", 1, true) ~= nil and string.find(Config.VanQuest.Bought, "fuel", 1, true) ~= nil)

-- The career road -----------------------------------------------------------------------------------------------

local row: Career.Unlock? = nil
for _, unlock in Career.unlocksAt(LEVEL) do
	if unlock.kind == "car" and unlock.id == "van" then
		row = unlock
	end
end
check("the road at level 4: Old Van: Earl's Used Wheels (Marge's quest at level 4)", row ~= nil and (row :: Career.Unlock).name == "Old Van: Earl's Used Wheels (Marge's quest at level 4)", row and row.name)
check("the level 4 reward says so", string.find(Config.Levels.Rewards[4].text or "", "Earl", 1, true) ~= nil)

-- The lot -------------------------------------------------------------------------------------------------------

local seller = Map.VanSeller
local yard: Map.Area? = nil
for _, area in Map.Yards do
	if area.id == "earl" then
		yard = area
	end
end
check("Earl's Used Wheels is a yard", yard ~= nil)
local function inside(a: Map.Area, x: number, z: number, margin: number): boolean
	return x > a.x0 + margin and x < a.x1 - margin and z > a.z0 + margin and z < a.z1 - margin
end
if yard then
	check("the van for sale, Earl and the parking spot are in it (with room around)", inside(yard, seller.x, seller.z, 8)
		and inside(yard, seller.earl.x, seller.earl.z, 8) and inside(yard, seller.parking.x, seller.parking.z, 8))
	check("the van for sale and the one you buy stand apart", math.abs(seller.x - seller.parking.x) >= 30)
	check("both face the highway (south)", seller.facing.x == 0 and seller.facing.z == 1)
	-- Off every road: no road's asphalt reaches into the lot (its front edge is the highway's edge).
	local clear = true
	for _, s in Map.Segments do
		for x = yard.x0, yard.x1, 5 do
			for z = yard.z0, yard.z1 - 1, 5 do
				local dx, dz = s.bx - s.ax, s.bz - s.az
				local length2 = dx * dx + dz * dz
				local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
				local d = math.sqrt((x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2)
				if d < s.width / 2 then
					clear = false
				end
			end
		end
	end
	check("no road runs through the lot", clear)
	-- Its front on the West Highway: from the gate in front of the van you buy you are on it.
	local _, _, _, _, width = Map.nearestRoad(seller.parking.x, yard.z1 + 2)
	local onHighway = false
	for _, s in Map.Connectors do
		if s.name == "West Highway" and s.az == s.bz and math.abs(s.az - (yard.z1 + Map.HighwayWidth / 2)) < 1
			and seller.parking.x <= math.max(s.ax, s.bx) and seller.parking.x >= math.min(s.ax, s.bx) then
			onHighway = true
		end
	end
	check("its front is the West Highway's edge", onHighway and width == Map.HighwayWidth)
	check("dry, off the lake and the mountain", not Map.inWater(yard.x0, yard.z0) and not Map.inWater(yard.x1, yard.z1))
	local estateClear = true
	for _, plot in Map.EstatePlots do
		if plot.x > yard.x0 - 80 and plot.x < yard.x1 + 80 and plot.z > yard.z0 - 80 and plot.z < yard.z1 + 80 then
			estateClear = false
		end
	end
	check("no home or garage next to it", estateClear)
end
check("far from the depot (a trip out west)", seller.x < -1400 and math.sqrt(seller.x ^ 2 + seller.z ^ 2) > 1400)
check("nothing else of the map's places stands there", (function()
	for _, place in Map.Places do
		if (place.x - seller.x) ^ 2 + (place.z - seller.z) ^ 2 < 150 * 150 then
			return false
		end
	end
	for _, spot in Map.EmployerSpots do
		if (spot.x - seller.x) ^ 2 + (spot.z - seller.z) ^ 2 < 150 * 150 then
			return false
		end
	end
	return true
end)())

-- The landmark (the map, the GPS, the discovery) ----------------------------------------------------------------

local landmark: Map.Landmark? = nil
for _, entry in Map.Landmarks do
	if entry.id == "earl" then
		landmark = entry
	end
end
check("a landmark 'Earl's Used Wheels' at Earl", landmark ~= nil and (landmark :: Map.Landmark).name == "Earl's Used Wheels"
	and (landmark :: Map.Landmark).x == seller.earl.x and (landmark :: Map.Landmark).z == seller.earl.z)
check("its map icon", Icons.landmark("earl") ~= nil)
local tag: LocationTags.Tag? = nil
for _, entry in LocationTags.build() do
	if entry.id == "earl" then
		tag = entry
	end
end
check("its location tag measures to the lot", tag ~= nil and (tag :: LocationTags.Tag).area ~= nil and LocationTags.distance(tag :: LocationTags.Tag, seller.x, seller.z) == 0)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
