--!strict
-- 10.4 THE PLAY PANEL (the owner: "on the map just one circle where you'd stand, like PLAY, and you'd create a lobby";
-- server/Parties.luau decides everything, the rules shared/PartyRules.luau; Config.Runs.Panel): what you see at the
-- lobby's PLAY circle and in a party lobby. Presentation only: the Party remote asks. client/RunUi.luau starts it (its
-- window: RunUi.isOpen, RunUi.close, RunUi.onOpen).
--   * The panel (a window in the middle of the screen, the game's contract look: charcoal, the circle's blue line;
--     Panel.Width × Height px, scaled to fit, a phone's at Panel.TouchScale at least: every button a finger's size). It
--     opens when you step into the circle (the server's view with circle = true); ✕ or ESC shut it until you step out
--     and in again (the bar's OPEN brings it back). Its screens:
--       OPEN LOBBIES (in no lobby): ＋ CREATE A LOBBY, how it works, the lobbies you may join (the host, the house with
--         its little picture, the difficulty, n/4, friends only; JOIN, or FULL / STARTING);
--       CREATE A LOBBY: the six houses (each its picture: an icon on its walls' and roof's colours, its name, a short
--         line; one in a run "IN A RUN", one another lobby holds "TAKEN"), the difficulty (the five; the ones not open
--         to you 🔒: a tap says how to open them), who can join (PUBLIC / FRIENDS ONLY), CREATE LOBBY; ‹ BACK;
--       YOUR LOBBY: the house, the difficulty, public or friends, the players (👑 the host, ✓ READY or not; the host's
--         KICK on the others), READY (everybody), the host's CHANGE HOUSE (the houses again), difficulty and START
--         (once the host is READY; then STARTING IN 5 and CANCEL), LEAVE LOBBY.
--   * The lobby bar (in a lobby, the panel shut or you away from the circle; or in the circle with the panel shut): the
--     house, the difficulty, the players and who is READY, STARTING IN 3, and OPEN. A computer's top centre under the
--     HUD's top row, a touch screen's top right (where the 9.7 pad panel stood). Walking away keeps you in the lobby.
--   * The circle's glow breathes (its PlayGlow part, Play.Pulse s a breath: a tween on this screen only).
--   PlayUi.start()           the remote, the screen (client/RunUi.luau's start)
--   PlayUi.view()            the server's view now ({ circle, lobby?, lobbies, houses, … }) or nil (client/SandboxGuide.luau)
--   PlayUi.isOpen()          the panel is open (a window: RunUi.isOpen)
--   PlayUi.close()           shuts the panel (ESC, another window)
--   PlayUi.open()            opens it (the bar's OPEN)
--   PlayUi.screen()          which screen shows: "home" | "create" | "lobby" | "house" (the checks)
--   PlayUi.onOpen            set by client/RunUi.luau: called when the panel opens (one window at a time)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RunRules = require(Shared.RunRules)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local PlayUi = {}

PlayUi.onOpen = nil :: (() -> ())?

local R = Config.Runs
local PN = R.Panel
local K = Theme.Contract
local BLUE = Color3.fromRGB(R.Play.Free[1], R.Play.Free[2], R.Play.Free[3])
local AMBER = Color3.fromRGB(R.Play.Waiting[1], R.Play.Waiting[2], R.Play.Waiting[3])
local GOLD = Color3.fromRGB(255, 206, 92)
local BUTTON = 56 -- px at scale 1: a button's least size (a finger's at the touch scale)
local HEADER = 62 -- px at scale 1: the panel's header
local BAR_H = 68 -- px at scale 1: the lobby bar
local BAR_TOP = 120 -- px: the bar's top on a computer (under the HUD's top row of chips and key hints)

local remote: RemoteEvent? = nil
local gui: ScreenGui? = nil
local ui: { [string]: any } = {} -- panel, bar, the countdown labels
local state = {
	view = nil :: { [string]: any }?,
	screen = "home", -- "home" | "create" | "lobby" | "house"
	shut = false, -- ✕ / ESC in the circle: shut until you step out and in again (or OPEN)
	open = false, -- OPEN on the bar: the panel shows wherever you are (in a lobby)
	was = false, -- in the circle at the view before
	house = nil :: string?, -- the create screen's picks
	difficulty = nil :: string?,
	friends = false,
	key = "", -- (the panel drawn for this: nothing new, nothing drawn)
	barKey = "",
	ticking = false,
	toast = nil :: TextLabel?,
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function now(): number
	local ok, t = pcall(function(): number
		return workspace:GetServerTimeNow()
	end)
	return if ok then t else os.clock()
end

local function send(message: { [string]: any })
	local r = remote
	if r then
		r:FireServer(message)
	end
end

local function screenGui(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", { Name = "PlayUi", ResetOnSpawn = false, DisplayOrder = 21, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	gui = made
	return made
end

-- The panel's scale: the HUD's (a touch screen's TouchScale at least), never more than 1, never past the screen.
local function scaleNow(): number
	local size = Ui.screenSize()
	local s = Ui.screenScale()
	if Ui.touchLayout() then
		s = math.max(s, PN.TouchScale)
	end
	local fit = math.min((size.X - 2 * PN.Margin) / PN.Width, (size.Y - 2 * PN.Margin) / PN.Height)
	return math.min(1, s, fit)
end

-- The bar's scale: the HUD's (a touch screen's TouchScale at least), never more than 1.
local function barScale(): number
	local s = Ui.screenScale()
	if Ui.touchLayout() then
		s = math.max(s, PN.TouchScale)
	end
	return math.min(1, s)
end

local function label(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3, bold: boolean?, cut: boolean?): TextLabel
	return Ui.make("TextLabel", {
		Name = name,
		Text = text,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		Font = if bold then Theme.HeadingFont else Theme.Font,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = if cut then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
		ZIndex = 3,
	}, parent)
end

local function wrapped(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3): TextLabel
	local made = label(parent, name, text, x, y, w, h, size, color)
	made.TextWrapped = true
	made.TextYAlignment = Enum.TextYAlignment.Top
	return made
end

-- A button (`face` its colour, `ink` its words'); `on`: pressed (nil: shown, not pressable)
local function button(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, face: Color3, ink: Color3, on: (() -> ())?): TextButton
	local made = Ui.make("TextButton", {
		Name = name,
		Text = text,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, math.max(h, BUTTON)),
		BackgroundColor3 = face,
		BackgroundTransparency = if on then 0 else 0.35,
		AutoButtonColor = on ~= nil,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = ink,
		TextWrapped = true,
		ZIndex = 4,
	}, parent)
	Ui.corner(made, 8)
	if on then
		made.Activated:Connect(on)
	end
	return made
end

-- A house's little picture: its walls' colour, its roof's as a band on top, its icon on them.
local function picture(parent: Instance, house: string, x: number, y: number, size: number): Frame
	local card = R.Houses[house] or R.Houses.sandbox_house
	local frame = Ui.make("Frame", { Name = "Picture", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size, size), BackgroundColor3 = rgb(card.wall), BorderSizePixel = 0, ZIndex = 4 }, parent)
	Ui.corner(frame, 6)
	local roof = Ui.make("Frame", { Name = "Roof", Size = UDim2.new(1, 0, 0, math.floor(size * 0.3)), BackgroundColor3 = rgb(card.roof), BorderSizePixel = 0, ZIndex = 5 }, frame)
	Ui.corner(roof, 6)
	Ui.make("TextLabel", { Name = "Icon", Text = card.icon, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, math.floor(size * 0.08)), BackgroundTransparency = 1,
		TextSize = math.floor(size * 0.5), Font = Theme.Font, TextColor3 = K.text, ZIndex = 6 }, frame)
	return frame
end

-- A short line a moment under the panel's header (a locked difficulty: how to open it).
local function note(text: string)
	local panel = ui.panel
	if not panel then
		return
	end
	local old = state.toast
	if old then
		old:Destroy()
	end
	local toast = label(panel, "Note", text, 16, HEADER - 20, PN.Width - 32, 18, 12, GOLD)
	toast.TextTruncate = Enum.TextTruncate.AtEnd
	state.toast = toast
	task.delay(3, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

local function difficultyName(id: any): string
	local def = RunRules.def(id) or (RunRules.def(R.Default) :: Config.RunDifficulty)
	return string.upper(def.name)
end

-- ── The panel's screens ────────────────────────────────────────────────────

local drawPanel: () -> () = function() end -- (set below: the screens' buttons draw the panel again)
local refresh: () -> () = function() end -- (set below: what shows now)

-- ✕ / ESC: the panel shut (the bar instead); the bar's OPEN: the panel wherever you are.
local function shutPanel()
	state.shut, state.open = true, false
	refresh()
end

local function openPanel()
	if state.view then
		state.shut, state.open = false, true
		refresh()
	end
end

local function goTo(screen: string)
	state.screen = screen
	state.key = ""
	drawPanel()
end

-- The difficulty buttons (3 a row): `picked` lit in its colour, the ones not in `open` 🔒 (a tap says how to open them).
local function difficulties(parent: Instance, x: number, y: number, w: number, picked: string, open: { string }, pick: ((string) -> ())?)
	local list = RunRules.list()
	local gap = 6
	local each = math.floor((w - 2 * gap) / 3)
	local isOpen: { [string]: boolean } = {}
	for _, id in open do
		isOpen[id] = true
	end
	for n, def in list do
		local col, row = (n - 1) % 3, (n - 1) // 3
		local opened = isOpen[def.id] == true
		local lit = def.id == picked
		local made = button(parent, `Difficulty_{def.id}`, if opened then string.upper(def.name) else `🔒 {string.upper(def.name)}`, x + col * (each + gap), y + row * (BUTTON + gap), each, BUTTON,
			if lit then rgb(def.color) else K.row, if lit then K.charcoal elseif opened then rgb(def.color) else K.secondary, if pick then function()
				if opened then
					pick(def.id)
				else
					local before = list[n - 1]
					note(`🔒 Finish a run at {if before then string.upper(before.name) else "the one before"} to open {string.upper(def.name)}`)
				end
			end else nil)
		made.TextSize = 12
		if not pick then
			made.BackgroundTransparency = if lit then 0 else 0.35
		end
	end
end

-- The six houses' cards (2 a row): `picked` outlined in gold; one in a run or another lobby's not pressable.
local function houseCards(parent: Instance, view: { [string]: any }, x: number, y: number, w: number, picked: string?, pick: (string) -> ())
	local gap = 8
	local each = math.floor((w - gap) / 2)
	local high = 96
	for n, h in view.houses or {} do
		local col, row = (n - 1) % 2, (n - 1) // 2
		local card = R.Houses[h.id] or R.Houses.sandbox_house
		local free = h.state == "free" or h.mine == true
		local made = button(parent, `House_{h.id}`, "", x + col * (each + gap), y + row * (high + gap), each, high, K.row, K.text, if free then function()
			pick(h.id)
		end else nil)
		made.BackgroundTransparency = if free then 0 else 0.4
		Ui.stroke(made, if h.id == picked then GOLD else K.rule, if h.id == picked then 2 else 1)
		picture(made, h.id, 8, 8, 48)
		local name = wrapped(made, "Name", string.upper(tostring(h.name)), 64, 6, each - 70, 32, 12, K.text)
		name.Font = Theme.HeadingFont
		wrapped(made, "Line", card.line, 64, 38, each - 70, 30, 11, K.secondary)
		local status, tone = "FREE", K.good
		if h.mine == true then
			status, tone = "YOUR LOBBY'S", GOLD
		elseif h.state == "run" then
			status, tone = `IN A RUN{if h.by then " · " .. string.upper(h.by) else ""}`, K.red
		elseif h.state == "lobby" then
			status, tone = `TAKEN{if h.by then " · " .. string.upper(h.by) .. "'S" else ""}`, AMBER
		end
		local tag = label(made, "State", status, 64, 72, each - 70, 18, 11, tone, true, true)
		tag.ZIndex = 5
	end
end

local function homeScreen(panel: Frame, view: { [string]: any })
	local W = PN.Width
	local create = button(panel, "Create", "", 16, 76, 280, 120, K.raised, K.text, function()
		state.house, state.difficulty, state.friends = nil, nil, false -- (each new lobby: public until picked)
		goTo("create")
	end)
	Ui.stroke(create, BLUE, 2)
	label(create, "Title", "＋ CREATE A LOBBY", 0, 24, 280, 26, 18, K.text, true).TextXAlignment = Enum.TextXAlignment.Center
	label(create, "Line1", "Pick a house and a difficulty", 0, 58, 280, 18, 13, K.secondary).TextXAlignment = Enum.TextXAlignment.Center
	label(create, "Line2", "Public, or for your friends", 0, 80, 280, 18, 13, K.secondary).TextXAlignment = Enum.TextXAlignment.Center
	label(panel, "HowTitle", "HOW IT WORKS", 16, 210, 280, 18, 13, K.secondary, true)
	wrapped(panel, "How", `• Up to {R.MaxParty} players a lobby\n• Everybody presses READY\n• The host presses START: {R.Party.Countdown} s, then the run\n• Walk around while you wait: only LEAVE takes you out`,
		16, 234, 280, 150, 13, K.text)
	-- the lobbies you may join (yours is the lobby screen's)
	local rows: { { [string]: any } } = {}
	for _, l in view.lobbies or {} do
		if l.mine ~= true then
			table.insert(rows, l)
		end
	end
	label(panel, "ListTitle", `OPEN LOBBIES · {#rows}`, 312, 72, W - 328, 20, 14, K.text, true)
	local list = Ui.make("ScrollingFrame", {
		Name = "Lobbies",
		Position = UDim2.fromOffset(312, 98),
		Size = UDim2.fromOffset(W - 328, PN.Height - 98 - 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.fromOffset(0, #rows * 72),
		ZIndex = 3,
	}, panel)
	local rowW = W - 328 - 8
	if #rows == 0 then
		wrapped(list, "Empty", "No open lobbies yet. Create one: your friends can join it here.", 8, 12, rowW - 16, 60, 14, K.secondary)
	end
	for n, l in rows do
		local row = Ui.make("Frame", { Name = `Lobby_{l.id}`, Position = UDim2.fromOffset(0, (n - 1) * 72), Size = UDim2.fromOffset(rowW, 64), BackgroundColor3 = K.row, BorderSizePixel = 0, ZIndex = 3 }, list)
		Ui.corner(row, 8)
		picture(row, l.house, 8, 8, 48)
		label(row, "Host", `{string.upper(tostring(l.hostName))}'S LOBBY`, 64, 8, rowW - 64 - 112, 22, 14, K.text, true, true)
		local def = RunRules.def(l.difficulty)
		local info = label(row, "Info", `{if l.friends then "👥 " else ""}{l.name} · {difficultyName(l.difficulty)} · {l.n}/{l.max}`, 64, 34, rowW - 64 - 112, 20, 12, K.secondary, false, true)
		if def then
			info.TextColor3 = K.secondary
		end
		local joinable = l.state == "open"
		local text = if l.state == "full" then "FULL" elseif l.state == "starting" then "STARTING" else "JOIN"
		local join = button(row, "Join", text, rowW - 104, 4, 96, BUTTON, if joinable then K.good else K.track, K.charcoal, if joinable then function()
			send({ kind = "join", id = l.id })
		end else nil)
		join.TextSize = if joinable then 15 else 11
	end
end

local function createScreen(panel: Frame, view: { [string]: any })
	local W = PN.Width
	label(panel, "HouseTitle", "1 · PICK A HOUSE", 16, 70, 300, 20, 14, K.text, true)
	houseCards(panel, view, 16, 96, 420, state.house, function(id: string)
		state.house = id
		state.key = ""
		drawPanel()
	end)
	local x, w = 448, W - 448 - 16
	label(panel, "DifficultyTitle", "2 · DIFFICULTY", x, 70, w, 20, 14, K.text, true)
	local picked = RunRules.clean(state.difficulty or R.Default)
	difficulties(panel, x, 96, w, picked, view.open or {}, function(id: string)
		state.difficulty = id
		state.key = ""
		drawPanel()
	end)
	label(panel, "WhoTitle", "3 · WHO CAN JOIN", x, 222, w, 20, 14, K.text, true)
	button(panel, "Friends", if state.friends then "👥 FRIENDS ONLY" else "🌍 PUBLIC: ANYBODY", x, 246, w, BUTTON, K.raised, if state.friends then GOLD else K.text, function()
		state.friends = not state.friends
		state.key = ""
		drawPanel()
	end)
	local ready = state.house ~= nil
	local make = button(panel, "Make", if ready then "CREATE LOBBY" else "PICK A HOUSE FIRST", x, 336, w, BUTTON, if ready then K.good else K.track, K.charcoal, if ready then function()
		send({ kind = "create", house = state.house, difficulty = picked, friends = state.friends })
	end else nil)
	make.TextSize = if ready then 16 else 12
end

local function lobbyScreen(panel: Frame, view: { [string]: any }, lobby: { [string]: any })
	local W = PN.Width
	local mine = lobby.mine == true
	local me = view.me
	local picking = state.screen == "house" and mine
	-- the left: the house (or the houses to pick from), the players
	if picking then
		label(panel, "HouseTitle", "PICK ANOTHER HOUSE", 16, 70, 300, 20, 14, K.text, true)
		houseCards(panel, view, 16, 96, 420, lobby.house, function(id: string)
			send({ kind = "house", id = id })
			goTo("lobby")
		end)
	else
		picture(panel, lobby.house, 16, 70, 56)
		label(panel, "House", string.upper(tostring(lobby.name)), 84, 70, 348, 24, 18, K.text, true, true)
		local def = RunRules.def(lobby.difficulty)
		label(panel, "Info", `{difficultyName(lobby.difficulty)} · {if lobby.friends then "FRIENDS ONLY" else "PUBLIC"} · {#lobby.members}/{lobby.max} PLAYERS`, 84, 96, 348, 18, 12,
			if def then rgb(def.color) else K.secondary, true, true)
		local line = label(panel, "Line", "", 84, 116, 348, 16, 12, K.secondary, true, true)
		ui.line = line
		label(panel, "PlayersTitle", "PLAYERS", 16, 138, 300, 18, 13, K.secondary, true)
		for n, m in lobby.members or {} do
			local y = 160 + (n - 1) * 60
			local row = Ui.make("Frame", { Name = `Member{n}`, Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(416, BUTTON), BackgroundColor3 = if m.id == me then K.raised else K.row,
				BorderSizePixel = 0, ZIndex = 3 }, panel)
			Ui.corner(row, 6)
			local kick = mine and m.id ~= me
			label(row, "Name", `{if m.host then "👑 " else ""}{m.name}{if m.id == me then " (YOU)" else ""}`, 12, 0, if kick then 220 else 300, BUTTON, 14, K.text, true, true)
			label(row, "Status", if m.ready then "✓ READY" else "NOT READY", if kick then 236 else 316, 0, 96, BUTTON, 12, if m.ready then K.good else K.secondary, true)
			if kick then
				local out = button(row, "Kick", "KICK", 416 - 80, 0, 80, BUTTON, K.row, K.red, function()
					send({ kind = "kick", id = m.id })
				end)
				Ui.stroke(out, K.red, 1)
				out.TextSize = 12
			end
		end
	end
	-- the right: the host's house and difficulty, or what the host does; READY, START / CANCEL
	local x, w = 448, W - 448 - 16
	local counting = type(lobby.endsAt) == "number"
	if mine then
		label(panel, "HouseTitle2", "HOUSE", x, 70, w, 18, 13, K.secondary, true)
		button(panel, "ChangeHouse", if picking then "‹ KEEP THIS HOUSE" else "CHANGE HOUSE", x, 92, w, BUTTON, K.raised, K.text, if counting then nil else function()
			goTo(if picking then "lobby" else "house")
		end).TextSize = 13
		label(panel, "DifficultyTitle", "DIFFICULTY", x, 156, w, 18, 13, K.secondary, true)
		difficulties(panel, x, 180, w, lobby.difficulty, lobby.open or {}, if counting then nil else function(id: string)
			send({ kind = "difficulty", id = id })
		end)
	else
		wrapped(panel, "HostDoes", `{lobby.hostName} picks the house and the difficulty and presses START. Press READY when you are set.`, x, 72, w, 100, 14, K.text)
		wrapped(panel, "Wander", "Walk around while you wait (your warehouse too): only LEAVE LOBBY takes you out.", x, 180, w, 80, 13, K.secondary)
	end
	local hint = wrapped(panel, "Why", if mine and not counting and lobby.why then tostring(lobby.why) else "", x, 302, w, 30, 12, GOLD)
	hint.TextYAlignment = Enum.TextYAlignment.Bottom
	local readyOn = false
	for _, m in lobby.members or {} do
		if m.id == me then
			readyOn = m.ready == true
		end
	end
	local half = math.floor((w - 6) / 2)
	local readyW = if mine then half else w
	local readyB = button(panel, "Ready", if readyOn then "✓ READY" else "READY", x, 336, readyW, BUTTON, if readyOn then K.good else K.raised, if readyOn then K.charcoal else K.text, function()
		send({ kind = "ready", on = not readyOn })
	end)
	readyB.TextSize = 15
	if not readyOn then
		Ui.stroke(readyB, K.good, 2)
	end
	if mine then
		if counting then
			button(panel, "Cancel", "CANCEL", x + half + 6, 336, w - half - 6, BUTTON, K.red, K.text, function()
				send({ kind = "cancel" })
			end).TextSize = 15
		else
			local go = lobby.canStart == true
			button(panel, "Start", "▶ START", x + half + 6, 336, w - half - 6, BUTTON, if go then BLUE else K.track, K.charcoal, function()
				send({ kind = "start" })
			end).TextSize = 15
		end
	end
end

-- The countdown's and READY's line (the panel's and the bar's), now.
local function lobbyLine(lobby: { [string]: any }): (string, Color3)
	if type(lobby.endsAt) == "number" then
		return `STARTING IN {math.max(0, math.ceil(lobby.endsAt - now()))}`, AMBER
	end
	local n = #(lobby.members or {})
	local ready = tonumber(lobby.ready) or 0
	if lobby.mine then
		return if lobby.canStart then `{ready}/{n} READY · PRESS START` else `{ready}/{n} READY · PRESS READY, THEN START`, K.good
	end
	return `{ready}/{n} READY · WAITING FOR {string.upper(tostring(lobby.hostName))}`, K.secondary
end

local function closePanel()
	if ui.panel then
		Ui.gamepadRelease(ui.panel)
		ui.panel:Destroy()
		ui.panel = nil
		ui.line = nil
	end
	state.key = ""
end

local function closeBar()
	if ui.bar then
		ui.bar:Destroy()
		ui.bar = nil
		ui.barLine = nil
	end
	state.barKey = ""
end

drawPanel = function()
	local root = screenGui()
	local view = state.view
	if not root or not view then
		closePanel()
		return
	end
	local lobby = view.lobby
	-- (a key of what it shows: the same, nothing drawn)
	local parts: { string } = { state.screen, tostring(state.house), tostring(state.difficulty), tostring(state.friends), tostring(Ui.touchLayout()) }
	for _, l in view.lobbies or {} do
		table.insert(parts, `{l.id}:{l.state}:{l.n}:{l.house}:{l.difficulty}`)
	end
	for _, h in view.houses or {} do
		table.insert(parts, `{h.id}:{h.state}:{h.by}`)
	end
	table.insert(parts, table.concat(view.open or {}, ","))
	if lobby then
		table.insert(parts, `L{lobby.id}:{lobby.house}:{lobby.difficulty}:{lobby.friends}:{lobby.endsAt}:{lobby.canStart}:{lobby.why}:{table.concat(lobby.open or {}, ",")}`)
		for _, m in lobby.members or {} do
			table.insert(parts, `{m.id}:{m.name}:{m.ready}`)
		end
	end
	local key = table.concat(parts, "|")
	if ui.panel and key == state.key then
		return
	end
	local first = ui.panel == nil
	state.key = key
	closePanel()
	state.key = key
	local W, H = PN.Width, PN.Height
	local panel = Ui.make("Frame", {
		Name = "PlayPanel",
		Size = UDim2.fromOffset(W, H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 2,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow() }, panel)
	Ui.corner(panel, 12)
	Ui.stroke(panel, BLUE, 2)
	ui.panel = panel
	-- the header: ▶ PLAY, what this screen is, ‹ BACK or LEAVE LOBBY, ✕
	label(panel, "Title", "▶ PLAY", 16, 10, 120, 40, 26, BLUE, true)
	local subtitle = if state.screen == "create" then "CREATE A LOBBY"
		elseif lobby and state.screen == "house" then "YOUR LOBBY · ITS HOUSE"
		elseif lobby then (if lobby.mine then "YOUR LOBBY" else `{string.upper(tostring(lobby.hostName))}'S LOBBY`)
		else "OPEN LOBBIES"
	label(panel, "Subtitle", subtitle, 136, 20, W - 136 - 62 - 160, 22, 15, K.secondary, true, true)
	local close = button(panel, "Close", "✕", W - 62, 3, BUTTON, BUTTON, K.charcoal, K.text, shutPanel)
	close.TextSize = 20
	Ui.stroke(close, K.rule, 1)
	if state.screen == "create" or (lobby and state.screen == "house") then
		button(panel, "Back", "‹ BACK", W - 62 - 126, 3, 120, BUTTON, K.charcoal, K.text, function()
			goTo(if lobby then "lobby" else "home")
		end).TextSize = 14
	elseif lobby then
		local leave = button(panel, "Leave", "LEAVE LOBBY", W - 62 - 156, 3, 150, BUTTON, K.charcoal, K.red, function()
			send({ kind = "leave" })
		end)
		leave.TextSize = 13
		Ui.stroke(leave, K.red, 1)
	end
	Ui.make("Frame", { Name = "HeaderLine", Position = UDim2.fromOffset(16, HEADER), Size = UDim2.new(1, -32, 0, 1), BackgroundColor3 = K.rule, BorderSizePixel = 0, ZIndex = 3 }, panel)
	if lobby then
		lobbyScreen(panel, view, lobby)
		local line = ui.line
		if line then
			local text, color = lobbyLine(lobby)
			line.Text, line.TextColor3 = text, color
		end
	elseif state.screen == "create" then
		createScreen(panel, view)
	else
		homeScreen(panel, view)
	end
	if first then
		local hook = PlayUi.onOpen
		if hook then
			pcall(hook)
		end
		local main = panel:FindFirstChild("Create") or panel:FindFirstChild("Ready") or close
		pcall(Ui.gamepadFocus, main :: any)
	end
end

-- ── The lobby bar ──────────────────────────────────────────────────────────

local function drawBar()
	local root = screenGui()
	local view = state.view
	if not root or not view then
		closeBar()
		return
	end
	local lobby = view.lobby
	local touch = Ui.touchLayout()
	local key = if lobby then `L{lobby.id}:{lobby.house}:{lobby.difficulty}:{lobby.endsAt}:{#(lobby.members or {})}:{lobby.ready}:{lobby.canStart}:{touch}` else `circle:{touch}`
	if ui.bar and key == state.barKey then
		return
	end
	closeBar()
	state.barKey = key
	local W = PN.Bar
	local bar = Ui.make("Frame", {
		Name = "PlayBar",
		Size = UDim2.fromOffset(W, BAR_H),
		Position = if touch then UDim2.new(1, -16, 0, 8) else UDim2.new(0.5, 0, 0, BAR_TOP),
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = barScale() }, bar)
	Ui.corner(bar, 10)
	Ui.stroke(bar, if lobby and lobby.endsAt then AMBER else BLUE, 2)
	ui.bar = bar
	if lobby then
		picture(bar, lobby.house, 10, 12, 44)
		label(bar, "House", `{string.upper(tostring(lobby.name))} · {difficultyName(lobby.difficulty)}`, 62, 10, W - 62 - 100, 22, 14, K.text, true, true)
		ui.barLine = label(bar, "Line", "", 62, 36, W - 62 - 100, 20, 12, K.secondary, true, true)
	else
		label(bar, "House", "▶ PLAY", 14, 10, W - 14 - 100, 22, 16, BLUE, true, true)
		label(bar, "Line", "CREATE A LOBBY OR JOIN ONE", 14, 36, W - 14 - 100, 20, 12, K.secondary, true, true)
	end
	local open = button(bar, "Open", "OPEN", W - 92, 6, 84, BUTTON, BLUE, K.charcoal, openPanel)
	open.TextSize = 15
end

-- The countdown's lines (the panel's and the bar's) every few tenths while a lobby counts down.
local function tick()
	local lobby = state.view and state.view.lobby
	if not lobby then
		return
	end
	local text, color = lobbyLine(lobby)
	for _, line in { ui.line, ui.barLine } do
		if line and line.Parent then
			if line.Text ~= text then
				line.Text = text
			end
			line.TextColor3 = color
		end
	end
end

local function startTicking()
	if state.ticking then
		return
	end
	state.ticking = true
	task.spawn(function()
		while state.ticking do
			task.wait(0.2)
			local lobby = state.view and state.view.lobby
			if not lobby or type(lobby.endsAt) ~= "number" then
				state.ticking = false
				break
			end
			pcall(tick)
		end
	end)
end

-- What shows now: the panel, the bar or nothing.
refresh = function()
	local view = state.view
	if not view then
		closePanel()
		closeBar()
		return
	end
	local panelShown = not state.shut and (view.circle == true or state.open)
	if panelShown then
		closeBar()
		drawPanel()
	else
		closePanel()
		drawBar()
	end
	tick()
	if view.lobby and type(view.lobby.endsAt) == "number" then
		startTicking()
	end
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onMessage(message: any)
	if type(message) ~= "table" or message.kind ~= "play" then
		return
	end
	if message.me == nil then
		state.view = nil
		state.screen, state.shut, state.open, state.was = "home", false, false, false
		refresh()
		return
	end
	local circle = message.circle == true
	if circle and not state.was then
		state.shut = false -- (stepping in opens it)
	end
	state.was = circle
	local had = state.view and state.view.lobby
	state.view = message
	if message.lobby then
		if state.screen == "home" or state.screen == "create" then
			state.screen = "lobby"
		end
		if not message.lobby.mine and state.screen == "house" then
			state.screen = "lobby"
		end
	else
		if state.screen == "lobby" or state.screen == "house" then
			state.screen = "home"
		end
		if had then
			state.open = false
		end
		if not circle then
			state.open = false
		end
	end
	refresh()
end

function PlayUi.view(): { [string]: any }?
	return state.view
end

function PlayUi.isOpen(): boolean
	return ui.panel ~= nil
end

function PlayUi.close()
	if ui.panel then
		shutPanel()
	end
end

function PlayUi.open()
	openPanel()
end

function PlayUi.screen(): string
	return state.screen
end

-- The circle's glow breathes (this screen only): its PlayGlow's transparency eased up and down.
local function breathe()
	task.spawn(function()
		local world = workspace:WaitForChild("Sandbox", 30)
		local lobby = world and world:WaitForChild("Lobby", 30)
		local circle = lobby and lobby:WaitForChild("PlayCircle", 30)
		local glow = circle and circle:FindFirstChild("PlayGlow")
		if glow and glow:IsA("BasePart") then
			local info = TweenInfo.new(R.Play.Pulse / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			pcall(function()
				TweenService:Create(glow, info, { Transparency = 0.55 }):Play()
			end)
		end
	end)
end

function PlayUi.start()
	if not Config.Sandbox.On or remote then
		return
	end
	local r = Net.get("Party")
	remote = r
	r.OnClientEvent:Connect(onMessage)
	-- (a resize: the panel and the bar at the new scale)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			for _, pair in { { ui.panel, scaleNow() }, { ui.bar, barScale() } } do
				local frame = pair[1]
				local scale = if frame then frame:FindFirstChild("Scale") else nil
				if scale and scale:IsA("UIScale") then
					scale.Scale = pair[2]
				end
			end
		end)
	end
	pcall(breathe)
	r:FireServer({ kind = "state" })
end

return PlayUi
