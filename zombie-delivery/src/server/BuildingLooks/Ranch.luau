--!strict
-- Silver Spur Ranch stable: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "ranch", width = 60, depth = 20, height = 11, interior = true,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { -24, 11.2, 8.1 }, { -12, 11.2, 8.1 }, { 0, 11.2, 8.1 }, { 12, 11.2, 8.1 }, { 24, 11.2, 8.1 } },
	details = {
		{ name = "HeaderFascia", position = { 0, 8.6, -10.55 }, size = { 61, 0.9, 0.3 }, color = { 70, 48, 34 }, material = "WoodPlanks" },
		{ name = "HeaderRedLine", position = { 0, 8.25, -10.75 }, size = { 61, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "StallPlate1", position = { -24, 8.75, -10.76 }, size = { 1.6, 0.6, 0.1 }, color = { 228, 224, 212 }, material = "WoodPlanks", label = "01", textColor = { 60, 40, 28 } },
		{ name = "StallPlate2", position = { -12, 8.75, -10.76 }, size = { 1.6, 0.6, 0.1 }, color = { 228, 224, 212 }, material = "WoodPlanks", label = "02", textColor = { 60, 40, 28 } },
		{ name = "StallPlate3", position = { 0, 8.75, -10.76 }, size = { 1.6, 0.6, 0.1 }, color = { 228, 224, 212 }, material = "WoodPlanks", label = "03", textColor = { 60, 40, 28 } },
		{ name = "StallPlate4", position = { 12, 8.75, -10.76 }, size = { 1.6, 0.6, 0.1 }, color = { 228, 224, 212 }, material = "WoodPlanks", label = "04", textColor = { 60, 40, 28 } },
		{ name = "StallPlate5", position = { 24, 8.75, -10.76 }, size = { 1.6, 0.6, 0.1 }, color = { 228, 224, 212 }, material = "WoodPlanks", label = "05", textColor = { 60, 40, 28 } },
		{ name = "PostLantern-1", position = { -18, 6.8, -10.75 }, size = { 0.5, 0.8, 0.5 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 22 },
		{ name = "PostLantern1", position = { 18, 6.8, -10.75 }, size = { 0.5, 0.8, 0.5 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 22 },
		{ name = "PostShoe6_-1", position = { -6, 0.3, -10 }, size = { 0.7, 0.6, 0.95 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PostShoe6_1", position = { 6, 0.3, -10 }, size = { 0.7, 0.6, 0.95 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PostShoe18_-1", position = { -18, 0.3, -10 }, size = { 0.7, 0.6, 0.95 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PostShoe18_1", position = { 18, 0.3, -10 }, size = { 0.7, 0.6, 0.95 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PostShoe30_-1", position = { -30, 0.3, -10 }, size = { 0.7, 0.6, 0.95 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PostShoe30_1", position = { 30, 0.3, -10 }, size = { 0.7, 0.6, 0.95 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Cupola", position = { 0, 12.2, 4 }, size = { 3, 2.4, 3 }, color = { 228, 224, 212 }, material = "WoodPlanks" },
		{ name = "CupolaLouvre", position = { 0, 12.2, 2.45 }, size = { 2.2, 1.4, 0.1 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CupolaRoof", position = { 0, 13.6, 4 }, size = { 3.8, 0.4, 3.8 }, color = { 80, 70, 66 }, material = "Slate" },
		{ name = "VaneMast", position = { 0, 14.8, 4 }, size = { 0.2, 2, 0.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "VaneArrow", position = { 0, 15.4, 4 }, size = { 1.6, 0.15, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
	},
} :: Kit.Blueprint
