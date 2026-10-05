--!strict
-- Water Works pump house: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "waterworks", width = 26, depth = 16, height = 10,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 6, 7 } },
	details = {
		{ name = "DoorJamb-1", position = { -3.25, 3.6, -8.3 }, size = { 0.4, 7.2, 0.5 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DoorJamb1", position = { 3.25, 3.6, -8.3 }, size = { 0.4, 7.2, 0.5 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DoorHeader", position = { 0, 7.18, -8.3 }, size = { 7, 0.35, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowCap1", position = { 8, 6.75, -8.35 }, size = { 5.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowSill1", position = { 8, 3.3, -8.4 }, size = { 5.8, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WindowBar0", position = { 6.75, 5, -8.3 }, size = { 0.14, 3, 0.1 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowBar1", position = { 8, 5, -8.3 }, size = { 0.14, 3, 0.1 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowBar2", position = { 9.25, 5, -8.3 }, size = { 0.14, 3, 0.1 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowRecess-1", position = { -8, 5, -8.15 }, size = { 5, 3, 0.25 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15, night = true },
		{ name = "WindowCap-1", position = { -8, 6.75, -8.35 }, size = { 5.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowSill-1", position = { -8, 3.3, -8.4 }, size = { 5.8, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CornerPilaster-1", position = { -12.6, 5, -8.3 }, size = { 0.8, 10, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CornerPilaster1", position = { 12.6, 5, -8.3 }, size = { 0.8, 10, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "RoofCoping", position = { 0, 10.5, -9.2 }, size = { 28, 0.5, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RedLine", position = { 0, 9.7, -8.1 }, size = { 26, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "WallLamp-1", position = { -11.3, 8.2, -8.4 }, size = { 0.8, 0.5, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 20 },
		{ name = "WallLamp1", position = { 11.3, 8.2, -8.4 }, size = { 0.8, 0.5, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "IntakePlate", position = { -8, 2.3, -8.1 }, size = { 4, 0.9, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "INTAKE  /  PUMPS" },
		{ name = "RoofVent", position = { -6, 12, 2 }, size = { 3, 2, 3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RoofVentCap", position = { -6, 13.15, 2 }, size = { 3.6, 0.3, 3.6 }, color = { 100, 104, 101 }, material = "Metal" },
	},
} :: Kit.Blueprint
