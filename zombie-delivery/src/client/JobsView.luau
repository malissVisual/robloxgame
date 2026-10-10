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

local K = Theme.Contract
local TUNE = Config.JobsView
local JobsView = {}

-- What PhoneApps lends the view: the old full card, YOUR RUN, NEXT UP, a job's one action and its lock.
export type Parts = {
	card: (parent: Instance, offer: any, order: number) -> (),
	run: (list: Instance, order: number) -> number,
	nextUp: (list: Instance, order: number) -> number,
	act: (offer: any) -> (),
	why: (offer: any) -> (string?, string?),
}

local GOLD = Color3.fromRGB(242, 201, 76) -- the golden order's pay, ribbon and button
local GOLD_INK = Color3.fromRGB(42, 30, 5)
local GREEN = Color3.fromRGB(111, 227, 138) -- the pay
local DIM = Color3.fromRGB(125, 131, 139) -- a locked row's pay
local FAINT = Color3.fromRGB(142, 148, 156) -- a row's facts
local SHADE = Color3.fromRGB(14, 13, 11) -- the hero's shade under its words
local GREY = Color3.fromRGB(110, 110, 110) -- a locked picture
local RUN_FACE, RUN_INK = Color3.fromRGB(42, 20, 22), Color3.fromRGB(255, 138, 132)
local RUSH_FACE, RUSH_INK = Color3.fromRGB(58, 42, 18), Color3.fromRGB(245, 183, 72)
local DANGER: { [number]: Color3 } = {
	[0] = Color3.fromRGB(126, 196, 120), -- on foot, by bike
	[1] = Color3.fromRGB(126, 196, 120),
	[2] = Color3.fromRGB(228, 170, 82),
	[3] = Color3.fromRGB(229, 83, 75),
	[4] = Color3.fromRGB(180, 108, 240),
}

-- The sub-view: nil the list, "run" YOUR RUN, "next" NEXT UP, "job" a job's details (JobsView.detail: its index).
JobsView.view = nil :: string?
JobsView.detail = nil :: number?

-- Back to the list (Phone: JOBS opens on it).
function JobsView.home()
	JobsView.view = nil
	JobsView.detail = nil
end

local function click()
	local sound = Ui.onClick
	if sound then
		sound()
	end
end

local function goTo(host: any, view: string?, detail: number?)
	JobsView.view = view
	JobsView.detail = detail
	host.redraw()
end

-- A small rounded chip button (the top bar's, ADD ALL).
local function chip(parent: Instance, look: any, name: string, value: string, face: Color3, ink: Color3, order: number, room: string?): any
	local made = Ui.make("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(look.width(room or value, 11, Theme.HeadingFont) + 22, TUNE.Chip),
		BackgroundColor3 = face,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = value,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = ink,
		LayoutOrder = order,
	}, parent)
	Ui.corner(made, TUNE.Chip // 2)
	return made
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
		local run = chip(chips, look, "RunChip", JobPick.runChip(math.max(1, #lines), Ui.money(total), not wide), RUN_FACE, RUN_INK, 1)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = RUN_INK, Thickness = 1, Transparency = if JobsView.view == "run" then 0 else 0.7 }, run)
		run.Activated:Connect(function()
			click()
			goTo(host, if JobsView.view == "run" then nil else "run")
		end)
		width += run.Size.X.Offset + 8
	end
	if queued > 0 then
		local nextUp = chip(chips, look, "NextChip", JobPick.nextChip(queued), K.raised, K.text, 2)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.text, Thickness = 1, Transparency = if JobsView.view == "next" then 0 else 0.85 }, nextUp)
		nextUp.Activated:Connect(function()
			click()
			goTo(host, if JobsView.view == "next" then nil else "next")
		end)
		width += nextUp.Size.X.Offset + 8
	end
	-- 6.15's rush hour (the workspace attributes server/LiveEvents.luau keeps): its chip at the right, its clock ticking.
	local id = workspace:GetAttribute(LiveEvents.Attr.Id)
	local prefix = JobPick.rushPrefix(if type(id) == "string" then id else nil)
	local rush: any = nil
	if prefix then
		rush = chip(chips, look, "RushChip", prefix, RUSH_FACE, RUSH_INK, 3, prefix .. "0:00")
		rush.Selectable = false
		rush.Active = false
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

-- The picture of a job filling `parent` (greyed when shut), or its emoji on charcoal while not uploaded.
local function picture(parent: Instance, offer: any, shut: boolean, emojiSize: number, z: number)
	local image, _, emoji = JobThumbs.forJob(offer)
	if image then
		Ui.make("ImageLabel", {
			Name = "Picture",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = K.charcoal,
			BorderSizePixel = 0,
			Image = image,
			ImageColor3 = if shut then GREY else Color3.new(1, 1, 1),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = z,
		}, parent)
	else
		Ui.label(parent, emoji or "📦", UDim2.fromScale(1, 1), {
			Name = "Emoji",
			BackgroundColor3 = K.charcoal,
			BackgroundTransparency = 0,
			TextSize = emojiSize,
			TextTransparency = if shut then 0.5 else 0,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z,
		})
	end
end

local function nameOf(offer: any): string
	local _, name = JobThumbs.forJob(offer)
	return string.upper(name or offer.cargo or "Job")
end

-- The hero card (see the header), `height` px tall.
local function heroCard(parent: Instance, look: any, host: any, parts: Parts, offer: any, kind: string, height: number)
	local onDuty = type(host.job()) == "table"
	local spec = if type(offer.specialOrder) == "table" then offer.specialOrder else nil
	local label = parts.why(offer)
	local shut = JobPick.blocked(offer, onDuty) -- (locked, or during a run neither + ADD nor + QUEUE)
	local stuck = if shut then (label or (if type(offer.queueButton) == "string" then offer.queueButton elseif type(offer.orderButton) == "string" then offer.orderButton else "FINISH YOUR RUN")) else nil
	local golden = kind == "golden"
	local accent = if spec then SpecialOrderUi.colorOf(spec) else K.line
	local card = Ui.make("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = if spec then SpecialOrderUi.faceOf(spec) else K.row,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = 1,
	}, parent)
	Ui.corner(card, 12)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if golden then GOLD else accent, Thickness = if spec then 2 else 1, Transparency = if spec then 0 else 0.75 }, card)
	card:SetAttribute("Hero", kind)
	card:SetAttribute("Index", offer.index)
	if spec then
		card:SetAttribute("SpecialOrder", spec.kind)
	end
	picture(card, offer, shut, 72, 1)
	local function details()
		click()
		goTo(host, "job", tonumber(offer.index))
	end
	-- the words at the bottom over a shade: the name and the danger, the pay, the facts, the button
	local payText = Ui.money(tonumber(offer.pay) or 0)
	local paySize = if height >= 260 then 52 else 42
	local infoH = 16 + (paySize + 2) + 18 + 4 + 44 + 4 * 4 -- (the five lines and the list's gaps)
	Ui.make("Frame", { Name = "Fade", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -(infoH + 28 + 40)), BackgroundColor3 = SHADE, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 2 }, card)
	Ui.make("Frame", { Name = "Shade", Size = UDim2.new(1, 0, 0, infoH + 28), Position = UDim2.new(0, 0, 1, -(infoH + 28)), BackgroundColor3 = SHADE, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 2 }, card)
	local cover = Ui.make("TextButton", { Name = "Open", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = false, ZIndex = 3, LayoutOrder = 9 }, card)
	cover.Activated:Connect(details)
	local info = Ui.make("Frame", { Name = "Info", Size = UDim2.new(1, -32, 0, infoH), Position = UDim2.new(0, 16, 1, -14), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1, ZIndex = 4, LayoutOrder = 0 }, card)
	Ui.list(info, true, 4)
	local head = Ui.make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 1 }, info)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, head)
	Ui.label(head, `{nameOf(offer)}  ·`, UDim2.fromOffset(0, 16), { Name = "Business", AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = Color3.fromRGB(230, 220, 192), TextWrapped = false, LayoutOrder = 1 })
	local danger, level = JobPick.danger(offer)
	Ui.label(head, danger, UDim2.fromOffset(0, 16), { Name = "Danger", AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = DANGER[level], TextWrapped = false, LayoutOrder = 2 })
	Ui.label(info, payText, UDim2.new(1, 0, 0, paySize + 2), {
		Name = "Pay",
		Font = Theme.DisplayFont,
		TextSize = paySize,
		TextColor3 = if shut then DIM elseif golden then GOLD else GREEN,
		TextWrapped = false,
		LayoutOrder = 2,
	})
	Ui.label(info, table.concat(JobPick.heroFacts(offer), "    "), UDim2.new(1, 0, 0, 18), { Name = "Facts", Font = Theme.HeadingFont, TextSize = 14, TextColor3 = K.text, TextWrapped = false, LayoutOrder = 3 })
	Ui.make("Frame", { Name = "Gap", Size = UDim2.new(1, 0, 0, 4), BackgroundTransparency = 1, LayoutOrder = 4 }, info)
	local take = Ui.make("TextButton", {
		Name = "Take",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = if shut then K.raised elseif golden then GOLD else K.red,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = stuck or JobPick.button(offer, onDuty),
		Font = Theme.HeadingFont,
		TextSize = 18,
		TextColor3 = if shut then K.secondary elseif golden then GOLD_INK else Color3.new(1, 1, 1),
		LayoutOrder = 5,
	}, info)
	Ui.corner(take, 8)
	take.Activated:Connect(function()
		click()
		parts.act(offer)
	end)
	-- on top: the ribbon and the countdown of a special order (else a regular's medal), the ⓘ
	local ribbon = JobPick.ribbon(offer)
	if ribbon then
		local tag = Ui.label(card, ribbon, UDim2.fromOffset(look.width(ribbon, 12, Theme.HeadingFont) + 22, 24), {
			Name = "Ribbon",
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = GOLD_INK,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		Ui.corner(tag, 12)
		local timer = Ui.label(card, "", UDim2.fromOffset(70, 24), {
			Name = "Countdown",
			Position = UDim2.new(1, -10, 0, 10),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.3,
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextColor3 = accent,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		Ui.corner(timer, 12)
		SpecialOrderUi.countdown(timer, spec and spec.expiresAt, "⏳ ")
	else
		local medal = JobPick.medal(RegularsApp.counts(), offer)
		if medal then
			Ui.label(card, medal, UDim2.fromOffset(28, 28), { Name = "Medal", Position = UDim2.new(1, -46, 0, 8), AnchorPoint = Vector2.new(1, 0), TextSize = 22, TextWrapped = false, ZIndex = 4 })
		end
	end
	local more = Ui.make("TextButton", {
		Name = "Details",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -10, 0, if ribbon then 40 else 10),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "ⓘ",
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.text,
		ZIndex = 5,
		LayoutOrder = 8,
	}, card)
	Ui.corner(more, 14)
	more.Activated:Connect(details)
end

-- One compact row (see the header).
local function jobRow(parent: Instance, look: any, host: any, parts: Parts, offer: any, order: number)
	local onDuty = type(host.job()) == "table"
	local label = parts.why(offer)
	local blocked = JobPick.blocked(offer, onDuty)
	local shut = label ~= nil and not (onDuty and offer.queue == true)
	local spec = if type(offer.specialOrder) == "table" then offer.specialOrder else nil
	local rowH = TUNE.Row
	local row = Ui.make("TextButton", {
		Name = "JobRow",
		Size = UDim2.new(1, 0, 0, rowH),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		LayoutOrder = order,
	}, parent)
	row:SetAttribute("Index", offer.index)
	Ui.corner(row, 10)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.8 }, row)
	SpecialOrderUi.frame(row, offer) -- 6.14: a golden or a regular's order in its colours
	local danger, level = JobPick.danger(offer)
	Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = if spec then SpecialOrderUi.colorOf(spec) else DANGER[level], BorderSizePixel = 0, ZIndex = 3 }, row)
	local thumb = Ui.make("Frame", { Name = "Thumb", Size = UDim2.new(0, TUNE.Thumb, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true }, row)
	picture(thumb, offer, shut, 24, 1)
	local medal = JobPick.medal(RegularsApp.counts(), offer)
	if medal then
		Ui.label(thumb, medal, UDim2.fromOffset(18, 18), { Name = "Medal", Position = UDim2.new(1, -2, 0, 2), AnchorPoint = Vector2.new(1, 0), TextSize = 14, TextWrapped = false, ZIndex = 2 })
	end
	local x = TUNE.Thumb + 10
	Ui.label(row, danger, UDim2.new(0, 44, 1, 0), { Name = "Danger", Position = UDim2.fromOffset(x, 0), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = if shut then DIM else DANGER[level], TextWrapped = false })
	-- the action at the right: "+" (ACCEPT, + ADD or + QUEUE), else the lock's short words
	local lock = if blocked then (JobPick.lockShort(offer) or "⏸") else nil
	local addW = if lock then math.max(TUNE.Add, look.width(lock, 11, Theme.HeadingFont) + 14) else TUNE.Add
	local add = Ui.make("TextButton", {
		Name = "Add",
		Size = UDim2.fromOffset(addW, TUNE.Add),
		Position = UDim2.new(1, -6, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = if lock then K.raised else K.red,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = lock or "+",
		Font = Theme.HeadingFont,
		TextSize = if lock then 11 else 24,
		TextColor3 = if lock then K.secondary else Color3.new(1, 1, 1),
		ZIndex = 2,
	}, row)
	Ui.corner(add, 9)
	add.Activated:Connect(function()
		click()
		parts.act(offer)
	end)
	local payText = Ui.money(tonumber(offer.pay) or 0)
	local payW = look.width(payText, 20, Theme.HeadingFont) + 4
	Ui.label(row, payText, UDim2.new(0, payW, 1, 0), {
		Name = "Pay",
		Position = UDim2.new(1, -(addW + 14), 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 20,
		TextColor3 = if shut then DIM elseif spec and spec.kind == "golden" then GOLD else GREEN,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local nameX = x + 44
	local nameW = -(nameX + addW + payW + 24)
	Ui.label(row, nameOf(offer), UDim2.new(1, nameW, 0, 18), { Name = "Business", Position = UDim2.fromOffset(nameX, 8), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(row, JobPick.facts(offer), UDim2.new(1, nameW, 0, 16), { Name = "Facts", Position = UDim2.fromOffset(nameX, 27), TextSize = 11, TextColor3 = FAINT, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local function lit(on: boolean)
		row.BackgroundColor3 = if on then K.raised elseif spec then SpecialOrderUi.faceOf(spec) else K.row
	end
	row.MouseEnter:Connect(function()
		lit(true)
	end)
	row.MouseLeave:Connect(function()
		lit(false)
	end)
	row.Activated:Connect(function()
		click()
		goTo(host, "job", tonumber(offer.index))
	end)
end

-- The back button of a sub-view.
local function back(list: Instance, look: any, host: any)
	look.button(list, "‹ JOBS", "quiet", 1, function()
		goTo(host, nil)
	end).Name = "BackToJobs"
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
		back(list, look, host)
		parts.run(list, 1)
		return
	elseif JobsView.view == "next" then
		back(list, look, host)
		parts.nextUp(list, 1)
		return
	elseif JobsView.view == "job" then
		local offer = findOffer(offers, JobsView.detail)
		if offer then
			back(list, look, host)
			parts.card(list, offer, 2)
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
	local holder = Ui.make("Frame", { Name = "JobsView", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order + 1 }, list)
	local side = wide and hero ~= nil
	Ui.make("UIListLayout", {
		FillDirection = if side then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	local heroH = math.clamp(math.floor(host.room()), TUNE.HeroMin, TUNE.HeroMax)
	local share = if side then TUNE.HeroShare else 1
	if hero and kind then
		local left = Ui.make("Frame", { Name = "Left", Size = UDim2.new(share, if side then -5 else 0, 0, heroH), BackgroundTransparency = 1, LayoutOrder = 1 }, holder)
		heroCard(left, look, host, parts, hero, kind, heroH)
	end
	local right = Ui.make("Frame", { Name = "Right", Size = UDim2.new(if side then 1 - share else 1, if side then -5 else 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, holder)
	Ui.list(right, true, 6)
	-- "N MORE JOBS" and ADD ALL · $X (the server's plan: into the run, then NEXT UP)
	local head = Ui.make("Frame", { Name = "MoreHead", Size = UDim2.new(1, 0, 0, TUNE.Chip), BackgroundTransparency = 1, LayoutOrder = 0 }, right)
	Ui.label(head, JobPick.more(#rows, hero ~= nil), UDim2.new(1, -150, 1, 0), { Name = "More", Font = Theme.HeadingFont, TextSize = 11, TextColor3 = K.secondary, TextWrapped = false })
	local plan = if type(info) == "table" and type(info.addAll) == "table" then info.addAll else nil
	if plan and (tonumber(plan.count) or 0) > 0 then
		local all = chip(head, look, "AddAll", `ADD ALL · {Ui.money(tonumber(plan.total) or 0)}`, K.raised, K.text, 1)
		all.AnchorPoint = Vector2.new(1, 0)
		all.Position = UDim2.fromScale(1, 0)
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
			jobRow(right, look, host, parts, offer, index)
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
