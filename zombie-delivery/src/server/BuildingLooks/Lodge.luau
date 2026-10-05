--!strict
-- Ski Lodge: approved cinematic facade (timber, stone, warm lanterns); static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "lodge", width = 50, depth = 34, height = 18,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 4, 7 } },
	details = {
		{ name = "StonePlinth-1", position = { -14.1, 1.2, -17.3 }, size = { 21.8, 2.4, 0.6 }, color = { 96, 98, 100 }, material = "Slate" },
		{ name = "StonePlinth1", position = { 14.1, 1.2, -17.3 }, size = { 21.8, 2.4, 0.6 }, color = { 96, 98, 100 }, material = "Slate" },
		{ name = "CornerPost-1", position = { -24.6, 9, -17.4 }, size = { 1.2, 18, 1 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "CornerPost1", position = { 24.6, 9, -17.4 }, size = { 1.2, 18, 1 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "TimberBeam", position = { 0, 13.5, -17.3 }, size = { 50, 0.8, 0.5 }, color = { 90, 62, 44 }, material = "WoodPlanks" },
		{ name = "TimberPost-1", position = { -8.3, 10.2, -17.3 }, size = { 0.8, 15.6, 0.5 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "TimberPost1", position = { 8.3, 10.2, -17.3 }, size = { 0.8, 15.6, 0.5 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "DoorJamb-1", position = { -2.4, 3.8, -17.4 }, size = { 0.6, 7.6, 0.6 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "DoorJamb1", position = { 2.4, 3.8, -17.4 }, size = { 0.6, 7.6, 0.6 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "DoorHeader", position = { 0, 7.9, -17.4 }, size = { 5.4, 0.6, 0.6 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "PorchCanopy", position = { 0, 9.6, -19 }, size = { 9, 0.5, 3.6 }, color = { 90, 62, 44 }, material = "WoodPlanks" },
		{ name = "CanopyArm-1", position = { -4, 9.1, -18.9 }, size = { 0.4, 0.5, 3.4 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "CanopyArm1", position = { 4, 9.1, -18.9 }, size = { 0.4, 0.5, 3.4 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "CanopyRedEdge", position = { 0, 9.6, -20.86 }, size = { 9, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "PorchLantern", position = { 0, 8.6, -19.5 }, size = { 0.8, 1, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 26 },
		{ name = "WindowCap-1", position = { -16.67, 11.7, -17.4 }, size = { 5.2, 0.5, 0.6 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "WindowSill-1", position = { -16.67, 8.15, -17.45 }, size = { 5.2, 0.4, 0.8 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "Shutter-1_0", position = { -19.57, 9.9, -17.2 }, size = { 1.6, 3, 0.2 }, color = { 58, 72, 60 }, material = "WoodPlanks" },
		{ name = "Shutter-1_1", position = { -13.77, 9.9, -17.2 }, size = { 1.6, 3, 0.2 }, color = { 58, 72, 60 }, material = "WoodPlanks" },
		{ name = "WindowCap1", position = { 16.67, 11.7, -17.4 }, size = { 5.2, 0.5, 0.6 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "WindowSill1", position = { 16.67, 8.15, -17.45 }, size = { 5.2, 0.4, 0.8 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "Shutter1_0", position = { 13.77, 9.9, -17.2 }, size = { 1.6, 3, 0.2 }, color = { 58, 72, 60 }, material = "WoodPlanks" },
		{ name = "Shutter1_1", position = { 19.57, 9.9, -17.2 }, size = { 1.6, 3, 0.2 }, color = { 58, 72, 60 }, material = "WoodPlanks" },
		{ name = "LoftWindow-1", position = { -16.67, 15.6, -17.15 }, size = { 3.2, 2.4, 0.25 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15, night = true },
		{ name = "LoftWindow1", position = { 16.67, 15.6, -17.15 }, size = { 3.2, 2.4, 0.25 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15, night = true },
		{ name = "WallLantern-1", position = { -6, 6.5, -17.5 }, size = { 0.6, 0.9, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "WallLantern1", position = { 6, 6.5, -17.5 }, size = { 0.6, 0.9, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 22 },
		{ name = "RentalsPlate", position = { -10.8, 5, -17.15 }, size = { 3.6, 1, 0.12 }, color = { 90, 62, 44 }, material = "WoodPlanks", label = "SKI RENTALS" },
		{ name = "LiftPlate", position = { 10.8, 5, -17.15 }, size = { 3.6, 1, 0.12 }, color = { 90, 62, 44 }, material = "WoodPlanks", label = "LIFT PASSES" },
	},
} :: Kit.Blueprint
