--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the owner's small test world in place of the city. Houses to empty, the
-- roads, four player plots, each with a ZDC warehouse (its display plots), a van spot at its roller door and a Moving
-- contracts board. Plain data (numbers only: the pure tests run it outside Roblox); the builders read it. Jinočany
-- (design/jinocany/NAVRH.md §2, plan.json): the village's bounds, its step-1 streets and the six houses to empty.
--
-- Coordinates: studs, y up, the ground's top at GroundTop, the asphalt's at RoadTop. A spot is { x, y, z, yaw }: yaw
-- in degrees about Y, the way its front looks: 0 looks north (-z), 90 west (-x), 180 south (+z), 270 east (+x);
-- in Roblox: CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0) (SandboxMap.cframe).
--
--   Bounds           the world's edge (the scenery fills it; nothing you play with is outside): the Jinočany plan's
--                    (plan.json bounds, 1 600 × 1 440)
--   Roads            the asphalt rects: Pražská (north-south, the plots to the farmstead; renamed by the Jinočany plan,
--                    design/jinocany/NAVRH.md: the streets keep their Czech names, diacritics and all) and Depot Row
--                    (the plots'), first and second as ever; then the village's step-1 streets (plan.json roads of
--                    step 1): Hlavní (Depot Row on west through the village), Hornická (on to the map's west edge),
--                    Školní, Lidická and Na Pouštce (north off Hlavní), Fibichova and Smetanova (south off Hlavní) and
--                    Mirešická (along the south, from Fibichova's and Smetanova's ends to Pražská). They only touch (no
--                    two overlap but Pražská's top end on Depot Row): server/SandboxWorld.luau lays each one's asphalt
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
--   Houses           Jinočany step 1 (plan.json `enter`; tests/sandboxhouses_test.luau checks them against it): the six
--                    houses to empty, each a Moving contract of its own (Config.Moving.Sandbox.Houses, by id; server/
--                    Moving.luau offers one at a time). Each:
--                      id          plan.json's (the farmstead's sandbox_house as ever)
--                      name        what the card, the guide and its signs call it (made up, in English words)
--                      street      the road it stands on, one of Roads (the contract's address, the guide's words)
--                      number      its made-up house number (the address: "Hlavní 5"; the farmstead none)
--                      kind        its plan's kind (shared/HouseLayout.luau): "big" the farmstead, "house" the rest
--                      look        its outside's kind (plan.json houses' kind, for the village's art): "farmstead",
--                                  "old" (a Czech family house with a garden) or "row" (terraced)
--                      box         its footprint (x0, x1, z0, z1)
--                      lot         its garden: the box, the front yard up to its street's edge and a strip behind
--                      house       the walls' box: its footprint's middle, its bottom, its size (sx along x, sy the
--                                  walls' height, sz along z; the roof over it)
--                      yaw         the way its front looks (its front door's)
--                      door        outside its front door, looking out to its street
--                      curb        the van's pivot (the Sprinter, 22 long, across the street, its back 2 studs in from
--                                  the house's edge of it, its nose away from the door: "Call the van to the door")
--                      back        only where the house has a back door (the farmstead's): outside it, looking out
--   House            Houses[1], The Old Farmstead on Pražská (the Jinočany plan's names): what only the farmstead has
--                    reads it (server/HouseMesh.luau dresses only it, the menu's drift shows it). 8.1: the box is the
--                    owner's Blender house's (server/HouseMesh.luau dresses only a box of its size), its front wall where
--                    the chalet's always was (the door, the path and the curb unmoved). 8.2.1: the owner's big European
--                    house (design/blender-house/house.py TARGET "sandbox": 44 × 14.5 × 34, the chalet's old
--                    footprint). 8.3 the big move: back, its back door (the model's, in the middle of its back wall;
--                    outside it, looking out: south), a second way in and out of a move (server/Moving.luau SB.site)
--   SandboxMap.plotAt(x, z)   the plot whose rect holds the point (nil: none)
--   SandboxMap.house(id)      the house of that id (nil: none)
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

SandboxMap.GroundTop = 0
SandboxMap.RoadTop = 0.4
SandboxMap.Bounds = { x0 = -1180, x1 = 420, z0 = -680, z1 = 760 } :: Rect -- (Jinočany, plan.json; 8.0 – 8.9: ±340, -280 … 640)

SandboxMap.Roads = {
	{ name = "Pražská", x0 = -14, x1 = 14, z0 = -74, z1 = 470 },
	{ name = "Depot Row", x0 = -270, x1 = 270, z0 = -74, z1 = -46 },
	-- Jinočany step 1 (plan.json roads of step 1)
	{ name = "Hlavní", x0 = -1000, x1 = -270, z0 = -74, z1 = -46 },
	{ name = "Hornická", x0 = -1180, x1 = -1000, z0 = -74, z1 = -46 },
	{ name = "Školní", x0 = -572, x1 = -548, z0 = -470, z1 = -74 },
	{ name = "Lidická", x0 = -392, x1 = -368, z0 = -470, z1 = -74 },
	{ name = "Na Pouštce", x0 = -832, x1 = -808, z0 = -470, z1 = -74 },
	{ name = "Fibichova", x0 = -632, x1 = -608, z0 = -46, z1 = 300 },
	{ name = "Smetanova", x0 = -460, x1 = -436, z0 = -46, z1 = 300 },
	{ name = "Mirešická", x0 = -912, x1 = -14, z0 = 300, z1 = 324 },
} :: { { name: string, x0: number, x1: number, z0: number, z1: number } }

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

-- A family house of the village (plan.json `enter`): its box, its front door's spot and its curb as the plan has them,
-- the rest made from them (its walls WALLS high, its lot from its street's edge `edge` to BACK behind it).
local WALLS, BACK = 10, 6
local function family(id: string, name: string, street: string, number: number, look: string, box: Rect, door: Spot, curb: Spot, edge: number): House
	local yaw = door.yaw
	local lot = table.clone(box)
	if yaw == 0 then -- (its front looks north: its street's south edge north of it)
		lot.z0, lot.z1 = edge, box.z1 + BACK
	elseif yaw == 180 then
		lot.z0, lot.z1 = box.z0 - BACK, edge
	elseif yaw == 90 then
		lot.x0, lot.x1 = edge, box.x1 + BACK
	else
		lot.x0, lot.x1 = box.x0 - BACK, edge
	end
	return {
		id = id,
		name = name,
		street = street,
		number = number,
		kind = "house",
		look = look,
		box = box,
		lot = lot,
		house = { x = (box.x0 + box.x1) / 2, y = 0, z = (box.z0 + box.z1) / 2, sx = box.x1 - box.x0, sy = WALLS, sz = box.z1 - box.z0 },
		yaw = yaw,
		door = door,
		curb = curb,
	}
end

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
	-- Jinočany step 1: five family houses (plan.json `enter` 2 … 6; their names and numbers made up)
	family("Hlavní_n_5", "The Linden House", "Hlavní", 5, "old", { x0 = -464, x1 = -434, z0 = -110, z1 = -86 },
		{ x = -449, y = 0, z = -86, yaw = 180 }, { x = -449, y = TOP, z = -61, yaw = 180 }, -74),
	family("Hlavní_s_11", "The Blue Gate House", "Hlavní", 11, "old", { x0 = -694, x1 = -664, z0 = -34, z1 = -10 },
		{ x = -679, y = 0, z = -34, yaw = 0 }, { x = -679, y = TOP, z = -59, yaw = 0 }, -46),
	family("Školní_e_20", "The Schoolmaster's House", "Školní", 20, "old", { x0 = -536, x1 = -512, z0 = -264, z1 = -234 },
		{ x = -536, y = 0, z = -249, yaw = 90 }, { x = -561, y = TOP, z = -249, yaw = 90 }, -548),
	family("Lidická_e_30", "The Rose Garden House", "Lidická", 30, "old", { x0 = -356, x1 = -332, z0 = -308, z1 = -278 },
		{ x = -356, y = 0, z = -293, yaw = 90 }, { x = -381, y = TOP, z = -293, yaw = 90 }, -368),
	family("Smetanova_w_84", "The End Terrace", "Smetanova", 84, "row", { x0 = -496, x1 = -470, z0 = 160, z1 = 178 },
		{ x = -470, y = 0, z = 169, yaw = 270 }, { x = -447, y = TOP, z = 169, yaw = 270 }, -460),
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
