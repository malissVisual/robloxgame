-- 7.0, the moves' world (shared/MoveSiteLooks.luau, Config.MoveSites; server/MoveSites.luau builds it): sound pieces,
-- the part and light budget; at the depot's checkpoint nothing in the truck's lane in from Bone St (under the gantry's
-- sign), nothing on the road, the depot's own spots kept clear (the spawn, the scooter rack and its way out, the supply
-- drop's pad, the board, the gear stall, the hall), the people's walk line round the depot's block clear (Traffic's
-- survey and walkers); the kiosk's corkboard where Moving's reach expects it; a house's dress-up never solid, never on
-- the path from its door to the truck's kerb, the walk line or the mailbox, its cones on the road; the banner between
-- the hall's boards over its door; the evacuation spots on their kerbs, clear of the street props, the doors, piles and
-- parks and the people's walk line. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local StreetProps = require("./StreetProps")
local TrafficLanes = require("./TrafficLanes")
local Looks = require("./MoveSiteLooks")

-- The people's walk line round every block (TrafficLanes.SidewalkInset in from the curb): server/Traffic.luau's survey
-- finds it clear of anything solid a body wide (Body) between PROBE_LOW and PROBE_HIGH (1 … 5.5 over the walk), and the
-- people walk it. Nothing of the moves' world below 5.5 may stand on it (they would walk into it, or the side closes).
local INSET, BODY = TrafficLanes.SidewalkInset, TrafficLanes.Body + 0.2

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local t = Config.MoveSites
local sets = Looks.all()
local byId: { [string]: Looks.Set } = {}
for _, set in sets do
	byId[set.id] = set
end
check("every set: the checkpoint, the kiosk, the banner, Marge's house, the evacuation spots",
	byId.checkpoint ~= nil and byId.board ~= nil and byId.banner ~= nil and byId.house_marge ~= nil and #Looks.spotPlaces() == #t.Spots and #t.Spots >= 2)

-- 8.0.1, the plots' kiosks (MoveSiteLooks.board(true), server/MoveSites.luau plotBoard): the same kiosk, its corkboard
-- the sandbox's (8.3: the lodge, bring it home to your warehouse), nothing of the city's story on it; the depot's unchanged.
local function wordsOf(pieces: { Looks.Piece }): { [string]: string }
	local out = {}
	for _, p in pieces do
		local lines = {}
		for _, w in p.words or {} do
			for _, l in w.lines do
				table.insert(lines, l.text)
			end
		end
		out[p.name] = table.concat(lines, " / ")
	end
	return out
end
local city, plot = Looks.board(), Looks.board(true)
local cityText, plotText = wordsOf(city), wordsOf(plot)
local all: { string } = {}
local names: { [string]: boolean } = {}
local twice = false
for _, text in plotText do
	table.insert(all, text)
end
for _, p in plot do
	twice = twice or names[p.name] == true
	names[p.name] = true
end
local plotAll = table.concat(all, " | ")
local sameKiosk = true
for _, p in city do
	if not string.find(p.name, "^Photo") and not string.find(p.name, "^Flyer") and p.name ~= "Logo" then
		local mine = nil
		for _, q in plot do
			if q.name == p.name then
				mine = q
			end
		end
		sameKiosk = sameKiosk and mine ~= nil and mine.size[1] == p.size[1] and mine.at[2] == p.at[2] and mine.solid == p.solid
	end
end
check("8.0.1: the plots' kiosk: as many pieces as the depot's, unique names, the same kiosk round the corkboard (the Board solid where it was)",
	#plot == #city and not twice and sameKiosk, `{#plot} / {#city}`)
check("8.0.1: …its corkboard says THE ALPINE LODGE (8.3) and \"Bring it home to your warehouse.\"", string.find(plotAll, "THE ALPINE LODGE", 1, true) ~= nil
	and string.find(plotAll, "Bring it home to your warehouse.", 1, true) ~= nil, plotAll)
check("8.0.1: …no Marge, no Walt, no Wall, no evacuation", string.find(plotAll, "MARGE", 1, true) == nil and string.find(plotAll, "WALT", 1, true) == nil
	and string.find(plotAll, "Wall", 1, true) == nil and string.find(string.upper(plotAll), "EVACUAT", 1, true) == nil, plotAll)
check("8.0.1: the depot's kiosk unchanged (Marge's photo, Go to the Wall, ZDC MOVING & EVACUATION)", cityText.PhotoMarge ~= nil
	and string.find(cityText.FlyerEvac, "Go to the Wall", 1, true) ~= nil and string.find(cityText.Header, "EVACUATION", 1, true) ~= nil)

-- Sound pieces --------------------------------------------------------------------------------------------------------

local function finite(list: { number }, count: number): boolean
	if #list ~= count then
		return false
	end
	for _, n in list do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

local total, lights = 0, 0
local bad: { string } = {}
for _, set in sets do
	local names: { [string]: boolean } = {}
	for _, p in set.pieces do
		total += 1
		local where = `{set.id}.{p.name}`
		if names[p.name] then
			table.insert(bad, where .. " twice")
		end
		names[p.name] = true
		if not finite(p.size, 3) or not finite(p.at, 3) or not finite(p.color, 3) then
			table.insert(bad, where .. " numbers")
		end
		for _, n in p.size do
			if n < 0.04 or n > 64 then
				table.insert(bad, where .. " size")
			end
		end
		for _, n in p.color do
			if n < 0 or n > 255 then
				table.insert(bad, where .. " colour")
			end
		end
		if not table.find(Looks.Materials, p.material) then
			table.insert(bad, where .. " material " .. p.material)
		end
		if p.shape and not table.find(Looks.Shapes, p.shape) then
			table.insert(bad, where .. " shape")
		end
		if p.shape == "Cylinder" and math.abs(p.size[2] - p.size[3]) > 1e-9 then
			table.insert(bad, where .. " an oval cylinder")
		end
		if p.light then
			lights += 1
		end
		for _, w in p.words or {} do
			local share = 0
			for _, l in w.lines do
				share += l.size
				if l.text == "" or not finite(l.color, 3) then
					table.insert(bad, where .. " a line")
				end
			end
			if not table.find(Looks.Faces, w.face) or share > 1 or #w.lines == 0 then
				table.insert(bad, where .. " words on " .. w.face)
			end
		end
	end
end
check("sound pieces: unique names, finite sizes and colours, known materials, round cylinders, text that fits", #bad == 0, table.concat(bad, ", "))
check(`the part budget: {total} parts (Config.MoveSites.Budget {t.Budget})`, total <= t.Budget and total > 0, total)
check(`the lights: {lights} (at most {t.Lights})`, lights <= t.Lights, lights)
check("the shadows: the big pieces only (a wall panel does, a cone does not)", (function(): boolean
	local cp = byId.checkpoint
	local wall, cone
	for _, p in cp.pieces do
		if p.name == "WallE1" then
			wall = Looks.shadow(p, Map.WalkTop)
		end
	end
	for _, p in byId.house_marge.pieces do
		if p.name == "Cone1" then
			cone = Looks.shadow(p, Map.WalkTop)
		end
	end
	return wall == true and cone == false
end)())

-- The checkpoint -------------------------------------------------------------------------------------------------------

local cp = byId.checkpoint
local dx, dz = Map.Depot.x, Map.Depot.z
local drop = Config.Moving.DropOff
check("the checkpoint stands round Moving's drop-off", cp.place.x == dx + drop[1] and cp.place.z == dz + drop[2] and cp.place.yaw == 0)
local w, d = t.Bay[1], t.Bay[2]
-- Depot boxes (studs from the depot's middle: x0, x1, z0, z1) the checkpoint keeps out of.
local keep: { [string]: { number } } = {
	["the spawn pad"] = { -7, 7, 19, 33 },
	["the scooter rack and its way out to Bone St"] = { -10.5, 10.5, 40, 56 }, -- (its slots ±8.5, a scooter ±0.75)
	["the supply drop's pad"] = { 24 - 12, 24 + 12, 10 - 12, 10 + 12 },
	["the Moving contracts kiosk"] = { Config.Moving.Board[1] - 3, Config.Moving.Board[1] + 3, Config.Moving.Board[2] - 5, Config.Moving.Board[2] + 5 },
	["the gear stall"] = { Config.GearStall.X - 6, Config.GearStall.X + 6, Config.GearStall.Z - 15, Config.GearStall.Z + 15 },
	["the hall"] = { -42, 42, -50, -4 },
}
local inLane, onRoad, solidLow = {}, {}, 0
local hits: { string } = {}
local paint = 0
for _, p in cp.pieces do
	local x0, x1, y0, y1, z0, z1 = Looks.box(cp.place, p)
	local lx0, lx1, lz0, lz1 = x0 - cp.place.x, x1 - cp.place.x, z0 - cp.place.z, z1 - cp.place.z
	local ly0, ly1 = y0 - cp.place.y, y1 - cp.place.y
	-- the lane: the bay and the kerb in front of it out to the road, up to under the gantry's sign
	if lx1 > -w / 2 - 0.5 and lx0 < w / 2 + 0.5 and lz1 > -d / 2 - 0.5 and lz0 < d / 2 + 4 then
		if ly1 <= 0.2 then
			paint += 1
		elseif ly0 < t.Clear - 0.4 then
			table.insert(inLane, p.name)
		end
	end
	if x1 > dx + Map.BlockSize / 2 + 0.01 or z1 > dz + Map.BlockSize / 2 + 0.01 or x0 < dx - Map.BlockSize / 2 or z0 < dz - Map.BlockSize / 2 then
		table.insert(onRoad, p.name)
	end
	for what, b in keep do
		if x1 - dx > b[1] and x0 - dx < b[2] and z1 - dz > b[3] and z0 - dz < b[4] then
			table.insert(hits, `{p.name} in {what}`)
		end
	end
	if p.solid and ly0 < 0.5 then
		solidLow += 1
	end
	if p.name == "CheckpointSign" then
		check("the gantry's sign hangs at Clear over the walk, both faces saying SAFE ZONE — EVACUATION CHECKPOINT",
			math.abs(ly0 - t.Clear) < 1e-6 and p.words ~= nil and #p.words == 2 and p.words[1].lines[1].text == "SAFE ZONE — EVACUATION CHECKPOINT"
				and p.words[2].lines[1].text == p.words[1].lines[1].text)
	end
end
check("nothing in the truck's lane in from Bone St below the gantry's sign (the bay, its kerb)", #inLane == 0, table.concat(inLane, ", "))
check("the bay is painted on the yard (its outline, the chevrons, the stop bar)", paint >= 9, paint)
check("nothing of the checkpoint on the road (inside the depot's block)", #onRoad == 0, table.concat(onRoad, ", "))
check("the depot's own spots stay clear (the spawn, the scooters, the supply pad, the kiosk, the stall, the hall)", #hits == 0, table.concat(hits, ", "))
check("the Wall stands: solid footings, posts, the booth, sandbags, a jersey barrier", solidLow >= 15, solidLow)
-- The depot block's walk lines (its south side along Bone St, its east side) under the checkpoint and the kiosk.
local ring = Map.BlockSize / 2 - INSET
local walkers: { string } = {}
for _, set in { cp, byId.board } do
	for _, p in set.pieces do
		local x0, x1, y0, y1, z0, z1 = Looks.box(set.place, p)
		if y1 > Map.WalkTop + 1 and y0 < Map.WalkTop + 5.5 then
			local x0d, x1d, z0d, z1d = x0 - dx, x1 - dx, z0 - dz, z1 - dz
			local along = function(a0: number, a1: number): boolean
				return a1 > -ring - BODY and a0 < ring + BODY
			end
			for _, k in { -1, 1 } do
				if (z1d > k * ring - BODY and z0d < k * ring + BODY and along(x0d, x1d)) or (x1d > k * ring - BODY and x0d < k * ring + BODY and along(z0d, z1d)) then
					table.insert(walkers, `{set.id}.{p.name}`)
				end
			end
		end
	end
end
check("the people's walk line round the depot's block stays clear (the checkpoint, the kiosk)", #walkers == 0, table.concat(walkers, ", "))
-- The gate: between the gantry's posts at least the truck's width with room each side.
local posts: { number } = {}
for _, p in cp.pieces do
	if string.sub(p.name, 1, 10) == "GantryPost" then
		local x0, x1 = Looks.box(cp.place, p)
		table.insert(posts, if x0 < cp.place.x then x1 else x0)
	end
end
check("the gate is wide open: 2 posts outside the bay", #posts == 2 and math.abs(posts[2] - posts[1]) >= w + 2, #posts)

-- The kiosk ------------------------------------------------------------------------------------------------------------

local kiosk = byId.board
local board: Looks.Piece? = nil
for _, p in kiosk.pieces do
	if p.name == "Board" then
		board = p
	end
end
check("the kiosk's corkboard (Moving's prompt hangs on it) is solid", board ~= nil and board.solid == true)
if board then
	local x0, x1, y0, y1, z0, z1 = Looks.box(kiosk.place, board)
	local bx, bz = dx + Config.Moving.Board[1], dz + Config.Moving.Board[2]
	local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
	check("…within a stud of Config.Moving.Board (Moving's reach rules hold), at a hand's height, facing the yard",
		math.sqrt((mx - bx) ^ 2 + (mz - bz) ^ 2) < 1 and (y0 + y1) / 2 - Map.WalkTop > 3.5 and (y0 + y1) / 2 - Map.WalkTop < 6.5 and kiosk.place.yaw == 90)
end
local front = {}
for _, p in kiosk.pieces do
	local x0 = Looks.box(kiosk.place, p)
	if p.solid and x0 < dx + Config.Moving.Board[1] - 1.5 then
		table.insert(front, p.name)
	end
end
check("nothing solid stands in front of the kiosk (the yard side)", #front == 0, table.concat(front, ", "))

-- The houses ------------------------------------------------------------------------------------------------------------

for _, contract in Config.Moving.Contracts do
	if contract.kind ~= "house" then
		continue -- (7.x farm move: a farm's site is checked below)
	end
	local set = byId["house_" .. contract.id]
	local home = Map.home(contract.home or "")
	if not set or not home then
		check(`{contract.id}: its house on the map`, false)
		continue
	end
	local park = Looks.parkDepth(home)
	local district, i, j = Map.blockAt(home.door.x, home.door.z)
	local curb = math.huge
	if district then
		local cx, cz = district.ox + i * Map.Cell, district.oz + j * Map.Cell
		curb = Map.BlockSize / 2 - ((home.door.x - cx) * home.facing.x + (home.door.z - cz) * home.facing.z)
	end
	local origin: Looks.Place = { x = 0, y = 0, z = 0, yaw = 0 } -- (the door's own frame)
	local solid, path, mailbox, cones, inLot = {}, {}, {}, 0, {}
	for _, p in set.pieces do
		local x0, x1, y0, y1, z0, z1 = Looks.box(origin, p)
		if p.solid then
			table.insert(solid, p.name)
		end
		-- the path: the door's width with room, from the doorstep out to the truck's spot, a body's height
		if x1 > -2.4 and x0 < 2.4 and z0 < 0 and z1 > -park and y0 < 7.5 and y1 > Map.RoadTop - Map.WalkTop + 0.2 then
			table.insert(path, p.name)
		end
		-- World's mailbox (3 right of the path, 2.5 off the lot's front)
		local yard = 25 - Map.HouseFront -- (a Suburbs house's lot is 50)
		if x1 > 2.2 and x0 < 3.8 and z1 > -(yard - 2.5) - 0.9 and z0 < -(yard - 2.5) + 0.9 and y0 < 4.2 then
			table.insert(mailbox, p.name)
		end
		if string.sub(p.name, 1, 4) == "Cone" and z1 < -(curb + Map.CurbRun) then
			cones += 1
		end
		if math.abs(x0) > 24 or math.abs(x1) > 24 then
			table.insert(inLot, p.name)
		end
		-- the block's walk line in front of the house (curb − INSET from the door)
		if z1 > -(curb - INSET) - BODY and z0 < -(curb - INSET) + BODY and y1 > 1 and y0 < 5.5 then
			table.insert(path, p.name .. " (on the people's walk line)")
		end
	end
	check(`{contract.id}: nothing of the dress-up is solid (the crew carries sofas past it)`, #solid == 0, table.concat(solid, ", "))
	check(`{contract.id}: nothing on the path from the door to the truck's kerb ({math.floor(park)} studs)`, #path == 0, table.concat(path, ", "))
	check(`{contract.id}: the mailbox stays clear`, #mailbox == 0, table.concat(mailbox, ", "))
	check(`{contract.id}: all 12 cone parts on the road past the kerb`, cones == 12, cones)
	check(`{contract.id}: within its lot along the street`, #inLot == 0, table.concat(inLot, ", "))
	local sign = false
	for _, p in set.pieces do
		if p.name == "YardSign" and p.words then
			sign = p.words[1].lines[1].text == "ZDC MOVING" and p.words[1].lines[2].text == string.upper(contract.name)
		end
	end
	check(`{contract.id}: the yard sign says ZDC MOVING · {string.upper(contract.name)}`, sign)
end

-- The banner ------------------------------------------------------------------------------------------------------------

local banner = byId.banner
for _, p in banner.pieces do
	if p.name == "Banner" then
		local x0, x1, y0, y1 = Looks.box(banner.place, p)
		-- the hall's front: open 72 wide and 14 tall, its canopy's underside at 19.3, DISPATCH / FLEET from |x| 19.5
		check("the banner hangs over the hall's door (above 14), under its canopy, between its DISPATCH and FLEET boards",
			y0 - Map.WalkTop >= 14 and y1 - Map.WalkTop + t.Banner.Hang <= 19.3 + 1e-6 and x0 - dx > -19 and x1 - dx < 19)
	end
end

-- 7.x farm move: Walt's farm at the Old Farm (Config.Moving.Sites.farm, MoveSiteLooks.farm) -------------------------------

do
	local contract: any = nil
	for _, c in Config.Moving.Contracts do
		if c.kind == "farm" then
			contract = c
		end
	end
	local set = contract and byId["farm_" .. contract.id]
	local place = contract and Looks.sitePlace(contract.place)
	local doors = contract and Looks.siteDoors(contract.kind, contract.place)
	check("the farm's set at its Map.Places place (its point, its frame)", set ~= nil and place ~= nil and doors ~= nil and #doors == 2 and (function(): boolean
		for _, p in Map.Places do
			if p.id == contract.place then
				return p.x == place.x and p.z == place.z and place.yaw == 0 and place.y == Map.RoadTop
			end
		end
		return false
	end)())
	if set and place and doors then
		local site = Config.Moving.Sites.farm
		local yard: Map.Area? = nil
		for _, y in Map.Yards do
			if y.id == contract.place then
				yard = y
			end
		end
		-- the World farm's own things round the place (its literal layout: the barn, the silo) and its Map data
		local spot = Map.CargoSpots[contract.place]
		local secret: Map.Secret? = nil
		for _, s in Map.Secrets do
			if s.id == "secret_" .. contract.place then
				secret = s
			end
		end
		local board = Map.EmployerSpots[contract.place]
		local solid, paths, keeps, outside = {}, {}, {}, {}
		local porch = Config.MoveGreeters.Porch
		for _, p in set.pieces do
			local x0, x1, y0, y1, z0, z1 = Looks.box(place, p)
			if p.solid and p.name ~= "FarmhouseBody" then
				table.insert(solid, p.name)
			end
			if yard and (x0 < yard.x0 or x1 > yard.x1 or z0 < yard.z0 or z1 > yard.z1) then
				table.insert(outside, p.name)
			end
			local low = y0 < place.y + 7.5
			for n, d in doors do
				-- the way out of the door to the van's spot (the door's width with room), and the van there (7.4 × 17)
				local corners = {}
				for _, x in { x0, x1 } do
					for _, z in { z0, z1 } do
						table.insert(corners, { (x - d.x) * d.fx + (z - d.z) * d.fz, (x - d.x) * -d.fz + (z - d.z) * d.fx })
					end
				end
				local out0, out1, side0, side1 = math.huge, -math.huge, math.huge, -math.huge
				for _, c in corners do
					out0, out1 = math.min(out0, c[1]), math.max(out1, c[1])
					side0, side1 = math.min(side0, c[2]), math.max(side1, c[2])
				end
				local half = d.width / 2 + 0.4
				if low and out1 > 0.6 and out0 < site.Curb - 8.5 and side1 > -half and side0 < half then
					table.insert(paths, `{p.name} on door {n}'s way out`)
				end
				if low and out1 > site.Curb - 8.5 and out0 < site.Curb + 8.5 and side1 > -4 and side0 < 4 then
					table.insert(paths, `{p.name} on door {n}'s van spot`)
				end
				-- Walt's spot by the front door (Config.MoveGreeters.Porch in its frame: right of it, out of it)
				local px, pz = porch[1], -porch[2] -- (server/MoveGreeters.luau porchSpot: right × Porch[1], out × -Porch[2])
				if n == 1 and low and side1 > px - 1.2 and side0 < px + 1.2 and out1 > pz - 1.2 and out0 < pz + 1.2 then
					table.insert(paths, `{p.name} on Walt's spot`)
				end
			end
			local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
			local reach = math.max(x1 - x0, z1 - z0) / 2
			local function near(x: number, z: number, r: number): boolean
				return math.abs(mx - x) < reach + r and math.abs(mz - z) < reach + r
			end
			if spot and (near(spot.park.x, spot.park.z, 8) or near(spot.pile.x, spot.pile.z, 6)) then
				table.insert(keeps, `{p.name} by the Farm Run's cargo spot`)
			end
			if secret and near(secret.x, secret.z, 3) then
				table.insert(keeps, `{p.name} by the lost package`)
			end
			if board and near(board.x, board.z, 8) then
				table.insert(keeps, `{p.name} by the WORK HERE board`)
			end
			-- World's barn (40 × 30 round the place + (-60, -80)) and silo (r 7 round + (-20, -90)) at the raw frame
			local bx, bz = Looks.toWorld(place, -60, -80)
			local sx, sz = Looks.toWorld(place, -20, -90)
			if math.abs(mx - bx) < 20 + reach - 0.3 and math.abs(mz - bz) < 15 + reach - 0.3 then
				table.insert(keeps, `{p.name} in the barn`)
			end
			if near(sx, sz, 7) then
				table.insert(keeps, `{p.name} on the silo`)
			end
		end
		check("the farm: only the farmhouse's body is solid (the dress never)", #solid == 0, table.concat(solid, ", "))
		check("the farm: nothing on a door's way out to its van spot, on a van spot or on Walt's spot", #paths == 0, table.concat(paths, ", "))
		check("the farm: clear of the World farm's barn, silo, cargo spot, lost package and board", #keeps == 0, table.concat(keeps, ", "))
		check("the farm: inside the Old Farm's yard", yard ~= nil and #outside == 0, table.concat(outside, ", "))
		local front, barn = doors[1], doors[2]
		local hx, hz = Looks.toWorld(place, site.House.At[1], site.House.At[2] + site.House.Size[3] / 2)
		check("the farm: the front door on the farmhouse's front, the barn doors on the World barn's (its Kit facade at z +15.15)",
			math.abs(front.x - hx) < 1e-6 and math.abs(front.z - hz) < 1e-6 and front.fz == 1 and barn.fz == 1 and barn.width >= 10
			and math.abs(barn.z - (place.z - 80 + 15.6)) < 0.5 and barn.x == place.x - 60)
		check("the farm: the van's spot Curb studs out of each door, you come out Out studs out",
			math.abs(front.park.z - front.z - site.Curb) < 1e-6 and math.abs(barn.out.z - barn.z - site.Out) < 1e-6)
		local sign = false
		for _, p in set.pieces do
			if p.name == "YardSign" and p.words then
				sign = p.words[1].lines[1].text == "ZDC MOVING" and p.words[1].lines[2].text == string.upper(contract.name)
			end
		end
		check(`the farm: the yard sign says ZDC MOVING · {string.upper(contract.name)}`, sign)
		-- Map step 2 moves the Old Farm and turns it 90° (Map.Relocations): the site follows its place
		local raw = Map.Places
		local moved = {}
		for _, p in raw do
			table.insert(moved, if p.id == contract.place then { id = p.id, name = p.name, x = -648, z = -1320, nx = 0, nz = 0 } else p)
		end
		local M = Map :: any
		M.Places = moved
		M.Relocations = { [contract.place] = { from = { place.x, place.z }, to = { -648, -1320 }, turn = 90 } }
		local turned = Looks.sitePlace(contract.place) :: Looks.Place
		local after = Looks.siteDoors(contract.kind, contract.place) :: { Looks.SiteDoor }
		M.Places = raw
		M.Relocations = nil
		local ok = turned.x == -648 and turned.z == -1320 and turned.yaw == -90
		for n, d in after do
			local before = doors[n]
			-- new = to + R(90)·(old − from): (dx, dz) → (−dz, dx)
			local ex, ez = -648 - (before.z - place.z), -1320 + (before.x - place.x)
			ok = ok and math.abs(d.x - ex) < 1e-6 and math.abs(d.z - ez) < 1e-6 and math.abs(d.fx - -before.fz) < 1e-6 and math.abs(d.fz - before.fx) < 1e-6
				and math.abs(d.park.x - (d.x + d.fx * site.Curb)) < 1e-6 and math.abs(d.park.z - (d.z + d.fz * site.Curb)) < 1e-6
		end
		check("map step 2: the Old Farm moved to (-648, -1320) and turned 90°: its doors and van spots go with it", ok and #after == 2)
	end
end

-- The evacuation spots --------------------------------------------------------------------------------------------------

local props: { StreetProps.Prop } = {}
for _, block in StreetProps.blocks() do
	for _, prop in block.props do
		table.insert(props, prop)
	end
end
for _, place in Looks.spotPlaces() do
	local set = byId[`spot{place.seed}`]
	local where = `spot {place.seed} ({math.floor(place.x)}, {math.floor(place.z)})`
	local blocked, near, walk = {}, {}, {}
	local district, i, j = Map.blockAt(place.x, place.z)
	check(`{where}: on a block's kerb (inside the block, off the road)`, district ~= nil)
	local origin: Looks.Place = { x = 0, y = 0, z = 0, yaw = 0 }
	for _, p in set.pieces do
		local x0, x1, _, _, z0, z1 = Looks.box(place, p)
		local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
		local reach = math.max(x1 - x0, z1 - z0) / 2
		if not StreetProps.clear(mx, mz, reach) then
			table.insert(blocked, p.name)
		end
		for _, prop in props do
			if (prop.x - mx) ^ 2 + (prop.z - mz) ^ 2 < (reach + 3) ^ 2 then
				table.insert(near, `{p.name} by a {prop.kind}`)
			end
		end
		-- in its own frame (+Z into the block, from Depth in from the curb): from the curb to before the walk line's band
		local _, _, _, _, lz0, lz1 = Looks.box(origin, p)
		if lz0 < -t.Depth or lz1 > INSET - BODY - t.Depth then
			table.insert(walk, p.name)
		end
	end
	if district then
		local cx, cz = district.ox + i * Map.Cell, district.oz + j * Map.Cell
		check(`{where}: within its block`, math.abs(place.x - cx) <= Map.BlockSize / 2 and math.abs(place.z - cz) <= Map.BlockSize / 2)
	end
	check(`{where}: clear of the doors, piles, parks, stops, docks, crosswalks and the safe zone (StreetProps.clear)`, #blocked == 0, table.concat(blocked, ", "))
	check(`{where}: clear of the street props`, #near == 0, table.concat(near, ", "))
	check(`{where}: between the curb and the people's walk line`, #walk == 0, table.concat(walk, ", "))
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
