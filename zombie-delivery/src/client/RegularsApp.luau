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
-- 6.18 (the UI kit, client/CardKit.luau; design/ui-kit/README.md): REGULARS in the JOBS look. Chips (in the popup's
-- header when they fit, else on top of the body): who knows
-- you ("2 / 25 KNOW YOU") and the tiers held ("🥈 SILVER 1"). The HERO is your best regular (the highest tier first):
-- its business's picture, its medal on the ribbon ("🥈 SILVER · +10%"), its name, the bonus big in the medal's
-- colour, "15 deliveries · 25 more for GOLD (+15%)" and the bar to the next tier. The other businesses are the kit's
-- rows (Regular_<id>): the picture (greyed and "NOT MET" while you never delivered for them), the medal on its corner,
-- the name, one line, the bonus big. What a tier pays closes the list in one line. The hero sits beside the rows in a
-- wide popup.
-- Presentation only: the server counts the deliveries and pays the bonus (server/Regulars.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rules = require(Shared.Regulars)
local Theme = require(script.Parent.Theme)
local OrdersUi = require(script.Parent.OrdersUi)
local JobThumbs = require(Shared.JobThumbs)
local CardKit = require(script.Parent.CardKit) -- 6.18: the UI kit

local K = Theme.Contract
local RegularsApp = {}

-- The medals' colours (Theme.Postage's bronze, silver and gold; a cool platinum).
local MEDALS: { [string]: Color3 } = {
	bronze = Color3.fromRGB(198, 134, 86),
	silver = Color3.fromRGB(186, 191, 199),
	gold = Color3.fromRGB(214, 178, 92),
	platinum = Color3.fromRGB(170, 214, 228),
}

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

-- A business's picture (its business's, shared/JobThumbs.luau), else its emoji.
local function picture(entry: Rules.Card): CardKit.Picture
	local image, _, emoji = JobThumbs.forJob(Rules.infoOf(entry.id))
	return { image = image, emoji = emoji or entry.emoji }
end

-- The medal's words ("🥈 SILVER · +10%"), else NEW FACE / NOT MET.
local function medalOf(entry: Rules.Card): string
	return if entry.tierName then `{entry.icon or ""} {string.upper(entry.tierName)} · +{Rules.percent(entry.bonus)}%` else (if entry.met then "NEW FACE" else "NOT MET")
end

-- "15 deliveries · 25 more for GOLD (+15%)", or the top tier's.
local function lineOf(entry: Rules.Card): string
	if not entry.met then
		return "Deliver for them once to meet them."
	end
	local deliveries = `{entry.count} {if entry.count == 1 then "delivery" else "deliveries"}`
	local nextWords = if entry.nextName and entry.nextAt
		then `{entry.toGo} more for {string.upper(entry.nextName)} (+{Rules.percent(Rules.bonusOf(entry.nextAt))}%)`
		else "Top tier: the best pay there is"
	return `{deliveries} · {nextWords}`
end

-- The hero: your best regular (see the header).
local function heroCard(parent: Instance, entry: Rules.Card, height: number)
	local color = RegularsApp.colorOf(entry.tier)
	CardKit.hero(parent, {
		name = `Regular_{entry.id}`,
		height = height,
		stroke = if entry.tierName then color else nil,
		strong = entry.tierName ~= nil,
		picture = picture(entry),
		title = string.upper(entry.name),
		value = `+{Rules.percent(entry.bonus)}%`,
		valueColor = if entry.tierName then color else K.secondary,
		facts = lineOf(entry),
		bar = { share = entry.progress, color = if entry.tierName then color else K.secondary },
		ribbon = { text = medalOf(entry), face = if entry.tierName then color else K.raised, ink = if entry.tierName then CardKit.Color.goldInk else K.text },
		onOpen = function() end,
		silent = true,
	})
end

-- One business's row (see the header).
local function businessRow(parent: Instance, entry: Rules.Card, order: number)
	local color = RegularsApp.colorOf(entry.tier)
	local made = CardKit.row(parent, {
		name = `Regular_{entry.id}`,
		order = order,
		accent = if entry.tierName then color else K.line,
		picture = picture(entry),
		shut = not entry.met,
		overlay = entry.icon,
		title = string.upper(entry.name),
		titleColor = if entry.met then K.text else K.secondary,
		facts = lineOf(entry),
		value = if entry.met then `+{Rules.percent(entry.bonus)}%` else nil,
		valueColor = if entry.tierName then color else K.secondary,
		lock = if entry.met then nil else "NOT MET",
		silent = true,
		onOpen = function() end,
	})
	made.title.Name = "Name"
	made.facts.Name = if entry.met then "Next" else "Hint"
	if entry.met then
		CardKit.rowBar(made, entry.progress, if entry.tierName then color else K.secondary)
	end
end

-- The app in the phone's popup (`list`, its scrolling body; `wide`: the hero beside the rows).
function RegularsApp.draw(list: Instance, look: OrdersUi.Kit, wide: boolean?)
	local view = Rules.view(regulars or {})
	local chips = CardKit.chips(list, "RegularsSummary", 0)
	CardKit.chip(chips, { name = "Known", text = `{view.met} / {view.total} KNOW YOU`, order = 0, static = true })
	for index, tier in Rules.Tiers do
		CardKit.chip(chips, { name = `Tier_{tier.id}`, text = string.upper(`{tier.icon} {tier.name} {view.tiers[tier.id] or 0}`), ink = RegularsApp.colorOf(tier.id), order = index, static = true })
	end
	local popup = require(script.Parent.PhonePopup)
	local bar, barRoom = popup.bar()
	local taken = CardKit.toHeader(chips, bar, barRoom, list) -- (the header's strip when they fit, like JOBS' chips)
	local first = view.list[1]
	local hero = if first and first.met then first else nil
	local height = CardKit.Layout.heroHeight(popup.room() - taken)
	local _, left, right = CardKit.columns(list, { name = "RegularsView", order = 1, side = wide == true and hero ~= nil, hero = hero ~= nil, heroHeight = height })
	if hero then
		heroCard(left, hero, height)
	end
	CardKit.sectionHeader(right, { name = "BusinessesHead", text = "BUSINESSES", order = 0 })
	for index, entry in view.list do
		if entry ~= hero then
			local ok, err = pcall(function()
				businessRow(right, entry, index)
			end)
			if not ok then
				warn(`[RegularsApp] a row failed: {err}`)
			end
		end
	end
	local rates: { string } = {}
	for _, tier in Rules.Tiers do
		table.insert(rates, `{tier.name} {tier.at} +{Rules.percent(tier.bonus)}%`)
	end
	look.meta(right, `Every delivery for a business counts: {table.concat(rates, " · ")}. Silver regulars get a REGULAR'S ORDER now and then.`, #view.list + 1).Name = "Rates"
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
