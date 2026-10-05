--!strict
-- Military Base ammo bunker: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "army", width = 12, depth = 10, height = 7,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 3.6, 5.4 } },
	details = {
		{ name = "BlastJamb-1", position = { -2.4, 2.8, -5.5 }, size = { 1, 5.6, 1 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "BlastJamb1", position = { 2.4, 2.8, -5.5 }, size = { 1, 5.6, 1 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "HazardBand0_-1", position = { -2.4, 1, -5.5 }, size = { 1.04, 0.5, 1.04 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "HazardBand0_1", position = { 2.4, 1, -5.5 }, size = { 1.04, 0.5, 1.04 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "HazardBand1_-1", position = { -2.4, 2.6, -5.5 }, size = { 1.04, 0.5, 1.04 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "HazardBand1_1", position = { 2.4, 2.6, -5.5 }, size = { 1.04, 0.5, 1.04 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "HazardBand2_-1", position = { -2.4, 4.2, -5.5 }, size = { 1.04, 0.5, 1.04 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "HazardBand2_1", position = { 2.4, 4.2, -5.5 }, size = { 1.04, 0.5, 1.04 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "BlastHood", position = { 0, 7.3, -6 }, size = { 8, 0.6, 2.2 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "HoodRedLine", position = { 0, 7.3, -7.16 }, size = { 8, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "CagedLamp", position = { 3.7, 5.6, -5.35 }, size = { 0.7, 0.7, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 22 },
		{ name = "LampCage", position = { 3.7, 6.05, -5.35 }, size = { 0.9, 0.15, 0.8 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "BunkerPlate", position = { -4, 5, -5.06 }, size = { 2.2, 0.9, 0.1 }, color = { 52, 58, 44 }, material = "Metal", label = "BUNKER 3", textColor = { 230, 200, 90 } },
		{ name = "NoSmokingPlate", position = { 4, 3.2, -5.06 }, size = { 2.2, 0.9, 0.1 }, color = { 153, 49, 43 }, material = "Metal", label = "NO SMOKING" },
		{ name = "Buttress-1", position = { -5.6, 3.5, -4.9 }, size = { 1, 7, 1.4 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "Buttress1", position = { 5.6, 3.5, -4.9 }, size = { 1, 7, 1.4 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "VentPipe-1", position = { -3, 8, 2 }, size = { 0.9, 2, 0.9 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "VentPipe1", position = { 3, 8, 2 }, size = { 0.9, 2, 0.9 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "VentCap-1", position = { -3, 9.15, 2 }, size = { 1.4, 0.3, 1.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "VentCap1", position = { 3, 9.15, 2 }, size = { 1.4, 0.3, 1.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "AntennaWhip", position = { 4.5, 9, 3 }, size = { 0.15, 4, 0.15 }, color = { 38, 43, 47 }, material = "Metal" },
	},
} :: Kit.Blueprint
