--!strict
-- Train Yard office: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "trainyard", width = 26, depth = 16, height = 9,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 5, 6.8 } },
	details = {
		{ name = "DoorJamb-1", position = { -2.75, 3.4, -8.3 }, size = { 0.4, 6.8, 0.5 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DoorJamb1", position = { 2.75, 3.4, -8.3 }, size = { 0.4, 6.8, 0.5 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "Window-1", position = { -8.5, 4.6, -8.15 }, size = { 6, 3.2, 0.25 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15, night = true },
		{ name = "Window1", position = { 8.5, 4.6, -8.15 }, size = { 6, 3.2, 0.25 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15, night = true },
		{ name = "WindowCap-1", position = { -8.5, 6.35, -8.35 }, size = { 6.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowCap1", position = { 8.5, 6.35, -8.35 }, size = { 6.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowSill-1", position = { -8.5, 2.85, -8.4 }, size = { 6.6, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WindowSill1", position = { 8.5, 2.85, -8.4 }, size = { 6.6, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WindowMullion-1", position = { -8.5, 4.6, -8.32 }, size = { 0.14, 3.2, 0.1 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowMullion1", position = { 8.5, 4.6, -8.32 }, size = { 0.14, 3.2, 0.1 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "CornerPilaster-1", position = { -12.6, 4.5, -8.3 }, size = { 0.8, 9, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CornerPilaster1", position = { 12.6, 4.5, -8.3 }, size = { 0.8, 9, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "RoofCoping", position = { 0, 9.5, -9.2 }, size = { 28, 0.5, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RedLine", position = { 0, 8.92, -8.08 }, size = { 26, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "WallLamp", position = { 11.3, 7.3, -8.4 }, size = { 0.8, 0.5, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 24 },
		{ name = "FreightPlate", position = { 8.5, 1.6, -8.1 }, size = { 5, 1, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "FREIGHT  >" },
		{ name = "MasterPlate", position = { -8.5, 1.6, -8.1 }, size = { 5, 1, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "YARD MASTER" },
		{ name = "ClockRim", position = { -12.6, 8.1, -9.65 }, size = { 0.2, 2.2, 2.2 }, color = { 38, 43, 47 }, material = "Metal", shape = "Cylinder" },
		{ name = "ClockFace", position = { -12.6, 8.1, -9.65 }, size = { 0.3, 1.9, 1.9 }, color = { 232, 230, 222 }, material = "SmoothPlastic", shape = "Cylinder" },
		{ name = "ClockHands", position = { -12.6, 8.4, -9.65 }, size = { 0.34, 0.75, 0.1 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RoofVent", position = { -6, 11, 2 }, size = { 3, 2, 3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "StovePipe", position = { 8, 11.5, 4 }, size = { 0.8, 3, 0.8 }, color = { 38, 43, 47 }, material = "Metal" },
	},
} :: Kit.Blueprint
