--!strict
-- 4.5: the admin's test buddies' decisions, pure (no Roblox at its top level, so tests/buddy_test.luau runs it in the
-- standalone Luau): where each buddy stands round its owner, whether it walks, runs, stands or appears at its place
-- (follow, stay, guard), when it counts as stuck, which passenger seat it takes and how it gets in, and its hit
-- chance. server/Buddy.luau moves the bodies. Positions are plain numbers: X and Z along the ground.

local Config = require(script.Parent.Config)

local BuddyBrain = {}

export type Mode = "follow" | "stay" | "guard"

-- What a buddy does now: "stand", "move" (to x, z; run = at the run speed) or "teleport" (appear at x, z).
export type Decision = { action: string, x: number, z: number, run: boolean }

export type Input = {
	mode: Mode,
	x: number, -- the buddy
	z: number,
	moving: boolean, -- it walks now (a standing one waits for Restart, a walking one stops at Arrive)
	ownerX: number?, -- the owner on foot (nil: no owner to follow, e.g. dead)
	ownerZ: number?,
	placeX: number?, -- its place round the owner (BuddyBrain.place)
	placeZ: number?,
	homeX: number?, -- guard: its spot
	homeZ: number?,
	enemyX: number?, -- guard: the nearest enemy it fights
	enemyZ: number?,
}

local function dist(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

-- Is the mode one of the three? (a bad value from the admin panel)
function BuddyBrain.validMode(mode: any): boolean
	return mode == "follow" or mode == "stay" or mode == "guard"
end

-- Buddy `index` of `count`: its place round an owner at (ox, oz) looking along (lookX, lookZ): behind them, fanned out
-- to both sides (one right behind, two to the back left and right, three spread wider).
function BuddyBrain.place(index: number, count: number, ox: number, oz: number, lookX: number, lookZ: number, distance: number?): (number, number)
	local d = distance or Config.Buddy.FollowDistance
	local len = math.sqrt(lookX * lookX + lookZ * lookZ)
	local fx, fz = if len > 0.01 then lookX / len else 0, if len > 0.01 then lookZ / len else 1
	local n = math.max(count, 1)
	local spread = 0.75 -- radians between neighbours
	local angle = math.pi + (index - (n + 1) / 2) * spread -- pi: right behind
	local c, s = math.cos(angle), math.sin(angle)
	-- (fx, fz) turned by angle round the up axis
	local dx, dz = fx * c - fz * s, fx * s + fz * c
	return ox + dx * d, oz + dz * d
end

-- To (gx, gz): stand when there (with the walk/stand hysteresis), else move (run when it is far).
local function goTo(input: Input, gx: number, gz: number, runFrom: number): Decision
	local cfg = Config.Buddy
	local gap = dist(input.x, input.z, gx, gz)
	if gap > cfg.TeleportDistance then
		return { action = "teleport", x = gx, z = gz, run = false }
	end
	local threshold = if input.moving then cfg.Arrive else cfg.Restart
	if gap <= threshold then
		return { action = "stand", x = input.x, z = input.z, run = false }
	end
	return { action = "move", x = gx, z = gz, run = runFrom > cfg.RunFrom }
end

function BuddyBrain.decide(input: Input): Decision
	local cfg = Config.Buddy
	local stand: Decision = { action = "stand", x = input.x, z = input.z, run = false }
	if input.mode == "stay" then
		return stand
	end
	if input.mode == "guard" then
		local hx, hz = input.homeX, input.homeZ
		if hx == nil or hz == nil then
			return stand
		end
		local ex, ez = input.enemyX, input.enemyZ
		if ex ~= nil and ez ~= nil and dist(ex, ez, hx, hz) <= cfg.Range then
			local toEnemy = dist(input.x, input.z, ex, ez)
			if toEnemy <= cfg.GuardCloseIn then
				return stand -- close enough: stand and shoot
			end
			-- A step toward it (to get it in sight), never farther than the leash from the spot.
			local dx, dz = ex - hx, ez - hz
			local len = math.sqrt(dx * dx + dz * dz)
			local reach = math.min(cfg.GuardLeash, math.max(0, len - cfg.GuardCloseIn * 0.8))
			local gx, gz = hx, hz
			if len > 0.01 then
				gx, gz = hx + dx / len * reach, hz + dz / len * reach
			end
			return goTo(input, gx, gz, 0)
		end
		return goTo(input, hx, hz, dist(input.x, input.z, hx, hz))
	end
	-- follow
	local ox, oz, px, pz = input.ownerX, input.ownerZ, input.placeX, input.placeZ
	if ox == nil or oz == nil then
		return stand -- the owner is away (dead, in a car with no seat for it): wait
	end
	local toOwner = dist(input.x, input.z, ox, oz)
	local gx, gz = px or ox, pz or oz
	if toOwner > cfg.TeleportDistance then
		return { action = "teleport", x = gx, z = gz, run = false }
	end
	return goTo(input, gx, gz, toOwner)
end

-- Seconds it has been stuck: `moved` studs since the last decision (dt s ago) while it should move. Moving at under a
-- fifth of the walk counts as stuck; a buddy that stands is never stuck.
function BuddyBrain.stuck(stuckFor: number, moved: number, dt: number, wantsToMove: boolean): number
	if not wantsToMove then
		return 0
	end
	if moved < Config.Buddy.Speed * dt * 0.2 then
		return stuckFor + dt
	end
	return 0
end

-- The first seat it may take: free[i] = nobody sits in passenger seat i and nobody is on the way into it.
function BuddyBrain.pickSeat(free: { boolean }): number?
	for i, ok in free do
		if ok then
			return i
		end
	end
	return nil
end

-- The owner sits in their car: how does a buddy `distance` studs from it get in? "sit" (into the seat now: near a
-- car that stands, or far away / stuck: it appears in it) or "walk" (to the car first).
function BuddyBrain.boarding(distance: number, carSpeed: number, stuckFor: number): string
	local cfg = Config.Buddy
	if distance > cfg.TeleportDistance or stuckFor >= cfg.StuckSeconds then
		return "sit"
	end
	if distance <= cfg.BoardReach and carSpeed <= Config.Cargo.BoardMaxSpeed then
		return "sit"
	end
	return "walk"
end

-- The chance a shot hits a target moving at `speed` studs/s (like the bandits': worse at a fast one).
function BuddyBrain.hitChance(speed: number): number
	return Config.Buddy.Accuracy * math.clamp(1 - speed / 120, 0.3, 1)
end

-- How many more buddies the owner may get: `want` asked, `have` already (capped at Config.Buddy.Max).
function BuddyBrain.allowed(have: number, want: number?): number
	local n = math.floor(want or 1)
	return math.clamp(n, 0, math.max(0, Config.Buddy.Max - have))
end

return BuddyBrain
