--!strict
-- 5.2: the orders of your run in the phone's ORDERS app (client/Phone.luau draws the focused order, then this): one
-- block per order (server/Jobs.luau's payload `orders`): its cargo and customer, its stops (✓ done, ▶ the one the GPS
-- shows, ● open, ○ waiting: a drop opens once its order's pieces are picked up), its own clock (ticked while the phone
-- is open: OrdersUi.tick), its pay, and PIN / UNPIN (the PinOrder remote: the GPS follows the pinned order; the stop
-- whose circle you are at always comes first). The orders done or lost so far are one quiet line each. Also what you
-- carry, piece by piece (the payload's `carried`), when it is more than one order's.
-- Presentation only: the server decides the stops, the clocks and the pay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local K = Theme.Contract
local OrdersUi = {}

-- The Phone's own list pieces, handed in (one look for every app).
export type Kit = {
	block: (parent: Instance, order: number, selected: boolean?) -> any,
	caps: (parent: Instance, value: string, order: number, color: Color3?) -> any,
	text: (parent: Instance, value: string, size: UDim2, props: { [string]: any }?) -> any,
	button: (parent: Instance, label: string, kind: any, order: number, onClick: () -> ()) -> any,
}

type Timer = { label: any, endsAt: number }

local timers: { Timer } = {}

local function stopMark(stop: any): string
	if stop.done == true then
		return "✓"
	elseif stop.current == true then
		return "▶"
	elseif stop.open == true then
		return "●"
	end
	return "○"
end

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

-- Draws the run's orders into the phone's list from layout order `order` on; returns the next free layout order.
-- Nothing (the same order back) for a job of one order.
function OrdersUi.render(list: Instance, job: any, kit: Kit, order: number): number
	table.clear(timers)
	local orders = if type(job) == "table" and type(job.orders) == "table" then job.orders else nil
	if not orders or #orders <= 1 then
		return order
	end
	local open: { any }, closed: { any } = {}, {}
	for _, entry in orders do
		if type(entry) == "table" then
			table.insert(if entry.state == "open" then open else closed, entry)
		end
	end
	local carried = carriedBy(job)
	local n = order
	local head = kit.block(list, n)
	n += 1
	kit.caps(head, `Your orders · {#open} on the go`, 1, K.red)
	kit.text(head, "The GPS takes the stop you are at, else the pinned order, else the nearest. Pick-ups in any order; a drop once its pieces are with you.", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextColor3 = K.secondary,
		TextSize = 12,
	})
	for _, entry in open do
		local b = kit.block(list, n, entry.focused == true)
		n += 1
		local stars = tonumber(entry.stars) or 0
		local mode = if entry.mode == "foot" then "🚶" elseif entry.mode == "bike" then "🚲" else string.rep("★", stars)
		kit.caps(b, `Order {entry.id} · {mode}{if entry.pinned == true then " · 📌 pinned" else ""}{if entry.focused == true then " · now" else ""}`, 1, if entry.pinned == true then K.red else nil)
		kit.text(b, tostring(entry.title or entry.cargo or "Order"), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Font = Theme.HeadingFont, TextSize = 15 })
		local lines: { string } = {}
		if type(entry.stops) == "table" then
			for _, stop in entry.stops do
				if type(stop) == "table" then
					table.insert(lines, `{stopMark(stop)} {stop.label or (if stop.kind == "pickup" then "Pick up" else "Deliver")}`)
				end
			end
		end
		kit.text(b, table.concat(lines, "\n"), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, TextColor3 = K.secondary, TextSize = 12 })
		local mine = carried[tonumber(entry.id) or -1]
		if mine and #mine > 0 then
			kit.text(b, `With you: {table.concat(mine, ", ")}`, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, TextColor3 = K.secondary, TextSize = 12 })
		end
		-- The clock (ticked) and the pay.
		local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 5 }, b)
		local clock = kit.text(row, "", UDim2.new(0.5, 0, 1, 0), { Font = Theme.HeadingFont, TextSize = 16, TextWrapped = false })
		if type(entry.endsAt) == "number" then
			table.insert(timers, { label = clock, endsAt = entry.endsAt })
		end
		kit.text(row, `{Ui.money(tonumber(entry.pay) or 0)} · {tonumber(entry.delivered) or 0}/{tonumber(entry.pieces) or 0}`, UDim2.new(0.5, 0, 1, 0), {
			Position = UDim2.fromScale(0.5, 0),
			Font = Theme.HeadingFont,
			TextSize = 16,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local id = tonumber(entry.id)
		local pinned = entry.pinned == true
		kit.button(list, if pinned then `UNPIN ORDER {entry.id}` else `📌 PIN ORDER {entry.id} (GPS)`, "quiet", n, function()
			pin(if pinned then nil else id)
		end)
		n += 1
	end
	if #closed > 0 then
		local b = kit.block(list, n)
		n += 1
		kit.caps(b, "Done today on this run", 1)
		local lines: { string } = {}
		for _, entry in closed do
			local got = tonumber(entry.rating)
			local how = if entry.state == "done" then `✓ +{Ui.money(tonumber(entry.paid) or 0)}{if got then ` {string.rep("★", got)}` else ""}` else "✗ lost"
			table.insert(lines, `{how} · {entry.cargo or "Order"} for {entry.customer or "?"}`)
		end
		kit.text(b, table.concat(lines, "\n"), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextColor3 = K.secondary, TextSize = 12 })
	end
	OrdersUi.tick()
	return n
end

-- The orders' clocks (the phone's open loop, twice a second).
function OrdersUi.tick()
	local now = workspace:GetServerTimeNow()
	for _, timer in timers do
		local label = timer.label
		if label and label.Parent then
			local left = timer.endsAt - now
			label.Text = Ui.clock(math.max(0, left))
			label.TextColor3 = if left < 30 then K.red else K.text
		end
	end
end

-- The app was left or redrawn without the orders.
function OrdersUi.clear()
	table.clear(timers)
end

return OrdersUi
