--!strict
-- Last Bite Burgers (Map.Venues "lastbite", 5.3): the storefront (Kit.storefront) under a mustard and red awning, a
-- giant burger on the roof, the grill hood over the kitchen. Decoration only.
local Kit = require(script.Parent.Kit)

local BUN, PATTY, CHEESE = { 214, 150, 76 }, { 92, 52, 34 }, { 244, 196, 50 }
local UP = { 0, 0, 90 } -- a cylinder standing up

return Kit.storefront({
	id = "venue_burgers",
	awning = { 214, 160, 40 },
	stripe = { 170, 40, 30 },
	trim = { 50, 50, 54 },
	counter = { 170, 40, 30 },
	menu = "BURGERS · FRIES · SHAKES",
	poster = "OPEN LATE",
	extras = {
		{ name = "BunBottom", position = { 0, 13.7, 2 }, size = { 1.4, 7, 7 }, color = BUN, material = "SmoothPlastic", rotation = UP, shape = "Cylinder" },
		{ name = "Patty", position = { 0, 14.8, 2 }, size = { 0.8, 7.4, 7.4 }, color = PATTY, material = "SmoothPlastic", rotation = UP, shape = "Cylinder" },
		{ name = "Cheese", position = { 0, 15.3, 2 }, size = { 0.2, 7.6, 7.6 }, color = CHEESE, material = "SmoothPlastic", rotation = UP, shape = "Cylinder" },
		{ name = "BunTop", position = { 0, 16.4, 2 }, size = { 2, 7.2, 7.2 }, color = BUN, material = "SmoothPlastic", rotation = UP, shape = "Cylinder" },
		{ name = "GrillHood", position = { 9, 9.2, 9.5 }, size = { 6, 2, 3 }, color = { 160, 164, 168 }, material = "Metal" },
	},
})
