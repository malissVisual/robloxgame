--!strict
-- 6.18, the UI kit: the parts the game's windows draw with (the STOCK list and the picker, the book, the UPGRADES desk,
-- the TASKS panel, the PAINT shop, trading, the CREW window, the map, the move's panel, the Auction House):
--   * CardKit.Color                    the palette: money green, gold for something special, dim and faint words, the
--                                      amber and green states' chips, and Theme's contract colours
--   * CardKit.chip(parent, spec)       a small rounded chip (a state, a tab, a sort or a filter)
--   * CardKit.bigButton(parent, spec)  the one primary button of a screen (red; gold for a special; green; grey shut);
--                                      CardKit.paint(button, kind) repaints it for another state, CardKit.Buttons the faces
--   * CardKit.click()                  the soft click every button makes; CardKit.width(text, size, font) a line's width
-- The sizes are Config.UiKit's (Chip, Button). Presentation only: every action keeps its caller's server path.
-- 10.6: the city phone's cards (the hero, the rows, their 3D pictures and icons, the tabs, the details sub-view; their
-- maths shared/CardLayout.luau) are gone with the city.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local K = Theme.Contract
local KIT = Config.UiKit
local CardKit = {}

CardKit.Color = {
	money = Color3.fromRGB(111, 227, 138), -- a pay, money you get: the big value
	gold = Color3.fromRGB(242, 201, 76), -- something special (a legendary, a sale): its value, ribbon and button
	goldInk = Color3.fromRGB(42, 30, 5), -- the words on gold
	dim = Color3.fromRGB(125, 131, 139), -- a locked item's value
	faint = Color3.fromRGB(142, 148, 156), -- a row's facts line
	title = Color3.fromRGB(230, 220, 192), -- a card's title
	rushFace = Color3.fromRGB(58, 42, 18), -- an amber state's chip (a piece ON STAND in the STOCK list)
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

-- Paints a big button for a kind (a state that changes: the PAINT shop's BUY / WEAR, a bid, the run's LEAVE).
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

return CardKit
