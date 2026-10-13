--!strict
-- 7.0, the moves' story on screen ("The Last Move": the words are shared/MoveStory.luau's; client/MovingHud.luau calls
-- in at its MoveStory hooks). In the 6.18 UI kit's look (client/CardKit.luau: charcoal cards, the red primary, chips).
--
--   * The story cards, cutscene-like: a dim veil with black bars at the top and the bottom, and a card low in the
--     middle (in the middle on a touch screen, never wider than the screen): the speaker's portrait
--     (client/Portrait.luau: their NPC's bust over the chapter's colour; Dana of Big Move Movers a mover's over dark
--     red), their name and role in small caps, the line big; the page (2 / 5), SKIP and NEXT › (the last page says the
--     sequence's own action).
--     Space / Enter / the gamepad's A or a tap on the card is NEXT (client/DialogKeys.luau); ✕ only where there is a
--     way back.
--       MoveStoryUi.intro(after) -> boolean
--           Marge's intro (MoveStory.Intro) the first time the Moving contracts board opens: the player attribute
--           MoveStory (server/PlayerData.luau) without "intro", and not shown this game yet. At its end (or SKIP) the
--           server keeps it seen (the Tutorial remote's ("story", "intro"): server/Tutorial.luau) and `after` runs (the
--           contract card). False: no intro due, nothing shown (the caller goes on itself).
--       MoveStoryUi.briefing(contract, go, back?)
--           the contract's chapter's briefing before START (once a game for each chapter), Big Move Movers' taunt on
--           the radio its last card: ▶ START THE MOVE or SKIP run `go` (the card's START), ✕ runs `back` (the card
--           again). No chapter, or briefed already this game: `go` at once.
--   * MoveStoryUi.chapters(body, order, contract, open?, onPlay?)   the contract card's CHAPTERS: the story road as a
--     strip of tiles that scrolls sideways (the client's portrait, PROLOGUE / CHAPTER n / FINALE, ▶ PLAY, 🔒 LOCKED or
--     🔒 SOON, the title, the client), the contract's own chapter lit; a tap on a tile shows its words under the strip
--     (a playable one: the client's blurb; a locked one: what to finish first; the others: their hook). 7.x farm move:
--     `open` (the card's contracts: id → open) says which chapters play (else the player's save flags, the attribute
--     MoveStory: a chapter opens once the chapters before it are done); a tap on another playable chapter's tile also
--     runs onPlay(its contract) (the card asks the server for that contract's card).
--   * MoveStoryUi.thanks(body, order, result, contract)   the client's line on the result card for the outcome
--     (MoveStory.thanksLine: great / ok / late / failed) by their small portrait.
-- MoveStoryUi.isOpen(): a story card is up (MovingHud.isOpen says so: the mouse is free). Presentation only: the only
-- thing it asks of the server is to keep the intro seen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MoveStory = require(Shared.MoveStory)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local Portrait = require(script.Parent.Portrait)
local DialogKeys = require(script.Parent.DialogKeys)

local MoveStoryUi = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local C = CardKit.Color
local TUNE = Config.MoveStory
local KEYS_ID = "movestory" -- the story card's entry in client/DialogKeys.luau
local CARD_W = 580 -- a story card (unscaled), narrower on a small screen
local FACE = 112 -- the speaker's portrait on a story card
local BARS = 0.07 -- the black bars, a share of the screen's height each
local MARGIN = 16 -- (unscaled) the least room round a story card
local TILE_W, TILE_H = 128, 84 -- a chapter's tile on the contract card
local THUMB = 36 -- the portrait on a tile
local QUOTE = 46 -- the portrait by the result card's thanks
local ORANGE = Color3.fromRGB(240, 132, 44) -- ZDC Moving's colour (the board, client/MovingHud.luau)

type Sequence = {
	lines: { MoveStory.Line },
	heading: string, -- over every card ("PROLOGUE · EVERYTHING MUST GO")
	color: Color3, -- the portraits' backdrop and the card's edge
	finish: string, -- the last page's action
	onDone: () -> (), -- the last page's action or SKIP
	onBack: (() -> ())?, -- ✕ (nil: no ✕)
}

local gui: ScreenGui? = nil
local shown: { seq: Sequence, page: number, root: any }? = nil
local introShown = false -- (once a game, whatever the attribute says: the server's answer may be on its way)
local briefed: { [string]: boolean } = {} -- chapter id → briefed this game

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function sound(name: string)
	pcall(function()
		(require(script.Parent.Sounds) :: any).play(name, 0.6)
	end)
end

local function screen(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", {
		Name = "MoveStory",
		ResetOnSpawn = false,
		IgnoreGuiInset = true, -- (the bars reach the screen's edges)
		DisplayOrder = 8, -- over client/MovingHud.luau's cards (7)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

local function text(parent: Instance, value: string, size: UDim2, props: { [string]: any }): any
	local label = Ui.label(parent, value, size, { Font = Theme.Font, TextSize = 14, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	for key, prop in props do
		label[key] = prop
	end
	return label
end

-- ── The story cards ─────────────────────────────────────────────────────────

local draw: () -> ()

function MoveStoryUi.close()
	local current = shown
	shown = nil
	DialogKeys.close(KEYS_ID)
	if current and current.root then
		current.root:Destroy()
	end
end

function MoveStoryUi.isOpen(): boolean
	return shown ~= nil
end

local function finish(seq: Sequence)
	MoveStoryUi.close()
	seq.onDone()
end

local function advance()
	local current = shown
	if not current then
		return
	end
	if current.page < #current.seq.lines then
		current.page += 1
		sound("cycle")
		draw()
	else
		finish(current.seq)
	end
end

-- A plain caps action (SKIP): a finger tall on touch.
local function quietAction(parent: Instance, value: string, height: number, order: number, onClick: () -> ()): any
	local button = Ui.make("TextButton", {
		Name = "Skip",
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = value,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.secondary,
		LayoutOrder = order,
		ZIndex = 5,
	}, parent)
	button.Activated:Connect(function()
		CardKit.click()
		onClick()
	end)
	return button
end

draw = function()
	local current = shown
	local root = screen()
	if not current or not root then
		return
	end
	if current.root then
		current.root:Destroy()
	end
	local seq = current.seq
	local line = seq.lines[current.page]
	local radio = line.who == MoveStory.Villain.id
	local person = MoveStory.speaker(line.who)
	local touch = Ui.touchLayout()
	local action = if touch then 52 else 40
	-- the size: readable on a phone (at least 0.8), never wider than the screen
	local size = Ui.screenSize()
	local scale = math.max(Ui.screenScale(), 0.8)
	local width = math.min(CARD_W, size.X / scale - 2 * MARGIN)
	local face = if width < 440 then 84 else FACE
	-- the veil (a tap on it does nothing: the card is the button) and the bars
	local veil = Ui.make("TextButton", {
		Name = "StoryVeil",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
	}, root)
	current.root = veil
	for _, top in { true, false } do
		Ui.make("Frame", {
			Name = if top then "BarTop" else "BarBottom",
			Size = UDim2.fromScale(1, BARS),
			Position = UDim2.fromScale(0, if top then 0 else 1 - BARS),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 2,
		}, veil)
	end
	local card = Ui.make("TextButton", {
		Name = "StoryCard",
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = if touch then Vector2.new(0.5, 0.5) else Vector2.new(0.5, 1),
		Position = if touch then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.5, 0, 1 - BARS, -MARGIN),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 3,
	}, veil)
	Ui.make("UIScale", { Name = "Scale", Scale = scale }, card)
	Ui.corner(card, 12)
	local edge = if radio then rgb(MoveStory.Villain.color) else seq.color
	Ui.make("UIStroke", { Color = edge, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 12) }, card)
	card.Activated:Connect(advance)
	-- the rows in a list (the ✕ over the card's corner is not one of them)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 4 }, card)
	Ui.list(body, true, 10)
	-- the speaker and the line
	local top = Ui.make("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 4 }, body)
	local holder = Ui.make("Frame", { Name = "Face", Size = UDim2.fromOffset(face, face), BackgroundTransparency = 1, ZIndex = 4 }, top)
	if person then
		Portrait.mount(holder, { person }, edge, { key = `story:{person.id}:{edge:ToHex()}` })
	else
		Portrait.flat(holder, edge, nil, false)
	end
	local words = Ui.make("Frame", {
		Name = "Words",
		Size = UDim2.new(1, -(face + 14), 0, 0),
		Position = UDim2.fromOffset(face + 14, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, top)
	Ui.list(words, true, 4)
	local heading = if radio then "📻 ON THE RADIO · BIG MOVE MOVERS" else seq.heading
	text(words, heading, UDim2.new(1, 0, 0, 14), { Name = "Heading", Font = Theme.HeadingFont, TextSize = 11, TextColor3 = edge, LayoutOrder = 1, ZIndex = 4 })
	text(words, string.upper(if person then person.name else line.who), UDim2.new(1, 0, 0, 18), { Name = "Speaker", Font = Theme.HeadingFont, TextSize = 15, TextColor3 = C.title, LayoutOrder = 2, ZIndex = 4 })
	text(words, if person then MoveStory.roleOf(person) else "", UDim2.new(1, 0, 0, 14), { Name = "Role", TextSize = 11, TextColor3 = C.faint, LayoutOrder = 3, ZIndex = 4 })
	Ui.make("Frame", { Name = "Rule", Size = UDim2.fromOffset(28, 2), BackgroundColor3 = K.red, BorderSizePixel = 0, LayoutOrder = 4, ZIndex = 4 }, words)
	text(words, line.text, UDim2.new(1, 0, 0, 0), {
		Name = "Line",
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = if touch then 17 else 18,
		LineHeight = 1.1,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextColor3 = K.text,
		LayoutOrder = 5,
		ZIndex = 4,
	})
	-- the footer: the page and SKIP on the left, NEXT on the right
	local footer = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, 0, 0, action), BackgroundTransparency = 1, LayoutOrder = 2, ZIndex = 4 }, body)
	local left = Ui.make("Frame", { Name = "Left", Size = UDim2.fromScale(0.45, 1), BackgroundTransparency = 1, ZIndex = 4 }, footer)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	local count = #seq.lines
	text(left, `{current.page} / {count}`, UDim2.fromOffset(44, action), { Name = "Page", Font = Theme.MonoFont, TextSize = 12, TextColor3 = C.faint, LayoutOrder = 1, ZIndex = 5 })
	if current.page < count then
		quietAction(left, "SKIP ››", action, 2, function()
			finish(seq)
		end)
	end
	local last = current.page >= count
	local nextWidth = math.min(240, math.max(130, CardKit.width(seq.finish, 14, Theme.HeadingFont) + 36))
	local holderNext = Ui.make("Frame", {
		Name = "NextHolder",
		Size = UDim2.new(0, nextWidth, 1, 0),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, footer)
	local nextButton = CardKit.bigButton(holderNext, {
		name = "Next",
		text = if last then seq.finish else "NEXT ›",
		kind = if last then "good" else "primary",
		height = action,
		textSize = 14,
		z = 5,
		silent = true,
		onClick = advance,
	})
	nextButton.Size = UDim2.fromScale(1, 1)
	local back = seq.onBack
	if back then
		local close = Ui.closeButton(card, function()
			MoveStoryUi.close()
			back()
		end)
		close.Position = UDim2.new(1, 10, 0, -10)
		close.ZIndex = 6
	end
	Ui.gamepadFocus(nextButton)
	DialogKeys.open(KEYS_ID, advance, { guard = TUNE.Guard, layer = 2 })
end

local function play(seq: Sequence)
	MoveStoryUi.close()
	if #seq.lines == 0 then
		seq.onDone()
		return
	end
	shown = { seq = seq, page = 1, root = nil }
	sound("notify")
	draw()
end

-- Is Marge's intro due? (The attribute comes with the profile: none yet means not loaded, so no intro.)
local function introDue(): boolean
	local seen = player:GetAttribute("MoveStory")
	return not introShown and type(seen) == "string" and MoveStory.decodeSeen(seen).intro ~= true
end

function MoveStoryUi.intro(after: () -> ()): boolean
	if not introDue() then
		return false
	end
	introShown = true
	play({
		lines = MoveStory.Intro,
		heading = string.upper(MoveStory.Company),
		color = ORANGE,
		finish = "SHOW ME THE JOB",
		onDone = function()
			pcall(function()
				Net.get("Tutorial"):FireServer("story", "intro")
			end)
			after()
		end,
		onBack = nil,
	})
	return true
end

-- The chapter's briefing with Big Move Movers on the radio as its last card.
function MoveStoryUi.briefing(contract: any, go: () -> (), back: (() -> ())?): boolean
	local chapter = MoveStory.forContract(contract)
	if not chapter or briefed[chapter.id] then
		go()
		return false
	end
	local lines = table.clone(chapter.briefing)
	table.insert(lines, { who = MoveStory.Villain.id, text = chapter.taunt })
	play({
		lines = lines,
		heading = `{MoveStory.label(chapter)} · {string.upper(chapter.title)}`,
		color = rgb(chapter.color),
		finish = "▶ START THE MOVE",
		onDone = function()
			briefed[chapter.id] = true
			go()
		end,
		onBack = back,
	})
	return true
end

-- ── The contract card's CHAPTERS ────────────────────────────────────────────

-- 7.x farm move: a chapter's state on the card: "play" | "locked" | "soon" (`open`: the card's contracts, else the save).
local function stateOf(chapter: MoveStory.Chapter, open: { [string]: boolean }?): string
	local contract = chapter.contract
	if chapter.soon == true or contract == nil then
		return "soon"
	elseif open then
		return if open[contract] == true then "play" else "locked"
	end
	local seen = player:GetAttribute("MoveStory")
	return MoveStory.status(chapter, if type(seen) == "string" then MoveStory.decodeSeen(seen) else nil)
end

local function tile(strip: Instance, chapter: MoveStory.Chapter, index: number, state: string, onPick: () -> ()): any
	local open = state == "play"
	local color = rgb(chapter.color)
	local made = Ui.make("TextButton", {
		Name = `Chapter_{chapter.id}`,
		Size = UDim2.fromOffset(TILE_W, TILE_H),
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = index,
		ZIndex = 22,
	}, strip)
	Ui.corner(made, 8)
	Ui.make("UIStroke", { Name = "Lit", Color = color, Thickness = 1, Transparency = 0.75, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, made)
	Ui.make("Frame", { Name = "Accent", Size = UDim2.new(1, -16, 0, 3), Position = UDim2.fromOffset(8, 0), BackgroundColor3 = if open then color else K.rule, BorderSizePixel = 0, ZIndex = 23 }, made)
	local face = Ui.make("Frame", { Name = "Face", Size = UDim2.fromOffset(THUMB, THUMB), Position = UDim2.fromOffset(8, 9), BackgroundTransparency = 1, ZIndex = 23 }, made)
	Portrait.mount(face, Portrait.people(chapter.clientId, chapter.partnerId), color, { dim = not open })
	text(made, MoveStory.label(chapter), UDim2.fromOffset(TILE_W - THUMB - 22, 14), { Name = "Label", Position = UDim2.fromOffset(THUMB + 14, 9), Font = Theme.HeadingFont, TextSize = 10, TextColor3 = C.faint, ZIndex = 23 })
	local pill = text(made, if open then "▶ PLAY" elseif state == "locked" then "🔒 LOCKED" else "🔒 SOON", UDim2.fromOffset(TILE_W - THUMB - 22, 18), {
		Name = "State",
		Position = UDim2.fromOffset(THUMB + 14, 25),
		Font = Theme.HeadingFont,
		TextSize = 10,
		TextColor3 = if open then K.good else C.faint,
		BackgroundColor3 = if open then C.goodFace else K.raised,
		BackgroundTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 23,
	})
	Ui.corner(pill, 9)
	text(made, chapter.title, UDim2.fromOffset(TILE_W - 16, 16), { Name = "Title", Position = UDim2.fromOffset(8, 50), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = if open then C.title else K.secondary, ZIndex = 23 })
	text(made, chapter.client, UDim2.fromOffset(TILE_W - 16, 14), { Name = "Client", Position = UDim2.fromOffset(8, 66), TextSize = 10, TextColor3 = C.faint, ZIndex = 23 })
	made.Activated:Connect(function()
		CardKit.click()
		onPick()
	end)
	return made
end

function MoveStoryUi.chapters(body: Instance, order: number, contract: any, open: { [string]: boolean }?, onPlay: ((string) -> ())?): any
	local chapters = MoveStory.Chapters
	local current = MoveStory.forContract(contract)
	local states: { [string]: string } = {}
	for _, chapter in chapters do
		states[chapter.id] = stateOf(chapter, open)
	end
	local section = Ui.make("Frame", { Name = "MoveStoryChapters", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 22 }, body)
	Ui.list(section, true, 6)
	local playable = 0
	for _, chapter in chapters do
		if states[chapter.id] == "play" then
			playable += 1
		end
	end
	local head = Ui.make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22 }, section)
	text(head, "THE LAST MOVE · CHAPTERS", UDim2.new(1, -110, 1, 0), { Name = "Title", Font = Theme.HeadingFont, TextSize = 11, TextColor3 = ORANGE, ZIndex = 22 })
	text(head, `{playable} OF {#chapters} OPEN`, UDim2.new(0, 110, 1, 0), {
		Name = "Open",
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = C.faint,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 22,
	})
	local strip = Ui.make("ScrollingFrame", {
		Name = "Road",
		Size = UDim2.new(1, 0, 0, TILE_H + 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		LayoutOrder = 2,
		ZIndex = 22,
	}, section)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
	local detail = text(section, "", UDim2.new(1, 0, 0, 0), {
		Name = "Detail",
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextColor3 = K.secondary,
		LayoutOrder = 3,
		ZIndex = 22,
	})
	local tiles: { [string]: any } = {}
	local function pick(chapter: MoveStory.Chapter)
		for id, made in tiles do
			local lit = made:FindFirstChild("Lit")
			if lit then
				lit.Transparency = if id == chapter.id then 0 else 0.75
				lit.Thickness = if id == chapter.id then 2 else 1
			end
		end
		local state = states[chapter.id]
		local seen = player:GetAttribute("MoveStory")
		local lock = if state == "locked" then MoveStory.lockText(chapter, if type(seen) == "string" then MoveStory.decodeSeen(seen) else {}) else nil
		detail.Text = if state == "play"
			then `{chapter.icon} {string.upper(chapter.title)} · “{chapter.blurb}” — {chapter.client}`
			elseif state == "locked" then `{chapter.icon} {string.upper(chapter.title)} · {lock or "🔒 Finish the chapter before it first."} {chapter.hook}`
			else `{chapter.icon} {string.upper(chapter.title)} · 🔒 SOON · {chapter.hook}`
	end
	for index, chapter in chapters do
		tiles[chapter.id] = tile(strip, chapter, index, states[chapter.id], function()
			pick(chapter)
			-- 7.x farm move: another playable chapter: its contract's card
			local other = chapter.contract
			if onPlay and other and states[chapter.id] == "play" and chapter ~= current then
				onPlay(other)
			end
		end)
	end
	pick(current or chapters[1])
	return section
end

-- ── The result card's thanks ────────────────────────────────────────────────

function MoveStoryUi.thanks(body: Instance, order: number, result: any, contract: any): any
	if type(result) ~= "table" then
		return nil
	end
	local chapter = MoveStory.forContract(contract) or MoveStory.forContract(result.name)
	local line = if chapter then MoveStory.thanksLine(chapter.contract, result.how, tonumber(result.stars)) else nil
	if not chapter or not line then
		return nil
	end
	local color = rgb(chapter.color)
	local row = Ui.make("Frame", {
		Name = "MoveStoryThanks",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 22,
	}, body)
	Ui.corner(row, 8)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, row)
	local face = Ui.make("Frame", { Name = "Face", Size = UDim2.fromOffset(QUOTE, QUOTE), BackgroundTransparency = 1, ZIndex = 23 }, row)
	Portrait.mount(face, Portrait.people(chapter.clientId, chapter.partnerId), color)
	local words = Ui.make("Frame", {
		Name = "Words",
		Size = UDim2.new(1, -(QUOTE + 10), 0, 0),
		Position = UDim2.fromOffset(QUOTE + 10, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 23,
	}, row)
	Ui.list(words, true, 2)
	text(words, string.upper(chapter.client), UDim2.new(1, 0, 0, 14), { Name = "Client", Font = Theme.HeadingFont, TextSize = 11, TextColor3 = color, LayoutOrder = 1, ZIndex = 23 })
	text(words, `“{line}”`, UDim2.new(1, 0, 0, 0), {
		Name = "Thanks",
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextColor3 = K.text,
		LayoutOrder = 2,
		ZIndex = 23,
	})
	return row
end

return MoveStoryUi
