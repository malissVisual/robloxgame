--!strict
-- The layout of the world, as plain numbers (x, z on the ground; -Z is north on the map). The server builds it
-- (server/World.luau), the client draws it (client/MapView.luau) and both ask it where the roads are.
--
--   Downtown   a 9 x 9 grid of blocks around the Central Park (6.11: the middle block, a pond in the very middle of the
--              map, Map.Park), the shops in the four blocks next to it (the safe zone), the depot north-east of it
--              on block (1, -1) (6.11: Map.Depot; it stood on the middle block before)
--   Harbor     east, across the river (Rust Bridge, Old Bridge), docks on the sea
--   Suburbs    south, little houses
--   Highways   north to the Gas Station, through the mountain tunnel to the Military Base;
--              west to the Radio Station and the Old Farm; the Ranch Road off the West Highway to Silver Spur Ranch
--   Riverside  the Riverside Riding School by the river, down Riding School Lane from the Suburbs
--   Harbor     the Harbor Fuel Depot south of the warehouses
--   Downtown   the First Zombie Bank just north of the safe zone (on 6th Ave, the way to the North Highway) and
--              the City Clinic south-west of the park
--   Real estate (Config.Estate, Map.EstatePlots), spread over the map: the Hilltop Mansion in Sunset Hills above the
--              city (up the winding Sunset Drive, north-east of Downtown), Ocean View on the sea cliffs north of the
--              Harbor, Pinecrest in the pines off the West Highway, the Lakeside Villa by the frozen lake, the Sunset
--              Villa down a quiet lane in the west, houses on different Suburbs streets and one at the edge of town,
--              five garages (3.4: the Rented Lockup and the Southside Garage between Downtown and the Suburbs; the
--              Harbor Lockup, the Highway Garage on the North Highway, Downtown Parking) and the two
--              office towers (Dispatch Tower downtown, Harbor Point in the Harbor) with the offices on their upper
--              floors (Map.Towers)
--   Missions   (3.0) fifteen more places for the mission campaigns (shared/Missions.luau): on downtown blocks the
--              Corner Pharmacy, FreshMart, Fire Station 9, Precinct 13 and City Hall, the Harbor Warehouse on a Harbor
--              block; out of town, each in its own yard at the end of a short road, the Old Airfield (south-west), the
--              Power Plant (south of the Harbor), the Water Works (by the river), the Biotech Lab and the Train Yard
--              (north of Downtown), Blackrock Prison (far north-west), Lighthouse Point (on the coast north of Ocean
--              View), the Survivor Camp (on the Radio Road) and the Stadium Shelter (south of the Suburbs)
--   Secrets    (3.1) a lost package hidden at every place, one more up the stadium stands (Map.Secrets)
--   Repairs    (3.4) the repair shops (Map.RepairShops): Wrench Garage and Rust Bridge Repairs (a Harbor block)
--   Bikes      (5.1) Spoke & Chain Cycles (Map.Shops.bikes), the bike shop on Downtown block (-1, 1), its door on Main St;
--              6.12.7: the bikes are Dead End Motors' BIKES counter (Map.Shops.bikes, Config.BikeShop), next to its car
--              counter: one shop; Spoke & Chain's old building an ordinary one (Map.FormerBikeShop)
--   Bags       (6.6) ZDC Bags (Map.Shops.bags, Config.BagShop): the bag kiosk in the depot's yard, by the spawn;
--              6.12.2: it and Last Stop Supplies (Map.Shops.supplies) are the two counters of the gear stall there
--              (Config.GearStall), Last Stop's old building on block (0, -1) an ordinary one (Map.LastStop)
--   Park       (6.11) the Central Park (Map.Park, server/CentralPark.luau): the pond with its island and fountain, the
--              paths, trees, flowerbeds, benches, lamps and a gazebo, on the middle block in the safe zone
--   Gas       (5.4) the gas stations (Map.GasStations): the old one on the North Highway and three on the town's lots
--   Places     (5.3) what stands on every lot of the ordinary Downtown and Suburbs blocks (Map.lots, seeded: towers,
--              lawns, parking, houses ...), the storefronts the businesses work from (Map.Venues: Luigi's Pizza, the
--              Daily Bread Bakery, the Post Office ... and the older pharmacy, FreshMart, bank, Frosty's, warehouse) and
--              the homes the deliveries go to (Map.Homes: apartment entrances downtown, houses in the Suburbs), each
--              with its door, its pile just outside and its park on the road in front
--
-- It also holds the shape of the night over the clock (Map.nightFactor): the server runs the clock
-- (server/DayNight.luau), every client draws the look from the same numbers (client/Weather.luau).
--
-- A district is a grid: block (i, j) is centred at (ox + i × CELL, oz + j × CELL); the roads run between the blocks
-- and around them (road k between block k and k + 1, centred at ox + (k + 0.5) × CELL).

local Config = require(script.Parent.Config)

local BLOCK = Config.City.BlockSize
local ROAD = Config.City.RoadWidth
local HIGHWAY = Config.City.HighwayWidth
local CELL = BLOCK + ROAD

local Map = {}

Map.Cell = CELL
Map.BlockSize = BLOCK
Map.RoadWidth = ROAD
Map.HighwayWidth = HIGHWAY
Map.RoadTop = 0.4
-- 6.10: the sidewalks a curb over the road (the owner: "a little higher"): WalkTop 0.6 → 0.9, 0.5 studs over the
-- road (about 15 cm; it was 0.2). Every block's edge is a sloped kerb (shared/CurbShape.luau, built by
-- server/Curbs.luau): CurbRun studs out onto the road it rises from RoadTop to WalkTop, so every vehicle drives up and
-- down it anywhere along the curb (the wheels are frictionless colliders: a slope lifts them, a step would stop them)
-- and the people step over it.
Map.WalkTop = 0.9
Map.CurbRun = 2

export type District = {
	id: string,
	name: string,
	style: string, -- downtown | harbor | suburbs
	ox: number,
	oz: number,
	i0: number,
	i1: number,
	j0: number,
	j1: number,
	streets: { string }, -- roads along X (constant z)
	avenues: { string }, -- roads along Z (constant x)
}

export type Segment = {
	ax: number,
	az: number,
	bx: number,
	bz: number,
	width: number,
	kind: string, -- street | grid | bridge | highway | ice
	name: string?,
}

export type Area = { id: string, name: string, x0: number, z0: number, x1: number, z1: number }

export type Place = {
	id: string,
	name: string,
	x: number,
	z: number,
	nx: number, -- the side the zombies wait on (0, 0 = all around)
	nz: number,
}

-- 3.1: a lost package hidden at a place (Map.Secrets).
export type Secret = {
	id: string, -- "secret_<place id>"; an extra one at a fun spot: "secret_<place id>_<where>"
	place: string, -- the Map.Places id it belongs to
	hint: string, -- a riddle-ish line for the SECRETS tab (client/MissionsUi.luau)
	x: number,
	y: number, -- the floor under the package (the ground, a sidewalk, a portico, a platform, a stand)
	z: number,
}

export type Address = {
	x: number,
	z: number,
	nx: number,
	nz: number,
	name: string,
	district: string,
	poi: boolean,
}

Map.Bounds = { x0 = -2150, z0 = -2950, x1 = 1900, z1 = 1500 }
Map.River = { x0 = 760, x1 = 920 }
Map.Sea = { x0 = 1660 }
Map.WaterLevel = -3
Map.Mountain = { x = 300, z = -1700, radius = 265, tunnelZ0 = -1960, tunnelZ1 = -1440 }
-- North of the mountain it is winter: snow, and a frozen lake the Lodge Road crosses on the ice.
Map.WinterZ = -1965
Map.Lake = { x0 = -490, x1 = -110, z0 = -2340, z1 = -2060 }

Map.Districts = {
	{
		id = "downtown",
		name = "Downtown",
		style = "downtown",
		ox = 0,
		oz = 0,
		i0 = -4,
		i1 = 4,
		j0 = -4,
		j1 = 4,
		streets = { "Maple St", "Oak St", "Grave St", "Elm St", "Bone St", "Main St", "Cedar St", "Ash St", "Hollow St", "Pine St" },
		avenues = { "1st Ave", "2nd Ave", "3rd Ave", "4th Ave", "5th Ave", "6th Ave", "7th Ave", "8th Ave", "9th Ave", "10th Ave" },
	},
	{
		id = "harbor",
		name = "Harbor",
		style = "harbor",
		ox = 1080,
		oz = 0,
		i0 = 0,
		i1 = 3,
		j0 = -3,
		j1 = 3,
		streets = { "Anchor Rd", "Salt Rd", "Gull Rd", "Cargo Rd", "Rope Rd", "Keel Rd", "Hull Rd", "Tide Rd" },
		avenues = { "Dock 1", "Dock 2", "Dock 3", "Dock 4", "Dock 5" },
	},
	{
		id = "suburbs",
		name = "Suburbs",
		style = "suburbs",
		ox = 0,
		oz = 900,
		i0 = -2,
		i1 = 2,
		j0 = 0,
		j1 = 2,
		streets = { "Willow Ln", "Daisy Ln", "Cherry Ln", "Birch Ln" },
		avenues = { "Hill Rd", "Brook Rd", "Fern Rd", "Moss Rd", "Lake Rd", "Rose Rd" },
	},
} :: { District }

-- Blocks that are not ordinary city blocks: the park, the depot, the shops and the employers' buildings.
Map.SpecialBlocks = {
	downtown = {
		["0,0"] = "park", -- 6.11: the Central Park (Map.Park), where the depot stood
		["1,-1"] = "depot", -- 6.11: the depot (Map.Depot), where four plain towers stood (Map.FormerBlocks)
		["1,0"] = "dealer",
		["-1,0"] = "guns",
		["0,1"] = "mechanic",
		["0,-1"] = "supplies", -- (6.12.2: Last Stop's old building, no shop any more: Map.LastStop; the block stays special)
		["2,1"] = "movers",
		["1,-2"] = "bank", -- First Zombie Bank: its front on 6th Ave, just out of the safe zone
		["-2,2"] = "clinic", -- City Clinic: its front and the emergency entrance on 4th Ave
		["-1,-1"] = "dispatchtower", -- Dispatch Tower (the offices), in the safe zone
		["1,1"] = "parking", -- Downtown Parking (a garage), in the safe zone
		["-1,1"] = "bikes", -- 5.1, Spoke & Chain Cycles (6.12.7: its old building, no shop any more: Map.FormerBikeShop)
		-- 3.0, the missions' places in town (all just outside the safe zone):
		["0,-3"] = "cityhall", -- City Hall: north of the park, its steps down to the street in front (south)
		["-2,-2"] = "police", -- Precinct 13: its front and the patrol cars on the street to the south
		["2,-1"] = "firestation", -- Fire Station 9: the truck bays open to the avenue on the east
		["1,3"] = "pharmacy", -- the Corner Pharmacy: its door on the street to the north
		["-3,1"] = "market", -- FreshMart: the car park and the doors on the avenue to the east
	},
	suburbs = { ["0,2"] = "school" },
	harbor = {
		["1,0"] = "frosty",
		["3,-1"] = "harborpoint", -- Harbor Point (an office), by the docks
		["0,-3"] = "lockup", -- the Harbor Lockup (a garage), where the Old Bridge comes over
		["2,2"] = "warehouse", -- the Harbor Warehouse (3.0): its roller doors on the avenue to the west
		["0,1"] = "repairs", -- Rust Bridge Repairs (3.4, a repair shop): where the Rust Bridge comes over
		["0,0"] = "gas", -- 5.4, Harbor Gas (Map.GasStations): where the Rust Bridge comes over, across from Frosty's
	},
} :: { [string]: { [string]: string } }

function Map.special(districtId: string, i: number, j: number): string?
	local blocks = Map.SpecialBlocks[districtId]
	return if blocks then blocks[`{i},{j}`] else nil
end

-- 6.11: the special blocks that were ordinary blocks before (Harbor Gas, 5.4; the depot's, 6.11). Whatever rolls its
-- dice block by block (Map.addresses, Map.makeLots, shared/RentalDocks.luau, shared/Shortcuts.luau, the towers in
-- server/World.luau) still rolls theirs and keeps nothing there, so every other block stays as it was.
Map.FormerBlocks = {
	downtown = { ["1,-1"] = true },
	harbor = { ["0,0"] = true },
} :: { [string]: { [string]: boolean } }

function Map.wasOrdinary(districtId: string, i: number, j: number): boolean
	local blocks = Map.FormerBlocks[districtId]
	return blocks ~= nil and blocks[`{i},{j}`] == true
end

-- 6.11, the depot (the owner: "move the houses elsewhere"): the spawn, the job board, the garage terminal, Marge, the
-- scooter rack and the ZDC Bags kiosk, on Downtown block (1, -1) north-east of the park, laid out as on the middle block
-- before: the hall at the back (north), the yard open to Bone St (south), the park's corner across the junction. Every
-- spot of it is given from its middle (x, z): World.DepotSpawn, Config.Tutorial.NpcSpot, Config.Goal.BoardSpot,
-- Config.BagShop, Config.Rental.SpawnRack. 6.12.2: the JOBS spot round the job board (server/JobsSpot.luau) and the
-- gear stall west of the spawn (Config.GearStall: the ZDC Bags and Last Stop Supplies counters) in place of the kiosk.
export type Depot = { i: number, j: number, x: number, z: number }
Map.Depot = { i = 1, j = -1, x = CELL, z = -CELL } :: Depot

-- 6.12.2: the building on Downtown block (0, -1) that was Last Stop Supplies until its stock moved to the gear stall at
-- the depot (Map.Shops.supplies): an ordinary building now (server/World.luau buildSupplies: its look, no counter, no
-- clerk, no name board; 6.12.6: a bare roof, its giant vest turns over the gear stall). The block stays special (its
-- dice as before); the bus lines still draw a stop toward it as they did (shared/BusLines.luau), without its name.
Map.LastStop = { i = 0, j = -1, x = 0, z = -CELL }

-- 6.12.7: the building on Downtown block (-1, 1) that was Spoke & Chain Cycles until the bikes moved to Dead End
-- Motors' BIKES counter (Map.Shops.bikes, Config.BikeShop: one shop for the cars and the bikes): an ordinary building
-- now (server/World.luau buildBikeShop: its shell and its shop windows, no counter, no prompt, no clerk, no name board,
-- no display bikes; its rooftop bike stands on Dead End Motors' roof). The block stays special (its dice as before);
-- the bus lines still draw a stop toward it as they did (shared/BusLines.luau), without its name.
Map.FormerBikeShop = { i = -1, j = 1, x = -CELL, z = CELL }

-- 6.11, the Central Park (the owner: "the middle of the map, where the safe zone is, nice: nature, some water in the
-- middle, a park ... so people remember where the safe zone is and where all the shops are") on the middle block (0, 0),
-- the shops all round it. server/CentralPark.luau builds it, client/MapView.luau draws it. In studs from its middle:
--   pond    the pond, a regular octagon (its flat sides to the four streets), `pond` from the middle to a flat side;
--           real water (Terrain) from the ground's 0 down `depth` (the walk is Map.WalkTop over it), a stone coping
--   island  the island in the pond's middle (its radius): the fountain, a footbridge to it from the south
--   ring    the path round the pond (this wide, outside the coping); paths from it to the middles of the four sides
--           and to the four corners
--   walk    the sidewalk round the block's edge (this wide): the people's walk line on it as on every block, nothing
--           solid on it (no fence: the park is open all round)
--   seed    the park's own dice (the trees' sizes and shades): the world's random numbers are not touched
export type Park = { id: string, name: string, i: number, j: number, x: number, z: number, pond: number, depth: number, island: number, ring: number, walk: number, seed: number }
Map.Park = { id = "park", name = "Central Park", i = 0, j = 0, x = 0, z = 0, pond = 19, depth = 4, island = 6.5, ring = 4.5, walk = 10, seed = Config.City.Seed + 611 } :: Park

-- 6.11 review: is (x, y, z) in the park's pond: inside its octagon (flat sides `pond` from the middle, to the streets
-- and to the corners) and lower than the walk? server/Vehicles.luau sinks a vehicle there (its coping is low enough for
-- a car's wheels to roll over, and the pond's floor is above the usual "sank" depth).
function Map.inPond(x: number, y: number, z: number): boolean
	local park = Map.Park
	local dx, dz = math.abs(x - park.x), math.abs(z - park.z)
	return y < Map.WalkTop and dx <= park.pond and dz <= park.pond and (dx + dz) <= park.pond * math.sqrt(2)
end

-- The shops (their block centres); you must stand within Radius of one to use it (6.6: a shop's own `radius`, else
-- Map.ShopRadius: ZDC Bags is a small kiosk in the depot's yard, Map.shopRadius). 6.12.2: ZDC Bags and Last Stop
-- Supplies are the two counters of the gear stall in the depot's yard (Config.GearStall): each spot is its counter's
-- front, with the stall's radius. 6.12.7: the bikes ("bikes") are the BIKES counter of Dead End Motors, beside its car
-- counter ("dealer"): its spot the counter's front, its radius over the counter and the bike stands (Config.BikeShop).
Map.Shops = {
	depot = { name = "Depot Garage", x = Map.Depot.x, z = Map.Depot.z }, -- (6.7: the garage terminal, not a shop: it sells nothing, no shop window)
	dealer = { name = "Dead End Motors", x = CELL, z = 0 },
	guns = { name = "Lead & Co.", x = -CELL, z = 0 },
	mechanic = { name = "Wrench Garage", x = 0, z = CELL },
	-- 6.12.2: the GEAR counter of the gear stall (its old building on block (0, -1): Map.LastStop)
	supplies = {
		name = "Last Stop Supplies",
		x = Map.Depot.x + Config.GearStall.X + Config.GearStall.Depth / 2,
		z = Map.Depot.z + Config.GearStall.Z + Config.GearStall.Counter,
		radius = Config.GearStall.Radius,
	},
	-- 5.1: bikes and bike gear (Config.BikeShop). 6.12.7: Dead End Motors' BIKES counter, at the back of its showroom
	-- (World buildDealer: the building faces west, so its frame's x runs north and its z east, from the block's middle
	-- plus Back); its old building on block (-1, 1): Map.FormerBikeShop
	bikes = {
		name = "Dead End Motors · Bikes",
		x = CELL + Config.BikeShop.Building.Back + Config.BikeShop.Desk.Z - Config.BikeShop.Desk.Deep / 2,
		z = 0 - Config.BikeShop.Desk.X,
		radius = Config.BikeShop.Radius,
	},
	bags = { name = Config.BagShop.Name, x = Map.Depot.x + Config.BagShop.X, z = Map.Depot.z + Config.BagShop.Z, radius = Config.BagShop.Radius }, -- 6.6: the bags (6.11: in the depot's yard, wherever the depot is; 6.12.2: the gear stall's BAGS counter)
} :: { [string]: { name: string, x: number, z: number, radius: number? } }
Map.ShopRadius = 80

-- 6.6: how close to a shop's spot counts as in it (its own radius, else Map.ShopRadius).
function Map.shopRadius(shopId: string): number
	local shop = Map.Shops[shopId]
	return if shop and shop.radius then shop.radius else Map.ShopRadius
end

-- 3.4, the repair shops (server/Repair.luau): Wrench Garage in Downtown and Rust Bridge Repairs on a Harbor block
-- (Map.SpecialBlocks "repairs"). server/World.luau builds their repair bays (World.RepairBays); the bays face the
-- road in front (`facing`, a unit direction along X or Z), the cars drive in through the wide door.
export type RepairShop = { id: string, name: string, x: number, z: number, facing: { x: number, z: number } }
Map.RepairShops = {
	{ id = "mechanic", name = "Wrench Garage", x = 0, z = CELL, facing = { x = 0, z = -1 } },
	{ id = "repairs", name = "Rust Bridge Repairs", x = 1080, z = CELL, facing = { x = -1, z = 0 } },
} :: { RepairShop }

-- Flat open areas at the ends of the highways.
Map.Yards = {
	{ id = "base", name = "Military Base", x0 = 40, z0 = -2840, x1 = 560, z1 = -2360 },
	{ id = "radio", name = "Radio Station", x0 = -1200, z0 = -660, x1 = -1000, z1 = -460 },
	{ id = "farm", name = "Old Farm", x0 = -2030, z0 = 370, x1 = -1730, z1 = 670 },
	{ id = "docks", name = "Harbor Docks", x0 = 1601, z0 = -200, x1 = 1656, z1 = 200 },
	{ id = "gas", name = "Gas Station", x0 = 92, z0 = -960, x1 = 200, z1 = -840 },
	{ id = "lodge", name = "Ski Lodge", x0 = -780, z0 = -2320, x1 = -530, z1 = -2080 },
	{ id = "ranch", name = "Silver Spur Ranch", x0 = -1010, z0 = 700, x1 = -790, z1 = 880 },
	{ id = "stables", name = "Riverside Riding School", x0 = 580, z0 = 890, x1 = 745, z1 = 1060 },
	{ id = "fueldepot", name = "Harbor Fuel Depot", x0 = 1290, z0 = 521, x1 = 1640, z1 = 720 },
	-- 3.0, the missions' places out of town (Map.PlaceRoads lead to the ones that are not on a road already).
	{ id = "airfield", name = "Old Airfield", x0 = -1760, z0 = 1150, x1 = -1240, z1 = 1380 },
	{ id = "powerplant", name = "Power Plant", x0 = 1015, z0 = 521, x1 = 1270, z1 = 760 },
	{ id = "waterworks", name = "Water Works", x0 = 430, z0 = 690, x1 = 745, z1 = 870 },
	{ id = "lab", name = "Biotech Lab", x0 = -420, z0 = -1150, x1 = -150, z1 = -950 },
	{ id = "prison", name = "Blackrock Prison", x0 = -1800, z0 = -1260, x1 = -1400, z1 = -900 },
	{ id = "lighthouse", name = "Lighthouse Point", x0 = 1520, z0 = -1180, x1 = 1650, z1 = -980 },
	{ id = "trainyard", name = "Train Yard", x0 = -580, z0 = -900, x1 = -100, z1 = -740 },
	{ id = "camp", name = "Survivor Camp", x0 = -1080, z0 = -360, x1 = -860, z1 = -140 },
	{ id = "stadium", name = "Stadium Shelter", x0 = -200, z0 = 1277, x1 = 200, z1 = 1440 },
	-- 5.0, Earl's Used Wheels (Map.VanSeller): a dusty lot on the north side of the West Highway's last stretch, between
	-- the Airfield Road and the Old Farm. Its front edge is the highway's edge (centre z 520, 40 wide).
	{ id = "earl", name = "Earl's Used Wheels", x0 = -1650, z0 = 420, x1 = -1490, z1 = 500 },
} :: { Area }

-- 5.0, Earl's Used Wheels (Config.VanQuest, server/VanQuest.luau): where Earl's old van stands for sale (x, z, facing
-- the highway: its nose to the road), where Earl stands (earl) and where the van you buy from him is parked for you
-- (parking, beside the one for sale, facing the road too). About 1,700 studs west of the depot: a trip.
export type VanSeller = { x: number, z: number, facing: { x: number, z: number }, earl: { x: number, z: number }, parking: { x: number, z: number } }
Map.VanSeller = {
	x = -1592,
	z = 458,
	facing = { x = 0, z = 1 },
	earl = { x = -1572, z = 474 },
	parking = { x = -1548, z = 458 },
} :: VanSeller

-- Open ground next to the yards that must stay free of trees (the ranch paddock, the riding arena).
Map.Clearings = {
	{ id = "paddock", name = "Paddock", x0 = -1010, z0 = 880, x1 = -790, z1 = 1020 },
	{ id = "arena", name = "Riding Arena", x0 = 585, z0 = 1060, x1 = 750, z1 = 1235 },
} :: { Area }

-- Named destinations (the far, crazy deliveries).
Map.Places = {
	{ id = "base", name = "Military Base", x = 300, z = -2600, nx = 0, nz = 0 },
	{ id = "radio", name = "Radio Station", x = -1100, z = -560, nx = 0, nz = 0 },
	{ id = "farm", name = "Old Farm", x = -1880, z = 520, nx = 0, nz = 0 },
	{ id = "docks", name = "Harbor Docks", x = 1626, z = 0, nx = 0, nz = 0 },
	{ id = "gas", name = "Gas Station", x = 146, z = -900, nx = 0, nz = 0 },
	{ id = "lodge", name = "Ski Lodge", x = -655, z = -2200, nx = 0, nz = 0 },
	{ id = "school", name = "Sunny Hill School", x = 0, z = 900 + 2 * CELL - BLOCK / 2 - 6, nx = 0, nz = -1 },
	{ id = "frosty", name = "Frosty's Ice Cream", x = 1080 + CELL - BLOCK / 2 - 6, z = 0, nx = -1, nz = 0 },
	{ id = "movers", name = "Big Move Movers", x = 2 * CELL + BLOCK / 2 + 6, z = CELL, nx = 1, nz = 0 },
	{ id = "ranch", name = "Silver Spur Ranch", x = -900, z = 740, nx = 0, nz = 0 },
	{ id = "stables", name = "Riverside Riding School", x = 640, z = 972, nx = 0, nz = 0 },
	{ id = "fueldepot", name = "Harbor Fuel Depot", x = 1440, z = 550, nx = 0, nz = 0 },
	-- Downtown, on the road in front of their blocks (outside the safe zone, so they are addresses too).
	{ id = "bank", name = "First Zombie Bank", x = CELL - BLOCK / 2 - 6, z = -2 * CELL, nx = -1, nz = 0 },
	{ id = "clinic", name = "City Clinic", x = -2 * CELL + BLOCK / 2 + 6, z = 2 * CELL + 12, nx = 1, nz = 0 },
	-- 3.0, the missions' places. In town: on the road in front of their blocks (Map.SpecialBlocks).
	{ id = "pharmacy", name = "Corner Pharmacy", x = CELL, z = 3 * CELL - BLOCK / 2 - 6, nx = 0, nz = -1 },
	{ id = "market", name = "FreshMart Supermarket", x = -3 * CELL + BLOCK / 2 + 6, z = CELL, nx = 1, nz = 0 },
	{ id = "warehouse", name = "Harbor Warehouse", x = 1080 + 2 * CELL - BLOCK / 2 - 6, z = 2 * CELL, nx = -1, nz = 0 },
	{ id = "firestation", name = "Fire Station 9", x = 2 * CELL + BLOCK / 2 + 6, z = -CELL, nx = 1, nz = 0 },
	{ id = "police", name = "Precinct 13", x = -2 * CELL, z = -2 * CELL + BLOCK / 2 + 6, nx = 0, nz = 1 },
	{ id = "cityhall", name = "City Hall", x = 0, z = -3 * CELL + BLOCK / 2 + 6, nx = 0, nz = 1 },
	-- Out of town: in their yards, just in from the road.
	{ id = "airfield", name = "Old Airfield", x = -1400, z = 1185, nx = 0, nz = 0 },
	{ id = "powerplant", name = "Power Plant", x = 1100, z = 548, nx = 0, nz = 0 },
	{ id = "waterworks", name = "Water Works", x = 452, z = 780, nx = 0, nz = 0 },
	{ id = "lab", name = "Biotech Lab", x = -172, z = -1000, nx = 0, nz = 0 },
	{ id = "prison", name = "Blackrock Prison", x = -1600, z = -925, nx = 0, nz = 0 },
	{ id = "lighthouse", name = "Lighthouse Point", x = 1545, z = -1080, nx = 0, nz = 0 },
	{ id = "trainyard", name = "Train Yard", x = -216, z = -765, nx = 0, nz = 0 },
	{ id = "camp", name = "Survivor Camp", x = -1058, z = -250, nx = 0, nz = 0 },
	{ id = "stadium", name = "Stadium Shelter", x = 0, z = 1300, nx = 0, nz = 0 },
} :: { Place }

-- 3.1, the lost packages: one hidden at every place (and one more at a fun spot), found on foot with its prompt
-- (server/World.luau builds them, server/Challenges.luau pays the finder once, client/Secrets.luau hides the ones a
-- player has found, client/MissionsUi.luau shows the hints). Each one lies next to something real of its place
-- (server/World.luau's builders): behind a building or a stand, under a bench or a table, between parked things, up
-- on a platform; within 60 studs of the place's point (the extra one anywhere in its place's yard), never in the
-- water, never inside a solid part, reachable on foot (a jump is about 7 studs). Where a place has nothing to hide
-- behind near its point, World brings a small cover with the package (a sandbag nest, a snowman, hay, tyres, boxes,
-- a cable reel). y is the floor under the package: the yards 0.4 (ROAD_TOP), the blocks' sidewalks Map.WalkTop (6.10:
-- written so, it follows the curb: 0.9 now).
Map.Secrets = {
	-- The far places.
	{ id = "secret_base", place = "base", hint = "The soldiers built a little sandbag nest in the middle of the yard. Something waits inside.", x = 330, y = 0.4, z = -2632 },
	{ id = "secret_radio", place = "radio", hint = "At the feet of the tall steel giant, under its blinking red eye.", x = -1061, y = 0.4, z = -603.5 },
	{ id = "secret_farm", place = "farm", hint = "Fresh food is sold out front; something less fresh waits behind the stand.", x = -1874.5, y = 0.4, z = 470.2 },
	{ id = "secret_docks", place = "docks", hint = "Behind the tallest stack of ammo crates, with the sea at your back.", x = 1650.5, y = 0.4, z = -14 },
	{ id = "secret_gas", place = "gas", hint = "Behind the little shop, where the pumps can't see.", x = 196.5, y = 0.4, z = -890 },
	{ id = "secret_lodge", place = "lodge", hint = "A cold guard with a carrot nose keeps watch by the lodge. Look behind him.", x = -690, y = 0.4, z = -2241.5 },
	{ id = "secret_ranch", place = "ranch", hint = "Just inside the gate, the hay hides something the horses won't eat.", x = -940, y = 0.4, z = 708 },
	{ id = "secret_stables", place = "stables", hint = "Hay by the lamp near the clubhouse: look on the side away from the stalls.", x = 619.6, y = 0.4, z = 931.5 },
	{ id = "secret_fueldepot", place = "fueldepot", hint = "Behind the full barrels at the back of the loading shed. No smoking!", x = 1465, y = 0.4, z = 592 },
	-- The employers' buildings in town.
	{ id = "secret_school", place = "school", hint = "Class is out. In the corner of the front wall, as far from the door as you can get.", x = -38.5, y = Map.WalkTop, z = 1171 },
	{ id = "secret_frosty", place = "frosty", hint = "Hugging the pink wall north of the door, out of the sun, like ice cream should.", x = 1209.6, y = Map.WalkTop, z = -30 },
	{ id = "secret_movers", place = "movers", hint = "Among the moving boxes nobody ever moved, against the orange wall.", x = 302.4, y = Map.WalkTop, z = 111 },
	{ id = "secret_bank", place = "bank", hint = "Up the steps, between marble and money: behind the last column on the south side.", x = 127.6, y = Map.WalkTop + 1.2, z = -266 }, -- (the portico, 1.2 over the walk)
	{ id = "secret_clinic", place = "clinic", hint = "The patients' bench by the front door hides more than old gum.", x = -266, y = Map.WalkTop, z = 324 },
	-- The missions' places in town (3.0).
	{ id = "secret_pharmacy", place = "pharmacy", hint = "Right under the green cross, against the wall.", x = 116, y = Map.WalkTop, z = 414 },
	{ id = "secret_market", place = "market", hint = "Between the grocery pallets at the delivery bay.", x = -411, y = Map.WalkTop + 0.1, z = 109 }, -- (the car park, 0.1 over the walk)
	{ id = "secret_warehouse", place = "warehouse", hint = "The yellow forklift parked out front is hiding something behind its back.", x = 1345, y = Map.WalkTop, z = 252 }, -- 4.0: moved off the loading docks
	{ id = "secret_firestation", place = "firestation", hint = "Tucked behind the red hydrant on the corner. No hose needed.", x = 316, y = Map.WalkTop, z = -104 },
	{ id = "secret_police", place = "police", hint = "Between the two parked patrol cars. Nobody is watching.", x = -258, y = Map.WalkTop, z = -258 },
	{ id = "secret_cityhall", place = "cityhall", hint = "Make a wish at the fountain, then look on its far side, toward the hall.", x = 22, y = Map.WalkTop, z = -401.5 },
	-- The missions' places out of town (3.0).
	{ id = "secret_airfield", place = "airfield", hint = "Old tyres by the fence, just inside the gate on your right. Look behind them.", x = -1430.5, y = 0.4, z = 1156 },
	{ id = "secret_powerplant", place = "powerplant", hint = "A big cable reel by the lamp in front of the turbine hall. Check the side facing the hall.", x = 1114, y = 0.4, z = 602.6 },
	{ id = "secret_waterworks", place = "waterworks", hint = "The pump house hums. Walk down its west wall.", x = 483, y = 0.4, z = 732 },
	{ id = "secret_lab", place = "lab", hint = "Right under the yellow BIOHAZARD sign. Nobody wants to look there.", x = -213.2, y = 0.4, z = -1036 },
	{ id = "secret_prison", place = "prison", hint = "At the foot of the left gate tower, where the tower meets the wall.", x = -1626, y = 0.4, z = -961.5 },
	{ id = "secret_lighthouse", place = "lighthouse", hint = "Behind the keeper's cottage, right below the chimney.", x = 1590.4, y = 0.4, z = -1051 },
	{ id = "secret_trainyard", place = "trainyard", hint = "Up on the freight platform, past the last crates at the east end.", x = -203, y = 3.4, z = -817 },
	{ id = "secret_camp", place = "camp", hint = "Behind the sandbags by the gate, in the corner with the planks.", x = -1073, y = 0.4, z = -285.5 },
	{ id = "secret_stadium", place = "stadium", hint = "Under the supply table by the gate, among the relief goods.", x = 15, y = 0.4, z = 1318 },
	-- The extra one: the stands are steps (4 studs each); the top row is under the roof.
	{ id = "secret_stadium_top", place = "stadium", hint = "Climb to the very top row of the east stands, far end. Best seat in the house.", x = 191, y = 16.4, z = 1430 },
} :: { Secret }

-- Where each employer's board stands (walk up to it to work for them).
-- (keyed by Config.Employers ids)
Map.EmployerSpots = {
	school = { x = 0, z = 900 + 2 * CELL - BLOCK / 2 + 8 },
	icecream = { x = 1080 + CELL - BLOCK / 2 + 8, z = 0 },
	movers = { x = 2 * CELL + BLOCK / 2 - 8, z = CELL },
	army = { x = 330, z = -2385 },
	farm = { x = -1790, z = 560 },
	ranch = { x = -930, z = 728 },
	gas = { x = 188, z = -948 },
	clinic = { x = -2 * CELL + BLOCK / 2 - 8, z = 2 * CELL - 26 }, -- by the clinic's front door, left of the emergency bay
} :: { [string]: { x: number, z: number } }
Map.EmployerRadius = 40

export type CargoSpot = {
	park: { x: number, z: number }, -- where the vehicle stops (the circle)
	pile: { x: number, z: number }, -- where the cargo stands / the receiver waits (on foot, 8 – 20 studs from park)
	facing: { x: number, z: number }, -- the way the person at the pile faces (a unit direction: toward the park)
}

-- Where the special jobs load and unload (server/Cargo.luau): park in the circle, carry the cargo between the pile
-- and the back of the vehicle. Ordinary addresses have no spot (the park is the address, the pile 12 studs in).
local cargoSpots: { [string]: CargoSpot } = {}
local rawSpots: { [string]: { park: { number }, pile: { number } } } = {
	docks = { park = { 1622, -12 }, pile = { 1636, -4 } }, -- by the cranes, ammo pallets behind
	frosty = { park = { 1162, 16 }, pile = { 1177, 20 } }, -- on the sidewalk next to the shop door
	farm = { park = { -1850, 490 }, pile = { -1862, 480 } }, -- the produce stand by the barn
	ranch = { park = { -858, 800 }, pile = { -842, 806 } }, -- in front of the stable
	stables = { park = { 650, 960 }, pile = { 662, 948 } }, -- in front of the riding school stable
	fueldepot = { park = { 1436, 565 }, pile = { 1452, 574 } }, -- under the loading shed
	gas = { park = { 150, -945 }, pile = { 165, -936 } }, -- the tank filler by the shop
	base = { park = { 282, -2420 }, pile = { 268, -2430 } }, -- the ammo bunker inside the gate
	lodge = { park = { -684, -2208 }, pile = { -699, -2200 } }, -- at the lodge door
	school = { park = { 14, 1124 }, pile = { 20, 1140 } }, -- the school gate
	movers = { park = { 349, 172 }, pile = { 337, 172 } }, -- the loading door, away from the WORK HERE board
	bank = { park = { 76, -292 }, pile = { 93, -292 } }, -- at the curb below the bank's steps (6th Ave)
	clinic = { park = { -219, 300 }, pile = { -237, 300 } }, -- under the emergency canopy (4th Ave)
	-- 3.0: every place has one now (the missions load and unload anywhere)
	radio = { park = { -1126, -590 }, pile = { -1140, -598 } }, -- at the station's door
	-- 3.0, the missions' places (server/World.luau keeps its props off these spots)
	pharmacy = { park = { 156, 366 }, pile = { 156, 381 } }, -- at the curb by the pharmacy's door
	market = { park = { -366, 128 }, pile = { -382, 128 } }, -- the delivery bay beside the car park
	warehouse = { park = { 1302, 270 }, pile = { 1318, 270 } }, -- in front of the open roller door
	firestation = { park = { 354, -116 }, pile = { 339, -116 } }, -- beside the truck bays
	police = { park = { -300, -222 }, pile = { -300, -238 } }, -- at the foot of the precinct's steps
	cityhall = { park = { -16, -366 }, pile = { -16, -382 } }, -- at the foot of City Hall's steps
	airfield = { park = { -1430, 1200 }, pile = { -1446, 1208 } }, -- the freight pallets by the hangar
	powerplant = { park = { 1080, 560 }, pile = { 1068, 572 } }, -- the loading dock inside the gate
	waterworks = { park = { 470, 770 }, pile = { 484, 760 } }, -- by the pump house
	lab = { park = { -190, -992 }, pile = { -204, -984 } }, -- the delivery door of the lab
	prison = { park = { -1580, -930 }, pile = { -1566, -940 } }, -- outside the gate, by the guard post
	lighthouse = { park = { 1550, -1068 }, pile = { 1564, -1060 } }, -- by the keeper's cottage
	trainyard = { park = { -232, -775 }, pile = { -246, -783 } }, -- the freight platform
	camp = { park = { -1050, -240 }, pile = { -1036, -232 } }, -- inside the barricade's gap
	stadium = { park = { 40, 1298 }, pile = { 52, 1308 } }, -- the relief tents by the gate
}
for id, spot in rawSpots do
	local dx, dz = spot.park[1] - spot.pile[1], spot.park[2] - spot.pile[2]
	local length = math.sqrt(dx * dx + dz * dz)
	cargoSpots[id] = {
		park = { x = spot.park[1], z = spot.park[2] },
		pile = { x = spot.pile[1], z = spot.pile[2] },
		facing = { x = dx / length, z = dz / length },
	}
end
Map.CargoSpots = cargoSpots

-- ── Freight (Zombie Delivery 4.0) ──────────────────────────────────────────
-- Where the pallets of the Freight Run (Config.JobTypes "freightrun", shared/Freight.luau) are loaded and set down.
-- server/World.luau builds the docks, server/Jobs.luau puts a job's stops there, server/Equipment.luau parks the pallet
-- jacks on their spots. Generic on purpose: a hub is a list of docks (a semi truck's longer bay is one more dock with
-- its own park and staging), a vehicle says itself how many pallets it takes (Economy.palletsOf).
--
-- A hub: raised dock platforms (`height` over the sidewalk: a truck's load floor) along a building; at each dock a
-- truck backs into its painted bay (`park`, the circle; `facing`, the way a truck backed in faces: away from the
-- dock) until its back touches the dock `edge`; the job's pallets wait on the dock floor (`staging`). The pallet jacks
-- stand on their spots (`jacks`, `facing` the way the forks point); the dock foreman stands at `giver`.
export type FreightDock = {
	park: { x: number, z: number },
	facing: { x: number, z: number },
	edge: { x: number, z: number },
	staging: { { x: number, z: number } },
}
export type JackSpot = { x: number, z: number, facing: { x: number, z: number } }
export type FreightHub = {
	place: string, -- the Map.Places id
	height: number, -- the dock floor over the sidewalk (WalkTop)
	platform: { x0: number, z0: number, x1: number, z1: number }, -- the raised dock floor
	giver: { x: number, z: number },
	docks: { FreightDock },
	jacks: { JackSpot },
}

-- The Harbor Warehouse (its block: the centre 1368, 288; the front wall at x = 1360 facing the avenue to the west;
-- the old mission door at z = 270 with its cargo spot stays as it was): two loading docks at the doors z = 294 and
-- z = 318, the platform 2.4 over the sidewalk reaching 10 out and 16 in, the pallets staged inside the doors.
Map.FreightDocks = {
	warehouse = {
		place = "warehouse",
		height = 2.4,
		platform = { x0 = 1350, z0 = 286, x1 = 1376, z1 = 326 },
		giver = { x = 1355, z = 306 },
		docks = {
			{
				park = { x = 1333, z = 294 },
				facing = { x = -1, z = 0 },
				edge = { x = 1350, z = 294 },
				staging = { { x = 1366, z = 290 }, { x = 1366, z = 298 }, { x = 1371.5, z = 290 }, { x = 1371.5, z = 298 } },
			},
			{
				park = { x = 1333, z = 318 },
				facing = { x = -1, z = 0 },
				edge = { x = 1350, z = 318 },
				staging = { { x = 1366, z = 314 }, { x = 1366, z = 322 }, { x = 1371.5, z = 314 }, { x = 1371.5, z = 322 } },
			},
		},
		jacks = {
			{ x = 1366, z = 304, facing = { x = -1, z = 0 } },
			{ x = 1366, z = 308, facing = { x = -1, z = 0 } },
		},
	},
} :: { [string]: FreightHub }

-- A receiving dock (the Freight Run's drop): a marked pad by a back door where the pallets are set down (`spots`, in
-- that order), the person who takes them at `receiver` (facing the pad), the place's own pallet jack on its spot
-- (every truck can unload, not only the Freight Truck with its own jack). The circle is the place's cargo spot park.
export type ReceivingDock = {
	place: string,
	spots: { { x: number, z: number } },
	receiver: { x: number, z: number },
	jack: JackSpot,
}
Map.ReceivingDocks = {
	-- FreshMart: on its car park by the delivery bay (the store faces east, the pile at -382, 128).
	market = {
		place = "market",
		spots = { { x = -395, z = 123.5 }, { x = -395, z = 128 }, { x = -395, z = 132.5 } },
		receiver = { x = -389, z = 138 },
		jack = { x = -402, z = 140, facing = { x = 0, z = -1 } },
	},
	-- Big Move Movers: in front of the orange shed's loading door (the shed faces east, its front at x = 301).
	movers = {
		place = "movers",
		spots = { { x = 318, z = 167.5 }, { x = 318, z = 172 }, { x = 318, z = 176.5 } },
		receiver = { x = 326, z = 180 },
		jack = { x = 309, z = 180, facing = { x = 0, z = -1 } },
	},
	-- The Power Plant: the stores by the loading dock inside the gate.
	powerplant = {
		place = "powerplant",
		spots = { { x = 1051.5, z = 566 }, { x = 1056, z = 566 }, { x = 1060.5, z = 566 } },
		receiver = { x = 1064, z = 574 },
		jack = { x = 1048, z = 575, facing = { x = 1, z = 0 } },
	},
} :: { [string]: ReceivingDock }

-- ── Real estate (Zombie Delivery 2.6) ──────────────────────────────────────
-- Where every property of Config.Estate stands (the same ids). server/World.luau builds them from this; the server's
-- Estate / CarCall / Business use the spots World registers (World.EstateSpawns, EstateGarages, EstatePrompts,
-- OfficePrompts); the client's EstateUi sets the GPS to them.
--
-- A plot's local frame: the origin is the centre of the main building on the ground, its front (the door, the garage
-- doors) faces `facing`, toward its road. The lot reaches `w` / 2 to either side, `front` studs forward (the front
-- wall; the driveway runs on from there to the road) and `back` studs back (the garden, the pool).
--
--   Mansions      Hilltop: on top of Sunset Hills north-east of Downtown, up the winding Sunset Drive (it carries
--                 on from 8th Ave at Downtown's north edge), facing the city. Ocean View: on the sea cliffs north of
--                 the Harbor, at the end of Cliff Road (Dock 4 on). Pinecrest: in the pines south of the West
--                 Highway, at the end of Pine Lane.
--   Villas        Lakeside: by the frozen lake, on the Lodge Road (in the snow). Sunset: at the end of Sunset Lane,
--                 a quiet lane west off the Radio Road.
--   Houses        three on ordinary lots of different Suburbs blocks and streets (the rest of their block stays as
--                 it is), Birch Cottage at the edge of town, at the end of Birch Lane west of the Suburbs
--   Garages       the Harbor Lockup (a Harbor block), the Highway Garage (by the North Highway), Downtown Parking
--                 (a downtown block in the safe zone); 3.4: the Rented Lockup and the Southside Garage south of
--                 Downtown, on the streets to the Suburbs
--   Offices       rooms on the upper floors of the two towers (Map.Towers); the lobby's elevator takes you up

Map.SunsetHills = { id = "sunsethills", name = "Sunset Hills", x0 = 360, z0 = -1290, x1 = 745, z1 = -690 } :: Area

export type EstatePlot = {
	x: number,
	z: number,
	facing: { x: number, z: number }, -- a unit direction along X or Z
	district: string, -- sunsethills | coast | countryside | north | west | suburbs | harbor | downtown | highway
	w: number,
	front: number,
	back: number,
	tower: string?, -- offices: their tower (Map.Towers id) and floor (1 = the lobby)
	floor: number?,
}

export type Tower = {
	id: string,
	name: string,
	x: number, -- the centre of the tower on the ground
	z: number,
	facing: { x: number, z: number }, -- its entrance faces this way
	floors: number, -- floor 1 is the lobby; the roof terrace is on top of the last floor
	floorHeight: number,
	w: number, -- square, this wide
	district: string,
}

local function facingOf(x: number, z: number): { x: number, z: number }
	return { x = x, z = z }
end

-- The two office towers. Every office is a floor of one of them (Map.EstatePlots[id].tower / floor).
Map.Towers = {
	dispatchtower = { id = "dispatchtower", name = "Dispatch Tower", x = -CELL, z = -CELL, facing = facingOf(1, 0), floors = 14, floorHeight = 12, w = 64, district = "downtown" },
	harborpoint = { id = "harborpoint", name = "Harbor Point", x = 1080 + 3 * CELL, z = -CELL, facing = facingOf(-1, 0), floors = 12, floorHeight = 12, w = 56, district = "harbor" },
} :: { [string]: Tower }

-- How high a tower floor's floor is above the ground (floor 1, the lobby: 0; the roof: floor `floors + 1`).
function Map.floorHeight(tower: Tower, floor: number): number
	return (floor - 1) * tower.floorHeight
end

-- A Suburbs lot: block (i, j), lot (a, b) in it (the same 2 x 2 lots server/World.luau lays out, SUBURB_INSET
-- inside the block's edge). Returns the lot's middle.
local SUBURB_INSET = 5
local SUBURB_LOT = (BLOCK - SUBURB_INSET * 2) / 2
Map.SuburbInset = SUBURB_INSET
Map.SuburbLot = SUBURB_LOT
function Map.suburbLot(i: number, j: number, a: number, b: number): (number, number)
	local suburbs = Map.Districts[3]
	local x = suburbs.ox + i * CELL - BLOCK / 2 + SUBURB_INSET + SUBURB_LOT * (a + 0.5)
	local z = suburbs.oz + j * CELL - BLOCK / 2 + SUBURB_INSET + SUBURB_LOT * (b + 0.5)
	return x, z
end
-- A house for sale on a Suburbs lot: it faces the nearer street (north for b = 0, south for b = 1) and stands
-- 5 studs forward of the lot's middle.
local function suburbHouse(i: number, j: number, a: number, b: number): EstatePlot
	local x, z = Map.suburbLot(i, j, a, b)
	local fz = if b == 0 then -1 else 1
	return { x = x, z = z + fz * 5, facing = facingOf(0, fz), district = "suburbs", w = 44, front = 10, back = 27 }
end

local function office(tower: Tower, floor: number): EstatePlot
	local half = tower.w / 2
	return { x = tower.x, z = tower.z, facing = tower.facing, district = tower.district, w = tower.w, front = half, back = half, tower = tower.id, floor = floor }
end

Map.EstatePlots = {
	-- The mansions, each in its own part of the map.
	hilltop = { x = 520, z = -1186, facing = facingOf(0, 1), district = "sunsethills", w = 110, front = 23, back = 66 },
	oceanview = { x = 1486, z = -720, facing = facingOf(-1, 0), district = "coast", w = 110, front = 23, back = 66 },
	pinecrest = { x = -1550, z = 806, facing = facingOf(0, -1), district = "countryside", w = 110, front = 23, back = 66 },
	-- The villas.
	lakeside = { x = -60, z = -2157, facing = facingOf(0, -1), district = "north", w = 78, front = 17, back = 40 },
	sunset = { x = -1460, z = -100, facing = facingOf(1, 0), district = "west", w = 78, front = 17, back = 30 },
	-- The houses: Suburbs lots on three different streets, and Birch Cottage at the edge of town.
	maple = suburbHouse(-1, 0, 0, 0),
	oak = suburbHouse(1, 1, 1, 0),
	elm = suburbHouse(-2, 1, 0, 1),
	birch = { x = -513, z = 900 + 2.5 * CELL, facing = facingOf(1, 0), district = "suburbs", w = 44, front = 10, back = 27 },
	-- The garages. 3.4: the two small ones come first (the Rented Lockup and the Southside Garage, both on the stretch
	-- between Downtown and the Suburbs, each on its own street), then the bigger ones.
	garage_rented = { x = -30, z = 738, facing = facingOf(-1, 0), district = "southside", w = 24, front = 9, back = 9 },
	garage_south = { x = 172, z = 738, facing = facingOf(1, 0), district = "southside", w = 32, front = 11, back = 11 },
	garage_harbor = { x = 1049, z = -432, facing = facingOf(-1, 0), district = "harbor", w = 52, front = 12, back = 12 },
	garage_north = { x = 119, z = -722, facing = facingOf(-1, 0), district = "highway", w = 52, front = 13, back = 13 },
	garage_downtown = { x = CELL, z = CELL - 4, facing = facingOf(0, 1), district = "downtown", w = 90, front = 34, back = 34 },
	-- The offices.
	office_harbor = office(Map.Towers.harborpoint, 7),
	office_tower = office(Map.Towers.dispatchtower, 8),
	office_penthouse = office(Map.Towers.dispatchtower, 14),
} :: { [string]: EstatePlot }

-- A point given in a plot's local frame on the map: `right` to the right of somebody looking out of the front door,
-- `back` behind the centre (the front wall is at back = -front).
function Map.plotPoint(plot: EstatePlot, right: number, back: number): (number, number)
	local fx, fz = plot.facing.x, plot.facing.z
	return plot.x - fz * right - fx * back, plot.z + fx * right - fz * back
end

-- Where a car comes out of a property's garage (homes and garages): this far in front of the front wall.
Map.GarageApron = 8

-- ── Venues (Zombie Delivery 5.3) ───────────────────────────────────────────
-- The real places the businesses (Config.Jobs.Businesses) work from: small storefronts on downtown (and two Suburbs)
-- lots, each facing its street (server/World.luau builds them from Map.lots; BuildingLooks has a look per kind). A
-- storefront is VenueSize big, its front wall VenueFront studs in from the curb, the door in the middle of it; the pile
-- (where the pieces wait and the cook / clerk hands them over) just outside the door, the park on the road at the curb
-- in front (the Map.CargoSpots rule: pile 8 – 20 studs from park), the clerk's spot just inside the door. The older
-- storefronts (the Corner Pharmacy, FreshMart, the bank, Frosty's, the Harbor Warehouse) are venues too (`built` false:
-- World builds them as before; their pile and park are their Map.CargoSpots).
export type Spot = { x: number, z: number }
export type Venue = {
	id: string, -- also its Map.Landmarks id (a new storefront) or its Map.Places id (an older one)
	business: string, -- the Config.Jobs.Businesses id
	name: string,
	kind: string, -- pizzeria | bakery | burgers | noodles | cafe | postoffice | news | hardware | electronics | pawnshop |
	-- flowers | pharmacy | supermarket | bank | icecream | warehouse
	sub: string, -- what it is, in caps (the location tag's second line, the name board's second line)
	icon: string, -- the map list's emoji
	about: string, -- the map list's line
	district: string,
	x: number, -- the middle of the building on the ground
	z: number,
	facing: Spot, -- the way its front (the door) faces: a unit direction along X or Z, toward its street
	door: Spot, -- the middle of the doorway (the front wall)
	park: Spot,
	pile: Spot,
	clerk: Spot, -- where the cook / clerk stands, just inside the door
	built: boolean, -- a new storefront (World builds it on its lot) or an older one
}
Map.VenueSize = { w = 30, d = 24, h = 12, door = 9, doorHeight = 8 } -- (BuildingLooks/Kit.luau's storefront: the same)
Map.VenueFront = 11 -- studs from the curb (the block's edge) to a storefront's front wall
Map.DowntownInset = 10 -- the downtown lots start this far inside the block's edge
Map.CurbPark = 6 -- the park: this far out on the road from the curb

local function districtById(id: string): District
	for _, d in Map.Districts do
		if d.id == id then
			return d
		end
	end
	error(`no district {id}`)
end
Map.districtById = districtById

-- The middle of lot (a, b) of block (i, j) (a: 0 west, 1 east; b: 0 north, 1 south) and the lot's size.
function Map.lotCentre(districtId: string, i: number, j: number, a: number, b: number): (number, number, number)
	local d = districtById(districtId)
	local inset = if d.style == "suburbs" then SUBURB_INSET else Map.DowntownInset
	local size = (BLOCK - inset * 2) / 2
	return d.ox + i * CELL - BLOCK / 2 + inset + size * (a + 0.5), d.oz + j * CELL - BLOCK / 2 + inset + size * (b + 0.5), size
end

do
	local SIZE = Map.VenueSize
	-- The new storefronts: on block (i, j), lot (a, b), facing (fx, fz) (the lot's outer side).
	local NEW: { { any } } = {
		-- id, business, name, kind, sub, icon, about, district, i, j, a, b, fx, fz
		{ "luigis", "pizzeria", "Luigi's Pizza", "pizzeria", "PIZZERIA", "🍕", "Downtown, south-east, on Ash St. Luigi's pizzas: hot, cheesy, best at night.", "downtown", 2, 2, 0, 1, 0, 1 },
		{ "dailybread", "bakery", "Daily Bread Bakery", "bakery", "BAKERY", "🥖", "Downtown, south, on Ash St. Anna bakes before sunrise: bread, rolls and cakes.", "downtown", -1, 3, 1, 0, 0, -1 },
		{ "lastbite", "burgers", "Last Bite Burgers", "burgers", "BURGERS", "🍔", "Downtown, west, on 3rd Ave. Burgers and fries, every one could be your last.", "downtown", -2, -1, 0, 1, -1, 0 },
		{ "wokdead", "noodles", "Wok Dead", "noodles", "NOODLES", "🍜", "Downtown, east, on Main St. Noodles in a box, hot from the wok.", "downtown", 3, 1, 1, 0, 0, -1 },
		{ "grindhouse", "cafe", "Grind House", "cafe", "CAFE · COFFEE", "☕", "The Suburbs, on Willow Ln, the first street from town. Coffee and pastries.", "suburbs", 0, 0, 0, 0, 0, -1 },
		{ "postoffice", "post", "Post Office", "postoffice", "MAIL · PARCELS", "📮", "Downtown, south of the park, on Ash St. Letters and parcels for every door.", "downtown", 0, 2, 1, 1, 0, 1 },
		{ "dailyundead", "news", "The Daily Undead", "news", "PRINT SHOP · NEWSSTAND", "📰", "Downtown, north of the park, on 5th Ave. The morning paper, still printed.", "downtown", 0, -2, 0, 0, -1, 0 },
		{ "boltnail", "hardware", "Bolt & Nail Hardware", "hardware", "HARDWARE", "🔨", "Downtown, far west, on 2nd Ave. Tools, nails, planks: everything to board up a house.", "downtown", -3, 2, 0, 1, -1, 0 },
		{ "volt", "electronics", "Volt Electronics", "electronics", "ELECTRONICS", "📻", "Downtown, north-east, on 8th Ave. Radios, batteries, parts.", "downtown", 3, -2, 0, 0, -1, 0 },
		{ "secondlife", "pawnshop", "Second Life Pawn", "pawnshop", "PAWN SHOP", "💰", "Downtown, far north-west, on Grave St. Vinnie buys and sells anything. Ammo too.", "downtown", -3, -3, 1, 1, 0, 1 },
		{ "bloom", "flowers", "Bloom", "flowers", "FLOWER SHOP", "💐", "The Suburbs, by the school, on Fern Rd. Flowers, still growing somewhere.", "suburbs", -1, 2, 1, 0, 1, 0 },
	}
	local venues: { Venue } = {}
	for _, row in NEW do
		local districtId, i, j, a, b, fx, fz = row[8], row[9], row[10], row[11], row[12], row[13], row[14]
		local d = districtById(districtId)
		local cx, cz = d.ox + i * CELL, d.oz + j * CELL
		local lx, lz = Map.lotCentre(districtId, i, j, a, b)
		local wall = BLOCK / 2 - Map.VenueFront
		-- the door on the front wall: along the facing axis at the wall, across it at the lot's middle
		local doorX = if fx ~= 0 then cx + fx * wall else lx
		local doorZ = if fz ~= 0 then cz + fz * wall else lz
		local out = BLOCK / 2 + Map.CurbPark
		table.insert(venues, {
			id = row[1],
			business = row[2],
			name = row[3],
			kind = row[4],
			sub = row[5],
			icon = row[6],
			about = row[7],
			district = districtId,
			x = doorX - fx * SIZE.d / 2,
			z = doorZ - fz * SIZE.d / 2,
			facing = { x = fx, z = fz },
			door = { x = doorX, z = doorZ },
			pile = { x = doorX + fx * 2.5, z = doorZ + fz * 2.5 },
			park = { x = if fx ~= 0 then cx + fx * out else lx, z = if fz ~= 0 then cz + fz * out else lz },
			clerk = { x = doorX - fx * 3 + fz * 3.5, z = doorZ - fz * 3 - fx * 3.5 },
			built = true,
		})
	end
	-- The older storefronts, from their places and cargo spots.
	for _, row in {
		{ "pharmacy", "pharmacy", "pharmacy", "PHARMACY", "💊" },
		{ "market", "supermarket", "supermarket", "SUPERMARKET", "🛒" },
		{ "bank", "bank", "bank", "BANK", "🏦" },
		{ "frosty", "icecream", "icecream", "ICE CREAM", "🍦" },
		{ "warehouse", "warehouse", "warehouse", "WAREHOUSE", "📦" },
	} do
		for _, place in Map.Places do
			local spot = Map.CargoSpots[place.id]
			if place.id ~= row[1] or not spot then
				continue
			end
			-- the block behind the place (Map.blockAt comes further down)
			local bx, bz = place.x - place.nx * 30, place.z - place.nz * 30
			local d: District? = nil
			local i, j = 0, 0
			for _, district in Map.Districts do
				local di, dj = math.floor((bx - district.ox) / CELL + 0.5), math.floor((bz - district.oz) / CELL + 0.5)
				if di >= district.i0 and di <= district.i1 and dj >= district.j0 and dj <= district.j1 then
					d, i, j = district, di, dj
				end
			end
			local fx, fz = place.nx, place.nz
			local doorX, doorZ = spot.pile.x - fx * 2.5, spot.pile.z - fz * 2.5
			table.insert(venues, {
				id = place.id,
				business = row[2],
				name = place.name,
				kind = row[3],
				sub = row[4],
				icon = row[5],
				about = "",
				district = if d then d.id else "",
				x = if d then d.ox + i * CELL else place.x,
				z = if d then d.oz + j * CELL else place.z,
				facing = { x = fx, z = fz },
				door = { x = doorX, z = doorZ },
				park = { x = spot.park.x, z = spot.park.z },
				pile = { x = spot.pile.x, z = spot.pile.z },
				clerk = { x = doorX - fx * 3, z = doorZ - fz * 3 },
				built = false,
			})
		end
	end
	Map.Venues = venues
end

-- A venue by its id (nil: none).
function Map.venue(id: string): Venue?
	for _, venue in Map.Venues do
		if venue.id == id then
			return venue
		end
	end
	return nil
end

-- The venues of a business (Config.Jobs.Businesses id; the bakery also bakes the cakes: "cake" is the bakery's).
function Map.venuesOf(business: string): { Venue }
	local id = if business == "cake" then "bakery" else business
	local list = {}
	for _, venue in Map.Venues do
		if venue.business == id then
			table.insert(list, venue)
		end
	end
	return list
end

-- ── Gas stations (Zombie Delivery 5.4) ─────────────────────────────────────
-- Where the cars refuel (Config.Fuel, server/Fuel.luau): the pumps' Refuel prompts, the kiosk's jerry cans, the tow's
-- destination. The old Gas Station on the North Highway (its yard "gas"; an employer too: the Fuel Run brings its fuel
-- from the Harbor Fuel Depot) got Codex's pumps; three more stand on the town's lots, each built from
-- server/GasArt/Layout.luau (a 70 x 50 station: the island with two pumps under a canopy, the kiosk, the price sign),
-- its front (the layout's -Z) to its street:
--   Westside Gas  Downtown block (-4, 1), its south row of lots (lot kind "gas"), on the street the West Highway starts from
--   Harbor Gas    the Harbor block (0, 0) (a special block "gas"), on the street the Rust Bridge comes in on
--   Willow Gas    Suburbs block (1, 0), its north row of lots, on Willow Ln (the first street from town)
-- A station's (x, z) is the middle of its floor; `pumps` are where its pumps stand and `bays` where a car stands
-- beside one (looking `look`: out of the station; the tow puts a car there), all on the map. A lot station's pumps
-- and bays come from GasLayout (= GasArt/Layout: the island at (-16, -6), its pumps 4 studs either side of it along Z,
-- the bays 5.2 studs out across; tests/fuel_test.luau and server/World.luau check them).
export type GasBay = { x: number, z: number, look: Spot, pump: number }
export type GasStation = {
	id: string, -- its Map.Landmarks id ("gas": the old one, an employer's landmark; the others "gas_…")
	name: string,
	x: number,
	z: number,
	facing: Spot, -- the front (a unit direction along X or Z)
	about: string, -- the map list's line (a new station)
	district: string?, -- a lot station: its block (i, j) and its row of lots (b: 0 north, 1 south); nil: a yard / special block
	i: number?,
	j: number?,
	b: number?,
	pumps: { Spot },
	bays: { GasBay },
}
Map.GasLayout = {
	width = 70, -- across the front (the layout's X)
	depth = 50, -- front to back (its Z)
	pumps = { { -16, -10 }, { -16, -2 } } :: { { number } }, -- (x, z) in the layout's frame
	bays = { { -21.2, -10, 1 }, { -10.8, -10, 1 }, { -21.2, -2, 2 }, { -10.8, -2, 2 } } :: { { number } }, -- (x, z, pump)
	inset = 5, -- the front: this far inside the block's edge (the curb)
}
do
	-- A point of a station's frame (right of somebody looking out of the front, back from the middle) on the map.
	local function at(x: number, z: number, fx: number, fz: number, right: number, back: number): Spot
		return { x = x - fz * right - fx * back, z = z + fx * right - fz * back }
	end
	local stations: { GasStation } = {
		{
			id = "gas",
			name = "Gas Station",
			x = 136,
			z = -900,
			facing = { x = -1, z = 0 },
			about = "",
			-- the two pumps under the old canopy (server/World.luau buildGas), their fronts to the highway
			pumps = { { x = 136, z = -909 }, { x = 136, z = -891 } },
			bays = { { x = 136, z = -914.5, look = { x = -1, z = 0 }, pump = 1 }, { x = 136, z = -885.5, look = { x = -1, z = 0 }, pump = 2 } },
		},
	}
	local LAYOUT = Map.GasLayout
	for _, row in {
		-- id, name, about, district, i, j, b (the lot row; -1: a special block), fx, fz
		{ "gas_downtown", "Westside Gas", "Downtown's west edge, on Cedar St where the West Highway starts. Fuel at the pumps, jerry cans in the kiosk.", "downtown", -4, 1, 1, 0, 1 },
		{ "gas_harbor", "Harbor Gas", "In the Harbor, where the Rust Bridge comes over. Fuel at the pumps, jerry cans in the kiosk.", "harbor", 0, 0, -1, 0, 1 },
		{ "gas_suburbs", "Willow Gas", "The Suburbs, on Willow Ln, the first street from town. Fuel at the pumps, jerry cans in the kiosk.", "suburbs", 1, 0, 0, 0, -1 },
		-- 6.12.7 (the owner: "one or two gas stations closer"): two just outside the safe zone, their fronts on its
		-- corner streets: east of Dead End Motors, a block from the depot, and west of the Dispatch Tower. Their rows held
		-- apartments and a car park (no storefront, zip line or alley: tests/fuel_test.luau).
		{ "gas_depot", "Depot Gas", "Just outside the safe zone, east of Dead End Motors: a block from the depot. Fuel at the pumps, jerry cans in the kiosk.", "downtown", 2, 0, 0, 0, -1 },
		{ "gas_tower", "Tower Gas", "Just outside the safe zone, west of the Dispatch Tower. Fuel at the pumps, jerry cans in the kiosk.", "downtown", -2, -1, 0, 0, -1 },
	} :: { { any } } do
		local d = districtById(row[4])
		local i, j, b, fx, fz = row[5], row[6], row[7], row[8], row[9]
		local cx, cz = d.ox + i * CELL, d.oz + j * CELL
		-- the front LAYOUT.inset inside the block's edge, the middle of the row (or the block) across
		local out = BLOCK / 2 - LAYOUT.inset - LAYOUT.depth / 2
		local x, z = cx + fx * out, cz + fz * out
		if b >= 0 then
			local lx = Map.lotCentre(row[4], i, j, 0, b)
			local rx = Map.lotCentre(row[4], i, j, 1, b)
			if fz ~= 0 then
				x = (lx + rx) / 2
			end
		end
		local station: GasStation = {
			id = row[1],
			name = row[2],
			x = x,
			z = z,
			facing = { x = fx, z = fz },
			about = row[3],
			district = if b >= 0 then row[4] else nil,
			i = if b >= 0 then i else nil,
			j = if b >= 0 then j else nil,
			b = if b >= 0 then b else nil,
			pumps = {},
			bays = {},
		}
		for _, p in LAYOUT.pumps do
			table.insert(station.pumps, at(x, z, fx, fz, p[1], p[2]))
		end
		for _, p in LAYOUT.bays do
			local spot = at(x, z, fx, fz, p[1], p[2])
			table.insert(station.bays, { x = spot.x, z = spot.z, look = { x = fx, z = fz }, pump = p[3] })
		end
		table.insert(stations, station)
	end
	Map.GasStations = stations
end

-- A gas station by its id (nil: none).
function Map.gasStation(id: string): GasStation?
	for _, station in Map.GasStations do
		if station.id == id then
			return station
		end
	end
	return nil
end

-- The gas station nearest to (x, z) (straight line) and how far it is.
function Map.nearestGas(x: number, z: number): (GasStation, number)
	local best, bestD = Map.GasStations[1], math.huge
	for _, station in Map.GasStations do
		local d = math.sqrt((station.x - x) ^ 2 + (station.z - z) ^ 2)
		if d < bestD then
			best, bestD = station, d
		end
	end
	return best, bestD
end

-- (kind: shop | employer | place | venue, 5.3: a storefront of Map.Venues)
export type Landmark = { id: string, name: string, icon: string, x: number, z: number, kind: string, description: string }

-- Everything worth driving to, for the map's list and the GPS. 6.7: every shop's line says what it really sells; the
-- depot sells nothing (its Depot Garage is the garage terminal: client/MapView.luau lists it on its own, not as a shop).
local landmarks: { Landmark } = {
	{ id = "depot", name = "Depot (your company)", icon = "📦", x = Map.Depot.x, z = Map.Depot.z, kind = "shop", description = "Your company, north-east of the Central Park (the giant parcel on its roof): the JOBS spot with the job board, Marge, the garage terminal (your parked van, the company vehicles) and the gear stall by the spawn (ZDC Bags and Last Stop Supplies). The safe zone." },
	-- 6.11: the Central Park in the middle of the safe zone (Map.Park).
	{ id = "park", name = Map.Park.name, icon = "🌳", x = Map.Park.x, z = Map.Park.z, kind = "place", description = "The middle of the city and of the safe zone: the pond with the fountain on its island, benches under the trees, the shops all round it. The depot is across the junction to the north-east." },
	-- 6.12.7: one shop for the cars and the bikes (the CARS and BIKES counters; Spoke & Chain's own entry is gone)
	{ id = "dealer", name = "Dead End Motors", icon = "🚗", x = CELL, z = 0, kind = "shop", description = "Cars, vans and trucks, each with a role (the first van comes from Earl, Marge's quest at level 4); every car needs a garage slot. And at the BIKES counter, from level 2: bikes, the E-Scooter and bike gear (a basket, panniers, a trailer), faster than walking with more room for the light runs." },
	{ id = "guns", name = "Lead & Co.", icon = "🔫", x = -CELL, z = 0, kind = "shop", description = "Guns from the SMG up (your pistol is the starter), the gun upgrades (Gun Damage, Fire Rate) and a baseball bat." },
	{ id = "mechanic", name = "Wrench Garage", icon = "🔧", x = 0, z = CELL, kind = "shop", description = "Your car's stages, car upgrades, gear, paint and car guns, and two repair bays: drive in, get out, wait." },
	{ id = "repairs", name = "Rust Bridge Repairs", icon = "🔧", x = 1080, z = CELL, kind = "shop", description = "A repair shop in the Harbor, where the Rust Bridge comes over: two repair bays. Drive in, get out, wait." },
	{ id = "bags", name = Config.BagShop.Name, icon = "🛍️", x = Map.Shops.bags.x, z = Map.Shops.bags.z, kind = "shop", description = "Bags: sprint with your deliveries. The BAGS counter of the gear stall in the depot's yard, by the spawn." }, -- 6.6 (6.12.2: the stall)
	-- 6.12.2: the GEAR counter of the gear stall in the depot's yard (no running shoes any more)
	{ id = "supplies", name = "Last Stop Supplies", icon = "🛒", x = Map.Shops.supplies.x, z = Map.Shops.supplies.z, kind = "shop", description = "Items: medkits, energy drinks, molotovs, and for a car repair kits, nitro, landmines, jerry cans. Vests (the Courier Vest, Kevlar, heavy armour). The GEAR counter of the gear stall in the depot's yard, by the spawn." },
	-- (5.1: Spoke & Chain Cycles had its own entry here; 6.12.7: the bikes are Dead End Motors' BIKES counter, above)
	-- 5.0: Earl sells his old van here (Config.VanQuest): your first vehicle.
	{ id = "earl", name = "Earl's Used Wheels", icon = "🚐", x = Map.VanSeller.earl.x, z = Map.VanSeller.earl.z, kind = "place", description = "Far out west on the West Highway, past the Airfield Road. Earl sells his old van here: your first vehicle (Marge's quest at level 4)." },
}
-- Where each employer is, in a few words (the map's list).
local EMPLOYER_WHERE: { [string]: string } = {
	school = "In the Suburbs.",
	army = "North, through the Mount Rot tunnel.",
	icecream = "In the Harbor.",
	movers = "Downtown.",
	farm = "At the end of the West Highway.",
	ranch = "Off the West Highway, down the Ranch Road.",
	gas = "On the North Highway.",
	clinic = "Downtown, south-west of the park.",
}
for _, employer in Config.Employers do
	local spot = Map.EmployerSpots[employer.id]
	local reward = employer.reward
	for _, car in Config.Cars do
		if car.id == employer.reward then
			reward = car.name
		end
	end
	local gun: string? = nil
	for _, weapon in Config.Weapons do
		if employer.weapon and weapon.id == employer.weapon then
			gun = weapon.name
		end
	end
	local where = EMPLOYER_WHERE[employer.id]
	local text = `{if where then where .. " " else ""}Work for {employer.person}.`
	if gun and employer.weaponAt then
		text ..= ` After {employer.weaponAt} jobs you earn the {gun}, after {employer.needed} the {reward} is yours.`
	else
		text ..= ` After {employer.needed} jobs the {reward} is yours.`
	end
	if spot then
		table.insert(landmarks, {
			id = employer.id,
			name = employer.name,
			icon = employer.icon,
			x = spot.x,
			z = spot.z,
			kind = "employer",
			description = text,
		})
	end
end
-- The far places that are not an employer's (the Gas Station and the Old Farm are listed as employers).
for _, info in {
	{ "lodge", "⛷️", "Far north, across the frozen lake." },
	{ "radio", "📡", "At the end of the Radio Road." },
	{ "docks", "⚓", "The harbor, on the sea. Army ammo is loaded here." },
	{ "stables", "🐎", "By the river, down Riding School Lane from the Suburbs. The ranch horses go here." },
	{ "fueldepot", "🛢️", "South of the Harbor. Fuel barrels for the Gas Station." },
	{ "bank", "🏦", "Downtown, just north of the safe zone. The cash transports load here." },
	-- 3.0, the missions' places
	{ "pharmacy", "💊", "Downtown, south of the park. Pills, bandages and the last vaccines in town." },
	{ "market", "🛒", "Downtown, west of the park. FreshMart: not so fresh any more, but still open." },
	{ "warehouse", "📦", "In the Harbor. Roller doors, forklifts and crates of everything." },
	{ "firestation", "🚒", "Downtown, east of the depot, across 7th Ave. Fire Station 9: red trucks, brave crews." },
	{ "police", "🚓", "Downtown, north-west of the park. Precinct 13: what is left of the law." },
	{ "cityhall", "🏛️", "Downtown, north of the park. The mayor still holds office here." },
	{ "airfield", "✈️", "Far south-west, down the Airfield Road off the West Highway. A runway and an old plane." },
	{ "powerplant", "⚡", "South of the Harbor. The chimneys that keep the city's lights on." },
	{ "waterworks", "💧", "By the river, south-east of Downtown. Clean water for everybody." },
	{ "lab", "🧪", "North of Downtown, off the North Highway. Biotech Lab: they are working on a cure." },
	{ "prison", "⛓️", "Far north-west, at the end of Blackrock Road. Walls, towers, a gate." },
	{ "lighthouse", "🗼", "On the coast north of Ocean View, past the end of Cliff Road." },
	{ "trainyard", "🚂", "Just north of Downtown. Rails, wagons and the freight platform." },
	{ "camp", "⛺", "West of Downtown, on the Radio Road. Tents and barricades: survivors live here." },
	{ "stadium", "🏟️", "South of the Suburbs. The stadium is a shelter now: tents on the field." },
} do
	for _, place in Map.Places do
		if place.id == info[1] then
			table.insert(landmarks, { id = place.id, name = place.name, icon = info[2], x = place.x, z = place.z, kind = "place", description = info[3] })
		end
	end
end
-- 5.3, the new storefronts (Map.Venues that World builds): on the road in front of their door.
for _, venue in Map.Venues do
	if venue.built then
		table.insert(landmarks, { id = venue.id, name = venue.name, icon = venue.icon, x = venue.park.x, z = venue.park.z, kind = "venue", description = venue.about })
	end
end
-- 5.4, the new gas stations (Map.GasStations; the old one is the Gas Station employer's): on the road in front.
for _, station in Map.GasStations do
	if station.id ~= "gas" then
		local out = Map.GasLayout.depth / 2 + Map.GasLayout.inset + Map.CurbPark
		table.insert(landmarks, { id = station.id, name = station.name, icon = "⛽", x = station.x + station.facing.x * out, z = station.z + station.facing.z * out, kind = "place", description = station.about })
	end
end
-- Zombie Delivery 2.6, the real estate: Sunset Hills (on Sunset Drive), the other mansions and the villas (at their
-- gates), the two towers (at their doors) and the garages (at their doors). The houses in the Suburbs are found
-- through the ESTATE list (client/EstateUi.luau).
do
	local function towerDoor(tower: Tower): (number, number)
		local out = tower.w / 2 + 12
		return tower.x + tower.facing.x * out, tower.z + tower.facing.z * out
	end
	local dispatchX, dispatchZ = towerDoor(Map.Towers.dispatchtower)
	local harborX, harborZ = towerDoor(Map.Towers.harborpoint)
	table.insert(landmarks, { id = "sunsethills", name = "Sunset Hills", icon = "🏡", x = 600, z = -900, kind = "place", description = "Above the city, north-east of Downtown: the winding Sunset Drive up to the Hilltop Mansion, the whole city at your feet. A home to spawn at and a garage for eight." })
	table.insert(landmarks, { id = "dispatchtower", name = "Dispatch Tower", icon = "🏢", x = dispatchX, z = dispatchZ, kind = "place", description = "Downtown, by the park, two blocks west of the depot. Offices for sale on the 8th floor and the penthouse: run your own delivery company. Take the elevator in the lobby." })
	table.insert(landmarks, { id = "harborpoint", name = "Harbor Point", icon = "🏙️", x = harborX, z = harborZ, kind = "place", description = "In the Harbor, by the docks. An office for sale on the 7th floor: start your own delivery company. Take the elevator in the lobby." })
	local WHERE: { [string]: string } = {
		oceanview = "On the sea cliffs north of the Harbor, up Cliff Road.",
		pinecrest = "In the pines south of the West Highway, down Pine Lane.",
		lakeside = "Far north by the frozen lake, on the Lodge Road.",
		sunset = "In the west, at the end of Sunset Lane off the Radio Road.",
	}
	for _, def in Config.Estate.Properties do
		local plot = Map.EstatePlots[def.id]
		if not plot then
			continue
		end
		local x, z = Map.plotPoint(plot, 0, -(plot.front + Map.GarageApron))
		if def.kind == "garage" then
			table.insert(landmarks, { id = def.id, name = def.name, icon = "🅿️", x = x, z = z, kind = "place", description = `For sale. {def.description}` })
		elseif WHERE[def.id] then
			table.insert(landmarks, { id = def.id, name = def.name, icon = if def.kind == "villa" then "🏠" else "🏰", x = x, z = z, kind = "place", description = `{WHERE[def.id]} For sale. {def.description}` })
		end
	end
end
Map.Landmarks = landmarks

-- ── Day and night ──────────────────────────────────────────────────────────
-- The clock (Lighting.ClockTime, 0 – 24) runs over Config.DayNight.DayLength. It is night from NightFrom to NightTo;
-- the look fades over NIGHT_FADE hours on either side of both (dusk and dawn).

local NIGHT_FADE = 1

-- Is it night at this hour (the street lamps and the headlights are on, more zombies, better pay)?
function Map.isNight(hour: number): boolean
	local h = hour % 24
	return h >= Config.DayNight.NightFrom or h < Config.DayNight.NightTo
end

-- 0 in full day … 1 in deep night, smooth through dusk and dawn (0.5 right when the night starts or ends).
function Map.nightFactor(hour: number): number
	local h = hour % 24
	local function ramp(edge: number): number -- 0 before the fade, 1 after it, smoothstep in between
		local t = math.clamp((h - (edge - NIGHT_FADE)) / (2 * NIGHT_FADE), 0, 1)
		return t * t * (3 - 2 * t)
	end
	-- The evening fades in toward NightFrom, the morning out toward NightTo (noon splits them).
	if h >= 12 then
		return ramp(Config.DayNight.NightFrom)
	end
	return 1 - ramp(Config.DayNight.NightTo)
end

-- ── Roads ──────────────────────────────────────────────────────────────────

local function districtEdges(d: District): (number, number, number, number)
	-- centre lines of the outer roads
	return d.ox + (d.i0 - 0.5) * CELL, d.ox + (d.i1 + 0.5) * CELL, d.oz + (d.j0 - 0.5) * CELL, d.oz + (d.j1 + 0.5) * CELL
end
Map.districtEdges = districtEdges

local connectors: { Segment } = {}
local function line(points: { { number } }, width: number, kind: string, name: string?)
	for n = 1, #points - 1 do
		local a, b = points[n], points[n + 1]
		table.insert(connectors, { ax = a[1], az = a[2], bx = b[1], bz = b[2], width = width, kind = kind, name = name })
	end
end

local downtownEdge = 4.5 * CELL + ROAD / 2 -- 665
local harborWest = 1080 - 0.5 * CELL - ROAD / 2 -- 991
line({ { downtownEdge, 0.5 * CELL }, { harborWest, 0.5 * CELL } }, ROAD, "bridge", "Rust Bridge")
line({ { downtownEdge, -2.5 * CELL }, { harborWest, -2.5 * CELL } }, ROAD, "bridge", "Old Bridge")
local suburbsNorth = 900 - 0.5 * CELL - ROAD / 2 -- 811
for k = -3, 2 do
	line({ { (k + 0.5) * CELL, downtownEdge }, { (k + 0.5) * CELL, suburbsNorth } }, ROAD, "street")
end
line({ { 0.5 * CELL, -downtownEdge }, { 0.5 * CELL, -1000 }, { 300, -1240 }, { 300, -2360 } }, HIGHWAY, "highway", "North Highway")
line({ { -downtownEdge, 1.5 * CELL }, { -1100, 1.5 * CELL }, { -1400, 520 }, { -1730, 520 } }, HIGHWAY, "highway", "West Highway")
line({ { -1100, 1.5 * CELL }, { -1100, -460 } }, HIGHWAY, "highway", "Radio Road")
line({ { 300 - HIGHWAY / 2, -2200 }, { Map.Lake.x1, -2200 } }, HIGHWAY, "highway", "Lodge Road")
line({ { Map.Lake.x1, -2200 }, { -530, -2200 } }, HIGHWAY, "ice", "Ice Road")
-- Country roads: they start on another road's centre line (a T-junction) and end at their yard.
line({ { -900, 1.5 * CELL }, { -900, 700 } }, ROAD, "street", "Ranch Road")
line({ { 2.5 * CELL, 900 + 0.5 * CELL }, { 580, 900 + 0.5 * CELL } }, ROAD, "street", "Riding School Lane")
-- The real estate's roads (2.6). Sunset Drive carries on from 8th Ave at Downtown's north edge and winds up Sunset
-- Hills to the Hilltop Mansion's turning circle; the lanes are short dead ends to the other homes.
Map.SunsetDrive = { { 3.5 * CELL, -downtownEdge + ROAD / 2 }, { 504, -760 }, { 600, -850 }, { 600, -960 }, { 520, -1050 }, { 520, -1140 } }
line(Map.SunsetDrive, ROAD, "street", "Sunset Drive")
line({ { 1080 + 2.5 * CELL, -3.5 * CELL }, { 1080 + 2.5 * CELL, -820 } }, ROAD, "street", "Cliff Road") -- Ocean View
line({ { -1550, 520 }, { -1550, 760 } }, ROAD, "street", "Pine Lane") -- Pinecrest, off the West Highway
line({ { -1100, -100 }, { -1420, -100 } }, ROAD, "street", "Sunset Lane") -- the Sunset Villa, off the Radio Road
line({ { -2.5 * CELL, 900 + 2.5 * CELL }, { -480, 900 + 2.5 * CELL } }, ROAD, "street", "Birch Lane") -- Birch Cottage
Map.EstateRoads = { "Sunset Drive", "Cliff Road", "Pine Lane", "Sunset Lane", "Birch Lane" }
-- The roads to the missions' places out of town (3.0). Each starts on another road's centre line (a T-junction or the
-- end of a road) and ends at the edge of its yard. (The Power Plant, the Survivor Camp and the Stadium Shelter lie
-- right along a road and need none.)
line({ { -1400, 520 }, { -1400, 1150 } }, ROAD, "street", "Airfield Road") -- off the West Highway's bend
line({ { 2.5 * CELL, 780 }, { 430, 780 } }, ROAD, "street", "Waterworks Road") -- off the street to the Suburbs
line({ { 0.5 * CELL, -1000 }, { -150, -1000 } }, ROAD, "street", "Lab Road") -- off the North Highway's bend
line({ { -1100, -380 }, { -1600, -380 }, { -1600, -900 } }, ROAD, "street", "Blackrock Road") -- off the Radio Road
line({ { 1080 + 2.5 * CELL, -820 }, { 1080 + 2.5 * CELL, -1080 }, { 1520, -1080 } }, ROAD, "street", "Lighthouse Road") -- on from Cliff Road
line({ { -1.5 * CELL, -4.5 * CELL }, { -1.5 * CELL, -740 } }, ROAD, "street", "Rail Yard Road") -- north from Downtown's edge
Map.PlaceRoads = { "Airfield Road", "Waterworks Road", "Lab Road", "Blackrock Road", "Lighthouse Road", "Rail Yard Road" }

Map.Connectors = connectors

-- Every road centre line (the district grids and the connectors).
local segments: { Segment } = {}
for _, d in Map.Districts do
	local x0, x1, z0, z1 = districtEdges(d)
	for k = d.i0 - 1, d.i1 do
		local x = d.ox + (k + 0.5) * CELL
		table.insert(segments, { ax = x, az = z0, bx = x, bz = z1, width = ROAD, kind = "grid" })
	end
	for k = d.j0 - 1, d.j1 do
		local z = d.oz + (k + 0.5) * CELL
		table.insert(segments, { ax = x0, az = z, bx = x1, bz = z, width = ROAD, kind = "grid" })
	end
end
for _, s in connectors do
	table.insert(segments, s)
end
Map.Segments = segments

local function closestOnSegment(s: Segment, x: number, z: number): (number, number, number)
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
	local px, pz = s.ax + dx * t, s.az + dz * t
	return px, pz, (x - px) ^ 2 + (z - pz) ^ 2
end

-- The closest point on any road centre line and that road's direction (unit) and width.
function Map.nearestRoad(x: number, z: number): (number, number, number, number, number)
	local best: Segment = segments[1]
	local bx, bz, bestD = closestOnSegment(best, x, z)
	for n = 2, #segments do
		local s = segments[n]
		local px, pz, d = closestOnSegment(s, x, z)
		if d < bestD then
			best, bx, bz, bestD = s, px, pz, d
		end
	end
	local dx, dz = best.bx - best.ax, best.bz - best.az
	local length = math.sqrt(dx * dx + dz * dz)
	return bx, bz, dx / length, dz / length, best.width
end

function Map.inYard(x: number, z: number): Area?
	for _, yard in Map.Yards do
		if x >= yard.x0 and x <= yard.x1 and z >= yard.z0 and z <= yard.z1 then
			return yard
		end
	end
	return nil
end

-- On asphalt: a road or a yard.
function Map.onRoad(x: number, z: number): boolean
	for _, s in segments do
		local _, _, d = closestOnSegment(s, x, z)
		if d <= (s.width / 2) ^ 2 + 1e-6 then
			return true
		end
	end
	return Map.inYard(x, z) ~= nil
end

function Map.isSafe(x: number, z: number): boolean
	local half = Config.City.SafeHalf
	return math.abs(x) < half and math.abs(z) < half
end

function Map.inWater(x: number, z: number): boolean
	return (x > Map.River.x0 and x < Map.River.x1) or x > Map.Sea.x0
end

function Map.isWinter(x: number, z: number): boolean
	return z < Map.WinterZ and x < Map.River.x0
end

function Map.onIce(x: number, z: number): boolean
	local lake = Map.Lake
	return x > lake.x0 and x < lake.x1 and z > lake.z0 and z < lake.z1
end

function Map.manhattan(ax: number, az: number, bx: number, bz: number): number
	return math.abs(ax - bx) + math.abs(az - bz)
end

-- The district (and block) a point is in, if any.
function Map.blockAt(x: number, z: number): (District?, number, number)
	for _, d in Map.Districts do
		local i = math.floor((x - d.ox) / CELL + 0.5)
		local j = math.floor((z - d.oz) / CELL + 0.5)
		if i >= d.i0 and i <= d.i1 and j >= d.j0 and j <= d.j1 then
			local cx, cz = d.ox + i * CELL, d.oz + j * CELL
			if math.abs(x - cx) < BLOCK / 2 and math.abs(z - cz) < BLOCK / 2 then
				return d, i, j
			end
		end
	end
	return nil, 0, 0
end

-- A small deterministic generator (the same world on every server, also in the tests).
function Map.lcg(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local addressCache: { Address }? = nil

-- Two addresses on every ordinary block (on the road just outside one side of it) and every named place.
function Map.addresses(): { Address }
	if addressCache then
		return addressCache
	end
	local rand = Map.lcg(Config.City.Seed + 99)
	local list: { Address } = {}
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				-- (5.4: a gas station's special block rolls its dice like the ordinary block it was, so every other
				-- block's addresses stay as they were, and holds none; 6.11: so does the depot's, Map.FormerBlocks)
				local special = Map.special(d.id, i, j)
				if special and not Map.wasOrdinary(d.id, i, j) then
					continue
				end
				local first = math.floor(rand() * 4) + 1
				for n = 0, 1 do
					local side = SIDES[(first + n * 2 - 1) % 4 + 1]
					local nx, nz = side[1], side[2]
					local cx, cz = d.ox + i * CELL, d.oz + j * CELL
					local along = (rand() - 0.5) * (BLOCK - 40)
					local out = BLOCK / 2 + 6
					local x = cx + nx * out + (if nz ~= 0 then along else 0)
					local z = cz + nz * out + (if nx ~= 0 then along else 0)
					local number = math.floor(rand() * 90) + 10
					local name: string
					if nz ~= 0 then
						local k = j + (if nz > 0 then 0 else -1) - d.j0 + 1
						name = `{number} {d.streets[k % #d.streets + 1]}`
					else
						local k = i + (if nx > 0 then 0 else -1) - d.i0 + 1
						name = `{number} {d.avenues[k % #d.avenues + 1]}`
					end
					if Map.isSafe(x, z) or special then
						continue
					end
					table.insert(list, { x = x, z = z, nx = nx, nz = nz, name = name, district = d.name, poi = false })
				end
			end
		end
	end
	for _, place in Map.Places do
		table.insert(list, { x = place.x, z = place.z, nx = place.nx, nz = place.nz, name = place.name, district = place.name, poi = true })
	end
	addressCache = list
	return list
end

-- ── Lots and homes (Zombie Delivery 5.3) ───────────────────────────────────
-- What stands on every lot of the ordinary Downtown and Suburbs blocks, decided here with Map.lcg (the same on every
-- server, in the client and in the tests), so the builder (server/World.luau), the jobs and the client know the same
-- buildings. A block has 2 x 2 lots (a: 0 west, 1 east; b: 0 north, 1 south), DowntownInset / SuburbInset in from its
-- edge; every lot touches two streets (its outer sides).
--   Downtown  a storefront (Map.Venues), else 70 % a tower, 15 % a lawn with trees, 15 % a parking lot with a wreck.
--             5.5: every tower that can face one of its streets (a free park) is an apartment building with a real
--             entrance there (a home: its residents in shared/Residents.luau); one with no free street stays a plain,
--             doorless tower. The towers stand in the middle of their lot as before (the entrance on the street wall).
--   Suburbs   a storefront, a house for sale (Map.EstatePlots: World's estate code builds it), else 85 % a house with
--             its front door to one of its two streets (houses face all four ways), a short path to the sidewalk, a
--             mailbox and its number, 15 % a burnt-out wreck.
-- The special blocks have no lots (their own builders), the Harbor has none (warehouses and containers). No home or
-- storefront faces a street where its park would be in the safe zone or within FreeRadius of a place, a cargo spot,
-- an employer's board, a storefront's park or (5.5) a gas station's pumps and bays (the jobs there have their own
-- spots), nor (5.5) within ParkGap of another home's park.
--
-- Every home (Map.Homes) has the Map.CargoSpots shape: the door (the middle of the front wall), the pile just outside it
-- (the receiver waits there, the pieces are set down there), the park on the road at the curb in front (pile 8 – 20
-- studs from park). 5.5: an apartment building's home is the building ("40 6th Ave"; `floors` says how many floors of
-- four flats, A – D, it has: shared/Residents.luau puts people in them and a delivery names one, "Apt 4C, 40 6th
-- Ave"); a house's is its address ("12 Willow Ln"). House numbers run along the street, odd on one side and even on
-- the other.
export type Lot = {
	district: string,
	i: number, -- the block
	j: number,
	a: number, -- the lot in it
	b: number,
	x: number, -- the lot's middle
	z: number,
	size: number,
	kind: string, -- tower | apartment | venue | grass | parking | house | wreck | estate | gas (5.4: a gas station's)
	facing: Spot, -- the front's way (a unit direction along X or Z: one of the lot's outer sides)
	w: number, -- the building: a tower's size along X, a house's front (0: none)
	d: number, -- … a tower's along Z, a house's depth
	h: number, -- … its height
	front: number, -- a house: its front wall this far forward of the lot's middle
	seed: number, -- dice for the looks (colours, trees) World rolls with
	venue: Venue?,
	home: Home?,
}
export type Home = {
	id: string,
	kind: string, -- house | apartment
	name: string, -- "12 Willow Ln" / "40 6th Ave" (5.5: an apartment building's, not one flat's)
	address: string, -- the building's: "12 Willow Ln" / "40 6th Ave"
	street: string,
	district: string,
	x: number, -- the lot's middle
	z: number,
	facing: Spot,
	door: Spot,
	park: Spot,
	pile: Spot,
	floors: number?, -- an apartment building: floors of flats (A – D on each)
}
Map.HouseFront = 18 -- a Suburbs house's front wall: this far forward of its lot's middle (12 from the curb)
Map.FreeRadius = 30
Map.ParkGap = 12 -- 5.5: no two homes' parks closer than this (every tower facing a street: the parks fill up)

-- Lays out every lot and home (fresh tables each call: the same every time; Map.AllLots / Map.Homes hold the one made
-- when the module loads). 6.11: the third result are the lots a block that was ordinary had (Map.FormerBlocks: the
-- depot's four towers), laid out with the same dice but with no homes; nothing stands on them any more, but whatever
-- rolled dice for them still does (server/World.luau's towers), so every other block stays as it was.
function Map.makeLots(): ({ [string]: { [string]: { Lot } } }, { Home }, { [string]: { [string]: { Lot } } })
	local districtLots: { [string]: { [string]: { Lot } } } = { downtown = {}, suburbs = {}, harbor = {} }
	local formerLots: { [string]: { [string]: { Lot } } } = { downtown = {}, suburbs = {}, harbor = {} }
	local homes: { Home } = {}
	local venueAt: { [string]: Venue } = {}
	-- 5.4: the rows of lots the gas stations stand on (Map.GasStations): both lots of the row are the station's.
	local gasAt: { [string]: GasStation } = {}
	for _, station in Map.GasStations do
		if station.district and station.i and station.j and station.b then
			for a = 0, 1 do
				gasAt[`{station.district}:{station.i},{station.j}:{a}{station.b}`] = station
			end
		end
	end
	for _, venue in Map.Venues do
		if venue.built then
			local d = districtById(venue.district)
			local i = math.floor((venue.x - d.ox) / CELL + 0.5)
			local j = math.floor((venue.z - d.oz) / CELL + 0.5)
			local a = if venue.x > d.ox + i * CELL then 1 else 0
			local b = if venue.z > d.oz + j * CELL then 1 else 0
			venueAt[`{venue.district}:{i},{j}:{a}{b}`] = venue
		end
	end

	-- The street a front faces from block (i, j) (the names as Map.addresses gives them).
	local function streetOf(d: District, i: number, j: number, fx: number, fz: number): string
		if fz ~= 0 then
			local k = j + (if fz > 0 then 0 else -1) - d.j0 + 1
			return d.streets[k % #d.streets + 1]
		end
		local k = i + (if fx > 0 then 0 else -1) - d.i0 + 1
		return d.avenues[k % #d.avenues + 1]
	end
	-- Is a park here clear of the safe zone and of the places' own spots?
	local function free(x: number, z: number): boolean
		local r2 = Map.FreeRadius * Map.FreeRadius
		local function near(px: number, pz: number): boolean
			return (x - px) ^ 2 + (z - pz) ^ 2 < r2
		end
		if Map.isSafe(x, z) then
			return false
		end
		for _, place in Map.Places do
			if near(place.x, place.z) then
				return false
			end
		end
		for _, spot in Map.CargoSpots do
			if near(spot.park.x, spot.park.z) or near(spot.pile.x, spot.pile.z) then
				return false
			end
		end
		for _, spot in Map.EmployerSpots do
			if near(spot.x, spot.z) then
				return false
			end
		end
		for _, venue in Map.Venues do
			if near(venue.park.x, venue.park.z) then
				return false
			end
		end
		-- 5.5: a gas station's pumps and bays (the cars that fill up park there), and the other homes' parks
		for _, station in Map.GasStations do
			for _, spot in station.pumps do
				if near(spot.x, spot.z) then
					return false
				end
			end
			for _, bay in station.bays do
				if near(bay.x, bay.z) then
					return false
				end
			end
		end
		for _, home in homes do
			if (x - home.park.x) ^ 2 + (z - home.park.z) ^ 2 < Map.ParkGap * Map.ParkGap then
				return false
			end
		end
		return true
	end
	-- A home behind a front wall `wall` studs out from the block's middle (cx, cz), facing (fx, fz), on the lot whose
	-- middle is (lx, lz): the door, the pile `step` out, the park at the curb.
	local function addHome(lot: Lot, d: District, kind: string, wall: number, step: number, floors: number?): Home
		local cx, cz = d.ox + lot.i * CELL, d.oz + lot.j * CELL
		local fx, fz = lot.facing.x, lot.facing.z
		local doorX = if fx ~= 0 then cx + fx * wall else lot.x
		local doorZ = if fz ~= 0 then cz + fz * wall else lot.z
		local out = BLOCK / 2 + Map.CurbPark
		local street = streetOf(d, lot.i, lot.j, fx, fz)
		local x0, _, z0 = districtEdges(d)
		local along = if fz ~= 0 then doorX - x0 else doorZ - z0
		local address = `{math.floor(along / 8) * 2 + (if fx + fz > 0 then 2 else 1)} {street}`
		local home: Home = {
			id = `home_{d.id}_{lot.i}_{lot.j}_{lot.a}{lot.b}`,
			kind = kind,
			name = address,
			address = address,
			street = street,
			district = d.id,
			x = lot.x,
			z = lot.z,
			facing = lot.facing,
			door = { x = doorX, z = doorZ },
			pile = { x = doorX + fx * step, z = doorZ + fz * step },
			park = { x = if fx ~= 0 then cx + fx * out else lot.x, z = if fz ~= 0 then cz + fz * out else lot.z },
			floors = floors,
		}
		table.insert(homes, home)
		lot.home = home
		return home
	end
	-- The lot's outer side to face: one of its two at random, the other if that one's park is not free (nil: neither).
	local function pickFacing(d: District, lot: Lot, alongX: boolean): Spot?
		local cx, cz = d.ox + lot.i * CELL, d.oz + lot.j * CELL
		local out = BLOCK / 2 + Map.CurbPark
		local sides = { { x = if lot.a == 0 then -1 else 1, z = 0 }, { x = 0, z = if lot.b == 0 then -1 else 1 } }
		if not alongX then
			sides = { sides[2], sides[1] }
		end
		for _, side in sides do
			local px = if side.x ~= 0 then cx + side.x * out else lot.x
			local pz = if side.z ~= 0 then cz + side.z * out else lot.z
			if free(px, pz) then
				return side
			end
		end
		return nil
	end

	for _, d in Map.Districts do
		if d.style == "harbor" then
			continue
		end
		local rand = Map.lcg(Config.City.Seed + (if d.style == "downtown" then 53 else 54))
		local span = math.max(d.i1 - d.i0, d.j1 - d.j0) / 2 + 1
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				-- (6.11: a block that was ordinary rolls its lots' dice as before, into formerLots)
				local former = Map.wasOrdinary(d.id, i, j)
				if Map.special(d.id, i, j) and not former then
					continue
				end
				local list: { Lot } = {}
				if former then
					formerLots[d.id][`{i},{j}`] = list
				else
					districtLots[d.id][`{i},{j}`] = list
				end
				local centerFactor = 1 - math.max(math.abs(i), math.abs(j)) / span
				for a = 0, 1 do
					for b = 0, 1 do
						local lx, lz, size = Map.lotCentre(d.id, i, j, a, b)
						-- every lot rolls the same dice, whatever it becomes (a change on one lot leaves the others)
						-- (5.5: the second die once chose which towers were apartments; still rolled, the others stay)
						local roll, _, side, seed = rand(), rand(), rand(), math.floor(rand() * 1e6)
						local w, dd, h = rand(), rand(), rand()
						local lot: Lot = {
							district = d.id,
							i = i,
							j = j,
							a = a,
							b = b,
							x = lx,
							z = lz,
							size = size,
							kind = "grass",
							facing = { x = 0, z = if b == 0 then -1 else 1 },
							w = 0,
							d = 0,
							h = 0,
							front = 0,
							seed = seed,
						}
						table.insert(list, lot)
						local venue = venueAt[`{d.id}:{i},{j}:{a}{b}`]
						local gas = gasAt[`{d.id}:{i},{j}:{a}{b}`]
						if gas then
							lot.kind = "gas" -- 5.4: server/World.luau builds the station over the row
							lot.facing = gas.facing
						elseif venue then
							lot.kind = "venue"
							lot.venue = venue
							lot.facing = venue.facing
							lot.w, lot.d, lot.h = Map.VenueSize.w, Map.VenueSize.d, Map.VenueSize.h
						elseif d.style == "downtown" then
							if roll < 0.7 then
								lot.kind = "tower"
								lot.w = size - 2 - w * 7
								lot.d = size - 2 - dd * 7
								lot.h = 16 + h * 18 + 55 * centerFactor * ((seed % 1000) / 1000)
								-- 5.5: every tower that can face a street is an apartment building (its people:
								-- shared/Residents.luau); one with no free street stays a plain tower
								local facing = if former then nil else pickFacing(d, lot, side < 0.5)
								if facing then
									lot.kind = "apartment"
									lot.facing = facing
									local half = if facing.x ~= 0 then lot.w / 2 else lot.d / 2
									local floors = math.clamp(math.floor((lot.h - 4) / 9), 2, 9)
									addHome(lot, d, "apartment", math.abs(lot.x - (d.ox + i * CELL)) + half, 3, floors)
								end
							elseif roll < 0.85 then
								lot.kind = "grass"
							else
								lot.kind = "parking"
							end
						else
							-- the Suburbs: a house for sale has its lot (it faces its nearer street, north or south)
							for _, plot in Map.EstatePlots do
								if math.abs(plot.x - lx) < 2 and math.abs(plot.z - lz) < size / 2 then
									lot.kind = "estate"
								end
							end
							if lot.kind ~= "estate" then
								local facing = if roll < 0.85 and not former then pickFacing(d, lot, side < 0.5) else nil
								if facing then
									lot.kind = "house"
									lot.facing = facing
									lot.w, lot.d, lot.h = 20 + w * 6, 16 + dd * 4, 11 + h * 3
									lot.front = Map.HouseFront
									addHome(lot, d, "house", size / 2 + Map.HouseFront, 2.5)
								else
									lot.kind = "wreck"
								end
							end
						end
					end
				end
			end
		end
	end
	return districtLots, homes, formerLots
end
Map.AllLots, Map.Homes, Map.FormerLots = Map.makeLots()

-- The lots of a district's ordinary blocks, by block ("i,j": its four lots); a district without lots: empty.
function Map.lots(districtId: string): { [string]: { Lot } }
	return Map.AllLots[districtId] or {}
end

-- The four lots of block (i, j) (empty: a special block, or a district without lots).
function Map.lotsAt(districtId: string, i: number, j: number): { Lot }
	local lots = Map.AllLots[districtId]
	return if lots then lots[`{i},{j}`] or {} else {}
end

-- 6.11: the lots block (i, j) had while it was ordinary (Map.FormerBlocks; empty for any other block). Nothing stands
-- on them: only their dice are still rolled.
function Map.formerLotsAt(districtId: string, i: number, j: number): { Lot }
	local lots = Map.FormerLots[districtId]
	return if lots then lots[`{i},{j}`] or {} else {}
end

-- A home by its id (nil: none).
function Map.home(id: string): Home?
	for _, home in Map.Homes do
		if home.id == id then
			return home
		end
	end
	return nil
end

return Map
