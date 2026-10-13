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
--   Roads            the asphalt rects: Main Street (north-south, the plots to the house) and Depot Row (the plots')
--   Turnaround       the circle at Main Street's south end, before the house
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
--   House            the one house to empty: its lot, the house's middle and size, its front door (outside, looking
--                    out: north to the road), curb (the van's pivot, nose north, back to the door)
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

SandboxMap.GroundTop = 0
SandboxMap.RoadTop = 0.4
SandboxMap.Bounds = { x0 = -340, x1 = 340, z0 = -280, z1 = 640 } :: Rect

SandboxMap.Roads = {
	{ name = "Main Street", x0 = -14, x1 = 14, z0 = -74, z1 = 470 },
	{ name = "Depot Row", x0 = -270, x1 = 270, z0 = -74, z1 = -46 },
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
		vanSpot = { x = x, y = SandboxMap.RoadTop, z = WALL_Z + 6 + 10, yaw = 180 }, -- (the van ~20 long: its back 6 off the wall)
		unload = { x = x, z = WALL_Z + 8, r = 16 },
		spawn = { x = x + 22, y = 3, z = WALL_Z + 18, yaw = 180 },
		board = { x = x - 24, y = 0, z = WALL_Z + 1, yaw = 180 },
	}
end
SandboxMap.Plots = plots

SandboxMap.House = {
	id = "sandbox_house",
	name = "The Old Chalet",
	lot = { x0 = -60, x1 = 60, z0 = 504, z1 = 600 } :: Rect,
	house = { x = 0, y = 0, z = 540, sx = 44, sy = 26, sz = 34 },
	door = { x = 0, y = 0, z = 523, yaw = 0 } :: Spot, -- outside the front door, looking north to the road
	curb = { x = 0, y = SandboxMap.RoadTop, z = 492, yaw = 0 } :: Spot, -- the van's pivot: nose north, back to the door
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
