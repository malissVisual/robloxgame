--!strict
-- 8.3 SANDBOX, a showroom visitor's offer (server/VisitorOffers.luau decides everything; shared/Visitors.luau has the
-- words): a small card "🤝 OFFER · The collector offers $340 for your Gramophone · Market price $260 · +31%" with its
-- clock running out (a bar and "⏳ 28 s") and two buttons, DECLINE and ACCEPT. The toast comes from the server (a
-- Notice); the card from the "Visitors" remote's { kind = "offer" }.
--   * It opens when the offer comes, unless another window covers the screen (OfferCard.covered: client/Main.client.luau
--     sets it, the same check that frees the mouse): then it waits and opens when that one closes, while the offer is
--     still open. It goes when the offer closes (the remote's { kind = "closed" }) or its clock runs out.
--   * ACCEPT sends { kind = "accept", id }, DECLINE { kind = "decline", id } (only the id: the server has the price) and
--     the card closes; closing it the ✕-less ways, ESC (the Roblox menu: client/Hud.luau's escape) and the gamepad's B,
--     is a DECLINE. 8.3 review: another window opening (📦 STOCK, the 📖 BOOK to compare prices …) only hides it
--     (OfferCard.hide: client/Main.client.luau's Hud.onCloseWindows when it is no escape): the offer keeps waiting, its
--     clock running, and the card comes back once nothing covers the screen; its clock or the server's closed message
--     ends it there as anywhere.
--   * Where (OfferCard.layout, pure): at the screen's right a little over the middle, clear of the HUD's groups
--     (client/Hud.luau's), the sandbox's chips (client/SandboxHud.luau's money block, client/SandboxTasksUi.luau's TASKS
--     chip), the move's top blocks (client/TopBlocks.luau), the quick chat's button, the move's list and on a touch
--     screen the touch controls (client/TouchLayout.luau); none clear, the place that covers the least. A touch screen's
--     buttons are at least Ui.MinTouch; 8.3 review: on a small one (667 × 375) the card shrinks, SHRINK at a time down
--     to the HUD's scale, until a place is clear (only its buttons stay Ui.MinTouch tall). Placed again on a resize or
--     when the top blocks move.
--   * A gamepad: the selection starts on DECLINE (an A pressed by habit never sells), stays inside the card; B declines.
--   * One window at a time (client/Main.client.luau registers it: onOpen, ESC).
-- Presentation only.
--   OfferCard.start()                         listens (nothing outside the sandbox)
--   OfferCard.open()                          shows the offer that waits (nothing: none)
--   OfferCard.close()                         closes it (a DECLINE of the offer it shows)
--   OfferCard.hide()                          8.3 review: hides it, the offer still waiting (another window opened)
--   OfferCard.isOpen(), .card(), .pending()   is it open / its frame / the offer that waits (shared/Visitors.luau's)
--   OfferCard.onOpen                          set by client/Main.client.luau (the other windows close)
--   OfferCard.covered                         set by client/Main.client.luau: is another window open now?
--   OfferCard.layout(W, H, S, touch, blocks) -> (box, scale)   where the card goes (px under Roblox's top bar)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.Visitors)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout)
local TopBlocks = require(script.Parent.TopBlocks)

local OfferCard = {}

OfferCard.onOpen = nil :: (() -> ())?
OfferCard.covered = nil :: (() -> boolean)?

local K = Theme.Contract
local GOLD = Color3.fromRGB(255, 196, 64) -- the offer's colour (the legendary gold of the warehouse's tags)
local GREEN = Color3.fromRGB(76, 176, 92) -- ACCEPT
local player = Players.LocalPlayer
-- the card at scale 1 (px)
local CARD_W, PAD, GAP = 300, 12, 8
local TITLE_H, WHO_H, PRICE_H, ITEM_H, MARKET_H, BAR_H = 18, 16, 32, 18, 14, 4
local BUTTON_H = 44
local BUTTON_W = (CARD_W - 2 * PAD - GAP) / 2
local CARD_H = PAD + TITLE_H + 2 + WHO_H + PRICE_H + ITEM_H + 2 + MARKET_H + GAP + BAR_H + 10 + BUTTON_H + PAD
local MARGIN = 8 -- from the screen's edges and what it keeps clear of
local SHRINK = 0.05 -- 8.3 review: a small touch screen's card tries this much smaller each time (down to the HUD's scale)
local TICK = 0.25 -- s between two looks while an offer waits
-- the HUD's groups (client/CarryGripUi.luau's list) and the sandbox's chips' ScreenGuis
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" }
local CHIP_GUIS = { SandboxHud = "MoneyBlock", SandboxTasksChip = "" } -- (a ScreenGui: its piece, "" every piece)

local remote = Net.get("Visitors")
local started = false
local gui: ScreenGui? = nil
local parts: { [string]: any } = {} -- the card's pieces (built once)
local opened = false
local waiting: Rules.Offer? = nil -- the offer that waits (shown or not)
local deadline = 0 -- os.clock() its clock runs out
local token = 0 -- one wait loop at a time

-- ── Where it goes (pure maths: the phone-ui check runs it) ──────────────────

local function clearOf(b: TouchLayout.Box, W: number, H: number, blocks: { TouchLayout.Box }): boolean
	if not MoveLayout.inside(b, W, H) then
		return false
	end
	for _, other in blocks do
		if TouchLayout.overlap(b, other) then
			return false
		end
	end
	return true
end

-- Its buttons' height at a scale (a touch screen: at least Ui.MinTouch screen px), and so its own.
local function buttonHeight(touch: boolean, scale: number): number
	return if touch then math.max(BUTTON_H, math.ceil(Ui.MinTouch / scale - 1e-6)) else BUTTON_H
end

local function cardHeight(touch: boolean, scale: number): number
	return CARD_H - BUTTON_H + buttonHeight(touch, scale)
end

-- 8.3 review: the scales it tries, the biggest first: on a touch screen its buttons a finger's height as drawn, then
-- SHRINK smaller down to the HUD's scale S (a small phone); elsewhere S.
local function scalesFor(S: number, touch: boolean): { number }
	local big = if touch then math.max(S, Ui.MinTouch / BUTTON_H) else S
	local list = { big }
	local s = big - SHRINK
	while s > S + 1e-6 do
		table.insert(list, s)
		s -= SHRINK
	end
	if big > S + 1e-6 then
		table.insert(list, S)
	end
	return list
end

function OfferCard.layout(W: number, H: number, S: number, touch: boolean, blocks: { TouchLayout.Box }): (TouchLayout.Box, number)
	local avoid = table.clone(blocks)
	if touch then
		local c = TouchLayout.cluster(W, H, S)
		for _, b in TouchLayout.buttons(c) do
			table.insert(avoid, b)
		end
		table.insert(avoid, c.thumb)
		table.insert(avoid, c.jump)
	end
	local fallback: TouchLayout.Box? = nil
	local fallbackScale = S
	local fallbackCost = math.huge
	for _, scale in scalesFor(S, touch) do
		local w, h = CARD_W * scale, cardHeight(touch, scale) * scale
		-- the preferred place: the right edge, a little over the middle; then every place flush against an edge of what
		-- is there (and the screen's middle)
		local px, py = W - MARGIN - w, H * 0.45 - h / 2
		local xs = { px, (W - w) / 2, MARGIN }
		local ys = { py, MARGIN, H - MARGIN - h }
		for _, b in avoid do
			table.insert(xs, b.x1 + MARGIN)
			table.insert(xs, b.x0 - MARGIN - w)
			table.insert(ys, b.y1 + MARGIN)
			table.insert(ys, b.y0 - MARGIN - h)
		end
		local best: TouchLayout.Box? = nil
		local bestNear = math.huge
		for _, y in ys do
			local y0 = math.floor(math.clamp(y, MARGIN, math.max(MARGIN, H - MARGIN - h)) + 0.5) -- (whole px: where it is put)
			for _, x in xs do
				local x0 = math.floor(math.clamp(x, MARGIN, math.max(MARGIN, W - MARGIN - w)) + 0.5)
				local b = TouchLayout.box(x0, y0, x0 + w, y0 + h)
				local near = math.abs(x0 - px) + math.abs(y0 - py)
				if near < bestNear and clearOf(b, W, H, avoid) then
					best, bestNear = b, near
				end
				local bad = MoveLayout.clash(b, W, H, avoid) + 1e-3 * near
				if bad < fallbackCost then
					fallback, fallbackScale, fallbackCost = b, scale, bad
				end
			end
		end
		if best then
			return best, scale -- (the biggest scale with a clear place)
		end
	end
	return (fallback or TouchLayout.box(MARGIN, MARGIN, MARGIN + CARD_W * S, MARGIN + cardHeight(touch, S) * S)) :: TouchLayout.Box, fallbackScale
end

-- ── The card ───────────────────────────────────────────────────────────────

local function hide()
	opened = false
	local card = parts.card
	if card then
		Ui.gamepadRelease(card)
		card.Visible = false
	end
end

-- The offer's answer (once): the card closes, the offer stops waiting.
local function answer(accept: boolean)
	local offer = waiting
	if not offer then
		hide()
		return
	end
	waiting = nil
	token += 1
	remote:FireServer({ kind = if accept then "accept" else "decline", id = offer.id })
	hide()
end

local function build(): Frame?
	local made = parts.card
	if made and made.Parent then
		return made
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local screen = Ui.make("ScreenGui", {
		Name = "OfferCard",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
	}, playerGui)
	gui = screen
	local card = Ui.make("Frame", {
		Name = "OfferCard",
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		SelectionGroup = true, -- (the gamepad's selection stays in the card)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, screen)
	Ui.corner(card, 10)
	Ui.make("UIStroke", { Name = "Edge", Color = GOLD, Thickness = 2 }, card)
	parts.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, card)
	local inner = CARD_W - 2 * PAD
	local y = PAD
	local function line(name: string, height: number, size: number, font: Enum.Font, color: Color3, xAlign: Enum.TextXAlignment?, width: number?): TextLabel
		local label = Ui.label(card, "", UDim2.fromOffset(width or inner, height), {
			Name = name,
			Position = UDim2.fromOffset(PAD, y),
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextXAlignment = xAlign or Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		return label
	end
	parts.title = line("Title", TITLE_H, 15, Theme.HeadingFont, GOLD, nil, inner - 70)
	parts.title.Text = "🤝 OFFER"
	parts.time = line("Time", TITLE_H, 13, Theme.HeadingFont, K.secondary, Enum.TextXAlignment.Right)
	y += TITLE_H + 2
	parts.who = line("Who", WHO_H, 13, Theme.Font, K.secondary)
	y += WHO_H
	parts.price = line("Price", PRICE_H, 28, Theme.HeadingFont, Theme.Colors.money or K.good)
	y += PRICE_H
	parts.item = line("Item", ITEM_H, 15, Theme.HeadingFont, K.text)
	y += ITEM_H + 2
	parts.market = line("Market", MARKET_H, 12, Theme.Font, K.good)
	y += MARKET_H + GAP
	local track = Ui.make("Frame", {
		Name = "Clock",
		Position = UDim2.fromOffset(PAD, y),
		Size = UDim2.fromOffset(inner, BAR_H),
		BackgroundColor3 = K.track,
		BorderSizePixel = 0,
	}, card)
	Ui.corner(track, 2)
	parts.bar = Ui.make("Frame", { Name = "Left", Size = UDim2.fromScale(1, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, track)
	Ui.corner(parts.bar, 2)
	y += BAR_H + 10
	local function button(name: string, text: string, x: number, face: Color3, ink: Color3, accept: boolean): TextButton
		local b = Ui.make("TextButton", {
			Name = name,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
			BackgroundColor3 = face,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.HeadingFont,
			TextSize = 16,
			TextColor3 = ink,
			Text = text,
		}, card)
		Ui.corner(b, 8)
		b.Activated:Connect(function()
			if opened then
				answer(accept)
			end
		end)
		return b
	end
	parts.decline = button("Decline", "DECLINE", PAD, K.raised, K.text, false)
	parts.accept = button("Accept", "✓ ACCEPT", PAD + BUTTON_W + GAP, GREEN, K.charcoal, true)
	Ui.make("UIStroke", { Name = "Edge", Color = K.rule, Thickness = 1 }, parts.decline)
	parts.card = card
	return card
end

-- The offer's words on the card.
local function paint(offer: Rules.Offer)
	local lines = Rules.cardLines(offer)
	parts.who.Text = lines.who
	parts.price.Text = lines.price
	parts.item.Text = lines.item
	parts.market.Text = (if offer.market == "hot" then "🔥 " elseif offer.market == "cold" then "❄ " else "") .. lines.market
end

-- The clock: the bar and "⏳ 28 s".
local function clock()
	local left = math.max(0, deadline - os.clock())
	local offer = waiting
	local total = if offer then math.max(1, offer.seconds) else 1
	if parts.time then
		parts.time.Text = `⏳ {math.ceil(left)} s`
	end
	if parts.bar then
		parts.bar.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
	end
end

-- What it keeps clear of, in its ScreenGui's px.
local function blocksNow(origin: Vector2): { TouchLayout.Box }
	local list: { TouchLayout.Box } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local function add(object: Instance?)
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
			local p, size = object.AbsolutePosition - origin, object.AbsoluteSize
			table.insert(list, TouchLayout.box(p.X, p.Y, p.X + size.X, p.Y + size.Y))
		end
	end
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud then
		for _, name in HUD_GROUPS do
			add(hud:FindFirstChild(name))
		end
	end
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
	for _, r in TopBlocks.rects(origin) do -- (the move's panel, Danny's status line, the guide's line, the planning)
		table.insert(list, r)
	end
	local chat = playerGui and playerGui:FindFirstChild("QuickChat")
	local moving = playerGui and playerGui:FindFirstChild("MovingHud")
	add(chat and chat:FindFirstChild("QuickChatButton"))
	add(moving and moving:FindFirstChild("MoveList", true))
	return list
end

-- Its place and size for this screen.
local function place()
	local card = parts.card
	local screen = gui
	if not opened or not card or not screen then
		return
	end
	local size = screen.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 2 or H < 2 then
		local s = Ui.screenSize()
		W, H = s.X, s.Y
	end
	local touch = Ui.touchLayout()
	local b, scale = OfferCard.layout(W, H, Ui.screenScale(), touch, blocksNow(screen.AbsolutePosition))
	local tall = buttonHeight(touch, scale)
	card.Size = UDim2.fromOffset(CARD_W, cardHeight(touch, scale))
	parts.decline.Size = UDim2.fromOffset(BUTTON_W, tall)
	parts.accept.Size = UDim2.fromOffset(BUTTON_W, tall)
	card.Position = UDim2.fromOffset(math.floor(b.x0 + 0.5), math.floor(b.y0 + 0.5))
	parts.scale.Scale = scale
end

local function isCovered(): boolean
	local check = OfferCard.covered
	if type(check) ~= "function" then
		return false
	end
	local ok, covered = pcall(check)
	return ok and covered == true
end

function OfferCard.isOpen(): boolean
	return opened
end

function OfferCard.card(): Frame?
	return parts.card
end

function OfferCard.pending(): Rules.Offer?
	return waiting
end

-- ESC (the Roblox menu), the gamepad's B: a DECLINE of the offer it shows.
function OfferCard.close()
	if not opened then
		return
	end
	answer(false)
end

-- 8.3 review: another window opening (client/Main.client.luau, no escape) only hides it: the offer keeps waiting and
-- follow() shows it again once nothing covers the screen (its clock and the server's closed message still end it).
function OfferCard.hide()
	if opened then
		hide()
	end
end

function OfferCard.open()
	local offer = waiting
	if not offer or opened then
		return
	end
	local card = build()
	if not card then
		return
	end
	opened = true
	paint(offer)
	clock()
	card.Visible = true
	place()
	local hook = OfferCard.onOpen
	if hook then
		hook() -- (client/Main.client.luau: the other windows close)
	end
	Ui.gamepadFocus(parts.decline) -- (never ACCEPT: an A pressed by habit sells nothing)
end

-- An offer waits: its clock, the card when nothing covers the screen, gone when its time is up.
local function follow()
	token += 1
	local mine = token
	task.spawn(function()
		while token == mine and waiting do
			if os.clock() >= deadline then
				waiting = nil
				hide()
				return
			end
			if not opened and not isCovered() then
				OfferCard.open()
			end
			if opened then
				clock()
			end
			task.wait(TICK)
		end
	end)
end

local function onMessage(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "offer" then
		local offer = Rules.readOffer(message)
		if not offer then
			return
		end
		hide()
		waiting = offer
		deadline = os.clock() + offer.seconds
		follow()
	elseif message.kind == "closed" then
		local offer = waiting
		if offer and message.id == offer.id then
			waiting = nil
			token += 1
			hide()
		end
	end
end

function OfferCard.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	remote.OnClientEvent:Connect(onMessage)
	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if opened and input.KeyCode == Enum.KeyCode.ButtonB then
			answer(false)
		end
	end)
	TopBlocks.onChanged(function()
		place()
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			place()
		end)
	end
end

return OfferCard
