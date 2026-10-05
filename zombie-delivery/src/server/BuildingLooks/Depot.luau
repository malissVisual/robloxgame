--!strict
-- Depot: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "depot", width = 80, depth = 40, height = 22,
	details = {
		{ name = "FrontFascia", position = { 0, 21, -20.7 }, size = { 80, 2, 1.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DispatchCanopy", position = { 0, 19.6, -21.5 }, size = { 80, 0.6, 4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CanopyRedEdge", position = { 0, 19.5, -23.55 }, size = { 80, 0.18, 0.12 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "Portal-1", position = { -39, 10, -20.8 }, size = { 1.2, 20, 1.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CornerAccent-1", position = { -38.2, 15.5, -21.48 }, size = { 0.5, 7, 0.15 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "WallRib-1_0", position = { -40.1, 11, -14 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WallRib-1_1", position = { -40.1, 11, -4 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WallRib-1_2", position = { -40.1, 11, 6 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WallRib-1_3", position = { -40.1, 11, 16 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "RoofVent-1", position = { -28, 25, 10 }, size = { 8, 4, 6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "VentCap-1", position = { -28, 27.3, 10 }, size = { 9, 0.6, 7 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Portal1", position = { 39, 10, -20.8 }, size = { 1.2, 20, 1.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "CornerAccent1", position = { 38.2, 15.5, -21.48 }, size = { 0.5, 7, 0.15 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "WallRib1_0", position = { 40.1, 11, -14 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WallRib1_1", position = { 40.1, 11, -4 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WallRib1_2", position = { 40.1, 11, 6 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WallRib1_3", position = { 40.1, 11, 16 }, size = { 0.4, 22, 0.8 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "RoofVent1", position = { 28, 25, 10 }, size = { 8, 4, 6 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "VentCap1", position = { 28, 27.3, 10 }, size = { 9, 0.6, 7 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CanopyLight0", position = { -26, 19, -21 }, size = { 12, 0.18, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "CanopyLight1", position = { 0, 19, -21 }, size = { 12, 0.18, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 24 },
		{ name = "CanopyLight2", position = { 26, 19, -21 }, size = { 12, 0.18, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "DispatchDirection", position = { 27, 16, -21.46 }, size = { 15, 2.6, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "DISPATCH  /  01" },
		{ name = "FleetDirection", position = { -27, 16, -21.46 }, size = { 15, 2.6, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "FLEET  /  02" },
	},
} :: Kit.Blueprint
