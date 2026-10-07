--!strict
-- 3.8, the HUD's contract look (design/ui-contract/, approved by the owner): the colours and the small presentation
-- pieces client/Hud.luau builds its groups from. Presentation only: no game state lives here.
--
-- The look: compact white type over the world, a localized charcoal scrim (or a text stroke) wherever the scene could
-- be bright, flat square shapes, fine grey lines and small precise red accents (the contract marker, the destination,
-- urgent states). Success and damage keep their meaning (good / warn), always with a word or an icon too.
--
-- Hud requires this module as its palette `P` (Hud.luau sits at the 200-register limit: one local for both), so the
-- colour names below are the ones Hud's code reads:
--   ink, ink2          the main and the supporting text (Theme.Contract text / secondary)
--   line               fine separators and outlines (use with lineAlpha)
--   danger, good, warn the semantic states (danger is the contract red)
--   accent             a quiet highlight: a full bar, a selected value (white)
--   surface, raised    the charcoal backing of a group or a window row, and a hovered / selected row
--   scrimAlpha, lineAlpha  the transparencies of the charcoal backing and of the fine lines
--
-- The pieces (all flat, square, no bounce; hover 120 ms, press a brief opacity dip):
--   P.text(parent, text, size, props?)        white text with a faint charcoal stroke (it reads over daylight)
--   P.caps(parent, text, size, props?)        small caps metadata (HeadingFont 12, the secondary text)
--   P.scrim(parent, fade?)                    a charcoal backing behind a text group, fading out to the right
--   P.rule(parent, size, props?)              a 1 px separator
--   P.marker(parent, size?, props?)           the small red square of the contract label
--   P.bar(parent, size, color)                (back, fill): a thin square bar on a faint track
--   P.keyBox(parent, key, size, props?)       a key in a square outline ("E", "J", "Q")
--   P.action(parent, text, props?, onClick?)  a quiet text action: hover brightens it and draws a thin red underline
--   P.dot(parent)                             the small red badge dot (Name "Badge", a count in it)
--   P.button(parent, text, size, kind, onClick) a window action: "main" (light face), "primary" (5.8: the phone's red
--                                             face, white caps, square), "quiet" (outline), "off"
--   P.row(parent, height, order, selected?)   a slim charcoal window row; selected: raised with a narrow red rule
--   P.tag(parent, text, color?)               a small outlined caps tag (EXCLUSIVE, REWARD)
--   P.fade(object, visible, seconds?)         fades a CanvasGroup in or out (no movement)
--   P.hex(color)                              a colour for RichText

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local K = Theme.Contract

local HudContract = {
	ink = K.text,
	ink2 = K.secondary,
	line = K.line,
	danger = K.red,
	red = K.red,
	good = K.good,
	warn = K.warn,
	accent = K.text,
	surface = K.charcoal,
	raised = K.raised,
	scrimAlpha = K.scrim,
	lineAlpha = K.lineAlpha,
	stroke = 0.62, -- the text stroke's transparency over the world
}
local P = HudContract

local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function apply(object: any, props: { [string]: any }?)
	if props then
		for key, value in props do
			object[key] = value
		end
	end
	return object
end

local function clickSound()
	local sound = Ui.onClick
	if sound then
		sound()
	end
end

-- White text with a faint charcoal stroke: it stays readable over a white wall in daylight.
function HudContract.text(parent: Instance, text: string, size: UDim2, props: { [string]: any }?): any
	local label = Ui.label(parent, text, size, {
		Font = Theme.Font,
		TextSize = 15,
		TextColor3 = P.ink,
		TextStrokeColor3 = P.surface,
		TextStrokeTransparency = P.stroke,
		TextWrapped = false,
	})
	return apply(label, props)
end

-- Small caps metadata: the names of things, units, keys.
function HudContract.caps(parent: Instance, text: string, size: UDim2, props: { [string]: any }?): any
	local label = HudContract.text(parent, string.upper(text), size, {
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return apply(label, props)
end

-- A localized charcoal backing behind a text group: solid-ish on the left, gone on the right (`fade` 0 – 1: where it
-- starts to fade). It fills its parent and sits under the parent's children (ZIndex 0).
function HudContract.scrim(parent: Instance, fade: number?, props: { [string]: any }?): any
	local frame = Ui.make("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, parent)
	local from = fade or 0.55
	Ui.make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, P.scrimAlpha),
			NumberSequenceKeypoint.new(math.clamp(from, 0.01, 0.98), P.scrimAlpha + (1 - P.scrimAlpha) * 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, frame)
	return apply(frame, props)
end

-- A fine separator line.
function HudContract.rule(parent: Instance, size: UDim2, props: { [string]: any }?): any
	local line = Ui.make("Frame", {
		Name = "Rule",
		Size = size,
		BackgroundColor3 = P.line,
		BackgroundTransparency = P.lineAlpha,
		BorderSizePixel = 0,
	}, parent)
	return apply(line, props)
end

-- The small red square of the contract label.
function HudContract.marker(parent: Instance, size: number?, props: { [string]: any }?): any
	local s = size or 8
	local square = Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = P.red,
		BorderSizePixel = 0,
	}, parent)
	return apply(square, props)
end

-- A thin square bar: `color` on a faint line-coloured track.
function HudContract.bar(parent: Instance, size: UDim2, color: Color3): (any, any)
	local back = Ui.make("Frame", { Name = "Bar", Size = size, BackgroundColor3 = P.line, BackgroundTransparency = 0.62, BorderSizePixel = 0 }, parent)
	local fill = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	return back, fill
end

-- A key in a square outline: the contextual action's E, the J of the board, the Q of the guns.
function HudContract.keyBox(parent: Instance, key: string, size: number, props: { [string]: any }?): any
	local box = Ui.label(parent, key, UDim2.fromOffset(size, size), {
		Name = "Key",
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.45,
		Font = Theme.HeadingFont,
		TextSize = math.max(11, math.floor(size * 0.45)),
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	Ui.make("UIStroke", { Name = "Outline", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.ink, Thickness = 1, Transparency = 0.15 }, box)
	return apply(box, props)
end

-- Hover and press for any button: hover brightens `label` (the button's own text by default) to white and shows the
-- thin red `underline` (100 – 140 ms); a press dips the opacity briefly. Keyboard / gamepad focus does the same.
function HudContract.hover(button: GuiButton, underline: GuiObject?, label: any?)
	local target: any = label or button
	local rest: Color3 = target.TextColor3
	button:SetAttribute("RestColor", rest)
	local playing: { Tween } = {}
	local function play(tween: Tween)
		table.insert(playing, tween)
		tween:Play()
	end
	local function to(on: boolean)
		for _, tween in playing do
			tween:Cancel()
		end
		table.clear(playing)
		local resting = button:GetAttribute("RestColor")
		play(TweenService:Create(target, HOVER, { TextColor3 = if on then P.ink elseif typeof(resting) == "Color3" then resting else rest }))
		if underline then
			play(TweenService:Create(underline, HOVER, { BackgroundTransparency = if on then 0 else 1 }))
		end
	end
	button.MouseEnter:Connect(function()
		to(true)
	end)
	button.MouseLeave:Connect(function()
		to(false)
	end)
	button.SelectionGained:Connect(function()
		to(true)
	end)
	button.SelectionLost:Connect(function()
		to(false)
	end)
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(target, PRESS, { TextTransparency = 0.35 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(target, HOVER, { TextTransparency = 0 }):Play()
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			to(false)
		end
	end)
	button.Destroying:Connect(function()
		for _, tween in playing do
			tween:Cancel()
		end
	end)
end

-- A quiet text action ("MAP [M]"): caps in the secondary white, at least 44 px tall (a finger), hover brightens it and
-- draws a thin red line under it. props go to the button (Size, Position, LayoutOrder ...). onClick plays the click.
function HudContract.action(parent: Instance, text: string, props: { [string]: any }?, onClick: (() -> ())?): any
	local button = Ui.make("TextButton", {
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = text,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = P.ink2,
		TextStrokeColor3 = P.surface,
		TextStrokeTransparency = P.stroke,
		TextWrapped = false,
	}, parent)
	apply(button, props)
	local underline = Ui.make("Frame", {
		Name = "Underline",
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0.5, 11),
		BackgroundColor3 = P.red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, button)
	HudContract.hover(button, underline)
	if onClick then
		button.Activated:Connect(function()
			clickSound()
			onClick()
		end)
	end
	return button
end

-- The small red badge dot on an action or a menu entry (Hud.setBadge fills its count, hides it at 0).
function HudContract.dot(parent: Instance, props: { [string]: any }?): any
	local badge = Ui.make("TextLabel", {
		Name = "Badge",
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 4, 0.5, -9),
		BackgroundColor3 = P.red,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = P.ink,
		Font = Theme.HeadingFont,
		TextSize = 10,
		Visible = false,
		ZIndex = 8,
	}, parent)
	return apply(badge, props)
end

export type ButtonKind = "main" | "primary" | "quiet" | "off"

-- A window action, rectangular: "main" a light face with charcoal text (the one clear action), "primary" (5.8) the
-- courier phone's red action (a Contract.red face, white caps, square; also a text set later), "quiet" an outline
-- with light text, "off" a dim face (locked / not now: its words say why). Hover: a red edge marker on the left (a
-- white one on the red face, which also brightens) and the text brightens; press: a brief opacity dip. At least 44 px
-- tall where it is used on touch.
function HudContract.button(parent: Instance, text: string, size: UDim2, kind: ButtonKind, onClick: () -> ()): any
	local main = kind == "main"
	local primary = kind == "primary"
	local off = kind == "off"
	local button = Ui.make("TextButton", {
		Size = size,
		BackgroundColor3 = if primary then P.red elseif main then P.ink else P.raised,
		BackgroundTransparency = if main or primary then 0 elseif off then 0.4 else 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = if primary then string.upper(text) else text,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = if primary then P.ink elseif main then P.surface elseif off then P.ink2 else P.ink,
		TextTransparency = if off then 0.25 else 0,
		TextWrapped = true,
	}, parent)
	button:SetAttribute("Kind", kind)
	if primary then
		button:GetPropertyChangedSignal("Text"):Connect(function()
			local upper = string.upper(button.Text)
			if upper ~= button.Text and not button.RichText then
				button.Text = upper
			end
		end)
	end
	if not main and not primary then
		Ui.make("UIStroke", { Name = "Outline", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = if off then 0.75 else P.lineAlpha }, button)
	end
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, button)
	local edge = Ui.make("Frame", {
		Name = "Edge",
		Size = UDim2.new(0, 2, 1, 0),
		Position = UDim2.new(0, -10, 0, 0),
		BackgroundColor3 = if primary then P.ink else P.red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, button)
	if not off then
		local playing: Tween? = nil
		local function to(on: boolean)
			if playing then
				playing:Cancel()
			end
			local tween = TweenService:Create(edge, HOVER, { BackgroundTransparency = if on then 0 else 1 })
			playing = tween
			tween:Play()
			if primary then
				button.BackgroundColor3 = if on then P.red:Lerp(P.ink, 0.1) else P.red
			elseif not main then
				button.BackgroundTransparency = if on then 0.2 else 1
			end
		end
		button.MouseEnter:Connect(function()
			to(true)
		end)
		button.MouseLeave:Connect(function()
			to(false)
		end)
		button.SelectionGained:Connect(function()
			to(true)
		end)
		button.SelectionLost:Connect(function()
			to(false)
		end)
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				TweenService:Create(button, PRESS, { TextTransparency = 0.35 }):Play()
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				TweenService:Create(button, HOVER, { TextTransparency = 0 }):Play()
			end
		end)
	end
	button.Activated:Connect(function()
		clickSound()
		onClick()
	end)
	return button
end

-- A slim window row: charcoal raised a little over the window; `selected` (the one that matters here) a quiet
-- highlight and a narrow red rule on its left.
function HudContract.row(parent: Instance, height: number, order: number, selected: boolean?): any
	local frame = Ui.make("Frame", {
		Name = "Row",
		Size = UDim2.new(1, -12, 0, height),
		BackgroundColor3 = if selected then P.raised else P.surface,
		BackgroundTransparency = if selected then 0 else 0.25,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Ui.make("UIStroke", { Name = "Outline", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = if selected then 0.5 else 0.8 }, frame)
	if selected then
		Ui.make("Frame", { Name = "Selected", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = P.red, BorderSizePixel = 0, ZIndex = 2 }, frame)
	end
	return frame
end

-- A small outlined caps tag (EXCLUSIVE, REWARD): the text and its outline in `color` (default the secondary white).
function HudContract.tag(parent: Instance, text: string, color: Color3?): any
	local tint = color or P.ink2
	local tag = Ui.label(parent, string.upper(text), UDim2.fromOffset(0, 18), {
		Name = "Tag",
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.2,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = tint,
		TextWrapped = false,
	})
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = tint, Thickness = 1, Transparency = 0.4 }, tag)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, tag)
	return tag
end

-- Fades a CanvasGroup in or out (opacity only: nothing moves or bounces).
function HudContract.fade(group: CanvasGroup, visible: boolean, seconds: number?)
	if visible then
		group.Visible = true
	end
	local tween = TweenService:Create(group, TweenInfo.new(seconds or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = if visible then 0 else 1 })
	if not visible then
		tween.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and group.GroupTransparency >= 0.99 then
				group.Visible = false
			end
		end)
	end
	tween:Play()
end

-- A colour for RichText.
function HudContract.hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

return HudContract
