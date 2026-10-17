--!strict
-- 10.5 ROUNDS (Config.Rounds; the owner: "16 people on one server … a round starts at one place, everybody runs there,
-- everyone has their own car, what you carry off to it quickly is yours … not teams"): the rules of a round, pure (no
-- Roblox: tests/roundrules_test.luau). server/Runs.luau runs the rounds with them, client/RoundUi.luau shows them.
--
--   RoundRules.pick(ids, last, roll) -> id?       the next round's place: one of `ids` (in order) by `roll` (0 … 1), never
--                                                 `last` again when there is another one
--   RoundRules.difficulty(list, roll) -> id       a round's difficulty: one of `list` by `roll` (none: Config.Runs.Default)
--   RoundRules.ranking(pieces, players) -> { Rank }   the round's table: every player in it (`players`: { id, name }, the
--                                                 order they came) with the pieces they took (`pieces`: { to, value }),
--                                                 the most value first, then the most pieces, then who came first;
--                                                 place 1, 2, … (the same value and count share a place)
--   RoundRules.rankOf(ranking, id) -> Rank?       a player's row
--   RoundRules.parking(curb, zone, house, count, P) -> { Spot }   the vans' spots at a place: side by side at its curb,
--                                                 the curb's own first, then the nearest ones beside it and in rows
--                                                 behind it (the way its nose looks), every one inside the zone (P.Margin
--                                                 off its edge) and clear of the house's box; at most Cols × Rows (the
--                                                 server keeps the first `count` it finds free)
--   RoundRules.spread(spot, count, S) -> { Spot } where the players land: rows of S.PerRow abreast (S.Apart apart), each
--                                                 row S.Back nearer the way the spot looks (the house's door: the vans
--                                                 stand behind it), facing that way
--   RoundRules.clock(seconds) -> "m:ss"
local Config = require(script.Parent.Config)

local RoundRules = {}

export type Spot = { x: number, y: number, z: number, yaw: number }
export type Rect = { x0: number, x1: number, z0: number, z1: number }
export type Piece = { to: number, value: number }
export type Player = { id: number, name: string }
export type Rank = { id: number, name: string, count: number, value: number, place: number }
export type Park = { Across: number, Along: number, Cols: number, Rows: number, Margin: number, Width: number, Length: number }
export type Spread = { PerRow: number, Apart: number, Back: number }

function RoundRules.pick(ids: { string }, last: string?, roll: number): string?
	local list: { string } = {}
	for _, id in ids do
		if id ~= last or #ids == 1 then
			table.insert(list, id)
		end
	end
	if #list == 0 then
		return nil
	end
	local n = math.clamp(math.floor(roll * #list) + 1, 1, #list)
	return list[n]
end

function RoundRules.difficulty(list: { string }, roll: number): string
	if #list == 0 then
		return Config.Runs.Default
	end
	return list[math.clamp(math.floor(roll * #list) + 1, 1, #list)]
end

function RoundRules.ranking(pieces: { Piece }, players: { Player }): { Rank }
	local rows: { Rank } = {}
	local byId: { [number]: Rank } = {}
	local came: { [number]: number } = {}
	for n, p in players do
		if not byId[p.id] then
			local row: Rank = { id = p.id, name = p.name, count = 0, value = 0, place = 0 }
			byId[p.id] = row
			came[p.id] = n
			table.insert(rows, row)
		end
	end
	for _, piece in pieces do
		local row = byId[piece.to]
		if row then
			row.count += 1
			row.value += math.max(0, math.floor((tonumber(piece.value) or 0) + 0.5))
		end
	end
	table.sort(rows, function(a: Rank, b: Rank): boolean
		if a.value ~= b.value then
			return a.value > b.value
		elseif a.count ~= b.count then
			return a.count > b.count
		end
		return came[a.id] < came[b.id]
	end)
	for n, row in rows do
		local before = rows[n - 1]
		row.place = if before and before.value == row.value and before.count == row.count then before.place else n
	end
	return rows
end

function RoundRules.rankOf(ranking: { Rank }, id: number): Rank?
	for _, row in ranking do
		if row.id == id then
			return row
		end
	end
	return nil
end

-- (the yaw convention: SandboxMap's, 0 looks north (-z), 90 west)
local function axes(yaw: number): (number, number, number, number)
	local a = math.rad(yaw)
	return -math.sin(a), -math.cos(a), math.cos(a), -math.sin(a) -- look x, z; right x, z
end

-- Does a van standing at (x, z) with its nose along (lx, lz) keep inside `rect` less `margin`, and off `box`?
local function fits(x: number, z: number, lx: number, lz: number, P: Park, zone: Rect, box: Rect?): boolean
	local hw, hl = P.Width / 2, P.Length / 2
	local ex = math.abs(lx) * hl + math.abs(lz) * hw -- (its half extents along x and z)
	local ez = math.abs(lz) * hl + math.abs(lx) * hw
	if x - ex < zone.x0 + P.Margin or x + ex > zone.x1 - P.Margin or z - ez < zone.z0 + P.Margin or z + ez > zone.z1 - P.Margin then
		return false
	end
	if box and x + ex > box.x0 and x - ex < box.x1 and z + ez > box.z0 and z - ez < box.z1 then
		return false
	end
	return true
end

function RoundRules.parking(curb: Spot, zone: Rect, house: Rect?, count: number, P: Park): { Spot }
	local lx, lz, rx, rz = axes(curb.yaw)
	local found: { { spot: Spot, cost: number } } = {}
	local half = math.floor(P.Cols / 2)
	for row = 0, P.Rows - 1 do
		for col = -half, half do
			local across, along = col * P.Across, row * P.Along
			local x = curb.x + rx * across + lx * along
			local z = curb.z + rz * across + lz * along
			if fits(x, z, lx, lz, P, zone, house) then
				-- (the curb's row first, the nearest beside it, then the rows behind: a row costs more than a step aside)
				table.insert(found, { spot = { x = x, y = curb.y, z = z, yaw = curb.yaw }, cost = row * (half + 1) * 2 + math.abs(col) * 2 + (if col < 0 then 1 else 0) })
			end
		end
	end
	table.sort(found, function(a, b): boolean
		return a.cost < b.cost
	end)
	local out: { Spot } = {}
	for _, f in found do
		table.insert(out, f.spot)
	end
	return out
end

function RoundRules.spread(spot: Spot, count: number, S: Spread): { Spot }
	local lx, lz, rx, rz = axes(spot.yaw)
	local per = math.max(1, S.PerRow)
	local out: { Spot } = {}
	for n = 1, count do
		local row = (n - 1) // per
		local inRow = math.min(per, count - row * per)
		local k = (n - 1) % per
		local across = (k - (inRow - 1) / 2) * S.Apart
		local back = row * S.Back
		table.insert(out, { x = spot.x + rx * across + lx * back, y = spot.y, z = spot.z + rz * across + lz * back, yaw = spot.yaw })
	end
	return out
end

function RoundRules.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return RoundRules
