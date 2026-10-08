--!strict
-- 6.10, the curb as plain numbers: the sidewalks of the city blocks stand Map.WalkTop, the roads Map.RoadTop, so a
-- block's edge is a curb Height (0.5 studs, about 15 cm) over the road. Its kerb is a slope, not a step: from the
-- block's edge it runs Run (Map.CurbRun) studs out onto the road, down from the walk's top to the road's. Why a slope:
-- the vehicles' wheels are frictionless colliders pushed along the ground by a LinearVelocity (server/Vehicles.luau);
-- a slope lifts them anywhere along the curb, at any angle, slow or fast, and lets them roll down again, but a step as
-- high as a small wheel's axle (the E-Scooter's is 0.6) would stop them dead. The people walk up it like any slope.
--
-- The ring round a block (server/Curbs.luau builds it with the block's sidewalk slab, server/World.luau): a wedge
-- along each of the four sides and a corner wedge (a hip: its apex over the slab's corner, sloping down both ways) at
-- each corner. Nothing of it stands up from the road. Pure Luau (no Roblox types): tests/curb_test.luau checks it.
--
--   CurbShape.Height, Run, Slope, Angle  the curb's height, the ramp's length out onto the road, its rise per stud and
--                                        its angle (radians)
--   CurbShape.rise(out)                  the kerb's height over the road `out` studs out from the curb (the block's edge)
--   CurbShape.outside(x, z)              how far (x, z) is outside the nearest city block (≤ 0: on a block)
--   CurbShape.groundAt(x, z)             the ground's top there: the walk on a block, the ramp by it, else the road
--   CurbShape.pieces(cx, cz)             the ring of the block centred at (cx, cz): its eight pieces

local Map = require(script.Parent.Map)

local CurbShape = {}

local BLOCK = Map.BlockSize
local CELL = Map.Cell

CurbShape.Height = Map.WalkTop - Map.RoadTop
CurbShape.Run = Map.CurbRun
CurbShape.Slope = CurbShape.Height / CurbShape.Run
CurbShape.Angle = math.atan(CurbShape.Slope)

-- One piece of a ring: its middle (x, y, z), its size along its own axes (sx along X, sy up, sz along Z) and its X
-- axis on the ground (rx, rz; Y is up, Z = X × Y). An "edge" is a WedgePart: its high side at its +Z (against the
-- slab), its low edge at its -Z (out on the road). A "corner" is a CornerWedgePart: its apex over its (+X, -Z) corner,
-- which is the slab's corner.
export type Piece = {
	kind: string, -- "edge" | "corner"
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	rx: number,
	rz: number,
}

-- The kerb's height over the road `out` studs out from the curb (0 and less: on the walk).
function CurbShape.rise(out: number): number
	if out <= 0 then
		return CurbShape.Height
	end
	return CurbShape.Height * math.max(0, 1 - out / CurbShape.Run)
end

-- How far (x, z) lies outside the nearest block of the districts (≤ 0: on a block): beyond a side, the distance out
-- from it; beyond a corner, the larger of the two (the ring's hip there).
function CurbShape.outside(x: number, z: number): number
	local best = math.huge
	for _, d in Map.Districts do
		local i = math.clamp(math.floor((x - d.ox) / CELL + 0.5), d.i0, d.i1)
		local j = math.clamp(math.floor((z - d.oz) / CELL + 0.5), d.j0, d.j1)
		local du = math.abs(x - (d.ox + i * CELL)) - BLOCK / 2
		local dv = math.abs(z - (d.oz + j * CELL)) - BLOCK / 2
		best = math.min(best, math.max(du, dv))
	end
	return best
end

-- The ground's top at (x, z) in the city: the walk on a block, the kerb's slope next to it, the road beyond (the far
-- places' yards and the land are not asked about here).
function CurbShape.groundAt(x: number, z: number): number
	return Map.RoadTop + CurbShape.rise(CurbShape.outside(x, z))
end

-- The ring round the block centred at (cx, cz): four edges (north, east, south, west), then the four corners.
function CurbShape.pieces(cx: number, cz: number): { Piece }
	local half, run, height = BLOCK / 2, CurbShape.Run, CurbShape.Height
	local y = Map.RoadTop + height / 2
	local list: { Piece } = {}
	-- n: the side's way out of the block. The wedge's -Z (its low edge) looks out: its X = Y × (-n) = (-nz, nx).
	for _, n in { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } do
		local nx, nz = n[1], n[2]
		table.insert(list, {
			kind = "edge",
			x = cx + nx * (half + run / 2),
			y = y,
			z = cz + nz * (half + run / 2),
			sx = BLOCK,
			sy = height,
			sz = run,
			rx = -nz,
			rz = nx,
		})
	end
	-- A corner (sx, sz: the ways out of the block there). The corner wedge's apex is over its (+X, -Z) corner and it
	-- slopes down toward -X and +Z: -X must be one way out (d1) and +Z = X × Y the other (d2). With X = -d1, X × Y is
	-- (d1z, 0, -d1x): d1 along X fits when sz = -sx, d1 along Z when sz = sx.
	for _, s in { { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } } do
		local sx, sz = s[1], s[2]
		local d1x, d1z = if sz == -sx then sx else 0, if sz == -sx then 0 else sz
		table.insert(list, {
			kind = "corner",
			x = cx + sx * (half + run / 2),
			y = y,
			z = cz + sz * (half + run / 2),
			sx = run,
			sy = height,
			sz = run,
			rx = -d1x,
			rz = -d1z,
		})
	end
	return list
end

return CurbShape
