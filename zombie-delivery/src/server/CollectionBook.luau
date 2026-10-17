--!strict
-- 8.2 SANDBOX: the collection book on the server (Config.CollectionBook; the rules shared/CollectionBookRules.luau, the
-- book's window client/CollectionBookUi.luau). Every piece a move brings home (Collection.onAdded: Collection.add took
-- it) is written into the player's book (profile.collectionBook: { [item] = { n, best } }, kept in the save by
-- server/PlayerData.luau): a piece new in the book is a discovery. The book's milestones (Config.CollectionBook.Milestones:
-- found 10, found 20, all the furniture, every collectible, a legendary) pay their reward once each
-- (profile.collectionBookPaid; PlayerData.addMoney "BookMilestone"), with a toast on the player's screen. The server
-- decides all of it; the client only asks for the state.
-- 8.7 review: a piece bought from another player (Collection.onTransferred: server/PlayerTrade.luau's deal) is written
-- in as bought (CollectionBookRules.record's `bought`): the book shows it, tagged, but it is not found, so no milestone,
-- no badge and no "New in your book" comes of it; the first one a move brings home makes it found.
--
--   CollectionBook.record(player, item, condition, bought?, rarity?)   one more `item` came home (8.7 review: `bought`:
--                                                    bought from a player; 9.x loot: `rarity` the piece's, the page keeps
--                                                    the rarest) → true when it is new in the book (the state goes
--                                                    out at the frame's end, then the milestones it reached pay); a
--                                                    piece not in the book, a bought one or a player not loaded: false
--   CollectionBook.book(player)                      a copy of the player's book (CollectionBookRules.view; nil: not
--                                                    loaded); CollectionBook.paid(player) the paid milestones' ids
--   CollectionBook.settle(player)                    pays every milestone reached and not paid yet (→ how many)
--   CollectionBook.admin(player, what)               the admin panel's SANDBOX tab (server/Admin.luau): "fill" every
--                                                    piece found (the milestones it reaches pay, as a player's would),
--                                                    "clear" the book and its milestones empty (they can pay again)
--                                                    → what to say
--   CollectionBook.start()                           the remote, the hooks on Collection.add and (8.7 review)
--                                                    Collection.transfer, joining and leaving
--
-- The "CollectionBook" remote (Config.Robust.Limits.CollectionBook requests a second; anything but a table with kind
-- "state" is ignored):
--   client → server   { kind = "state" }
--   server → client   { kind = "state", book = { [item] = { n, best } }, paid = { milestone ids }, new = { items } }
--                     when the save has loaded (then the milestones it reached pay: an older save's book, filled from
--                     its stock), when asked, and once a frame after the book changed (`new`: the pieces new in the book
--                     since the last state, in the order they came: the client's "New in your book" toast);
--                     { kind = "milestone", id, name, money } a milestone paid (after that frame's state)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.CollectionBookRules)
local CollectionRules = require(Shared.CollectionRules) -- 9.x loot: a piece's own rarity (pieceRarity)
local PlayerData = require(script.Parent.PlayerData)
local Collection = require(script.Parent.Collection)

local CollectionBook = {}

local remote = Net.get("CollectionBook")

local joined: { [Player]: boolean } = {}
local pending: { [Player]: { string } } = {} -- a state push waiting for the frame's end: the pieces new since the last

local function bookOf(player: Player): (Rules.Book?, Rules.Paid?)
	local profile = PlayerData.get(player)
	if not profile then
		return nil, nil
	end
	return profile.collectionBook, profile.collectionBookPaid
end

local function sendState(player: Player, new: { string })
	local book, paid = bookOf(player)
	if not book or not paid or not player.Parent then
		return
	end
	remote:FireClient(player, { kind = "state", book = Rules.view(book), paid = Rules.paidList(paid), new = new })
end

function CollectionBook.settle(player: Player): number
	local book, paid = bookOf(player)
	if not book or not paid then
		return 0
	end
	local due = Rules.due(book, paid)
	for _, milestone in due do
		Rules.pay(paid, milestone.id) -- (before the money: a milestone pays once, whatever happens next; 8.4 review: + the retired one it replaced)
		PlayerData.addMoney(player, milestone.reward, "BookMilestone", milestone.id)
		PlayerData.saveSoon(player) -- (8.3 saves: a milestone paid is saved a moment later)
		if player.Parent then
			remote:FireClient(player, { kind = "milestone", id = milestone.id, name = milestone.name, money = milestone.reward })
		end
	end
	return #due
end

-- The state goes out once at the frame's end, however many pieces came home (a van unloaded: one push), then the
-- milestones those pieces reached pay.
local function push(player: Player, item: string?)
	local list = pending[player]
	if not list then
		local fresh: { string } = {}
		list = fresh
		pending[player] = fresh
		task.defer(function()
			if pending[player] ~= fresh then
				return
			end
			pending[player] = nil
			sendState(player, fresh)
			CollectionBook.settle(player)
		end)
	end
	if item and not table.find(list :: { string }, item) then
		table.insert(list :: { string }, item)
	end
end

function CollectionBook.record(player: Player, item: any, condition: any, bought: boolean?, rarity: any?): boolean
	local book = bookOf(player)
	if not book or not Rules.inBook(item) then
		return false
	end
	local new = Rules.record(book, item, condition, bought == true, rarity)
	push(player, if new then item else nil)
	return new
end

function CollectionBook.book(player: Player): Rules.Book?
	local book = bookOf(player)
	return if book then Rules.view(book) else nil
end

function CollectionBook.paid(player: Player): { string }
	local _, paid = bookOf(player)
	return if paid then Rules.paidList(paid) else {}
end

function CollectionBook.admin(player: Player, what: string): string
	local book, paid = bookOf(player)
	if not book or not paid then
		return "Still loading..."
	end
	if what == "fill" then
		local added = Rules.fill(book)
		for _, item in added do
			push(player, item)
		end
		if #added == 0 then
			push(player, nil)
		end
		return `ADMIN: the collection book is full ({#added} new, {#Rules.Pieces} pieces; the milestones it reached pay).`
	elseif what == "clear" then
		table.clear(book)
		table.clear(paid)
		local profile = PlayerData.get(player)
		if profile then
			for key in profile.rewards do -- (8.2 review: and their copies in `rewards`, or the next join would read them back)
				if string.sub(key, 1, 5) == "book:" then
					profile.rewards[key] = nil
				end
			end
		end
		push(player, nil)
		return "ADMIN: the collection book is empty (its milestones can pay again)."
	end
	return `ADMIN: no book command "{what}".`
end

-- ── Joining, leaving, the remote ──────────────────────────────────────────

-- The save has loaded (PlayerData.Changed fires then first): the state goes out, then the milestones its book reached
-- and never paid (an older save's, filled from its stock) pay.
local function onJoined(player: Player)
	if joined[player] or not player.Parent or not bookOf(player) then
		return
	end
	joined[player] = true
	push(player, nil)
end

local function onLeft(player: Player)
	joined[player] = nil
	pending[player] = nil
end

local function onRemote(player: Player, message: any)
	if not Net.limit(player, "CollectionBook", Config.Robust.Limits.CollectionBook) then
		return
	end
	if type(message) == "table" and message.kind == "state" then
		sendState(player, {})
	end
end

-- 9.x loot: a piece's own rarity (its house's roll, else its item's), nil for junk.
local function rarityOf(entry: any): string?
	return if type(entry) == "table" and type(entry.item) == "string" then CollectionRules.pieceRarity(entry) else nil
end

function CollectionBook.start()
	remote.OnServerEvent:Connect(onRemote)
	Collection.onAdded(function(player: Player, entry: any)
		CollectionBook.record(player, entry.item, entry.condition, nil, rarityOf(entry)) -- (9.x loot: its rarity)
	end)
	Collection.onTransferred(function(buyer: Player, _seller: Player, entry: any) -- (8.7 review: bought, never found)
		CollectionBook.record(buyer, entry.item, entry.condition, true, rarityOf(entry))
	end)
	PlayerData.Changed:Connect(onJoined)
	for _, player in Players:GetPlayers() do
		onJoined(player)
	end
	Players.PlayerRemoving:Connect(onLeft)
end

return CollectionBook
