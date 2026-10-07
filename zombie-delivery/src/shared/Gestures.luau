--!strict
-- 5.7: short arm gestures of people and couriers, the pure part (no Roblox at its top level, so
-- tests/gestures_test.luau runs it in the standalone Luau). The server names one on a character or a person
-- (server/Npcs.luau Npcs.act: the attributes Gesture = the kind, GestureAt = the server time it starts) and every
-- client lays it over the arms (client/ArmPose.luau, the joints' Transform in PreSimulation; never C0).
--   wave   the right hand up beside the head, waving (a receiver at the door, a giver calling you over)
--   give   both hands forward, holding out (the courier handing a piece over, a giver handing one to you)
--   take   both hands forward and a little lower, reaching to take it
--   knock  the right fist forward at the door, three knocks (the sound's knocks, Config.Juice.KnockGap apart)
--   bag    6.0: the right hand drops a piece into the plastic bag in the left (a pick-up into the bag)
--   throw  6.0: the right arm winds back over the shoulder and whips forward (a throw at a door)
--   vest   6.0: both arms over the head, then down, tugging a new vest straight
--   sling / unsling  6.4: the right hand reaches over the left shoulder for the bag's strap and swings the bag onto
--          the back (sling) or back to the front (unsling) (server/KitWear.luau; client/BagSway.luau moves the bag)
--   pickup 6.7: down on the knees, the back bent, the right hand to a piece (a bag) on the ground and up with it
--   land   6.7: a short dip on the knees (client/BodyLife.luau dips a landing by itself, by the fall)
-- 6.7: "pickup" and "land" also bend the body (shared/BodyMotion.luau gesture, their seconds Config.Body.Gestures):
-- the keys waist / neck ({ x, y, z } degrees) and crouch ({ drop, back } studs, the hips' tip in degrees);
-- client/ArmPose.luau bends the legs so the feet stay where they stood.
--   receive  6.7: both hands held in front of the chest, holding the piece just handed over (a receiver at the door)
-- 6.7, items in the hand (server/HandItem.luau holds the piece in the right hand while these play): give holds the
-- piece out in both hands a little closer together (a box about a stud wide between them), take and receive hold it
-- in front of the chest; bag reaches across with it to the bag's mouth and dips in at Config.Courier.HandItem.BagIn
-- (the piece goes in then); throw winds up until Config.Throw.WindUp (the arm back over the shoulder) and whips
-- through it (the server lets the piece go at WindUp, half-way through the whip), then follows through.
-- Gestures.body(kind, t): 6.7, the torso and the head with it (client/BagSway.luau lays them on the Waist and the Neck):
-- the bag's look down at it, the throw's turn of the torso back and through, a small bow handing over.
-- Angles are in degrees per joint (rs, re, rw: the right shoulder, elbow, wrist; ls, le, lw: the left), as
-- { x, y, z }: ArmPose turns them into CFrame.Angles(0, y, 0) * CFrame.Angles(x, 0, z). For an R15 arm hanging
-- down, +x lifts it forward, +y turns it in (the right arm; the left mirrored), +z lifts the right arm out sideways.

local Config = require(script.Parent.Config)
local BodyMotion = require(script.Parent.BodyMotion) -- 6.7: the gestures with the legs

local Gestures = {}

export type Angles = { number } -- { x, y, z } degrees
export type Pose = { [string]: Angles } -- rs re rw ls le lw

local J = Config.Juice

-- How long a gesture lasts (nil: no such gesture).
function Gestures.seconds(kind: string): number?
	return J.Gestures[kind] or Config.Body.Gestures[kind] -- (6.7: pickup, land)
end

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

-- How far the gesture is laid over the arms (0..1) `t` seconds after it began: in over the first quarter (at most
-- 0.18 s), held, out over the last third (at most 0.3 s). 0 before the start and from the end on.
function Gestures.weight(kind: string, t: number): number
	local total = Gestures.seconds(kind)
	if not total or t <= 0 or t >= total then
		return 0
	end
	local rise = math.min(total * 0.25, 0.18)
	local fall = math.min(total / 3, 0.3)
	return math.min(smooth(t / rise), smooth((total - t) / fall))
end

-- The arm angles `t` seconds into the gesture (the shape it is lerped toward; nil for an unknown kind).
function Gestures.pose(kind: string, t: number): Pose?
	local body = BodyMotion.gesture(kind, t) -- 6.7: pickup, land
	if body then
		return body
	end
	if kind == "wave" then
		local swing = math.sin(2 * math.pi * J.WaveHz * math.max(0, t))
		return {
			rs = { 14, 0, 148 + 12 * swing },
			re = { 22, 0, 0 },
			rw = { 0, 0, 18 * swing },
		}
	elseif kind == "give" then
		-- (6.7: the hands closer together, the piece held out between them)
		return {
			rs = { 72, 20, 0 },
			re = { 16, 0, 0 },
			rw = { -18, 0, 0 },
			ls = { 72, -20, 0 },
			le = { 16, 0, 0 },
			lw = { -18, 0, 0 },
		}
	elseif kind == "take" then
		return {
			rs = { 62, 16, 0 },
			re = { 30, 0, 0 },
			rw = { -8, 0, 0 },
			ls = { 62, -16, 0 },
			le = { 30, 0, 0 },
			lw = { -8, 0, 0 },
		}
	elseif kind == "receive" then
		-- 6.7: the piece handed over held in front of the chest, the elbows bent
		return {
			rs = { 56, 18, 0 },
			re = { 42, 0, 0 },
			rw = { -14, 0, 0 },
			ls = { 56, -18, 0 },
			le = { 42, 0, 0 },
			lw = { -14, 0, 0 },
		}
	elseif kind == "knock" then
		-- The fist comes in to the door on every knock (a sharp tap, back out between them), three times.
		local gap = J.KnockGap
		local tap = 0
		if t >= 0 and t < gap * 3 then
			local phase = (t % gap) / gap
			tap = math.max(0, 1 - phase * 3) -- the hit at the start of each gap, then back
		end
		return {
			rs = { 58 + 10 * tap, -6, 0 },
			re = { 74 - 14 * tap, 0, 0 },
			rw = { -10, 0, 0 },
		}
	elseif kind == "bag" then
		-- 6.0: a piece dropped into the plastic bag: the right hand across to the left hip and in, the left hand
		-- lifts the bag's mouth a little forward. 6.7: with the piece in the hand (server/HandItem.luau): across to
		-- the mouth, in (deepest at HandItem.BagIn, when it goes in), and back.
		-- (6.7, worked out on the courier's R15 arms: the left hand brings a hand bag up in front of the belly, its mouth
		-- under the right hand, which reaches across to the middle and dips down into it)
		local reach, dip = Gestures.bagMove(t)
		return {
			rs = { 48 * reach, 58 * reach + 8 * dip, 0 },
			re = { 40 * reach - 30 * dip, 0, 0 },
			rw = { -20 * reach - 10 * dip, 0, 0 },
			ls = { 16 * reach, -58 * reach, 0 },
			le = { 95 * reach, 0, 0 },
		}
	elseif kind == "throw" then
		-- 6.0: a throw at a door: the right arm winds back over the shoulder, then whips forward and down. 6.7: the
		-- wind-up ends just before Config.Throw.WindUp, the whip goes through it (the piece leaves the hand there), and
		-- the left arm points at the door, then swings down.
		local wind, whip = Gestures.throwMove(t)
		local function mix(a: number, b: number, c: number): number
			return a + (b - a) * wind + (c - b) * whip
		end
		return {
			rs = { mix(40, 168, 62), mix(0, -10, 14), mix(10, 28, 0) },
			re = { mix(30, 95, 8), 0, 0 },
			rw = { mix(0, 25, -35), 0, 0 },
			ls = { mix(40, 62, 28), mix(-10, -14, -4), 0 },
			le = { 20, 0, 0 },
		}
	elseif kind == "sling" or kind == "unsling" then
		-- 6.4: a bag swung onto the back (sling) or back to the front (unsling): the right hand reaches across to the
		-- left shoulder and grips the strap, then pulls it back over the shoulder (sling) or down to the front
		-- (unsling); the left arm lifts a little out of the way.
		local u = math.clamp(t / (J.Gestures[kind] or 0.55), 0, 1)
		local reach = smooth(u / 0.4)
		local pull = smooth((u - 0.4) / 0.6)
		local back = if kind == "sling" then 1 else -0.6
		return {
			rs = { 30 + 95 * reach + 25 * pull * back, 10 + 40 * reach, 0 },
			re = { 20 + 85 * reach - 30 * pull, 0, 0 },
			rw = { -10, 0, 0 },
			ls = { 10 + 12 * reach, 0, -12 * reach },
			le = { 15, 0, 0 },
		}
	elseif kind == "vest" then
		-- 6.0: a vest put on: both arms up over the head, then down, tugging it straight at the chest.
		local u = math.clamp(t / (J.Gestures.vest or 1.2), 0, 1)
		local up = smooth(u / 0.45)
		local down = smooth((u - 0.45) / 0.55)
		local shoulder = 20 + 145 * up - 125 * down
		local elbow = 20 + 40 * up + 30 * down
		return {
			rs = { shoulder, 10 + 10 * down, 0 },
			re = { elbow, 0, 0 },
			rw = { -10, 0, 0 },
			ls = { shoulder, -10 - 10 * down, 0 },
			le = { elbow, 0, 0 },
			lw = { -10, 0, 0 },
		}
	end
	return nil
end

-- 6.7: the bag gesture's reach (0..1: across to the bag's mouth) and dip (0..1, deepest at HandItem.BagIn).
function Gestures.bagMove(t: number): (number, number)
	local total = J.Gestures.bag or 0.5
	local at = Config.Courier.HandItem.BagIn
	local reach = smooth(t / math.max(0.05, total * 0.4))
	local dip = math.sin(math.pi * math.clamp((t - (at - 0.12)) / 0.24, 0, 1))
	return reach, dip
end

-- 6.7: the throw's wind-up (0..1, done just before Config.Throw.WindUp) and whip (0..1, a third of the way through at
-- WindUp: the arm over the shoulder, coming forward, where the piece leaves the hand).
function Gestures.throwMove(t: number): (number, number)
	local release = Config.Throw.WindUp
	local wind = smooth(t / math.max(0.05, release - 0.05))
	local whip = smooth((t - (release - 0.05)) / 0.12)
	return wind, whip
end

-- 6.7: the torso and the head in a gesture (degrees, { x, y, z } as for the arms: the Waist's and the Neck's turn laid
-- on top of the animation by client/BagSway.luau; +x tips forward … backward for the waist and lifts the head, +y
-- turns them to the left); nil for a gesture of the arms alone.
function Gestures.body(kind: string, t: number): Pose?
	if kind == "bag" then
		-- looking down at the bag's mouth on the left, bent a little toward it
		local reach, dip = Gestures.bagMove(t)
		return { waist = { -8 * reach, 10 * reach, 0 }, neck = { -22 * reach - 8 * dip, 10 * reach, 0 } }
	elseif kind == "throw" then
		-- the torso turns the right shoulder back in the wind-up and through to the left in the whip, leaning into it;
		-- the head keeps looking at the door
		local wind, whip = Gestures.throwMove(t)
		local function mix(a: number, b: number, c: number): number
			return a + (b - a) * wind + (c - b) * whip
		end
		return { waist = { mix(0, 4, -8), mix(0, -24, 16), 0 }, neck = { 0, mix(0, 18, -12), 0 } }
	elseif kind == "give" then
		return { waist = { -4, 0, 0 }, neck = { -6, 0, 0 } } -- (a small bow, handing it over)
	end
	return nil
end

-- R6 bodies (no elbows): the right and left shoulders' angle about their own Z (+ is forward for both; ArmPose mirrors
-- the left), degrees; nil leaves that arm alone.
function Gestures.r6(kind: string, t: number): (number?, number?)
	local pose = Gestures.pose(kind, t)
	if not pose then
		return nil, nil
	end
	if kind == "wave" then
		return 160 + 12 * math.sin(2 * math.pi * J.WaveHz * math.max(0, t)), nil
	end
	local rs, re, ls, le = pose.rs, pose.re, pose.ls, pose.le
	local right = if rs then rs[1] + (if re then re[1] * 0.3 else 0) else nil
	local left = if ls then ls[1] + (if le then le[1] * 0.3 else 0) else nil
	return right, left
end

return Gestures
