-- 8.3 walk-in doors: a door leaf's swing (shared/DoorSwing.luau, pure) and the trip's timing (Config.Moving.Doors). The
-- attributes read (DoorLeaf -1 / 0 / 1, DoorSwing ±1, DoorAngle, no leaf without a number), a leaf's pieces in its own
-- frame (one; a double door's two halves tiling it), its hinge at its end on the face it swings to (it stays put), open
-- it lies on its swing side clear of its frame turned Angle (an X-wide and a Z-wide leaf, both hinges, both swings), the
-- sandbox interior's front door leaves (open flat along the porch beside the doorway, their painted side to the porch's
-- middle), the easing (fast into the stop opening, slow then quick shutting), the dark doorway's size; the timing: the
-- leaf opens before the zone and is open by the end of the dwell at a walk (the trip never waits for it), the server's
-- move lands while the client's screen is black (FadeOut + Margin after the fade out, inside its black until it sees
-- itself there), Danny's own step within the dark, nothing the fade's own safety lifts early.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local DoorSwing = require("./DoorSwing")

local D = Config.Moving.Doors
local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local EPS = 1e-6
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or EPS)
end

-- A point `q` of a piece (its own frame, from its middle) at openness u, in the leaf's frame: (x, z). The game's
-- leaf * T(ox + hx, oz + hz) * Ry(yaw u) * T(-hx, -hz), about +Y a turn of θ taking (x, z) to (x cos θ + z sin θ,
-- -x sin θ + z cos θ).
local function at(p: DoorSwing.Piece, qx: number, qz: number, u: number): (number, number)
	local t = p.yaw * u
	local x, z = qx - p.hx, qz - p.hz
	return p.ox + p.hx + x * math.cos(t) + z * math.sin(t), p.oz + p.hz - x * math.sin(t) + z * math.cos(t)
end
-- Its four corners at openness u.
local function corners(p: DoorSwing.Piece, u: number): { { number } }
	local out = {}
	for _, c in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local x, z = at(p, c[1] * p.sx / 2, c[2] * p.sz / 2, u)
		table.insert(out, { x, z })
	end
	return out
end

-- ── The attributes ─────────────────────────────────────────────────────────

do
	local h, s, a = DoorSwing.read(1, nil, nil, 95)
	check("DoorLeaf 1 alone: hinged at its + end, swinging to its + side, the default angle", h == 1 and s == 1 and a == 95)
	h, s, a = DoorSwing.read(-1, -1, 90, 95)
	check("DoorLeaf -1, DoorSwing -1, DoorAngle 90 as given", h == -1 and s == -1 and a == 90)
	h = DoorSwing.read(0, 1, nil, 95)
	check("DoorLeaf 0: a double door", h == 0)
	h, s = DoorSwing.read(2.5, -7, nil, 95)
	check("…numbers by their sign (2.5 → 1, -7 → -1)", h == 1 and s == -1)
	check("no number, no leaf (nil, a word, true, NaN)", DoorSwing.read(nil, 1, 90, 95) == nil and DoorSwing.read("left", 1, 90, 95) == nil
		and DoorSwing.read(true, 1, 90, 95) == nil and DoorSwing.read(0 / 0, 1, 90, 95) == nil)
	local _, s2, a2 = DoorSwing.read(1, 0, 400, 95)
	local _, _, a3 = DoorSwing.read(1, 1, -10, 95)
	check("a swing of 0 swings to the + side; an angle out of (0, 180] is the default", s2 == 1 and a2 == 95 and a3 == 95)
end

-- ── The swing's geometry ───────────────────────────────────────────────────

-- every hinge and swing of a leaf `sx` × `sz` (one piece): its hinge stays put, shut it is the leaf, open it lies on the
-- swing side of its hinge (clear of its frame), its free end turned the angle about the hinge toward the swing side
local function oneLeaf(sx: number, sz: number, angle: number): (boolean, string)
	local alongX = sx >= sz
	for _, hinge in { -1, 1 } do
		for _, swing in { -1, 1 } do
			local pieces = DoorSwing.pieces(sx, sz, hinge, swing, angle)
			local p = pieces[1]
			if #pieces ~= 1 or p.ox ~= 0 or p.oz ~= 0 or not near(p.sx, sx) or not near(p.sz, sz) then
				return false, `{hinge} {swing}: not one piece, the leaf itself`
			end
			local width, thick = if alongX then sx else sz, if alongX then sz else sx
			local hingeAlong = if alongX then p.hx else p.hz
			local hingeAcross = if alongX then p.hz else p.hx
			if not near(hingeAlong, hinge * width / 2) or not near(hingeAcross, swing * thick / 2) then
				return false, `{hinge} {swing}: the hinge not at its end on the swing face`
			end
			local hx, hz = at(p, p.hx, p.hz, 1)
			if not near(hx, p.hx) or not near(hz, p.hz) then
				return false, `{hinge} {swing}: the hinge moved`
			end
			for _, c in corners(p, 0) do
				if math.abs(c[1]) > sx / 2 + EPS or math.abs(c[2]) > sz / 2 + EPS then
					return false, `{hinge} {swing}: shut, not the leaf`
				end
			end
			for _, c in corners(p, 1) do
				local across = (if alongX then c[2] - p.hz else c[1] - p.hx) * swing
				if across < -1e-4 then
					return false, `{hinge} {swing}: open, a corner behind its hinge ({across})`
				end
			end
			-- the free end's middle (its edge on the middle plane) turned `angle` about the hinge, toward the swing side
			local fx, fz = if alongX then -hinge * sx / 2 else 0, if alongX then 0 else -hinge * sz / 2
			local ox, oz = at(p, fx, fz, 1)
			local sx0, sz0 = fx - p.hx, fz - p.hz
			local sx1, sz1 = ox - p.hx, oz - p.hz
			local turned = math.deg(math.acos(math.clamp((sx0 * sx1 + sz0 * sz1) / (math.sqrt(sx0 * sx0 + sz0 * sz0) * math.sqrt(sx1 * sx1 + sz1 * sz1)), -1, 1)))
			local side = (if alongX then oz - fz else ox - fx) * swing
			if not near(turned, angle, 1e-3) or side <= 0 then
				return false, `{hinge} {swing}: the free end turned {turned}° (side {side})`
			end
		end
	end
	return true, ""
end
local okX, whyX = oneLeaf(4, 0.4, 95)
check("an X-wide leaf (the chalet's 4 × 0.4): its hinge at its end on the swing face, put; open on the swing side, turned Angle", okX, whyX)
local okZ, whyZ = oneLeaf(0.4, 4, 90)
check("a Z-wide leaf (a door in a side wall, 0.4 × 4): the same along Z", okZ, whyZ)
local okW, whyW = oneLeaf(7.8, 0.4, 120)
check("a wide one at 120°", okW, whyW)

do
	local pieces = DoorSwing.pieces(6, 0.4, 0, 1, 90)
	local a, b = pieces[1], pieces[2]
	local tiles = #pieces == 2 and near(a.sx, 3) and near(b.sx, 3) and near(a.ox, -1.5) and near(b.ox, 1.5) and near(a.hx, -1.5) and near(b.hx, 1.5)
	check("a double door (DoorLeaf 0): two halves tiling it, hinged at its two ends", tiles)
	local _, az = at(a, 1.5, 0, 1)
	local _, bz = at(b, -1.5, 0, 1)
	check("…both swing to the same side (their inner ends to +Z), meeting in its middle when shut", az > 2.5 and bz > 2.5 and near(at(a, 1.5, 0, 0), 0) and near(at(b, -1.5, 0, 0), 0))
end

-- the sandbox interior's front door (server/HouseInterior.luau frontLeaves): two leaves, each half the 7-wide doorway,
-- 0.24 thick, DoorLeaf ±1 at the doorway's sides, DoorSwing -1 (out onto the porch, -Z), DoorAngle 90
do
	local leaf = Config.Furniture.FrontDoor / 2
	local ok = true
	for _, s in { -1, 1 } do
		local p = DoorSwing.pieces(leaf, 0.24, s, -1, 90)[1]
		-- the leaf's middle sits at s · leaf / 2 from the doorway's middle
		local mx, mz = at(p, 0, 0, 1)
		local x = s * leaf / 2 + mx
		local normalX = math.sin(p.yaw) -- (its +Z face, the painted one, turned by yaw: (sin, cos))
		ok = ok and math.abs(x) > leaf - 0.25 and math.abs(x) < leaf + 0.25 and mz < -leaf / 2 and near(math.cos(p.yaw), 0)
			and normalX * s < -0.99
	end
	check("the interior's front door leaves: open flat along the porch beside the doorway, painted side to its middle", ok)
end

-- ── The easing, the dark doorway ───────────────────────────────────────────

do
	local monotone = true
	local lastO, lastC = -1, -1
	for i = 0, 20 do
		local o, c = DoorSwing.ease(i / 20, true), DoorSwing.ease(i / 20, false)
		monotone = monotone and o >= lastO and c >= lastC
		lastO, lastC = o, c
	end
	check("the swing's share: 0 … 1 both ways, never back", DoorSwing.ease(0, true) == 0 and DoorSwing.ease(1, true) == 1 and DoorSwing.ease(0, false) == 0
		and DoorSwing.ease(1, false) == 1 and monotone and DoorSwing.ease(-1, true) == 0 and DoorSwing.ease(2, false) == 1)
	check("…opening fast, easing into the stop; shutting slow, then quicker into the frame", DoorSwing.ease(0.5, true) > 0.8 and DoorSwing.ease(0.5, false) < 0.3)
	local x, y, z = DoorSwing.dark(4, 7, 0.4)
	local x2, _, z2 = DoorSwing.dark(0.4, 7, 4)
	check("the dark doorway: the leaf's whole face (two halves meet with no seam), thin in its middle plane", x == 4 and y == 7 and z <= 0.05 and x2 <= 0.05
		and z2 == 4)
end

-- ── The timing (Config.Moving.Doors) ───────────────────────────────────────

check("the doors swing; the numbers are there", D.Swing == true and D.Open > 0 and D.Close > 0 and D.Shut > 0 and D.FadeOut > 0 and D.Margin > 0
	and D.Dark > 0 and D.FadeIn > 0 and D.Wait > 0 and D.Stream > 0 and D.Arrive > 0 and D.Angle > 0 and D.Angle <= 180)
check("about the owner's numbers: the leaf ~0.35 s, the fade out ~0.25 s, the fade in ~0.35 s", near(D.Open, 0.35, 0.1) and near(D.FadeOut, 0.25, 0.1)
	and near(D.FadeIn, 0.35, 0.1))
check("the leaf starts opening before the zone (its approach deeper and wider)", D.Approach > D.Depth + 1 and D.ApproachSide >= 0)
-- walking up at the walk (or with a two-hands piece: the slowest carry but a drag), the leaf has opened by the end of
-- the dwell: the trip never stops you at a shut door
local walk = Config.Movement.Walk
local slow = walk * Config.Moving.Speed.Both
check("…and it is open by the end of the dwell at a walk, even with a piece in both hands", (D.Approach - D.Depth) / walk + D.Dwell >= D.Open
	and (D.Approach - D.Depth) / slow + D.Dwell >= D.Open, (D.Approach - D.Depth) / walk + D.Dwell)
-- the client's screen is black FadeOut s after the fade out reaches it; the server moves you FadeOut + Margin s after it
-- sent it: the message and the move both cross the network, Margin is the room for their unevenness
local moveAt = D.FadeOut + D.Margin
check("the server's move lands after the client's screen is black (FadeOut + Margin, Margin for the network)", moveAt > D.FadeOut and D.Margin >= 0.05
	and D.Margin <= D.FadeOut)
-- the client keeps it black until it sees itself there (Wait s at most), then Dark s: Danny's own step (Config.MoveHelper
-- .Tick) puts him at the far end within that even when the trip did not
check("…the black held Dark s once there: Danny's own step comes within it", D.Dark >= Config.MoveHelper.Tick and D.Wait > D.Dark)
check("…and the fade out's own safety (client/Fade.luau HOLD, 4 s) never lifts it before the move, the stream's wait too", moveAt + D.Stream < 4)
check("a door's whole trip stays short: the leaf, the dwell, the fade, the black and the fade in under 2 s", D.Open + D.FadeOut + D.Margin + D.Dark + D.FadeIn < 2)
check("the zones' 8.1 rules kept: you come out past the zone (4 studs out; the entry EntryIn in), the dwell before Rearm", D.Depth < 4
	and D.Depth < Config.Furniture.EntryIn and D.Dwell < D.Rearm and D.Walk == true)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
