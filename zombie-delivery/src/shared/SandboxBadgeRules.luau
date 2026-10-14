--!strict
-- 8.3 SANDBOX, the Roblox badges' rules (Config.SandboxBadges; the owner's guide design/sandbox/BADGES.md): which
-- badges there are, which are set up (an id over 0), which moment or state earns which badge, the TOP MOVERS board's
-- leader, the moves' counter in the save and the admin panel's line. Pure (no Roblox at its top level;
-- tests/sandboxbadges_test.luau): server/SandboxBadges.luau awards with it (and puts its summary on the admins: the
-- attribute AdminBadges, client/AdminPanel.luau's SANDBOX tab), server/PlayerData.luau reads the counter with it. It
-- never errors on junk (a save, a profile, a row): the save's load calls it.
--
--   SandboxBadgeRules.Order               the badge keys in the admin line's (and the guide's) order
--   SandboxBadgeRules.States              the keys a player's state earns (stateOf → fromState): looked at when the save
--                                         has loaded too, so a milestone reached before the badge was set up is awarded
--   SandboxBadgeRules.def(key)            Config's { id, name, description } (nil: no such badge; any type)
--   SandboxBadgeRules.idOf(key)           the badge's Roblox id: a whole number over 0 (nil: not set up, id 0, junk)
--   SandboxBadgeRules.ready()             the keys set up, in Order
--   SandboxBadgeRules.live(studio)        may a badge be awarded here: never in Studio unless Config.SandboxBadges.Studio
--   The moments (each → the keys it earns, in Order):
--   SandboxBadgeRules.finished(move, result)   a move's end (server/Moving.luau's onResult: MovingRules' Move and
--                                         Result) → finished (done or late with a piece home), clean (nothing broken)
--   SandboxBadgeRules.fromMove(finished, clean, moves)   firstMove, tenMoves (moves: the finished moves now, this one
--                                         counted), cleanMove
--   SandboxBadgeRules.fromSale(kind, money, hot)   Collection.onPaid: a "sale" for money → firstSale, with a hot piece
--                                         in it (paid.hot) → hotSale
--   SandboxBadgeRules.fromAdded(item)     Collection.onAdded: a legendary piece came home → legendary
--   SandboxBadgeRules.stateOf(profile, shown)   a player's State from their profile (the moves' counter, the collection
--                                         book, the upgrades, the van's paint) and whether a piece of theirs is on show
--   SandboxBadgeRules.fromState(state)    firstMove, tenMoves, firstShow, legendary, fullBook, firstUpgrade, warehouse5,
--                                         painted (only keys of States)
--   SandboxBadgeRules.upgraded(levels)    anything bought at the UPGRADES desk (a level over its start)
--   SandboxBadgeRules.painted(vanPaint)   anything bought at the PAINT shop, or the van wearing other than the factory's
--   SandboxBadgeRules.topOf(rows, players)   the TOP MOVERS board's leader (SandboxLeaders.rows: ranked) when it has at
--                                         least `players` rows: alone at the top, with a collection worth more than $0
--                                         (its userId; nil: nobody, a tie at the top, too few players)
--   The save (profile.sandboxMoves: the moves finished, for tenMoves):
--   SandboxBadgeRules.Flag                the save's mark (Config.SandboxBadges.Flag)
--   SandboxBadgeRules.movesFromSave(saved)   the counter: only from a real save (money in it) written with the flag, a
--                                         whole number ≥ 0; anything else 0 (8.4 review: a real save without the flag that
--                                         has the "mv:" key in its `rewards`: that key's count)
--   8.4 review, through an older server: an 8.2 server drops sandboxMoves and its flag but keeps the short keys of the
--   save's `rewards`, so the counter goes there too: one "mv:<n>" key, n capped at the most moves a badge wants
--   (Config.SandboxBadges.Moves: the badges need no more), none at 0
--   SandboxBadgeRules.Key                 that prefix
--   SandboxBadgeRules.mirror(rewards, moves)   that key made the count's (the stale ones cleared): every save
--   SandboxBadgeRules.fromRewards(rewards)   the count that key holds (none: 0)
--   SandboxBadgeRules.count(moves)        one more finished move (a whole number, never past 1e9)
--   SandboxBadgeRules.summary(live?, awarded?)   the admin panel's line: how many are set up, whether this server awards
--                                         (live: nil unknown), how many it awarded, and the names set up and not

local Config = require(script.Parent.Config)
local CollectionBookRules = require(script.Parent.CollectionBookRules)
local UpgradeRules = require(script.Parent.UpgradeRules)
local VanPaintRules = require(script.Parent.VanPaintRules)

local SandboxBadgeRules = {}

export type State = {
	moves: number, -- moves finished (profile.sandboxMoves)
	shown: boolean, -- a piece of theirs on a display stand
	legendary: number, -- legendary pieces in the collection book
	found: number, -- pieces found in the collection book …
	total: number, -- … of these
	warehouse: number, -- the warehouse level (1 … 5)
	upgraded: boolean, -- anything bought at the UPGRADES desk
	painted: boolean, -- anything bought at the PAINT shop
}
export type Row = { userId: number, value: number, rank: number }

local LEGENDARY = "legendary" -- (Config.Collection's rarest tier: CollectionBookRules.counts' legendary)
local MAX_MOVES = 1e9

local function tune(): any
	return Config.SandboxBadges
end

SandboxBadgeRules.Order = {
	"firstMove",
	"tenMoves",
	"cleanMove",
	"firstShow",
	"firstSale",
	"hotSale",
	"legendary",
	"fullBook",
	"firstUpgrade",
	"warehouse5",
	"painted",
	"topMover",
} :: { string }
SandboxBadgeRules.States = { "firstMove", "tenMoves", "firstShow", "legendary", "fullBook", "firstUpgrade", "warehouse5", "painted" } :: { string }
SandboxBadgeRules.Flag = tune().Flag :: string

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function whole(n: any): number
	return if finite(n) and n > 0 then math.min(math.floor(n), MAX_MOVES) else 0
end

-- ── The badges ─────────────────────────────────────────────────────────────

function SandboxBadgeRules.def(key: any): Config.SandboxBadgeDef?
	if type(key) ~= "string" then
		return nil
	end
	local badges = tune().Badges
	local def = if type(badges) == "table" then badges[key] else nil
	return if type(def) == "table" then def else nil
end

function SandboxBadgeRules.idOf(key: any): number?
	local def = SandboxBadgeRules.def(key)
	local id: any = if def then def.id else nil
	if not finite(id) or id <= 0 or id ~= math.floor(id) or id > 2 ^ 53 then
		return nil
	end
	return id
end

function SandboxBadgeRules.ready(): { string }
	local out: { string } = {}
	for _, key in SandboxBadgeRules.Order do
		if SandboxBadgeRules.idOf(key) then
			table.insert(out, key)
		end
	end
	return out
end

function SandboxBadgeRules.live(studio: boolean): boolean
	return not studio or tune().Studio == true
end

-- The keys of `earned` (a set) in Order.
local function ordered(earned: { [string]: boolean }): { string }
	local out: { string } = {}
	for _, key in SandboxBadgeRules.Order do
		if earned[key] then
			table.insert(out, key)
		end
	end
	return out
end

-- ── The moments ────────────────────────────────────────────────────────────

function SandboxBadgeRules.finished(move: any, result: any): (boolean, boolean)
	if type(move) ~= "table" or type(result) ~= "table" or (result.how ~= "done" and result.how ~= "late") then
		return false, false
	end
	local home = 0
	if type(move.order) == "table" and type(move.things) == "table" then
		for _, spot in move.order do
			local thing = move.things[spot]
			if type(thing) == "table" and thing.state == "delivered" then
				home += 1
			end
		end
	end
	if home == 0 then
		return false, false
	end
	return true, result.broken == 0
end

function SandboxBadgeRules.fromMove(finished: boolean, clean: boolean, moves: number): { string }
	if not finished then
		return {}
	end
	return ordered({
		firstMove = true,
		tenMoves = whole(moves) >= tune().Moves,
		cleanMove = clean == true,
	})
end

function SandboxBadgeRules.fromSale(kind: any, money: any, hot: any): { string }
	if kind ~= "sale" or not finite(money) or money <= 0 then
		return {}
	end
	return ordered({ firstSale = true, hotSale = finite(hot) and hot > 0 })
end

function SandboxBadgeRules.fromAdded(item: any): { string }
	if type(item) == "string" and CollectionBookRules.rarityOf(item) == LEGENDARY then
		return { "legendary" }
	end
	return {}
end

-- ── The state ──────────────────────────────────────────────────────────────

function SandboxBadgeRules.upgraded(levels: any): boolean
	local none = UpgradeRules.empty()
	for _, id in UpgradeRules.Order do
		if UpgradeRules.level(levels, id) > UpgradeRules.level(none, id) then
			return true
		end
	end
	return false
end

function SandboxBadgeRules.painted(vanPaint: any): boolean
	if type(vanPaint) ~= "table" then
		return false
	end
	if type(vanPaint.owned) == "table" then
		for id, on in vanPaint.owned do
			local item = VanPaintRules.find(id)
			if on == true and item and not VanPaintRules.free(item) then
				return true
			end
		end
	end
	local worn = vanPaint.worn
	if type(worn) == "table" then
		for _, slot in { "paint", "livery" } do
			local id = worn[slot]
			if VanPaintRules.find(id) and id ~= (VanPaintRules.Default :: any)[slot] then
				return true
			end
		end
	end
	return false
end

function SandboxBadgeRules.stateOf(profile: any, shown: boolean?): State
	local p: any = if type(profile) == "table" then profile else {}
	local book = if type(p.collectionBook) == "table" then p.collectionBook else {}
	local counts = CollectionBookRules.counts(book)
	return {
		moves = whole(p.sandboxMoves),
		shown = shown == true,
		legendary = counts.legendary,
		found = counts.found,
		total = counts.total,
		warehouse = UpgradeRules.warehouseLevel(p.sandboxUpgrades),
		upgraded = SandboxBadgeRules.upgraded(p.sandboxUpgrades),
		painted = SandboxBadgeRules.painted(p.vanPaint),
	}
end

function SandboxBadgeRules.fromState(state: State): { string }
	local moves = whole(state.moves)
	return ordered({
		firstMove = moves >= 1,
		tenMoves = moves >= tune().Moves,
		firstShow = state.shown == true,
		legendary = whole(state.legendary) > 0,
		fullBook = whole(state.total) > 0 and whole(state.found) >= whole(state.total),
		firstUpgrade = state.upgraded == true,
		warehouse5 = finite(state.warehouse) and state.warehouse >= tune().Level,
		painted = state.painted == true,
	})
end

-- ── The TOP MOVERS board ───────────────────────────────────────────────────

function SandboxBadgeRules.topOf(rows: any, players: any): number?
	local need = if finite(players) then math.max(1, math.floor(players)) else 1
	if type(rows) ~= "table" or #rows < need then
		return nil
	end
	local first, second = rows[1], rows[2]
	if type(first) ~= "table" or not finite(first.value) or first.value <= 0 or not finite(first.userId) then
		return nil
	end
	if type(second) == "table" and (second.rank == first.rank or (finite(second.value) and second.value >= first.value)) then
		return nil -- (a tie at the top: nobody is alone there)
	end
	return first.userId
end

-- ── The save ───────────────────────────────────────────────────────────────

-- 8.4 review: the counter's short key in `rewards` (an older server keeps it while it drops sandboxMoves).
SandboxBadgeRules.Key = "mv:"

local function mirrorCap(): number
	return math.max(1, whole(tune().Moves))
end

function SandboxBadgeRules.mirror(rewards: { [string]: boolean }, moves: any)
	local n = math.min(whole(moves), mirrorCap())
	local want = if n > 0 then SandboxBadgeRules.Key .. n else nil
	for key in rewards do
		if type(key) == "string" and string.sub(key, 1, #SandboxBadgeRules.Key) == SandboxBadgeRules.Key and key ~= want then
			rewards[key] = nil
		end
	end
	if want then
		rewards[want] = true
	end
end

function SandboxBadgeRules.fromRewards(rewards: any): number
	local most = 0
	if type(rewards) == "table" then
		for key, on in rewards do
			if on == true and type(key) == "string" and #key <= 12 and string.sub(key, 1, #SandboxBadgeRules.Key) == SandboxBadgeRules.Key then
				local n = tonumber(string.sub(key, #SandboxBadgeRules.Key + 1))
				if finite(n) and n == math.floor(n :: number) then
					most = math.max(most, math.min(whole(n), mirrorCap()))
				end
			end
		end
	end
	return most
end

function SandboxBadgeRules.movesFromSave(saved: any): number
	if type(saved) ~= "table" or saved.money == nil then
		return 0
	end
	if saved[SandboxBadgeRules.Flag] ~= true then
		return SandboxBadgeRules.fromRewards(saved.rewards) -- (8.4 review: through an older server; the save's own rewards)
	end
	return whole(saved.sandboxMoves)
end

function SandboxBadgeRules.count(moves: any): number
	return math.min(whole(moves) + 1, MAX_MOVES)
end

-- ── The admin panel's line ─────────────────────────────────────────────────

function SandboxBadgeRules.summary(live: boolean?, awarded: number?): string
	local set: { string } = {}
	local unset: { string } = {}
	for _, key in SandboxBadgeRules.Order do
		local def = SandboxBadgeRules.def(key)
		local name = if def and type(def.name) == "string" then def.name else key
		table.insert(if SandboxBadgeRules.idOf(key) then set else unset, name)
	end
	if #set == 0 then
		return `No badge is set up yet: every id in Config.SandboxBadges is 0, so nothing is awarded ({#unset} badges waiting; how: design/sandbox/BADGES.md).`
	end
	local parts = { `{#set} of {#set + #unset} set up` }
	if live == true then
		table.insert(parts, "awarded on this server")
	elseif live == false then
		table.insert(parts, "not awarded here (Studio: Config.SandboxBadges.Studio is off)")
	end
	if finite(awarded) then
		table.insert(parts, `{whole(awarded)} awarded since the server started`)
	end
	local text = table.concat(parts, " · ") .. `. Set up: {table.concat(set, ", ")}.`
	if #unset > 0 then
		text ..= ` Id 0 (off): {table.concat(unset, ", ")}.`
	end
	return text
end

return SandboxBadgeRules
