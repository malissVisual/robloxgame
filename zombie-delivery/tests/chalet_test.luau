-- 7.1, the Alps step 1: the Suburbs houses as Austrian chalets (shared/ChaletLooks.luau; server/Chalets.luau builds
-- them, World's buildHouse hands it each house's lot and the world's dice) and the houses for sale on the Suburbs lots
-- dressed as chalets (ChaletLooks.estate). For every house of the map (Map.Homes, kind "house"):
--   * the gameplay where it was: the house's solid box (its lot's w, h, d behind the front wall), the "Door" (Cargo
--     swings it open for a delivery: found by its name next to the home's door, solid and queryable), the two
--     ground-floor windows lit by the world's two window dice; the only solid pieces the body, the gable and the door
--   * nothing in the door's swing or on the path from the door to the kerb (couriers, receivers, movers), nothing over
--     the lot's edges, nothing under the walk
--   * within the part budget (ChaletLooks.Budget a chalet; the whole Suburbs' houses under the 7.1 budget; 7.1 review:
--     about 32 parts a chalet, it was 45), the three looks all used, the roof steep with wide eaves, the balcony under
--     the roof's verge
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Map = require("./Map")
local ChaletLooks = require("./ChaletLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Every Suburbs house's lot.
local houses: { Map.Lot } = {}
for _, list in Map.lots("suburbs") do
	for _, lot in list do
		if lot.kind == "house" and lot.home then
			table.insert(houses, lot)
		end
	end
end
local homes = 0
for _, home in Map.Homes do
	homes += if home.kind == "house" then 1 else 0
end
print(`  {#houses} houses in the Suburbs`)
check("every house of Map.Homes stands on a Suburbs lot (44 in 7.0)", #houses == homes and #houses >= 30, #houses)

local function overlaps(a: { number }, b: { number }): boolean
	return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4] and a[5] < b[6] and b[5] < a[6]
end
local function boxOf(piece: ChaletLooks.Piece): { number }
	local x0, x1, y0, y1, z0, z1 = ChaletLooks.box(piece)
	return { x0, x1, y0, y1, z0, z1 }
end

local bodyOk, doorOk, windowsOk, solidOk, pathOk, lotOk, budgetOk = true, true, true, true, true, true, true
local used: { [number]: number } = {}
local most, total = 0, 0
local notes: { string } = {}
local function note(text: string)
	if #notes < 8 then
		table.insert(notes, text)
	end
end
local swing = math.rad(Config.Jobs.Places.DoorSwing)
for n, lot in houses do
	local home = lot.home :: Map.Home
	local spec: ChaletLooks.Spec = { w = lot.w, d = lot.d, h = lot.h, lot = lot.size, front = Map.HouseFront, seed = lot.seed, render = n % 5 + 1, shade = (n % 7) * 10 - 30 }
	local pieces = ChaletLooks.house(spec)
	local variant = ChaletLooks.variantOf(lot.seed)
	used[variant] = (used[variant] or 0) + 1
	most = math.max(most, #pieces)
	total += #pieces
	budgetOk = budgetOk and #pieces <= ChaletLooks.Budget
	-- the house's door where Map.Homes has it: the middle of the front wall, Map.HouseFront forward of its lot's middle
	local out = (home.door.x - home.x) * home.facing.x + (home.door.z - home.z) * home.facing.z
	doorOk = doorOk and math.abs(out - Map.HouseFront) < 1e-6
	local bodies, doors, windows = 0, 0, {}
	local names: { [string]: number } = {}
	for _, p in pieces do
		names[p.name] = (names[p.name] or 0) + 1
		if p.name == "House" then
			bodies += 1
			bodyOk = bodyOk and p.solid == true and p.size[1] == lot.w and p.size[2] == lot.h and p.size[3] == lot.d
				and p.at[1] == 0 and p.at[2] == lot.h / 2 and p.at[3] == lot.d / 2 and p.turn == nil
		elseif p.name == "Door" then
			doors += 1
			doorOk = doorOk and p.solid == true and p.size[1] == 4 and p.size[2] == 7 and p.size[3] == 0.4 and p.at[1] == 0 and p.at[2] == 3.5 and p.at[3] == -0.2
		elseif p.name == "Window" then
			table.insert(windows, p.window or 0)
			windowsOk = windowsOk and p.material == "Glass" and p.at[3] > -0.4
		end
		solidOk = solidOk and ((p.solid == true) == (p.name == "House" or p.name == "Door" or p.name == "Roof"))
		local b = boxOf(p)
		-- on its lot (the front edge lot / 2 - HouseFront out from the wall, the back edge lot / 2 + HouseFront in), not
		-- under the walk
		local front, back = -(lot.size / 2 - Map.HouseFront), lot.size / 2 + Map.HouseFront
		if b[1] < -lot.size / 2 - 1e-6 or b[2] > lot.size / 2 + 1e-6 or b[5] < front - 1e-6 or b[6] > back + 1e-6 or b[3] < -0.05 then
			lotOk = false
			note(`{home.id} {p.name} off its lot`)
		end
		-- nothing in the door's way out or on the path to the kerb (the walk, out to the curb), from the ground up to
		-- over a mover's head with a wardrobe; the wall's own skin (the door's surround, the plinth beside the door)
		-- stays within 0.13 of the wall
		if p.name ~= "Door" and overlaps(b, { -ChaletLooks.Path, ChaletLooks.Path, 0.05, 9, front - 5, -0.13 }) then
			pathOk = false
			note(`{home.id} {p.name} on the path`)
		end
		-- the door's swing (DoorSwing outward round its hinge at x = -2): nothing there but the door
		if p.name ~= "Door" then
			for k = 0, 8 do
				local a = swing * k / 8
				for r = 0.5, 4, 0.5 do
					local x, z = -2 + r * math.cos(a), -0.2 - r * math.sin(a)
					if b[1] < x and x < b[2] and b[5] < z and z < b[6] and b[3] < 7 and b[4] > 0.1 then
						pathOk = false
						note(`{home.id} {p.name} in the door's swing`)
					end
				end
			end
		end
	end
	bodyOk = bodyOk and bodies == 1
	doorOk = doorOk and doors == 1
	table.sort(windows)
	windowsOk = windowsOk and #windows == 2 and windows[1] == 1 and windows[2] == 2
	for name, count in names do
		if name == "House" or name == "Door" then
			budgetOk = budgetOk and count == 1
		end
	end
end
for _, text in notes do
	print("  " .. text)
end
print(`  pieces: {most} at most a house, {total} in all ({#houses} houses); looks: tyrol {used[1] or 0}, salzburg {used[2] or 0}, bregenz {used[3] or 0}`)
check("the house's solid box where it always was (its lot's w, h, d behind the front wall, Map.Homes' door in its middle)", bodyOk)
check("the Door where it always was, solid (Cargo finds it by its name and swings it open)", doorOk)
check("two ground-floor windows, lit at night by the world's two window dice", windowsOk)
check("solid: the body, the gable and the door only (everything else decoration: nothing to bump into)", solidOk)
check("nothing in the door's swing or on the path from the door to the kerb", pathOk)
check("everything on its own lot, nothing under the walk", lotOk)
check(`within the budget: {ChaletLooks.Budget} pieces a chalet at most, one body and one door each`, budgetOk and most <= ChaletLooks.Budget, most)
-- (7.1's budget: the Suburbs' houses were about 11 parts each with the path, the mailbox and the tree; the whole city
-- 22,851 parts in 7.0: the chalets and the square stay within 15 % of it, tools/perf/world_count.py)
check("the chalets add less than 15 % of the city's 7.0 parts (22,851)", (total - 6 * #houses) <= 22851 * 0.15, total - 6 * #houses)
-- 7.1 review: what stood together is one piece (the plinth, the fence and its rail, the firewood, a flower box and its
-- geraniums, the balcony's box with its flowers), the purlin ends gone: 13 pieces fewer a chalet (31.6 on the map on
-- average, 44.6 before)
check("7.1 review: at most 32 pieces a chalet on average (it was 44.6)", total <= 32 * #houses, string.format("%.1f", total / #houses))
check("the three looks all on the map (tyrol, salzburg, bregenz)", (used[1] or 0) >= 5 and (used[2] or 0) >= 5 and (used[3] or 0) >= 5)

-- The roof: steep, its eaves wide; the balcony under its verge; for every width a house may have.
local roofOk = true
for w = 20, 26, 0.5 do
	local rise, widest = ChaletLooks.roof(w)
	local pitch = math.deg(math.atan(rise / (w / 2)))
	roofOk = roofOk and pitch >= 33 and pitch <= 45 and widest >= 10 and widest <= w - 3 + 1e-6
	for variant = 1, 3 do
		local seed = 0
		while ChaletLooks.variantOf(seed) ~= variant do
			seed += 1
		end
		local h = 11
		for _, p in ChaletLooks.house({ w = w, d = 18, h = h, lot = 50, front = Map.HouseFront, seed = seed, render = 1, shade = 0 }) do
			if p.name == "BalconySide" or p.name == "HandRail" then
				-- its ends under the roof's verge (the shingles' underside over it), not through it
				local b = boxOf(p)
				local edge = math.max(math.abs(b[1]), math.abs(b[2]))
				local verge = h + rise * (1 - edge / (w / 2))
				roofOk = roofOk and b[4] <= verge - 0.3
			elseif p.name == "RoofShingles" then
				local b = boxOf(p)
				roofOk = roofOk and (math.abs(b[1]) >= w / 2 + 1.5 or math.abs(b[2]) >= w / 2 + 1.5) -- (its eave 1.5 and more out)
			end
		end
	end
end
check("a steep roof (33 to 45°) with wide eaves, the balcony under its verge", roofOk)

-- The houses for sale on the Suburbs lots: their dress outside their walls, off their door and windows.
local estateOk = true
for _, upper in { false, true } do
	local layout: ChaletLooks.EstateLayout = {
		x0 = -22,
		x1 = 8,
		z0 = -10,
		z1 = 10,
		eaves = 11,
		upper = upper,
		windows = { { at = -18.5, width = 4, bottom = 3.3, top = 8.3 }, { at = -2, width = 5, bottom = 4.3, top = 8.3 } },
		door = { at = -14, width = 5 },
	}
	local pieces = ChaletLooks.estate(layout)
	estateOk = estateOk and #pieces <= (if upper then 18 else 9) -- (7.1 review: 24 and 13 before)
	for _, p in pieces do
		local b = boxOf(p)
		-- outside the walls (nothing inside the rooms)
		local inside = b[1] > -22 + 0.01 and b[2] < 8 - 0.01 and b[5] > -10 + 0.01 and b[6] < 10 - 0.01
		-- off the door (x -14, 5 wide, 8.3 tall) and the windows' glass, out to 3 studs in front of the wall
		local door = overlaps(b, { -16.5, -11.5, 0.05, 8.3, -13, -10.01 })
		local glass = false
		for _, wnd in layout.windows do
			glass = glass or overlaps(b, { wnd.at - wnd.width / 2, wnd.at + wnd.width / 2, wnd.bottom + 0.6, wnd.top, -10.3, -10 })
		end
		estateOk = estateOk and not inside and not door and not glass and not p.solid and b[2] <= 8 + 0.2
	end
end
check("a house for sale's dress: outside its walls, off its door and its windows' glass, decoration only", estateOk)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
