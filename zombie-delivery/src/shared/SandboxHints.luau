--!strict
-- 8.3 SANDBOX, the first-time hints (the 8.2 review: the new features need a word the first time they matter). Pure (no
-- Roblox: tests/sandboxhints_test.luau); client/SandboxHintsUi.luau hears the remotes and shows each as a toast.
--   book   the first piece ever in your collection book: its state had none, the next has some (a book is kept in the
--          save, so this is once for good)  "📖 New in your book! Press C (📖) to see it"
--   tasks  the first task done ("done" of the SandboxTasks remote) while a reward waits  "📋 Claim your reward in TASKS"
--   fill   FillStock pieces or more in the stock that would earn on show and a free stand for them (what ⭐ FILL BEST
--          would do)  "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK"
-- 8.9, the 8.5 – 8.7 features (each the first time it matters; the auction, 8.8, has none while it is off):
--   orders 8.5 your clipboard out for the first time (orders mode: your character's ClipboardHeld, server/Clipboard.luau)
--          "📋 Orders mode: E or click a piece to give it to Danny. Click Danny for his orders. (Q) puts it
--          away." (9.0: E too; a gamepad's "R1 by a piece …", "L1 at Danny …", "(B)"; a phone's taps and "Tap 📋 to put
--          it away")
--   visit  8.7 you walk into another player's warehouse with a piece of theirs on show (its stand's trade prompts on,
--          tagged Config.PlayerTrade.PromptTag with their owner's UserId: server/Warehouse.luau's)
--          "🤝 Like a piece here? Make the owner an offer."
--   price  8.7 PriceShown pieces or more of yours on show and none with a FOR SALE sign yet (the "Collection" state's
--          views' `sale`)  "🏷 Put a price on a piece and other players can buy it, even while you're away."
--   deal   8.7 another player's offer for your piece (the "PlayerTrade" remote's { kind = "offer", player = true }: it
--          waits while its offer card is open)  "Players pay more than the game: a piece they lack is worth more to them."
--   (visit, price and deal only while trading is on: SandboxHints.tradeOn)
-- The words name this device's way (shared/SandboxPad.luau: a key on a computer, the D-pad with a gamepad, the chip on a
-- touch screen). Each once a session (the seen flags live in the client, as the guide's done steps do: a new session
-- may say "tasks" and "fill" again, "book" never), never two at once (Config.SandboxHud.Hints.Gap s apart, Delay s after
-- what made it matter), and never while something covers the screen (a grip check, the move's cards with its result, a
-- sandbox window, the start screen): it waits for it.
--   SandboxHints.Ids                              "book", "tasks", "fill"; 8.9: "orders", "visit", "price", "deal"
--   SandboxHints.new() -> Queue                   nothing seen, nothing waiting
--   SandboxHints.offer(q, id, now) -> boolean     wait to show `id` from now + Delay (false: seen, waiting already or
--                                                 no hint of ours)
--   SandboxHints.take(q, now, covered, still?) -> string?   the hint to show now (marked seen: it never comes again),
--                                                 nil: none due, the screen covered or the last one too recent; still(id)
--                                                 false: no longer true (dropped, not shown, not seen)
--   SandboxHints.seen(q, id) / waiting(q, id)     marked seen; waiting to show
--   SandboxHints.busy(q, now) -> boolean          a hint waits, or one showed less than Gap s ago: the guide's soft
--                                                 steps keep quiet meanwhile (shared/SandboxSteps.luau, its `hush`)
--   SandboxHints.found(q, id)                     the player found it alone while its hint waited (opened the book, the
--                                                 TASKS panel): not shown, seen
--   SandboxHints.text(id, device) -> string       its words for the device
--   SandboxHints.firstPiece(before, now, new) -> boolean   the book's count before (nil: no state yet), now, the new
--                                                 pieces in this state: the first piece ever?
--   SandboxHints.fillWorth(stock, stands) -> boolean   the "Collection" state's stock (its views) and stands: the hint
--                                                 for ⭐ FILL BEST worth saying?
--   SandboxHints.tradeOn() -> boolean             8.9: trading between players is on (Config.PlayerTrade.On)
--   SandboxHints.priceWorth(stock) -> boolean     8.9: the "Collection" state's stock: PriceShown pieces or more on show,
--                                                 none with a FOR SALE sign (the hint for a sign worth saying?)
--   SandboxHints.hallAt(x, z, levelOf?) -> (number?, Rect?)   8.9: the plot whose warehouse floor holds (x, z) (the
--                                                 building of its level, levelOf(id): workspace.Warehouses' Level<id>;
--                                                 nil, or no levelOf: 4) and that floor; nil: none
--   SandboxHints.visiting(x, z, me, spots, levelOf?) -> boolean   8.9: do you stand at (x, z) in a warehouse where a
--                                                 piece of another player is on show? spots: the trade prompts on (their
--                                                 stands' { x, z, seller }); me: your UserId (yours never count)
--   SandboxHints.playerOffer(message) -> boolean  8.9: a "PlayerTrade" remote's message: another player's offer for your
--                                                 piece?

local Config = require(script.Parent.Config)
local SandboxPad = require(script.Parent.SandboxPad)
local StockPlan = require(script.Parent.StockPlan)
local SandboxMap = require(script.Parent.SandboxMap) -- 8.9: the plots (a visit)
local WarehouseLayout = require(script.Parent.WarehouseLayout) -- 8.9: a warehouse's floor at its level (a visit)

local SandboxHints = {}

export type Waiting = { id: string, at: number }
export type Queue = { waiting: { Waiting }, seen: { [string]: boolean }, lastAt: number }
export type Rect = { x0: number, x1: number, z0: number, z1: number }
-- 8.9: a trade prompt on (a piece on show on its stand): where the stand is and its owner's UserId.
export type Spot = { x: number, z: number, seller: number }

SandboxHints.Ids = { "book", "tasks", "fill", "orders", "visit", "price", "deal" }

local function tune()
	return Config.SandboxHud.Hints
end

function SandboxHints.new(): Queue
	return { waiting = {}, seen = {}, lastAt = -math.huge }
end

function SandboxHints.seen(q: Queue, id: string): boolean
	return q.seen[id] == true
end

function SandboxHints.waiting(q: Queue, id: string): boolean
	for _, entry in q.waiting do
		if entry.id == id then
			return true
		end
	end
	return false
end

function SandboxHints.busy(q: Queue, now: number): boolean
	return #q.waiting > 0 or now - q.lastAt < tune().Gap
end

function SandboxHints.found(q: Queue, id: string)
	for index, entry in q.waiting do
		if entry.id == id then
			table.remove(q.waiting, index)
			q.seen[id] = true
			return
		end
	end
end

function SandboxHints.offer(q: Queue, id: string, now: number): boolean
	if not table.find(SandboxHints.Ids, id) or q.seen[id] or SandboxHints.waiting(q, id) then
		return false
	end
	table.insert(q.waiting, { id = id, at = now + tune().Delay })
	return true
end

function SandboxHints.take(q: Queue, now: number, covered: boolean, still: ((string) -> boolean)?): string?
	if covered or now - q.lastAt < tune().Gap then
		return nil
	end
	local index = 1
	while index <= #q.waiting do
		local entry = q.waiting[index]
		if still and not still(entry.id) then
			table.remove(q.waiting, index) -- (no longer true: not said, so a later time may say it)
		elseif entry.at <= now then
			table.remove(q.waiting, index)
			q.seen[entry.id] = true
			q.lastAt = now
			return entry.id
		else
			index += 1
		end
	end
	return nil
end

function SandboxHints.text(id: string, device: SandboxPad.Device): string
	if id == "book" then
		return if device == "touch"
			then `📖 New in your book! {SandboxPad.how("book", device)} to see it`
			else `📖 New in your book! {SandboxPad.how("book", device)} (📖) to see it`
	elseif id == "tasks" then
		return `📋 Claim your reward in {SandboxPad.named("tasks", device)}`
	elseif id == "fill" then
		return `⭐ FILL BEST puts your best pieces on show: open {SandboxPad.named("stock", device, true)}`
	elseif id == "orders" then
		-- (8.9: a click, a tap or R1 by a piece; a click or a tap on Danny, a gamepad's L1 at him: client/MoveHelperCard.luau)
		local name = Config.MoveHelper.Name
		local away = SandboxPad.keyWord("stow", device)
		if device == "touch" then
			return `📋 Orders mode: tap a piece to give it to {name}. Tap {name} for his orders. {SandboxPad.howTo("stow", device)} to put it away.`
		elseif device == "pad" then
			return `📋 Orders mode: {SandboxPad.keyWord("dannygive", device)} by a piece gives it to {name}. {SandboxPad.keyWord("danny", device)} at {name} for his orders. ({away}) puts it away.`
		end
		-- (9.0: E by a piece too, client/DannyOrders.luau's prompts in place of its Pick up)
		return `📋 Orders mode: {Config.MoveHelper.Clipboard.GiveKey} or click a piece to give it to {name}. Click {name} for his orders. ({away}) puts it away.`
	elseif id == "visit" then
		return "🤝 Like a piece here? Make the owner an offer."
	elseif id == "price" then
		return "🏷 Put a price on a piece and other players can buy it, even while you're away."
	elseif id == "deal" then
		return "Players pay more than the game: a piece they lack is worth more to them."
	end
	return ""
end

function SandboxHints.firstPiece(before: number?, now: number, new: number): boolean
	return before == 0 and now > 0 and new > 0
end

-- A number that is a number (the remote's views come over the network).
local function number(value: any): number
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end

function SandboxHints.fillWorth(stock: any, stands: any): boolean
	if type(stock) ~= "table" then
		return false
	end
	local pieces: { StockPlan.Piece } = {}
	local waiting = 0
	for _, entry in stock do
		if type(entry) == "table" and (type(entry.uid) == "string" or type(entry.uid) == "number") and type(entry.item) == "string" then
			local stand = if type(entry.stand) == "number" then entry.stand else nil
			local piece: StockPlan.Piece = {
				uid = entry.uid,
				item = entry.item,
				stand = stand,
				rarity = if type(entry.rarity) == "string" then entry.rarity else "common",
				income = number(entry.income),
				price = number(entry.price),
				broken = entry.broken == true,
			}
			table.insert(pieces, piece)
			if stand == nil and piece.broken ~= true and piece.income > 0 then
				waiting += 1
			end
		end
	end
	if waiting < tune().FillStock then
		return false
	end
	return #StockPlan.fill(pieces, math.floor(number(stands)), function(_stand: number, _item: string): boolean
		return true -- (which stand takes which piece is the server's: here only that a free stand is there)
	end) > 0
end

-- ── 8.9: the 8.5 – 8.7 features ─────────────────────────────────────────────

function SandboxHints.tradeOn(): boolean
	local trade = (Config :: any).PlayerTrade
	return type(trade) == "table" and trade.On == true
end

function SandboxHints.priceWorth(stock: any): boolean
	if type(stock) ~= "table" then
		return false
	end
	local shown = 0
	for _, entry in stock do
		if type(entry) == "table" and type(entry.stand) == "number" then
			if number(entry.sale) > 0 then
				return false -- (a sign there already: the player knows it)
			end
			shown += 1
		end
	end
	return shown >= tune().PriceShown
end

function SandboxHints.hallAt(x: number, z: number, levelOf: ((number) -> number?)?): (number?, Rect?)
	local plot = SandboxMap.plotAt(x, z)
	local site = if plot then WarehouseLayout.site(plot, if levelOf then levelOf(plot.id) else nil) else nil
	if not plot or not site then
		return nil, nil
	end
	local floor = WarehouseLayout.inside(site)
	if x < floor.x0 or x > floor.x1 or z < floor.z0 or z > floor.z1 then
		return nil, nil
	end
	return plot.id, { x0 = floor.x0, x1 = floor.x1, z0 = floor.z0, z1 = floor.z1 }
end

function SandboxHints.visiting(x: number, z: number, me: number, spots: { Spot }, levelOf: ((number) -> number?)?): boolean
	local _, floor = SandboxHints.hallAt(x, z, levelOf)
	if not floor then
		return false
	end
	for _, spot in spots do
		if spot.seller ~= me and spot.x >= floor.x0 and spot.x <= floor.x1 and spot.z >= floor.z0 and spot.z <= floor.z1 then
			return true
		end
	end
	return false
end

function SandboxHints.playerOffer(message: any): boolean
	return type(message) == "table" and message.kind == "offer" and message.player == true and type(message.id) == "string"
end

return SandboxHints
