--!strict
-- Grind House (Map.Venues "grindhouse", 5.3): the café's storefront (Kit.storefront) under a green and cream awning,
-- a big coffee cup on the roof, a little table outside by the left window. Decoration only.
local Kit = require(script.Parent.Kit)

local CUP, COFFEE, IRON = { 240, 238, 232 }, { 92, 58, 36 }, { 40, 40, 42 }
local UP = { 0, 0, 90 } -- a cylinder standing up

return Kit.storefront({
	id = "venue_cafe",
	awning = { 44, 84, 70 },
	stripe = { 232, 226, 210 },
	trim = { 70, 52, 40 },
	counter = { 96, 66, 46 },
	menu = "COFFEE · TEA · PASTRIES",
	poster = "COFFEE",
	extras = {
		{ name = "RoofCup", position = { 0, 15, 3 }, size = { 4, 5, 5 }, color = CUP, material = "SmoothPlastic", rotation = UP, shape = "Cylinder" },
		{ name = "RoofCoffee", position = { 0, 17.02, 3 }, size = { 0.1, 4.4, 4.4 }, color = COFFEE, material = "SmoothPlastic", rotation = UP, shape = "Cylinder" },
		{ name = "RoofCupHandle", position = { 2.9, 15, 3 }, size = { 0.6, 2.4, 0.6 }, color = CUP, material = "SmoothPlastic" },
		{ name = "TableTop", position = { -11, 2.5, -14 }, size = { 0.2, 2.6, 2.6 }, color = IRON, material = "Metal", rotation = UP, shape = "Cylinder" },
		{ name = "TableLeg", position = { -11, 1.2, -14 }, size = { 0.3, 2.4, 0.3 }, color = IRON, material = "Metal" },
	},
})
