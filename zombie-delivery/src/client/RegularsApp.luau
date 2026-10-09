--!strict
-- 6.14, the REGULARS (shared/Regulars.luau, Config.Regulars; the owner: "a bit MORE grind, but a FUN grind"): the
-- phone's MORE → REGULARS app, drawn in the phone's popup with the phone's own kit (OrdersUi.Kit, design/phone-ui/).
--   * On top: how many businesses know you ("8 / 25 businesses know you"), the tiers held (🥉 3 · 🥈 1 …) and what a
--     tier pays (Bronze at 5 deliveries +5 % … Platinum at 100 +20 %), and that a Silver regular gets REGULAR'S ORDERS.
--   * A card for every business that gives jobs (25; two columns in a wide popup): its picture (client/JobThumbUi.luau,
--     the strip, or the slim banner while it is not uploaded), its name, its medal and bonus ("🥈 SILVER · +10%"), a bar
--     to the next tier and the words ("17 deliveries · 23 more for GOLD +15%"). The ones you never delivered for are
--     greyed: "Deliver for them once to meet them". The highest tier first (Regulars.view).
--   * RegularsApp.badge(offer): a job row's badge for its business (the phone's JOBS list, client/PhoneApps.luau; J's
--     board, client/DispatchUi.luau): its words and its medal's colour; nil for a business never met.
--   * The counts come with the State (server/Main.server.luau sends profile.regulars; RegularsApp.start listens): a
--     tier reached says so with a toast ("Luigi's Pizza: you're a SILVER regular · +10% pay") and the level-up sting a
--     little higher (client/Sounds.luau "level_up"); several at once (the admin's REGULARS) one toast.
-- Presentation only: the server counts the deliveries and pays the bonus (server/Regulars.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rules = require(Shared.Regulars)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local OrdersUi = require(script.Parent.OrdersUi)
local JobThumbUi = require(script.Parent.JobThumbUi)

local K = Theme.Contract
local RegularsApp = {}

-- The medals' colours (Theme.Postage's bronze, silver and gold; a cool platinum).
local MEDALS: { [string]: Color3 } = {
	bronze = Color3.fromRGB(198, 134, 86),
	silver = Color3.fromRGB(186, 191, 199),
	gold = Color3.fromRGB(214, 178, 92),
	platinum = Color3.fromRGB(170, 214, 228),
}
local DIM = Color3.fromRGB(96, 98, 102) -- a business never met: its picture greyed
local PICTURE = 64 -- a card's picture strip, px (cropped: the sign shows)

local regulars: { [string]: number }? = nil -- the State's counts (nil before the first State)
local notify: ((string) -> ())? = nil

-- A medal's colour (the secondary text for no tier).
function RegularsApp.colorOf(tier: string?): Color3
	return if tier and MEDALS[tier] then MEDALS[tier] else K.secondary
end

-- The counts as the last State said (an empty table before it).
function RegularsApp.counts(): { [string]: number }
	return regulars or {}
end

local function sound(name: string, volume: number, pitch: number)
	pcall(function()
		local play = (require(script.Parent.Sounds) :: any).play
		if play then
			play(name, volume, pitch)
		end
	end)
end

-- The State's `regulars` (RegularsApp.start; the phone check sets it too): a tier reached since the last one is said.
function RegularsApp.setRegulars(value: any)
	if type(value) ~= "table" then
		return
	end
	local fresh = Rules.clean(value)
	local before = regulars
	regulars = fresh
	if not before then
		return -- (the first State: nothing new)
	end
	local ups: { { id: string, tier: Rules.Tier } } = {}
	for id, count in fresh do
		local _, was = Rules.tierOf(before[id] or 0)
		local tier, now = Rules.tierOf(count)
		if tier and now > was then
			table.insert(ups, { id = id, tier = tier })
		end
	end
	if #ups == 0 then
		return
	end
	sound("level_up", 0.75, 1.15)
	local tell = notify
	if tell then
		tell(if #ups == 1 then Rules.tierUpText(ups[1].id, ups[1].tier) else `REGULARS: {#ups} businesses know you better now · MORE → REGULARS`)
	end
end

function RegularsApp.badge(offer: any): (string?, Color3?)
	local text, tier = Rules.badge(regulars, offer)
	if not text then
		return nil, nil
	end
	return text, RegularsApp.colorOf(tier)
end

-- Two columns in a wide popup (each a vertical list), else both are the list itself.
local function columns(list: Instance, order: number, two: boolean): (Instance, Instance)
	if not two then
		return list, list
	end
	local row = Ui.make("Frame", { Name = "Columns", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, list)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, row)
	local function column(index: number): Instance
		local made = Ui.make("Frame", {
			Name = if index == 1 then "Left" else "Right",
			Size = UDim2.new(0.5, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, row)
		Ui.list(made, true, 8)
		return made
	end
	return column(1), column(2)
end

-- A thin bar (share 0 … 1) in the medal's colour.
local function bar(parent: Instance, share: number, color: Color3, order: number)
	local holder = Ui.make("Frame", { Name = "Progress", Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local back = Ui.make("Frame", { Name = "Track", Size = UDim2.new(1, 0, 0, 4), Position = UDim2.fromOffset(0, 2), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, holder)
	Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(math.clamp(share, 0, 1), 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
end

-- One business's card.
local function card(parent: Instance, entry: Rules.Card, order: number, look: OrdersUi.Kit)
	local color = RegularsApp.colorOf(entry.tier)
	local b = look.block(parent, order, entry.rank > 0)
	b.Parent.Name = `Regular_{entry.id}`
	local strip = JobThumbUi.strip(b, Rules.infoOf(entry.id), 0, PICTURE)
	local picture = if strip then strip:FindFirstChild("Picture") else nil
	if picture and not entry.met then
		picture.ImageColor3 = DIM
		picture.ImageTransparency = 0.35
	end
	local tag = if picture and strip then strip:FindFirstChild("Business") else nil
	if tag then
		tag.Visible = false -- (the card's own title names it, right under the picture)
	end
	-- The name and the medal (or how many deliveries so far).
	local medal = if entry.tierName then `{entry.icon or ""} {string.upper(entry.tierName)} · +{Rules.percent(entry.bonus)}%` else (if entry.met then "NEW FACE" else "NOT MET")
	local medalW = look.width(medal, 12, Theme.HeadingFont)
	local head = Ui.make("Frame", { Name = "TitleRow", Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
	look.text(head, medal, UDim2.new(0, medalW, 1, 0), {
		Name = "Medal",
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = if entry.tierName then color else K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	look.text(head, string.upper(entry.name), UDim2.new(1, -(medalW + 8), 1, 0), {
		Name = "Name",
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = if entry.met then K.text else K.secondary,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if not entry.met then
		look.meta(b, "Deliver for them once to meet them.", 2).Name = "Hint"
		return
	end
	bar(b, entry.progress, if entry.tierName then color else K.secondary, 2)
	local deliveries = `{entry.count} {if entry.count == 1 then "delivery" else "deliveries"}`
	local nextWords = if entry.nextName and entry.nextAt
		then `{entry.toGo} more for {string.upper(entry.nextName)} (+{Rules.percent(Rules.bonusOf(entry.nextAt))}%)`
		else "Top tier: the best pay there is"
	look.meta(b, `{deliveries} · {nextWords}`, 3, if entry.tierName then K.text else K.secondary).Name = "Next"
end

-- The app in the phone's popup (`list`, its scrolling body; `wide`: two columns of cards).
function RegularsApp.draw(list: Instance, look: OrdersUi.Kit, wide: boolean?)
	local view = Rules.view(regulars or {})
	local head = look.block(list, 1, true)
	head.Parent.Name = "RegularsSummary"
	look.caps(head, `{view.met} / {view.total} businesses know you`, 1)
	local chips = look.chipRow(head, 2)
	for _, tier in Rules.Tiers do
		look.chip(chips, `{tier.icon} {tier.name} {view.tiers[tier.id] or 0}`, RegularsApp.colorOf(tier.id))
	end
	local rates: { string } = {}
	for _, tier in Rules.Tiers do
		table.insert(rates, `{tier.name} at {tier.at} +{Rules.percent(tier.bonus)}%`)
	end
	look.meta(head, `Every delivery for a business counts. Its regulars earn more on every job for it: {table.concat(rates, " · ")}. Silver regulars get a REGULAR'S ORDER now and then.`, 3)
	look.section(list, "Businesses", 2)
	local left, right = columns(list, 3, wide == true)
	for index, entry in view.list do
		local ok, err = pcall(function()
			card(if index % 2 == 1 then left else right, entry, 3 + index, look)
		end)
		if not ok then
			warn(`[RegularsApp] a card failed: {err}`)
		end
	end
end

-- Listens to the State (the counts) and says a tier reached with `toast` (client/Main.client.luau: Hud.toast).
function RegularsApp.start(toast: (string) -> ())
	notify = toast
	Net.get("State").OnClientEvent:Connect(function(state: any)
		if type(state) == "table" then
			RegularsApp.setRegulars(state.regulars)
		end
	end)
end

return RegularsApp
