--!strict
-- Small helpers for building the interface in code.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))
local Theme = require(script.Parent.Theme)
local Ui = {}
Ui.Colors = Theme.Colors
Ui.Gps = Theme.Gps -- the GPS purple (the routes, the crew)

-- ── Screen ────────────────────────────────────────────────────────────────
-- One rule for the size of the interface everywhere (the HUD, its windows, the crew window, the leaderboard): 1 at
-- 1150 × 680 pixels, smaller on phones (at least 0.55), a little bigger on big screens (at most 1.1).
Ui.ScaleBase = Vector2.new(1150, 680)
Ui.MinScale = 0.55
Ui.MaxScale = 1.1

-- The scale for a screen of `size` pixels (the ScreenGui's area, under Roblox's top bar).
function Ui.scaleFor(size: Vector2): number
	return math.clamp(math.min(size.X / Ui.ScaleBase.X, size.Y / Ui.ScaleBase.Y), Ui.MinScale, Ui.MaxScale)
end

-- The area a ScreenGui (IgnoreGuiInset off) has: the viewport under Roblox's top bar.
function Ui.screenSize(): Vector2
	local camera = workspace.CurrentCamera
	if not camera then
		return Ui.ScaleBase
	end
	local inset = GuiService:GetGuiInset()
	return Vector2.new(camera.ViewportSize.X, math.max(1, camera.ViewportSize.Y - inset.Y))
end

-- The scale of this screen right now.
function Ui.screenScale(): number
	return Ui.scaleFor(Ui.screenSize())
end

-- A phone or a tablet without a keyboard: the touch layout (the thumbstick, the jump button, the FIRE button).
function Ui.touchLayout(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Instance.new + properties + parent. Returns any, so the caller can use the class's properties freely.
function Ui.make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance: any = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Ui.corner(parent: Instance, radius: number?)
	Ui.make("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius) }, parent)
end

-- Reuse the border when a caller highlights a panel; avoid overlapping double strokes.
-- 3.2: the quiet border (Theme.Border, the default) is see-through (Theme.BorderTransparency); an accent colour is
-- solid. A caller may still set .Transparency on what it returns.
function Ui.stroke(parent: Instance, color: Color3?, thickness: number?): any
	local border: any = parent:FindFirstChild("UiBorder")
	if not border then
		border = Ui.make("UIStroke", { Name = "UiBorder", ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
	end
	border.Color = color or Theme.Border
	border.Thickness = thickness or 1
	border.Transparency = if color == nil or color == Theme.Border then Theme.BorderTransparency else 0
	return border
end

function Ui.padding(parent: Instance, pixels: number)
	local p = UDim.new(0, pixels)
	Ui.make("UIPadding", { PaddingLeft = p, PaddingRight = p, PaddingTop = p, PaddingBottom = p }, parent)
end

function Ui.list(parent: Instance, vertical: boolean, gap: number, align: Enum.HorizontalAlignment?)
	Ui.make("UIListLayout", {
		FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	}, parent)
end

function Ui.panel(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): any
	local frame = Ui.make("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = Ui.Colors.panel,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame, Theme.PanelRadius)
	Ui.stroke(frame, Theme.Border, 1)
	return frame
end

-- ── 3.2: the HUD style ────────────────────────────────────────────────────
-- The pieces the right side of 3.1.3 – 3.1.4 is made of, for the rest of the interface: the accent edge, the small
-- caps label, the key chip, the quiet (glass) button and a pill.

-- A thin accent bar down the left edge of a card (the gun card's): `inset` px in, a little shorter than the card.
-- It sits outside any layout of the card: give the card's content a frame of its own when it has a UIListLayout.
function Ui.edge(parent: Instance, color: Color3, inset: number?): any
	local edge = Ui.make("Frame", {
		Name = "Edge",
		Size = UDim2.new(0, 3, 1, -16),
		Position = UDim2.new(0, inset or 7, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
	Ui.corner(edge, 2)
	return edge
end

-- A small caps label (HeadingFont, upper case, dim): the names of things, the units, the keys.
function Ui.caps(parent: Instance, text: string, size: UDim2, props: { [string]: any }?): any
	local label = Ui.label(parent, string.upper(text), size, {
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = Ui.Colors.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if props then
		for key, value in props do
			label[key] = value
		end
	end
	return label
end

-- A key in a dark chip ("M", "Q", "K"), the accent colour for its letter.
function Ui.keyChip(parent: Instance, key: string, size: number, accent: Color3?, props: { [string]: any }?): any
	local chip = Ui.label(parent, key, UDim2.fromOffset(size, size), {
		Name = "Key",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Ink,
		Font = Theme.HeadingFont,
		TextSize = math.max(9, math.floor(size * 0.55)),
		TextColor3 = accent or Ui.Colors.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	Ui.corner(chip, math.max(4, math.floor(size / 4)))
	if props then
		for key2, value in props do
			chip[key2] = value
		end
	end
	return chip
end

-- A quiet button: glass, a thin stroke (the accent's, else grey), the text in the accent or the text colour. For the
-- secondary actions (close, tabs, refresh, OK) next to the coloured main ones.
function Ui.ghostButton(parent: Instance, text: string, size: UDim2, accent: Color3?, onClick: () -> ()): any
	local button = Ui.button(parent, text, size, Ui.Colors.panelLight, onClick)
	button.BackgroundTransparency = 0.2
	button.TextColor3 = accent or Ui.Colors.text
	local border = Ui.stroke(button, accent or Ui.Colors.grey, 1)
	border.Transparency = if accent then 0.35 else 0.45
	return button
end

-- A window's close button: a small glass square with ✕.
function Ui.closeButton(parent: Instance, onClick: () -> ()): any
	local close = Ui.ghostButton(parent, "✕", UDim2.fromOffset(36, 36), nil, onClick)
	close.TextSize = 16
	close.TextColor3 = Ui.Colors.dim
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	return close
end

function Ui.label(parent: Instance, text: string, size: UDim2, props: { [string]: any }?): any
	local label = Ui.make("TextLabel", {
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Ui.Colors.text,
		Font = Theme.HeadingFont,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, parent)
	if props then
		for key, value in props do
			label[key] = value
		end
	end
	return label
end

-- Set by client/Sounds.luau: a soft click for every button made here.
Ui.onClick = nil :: (() -> ())?

function Ui.button(parent: Instance, text: string, size: UDim2, color: Color3, onClick: () -> ()): any
	local button = Ui.make("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Theme.textOn(color),
		Font = Theme.HeadingFont,
		TextSize = 18,
		AutoButtonColor = false,
	}, parent)
	Ui.corner(button, Theme.Radius)
	local border = Ui.stroke(button, color:Lerp(Color3.new(1, 1, 1), 0.25), 1)
	border.Transparency = 0.4
	local feedback: Tween? = nil
	local function highlight(on: boolean)
		if feedback then feedback:Cancel() end
		local tween = TweenService:Create(border, TweenInfo.new(0.12), { Transparency = if on then 0 else 0.4 })
		feedback = tween
		tween:Play()
	end
	button.MouseEnter:Connect(function() highlight(true) end)
	button.MouseLeave:Connect(function() highlight(false) end)
	button.SelectionGained:Connect(function() highlight(true) end)
	button.SelectionLost:Connect(function() highlight(false) end)
	button.Destroying:Connect(function() if feedback then feedback:Cancel() end end)
	button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		onClick()
	end)
	return button
end

-- A small rounded tag that grows with its text (cargo counts, rewards).
function Ui.chip(parent: Instance, text: string, color: Color3?, textColor: Color3?): any
	local chip = Ui.make("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color or Ui.Colors.panelLight,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = textColor or Theme.textOn(color or Ui.Colors.panelLight),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
	}, parent)
	Ui.corner(chip, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, chip)
	return chip
end

-- An icon from the icon set (shared/Icons.luau): an ImageLabel when its asset id is filled in, else a label with the
-- emoji / text fallback (what the interface always showed). props go to whichever it is: the Text* and Font ones only
-- to the fallback label, the Image* and ScaleType ones only to the image (ImageColor3 tints the white icon; white
-- when not given), the rest (Position, AnchorPoint, LayoutOrder, ZIndex, ...) to both.
function Ui.icon(parent: Instance, iconName: string?, fallback: string, size: UDim2, props: { [string]: any }?): GuiObject
	local id = Icons.get(iconName)
	local given: { [string]: any } = props or {}
	if not id then
		local textProps: { [string]: any } = {}
		for key, value in given do
			if string.sub(key, 1, 5) ~= "Image" and key ~= "ScaleType" then
				textProps[key] = value
			end
		end
		return Ui.label(parent, fallback, size, textProps)
	end
	local image = Ui.make("ImageLabel", {
		Name = iconName,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = id,
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = Color3.new(1, 1, 1),
	}, parent)
	for key, value in given do
		if string.sub(key, 1, 4) ~= "Text" and key ~= "Font" and key ~= "RichText" then
			image[key] = value
		end
	end
	return image
end

function Ui.bar(parent: Instance, size: UDim2, color: Color3): (any, any)
	local back = Ui.make("Frame", { Size = size, BackgroundColor3 = Color3.fromRGB(10, 16, 13), BorderSizePixel = 0 }, parent)
	Ui.corner(back, 6)
	local fill = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	Ui.corner(fill, 6)
	return back, fill
end

function Ui.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- ── 3.6 Postage & Trouble shapes (design/ui-concept/) ─────────────────────

-- A paper ticket: a cream card with a soft shadow, an optional slight tilt, and (with `stubWidth`) a perforated stub on
-- its right (a dashed line with two half-round notches). Returns the card, its body (content area) and the stub (nil
-- without one). Hit areas stay rectangular; the shape is only drawn.
function Ui.ticket(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?, stubWidth: number?, tilt: number?): (any, any, any)
	local P = Theme.Postage
	local holder = Ui.make("Frame", {
		Name = "Ticket",
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundTransparency = 1,
		Rotation = tilt or 0,
	}, parent)
	local shadow = Ui.make("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(3, 5),
		BackgroundColor3 = P.shadow,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(shadow, 6)
	local card = Ui.make("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.paper,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(card, 6)
	local stubW = stubWidth or 0
	local body = Ui.make("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -stubW, 1, 0),
		BackgroundTransparency = 1,
	}, card)
	local stub: any = nil
	if stubW > 0 then
		stub = Ui.make("Frame", {
			Name = "Stub",
			Size = UDim2.new(0, stubW, 1, 0),
			Position = UDim2.new(1, -stubW, 0, 0),
			BackgroundTransparency = 1,
		}, card)
		-- the perforation: a dashed line and a notch top and bottom
		for i = 0, 11 do
			Ui.make("Frame", {
				Size = UDim2.new(0, 1, 1 / 24, 0),
				Position = UDim2.new(1, -stubW, (i * 2 + 0.5) / 24, 0),
				BackgroundColor3 = P.line,
				BorderSizePixel = 0,
			}, card)
		end
		for _, y in { 0, 1 } do
			local notch = Ui.make("Frame", {
				Size = UDim2.fromOffset(12, 12),
				Position = UDim2.new(1, -stubW, y, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = P.ink,
				BorderSizePixel = 0,
			}, card)
			Ui.corner(notch, 6)
		end
	end
	return card, body, stub
end

-- Tactile hover / press for a button (or any GuiObject inside one): hover lifts it (`lift` px) and straightens a tilt,
-- press sinks it 2 px and scales to 0.97, release springs back. Touch taps activate at once (no hover step). The
-- tweens are cancelled when the object is destroyed.
function Ui.tactile(target: GuiObject, lift: number?, hoverScale: number?)
	local TweenService = game:GetService("TweenService")
	local scale = target:FindFirstChildOfClass("UIScale") or Ui.make("UIScale", { Scale = 1 }, target)
	local home = target.Position
	local tilt = target.Rotation
	local up = lift or 5
	local big = hoverScale or 1.04
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local playing: { Tween } = {}
	local function to(position: UDim2, rotation: number, size: number)
		for _, tween in playing do
			tween:Cancel()
		end
		table.clear(playing)
		local a = TweenService:Create(target, info, { Position = position, Rotation = rotation })
		local b = TweenService:Create(scale, info, { Scale = size })
		table.insert(playing, a)
		table.insert(playing, b)
		a:Play()
		b:Play()
	end
	local function rest()
		to(home, tilt, 1)
	end
	local function hover()
		to(home - UDim2.fromOffset(0, up), 0, big)
	end
	target.MouseEnter:Connect(hover)
	target.MouseLeave:Connect(rest)
	target.SelectionGained:Connect(hover)
	target.SelectionLost:Connect(rest)
	target.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			to(home + UDim2.fromOffset(0, 2), 0, 0.97)
		end
	end)
	target.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			hover()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			rest()
		end
	end)
	target.Destroying:Connect(function()
		for _, tween in playing do
			tween:Cancel()
		end
	end)
end

function Ui.money(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

function Ui.stars(count: number): string
	return string.rep("★", count) .. string.rep("☆", 3 - count)
end

function Ui.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Ui
