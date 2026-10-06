--!strict
-- Southside Garage: stone piers, a concrete lintel and wall lanterns; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "garage_south", width = 26, depth = 22, height = 11, interior = true,
	-- The openings that stay clear: { center x, width, clear height }.
	entries = { { -6, 10, 9 }, { 6, 10, 9 } },
	details = {
		{ name = "LintelFascia", position = { 0, 10.3, -11.15 }, size = { 26, 1.4, 0.3 }, color = { 132, 130, 124 }, material = "Concrete" },
		{ name = "RoofEdgeCap", position = { 0, 11.5, -11.65 }, size = { 27.2, 0.5, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DoorCanopy", position = { 0, 9.45, -12.3 }, size = { 25, 0.35, 2.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CanopyRedEdge", position = { 0, 9.45, -13.45 }, size = { 25, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "DoorNumber1", position = { -6, 10.3, -11.36 }, size = { 2.6, 0.9, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "01" },
		{ name = "DoorLamp1", position = { -6, 9.2, -12.3 }, size = { 3, 0.14, 0.5 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 18 },
		{ name = "DoorNumber2", position = { 6, 10.3, -11.36 }, size = { 2.6, 0.9, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "02" },
		{ name = "DoorLamp2", position = { 6, 9.2, -12.3 }, size = { 3, 0.14, 0.5 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 18 },
		{ name = "DoorJamb0", position = { -12, 4.5, -11.2 }, size = { 1.6, 9, 0.4 }, color = { 132, 130, 124 }, material = "Concrete" },
		{ name = "BumperGuard0", position = { -12, 1.1, -11.3 }, size = { 1.8, 2.2, 0.6 }, color = { 196, 158, 52 }, material = "SmoothPlastic" },
		{ name = "DoorJamb1", position = { 0, 4.5, -11.2 }, size = { 1.6, 9, 0.4 }, color = { 132, 130, 124 }, material = "Concrete" },
		{ name = "BumperGuard1", position = { 0, 1.1, -11.3 }, size = { 1.8, 2.2, 0.6 }, color = { 196, 158, 52 }, material = "SmoothPlastic" },
		{ name = "DoorJamb2", position = { 12, 4.5, -11.2 }, size = { 1.6, 9, 0.4 }, color = { 132, 130, 124 }, material = "Concrete" },
		{ name = "BumperGuard2", position = { 12, 1.1, -11.3 }, size = { 1.8, 2.2, 0.6 }, color = { 196, 158, 52 }, material = "SmoothPlastic" },
		{ name = "CornerColumn-1", position = { -13.4, 5.5, -10.8 }, size = { 0.8, 11, 1.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "SideRib-1_0", position = { -13.15, 5.3, -5.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_1", position = { -13.15, 5.3, 0 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_2", position = { -13.15, 5.3, 5.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "CornerColumn1", position = { 13.4, 5.5, -10.8 }, size = { 0.8, 11, 1.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "SideRib1_0", position = { 13.15, 5.3, -5.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_1", position = { 13.15, 5.3, 0 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_2", position = { 13.15, 5.3, 5.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "HouseNumber", position = { 0, 7.2, -11.36 }, size = { 1.2, 1.2, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "12" },
		{ name = "KeepClear", position = { 0, 4.6, -11.36 }, size = { 1.3, 0.9, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "NO PARK" },
		{ name = "WallLantern-1", position = { -12, 7.4, -11.6 }, size = { 0.8, 1.1, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "WallLantern1", position = { 12, 7.4, -11.6 }, size = { 0.8, 1.1, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "Downpipe", position = { 13.25, 5.5, 10 }, size = { 0.4, 11, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Gutter", position = { 13.25, 10.8, 0 }, size = { 0.5, 0.4, 21 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "BrickVent", position = { -6, 12.6, 6 }, size = { 2, 2.4, 2 }, color = { 112, 84, 70 }, material = "Brick" },
	},
} :: Kit.Blueprint
