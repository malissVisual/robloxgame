--!strict
-- Worn city props, pure ground-relative native geometry (-Z street, X kerb). Deterministic color variants;
-- solid/query flags identify hulls only. Claude keeps StreetProps placement, flare light and gameplay.
local Art = {}
export type Piece = {
	name: string, size: { number }, at: { number }, color: { number }, material: string,
	rotation: { number }?, shape: string?, solid: boolean?, query: boolean?, night: boolean?, slots: { any }?,
}
Art.ids = { "bin", "hydrant", "barricade", "sandbags", "debris", "bags", "boarded", "car", "flare" }
Art.Budgets = { bin = 6, hydrant = 6, barricade = 8, sandbags = 8, debris = 6, bags = 6, boarded = 8, car = 20, flare = 3 }
Art.Footprints = {
	bin = { 1.6, 2.6, 1.6 }, hydrant = { 1.6, 2.6, 1 }, barricade = { 4.8, 2.8, 1.4 },
	sandbags = { 4, 1.8, 1.6 }, debris = { 3.2, 0.6, 2 }, bags = { 3, 2.2, 1.8 },
	boarded = { 8, 6.5, 0.6 }, car = { 11, 4.5, 5 }, flare = { 1, 0.4, 0.4 },
}
local DARK, RED, STEEL = { 24, 27, 32 }, { 215, 74, 70 }, { 112, 119, 118 }
local COLORS = { { 70, 90, 76 }, { 64, 68, 72 }, { 55, 73, 89 } }
local function dice(seed: number): number
	return (math.floor(seed) % 2147483647) % 3 + 1
end

function Art.pieces(kind: string, seed: number, width: number?): { Piece }
	assert(table.find(Art.ids, kind), "Unknown street prop")
	local p: { Piece } = {}
	local v = dice(seed)
	local function add(name: string, size: { number }, at: { number }, color: { number }, shape: string?, rot: { number }?, solid: boolean?, material: string?)
		table.insert(p, { name = name, size = size, at = at, color = table.clone(color), material = material or "Metal", shape = shape, rotation = rot, solid = solid })
	end
	if kind == "bin" then
		add("BinHull", { 1.35, 2.15, 1.35 }, { 0, 1.075, 0 }, COLORS[v], nil, nil, true)
		add("OpenLid", { 1.5, 0.17, 1.5 }, { 0, 2.3, 0 }, DARK)
		add("LitterSlot", { 0.83, 0.22, 0.025 }, { 0, 1.94, -0.69 }, DARK)
	elseif kind == "hydrant" then
		add("Barrel", { 1.9, 0.79, 0.79 }, { 0, 1.1, 0 }, RED, "Cylinder", { 0, 0, 90 }, true)
		add("Crown", { 0.88, 0.51, 0.88 }, { 0, 2.1, 0 }, RED, "Ball")
		add("Nozzles", { 1.54, 0.39, 0.39 }, { 0, 1.38, 0 }, { 141, 47, 43 }, "Cylinder")
		add("FrontCap", { 0.15, 0.45, 0.45 }, { 0, 1.38, -0.415 }, STEEL, "Cylinder", { 0, 90, 0 })
		add("Foot", { 0.18, 0.96, 0.96 }, { 0, 0.09, 0 }, { 94, 40, 36 }, "Cylinder", { 0, 0, 90 })
	elseif kind == "barricade" then
		add("BarrierBoard", { 4.5, 0.83, 0.15 }, { 0, 2.1, 0 }, { 206, 185, 135 }, nil, nil, true)
		for _, side in { -1, 1 } do
			add("Leg" .. side, { 0.22, 2.3, 1.25 }, { side * 1.9, 1.15, 0 }, STEEL, nil, nil, true)
			add("HazardStripe" .. side, { 0.3, 0.86, 0.028 }, { side * 1.1, 2.1, -0.09 }, DARK, nil, { 0, 0, -25 })
		end
		add("AmberBeacon", { 0.43, 0.25, 0.34 }, { 0, 2.65, 0 }, { 214, 151, 65 })
		p[#p].night = true -- visual only, no actual light
	elseif kind == "sandbags" then
		for row = 1, 2 do
			for n = 1, 2 do
				add("Bag" .. row .. n, { 1.8, 0.77, 1.36 }, { (n - 1.5) * 1.9 + (if row == 2 then 0.08 else 0), (row - 0.5) * 0.81, 0 }, { 138 + v * 5, 123 + row * 4, 91 }, "Ball", nil, true, "Fabric")
			end
		end
	elseif kind == "debris" then
		add("BrokenSlab", { 1.7, 0.3, 1.35 }, { -0.58, 0.15, -0.1 }, { 111, 111, 105 }, "Wedge", { 0, v * 4, 0 }, nil, "Concrete")
		add("Plank", { 2.3, 0.15, 0.42 }, { 0.26, 0.25, 0.42 }, { 123, 96, 65 }, nil, { 0, -13, 0 }, nil, "WoodPlanks")
		add("Brick", { 0.63, 0.2, 0.36 }, { 0.74, 0.1, -0.57 }, { 130, 80, 59 }, nil, { 0, 12, 0 }, nil, "Brick")
	elseif kind == "bags" then
		add("TrashL", { 1.44, 1.35, 1.48 }, { -0.74, 0.675, 0.08 }, DARK, "Ball", nil, nil, "Plastic")
		add("TrashR", { 1.28, 1.25, 1.34 }, { 0.77, 0.625, 0.18 }, { 35, 38, 39 }, "Ball", nil, nil, "Plastic")
		add("TrashTop", { 1, 1, 1.1 }, { 0.05, 1.6, 0.17 }, { 28, 34, 31 }, "Ball", nil, nil, "Plastic")
		add("Tie", { 0.23, 0.14, 0.23 }, { 0.05, 2.1, 0.17 }, STEEL)
	elseif kind == "boarded" then
		local w = math.clamp(width or 6, 4, 8)
		add("Plywood", { w - 0.1, 6.3, 0.17 }, { 0, 3.17, 0.08 }, { 150, 121, 82 }, nil, { -2, 0, 0 }, nil, "WoodPlanks")
		for _, side in { -1, 1 } do
			add("RedCross" .. side, { 0.17, 1.7, 0.025 }, { 0, 3.5, -0.145 }, RED, nil, { 0, 0, side * 35 })
		end
		add("WarningPlate", { math.min(2.5, w - 1), 0.65, 0.03 }, { 0, 5.23, -0.145 }, DARK)
		p[#p].slots = { { name = "Warning", text = "NO ENTRY" } }
	elseif kind == "car" then
		local paint = { 88 + v * 12, 72 + v * 9, 59 + v * 10 }
		add("AbandonedHull", { 10.2, 1.5, 4.3 }, { 0, 1.2, 0 }, paint, nil, nil, true, "CorrodedMetal")
		p[#p].query = true -- only the hull stops bullets
		add("Cabin", { 4.7, 1.32, 4.05 }, { 0.4, 2.61, 0 }, paint, nil, nil, nil, "CorrodedMetal")
		add("Windscreen", { 0.06, 0.92, 3.61 }, { -1.98, 2.61, 0 }, { 34, 46, 52 })
		add("RearGlass", { 0.06, 0.92, 3.61 }, { 2.78, 2.61, 0 }, { 34, 46, 52 })
		for _, side in { -1, 1 } do
			add("SideGlass" .. side, { 3.95, 0.82, 0.03 }, { 0.35, 2.61, side * 2.043 }, { 34, 46, 52 })
			for _, axle in { -3.65, 3.65 } do
				add("FlatTyre" .. side .. axle, { 0.39, 1.22, 1.22 }, { axle, 0.61, side * 2.19 }, DARK, "Cylinder", { 0, 90, 0 }, nil, "Rubber")
			end
		end
		add("CrackedGlass", { 0.05, 0.93, 0.63 }, { -2.027, 2.58, -0.64 }, paint, nil, { 14, 0, 0 })
		add("DoorAjar", { 1.91, 1.05, 0.08 }, { -0.56, 1.73, -2.26 }, paint, nil, { 0, 10, 0 }, nil, "CorrodedMetal")
		add("Grille", { 0.04, 0.38, 2.85 }, { -5.123, 1.1, 0 }, DARK)
		add("RustHood", { 1.35, 0.025, 1.6 }, { -3.24, 1.97, 0.55 }, { 110, 66, 43 }, nil, { 0, 8, 0 })
		for _, side in { -1, 1 } do
			add("Lamp" .. side, { 0.04, 0.3, 0.83 }, { -5.13, 1.48, side * 1.4 }, { 177, 164, 132 })
		end
	elseif kind == "flare" then
		add("FlareBody", { 0.83, 0.15, 0.15 }, { -0.07, 0.075, 0 }, RED, "Cylinder")
		add("FlareTip", { 0.18, 0.25, 0.25 }, { 0.39, 0.16, 0 }, { 255, 92, 70 }, "Ball", nil, nil, "Neon")
		p[#p].night = true -- Claude retains the single existing red flare light
	end
	return p
end

return Art
