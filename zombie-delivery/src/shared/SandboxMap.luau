--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the owner's small test world in place of the city. Houses to empty, the
-- roads, four player plots, each with a ZDC warehouse (its display plots), a van spot at its roller door and a Moving
-- contracts board. Plain data (numbers only: the pure tests run it outside Roblox); the builders read it. 9.4 the
-- countryside (design/countryside/plan.py, plan.json; the owner: "all the family houses are gone; instead six different
-- spots, no towns, no villages"): open country with six separate places to empty (Houses), each with its own
-- surroundings, joined to the depot by country lanes; its map section below, the six spots by hand under it.
--
-- Coordinates: studs, y up, the ground's top at GroundTop, the asphalt's at RoadTop. A spot is { x, y, z, yaw }: yaw
-- in degrees about Y, the way its front looks: 0 looks north (-z), 90 west (-x), 180 south (+z), 270 east (+x);
-- in Roblox: CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0) (SandboxMap.cframe).
--
--   Bounds           the world's edge (the scenery fills it; nothing you play with is outside)
--   Roads            the asphalt rects: Pražská (north-south, the plots to the farmstead) and Depot Row (the plots')
--                    first, always these two (Roads[1], Roads[2]); then the country lanes, each one rect or a few that
--                    meet end to end (they share its name; none over another): Mill Lane (west from Depot Row to the
--                    mill), Wood Lane (north off it into the forest), Hill Road (north off it to the lone house), Orchard
--                    Lane (north from Depot Row's east end to the orchard), Pond Lane (west off Pražská, then south to
--                    the pond). lane: a lane (narrower than Pražská; no centre line), else a main road; yard: a spot's
--                    turning yard at its lane's end (its lane's name: the van turns round there, its curb in it)
--   9.4 the countryside (design/countryside/plan.json; tools/countryside/sandboxmap.py writes Bounds, Roads and these
--   between the BEGIN COUNTRYSIDE and END COUNTRYSIDE lines: change the plan, run it again):
--   Landmarks        each spot's surroundings and the map's own (id, name, kind, rect, yaw: the way its front looks):
--                    the farm's barn, old tractor and trailer, stackyard of bales, paddock and muck heap; the fish pond
--                    with its jetty and boat; the lone house's garden; the lodge's woodpile; the millrace's weir and
--                    footbridge; the orchard's beehives; the D5 at the east edge; the railway under it and its lone
--                    halt (shared/CountryLooks.luau draws them, the D5 shared/VillageLooks.luau)
--   Fields           the fields between the lanes (a crop's kind and its rect; none over another, a plot, a lot, a road)
--   Lawns            ground tiles of their own (kind, rect): the forest's floor
--   TreeLines        windbreaks and fruit alleys (trees), hedges and fences (kind, points)
--   Woods            the forest: its rect (its trees on a jittered grid) and its clearings (the lodge's: no tree)
--   Orchard          the orchard's rect (its fruit trees in rows; the cottage on its east edge)
--   Streams          the millrace from the forest past the mill into the pond (id, width, its middle line's points)
--   Turnaround       the circle at Pražská's south end, before the farmstead
--   Plots            four players' plots along Depot Row's north side (SandboxPlots claims one per player):
--                      rect        the plot's ground (x0, x1, z0, z1)
--                      warehouse   the building: its middle at the ground and its size (x across, y up, z deep);
--                                  its roller door in the south wall, DoorWidth wide, in the middle
--                      door        outside the roller door's middle, looking out (south)
--                      vanSpot     the van's pivot: its nose to the street (south), its back doors to the roller
--                                  door, VanGap studs from the wall
--                      unload      the circle the van's back must be in to unload into the warehouse
--                      spawn       where the player appears (beside the van, inside the plot)
--                      board       the Moving contracts board (by the roller door, on the wall's outside)
--   Houses           the six places to empty (design/countryside/plan.json `spots`; tests/sandboxhouses_test.luau holds
--                    them to it), each a Moving contract of its own (Config.Moving.Sandbox.Houses, by id; server/
--                    Moving.luau offers one at a time). In this order: the farmstead, the pond cabin, the lone house,
--                    the forest lodge, the old mill, the orchard cottage. Each:
--                      id          the spot's (the farmstead's sandbox_house as ever)
--                      name        what the card, the guide and its signs call it (made up, in English words)
--                      street      the road it stands on, one of Roads (the contract's address, the guide's words)
--                      number      none (a spot of its own has no house number)
--                      kind        its inside's plan's kind (shared/HouseLayout.luau; its contract's, Config.Moving
--                                  .Sandbox.Houses): "big" the farmstead, "house" the lone house, the other four
--                                  shared/Layouts/Countryside.luau's "cabin", "lodge", "mill" and "cottage"
--                      look        its outside's kind: "farmstead" (server/SandboxWorld.luau's, the owner's Blender
--                                  house), else shared/VillageLooks.luau house's ("cabin", "old", "lodge", "mill",
--                                  "cottage": shared/VillageScenery.luau builds each in its own)
--                      box         its footprint (x0, x1, z0, z1): sx along its front × sz deep, turned with its yaw
--                      lot         its garden: the box, LOT round it, its front up to its yard's edge (10 studs:
--                                  the front garden; the mill's west side stops at its wall: the millrace runs there)
--                      house       the walls' box: its footprint's middle, its bottom, its size (sx along x, sy the
--                                  walls' height, sz along z; the roof over it)
--                      yaw         the way its front looks (its front door's)
--                      door        outside its front door, looking out to its yard (DOOR_IN in from its box's front
--                                  edge: the look's front wall 1.5 in, its door 0.3 out of it)
--                      curb        the van's pivot in its yard (the Sprinter, 21.8 long: its back 2 studs in from the
--                                  yard's edge nearest the door, its nose away from the door: "Call the van to the door")
--                      back        only where the house has a back door (the farmstead's): outside it, looking out
--   House            Houses[1], The Old Farmstead on Pražská: what only the farmstead has reads it (server/HouseMesh
--                    .luau dresses only it, the menu's drift shows it). 8.1: the box is the owner's Blender house's
--                    (server/HouseMesh.luau dresses only a box of its size), its front wall where the chalet's always
--                    was (the door, the path and the curb unmoved). 8.2.1: the owner's big European house
--                    (design/blender-house/house.py TARGET "sandbox": 44 × 14.5 × 34, the chalet's old footprint). 8.3
--                    the big move: back, its back door (the model's, in the middle of its back wall; outside it,
--                    looking out: south), a second way in and out of a move (server/Moving.luau SB.site)
--   SandboxMap.plotAt(x, z)   the plot whose rect holds the point (nil: none)
--   SandboxMap.house(id)      the house of that id (nil: none, an id of an older map's too)
--   SandboxMap.houseAt(x, z, margin)   the first house whose lot holds the point or lies within `margin` of it (nil: none)
--   SandboxMap.cframe(spot)   (Roblox only) a spot's CFrame

local SandboxMap = {}

export type Spot = { x: number, y: number, z: number, yaw: number }
export type Rect = { x0: number, x1: number, z0: number, z1: number }
export type Plot = {
	id: number,
	rect: Rect,
	warehouse: { x: number, y: number, z: number, sx: number, sy: number, sz: number },
	door: Spot,
	vanSpot: Spot,
	unload: { x: number, z: number, r: number },
	spawn: Spot,
	board: Spot,
}

-- a place to empty (SandboxMap.Houses)
export type House = {
	id: string,
	name: string,
	street: string,
	number: number?,
	kind: string,
	look: string,
	box: Rect,
	lot: Rect,
	house: { x: number, y: number, z: number, sx: number, sy: number, sz: number },
	yaw: number,
	door: Spot,
	curb: Spot,
	back: Spot?,
}

-- 9.4 the countryside: a road (a lane's rect, its yard), a landmark, a field, a lawn, a tree line, a wood, a stream
export type Road = { name: string, x0: number, x1: number, z0: number, z1: number, lane: boolean, yard: boolean }
export type Landmark = { id: string, name: string, kind: string, x0: number, x1: number, z0: number, z1: number, yaw: number }
export type Field = { kind: string, x0: number, x1: number, z0: number, z1: number }
export type Lawn = { kind: string, x0: number, x1: number, z0: number, z1: number }
export type TreeLine = { kind: string, points: { { x: number, z: number } } }
export type Wood = { id: string, x0: number, x1: number, z0: number, z1: number, clearings: { Rect } }
export type Stream = { id: string, width: number, points: { { x: number, z: number } } }

SandboxMap.GroundTop = 0
SandboxMap.RoadTop = 0.4

-- BEGIN COUNTRYSIDE (tools/countryside/sandboxmap.py writes these lines from design/countryside/plan.json: do not edit them)
SandboxMap.Bounds = { x0 = -1180, x1 = 420, z0 = -680, z1 = 760 } :: Rect
SandboxMap.Roads = {
	{ name = "Pražská", x0 = -14, x1 = 14, z0 = -74, z1 = 470, lane = false, yard = false },
	{ name = "Depot Row", x0 = -270, x1 = 270, z0 = -74, z1 = -46, lane = false, yard = false },
	{ name = "Mill Lane", x0 = -1012, x1 = -270, z0 = -71, z1 = -49, lane = true, yard = false },
	{ name = "Mill Lane", x0 = -1066, x1 = -1012, z0 = -84, z1 = -36, lane = true, yard = true },
	{ name = "Wood Lane", x0 = -951, x1 = -929, z0 = -404, z1 = -71, lane = true, yard = false },
	{ name = "Wood Lane", x0 = -967, x1 = -913, z0 = -452, z1 = -404, lane = true, yard = true },
	{ name = "Hill Road", x0 = -531, x1 = -509, z0 = -440, z1 = -71, lane = true, yard = false },
	{ name = "Hill Road", x0 = -583, x1 = -531, z0 = -460, z1 = -412, lane = true, yard = true },
	{ name = "Orchard Lane", x0 = 270, x1 = 292, z0 = -494, z1 = -46, lane = true, yard = false },
	{ name = "Orchard Lane", x0 = 222, x1 = 270, z0 = -494, z1 = -446, lane = true, yard = true },
	{ name = "Pond Lane", x0 = -896, x1 = -14, z0 = 320, z1 = 342, lane = true, yard = false },
	{ name = "Pond Lane", x0 = -896, x1 = -874, z0 = 342, z1 = 446, lane = true, yard = false },
	{ name = "Pond Lane", x0 = -922, x1 = -874, z0 = 446, z1 = 494, lane = true, yard = true },
} :: { Road }
SandboxMap.Landmarks = {
	{ id = "barn", name = "The Barn", kind = "barn", x0 = -144, x1 = -88, z0 = 500, z1 = 548, yaw = 270 },
	{ id = "tractor", name = "The Old Tractor", kind = "tractor", x0 = -170, x1 = -106, z0 = 460, z1 = 490, yaw = 270 },
	{ id = "bales", name = "The Stackyard", kind = "bales", x0 = 82, x1 = 150, z0 = 508, z1 = 572, yaw = 0 },
	{ id = "paddock", name = "The Paddock", kind = "paddock", x0 = -56, x1 = 64, z0 = 618, z1 = 690, yaw = 0 },
	{ id = "muckheap", name = "The Muck Heap", kind = "muckheap", x0 = -144, x1 = -100, z0 = 560, z1 = 590, yaw = 270 },
	{ id = "pond", name = "The Fish Pond", kind = "fishpond", x0 = -1160, x1 = -957, z0 = 380, z1 = 560, yaw = 270 },
	{ id = "garden", name = "The Garden", kind = "garden", x0 = -625, x1 = -583, z0 = -510, z1 = -466, yaw = 270 },
	{ id = "woodyard", name = "The Woodpile", kind = "woodyard", x0 = -999, x1 = -973, z0 = -480, z1 = -456, yaw = 180 },
	{ id = "weir", name = "The Weir", kind = "weir", x0 = -1088, x1 = -1068, z0 = -134, z1 = -122, yaw = 0 },
	{ id = "footbridge", name = "The Footbridge", kind = "footbridge", x0 = -1090, x1 = -1066, z0 = 12, z1 = 20, yaw = 0 },
	{ id = "apiary", name = "The Beehives", kind = "apiary", x0 = 150, x1 = 186, z0 = -432, z1 = -414, yaw = 270 },
	{ id = "d5", name = "D5 Motorway", kind = "motorway", x0 = 330, x1 = 390, z0 = -680, z1 = 760, yaw = 90 },
	{ id = "railway", name = "Railway", kind = "railway", x0 = -1180, x1 = 330, z0 = 716, z1 = 728, yaw = 90 },
	{ id = "railway_east", name = "Railway", kind = "railway", x0 = 390, x1 = 420, z0 = 716, z1 = 728, yaw = 270 },
	{ id = "halt", name = "Meadow Halt", kind = "halt", x0 = 140, x1 = 220, z0 = 700, z1 = 716, yaw = 0 },
} :: { Landmark }
SandboxMap.Fields = {
	{ kind = "rapeseed", x0 = -750, x1 = 20, z0 = -680, z1 = -520 },
	{ kind = "wheat", x0 = -750, x1 = -635, z0 = -510, z1 = -250 },
	{ kind = "young", x0 = -625, x1 = -541, z0 = -402, z1 = -250 },
	{ kind = "wheat", x0 = -499, x1 = 20, z0 = -510, z1 = -240 },
	{ kind = "ploughed", x0 = -499, x1 = -280, z0 = -230, z1 = -81 },
	{ kind = "young", x0 = -1060, x1 = -961, z0 = -240, z1 = -94 },
	{ kind = "rapeseed", x0 = -919, x1 = -541, z0 = -240, z1 = -81 },
	{ kind = "wheat", x0 = -1002, x1 = -660, z0 = -39, z1 = 310 },
	{ kind = "ploughed", x0 = -640, x1 = -300, z0 = -39, z1 = 310 },
	{ kind = "rapeseed", x0 = -280, x1 = -36, z0 = -36, z1 = 310 },
	{ kind = "young", x0 = -1150, x1 = -884, z0 = 570, z1 = 706 },
	{ kind = "ploughed", x0 = -864, x1 = -520, z0 = 352, z1 = 706 },
	{ kind = "wheat", x0 = -500, x1 = -180, z0 = 352, z1 = 706 },
	{ kind = "rapeseed", x0 = -170, x1 = -48, z0 = 352, z1 = 450 },
	{ kind = "young", x0 = -170, x1 = -66, z0 = 600, z1 = 706 },
	{ kind = "young", x0 = 24, x1 = 296, z0 = 28, z1 = 300 },
	{ kind = "rapeseed", x0 = 48, x1 = 296, z0 = 310, z1 = 496 },
	{ kind = "wheat", x0 = 160, x1 = 296, z0 = 506, z1 = 690 },
} :: { Field }
SandboxMap.Lawns = {
	{ kind = "forest", x0 = -1160, x1 = -760, z0 = -672, z1 = -500 },
	{ kind = "forest", x0 = -1160, x1 = -760, z0 = -392, z1 = -250 },
	{ kind = "forest", x0 = -1160, x1 = -1005, z0 = -500, z1 = -392 },
	{ kind = "forest", x0 = -895, x1 = -760, z0 = -500, z1 = -392 },
} :: { Lawn }
SandboxMap.TreeLines = {
	{ kind = "windbreak", points = { { x = 312, z = -20 }, { x = 312, z = 700 } } },
	{ kind = "windbreak", points = { { x = -650, z = -27 }, { x = -650, z = 300 } } },
	{ kind = "windbreak", points = { { x = -290, z = -27 }, { x = -290, z = 300 } } },
	{ kind = "windbreak", points = { { x = -510, z = 362 }, { x = -510, z = 700 } } },
	{ kind = "windbreak", points = { { x = -480, z = -515 }, { x = 10, z = -515 } } },
	{ kind = "alley", points = { { x = -497, z = -430 }, { x = -497, z = -92 } } },
	{ kind = "alley", points = { { x = -860, z = 306 }, { x = -40, z = 306 } } },
	{ kind = "hedge", points = { { x = -905, z = -79 }, { x = -560, z = -79 } } },
	{ kind = "hedge", points = { { x = -860, z = 349 }, { x = -180, z = 349 } } },
	{ kind = "hedge", points = { { x = -170, z = 596 }, { x = -170, z = 700 } } },
	{ kind = "fence", points = { { x = 217, z = -495 }, { x = 217, z = -650 }, { x = 30, z = -650 }, { x = 30, z = -300 }, { x = 217, z = -300 }, { x = 217, z = -445 } } },
} :: { TreeLine }
SandboxMap.Woods = {
	{ id = "forest", x0 = -1160, x1 = -760, z0 = -672, z1 = -250, clearings = { { x0 = -1005, x1 = -895, z0 = -500, z1 = -392 } } },
} :: { Wood }
SandboxMap.Orchard = { x0 = 30, x1 = 216, z0 = -650, z1 = -300 } :: Rect
SandboxMap.Streams = {
	{ id = "millrace", width = 8, points = { { x = -1110, z = -676 }, { x = -1096, z = -560 }, { x = -1104, z = -440 }, { x = -1090, z = -320 }, { x = -1092, z = -200 }, { x = -1078, z = -134 }, { x = -1078, z = 10 }, { x = -1082, z = 120 }, { x = -1070, z = 250 }, { x = -1060, z = 386 } } },
} :: { Stream }
-- END COUNTRYSIDE

SandboxMap.Turnaround = { x = 0, z = 470, r = 34 }

SandboxMap.DoorWidth = 26 -- the warehouse's roller door
SandboxMap.VanGap = 6 -- studs from the warehouse's front wall to the van's back

local PLOT_X = { -195, -65, 65, 195 }
local WALL_Z = -130 -- the warehouses' front (south) wall

local plots: { Plot } = {}
for id, x in PLOT_X do
	plots[id] = {
		id = id,
		rect = { x0 = x - 60, x1 = x + 60, z0 = -230, z1 = -78 },
		warehouse = { x = x, y = 0, z = WALL_Z - 30, sx = 80, sy = 24, sz = 60 },
		door = { x = x, y = 0, z = WALL_Z, yaw = 180 },
		vanSpot = { x = x, y = SandboxMap.RoadTop, z = WALL_Z + 6 + 11, yaw = 180 }, -- (the Sprinter 22 long: its back 6 off the wall)
		unload = { x = x, z = WALL_Z + 8, r = 16 },
		spawn = { x = x + 22, y = 3, z = WALL_Z + 18, yaw = 180 },
		board = { x = x - 24, y = 0, z = WALL_Z + 1, yaw = 180 },
	}
end
SandboxMap.Plots = plots

local TOP = SandboxMap.RoadTop

-- A spot of the countryside (plan.json `spots`): its look, kind, box and yaw as the plan has them, the rest made from
-- them the way the plan makes them (design/countryside/plan.py spots(); tests/sandboxhouses_test.luau holds them
-- together): its door DOOR_IN in from its box's front edge (a look stands its front wall Config.Village.Front, 1.5, in
-- from it, its door 0.3 out of that wall: the spot just outside it, VillageLooks.doorSpots), its curb CURB_IN from
-- `edge` (its yard's edge nearest the door: the van's back 2 in, its middle 11 on, its nose away from the door), its
-- walls WALLS high, its lot LOT round its box and its front to `edge`.
local WALLS, LOT, DOOR_IN, CURB_IN = 10, 6, 1.2, 13
local OUT = { [0] = { 0, -1 }, [90] = { -1, 0 }, [180] = { 0, 1 }, [270] = { 1, 0 } } :: { [number]: { number } } -- (a yaw's look)
local function spot(id: string, name: string, street: string, look: string, kind: string, box: Rect, yaw: number, edge: number): House
	local out = OUT[yaw]
	local mx, mz = (box.x0 + box.x1) / 2, (box.z0 + box.z1) / 2
	-- (the front edge's middle: the box's side the yaw looks out of)
	local fx = if out[1] < 0 then box.x0 elseif out[1] > 0 then box.x1 else mx
	local fz = if out[2] < 0 then box.z0 elseif out[2] > 0 then box.z1 else mz
	local lot = { x0 = box.x0 - LOT, x1 = box.x1 + LOT, z0 = box.z0 - LOT, z1 = box.z1 + LOT }
	if yaw == 0 then -- (its front looks north: its yard's south edge north of it)
		lot.z0 = edge
	elseif yaw == 180 then
		lot.z1 = edge
	elseif yaw == 90 then
		lot.x0 = edge
	else
		lot.x1 = edge
	end
	return {
		id = id,
		name = name,
		street = street,
		number = nil,
		kind = kind,
		look = look,
		box = box,
		lot = lot,
		house = { x = mx, y = 0, z = mz, sx = box.x1 - box.x0, sy = WALLS, sz = box.z1 - box.z0 },
		yaw = yaw,
		door = { x = fx - out[1] * DOOR_IN, y = 0, z = fz - out[2] * DOOR_IN, yaw = yaw },
		curb = { x = if out[1] ~= 0 then edge + out[1] * CURB_IN else mx, y = TOP, z = if out[2] ~= 0 then edge + out[2] * CURB_IN else mz, yaw = yaw },
	}
end

-- The old mill: the millrace runs past its right-hand side (its west wall, seen facing its door from outside), its lot
-- stops at that wall.
local mill = spot("old_mill", "The Old Mill", "Mill Lane", "mill", "mill", { x0 = -1072, x1 = -1048, z0 = -26, z1 = 0 }, 0, -36)
mill.lot.x0 = mill.box.x0

SandboxMap.Houses = {
	{
		id = "sandbox_house",
		name = "The Old Farmstead",
		street = "Pražská", -- (the road it stands on, one of SandboxMap.Roads: the contract's address, the guide's words)
		kind = "big",
		look = "farmstead",
		box = { x0 = -22, x1 = 22, z0 = 523, z1 = 557 } :: Rect,
		lot = { x0 = -60, x1 = 60, z0 = 504, z1 = 600 } :: Rect,
		-- (the front wall at the door, z 523; the house's box back from it: tools/house-art/check.py, house.py's TARGETS
		-- "sandbox" box; sy the walls' height, the roof over it up to 26)
		house = { x = 0, y = 0, z = 523 + 34 / 2, sx = 44, sy = 14.5, sz = 34 },
		yaw = 0,
		door = { x = 0, y = 0, z = 523, yaw = 0 } :: Spot, -- outside the front door, looking north to the road
		curb = { x = 0, y = TOP, z = 492, yaw = 0 } :: Spot, -- the van's pivot: nose north, back to the door
		back = { x = 0, y = 0, z = 523 + 34, yaw = 180 } :: Spot, -- 8.3: outside the back door, looking south into the garden
	},
	-- 9.4 the countryside: five spots of their own (plan.json `spots` 2 … 6), each `edge` its yard's edge by its door
	spot("pond_cabin", "The Pond Cabin", "Pond Lane", "cabin", "cabin", { x0 = -950, x1 = -932, z0 = 458, z1 = 482 }, 270, -922),
	spot("lone_house", "The Lone House", "Hill Road", "old", "house", { x0 = -617, x1 = -593, z0 = -451, z1 = -421 }, 270, -583),
	spot("forest_lodge", "The Forest Lodge", "Wood Lane", "lodge", "lodge", { x0 = -954, x1 = -926, z0 = -484, z1 = -462 }, 180, -452),
	mill,
	spot("orchard_cottage", "The Orchard Cottage", "Orchard Lane", "cottage", "cottage", { x0 = 192, x1 = 212, z0 = -483, z1 = -457 }, 270, 222),
} :: { House }

-- The one house before the six (The Old Farmstead): what only it has reads it (HouseMesh's import, the menu's drift).
SandboxMap.House = SandboxMap.Houses[1]

local byId: { [string]: House } = {}
for _, h in SandboxMap.Houses do
	byId[h.id] = h
end

function SandboxMap.plotAt(x: number, z: number): Plot?
	for _, plot in plots do
		local r = plot.rect
		if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
			return plot
		end
	end
	return nil
end

function SandboxMap.house(id: any): House?
	return if type(id) == "string" then byId[id] else nil
end

function SandboxMap.houseAt(x: number, z: number, margin: number): House?
	for _, h in SandboxMap.Houses do
		local lot = h.lot
		if x >= lot.x0 - margin and x <= lot.x1 + margin and z >= lot.z0 - margin and z <= lot.z1 + margin then
			return h
		end
	end
	return nil
end

function SandboxMap.cframe(spot: Spot): any
	return (CFrame :: any).new(spot.x, spot.y, spot.z) * (CFrame :: any).Angles(0, math.rad(spot.yaw), 0)
end

return SandboxMap
