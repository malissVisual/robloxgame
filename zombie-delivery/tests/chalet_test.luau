-- 7.1, the Alps step 1: the Suburbs houses as Austrian chalets (shared/ChaletLooks.luau; 10.6: server/SandboxWorld.luau
-- builds the sandbox's house with it) and the houses for sale on the Suburbs lots dressed as chalets
-- (ChaletLooks.estate). For every lot the old city's Suburbs had (shared/Map.luau's 44 house lots before 10.6, kept here
-- as LOTS: a spread of sizes and seeds to build on):
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

-- The old city's Suburbs house lots (shared/Map.luau's, frozen at 10.6): the house's width, depth and height, the lot's
-- size, its seed; its front wall HOUSE_FRONT forward of the lot's middle (Map.HouseFront: its door in the wall's middle).
type Lot = { w: number, d: number, h: number, size: number, seed: number }
local HOUSE_FRONT = 18
local houses: { Lot } = {
	{ w = 24.843384421284668, d = 19.339617220069858, h = 12.99713362659992, size = 50, seed = 491885 },
	{ w = 22.64807839379467, d = 16.928148136407273, h = 12.979071172866105, size = 50, seed = 197229 },
	{ w = 23.31952467869923, d = 16.517217159752935, h = 12.942197539324125, size = 50, seed = 337108 },
	{ w = 24.317705059719927, d = 18.627317036154974, h = 13.415512318644218, size = 50, seed = 38733 },
	{ w = 22.971244310933393, d = 16.622800762413814, h = 13.411758792038782, size = 50, seed = 318980 },
	{ w = 23.87993096362793, d = 18.765061958474163, h = 11.229368947659962, size = 50, seed = 702443 },
	{ w = 24.298724226000463, d = 19.811434339556317, h = 12.310256720343844, size = 50, seed = 680609 },
	{ w = 25.717778886405547, d = 17.936421349585448, h = 11.746259167088438, size = 50, seed = 150213 },
	{ w = 21.339049743804196, d = 19.513525293686918, h = 12.034596871151214, size = 50, seed = 471136 },
	{ w = 25.75983303762957, d = 19.267043209883425, h = 13.58210056841569, size = 50, seed = 307077 },
	{ w = 23.04668860886869, d = 16.470603388241123, h = 11.372174839370116, size = 50, seed = 205889 },
	{ w = 21.962850798818145, d = 17.847333663932357, h = 11.482505048608878, size = 50, seed = 285706 },
	{ w = 24.21259574239384, d = 16.139414178337358, h = 12.24641697457658, size = 50, seed = 424244 },
	{ w = 23.853216798839362, d = 19.085430019614687, h = 11.594373032538568, size = 50, seed = 30797 },
	{ w = 22.117154268657, d = 19.43585974670561, h = 11.289384429146894, size = 50, seed = 549281 },
	{ w = 22.8777236369231, d = 19.06516539777179, h = 12.949202640866119, size = 50, seed = 310279 },
	{ w = 20.441933031605494, d = 17.699662374052835, h = 11.301882207209134, size = 50, seed = 699386 },
	{ w = 25.532067494962426, d = 17.620039898548313, h = 11.709497240567112, size = 50, seed = 830704 },
	{ w = 23.020469451342215, d = 16.72063514098584, h = 12.334223179923578, size = 50, seed = 864732 },
	{ w = 21.008226393729657, d = 17.397575951551623, h = 12.791611883595225, size = 50, seed = 149554 },
	{ w = 24.173509645437363, d = 18.322757307740634, h = 12.363529736049035, size = 50, seed = 363876 },
	{ w = 25.06373642763471, d = 18.41407959946811, h = 12.52728617938914, size = 50, seed = 322177 },
	{ w = 20.537797883653823, d = 18.694509754604205, h = 13.01029538271045, size = 50, seed = 864786 },
	{ w = 20.820487556811877, d = 19.836647527140236, h = 13.109589693238576, size = 50, seed = 740323 },
	{ w = 22.81918782817124, d = 19.343816767766903, h = 12.034408718379595, size = 50, seed = 13433 },
	{ w = 22.732443157334295, d = 19.842480754333064, h = 11.291371962792587, size = 50, seed = 434493 },
	{ w = 23.24001490067692, d = 17.8395550752427, h = 11.872314201083327, size = 50, seed = 364039 },
	{ w = 22.285358479512258, d = 16.359498687423297, h = 12.020916829836477, size = 50, seed = 771941 },
	{ w = 24.542881913057418, d = 16.968571963690753, h = 12.452995591753158, size = 50, seed = 176829 },
	{ w = 23.56839377765394, d = 17.290730526010254, h = 11.639961453750693, size = 50, seed = 459708 },
	{ w = 25.25866602944086, d = 19.37861586863046, h = 11.874956470332068, size = 50, seed = 828403 },
	{ w = 20.3571575101066, d = 17.56686479557945, h = 12.597951579930216, size = 50, seed = 529801 },
	{ w = 25.15019408534299, d = 16.67914179403255, h = 13.140210793018538, size = 50, seed = 89740 },
	{ w = 22.98786091430845, d = 19.356174859550013, h = 12.43749485717853, size = 50, seed = 229775 },
	{ w = 23.452327538702942, d = 18.201785329917247, h = 12.784775641080714, size = 50, seed = 338082 },
	{ w = 23.479676794707473, d = 18.319075983314846, h = 11.087621279608106, size = 50, seed = 22758 },
	{ w = 22.091791699725942, d = 19.251483545872834, h = 11.271694738205237, size = 50, seed = 359829 },
	{ w = 21.101413543430542, d = 16.22217669544944, h = 11.518513217119978, size = 50, seed = 212823 },
	{ w = 22.270588672040578, d = 17.05724793212232, h = 12.811248217067913, size = 50, seed = 716193 },
	{ w = 25.928298341974894, d = 16.592844719619347, h = 11.905652997461756, size = 50, seed = 239377 },
	{ w = 22.784124192580695, d = 18.972648232218482, h = 11.527130382160777, size = 50, seed = 745115 },
	{ w = 24.7234705814379, d = 16.432310186729126, h = 11.033827845504348, size = 50, seed = 772591 },
	{ w = 20.089481155471393, d = 19.56332574371558, h = 11.972738531858417, size = 50, seed = 179031 },
	{ w = 20.248364860423248, d = 16.546871182086758, h = 12.514181096119975, size = 50, seed = 720640 },
}
print(`  {#houses} houses`)
check("the old Suburbs' 44 house lots", #houses == 44, #houses)

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
local swing = math.rad(80) -- (the old city's delivery door swing, Config.Jobs.Places.DoorSwing before 10.6)
for n, lot in houses do
	local id = `lot {n}`
	local spec: ChaletLooks.Spec = { w = lot.w, d = lot.d, h = lot.h, lot = lot.size, front = HOUSE_FRONT, seed = lot.seed, render = n % 5 + 1, shade = (n % 7) * 10 - 30 }
	local pieces = ChaletLooks.house(spec)
	local variant = ChaletLooks.variantOf(lot.seed)
	used[variant] = (used[variant] or 0) + 1
	most = math.max(most, #pieces)
	total += #pieces
	budgetOk = budgetOk and #pieces <= ChaletLooks.Budget
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
		local front, back = -(lot.size / 2 - HOUSE_FRONT), lot.size / 2 + HOUSE_FRONT
		if b[1] < -lot.size / 2 - 1e-6 or b[2] > lot.size / 2 + 1e-6 or b[5] < front - 1e-6 or b[6] > back + 1e-6 or b[3] < -0.05 then
			lotOk = false
			note(`{id} {p.name} off its lot`)
		end
		-- nothing in the door's way out or on the path to the kerb (the walk, out to the curb), from the ground up to
		-- over a mover's head with a wardrobe; the wall's own skin (the door's surround, the plinth beside the door)
		-- stays within 0.13 of the wall
		if p.name ~= "Door" and overlaps(b, { -ChaletLooks.Path, ChaletLooks.Path, 0.05, 9, front - 5, -0.13 }) then
			pathOk = false
			note(`{id} {p.name} on the path`)
		end
		-- the door's swing (DoorSwing outward round its hinge at x = -2): nothing there but the door
		if p.name ~= "Door" then
			for k = 0, 8 do
				local a = swing * k / 8
				for r = 0.5, 4, 0.5 do
					local x, z = -2 + r * math.cos(a), -0.2 - r * math.sin(a)
					if b[1] < x and x < b[2] and b[5] < z and z < b[6] and b[3] < 7 and b[4] > 0.1 then
						pathOk = false
						note(`{id} {p.name} in the door's swing`)
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
check("the house's solid box where it always was (its lot's w, h, d behind the front wall, the door in its middle)", bodyOk)
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
		for _, p in ChaletLooks.house({ w = w, d = 18, h = h, lot = 50, front = HOUSE_FRONT, seed = seed, render = 1, shade = 0 }) do
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
