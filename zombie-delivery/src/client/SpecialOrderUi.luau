--!strict
-- 6.14, the GOLDEN ORDERS and the REGULARS' ORDERS on the client (shared/SpecialOrders.luau; a board row, a NEXT UP
-- entry and a result carry them: server/Jobs.luau describe, queueApi.view, payOrder's `special`). Presentation only.
--   SpecialOrderUi.split(list)              the job list's rows: the special orders (their own section on top) and the rest
--   SpecialOrderUi.colorOf(spec), faceOf(spec)   its accent (gold; a regular's order a cool silver) and its card's face
--   SpecialOrderUi.decorate(card, body, offer)   the phone's card (client/PhoneApps.luau) in its colours: the frame, the
--                                           ★ line with its perks ("★ GOLDEN ORDER · ×3 PAY · ×2 XP · MORE DANGER") and
--                                           the countdown at its right
--   SpecialOrderUi.frame(card, offer)       J's row (client/DispatchUi.luau): its card's face and frame
--   SpecialOrderUi.tintChip(label, offer)   J's ★ chip in its colour
--   SpecialOrderUi.countdown(label, expiresAt, prefix?)   a label counting down to `expiresAt` (server time), red in
--                                           its last URGENT s: one loop every 0.5 s for every such label, while any shows
--   SpecialOrderUi.resultLines(r), tint(row, gold), toast(r, toast)   the result window's lines (client/Hud.luau
--                                           showResult: "★ GOLDEN ORDER ×3 · ×2 XP", "Regular · Luigi's Pizza (Silver)
--                                           +$8") and, for a run whose result is a toast (on foot, by bike, an order
--                                           done mid-run), one more toast with them
--   SpecialOrderUi.start(toast)             a special order coming onto the board (a new row of one in the Offers remote):
--                                           a toast ("★ A GOLDEN ORDER is on your board · 3:00 · …") and a sting
--                                           (client/Sounds.luau "event_start" for a golden one, "notify" for a regular's)
-- The server decides its pay, its danger and when it leaves the board (server/SpecialOrders.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rules = require(Shared.SpecialOrders)
local Regulars = require(Shared.Regulars)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local SpecialOrderUi = {}

local GOLD = Color3.fromRGB(214, 178, 92) -- Theme.Postage.gold
local GOLD_FACE = Color3.fromRGB(44, 39, 27) -- Theme.Postage.butter: a gold card's charcoal face
local REGULAR = Color3.fromRGB(170, 200, 228) -- a regular's order: a cool silver
local REGULAR_FACE = Color3.fromRGB(28, 35, 44) -- Theme.Postage.sky
local RED = Color3.fromRGB(215, 74, 70) -- Theme.Contract.red: a countdown's last seconds
local URGENT = 30

type Timer = { label: any, expiresAt: number, prefix: string, color: Color3? }
local timers: { Timer } = {}
local ticking = false
local seen: { [number]: boolean } = {} -- the special rows already said (by their board index)

local function specOf(offer: any): any
	return if type(offer) == "table" and type(offer.specialOrder) == "table" then offer.specialOrder else nil
end

function SpecialOrderUi.colorOf(spec: any): Color3
	return if type(spec) == "table" and spec.kind == "golden" then GOLD else REGULAR
end

function SpecialOrderUi.faceOf(spec: any): Color3
	return if type(spec) == "table" and spec.kind == "golden" then GOLD_FACE else REGULAR_FACE
end

function SpecialOrderUi.split(list: { any }): ({ any }, { any })
	local specials: { any } = {}
	local rest: { any } = {}
	for _, offer in list do
		table.insert(if specOf(offer) then specials else rest, offer)
	end
	return specials, rest
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Every countdown label's text; false once none shows any more.
local function tick(): boolean
	local now = workspace:GetServerTimeNow()
	for index = #timers, 1, -1 do
		local timer = timers[index]
		local label = timer.label
		if not label or not label.Parent then
			table.remove(timers, index)
		else
			local left = timer.expiresAt - now
			label.Text = timer.prefix .. clock(left)
			if timer.color then
				label.TextColor3 = if left < URGENT then RED else timer.color
			end
		end
	end
	return #timers > 0
end

function SpecialOrderUi.countdown(label: any, expiresAt: any, prefix: string?)
	local at = tonumber(expiresAt)
	if not label or not at then
		return
	end
	table.insert(timers, { label = label, expiresAt = at, prefix = prefix or "", color = label.TextColor3 })
	label.Text = (prefix or "") .. clock(at - workspace:GetServerTimeNow())
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, more = pcall(tick)
			if not ok or not more then
				break
			end
		end
		ticking = false
	end)
end

function SpecialOrderUi.decorate(card: any, body: any, offer: any): boolean
	local spec = specOf(offer)
	if not spec or not card or not body then
		return false
	end
	local color = SpecialOrderUi.colorOf(spec)
	card.BackgroundColor3 = SpecialOrderUi.faceOf(spec)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = 2
		stroke.Transparency = 0
	end
	local accent = card:FindFirstChild("Accent")
	if accent then
		accent.BackgroundColor3 = color
	end
	card:SetAttribute("SpecialOrder", spec.kind)
	-- (the perks wrap onto a second line in a narrow column; the countdown stays at the top right)
	local head = Ui.make("Frame", { Name = "SpecialOrder", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = -1 }, body)
	Ui.label(head, `{Rules.label(spec)} · {Rules.perks(spec)}`, UDim2.new(1, -60, 0, 0), {
		Name = "Perks",
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = color,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local left = Ui.label(head, "", UDim2.new(0, 56, 0, 18), {
		Name = "Countdown",
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = color,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	SpecialOrderUi.countdown(left, spec.expiresAt, "⏱ ")
	return true
end

function SpecialOrderUi.frame(card: any, offer: any)
	local spec = specOf(offer)
	if not spec or not card then
		return
	end
	card.BackgroundColor3 = SpecialOrderUi.faceOf(spec)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = SpecialOrderUi.colorOf(spec)
		stroke.Thickness = 2
		stroke.Transparency = 0
	end
	card:SetAttribute("SpecialOrder", spec.kind)
end

function SpecialOrderUi.tintChip(label: any, offer: any)
	local spec = specOf(offer)
	if not spec or not label then
		return
	end
	local color = SpecialOrderUi.colorOf(spec)
	label.TextColor3 = color
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Transparency = 0.2
	end
end

function SpecialOrderUi.resultLines(r: any): { Rules.Line }
	return Rules.resultLines(r)
end

-- A result line's row in gold (`gold`), its texts.
function SpecialOrderUi.tint(row: any, gold: boolean)
	if not gold or not row then
		return
	end
	for _, child in row:GetChildren() do
		if child:IsA("TextLabel") then
			child.TextColor3 = GOLD
		end
	end
end

-- The money of a line ("+$8").
function SpecialOrderUi.money(line: Rules.Line): string?
	return if line.money then "+" .. Ui.money(line.money) else nil
end

-- A run whose result is a toast (on foot, by bike, an order done while others go on): its lines as one more toast.
function SpecialOrderUi.toast(r: any, toast: (string) -> ())
	if type(r) ~= "table" or r.success ~= true or not (r.mode == "foot" or r.mode == "bike" or r.midJob == true) then
		return
	end
	local parts: { string } = {}
	for _, line in Rules.resultLines(r) do
		local money = SpecialOrderUi.money(line)
		table.insert(parts, if money then `{line.text} {money}` else line.text)
	end
	if #parts > 0 then
		toast(table.concat(parts, " · "))
	end
end

local function sound(name: string, volume: number)
	pcall(function()
		local play = (require(script.Parent.Sounds) :: any).play
		if play then
			play(name, volume)
		end
	end)
end

-- A board the server sent (the Offers remote): a special row not said yet is said now (a toast and a sting).
function SpecialOrderUi.onOffers(list: any, toast: (string) -> ())
	if type(list) ~= "table" then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, row in list do
		local spec = specOf(row)
		local index = if type(row) == "table" then tonumber(row.index) else nil
		if spec and index and not seen[index] and not Rules.expired(spec, now) then
			seen[index] = true
			local name = if spec.kind == "regular" then Regulars.nameOf(tostring(spec.business)) else nil
			toast(Rules.appearText(spec, name, Rules.left(spec, now)))
			sound(if spec.kind == "golden" then "event_start" else "notify", 0.8)
		end
	end
end

function SpecialOrderUi.start(toast: (string) -> ())
	Net.get("Offers").OnClientEvent:Connect(function(list: any)
		SpecialOrderUi.onOffers(list, toast)
	end)
end

return SpecialOrderUi
