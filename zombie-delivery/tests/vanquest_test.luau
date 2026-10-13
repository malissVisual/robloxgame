-- 5.0, Earl's van (shared/VanQuest.luau, Config.VanQuest, Map.VanSeller): the first vehicle was bought from Earl at
-- Earl's Used Wheels, far out on the West Highway, once Marge told you about him at the van's level. 7.x (one car): the
-- quest is retired: his words now, and the lot on the map (in a yard of its own, off the roads, far from Downtown, next
-- to the West Highway, the landmark). Run with tests/run_tests.py.
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

-- 7.x (one car, Config.CompanyVan): the quest is retired. Every courier owns the ZDC Van from the start; Earl sells
-- nothing, his lot keeps his old van for show and he only talks (server/VanQuest.luau). server/World.luau still names
-- his plate and his prompt with VanQuest.priceText / promptText and Config.VanQuest.Seller / Place.

check("Earl and his place keep their names (server/World.luau reads them)", Config.VanQuest.Seller == "Earl" and Config.VanQuest.Place == "Earl's Used Wheels")
check("his plate: FOR SALE · SOLD; his prompt: Talk", VanQuest.priceText() == "· SOLD" and VanQuest.promptText() == "Talk" and `FOR SALE {VanQuest.priceText()}` == "FOR SALE · SOLD")
check("his old van's tag says it is not for sale", string.find(VanQuest.tag(), "SOLD", 1, true) ~= nil and string.find(VanQuest.tag(), "not for sale", 1, true) ~= nil)
local lines = Config.VanQuest.Lines
check("his lines go round", #lines >= 2 and VanQuest.line(1) == lines[1] and VanQuest.line(#lines + 1) == lines[1] and VanQuest.line(2) == lines[2])
check("his first line sends you to your company's ZDC Van", string.find(VanQuest.line(1), "ZDC Van", 1, true) ~= nil)
check("no quest any more: nothing to buy or open", (VanQuest :: any).canBuy == nil and (VanQuest :: any).shouldOpen == nil and (Config.VanQuest :: any).Car == nil)
check("his old van's body is still the world's (the traffic's Old Van)", (function()
	for _, def in Config.AmbientCars do
		if def.id == "van" then
			return def.name == "Old Van" and def.ambient == true
		end
	end
	return false
end)())

-- The career road: the van is yours at level 1, nothing of Earl's -----------------------------------------------

local row: Career.Unlock? = nil
for _, unlock in Career.unlocksAt(1) do
	if unlock.kind == "car" then
		row = unlock
	end
end
check("the road at level 1: ZDC Van: yours from day one", row ~= nil and (row :: Career.Unlock).id == Config.CompanyVan.Car and (row :: Career.Unlock).name == "ZDC Van: yours from day one", row and row.name)
check("the level 4 reward no longer sends you to Earl", string.find(Config.Levels.Rewards[4].text or "", "Earl", 1, true) == nil)

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
