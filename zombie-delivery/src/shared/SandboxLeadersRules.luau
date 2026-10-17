--!strict
-- 8.2 SANDBOX, showing off: the rules of the player list's columns and of the TOP MOVERS board at the crossroads
-- (server/SandboxLeaders.luau builds and fills them; the numbers are Config.SandboxLeaders'). Pure (no Roblox at its top
-- level; tests/sandboxleaders_test.luau).
--
--   SandboxLeadersRules.money(n)          "$0", "$0.2", "$45", "$999", "$1.2K", "$12.3K", "$123K", "$3.4M", "$1.2B": a
--                                         tenth under $10, whole dollars up to $999, then K / M / B with one decimal
--                                         under 100 of the unit and none from there (never rounded up a unit:
--                                         $999,999 is "$999K", $1,050 "$1K")
--   SandboxLeadersRules.perMinute(n)      $ a minute to a tenth (the player list's 📈 column)
--   SandboxLeadersRules.isLegendary(entry)   a piece of Config.SandboxLeaders.Legendary's tier (CollectionRules.rarityOf)
--   SandboxLeadersRules.summary(entries)  { count, value, legendaries }: what a collection is worth (CollectionRules
--                                         valueOf summed, on show or not, as CollectionRules.totals) and how many of
--                                         its pieces are legendary
--   SandboxLeadersRules.rank(rows)        the rows best first (a new list): the collection's value, then $ a minute,
--                                         then the legendaries, then the name (A … Z), then the user id; each row's
--                                         `rank` set: a true tie (the same value, $ a minute to the cent and
--                                         legendaries) shares it and the next one skips (1, 1, 3)
--   SandboxLeadersRules.cells(row)        a row's words on the board by column key: rank, name, value, income
--                                         ("+$45", "$0"), legend ("★ 2", "–"), best (the all-time best, "–" without)
--   SandboxLeadersRules.columns(allTime)  the board's columns, left to right: key, title, x and width (shares of the
--                                         board's width), align ("left" | "center" | "right"); the ALL-TIME one only
--                                         with allTime
--   SandboxLeadersRules.spot()            where the board stands (a SandboxMap Spot): 9.7 the lobby's
--                                         (SandboxMap.Lobby.shops.leaders: design/lobby/plan.py, by the plaza's west
--                                         edge, its face to the plaza), on the ground there
--   SandboxLeadersRules.footprint()       { width, depth }: the ground the board covers (its roof is the widest part)
--   SandboxLeadersRules.corners(spot?)    the footprint's four corners on the ground ({ x, z }, round it)
--   SandboxLeadersRules.look(spot?)       the way the board's face looks on the ground (x, z: a unit vector)

local Config = require(script.Parent.Config)
local CollectionRules = require(script.Parent.CollectionRules)
local SandboxMap = require(script.Parent.SandboxMap)
local SandboxScenery = require(script.Parent.SandboxScenery)

local SandboxLeadersRules = {}

export type Row = {
	userId: number,
	name: string, -- the display name
	value: number, -- the collection's worth ($)
	income: number, -- $ a minute now (Collection.incomePerMinute)
	legendaries: number,
	best: number?, -- the all-time best collection value (nil: no ALL-TIME column)
	rank: number, -- set by rank (1 the best)
}
export type Summary = { count: number, value: number, legendaries: number }
export type Column = { key: string, title: string, x: number, width: number, align: string }
export type Corner = { x: number, z: number }

local UNITS: { { number | string } } = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- ── The words ──────────────────────────────────────────────────────────────

function SandboxLeadersRules.money(n: number): string
	local amount = if finite(n) then math.max(0, n) else 0
	if amount < 9.95 then
		local tenth = math.floor(amount * 10 + 0.5) / 10
		if tenth == math.floor(tenth) then
			return "$" .. tostring(math.floor(tenth))
		end
		return string.format("$%.1f", tenth)
	end
	local whole = math.floor(amount + 0.5)
	if whole < 1000 then
		return "$" .. tostring(whole)
	end
	for _, unit in UNITS do
		local size, suffix = unit[1] :: number, unit[2] :: string
		if whole >= size then
			local v = whole / size
			if v >= 100 then
				return string.format("$%d%s", math.floor(v + 1e-9), suffix)
			end
			local tenth = math.floor(v * 10 + 1e-9)
			if tenth % 10 == 0 then
				return string.format("$%d%s", tenth // 10, suffix)
			end
			return string.format("$%d.%d%s", tenth // 10, tenth % 10, suffix)
		end
	end
	return "$" .. tostring(whole)
end

function SandboxLeadersRules.perMinute(n: number): number
	return if finite(n) then math.floor(math.max(0, n) * 10 + 0.5) / 10 else 0
end

-- ── A collection ───────────────────────────────────────────────────────────

function SandboxLeadersRules.isLegendary(entry: { item: string }): boolean
	return CollectionRules.rarityOf(CollectionRules.defOf(entry.item)) == Config.SandboxLeaders.Legendary
end

function SandboxLeadersRules.summary(entries: { CollectionRules.Entry }): Summary
	local out: Summary = { count = 0, value = 0, legendaries = 0 }
	for _, entry in entries do
		out.count += 1
		out.value += CollectionRules.valueOf(entry)
		if SandboxLeadersRules.isLegendary(entry) then
			out.legendaries += 1
		end
	end
	return out
end

-- ── The ranking ────────────────────────────────────────────────────────────

local function cents(n: number): number
	return if finite(n) then math.floor(n * 100 + 0.5) else 0
end

local function tied(a: Row, b: Row): boolean
	return a.value == b.value and cents(a.income) == cents(b.income) and a.legendaries == b.legendaries
end

local function better(a: Row, b: Row): boolean
	if a.value ~= b.value then
		return a.value > b.value
	end
	if cents(a.income) ~= cents(b.income) then
		return cents(a.income) > cents(b.income)
	end
	if a.legendaries ~= b.legendaries then
		return a.legendaries > b.legendaries
	end
	local an, bn = string.lower(a.name), string.lower(b.name)
	if an ~= bn then
		return an < bn
	end
	return a.userId < b.userId
end

function SandboxLeadersRules.rank(rows: { Row }): { Row }
	local out = table.clone(rows)
	table.sort(out, better)
	for index, row in out do
		local above = out[index - 1]
		row.rank = if above and tied(above, row) then above.rank else index
	end
	return out
end

function SandboxLeadersRules.cells(row: Row): { [string]: string }
	local best = row.best
	return {
		rank = tostring(row.rank),
		name = row.name,
		value = SandboxLeadersRules.money(row.value),
		income = if cents(row.income) > 0 then "+" .. SandboxLeadersRules.money(row.income) else "$0",
		legend = if row.legendaries > 0 then `★ {row.legendaries}` else "–",
		best = if best ~= nil then SandboxLeadersRules.money(math.max(best, row.value)) else "–",
	}
end

-- The board's columns (shares of its width), with or without the ALL-TIME one.
local WITH_BEST: { Column } = {
	{ key = "rank", title = "#", x = 0.015, width = 0.07, align = "center" },
	{ key = "name", title = "MOVER", x = 0.1, width = 0.28, align = "left" },
	{ key = "value", title = "COLLECTION", x = 0.39, width = 0.17, align = "right" },
	{ key = "income", title = "$/MIN", x = 0.57, width = 0.13, align = "right" },
	{ key = "legend", title = "LEGENDARY", x = 0.71, width = 0.13, align = "center" },
	{ key = "best", title = "ALL-TIME", x = 0.85, width = 0.135, align = "right" },
}
local WITHOUT_BEST: { Column } = {
	{ key = "rank", title = "#", x = 0.015, width = 0.07, align = "center" },
	{ key = "name", title = "MOVER", x = 0.1, width = 0.34, align = "left" },
	{ key = "value", title = "COLLECTION", x = 0.45, width = 0.2, align = "right" },
	{ key = "income", title = "$/MIN", x = 0.66, width = 0.15, align = "right" },
	{ key = "legend", title = "LEGENDARY", x = 0.82, width = 0.165, align = "center" },
}

function SandboxLeadersRules.columns(allTime: boolean): { Column }
	local out: { Column } = {}
	local list: { Column } = if allTime then WITH_BEST else WITHOUT_BEST
	for _, column in list do
		table.insert(out, table.clone(column))
	end
	return out
end

-- ── Where it stands ────────────────────────────────────────────────────────

function SandboxLeadersRules.spot(): SandboxMap.Spot
	local at = SandboxMap.Lobby.shops.leaders.spot -- (9.7: the lobby's; Pražská and Depot Row are gone)
	return { x = at.x, y = SandboxScenery.groundAt(at.x, at.z), z = at.z, yaw = at.yaw }
end

function SandboxLeadersRules.footprint(): { width: number, depth: number }
	local B = Config.SandboxLeaders.Board
	return { width = B.Width + 2 * B.Roof.Over, depth = 2 * B.Roof.Run }
end

-- (a spot's yaw as Roblox turns it: CFrame.Angles(0, yaw, 0); its X axis (cos, -sin), its look -Z (-sin, -cos))
function SandboxLeadersRules.look(spot: SandboxMap.Spot?): (number, number)
	local a = math.rad((spot or SandboxLeadersRules.spot()).yaw)
	return -math.sin(a), -math.cos(a)
end

function SandboxLeadersRules.corners(spot: SandboxMap.Spot?): { Corner }
	local at = spot or SandboxLeadersRules.spot()
	local a = math.rad(at.yaw)
	local rx, rz = math.cos(a), -math.sin(a)
	local bx, bz = math.sin(a), math.cos(a)
	local f = SandboxLeadersRules.footprint()
	local w, d = f.width / 2, f.depth / 2
	local out: { Corner } = {}
	for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		table.insert(out, { x = at.x + rx * w * s[1] + bx * d * s[2], z = at.z + rz * w * s[1] + bz * d * s[2] })
	end
	return out
end

return SandboxLeadersRules
