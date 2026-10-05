--!strict
-- Mechanic: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "mechanic", width = 70, depth = 60, height = 20,
	details = {
		{ name = "GarageFascia", position = { 0, 18, -30.7 }, size = { 70, 3, 1.1 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "BayCanopy", position = { 0, 15.8, -31.4 }, size = { 70, 0.5, 3.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RedBayReveal", position = { 0, 16.12, -33.18 }, size = { 64, 0.13, 0.12 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "OuterColumn-1", position = { -33.2, 7.75, -30.8 }, size = { 1.2, 15.5, 1.1 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "BayMarker-1", position = { -8.5, 16.12, -33.28 }, size = { 4.5, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "01" },
		{ name = "CanopyLight-1", position = { -8.5, 15.47, -31.2 }, size = { 10, 0.15, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 25 },
		{ name = "FrontRib-1_0", position = { -22, 7.5, -30.75 }, size = { 0.22, 15, 0.35 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "FrontRib-1_1", position = { -26, 7.5, -30.75 }, size = { 0.22, 15, 0.35 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "FrontRib-1_2", position = { -30, 7.5, -30.75 }, size = { 0.22, 15, 0.35 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "RoofVent-1", position = { -25, 23, 12 }, size = { 8, 4, 6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "VentLouver-1", position = { -25, 23, 8.9 }, size = { 6, 2.6, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "SideRib-1_0", position = { -35.1, 10, -20 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_1", position = { -35.1, 10, -6 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_2", position = { -35.1, 10, 8 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib-1_3", position = { -35.1, 10, 22 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "OuterColumn1", position = { 33.2, 7.75, -30.8 }, size = { 1.2, 15.5, 1.1 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "BayMarker1", position = { 8.5, 16.12, -33.28 }, size = { 4.5, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "02" },
		{ name = "CanopyLight1", position = { 8.5, 15.47, -31.2 }, size = { 10, 0.15, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 25 },
		{ name = "FrontRib1_0", position = { 22, 7.5, -30.75 }, size = { 0.22, 15, 0.35 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "FrontRib1_1", position = { 26, 7.5, -30.75 }, size = { 0.22, 15, 0.35 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "FrontRib1_2", position = { 30, 7.5, -30.75 }, size = { 0.22, 15, 0.35 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "RoofVent1", position = { 25, 23, 12 }, size = { 8, 4, 6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "VentLouver1", position = { 25, 23, 8.9 }, size = { 6, 2.6, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "SideRib1_0", position = { 35.1, 10, -20 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_1", position = { 35.1, 10, -6 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_2", position = { 35.1, 10, 8 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "SideRib1_3", position = { 35.1, 10, 22 }, size = { 0.3, 20, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "WorkshopPlate", position = { -25, 13, -31.08 }, size = { 12, 2, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "SERVICE  /  REPAIR" },
		{ name = "PartsPlate", position = { 25, 13, -31.08 }, size = { 12, 2, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "PARTS  /  PAINT" },
	},
} :: Kit.Blueprint
