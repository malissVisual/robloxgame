--!strict
-- Radio Station studio: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "radio", width = 30, depth = 20, height = 12,
	details = {
		{ name = "StudioDoor", position = { -10, 3.75, -10.1 }, size = { 4, 7.5, 0.2 }, color = { 52, 58, 62 }, material = "Metal" },
		{ name = "DoorJamb-1", position = { -12.2, 4, -10.2 }, size = { 0.4, 8, 0.45 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DoorJamb1", position = { -7.8, 4, -10.2 }, size = { 0.4, 8, 0.45 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DoorHeader", position = { -10, 8, -10.2 }, size = { 5, 0.4, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DoorCanopy", position = { -10, 8.6, -11.2 }, size = { 6, 0.35, 2.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CanopyLight", position = { -10, 8.37, -11.4 }, size = { 3, 0.12, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 18 },
		{ name = "OnAirSign", position = { -10, 9.75, -10.15 }, size = { 4.4, 1.1, 0.25 }, color = { 38, 43, 47 }, material = "Metal", label = "ON AIR", textColor = { 226, 70, 56 } },
		{ name = "StudioWindow", position = { 5, 6.2, -10.12 }, size = { 14, 2.6, 0.25 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15, night = true },
		{ name = "StudioWindowCap", position = { 5, 7.65, -10.3 }, size = { 14.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "StudioWindowSill", position = { 5, 4.75, -10.35 }, size = { 14.6, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "StudioMullion0", position = { 0.33, 6.2, -10.3 }, size = { 0.16, 2.6, 0.12 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "StudioMullion1", position = { 9.67, 6.2, -10.3 }, size = { 0.16, 2.6, 0.12 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "StudioFascia", position = { 0, 11.4, -10.3 }, size = { 30.4, 1.2, 0.6 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "StudioRedLine", position = { 0, 11, -10.66 }, size = { 30.4, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "FrequencyPlate", position = { 5, 11.5, -10.68 }, size = { 8, 0.8, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "101.3 FM  /  EMERGENCY" },
		{ name = "CornerPilaster-1", position = { -14.6, 6, -10.3 }, size = { 0.8, 12, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CornerPilaster1", position = { 14.6, 6, -10.3 }, size = { 0.8, 12, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CableRiser", position = { -4.5, 6, -10.25 }, size = { 0.5, 12, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WallLamp", position = { 13.2, 8.2, -10.5 }, size = { 0.8, 0.5, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 20 },
		{ name = "DishMount", position = { 6, 13, 2 }, size = { 0.6, 2, 0.6 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Dish", position = { 6, 15, 2 }, size = { 0.4, 4, 4 }, color = { 214, 216, 212 }, material = "SmoothPlastic", shape = "Cylinder" },
		{ name = "DishFeed", position = { 6.9, 15, 2 }, size = { 1.4, 0.2, 0.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RoofExtract", position = { -8, 13, 4 }, size = { 3, 2, 3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "ExtractCap", position = { -8, 14.15, 4 }, size = { 3.6, 0.3, 3.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "AntennaWhip", position = { 12, 14.5, 6 }, size = { 0.3, 5, 0.3 }, color = { 202, 205, 200 }, material = "Metal" },
	},
} :: Kit.Blueprint
