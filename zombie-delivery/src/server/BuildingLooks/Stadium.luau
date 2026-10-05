--!strict
-- Stadium Shelter entrance gate: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "stadium", width = 136, depth = 3.6, height = 18,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 116.4, 15 } },
	details = {
		{ name = "PillarPlinth-1", position = { -60.45, 0.7, 0 }, size = { 4.4, 1.4, 4.4 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "PillarPlinth1", position = { 60.45, 0.7, 0 }, size = { 4.4, 1.4, 4.4 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "PillarCap-1", position = { -60, 18.3, 0 }, size = { 4.4, 0.6, 4.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PillarCap1", position = { 60, 18.3, 0 }, size = { 4.4, 0.6, 4.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PillarRedStripe-1", position = { -60, 8, -1.85 }, size = { 0.5, 12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "PillarRedStripe1", position = { 60, 8, -1.85 }, size = { 0.5, 12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "PillarPlate-1", position = { -60, 11.5, -1.86 }, size = { 2.8, 1.6, 0.1 }, color = { 38, 43, 47 }, material = "Metal", label = "SHELTER" },
		{ name = "PillarPlate1", position = { 60, 11.5, -1.86 }, size = { 2.8, 1.6, 0.1 }, color = { 38, 43, 47 }, material = "Metal", label = "MEDICAL" },
		{ name = "PillarLamp-1", position = { -60, 14, -2.3 }, size = { 1.2, 0.8, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 34 },
		{ name = "PillarLamp1", position = { 60, 14, -2.3 }, size = { 1.2, 0.8, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 34 },
		{ name = "BeamCoping", position = { 0, 18.25, 0 }, size = { 123.6, 0.5, 2.6 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "BeamRedLine", position = { 0, 15.12, -1.3 }, size = { 116, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "BeamPlate-1", position = { -36, 16.5, -1.3 }, size = { 24, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "SHELTER  /  FOOD  /  WATER" },
		{ name = "BeamPlate1", position = { 36, 16.5, -1.3 }, size = { 24, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "MEDICAL  /  BEDS  /  INFO" },
		{ name = "NoticeBoard-1", position = { -66, 5, -1 }, size = { 5, 3, 0.3 }, color = { 38, 43, 47 }, material = "Metal", label = "SHELTER RULES: NO BITES" },
		{ name = "NoticeBoard1", position = { 66, 5, -1 }, size = { 5, 3, 0.3 }, color = { 38, 43, 47 }, material = "Metal", label = "<  MEDICAL TENT" },
		{ name = "NoticePostIn-1", position = { -63.8, 3.25, -0.8 }, size = { 0.3, 6.5, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "NoticePostIn1", position = { 63.8, 3.25, -0.8 }, size = { 0.3, 6.5, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "NoticePostOut-1", position = { -68.2, 3.25, -0.8 }, size = { 0.3, 6.5, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "NoticePostOut1", position = { 68.2, 3.25, -0.8 }, size = { 0.3, 6.5, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
	},
} :: Kit.Blueprint
