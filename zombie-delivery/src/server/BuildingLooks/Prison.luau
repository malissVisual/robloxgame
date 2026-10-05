--!strict
-- Blackrock Prison gate: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return {
	id = "prison", width = 80, depth = 3, height = 18,
	-- The front openings kept clear: { center x, width, clear height }.
	entries = { { 0, 28, 15 } },
	details = {
		{ name = "GateJamb-1", position = { -14.6, 7.5, -2 }, size = { 1, 15, 1 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "GateJamb1", position = { 14.6, 7.5, -2 }, size = { 1, 15, 1 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "BeamFascia", position = { 0, 15.4, -2.2 }, size = { 30, 0.6, 0.3 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "BeamRedLine", position = { 0, 15.4, -2.4 }, size = { 30, 0.12, 0.1 }, color = { 153, 49, 43 }, material = "Metal" },
		{ name = "GateFlood-1", position = { -10, 17.3, -2.5 }, size = { 1.4, 0.5, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 32 },
		{ name = "GateFlood1", position = { 10, 17.3, -2.5 }, size = { 1.4, 0.5, 0.8 }, color = { 156, 146, 122 }, material = "Glass", night = true, beam = 32 },
		{ name = "TowerPlate-1", position = { -20, 9, -3.56 }, size = { 4, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "EAST TOWER" },
		{ name = "TowerPlate1", position = { 20, 9, -3.56 }, size = { 4, 1.4, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = "WEST TOWER" },
		{ name = "VisitorPlate", position = { -20, 5, -3.56 }, size = { 4, 1.2, 0.12 }, color = { 153, 49, 43 }, material = "Metal", label = "VISITORS  >  GUARD POST" },
		{ name = "TowerFin16_-1", position = { -16.9, 9, -3.7 }, size = { 0.8, 18, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "TowerFin16_1", position = { 16.9, 9, -3.7 }, size = { 0.8, 18, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "TowerFin23_-1", position = { -23.1, 9, -3.7 }, size = { 0.8, 18, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "TowerFin23_1", position = { 23.1, 9, -3.7 }, size = { 0.8, 18, 0.4 }, color = { 38, 43, 47 }, material = "Metal" },
		{ name = "TowerPlinth-1", position = { -20, 0.6, -3.8 }, size = { 7.6, 1.2, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "TowerPlinth1", position = { 20, 0.6, -3.8 }, size = { 7.6, 1.2, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WallPilaster30_-1", position = { -30, 9, -1.8 }, size = { 1.2, 18, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WallPilaster30_1", position = { 30, 9, -1.8 }, size = { 1.2, 18, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WallPilaster38_-1", position = { -38, 9, -1.8 }, size = { 1.2, 18, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "WallPilaster38_1", position = { 38, 9, -1.8 }, size = { 1.2, 18, 0.6 }, color = { 100, 104, 101 }, material = "Concrete" },
		{ name = "KeepClearFront", position = { 0, 0.04, -5.2 }, size = { 28.4, 0.06, 0.4 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "KeepClearSide-1", position = { -14, 0.04, -3.6 }, size = { 0.4, 0.06, 3.4 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
		{ name = "KeepClearSide1", position = { 14, 0.04, -3.6 }, size = { 0.4, 0.06, 3.4 }, color = { 214, 170, 40 }, material = "SmoothPlastic" },
	},
} :: Kit.Blueprint
