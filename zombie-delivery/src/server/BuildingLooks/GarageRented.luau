--!strict
-- Rented Lockup: a single rusty lock-up with a unit plate and a roof vent; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "garage_rented", width = 14, depth = 18, height = 11, interior = true,
	-- The openings that stay clear: { center x, width, clear height }.
	entries = { { 0, 10, 9 } },
	details = {
		{ name = "LintelFascia", position = { 0, 10.3, -9.15 }, size = { 14, 1.4, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RoofEdgeCap", position = { 0, 11.5, -9.65 }, size = { 15.2, 0.5, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DoorCanopy", position = { 0, 9.45, -10.3 }, size = { 13, 0.35, 2.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CanopyRedEdge", position = { 0, 9.45, -11.45 }, size = { 13, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "DoorNumber1", position = { 0, 10.3, -9.36 }, size = { 4, 0.9, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "UNIT 07" },
		{ name = "DoorLamp1", position = { 0, 9.2, -10.3 }, size = { 3, 0.14, 0.5 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 18 },
		{ name = "DoorJamb0", position = { -6, 4.5, -9.2 }, size = { 1.6, 9, 0.4 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "BumperGuard0", position = { -6, 1.1, -9.3 }, size = { 1.8, 2.2, 0.6 }, color = { 196, 158, 52 }, material = "SmoothPlastic" },
		{ name = "DoorJamb1", position = { 6, 4.5, -9.2 }, size = { 1.6, 9, 0.4 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "BumperGuard1", position = { 6, 1.1, -9.3 }, size = { 1.8, 2.2, 0.6 }, color = { 196, 158, 52 }, material = "SmoothPlastic" },
		{ name = "CornerColumn-1", position = { -7.4, 5.5, -8.8 }, size = { 0.8, 11, 1.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "SideRib-1_0", position = { -7.15, 5.3, -4.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_1", position = { -7.15, 5.3, 0 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_2", position = { -7.15, 5.3, 4.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "CornerColumn1", position = { 7.4, 5.5, -8.8 }, size = { 0.8, 11, 1.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "SideRib1_0", position = { 7.15, 5.3, -4.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_1", position = { 7.15, 5.3, 0 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_2", position = { 7.15, 5.3, 4.5 }, size = { 0.3, 10.6, 0.5 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "RoofVent", position = { 2, 12.6, 4 }, size = { 1.8, 1.6, 1.8 }, color = { 100, 104, 101 }, material = "CorrodedMetal" },
		{ name = "RoofVentCap", position = { 2, 13.55, 4 }, size = { 2.4, 0.3, 2.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PadlockHasp", position = { 6, 3.4, -9.5 }, size = { 0.5, 0.9, 0.2 }, color = { 202, 205, 200 }, material = "Metal" },
	},
} :: Kit.Blueprint
