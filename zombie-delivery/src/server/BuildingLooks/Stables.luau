--!strict
-- Riverside Riding School club house: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "stables", width = 28, depth = 18, height = 10, interior = true,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 4, 7 } },
	details = {
		{ name = "CornerBoard-1", position = { -13.7, 5, -9.3 }, size = { 0.7, 10, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "CornerBoard1", position = { 13.7, 5, -9.3 }, size = { 0.7, 10, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "StonePlinth-1", position = { -8.3, 0.4, -9.2 }, size = { 11.4, 0.8, 0.4 }, color = { 96, 98, 100 }, material = "Slate" },
		{ name = "StonePlinth1", position = { 8.3, 0.4, -9.2 }, size = { 11.4, 0.8, 0.4 }, color = { 96, 98, 100 }, material = "Slate" },
		{ name = "DoorJamb-1", position = { -2.3, 3.65, -9.45 }, size = { 0.4, 7.3, 0.5 }, color = { 50, 96, 64 }, material = "Wood" },
		{ name = "DoorJamb1", position = { 2.3, 3.65, -9.45 }, size = { 0.4, 7.3, 0.5 }, color = { 50, 96, 64 }, material = "Wood" },
		{ name = "DoorHeader", position = { 0, 7.25, -9.45 }, size = { 4.8, 0.35, 0.5 }, color = { 50, 96, 64 }, material = "Wood" },
		{ name = "Shutter-1_0", position = { -11, 5.5, -9.25 }, size = { 1.4, 3.2, 0.2 }, color = { 50, 96, 64 }, material = "WoodPlanks" },
		{ name = "Shutter-1_1", position = { -5, 5.5, -9.25 }, size = { 1.4, 3.2, 0.2 }, color = { 50, 96, 64 }, material = "WoodPlanks" },
		{ name = "WindowCap-1", position = { -8, 7.2, -9.35 }, size = { 5.2, 0.3, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "FlowerBox-1", position = { -8, 3.6, -9.55 }, size = { 4.8, 0.8, 0.8 }, color = { 90, 62, 44 }, material = "WoodPlanks" },
		{ name = "Geraniums-1", position = { -8, 4.15, -9.55 }, size = { 4.4, 0.4, 0.6 }, color = { 153, 49, 43 }, material = "SmoothPlastic" },
		{ name = "Shutter1_0", position = { 5, 5.5, -9.25 }, size = { 1.4, 3.2, 0.2 }, color = { 50, 96, 64 }, material = "WoodPlanks" },
		{ name = "Shutter1_1", position = { 11, 5.5, -9.25 }, size = { 1.4, 3.2, 0.2 }, color = { 50, 96, 64 }, material = "WoodPlanks" },
		{ name = "WindowCap1", position = { 8, 7.2, -9.35 }, size = { 5.2, 0.3, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "FlowerBox1", position = { 8, 3.6, -9.55 }, size = { 4.8, 0.8, 0.8 }, color = { 90, 62, 44 }, material = "WoodPlanks" },
		{ name = "Geraniums1", position = { 8, 4.15, -9.55 }, size = { 4.4, 0.4, 0.6 }, color = { 153, 49, 43 }, material = "SmoothPlastic" },
		{ name = "DoorLantern-1", position = { -3.6, 6.2, -9.5 }, size = { 0.6, 0.9, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 20 },
		{ name = "DoorLantern1", position = { 3.6, 6.2, -9.5 }, size = { 0.6, 0.9, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "LessonsPlate", position = { -8, 1.7, -9.1 }, size = { 4, 0.9, 0.12 }, color = { 50, 96, 64 }, material = "WoodPlanks", label = "LESSONS  /  LIVERY" },
		{ name = "MembersPlate", position = { 8, 1.7, -9.1 }, size = { 4, 0.9, 0.12 }, color = { 50, 96, 64 }, material = "WoodPlanks", label = "MEMBERS" },
		{ name = "Chimney", position = { 8, 14.5, 3 }, size = { 1.6, 3, 1.6 }, color = { 110, 66, 54 }, material = "Brick" },
	},
} :: Kit.Blueprint
