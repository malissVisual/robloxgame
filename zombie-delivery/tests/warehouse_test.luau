-- 8.0 SANDBOX, the warehouse (design/sandbox/KONTRAKT.md "warehouse"; shared/WarehouseLayout.luau, which
-- server/Warehouse.luau builds on every plot): on every plot of SandboxMap.Plots
--   * Config.Warehouse.Stands display stands, every one inside the building, with aisles of at least
--     Config.Warehouse.Aisle between any two and along the side walls (a player and a carried sofa walk them)
--   * no stand on the receiving zone (the door's width just inside the roller door) or the way in (the door path, from
--     the van's back through the door and the zone to an aisle past it); nothing solid on that way below the door's top
--   * every piece of the catalogue fits a stand unturned (the sofa 7.2 × 3.2, the wardrobe 4.4 × 2.2 × 7.0, the
--     biggest of all) and stands under the tie beams
--   * WarehouseLayout.standAt finds every stand at its middle and its corners, none in the aisles (a round trip)
--   * the building: within its part budget, unique names, finite sizes, on the plot, over the ground; the lamps few;
--     the UNLOAD HERE bay round the van's spot, in front of the door, off the building
--   * the signs' and the tags' texts
-- Run with tests/run_tests.py.
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")
local FurnitureLooks = require("./FurnitureLooks")

local T = Config.Warehouse

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Rect = { x0: number, x1: number, z0: number, z1: number }
local function rectOf(s: WarehouseLayout.Stand): Rect
	return { x0 = s.x - s.sx / 2, x1 = s.x + s.sx / 2, z0 = s.z - s.sz / 2, z1 = s.z + s.sz / 2 }
end
local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
end
local function within(a: Rect, b: Rect, margin: number?): boolean
	local m = margin or 0
	return a.x0 >= b.x0 + m - 1e-6 and a.x1 <= b.x1 - m + 1e-6 and a.z0 >= b.z0 + m - 1e-6 and a.z1 <= b.z1 - m + 1e-6
end
-- the walk between two boxes: the gap along the axis where they are apart (0: they overlap)
local function gap(a: Rect, b: Rect): number
	local dx = math.max(b.x0 - a.x1, a.x0 - b.x1)
	local dz = math.max(b.z0 - a.z1, a.z0 - b.z1)
	return math.max(dx, dz, 0)
end
local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

check("Config.Warehouse.Stands is 12 (the owner's start), WarehouseLayout.count() says so", T.Stands == 12 and WarehouseLayout.count() == 12, T.Stands)
check("the stands' grid has an even number of columns (half each side of the middle aisle)", T.Columns % 2 == 0, T.Columns)
check("the plots are the four of SandboxMap", #SandboxMap.Plots == 4, #SandboxMap.Plots)

local standsOk, aislesOk, wallsOk, zoneOk, pathOk, plotOk, facingOk, topOk = true, true, true, true, true, true, true, true
local worst, wallWorst = math.huge, math.huge
local roundOk, aisleNil, outsideNil = true, true, true
local budgetOk, namesOk, finiteOk, groundOk, onPlotOk, solidPathOk, lampsOk, signsOk, bayOk = true, true, true, true, true, true, true, true, true
local doorOk, standPartsOk, receivingOk = true, true, true
local most, lampCount = 0, 0
local detail: { string } = {}
for _, plot in SandboxMap.Plots do
	local inside = WarehouseLayout.inside(plot)
	local zone = WarehouseLayout.receiving(plot)
	local path = WarehouseLayout.doorPath(plot)
	local door = WarehouseLayout.door(plot)
	local w = plot.warehouse
	-- the stands
	local rects: { Rect } = {}
	for i = 1, T.Stands do
		local s = WarehouseLayout.stand(plot, i)
		if not s then
			standsOk = false
			continue
		end
		local r = rectOf(s)
		rects[i] = r
		standsOk = standsOk and within(r, inside) and s.index == i and s.sx >= T.StandSize and s.sz >= T.StandSize
		facingOk = facingOk and s.yaw == 180
		topOk = topOk and math.abs(s.y - (WarehouseLayout.FloorTop + T.StandHeight)) < 1e-6
		-- the side walls keep an aisle (the back wall may hold the back row)
		local side = math.min(r.x0 - inside.x0, inside.x1 - r.x1)
		wallWorst = math.min(wallWorst, side)
		wallsOk = wallsOk and side >= T.Aisle - 1e-6
		zoneOk = zoneOk and not overlaps(r, zone)
		pathOk = pathOk and not overlaps(r, path)
		plotOk = plotOk and within(r, plot.rect)
		-- the round trip: the middle and just inside each corner
		local inset = 0.05
		for _, p in { { s.x, s.z }, { r.x0 + inset, r.z0 + inset }, { r.x1 - inset, r.z0 + inset }, { r.x0 + inset, r.z1 - inset }, { r.x1 - inset, r.z1 - inset } } do
			if WarehouseLayout.standAt(plot, p[1], p[2]) ~= i then
				roundOk = false
				table.insert(detail, `plot {plot.id} stand {i} at {p[1]}, {p[2]}`)
			end
		end
		-- just past its edges (the aisles round it): no stand
		for _, p in { { r.x0 - 1, s.z }, { r.x1 + 1, s.z }, { s.x, r.z0 - 1 }, { s.x, r.z1 + 1 } } do
			if WarehouseLayout.standAt(plot, p[1], p[2]) ~= nil then
				aisleNil = false
			end
		end
	end
	for i = 1, T.Stands do
		for j = i + 1, T.Stands do
			local a, b = rects[i], rects[j]
			if a and b then
				local g = gap(a, b)
				worst = math.min(worst, g)
				aislesOk = aislesOk and g >= T.Aisle - 1e-6
			end
		end
	end
	check(`plot {plot.id}: stand 0 and stand {T.Stands + 1} do not exist`, WarehouseLayout.stand(plot, 0) == nil and WarehouseLayout.stand(plot, T.Stands + 1) == nil and WarehouseLayout.stand(plot, 1.5) == nil)
	outsideNil = outsideNil and WarehouseLayout.standAt(plot, door.x, door.z + 3) == nil and WarehouseLayout.standAt(plot, (zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2) == nil and WarehouseLayout.standAt(plot, w.x, w.z - w.sz) == nil
	-- the receiving zone: the door's width, just inside the door
	receivingOk = receivingOk
		and math.abs((zone.x1 - zone.x0) - SandboxMap.DoorWidth) < 1e-6
		and math.abs(zone.z1 - inside.z1) < 1e-6
		and math.abs((zone.z1 - zone.z0) - T.Receiving) < 1e-6
		and within(zone, inside)
	doorOk = doorOk and door.width == SandboxMap.DoorWidth and math.abs(door.z - plot.door.z) < 1e-6 and math.abs(door.x - plot.door.x) < 1e-6 and door.height >= 12

	-- the building
	local pieces = WarehouseLayout.pieces(plot)
	most = math.max(most, #pieces)
	budgetOk = budgetOk and #pieces <= T.MaxParts
	local names: { [string]: boolean } = {}
	local lamps, standParts = 0, 0
	for _, p in pieces do
		if names[p.name] then
			namesOk = false
			table.insert(detail, `duplicate {p.name}`)
		end
		names[p.name] = true
		for k = 1, 3 do
			finiteOk = finiteOk and finite(p.size[k]) and finite(p.at[k]) and p.size[k] > 0
		end
		local x0, x1, y0, y1, z0, z1 = WarehouseLayout.bounds(p)
		if y0 < -0.01 then
			groundOk = false
			table.insert(detail, `{p.name} below the ground ({y0})`)
		end
		if not within({ x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, plot.rect) then
			onPlotOk = false
			table.insert(detail, `{p.name} off the plot`)
		end
		-- nothing solid on the way in (above the floor, under the door's top), the floor itself apart
		if p.solid and p.name ~= "Floor" and y1 > WarehouseLayout.FloorTop + 0.05 and y0 < door.height and overlaps({ x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, path) then
			solidPathOk = false
			table.insert(detail, `{p.name} solid on the way in`)
		end
		-- the door's opening itself: nothing under 14 studs across it (a carried wardrobe, a tall player)
		if y1 > SandboxMap.RoadTop + 0.1 and y0 < 14 and x1 > door.x - door.width / 2 + 0.01 and x0 < door.x + door.width / 2 - 0.01 and z1 > door.z - 1.5 and z0 < door.z + 0.5 and p.group ~= "paint" and p.name ~= "Floor" then
			doorOk = false
			table.insert(detail, `{p.name} in the door's opening`)
		end
		if p.light then
			lamps += 1
		end
		if p.stand then
			standParts += 1
		end
	end
	lampCount = lamps
	lampsOk = lampsOk and lamps >= 4 and lamps <= 8
	standPartsOk = standPartsOk and standParts == 3 * T.Stands
	for _, name in { "ZdcSign", "OwnerSign", "StockBoard", "Floor", "Header", "RoofWest", "RoofEast", "DoorCurtain", "ReceivingText", "BayText" } do
		signsOk = signsOk and names[name] == true
	end
	for i = 1, T.Stands do
		signsOk = signsOk and names[`Stand{i}`] == true and names[`Plate{i}`] == true and names[`StandTop{i}`] == true
	end
	-- the bay: round the van's spot, in front of the door, off the building, on the plot
	local bay = WarehouseLayout.bay(plot)
	local v = plot.vanSpot
	bayOk = bayOk
		and v.x > bay.x0 and v.x < bay.x1 and v.z > bay.z0 and v.z < bay.z1
		and bay.z0 > door.z and within(bay, plot.rect)
		and plot.unload.z > bay.z0 and plot.unload.z < bay.z1
		and (bay.x1 - bay.x0) == T.Bay[1] and (bay.z1 - bay.z0) == T.Bay[2]
	local spawn = plot.spawn
	bayOk = bayOk and not (spawn.x > bay.x0 and spawn.x < bay.x1 and spawn.z > bay.z0 and spawn.z < bay.z1)
end
check(`every stand is inside its building, the way its piece looks (south, to its aisle) and its top at the floor + {T.StandHeight}`, standsOk and facingOk and topOk)
check(`aisles of at least {T.Aisle} studs between any two stands (the least: {worst})`, aislesOk, worst)
check(`an aisle of at least {T.Aisle} studs between the stands and the side walls (the least: {wallWorst})`, wallsOk, wallWorst)
check("no stand on the receiving zone", zoneOk)
check("no stand on the door path (the van's back → the door → the zone → an aisle past it)", pathOk)
check("every stand on its plot", plotOk)
check("the receiving zone: the door's width, just inside the door, Config.Warehouse.Receiving deep", receivingOk)
check("the roller door: SandboxMap's door, its opening clear under 14 studs", doorOk, table.concat(detail, "; "))
check("standAt round-trips: every stand at its middle and its corners", roundOk, table.concat(detail, "; "))
check("standAt: nothing in the aisles round a stand, at the door, in the receiving zone or behind the building", aisleNil and outsideNil)
check(`the building within its part budget ({most} parts of {T.MaxParts})`, budgetOk, most)
check("its pieces' names are unique, their sizes finite and positive", namesOk and finiteOk, table.concat(detail, "; "))
check("its pieces stand on the plot, none under the ground", onPlotOk and groundOk, table.concat(detail, "; "))
check("nothing solid on the way in under the door's top (the floor apart)", solidPathOk, table.concat(detail, "; "))
check(`the hall's lamps: {lampCount} (4 … 8 PointLights)`, lampsOk, lampCount)
check("the signs (ZDC, the owner's, STOCK, RECEIVING, UNLOAD HERE) and every stand's podium, top and plate", signsOk and standPartsOk)
check("the UNLOAD HERE bay: round the van's spot and the unload circle, in front of the door, off the spawn, on the plot", bayOk)

-- WarehouseLayout.stands (the guide's arrow): a plot or its id, every stand in stand-number order
local listOk = true
for _, plot in SandboxMap.Plots do
	local byPlot, byId = WarehouseLayout.stands(plot), WarehouseLayout.stands(plot.id)
	listOk = listOk and #byPlot == T.Stands and #byId == T.Stands
	for i = 1, T.Stands do
		local s = WarehouseLayout.stand(plot, i) :: WarehouseLayout.Stand
		local a, b = byPlot[i], byId[i]
		listOk = listOk and a and b and a.x == s.x and a.y == s.y and a.z == s.z and b.x == s.x and b.z == s.z
			and type(a.x) == "number" and type(a.y) == "number" and type(a.z) == "number"
	end
end
check("stands(plot or id): every stand's spot { x, y, z } in stand-number order; {} for no plot", listOk and #WarehouseLayout.stands(99) == 0)

-- every piece of the catalogue fits a stand (unturned: it looks south) and stands under the tie beams
local fits, tallest, biggest = true, 0, ""
local beams = SandboxMap.Plots[1].warehouse.sy - 1
for _, id in FurnitureLooks.Order do
	local size = FurnitureLooks.Items[id].size
	if size.X > T.StandSize - 0.2 or size.Z > T.StandSize - 0.2 then
		fits = false
		biggest ..= id .. " "
	end
	tallest = math.max(tallest, size.Y)
end
local sofa, wardrobe = FurnitureLooks.Items.sofa.size, FurnitureLooks.Items.wardrobe.size
check("the sofa (7.2 × 3.2) and the wardrobe (4.4 × 2.2 × 7.0) fit a stand", sofa.X <= T.StandSize and sofa.Z <= T.StandSize and wardrobe.X <= T.StandSize and wardrobe.Z <= T.StandSize and wardrobe.Y <= 7.01)
check(`every piece of the catalogue fits a stand ({#FurnitureLooks.Order} pieces, the hay wagon's 9.6 the longest)`, fits, biggest)
check(`the tallest piece on a stand stays under the tie beams ({tallest} studs)`, WarehouseLayout.FloorTop + T.StandHeight + tallest < beams - 1, tallest)

-- the texts
check("the owner's sign: <Name>'s Warehouse", WarehouseLayout.ownerLines("Pavel", 2)[1].text == "Pavel's Warehouse" and WarehouseLayout.ownerLines("Pavel", 2)[2].text == "ZDC STORAGE · PLOT 2")
check("…FOR RENT without an owner", WarehouseLayout.ownerLines(nil, 3)[1].text == "FOR RENT")
local board = WarehouseLayout.stockLines(5, 12.4, 3, 12)
check("the STOCK board: 📦 N pieces in stock · $X/min", board[1].text == "STOCK" and board[2].text == "📦 5 pieces in stock · $12/min" and board[3].text == "3 of 12 stands on show", board[2].text)
check("…one piece", WarehouseLayout.stockLines(1, 2.5, 0, 12)[2].text == "📦 1 piece in stock · $2.5/min", WarehouseLayout.stockLines(1, 2.5, 0, 12)[2].text)
local tag = WarehouseLayout.tagLines("Old TV", "Rare", 3)
check("a shown piece's tag: its name in its rarity's colour, RARE · +$3/min", tag[1].text == "Old TV" and tag[1].color == T.Rarity.rare and tag[2].text == "RARE · +$3/min", tag[2].text)
check("…an unknown rarity takes common's colour", WarehouseLayout.rarityColor("mythic") == T.Rarity.common and WarehouseLayout.rarityColor(nil) == T.Rarity.common and WarehouseLayout.tagLines("Box", nil, 0)[2].text == "COMMON · +$0/min")
check("money: $0, $2.5, $10, $1,234, $1,234,568", WarehouseLayout.money(0) == "$0" and WarehouseLayout.money(2.46) == "$2.5" and WarehouseLayout.money(9.96) == "$10" and WarehouseLayout.money(1234) == "$1,234" and WarehouseLayout.money(1234567.6) == "$1,234,568" and WarehouseLayout.money(-3) == "$0", WarehouseLayout.money(1234567.6))

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
