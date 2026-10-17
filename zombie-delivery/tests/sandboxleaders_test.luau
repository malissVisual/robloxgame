-- 8.2 SANDBOX, showing off: shared/SandboxLeadersRules.luau (the money's short words, $ a minute to a tenth, the
-- legendaries counted, the ranking and its ties, a row's words, the board's columns) and where the TOP MOVERS board
-- stands: 9.7 in the lobby (SandboxMap.Lobby.shops.leaders) by the plaza's west edge, its face to the spawn, its whole
-- footprint on flat meadow inside the lobby's hedge, clear of the plots, the portals and their pads, the dispatch, the
-- lobby's lamps and trees (SandboxMap and SandboxScenery's numbers), and clear of everything the real
-- server/SandboxWorld.luau builds there (SandboxWorldServer.luau on tools/perf/world-mock.luau: only meadow under it).
-- The board's own parts inside that footprint: tests/sandboxleaders_runtime_test.luau. Run with tests/run_tests.py.
local Config = require("./Config")
local Rules = require("./SandboxLeadersRules")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local VillageScenery = require("./VillageScenery") -- 8.9: the village's trees

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- ── The money's words ──────────────────────────────────────────────────────

do
	local cases: { { number | string } } = {
		{ 0, "$0" },
		{ 0.04, "$0" },
		{ 0.2, "$0.2" },
		{ 0.25, "$0.3" },
		{ 3, "$3" },
		{ 9.94, "$9.9" },
		{ 9.96, "$10" },
		{ 45, "$45" },
		{ 45.4, "$45" },
		{ 999, "$999" },
		{ 999.6, "$1K" },
		{ 1000, "$1K" },
		{ 1050, "$1K" },
		{ 1234, "$1.2K" },
		{ 1299, "$1.2K" },
		{ 12345, "$12.3K" },
		{ 99999, "$99.9K" },
		{ 100000, "$100K" },
		{ 123456, "$123K" },
		{ 999999, "$999K" },
		{ 1000000, "$1M" },
		{ 3400000, "$3.4M" },
		{ 3456789, "$3.4M" },
		{ 12345678, "$12.3M" },
		{ 1200000000, "$1.2B" },
		{ -5, "$0" },
	}
	local bad: { string } = {}
	for _, case in cases do
		local got = Rules.money(case[1] :: number)
		if got ~= case[2] then
			table.insert(bad, `{case[1]} → {got} (not {case[2]})`)
		end
	end
	check(`money: a tenth under $10, whole dollars to $999, then $1.2K / $12.3K / $123K / $3.4M / $1.2B, never rounded up a unit ({#cases} cases)`, #bad == 0, table.concat(bad, "; "))
	check("money: NaN and ±inf are $0", Rules.money(0 / 0) == "$0" and Rules.money(math.huge) == "$0" and Rules.money(-math.huge) == "$0")
	check("perMinute: to a tenth, never negative, NaN 0", Rules.perMinute(0.24) == 0.2 and Rules.perMinute(12.36) == 12.4 and Rules.perMinute(7) == 7 and Rules.perMinute(-3) == 0 and Rules.perMinute(0 / 0) == 0)
end

-- ── The legendaries and a collection's worth ───────────────────────────────

do
	check("the board counts Config.Collection's top tier", Config.SandboxLeaders.Legendary == Config.Collection.Order[#Config.Collection.Order] and Config.Collection.Tiers[Config.SandboxLeaders.Legendary] ~= nil)
	check("legendary: the oil painting and the knight's armour (their own rarity)", Rules.isLegendary({ item = "oil_painting" }) and Rules.isLegendary({ item = "knight_armour" }))
	check("not legendary: the gold record (worth $1,600 but rare of its own), the piano, an epic vase, an unknown id", not Rules.isLegendary({ item = "gold_record" }) and not Rules.isLegendary({ item = "piano" }) and not Rules.isLegendary({ item = "antique_vase" }) and not Rules.isLegendary({ item = "no_such_thing" }))
	local entries = {
		{ item = "oil_painting", condition = 1, stand = 1 },
		{ item = "knight_armour", condition = 0.4 },
		{ item = "sofa", condition = 0.9, stand = 2 },
		{ item = "piano", condition = 0 },
		{ item = "gold_record", condition = 1 },
		{ item = "no_such_thing", condition = 1 },
	}
	local s = Rules.summary(entries :: any)
	check("summary: 6 pieces worth $14,650 (on show or not, broken or not, an unknown one $0), 2 legendaries", s.count == 6 and s.value == 6000 + 5500 + 350 + 1200 + 1600 and s.legendaries == 2, `{s.count} {s.value} {s.legendaries}`)
	local empty = Rules.summary({})
	check("summary of nothing: 0, $0, no legendaries", empty.count == 0 and empty.value == 0 and empty.legendaries == 0)
end

-- ── The ranking ────────────────────────────────────────────────────────────

local function row(id: number, name: string, value: number, income: number, legendaries: number, best: number?): Rules.Row
	return { userId = id, name = name, value = value, income = income, legendaries = legendaries, best = best, rank = 0 }
end

local function order(rows: { Rules.Row }): string
	local out = {}
	for _, r in rows do
		table.insert(out, `{r.rank}:{r.name}`)
	end
	return table.concat(out, " ")
end

do
	local input = { row(1, "Ann", 500, 4, 0), row(2, "Ben", 12000, 30, 1), row(3, "Cy", 3000, 9, 0), row(4, "Dee", 0, 0, 0) }
	local ranked = Rules.rank(input)
	check("rank: by the collection's worth, best first, ranks 1 … 4", order(ranked) == "1:Ben 2:Cy 3:Ann 4:Dee", order(ranked))
	check("rank: a new list (the input's order kept)", ranked ~= input and input[1].name == "Ann" and #ranked == 4)
	ranked = Rules.rank({ row(1, "Ann", 5000, 10, 0), row(2, "Ben", 5000, 25, 0) })
	check("the same worth: more $ a minute first, no tie", order(ranked) == "1:Ben 2:Ann", order(ranked))
	ranked = Rules.rank({ row(1, "Ann", 5000, 25, 0), row(2, "Ben", 5000, 25, 2) })
	check("the same worth and $ a minute: more legendaries first, no tie", order(ranked) == "1:Ben 2:Ann", order(ranked))
	ranked = Rules.rank({ row(5, "zed", 800, 3, 0), row(6, "Amy", 800, 3, 0), row(7, "Max", 9000, 40, 1), row(8, "Bo", 100, 1, 0) })
	check("a true tie shares the rank (A … Z, any case) and the next one skips: 1, 2, 2, 4", order(ranked) == "1:Max 2:Amy 2:zed 4:Bo", order(ranked))
	ranked = Rules.rank({ row(1, "Ann", 800, 3.001, 0), row(2, "Ben", 800, 3.004, 0) })
	check("$ a minute compared to the cent: 3.001 and 3.004 tie", ranked[1].rank == 1 and ranked[2].rank == 1 and ranked[1].name == "Ann", order(ranked))
	ranked = Rules.rank({ row(9, "Sam", 0, 0, 0), row(3, "Sam", 0, 0, 0), row(4, "Ann", 0, 0, 0) })
	check("nobody owns anything: all first, by name, then by user id", order(ranked) == "1:Ann 1:Sam 1:Sam" and ranked[2].userId == 3 and ranked[3].userId == 9, order(ranked))
	check("rank of nobody: an empty list", #Rules.rank({}) == 0)
end

do
	local words = Rules.cells({ userId = 1, name = "Ann", value = 12345, income = 45.2, legendaries = 2, best = 15500, rank = 1 })
	check("cells: rank, name, $12.3K, +$45, ★ 2, all-time $15.5K", words.rank == "1" and words.name == "Ann" and words.value == "$12.3K" and words.income == "+$45" and words.legend == "★ 2" and words.best == "$15.5K", `{words.value} {words.income} {words.legend} {words.best}`)
	words = Rules.cells({ userId = 1, name = "Bo", value = 300, income = 0.2, legendaries = 0, best = nil, rank = 4 })
	check("cells: +$0.2, no legendary '–', no all-time '–'", words.income == "+$0.2" and words.legend == "–" and words.best == "–" and words.rank == "4")
	words = Rules.cells({ userId = 1, name = "Cy", value = 3400000, income = 0.004, legendaries = 0, best = 1000, rank = 2 })
	check("cells: nothing on show earns '$0'; the all-time never under the worth now", words.income == "$0" and words.value == "$3.4M" and words.best == "$3.4M", `{words.income} {words.best}`)
end

-- ── The board's columns ────────────────────────────────────────────────────

do
	local function sane(columns: { Rules.Column }): string?
		local right = 0
		local keys: { [string]: boolean } = {}
		for _, c in columns do
			if c.x < right - 1e-9 then
				return `{c.key} overlaps the one before`
			end
			if c.width <= 0 or c.x + c.width > 1 + 1e-9 or c.x < 0 then
				return `{c.key} out of the board`
			end
			if keys[c.key] or c.title == "" or not (c.align == "left" or c.align == "center" or c.align == "right") then
				return `{c.key}: a second one, no title or a bad align`
			end
			keys[c.key] = true
			right = c.x + c.width
		end
		return nil
	end
	local withBest, without = Rules.columns(true), Rules.columns(false)
	local keysWith, keysWithout = {}, {}
	for _, c in withBest do
		table.insert(keysWith, c.key)
	end
	for _, c in without do
		table.insert(keysWithout, c.key)
	end
	check("columns with the all-time: # MOVER COLLECTION $/MIN LEGENDARY ALL-TIME, side by side on the board", table.concat(keysWith, " ") == "rank name value income legend best" and withBest[6].title == "ALL-TIME" and sane(withBest) == nil, sane(withBest))
	check("columns without it: no ALL-TIME, the rest wider", table.concat(keysWithout, " ") == "rank name value income legend" and sane(without) == nil and without[2].width > withBest[2].width, sane(without))
	withBest[1].x = 0.5
	check("columns: copies (a caller's change stays its own)", Rules.columns(true)[1].x ~= 0.5)
	local cellKeys = Rules.cells(row(1, "Ann", 1, 1, 1, 1))
	local all = true
	for _, c in Rules.columns(true) do
		all = all and cellKeys[c.key] ~= nil
	end
	check("every column has its words in a row's cells", all)
end

-- ── Where the board stands ─────────────────────────────────────────────────

local spot = Rules.spot()
local C = SandboxScenery.Clear
local corners = Rules.corners(spot)
local foot = Rules.footprint()

-- Points all over the footprint (its edges and inside, every half stud), grown by `by` studs all round.
local function samples(by: number): { { number } }
	local a = math.rad(spot.yaw)
	local rx, rz, bx, bz = math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
	local w, d = foot.width / 2 + by, foot.depth / 2 + by
	local out = {}
	local steps = math.ceil(2 * w / 0.5)
	local deep = math.ceil(2 * d / 0.5)
	for i = 0, steps do
		for j = 0, deep do
			local u, v = -w + 2 * w * i / steps, -d + 2 * d * j / deep
			table.insert(out, { spot.x + rx * u + bx * v, spot.z + rz * u + bz * v })
		end
	end
	return out
end

do
	local own = SandboxMap.Lobby.shops.leaders.spot
	local plaza = SandboxMap.Lobby.plaza
	check("9.7: the spot: the lobby's (SandboxMap.Lobby.shops.leaders), just west of its plaza", spot.x == own.x and spot.z == own.z and spot.yaw == own.yaw
		and SandboxMap.inLobby(spot.x, spot.z) and spot.x < plaza.x0 and plaza.x0 - spot.x < 60 and spot.z > plaza.z0 and spot.z < plaza.z1, `{spot.x}, {spot.z}`)
	local lx, lz = Rules.look(spot)
	local cx, cz = SandboxMap.Lobby.spawn.x, SandboxMap.Lobby.spawn.z
	local tx, tz = cx - spot.x, cz - spot.z
	local cos = (lx * tx + lz * tz) / math.sqrt(tx * tx + tz * tz)
	check("its face looks across the plaza at the spawn (within 20°)", cos > math.cos(math.rad(20)), cos)
	check("the footprint: the roof's (the panel and Over each side, Run each way)", foot.width == Config.SandboxLeaders.Board.Width + 2 * Config.SandboxLeaders.Board.Roof.Over and foot.depth == 2 * Config.SandboxLeaders.Board.Roof.Run)
	local d01 = math.sqrt((corners[1].x - corners[2].x) ^ 2 + (corners[1].z - corners[2].z) ^ 2)
	local d12 = math.sqrt((corners[2].x - corners[3].x) ^ 2 + (corners[2].z - corners[3].z) ^ 2)
	local mx = (corners[1].x + corners[3].x) / 2
	local mz = (corners[1].z + corners[3].z) / 2
	check("corners: the footprint's rectangle round the spot, turned with it", #corners == 4 and math.abs(d01 - foot.width) < 1e-6 and math.abs(d12 - foot.depth) < 1e-6 and math.abs(mx - spot.x) < 1e-6 and math.abs(mz - spot.z) < 1e-6)
	local fx, fz = corners[1].x - corners[4].x, corners[1].z - corners[4].z -- (from the back edge to the front one)
	check("corners 1 and 2 are the front's (the face's side)", fx * lx + fz * lz > 0)
end

do
	local L = SandboxMap.Lobby
	local why: string? = nil
	local margin = 3 -- studs past the lamps, the trees: room to walk round the board
	local keep: { { name: string, rect: any, by: number } } = {}
	for _, plot in SandboxMap.Plots do
		table.insert(keep, { name = `plot {plot.id}`, rect = plot.rect, by = C.Plot })
	end
	for _, portal in L.portals do
		table.insert(keep, { name = `{portal.house}'s portal`, rect = portal.foot, by = margin })
		table.insert(keep, { name = `{portal.house}'s pad`, rect = portal.pad, by = margin })
	end
	local d = L.dispatch
	table.insert(keep, { name = "the dispatch", rect = { x0 = d.x - 4, x1 = d.x + 4, z0 = d.z - 3, z1 = d.z + 3 }, by = margin })
	table.insert(keep, { name = "the paint shop", rect = L.shops.paint.rect, by = margin })
	table.insert(keep, { name = "the Auction House", rect = L.shops.auction.rect, by = margin })
	table.insert(keep, { name = "the plaza", rect = L.plaza, by = 0 })
	for _, p in samples(0) do
		local x, z = p[1], p[2]
		local b = L.bounds
		if x < b.x0 + L.hedge + C.Edge or x > b.x1 - L.hedge - C.Edge or z < b.z0 + L.hedge + C.Edge or z > b.z1 - L.hedge - C.Edge then
			why = "on the lobby's hedge"
		end
		for _, k in keep do
			if SandboxScenery.rectDistance(k.rect, x, z) < k.by then
				why = `on {k.name} at {x}, {z}`
			end
		end
		for _, l in L.lamps do
			if math.sqrt((x - l.x) ^ 2 + (z - l.z) ^ 2) < margin then
				why = `on the lamp at {l.x}, {l.z}`
			end
		end
		for _, t in L.trees do
			if math.sqrt((x - t.x) ^ 2 + (z - t.z) ^ 2) < 6 + margin then
				why = `under the tree at {t.x}, {t.z}`
			end
		end
		if math.abs(SandboxScenery.groundAt(x, z) - SandboxMap.GroundTop) > 1e-9 then
			why = `on a mound at {x}, {z}`
		end
	end
	check("the board's footprint: inside the lobby's hedge, clear of the plots, the portals and their pads, the dispatch, the paint shop, the Auction House, the plaza, the lamps and the trees, on flat meadow", why == nil, why)
	check("…and it stands on the meadow's top", spot.y == SandboxMap.GroundTop)
end

-- ── Clear of the world the map builds ──────────────────────────────────────

do
	require("./WorldMock")
	local SandboxWorld = require("./SandboxWorldServer")
	local world = SandboxWorld.build()
	-- the footprint grown by 1.5 studs, as a turned rectangle: its axes and half sizes (a separating-axis test against
	-- each part's box on the ground)
	local a = math.rad(spot.yaw)
	local axes = { { math.cos(a), -math.sin(a) }, { math.sin(a), math.cos(a) } }
	local halves = { foot.width / 2 + 1.5, foot.depth / 2 + 1.5 }
	local function overlaps(x0: number, x1: number, z0: number, z1: number): boolean
		-- the world's axes
		local px = { spot.x - math.abs(axes[1][1]) * halves[1] - math.abs(axes[2][1]) * halves[2], spot.x + math.abs(axes[1][1]) * halves[1] + math.abs(axes[2][1]) * halves[2] }
		local pz = { spot.z - math.abs(axes[1][2]) * halves[1] - math.abs(axes[2][2]) * halves[2], spot.z + math.abs(axes[1][2]) * halves[1] + math.abs(axes[2][2]) * halves[2] }
		if px[2] < x0 or px[1] > x1 or pz[2] < z0 or pz[1] > z1 then
			return false
		end
		-- the footprint's axes
		local cx, cz, hx, hz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2
		for n, axis in axes do
			local centre = (cx - spot.x) * axis[1] + (cz - spot.z) * axis[2]
			local reach = math.abs(axis[1]) * hx + math.abs(axis[2]) * hz
			if math.abs(centre) > halves[n] + reach then
				return false
			end
		end
		return true
	end
	local hit: string? = nil
	local seen = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Meadow" and d.Name ~= "Mound" then
			seen += 1
			local size = d.Size
			local x, _, z, r00, r01, r02, _, _, _, r20, r21, r22 = d.CFrame:GetComponents()
			local hx = (math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2
			local hz = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
			if overlaps(x - hx, x + hx, z - hz, z + hz) then
				hit = `{d.Name} at {math.floor(x)}, {math.floor(z)}`
			end
		end
	end
	check(`nothing the map builds stands within 1.5 studs of the board's footprint, only meadow under it ({seen} parts looked at)`, hit == nil and seen > 300, hit)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
