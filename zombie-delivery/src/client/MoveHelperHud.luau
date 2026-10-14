--!strict
-- 7.0, the depot's helper's strip (server/MoveHelper.luau: Danny joins a move whose crew is one player) under the
-- move's panel (client/MovingHud.luau) while he is on your move (your player attribute MoveHelper = the order in force).
-- 7.0 review: it sits under the move's panel where it really is (client/TopBlocks.luau "MovePanel", its height
-- measured, not assumed), follows it and the screen's size, and is a top-centre block itself ("MoveHelper": the quick
-- chat's lines and the HUD's chips go under or beside it). On a touch screen its buttons are at least Ui.MinTouch high.
-- 8.3 Danny's orders (the owner: "I'd like to click on him any time and tell him what to do"): the orders live on his
-- command card (client/MoveHelperCard.luau: a click or a tap on him), so with the card (it calls MoveHelperHud.useCard)
-- the strip is his compact STATUS LINE: "🧑‍🔧 DANNY · AUTO" over what he does (shared/MoveHelperBrain.luau status: the
-- player attributes MoveHelper and MoveHelperDoing) and an ORDERS button (a tap on the line too) that opens the card.
-- While you wait for him at a two-person piece (your player attribute MoveHelperCall = its name) the line turns orange,
-- "⏳ WAITING FOR DANNY…" ("💪 ON THREE… LIFT!" once he is at its other end: MoveHelperReady, your lift check open),
-- and its button is STOP (G on a keyboard too): the Moving remote's ("helper", "stop"); the server decides. Without a
-- card (the city: client/Main.client.luau starts it only in the sandbox) the line and a row of the four orders (AUTO,
-- HELP ME, WAIT HERE, AT VAN), the one in force lit: a tap sends the Moving remote's ("helper", order). Presentation
-- only.
--   MoveHelperHud.start(), MoveHelperHud.strip()   the strip (nil before Danny first joins)
--   MoveHelperHud.useCard(open)                    8.3 the status line with ORDERS (open: the card's opener)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Brain = require(Shared.MoveHelperBrain)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local MoveLayout = require(script.Parent.MoveLayout) -- 7.0 review
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review

local MoveHelperHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local WIDTH, ROW, GAP = MoveLayout.PANEL_W, 30, 6
local LINE_H = 26 -- the city's line over its buttons
local STATUS_ROW = 32 -- 8.3 the status line's row (its two lines of words, its button)
local ACTION_W = 92 -- 8.3 ORDERS / STOP
local PAD = 6
local ORDERS = {
	{ id = "auto", text = "AUTO" },
	{ id = "help", text = "HELP ME" },
	{ id = "stay", text = "WAIT HERE" },
	{ id = "van", text = "AT VAN" },
}

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local strip: Frame? = nil
local line: TextLabel? = nil -- the city's line
local scale: UIScale? = nil
local buttons: { [string]: TextButton } = {}
local status: { [string]: any } = {} -- 8.3 the status line's pieces: tap (the line), title, doing, action
local openCard: (() -> ())? = nil -- 8.3 the command card's opener (useCard)

local function waiting(): string?
	local call = player:GetAttribute("MoveHelperCall")
	return if type(call) == "string" and call ~= "" then call else nil
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
		Name = "Orders",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(WIDTH, LINE_H + ROW + 8),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, made)
	Ui.corner(frame, 8)
	scale = Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, frame)
	-- the city's line and its row of orders
	line = Ui.label(frame, "", UDim2.new(1, -20, 0, 18), {
		Name = "Line",
		Position = UDim2.fromOffset(10, 5),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local width = (WIDTH - 20 - (#ORDERS - 1) * GAP) / #ORDERS
	for index, order in ORDERS do
		local button = Ui.make("TextButton", {
			Name = order.id,
			Size = UDim2.fromOffset(width, ROW),
			Position = UDim2.fromOffset(10 + (index - 1) * (width + GAP), LINE_H),
			BackgroundColor3 = K.row,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = K.text,
			Text = order.text,
		}, frame)
		Ui.corner(button, 6)
		local id = order.id
		button.Activated:Connect(function()
			remote:FireServer("helper", id)
		end)
		buttons[id] = button
	end
	-- 8.3 the status line (with the card): the words (a tap opens the card) and ORDERS / STOP
	local tap = Ui.make("TextButton", {
		Name = "StatusTap",
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.fromOffset(WIDTH - 2 * PAD - ACTION_W - GAP, STATUS_ROW),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Selectable = false,
		Text = "",
		Visible = false,
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
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.text,
		Text = "ORDERS",
		Visible = false,
	}, frame)
	Ui.corner(action, 6)
	status.action = action
	tap.Activated:Connect(function()
		local open = openCard
		if open and not waiting() then
			open()
		end
	end)
	action.Activated:Connect(function()
		if waiting() then
			remote:FireServer("helper", "stop")
			return
		end
		local open = openCard
		if open then
			open()
		end
	end)
	strip = frame
	TopBlocks.set("MoveHelper", frame)
	return frame
end

-- Its rows a finger's height on a touch screen (in the strip's own px: the UIScale makes them screen px).
local function rowHeight(base: number, s: number): number
	return if Ui.touchLayout() then math.max(base, math.ceil(Ui.MinTouch / s)) else base
end

-- Under the move's panel, where it really is (else where it would be), its own rows a finger's height on a touch screen.
local function place()
	local frame = strip
	if not frame or not frame.Visible then
		return
	end
	local s = Ui.screenScale()
	local scaler = scale
	if scaler and math.abs(scaler.Scale - s) > 0.001 then
		scaler.Scale = s
	end
	local size: UDim2
	if openCard then
		-- 8.3 the status line: one row
		local high = rowHeight(STATUS_ROW, s)
		size = UDim2.fromOffset(WIDTH, high + 2 * PAD)
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
	else
		local high = rowHeight(ROW, s)
		size = UDim2.fromOffset(WIDTH, LINE_H + high + 8)
		for _, button in buttons do
			if button.Size.Y.Offset ~= high then
				button.Size = UDim2.fromOffset(button.Size.X.Offset, high)
			end
		end
	end
	if frame.Size ~= size then
		frame.Size = size
	end
	local bottom = MoveLayout.panel(Ui.screenSize().X, s).y1
	local panel = TopBlocks.get("MovePanel")
	local root = gui
	if panel and panel.Visible and panel.AbsoluteSize.Y > 1 then
		local origin = if root then root.AbsolutePosition.Y else 0
		bottom = panel.AbsolutePosition.Y - origin + panel.AbsoluteSize.Y
	end
	local position = UDim2.new(0.5, 0, 0, math.floor(bottom + MoveLayout.STRIP_GAP * s + 0.5))
	if frame.Position ~= position then
		frame.Position = position
	end
end

local function refresh()
	local mode = player:GetAttribute("MoveHelper")
	local on = type(mode) == "string"
	local frame = if on then build() else strip
	if not frame then
		return
	end
	frame.Visible = on
	if not on then
		return
	end
	local card = openCard ~= nil
	local label = line
	if label then
		label.Visible = not card
	end
	for _, button in buttons do
		button.Visible = not card
	end
	status.tap.Visible = card
	status.action.Visible = card
	place()
	local doing = player:GetAttribute("MoveHelperDoing")
	local name = string.upper(Config.MoveHelper.Name)
	if card then
		local piece = waiting()
		if piece then
			-- you wait for him at your end of a two-person piece (then he is there: your lift): STOP (G) ends it
			local ready = player:GetAttribute("MoveHelperReady") == true
			frame.BackgroundColor3 = ORANGE
			status.title.Text = if ready then "💪 ON THREE… LIFT!" else `⏳ WAITING FOR {name}…`
			status.title.TextColor3 = K.charcoal
			status.doing.Text = if ready then `{Config.MoveHelper.Name} is at the other end of the {piece} · G: stop`
				else `Stay at your end of the {piece} · G: stop`
			status.doing.TextColor3 = K.charcoal
			status.action.Text = "STOP"
			status.action.BackgroundColor3 = K.charcoal
			status.action.TextColor3 = K.text
		else
			frame.BackgroundColor3 = K.charcoal
			status.title.Text = `🧑‍🔧 {name} · {Brain.modeName(mode)}`
			status.title.TextColor3 = K.text
			status.doing.Text = if type(doing) == "string" then doing else ""
			status.doing.TextColor3 = K.secondary
			status.action.Text = "ORDERS"
			status.action.BackgroundColor3 = ORANGE
			status.action.TextColor3 = K.charcoal
		end
		return
	end
	frame.BackgroundColor3 = K.charcoal
	if label then
		label.Text = `🧑‍🔧 {name} · {if type(doing) == "string" then doing else ""}`
	end
	for id, button in buttons do
		local lit = id == mode
		button.BackgroundColor3 = if lit then ORANGE else K.row
		button.TextColor3 = if lit then K.charcoal else K.text
	end
end

function MoveHelperHud.strip(): Frame?
	return strip
end

-- 8.3 Danny's command card is there (client/MoveHelperCard.luau's start): the strip is his status line, its ORDERS (and
-- a tap on the line) open the card.
function MoveHelperHud.useCard(open: () -> ())
	openCard = open
	refresh()
end

function MoveHelperHud.start()
	player:GetAttributeChangedSignal("MoveHelper"):Connect(refresh)
	player:GetAttributeChangedSignal("MoveHelperDoing"):Connect(refresh)
	player:GetAttributeChangedSignal("MoveHelperCall"):Connect(refresh) -- 8.3
	player:GetAttributeChangedSignal("MoveHelperReady"):Connect(refresh)
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
	refresh()
end

return MoveHelperHud
