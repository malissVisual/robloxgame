--!strict
-- 10.6 THE FLOATING ISLANDS, their art (the owner: "grass on top, dirt and stone sides with tapering rock underneath ...
-- the sky all round and below"; Config.Islands): an island's rock under its grass, the decorative floating rocks and the
-- soft clouds under them, as plain numbers in shared/VillageLooks.luau's Piece (one part each). Pure (no Roblox at its
-- top level: tests/islands_test.luau runs it in the Luau CLI), deterministic (an island's own dice: its seed);
-- server/SandboxWorld.luau makes the parts (the grass on top is shared/SandboxScenery.luau tops': its tiles round what
-- has its own ground, the lobby's plaza, the plots' pads, a lawn). A piece's `at` is on the map, its y the world's (not
-- over the ground, as VillageLooks' are); its chunk "islands" (a Persistent model: every client sees every island from
-- anywhere).
--   An island (SandboxMap.Islands' entry; Config.Islands.Body):
--     "IslandDirt"      the dirt under the grass (Body.Dirt deep, Inset in from the grass's edge: the grass's lip over it)
--     "IslandStone"     the stone sides under it (Body.Stone deep, Narrow further in)
--     "IslandTaper"     Body.Taper blocks of rock under that, each Shrink of the one over it, turned a little and off its
--                       middle a little (its dice)
--     "IslandTip"       an upside-down pyramid of four corner wedges from the last block down to the tip: its bottom at
--                       top - depth (IslandLooks.bottom)
--     "IslandBoulder"   boulders out of its sides in the dirt and stone (one every Body.Bulges studs of a side)
--     "IslandHanging"   rocks hanging under the stone's edge (each an upside-down pyramid: one every Body.Hanging studs
--                       round it)
--   Everything of it inside its top's rect (seen from above the grass hides it) but the boulders' faces (Out studs out),
--   nothing over its top less the grass (2 deep), solid but the hanging rocks and the tip (nobody gets there).
--   A rock (SandboxMap.Rocks'): "RockCap" (grass, every Rock.Cap-th one), "RockStone", "RockTip" (its pyramid down to
--   top - depth); decoration (nothing collides).
--   The clouds (Config.Islands.Clouds): "Cloud" puffs (ellipsoids, see-through), banks of them round and under the
--   Bounds; decoration.
--
--   IslandLooks.body(island) -> { Piece }      an island's rock
--   IslandLooks.rock(rock) -> { Piece }        a floating rock
--   IslandLooks.clouds(bounds, seed) -> { Piece }
--   IslandLooks.bottom(island) -> number       its tip's y (top - depth)
--   IslandLooks.pyramid(cx, cz, y, a, b, height, name, color, material, solid) -> { Piece }   an upside-down pyramid:
--                                              its base a × b half sizes (x, z) at y, its tip `height` under it
--   IslandLooks.Materials                      the materials it uses

local Config = require(script.Parent.Config)
local VillageLooks = require(script.Parent.VillageLooks)

local IslandLooks = {}

type Piece = VillageLooks.Piece
type Island = { rect: { x0: number, x1: number, z0: number, z1: number }, top: number, depth: number, look: { dirt: { number }, stone: { number }, rock: { number }, grass: { number } }, seed: number }
type Rock = { x: number, z: number, top: number, size: number, depth: number, seed: number }

IslandLooks.Materials = { "Grass", "Ground", "Slate", "Rock", "SmoothPlastic" }

local B = Config.Islands.Body
local CHUNK = "islands"
local M = 2147483647

-- The dice: a Lehmer generator (VillageLooks' own), stirred first so near seeds part ways.
local function dice(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % (M - 1) + 1
	for _ = 1, 3 do
		state = (state * 48271) % M
	end
	return function(): number
		state = (state * 48271) % M
		return (state - 1) / (M - 1)
	end
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- A colour up to `by` lighter or darker (its dice), kept in 0 … 255.
local function tint(c: { number }, roll: () -> number, by: number): { number }
	local d = math.floor((roll() * 2 - 1) * by + 0.5)
	return { math.clamp(c[1] + d, 0, 255), math.clamp(c[2] + d, 0, 255), math.clamp(c[3] + d, 0, 255) }
end

local function put(out: { Piece }, name: string, shape: string, size: { number }, at: { number }, yaw: number, turn: { number }?, color: { number }, material: string, solid: boolean, alpha: number?): Piece
	local p: Piece = {
		name = name,
		shape = shape,
		size = size,
		at = at,
		yaw = yaw,
		turn = turn,
		color = color,
		material = material,
		solid = solid,
		alpha = alpha,
		tag = nil,
		text = nil,
		unit = nil,
		ground = nil,
		chunk = CHUNK,
	}
	table.insert(out, p)
	return p
end

-- An upside-down pyramid of four corner wedges: its base (a × b: half its size along x and z) at y round (cx, cz), its
-- tip `height` under its middle. Each wedge a quarter (a CornerWedgePart, its apex over its (+X, -Z) corner), turned a
-- quarter more than the one before, then upside down (about X: SandboxMap's yaw then a turn of 180° about X).
function IslandLooks.pyramid(cx: number, cz: number, y: number, a: number, b: number, height: number, name: string, color: { number }, material: string, solid: boolean): { Piece }
	local out: { Piece } = {}
	for q = 0, 3 do
		local angle = q * math.pi / 2
		local ex, ez = if q % 2 == 0 then a else b, if q % 2 == 0 then b else a
		-- (its middle: (-ex / 2, 0, ez / 2) turned by the quarter about Y, then upside down about X: z the other way)
		local ox = -ex / 2 * math.cos(angle) + ez / 2 * math.sin(angle)
		local oz = ex / 2 * math.sin(angle) + ez / 2 * math.cos(angle)
		put(out, name, "CornerWedge", { ex, height, ez }, { cx + ox, y - height / 2, cz - oz }, -math.deg(angle), { 180, 0, 0 }, color, material, solid)
	end
	return out
end

function IslandLooks.bottom(island: Island): number
	return island.top - island.depth
end

-- ── An island ──────────────────────────────────────────────────────────────

function IslandLooks.body(island: Island): { Piece }
	local out: { Piece } = {}
	local roll = dice(island.seed)
	local r = island.rect
	local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
	local W, L = r.x1 - r.x0, r.z1 - r.z0
	local look = island.look
	local y = island.top - B.Grass -- (under the grass)
	-- the dirt, then the stone sides
	local dw, dl = W - 2 * B.Inset, L - 2 * B.Inset
	put(out, "IslandDirt", "Block", { dw, B.Dirt, dl }, { cx, y - B.Dirt / 2, cz }, 0, nil, look.dirt, "Ground", true)
	y -= B.Dirt
	local sw, sl = dw - 2 * B.Narrow, dl - 2 * B.Narrow
	put(out, "IslandStone", "Block", { sw, B.Stone, sl }, { cx, y - B.Stone / 2, cz }, 0, nil, look.stone, "Slate", true)
	-- the boulders out of its sides (in the dirt and the stone, Out studs out of them)
	local function boulders(along: number, side: string)
		local n = math.max(1, math.floor(along / B.Bulges))
		for k = 1, n do
			local t = (k - 0.5) / n + (roll() - 0.5) * 0.4 / n
			local wide = lerp(14, 30, roll())
			local tall = lerp(8, B.Dirt + B.Stone - 4, roll())
			local deep = lerp(8, 12, roll())
			local top = island.top - B.Grass - 0.5 - roll() * 3
			local yy = top - tall / 2
			local turn = (roll() - 0.5) * 24
			local earthy = roll() < 0.4
			local color = tint(if earthy then look.dirt else look.stone, roll, B.Tint)
			-- (its outer face Out studs out of the dirt's face: a little past the grass's edge, under it)
			local x, z, size
			if side == "north" or side == "south" then
				x = lerp(r.x0 + 20, r.x1 - 20, t)
				z = if side == "north" then r.z0 + B.Inset - B.Out + deep / 2 else r.z1 - B.Inset + B.Out - deep / 2
				size = { wide, tall, deep }
			else
				z = lerp(r.z0 + 20, r.z1 - 20, t)
				x = if side == "west" then r.x0 + B.Inset - B.Out + deep / 2 else r.x1 - B.Inset + B.Out - deep / 2
				size = { deep, tall, wide }
			end
			put(out, "IslandBoulder", "Block", size, { x, yy, z }, turn, nil, color, if earthy then "Ground" else "Slate", true)
		end
	end
	boulders(W, "north")
	boulders(W, "south")
	boulders(L, "west")
	boulders(L, "east")
	y -= B.Stone
	-- the taper: blocks, each Shrink of the one over it, then the tip
	local left = island.depth - B.Grass - B.Dirt - B.Stone
	local blocks = left * B.Share
	local h = blocks / B.Taper
	local bw, bl = sw, sl
	local bx, bz = cx, cz
	for k = 1, B.Taper do
		bw, bl = bw * B.Shrink, bl * B.Shrink
		bx += (roll() - 0.5) * 2 * B.Shift * bw
		bz += (roll() - 0.5) * 2 * B.Shift * bl
		local yaw = (roll() - 0.5) * 2 * B.Turn
		put(out, "IslandTaper", "Block", { bw, h, bl }, { bx, y - h / 2, bz }, yaw, nil, tint(look.rock, roll, B.Tint), "Rock", true)
		y -= h
		local _ = k
	end
	for _, p in IslandLooks.pyramid(bx, bz, y, bw / 2, bl / 2, left - blocks, "IslandTip", tint(look.rock, roll, B.Tint), "Rock", false) do
		table.insert(out, p)
	end
	-- the hanging rocks: under the stone's edge, round it
	local round = 2 * (W + L)
	local n = math.max(2, math.floor(round / B.Hanging))
	local under = island.top - B.Grass - B.Dirt - B.Stone
	for k = 1, n do
		local t = (k - 0.5 + (roll() - 0.5) * 0.5) / n * round
		local size = lerp(B.Size * 0.5, B.Size, roll())
		local long = lerp(B.Long * 0.5, B.Long, roll())
		local inset = size / 2 + B.Inset + B.Narrow + 2
		local x, z
		if t < W then
			x, z = r.x0 + t, r.z0 + inset
		elseif t < W + L then
			x, z = r.x1 - inset, r.z0 + (t - W)
		elseif t < 2 * W + L then
			x, z = r.x1 - (t - W - L), r.z1 - inset
		else
			x, z = r.x0 + inset, r.z1 - (t - 2 * W - L)
		end
		x = math.clamp(x, r.x0 + inset, r.x1 - inset)
		z = math.clamp(z, r.z0 + inset, r.z1 - inset)
		for _, p in IslandLooks.pyramid(x, z, under, size / 2, size / 2 * lerp(0.7, 1, roll()), long, "IslandHanging", tint(look.rock, roll, B.Tint), "Rock", false) do
			table.insert(out, p)
		end
	end
	return out
end

-- ── A floating rock ────────────────────────────────────────────────────────

function IslandLooks.rock(rock: Rock): { Piece }
	local out: { Piece } = {}
	local roll = dice(rock.seed * 7919 + 13)
	local C = Config.Islands
	local stone = tint({ 128, 122, 114 }, roll, C.Body.Tint)
	local w, l = rock.size, rock.size * lerp(0.7, 1, roll())
	local yaw = roll() * 90
	local block = math.max(3, rock.depth * 0.3)
	if rock.seed % C.Rock.Cap == 0 then
		put(out, "RockCap", "Block", { w, 1, l }, { rock.x, rock.top - 0.5, rock.z }, yaw, nil, tint({ 98, 140, 62 }, roll, C.Body.Tint), "Grass", false)
	end
	local top = if rock.seed % C.Rock.Cap == 0 then rock.top - 1 else rock.top
	put(out, "RockStone", "Block", { w * 0.94, block, l * 0.94 }, { rock.x, top - block / 2, rock.z }, yaw, nil, stone, "Slate", false)
	local tipTop = top - block
	-- (its pyramid square to the map: a little narrower than the turned block, inside it whatever its turn)
	local half = math.min(w, l) * 0.94 / 2 * 0.72
	for _, p in IslandLooks.pyramid(rock.x, rock.z, tipTop, half, half, rock.depth - (rock.top - tipTop), "RockTip", tint({ 104, 98, 92 }, roll, C.Body.Tint), "Rock", false) do
		table.insert(out, p)
	end
	return out
end

-- ── The clouds ─────────────────────────────────────────────────────────────

function IslandLooks.clouds(bounds: { x0: number, x1: number, z0: number, z1: number }, seed: number): { Piece }
	local out: { Piece } = {}
	local C = Config.Islands.Clouds
	local roll = dice(seed)
	local x0, x1 = bounds.x0 - C.Spread, bounds.x1 + C.Spread
	local z0, z1 = bounds.z0 - C.Spread, bounds.z1 + C.Spread
	-- (the banks on a jittered grid over the area: about Count of them, none on another)
	local across = math.max(1, math.floor(math.sqrt(C.Count * (x1 - x0) / (z1 - z0)) + 0.5))
	local down = math.max(1, math.ceil(C.Count / across))
	local n = 0
	for i = 0, across - 1 do
		for j = 0, down - 1 do
			n += 1
			if n > C.Count then
				break
			end
			local bx = lerp(x0, x1, (i + 0.25 + roll() * 0.5) / across)
			local bz = lerp(z0, z1, (j + 0.25 + roll() * 0.5) / down)
			local by = C.Height + (roll() * 2 - 1) * C.Rise
			for k = 1, C.Puffs do
				local size = lerp(C.Size[1], C.Size[2], roll())
				local px = bx + (k - (C.Puffs + 1) / 2) * size * 0.55 + (roll() - 0.5) * 20
				local pz = bz + (roll() - 0.5) * size * 0.5
				local py = by + (roll() - 0.5) * size * C.Flat * 0.4
				put(out, "Cloud", "Ellipsoid", { size, size * C.Flat, size * lerp(0.6, 0.9, roll()) }, { px, py, pz }, roll() * 180, nil, C.Color, "SmoothPlastic", false, C.Alpha)
			end
		end
	end
	return out
end

return IslandLooks
