--!strict
-- Biotech Lab: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "lab", width = 90, depth = 120, height = 20,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 10, 9 }, { 36, 10, 9 } },
	details = {
		{ name = "UpperMullion-328", position = { -32.8, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperMullion-246", position = { -24.6, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperMullion-164", position = { -16.4, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperMullion-82", position = { -8.2, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperMullion82", position = { 8.2, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperMullion164", position = { 16.4, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperMullion246", position = { 24.6, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperMullion328", position = { 32.8, 14.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "LowerMullion-3225", position = { -32.25, 5.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "LowerMullion-2350", position = { -23.5, 5.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "LowerMullion-1475", position = { -14.75, 5.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "LowerMullion1600", position = { 16, 5.5, -60.78 }, size = { 0.3, 3.4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "UpperSill", position = { 0, 12.6, -60.85 }, size = { 83, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "LowerCapWest", position = { -23.5, 7.4, -60.8 }, size = { 35.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "LowerSillWest", position = { -23.5, 3.6, -60.85 }, size = { 35.6, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "LowerCapEast", position = { 16, 7.4, -60.8 }, size = { 20.6, 0.3, 0.5 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "LowerSillEast", position = { 16, 3.6, -60.85 }, size = { 20.6, 0.3, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "RedLine", position = { 0, 12.32, -60.85 }, size = { 82, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "EndFin-1", position = { -44.2, 10, -60.6 }, size = { 1.2, 20, 1.2 }, color = { 214, 218, 216 }, material = "Concrete" },
		{ name = "EndFin1", position = { 44.2, 10, -60.6 }, size = { 1.2, 20, 1.2 }, color = { 214, 218, 216 }, material = "Concrete" },
		{ name = "EntryJamb-1", position = { -5.3, 4.7, -60.4 }, size = { 0.5, 9.4, 0.6 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "EntryJamb1", position = { 5.3, 4.7, -60.4 }, size = { 0.5, 9.4, 0.6 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "CanopyLight", position = { 0, 9.9, -63.2 }, size = { 6, 0.12, 1.2 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 30 },
		{ name = "ReceptionPlate", position = { -9, 8.3, -60.75 }, size = { 6, 1, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "RECEPTION  /  VISITORS" },
		{ name = "DeliveryJamb-1", position = { 30.7, 4.6, -60.45 }, size = { 0.5, 9.2, 0.6 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DeliveryJamb1", position = { 41.3, 4.6, -60.45 }, size = { 0.5, 9.2, 0.6 }, color = { 202, 205, 200 }, material = "Metal" },
		{ name = "DeliveryRedReveal", position = { 36, 9.25, -60.5 }, size = { 10.6, 0.12, 0.12 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "DeliveryLamp", position = { 36, 11.6, -60.9 }, size = { 1.6, 0.5, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 26 },
		{ name = "RoofCoping", position = { 0, 20.5, -61.2 }, size = { 92, 0.6, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "RoofExtract", position = { 0, 22.5, 10 }, size = { 6, 3, 6 }, color = { 190, 194, 196 }, material = "Metal" },
		{ name = "ExtractCap", position = { 0, 24.2, 10 }, size = { 7, 0.4, 7 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "ExhaustStack-1", position = { -12, 23.5, 30 }, size = { 1.2, 5, 1.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "ExhaustStack1", position = { 12, 23.5, 30 }, size = { 1.2, 5, 1.2 }, color = { 38, 43, 47 }, material = "Metal" },
	},
} :: Kit.Blueprint
