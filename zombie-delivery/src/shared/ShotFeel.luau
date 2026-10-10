--!strict
-- 6.16, shooting and hits (the owner: "I want to upgrade the visuals and the feel"): the pure rules of the shots' show,
-- their numbers in Config.Shots. Pure (no Roblox at its top level; tests/shotfeel_test.luau runs it in the plain Luau
-- CLI). The server still decides every hit (server/Gun.luau); all of this is the client's picture.
--   * ShotFeel.kick(id): a gun's kick (Config.Shots.Guns by a weapon's or a car gun's id, else Default): the camera's
--     pitch and yaw (client/ShotKick.luau), the arms' (client/ArmPose.luau), the casing it throws (client/ShotFx.luau).
--   * ShotFeel.spring(x, v, rate, dt): one step of a critically damped spring, exact at any frame time (a hitch never
--     makes it overshoot): the camera's kick and a headshot's punch spring back by it.
--   * ShotFeel.impulse(peak, rate): the speed that sends a spring at rest up to `peak` (at 1 / rate s).
--   * ShotFeel.fall(casing, dt): a shell casing's flight: gravity, a bounce on the floor under it, then rest.
--   * ShotFeel.surface(material): what a round shows where it stops, by the material's name: "metal" (sparks), "stone"
--     (a few sparks and dust), "wood" (chips), "soft" (dust), "glass" (glints), "water" (a splash, no mark).
--   * ShotFeel.hitKind(crit, killed) / ShotFeel.marker(kind, killed): the Hit remote's news as "hit" | "kill" |
--     "head", and the hit marker's look for it (Config.Shots.Marker) with whether a skull shows.
--   * ShotFeel.bucket(burst) / ShotFeel.allow(bucket, now, perSecond, burst): a token bucket (other shooters' impacts).
--   * ShotFeel.ring(size) / ShotFeel.take(ring): a round-robin pool's next slot (the oldest one goes first).

local Config = require(script.Parent.Config)

local ShotFeel = {}

local Shots = Config.Shots
local E = math.exp(1)

function ShotFeel.kick(id: string?): Config.ShotKickDef
	return (if id then Shots.Guns[id] else nil) or Shots.Default
end

-- A critically damped spring pulled to 0 at `rate` (1/s): x and its speed v after dt seconds (the exact solution).
function ShotFeel.spring(x: number, v: number, rate: number, dt: number): (number, number)
	if dt <= 0 then
		return x, v
	end
	local decay = math.exp(-rate * dt)
	local b = v + rate * x
	return (x + b * dt) * decay, (v - rate * b * dt) * decay
end

-- The speed that sends a spring at rest to `peak` (it gets there 1 / rate seconds later, then settles back).
function ShotFeel.impulse(peak: number, rate: number): number
	return peak * rate * E
end

-- A shell casing in the air: where it is, how fast it goes, the floor under it (world Y), and whether it lies still.
export type Fall = { x: number, y: number, z: number, vx: number, vy: number, vz: number, floor: number, resting: boolean }

-- One step of a casing's flight (Config.Shots.Casings): falls, bounces on its floor (losing speed), comes to rest.
-- Returns true on the step it bounced.
function ShotFeel.fall(c: Fall, dt: number): boolean
	if c.resting or dt <= 0 then
		return false
	end
	local tuning = Shots.Casings
	c.vy -= tuning.Gravity * dt
	c.x += c.vx * dt
	c.y += c.vy * dt
	c.z += c.vz * dt
	if c.y > c.floor or c.vy >= 0 then
		return false
	end
	c.y = c.floor
	c.vy = -c.vy * tuning.Bounce
	c.vx *= tuning.Friction
	c.vz *= tuning.Friction
	if c.vy < 1.5 then
		c.vx, c.vy, c.vz = 0, 0, 0
		c.resting = true
	end
	return true
end

-- What a round shows where it stops, by Enum.Material's name. Anything not named (Plastic, SmoothPlastic: most walls
-- here) is "stone".
local SURFACE: { [string]: string } = {
	Metal = "metal", CorrodedMetal = "metal", DiamondPlate = "metal", Foil = "metal",
	Wood = "wood", WoodPlanks = "wood", Cardboard = "wood", RoofShingles = "wood",
	Grass = "soft", LeafyGrass = "soft", Sand = "soft", Mud = "soft", Ground = "soft", Snow = "soft", Salt = "soft",
	Fabric = "soft", Carpet = "soft", Leather = "soft", Rubber = "soft",
	Glass = "glass", Ice = "glass", Glacier = "glass", Neon = "glass",
	Water = "water",
}

function ShotFeel.surface(material: string): string
	return SURFACE[material] or "stone"
end

-- Does a round leave a dark mark on this surface (water does not)?
function ShotFeel.marks(surface: string): boolean
	return surface ~= "water"
end

-- The Hit remote's news (server/Gun.luau: crit = a headshot; killed = true, or a number of kills for a blast).
function ShotFeel.hitKind(crit: boolean?, killed: any): (string, boolean)
	local dead = killed == true or (type(killed) == "number" and killed > 0)
	return if crit then "head" elseif dead then "kill" else "hit", dead
end

export type MarkerLook = { color: { number }, size: number, seconds: number, thick: number }

-- The hit marker for a hit of `kind` ("hit" | "kill" | "head"; a headshot counts as a kill unless `killed` is false),
-- and whether the small skull shows over it.
function ShotFeel.marker(kind: string, killed: boolean?): (MarkerLook, boolean)
	local m = Shots.Marker
	local kill = kind == "kill" or (kind == "head" and killed ~= false)
	local look = if kind == "head" then m.Head elseif kind == "kill" then m.Kill else m.Hit
	return look, kill and m.Skull == true
end

-- A token bucket: `perSecond` come back a second, `burst` at most.
export type Bucket = { tokens: number, at: number }

function ShotFeel.bucket(burst: number): Bucket
	return { tokens = burst, at = 0 }
end

function ShotFeel.allow(bucket: Bucket, now: number, perSecond: number, burst: number): boolean
	bucket.tokens = math.min(burst, bucket.tokens + math.max(0, now - bucket.at) * perSecond)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- A pool of `size` things used in turn: the next one is always the one used longest ago.
export type Ring = { size: number, next: number }

function ShotFeel.ring(size: number): Ring
	return { size = math.max(1, size), next = 1 }
end

function ShotFeel.take(ring: Ring): number
	local slot = ring.next
	ring.next = slot % ring.size + 1
	return slot
end

return ShotFeel
