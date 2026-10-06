--!strict
-- Old Farm barn: approved cinematic facade (painted doors, hay hoist); static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "farm", width = 40, depth = 30, height = 18, interior = true,
	details = {
		{ name = "BarnDoorLeaf-1", position = { -3.5, 6, -15.15 }, size = { 7, 12, 0.3 }, color = { 118, 34, 30 }, material = "WoodPlanks" },
		{ name = "BarnDoorLeaf1", position = { 3.5, 6, -15.15 }, size = { 7, 12, 0.3 }, color = { 118, 34, 30 }, material = "WoodPlanks" },
		{ name = "DoorTrim-1", position = { -7.4, 6.4, -15.3 }, size = { 0.8, 12.8, 0.4 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "DoorTrim1", position = { 7.4, 6.4, -15.3 }, size = { 0.8, 12.8, 0.4 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "DoorHeaderTrim", position = { 0, 12.4, -15.3 }, size = { 15.6, 0.8, 0.4 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "DoorStile", position = { 0, 6, -15.35 }, size = { 0.6, 12, 0.25 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "DoorRail-1_0", position = { -3.5, 3.5, -15.35 }, size = { 6.6, 0.5, 0.2 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "DoorRail-1_1", position = { -3.5, 8.5, -15.35 }, size = { 6.6, 0.5, 0.2 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "DoorRail1_0", position = { 3.5, 3.5, -15.35 }, size = { 6.6, 0.5, 0.2 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "DoorRail1_1", position = { 3.5, 8.5, -15.35 }, size = { 6.6, 0.5, 0.2 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "LoftDoor", position = { 0, 15.4, -15.15 }, size = { 5, 3.6, 0.3 }, color = { 118, 34, 30 }, material = "WoodPlanks" },
		{ name = "LoftSill", position = { 0, 13.4, -15.35 }, size = { 5.8, 0.4, 0.5 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "LoftHeader", position = { 0, 17.45, -15.3 }, size = { 5.8, 0.5, 0.4 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "HoistBeam", position = { 0, 17.9, -16.4 }, size = { 0.7, 0.7, 3 }, color = { 84, 60, 42 }, material = "Wood" },
		{ name = "HoistPulley", position = { 0, 17.1, -17.6 }, size = { 0.5, 0.8, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "HoistRope", position = { 0, 15.2, -17.6 }, size = { 0.1, 3, 0.1 }, color = { 170, 150, 110 }, material = "SmoothPlastic" },
		{ name = "BarnLamp-1", position = { -5.5, 13.5, -15.8 }, size = { 1.2, 0.4, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 30 },
		{ name = "BarnLamp1", position = { 5.5, 13.5, -15.8 }, size = { 1.2, 0.4, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "StonePlinth-1", position = { -13.9, 0.7, -15.2 }, size = { 12.2, 1.4, 0.4 }, color = { 110, 108, 104 }, material = "Slate" },
		{ name = "StonePlinth1", position = { 13.9, 0.7, -15.2 }, size = { 12.2, 1.4, 0.4 }, color = { 110, 108, 104 }, material = "Slate" },
		{ name = "CornerBoard-1", position = { -19.7, 9, -15.2 }, size = { 0.8, 18, 0.4 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "CornerBoard1", position = { 19.7, 9, -15.2 }, size = { 0.8, 18, 0.4 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "Batten11_-1", position = { -11.3, 9.7, -15.1 }, size = { 0.3, 16.6, 0.2 }, color = { 100, 30, 26 }, material = "WoodPlanks" },
		{ name = "Batten11_1", position = { 11.3, 9.7, -15.1 }, size = { 0.3, 16.6, 0.2 }, color = { 100, 30, 26 }, material = "WoodPlanks" },
		{ name = "Batten15_-1", position = { -15.6, 9.7, -15.1 }, size = { 0.3, 16.6, 0.2 }, color = { 100, 30, 26 }, material = "WoodPlanks" },
		{ name = "Batten15_1", position = { 15.6, 9.7, -15.1 }, size = { 0.3, 16.6, 0.2 }, color = { 100, 30, 26 }, material = "WoodPlanks" },
		{ name = "EaveTrim", position = { 0, 17.85, -15.1 }, size = { 40.4, 0.3, 0.2 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "StandPlate", position = { -13.9, 4, -15.26 }, size = { 4.4, 1, 0.12 }, color = { 228, 224, 212 }, material = "WoodPlanks", label = "PRODUCE STAND  >", textColor = { 60, 40, 28 } },
		{ name = "FeedPlate", position = { 13.9, 4, -15.26 }, size = { 4.4, 1, 0.12 }, color = { 228, 224, 212 }, material = "WoodPlanks", label = "HAY  /  FEED", textColor = { 60, 40, 28 } },
	},
} :: Kit.Blueprint
