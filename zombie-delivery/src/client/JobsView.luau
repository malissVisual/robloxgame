--!strict
-- 6.17, the JOBS app at a glance (the owner: "when I open JOBS I want to leave, it doesn't make me want to click a
-- job"; he picked redesign B). The phone's JOBS app (client/PhoneApps.luau board) and J (client/Main.client.luau)
-- open it in the phone's popup:
--   * The top bar, in the popup's header right of "JOBS" (PhonePopup.bar): "▶ YOUR RUN · 2 · $340" while you are on a
--     run (a tap: YOUR RUN, PhoneApps.runCard), "NEXT UP · 1" while jobs wait (a tap: NEXT UP, PhoneApps.nextUp, with
--     its PAUSE / RESUME, CLEAR ALL and ✕) and at the right, while rush hour (6.15) pays, "🕑 RUSH ×1.5 · 3:12" with
--     its clock. (A narrow popup: "▶ RUN · 2 · $340", the rush chip heads the body.)
--   * Left, the HERO card: the best job right now (shared/JobPick.luau hero): a GOLDEN ORDER (gold frame, the
--     "★ GOLDEN ORDER ×3" ribbon, the ⏳ countdown), else a REGULAR'S ORDER (silver), else the best-paying job you can
--     take. Its business's picture (shared/JobThumbs.luau) fills the card, the name and the danger stars, the PAY big
--     (gold for a golden order, green else), one line of facts (📍 distance, ⏱ time, +2× XP) and one big button
--     ("TAKE GOLDEN ORDER", "TAKE JOB", "+ ADD", "+ QUEUE"; a locked one says why on a tap). ⓘ (or a tap on the card)
--     opens its details.
--   * Right, "N MORE JOBS" with a small "ADD ALL · $X" chip (the JobQueue remote's addAll; a toast says what it did),
--     then a compact row a job: its picture (greyed while locked; a regular's tier medal on it), the danger stars in
--     their colour (🚶 / 🚲 on foot or by bike), the business, "📍 420 · ⏱ 2:10", the pay big in green and a red "+"
--     (the same action as the old card's: ACCEPT, + ADD or + QUEUE); a locked row shows "🔒 LV 9" (its reason on a
--     tap). A tap on the row opens its details.
--   * The details (a sub-view, "‹ JOBS" goes back): the old full card (PhoneApps' offerCard: the cargo → the
--     customer, the addresses, the district, the role chips, the modifiers, night ×, the regulars' words, the lock's
--     words such as NEEDS 6 SLOTS) with its action.
-- On a gamepad the hero's button takes the first selection; the rows, the ⓘ and the chips are selectable buttons.
-- Presentation only: every action keeps its server path (AcceptJob, JobQueue); the server decides every job.
-- 6.18: drawn with the UI kit (client/CardKit.luau: hero, row, chip, sectionHeader, columns, details; the sizes in
-- Config.UiKit), the same look as 6.17; every popup and the phone's home use the kit now (design/ui-kit/README.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local JobPick = require(Shared.JobPick)
local JobQueue = require(Shared.JobQueue)
local JobThumbs = require(Shared.JobThumbs)
local LiveEvents = require(Shared.LiveEvents)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local SpecialOrderUi = require(script.Parent.SpecialOrderUi)
local RegularsApp = require(script.Parent.RegularsApp)
local CardKit = require(script.Parent.CardKit)

local K = Theme.Contract
local TUNE = Config.UiKit
local JobsView = {}

-- What PhoneApps lends the view: the old full card, YOUR RUN, NEXT UP, a job's one action and its lock.
export type Parts = {
	card: (parent: Instance, offer: any, order: number) -> (),
	run: (list: Instance, order: number) -> number,
	nextUp: (list: Instance, order: number) -> number,
	act: (offer: any) -> (),
	why: (offer: any) -> (string?, string?),
}

local C = CardKit.Color
local DANGER = CardKit.Danger

-- The sub-view: nil the list, "run" YOUR RUN, "next" NEXT UP, "job" a job's details (JobsView.detail: its index).
JobsView.view = nil :: string?
JobsView.detail = nil :: number?

-- Back to the list (Phone: JOBS opens on it).
function JobsView.home()
	JobsView.view = nil
	JobsView.detail = nil
end

local click = CardKit.click

local function goTo(host: any, view: string?, detail: number?)
	JobsView.view = view
	JobsView.detail = detail
	host.redraw()
end

-- The top bar (see the header): its chips in the popup header's strip while they fit there (host.bar: the strip and
-- its room in px), else in a row heading the body. Returns the next layout order in the body.
local function topBar(list: Instance, look: any, host: any, wide: boolean): number
	local bar, room = host.bar()
	local job = host.job()
	local queue = host.queue()
	local queued = if type(queue) == "table" and type(queue.list) == "table" then #queue.list else 0
	local chips = Ui.make("Frame", { Name = "Chips", Size = UDim2.new(1, 0, 0, TUNE.Chip), BackgroundTransparency = 1, LayoutOrder = 0 })
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, chips)
	local width = 0 -- (the chips on the left with their gaps)
	if type(job) == "table" then
		local lines, total = JobQueue.runLines(job)
		local run = CardKit.chip(chips, { name = "RunChip", text = JobPick.runChip(math.max(1, #lines), Ui.money(total), not wide), face = C.runFace, ink = C.runInk, order = 1, stroke = C.runInk, lit = JobsView.view == "run", onClick = function()
			goTo(host, if JobsView.view == "run" then nil else "run")
		end })
		width += run.Size.X.Offset + 8
	end
	if queued > 0 then
		local nextUp = CardKit.chip(chips, { name = "NextChip", text = JobPick.nextChip(queued), order = 2, stroke = K.text, lit = JobsView.view == "next", faint = 0.85, onClick = function()
			goTo(host, if JobsView.view == "next" then nil else "next")
		end })
		width += nextUp.Size.X.Offset + 8
	end
	-- 6.15's rush hour (the workspace attributes server/LiveEvents.luau keeps): its chip at the right, its clock ticking.
	local id = workspace:GetAttribute(LiveEvents.Attr.Id)
	local prefix = JobPick.rushPrefix(if type(id) == "string" then id else nil)
	local rush: any = nil
	if prefix then
		rush = CardKit.chip(chips, { name = "RushChip", text = prefix, face = C.rushFace, ink = C.rushInk, order = 3, room = prefix .. "0:00", static = true })
		SpecialOrderUi.countdown(rush, workspace:GetAttribute(LiveEvents.Attr.Ends), prefix)
	end
	if width == 0 and not rush then
		chips:Destroy()
		return 0
	end
	local need = width + (if rush and wide then rush.Size.X.Offset else 0)
	if bar and need <= (tonumber(room) or 0) then
		chips.Size = UDim2.fromScale(1, 1)
		chips.Parent = bar
		if rush and wide then
			rush.Parent = bar -- (at the strip's right)
			rush.AnchorPoint = Vector2.new(1, 0.5)
			rush.Position = UDim2.fromScale(1, 0.5)
		elseif rush then
			rush.Parent = list
			rush.LayoutOrder = 0
			return 1
		end
		return 0
	end
	chips.Parent = list -- (no room in the header: a row heading the body)
	return 1
end

local function findOffer(offers: { any }?, index: number?): any
	for _, offer in (if type(offers) == "table" then offers else {}) :: { any } do
		if type(offer) == "table" and index ~= nil and offer.index == index then
			return offer
		end
	end
	return nil
end

-- The picture of a job (its business's: shared/JobThumbs.luau), else its emoji.
local function picture(offer: any): CardKit.Picture
	local image, _, emoji = JobThumbs.forJob(offer)
	return { image = image, emoji = emoji }
end

local function nameOf(offer: any): string
	local _, name = JobThumbs.forJob(offer)
	return string.upper(name or offer.cargo or "Job")
end

-- The hero card (see the header), `height` px tall.
local function heroCard(parent: Instance, host: any, parts: Parts, offer: any, kind: string, height: number)
	local onDuty = type(host.job()) == "table"
	local spec = if type(offer.specialOrder) == "table" then offer.specialOrder else nil
	local label = parts.why(offer)
	local shut = JobPick.blocked(offer, onDuty) -- (locked, or during a run neither + ADD nor + QUEUE)
	local stuck = if shut then (label or (if type(offer.queueButton) == "string" then offer.queueButton elseif type(offer.orderButton) == "string" then offer.orderButton else "FINISH YOUR RUN")) else nil
	local golden = kind == "golden"
	local accent = if spec then SpecialOrderUi.colorOf(spec) else K.line
	local danger, level = JobPick.danger(offer)
	local function details()
		goTo(host, "job", tonumber(offer.index))
	end
	local ribbon = JobPick.ribbon(offer)
	local made = CardKit.hero(parent, {
		height = height,
		face = if spec then SpecialOrderUi.faceOf(spec) else nil,
		stroke = if golden then C.gold else accent,
		strong = spec ~= nil,
		picture = picture(offer),
		shut = shut,
		title = `{nameOf(offer)}  ·`,
		tag = danger,
		tagColor = DANGER[level],
		value = Ui.money(tonumber(offer.pay) or 0),
		valueColor = if shut then C.dim elseif golden then C.gold else C.money,
		facts = table.concat(JobPick.heroFacts(offer), "    "),
		action = {
			name = "Take",
			text = stuck or JobPick.button(offer, onDuty),
			kind = if shut then "shut" elseif golden then "gold" else "primary",
			onClick = function()
				parts.act(offer)
			end,
		},
		ribbon = if ribbon then { text = ribbon, face = accent } else nil,
		corner = if ribbon then { text = "", ink = accent } else nil,
		medal = if ribbon then nil else JobPick.medal(RegularsApp.counts(), offer),
		onOpen = details,
		onDetails = details,
	})
	made.card:SetAttribute("Hero", kind)
	made.card:SetAttribute("Index", offer.index)
	if spec then
		made.card:SetAttribute("SpecialOrder", spec.kind)
	end
	if made.corner then
		SpecialOrderUi.countdown(made.corner, spec and spec.expiresAt, "⏳ ")
	end
end

-- One compact row (see the header).
local function jobRow(parent: Instance, host: any, parts: Parts, offer: any, order: number)
	local onDuty = type(host.job()) == "table"
	local label = parts.why(offer)
	local blocked = JobPick.blocked(offer, onDuty)
	local shut = label ~= nil and not (onDuty and offer.queue == true)
	local spec = if type(offer.specialOrder) == "table" then offer.specialOrder else nil
	local danger, level = JobPick.danger(offer)
	local made = CardKit.row(parent, {
		name = "JobRow",
		order = order,
		decorate = function(row)
			SpecialOrderUi.frame(row, offer) -- 6.14: a golden or a regular's order in its colours
		end,
		rest = if spec then SpecialOrderUi.faceOf(spec) else nil,
		accent = if spec then SpecialOrderUi.colorOf(spec) else DANGER[level],
		picture = picture(offer),
		shut = shut,
		overlay = JobPick.medal(RegularsApp.counts(), offer),
		tag = danger,
		tagColor = if shut then C.dim else DANGER[level],
		title = nameOf(offer),
		facts = JobPick.facts(offer),
		value = Ui.money(tonumber(offer.pay) or 0),
		valueColor = if spec and spec.kind == "golden" then C.gold else C.money,
		action = "+",
		lock = if blocked then (JobPick.lockShort(offer) or "⏸") else nil,
		onAction = function()
			parts.act(offer)
		end,
		onOpen = function()
			goTo(host, "job", tonumber(offer.index))
		end,
	})
	made.row:SetAttribute("Index", offer.index)
end

-- The back button of a sub-view.
local function back(list: Instance, look: any, host: any, draw: (list: Instance, order: number) -> ())
	CardKit.details(list, look, { back = "‹ JOBS", name = "BackToJobs", order = 1, onBack = function()
		goTo(host, nil)
	end, draw = draw })
end

-- The JOBS app (client/PhoneApps.luau board draws it). `wide`: the hero and the rows side by side.
function JobsView.draw(list: Instance, look: any, host: any, wide: boolean, parts: Parts, fullBoard: string)
	local offers, info = host.board()
	local job = host.job()
	local onDuty = type(job) == "table"
	local queue = host.queue()
	local queued = if type(queue) == "table" and type(queue.list) == "table" then #queue.list else 0
	if JobsView.view == "run" and not onDuty or JobsView.view == "next" and queued == 0 then
		JobsView.home() -- (the run ended, the queue emptied)
	end
	local order = topBar(list, look, host, wide)
	if JobsView.view == "run" then
		back(list, look, host, function(into)
			parts.run(into, 1)
		end)
		return
	elseif JobsView.view == "next" then
		back(list, look, host, function(into)
			parts.nextUp(into, 1)
		end)
		return
	elseif JobsView.view == "job" then
		local offer = findOffer(offers, JobsView.detail)
		if offer then
			back(list, look, host, function(into, at)
				parts.card(into, offer, at)
			end)
			return
		end
		JobsView.home() -- (it was taken or left the board)
	end
	if offers == nil then
		look.emptyState(list, "📋", "Calling the dispatcher...", "The board comes in a moment.", order + 1)
		look.button(list, fullBoard, "quiet", order + 2, host.fullBoard)
		return
	end
	local hero, kind = JobPick.hero(offers, onDuty, workspace:GetServerTimeNow())
	local rows = JobPick.rows(offers, hero, onDuty)
	local footNote = if type(info) == "table" and type(info.footNote) == "string" then info.footNote else nil
	if hero == nil and #rows == 0 then
		look.emptyState(list, "📋", "No jobs right now", footNote or "New ones come soon.", order + 1)
		look.button(list, fullBoard, "quiet", order + 2, host.fullBoard)
		return
	end
	local side = wide and hero ~= nil
	local heroH = CardKit.Layout.heroHeight(host.room())
	local _, left, right = CardKit.columns(list, { name = "JobsView", order = order + 1, side = side, hero = hero ~= nil and kind ~= nil, heroHeight = heroH })
	if hero and kind then
		heroCard(left, host, parts, hero, kind, heroH)
	end
	-- "N MORE JOBS" and ADD ALL · $X (the server's plan: into the run, then NEXT UP)
	local plan = if type(info) == "table" and type(info.addAll) == "table" then info.addAll else nil
	local _, _, all = CardKit.sectionHeader(right, {
		name = "MoreHead",
		label = "More",
		text = JobPick.more(#rows, hero ~= nil),
		order = 0,
		chip = if plan and (tonumber(plan.count) or 0) > 0 then { name = "AddAll", text = `ADD ALL · {Ui.money(tonumber(plan.total) or 0)}`, order = 1 } else nil,
	})
	if plan and all then
		local parts2: { string } = {}
		local started, added, waiting = tonumber(plan.started) or 0, tonumber(plan.added) or 0, tonumber(plan.queued) or 0
		if started > 0 then
			table.insert(parts2, "the first one starts")
		end
		if added > 0 then
			table.insert(parts2, `{added} {if added == 1 then "joins" else "join"} your run`)
		end
		if waiting > 0 then
			table.insert(parts2, `{waiting} wait in NEXT UP`)
		end
		local total = tonumber(plan.count) or 0
		local said = `{total} {if total == 1 then "job" else "jobs"}: {table.concat(parts2, ", ")}.`
		all:SetAttribute("Plan", said)
		all.Activated:Connect(function()
			click()
			Net.get("JobQueue"):FireServer("addAll")
			host.notify(said)
		end)
	end
	for index, offer in rows do
		local ok, err = pcall(function()
			jobRow(right, host, parts, offer, index)
		end)
		if not ok then
			warn(`[JobsView] a row failed: {err}`)
		end
	end
	if footNote then
		look.meta(right, footNote, #rows + 1, K.secondary).Name = "FootNote"
	end
	look.button(right, fullBoard, "quiet", #rows + 2, host.fullBoard).Name = "FullBoard"
end

return JobsView
