-- 5.3, the real places (shared/Map.luau "Venues" and "Lots and homes"): the lots are the same every time (Map.makeLots,
-- seeded), the storefronts (Map.Venues) and the homes (Map.Homes) stand on their own ordinary blocks, inside them, off
-- the roads and off each other; every storefront's and home's door faces a road, the pile is just outside the door and
-- the park on the road at the curb in front (8 – 20 studs apart, the Map.CargoSpots rule); enough homes of both kinds,
-- houses facing all four ways; 5.5: every Downtown tower that can face a street is an apartment building (named by
-- its address, the flats are Residents'), only the ones with no free street (the safe zone) stay doorless; every
-- business a storefront names exists and every food business has a storefront; the new storefronts are landmarks with
-- their kind on the location tag.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local JobRules = require("./JobRules")
local LocationTags = require("./LocationTags")
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

-- Is any road's asphalt here (the yards do not count)?
local function onAsphalt(x: number, z: number): boolean
	for _, s in Map.Segments do
		local dx, dz = s.bx - s.ax, s.bz - s.az
		local length2 = dx * dx + dz * dz
		local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
		local px, pz = s.ax + dx * t, s.az + dz * t
		if (x - px) ^ 2 + (z - pz) ^ 2 <= (s.width / 2) ^ 2 + 1e-6 then
			return true
		end
	end
	return false
end
local function distance(a: Map.Spot, b: Map.Spot): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- A building's footprint: { x0, z0, x1, z1 }.
type Box = { x0: number, z0: number, x1: number, z1: number, what: string }
-- The box of a building whose front wall's middle is `door`, facing (fx, fz), `w` across the front and `d` deep.
local function frontBox(door: Map.Spot, fx: number, fz: number, w: number, d: number, what: string): Box
	local cx, cz = door.x - fx * d / 2, door.z - fz * d / 2
	local hx = if fx ~= 0 then d / 2 else w / 2
	local hz = if fz ~= 0 then d / 2 else w / 2
	return { x0 = cx - hx, z0 = cz - hz, x1 = cx + hx, z1 = cz + hz, what = what }
end

-- ── The lots ───────────────────────────────────────────────────────────────

local lotsA, homesA = Map.makeLots()
local lotsB, homesB = Map.makeLots()
local same = #homesA == #homesB and #homesA == #Map.Homes
for districtId, blocks in Map.AllLots do
	for key, list in blocks do
		for n, lot in list do
			local a, b = lotsA[districtId][key][n], lotsB[districtId][key][n]
			if not a or not b or a.kind ~= lot.kind or b.kind ~= lot.kind or a.x ~= lot.x or a.z ~= lot.z or a.w ~= lot.w or a.h ~= lot.h
				or a.facing.x ~= lot.facing.x or a.facing.z ~= lot.facing.z or a.seed ~= b.seed then
				same = false
			end
		end
	end
end
for n, home in Map.Homes do
	local a, b = homesA[n], homesB[n]
	if not a or not b or a.id ~= home.id or b.name ~= home.name or a.park.x ~= home.park.x or a.pile.z ~= home.pile.z then
		same = false
	end
end
check("the lots and homes are the same every time (seeded)", same)

local counts: { [string]: number } = {}
local lotCount, blocks = 0, 0
local badBlock: string? = nil
for _, d in Map.Districts do
	for i = d.i0, d.i1 do
		for j = d.j0, d.j1 do
			local list = Map.lotsAt(d.id, i, j)
			if d.style == "harbor" or Map.special(d.id, i, j) then
				if #list > 0 then
					badBlock = `{d.id} {i},{j} has lots`
				end
				continue
			end
			blocks += 1
			if #list ~= 4 then
				badBlock = `{d.id} {i},{j}: {#list} lots`
			end
			for _, lot in list do
				lotCount += 1
				counts[lot.kind] = (counts[lot.kind] or 0) + 1
				local bd, bi, bj = Map.blockAt(lot.x, lot.z)
				if not bd or bd.id ~= d.id or bi ~= i or bj ~= j then
					badBlock = `{d.id} {i},{j}: a lot off its block`
				end
				if math.abs(lot.facing.x) + math.abs(lot.facing.z) ~= 1 then
					badBlock = `{d.id} {i},{j}: a lot faces no side`
				end
			end
		end
	end
end
check("every ordinary Downtown and Suburbs block has four lots, the special blocks and the Harbor none", badBlock == nil, badBlock)
check("Map.lots lists the blocks by i,j", Map.lots("downtown")["2,2"] == Map.lotsAt("downtown", 2, 2) and next(Map.lots("harbor")) == nil)
print(`  {blocks} blocks, {lotCount} lots:`, counts.tower, "towers,", counts.apartment, "apartments,", counts.venue, "venues,", counts.grass, "lawns,", counts.parking, "parking,", counts.house, "houses,", counts.wreck, "wrecks,", counts.estate, "for sale")
check("downtown keeps its look: mostly towers, some lawns and parking", (counts.tower or 0) + (counts.apartment or 0) > 150 and (counts.grass or 0) > 15 and (counts.parking or 0) > 15)
check("the three houses for sale keep their lots", counts.estate == 3, counts.estate)

-- ── The storefronts ────────────────────────────────────────────────────────

local businesses: { [string]: Config.BusinessDef } = {}
for _, business in Config.Jobs.Businesses do
	businesses[business.id] = business
end
local KINDS = { "pizzeria", "bakery", "burgers", "noodles", "cafe", "postoffice", "news", "hardware", "electronics", "pawnshop", "flowers" }
local OLDER = { pharmacy = "pharmacy", market = "supermarket", bank = "bank", frosty = "icecream", warehouse = "warehouse" }
local byKind: { [string]: Map.Venue } = {}
local ids: { [string]: boolean } = {}
local venueProblem: string? = nil
local size = Map.VenueSize
local boxes: { Box } = {}
for _, venue in Map.Venues do
	local fx, fz = venue.facing.x, venue.facing.z
	if ids[venue.id] then
		venueProblem = `{venue.id}: twice`
	end
	ids[venue.id] = true
	if not businesses[venue.business] then
		venueProblem = `{venue.id}: no business {venue.business}`
	elseif math.abs(fx) + math.abs(fz) ~= 1 then
		venueProblem = `{venue.id}: no front`
	elseif string.upper(venue.sub) ~= venue.sub or venue.sub == "" then
		venueProblem = `{venue.id}: its kind is not in caps`
	end
	if venue.built then
		byKind[venue.kind] = venue
		local box = frontBox(venue.door, fx, fz, size.w, size.d, venue.id)
		table.insert(boxes, box)
		if math.abs((box.x0 + box.x1) / 2 - venue.x) > 1e-6 or math.abs((box.z0 + box.z1) / 2 - venue.z) > 1e-6 then
			venueProblem = `{venue.id}: its middle is not behind its door`
		end
		local d, i, j = Map.blockAt(venue.x, venue.z)
		local found = false
		for _, lot in Map.lotsAt(venue.district, i, j) do
			found = found or (lot.kind == "venue" and lot.venue == venue)
		end
		if not d or d.id ~= venue.district or Map.special(d.id, i, j) or not found then
			venueProblem = `{venue.id}: not on a lot of an ordinary {venue.district} block`
		end
		local cx, cz = (d :: Map.District).ox + i * Map.Cell, (d :: Map.District).oz + j * Map.Cell
		if box.x0 < cx - Map.BlockSize / 2 + 9 or box.x1 > cx + Map.BlockSize / 2 - 9 or box.z0 < cz - Map.BlockSize / 2 + 9 or box.z1 > cz + Map.BlockSize / 2 - 9 then
			venueProblem = `{venue.id}: closer than 9 studs to the curb`
		end
		local clerkInside = venue.clerk.x > box.x0 and venue.clerk.x < box.x1 and venue.clerk.z > box.z0 and venue.clerk.z < box.z1
		if not clerkInside then
			venueProblem = `{venue.id}: the clerk stands outside`
		end
	elseif OLDER[venue.id] ~= venue.business then
		venueProblem = `{venue.id}: not one of the older storefronts`
	else
		local spot = Map.CargoSpots[venue.id]
		if not spot or spot.park.x ~= venue.park.x or spot.pile.z ~= venue.pile.z then
			venueProblem = `{venue.id}: not its cargo spot`
		end
	end
end
check("the storefronts: unique, each a real business, a front, the kind in caps, on their lot (inside the block)", venueProblem == nil, venueProblem)
local missing = {}
for _, kind in KINDS do
	if not byKind[kind] then
		table.insert(missing, kind)
	end
end
check("one storefront of each new kind", #missing == 0, table.concat(missing, ", "))
local older = 0
for id in OLDER do
	older += if Map.venue(id) ~= nil then 1 else 0
end
check("the older storefronts are venues too (pharmacy, FreshMart, the bank, Frosty's, the warehouse)", older == 5, older)
local downtown, suburbs = 0, 0
for _, venue in Map.Venues do
	if venue.built then
		downtown += if venue.district == "downtown" then 1 else 0
		suburbs += if venue.district == "suburbs" then 1 else 0
	end
end
check("spread over Downtown, one or two in the Suburbs", downtown >= 8 and suburbs >= 1 and suburbs <= 2, `{downtown} / {suburbs}`)
local spread = true
for n, a in Map.Venues do
	for m = n + 1, #Map.Venues do
		local b = Map.Venues[m]
		if distance(a.park, b.park) < 60 then
			spread = false
			print("  too close:", a.id, b.id)
		end
	end
end
check("the storefronts stand 60+ studs apart", spread)

-- Every food business has a storefront; every storefront's business is found by Map.venuesOf.
local hungry = {}
for _, business in Config.Jobs.Businesses do
	local food = JobRules.hasRule(JobRules.cargoRules(business.kind, business.look, business.id), "food")
	if food and #Map.venuesOf(business.id) == 0 then
		table.insert(hungry, business.id)
	end
end
check("every food business has a storefront", #hungry == 0, table.concat(hungry, ", "))
check("the cakes come from the bakery", #Map.venuesOf("cake") == 1 and Map.venuesOf("cake")[1].kind == "bakery")
check("an unknown business has none", #Map.venuesOf("moon") == 0 and Map.venue("moon") == nil)

-- ── The homes ──────────────────────────────────────────────────────────────

local houses, apartments = 0, 0
local ways: { [string]: boolean } = {}
local names: { [string]: boolean } = {}
local homeProblem: string? = nil
for _, home in Map.Homes do
	if home.kind == "house" then
		houses += 1
		ways[`{home.facing.x},{home.facing.z}`] = true
	elseif home.kind == "apartment" then
		apartments += 1
		if not home.floors or home.floors < 2 or home.floors > 9 or home.name ~= home.address then
			homeProblem = `{home.id}: not a building ({home.name}, {home.floors} floors)`
		end
	else
		homeProblem = `{home.id}: kind {home.kind}`
	end
	if names[home.name] or names[home.id] then
		homeProblem = `{home.name}: twice`
	end
	names[home.name], names[home.id] = true, true
	if not string.find(home.name, home.address, 1, true) or not string.match(home.address, "^%d+ ") or not string.find(home.address, home.street, 1, true) then
		homeProblem = `{home.id}: its name {home.name}`
	end
	local d, i, j = Map.blockAt(home.x, home.z)
	if not d or d.id ~= home.district or Map.special(d.id, i, j) then
		homeProblem = `{home.id}: not on an ordinary block`
	elseif Map.isSafe(home.park.x, home.park.z) then
		homeProblem = `{home.id}: in the safe zone`
	end
	-- the building
	local lot: Map.Lot? = nil
	for _, candidate in Map.lotsAt(home.district, i, j) do
		if candidate.home == home then
			lot = candidate
		end
	end
	if not lot then
		homeProblem = `{home.id}: no lot`
		continue
	end
	local box: Box
	if home.kind == "apartment" then
		box = { x0 = lot.x - lot.w / 2, z0 = lot.z - lot.d / 2, x1 = lot.x + lot.w / 2, z1 = lot.z + lot.d / 2, what = home.id }
	else
		box = frontBox(home.door, home.facing.x, home.facing.z, lot.w, lot.d, home.id)
	end
	table.insert(boxes, box)
	local cx, cz = (d :: Map.District).ox + i * Map.Cell, (d :: Map.District).oz + j * Map.Cell
	if box.x0 < cx - Map.BlockSize / 2 + 9 or box.x1 > cx + Map.BlockSize / 2 - 9 or box.z0 < cz - Map.BlockSize / 2 + 9 or box.z1 > cz + Map.BlockSize / 2 - 9 then
		homeProblem = `{home.id}: closer than 9 studs to the curb`
	end
	-- the door is on the building's wall that faces the street
	local fx, fz = home.facing.x, home.facing.z
	local onWall = if fx ~= 0 then math.abs(home.door.x - (if fx > 0 then box.x1 else box.x0)) < 1e-6 else math.abs(home.door.z - (if fz > 0 then box.z1 else box.z0)) < 1e-6
	if not onWall then
		homeProblem = `{home.id}: the door is not on its front wall`
	end
end
check("the homes: unique names, a real address on their street, on an ordinary block's lot, out of the safe zone, the door on the front wall", homeProblem == nil, homeProblem)
print(`  {#Map.Homes} homes: {houses} houses, {apartments} apartments`)
check("at least 40 homes", #Map.Homes >= 40, #Map.Homes)
check("5.5: 150+ apartment doors downtown (every tower that can face a street)", apartments >= 150, apartments)
-- 5.5: a tower stays doorless only when neither of its streets has a free park (the safe zone, a place's spot …).
local doorless: string? = nil
for _, list in Map.lots("downtown") do
	for _, lot in list do
		if lot.kind == "tower" then
			local d, i, j = Map.blockAt(lot.x, lot.z)
			local cx, cz = (d :: Map.District).ox + i * Map.Cell, (d :: Map.District).oz + j * Map.Cell
			local out = Map.BlockSize / 2 + Map.CurbPark
			local west, north = lot.x < cx, lot.z < cz
			local parks = { { x = cx + (if west then -out else out), z = lot.z }, { x = lot.x, z = cz + (if north then -out else out) } }
			for _, park in parks do
				local blocked = Map.isSafe(park.x, park.z)
				for _, place in Map.Places do
					blocked = blocked or (park.x - place.x) ^ 2 + (park.z - place.z) ^ 2 < Map.FreeRadius ^ 2
				end
				for _, spot in Map.CargoSpots do
					blocked = blocked or (park.x - spot.park.x) ^ 2 + (park.z - spot.park.z) ^ 2 < Map.FreeRadius ^ 2
						or (park.x - spot.pile.x) ^ 2 + (park.z - spot.pile.z) ^ 2 < Map.FreeRadius ^ 2
				end
				for _, spot in Map.EmployerSpots do
					blocked = blocked or (park.x - spot.x) ^ 2 + (park.z - spot.z) ^ 2 < Map.FreeRadius ^ 2
				end
				for _, venue in Map.Venues do
					blocked = blocked or (park.x - venue.park.x) ^ 2 + (park.z - venue.park.z) ^ 2 < Map.FreeRadius ^ 2
				end
				for _, station in Map.GasStations do
					for _, spot in station.pumps do
						blocked = blocked or (park.x - spot.x) ^ 2 + (park.z - spot.z) ^ 2 < Map.FreeRadius ^ 2
					end
					for _, bay in station.bays do
						blocked = blocked or (park.x - bay.x) ^ 2 + (park.z - bay.z) ^ 2 < Map.FreeRadius ^ 2
					end
				end
				for _, home in Map.Homes do
					blocked = blocked or (park.x - home.park.x) ^ 2 + (park.z - home.park.z) ^ 2 < Map.ParkGap ^ 2
				end
				if not blocked then
					doorless = `{lot.district} {lot.i},{lot.j} {lot.a}{lot.b}: a free park at {park.x}, {park.z} but no entrance`
				end
			end
		end
	end
end
check("5.5: a tower stays doorless only with no free street", doorless == nil, doorless)
-- 5.5: no home's park on a gas station's pumps or bays.
local atPumps: string? = nil
for _, home in Map.Homes do
	for _, station in Map.GasStations do
		for _, bay in station.bays do
			if (home.park.x - bay.x) ^ 2 + (home.park.z - bay.z) ^ 2 < Map.FreeRadius ^ 2 then
				atPumps = `{home.id} at {station.id}`
			end
		end
	end
end
check("5.5: no home parks at a gas station's pumps", atPumps == nil, atPumps)
check("plenty of houses in the Suburbs", houses >= 30, houses)
check("the houses face all four ways", ways["1,0"] and ways["-1,0"] and ways["0,1"] and ways["0,-1"] or false)

-- ── Doors, piles and parks (storefronts and homes) ─────────────────────────

type Front = { id: string, facing: Map.Spot, door: Map.Spot, pile: Map.Spot, park: Map.Spot }
local fronts: { Front } = {}
for _, venue in Map.Venues do
	table.insert(fronts, { id = venue.id, facing = venue.facing, door = venue.door, pile = venue.pile, park = venue.park })
end
for _, home in Map.Homes do
	table.insert(fronts, { id = home.id, facing = home.facing, door = home.door, pile = home.pile, park = home.park })
end
local frontProblem: string? = nil
local pileProblem: string? = nil
for _, f in fronts do
	local fx, fz = f.facing.x, f.facing.z
	local gap = distance(f.pile, f.park)
	if gap < 8 or gap > 20 then
		pileProblem = `{f.id}: pile {math.floor(gap * 10) / 10} studs from park`
	end
	-- the pile just outside the door, toward the park
	local out = (f.pile.x - f.door.x) * fx + (f.pile.z - f.door.z) * fz
	if out <= 0 or out > 4 then
		pileProblem = `{f.id}: the pile is not just outside the door`
	end
	if onAsphalt(f.door.x, f.door.z) or onAsphalt(f.pile.x, f.pile.z) then
		frontProblem = `{f.id}: the door or the pile on a road`
	elseif not onAsphalt(f.park.x, f.park.z) or Map.inYard(f.park.x, f.park.z) or Map.inWater(f.park.x, f.park.z) then
		frontProblem = `{f.id}: the park is not on a road`
	else
		-- the road runs across the front: its asphalt starts in front of the door, the street goes sideways
		local _, _, rdx, rdz = Map.nearestRoad(f.park.x, f.park.z)
		local ahead = false
		for step = 1, 25 do
			ahead = ahead or onAsphalt(f.door.x + fx * step, f.door.z + fz * step)
		end
		if math.abs(rdx * fx + rdz * fz) > 0.01 or not ahead then
			frontProblem = `{f.id}: does not face its road`
		end
	end
end
check("every door faces a road (the street across its front), the door and pile off it, the park on it", frontProblem == nil, frontProblem)
check("every pile is just outside its door, 8 – 20 studs from its park", pileProblem == nil, pileProblem)

-- The homes and the new storefronts keep off the places' own spots (and each other's parks).
local clash: string? = nil
local function near(a: Map.Spot, x: number, z: number, r: number): boolean
	return (a.x - x) ^ 2 + (a.z - z) ^ 2 < r * r
end
for _, f in fronts do
	if Map.venue(f.id) and not (Map.venue(f.id) :: Map.Venue).built then
		continue
	end
	for _, place in Map.Places do
		if near(f.park, place.x, place.z, 25) then
			clash = `{f.id} at {place.id}`
		end
	end
	for id, spot in Map.CargoSpots do
		if near(f.park, spot.park.x, spot.park.z, 25) or near(f.pile, spot.pile.x, spot.pile.z, 25) then
			clash = `{f.id} at {id}'s cargo spot`
		end
	end
	for id, spot in Map.EmployerSpots do
		if near(f.park, spot.x, spot.z, 25) or near(f.pile, spot.x, spot.z, 25) then
			clash = `{f.id} at {id}'s board`
		end
	end
end
for n, a in fronts do
	for m = n + 1, #fronts do
		if near(a.park, fronts[m].park.x, fronts[m].park.z, 12) then
			clash = `{a.id} and {fronts[m].id} share a park`
		end
	end
end
check("the homes and storefronts keep off the places, the cargo spots, the boards and each other", clash == nil, clash)

-- No two buildings overlap; none on a road; none on an estate lot.
local overlap: string? = nil
for n, a in boxes do
	for m = n + 1, #boxes do
		local b = boxes[m]
		if a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1 then
			overlap = `{a.what} and {b.what}`
		end
	end
	for _, x in { a.x0, (a.x0 + a.x1) / 2, a.x1 } do
		for _, z in { a.z0, (a.z0 + a.z1) / 2, a.z1 } do
			if onAsphalt(x, z) then
				overlap = `{a.what} on a road`
			end
		end
	end
	for id, plot in Map.EstatePlots do
		if plot.district == "suburbs" and math.abs(plot.x - (a.x0 + a.x1) / 2) < 30 and math.abs(plot.z - (a.z0 + a.z1) / 2) < 30 then
			overlap = `{a.what} on the estate lot {id}`
		end
	end
end
check("no two buildings overlap, none stands on a road or an estate lot", overlap == nil, overlap)

-- ── On the map ─────────────────────────────────────────────────────────────

local landmarks: { [string]: Map.Landmark } = {}
for _, landmark in Map.Landmarks do
	landmarks[landmark.id] = landmark
end
local listed = true
for _, venue in Map.Venues do
	local landmark = landmarks[venue.id]
	if venue.built and (not landmark or landmark.kind ~= "venue" or landmark.description == "" or landmark.x ~= venue.park.x or landmark.z ~= venue.park.z) then
		listed = false
		print("  not a landmark:", venue.id)
	end
end
check("every new storefront is a landmark (kind venue, at the road in front of its door)", listed)
local tags: { [string]: LocationTags.Tag } = {}
for _, tag in LocationTags.build() do
	tags[tag.id] = tag
end
check("the location tag says the storefront's kind", tags.luigis ~= nil and tags.luigis.sub == "PIZZERIA" and tags.luigis.name == "Luigi's Pizza")
check("an older storefront's tag says its kind too", tags.pharmacy ~= nil and tags.pharmacy.sub == "PHARMACY" and tags.market ~= nil and tags.market.sub == "SUPERMARKET")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
