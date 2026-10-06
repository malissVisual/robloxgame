--!strict
-- Volt Electronics (Map.Venues "volt", 5.3): the storefront (Kit.storefront) under a blue awning, a wall of screens
-- inside that glows at night, an antenna mast and a dish on the roof. Decoration only.
local Kit = require(script.Parent.Kit)

local STEEL, SCREEN = { 170, 174, 180 }, { 60, 120, 160 }

return Kit.storefront({
	id = "venue_electronics",
	awning = { 30, 90, 140 },
	stripe = { 220, 220, 226 },
	trim = { 40, 44, 50 },
	counter = { 50, 54, 60 },
	menu = "RADIOS · BATTERIES · PARTS",
	poster = "WE FIX RADIOS",
	extras = {
		{ name = "ScreenWall", position = { 13.9, 6, 3 }, size = { 0.2, 3, 6 }, color = SCREEN, material = "Glass", night = true },
		{ name = "AntennaMast", position = { -10, 15.5, 8 }, size = { 0.3, 5, 0.3 }, color = STEEL, material = "Metal" },
		{ name = "AntennaBar", position = { -10, 17.2, 8 }, size = { 3, 0.15, 0.15 }, color = STEEL, material = "Metal" },
		{ name = "Dish", position = { 6, 14.6, 8 }, size = { 0.3, 3, 3 }, color = { 220, 220, 224 }, material = "Metal", rotation = { 0, 60, 30 }, shape = "Cylinder" },
	},
})
