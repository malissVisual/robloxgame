--!strict
-- Harbor Fuel Depot office: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "fueldepot", width = 24, depth = 14, height = 9,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { -6, 3.6, 7.2 } },
	details = {
		{ name = "OfficeFascia", position = { 0, 8.4, -7.45 }, size = { 24.4, 1, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "OfficeRedEdge", position = { 0, 7.84, -7.76 }, size = { 24.4, 0.12, 0.12 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "DoorCanopy", position = { -6, 7.6, -8.4 }, size = { 6, 0.35, 2.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DoorJamb-1", position = { -8.05, 3.6, -7.3 }, size = { 0.35, 7.2, 0.4 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DoorJamb1", position = { -3.95, 3.6, -7.3 }, size = { 0.35, 7.2, 0.4 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "CanopyLight", position = { -6, 7.37, -8.6 }, size = { 3, 0.12, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 16 },
		{ name = "WindowCap", position = { 4, 6.75, -7.4 }, size = { 8.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowSill", position = { 4, 3.3, -7.45 }, size = { 8.6, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WindowMullion-1", position = { 1.33, 5, -7.33 }, size = { 0.16, 3, 0.12 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowMullion1", position = { 6.67, 5, -7.33 }, size = { 0.16, 3, 0.12 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "CornerPilaster-1", position = { -11.8, 4.5, -7.3 }, size = { 0.8, 9, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CornerPilaster1", position = { 11.8, 4.5, -7.3 }, size = { 0.8, 9, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "NoSmokingPlate", position = { -9.8, 4.8, -7.1 }, size = { 2.8, 1.6, 0.12 }, color = { 153, 49, 43 }, material = "Metal", label = "NO SMOKING" },
		{ name = "OfficePlate", position = { 4, 8.4, -7.76 }, size = { 6, 0.8, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "DEPOT OFFICE" },
		{ name = "WallLamp", position = { 10.2, 7.3, -7.6 }, size = { 0.8, 0.5, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 18 },
		{ name = "RoofExtract", position = { 6, 10.6, 2 }, size = { 3, 2, 3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "ExtractCap", position = { 6, 11.75, 2 }, size = { 3.6, 0.3, 3.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_0", position = { -12.15, 4.5, -3 }, size = { 0.3, 9, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_0", position = { 12.15, 4.5, -3 }, size = { 0.3, 9, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_1", position = { -12.15, 4.5, 3 }, size = { 0.3, 9, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_1", position = { 12.15, 4.5, 3 }, size = { 0.3, 9, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
	},
} :: Kit.Blueprint
