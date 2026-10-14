-- 8.2 SANDBOX, showing off on the server: the real server/SandboxLeaders.luau with the real server/PlayerData.luau and
-- server/Collection.luau (SandboxLeadersServer.luau, PlayerDataServer.luau, CollectionServer.luau through
-- tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players, DataStore, clock and Net and
-- tests/runtime/LeadersRuntime.luau's OrderedDataStore. The player list: PlayerData's city columns replaced by the
-- sandbox's (in their order, for a player here before the start and one who joins later), their values (the money, $ a
-- minute to a tenth, the collection's worth), the updates throttled (at most one write a second, the last change always
-- lands); the TOP MOVERS board: built once at SandboxLeadersRules.spot with every part inside its footprint, a SurfaceGui
-- on each face, its rows (ranked, the medals, both faces the same, an empty line), written at most every BoardEvery s,
-- a player leaving (their row goes, nothing errors); the all-time best (read once on joining, a higher stored best
-- shown, a new best written at once and then at most every 2 minutes a player with the latest value, written even after
-- they left, never down when another server wrote more, an outage: one warning and a retry 2 minutes later, Studio:
-- never written). Run: python3 tests/run_tests.py [path to the luau binary]

local L = require("./LeadersRuntime")
local E = L.E
local Config = require("./Config")
local Rules = require("./SandboxLeadersRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Leaders = require("./SandboxLeadersServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local S = Config.SandboxLeaders
local STATS = { S.Stats.Money, S.Stats.Income, S.Stats.Collection }
local STORE = S.AllTime.Store

-- A save of today (8.1: every flag, the collection's): `pieces` = { { item, stand? } }.
local function save(userId: number, cash: number, pieces: { { any } }): any
	local entries = {}
	for n, p in pieces do
		table.insert(entries, { uid = `{userId}-{n}`, item = p[1], variant = 1, condition = 1, name = p[1], stand = p[2], got = 0 })
	end
	return {
		money = cash, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
		noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
		vanStages = true, xpCurve = Config.Levels.Curve, cars = { [Config.CompanyVan.Car] = true }, car = Config.CompanyVan.Car,
		collectionKept = true, collection = { entries = entries, nextUid = #pieces + 1 },
	}
end

local function statNames(player: any): string
	local folder = player:FindFirstChild("leaderstats")
	local names = {}
	for _, child in (if folder then folder:GetChildren() else {}) do
		table.insert(names, child.Name)
	end
	return table.concat(names, ", ")
end
local function stat(player: any, name: string): any
	local folder = player:FindFirstChild("leaderstats")
	local value = folder and folder:FindFirstChild(name)
	return if value then value.Value else nil
end
-- What the player list should say now: the profile's money, $ a minute to a tenth, the collection's worth.
local function listRight(player: any): (boolean, string)
	local profile = PlayerData.get(player) :: any
	local worth = Rules.summary(Collection.stock(player)).value
	local income = Rules.perMinute(Collection.incomePerMinute(player))
	local ok = stat(player, STATS[1]) == profile.money and stat(player, STATS[2]) == income and stat(player, STATS[3]) == worth
	return ok, `{stat(player, STATS[1])}/{profile.money} {stat(player, STATS[2])}/{income} {stat(player, STATS[3])}/{worth}`
end

local function paint(side: string): any
	local board = Leaders.board()
	local panel = board and board:FindFirstChild("Panel")
	local gui = panel and panel:FindFirstChild(side)
	return gui and gui:FindFirstChild("Paint")
end
-- The board's rows as one line ("1 Ben $11.5K +$460 ★ 2 $11.5K | 2 Ann …"), the visible ones only.
local function boardText(side: string?): string
	local p = paint(side or "BoardFront")
	local out = {}
	for index = 1, S.Rows do
		local row = p and p:FindFirstChild(`Row{index}`)
		if row and row.Visible then
			local words = {}
			local badge = row:FindFirstChild("Badge")
			table.insert(words, badge and badge:FindFirstChild("rank").Text or "?")
			for _, key in { "name", "value", "income", "legend", "best" } do
				local label = row:FindFirstChild(key)
				table.insert(words, if label then label.Text else "?")
			end
			table.insert(out, table.concat(words, " "))
		end
	end
	return table.concat(out, " | ")
end

PlayerData.start()
Collection.start()

-- ── Before the start: PlayerData's (the city's) columns ────────────────────
L.ordered[STORE] = { ["101"] = 9000 } -- Ann's best, from an earlier day
E.saves.Player_101 = save(101, 1500, { { "sofa", 1 }, { "oil_painting" } })
local A = E.join(101, "Ann")
check("before the start: PlayerData's columns (Level, Money, Deliveries)", statNames(A) == "Level, Money, Deliveries", statNames(A))

-- ── The start ──────────────────────────────────────────────────────────────
Leaders.start()
Leaders.start() -- (a second start does nothing)
local board = Leaders.board()
check("start: the board \"TopMovers\" in the workspace (no workspace.Sandbox here), once", board ~= nil and board.Parent == E.workspace and board.Name == "TopMovers" and #E.workspace:GetChildren() == 2, #E.workspace:GetChildren())
check("start: the all-time store asked for by its name", #L.asked == 1 and L.asked[1] == STORE)
check("start: the list waits for the frame's end", statNames(A) == "Level, Money, Deliveries")
E.flush()
check("a player here before the start: the sandbox's columns in their order, the city's gone", statNames(A) == table.concat(STATS, ", "), statNames(A))
local ok, detail = listRight(A)
check("… their values: $1,500, the sofa's $7.7 a minute, the collection $6,350", ok and stat(A, STATS[1]) == 1500 and stat(A, STATS[2]) == 7.7 and stat(A, STATS[3]) == 6350, detail)
check("the all-time best read once for Ann (the store's $9,000)", L.gets == 1 and Leaders.best(101) == 9000, Leaders.best(101))
check("…and nothing written (her $6,350 is under it)", L.updates == 0)

-- ── The board ──────────────────────────────────────────────────────────────
do
	local spot = Rules.spot()
	local foot = Rules.footprint()
	local a = math.rad(spot.yaw)
	local rx, rz, bx, bz = math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
	local outside: string? = nil
	local parts, unanchored, solid = 0, 0, {}
	for _, d in board:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if not d.Anchored then
				unanchored += 1
			end
			solid[d.Name] = d.CanCollide
			local s = d.Size
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = d.CFrame * E.Mock.Vector3.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2)
						local dx, dz = p.X - spot.x, p.Z - spot.z
						local u, v = dx * rx + dz * rz, dx * bx + dz * bz
						if math.abs(u) > foot.width / 2 + 1e-6 or math.abs(v) > foot.depth / 2 + 1e-6 or p.Y < spot.y - 1 then
							outside = `{d.Name} at {math.floor(u * 10) / 10}, {math.floor(v * 10) / 10}`
						end
					end
				end
			end
		end
	end
	check(`the board's parts ({parts}) all inside SandboxLeadersRules.footprint round its spot, anchored`, outside == nil and parts >= 15 and unanchored == 0, outside)
	check("the posts, the footings and the panel are solid; the roof and the flowers are not", solid.Post and solid.Footing and solid.Panel and solid.Roof == false and solid.Bloom == false and solid.FlowerBox == false)
	local pivot = board.WorldPivot
	check("its pivot: the spot, turned to its yaw (its look to the crossroads)", pivot ~= nil and near(pivot.Position.X, spot.x) and near(pivot.Position.Z, spot.z) and near(-pivot.R[3], (Rules.look(spot))) and board.ModelStreamingMode == "Atomic")
	local panel = board:FindFirstChild("Panel")
	local front, back = panel and panel:FindFirstChild("BoardFront"), panel and panel:FindFirstChild("BoardBack")
	check("a SurfaceGui on each face of the panel (front and back), Range far, PixelsPerStud", front ~= nil and back ~= nil and front.Face == "Front" and back.Face == "Back" and front.MaxDistance == S.Board.Range and front.PixelsPerStud == S.Board.PixelsPerStud and front.ClassName == "SurfaceGui")
	local heads = {}
	for _, column in Rules.columns(S.AllTime.On) do
		local label = paint("BoardFront"):FindFirstChild("Heads"):FindFirstChild("Head_" .. column.key)
		table.insert(heads, if label then label.Text else "?")
	end
	check("its title TOP MOVERS and the columns' titles", string.find(paint("BoardFront"):FindFirstChild("Title").Text, "TOP MOVERS", 1, true) ~= nil and table.concat(heads, " ") == "# MOVER COLLECTION $/MIN LEGENDARY ALL-TIME", table.concat(heads, " "))
end

check("before the first draw: no row shown", boardText() == "")
E.advance(0)
check("the board: Ann first, $6.3K, +$7.7, ★ 1, her all-time $9K", boardText() == "1 Ann $6.3K +$7.7 ★ 1 $9K", boardText())
check("…the other rows hidden, no empty-server line", not paint("BoardFront"):FindFirstChild("Row2").Visible and not paint("BoardFront"):FindFirstChild("Empty").Visible)

-- ── A player joins ─────────────────────────────────────────────────────────
E.advance(3)
E.saves.Player_202 = save(202, 800, { { "knight_armour", 1 }, { "oil_painting", 2 } })
local B = E.join(202, "Ben")
local updatesAt = L.updates
check("a player who joins: the sandbox's columns at the frame's end, their values", statNames(B) == table.concat(STATS, ", ") and (listRight(B)) and stat(B, STATS[3]) == 11500 and stat(B, STATS[2]) == 460, statNames(B))
check("…their all-time best read (none stored)", L.gets == 2 and Leaders.best(202) == 11500)
E.advance(0)
check("…and their first best written at once (UpdateAsync, a whole number)", L.updates == updatesAt + 1 and L.ordered[STORE]["202"] == 11500, L.updates)
local firstBest = E.clock
check("the board at once (its last draw was BoardEvery s ago): Ben first ($11.5K, +$460, ★ 2), Ann second", boardText() == "1 Ben $11.5K +$460 ★ 2 $11.5K | 2 Ann $6.3K +$7.7 ★ 1 $9K", boardText())
check("…both faces the same", boardText("BoardBack") == boardText("BoardFront"))
local row1 = paint("BoardFront"):FindFirstChild("Row1")
local row2 = paint("BoardFront"):FindFirstChild("Row2")
check("the medals: gold for 1, silver for 2", near(row1:FindFirstChild("Badge").BackgroundColor3.G, 196 / 255) and near(row2:FindFirstChild("Badge").BackgroundColor3.G, 212 / 255))
local rows = Leaders.rows()
check("SandboxLeaders.rows: the same ranking (Ben 1, Ann 2) with their numbers", #rows == 2 and rows[1].name == "Ben" and rows[1].rank == 1 and rows[1].legendaries == 2 and rows[2].name == "Ann" and rows[2].best == 9000)

-- ── The throttle ───────────────────────────────────────────────────────────
E.advance(3)
do
	local changes, last = 0, stat(A, STATS[1])
	local times = {}
	for _ = 1, 30 do
		PlayerData.addMoney(A, 1, "Admin")
		E.advance(0.1)
		local now = stat(A, STATS[1])
		if now ~= last then
			changes += 1
			last = now
			table.insert(times, E.clock)
		end
	end
	local apart = true
	for n = 2, #times do
		apart = apart and times[n] - times[n - 1] >= S.Every - 0.15 -- (seen every 0.1 s)
	end
	check(`the money column: 30 changes in 3 s written {changes} times, at least {S.Every} s apart`, changes >= 2 and changes <= 4 and apart, changes)
	E.advance(S.Every + 0.1)
	local right, why = listRight(A)
	check("…the last change lands", right and stat(A, STATS[1]) == (PlayerData.get(A) :: any).money, why)
	-- a change a second after the last write lands at the frame's end; one within a second of a write waits for it
	E.advance(S.Every + 0.1)
	PlayerData.addMoney(A, 5, "Admin")
	E.flush()
	check("a change a second after the last write: written at the frame's end", stat(A, STATS[1]) == (PlayerData.get(A) :: any).money)
	PlayerData.addMoney(A, 5, "Admin")
	E.flush()
	local waiting = stat(A, STATS[1])
	E.advance(0.5)
	local still = stat(A, STATS[1])
	local owed = (PlayerData.get(A) :: any).money
	E.advance(0.6)
	check("…one within a second of a write: written when the second is up", waiting == still and still ~= owed and stat(A, STATS[1]) == (PlayerData.get(A) :: any).money, `{waiting} {still} {stat(A, STATS[1])}`)
end

-- ── The collection changes ─────────────────────────────────────────────────
do
	E.advance(3)
	local uid = Collection.add(A, { item = "knight_armour", condition = 1 })
	check("a piece comes home: the columns and the board follow", uid ~= nil)
	E.advance(S.Every)
	check("…the collection column: $11,850 (the armour in the stock earns nothing yet)", stat(A, STATS[3]) == 11850 and stat(A, STATS[2]) == 7.7, stat(A, STATS[3]))
	Collection.display(A, uid :: string, 2)
	E.advance(S.Every)
	check("…put on show: $ a minute $227.7", stat(A, STATS[2]) == 227.7, stat(A, STATS[2]))
	E.advance(S.BoardEvery)
	check("the board: Ann's $11.9K passes Ben's $11.5K", string.sub(boardText(), 1, 8) == "1 Ann $1" and string.find(boardText(), "2 Ben", 1, true) ~= nil, boardText())
	-- a change with the board idle: drawn at once; more within BoardEvery s of that draw: one draw when it is up
	E.advance(S.BoardEvery * 2)
	Collection.add(B, { item = "piano", condition = 1 })
	E.advance(0)
	local drawn = boardText()
	check("a change with the board idle: drawn at once (Ben's $12.7K first)", string.sub(drawn, 1, 12) == "1 Ben $12.7K", drawn)
	Collection.add(B, { item = "antique_vase", condition = 1 })
	E.advance(0.3)
	Collection.add(A, { item = "toolbox", condition = 1 })
	E.advance(0.3)
	check("…changes within BoardEvery s of the last draw wait", boardText() == drawn)
	E.advance(S.BoardEvery)
	check("…then one draw: Ben's $15.7K, Ann's $11.9K", string.sub(boardText(), 1, 12) == "1 Ben $15.7K" and string.find(boardText(), "2 Ann $11.9K", 1, true) ~= nil, boardText())
end

-- ── The all-time best ──────────────────────────────────────────────────────
do
	check("Ann's $11,850 beat her stored $9,000: written at once (her first write); her $11,940 since waits, but shows", L.ordered[STORE]["101"] == 11850 and Leaders.best(101) == 11940, L.ordered[STORE]["101"])
	-- Ben's new bests ($12,700, $16,200) came less than 2 minutes after his first write: they wait
	check("Ben's new best waits for 2 minutes since his last write", L.ordered[STORE]["202"] == 11500)
	local updates = L.updates
	E.advance(firstBest + S.AllTime.Every - E.clock - 0.5)
	check("…not a moment before", L.updates == updates and L.ordered[STORE]["202"] == 11500)
	E.advance(1)
	check("…then one write with the latest best ($15,700)", L.updates == updates + 1 and L.ordered[STORE]["202"] == 15700, L.ordered[STORE]["202"])
	local times = {}
	for _, w in L.writeTimes do
		if w.key == "202" then
			table.insert(times, w.clock)
		end
	end
	check("Ben's writes 2 minutes apart at least", #times == 2 and times[2] - times[1] >= S.AllTime.Every - 1e-6)
	-- another server wrote a higher best for Ben: his next write never lowers it
	L.ordered[STORE]["202"] = 50000
	E.advance(S.AllTime.Every)
	updates = L.updates
	Collection.add(B, { item = "sofa", condition = 1 }) -- $16,050: his best here, under the store's
	E.advance(S.Every + 0.1)
	check("a higher best from another server stays (the write does nothing, the board shows it)", L.updates == updates + 1 and L.ordered[STORE]["202"] == 50000 and Leaders.best(202) == 50000, L.ordered[STORE]["202"])
	E.advance(S.BoardEvery)
	check("…the board's ALL-TIME: $50K", string.find(boardText(), "1 Ben $16K +$460 ★ 2 $50K", 1, true) ~= nil, boardText())
end

-- ── A player leaves ────────────────────────────────────────────────────────
do
	E.advance(S.AllTime.Every)
	Collection.add(A, { item = "oil_painting", condition = 1 }) -- $17,940: a new best for Ann
	E.advance(S.Every + 0.1)
	local stored = L.ordered[STORE]["101"]
	Collection.add(A, { item = "piano", condition = 1 }) -- $19,140, then she leaves before the next write
	E.leave(A)
	check("Ann leaves: nothing errors (her waiting writes find her gone)", true)
	E.advance(S.BoardEvery + 0.1)
	check("…her row goes; Ben alone, first", boardText() == "1 Ben $16K +$460 ★ 2 $50K", boardText())
	check("…SandboxLeaders.rows: only Ben", #Leaders.rows() == 1 and Leaders.rows()[1].name == "Ben")
	E.advance(S.AllTime.Every)
	check("…her last best still written when her 2 minutes are up ($19,140)", stored == 17940 and L.ordered[STORE]["101"] == 19140, `{stored} {L.ordered[STORE]["101"]}`)
end

-- ── An outage, Studio ──────────────────────────────────────────────────────
do
	L.down = true
	local warnings = #E.warnings
	local gets, updates = L.gets, L.updates
	E.saves.Player_303 = save(303, 100, { { "antique_vase", 1 } })
	local C = E.join(303, "Cy")
	E.advance(0)
	check("the store down: Cy's read fails, his first write too, nothing errors, one warning", L.gets == gets + 1 and L.updates == updates + 1 and #E.warnings == warnings + 1 and string.find(E.warnings[#E.warnings], "[SandboxLeaders]", 1, true) ~= nil, #E.warnings - warnings)
	check("…his columns and his row all the same", (listRight(C)) and stat(C, STATS[3]) == 3000)
	E.advance(S.BoardEvery)
	check("…the board shows his best here ($3K)", string.find(boardText(), "Cy $3K +$78 – $3K", 1, true) ~= nil, boardText())
	E.advance(S.AllTime.Every - S.BoardEvery - 1)
	check("…no second try before 2 minutes", L.updates == updates + 1)
	L.down = false
	E.advance(1.1)
	check("…then the retry, the store back: written, no second warning", L.updates == updates + 2 and L.ordered[STORE]["303"] == 3000 and #E.warnings == warnings + 1)
	E.studio = true
	E.advance(S.AllTime.Every)
	updates = L.updates
	Collection.add(C, { item = "jukebox", condition = 1 })
	E.advance(S.AllTime.Every + S.Every)
	check("Studio: a new best is shown but never written (AllTime.Studio false)", L.updates == updates and L.ordered[STORE]["303"] == 3000 and Leaders.best(303) == 6400, Leaders.best(303))
	E.studio = false
	E.leave(C)
	E.leave(B)
	E.advance(S.BoardEvery + 0.1)
	check("everybody gone: no rows, the empty-server line on both faces", boardText() == "" and paint("BoardFront"):FindFirstChild("Empty").Visible and paint("BoardBack"):FindFirstChild("Empty").Visible)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
