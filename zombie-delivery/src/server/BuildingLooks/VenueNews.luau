--!strict
-- The Daily Undead (Map.Venues "dailyundead", 5.3): the print shop and newsstand (Kit.storefront) under a black and red
-- awning, a yellow newspaper box on the walk left of the door, bundles of the morning paper inside, the press's vent
-- on the roof. Decoration only.
local Kit = require(script.Parent.Kit)

local BOX, PAPER, DARK = { 220, 180, 40 }, { 230, 226, 214 }, { 60, 60, 64 }

return Kit.storefront({
	id = "venue_news",
	awning = { 30, 30, 32 },
	stripe = { 200, 40, 36 },
	trim = DARK,
	counter = { 80, 80, 84 },
	menu = "MORNING EDITION · 1 $",
	poster = "EXTRA! EXTRA!",
	extras = {
		{ name = "NewsBox", position = { -11.5, 1.6, -13.5 }, size = { 2, 3.2, 1.8 }, color = BOX, material = "Metal" },
		{ name = "NewsBoxWindow", position = { -11.5, 2.4, -14.45 }, size = { 1.6, 1, 0.1 }, color = PAPER, material = "Glass", label = "NEWS", textColor = { 30, 30, 32 } },
		{ name = "Bundles", position = { 9, 1, 9 }, size = { 4, 2, 3 }, color = PAPER, material = "SmoothPlastic" },
		{ name = "BundleTie", position = { 9, 1, 7.48 }, size = { 0.2, 2.02, 0.05 }, color = { 180, 40, 36 }, material = "SmoothPlastic" },
		{ name = "PressVent", position = { -8, 14, 7 }, size = { 3, 2, 3 }, color = DARK, material = "Metal" },
		{ name = "PressStack", position = { -8, 15.75, 7 }, size = { 1.2, 1.5, 1.2 }, color = DARK, material = "Metal" },
	},
})
