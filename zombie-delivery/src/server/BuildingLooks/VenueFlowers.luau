--!strict
-- Bloom (Map.Venues "bloom", 5.3): the flower shop's storefront (Kit.storefront) under a pink and white awning, three
-- buckets of flowers on the walk under the left window. Decoration only.
local Kit = require(script.Parent.Kit)

local POT = { 120, 80, 60 }
local UP = { 0, 0, 90 } -- a cylinder standing up

local extras: { Kit.Detail } = {}
local BLOOMS: { { number } } = { { 214, 50, 60 }, { 240, 200, 60 }, { 150, 80, 190 } }
for n, x in { -12.2, -9.6, -7 } do
	table.insert(extras, { name = "Bucket" .. n, position = { x, 0.8, -13.2 }, size = { 1.6, 1.6, 1.6 }, color = POT, material = "Metal", rotation = UP, shape = "Cylinder" })
	table.insert(extras, { name = "Flowers" .. n, position = { x, 2.1, -13.2 }, size = { 1, 1.9, 1.9 }, color = BLOOMS[n], material = "SmoothPlastic", rotation = UP, shape = "Cylinder" })
end

return Kit.storefront({
	id = "venue_flowers",
	awning = { 214, 110, 150 },
	stripe = { 250, 240, 244 },
	trim = { 90, 110, 80 },
	counter = { 120, 150, 100 },
	menu = "BOUQUETS · PLANTS · WREATHS",
	poster = "FRESH FLOWERS",
	extras = extras,
})
