--!strict
-- 9.5 the countryside (the owner: "instead of those houses make rather six different spots: by the pond, on the farm,
-- one house, somewhere else again ... not any towns, and not villages"): the insides of the four new places to empty
-- as plans of shared/HouseLayout.luau's kinds "cabin" (The Pond Cabin), "lodge" (The Forest Lodge), "mill" (The Old
-- Mill) and "cottage" (The Orchard Cottage): HouseLayout.plan(seed, kind) comes here (the Lone House is a family
-- house's "house", the farmstead the big house). Pure and deterministic like a house (the same seed and kind, the same
-- plan on every server); it makes no instances. server/HouseInterior.luau builds a plan in its kind's own style.
--
--   Countryside.plan(seed, kind, found?, pool?)   a plan of `kind` (one of Countryside.Kinds): HouseLayout's Plan, every
--                                  position local to its front door's middle on the floor, +Z into it, +Y up; a single
--                                  way out (its front door: doors[1], exit), so no `exits`. `found`: the move owner's
--                                  collection book (8.3 economy: a legendary not in it is tried first); `pool`:
--                                  HouseLayout.Collectibles (each collectible's placement; nil: every one at a wall)
--   Countryside.Kinds              the kinds it lays out
--   Countryside.Recipes            per kind, what each room holds (HouseLayout's Entry: item, how, ref, must, star, odds;
--                                  must and star together: always there and always ★)
--   Countryside.Rooms              per kind, its rooms in the order they are furnished (the spots are numbered so)
--   Countryside.Themes             per kind, the collectibles that suit it (tried first in each rarity)
--   Countryside.size(kind)         its inside (along the front, deep: its walls' middles): Config.Furniture.Countryside's
--                                  Box × Scale in whole even studs
--
-- Each kind (Config.Furniture.Countryside: Box, Ceiling, Spots, Stars, Collectibles, InteriorMaxParts), the dice moving
-- its walls and doorways and mirroring it left to right (the mill not: its water wheel's shaft stays on its -X wall,
-- the right-hand side of the building seen from outside facing the front door):
--   "cabin"    a timber fishing cabin: the main room you come into (its wood stove, the sink and counter in a front
--              corner, the table with folding chairs), behind it the bunk room and the store (the fishing things, the
--              outboard motor, shelves)
--   "lodge"    a forester's lodge: a hall straight through from the front door with the rooms off it: the great room
--              (the fireplace, antlers on the wall), the kitchen (the big oak table, its stove and sink), the bedroom and
--              the gun room (the empty gun cabinet); now and then the great room runs the hall's whole depth and the gun
--              room's things stand in it (three rooms)
--   "mill"     a watermill's ground floor: the big workroom (the millstones under their hopper free-standing in it, the
--              pit wheel on the water wheel's shaft in its pit on the -X wall, the sack hoist's chain) and the miller's
--              room along its side
--   "cottage"  an orchard cottage: the living kitchen you come into (its tiled range, the sink and counter, the dresser,
--              the table), behind it the bedroom and the store (the apple press, the beehive box, fruit crates); now and
--              then the bedroom takes the back's whole width (two rooms) and the store's things stand in the kitchen
-- Room ids (kind): cabin main (living), bunks (bedroom), store (store); lodge hall (hall), living, kitchen, bedroom,
-- gunroom (living); mill workroom (workroom), millers (living); cottage kitchen (kitchen), bedroom, store (store).
-- Fixtures besides a house's (counter, sink, shelves, larder, tiled_stove, fireplace, antlers, picture, rugs, mats):
-- wood_stove (a cast iron stove, its pipe up to the ceiling: size.Y), net and lifebuoy (the cabin's walls' decor, high),
-- millstones (free-standing: the stone floor, the vat, the hopper on its horse), pit_wheel (against the -X wall),
-- sack_hoist (its trap and chain from the ceiling: decor, size.Y down from the ceiling), hanging_lantern (decor, no light).
-- Every piece gets out of the front door carried end first (as a house's), and Danny has a spot beside every piece he
-- walks to (shared/HouseRoute.luau reach, within Config.MoveHelper.Route.Stand: one that has none is dropped, as one that
-- cannot get out is).

local Config = require(script.Parent.Parent.Config)
local FurnitureLooks = require(script.Parent.Parent.FurnitureLooks)
local HouseRoute = require(script.Parent.Parent.HouseRoute)

local T = Config.Furniture
local C = (T :: any).Countryside
local Countryside = {}

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

-- The dice: Park-Miller after the hash (exact in doubles); each kind its own stream (salted, not a house's).
local function newRng(seed: number, salt: number): Rng
	local s = math.floor(math.abs(seed)) % 4294967296
	local state = hash(bit32.bxor(s, salt)) % 2147483646 + 1
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

-- ── Reachability (every piece out of the front door) ──────────────────────────────────────

local CAP = 4
local STEP = 0.05

type Field = { x0: number, z0: number, nx: number, nz: number, step: number, static: { number }, door: Rect }

local function spanOf(field: Field, r: Rect, pad: number): (number, number, number, number)
	local step, x0, z0 = field.step, field.x0, field.z0
	return math.max(0, math.floor((r.x0 - pad - x0) / step)), math.min(field.nx - 1, math.ceil((r.x1 + pad - x0) / step)),
		math.max(0, math.floor((r.z0 - pad - z0) / step)), math.min(field.nz - 1, math.ceil((r.z1 + pad - z0) / step))
end

local function newField(box: Rect, walls: { Rect }, door: Rect): Field
	local step = T.Grid
	local x0, z0 = math.floor(box.x0 / step) * step, math.floor(box.z0 / step) * step
	local nx = math.floor((box.x1 - x0) / step) + 1
	local nz = math.floor((box.z1 - z0) / step) + 1
	local field: Field = { x0 = x0, z0 = z0, nx = nx, nz = nz, step = step, static = table.create(nx * nz, CAP), door = door }
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

-- Which of `pieces` (footprints, each with the radius it needs) cannot get out of the front door: their indexes.
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
	-- the widest way in from the front door: best[k] the widest disc (in STEP levels) from the doorway to point k
	local levels = math.floor(CAP / STEP)
	local best = table.create(count, -1)
	local buckets: { { number } } = {}
	for level = 0, levels do
		buckets[level + 1] = {}
	end
	local door = field.door
	do
		local i0, i1, j0, j1 = spanOf(field, door, 0)
		for j = j0, j1 do
			local z = z0 + j * step
			for i = i0, i1 do
				local x = x0 + i * step
				if x >= door.x0 - 1e-6 and x <= door.x1 + 1e-6 and z >= door.z0 - 1e-6 and z <= door.z1 + 1e-6 then
					local k = j * nx + i + 1
					local level = math.min(levels, math.floor(math.min(static[k], near1[k]) / STEP))
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
					local v = math.min(level, math.floor(math.min(static[nk], near1[nk]) / STEP))
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
-- "around"; must: always there; star: one of the ★ candidates (Stars of them by the dice; must and star: always there
-- and always ★); odds: how likely an optional piece comes before the others.

local RECIPES: { [string]: { [string]: { Entry } } } = {
	cabin = {
		main = {
			{ item = "dining_table", how = "middle", must = true },
			{ item = "folding_chair", how = "around", ref = "dining_table", must = true },
			{ item = "folding_chair", how = "around", ref = "dining_table", must = true },
			{ item = "folding_chair", how = "around", ref = "dining_table" },
			{ item = "coal_scuttle", how = "corner", must = true },
			{ item = "armchair", how = "wall", odds = 2 },
			{ item = "radio", how = "wall", odds = 1.5 },
			{ item = "guitar", how = "corner", odds = 1.5 },
			{ item = "bookshelf", how = "wall" },
			{ item = "floor_lamp", how = "corner" },
			{ item = "painting", how = "wall" },
			{ item = "record_player", how = "wall", star = true },
		},
		bunks = {
			{ item = "bunk_bed", how = "far", must = true },
			{ item = "nightstand", how = "beside", ref = "bunk_bed", must = true },
			{ item = "coat_rack", how = "corner", odds = 1.5 },
			{ item = "dresser", how = "wall" },
			{ item = "mirror", how = "corner" },
			{ item = "box", how = "corner" },
			{ item = "photo_album", how = "corner", star = true },
		},
		store = {
			{ item = "outboard_motor", how = "wall", must = true },
			{ item = "fishing_rods", how = "corner", must = true, star = true },
			{ item = "oars", how = "corner", must = true },
			{ item = "tackle_box", how = "wall", must = true },
			{ item = "landing_net", how = "corner", odds = 2 },
			{ item = "cool_box", how = "wall", odds = 2 },
			{ item = "toolbox", how = "wall" },
			{ item = "box", how = "corner" },
		},
	},
	lodge = {
		hall = {
			{ item = "boot_rack", how = "wall", must = true },
			{ item = "coat_rack", how = "corner", must = true },
			{ item = "log_basket", how = "corner", odds = 2 },
			{ item = "shoe_cabinet", how = "wall" },
			{ item = "plant", how = "corner" },
		},
		living = {
			{ item = "antler_trophy", how = "wall", must = true, star = true },
			{ item = "armchair", how = "wall", must = true },
			{ item = "stuffed_owl", how = "corner", must = true },
			{ item = "sofa", how = "centre", odds = 2 },
			{ item = "coffee_table", how = "front", ref = "sofa", odds = 1.5 },
			{ item = "armchair", how = "wall", odds = 2 },
			{ item = "log_basket", how = "corner", odds = 2 },
			{ item = "bookshelf", how = "wall", odds = 1.5 },
			{ item = "floor_lamp", how = "corner" },
			{ item = "painting", how = "wall" },
			{ item = "grandfather_clock", how = "wall", star = true },
		},
		kitchen = {
			{ item = "oak_table", how = "middle", must = true },
			{ item = "dining_chair", how = "around", ref = "oak_table", must = true },
			{ item = "dining_chair", how = "around", ref = "oak_table", must = true },
			{ item = "dining_chair", how = "around", ref = "oak_table" },
			{ item = "dining_chair", how = "around", ref = "oak_table" },
			{ item = "fridge", how = "corner", odds = 1.5 },
			{ item = "dishes_box", how = "corner" },
			{ item = "radio", how = "wall" },
			{ item = "stein_crate", how = "corner" },
		},
		bedroom = {
			{ item = "bed", how = "far", must = true },
			{ item = "nightstand", how = "beside", ref = "bed", must = true },
			{ item = "wardrobe", how = "wall", must = true },
			{ item = "carved_chest", how = "front", ref = "bed", odds = 2 },
			{ item = "dresser", how = "wall" },
			{ item = "mirror", how = "corner" },
			{ item = "photo_album", how = "corner", star = true },
		},
		gunroom = {
			{ item = "gun_cabinet", how = "wall", must = true },
			{ item = "bookshelf", how = "wall", must = true },
			{ item = "armchair", how = "wall", odds = 1.5 },
			{ item = "log_basket", how = "corner", odds = 1.5 },
			{ item = "painting", how = "wall" },
			{ item = "floor_lamp", how = "corner" },
			{ item = "plant", how = "corner" },
			{ item = "box", how = "corner" },
			{ item = "cuckoo_clock", how = "wall", star = true },
		},
	},
	mill = {
		workroom = {
			{ item = "millstone", how = "wall", must = true },
			{ item = "grain_scales", how = "wall", must = true },
			{ item = "sack_trolley", how = "wall", must = true },
			{ item = "joiners_bench", how = "wall", must = true },
			{ item = "flour_sacks", how = "corner", must = true },
			{ item = "grain_crate", how = "corner", must = true },
			{ item = "flour_sacks", how = "wall", odds = 2 },
			{ item = "grain_crate", how = "wall", odds = 1.5 },
			{ item = "flour_sacks", how = "corner" },
			{ item = "flour_sacks", how = "wall" },
			{ item = "grain_crate", how = "corner" },
			{ item = "toolbox", how = "wall" },
			{ item = "box", how = "corner" },
			{ item = "box", how = "wall" },
		},
		millers = {
			{ item = "grandfather_clock", how = "wall", must = true, star = true },
			{ item = "bed", how = "far", must = true },
			{ item = "wardrobe", how = "wall", must = true },
			{ item = "nightstand", how = "beside", ref = "bed" },
			{ item = "armchair", how = "wall", odds = 1.5 },
			{ item = "bookshelf", how = "wall" },
			{ item = "radio", how = "wall" },
			{ item = "dining_table", how = "middle", odds = 1.5 },
			{ item = "dining_chair", how = "around", ref = "dining_table" },
			{ item = "dining_chair", how = "around", ref = "dining_table" },
			{ item = "photo_album", how = "corner", star = true },
		},
	},
	cottage = {
		kitchen = {
			{ item = "dining_table", how = "middle", must = true },
			{ item = "dining_chair", how = "around", ref = "dining_table", must = true },
			{ item = "dining_chair", how = "around", ref = "dining_table", must = true },
			{ item = "dining_chair", how = "around", ref = "dining_table" },
			{ item = "sewing_machine", how = "wall", must = true, star = true },
			{ item = "plate_dresser", how = "wall", must = true },
			{ item = "jam_shelf", how = "wall", must = true },
			{ item = "rocking_chair", how = "corner", must = true },
			{ item = "fruit_crates", how = "corner", odds = 2 },
			{ item = "flower_pots", how = "wall", odds = 2 },
			{ item = "radio", how = "wall" },
			{ item = "cuckoo_clock", how = "wall", star = true },
		},
		bedroom = {
			{ item = "bed", how = "far", must = true },
			{ item = "nightstand", how = "beside", ref = "bed", must = true },
			{ item = "wardrobe", how = "wall", must = true },
			{ item = "dresser", how = "wall", odds = 1.5 },
			{ item = "flower_pots", how = "wall" },
			{ item = "mirror", how = "corner" },
			{ item = "photo_album", how = "corner", star = true },
		},
		store = {
			{ item = "apple_press", how = "wall", must = true },
			{ item = "bee_box", how = "corner", must = true },
			{ item = "fruit_crates", how = "corner", must = true },
			{ item = "fruit_crates", how = "wall", odds = 1.5 },
			{ item = "toolbox", how = "wall" },
			{ item = "box", how = "corner" },
		},
	},
}
Countryside.Recipes = RECIPES
Countryside.Kinds = { "cabin", "lodge", "mill", "cottage" }
-- the rooms in the order they are furnished (and their spots numbered); where a filler box goes when a plan is short
local FURNISH: { [string]: { string } } = {
	cabin = { "main", "bunks", "store" },
	lodge = { "living", "kitchen", "bedroom", "gunroom", "hall" },
	mill = { "workroom", "millers" },
	cottage = { "kitchen", "bedroom", "store" },
}
Countryside.Rooms = FURNISH
local FILLER: { [string]: { string } } = {
	cabin = { "store", "main", "bunks" },
	lodge = { "gunroom", "living", "kitchen", "bedroom", "hall" },
	mill = { "workroom", "millers" },
	cottage = { "store", "kitchen", "bedroom" },
}
-- the collectibles that suit each place (tried first in their rarity)
local THEMES: { [string]: { string } } = {
	cabin = { "ship_bottle", "vintage_radio", "vintage_camera", "old_globe", "signed_guitar", "zombie_safe" },
	lodge = { "stag_head", "carved_bear", "old_globe", "gramophone", "crystal_chandelier", "oil_painting", "knight_armour" },
	mill = { "antique_typewriter", "golden_horseshoe", "pocket_watch", "vintage_radio", "antique_vase", "zombie_safe" },
	cottage = { "jewellery_box", "gramophone", "bowling_trophy", "antique_vase", "crystal_chandelier", "oil_painting" },
}
Countryside.Themes = THEMES
-- a collectible's catalogue room (FurnitureLooks.Rooms) to the room kinds of a place it may stand in, in turn
local COLLECT_IN: { [string]: { string } } = {
	living = { "living", "kitchen", "hall" },
	kitchen = { "kitchen", "living" },
	bedroom = { "bedroom", "living" },
	kids = { "bedroom", "living" },
	hall = { "hall", "living", "kitchen", "workroom" },
	garage = { "store", "workroom", "living" },
	bath = { "bedroom", "living" },
}
local SALT: { [string]: number } = { cabin = 0x0cab1a95, lodge = 0x10d6e195, mill = 0x0a111295, cottage = 0x0c077a95 }

function Countryside.size(kind: string): (number, number)
	local k = C[kind]
	local function even(n: number): number
		return 2 * math.floor(n * C.Scale / 2 + 0.5)
	end
	return even(k.Box[1]), even(k.Box[2])
end

-- ── A plan ─────────────────────────────────────────────────────────────────────

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
	kind: string,
	rng: Rng,
	ceiling: number,
	W: number,
	D: number,
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
	extra: { [string]: { Entry } }, -- a room's entries besides its recipe's (a room the plan has not: its things moved in)
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

local function addRoom(S: State, id: string, kind: string, cell: Rect)
	local room: RoomData = { id = id, kind = kind, cell = cell, inner = cell }
	table.insert(S.rooms, room)
	S.byId[id] = room
end

local function addDoor(S: State, x: number, z: number, width: number, alongX: boolean, a: string, b: string?)
	table.insert(S.doors, { x = x, z = z, width = width, alongX = alongX, a = a, b = b })
end

-- ── The shells: each kind's rooms (their walls' middles) and doorways, then maybe mirrored ─────────────────────

local SHELLS: { [string]: (State) -> boolean } = {}

-- the cabin: the main room across the front, the bunk room and the store behind it
SHELLS.cabin = function(S: State): boolean
	local rng, W, D = S.rng, S.W, S.D
	local F = 16 + 2 * rng.int(0, 1)
	local bunks = rng.int(20, 23)
	local x0, x1 = -W / 2, W / 2
	addRoom(S, "main", "living", rect(x0, 0, x1, F))
	addRoom(S, "bunks", "bedroom", rect(x0, F, x0 + bunks, D))
	addRoom(S, "store", "store", rect(x0 + bunks, F, x1, D))
	addDoor(S, 0, 0, T.FrontDoor, true, "main", nil)
	addDoor(S, doorIn(rng, x0, x0 + bunks, T.Door), F, T.Door, true, "main", "bunks")
	addDoor(S, doorIn(rng, x0 + bunks, x1, T.Door), F, T.Door, true, "main", "store")
	return rng.num() < 0.5
end

-- the lodge: the hall straight through from the front door, two rooms each side of it (or the great room the hall's
-- whole depth on its side: then the gun room's things stand in it)
SHELLS.lodge = function(S: State): boolean
	local rng, W, D = S.rng, S.W, S.D
	local half = T.HallWidth / 2
	local x0, x1 = -W / 2, W / 2
	local big = rng.num() < 0.35
	local FA = 20 + 2 * rng.int(-1, 1)
	local FB = 18 + 2 * rng.int(-1, 1)
	addRoom(S, "hall", "hall", rect(-half, 0, half, D))
	addDoor(S, 0, 0, T.FrontDoor, true, "hall", nil)
	if big then
		addRoom(S, "living", "living", rect(x0, 0, -half, D))
		addDoor(S, -half, doorIn(rng, 0, D * 0.6, T.FrontDoor), T.FrontDoor, false, "hall", "living")
		S.extra.living = RECIPES.lodge.gunroom
	else
		addRoom(S, "living", "living", rect(x0, 0, -half, FA))
		addRoom(S, "bedroom", "bedroom", rect(x0, FA, -half, D))
		addDoor(S, -half, doorIn(rng, 0, FA, T.Door), T.Door, false, "hall", "living")
		addDoor(S, -half, doorIn(rng, FA, D, T.Door), T.Door, false, "hall", "bedroom")
	end
	addRoom(S, "kitchen", "kitchen", rect(half, 0, x1, FB))
	addDoor(S, half, doorIn(rng, 0, FB, T.Door), T.Door, false, "hall", "kitchen")
	if big then
		addRoom(S, "bedroom", "bedroom", rect(half, FB, x1, D))
		addDoor(S, half, doorIn(rng, FB, D, T.Door), T.Door, false, "hall", "bedroom")
	else
		addRoom(S, "gunroom", "living", rect(half, FB, x1, D))
		addDoor(S, half, doorIn(rng, FB, D, T.Door), T.Door, false, "hall", "gunroom")
	end
	return rng.num() < 0.5
end

-- the mill: the workroom (the -X side, the front door in it) and the miller's room along its +X side; never mirrored
-- (the water wheel turns outside its -X wall)
SHELLS.mill = function(S: State): boolean
	local rng, W, D = S.rng, S.W, S.D
	local side = 12 + 2 * rng.int(0, 1)
	local x0, x1 = -W / 2, W / 2
	addRoom(S, "workroom", "workroom", rect(x0, 0, x1 - side, D))
	addRoom(S, "millers", "living", rect(x1 - side, 0, x1, D))
	addDoor(S, 0, 0, T.FrontDoor, true, "workroom", nil)
	addDoor(S, x1 - side, doorIn(rng, D * 0.3, D * 0.75, T.FrontDoor), T.FrontDoor, false, "workroom", "millers")
	return false
end

-- the cottage: the living kitchen across the front, the bedroom and the store behind it (or the bedroom the back's
-- whole width: then the store's things stand in the kitchen)
SHELLS.cottage = function(S: State): boolean
	local rng, W, D = S.rng, S.W, S.D
	local F = 18 + 2 * rng.int(0, 1)
	local x0, x1 = -W / 2, W / 2
	local two = rng.num() < 0.3
	addRoom(S, "kitchen", "kitchen", rect(x0, 0, x1, F))
	addDoor(S, 0, 0, T.FrontDoor, true, "kitchen", nil)
	if two then
		addRoom(S, "bedroom", "bedroom", rect(x0, F, x1, D))
		addDoor(S, doorIn(rng, x0, x1, T.Door, 6), F, T.Door, true, "kitchen", "bedroom")
		S.extra.kitchen = RECIPES.cottage.store
	else
		local bed = rng.int(24, 27)
		addRoom(S, "bedroom", "bedroom", rect(x0, F, x0 + bed, D))
		addRoom(S, "store", "store", rect(x0 + bed, F, x1, D))
		addDoor(S, doorIn(rng, x0, x0 + bed, T.Door), F, T.Door, true, "kitchen", "bedroom")
		addDoor(S, doorIn(rng, x0 + bed, x1, T.Door), F, T.Door, true, "kitchen", "store")
	end
	return rng.num() < 0.5
end

local function shell(S: State)
	S.mirrored = SHELLS[S.kind](S)
	if S.mirrored then
		for _, room in S.rooms do
			room.cell = rect(-room.cell.x1, room.cell.z0, -room.cell.x0, room.cell.z1)
		end
		for _, d in S.doors do
			d.x = -d.x
		end
	end
	for _, room in S.rooms do
		local c = room.cell
		room.inner = rect(c.x0 + HALF, c.z0 + HALF, c.x1 - HALF, c.z1 - HALF)
	end
end

-- Is a side of a room on the building's outside?
local function outer(S: State, room: RoomData, side: string): boolean
	local c = room.cell
	if side == "S" then
		return c.z0 <= 1e-6
	elseif side == "N" then
		return c.z1 >= S.D - 1e-6
	elseif side == "W" then
		return c.x0 <= -S.W / 2 + 1e-6
	end
	return c.x1 >= S.W / 2 - 1e-6
end

-- The doorways in a side of a room: { from, to } along it.
local function openings(S: State, room: RoomData, side: string): { { number } }
	local line = lineOf(room.cell, side)
	local alongX = side == "S" or side == "N"
	local out: { { number } } = {}
	for _, d in S.doors do
		if d.alongX == alongX and (d.a == room.id or d.b == room.id) then
			local at = if alongX then d.z else d.x
			local t = if alongX then d.x else d.z
			if math.abs(at - line) < 1e-6 then
				table.insert(out, { t - d.width / 2, t + d.width / 2 })
			end
		end
	end
	table.sort(out, function(p: { number }, q: { number }): boolean
		return p[1] < q[1]
	end)
	return out
end

-- The walls (as a house's): every room side as slabs, its half of a shared wall, the whole of an outer one (run on over
-- the building's corners), cut at the doorways, with the wall over every doorway.
local function walls(S: State)
	local ceiling = S.ceiling
	local x0, x1 = -S.W / 2, S.W / 2
	for _, room in S.rooms do
		local c = room.cell
		for _, side in SIDES do
			local isOuter = outer(S, room, side)
			local alongX = side == "S" or side == "N"
			local line = lineOf(c, side)
			local a, b = span(c, side)
			local lo = if alongX then x0 else 0
			local hi = if alongX then x1 else S.D
			local inward = if side == "S" or side == "W" then 1 else -1
			local p0, p1
			if isOuter then
				p0, p1 = line - HALF, line + HALF
			else
				p0, p1 = line, line + inward * HALF
			end
			local normal = Vector3.new(if alongX then 0 else inward, 0, if alongX then inward else 0)
			local function slab(s0: number, s1: number, y0: number, y1: number, header: boolean)
				local r = if alongX then rect(s0, p0, s1, p1) else rect(p0, s0, p1, s1)
				table.insert(S.faces, {
					room = room.id,
					min = Vector3.new(r.x0, y0, r.z0),
					max = Vector3.new(r.x1, y1, r.z1),
					normal = normal,
					outer = isOuter,
					header = header,
				})
				if not header then
					table.insert(S.walls, r)
				end
			end
			local from = a
			for _, gap in openings(S, room, side) do
				if gap[1] > from + 1e-6 then
					slab(if isOuter and from <= lo + 1e-6 then from - HALF else from, gap[1], 0, ceiling, false)
				end
				slab(gap[1], gap[2], T.DoorHeight, ceiling, true)
				from = gap[2]
			end
			if b > from + 1e-6 then
				slab(if isOuter and from <= lo + 1e-6 then from - HALF else from, if isOuter and b >= hi - 1e-6 then b + HALF else b, 0, ceiling, false)
			end
		end
	end
end

-- ── The fixtures and the windows ───────────────────────────────────────────────────

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

-- The side of a room away from x = 0 (its outer side wall).
local function outerSide(room: RoomData): string
	return if (room.cell.x0 + room.cell.x1) / 2 < 0 then "W" else "E"
end

-- The windows on a room's outer sides (`skip` sides left out): one in the middle of every free stretch of the wall that
-- has room for one (clear of its doorways, the tall solid fixtures against it and the windows there already), two along
-- a long one.
local function windowsOf(S: State, roomId: string, skip: { [string]: boolean }?)
	local room = S.byId[roomId]
	local inner = room.inner
	local w = T.Window[1]
	for _, side in SIDES do
		if not outer(S, room, side) or (skip and skip[side]) then
			continue
		end
		local alongX = side == "S" or side == "N"
		local a, b = span(inner, side)
		local blocked: { { number } } = {}
		for _, gap in openings(S, room, side) do
			table.insert(blocked, { gap[1] - 1, gap[2] + 1 })
		end
		for _, f in S.fixtures do
			local r = f.rect
			local atWall = (side == "S" and r.z0 <= inner.z0 + 0.6) or (side == "N" and r.z1 >= inner.z1 - 0.6)
				or (side == "W" and r.x0 <= inner.x0 + 0.6) or (side == "E" and r.x1 >= inner.x1 - 0.6)
			if f.room == roomId and f.solid and f.y + f.h > T.WindowSill and atWall then
				table.insert(blocked, if alongX then { r.x0 - 0.3, r.x1 + 0.3 } else { r.z0 - 0.3, r.z1 + 0.3 })
			end
		end
		for _, wd in S.windows do
			if wd.room == roomId and wd.side == side then
				table.insert(blocked, { wd.t - wd.width / 2 - 1.5, wd.t + wd.width / 2 + 1.5 })
			end
		end
		table.sort(blocked, function(p: { number }, q: { number }): boolean
			return p[1] < q[1]
		end)
		local from = a + 1
		local stretches: { { number } } = {}
		for _, bl in blocked do
			if bl[1] > from then
				table.insert(stretches, { from, bl[1] })
			end
			from = math.max(from, bl[2])
		end
		if b - 1 > from then
			table.insert(stretches, { from, b - 1 })
		end
		for _, st in stretches do
			local len = st[2] - st[1]
			if len >= w then
				local n = if len >= 3 * w + 8 then 2 else 1
				for k = 1, n do
					window(S, roomId, side, st[1] + len * k / (n + 1), T.Window, T.WindowSill)
				end
			end
		end
	end
end

local FIXTURES: { [string]: (State) -> () } = {}

-- the kitchen corner (a counter and the sink, a window over the sink) along the front wall from a front corner, `side`
-- the side wall it starts at
local function sinkRun(S: State, roomId: string, side: string)
	local room = S.byId[roomId]
	local inner = room.inner
	local dir = if side == "W" then 1 else -1
	local start = if side == "W" then inner.x0 else inner.x1
	fixture(S, "counter", roomId, "S", start + dir * 2.25, 4.5, 3, 2.6, 0, true)
	fixture(S, "sink", roomId, "S", start + dir * 6.25, 3.5, 3, 2.6, 0, true)
	window(S, roomId, "S", start + dir * 6.25, T.Window, T.WindowSill)
end

FIXTURES.cabin = function(S: State)
	local rng = S.rng
	local main = S.byId.main
	local inner = main.inner
	local stoveSide = if rng.num() < 0.5 then "W" else "E"
	local sinkSide = OPPOSITE[stoveSide]
	sinkRun(S, "main", sinkSide)
	-- the wood stove on the other side wall, its pipe up to the ceiling; a mat inside the front door
	fixture(S, "wood_stove", "main", stoveSide, (inner.z0 + inner.z1) / 2 + rng.int(-2, 2), 3.2, S.ceiling, 3, 0, true)
	freeFixture(S, "mat", "main", 0, 0, HALF + 1.6, 4.4, 0.08, 2.4, 0, false)
	-- the store: shelves on its back wall, at its outer end
	local store = S.byId.store
	local sx = if outerSide(store) == "W" then store.inner.x0 + 2.8 else store.inner.x1 - 2.8
	fixture(S, "shelves", "store", "N", sx, 5, 7, 1.6, 0, true)
	windowsOf(S, "main")
	windowsOf(S, "bunks", { S = true })
	local a, b = span(store.inner, outerSide(store))
	window(S, "store", outerSide(store), (a + b) / 2, T.BathWindow, 6.5)
end

FIXTURES.lodge = function(S: State)
	local living = S.byId.living
	local side = outerSide(living)
	local inner = living.inner
	local mid = (inner.z0 + inner.z1) / 2
	local place = if inner.z1 - inner.z0 > 24 then inner.z0 + 10 else mid
	fixture(S, "fireplace", "living", side, place, 5.6, 6, 2.6, 0, true)
	-- the kitchen: the tiled range on its outer wall by the back, the sink run along the front from the outer corner
	local kitchen = S.byId.kitchen
	local kside = outerSide(kitchen)
	fixture(S, "tiled_stove", "kitchen", kside, kitchen.inner.z1 - 3, 3.2, 3, 2.4, 0, true)
	sinkRun(S, "kitchen", kside)
	-- the hall: a mat inside the front door, a runner down it
	local hall = S.byId.hall.inner
	freeFixture(S, "mat", "hall", 0, 0, HALF + 1.6, 4.4, 0.08, 2.4, 0, false)
	freeFixture(S, "runner", "hall", 0, 0, (hall.z0 + 5 + hall.z1 - 3) / 2, 3.6, 0.08, hall.z1 - hall.z0 - 8, 0, false)
	for _, room in S.rooms do
		windowsOf(S, room.id, if room.id == "hall" then { S = true } else nil) -- (the hall's: at its back end)
	end
end

FIXTURES.mill = function(S: State)
	local rng = S.rng
	local work = S.byId.workroom
	local inner = work.inner
	-- the millstones free-standing in the workroom (their stone floor M square), the pit wheel in line with them on the
	-- -X wall, the sack hoist's trap and chain by the miller's room
	local M = 8
	local cx = (inner.x0 + inner.x1) / 2 + 1 + rng.int(0, 2)
	local cz = math.floor((inner.z0 + inner.z1) * 0.55 + 0.5) + rng.int(-2, 2)
	freeFixture(S, "millstones", "workroom", cx, 0, cz, M, 8.6, M, 0, true)
	fixture(S, "pit_wheel", "workroom", "W", cz, 9, 9.5, 3.4, 0, true)
	freeFixture(S, "sack_hoist", "workroom", inner.x1 - 4, S.ceiling - 4.5, inner.z1 - 7, 2.4, 4.5, 2.4, 0, false)
	for _, z in { inner.z0 + 9, inner.z1 - 12 } do
		freeFixture(S, "hanging_lantern", "workroom", cx - 5, S.ceiling - 3.4, z, 0.9, 3.4, 0.9, 0, false)
	end
	freeFixture(S, "mat", "workroom", 0, 0, HALF + 1.6, 4.4, 0.08, 2.4, 0, false)
	-- the miller's room: his stove on its outer wall near the back
	local millers = S.byId.millers
	fixture(S, "wood_stove", "millers", "E", millers.inner.z1 - 5, 3.2, S.ceiling, 3, 0, true)
	windowsOf(S, "workroom", { W = true })
	local a, b = span(inner, "W") -- (the -X wall's windows clear of the pit wheel)
	for _, t in { a + 5, b - 5 } do
		if math.abs(t - cz) > 8 then
			window(S, "workroom", "W", t, T.Window, T.WindowSill)
		end
	end
	windowsOf(S, "millers")
end

FIXTURES.cottage = function(S: State)
	local rng = S.rng
	local kitchen = S.byId.kitchen
	local inner = kitchen.inner
	local rangeSide = if rng.num() < 0.5 then "W" else "E"
	sinkRun(S, "kitchen", OPPOSITE[rangeSide])
	fixture(S, "tiled_stove", "kitchen", rangeSide, (inner.z0 + inner.z1) / 2 + 2, 3.2, 3, 2.4, 0, true)
	freeFixture(S, "mat", "kitchen", 0, 0, HALF + 1.6, 4.4, 0.08, 2.4, 0, false)
	local store = S.byId.store
	if store then
		local length = math.min(8, store.inner.x1 - store.inner.x0 - 6)
		local at = if outerSide(store) == "W" then store.inner.x0 + length / 2 else store.inner.x1 - length / 2
		fixture(S, "larder", "store", "N", at, length, 7, 1.6, 0, true)
		local a, b = span(store.inner, outerSide(store))
		window(S, "store", outerSide(store), (a + b) / 2, T.BathWindow, 6.5)
	end
	windowsOf(S, "kitchen")
	windowsOf(S, "bedroom")
end

-- Kept clear: in front of every doorway, DoorClear deep into each room it joins; in front of a window (for tall
-- pieces).
local function zones(S: State)
	for _, room in S.rooms do
		S.zones[room.id] = {}
		S.windowZones[room.id] = {}
	end
	for _, d in S.doors do
		for _, id in { d.a, d.b or "" } do
			local room = S.byId[id]
			if room then
				local w = d.width / 2 + 0.5
				if d.alongX then
					local into = if (room.cell.z0 + room.cell.z1) / 2 > d.z then 1 else -1
					local face = d.z + into * HALF
					table.insert(S.zones[id], rect(d.x - w, face, d.x + w, face + into * T.DoorClear))
				else
					local into = if (room.cell.x0 + room.cell.x1) / 2 > d.x then 1 else -1
					local face = d.x + into * HALF
					table.insert(S.zones[id], rect(face, d.z - w, face + into * T.DoorClear, d.z + w))
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
	if not room then
		return nil
	end
	S.placing = e.item
	local c = candidates(S, room, e)
	if not c and must and e.how ~= "wall" then
		c = candidates(S, room, { item = e.item, how = "wall" }) -- (a must that does not fit its way: at any wall)
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

-- A room's entries: its recipe's and the ones moved into it (S.extra).
local function entriesOf(S: State, roomId: string): { Entry }
	local own = RECIPES[S.kind][roomId] or {}
	local more = S.extra[roomId]
	if not more then
		return own
	end
	local all = table.clone(own)
	for _, e in more do
		table.insert(all, e)
	end
	return all
end

-- The furnish order: the kind's rooms the plan has.
local function furnishOrder(S: State): { string }
	local out: { string } = {}
	for _, id in FURNISH[S.kind] do
		if S.byId[id] then
			table.insert(out, id)
		end
	end
	return out
end

-- The pieces that cannot get out of the front door (indexes into S.placed).
local function stuckNow(S: State, field: Field): { number }
	local rects, radii = {}, {}
	for _, p in S.placed do
		table.insert(rects, p.rect)
		table.insert(radii, radiusOf(p.item))
	end
	return stuckOf(field, rects, radii)
end

-- The pieces Danny has no spot beside (shared/HouseRoute.luau reach within Route.Stand, from where he comes in by the
-- front door): indexes into S.placed.
local function unreachable(S: State, grid: HouseRoute.Grid): { number }
	local rects: { HouseRoute.Rect } = {}
	for _, p in S.placed do
		table.insert(rects, p.rect)
	end
	HouseRoute.block(grid, rects)
	local stand = (Config :: any).MoveHelper.Route.Stand
	local fz = T.EntryIn + 1.5
	local out: { number } = {}
	for index, r in rects do
		local x = HouseRoute.reach(grid, 0, fz, r, stand)
		if not x then
			table.insert(out, index)
		end
	end
	return out
end

-- Drop what blocks a piece in `list` (S.placed indexes): the latest optional piece of its room, else the piece itself (a
-- must placed again elsewhere in its room, not where it got stuck).
local function makeWay(S: State, victim: Placed, keepStars: boolean)
	local latest: Placed? = nil
	if victim.must then
		for _, p in S.placed do
			if p ~= victim and p.room == victim.room and not p.must and not (keepStars and p.star) and (latest == nil or p.order > latest.order) then
				latest = p
			end
		end
	end
	if latest then
		table.remove(S.placed, table.find(S.placed, latest) :: number)
		return
	end
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

-- 8.3 economy: a shuffled list of collectibles with the ones not in `found` first (a page only bought is no find).
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

-- A plan's shell as HouseRoute reads it (its walls, its solid fixtures, its rooms and doorways).
local function routeShell(S: State, box: Rect): any
	local rooms: { Room } = {}
	for _, room in S.rooms do
		local inner = room.inner
		table.insert(rooms, { id = room.id, kind = room.kind, min = Vector3.new(inner.x0, 0, inner.z0), max = Vector3.new(inner.x1, S.ceiling, inner.z1) })
	end
	local doors: { Door } = {}
	for n, d in S.doors do
		local axis: Axis = if d.alongX then "X" else "Z"
		table.insert(doors, { at = Vector3.new(d.x, 0, d.z), width = d.width, axis = axis, rooms = { d.a, d.b or "outside" }, front = n == 1 })
	end
	local fixtures: { any } = {}
	for _, f in S.fixtures do
		table.insert(fixtures, { at = CFrame.new(f.x, f.y, f.z), size = Vector3.new(f.w, f.h, f.d), turn = f.turn, solid = f.solid })
	end
	return { faces = S.faces, rooms = rooms, doors = doors, fixtures = fixtures, wall = T.Wall, min = Vector3.new(box.x0, 0, box.z0), max = Vector3.new(box.x1, S.ceiling, box.z1) }
end

local function furnish(S: State, found: { [string]: any }?, pool: { Entry }?, seed: number)
	local rng = S.rng
	local K = C[S.kind]
	local order = furnishOrder(S)
	-- the ★ pieces: the must-and-star ones always, then Stars of the others by the dice
	type Pick = { room: string, entry: Entry }
	local sentimental: { Pick } = {}
	local starred: { [Entry]: boolean } = {}
	local stars = 0
	for _, roomId in order do
		for _, e in entriesOf(S, roomId) do
			if e.star and e.must then
				starred[e] = true
				stars += 1
			elseif e.star then
				table.insert(sentimental, { room = roomId, entry = e })
			end
		end
	end
	shuffle(sentimental, rng)
	for n = 1, math.min(K.Stars - stars, #sentimental) do
		starred[sentimental[n].entry] = true
	end
	local target = rng.int(K.Spots[1], K.Spots[2])
	-- the musts, then the ★ ones, then the rest in a weighted shuffle until the plan holds `target` pieces
	local optional: { Pick } = {}
	for _, roomId in order do
		for _, e in entriesOf(S, roomId) do
			if e.must then
				place(S, roomId, e, true, starred[e] == true)
			elseif not e.star then
				table.insert(optional, { room = roomId, entry = e })
			end
		end
	end
	for _, roomId in order do
		for _, e in entriesOf(S, roomId) do
			if starred[e] and not e.must then
				place(S, roomId, e, true, true)
			end
		end
	end
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

	-- Every piece must get out of the front door: drop what blocks.
	local solids = table.clone(S.walls)
	for _, f in S.fixtures do
		if f.solid then
			table.insert(solids, f.rect)
		end
	end
	local box = rect(-S.W / 2 - HALF, -HALF, S.W / 2 + HALF, S.D + HALF)
	local field = newField(box, solids, rect(-T.FrontDoor / 2, -HALF, T.FrontDoor / 2, HALF))
	for _ = 1, 16 do
		local stuck = stuckNow(S, field)
		if #stuck == 0 then
			break
		end
		makeWay(S, S.placed[stuck[1]], false)
	end
	local stuck = stuckNow(S, field)
	for n = #stuck, 1, -1 do
		table.remove(S.placed, stuck[n])
	end
	-- Danny's spot beside every piece (shared/HouseRoute.luau, as the move's grid reads the plan): a piece he cannot get
	-- to clears its way as a stuck one does (the latest optional piece of its room, the ★ kept, else itself)
	local grid = HouseRoute.grid(routeShell(S, box))
	if grid then
		for _ = 1, 16 do
			local far = unreachable(S, grid)
			if #far == 0 then
				break
			end
			makeWay(S, S.placed[far[1]], true)
			local again = stuckNow(S, field)
			for n = #again, 1, -1 do
				table.remove(S.placed, again[n])
			end
		end
		local far = unreachable(S, grid)
		for n = #far, 1, -1 do
			table.remove(S.placed, far[n])
		end
	end

	-- too few pieces: moving boxes where they fit (and can get out, and Danny can get to them)
	local filler = FILLER[S.kind]
	local fill = 1
	while #S.placed < K.Spots[1] and fill <= #filler * 4 do
		local roomId = filler[(fill - 1) % #filler + 1]
		local how = if fill > #filler * 2 then "wall" else "corner"
		fill += 1
		local p = place(S, roomId, { item = "box", how = how }, false, false)
		if p and (#stuckNow(S, field) > 0 or (grid ~= nil and #unreachable(S, grid) > 0)) then
			table.remove(S.placed, table.find(S.placed, p) :: number)
		end
	end
	-- exactly Stars ★: the sentimental pieces first, then the dearest
	local have = 0
	for _, p in S.placed do
		if p.star then
			have += 1
		end
	end
	if have < K.Stars then
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
			if have >= K.Stars then
				break
			end
			if not p.star then
				p.star = true
				have += 1
			end
		end
	end


	-- the collectibles (as a house's: their own dice, a legendary one now and then, the others by Odds; each in a room
	-- its catalogue room suits, none twice; the place's themed ones first in their rarity; one that finds no place, or
	-- would keep a piece in or from Danny, gives way to another of its rarity, else of the rarity below)
	do
		local rules = T.Collectibles
		local rarities = FurnitureLooks.Rarities
		local dice = newRng(seed + rules.Salt, SALT[S.kind])
		local want = dice.int(K.Collectibles.Count[1], K.Collectibles.Count[2])
		local tiers: { string } = {}
		if dice.num() < K.Collectibles.Legendary then
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
		local list: { Entry } = pool or {}
		if not pool then
			for _, id in (FurnitureLooks :: any).Collectibles or {} do
				table.insert(list, { item = id, how = "wall" })
			end
		end
		local theme: { [string]: boolean } = {}
		for _, id in THEMES[S.kind] do
			theme[id] = true
		end
		-- the rooms a collectible may stand in, in turn
		local function roomsFor(id: string): { string }
			local out: { string } = {}
			local kinds: { string } = COLLECT_IN[FurnitureLooks.Items[id].room] or { "living" }
			for _, kind in kinds do
				for _, roomId in order do
					if S.byId[roomId].kind == kind and not table.find(out, roomId) then
						table.insert(out, roomId)
					end
				end
			end
			if #out == 0 then
				table.insert(out, order[1])
			end
			return out
		end
		local byRarity: { [string]: { Entry } } = {}
		for _, rarity in rarities do
			local mine: { Entry } = {}
			local others: { Entry } = {}
			for _, e in list do
				local def = FurnitureLooks.Items[e.item]
				if def and def.rarity == rarity then
					table.insert(if theme[e.item] then mine else others, e)
				end
			end
			shuffle(mine, dice)
			shuffle(others, dice)
			table.move(others, 1, #others, #mine + 1, mine)
			byRarity[rarity] = if rarity == "legendary" then unfoundFirst(mine, found) else mine
		end
		local tried: { [string]: boolean } = {}
		local count = 0
		local function put(e: Entry): boolean
			tried[e.item] = true
			local ways: { Entry } = { e }
			if e.how ~= "wall" then
				table.insert(ways, { item = e.item, how = "wall" })
			end
			for _, roomId in roomsFor(e.item) do
				for _, way in ways do
					for _ = 1, 3 do
						local p = place(S, roomId, way, false, false)
						if not p then
							break
						end
						if #stuckNow(S, field) == 0 and (grid == nil or #unreachable(S, grid) == 0) then
							count += 1
							return true
						end
						table.remove(S.placed, table.find(S.placed, p) :: number)
						local key = roomId .. "/" .. e.item
						S.banned[key] = S.banned[key] or {}
						table.insert(S.banned[key], p.rect)
					end
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
				if count >= K.Collectibles.Count[1] or rarity == "legendary" then
					break
				end
				if not tried[e.item] then
					put(e)
				end
			end
		end
	end

	-- (and still: a piece Danny cannot get to now goes; none should)
	if grid then
		local far = unreachable(S, grid)
		for n = #far, 1, -1 do
			table.remove(S.placed, far[n])
		end
	end
end

-- The wall decor, high on the walls (its bottom Alpine.Decor up: over every piece), clear of the doorways, the windows
-- and the fixtures that reach that high; over a piece standing at that wall where it can, else the wall's middle. Its
-- own dice: the pieces stay where they were.
local function decor(S: State, seed: number)
	local dice = newRng(seed + 7919, SALT[S.kind])
	local up = T.Alpine.Decor
	type Hung = { room: string, side: string, a: number, b: number }
	local hung: { Hung } = {}
	local function hang(kind: string, roomId: string, size: { number })
		local room = S.byId[roomId]
		if not room then
			return
		end
		local w = size[1]
		type DecorSpot = { side: string, t: number, score: number }
		local cands: { DecorSpot } = {}
		for _, side in SIDES do
			local lo, hi = span(room.inner, side)
			local alongX = side == "S" or side == "N"
			local blocked: { { number } } = {}
			for _, gap in openings(S, room, side) do
				table.insert(blocked, { gap[1] - 0.6, gap[2] + 0.6 })
			end
			for _, wd in S.windows do
				if wd.room == roomId and wd.side == side and wd.y + wd.height / 2 > up - 0.3 then
					table.insert(blocked, { wd.t - wd.width / 2 - 0.4, wd.t + wd.width / 2 + 0.4 })
				end
			end
			local inner = room.inner
			for _, f in S.fixtures do
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
					for _, p in S.placed do
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
		fixture(S, kind, roomId, c.side, c.t, size[1], size[2], size[3], up, false)
		table.insert(hung, { room = roomId, side = c.side, a = c.t - w / 2, b = c.t + w / 2 })
	end
	local A = T.Alpine
	if S.kind == "cabin" then
		hang("net", "main", { 4, 2.6, 0.3 })
		hang("lifebuoy", "main", { 1.8, 1.8, 0.3 })
		hang("picture", "bunks", A.Picture)
	elseif S.kind == "lodge" then
		hang("antlers", "living", A.Antlers)
		hang("antlers", "hall", A.Antlers)
		hang("antlers", "gunroom", A.Antlers)
		hang("picture", "bedroom", A.Picture)
		hang("picture", "living", A.Picture)
	elseif S.kind == "mill" then
		hang("picture", "millers", A.Picture)
	else
		hang("picture", "kitchen", A.Picture)
		hang("picture", "bedroom", A.Picture)
	end
	-- the rugs: under a table, at the foot of a bed
	local function rug(kind: string, roomId: string, x: number, z: number, w: number, d: number, turn: number)
		local inner = S.byId[roomId].inner
		local ex, ez = if norm(turn) % 180 == 0 then w else d, if norm(turn) % 180 == 0 then d else w
		local hx, hz = math.min(ex / 2, (inner.x1 - inner.x0) / 2 - 0.6), math.min(ez / 2, (inner.z1 - inner.z0) / 2 - 0.6)
		x = math.clamp(x, inner.x0 + 0.6 + hx, inner.x1 - 0.6 - hx)
		z = math.clamp(z, inner.z0 + 0.6 + hz, inner.z1 - 0.6 - hz)
		local rw, rd = if norm(turn) % 180 == 0 then hx * 2 else hz * 2, if norm(turn) % 180 == 0 then hz * 2 else hx * 2
		table.insert(S.fixtures, { kind = kind, room = roomId, x = x, y = 0, z = z, w = rw, h = 0.08, d = rd, turn = turn, solid = false, rect = rect(x - hx, z - hz, x + hx, z + hz) })
	end
	for _, p in S.placed do
		if p.item == "dining_table" or p.item == "oak_table" then
			rug("rug", p.room, p.x, p.z, 10, 7.4, p.turn)
		elseif (p.item == "bed" or p.item == "bunk_bed") and p.side then
			local face = SIDE_FACE[p.side]
			rug("rug", p.room, p.x + face[1] * 5.2, p.z + face[2] * 5.2, 7, 3.6, p.turn)
		elseif p.item == "sofa" and p.side then
			local face = SIDE_FACE[p.side]
			rug("round_rug", p.room, p.x + face[1] * 4, p.z + face[2] * 4, 7, 7, 0)
		end
	end
end

-- ── The plan ───────────────────────────────────────────────────────────────────

local function toPlan(S: State, seed: number): Plan
	local rank: { [string]: number } = {}
	for n, id in FURNISH[S.kind] do
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
		table.insert(rooms, { id = room.id, kind = room.kind, min = Vector3.new(inner.x0, 0, inner.z0), max = Vector3.new(inner.x1, S.ceiling, inner.z1) })
	end
	local doors: { Door } = {}
	for n, d in S.doors do
		local axis: Axis = if d.alongX then "X" else "Z"
		table.insert(doors, { at = Vector3.new(d.x, 0, d.z), width = d.width, axis = axis, rooms = { d.a, d.b or "outside" }, front = n == 1 })
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
	local min = Vector3.new(-S.W / 2 - HALF, 0, -HALF)
	local max = Vector3.new(S.W / 2 + HALF, S.ceiling, S.D + HALF)
	local up = T.EntryUp
	return {
		kind = S.kind,
		seed = seed,
		mirrored = S.mirrored,
		size = max - min,
		min = min,
		max = max,
		rooms = rooms,
		doors = doors,
		entry = CFrame.lookAt(Vector3.new(0, up, T.EntryIn), Vector3.new(0, up, T.EntryIn + 1)),
		exit = Vector3.new(0, up, HALF),
		spots = spots,
		ceiling = S.ceiling,
		wall = T.Wall,
		doorHeight = T.DoorHeight,
		faces = S.faces,
		windows = windows,
		fixtures = fixtures,
	}
end

function Countryside.plan(seed: number, kind: string, found: { [string]: any }?, pool: { Entry }?): Plan
	assert(SHELLS[kind], `Countryside.plan: no kind "{kind}"`)
	local W, D = Countryside.size(kind)
	local S: State = {
		kind = kind,
		rng = newRng(seed, SALT[kind]),
		ceiling = C[kind].Ceiling,
		W = W,
		D = D,
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
		extra = {},
	}
	shell(S)
	walls(S)
	FIXTURES[kind](S)
	zones(S)
	furnish(S, found, pool, seed)
	decor(S, seed)
	return toPlan(S, seed)
end

return Countryside
