--!strict
-- 8.0 SANDBOX: your collection (design/sandbox/KONTRAKT.md, "Collection"). Everything you bring home from a move is
-- yours: it waits in your warehouse's stock until you put it on show on a display stand (then it earns money every
-- minute you play) or sell it. The server decides every value (shared/CollectionRules.luau, Config.Collection); the
-- save keeps the collection (profile.collection = { entries = { Entry }, nextUid }: server/PlayerData.luau reads it
-- with CollectionRules.fromSave, only from a save written with its flag).
--
--   Collection.add(player, entry)              one piece into your stock: entry = { item, variant?, condition, name? }
--                                              → its uid (nil: refused, and why: no save yet, an unknown item, the
--                                              stock full at Config.Collection.MaxStock)
--   Collection.stock(player)                   { Entry } everything you own (on show or not; copies)
--   Collection.display(player, uid, stand)     put a piece of your stock on display stand `stand` (an index of your
--                                              warehouse's stands, CollectionRules.standsFor; one piece a stand; a
--                                              piece on show elsewhere moves there; 8.1: a piece too big for an
--                                              upgrade's small stand is refused, WarehouseLayout.fits; 8.3: the stands
--                                              of your warehouse's level, UpgradeRules.warehouseLevel) → ok, why
--   Collection.undisplay(player, uid)          take it down (back to the stock) → ok, why
--   Collection.sell(player, uid, expect?)      sell it (on show or not) at the market's price (8.3) → the money paid
--                                              (nil: refused), why; `expect` (the price the client asked with): only at
--                                              that price, else refused (the prices moved) and the state sent again
--   Collection.sellAt(player, uid, price, reason)   8.3 visitors: sell it at a price the server set (a visitor's offer,
--                                              server/VisitorOffers.luau), paid as `reason`; else as sell → money?, why
--   Collection.setSale(player, uid, price?)    8.7 trading: a FOR SALE sign on a piece on show at that price (a whole
--                                              number; nil: the sign off) → ok, why (the bounds are server/PlayerTrade's)
--   Collection.transfer(seller, buyer, uid, stand, price, fee)   8.7 trading: the deal between two players, all in one
--                                              go with no yield (server/PlayerTrade.luau prices it): checked first (both
--                                              here with their saves, not the same player, the buyer with a warehouse,
--                                              the seller's piece still on stand `stand`, room in the buyer's stock, the
--                                              buyer's money), then the seller's stands counted at the old rates, the
--                                              piece out of the seller's collection and into the buyer's stock (a new uid
--                                              of the buyer's, not on show, no sign; got now), the price from the buyer
--                                              ("PlayerBuy"), to the seller ("PlayerSale") less the fee ("TradeFee"); the
--                                              onTransferred listeners, both changed; 8.7 review: both saved at once, the
--                                              buyer's first (below) → the buyer's new entry (a copy), nil and why
--                                              (a Refusal: { code, text }: "save", "self", "house", "gone", "full",
--                                              "money", "left")
--   Collection.incomePerMinute(player)         what your pieces on show earn a minute now (8.1: with your lights)
--   Collection.stands(player)                  8.1: the display stands you have (CollectionRules.standsFor: 8.3 your
--                                              warehouse level's big ones and the More stands you bought)
--   Collection.boost(player)                   8.1: your income's × (CollectionRules.boost: the Showroom lights)
--   Collection.upgrade(player, apply)          8.1 (server/Upgrades.luau): an upgrade bought or reset. What the stands
--                                              earned up to now is counted at the old rates, apply() changes the
--                                              levels, the pieces on stands you no longer have go back to the stock
--                                              (how many: the return; 8.3: a warehouse level up keeps every stand, a
--                                              level down, the admin's RESET, loses some, and a piece too big for
--                                              its stand at the new level goes back too), the state goes out and the
--                                              listeners hear
--   Collection.openPicker(player, stand)       (Warehouse: an empty display stand's prompt) ask the player's client to
--                                              pick a piece for it (the "Collection" remote's { kind = "pick", stand })
--   Collection.clear(player)                   (the admin's CLEAR STOCK) the whole collection gone for nothing → how many
--   Collection.onChanged(fn)                   fn(player) after any change to a player's collection (and when their
--                                              save has loaded)
--   Collection.onAdded(fn)                     8.2: fn(player, entry) after a piece came home (Collection.add took it;
--                                              entry a copy): the collection book (server/CollectionBook.luau)
--   Collection.onTransferred(fn)               8.7 review: fn(buyer, seller, entry) after a deal between players
--                                              (Collection.transfer; entry the buyer's new piece, a copy: its new uid),
--                                              before the collections' change (onChanged) and the saves: the book marks
--                                              it bought (server/CollectionBook.luau), the daily tasks and the analytics
--                                              take its uid as seen (server/SandboxTasks.luau, SandboxAnalytics.luau)
--   Collection.onPaid(fn)                      8.2: fn(player, "income" | "sale", money, paid) after the stands paid or a
--                                              piece sold (server/SandboxTasks.luau); 8.3: paid = { hot }: the dollars of
--                                              that income the hot kinds earned, the hot pieces of that sale
--   Collection.market(player)                  8.3: the player's market now (shared/Market.luau's View: today's hot and
--                                              cold kinds, their own demand; nil: no save yet)
--   Collection.marketIncome(item)              8.3: today's × on the income of a piece of that kind (Market.incomeFactor:
--                                              the stands' $/min tags, server/Warehouse.luau)
--   Collection.active(player)                  8.3 economy: the player did something now (their stands pay in full
--                                              again; the remotes and the walking below call it by themselves)
--   Collection.idle(player)                    8.3 economy: the share their stands pay now (1: active; IdleShare: idle)
--   Collection.tick()                          pays everybody here what their stands earned since the last payout (the
--                                              loop runs it every Config.Collection.Tick s)
--   Collection.start()                         the remote, joining and leaving, the payout loop
--
-- The "Collection" remote (Config.Robust.Limits.Collection requests a second; every input checked):
--   client → server   { kind = "display", uid, stand } | { kind = "undisplay", uid } | { kind = "sell", uid } |
--                     { kind = "state" }; a refusal comes back as a Notice (its why)
--   server → client   { kind = "state", stock = { View }, income, stands, market, idle? (8.3 economy) } after every
--                     change (once a frame), when the save has loaded and when asked (a View is an Entry with rarity, value, income, price,
--                     broken, 8.3 base and market: CollectionRules.view; market the player's Market View); { kind =
--                     "pick", stand } opens the picker; { kind = "sold", name, money }
-- 8.3, the market (shared/Market.luau, Config.Market): every price and the stands' income are the market's. Today's hot
-- kinds sell for more and earn more on show, the cold one sells for less (the day's picks, the same on every server);
-- every piece of a kind the player sells weighs on that kind's price for them (profile.market, saved with its flag:
-- server/PlayerData.luau), a step of it comes back every Config.Market.Recover s. The market's day turns at the first
-- payout after 00:00 UTC: what the stands earned up to then is counted at the old day's rates, then every state goes
-- out again (the warehouses' tags hear the change); when a step of a player's demand comes back their state goes out
-- again at the next payout. A sale's CollectionSold carries the market ("hot", "cold"; a bulk sale: "hot" when a hot
-- piece was in it, else "cold" when a cold one was).
-- The income is exact: whenever the pieces on show change (one put up, taken down, sold) and at every payout, what they
-- earned up to that moment is counted; every Tick s the whole dollars are paid ("CollectionIncome"), the cents wait for
-- the next payout; leaving pays what was counted. A sale pays "CollectionSale". Analytics (PlayerData.track):
-- CollectionAdded (once a frame: how many came home, the rarest), CollectionDisplayed, CollectionSold.
-- 8.7 trading (server/PlayerTrade.luau): a piece on show may carry a FOR SALE sign (entry.sale, its price; in the state's
-- View too); taking it down (one, or TAKE ALL DOWN), a stand lost to a level down and selling it end the sign, a move to
-- another stand keeps it. A deal between players (Collection.transfer) is no "sale" for onPaid (the daily sell tasks, the
-- sale badges) and no piece come home for onAdded: a piece passed back and forth between friends must earn nobody a
-- task. 8.7 review: its new uid is none either (onTransferred: the "home" / "rare" tasks and CollectibleFound skip it,
-- the book marks it bought, never found). The deal's two saves are written at once, the buyer's first and the seller's
-- once it landed (no saveSoon: its Gap and the request budget's Reserve put up to a minute between the two, and a crash
-- there duped the piece or made money): a crash between them leaves the piece in both saves, paid for by the buyer,
-- never the price with nobody's piece. (A follow-up could close that last step: a pending deal in the buyer's save,
-- settled on the seller's next load.)
-- 8.3 economy, AFK (the owner: the money should take long to save up, not come by itself): the stands pay in full while
-- their owner plays; after Config.Collection.IdleAfter s without activity only IdleShare of it (0: nothing), counted
-- exactly (the idle stretch of a payout at the share, the rest in full). Activity is what the server sees, one clock a
-- player (Meter.active): the character's root moved IdleMove studs or more over the ground since the last such move
-- (looked at every payout: walking, a van driven; a jump is none), or a call of one of Config.Collection.IdleRemotes
-- (the Collection, Moving, Upgrades, SandboxTasks, Visitors, VanPaint and 8.7's PlayerTrade remotes; a bare "state"
-- ask does not count: the clients send those by themselves).
-- The state's `idle` (the share, only while idle) puts "· idle" on the HUD's income line; the state goes out again when
-- the player goes idle and when they come back. Roblox kicks an idle player after about 20 minutes, but anti-idle
-- macros exist: a jump in place or a key pressed now and then does not count.
-- 8.2, the STOCK list's bulk buttons (client/WarehouseUi.luau; which pieces: shared/StockPlan.luau, the rules the window
-- shows before it asks). Only through the remote, each also under Config.Robust.Limits.CollectionBulk, each one change
-- (one state push, one listener call, one analytics event, one payment):
--   client → server   { kind = "fillbest" }            ⭐ FILL BEST: the best earners of the stock onto every free stand
--                                                      the player has, each where it fits (WarehouseLayout.fits at
--                                                      their warehouse level, 8.3);
--                                                      CollectionDisplayed (their $ a minute, the rarest); then
--                                                      { kind = "bulk", action = "fillbest", count, income } (the $ a
--                                                      minute they add)
--                     { kind = "sellmany", filter, uids, expect? }   💰 SELL…: every piece in the stock the filter takes
--                                                      ("common", "broken", "duplicates": all but the best of each item;
--                                                      never a piece on show), sold at the server's prices (8.3: the
--                                                      market's, one after the other in StockPlan.toSell's order:
--                                                      StockPlan.price): one "CollectionSale" (the SKU the item when they
--                                                      are all one item), CollectionSold (the money, the rarest, the
--                                                      market), { kind = "sold", name = "N pieces", money, count }. The
--                                                      client's confirm shows the same total and sends it as `expect`:
--                                                      another total (the prices moved) sells nothing, says so and sends
--                                                      the state again. 8.4 review: `uids`, the pieces the confirm listed
--                                                      (each once, Config.Collection.MaxStock at most), is a must and
--                                                      exactly what is sold: when the filter takes other pieces now (one
--                                                      came home since, a better copy made the best one a duplicate)
--                                                      nothing is sold, the Notice says so and the state goes out again
--                     { kind = "undisplayall" }        ↩ TAKE ALL DOWN: every piece on show back to the stock (what they
--                                                      earned up to now counts); { kind = "bulk", action =
--                                                      "undisplayall", count }
--                     nothing to do (no free stand, nothing that fits, nothing to sell or on show), a filter that isn't
--                     one or no save: refused, the Notice says why.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.CollectionRules)
local WarehouseLayout = require(Shared.WarehouseLayout) -- 8.1: the upgrade stands' size (fits)
local UpgradeRules = require(Shared.UpgradeRules) -- 8.3: the warehouse level (whose stands' sizes)
local StockPlan = require(Shared.StockPlan) -- 8.2: the STOCK list's bulk buttons
local Market = require(Shared.Market) -- 8.3: the market (hot and cold kinds, the player's demand)
local PlayerData = require(script.Parent.PlayerData)

local Collection = {}

-- 8.2 e2e: who has a warehouse to show pieces in (server/SandboxBoot.luau sets it: SandboxPlots.of; nil: everybody, as
-- the tests' runtimes). Without one (a full server's fifth player) nothing goes on show and nothing of theirs earns; the
-- saved stands stay as they are for when a plot is free.
Collection.hasWarehouse = nil :: ((Player) -> boolean)?
local NO_WAREHOUSE = "Displays are for a warehouse of your own: wait for a free plot."

export type Entry = Rules.Entry

local MAX_UID = 64 -- a longer uid from a client is no piece of ours
local MAX_NAME = 60

local remote = Net.get("Collection")
local notice = Net.get("Notice")

local listeners: { (Player) -> () } = {}
local addedListeners: { (Player, Entry) -> () } = {} -- 8.2: Collection.onAdded's
local transferredTo: { (Player, Player, Entry) -> () } = {} -- 8.7 review: Collection.onTransferred's
export type Paid = { hot: number } -- 8.3: Collection.onPaid's last argument
local paidTo: { (Player, string, number, Paid) -> () } = {} -- 8.2: Collection.onPaid's fns

-- The income counted for each player here: up to `at` (os.clock), `carry` $ not paid yet (8.3: `hot` of it earned by
-- the hot kinds). 8.3 economy, AFK: `active` the os.clock of their last activity, `idle` whether their state says they
-- are idle, `pos` where their root was at the last move that counted.
type Meter = { at: number, carry: number, hot: number, active: number, idle: boolean, pos: Vector3? }
local meters: { [Player]: Meter } = {}
local pushing: { [Player]: boolean } = {} -- a state push waits for the frame's end
type Batch = { n: number, rarity: string }
local added: { [Player]: Batch } = {} -- pieces that came home this frame (one analytics event)
local refused: { [Player]: number } = {} -- pieces refused this frame (stock full: one notice)
local marketDay = Market.dayOf(os.time()) -- 8.3: the market's day (it turns at the first payout after 00:00 UTC)
local marketDue: { [Player]: number } = {} -- 8.3: os.time() a step of the player's demand comes back (the state again)

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function cents(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local function collectionOf(player: Player): Rules.Saved?
	local profile = PlayerData.get(player)
	return if profile then profile.collection else nil
end

local function standsOf(player: Player): number
	return Rules.standsFor(PlayerData.get(player))
end

-- 8.3: the player's warehouse level (1 … 5: their ZDC Warehouse upgrade; no save yet: the garage): whose stands are
-- big and small (WarehouseLayout.fits, count).
local function levelOf(player: Player): number
	local profile = PlayerData.get(player)
	return UpgradeRules.warehouseLevel(if profile then profile.sandboxUpgrades else {})
end

-- Does a piece of this item stand on stand i of a warehouse of that level (as Collection.display: an upgrade's small
-- stand holds no bed)?
local function fitsStand(stand: number, item: string, level: number): boolean
	local def = Rules.defOf(item)
	return def == nil or WarehouseLayout.fits(stand, def.size, level)
end

-- 8.3: the same for the player's warehouse as it is now (CollectionRules.fitStands: a level down sends a piece too big
-- for its stand back to the stock).
local function fitsFor(player: Player): (number, string) -> boolean
	local level = levelOf(player)
	return function(stand: number, item: string): boolean
		return fitsStand(stand, item, level)
	end
end

-- 8.1: the player's income × (their Showroom lights).
local function boostOf(player: Player): number
	return Rules.boost(PlayerData.get(player))
end

-- 8.3: the player's market now (today's hot and cold kinds, their demand; nil: no save yet).
local function marketOf(player: Player): Market.View?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	return Market.view(profile.market, marketDay, os.time())
end

-- The player's piece with this uid (and its index), nil for anything else.
local function find(collection: Rules.Saved, uid: any): (Entry?, number?)
	if type(uid) ~= "string" or #uid > MAX_UID then
		return nil, nil
	end
	for index, entry in collection.entries do
		if entry.uid == uid then
			return entry, index
		end
	end
	return nil, nil
end

local function isStand(stand: any, count: number): boolean
	return finite(stand) and stand == math.floor(stand) and stand >= 1 and stand <= count
end

-- What the pieces on show earn a minute (only on the stands the warehouse has; 8.1: × the lights; 8.3: × the market's)
-- and how much of it the hot kinds earn.
local function rate(player: Player, collection: Rules.Saved): (number, number)
	local housed = Collection.hasWarehouse
	if housed and not housed(player) then
		return 0, 0 -- (no warehouse of their own: nothing on show earns)
	end
	local stands = standsOf(player)
	local boost = boostOf(player)
	local market = marketOf(player)
	local total, hot = 0, 0
	for _, entry in collection.entries do
		local stand = entry.stand
		if stand ~= nil and stand >= 1 and stand <= stands then
			local earns = Rules.income(entry, boost, market)
			total += earns
			if Market.tag(market, entry.item) == "hot" then
				hot += earns
			end
		end
	end
	return total, hot
end

-- Counts what the pieces on show earned up to now (before they change, and at every payout).
local function settle(player: Player)
	local meter = meters[player]
	local collection = collectionOf(player)
	if not meter or not collection then
		return
	end
	local now = os.clock()
	local seconds = math.clamp(now - meter.at, 0, Config.Collection.Tick * 6) -- (a stalled server pays no hours)
	meter.at = now
	local total, hot = rate(player, collection)
	-- 8.3 economy, AFK: the stretch of it past IdleAfter without activity counts at IdleShare
	local C = Config.Collection
	local idle = math.clamp(now - (meter.active + C.IdleAfter), 0, seconds)
	local counted = seconds - idle + idle * math.clamp(C.IdleShare, 0, 1)
	meter.carry += total * counted / 60
	meter.hot += hot * counted / 60
end

-- 8.3 economy, AFK: the share `player`'s stands pay now (1: active; Config.Collection.IdleShare: idle).
local function shareOf(player: Player): number
	local meter = meters[player]
	local C = Config.Collection
	return if meter and os.clock() - meter.active >= C.IdleAfter then math.clamp(C.IdleShare, 0, 1) else 1
end

-- Pays the whole dollars counted (the cents stay for the next payout).
local function payout(player: Player)
	local meter = meters[player]
	if not meter then
		return
	end
	local pay = math.floor(meter.carry + 1e-9)
	if pay >= 1 then
		meter.carry -= pay
		local hot = math.min(pay, math.floor(meter.hot + 1e-9)) -- (8.3: the hot kinds' whole dollars of it)
		meter.hot -= hot
		PlayerData.addMoney(player, pay, "CollectionIncome")
		for _, fn in paidTo do task.spawn(fn, player, "income", pay, { hot = hot }) end -- 8.2: Collection.onPaid
	end
end

local function sendState(player: Player)
	pushing[player] = nil
	local collection = collectionOf(player)
	if not collection or not player.Parent then
		return
	end
	local stock = table.create(#collection.entries)
	local boost = boostOf(player)
	local market = marketOf(player)
	for _, entry in collection.entries do
		table.insert(stock, Rules.view(entry, boost, market))
	end
	local profile = PlayerData.get(player)
	local wait: number? = if profile then Market.nextChange(profile.market, marketDay, os.time()) else nil
	marketDue[player] = nil
	if wait ~= nil then
		marketDue[player] = os.time() + math.max(1, math.ceil(wait)) -- (8.3: a step of the demand back: the state again)
	end
	local share = shareOf(player)
	local meter = meters[player]
	if meter then
		meter.idle = share < 1
	end
	remote:FireClient(player, { kind = "state", stock = stock, income = cents((rate(player, collection))), stands = standsOf(player), market = market, idle = if share < 1 then share else nil })
end

-- The state goes out once at the frame's end, however many changes it had (a van unloaded: one push).
local function pushState(player: Player)
	if pushing[player] then
		return
	end
	pushing[player] = true
	task.defer(function()
		if pushing[player] then
			sendState(player)
		end
	end)
end

local function changed(player: Player)
	pushState(player)
	for _, fn in listeners do
		task.spawn(fn, player)
	end
end

-- Analytics: the pieces that came home this frame as one event (how many, the rarest).
local function noteAdded(player: Player, rarity: string)
	local batch = added[player]
	if not batch then
		local fresh: Batch = { n = 0, rarity = rarity }
		batch = fresh
		added[player] = fresh
		task.defer(function()
			if added[player] == fresh then
				added[player] = nil
			end
			PlayerData.track("event", player, "CollectionAdded", fresh.n, fresh.rarity)
		end)
	end
	batch.n += 1
	if Rules.tier(rarity).rank > Rules.tier(batch.rarity).rank then
		batch.rarity = rarity
	end
end

-- The stock is full: one notice a frame, however many pieces did not fit.
local function noteRefused(player: Player)
	local count = refused[player]
	refused[player] = (count or 0) + 1
	if count then
		return
	end
	task.defer(function()
		local n = refused[player] or 1
		refused[player] = nil
		if player.Parent then
			local what = if n == 1 then "A piece" else `{n} pieces`
			notice:FireClient(player, `{what} didn't fit: your warehouse is full ({Config.Collection.MaxStock} pieces). Sell some!`)
		end
	end)
end

-- ── The API ────────────────────────────────────────────────────────────────

function Collection.add(player: Player, entry: { item: string, variant: number?, condition: number, name: string? }): (string?, string?)
	local profile = PlayerData.get(player)
	if not profile then
		return nil, "Your save isn't loaded yet."
	end
	local raw: any = entry
	local def = if type(raw) == "table" and type(raw.item) == "string" then Rules.defOf(raw.item) else nil
	if not def then
		return nil, "That's no piece of furniture."
	end
	local collection = profile.collection
	if #collection.entries >= Config.Collection.MaxStock then
		noteRefused(player)
		return nil, `Your warehouse is full ({Config.Collection.MaxStock} pieces): sell some first.`
	end
	local condition = if finite(raw.condition) then math.floor(math.clamp(raw.condition, 0, 1) * 1000 + 0.5) / 1000 elseif raw.condition == nil then 1 else 0
	local variant = if finite(raw.variant) then math.clamp(math.floor(raw.variant), 1, 99) else 1
	local name = if type(raw.name) == "string" and #raw.name >= 1 and #raw.name <= MAX_NAME then raw.name else def.name
	local uid = Rules.uid(player.UserId, collection.nextUid)
	collection.nextUid += 1
	while find(collection, uid) do -- (never from a clean save; a guard all the same)
		uid = Rules.uid(player.UserId, collection.nextUid)
		collection.nextUid += 1
	end
	table.insert(collection.entries, {
		uid = uid,
		item = def.id,
		variant = variant,
		condition = condition,
		name = name,
		stand = nil,
		got = os.time(),
	})
	local piece = table.clone(collection.entries[#collection.entries]) -- (8.2: for Collection.onAdded)
	noteAdded(player, Rules.rarityOf(def))
	PlayerData.saveSoon(player) -- (8.3 saves: a trip's pieces home are saved a moment later, one save for the van)
	changed(player)
	for _, fn in addedListeners do -- (8.2: the collection book)
		task.spawn(fn, player, table.clone(piece))
	end
	return uid, nil
end

function Collection.stock(player: Player): { Entry }
	local collection = collectionOf(player)
	local out: { Entry } = {}
	if collection then
		for _, entry in collection.entries do
			table.insert(out, table.clone(entry))
		end
	end
	return out
end

function Collection.display(player: Player, uid: string, stand: number): (boolean, string?)
	local collection = collectionOf(player)
	if not collection then
		return false, "Your save isn't loaded yet."
	end
	local entry = find(collection, uid)
	if not entry then
		return false, "That piece isn't in your stock."
	end
	local housed = Collection.hasWarehouse
	if housed and not housed(player) then
		return false, NO_WAREHOUSE
	end
	if not isStand(stand, standsOf(player)) then
		return false, "There's no such display stand."
	end
	if entry.stand == stand then
		return true, nil
	end
	local def = Rules.defOf(entry.item)
	local level = levelOf(player)
	if def and not WarehouseLayout.fits(stand, def.size, level) then
		return false, `Your {entry.name} is too big for small stand {stand}: show it on stands 1 – {WarehouseLayout.count(level)}.`
	end
	for _, other in collection.entries do
		if other.stand == stand then
			return false, `That stand already shows your {other.name}.`
		end
	end
	settle(player)
	entry.stand = stand
	PlayerData.track("event", player, "CollectionDisplayed", math.floor(Rules.income(entry, boostOf(player), marketOf(player)) + 0.5), Rules.rarityOf(Rules.defOf(entry.item)))
	changed(player)
	return true, nil
end

function Collection.undisplay(player: Player, uid: string): (boolean, string?)
	local collection = collectionOf(player)
	if not collection then
		return false, "Your save isn't loaded yet."
	end
	local entry = find(collection, uid)
	if not entry then
		return false, "That piece isn't in your stock."
	end
	if entry.stand == nil then
		return false, "That piece isn't on show."
	end
	settle(player)
	entry.stand = nil
	entry.sale = nil -- (8.7: its FOR SALE sign comes down with it)
	changed(player)
	return true, nil
end

function Collection.sell(player: Player, uid: string, expect: number?): (number?, string?)
	local collection = collectionOf(player)
	local profile = PlayerData.get(player)
	if not collection or not profile then
		return nil, "Your save isn't loaded yet."
	end
	local entry, index = find(collection, uid)
	if not entry or not index then
		return nil, "That piece isn't in your stock."
	end
	local market = marketOf(player)
	local price = Rules.sell(entry, market) -- (8.3: the market's price)
	if expect ~= nil and price < expect then -- (8.3 review: only a price that fell: one that rose is paid, never refused)
		sendState(player) -- (8.3: the prices moved since the client asked: it sees them now)
		return nil, `The market moved: your {entry.name} sells for {Market.money(price)} now.`
	end
	settle(player) -- (on show: what it earned up to now still counts)
	table.remove(collection.entries, index)
	Market.note(profile.market, entry.item, marketDay, os.time()) -- (8.3: one more of its kind sold today)
	local tag = Market.tag(market, entry.item)
	PlayerData.addMoney(player, price, "CollectionSale", entry.item)
	for _, fn in paidTo do task.spawn(fn, player, "sale", price, { hot = if tag == "hot" then 1 else 0 }) end -- 8.2: Collection.onPaid
	remote:FireClient(player, { kind = "sold", name = entry.name, money = price })
	PlayerData.track("event", player, "CollectionSold", price, Rules.rarityOf(Rules.defOf(entry.item)), tag)
	changed(player)
	return price, nil
end

-- 8.3 visitors: a piece sold at a price the server set elsewhere (server/VisitorOffers.luau: a visitor's offer), paid
-- for `reason` (AnalyticsPlan's Sources: "VisitorOffer"). As Collection.sell: on show or not, what it earned up to now
-- counts, the market's demand weighs one more of its kind, onPaid "sale", "sold", CollectionSold. → money?, why
function Collection.sellAt(player: Player, uid: string, price: number, reason: string): (number?, string?)
	local collection = collectionOf(player)
	local profile = PlayerData.get(player)
	if not collection or not profile then
		return nil, "Your save isn't loaded yet."
	end
	local entry, index = find(collection, uid)
	if not entry or not index then
		return nil, "That piece isn't in your stock."
	end
	if not finite(price) or price ~= math.floor(price) or price < 1 or price >= 2 ^ 40 or type(reason) ~= "string" then
		return nil, "That's no price."
	end
	local tag = Market.tag(marketOf(player), entry.item)
	settle(player)
	table.remove(collection.entries, index)
	Market.note(profile.market, entry.item, marketDay, os.time())
	PlayerData.addMoney(player, price, reason, entry.item)
	for _, fn in paidTo do task.spawn(fn, player, "sale", price, { hot = if tag == "hot" then 1 else 0 }) end
	remote:FireClient(player, { kind = "sold", name = entry.name, money = price })
	PlayerData.track("event", player, "CollectionSold", price, Rules.rarityOf(Rules.defOf(entry.item)), tag)
	changed(player)
	return price, nil
end

-- 8.7 trading: a FOR SALE sign on a piece on show (its price, a whole number of dollars; nil: the sign comes off). The
-- price's bounds are server/PlayerTrade.luau's (shared/PlayerTradeRules.luau): here only a sane number.
function Collection.setSale(player: Player, uid: string, price: number?): (boolean, string?)
	local collection = collectionOf(player)
	if not collection then
		return false, "Your save isn't loaded yet."
	end
	local entry = find(collection, uid)
	if not entry then
		return false, "That piece isn't in your stock."
	end
	if price ~= nil and Rules.saleOf(price) == nil then
		return false, "That's no price."
	end
	if price ~= nil and entry.stand == nil then
		return false, `Put your {entry.name} on show first: a FOR SALE sign stands on its stand.`
	end
	if entry.sale == price then
		return true, nil
	end
	entry.sale = price
	PlayerData.saveSoon(player) -- (the sign survives a rejoin)
	changed(player)
	return true, nil
end

export type Refusal = { code: string, text: string }

local function refusal(code: string, text: string): (nil, Refusal)
	return nil, { code = code, text = text }
end

function Collection.transfer(seller: Player, buyer: Player, uid: string, stand: number, price: number, fee: number): (Entry?, Refusal?)
	-- (every check before anything moves, and nothing in here yields: the deal is one step)
	if seller == buyer then
		return refusal("self", "That's your own piece.")
	end
	if not seller.Parent or not buyer.Parent then
		return refusal("left", "They left the server.")
	end
	local from, to = collectionOf(seller), collectionOf(buyer)
	local buyerProfile = PlayerData.get(buyer)
	if not from or not to or not buyerProfile then
		return refusal("save", "A save isn't loaded yet.")
	end
	if not finite(price) or price ~= math.floor(price) or price < 1 or price >= 2 ^ 40 or not finite(fee) or fee < 0 or fee > price then
		return refusal("gone", "That's no price.")
	end
	local housed = Collection.hasWarehouse
	if housed and not housed(buyer) then
		return refusal("house", "You need a warehouse of your own to buy: wait for a free plot.")
	end
	if housed and not housed(seller) then
		return refusal("gone", "That piece isn't on show any more.")
	end
	local entry, index = find(from, uid)
	if not entry or not index or entry.stand == nil or entry.stand ~= stand then
		return refusal("gone", "That piece isn't on show there any more.")
	end
	if #to.entries >= Config.Collection.MaxStock then
		return refusal("full", `Your warehouse is full ({Config.Collection.MaxStock} pieces): sell some first.`)
	end
	if buyerProfile.money < price then
		return refusal("money", `You have {Market.money(buyerProfile.money)}: not enough for {Market.money(price)}.`)
	end
	-- the moves
	settle(seller) -- (what the seller's stands earned up to now, at the old rates)
	table.remove(from.entries, index)
	local newUid = Rules.uid(buyer.UserId, to.nextUid)
	to.nextUid += 1
	while find(to, newUid) do -- (never from a clean save; a guard all the same)
		newUid = Rules.uid(buyer.UserId, to.nextUid)
		to.nextUid += 1
	end
	local piece: Entry = {
		uid = newUid,
		item = entry.item,
		variant = entry.variant,
		condition = entry.condition,
		name = entry.name,
		stand = nil,
		got = os.time(),
		sale = nil,
	}
	table.insert(to.entries, piece)
	PlayerData.spend(buyer, price, "PlayerBuy", entry.item)
	PlayerData.addMoney(seller, price, "PlayerSale", entry.item)
	if fee > 0 then
		PlayerData.spend(seller, fee, "TradeFee", entry.item)
	end
	for _, fn in transferredTo do -- (8.7 review: before onChanged's look at the stock and before the saves)
		task.spawn(fn, buyer, seller, table.clone(piece))
	end
	changed(seller)
	changed(buyer)
	-- 8.7 review: both saved now, not soon (PlayerData.save: no Gap, no budget Reserve; the session's lock and the saves'
	-- seq as ever), the buyer first: a crash between the two leaves a piece the buyer paid for in both saves, never the
	-- price with nobody's piece. The seller's waits for the buyer's to land; not written (a failed write, the buyer
	-- leaving: their leave save carries it), the seller's own saves carry theirs (the fee's Soon, the autosave).
	task.spawn(function()
		if PlayerData.save(buyer) then
			PlayerData.save(seller)
		end
	end)
	return table.clone(piece), nil
end

-- The admin's CLEAR STOCK (server/Admin.luau "sandbox"): the whole collection gone, on show or not, for nothing (what
-- the pieces on show earned up to now still counts). → how many pieces went (nil: no save yet).
function Collection.clear(player: Player): number?
	local collection = collectionOf(player)
	if not collection then
		return nil
	end
	settle(player)
	local count = #collection.entries
	table.clear(collection.entries)
	changed(player)
	return count
end

function Collection.incomePerMinute(player: Player): number
	local collection = collectionOf(player)
	return if collection then rate(player, collection) else 0
end

function Collection.stands(player: Player): number
	return standsOf(player)
end

function Collection.boost(player: Player): number
	return boostOf(player)
end

function Collection.market(player: Player): Market.View?
	return marketOf(player)
end

function Collection.marketIncome(item: string): number
	return Market.incomeFactor(Market.today(marketDay), item)
end

function Collection.upgrade(player: Player, apply: () -> ()): number
	settle(player) -- (what the stands earned up to now, at the old rates)
	apply()
	local collection = collectionOf(player)
	local moved = if collection then Rules.fitStands(collection, standsOf(player), fitsFor(player)) else 0
	changed(player)
	return moved
end

function Collection.openPicker(player: Player, stand: number)
	if not collectionOf(player) or not isStand(stand, standsOf(player)) then
		return
	end
	sendState(player) -- (the picker lists the stock as it is now)
	remote:FireClient(player, { kind = "pick", stand = stand })
end

-- 8.3 economy, AFK: `player` did something now. Back from idle: what the stands earned while idle is counted at the
-- idle share first, then they pay in full again and the state goes out (the HUD's "· idle" goes).
function Collection.active(player: Player)
	local meter = meters[player]
	if not meter then
		return
	end
	local now = os.clock()
	if now - meter.active >= Config.Collection.IdleAfter then
		settle(player)
	end
	meter.active = now
	if meter.idle then
		pushState(player)
	end
end

function Collection.idle(player: Player): number
	return shareOf(player)
end

function Collection.onChanged(fn: (Player) -> ())
	table.insert(listeners, fn)
end

function Collection.onAdded(fn: (Player, Entry) -> ())
	table.insert(addedListeners, fn)
end

function Collection.onTransferred(fn: (Player, Player, Entry) -> ())
	table.insert(transferredTo, fn)
end

function Collection.onPaid(fn: (Player, string, number, Paid) -> ())
	table.insert(paidTo, fn)
end

function Collection.tick()
	local here: { Player } = {}
	for player in meters do
		table.insert(here, player)
	end
	for _, player in here do
		if player.Parent then
			-- 8.3 economy, AFK: the root moved IdleMove studs since the last move that counted (walking, a van driven)
			local meter = meters[player]
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if meter and root and root:IsA("BasePart") then
				local at = (root :: BasePart).Position
				local from = meter.pos or at
				local dx, dz = at.X - from.X, at.Z - from.Z
				if meter.pos == nil then
					meter.pos = at
				elseif dx * dx + dz * dz >= Config.Collection.IdleMove ^ 2 then -- (over the ground: a jump is none)
					meter.pos = at
					Collection.active(player)
				end
			end
			settle(player)
			payout(player)
			if meter and not meter.idle and shareOf(player) < 1 then
				pushState(player) -- (8.3 economy: idle now: the HUD's "· idle")
			end
		end
	end
	-- 8.3: the market's day turns (after the stands were counted at the old day's rates): every state again; a step of
	-- a player's demand came back: their state again
	local now = os.time()
	local day = Market.dayOf(now)
	local turned = day ~= marketDay
	marketDay = day
	for _, player in here do
		local due = marketDue[player]
		if player.Parent and (turned or (due ~= nil and now >= due)) then
			marketDue[player] = nil
			if turned then
				changed(player)
			else
				pushState(player)
			end
		end
	end
end

-- ── 8.2: the STOCK list's bulk buttons (the remote's fillbest, sellmany, undisplayall) ──────────────────────────

local NOTHING_TO_SELL: { [string]: string } = {
	common = "There's no Common piece in your stock to sell.",
	broken = "There's no broken piece in your stock.",
	duplicates = "No duplicates in your stock: you have one of each.",
}

-- The rarer of two rarities (the analytics' field).
local function rarer(a: string?, b: string): string
	return if a and Rules.tier(a).rank >= Rules.tier(b).rank then a else b
end

-- The collection's pieces as shared/StockPlan.luau reads them (CollectionRules.view: × the player's lights; 8.3: at the
-- market's prices and incomes, with their price without it).
local function piecesOf(player: Player, collection: Rules.Saved, market: Market.View?): { StockPlan.Piece }
	local boost = boostOf(player)
	local out: { StockPlan.Piece } = table.create(#collection.entries)
	for _, entry in collection.entries do
		local v = Rules.view(entry, boost, market)
		table.insert(out, { uid = v.uid, item = v.item, stand = v.stand, got = v.got, rarity = v.rarity, income = v.income, price = v.price, broken = v.broken, condition = v.condition, base = v.base })
	end
	return out
end

-- ⭐ FILL BEST → how many went up (nil: nothing to do), why.
local function fillBest(player: Player): (number?, string?)
	local collection = collectionOf(player)
	if not collection then
		return nil, "Your save isn't loaded yet."
	end
	local housed = Collection.hasWarehouse
	if housed and not housed(player) then
		return nil, NO_WAREHOUSE
	end
	local stands = standsOf(player)
	local level = levelOf(player) -- (8.3: the stands of their warehouse's level)
	local function fits(stand: number, item: string): boolean
		return fitsStand(stand, item, level)
	end
	local market = marketOf(player)
	local pieces = piecesOf(player, collection, market)
	local plan = StockPlan.fill(pieces, stands, fits)
	if #plan == 0 then
		if #StockPlan.free(pieces, stands) == 0 then
			return nil, "Every display stand you have already shows a piece."
		end
		for _, piece in pieces do
			if piece.stand == nil and not piece.broken and piece.income > 0 then
				return nil, "What's in your stock is too big for your free small stands."
			end
		end
		return nil, "Nothing in your stock would earn on a stand. Bring more home from a move!"
	end
	settle(player)
	local byUid: { [string]: Entry } = {}
	local taken: { [number]: boolean } = {}
	for _, entry in collection.entries do
		byUid[entry.uid] = entry
		if entry.stand ~= nil then
			taken[entry.stand] = true
		end
	end
	local boost = boostOf(player)
	local count, gained, rarest = 0, 0, nil :: string?
	for _, place in plan do
		-- (the plan is our own; checked all the same, as Collection.display would)
		local entry = byUid[place.uid]
		if entry and entry.stand == nil and isStand(place.stand, stands) and not taken[place.stand] and fits(place.stand, entry.item) then
			entry.stand = place.stand
			taken[place.stand] = true
			count += 1
			gained += Rules.income(entry, boost, market)
			rarest = rarer(rarest, Rules.rarityOf(Rules.defOf(entry.item)))
		end
	end
	if count == 0 then
		return nil, "Nothing could go on show."
	end
	PlayerData.track("event", player, "CollectionDisplayed", math.floor(gained + 0.5), rarest)
	remote:FireClient(player, { kind = "bulk", action = "fillbest", count = count, income = cents(gained) })
	changed(player)
	return count, nil
end

-- 8.4 review: the uids a SELL… confirm listed (a list of uid strings, each once, Config.Collection.MaxStock at most: a
-- sale never holds more than the stock) → the set and how many (nil: no such list).
local function listed(raw: any): ({ [string]: boolean }?, number)
	if type(raw) ~= "table" then
		return nil, 0
	end
	local set: { [string]: boolean } = {}
	local count = 0
	for key, uid in raw do
		count += 1
		if count > Config.Collection.MaxStock or type(key) ~= "number" or type(uid) ~= "string" or #uid == 0 or #uid > MAX_UID or set[uid] then
			return nil, 0
		end
		set[uid] = true
	end
	if count == 0 or count ~= #raw then
		return nil, 0
	end
	return set, count
end

-- 💰 SELL… → the money paid (nil: nothing sold), how many, why. 8.3: at the market's prices, the pieces one after the
-- other (StockPlan.price: each next piece of a kind under the demand of the ones before it); `expect`, the total the
-- client's confirm showed: another total sells nothing (the state goes out again). 8.4 review: `uids`, the pieces it
-- listed: sold only while the filter takes exactly those, else nothing (the state goes out again).
local function sellMany(player: Player, filter: any, expect: number?, uids: any): (number?, number, string?)
	local collection = collectionOf(player)
	local profile = PlayerData.get(player)
	if not collection or not profile then
		return nil, 0, "Your save isn't loaded yet."
	end
	if not StockPlan.isFilter(filter) then
		return nil, 0, "Choose what to sell: all Common, all broken or the duplicates."
	end
	local market = marketOf(player)
	local list = StockPlan.toSell(piecesOf(player, collection, market), filter)
	if #list == 0 then
		return nil, 0, NOTHING_TO_SELL[filter]
	end
	local asked, many = listed(uids)
	local same = asked ~= nil and many == #list
	for _, piece in list do
		same = same and (asked :: { [string]: boolean })[piece.uid] == true
	end
	if not same then -- (8.4 review: never a piece the confirm did not list, never fewer than it said)
		sendState(player)
		return nil, 0, `Your stock changed since you asked: {StockPlan.filterName(filter)} would sell other pieces now ({#list}). Nothing was sold: look again.`
	end
	local total = StockPlan.price(list, market)
	if expect ~= nil and total < expect then -- (8.3 review: only a total that fell)
		sendState(player) -- (8.3: the prices moved since the client asked: it sees them now)
		return nil, 0, `The market moved: those {#list} {if #list == 1 then "piece sells" else "pieces sell"} for {Market.money(total)} now. Ask again.`
	end
	local chosen: { [string]: boolean } = {}
	for _, piece in list do
		chosen[piece.uid] = true
	end
	local kept: { Entry } = {}
	local kinds: { [string]: number } = {} -- (8.3: how many of each kind went)
	local count, hot, cold, rarest, item, mixed = 0, 0, 0, nil :: string?, nil :: string?, false
	for _, entry in collection.entries do
		if chosen[entry.uid] and entry.stand == nil then
			count += 1
			kinds[entry.item] = (kinds[entry.item] or 0) + 1
			local tag = Market.tag(market, entry.item)
			hot += if tag == "hot" then 1 else 0
			cold += if tag == "cold" then 1 else 0
			rarest = rarer(rarest, Rules.rarityOf(Rules.defOf(entry.item)))
			mixed = mixed or (item ~= nil and item ~= entry.item)
			item = entry.item
		else
			table.insert(kept, entry)
		end
	end
	table.clear(collection.entries)
	table.move(kept, 1, #kept, 1, collection.entries)
	local now = os.time()
	for kind, n in kinds do
		Market.note(profile.market, kind, marketDay, now, n)
	end
	PlayerData.addMoney(player, total, "CollectionSale", if mixed then nil else item)
	for _, fn in paidTo do task.spawn(fn, player, "sale", total, { hot = hot }) end -- 8.2 merge: Collection.onPaid (a bulk sale counts too)
	remote:FireClient(player, { kind = "sold", name = `{count} {if count == 1 then "piece" else "pieces"}`, money = total, count = count })
	PlayerData.track("event", player, "CollectionSold", total, rarest, if hot > 0 then "hot" elseif cold > 0 then "cold" else nil)
	changed(player)
	return total, count, nil
end

-- ↩ TAKE ALL DOWN → how many came down (nil: nothing on show), why.
local function undisplayAll(player: Player): (number?, string?)
	local collection = collectionOf(player)
	if not collection then
		return nil, "Your save isn't loaded yet."
	end
	local shown = 0
	for _, entry in collection.entries do
		if entry.stand ~= nil then
			shown += 1
		end
	end
	if shown == 0 then
		return nil, "Nothing is on show."
	end
	settle(player) -- (what they earned up to now still counts)
	for _, entry in collection.entries do
		entry.stand = nil
		entry.sale = nil -- (8.7: the FOR SALE signs too)
	end
	remote:FireClient(player, { kind = "bulk", action = "undisplayall", count = shown })
	changed(player)
	return shown, nil
end

local BULK: { [string]: boolean } = { fillbest = true, sellmany = true, undisplayall = true }

-- 8.3: the price a client's confirm showed (a whole number of dollars; anything else: none, the sale goes on as before).
local function expected(value: any): number?
	return if finite(value) and value == math.floor(value) and value >= 0 and value < 2 ^ 40 then value else nil
end

-- ── Joining, leaving, the remote ──────────────────────────────────────────

-- The save has loaded (PlayerData.Changed fires then first): the income is counted from now, pieces on stands the
-- warehouse no longer has (8.3: or too big for their stand at its level) go back to the stock, the client gets the
-- state and the listeners (the warehouse) a change.
local function joined(player: Player)
	if meters[player] or not player.Parent then
		return
	end
	local collection = collectionOf(player)
	if not collection then
		return
	end
	meters[player] = { at = os.clock(), carry = 0, hot = 0, active = os.clock(), idle = false, pos = nil }
	Rules.fitStands(collection, standsOf(player), fitsFor(player))
	changed(player)
end

-- Leaving pays what the stands earned up to now (before PlayerData's leave save, which waits for the other handlers).
local function left(player: Player)
	settle(player)
	payout(player)
	meters[player] = nil
	pushing[player] = nil
	added[player] = nil
	refused[player] = nil
	marketDue[player] = nil
end

local function onRemote(player: Player, message: any)
	if not Net.limit(player, "Collection", Config.Robust.Limits.Collection) then
		return
	end
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if type(kind) == "string" and BULK[kind] and not Net.limit(player, "CollectionBulk", Config.Robust.Limits.CollectionBulk) then
		return -- (8.2: a bulk button at most CollectionBulk times a second)
	end
	local ok, why = true, nil :: string?
	if kind == "state" then
		sendState(player)
	elseif kind == "display" then
		ok, why = Collection.display(player, message.uid, message.stand)
	elseif kind == "undisplay" then
		ok, why = Collection.undisplay(player, message.uid)
	elseif kind == "sell" then
		local money: number? = nil
		money, why = Collection.sell(player, message.uid, expected(message.expect))
		ok = money ~= nil
	elseif kind == "fillbest" then
		local count: number? = nil
		count, why = fillBest(player)
		ok = count ~= nil
	elseif kind == "sellmany" then
		local money: number?, sold: number = nil, 0
		money, sold, why = sellMany(player, message.filter, expected(message.expect), message.uids)
		ok = money ~= nil and sold > 0
	elseif kind == "undisplayall" then
		local count: number? = nil
		count, why = undisplayAll(player)
		ok = count ~= nil
	end
	if not ok and why then
		notice:FireClient(player, why)
	end
end

-- 8.3 economy, AFK: a call of one of the remotes counts as activity (not a bare "state" ask: the clients send those by
-- themselves: ("state") or { kind = "state" }).
local function onActivity(player: Player, first: any)
	if first ~= "state" and not (type(first) == "table" and first.kind == "state") then
		Collection.active(player)
	end
end

function Collection.start()
	remote.OnServerEvent:Connect(onRemote)
	for _, name in Config.Collection.IdleRemotes do
		task.spawn(function()
			local ok, other = pcall(Net.get, name)
			if ok and other then
				other.OnServerEvent:Connect(onActivity)
			end
		end)
	end
	PlayerData.Changed:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(left)
	task.spawn(function()
		while true do
			task.wait(Config.Collection.Tick)
			local ok, err = pcall(Collection.tick :: () -> ...any)
			if not ok then
				warn(`[Collection] payout failed: {err}`)
			end
		end
	end)
end

return Collection
