--!strict
-- 7.0 planning (the owner's rework, design/rework/NAVRH.md §3: "quick messages, a wheel"): the crew's quick chat on a
-- move or in its planning lobby. Hold T (a tap of T still takes the next gun: client/WeaponWheel.luau gives way to a
-- held T while this is active, Main sets WeaponWheel.yields) or tap the 💬 button on a touch screen: six lines on a ring
-- round the middle of the screen (shared/MoveRoles.luau Chat). Point at one and let go of T, or click / tap it, to say
-- it. The server (server/MoveLobby.luau, the MoveLobby remote's "chat", Config.Robust.Limits.QuickChat) sends it to
-- your crew only; every crew mate sees a short bubble over the sender's head (Config.MoveRoles.Chat.Bubble s) and a line
-- under the move's panel (Chat.Feed s; in the planning, at the top). Active while your player attribute MoveWith (a
-- move) or MoveLobby (a planning) is set. Presentation only: the server checks who may hear what.
-- 7.0 review: the lines coming in start under the lowest of the move's top-centre blocks (client/TopBlocks.luau: the
-- move's panel, Danny's strip, the planning's pill), measured; the touch button (client/MoveLayout.luau chatButton)
-- sits beside the panel clear of the touch buttons and the HUD's groups, and hides while a card or the planning covers
-- the screen (QuickChat.covered, set by Main); on a touch screen the ring's lines are a finger's size (MoveLayout.ring);
-- a ring shut while T is still held stays shut (the hold starts again on the next press).
--   QuickChat.start()    the key, the touch button, the lines coming in
--   QuickChat.active()   on a move or in its planning (Main: WeaponWheel.yields)
--   QuickChat.isOpen()   the ring is open (Main: the mouse is free while it is)
--   QuickChat.close(say) shut the ring (Main: ESC)
--   QuickChat.covered    set by Main: is a card, the move's list or the planning over the screen (the button hides)

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MoveRoles = require(Shared.MoveRoles)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local TouchLayout = require(script.Parent.TouchLayout) -- 7.0 review
local MoveLayout = require(script.Parent.MoveLayout) -- 7.0 review
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review

local QuickChat = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local T = Config.MoveRoles.Chat
local RADIUS = 150 -- px (unscaled): the lines' ring
local PILL = Vector2.new(210, 44)
local FEED_MAX = 3
-- the HUD's groups (client/Hud.luau's panels, Hotbar's bar, KeyHints) the touch button keeps clear of
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" }

QuickChat.covered = nil :: (() -> boolean)?

local remote = Net.get("MoveLobby")
local gui: ScreenGui? = nil
local ring: any = nil -- the ring's backdrop (a TextButton over the screen), nil: not built
local pills: { any } = {}
local centre: any = nil
local touchButton: any = nil
local feed: any = nil
local open = false
local touchMode = false
local pressedAt: number? = nil
local hovered: number? = nil

function QuickChat.active(): boolean
	return player:GetAttribute("MoveWith") ~= nil or player:GetAttribute("MoveLobby") ~= nil
end

function QuickChat.isOpen(): boolean
	return open
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
		Name = "QuickChat",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 9, -- (over the planning lobby: 6, and the move's HUD: 7)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

local function sound(name: string)
	pcall(function()
		(require(script.Parent.Sounds) :: any).play(name, 0.6)
	end)
end

-- ── The ring ───────────────────────────────────────────────────────────────

local function paint(index: number?)
	hovered = index
	for i, pill in pills do
		local on = i == index
		pill.BackgroundColor3 = if on then K.red else K.raised
		local stroke = pill:FindFirstChild("Edge")
		if stroke then
			stroke.Color = if on then K.red else K.rule
		end
	end
end

local function build(root: ScreenGui)
	local backdrop = Ui.make("TextButton", {
		Name = "Ring",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 1,
	}, root)
	backdrop.Activated:Connect(function()
		-- a tap beside the lines (touch, or a click away from them): shut, nothing said
		QuickChat.close(false)
	end)
	local middle = Ui.make("Frame", {
		Name = "Middle",
		Size = UDim2.fromOffset(2 * RADIUS + PILL.X, 2 * RADIUS + PILL.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, backdrop)
	Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, middle)
	centre = middle
	local hub = Ui.make("Frame", {
		Name = "Hub",
		Size = UDim2.fromOffset(120, 120),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, middle)
	Ui.corner(hub, 60)
	Ui.make("UIStroke", { Color = K.rule, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hub)
	Ui.label(hub, "💬\nQUICK CHAT", UDim2.fromScale(1, 0.62), {
		Name = "Title",
		Position = UDim2.fromScale(0, 0.12),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	Ui.label(hub, if Ui.touchLayout() then "TAP ONE" else "LET GO OF T", UDim2.fromScale(1, 0.2), {
		Name = "How",
		Position = UDim2.fromScale(0, 0.7),
		Font = Theme.HeadingFont,
		TextSize = 10,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	table.clear(pills)
	for index, line in MoveRoles.Chat do
		local angle = math.rad(-90 + (index - 1) * 60)
		local pill = Ui.make("TextButton", {
			Name = `Line{index}`,
			Size = UDim2.fromOffset(PILL.X, PILL.Y),
			Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = K.raised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = `{line.icon}  {line.text}`,
			Font = Theme.HeadingFont,
			TextSize = 15,
			TextColor3 = K.text,
			ZIndex = 3,
		}, middle)
		Ui.corner(pill, PILL.Y // 2)
		Ui.make("UIStroke", { Name = "Edge", Color = K.rule, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
		local which = index
		pill.MouseEnter:Connect(function()
			if not touchMode then
				paint(which)
			end
		end)
		pill.Activated:Connect(function()
			QuickChat.say(which)
		end)
		table.insert(pills, pill)
	end
	ring = backdrop
end

-- The line under the mouse (its direction from the ring's middle), nil near the middle.
local function aimed(): number?
	if not centre then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local mid = centre.AbsolutePosition + centre.AbsoluteSize / 2
	local d = mouse - mid
	if d.Magnitude < 40 * Ui.screenScale() then
		return nil
	end
	local degrees = math.deg(math.atan2(d.Y, d.X))
	local count = #MoveRoles.Chat
	local step = 360 / count
	return math.floor(((degrees + 90 + step / 2) % 360) / step) + 1
end

local function openRing(touch: boolean)
	local root = screen()
	if not root or open or not QuickChat.active() then
		return
	end
	if not ring then
		build(root)
	end
	-- 7.0 review: a touch screen's lines a finger's height, the ring shrunk to stay on a short screen
	local size = Ui.screenSize()
	local ringScale, radius, width = MoveLayout.ring(size.X, size.Y, Ui.screenScale(), Ui.touchLayout(), RADIUS, PILL.X, PILL.Y)
	local scale = centre and centre:FindFirstChild("Scale")
	if scale then
		scale.Scale = ringScale
	end
	if centre then
		centre.Size = UDim2.fromOffset(2 * radius + width, 2 * radius + PILL.Y)
		for index, pill in pills do
			local angle = math.rad(-90 + (index - 1) * 60)
			pill.Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
			pill.Size = UDim2.fromOffset(width, PILL.Y)
			pill.TextWrapped = width < PILL.X -- (a phone upright: two lines of words)
		end
	end
	touchMode = touch
	open = true
	paint(nil)
	ring.Visible = true
	if Ui.gamepadActive() and pills[1] then
		Ui.gamepadFocus(pills[1])
	end
end

-- Shut the ring; `say`: the line under the mouse is said.
function QuickChat.close(say: boolean)
	if not open then
		return
	end
	open = false
	pressedAt = nil -- (7.0 review: a ring shut while T is still held does not open again)
	if ring then
		ring.Visible = false
		Ui.gamepadRelease(ring)
	end
	local index = hovered
	hovered = nil
	if say and index then
		remote:FireServer("chat", index)
	end
end

-- Say line `index` (a click or a tap on it).
function QuickChat.say(index: number)
	if open then
		open = false
		if ring then
			ring.Visible = false
			Ui.gamepadRelease(ring)
		end
	end
	hovered = nil
	pressedAt = nil
	remote:FireServer("chat", index)
end

-- ── The lines coming in ────────────────────────────────────────────────────

-- Under the lowest of the move's top-centre blocks (the panel, Danny's strip, the planning's pill: client/TopBlocks.luau,
-- measured), else the screen's top: where the feed starts (px in this gui).
local function feedTop(): number
	local root = gui
	local bottom = TopBlocks.bottom(if root then root.AbsolutePosition else nil)
	return if bottom then bottom + 6 else 8
end

local function placeFeed()
	local made = feed
	if made and made.Parent then
		made.Position = UDim2.new(0.5, 0, 0, feedTop())
	end
end

local function feedLine(text: string)
	local root = screen()
	if not root then
		return
	end
	if not feed or not feed.Parent then
		feed = Ui.make("Frame", {
			Name = "Feed",
			Size = UDim2.fromOffset(360, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, root)
		Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, feed)
		Ui.list(feed, true, 4, Enum.HorizontalAlignment.Center)
	end
	feed.Position = UDim2.new(0.5, 0, 0, feedTop())
	local scale = feed:FindFirstChild("Scale")
	if scale then
		scale.Scale = Ui.screenScale()
	end
	local lines: { any } = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	table.sort(lines, function(a: any, b: any): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #lines >= FEED_MAX do
		local oldest = table.remove(lines, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local order = if #lines > 0 then lines[#lines].LayoutOrder + 1 else 1
	local label = Ui.label(feed, text, UDim2.fromOffset(0, 26), {
		Name = "Line",
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = K.scrim,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = K.text,
		TextWrapped = false,
		LayoutOrder = order,
		ZIndex = 5,
	})
	Ui.corner(label, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, label)
	task.delay(T.Feed, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

-- A short bubble over the sender's head (one at a time each).
local function bubble(sender: Player, text: string)
	local character = sender.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not head or not head:IsA("BasePart") or not playerGui then
		return
	end
	local name = `QuickChatBubble_{sender.UserId}`
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local board = Ui.make("BillboardGui", {
		Name = name,
		Adornee = head,
		Size = UDim2.fromOffset(240, 40),
		StudsOffset = Vector3.new(0, 2.8, 0),
		AlwaysOnTop = true,
		MaxDistance = 220,
		LightInfluence = 0,
		ResetOnSpawn = false,
	}, playerGui)
	local label = Ui.label(board, text, UDim2.fromScale(1, 1), {
		Name = "Text",
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.15,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	Ui.corner(label, 10)
	Ui.make("UIStroke", { Color = Color3.fromRGB(240, 132, 44), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, label)
	task.delay(T.Bubble, function()
		if board.Parent then
			board:Destroy()
		end
	end)
end

local function heard(line: any)
	if type(line) ~= "table" or type(line.index) ~= "number" then
		return
	end
	local said = MoveRoles.Chat[line.index]
	if not said then
		return
	end
	local name = if type(line.name) == "string" then line.name else "?"
	feedLine(`{said.icon} {string.upper(name)}: {said.text}`)
	local sender = Players:GetPlayerByUserId(tonumber(line.from) or 0)
	if sender then
		bubble(sender, `{said.icon} {said.text}`)
	end
	sound("notify")
end

-- ── The touch button ───────────────────────────────────────────────────────

-- 7.0 review: the button's place: beside the move's panel (or where the panel would be), clear of the touch buttons, the
-- HUD's groups and the other top-centre blocks (client/MoveLayout.luau chatButton).
local function placeButton(button: any, root: ScreenGui)
	local size = root.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 2 or H < 2 then
		size = Ui.screenSize()
		W, H = size.X, size.Y
	end
	local origin = root.AbsolutePosition
	local S = Ui.screenScale()
	local blocks: { TouchLayout.Box } = {}
	local cluster = TouchLayout.cluster(W, H, S)
	for _, b in TouchLayout.buttons(cluster) do
		table.insert(blocks, b)
	end
	table.insert(blocks, cluster.thumb)
	table.insert(blocks, cluster.jump)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud then
		for _, name in HUD_GROUPS do
			local group = hud:FindFirstChild(name)
			if group and group:IsA("GuiObject") and group.Visible and group.AbsoluteSize.X > 1 and group.AbsoluteSize.Y > 1 then
				local p, s = group.AbsolutePosition - origin, group.AbsoluteSize
				table.insert(blocks, TouchLayout.box(p.X, p.Y, p.X + s.X, p.Y + s.Y))
			end
		end
	end
	local panel = MoveLayout.panel(W, S)
	local found = TopBlocks.get("MovePanel")
	for _, r in TopBlocks.rects(origin) do
		table.insert(blocks, r)
	end
	if found and found.Visible and found.AbsoluteSize.X > 1 then
		local p, s = found.AbsolutePosition - origin, found.AbsoluteSize
		panel = TouchLayout.box(p.X, p.Y, p.X + s.X, p.Y + s.Y)
	end
	local at = MoveLayout.chatButton(W, H, S, panel, blocks)
	button.Size = UDim2.fromOffset(at.x1 - at.x0, at.y1 - at.y0)
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position = UDim2.fromOffset(at.x0, at.y0)
end

local function refreshButton()
	local root = screen()
	if not root then
		return
	end
	local covered = QuickChat.covered
	local show = Ui.touchLayout() and QuickChat.active() and not (covered ~= nil and covered())
	if show and not touchButton then
		touchButton = Ui.make("TextButton", {
			Name = "QuickChatButton",
			Size = UDim2.fromOffset(MoveLayout.CHAT, MoveLayout.CHAT),
			BackgroundColor3 = K.charcoal,
			BackgroundTransparency = Theme.PanelTransparency,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "💬",
			TextSize = 24,
			Font = Theme.Font,
			TextColor3 = K.text,
			ZIndex = 6,
		}, root)
		Ui.corner(touchButton, 24)
		Ui.make("UIStroke", { Color = Color3.fromRGB(240, 132, 44), Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, touchButton)
		touchButton.Activated:Connect(function()
			if open then
				QuickChat.close(false)
			else
				openRing(true)
			end
		end)
	end
	if touchButton then
		touchButton.Visible = show
		if show then
			placeButton(touchButton, root)
		end
	end
	if open and not QuickChat.active() then
		QuickChat.close(false)
	end
end

function QuickChat.start()
	screen()
	remote.OnClientEvent:Connect(function(kind: any, a: any)
		if kind == "chat" then
			heard(a)
		end
	end)
	player:GetAttributeChangedSignal("MoveWith"):Connect(refreshButton)
	player:GetAttributeChangedSignal("MoveLobby"):Connect(refreshButton)
	refreshButton()
	-- 7.0 review: the top-centre blocks moved (the feed and the button follow); the cards and the planning come and go
	-- (the button hides under them): a light look four times a second while on a move or in its planning
	TopBlocks.onChanged(function()
		placeFeed()
		if touchButton and touchButton.Visible then
			refreshButton()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if QuickChat.active() or (touchButton and touchButton.Visible) then
				pcall(refreshButton)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() or input.KeyCode ~= Enum.KeyCode.T then
			return
		end
		if QuickChat.active() then
			pressedAt = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode ~= Enum.KeyCode.T then
			return
		end
		pressedAt = nil
		if open and not touchMode then
			QuickChat.close(true)
		end
	end)
	-- the held T opens it after Chat.Hold (a tap is the weapon wheel's next gun); the line under the mouse lights
	RunService.Heartbeat:Connect(function()
		local since = pressedAt
		if not open and since and os.clock() - since >= T.Hold then
			openRing(false)
		end
		if open and not touchMode then
			local index = aimed()
			if index ~= hovered then
				paint(index)
			end
		end
	end)
end

return QuickChat
