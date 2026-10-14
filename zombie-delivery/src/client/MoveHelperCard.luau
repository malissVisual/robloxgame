--!strict
-- 8.3 Danny's card and his list's clicks (the owner: "make it so I click on the helper, but I have to PAY for him when I
-- want help … you go into the house, click on something, and that assigns it to him, and the rest you carry
-- yourself"). server/MoveHelper.luau decides everything; his words are shared/MoveHelperBrain.luau's:
--   * Opening the card: on a computer a click on his body (the crosshair's middle while the camera holds the mouse, else
--     the mouse's point), on a touch screen a tap on him (UserInputService.TouchTapInWorld; Config.MoveHelper.TapSlop
--     studs beside his body count, ClickReach studs at most), on a gamepad the prompt on him ("Hire Danny" while he is
--     for hire, then "Talk to Danny": a ProximityPrompt this client makes on his root, shown only while a gamepad is in
--     use, on shared/SandboxPad.luau's "danny" button: L1); the button of his status line (client/MoveHelperHud.luau, wired by useCard). Never while your
--     hands are full, you wait for him or a grip check shows (a left click is the check's press then:
--     client/CarryGripUi.luau active). His body is found by your player attribute MoveHelperId (his body's
--     MoveHelper): only his move's crew has it.
--   * The card: "🧑‍🔧 DANNY", his status (MoveHelperBrain.status), ✕; for hire: "Hire Danny for this move · $170", what
--     he does for you, and HIRE · $170 (the Moving remote's ("helper", "hire"): the server checks the crew and the
--     money and takes it); hired: "2 pieces to carry", how to give him pieces, and CLEAR QUEUE (("helper", "clear")).
--     A tap on its button sends once and the card closes. A gamepad's selection starts on its button.
--   * His list (hired): a click on a piece of your move (a tap on a touch screen) sends ("helper", "assign", its model):
--     onto his list, or off it again (the server checks and says so in a toast; its marker over the piece is the
--     server's). On a gamepad the prompt "Give to Danny" ("Take back from Danny" for a piece of his list) on the nearest
--     piece of your move within reach, on SandboxPad's "dannygive" button (R1: free in the sandbox, no throw or holster
--     there).
--   * Where (MoveHelperCard.layout, pure): beside his head as it was on the screen when it opened (right of him, else
--     left, over, under), clear of the HUD's groups (client/Hud.luau's), the sandbox's chips (client/SandboxHud.luau's
--     money block, client/SandboxTasksUi.luau's TASKS chip), the move's top blocks (its panel, Danny's status line, the
--     guide's line: client/TopBlocks.luau), the quick chat's button, the move's list and on a touch screen the touch
--     controls (client/TouchLayout.luau); none clear, the place that covers the least. On a touch screen its button and
--     its ✕ are at least Ui.MinTouch. Placed again on a resize or when the top blocks move.
--   * One window at a time (client/Main.client.luau registers it: onOpen, ESC); ✕, ESC, the gamepad's B, a click or a
--     tap beside it, walking Config.MoveHelper.CardReach studs from him, a seat, him gone close it.
-- Presentation only.
--   MoveHelperCard.start()                         listens (nothing outside the sandbox)
--   MoveHelperCard.open(at?)                       opens it beside the screen point `at` (nil: his head's now)
--   MoveHelperCard.close(), .isOpen(), .card()     closes it / is it open / its frame (the checks)
--   MoveHelperCard.onOpen                          set by client/Main.client.luau (the other windows close)
--   MoveHelperCard.body()                          his body (nil: none on your move, or not streamed in)
--   MoveHelperCard.pieceAt(origin, direction)      the piece of your move a ray from `origin` hits first (its model), nil
--   MoveHelperCard.layout(W, H, S, touch, anchor, blocks) -> (box, scale)   where the card goes (px under Roblox's top
--                                                  bar; anchor: { x, y } or nil, the screen's middle)

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Brain = require(Shared.MoveHelperBrain)
local SandboxPad = require(Shared.SandboxPad) -- (the gamepad's buttons for him: its actions "danny" and "dannygive")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout)
local TopBlocks = require(script.Parent.TopBlocks)
local MoveHelperHud = require(script.Parent.MoveHelperHud)
local CarryGripUi = require(script.Parent.CarryGripUi)

local MoveHelperCard = {}

MoveHelperCard.onOpen = nil :: (() -> ())?

local H = Config.MoveHelper
local K = Theme.Contract
local player = Players.LocalPlayer
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
-- the card at scale 1 (px)
local CARD_W, PAD, GAP = 320, 10, 8
local TITLE_H, DOING_H, CLOSE = 18, 16, 28
local LINE_H, HINT_H, BUTTON_H = 20, 30, 56
local MARGIN = 8 -- from the screen's edges and what it keeps clear of
local SIDE = 36 -- px between his head's point and the card beside it
local PIECE_REACH = 12 -- studs: the gamepad's "Give to Danny" on the nearest piece this near
local TALK_PAD = SandboxPad.pads("danny")[1] or "ButtonL1" -- (shared/SandboxPad.luau: L1 his)
local GIVE_PAD = SandboxPad.pads("dannygive")[1] or "ButtonR1"
local PICK = { ["Pick up"] = true, Lift = true, ["Lift with " .. H.Name] = true, ["Pick up with " .. H.Name] = true } -- (a piece's own prompt)
-- the HUD's groups (client/CarryGripUi.luau's list) and the sandbox's chips' ScreenGuis
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" }
local CHIP_GUIS = { SandboxHud = "MoneyBlock", SandboxTasksChip = "" } -- (a ScreenGui: its piece, "" every piece)

local remote = Net.get("Moving")
local started = false
local gui: ScreenGui? = nil
local parts: { [string]: any } = {} -- the card's pieces (built once)
local opened = false
local openToken = 0
local anchorAt: { x: number, y: number }? = nil -- his head's point when it opened
local found: Model? = nil -- his body (found by MoveHelperId)
local prompt: ProximityPrompt? = nil -- the gamepad's "Hire Danny" / "Talk to Danny" on him
local give: ProximityPrompt? = nil -- the gamepad's "Give to Danny" on the nearest piece
local giveTo: Model? = nil -- …that piece

-- ── Where it goes (pure maths: the phone-ui check runs it) ──────────────────

local function cardHeight(touch: boolean, scale: number): (number, number)
	local close = if touch then math.max(CLOSE, math.ceil(Ui.MinTouch / scale)) else CLOSE
	local head = math.max(TITLE_H + DOING_H, close)
	return PAD + head + GAP + LINE_H + HINT_H + GAP + BUTTON_H + PAD, close
end

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

function MoveHelperCard.layout(W: number, H: number, S: number, touch: boolean, anchor: { x: number, y: number }?, blocks: { TouchLayout.Box }): (TouchLayout.Box, number)
	local scale = if touch then math.max(S, Ui.MinTouch / BUTTON_H) else S
	local tall = cardHeight(touch, scale)
	local w, h = CARD_W * scale, tall * scale
	local avoid = table.clone(blocks)
	if touch then
		local c = TouchLayout.cluster(W, H, S)
		for _, b in TouchLayout.buttons(c) do
			table.insert(avoid, b)
		end
		table.insert(avoid, c.thumb)
		table.insert(avoid, c.jump)
	end
	local ax = if anchor then anchor.x else W / 2
	local ay = if anchor then anchor.y else H * 0.45
	if anchor then
		table.insert(avoid, TouchLayout.box(ax - 26 * S, ay - 30 * S, ax + 26 * S, ay + 90 * S)) -- (never on him: his head, his body)
	end
	-- the preferred place: right of his head, level with it; then left of it, over it, under it; and every place flush
	-- against an edge of what is there
	local px, py = ax + SIDE, ay - h / 2
	local xs = { px, ax - SIDE - w, ax - w / 2 }
	local ys = { py, ay - SIDE - h, ay + SIDE }
	for _, b in avoid do
		table.insert(xs, b.x1 + MARGIN)
		table.insert(xs, b.x0 - MARGIN - w)
		table.insert(ys, b.y1 + MARGIN)
		table.insert(ys, b.y0 - MARGIN - h)
	end
	local best: TouchLayout.Box? = nil
	local bestNear = math.huge
	local fallback: TouchLayout.Box? = nil
	local fallbackCost = math.huge
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
				fallback, fallbackCost = b, bad
			end
		end
	end
	return (best or fallback or TouchLayout.box(MARGIN, MARGIN, MARGIN + w, MARGIN + h)) :: TouchLayout.Box, scale
end

-- ── His body, the pieces ───────────────────────────────────────────────────

function MoveHelperCard.body(): Model?
	local id = player:GetAttribute("MoveHelperId")
	if type(id) ~= "number" then
		found = nil
		return nil
	end
	local was = found
	if was and was.Parent and was:GetAttribute("MoveHelper") == id then
		return was
	end
	found = nil
	local folder = workspace:FindFirstChild("Npcs")
	for _, child in (if folder then folder:GetChildren() else {}) :: { Instance } do
		if child:IsA("Model") and child:GetAttribute("MoveHelper") == id then
			found = child
			return child
		end
	end
	return nil
end

local function rootOf(model: Model?): BasePart?
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return if root and root:IsA("BasePart") then root else nil
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function seated(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function hired(): boolean
	return player:GetAttribute("MoveHelper") == "hired"
end

-- May a click, a tap or a prompt act now (Danny on your move, your hands free, not waiting for him, no grip check, on
-- foot)?
local function mayAct(): boolean
	local character = player.Character
	return type(player:GetAttribute("MoveHelper")) == "string" and character ~= nil and character:GetAttribute("Carrying") == nil
		and character:GetAttribute("Pushing") == nil and player:GetAttribute("MoveHelperCall") == nil and not seated() and not CarryGripUi.active()
end

-- A piece's own prompt (its Pick up / Lift, tagged MovePrompt) when it is your move's: shown to you (MovingHud's rule).
local function piecePrompt(model: Instance): ProximityPrompt?
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") and PICK[d.ActionText] then
			local owner = d:GetAttribute("MoveOwner")
			if type(owner) == "number" and (owner == player.UserId or player:GetAttribute("MoveWith") == owner) then
				return d
			end
			return nil
		end
	end
	return nil
end

-- The piece of your move a ray hits first (its model: the attribute MoveSpot), nil: none, or another move's.
function MoveHelperCard.pieceAt(origin: Vector3, direction: Vector3): Model?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		table.insert(ignore, npcs) -- (Danny, a crew mate's … never in the way of a piece)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(origin, direction * H.ClickReach, params)
	local node: Instance? = if hit then hit.Instance else nil
	while node and node ~= workspace do
		if node:IsA("Model") and type(node:GetAttribute("MoveSpot")) == "number" then
			return if piecePrompt(node) then node else nil
		end
		node = node.Parent
	end
	return nil
end

-- His head's point on the screen (px under the top bar), nil: behind the camera or off it.
local function headPoint(): { x: number, y: number }?
	local camera = workspace.CurrentCamera
	local root = rootOf(MoveHelperCard.body())
	if not camera or not root then
		return nil
	end
	local ok, point, visible = pcall(function()
		return camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.2, 0))
	end)
	if not ok or not visible then
		return nil
	end
	local inset = GuiService:GetGuiInset()
	return { x = point.X, y = point.Y - inset.Y }
end

-- Does a ray (unit `direction`) from `origin` reach him: his body hit, or passing within TapSlop studs of his middle
-- with nothing nearer in the way?
local function reaches(origin: Vector3, direction: Vector3): boolean
	local model = MoveHelperCard.body()
	local root = rootOf(model)
	if not model or not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character :: Instance } else {}
	local hit = workspace:Raycast(origin, direction * H.ClickReach, params)
	if hit and hit.Instance:IsDescendantOf(model) then
		return true
	end
	local to = root.Position - origin
	local along = to:Dot(direction)
	if along <= 0 or along > H.ClickReach or (to - direction * along).Magnitude > H.TapSlop then
		return false
	end
	return hit == nil or (hit.Position - origin).Magnitude >= along - 1.5
end

-- ── The card ───────────────────────────────────────────────────────────────

local function send(kind: string)
	if not opened then
		return -- (a second tap as it closes: one request)
	end
	remote:FireServer("helper", kind)
	MoveHelperCard.close()
end

local function priceNow(): number
	local price = player:GetAttribute("MoveHelperPrice")
	return if type(price) == "number" then price else 0
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
		Name = "MoveHelperCard",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
	}, playerGui)
	gui = screen
	local card = Ui.make("Frame", {
		Name = "DannyCard",
		Size = UDim2.fromOffset(CARD_W, 200),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
	}, screen)
	Ui.corner(card, 10)
	Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 2 }, card)
	parts.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, card)
	parts.title = Ui.label(card, `🧑‍🔧 {string.upper(H.Name)}`, UDim2.fromOffset(CARD_W - 2 * PAD - CLOSE - GAP, TITLE_H), {
		Name = "Title",
		Position = UDim2.fromOffset(PAD, PAD),
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	parts.doing = Ui.label(card, "", UDim2.fromOffset(CARD_W - 2 * PAD - CLOSE - GAP, DOING_H), {
		Name = "Doing",
		Position = UDim2.fromOffset(PAD, PAD + TITLE_H),
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = Ui.make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, PAD),
		Size = UDim2.fromOffset(CLOSE, CLOSE),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.text,
		Text = "✕",
	}, card)
	Ui.corner(close, 6)
	close.Activated:Connect(function()
		MoveHelperCard.close()
	end)
	parts.close = close
	parts.line = Ui.label(card, "", UDim2.fromOffset(CARD_W - 2 * PAD, LINE_H), {
		Name = "Line",
		Font = Theme.HeadingFont,
		TextSize = 15,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	parts.hint = Ui.label(card, "", UDim2.fromOffset(CARD_W - 2 * PAD, HINT_H), {
		Name = "Hint",
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})
	local main = Ui.make("TextButton", {
		Name = "Main",
		Size = UDim2.fromOffset(CARD_W - 2 * PAD, BUTTON_H),
		BackgroundColor3 = ORANGE,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = K.charcoal,
		Text = "HIRE",
	}, card)
	Ui.corner(main, 8)
	parts.edge = Ui.make("UIStroke", { Name = "Edge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1, Transparency = 1 }, main)
	main.Activated:Connect(function()
		send(if hired() then "clear" else "hire")
	end)
	parts.main = main
	parts.card = card
	return card
end

-- How a piece goes to him with this input (a click, a tap, the gamepad's R1).
local function giveWords(): (string, string)
	if Ui.gamepadActive() then
		local button = SandboxPad.button(GIVE_PAD)
		return `{button} by a piece gives it to him`, `{button} again takes it back`
	elseif Ui.touchLayout() then
		return "Tap a piece to give it to him", "tap it again to take it back"
	end
	return "Click a piece to give it to him", "click it again to take it back"
end

-- The card's own words and colours: his status, for hire (the price, HIRE) or hired (his list, CLEAR QUEUE).
local function paint()
	if not parts.card then
		return
	end
	local isHired = hired()
	local count = player:GetAttribute("MoveHelperQueue")
	local doing = player:GetAttribute("MoveHelperDoing")
	local price = Brain.money(priceNow())
	parts.doing.Text = Brain.status(isHired, priceNow(), count, if type(doing) == "string" then doing else nil)
	local first, second = giveWords()
	if isHired then
		parts.line.Text = Brain.queueText(count)
		parts.hint.Text = `{first} · {second}.`
		parts.main.Text = "CLEAR QUEUE"
		parts.main.BackgroundColor3 = K.raised
		parts.main.TextColor3 = K.text
		parts.edge.Transparency = 0
	else
		parts.line.Text = `Hire {H.Name} for this move · {price}`
		parts.hint.Text = "He carries the pieces you give him and lifts the heavy ones with you."
		parts.main.Text = `HIRE · {price}`
		parts.main.BackgroundColor3 = ORANGE
		parts.main.TextColor3 = K.charcoal
		parts.edge.Transparency = 1
	end
end

-- What it keeps clear of, in its ScreenGui's px.
local function blocksNow(origin: Vector2): { TouchLayout.Box }
	local list: { TouchLayout.Box } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local function add(object: Instance?)
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
			local at, size = object.AbsolutePosition - origin, object.AbsoluteSize
			table.insert(list, TouchLayout.box(at.X, at.Y, at.X + size.X, at.Y + size.Y))
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

-- Its place and size for this screen (beside his head's point as it opened).
local function place()
	local card = parts.card
	local screen = gui
	if not opened or not card or not screen then
		return
	end
	local size = screen.AbsoluteSize
	local W, Hh = size.X, size.Y
	if W < 2 or Hh < 2 then
		local s = Ui.screenSize()
		W, Hh = s.X, s.Y
	end
	local touch = Ui.touchLayout()
	local b, scale = MoveHelperCard.layout(W, Hh, Ui.screenScale(), touch, anchorAt, blocksNow(screen.AbsolutePosition))
	local tall, close = cardHeight(touch, scale)
	card.Size = UDim2.fromOffset(CARD_W, tall)
	card.Position = UDim2.fromOffset(math.floor(b.x0 + 0.5), math.floor(b.y0 + 0.5))
	parts.scale.Scale = scale
	local head = math.max(TITLE_H + DOING_H, close)
	parts.close.Size = UDim2.fromOffset(close, close)
	local wordsW = CARD_W - 2 * PAD - close - GAP
	parts.title.Size = UDim2.fromOffset(wordsW, TITLE_H)
	parts.doing.Size = UDim2.fromOffset(wordsW, DOING_H)
	local top = PAD + head + GAP
	parts.line.Position = UDim2.fromOffset(PAD, top)
	parts.hint.Position = UDim2.fromOffset(PAD, top + LINE_H)
	parts.main.Position = UDim2.fromOffset(PAD, top + LINE_H + HINT_H + GAP)
end

function MoveHelperCard.isOpen(): boolean
	return opened
end

function MoveHelperCard.card(): Frame?
	return parts.card
end

function MoveHelperCard.close()
	if not opened then
		return
	end
	opened = false
	openToken += 1
	local card = parts.card
	if card then
		Ui.gamepadRelease(card)
		card.Visible = false
	end
end

function MoveHelperCard.open(at: { x: number, y: number }?)
	if type(player:GetAttribute("MoveHelper")) ~= "string" then
		return
	end
	local card = build()
	if not card then
		return
	end
	anchorAt = at or headPoint()
	opened = true
	openToken += 1
	local token = openToken
	card.Visible = true
	paint()
	place()
	local hook = MoveHelperCard.onOpen
	if hook then
		hook() -- (client/Main.client.luau: the other windows close)
	end
	Ui.gamepadFocus(parts.main)
	-- walking away from him, a seat, him gone: it closes (a look every quarter second while it is open)
	task.spawn(function()
		while opened and openToken == token do
			task.wait(0.25)
			if not opened or openToken ~= token then
				return
			end
			local mine, his = myRoot(), rootOf(MoveHelperCard.body())
			if type(player:GetAttribute("MoveHelper")) ~= "string" or seated() or (mine and his and (mine.Position - his.Position).Magnitude > H.CardReach) then
				MoveHelperCard.close()
				return
			end
		end
	end)
end

-- Is a screen point (px under the top bar) on the card?
local function onCard(x: number, y: number): boolean
	local card = parts.card
	if not card or not card.Visible then
		return false
	end
	local at, size = card.AbsolutePosition, card.AbsoluteSize
	return x >= at.X and x <= at.X + size.X and y >= at.Y and y <= at.Y + size.Y
end

-- A click or a tap in the world (a ray): on him, his card; on a piece of your move while he is hired, onto his list or
-- off it (the server decides).
local function clicked(origin: Vector3, direction: Vector3)
	if reaches(origin, direction) then
		MoveHelperCard.open(nil)
		return
	end
	if not hired() then
		return
	end
	local piece = MoveHelperCard.pieceAt(origin, direction)
	if piece then
		remote:FireServer("helper", "assign", piece)
	end
end

-- ── The gamepad's prompts: on him, on the nearest piece ────────────────────

local function keepPrompt()
	local model = MoveHelperCard.body()
	local root = rootOf(model)
	local made = prompt
	if not root then
		if made then
			made:Destroy()
			prompt = nil
		end
		return
	end
	if not made or made.Parent ~= root then
		if made then
			made:Destroy()
		end
		local fresh = Instance.new("ProximityPrompt")
		fresh.Name = "TalkToDanny"
		fresh.ObjectText = ""
		fresh.GamepadKeyCode = (Enum.KeyCode :: any)[TALK_PAD]
		fresh.HoldDuration = 0
		fresh.MaxActivationDistance = 12
		fresh.RequiresLineOfSight = false
		fresh.Triggered:Connect(function()
			if mayAct() then
				MoveHelperCard.open(nil)
			end
		end)
		fresh.Parent = root
		prompt = fresh
		made = fresh
	end
	local p = made :: ProximityPrompt
	local words = if hired() then `Talk to {H.Name}` else `Hire {H.Name}`
	if p.ActionText ~= words then
		p.ActionText = words
	end
	local on = Ui.gamepadActive() and mayAct()
	if p.Enabled ~= on then
		p.Enabled = on
	end
end

-- The nearest piece of your move within PIECE_REACH (its own prompt shown: home or on the ground; or on his list).
local function nearestPiece(): Model?
	local mine = myRoot()
	if not mine then
		return nil
	end
	local best: Model? = nil
	local bestDistance = PIECE_REACH
	for _, tagged in CollectionService:GetTagged("MovePrompt") do
		local root = tagged.Parent
		local model = root and root.Parent
		if not tagged:IsA("ProximityPrompt") or not PICK[tagged.ActionText] or not root or not root:IsA("BasePart") or not model or not model:IsA("Model") then
			continue
		end
		if type(model:GetAttribute("MoveSpot")) ~= "number" or (not tagged.Enabled and model:GetAttribute("DannyQueue") == nil) or piecePrompt(model) == nil then
			continue
		end
		local d = (root.Position - mine.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = model, d
		end
	end
	return best
end

local function keepGive()
	local on = Ui.gamepadActive() and hired() and mayAct()
	local piece = if on then nearestPiece() else nil
	local root = if piece then rootOf(piece) else nil
	local made = give
	if not piece or not root then
		if made then
			made.Enabled = false
		end
		giveTo = nil
		return
	end
	if not made or made.Parent ~= root then
		if made then
			made:Destroy()
		end
		local fresh = Instance.new("ProximityPrompt")
		fresh.Name = "GiveToDanny"
		fresh.GamepadKeyCode = (Enum.KeyCode :: any)[GIVE_PAD]
		fresh.HoldDuration = 0
		fresh.MaxActivationDistance = PIECE_REACH
		fresh.RequiresLineOfSight = false
		fresh.UIOffset = Vector2.new(0, 60) -- (under the piece's own prompt)
		fresh.Triggered:Connect(function()
			local to = giveTo
			if to and mayAct() and hired() then
				remote:FireServer("helper", "assign", to)
			end
		end)
		fresh.Parent = root
		give = fresh
		made = fresh
	end
	giveTo = piece
	local p = made :: ProximityPrompt
	local words = if piece:GetAttribute("DannyQueue") ~= nil then `Take back from {H.Name}` else `Give to {H.Name}`
	if p.ActionText ~= words then
		p.ActionText = words
	end
	local own = piecePrompt(piece)
	local object = if own then own.ObjectText else ""
	if p.ObjectText ~= object then
		p.ObjectText = object
	end
	if not p.Enabled then
		p.Enabled = true
	end
end

function MoveHelperCard.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	MoveHelperHud.useCard(function()
		if MoveHelperCard.isOpen() then
			MoveHelperCard.close()
		else
			MoveHelperCard.open(nil)
		end
	end)
	for _, name in { "MoveHelper", "MoveHelperDoing", "MoveHelperId", "MoveHelperCall", "MoveHelperPrice", "MoveHelperQueue" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if type(player:GetAttribute("MoveHelper")) ~= "string" then
				MoveHelperCard.close()
			elseif opened then
				paint()
			end
			pcall(keepPrompt) -- (his body by his id; off while you wait for him)
		end)
	end
	-- a click (a computer) or the input beside the open card (it closes); B while it is open
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local kind = input.UserInputType
		if opened then
			if input.KeyCode == Enum.KeyCode.ButtonB then
				MoveHelperCard.close()
				return
			end
			if not processed and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and not onCard(input.Position.X, input.Position.Y) then
				MoveHelperCard.close() -- (a click or a tap beside it)
			end
			return
		end
		if processed or kind ~= Enum.UserInputType.MouseButton1 or not mayAct() then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local ray = if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
			then camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
			else camera:ScreenPointToRay(input.Position.X, input.Position.Y)
		clicked(ray.Origin, ray.Direction.Unit)
	end)
	-- a tap on him or on a piece (a touch screen)
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if processed or opened or not mayAct() then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local ray = camera:ScreenPointToRay(position.X, position.Y)
		clicked(ray.Origin, ray.Direction.Unit)
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		pcall(keepPrompt)
		pcall(keepGive)
		if opened then
			paint()
		end
	end)
	-- the screen, the top blocks: placed again
	TopBlocks.onChanged(function()
		place()
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			place()
		end)
	end
	-- his body comes and goes (streaming, a respawn): his prompt follows it (a look every second); the gamepad's "Give to
	-- Danny" follows the nearest piece (a look every quarter second, only while a gamepad is in use)
	task.spawn(function()
		local tick = 0
		while true do
			if tick % 4 == 0 then
				pcall(keepPrompt)
			end
			if Ui.gamepadActive() or give ~= nil then
				pcall(keepGive)
			end
			tick += 1
			task.wait(0.25)
		end
	end)
end

return MoveHelperCard
