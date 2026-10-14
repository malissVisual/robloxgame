--!strict
-- 8.3 SANDBOX, the first-time hints (the 8.2 review: the new features need a word the first time they matter). Pure (no
-- Roblox: tests/sandboxhints_test.luau); client/SandboxHintsUi.luau hears the remotes and shows each as a toast.
--   book   the first piece ever in your collection book: its state had none, the next has some (a book is kept in the
--          save, so this is once for good)  "📖 New in your book! Press C (📖) to see it"
--   tasks  the first task done ("done" of the SandboxTasks remote) while a reward waits  "📋 Claim your reward in TASKS"
--   fill   FillStock pieces or more in the stock that would earn on show and a free stand for them (what ⭐ FILL BEST
--          would do)  "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK"
-- The words name this device's way (shared/SandboxPad.luau: a key on a computer, the D-pad with a gamepad, the chip on a
-- touch screen). Each once a session (the seen flags live in the client, as the guide's done steps do: a new session
-- may say "tasks" and "fill" again, "book" never), never two at once (Config.SandboxHud.Hints.Gap s apart, Delay s after
-- what made it matter), and never while something covers the screen (a grip check, the move's cards with its result, a
-- sandbox window, the start screen): it waits for it.
--   SandboxHints.Ids                              "book", "tasks", "fill"
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

local Config = require(script.Parent.Config)
local SandboxPad = require(script.Parent.SandboxPad)
local StockPlan = require(script.Parent.StockPlan)

local SandboxHints = {}

export type Waiting = { id: string, at: number }
export type Queue = { waiting: { Waiting }, seen: { [string]: boolean }, lastAt: number }

SandboxHints.Ids = { "book", "tasks", "fill" }

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

return SandboxHints
