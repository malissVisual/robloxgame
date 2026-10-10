--!strict
-- 6.14, get ready for the mission on the client (the owner: "You and a friend do delivery jobs ... it should feel like
-- 'okay, let's go get ready for that mission'. Jobs are the daily work: grind, save up for something, then progress in
-- the mission."). shared/Readiness.luau decides; this module feeds it and shows it:
--   * What it knows: the State remote (Main: ReadyCheck.setState), the Missions remote's state (the progress, the crew:
--     server/Missions.luau sends it on "open" and whenever it changes), the Xp attribute and Marge's tutorial phase
--     (the Tutorial remote). ReadyCheck.current() is the answer, worked out again only when one of them changed.
--   * The phone's home (client/Phone.luau): the wide NEXT MISSION tile (ReadyCheck.tile / fillTile: the chapter and
--     n/N, the mission, "2 of 3 ready" in red or "READY · START" in green, the savings goal's bar) and the WORK tile's
--     goal line (ReadyCheck.workLine: "Earn for the Old Van · $1,160 to go"). 6.18: the tile is the home's hero card
--     (client/CardKit.luau hero, client/PhoneHome.luau): the chapter's picture, the mission big, GET READY / ▶ START.
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
-- 6.18 (the UI kit, client/CardKit.luau; design/ui-kit/README.md): the READY CHECK in the JOBS look. The mission is the
-- HERO ("MissionCard": the chapter's picture, the chapter and n/N on the ribbon, the readiness chip on the corner, the
-- mission's name, its reward big, one facts line (the stars, DUO / co-op, what it lends; or why START waits), the
-- savings goal's bar, and ONE button: ▶ START (green), CALL CAR FIRST (amber), a grey IN PROGRESS / YOUR LEADER PICKS,
-- else WORK · EARN AND LEVEL UP (red). The checks are the kit's rows ("Check_<id>": the icon, the mark ✔ / ✖ / ☆
-- in its colour, the headline, one line of how and where, the action's words: 📍 GPS ›, INVITE ›, JOBS ›; the edge
-- green / red / grey), MISSIONS › a chip over them, and the savings goal a row ("SavingsGoal": $640 / $1,800, the money
-- to go big, its bar; the ticker keeps it live). The hero sits beside the rows in a wide popup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Readiness = require(Shared.Readiness)
local MissionArt = require(Shared.MissionArt)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Gps = require(script.Parent.Gps)
local OrdersUi = require(script.Parent.OrdersUi)
local CardKit = require(script.Parent.CardKit) -- 6.18: the home's hero and the READY CHECK in the UI kit's look

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
	room: (() -> number)?, -- 6.18: the popup's room (the hero's height; client/Phone.luau's host)
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

-- ── The phone's NEXT MISSION hero ─────────────────────────────────────────

-- 6.18: the home's hero card in the UI kit's look (client/CardKit.luau hero; client/PhoneHome.luau places it): the
-- chapter's picture (else the mission's emoji big), "NEXT MISSION" on its ribbon, the readiness chip at the right
-- ("✖ 1 OF 2 READY" red / "✔ READY · START" green / amber), then at its foot the chapter and n/N, the mission big, the
-- savings goal and its bar, and (a tall enough hero, `spec.button`) GET READY / ▶ START. The whole card opens the
-- READY CHECK. Returns its parts (`card`, `name` the mission, `status`, `chapter`, `goal`, `track`, `bar`, `action`).
function ReadyCheck.tile(parent: Instance, spec: { name: string, height: number, button: boolean, onOpen: () -> () }): { [string]: any }
	local parts = CardKit.hero(parent, {
		name = spec.name,
		order = 1,
		height = spec.height,
		button = true,
		silent = true,
		stroke = K.red,
		picture = { emoji = "🏁" },
		title = "",
		titleColor = K.secondary,
		value = "",
		valueColor = K.text,
		valueSize = Config.UiKit.HomeValue,
		valueFont = Theme.HeadingFont,
		facts = "",
		bar = { share = 0, color = K.red },
		action = if spec.button then { name = "Go", text = "GET READY ›", height = Config.UiKit.HomeButton, textSize = 16, silent = true, onClick = spec.onOpen } else nil,
		ribbon = { text = "NEXT MISSION", face = K.red, ink = K.text },
		corner = { text = "", ink = K.red, width = 120 },
		onOpen = spec.onOpen,
	})
	parts.ribbon.Name = "Head"
	parts.corner.Name = "Status"
	parts.title.Name = "Chapter"
	parts.value.Name = "Mission"
	parts.facts.Name = "Goal"
	-- (a long name, "Rush Hour of the Dead", shrinks a little before it would be cut)
	parts.value.TextScaled = true
	Ui.make("UITextSizeConstraint", { MaxTextSize = Config.UiKit.HomeValue, MinTextSize = 16 }, parts.value)
	return {
		card = parts.card,
		head = parts.ribbon,
		status = parts.corner,
		name = parts.value,
		chapter = parts.title,
		goal = parts.facts,
		track = parts.track,
		bar = parts.bar,
		action = parts.action,
		stroke = parts.card:FindFirstChildOfClass("UIStroke"),
	}
end

-- Fills the hero with the answer now.
function ReadyCheck.fillTile(t: { [string]: any }?)
	if not t then
		return
	end
	local result = ReadyCheck.current()
	local mission = result.mission
	t.name.Text = if mission then `{mission.icon} {mission.name}` else "🏆 Every mission done"
	t.chapter.Text = Readiness.chapterLine(mission)
	-- the chapter's picture (shared/MissionArt.luau), else the mission's emoji
	local image = if mission then MissionArt.forCampaign(mission.campaign) else nil
	local key = image or (if mission then mission.icon else "🏆")
	if t.picture ~= key then
		t.picture = key
		CardKit.repicture(t.card, { image = image, emoji = if mission then mission.icon else "🏆" }, 64)
	end
	local badge, tone = Readiness.badge(result)
	local color = if tone == "good" then K.good elseif tone == "wait" then K.warn else K.red
	t.status.Text = badge
	t.status.TextColor3 = color
	t.status.Size = UDim2.fromOffset(CardKit.width(badge, 13, Theme.HeadingFont) + 20, 24)
	if t.stroke then
		t.stroke.Color = color
	end
	local action = t.action
	if action then
		local kind = if not mission then "shut" elseif result.ready and result.start.can then "good" elseif result.ready then "warn" else "primary"
		action.Text = if not mission then "MISSIONS ›" elseif kind == "good" then "READY · GO ›" elseif kind == "warn" then "READY CHECK ›" else "GET READY ›"
		CardKit.paint(action, kind)
	end
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

-- One row (6.18: the kit's compact row): the check's icon, its mark (✔ green, ✖ red, ☆ grey) in the tag, the
-- headline and how / where (an optional one says it helps), the action's words on the right ("Action": the row and
-- the words act). Name "Check_<id>".
local function row(parent: Instance, check: Readiness.Check, order: number, onAct: () -> ())
	local actionable = check.action ~= nil and not check.done
	local missing = check.required and not check.done
	local tone = if check.done then K.good elseif check.required then K.red else K.secondary
	local facts = check.detail or ""
	if not check.required and not check.done then
		facts = if facts ~= "" then `{facts} · it helps` else "Not needed to start: it helps"
	end
	local made = CardKit.row(parent, {
		name = `Check_{check.id}`,
		order = order,
		accent = if check.done then K.good elseif missing then K.red else K.line,
		picture = { emoji = check.icon },
		thumb = Config.UiKit.Icon,
		tag = Readiness.mark(check),
		tagColor = tone,
		tagWidth = 24,
		title = check.text,
		titleColor = if check.done then K.secondary else K.text,
		facts = facts,
		word = if actionable then ACTION_WORDS[check.action or ""] or "›" else nil,
		actionFace = if missing then K.red else nil,
		onAction = if actionable then onAct else nil,
		silent = not actionable,
		onOpen = function()
			if actionable then
				onAct()
			end
		end,
	})
	made.tag.Name = "Mark"
	if made.action then
		made.action.Name = "Action"
	end
end

-- The savings goal's row (6.18): what for, your money / its price, the money to go big, the bar (tick keeps it live).
local function goalRow(parent: Instance, goal: Readiness.Goal, order: number)
	local made = CardKit.row(parent, {
		name = "SavingsGoal",
		order = order,
		accent = K.red,
		picture = { emoji = goal.icon },
		thumb = Config.UiKit.Icon,
		title = `SAVING FOR · {string.upper(goal.name)}`,
		titleColor = K.text,
		facts = `{Readiness.money(goal.have)} / {Readiness.money(goal.need)}`,
		value = Readiness.toGo(goal),
		valueColor = K.text,
		silent = true,
		onOpen = function() end,
	})
	local fill = CardKit.rowBar(made, 0, K.red)
	data.view = { parts = made, fill = fill, goal = goal, hero = data.view and data.view.hero }
	ReadyCheck.tick()
end

-- The goal's money line, its value and the bars, from the state now (the phone's ticker, twice a second while it shows).
function ReadyCheck.tick()
	local view = data.view
	if not view or not view.parts or not view.parts.row.Parent then
		return
	end
	local goal = ReadyCheck.current().goal
	if not goal or goal.id ~= view.goal.id then
		return
	end
	local color = if goal.afford then K.good elseif goal.left <= 0 then K.warn else K.red
	local share = math.clamp(goal.have / math.max(1, goal.need), 0, 1)
	view.parts.facts.Text = `{Readiness.money(goal.have)} / {Readiness.money(goal.need)}`
	CardKit.setValue(view.parts, Readiness.toGo(goal), if goal.afford then K.good elseif goal.left <= 0 then K.warn else K.text)
	view.fill.Size = UDim2.fromScale(share, 1)
	view.fill.BackgroundColor3 = color
	local hero = view.hero
	if hero and hero.Parent then
		hero.Size = UDim2.fromScale(share, 1)
		hero.BackgroundColor3 = color
	end
end

-- What the READY CHECK shows right now (the phone draws it again when this changes, not for every coin).
function ReadyCheck.key(): string
	return Readiness.key(ReadyCheck.current())
end

-- The hero's ONE button (see the header) and its look: START when it can work (the MISSIONS window on it, its START),
-- CALL CAR FIRST (the GARAGE), what stands in the way (IN PROGRESS, LEADER PICKS, AFTER YOUR RUN: grey), else JOBS.
local function heroAction(result: Readiness.Result, host: Host): CardKit.Button
	local mission = result.mission :: Readiness.MissionInfo
	local start = result.start
	if start.can then
		return { name = "Start", text = "▶ START", kind = "good", onClick = function()
			host.close()
			local go = ReadyCheck.onStart
			if go then
				go(mission.id)
			end
		end }
	elseif start.label == "IN PROGRESS" or (result.ready and (start.label == "LEADER PICKS" or start.label == "AFTER YOUR RUN")) then
		local words = if start.label == "IN PROGRESS" then "▶ IN PROGRESS" elseif start.label == "LEADER PICKS" then "👥 YOUR LEADER PICKS" else "FINISH YOUR RUN FIRST"
		return { name = "Waiting", text = words, kind = "shut", onClick = function()
			host.notify(start.why or start.label)
		end }
	elseif result.ready and start.label == "CALL CAR" then
		return { name = "CallCar", text = "CALL CAR FIRST  ›", kind = "warn", onClick = function()
			host.go("garage")
		end }
	end
	return { name = "Jobs", text = "WORK · EARN AND LEVEL UP", kind = "primary", onClick = function()
		host.go("board")
	end }
end

-- The READY CHECK in the phone's popup (see the header; `wide`: the hero beside the rows).
function ReadyCheck.draw(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?)
	data.view = nil
	local result = ReadyCheck.current()
	local mission = result.mission
	local function openMissions()
		act({ id = "missions", icon = "", text = "", done = false, required = false, action = "missions" }, host, result)
	end
	if not mission then
		look.emptyState(list, "🏆", "Every mission done", "Every chapter, every star. Replay any of them in MISSIONS for fun.", 1)
		look.button(list, "OPEN MISSIONS", "main", 2, openMissions)
		return
	end
	local room = if host.room then host.room() else Config.UiKit.HeroMin
	local height = CardKit.Layout.heroHeight(room)
	local _, left, right = CardKit.columns(list, { name = "ReadyView", order = 1, side = wide == true, hero = true, heroHeight = height })
	-- The mission: the hero.
	local badge, tone = Readiness.badge(result)
	local color = if tone == "good" then K.good elseif tone == "wait" then K.warn else K.red
	local def = require(Shared.Missions).find(mission.id)
	local start = result.start
	local facts = { string.rep("★", math.clamp(mission.tier, 1, 4)) }
	if mission.duo then
		table.insert(facts, "🤝 DUO")
	elseif mission.coop then
		table.insert(facts, "👥 co-op")
	end
	if mission.lends then
		table.insert(facts, "lends its vehicle")
	end
	local owner = ReadyCheck.input().crewOwner
	local why = if owner then `👥 {owner}'s crew: your leader picks`
		elseif start.why and not start.can and start.label ~= "NOT READY" and start.label ~= "LEADER PICKS" then `⏸ {start.why}`
		else nil
	local goal = result.goal
	local image = MissionArt.forCampaign(mission.campaign)
	local parts = CardKit.hero(left, {
		name = "MissionCard",
		height = height,
		stroke = color,
		strong = true,
		picture = { image = image, emoji = mission.icon },
		title = string.upper(mission.name),
		value = if def then Ui.money(def.reward) else "",
		valueColor = if mission.replay then CardKit.Color.dim else CardKit.Color.money,
		facts = why or table.concat(facts, " · "),
		factsColor = if why then K.warn else K.text,
		bar = if goal then { share = math.clamp(goal.have / math.max(1, goal.need), 0, 1), color = K.red } else nil,
		action = heroAction(result, host),
		ribbon = { text = `{mission.icon}  {string.upper(Readiness.chapterLine(mission))}`, face = K.raised, ink = K.text },
		corner = { text = badge, ink = color, width = CardKit.width(badge, 13, Theme.HeadingFont) + 20 },
		onOpen = function() end,
		silent = true,
	})
	parts.corner.Name = "Status"
	data.view = { hero = parts.bar }
	-- The checklist (MISSIONS › a chip at its head).
	local _, _, missionsChip = CardKit.sectionHeader(right, {
		name = "ChecksHead",
		text = string.upper(if result.ready then "Ready · what would help" else "Before you can start"),
		order = 0,
		chip = { name = "OpenMissions", text = "MISSIONS ›", order = 1, onClick = openMissions },
	})
	missionsChip.Name = "OpenMissions"
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
		row(right, text, index, function()
			act(check, host, result)
		end)
	end
	-- The savings goal.
	if goal then
		goalRow(right, goal, #result.checks + 1)
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
