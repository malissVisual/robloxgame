--!strict
-- Wok Dead (Map.Venues "wokdead", 5.3): the noodle bar's storefront (Kit.storefront) under a deep red and gold awning,
-- two red lanterns that glow at night at its ends, the kitchen's steam stack on the roof. Decoration only.
local Kit = require(script.Parent.Kit)

local LANTERN, CORD = { 220, 60, 40 }, { 30, 28, 28 }
local UP = { 0, 0, 90 } -- a cylinder standing up

return Kit.storefront({
	id = "venue_noodles",
	awning = { 150, 30, 34 },
	stripe = { 226, 186, 70 },
	trim = { 40, 36, 34 },
	counter = { 90, 50, 40 },
	menu = "NOODLES · DUMPLINGS · TEA",
	poster = "WOK HOT",
	extras = {
		{ name = "LanternL", position = { -13, 7.4, -14.6 }, size = { 1.6, 1.4, 1.4 }, color = LANTERN, material = "Glass", rotation = UP, shape = "Cylinder", night = true },
		{ name = "LanternR", position = { 13, 7.4, -14.6 }, size = { 1.6, 1.4, 1.4 }, color = LANTERN, material = "Glass", rotation = UP, shape = "Cylinder", night = true },
		{ name = "LanternCordL", position = { -13, 8.65, -14.6 }, size = { 0.1, 1.1, 0.1 }, color = CORD, material = "Metal" },
		{ name = "LanternCordR", position = { 13, 8.65, -14.6 }, size = { 0.1, 1.1, 0.1 }, color = CORD, material = "Metal" },
		{ name = "SteamStack", position = { -8, 14.5, 8 }, size = { 1.6, 5, 1.6 }, color = { 140, 140, 144 }, material = "Metal" },
	},
})
