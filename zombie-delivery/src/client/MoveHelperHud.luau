--!strict
-- 7.0, the depot's helper's orders (server/MoveHelper.luau: Danny joins a move whose crew is one player): a small strip
-- under the move's panel (client/MovingHud.luau) while he is on your move (your player attribute MoveHelper = the order
-- in force): what he does now (MoveHelperDoing) and three buttons, HELP ME (he follows you and lifts with you), SMALL
-- STUFF (he carries the one-hand things to the truck: the default) and WAIT AT TRUCK, the one in force lit. A tap sends
-- the Moving remote's ("helper", order); the server checks it. On a touch screen the buttons are at least Ui.MinTouch
-- high. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local MoveHelperHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local PANEL_TOP, PANEL_H = 8, 98 -- client/MovingHud.luau's move panel (px at scale 1): the strip sits under it
local WIDTH, ROW, GAP = 380, 30, 6
local ORDERS = {
	{ id = "help", text = "HELP ME" },
	{ id = "carry", text = "SMALL STUFF" },
	{ id = "wait", text = "WAIT AT TRUCK" },
}

local remote = Net.get("Moving")
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
	local gui = Ui.make("ScreenGui", {
		Name = "MoveHelperHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	local frame = Ui.make("Frame", {
		Name = "Orders",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(WIDTH, 26 + ROW + 8),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
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
	return frame
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
	local s = Ui.screenScale()
	local scaler = scale
	if scaler then
		scaler.Scale = s
	end
	local high = if Ui.touchLayout() then math.max(ROW, math.ceil(Ui.MinTouch / s)) else ROW
	frame.Size = UDim2.fromOffset(WIDTH, 26 + high + 8)
	frame.Position = UDim2.new(0.5, 0, 0, PANEL_TOP + (PANEL_H + 6) * s)
	local doing = player:GetAttribute("MoveHelperDoing")
	local label = line
	if label then
		label.Text = `🧑‍🔧 {string.upper(Config.MoveHelper.Name)} · {if type(doing) == "string" then doing else ""}`
	end
	for id, button in buttons do
		local lit = id == mode
		button.Size = UDim2.fromOffset(button.Size.X.Offset, high)
		button.BackgroundColor3 = if lit then ORANGE else K.row
		button.TextColor3 = if lit then K.charcoal else K.text
	end
end

function MoveHelperHud.start()
	player:GetAttributeChangedSignal("MoveHelper"):Connect(refresh)
	player:GetAttributeChangedSignal("MoveHelperDoing"):Connect(refresh)
	refresh()
end

return MoveHelperHud
