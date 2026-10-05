--!strict
-- Lighthouse Point keeper's cottage: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "lighthouse", width = 20, depth = 14, height = 9,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { -4, 3.6, 6.6 } },
	details = {
		{ name = "DoorJamb-1", position = { -6.05, 3.5, -7.25 }, size = { 0.4, 7, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "DoorJamb1", position = { -1.95, 3.5, -7.25 }, size = { 0.4, 7, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "DoorHeader", position = { -4, 7, -7.25 }, size = { 4.6, 0.4, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "DoorHood", position = { -4, 7.8, -8 }, size = { 5, 0.3, 1.6 }, color = { 150, 40, 36 }, material = "Metal" },
		{ name = "ShipLantern", position = { -6.9, 5.6, -7.5 }, size = { 0.6, 0.9, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 18 },
		{ name = "LanternBracket", position = { -6.9, 6.15, -7.3 }, size = { 0.15, 0.15, 0.6 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Shutter-1", position = { 1.2, 5, -7.2 }, size = { 1.4, 3.2, 0.15 }, color = { 40, 70, 110 }, material = "WoodPlanks" },
		{ name = "Shutter1", position = { 6.8, 5, -7.2 }, size = { 1.4, 3.2, 0.15 }, color = { 40, 70, 110 }, material = "WoodPlanks" },
		{ name = "WindowCap", position = { 4, 6.75, -7.3 }, size = { 4.8, 0.3, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "WindowSill", position = { 4, 3.3, -7.35 }, size = { 4.8, 0.3, 0.6 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "WindowMullion", position = { 4, 5, -7.33 }, size = { 0.12, 3, 0.1 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "WindowTransom", position = { 4, 5, -7.33 }, size = { 4, 0.12, 0.1 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "LifeRing", position = { 10.15, 5.2, -4 }, size = { 0.2, 1.6, 1.6 }, color = { 196, 40, 36 }, material = "SmoothPlastic", shape = "Cylinder" },
		{ name = "LifeRingHole", position = { 10.15, 5.2, -4 }, size = { 0.3, 0.8, 0.8 }, color = { 236, 232, 220 }, material = "SmoothPlastic", shape = "Cylinder" },
		{ name = "CornerBoard-1", position = { -9.65, 4.5, -7.25 }, size = { 0.7, 9, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "CornerBoard1", position = { 9.65, 4.5, -7.25 }, size = { 0.7, 9, 0.5 }, color = { 236, 232, 220 }, material = "Wood" },
		{ name = "StonePlinth-1", position = { -8.15, 0.5, -7.2 }, size = { 3.7, 1, 0.4 }, color = { 120, 116, 110 }, material = "Slate" },
		{ name = "StonePlinth1", position = { 4.15, 0.5, -7.2 }, size = { 11.7, 1, 0.4 }, color = { 120, 116, 110 }, material = "Slate" },
		{ name = "EaveTrim", position = { 0, 8.9, -8.1 }, size = { 22, 0.4, 0.2 }, color = { 236, 232, 220 }, material = "WoodPlanks" },
		{ name = "KeeperPlate", position = { 4, 8, -7.06 }, size = { 3.2, 0.8, 0.1 }, color = { 40, 70, 110 }, material = "Metal", label = "KEEPER" },
		{ name = "Downpipe", position = { -9.1, 4.3, -7.2 }, size = { 0.25, 8.6, 0.25 }, color = { 38, 43, 47 }, material = "Metal" },
	},
} :: Kit.Blueprint
