--!strict
-- Guns: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "guns", width = 60, depth = 46, height = 16,
	details = {
		{ name = "SecurityFascia", position = { 0, 14.8, -23.75 }, size = { 60, 2, 0.9 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "SteelDoorCanopy", position = { 0, 12.5, -24 }, size = { 22, 0.45, 3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RedDoorReveal", position = { 0, 12.21, -25.52 }, size = { 22, 0.12, 0.12 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "DoorJamb-1", position = { -6.65, 5.5, -23.8 }, size = { 0.5, 11, 0.6 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowRecess-1", position = { -18, 7.5, -23.75 }, size = { 14, 6, 0.3 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15 },
		{ name = "WindowCap-1", position = { -18, 10.65, -24 }, size = { 14.5, 0.35, 0.7 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowSill-1", position = { -18, 4.35, -24 }, size = { 14.5, 0.35, 0.7 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "SecurityBar-1_0", position = { -23, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar-1_1", position = { -20.5, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar-1_2", position = { -18, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar-1_3", position = { -15.5, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar-1_4", position = { -13, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "CanopyLight-1", position = { -7, 12.1, -24 }, size = { 3, 0.14, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true },
		{ name = "CornerPilaster-1", position = { -29.4, 7, -23.7 }, size = { 1.1, 14, 0.9 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "DoorJamb1", position = { 6.65, 5.5, -23.8 }, size = { 0.5, 11, 0.6 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "WindowRecess1", position = { 18, 7.5, -23.75 }, size = { 14, 6, 0.3 }, color = { 28, 36, 38 }, material = "Glass", transparency = 0.15 },
		{ name = "WindowCap1", position = { 18, 10.65, -24 }, size = { 14.5, 0.35, 0.7 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "WindowSill1", position = { 18, 4.35, -24 }, size = { 14.5, 0.35, 0.7 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "SecurityBar1_0", position = { 13, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar1_1", position = { 15.5, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar1_2", position = { 18, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar1_3", position = { 20.5, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "SecurityBar1_4", position = { 23, 7.5, -24 }, size = { 0.12, 6, 0.15 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "CanopyLight1", position = { 7, 12.1, -24 }, size = { 3, 0.14, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 18 },
		{ name = "CornerPilaster1", position = { 29.4, 7, -23.7 }, size = { 1.1, 14, 0.9 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "DoorLintel", position = { 0, 11.2, -23.8 }, size = { 13.5, 0.45, 0.6 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "ShopPlate", position = { -18, 12, -23.98 }, size = { 14, 1.5, 0.15 }, color = { 38, 43, 47 }, material = "Metal", label = "LICENSED  /  ARMORY" },
		{ name = "RoofExtract", position = { 20, 18, 10 }, size = { 5, 3, 5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "ExtractCap", position = { 20, 19.7, 10 }, size = { 6, 0.4, 6 }, color = { 100, 104, 101 }, material = "Metal" },
	},
} :: Kit.Blueprint
