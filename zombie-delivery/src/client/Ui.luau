--!strict
-- Small helpers for building the interface in code.
--
-- 3.8, the contract UI (design/ui-contract/, approved by the owner; it replaces 3.6's "Postage & Trouble"): charcoal
-- rectangles, compact white type, fine grey lines, small precise red accents. No tilts, stubs, lifts, bounces or
-- pastels. The helpers keep their 3.6 signatures, so every module that calls them wears the new look:
--
--   Ui.button(parent, text, size, color, onClick) -> TextButton
--       a flat rectangle with a fine line. `color` says what it means (Theme.soft): yellow / green / money are the
--       MAIN action (raised charcoal, a thin red rule along its bottom, an arrow when there is room), red / blue /
--       grey / the GPS purple get a dark face with that meaning's thin accent; any other colour a charcoal face
--       barely tinted by it. Hover (100 – 140 ms) brightens the face and the label and shows the underline; press
--       dips its opacity. Setting .BackgroundColor3 later (a caller's enabled / selected state) gets the same
--       treatment, and a .TextColor3 that would not read on the face (old dark ink) falls back to the light text.
--       5.8: `color` = Theme.Contract.red is the PRIMARY action, the phone's red button: a red face, white caps (also
--       a text set later), square, no arrow; hover brightens the face. (Theme.Colors.red stays the danger meaning.)
--   Ui.ghostButton(parent, text, size, accent?, onClick) -> TextButton   a plain text action (no surface).
--   Ui.closeButton(parent, onClick) -> TextButton   a "✕" in a 40 × 40 square outline (44 × 44 to hit on touch);
--       hover raises it and turns the outline red.
--   Ui.keyChip(parent, key, size, accent?, props?) -> TextLabel   a key ("M", "ESC") in a square outline.
--   Ui.caps(parent, text, size, props?) -> TextLabel   a small caps label (12 px, the secondary text).
--
-- 5.8, the courier phone's marks (design/phone-ui/) for every window:
--   Ui.brand(parent, size?, props?) -> Frame   the company's mark: the red square and the "DELIVEROS" wordmark (8.9: was ZDC).
--   Ui.glyph(slot, id, size?)   draws the white line glyph `id` (PhoneContract: "map", "settings"; "" clears).
--   Ui.glyphFor(icon?) -> string   the glyph id for a window's emoji icon ("" when none fits).
--   Ui.heading(parent, title, options?) -> Heading   one header line: [■ ZDC] | [glyph] TITLE in caps.
--       options: { glyph: string?, brand: boolean?, textSize: number?, height: number? };
--       Heading: { frame, brand, glyph, title }.
--
-- The 3.6 shapes, flattened in 3.8:
--   Ui.window(parent, title, subtitle, icon?, size?, options?) -> (frame, content, chrome)
--       a charcoal rectangle: a header (5.8: the ZDC mark, a thin rule, the line glyph and the title in caps, the
--       subtitle in small caps under it, a thin line, the square ✕), the content area and a slim footer (a context
--       line on the right). options: { glyph: string?, brand: boolean? } (the glyph defaults to the icon's, see
--       WindowOptions). `frame` is what you size, move, scale (UIScale) and show; put your things in `content`.
--       chrome: { frame, surface, header, content, footer, icon, title, subtitle, close, esc, escText, context,
--       heading, glyph, onClose }. The close action and ESC (or the gamepad's B, or opening the Roblox menu) call
--       chrome.onClose when it is set, else hide `frame`. Ui.WindowHeader / Ui.WindowFooter are the heights (px at
--       scale 1) the content area leaves for the chrome.
--   Ui.ticket(parent, size, position, anchor?, stubWidth?, tilt?, notch?) -> (card, body, stub)
--       5.8: a slim row like the phone's: the row surface, a hairline, no corners, no stub line. `tilt` and `notch`
--       are ignored (kept for the callers); with stubWidth the right column is a plain content area (the stub).
--       Ui.selectRow(card, on) gives it (or any row) the selected look: raised, a brighter hairline and a narrow red
--       rule down its left edge, outside the card's padding (keep a layout inside the body, not on the card).
-- 10.6: the city's pieces nobody draws any more are gone (the HUD's panel, the chip, the bar, the dashes, the edge,
-- the square tabs, the consumables' tag and its hover, the speed dial, the danger stars, the padding).
--
-- Touch: on the touch layout a button, a ghost button or a close action smaller than 44 px gets invisible
-- margins around it, so its hit area is at least 44 × 44 screen pixels (the drawing stays compact).

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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

-- 6.8 review: what the gamepad has selected now (nil: nothing), so a window that rebuilds its rows can put it back.
function Ui.gamepadSelection(): GuiObject?
	return GuiService.SelectedObject
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

function Ui.list(parent: Instance, vertical: boolean, gap: number, align: Enum.HorizontalAlignment?)
	Ui.make("UIListLayout", {
		FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	}, parent)
end

-- ── The small pieces ──────────────────────────────────────────────────────

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
		Text = if look.primary then string.upper(text) else text,
		TextColor3 = look.text,
		Font = Theme.HeadingFont,
		TextSize = 18,
		AutoButtonColor = false,
	}, parent)
	-- 5.8: the primary action (Contract.red) is square; the others keep the 0 – 2 px corner.
	local corner = Ui.make("UICorner", { CornerRadius = UDim.new(0, if look.primary then 0 else Theme.Radius) }, button)
	local border = Ui.stroke(button, if look.primary then look.face else K.rule, 1)
	border.Transparency = 0
	-- The thin rule along the bottom: the main action's red accent (always), every other action's hover underline.
	local lip = Ui.make("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = look.lip,
		BackgroundTransparency = if look.main and not look.primary then 0 else 1,
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
		arrow.Visible = look.main and not look.primary and button.Text ~= "" and room >= 56 and not string.find(button.Text, "→", 1, true)
		arrow.TextColor3 = button.TextColor3
		arrow.ZIndex = button.ZIndex
		lip.ZIndex = button.ZIndex
		veil.ZIndex = button.ZIndex
	end
	-- The primary action's label is in caps (also a text a caller sets later; RichText is left alone).
	local function caps()
		if look.primary and not button.RichText then
			local upper = string.upper(button.Text)
			if upper ~= button.Text then
				button.Text = upper
			end
		end
	end
	local function paint()
		applied = face()
		button.BackgroundColor3 = applied
		corner.CornerRadius = UDim.new(0, if look.primary then 0 else Theme.Radius)
		lip.BackgroundColor3 = if look.main or look.lip ~= K.rule then look.lip else K.text
		play(tweens, "lip", lip, HOVER_INFO, { BackgroundTransparency = if look.primary then 1 elseif look.main or (hovered and not look.quiet) then 0 else 1 })
		border.Color = if look.primary then applied elseif hovered and not look.quiet then K.line else K.rule
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
		caps()
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
	button:GetPropertyChangedSignal("Text"):Connect(caps)
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

-- A window's close action (5.8, the phone's square): a "✕" in a 40 × 40 square outline (at least 44 × 44 to hit on
-- touch); hover / focus raises its face and turns the outline red, press dips the mark.
function Ui.closeButton(parent: Instance, onClick: () -> ()): any
	local close = Ui.make("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		BackgroundColor3 = K.raised,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "✕",
		TextColor3 = K.text, -- 4.0.2: the one way out shown (ESC is Roblox's own menu key)
		Font = Theme.HeadingFont,
		TextSize = 18,
		AutoButtonColor = false,
	}, parent)
	local outline = Ui.make("UIStroke", {
		Name = "Outline",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = K.rule,
		Thickness = 1,
	}, close)
	local tweens: { [string]: Tween } = {}
	local function hover(on: boolean)
		play(tweens, "face", close, HOVER_INFO, { BackgroundTransparency = if on then 0 else 1 })
		play(tweens, "line", outline, HOVER_INFO, { Color = if on then K.red else K.rule })
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

function Ui.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- ── Rows (3.6's tickets, flat since 3.8) ──────────────────────────────────

-- The hairline's transparency on a slim row (the selected row's: Ui.HAIRLINE_SELECTED), K.line over the row surface.
Ui.HAIRLINE = 0.8
Ui.HAIRLINE_SELECTED = 0.5

-- 5.8, a slim row like the phone's (HudContract.row): a charcoal row surface (the caller may recolour it), a hairline,
-- no corners, no stub line, no tilt, no shadow. With `stubWidth` the right column (the stub) is a plain content area
-- of that width. Returns the card, its body (content area) and the stub (nil without one). The card sits in a
-- transparent holder named "Ticket" (its .Parent), the thing a layout places. The selected look's red rule (Ui.selectRow)
-- is the card's own child, beside body and stub: give the card's content a layout inside `body`, never on the card.
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
	Ui.stroke(card, K.line, 1).Transparency = Ui.HAIRLINE
	-- The selected row's narrow red rule (Ui.selectRow shows it), outside the body's layout.
	Ui.make("Frame", {
		Name = "Rule",
		Size = UDim2.new(0, 2, 1, 0),
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
	end
	return card, body, stub
end

-- The selected look of a row (a Ui.ticket card, or any frame / button): raised, its hairline a little brighter, and a
-- narrow red rule down its left edge (keyboard / gamepad selection gets the same). Off: back to the row surface. The
-- rule is a child named "Rule" placed over the card's left edge, outside any UIPadding of the card (the phone's card
-- fix); a card that holds a UIListLayout itself would lay the rule out too, so keep the layout in an inner frame
-- (Ui.ticket's body).
function Ui.selectRow(card: GuiObject, on: boolean)
	local rule = card:FindFirstChild("Rule")
	if not rule then
		local pad = card:FindFirstChildOfClass("UIPadding")
		local left = if pad then pad.PaddingLeft.Offset else 0
		local top = if pad then pad.PaddingTop.Offset else 0
		local bottom = if pad then pad.PaddingBottom.Offset else 0
		rule = Ui.make("Frame", {
			Name = "Rule",
			Size = UDim2.new(0, 2, 1, top + bottom),
			Position = UDim2.fromOffset(-left, -top),
			BackgroundColor3 = K.red,
			BorderSizePixel = 0,
			ZIndex = card.ZIndex + 2,
		}, card)
	end
	if rule and rule:IsA("GuiObject") then
		rule.Visible = on
	end
	card.BackgroundColor3 = if on then K.raised else K.row
	local hairline = card:FindFirstChild("UiBorder")
	if hairline and hairline:IsA("UIStroke") and card:FindFirstChild("PressVeil") == nil then
		hairline.Color = K.line
		hairline.Transparency = if on then Ui.HAIRLINE_SELECTED else Ui.HAIRLINE
	end
end

-- ── The ZDC mark, the line glyphs and the heading (5.8, the phone's look) ─

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

-- The ZDC mark (the phone's brand): the red square and the "ZDC" wordmark in `size` px type (default 20), in a
-- transparent Frame named "Brand" sized to fit (its width is .Size.X.Offset). props go to that frame.
function Ui.brand(parent: Instance, size: number?, props: { [string]: any }?): any
	local s = size or 20
	local square = math.max(8, math.floor(s * 0.6 + 0.5))
	local wordW = math.floor(s * 5.4 + 0.5) -- (8.9: DELIVEROS, nine letters)
	local frame = Ui.make("Frame", {
		Name = "Brand",
		Size = UDim2.fromOffset(square + 6 + wordW, s + 8),
		BackgroundTransparency = 1,
	}, parent)
	Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(square, square),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
	}, frame)
	Ui.label(frame, "DELIVEROS", UDim2.new(0, wordW, 1, 0), {
		Name = "Wordmark",
		Position = UDim2.fromOffset(square + 6, 0),
		Font = Theme.DisplayFont,
		TextSize = s,
		TextColor3 = K.text,
		TextWrapped = false,
	})
	if props then
		for key, value in props do
			frame[key] = value
		end
	end
	return frame
end

-- The line glyph (client/PhoneContract's GLYPHS) for the icons the windows pass to Ui.window: "" for none.
local ICON_GLYPHS: { [string]: string } = {
	["🛠"] = "settings", -- the admin panel
	["⚙"] = "settings",
	["🗺"] = "map",
}

-- The line glyph id for a window's `icon` (an emoji, with or without its emoji variation selector), "" if none fits.
function Ui.glyphFor(icon: string?): string
	if not icon then
		return ""
	end
	local plain = string.gsub(icon, "\u{FE0F}", "")
	return ICON_GLYPHS[plain] or ""
end

-- client/PhoneContract draws the glyphs. It requires this module, so it is required here only when the first glyph
-- is drawn (both have loaded by then), through a plain Instance so the analyzer sees no require cycle.
local glyphKit: any = nil

-- Draws the white line glyph `id` ("map", "settings"; "" clears it) centred in `slot`,
-- `size` px (default: the slot's width less 4). Replaces what the slot held; the slot's "Glyph" attribute names it.
function Ui.glyph(slot: GuiObject, id: string, size: number?)
	for _, child in slot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	slot:SetAttribute("Glyph", id)
	if id == "" then
		return
	end
	if glyphKit == nil then
		-- (found among the siblings by name: a module the analyzer cannot follow, so it reports no cycle)
		local found: ModuleScript? = nil
		for _, sibling in script.Parent:GetChildren() do
			if sibling:IsA("ModuleScript") and sibling.Name == "PhoneContract" then
				found = sibling
			end
		end
		local ok, kit = pcall(function(): any
			local module = found
			return if module then require(module) :: any else nil
		end)
		glyphKit = if ok and kit then kit else false
	end
	if glyphKit then
		glyphKit.glyph(slot, id, size or math.max(8, slot.Size.X.Offset - 4))
	end
end

export type HeadingOptions = {
	glyph: string?, -- the line glyph before the title (a PhoneContract id; "" or nil: none)
	brand: boolean?, -- the ZDC mark and a thin rule before it all (default true)
	textSize: number?, -- the title's type (default 20; the mark and the glyph follow it)
	height: number?, -- the line's height (default 30)
}
export type Heading = { frame: Frame, brand: Frame?, glyph: Frame, title: TextLabel }

-- One header line in the phone's look: [■ ZDC] | [glyph] TITLE (caps, DisplayFont), in a transparent Frame named
-- "Heading" across its parent (Size (1, 0, 0, height): the caller sets .Size / .Position). Ui.glyph(heading.glyph, id)
-- changes the glyph later; the title moves left when there is none. The title stays in caps.
function Ui.heading(parent: Instance, title: string, options: HeadingOptions?): Heading
	local o: HeadingOptions = options or {}
	local h = o.height or 30
	local textSize = o.textSize or 20
	local frame = Ui.make("Frame", { Name = "Heading", Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1 }, parent)
	local x = 0
	local brand: any = nil
	if o.brand ~= false then
		brand = Ui.brand(frame, math.max(14, textSize - 2), { Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5) })
		x = brand.Size.X.Offset + 10
		Ui.make("Frame", {
			Name = "Divider",
			Size = UDim2.fromOffset(1, math.floor(h * 0.7)),
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = K.rule,
			BorderSizePixel = 0,
		}, frame)
		x += 11
	end
	local glyphSize = math.floor(textSize * 1.2 + 0.5)
	local slot = Ui.make("Frame", {
		Name = "Glyph",
		Size = UDim2.fromOffset(glyphSize, glyphSize),
		Position = UDim2.new(0, x, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
	}, frame)
	local titleLabel = Ui.label(frame, title, UDim2.new(1, -x, 1, 0), {
		Name = "Title",
		Position = UDim2.fromOffset(x, 0),
		Font = Theme.DisplayFont,
		TextSize = textSize,
		TextColor3 = K.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	upperCase(titleLabel)
	-- The title after the glyph, or in its place when there is none.
	local function place()
		local id = slot:GetAttribute("Glyph")
		local has = type(id) == "string" and id ~= ""
		local at = if has then x + glyphSize + 10 else x
		slot.Visible = has
		titleLabel.Position = UDim2.fromOffset(at, 0)
		titleLabel.Size = UDim2.new(1, -at, 1, 0)
	end
	slot:GetAttributeChangedSignal("Glyph"):Connect(place)
	Ui.glyph(slot, o.glyph or "")
	place()
	return { frame = frame, brand = brand, glyph = slot, title = titleLabel }
end

-- ── The window ────────────────────────────────────────────────────────────

Ui.WindowHeader = 78 -- px at scale 1: the header over the content
Ui.WindowFooter = 40 -- px at scale 1: the footer under it

export type WindowOptions = {
	-- The header's line glyph (a PhoneContract id: "map", "settings"; "" for none). Default: the one that matches
	-- `icon` (Ui.glyphFor), which also follows a later chrome.icon.Text.
	glyph: string?,
	brand: boolean?, -- the ZDC mark at the left of the header (default true)
}

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
	heading: Heading, -- 5.8: the header line (brand, glyph, title)
	glyph: Frame, -- 5.8: the glyph slot (Ui.glyph(chrome.glyph, id) changes it)
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

-- A charcoal window: see the top of this file. `icon` (an emoji) is kept in a hidden badge for the callers that still
-- reach it (chrome.icon) and picks the header's line glyph (options.glyph overrides it).
function Ui.window(parent: Instance, title: string, subtitle: string, icon: string?, size: UDim2?, options: WindowOptions?): (any, any, WindowChrome)
	local o: WindowOptions = options or {}
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

	-- 5.8, the phone's header (one layout for every window): the ZDC mark, a thin rule, the line glyph and the title in
	-- caps; the subtitle in small caps under it; a thin line across; the square ✕ on the right.
	local headerH, footerH = Ui.WindowHeader, Ui.WindowFooter
	local header = Ui.make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, headerH), BackgroundTransparency = 1, BorderSizePixel = 0 }, surface)
	Ui.make("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -48, 0, 1),
		Position = UDim2.new(0, 24, 1, -1),
		BackgroundColor3 = K.rule,
		BorderSizePixel = 0,
	}, header)
	local badge = Ui.make("Frame", { Name = "Badge", Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1, Visible = false }, header)
	local iconObject = Ui.label(badge, icon or "", UDim2.fromOffset(24, 24), {
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = K.secondary,
	})
	local heading = Ui.heading(header, title, { glyph = o.glyph or Ui.glyphFor(icon), brand = o.brand, textSize = 20, height = 30 })
	heading.frame.Size = UDim2.new(1, -(24 + 64), 0, 30) -- (the ✕ and a gap on the right)
	heading.frame.Position = UDim2.fromOffset(24, 11)
	local titleLabel = heading.title
	-- The glyph follows the icon a caller sets later (chrome.icon.Text), unless options.glyph pinned it.
	if o.glyph == nil and iconObject:IsA("TextLabel") then
		local label = iconObject :: TextLabel
		label:GetPropertyChangedSignal("Text"):Connect(function()
			local id = Ui.glyphFor(label.Text)
			if id ~= "" and heading.glyph:GetAttribute("Glyph") ~= id then
				Ui.glyph(heading.glyph, id)
			end
		end)
	end
	local subtitleLabel = Ui.label(header, subtitle, UDim2.new(1, -(24 + 64), 0, 16), {
		Name = "Subtitle",
		Position = UDim2.fromOffset(24, 47),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	upperCase(subtitleLabel)

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
	close.Position = UDim2.new(1, -24, 0, 26) -- (on the heading's line, its right edge on the header's line end)
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
		heading = heading,
		glyph = heading.glyph,
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

-- ── Text ──────────────────────────────────────────────────────────────────

function Ui.money(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

function Ui.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Ui
