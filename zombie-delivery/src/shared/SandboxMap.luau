--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the owner's small test world in place of the city. 9.7 runs (the owner:
-- "shrink the map ... one little lobby, like Dungeon Quest: there you go into a dungeon, here you go into a house"):
-- the LOBBY (design/lobby/plan.py, plan.json; its section below) is the whole visible world, a compact square with the
-- plaza, the spawn, the ZDC dispatch, the four player plots (each with a ZDC warehouse, its display stands), the
-- shops and six house portals; the six places to empty (Houses) each stand in a RUN ZONE of their own far off
-- (design/countryside/plan.py, plan.json; its section below: Zones), fenced, out of sight of the lobby and of each
-- other, their truck parked at the curb by the door (no driving any more: no lanes, no Depot Row, no Pražská). Plain
-- data (numbers only: the pure tests run it outside Roblox); the builders read it.
--
-- Coordinates: studs, y up, the ground's top at GroundTop, the asphalt's (the yards') at RoadTop. A spot is { x, y, z,
-- yaw }: yaw in degrees about Y, the way its front looks: 0 looks north (-z), 90 west (-x), 180 south (+z), 270 east
-- (+x); in Roblox: CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0) (SandboxMap.cframe).
--
--   9.7 the lobby (design/lobby/plan.json; tools/lobby/sandboxmap.py writes Lobby between the BEGIN LOBBY and END
--   LOBBY lines: change the plan, run it again):
--   Lobby            bounds (the square: a hedge `hedge` in from it, invisible walls on it), far (studs to every run
--                    zone at least), plaza, spawn (a Spot; spawnApart: the players' spawns apart), dispatch (the ZDC
--                    dispatch kiosk), fountain, plots ({ id, x, wall, rect }: Plots below), portals ({ house, name, x, z,
--                    yaw, pad, foot, back }: a gate per place to empty, its glowing pad in front of it, its footprint,
--                    where its party comes back), shops (paint, leaders, auction: their spots and rects; paint's stand
--                    at its counter), lamps, trees
--   9.4 the countryside (design/countryside/plan.json; tools/countryside/sandboxmap.py writes Bounds, Roads and these
--   between the BEGIN COUNTRYSIDE and END COUNTRYSIDE lines: change the plan, run it again):
--   Bounds           the world's edge round the run zones and the lobby (the meadow under all of it; nothing you play
--                    with is outside a zone or the lobby)
--   Roads            9.7 the yards: each place's yard where its truck stands (name: the road its place stood on, its
--                    words' "on Pond Lane"; lane, yard: true)
--   Landmarks        each place's surroundings (id, name, kind, rect, yaw: the way its front looks): the farm's barn, old
--                    tractor and trailer, stackyard of bales, paddock and muck heap; the fish pond with its jetty and
--                    boat; the lone house's garden; the lodge's woodpile; the millrace's weir and footbridge; the
--                    orchard's beehives (shared/CountryLooks.luau draws them)
--   Fields           (9.7: none)
--   Lawns            ground tiles of their own (kind, rect): the forest's floor
--   TreeLines        the orchard's fence, 9.7 the zones' screen hedges (kind, points)
--   Woods            the forest: its rect (its trees on a jittered grid) and its clearings (the lodge's: no tree)
--   Orchard          the orchard's rect (its fruit trees in rows; the cottage on its east edge)
--   Streams          the millrace from the forest past the mill into the pond (id, width, its middle line's points)
--   Zones            9.7 the run zones: id (its place's), rect (the fenced area round it: a screen hedge and invisible
--                    walls on its edge), arrive (where a run's party arrives: its front yard, facing the door)
--   Plots            four players' plots in the lobby's north row (SandboxPlots claims one per player), from Lobby.plots:
--                      rect        the plot's ground (x0, x1, z0, z1)
--                      warehouse   the building: its middle at the ground and its size (x across, y up, z deep);
--                                  its roller door in the south wall, DoorWidth wide, in the middle
--                      door        outside the roller door's middle, looking out (south)
--                      vanSpot     where the van stood before 9.7 (the UNLOAD HERE bay's middle; no van parks there now)
--                      unload      the bay's circle (shared/WarehouseLayout.luau's paint)
--                      spawn       a spot in front of the warehouse (the admin's TO WAREHOUSE)
--                      board       (8.0's Moving contracts board's spot: none is built since 9.7)
--   Houses           the six places to empty (design/countryside/plan.json `spots`; tests/sandboxhouses_test.luau holds
--                    them to it), each a run's house (Config.Moving.Sandbox.Houses, by id; server/Runs.luau: a portal
--                    each in the lobby). In this order: the farmstead, the pond cabin, the lone house, the forest
--                    lodge, the old mill, the orchard cottage. Each:
--                      id          the spot's (the farmstead's sandbox_house as ever)
--                      name        what the portal, the guide and its signs call it (made up, in English words)
--                      street      the road it stood on (its yard's name: the contract's address, the guide's words)
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
--                      curb        the truck's pivot in its yard (the Sprinter, 21.8 long: its back 2 studs in from the
--                                  yard's edge nearest the door, its nose away from the door): a run parks it there
--                      back        only where the house has a back door (the farmstead's): outside it, looking out
--   House            Houses[1], The Old Farmstead: what only the farmstead has reads it (server/HouseMesh.luau dresses
--                    only it, the menu's drift shows it). 8.1: the box is the owner's Blender house's (server/HouseMesh
--                    .luau dresses only a box of its size). 8.2.1: the owner's big European house (design/blender-house/
--                    house.py TARGET "sandbox": 44 × 14.5 × 34). 8.3 the big move: back, its back door (the model's, in
--                    the middle of its back wall; outside it, looking out: south), a second way in and out of a run
--   SandboxMap.plotAt(x, z)   the plot whose rect holds the point (nil: none)
--   SandboxMap.house(id)      the house of that id (nil: none, an id of an older map's too)
--   SandboxMap.houseAt(x, z, margin)   the first house whose lot holds the point or lies within `margin` of it (nil: none)
--   SandboxMap.zone(id)       9.7: the run zone of that house id (nil: none)
--   SandboxMap.zoneAt(x, z, margin?)   9.7: the run zone whose rect (grown by `margin`) holds the point (nil: none)
--   SandboxMap.portal(id)     9.7: the lobby's portal of that house id (nil: none)
--   SandboxMap.inLobby(x, z, margin?)  9.7: is the point in the lobby's bounds (grown by `margin`)?
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
-- 9.7: a run zone, the lobby's plot, portal and shops, the lobby
export type Zone = { id: string, rect: Rect, arrive: Spot }
export type LobbyPlot = { id: number, x: number, wall: number, rect: Rect }
export type Portal = { house: string, name: string, x: number, z: number, yaw: number, pad: Rect, foot: Rect, back: Spot }
export type Lobby = {
	bounds: Rect,
	hedge: number,
	far: number,
	plaza: Rect,
	spawn: Spot,
	spawnApart: number,
	dispatch: Spot,
	fountain: { x: number, z: number, r: number },
	plots: { LobbyPlot },
	portals: { Portal },
	shops: { paint: { spot: Spot, rect: Rect, stand: Spot }, leaders: { spot: Spot, rect: Rect }, auction: { spot: Spot, rect: Rect } },
	lamps: { { x: number, z: number } },
	trees: { { kind: string, x: number, z: number } },
}

SandboxMap.GroundTop = 0
SandboxMap.RoadTop = 0.4

-- BEGIN LOBBY (tools/lobby/sandboxmap.py writes these lines from design/lobby/plan.json: do not edit them)
SandboxMap.Lobby = {
	bounds = { x0 = 1560, x1 = 2040, z0 = -200, z1 = 200 },
	hedge = 2,
	far = 1000,
	plaza = { x0 = 1635, x1 = 1965, z0 = -54, z1 = 150 },
	spawn = { x = 1800, y = 3, z = 10, yaw = 180 },
	spawnApart = 6,
	dispatch = { x = 1800, y = 0, z = -44, yaw = 180 },
	fountain = { x = 1800, z = 70, r = 9 },
	plots = {
		{ id = 1, x = 1626, wall = -100, rect = { x0 = 1570, x1 = 1682, z0 = -190, z1 = -60 } },
		{ id = 2, x = 1742, wall = -100, rect = { x0 = 1686, x1 = 1798, z0 = -190, z1 = -60 } },
		{ id = 3, x = 1858, wall = -100, rect = { x0 = 1802, x1 = 1914, z0 = -190, z1 = -60 } },
		{ id = 4, x = 1974, wall = -100, rect = { x0 = 1918, x1 = 2030, z0 = -190, z1 = -60 } },
	},
	portals = {
		{ house = "pond_cabin", name = "The Pond Cabin", x = 1595, z = 0, yaw = 270, pad = { x0 = 1600, x1 = 1614, z0 = -7, z1 = 7 }, foot = { x0 = 1582, x1 = 1597, z0 = -10, z1 = 10 }, back = { x = 1618, y = 3, z = 0, yaw = 270 } },
		{ house = "old_mill", name = "The Old Mill", x = 1595, z = 96, yaw = 270, pad = { x0 = 1600, x1 = 1614, z0 = 89, z1 = 103 }, foot = { x0 = 1582, x1 = 1597, z0 = 86, z1 = 106 }, back = { x = 1618, y = 3, z = 96, yaw = 270 } },
		{ house = "sandbox_house", name = "The Old Farmstead", x = 1692, z = 176, yaw = 0, pad = { x0 = 1685, x1 = 1699, z0 = 157, z1 = 171 }, foot = { x0 = 1682, x1 = 1702, z0 = 174, z1 = 189 }, back = { x = 1692, y = 3, z = 153, yaw = 0 } },
		{ house = "lone_house", name = "The Lone House", x = 1908, z = 176, yaw = 0, pad = { x0 = 1901, x1 = 1915, z0 = 157, z1 = 171 }, foot = { x0 = 1898, x1 = 1918, z0 = 174, z1 = 189 }, back = { x = 1908, y = 3, z = 153, yaw = 0 } },
		{ house = "forest_lodge", name = "The Forest Lodge", x = 2005, z = 96, yaw = 90, pad = { x0 = 1986, x1 = 2000, z0 = 89, z1 = 103 }, foot = { x0 = 2003, x1 = 2018, z0 = 86, z1 = 106 }, back = { x = 1982, y = 3, z = 96, yaw = 90 } },
		{ house = "orchard_cottage", name = "The Orchard Cottage", x = 2005, z = 0, yaw = 90, pad = { x0 = 1986, x1 = 2000, z0 = -7, z1 = 7 }, foot = { x0 = 2003, x1 = 2018, z0 = -10, z1 = 10 }, back = { x = 1982, y = 3, z = 0, yaw = 90 } },
	},
	shops = {
		paint = { spot = { x = 2006, y = 0, z = -40, yaw = 90 }, rect = { x0 = 2006, x1 = 2018, z0 = -51, z1 = -29 }, stand = { x = 2002, y = 3, z = -40, yaw = 270 } },
		leaders = { spot = { x = 1594, y = 0, z = -40, yaw = 270 }, rect = { x0 = 1591.5, x1 = 1596.5, z0 = -52, z1 = -28 } },
		auction = { spot = { x = 1800, y = 0, z = 156, yaw = 0 }, rect = { x0 = 1774, x1 = 1826, z0 = 152, z1 = 190 } },
	},
	lamps = { { x = 1635, z = -54 }, { x = 1965, z = -54 }, { x = 1635, z = 150 }, { x = 1965, z = 150 }, { x = 1740, z = -54 }, { x = 1860, z = -54 }, { x = 1635, z = 48 }, { x = 1965, z = 48 } },
	trees = {
		{ kind = "linden", x = 1575, z = 180 },
		{ kind = "oak", x = 2025, z = 180 },
		{ kind = "birch", x = 1640, z = 186 },
		{ kind = "birch", x = 1960, z = 186 },
		{ kind = "linden", x = 1572, z = 140 },
		{ kind = "oak", x = 2028, z = 140 },
		{ kind = "birch", x = 1574, z = -30 },
		{ kind = "birch", x = 2026, z = -30 },
	},
} :: Lobby
-- END LOBBY

-- BEGIN COUNTRYSIDE (tools/countryside/sandboxmap.py writes these lines from design/countryside/plan.json: do not edit them)
SandboxMap.Bounds = { x0 = -1180, x1 = 2080, z0 = -680, z1 = 760 } :: Rect
SandboxMap.Roads = {
	{ name = "Pražská", x0 = -30, x1 = 30, z0 = 452, z1 = 504, lane = true, yard = true },
	{ name = "Mill Lane", x0 = -1066, x1 = -1012, z0 = -84, z1 = -36, lane = true, yard = true },
	{ name = "Wood Lane", x0 = -967, x1 = -913, z0 = -452, z1 = -404, lane = true, yard = true },
	{ name = "Hill Road", x0 = -583, x1 = -531, z0 = -460, z1 = -412, lane = true, yard = true },
	{ name = "Orchard Lane", x0 = 222, x1 = 270, z0 = -494, z1 = -446, lane = true, yard = true },
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
} :: { Landmark }
SandboxMap.Fields = {
} :: { Field }
SandboxMap.Lawns = {
	{ kind = "forest", x0 = -1160, x1 = -760, z0 = -672, z1 = -500 },
	{ kind = "forest", x0 = -1160, x1 = -760, z0 = -392, z1 = -250 },
	{ kind = "forest", x0 = -1160, x1 = -1005, z0 = -500, z1 = -392 },
	{ kind = "forest", x0 = -895, x1 = -760, z0 = -500, z1 = -392 },
} :: { Lawn }
SandboxMap.TreeLines = {
	{ kind = "fence", points = { { x = 217, z = -495 }, { x = 217, z = -650 }, { x = 30, z = -650 }, { x = 30, z = -300 }, { x = 217, z = -300 }, { x = 217, z = -445 } } },
	{ kind = "screen", points = { { x = -190, z = 440 }, { x = 170, z = 440 }, { x = 170, z = 712 }, { x = -190, z = 712 }, { x = -190, z = 440 } } },
	{ kind = "screen", points = { { x = -1170, z = 368 }, { x = -860, z = 368 }, { x = -860, z = 580 }, { x = -1170, z = 580 }, { x = -1170, z = 368 } } },
	{ kind = "screen", points = { { x = -650, z = -525 }, { x = -515, z = -525 }, { x = -515, z = -395 }, { x = -650, z = -395 }, { x = -650, z = -525 } } },
	{ kind = "screen", points = { { x = -1015, z = -512 }, { x = -885, z = -512 }, { x = -885, z = -386 }, { x = -1015, z = -386 }, { x = -1015, z = -512 } } },
	{ kind = "screen", points = { { x = -1112, z = -150 }, { x = -995, z = -150 }, { x = -995, z = 46 }, { x = -1112, z = 46 }, { x = -1112, z = -150 } } },
	{ kind = "screen", points = { { x = 108, z = -548 }, { x = 292, z = -548 }, { x = 292, z = -384 }, { x = 108, z = -384 }, { x = 108, z = -548 } } },
} :: { TreeLine }
SandboxMap.Woods = {
	{ id = "forest", x0 = -1160, x1 = -760, z0 = -672, z1 = -250, clearings = { { x0 = -1005, x1 = -895, z0 = -500, z1 = -392 } } },
} :: { Wood }
SandboxMap.Orchard = { x0 = 30, x1 = 216, z0 = -650, z1 = -300 } :: Rect
SandboxMap.Streams = {
	{ id = "millrace", width = 8, points = { { x = -1110, z = -676 }, { x = -1096, z = -560 }, { x = -1104, z = -440 }, { x = -1090, z = -320 }, { x = -1092, z = -200 }, { x = -1078, z = -134 }, { x = -1078, z = 10 }, { x = -1082, z = 120 }, { x = -1070, z = 250 }, { x = -1060, z = 386 } } },
} :: { Stream }
SandboxMap.Zones = {
	{ id = "sandbox_house", rect = { x0 = -190, x1 = 170, z0 = 440, z1 = 712 }, arrive = { x = 0, y = 3, z = 513, yaw = 180 } },
	{ id = "pond_cabin", rect = { x0 = -1170, x1 = -860, z0 = 368, z1 = 580 }, arrive = { x = -923.2, y = 3, z = 470, yaw = 90 } },
	{ id = "lone_house", rect = { x0 = -650, x1 = -515, z0 = -525, z1 = -395 }, arrive = { x = -584.2, y = 3, z = -436, yaw = 90 } },
	{ id = "forest_lodge", rect = { x0 = -1015, x1 = -885, z0 = -512, z1 = -386 }, arrive = { x = -940, y = 3, z = -453.2, yaw = 0 } },
	{ id = "old_mill", rect = { x0 = -1112, x1 = -995, z0 = -150, z1 = 46 }, arrive = { x = -1060, y = 3, z = -34.8, yaw = 180 } },
	{ id = "orchard_cottage", rect = { x0 = 108, x1 = 292, z0 = -548, z1 = -384 }, arrive = { x = 220.8, y = 3, z = -470, yaw = 90 } },
} :: { Zone }
-- END COUNTRYSIDE

SandboxMap.DoorWidth = 26 -- the warehouse's roller door
SandboxMap.VanGap = 6 -- studs from the warehouse's front wall to where the van's back stood (the bay's middle)

-- 9.7: the plots are the lobby's (Lobby.plots: their middles across, their warehouses' front walls), each warehouse
-- looking south onto the plaza as ever (its frame only moved: shared/WarehouseLayout.luau)
local plots: { Plot } = {}
for _, p in SandboxMap.Lobby.plots do
	local x, wall = p.x, p.wall
	plots[p.id] = {
		id = p.id,
		rect = { x0 = p.rect.x0, x1 = p.rect.x1, z0 = p.rect.z0, z1 = p.rect.z1 },
		warehouse = { x = x, y = 0, z = wall - 30, sx = 80, sy = 24, sz = 60 },
		door = { x = x, y = 0, z = wall, yaw = 180 },
		vanSpot = { x = x, y = SandboxMap.RoadTop, z = wall + SandboxMap.VanGap + 11, yaw = 180 }, -- (the Sprinter 22 long: its back 6 off the wall)
		unload = { x = x, z = wall + 8, r = 16 },
		spawn = { x = x + 22, y = 3, z = wall + 18, yaw = 180 },
		board = { x = x - 24, y = 0, z = wall + 1, yaw = 180 },
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

local zoneOf: { [string]: Zone } = {}
for _, z in SandboxMap.Zones do
	zoneOf[z.id] = z
end
local portalOf: { [string]: Portal } = {}
for _, p in SandboxMap.Lobby.portals do
	portalOf[p.house] = p
end

function SandboxMap.zone(id: any): Zone?
	return if type(id) == "string" then zoneOf[id] else nil
end

function SandboxMap.zoneAt(x: number, z: number, margin: number?): Zone?
	local m = margin or 0
	for _, zone in SandboxMap.Zones do
		local r = zone.rect
		if x >= r.x0 - m and x <= r.x1 + m and z >= r.z0 - m and z <= r.z1 + m then
			return zone
		end
	end
	return nil
end

function SandboxMap.portal(id: any): Portal?
	return if type(id) == "string" then portalOf[id] else nil
end

function SandboxMap.inLobby(x: number, z: number, margin: number?): boolean
	local m = margin or 0
	local b = SandboxMap.Lobby.bounds
	return x >= b.x0 - m and x <= b.x1 + m and z >= b.z0 - m and z <= b.z1 + m
end

function SandboxMap.cframe(spot: Spot): any
	return (CFrame :: any).new(spot.x, spot.y, spot.z) * (CFrame :: any).Angles(0, math.rad(spot.yaw), 0)
end

return SandboxMap
