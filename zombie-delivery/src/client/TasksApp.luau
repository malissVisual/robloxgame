--!strict
-- 6.12, the phone's TASKS app (MORE → TASKS; client/Phone.luau draws it in its centred popup with the phone's own kit,
-- OrdersUi.Kit, design/phone-ui/): the three daily tasks and the weekly one as cards (the title, a thin progress bar,
-- "3 / 5" and the reward, a red CLAIM once it is done, ✓ CLAIMED after), the card of the bonus for every daily done,
-- and how long until the tasks are new (00:00 UTC; the weekly's on Monday 00:00 UTC). The CLAIM buttons are the
-- popup's actions, so a gamepad lands on the first one (PhonePopup.focus) and B / ESC close it like every app.
-- The server decides everything (server/Tasks.luau, shared/Tasks.luau): this shows its state and asks through the
-- Tasks remote: ("open") when the app needs the state, ("claim", slot) on CLAIM. A task finished brings a toast and a
-- sound, a claim paid the money's sound; TasksApp.ready (the rewards waiting) feeds the phone's badges (TASKS, MORE)
-- and its unread dot (Phone: refreshBadges, Phone.onUnread → Hud.setPhoneUnread).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local OrdersUi = require(script.Parent.OrdersUi)

local K = Theme.Contract
local TasksApp = {}

-- Set by Phone.start.
TasksApp.notify = nil :: ((string) -> ())? -- a toast (Phone.notify: Hud.toast)
TasksApp.changed = nil :: (() -> ())? -- the state changed: the phone's badges, the app if it shows

-- 6.12: the sounds (client/Sounds.luau names). The sounds helper's "task_done" will take DONE's place.
local DONE_SOUND = "level_up"
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

-- A thin bar (share 0 … 1) in a card.
local function bar(parent: Instance, share: number, done: boolean, order: number)
	local holder = Ui.make("Frame", { Name = "Progress", Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local back, fill = P.bar(holder, UDim2.new(1, 0, 0, 4), if done then K.good else K.red)
	back.Position = UDim2.fromOffset(0, 3)
	fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
end

-- One task's card: the title, the bar, "3 / 5" and the reward, CLAIM (done) or ✓ CLAIMED.
local function card(list: Instance, task: any, order: number, look: OrdersUi.Kit)
	local target = math.max(1, tonumber(task.target) or 1)
	local have = math.clamp(tonumber(task.progress) or 0, 0, target)
	local done, claimed = task.done == true, task.claimed == true
	local b = look.block(list, order, done and not claimed)
	b.Parent.Name = `Task_{task.slot}`
	look.text(b, tostring(task.title or "Task"), UDim2.new(1, 0, 0, 0), {
		Name = "Title",
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Font = Theme.HeadingFont,
		TextSize = 15,
		TextColor3 = if claimed then K.secondary else K.text,
	})
	bar(b, have / target, done, 2)
	local status = if claimed then "✓ CLAIMED" elseif done then "DONE" else `{amount(have, task.unit)} / {amount(target, task.unit)}`
	local _, statusLabel, reward = look.row2(b, status, `{Ui.money(tonumber(task.money) or 0)} · {tonumber(task.xp) or 0} XP`, 3, true)
	statusLabel.Name = "Status"
	statusLabel.TextColor3 = if done then K.good else K.secondary
	reward.TextColor3 = if claimed then K.secondary else K.text
	if done and not claimed then
		local slot = task.slot
		look.button(b, "CLAIM", "main", 4, function()
			claim(slot)
		end).Name = `Claim_{slot}`
	end
end

-- The bonus for every daily done: how many are done, its reward, CLAIM BONUS.
local function bonusCard(list: Instance, order: number, look: OrdersUi.Kit)
	local bonus = if type(view.bonus) == "table" then view.bonus else {}
	local daily = if type(view.daily) == "table" then view.daily else {}
	local doneCount = 0
	for _, task in daily do
		if type(task) == "table" and task.done == true then
			doneCount += 1
		end
	end
	local ready, claimed = bonus.done == true and bonus.claimed ~= true, bonus.claimed == true
	local b = look.block(list, order, ready)
	b.Parent.Name = "Task_bonus"
	look.caps(b, "BONUS · EVERY DAILY DONE", 1, if claimed then K.secondary else K.text)
	bar(b, if #daily > 0 then doneCount / #daily else 0, bonus.done == true, 2)
	local status = if claimed then "✓ CLAIMED" else `{doneCount} / {#daily} done`
	local _, statusLabel = look.row2(b, status, `{Ui.money(tonumber(bonus.money) or 0)} · {tonumber(bonus.xp) or 0} XP`, 3, true)
	statusLabel.Name = "Status"
	statusLabel.TextColor3 = if bonus.done == true then K.good else K.secondary
	if ready then
		look.button(b, "CLAIM BONUS", "main", 4, function()
			claim("bonus")
		end).Name = "Claim_bonus"
	end
end

-- The app in the phone's popup (`list`, its scrolling body).
function TasksApp.draw(list: Instance, look: OrdersUi.Kit, _wide: boolean?)
	clocks = {}
	if type(view) ~= "table" then
		ask()
		look.emptyState(list, "📋", "Calling dispatch...", "Your tasks come in a moment.", 1)
		return
	end
	local now = workspace:GetServerTimeNow()
	look.section(list, "Daily tasks", 1)
	local dayClock = look.meta(list, `New tasks in {left((tonumber(view.dayEnds) or now) - now)} · at 00:00 UTC`, 2)
	dayClock.Name = "DayClock"
	clocks.day = dayClock
	local order = 2
	for _, task in (if type(view.daily) == "table" then view.daily else {}) :: { any } do
		if type(task) == "table" then
			order += 1
			card(list, task, order, look)
		end
	end
	order += 1
	bonusCard(list, order, look)
	order += 1
	look.section(list, "Weekly task", order)
	order += 1
	local weekClock = look.meta(list, `New in {left((tonumber(view.weekEnds) or now) - now)} · Monday 00:00 UTC`, order)
	weekClock.Name = "WeekClock"
	clocks.week = weekClock
	if type(view.weekly) == "table" then
		order += 1
		card(list, view.weekly, order, look)
	end
	order += 1
	look.meta(list, "Deliveries, throws, rides and the night all count. A task done and not claimed is paid at the reset.", order)
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
		day.Text = `New tasks in {left(dayEnds - now)} · at 00:00 UTC`
	end
	if week and week.Parent then
		week.Text = `New in {left(weekEnds - now)} · Monday 00:00 UTC`
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
		tell(`{if data.weekly == true then "WEEKLY TASK" else "TASK"} DONE: {data.title or "a task"} · claim {Ui.money(tonumber(data.money) or 0)} in your phone (MORE → TASKS)`)
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
