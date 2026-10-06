--!strict
-- Warehouse: approved cinematic facade; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

return function(doors: { number }): Kit.Blueprint
	local blueprint: Kit.Blueprint = {
		id = "warehouse", width = 100, depth = 56, height = 22, interior = true,
		details = {
			{ name = "DockCornice", position = { 0, 21.65, -28.8 }, size = { 100, 0.7, 1.1 }, color = { 38, 43, 47 }, material = "Metal" },
			{ name = "DockCanopy", position = { 0, 21.1, -29.2 }, size = { 100, 0.45, 4 }, color = { 38, 43, 47 }, material = "Metal" },
			{ name = "DockRedEdge", position = { 0, 21.03, -31.24 }, size = { 100, 0.14, 0.12 }, color = { 153, 49, 43 }, material = "Metal" },
			{ name = "CladdingRib-1_0", position = { -50.1, 11, -20 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib-1_1", position = { -50.1, 11, -8 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib-1_2", position = { -50.1, 11, 4 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib-1_3", position = { -50.1, 11, 16 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib-1_4", position = { -50.1, 11, 24 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "RoofVent-1", position = { -38, 25, 16 }, size = { 9, 4, 6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib1_0", position = { 50.1, 11, -20 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib1_1", position = { 50.1, 11, -8 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib1_2", position = { 50.1, 11, 4 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib1_3", position = { 50.1, 11, 16 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "CladdingRib1_4", position = { 50.1, 11, 24 }, size = { 0.35, 22, 0.6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "RoofVent1", position = { 38, 25, 16 }, size = { 9, 4, 6 }, color = { 100, 104, 101 }, material = "Metal" },
			{ name = "OfficeLeftFrame", position = { 35.75, 10, -28.45 }, size = { 0.3, 3.6, 0.2 }, color = { 202, 205, 200 }, material = "Metal" },
			{ name = "OfficeRightFrame", position = { 44.25, 10, -28.45 }, size = { 0.3, 3.6, 0.2 }, color = { 202, 205, 200 }, material = "Metal" },
			{ name = "OfficeTopFrame", position = { 40, 11.8, -28.45 }, size = { 8.8, 0.3, 0.2 }, color = { 202, 205, 200 }, material = "Metal" },
			{ name = "OfficeSill", position = { 40, 8.2, -28.45 }, size = { 8.8, 0.3, 0.2 }, color = { 202, 205, 200 }, material = "Metal" },
			{ name = "OfficePlate", position = { 40, 16, -28.75 }, size = { 9, 2, 0.15 }, color = { 38, 43, 47 }, material = "Metal", label = "DISPATCH" },
			{ name = "CargoArrow", position = { 46, 18, -28.75 }, size = { 5, 2.6, 0.15 }, color = { 153, 49, 43 }, material = "Metal", label = "03" },
		},
	}
	for index, x in doors do
		for _, side in { -1, 1 } do
			table.insert(blueprint.details, { name = `DockJamb{index}_{side}`, position = { x + side * 8.65, 7, -28.85 }, size = { 0.5, 14, 0.65 }, color = { 202, 205, 200 }, material = "Metal" })
		end
		table.insert(blueprint.details, { name = `DockHeader{index}`, position = { x, 14.5, -28.85 }, size = { 18, 0.5, 0.65 }, color = { 38, 43, 47 }, material = "Metal" })
		table.insert(blueprint.details, { name = `DockNumber{index}`, position = { x, 15.6, -28.9 }, size = { 5, 1.2, 0.12 }, color = { 38, 43, 47 }, material = "Metal", label = string.format("%02d", index) })
	end
	return blueprint
end
