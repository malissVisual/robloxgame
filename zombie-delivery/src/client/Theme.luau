--!strict
-- Dead End Dispatch: all visual tokens live here. Does not contain gameplay state.
-- 3.6, "Postage & Trouble" (Codex's concept, design/ui-concept/): the whole interface is light now. Cream paper and
-- powder-lavender surfaces with dark plum ink, pastel actions (sage for the main one), shipping-ticket shapes. The
-- semantic colours (Theme.Colors: panel, text, yellow, red ...) keep their names and meaning, so every module that
-- used them gets the new look; they are now inks readable on the light surfaces, and Theme.soft turns one into the
-- pastel surface a button or a chip of that meaning wears (Ui.button / Ui.chip do it for you).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))

local Theme = {}

-- 3.6, "Postage & Trouble": soft courier colours. Light cream and powder-lavender surfaces with dark plum ink; pastels
-- on surfaces, never for critical text. Use these through Theme, not raw Color3s.
Theme.Postage = {
	paper = Color3.fromRGB(250, 244, 228), -- #FAF4E4 the current objective ticket, cards on the HUD
	ticket = Color3.fromRGB(252, 247, 237), -- #FCF7ED job cards, list rows
	lavender = Color3.fromRGB(238, 230, 243), -- #EEE6F3 window surfaces
	lavenderDeep = Color3.fromRGB(226, 214, 236), -- selected rows, the sidebar
	ink = Color3.fromRGB(73, 55, 80), -- #493750 objectives, prices, big values
	ink2 = Color3.fromRGB(116, 97, 125), -- #74617D routes, labels, explanations
	sage = Color3.fromRGB(229, 237, 206), -- #E5EDCE the main action (ACCEPT, TAKE OUT)
	violet = Color3.fromRGB(132, 102, 153), -- #846699 crew / GPS identity, key chips
	line = Color3.fromRGB(205, 190, 214), -- perforations, dashed separators, thin strokes
	shadow = Color3.fromRGB(58, 40, 70), -- the soft drop shadow under paper
	danger = Color3.fromRGB(196, 72, 84), -- warnings (always with an icon or text, never colour alone)
	good = Color3.fromRGB(78, 112, 58), -- success as ink on paper ("Owned", "Your car is here", a full bar)
	warn = Color3.fromRGB(170, 104, 36), -- a middle state as ink or a bar (half condition, "the car could not come")
	tags = { -- the consumable tags, alternating
		Color3.fromRGB(240, 232, 248),
		Color3.fromRGB(250, 240, 222),
		Color3.fromRGB(228, 240, 214),
		Color3.fromRGB(248, 226, 232),
		Color3.fromRGB(224, 236, 246),
	},
	-- 3.6 (stream B): the window chrome and the button faces (index.html, the "Postage & Trouble" block).
	header = Color3.fromRGB(228, 215, 238), -- #E4D7EE a window's header
	footer = Color3.fromRGB(233, 221, 247), -- #E9DDF7 a window's footer
	footerLine = Color3.fromRGB(195, 170, 218), -- #C3AADA the line over the footer
	dash = Color3.fromRGB(205, 185, 219), -- #CDB9DB the dashed line under the header
	windowShadow = Color3.fromRGB(198, 177, 213), -- #C6B1D5 the window's offset shadow
	brand = Color3.fromRGB(228, 235, 208), -- #E4EBD0 the icon circle in a window's header
	brandLine = Color3.fromRGB(196, 203, 170), -- #C4CBAA its ring
	closeFace = Color3.fromRGB(243, 235, 249), -- #F3EBF9 the round close button
	closeLip = Color3.fromRGB(207, 185, 219), -- #CFB9DB its shadow
	sageLip = Color3.fromRGB(188, 202, 152), -- #BCCA98 the main action's shadow
	sageHover = Color3.fromRGB(239, 245, 221), -- #EFF5DD the main action under the mouse
	sagePress = Color3.fromRGB(220, 230, 193), -- #DCE6C1 the main action pressed
	rose = Color3.fromRGB(246, 223, 228), -- a red (danger) action's face
	roseLip = Color3.fromRGB(221, 176, 186),
	sky = Color3.fromRGB(223, 234, 245), -- a blue (info, GPS-to) action's face
	skyLip = Color3.fromRGB(174, 197, 220),
	butter = Color3.fromRGB(248, 236, 204), -- a gold (special, earned) chip's face
	butterLip = Color3.fromRGB(222, 199, 150),
	lilac = Color3.fromRGB(234, 222, 246), -- a violet (crew) action's face
	lilacLip = Color3.fromRGB(196, 172, 220),
	disabled = Color3.fromRGB(233, 223, 239), -- #E9DFEF a locked / disabled action
	track = Color3.fromRGB(230, 218, 237), -- #E6DAED the empty part of a bar
	hatch = Color3.fromRGB(239, 232, 242), -- #EFE8F2 a locked ticket (hatched)
	note = Color3.fromRGB(238, 234, 221), -- #EEEADD a written remedy under a locked ticket
	gold = Color3.fromRGB(178, 128, 30), -- medals, titles, the star gold as ink
	silver = Color3.fromRGB(128, 132, 146),
	bronze = Color3.fromRGB(168, 102, 56),
	veil = Color3.fromRGB(42, 30, 52), -- the dim veil over the world behind a modal / the wheel
	pill = Color3.fromRGB(250, 244, 228), -- the cream pill behind text that floats over the 3D world
}
local P = Theme.Postage

-- 3.7+, the contract UI (Codex's design/ui-contract/, approved by the owner): compact white type over the world, a
-- localized charcoal scrim or window surface, fine grey lines and small precise red accents (the contract marker, the
-- destination, urgent feedback). Success and damage keep their meaning (good / warn), always with a word or an icon.
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
}

-- The semantic colours, remapped for the light surfaces: `panel` / `panelLight` are surfaces (lavender, cream
-- paper), `text` / `dim` the plum inks, and the accents (money, yellow, red, green, blue, grey) are inks that read
-- on cream and lavender (at least 3:1). As a button's or a chip's face they become their pastel (Theme.soft).
Theme.Colors = {
	panel = P.lavender,
	panelLight = P.ticket,
	text = P.ink,
	dim = P.ink2,
	money = Color3.fromRGB(78, 118, 52),
	yellow = Color3.fromRGB(166, 104, 24), -- the old gold accent, now an amber ink
	red = Color3.fromRGB(190, 64, 78),
	green = Color3.fromRGB(84, 124, 58),
	blue = Color3.fromRGB(56, 112, 148),
	grey = Color3.fromRGB(138, 124, 148),
}
-- The GPS purple: the GPS route on the maps, the crew (its strip, window and tags) and the CREW button. It stays vivid
-- (the route over the map and the beam in the world); on paper use Theme.Postage.violet for text.
Theme.Gps = Color3.fromRGB(176, 92, 255)
Theme.Border = P.line
Theme.Radius = 8 -- buttons and the default corner
Theme.PanelTransparency = 0.04 -- the HUD's cards: paper, nearly solid (3.2's dark glass is gone)
Theme.PanelRadius = 12
Theme.BorderTransparency = 0.2 -- the quiet stroke (Border); an accent stroke is solid
Theme.WindowTransparency = 0
Theme.WindowRadius = 18 -- the lavender windows
Theme.Ink = P.ink -- key chips, badges and text on the pastel faces
Theme.Font = Enum.Font.GothamMedium
Theme.HeadingFont = Enum.Font.GothamBold
Theme.DisplayFont = Enum.Font.GothamBlack
Theme.MonoFont = Enum.Font.RobotoMono -- the ticket numbers: timers, payouts, key numbers, "3 / 4 slots"

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

-- The ink for text on `color`: plum on light surfaces, cream paper on dark ones.
function Theme.textOn(color: Color3): Color3
	return if Theme.contrast(P.ink, color) >= Theme.contrast(P.paper, color) then P.ink else P.paper
end

-- `text` if it reads on `surface` (at least 3:1), else the ink that does (textOn). Ui.button and Ui.chip use it so a
-- caller's old white-on-colour text never ends up white on a pastel.
function Theme.readable(text: Color3, surface: Color3): Color3
	return if Theme.contrast(text, surface) >= 3 then text else Theme.textOn(surface)
end

local function key(color: Color3): string
	return string.format("%d,%d,%d", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

export type Soft = { face: Color3, lip: Color3, text: Color3, main: boolean, quiet: boolean }

-- The pastel faces of the semantic colours: what a button or a chip of that meaning wears.
local SOFT: { [string]: Soft } = {}
local FACES: { [string]: boolean } = {}
local function soft(colors: { Color3 }, face: Color3, lip: Color3, text: Color3, main: boolean, quiet: boolean)
	for _, color in colors do
		SOFT[key(color)] = { face = face, lip = lip, text = text, main = main, quiet = quiet }
	end
	FACES[key(face)] = true
end
local C = Theme.Colors
-- The old (3.5) values too: a module that still writes one of them gets the new face.
soft({ C.yellow, C.green, C.money, P.sage, Color3.fromRGB(245, 179, 79), Color3.fromRGB(139, 186, 116), Color3.fromRGB(170, 218, 137) }, P.sage, P.sageLip, P.ink, true, false)
soft({ C.red, P.danger, Color3.fromRGB(231, 112, 92) }, P.rose, P.roseLip, P.ink, false, false)
soft({ C.blue, Color3.fromRGB(117, 175, 185) }, P.sky, P.skyLip, P.ink, false, false)
soft({ C.grey, P.disabled, Color3.fromRGB(79, 95, 82) }, P.disabled, P.disabled, P.ink2, false, true)
soft({ Theme.Gps, P.violet, P.lilac }, P.lilac, P.lilacLip, P.ink, false, false)
soft({ P.gold, P.butter }, P.butter, P.butterLip, P.ink, false, false)
soft({ C.panelLight, P.paper, Color3.fromRGB(34, 45, 40) }, P.ticket, P.closeLip, P.ink, false, false)
soft({ C.panel, P.lavenderDeep, Color3.fromRGB(20, 28, 26) }, P.lavenderDeep, P.closeLip, P.ink, false, false)

-- The pastel face, its shadow (lip) and its ink for an action or a chip of `color`. The semantic colours have their
-- own faces (yellow / green / money: the sage main action; red: rose; blue: sky; grey: disabled; the GPS purple:
-- lilac); any other colour is washed toward paper (it keeps its hue: a campaign's, a kind's).
function Theme.soft(color: Color3): Soft
	local known = SOFT[key(color)]
	if known then
		return known
	end
	local face = color:Lerp(P.paper, 0.68)
	return { face = face, lip = color:Lerp(P.paper, 0.35), text = Theme.textOn(face), main = false, quiet = false }
end

-- Is `color` one of the pastel faces Theme.soft hands out (so it is not washed again)?
function Theme.isFace(color: Color3): boolean
	return FACES[key(color)] == true
end

-- The same colour, compared by its 0 – 255 channels (a Color3 read back from a property is rounded to floats).
function Theme.same(a: Color3, b: Color3): boolean
	return key(a) == key(b)
end

return Theme
