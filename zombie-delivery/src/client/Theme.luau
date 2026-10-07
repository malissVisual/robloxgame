--!strict
-- Dead End Dispatch: all visual tokens live here. Does not contain gameplay state.
-- 3.8, the contract UI (Codex's design/ui-contract/, approved by the owner; it replaces 3.6's "Postage & Trouble"):
-- charcoal rectangles, compact white type, fine grey lines and small precise red accents. Theme.Contract holds the
-- tokens. The semantic colours (Theme.Colors: panel, text, yellow, red ...) keep their names and meaning, so every
-- module that used them gets the new look; Theme.soft turns one into the flat dark face a button or a chip of that
-- meaning wears (Ui.button / Ui.chip do it for you). Theme.Postage stays for old references, remapped (see there).
-- 5.8, every window in the courier-phone style (design/phone-ui/): Theme.Contract.red as a button's colour is the
-- PRIMARY action (a red face, white caps, square: Ui.button(..., Theme.Contract.red), HudContract.button "primary");
-- Theme.Colors.red stays the danger meaning (a dark face with a red hint), one step apart so Theme.soft tells them
-- apart. The last pastel Postage tokens (violet, sage, hatch) are contract tokens now.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))

local Theme = {}

-- 3.7+, the contract UI: compact white type over the world, a localized charcoal scrim or window surface, fine grey
-- lines and small precise red accents (the contract marker, the destination, urgent feedback). Success and damage keep
-- their meaning (good / warn), always with a word or an icon.
Theme.Contract = {
	text = Color3.fromRGB(242, 242, 240), -- #F2F2F0 main text and icons
	secondary = Color3.fromRGB(196, 199, 203), -- #C4C7CB supporting text
	charcoal = Color3.fromRGB(20, 23, 28), -- #14171C readability backing, window surfaces
	raised = Color3.fromRGB(30, 34, 41), -- a selected row / hovered surface on charcoal
	line = Color3.fromRGB(133, 139, 147), -- #858B93 fine separators (use with transparency)
	red = Color3.fromRGB(215, 74, 70), -- #D74A46 contract, destination, urgent
	good = Color3.fromRGB(126, 196, 120), -- success as text / a full bar on charcoal
	warn = Color3.fromRGB(228, 170, 82), -- a middle state on charcoal
	scrim = 0.35, -- the charcoal scrim's transparency behind HUD text groups
	lineAlpha = 0.45, -- the fine lines' transparency
	-- 3.8 (the windows): the steps around charcoal, and the line already mixed over charcoal (a solid colour for the
	-- places that cannot take a transparency, e.g. a stroke a caller sets to Transparency 0).
	row = Color3.fromRGB(25, 29, 35), -- a list row / card on a charcoal window
	recessed = Color3.fromRGB(15, 17, 21), -- a sunk area (a sidebar, an inactive tab, a disabled action)
	track = Color3.fromRGB(52, 57, 64), -- the empty part of a bar
	rule = Color3.fromRGB(82, 87, 93), -- Contract.line at lineAlpha over charcoal: a fine solid separator
}
local K = Theme.Contract

-- 3.6's "Postage & Trouble" tokens, kept so every module that still names them compiles. 3.8: nothing shows the
-- cream / lavender / pastel look any more. Each field is remapped to the contract value of the same ROLE (a surface to
-- a charcoal step, an ink to the light text, an accent to red / good / warn, a pastel face to a flat dark face), so
-- the old references restyle themselves consistently. The names are legacy: `paper` is a raised charcoal card, `ink`
-- the light text, `sage` the main action's face, `violet` a light accent, `lavenderDeep` a recessed surface. New code
-- uses Theme.Contract.
-- 5.8: the ones that still differed are retired onto contract tokens: paper and sage are Contract.raised (as a
-- button's colour the raised "active" look: a selected tab or row), lavender is charcoal, violet the white text, hatch
-- the recessed surface. A main action asks for Theme.Colors.yellow (raised, the red rule) or Contract.red (primary).
-- The action faces below (rose, sky, ...) stay a step apart so Theme.soft can tell the meanings apart.
Theme.Postage = {
	paper = K.raised, -- a card that stands out on charcoal; the active tab (was the cream ticket)
	ticket = K.row, -- job cards, list rows
	lavender = K.charcoal, -- window surfaces
	lavenderDeep = K.recessed, -- a sidebar, an inactive tab, a disabled action
	ink = K.text, -- objectives, prices, big values
	ink2 = K.secondary, -- routes, labels, explanations
	sage = K.raised, -- (was the main action's face) a raised surface, like paper
	violet = K.text, -- the old crew / GPS accent as ink: the white text, bars and key letters
	line = K.rule, -- separators, thin strokes
	shadow = Color3.fromRGB(0, 0, 0), -- (no drop shadows any more)
	danger = K.red, -- warnings (always with an icon or text, never colour alone)
	good = K.good, -- success ("Owned", "Your car is here", a full bar)
	warn = K.warn, -- a middle state (half condition, "the car could not come")
	tags = { -- the consumable tags and the tinted rows: dark, barely tinted faces (no pastels)
		Color3.fromRGB(34, 38, 46),
		Color3.fromRGB(40, 37, 31),
		Color3.fromRGB(30, 40, 33),
		Color3.fromRGB(42, 30, 32),
		Color3.fromRGB(29, 36, 45),
	},
	header = K.charcoal, -- a window's header
	footer = K.charcoal, -- a window's footer
	footerLine = K.rule, -- the line over the footer
	dash = K.rule, -- the line under the header
	windowShadow = K.charcoal, -- (no offset shadow any more)
	brand = K.raised, -- (the header badge is gone)
	brandLine = K.rule,
	closeFace = K.charcoal, -- the close action (plain text now)
	closeLip = K.rule, -- a quiet line
	sageLip = K.red, -- the main action's thin red rule
	sageHover = Color3.fromRGB(44, 49, 58), -- the main action under the mouse
	sagePress = Color3.fromRGB(26, 29, 35), -- the main action pressed
	rose = Color3.fromRGB(46, 27, 29), -- a red (danger) action's face: charcoal with a hint of red
	roseLip = K.red,
	sky = Color3.fromRGB(28, 35, 44), -- a blue (info, GPS-to) action's face
	skyLip = Color3.fromRGB(138, 166, 190),
	butter = Color3.fromRGB(44, 39, 27), -- a gold (special, earned) chip's face
	butterLip = Color3.fromRGB(214, 178, 92),
	lilac = Color3.fromRGB(35, 36, 46), -- a crew action's face
	lilacLip = Color3.fromRGB(205, 208, 214),
	disabled = Color3.fromRGB(27, 30, 35), -- a locked / disabled action
	track = K.track, -- the empty part of a bar
	hatch = K.recessed, -- a locked row (a sunk surface; no hatching)
	note = Color3.fromRGB(31, 33, 38), -- a written remedy under a locked row
	gold = Color3.fromRGB(214, 178, 92), -- medals, titles, the star gold as text on charcoal
	silver = Color3.fromRGB(186, 191, 199),
	bronze = Color3.fromRGB(198, 134, 86),
	veil = Color3.fromRGB(8, 10, 13), -- the dim veil over the world behind a modal / the wheel
	pill = K.charcoal, -- the charcoal scrim behind text that floats over the 3D world
}
local P = Theme.Postage

-- The semantic colours every module uses: `panel` / `panelLight` are surfaces (charcoal, a row), `text` / `dim` the
-- light inks, and the accents read on charcoal (at least 3:1). As a button's or a chip's face they become a flat dark
-- face (Theme.soft); their colour stays in the text or the thin accent.
Theme.Colors = {
	panel = K.charcoal,
	panelLight = K.row,
	text = K.text,
	dim = K.secondary,
	money = Color3.fromRGB(132, 200, 122), -- money reads as good (a step apart from green)
	yellow = K.warn, -- the old gold accent: amber as text; as a button it is the main action
	-- the danger meaning (warnings, FIRE, LEAVE): as text the contract red; as a button's colour a dark face with a red
	-- hint. One step from Contract.red, which as a button's colour is the primary action.
	red = Color3.fromRGB(214, 74, 70),
	green = K.good,
	blue = Color3.fromRGB(138, 166, 190), -- a cool grey-blue (info)
	grey = K.line,
}
-- The GPS purple: the GPS route on the maps and the beam in the world (they stay vivid over the scene). On a window
-- the crew's text uses Theme.Postage.violet (a light accent now).
Theme.Gps = Color3.fromRGB(176, 92, 255)
Theme.Border = P.line
Theme.Radius = 2 -- buttons and the default corner: flat, square geometry (0 – 2 px)
Theme.PanelTransparency = 0.12 -- the HUD's cards: a charcoal scrim
Theme.PanelRadius = 2
Theme.BorderTransparency = 0 -- the quiet stroke (Border is already the line mixed over charcoal)
Theme.WindowTransparency = 0.02
Theme.WindowRadius = 0 -- the charcoal windows: a plain rectangle
Theme.Ink = P.ink -- key chips, badges and text on the dark faces
Theme.Font = Enum.Font.GothamMedium
Theme.HeadingFont = Enum.Font.GothamBold
Theme.DisplayFont = Enum.Font.GothamBold -- 3.8: no Black weight; titles are bold with restraint
Theme.MonoFont = Enum.Font.GothamMedium -- 3.8: numbers stay in the Gotham family (timers, payouts, "3 / 4 slots")

-- Optional Roblox assets. Empty IDs keep the live city flyover and native wordmark.
-- The ids are pasted in shared/Icons.luau (zombie_delivery_logo, menu_background), the one place for every picture.
Theme.Images = {
	logo = Icons.get("zombie_delivery_logo") or "",
	menuBackground = Icons.get("menu_background") or "",
}

local function linear(v: number): number
	return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end

local function luminance(color: Color3): number
	return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
end

-- The WCAG contrast ratio of two colours (1 – 21).
function Theme.contrast(a: Color3, b: Color3): number
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

-- The text for `color`: the light contract text on dark faces (all of them now), charcoal on a light one.
function Theme.textOn(color: Color3): Color3
	return if Theme.contrast(K.text, color) >= Theme.contrast(K.charcoal, color) then K.text else K.charcoal
end

-- `text` if it reads on `surface` (at least 3:1), else the text that does (textOn). Ui.button and Ui.chip use it so a
-- caller's old dark ink never ends up dark on charcoal.
function Theme.readable(text: Color3, surface: Color3): Color3
	return if Theme.contrast(text, surface) >= 3 then text else Theme.textOn(surface)
end

local function key(color: Color3): string
	return string.format("%d,%d,%d", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

-- face: the flat surface; lip: its thin accent (the main action's red rule, a meaning's edge); text: its label;
-- main: the one clear action of a window; quiet: disabled / secondary (no accent); primary (5.8): the phone's red
-- action (a red face, white caps, square; Contract.red).
export type Soft = { face: Color3, lip: Color3, text: Color3, main: boolean, quiet: boolean, primary: boolean }

-- The flat faces of the semantic colours: what a button or a chip of that meaning wears.
local SOFT: { [string]: Soft } = {}
local FACES: { [string]: boolean } = {}
local function soft(colors: { Color3 }, face: Color3, lip: Color3, text: Color3, main: boolean, quiet: boolean, primary: boolean?)
	for _, color in colors do
		SOFT[key(color)] = { face = face, lip = lip, text = text, main = main, quiet = quiet, primary = primary == true }
	end
	FACES[key(face)] = true
end
local C = Theme.Colors
-- The old (3.5 dark, 3.6 pastel) values too: a module that still writes one of them gets the new face.
-- 5.8: the primary action, the phone's red button (Contract.red; PhoneContract.primary draws the same).
soft({ K.red }, K.red, K.red, K.text, true, false, true)
-- The main action: raised charcoal (a step from Contract.raised) with the red rule.
local MAIN_FACE = Color3.fromRGB(33, 37, 45)
soft({ C.yellow, C.green, C.money, MAIN_FACE, Color3.fromRGB(245, 179, 79), Color3.fromRGB(139, 186, 116), Color3.fromRGB(170, 218, 137), Color3.fromRGB(229, 237, 206) }, MAIN_FACE, P.sageLip, K.text, true, false)
soft({ C.red, P.rose, Color3.fromRGB(231, 112, 92), Color3.fromRGB(196, 72, 84), Color3.fromRGB(190, 64, 78) }, P.rose, P.roseLip, K.text, false, false)
soft({ C.blue, P.sky, Color3.fromRGB(117, 175, 185), Color3.fromRGB(56, 112, 148) }, P.sky, P.skyLip, K.text, false, false)
soft({ C.grey, P.disabled, Color3.fromRGB(79, 95, 82), Color3.fromRGB(138, 124, 148) }, P.disabled, P.disabled, K.secondary, false, true)
soft({ Theme.Gps, P.violet, Color3.fromRGB(228, 230, 233), P.lilac }, P.lilac, P.lilacLip, K.text, false, false)
soft({ P.gold, P.butter, Color3.fromRGB(178, 128, 30) }, P.butter, P.butterLip, K.text, false, false)
-- An active tab / a highlighted card (P.paper, P.sage: Contract.raised): raised, a white rule on hover.
soft({ K.raised }, K.raised, K.text, K.text, false, false)
soft({ C.panelLight, Color3.fromRGB(34, 45, 40), Color3.fromRGB(252, 247, 237), Color3.fromRGB(250, 244, 228) }, P.ticket, P.line, K.text, false, false)
soft({ C.panel, P.lavenderDeep, Color3.fromRGB(20, 28, 26), Color3.fromRGB(238, 230, 243), Color3.fromRGB(226, 214, 236) }, P.lavenderDeep, P.line, K.secondary, false, true)

-- The flat face, its thin accent (lip) and its text for an action or a chip of `color`. The semantic colours have
-- their own faces (Contract.red: the primary action, a red face; yellow / green / money: the main action, raised
-- charcoal with a red rule; paper / sage: raised, the active look; red (Theme.Colors.red, danger): charcoal with a
-- hint of red; blue: with a hint of grey-blue; grey: disabled; the GPS purple: crew); any other colour becomes a
-- charcoal face barely tinted by it, with the colour itself as the accent (a campaign's, a kind's).
function Theme.soft(color: Color3): Soft
	local known = SOFT[key(color)]
	if known then
		return known
	end
	local face = color:Lerp(K.charcoal, 0.84)
	return { face = face, lip = color, text = Theme.textOn(face), main = false, quiet = false, primary = false }
end

-- Is `color` one of the flat faces Theme.soft hands out (so it is not mapped again)?
function Theme.isFace(color: Color3): boolean
	return FACES[key(color)] == true
end

-- The same colour, compared by its 0 – 255 channels (a Color3 read back from a property is rounded to floats).
function Theme.same(a: Color3, b: Color3): boolean
	return key(a) == key(b)
end

return Theme
