--!strict
-- 5.7: short arm gestures of people and couriers, the pure part (no Roblox at its top level, so
-- tests/gestures_test.luau runs it in the standalone Luau). The server names one on a character or a person
-- (server/Npcs.luau Npcs.act: the attributes Gesture = the kind, GestureAt = the server time it starts) and every
-- client lays it over the arms (client/ArmPose.luau, the joints' Transform in PreSimulation; never C0).
--   wave   the right hand up beside the head, waving (a receiver at the door, a giver calling you over)
--   give   both hands forward, holding out (the courier handing a piece over, a giver handing one to you)
--   take   both hands forward and a little lower, reaching to take it
--   knock  the right fist forward at the door, three knocks (the sound's knocks, Config.Juice.KnockGap apart)
-- Angles are in degrees per joint (rs, re, rw: the right shoulder, elbow, wrist; ls, le, lw: the left), as
-- { x, y, z }: ArmPose turns them into CFrame.Angles(0, y, 0) * CFrame.Angles(x, 0, z). For an R15 arm hanging
-- down, +x lifts it forward, +y turns it in (the right arm; the left mirrored), +z lifts the right arm out sideways.

local Config = require(script.Parent.Config)

local Gestures = {}

export type Angles = { number } -- { x, y, z } degrees
export type Pose = { [string]: Angles } -- rs re rw ls le lw

local J = Config.Juice

-- How long a gesture lasts (nil: no such gesture).
function Gestures.seconds(kind: string): number?
	return J.Gestures[kind]
end

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

-- How far the gesture is laid over the arms (0..1) `t` seconds after it began: in over the first quarter (at most
-- 0.18 s), held, out over the last third (at most 0.3 s). 0 before the start and from the end on.
function Gestures.weight(kind: string, t: number): number
	local total = J.Gestures[kind]
	if not total or t <= 0 or t >= total then
		return 0
	end
	local rise = math.min(total * 0.25, 0.18)
	local fall = math.min(total / 3, 0.3)
	return math.min(smooth(t / rise), smooth((total - t) / fall))
end

-- The arm angles `t` seconds into the gesture (the shape it is lerped toward; nil for an unknown kind).
function Gestures.pose(kind: string, t: number): Pose?
	if kind == "wave" then
		local swing = math.sin(2 * math.pi * J.WaveHz * math.max(0, t))
		return {
			rs = { 14, 0, 148 + 12 * swing },
			re = { 22, 0, 0 },
			rw = { 0, 0, 18 * swing },
		}
	elseif kind == "give" then
		return {
			rs = { 74, 10, 0 },
			re = { 14, 0, 0 },
			rw = { -16, 0, 0 },
			ls = { 74, -10, 0 },
			le = { 14, 0, 0 },
			lw = { -16, 0, 0 },
		}
	elseif kind == "take" then
		return {
			rs = { 62, 12, 0 },
			re = { 30, 0, 0 },
			rw = { -8, 0, 0 },
			ls = { 62, -12, 0 },
			le = { 30, 0, 0 },
			lw = { -8, 0, 0 },
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
