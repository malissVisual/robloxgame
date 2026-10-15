--!strict
-- 7.0 prototype, the moving (design/rework/NAVRH.md): the plan of a place to move out of, as data. Pure and
-- deterministic (the same seed and kind give the same plan on every server); it makes no instances.
-- server/HouseInterior.luau builds a plan, the moving job (server/Moving.luau) carries its pieces out of it.
--
--   HouseLayout.plan(seed, kind)   a plan of `kind` ("house": Marge's family house in the suburbs, one storey; 7.x
--                                  "farm": Walt's alpine farm, shared/Layouts/Farm.luau, its plan adds `exits`; 8.3
--                                  "big": the sandbox's big house, a house's plan made bigger, see below; an
--                                  unknown kind is a house). Every position is LOCAL to the house's origin: the ground
--                                  (the floor's top) at the front door's middle, +Z into the house, +Y up.
--   8.3 the big house (Config.Furniture.Big): one big floor laid out as a house (the same rooms' kinds, fixtures, rules
--   and dice), only bigger: six rooms in the back row (the house's four, the guest room "guest" of kind bedroom and the
--   study "study" of kind living: HouseLayout.BigRecipes), a bigger front row, more pieces (Big.Spots), more ★
--   (Big.Stars) and collectibles (Big.Collectibles), and a second way out: the back door at the corridor's east
--   end (+X, mirrored or not; its doorway doors[n] with rooms { "corridor", "outside" }), so its plan has `exits` as a
--   farm's (exits[1] the front door, exits[2] the back door). Every piece gets out by either door (its layout checks
--   both). A house's plan is the same as before the big house (its dice untouched).
--   8.3 economy: HouseLayout.plan(seed, kind, found), `found` the move owner's collection book ({ [item] = anything },
--   optional): a house that rolls a legendary collectible tries the legendaries not in it first (the same seed, kind
--   and book give the same plan; without `found` the plan is as before). A farm ignores it. 8.7 review: a page only
--   bought from a player (its `bought` mark, shared/CollectionBookRules.luau) is not in it: that one is still to find.
--   8.3: HouseLayout.Collectibles is the whole pool a house's collectibles come from: its own entries, then any other
--   piece of FurnitureLooks.Collectibles (a new one joins on its own, at a wall in the room its catalogue entry names,
--   when the house has that room). HouseLayout.BigRecipes: the big house's rooms' recipes (its own and the house's).
--   HouseLayout.Kinds              the kinds it lays out (a new kind ("apartment", "farm", "hotel") is a function
--                                  seed's dice → Plan added to KINDS below)
--   HouseLayout.Recipes            what each room holds: its pieces, how each is placed, the musts and the ★ ones
--   HouseLayout.Collectibles       8.0: how each collectible (FurnitureLooks.Collectibles, a piece with a rarity) is
--                                  placed in its room; a house holds Config.Furniture.Collectibles.Count of them besides
--                                  its Spots (their own dice, never ★; a legendary one in about one house in 25)
--   HouseLayout.extent(id, turn)   a piece's footprint (X, Z) turned by `turn` degrees (a multiple of 90)
--   HouseLayout.stuck(plan)        the spots whose piece cannot be carried out of the front door (empty for every plan
--                                  it makes: it checks this while it lays the pieces out)
--   7.x farm move (server/Moving.luau): HouseLayout.exitsOf(plan) the ways out (a farm's exits, a house's front
--   door), HouseLayout.entries(plan) where you come in by each, HouseLayout.exitsFor(plan, id) the ways out a piece
--   may take (a farm's bigDoor piece: the barn doors only)
--
-- A Plan:
--   kind, seed, mirrored          what it is, its dice, and whether it is the left-right mirror of the template
--   size, min, max                the house's box (the outer faces of its outer walls, floor to ceiling)
--   rooms                         { id, kind, min, max }: each room's clear inside (min.Y the floor, max.Y the ceiling);
--                                 ids hall, corridor (kind "hall"), living, kitchen, bedroom, kids, bath, garage
--   doors                         { at, width, axis, rooms, front }: a doorway's middle on its wall's centre line (at
--                                 floor level), its width along `axis` ("X": in a wall running along X), the rooms it
--                                 joins; doors[1] is the front door (rooms { "hall", "outside" }, front = true)
--   entry                         where a player appears inside the front door, facing into the house
--   exit                          the front door's inside (EntryUp over the floor): the trigger to leave
--   spots                         { id, item, room, at, star, turn, variant }: a piece (FurnitureLooks id) standing in a
--                                 room (its id), `at` its Root's middle (on the floor), turned `turn` degrees about Y
--                                 (its front, -Z, toward the room), `variant` its colours; Stars of them are ★ (8.0: a
--                                 house's collectibles come last in their rooms, their catalogue entries' rarity set)
--   ceiling, wall, doorHeight     the numbers it was laid out with (Config.Furniture)
--   faces                         { room, min, max, normal, outer, header }: the walls as slabs, one per room side
--                                 piece (a shared wall is two, one for each room's wallpaper), cut at the doorways;
--                                 `header` the wall over a doorway; `normal` points into the room
--   windows                       { room, at, width, height, normal }: on the outer walls' inside faces
--   fixtures                      { kind, room, at, size, turn, solid }: what stays (counters, the stove, the sink,
--                                 the tub, the toilet, the basin, the workbench, shelves, the garage door, rugs ...;
--                                 7.x alpine: the Kachelofen, the kitchen's corner bench and its corner shelf, the
--                                 antlers and the pictures high on the walls): `at` the bottom middle, size (along the
--                                 wall, height, depth), the front toward -Z turned by `turn`; a solid one stands in the
--                                 way (a corner shelf's corner is at its +X, +Z)

local Config = require(script.Parent.Config)
local FurnitureLooks = require(script.Parent.FurnitureLooks)
local Farm = require(script.Parent.Layouts.Farm) -- 7.x the farm

local T = Config.Furniture
local A = T.Alpine
local HouseLayout = {}

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
	exits: { Vector3 }?, -- (7.x a farm's, 8.3 a big house's ways out: exits[1] == exit)
	spots: { Spot },
	ceiling: number,
	wall: number,
	doorHeight: number,
	faces: { Face },
	windows: { Window },
	fixtures: { Fixture },
}

-- ── Small things ──────────────────────────────────────────────────────────────

type Rng = { num: () -> number, int: (number, number) -> number }

-- 32-bit multiply, exact in doubles (in 16-bit halves).
local function mul32(a: number, b: number): number
	local hi, lo = a // 65536, a % 65536
	return ((hi * b) % 65536 * 65536 + lo * b) % 4294967296
end

-- A seed's 32-bit hash (lowbias32): neighbouring seeds give unrelated dice.
local function hash(x: number): number
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x7feb352d)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = mul32(x, 0x846ca68b)
	return bit32.bxor(x, bit32.rshift(x, 16))
end

-- The dice (Park-Miller after the hash: exact in doubles, the same everywhere).
local function newRng(seed: number): Rng
	local s = math.floor(math.abs(seed)) % 4294967296
	local state = hash(s) % 2147483646 + 1
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

-- Do a and b come closer than `gap`?
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
function HouseLayout.extent(id: string, turn: number): (number, number)
	local def = FurnitureLooks.Items[id] or FurnitureLooks.Items.box
	if norm(turn) % 180 == 0 then
		return def.size.X, def.size.Z
	end
	return def.size.Z, def.size.X
end

-- ── Reachability ──────────────────────────────────────────────────────────────
-- Every piece must get from where it stands out of the front door, carried end first: a disc as wide as its narrow
-- side (min of X and Z) must find a way through the walls' gaps, past the fixtures and every other piece (all still in
-- place, the worst case). On a grid of T.Grid studs: the clearance of every point (to the walls and fixtures once, the
-- pieces added each check), the widest way in from the front door (a bottleneck fill), then from each piece a flood
-- over the points clear for it (without itself) until it meets that way at its width.

local CAP = 4 -- clearances beyond this do not matter (the widest piece needs 2.7)
local STEP = 0.05 -- the bottleneck's levels

type Field = { x0: number, z0: number, nx: number, nz: number, step: number, static: { number }, door: Rect }

local function newField(box: Rect, walls: { Rect }, door: Rect): Field
	local step = T.Grid
	local x0, z0 = math.floor(box.x0 / step) * step, math.floor(box.z0 / step) * step
	local nx = math.floor((box.x1 - x0) / step) + 1
	local nz = math.floor((box.z1 - z0) / step) + 1
	local static = table.create(nx * nz, CAP)
	local field: Field = { x0 = x0, z0 = z0, nx = nx, nz = nz, step = step, static = static, door = door }
	for _, r in walls do
		local i0 = math.max(0, math.floor((r.x0 - CAP - x0) / step))
		local i1 = math.min(nx - 1, math.ceil((r.x1 + CAP - x0) / step))
		local j0 = math.max(0, math.floor((r.z0 - CAP - z0) / step))
		local j1 = math.min(nz - 1, math.ceil((r.z1 + CAP - z0) / step))
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

-- Which of `pieces` (footprints, each with the radius it needs) cannot get out of the front door: their indexes.
local function stuckOf(field: Field, pieces: { Rect }, radii: { number }): { number }
	local nx, nz, step, x0, z0 = field.nx, field.nz, field.step, field.x0, field.z0
	local clear = table.clone(field.static)
	for _, r in pieces do
		local i0 = math.max(0, math.floor((r.x0 - CAP - x0) / step))
		local i1 = math.min(nx - 1, math.ceil((r.x1 + CAP - x0) / step))
		local j0 = math.max(0, math.floor((r.z0 - CAP - z0) / step))
		local j1 = math.min(nz - 1, math.ceil((r.z1 + CAP - z0) / step))
		for j = j0, j1 do
			local z = z0 + j * step
			for i = i0, i1 do
				local d = distTo(x0 + i * step, z, r)
				local k = j * nx + i + 1
				if d < clear[k] then
					clear[k] = d
				end
			end
		end
	end
	-- the widest way in: best[k] = the widest disc (in STEP levels) that gets from the front door to point k
	local levels = math.floor(CAP / STEP)
	local best = table.create(nx * nz, -1)
	local buckets: { { number } } = {}
	for level = 0, levels do
		buckets[level + 1] = {}
	end
	local door = field.door
	for j = 0, nz - 1 do
		local z = z0 + j * step
		if z >= door.z0 - 1e-6 and z <= door.z1 + 1e-6 then
			for i = 0, nx - 1 do
				local x = x0 + i * step
				if x >= door.x0 - 1e-6 and x <= door.x1 + 1e-6 then
					local k = j * nx + i + 1
					local level = math.floor(clear[k] / STEP)
					best[k] = level
					table.insert(buckets[level + 1], k)
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
				local ni, nj = i, j
				if side == 1 then
					ni -= 1
				elseif side == 2 then
					ni += 1
				elseif side == 3 then
					nj -= 1
				else
					nj += 1
				end
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
	-- from each piece: a flood over the points clear for it (itself lifted) until it meets the way in at its width
	local stuck: { number } = {}
	for index, own in pieces do
		local radius = radii[index]
		local need = math.ceil(radius / STEP - 1e-9)
		local function clearFor(k: number, x: number, z: number): boolean
			if clear[k] >= radius then
				return true -- (8.3: nothing at all is that close, its own box neither: the same answer, quicker)
			end
			local c = field.static[k]
			if c < radius then
				return false
			end
			for other, r in pieces do
				if other ~= index and distTo(x, z, r) < radius then
					return false
				end
			end
			return true
		end
		local seen: { [number]: boolean } = {}
		local queue: { number } = {}
		local ci = math.clamp(math.floor(((own.x0 + own.x1) / 2 - x0) / step + 0.5), 0, nx - 1)
		local cj = math.clamp(math.floor(((own.z0 + own.z1) / 2 - z0) / step + 0.5), 0, nz - 1)
		-- start inside its own footprint, at the middle or wherever it is clear for it
		local i0 = math.max(0, math.ceil((own.x0 - x0) / step))
		local i1 = math.min(nx - 1, math.floor((own.x1 - x0) / step))
		local j0 = math.max(0, math.ceil((own.z0 - z0) / step))
		local j1 = math.min(nz - 1, math.floor((own.z1 - z0) / step))
		local starts = { cj * nx + ci + 1 }
		for j = j0, j1 do
			for i = i0, i1 do
				table.insert(starts, j * nx + i + 1)
			end
		end
		for _, k in starts do
			if not seen[k] then
				local i, j = (k - 1) % nx, (k - 1) // nx
				seen[k] = true
				if clearFor(k, x0 + i * step, z0 + j * step) then
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
				local ni, nj = i, j
				if side == 1 then
					ni -= 1
				elseif side == 2 then
					ni += 1
				elseif side == 3 then
					nj -= 1
				else
					nj += 1
				end
				if ni >= 0 and ni < nx and nj >= 0 and nj < nz then
					local nk = nj * nx + ni + 1
					if not seen[nk] then
						seen[nk] = true
						if clearFor(nk, x0 + ni * step, z0 + nj * step) then
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

-- The radius a piece needs carried end first.
local function radiusOf(id: string): number
	local def = FurnitureLooks.Items[id] or FurnitureLooks.Items.box
	return math.min(def.size.X, def.size.Z) / 2
end

-- ── The rooms' contents ─────────────────────────────────────────────────────────
-- how: "far" (back to the wall across from the room's door, centred), "centre" (back to a long wall, centred),
-- "wall" (back to any wall), "corner" (back to a wall, as near a corner as it goes), "facing" (back to the wall across
-- from `ref`, in line with it), "front" (free-standing in front of `ref`), "beside" (the same wall right next to
-- `ref`), "middle" (free-standing in the middle with room round it), "around" (a chair at `ref`'s long side, facing it).
-- must: always there; star: one of the sentimental ★ pieces (Stars of them); odds: how likely an optional piece comes
-- before the others (default 1)
export type Entry = { item: string, how: string, ref: string?, must: boolean?, star: boolean?, odds: number? }

local RECIPES: { [string]: { Entry } } = {
	hall = {
		{ item = "coat_rack", how = "corner", must = true },
		{ item = "shoe_cabinet", how = "wall" },
		{ item = "plant", how = "corner" },
		{ item = "ski_bundle", how = "corner", odds = 4 }, -- (7.x alpine)
	},
	living = {
		{ item = "sofa", how = "centre", must = true },
		{ item = "tv", how = "facing", ref = "sofa", must = true },
		{ item = "coffee_table", how = "front", ref = "sofa", must = true },
		{ item = "grandfather_clock", how = "wall", star = true },
		{ item = "record_player", how = "wall", star = true },
		{ item = "armchair", how = "wall", odds = 3 },
		{ item = "bookshelf", how = "wall", odds = 2.5 },
		{ item = "piano", how = "wall", odds = 2 },
		{ item = "floor_lamp", how = "corner", odds = 2 },
		{ item = "painting", how = "wall", odds = 1.5 },
		-- 7.x alpine pieces, a chalet's extras (the sentimental ones are no star entries: the ★ stay the house's own
		-- star pieces, these are ★ only when a house is short of them)
		{ item = "cuckoo_clock", how = "wall", odds = 4 },
		{ item = "heart_chair", how = "wall", odds = 3 },
		{ item = "accordion", how = "corner", odds = 3 },
	},
	kitchen = {
		{ item = "fridge", how = "corner", must = true },
		{ item = "dining_table", how = "middle", must = true },
		{ item = "dining_chair", how = "around", ref = "dining_table", must = true },
		{ item = "dining_chair", how = "around", ref = "dining_table", must = true },
		{ item = "dining_chair", how = "around", ref = "dining_table" },
		{ item = "dining_chair", how = "around", ref = "dining_table" },
		{ item = "microwave", how = "wall" },
		{ item = "dishes_box", how = "corner" },
		{ item = "radio", how = "wall" },
		{ item = "stein_crate", how = "corner", odds = 3 }, -- (7.x alpine)
	},
	bedroom = {
		{ item = "bed", how = "far", must = true },
		{ item = "nightstand", how = "beside", ref = "bed", must = true },
		{ item = "wardrobe", how = "wall", must = true },
		{ item = "photo_album", how = "corner", star = true },
		{ item = "nightstand", how = "beside", ref = "bed" },
		{ item = "dresser", how = "wall", odds = 1.5 },
		{ item = "mirror", how = "corner" },
		-- 7.x alpine
		{ item = "painted_cupboard", how = "wall", odds = 3 },
		{ item = "carved_chest", how = "front", ref = "bed", odds = 3 },
		{ item = "edelweiss_frame", how = "corner", odds = 3 },
	},
	kids = {
		{ item = "kids_bed", how = "far", must = true },
		{ item = "rocking_horse", how = "wall", star = true },
		{ item = "toy_box", how = "wall", odds = 1.5 },
		{ item = "desk", how = "wall" },
		{ item = "guitar", how = "corner" },
	},
	bath = {
		{ item = "washing_machine", how = "wall", must = true },
		{ item = "laundry_basket", how = "beside", ref = "washing_machine" },
	},
	garage = {
		{ item = "toolbox", how = "wall", must = true },
		{ item = "bicycle", how = "wall", must = true },
		{ item = "lawn_mower", how = "wall" },
		{ item = "box", how = "corner" },
		{ item = "box", how = "corner" },
	},
}
HouseLayout.Recipes = RECIPES
-- 8.0 collectibles (FurnitureLooks.Collectibles: the rare pieces, Config.Furniture.Collectibles the dice): how each
-- stands in its room (the room its catalogue entry names); a "beside" one whose ref is not there, or finds no place by
-- it, stands at any wall
local COLLECTIBLES: { Entry } = {
	{ item = "bowling_trophy", how = "wall" },
	{ item = "vintage_radio", how = "wall" },
	{ item = "old_globe", how = "corner" },
	{ item = "stag_head", how = "wall" },
	{ item = "gold_record", how = "wall" },
	{ item = "ship_bottle", how = "beside", ref = "desk" },
	{ item = "jewellery_box", how = "beside", ref = "dresser" },
	{ item = "antique_vase", how = "corner" },
	{ item = "arcade_cabinet", how = "wall" },
	{ item = "jukebox", how = "wall" },
	{ item = "oil_painting", how = "wall" },
	{ item = "knight_armour", how = "corner" },
	-- 8.3: twelve more (the same Count a house: a bigger pool to draw from)
	{ item = "antique_typewriter", how = "wall" },
	{ item = "vintage_camera", how = "corner" },
	{ item = "carved_bear", how = "corner" },
	{ item = "gramophone", how = "wall" },
	{ item = "pocket_watch", how = "beside", ref = "nightstand" },
	{ item = "golden_horseshoe", how = "wall" },
	{ item = "crystal_chandelier", how = "corner" },
	{ item = "alphorn", how = "wall" },
	{ item = "signed_guitar", how = "corner" },
	{ item = "ski_trophy", how = "wall" },
	{ item = "trex_skull", how = "wall" },
	{ item = "zombie_safe", how = "corner" },
}
-- 8.3: the pool a house's collectibles come from (HouseLayout.Collectibles): COLLECTIBLES' entries (their placement),
-- then every other piece of FurnitureLooks.Collectibles (one added to the catalogue joins on its own: at a wall, in its
-- catalogue room)
local POOL: { Entry } = table.clone(COLLECTIBLES)
do
	local known: { [string]: boolean } = {}
	for _, e in COLLECTIBLES do
		known[e.item] = true
	end
	for _, id in (FurnitureLooks :: any).Collectibles or {} do
		if not known[id] and FurnitureLooks.Items[id] then
			table.insert(POOL, { item = id, how = "wall" })
		end
	end
end
HouseLayout.Collectibles = POOL
-- the rooms in the order they are furnished (and their spots numbered)
local FURNISH = { "living", "kitchen", "bedroom", "kids", "bath", "garage", "hall" }
-- where a filler box goes when a house is short of pieces
local FILLER = { "garage", "living", "bedroom", "kitchen", "kids", "hall" }

-- 8.3 the big house's rooms: the house's recipes (the same entries) and its own: a living room with a few more seats and
-- lamps for its size, the guest room (a bedroom's), the study (the bookshelves, an armchair, a ★ cuckoo clock)
local BIG_LIVING: { Entry } = table.clone(RECIPES.living)
table.insert(BIG_LIVING, { item = "armchair", how = "wall", odds = 2 })
table.insert(BIG_LIVING, { item = "floor_lamp", how = "corner" })
table.insert(BIG_LIVING, { item = "plant", how = "corner", odds = 1.5 })
local BIG_RECIPES: { [string]: { Entry } } = {
	hall = RECIPES.hall,
	living = BIG_LIVING,
	kitchen = RECIPES.kitchen,
	bedroom = RECIPES.bedroom,
	kids = RECIPES.kids,
	bath = RECIPES.bath,
	garage = RECIPES.garage,
	guest = {
		{ item = "bed", how = "far", must = true },
		{ item = "nightstand", how = "beside", ref = "bed", must = true },
		{ item = "painted_cupboard", how = "wall", must = true },
		{ item = "nightstand", how = "beside", ref = "bed" },
		{ item = "carved_chest", how = "front", ref = "bed", odds = 2 },
		{ item = "dresser", how = "wall", odds = 1.5 },
		{ item = "mirror", how = "corner" },
		{ item = "edelweiss_frame", how = "corner", odds = 2 },
		{ item = "plant", how = "corner" },
	},
	study = {
		{ item = "bookshelf", how = "centre", must = true },
		{ item = "armchair", how = "facing", ref = "bookshelf", must = true },
		{ item = "floor_lamp", how = "beside", ref = "armchair" },
		{ item = "cuckoo_clock", how = "wall", star = true },
		{ item = "bookshelf", how = "wall", odds = 2 },
		{ item = "piano", how = "wall", odds = 1.5 },
		{ item = "painting", how = "wall", odds = 1.5 },
		{ item = "heart_chair", how = "wall", odds = 2 },
		{ item = "accordion", how = "corner", odds = 2 },
		{ item = "plant", how = "corner" },
	},
}
HouseLayout.BigRecipes = BIG_RECIPES

-- ── A house ─────────────────────────────────────────────────────────────────────

type RoomData = { id: string, kind: string, cell: Rect, inner: Rect }
type DoorData = { x: number, z: number, width: number, alongX: boolean, a: string, b: string? }
type FixtureData = { kind: string, room: string, x: number, y: number, z: number, w: number, h: number, d: number, turn: number, solid: boolean, rect: Rect }
type WindowData = { room: string, side: string, t: number, y: number, width: number, height: number }
type Placed = {
	item: string,
	room: string,
	x: number,
	z: number,
	turn: number,
	rect: Rect,
	h: number,
	side: string?,
	t: number?,
	must: boolean,
	star: boolean,
	order: number,
	variant: number,
	entry: Entry,
}

-- the back row's orders (left to right before a mirror) and each room's width between its walls' middles
local BACK_ORDERS = {
	{ "garage", "kids", "bath", "bedroom" },
	{ "garage", "bedroom", "bath", "kids" },
	{ "kids", "bath", "bedroom", "garage" },
	{ "bedroom", "bath", "kids", "garage" },
}
local BACK_WIDTH: { [string]: { number } } = { garage = { 16, 18 }, kids = { 16, 18 }, bath = { 11, 12 }, bedroom = { 20, 23 } }
local KIND_OF: { [string]: string } = { corridor = "hall", guest = "bedroom", study = "living" }

-- 8.3 the big house: what a kind of house is laid out from (planHouse's shape). The house's is the house as it always was
-- (the same dice in the same order); the big house's: six back rooms (the garage, its ski room, at an end), a deeper and
-- wider front row, its own recipes, counts and the back door (backDoor wide, at the corridor's east end).
type Shape = {
	kind: string,
	orders: { { string } },
	widths: { [string]: { number } },
	front: number, -- the front row's depth: front + 2 × (0 … 2)
	kitchen: number, -- the kitchen's share of the front row beside the hall: kitchen + (0 … 0.06)
	recipes: { [string]: { Entry } },
	furnish: { string },
	filler: { string },
	spots: { number },
	stars: number,
	collectibles: { number },
	legendary: number,
	backDoor: number?,
	roomy: number?, -- 8.5.2: the rooms', the hall's and the corridor's sizes × this (the big house's Config.Furniture.Big.Roomy)
	found: { [string]: any }?, -- 8.3 economy: the move owner's book (HouseLayout.plan's `found`)
}
local BIG_CONFIG = (T :: any).Big
local SHAPES: { [string]: Shape } = {
	house = {
		kind = "house",
		orders = BACK_ORDERS,
		widths = BACK_WIDTH,
		front = 24,
		kitchen = 0.44,
		recipes = RECIPES,
		furnish = FURNISH,
		filler = FILLER,
		spots = T.Spots,
		stars = T.Stars,
		collectibles = T.Collectibles.Count,
		legendary = T.Collectibles.Legendary,
		backDoor = nil,
	},
	big = {
		kind = "big",
		orders = {
			{ "garage", "kids", "bath", "guest", "study", "bedroom" },
			{ "garage", "study", "bedroom", "bath", "guest", "kids" },
			{ "kids", "bath", "bedroom", "study", "guest", "garage" },
			{ "bedroom", "guest", "bath", "kids", "study", "garage" },
		},
		widths = { garage = { 16, 18 }, kids = { 16, 18 }, bath = { 11, 12 }, bedroom = { 20, 23 }, guest = { 17, 19 }, study = { 16, 18 } },
		front = BIG_CONFIG.Front,
		kitchen = BIG_CONFIG.Kitchen,
		recipes = BIG_RECIPES,
		furnish = { "living", "kitchen", "bedroom", "guest", "study", "kids", "bath", "garage", "hall" },
		filler = { "garage", "living", "study", "bedroom", "guest", "kitchen", "kids", "hall" },
		spots = BIG_CONFIG.Spots,
		stars = BIG_CONFIG.Stars,
		collectibles = BIG_CONFIG.Collectibles.Count,
		legendary = BIG_CONFIG.Collectibles.Legendary,
		backDoor = BIG_CONFIG.BackDoor,
	},
}

-- A side of a room: the wall at its min Z ("S"), max Z ("N"), min X ("W"), max X ("E"); a piece with its back to it
-- turns `turn` degrees and faces (fx, fz) into the room.
local SIDE_TURN: { [string]: number } = { S = 180, N = 0, W = 270, E = 90 }
local SIDE_FACE: { [string]: { number } } = { S = { 0, 1 }, N = { 0, -1 }, W = { 1, 0 }, E = { -1, 0 } }
local OPPOSITE: { [string]: string } = { S = "N", N = "S", W = "E", E = "W" }
local SIDES = { "S", "N", "W", "E" }

-- Against `side` of the inner rect, `t` along the wall: a footprint w along the wall, d deep, `gap` off the wall.
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

-- The span along a side of the inner rect.
local function span(inner: Rect, side: string): (number, number)
	if side == "S" or side == "N" then
		return inner.x0, inner.x1
	end
	return inner.z0, inner.z1
end

-- 8.3 economy: a shuffled list of collectibles with the ones not in `found` first (each part in its shuffled order).
-- 8.7 review: a page marked bought is no find (the book's own rule: CollectionBookRules.isFound).
local function unfoundFirst(list: { Entry }, found: { [string]: any }?): { Entry }
	if not found then
		return list
	end
	local fresh: { Entry } = {}
	local seen: { Entry } = {}
	for _, e in list do
		local page = found[e.item]
		table.insert(if page and not (type(page) == "table" and page.bought == true) then seen else fresh, e)
	end
	table.move(seen, 1, #seen, #fresh + 1, fresh)
	return fresh
end

local function planHouse(seed: number, shape: Shape): Plan
	local rng = newRng(seed)
	local W_ = T.Wall
	local HALF_WALL = W_ / 2
	local RECIPES = shape.recipes -- (8.3: the big house's own; the house's the same as ever)

	-- The shell: a front row (kitchen, the entrance hall with the front door, the living room), the corridor across
	-- the house, a back row (garage, kids' room, bathroom, bedroom in one of four orders; 8.3 the big house: six rooms), then
	-- maybe mirrored.
	-- (8.5.2, the owner: "more room in the house": the big house's rooms, its hall and its corridor `roomy` times as wide
	-- and deep, whole studs; the same dice, the doors and the furniture as they were: only the room round them grows)
	local roomy = shape.roomy or 1
	local function grow(n: number): number
		return if roomy == 1 then n else math.floor(n * roomy + 0.5)
	end
	local order = shape.orders[rng.int(1, #shape.orders)]
	local widths: { [string]: number } = {}
	local W = 0
	for _, id in order do
		local range = shape.widths[id]
		widths[id] = grow(rng.int(range[1], range[2]))
		W += widths[id]
	end
	local F = grow(shape.front + 2 * rng.int(0, 2))
	local C = grow(T.Corridor)
	local B = grow(22 + 2 * rng.int(0, 1))
	local D = F + C + B
	local hallWide = grow(T.HallWidth)
	local half = hallWide / 2
	local rest = W - hallWide
	local kw = math.floor(rest * (shape.kitchen + rng.num() * 0.06) + 0.5)
	local lw = rest - kw
	local x0, x1 = -half - kw, half + lw

	local rooms: { RoomData } = {}
	local byId: { [string]: RoomData } = {}
	local function addRoom(id: string, cell: Rect)
		local room: RoomData = { id = id, kind = KIND_OF[id] or id, cell = cell, inner = cell }
		table.insert(rooms, room)
		byId[id] = room
	end
	addRoom("hall", rect(-half, 0, half, F))
	addRoom("living", rect(half, 0, x1, F))
	addRoom("kitchen", rect(x0, 0, -half, F))
	addRoom("corridor", rect(x0, F, x1, F + C))
	local cursor = x0
	for _, id in order do
		addRoom(id, rect(cursor, F + C, cursor + widths[id], D))
		cursor += widths[id]
	end

	local doors: { DoorData } = {}
	local function addDoor(x: number, z: number, width: number, alongX: boolean, a: string, b: string?)
		table.insert(doors, { x = x, z = z, width = width, alongX = alongX, a = a, b = b })
	end
	addDoor(0, 0, T.FrontDoor, true, "hall", nil)
	addDoor(-half, F / 2 + rng.int(-3, 3), T.Door, false, "hall", "kitchen")
	addDoor(half, F / 2 + rng.int(-3, 3), T.FrontDoor, false, "hall", "living")
	addDoor(0, F, T.HallOpening, true, "hall", "corridor")
	addDoor(rng.int(x0 + 8, -half - 5), F, T.Door, true, "kitchen", "corridor")
	addDoor(rng.int(half + 5, x1 - 5), F, T.Door, true, "living", "corridor")
	for _, id in order do
		local cell = byId[id].cell
		local width = if id == "garage" then T.FrontDoor else T.Door
		local margin = width / 2 + 1.5
		addDoor(rng.int(math.ceil(cell.x0 + margin), math.floor(cell.x1 - margin)), F + C, width, true, "corridor", id)
	end

	-- The mirror (left and right swapped): the kitchen on the other side, the back row reversed.
	local mirrored = rng.num() < 0.5
	if mirrored then
		x0, x1 = -x1, -x0
		for _, room in rooms do
			room.cell = rect(-room.cell.x1, room.cell.z0, -room.cell.x0, room.cell.z1)
		end
		for _, door in doors do
			door.x = -door.x
		end
	end
	if shape.backDoor then
		-- 8.3 the big house: the back door, a second way out, in the corridor's east end (+X, mirrored or not)
		addDoor(x1, F + C / 2, shape.backDoor, false, "corridor", nil)
	end
	for _, room in rooms do
		local c = room.cell
		room.inner = rect(c.x0 + HALF_WALL, c.z0 + HALF_WALL, c.x1 - HALF_WALL, c.z1 - HALF_WALL)
	end
	local house = rect(x0, 0, x1, D)

	-- Is a side of a room on the house's outside?
	local function outer(room: RoomData, side: string): boolean
		local c = room.cell
		if side == "S" then
			return c.z0 <= house.z0
		elseif side == "N" then
			return c.z1 >= house.z1
		elseif side == "W" then
			return c.x0 <= house.x0
		end
		return c.x1 >= house.x1
	end
	-- The doorways in a side of a room: { from, to } along it.
	local function openings(room: RoomData, side: string): { { number } }
		local c = room.cell
		local line = if side == "S" then c.z0 elseif side == "N" then c.z1 elseif side == "W" then c.x0 else c.x1
		local alongX = side == "S" or side == "N"
		local out: { { number } } = {}
		for _, door in doors do
			if door.alongX == alongX and (door.a == room.id or door.b == room.id) then
				local at = if alongX then door.z else door.x
				local t = if alongX then door.x else door.z
				if math.abs(at - line) < 1e-6 then
					table.insert(out, { t - door.width / 2, t + door.width / 2 })
				end
			end
		end
		table.sort(out, function(a: { number }, b: { number }): boolean
			return a[1] < b[1]
		end)
		return out
	end

	-- The walls: every room side as slabs (its half of a shared wall, the whole of an outer one), cut at the doorways,
	-- with the wall over every doorway.
	local faces: { Face } = {}
	local wallRects: { Rect } = {}
	local ceiling = T.Ceiling
	for _, room in rooms do
		local c = room.cell
		for _, side in SIDES do
			local isOuter = outer(room, side)
			local alongX = side == "S" or side == "N"
			local line = if side == "S" then c.z0 elseif side == "N" then c.z1 elseif side == "W" then c.x0 else c.x1
			local a, b = if alongX then c.x0 else c.z0, if alongX then c.x1 else c.z1
			local lo = if alongX then house.x0 else house.z0
			local hi = if alongX then house.x1 else house.z1
			-- across the wall: the slab's two faces
			local inward = if side == "S" or side == "W" then 1 else -1
			local p0, p1
			if isOuter then
				p0, p1 = line - HALF_WALL, line + HALF_WALL
			else
				p0, p1 = line, line + inward * HALF_WALL
			end
			local normal = Vector3.new(if alongX then 0 else inward, 0, if alongX then inward else 0)
			local function slab(s0: number, s1: number, y0: number, y1: number, header: boolean)
				local r = if alongX then rect(s0, p0, s1, p1) else rect(p0, s0, p1, s1)
				table.insert(faces, {
					room = room.id,
					min = Vector3.new(r.x0, y0, r.z0),
					max = Vector3.new(r.x1, y1, r.z1),
					normal = normal,
					outer = isOuter,
					header = header,
				})
				if not header then
					table.insert(wallRects, r)
				end
			end
			local from = a
			for _, gap in openings(room, side) do
				if gap[1] > from + 1e-6 then
					slab(if isOuter and from <= lo + 1e-6 then from - HALF_WALL else from, gap[1], 0, ceiling, false)
				end
				slab(gap[1], gap[2], T.DoorHeight, ceiling, true)
				from = gap[2]
			end
			if b > from + 1e-6 then
				slab(if isOuter and from <= lo + 1e-6 then from - HALF_WALL else from, if isOuter and b >= hi - 1e-6 then b + HALF_WALL else b, 0, ceiling, false)
			end
		end
	end

	-- Kept clear: in front of every doorway, DoorClear deep into each room it joins.
	local zones: { [string]: { Rect } } = {}
	for _, room in rooms do
		zones[room.id] = {}
	end
	for _, door in doors do
		local joined: { string } = { door.a }
		if door.b then
			table.insert(joined, door.b)
		end
		for _, id in joined do
			local room = byId[id]
			if room then
				local w = door.width / 2 + 0.5
				if door.alongX then
					local into = if (room.cell.z0 + room.cell.z1) / 2 > door.z then 1 else -1
					local face = door.z + into * HALF_WALL
					table.insert(zones[room.id], rect(door.x - w, face, door.x + w, face + into * T.DoorClear))
				else
					local into = if (room.cell.x0 + room.cell.x1) / 2 > door.x then 1 else -1
					local face = door.x + into * HALF_WALL
					table.insert(zones[room.id], rect(face, door.z - w, face + into * T.DoorClear, door.z + w))
				end
			end
		end
	end

	-- ── The fixtures ───────────────────────────────────────────────────────────
	local fixtures: { FixtureData } = {}
	local function fixture(kind: string, room: RoomData, side: string, t: number, w: number, h: number, d: number, y: number, solid: boolean): FixtureData
		local x, z, r = against(room.inner, side, t, w, d, 0)
		local f: FixtureData = { kind = kind, room = room.id, x = x, y = y, z = z, w = w, h = h, d = d, turn = SIDE_TURN[side], solid = solid, rect = r }
		table.insert(fixtures, f)
		return f
	end
	local function flat(kind: string, room: RoomData, x: number, z: number, w: number, d: number, turn: number)
		table.insert(fixtures, { kind = kind, room = room.id, x = x, y = 0, z = z, w = w, h = 0.08, d = d, turn = turn, solid = false, rect = rect(x - w / 2, z - d / 2, x + w / 2, z + d / 2) })
	end
	-- the side of a room away from the house's middle (its outer side wall)
	local function outerSide(room: RoomData): string
		return if (room.cell.x0 + room.cell.x1) / 2 < 0 then "W" else "E"
	end
	local windows: { WindowData } = {}
	local function window(room: RoomData, side: string, t: number, size: { number }, sill: number)
		table.insert(windows, { room = room.id, side = side, t = t, y = sill + size[2] / 2, width = size[1], height = size[2] })
	end

	-- the kitchen: an L of counters in its front outer corner (the stove on the side run, the sink under the front
	-- window), wall cupboards and the hood over the side run
	do
		local k = byId.kitchen
		local side = outerSide(k)
		local inner = k.inner
		local depth = 2.6
		local z0 = inner.z0
		fixture("counter", k, side, z0 + 2.25, 4.5, 3, depth, 0, true)
		fixture("stove", k, side, z0 + 6, 3, 3, depth, 0, true)
		fixture("counter", k, side, z0 + 9.75, 4.5, 3, depth, 0, true)
		fixture("cabinets", k, side, z0 + 2.25, 4.5, 3, 1.4, 6.4, false)
		fixture("hood", k, side, z0 + 6, 3, 2.2, 1.8, 7.0, false)
		fixture("cabinets", k, side, z0 + 9.75, 4.5, 3, 1.4, 6.4, false)
		local dir = if side == "W" then 1 else -1
		local start = (if side == "W" then inner.x0 else inner.x1) + dir * depth
		fixture("sink", k, "S", start + dir * 4.5, 9, 3, depth, 0, true) -- (7.x alpine: one run, the sink in its middle)
		window(k, "S", start + dir * 4.5, T.Window, T.WindowSill)
		-- 7.x alpine: the corner bench (Eckbank) in the back outer corner, its long leg on the outer wall, its short leg
		-- on the back wall (clear of the doorway to the corridor: that is at least 8 from the outer wall), and over it
		-- the Herrgottswinkel's corner shelf (its corner at its +X, +Z: against the outer wall when that is W, else
		-- against the back wall)
		local bench = A.Bench
		fixture("corner_bench", k, side, inner.z1 - bench[1] / 2, bench[1], bench[4], bench[3], 0, true)
		local short = if side == "W" then inner.x0 + bench[3] + bench[2] / 2 else inner.x1 - bench[3] - bench[2] / 2
		fixture("bench", k, "N", short, bench[2], bench[4], bench[3], 0, true)
		local shelf = A.Shelf
		if side == "W" then
			fixture("corner_shelf", k, "W", inner.z1 - shelf[1] / 2, shelf[1], 1.4, shelf[1], shelf[2], false)
		else
			fixture("corner_shelf", k, "N", inner.x1 - shelf[1] / 2, shelf[1], 1.4, shelf[1], shelf[2], false)
		end
	end
	-- the bathroom: the tub across its back corner, the toilet on the far side wall, the basin and mirror on the other
	do
		local bath = byId.bath
		local inner = bath.inner
		local left = rng.num() < 0.5
		local tubAt = if left then inner.x0 + 3.6 else inner.x1 - 3.6
		fixture("tub", bath, "N", tubAt, 7.2, 2.2, 3.4, 0, true)
		local toiletSide = if left then "E" else "W"
		fixture("toilet", bath, toiletSide, inner.z1 - 3.4 - 1.2, 1.8, 3.2, 2.8, 0, true)
		local basinSide = if left then "W" else "E"
		fixture("basin", bath, basinSide, (inner.z0 + inner.z1) / 2 - 1, 2.6, 3.2, 1.8, 0, true)
		window(bath, "N", tubAt, T.BathWindow, 6.5)
		flat("mat", bath, tubAt, inner.z1 - 3.4 - 1.6, 3.4, 2.0, 0)
	end
	-- the garage: its door in the outer side wall, the workbench and shelves on the back wall, an oil stain
	do
		local g = byId.garage
		local inner = g.inner
		local side = outerSide(g)
		local mid = (inner.z0 + inner.z1) / 2
		fixture("garage_door", g, side, mid, math.min(12, inner.z1 - inner.z0 - 8), 8.5, 0.3, 0, false)
		local outerEnd = if side == "W" then inner.x0 else inner.x1
		local innerEnd = if side == "W" then inner.x1 else inner.x0
		local dir = if side == "W" then 1 else -1
		fixture("workbench", g, "N", outerEnd + dir * 3.4, 6.4, 3.2, 2.4, 0, true)
		fixture("shelves", g, "N", innerEnd - dir * 2.8, 5, 7, 1.6, 0, true)
		flat("stain", g, (inner.x0 + inner.x1) / 2, mid + 1, 4, 3, 0)
	end
	-- the living room: the Kachelofen on its outer side wall (7.x alpine: a chalet's tiled stove took the fireplace's
	-- place and its dice): in the middle, else in the front corner with a window in the middle
	local stoveMiddle = rng.num() < 0.6
	do
		local lv = byId.living
		local inner = lv.inner
		local side = outerSide(lv)
		local mid = (inner.z0 + inner.z1) / 2
		local stove = A.Stove
		if stoveMiddle then
			fixture("kachelofen", lv, side, mid, stove[1], stove[2], stove[3], 0, true)
		else
			fixture("kachelofen", lv, side, inner.z0 + stove[1] / 2, stove[1], stove[2], stove[3], 0, true)
			window(lv, side, mid, T.Window, T.WindowSill)
		end
	end
	-- (the hall: its runner from inside the front door; 7.x alpine: no doormat inside any more, the porch has one)

	-- The windows on the outer walls: the front of the living room (two if it is wide), the back of every back room
	-- but the garage and the bath (it has its own), the outer sides of the back row's end rooms and the corridor's ends.
	do
		local lv = byId.living
		local a, b = span(lv.inner, "S")
		if b - a >= 22 then
			window(lv, "S", a + (b - a) / 3, T.Window, T.WindowSill)
			window(lv, "S", a + (b - a) * 2 / 3, T.Window, T.WindowSill)
		else
			window(lv, "S", (a + b) / 2, T.Window, T.WindowSill)
		end
		for _, id in order do
			local room = byId[id]
			if id ~= "garage" and id ~= "bath" then
				local a2, b2 = span(room.inner, "N")
				window(room, "N", (a2 + b2) / 2, T.Window, T.WindowSill)
				for _, side in { "W", "E" } do
					if outer(room, side) then
						local a3, b3 = span(room.inner, side)
						window(room, side, (a3 + b3) / 2, T.Window, T.WindowSill)
					end
				end
			end
		end
		local corridor = byId.corridor
		for _, side in { "W", "E" } do
			if side == "E" and shape.backDoor then
				continue -- (8.3 the big house: the back door there)
			end
			local a4, b4 = span(corridor.inner, side)
			window(corridor, side, (a4 + b4) / 2, { 3, T.Window[2] }, T.WindowSill)
		end
	end
	-- in front of a window (tall pieces keep off)
	local windowZones: { [string]: { Rect } } = {}
	for _, room in rooms do
		windowZones[room.id] = {}
	end
	for _, w in windows do
		local room = byId[w.room]
		local _, _, r = against(room.inner, w.side, w.t, w.width + 1, 3, 0)
		table.insert(windowZones[w.room], r)
	end

	-- ── The pieces ─────────────────────────────────────────────────────────────
	local placed: { Placed } = {}
	local counter = 0
	local function solidsIn(roomId: string): { Rect }
		local out: { Rect } = {}
		for _, f in fixtures do
			if f.solid and f.room == roomId then
				table.insert(out, f.rect)
			end
		end
		return out
	end
	-- places a piece got stuck in (it is placed again elsewhere): room/item → footprints
	local banned: { [string]: { Rect } } = {}
	local placing = ""
	local function fits(room: RoomData, r: Rect, h: number): boolean
		if not within(r, room.inner) then
			return false
		end
		local ban = banned[room.id .. "/" .. placing]
		if ban then
			for _, b in ban do
				if hits(r, b, 0) then
					return false
				end
			end
		end
		for _, z in zones[room.id] do
			if hits(r, z, 0) then
				return false
			end
		end
		for _, f in solidsIn(room.id) do
			if hits(r, f, T.FixtureGap) then
				return false
			end
		end
		for _, p in placed do
			if p.room == room.id and hits(r, p.rect, T.Gap) then
				return false
			end
		end
		if h > T.WindowSill then
			for _, z in windowZones[room.id] do
				if hits(r, z, 0) then
					return false
				end
			end
		end
		return true
	end
	type Cand = { x: number, z: number, turn: number, rect: Rect, side: string?, t: number?, score: number }
	-- Every place against a wall of the room a piece fits, scored by `score(side, t, lo, hi)` (lower is better).
	local function wallSpots(room: RoomData, id: string, score: (string, number, number, number) -> number): { Cand }
		local def = FurnitureLooks.Items[id]
		local w, d, h = def.size.X, def.size.Z, def.size.Y
		local out: { Cand } = {}
		for _, side in SIDES do
			local lo, hi = span(room.inner, side)
			local t = lo + w / 2 + T.WallGap
			while t <= hi - w / 2 - T.WallGap + 1e-6 do
				local x, z, r = against(room.inner, side, t, w, d, T.WallGap)
				if fits(room, r, h) then
					table.insert(out, { x = x, z = z, turn = SIDE_TURN[side], rect = r, side = side, t = t, score = score(side, t, lo, hi) })
				end
				t += 0.5
			end
		end
		return out
	end
	-- The best few candidates (lowest score), one of them by the dice.
	local function choose(cands: { Cand }, spread: number): Cand?
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
		return cands[rng.int(1, n)]
	end
	local function find(roomId: string, id: string): Placed?
		for _, p in placed do
			if p.room == roomId and p.item == id then
				return p
			end
		end
		return nil
	end
	local function free(x: number, z: number, turn: number, id: string): Rect
		local ex, ez = HouseLayout.extent(id, turn)
		return rect(x - ex / 2, z - ez / 2, x + ex / 2, z + ez / 2)
	end

	local function candidates(room: RoomData, e: Entry): Cand?
		local def = FurnitureLooks.Items[e.item]
		local h = def.size.Y
		local how = e.how
		local ref = if e.ref then find(room.id, e.ref) else nil
		if e.ref and not ref and how ~= "around" then
			how = "wall"
		end
		if how == "wall" then
			return choose(wallSpots(room, e.item, function(): number
				return 0
			end), 0)
		elseif how == "corner" then
			return choose(wallSpots(room, e.item, function(_: string, t: number, lo: number, hi: number): number
				return math.min(t - lo, hi - t)
			end), 0.6)
		elseif how == "centre" then
			return choose(wallSpots(room, e.item, function(_: string, t: number, lo: number, hi: number): number
				return math.abs(t - (lo + hi) / 2) - (hi - lo) * 0.5
			end), 1)
		elseif how == "far" then
			-- across from the room's door (its first one)
			local doorSide = "S"
			for _, door in doors do
				if door.a == room.id or door.b == room.id then
					if door.alongX then
						doorSide = if math.abs(door.z - room.cell.z0) < 1e-6 then "S" else "N"
					else
						doorSide = if math.abs(door.x - room.cell.x0) < 1e-6 then "W" else "E"
					end
					break
				end
			end
			local far = OPPOSITE[doorSide]
			return choose(wallSpots(room, e.item, function(side: string, t: number, lo: number, hi: number): number
				return (if side == far then 0 else 100) + math.abs(t - (lo + hi) / 2)
			end), 1)
		elseif how == "facing" and ref and ref.side and ref.t then
			local across = OPPOSITE[ref.side]
			local target = ref.t
			return choose(wallSpots(room, e.item, function(side: string, t: number): number
				return (if side == across then 0 else 100) + math.abs(t - target)
			end), 0.5)
		elseif how == "beside" and ref and ref.side and ref.t then
			local w, d = def.size.X, def.size.Z
			local refW = FurnitureLooks.Items[ref.item].size.X
			local sides = { -1, 1 }
			shuffle(sides, rng)
			for _, s in sides do
				local t = ref.t + s * (refW / 2 + T.Gap + 0.05 + w / 2)
				local x, z, r = against(room.inner, ref.side, t, w, d, T.WallGap)
				if fits(room, r, h) then
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
				local r = free(x, z, ref.turn, e.item)
				if fits(room, r, h) then
					return { x = x, z = z, turn = ref.turn, rect = r, score = 0 }
				end
			end
			return nil
		elseif how == "middle" then
			-- free-standing, its long side along the room's long side, room round it for chairs and a way past
			local inner = room.inner
			local long = (inner.x1 - inner.x0) >= (inner.z1 - inner.z0)
			local turn = if long then 0 else 90
			local ex, ez = HouseLayout.extent(e.item, turn)
			local laneLong, laneEnd = 3.8, 2.5
			local cx, cz = (inner.x0 + inner.x1) / 2, (inner.z0 + inner.z1) / 2
			local cands: { Cand } = {}
			local x = inner.x0 + ex / 2
			while x <= inner.x1 - ex / 2 do
				local z = inner.z0 + ez / 2
				while z <= inner.z1 - ez / 2 do
					local r = free(x, z, turn, e.item)
					local around = if long
						then rect(r.x0 - laneEnd, r.z0 - laneLong, r.x1 + laneEnd, r.z1 + laneLong)
						else rect(r.x0 - laneLong, r.z0 - laneEnd, r.x1 + laneLong, r.z1 + laneEnd)
					if fits(room, around, h) then
						table.insert(cands, { x = x, z = z, turn = turn, rect = r, score = math.abs(x - cx) + math.abs(z - cz) })
					end
					z += 1
				end
				x += 1
			end
			return choose(cands, 1)
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
			-- facing each other first
			for _, n in { 1, 3, 2, 4 } do
				local seat = seats[n]
				local r = free(seat[1], seat[2], seat[3], e.item)
				if fits(room, r, h) then
					return { x = seat[1], z = seat[2], turn = seat[3], rect = r, score = 0 }
				end
			end
			return nil
		end
		return choose(wallSpots(room, e.item, function(): number
			return 0
		end), 0)
	end

	local function place(roomId: string, e: Entry, must: boolean, star: boolean): Placed?
		local room = byId[roomId]
		placing = e.item
		local c = candidates(room, e)
		if not c then
			return nil
		end
		counter += 1
		local p: Placed = {
			item = e.item,
			room = roomId,
			x = c.x,
			z = c.z,
			turn = norm(c.turn),
			rect = c.rect,
			h = FurnitureLooks.Items[e.item].size.Y,
			side = c.side,
			t = c.t,
			must = must,
			star = star,
			order = counter,
			variant = rng.int(1, 12),
			entry = e,
		}
		table.insert(placed, p)
		return p
	end

	-- the ★ pieces: Stars of the sentimental ones, by the dice
	type Pick = { room: string, entry: Entry }
	local sentimental: { Pick } = {}
	for _, roomId in shape.furnish do
		for _, e in RECIPES[roomId] do
			if e.star then
				table.insert(sentimental, { room = roomId, entry = e })
			end
		end
	end
	shuffle(sentimental, rng)
	local starred: { [Entry]: boolean } = {}
	for n = 1, math.min(shape.stars, #sentimental) do
		starred[sentimental[n].entry] = true
	end
	local target = rng.int(shape.spots[1], shape.spots[2])
	-- the musts, then the ★ ones, then the rest in a shuffled order until the house holds `target` pieces
	local optional: { Pick } = {}
	for _, roomId in shape.furnish do
		for _, e in RECIPES[roomId] do
			if e.must then
				place(roomId, e, true, false)
			elseif not e.star then
				table.insert(optional, { room = roomId, entry = e })
			end
		end
	end
	for _, roomId in shape.furnish do
		for _, e in RECIPES[roomId] do
			if starred[e] then
				place(roomId, e, true, true)
			end
		end
	end
	-- a weighted shuffle: the higher an entry's odds, the earlier it tends to come
	local keys: { [Pick]: number } = {}
	for _, pick in optional do
		keys[pick] = rng.num() ^ (1 / (pick.entry.odds or 1))
	end
	table.sort(optional, function(a: Pick, b: Pick): boolean
		return keys[a] > keys[b]
	end)
	for _, pick in optional do
		if #placed >= target then
			break
		end
		place(pick.room, pick.entry, false, false)
	end

	-- Every piece must get out: drop what blocks (the latest optional piece of the room, else the stuck piece itself).
	local doorway = rect(-T.FrontDoor / 2, -HALF_WALL, T.FrontDoor / 2, HALF_WALL)
	local solidRects = table.clone(wallRects)
	for _, f in fixtures do
		if f.solid then
			table.insert(solidRects, f.rect)
		end
	end
	local field = newField(rect(house.x0 - HALF_WALL, -HALF_WALL, house.x1 + HALF_WALL, house.z1 + HALF_WALL), solidRects, doorway)
	-- (8.3 the big house: the back door's way out is checked once every piece stands, below: the field of its own here)
	local backField = if shape.backDoor
		then newField(
			rect(house.x0 - HALF_WALL, -HALF_WALL, house.x1 + HALF_WALL, house.z1 + HALF_WALL),
			solidRects,
			rect(x1 - HALF_WALL, F + C / 2 - shape.backDoor / 2, x1 + HALF_WALL, F + C / 2 + shape.backDoor / 2)
		)
		else nil
	local function stuckNow(other: Field?): { number }
		local rects, radii = {}, {}
		for _, p in placed do
			table.insert(rects, p.rect)
			table.insert(radii, radiusOf(p.item))
		end
		return stuckOf(other or field, rects, radii)
	end
	for _ = 1, 16 do
		local stuck = stuckNow()
		if #stuck == 0 then
			break
		end
		local victim = placed[stuck[1]]
		local latest: Placed? = nil
		if victim.must then
			for _, p in placed do
				if p.room == victim.room and not p.must and (latest == nil or p.order > latest.order) then
					latest = p
				end
			end
		end
		if latest then
			table.remove(placed, table.find(placed, latest) :: number)
		else
			-- a must or ★ piece goes elsewhere in its room (not where it got stuck), an optional one goes
			table.remove(placed, table.find(placed, victim) :: number)
			if victim.must then
				local key = victim.room .. "/" .. victim.item
				banned[key] = banned[key] or {}
				table.insert(banned[key], victim.rect)
				local again = place(victim.room, victim.entry, true, victim.star)
				if again then
					again.order = victim.order
				end
			end
		end
	end
	-- still stuck after that: out with it
	local stuck = stuckNow()
	for n = #stuck, 1, -1 do
		table.remove(placed, stuck[n])
	end
	-- too few pieces: moving boxes where they fit (and can get out)
	local fill = 1
	while #placed < shape.spots[1] and fill <= #shape.filler * 3 do
		local roomId = shape.filler[(fill - 1) % #shape.filler + 1]
		fill += 1
		local p = place(roomId, { item = "box", how = "corner" }, false, false)
		if p and #stuckNow() > 0 then
			table.remove(placed, table.find(placed, p) :: number)
		end
	end
	-- exactly Stars ★: the sentimental pieces first (the star entries, then a sentimental extra: 7.x alpine), then the
	-- dearest
	local stars = 0
	for _, p in placed do
		if p.star then
			stars += 1
		end
	end
	if stars < shape.stars then
		local byValue = table.clone(placed)
		table.sort(byValue, function(a: Placed, b: Placed): boolean
			local da, db = FurnitureLooks.Items[a.item], FurnitureLooks.Items[b.item]
			if da.sentimental ~= db.sentimental then
				return da.sentimental
			end
			local va, vb = da.value, db.value
			if va ~= vb then
				return va > vb
			end
			return a.order < b.order
		end)
		for _, p in byValue do
			if stars >= shape.stars then
				break
			end
			if not p.star then
				p.star = true
				stars += 1
			end
		end
	end

	-- 8.0 collectibles: Collectibles.Count of the rare pieces, after the house's own pieces and its ★ (those stay as they
	-- were; a collectible is never ★), on their own dice: a legendary one in about one house of 25 (Legendary), the
	-- others' rarities by their Odds; each in its own room, none twice. A piece that finds no place there (or whose
	-- place would keep a piece from getting out) gives way to another of its rarity, else of the rarity below. (8.3: the
	-- big house's count and legendary chance its own; drawn from HouseLayout.Collectibles, only pieces of a room the house
	-- has)
	do
		local rules = T.Collectibles
		local rarities = FurnitureLooks.Rarities
		local dice = newRng(seed + rules.Salt)
		local want = dice.int(shape.collectibles[1], shape.collectibles[2])
		local tiers: { string } = {}
		if dice.num() < shape.legendary then
			table.insert(tiers, "legendary")
		end
		local total = 0
		for _, rarity in rarities do
			total += rules.Odds[rarity] or 0
		end
		while #tiers < want do
			local roll = dice.num() * total
			local got = rarities[1]
			for _, rarity in rarities do
				local odds = rules.Odds[rarity] or 0
				if odds > 0 then
					got = rarity
					if roll < odds then
						break
					end
					roll -= odds
				end
			end
			table.insert(tiers, got)
		end
		-- the pieces of each rarity, in an order of the dice
		local byRarity: { [string]: { Entry } } = {}
		for _, rarity in rarities do
			local list: { Entry } = {}
			for _, e in POOL do
				local def = FurnitureLooks.Items[e.item]
				if def.rarity == rarity and byId[def.room] then
					table.insert(list, e)
				end
			end
			shuffle(list, dice)
			byRarity[rarity] = if rarity == "legendary" then unfoundFirst(list, shape.found) else list -- (8.3 economy)
		end
		local tried: { [string]: boolean } = {}
		local count = 0
		-- in its room as it stands there (else at a wall), somewhere every piece still gets out from
		local function put(e: Entry): boolean
			tried[e.item] = true
			local room = FurnitureLooks.Items[e.item].room
			local ways: { Entry } = { e }
			if e.how ~= "wall" then
				table.insert(ways, { item = e.item, how = "wall" })
			end
			for _, way in ways do
				for _ = 1, 3 do
					local p = place(room, way, false, false)
					if not p then
						break
					end
					if #stuckNow() == 0 then
						count += 1
						return true
					end
					table.remove(placed, table.find(placed, p) :: number)
					local key = room .. "/" .. e.item
					banned[key] = banned[key] or {}
					table.insert(banned[key], p.rect)
				end
			end
			return false
		end
		for _, tier in tiers do
			local done = false
			for level = table.find(rarities, tier) :: number, 1, -1 do
				for _, e in byRarity[rarities[level]] do
					if not tried[e.item] and put(e) then
						done = true
						break
					end
				end
				if done then
					break
				end
			end
		end
		-- (too few that fit: any other but a legendary one, the commonest first)
		for _, rarity in rarities do
			for _, e in byRarity[rarity] do
				if count >= shape.collectibles[1] or rarity == "legendary" then
					break
				end
				if not tried[e.item] then
					put(e)
				end
			end
		end
	end
	-- 8.3 the big house: every piece gets out of the back door too. Its way is the corridor, which a piece that gets to the
	-- front door nearly always has (the rooms open onto it), so this looks once every piece stands; a piece that cannot
	-- get there clears its way as the front door's loop does: the latest optional piece of its room goes, else itself.
	if backField then
		for _ = 1, 8 do
			local behind = stuckNow(backField)
			if #behind == 0 then
				break
			end
			local victim = placed[behind[1]]
			local latest: Placed? = nil
			for _, p in placed do
				if p ~= victim and p.room == victim.room and not p.must and not p.star and (latest == nil or p.order > latest.order) then
					latest = p
				end
			end
			table.remove(placed, table.find(placed, latest or victim) :: number)
		end
	end

	-- Rugs: under the coffee table, at the foot of the bed, a round one in the kids' room, a runner down the hall.
	do
		local function rug(kind: string, roomId: string, x: number, z: number, w: number, d: number, turn: number)
			local inner = byId[roomId].inner
			local ex, ez = if norm(turn) % 180 == 0 then w else d, if norm(turn) % 180 == 0 then d else w
			-- kept inside the room
			local hx, hz = math.min(ex / 2, (inner.x1 - inner.x0) / 2 - 0.6), math.min(ez / 2, (inner.z1 - inner.z0) / 2 - 0.6)
			x = math.clamp(x, inner.x0 + 0.6 + hx, inner.x1 - 0.6 - hx)
			z = math.clamp(z, inner.z0 + 0.6 + hz, inner.z1 - 0.6 - hz)
			local rw, rd = if norm(turn) % 180 == 0 then hx * 2 else hz * 2, if norm(turn) % 180 == 0 then hz * 2 else hx * 2
			table.insert(fixtures, { kind = kind, room = roomId, x = x, y = 0, z = z, w = rw, h = 0.08, d = rd, turn = turn, solid = false, rect = rect(x - hx, z - hz, x + hx, z + hz) })
		end
		local table_ = find("living", "coffee_table")
		local sofa = find("living", "sofa")
		if table_ and sofa and sofa.side then
			local face = SIDE_FACE[sofa.side]
			rug("rug", "living", table_.x - face[1] * 0.6, table_.z - face[2] * 0.6, 8.4, 6.4, sofa.turn)
		end
		for _, roomId in { "bedroom", "guest" } do -- (8.3: the big house's guest room too)
			local bed = if byId[roomId] then find(roomId, "bed") else nil
			if bed and bed.side then
				local face = SIDE_FACE[bed.side]
				rug("rug", roomId, bed.x + face[1] * 3.2, bed.z + face[2] * 3.2, 8, 4.4, bed.turn)
			end
		end
		local kids = byId.kids.inner
		rug("round_rug", "kids", (kids.x0 + kids.x1) / 2, (kids.z0 + kids.z1) / 2, 6, 6, 0)
		local hall = byId.hall.inner
		rug("runner", "hall", 0, (hall.z0 + 4 + hall.z1 - 3) / 2, 3.6, hall.z1 - hall.z0 - 7, 0)
		local study = byId.study -- (8.3: the big house's study, a round rug in its middle)
		if study then
			rug("round_rug", "study", (study.inner.x0 + study.inner.x1) / 2, (study.inner.z0 + study.inner.z1) / 2, 7, 7, 0)
		end
	end

	-- 7.x alpine: the wall decor, high on the walls (its bottom Alpine.Decor up: over every piece and below the
	-- ceiling's beams), clear of the doorways (and their frames), the windows and the fixtures that reach that high: the
	-- antlers in the living room, a framed alpine picture in the hall and in the bedroom; over a piece standing at that
	-- wall where it can (where people hang them), else the wall's middle. Its own dice: the pieces stay where they were
	-- and the ★ the house's.
	do
		local dice = newRng(seed + 7919)
		local up = A.Decor
		type Hung = { room: string, side: string, a: number, b: number }
		local hung: { Hung } = {}
		local function hang(kind: string, roomId: string, size: { number })
			local room = byId[roomId]
			local w = size[1]
			type DecorSpot = { side: string, t: number, score: number }
			local cands: { DecorSpot } = {}
			for _, side in SIDES do
				local lo, hi = span(room.inner, side)
				local alongX = side == "S" or side == "N"
				local blocked: { { number } } = {}
				for _, gap in openings(room, side) do
					table.insert(blocked, { gap[1] - 0.6, gap[2] + 0.6 })
				end
				for _, wd in windows do
					if wd.room == roomId and wd.side == side and wd.y + wd.height / 2 > up - 0.3 then
						table.insert(blocked, { wd.t - wd.width / 2 - 0.4, wd.t + wd.width / 2 + 0.4 })
					end
				end
				local inner = room.inner
				for _, f in fixtures do
					local r = f.rect
					local atWall = (side == "S" and r.z0 <= inner.z0 + 0.6) or (side == "N" and r.z1 >= inner.z1 - 0.6)
						or (side == "W" and r.x0 <= inner.x0 + 0.6) or (side == "E" and r.x1 >= inner.x1 - 0.6)
					if f.room == roomId and f.y + f.h > up - 0.3 and atWall then
						table.insert(blocked, if alongX then { r.x0 - 0.3, r.x1 + 0.3 } else { r.z0 - 0.3, r.z1 + 0.3 })
					end
				end
				for _, h in hung do
					if h.room == roomId and h.side == side then
						table.insert(blocked, { h.a - 1, h.b + 1 })
					end
				end
				local t = lo + w / 2 + 0.8
				while t <= hi - w / 2 - 0.8 + 1e-6 do
					local free = true
					for _, b in blocked do
						if t + w / 2 > b[1] and t - w / 2 < b[2] then
							free = false
							break
						end
					end
					if free then
						local score = 50 + math.abs(t - (lo + hi) / 2)
						for _, p in placed do
							if p.room == roomId and p.side == side and p.t then
								score = math.min(score, math.abs(t - p.t))
							end
						end
						table.insert(cands, { side = side, t = t, score = score })
					end
					t += 0.5
				end
			end
			if #cands == 0 then
				return
			end
			table.sort(cands, function(a: DecorSpot, b: DecorSpot): boolean
				if math.abs(a.score - b.score) > 1e-9 then
					return a.score < b.score
				end
				if a.side ~= b.side then
					return a.side < b.side
				end
				return a.t < b.t
			end)
			local n = 1
			while n < #cands and cands[n + 1].score <= cands[1].score + 1 do
				n += 1
			end
			local c = cands[dice.int(1, n)]
			fixture(kind, room, c.side, c.t, size[1], size[2], size[3], up, false)
			table.insert(hung, { room = roomId, side = c.side, a = c.t - w / 2, b = c.t + w / 2 })
		end
		hang("antlers", "living", A.Antlers)
		hang("picture", "hall", A.Picture)
		hang("picture", "bedroom", A.Picture)
		if byId.study and byId.guest then -- (8.3 the big house: antlers in the study, a picture in the guest room)
			hang("antlers", "study", A.Antlers)
			hang("picture", "guest", A.Picture)
		end
	end

	-- ── The plan ───────────────────────────────────────────────────────────────
	-- spots numbered room by room, in placing order
	local rank: { [string]: number } = {}
	for n, id in shape.furnish do
		rank[id] = n
	end
	table.sort(placed, function(a: Placed, b: Placed): boolean
		if a.room ~= b.room then
			return rank[a.room] < rank[b.room]
		end
		return a.order < b.order
	end)
	local spots: { Spot } = {}
	for n, p in placed do
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
	local planRooms: { Room } = {}
	for _, room in rooms do
		local inner = room.inner
		table.insert(planRooms, { id = room.id, kind = room.kind, min = Vector3.new(inner.x0, 0, inner.z0), max = Vector3.new(inner.x1, ceiling, inner.z1) })
	end
	local planDoors: { Door } = {}
	for n, door in doors do
		local axis: Axis = if door.alongX then "X" else "Z"
		table.insert(planDoors, { at = Vector3.new(door.x, 0, door.z), width = door.width, axis = axis, rooms = { door.a, door.b or "outside" }, front = n == 1 })
	end
	local planWindows: { Window } = {}
	for _, w in windows do
		local room = byId[w.room]
		local inner = room.inner
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
		table.insert(planWindows, { room = w.room, at = at, width = w.width, height = w.height, normal = normal })
	end
	local planFixtures: { Fixture } = {}
	for _, f in fixtures do
		table.insert(planFixtures, {
			kind = f.kind,
			room = f.room,
			at = CFrame.new(f.x, f.y, f.z) * CFrame.Angles(0, math.rad(f.turn), 0),
			size = Vector3.new(f.w, f.h, f.d),
			turn = f.turn,
			solid = f.solid,
		})
	end
	local min = Vector3.new(house.x0 - HALF_WALL, 0, house.z0 - HALF_WALL)
	local max = Vector3.new(house.x1 + HALF_WALL, ceiling, house.z1 + HALF_WALL)
	local up = T.EntryUp
	return {
		kind = shape.kind,
		seed = seed,
		mirrored = mirrored,
		size = max - min,
		min = min,
		max = max,
		rooms = planRooms,
		doors = planDoors,
		entry = CFrame.lookAt(Vector3.new(0, up, T.EntryIn), Vector3.new(0, up, T.EntryIn + 1)),
		exit = Vector3.new(0, up, HALF_WALL),
		-- (8.3 the big house: its ways out, the front door's and the back door's insides; a house: none, its exit)
		exits = if shape.backDoor then { Vector3.new(0, up, HALF_WALL), Vector3.new(x1 - HALF_WALL, up, F + C / 2) } else nil,
		spots = spots,
		ceiling = ceiling,
		wall = W_,
		doorHeight = T.DoorHeight,
		faces = faces,
		windows = planWindows,
		fixtures = planFixtures,
	}
end

-- A shape with its numbers read from Config now (not when this module loaded: a test may change them a moment); 8.3
-- economy: the move owner's book (`found`).
local function live(shape: Shape, found: { [string]: any }?): Shape
	local made = table.clone(shape)
	made.found = found
	if shape.kind == "big" then
		local L = (T :: any).Big
		made.front, made.kitchen, made.backDoor = L.Front, L.Kitchen, L.BackDoor
		local roomy = L.Roomy -- (8.5.2: 1 … 2, else as it was)
		made.roomy = if type(roomy) == "number" and roomy == roomy then math.clamp(roomy, 1, 2) else 1
		made.spots, made.stars = L.Spots, L.Stars
		made.collectibles, made.legendary = L.Collectibles.Count, L.Collectibles.Legendary
	else
		made.spots, made.stars = T.Spots, T.Stars
		made.collectibles, made.legendary = T.Collectibles.Count, T.Collectibles.Legendary
	end
	return made
end

local KINDS: { [string]: (number, { [string]: any }?) -> Plan } = {
	house = function(seed: number, found: { [string]: any }?): Plan
		return planHouse(seed, live(SHAPES.house, found))
	end,
	farm = function(seed: number): Plan
		return Farm.plan(seed)
	end,
	big = function(seed: number, found: { [string]: any }?): Plan -- 8.3: the sandbox's big house
		return planHouse(seed, live(SHAPES.big, found))
	end,
}
HouseLayout.Kinds = { "house", "farm", "big" }

function HouseLayout.plan(seed: number, kind: string, found: { [string]: any }?): Plan
	local make = KINDS[kind] or KINDS.house
	return make(seed, if type(found) == "table" then found else nil)
end

-- 7.x farm move (server/Moving.luau): a plan's ways out, in order: its exits (a farm's: the front door, the barn doors),
-- else its one front door (exit).
function HouseLayout.exitsOf(plan: Plan): { Vector3 }
	local exits = (plan :: any).exits
	return if type(exits) == "table" and #exits > 0 then exits else { plan.exit }
end

-- Where you come in by each exit (the same order): the front door's the plan's entry, another's EntryIn in from its
-- doorway's inside (the exit) facing into the room behind it.
function HouseLayout.entries(plan: Plan): { CFrame }
	local list: { CFrame } = { plan.entry }
	local exits = HouseLayout.exitsOf(plan)
	local n = 0
	for _, door in plan.doors do
		if door.rooms[2] ~= "outside" then
			continue
		end
		n += 1
		local exit = exits[n]
		if n > 1 and exit then
			local into = Vector3.new(exit.X - door.at.X, 0, exit.Z - door.at.Z)
			into = if into.Magnitude > 1e-3 then into.Unit else Vector3.new(0, 0, 1)
			local at = Vector3.new(exit.X, T.EntryUp, exit.Z) + into * T.EntryIn
			list[n] = CFrame.lookAt(at, at + into)
		end
	end
	return list
end

-- The exits (indexes into exitsOf) a piece of this FurnitureLooks id can be carried out of: a farm's Farm.exitsFor (a
-- bigDoor piece only the barn doors), a house's its front door (8.3: a big house's either door: both doorways take every
-- piece of a house, and its layout checks the way to each).
function HouseLayout.exitsFor(plan: Plan, id: string): { number }
	if plan.kind == "farm" then
		return Farm.exitsFor(plan :: any, id)
	end
	local all: { number } = {}
	for index in HouseLayout.exitsOf(plan) do
		table.insert(all, index)
	end
	return all
end

-- The spots of a plan whose piece cannot be carried out of the front door (with every other piece in place). 8.3: a
-- big house's, of the front door or of the back door (every doorway to the outside).
function HouseLayout.stuck(plan: Plan): { number }
	if plan.kind == "farm" then -- 7.x the farm: its exits (the barn doors too)
		return Farm.stuck(plan :: any)
	end
	local half = plan.wall / 2
	local walls: { Rect } = {}
	for _, f in plan.faces do
		if not f.header then
			table.insert(walls, rect(f.min.X, f.min.Z, f.max.X, f.max.Z))
		end
	end
	for _, f in plan.fixtures do
		if f.solid then
			local ex, ez = if norm(f.turn) % 180 == 0 then f.size.X else f.size.Z, if norm(f.turn) % 180 == 0 then f.size.Z else f.size.X
			local p = f.at.Position
			table.insert(walls, rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2))
		end
	end
	local rects, radii = {}, {}
	for _, s in plan.spots do
		local ex, ez = HouseLayout.extent(s.item, s.turn)
		local p = s.at.Position
		table.insert(rects, rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2))
		table.insert(radii, radiusOf(s.item))
	end
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, door in plan.doors do
		if door.rooms[2] ~= "outside" then
			continue
		end
		local w = door.width / 2
		local doorway = if door.axis == "X"
			then rect(door.at.X - w, door.at.Z - half, door.at.X + w, door.at.Z + half)
			else rect(door.at.X - half, door.at.Z - w, door.at.X + half, door.at.Z + w)
		local field = newField(rect(plan.min.X, plan.min.Z, plan.max.X, plan.max.Z), walls, doorway)
		for _, index in stuckOf(field, rects, radii) do
			local id = plan.spots[index].id
			if not seen[id] then
				seen[id] = true
				table.insert(out, id)
			end
		end
	end
	table.sort(out)
	return out
end

return HouseLayout
