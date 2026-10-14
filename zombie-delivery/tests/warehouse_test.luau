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
--   * 8.0.1: everything outside on the plot's concrete (SandboxMap.GroundTop, flush with the meadow; not the asphalt's
--     RoadTop): the bay's lines and words a hair over it, the bollards' feet on it, the hall's floor at most 0.1 over it
--     (no step at the door); the bay centred on the parked van (Config.Sprinter.Length at vanSpot), its words in the
--     room between the van's back and the bay's door end
--   * the signs' and the tags' texts
--   * 8.1 (the upgrades): the hall holds Config.Warehouse.MaxStands (20): the start's 12 big ones as before and 8
--     smaller upgrade stands (the front corners beside the receiving zone, the middle aisle), every one of the 20 with
--     the checks above (aisles, walls, the zone, the way in, the round trip) and the room in front of the side it
--     looks at; an upgrade stand's painted spot under its podium; the small stands hold most of the catalogue
--     (WarehouseLayout.fits), the big ones all of it; the UPGRADES desk at the back wall's middle, off every stand
--     and the way in, with room to stand at it
--   * 8.3 (design/warehouse-levels/KONTRAKT.md): every check above on every warehouse level (WarehouseLayout.site: the
--     Garage, the Workshop, the Storehouse, the Big Warehouse above, the Logistics Center), each with its own numbers
--     (its big stands, its small spots from Config.Warehouse.MoreFrom on, its door, its receiving zone, the least walk
--     and the side room of WarehouseLayout.grid); every level's front wall and door where the plot's are, its box
--     behind it on the plot, the Blender level's size, door and top (Config.Warehouse.Levels); the pieces on its
--     stands clear of its beams and lamps; the sites, levelOf, count, capacity, fits and standSize per level
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
local ALL = WarehouseLayout.capacity()
check("8.1: the hall holds Config.Warehouse.MaxStands (20) stands: WarehouseLayout.capacity()", T.MaxStands == 20 and ALL == 20, ALL)
check("the stands' grid has an even number of columns (half each side of the middle aisle)", T.Columns % 2 == 0, T.Columns)
check("the plots are the four of SandboxMap", #SandboxMap.Plots == 4, #SandboxMap.Plots)

local standsOk, aislesOk, wallsOk, zoneOk, pathOk, plotOk, facingOk, topOk = true, true, true, true, true, true, true, true
local worst, wallWorst = math.huge, math.huge
local roundOk, aisleNil, outsideNil = true, true, true
local budgetOk, namesOk, finiteOk, groundOk, onPlotOk, solidPathOk, lampsOk, signsOk, bayOk = true, true, true, true, true, true, true, true, true
local GROUND = SandboxMap.GroundTop
local floorOk, paintOk, bollardsOk, bayMiddleOk, wordsOk = true, true, 0, true, true
local doorOk, standPartsOk, receivingOk = true, true, true
local frontOk, spotsOk, deskOk, deskRoomOk = true, true, true, true
local siteOk, overheadOk, roofOk, colourOk = true, true, true, true
local TALLEST = 0 -- (the catalogue's tallest piece)
for _, id in FurnitureLooks.Order do
	TALLEST = math.max(TALLEST, FurnitureLooks.Items[id].size.Y)
end
local most, lampCount = 0, 0
local lampsSeen: { string } = {}
local detail: { string } = {}
for level = 1, WarehouseLayout.Levels do
for _, basePlot in SandboxMap.Plots do
	-- 8.3: the plot at this level (a Site): its own big stands, small spots, door, receiving zone and walks
	local plot = WarehouseLayout.site(basePlot, level) :: SandboxMap.Plot
	local ALL = WarehouseLayout.capacity(level)
	local BIG = WarehouseLayout.count(level)
	local G = WarehouseLayout.grid(level)
	local inside = WarehouseLayout.inside(plot)
	local zone = WarehouseLayout.receiving(plot)
	local path = WarehouseLayout.doorPath(plot)
	local door = WarehouseLayout.door(plot)
	local w = plot.warehouse
	-- the stands
	local rects: { Rect } = {}
	for i = 1, ALL do
		local s = WarehouseLayout.stand(plot, i)
		if not s then
			standsOk = false
			continue
		end
		local r = rectOf(s)
		rects[i] = r
		-- the start's 12: the big podium, looking south; 8.1's upgrade stands: the small one, south or north
		local big = i <= BIG
		local wide, deep = if big then T.StandSize else T.SmallStand[1], if big then T.StandSize else T.SmallStand[2]
		standsOk = standsOk and within(r, inside) and s.index == i and s.sx >= wide and s.sz >= deep and (s.small == true) == not big
		facingOk = facingOk and (s.yaw == 180 or (not big and s.yaw == 0))
		topOk = topOk and math.abs(s.y - (WarehouseLayout.FloorTop + T.StandHeight)) < 1e-6
		-- the side walls keep an aisle (the back wall may hold the back row)
		local side = math.min(r.x0 - inside.x0, inside.x1 - r.x1)
		wallWorst = math.min(wallWorst, side)
		wallsOk = wallsOk and side >= G.side - 1e-6
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
	for i = 1, ALL do
		for j = i + 1, ALL do
			local a, b = rects[i], rects[j]
			if a and b then
				local g = gap(a, b)
				worst = math.min(worst, g)
				aislesOk = aislesOk and g >= G.walk - 1e-6
			end
		end
	end
	-- 8.1: the side a stand looks at (its prompts, its plate): an aisle's depth in front of it, inside the hall, no stand
	for i = 1, ALL do
		local s = WarehouseLayout.stand(plot, i)
		local r = rects[i]
		if s and r then
			local strip: Rect = if s.yaw == 0 then { x0 = r.x0, x1 = r.x1, z0 = r.z0 - G.walk, z1 = r.z0 } else { x0 = r.x0, x1 = r.x1, z0 = r.z1, z1 = r.z1 + G.walk }
			local clear = within(strip, inside)
			for j = 1, ALL do
				if j ~= i and rects[j] and overlaps(strip, rects[j]) then
					clear = false
				end
			end
			if not clear then
				frontOk = false
				table.insert(detail, `level {level} plot {plot.id} stand {i}: no room in front`)
			end
		end
	end
	check(`plot {plot.id}: stand 0 and stand {ALL + 1} do not exist`, WarehouseLayout.stand(plot, 0) == nil and WarehouseLayout.stand(plot, ALL + 1) == nil and WarehouseLayout.stand(plot, 1.5) == nil)
	-- 8.1: the UPGRADES desk: against the back wall's middle, facing the hall, off every stand, the zone and the way in,
	-- with an aisle's depth free in front of it
	local desk = WarehouseLayout.terminal(plot)
	local deskRect: Rect = { x0 = desk.x - desk.sx / 2, x1 = desk.x + desk.sx / 2, z0 = desk.z - desk.sz / 2, z1 = desk.z + desk.sz / 2 }
	local room: Rect = { x0 = deskRect.x0, x1 = deskRect.x1, z0 = deskRect.z1, z1 = deskRect.z1 + G.walk }
	deskOk = deskOk and within(deskRect, inside) and math.abs(deskRect.z0 - inside.z0) < 1e-6 and math.abs(desk.x - w.x) < 1e-6 and desk.yaw == 180
		and not overlaps(deskRect, zone) and not overlaps(deskRect, path) and desk.y > WarehouseLayout.FloorTop + 2.5 and desk.y < WarehouseLayout.FloorTop + 4
	deskRoomOk = deskRoomOk and within(room, inside) and not overlaps(room, path)
	for i = 1, ALL do
		if rects[i] and (overlaps(deskRect, rects[i]) or overlaps(room, rects[i])) then
			deskRoomOk = false
			table.insert(detail, `level {level} plot {plot.id}: the desk at stand {i}`)
		end
	end
	outsideNil = outsideNil and WarehouseLayout.standAt(plot, door.x, door.z + 3) == nil and WarehouseLayout.standAt(plot, (zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2) == nil and WarehouseLayout.standAt(plot, w.x, w.z - w.sz) == nil
	-- the receiving zone: the door's width, just inside the door
	receivingOk = receivingOk
		and math.abs((zone.x1 - zone.x0) - door.width) < 1e-6
		and math.abs(zone.z1 - inside.z1) < 1e-6
		and math.abs((zone.z1 - zone.z0) - G.receiving) < 1e-6
		and within(zone, inside)
	local def = WarehouseLayout.level(level)
	doorOk = doorOk and door.width == def.door[1] and door.height == def.door[2] and math.abs(door.z - plot.door.z) < 1e-6 and math.abs(door.x - plot.door.x) < 1e-6 and door.height >= 9
	-- 8.3: the level's box: the Blender level's size, its front wall the plot's (where the door is), on the plot
	local box = plot.warehouse
	local out = WarehouseLayout.outline(plot)
	siteOk = siteOk and box.sx == def.size[1] and box.sy == def.size[2] and box.sz == def.size[3] and math.abs(out.z1 - plot.door.z) < 1e-6
		and math.abs(box.x - basePlot.warehouse.x) < 1e-6 and within(out, plot.rect) and WarehouseLayout.levelOf(plot) == level
		and math.abs(out.top - (def.size[2] + (if def.roof == "shed" then 0 else def.rise))) < 1e-6

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
		-- (8.3: a colour, three whole numbers 0 … 255, and a material for every piece; a light's colour too)
		local c = p.color
		local light = p.light
		if not (type(c) == "table" and #c == 3 and type(p.material) == "string" and (light == nil or type(light.color) == "table")) then
			colourOk = false
			table.insert(detail, `level {level}: {p.name} without a colour`)
		else
			for k = 1, 3 do
				colourOk = colourOk and type(c[k]) == "number" and c[k] >= 0 and c[k] <= 255
			end
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
		-- nothing solid on the way in (above the floor, under the door's top), the floor itself apart (8.3: and the roof,
		-- which stands on the walls: a shed's tilted slab's box reaches down to its back wall's top, over the way in it
		-- is far over the door; its own check below)
		if p.group == "roof" and p.solid then
			roofOk = roofOk and y0 >= plot.warehouse.sy - def.rise - 1 - 1e-6
		end
		if p.solid and p.name ~= "Floor" and p.group ~= "roof" and y1 > WarehouseLayout.FloorTop + 0.05 and y0 < door.height and overlaps({ x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, path) then
			solidPathOk = false
			table.insert(detail, `{p.name} solid on the way in`)
		end
		-- the door's opening itself: nothing under 14 studs across it (a carried wardrobe, a tall player; 8.3: under the
		-- rolled-up door's bottom, 2 under the opening's top: a Garage's 7.5)
		if y1 > GROUND + 0.1 and y0 < door.height - 2 and x1 > door.x - door.width / 2 + 0.01 and x0 < door.x + door.width / 2 - 0.01 and z1 > door.z - 1.5 and z0 < door.z + 0.5 and p.group ~= "paint" and p.name ~= "Floor" then
			doorOk = false
			table.insert(detail, `level {level}: {p.name} in the door's opening`)
		end
		if p.light then
			lamps += 1
		end
		-- 8.0.1: on the plot's concrete (GroundTop), not the asphalt's RoadTop
		if p.name == "Floor" then
			floorOk = floorOk and math.abs(y0 - GROUND) < 1e-6 and math.abs(y1 - WarehouseLayout.FloorTop) < 1e-6
		elseif p.group == "bay" then
			-- (the words' part lies flat: its face up at y1)
			if not (y0 > GROUND and y0 <= GROUND + 0.05 and y1 <= GROUND + 0.1) then
				paintOk = false
				table.insert(detail, `{p.name} at {y0} … {y1}`)
			end
		elseif string.sub(p.name, 1, 7) == "Bollard" then
			if math.abs(y0 - GROUND) < 1e-6 and y1 > GROUND + 3 then
				bollardsOk += 1
			else
				table.insert(detail, `{p.name}'s foot at {y0}`)
			end
		end
		if p.stand then
			standParts += 1
		end
	end
	lampCount = math.max(lampCount, lamps)
	lampsOk = lampsOk and lamps == #G.lamps and lamps >= 1 and lamps <= 12
	if basePlot.id == 1 then
		table.insert(lampsSeen, `{lamps}`)
	end
	standPartsOk = standPartsOk and standParts == 3 * ALL
	local shed = def.roof == "shed"
	for _, name in { "OwnerSign", "StockBoard", "Floor", "Header", "DoorCurtain", "ReceivingText", "BayText", "TerminalDesk", "TerminalTop", "TerminalScreen", "UpgradeSign" } do
		signsOk = signsOk and names[name] == true
	end
	-- (8.3: a shed's one roof and its sloped side walls; a gable's two slopes and the ZDC sign in its front gable)
	for _, name in (if shed then { "Roof", "WallSlopeWest", "WallSlopeEast" } else { "ZdcSign", "RoofWest", "RoofEast" }) do
		signsOk = signsOk and names[name] == true
	end
	for i = 1, ALL do
		signsOk = signsOk and names[`Stand{i}`] == true and names[`Plate{i}`] == true and names[`StandTop{i}`] == true
	end
	-- 8.1: an upgrade stand's spot painted under its podium (the outline and its words: covered once it is built), the
	-- start's stands without one; the desk's body solid
	local byName: { [string]: any } = {}
	for _, p in pieces do
		byName[p.name] = p
	end
	for i = 1, ALL do
		local s = WarehouseLayout.stand(plot, i) :: WarehouseLayout.Stand
		local podium = byName[`Stand{i}`]
		local _, _, _, podiumTop = WarehouseLayout.bounds(podium)
		local spot = { byName[`Spot{i}North`], byName[`Spot{i}South`], byName[`Spot{i}West`], byName[`Spot{i}East`], byName[`SpotText{i}`] }
		if i <= BIG then
			spotsOk = spotsOk and #spot == 0
		else
			spotsOk = spotsOk and #spot == 5 and spot[5].words ~= nil and spot[5].words[1].lines[1].text == `STAND {i}`
			for _, part in spot do
				local x0, x1, y0, y1, z0, z1 = WarehouseLayout.bounds(part)
				local under = part.group == "paint" and x0 >= s.x - s.sx / 2 - 1e-6 and x1 <= s.x + s.sx / 2 + 1e-6 and z0 >= s.z - s.sz / 2 - 1e-6 and z1 <= s.z + s.sz / 2 + 1e-6
					and y0 >= WarehouseLayout.FloorTop - 1e-6 and y1 < podiumTop and not part.solid
				if not under then
					spotsOk = false
					table.insert(detail, `level {level}: {part.name} not under its podium`)
				end
			end
		end
	end
	deskOk = deskOk and byName.TerminalDesk ~= nil and byName.TerminalDesk.solid == true and byName.TerminalDesk.group == "terminal" and byName.TerminalScreen.words ~= nil
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
	-- 8.0.1: centred on the parked van (yaw 180: its nose south, its back to the door), the van inside it with room at
	-- both ends, the words between the bay's north line and the van's back (seen with the van parked)
	local van = { x0 = v.x - Config.Sprinter.Width / 2, x1 = v.x + Config.Sprinter.Width / 2, z0 = v.z - Config.Sprinter.Length / 2, z1 = v.z + Config.Sprinter.Length / 2 }
	bayMiddleOk = bayMiddleOk and v.yaw == 180
		and math.abs((bay.x0 + bay.x1) / 2 - v.x) < 1e-6 and math.abs((bay.z0 + bay.z1) / 2 - v.z) < 1e-6
		and within(van, bay, 1)
	for _, p in pieces do
		if p.name == "BayText" then
			local x0, x1, _, _, z0, z1 = WarehouseLayout.bounds(p)
			wordsOk = wordsOk and z0 >= bay.z0 + 0.5 - 1e-6 and z1 <= van.z0 + 1e-6 and z1 - z0 >= 2 and x0 >= bay.x0 and x1 <= bay.x1
		end
	end
	-- 8.3: the pieces on its stands (the tallest of the catalogue) clear under its beams and lamps where they pass over
	for _, p in pieces do
		local beam = string.sub(p.name, 1, 4) == "Beam" or (string.sub(p.name, 1, 4) == "Lamp" and string.sub(p.name, 1, 8) ~= "LampGlow")
		if beam then
			local x0, x1, y0, _, z0, z1 = WarehouseLayout.bounds(p)
			for i = 1, ALL do
				local r = rects[i]
				if r and overlaps(r, { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }) and WarehouseLayout.FloorTop + T.StandHeight + TALLEST > y0 - 0.5 then
					overheadOk = false
					table.insert(detail, `level {level}: {p.name} over stand {i} at {y0}`)
				end
			end
		end
	end
end
end
check(`8.3: every level's box: the Blender level's size, door and top (Config.Warehouse.Levels), its front wall and door the plot's, on the plot`, siteOk)
check("8.3: every level's solid roof on its walls (never lower than a stud under its lowest wall's top)", roofOk)
check(`8.3: the pieces on every level's stands (the tallest, {TALLEST}) clear under its beams and lamps`, overheadOk, table.concat(detail, "; "))
check(`every stand (all {ALL}: the start's 12 big, 8.1's small ones) is inside its building, the way its piece looks (south, to its aisle; an upgrade stand south or north) and its top at the floor + {T.StandHeight}`, standsOk and facingOk and topOk)
check(`8.1: every stand has an aisle (its level's walk: {T.Aisle} in the Big Warehouse) in front of the side it looks at, inside the hall, no other stand on it`, frontOk, table.concat(detail, "; "))
check(`aisles of at least the level's walk between any two stands ({T.Aisle} in the Big Warehouse; the least anywhere: {worst})`, aislesOk, worst)
check(`the level's side room between the stands and the side walls ({T.Aisle} in the Big Warehouse; 0 where they stand against them; the least: {wallWorst})`, wallsOk, wallWorst)
check("no stand on the receiving zone", zoneOk)
check("no stand on the door path (the van's back → the door → the zone → an aisle past it)", pathOk)
check("every stand on its plot", plotOk)
check("the receiving zone: the door's width, just inside the door, the level's depth (Config.Warehouse.Receiving in the Big Warehouse)", receivingOk)
check("the roller door: the level's (the Big Warehouse's SandboxMap.DoorWidth), at the plot's door, its opening clear under the rolled-up door", doorOk, table.concat(detail, "; "))
check("standAt round-trips: every stand at its middle and its corners", roundOk, table.concat(detail, "; "))
check("standAt: nothing in the aisles round a stand, at the door, in the receiving zone or behind the building", aisleNil and outsideNil)
check(`the building within its part budget ({most} parts of {T.MaxParts})`, budgetOk, most)
check("its pieces' names are unique, their sizes finite and positive", namesOk and finiteOk, table.concat(detail, "; "))
check("8.3: every piece of every level has its colour and material (a lamp's light its colour)", colourOk, table.concat(detail, "; "))
check("its pieces stand on the plot, none under the ground", onPlotOk and groundOk, table.concat(detail, "; "))
check("nothing solid on the way in under the door's top (the floor apart)", solidPathOk, table.concat(detail, "; "))
check(`the hall's lamps: the level's (Garage … Logistics Center: {table.concat(lampsSeen, ", ")} PointLights, at most 12)`, lampsOk, lampCount)
check("the signs (ZDC, the owner's, STOCK, RECEIVING, UNLOAD HERE, 8.1's UPGRADES desk and sign) and every stand's podium, top and plate", signsOk and standPartsOk)
check("8.1: an upgrade stand's spot (its outline, \"STAND n\") painted under its podium: covered once it is built; none for the start's", spotsOk, table.concat(detail, "; "))
check("8.1: the UPGRADES desk at the back wall's middle, facing the hall, its top at counter height, off the zone and the way in; its body solid", deskOk)
check(`8.1: … no stand on it and an aisle (the level's walk) free in front of it to stand at`, deskRoomOk, table.concat(detail, "; "))
check("the UNLOAD HERE bay: round the van's spot and the unload circle, in front of the door, off the spawn, on the plot", bayOk)
check("8.0.1: the bay centred on the parked Sprinter (vanSpot), the van inside it with a stud to spare all round", bayMiddleOk)
check("8.0.1: UNLOAD HERE between the bay's door end and the parked van's back (not under it)", wordsOk)
check(`8.0.1: the hall's floor from the plot's concrete (GroundTop) to FloorTop, a lip of at most 0.1 at the door ({WarehouseLayout.FloorTop - GROUND})`, floorOk and WarehouseLayout.FloorTop > GROUND and WarehouseLayout.FloorTop - GROUND <= 0.1 + 1e-9)
check("8.0.1: the bay's lines and words a hair over the plot's concrete (GroundTop), not floating at RoadTop", paintOk, table.concat(detail, "; "))
check(`8.0.1: every bollard's foot on the plot's concrete ({bollardsOk} of {2 * #SandboxMap.Plots * 3}: 8.3, from level 3, where the Blender model has its posts)`, bollardsOk == 2 * #SandboxMap.Plots * 3, table.concat(detail, "; "))

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
local counted = #WarehouseLayout.stands(1, 16) == 16 and #WarehouseLayout.stands(1, 99) == ALL and #WarehouseLayout.stands(1, -2) == 0 and #WarehouseLayout.stands(1, 0 / 0) == T.Stands
local s16, l16 = WarehouseLayout.stand(SandboxMap.Plots[1], 16) :: WarehouseLayout.Stand, WarehouseLayout.stands(1, 16)[16]
check("8.1: stands(plot, count): the first `count` (at most the hall's; junk: the start's)", counted and l16.x == s16.x and l16.z == s16.z)

-- 8.3: the levels' API (sites, levelOf, count, capacity, fits, standSize)
do
	local counts, capacities = {}, {}
	for level = 1, WarehouseLayout.Levels do
		table.insert(counts, WarehouseLayout.count(level))
		table.insert(capacities, WarehouseLayout.capacity(level))
	end
	check(`8.3: the levels' big stands 2, 4, 8, 12, 24 and all their stands 2, 4, 8, 20, 32 ({table.concat(counts, ", ")} / {table.concat(capacities, ", ")}); none given: the Big Warehouse's`,
		table.concat(counts, ",") == "2,4,8,12,24" and table.concat(capacities, ",") == "2,4,8,20,32" and WarehouseLayout.count() == 12 and WarehouseLayout.capacity() == 20)
	local base = SandboxMap.Plots[2]
	local site = WarehouseLayout.site(base, 1) :: any
	check("8.3: site(plot, level): a copy at that level (the plot untouched), by plot or id; junk levels: 4; no plot: nil",
		site ~= base and site.level == 1 and site.id == 2 and site.warehouse.sx == 26 and base.warehouse.sx == 80 and (base :: any).level == nil
			and (WarehouseLayout.site(2, 5) :: any).warehouse.sx == 104 and (WarehouseLayout.site(base, 9) :: any).level == 4 and (WarehouseLayout.site(base, 0 / 0) :: any).level == 4
			and (WarehouseLayout.site(base) :: any).level == 4 and WarehouseLayout.site(99, 1) == nil)
	local shedSite = WarehouseLayout.site(1, 1) :: any
local front, backZ = shedSite.warehouse.z + shedSite.warehouse.sz / 2, shedSite.warehouse.z - shedSite.warehouse.sz / 2
check("8.3: ceiling: a gable's walls' top anywhere; a Garage's from its back wall (9.5) up its slope to its front wall (12)",
	WarehouseLayout.ceiling(SandboxMap.Plots[1], -150) == 24 and WarehouseLayout.ceiling(shedSite, backZ) == 9.5 and WarehouseLayout.ceiling(shedSite, front) == 12
		and math.abs(WarehouseLayout.ceiling(shedSite, (front + backZ) / 2) - 10.75) < 1e-9 and WarehouseLayout.ceiling(shedSite, backZ - 50) == 9.5)
check("8.3: levelOf: a site's level, a plain plot's 4", WarehouseLayout.levelOf(site) == 1 and WarehouseLayout.levelOf(base) == 4 and WarehouseLayout.levelOf(WarehouseLayout.site(1, 3) :: any) == 3)
	local same = true
	local plain, four = WarehouseLayout.pieces(base), WarehouseLayout.pieces(WarehouseLayout.site(base, 4) :: any)
	same = #plain == #four
	for i, p in plain do
		local q = four[i]
		same = same and q ~= nil and q.name == p.name and q.at[1] == p.at[1] and q.at[2] == p.at[2] and q.at[3] == p.at[3]
	end
	check("8.3: a plain plot is the Big Warehouse, level 4 (the same building, piece for piece)", same)
	local own = WarehouseLayout.stands(site)
	check("8.3: stands(site): its level's big stands (the Garage's 2), in its building", #own == 2 and own[1].x == (WarehouseLayout.stand(site, 1) :: any).x and #WarehouseLayout.stands(site, 99) == 2)
	local bed, wagon = FurnitureLooks.Items.bed.size, FurnitureLooks.Items.hay_wagon and FurnitureLooks.Items.hay_wagon.size or FurnitureLooks.Items.bed.size
	check("8.3: fits per level: the Garage's 2 and the Logistics Center's 24 big stands take everything, its 25 – 32 small ones not the bed; level 4's 13 small",
		WarehouseLayout.fits(2, wagon, 1) and WarehouseLayout.fits(13, bed, 5) and WarehouseLayout.fits(24, bed, 5) and not WarehouseLayout.fits(25, bed, 5)
			and not WarehouseLayout.fits(13, bed, 4) and not WarehouseLayout.fits(3, bed, 1) and not WarehouseLayout.fits(33, FurnitureLooks.Items.box.size, 5))
	local sx5, sz5 = WarehouseLayout.standSize(25, 5)
	check("8.3: standSize per level (the Logistics Center's 25: a small one; the Garage's 3: none)", sx5 == T.SmallStand[1] and sz5 == T.SmallStand[2] and WarehouseLayout.standSize(3, 1) == nil
		and select(1, WarehouseLayout.standSize(13, 5)) == T.StandSize)
end

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

-- 8.1: the upgrade stands are smaller: WarehouseLayout.fits says which pieces go on them (the big ones take everything)
local misfits: { string } = {}
local bigOk, sizeOk = true, true
for _, id in FurnitureLooks.Order do
	local size = FurnitureLooks.Items[id].size
	bigOk = bigOk and WarehouseLayout.fits(1, size) and WarehouseLayout.fits(T.Stands, size)
	if not WarehouseLayout.fits(ALL, size) then
		table.insert(misfits, id)
		sizeOk = sizeOk and (size.X > T.SmallStand[1] - WarehouseLayout.Fit or size.Z > T.SmallStand[2] - WarehouseLayout.Fit)
	end
end
print(`      the small stands hold {#FurnitureLooks.Order - #misfits} of {#FurnitureLooks.Order} pieces; not: {table.concat(misfits, ", ")}`)
check("8.1: a big stand takes every piece of the catalogue (WarehouseLayout.fits)", bigOk)
check("8.1: a small stand takes at least 9 in 10 of the catalogue, the sofa, the piano and the dining table among them", #misfits * 10 <= #FurnitureLooks.Order and sizeOk
	and WarehouseLayout.fits(T.Stands + 1, FurnitureLooks.Items.sofa.size) and WarehouseLayout.fits(ALL, FurnitureLooks.Items.piano.size) and WarehouseLayout.fits(ALL, FurnitureLooks.Items.dining_table.size), #misfits)
check("8.1: … not the double bed; standSize and fits for no such stand: nil, false; a piece without a size fits", not WarehouseLayout.fits(ALL, FurnitureLooks.Items.bed.size)
	and WarehouseLayout.standSize(0) == nil and WarehouseLayout.standSize(ALL + 1) == nil and not WarehouseLayout.fits(ALL + 1, FurnitureLooks.Items.box.size) and WarehouseLayout.fits(3, {}) and select(1, WarehouseLayout.standSize(ALL)) == T.SmallStand[1])

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
