--!strict
-- Small helpers for building the interface in code.
--
-- 3.8, the contract UI (design/ui-contract/, approved by the owner; it replaces 3.6's "Postage & Trouble"): charcoal
-- rectangles, compact white type, fine grey lines, small precise red accents. No tilts, stubs, lifts, bounces or
-- pastels. The helpers keep their 3.6 signatures, so every module that calls them wears the new look:
--
--   Ui.panel(parent, size, position, anchor?) -> Frame
--       a charcoal card (the HUD's cards): a scrim (Theme.PanelTransparency), square, a fine line.
--   Ui.button(parent, text, size, color, onClick) -> TextButton
--       a flat rectangle with a fine line. `color` says what it means (Theme.soft): yellow / green / money are the
--       MAIN action (raised charcoal, a thin red rule along its bottom, an arrow when there is room), red / blue /
--       grey / the GPS purple get a dark face with that meaning's thin accent; any other colour a charcoal face
--       barely tinted by it. Hover (100 – 140 ms) brightens the face and the label and shows the underline; press
--       dips its opacity. Setting .BackgroundColor3 later (a caller's enabled / selected state) gets the same
--       treatment, and a .TextColor3 that would not read on the face (old dark ink) falls back to the light text.
--   Ui.ghostButton(parent, text, size, accent?, onClick) -> TextButton   a plain text action (no surface).
--   Ui.closeButton(parent, onClick) -> TextButton   a small "✕" (44 × 44 to hit); hover brightens it, red underline.
--   Ui.chip(parent, text, color?, textColor?) -> TextLabel   a compact tag: dark face, the meaning's fine outline.
--   Ui.keyChip(parent, key, size, accent?, props?) -> TextLabel   a key ("M", "ESC") in a square outline.
--   Ui.caps(parent, text, size, props?) -> TextLabel   a small caps label (12 px, the secondary text).
--   Ui.bar(parent, size, color) -> (back, fill)   a thin square bar on a dark track.
--
-- The 3.6 shapes, flattened in 3.8:
--   Ui.window(parent, title, subtitle, icon?, size?) -> (frame, content, chrome)
--       a charcoal rectangle: a header (a red marker and the subtitle as a small caps label, the title, a thin line,
--       a small ✕), the content area and a slim footer (the ESC key, "CLOSE", a context line on the right). `frame` is
--       what you size, move, scale (UIScale) and show; put your things in `content`. chrome: { frame, surface,
--       header, content, footer, icon, title, subtitle, close, esc, escText, context, onClose }. The close action and
--       ESC (or the gamepad's B, or opening the Roblox menu) call chrome.onClose when it is set, else hide `frame`.
--       Ui.WindowHeader / Ui.WindowFooter are the heights (px at scale 1) the content area leaves for the chrome.
--   Ui.ticket(parent, size, position, anchor?, stubWidth?, tilt?, notch?) -> (card, body, stub)
--       a flat row card. `tilt` and `notch` are ignored (kept for the callers); with stubWidth the right column is
--       the stub, behind a fine line (no perforation). Ui.selectRow(card, on) gives it the selected look: a quiet
--       highlight and a narrow red rule on its left.
--   Ui.tactile(target, lift?, hoverScale?)   a hover brightens the target's surface (no lift, no tilt, no growth).
--   Ui.tag(parent, text, index, size?, onClick?) -> (tag, parts)
--       a compact square tile (the consumables): a dark face, a fine line, the name over it on hover / gamepad focus.
--       parts: { key (top left), count (bottom right), label, lip (the hover underline) }.
--   Ui.dial(parent, diameter, position?, anchor?) -> Dial
--       the same API as 3.6's speed dial, drawn as compact text (no circle, no ticks; the needle is hidden).
--   Ui.dashes(parent, vertical, count, color, size, position) -> Frame   a fine solid line (count is ignored).
--
-- Touch: on the touch layout a button, a ghost button, a close action or a tag smaller than 44 px gets invisible
-- margins around it, so its hit area is at least 44 × 44 screen pixels (the drawing stays compact).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))
local Theme = require(script.Parent.Theme)
local Ui = {}
Ui.Colors = Theme.Colors
Ui.Gps = Theme.Gps -- the GPS purple (the routes on the maps)
local K = Theme.Contract

-- ── Screen ────────────────────────────────────────────────────────────────
-- One rule for the size of the interface everywhere (the HUD, its windows, the crew window, the leaderboard): 1 at
-- 1150 × 680 pixels, smaller on phones (at least 0.55), a little bigger on big screens (at most 1.1).
Ui.ScaleBase = Vector2.new(1150, 680)
Ui.MinScale = 0.55
Ui.MaxScale = 1.1
Ui.MinTouch = 44 -- screen px: the smallest hit area on the touch layout

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

-- 4.2, a gamepad: is it what was used last (not the mouse, the keys or a finger)?
function Ui.gamepadActive(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

-- 4.2: a window or a list that opens puts the gamepad's selection on its main action (`target`), so A takes it and
-- the stick moves on from there. Only while a gamepad is in use: the mouse, the keys and touch never see a selection.
function Ui.gamepadFocus(target: GuiObject?)
	if not target or not Ui.gamepadActive() then
		return
	end
	pcall(function()
		GuiService.SelectedObject = target
	end)
end

-- 4.2: a window that closes lets go of the gamepad's selection inside it.
function Ui.gamepadRelease(container: Instance?)
	local selected = GuiService.SelectedObject
	if selected and container and selected:IsDescendantOf(container) then
		GuiService.SelectedObject = nil
	end
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
-- The quiet border (Theme.Border, the default) uses Theme.BorderTransparency; an accent colour is solid. A caller may
-- still set .Transparency on what it returns.
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

-- A charcoal card (the HUD's cards; the windows use Ui.window).
function Ui.panel(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): any
	local frame = Ui.make("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame, Theme.PanelRadius)
	Ui.stroke(frame, Theme.Border, 1)
	return frame
end

-- 3.8: a fine solid line (3.6 drew it dashed; `count` is ignored) of `size` at `position`.
function Ui.dashes(parent: Instance, vertical: boolean, count: number, color: Color3, size: UDim2, position: UDim2): any
	local _ = vertical and count
	local line = Ui.make("Frame", { Name = "Dashes", Size = size, Position = position, BackgroundTransparency = 1 }, parent)
	Ui.make("Frame", { Name = "Line", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, line)
	return line
end

-- ── The small pieces ──────────────────────────────────────────────────────

-- A thin accent rule down the left edge of a card: `inset` px in, a little shorter than the card. It sits outside any
-- layout of the card: give the card's content a frame of its own when it has a UIListLayout.
function Ui.edge(parent: Instance, color: Color3, inset: number?): any
	return Ui.make("Frame", {
		Name = "Edge",
		Size = UDim2.new(0, 2, 1, -16),
		Position = UDim2.new(0, inset or 7, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
end

-- A small caps label (HeadingFont, upper case, the secondary text): the names of things, the units, the keys.
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

-- A key in a square outline ("M", "Q", "K", "ESC"): the light text (or the accent, made readable) on a charcoal scrim.
function Ui.keyChip(parent: Instance, key: string, size: number, accent: Color3?, props: { [string]: any }?): any
	local chip = Ui.label(parent, key, UDim2.fromOffset(size, size), {
		Name = "Key",
		BackgroundTransparency = 0.3,
		BackgroundColor3 = K.charcoal,
		Font = Theme.HeadingFont,
		TextSize = math.max(11, math.floor(size * 0.5)),
		TextColor3 = Theme.readable(accent or K.text, K.charcoal),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	local line = Ui.stroke(chip, K.text, 1)
	line.Transparency = 0.35
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

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WHITE = Color3.new(1, 1, 1)

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Plays a tween and remembers it in `slot` (cancelling the one before), so a fast hover / leave does not stack.
local function play(slots: { [string]: Tween }, slot: string, object: Instance, info: TweenInfo, goal: { [string]: any })
	local before = slots[slot]
	if before then
		before:Cancel()
	end
	local tween = TweenService:Create(object, info, goal)
	slots[slot] = tween
	tween:Play()
end

local function cancelAll(slots: { [string]: Tween })
	for _, tween in slots do
		tween:Cancel()
	end
	table.clear(slots)
end

-- The press feedback: a charcoal veil over the control that dips its opacity for a moment.
local function pressVeil(button: GuiObject): Frame
	return Ui.make("Frame", {
		Name = "PressVeil",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex,
	}, button)
end

-- Touch: invisible margins (outside the drawing) so `button`'s hit area is at least Ui.MinTouch screen px each way.
-- A tap on a margin runs `fire`. Only on the touch layout; re-measured when the button's screen size changes.
local function touchMargins(button: GuiObject, fire: () -> ())
	if not Ui.touchLayout() then
		return
	end
	local margins: { [string]: any } = {}
	for _, side in { "Top", "Bottom", "Left", "Right" } do
		local margin = Ui.make("TextButton", {
			Name = "Hit" .. side,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Selectable = false,
			Visible = false,
			ZIndex = button.ZIndex,
		}, button)
		margin.Activated:Connect(fire)
		margins[side] = margin
	end
	-- The nearby controls a margin must not reach into: the buttons beside it (its siblings) and the ones in its
	-- siblings (a row of holders).
	local function neighbours(): { GuiObject }
		local list: { GuiObject } = {}
		local parent = button.Parent
		if not parent then
			return list
		end
		for _, other in parent:GetChildren() do
			if other ~= button and other:IsA("GuiObject") and other.Visible then
				if other:IsA("GuiButton") then
					table.insert(list, other)
				end
				for _, inner in other:GetChildren() do
					if inner:IsA("GuiButton") and inner.Visible then
						table.insert(list, inner)
					end
				end
			end
		end
		return list
	end
	local function measure()
		local shown = button.AbsoluteSize
		if shown.X <= 0 or shown.Y <= 0 then
			return
		end
		-- The UIScales above it: screen px per local px (from the offset part of the size, when it has one).
		local unitX = if button.Size.X.Offset > 0 and button.Size.X.Scale == 0 then shown.X / button.Size.X.Offset else 1
		local unitY = if button.Size.Y.Offset > 0 and button.Size.Y.Scale == 0 then shown.Y / button.Size.Y.Offset else 1
		local needY = math.max(0, (Ui.MinTouch - shown.Y) / 2)
		local needX = math.max(0, (Ui.MinTouch - shown.X) / 2)
		-- Each side grows at most halfway to the next control on that side (screen px), so it never takes its taps.
		local room = { Top = needY, Bottom = needY, Left = needX, Right = needX }
		if needX > 0 or needY > 0 then
			local at = button.AbsolutePosition
			local x1, y1, x2, y2 = at.X, at.Y, at.X + shown.X, at.Y + shown.Y
			-- Not out of its own row: a button in a row frame (a list of rows, each with its KICK / INVITE) stops at the
			-- row's edge, so a tap just under it never reaches the next row's button.
			local holder = button.Parent
			if holder and holder:IsA("GuiObject") then
				local hp, hs = holder.AbsolutePosition, holder.AbsoluteSize
				if hs.Y > shown.Y + 1 then
					room.Top = math.min(room.Top, math.max(0, y1 - hp.Y))
					room.Bottom = math.min(room.Bottom, math.max(0, hp.Y + hs.Y - y2))
				end
				if hs.X > shown.X + 1 then
					room.Left = math.min(room.Left, math.max(0, x1 - hp.X))
					room.Right = math.min(room.Right, math.max(0, hp.X + hs.X - x2))
				end
			end
			for _, other in neighbours() do
				local p, s = other.AbsolutePosition, other.AbsoluteSize
				local ox1, oy1, ox2, oy2 = p.X, p.Y, p.X + s.X, p.Y + s.Y
				if ox1 < x2 + needX and ox2 > x1 - needX then -- in the same column: above or below
					if oy2 <= y1 then
						room.Top = math.min(room.Top, (y1 - oy2) / 2)
					elseif oy1 >= y2 then
						room.Bottom = math.min(room.Bottom, (oy1 - y2) / 2)
					end
				end
				if oy1 < y2 + needY and oy2 > y1 - needY then -- in the same row: left or right
					if ox2 <= x1 then
						room.Left = math.min(room.Left, (x1 - ox2) / 2)
					elseif ox1 >= x2 then
						room.Right = math.min(room.Right, (ox1 - x2) / 2)
					end
				end
			end
		end
		local top, bottom = room.Top / math.max(0.05, unitY), room.Bottom / math.max(0.05, unitY)
		local left, right = room.Left / math.max(0.05, unitX), room.Right / math.max(0.05, unitX)
		margins.Top.Visible, margins.Bottom.Visible = top > 0.5, bottom > 0.5
		margins.Left.Visible, margins.Right.Visible = left > 0.5, right > 0.5
		margins.Top.Size = UDim2.new(1, 0, 0, top)
		margins.Top.Position = UDim2.fromOffset(0, -top)
		margins.Bottom.Size = UDim2.new(1, 0, 0, bottom)
		margins.Bottom.Position = UDim2.new(0, 0, 1, 0)
		margins.Left.Size = UDim2.new(0, left, 1, 0)
		margins.Left.Position = UDim2.fromOffset(-left, 0)
		margins.Right.Size = UDim2.new(0, right, 1, 0)
		margins.Right.Position = UDim2.new(1, 0, 0, 0)
	end
	-- Re-measured when it changes size and when its neighbours change (a layout filled in later); not every frame.
	local queued = false
	local function later()
		if queued then
			return
		end
		queued = true
		task.delay(0.1, function()
			queued = false
			if button.Parent then
				measure()
			end
		end)
	end
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(later)
	button:GetPropertyChangedSignal("ZIndex"):Connect(function()
		for _, margin in margins do
			margin.ZIndex = button.ZIndex
		end
	end)
	local watched: { RBXScriptConnection } = {}
	local function watchParent()
		for _, connection in watched do
			connection:Disconnect()
		end
		table.clear(watched)
		local parent = button.Parent
		if parent then
			table.insert(watched, parent.ChildAdded:Connect(later))
			table.insert(watched, parent.ChildRemoved:Connect(later))
		end
		later()
	end
	button.AncestryChanged:Connect(watchParent)
	button.Destroying:Connect(function()
		for _, connection in watched do
			connection:Disconnect()
		end
		table.clear(watched)
	end)
	watchParent()
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
	local border = Ui.stroke(button, K.rule, 1)
	border.Transparency = 0
	-- The thin rule along the bottom: the main action's red accent (always), every other action's hover underline.
	local lip = Ui.make("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = look.lip,
		BackgroundTransparency = if look.main then 0 else 1,
		BorderSizePixel = 0,
	}, button)
	-- The main action's arrow (only while the text leaves room for it).
	local arrow = Ui.make("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Text = "→",
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextColor3 = look.text,
		Visible = false,
	}, button)
	local veil = pressVeil(button)
	local tweens: { [string]: Tween } = {}

	local hovered = false
	local applied = look.face -- the face this button set last (a caller's own colour differs from it)
	local function face(): Color3
		return if hovered and not look.quiet then look.face:Lerp(WHITE, 0.07) else look.face
	end
	local function refreshArrow()
		local room = button.AbsoluteSize.X - button.TextBounds.X
		arrow.Visible = look.main and button.Text ~= "" and room >= 56 and not string.find(button.Text, "→", 1, true)
		arrow.TextColor3 = button.TextColor3
		arrow.ZIndex = button.ZIndex
		lip.ZIndex = button.ZIndex
		veil.ZIndex = button.ZIndex
	end
	local function paint()
		applied = face()
		button.BackgroundColor3 = applied
		lip.BackgroundColor3 = if look.main or look.lip ~= K.rule then look.lip else K.text
		play(tweens, "lip", lip, HOVER_INFO, { BackgroundTransparency = if look.main or (hovered and not look.quiet) then 0 else 1 })
		border.Color = if hovered and not look.quiet then K.line else K.rule
	end
	-- A caller set .BackgroundColor3 (its enabled / selected state): wear that colour's face.
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		local now = button.BackgroundColor3
		if Theme.same(now, applied) then
			return
		end
		local nextLook = Theme.soft(now)
		if nextLook == look then
			-- the same meaning again (a window's step() repaints every 0.05 s): keep the face, no new tween
			button.BackgroundColor3 = applied
			return
		end
		look = nextLook
		paint()
		if button:GetAttribute("KeepStroke") == true then
			border.Color = K.rule
		end
		button.TextColor3 = Theme.readable(button.TextColor3, look.face)
		refreshArrow()
	end)
	-- A caller's text colour that would not read on the face (old dark ink): the face's text.
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

	local function press(on: boolean)
		play(tweens, "press", veil, PRESS_INFO, { BackgroundTransparency = if on then 0.55 else 1 })
	end
	local function hover(on: boolean)
		hovered = on
		paint()
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function()
		hover(false)
		press(false)
	end)
	button.SelectionGained:Connect(function() hover(true) end)
	button.SelectionLost:Connect(function() hover(false) end)
	button.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			press(true)
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			press(false)
		end
	end)
	button.Destroying:Connect(function()
		cancelAll(tweens)
	end)
	local function fire()
		click(onClick)
	end
	button.Activated:Connect(fire)
	touchMargins(button, fire)
	task.defer(refreshArrow)
	return button
end

-- A plain text action: no surface, the label in the accent (made readable) or the light text; hover brightens it and
-- shows a thin underline. For the secondary actions (back, decline, OK, controls) next to the main one.
function Ui.ghostButton(parent: Instance, text: string, size: UDim2, accent: Color3?, onClick: () -> ()): any
	local button = Ui.button(parent, text, size, Ui.Colors.panelLight, onClick)
	button:SetAttribute("KeepStroke", true)
	button.BackgroundTransparency = 1
	button.TextColor3 = Theme.readable(accent or K.secondary, K.charcoal)
	local border = button:FindFirstChild("UiBorder")
	if border and border:IsA("UIStroke") then
		border.Enabled = false
	end
	-- The underline sits under the label, a little in from the edges.
	local lip = button:FindFirstChild("Lip")
	if lip and lip:IsA("Frame") then
		lip.Size = UDim2.new(1, -24, 0, 1)
		lip.Position = UDim2.new(0, 12, 1, -6)
	end
	local resting = button.TextColor3
	button:GetPropertyChangedSignal("TextColor3"):Connect(function()
		if not Theme.same(button.TextColor3, K.text) then
			resting = button.TextColor3
		end
	end)
	local function hover(on: boolean)
		button.TextColor3 = if on then K.text else resting
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function() hover(false) end)
	button.SelectionGained:Connect(function() hover(true) end)
	button.SelectionLost:Connect(function() hover(false) end)
	hover(false)
	return button
end

-- A window's close action: a small "✕" in the secondary text (a 44 × 44 hit area); hover / focus brightens it and
-- shows a red underline, press dips it.
function Ui.closeButton(parent: Instance, onClick: () -> ()): any
	local close = Ui.make("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "✕",
		TextColor3 = K.text, -- 4.0.2: the one way out shown (ESC is Roblox's own menu key)
		Font = Theme.HeadingFont,
		TextSize = 22,
		AutoButtonColor = false,
	}, parent)
	local mark = Ui.make("Frame", {
		Name = "Underline",
		Size = UDim2.fromOffset(14, 2),
		Position = UDim2.new(0.5, 0, 0.5, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = K.red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, close)
	local tweens: { [string]: Tween } = {}
	local function hover(on: boolean)
		play(tweens, "text", close, HOVER_INFO, { TextColor3 = if on then K.red else K.text })
		play(tweens, "mark", mark, HOVER_INFO, { BackgroundTransparency = if on then 0 else 1 })
	end
	close.MouseEnter:Connect(function() hover(true) end)
	close.MouseLeave:Connect(function()
		hover(false)
		close.TextTransparency = 0
	end)
	close.SelectionGained:Connect(function() hover(true) end)
	close.SelectionLost:Connect(function() hover(false) end)
	close.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			close.TextTransparency = 0.45
		end
	end)
	close.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			close.TextTransparency = 0
		end
	end)
	close.Destroying:Connect(function()
		cancelAll(tweens)
	end)
	local function fire()
		click(onClick)
	end
	close.Activated:Connect(fire)
	touchMargins(close, fire)
	return close
end

-- A compact tag that grows with its text (cargo counts, rewards): a dark face (Theme.soft of `color`) with a fine
-- outline in the meaning's accent; a `textColor` that would not read on it falls back to the light text.
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
		TextSize = 12,
	}, parent)
	Ui.corner(chip, Theme.Radius)
	local outline = Ui.stroke(chip, look.lip, 1)
	outline.Transparency = if look.quiet or look.lip == K.rule then 0 else 0.4
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
	-- A caller's later colours get the same treatment.
	chip:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if Theme.isFace(chip.BackgroundColor3) or Theme.same(chip.BackgroundColor3, look.face) then
			return
		end
		look = Theme.soft(chip.BackgroundColor3)
		chip.BackgroundColor3 = look.face
		outline.Color = look.lip
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

-- A thin square bar: `color` on a dark track.
function Ui.bar(parent: Instance, size: UDim2, color: Color3): (any, any)
	local back = Ui.make("Frame", { Size = size, BackgroundColor3 = K.track, BorderSizePixel = 0 }, parent)
	local fill = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	return back, fill
end

function Ui.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- ── Rows (3.6's tickets, flat since 3.8) ──────────────────────────────────

-- A flat row card: a dark surface (the caller may recolour it), a fine line, no tilt, no shadow. With `stubWidth` the
-- right column (the stub) sits behind a fine vertical line. Returns the card, its body (content area) and the stub
-- (nil without one). The card sits in a transparent holder named "Ticket" (its .Parent), the thing a layout places.
function Ui.ticket(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?, stubWidth: number?, tilt: number?, notch: Color3?): (any, any, any)
	local _ = tilt and notch -- 3.8: no tilt, no die-cut notches
	local holder = Ui.make("Frame", {
		Name = "Ticket",
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundTransparency = 1,
	}, parent)
	local card = Ui.make("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
	}, holder)
	Ui.stroke(card, K.rule, 1).Transparency = 0
	-- The selected row's narrow red rule (Ui.selectRow shows it).
	Ui.make("Frame", {
		Name = "Rule",
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, card)
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
		Ui.make("Frame", {
			Name = "Divider",
			Size = UDim2.new(0, 1, 1, -24),
			Position = UDim2.new(1, -stubW, 0, 12),
			BackgroundColor3 = K.rule,
			BorderSizePixel = 0,
		}, card)
	end
	return card, body, stub
end

-- The selected look of a row (a Ui.ticket card, or any frame): a quiet highlight and a narrow red rule on its left
-- (keyboard / gamepad selection gets the same). Off: back to the row surface.
function Ui.selectRow(card: GuiObject, on: boolean)
	local rule = card:FindFirstChild("Rule")
	if not rule then
		rule = Ui.make("Frame", {
			Name = "Rule",
			Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = K.red,
			BorderSizePixel = 0,
			ZIndex = card.ZIndex + 2,
		}, card)
	end
	if rule and rule:IsA("GuiObject") then
		rule.Visible = on
	end
	card.BackgroundColor3 = if on then K.raised else K.row
end

-- Hover for a row or a control (or any GuiObject inside one): its surface brightens a little (100 – 140 ms), with no
-- lift, tilt or growth. A transparent holder (Ui.ticket's) brightens its "Card". `lift` and `hoverScale` are ignored
-- (kept for the callers). Touch taps activate at once (no hover step). The tween is cancelled when it is destroyed.
function Ui.tactile(target: GuiObject, lift: number?, hoverScale: number?)
	local _ = lift and hoverScale
	if target:FindFirstChild("PressVeil") then
		return -- a Ui.button: it has its own hover
	end
	local surface: GuiObject = target
	if target.BackgroundTransparency >= 1 then
		local card = target:FindFirstChild("Card")
		if card and card:IsA("GuiObject") then
			surface = card
		end
	end
	local tweens: { [string]: Tween } = {}
	local resting: Color3? = nil -- the caller's colour, while we brighten it
	local lit: Color3? = nil
	local function hover(on: boolean)
		if on then
			if resting == nil then
				resting = surface.BackgroundColor3
			end
			local base = resting :: Color3
			local goal = base:Lerp(WHITE, 0.05)
			lit = goal
			play(tweens, "face", surface, HOVER_INFO, { BackgroundColor3 = goal })
		else
			local base = resting
			resting = nil
			local mine = lit
			local running: Tween? = tweens.face
			if base and mine then
				-- Only undo our own brightening (a caller that recoloured it meanwhile keeps its colour).
				local ours = Theme.same(surface.BackgroundColor3, mine)
					or (if running then running.PlaybackState == Enum.PlaybackState.Playing else false)
				if ours then
					play(tweens, "face", surface, HOVER_INFO, { BackgroundColor3 = base })
				end
			end
		end
	end
	target.MouseEnter:Connect(function() hover(true) end)
	target.MouseLeave:Connect(function() hover(false) end)
	target.SelectionGained:Connect(function() hover(true) end)
	target.SelectionLost:Connect(function() hover(false) end)
	target.Destroying:Connect(function()
		cancelAll(tweens)
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

-- Keeps a label in upper case (the small caps labels a caller may set later).
local function upperCase(label: TextLabel)
	label.Text = string.upper(label.Text)
	label:GetPropertyChangedSignal("Text"):Connect(function()
		local upper = string.upper(label.Text)
		if upper ~= label.Text then
			label.Text = upper
		end
	end)
end

-- A charcoal window: see the top of this file. `icon` (an Icons name or an emoji) is kept in a hidden badge for the
-- callers that still reach it (chrome.icon); the header is type only.
function Ui.window(parent: Instance, title: string, subtitle: string, icon: string?, size: UDim2?): (any, any, WindowChrome)
	local frame = Ui.make("Frame", {
		Name = "Window",
		Size = size or UDim2.fromOffset(760, 520),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, parent)
	local surface = Ui.make("Frame", {
		Name = "Surface",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true, -- clicks on the window do not reach the world
	}, frame)
	Ui.stroke(surface, K.rule, 1).Transparency = 0

	-- The header: a red marker and the small caps label (the subtitle), the title, a thin line, the ✕.
	local headerH, footerH = Ui.WindowHeader, Ui.WindowFooter
	local header = Ui.make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, headerH), BackgroundTransparency = 1, BorderSizePixel = 0 }, surface)
	Ui.make("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -48, 0, 1),
		Position = UDim2.new(0, 24, 1, -1),
		BackgroundColor3 = K.rule,
		BorderSizePixel = 0,
	}, header)
	Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(7, 7),
		Position = UDim2.fromOffset(24, 21),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
	}, header)
	local badge = Ui.make("Frame", { Name = "Badge", Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1, Visible = false }, header)
	local iconObject = Ui.icon(badge, icon, icon or "", UDim2.fromOffset(24, 24), {
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = K.secondary,
		ImageColor3 = K.secondary,
	})
	local subtitleLabel = Ui.label(header, subtitle, UDim2.new(1, -120, 0, 16), {
		Name = "Subtitle",
		Position = UDim2.fromOffset(40, 17),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	upperCase(subtitleLabel)
	local titleLabel = Ui.label(header, title, UDim2.new(1, -120, 0, 30), {
		Name = "Title",
		Position = UDim2.fromOffset(24, 36),
		Font = Theme.DisplayFont,
		TextSize = 22,
		TextColor3 = K.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	upperCase(titleLabel)

	local content = Ui.make("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 1, -(headerH + footerH)),
		Position = UDim2.fromOffset(0, headerH),
		BackgroundTransparency = 1,
	}, surface)

	-- The slim footer: the context (the caller's) on the right, a thin line over it. (4.0.2: no "ESC · CLOSE" on the
	-- left any more: ESC is Roblox's menu; the ✕ in the header closes, and so does the window's own key, J for the jobs.)
	local footer = Ui.make("Frame", {
		Name = "Footer",
		Size = UDim2.new(1, 0, 0, footerH),
		Position = UDim2.new(0, 0, 1, -footerH),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, surface)
	Ui.make("Frame", { Name = "Line", Size = UDim2.new(1, -48, 0, 1), Position = UDim2.fromOffset(24, 0), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, footer)
	local touch = Ui.touchLayout()
	local esc = Ui.keyChip(footer, if touch then "✕" else "ESC", 22, K.secondary, {
		Size = UDim2.fromOffset(if touch then 22 else 34, 22),
		Position = UDim2.new(0, 24, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextSize = 11,
		Visible = false,
	})
	local escText = Ui.label(footer, if touch then "TAP ✕ TO CLOSE" else "CLOSE", UDim2.fromOffset(150, 20), {
		Visible = false,
		Position = UDim2.new(0, if touch then 54 else 68, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
	})
	local context = Ui.label(footer, "", UDim2.new(1, -260, 0, 20), {
		Name = "Context",
		Position = UDim2.new(1, -24, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
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
	close.Position = UDim2.new(1, -14, 0.5, 0)
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

-- A compact square tile (the consumables): see the top of this file. `text` is its face (an emoji; set it to "" and
-- put an Ui.icon in it for a picture).
function Ui.tag(parent: Instance, text: string, index: number, size: UDim2?, onClick: (() -> ())?): (any, TagParts)
	local _ = index -- 3.8: every tile wears the same face (3.6 alternated pastels and tilts by index)
	local tag = Ui.make("TextButton", {
		Name = "Tag",
		Size = size or UDim2.fromOffset(46, 50),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = K.text,
		Font = Theme.HeadingFont,
		TextSize = 20,
		AutoButtonColor = false,
	}, parent)
	Ui.stroke(tag, K.rule, 1).Transparency = 0
	-- The hover / focus underline (the red edge marker).
	local lip = Ui.make("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = K.red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, tag)
	local key = Ui.label(tag, "", UDim2.fromOffset(16, 14), {
		Name = "KeyNumber",
		Position = UDim2.fromOffset(4, 2),
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
	})
	local count = Ui.label(tag, "", UDim2.fromOffset(24, 14), {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	-- The name over it: shows on hover / gamepad focus.
	local label = Ui.label(tag, "", UDim2.fromOffset(0, 24), {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = K.charcoal,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.text,
		TextWrapped = false,
		Visible = false,
		ZIndex = 5,
	})
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, label)
	local tweens: { [string]: Tween } = {}
	local function name(on: boolean)
		label.Visible = on and label.Text ~= ""
		play(tweens, "lip", lip, HOVER_INFO, { BackgroundTransparency = if on then 0 else 1 })
	end
	tag.MouseEnter:Connect(function() name(true) end)
	tag.MouseLeave:Connect(function()
		name(false)
		tag.TextTransparency = 0
	end)
	tag.SelectionGained:Connect(function() name(true) end)
	tag.SelectionLost:Connect(function() name(false) end)
	tag.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			tag.TextTransparency = 0.4
		end
	end)
	tag.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			tag.TextTransparency = 0
		end
	end)
	tag.Destroying:Connect(function()
		cancelAll(tweens)
	end)
	Ui.tactile(tag)
	if onClick then
		local function fire()
			click(onClick)
		end
		tag.Activated:Connect(fire)
		touchMargins(tag, fire)
	end
	return tag, { key = key, count = count, label = label, lip = lip }
end

-- ── The dial (3.6's speed dial, compact text since 3.8) ───────────────────

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

-- The 3.6 dial's API as a compact, right-aligned text group in a `diameter` square (the space the old dial took):
-- the title in small caps, the value with its unit, the condition (caption, percent, a thin bar), the slots as small
-- squares and their line. No circle and no ticks; the needle exists but stays hidden. No text under 12 px.
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
	local face = Ui.make("CanvasGroup", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 0,
	}, frame)
	local needle = Ui.make("Frame", { Name = "Needle", Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Visible = false }, face)
	local function setNeedle(fraction: number)
		needle:SetAttribute("Fraction", math.clamp(fraction, 0, 1))
	end
	local right = Enum.TextXAlignment.Right
	local title = Ui.caps(face, "", UDim2.new(1, 0, 0, px(14)), {
		Name = "Title",
		Position = UDim2.fromScale(0, 0.2),
		TextSize = px(12),
		TextXAlignment = right,
	})
	local speedRow = Ui.make("Frame", {
		Name = "Speed",
		Size = UDim2.new(1, 0, 0, math.floor(44 * s)),
		Position = UDim2.new(0, 0, 0.2, px(16)),
		BackgroundTransparency = 1,
	}, face)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, math.floor(4 * s)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, speedRow)
	local value = Ui.label(speedRow, "0", UDim2.fromScale(0, 1), {
		Name = "Value",
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = math.max(18, math.floor(36 * s)),
		TextColor3 = K.text,
		TextWrapped = false,
		TextXAlignment = right,
		LayoutOrder = 1,
	})
	local unit = Ui.label(speedRow, "KM/H", UDim2.fromOffset(0, px(14) + math.floor(6 * s)), {
		Name = "Unit",
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = px(12),
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
	})
	local caption = Ui.caps(face, "Vehicle condition", UDim2.new(1, -48, 0, px(14)), {
		Name = "Caption",
		Position = UDim2.new(0, 0, 0.58, 0),
	})
	caption.TextSize = px(12)
	local percent = Ui.label(face, "", UDim2.fromOffset(44, px(14)), {
		Name = "Percent",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0.58, 0),
		Font = Theme.HeadingFont,
		TextSize = px(12),
		TextColor3 = K.text,
		TextXAlignment = right,
		TextWrapped = false,
	})
	local barBack, barFill = Ui.bar(face, UDim2.new(1, 0, 0, 2), K.text)
	barBack.Name = "Condition"
	barBack.Position = UDim2.new(0, 0, 0.58, px(14) + 6)
	local pips = Ui.make("Frame", {
		Name = "Pips",
		Size = UDim2.new(1, 0, 0, math.max(6, math.floor(8 * s))),
		Position = UDim2.new(0, 0, 0.74, 0),
		BackgroundTransparency = 1,
	}, face)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pips)
	local pipsLabel = Ui.label(face, "", UDim2.new(1, 0, 0, px(14)), {
		Name = "PipsLabel",
		Position = UDim2.new(0, 0, 0.8, 0),
		Font = Theme.HeadingFont,
		TextSize = px(12),
		TextColor3 = K.secondary,
		TextXAlignment = right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local function setBar(fraction: number, color: Color3?)
		barFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		barFill.BackgroundColor3 = color or K.text
		percent.Text = `{math.floor(math.clamp(fraction, 0, 1) * 100 + 0.5)}%`
	end
	local shownPips = ""
	local function setPips(filled: number, total: number, text: string?)
		local signature = `{filled}/{total}`
		if signature ~= shownPips then
			shownPips = signature
			Ui.clear(pips)
			local width = if total > 8 then math.max(5, math.floor(7 * s)) else math.max(7, math.floor(10 * s))
			for i = 1, math.max(0, math.floor(total)) do
				local full = i <= filled
				local pip = Ui.make("Frame", {
					Size = UDim2.new(0, width, 1, 0),
					BackgroundColor3 = K.text,
					BackgroundTransparency = if full then 0 else 1,
					BorderSizePixel = 0,
					LayoutOrder = i,
				}, pips)
				Ui.stroke(pip, if full then K.text else K.line, 1).Transparency = 0
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
