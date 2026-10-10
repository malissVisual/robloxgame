--!strict
-- 6.0.1: the courier phone's apps open in a centred popup over the game (the owner's wish: the phone never turns
-- sideways; what you tap in it opens in the middle of the screen). client/Phone.luau draws the app in it.
--   * The backdrop: the whole screen dimmed (a tap on it closes the app) and a light BlurEffect in Lighting, made and
--     removed here.
--   * The panel: a ZDC charcoal panel, 760 × 520 at the desktop scale (PhoneLayout.popup: at most 92 % × 86 % of the
--     screen; touch keeps full-size text and targets and scrolls), with Ui.window's header language (the ZDC mark,
--     a thin rule, the app's line glyph from PhoneContract, the title in caps, the square ✕) and the app's content
--     in a scrolling body under it.
--   * It grows from the tapped tile to the centre (0.2 s, Quad Out) and shrinks back to it on close; under reduced
--     motion it only fades (a veil of the panel's colour over it) and the blur comes at once.
-- The phone stays where it is under the backdrop, dimmed. Phone owns the keys (Q / ESC / B close the popup first).
--   PhonePopup.show(id, title, from?) -> (body, wide)   opens the popup from `from` (a screen point; nil: grows in
--       place), or gives the open one this app's header; the body is cleared. `wide`: room for two columns.
--   PhonePopup.hide(instant?)   closes it (back to where it came from). PhonePopup.isOpen().
--   PhonePopup.panel()   the open panel (a banner drops in it), PhonePopup.focus()   gamepad focus on its first action.
--   PhonePopup.refit() -> boolean   the screen resized: fits the panel again; true when `wide` changed.
--   PhonePopup.onClose   set by Phone: the ✕ or the backdrop was pressed.
--   6.17: PhonePopup.bar() -> (Frame?, width)   a strip in the header right of the title, emptied with the body on
--       every show (the JOBS app's chips: client/JobsView.luau), and its width; PhonePopup.room() -> number   the body's height (px at its
--       scale) inside its padding: what shows without scrolling.
-- Presentation only.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local PhoneLayout = require(script.Parent.PhoneLayout)
local PhoneMotion = require(script.Parent.PhoneMotion)

local K = Theme.Contract
local PhonePopup = {}

PhonePopup.onClose = nil :: (() -> ())?
PhonePopup.HEADER = 64 -- px at the panel's scale: the header over the body

local GROW = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE = TweenInfo.new(0.15, Enum.EasingStyle.Linear)
local DIM = 0.45 -- the backdrop's transparency at rest
local BLUR = 8 -- the blur's size at rest (low: the city stays readable behind it)
local SEED = 0.12 -- the panel's scale at the tile, a share of its own

type Shown = {
	id: string,
	wide: boolean,
	from: Vector2?,
	closing: boolean,
	backdrop: any,
	panel: any,
	scaler: any,
	veil: any,
	heading: any,
	close: any,
	body: any,
	blur: any,
	bar: any, -- 6.17
}

local shown: Shown? = nil
local BODY_PAD = 12 + 24 -- the body's padding, top and bottom (6.17: PhonePopup.room)

-- 6.17: the header's strip starts after the title (its words about 14 px a letter at 20 px caps) and ends before ✕.
local function placeBar(bar: any, heading: any, title: string)
	local titleX = heading.title.Position.X.Offset
	local left = 24 + titleX + (utf8.len(title) or #title) * 14 + 14
	bar.Position = UDim2.new(0, left, 0.5, 0)
	bar.Size = UDim2.new(1, -(left + 72), 0, 30)
	bar:SetAttribute("Left", left + 72)
end
local gui: ScreenGui? = nil

-- The popup's ScreenGui (over the phone and the HUD, with the windows).
local function screen(): ScreenGui
	local made = gui
	if made and made.Parent then
		return made
	end
	local fresh: ScreenGui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryPhoneApp",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui = fresh
	return fresh
end

-- The panel's size and scale for this screen.
local function layout(): PhoneLayout.Popup
	local size = Ui.screenSize()
	local touch = Ui.touchLayout()
	return PhoneLayout.popup(size.X, size.Y, touch, if touch then 1 else math.clamp(Ui.screenScale(), 0.85, 1.1))
end

local function tween(target: Instance, info: TweenInfo, goal: { [string]: any }, done: (() -> ())?)
	local made = TweenService:Create(target, info, goal)
	if done then
		made.Completed:Connect(function(state: Enum.PlaybackState)
			if state ~= Enum.PlaybackState.Cancelled then
				done()
			end
		end)
	end
	made:Play()
end

-- Where the panel grows from: `from` (a screen point) in the popup's own coordinates, else the centre.
local function origin(from: Vector2?): UDim2
	if not from then
		return UDim2.fromScale(0.5, 0.5)
	end
	local at = screen().AbsolutePosition
	return UDim2.fromOffset(from.X - at.X, from.Y - at.Y)
end

local function requestClose()
	local sound = Ui.onClick
	if sound then
		sound()
	end
	local cb = PhonePopup.onClose
	if cb then
		cb()
	else
		PhonePopup.hide()
	end
end

local function destroy(open: Shown)
	open.backdrop:Destroy()
	open.panel:Destroy()
	open.blur:Destroy()
end

local function build(id: string, title: string, from: Vector2?): Shown
	local made = screen()
	local fit = layout()
	-- (the backdrop reaches past the screen's edges, under Roblox's top bar too)
	local backdrop = Ui.make("TextButton", {
		Name = "Backdrop",
		Size = UDim2.new(1, 0, 1, 120),
		Position = UDim2.fromOffset(0, -60),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true, -- (the mouse is free while an app is open)
		ZIndex = 1,
	}, made)
	backdrop.Activated:Connect(requestClose)
	local panel = Ui.make("Frame", {
		Name = "AppPopup",
		Size = UDim2.fromOffset(fit.width, fit.height),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true, -- (clicks on the panel do not reach the backdrop or the world)
		ClipsDescendants = true, -- (a banner drops in from above its top edge)
		SelectionGroup = true, -- (the gamepad's selection stays in the app)
		ZIndex = 2,
	}, made)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, panel)
	local scaler = Ui.make("UIScale", { Scale = fit.scale }, panel)
	-- Ui.window's header: [■ ZDC] | [glyph] TITLE, the square ✕ on the right, a thin line under it.
	local headerH = PhonePopup.HEADER
	local header = Ui.make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, headerH), BackgroundTransparency = 1 }, panel)
	local heading = Ui.heading(header, title, { glyph = id, textSize = 20, height = 30 })
	heading.frame.Size = UDim2.new(1, -(24 + 64), 0, 30)
	heading.frame.Position = UDim2.fromOffset(24, (headerH - 30) / 2)
	local bar = Ui.make("Frame", { Name = "HeaderBar", AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, ZIndex = 3 }, header)
	placeBar(bar, heading, title)
	local close = Ui.closeButton(header, requestClose)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -16, 0, headerH / 2)
	Ui.make("Frame", { Name = "Line", Size = UDim2.new(1, -48, 0, 1), Position = UDim2.new(0, 24, 1, -1), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, header)
	local body = Ui.make("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -headerH),
		Position = UDim2.fromOffset(0, headerH),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.line,
		ScrollBarImageTransparency = 0.3,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ClipsDescendants = true,
	}, panel)
	Ui.list(body, true, 8)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 24) }, body)
	-- The veil: the panel's colour over its content while it grows, shrinks or fades.
	local veil = Ui.make("Frame", { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.charcoal, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 50 }, panel)
	local blur = Ui.make("BlurEffect", { Name = "PhoneAppBlur", Size = 0 }, Lighting)
	return {
		id = id,
		wide = fit.wide,
		from = from,
		closing = false,
		backdrop = backdrop,
		panel = panel,
		scaler = scaler,
		veil = veil,
		heading = heading,
		close = close,
		body = body,
		blur = blur,
		bar = bar,
	}
end

-- In: grows from the tile to the centre (or fades in under reduced motion), the backdrop dims, the blur comes.
local function enter(open: Shown)
	local rest = open.scaler.Scale
	local veil = open.veil
	veil.Visible = true
	local function unveil()
		if not open.closing then
			veil.Visible = false
		end
	end
	if PhoneMotion.reducedMotion() then
		open.blur.Size = BLUR
		veil.BackgroundTransparency = 0
		tween(open.backdrop, FADE, { BackgroundTransparency = DIM })
		tween(veil, FADE, { BackgroundTransparency = 1 }, unveil)
		return
	end
	open.panel.Position = origin(open.from)
	open.scaler.Scale = rest * (if open.from then SEED else 0.9)
	veil.BackgroundTransparency = 0.15
	tween(open.backdrop, GROW, { BackgroundTransparency = DIM })
	tween(open.blur, GROW, { Size = BLUR })
	tween(open.scaler, GROW, { Scale = rest })
	tween(veil, GROW, { BackgroundTransparency = 1 }, unveil)
	tween(open.panel, GROW, { Position = UDim2.fromScale(0.5, 0.5) })
end

function PhonePopup.isOpen(): boolean
	return shown ~= nil
end

function PhonePopup.show(id: string, title: string, from: Vector2?): (ScrollingFrame, boolean)
	local open = shown
	if open == nil then
		local fresh = build(id, title, from)
		shown = fresh
		enter(fresh)
		return fresh.body, fresh.wide
	end
	if open.id ~= id then
		-- (another app in the open popup: its header; the panel stays where it is)
		open.id = id
		open.heading.title.Text = title
		Ui.glyph(open.heading.glyph, id)
		placeBar(open.bar, open.heading, title)
	end
	Ui.clear(open.bar)
	Ui.clear(open.body)
	open.body.CanvasPosition = Vector2.zero
	return open.body, open.wide
end

function PhonePopup.hide(instant: boolean?)
	local open = shown
	if not open then
		return
	end
	shown = nil
	open.closing = true
	Ui.gamepadRelease(open.panel)
	open.backdrop.Modal = false
	if instant then
		destroy(open)
		return
	end
	local veil = open.veil
	veil.Visible = true
	local function gone()
		destroy(open)
	end
	if PhoneMotion.reducedMotion() then
		open.blur.Size = 0
		tween(open.backdrop, FADE, { BackgroundTransparency = 1 })
		tween(veil, FADE, { BackgroundTransparency = 0 }, gone)
		return
	end
	tween(open.backdrop, SHRINK, { BackgroundTransparency = 1 })
	tween(open.blur, SHRINK, { Size = 0 })
	tween(veil, SHRINK, { BackgroundTransparency = 0.15 })
	tween(open.scaler, SHRINK, { Scale = open.scaler.Scale * (if open.from then SEED else 0.9) })
	tween(open.panel, SHRINK, { Position = origin(open.from) }, gone)
end

-- The open panel (nil when closed): a banner drops into it.
function PhonePopup.panel(): GuiObject?
	local open = shown
	return if open then open.panel else nil
end

-- 6.17: the header's strip for the open app (nil when closed) and its width (px at the panel's scale). See the header.
function PhonePopup.bar(): (Frame?, number)
	local open = shown
	if not open then
		return nil, 0
	end
	return open.bar, layout().width - (tonumber(open.bar:GetAttribute("Left")) or 0)
end

-- 6.17: what shows of the body without scrolling (px at the panel's scale).
function PhonePopup.room(): number
	return layout().height - PhonePopup.HEADER - BODY_PAD
end

-- The gamepad's selection on the app's first action (by layout order), else on the ✕.
function PhonePopup.focus()
	local open = shown
	if not open then
		return
	end
	local function first(node: Instance): GuiObject?
		local children = node:GetChildren()
		table.sort(children, function(a: Instance, b: Instance): boolean
			local x = if a:IsA("GuiObject") then a.LayoutOrder or 0 else 0
			local y = if b:IsA("GuiObject") then b.LayoutOrder or 0 else 0
			return x < y
		end)
		for _, child in children do
			if child:IsA("GuiObject") and child.Visible then
				if (child:IsA("TextButton") or child:IsA("ImageButton")) and child.Selectable ~= false then
					return child
				end
				local found = first(child)
				if found then
					return found
				end
			end
		end
		return nil
	end
	Ui.gamepadFocus(first(open.body) or open.close)
end

-- The screen resized: the panel fits it again. True when two columns came or went (the app is drawn again).
function PhonePopup.refit(): boolean
	local open = shown
	if not open then
		return false
	end
	local fit = layout()
	open.panel.Size = UDim2.fromOffset(fit.width, fit.height)
	open.scaler.Scale = fit.scale
	local changed = open.wide ~= fit.wide
	open.wide = fit.wide
	return changed
end

return PhonePopup
