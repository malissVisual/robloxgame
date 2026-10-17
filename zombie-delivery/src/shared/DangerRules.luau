--!strict
-- 10.x DANGER (the owner: "both: on the easier difficulties only a timer and traps, on the harder ones zombies too"; "it
-- has to be designed to be fun"): what a run's house holds besides its loot, pure (no Roblox at its top level:
-- tests/danger_test.luau runs it on the real plans). server/RunDanger.luau builds and runs what it plans, client/
-- RunDangerUi.luau shows it; the numbers are Config.Runs' (Danger by difficulty, Locks, Search, Rooms, Vault, Hazard,
-- Zombies). Positions are a plan's own (shared/HouseLayout.luau: local to its front door, X and Z along the floor); a
-- Rect is { x0, z0, x1, z1 } (shared/HouseRoute.luau's).
--
-- The plan of a run (DangerRules.plan: the house's plan, its seed and the difficulty: the same house at the same
-- difficulty always the same danger):
--   * Locks (Danger.Locks at most): an inside doorway whose leaf, shut, cuts rooms with pieces off the way in (never a
--     room you come in by: DangerRules.lockable), the richer rooms likelier; two locks never cut off the same room. Each
--     lock's key is hidden in a searchable piece (Search.Items, never a collectible) of a room you can get to with the
--     locks before it still shut: never behind its own lock, and a chain at most (the store's key in the bunk room
--     behind the first lock). A lock with no such piece left is not made. A locked room's pieces come Locks.Lift tiers up.
--   * The vault (Danger.Vault pieces, Normal and up): the house's most valuable piece a person can carry (no two-person
--     piece; the dice choose among the best, a room you come in by worth Vault.Entry of another's) and, for two, the next best in its room, each in a steel and glass case;
--     each at least Vault.Floor (Epic), Legendary at Danger.Legendary's chance. Its gold key is hidden like the others,
--     in a locked room's piece when there is one (deeper: rarer), never in the vault.
--   * Hazards (Danger.Creak / Puddle / Plaster at most, as many as the house has floor for): on open floor in a room, a
--     Gap from every doorway, piece, solid fixture, wall, the way in and each other, and never on a way that matters:
--     with every piece standing, every doorway and every piece's reach that a body (Hazard.Radius) could walk to from
--     the way in still can, the hazards in its way (shared/HouseRoute.luau's grid, a flood from the way in).
--
--   DangerRules.difficulty(id) -> id      a known difficulty's id (Config.Runs.Danger), else Config.Runs.Default
--   DangerRules.level(id) -> RunDanger    its numbers
--   DangerRules.searchable(item)          is a piece of that kind searched (Search.Items; never a collectible)
--   DangerRules.roomName(id) / keyName(room?)   "Bedroom" / "Bedroom key" (no room: "Vault key")
--   DangerRules.doorRect(plan, door)      a doorway's opening (its width across, the wall's thickness through)
--   DangerRules.reachable(plan, shut?)    the rooms you can walk to from outside with the doors `shut` ({ [index] = true })
--                                         shut: { [room id] = true }
--   DangerRules.lockable(plan)            the doorways a lock may shut: { door, room (the one behind it), behind (every
--                                         room it cuts off) }
--   DangerRules.footprint(spot)           a plan's piece's footprint (its catalogue size turned as it stands)
--   DangerRules.plan(plan, difficulty, seed?) -> Plan   (seed: the plan's own by default)
--   DangerRules.hazardAt(hazards, x, z)   the hazard (x, z) stands on, nil none
--   DangerRules.nearest(hazards, x, z, range)   the nearest hazard within `range` studs and its studs, nil none
--   DangerRules.knock(id) / plasterDamage(id)   a creak's knock (as hp of a bite: MovingRules.hitDamage) / the plaster's
--                                         damage, × the difficulty's Harm
--   DangerRules.waveDue(startedAt, seconds, now)   is Zombies.WaveAt of the clock gone
--   DangerRules.pickKind(kinds, roll)     a zombie's kind by the weights (roll in [0, 1)); "walker" without any
--   DangerRules.hint(kind)                the HUD's ⚠ words for a hazard near
--   DangerRules.keyText(name, by) / vaultText(by) / lockText(name, by)   the party's lines
--   DangerRules.dice(seed) -> () -> number   a run's own dice (0 … 1; server/RunDanger.luau's spawns and looks: never
--                                         math.random's, the rest of the game's)

local Config = require(script.Parent.Config)
local FurnitureLooks = require(script.Parent.FurnitureLooks)
local HouseRoute = require(script.Parent.HouseRoute)

local DangerRules = {}

export type Rect = HouseRoute.Rect
export type Lock = { door: number, room: string, name: string, behind: { string }, key: number, rect: Rect }
export type Hazard = { kind: string, x: number, z: number, sx: number, sz: number, rect: Rect }
export type Vault = { spots: { number }, room: string, key: number, floors: { [number]: string } }
export type Plan = {
	difficulty: string,
	locks: { Lock },
	vault: Vault?,
	hazards: { Hazard },
	searchable: { number }, -- every spot with a Search prompt (no vault piece)
	keys: { [number]: string }, -- spot → what it hides: "lock1", "lock2" … (locks[n]'s key) or "vault"
	lifts: { [number]: number }, -- spot → tiers up (a locked room's piece)
}
export type Option = { door: number, room: string, behind: { string } }

local KINDS = { "plaster", "creak", "puddle" } -- (placed in this order: the biggest first)
local COUNT = { plaster = "Plaster", creak = "Creak", puddle = "Puddle" }
local TUNE = { plaster = "Plaster", creak = "Creak", puddle = "Puddle" }

local function tune(): any
	return (Config :: any).Runs
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function rect(x0: number, z0: number, x1: number, z1: number): Rect
	return { x0 = math.min(x0, x1), z0 = math.min(z0, z1), x1 = math.max(x0, x1), z1 = math.max(z0, z1) }
end

-- Studs between two rects (0: they touch or overlap).
local function apart(a: Rect, b: Rect): number
	local dx = math.max(a.x0 - b.x1, 0, b.x0 - a.x1)
	local dz = math.max(a.z0 - b.z1, 0, b.z0 - a.z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- ── The dice (as shared/LootRules.luau's: exact in doubles, the same on every server) ─────────────────────────────

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

type Rng = { num: () -> number, int: (number, number) -> number }

local function dice(seed: number, difficulty: string): Rng
	local order = { "easy", "normal", "hard", "insane", "nightmare" }
	local base = if finite(seed) then math.floor(math.abs(seed)) % 4294967296 else 0
	local state = hash((base + 7477 + (table.find(order, difficulty) or 0) * 130363) % 4294967296) % 2147483646 + 1
	local function num(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	for _ = 1, 3 do
		num()
	end
	return {
		num = num,
		int = function(a: number, b: number): number
			return a + math.min(b - a, math.floor(num() * (b - a + 1)))
		end,
	}
end

function DangerRules.dice(seed: number): () -> number
	return dice(seed, "").num
end

-- ── Small rules ────────────────────────────────────────────────────────────

function DangerRules.difficulty(id: any): string
	if type(id) == "string" and tune().Danger[id] ~= nil then
		return id
	end
	return tune().Default
end

function DangerRules.level(id: any): Config.RunDanger
	return tune().Danger[DangerRules.difficulty(id)]
end

local searchSet: { [string]: boolean }? = nil
function DangerRules.searchable(item: any): boolean
	if type(item) ~= "string" then
		return false
	end
	local set = searchSet
	if not set then
		local made: { [string]: boolean } = {}
		for _, id in tune().Search.Items do
			made[id] = true
		end
		searchSet = made
		set = made
	end
	local def = FurnitureLooks.Items[item]
	return (set :: { [string]: boolean })[item] == true and def ~= nil and (def :: any).rarity == nil
end

function DangerRules.roomName(id: string): string
	local name = tune().Rooms[id]
	if type(name) == "string" then
		return name
	end
	return (string.gsub(id, "^%l", string.upper))
end

function DangerRules.keyName(room: string?): string
	return if room then `{DangerRules.roomName(room)} key` else "Vault key"
end

function DangerRules.doorRect(plan: any, door: any): Rect
	local half = (tonumber(plan.wall) or 1) / 2
	local w = (tonumber(door.width) or 4) / 2
	local at = door.at
	if door.axis == "X" then
		return rect(at.X - w, at.Z - half, at.X + w, at.Z + half)
	end
	return rect(at.X - half, at.Z - w, at.X + half, at.Z + w)
end

function DangerRules.footprint(spot: any): Rect
	local def = FurnitureLooks.Items[spot.item] or FurnitureLooks.Items.box
	local at = spot.at.Position
	return HouseRoute.footprint(at.X, at.Z, def.size.X, def.size.Z, math.rad(tonumber(spot.turn) or 0))
end

-- (a solid fixture's footprint as the plan turns it: shared/HouseRoute.luau's)
local function fixtureRect(f: any): Rect
	local turn = ((tonumber(f.turn) or 0) % 360 + 360) % 360
	local ex = if turn % 180 == 0 then f.size.X else f.size.Z
	local ez = if turn % 180 == 0 then f.size.Z else f.size.X
	local p = f.at.Position
	return rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2)
end

-- ── The rooms ──────────────────────────────────────────────────────────────

function DangerRules.reachable(plan: any, shut: { [number]: boolean }?): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	local queue: { string } = {}
	local doors: { any } = plan.doors or {}
	for index, door in doors do
		if shut and shut[index] then
			continue
		end
		local a, b = door.rooms[1], door.rooms[2]
		local inner = if a == "outside" then b elseif b == "outside" then a else nil
		if inner and not seen[inner] then
			seen[inner] = true
			table.insert(queue, inner)
		end
	end
	local head = 1
	while head <= #queue do
		local room = queue[head]
		head += 1
		for index, door in doors do
			if shut and shut[index] then
				continue
			end
			local a, b = door.rooms[1], door.rooms[2]
			local other = if a == room then b elseif b == room then a else nil
			if other and other ~= "outside" and not seen[other] then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	return seen
end

function DangerRules.lockable(plan: any): { Option }
	local all = DangerRules.reachable(plan, nil)
	local out: { Option } = {}
	for index, door in (plan.doors or {}) :: { any } do
		local a, b = door.rooms[1], door.rooms[2]
		if a == nil or b == nil or a == "outside" or b == "outside" then
			continue
		end
		local reach = DangerRules.reachable(plan, { [index] = true })
		local behind: { string } = {}
		for _, room in plan.rooms do
			if all[room.id] and not reach[room.id] then
				table.insert(behind, room.id)
			end
		end
		if #behind > 0 then
			table.insert(out, { door = index, room = if reach[a] then b else a, behind = behind })
		end
	end
	return out
end

-- ── The hazards' floor ─────────────────────────────────────────────────────

-- (the cell under (x, z), 0 off the grid)
local function cellAt(g: HouseRoute.Grid, x: number, z: number): number
	local i = math.floor((x - g.x0) / g.step + 0.5)
	local j = math.floor((z - g.z0) / g.step + 0.5)
	if i < 0 or j < 0 or i >= g.nx or j >= g.nz then
		return 0
	end
	return j * g.nx + i + 1
end

-- (every open cell walkable from `start`, four ways, marked `stamp` in `mark`)
local function flood(g: HouseRoute.Grid, start: number, mark: { number }, stamp: number)
	if start == 0 or g.open[start] ~= 1 then
		return
	end
	local nx, nz, open = g.nx, g.nz, g.open
	local queue = { start }
	mark[start] = stamp
	local head = 1
	while head <= #queue do
		local k = queue[head]
		head += 1
		local i, j = (k - 1) % nx, (k - 1) // nx
		for d = 1, 4 do
			local ni = i + (if d == 1 then 1 elseif d == 2 then -1 else 0)
			local nj = j + (if d == 3 then 1 elseif d == 4 then -1 else 0)
			if ni < 0 or nj < 0 or ni >= nx or nj >= nz then
				continue
			end
			local nk = nj * nx + ni + 1
			if open[nk] == 1 and mark[nk] ~= stamp then
				mark[nk] = stamp
				table.insert(queue, nk)
			end
		end
	end
end

-- (the cells within `pad` studs of `r` marked `stamp`)
local function cellsNear(g: HouseRoute.Grid, r: Rect, pad: number, mark: { number }, stamp: number): { number }
	local out: { number } = {}
	local i0 = math.max(0, math.floor((r.x0 - pad - g.x0) / g.step))
	local i1 = math.min(g.nx - 1, math.ceil((r.x1 + pad - g.x0) / g.step))
	local j0 = math.max(0, math.floor((r.z0 - pad - g.z0) / g.step))
	local j1 = math.min(g.nz - 1, math.ceil((r.z1 + pad - g.z0) / g.step))
	for j = j0, j1 do
		for i = i0, i1 do
			local k = j * g.nx + i + 1
			if mark[k] == stamp and HouseRoute.toRect(g.x0 + i * g.step, g.z0 + j * g.step, r) <= pad then
				table.insert(out, k)
			end
		end
	end
	return out
end

-- The ways in (the front door's entry, a big house's other ways out's insides).
local function waysIn(plan: any): { { number } }
	local out: { { number } } = {}
	if plan.entry then
		local p = plan.entry.Position
		table.insert(out, { p.X, p.Z })
	end
	for _, at in (plan.exits or { plan.exit }) :: { any } do
		if at then
			table.insert(out, { at.X, at.Z })
		end
	end
	return out
end

local function placeHazards(plan: any, level: Config.RunDanger, rng: Rng, pieces: { Rect }): { Hazard }
	local H = tune().Hazard
	local gap = H.Gap
	local placed: { Hazard } = {}
	local want = 0
	for _, kind in KINDS do
		want += math.max(0, math.floor((level :: any)[COUNT[kind]] or 0))
	end
	if want == 0 then
		return placed
	end
	local grid = HouseRoute.grid(plan, H.Radius, H.Grid)
	if not grid then
		return placed
	end
	local g = grid :: HouseRoute.Grid
	HouseRoute.block(g, pieces)
	local doors: { Rect } = {}
	for _, door in (plan.doors or {}) :: { any } do
		table.insert(doors, DangerRules.doorRect(plan, door))
	end
	local solids: { Rect } = {}
	for _, f in (plan.fixtures or {}) :: { any } do
		if f.solid then
			table.insert(solids, fixtureRect(f))
		end
	end
	local ways = waysIn(plan)
	-- the way: from the front door's entry; what must stay walkable once the hazards lie there (every doorway's
	-- opening, every piece's reach that can be walked to now)
	local mark = table.create(g.nx * g.nz, 0)
	local stamp = 1
	local first = ways[1]
	local sx0, sz0 = HouseRoute.snap(g, first[1], first[2], 4)
	local start = if sx0 and sz0 then cellAt(g, sx0, sz0) else 0
	if start == 0 then
		return placed
	end
	flood(g, start, mark, stamp)
	local targets: { { number } } = {}
	for _, r in doors do
		local cells = cellsNear(g, r, 0.6, mark, stamp)
		if #cells > 0 then
			table.insert(targets, cells)
		end
	end
	for _, p in pieces do
		local cells = cellsNear(g, p, gap.Reach, mark, stamp)
		if #cells > 0 then
			table.insert(targets, cells)
		end
	end
	-- (a gap from everything; the rooms by their floor below: a hazard in a bigger room likelier)
	local function fits(r: Rect): boolean
		for _, d in doors do
			if apart(r, d) < gap.Door then
				return false
			end
		end
		for _, p in pieces do
			if apart(r, p) < gap.Piece then
				return false
			end
		end
		for _, s in solids do
			if apart(r, s) < gap.Fixture then
				return false
			end
		end
		for _, w in ways do
			if HouseRoute.toRect(w[1], w[2], r) < gap.Entry then
				return false
			end
		end
		for _, h in placed do
			if apart(r, h.rect) < gap.Each then
				return false
			end
		end
		return true
	end
	local function walkable(r: Rect): boolean
		local list = table.clone(pieces)
		for _, h in placed do
			table.insert(list, h.rect)
		end
		table.insert(list, r)
		HouseRoute.block(g, list)
		stamp += 1
		flood(g, start, mark, stamp)
		for _, cells in targets do
			local reached = false
			for _, k in cells do
				if mark[k] == stamp then
					reached = true
					break
				end
			end
			if not reached then
				return false
			end
		end
		return true
	end
	for _, kind in KINDS do
		local T = H[TUNE[kind]]
		for _ = 1, math.max(0, math.floor((level :: any)[COUNT[kind]] or 0)) do
			for _ = 1, H.Tries do
				local sx, sz = T.Size[1], T.Size[2]
				if rng.num() < 0.5 then
					sx, sz = sz, sx
				end
				local rooms: { any } = {}
				local total = 0
				for _, room in plan.rooms do
					local w = room.max.X - room.min.X - 2 * gap.Wall - sx
					local d = room.max.Z - room.min.Z - 2 * gap.Wall - sz
					if w > 0 and d > 0 then
						table.insert(rooms, { room = room, w = w, d = d, area = (w + sx) * (d + sz) })
						total += (w + sx) * (d + sz)
					end
				end
				if #rooms == 0 then
					break
				end
				local roll = rng.num() * total
				local pick = rooms[#rooms]
				for _, entry in rooms do
					roll -= entry.area
					if roll <= 0 then
						pick = entry
						break
					end
				end
				local x = pick.room.min.X + gap.Wall + sx / 2 + rng.num() * pick.w
				local z = pick.room.min.Z + gap.Wall + sz / 2 + rng.num() * pick.d
				local r = rect(x - sx / 2, z - sz / 2, x + sx / 2, z + sz / 2)
				if fits(r) and walkable(r) then
					table.insert(placed, { kind = kind, x = x, z = z, sx = sx, sz = sz, rect = r })
					break
				end
			end
		end
	end
	return placed
end

-- ── The plan ───────────────────────────────────────────────────────────────

function DangerRules.plan(plan: any, difficulty: any, seed: number?): Plan
	local id = DangerRules.difficulty(difficulty)
	local level = DangerRules.level(id)
	local rng = dice(seed or tonumber(plan.seed) or 0, id)
	local out: Plan = { difficulty = id, locks = {}, vault = nil, hazards = {}, searchable = {}, keys = {}, lifts = {} }
	local spots: { any } = plan.spots or {}
	local roomOf: { [number]: string } = {}
	local pieces: { Rect } = {}
	for _, spot in spots do
		roomOf[spot.id] = spot.room
		table.insert(pieces, DangerRules.footprint(spot))
		if DangerRules.searchable(spot.item) then
			table.insert(out.searchable, spot.id)
		end
	end
	local function worth(spot: any): number
		local def = FurnitureLooks.Items[spot.item]
		return if def and finite(def.value) then def.value else 0
	end
	-- 1. the locks: the richer rooms likelier, never the same room twice
	local scored: { { option: Option, score: number } } = {}
	for _, option in DangerRules.lockable(plan) do
		local sum, count = 0, 0
		for _, spot in spots do
			if table.find(option.behind, spot.room) then
				sum += worth(spot)
				count += 1
			end
		end
		if count > 0 then
			table.insert(scored, { option = option, score = (sum + 50) * (0.4 + rng.num()) })
		end
	end
	table.sort(scored, function(a, b)
		return a.score > b.score
	end)
	local chosen: { Option } = {}
	local cut: { [string]: boolean } = {}
	for _, entry in scored do
		if #chosen >= math.max(0, math.floor(level.Locks)) then
			break
		end
		local clash = false
		for _, room in entry.option.behind do
			clash = clash or cut[room] == true
		end
		if not clash then
			table.insert(chosen, entry.option)
			for _, room in entry.option.behind do
				cut[room] = true
			end
		end
	end
	-- each lock's key: in a searchable piece of a room open with the locks after it still shut
	local shut: { [number]: boolean } = {}
	for _, option in chosen do
		shut[option.door] = true
	end
	local open = DangerRules.reachable(plan, shut)
	local taken: { [number]: boolean } = {}
	for _, option in chosen do
		local candidates: { number } = {}
		for _, spot in out.searchable do
			if open[roomOf[spot]] and not taken[spot] then
				table.insert(candidates, spot)
			end
		end
		if #candidates > 0 then
			local key = candidates[rng.int(1, #candidates)]
			taken[key] = true
			table.insert(out.locks, {
				door = option.door,
				room = option.room,
				name = DangerRules.roomName(option.room),
				behind = option.behind,
				key = key,
				rect = DangerRules.doorRect(plan, plan.doors[option.door]),
			})
			out.keys[key] = `lock{#out.locks}`
			for _, spot in spots do
				if table.find(option.behind, spot.room) then
					out.lifts[spot.id] = tune().Locks.Lift
				end
			end
		end
		for _, room in option.behind do
			open[room] = true -- (its key found, or no lock made: open from here on)
		end
	end
	-- 2. the vault: the best piece a person carries (the dice among the best), another of its room for two
	local count = math.max(0, math.floor(level.Vault))
	if count > 0 then
		local best: { { spot: any, score: number } } = {}
		local entry = DangerRules.reachable(plan, (function(): { [number]: boolean }
			local every: { [number]: boolean } = {} -- (the rooms you come in by: every inside doorway shut)
			for index, door in (plan.doors or {}) :: { any } do
				if door.rooms[1] ~= "outside" and door.rooms[2] ~= "outside" then
					every[index] = true
				end
			end
			return every
		end)())
		for _, spot in spots do
			local def = FurnitureLooks.Items[spot.item]
			if def and def.class ~= "pair" and not taken[spot.id] then
				local deeper = if entry[spot.room] then tune().Vault.Entry else 1 -- (a room you come in by: less likely)
				table.insert(best, { spot = spot, score = worth(spot) * (0.75 + 0.5 * rng.num()) * deeper })
			end
		end
		table.sort(best, function(a, b)
			return a.score > b.score
		end)
		local top = best[1]
		if top then
			local room = top.spot.room
			local pick: { number } = { top.spot.id }
			for n = 2, #best do
				if #pick >= count then
					break
				end
				if best[n].spot.room == room then
					table.insert(pick, best[n].spot.id)
				end
			end
			local deep: { number } = {}
			local rest: { number } = {}
			for _, spot in out.searchable do
				if taken[spot] or table.find(pick, spot) then
					continue
				end
				table.insert(if out.lifts[spot] ~= nil and roomOf[spot] ~= room then deep else rest, spot)
			end
			local list = if #deep > 0 then deep else rest
			if #list > 0 then
				local key = list[rng.int(1, #list)]
				taken[key] = true
				out.keys[key] = "vault"
				local floors: { [number]: string } = {}
				for _, spot in pick do
					floors[spot] = if rng.num() < level.Legendary then "legendary" else tune().Vault.Floor
					out.lifts[spot] = nil
				end
				out.vault = { spots = pick, room = room, key = key, floors = floors }
			end
		end
	end
	local vault = out.vault
	if vault then
		for index = #out.searchable, 1, -1 do
			if table.find(vault.spots, out.searchable[index]) then
				table.remove(out.searchable, index)
			end
		end
	end
	-- 3. the hazards
	out.hazards = placeHazards(plan, level, rng, pieces)
	return out
end

-- ── In a run ───────────────────────────────────────────────────────────────

function DangerRules.hazardAt(hazards: { Hazard }, x: number, z: number): Hazard?
	for _, h in hazards do
		local r = h.rect
		if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
			return h
		end
	end
	return nil
end

function DangerRules.nearest(hazards: { Hazard }, x: number, z: number, range: number): (Hazard?, number)
	local best: Hazard? = nil
	local far = range
	for _, h in hazards do
		local d = HouseRoute.toRect(x, z, h.rect)
		if d <= far then
			best, far = h, d
		end
	end
	return best, far
end

function DangerRules.knock(id: any): number
	return tune().Hazard.Creak.Knock * DangerRules.level(id).Harm
end

function DangerRules.plasterDamage(id: any): number
	return math.floor(tune().Hazard.Plaster.Damage * DangerRules.level(id).Harm + 0.5)
end

function DangerRules.waveDue(startedAt: number, seconds: number, now: number): boolean
	if not finite(startedAt) or not finite(seconds) or not finite(now) or seconds <= 0 then
		return false
	end
	return now - startedAt >= seconds * tune().Zombies.WaveAt
end

function DangerRules.pickKind(kinds: { [string]: number }, roll: number): string
	local names: { string } = {}
	local total = 0
	for name, weight in kinds do
		if finite(weight) and weight > 0 then
			table.insert(names, name)
			total += weight
		end
	end
	if total <= 0 then
		return "walker"
	end
	table.sort(names) -- (a fixed order: the same roll, the same kind)
	local left = math.clamp(if finite(roll) then roll else 0, 0, 0.999999) * total
	for _, name in names do
		left -= kinds[name]
		if left < 0 then
			return name
		end
	end
	return names[#names]
end

local HINTS: { [string]: string } = {
	creak = "⚠ Creaky boards: carry round them, or you drop it",
	puddle = "⚠ Slippery puddle: you will slide",
	plaster = "⚠ Loose plaster overhead: keep moving",
}
function DangerRules.hint(kind: any): string
	return HINTS[if type(kind) == "string" then kind else ""] or "⚠ Careful"
end

function DangerRules.keyText(name: string, by: string): string
	return `🔑 {name} found by {by}`
end

function DangerRules.lockText(name: string, by: string): string
	return `🔓 {by} unlocked the {name}`
end

function DangerRules.vaultText(by: string): string
	return `🗝 {by} opened the vault`
end

return DangerRules
