--!strict
-- 6.18, the phone's home screen in the UI kit's look (the owner, after 6.17's JOBS: "I need it unified so the phone
-- looks like that"). client/Phone.luau builds the phone and calls this for its home (and MORE's rows); the parts are
-- client/CardKit.luau's, the sizes Config.UiKit's, where everything sits client/PhoneLayout.luau's:
--   * The header: chips for the secondary state: your cash (green; a tap: BANK), your level with a thin XP line (a
--     tap: CAREER) and the shift (amber at night, when jobs pay more).
--   * The HERO card, the most important thing now: NEXT MISSION (client/ReadyCheck.luau tile: the mission big, its
--     chapter and n/N, the readiness chip in red / green / amber, the savings goal and its bar, GET READY / ▶ START;
--     the chapter's picture when there is one) or, during a run, YOUR RUN (the next stop, the pay big in green, the
--     pieces and the distance, the clock, OPEN RUN: ORDERS). A short phone's hero has no button: the card is it.
--   * Then a compact row an app, the same as JOBS' rows: its icon (client/PhoneContract.luau glyph), its name, ONE live
--     line and a round "›": JOBS ("7 jobs · best $1,140" and the best pay big in green, gold for a golden order; "Your
--     run · 2 orders · 3 next" and the run's pay; a live event's "🌕 BLOOD MOON · jobs pay ×2" first), TASKS ("1 to
--     claim · 1/3"), MISSIONS ("2/6 · Code Red", "🔒 Level 4"; their bars), MAP, SHOP, BAG & ITEMS, GARAGE (how you
--     get around), STYLE, MORE. The red badges (counts, NEW, $, !) on the icon's corner.
--   * MESSAGES under them (the unread count, the newest line); MORE's sub-screen is rows too.
-- The rows keep their names (jobsApp, mapApp …: Marge's arrows in client/TutorialUi.luau point at them); the gamepad
-- lands on the hero. Presentation only: every tap opens what it opened before.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local JobPick = require(Shared.JobPick)
local JobQueue = require(Shared.JobQueue)
local JobThumbs = require(Shared.JobThumbs)
local LiveEvents = require(Shared.LiveEvents)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local CardKit = require(script.Parent.CardKit)

local K = Theme.Contract
local C = CardKit.Color
local KIT = Config.UiKit
local PhoneHome = {}

export type AppDef = { id: string, name: string, sub: string, window: boolean?, bar: boolean? }

-- What Phone lends the home: its refs (the labels it fills), the badges by app id, the launch of an app (from the
-- tapped button), the app glyphs and client/ReadyCheck.luau.
export type Home = {
	refs: { [string]: any },
	badges: { [string]: any },
	launch: (id: string, from: GuiObject?) -> (),
	glyph: (face: Instance, id: string, size: number) -> (),
	ready: any,
}

-- The apps' accents (their row's edge): JOBS red (the daily work), TASKS green, MISSIONS amber; the rest quiet.
local ACCENTS: { [string]: Color3 } = { jobs = K.red, tasks = K.good, missions = K.warn }
local QUIET = Color3.fromRGB(58, 64, 72)
local NIGHT_ROOM = "🌙 NIGHT · PAY ×0.0"

-- ── The rows ────────────────────────────────────────────────────────────────

-- An app's compact row (home's and MORE's): `{id}App`, its live line "Sub", its "Badge", a "Progress" bar for TASKS and
-- MISSIONS (refs.bars), the JOBS row's big value (refs.jobsRow).
function PhoneHome.appRow(parent: Instance, def: AppDef, order: number, home: Home): any
	local refs = home.refs
	local cell: any = nil
	local made = CardKit.row(parent, {
		name = `{def.id}App`,
		order = order,
		accent = ACCENTS[def.id] or QUIET,
		picture = {
			glyph = function(slot: Instance, size: number)
				home.glyph(slot, def.id, size)
			end,
		},
		thumb = KIT.Icon,
		emojiSize = 26,
		title = def.name,
		titleColor = K.text,
		facts = def.sub,
		factsColor = K.secondary,
		value = if def.id == "jobs" then "" else nil,
		action = "›",
		badge = true,
		silent = true,
		onOpen = function()
			home.launch(def.id, cell)
		end,
	})
	cell = made.row
	made.title.Name = "Title"
	made.facts.Name = "Sub"
	refs.subs[def.id] = made.facts
	home.badges[def.id] = made.badge
	if def.id == "jobs" then
		refs.jobsRow = made
	end
	if def.bar then
		local x = KIT.Icon + 10
		local holder = Ui.make("Frame", { Name = "Progress", Size = UDim2.new(1, -(x + KIT.Add + 20), 0, 3), Position = UDim2.new(0, x, 1, -7), BackgroundTransparency = 1 }, cell)
		local _, fill = P.bar(holder, UDim2.new(1, 0, 1, 0), K.red)
		fill.Size = UDim2.fromScale(0, 1)
		refs.bars[def.id] = fill
	end
	return cell
end

-- ── The heroes ──────────────────────────────────────────────────────────────

-- The hero pair in refs.heroHolder, `height` px tall (again when the phone's size changes it: PhoneHome.fit):
-- NEXT MISSION (refs.nextTile) and YOUR RUN (refs.runHero, "HomeContract"), one showing.
function PhoneHome.heroes(home: Home, height: number)
	local refs = home.refs
	local holder = refs.heroHolder
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	refs.heroH = height
	holder.Size = UDim2.new(1, 0, 0, height)
	local button = CardKit.Layout.hasButton(height)
	refs.nextTile = home.ready.tile(holder, {
		name = "nextApp",
		height = height,
		button = button,
		onOpen = function()
			home.launch("next", refs.nextTile.card)
		end,
	})
	local run: any = nil
	local function openRun()
		home.launch(if refs.jobOn then "orders" else "board", run.card)
	end
	run = CardKit.hero(holder, {
		name = "HomeContract",
		order = 2,
		height = height,
		button = true,
		silent = true,
		stroke = C.runInk,
		picture = { emoji = "🛵" },
		title = "",
		value = "",
		valueSize = KIT.HomeValue + 8,
		facts = "",
		action = if button then { name = "OpenRun", text = "OPEN RUN ›", height = KIT.HomeButton, textSize = 16, silent = true, onClick = openRun } else nil,
		ribbon = { text = "▶ YOUR RUN", face = C.runFace, ink = C.runInk },
		corner = { text = "", ink = K.text, width = 72 },
		onOpen = openRun,
	})
	run.title.Name = "Stop"
	run.value.Name = "Pay"
	run.facts.Name = "Meta"
	run.card.Visible = false
	refs.runHero = run
	refs.runPicture = nil
	refs.firstTile = refs.nextTile.card
end

-- The phone was fitted again (opened, resized): the hero follows the room it has (PhoneLayout.heroHeight).
function PhoneHome.fit(home: Home, height: number)
	if home.refs.heroHolder and home.refs.heroH ~= height then
		PhoneHome.heroes(home, height)
		PhoneHome.fill(home)
	end
end

-- ── Building ────────────────────────────────────────────────────────────────

-- Home's parts in `parent` (a vertical list): the header (1), the hero (2), the apps (3), MESSAGES (4). Phone puts the
-- quick switch (MY BIKE, CALL CAR, TOW) at 5.
function PhoneHome.build(parent: Instance, apps: { AppDef }, home: Home, heroHeight: number)
	local refs = home.refs
	refs.homeKit = home
	-- the header's chips
	local head = Ui.make("Frame", { Name = "Shift", Size = UDim2.new(1, 0, 0, KIT.Chip), BackgroundTransparency = 1, LayoutOrder = 1 }, parent)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, head)
	local cash: any, level: any = nil, nil
	cash = CardKit.chip(head, { name = "MoneyChip", text = "$0", face = C.goodFace, ink = C.money, order = 1, silent = true, onClick = function()
		home.launch("bank", cash)
	end })
	level = CardKit.chip(head, { name = "LevelChip", text = "LV 1", order = 2, silent = true, onClick = function()
		home.launch("career", level)
	end })
	local xp = Ui.make("Frame", { Name = "Xp", Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -4), BackgroundColor3 = C.white, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, level)
	refs.idXp = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = K.good, BorderSizePixel = 0 }, xp)
	refs.idMoney, refs.idRank = cash, level
	refs.shift = CardKit.chip(head, { name = "ShiftChip", text = "", room = NIGHT_ROOM, order = 3, static = true })
	-- the hero (NEXT MISSION or YOUR RUN)
	refs.heroHolder = Ui.make("Frame", { Name = "HomeHero", Size = UDim2.new(1, 0, 0, heroHeight), BackgroundTransparency = 1, LayoutOrder = 2 }, parent)
	PhoneHome.heroes(home, heroHeight)
	-- the apps
	local list = Ui.make("Frame", { Name = "Apps", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, parent)
	Ui.list(list, true, KIT.Gap)
	for order, def in apps do
		PhoneHome.appRow(list, def, order, home)
	end
	-- MESSAGES: the unread count and the newest line (a tap: MESSAGES)
	local note: any = nil
	note = CardKit.row(parent, {
		name = "MessagesRow",
		order = 4,
		accent = QUIET,
		picture = {
			glyph = function(slot: Instance, size: number)
				home.glyph(slot, "messages", size)
			end,
		},
		thumb = KIT.Icon,
		title = "MESSAGES",
		titleColor = K.text,
		facts = "No new messages",
		factsColor = K.secondary,
		action = "›",
		badge = true,
		silent = true,
		onOpen = function()
			home.launch("messages", note.row)
		end,
	})
	note.badge.Name = "Unread"
	refs.noteFrom, refs.noteText, refs.noteCount, refs.note = note.title, note.facts, note.badge, note.row
end

-- ── Filling ─────────────────────────────────────────────────────────────────

-- The header's chips: the cash, the level (and its XP share), the shift (`night`: amber).
function PhoneHome.header(home: Home, cash: string, level: number, share: number, shift: string, night: boolean)
	local refs = home.refs
	local chips = { refs.idMoney, refs.idRank }
	refs.idMoney.Text = cash
	refs.idRank.Text = `LV {level}`
	for _, chip in chips do
		chip.Size = UDim2.fromOffset(CardKit.width(chip.Text, 11, Theme.HeadingFont) + 22, KIT.Chip)
	end
	refs.idXp.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	refs.shift.Text = shift
	refs.shift.BackgroundColor3 = if night then C.rushFace else K.raised
	refs.shift.TextColor3 = if night then C.rushInk else K.secondary
end

-- The hero: YOUR RUN while you are on one (`summary`: client/PhoneLayout.luau summary), else NEXT MISSION.
function PhoneHome.run(home: Home, summary: any, job: any)
	local refs = home.refs
	local run = refs.runHero
	if not run then
		return
	end
	local active = summary.active == true
	refs.jobOn = active
	run.card.Visible = active
	refs.nextTile.card.Visible = not active
	refs.firstTile = if active then run.card else refs.nextTile.card
	if not active then
		return
	end
	local image, _, emoji = JobThumbs.forJob(job)
	local key = image or emoji or "🛵"
	if refs.runPicture ~= key then
		refs.runPicture = key
		CardKit.repicture(run.card, { image = image, emoji = emoji or "🛵" }, 64)
	end
	run.title.Text = summary.title
	run.value.Text = Ui.money(tonumber(summary.pay) or 0)
	local count = tonumber(summary.count) or 1
	run.facts.Text = `📦 {count} {if count == 1 then "order" else "orders"} · {summary.meta}`
	local left = summary.left
	run.corner.Visible = left ~= nil
	if left then
		run.corner.Text = `⏱ {Ui.clock(left)}`
		run.corner.TextColor3 = if left < 30 then K.red else K.text
	end
end

-- JOBS' row: its line (a paying live event first, then the run and NEXT UP, then "7 jobs · best $X", else the board's
-- words) and its big value (the run's pay, else the best pay: gold for a golden order). `jobs`: refs.jobsState
-- (Phone's refreshBadges: the open orders, the queue, the new runs).
function PhoneHome.jobs(home: Home, job: any, offers: any, now: number)
	local refs = home.refs
	local row, line = refs.jobsRow, refs.subs.jobs
	if not (row and line) then
		return
	end
	local jobs = refs.jobsState or { open = 0, queued = 0, fresh = 0, paused = false }
	local liveId = workspace:GetAttribute(LiveEvents.Attr.Id)
	local live = LiveEvents.workLine(if type(liveId) == "string" then liveId else nil)
	local onDuty = type(job) == "table"
	local count, best, golden = JobPick.summary(offers, onDuty, now)
	local words = JobQueue.jobsLine(jobs.open, jobs.queued, jobs.fresh, jobs.paused)
	if live then
		line.Text = live
		line.TextColor3 = K.warn
	elseif onDuty or jobs.queued > 0 or count == 0 then
		line.Text = words
		line.TextColor3 = K.secondary
	else
		line.Text = `{JobPick.homeLine(count)}{Ui.money(best)}`
		line.TextColor3 = K.secondary
	end
	if onDuty then
		local _, total = JobQueue.runLines(job)
		CardKit.setValue(row, if total > 0 then Ui.money(total) else "", C.money)
	else
		CardKit.setValue(row, if count > 0 then Ui.money(best) else "", if golden then C.gold else C.money)
	end
end

-- TASKS' and MISSIONS' lines and bars (6.12.5's words), the NEXT MISSION hero (client/ReadyCheck.luau).
function PhoneHome.apps(home: Home, info: any, done: number, total: number, ready: number)
	local refs = home.refs
	home.ready.fillTile(refs.nextTile)
	local missionsSub, missionsBar = refs.subs.missions, refs.bars.missions
	if info and missionsSub then
		local finished = info.total > 0 and info.done >= info.total
		missionsSub.Text = if not info.open then `🔒 {info.why or "Locked"}`
			elseif finished then `{info.name} ✓`
			else `{info.done}/{info.total} · {info.name}`
		missionsSub.TextColor3 = if info.open then K.text else K.secondary
		if missionsBar then
			missionsBar.Size = UDim2.fromScale(if info.total > 0 then math.clamp(info.done / info.total, 0, 1) else 0, 1)
		end
	end
	local tasksSub, tasksBar = refs.subs.tasks, refs.bars.tasks
	if tasksSub then
		tasksSub.Text = if total == 0 then "Daily and weekly"
			elseif ready > 0 then `{ready} to claim · {done}/{total}`
			elseif done >= total then "All done today ✓"
			else `{done}/{total} done today`
		tasksSub.TextColor3 = if ready > 0 then K.good else K.secondary
	end
	if tasksBar then
		tasksBar.Size = UDim2.fromScale(if total > 0 then math.clamp(done / total, 0, 1) else 0, 1)
		tasksBar.BackgroundColor3 = if total > 0 and done >= total then K.good else K.red
	end
end

-- Everything again from what refs holds (after the hero was rebuilt): Phone's fillHome does the same each tick.
function PhoneHome.fill(home: Home)
	local fill = home.refs.fillHome
	if fill then
		fill()
	end
end

return PhoneHome
