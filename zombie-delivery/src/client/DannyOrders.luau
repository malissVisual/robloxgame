--!strict
-- 8.5 SANDBOX, Danny's clipboard on the client: ORDERS MODE (the owner: "When I want to give work to my employee, the
-- helper, I'll hold a paper in my hand, like a notepad. At that moment I'm in a kind of ordering mode and I click on
-- what he should carry."). server/Clipboard.luau decides: your character's ClipboardHeld (only the server sets it) is
-- the clipboard in your right hand, everybody sees it (client/ArmPose.luau holds it up); this asks for it (the Clipboard
-- remote: true takes it out, false puts it away) and shows the mode. The words are shared/ClipboardRules.luau's.
--   * Taking it out and putting it away, only while Danny works for your move (your player attribute MoveHelper =
--     "hired"): the key Config.MoveHelper.Clipboard.Key (Q: free in the sandbox; shared/SandboxPad.luau's "clipboard"
--     and "stow"), a gamepad's R1 (out; with it out R1 by a piece gives it to him: client/MoveHelperCard.luau's "Give to
--     Danny") and B (away, nothing else taking it: no window open, no GUI selection), the touch 📋 button (ORDERS:
--     DannyOrders.layout puts it where the grip check's TAP goes, MoveLayout.tapSpots: never both, the grip's only while
--     you carry), Danny's status line's 📋 ORDERS (client/MoveHelperHud.luau useOrders), his card's 📋 CLIPBOARD
--     (client/MoveHelperCard.luau). The server refuses with a notice (your hands full, a seat …) and puts it away by
--     itself (a pick, a seat, death, the move's end, the hire over): the attribute goes, the mode with it.
--   * Orders mode (the clipboard out): client/MoveHelperCard.luau gives a piece only then (a click, a tap, R1; no click
--     opens his card meanwhile). The piece you point at (the crosshair's middle while the camera holds the mouse, else
--     the mouse; with a gamepad R1's piece, the nearest; on a touch screen the one just tapped, Clipboard.Flash s) is
--     outlined (one Highlight in a local folder, workspace.DannyOrders: Roblox draws 31 at most, client/
--     EnemyOutline.luau keeps 7 spare) green when it can be given, orange when it is on his list (take it back), red
--     when it can't, with its words over it (ClipboardRules.look: the server's MoveHelperBrain.assignCheck guessed from
--     what this client sees: its own prompt shown, what its weld holds it to, his list, how far; his list's numbers are
--     the server's markers over the pieces), looked at every Clipboard.Look s. 8.6 Danny himself (or the piece in his
--     arms) pointed at: orange, "📋 Orders for Danny" (a click opens his orders menu: client/MoveHelperCard.luau
--     target). A line at the bottom says the mode:
--     "📋 Pick what Danny carries · Q put away" (the device's words: ClipboardRules.hint) clear of the HUD's groups, the
--     chips, the move's top blocks (its panel, Danny's status line, the guide's line), the quick chat's button, the move's
--     list, the touch controls and the 📋 button (DannyOrders.layout). It is no window (nothing closes for it; 9.0: the
--     sandbox's cursor is free, client/CameraRig.luau aimOnly, and points) and steps aside while one covers the screen
--     (DannyOrders.covered: Main's, his card open, a grip check): the line, the outline and the 📋 button hidden, R1 and
--     B left to the window.
--   * 8.9 its sounds (art/audio/sfx5.ogg, quiet: client/SandboxSounds.luau event): the clipboard taken out (a paper
--     rustle and the clip) and put away, whoever did it (your ClipboardHeld changed, looked at with the rest every
--     Clipboard.Look s: shared/SoundPlan.luau clipboardCue; a new body: none); asked out and refused (the server's
--     notice), the soft nope in place of the notice's ping (SandboxSounds.await). The pieces' tick and cross-off are
--     client/MoveHelperCard.luau's (it sends them).
-- Presentation only.
--   DannyOrders.start()                     listens (nothing outside the sandbox)
--   DannyOrders.on() -> boolean             the clipboard out (orders mode)
--   DannyOrders.toggle(out?)                asks the server: out (true), away (false), the other way (nil)
--   DannyOrders.covered                     set by client/Main.client.luau: does a window cover the screen now?
--   DannyOrders.hint(), .button()           the bottom line's frame, the touch button (the checks; nil before built)
--   DannyOrders.lit() -> (Model?, string?)  the piece outlined now and its words (the checks)
--   DannyOrders.layout(W, H, S, touch, blocks, hintW) -> (hint, scale, button?)   where the line (hintW px wide at scale
--                                           1) and the touch button go (pure; px under Roblox's top bar)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Brain = require(Shared.MoveHelperBrain)
local ClipboardRules = require(Shared.ClipboardRules)
local SandboxPad = require(Shared.SandboxPad)
local SoundPlan = require(Shared.SoundPlan) -- 8.9 (the clipboard's sounds)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local PadGlyph = require(script.Parent.PadGlyph)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout)
local TopBlocks = require(script.Parent.TopBlocks)
local MoveHelperHud = require(script.Parent.MoveHelperHud)
local MoveHelperCard = require(script.Parent.MoveHelperCard)
local CarryGripUi = require(script.Parent.CarryGripUi)

local DannyOrders = {}

DannyOrders.covered = nil :: (() -> boolean)?

local H = Config.MoveHelper
local C = H.Clipboard
local K = Theme.Contract
local player = Players.LocalPlayer
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local KEY = (Enum.KeyCode :: any)[C.Key]
local OUT_PAD = (Enum.KeyCode :: any)[SandboxPad.pads("clipboard")[1] or "ButtonR1"]
local AWAY_PAD = (Enum.KeyCode :: any)[SandboxPad.pads("stow")[1] or "ButtonB"]
local MARGIN, GAP = 8, 8
local LEAST = 0.8 -- × the HUD's scale: the line at its smallest (its words need the room)
-- the HUD's groups (client/CarryGripUi.luau's list) and the sandbox's chips' ScreenGuis (a piece of it, "" every piece)
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" }
local CHIP_GUIS = { SandboxHud = "MoneyBlock", SandboxTasksChip = "" }

local remote = Net.get("Clipboard")
local started = false
local gui: ScreenGui? = nil
local parts: { [string]: any } = {}
local words = "" -- the line's words now (its width follows them)
local wordsW = 0 -- …their width at scale 1
local litPiece: Model? = nil
local litWords: string? = nil
local placedKey = "" -- what the last place() was for (placed again when it changes, or a second later)
local placedAt = 0
local clipBody: Model? = nil -- 8.9 the body the clipboard was last looked at on …
local clipWas = false -- … and whether it was out then

-- ── Where it goes (pure maths: the phone-ui check runs it) ──────────────────

local function clearOf(b: TouchLayout.Box, W: number, Hh: number, blocks: { TouchLayout.Box }): boolean
	if not MoveLayout.inside(b, W, Hh) then
		return false
	end
	for _, other in blocks do
		if TouchLayout.overlap(b, other) then
			return false
		end
	end
	return true
end

function DannyOrders.layout(W: number, Hh: number, S: number, touch: boolean, blocks: { TouchLayout.Box }, hintW: number): (TouchLayout.Box, number, TouchLayout.Box?)
	local avoid = table.clone(blocks)
	local button: TouchLayout.Box? = nil
	local left, right = MARGIN, W - MARGIN
	local bottom = Hh - GAP - 18 * S -- (the HUD's contextual line's: TouchLayout.hint)
	if touch then
		local c = TouchLayout.cluster(W, Hh, S)
		for _, b in TouchLayout.buttons(c) do
			table.insert(avoid, b)
		end
		table.insert(avoid, c.thumb)
		table.insert(avoid, c.jump)
		-- the 📋 button: the grip's TAP places (over FIRE, over the column, beside it …), the first clear one, else the
		-- one that covers the least
		local size = math.max(C.ButtonMin, Ui.MinTouch, C.Button * S)
		local best: TouchLayout.Box? = nil
		local bestCost = math.huge
		for _, spot in MoveLayout.tapSpots(W, Hh, S, size) do
			local cost = MoveLayout.clash(spot, W, Hh, avoid)
			if cost < bestCost - 1e-6 then
				best, bestCost = spot, cost
			end
			if cost <= 0 then
				break
			end
		end
		button = best
		if best then
			table.insert(avoid, TouchLayout.box(best.x0 - GAP, best.y0 - GAP, best.x1 + GAP, best.y1 + GAP))
		end
		left, right = TouchLayout.hintSpan(c, TouchLayout.buttons(c), bottom - 96 * S, W)
	end
	-- the line: at the bottom in the middle (on a touch screen between the thumbstick's corner and the buttons), at the
	-- HUD's scale, smaller down to LEAST × it; else over what is at the bottom (flush over its top); the clear place
	-- nearest the middle of the bottom; none: the one that covers the least
	local fallback: TouchLayout.Box? = nil
	local fallbackScale, fallbackCost = S, math.huge
	local scale = S
	while true do
		local w, h = hintW * scale, C.Tall * scale
		local ys = { bottom }
		local xs = { W / 2, math.clamp(W / 2, left + w / 2, math.max(left + w / 2, right - w / 2)) }
		for _, b in avoid do
			if b.y0 > Hh * 0.45 then
				table.insert(ys, b.y0 - GAP)
			end
			if b.y1 > Hh * 0.45 then
				table.insert(xs, b.x1 + GAP + w / 2)
				table.insert(xs, b.x0 - GAP - w / 2)
			end
		end
		local best: TouchLayout.Box? = nil
		local bestNear = math.huge
		for _, y1 in ys do
			local y0 = math.floor(math.clamp(y1 - h, MARGIN, math.max(MARGIN, Hh - MARGIN - h)) + 0.5)
			for _, cx in xs do
				local x0 = math.floor(math.clamp(cx - w / 2, MARGIN, math.max(MARGIN, W - MARGIN - w)) + 0.5)
				local b = TouchLayout.box(x0, y0, x0 + w, y0 + h)
				local near = math.abs(x0 + w / 2 - W / 2) + 2 * math.abs(y0 + h - bottom)
				if near < bestNear and clearOf(b, W, Hh, avoid) then
					best, bestNear = b, near
				end
				local bad = MoveLayout.clash(b, W, Hh, avoid) + 1e-3 * near
				if bad < fallbackCost then
					fallback, fallbackScale, fallbackCost = b, scale, bad
				end
			end
		end
		if best then
			return best, scale, button
		end
		if scale <= S * LEAST + 1e-6 then
			break
		end
		scale = math.max(S * LEAST, scale - 0.05)
	end
	local w, h = hintW * S, C.Tall * S
	return (fallback or TouchLayout.box(W / 2 - w / 2, bottom - h, W / 2 + w / 2, bottom)) :: TouchLayout.Box, fallbackScale, button
end

-- ── The state ──────────────────────────────────────────────────────────────

local function hired(): boolean
	return player:GetAttribute("MoveHelper") == "hired"
end

function DannyOrders.on(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("ClipboardHeld") == true
end

-- 8.9 the newest sounds (client/SandboxSounds.luau: found when first wanted; nothing where it is not there).
local function sandboxSounds(): any
	local ok, found = pcall(function(): any
		return require(script.Parent.SandboxSounds)
	end)
	return if ok then found else nil
end

local function sound(event: string)
	local found = sandboxSounds()
	if found then
		pcall(found.event, event)
	end
end

function DannyOrders.toggle(out: boolean?)
	local want = if out == nil then not DannyOrders.on() else out
	if want and not hired() then
		return -- (no Danny working for you: nothing to give orders to)
	end
	local was = DannyOrders.on()
	remote:FireServer(want)
	local found = if want and not was then sandboxSounds() else nil
	if found then
		-- 8.9 asked out: its rustle comes with ClipboardHeld (step); refused, the server's notice: the soft nope
		pcall(found.await, function(): string?
			return if DannyOrders.on() then "" else nil
		end)
	end
end

-- Does a window, his card or a grip check cover the screen now?
local function covered(): boolean
	local hook = DannyOrders.covered
	return (hook ~= nil and hook()) or MoveHelperCard.isOpen() or CarryGripUi.active()
end

-- May the clipboard come out now, as far as this client sees (the 📋 button shows then; the server decides)?
local function mayTake(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return hired() and character ~= nil and character:GetAttribute("Carrying") == nil and character:GetAttribute("Pushing") == nil
		and not (humanoid ~= nil and humanoid.SeatPart ~= nil)
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- What a piece's weld holds it to: "player" or "danny" (a body: its carrier), "van" (the van's body), nil (none).
local function holderOf(model: Model): string?
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	for _, child in root:GetChildren() do
		if child:IsA("WeldConstraint") or child:IsA("Weld") then
			local weld = child :: any
			local other = if weld.Part0 == root then weld.Part1 else weld.Part0
			if other and other:IsA("BasePart") then
				local body = other:FindFirstAncestorOfClass("Model")
				if body and body:FindFirstChildOfClass("Humanoid") then
					return if body:GetAttribute("MoveHelper") ~= nil then "danny" else "player"
				end
				return "van"
			end
		end
	end
	return nil
end

-- The server's answer for a piece, guessed from what this client sees (MoveHelperBrain.assignCheck): its words and tone.
local function lookOf(model: Model): (string?, string)
	if model == MoveHelperCard.body() then
		return `📋 Orders for {H.Name}`, "back" -- 8.6 (a click opens his orders menu: MoveHelperCard.target)
	end
	local prompt = MoveHelperCard.promptOf(model)
	local root, mine = model.PrimaryPart, myRoot()
	if not prompt or not root then
		return nil, "no"
	end
	local queued = model:GetAttribute("DannyQueue")
	local count = player:GetAttribute("MoveHelperQueue")
	local shown = prompt.Enabled
	local state, held, his = ClipboardRules.holder(shown, if shown then nil else holderOf(model))
	local dx, dz = 0, 0
	if mine then
		dx, dz = root.Position.X - mine.Position.X, root.Position.Z - mine.Position.Z
	end
	local verdict = Brain.assignCheck({
		crew = true,
		hired = hired(),
		mine = true,
		state = state,
		held = held,
		his = his,
		queued = type(queued) == "number",
		count = if type(count) == "number" then count else 0,
		near = mine ~= nil and math.sqrt(dx * dx + dz * dz) <= H.ClickReach,
		clipboard = true,
	})
	return ClipboardRules.look(verdict, if type(queued) == "number" then queued else nil, if type(count) == "number" then count else nil)
end

-- The piece pointed at now: a gamepad's R1 piece, a touch screen's tapped one (a moment), else under the crosshair or
-- the mouse.
local function pointed(): Model?
	if Ui.gamepadActive() then
		return MoveHelperCard.giveTarget()
	end
	if Ui.touchLayout() then
		local piece, at = MoveHelperCard.tapped()
		return if piece and piece.Parent and os.clock() - at < C.Flash then piece else nil
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	else
		local at = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(at.X, at.Y)
	end
	return (MoveHelperCard.target(ray.Origin, ray.Direction.Unit)) -- (8.6: a piece, or Danny himself: his orders)
end

-- ── Its pieces ─────────────────────────────────────────────────────────────

local function build(): boolean
	local made = parts.hint
	if made and made.Parent then
		return true
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	local screen = Ui.make("ScreenGui", {
		Name = "DannyOrders",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = screen
	-- the line at the bottom: "📋 Pick what Danny carries · Q put away"
	local hint = Ui.make("Frame", {
		Name = "OrdersHint",
		Size = UDim2.fromOffset(200, C.Tall),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, screen)
	Ui.corner(hint, 8)
	Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 1.5 }, hint)
	parts.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, hint)
	parts.words = Ui.label(hint, "", UDim2.fromOffset(200 - 2 * C.Pad, C.Tall), {
		Name = "Words",
		Position = UDim2.fromOffset(C.Pad, 0),
		Font = Theme.Font,
		TextSize = C.Text,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	-- the touch 📋 button (ORDERS: orange while it is out)
	local button = Ui.make("TextButton", {
		Name = "ClipboardButton",
		Size = UDim2.fromOffset(C.Button, C.Button),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 22,
		TextColor3 = K.text,
		Text = "📋",
		Visible = false,
	}, screen)
	Ui.corner(button, 10)
	Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 1.5 }, button)
	parts.word = Ui.label(button, "ORDERS", UDim2.new(1, 0, 0, 12), {
		Name = "Word",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -3),
		Font = Theme.HeadingFont,
		TextSize = 10,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	button.Activated:Connect(function()
		DannyOrders.toggle(nil)
	end)
	-- the piece pointed at: its outline (a local folder in the world) and its words over it
	local folder = workspace:FindFirstChild("DannyOrders") or Ui.make("Folder", { Name = "DannyOrders" }, workspace)
	parts.mark = Ui.make("Highlight", {
		Name = "Pointed",
		Enabled = false,
		FillTransparency = 0.78,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	}, folder)
	local tag = Ui.make("BillboardGui", {
		Name = "DannyOrdersTag",
		ResetOnSpawn = false, -- (kept over a respawn, as its ScreenGui)
		Enabled = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(230, 26),
		MaxDistance = H.ClickReach + 20,
	}, playerGui)
	parts.tag = tag
	parts.tagWords = Ui.label(tag, "", UDim2.fromScale(1, 1), {
		Name = "Words",
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.15,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.corner(parts.tagWords, 6)
	parts.hint, parts.button = hint, button
	return true
end

function DannyOrders.hint(): Frame?
	return parts.hint
end

function DannyOrders.button(): TextButton?
	return parts.button
end

function DannyOrders.lit(): (Model?, string?)
	return litPiece, litWords
end

-- What the line and the button keep clear of, in its ScreenGui's px.
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

-- The line's words for the device now, and their width at scale 1.
local function setWords()
	local text = ClipboardRules.hint(PadGlyph.device())
	if text == words then
		return
	end
	words = text
	local ok, size = pcall(function(): Vector2
		return TextService:GetTextSize(text, C.Text, Theme.Font, Vector2.new(2000, 100))
	end)
	wordsW = math.ceil(if ok and size then size.X else #text * C.Text * 0.55) + 2
	parts.words.Text = text
	placedKey = "" -- (placed again for them)
end

-- Its place and size for this screen (when what it is for changed, or a second later).
local function place(force: boolean?)
	local screen = gui
	local hint, button = parts.hint, parts.button
	if not screen or not hint or not button then
		return
	end
	local touch = Ui.touchLayout()
	local size = screen.AbsoluteSize
	local W, Hh = size.X, size.Y
	if W < 2 or Hh < 2 then
		local s = Ui.screenSize()
		W, Hh = s.X, s.Y
	end
	local key = `{W}x{Hh}|{touch}|{words}`
	if not force and key == placedKey and os.clock() - placedAt < 1 then
		return
	end
	placedKey, placedAt = key, os.clock()
	local S = Ui.screenScale()
	local hintW = wordsW + 2 * C.Pad
	local b, scale, spot = DannyOrders.layout(W, Hh, S, touch, blocksNow(screen.AbsolutePosition), hintW)
	hint.Size = UDim2.fromOffset(hintW, C.Tall)
	parts.words.Size = UDim2.fromOffset(wordsW, C.Tall)
	parts.scale.Scale = scale
	hint.Position = UDim2.fromOffset(math.floor(b.x0 + 0.5), math.floor(b.y0 + 0.5))
	if spot then
		local side = math.floor(spot.x1 - spot.x0 + 0.5)
		button.Size = UDim2.fromOffset(side, side)
		button.Position = UDim2.fromOffset(math.floor(spot.x0 + 0.5), math.floor(spot.y0 + 0.5))
		button.TextSize = math.floor(side * 0.42)
		parts.word.TextSize = math.max(8, math.floor(side * 0.2))
		parts.word.Size = UDim2.new(1, 0, 0, math.floor(side * 0.25))
	end
end

-- The piece outlined (nil: none) with its words in its tone's colour.
local function mark(piece: Model?, text: string?, tone: string)
	local highlight = parts.mark :: Highlight?
	local tag = parts.tag :: BillboardGui?
	if not highlight or not tag then
		return
	end
	local root = if piece then piece.PrimaryPart else nil
	if not piece or not text or not root then
		litPiece, litWords = nil, nil
		if highlight.Enabled then
			highlight.Enabled = false
			(highlight :: any).Adornee = nil
		end
		if tag.Enabled then
			tag.Enabled = false
			(tag :: any).Adornee = nil
		end
		return
	end
	local rgb = if tone == "give" then C.Give elseif tone == "back" then C.Back else C.No
	local color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	litPiece, litWords = piece, text
	if highlight.Adornee ~= piece then
		highlight.Adornee = piece
	end
	highlight.OutlineColor, highlight.FillColor = color, color
	highlight.Enabled = true
	if tag.Adornee ~= root then
		tag.Adornee = root
	end
	parts.tagWords.Text = text
	parts.tagWords.TextColor3 = color
	tag.Enabled = true
end

-- One look: the line, the button, the outline (every Clipboard.Look s, and when something changed).
local function step()
	if not build() then
		return
	end
	local on = DannyOrders.on()
	MoveHelperHud.setOrders(on)
	-- 8.9 the clipboard taken out or put away (by you or by the server): its sound (a new body: none)
	local character = player.Character
	if character ~= clipBody then
		clipBody, clipWas = character, on
	elseif on ~= clipWas then
		local cue = SoundPlan.clipboardCue(clipWas, on)
		clipWas = on
		if cue then
			sound(cue)
		end
	end
	local hide = covered()
	local showHint = on and hired() and not hide
	local showButton = Ui.touchLayout() and not Ui.gamepadActive() and hired() and not hide and (on or mayTake())
	if showHint or showButton then
		setWords()
		place(false)
	end
	if parts.hint.Visible ~= showHint then
		parts.hint.Visible = showHint
	end
	if parts.button.Visible ~= showButton then
		parts.button.Visible = showButton
	end
	if parts.lit ~= on then -- (orange while it is out)
		parts.lit = on
		parts.button.BackgroundColor3 = if on then ORANGE else K.charcoal
		parts.button.TextColor3 = if on then K.charcoal else K.text
		parts.word.TextColor3 = if on then K.charcoal else K.text
	end
	if showHint then
		local piece = pointed()
		local text, tone = nil, "no"
		if piece then
			text, tone = lookOf(piece)
		end
		mark(piece, text, tone)
	else
		mark(nil, nil, "no")
	end
end

function DannyOrders.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	MoveHelperHud.useOrders(function()
		DannyOrders.toggle(nil)
	end)
	-- Q; a gamepad's R1 (out) and B (away), nothing else taking them
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local key = input.KeyCode
		if processed or not hired() or (key ~= KEY and key ~= OUT_PAD and key ~= AWAY_PAD) then
			return
		end
		local on = DannyOrders.on()
		if key == KEY then
			DannyOrders.toggle(not on)
		elseif key == OUT_PAD and not on and not covered() then
			DannyOrders.toggle(true) -- (out: R1 by a piece gives it to him, MoveHelperCard's "Give to Danny")
		elseif key == AWAY_PAD and on and not covered() and not MoveHelperCard.justClosed() and Ui.gamepadSelection() == nil then
			DannyOrders.toggle(false) -- (a window's B is the window's: his card's even when it heard it first)
		end
	end)
	for _, name in { "MoveHelper", "MoveHelperQueue" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			pcall(step)
		end)
	end
	PadGlyph.watch(function()
		pcall(step)
	end)
	TopBlocks.onChanged(function()
		placedKey = ""
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			placedKey = ""
		end)
	end
	-- the look (Clipboard.Look s): cheap while Danny is not hired (nothing shown)
	task.spawn(function()
		while true do
			local ok, err = pcall(step :: any)
			if not ok then
				warn(`[DannyOrders] {err}`)
			end
			task.wait(C.Look)
		end
	end)
end

return DannyOrders
