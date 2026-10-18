--!strict
-- 6.24, the special zombies (the owner: "new zombies, so the fighting isn't always the same"): the pure rules behind
-- the runner's leap, the brute's armour and the bloater's blast (Config.Zombies' lunge, armour, blast) and where they
-- come (Config.ZombieTypes). Shared by the server (server/Zombies.luau: the spawns, the damage, the blast) and the
-- tests (tests/zombiekinds_test.luau runs it in the plain Luau CLI; no Roblox at its top level).
--   * ZombieKinds.danger(distance)         0 … 1: how far from the old city's depot (DangerNear … DangerFar)
--   * ZombieKinds.weights(base, context)   a kinds table ({ kind = weight }) weighed for the night and the danger (a new
--                                          table; the base is never changed). (10.6: no job's tier, no player's level,
--                                          no Blood Moon: the city's.)
--   * ZombieKinds.capped(kind, alive)      is a kind at its MaxAlive (alive: how many of it live now)?
--   * ZombieKinds.isFront(lookX, lookZ, dirX, dirZ, angle)   does a hit travelling `dir` strike the front of a body
--                                          facing `look` (within `angle` degrees of where it faces)?
--   * ZombieKinds.armourShare(armour, hit) the share of a hit the plates let through (1: all)
--   * ZombieKinds.blastShare(blast, distance)   the share of a blast's damage at that distance (0 out of its radius)
--   * ZombieKinds.fuseLeft(fuseAt, now, seconds)   when a fuse goes off when it is (re)lit now for `seconds`: never
--                                          later than one already burning

local Config = require(script.Parent.Config)

local ZombieKinds = {}

local Types = Config.ZombieTypes

-- What a random pick of a kind knows: the night's share (0 … 1) and the danger (0 … 1).
export type Context = { night: number, danger: number }

-- What a hit on armour is: a headshot (crit), its cause ("gun" / nil a round, "melee", "car", "splash", "other" …), its
-- pellets (a shotgun's many), its damage (a pellet's) and whether it struck the front.
export type Hit = { crit: boolean, cause: string?, pellets: number, damage: number, front: boolean }

function ZombieKinds.danger(distance: number?): number
	if not distance then
		return 0
	end
	return math.clamp((distance - Types.DangerNear) / math.max(1, Types.DangerFar - Types.DangerNear), 0, 1)
end

-- One kind's factor for this context (1: as the table says).
function ZombieKinds.factor(kind: string, context: Context): number
	local factor = 1
	factor *= 1 + (Types.Night[kind] or 0) * math.clamp(context.night, 0, 1)
	factor *= 1 + (Types.Danger[kind] or 0) * math.clamp(context.danger, 0, 1)
	return math.max(0, factor)
end

function ZombieKinds.weights(base: { [string]: number }, context: Context): { [string]: number }
	local out: { [string]: number } = {}
	for kind, weight in base do
		out[kind] = math.max(0, weight) * ZombieKinds.factor(kind, context)
	end
	return out
end

-- The share of each kind in a weights table (for the tests and the admin's numbers).
function ZombieKinds.shares(weights: { [string]: number }): { [string]: number }
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local out: { [string]: number } = {}
	for kind, weight in weights do
		out[kind] = if total > 0 then weight / total else 0
	end
	return out
end

function ZombieKinds.capped(kind: string, alive: number): boolean
	local most = Types.MaxAlive[kind]
	return most ~= nil and alive >= most
end

function ZombieKinds.isFront(lookX: number, lookZ: number, dirX: number, dirZ: number, angle: number): boolean
	local look = math.sqrt(lookX * lookX + lookZ * lookZ)
	local dir = math.sqrt(dirX * dirX + dirZ * dirZ)
	if look < 1e-6 or dir < 1e-6 then
		return false
	end
	-- the way back to where it came from, against the way it faces
	local dot = -(lookX * dirX + lookZ * dirZ) / (look * dir)
	return dot >= math.cos(math.rad(angle))
end

function ZombieKinds.armourShare(armour: Config.ArmourDef, hit: Hit): number
	local cause = hit.cause
	if hit.crit or cause == "splash" or cause == "car" or cause == "other" or hit.pellets >= armour.pellets then
		return 1
	end
	local share = 1
	if hit.front then
		share *= armour.front
	end
	if (cause == nil or cause == "gun") and hit.damage <= armour.smallDamage then
		share *= armour.small
	end
	return math.clamp(share, armour.least, 1)
end

function ZombieKinds.blastShare(blast: Config.BlastDef, distance: number): number
	if distance > blast.radius or distance ~= distance then
		return 0
	end
	if distance <= blast.inner then
		return 1
	end
	local t = (distance - blast.inner) / math.max(1e-6, blast.radius - blast.inner)
	return 1 - (1 - blast.edge) * t
end

function ZombieKinds.fuseLeft(fuseAt: number?, now: number, seconds: number): number
	local at = now + math.max(0, seconds)
	return if fuseAt then math.min(fuseAt, at) else at
end

return ZombieKinds
