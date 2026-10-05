--!strict
-- Dealer: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "dealer", width = 84, depth = 52, height = 18,
	details = {
		{ name = "ShowroomFascia", position = { 0, 16.5, -26.7 }, size = { 84, 3, 1.1 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "FloatingCanopy", position = { 0, 14.8, -27.4 }, size = { 86, 0.6, 4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RedReveal", position = { 0, 14.45, -29.45 }, size = { 84, 0.16, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "Mullion-1_0", position = { -9, 7.5, -26.85 }, size = { 0.45, 15, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Mullion-1_1", position = { -24, 7.5, -26.85 }, size = { 0.45, 15, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Mullion-1_2", position = { -40, 7.5, -26.85 }, size = { 0.45, 15, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowRail-1", position = { -25, 1.5, -26.85 }, size = { 32, 0.25, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowMidRail-1", position = { -25, 7, -26.85 }, size = { 32, 0.18, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Sill-1", position = { -25, 0.75, -26.8 }, size = { 32, 1, 0.9 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "RoofUnit-1", position = { -28, 21.3, 12 }, size = { 10, 3, 7 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "RoofUnitGrille-1", position = { -28, 21.6, 8.42 }, size = { 8, 1.8, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CanopyLight-1", position = { -24, 14.38, -27.1 }, size = { 15, 0.15, 0.7 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 26 },
		{ name = "Mullion1_0", position = { 9, 7.5, -26.85 }, size = { 0.45, 15, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Mullion1_1", position = { 24, 7.5, -26.85 }, size = { 0.45, 15, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Mullion1_2", position = { 40, 7.5, -26.85 }, size = { 0.45, 15, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowRail1", position = { 25, 1.5, -26.85 }, size = { 32, 0.25, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowMidRail1", position = { 25, 7, -26.85 }, size = { 32, 0.18, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "Sill1", position = { 25, 0.75, -26.8 }, size = { 32, 1, 0.9 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "RoofUnit1", position = { 28, 21.3, 12 }, size = { 10, 3, 7 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "RoofUnitGrille1", position = { 28, 21.6, 8.42 }, size = { 8, 1.8, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "CanopyLight1", position = { 24, 14.38, -27.1 }, size = { 15, 0.15, 0.7 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 26 },
		{ name = "CatalogPlate", position = { 16, 10.6, -27.12 }, size = { 12, 2, 0.14 }, color = { 38, 43, 47 }, material = "Metal", label = "SALES  /  CATALOG" },
		{ name = "DoorHeader", position = { 0, 12.6, -26.85 }, size = { 17, 0.5, 0.45 }, color = { 202, 205, 200 }, material = "Metal" },
	},
} :: Kit.Blueprint
