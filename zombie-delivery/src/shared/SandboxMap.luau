--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the owner's small test world in place of the city. 9.7 runs (the owner:
-- "shrink the map ... one little lobby, like Dungeon Quest: there you go into a dungeon, here you go into a house"): the
-- LOBBY (design/lobby/plan.py, plan.json; its section below) where everybody is between runs, a compact square with the
-- plaza, the spawn, the Deliveros dispatch, the four player plots (each with a warehouse, its display stands), the shops
-- and (10.4) one PLAY circle where parties gather for a run. 10.6 the floating islands (the owner: "the world is made of
-- blocks: the lobby one big block, each map a smaller block that holds only that map ... floating islands in the sky";
-- design/islands/plan.py, plan.json; its section below): the lobby stands on the biggest island, each of the six places
-- to empty (Houses) on an island of its own round it, at its own height, the sky all round and under them; a run's fade
-- takes you across (no roads, no driving), its truck parked at the curb by the door. Plain data (numbers only: the pure
-- tests run it outside Roblox); the builders read it.
--
-- Coordinates: studs, y up. The lobby's ground's top at GroundTop, the asphalt's at RoadTop; 10.6 a map island's ground
-- at its own `top` (its yard's asphalt RoadTop - GroundTop over it: SandboxMap.groundAt, roadAt), every spot of its place
-- with its y on it. A spot is { x, y, z, yaw }: yaw in degrees about Y, the way its front looks: 0 looks north (-z), 90
-- west (-x), 180 south (+z), 270 east (+x); in Roblox: CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
-- (SandboxMap.cframe).
--
--   9.7 the lobby (design/lobby/plan.json; tools/lobby/sandboxmap.py writes Lobby between the BEGIN LOBBY and END
--   LOBBY lines: change the plan, run it again):
--   Lobby            bounds (the square: a low hedge `hedge` in from it, invisible walls on it; 10.6 its island's top a
--                    rim of grass round it), far (studs from its island to every other island at least), plaza, spawn
--                    (a Spot; spawnApart: the players' spawns apart), dispatch (the Deliveros dispatch kiosk), fountain,
--                    plots ({ id, x, wall, rect }: Plots below), 10.4 play ({ x, z, r, back }: the PLAY circle's middle
--                    on the ground and its radius, config Runs.Play.Radius; back: a Spot just off it facing it, where a
--                    party comes back from a run), shops (paint, leaders, auction: their spots and rects; paint's stand at
--                    its counter), lamps, trees
--   10.6 the islands (design/islands/plan.json; tools/islands/sandboxmap.py writes these between the BEGIN ISLANDS and
--   END ISLANDS lines: change the plan, run it again; 9.4 – 10.5's countryside section went with its plan):
--   Islands          one per island, the lobby's first: id, house (the place to empty on it; none: the lobby's), name,
--                    x, z (its top's middle), sx, sz (its top's size), top (its top's height), depth (from its top to the
--                    tip of the rock under it: its bottom is top - depth), rect (its top), walls (the walled area on it:
--                    the lobby's bounds; a map island's run zone), home (where the fall catch puts somebody back when
--                    where they stood last is no good: the lobby's spawn, a zone's arrive), look (its grass, dirt, stone
--                    and rock colours: shared/IslandLooks.luau), seed (its rock's dice)
--   Rocks            the decorative floating rocks round the islands (x, z, top, size, depth, seed; nothing on them)
--   Bounds           round every island and rock: nothing of the world is outside them
--   Roads            the yards: each place's yard in front of its door where its truck stands, big enough for a round's
--                    vans side by side and in rows (name: the road its place stood on, its words' "on Pond Lane"; lane,
--                    yard: true)
--   Landmarks        each place's surroundings (id, name, kind, rect, yaw: the way its front looks): the farm's barn, old
--                    tractor, stackyard, paddock and muck heap; the fish pond with its jetty and boat; the lone house's
--                    garden; the lodge's woodpile; the mill's spring, weir, footbridge and waterfall (its millrace off its
--                    island's edge); the orchard's beehives (shared/CountryLooks.luau draws them)
--   Fields           (none)
--   Lawns            ground tiles of their own (kind, rect): the lodge's forest floor
--   TreeLines        the orchard's fence, the lone house's windbreak, every map island's low rim hedge on its walls
--                    (kind, points)
--   Woods            the lodge's forest: its rect (its trees on a jittered grid) and its clearings (the lodge's: no tree)
--   Orchard          the orchard's rect (its fruit trees in rows; the cottage on its east side)
--   Streams          the mill's millrace from its spring past the mill and off its island's edge (id, width, its middle
--                    line's points)
--   Zones            9.7 the run zones, 10.6 the map islands' walled areas: id (its place's), rect (invisible walls and a
--                    low hedge on its edge), arrive (where a run's party arrives: its front yard, facing the door)
--   Houses           the six places to empty, each on its island (design/islands/plan.json `spots`;
--                    tests/sandboxhouses_test.luau holds them to it), each a run's house (Config.Moving.Sandbox.Houses, by
--                    id; 10.4: a party's lobby at the PLAY circle picks one: server/Parties.luau). In this order: the
--                    farmstead, the pond cabin, the lone house, the forest lodge, the old mill, the orchard cottage. Each:
--                      id          the spot's (the farmstead's sandbox_house as ever)
--                      name        what the PLAY panel, the guide and the signs call it (made up, in English words)
--                      street      the road it stood on (its yard's name: the contract's address, the guide's words)
--                      number      none (a spot of its own has no house number)
--                      kind        its inside's plan's kind (shared/HouseLayout.luau; its contract's, Config.Moving
--                                  .Sandbox.Houses): "big" the farmstead, "house" the lone house, the other four
--                                  shared/Layouts/Countryside.luau's "cabin", "lodge", "mill" and "cottage"
--                      look        its outside's kind: "farmstead" (server/SandboxWorld.luau's, the owner's Blender
--                                  house), else shared/VillageLooks.luau house's ("cabin", "old", "lodge", "mill",
--                                  "cottage": shared/VillageScenery.luau builds each in its own)
--                      island      10.6 the island it stands on (Islands' id)
--                      box         its footprint (x0, x1, z0, z1): sx along its front × sz deep, turned with its yaw
--                      lot         its garden: the box, 6 round it, its front up to its yard's edge (10 studs: the front
--                                  garden; the mill's west side stops at its wall: the millrace runs there)
--                      house       the walls' box: its footprint's middle, its bottom (its island's top), its size (sx
--                                  along x, sy the walls' height, sz along z; the roof over it)
--                      yaw         the way its front looks (its front door's)
--                      door        outside its front door, looking out to its yard (1.2 in from its box's front edge:
--                                  the look's front wall 1.5 in, its door 0.3 out of it)
--                      curb        the truck's pivot in its yard (the Sprinter, 21.8 long: its back 2 studs in from the
--                                  yard's edge nearest the door, its nose away from the door): a run parks it there (its y
--                                  the yard's asphalt)
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
--   SandboxMap.inPlay(x, z, margin?)   10.4: is the point in the PLAY circle (its radius grown by `margin`)?
--   SandboxMap.inLobby(x, z, margin?)  9.7: is the point in the lobby's bounds (grown by `margin`)?
--   SandboxMap.island(id)     10.6: the island of that id (nil: none)
--   SandboxMap.islandAt(x, z, margin?)   10.6: the island whose top (grown by `margin`) holds the point (nil: none)
--   SandboxMap.islandOf(houseId)   10.6: the island a place to empty stands on (nil: none)
--   SandboxMap.groundAt(x, z, margin?)  10.6: the ground's top there: its island's top (its top grown by `margin`: a
--                             piece hanging just past its edge; GroundTop off every island)
--   SandboxMap.roadAt(x, z)    10.6: a yard's asphalt's top there (groundAt and RoadTop - GroundTop over it)
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
	island: string,
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
-- 9.7: a run zone, the lobby's plot and shops, the lobby; 10.4 the PLAY circle
export type Zone = { id: string, rect: Rect, arrive: Spot }
export type LobbyPlot = { id: number, x: number, wall: number, rect: Rect }
export type Play = { x: number, z: number, r: number, back: Spot }
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
	play: Play,
	shops: { paint: { spot: Spot, rect: Rect, stand: Spot }, leaders: { spot: Spot, rect: Rect }, auction: { spot: Spot, rect: Rect } },
	lamps: { { x: number, z: number } },
	trees: { { kind: string, x: number, z: number } },
}
-- 10.6 an island (its look's colours { r, g, b }), a floating rock
export type IslandLook = { grass: { number }, dirt: { number }, stone: { number }, rock: { number } }
export type Island = {
	id: string,
	house: string?,
	name: string,
	x: number,
	z: number,
	sx: number,
	sz: number,
	top: number,
	depth: number,
	rect: Rect,
	walls: Rect,
	home: Spot,
	look: IslandLook,
	seed: number,
}
export type Rock = { x: number, z: number, top: number, size: number, depth: number, seed: number }

SandboxMap.GroundTop = 0
SandboxMap.RoadTop = 0.4

-- BEGIN LOBBY (tools/lobby/sandboxmap.py writes these lines from design/lobby/plan.json: do not edit them)
SandboxMap.Lobby = {
	bounds = { x0 = 1572, x1 = 2028, z0 = -128, z1 = 98 },
	hedge = 2,
	far = 300,
	plaza = { x0 = 1600, x1 = 2000, z0 = 6, z1 = 92 },
	spawn = { x = 1800, y = 3, z = 80, yaw = 0 },
	spawnApart = 6,
	dispatch = { x = 1760, y = 0, z = 44, yaw = 270 },
	fountain = { x = 1630, z = 48, r = 9 },
	plots = {
		{ id = 1, x = 1632, wall = -33, rect = { x0 = 1577, x1 = 1687, z0 = -123, z1 = 3 } },
		{ id = 2, x = 1744, wall = -33, rect = { x0 = 1689, x1 = 1799, z0 = -123, z1 = 3 } },
		{ id = 3, x = 1856, wall = -33, rect = { x0 = 1801, x1 = 1911, z0 = -123, z1 = 3 } },
		{ id = 4, x = 1968, wall = -33, rect = { x0 = 1913, x1 = 2023, z0 = -123, z1 = 3 } },
	},
	play = { x = 1800, z = 44, r = 16, back = { x = 1800, y = 3, z = 68, yaw = 0 } },
	shops = {
		paint = { spot = { x = 1864, y = 0, z = 44, yaw = 90 }, rect = { x0 = 1864, x1 = 1876, z0 = 33, z1 = 55 }, stand = { x = 1860, y = 3, z = 44, yaw = 270 } },
		leaders = { spot = { x = 1680, y = 0, z = 50, yaw = 270 }, rect = { x0 = 1677.5, x1 = 1682.5, z0 = 38, z1 = 62 } },
		auction = { spot = { x = 1930, y = 0, z = 44, yaw = 90 }, rect = { x0 = 1926, x1 = 1964, z0 = 18, z1 = 70 } },
	},
	lamps = { { x = 1600, z = 6 }, { x = 2000, z = 6 }, { x = 1600, z = 92 }, { x = 2000, z = 92 }, { x = 1710, z = 6 }, { x = 1890, z = 6 }, { x = 1710, z = 92 }, { x = 1890, z = 92 } },
	trees = {
		{ kind = "linden", x = 1586, z = 20 },
		{ kind = "oak", x = 2014, z = 20 },
		{ kind = "birch", x = 1586, z = 52 },
		{ kind = "birch", x = 2014, z = 52 },
		{ kind = "oak", x = 1586, z = 84 },
		{ kind = "linden", x = 2014, z = 84 },
	},
} :: Lobby
-- END LOBBY

-- BEGIN ISLANDS (tools/islands/sandboxmap.py writes these lines from design/islands/plan.json: do not edit them)
SandboxMap.Islands = {
	{ id = "lobby", name = "The Lobby", x = 1800, z = -15, sx = 492, sz = 262, top = 0, depth = 170, rect = { x0 = 1554, x1 = 2046, z0 = -146, z1 = 116 }, walls = { x0 = 1572, x1 = 2028, z0 = -128, z1 = 98 }, home = { x = 1800, y = 3, z = 80, yaw = 0 }, look = { grass = { 96, 138, 60 }, dirt = { 118, 88, 60 }, stone = { 132, 126, 118 }, rock = { 104, 98, 92 } }, seed = 11 },
	{ id = "farm", house = "sandbox_house", name = "The Old Farmstead", x = 1100, z = -620, sx = 384, sz = 260, top = 28, depth = 150, rect = { x0 = 908, x1 = 1292, z0 = -750, z1 = -490 }, walls = { x0 = 920, x1 = 1280, z0 = -738, z1 = -502 }, home = { x = 1100, y = 31, z = -664, yaw = 180 }, look = { grass = { 108, 142, 62 }, dirt = { 124, 90, 58 }, stone = { 138, 130, 120 }, rock = { 108, 100, 92 } }, seed = 21 },
	{ id = "pond", house = "pond_cabin", name = "The Pond Cabin", x = 1060, z = 380, sx = 336, sz = 224, top = 10, depth = 120, rect = { x0 = 892, x1 = 1228, z0 = 268, z1 = 492 }, walls = { x0 = 904, x1 = 1216, z0 = 280, z1 = 480 }, home = { x = 1150.8, y = 13, z = 380, yaw = 90 }, look = { grass = { 88, 140, 66 }, dirt = { 112, 86, 58 }, stone = { 126, 124, 118 }, rock = { 98, 96, 92 } }, seed = 22 },
	{ id = "lone", house = "lone_house", name = "The Lone House", x = 1900, z = 690, sx = 168, sz = 184, top = 52, depth = 110, rect = { x0 = 1816, x1 = 1984, z0 = 598, z1 = 782 }, walls = { x0 = 1828, x1 = 1972, z0 = 610, z1 = 770 }, home = { x = 1904.8, y = 55, z = 690, yaw = 90 }, look = { grass = { 102, 146, 64 }, dirt = { 122, 92, 62 }, stone = { 140, 134, 124 }, rock = { 110, 104, 96 } }, seed = 23 },
	{ id = "lodge", house = "forest_lodge", name = "The Forest Lodge", x = 1950, z = -770, sx = 284, sz = 242, top = 74, depth = 140, rect = { x0 = 1808, x1 = 2092, z0 = -891, z1 = -649 }, walls = { x0 = 1820, x1 = 2080, z0 = -879, z1 = -661 }, home = { x = 1950, y = 77, z = -770.2, yaw = 0 }, look = { grass = { 76, 114, 54 }, dirt = { 104, 80, 56 }, stone = { 118, 116, 110 }, rock = { 92, 90, 86 } }, seed = 24 },
	{ id = "mill", house = "old_mill", name = "The Old Mill", x = 2610, z = -440, sx = 244, sz = 212, top = 40, depth = 120, rect = { x0 = 2488, x1 = 2732, z0 = -546, z1 = -334 }, walls = { x0 = 2500, x1 = 2720, z0 = -534, z1 = -346 }, home = { x = 2610, y = 43, z = -466.8, yaw = 180 }, look = { grass = { 92, 136, 62 }, dirt = { 116, 88, 60 }, stone = { 130, 128, 122 }, rock = { 100, 98, 94 } }, seed = 25 },
	{ id = "orchard", house = "orchard_cottage", name = "The Orchard Cottage", x = 2620, z = 420, sx = 294, sz = 228, top = 18, depth = 120, rect = { x0 = 2473, x1 = 2767, z0 = 306, z1 = 534 }, walls = { x0 = 2485, x1 = 2755, z0 = 318, z1 = 522 }, home = { x = 2685.8, y = 21, z = 420, yaw = 90 }, look = { grass = { 112, 152, 70 }, dirt = { 126, 94, 62 }, stone = { 142, 136, 126 }, rock = { 112, 106, 98 } }, seed = 26 },
} :: { Island }
SandboxMap.Rocks = {
	{ x = 836, z = -836, top = 40, size = 26, depth = 34, seed = 1 },
	{ x = 1330, z = -440, top = 18, size = 18, depth = 24, seed = 2 },
	{ x = 2150, z = -910, top = 88, size = 22, depth = 30, seed = 3 },
	{ x = 2780, z = -290, top = 54, size = 20, depth = 26, seed = 4 },
	{ x = 2416, z = 604, top = 30, size = 24, depth = 30, seed = 5 },
	{ x = 2830, z = 270, top = 6, size = 16, depth = 22, seed = 6 },
	{ x = 1770, z = 820, top = 64, size = 18, depth = 24, seed = 7 },
	{ x = 826, z = 566, top = 22, size = 22, depth = 28, seed = 8 },
	{ x = 1500, z = 190, top = 14, size = 20, depth = 26, seed = 9 },
	{ x = 2110, z = -230, top = 26, size = 16, depth = 22, seed = 10 },
	{ x = 1500, z = -240, top = -18, size = 24, depth = 30, seed = 11 },
} :: { Rock }
SandboxMap.Bounds = { x0 = 760, x1 = 2900, z0 = -980, z1 = 880 } :: Rect
SandboxMap.Roads = {
	{ name = "Pražská", x0 = 1036, x1 = 1164, z0 = -729, z1 = -673, lane = true, yard = true },
	{ name = "Pond Lane", x0 = 1152, x1 = 1208, z0 = 316, z1 = 444, lane = true, yard = true },
	{ name = "Hill Road", x0 = 1906, x1 = 1962, z0 = 626, z1 = 754, lane = true, yard = true },
	{ name = "Wood Lane", x0 = 1886, x1 = 2014, z0 = -769, z1 = -713, lane = true, yard = true },
	{ name = "Mill Lane", x0 = 2546, x1 = 2674, z0 = -524, z1 = -468, lane = true, yard = true },
	{ name = "Orchard Lane", x0 = 2687, x1 = 2743, z0 = 356, z1 = 484, lane = true, yard = true },
} :: { Road }
SandboxMap.Landmarks = {
	{ id = "barn", name = "The Barn", kind = "barn", x0 = 950, x1 = 1006, z0 = -670, z1 = -622, yaw = 270 },
	{ id = "muckheap", name = "The Muck Heap", kind = "muckheap", x0 = 950, x1 = 994, z0 = -610, z1 = -580, yaw = 270 },
	{ id = "bales", name = "The Stackyard", kind = "bales", x0 = 1182, x1 = 1250, z0 = -654, z1 = -590, yaw = 0 },
	{ id = "tractor", name = "The Old Tractor", kind = "tractor", x0 = 1190, x1 = 1254, z0 = -574, z1 = -544, yaw = 270 },
	{ id = "paddock", name = "The Paddock", kind = "paddock", x0 = 1060, x1 = 1160, z0 = -570, z1 = -512, yaw = 0 },
	{ id = "pond", name = "The Fish Pond", kind = "fishpond", x0 = 914, x1 = 1117, z0 = 290, z1 = 470, yaw = 270 },
	{ id = "garden", name = "The Garden", kind = "garden", x0 = 1858, x1 = 1900, z0 = 618, z1 = 662, yaw = 270 },
	{ id = "woodyard", name = "The Woodpile", kind = "woodyard", x0 = 1888, x1 = 1914, z0 = -807, z1 = -783, yaw = 180 },
	{ id = "spring", name = "The Spring", kind = "spring", x0 = 2576, x1 = 2608, z0 = -382, z1 = -352, yaw = 0 },
	{ id = "weir", name = "The Weir", kind = "weir", x0 = 2582, x1 = 2602, z0 = -414, z1 = -402, yaw = 180 },
	{ id = "footbridge", name = "The Footbridge", kind = "footbridge", x0 = 2520, x1 = 2528, z0 = -470, z1 = -446, yaw = 90 },
	{ id = "waterfall", name = "The Waterfall", kind = "waterfall", x0 = 2478, x1 = 2498, z0 = -466, z1 = -450, yaw = 90 },
	{ id = "apiary", name = "The Beehives", kind = "apiary", x0 = 2647, x1 = 2683, z0 = 452, z1 = 470, yaw = 270 },
} :: { Landmark }
SandboxMap.Fields = {
} :: { Field }
SandboxMap.Lawns = {
	{ kind = "forest", x0 = 1820, x1 = 2080, z0 = -879, z1 = -823 },
	{ kind = "forest", x0 = 1820, x1 = 2080, z0 = -695, z1 = -661 },
	{ kind = "forest", x0 = 1820, x1 = 1872, z0 = -823, z1 = -695 },
	{ kind = "forest", x0 = 2028, x1 = 2080, z0 = -823, z1 = -695 },
} :: { Lawn }
SandboxMap.TreeLines = {
	{ kind = "hedge", points = { { x = 920, z = -738 }, { x = 1280, z = -738 }, { x = 1280, z = -502 }, { x = 920, z = -502 }, { x = 920, z = -738 } } },
	{ kind = "hedge", points = { { x = 904, z = 280 }, { x = 1216, z = 280 }, { x = 1216, z = 480 }, { x = 904, z = 480 }, { x = 904, z = 280 } } },
	{ kind = "windbreak", points = { { x = 1844, z = 680 }, { x = 1844, z = 756 } } },
	{ kind = "hedge", points = { { x = 1828, z = 610 }, { x = 1972, z = 610 }, { x = 1972, z = 770 }, { x = 1828, z = 770 }, { x = 1828, z = 610 } } },
	{ kind = "hedge", points = { { x = 1820, z = -879 }, { x = 2080, z = -879 }, { x = 2080, z = -661 }, { x = 1820, z = -661 }, { x = 1820, z = -879 } } },
	{ kind = "hedge", points = { { x = 2500, z = -464 }, { x = 2500, z = -534 }, { x = 2720, z = -534 }, { x = 2720, z = -346 }, { x = 2500, z = -346 }, { x = 2500, z = -452 } } },
	{ kind = "fence", points = { { x = 2643, z = 410 }, { x = 2643, z = 328 }, { x = 2495, z = 328 }, { x = 2495, z = 512 }, { x = 2643, z = 512 }, { x = 2643, z = 430 } } },
	{ kind = "hedge", points = { { x = 2485, z = 318 }, { x = 2755, z = 318 }, { x = 2755, z = 522 }, { x = 2485, z = 522 }, { x = 2485, z = 318 } } },
} :: { TreeLine }
SandboxMap.Woods = {
	{ id = "forest", x0 = 1820, x1 = 2080, z0 = -879, z1 = -661, clearings = { { x0 = 1872, x1 = 2028, z0 = -823, z1 = -695 } } },
} :: { Wood }
SandboxMap.Orchard = { x0 = 2497, x1 = 2641, z0 = 330, z1 = 510 } :: Rect
SandboxMap.Streams = {
	{ id = "millrace", width = 8, points = { { x = 2592, z = -372 }, { x = 2592, z = -408 }, { x = 2592, z = -458 }, { x = 2550, z = -458 }, { x = 2488.5, z = -458 } } },
} :: { Stream }
SandboxMap.Zones = {
	{ id = "sandbox_house", rect = { x0 = 920, x1 = 1280, z0 = -738, z1 = -502 }, arrive = { x = 1100, y = 31, z = -664, yaw = 180 } },
	{ id = "pond_cabin", rect = { x0 = 904, x1 = 1216, z0 = 280, z1 = 480 }, arrive = { x = 1150.8, y = 13, z = 380, yaw = 90 } },
	{ id = "lone_house", rect = { x0 = 1828, x1 = 1972, z0 = 610, z1 = 770 }, arrive = { x = 1904.8, y = 55, z = 690, yaw = 90 } },
	{ id = "forest_lodge", rect = { x0 = 1820, x1 = 2080, z0 = -879, z1 = -661 }, arrive = { x = 1950, y = 77, z = -770.2, yaw = 0 } },
	{ id = "old_mill", rect = { x0 = 2500, x1 = 2720, z0 = -534, z1 = -346 }, arrive = { x = 2610, y = 43, z = -466.8, yaw = 180 } },
	{ id = "orchard_cottage", rect = { x0 = 2485, x1 = 2755, z0 = 318, z1 = 522 }, arrive = { x = 2685.8, y = 21, z = 420, yaw = 90 } },
} :: { Zone }
SandboxMap.Houses = {
	{ id = "sandbox_house", name = "The Old Farmstead", street = "Pražská", kind = "big", look = "farmstead", island = "farm", box = { x0 = 1078, x1 = 1122, z0 = -654, z1 = -620 }, lot = { x0 = 1040, x1 = 1160, z0 = -673, z1 = -577 }, house = { x = 1100, y = 28, z = -637, sx = 44, sy = 14.5, sz = 34 }, yaw = 0, door = { x = 1100, y = 28, z = -654, yaw = 0 }, curb = { x = 1100, y = 28.4, z = -685, yaw = 0 }, back = { x = 1100, y = 28, z = -620, yaw = 180 } },
	{ id = "pond_cabin", name = "The Pond Cabin", street = "Pond Lane", kind = "cabin", look = "cabin", island = "pond", box = { x0 = 1124, x1 = 1142, z0 = 368, z1 = 392 }, lot = { x0 = 1118, x1 = 1152, z0 = 362, z1 = 398 }, house = { x = 1133, y = 10, z = 380, sx = 18, sy = 10, sz = 24 }, yaw = 270, door = { x = 1140.8, y = 10, z = 380, yaw = 270 }, curb = { x = 1165, y = 10.4, z = 380, yaw = 270 } },
	{ id = "lone_house", name = "The Lone House", street = "Hill Road", kind = "house", look = "old", island = "lone", box = { x0 = 1872, x1 = 1896, z0 = 675, z1 = 705 }, lot = { x0 = 1866, x1 = 1906, z0 = 669, z1 = 711 }, house = { x = 1884, y = 52, z = 690, sx = 24, sy = 10, sz = 30 }, yaw = 270, door = { x = 1894.8, y = 52, z = 690, yaw = 270 }, curb = { x = 1919, y = 52.4, z = 690, yaw = 270 } },
	{ id = "forest_lodge", name = "The Forest Lodge", street = "Wood Lane", kind = "lodge", look = "lodge", island = "lodge", box = { x0 = 1936, x1 = 1964, z0 = -801, z1 = -779 }, lot = { x0 = 1930, x1 = 1970, z0 = -807, z1 = -769 }, house = { x = 1950, y = 74, z = -790, sx = 28, sy = 10, sz = 22 }, yaw = 180, door = { x = 1950, y = 74, z = -780.2, yaw = 180 }, curb = { x = 1950, y = 74.4, z = -756, yaw = 180 } },
	{ id = "old_mill", name = "The Old Mill", street = "Mill Lane", kind = "mill", look = "mill", island = "mill", box = { x0 = 2598, x1 = 2622, z0 = -458, z1 = -432 }, lot = { x0 = 2598, x1 = 2628, z0 = -468, z1 = -426 }, house = { x = 2610, y = 40, z = -445, sx = 24, sy = 10, sz = 26 }, yaw = 0, door = { x = 2610, y = 40, z = -456.8, yaw = 0 }, curb = { x = 2610, y = 40.4, z = -481, yaw = 0 } },
	{ id = "orchard_cottage", name = "The Orchard Cottage", street = "Orchard Lane", kind = "cottage", look = "cottage", island = "orchard", box = { x0 = 2657, x1 = 2677, z0 = 407, z1 = 433 }, lot = { x0 = 2651, x1 = 2687, z0 = 401, z1 = 439 }, house = { x = 2667, y = 18, z = 420, sx = 20, sy = 10, sz = 26 }, yaw = 270, door = { x = 2675.8, y = 18, z = 420, yaw = 270 }, curb = { x = 2700, y = 18.4, z = 420, yaw = 270 } },
} :: { House }
-- END ISLANDS

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

function SandboxMap.inPlay(x: number, z: number, margin: number?): boolean
	local p = SandboxMap.Lobby.play
	local r = p.r + (margin or 0)
	return (x - p.x) ^ 2 + (z - p.z) ^ 2 <= r * r
end

function SandboxMap.inLobby(x: number, z: number, margin: number?): boolean
	local m = margin or 0
	local b = SandboxMap.Lobby.bounds
	return x >= b.x0 - m and x <= b.x1 + m and z >= b.z0 - m and z <= b.z1 + m
end

-- ── 10.6 the islands ───────────────────────────────────────────────────────

local islandById: { [string]: Island } = {}
for _, i in SandboxMap.Islands do
	islandById[i.id] = i
end

function SandboxMap.island(id: any): Island?
	return if type(id) == "string" then islandById[id] else nil
end

function SandboxMap.islandAt(x: number, z: number, margin: number?): Island?
	local m = margin or 0
	for _, i in SandboxMap.Islands do
		local r = i.rect
		if x >= r.x0 - m and x <= r.x1 + m and z >= r.z0 - m and z <= r.z1 + m then
			return i
		end
	end
	return nil
end

function SandboxMap.islandOf(houseId: any): Island?
	local h = SandboxMap.house(houseId)
	return if h then islandById[h.island] else nil
end

function SandboxMap.groundAt(x: number, z: number, margin: number?): number
	local i = SandboxMap.islandAt(x, z, margin)
	return if i then i.top else SandboxMap.GroundTop
end

function SandboxMap.roadAt(x: number, z: number): number
	return SandboxMap.groundAt(x, z) + SandboxMap.RoadTop - SandboxMap.GroundTop
end

function SandboxMap.cframe(spot: Spot): any
	return (CFrame :: any).new(spot.x, spot.y, spot.z) * (CFrame :: any).Angles(0, math.rad(spot.yaw), 0)
end

return SandboxMap
