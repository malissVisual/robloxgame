--!strict
-- 3.9: the melee's rules, pure (no Roblox at its top level, so tests/melee_test.luau runs it in the standalone Luau):
-- what a swing is (a punch with the gun holstered, a strike with the gun in the hand), its numbers (Config.Melee), the
-- cone in front of you that it reaches (server/CloseCombat.luau picks the nearest enemy in it) and the arm's swing
-- curve over Config.Melee.SwingTime (client/ArmPose.luau). Positions are plain numbers: X and Z along the ground, Y up.

local Config = require(script.Parent.Config)

local Melee = {}

export type KindDef = { damage: number, cooldown: number, push: number }

-- The swing for the hands' state: "punch" (holstered) or "gun".
function Melee.kindOf(holstered: boolean): string
	return if holstered then "punch" else "gun"
end

-- A kind's numbers (an unknown kind is a punch).
function Melee.def(kind: string): KindDef
	local kinds: { [string]: KindDef } = Config.Melee.Kinds
	return kinds[kind] or kinds.punch
end

-- Is a point in reach of a swing from (fromX, fromY, fromZ) toward (dirX, dirZ) along the ground? Returns its distance
-- along the ground when it is (within Config.Melee.Reach, HalfAngle to either side and Height up or down), else nil.
-- Something right on top of you (closer than a stud) is always in reach, whatever the direction.
function Melee.reach(fromX: number, fromY: number, fromZ: number, dirX: number, dirZ: number, toX: number, toY: number, toZ: number): number?
	local cfg = Config.Melee
	if math.abs(toY - fromY) > cfg.Height then
		return nil
	end
	local dx, dz = toX - fromX, toZ - fromZ
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > cfg.Reach then
		return nil
	end
	if distance < 1 then
		return distance
	end
	local length = math.sqrt(dirX * dirX + dirZ * dirZ)
	if length < 1e-6 then
		return nil
	end
	local cosine = (dx * dirX + dz * dirZ) / (distance * length)
	return if cosine >= math.cos(math.rad(cfg.HalfAngle)) then distance else nil
end

-- The arm's swing `elapsed` seconds after it started: how far the swing pose is laid over the arm (0 = not at all,
-- 1 = fully) and where it is between the wind-up (0) and the hit (1). Quick back, a snap forward, then back down:
--   the first quarter  winds up (the pose comes in, at the wind-up)
--   the second quarter snaps from the wind-up to the hit
--   the second half    eases back from the hit to the animation
-- After SwingTime (or before 0) it is (0, 0): no swing.
function Melee.swing(elapsed: number): (number, number)
	local total = Config.Melee.SwingTime
	if elapsed < 0 or elapsed >= total or total <= 0 then
		return 0, 0
	end
	local p = elapsed / total
	if p < 0.25 then
		local k = p / 0.25
		return 1 - (1 - k) * (1 - k), 0
	elseif p < 0.5 then
		local k = (p - 0.25) / 0.25
		return 1, k * (2 - k) -- eased: fast into the hit
	end
	local k = (p - 0.5) / 0.5
	return 1 - k * k, 1
end

return Melee
