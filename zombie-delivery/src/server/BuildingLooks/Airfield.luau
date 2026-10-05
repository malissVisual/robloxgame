--!strict
-- Old Airfield hangar: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "airfield", width = 64, depth = 44, height = 18,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 62, 15 } },
	details = {
		{ name = "DoorPost-1", position = { -32.2, 9, -22.4 }, size = { 1.2, 18, 1.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "DoorPost1", position = { 32.2, 9, -22.4 }, size = { 1.2, 18, 1.2 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "PostBase-1", position = { -32.2, 0.5, -22.4 }, size = { 1.8, 1, 1.8 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "PostBase1", position = { 32.2, 0.5, -22.4 }, size = { 1.8, 1, 1.8 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "DoorTrack", position = { 0, 15.25, -22.4 }, size = { 64, 0.4, 0.6 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "FasciaRedLine", position = { 0, 17.88, -22.06 }, size = { 64, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "FasciaRib12_-1", position = { -12, 16.75, -22.1 }, size = { 0.3, 2.5, 0.2 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "FasciaRib12_1", position = { 12, 16.75, -22.1 }, size = { 0.3, 2.5, 0.2 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "FasciaRib28_-1", position = { -28, 16.75, -22.1 }, size = { 0.3, 2.5, 0.2 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "FasciaRib28_1", position = { 28, 16.75, -22.1 }, size = { 0.3, 2.5, 0.2 }, color = { 100, 104, 101 }, material = "Metal" },
		{ name = "HangarFlood-1", position = { -16, 15.6, -23 }, size = { 2.4, 0.4, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 32 },
		{ name = "HangarFlood1", position = { 16, 15.6, -23 }, size = { 2.4, 0.4, 0.6 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 32 },
		{ name = "SideRib0_-1", position = { -32.2, 9, -10 }, size = { 0.4, 18, 0.6 }, color = { 38, 43, 47 }, material = "CorrodedMetal" },
		{ name = "SideRib0_1", position = { 32.2, 9, -10 }, size = { 0.4, 18, 0.6 }, color = { 38, 43, 47 }, material = "CorrodedMetal" },
		{ name = "SideRib1_-1", position = { -32.2, 9, 2 }, size = { 0.4, 18, 0.6 }, color = { 38, 43, 47 }, material = "CorrodedMetal" },
		{ name = "SideRib1_1", position = { 32.2, 9, 2 }, size = { 0.4, 18, 0.6 }, color = { 38, 43, 47 }, material = "CorrodedMetal" },
		{ name = "SideRib2_-1", position = { -32.2, 9, 14 }, size = { 0.4, 18, 0.6 }, color = { 38, 43, 47 }, material = "CorrodedMetal" },
		{ name = "SideRib2_1", position = { 32.2, 9, 14 }, size = { 0.4, 18, 0.6 }, color = { 38, 43, 47 }, material = "CorrodedMetal" },
		{ name = "TaxiCentre", position = { 0, 0.15, -24.2 }, size = { 0.6, 0.06, 3.6 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "HoldBar", position = { 0, 0.15, -25.5 }, size = { 24, 0.06, 0.5 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "FreightPlate", position = { -20, 16.5, -22.12 }, size = { 12, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "FREIGHT  >" },
		{ name = "MaintenancePlate", position = { 20, 16.5, -22.12 }, size = { 12, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "MAINTENANCE" },
	},
} :: Kit.Blueprint
