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
Theme.Radius = 8
Theme.PanelTransparency = 0.06
Theme.Font = Enum.Font.GothamMedium
Theme.HeadingFont = Enum.Font.GothamBold
Theme.DisplayFont = Enum.Font.GothamBlack

-- Optional Roblox assets. Empty IDs keep the live city flyover and native wordmark.
-- The ids are pasted in shared/Icons.luau (zombie_delivery_logo, menu_background), the one place for every picture.
Theme.Images = {
	logo = Icons.get("zombie_delivery_logo") or "",
	menuBackground = Icons.get("menu_background") or "",
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
