--!strict
-- Pure grid logic with no dependency on Roblox. An empty cell = false
-- (not nil — arrays with holes break over the network).
-- A player has two grids: the merge board and the squad. Slot ids address both:
-- board = 1 … BoardSize, squad = SquadOffset + 1 … SquadOffset + SquadSize.

local Balance = require(script.Parent.Config.Balance)
local Units = require(script.Parent.Config.Units)

export type Unit = { class: string, tier: number, ascended: boolean? } -- tier = merge level; ascended = two level 9 merged
export type Cell = Unit | false
export type Cells = { Cell }

local Grid = {}

function Grid.new(size: number): Cells
	local cells: Cells = {}
	for i = 1, size do
		cells[i] = false
	end
	return cells
end

function Grid.firstEmpty(cells: Cells): number?
	for i = 1, #cells do
		if not cells[i] then
			return i
		end
	end
	return nil
end

function Grid.count(cells: Cells): number
	local n = 0
	for i = 1, #cells do
		if cells[i] then
			n += 1
		end
	end
	return n
end

-- `limits` = the highest merge level the player has bought for every class (default: no limit).
function Grid.canMerge(a: Cell, b: Cell, limits: { [string]: number }?): boolean
	if a == false or b == false or a.class ~= b.class or a.tier ~= b.tier then
		return false
	end
	local maxTier = Units.maxTier(a.class)
	local cap = if limits then limits[a.class] or 1 else maxTier
	if a.tier >= maxTier then
		-- Two top-level soldiers of a class whose top level is bought become one ASCENDED soldier.
		return cap >= maxTier and not a.ascended and not b.ascended
	end
	return a.tier < math.min(cap, maxTier)
end

-- The soldier two merged ones become.
function Grid.mergeResult(a: Unit): Unit
	if a.tier >= Units.maxTier(a.class) then
		return { class = a.class, tier = a.tier, ascended = true }
	end
	return { class = a.class, tier = a.tier + 1 }
end

-- The merge board unlocks from the row closest to the player (the front) toward the back,
-- left to right. `boardRank(id)` is the position of a pad in that order (1 = first to unlock).
function Grid.boardRank(id: number): number
	local rows = Balance.BoardSize // Balance.BoardColumns
	local row = (id - 1) // Balance.BoardColumns
	local column = (id - 1) % Balance.BoardColumns
	return (rows - 1 - row) * Balance.BoardColumns + column + 1
end

function Grid.isBoardUnlocked(id: number, boardSlots: number): boolean
	return Grid.boardRank(id) <= boardSlots
end

-- Turns a slot id into (grid, index inside that grid), or nil for anything invalid or locked.
function Grid.resolve(board: Cells, squad: Cells, id: any, boardSlots: number): (Cells?, number?)
	if type(id) ~= "number" or id % 1 ~= 0 then
		return nil, nil
	end
	if id >= 1 and id <= Balance.BoardSize then
		if not Grid.isBoardUnlocked(id, boardSlots) then
			return nil, nil
		end
		return board, id
	end
	local index = id - Balance.SquadOffset
	if index >= 1 and index <= Balance.SquadSize then
		return squad, index
	end
	return nil, nil
end

-- Moves, merges or swaps the soldier at `fromCells[from]` with `toCells[to]` (the two grids
-- may be the same). Returns "move" | "merge" | "swap" | nil (nothing happened).
function Grid.interact(fromCells: Cells, from: number, toCells: Cells, to: number, limits: { [string]: number }?): string?
	if fromCells == toCells and from == to then
		return nil
	end
	local a, b = fromCells[from], toCells[to]
	if not a then
		return nil
	end
	if not b then
		toCells[to] = a
		fromCells[from] = false
		return "move"
	end
	if Grid.canMerge(a, b, limits) then
		toCells[to] = Grid.mergeResult(a)
		fromCells[from] = false
		return "merge"
	end
	fromCells[from], toCells[to] = b, a
	return "swap"
end

return Grid
