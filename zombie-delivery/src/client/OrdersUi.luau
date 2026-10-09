--!strict
-- 5.2: the orders of your run in the phone's ORDERS app (client/Phone.luau draws the focused order as its hero card,
-- then this): one compact card per other order (server/Jobs.luau's payload `orders`): the title row (🚶 / 🚲 or the
-- stars, the title, the pay), the customer, its stops (✓ done, ▶ the one the GPS shows, ● open, ○ waiting: a drop opens
-- once its order's pieces are picked up), its own clock (ticked while the phone is open: OrdersUi.tick) with the pieces
-- delivered, what of it you carry (the payload's `carried`), and a small PIN / UNPIN pill at the top right (the
-- PinOrder remote: the GPS follows the pinned order; the stop whose circle you are at always comes first). The orders
-- done or lost so far are one muted "Earlier on this run" card.
-- 5.4: drawn with the phone's kit (cards, section labels, chips, the stepper: Phone's `look`), so every app matches.
-- Presentation only: the server decides the stops, the clocks and the pay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local K = Theme.Contract
local OrdersUi = {}

-- The Phone's own list pieces, handed in (one look for every app). 5.4: the type and spacing scale's helpers too.
export type Kit = {
	-- a card (8 px corners, the row surface, a faint line; `selected`: the red accent on its left); returns its body
	block: (parent: Instance, order: number, selected: boolean?) -> any,
	caps: (parent: Instance, value: string, order: number, color: Color3?) -> any,
	text: (parent: Instance, value: string, size: UDim2, props: { [string]: any }?) -> any,
	button: (parent: Instance, label: string, kind: any, order: number, onClick: () -> ()) -> any,
	-- the caps label (11, secondary) over a group of cards
	section: (list: Instance, label: string, order: number) -> any,
	-- meta text (12, secondary), wrapped
	meta: (parent: Instance, value: string, order: number, color: Color3?) -> any,
	-- a small rounded pill (caps 11); chipRow: a wrapping row for them
	chip: (parent: Instance, text: string, color: Color3?) -> any,
	chipRow: (parent: Instance, order: number) -> any,
	-- a line of two: the left text (body 14, truncated) and the right one (meta 12; `strong`: HeadingFont 14, light);
	-- returns the row, the left label and the right label
	row2: (parent: Instance, leftText: string, rightText: string, order: number, strong: boolean?) -> (any, any, any),
	-- the centred empty state: a glyph in a circle, the title, a line under it
	emptyState: (list: Instance, glyph: string, title: string, sub: string?, order: number) -> any,
	-- the stops as vertical rows of a status dot: ✓ done (muted), ▶ the current one (red), ● open, ○ waiting
	stepper: (parent: Instance, stops: { any }, order: number) -> any,
	-- a small pill action at the right of its parent (a 36 px touch target around a 24 px face); `accent`: red outline
	pill: (parent: Instance, text: string, onClick: () -> (), accent: boolean?) -> any,
	-- how wide a line of text is (unscaled pixels)
	width: (value: string, size: number, font: Enum.Font) -> number,
}

type Timer = { label: any, endsAt: number, prefix: string? }

local timers: { Timer } = {}

local function pin(id: number?)
	Net.get("PinOrder"):FireServer(id)
end

-- "2 pizza boxes (hands), 1 parcel (pack)" by order id.
local function carriedBy(job: any): { [number]: { string } }
	local out: { [number]: { string } } = {}
	if type(job.carried) ~= "table" then
		return out
	end
	for _, piece in job.carried do
		if type(piece) == "table" and type(piece.order) == "number" then
			local list = out[piece.order] or {}
			out[piece.order] = list
			table.insert(list, `{piece.name or "piece"} ({piece.where or "?"}){if type(piece.dest) == "string" then ` for {piece.dest}` else ""}`)
		end
	end
	return out
end

-- 🚶 on foot, 🚲 by bike, else the job's stars.
function OrdersUi.modeIcon(entry: any): string
	if entry.mode == "foot" then
		return "🚶"
	elseif entry.mode == "bike" then
		return "🚲"
	end
	return string.rep("★", math.max(1, tonumber(entry.stars) or 1))
end

-- PIN / UNPIN as a small pill at the right of `parent` (the focused order's hero card uses it too).
function OrdersUi.pinPill(parent: Instance, entry: any, kit: Kit): any
	local pinned = entry.pinned == true
	local id = tonumber(entry.id)
	return kit.pill(parent, if pinned then "Unpin" else "📌 Pin", function()
		pin(if pinned then nil else id)
	end, pinned)
end

-- The focused order's entry in the payload's `orders` (nil without one).
function OrdersUi.focused(job: any): any
	if type(job) ~= "table" or type(job.orders) ~= "table" then
		return nil
	end
	local byId: any = nil
	for _, entry in job.orders do
		if type(entry) == "table" then
			if entry.focused == true then
				return entry
			elseif job.focus ~= nil and entry.id == job.focus then
				byId = entry
			end
		end
	end
	return byId
end

-- Draws the run's other orders into the phone's list from layout order `order` on; returns the next free layout
-- order. Nothing (the same order back) for a job of one order.
function OrdersUi.render(list: Instance, job: any, kit: Kit, order: number): number
	table.clear(timers)
	local orders = if type(job) == "table" and type(job.orders) == "table" then job.orders else nil
	if not orders or #orders <= 1 then
		return order
	end
	local focused = OrdersUi.focused(job)
	local others: { any }, closed: { any } = {}, {}
	for _, entry in orders do
		if type(entry) == "table" then
			if entry.state ~= "open" then
				table.insert(closed, entry)
			elseif entry ~= focused then
				table.insert(others, entry)
			end
		end
	end
	local carried = carriedBy(job)
	local n = order
	if #others > 0 then
		kit.section(list, `Other orders · {#others}`, n)
		n += 1
		kit.meta(list, "Pick-ups in any order; a drop once its pieces are with you. PIN one and the GPS follows it.", n)
		n += 1
	end
	for _, entry in others do
		local b = kit.block(list, n)
		n += 1
		local pinned = entry.pinned == true
		-- The order's number (red while pinned) and PIN / UNPIN at the top right.
		local head = Ui.make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
		local tag = kit.caps(head, `Order {entry.id}{if pinned then " · 📌 pinned" else ""}`, 0, if pinned then K.red else nil)
		tag.Size = UDim2.new(1, -96, 1, 0)
		tag.TextSize = 11
		OrdersUi.pinPill(head, entry, kit)
		-- The title row: the mode, the title, the pay.
		local _, title = kit.row2(b, `{OrdersUi.modeIcon(entry)}  {tostring(entry.title or entry.cargo or "Order")}`, Ui.money(tonumber(entry.pay) or 0), 2, true)
		title.Font = Theme.HeadingFont
		title.TextSize = 15
		if type(entry.customer) == "string" then
			kit.meta(b, `For {entry.customer}`, 3)
		end
		if type(entry.stops) == "table" and #entry.stops > 0 then
			kit.stepper(b, entry.stops, 4)
		end
		-- The clock (ticked) and the pieces delivered.
		local _, clock = kit.row2(b, "", `{tonumber(entry.delivered) or 0} / {tonumber(entry.pieces) or 0} delivered`, 5)
		clock.Font = Theme.HeadingFont
		clock.TextSize = 16
		if type(entry.endsAt) == "number" then
			table.insert(timers, { label = clock, endsAt = entry.endsAt })
		end
		local mine = carried[tonumber(entry.id) or -1]
		if mine and #mine > 0 then
			kit.meta(b, `With you: {table.concat(mine, ", ")}`, 6)
		end
	end
	if #closed > 0 then
		local b = kit.block(list, n)
		n += 1
		local card = b.Parent
		if card and card:IsA("GuiObject") then
			card.BackgroundTransparency = 0.55 -- (muted: these are behind you)
		end
		kit.caps(b, "Earlier on this run", 1)
		for index, entry in closed do
			local got = tonumber(entry.rating)
			local how = if entry.state == "done" then `✓ +{Ui.money(tonumber(entry.paid) or 0)}{if got then ` {string.rep("★", got)}` else ""}` else "✗ lost"
			kit.meta(b, `{how} · {entry.cargo or "Order"} for {entry.customer or "?"}`, 1 + index)
		end
	end
	OrdersUi.tick()
	return n
end

-- 6.12.8: a label that shows an order's clock (YOUR RUN on the phone's BOARD): ticked with the others, `prefix` before
-- it ("$120 · ").
function OrdersUi.track(label: any, endsAt: number, prefix: string?)
	table.insert(timers, { label = label, endsAt = endsAt, prefix = prefix })
	local left = endsAt - workspace:GetServerTimeNow()
	label.Text = (prefix or "") .. Ui.clock(math.max(0, left))
end

-- The orders' clocks (the phone's open loop, twice a second).
function OrdersUi.tick()
	local now = workspace:GetServerTimeNow()
	for _, timer in timers do
		local label = timer.label
		if label and label.Parent then
			local left = timer.endsAt - now
			label.Text = (timer.prefix or "") .. Ui.clock(math.max(0, left))
			label.TextColor3 = if left < 30 then K.red else K.text
		end
	end
end

-- The app was left or redrawn without the orders.
function OrdersUi.clear()
	table.clear(timers)
end

return OrdersUi
