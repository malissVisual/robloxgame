-- 6.10, the curb (shared/CurbShape.luau, Map.WalkTop over Map.RoadTop): the sidewalks a little higher than the road,
-- the kerb a gentle slope all round every block (its eight pieces closing the ring, no step anywhere), and what stands
-- by the curb on the flat (the crosswalks, the parks, the bus, the poles, the docks, the kerb props, the lost
-- packages); in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local Crossings = require("./Crossings")
local BusLines = require("./BusLines")
local RentalDocks = require("./RentalDocks")
local CurbShape = require("./CurbShape")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, e: number?): boolean
	return math.abs(a - b) <= (e or 1e-6)
end

local BLOCK, ROAD = Map.BlockSize, Map.RoadWidth
local H, RUN = CurbShape.Height, CurbShape.Run

-- ── The numbers ────────────────────────────────────────────────────────────
check("the road stays at its level", Map.RoadTop == 0.4)
check("the sidewalks a curb over the road: 0.5 studs (a little: about 15 cm)", near(Map.WalkTop - Map.RoadTop, 0.5) and near(H, 0.5), Map.WalkTop)
-- The wheels are frictionless colliders pushed by a LinearVelocity of at most mass × 160 (server/Vehicles.luau) under
-- the world's gravity 196.2: a slope of rise s per stud costs s × 196.2 of it. 0.25 is a third of the push and keeps the
-- hop small at speed; the run stays clear of the bus at its stop (2 studs from the curb).
check("the kerb is a gentle slope (≤ 0.3 per stud, 14°)", CurbShape.Slope <= 0.3 and near(CurbShape.Slope, H / RUN), CurbShape.Slope)
check("the kerb's run fits beside a bus at its stop", RUN <= Map.CurbPark - BusLines.HalfWidth + 1e-6, `{RUN} vs {Map.CurbPark - BusLines.HalfWidth}`)
-- client/CurbRide.luau holds a vehicle's climb over a kerb to CurbHop: never slower than the slope lifts it at 20
-- studs / s (a slow climb is untouched), and well under the 15 / s a 60 studs / s run up the slope would fling it.
check("the hop held over a kerb: a slow climb untouched, the fling at speed cut", Config.City.CurbHop >= CurbShape.Slope * 20 and Config.City.CurbHop <= 8, Config.City.CurbHop)
check("rise: the walk at the curb, the road at the ramp's foot, straight between", near(CurbShape.rise(-3), H) and near(CurbShape.rise(0), H) and near(CurbShape.rise(RUN / 2), H / 2) and near(CurbShape.rise(RUN), 0) and near(CurbShape.rise(RUN + 5), 0))

-- ── The ring ───────────────────────────────────────────────────────────────
local d = Map.Districts[1]
local cx, cz = d.ox + 2 * Map.Cell, d.oz - 1 * Map.Cell -- an ordinary Downtown block
local pieces = CurbShape.pieces(cx, cz)
local edges, corners = 0, 0
for _, p in pieces do
	if p.kind == "edge" then
		edges += 1
	elseif p.kind == "corner" then
		corners += 1
	end
end
check("a ring is four wedges along the sides and four corner wedges", #pieces == 8 and edges == 4 and corners == 4, `{edges} + {corners}`)

-- A piece's local frame: X on the ground, Y up, Z = X × Y.
local function axes(p: CurbShape.Piece): (number, number, number, number)
	return p.rx, p.rz, -p.rz, p.rx
end
local function point(p: CurbShape.Piece, lx: number, lz: number): (number, number)
	local xx, xz, zx, zz = axes(p)
	return p.x + xx * lx + zx * lz, p.z + xz * lx + zz * lz
end
-- The top of a piece at its local (lx, lz) over the road, nil off its footprint. An edge (a WedgePart): its full
-- height at its +Z side, nothing at its -Z. A corner (a CornerWedgePart): its apex over its (+X, -Z) corner.
local function topOf(p: CurbShape.Piece, lx: number, lz: number): number?
	if math.abs(lx) > p.sx / 2 + 1e-6 or math.abs(lz) > p.sz / 2 + 1e-6 then
		return nil
	end
	if p.kind == "edge" then
		return p.sy * (lz + p.sz / 2) / p.sz
	end
	local a, b = (p.sx / 2 - lx) / p.sx, (lz + p.sz / 2) / p.sz
	return p.sy * (1 - math.max(a, b))
end
local function ringTop(x: number, z: number): number?
	local best: number? = nil
	for _, p in pieces do
		local xx, xz, zx, zz = axes(p)
		local dx, dz = x - p.x, z - p.z
		local top = topOf(p, dx * xx + dz * xz, dx * zx + dz * zz)
		if top and (best == nil or top > best) then
			best = top
		end
	end
	return best
end

local shapeOk, shapeWhy = true, ""
for _, p in pieces do
	local xx, xz, zx, zz = axes(p)
	local unit = near(xx * xx + xz * xz, 1) and near(zx * zx + zz * zz, 1) and near(xx * zx + xz * zz, 0)
	local flat = near(p.y, Map.RoadTop + H / 2) and near(p.sy, H)
	if not unit or not flat then
		shapeOk, shapeWhy = false, `{p.kind} at {p.x}, {p.z}: axes / height`
	elseif p.kind == "edge" then
		-- its high side against the slab (on the block's edge), its low edge Run out on the road, as long as the side
		local hx, hz = point(p, 0, p.sz / 2)
		local lx, lz = point(p, 0, -p.sz / 2)
		if not (near(CurbShape.outside(hx, hz), 0) and near(CurbShape.outside(lx, lz), RUN) and near(p.sx, BLOCK) and near(p.sz, RUN)) then
			shapeOk, shapeWhy = false, `edge at {p.x}, {p.z}: high {CurbShape.outside(hx, hz)}, low {CurbShape.outside(lx, lz)}`
		end
	else
		-- its apex over the slab's corner, its far corner out on the road (Run out both ways)
		local ax, az = point(p, p.sx / 2, -p.sz / 2)
		local fx, fz = point(p, -p.sx / 2, p.sz / 2)
		local apex = near(math.abs(ax - cx), BLOCK / 2) and near(math.abs(az - cz), BLOCK / 2)
		local far = near(math.abs(fx - cx), BLOCK / 2 + RUN) and near(math.abs(fz - cz), BLOCK / 2 + RUN)
		if not (apex and far and near(p.sx, RUN) and near(p.sz, RUN)) then
			shapeOk, shapeWhy = false, `corner at {p.x}, {p.z}: apex {ax}, {az}, far {fx}, {fz}`
		end
	end
end
check("every piece: level axes, the curb's height, high side on the slab, low edge out on the road", shapeOk, shapeWhy)

-- Walk round the block a stud out at a time (along every side and round every corner, at every distance out up to
-- past the ramp): the ring's top is the kerb's slope everywhere, no notch, no step, nothing past the run.
local worst, notch, ringOk = 0, 0, true
for out = 0.05, RUN + 1, 0.15 do
	for t = -BLOCK / 2 - RUN - 1, BLOCK / 2 + RUN + 1, 0.7 do
		for _, side in { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } do
			local nx, nz = side[1], side[2]
			local x = cx + nx * (BLOCK / 2 + out) + (if nx == 0 then t else 0)
			local z = cz + nz * (BLOCK / 2 + out) + (if nz == 0 then t else 0)
			local want = CurbShape.rise(CurbShape.outside(x, z))
			local top = ringTop(x, z) or 0
			worst = math.max(worst, math.abs(top - want))
			if want > 1e-3 and ringTop(x, z) == nil then
				notch += 1
			end
			if CurbShape.outside(x, z) > RUN + 1e-6 and top > 1e-6 then
				ringOk = false
			end
		end
	end
end
check("the ring is the kerb's slope all round (sides and corners), no notch", worst < 1e-6 and notch == 0, `worst {worst}, notches {notch}`)
check("nothing of the ring past its run", ringOk)

-- ── The ground ─────────────────────────────────────────────────────────────
check("groundAt: the walk on a block, the road in a street", near(CurbShape.groundAt(cx, cz), Map.WalkTop) and near(CurbShape.groundAt(cx + Map.Cell / 2, cz), Map.RoadTop) and near(CurbShape.groundAt(cx + BLOCK / 2 - 0.1, cz + 20), Map.WalkTop))
check("groundAt: halfway down the ramp, halfway up the curb", near(CurbShape.groundAt(cx + BLOCK / 2 + RUN / 2, cz), Map.RoadTop + H / 2))
check("groundAt: the corner's hip (the farther way out counts)", near(CurbShape.groundAt(cx + BLOCK / 2 + 0.5, cz - BLOCK / 2 - 1.5), Map.RoadTop + CurbShape.rise(1.5)))
check("groundAt agrees with Map.blockAt", (function()
	for x = -700, 1700, 37 do
		for z = -700, 1300, 41 do
			local onBlock = Map.blockAt(x, z) ~= nil
			if onBlock ~= (CurbShape.outside(x, z) < 0) then
				print("  disagree at", x, z)
				return false
			end
		end
	end
	return true
end)())

-- ── What stands by the curb ────────────────────────────────────────────────
local stripes = 0
for _, s in Crossings.Stripes do
	stripes = math.max(stripes, math.abs(s) + Crossings.StripeWidth / 2)
end
check("the crosswalks' stripes end before the kerb's slope", stripes <= ROAD / 2 - RUN, `{stripes} vs {ROAD / 2 - RUN}`)
check("a van parked at a park (CurbPark out) stands beside the slope, not on it", Map.CurbPark - 3.4 >= RUN)
local parksOk = true
for _, list in { Map.Homes, Map.Venues } do
	for _, place in list do
		if CurbShape.outside(place.park.x, place.park.z) < Map.CurbPark - 0.5 then
			parksOk = false
			print("  a park by the slope:", place.park.x, place.park.z)
		end
	end
end
check("every home's and storefront's park is out on the road", parksOk)
check("the light poles on the corners stand on the walk", Crossings.PoleCorner - ROAD / 2 > 0.5 and near(CurbShape.groundAt(cx + BLOCK / 2 - (Crossings.PoleCorner - ROAD / 2), cz - BLOCK / 2 + 1.5), Map.WalkTop))
local docksOk = true
for _, dock in RentalDocks.docks() do
	for _, slot in dock.slots do
		if not near(CurbShape.groundAt(slot.x, slot.z), Map.WalkTop) then
			docksOk = false
			print("  a dock's slot off the walk:", dock.id, slot.x, slot.z)
		end
	end
end
check("every rental dock's scooters stand on the walk", docksOk)
check("the kerb props stand on the walk", Config.LivingCity.Street.CurbDepth > 0.5)
local tyres = Config.LivingCity.Street.CarKerb - 2.19 -- an abandoned car's kerb-side tyres (server/StreetDressing.luau)
check("an abandoned car's kerb-side tyres stand on the slope (it leans), its street side on the road", tyres > 0 and tyres < RUN and Config.LivingCity.Street.CarKerb + 2.19 > RUN)
local packagesOk = true
for _, secret in Map.Secrets do
	if Map.blockAt(secret.x, secret.z) and secret.y < Map.WalkTop - 1e-6 then
		packagesOk = false
		print("  under the walk:", secret.id)
	end
end
check("the lost packages on the blocks lie on the walk (or higher)", packagesOk)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
