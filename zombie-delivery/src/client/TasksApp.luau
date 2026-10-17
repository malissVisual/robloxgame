--!strict
-- 6.12, the phone's TASKS app (6.12.5: on the phone's home, a MAIN tile; client/Phone.luau draws it in its centred popup with the phone's own kit,
-- OrdersUi.Kit, design/phone-ui/): the three daily tasks and the weekly one as cards (the title, a thin progress bar,
-- "3 / 5" and the reward, a red CLAIM once it is done, ✓ CLAIMED after), the card of the bonus for every daily done,
-- and how long until the tasks are new (00:00 UTC; the weekly's on Monday 00:00 UTC). The CLAIM buttons are the
-- popup's actions, so a gamepad lands on the first one (PhonePopup.focus) and B / ESC close it like every app.
-- The server decides everything (server/Tasks.luau, shared/Tasks.luau): this shows its state and asks through the
-- Tasks remote: ("open") when the app needs the state, ("claim", slot) on CLAIM. A task finished brings a toast and a
-- sound, a claim paid the money's sound; TasksApp.ready (the rewards waiting) feeds the phone's badges (TASKS, MORE)
-- and its unread dot (Phone: refreshBadges, Phone.onUnread → Hud.setPhoneUnread).
-- 6.18 (the UI kit, client/CardKit.luau; design/ui-kit/README.md): TASKS in the JOBS look. The chips (in the popup's
-- header right of TASKS when they fit, else heading the body; CardKit.toHeader) say when
-- the tasks are new ("⏱ DAILY · 3 h 2 min", "📅 WEEKLY · 2 d 1 h") and how many wait ("1 TO CLAIM"). The HERO is the
-- task to claim (else the one closest to done): its kind on the ribbon (DAILY / BONUS / WEEKLY), its progress on the
-- corner, its name, the money big, "+110 XP", its bar and ONE button: CLAIM · $180 (green), else a grey "2 / 5 · KEEP
-- GOING". The other tasks are the kit's rows (Task_<slot>): the emoji, the name, "0 / 1 · +80 XP" (✓ CLAIMED), the
-- money big (dim once claimed), a CLAIM word on a done one, the bar at the row's foot. The hero sits beside the rows
-- in a wide popup (CardKit.columns), its height the popup's room. CLAIM is still Claim_<slot> (the gamepad's first).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local OrdersUi = require(script.Parent.OrdersUi)
local CardKit = require(script.Parent.CardKit) -- 6.18: the UI kit

local K = Theme.Contract
local TasksApp = {}

-- Set by Phone.start.
TasksApp.notify = nil :: ((string) -> ())? -- a toast (Phone.notify: Hud.toast)
TasksApp.changed = nil :: (() -> ())? -- the state changed: the phone's badges, the app if it shows

-- 6.12: the sounds (client/Sounds.luau names; sfx3's "task_done", with its stand-in until sfx3 is uploaded).
local DONE_SOUND = "task_done"
local CLAIM_SOUND = "cash"

local view: any = nil -- the server's last state (shared/Tasks.luau Tasks.view)
local askedAt = -1
local clocks: { day: any?, week: any? } = {} -- the countdown labels of the app that shows
local started = false

local function ask()
	local now = os.clock()
	if askedAt >= 0 and now - askedAt < 2 then
		return
	end
	askedAt = now
	Net.get("Tasks"):FireServer("open")
end

local function sound(name: string)
	pcall(function()
		local play = (require(script.Parent.Sounds) :: any).play
		if play then
			play(name)
		end
	end)
end

local function tell(text: string)
	local notify = TasksApp.notify
	if notify then
		notify(text)
	end
end

-- 5 h 12 min, 3 d 4 h, 12 min, 40 s
local function left(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 86400 then
		return `{s // 86400} d {(s % 86400) // 3600} h`
	elseif s >= 3600 then
		return `{s // 3600} h {(s % 3600) // 60} min`
	elseif s >= 60 then
		return `{s // 60} min`
	end
	return `{s} s`
end

local function amount(value: number, unit: string?): string
	if unit == "$" then
		return Ui.money(value)
	elseif unit == "s" then
		return `{value} s`
	end
	return tostring(value)
end

-- How many rewards wait to be claimed (the phone's badges and dot).
function TasksApp.ready(): number
	return if type(view) == "table" and type(view.ready) == "number" then view.ready else 0
end

-- 6.12.5: the phone home's TASKS tile: today's dailies done, how many there are, the rewards waiting.
function TasksApp.summary(): (number, number, number)
	if type(view) ~= "table" or type(view.daily) ~= "table" then
		return 0, 0, 0
	end
	local done, total = 0, 0
	for _, task in view.daily do
		if type(task) == "table" then
			total += 1
			if task.done == true then
				done += 1
			end
		end
	end
	return done, total, TasksApp.ready()
end

-- CLAIM: asks the server (a second press of the same CLAIM while its answer is on the way is not sent).
local pressedAt: { [any]: number } = {}
local function claim(slot: any)
	local now = os.clock()
	if pressedAt[slot] and now - pressedAt[slot] < 1.5 then
		return
	end
	pressedAt[slot] = now
	Net.get("Tasks"):FireServer("claim", slot)
end

-- 6.18: the chips' words for the clocks (the ticker keeps them live).
local function dayWords(seconds: number): string
	return `⏱ DAILY · {left(seconds)}`
end
local function weekWords(seconds: number): string
	return `📅 WEEKLY · {left(seconds)}`
end

-- 6.18: every task as one shape (the dailies, the bonus for every daily done, the weekly), in the order they show.
type Entry = { slot: any, kind: string, title: string, have: number, target: number, unit: string?, money: number, xp: number, done: boolean, claimed: boolean }
local KINDS: { [string]: { ribbon: string, emoji: string } } = {
	daily = { ribbon = "DAILY TASK", emoji = "📋" },
	bonus = { ribbon = "BONUS · EVERY DAILY", emoji = "⭐" },
	weekly = { ribbon = "WEEKLY TASK", emoji = "🏆" },
}

local function entries(): { Entry }
	local out: { Entry } = {}
	local daily = if type(view.daily) == "table" then view.daily else {}
	local doneCount = 0
	for _, task in daily :: { any } do
		if type(task) == "table" then
			local target = math.max(1, tonumber(task.target) or 1)
			if task.done == true then
				doneCount += 1
			end
			table.insert(out, {
				slot = task.slot,
				kind = "daily",
				title = tostring(task.title or "Task"),
				have = math.clamp(tonumber(task.progress) or 0, 0, target),
				target = target,
				unit = task.unit,
				money = tonumber(task.money) or 0,
				xp = tonumber(task.xp) or 0,
				done = task.done == true,
				claimed = task.claimed == true,
			})
		end
	end
	local bonus = if type(view.bonus) == "table" then view.bonus else {}
	table.insert(out, {
		slot = "bonus",
		kind = "bonus",
		title = "Every daily done",
		have = doneCount,
		target = math.max(1, #daily),
		money = tonumber(bonus.money) or 0,
		xp = tonumber(bonus.xp) or 0,
		done = bonus.done == true,
		claimed = bonus.claimed == true,
	})
	local weekly = view.weekly
	if type(weekly) == "table" then
		local target = math.max(1, tonumber(weekly.target) or 1)
		table.insert(out, {
			slot = weekly.slot or "weekly",
			kind = "weekly",
			title = tostring(weekly.title or "Weekly task"),
			have = math.clamp(tonumber(weekly.progress) or 0, 0, target),
			target = target,
			unit = weekly.unit,
			money = tonumber(weekly.money) or 0,
			xp = tonumber(weekly.xp) or 0,
			done = weekly.done == true,
			claimed = weekly.claimed == true,
		})
	end
	return out
end

-- The hero: the first reward to claim, else the task closest to done (not claimed), else none.
local function heroOf(list: { Entry }): Entry?
	local best: Entry? = nil
	local share = -1
	for _, entry in list do
		if entry.done and not entry.claimed then
			return entry
		end
		if not entry.claimed and entry.have / entry.target > share then
			best, share = entry, entry.have / entry.target
		end
	end
	return best
end

local function progressWords(entry: Entry): string
	return `{amount(entry.have, entry.unit)} / {amount(entry.target, entry.unit)}`
end

-- The hero card (see the header), `height` px tall.
local function heroCard(parent: Instance, entry: Entry, height: number)
	local claimable = entry.done and not entry.claimed
	local kind = KINDS[entry.kind] or KINDS.daily
	local slot = entry.slot
	local made = CardKit.hero(parent, {
		name = `Task_{slot}`,
		height = height,
		stroke = if claimable then K.good else K.line,
		strong = claimable,
		picture = { emoji = kind.emoji },
		title = string.upper(entry.title),
		value = Ui.money(entry.money),
		valueColor = if entry.kind == "weekly" then CardKit.Color.gold else CardKit.Color.money,
		facts = `+{entry.xp} XP`,
		bar = { share = entry.have / entry.target, color = if entry.done then K.good else K.red },
		ribbon = { text = kind.ribbon, face = if claimable then K.good else K.raised, ink = if claimable then CardKit.Color.goldInk else K.text },
		corner = { text = if entry.done then "✓ DONE" else progressWords(entry), ink = if entry.done then K.good else K.text, width = CardKit.width(progressWords(entry), 13, Theme.HeadingFont) + 24 },
		action = if claimable
			then { name = `Claim_{slot}`, text = `CLAIM · {Ui.money(entry.money)}`, kind = "good", onClick = function()
				claim(slot)
			end }
			else { name = "Waiting", text = `{progressWords(entry)} · KEEP GOING`, kind = "shut" },
		onOpen = function() end,
		silent = true,
	})
	made.corner.Name = "Status"
end

-- One task's row (see the header).
local function taskRow(parent: Instance, entry: Entry, order: number)
	local claimable = entry.done and not entry.claimed
	local kind = KINDS[entry.kind] or KINDS.daily
	local slot = entry.slot
	local made = CardKit.row(parent, {
		name = `Task_{slot}`,
		order = order,
		accent = if claimable then K.good elseif entry.claimed then K.line elseif entry.kind == "weekly" then CardKit.Color.gold else K.red,
		picture = { emoji = kind.emoji },
		thumb = Config.UiKit.Icon,
		shut = entry.claimed,
		title = entry.title,
		titleColor = if entry.claimed then K.secondary else K.text,
		facts = if entry.claimed then "✓ CLAIMED" else `{progressWords(entry)} · +{entry.xp} XP`,
		factsColor = if claimable then K.good else nil,
		value = Ui.money(entry.money),
		valueColor = if entry.kind == "weekly" then CardKit.Color.gold else CardKit.Color.money,
		word = if claimable then "CLAIM" else nil,
		actionFace = if claimable then K.good else nil,
		wordInk = CardKit.Color.goldInk,
		onAction = if claimable then function()
			claim(slot)
		end else nil,
		silent = not claimable,
		onOpen = function()
			if claimable then
				claim(slot)
			end
		end,
	})
	if made.action then
		made.action.Name = `Claim_{slot}`
	end
	if not entry.claimed then
		CardKit.rowBar(made, entry.have / entry.target, if entry.done then K.good else K.red)
	end
end

-- The app in the phone's popup (`list`, its scrolling body; `wide`: the hero beside the rows).
function TasksApp.draw(list: Instance, look: OrdersUi.Kit, wide: boolean?)
	clocks = {}
	if type(view) ~= "table" then
		ask()
		look.emptyState(list, "📋", "Calling dispatch...", "Your tasks come in a moment.", 1)
		return
	end
	local now = workspace:GetServerTimeNow()
	-- The chips: the clocks and the rewards waiting.
	local chips = CardKit.chips(list, "Chips", 0)
	clocks.day = CardKit.chip(chips, { name = "DayClock", text = dayWords((tonumber(view.dayEnds) or now) - now), room = "⏱ DAILY · 23 h 59 min", order = 1, static = true })
	clocks.week = CardKit.chip(chips, { name = "WeekClock", text = weekWords((tonumber(view.weekEnds) or now) - now), room = "📅 WEEKLY · 6 d 23 h", order = 2, static = true })
	local ready = TasksApp.ready()
	if ready > 0 then
		CardKit.chip(chips, { name = "ReadyChip", text = `{ready} TO CLAIM`, face = CardKit.Color.goodFace, ink = K.good, order = 3, static = true })
	end
	-- (in the popup's header when they fit, like JOBS' chips; else heading the body, the hero that much shorter)
	local popup = require(script.Parent.PhonePopup)
	local bar, barRoom = popup.bar()
	local taken = CardKit.toHeader(chips, bar, barRoom, list)
	local all = entries()
	local hero = heroOf(all)
	local height = CardKit.Layout.heroHeight(popup.room() - taken)
	local _, left, right = CardKit.columns(list, { name = "TasksView", order = 1, side = wide == true and hero ~= nil, hero = hero ~= nil, heroHeight = height })
	if hero then
		heroCard(left, hero, height)
	end
	local order = 0
	for _, entry in all do
		if entry ~= hero then
			order += 1
			taskRow(right, entry, order)
		end
	end
	look.meta(right, "Deliveries, throws, rides and the night all count. A task done and not claimed is paid at the reset.", order + 1).Name = "FootNote"
end

-- The countdowns (the phone's ticker, twice a second while TASKS shows). Past the reset: the new state is asked for.
function TasksApp.tick()
	if type(view) ~= "table" then
		return
	end
	local now = workspace:GetServerTimeNow()
	local dayEnds, weekEnds = tonumber(view.dayEnds) or now, tonumber(view.weekEnds) or now
	local day, week = clocks.day, clocks.week
	if day and day.Parent then
		day.Text = dayWords(dayEnds - now) -- (6.18: the chip; its width holds the longest clock)
	end
	if week and week.Parent then
		week.Text = weekWords(weekEnds - now)
	end
	if now >= dayEnds or now >= weekEnds then
		ask() -- (the server resets within Config.Tasks.CheckEvery and sends it anyway)
	end
end

local function onEvent(kind: any, data: any)
	if kind == "state" and type(data) == "table" then
		view = data
		local changed = TasksApp.changed
		if changed then
			changed()
		end
	elseif kind == "done" and type(data) == "table" then
		sound(DONE_SOUND)
		tell(`{if data.weekly == true then "WEEKLY TASK" else "TASK"} DONE: {data.title or "a task"} · claim {Ui.money(tonumber(data.money) or 0)} in your phone (TASKS)`)
	elseif kind == "claimed" and type(data) == "table" then
		sound(CLAIM_SOUND)
		tell(`{data.title or "Task"}: +{Ui.money(tonumber(data.money) or 0)} · +{tonumber(data.xp) or 0} XP`)
	end
end

-- Listens to the Tasks remote and asks for the state once (Phone.start).
function TasksApp.start()
	if started then
		return
	end
	started = true
	Net.get("Tasks").OnClientEvent:Connect(onEvent)
	ask()
end

return TasksApp
