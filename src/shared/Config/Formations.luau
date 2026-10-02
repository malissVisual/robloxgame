--!strict
-- Enemy FORMATIONS: layouts of a wave on the fight platform. NOT USED to place anybody since the fight starts
-- without a teleport (both sides walk from their rows, see Plots.showEnemies / Plots.enemyGround); the module and
-- its test (tools/tests/mutators_test.luau) stay for a future layout mode. Waves.formation(wave, twists) still names
-- the wave's layout. Original description:
-- Where the wave stands in the fight arena when the fight starts. A layout is a list of slots per
-- role (melee / heavy / ranged / boss) as offsets from the arena center (x to the side, z toward the enemies' end);
-- `Formations.spots` hands every enemy of the wave a world position, in the order of the wave's enemy list.
--
--   Formations.spots(name, roles, center) → { Vector3 }   roles[i] = "melee" | "heavy" | "ranged" | "boss" | "totem" | "treasure"
--
-- The arena platform is 72 studs deep (center z ± 36) and 76 wide; every spot is clamped to x ∈ center ± ClampX and
-- z ∈ center + [ClampZMin, ClampZMax] (the enemies' half, 16 studs from the squad's front row), and no two spots end
-- up closer than MinGap. Layouts: line (the plain 4-column grid), wedge (brutes in the tip, grunts on the diagonals,
-- shooters behind), shieldwall (one wide melee row, shooters behind), pincer (two groups on the flanks), bossCourt
-- (the boss in the middle, its wave on a ring) and scatter — the ONLY layout for more than 12 enemies (6 × 3).
-- Waves.formation(wave, twists) picks the layout; all numbers live here.

local Formations = {}

Formations.ClampX = 34
Formations.ClampZMin = -8
Formations.ClampZMax = 32
Formations.MinGap = 4 -- studs between two spots (a safety pass nudges closer ones apart)
Formations.ScatterFrom = 13 -- this many enemies (totems / treasure not counted) always use "scatter"

Formations.Totems = { Vector3.new(-14, 0, 17), Vector3.new(14, 0, 17), Vector3.new(0, 0, 17) } -- the 1st, 2nd, 3rd totem
Formations.Treasure = Vector3.new(0, 0, 28)

type Slots = { melee: { Vector3 }, ranged: { Vector3 }, boss: { Vector3 }, heavy: { Vector3 }? }

local function v(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

-- A grid of `columns` columns (`spacing` apart, centered) in rows at the given z offsets, front row first.
local function grid(columns: number, spacing: number, rows: { number }): { Vector3 }
	local list: { Vector3 } = {}
	for _, z in rows do
		for column = 1, columns do
			table.insert(list, v((column - (columns + 1) / 2) * spacing, z))
		end
	end
	return list
end

-- The shared reserve row at the back: used when a layout runs out of slots for a role.
local OVERFLOW = { v(4, 30), v(-4, 30), v(12, 30), v(-12, 30), v(20, 30), v(-20, 30), v(28, 30), v(-28, 30) }

local LAYOUTS: { [string]: () -> Slots } = {
	line = function()
		local all = grid(4, 13, { 12, 22, 32 })
		return { melee = all, ranged = all, boss = all } -- one shared grid: melee fill the front first, shooters follow
	end,
	wedge = function()
		return {
			heavy = { v(0, 8), v(-7, 8), v(7, 8) }, -- the tip
			melee = { v(-13, 12), v(13, 12), v(-26, 16), v(26, 16), v(-19.5, 14), v(19.5, 14), v(-7, 8), v(7, 8), v(0, 8) }, -- the diagonals
			ranged = { v(0, 22), v(-8, 22), v(8, 22), v(-16, 22), v(16, 22), v(-24, 22), v(24, 22) },
			boss = { v(0, 8) },
		}
	end,
	shieldwall = function()
		return {
			melee = { v(-3.5, 12), v(3.5, 12), v(-10.5, 12), v(10.5, 12), v(-17.5, 12), v(17.5, 12), v(-24.5, 12), v(24.5, 12) },
			ranged = { v(0, 22), v(-8, 22), v(8, 22), v(-16, 22), v(16, 22), v(-24, 22), v(24, 22) },
			boss = { v(0, 4) }, -- (a boss wave uses bossCourt; this is the fallback: in front of the wall)
		}
	end,
	pincer = function()
		return {
			melee = { v(-22, 0), v(22, 0), v(-29, 0), v(29, 0), v(-15, 0), v(15, 0), v(-22, 5), v(22, 5), v(-29, 5), v(29, 5) },
			ranged = { v(-22, 10), v(22, 10), v(-29, 10), v(29, 10), v(-15, 10), v(15, 10) },
			boss = { v(0, 14) },
		}
	end,
	bossCourt = function()
		local bossZ = 14
		local melee: { Vector3 } = {}
		local ranged: { Vector3 } = {}
		-- The inner ring (radius 10): the near half for the melee, the far half for the shooters.
		for i = 0, 7 do
			local angle = math.rad(i * 45 + 22.5)
			local p = v(math.sin(angle) * 10, bossZ - math.cos(angle) * 10)
			table.insert(if p.Z < bossZ then melee else ranged, p)
		end
		-- The outer ring (radius 18) for bigger waves.
		for i = 0, 11 do
			local angle = math.rad(i * 30 + 15)
			local p = v(math.sin(angle) * 18, bossZ - math.cos(angle) * 18)
			table.insert(if p.Z < bossZ then melee else ranged, p)
		end
		return { melee = melee, ranged = ranged, boss = { v(0, bossZ) } }
	end,
	scatter = function()
		local all = grid(6, 11, { 10, 20, 30 })
		return { melee = all, ranged = all, boss = all }
	end,
}

Formations.Names = { "line", "wedge", "shieldwall", "pincer", "bossCourt", "scatter" }

-- Pushes spots that ended up too close apart (a few passes), keeping them inside the clamp box.
local function separate(points: { Vector3 }, minX: number, maxX: number, minZ: number, maxZ: number)
	for _ = 1, 6 do
		local moved = false
		for i = 2, #points do
			for j = 1, i - 1 do
				local delta = points[i] - points[j]
				local d = delta.Magnitude
				if d < Formations.MinGap then
					local dir = if d > 0.01 then delta / d else Vector3.new(1, 0, 0)
					local p = points[i] + dir * (Formations.MinGap - d + 0.2)
					points[i] = Vector3.new(math.clamp(p.X, minX, maxX), p.Y, math.clamp(p.Z, minZ, maxZ))
					moved = true
				end
			end
		end
		if not moved then
			break
		end
	end
end

-- World positions (y = center.Y, the arena floor) for every role in `roles`, in the same order.
function Formations.spots(name: string, roles: { string }, center: Vector3): { Vector3 }
	local fighters = 0
	for _, role in roles do
		if role ~= "totem" and role ~= "treasure" then
			fighters += 1
		end
	end
	local make = LAYOUTS[name] or LAYOUTS.line
	if fighters >= Formations.ScatterFrom then
		make = LAYOUTS.scatter -- never a 4th row of the plain grid: it would stand off the platform
	end
	local slots = make()
	local used: { [string]: boolean } = {} -- offsets already handed out (keyed by "x|z": the layouts share slots)
	local cursor: { [string]: number } = { melee = 1, ranged = 1, boss = 1, heavy = 1, overflow = 1 }

	local function take(list: { Vector3 }, key: string): Vector3?
		while cursor[key] <= #list do
			local p = list[cursor[key]]
			cursor[key] += 1
			local id = string.format("%.1f|%.1f", p.X, p.Z)
			if not used[id] then
				used[id] = true
				return p
			end
		end
		return nil
	end
	local function pick(role: string): Vector3
		local order: { { any } }
		if role == "boss" then
			order = { { slots.boss, "boss" }, { slots.heavy or slots.melee, if slots.heavy then "heavy" else "melee" }, { slots.melee, "melee" } }
		elseif role == "heavy" then
			order = { { slots.heavy or slots.melee, if slots.heavy then "heavy" else "melee" }, { slots.melee, "melee" }, { slots.ranged, "ranged" } }
		elseif role == "ranged" then
			order = { { slots.ranged, "ranged" }, { slots.melee, "melee" } }
		else
			order = { { slots.melee, "melee" }, { slots.ranged, "ranged" } }
		end
		for _, entry in order do
			local p = take(entry[1], entry[2])
			if p then
				return p
			end
		end
		return take(OVERFLOW, "overflow") or v(0, 30)
	end

	local offsets: { Vector3 } = {}
	local totems = 0
	-- Bosses and heavies first (they own the key slots), then the rest in list order.
	for pass = 1, 2 do
		for i, role in roles do
			local keyRole = role == "boss" or role == "heavy"
			if (pass == 1) == keyRole then
				if role == "totem" then
					totems += 1
					offsets[i] = Formations.Totems[math.min(totems, #Formations.Totems)]
				elseif role == "treasure" then
					offsets[i] = Formations.Treasure
				else
					offsets[i] = pick(role)
				end
			end
		end
	end

	local minX, maxX = -Formations.ClampX, Formations.ClampX
	local minZ, maxZ = Formations.ClampZMin, Formations.ClampZMax
	for i, p in offsets do
		offsets[i] = Vector3.new(math.clamp(p.X, minX, maxX), 0, math.clamp(p.Z, minZ, maxZ))
	end
	separate(offsets, minX, maxX, minZ, maxZ)

	local result: { Vector3 } = {}
	for i, p in offsets do
		result[i] = Vector3.new(center.X + p.X, center.Y, center.Z + p.Z)
	end
	return result
end

return Formations
