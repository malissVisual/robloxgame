--!strict
-- Bolt & Nail Hardware (Map.Venues "boltnail", 5.3): the storefront (Kit.storefront) under an orange and black awning,
-- a stack of planks on the walk left of the door, a ladder leaning right of it, the tool board inside. Decoration only.
local Kit = require(script.Parent.Kit)

local PLANK, LADDER, DARK = { 176, 136, 90 }, { 200, 160, 60 }, { 40, 40, 44 }

return Kit.storefront({
	id = "venue_hardware",
	awning = { 200, 110, 30 },
	stripe = DARK,
	trim = { 70, 70, 74 },
	counter = { 110, 90, 60 },
	menu = "TOOLS · NAILS · PLANKS · PAINT",
	poster = "OPEN 7 DAYS",
	extras = {
		{ name = "PlankStack", position = { -11, 0.9, -13.8 }, size = { 5, 1.8, 2 }, color = PLANK, material = "WoodPlanks" },
		{ name = "LadderRailL", position = { 10.2, 3.6, -12.6 }, size = { 0.25, 7.2, 0.25 }, color = LADDER, material = "Metal" },
		{ name = "LadderRailR", position = { 12, 3.6, -12.6 }, size = { 0.25, 7.2, 0.25 }, color = LADDER, material = "Metal" },
		{ name = "LadderRung1", position = { 11.1, 2, -12.6 }, size = { 1.8, 0.2, 0.2 }, color = LADDER, material = "Metal" },
		{ name = "LadderRung2", position = { 11.1, 4, -12.6 }, size = { 1.8, 0.2, 0.2 }, color = LADDER, material = "Metal" },
		{ name = "LadderRung3", position = { 11.1, 6, -12.6 }, size = { 1.8, 0.2, 0.2 }, color = LADDER, material = "Metal" },
		{ name = "ToolBoard", position = { 13.9, 6, 3 }, size = { 0.2, 4, 8 }, color = { 150, 120, 80 }, material = "WoodPlanks" },
	},
})
