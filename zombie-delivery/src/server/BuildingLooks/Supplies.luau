--!strict
-- Supplies: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "supplies", width = 64, depth = 44, height = 14,
	details = {
		{ name = "RoofParapet", position = { 0, 13.65, -22.6 }, size = { 64, 0.7, 1.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "OliveAwning", position = { 0, 11.5, -23.2 }, size = { 56, 0.4, 4 }, color = { 77, 86, 66 }, material = "Metal" },
		{ name = "AwningValance", position = { 0, 11.23, -25.2 }, size = { 56, 0.25, 0.12 }, color = { 62, 70, 55 }, material = "Metal" },
		{ name = "RedWayfindingEdge", position = { -27, 11.22, -25.29 }, size = { 2.5, 0.28, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "CanopyPost-1", position = { -28, 5.5, -24.8 }, size = { 0.3, 11, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DoorJamb-1", position = { -6.5, 5.2, -22.8 }, size = { 0.3, 10.4, 0.45 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "Window-1", position = { -18.5, 6.5, -22.72 }, size = { 15, 7, 0.25 }, color = { 50, 57, 54 }, material = "Glass", transparency = 0.12 },
		{ name = "WindowTop-1", position = { -18.5, 10.1, -22.92 }, size = { 15.5, 0.25, 0.4 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowSill-1", position = { -18.5, 2.9, -22.9 }, size = { 15.5, 0.35, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WindowMullion-1", position = { -18.5, 6.5, -22.98 }, size = { 0.16, 7, 0.12 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "UnderAwningLight-1", position = { -18, 11.21, -23 }, size = { 8, 0.14, 0.5 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "CanopyPost1", position = { 28, 5.5, -24.8 }, size = { 0.3, 11, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DoorJamb1", position = { 6.5, 5.2, -22.8 }, size = { 0.3, 10.4, 0.45 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "Window1", position = { 18.5, 6.5, -22.72 }, size = { 15, 7, 0.25 }, color = { 50, 57, 54 }, material = "Glass", transparency = 0.12 },
		{ name = "WindowTop1", position = { 18.5, 10.1, -22.92 }, size = { 15.5, 0.25, 0.4 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowSill1", position = { 18.5, 2.9, -22.9 }, size = { 15.5, 0.35, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WindowMullion1", position = { 18.5, 6.5, -22.98 }, size = { 0.16, 7, 0.12 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "UnderAwningLight1", position = { 18, 11.21, -23 }, size = { 8, 0.14, 0.5 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 20 },
		{ name = "EntryHeader", position = { 0, 10.6, -22.8 }, size = { 13, 0.3, 0.45 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "ReceivingPlate", position = { -18.5, 1.8, -23.05 }, size = { 14, 1.2, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "SUPPLIES  /  COLLECTION" },
		{ name = "RoofVent", position = { 22, 16.2, 10 }, size = { 5, 3, 5 }, color = { 100, 104, 101 }, material = "Metal" },
	},
} :: Kit.Blueprint
