--!strict
-- 7.0, the depot's helper's strip (server/MoveHelper.luau: Danny comes with a move whose crew is one player) under the
-- move's panel (client/MovingHud.luau) while he is on your move (your player attribute MoveHelper).
-- 7.0 review: it sits under the move's panel where it really is (client/TopBlocks.luau "MovePanel", its height
-- measured, not assumed), follows it and the screen's size, and is a top-centre block itself ("MoveHelper": the quick
-- chat's lines and the HUD's chips go under or beside it). On a touch screen its button is at least Ui.MinTouch high.
-- 8.3 Danny for hire (the owner: "I have to PAY for him when I want help … click on something, and that assigns it to
-- him"): the strip is his STATUS LINE, two lines of words and one button (shared/MoveHelperBrain.luau's words; the
-- player attributes MoveHelper "offer" | "hired", MoveHelperPrice, MoveHelperQueue, MoveHelperDoing):
--   * for hire: "🧑‍🔧 DANNY · FOR HIRE" over "Carries what you click · $170 this move" (8.3 review: in this device's
--     words, client/PadGlyph.luau: "tap" on a touch screen, "give him" with a gamepad), HIRE $170;
--   * hired: "🧑‍🔧 DANNY · 2 pieces to carry" over what he does, LIST;
--   * you wait for him at a two-person piece (your player attribute MoveHelperCall = its name): orange, "⏳ WAITING FOR
--     DANNY…" ("💪 ON THREE… LIFT!" once he is at its other end: MoveHelperReady, your lift check open), STOP (G on a
--     keyboard too): the Moving remote's ("helper", "stop"); the server decides. 8.3 review: how to stop it in this
--     device's words: "G: stop" on a computer, "tap STOP" on a touch screen, with a gamepad the piece's own "Stop
--     waiting" prompt ("X: stop", SandboxPad's "use") while he comes (nothing once he is there: its prompt is Lift
--     again). Drawn again when the device changes.
--   With his card (client/MoveHelperCard.luau calls MoveHelperHud.useCard: the sandbox) HIRE and LIST open the card (a
--   tap on the line too): its HIRE spends the money, its CLEAR QUEUE empties his list. Without it (the city: client/
--   Main.client.luau starts the card only in the sandbox) HIRE sends ("helper", "hire") itself and LIST is CLEAR
--   (("helper", "clear")). Presentation only.
-- 8.4 (a small phone, 667 × 375: the strip's left end lay on the sandbox's money block and its 📋 TASKS chip): under
-- the panel it keeps clear of the HUD's chips at the top left (client/SandboxHud.luau's MoneyBlock, client/
-- SandboxTasksUi.luau's chip in its ScreenGui "SandboxTasksChip": the shown ones) and the touch controls
-- (MoveLayout.stripClear: shifted right just past the chips, else under them). Moved so, it hides while his card is
-- open (the card shows his status and its button too; on 667 px the shifted strip would take the card's room right of
-- the panel). 844 × 390 and wider: in the middle as before (nothing in its way), shown with the card too.
-- 8.5 Danny's clipboard, orders mode (client/DannyOrders.luau calls MoveHelperHud.useOrders: the sandbox): hired, the
-- button is 📋 ORDERS (it takes the clipboard out; "📋 PUT AWAY", orange, while it is out: shared/ClipboardRules.luau
-- orders) in LIST's place, his card a tap on the line as before; the words say how a piece goes to him
-- (ClipboardRules.carries: "Take out your clipboard (Q) to give him pieces", the device's key) for hire (the price is
-- HIRE's) and while his list is empty and the clipboard away. The city's line as before (no clipboard there).
-- 8.6 the crew's orders (the owner: "… to be able to tell him … get out of the car"): while Danny is in the van, getting
-- in or on his way to it (the server's MoveHelperOrders holds "getout") the button is 🚪 GET OUT, lit: the Moving
-- remote's ("helper", "getout"), the server decides. A driver reaches nothing else (his card shuts and the clipboard
-- stays away in a seat); STOP while you wait for him still comes first.
--   MoveHelperHud.start(), MoveHelperHud.strip()   the strip (nil before Danny first comes)
--   MoveHelperHud.useCard(open)                    8.3 HIRE and LIST open his card (open: the card's opener)
--   MoveHelperHud.cardOpen(open)                   8.4 his card opened or closed (client/MoveHelperCard.luau)
--   MoveHelperHud.useOrders(toggle)                8.5 hired, the button is 📋 ORDERS (toggle: the clipboard out / away)
--   MoveHelperHud.setOrders(on)                    8.5 the clipboard out or away now (client/DannyOrders.luau)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Brain = require(Shared.MoveHelperBrain)
local SandboxPad = require(Shared.SandboxPad) -- 8.3 review: a gamepad button's word
local ClipboardRules = require(Shared.ClipboardRules) -- 8.5: the clipboard's words
local Ui = require(script.Parent.Ui)
local PadGlyph = require(script.Parent.PadGlyph) -- 8.3 review: the device used now
local Theme = require(script.Parent.Theme)
local MoveLayout = require(script.Parent.MoveLayout) -- 7.0 review
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review
local TouchLayout = require(script.Parent.TouchLayout) -- 8.4: the touch controls the strip keeps clear of

local MoveHelperHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local WIDTH, GAP = MoveLayout.PANEL_W, 6
local STATUS_ROW = 32 -- 8.3 the status line's row (its two lines of words, its button)
local ACTION_W = 92 -- 8.3 HIRE / LIST / STOP
local PAD = 6
local CHIP_GUIS = { SandboxHud = "MoneyBlock", SandboxTasksChip = "" } -- 8.4: the HUD's chips (a ScreenGui: its piece, "" every piece)

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local strip: Frame? = nil
local scale: UIScale? = nil
local status: { [string]: any } = {} -- 8.3 the status line's pieces: tap (the line), title, doing, action
local openCard: (() -> ())? = nil -- 8.3 his card's opener (useCard)
local cardShown = false -- 8.4 his card is open (MoveHelperHud.cardOpen)
local moved = false -- 8.4 the strip stands off its place in the middle (MoveLayout.stripClear: a small phone)
local orders: (() -> ())? = nil -- 8.5 the clipboard's toggle (useOrders)
local ordersOn = false -- 8.5 the clipboard is out (setOrders)

local function waiting(): string?
	local call = player:GetAttribute("MoveHelperCall")
	return if type(call) == "string" and call ~= "" then call else nil
end

local function hired(): boolean
	return player:GetAttribute("MoveHelper") == "hired"
end

-- 8.6 GET OUT applies now (the server's MoveHelperOrders: he is in the van, getting in or on his way to it).
local function getOut(): boolean
	return hired() and table.find(Brain.orderList(player:GetAttribute("MoveHelperOrders")), "getout") ~= nil
end

local function priceNow(): number
	local price = player:GetAttribute("MoveHelperPrice")
	return if type(price) == "number" then price else 0
end

-- The button: STOP while you wait; with the card HIRE / LIST open it; without it HIRE and CLEAR go to the server. 8.5
-- hired, with the clipboard (the sandbox): 📋 ORDERS takes it out or puts it away.
local function act()
	if waiting() then
		remote:FireServer("helper", "stop")
		return
	end
	if getOut() then
		-- (8.8 its chirp, as the card's GET OUT: client/MoveHelperCard.luau's ordered, read here when pressed, not
		-- required at the top: the card requires this module)
		pcall(function()
			local card = (script.Parent :: Instance):FindFirstChild("MoveHelperCard")
			if card then
				(require(card :: ModuleScript) :: any).ordered("getout")
			end
		end)
		remote:FireServer("helper", "getout") -- 8.6 (the server decides)
		return
	end
	local toggle = orders
	if toggle and hired() then
		toggle()
		return
	end
	local open = openCard
	if open then
		open()
	elseif hired() then
		remote:FireServer("helper", "clear")
	else
		remote:FireServer("helper", "hire")
	end
end

local function build(): Frame?
	if strip and strip.Parent then
		return strip
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", {
		Name = "MoveHelperHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	local frame = Ui.make("Frame", {
		Name = "DannyLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(WIDTH, STATUS_ROW + 2 * PAD),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, made)
	Ui.corner(frame, 8)
	scale = Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, frame)
	-- the words (a tap opens the card) and the button
	local tap = Ui.make("TextButton", {
		Name = "StatusTap",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.fromOffset(WIDTH - 2 * PAD - ACTION_W - GAP, STATUS_ROW),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Selectable = false,
		Text = "",
	}, frame)
	status.tap = tap
	status.title = Ui.label(tap, "", UDim2.new(1, -8, 0, 16), {
		Name = "Title",
		Position = UDim2.fromOffset(4, 1),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	status.doing = Ui.label(tap, "", UDim2.new(1, -8, 0, 14), {
		Name = "Doing",
		Position = UDim2.fromOffset(4, 17),
		Font = Theme.Font,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local action = Ui.make("TextButton", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, PAD),
		Size = UDim2.fromOffset(ACTION_W, STATUS_ROW),
		BackgroundColor3 = ORANGE,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.charcoal,
		Text = "HIRE",
	}, frame)
	Ui.corner(action, 6)
	status.action = action
	tap.Activated:Connect(function()
		local open = openCard
		if open and not waiting() then
			open()
		end
	end)
	action.Activated:Connect(act)
	strip = frame
	TopBlocks.set("MoveHelper", frame)
	return frame
end

-- Its row a finger's height on a touch screen (in the strip's own px: the UIScale makes them screen px).
local function rowHeight(base: number, s: number): number
	return if Ui.touchLayout() then math.max(base, math.ceil(Ui.MinTouch / s)) else base
end

-- 8.4: what the strip keeps clear of, in its ScreenGui's px: the HUD's shown chips at the top left and, on a touch
-- screen, the touch controls (the buttons, the thumbstick's corner, the jump button).
local function inTheWay(origin: Vector2, W: number, H: number, s: number): ({ TouchLayout.Box }, { TouchLayout.Box })
	local chips: { TouchLayout.Box } = {}
	local function add(object: Instance?)
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
			local at, size = object.AbsolutePosition - origin, object.AbsoluteSize
			table.insert(chips, TouchLayout.box(at.X, at.Y, at.X + size.X, at.Y + size.Y))
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
	local keep: { TouchLayout.Box } = {}
	if Ui.touchLayout() then
		local cluster = TouchLayout.cluster(W, H, s)
		for _, b in TouchLayout.buttons(cluster) do
			table.insert(keep, b)
		end
		table.insert(keep, cluster.thumb)
		table.insert(keep, cluster.jump)
	end
	return chips, keep
end

-- Under the move's panel, where it really is (else where it would be), its row a finger's height on a touch screen;
-- 8.4: clear of the HUD's chips (a small phone: MoveLayout.stripClear), and shown unless his card, open, stands in for
-- it there (MoveHelperHud.cardOpen).
local function place()
	local frame = strip
	if not frame or type(player:GetAttribute("MoveHelper")) ~= "string" then
		return
	end
	local s = Ui.screenScale()
	local scaler = scale
	if scaler and math.abs(scaler.Scale - s) > 0.001 then
		scaler.Scale = s
	end
	local high = rowHeight(STATUS_ROW, s)
	local size = UDim2.fromOffset(WIDTH, high + 2 * PAD)
	local action = status.action :: TextButton
	if action.Size.Y.Offset ~= high then
		action.Size = UDim2.fromOffset(ACTION_W, high)
	end
	local tap = status.tap :: TextButton
	if tap.Size.Y.Offset ~= high then
		tap.Size = UDim2.fromOffset(WIDTH - 2 * PAD - ACTION_W - GAP, high)
		local top = math.floor((high - 31) / 2)
		status.title.Position = UDim2.fromOffset(4, top + 1)
		status.doing.Position = UDim2.fromOffset(4, top + 17)
	end
	if frame.Size ~= size then
		frame.Size = size
	end
	local screen = Ui.screenSize()
	local bottom = MoveLayout.panel(screen.X, s).y1
	local panel = TopBlocks.get("MovePanel")
	local root = gui
	local origin = if root then root.AbsolutePosition else Vector2.new(0, 0)
	if panel and panel.Visible and panel.AbsoluteSize.Y > 1 then
		bottom = panel.AbsolutePosition.Y - origin.Y + panel.AbsoluteSize.Y
	end
	local y = math.floor(bottom + MoveLayout.STRIP_GAP * s + 0.5)
	local w, h = WIDTH * s, (high + 2 * PAD) * s
	local wanted = TouchLayout.box(screen.X / 2 - w / 2, y, screen.X / 2 + w / 2, y + h)
	local chips, keep = inTheWay(origin, screen.X, screen.Y, s)
	local clear = MoveLayout.stripClear(wanted, screen.X, screen.Y, chips, keep)
	moved = clear ~= wanted
	local position = if moved then UDim2.new(0.5, math.floor(clear.x0 - wanted.x0 + 0.5), 0, math.floor(clear.y0 + 0.5)) else UDim2.new(0.5, 0, 0, y)
	if frame.Position ~= position then
		frame.Position = position
	end
	-- 8.4: moved off its place (a small phone, 667 px wide: shifted right it takes the room his card has there), it
	-- gives his open card that room: the card shows his status and its button too
	local shown = not (cardShown and moved)
	if frame.Visible ~= shown then
		frame.Visible = shown
	end
end

local function paint(frame: Frame, title: string, doing: string, button: string, alert: boolean, buttonLit: boolean)
	frame.BackgroundColor3 = if alert then ORANGE else K.charcoal
	status.title.Text = title
	status.title.TextColor3 = if alert then K.charcoal else K.text
	status.doing.Text = doing
	status.doing.TextColor3 = if alert then K.charcoal else K.secondary
	status.action.Text = button
	status.action.BackgroundColor3 = if alert then K.charcoal elseif buttonLit then ORANGE else K.row
	status.action.TextColor3 = if alert then K.text elseif buttonLit then K.charcoal else K.text
end

-- 8.3 review: how you stop waiting for him, in this device's words (none: the line says only where you are).
local function stopWords(ready: boolean): string
	local device = PadGlyph.device()
	if device == "keys" then
		return " · G: stop"
	elseif device == "touch" then
		return " · tap STOP"
	end
	local word = if ready then nil else SandboxPad.keyWord("use", device) -- (the piece's "Stop waiting" prompt)
	return if word then ` · {word}: stop` else ""
end

-- 8.3 review: what he carries for you, in this device's words. 8.5 with the clipboard (the sandbox): how a piece goes to
-- him ("Take out your clipboard (Q) to give him pieces": its key on this device).
local function carriesWords(): string
	local device = PadGlyph.device()
	if orders then
		return ClipboardRules.carries(device)
	end
	return if device == "touch" then "Carries what you tap" elseif device == "pad" then "Carries what you give him" else "Carries what you click"
end

local function refresh()
	local state = player:GetAttribute("MoveHelper")
	local on = type(state) == "string"
	local frame = if on then build() else strip
	if not frame then
		return
	end
	if not on then
		frame.Visible = false
		return
	end
	place() -- (it shows it: 8.4, unless his card stands in for it)
	local name = string.upper(Config.MoveHelper.Name)
	local doing = player:GetAttribute("MoveHelperDoing")
	local piece = waiting()
	if piece then
		-- you wait for him at your end of a two-person piece (then he is there: your lift): STOP (G) ends it
		local ready = player:GetAttribute("MoveHelperReady") == true
		paint(frame, if ready then "💪 ON THREE… LIFT!" else `⏳ WAITING FOR {name}…`,
			(if ready then `{Config.MoveHelper.Name} is at the other end of the {piece}` else `Stay at your end of the {piece}`) .. stopWords(ready), "STOP", true, false)
	elseif hired() then
		-- (8.5: with the clipboard the button is 📋 ORDERS, orange while it is out; his list empty and the clipboard
		-- away, the words say how a piece goes to him; 8.6 while he is in the van, getting in or on his way to it: 🚪 GET
		-- OUT, lit: the one order a driver can reach, the clipboard and his card are for on foot)
		local count = player:GetAttribute("MoveHelperQueue")
		local out = getOut()
		local how = not out and orders ~= nil and not ordersOn and (type(count) ~= "number" or count <= 0)
		paint(frame, `🧑‍🔧 {name} · {Brain.queueText(count)}`, if how then carriesWords() elseif type(doing) == "string" then doing else "",
			if out then Brain.orderWords("getout") elseif orders then ClipboardRules.orders(ordersOn) elseif openCard then "LIST" else "CLEAR", false,
			out or (orders ~= nil and ordersOn))
	else
		local price = Brain.money(priceNow())
		-- (8.5: with the clipboard its words alone, the price HIRE's)
		paint(frame, `🧑‍🔧 {name} · FOR HIRE`, if orders then carriesWords() else `{carriesWords()} · {price} this move`, `HIRE {price}`, false, true)
	end
end

function MoveHelperHud.strip(): Frame?
	return strip
end

-- 8.3 Danny's card is there (client/MoveHelperCard.luau's start): HIRE, LIST and a tap on the line open it.
function MoveHelperHud.useCard(open: () -> ())
	openCard = open
	refresh()
end

-- 8.4 his card opened or closed (client/MoveHelperCard.luau): where the strip had to move off its place in the middle
-- (a small phone) it hides while the card is open, the card in its room.
function MoveHelperHud.cardOpen(open: boolean)
	if cardShown ~= open then
		cardShown = open
		place()
	end
end

-- 8.5 Danny's clipboard is there (client/DannyOrders.luau's start): hired, the button is 📋 ORDERS.
function MoveHelperHud.useOrders(toggle: () -> ())
	orders = toggle
	refresh()
end

-- 8.5 the clipboard out or away (client/DannyOrders.luau, at every change it sees): the button's words and colour.
function MoveHelperHud.setOrders(on: boolean)
	if ordersOn ~= on then
		ordersOn = on
		refresh()
	end
end

function MoveHelperHud.start()
	for _, name in { "MoveHelper", "MoveHelperDoing", "MoveHelperCall", "MoveHelperReady", "MoveHelperPrice", "MoveHelperQueue", "MoveHelperOrders" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	-- 7.0 review: the panel moved, resized, showed or hid (client/TopBlocks.luau), the screen changed size
	TopBlocks.onChanged(function()
		place()
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			place()
		end)
	end
	-- 8.3 G while you wait for him: you stop waiting (the server ends the call)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.G and waiting() then
			remote:FireServer("helper", "stop")
		end
	end)
	PadGlyph.watch(refresh) -- 8.3 review: a gamepad picked up or put down, the screen touched: the words again
	refresh()
end

return MoveHelperHud
