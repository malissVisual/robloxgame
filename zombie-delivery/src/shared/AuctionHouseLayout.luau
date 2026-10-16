--!strict
-- 8.8 SANDBOX, the Auction House (design/auction/PLAN.md): the building as plain numbers. Pure (no Roblox at its top
-- level; tests/auctionhouse_test.luau); server/SandboxWorld.luau builds it from these parts, only while
-- Config.Auction.On (8.8 is the groundwork: the round itself comes with the server's step). Its numbers are
-- Config.Auction.House's; its place is House.Spot alone (the middle of its front wall on the ground, looking out), so it
-- moves with one line (it stands on Depot Row east of the crossroads, across from plots 3 and 4; 9.4 the countryside's
-- plan, design/countryside/plan.py, keeps its site clear).
--
-- A small Central European town hall of auctions, not alpine: a cream rendered hall on a granite plinth, white
-- pilasters and cornice, a red tile gable roof with its ridge along the front, tall white-framed windows, a doorway with
-- a burgundy canopy and the AUCTION HOUSE sign over it. Inside: a carpet down the aisle, three rows of benches either
-- side of it (standing room behind them and at the door), the stage at the back with the lot's pedestal, the lectern and
-- the lot display over it between two curtains, the consignment desk by the door on the right, two hanging lamps.
--
-- Frame: the spot's (SandboxMap's yaw: 0 looks north); u across (+ the right when you look out of the door), v into the
-- hall (0 the front wall's outer face, Depth the back wall's), y up from the ground.
--   AuctionHouseLayout.spot()                Config.Auction.House.Spot
--   AuctionHouseLayout.toWorld(u, v)         x, z on the map
--   AuctionHouseLayout.Floor                 the hall's floor top (studs over the ground)
--   AuctionHouseLayout.footprint()           { u0, u1, v0, v1 }: all of it (the roof's overhang, the canopy, the steps)
--   AuctionHouseLayout.corners()             the footprint's four corners on the map ({ x, z }, turned with the spot)
--   AuctionHouseLayout.site()                the map's rect round them (x0, x1, z0, z1)
--   AuctionHouseLayout.covers(x, z, grow?)   is the point within the footprint (grown by `grow` studs)?
--   AuctionHouseLayout.parts()               { Part } the building (the same list while the spot and sizes stay)
--   AuctionHouseLayout.door()                a Spot outside the doorway, looking out
--   AuctionHouseLayout.aisle()               { u0, u1, v0, v1 }: the walk from the steps to the stage (nothing solid in it)
--   AuctionHouseLayout.desk()                the consignment desk's front (where you stand at it): { x, z, yaw }
-- A Part's `tag` is a role the builder dresses: "sign" (the facade's SurfaceGui: SignLabels), "screen" (the lot
-- display's: ScreenLabels), "notice" (the desk's board), "desk" (the consignment desk's prompt), "stand" (the lot's
-- pedestal: where the server's step shows the piece), "lamp" (a PointLight, Config.Auction.House.Lamp).

local Config = require(script.Parent.Config)

local AuctionHouseLayout = {}

export type Part = {
	name: string,
	shape: string, -- "block" | "wedge" (a WedgePart: its high side at its +Z)
	x: number, -- its middle on the map
	y: number,
	z: number,
	sx: number, -- its size along its own axes
	sy: number,
	sz: number,
	yaw: number, -- degrees about Y (the spot's and its own)
	color: { number },
	material: string, -- an Enum.Material's name
	solid: boolean, -- collides; false: decoration (no collision, no ray)
	alpha: number?, -- its transparency (nil: 0)
	tag: string?,
}
export type Box = { u0: number, u1: number, v0: number, v1: number }

AuctionHouseLayout.Plinth = 0.5 -- the granite plinth's top (the walls stand on it)
AuctionHouseLayout.Floor = 0.7 -- the hall's wooden floor's top
AuctionHouseLayout.Thick = 1 -- the walls
AuctionHouseLayout.Over = 2 -- the roof's overhang all round
AuctionHouseLayout.Porch = 4 -- the canopy over the door, out from the front wall
-- the labels the builder puts on the sign and the lot display, and the client paints (client/AuctionUi.luau)
AuctionHouseLayout.SignLabels = { "Title", "Next" }
AuctionHouseLayout.ScreenLabels = { "Title", "Piece", "Facts", "Price", "Leader", "Clock" }

AuctionHouseLayout.Colors = {
	Render = { 236, 224, 196 }, -- the walls
	Trim = { 244, 241, 233 }, -- the pilasters, the cornice, the window frames
	Granite = { 150, 148, 142 },
	Roof = { 164, 66, 48 }, -- red clay tiles
	Ridge = { 122, 50, 38 },
	Burgundy = { 112, 36, 44 }, -- the canopy, the sign, the curtains
	Glass = { 92, 116, 138 },
	Wood = { 92, 60, 40 }, -- the stage, the lectern, the benches, the desk
	Planks = { 150, 106, 68 }, -- the floor
	Door = { 70, 50, 38 },
	Carpet = { 150, 36, 44 },
	Velvet = { 120, 28, 40 },
	Gold = { 214, 172, 74 },
	Marble = { 232, 228, 220 },
	Screen = { 30, 46, 40 }, -- the lot display's dark green board
	Lamp = { 255, 226, 180 },
} :: { [string]: { number } }

local function tune()
	return Config.Auction.House
end

function AuctionHouseLayout.spot(): Config.AuctionSpot
	return tune().Spot
end

function AuctionHouseLayout.toWorld(u: number, v: number): (number, number)
	local s = tune().Spot
	local a = math.rad(s.yaw)
	return s.x + u * math.cos(a) + v * math.sin(a), s.z - u * math.sin(a) + v * math.cos(a)
end

function AuctionHouseLayout.footprint(): Box
	local H = tune()
	local over = AuctionHouseLayout.Over
	return { u0 = -H.Width / 2 - over, u1 = H.Width / 2 + over, v0 = -AuctionHouseLayout.Porch, v1 = H.Depth + over }
end

function AuctionHouseLayout.corners(): { { x: number, z: number } }
	local f = AuctionHouseLayout.footprint()
	local out = {}
	for _, c in { { f.u0, f.v0 }, { f.u1, f.v0 }, { f.u1, f.v1 }, { f.u0, f.v1 } } do
		local x, z = AuctionHouseLayout.toWorld(c[1], c[2])
		table.insert(out, { x = x, z = z })
	end
	return out
end

function AuctionHouseLayout.site(): { x0: number, x1: number, z0: number, z1: number }
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, c in AuctionHouseLayout.corners() do
		x0, x1 = math.min(x0, c.x), math.max(x1, c.x)
		z0, z1 = math.min(z0, c.z), math.max(z1, c.z)
	end
	return { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
end

-- The point in the spot's frame (u, v).
local function toLocal(x: number, z: number): (number, number)
	local s = tune().Spot
	local a = math.rad(s.yaw)
	local dx, dz = x - s.x, z - s.z
	return dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
end

function AuctionHouseLayout.covers(x: number, z: number, grow: number?): boolean
	local g = grow or 0
	local f = AuctionHouseLayout.footprint()
	local u, v = toLocal(x, z)
	return u >= f.u0 - g and u <= f.u1 + g and v >= f.v0 - g and v <= f.v1 + g
end

function AuctionHouseLayout.door(): Config.AuctionSpot
	local x, z = AuctionHouseLayout.toWorld(0, -AuctionHouseLayout.Porch)
	return { x = x, y = 0, z = z, yaw = tune().Spot.yaw }
end

function AuctionHouseLayout.aisle(): Box
	local half = tune().Door[1] / 2 - 0.5
	return { u0 = -half, u1 = half, v0 = -3, v1 = tune().Depth - AuctionHouseLayout.Thick - 8.6 } -- (to the stage's step)
end

function AuctionHouseLayout.desk(): Config.AuctionSpot
	local x, z = AuctionHouseLayout.toWorld(tune().Width / 2 - 8.5, 4.75)
	return { x = x, y = AuctionHouseLayout.Floor, z = z, yaw = (tune().Spot.yaw + 270) % 360 } -- (looking at the desk: east in the hall)
end

-- ── The parts ───────────────────────────────────────────────────────────────

local cache: { Part }? = nil
local cachedFor = "" -- (the spot and the sizes the cache was made for: a spot moved or turned makes them again)

function AuctionHouseLayout.parts(): { Part }
	local H = tune()
	local key = `{H.Spot.x},{H.Spot.z},{H.Spot.yaw},{H.Width},{H.Depth},{H.Wall},{H.Roof},{H.Door[1]},{H.Door[2]}`
	if cache and key == cachedFor then
		return cache
	end
	local C = AuctionHouseLayout.Colors
	local W, D, WALL, RISE = H.Width, H.Depth, H.Wall, H.Roof
	local DW, DH = H.Door[1], H.Door[2]
	local T, PT, FT, OVER = AuctionHouseLayout.Thick, AuctionHouseLayout.Plinth, AuctionHouseLayout.Floor, AuctionHouseLayout.Over
	local list: { Part } = {}
	local yaw0 = H.Spot.yaw
	-- one part at (u, y, v) in the spot's frame, turned `turn` degrees more
	local function add(name: string, shape: string, u: number, y: number, v: number, su: number, sy: number, sv: number, color: { number }, material: string, solid: boolean, turn: number?, tag: string?, alpha: number?)
		local x, z = AuctionHouseLayout.toWorld(u, v)
		table.insert(list, {
			name = name,
			shape = shape,
			x = x,
			y = y,
			z = z,
			sx = su,
			sy = sy,
			sz = sv,
			yaw = (yaw0 + (turn or 0)) % 360,
			color = color,
			material = material,
			solid = solid,
			alpha = alpha,
			tag = tag,
		})
	end
	local wallY = PT + WALL / 2
	-- the plinth and the floor
	add("AuctionPlinth", "block", 0, PT - 0.45, D / 2, W + 1, 0.9, D + 1, C.Granite, "Granite", true)
	add("AuctionFloor", "block", 0, FT - 0.1, D / 2, W - 2 * T, 0.2, D - 2 * T, C.Planks, "WoodPlanks", true)
	add("AuctionStep", "block", 0, 0.125, -1.5, DW + 4, 0.25, 3, C.Granite, "Granite", true)
	-- the walls (the front one round the doorway)
	local side = W / 2 - T - DW / 2
	add("AuctionWall", "block", -(W / 2 - T / 2), wallY, D / 2, T, WALL, D, C.Render, "Plaster", true)
	add("AuctionWall", "block", W / 2 - T / 2, wallY, D / 2, T, WALL, D, C.Render, "Plaster", true)
	add("AuctionWall", "block", 0, wallY, D - T / 2, W - 2 * T, WALL, T, C.Render, "Plaster", true)
	add("AuctionWall", "block", -(DW / 2 + side / 2), wallY, T / 2, side, WALL, T, C.Render, "Plaster", true)
	add("AuctionWall", "block", DW / 2 + side / 2, wallY, T / 2, side, WALL, T, C.Render, "Plaster", true)
	add("AuctionWall", "block", 0, PT + DH + (WALL - DH) / 2, T / 2, DW, WALL - DH, T, C.Render, "Plaster", true)
	-- the pilasters at the corners, the cornice round the top
	for _, c in { { -1, 0.6 }, { 1, 0.6 }, { -1, D - 0.6 }, { 1, D - 0.6 } } do
		add("AuctionPilaster", "block", c[1] * (W / 2 - 0.6), wallY, c[2], 1.6, WALL, 1.6, C.Trim, "SmoothPlastic", false)
	end
	local cornice = PT + WALL - 0.4
	add("AuctionCornice", "block", 0, cornice, 0, W + 0.8, 0.8, 0.8, C.Trim, "SmoothPlastic", false)
	add("AuctionCornice", "block", 0, cornice, D, W + 0.8, 0.8, 0.8, C.Trim, "SmoothPlastic", false)
	add("AuctionCornice", "block", -W / 2, cornice, D / 2, 0.8, 0.8, D - 0.8, C.Trim, "SmoothPlastic", false)
	add("AuctionCornice", "block", W / 2, cornice, D / 2, 0.8, 0.8, D - 0.8, C.Trim, "SmoothPlastic", false)
	-- the roof: two slopes up to a ridge along the front (each a wedge, its high side at the ridge), the gables under it
	local base = PT + WALL
	local slope = D / 2 + OVER
	add("AuctionRoof", "wedge", 0, base + RISE / 2, -OVER + slope / 2, W + 2 * OVER, RISE, slope, C.Roof, "ClayRoofTiles", true)
	add("AuctionRoof", "wedge", 0, base + RISE / 2, D + OVER - slope / 2, W + 2 * OVER, RISE, slope, C.Roof, "ClayRoofTiles", true, 180)
	add("AuctionRidge", "block", 0, base + RISE + 0.1, D / 2, W + 2 * OVER, 0.6, 1.2, C.Ridge, "ClayRoofTiles", false)
	local gable = RISE * (D / 2) / slope
	for _, s in { -1, 1 } do
		add("AuctionGable", "wedge", s * (W / 2 - T / 2), base + gable / 2, D / 4, T, gable, D / 2, C.Render, "Plaster", false)
		add("AuctionGable", "wedge", s * (W / 2 - T / 2), base + gable / 2, 3 * D / 4, T, gable, D / 2, C.Render, "Plaster", false, 180)
	end
	-- the doorway: its white frame, the two leaves swung open against the wall inside, the canopy and the sign over it
	add("AuctionDoorFrame", "block", -(DW / 2 + 0.4), PT + (DH + 0.4) / 2, T / 2, 0.8, DH + 0.4, T + 0.6, C.Trim, "SmoothPlastic", false)
	add("AuctionDoorFrame", "block", DW / 2 + 0.4, PT + (DH + 0.4) / 2, T / 2, 0.8, DH + 0.4, T + 0.6, C.Trim, "SmoothPlastic", false)
	add("AuctionDoorFrame", "block", 0, PT + DH + 0.4, T / 2, DW + 1.6, 0.8, T + 0.6, C.Trim, "SmoothPlastic", false)
	add("AuctionDoorLeaf", "block", -(DW / 2 + DW / 4), PT + DH / 2, T + 0.15, DW / 2, DH - 0.2, 0.3, C.Door, "Wood", false)
	add("AuctionDoorLeaf", "block", DW / 2 + DW / 4, PT + DH / 2, T + 0.15, DW / 2, DH - 0.2, 0.3, C.Door, "Wood", false)
	add("AuctionCanopy", "block", 0, PT + DH + 1.05, -AuctionHouseLayout.Porch / 2, DW + 4, 0.5, AuctionHouseLayout.Porch, C.Burgundy, "Fabric", false)
	add("AuctionSign", "block", 0, PT + DH + 3.4, -0.25, DW + 12, 3.2, 0.4, C.Burgundy, "SmoothPlastic", false, nil, "sign")
	-- the windows: a white frame on the outside, the glass through the wall (the front two a side and one over, three in
	-- each side wall)
	local function window(u: number, y: number, tall: number)
		add("AuctionWindowFrame", "block", u, y, -0.15, 5, tall + 1, 0.3, C.Trim, "SmoothPlastic", false)
		add("AuctionWindow", "block", u, y, T / 2, 4, tall, T + 0.2, C.Glass, "Glass", false, nil, nil, 0.3)
	end
	for _, s in { -1, 1 } do
		window(s * 10.5, PT + 6, 6)
		window(s * 17.5, PT + 6, 6)
		window(s * 17.5, PT + 13, 3)
		for _, v in { 8, 16, 24 } do
			add("AuctionWindowFrame", "block", s * (W / 2 + 0.15), PT + 6, v, 0.3, 7, 5, C.Trim, "SmoothPlastic", false)
			add("AuctionWindow", "block", s * (W / 2 - T / 2), PT + 6, v, T + 0.2, 6, 4, C.Glass, "Glass", false, nil, nil, 0.3)
		end
	end
	-- the stage at the back: its gold edge, a step up, the lectern, the lot's pedestal, the lot display between curtains
	local stageFront = D - T - 7
	add("AuctionStage", "block", 0, FT + 1, stageFront + 3.5, 24, 2, 7, C.Wood, "Wood", true)
	add("AuctionStageEdge", "block", 0, FT + 1.85, stageFront - 0.1, 24.2, 0.3, 0.2, C.Gold, "Metal", false)
	add("AuctionStageStep", "block", 0, FT + 0.5, stageFront - 0.75, 8, 1, 1.5, C.Wood, "Wood", true)
	add("AuctionLectern", "block", 7.5, FT + 2 + 1.9, stageFront + 3, 2.4, 3.8, 1.6, C.Wood, "Wood", true)
	add("AuctionLotStand", "block", 0, FT + 2 + 1.2, stageFront + 3.5, 3.2, 2.4, 3.2, C.Velvet, "Fabric", true, nil, "stand")
	add("AuctionLotPlate", "block", 0, FT + 2 + 2.5, stageFront + 3.5, 3.4, 0.2, 3.4, C.Gold, "Metal", false)
	local screenY = PT + 11.5
	add("AuctionScreen", "block", 0, screenY, D - T - 0.2, 20, 9, 0.4, C.Screen, "SmoothPlastic", false, nil, "screen")
	add("AuctionScreenFrame", "block", 0, screenY + 4.7, D - T - 0.3, 20.8, 0.4, 0.5, C.Wood, "Wood", false)
	add("AuctionScreenFrame", "block", 0, screenY - 4.7, D - T - 0.3, 20.8, 0.4, 0.5, C.Wood, "Wood", false)
	add("AuctionScreenFrame", "block", -10.2, screenY, D - T - 0.3, 0.4, 9.8, 0.5, C.Wood, "Wood", false)
	add("AuctionScreenFrame", "block", 10.2, screenY, D - T - 0.3, 0.4, 9.8, 0.5, C.Wood, "Wood", false)
	for _, s in { -1, 1 } do
		add("AuctionCurtain", "block", s * 12.5, FT + 2 + 6.75, D - T - 0.4, 3, 13.5, 0.5, C.Burgundy, "Fabric", false)
	end
	-- the carpet down the aisle and the benches either side of it, facing the stage (their backs to the door)
	add("AuctionCarpet", "block", 0, FT + 0.025, T + (stageFront - 0.5 - T) / 2, 8, 0.05, stageFront - 0.5 - T, C.Carpet, "Carpet", false)
	for _, row in { 10, 14, 18 } do
		for _, s in { -1, 1 } do
			local u = s * 13.5
			add("AuctionBench", "block", u, FT + 1.6, row, 15, 0.5, 2, C.Wood, "Wood", true)
			add("AuctionBenchBack", "block", u, FT + 2.95, row - 1.2, 15, 2.2, 0.4, C.Wood, "Wood", true)
			add("AuctionBenchLeg", "block", u - 6.5, FT + 0.675, row, 0.6, 1.35, 1.6, C.Wood, "Wood", false)
			add("AuctionBenchLeg", "block", u + 6.5, FT + 0.675, row, 0.6, 1.35, 1.6, C.Wood, "Wood", false)
		end
	end
	-- the consignment desk by the door on the right (its front to the aisle), its marble top, the bell, the board
	local deskU = W / 2 - 5.5
	add("AuctionDesk", "block", deskU, FT + 1.7, 4.75, 3, 3.4, 5.5, C.Wood, "Wood", true, nil, "desk")
	add("AuctionDeskTop", "block", deskU, FT + 3.525, 4.75, 3.4, 0.25, 5.9, C.Marble, "Marble", false)
	add("AuctionBell", "block", deskU - 0.5, FT + 3.9, 3, 0.6, 0.5, 0.6, C.Gold, "Metal", false)
	add("AuctionNotice", "block", W / 2 - T - 0.15, FT + 6.5, 3.4, 0.3, 2.4, 4, C.Burgundy, "SmoothPlastic", false, nil, "notice") -- (before the first window)
	-- the two hanging lamps over the aisle
	for _, v in { 9, 18 } do
		add("AuctionLampCord", "block", 0, base - 1.5, v, 0.15, 3, 0.15, C.Wood, "Metal", false)
		add("AuctionLamp", "block", 0, base - 3.45, v, 2.6, 0.9, 2.6, C.Lamp, "SmoothPlastic", false, nil, "lamp")
	end
	cache, cachedFor = list, key
	return list
end

return AuctionHouseLayout
