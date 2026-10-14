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
--   MoveHelperHud.start(), MoveHelperHud.strip()   the strip (nil before Danny first comes)
--   MoveHelperHud.useCard(open)                    8.3 HIRE and LIST open his card (open: the card's opener)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Brain = require(Shared.MoveHelperBrain)
local SandboxPad = require(Shared.SandboxPad) -- 8.3 review: a gamepad button's word
local Ui = require(script.Parent.Ui)
local PadGlyph = require(script.Parent.PadGlyph) -- 8.3 review: the device used now
local Theme = require(script.Parent.Theme)
local MoveLayout = require(script.Parent.MoveLayout) -- 7.0 review
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review

local MoveHelperHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local WIDTH, GAP = MoveLayout.PANEL_W, 6
local STATUS_ROW = 32 -- 8.3 the status line's row (its two lines of words, its button)
local ACTION_W = 92 -- 8.3 HIRE / LIST / STOP
local PAD = 6

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local strip: Frame? = nil
local scale: UIScale? = nil
local status: { [string]: any } = {} -- 8.3 the status line's pieces: tap (the line), title, doing, action
local openCard: (() -> ())? = nil -- 8.3 his card's opener (useCard)

local function waiting(): string?
	local call = player:GetAttribute("MoveHelperCall")
	return if type(call) == "string" and call ~= "" then call else nil
end

local function hired(): boolean
	return player:GetAttribute("MoveHelper") == "hired"
end

local function priceNow(): number
	local price = player:GetAttribute("MoveHelperPrice")
	return if type(price) == "number" then price else 0
end

-- The button: STOP while you wait; with the card HIRE / LIST open it; without it HIRE and CLEAR go to the server.
local function act()
	if waiting() then
		remote:FireServer("helper", "stop")
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

-- Under the move's panel, where it really is (else where it would be), its row a finger's height on a touch screen.
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

-- 8.3 review: what he carries for you, in this device's words.
local function carriesWords(): string
	local device = PadGlyph.device()
	return if device == "touch" then "Carries what you tap" elseif device == "pad" then "Carries what you give him" else "Carries what you click"
end

local function refresh()
	local state = player:GetAttribute("MoveHelper")
	local on = type(state) == "string"
	local frame = if on then build() else strip
	if not frame then
		return
	end
	frame.Visible = on
	if not on then
		return
	end
	place()
	local name = string.upper(Config.MoveHelper.Name)
	local doing = player:GetAttribute("MoveHelperDoing")
	local piece = waiting()
	if piece then
		-- you wait for him at your end of a two-person piece (then he is there: your lift): STOP (G) ends it
		local ready = player:GetAttribute("MoveHelperReady") == true
		paint(frame, if ready then "💪 ON THREE… LIFT!" else `⏳ WAITING FOR {name}…`,
			(if ready then `{Config.MoveHelper.Name} is at the other end of the {piece}` else `Stay at your end of the {piece}`) .. stopWords(ready), "STOP", true, false)
	elseif hired() then
		paint(frame, `🧑‍🔧 {name} · {Brain.queueText(player:GetAttribute("MoveHelperQueue"))}`, if type(doing) == "string" then doing else "",
			if openCard then "LIST" else "CLEAR", false, false)
	else
		local price = Brain.money(priceNow())
		paint(frame, `🧑‍🔧 {name} · FOR HIRE`, `{carriesWords()} · {price} this move`, `HIRE {price}`, false, true)
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

function MoveHelperHud.start()
	for _, name in { "MoveHelper", "MoveHelperDoing", "MoveHelperCall", "MoveHelperReady", "MoveHelperPrice", "MoveHelperQueue" } do
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
