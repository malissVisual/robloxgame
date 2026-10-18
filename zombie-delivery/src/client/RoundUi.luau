--!strict
-- 10.5 ROUNDS, the client (server/Runs.luau decides everything; Config.Rounds; the rules shared/RoundRules.luau): the
-- round on your screen. Presentation only: the Runs remote's { kind = "round", … } and { kind = "claim", … }.
--   * Where: everything kept clear of the HUD (SandboxHud's money and chips, Hud's groups, the touch controls, the move's
--     panel and what else holds the top's middle: client/TopBlocks.luau, the corner map, Roblox's player list).
--   * The lobby's banner (the top's middle, under what holds it there): the countdown to the next round, its place and
--     difficulty ("NEXT QUICK ROUND · 0:42" over "THE OLD MILL · HARD"), how many are in the queue and what to do;
--     while a round is on without you, where and how long ("QUICK ROUND · 3:12 LEFT" over "ON AT THE OLD MILL"); after
--     one, that the next one is coming. 10.6 both in PLAY: only while you are in the queue (the PLAY panel's QUICK
--     ROUND: the view's `ready`), never while the PLAY panel is open (it says the same); its LEAVE QUEUE (the Runs
--     remote's { kind = "queue", on = false }) takes you out. On a phone at Config.Rounds.Banner.TouchScale at least
--     (LEAVE QUEUE a finger's size). 10.6 snatching's look: wider (up to 560 px; a small phone's narrower, so that it
--     stays high and clear of the HUD), its words scaled to fit, never cut (a long place's name).
--   * In the round: the table at the screen's left (its first Config.Rounds.Top rows: place, name, pieces, value; your
--     row lit, and under them when you are further down) and the feed under it (who took what: yours in gold, the
--     latest on top, each for FEED s; 10.6 the snatches too: "🤼 Bob snatched … from Ann!", "💪 Ann held on to …"). The
--     clock is the move's panel's (client/MovingHud.luau).
--   * Your van: its name tag (the server's RoundVanTag over it) says YOUR VAN for you, in gold and seen through walls.
--   * The last seconds of the countdown tick; your own Load rings.
--   RoundUi.start()   the remote, the screen
--   RoundUi.view()    the round's view now (the server's) or nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RoundRules = require(Shared.RoundRules)
local RunRules = require(Shared.RunRules)
local MoveLayout = require(script.Parent.MoveLayout)
local Theme = require(script.Parent.Theme)
local TopBlocks = require(script.Parent.TopBlocks)
local TouchLayout = require(script.Parent.TouchLayout)
local Ui = require(script.Parent.Ui)

local RoundUi = {}

local Q = Config.Rounds
local K = Theme.Contract
local GOLD = Color3.fromRGB(255, 206, 92)
local MONEY = Color3.fromRGB(140, 220, 120)
local BANNER_W, BANNER_H = 560, 64 -- px at scale 1 (10.6: LEAVE QUEUE at its right; wide for a long place's name)
local BANNER_FITS = { 560, 480, 400 } -- px at scale 1: its widths, the highest spot clear of the HUD wins (a small phone: narrower)
local LEAVE_W = 64 -- px at scale 1: LEAVE QUEUE (64 × 56: a finger's size at the touch scale)
local BOARD_W, ROW = 236, 22
local FEED, FEED_MAX = 6, 4 -- s a feed line shows, lines at most
local TICK = 5 -- the countdown's last seconds tick
local MEDAL = { "🥇", "🥈", "🥉" }
local GAP = 10 -- px between what it keeps clear of and it
local CHIP_GUIS = { SandboxHud = "MoneyBlock", SandboxTasksChip = "", SandboxMiniMap = "MiniMap", PlayUi = "PlayBar" } -- (the HUD's chips, the corner map; 10.6 the PLAY bar)
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "BottomBar", "KeyHints" } -- (client/Hud.luau's)

local player = Players.LocalPlayer
local view: { [string]: any }? = nil
local gui: ScreenGui? = nil
local banner: Frame? = nil
local board: Frame? = nil
local feed: Frame? = nil
local lines: { { text: string, mine: boolean, at: number } } = {}
local boardKey = ""
local ticked = -1
local started = false

local function play(name: string)
	pcall(function()
		require(script.Parent.Sounds).play(name)
	end)
end

local function scaleNow(): number
	return math.min(Ui.screenScale(), 1)
end

-- 10.6: the banner's scale: a phone's Banner.TouchScale at least (LEAVE QUEUE a finger's size), never past 1.
local function bannerScale(): number
	local s = Ui.screenScale()
	if Ui.touchLayout() then
		s = math.max(s, Q.Banner.TouchScale)
	end
	return math.min(s, 1)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local made = Ui.make("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	for key, value in props do
		(made :: any)[key] = value
	end
	return made
end

local function build(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local root = Ui.make("ScreenGui", { Name = "RoundUi", ResetOnSpawn = false, DisplayOrder = 18, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	gui = root
	local b = Ui.make("Frame", {
		Name = "Banner",
		Size = UDim2.fromOffset(BANNER_W, BANNER_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = bannerScale() }, b)
	Ui.corner(b, 10)
	Ui.stroke(b, GOLD, 1.5)
	-- (its words scaled to fit, never cut: a long place's name, a phone; they and LEAVE QUEUE follow its width, layout's)
	local wordsOff = -(LEAVE_W + 28) -- (their width: the banner's less LEAVE QUEUE and the margins)
	local kicker = text(b, "Kicker", { Size = UDim2.new(1, wordsOff, 0, 14), Position = UDim2.fromOffset(12, 5), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = K.secondary,
		TextScaled = true, TextTruncate = Enum.TextTruncate.None })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 11, MinTextSize = 8 }, kicker)
	local title = text(b, "Title", { Size = UDim2.new(1, wordsOff, 0, 22), Position = UDim2.fromOffset(12, 19), Font = Theme.HeadingFont, TextSize = 16, TextColor3 = GOLD,
		TextScaled = true, TextTruncate = Enum.TextTruncate.None })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 10 }, title)
	local line = text(b, "Line", { Size = UDim2.new(1, wordsOff, 0, 16), Position = UDim2.fromOffset(12, 43), TextSize = 12, TextColor3 = K.secondary,
		TextScaled = true, TextTruncate = Enum.TextTruncate.None })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, line)
	local leave = Ui.make("TextButton", { Name = "Leave", Text = "LEAVE QUEUE", Size = UDim2.fromOffset(LEAVE_W, 56), Position = UDim2.new(1, -LEAVE_W - 4, 0, 4),
		BackgroundColor3 = K.charcoal, AutoButtonColor = true, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.red, TextWrapped = true }, b)
	Ui.corner(leave, 8)
	Ui.stroke(leave, K.red, 1)
	leave.Activated:Connect(function() -- 10.6: out of the quick round's queue (the server says so)
		Net.get("Runs"):FireServer({ kind = "queue", on = false })
	end)
	banner = b
	local t = Ui.make("Frame", {
		Name = "Board",
		Size = UDim2.fromOffset(BOARD_W, 30),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.42, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Visible = false,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow() }, t)
	Ui.corner(t, 8)
	board = t
	local f = Ui.make("Frame", {
		Name = "Feed",
		Size = UDim2.fromOffset(BOARD_W + 60, FEED_MAX * 20),
		Position = UDim2.new(0, 12, 0.42, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow() }, f)
	feed = f
	return root
end

-- ── The lobby's banner ─────────────────────────────────────────────────────

local function difficultyName(id: any): string
	local def = RunRules.def(id)
	return if def then string.upper(def.name) else ""
end

-- The banner's words now: (title?, line, kicker); no title: no banner.
local function bannerText(v: { [string]: any }, left: number): (string?, string, string)
	local name = string.upper(tostring(v.name or ""))
	local count = tonumber(v.queued) or tonumber(v.players) or 0
	if v.phase == "wait" and v.name then
		return `{name} · {difficultyName(v.difficulty)}`, `{count} queued · your own van: what you load is yours`, `NEXT QUICK ROUND · {RoundRules.clock(left)}`
	elseif v.phase == "wait" then
		return "WAITING FOR A FREE HOUSE", `{count} queued · every house is in use right now`, "NEXT QUICK ROUND"
	elseif v.phase == "play" and v.inRound ~= true then
		return `ON AT {name}`, "You go in the next one: walk around meanwhile", `QUICK ROUND · {RoundRules.clock(left)} LEFT`
	elseif v.phase == "over" and v.inRound ~= true then
		return "THE NEXT ONE IS COMING", "You are still in the queue", "QUICK ROUND OVER"
	end
	return nil, "", ""
end

-- 10.6: the PLAY panel open (it shows the quick round itself): no banner.
local function panelOpen(): boolean
	local ok, open = pcall(function(): any
		return require(script.Parent.PlayUi).isOpen()
	end)
	return ok and open == true
end

-- ── The table and the feed ─────────────────────────────────────────────────

local function rowText(row: { [string]: any }): string
	local place = tonumber(row.place) or 0
	local medal = MEDAL[place] or `{place}.`
	return `{medal} {row.name or "?"}`
end

local function drawBoard(v: { [string]: any })
	local t = board
	if not t then
		return
	end
	local top = if type(v.top) == "table" then v.top else {}
	local mine = if type(v.mine) == "table" then v.mine else nil
	local inTop = false
	for _, row in top do
		inTop = inTop or row.me == true
	end
	local key = `{#top}|{mine and mine.place}|{mine and mine.value}`
	for _, row in top do
		key ..= `|{row.name},{row.place},{row.count},{row.value}`
	end
	if key == boardKey then
		return
	end
	boardKey = key
	for _, child in t:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	text(t, "Head", { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 4), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = GOLD, Text = "🏁 THE ROUND · TOP" })
	local y = 26
	local function add(row: { [string]: any }, me: boolean)
		local line = Ui.make("Frame", { Name = "Row", Size = UDim2.new(1, -8, 0, ROW - 2), Position = UDim2.fromOffset(4, y), BackgroundColor3 = K.raised,
			BackgroundTransparency = if me then 0.1 else 1, BorderSizePixel = 0 }, t)
		Ui.corner(line, 4)
		text(line, "Who", { Size = UDim2.new(1, -112, 1, 0), Position = UDim2.fromOffset(6, 0), Font = if me then Theme.HeadingFont else Theme.Font, TextSize = 12,
			TextColor3 = if me then GOLD else K.text, Text = rowText(row) })
		text(line, "Count", { Size = UDim2.fromOffset(36, ROW - 2), Position = UDim2.new(1, -104, 0, 0), TextSize = 11, TextColor3 = K.secondary,
			TextXAlignment = Enum.TextXAlignment.Right, Text = `📦{tonumber(row.count) or 0}` })
		text(line, "Value", { Size = UDim2.fromOffset(62, ROW - 2), Position = UDim2.new(1, -66, 0, 0), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = MONEY,
			TextXAlignment = Enum.TextXAlignment.Right, Text = Ui.money(tonumber(row.value) or 0) })
		y += ROW
	end
	for _, row in top do
		add(row, row.me == true)
	end
	if mine and not inTop then
		y += 2
		add({ place = mine.place, name = "You", count = mine.count, value = mine.value }, true)
	end
	if #top == 0 then
		text(t, "Empty", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, y), TextSize = 12, TextColor3 = K.secondary, Text = "Nobody has loaded anything yet" })
		y += ROW
	end
	t.Size = UDim2.fromOffset(BOARD_W, y + 4)
end

local function drawFeed()
	local f = feed
	if not f then
		return
	end
	for _, child in f:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local now = os.clock()
	for n, line in lines do
		local label = text(f, `Line{n}`, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(4, (n - 1) * 20), TextSize = 12, Font = Theme.HeadingFont,
			TextColor3 = if line.mine then GOLD else K.text, TextStrokeTransparency = 0.5, Text = line.text })
		label.TextTransparency = math.clamp((now - line.at - (FEED - 1)) / 1, 0, 1)
	end
end

local function onClaim(m: { [string]: any })
	local value = Ui.money(tonumber(m.value) or 0)
	local tier = if type(m.rarity) == "string" then Config.Collection.Tiers[m.rarity] else nil
	local tag = if tier and m.rarity ~= "common" then ` {string.upper(tier.name)}` else ""
	local said = if m.mine == true then `+ {m.icon or "📦"}{tag} {m.name or ""} is yours · {value}` else `{m.by or "?"} took{tag} {m.name or ""} · {value}`
	table.insert(lines, 1, { text = said, mine = m.mine == true, at = os.clock() })
	while #lines > FEED_MAX do
		table.remove(lines)
	end
	if m.mine == true then
		play("task_done")
	end
	drawFeed()
end

-- ── Your van ───────────────────────────────────────────────────────────────

local function markVan()
	local cars = workspace:FindFirstChild("Cars")
	if not cars then
		return
	end
	for _, model in cars:GetChildren() do
		if model:GetAttribute("RoundVan") == player.UserId then
			local tag = model:FindFirstChild("RoundVanTag", true)
			local words = tag and tag:FindFirstChild("Words")
			if tag and tag:IsA("BillboardGui") and words and words:IsA("TextLabel") and words.Text ~= "⬇ YOUR VAN" then
				words.Text = "⬇ YOUR VAN"
				words.TextColor3 = GOLD
				tag.AlwaysOnTop = true
				tag.MaxDistance = 400
			end
		end
	end
end

-- ── Where ────────────────────────────────────────────────────────────────────

-- What the banner and the table keep clear of: their boxes relative to `origin`.
local function blockers(origin: Vector2, W: number, H: number, S: number): { TouchLayout.Box }
	local list: { TouchLayout.Box } = {}
	local function add(object: Instance?)
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
			local at, size = object.AbsolutePosition - origin, object.AbsoluteSize
			table.insert(list, TouchLayout.box(at.X, at.Y, at.X + size.X, at.Y + size.Y))
		end
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	for guiName, piece in CHIP_GUIS do
		local holder = playerGui and playerGui:FindFirstChild(guiName)
		if holder and (holder :: any).Enabled ~= false then
			if piece ~= "" then
				add(holder:FindFirstChild(piece, true))
			else
				for _, child in holder:GetChildren() do
					add(child)
				end
			end
		end
	end
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	for _, name in HUD_GROUPS do
		add(hud and hud:FindFirstChild(name))
	end
	for _, r in TopBlocks.rects(origin) do
		table.insert(list, r)
	end
	if Ui.touchLayout() then
		local cluster = TouchLayout.cluster(W, H, S)
		for _, b in TouchLayout.buttons(cluster) do
			table.insert(list, b)
		end
		table.insert(list, cluster.thumb)
		table.insert(list, cluster.jump)
	else
		table.insert(list, TouchLayout.box(W - 16 - MoveLayout.PLAYER_LIST_W, 0, W, math.min(H * 0.45, 52 + 40 * #Players:GetPlayers())))
	end
	return list
end

-- A `w` × `h` box at x0 going down from y0 until nothing in `list` is under it (nil: no room on the screen).
local function slide(x0: number, y0: number, w: number, h: number, H: number, list: { TouchLayout.Box }): TouchLayout.Box?
	local b = TouchLayout.box(x0, y0, x0 + w, y0 + h)
	for _ = 1, 16 do
		local moved = false
		for _, other in list do
			if TouchLayout.overlap(b, other) then
				b = TouchLayout.box(b.x0, other.y1 + GAP, b.x1, other.y1 + GAP + h)
				moved = true
			end
		end
		if not moved then
			return if b.y1 <= H - GAP then b else nil
		end
	end
	return nil
end

-- The banner in the top's middle (under what holds it), the table at the left (else the right) under what is there,
-- the feed under the table.
local function layout(root: ScreenGui, S: number)
	local origin = root.AbsolutePosition
	local size = root.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 2 or H < 2 then
		return
	end
	local list = blockers(origin, W, H, S)
	local b = banner
	if b and b.Visible then
		local BS = bannerScale()
		local h = BANNER_H * BS
		local best: TouchLayout.Box?, bestW = nil, BANNER_W
		for _, bw in BANNER_FITS do -- (the highest spot wins, the wider on a tie: wide on a big screen, narrower on a small phone)
			local w = bw * BS
			local spot = slide(W / 2 - w / 2, GAP, w, h, H, list)
			if spot and (not best or spot.y0 < best.y0 - 0.5) then
				best, bestW = spot, bw
			end
		end
		if best then
			b.Size = UDim2.fromOffset(bestW, BANNER_H)
			b.AnchorPoint = Vector2.new(0, 0)
			b.Position = UDim2.fromOffset(math.floor(best.x0 + 0.5), math.floor(best.y0 + 0.5))
		end
	end
	local t, f = board, feed
	if t and f and t.Visible then
		local w, h = BOARD_W * S, t.Size.Y.Offset * S
		local spot = slide(GAP, GAP, w, h, H, list) or slide(W - GAP - w, GAP, w, h, H, list)
		if spot then
			t.AnchorPoint = Vector2.new(0, 0)
			t.Position = UDim2.fromOffset(math.floor(spot.x0 + 0.5), math.floor(spot.y0 + 0.5))
			table.insert(list, spot)
			local fw, fh = (BOARD_W + 60) * S, FEED_MAX * 20 * S
			local under = slide(spot.x0, spot.y1 + 4 * S, math.min(fw, W - spot.x0 - GAP), fh, H, list)
			f.Position = if under then UDim2.fromOffset(math.floor(under.x0 + 0.5), math.floor(under.y0 + 0.5)) else f.Position
			f.Size = UDim2.fromOffset(math.min(BOARD_W + 60, (W - spot.x0 - GAP) / S), FEED_MAX * 20)
			f.Visible = f.Visible and under ~= nil
		end
	end
end

-- ── The loop ───────────────────────────────────────────────────────────────

local nextVanLook = 0
local function refresh()
	local root = build()
	local v = view
	if not root or not v then
		return
	end
	local S = scaleNow()
	for _, frame in { banner, board, feed } :: { Frame? } do
		local scale = frame and frame:FindFirstChild("Scale")
		local want = if frame == banner then bannerScale() else S
		if scale and scale:IsA("UIScale") and scale.Scale ~= want then
			scale.Scale = want
		end
	end
	local now = workspace:GetServerTimeNow()
	local left = (tonumber(v.endsAt) or now) - now
	local title, line, kicker = bannerText(v, left)
	local b = banner
	if b then
		b.Visible = v.ready == true and title ~= nil and not panelOpen()
		local head, foot, top = b:FindFirstChild("Title"), b:FindFirstChild("Line"), b:FindFirstChild("Kicker")
		if title and head and foot and top and head:IsA("TextLabel") and foot:IsA("TextLabel") and top:IsA("TextLabel") then
			head.Text = title
			foot.Text = line
			top.Text = kicker
		end
	end
	if v.phase == "wait" and v.ready == true then
		local whole = math.ceil(left)
		if whole <= TICK and whole >= 1 and whole ~= ticked then
			ticked = whole
			play("ui_click")
		end
	end
	local playing = v.phase == "play" and v.inRound == true
	local t, f = board, feed
	if t and f then
		t.Visible = playing
		drawBoard(v)
		local fresh = #lines > 0 and os.clock() - lines[1].at < FEED
		f.Visible = playing and fresh
	end
	layout(root, S)
	if f and f.Visible then
		drawFeed()
	end
	if playing and os.clock() >= nextVanLook then
		nextVanLook = os.clock() + 1
		markVan()
	end
end

local function onMessage(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "round" then
		local was = view
		view = message
		if was and was.phase ~= "play" and message.phase == "play" and message.inRound == true then
			table.clear(lines)
			boardKey = ""
		end
		refresh()
	elseif message.kind == "claim" then
		onClaim(message)
		refresh()
	elseif message.kind == "snatch" then -- 10.6 snatching: who took what from whom (or held on to it)
		local said = if message.took == true then `🤼 {message.by or "?"} snatched {message.name or ""} from {message.from or "?"}!`
			else `💪 {message.from or "?"} held on to {message.name or ""} ({message.by or "?"} tried)`
		table.insert(lines, 1, { text = said, mine = message.mine == true, at = os.clock() })
		while #lines > FEED_MAX do
			table.remove(lines)
		end
		drawFeed()
		refresh()
	end
end

function RoundUi.view(): { [string]: any }?
	return view
end

function RoundUi.start()
	if started or not Q.On then
		return
	end
	started = true
	Net.get("Runs").OnClientEvent:Connect(onMessage)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		refresh()
	end)
end

return RoundUi
