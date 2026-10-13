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
--                                              piece on show elsewhere moves there) → ok, why
--   Collection.undisplay(player, uid)          take it down (back to the stock) → ok, why
--   Collection.sell(player, uid)               sell it (on show or not) → the money paid (nil: refused), why
--   Collection.incomePerMinute(player)         what your pieces on show earn a minute now
--   Collection.openPicker(player, stand)       (Warehouse: an empty display stand's prompt) ask the player's client to
--                                              pick a piece for it (the "Collection" remote's { kind = "pick", stand })
--   Collection.clear(player)                   (the admin's CLEAR STOCK) the whole collection gone for nothing → how many
--   Collection.onChanged(fn)                   fn(player) after any change to a player's collection (and when their
--                                              save has loaded)
--   Collection.tick()                          pays everybody here what their stands earned since the last payout (the
--                                              loop runs it every Config.Collection.Tick s)
--   Collection.start()                         the remote, joining and leaving, the payout loop
--
-- The "Collection" remote (Config.Robust.Limits.Collection requests a second; every input checked):
--   client → server   { kind = "display", uid, stand } | { kind = "undisplay", uid } | { kind = "sell", uid } |
--                     { kind = "state" }; a refusal comes back as a Notice (its why)
--   server → client   { kind = "state", stock = { View }, income, stands } after every change (once a frame), when the
--                     save has loaded and when asked (a View is an Entry with rarity, value, income, price, broken:
--                     CollectionRules.view); { kind = "pick", stand } opens the picker; { kind = "sold", name, money }
-- The income is exact: whenever the pieces on show change (one put up, taken down, sold) and at every payout, what they
-- earned up to that moment is counted; every Tick s the whole dollars are paid ("CollectionIncome"), the cents wait for
-- the next payout; leaving pays what was counted. A sale pays "CollectionSale". Analytics (PlayerData.track):
-- CollectionAdded (once a frame: how many came home, the rarest), CollectionDisplayed, CollectionSold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.CollectionRules)
local PlayerData = require(script.Parent.PlayerData)

local Collection = {}

export type Entry = Rules.Entry

local MAX_UID = 64 -- a longer uid from a client is no piece of ours
local MAX_NAME = 60

local remote = Net.get("Collection")
local notice = Net.get("Notice")

local listeners: { (Player) -> () } = {}

-- The income counted for each player here: up to `at` (os.clock), `carry` $ not paid yet.
type Meter = { at: number, carry: number }
local meters: { [Player]: Meter } = {}
local pushing: { [Player]: boolean } = {} -- a state push waits for the frame's end
type Batch = { n: number, rarity: string }
local added: { [Player]: Batch } = {} -- pieces that came home this frame (one analytics event)
local refused: { [Player]: number } = {} -- pieces refused this frame (stock full: one notice)

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

-- What the pieces on show earn a minute (only on the stands the warehouse has).
local function rate(player: Player, collection: Rules.Saved): number
	local stands = standsOf(player)
	local total = 0
	for _, entry in collection.entries do
		local stand = entry.stand
		if stand ~= nil and stand >= 1 and stand <= stands then
			total += Rules.income(entry)
		end
	end
	return total
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
	meter.carry += rate(player, collection) * seconds / 60
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
		PlayerData.addMoney(player, pay, "CollectionIncome")
	end
end

local function sendState(player: Player)
	pushing[player] = nil
	local collection = collectionOf(player)
	if not collection or not player.Parent then
		return
	end
	local stock = table.create(#collection.entries)
	for _, entry in collection.entries do
		table.insert(stock, Rules.view(entry))
	end
	remote:FireClient(player, { kind = "state", stock = stock, income = cents(rate(player, collection)), stands = standsOf(player) })
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
	noteAdded(player, Rules.rarityOf(def))
	changed(player)
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
	if not isStand(stand, standsOf(player)) then
		return false, "There's no such display stand."
	end
	if entry.stand == stand then
		return true, nil
	end
	for _, other in collection.entries do
		if other.stand == stand then
			return false, `That stand already shows your {other.name}.`
		end
	end
	settle(player)
	entry.stand = stand
	PlayerData.track("event", player, "CollectionDisplayed", math.floor(Rules.income(entry) + 0.5), Rules.rarityOf(Rules.defOf(entry.item)))
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
	changed(player)
	return true, nil
end

function Collection.sell(player: Player, uid: string): (number?, string?)
	local collection = collectionOf(player)
	if not collection then
		return nil, "Your save isn't loaded yet."
	end
	local entry, index = find(collection, uid)
	if not entry or not index then
		return nil, "That piece isn't in your stock."
	end
	settle(player) -- (on show: what it earned up to now still counts)
	local price = Rules.sell(entry)
	table.remove(collection.entries, index)
	PlayerData.addMoney(player, price, "CollectionSale", entry.item)
	remote:FireClient(player, { kind = "sold", name = entry.name, money = price })
	PlayerData.track("event", player, "CollectionSold", price, Rules.rarityOf(Rules.defOf(entry.item)))
	changed(player)
	return price, nil
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

function Collection.openPicker(player: Player, stand: number)
	if not collectionOf(player) or not isStand(stand, standsOf(player)) then
		return
	end
	sendState(player) -- (the picker lists the stock as it is now)
	remote:FireClient(player, { kind = "pick", stand = stand })
end

function Collection.onChanged(fn: (Player) -> ())
	table.insert(listeners, fn)
end

function Collection.tick()
	local here: { Player } = {}
	for player in meters do
		table.insert(here, player)
	end
	for _, player in here do
		if player.Parent then
			settle(player)
			payout(player)
		end
	end
end

-- ── Joining, leaving, the remote ──────────────────────────────────────────

-- The save has loaded (PlayerData.Changed fires then first): the income is counted from now, pieces on stands the
-- warehouse no longer has go back to the stock, the client gets the state and the listeners (the warehouse) a change.
local function joined(player: Player)
	if meters[player] or not player.Parent then
		return
	end
	local collection = collectionOf(player)
	if not collection then
		return
	end
	meters[player] = { at = os.clock(), carry = 0 }
	Rules.fitStands(collection, standsOf(player))
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
end

local function onRemote(player: Player, message: any)
	if not Net.limit(player, "Collection", Config.Robust.Limits.Collection) then
		return
	end
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	local ok, why = true, nil :: string?
	if kind == "state" then
		sendState(player)
	elseif kind == "display" then
		ok, why = Collection.display(player, message.uid, message.stand)
	elseif kind == "undisplay" then
		ok, why = Collection.undisplay(player, message.uid)
	elseif kind == "sell" then
		local money: number? = nil
		money, why = Collection.sell(player, message.uid)
		ok = money ~= nil
	end
	if not ok and why then
		notice:FireClient(player, why)
	end
end

function Collection.start()
	remote.OnServerEvent:Connect(onRemote)
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
