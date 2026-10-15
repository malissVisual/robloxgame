--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the owner's small test world in place of the city. One house to empty, a
-- road, four player plots, each with a ZDC warehouse (its display plots), a van spot at its roller door and a
-- Moving contracts board. Plain data (numbers only: the pure tests run it outside Roblox); the builders read it.
--
-- Coordinates: studs, y up, the ground's top at GroundTop, the asphalt's at RoadTop. A spot is { x, y, z, yaw }: yaw
-- in degrees about Y, the way its front looks: 0 looks north (-z), 90 west (-x), 180 south (+z), 270 east (+x);
-- in Roblox: CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0) (SandboxMap.cframe).
--
--   Bounds           the world's edge (the scenery fills it; nothing you play with is outside)
--   Roads            the asphalt rects: Pražská (north-south, the plots to the house; renamed by the Jinočany plan,
--                    design/jinocany/NAVRH.md: the streets keep their Czech names, diacritics and all) and Depot Row
--                    (the plots') first, always these two (Roads[1], Roads[2]); 8.9 then Jinočany's step-1 streets
--                    (Hlavní on from Depot Row west through the village to Hornická, Školní, Lidická and Na Pouštce
--                    north of it, Fibichova and Smetanova south to Mirešická, Mirešická east to Pražská); lane: a village
--                    lane (narrower; no centre line), else a main road
--   8.9 Jinočany, step 1 (design/jinocany/plan.json; tools/village/sandboxmap.py writes Bounds, Roads and these between
--   the BEGIN JINOCANY and END JINOCANY lines: change the plan, run it again):
--   Village          the village's houses (plan.json houses but the ones to empty: those are the moves' houses):
--                    id, street (one of Roads), kind (shared/VillageLooks.luau's "old" / "row" / "modern"), box, yaw
--                    (the way the door looks), door (outside it), curb (the van's pivot on the street)
--   Landmarks        the chapel green, the chapel, the Corner Drugstore, the Little Pond, the D5 (id, name, kind, rect)
--   Fields           the fields round the village (a crop's kind and its rect; none over another, a plot or a lot)
--   Lawns            the village's gardens and lawns (rects)
--   TreeLines        the windbreaks and fruit alleys (kind, points)
--   Orchard          the orchard's rect (its fruit trees in rows)
--   Turnaround       the circle at Pražská's south end, before the house
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
--   House            the one house to empty, its name and its street (The Old Farmstead on Pražská, the Jinočany
--                    plan's names), its lot, the house's box (its footprint's middle, its bottom, its size:
--                    the walls' box, the roof over it), its front door (outside, looking out: north to the road), curb
--                    (the van's pivot, nose north, back to the door). 8.1: the box is the owner's Blender house's
--                    (server/HouseMesh.luau dresses only a box of its size), its front wall where the chalet's always
--                    was (the door, the path and the curb unmoved). 8.2.1: the owner's big European house
--                    (design/blender-house/house.py TARGET "sandbox": 44 × 14.5 × 34, the chalet's old footprint).
--                    8.3 the big move: back, its back door (the model's, in the middle of its back wall; outside it,
--                    looking out: south), a second way in and out of a move (server/Moving.luau SB.site)
--   SandboxMap.plotAt(x, z)   the plot whose rect holds the point (nil: none)
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

-- 8.9 Jinočany: a street, a house of the village, a landmark, a field, a tree line (SandboxMap's village section)
export type Road = { name: string, x0: number, x1: number, z0: number, z1: number, lane: boolean }
export type VillageHouse = {
	id: string,
	street: string,
	kind: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	yaw: number,
	door: { x: number, z: number },
	curb: { x: number, z: number },
}
export type Landmark = { id: string, name: string, kind: string, x0: number, x1: number, z0: number, z1: number }
export type Field = { kind: string, x0: number, x1: number, z0: number, z1: number }
export type TreeLine = { kind: string, points: { { x: number, z: number } } }

SandboxMap.GroundTop = 0
SandboxMap.RoadTop = 0.4

-- BEGIN JINOCANY (tools/village/sandboxmap.py writes these lines from design/jinocany/plan.json: do not edit them)
SandboxMap.Bounds = { x0 = -1180, x1 = 420, z0 = -680, z1 = 760 } :: Rect
SandboxMap.Roads = {
	{ name = "Pražská", x0 = -14, x1 = 14, z0 = -74, z1 = 470, lane = false },
	{ name = "Depot Row", x0 = -270, x1 = 270, z0 = -74, z1 = -46, lane = false },
	{ name = "Hlavní", x0 = -1000, x1 = -270, z0 = -74, z1 = -46, lane = false },
	{ name = "Hornická", x0 = -1180, x1 = -1000, z0 = -74, z1 = -46, lane = false },
	{ name = "Školní", x0 = -572, x1 = -548, z0 = -470, z1 = -74, lane = true },
	{ name = "Lidická", x0 = -392, x1 = -368, z0 = -470, z1 = -74, lane = true },
	{ name = "Na Pouštce", x0 = -832, x1 = -808, z0 = -470, z1 = -74, lane = true },
	{ name = "Fibichova", x0 = -632, x1 = -608, z0 = -46, z1 = 300, lane = true },
	{ name = "Smetanova", x0 = -460, x1 = -436, z0 = -46, z1 = 300, lane = true },
	{ name = "Mirešická", x0 = -912, x1 = -14, z0 = 300, z1 = 324, lane = true },
} :: { Road }
SandboxMap.Village = {
	{ id = "Hlavní_n_1", street = "Hlavní", kind = "old", x0 = -970, x1 = -940, z0 = -110, z1 = -86, yaw = 180, door = { x = -955, z = -86 }, curb = { x = -955, z = -61 } },
	{ id = "Hlavní_n_2", street = "Hlavní", kind = "old", x0 = -924, x1 = -894, z0 = -110, z1 = -86, yaw = 180, door = { x = -909, z = -86 }, curb = { x = -909, z = -61 } },
	{ id = "Hlavní_n_3", street = "Hlavní", kind = "old", x0 = -878, x1 = -848, z0 = -110, z1 = -86, yaw = 180, door = { x = -863, z = -86 }, curb = { x = -863, z = -61 } },
	{ id = "Hlavní_n_4", street = "Hlavní", kind = "old", x0 = -510, x1 = -480, z0 = -110, z1 = -86, yaw = 180, door = { x = -495, z = -86 }, curb = { x = -495, z = -61 } },
	{ id = "Hlavní_s_6", street = "Hlavní", kind = "old", x0 = -970, x1 = -940, z0 = -34, z1 = -10, yaw = 0, door = { x = -955, z = -34 }, curb = { x = -955, z = -59 } },
	{ id = "Hlavní_s_7", street = "Hlavní", kind = "old", x0 = -878, x1 = -848, z0 = -34, z1 = -10, yaw = 0, door = { x = -863, z = -34 }, curb = { x = -863, z = -59 } },
	{ id = "Hlavní_s_8", street = "Hlavní", kind = "old", x0 = -832, x1 = -802, z0 = -34, z1 = -10, yaw = 0, door = { x = -817, z = -34 }, curb = { x = -817, z = -59 } },
	{ id = "Hlavní_s_9", street = "Hlavní", kind = "old", x0 = -786, x1 = -756, z0 = -34, z1 = -10, yaw = 0, door = { x = -771, z = -34 }, curb = { x = -771, z = -59 } },
	{ id = "Hlavní_s_10", street = "Hlavní", kind = "old", x0 = -740, x1 = -710, z0 = -34, z1 = -10, yaw = 0, door = { x = -725, z = -34 }, curb = { x = -725, z = -59 } },
	{ id = "Hlavní_s_12", street = "Hlavní", kind = "old", x0 = -602, x1 = -572, z0 = -34, z1 = -10, yaw = 0, door = { x = -587, z = -34 }, curb = { x = -587, z = -59 } },
	{ id = "Hlavní_s_13", street = "Hlavní", kind = "old", x0 = -556, x1 = -526, z0 = -34, z1 = -10, yaw = 0, door = { x = -541, z = -34 }, curb = { x = -541, z = -59 } },
	{ id = "Hlavní_s_14", street = "Hlavní", kind = "old", x0 = -510, x1 = -480, z0 = -34, z1 = -10, yaw = 0, door = { x = -495, z = -34 }, curb = { x = -495, z = -59 } },
	{ id = "Hlavní_s_15", street = "Hlavní", kind = "old", x0 = -418, x1 = -388, z0 = -34, z1 = -10, yaw = 0, door = { x = -403, z = -34 }, curb = { x = -403, z = -59 } },
	{ id = "Hlavní_s_16", street = "Hlavní", kind = "old", x0 = -372, x1 = -342, z0 = -34, z1 = -10, yaw = 0, door = { x = -357, z = -34 }, curb = { x = -357, z = -59 } },
	{ id = "Školní_w_17", street = "Školní", kind = "old", x0 = -608, x1 = -584, z0 = -308, z1 = -278, yaw = 270, door = { x = -584, z = -293 }, curb = { x = -559, z = -293 } },
	{ id = "Školní_w_18", street = "Školní", kind = "old", x0 = -608, x1 = -584, z0 = -264, z1 = -234, yaw = 270, door = { x = -584, z = -249 }, curb = { x = -559, z = -249 } },
	{ id = "Školní_e_19", street = "Školní", kind = "old", x0 = -536, x1 = -512, z0 = -440, z1 = -410, yaw = 90, door = { x = -536, z = -425 }, curb = { x = -561, z = -425 } },
	{ id = "Školní_e_21", street = "Školní", kind = "old", x0 = -536, x1 = -512, z0 = -220, z1 = -190, yaw = 90, door = { x = -536, z = -205 }, curb = { x = -561, z = -205 } },
	{ id = "Školní_e_22", street = "Školní", kind = "old", x0 = -536, x1 = -512, z0 = -176, z1 = -146, yaw = 90, door = { x = -536, z = -161 }, curb = { x = -561, z = -161 } },
	{ id = "Lidická_w_23", street = "Lidická", kind = "old", x0 = -428, x1 = -404, z0 = -440, z1 = -410, yaw = 270, door = { x = -404, z = -425 }, curb = { x = -379, z = -425 } },
	{ id = "Lidická_w_24", street = "Lidická", kind = "old", x0 = -428, x1 = -404, z0 = -264, z1 = -234, yaw = 270, door = { x = -404, z = -249 }, curb = { x = -379, z = -249 } },
	{ id = "Lidická_w_25", street = "Lidická", kind = "old", x0 = -428, x1 = -404, z0 = -220, z1 = -190, yaw = 270, door = { x = -404, z = -205 }, curb = { x = -379, z = -205 } },
	{ id = "Lidická_w_26", street = "Lidická", kind = "old", x0 = -428, x1 = -404, z0 = -176, z1 = -146, yaw = 270, door = { x = -404, z = -161 }, curb = { x = -379, z = -161 } },
	{ id = "Lidická_e_27", street = "Lidická", kind = "old", x0 = -356, x1 = -332, z0 = -440, z1 = -410, yaw = 90, door = { x = -356, z = -425 }, curb = { x = -381, z = -425 } },
	{ id = "Lidická_e_28", street = "Lidická", kind = "old", x0 = -356, x1 = -332, z0 = -396, z1 = -366, yaw = 90, door = { x = -356, z = -381 }, curb = { x = -381, z = -381 } },
	{ id = "Lidická_e_29", street = "Lidická", kind = "old", x0 = -356, x1 = -332, z0 = -352, z1 = -322, yaw = 90, door = { x = -356, z = -337 }, curb = { x = -381, z = -337 } },
	{ id = "Lidická_e_31", street = "Lidická", kind = "old", x0 = -356, x1 = -332, z0 = -264, z1 = -234, yaw = 90, door = { x = -356, z = -249 }, curb = { x = -381, z = -249 } },
	{ id = "Lidická_e_32", street = "Lidická", kind = "old", x0 = -356, x1 = -332, z0 = -220, z1 = -190, yaw = 90, door = { x = -356, z = -205 }, curb = { x = -381, z = -205 } },
	{ id = "Lidická_e_33", street = "Lidická", kind = "old", x0 = -356, x1 = -332, z0 = -176, z1 = -146, yaw = 90, door = { x = -356, z = -161 }, curb = { x = -381, z = -161 } },
	{ id = "Na Pouštce_w_34", street = "Na Pouštce", kind = "old", x0 = -868, x1 = -844, z0 = -440, z1 = -410, yaw = 270, door = { x = -844, z = -425 }, curb = { x = -819, z = -425 } },
	{ id = "Na Pouštce_w_35", street = "Na Pouštce", kind = "old", x0 = -868, x1 = -844, z0 = -396, z1 = -366, yaw = 270, door = { x = -844, z = -381 }, curb = { x = -819, z = -381 } },
	{ id = "Na Pouštce_w_36", street = "Na Pouštce", kind = "old", x0 = -868, x1 = -844, z0 = -352, z1 = -322, yaw = 270, door = { x = -844, z = -337 }, curb = { x = -819, z = -337 } },
	{ id = "Na Pouštce_w_37", street = "Na Pouštce", kind = "old", x0 = -868, x1 = -844, z0 = -308, z1 = -278, yaw = 270, door = { x = -844, z = -293 }, curb = { x = -819, z = -293 } },
	{ id = "Na Pouštce_w_38", street = "Na Pouštce", kind = "old", x0 = -868, x1 = -844, z0 = -264, z1 = -234, yaw = 270, door = { x = -844, z = -249 }, curb = { x = -819, z = -249 } },
	{ id = "Na Pouštce_w_39", street = "Na Pouštce", kind = "old", x0 = -868, x1 = -844, z0 = -220, z1 = -190, yaw = 270, door = { x = -844, z = -205 }, curb = { x = -819, z = -205 } },
	{ id = "Na Pouštce_w_40", street = "Na Pouštce", kind = "old", x0 = -868, x1 = -844, z0 = -176, z1 = -146, yaw = 270, door = { x = -844, z = -161 }, curb = { x = -819, z = -161 } },
	{ id = "Na Pouštce_e_41", street = "Na Pouštce", kind = "old", x0 = -796, x1 = -772, z0 = -308, z1 = -278, yaw = 90, door = { x = -796, z = -293 }, curb = { x = -821, z = -293 } },
	{ id = "Na Pouštce_e_42", street = "Na Pouštce", kind = "old", x0 = -796, x1 = -772, z0 = -264, z1 = -234, yaw = 90, door = { x = -796, z = -249 }, curb = { x = -821, z = -249 } },
	{ id = "Fibichova_w_53", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 2, z1 = 20, yaw = 270, door = { x = -642, z = 11 }, curb = { x = -619, z = 11 } },
	{ id = "Fibichova_w_54", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 20, z1 = 38, yaw = 270, door = { x = -642, z = 29 }, curb = { x = -619, z = 29 } },
	{ id = "Fibichova_w_55", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 38, z1 = 56, yaw = 270, door = { x = -642, z = 47 }, curb = { x = -619, z = 47 } },
	{ id = "Fibichova_w_56", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 72, z1 = 90, yaw = 270, door = { x = -642, z = 81 }, curb = { x = -619, z = 81 } },
	{ id = "Fibichova_w_57", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 90, z1 = 108, yaw = 270, door = { x = -642, z = 99 }, curb = { x = -619, z = 99 } },
	{ id = "Fibichova_w_58", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 108, z1 = 126, yaw = 270, door = { x = -642, z = 117 }, curb = { x = -619, z = 117 } },
	{ id = "Fibichova_w_59", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 126, z1 = 144, yaw = 270, door = { x = -642, z = 135 }, curb = { x = -619, z = 135 } },
	{ id = "Fibichova_w_60", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 160, z1 = 178, yaw = 270, door = { x = -642, z = 169 }, curb = { x = -619, z = 169 } },
	{ id = "Fibichova_w_61", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 178, z1 = 196, yaw = 270, door = { x = -642, z = 187 }, curb = { x = -619, z = 187 } },
	{ id = "Fibichova_w_62", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 196, z1 = 214, yaw = 270, door = { x = -642, z = 205 }, curb = { x = -619, z = 205 } },
	{ id = "Fibichova_w_63", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 214, z1 = 232, yaw = 270, door = { x = -642, z = 223 }, curb = { x = -619, z = 223 } },
	{ id = "Fibichova_w_64", street = "Fibichova", kind = "row", x0 = -668, x1 = -642, z0 = 248, z1 = 266, yaw = 270, door = { x = -642, z = 257 }, curb = { x = -619, z = 257 } },
	{ id = "Fibichova_e_65", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 2, z1 = 20, yaw = 90, door = { x = -598, z = 11 }, curb = { x = -621, z = 11 } },
	{ id = "Fibichova_e_66", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 20, z1 = 38, yaw = 90, door = { x = -598, z = 29 }, curb = { x = -621, z = 29 } },
	{ id = "Fibichova_e_67", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 38, z1 = 56, yaw = 90, door = { x = -598, z = 47 }, curb = { x = -621, z = 47 } },
	{ id = "Fibichova_e_68", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 72, z1 = 90, yaw = 90, door = { x = -598, z = 81 }, curb = { x = -621, z = 81 } },
	{ id = "Fibichova_e_69", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 90, z1 = 108, yaw = 90, door = { x = -598, z = 99 }, curb = { x = -621, z = 99 } },
	{ id = "Fibichova_e_70", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 108, z1 = 126, yaw = 90, door = { x = -598, z = 117 }, curb = { x = -621, z = 117 } },
	{ id = "Fibichova_e_71", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 126, z1 = 144, yaw = 90, door = { x = -598, z = 135 }, curb = { x = -621, z = 135 } },
	{ id = "Fibichova_e_72", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 160, z1 = 178, yaw = 90, door = { x = -598, z = 169 }, curb = { x = -621, z = 169 } },
	{ id = "Fibichova_e_73", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 178, z1 = 196, yaw = 90, door = { x = -598, z = 187 }, curb = { x = -621, z = 187 } },
	{ id = "Fibichova_e_74", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 196, z1 = 214, yaw = 90, door = { x = -598, z = 205 }, curb = { x = -621, z = 205 } },
	{ id = "Fibichova_e_75", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 214, z1 = 232, yaw = 90, door = { x = -598, z = 223 }, curb = { x = -621, z = 223 } },
	{ id = "Fibichova_e_76", street = "Fibichova", kind = "row", x0 = -598, x1 = -572, z0 = 248, z1 = 266, yaw = 90, door = { x = -598, z = 257 }, curb = { x = -621, z = 257 } },
	{ id = "Smetanova_w_77", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 2, z1 = 20, yaw = 270, door = { x = -470, z = 11 }, curb = { x = -447, z = 11 } },
	{ id = "Smetanova_w_78", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 20, z1 = 38, yaw = 270, door = { x = -470, z = 29 }, curb = { x = -447, z = 29 } },
	{ id = "Smetanova_w_79", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 38, z1 = 56, yaw = 270, door = { x = -470, z = 47 }, curb = { x = -447, z = 47 } },
	{ id = "Smetanova_w_80", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 72, z1 = 90, yaw = 270, door = { x = -470, z = 81 }, curb = { x = -447, z = 81 } },
	{ id = "Smetanova_w_81", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 90, z1 = 108, yaw = 270, door = { x = -470, z = 99 }, curb = { x = -447, z = 99 } },
	{ id = "Smetanova_w_82", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 108, z1 = 126, yaw = 270, door = { x = -470, z = 117 }, curb = { x = -447, z = 117 } },
	{ id = "Smetanova_w_83", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 126, z1 = 144, yaw = 270, door = { x = -470, z = 135 }, curb = { x = -447, z = 135 } },
	{ id = "Smetanova_w_85", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 178, z1 = 196, yaw = 270, door = { x = -470, z = 187 }, curb = { x = -447, z = 187 } },
	{ id = "Smetanova_w_86", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 196, z1 = 214, yaw = 270, door = { x = -470, z = 205 }, curb = { x = -447, z = 205 } },
	{ id = "Smetanova_w_87", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 214, z1 = 232, yaw = 270, door = { x = -470, z = 223 }, curb = { x = -447, z = 223 } },
	{ id = "Smetanova_w_88", street = "Smetanova", kind = "row", x0 = -496, x1 = -470, z0 = 248, z1 = 266, yaw = 270, door = { x = -470, z = 257 }, curb = { x = -447, z = 257 } },
	{ id = "Mirešická_n_89", street = "Mirešická", kind = "old", x0 = -882, x1 = -852, z0 = 264, z1 = 288, yaw = 180, door = { x = -867, z = 288 }, curb = { x = -867, z = 313 } },
	{ id = "Mirešická_n_90", street = "Mirešická", kind = "old", x0 = -836, x1 = -806, z0 = 264, z1 = 288, yaw = 180, door = { x = -821, z = 288 }, curb = { x = -821, z = 313 } },
	{ id = "Mirešická_n_91", street = "Mirešická", kind = "old", x0 = -790, x1 = -760, z0 = 264, z1 = 288, yaw = 180, door = { x = -775, z = 288 }, curb = { x = -775, z = 313 } },
	{ id = "Mirešická_n_92", street = "Mirešická", kind = "old", x0 = -744, x1 = -714, z0 = 264, z1 = 288, yaw = 180, door = { x = -729, z = 288 }, curb = { x = -729, z = 313 } },
	{ id = "Mirešická_n_93", street = "Mirešická", kind = "old", x0 = -560, x1 = -530, z0 = 264, z1 = 288, yaw = 180, door = { x = -545, z = 288 }, curb = { x = -545, z = 313 } },
	{ id = "Mirešická_n_94", street = "Mirešická", kind = "old", x0 = -422, x1 = -392, z0 = 264, z1 = 288, yaw = 180, door = { x = -407, z = 288 }, curb = { x = -407, z = 313 } },
	{ id = "Mirešická_n_95", street = "Mirešická", kind = "old", x0 = -376, x1 = -346, z0 = 264, z1 = 288, yaw = 180, door = { x = -361, z = 288 }, curb = { x = -361, z = 313 } },
	{ id = "Mirešická_n_96", street = "Mirešická", kind = "old", x0 = -330, x1 = -300, z0 = 264, z1 = 288, yaw = 180, door = { x = -315, z = 288 }, curb = { x = -315, z = 313 } },
} :: { VillageHouse }
SandboxMap.Landmarks = {
	{ id = "green", name = "The Chapel Green", kind = "green", x0 = -800, x1 = -584, z0 = -190, z1 = -80 },
	{ id = "chapel", name = "Chapel", kind = "chapel", x0 = -712, x1 = -688, z0 = -164, z1 = -124 },
	{ id = "drugstore", name = "Corner Drugstore", kind = "shop", x0 = 56, x1 = 120, z0 = -20, z1 = 40 },
	{ id = "pond", name = "Little Pond", kind = "pond", x0 = 50, x1 = 210, z0 = 145, z1 = 255 },
	{ id = "d5", name = "D5 Motorway", kind = "motorway", x0 = 330, x1 = 390, z0 = -680, z1 = 760 },
} :: { Landmark }
SandboxMap.Fields = {
	{ kind = "wheat", x0 = -1180, x1 = 420, z0 = -680, z1 = -505 },
	{ kind = "rapeseed", x0 = -1180, x1 = -1030, z0 = -505, z1 = 340 },
	{ kind = "rapeseed", x0 = -1180, x1 = -620, z0 = 340, z1 = 680 },
	{ kind = "ploughed", x0 = -620, x1 = -60, z0 = 340, z1 = 680 },
	{ kind = "wheat", x0 = -40, x1 = 330, z0 = 620, z1 = 680 },
	{ kind = "young", x0 = -280, x1 = 330, z0 = -505, z1 = -250 },
	{ kind = "young", x0 = 230, x1 = 330, z0 = 60, z1 = 620 },
	{ kind = "young", x0 = -1180, x1 = 420, z0 = 710, z1 = 760 },
} :: { Field }
SandboxMap.Lawns = { { x0 = -1030, x1 = -280, z0 = -505, z1 = 330 } } :: { Rect }
SandboxMap.TreeLines = {
	{ kind = "windbreak", points = { { x = -1180, z = 340 }, { x = -40, z = 340 } } },
	{ kind = "windbreak", points = { { x = -1040, z = -500 }, { x = -1040, z = 330 } } },
	{ kind = "alley", points = { { x = -1180, z = -96 }, { x = -1030, z = -96 } } },
	{ kind = "alley", points = { { x = -1180, z = -24 }, { x = -1030, z = -24 } } },
	{ kind = "alley", points = { { x = -36, z = 330 }, { x = -36, z = 460 } } },
	{ kind = "alley", points = { { x = 36, z = 300 }, { x = 36, z = 460 } } },
	{ kind = "windbreak", points = { { x = -280, z = -505 }, { x = 300, z = -505 } } },
	{ kind = "windbreak", points = { { x = 300, z = -505 }, { x = 300, z = 660 } } },
} :: { TreeLine }
SandboxMap.Orchard = { x0 = -400, x1 = -70, z0 = 20, z1 = 260 } :: Rect
-- END JINOCANY

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

SandboxMap.House = {
	id = "sandbox_house",
	name = "The Old Farmstead",
	street = "Pražská", -- (the road it stands on, one of SandboxMap.Roads: the contract's address, the guide's words)
	lot = { x0 = -60, x1 = 60, z0 = 504, z1 = 600 } :: Rect,
	-- (the front wall at the door, z 523; the house's box back from it: tools/house-art/check.py, house.py's TARGETS
	-- "sandbox" box; sy the walls' height, the roof over it up to 26)
	house = { x = 0, y = 0, z = 523 + 34 / 2, sx = 44, sy = 14.5, sz = 34 },
	door = { x = 0, y = 0, z = 523, yaw = 0 } :: Spot, -- outside the front door, looking north to the road
	curb = { x = 0, y = SandboxMap.RoadTop, z = 492, yaw = 0 } :: Spot, -- the van's pivot: nose north, back to the door
	back = { x = 0, y = 0, z = 523 + 34, yaw = 180 } :: Spot, -- 8.3: outside the back door, looking south into the garden
}

function SandboxMap.plotAt(x: number, z: number): Plot?
	for _, plot in plots do
		local r = plot.rect
		if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
			return plot
		end
	end
	return nil
end

function SandboxMap.cframe(spot: Spot): any
	return (CFrame :: any).new(spot.x, spot.y, spot.z) * (CFrame :: any).Angles(0, math.rad(spot.yaw), 0)
end

return SandboxMap
