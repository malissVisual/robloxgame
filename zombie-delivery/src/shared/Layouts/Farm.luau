--!strict
-- 7.x, the moves' first chapter ("Hold Your Horses", design/rework/PRIBEH.md): Walt's farm, an alpine farm (a Bauernhof)
-- as a plan of shared/HouseLayout.luau's kind "farm" (HouseLayout.plan(seed, "farm") comes here). Pure and
-- deterministic like a house: the same seed, the same farm, on every server; it makes no instances.
-- server/HouseInterior.luau builds it (its farm block: the barn's timber, the yard, the barn doors).
--
-- Two buildings in one interior. The farmhouse in front: the mud room, a hall straight through it from the front door
-- to the back door; the Stube (the living room, its tiled stove in the corner) and the kitchen (its tiled range) on one
-- side, the bedroom and the pantry on the other. Behind it the yard, open to the sky and fenced. Across the yard the
-- barn: the stable with its horse stalls (the hay loft over them), the threshing floor with the wide barn doors in its
-- back wall, the workshop with the forge. Mirrored left to right, the stable and the workshop swapped, the rooms' sizes
-- and the doorways moved by the dice.
--
--   Farm.plan(seed)          the plan: HouseLayout's Plan, kind "farm" (every position local to the farmhouse's front
--                            door, +Z into it, +Y up), its fields as a house's, plus
--     exits                  every way out, in order: the inside of each doorway to the outside at
--                            Config.Furniture.EntryUp over the floor. exits[1] == exit (the farmhouse's front door,
--                            doors[1]); exits[2] the barn doors (Config.Furniture.Farm.BarnDoor wide, in the threshing
--                            floor's back wall), where the big things leave. The doors whose rooms[2] is "outside" are
--                            the exits' doorways, in the same order.
--   Farm.exitsFor(plan, id)  the exits (indexes into plan.exits) a piece can be carried out of: all of them, but for a
--                            FurnitureLooks bigDoor piece (wider than a house's doorway: the hay wagon) only the
--                            doorways wide enough for it (the barn doors). A move routes such a piece there.
--   Farm.stuck(plan)         the spots whose piece cannot be carried out of any exit it may use (with every other piece
--                            in place); empty for every plan it makes (it checks this while it lays the pieces out)
--   Farm.Recipes             what each room holds (HouseLayout's Entry: item, how, ref, must, star, odds)
--   Farm.Rooms               the rooms in the order they are furnished (the spots are numbered so)
--
-- The rooms (id: kind): mudroom: hall, stube: living, kitchen: kitchen, bedroom: bedroom, pantry: pantry (the
-- farmhouse, Config.Furniture.Ceiling high); yard: yard (open to the sky: max.Y is its fences' height); stable: stable,
-- barn: barn (the threshing floor), workshop: workshop (Farm.BarnCeiling high). A wall two rooms share is two faces
-- (each room's half, as high as the taller room), so the yard's side of the farmhouse's back wall is the yard's face.
-- The fixtures (at, size and turn as in a house; a wall's fixture stands against it): tiled_stove (the kitchen's
-- range), kachelofen (the Stube's tiled stove with its bench), counter, sink, larder (the pantry's shelves), mat, rug,
-- runner, stall (a stall's straw and its horse's name board: not solid), stall_wall (a partition), manger, hay_loft (the
-- loft's floor over the stable, Farm.Loft up: decor), beam (a tie beam across a barn room, its underside Farm.Beam up),
-- lantern (a hanging light: `at` its bottom, size.Y up to what it hangs from), workbench, forge, trough, woodpile and
-- barn_doors (at the doorway's middle on the wall's centre line, its front into the barn: the doors open out onto an
-- apron with the daylight beyond, like the front door's porch).

local Config = require(script.Parent.Parent.Config)
local FurnitureLooks = require(script.Parent.Parent.FurnitureLooks)

local T = Config.Furniture
local F = T.Farm
local Farm = {}

export type Axis = "X" | "Z"
export type Room = { id: string, kind: string, min: Vector3, max: Vector3 }
export type Door = { at: Vector3, width: number, axis: Axis, rooms: { string }, front: boolean }
export type Spot = { id: number, item: string, room: string, at: CFrame, star: boolean, turn: number, variant: number }
export type Face = { room: string, min: Vector3, max: Vector3, normal: Vector3, outer: boolean, header: boolean }
export type Window = { room: string, at: Vector3, width: number, height: number, normal: Vector3 }
export type Fixture = { kind: string, room: string, at: CFrame, size: Vector3, turn: number, solid: boolean }
export type Plan = {
	kind: string,
	seed: number,
	mirrored: boolean,
	size: Vector3,
	min: Vector3,
	max: Vector3,
	rooms: { Room },
	doors: { Door },
	entry: CFrame,
	exit: Vector3,
	exits: { Vector3 },
	spots: { Spot },
	ceiling: number,
	wall: number,
	doorHeight: number,
	faces: { Face },
	windows: { Window },
	fixtures: { Fixture },
}
export type Entry = { item: string, how: string, ref: string?, must: boolean?, star: boolean?, odds: number? }

local HALF = T.Wall / 2

-- ── Small things (as shared/HouseLayout.luau's) ─────────────────────────────────────

type Rng = { num: () -> number, int: (number, number) -> number }

local function mul32(a: number, b: number): number
	local hi, lo = a // 65536, a % 65536
	return ((hi * b) % 65536 * 65536 + lo * b) % 4294967296
end

local function hash(x: number): number
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x7feb352d)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = mul32(x, 0x846ca68b)
	return bit32.bxor(x, bit32.rshift(x, 16))
end

-- The dice: Park-Miller after the hash (exact in doubles); the farm's own stream (salted, not a house's).
local function newRng(seed: number): Rng
	local s = math.floor(math.abs(seed)) % 4294967296
	local state = hash(bit32.bxor(s, 0x5eed7a12)) % 2147483646 + 1
	local function num(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	for _ = 1, 4 do
		num()
	end
	local function int(a: number, b: number): number
		return a + math.floor(num() * (b - a + 1))
	end
	return { num = num, int = int }
end

local function shuffle<V>(list: { V }, rng: Rng)
	for i = #list, 2, -1 do
		local j = rng.int(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

type Rect = { x0: number, z0: number, x1: number, z1: number }

local function rect(x0: number, z0: number, x1: number, z1: number): Rect
	return { x0 = math.min(x0, x1), z0 = math.min(z0, z1), x1 = math.max(x0, x1), z1 = math.max(z0, z1) }
end

local function hits(a: Rect, b: Rect, gap: number): boolean
	return a.x0 < b.x1 + gap and b.x0 < a.x1 + gap and a.z0 < b.z1 + gap and b.z0 < a.z1 + gap
end

local function within(a: Rect, b: Rect): boolean
	return a.x0 >= b.x0 - 1e-6 and a.z0 >= b.z0 - 1e-6 and a.x1 <= b.x1 + 1e-6 and a.z1 <= b.z1 + 1e-6
end

local function distTo(x: number, z: number, r: Rect): number
	local dx = math.max(r.x0 - x, 0, x - r.x1)
	local dz = math.max(r.z0 - z, 0, z - r.z1)
	return math.sqrt(dx * dx + dz * dz)
end

local function norm(turn: number): number
	return (turn % 360 + 360) % 360
end

-- A piece's footprint turned by `turn` degrees: (along X, along Z).
local function extent(id: string, turn: number): (number, number)
	local def = FurnitureLooks.Items[id] or FurnitureLooks.Items.box
	if norm(turn) % 180 == 0 then
		return def.size.X, def.size.Z
	end
	return def.size.Z, def.size.X
end

-- The radius a piece needs carried end first (half its narrow side).
local function radiusOf(id: string): number
	local def = FurnitureLooks.Items[id] or FurnitureLooks.Items.box
	return math.min(def.size.X, def.size.Z) / 2
end

-- ── Reachability ──────────────────────────────────────────────────────────────
-- As a house's (shared/HouseLayout.luau), with more than one way out: on a grid of Config.Furniture.Grid studs, every
-- point's clearance to the walls and the solid fixtures; the widest way in from any exit (a bottleneck fill from all
-- their doorways at once); from each piece a flood over the points clear for it (every other piece still in place)
-- until it meets that way at its width. The hay wagon needs 3.2 of clearance: CAP is above it.

local CAP = 5
local STEP = 0.05

type Field = { x0: number, z0: number, nx: number, nz: number, step: number, static: { number }, doors: { Rect } }

local function spanOf(field: Field, r: Rect, pad: number): (number, number, number, number)
	local step, x0, z0 = field.step, field.x0, field.z0
	return math.max(0, math.floor((r.x0 - pad - x0) / step)), math.min(field.nx - 1, math.ceil((r.x1 + pad - x0) / step)),
		math.max(0, math.floor((r.z0 - pad - z0) / step)), math.min(field.nz - 1, math.ceil((r.z1 + pad - z0) / step))
end

local function newField(box: Rect, walls: { Rect }, doors: { Rect }): Field
	local step = T.Grid
	local x0, z0 = math.floor(box.x0 / step) * step, math.floor(box.z0 / step) * step
	local nx = math.floor((box.x1 - x0) / step) + 1
	local nz = math.floor((box.z1 - z0) / step) + 1
	local field: Field = { x0 = x0, z0 = z0, nx = nx, nz = nz, step = step, static = table.create(nx * nz, CAP), doors = doors }
	local static = field.static
	for _, r in walls do
		local i0, i1, j0, j1 = spanOf(field, r, CAP)
		for j = j0, j1 do
			local z = z0 + j * step
			for i = i0, i1 do
				local d = distTo(x0 + i * step, z, r)
				local k = j * nx + i + 1
				if d < static[k] then
					static[k] = d
				end
			end
		end
	end
	return field
end

-- The widest way in from the exits: best[k] the widest disc (in STEP levels) from a doorway to point k.
local function wayIn(field: Field, clear: { number }): { number }
	local nx, nz, step, x0, z0 = field.nx, field.nz, field.step, field.x0, field.z0
	local levels = math.floor(CAP / STEP)
	local best = table.create(nx * nz, -1)
	local buckets: { { number } } = {}
	for level = 0, levels do
		buckets[level + 1] = {}
	end
	for _, door in field.doors do
		local i0, i1, j0, j1 = spanOf(field, door, 0)
		for j = j0, j1 do
			local z = z0 + j * step
			for i = i0, i1 do
				local x = x0 + i * step
				if x >= door.x0 - 1e-6 and x <= door.x1 + 1e-6 and z >= door.z0 - 1e-6 and z <= door.z1 + 1e-6 then
					local k = j * nx + i + 1
					local level = math.min(levels, math.floor(clear[k] / STEP))
					if level > best[k] then
						best[k] = level
						table.insert(buckets[level + 1], k)
					end
				end
			end
		end
	end
	for level = levels, 0, -1 do
		local bucket = buckets[level + 1]
		local n = 1
		while n <= #bucket do
			local k = bucket[n]
			n += 1
			if best[k] ~= level then
				continue
			end
			local i, j = (k - 1) % nx, (k - 1) // nx
			for side = 1, 4 do
				local ni = if side == 1 then i - 1 elseif side == 2 then i + 1 else i
				local nj = if side == 3 then j - 1 elseif side == 4 then j + 1 else j
				if ni >= 0 and ni < nx and nj >= 0 and nj < nz then
					local nk = nj * nx + ni + 1
					local v = math.min(level, math.floor(clear[nk] / STEP))
					if v > best[nk] then
						best[nk] = v
						table.insert(buckets[v + 1], nk)
					end
				end
			end
		end
		buckets[level + 1] = {}
	end
	return best
end

-- Which of `pieces` (footprints, each with the radius it needs) cannot get out: their indexes.
local function stuckOf(field: Field, pieces: { Rect }, radii: { number }): { number }
	local nx, nz, step, x0, z0 = field.nx, field.nz, field.step, field.x0, field.z0
	local static = field.static
	local count = nx * nz
	-- per point: the nearest piece (its distance and index) and the next nearest
	local near1, near1i, near2 = table.create(count, CAP), table.create(count, 0), table.create(count, CAP)
	for index, r in pieces do
		local i0, i1, j0, j1 = spanOf(field, r, CAP)
		for j = j0, j1 do
			local z = z0 + j * step
			for i = i0, i1 do
				local d = distTo(x0 + i * step, z, r)
				local k = j * nx + i + 1
				if d < near1[k] then
					near2[k], near1[k], near1i[k] = near1[k], d, index
				elseif d < near2[k] then
					near2[k] = d
				end
			end
		end
	end
	local clear = table.create(count, 0)
	for k = 1, count do
		clear[k] = math.min(static[k], near1[k])
	end
	local best = wayIn(field, clear)
	local stuck: { number } = {}
	for index, own in pieces do
		local radius = radii[index]
		local need = math.ceil(radius / STEP - 1e-9)
		local function clearFor(k: number): boolean
			return static[k] >= radius and (if near1i[k] == index then near2[k] else near1[k]) >= radius
		end
		local seen: { [number]: boolean } = {}
		local queue: { number } = {}
		local i0, i1, j0, j1 = spanOf(field, own, 0)
		local ci = math.clamp(math.floor(((own.x0 + own.x1) / 2 - x0) / step + 0.5), 0, nx - 1)
		local cj = math.clamp(math.floor(((own.z0 + own.z1) / 2 - z0) / step + 0.5), 0, nz - 1)
		local starts = { cj * nx + ci + 1 }
		for j = j0, j1 do
			for i = i0, i1 do
				local x, z = x0 + i * step, z0 + j * step
				if x >= own.x0 - 1e-6 and x <= own.x1 + 1e-6 and z >= own.z0 - 1e-6 and z <= own.z1 + 1e-6 then
					table.insert(starts, j * nx + i + 1)
				end
			end
		end
		for _, k in starts do
			if not seen[k] then
				seen[k] = true
				if clearFor(k) then
					table.insert(queue, k)
				end
			end
		end
		local out = false
		local n = 1
		while n <= #queue do
			local k = queue[n]
			n += 1
			if best[k] >= need then
				out = true
				break
			end
			local i, j = (k - 1) % nx, (k - 1) // nx
			for side = 1, 4 do
				local ni = if side == 1 then i - 1 elseif side == 2 then i + 1 else i
				local nj = if side == 3 then j - 1 elseif side == 4 then j + 1 else j
				if ni >= 0 and ni < nx and nj >= 0 and nj < nz then
					local nk = nj * nx + ni + 1
					if not seen[nk] then
						seen[nk] = true
						if clearFor(nk) then
							table.insert(queue, nk)
						end
					end
				end
			end
		end
		if not out then
			table.insert(stuck, index)
		end
	end
	return stuck
end

-- ── The rooms' contents ─────────────────────────────────────────────────────────
-- how: as a house's (shared/HouseLayout.luau): "far", "centre", "wall", "corner", "facing", "front", "beside", "middle",
-- "around"; and "open" (free-standing with a way all round, its front to the room's back wall: the hay wagon); must:
-- always there; star: one of the ★ candidates (Stars of them by the dice); odds: how likely an optional
-- piece comes before the others.

local RECIPES: { [string]: { Entry } } = {
	mudroom = {
		{ item = "coat_rack", how = "corner", must = true },
		{ item = "milk_churn", how = "corner", odds = 1.5 },
		{ item = "shoe_cabinet", how = "wall" },
		{ item = "ski_bundle", how = "corner", odds = 2 }, -- (7.x alpine pieces: the old wooden skis)
	},
	stube = {
		-- the bench along a wall and the table in front of it (the alpine Stube's corner), the chairs across
		{ item = "farm_bench", how = "wall", must = true },
		{ item = "dining_table", how = "front", ref = "farm_bench", must = true },
		{ item = "dining_chair", how = "around", ref = "dining_table", must = true },
		{ item = "dining_chair", how = "around", ref = "dining_table" },
		{ item = "cowbells", how = "wall", star = true },
		{ item = "guitar", how = "corner", odds = 2 },
		{ item = "armchair", how = "wall", odds = 1.5 },
		{ item = "radio", how = "wall" },
		{ item = "painting", how = "wall" },
		{ item = "heart_chair", how = "wall", odds = 2 }, -- (7.x alpine pieces: the carved chair, the crate of steins)
		{ item = "stein_crate", how = "corner", odds = 1.5 },
	},
	kitchen = {
		{ item = "butter_churn", how = "corner", must = true },
		{ item = "grandmas_churn", how = "corner", star = true },
		{ item = "dishes_box", how = "wall", odds = 1.5 },
		{ item = "dining_chair", how = "wall" },
		{ item = "fridge", how = "corner" },
	},
	bedroom = {
		{ item = "bed", how = "far", must = true },
		{ item = "nightstand", how = "beside", ref = "bed", must = true },
		{ item = "wardrobe", how = "wall", must = true },
		{ item = "dresser", how = "wall", odds = 1.5 },
		{ item = "mirror", how = "corner" },
		{ item = "painted_cupboard", how = "wall", odds = 2 }, -- (7.x alpine pieces: the painted farmhouse cupboard)
	},
	pantry = {
		{ item = "cheese_crate", how = "wall", must = true },
		{ item = "apple_crate", how = "corner", odds = 2 },
		{ item = "apple_crate", how = "corner" },
		{ item = "milk_churn", how = "corner" },
	},
	yard = {
		{ item = "wheelbarrow", how = "wall", must = true },
		{ item = "beehive", how = "wall", odds = 2 },
		{ item = "beehive", how = "wall" },
		{ item = "sled", how = "wall" },
	},
	stable = {
		{ item = "tack_rack", how = "wall", must = true },
		{ item = "saddle", how = "wall", must = true },
		{ item = "thunders_saddle", how = "wall", star = true },
		{ item = "saddle", how = "wall", odds = 1.5 },
		{ item = "hay_bale", how = "corner", odds = 2 },
		{ item = "feed_sacks", how = "wall", odds = 2 },
		{ item = "hay_bale", how = "corner" },
		{ item = "feed_sacks", how = "corner" },
	},
	barn = {
		{ item = "hay_wagon", how = "open", must = true },
		{ item = "hay_bale", how = "corner", must = true },
		{ item = "hay_bale", how = "corner", odds = 2 },
		{ item = "ladder", how = "wall", odds = 1.5 },
		{ item = "hay_bale", how = "wall" },
		{ item = "sled", how = "wall" },
		{ item = "feed_sacks", how = "wall" },
	},
	workshop = {
		{ item = "anvil", how = "wall", must = true },
		{ item = "tool_chest", how = "wall", must = true },
		{ item = "branding_iron", how = "wall", star = true },
		{ item = "toolbox", how = "wall", odds = 1.5 },
		{ item = "ladder", how = "wall" },
		{ item = "box", how = "corner" },
	},
}
Farm.Recipes = RECIPES
local FURNISH = { "stube", "kitchen", "bedroom", "pantry", "mudroom", "yard", "stable", "barn", "workshop" }
Farm.Rooms = FURNISH
-- where a filler box goes when the farm is short of pieces
local FILLER = { "workshop", "pantry", "barn", "stable", "mudroom", "kitchen" }

-- ── A farm ─────────────────────────────────────────────────────────────────────

type RoomData = { id: string, kind: string, cell: Rect, inner: Rect, top: number }
type DoorData = { x: number, z: number, width: number, alongX: boolean, a: string, b: string?, height: number }
type FixtureData = { kind: string, room: string, x: number, y: number, z: number, w: number, h: number, d: number, turn: number, solid: boolean, rect: Rect }
type WindowData = { room: string, side: string, t: number, y: number, width: number, height: number }
type Placed = {
	item: string,
	room: string,
	x: number,
	z: number,
	turn: number,
	rect: Rect,
	side: string?,
	t: number?,
	must: boolean,
	star: boolean,
	order: number,
	variant: number,
	entry: Entry,
}
type Cand = { x: number, z: number, turn: number, rect: Rect, side: string?, t: number?, score: number }
type State = {
	rng: Rng,
	rooms: { RoomData },
	byId: { [string]: RoomData },
	doors: { DoorData },
	fixtures: { FixtureData },
	windows: { WindowData },
	faces: { Face },
	walls: { Rect },
	zones: { [string]: { Rect } },
	windowZones: { [string]: { Rect } },
	placed: { Placed },
	banned: { [string]: { Rect } },
	placing: string,
	counter: number,
	mirrored: boolean,
	box: Rect,
}

-- A side of a room: the wall at its min Z ("S"), max Z ("N"), min X ("W"), max X ("E"); a piece with its back to it
-- turns `turn` degrees and faces (fx, fz) into the room.
local SIDE_TURN: { [string]: number } = { S = 180, N = 0, W = 270, E = 90 }
local SIDE_FACE: { [string]: { number } } = { S = { 0, 1 }, N = { 0, -1 }, W = { 1, 0 }, E = { -1, 0 } }
local OPPOSITE: { [string]: string } = { S = "N", N = "S", W = "E", E = "W" }
local SIDES = { "S", "N", "W", "E" }

local function against(inner: Rect, side: string, t: number, w: number, d: number, gap: number): (number, number, Rect)
	if side == "S" then
		return t, inner.z0 + gap + d / 2, rect(t - w / 2, inner.z0 + gap, t + w / 2, inner.z0 + gap + d)
	elseif side == "N" then
		return t, inner.z1 - gap - d / 2, rect(t - w / 2, inner.z1 - gap - d, t + w / 2, inner.z1 - gap)
	elseif side == "W" then
		return inner.x0 + gap + d / 2, t, rect(inner.x0 + gap, t - w / 2, inner.x0 + gap + d, t + w / 2)
	end
	return inner.x1 - gap - d / 2, t, rect(inner.x1 - gap - d, t - w / 2, inner.x1 - gap, t + w / 2)
end

local function span(r: Rect, side: string): (number, number)
	if side == "S" or side == "N" then
		return r.x0, r.x1
	end
	return r.z0, r.z1
end

local function lineOf(r: Rect, side: string): number
	return if side == "S" then r.z0 elseif side == "N" then r.z1 elseif side == "W" then r.x0 else r.x1
end

-- A doorway's middle along a stretch from a to b: a whole stud at least `margin` past its ends (their middle if none).
local function doorIn(rng: Rng, a: number, b: number, width: number, margin: number?): number
	local lo = math.ceil(a + width / 2 + (margin or 1.5))
	local hi = math.floor(b - width / 2 - (margin or 1.5))
	if lo > hi then
		return (a + b) / 2
	end
	return rng.int(lo, hi)
end

-- The two buildings and the yard: the rooms' cells (their walls' middles) and the doorways, then maybe mirrored.
local function shell(S: State)
	local rng = S.rng
	local half = F.Hall / 2
	local W2 = rng.int(F.HouseWidth[1] // 2, F.HouseWidth[2] // 2)
	local depth = rng.int(F.HouseDepth[1], F.HouseDepth[2])
	local stubeDepth = depth - rng.int(F.Kitchen[1], F.Kitchen[2])
	local bedDepth = depth - rng.int(F.Pantry[1], F.Pantry[2])
	local yardEnd = depth + rng.int(F.Yard[1], F.Yard[2])
	local barnEnd = yardEnd + rng.int(F.BarnDepth[1], F.BarnDepth[2])
	local threshing = 2 * rng.int(F.Threshing[1] // 2, F.Threshing[2] // 2)
	local stableW = rng.int(F.Stable[1], F.Stable[2])
	local workshopW = rng.int(F.Workshop[1], F.Workshop[2])
	local centre = rng.int(-2, 2)
	local stableLeft = rng.num() < 0.5
	local t0, t1 = centre - threshing / 2, centre + threshing / 2
	-- the barn reaches past the yard on both sides (the yard's fences end at its front wall)
	local leftW = math.max(if stableLeft then stableW else workshopW, t0 + W2)
	local rightW = math.max(if stableLeft then workshopW else stableW, W2 - t1)
	local function add(id: string, kind: string, cell: Rect, top: number)
		local room: RoomData = { id = id, kind = kind, cell = cell, inner = cell, top = top }
		table.insert(S.rooms, room)
		S.byId[id] = room
	end
	add("mudroom", "hall", rect(-half, 0, half, depth), T.Ceiling)
	add("stube", "living", rect(-W2, 0, -half, stubeDepth), T.Ceiling)
	add("kitchen", "kitchen", rect(-W2, stubeDepth, -half, depth), T.Ceiling)
	add("bedroom", "bedroom", rect(half, 0, W2, bedDepth), T.Ceiling)
	add("pantry", "pantry", rect(half, bedDepth, W2, depth), T.Ceiling)
	add("yard", "yard", rect(-W2, depth, W2, yardEnd), F.Fence)
	local left, right = if stableLeft then "stable" else "workshop", if stableLeft then "workshop" else "stable"
	add(left, left, rect(t0 - leftW, yardEnd, t0, barnEnd), F.BarnCeiling)
	add("barn", "barn", rect(t0, yardEnd, t1, barnEnd), F.BarnCeiling)
	add(right, right, rect(t1, yardEnd, t1 + rightW, barnEnd), F.BarnCeiling)

	local function door(x: number, z: number, width: number, alongX: boolean, a: string, b: string?, height: number?)
		table.insert(S.doors, { x = x, z = z, width = width, alongX = alongX, a = a, b = b, height = height or T.DoorHeight })
	end
	local D, O = T.Door, F.BarnOpening
	door(0, 0, T.FrontDoor, true, "mudroom", nil) -- doors[1]: the front door
	door(-half, doorIn(rng, 0, stubeDepth, D), D, false, "mudroom", "stube")
	door(-half, doorIn(rng, stubeDepth, depth, D), D, false, "mudroom", "kitchen")
	door(half, doorIn(rng, 0, bedDepth, D), D, false, "mudroom", "bedroom")
	door(half, doorIn(rng, bedDepth, depth, D), D, false, "mudroom", "pantry")
	-- the Stube to the kitchen: by the hall, clear of the tiled stove in the Stube's outer corner
	local lo, hi = math.ceil(-W2 + F.StoveClear), math.floor(-half - D / 2 - 1.5)
	door(if lo <= hi then rng.int(lo, hi) else (lo + hi) / 2, stubeDepth, D, true, "stube", "kitchen")
	door(0, depth, F.BackDoor, true, "mudroom", "yard")
	door(doorIn(rng, math.max(-W2, t0), math.min(W2, t1), O), yardEnd, O, true, "yard", "barn")
	-- the barn doors: the second exit, in the threshing floor's back wall
	door(doorIn(rng, t0, t1, F.BarnDoor), barnEnd, F.BarnDoor, true, "barn", nil, F.BarnDoorHeight)
	-- the stable and the workshop off the threshing floor, near its front (the stalls and the workbench are at the
	-- back; the hay wagon stands at the back of the threshing floor, by the barn doors)
	door(t0, doorIn(rng, yardEnd, yardEnd + O + 6, O), O, false, left, "barn")
	door(t1, doorIn(rng, yardEnd, yardEnd + O + 6, O), O, false, right, "barn")

	-- the mirror (left and right swapped)
	S.mirrored = rng.num() < 0.5
	if S.mirrored then
		for _, room in S.rooms do
			room.cell = rect(-room.cell.x1, room.cell.z0, -room.cell.x0, room.cell.z1)
		end
		for _, d in S.doors do
			d.x = -d.x
		end
	end
	local box: Rect? = nil
	for _, room in S.rooms do
		local c = room.cell
		room.inner = rect(c.x0 + HALF, c.z0 + HALF, c.x1 - HALF, c.z1 - HALF)
		box = if box then rect(math.min(box.x0, c.x0), math.min(box.z0, c.z0), math.max(box.x1, c.x1), math.max(box.z1, c.z1)) else c
	end
	local b = box :: Rect
	S.box = rect(b.x0 - HALF, b.z0 - HALF, b.x1 + HALF, b.z1 + HALF)
end

-- The stretches of a room's side other rooms share: { from, to, their top } in order.
local function sharedOf(S: State, room: RoomData, side: string): { { number } }
	local line = lineOf(room.cell, side)
	local a, b = span(room.cell, side)
	local opposite = OPPOSITE[side]
	local out: { { number } } = {}
	for _, other in S.rooms do
		if other ~= room and math.abs(lineOf(other.cell, opposite) - line) < 1e-6 then
			local oa, ob = span(other.cell, opposite)
			local from, to = math.max(a, oa), math.min(b, ob)
			if to > from + 1e-6 then
				table.insert(out, { from, to, other.top })
			end
		end
	end
	table.sort(out, function(p: { number }, q: { number }): boolean
		return p[1] < q[1]
	end)
	-- one stretch where neighbours of the same height meet (the yard's side of the farmhouse is one wall)
	local merged: { { number } } = {}
	for _, s in out do
		local last = merged[#merged]
		if last and math.abs(last[2] - s[1]) < 1e-6 and last[3] == s[3] then
			last[2] = s[2]
		else
			table.insert(merged, table.clone(s))
		end
	end
	return merged
end

-- The doorways in a side of a room: { from, to, height } along it.
local function openings(S: State, room: RoomData, side: string): { { number } }
	local line = lineOf(room.cell, side)
	local alongX = side == "S" or side == "N"
	local out: { { number } } = {}
	for _, d in S.doors do
		if d.alongX == alongX and (d.a == room.id or d.b == room.id) then
			local at = if alongX then d.z else d.x
			local t = if alongX then d.x else d.z
			if math.abs(at - line) < 1e-6 then
				table.insert(out, { t - d.width / 2, t + d.width / 2, d.height })
			end
		end
	end
	table.sort(out, function(p: { number }, q: { number }): boolean
		return p[1] < q[1]
	end)
	return out
end

type Stretch = { from: number, to: number, shared: boolean, top: number }

-- The walls: every room side as slabs, cut at its doorways (the wall over each its header). A stretch another room
-- shares is this room's half of the wall (as high as the taller room); an outer stretch is the whole wall, run on over
-- the building's corner on the S and N sides.
local function walls(S: State)
	for _, room in S.rooms do
		local c = room.cell
		local shared: { [string]: { { number } } } = {}
		for _, side in SIDES do
			shared[side] = sharedOf(S, room, side)
		end
		-- is the side `side` shared at `t` along it (a corner's end)?
		local function sharedAt(side: string, t: number): boolean
			for _, s in shared[side] do
				if t >= s[1] - 1e-6 and t <= s[2] + 1e-6 then
					return true
				end
			end
			return false
		end
		for _, side in SIDES do
			local alongX = side == "S" or side == "N"
			local line = lineOf(c, side)
			local a, b = span(c, side)
			local inward = if side == "S" or side == "W" then 1 else -1
			local normal = Vector3.new(if alongX then 0 else inward, 0, if alongX then inward else 0)
			local stretches: { Stretch } = {}
			local at = a
			for _, s in shared[side] do
				if s[1] > at + 1e-6 then
					table.insert(stretches, { from = at, to = s[1], shared = false, top = room.top })
				end
				table.insert(stretches, { from = s[1], to = s[2], shared = true, top = math.max(room.top, s[3]) })
				at = s[2]
			end
			if b > at + 1e-6 then
				table.insert(stretches, { from = at, to = b, shared = false, top = room.top })
			end
			local gaps = openings(S, room, side)
			for _, st in stretches do
				local from, to, isShared, top = st.from, st.to, st.shared, st.top
				local p0, p1 = if isShared then line else line - HALF, if isShared then line + inward * HALF else line + HALF
				local s0, s1 = from, to
				if not isShared and alongX then
					local edge = if side == "S" then c.z0 else c.z1
					if math.abs(from - a) < 1e-6 and not sharedAt("W", edge) then
						s0 -= HALF
					end
					if math.abs(to - b) < 1e-6 and not sharedAt("E", edge) then
						s1 += HALF
					end
				end
				local function slab(u0: number, u1: number, y0: number, y1: number, header: boolean)
					local r = if alongX then rect(u0, p0, u1, p1) else rect(p0, u0, p1, u1)
					table.insert(S.faces, {
						room = room.id,
						min = Vector3.new(r.x0, y0, r.z0),
						max = Vector3.new(r.x1, y1, r.z1),
						normal = normal,
						outer = not isShared,
						header = header,
					})
					if not header then
						table.insert(S.walls, r)
					end
				end
				local cur = s0
				for _, g in gaps do
					if g[2] <= from + 1e-6 or g[1] >= to - 1e-6 then
						continue
					end
					if g[1] > cur + 1e-6 then
						slab(cur, g[1], 0, top, false)
					end
					if g[3] < top then
						slab(g[1], g[2], g[3], top, true)
					end
					cur = g[2]
				end
				if s1 > cur + 1e-6 then
					slab(cur, s1, 0, top, false)
				end
			end
		end
	end
end

-- A fixture against a wall (`at` its bottom middle `y` up, the front into the room) or standing free.
local function fixture(S: State, kind: string, roomId: string, side: string, t: number, w: number, h: number, d: number, y: number, solid: boolean)
	local room = S.byId[roomId]
	local x, z, r = against(room.inner, side, t, w, d, 0)
	table.insert(S.fixtures, { kind = kind, room = roomId, x = x, y = y, z = z, w = w, h = h, d = d, turn = SIDE_TURN[side], solid = solid, rect = r })
end
local function freeFixture(S: State, kind: string, roomId: string, x: number, y: number, z: number, w: number, h: number, d: number, turn: number, solid: boolean)
	local ex, ez = if norm(turn) % 180 == 0 then w else d, if norm(turn) % 180 == 0 then d else w
	table.insert(S.fixtures, { kind = kind, room = roomId, x = x, y = y, z = z, w = w, h = h, d = d, turn = turn, solid = solid, rect = rect(x - ex / 2, z - ez / 2, x + ex / 2, z + ez / 2) })
end
local function window(S: State, roomId: string, side: string, t: number, size: { number }, sill: number)
	table.insert(S.windows, { room = roomId, side = side, t = t, y = sill + size[2] / 2, width = size[1], height = size[2] })
end

-- The side of a room away from x = 0 (a farmhouse room's outer side wall), or away from the threshing floor (a barn
-- room's end wall).
local function outerSide(S: State, room: RoomData, from: number): string
	return if (room.cell.x0 + room.cell.x1) / 2 < from then "W" else "E"
end

-- What stays: the stoves, the kitchen's counter, the pantry's larder, the stalls and the loft, the beams and lanterns,
-- the workbench and the forge, the barn doors, the yard's trough and woodpile; the windows.
local function fixtures(S: State)
	local rng = S.rng
	local by = S.byId
	local barn = by.barn
	local barnMid = (barn.cell.x0 + barn.cell.x1) / 2

	-- the Stube: the tiled stove (a Kachelofen with its bench) in the corner by the kitchen and the outer wall
	do
		local stube = by.stube
		local side = outerSide(S, stube, 0)
		local inner = stube.inner
		local t = if side == "W" then inner.x0 + 2.2 else inner.x1 - 2.2
		fixture(S, "kachelofen", "stube", "N", t, 4.4, 6, 3.6, 0, true)
		local a, b = span(inner, "S")
		window(S, "stube", "S", a + (b - a) / 3, T.Window, T.WindowSill)
		window(S, "stube", "S", a + (b - a) * 2 / 3, T.Window, T.WindowSill)
		local c, d = span(inner, side)
		window(S, "stube", side, (c + d) / 2, T.Window, T.WindowSill)
	end
	-- the kitchen: the tiled range on its outer wall, the counter and the sink under the window to the yard
	do
		local kitchen = by.kitchen
		local side = outerSide(S, kitchen, 0)
		local inner = kitchen.inner
		fixture(S, "tiled_stove", "kitchen", side, inner.z0 + 2.4, 3.2, 3, 2.4, 0, true)
		local dir = if side == "W" then 1 else -1
		local start = if side == "W" then inner.x0 else inner.x1
		fixture(S, "counter", "kitchen", "N", start + dir * 1.5, 3, 3, 2.6, 0, true)
		fixture(S, "sink", "kitchen", "N", start + dir * 4.5, 3, 3, 2.6, 0, true)
		window(S, "kitchen", "N", start + dir * 4.5, T.Window, T.WindowSill)
	end
	-- the bedroom's windows, the pantry's larder (along the yard wall from the outer corner) and its small window
	do
		local bedroom = by.bedroom
		local side = outerSide(S, bedroom, 0)
		local a, b = span(bedroom.inner, "S")
		window(S, "bedroom", "S", (a + b) / 2, T.Window, T.WindowSill)
		local c, d = span(bedroom.inner, side)
		window(S, "bedroom", side, (c + d) / 2, T.Window, T.WindowSill)
		local pantry = by.pantry
		local pside = outerSide(S, pantry, 0)
		local inner = pantry.inner
		local length = math.min(9, inner.x1 - inner.x0 - 5)
		local start = if pside == "W" then inner.x0 + length / 2 else inner.x1 - length / 2
		fixture(S, "larder", "pantry", "N", start, length, 7, 1.6, 0, true)
		local e, f = span(inner, pside)
		window(S, "pantry", pside, (e + f) / 2, T.BathWindow, 6.5)
	end
	-- the mud room: a mat inside the front door, a runner down the hall
	do
		local inner = by.mudroom.inner
		freeFixture(S, "mat", "mudroom", 0, 0, HALF + 1.6, 4.4, 0.08, 2.4, 0, false)
		freeFixture(S, "runner", "mudroom", 0, 0, (inner.z0 + 4 + inner.z1 - 3) / 2, 3.6, 0.08, inner.z1 - inner.z0 - 7, 0, false)
	end
	-- the yard: the water trough on a fence, the woodpile along the farmhouse's wall (clear of the back door)
	do
		local yard = by.yard
		local inner = yard.inner
		local fence = if rng.num() < 0.5 then "W" else "E"
		fixture(S, "trough", "yard", fence, (inner.z0 + inner.z1) / 2, 5, 2.4, 2, 0, true)
		local other = OPPOSITE[fence]
		local length = math.min(8, (inner.x1 - inner.x0) / 2 - F.BackDoor / 2 - 4)
		local t = if other == "W" then inner.x0 + length / 2 + 0.5 else inner.x1 - length / 2 - 0.5
		fixture(S, "woodpile", "yard", "S", t, length, 4.2, 1.8, 0, true)
	end
	-- the stable: the stalls along its back wall from its end wall (straw, a name board, a manger each; partitions
	-- between them), the hay loft over it, a lantern hanging under the loft
	do
		local stable = by.stable
		local inner = stable.inner
		local side = outerSide(S, stable, barnMid)
		local w, d = F.Stall[1], F.Stall[2]
		local dir = if side == "W" then 1 else -1
		local from = if side == "W" then inner.x0 else inner.x1
		for n = 1, F.Stalls do
			local mid = from + dir * (n - 0.5) * w
			fixture(S, "stall", "stable", "N", mid, w, 3, d, 0, false)
			fixture(S, "manger", "stable", "N", mid, 3, 3.4, 1.2, 0, true)
			if n < F.Stalls then
				fixture(S, "stall_wall", "stable", "N", from + dir * n * w, 0.5, F.StallWall, d, 0, true)
			end
		end
		local cx, cz = (inner.x0 + inner.x1) / 2, (inner.z0 + inner.z1) / 2
		freeFixture(S, "hay_loft", "stable", cx, F.Loft, cz, inner.x1 - inner.x0, 0.6, inner.z1 - inner.z0, 0, false)
		local hang = 2.6
		freeFixture(S, "lantern", "stable", cx, F.Loft - hang, (inner.z0 + inner.z1 - d) / 2, 0.9, hang, 0.9, 0, false)
		local a, b = span(inner, side)
		window(S, "stable", side, a + (b - a) * 0.4, F.BarnWindow, F.BarnSill)
	end
	-- the threshing floor: two tie beams with a lantern under each; the barn doors
	do
		local inner = barn.inner
		local cx = (inner.x0 + inner.x1) / 2
		for _, k in { 1 / 3, 2 / 3 } do
			local z = inner.z0 + (inner.z1 - inner.z0) * k
			freeFixture(S, "beam", "barn", cx, F.Beam, z, inner.x1 - inner.x0, 1, 1, 0, false)
			freeFixture(S, "lantern", "barn", cx, F.Beam - 2.4, z, 0.9, 2.4, 0.9, 0, false)
		end
		for _, d in S.doors do
			if d.a == "barn" and d.b == nil then
				freeFixture(S, "barn_doors", "barn", d.x, 0, d.z, d.width, d.height, T.Wall, 0, false)
			end
		end
	end
	-- the workshop: the workbench on its back wall, the forge on its end wall, a tie beam and a lantern, a window
	do
		local shop = by.workshop
		local inner = shop.inner
		local side = outerSide(S, shop, barnMid)
		local from = if side == "W" then inner.x0 else inner.x1
		local dir = if side == "W" then 1 else -1
		fixture(S, "workbench", "workshop", "N", from + dir * 3.6, 6.4, 3.2, 2.4, 0, true)
		fixture(S, "forge", "workshop", side, inner.z1 - 6.5, 4, 3.4, 3, 0, true)
		local cx, cz = (inner.x0 + inner.x1) / 2, (inner.z0 + inner.z1) / 2
		freeFixture(S, "beam", "workshop", cx, F.Beam, cz, inner.x1 - inner.x0, 1, 1, 0, false)
		freeFixture(S, "lantern", "workshop", cx, F.Beam - 2.4, cz, 0.9, 2.4, 0.9, 0, false)
		local a = span(inner, side)
		window(S, "workshop", side, a + 5, F.BarnWindow, F.BarnSill)
	end
end

-- Kept clear: in front of every doorway, DoorClear deep into each room it joins; in front of a window (for tall
-- pieces).
local function zones(S: State)
	for _, room in S.rooms do
		S.zones[room.id] = {}
		S.windowZones[room.id] = {}
	end
	for _, d in S.doors do
		local deep = T.DoorClear
		for _, id in { d.a, d.b or "" } do
			local room = S.byId[id]
			if room then
				local w = d.width / 2 + 0.5
				if d.alongX then
					local into = if (room.cell.z0 + room.cell.z1) / 2 > d.z then 1 else -1
					local face = d.z + into * HALF
					table.insert(S.zones[id], rect(d.x - w, face, d.x + w, face + into * deep))
				else
					local into = if (room.cell.x0 + room.cell.x1) / 2 > d.x then 1 else -1
					local face = d.x + into * HALF
					table.insert(S.zones[id], rect(face, d.z - w, face + into * deep, d.z + w))
				end
			end
		end
	end
	for _, w in S.windows do
		local room = S.byId[w.room]
		local _, _, r = against(room.inner, w.side, w.t, w.width + 1, 3, 0)
		table.insert(S.windowZones[w.room], r)
	end
end

-- ── The pieces (as a house's) ─────────────────────────────────────────────────────

local function fits(S: State, room: RoomData, r: Rect, h: number): boolean
	if not within(r, room.inner) then
		return false
	end
	local ban = S.banned[room.id .. "/" .. S.placing]
	if ban then
		for _, b in ban do
			if hits(r, b, 0) then
				return false
			end
		end
	end
	for _, z in S.zones[room.id] do
		if hits(r, z, 0) then
			return false
		end
	end
	for _, f in S.fixtures do
		if f.solid and f.room == room.id and hits(r, f.rect, T.FixtureGap) then
			return false
		end
	end
	for _, p in S.placed do
		if p.room == room.id and hits(r, p.rect, T.Gap) then
			return false
		end
	end
	if h > T.WindowSill then
		for _, z in S.windowZones[room.id] do
			if hits(r, z, 0) then
				return false
			end
		end
	end
	return true
end

-- Every place against a wall of the room a piece fits, scored by `score(side, t, lo, hi)` (lower is better).
local function wallSpots(S: State, room: RoomData, id: string, score: (string, number, number, number) -> number): { Cand }
	local def = FurnitureLooks.Items[id]
	local w, d, h = def.size.X, def.size.Z, def.size.Y
	local out: { Cand } = {}
	for _, side in SIDES do
		local lo, hi = span(room.inner, side)
		local t = lo + w / 2 + T.WallGap
		while t <= hi - w / 2 - T.WallGap + 1e-6 do
			local x, z, r = against(room.inner, side, t, w, d, T.WallGap)
			if fits(S, room, r, h) then
				table.insert(out, { x = x, z = z, turn = SIDE_TURN[side], rect = r, side = side, t = t, score = score(side, t, lo, hi) })
			end
			t += 0.5
		end
	end
	return out
end

-- The best few candidates (lowest score), one of them by the dice.
local function choose(S: State, cands: { Cand }, spread: number): Cand?
	if #cands == 0 then
		return nil
	end
	table.sort(cands, function(a: Cand, b: Cand): boolean
		if math.abs(a.score - b.score) > 1e-9 then
			return a.score < b.score
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.z < b.z
	end)
	local best = cands[1].score
	local n = 1
	while n < #cands and cands[n + 1].score <= best + spread do
		n += 1
	end
	return cands[S.rng.int(1, n)]
end

local function find(S: State, roomId: string, id: string): Placed?
	for _, p in S.placed do
		if p.room == roomId and p.item == id then
			return p
		end
	end
	return nil
end

local function footprint(x: number, z: number, turn: number, id: string): Rect
	local ex, ez = extent(id, turn)
	return rect(x - ex / 2, z - ez / 2, x + ex / 2, z + ez / 2)
end

local function candidates(S: State, room: RoomData, e: Entry): Cand?
	local def = FurnitureLooks.Items[e.item]
	local h = def.size.Y
	local how = e.how
	local ref = if e.ref then find(S, room.id, e.ref) else nil
	if e.ref and not ref and how ~= "around" then
		how = "wall"
	end
	if how == "corner" then
		return choose(S, wallSpots(S, room, e.item, function(_: string, t: number, lo: number, hi: number): number
			return math.min(t - lo, hi - t)
		end), 0.6)
	elseif how == "centre" then
		return choose(S, wallSpots(S, room, e.item, function(_: string, t: number, lo: number, hi: number): number
			return math.abs(t - (lo + hi) / 2) - (hi - lo) * 0.5
		end), 1)
	elseif how == "far" then
		-- across from the room's door (its first one)
		local doorSide = "S"
		for _, d in S.doors do
			if d.a == room.id or d.b == room.id then
				if d.alongX then
					doorSide = if math.abs(d.z - room.cell.z0) < 1e-6 then "S" else "N"
				else
					doorSide = if math.abs(d.x - room.cell.x0) < 1e-6 then "W" else "E"
				end
				break
			end
		end
		local far = OPPOSITE[doorSide]
		return choose(S, wallSpots(S, room, e.item, function(side: string, t: number, lo: number, hi: number): number
			return (if side == far then 0 else 100) + math.abs(t - (lo + hi) / 2)
		end), 1)
	elseif how == "facing" and ref and ref.side and ref.t then
		local across, target = OPPOSITE[ref.side], ref.t
		return choose(S, wallSpots(S, room, e.item, function(side: string, t: number): number
			return (if side == across then 0 else 100) + math.abs(t - target)
		end), 0.5)
	elseif how == "beside" and ref and ref.side and ref.t then
		local w, d = def.size.X, def.size.Z
		local refW = FurnitureLooks.Items[ref.item].size.X
		local sides = { -1, 1 }
		shuffle(sides, S.rng)
		for _, s in sides do
			local t = ref.t + s * (refW / 2 + T.Gap + 0.05 + w / 2)
			local x, z, r = against(room.inner, ref.side, t, w, d, T.WallGap)
			if fits(S, room, r, h) then
				return { x = x, z = z, turn = ref.turn, rect = r, side = ref.side, t = t, score = 0 }
			end
		end
		return nil
	elseif how == "front" and ref and ref.side then
		local face = SIDE_FACE[ref.side]
		local refD = FurnitureLooks.Items[ref.item].size.Z
		for _, gap in { 1.8, 2.2, 2.6, 3.0 } do
			local along = refD / 2 + gap + def.size.Z / 2
			local x, z = ref.x + face[1] * along, ref.z + face[2] * along
			local r = footprint(x, z, ref.turn, e.item)
			if fits(S, room, r, h) then
				return { x = x, z = z, turn = ref.turn, rect = r, score = 0 }
			end
		end
		return nil
	elseif how == "open" then
		-- free-standing with a way round it (the hay wagon), its long side along the room's, its front to the back wall
		-- (+Z: the barn doors), as near the room's middle as it goes
		local inner = room.inner
		local alongZ = (inner.z1 - inner.z0) >= (inner.x1 - inner.x0)
		local long = if def.size.Z >= def.size.X then 0 else 90
		local turn = if alongZ then long + 180 else long + 90
		local ex, ez = extent(e.item, turn)
		local lane = 1.5
		local cx, cz = (inner.x0 + inner.x1) / 2, (inner.z0 + inner.z1) / 2
		local cands: { Cand } = {}
		local x = inner.x0 + ex / 2 + lane
		while x <= inner.x1 - ex / 2 - lane + 1e-6 do
			local z = inner.z0 + ez / 2 + lane
			while z <= inner.z1 - ez / 2 - lane + 1e-6 do
				local r = footprint(x, z, turn, e.item)
				if fits(S, room, rect(r.x0 - lane, r.z0 - lane, r.x1 + lane, r.z1 + lane), h) then
					table.insert(cands, { x = x, z = z, turn = turn, rect = r, score = math.abs(x - cx) + math.abs(z - cz) })
				end
				z += 1
			end
			x += 1
		end
		return choose(S, cands, 1)
	elseif how == "middle" then
		-- free-standing, its long side along the room's long side, room round it for chairs and a way past
		local inner = room.inner
		local long = (inner.x1 - inner.x0) >= (inner.z1 - inner.z0)
		local sx, sz = def.size.X, def.size.Z
		local turn = if (sx >= sz) == long then 0 else 90
		local ex, ez = extent(e.item, turn)
		local laneLong, laneEnd = 3.8, 2.5
		local alongX = ex >= ez
		local cx, cz = (inner.x0 + inner.x1) / 2, (inner.z0 + inner.z1) / 2
		local cands: { Cand } = {}
		local x = inner.x0 + ex / 2
		while x <= inner.x1 - ex / 2 do
			local z = inner.z0 + ez / 2
			while z <= inner.z1 - ez / 2 do
				local r = footprint(x, z, turn, e.item)
				local around = if alongX
					then rect(r.x0 - laneEnd, r.z0 - laneLong, r.x1 + laneEnd, r.z1 + laneLong)
					else rect(r.x0 - laneLong, r.z0 - laneEnd, r.x1 + laneLong, r.z1 + laneEnd)
				if fits(S, room, around, h) then
					table.insert(cands, { x = x, z = z, turn = turn, rect = r, score = math.abs(x - cx) + math.abs(z - cz) })
				end
				z += 1
			end
			x += 1
		end
		return choose(S, cands, 1)
	elseif how == "around" and ref then
		-- the chair places along the table's long sides, facing it; the first free one
		local refDef = FurnitureLooks.Items[ref.item]
		local tableAlongX = norm(ref.turn) % 180 == 0
		local halfLong = refDef.size.X / 4
		local off = refDef.size.Z / 2 + T.Gap + 0.05 + def.size.Z / 2
		local seats: { { number } } = {}
		for _, s in { -1, 1 } do
			for _, a in { -1, 1 } do
				if tableAlongX then
					table.insert(seats, { ref.x + a * halfLong, ref.z + s * off, if s < 0 then 180 else 0 })
				else
					table.insert(seats, { ref.x + s * off, ref.z + a * halfLong, if s < 0 then 270 else 90 })
				end
			end
		end
		for _, n in { 1, 3, 2, 4 } do
			local seat = seats[n]
			local r = footprint(seat[1], seat[2], seat[3], e.item)
			if fits(S, room, r, h) then
				return { x = seat[1], z = seat[2], turn = seat[3], rect = r, score = 0 }
			end
		end
		return nil
	end
	return choose(S, wallSpots(S, room, e.item, function(): number
		return 0
	end), 0)
end

local function place(S: State, roomId: string, e: Entry, must: boolean, star: boolean): Placed?
	local room = S.byId[roomId]
	S.placing = e.item
	local c = candidates(S, room, e)
	if not c and must then
		-- a must that does not fit its way: free-standing anywhere it fits, else against any wall
		for _, how in { "open", "wall" } do
			c = c or candidates(S, room, { item = e.item, how = how })
		end
	end
	if not c then
		return nil
	end
	S.counter += 1
	local p: Placed = {
		item = e.item,
		room = roomId,
		x = c.x,
		z = c.z,
		turn = norm(c.turn),
		rect = c.rect,
		side = c.side,
		t = c.t,
		must = must,
		star = star,
		order = S.counter,
		variant = S.rng.int(1, 12),
		entry = e,
	}
	table.insert(S.placed, p)
	return p
end

-- The exits' doorways (each a box through its wall) and which pieces may use which (a bigDoor piece only a doorway
-- wider than a house's).
local function exitDoors(S: State): ({ Rect }, { number })
	local rects, widths = {}, {}
	for _, d in S.doors do
		if d.b == nil then
			local w = d.width / 2
			table.insert(rects, if d.alongX then rect(d.x - w, d.z - HALF, d.x + w, d.z + HALF) else rect(d.x - HALF, d.z - w, d.x + HALF, d.z + w))
			table.insert(widths, d.width)
		end
	end
	return rects, widths
end

-- The pieces that cannot get out of an exit they may use: indexes into `items`/`rects`. Two fields: every exit (for
-- most pieces) and the wide ones only (for a bigDoor piece).
local function stuckPieces(box: Rect, walls: { Rect }, doors: { Rect }, widths: { number }, items: { string }, rects: { Rect }): { number }
	local radii: { number } = {}
	local anyBig = false
	for n, id in items do
		radii[n] = radiusOf(id)
		local def = FurnitureLooks.Items[id]
		anyBig = anyBig or (def ~= nil and def.bigDoor == true)
	end
	local stuck = stuckOf(newField(box, walls, doors), rects, radii)
	if not anyBig then
		return stuck
	end
	local wide: { Rect } = {}
	for n, r in doors do
		if widths[n] > T.FrontDoor then
			table.insert(wide, r)
		end
	end
	local bigStuck = stuckOf(newField(box, walls, wide), rects, radii)
	local out: { number } = {}
	for _, n in stuck do
		local def = FurnitureLooks.Items[items[n]]
		if not (def and def.bigDoor) then
			table.insert(out, n)
		end
	end
	for _, n in bigStuck do
		local def = FurnitureLooks.Items[items[n]]
		if def and def.bigDoor then
			table.insert(out, n)
		end
	end
	table.sort(out)
	return out
end

local function furnish(S: State)
	local rng = S.rng
	-- the ★ pieces: Stars of the candidates, by the dice
	type Pick = { room: string, entry: Entry }
	local sentimental: { Pick } = {}
	for _, roomId in FURNISH do
		for _, e in RECIPES[roomId] do
			if e.star then
				table.insert(sentimental, { room = roomId, entry = e })
			end
		end
	end
	shuffle(sentimental, rng)
	-- Stars of them, in the dice's order (one that finds no room gives its place to the next); `check`: one that
	-- cannot get out goes again
	local function placeStars(check: (() -> boolean)?)
		local stars = 0
		for _, p in S.placed do
			if p.star then
				stars += 1
			end
		end
		for _, pick in sentimental do
			if stars >= F.Stars then
				break
			end
			if not find(S, pick.room, pick.entry.item) then
				local p = place(S, pick.room, pick.entry, true, true)
				if p and check and not check() then
					table.remove(S.placed, table.find(S.placed, p) :: number)
				elseif p then
					stars += 1
				end
			end
		end
	end
	local target = rng.int(F.Spots[1], F.Spots[2])
	-- the musts, then the ★ ones, then the rest in a weighted shuffle until the farm holds `target` pieces
	local optional: { Pick } = {}
	for _, roomId in FURNISH do
		for _, e in RECIPES[roomId] do
			if e.must then
				place(S, roomId, e, true, false)
			elseif not e.star then
				table.insert(optional, { room = roomId, entry = e })
			end
		end
	end
	placeStars()
	local keys: { [Pick]: number } = {}
	for _, pick in optional do
		keys[pick] = rng.num() ^ (1 / (pick.entry.odds or 1))
	end
	table.sort(optional, function(a: Pick, b: Pick): boolean
		return keys[a] > keys[b]
	end)
	for _, pick in optional do
		if #S.placed >= target then
			break
		end
		place(S, pick.room, pick.entry, false, false)
	end
	-- a second pass over the leftovers (a room that was full may take a smaller piece)
	if #S.placed < F.Spots[1] then
		for _, pick in optional do
			if #S.placed >= F.Spots[1] then
				break
			end
			if not find(S, pick.room, pick.entry.item) then
				place(S, pick.room, pick.entry, false, false)
			end
		end
	end

	-- Every piece must get out: drop what blocks (the latest optional piece of the room, else the stuck piece itself).
	local solids = table.clone(S.walls)
	for _, f in S.fixtures do
		if f.solid then
			table.insert(solids, f.rect)
		end
	end
	local doors, widths = exitDoors(S)
	local function stuckNow(): { number }
		local items, rects = {}, {}
		for _, p in S.placed do
			table.insert(items, p.item)
			table.insert(rects, p.rect)
		end
		return stuckPieces(S.box, solids, doors, widths, items, rects)
	end
	for _ = 1, 16 do
		local stuck = stuckNow()
		if #stuck == 0 then
			break
		end
		local victim = S.placed[stuck[1]]
		local latest: Placed? = nil
		if victim.must then
			for _, p in S.placed do
				if p.room == victim.room and not p.must and (latest == nil or p.order > latest.order) then
					latest = p
				end
			end
		end
		if latest then
			table.remove(S.placed, table.find(S.placed, latest) :: number)
		else
			table.remove(S.placed, table.find(S.placed, victim) :: number)
			if victim.must then
				local key = victim.room .. "/" .. victim.item
				S.banned[key] = S.banned[key] or {}
				table.insert(S.banned[key], victim.rect)
				local again = place(S, victim.room, victim.entry, true, victim.star)
				if again then
					again.order = victim.order
				end
			end
		end
	end
	local stuck = stuckNow()
	for n = #stuck, 1, -1 do
		table.remove(S.placed, stuck[n])
	end
	placeStars(function(): boolean
		return #stuckNow() == 0
	end)
	-- too few pieces: moving boxes where they fit (and can get out)
	local fill = 1
	while #S.placed < F.Spots[1] and fill <= #FILLER * 3 do
		local roomId = FILLER[(fill - 1) % #FILLER + 1]
		fill += 1
		local p = place(S, roomId, { item = "box", how = "corner" }, false, false)
		if p and #stuckNow() > 0 then
			table.remove(S.placed, table.find(S.placed, p) :: number)
		end
	end
	-- exactly Stars ★: the sentimental pieces first, then the dearest
	local stars = 0
	for _, p in S.placed do
		if p.star then
			stars += 1
		end
	end
	if stars < F.Stars then
		local byValue = table.clone(S.placed)
		table.sort(byValue, function(a: Placed, b: Placed): boolean
			local da, db = FurnitureLooks.Items[a.item], FurnitureLooks.Items[b.item]
			if da.sentimental ~= db.sentimental then
				return da.sentimental
			end
			if da.value ~= db.value then
				return da.value > db.value
			end
			return a.order < b.order
		end)
		for _, p in byValue do
			if stars >= F.Stars then
				break
			end
			if not p.star then
				p.star = true
				stars += 1
			end
		end
	end
	-- a rug under the Stube's table
	local table_ = find(S, "stube", "dining_table")
	if table_ then
		local inner = S.byId.stube.inner
		local w, d = math.min(9, inner.x1 - inner.x0 - 1.2), math.min(7, inner.z1 - inner.z0 - 1.2)
		local x = math.clamp(table_.x, inner.x0 + 0.6 + w / 2, inner.x1 - 0.6 - w / 2)
		local z = math.clamp(table_.z, inner.z0 + 0.6 + d / 2, inner.z1 - 0.6 - d / 2)
		freeFixture(S, "rug", "stube", x, 0, z, w, 0.08, d, 0, false)
	end
end

-- ── The plan ───────────────────────────────────────────────────────────────────

local function toPlan(S: State, seed: number): Plan
	local rank: { [string]: number } = {}
	for n, id in FURNISH do
		rank[id] = n
	end
	table.sort(S.placed, function(a: Placed, b: Placed): boolean
		if a.room ~= b.room then
			return rank[a.room] < rank[b.room]
		end
		return a.order < b.order
	end)
	local spots: { Spot } = {}
	for n, p in S.placed do
		local def = FurnitureLooks.Items[p.item]
		table.insert(spots, {
			id = n,
			item = p.item,
			room = p.room,
			at = CFrame.new(p.x, def.size.Y / 2, p.z) * CFrame.Angles(0, math.rad(p.turn), 0),
			star = p.star,
			turn = p.turn,
			variant = p.variant,
		})
	end
	local rooms: { Room } = {}
	for _, room in S.rooms do
		local inner = room.inner
		table.insert(rooms, { id = room.id, kind = room.kind, min = Vector3.new(inner.x0, 0, inner.z0), max = Vector3.new(inner.x1, room.top, inner.z1) })
	end
	local up = T.EntryUp
	local doors: { Door } = {}
	local exits: { Vector3 } = {}
	for n, d in S.doors do
		local axis: Axis = if d.alongX then "X" else "Z"
		table.insert(doors, { at = Vector3.new(d.x, 0, d.z), width = d.width, axis = axis, rooms = { d.a, d.b or "outside" }, front = n == 1 })
		if d.b == nil then
			-- the doorway's inside: toward its room
			local room = S.byId[d.a]
			local into = if d.alongX
				then (if (room.cell.z0 + room.cell.z1) / 2 > d.z then 1 else -1)
				else (if (room.cell.x0 + room.cell.x1) / 2 > d.x then 1 else -1)
			table.insert(exits, if d.alongX then Vector3.new(d.x, up, d.z + into * HALF) else Vector3.new(d.x + into * HALF, up, d.z))
		end
	end
	local windows: { Window } = {}
	for _, w in S.windows do
		local inner = S.byId[w.room].inner
		local at, normal
		if w.side == "S" then
			at, normal = Vector3.new(w.t, w.y, inner.z0), Vector3.new(0, 0, 1)
		elseif w.side == "N" then
			at, normal = Vector3.new(w.t, w.y, inner.z1), Vector3.new(0, 0, -1)
		elseif w.side == "W" then
			at, normal = Vector3.new(inner.x0, w.y, w.t), Vector3.new(1, 0, 0)
		else
			at, normal = Vector3.new(inner.x1, w.y, w.t), Vector3.new(-1, 0, 0)
		end
		table.insert(windows, { room = w.room, at = at, width = w.width, height = w.height, normal = normal })
	end
	local fixtures: { Fixture } = {}
	for _, f in S.fixtures do
		table.insert(fixtures, {
			kind = f.kind,
			room = f.room,
			at = CFrame.new(f.x, f.y, f.z) * CFrame.Angles(0, math.rad(f.turn), 0),
			size = Vector3.new(f.w, f.h, f.d),
			turn = f.turn,
			solid = f.solid,
		})
	end
	local min = Vector3.new(S.box.x0, 0, S.box.z0)
	local max = Vector3.new(S.box.x1, F.BarnCeiling, S.box.z1)
	return {
		kind = "farm",
		seed = seed,
		mirrored = S.mirrored,
		size = max - min,
		min = min,
		max = max,
		rooms = rooms,
		doors = doors,
		entry = CFrame.lookAt(Vector3.new(0, up, T.EntryIn), Vector3.new(0, up, T.EntryIn + 1)),
		exit = exits[1],
		exits = exits,
		spots = spots,
		ceiling = T.Ceiling,
		wall = T.Wall,
		doorHeight = T.DoorHeight,
		faces = S.faces,
		windows = windows,
		fixtures = fixtures,
	}
end

function Farm.plan(seed: number): Plan
	local S: State = {
		rng = newRng(seed),
		rooms = {},
		byId = {},
		doors = {},
		fixtures = {},
		windows = {},
		faces = {},
		walls = {},
		zones = {},
		windowZones = {},
		placed = {},
		banned = {},
		placing = "",
		counter = 0,
		mirrored = false,
		box = rect(0, 0, 0, 0),
	}
	shell(S)
	walls(S)
	fixtures(S)
	zones(S)
	furnish(S)
	return toPlan(S, seed)
end

-- The exits a piece can be carried out of (indexes into plan.exits): every one, but for a bigDoor piece only those
-- whose doorway is wider than a house's front door (the barn doors).
function Farm.exitsFor(plan: Plan, id: string): { number }
	local def = FurnitureLooks.Items[id]
	local big = def ~= nil and def.bigDoor == true
	local out: { number } = {}
	local n = 0
	for _, d in plan.doors do
		if d.rooms[2] == "outside" then
			n += 1
			if not big or d.width > T.FrontDoor then
				table.insert(out, n)
			end
		end
	end
	return out
end

-- The spots of a plan whose piece cannot be carried out of an exit it may use (with every other piece in place).
function Farm.stuck(plan: Plan): { number }
	local walls: { Rect } = {}
	for _, f in plan.faces do
		if not f.header then
			table.insert(walls, rect(f.min.X, f.min.Z, f.max.X, f.max.Z))
		end
	end
	for _, f in plan.fixtures do
		if f.solid then
			local turned = norm(f.turn) % 180 ~= 0
			local ex, ez = if turned then f.size.Z else f.size.X, if turned then f.size.X else f.size.Z
			local p = f.at.Position
			table.insert(walls, rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2))
		end
	end
	local doors, widths = {}, {}
	for _, d in plan.doors do
		if d.rooms[2] == "outside" then
			local w = d.width / 2
			table.insert(doors, if d.axis == "X" then rect(d.at.X - w, d.at.Z - HALF, d.at.X + w, d.at.Z + HALF) else rect(d.at.X - HALF, d.at.Z - w, d.at.X + HALF, d.at.Z + w))
			table.insert(widths, d.width)
		end
	end
	local items, rects = {}, {}
	for _, s in plan.spots do
		local ex, ez = extent(s.item, s.turn)
		local p = s.at.Position
		table.insert(items, s.item)
		table.insert(rects, rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2))
	end
	local out: { number } = {}
	for _, index in stuckPieces(rect(plan.min.X, plan.min.Z, plan.max.X, plan.max.Z), walls, doors, widths, items, rects) do
		table.insert(out, plan.spots[index].id)
	end
	return out
end

return Farm
