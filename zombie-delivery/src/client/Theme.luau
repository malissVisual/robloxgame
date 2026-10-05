--!strict
-- Dead End Dispatch: all visual tokens live here. Does not contain gameplay state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Icons"))

local Theme = {}

Theme.Colors = {
	panel = Color3.fromRGB(20, 28, 26),
	panelLight = Color3.fromRGB(34, 45, 40),
	text = Color3.fromRGB(246, 241, 224),
	dim = Color3.fromRGB(175, 187, 169),
	money = Color3.fromRGB(170, 218, 137),
	yellow = Color3.fromRGB(245, 179, 79),
	red = Color3.fromRGB(231, 112, 92),
	green = Color3.fromRGB(139, 186, 116),
	blue = Color3.fromRGB(117, 175, 185),
	grey = Color3.fromRGB(79, 95, 82),
}
-- The GPS purple: the GPS route on the maps, the crew (its strip, window and tags) and the CREW button.
Theme.Gps = Color3.fromRGB(176, 92, 255)
Theme.Border = Color3.fromRGB(78, 94, 81)
Theme.Radius = 10 -- buttons and the default corner
Theme.PanelTransparency = 0.15 -- 3.2: the HUD's dark glass (the windows set their own, more solid)
-- 3.2, the HUD style (the right side of 3.1.3 – 3.1.4, now everywhere): dark glass panels with a 12 px corner, a thin
-- quiet stroke (an accent colour only where it matters), DisplayFont for the big things, HeadingFont small caps for
-- the labels, gold (Colors.yellow) the one accent.
Theme.PanelRadius = 12
Theme.BorderTransparency = 0.45 -- the quiet stroke (Border); an accent stroke is solid
Theme.WindowTransparency = 0.04
Theme.Ink = Color3.fromRGB(10, 14, 13) -- key chips, badges, the dark of the bars
Theme.Font = Enum.Font.GothamMedium
Theme.HeadingFont = Enum.Font.GothamBold
Theme.DisplayFont = Enum.Font.GothamBlack

-- Optional Roblox assets. Empty IDs keep the live city flyover and native wordmark.
-- The ids are pasted in shared/Icons.luau (zombie_delivery_logo, menu_background), the one place for every picture.
Theme.Images = {
	logo = Icons.get("zombie_delivery_logo") or "",
	menuBackground = Icons.get("menu_background") or "",
}

-- 3.6, "Postage & Trouble" (Codex's concept, design/ui-concept/): soft courier colours. Light cream and powder-lavender
-- surfaces with dark plum ink; pastels on surfaces, never for critical text. Use these through Theme, not raw Color3s.
Theme.Postage = {
	paper = Color3.fromRGB(250, 244, 228), -- #FAF4E4 the current objective ticket, cards on the HUD
	ticket = Color3.fromRGB(252, 247, 237), -- #FCF7ED job cards, list rows
	lavender = Color3.fromRGB(238, 230, 243), -- #EEE6F3 window surfaces
	lavenderDeep = Color3.fromRGB(226, 214, 236), -- window headers, footers, selected rows
	ink = Color3.fromRGB(73, 55, 80), -- #493750 objectives, prices, big values
	ink2 = Color3.fromRGB(116, 97, 125), -- #74617D routes, labels, explanations
	sage = Color3.fromRGB(229, 237, 206), -- #E5EDCE the main action (ACCEPT, TAKE OUT)
	violet = Color3.fromRGB(132, 102, 153), -- #846699 crew / GPS identity, key chips
	line = Color3.fromRGB(205, 190, 214), -- perforations, dashed separators, thin strokes
	shadow = Color3.fromRGB(58, 40, 70), -- the soft drop shadow under paper
	danger = Color3.fromRGB(196, 72, 84), -- warnings (always with an icon or text, never colour alone)
	tags = { -- the consumable tags, alternating
		Color3.fromRGB(240, 232, 248),
		Color3.fromRGB(250, 240, 222),
		Color3.fromRGB(228, 240, 214),
		Color3.fromRGB(248, 226, 232),
		Color3.fromRGB(224, 236, 246),
	},
}

function Theme.textOn(color: Color3): Color3
	local function linear(v: number): number
		return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	local l = 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
	local dark = Color3.fromRGB(9, 14, 11)
	-- Compare both real foreground colors, rather than assuming pure black.
	local dl = 0.2126 * linear(dark.R) + 0.7152 * linear(dark.G) + 0.0722 * linear(dark.B)
	return if (l + 0.05) / (dl + 0.05) >= 1.05 / (l + 0.05) then dark else Color3.new(1, 1, 1)
end

return Theme
