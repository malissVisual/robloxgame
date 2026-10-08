-- 6.0, throwing a delivery at a door (shared/Throws.luau, Config.Throw): the aim, the power, the launch, the traced
-- arc (the ground, a wall's bounce), where it lands, the TRICKSHOT tip and what is too fragile to throw.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Throws = require("./Throws")
local Gestures = require("./Gestures") -- 6.8 review: the throw's arm at the whip
local CharacterGeometry = require("./CharacterGeometry") -- 6.8 review: the courier's rig (6.9: the classic R15's)

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Throw
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end
local function len(v: { number }): number
	return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
end
local function upDeg(v: { number }): number
	return math.deg(math.atan2(v[2], math.sqrt(v[1] * v[1] + v[3] * v[3])))
end

-- The numbers ------------------------------------------------------------------------------------------------------

check("a throw from up to ~45 studs, a door's spot of ~4", T.Range >= 30 and T.Range <= 60 and T.DoorRadius >= 2 and T.DoorRadius <= 6)
check("the strongest throw reaches the range", T.MaxSpeed * T.MaxSpeed / T.Gravity >= T.Range - 1, T.MaxSpeed * T.MaxSpeed / T.Gravity)
check("the speeds and angles in order", T.MinSpeed > 0 and T.MinSpeed < T.MaxSpeed and T.MinUp >= 0 and T.MinUp < T.MaxUp and T.MaxUp < 90)
check("the tips in order", T.FarFrom > 0 and T.FarFrom < T.Range and T.FarMin > 0 and T.FarMin < T.FarMax and T.OverTip > 0 and T.WallTip > 0)
check("the fragile looks of the plan", T.FragileLooks.cake and T.FragileLooks.vaccine and T.FragileLooks.sample and T.FragileLooks.electronics
	and T.FragileLooks.painting and T.FragileLooks.gadget and not T.FragileLooks.pizza)

-- The release and the aim ------------------------------------------------------------------------------------------

local from = Throws.release({ 0, 3, 0 }, { 0, 0, -1 })
check("released ahead, to the right and up", near(from[1], T.Release.side) and near(from[2], 3 + T.Release.up) and near(from[3], -T.Release.ahead))
local turned = Throws.release({ 10, 0, 10 }, { 1, 0.5, 0 }) -- facing +x: the right is +z (a pitched look counts flat)
check("released for a turned body", near(turned[1], 10 + T.Release.ahead) and near(turned[3], 10 + T.Release.side))
-- 6.8 review: the piece leaves the hand where the hand is. The right hand's grip (the courier's rig at rest, the
-- root at the origin) with the "throw" gesture's arm and torso WindUp seconds in (when the server lets it go): within
-- a few tenths of Release (it was the shoulder, the piece popped down ~1.8 studs out of the raised hand).
do
	-- 6.9: the couriers wear Roblox's classic blocky R15 (server/CourierAvatar.luau); its stand-in here is the native
	-- block body (CharacterArt's 6.0 body, the infected's: the classic R15's proportions and joints)
	local spec = CharacterGeometry.spec("walker")
	local at: { [string]: { number } } = {}
	for _, j in spec.joints do
		at[j.name] = j.at
	end
	local hand: { number } = { 0, 0, 0 }
	for _, b in spec.bones do
		if b.name == "RightHand" then
			hand = b.at
		end
	end
	local g = spec.grips.RightHand
	local grip = { hand[1] + g[1], hand[2] + g[2], hand[3] + g[3] }
	type M = { { number } }
	local function mul(a: M, b: M): M
		local out: M = {}
		for i = 1, 3 do
			out[i] = {}
			for k = 1, 3 do
				out[i][k] = a[i][1] * b[1][k] + a[i][2] * b[2][k] + a[i][3] * b[3][k]
			end
		end
		return out
	end
	local function apply(m: M, v: { number }): { number }
		return {
			m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
			m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
			m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
		}
	end
	local function sub(a: { number }, b: { number }): { number }
		return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
	end
	local function add(a: { number }, b: { number }): { number }
		return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
	end
	-- (as client/ArmPose.luau turns a pose: CFrame.Angles(0, y, 0) * CFrame.Angles(x, 0, z), degrees)
	local function angles(a: { number }?): M
		local x, y, z = math.rad(a and a[1] or 0), math.rad(a and a[2] or 0), math.rad(a and a[3] or 0)
		local rx: M = { { 1, 0, 0 }, { 0, math.cos(x), -math.sin(x) }, { 0, math.sin(x), math.cos(x) } }
		local ry: M = { { math.cos(y), 0, math.sin(y) }, { 0, 1, 0 }, { -math.sin(y), 0, math.cos(y) } }
		local rz: M = { { math.cos(z), -math.sin(z), 0 }, { math.sin(z), math.cos(z), 0 }, { 0, 0, 1 } }
		return mul(ry, mul(rx, rz))
	end
	local t = T.WindUp
	local arm = Gestures.pose("throw", t) :: Gestures.Pose
	local body = Gestures.body("throw", t)
	local W = angles(body and body.waist)
	local S = mul(W, angles(arm.rs))
	local E = mul(S, angles(arm.re))
	local H = mul(E, angles(arm.rw))
	local shoulder = add(at.Waist, apply(W, sub(at.RightShoulder, at.Waist)))
	local elbow = add(shoulder, apply(S, sub(at.RightElbow, at.RightShoulder)))
	local wrist = add(elbow, apply(E, sub(at.RightWrist, at.RightElbow)))
	local held = add(wrist, apply(H, sub(grip, at.RightWrist)))
	local r = T.Release
	check("the release is the hand at the whip (side, up, ahead)", near(held[1], r.side, 0.15) and near(held[2], r.up, 0.15) and near(-held[3], r.ahead, 0.15),
		string.format("%.2f %.2f %.2f", held[1], held[2], -held[3]))
	check("the hand at the whip is up over the shoulder", held[2] > at.RightShoulder[2] + 1, held[2])
	check("near the root (the server takes a client's point within 3 studs of its own)", math.sqrt(r.side ^ 2 + r.up ^ 2 + r.ahead ^ 2) < 3)
end

local level = Throws.aim({ 0, 0, -1 }) :: { number }
check("looking level throws up by Lift", level ~= nil and near(upDeg(level), T.Lift, 1e-4) and near(len(level), 1) and level[3] < 0)
check("looking down still throws up a little", near(upDeg(Throws.aim({ 0, -0.99, -0.1 }) :: { number }), T.MinUp, 1e-4))
check("looking up is kept under MaxUp", near(upDeg(Throws.aim({ 0.05, 0.99, 0 }) :: { number }), T.MaxUp, 1e-4))
check("straight up or down: no way to throw", Throws.aim({ 0, 1, 0 }) == nil and Throws.aim({ 0, -1, 0 }) == nil)

-- The power --------------------------------------------------------------------------------------------------------

check("the power starts at 0", Throws.charge(0) == 0 and Throws.charge(-1) == 0 and Throws.charge(0 / 0) == 0)
check("full after ChargeTime", near(Throws.charge(T.ChargeTime), 1))
check("half way up", near(Throws.charge(T.ChargeTime / 2), 0.5))
check("then back down", near(Throws.charge(T.ChargeTime * 1.5), 0.5) and near(Throws.charge(T.ChargeTime * 2), 0, 1e-6))
local inRange = true
for i = 0, 100 do
	local p = Throws.charge(i * 0.037)
	inRange = inRange and p >= 0 and p <= 1
end
check("always within 0 … 1", inRange)

-- The launch -------------------------------------------------------------------------------------------------------

local weak = Throws.velocity({ 0, 0.5, -1 }, 0) :: { number }
local strong = Throws.velocity({ 0, 0.5, -1 }, 1) :: { number }
check("the weakest and the strongest speeds", near(len(weak), T.MinSpeed) and near(len(strong), T.MaxSpeed))
check("the power is clamped", near(len(Throws.velocity({ 1, 1, 0 }, 7) :: { number }), T.MaxSpeed) and near(len(Throws.velocity({ 1, 1, 0 }, -3) :: { number }), T.MinSpeed))
check("a too low throw goes up MinUp", near(upDeg(Throws.velocity({ 1, -1, 0 }, 0.5) :: { number }), T.MinUp, 1e-4))
check("a too steep throw goes up MaxUp", near(upDeg(Throws.velocity({ 0.01, 1, 0 }, 0.5) :: { number }), T.MaxUp, 1e-4))
check("a broken direction: no throw", Throws.velocity({ 0, 1, 0 }, 1) == nil and Throws.velocity({ 0 / 0, 0, 1 }, 1) == nil
	and Throws.velocity({ math.huge, 0, 1 }, 1) == nil and Throws.velocity({} :: any, 1) == nil)
check("a broken power: the weakest", near(len(Throws.velocity({ 1, 0.3, 0 }, 0 / 0) :: { number }), T.MinSpeed))

-- The arc ----------------------------------------------------------------------------------------------------------

-- A flat ground at y = 0 (and, given, a wall x = wallX facing -x).
local function ground(wallX: number?): Throws.Cast
	return function(a: { number }, b: { number }): Throws.Hit?
		if wallX and a[1] < wallX and b[1] >= wallX then
			local k = (wallX - a[1]) / (b[1] - a[1])
			local y = a[2] + (b[2] - a[2]) * k
			if y > 0 then
				return { at = { wallX, y, a[3] + (b[3] - a[3]) * k }, normal = { -1, 0, 0 } }
			end
		end
		if a[2] > 0 and b[2] <= 0 then
			local k = a[2] / (a[2] - b[2])
			return { at = { a[1] + (b[1] - a[1]) * k, 0, a[3] + (b[3] - a[3]) * k }, normal = { 0, 1, 0 } }
		end
		return nil
	end
end

local v45 = { math.cos(math.rad(45)) * 40, math.sin(math.rad(45)) * 40, 0 }
local flight = Throws.trace({ 0, 0.001, 0 }, v45, ground())
local ideal = 40 * 40 / T.Gravity
check("lands on the ground", flight.grounded and near(flight.land[2], 0))
check("as far as a 45° throw goes", near(flight.land[1], ideal, 0.5), `{flight.land[1]} vs {ideal}`)
check("in the time it takes", near(flight.time, 2 * v45[2] / T.Gravity, 0.05), flight.time)
check("no bounce in the open", not flight.bounced)
check("points and times go together", #flight.points == #flight.times and #flight.points > 10 and flight.times[1] == 0)
local rising = true
for i = 2, #flight.times do
	rising = rising and flight.times[i] >= flight.times[i - 1]
end
check("the times only go on", rising)
check("the arc's top", near(math.max(table.unpack((function()
	local ys = {}
	for _, p in flight.points do
		table.insert(ys, p[2])
	end
	return ys
end)())), v45[2] * v45[2] / (2 * T.Gravity), 0.3))
check("at(0) is the start, at(end) the landing", Throws.at(flight, 0)[1] == 0 and near(Throws.at(flight, flight.time + 1)[1], flight.land[1]))
local mid = Throws.at(flight, flight.time / 2)
check("half way: half the distance, near the top", near(mid[1], flight.land[1] / 2, 0.6) and mid[2] > 4.5)

local walled = Throws.trace({ 0, 1, 0 }, v45, ground(12))
check("a wall in the way: it bounces", walled.bounced and walled.grounded)
check("and lands in front of the wall", walled.land[1] < 12 and walled.land[1] > 0, walled.land[1])
local open = Throws.trace({ 0, 1, 0 }, { 30, 5, 0 }, nil)
check("nothing to hit: traced for MaxTime", not open.grounded and near(open.time, T.MaxTime, T.Step + 1e-6))
local stuck = Throws.trace({ 0, 5, 0 }, { 10, 0, 0 }, function(a: { number }, _b: { number }): Throws.Hit?
	return { at = a, normal = { -1, 0, 0 } } -- a wall right there, always
end)
check("a wall that never lets go still ends", #stuck.points < 200 and stuck.bounced and not stuck.grounded)

-- Landing and the tip ----------------------------------------------------------------------------------------------

check("at the door", Throws.landed({ 1, 0, 2 }, { 0, 0, 0 }))
check("just outside the door's spot", not Throws.landed({ T.DoorRadius + 0.1, 0, 0 }, { 0, 0, 0 }))
check("on the roof above the door: no", not Throws.landed({ 0, 12, 0 }, { 0, 0, 0 }))
check("flat distance", near(Throws.flat({ 3, 50, 4 }, { 0, 0, 0 }), 5))

local close = Throws.tip(10, false, false)
check("a short plain throw: no tip", close.total == 0 and close.far == 0)
check("just over FarFrom: FarMin", Throws.tip(T.FarFrom + 0.01, false, false).far == T.FarMin)
check("at the range: FarMax", Throws.tip(T.Range, false, false).far == T.FarMax and Throws.tip(T.Range + 30, false, false).far == T.FarMax)
local midTip = Throws.tip((T.FarFrom + T.Range) / 2, false, false).far
check("in between: in between", midTip > T.FarMin and midTip < T.FarMax, midTip)
local all = Throws.tip(T.Range, true, true)
check("over and off a wall add up", all.over == T.OverTip and all.wall == T.WallTip and all.total == T.FarMax + T.OverTip + T.WallTip)
check("a broken distance: no far tip", Throws.tip(0 / 0, false, false).total == 0)

-- What may be thrown -----------------------------------------------------------------------------------------------

check("a pizza flies", Throws.throwable("pizza", false) and not Throws.fragile("pizza", false))
check("a cake is too fragile", Throws.fragile("cake", false) and not Throws.throwable("cake", false))
check("a fragile job: nothing flies", Throws.fragile("pizza", true) and not Throws.throwable("mail", true))
check("heavy looks never fly", not Throws.throwable("crate", false) and not Throws.throwable("barrel", false) and not Throws.throwable(nil, false))
local everyLight = true
for look in Config.Cargo.LightLooks do
	everyLight = everyLight and (Throws.throwable(look, false) ~= Throws.fragile(look, false))
end
check("every light look either flies or is fragile", everyLight)

-- 6.2, the auto-aim and the PERFECT tip ----------------------------------------------------------------------------

check("the auto-aim numbers", #T.AutoAngles > 0 and T.PerfectRadius > 0 and T.PerfectRadius < T.DoorRadius and T.PerfectTip > 0
	and T.PerfectCap >= T.PerfectTip and #T.PerfectLines > 0)
-- A flat ground at `y`: the cast the server and the client give trace (plain tables, no Vector3 here).
local function plane(y: number): Throws.Cast
	return function(a: { number }, b: { number }): Throws.Hit?
		if a[2] >= y and b[2] < y then
			local k = (a[2] - y) / (a[2] - b[2])
			return { at = { a[1] + (b[1] - a[1]) * k, y, a[3] + (b[3] - a[3]) * k }, normal = { 0, 1, 0 } }
		end
		return nil
	end
end
local standing = CharacterGeometry.spec("courier").hipHeight + 1 -- 6.8 review: the courier's root over its feet (3.8)
for _, case in { { name = "flat", dy = 0, dist = 25 }, { name = "a porch", dy = 2, dist = 18 }, { name = "far", dy = 0, dist = 40 } } do
	local start = Throws.release({ 0, standing, 0 }, { 0, 0, -1 })
	local door = { 3, case.dy, -case.dist } -- (the body's feet at y 0, the door's spot dy over them)
	local any = false
	for _, angle in T.AutoAngles do
		local speed = Throws.solve(start, door, angle)
		local power = speed and Throws.powerFor(speed)
		local direction = Throws.direction(start, door, angle)
		if speed and power and direction then
			any = true
			local velocity = Throws.velocity(direction, power)
			local trace = velocity and Throws.trace(start, velocity, plane(case.dy))
			check(`{case.name} at {angle}°: the solved throw lands on the door`, trace ~= nil and trace.grounded and Throws.flat(trace.land, door) < 0.5,
				trace and Throws.flat(trace.land, door))
			local flatLand = velocity and Throws.landFlat(start, velocity, case.dy)
			check(`{case.name} at {angle}°: landFlat agrees`, flatLand ~= nil and Throws.flat(flatLand, door) < 0.2, flatLand and Throws.flat(flatLand, door))
		end
	end
	check(`{case.name}: some angle reaches the door`, any)
end
check("an angle under the door's height can't reach it", Throws.solve({ 0, 0, 0 }, { 0, 30, -10 }, 35) == nil)
check("no solve on the spot", Throws.solve({ 0, 0, 0 }, { 0, 0, 0 }, 45) == nil)
check("powerFor within the speeds", Throws.powerFor(T.MinSpeed) == 0 and Throws.powerFor(T.MaxSpeed) == 1 and Throws.powerFor(T.MaxSpeed + 1) == nil
	and Throws.powerFor(T.MinSpeed - 1) == nil)
check("perfect in the middle, not at the edge", Throws.perfect({ 1, 0, 0 }, { 0, 0, 0 }) and not Throws.perfect({ 2, 0, 0 }, { 0, 0, 0 })
	and not Throws.perfect({ 0, 8, 0 }, { 0, 0, 0 }))
check("landFlat: never down to a height over the arc", Throws.landFlat({ 0, 0, 0 }, { 0, 1, -1 }, 50) == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
