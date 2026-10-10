--!strict
-- 6.18, the UI kit (the owner, after 6.17's JOBS: "I need it unified so the phone looks like that, and the other popups
-- too"). The look of JOBS (client/JobsView.luau) as parts every popup and the phone's home draw with; the rules are in
-- design/ui-kit/README.md, the sizes in Config.UiKit, the pure maths in shared/CardLayout.luau:
--   * dark charcoal cards, a big picture or icon, ONE big number an item (money green, gold for something special),
--     coloured danger / state accents, almost no text: the details come on a tap;
--   * CardKit.hero(parent, spec)       the big card: a picture filling it, a ribbon and a corner chip on top, ⓘ, and at
--                                      its foot over a shade the title (+ a tag), the big value, one facts line, a bar
--                                      and one big button; spec.button makes the whole card a button (the phone's home)
--   * CardKit.row(parent, spec)        a compact row: an accent edge, a thumb (picture, emoji or app glyph), a tag (the
--                                      danger stars), the name, one tiny facts line, the big value and one round action
--                                      ("+", "›") or a lock's short words; a badge; the row's tap opens its details
--   * CardKit.chip(parent, spec)       a small rounded chip (the header's secondary state: YOUR RUN, NEXT UP, rush hour)
--   * CardKit.bigButton(parent, spec)  the one primary button of a screen (red; gold for a special; green; grey shut)
--   * CardKit.sectionHeader(parent, spec)  "7 MORE JOBS" with a chip at its right (ADD ALL · $X)
--   * CardKit.columns(list, spec)      the hero on the left beside the rows (a body CardLayout.side wide), else stacked
--   * CardKit.details(list, look, spec) a tap-for-details sub-view: "‹ BACK" (‹ JOBS) and what it draws
--   * CardKit.Color / CardKit.Danger   the palette: money green, gold, the danger tiers, dim and faint words, the run's
--                                      and rush hour's chips
-- Presentation only: every action keeps its caller's server path.
-- 6.18 wave 2 (additive, for the SHOP, BAG, GARAGE and STYLE windows): a Picture's `icon` (a shared/Icons.luau name: its
-- uploaded white silhouette drawn whole, not cropped; a hero's as its mark at the right); a row's action may be a short
-- word ("BUY", "USE", "WEAR": a pill sized to it); CardKit.tabs, a row of tab chips (Tab_<id>, the open one lit with its
-- red Underline).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CardLayout = require(Shared.CardLayout)
local Icons = require(Shared.Icons)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local K = Theme.Contract
local KIT = Config.UiKit
local CardKit = {}

CardKit.Layout = CardLayout

CardKit.Color = {
	money = Color3.fromRGB(111, 227, 138), -- a pay, money you get: the big value
	gold = Color3.fromRGB(242, 201, 76), -- something special (a golden order): its value, ribbon and button
	goldInk = Color3.fromRGB(42, 30, 5), -- the words on gold
	dim = Color3.fromRGB(125, 131, 139), -- a locked item's value
	faint = Color3.fromRGB(142, 148, 156), -- a row's facts line
	shade = Color3.fromRGB(14, 13, 11), -- the hero's shade under its words
	grey = Color3.fromRGB(110, 110, 110), -- a locked picture
	title = Color3.fromRGB(230, 220, 192), -- the hero's title
	runFace = Color3.fromRGB(42, 20, 22), -- YOUR RUN's chip
	runInk = Color3.fromRGB(255, 138, 132),
	rushFace = Color3.fromRGB(58, 42, 18), -- rush hour's chip, an amber state
	rushInk = Color3.fromRGB(245, 183, 72),
	goodFace = Color3.fromRGB(22, 46, 30), -- a green state's chip
	card = K.row,
	raised = K.raised,
	primary = K.red,
	good = K.good,
	warn = K.warn,
	text = K.text,
	secondary = K.secondary,
	line = K.line,
	white = Color3.new(1, 1, 1),
}
local C = CardKit.Color

-- The danger tiers (shared/JobPick.luau danger: 0 on foot / by bike, 1 .. 4 stars).
CardKit.Danger = {
	[0] = Color3.fromRGB(126, 196, 120),
	[1] = Color3.fromRGB(126, 196, 120),
	[2] = Color3.fromRGB(228, 170, 82),
	[3] = Color3.fromRGB(229, 83, 75),
	[4] = Color3.fromRGB(180, 108, 240),
} :: { [number]: Color3 }

-- What a thumb or a hero shows: an uploaded picture, else an emoji on charcoal, else an app's glyph (`glyph`: draws it
-- in a frame, e.g. client/PhoneContract.luau glyph).
-- 6.18 wave 2: `icon` an Icons name (its silhouette once uploaded, before the emoji).
export type Picture = { image: string?, emoji: string?, glyph: ((face: Instance, size: number) -> ())?, face: Color3?, icon: string? }

-- The soft click every button makes (client/Sounds.luau sets Ui.onClick).
function CardKit.click()
	local sound = Ui.onClick
	if sound then
		sound()
	end
end

-- How wide a line of text is (unscaled px).
function CardKit.width(value: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(function(): Vector2
		return game:GetService("TextService"):GetTextSize(value, size, font, Vector2.new(1000, 100))
	end)
	return if ok then math.ceil(bounds.X) + 2 else #value * size * 0.6
end

-- The picture filling `parent` (greyed when `shut`), else its emoji, else its glyph (`size`: the emoji's / glyph's).
-- `mark`: a hero's emoji (no picture uploaded) is a big faint mark at the card's right, not hidden under its shade.
function CardKit.picture(parent: Instance, picture: Picture, shut: boolean, size: number, z: number, mark: boolean?)
	if picture.image and picture.image ~= "" then
		Ui.make("ImageLabel", {
			Name = "Picture",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = picture.face or K.charcoal,
			BorderSizePixel = 0,
			Image = picture.image,
			ImageColor3 = if shut then C.grey else C.white,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = z,
		}, parent)
	elseif Icons.get(picture.icon) then
		-- 6.18 wave 2: an uploaded icon, whole (a hero's at its right like an emoji's mark)
		local face = Ui.make("Frame", { Name = "Icon", Size = UDim2.fromScale(1, 1), BackgroundColor3 = picture.face or K.charcoal, BorderSizePixel = 0, ZIndex = z }, parent)
		Ui.make("ImageLabel", {
			Name = "Silhouette",
			Size = UDim2.fromOffset(size, size),
			Position = if mark then UDim2.new(1, -12, 0.42, 0) else UDim2.fromScale(0.5, 0.5),
			AnchorPoint = if mark then Vector2.new(1, 0.5) else Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = Icons.get(picture.icon),
			ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = if shut then C.grey else C.white,
			ImageTransparency = if mark then 0.45 elseif shut then 0.4 else 0,
			ZIndex = z,
		}, face)
	elseif picture.glyph then
		local face = Ui.make("Frame", { Name = "Icon", Size = UDim2.fromScale(1, 1), BackgroundColor3 = picture.face or K.charcoal, BorderSizePixel = 0, ZIndex = z }, parent)
		local slot = Ui.make("Frame", { Name = "Slot", Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = z }, face)
		picture.glyph(slot, size)
	else
		local label = Ui.label(parent, picture.emoji or "📦", UDim2.fromScale(1, 1), {
			Name = "Emoji",
			BackgroundColor3 = picture.face or K.charcoal,
			BackgroundTransparency = 0,
			TextSize = size,
			TextTransparency = if mark then 0.55 elseif shut then 0.5 else 0,
			TextWrapped = false,
			TextXAlignment = if mark then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center,
			ZIndex = z,
		})
		if mark then
			Ui.make("UIPadding", { PaddingRight = UDim.new(0, 12) }, label)
		end
	end
end

-- ── Chips and buttons ───────────────────────────────────────────────────────

export type Chip = {
	name: string,
	text: string,
	face: Color3?, -- default raised
	ink: Color3?, -- default text
	order: number?,
	room: string?, -- the widest text it will show (a clock's), for its width
	stroke: Color3?, -- a hairline: lit (`lit`) or faint (`faint` transparency)
	lit: boolean?,
	faint: number?,
	static: boolean?, -- a state, not a button (not selectable)
	silent: boolean?, -- no click of its own (its onClick clicks)
	onClick: (() -> ())?,
}

function CardKit.chip(parent: Instance, spec: Chip): any
	local made = Ui.make("TextButton", {
		Name = spec.name,
		Size = UDim2.fromOffset(CardKit.width(spec.room or spec.text, 11, Theme.HeadingFont) + 22, KIT.Chip),
		BackgroundColor3 = spec.face or K.raised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = spec.text,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = spec.ink or K.text,
		LayoutOrder = spec.order or 0,
	}, parent)
	Ui.corner(made, KIT.Chip // 2)
	if spec.stroke then
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = spec.stroke, Thickness = 1, Transparency = if spec.lit then 0 else (spec.faint or 0.7) }, made)
	end
	if spec.static then
		made.Selectable = false
		made.Active = false
	end
	local onClick, silent = spec.onClick, spec.silent
	if onClick then
		made.Activated:Connect(function()
			if not silent then
				CardKit.click()
			end
			onClick()
		end)
	end
	return made
end

-- The one primary button: kind "primary" (red), "gold" (a special's), "good" (green: ready, start), "shut" (grey: it
-- says why it can't).
export type Button = { name: string, text: string, kind: string?, height: number?, textSize: number?, order: number?, z: number?, silent: boolean?, onClick: (() -> ())? }

local FACES: { [string]: { face: Color3, ink: Color3 } } = {
	primary = { face = K.red, ink = C.white },
	gold = { face = C.gold, ink = C.goldInk },
	good = { face = K.good, ink = C.goldInk },
	warn = { face = K.warn, ink = C.goldInk },
	shut = { face = K.raised, ink = K.secondary },
}
CardKit.Buttons = FACES

-- Paints a big button for a kind (a state that changes: the phone's hero).
function CardKit.paint(button: any, kind: string)
	local look = FACES[kind] or FACES.primary
	button.BackgroundColor3 = look.face
	button.TextColor3 = look.ink
end

function CardKit.bigButton(parent: Instance, spec: Button): any
	local look = FACES[spec.kind or "primary"] or FACES.primary
	local made = Ui.make("TextButton", {
		Name = spec.name,
		Size = UDim2.new(1, 0, 0, spec.height or KIT.Button),
		BackgroundColor3 = look.face,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = spec.text,
		Font = Theme.HeadingFont,
		TextSize = spec.textSize or 18,
		TextColor3 = look.ink,
		LayoutOrder = spec.order or 0,
	}, parent)
	if spec.z then
		made.ZIndex = spec.z
	end
	Ui.corner(made, 8)
	local onClick, silent = spec.onClick, spec.silent
	if onClick then
		made.Activated:Connect(function()
			if not silent then
				CardKit.click()
			end
			onClick()
		end)
	end
	return made
end

-- "7 MORE JOBS" (caps, secondary) with an optional chip at the right. Returns the strip, its label and the chip.
export type Section = { name: string?, label: string?, text: string, order: number?, chip: Chip? }

function CardKit.sectionHeader(parent: Instance, spec: Section): (any, any, any)
	local head = Ui.make("Frame", { Name = spec.name or "SectionHead", Size = UDim2.new(1, 0, 0, KIT.Chip), BackgroundTransparency = 1, LayoutOrder = spec.order or 0 }, parent)
	local label = Ui.label(head, spec.text, UDim2.new(1, -150, 1, 0), { Name = spec.label or "Section", Font = Theme.HeadingFont, TextSize = 11, TextColor3 = K.secondary, TextWrapped = false })
	local chip: any = nil
	if spec.chip then
		chip = CardKit.chip(head, spec.chip)
		chip.AnchorPoint = Vector2.new(1, 0)
		chip.Position = UDim2.fromScale(1, 0)
	end
	return head, label, chip
end

-- ── The hero card ───────────────────────────────────────────────────────────

export type Hero = {
	name: string?, -- "Hero"
	order: number?,
	height: number,
	button: boolean?, -- the whole card is a TextButton (spec.onOpen its tap), else a Frame with a cover
	face: Color3?, -- default the row surface
	stroke: Color3?, -- its frame (default a faint line)
	strong: boolean?, -- the frame drawn strong (2 px, opaque): a special
	picture: Picture,
	shut: boolean?,
	title: string,
	titleColor: Color3?,
	tag: string?, -- after the title (the danger stars)
	tagColor: Color3?,
	value: string,
	valueColor: Color3?,
	valueSize: number?, -- default CardLayout.valueSize(height)
	valueFont: Enum.Font?, -- default the display font
	facts: string?,
	factsColor: Color3?,
	bar: { share: number, color: Color3 }?,
	action: Button?, -- its big button (none: the card is the action)
	ribbon: { text: string, face: Color3, ink: Color3? }?, -- top left (★ GOLDEN ORDER ×3, NEXT MISSION, ▶ YOUR RUN)
	corner: { text: string, ink: Color3, width: number? }?, -- top right: a countdown, a state chip
	medal: string?, -- top right instead of a corner chip (a regular's tier)
	onOpen: (() -> ())?, -- a tap on the card
	onDetails: (() -> ())?, -- ⓘ
	silent: boolean?, -- no click of its own on a tap of the card (its onOpen clicks)
}

export type HeroParts = { card: any, info: any, head: any, title: any, tag: any, value: any, facts: any, track: any, bar: any, action: any, ribbon: any, corner: any, details: any }

function CardKit.hero(parent: Instance, spec: Hero): HeroParts
	local height = spec.height
	local strong = spec.strong == true
	local card = Ui.make(if spec.button then "TextButton" else "Frame", {
		Name = spec.name or "Hero",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = spec.face or K.row,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = spec.order or 1,
	}, parent)
	if spec.button then
		card.AutoButtonColor = false
		card.Text = ""
	end
	Ui.corner(card, KIT.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = spec.stroke or K.line, Thickness = if strong then 2 else 1, Transparency = if strong then 0 else 0.75 }, card)
	-- (an emoji without its picture: a big faint mark at the right, about the card's height)
	local markSize = math.floor(height * 0.62)
	card:SetAttribute("Mark", markSize)
	CardKit.picture(card, spec.picture, spec.shut == true, markSize, 1, true)
	local onOpen, silent = spec.onOpen, spec.silent
	local function open()
		if not silent then
			CardKit.click()
		end
		if onOpen then
			onOpen()
		end
	end
	-- the words at the foot over a shade: the title and its tag, the value, the facts, a bar, the button
	local valueSize = spec.valueSize or CardLayout.valueSize(height)
	local action = spec.action
	local _, infoH = CardLayout.heroInfo(valueSize, spec.facts ~= nil, spec.bar ~= nil, if action then action.height or KIT.Button else 0)
	local shadeH = infoH + CardLayout.SHADE
	Ui.make("Frame", { Name = "Fade", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -(shadeH + 40)), BackgroundColor3 = C.shade, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 2 }, card)
	Ui.make("Frame", { Name = "Shade", Size = UDim2.new(1, 0, 0, shadeH), Position = UDim2.new(0, 0, 1, -shadeH), BackgroundColor3 = C.shade, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 2 }, card)
	CardKit.shade(card, spec.picture.image ~= nil and spec.picture.image ~= "")
	if spec.button then
		card.Activated:Connect(open)
	else
		local cover = Ui.make("TextButton", { Name = "Open", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = false, ZIndex = 3, LayoutOrder = 9 }, card)
		cover.Activated:Connect(open)
	end
	local parts = { card = card } :: any
	local info = Ui.make("Frame", { Name = "Info", Size = UDim2.new(1, -32, 0, infoH), Position = UDim2.new(0, 16, 1, -CardLayout.EDGE), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1, ZIndex = 4, LayoutOrder = 0 }, card)
	Ui.list(info, true, CardLayout.LIST_GAP)
	parts.info = info
	local head = Ui.make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, CardLayout.HEAD), BackgroundTransparency = 1, LayoutOrder = 1 }, info)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, head)
	parts.head = head
	parts.title = Ui.label(head, spec.title, UDim2.fromOffset(0, CardLayout.HEAD), { Name = "Business", AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = spec.titleColor or C.title, TextWrapped = false, LayoutOrder = 1 })
	if spec.tag then
		parts.tag = Ui.label(head, spec.tag, UDim2.fromOffset(0, CardLayout.HEAD), { Name = "Danger", AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = spec.tagColor or K.text, TextWrapped = false, LayoutOrder = 2 })
	end
	parts.value = Ui.label(info, spec.value, UDim2.new(1, 0, 0, valueSize + 2), {
		Name = "Pay",
		Font = spec.valueFont or Theme.DisplayFont,
		TextSize = valueSize,
		TextColor3 = spec.valueColor or C.money,
		TextWrapped = false,
		LayoutOrder = 2,
	})
	if spec.facts then
		parts.facts = Ui.label(info, spec.facts, UDim2.new(1, 0, 0, CardLayout.FACTS), { Name = "Facts", Font = Theme.HeadingFont, TextSize = 14, TextColor3 = spec.factsColor or K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 3 })
	end
	if spec.bar then
		local track = Ui.make("Frame", { Name = "Progress", Size = UDim2.new(1, 0, 0, CardLayout.BAR), BackgroundColor3 = C.white, BackgroundTransparency = 0.82, BorderSizePixel = 0, LayoutOrder = 4 }, info)
		Ui.corner(track, 2)
		parts.track = track
		parts.bar = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(math.clamp(spec.bar.share, 0, 1), 1), BackgroundColor3 = spec.bar.color, BorderSizePixel = 0 }, track)
		Ui.corner(parts.bar, 2)
	end
	if action then
		Ui.make("Frame", { Name = "Gap", Size = UDim2.new(1, 0, 0, 4), BackgroundTransparency = 1, LayoutOrder = 5 }, info)
		local made = table.clone(action)
		made.order = 6
		parts.action = CardKit.bigButton(info, made)
	end
	-- on top: the ribbon at the left, a corner chip (or a medal) at the right, the ⓘ
	local ribbon = spec.ribbon
	if ribbon then
		local tag = Ui.label(card, ribbon.text, UDim2.fromOffset(CardKit.width(ribbon.text, 12, Theme.HeadingFont) + 22, 24), {
			Name = "Ribbon",
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = ribbon.face,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = ribbon.ink or C.goldInk,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		Ui.corner(tag, 12)
		parts.ribbon = tag
	end
	local corner = spec.corner
	if corner then
		local chip = Ui.label(card, corner.text, UDim2.fromOffset(corner.width or 70, 24), {
			Name = "Countdown",
			Position = UDim2.new(1, -10, 0, 10),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.3,
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextColor3 = corner.ink,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		Ui.corner(chip, 12)
		parts.corner = chip
	elseif spec.medal then
		Ui.label(card, spec.medal, UDim2.fromOffset(28, 28), { Name = "Medal", Position = UDim2.new(1, -46, 0, 8), AnchorPoint = Vector2.new(1, 0), TextSize = 22, TextWrapped = false, ZIndex = 4 })
	end
	local onDetails = spec.onDetails
	if onDetails then
		local more = Ui.make("TextButton", {
			Name = "Details",
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -10, 0, if ribbon then 40 else 10),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "ⓘ",
			Font = Theme.HeadingFont,
			TextSize = 16,
			TextColor3 = K.text,
			ZIndex = 5,
			LayoutOrder = 8,
		}, card)
		Ui.corner(more, 14)
		more.Activated:Connect(function()
			CardKit.click()
			onDetails()
		end)
		parts.details = more
	end
	return parts
end

-- ── The compact row ─────────────────────────────────────────────────────────

export type Row = {
	name: string, -- "JobRow", "jobsApp"
	order: number,
	accent: Color3, -- the edge at its left
	picture: Picture,
	thumb: number?, -- the thumb's width (default Config.UiKit.Thumb; an app's icon Config.UiKit.Icon)
	emojiSize: number?, -- default 24
	shut: boolean?, -- a greyed picture and value
	decorate: ((row: any) -> ())?, -- paints the row before its parts (a special order's frame)
	rest: Color3?, -- its face when not lit (default the row surface)
	overlay: string?, -- on the thumb's corner (a regular's medal)
	tag: string?, -- the danger stars beside the thumb
	tagColor: Color3?,
	tagWidth: number?, -- default 44 with a tag, else 0
	title: string,
	titleColor: Color3?,
	facts: string,
	factsColor: Color3?,
	value: string?, -- the big value (none: the name has the room)
	valueColor: Color3?,
	action: string?, -- the round action ("+", "›"); a button when onAction is given, else a mark
	lock: string?, -- instead of the action: a lock's short words ("🔒 LV 9")
	actionFace: Color3?, -- default red ("+") or raised ("›", a lock)
	onAction: (() -> ())?,
	badge: boolean?, -- a red count / word badge on the thumb's corner ("Badge", hidden)
	silent: boolean?, -- no click of its own (its onOpen clicks)
	onOpen: () -> (),
}

export type RowParts = { row: any, thumb: any, tag: any, title: any, facts: any, value: any, action: any, badge: any, layout: { thumb: number, tag: number, action: number } }

function CardKit.row(parent: Instance, spec: Row): RowParts
	local thumbW = spec.thumb or KIT.Thumb
	local shut = spec.shut == true
	local row = Ui.make("TextButton", {
		Name = spec.name,
		Size = UDim2.new(1, 0, 0, KIT.Row),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		LayoutOrder = spec.order,
	}, parent)
	Ui.corner(row, KIT.RowCorner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.8 }, row)
	if spec.decorate then
		spec.decorate(row)
	end
	local parts = { row = row } :: any
	Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = spec.accent, BorderSizePixel = 0, ZIndex = 3 }, row)
	local thumb = Ui.make("Frame", { Name = "Thumb", Size = UDim2.new(0, thumbW, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true }, row)
	CardKit.picture(thumb, spec.picture, shut, spec.emojiSize or 24, 1)
	parts.thumb = thumb
	if spec.overlay then
		Ui.label(thumb, spec.overlay, UDim2.fromOffset(18, 18), { Name = "Medal", Position = UDim2.new(1, -2, 0, 2), AnchorPoint = Vector2.new(1, 0), TextSize = 14, TextWrapped = false, ZIndex = 2 })
	end
	local x = thumbW + 10
	local tagW = spec.tagWidth or (if spec.tag then 44 else 0)
	if spec.tag then
		parts.tag = Ui.label(row, spec.tag, UDim2.new(0, tagW, 1, 0), { Name = "Danger", Position = UDim2.fromOffset(x, 0), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = spec.tagColor or K.text, TextWrapped = false })
	end
	-- the action at the right: the round button, a mark, or the lock's short words
	local lock = spec.lock
	-- (6.18 wave 2: a short word for the action, "BUY", "USE": a pill sized to it, like a lock's words)
	local word = if not lock and spec.action and (utf8.len(spec.action) or 1) > 1 then spec.action else nil
	local small = lock or word
	local addW = CardLayout.action(if small then CardKit.width(small, if word then 12 else 11, Theme.HeadingFont) else nil)
	local onAction = spec.onAction
	if lock or spec.action then
		local plus = spec.action == "+"
		local made = Ui.make(if onAction then "TextButton" else "TextLabel", {
			Name = "Add",
			Size = UDim2.fromOffset(addW, KIT.Add),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = spec.actionFace or (if lock or not (plus or (word and onAction)) then K.raised else K.red),
			BorderSizePixel = 0,
			Text = lock or spec.action,
			Font = Theme.HeadingFont,
			TextSize = if lock then 11 elseif word then 12 else 24,
			TextColor3 = if lock then K.secondary else C.white,
			ZIndex = 2,
		}, row)
		if onAction then
			made.AutoButtonColor = false
		end
		Ui.corner(made, if plus or small then 9 else KIT.Add // 2)
		if onAction then
			made.Activated:Connect(function()
				CardKit.click()
				onAction()
			end)
		end
		parts.action = made
	else
		addW = 0
	end
	local payW = 0
	if spec.value then
		payW = CardKit.width(spec.value, 20, Theme.HeadingFont) + 4
		parts.value = Ui.label(row, spec.value, UDim2.new(0, payW, 1, 0), {
			Name = "Pay",
			Position = UDim2.new(1, -(addW + 14), 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			Font = Theme.HeadingFont,
			TextSize = 20,
			TextColor3 = if shut then C.dim else (spec.valueColor or C.money),
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	parts.layout = { thumb = thumbW, tag = tagW, action = addW }
	local nameX, nameW = CardLayout.rowText(thumbW, tagW, addW, payW)
	parts.title = Ui.label(row, spec.title, UDim2.new(1, nameW, 0, 18), { Name = "Business", Position = UDim2.fromOffset(nameX, 8), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = spec.titleColor or K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	parts.facts = Ui.label(row, spec.facts, UDim2.new(1, nameW, 0, 16), { Name = "Facts", Position = UDim2.fromOffset(nameX, 27), TextSize = 11, TextColor3 = spec.factsColor or C.faint, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	if spec.badge then
		parts.badge = Ui.label(row, "", UDim2.fromOffset(18, 18), {
			Name = "Badge",
			Position = UDim2.fromOffset(thumbW + 2, 3),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = K.red,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = K.text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
			ZIndex = 4,
		})
		Ui.corner(parts.badge, 9)
	end
	local rest = spec.rest or K.row
	local function lit(on: boolean)
		row.BackgroundColor3 = if on then K.raised else rest
	end
	row.MouseEnter:Connect(function()
		lit(true)
	end)
	row.MouseLeave:Connect(function()
		lit(false)
	end)
	row.SelectionGained:Connect(function()
		lit(true)
	end)
	row.SelectionLost:Connect(function()
		lit(false)
	end)
	local onOpen, silent = spec.onOpen, spec.silent
	row.Activated:Connect(function()
		if not silent then
			CardKit.click()
		end
		onOpen()
	end)
	return parts
end

-- A live row's big value changed (the phone's JOBS row): its text and colour, the name column fitted again ("" hides
-- the value and gives the name its room).
function CardKit.setValue(parts: RowParts, value: string, color: Color3?)
	local label, layout = parts.value, (parts :: any).layout
	if not (label and layout) then
		return
	end
	local payW = if value == "" then 0 else CardKit.width(value, 20, Theme.HeadingFont) + 4
	label.Text = value
	label.Size = UDim2.new(0, payW, 1, 0)
	if color then
		label.TextColor3 = color
	end
	local _, nameW = CardLayout.rowText(layout.thumb, layout.tag, layout.action, payW)
	parts.title.Size = UDim2.new(1, nameW, 0, 18)
	parts.facts.Size = UDim2.new(1, nameW, 0, 16)
end

-- A hero's shade under its words: over a picture (`photo`) dark for the words; over its emoji's mark none (the mark shows).
function CardKit.shade(card: Instance, photo: boolean)
	local fade, shade = card:FindFirstChild("Fade") :: any, card:FindFirstChild("Shade") :: any
	if fade and shade then
		fade.BackgroundTransparency = if photo then 0.6 else 1
		shade.BackgroundTransparency = if photo then 0.2 else 1
	end
end

-- A card's picture changed (the phone's hero: another mission, another run): the old one goes, the new one fills it
-- (a hero's emoji as its mark).
function CardKit.repicture(card: Instance, picture: Picture, size: number)
	for _, name in { "Picture", "Emoji", "Icon" } do
		local old = card:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local mark = card:GetAttribute("Mark")
	CardKit.picture(card, picture, false, if type(mark) == "number" then mark else size, 1, type(mark) == "number")
	CardKit.shade(card, picture.image ~= nil and picture.image ~= "")
end

-- 6.18 wave 2: a row of tab chips (the SHOP counters', BAG & ITEMS', STYLE's tabs): "Tab_<id>" each, the open one lit
-- (a strong hairline and the red "Underline"); a tap picks it (onPick: the caller draws again). Returns the row and the
-- chips by id.
export type Tabs = { name: string?, order: number?, tabs: { { string } }, selected: string, onPick: (id: string) -> () }

function CardKit.tabs(parent: Instance, spec: Tabs): (any, { [string]: any })
	local row = Ui.make("Frame", { Name = spec.name or "Tabs", Size = UDim2.new(1, 0, 0, KIT.Chip + 4), BackgroundTransparency = 1, LayoutOrder = spec.order or 0 }, parent)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	local made: { [string]: any } = {}
	for index, entry in spec.tabs do
		local id = entry[1]
		local on = id == spec.selected
		local chip = CardKit.chip(row, { name = `Tab_{id}`, text = entry[2], order = index, face = if on then K.raised else K.row, ink = if on then K.text else K.secondary, stroke = if on then K.text else K.line, lit = on, faint = 0.8, onClick = function()
			spec.onPick(id)
		end })
		chip.Size = UDim2.fromOffset(chip.Size.X.Offset + 8, KIT.Chip + 4)
		if on then
			Ui.make("Frame", { Name = "Underline", Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -2), BackgroundColor3 = K.red, BorderSizePixel = 0 }, chip)
		end
		made[id] = chip
	end
	return row, made
end

-- ── Layout and the details sub-view ─────────────────────────────────────────

-- The hero beside the rows (`side`: a body CardLayout.side wide) or heading them. Returns the holder, the hero's
-- column (nil without a hero) and the rows' column (a vertical list, Gap px).
export type Columns = { name: string?, order: number, side: boolean, hero: boolean, heroHeight: number }

function CardKit.columns(list: Instance, spec: Columns): (any, any, any)
	local holder = Ui.make("Frame", { Name = spec.name or "Cards", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = spec.order }, list)
	local side = spec.side and spec.hero
	Ui.make("UIListLayout", {
		FillDirection = if side then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	local share = if side then KIT.HeroShare else 1
	local left: any = nil
	if spec.hero then
		left = Ui.make("Frame", { Name = "Left", Size = UDim2.new(share, if side then -5 else 0, 0, spec.heroHeight), BackgroundTransparency = 1, LayoutOrder = 1 }, holder)
	end
	local right = Ui.make("Frame", { Name = "Right", Size = UDim2.new(if side then 1 - share else 1, if side then -5 else 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, holder)
	Ui.list(right, true, KIT.Gap)
	return holder, left, right
end

-- A tap-for-details sub-view: its "‹ BACK" button (`back`: its words, "‹ JOBS"; `look`: the app's kit, OrdersUi.Kit)
-- then what `draw` puts under it (from `order` + 1).
export type Details = { back: string?, name: string?, order: number?, onBack: () -> (), draw: ((list: Instance, order: number) -> ())? }

function CardKit.details(list: Instance, look: any, spec: Details): any
	local order = spec.order or 1
	local button = look.button(list, spec.back or "‹ BACK", "quiet", order, spec.onBack)
	button.Name = spec.name or "Back"
	if spec.draw then
		spec.draw(list, order + 1)
	end
	return button
end

return CardKit
