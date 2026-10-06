--!strict
-- Daily Bread Bakery (Map.Venues "dailybread", 5.3): the storefront (Kit.storefront) under a warm tan awning, the
-- bread oven inside with its chimney, a stand of loaves under the left window. Decoration only.
local Kit = require(script.Parent.Kit)

local BRICK, WOOD, LOAF = { 170, 120, 90 }, { 150, 110, 70 }, { 196, 136, 70 }

return Kit.storefront({
	id = "venue_bakery",
	awning = { 196, 150, 92 },
	stripe = { 250, 240, 220 },
	trim = { 110, 80, 52 },
	counter = WOOD,
	menu = "BREAD · ROLLS · CAKES",
	poster = "FRESH BREAD",
	extras = {
		{ name = "BreadOven", position = { 9, 2.5, 9 }, size = { 7, 5, 3.4 }, color = BRICK, material = "Brick" },
		{ name = "OvenDoor", position = { 9, 2.2, 7.25 }, size = { 3, 1.4, 0.1 }, color = { 255, 150, 70 }, material = "Glass", night = true },
		{ name = "Chimney", position = { 9, 14.5, 9 }, size = { 2, 5, 2 }, color = BRICK, material = "Brick" },
		{ name = "ChimneyCap", position = { 9, 17.15, 9 }, size = { 2.6, 0.3, 2.6 }, color = { 60, 60, 62 }, material = "Metal" },
		{ name = "BreadStand", position = { -10, 1.1, -13.1 }, size = { 6, 2.2, 1.6 }, color = WOOD, material = "WoodPlanks" },
		{ name = "Loaves", position = { -10, 2.45, -13.1 }, size = { 5, 0.5, 1.1 }, color = LOAF, material = "SmoothPlastic" },
	},
})
