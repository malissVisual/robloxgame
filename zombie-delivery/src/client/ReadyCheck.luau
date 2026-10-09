--!strict
-- 6.14, get ready for the mission on the client (the owner: "You and a friend do delivery jobs ... it should feel like
-- 'okay, let's go get ready for that mission'. Jobs are the daily work: grind, save up for something, then progress in
-- the mission."). shared/Readiness.luau decides; this module feeds it and shows it:
--   * What it knows: the State remote (Main: ReadyCheck.setState), the Missions remote's state (the progress, the crew:
--     server/Missions.luau sends it on "open" and whenever it changes), the Xp attribute and Marge's tutorial phase
--     (the Tutorial remote). ReadyCheck.current() is the answer, worked out again only when one of them changed.
--   * The phone's home (client/Phone.luau): the wide NEXT MISSION tile (ReadyCheck.tile / fillTile: the chapter and
--     n/N, the mission, "2 of 3 ready" in red or "READY · START" in green, the savings goal's bar) and the WORK tile's
--     goal line (ReadyCheck.workLine: "Earn for the Old Van · $1,160 to go").
--   * The READY CHECK (ReadyCheck.draw, the NEXT MISSION tile's app in the phone's popup): the mission, the checklist
--     (✔ done, ✖ required and missing, ☆ would help) with each row's action (GPS to the shop, INVITE a friend, JOBS to
--     earn, GARAGE to switch cars), the savings goal, START (ready: the MISSIONS window on that mission and its own
--     START, ReadyCheck.onStart: no second way to start a mission), JOBS and MISSIONS.
--   * INVITE (ReadyCheck.invite): Roblox's game invite (SocialService CanSendGameInviteAsync / PromptGameInvite, both in
--     a pcall), else the CREW window (ReadyCheck.onCrew: on the crew board for that mission).
--   * The HUD: the savings line under the cash (client/SavingsLine.luau, mounted by ReadyCheck.start); a one-time toast
--     and a sting when the next mission becomes READY ("Ready for Paper Trail · open MISSIONS (U)"); the job result's
--     "+$85 · $1,160 to go for the Old Van" (ReadyCheck.resultLine, client/Hud.luau). The toast and the line wait
--     through Marge's first day (Readiness `quiet`).
-- 6.14 review: what START needs besides the rows comes in too: the night (the workspace's Night attribute, watched),
-- the mission running, a job of yours (the Job remote, else the Missions state's onJob), a car of yours out and your
-- crew's members near you, your garages (the Missions state: server/Missions.luau asks the server's own answers) and
-- where you stand. The tile and the READY CHECK say Readiness.badge / start (START, CALL CAR, IN PROGRESS, LEADER
-- PICKS, AFTER YOUR RUN); the READY toast waits for a START that can work (by day a night mission is not ready).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Readiness = require(Shared.Readiness)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local Gps = require(script.Parent.Gps)
local OrdersUi = require(script.Parent.OrdersUi)

local K = Theme.Contract
local ReadyCheck = {}

-- Set by Main.
ReadyCheck.notify = nil :: ((text: string) -> ())? -- a toast (Hud.toast)
ReadyCheck.onStart = nil :: ((missionId: string) -> ())? -- START: the MISSIONS window on it and its START (MissionsUi)
ReadyCheck.onMissions = nil :: ((campaignId: string?) -> ())? -- the MISSIONS window on that chapter
ReadyCheck.onCrew = nil :: ((missionId: string?) -> ())? -- INVITE's fallback: the CREW window (MissionsUi.findCrew)
ReadyCheck.toGo = nil :: ((xpLeft: number, level: number) -> string)? -- "8 on-foot runs" (CareerUi.toGo)

type Host = {
	go: (id: string) -> (),
	close: () -> (),
	notify: (text: string) -> (),
}

local player = Players.LocalPlayer
-- Everything in one table (few locals).
local data: { [string]: any } = {
	state = nil, -- the State remote's last state
	missions = nil, -- the Missions remote's last state
	tutorial = nil, -- Marge's phase while her first day runs
	result = nil, -- Readiness.evaluate's last answer
	dirty = true,
	listeners = {},
	announced = {}, -- the missions whose READY toast was shown (once a session)
	previous = nil, -- the last answer's mission and whether it was ready (announce: only a change is news)
	asked = false, -- the Missions state asked for once the save was in (setState)
	view = nil, -- the READY CHECK's live pieces (the goal's money line and bar: tick)
	onJob = nil, -- 6.14 review: a job of yours runs (the Job remote; nil until it said)
}

local ACTION_WORDS: { [string]: string } = { gps = "📍 GPS  ›", invite = "INVITE  ›", jobs = "JOBS  ›", garage = "GARAGE  ›", missions = "MISSIONS  ›" }

-- ── What the client knows ─────────────────────────────────────────────────

local function myXp(): number
	local xp = tonumber(player:GetAttribute("Xp"))
	local state = data.state
	if xp == nil and type(state) == "table" and type(state.xp) == "number" then
		xp = state.xp
	end
	return xp or 0
end

local function tableOf(value: any): any
	return if type(value) == "table" then value else nil
end

-- The input shared/Readiness.luau reads, from the two states, the XP and the tutorial.
function ReadyCheck.input(): Readiness.Input
	local state = tableOf(data.state) or {}
	local missions = tableOf(data.missions) or {}
	local xp = myXp()
	-- (the XP decides, as on the server; before it is known, the Missions state's level)
	local known = tonumber(player:GetAttribute("Xp")) ~= nil or type(state.xp) == "number"
	local level = if known then Levels.levelFor(xp) elseif type(missions.level) == "number" then missions.level else 1
	local night = workspace:GetAttribute("Night")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local at = if root and root:IsA("BasePart") then { x = root.Position.X, z = root.Position.Z } else nil
	return {
		xp = xp,
		level = level,
		money = tonumber(state.money) or 0,
		progress = tableOf(missions.progress),
		cars = tableOf(state.cars),
		car = if type(state.car) == "string" then state.car else nil,
		lastCar = if type(state.lastCar) == "string" then state.lastCar else nil,
		carUpgrades = tableOf(state.carUpgrades),
		carGear = tableOf(state.carGear),
		crewSize = if type(missions.crewSize) == "number" then missions.crewSize else 0,
		crewOwner = if type(missions.crewOwner) == "string" then missions.crewOwner else nil,
		kit = tableOf(state.kit),
		weapons = tableOf(state.weapons),
		items = tableOf(state.items),
		vanQuest = if type(state.vanQuest) == "string" then state.vanQuest else nil,
		tutorial = data.tutorial,
		phone = if data.state == nil then nil else state.phone == true,
		-- 6.14 review (nil: not known, nothing held back for it)
		night = if type(night) == "boolean" then night else nil,
		active = if type(missions.active) == "string" then missions.active else nil,
		onJob = if data.onJob ~= nil then data.onJob elseif type(missions.onJob) == "boolean" then missions.onJob else nil,
		carOut = if type(missions.carOut) == "boolean" then missions.carOut else nil,
		partnerNear = if type(missions.partnersNear) == "number" then missions.partnersNear >= Config.Missions.Duo.MinCrew else nil,
		garages = tableOf(missions.garages),
		at = at,
	}
end

-- The answer now (worked out again only after a change).
function ReadyCheck.current(): Readiness.Result
	if data.dirty or data.result == nil then
		data.dirty = false
		local result = Readiness.evaluate(ReadyCheck.input())
		if data.missions == nil then
			result.quiet = true -- (no progress known yet: it would say First Shift to everybody; the HUD waits)
		end
		data.result = result
	end
	return data.result
end

-- Called with nothing whenever the answer may have changed (the phone's tile, the HUD's line).
function ReadyCheck.listen(fn: () -> ())
	table.insert(data.listeners, fn)
end

-- The one-time toast and sting when the next mission BECOMES ready: the same mission, not ready in the last answer and
-- ready now (the van bought, the level reached, a partner in the crew). What was ready when you joined, or a new
-- mission ready at once (a clear's NEXT: its cleared card says so) is no news; each mission once a session.
local function announce(result: Readiness.Result)
	local mission = result.mission
	if data.state == nil or data.missions == nil then
		return
	end
	local before = data.previous
	data.previous = if mission then { id = mission.id, ready = result.ready } else nil
	if not mission or not result.ready or result.quiet or data.announced[mission.id] then
		return
	end
	local label = result.start.label
	if type(data.missions.crewOwner) == "string" or label == "LEADER PICKS" or label == "IN PROGRESS" then
		return -- (in somebody else's crew the leader picks the mission: the toast waits until you lead your own)
	end
	data.announced[mission.id] = true
	if before == nil or before.id ~= mission.id or before.ready then
		return
	end
	local tell = ReadyCheck.notify
	if tell then
		tell(Readiness.readyToast(mission, Ui.touchLayout()))
	end
	pcall(function()
		require(script.Parent.Sounds).play(Config.Readiness.Sound)
	end)
end

local function changed()
	data.dirty = true
	local result = ReadyCheck.current()
	announce(result)
	for _, fn in data.listeners do
		local ok, err = pcall(fn)
		if not ok then
			warn(`[ReadyCheck] {err}`)
		end
	end
end

function ReadyCheck.setState(state: any)
	if type(state) == "table" then
		data.state = state
		if data.missions == nil and not data.asked then
			-- (the save is in: the Missions state can come now, if the first ask was too early)
			data.asked = true
			Net.get("Missions"):FireServer("open")
		end
		changed()
	end
end

-- The Missions remote's ("state", data): the progress, the level, the crew.
function ReadyCheck.setMissions(state: any)
	if type(state) == "table" then
		data.missions = state
		changed()
	end
end

-- The Tutorial remote: her phase while her first day runs (nil / "done": over; "say", "phone", "message": no phase).
function ReadyCheck.setTutorial(phase: any)
	if phase == "say" or phase == "phone" or phase == "message" then
		return
	end
	data.tutorial = if type(phase) == "string" and phase ~= "done" then phase else nil
	changed()
end

-- ── The words for the other surfaces ──────────────────────────────────────

-- The WORK tile's goal line ("Earn for the Old Van · $1,160 to go"), nil without a goal.
function ReadyCheck.workLine(): string?
	return Readiness.workLine(ReadyCheck.current().goal)
end

-- The job result's line ("+$85 · $1,160 to go for the Old Van"): the pay just earned counted in (the State with it
-- comes a moment after the result). nil without a goal or during Marge's first day.
function ReadyCheck.resultLine(pay: number): string?
	local result = ReadyCheck.current()
	if result.quiet or not result.goal then
		return nil
	end
	local state = tableOf(data.state) or {}
	return Readiness.resultLine(pay, result.goal, (tonumber(state.money) or 0) + pay)
end

-- 6.14 review: the goal's words after a pay, for the DELIVERED toast ("$1,160 to go for the Old Van"); nil without
-- a goal, without pay or during Marge's first day.
function ReadyCheck.goalWords(pay: number): string?
	local result = ReadyCheck.current()
	if result.quiet or not result.goal or pay <= 0 then
		return nil
	end
	local state = tableOf(data.state) or {}
	return Readiness.goalWords(result.goal, (tonumber(state.money) or 0) + pay)
end

-- ── The phone's NEXT MISSION tile ─────────────────────────────────────────

-- Its lines in the tile Phone's mainTile made (`left`: where its text starts): NEXT MISSION and the readiness on top
-- ("✖ 1 OF 2 READY" / "✔ READY · START" at the right), the mission, its chapter and n/N, the savings goal and its bar.
-- Returns them (`name`, the mission, is the hover's label). (About 218 px of text at the phone's width: short lines.)
function ReadyCheck.tile(cell: Instance, left: number): { [string]: any }
	local width = UDim2.new(1, -(left + 12), 0, 16)
	local t: { [string]: any } = {}
	t.head = P.caps(cell, "NEXT MISSION", UDim2.fromOffset(92, 16), { Name = "Head", Position = UDim2.fromOffset(left, 12), TextSize = 11, TextColor3 = K.red, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left })
	t.status = P.caps(cell, "", UDim2.new(1, -(left + 12 + 92), 0, 16), { Name = "Status", Position = UDim2.fromOffset(left + 92, 12), TextSize = 11, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right })
	t.name = P.text(cell, "", UDim2.new(1, -(left + 12), 0, 20), { Name = "Mission", Position = UDim2.fromOffset(left, 29), Font = Theme.HeadingFont, TextSize = 16, TextScaled = true, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left })
	-- (a long name, "Rush Hour of the Dead", shrinks a little before it would be cut)
	Ui.make("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 12 }, t.name)
	t.chapter = P.text(cell, "", width, { Name = "Chapter", Position = UDim2.fromOffset(left, 52), TextSize = 12, TextColor3 = K.secondary, TextStrokeTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	t.goal = P.text(cell, "", width, { Name = "Goal", Position = UDim2.fromOffset(left, 70), TextSize = 12, TextColor3 = K.text, TextStrokeTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local holder = Ui.make("Frame", { Name = "Progress", Size = UDim2.new(1, -(left + 16), 0, 4), Position = UDim2.fromOffset(left, 91), BackgroundTransparency = 1 }, cell)
	local back, fill = P.bar(holder, UDim2.new(1, 0, 1, 0), K.red)
	fill.Size = UDim2.fromScale(0, 1)
	t.track, t.bar = back, fill
	return t
end

-- Fills the tile's lines with the answer now.
function ReadyCheck.fillTile(t: { [string]: any }?)
	if not t then
		return
	end
	local result = ReadyCheck.current()
	local mission = result.mission
	t.name.Text = if mission then `{mission.icon} {mission.name}` else "🏆 Every mission done"
	t.chapter.Text = Readiness.chapterLine(mission)
	local badge, tone = Readiness.badge(result)
	t.status.Text = badge
	t.status.TextColor3 = if tone == "good" then K.good elseif tone == "wait" then K.warn else K.red
	local goal = result.goal
	t.goal.Text = if goal then `{goal.icon} {Readiness.goalLine(goal)}` elseif mission and result.ready then (result.start.why or "Everything it needs is yours") else ""
	t.goal.TextColor3 = if goal and goal.afford then K.good elseif goal and goal.locked and goal.left <= 0 then K.warn elseif goal then K.text else K.secondary
	t.track.Visible = goal ~= nil
	if goal then
		t.bar.Size = UDim2.fromScale(math.clamp(goal.have / math.max(1, goal.need), 0, 1), 1)
		t.bar.BackgroundColor3 = if goal.afford then K.good elseif goal.left <= 0 then K.warn else K.red
	end
end

-- ── INVITE ────────────────────────────────────────────────────────────────

-- Roblox's game invite when it can be sent (both calls in a pcall), else the CREW window (the crew board for this
-- mission). The friend still joins your crew in CREW (K) once here: the toast says so.
function ReadyCheck.invite(missionId: string?)
	task.spawn(function()
		local prompted = false
		local ok, can = pcall(function(): boolean
			return game:GetService("SocialService"):CanSendGameInviteAsync(player)
		end)
		if ok and can == true then
			prompted = pcall(function()
				game:GetService("SocialService"):PromptGameInvite(player)
			end)
		end
		local tell = ReadyCheck.notify
		if prompted then
			if tell then
				tell(if Ui.touchLayout() then "Once your friend is here: CREW → INVITE them to your crew" else "Once your friend is here: CREW (K) → INVITE them to your crew")
			end
			return
		end
		local crew = ReadyCheck.onCrew
		if crew then
			crew(missionId)
		elseif tell then
			tell("Open CREW (K) and invite a player to your crew.")
		end
	end)
end

-- ── The READY CHECK (the phone's popup) ───────────────────────────────────

-- A row's action: the GPS to its shop (the phone goes away: go there), INVITE, JOBS, GARAGE, MISSIONS.
local function act(check: Readiness.Check, host: Host, result: Readiness.Result)
	local mission = result.mission
	local action = check.action
	if action == "gps" and check.place then
		local name = Gps.to(check.place)
		host.close()
		host.notify(`GPS set: {name or Readiness.placeName(check.place) or check.place}{if check.name then ` · {check.name}` else ""}`)
	elseif action == "invite" then
		ReadyCheck.invite(if mission then mission.id else nil)
	elseif action == "jobs" then
		host.go("board")
	elseif action == "garage" then
		host.go("garage")
	elseif action == "missions" then
		local open = ReadyCheck.onMissions
		host.close()
		if open then
			open(if mission then mission.campaign else nil)
		end
	end
end

-- One row: the mark (✔ green, ✖ red, ☆ grey), the headline and how / where, the action on the right (the row is a
-- button then: Name "Check_<id>").
local function row(parent: Instance, look: OrdersUi.Kit, check: Readiness.Check, order: number, onAct: () -> ())
	local actionable = check.action ~= nil and not check.done
	local missing = check.required and not check.done
	local cell = Ui.make(if actionable then "TextButton" else "Frame", {
		Name = `Check_{check.id}`,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	if actionable then
		cell.AutoButtonColor = false
		cell.Text = ""
	end
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if missing then K.red else K.line, Thickness = 1, Transparency = if missing then 0.45 else 0.82 }, cell)
	Ui.make("UISizeConstraint", { MinSize = Vector2.new(0, 54) }, cell)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, cell)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, cell)
	look.text(cell, Readiness.mark(check), UDim2.fromOffset(22, 22), {
		Name = "Mark",
		LayoutOrder = 1,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = if check.done then K.good elseif check.required then K.red else K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local words = Ui.make("Frame", { Name = "Words", Size = UDim2.new(1, if actionable then -128 else -30, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, cell)
	Ui.list(words, true, 2)
	look.text(words, `{check.icon}  {check.text}`, UDim2.new(1, 0, 0, 0), { Name = "Text", AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Font = Theme.HeadingFont, TextSize = 14, TextColor3 = if check.done then K.secondary else K.text })
	if check.detail then
		look.text(words, check.detail, UDim2.new(1, 0, 0, 0), { Name = "Detail", AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 12, TextColor3 = K.secondary })
	end
	if not check.required and not check.done then
		look.text(words, "Not needed to start: it helps", UDim2.new(1, 0, 0, 0), { Name = "Optional", AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, TextSize = 11, TextColor3 = K.secondary, TextTransparency = 0.25 })
	end
	if actionable then
		local label = look.text(cell, ACTION_WORDS[check.action or ""] or "›", UDim2.fromOffset(90, 22), { Name = "Action", LayoutOrder = 3, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = if missing then K.red else K.text, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right })
		local button = cell :: any
		local function lit(on: boolean)
			button.BackgroundColor3 = if on then K.raised else K.row
			label.TextColor3 = if on then K.red elseif missing then K.red else K.text
		end
		button.MouseEnter:Connect(function()
			lit(true)
		end)
		button.MouseLeave:Connect(function()
			lit(false)
		end)
		button.SelectionGained:Connect(function()
			lit(true)
		end)
		button.SelectionLost:Connect(function()
			lit(false)
		end)
		button.Activated:Connect(function()
			local sound = Ui.onClick
			if sound then
				sound()
			end
			onAct()
		end)
	end
end

-- The savings goal's card: what for, your money / its price, what is left, the bar (tick keeps the money live).
local function goalCard(parent: Instance, look: OrdersUi.Kit, goal: Readiness.Goal, order: number)
	local card = look.block(parent, order)
	card.Parent.Name = "SavingsGoal"
	look.caps(card, "Saving for", 1, K.red).TextSize = 11
	look.text(card, goal.name, UDim2.new(1, 0, 0, 22), { LayoutOrder = 2, Font = Theme.HeadingFont, TextSize = 17, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local _, have, left = look.row2(card, `{Readiness.money(goal.have)} / {Readiness.money(goal.need)}`, Readiness.toGo(goal), 3, true)
	local holder = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 1, LayoutOrder = 4 }, card)
	local back, fill = P.bar(holder, UDim2.new(1, 0, 0, 4), K.red)
	back.Position = UDim2.fromOffset(0, 2)
	look.meta(card, `Jobs pay for it: WORK has the board.{if goal.place then ` Its row's GPS shows the way.` else ""}`, 5)
	data.view = { have = have, left = left, fill = fill, goal = goal }
	ReadyCheck.tick()
end

-- The goal's money line and bar, from the state now (the phone's ticker, twice a second while it shows).
function ReadyCheck.tick()
	local view = data.view
	if not view or not view.have.Parent then
		return
	end
	local goal = ReadyCheck.current().goal
	if not goal or goal.id ~= view.goal.id then
		return
	end
	view.have.Text = `{Readiness.money(goal.have)} / {Readiness.money(goal.need)}`
	view.left.Text = Readiness.toGo(goal)
	view.left.TextColor3 = if goal.afford then K.good elseif goal.left <= 0 then K.warn else K.text
	view.fill.Size = UDim2.fromScale(math.clamp(goal.have / math.max(1, goal.need), 0, 1), 1)
	view.fill.BackgroundColor3 = if goal.afford then K.good elseif goal.left <= 0 then K.warn else K.red
end

-- What the READY CHECK shows right now (the phone draws it again when this changes, not for every coin).
function ReadyCheck.key(): string
	return Readiness.key(ReadyCheck.current())
end

-- The READY CHECK in the phone's popup (`wide`: two columns: the mission, its buttons and the goal on the left, the
-- checklist on the right).
function ReadyCheck.draw(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?)
	data.view = nil
	local result = ReadyCheck.current()
	local mission = result.mission
	local columns = require(script.Parent.PhoneApps).columns
	if not mission then
		look.emptyState(list, "🏆", "Every mission done", "Every chapter, every star. Replay any of them in MISSIONS for fun.", 1)
		look.button(list, "OPEN MISSIONS", "main", 2, function()
			act({ id = "missions", icon = "", text = "", done = false, required = false, action = "missions" }, host, result)
		end)
		return
	end
	local left, right = columns(list, 1, wide == true)
	-- The mission.
	local card = look.block(left, 1, true)
	card.Parent.Name = "MissionCard"
	look.caps(card, `{mission.icon}  {Readiness.chapterLine(mission)}`, 1, K.red).TextSize = 11
	look.text(card, string.upper(mission.name), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Font = Theme.HeadingFont, TextSize = 19 })
	look.meta(card, mission.description, 3)
	local chips = look.chipRow(card, 4)
	local badge, tone = Readiness.badge(result)
	look.chip(chips, badge, if tone == "good" then K.good elseif tone == "wait" then K.warn else K.red)
	look.chip(chips, string.rep("★", math.clamp(mission.tier, 1, 4)), K.text)
	if mission.duo then
		look.chip(chips, "🤝 DUO", K.red)
	elseif mission.coop then
		look.chip(chips, "Co-op", K.text)
	end
	if mission.lends then
		look.chip(chips, "Lends its vehicle")
	end
	local owner = ReadyCheck.input().crewOwner
	if owner then
		look.meta(card, `👥 You ride in {owner}'s crew: your leader picks the mission. Leave the crew (CREW) to start your own.`, 5)
	end
	-- The buttons: START when it can work (the MISSIONS window on it, its START), CALL CAR FIRST (the GARAGE), what
	-- stands in the way (IN PROGRESS, LEADER PICKS, AFTER YOUR RUN: quiet), else JOBS (earn, level up); MISSIONS.
	local actions = if wide then left else list
	local base = if wide then 2 else 30
	local start = result.start
	if start.why and not start.can and start.label ~= "NOT READY" and start.label ~= "LEADER PICKS" then
		look.meta(card, `⏸ {start.why}.`, 6)
	end
	if start.can then
		local button = look.button(actions, `START ▶   {string.upper(mission.name)}`, "main", base, function()
			host.close()
			local go = ReadyCheck.onStart
			if go then
				go(mission.id)
			end
		end)
		button.Name = "Start"
	elseif start.label == "IN PROGRESS" or (result.ready and (start.label == "LEADER PICKS" or start.label == "AFTER YOUR RUN")) then
		local words = if start.label == "IN PROGRESS" then "▶ IN PROGRESS" elseif start.label == "LEADER PICKS" then "👥 YOUR LEADER PICKS" else "FINISH YOUR RUN FIRST"
		local button = look.button(actions, words, "quiet", base, function()
			host.notify(start.why or start.label)
		end)
		button.Name = "Waiting"
	elseif result.ready and start.label == "CALL CAR" then
		local button = look.button(actions, "CALL CAR FIRST  ›", "main", base, function()
			host.go("garage")
		end)
		button.Name = "CallCar"
	else
		local jobs = look.button(actions, "WORK · EARN AND LEVEL UP", "main", base, function()
			host.go("board")
		end)
		jobs.Name = "Jobs"
	end
	local open = look.button(actions, "OPEN MISSIONS", "quiet", base + 1, function()
		act({ id = "missions", icon = "", text = "", done = false, required = false, action = "missions" }, host, result)
	end)
	open.Name = "OpenMissions"
	-- The checklist.
	look.section(right, if result.ready then "Ready · what would help" else "Before you can start", if wide then 1 else 2)
	local rows = Ui.make("Frame", { Name = "Checks", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = if wide then 2 else 3 }, right)
	Ui.list(rows, true, 6)
	for index, check in result.checks do
		local text = check
		if check.id == "level" and not check.done and check.have and check.need then
			-- the XP to go as work ("about 8 on-foot runs", CareerUi.toGo)
			local toGo = ReadyCheck.toGo
			if toGo then
				local ok, words = pcall(toGo, math.max(0, check.need - check.have), Levels.levelFor(check.have))
				if ok and type(words) == "string" then
					text = table.clone(check)
					text.detail = `{check.detail or ""} · about {words}`
				end
			end
		end
		row(rows, look, text, index, function()
			act(check, host, result)
		end)
	end
	-- The savings goal.
	if result.goal then
		goalCard(if wide then left else list, look, result.goal, if wide then 4 else 20)
	end
end

-- ── Start ─────────────────────────────────────────────────────────────────

function ReadyCheck.start()
	local missions = Net.get("Missions")
	missions.OnClientEvent:Connect(function(kind: any, state: any)
		if kind == "state" then
			ReadyCheck.setMissions(state)
		elseif type(kind) == "table" then
			ReadyCheck.setMissions(kind)
		end
	end)
	-- (client/MissionsUi.luau asks for it when it starts, after this; asked before the save loaded, the server sends
	-- nothing: setState asks once more when the first State shows the save is in.)
	Net.get("Tutorial").OnClientEvent:Connect(function(phase: any)
		ReadyCheck.setTutorial(phase)
	end)
	player:GetAttributeChangedSignal("Xp"):Connect(changed)
	-- 6.14 review: the night (a NIGHT ONLY mission) and a job of yours (AFTER YOUR RUN).
	workspace:GetAttributeChangedSignal("Night"):Connect(changed)
	Net.get("Job").OnClientEvent:Connect(function(job: any)
		local now = job ~= nil
		if now ~= data.onJob then
			data.onJob = now
			changed()
		end
	end)
	-- The HUD's savings line under the cash (client/SavingsLine.luau; no HUD, no line).
	local ok, err = pcall(function()
		require(script.Parent.SavingsLine).start(ReadyCheck)
	end)
	if not ok then
		warn(`[ReadyCheck] the savings line: {err}`)
	end
end

return ReadyCheck
