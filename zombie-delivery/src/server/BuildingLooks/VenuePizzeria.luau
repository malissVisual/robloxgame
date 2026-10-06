--!strict
-- Luigi's Pizza (Map.Venues "luigis", 5.3): the storefront (Kit.storefront) under a red and white awning, the brick
-- oven glowing inside, its chimney and a big pizza on the roof. Decoration only; World builds the shell and the board.
local Kit = require(script.Parent.Kit)

local BRICK, EMBER, CRUST, SAUCE = { 150, 70, 50 }, { 255, 140, 60 }, { 226, 176, 96 }, { 186, 48, 36 }

return Kit.storefront({
	id = "venue_pizzeria",
	awning = { 178, 40, 36 },
	stripe = { 236, 232, 224 },
	trim = { 60, 48, 40 },
	counter = { 120, 84, 56 },
	menu = "PIZZA · CALZONE · SODA",
	poster = "HOT PIZZA",
	extras = {
		{ name = "Oven", position = { 9, 2.25, 9 }, size = { 6, 4.5, 3.6 }, color = BRICK, material = "Brick" },
		{ name = "OvenMouth", position = { 9, 2.2, 7.15 }, size = { 2.6, 1.6, 0.1 }, color = EMBER, material = "Glass", night = true },
		{ name = "Chimney", position = { 9, 14.5, 9 }, size = { 2, 5, 2 }, color = BRICK, material = "Brick" },
		{ name = "ChimneyCap", position = { 9, 17.15, 9 }, size = { 2.6, 0.3, 2.6 }, color = { 60, 60, 62 }, material = "Metal" },
		{ name = "RoofPizza", position = { -4, 15.4, -2 }, size = { 0.4, 5, 5 }, color = CRUST, material = "SmoothPlastic", rotation = { 0, 90, 0 }, shape = "Cylinder" },
		{ name = "RoofPizzaSauce", position = { -4, 15.4, -2.25 }, size = { 0.1, 4.2, 4.2 }, color = SAUCE, material = "SmoothPlastic", rotation = { 0, 90, 0 }, shape = "Cylinder" },
	},
})
