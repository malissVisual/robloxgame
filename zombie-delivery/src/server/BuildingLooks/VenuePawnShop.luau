--!strict
-- Second Life Pawn (Map.Venues "secondlife", 5.3): the storefront (Kit.storefront) under a plum and gold awning, the
-- pawnbroker's three gold balls on a rod right of the door, a safe behind the counter. Decoration only.
local Kit = require(script.Parent.Kit)

local GOLD, DARK = { 212, 170, 60 }, { 50, 44, 40 }
local OUT = { 0, 90, 0 } -- a disc facing the street

return Kit.storefront({
	id = "venue_pawnshop",
	awning = { 90, 40, 60 },
	stripe = GOLD,
	trim = DARK,
	counter = { 70, 56, 44 },
	menu = "BUY · SELL · LOANS · AMMO",
	poster = "WE BUY GOLD",
	extras = {
		{ name = "BallRod", position = { 12.6, 11.9, -13.2 }, size = { 0.15, 0.15, 2.4 }, color = DARK, material = "Metal" },
		{ name = "BallTop", position = { 12.6, 11.6, -14.4 }, size = { 1, 1, 1 }, color = GOLD, material = "Metal", rotation = OUT, shape = "Cylinder" },
		{ name = "BallLeft", position = { 12, 10.6, -14.4 }, size = { 1, 1, 1 }, color = GOLD, material = "Metal", rotation = OUT, shape = "Cylinder" },
		{ name = "BallRight", position = { 13.2, 10.6, -14.4 }, size = { 1, 1, 1 }, color = GOLD, material = "Metal", rotation = OUT, shape = "Cylinder" },
		{ name = "Safe", position = { 10, 2, 9 }, size = { 3, 4, 3 }, color = { 60, 64, 70 }, material = "Metal" },
	},
})
