--!strict
-- 7.0, the depot's helper's orders (server/MoveHelper.luau: Danny joins a move whose crew is one player): a small strip
-- under the move's panel (client/MovingHud.luau) while he is on your move (your player attribute MoveHelper = the order
-- in force): what he does now (MoveHelperDoing) and three buttons, HELP ME (he follows you and lifts with you), SMALL
-- STUFF (he carries the smaller pieces to the van: the default) and WAIT AT VAN (7.x: the van, not the truck), the one
-- in force lit. He lifts your two-person pieces with you on every order but WAIT AT VAN. A tap sends
-- the Moving remote's ("helper", order); the server checks it. On a touch screen the buttons are at least Ui.MinTouch
-- high. 7.0 review: the strip sits under the move's panel where it really is (client/TopBlocks.luau "MovePanel", its
-- height measured, not assumed), follows it and the screen's size, and is a top-centre block itself ("MoveHelper": the
-- quick chat's lines and the HUD's chips go under or beside it). Presentation only.
--   MoveHelperHud.start(), MoveHelperHud.strip()   the strip (nil before Danny first joins)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local MoveLayout = require(script.Parent.MoveLayout) -- 7.0 review
local TopBlocks = require(script.Parent.TopBlocks) -- 7.0 review

local MoveHelperHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local WIDTH, ROW, GAP = MoveLayout.PANEL_W, 30, 6
local ORDERS = {
	{ id = "help", text = "HELP ME" },
	{ id = "carry", text = "SMALL STUFF" },
	{ id = "wait", text = "WAIT AT VAN" },
}

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local strip: Frame? = nil
local line: TextLabel? = nil
local scale: UIScale? = nil
local buttons: { [string]: TextButton } = {}

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
		Size = UDim2.fromOffset(WIDTH, 26 + ROW + 8),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, made)
	Ui.corner(frame, 8)
	scale = Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, frame)
	line = Ui.label(frame, "", UDim2.new(1, -20, 0, 18), {
		Position = UDim2.fromOffset(10, 5),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local width = (WIDTH - 20 - 2 * GAP) / 3
	for index, order in ORDERS do
		local button = Ui.make("TextButton", {
			Name = order.id,
			Size = UDim2.fromOffset(width, ROW),
			Position = UDim2.fromOffset(10 + (index - 1) * (width + GAP), 26),
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
	strip = frame
	TopBlocks.set("MoveHelper", frame)
	return frame
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
	local high = if Ui.touchLayout() then math.max(ROW, math.ceil(Ui.MinTouch / s)) else ROW
	local size = UDim2.fromOffset(WIDTH, 26 + high + 8)
	if frame.Size ~= size then
		frame.Size = size
	end
	for _, button in buttons do
		if button.Size.Y.Offset ~= high then
			button.Size = UDim2.fromOffset(button.Size.X.Offset, high)
		end
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
	place()
	local doing = player:GetAttribute("MoveHelperDoing")
	local label = line
	if label then
		label.Text = `🧑‍🔧 {string.upper(Config.MoveHelper.Name)} · {if type(doing) == "string" then doing else ""}`
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

function MoveHelperHud.start()
	player:GetAttributeChangedSignal("MoveHelper"):Connect(refresh)
	player:GetAttributeChangedSignal("MoveHelperDoing"):Connect(refresh)
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
	refresh()
end

return MoveHelperHud
