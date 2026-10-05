--!strict
-- Small helpers for building the interface in code.
--
-- 3.6, "Postage & Trouble" (design/ui-concept/): light paper and lavender surfaces with plum ink, pastel actions,
-- shipping-ticket shapes. The helpers every module uses keep their signatures and wear the new look:
--
--   Ui.panel(parent, size, position, anchor?) -> Frame
--       a paper card (the HUD's cards): cream, a 12 px corner, a thin lavender line.
--   Ui.button(parent, text, size, color, onClick) -> TextButton
--       an action. `color` says what it means and becomes its pastel face (Theme.soft): yellow / green / money are
--       the sage MAIN action (an arrow on its right when there is room), red rose, blue sky, grey disabled, the GPS
--       purple lilac; any other colour is washed toward paper. A soft shadow under it (the lip), hover lightens it,
--       press sinks it (0.97, the lip gone). Setting .BackgroundColor3 later (a caller's enabled / selected state)
--       gets the same treatment, and a .TextColor3 that would not read on the face (old white-on-colour text) falls
--       back to ink.
--   Ui.ghostButton(parent, text, size, accent?, onClick) -> TextButton   a quiet secondary action (paper, a line).
--   Ui.closeButton(parent, onClick) -> TextButton   round, ✕, turns 90° and grows on hover, shrinks on press.
--   Ui.chip(parent, text, color?, textColor?) -> TextLabel   a small badge on the pastel face of `color`.
--   Ui.keyChip(parent, key, size, accent?, props?) -> TextLabel   a key ("M", "ESC") on a paper chip with a line.
--   Ui.caps(parent, text, size, props?) -> TextLabel   a small caps label (12 px, the secondary ink).
--   Ui.bar(parent, size, color) -> (back, fill)   a thin bar on a lavender track.
--
-- New in 3.6 (for the HUD, the Dispatch board, the garage, the missions):
--   Ui.window(parent, title, subtitle, icon?, size?) -> (frame, content, chrome)
--       a lavender window: a header (the icon in a round sage badge, the title, the subtitle, the round close
--       button), the content area and a footer (ESC chip, "Close window", a context line on the right). `frame` is
--       what you size, move, scale (UIScale) and show; put your things in `content`. chrome: { frame, surface,
--       header, content, footer, icon, title, subtitle, close, esc, escText, context, onClose }. The close button and
--       ESC (or the gamepad's B, or opening the Roblox menu) call chrome.onClose when it is set, else hide `frame`.
--       Ui.WindowHeader / Ui.WindowFooter are the heights (px at scale 1) the content area leaves for the chrome.
--   Ui.ticket(parent, size, position, anchor?, stubWidth?, tilt?, notch?) -> (card, body, stub)
--       a paper ticket with a soft lip and (with stubWidth) a perforated stub; `notch` colours the two half-round
--       notches (the surface behind the ticket; default the window lavender).
--   Ui.tactile(target, lift?, hoverScale?)   hover lifts / straightens / grows, press sinks (follows a target the
--       caller moves later; a target in a layout only grows and straightens).
--   Ui.tag(parent, text, index, size?, onClick?) -> (tag, parts)
--       a tilted pastel tag (the consumables): the face of Theme.Postage.tags[index], tilted ±4° by index, the
--       tactile hover (lift 9, scale 1.12). parts: { key (top left), count (bottom right), label (the name that
--       shows above it on hover / gamepad focus), lip }.
--   Ui.dial(parent, diameter, position?, anchor?) -> Dial
--       a round cream dial with ticks (the speed dial): { frame, face (a CanvasGroup), title, value, unit,
--       caption, percent, barBack, barFill, pips, pipsLabel, needle, setNeedle(fraction), setBar(fraction, color?),
--       setPips(filled, total, text?), setDim(on) }.
--   Ui.dashes(parent, vertical, count, color, size, position) -> Frame   a dashed line (perforations, separators).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))
local Theme = require(script.Parent.Theme)
local Ui = {}
Ui.Colors = Theme.Colors
Ui.Gps = Theme.Gps -- the GPS purple (the routes, the crew)
local P = Theme.Postage

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

-- 3.6: a paper card (the HUD's cards; the windows use Ui.window).
function Ui.panel(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): any
	local frame = Ui.make("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = P.paper,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame, Theme.PanelRadius)
	Ui.stroke(frame, Theme.Border, 1)
	return frame
end

-- A dashed line: `count` dashes along a frame of `size` at `position` (horizontal unless `vertical`). The perforations
-- of the tickets and the line under a window's header.
function Ui.dashes(parent: Instance, vertical: boolean, count: number, color: Color3, size: UDim2, position: UDim2): any
	local line = Ui.make("Frame", { Name = "Dashes", Size = size, Position = position, BackgroundTransparency = 1 }, parent)
	local share = 1 / (count * 2)
	for i = 0, count - 1 do
		Ui.make("Frame", {
			Size = if vertical then UDim2.fromScale(1, share) else UDim2.fromScale(share, 1),
			Position = if vertical then UDim2.fromScale(0, (i * 2 + 0.5) * share) else UDim2.fromScale((i * 2 + 0.5) * share, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, line)
	end
	return line
end

-- ── The small pieces ──────────────────────────────────────────────────────

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

-- A small caps label (HeadingFont, upper case, the secondary ink): the names of things, the units, the keys.
function Ui.caps(parent: Instance, text: string, size: UDim2, props: { [string]: any }?): any
	local label = Ui.label(parent, string.upper(text), size, {
		Font = Theme.HeadingFont,
		TextSize = 12,
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

-- A key on a paper chip with a thin line ("M", "Q", "K", "ESC"); the accent (made readable) for its letter.
function Ui.keyChip(parent: Instance, key: string, size: number, accent: Color3?, props: { [string]: any }?): any
	local chip = Ui.label(parent, key, UDim2.fromOffset(size, size), {
		Name = "Key",
		BackgroundTransparency = 0,
		BackgroundColor3 = P.paper,
		Font = Theme.HeadingFont,
		TextSize = math.max(12, math.floor(size * 0.55)),
		TextColor3 = Theme.readable(accent or P.ink2, P.paper),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	Ui.corner(chip, math.max(4, math.floor(size / 4)))
	local line = Ui.stroke(chip, P.line, 1)
	line.Transparency = 0
	if props then
		for key2, value in props do
			chip[key2] = value
		end
	end
	return chip
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

-- ── Buttons ───────────────────────────────────────────────────────────────

-- Set by client/Sounds.luau: a soft click for every button made here.
Ui.onClick = nil :: (() -> ())?

local function click(onClick: () -> ())
	local sound = Ui.onClick
	if sound then
		sound()
	end
	onClick()
end

local PRESS_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The button's own UIScale for the press (nil when the caller scales the button with a UIScale of its own).
local function pressScale(button: GuiObject): UIScale?
	local scale = button:FindFirstChildOfClass("UIScale")
	if scale then
		return if scale.Name == "Press" then scale else nil
	end
	return Ui.make("UIScale", { Name = "Press", Scale = 1 }, button)
end

function Ui.button(parent: Instance, text: string, size: UDim2, color: Color3, onClick: () -> ()): any
	local look = Theme.soft(color)
	local button = Ui.make("TextButton", {
		Size = size,
		BackgroundColor3 = look.face,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = look.text,
		Font = Theme.HeadingFont,
		TextSize = 18,
		AutoButtonColor = false,
	}, parent)
	Ui.corner(button, Theme.Radius)
	local border = Ui.stroke(button, look.lip, 1)
	border.Transparency = 0.35
	-- The soft shadow: a darker band along the bottom (a Frame cannot cast a real one; children draw on top).
	local lip = Ui.make("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, -2 * Theme.Radius, 0, 3),
		BackgroundColor3 = look.lip,
		BorderSizePixel = 0,
		Visible = not look.quiet,
	}, button)
	Ui.corner(lip, 2)
	-- The main action's arrow (only while the text leaves room for it).
	local arrow = Ui.make("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, -1),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Text = "→",
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = look.text,
		Visible = false,
	}, button)

	local hovered, pressed = false, false
	local applied = look.face -- the face this button set last (a caller's own colour differs from it)
	local function face(): Color3
		return if pressed and look.main then P.sagePress
			elseif hovered and look.main then P.sageHover
			elseif hovered then look.face:Lerp(Color3.new(1, 1, 1), 0.35)
			else look.face
	end
	local function refreshArrow()
		local room = button.AbsoluteSize.X - button.TextBounds.X
		arrow.Visible = look.main and button.Text ~= "" and room >= 56 and not string.find(button.Text, "→", 1, true)
		arrow.TextColor3 = button.TextColor3
		arrow.ZIndex = button.ZIndex
		lip.ZIndex = button.ZIndex
	end
	local function paint()
		applied = face()
		button.BackgroundColor3 = applied
		lip.Visible = not look.quiet and not pressed
	end
	-- A caller set .BackgroundColor3 (its enabled / selected state): wear that colour's face.
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		local now = button.BackgroundColor3
		if Theme.same(now, applied) then
			return
		end
		look = Theme.soft(now)
		paint()
		if button:GetAttribute("KeepStroke") ~= true then
			border.Color = look.lip
			lip.BackgroundColor3 = look.lip
		end
		button.TextColor3 = Theme.readable(button.TextColor3, look.face)
		refreshArrow()
	end)
	-- A caller's text colour that would not read on the face (old white-on-colour text): the face's ink.
	button:GetPropertyChangedSignal("TextColor3"):Connect(function()
		local fixed = Theme.readable(button.TextColor3, look.face)
		if not Theme.same(fixed, button.TextColor3) then
			button.TextColor3 = fixed
		end
		arrow.TextColor3 = button.TextColor3
	end)
	button:GetPropertyChangedSignal("TextBounds"):Connect(refreshArrow)
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshArrow)
	button:GetPropertyChangedSignal("ZIndex"):Connect(refreshArrow)

	local feedback: Tween? = nil
	local function sink(on: boolean)
		pressed = on
		paint()
		local scale = pressScale(button)
		if scale then
			if feedback then
				feedback:Cancel()
			end
			local tween = TweenService:Create(scale, PRESS_INFO, { Scale = if on then 0.97 else 1 })
			feedback = tween
			tween:Play()
		end
	end
	local function hover(on: boolean)
		hovered = on
		if not on then
			pressed = false
		end
		paint()
		border.Transparency = if on then 0 else 0.35
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function()
		hover(false)
		sink(false)
	end)
	button.SelectionGained:Connect(function() hover(true) end)
	button.SelectionLost:Connect(function() hover(false) end)
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sink(true)
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sink(false)
		end
	end)
	button.Destroying:Connect(function()
		if feedback then
			feedback:Cancel()
		end
	end)
	button.Activated:Connect(function()
		click(onClick)
	end)
	task.defer(refreshArrow)
	return button
end

-- A quiet button: paper, a thin line (the accent's, else lavender), the text in the accent (made readable) or ink.
-- For the secondary actions (close, tabs, refresh, OK) next to the main ones.
function Ui.ghostButton(parent: Instance, text: string, size: UDim2, accent: Color3?, onClick: () -> ()): any
	local button = Ui.button(parent, text, size, Ui.Colors.panelLight, onClick)
	button:SetAttribute("KeepStroke", true)
	button.TextColor3 = Theme.readable(accent or Ui.Colors.text, P.ticket)
	local border = Ui.stroke(button, accent or P.line, 1)
	border.Transparency = if accent then 0.35 else 0
	local lip = button:FindFirstChild("Lip")
	if lip and lip:IsA("GuiObject") then
		lip.BackgroundColor3 = P.track
	end
	return button
end

-- A window's close button: round, ✕; it turns 90° and grows on hover, shrinks on press (index.html .close).
function Ui.closeButton(parent: Instance, onClick: () -> ()): any
	local close = Ui.make("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		BackgroundColor3 = P.closeFace,
		BorderSizePixel = 0,
		Text = "✕",
		TextColor3 = P.ink2,
		Font = Theme.HeadingFont,
		TextSize = 16,
		AutoButtonColor = false,
	}, parent)
	Ui.corner(close, 18)
	local ring = Ui.stroke(close, P.closeLip, 2)
	ring.Transparency = 0
	local scale = Ui.make("UIScale", { Name = "Press", Scale = 1 }, close)
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local playing: { Tween } = {}
	local function to(rotation: number, size: number)
		for _, tween in playing do
			tween:Cancel()
		end
		table.clear(playing)
		local a = TweenService:Create(close, info, { Rotation = rotation })
		local b = TweenService:Create(scale, info, { Scale = size })
		table.insert(playing, a)
		table.insert(playing, b)
		a:Play()
		b:Play()
	end
	close.MouseEnter:Connect(function() to(90, 1.1) end)
	close.MouseLeave:Connect(function()
		to(0, 1)
		ring.Thickness = 2
	end)
	close.SelectionGained:Connect(function() to(90, 1.1) end)
	close.SelectionLost:Connect(function() to(0, 1) end)
	close.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			to(90, 0.92)
			ring.Thickness = 0
		end
	end)
	close.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			to(90, 1.1)
			ring.Thickness = 2
		elseif input.UserInputType == Enum.UserInputType.Touch then
			to(0, 1)
			ring.Thickness = 2
		end
	end)
	close.Destroying:Connect(function()
		for _, tween in playing do
			tween:Cancel()
		end
	end)
	close.Activated:Connect(function()
		click(onClick)
	end)
	return close
end

-- A small rounded badge that grows with its text (cargo counts, rewards), on the pastel face of `color`; a
-- `textColor` that would not read on it falls back to ink.
function Ui.chip(parent: Instance, text: string, color: Color3?, textColor: Color3?): any
	local look = Theme.soft(color or Ui.Colors.panelLight)
	local chip = Ui.make("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = look.face,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Theme.readable(textColor or look.text, look.face),
		Font = Theme.HeadingFont,
		TextSize = 14,
	}, parent)
	Ui.corner(chip, 4)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, chip)
	-- A caller's later colours get the same treatment.
	chip:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if Theme.isFace(chip.BackgroundColor3) or Theme.same(chip.BackgroundColor3, look.face) then
			return
		end
		look = Theme.soft(chip.BackgroundColor3)
		chip.BackgroundColor3 = look.face
		chip.TextColor3 = Theme.readable(chip.TextColor3, look.face)
	end)
	chip:GetPropertyChangedSignal("TextColor3"):Connect(function()
		local fixed = Theme.readable(chip.TextColor3, chip.BackgroundColor3)
		if not Theme.same(fixed, chip.TextColor3) then
			chip.TextColor3 = fixed
		end
	end)
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

-- A thin bar: `color` on a lavender track.
function Ui.bar(parent: Instance, size: UDim2, color: Color3): (any, any)
	local back = Ui.make("Frame", { Size = size, BackgroundColor3 = P.track, BorderSizePixel = 0 }, parent)
	Ui.corner(back, 4)
	local fill = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	Ui.corner(fill, 4)
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

-- A paper ticket: a cream card with a soft lip under it, an optional slight tilt, and (with `stubWidth`) a perforated
-- stub on its right (a dashed line with two half-round notches in `notch`, the colour behind the ticket). Returns the
-- card, its body (content area) and the stub (nil without one). Hit areas stay rectangular; the shape is only drawn.
function Ui.ticket(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?, stubWidth: number?, tilt: number?, notch: Color3?): (any, any, any)
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
		Position = UDim2.fromOffset(0, 5),
		BackgroundColor3 = P.closeLip,
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
		Ui.dashes(card, true, 12, P.line, UDim2.new(0, 1, 1, 0), UDim2.new(1, -stubW, 0, 0))
		for _, y in { 0, 1 } do
			local hole = Ui.make("Frame", {
				Name = "Notch",
				Size = UDim2.fromOffset(12, 12),
				Position = UDim2.new(1, -stubW, y, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = notch or P.lavender,
				BorderSizePixel = 0,
			}, card)
			Ui.corner(hole, 6)
		end
	end
	return card, body, stub
end

-- Tactile hover / press for a button (or any GuiObject inside one): hover lifts it (`lift` px), straightens a tilt
-- and grows it (`hoverScale`), press sinks it 2 px and scales to 0.97, release springs back. Touch taps activate at
-- once (no hover step). It follows a target the caller moves later (its resting place is re-read whenever it is at
-- rest); in a layout only the scale and the tilt move. The tweens are cancelled when the object is destroyed.
function Ui.tactile(target: GuiObject, lift: number?, hoverScale: number?)
	local scale = target:FindFirstChildOfClass("UIScale") or Ui.make("UIScale", { Name = "Press", Scale = 1 }, target)
	local home = target.Position
	local tilt = target.Rotation
	local up = lift or 5
	local big = hoverScale or 1.04
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local playing: { Tween } = {}
	local away = false -- moved off its resting place by us
	local function to(position: UDim2, rotation: number, size: number, resting: boolean)
		if not away then
			-- At rest: wherever the caller put it (and tilted it) is home now.
			home = target.Position
			tilt = target.Rotation
		end
		away = not resting
		for _, tween in playing do
			tween:Cancel()
		end
		table.clear(playing)
		local a = TweenService:Create(target, info, { Position = if resting then home else position, Rotation = if resting then tilt else rotation })
		local b = TweenService:Create(scale, info, { Scale = size })
		table.insert(playing, a)
		table.insert(playing, b)
		a:Play()
		b:Play()
	end
	local function rest()
		to(home, tilt, 1, true)
	end
	local function hover()
		to(home - UDim2.fromOffset(0, up), 0, big, false)
	end
	target.MouseEnter:Connect(hover)
	target.MouseLeave:Connect(rest)
	target.SelectionGained:Connect(hover)
	target.SelectionLost:Connect(rest)
	target.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			to(home + UDim2.fromOffset(0, 2), 0, 0.97, false)
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

-- ── The window ────────────────────────────────────────────────────────────

Ui.WindowHeader = 78 -- px at scale 1: the header over the content
Ui.WindowFooter = 40 -- px at scale 1: the footer under it

export type WindowChrome = {
	frame: Frame,
	surface: Frame,
	header: Frame,
	content: Frame,
	footer: Frame,
	icon: GuiObject,
	title: TextLabel,
	subtitle: TextLabel,
	close: TextButton,
	esc: TextLabel,
	escText: TextLabel,
	context: TextLabel,
	onClose: (() -> ())?,
}

-- Closes a window made by Ui.window: its onClose, else it hides.
function Ui.closeWindow(chrome: WindowChrome)
	local onClose = chrome.onClose
	if onClose then
		onClose()
	else
		chrome.frame.Visible = false
	end
end

-- Is this GuiObject shown on screen right now (itself, its ancestors and its ScreenGui)?
local function shown(object: GuiObject): boolean
	local node: Instance? = object
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("LayerCollector") then
			return node.Enabled and node:IsDescendantOf(game)
		end
		node = node.Parent
	end
	return false
end

-- A lavender window (dispatch.png, garage.png): see the top of this file. `icon`: an Icons name or an emoji.
function Ui.window(parent: Instance, title: string, subtitle: string, icon: string?, size: UDim2?): (any, any, WindowChrome)
	local radius = Theme.WindowRadius
	local frame = Ui.make("Frame", {
		Name = "Window",
		Size = size or UDim2.fromOffset(760, 520),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, parent)
	-- The offset shadow (8, 8) and the surface.
	local shadow = Ui.make("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = P.windowShadow,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, frame)
	Ui.corner(shadow, radius)
	local surface = Ui.make("Frame", {
		Name = "Surface",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.lavender,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true, -- clicks on the window do not reach the world
	}, frame)
	Ui.corner(surface, radius)

	-- The header: the icon badge, the title and the subtitle, the close button, a dashed line under it.
	local headerH, footerH = Ui.WindowHeader, Ui.WindowFooter
	local header = Ui.make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, headerH), BackgroundColor3 = P.header, BorderSizePixel = 0 }, surface)
	Ui.corner(header, radius)
	Ui.make("Frame", { Name = "Square", Size = UDim2.new(1, 0, 0, radius), Position = UDim2.new(0, 0, 1, -radius), BackgroundColor3 = P.header, BorderSizePixel = 0 }, header)
	Ui.dashes(header, false, 64, P.dash, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1))
	local badge = Ui.make("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(42, 42),
		Position = UDim2.new(0, 22, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = P.brand,
		BorderSizePixel = 0,
	}, header)
	Ui.corner(badge, 21)
	Ui.stroke(badge, P.brandLine, 1).Transparency = 0
	local iconObject = Ui.icon(badge, icon, icon or "", UDim2.fromOffset(24, 24), {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = P.ink2,
		ImageColor3 = P.ink2,
	})
	local titleLabel = Ui.label(header, title, UDim2.new(1, -150, 0, 30), {
		Name = "Title",
		Position = UDim2.fromOffset(78, 12),
		Font = Theme.DisplayFont,
		TextSize = 25,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local subtitleLabel = Ui.label(header, subtitle, UDim2.new(1, -150, 0, 18), {
		Name = "Subtitle",
		Position = UDim2.fromOffset(79, 44),
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local content = Ui.make("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 1, -(headerH + footerH)),
		Position = UDim2.fromOffset(0, headerH),
		BackgroundTransparency = 1,
	}, surface)

	-- The footer: ESC · Close window on the left, the context (the caller's) on the right.
	local footer = Ui.make("Frame", {
		Name = "Footer",
		Size = UDim2.new(1, 0, 0, footerH),
		Position = UDim2.new(0, 0, 1, -footerH),
		BackgroundColor3 = P.footer,
		BorderSizePixel = 0,
	}, surface)
	Ui.corner(footer, radius)
	Ui.make("Frame", { Name = "Square", Size = UDim2.new(1, 0, 0, radius), BackgroundColor3 = P.footer, BorderSizePixel = 0 }, footer)
	Ui.make("Frame", { Name = "Line", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = P.footerLine, BorderSizePixel = 0 }, footer)
	local touch = Ui.touchLayout()
	local esc = Ui.keyChip(footer, if touch then "✕" else "ESC", 24, P.ink2, {
		Size = UDim2.fromOffset(if touch then 24 else 38, 24),
		Position = UDim2.new(0, 24, 0.5, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		TextSize = 12,
	})
	local escText = Ui.label(footer, if touch then "Tap ✕ to close" else "Close window", UDim2.fromOffset(150, 20), {
		Position = UDim2.new(0, if touch then 56 else 70, 0.5, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextWrapped = false,
	})
	local context = Ui.label(footer, "", UDim2.new(1, -260, 0, 20), {
		Name = "Context",
		Position = UDim2.new(1, -24, 0.5, 1),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
	})

	local chrome: WindowChrome
	local close = Ui.closeButton(header, function()
		Ui.closeWindow(chrome)
	end)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -26, 0.5, 0)
	chrome = {
		frame = frame,
		surface = surface,
		header = header,
		content = content,
		footer = footer,
		icon = iconObject,
		title = titleLabel,
		subtitle = subtitleLabel,
		close = close,
		esc = esc,
		escText = escText,
		context = context,
		onClose = nil,
	}
	-- ESC (or the gamepad's B, or the Roblox menu opening) closes it while it is shown (not while typing).
	local function escape()
		if shown(frame) and not UserInputService:GetFocusedTextBox() then
			Ui.closeWindow(chrome)
		end
	end
	local keys = UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			escape()
		end
	end)
	local menu = GuiService.MenuOpened:Connect(escape)
	frame.Destroying:Connect(function()
		keys:Disconnect()
		menu:Disconnect()
	end)
	return frame, content, chrome
end

-- ── The tag (the consumables) ─────────────────────────────────────────────

export type TagParts = { key: TextLabel, count: TextLabel, label: TextLabel, lip: Frame }

-- A tilted pastel tag (on-route.png, hover-item.png): see the top of this file. `text` is its face (an emoji; set it
-- to "" and put an Ui.icon in it for a picture).
function Ui.tag(parent: Instance, text: string, index: number, size: UDim2?, onClick: (() -> ())?): (any, TagParts)
	local faces = P.tags
	local odd = index % 2 == 1
	local tag = Ui.make("TextButton", {
		Name = "Tag",
		Size = size or UDim2.fromOffset(46, 50),
		BackgroundColor3 = faces[(index - 1) % #faces + 1],
		BorderSizePixel = 0,
		Rotation = if odd then -4 else 4,
		Text = text,
		TextColor3 = P.ink2,
		Font = Theme.HeadingFont,
		TextSize = 22,
		AutoButtonColor = false,
	}, parent)
	Ui.corner(tag, 10)
	local lip = Ui.make("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, -16, 0, 3),
		BackgroundColor3 = P.closeLip,
		BorderSizePixel = 0,
	}, tag)
	Ui.corner(lip, 2)
	local key = Ui.label(tag, "", UDim2.fromOffset(16, 14), {
		Name = "KeyNumber",
		Position = UDim2.fromOffset(4, 2),
		Font = Theme.MonoFont,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextWrapped = false,
	})
	local count = Ui.label(tag, "", UDim2.fromOffset(24, 14), {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Font = Theme.MonoFont,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	-- The name over it: shows on hover / gamepad focus (index.html .item:after).
	local label = Ui.label(tag, "", UDim2.fromOffset(0, 26), {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -10),
		BackgroundTransparency = 0,
		BackgroundColor3 = P.ticket,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextWrapped = false,
		Rotation = -2,
		Visible = false,
		ZIndex = 5,
	})
	Ui.corner(label, 6)
	Ui.stroke(label, P.line, 1).Transparency = 0
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, label)
	local function name(on: boolean)
		label.Visible = on and label.Text ~= ""
		lip.Visible = not on
	end
	tag.MouseEnter:Connect(function() name(true) end)
	tag.MouseLeave:Connect(function() name(false) end)
	tag.SelectionGained:Connect(function() name(true) end)
	tag.SelectionLost:Connect(function() name(false) end)
	Ui.tactile(tag, 9, 1.12)
	if onClick then
		tag.Activated:Connect(function()
			click(onClick)
		end)
	end
	return tag, { key = key, count = count, label = label, lip = lip }
end

-- ── The dial (the speed dial) ─────────────────────────────────────────────

export type Dial = {
	frame: Frame,
	face: CanvasGroup,
	title: TextLabel,
	value: TextLabel,
	unit: TextLabel,
	caption: TextLabel,
	percent: TextLabel,
	barBack: Frame,
	barFill: Frame,
	pips: Frame,
	pipsLabel: TextLabel,
	needle: Frame,
	setNeedle: (fraction: number) -> (),
	setBar: (fraction: number, color: Color3?) -> (),
	setPips: (filled: number, total: number, text: string?) -> (),
	setDim: (on: boolean) -> (),
}

local DIAL_SWEEP = 120 -- degrees either side of the top: the ticks and the needle's travel

-- A round cream dial (on-route.png, index.html .vehicle): see the top of this file. Sizes are for a `diameter` of
-- 210 px and scale with it (no text under 12 px).
function Ui.dial(parent: Instance, diameter: number, position: UDim2?, anchor: Vector2?): Dial
	local d = diameter
	local s = d / 210
	local function px(value: number): number
		return math.max(12, math.floor(value * s + 0.5))
	end
	local frame = Ui.make("Frame", {
		Name = "Dial",
		Size = UDim2.fromOffset(d, d),
		Position = position or UDim2.new(),
		AnchorPoint = anchor or Vector2.zero,
		BackgroundTransparency = 1,
	}, parent)
	local shadow = Ui.make("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, math.floor(7 * s)),
		BackgroundColor3 = P.closeLip,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, frame)
	Ui.corner(shadow, math.floor(d / 2))
	local face = Ui.make("CanvasGroup", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.paper,
		BorderSizePixel = 0,
		GroupTransparency = 0,
	}, frame)
	Ui.corner(face, math.floor(d / 2))
	-- The ticks: every 15° over the top two thirds of the rim.
	local tickR = d / 2 - 10 * s - 4
	for angle = -DIAL_SWEEP, DIAL_SWEEP, 15 do
		local a = math.rad(angle)
		Ui.make("Frame", {
			Name = "Tick",
			Size = UDim2.fromOffset(2, math.max(5, math.floor(8 * s))),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(a) * tickR, 0.5, -math.cos(a) * tickR),
			Rotation = angle,
			BackgroundColor3 = P.dash,
			BorderSizePixel = 0,
		}, face)
	end
	local needleLength = math.floor(30 * s)
	local needleR = d / 2 - 10 * s - needleLength / 2
	local needle = Ui.make("Frame", {
		Name = "Needle",
		Size = UDim2.fromOffset(2, needleLength),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = P.violet,
		BorderSizePixel = 0,
	}, face)
	local function setNeedle(fraction: number)
		local angle = -DIAL_SWEEP + 2 * DIAL_SWEEP * math.clamp(fraction, 0, 1)
		local a = math.rad(angle)
		needle.Position = UDim2.new(0.5, math.sin(a) * needleR, 0.5, -math.cos(a) * needleR)
		needle.Rotation = angle
	end
	setNeedle(0)

	local title = Ui.caps(face, "", UDim2.new(0.7, 0, 0, px(14)), {
		Name = "Title",
		Position = UDim2.fromScale(0.5, 0.17),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = px(12),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local speedRow = Ui.make("Frame", {
		Name = "Speed",
		Size = UDim2.new(0.8, 0, 0, math.floor(64 * s)),
		Position = UDim2.fromScale(0.5, 0.25),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	}, face)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, math.floor(4 * s)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, speedRow)
	local value = Ui.label(speedRow, "0", UDim2.fromScale(0, 1), {
		Name = "Value",
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.DisplayFont,
		TextSize = math.floor(60 * s),
		TextColor3 = P.ink,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
	})
	local unit = Ui.label(speedRow, "KM/H", UDim2.fromOffset(0, px(14) + math.floor(8 * s)), {
		Name = "Unit",
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = px(12),
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
	})
	local inset = math.floor(30 * s)
	local caption = Ui.caps(face, "Vehicle condition", UDim2.new(1, -2 * inset - 40, 0, px(14)), {
		Name = "Caption",
		Position = UDim2.new(0, inset, 0.58, 0),
	})
	caption.TextSize = px(12)
	local percent = Ui.label(face, "", UDim2.fromOffset(44, px(14)), {
		Name = "Percent",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -inset, 0.58, 0),
		Font = Theme.HeadingFont,
		TextSize = px(12),
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	local barBack, barFill = Ui.bar(face, UDim2.new(1, -2 * inset, 0, math.max(4, math.floor(5 * s))), P.lilacLip)
	barBack.Name = "Condition"
	barBack.Position = UDim2.new(0, inset, 0.67, 0)
	local pips = Ui.make("Frame", {
		Name = "Pips",
		Size = UDim2.new(1, -2 * inset, 0, math.max(8, math.floor(10 * s))),
		Position = UDim2.new(0.5, 0, 0.74, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	}, face)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pips)
	local pipsLabel = Ui.label(face, "", UDim2.new(1, -2 * inset, 0, px(14)), {
		Name = "PipsLabel",
		Position = UDim2.new(0.5, 0, 0.8, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.MonoFont,
		TextSize = px(12),
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local function setBar(fraction: number, color: Color3?)
		barFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		barFill.BackgroundColor3 = color or P.lilacLip
		percent.Text = `{math.floor(math.clamp(fraction, 0, 1) * 100 + 0.5)}%`
	end
	local shownPips = ""
	local function setPips(filled: number, total: number, text: string?)
		local signature = `{filled}/{total}`
		if signature ~= shownPips then
			shownPips = signature
			Ui.clear(pips)
			local width = if total > 8 then math.max(6, math.floor(9 * s)) else math.max(8, math.floor(13 * s))
			for i = 1, math.max(0, math.floor(total)) do
				local full = i <= filled
				local pip = Ui.make("Frame", {
					Size = UDim2.new(0, width, 1, 0),
					BackgroundColor3 = if full then P.lilacLip else P.paper,
					BorderSizePixel = 0,
					LayoutOrder = i,
				}, pips)
				Ui.corner(pip, 2)
				Ui.stroke(pip, if full then P.lilacLip else P.line, 1).Transparency = 0
			end
		end
		pipsLabel.Text = text or `{filled} / {total} cargo slots`
	end
	local dimTween: Tween? = nil
	local function setDim(on: boolean)
		if dimTween then
			dimTween:Cancel()
		end
		local tween = TweenService:Create(face, TweenInfo.new(0.2), { GroupTransparency = if on then 0.45 else 0 })
		dimTween = tween
		tween:Play()
	end
	face.Destroying:Connect(function()
		if dimTween then
			dimTween:Cancel()
		end
	end)
	return {
		frame = frame,
		face = face,
		title = title,
		value = value,
		unit = unit,
		caption = caption,
		percent = percent,
		barBack = barBack,
		barFill = barFill,
		pips = pips,
		pipsLabel = pipsLabel,
		needle = needle,
		setNeedle = setNeedle,
		setBar = setBar,
		setPips = setPips,
		setDim = setDim,
	}
end

-- ── Text ──────────────────────────────────────────────────────────────────

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
