-- 5.7, the towers' looks (shared/TowerLooks.luau): every Downtown tower wears one of four looks, within its part
-- budget, nothing low out on the sidewalk, nothing over an apartment entrance or a zip line's ladder, the zip lines'
-- roofs bare and every roof's things low enough for the cables; in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local TrafficLanes = require("./TrafficLanes")
local ZipLines = require("./ZipLines")
local TowerLooks = require("./TowerLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local tuning = Config.LivingCity.Towers
local towers: { Map.Lot } = {}
for _, lots in Map.lots("downtown") do
	for _, lot in lots do
		if lot.kind == "tower" or lot.kind == "apartment" then
			table.insert(towers, lot)
		end
	end
end
check("Downtown has towers to dress", #towers > 40, #towers)

-- The zip lines' towers and their ladders.
local zipLadders: { [Map.Lot]: { ZipLines.Ladder } } = {}
for _, line in ZipLines.lines() do
	zipLadders[line.start] = zipLadders[line.start] or {}
	table.insert(zipLadders[line.start], line.ladderA)
	zipLadders[line.finish] = zipLadders[line.finish] or {}
	table.insert(zipLadders[line.finish], line.ladderB)
end

local styles: { [string]: number } = {}
local overBudget, outOfRoof, tooHigh, lowOut, nearCurb, overDoor, overLadder, zipRoof, unstable, unknown = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local biggest = 0
local safeDepth = TrafficLanes.DetourInsets[#TrafficLanes.DetourInsets] + TrafficLanes.Body -- the deepest walk line's reach
for _, lot in towers do
	local look = TowerLooks.look(lot)
	local again = TowerLooks.look(lot)
	local name = `({lot.i},{lot.j}) {lot.a}{lot.b}`
	styles[look.style] = (styles[look.style] or 0) + 1
	if not table.find(TowerLooks.Styles, look.style) then
		table.insert(unknown, name)
	end
	if #again.pieces ~= #look.pieces or again.style ~= look.style then
		table.insert(unstable, name)
	end
	biggest = math.max(biggest, #look.pieces)
	if #look.pieces > tuning.Budget then
		table.insert(overBudget, `{name}: {#look.pieces}`)
	end
	local d = Map.districtById(lot.district)
	local cx, cz = d.ox + lot.i * Map.Cell, d.oz + lot.j * Map.Cell
	for _, piece in look.pieces do
		local hx, hy, hz = piece.size[1] / 2, piece.size[2] / 2, piece.size[3] / 2
		local x, y, z = piece.at[1], piece.at[2], piece.at[3]
		local bottom = y - hy
		-- how far it reaches out of the tower's box
		local outX = math.max(0, math.abs(x) + hx - lot.w / 2)
		local outZ = math.max(0, math.abs(z) + hz - lot.d / 2)
		if piece.roof then
			if outX > 1e-6 or outZ > 1e-6 then
				table.insert(outOfRoof, `{name} {piece.name}`)
			end
			if y + hy > lot.h + tuning.RoofHeight + 1e-6 then
				table.insert(tooHigh, `{name} {piece.name}`)
			end
			if zipLadders[lot] then
				table.insert(zipRoof, `{name} {piece.name}`)
			end
		end
		-- under the people's heads (the walk probe: 5.5 studs) it stays on the wall
		if bottom < 6 and math.max(outX, outZ) > 0.8 then
			table.insert(lowOut, `{name} {piece.name}`)
		end
		-- its distance in from the nearest curb
		local wx, wz = lot.x + x, lot.z + z
		local depth = math.min(Map.BlockSize / 2 - (math.abs(wx - cx) + hx), Map.BlockSize / 2 - (math.abs(wz - cz) + hz))
		if bottom < 6 and depth < safeDepth then
			table.insert(nearCurb, `{name} {piece.name} {depth}`)
		elseif depth < 7 then
			table.insert(nearCurb, `{name} {piece.name} {depth} (high)`)
		end
		-- off an apartment's entrance
		local home = lot.home
		if home and bottom < 12 and piece.face and piece.face[1] == home.facing.x and piece.face[2] == home.facing.z then
			local door = if home.facing.x ~= 0 then home.door.z else home.door.x
			local at = if home.facing.x ~= 0 then wz else wx
			local half = if home.facing.x ~= 0 then hz else hx
			if math.abs(at - door) < half + tuning.DoorClear - 1e-6 then
				table.insert(overDoor, `{name} {piece.name}`)
			end
		end
		-- off a zip line's ladder
		for _, ladder in zipLadders[lot] or {} do
			if piece.face and piece.face[1] == ladder.nx and piece.face[2] == ladder.nz then
				local at = if ladder.nx ~= 0 then wz else wx
				local foot = if ladder.nx ~= 0 then ladder.z else ladder.x
				local half = if ladder.nx ~= 0 then hz else hx
				if math.abs(at - foot) < half + tuning.LadderClear - 1e-6 then
					table.insert(overLadder, `{name} {piece.name}`)
				end
			end
		end
	end
end
for _, style in TowerLooks.Styles do
	print(string.format("  %-10s %d towers", style, styles[style] or 0))
	check(`the {style} look is worn by several towers`, (styles[style] or 0) >= 5, styles[style])
end
print(`  the most parts a look adds: {biggest}`)
check("every look is one of the four", #unknown == 0, table.concat(unknown, ", "))
check("the same look every time (the lot's own dice)", #unstable == 0, table.concat(unstable, ", "))
check(`no look adds more than {tuning.Budget} parts`, #overBudget == 0, table.concat(overBudget, ", "))
check("the roof's things stand on the roof", #outOfRoof == 0, table.concat(outOfRoof, ", "))
check(`the roof's things stay {tuning.RoofHeight} studs low (the zip cables)`, #tooHigh == 0, table.concat(tooHigh, ", "))
check("a zip line's two towers keep their roofs bare", #zipRoof == 0, table.concat(zipRoof, ", "))
check("nothing under head height reaches out over the sidewalk", #lowOut == 0, table.concat(lowOut, ", "))
check("nothing low on the people's walk lines, nothing near the curb", #nearCurb == 0, table.concat(nearCurb, ", "))
check("nothing over an apartment entrance", #overDoor == 0, table.concat(overDoor, ", "))
check("nothing on a zip line's ladder", #overLadder == 0, table.concat(overLadder, ", "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
