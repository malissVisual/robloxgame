--!strict
-- 6.7, the tour's arrow (the owner: "It should simply show with an arrow where things are in the menu"): a big red
-- arrow pointing at one thing on the screen, a pulsing red frame round that thing and a one-line caption box beside
-- the arrow with NEXT › and SKIP TUTORIAL. client/TutorialUi.luau drives the tour (the stops: shared/TutorialSteps.luau
-- ScreenTour); this module only draws, follows and takes NEXT / SKIP.
--
--   * Never in the way: no dim and no modal panel, the game runs on (you walk while it shows). Only the caption's
--     buttons take clicks; the arrow and the frame let them through to what is under them.
--   * It follows its target every frame (RenderStepped while it shows): the target's AbsolutePosition and
--     AbsoluteSize, in this ScreenGui's space (the HUD and the phone have the same insets; their origins are taken off),
--     so a phone sliding in or a HUD laid out again keeps the arrow on it. It bounces toward it
--     (Config.Tutorial.TourBounce, TourBounceSpeed). Where the arrow and the caption sit (the stop's side, or the side
--     with room) is TutorialSteps.placeArrow (pure, tested).
--   * The target is found by Point.find a few times a second while it is gone (by name: no tree walks a frame);
--     hidden (its ScreenGui off, a parent not Visible) or off the screen, the arrow and the frame hide and the caption
--     waits at the top centre, so NEXT and SKIP are always there.
--   * Keys: Enter (and a gamepad's A) is NEXT, not Space (you can still jump); a gamepad's selection sits on NEXT. A
--     touch screen taps (the caption a finger tall, at least 0.8 of its size).
--   * Drawn with frames (nothing to upload): a shaft and a chevron head in the ZDC red over a charcoal outline, drawn
--     pointing down and turned by Rotation for the other three directions.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local TutorialSteps = require(Shared.TutorialSteps)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local TutorialArrow = {}

-- One stop of the tour on screen.
export type Point = {
	find: () -> GuiObject?, -- the target (asked again a few times a second while it is gone)
	text: string, -- the caption (one sentence)
	side: string, -- left / right / above / below the target (TutorialSteps.placeArrow)
	step: number,
	count: number,
	next: string, -- the red action's words ("NEXT ›")
	skip: string, -- the quiet action's words ("SKIP TUTORIAL")
	onNext: () -> (),
	onSkip: () -> (),
}

local K = Theme.Contract
local Tuning = Config.Tutorial
local TOUCH = Ui.touchLayout()
local ARROW_W, ARROW_L = 56, 76 -- the arrow's box (unscaled), drawn pointing down
local THICK, HEAD = 13, 36 -- the bars' thickness, the head's bars' length
local OUTLINE = 3 -- the charcoal round the red
local RING_PAD = 5 -- the frame round the target, px outside it
local ACTION_H = if TOUCH then 48 else 36
local ACTION = "TutorialTourNext"
local LOOK_EVERY = 0.25 -- seconds between two looks for the target (and the screen's scale)
local GUARD = 0.35 -- seconds after a stop shows before a key turns it (a key held from the last one)

local player = Players.LocalPlayer
local refs: any = {} -- the instances (one table: few locals)
local current: Point? = nil
local target: GuiObject? = nil
local targetShown = false
local nextLook = 0
local shownAt = 0
local scale = 1
local frameConn: RBXScriptConnection? = nil
local bound = false

-- ── Building ───────────────────────────────────────────────────────────────

-- A bar of the arrow: centred at (cx, cy) in the arrow's box, turned by `rotation`.
local function bar(parent: Instance, color: Color3, w: number, h: number, cx: number, cy: number, rotation: number, z: number)
	Ui.make("Frame", {
		Size = UDim2.fromOffset(w, h),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Rotation = rotation,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
end

-- The arrow pointing down: the tip at the bottom centre, a shaft down to it and two bars meeting there (the chevron);
-- every bar twice, charcoal and a little bigger under the red (an outline without strokes crossing inside).
local function buildArrow(gui: Instance)
	local arrow = Ui.make("Frame", {
		Name = "Arrow",
		Size = UDim2.fromOffset(ARROW_W, ARROW_L),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
	}, gui)
	refs.arrowScale = Ui.make("UIScale", {}, arrow)
	local tipX, tipY = ARROW_W / 2, ARROW_L - OUTLINE - THICK / 2
	local reach = HEAD * math.sqrt(0.5) -- how far a head bar reaches back (and to the side) from the tip
	local shaftTop, shaftBottom = OUTLINE, tipY - THICK / 2
	for layer = 1, 2 do
		local grow = if layer == 1 then OUTLINE * 2 else 0
		local color = if layer == 1 then K.charcoal else K.red
		bar(arrow, color, THICK + grow, shaftBottom - shaftTop + grow, tipX, (shaftTop + shaftBottom) / 2, 0, layer + 2)
		bar(arrow, color, THICK + grow, HEAD + grow, tipX - reach / 2, tipY - reach / 2, -45, layer + 2)
		bar(arrow, color, THICK + grow, HEAD + grow, tipX + reach / 2, tipY - reach / 2, 45, layer + 2)
	end
	refs.arrow = arrow
end

local function sound()
	local click = Ui.onClick
	if click then
		click()
	end
end

-- The caption: a charcoal box with a red left edge, MARGE · 3 / 8 in small caps, the line, then SKIP TUTORIAL (a quiet
-- text action) and NEXT › (the phone's red primary) with its key.
local function buildCaption(gui: Instance)
	local box = Ui.make("Frame", {
		Name = "Caption",
		Size = UDim2.fromOffset(Tuning.TourCaptionWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Active = true, -- (a click on it stays here)
		ZIndex = 5,
	}, gui)
	refs.boxScale = Ui.make("UIScale", {}, box)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, box)
	Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 6 }, box)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 6 }, box)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6) }, body)
	Ui.list(body, true, 6)
	refs.step = Ui.label(body, "", UDim2.new(1, 0, 0, 14), {
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
		LayoutOrder = 1,
		ZIndex = 6,
	})
	refs.text = Ui.label(body, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 17,
		LineHeight = 1.1,
		TextColor3 = K.text,
		LayoutOrder = 2,
		ZIndex = 6,
	})
	local footer = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, 0, 0, ACTION_H), BackgroundTransparency = 1, LayoutOrder = 3, ZIndex = 6 }, body)
	local skip = Ui.make("TextButton", {
		Name = "Skip",
		Size = UDim2.fromOffset(0, ACTION_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		ZIndex = 7,
	}, footer)
	skip.MouseEnter:Connect(function()
		skip.TextColor3 = K.text
	end)
	skip.MouseLeave:Connect(function()
		skip.TextColor3 = K.secondary
	end)
	skip.Activated:Connect(function()
		local point = current
		if point then
			sound()
			point.onSkip()
		end
	end)
	local right = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, footer)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, right)
	Ui.label(right, if TOUCH then "" else "ENTER", UDim2.fromOffset(0, ACTION_H), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
		Visible = not TOUCH,
		LayoutOrder = 1,
		ZIndex = 7,
	})
	local nextButton = Ui.make("TextButton", {
		Name = "Next",
		Size = UDim2.fromOffset(0, ACTION_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.text,
		LayoutOrder = 2,
		ZIndex = 7,
	}, right)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, nextButton)
	local function lit(on: boolean)
		nextButton.BackgroundColor3 = if on then K.red:Lerp(K.text, 0.1) else K.red
	end
	nextButton.MouseEnter:Connect(function() lit(true) end)
	nextButton.MouseLeave:Connect(function() lit(false) end)
	nextButton.SelectionGained:Connect(function() lit(true) end)
	nextButton.SelectionLost:Connect(function() lit(false) end)
	nextButton.Activated:Connect(function()
		local point = current
		if point then
			sound()
			point.onNext()
		end
	end)
	refs.skip = skip
	refs.next = nextButton
	refs.box = box
end

local function build()
	if refs.gui then
		return
	end
	local gui = Ui.make("ScreenGui", {
		Name = "TutorialTour",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- (like the HUD and the phone)
		DisplayOrder = 8, -- over the HUD, the phone and its popup (3), Marge's dialog (6)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	local ring = Ui.make("Frame", { Name = "Ring", BackgroundTransparency = 1, Visible = false, ZIndex = 1 }, gui)
	Ui.corner(ring, 6)
	refs.ringStroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.red, Thickness = 3 }, ring)
	refs.ring = ring
	buildArrow(gui)
	buildCaption(gui)
	refs.gui = gui
end

-- ── Following ──────────────────────────────────────────────────────────────

-- Is `object` on screen: every GuiObject up to its ScreenGui Visible, the ScreenGui on?
local function onScreen(object: GuiObject): boolean
	local node: Instance? = object
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

-- A few times a second: the target again while it is gone, whether it shows, and the screen's scale.
local function look(now: number)
	if now < nextLook then
		return
	end
	nextLook = now + LOOK_EVERY
	local point = current
	if not point then
		return
	end
	local found = target
	if not found or not found.Parent then
		local ok, result = pcall(point.find)
		found = if ok then result else nil
		target = found
	end
	targetShown = found ~= nil and onScreen(found)
	local s = Ui.screenScale()
	if TOUCH then
		-- (like Marge's dialog: readable on a phone, never wider than the screen)
		s = math.min(math.max(s, 0.8), (Ui.screenSize().X - 32) / Tuning.TourCaptionWidth)
	end
	if math.abs(s - scale) > 0.001 then
		scale = s
		refs.boxScale.Scale = s
		refs.arrowScale.Scale = s
	end
end

local function update()
	local point = current
	local gui = refs.gui
	if not point or not gui then
		return
	end
	local now = os.clock()
	look(now)
	local origin, screen = gui.AbsolutePosition, gui.AbsoluteSize
	local box, arrow, ring = refs.box, refs.arrow, refs.ring
	local boxSize = box.AbsoluteSize
	local rect: { x: number, y: number, w: number, h: number }? = nil
	local found = target
	if found and targetShown then
		local at, size = found.AbsolutePosition, found.AbsoluteSize
		local x, y = at.X - origin.X, at.Y - origin.Y
		if size.X > 1 and size.Y > 1 and x + size.X > 0 and y + size.Y > 0 and x < screen.X and y < screen.Y then
			rect = { x = x, y = y, w = size.X, h = size.Y }
		end
	end
	if not rect then
		-- Nothing to point at now: the caption waits at the top centre.
		arrow.Visible = false
		ring.Visible = false
		box.Position = UDim2.fromOffset(math.floor((screen.X - boxSize.X) / 2), math.floor(screen.Y * 0.16))
		return
	end
	local place = TutorialSteps.placeArrow({
		target = rect,
		screen = { w = screen.X, h = screen.Y },
		side = point.side,
		length = ARROW_L * scale,
		travel = Tuning.TourBounce * scale,
		gap = Tuning.TourGap * scale,
		caption = { w = boxSize.X, h = boxSize.Y },
	})
	local wave = 0.5 + 0.5 * math.sin((now - shownAt) * Tuning.TourBounceSpeed * 2 * math.pi)
	local back = (1 - wave) * Tuning.TourBounce * scale -- (it starts against the target)
	arrow.Position = UDim2.fromOffset(place.arrowX - place.dirX * back, place.arrowY - place.dirY * back)
	arrow.Rotation = place.rotation
	arrow.Visible = true
	ring.Position = UDim2.fromOffset(rect.x - RING_PAD, rect.y - RING_PAD)
	ring.Size = UDim2.fromOffset(rect.w + RING_PAD * 2, rect.h + RING_PAD * 2)
	ring.Visible = true
	refs.ringStroke.Transparency = 0.1 + 0.45 * (1 - wave)
	box.Position = UDim2.fromOffset(math.floor(place.captionX + 0.5), math.floor(place.captionY + 0.5))
end

-- ── Keys ───────────────────────────────────────────────────────────────────

-- Enter / a gamepad's A: NEXT (A over a selected button presses that button: the selection sits on NEXT).
local function onKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local point = current
	if not point or UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	if input.KeyCode == Enum.KeyCode.ButtonA and GuiService.SelectedObject ~= nil then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin and os.clock() - shownAt > GUARD then
		task.spawn(point.onNext)
	end
	return Enum.ContextActionResult.Sink
end

local function bind(on: boolean)
	if on == bound then
		return
	end
	bound = on
	if on then
		-- (under client/DialogKeys.luau's priority: a dialog that opens over the tour takes the keys first)
		ContextActionService:BindActionAtPriority(ACTION, onKey, false, Enum.ContextActionPriority.High.Value + 5, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonA)
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

-- ── API ────────────────────────────────────────────────────────────────────

-- Points at a new stop (the last one's arrow goes).
function TutorialArrow.show(point: Point)
	build()
	current = point
	target = nil
	targetShown = false
	nextLook = 0
	shownAt = os.clock()
	refs.step.Text = string.upper(`{Tuning.NpcName} · {point.step} / {point.count}`)
	refs.text.Text = point.text
	refs.next.Text = point.next
	refs.skip.Text = point.skip
	refs.gui.Enabled = true
	bind(true)
	if not frameConn then
		frameConn = RunService.RenderStepped:Connect(function()
			local ok, err = pcall(function()
				update()
			end)
			if not ok then
				warn(`[TutorialArrow] {err}`)
				TutorialArrow.hide()
			end
		end)
	end
	update()
	TutorialArrow.focus()
end

-- A gamepad's selection back on NEXT (the phone that opens puts it on its first tile).
function TutorialArrow.focus()
	if current and refs.next then
		Ui.gamepadFocus(refs.next)
	end
end

-- The tour is over: nothing of it stays on screen.
function TutorialArrow.hide()
	current = nil
	target = nil
	bind(false)
	local conn = frameConn
	frameConn = nil
	if conn then
		conn:Disconnect()
	end
	local gui = refs.gui
	if gui then
		Ui.gamepadRelease(gui)
		gui.Enabled = false
		refs.arrow.Visible = false
		refs.ring.Visible = false
	end
end

function TutorialArrow.isShown(): boolean
	return current ~= nil
end

return TutorialArrow
