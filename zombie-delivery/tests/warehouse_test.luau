-- 8.0 SANDBOX, the warehouse (design/sandbox/KONTRAKT.md "warehouse"; shared/WarehouseLayout.luau, which
-- server/Warehouse.luau builds on every plot). 8.3: at every level (Config.WarehouseLevels: the Garage 1 … the Logistics
-- centre 5) on every plot of SandboxMap.Plots:
--   * the level's building: its size and door (the Blender level's, Config's), its door on the plot's door; level 4 is
--     SandboxMap's plot.warehouse (8.0's); each level holds the one before (a player inside it is inside the bigger one)
--   * its display stands (the level's count, 2 … 20), every one inside the walls, never against a side wall, with the
--     level's aisle between any two and in front of each (inside the hall, no other stand on it)
--   * no stand on the receiving zone (the door's width just inside the roller door) or the way in (the door path, from
--     the van's back through the door and the zone to an aisle past it); nothing solid on that way below the door's top
--   * every piece of the sandbox house's catalogue fits every level's stands unturned (the double bed, the sofa, the
--     wardrobe; only Walt's hay wagon wants the big stands from level 3), and stands under the hall's lamps and beams
--   * WarehouseLayout.standAt finds every stand at its middle and its corners, none in the aisles (a round trip)
--   * the guide's spots: WarehouseLayout.stands(plot or id, level) are the level's real stands in stand-number order,
--     SandboxSteps.nearestFree picks one of them
--   * the UPGRADES desk at the back wall's middle, off every stand and the way in, with room to stand at it
--   * the building: within its part budget, unique names, finite sizes, on the plot, over the ground; its lamps; the
--     UNLOAD HERE bay round the van's spot, in front of the door, off the building (every level: it never moves)
--   * 8.0.1: everything outside on the plot's concrete (SandboxMap.GroundTop): the bay's lines and words a hair over it,
--     the bollards' feet on it (from level 3), the hall's floor at most 0.1 over it (no step at the door); the bay
--     centred on the parked van, its words in the room between the van's back and the bay's door end
--   * 8.3, the rebuild: a player caught by the new level's walls, a stand or the desk is moved to a free spot (the
--     receiving zone, itself free); one in an aisle stays
--   * the signs' and the tags' texts
-- Run with tests/run_tests.py.
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxSteps = require("./SandboxSteps")
local WarehouseLayout = require("./WarehouseLayout")
local WarehouseLevels = require("./WarehouseLevels")
local FurnitureLooks = require("./FurnitureLooks")

local T = Config.Warehouse
local LEVELS = Config.WarehouseLevels.List

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
	return a.x0 < b.x1 - 1e-9 and b.x0 < a.x1 - 1e-9 and a.z0 < b.z1 - 1e-9 and b.z0 < a.z1 - 1e-9
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

-- the sandbox house's catalogue (Walt's farm pieces apart) and the whole one
local farm: { [string]: boolean } = {}
for _, id in FurnitureLooks.FarmPieces do
	farm[id] = true
end

check("five levels: the Garage, the Workshop, the Warehouse, the Big warehouse, the Logistics centre", #LEVELS == 5 and WarehouseLevels.Count == 5
	and LEVELS[1].name == "Garage" and LEVELS[2].name == "Workshop" and LEVELS[3].name == "Warehouse" and LEVELS[4].name == "Big warehouse" and LEVELS[5].name == "Logistics centre")
local standsOk = true
for n, def in LEVELS do
	standsOk = standsOk and WarehouseLayout.count(n) == def.stands and def.columns % 2 == 0 and def.stands >= 1
end
check("the stands a level: 2, 4, 8, 12, 20 (WarehouseLayout.count); an even number of columns", standsOk and LEVELS[1].stands == 2 and LEVELS[2].stands == 4
	and LEVELS[3].stands == 8 and LEVELS[4].stands == 12 and LEVELS[5].stands == 20 and WarehouseLayout.most() == 20)
check("a level asked as junk (nil, NaN, a string, 0, 9, 2.7): the start's, clamped, rounded down", WarehouseLayout.level(nil) == 1 and WarehouseLayout.level(0 / 0) == 1
	and WarehouseLayout.level("x") == 1 and WarehouseLayout.level(0) == 1 and WarehouseLayout.level(9) == 5 and WarehouseLayout.level(2.7) == 2 and WarehouseLayout.count(nil) == 2)
check("the plots are the four of SandboxMap", #SandboxMap.Plots == 4, #SandboxMap.Plots)

local GROUND = SandboxMap.GroundTop
local detail: { string } = {}
local function note(text: string)
	if #detail < 12 then
		table.insert(detail, text)
	end
end

for n, def in LEVELS do
	local tag = `level {n} ({def.name})`
	local standsAt, facingOk, topOk, wallsOk, aislesOk, frontOk, zoneOk, pathOk, plotOk = true, true, true, true, true, true, true, true, true
	local roundOk, aisleNil, outsideNil, receivingOk, doorOk, sizeOk = true, true, true, true, true, true
	local deskOk, deskRoomOk, budgetOk, namesOk, finiteOk, groundOk, onPlotOk, solidPathOk, openingOk = true, true, true, true, true, true, true, true, true
	local lampsOk, signsOk, standPartsOk, bayOk, bayMiddleOk, wordsOk, floorOk, paintOk, spotsOk, freeOk = true, true, true, true, true, true, true, true, true, true
	local bollards, worst, wallWorst, most, lampCount, roofOk, neon = 0, math.huge, math.huge, 0, 0, true, 0
	table.clear(detail)
	for _, plot in SandboxMap.Plots do
		local inside = WarehouseLayout.inside(plot, n)
		local zone = WarehouseLayout.receiving(plot, n)
		local path = WarehouseLayout.doorPath(plot, n)
		local door = WarehouseLayout.door(plot, n)
		local outline = WarehouseLayout.outline(plot, n)
		local box = WarehouseLayout.box(plot, n)
		-- the building: the level's size and door, its door on the plot's
		sizeOk = sizeOk and math.abs((outline.x1 - outline.x0) - def.size[1]) < 1e-6 and math.abs((outline.z1 - outline.z0) - def.size[3]) < 1e-6
			and box.sy == def.size[2] and box.sx == def.size[1] and box.sz == def.size[3] and math.abs(box.x - plot.door.x) < 1e-6
			and math.abs(outline.z1 - plot.door.z) < 1e-6 and math.abs(outline.top - (if def.roof == "shed" then def.size[2] else def.size[2] + def.rise)) < 1e-6
			and within(outline :: any, plot.rect)
		doorOk = doorOk and door.width == def.door[1] and door.height == def.door[2] and math.abs(door.z - plot.door.z) < 1e-6 and math.abs(door.x - plot.door.x) < 1e-6
		-- the stands
		local rects: { Rect } = {}
		for i = 1, def.stands do
			local s = WarehouseLayout.stand(plot, i, n)
			if not s then
				standsAt = false
				continue
			end
			local r = rectOf(s)
			rects[i] = r
			standsAt = standsAt and within(r, inside) and s.index == i and s.sx >= def.stand - 1e-9 and s.sz >= def.stand - 1e-9
			facingOk = facingOk and s.yaw == 180
			topOk = topOk and math.abs(s.y - (WarehouseLayout.FloorTop + T.StandHeight)) < 1e-6
			-- never against a side wall (a stud's half at least)
			local side = math.min(r.x0 - inside.x0, inside.x1 - r.x1)
			wallWorst = math.min(wallWorst, side)
			wallsOk = wallsOk and side >= 0.5 - 1e-6
			zoneOk = zoneOk and not overlaps(r, zone)
			pathOk = pathOk and not overlaps(r, path)
			plotOk = plotOk and within(r, plot.rect)
			-- the round trip: the middle and just inside each corner
			local inset = 0.05
			for _, p in { { s.x, s.z }, { r.x0 + inset, r.z0 + inset }, { r.x1 - inset, r.z0 + inset }, { r.x0 + inset, r.z1 - inset }, { r.x1 - inset, r.z1 - inset } } do
				if WarehouseLayout.standAt(plot, p[1], p[2], n) ~= i then
					roundOk = false
					note(`plot {plot.id} stand {i} at {p[1]}, {p[2]}`)
				end
			end
			-- just past its edges (the aisles round it): no stand
			for _, p in { { r.x0 - 1, s.z }, { r.x1 + 1, s.z }, { s.x, r.z0 - 1 }, { s.x, r.z1 + 1 } } do
				if WarehouseLayout.standAt(plot, p[1], p[2], n) ~= nil then
					aisleNil = false
				end
			end
			-- 8.3: a player on it as the warehouse is rebuilt is moved off
			local spot = WarehouseLayout.freeSpot(plot, n, s.x, s.z)
			freeOk = freeOk and spot ~= nil and WarehouseLayout.freeSpot(plot, n, spot.x, spot.z) == nil
				and spot.x > zone.x0 and spot.x < zone.x1 and spot.z > zone.z0 and spot.z < zone.z1
		end
		for i = 1, def.stands do
			for j = i + 1, def.stands do
				local a, b = rects[i], rects[j]
				if a and b then
					local g = gap(a, b)
					worst = math.min(worst, g)
					aislesOk = aislesOk and g >= def.aisle - 1e-6
				end
			end
		end
		-- the side a stand looks at (south: its prompts, its plate): an aisle's depth in front of it, inside the hall, no
		-- other stand on it
		for i = 1, def.stands do
			local r = rects[i]
			if r then
				local strip: Rect = { x0 = r.x0, x1 = r.x1, z0 = r.z1, z1 = r.z1 + def.aisle }
				local clear = within(strip, inside)
				for j = 1, def.stands do
					if j ~= i and rects[j] and overlaps(strip, rects[j]) then
						clear = false
					end
				end
				if not clear then
					frontOk = false
					note(`plot {plot.id} stand {i}: no room in front`)
				end
			end
		end
		standsAt = standsAt and WarehouseLayout.stand(plot, 0, n) == nil and WarehouseLayout.stand(plot, def.stands + 1, n) == nil and WarehouseLayout.stand(plot, 1.5, n) == nil
		-- the UPGRADES desk: against the back wall's middle, facing the hall, off every stand, the zone and the way in, with
		-- an aisle's depth free in front of it
		local desk = WarehouseLayout.terminal(plot, n)
		local deskRect: Rect = { x0 = desk.x - desk.sx / 2, x1 = desk.x + desk.sx / 2, z0 = desk.z - desk.sz / 2, z1 = desk.z + desk.sz / 2 }
		local room: Rect = { x0 = deskRect.x0, x1 = deskRect.x1, z0 = deskRect.z1, z1 = deskRect.z1 + def.aisle }
		deskOk = deskOk and within(deskRect, inside) and math.abs(deskRect.z0 - inside.z0) < 1e-6 and math.abs(desk.x - plot.door.x) < 1e-6 and desk.yaw == 180
			and not overlaps(deskRect, zone) and not overlaps(deskRect, path) and desk.y > WarehouseLayout.FloorTop + 2.5 and desk.y < WarehouseLayout.FloorTop + 4
		deskRoomOk = deskRoomOk and within(room, inside) and not overlaps(room, path)
		for i = 1, def.stands do
			if rects[i] and (overlaps(deskRect, rects[i]) or overlaps(room, rects[i])) then
				deskRoomOk = false
				note(`plot {plot.id}: the desk at stand {i}`)
			end
		end
		freeOk = freeOk and WarehouseLayout.freeSpot(plot, n, desk.x, desk.z) ~= nil and WarehouseLayout.freeSpot(plot, n, desk.x, room.z1 - 0.1) == nil
			and WarehouseLayout.freeSpot(plot, n, outline.x0 + 0.5, (outline.z0 + outline.z1) / 2) ~= nil -- (in a side wall)
			and WarehouseLayout.freeSpot(plot, n, plot.door.x, (zone.z0 + zone.z1) / 2) == nil -- (the receiving zone)
		outsideNil = outsideNil and WarehouseLayout.standAt(plot, door.x, door.z + 3, n) == nil and WarehouseLayout.standAt(plot, (zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2, n) == nil
			and WarehouseLayout.standAt(plot, plot.door.x, outline.z0 - 1, n) == nil
		-- the receiving zone: the door's width, just inside the door, the level's depth
		receivingOk = receivingOk
			and math.abs((zone.x1 - zone.x0) - def.door[1]) < 1e-6
			and math.abs(zone.z1 - inside.z1) < 1e-6
			and math.abs((zone.z1 - zone.z0) - def.receiving) < 1e-6
			and within(zone, inside)
		-- the guide's spots (client/SandboxGuide.luau: WarehouseLayout.stands with the player's level)
		local byPlot, byId = WarehouseLayout.stands(plot, n), WarehouseLayout.stands(plot.id, n)
		spotsOk = spotsOk and #byPlot == def.stands and #byId == def.stands
		local taken: { [number]: boolean } = {}
		for i = 1, def.stands do
			local s = WarehouseLayout.stand(plot, i, n) :: WarehouseLayout.Stand
			local a, b = byPlot[i], byId[i]
			spotsOk = spotsOk and a and b and a.x == s.x and a.y == s.y and a.z == s.z and b.x == s.x and b.z == s.z
				and a.x > inside.x0 and a.x < inside.x1 and a.z > inside.z0 and a.z < inside.z1
			taken[i] = i < def.stands -- (every stand but the last one taken)
		end
		local nearest = SandboxSteps.nearestFree(plot.door.x, plot.door.z, byId, {})
		local last = SandboxSteps.nearestFree(plot.door.x, plot.door.z, byId, taken)
		spotsOk = spotsOk and nearest ~= nil and nearest >= 1 and nearest <= def.stands and last == def.stands

		-- the building
		local pieces = WarehouseLayout.pieces(plot, n)
		most = math.max(most, #pieces)
		budgetOk = budgetOk and #pieces <= T.MaxParts
		local names: { [string]: any } = {}
		local lamps, standParts = 0, 0
		neon = 0
		-- the opening clear up to here (a rolled roller door's curtain and bar hang in its top; a garage's panel lies over it)
		local clearTo = math.min(14, if def.roof == "shed" then door.height else door.height - 1.95)
		for _, p in pieces do
			if names[p.name] then
				namesOk = false
				note(`duplicate {p.name}`)
			end
			names[p.name] = p
			for k = 1, 3 do
				finiteOk = finiteOk and finite(p.size[k]) and finite(p.at[k]) and p.size[k] > 0
			end
			local x0, x1, y0, y1, z0, z1 = WarehouseLayout.bounds(p)
			if y0 < -0.01 then
				groundOk = false
				note(`{p.name} below the ground ({y0})`)
			end
			if not within({ x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, plot.rect) then
				onPlotOk = false
				note(`{p.name} off the plot`)
			end
			-- nothing solid on the way in (above the floor, under the door's top), the floor itself apart (a roof's box is a
			-- sloped slab's: its middle over the walls' tops instead, below)
			if p.group == "roof" then
				roofOk = roofOk and (p.at[2] > door.height or not overlaps({ x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, path))
			elseif p.solid and p.name ~= "Floor" and y1 > WarehouseLayout.FloorTop + 0.05 and y0 < door.height and overlaps({ x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, path) then
				solidPathOk = false
				note(`{p.name} solid on the way in`)
			end
			-- the door's opening itself: nothing under clearTo across it (a carried wardrobe, a tall player)
			if p.group ~= "roof" and y1 > GROUND + 0.1 and y0 < clearTo and x1 > door.x - door.width / 2 + 0.01 and x0 < door.x + door.width / 2 - 0.01 and z1 > door.z - 1.5 and z0 < door.z + 0.5 and p.group ~= "paint" and p.name ~= "Floor" then
				openingOk = false
				note(`{p.name} in the door's opening`)
			end
			if p.light then
				lamps += 1
				-- (8.3 review, the owner's "flashbang": the lights' brightness and reach are Config's, nothing brighter)
				lampsOk = lampsOk and p.light.brightness == T.Lamp.Brightness and p.light.range == T.Lamp.Range and p.light.color == T.Lamp.Color
			end
			if p.material == "Neon" then
				neon += 1
			end
			-- 8.0.1: on the plot's concrete (GroundTop), not the asphalt's RoadTop
			if p.name == "Floor" then
				floorOk = floorOk and math.abs(y0 - GROUND) < 1e-6 and math.abs(y1 - WarehouseLayout.FloorTop) < 1e-6
			elseif p.group == "bay" then
				-- (the words' part lies flat: its face up at y1)
				if not (y0 > GROUND and y0 <= GROUND + 0.05 and y1 <= GROUND + 0.1) then
					paintOk = false
					note(`{p.name} at {y0} … {y1}`)
				end
			elseif string.sub(p.name, 1, 7) == "Bollard" then
				if math.abs(y0 - GROUND) < 1e-6 and y1 > GROUND + 3 then
					bollards += 1
				else
					note(`{p.name}'s foot at {y0}`)
				end
			end
			if p.stand then
				standParts += 1
			end
		end
		lampCount = lamps
		-- about the light a square stud of level 4 has (6 lamps on 80 × 60), not more: a bigger hall is no brighter
		local perArea = (lamps / (def.size[1] * def.size[3])) / (6 / (80 * 60))
		lampsOk = lampsOk and lamps >= 1 and neon == lamps and (n == 1 or (perArea >= 0.6 and perArea <= 1.4))
		standPartsOk = standPartsOk and standParts == 3 * def.stands
		for _, name in { "ZdcSign", "OwnerSign", "StockBoard", "Floor", "Header", "WallBack", "WallWest", "WallEast", "WallFrontWest", "WallFrontEast", "ReceivingText", "BayText", "TerminalDesk", "TerminalTop", "TerminalScreen", "UpgradeSign" } do
			if names[name] == nil then
				signsOk = false
				note(`no {name}`)
			end
		end
		local roofs = 0
		for name in names do
			roofs += if string.match(name, "^Roof%a+%d*$") then 1 else 0
		end
		signsOk = signsOk and roofs >= 2 and (def.roof == "shed" or names.DoorCurtain ~= nil) and (def.roof ~= "shed" or names.DoorPanel ~= nil)
		for i = 1, def.stands do
			signsOk = signsOk and names[`Stand{i}`] ~= nil and names[`Plate{i}`] ~= nil and names[`StandTop{i}`] ~= nil
		end
		signsOk = signsOk and names[`Stand{def.stands + 1}`] == nil
		deskOk = deskOk and names.TerminalDesk.solid == true and names.TerminalDesk.group == "terminal" and names.TerminalScreen.words ~= nil
		-- the walls: as high as the level's (a shed's back and sides its back wall's), the floor's paint and the signs in
		-- the hall under the roof
		local back = if def.roof == "shed" then def.size[2] - def.rise else def.size[2]
		local _, _, _, wallTop = WarehouseLayout.bounds(names.WallBack)
		local _, _, _, frontTop = WarehouseLayout.bounds(names.WallFrontWest)
		local _, _, _, boardTop = WarehouseLayout.bounds(names.StockBoard)
		signsOk = signsOk and math.abs(wallTop - back) < 1e-6 and math.abs(frontTop - def.size[2]) < 1e-6 and boardTop < back - 0.1
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
		local x0, x1, _, _, z0, z1 = WarehouseLayout.bounds(names.BayText)
		wordsOk = wordsOk and z0 >= bay.z0 + 0.5 - 1e-6 and z1 <= van.z0 + 1e-6 and z1 - z0 >= 2 and x0 >= bay.x0 and x1 <= bay.x1
	end
	check(`{tag}: {def.size[1]} × {def.size[2]} × {def.size[3]}, its door {def.door[1]} × {def.door[2]} on the plot's door, on the plot`, sizeOk and doorOk)
	check(`{tag}: its {def.stands} stands inside the building, looking south, their top at the floor + {T.StandHeight}, never against a side wall (the least: {wallWorst})`, standsAt and facingOk and topOk and wallsOk, table.concat(detail, "; "))
	check(`{tag}: aisles of at least {def.aisle} studs between any two stands (the least: {worst}) and in front of each`, aislesOk and frontOk, table.concat(detail, "; "))
	check(`{tag}: no stand on the receiving zone or the way in; every stand on its plot`, zoneOk and pathOk and plotOk)
	check(`{tag}: the receiving zone the door's width, just inside it, {def.receiving} deep`, receivingOk)
	check(`{tag}: standAt round-trips; nothing in the aisles, at the door, in the zone or behind the building`, roundOk and aisleNil and outsideNil, table.concat(detail, "; "))
	check(`{tag}: the guide's spots (stands(plot or id, level)) are its stands; nearestFree picks one`, spotsOk)
	check(`{tag}: the UPGRADES desk at the back wall's middle, facing the hall, counter height, its body solid; no stand on it and an aisle free in front of it`, deskOk and deskRoomOk, table.concat(detail, "; "))
	check(`{tag}: within the part budget ({most} of {T.MaxParts}); unique names, finite sizes, on the plot, none under the ground`, budgetOk and namesOk and finiteOk and onPlotOk and groundOk, table.concat(detail, "; "))
	check(`{tag}: nothing solid on the way in; the door's opening clear under min(14, its top less a rolled door's)`, solidPathOk and openingOk and roofOk, table.concat(detail, "; "))
	check(`{tag}: {lampCount} lamps (PointLights: Config's brightness, a Neon glow each, about level 4's light a square stud); the signs, the desk, the walls (the back {if def.roof == "shed" then "lower: the shed's" else "as high"}) and every stand's podium, top and plate`, lampsOk and signsOk and standPartsOk, table.concat(detail, "; "))
	check(`{tag}: the UNLOAD HERE bay round the van's spot and the unload circle, centred on the parked Sprinter, its words before the van's back`, bayOk and bayMiddleOk and wordsOk)
	check(`{tag}: the hall's floor from the plot's concrete to FloorTop; the bay's paint a hair over it; {bollards} bollards with their feet on it`, floorOk and paintOk and bollards == (if n >= 3 then 2 * #SandboxMap.Plots else 0), table.concat(detail, "; "))
	check(`{tag}: 8.3, the rebuild: a player on a stand, at the desk or in a wall is moved to the receiving zone (free); in an aisle or the zone they stay`, freeOk)
end

-- ── The levels together ──────────────────────────────────────────────────────
local holdsOk, growsOk = true, true
for _, plot in SandboxMap.Plots do
	for n = 2, #LEVELS do
		local a, b = WarehouseLayout.inside(plot, n - 1), WarehouseLayout.inside(plot, n)
		local oa, ob = WarehouseLayout.outline(plot, n - 1), WarehouseLayout.outline(plot, n)
		holdsOk = holdsOk and within(a, b) and ob.z1 == oa.z1 and ob.x0 < oa.x0 and ob.x1 > oa.x1 and ob.z0 < oa.z0
		growsOk = growsOk and LEVELS[n].stands > LEVELS[n - 1].stands and LEVELS[n].door[1] >= LEVELS[n - 1].door[1] and LEVELS[n].price > LEVELS[n - 1].price
	end
end
check("8.3: each level holds the one before (its floor inside the bigger one's, the same front wall): growing never traps anybody", holdsOk)
check("8.3: each level more stands, as wide a door at least, dearer", growsOk)
local four = WarehouseLayout.box(SandboxMap.Plots[3], 4)
local w3 = SandboxMap.Plots[3].warehouse
check("level 4 is 8.0's warehouse (SandboxMap's plot.warehouse)", four.x == w3.x and four.z == w3.z and four.sx == w3.sx and four.sy == w3.sy and four.sz == w3.sz)
check("stands(): {} for no plot; no level asked: the start's", #WarehouseLayout.stands(99, 3) == 0 and #WarehouseLayout.stands(1) == LEVELS[1].stands)

-- every piece of the catalogue fits a stand (unturned: it looks south) and stands under the hall's lamps and beams
local fitsAll, fitsBig, tallest, misfits = true, true, 0, {}
for _, id in FurnitureLooks.Order do
	local size = FurnitureLooks.Items[id].size
	tallest = math.max(tallest, size.Y)
	for n, def in LEVELS do
		local fits = WarehouseLayout.fits(1, size, n) and WarehouseLayout.fits(def.stands, size, n)
		if not fits then
			if farm[id] then
				table.insert(misfits, `{id}@{n}`)
			else
				fitsAll = false
			end
		end
		if def.stand >= 10 then
			fitsBig = fitsBig and fits
		end
	end
end
print(`      not on every level's stands: {table.concat(misfits, ", ")}`)
check("every piece of the sandbox house's catalogue fits every level's stands unturned (the bed 5.4 × 7.4, the sofa 7.2)", fitsAll)
check("the big stands (10: from level 3) take every piece of the catalogue, Walt's hay wagon (6.4 × 9.6) too", fitsBig and LEVELS[3].stand == 10 and LEVELS[5].stand == 10)
local pairsFit = true
for _, id in { "alphorn", "trex_skull", "zombie_safe" } do
	local def = FurnitureLooks.Items[id]
	pairsFit = pairsFit and def ~= nil and def.class == "pair" and def.rarity ~= nil
	for n in LEVELS do
		pairsFit = pairsFit and def ~= nil and WarehouseLayout.fits(1, def.size, n) and WarehouseLayout.fits(LEVELS[n].stands, def.size, n)
	end
end
check("8.3: the two-person collectibles (the alphorn 7.2 × 1.4, the T. rex skull, the safe) stand on every level's stands, the Garage's 8 too", pairsFit)
local headOk = true
for n in LEVELS do
	headOk = headOk and WarehouseLayout.FloorTop + T.StandHeight + tallest < WarehouseLayout.headroom(n) - 0.2
end
check(`the tallest piece on a stand stays under every level's lamps and beams ({tallest} studs; the garage's headroom {WarehouseLayout.headroom(1)})`, headOk, tallest)
check("fits: no such stand: false; a piece without a size fits; standSize per level", not WarehouseLayout.fits(3, FurnitureLooks.Items.box.size, 1)
	and WarehouseLayout.fits(3, {}, 3) and WarehouseLayout.standSize(0, 4) == nil and WarehouseLayout.standSize(21, 5) == nil
	and select(1, WarehouseLayout.standSize(2, 1)) == LEVELS[1].stand and select(1, WarehouseLayout.standSize(20, 5)) == 10)

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
check("the desk's monitor names the warehouse track", WarehouseLayout.terminalLines()[2].text == "Warehouse · Lights · Van · Danny")

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
