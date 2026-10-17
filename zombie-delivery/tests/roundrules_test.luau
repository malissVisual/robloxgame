-- 10.5 ROUNDS: shared/RoundRules.luau, the rules of a round (Config.Rounds): the next place (never the same twice in a
-- row), its difficulty, the round's table (the most value first, then the most pieces, then who came first; the same
-- share a place), the vans' spots at every place (enough for a full server, inside its zone, off the house's lot, never
-- on each other, the curb's first), where the players land (rows by the door), the clock; and no zombies at any
-- difficulty any more. The server's side (the countdown, the vans, Load at your own van, the results): tests/
-- rounds_runtime_test.luau. Run with tests/run_tests.py.
local Config = require("./Config")
local RoundRules = require("./RoundRules")
local RunRules = require("./RunRules")
local SandboxMap = require("./SandboxMap")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Q = Config.Rounds
local FULL = 16 -- (the owner: "16 people on one server")

-- ── The place, the difficulty ─────────────────────────────────────────────

do
	local ids = { "a", "b", "c" }
	local never = true
	for n = 0, 99 do
		if RoundRules.pick(ids, "b", n / 100) == "b" then
			never = false
		end
	end
	check("pick: never the last place again while there is another", never)
	check("pick: the roll picks among the others in order (a … c)", RoundRules.pick(ids, "b", 0) == "a" and RoundRules.pick(ids, "b", 0.99) == "c"
		and RoundRules.pick(ids, nil, 0.5) == "b")
	check("pick: one place only: that one again; none: nil", RoundRules.pick({ "a" }, "a", 0.3) == "a" and RoundRules.pick({}, nil, 0.3) == nil)
	check("difficulty: one of the list by the roll; none: Config.Runs.Default", RoundRules.difficulty({ "easy", "hard" }, 0) == "easy"
		and RoundRules.difficulty({ "easy", "hard" }, 0.999) == "hard" and RoundRules.difficulty({}, 0.5) == Config.Runs.Default)
	local known = #Q.Difficulties > 0
	for _, id in Q.Difficulties do
		known = known and RunRules.def(id) ~= nil
	end
	check("Config.Rounds.Difficulties: every one a known difficulty", known)
end

-- ── The table ─────────────────────────────────────────────────────────────

do
	local players = { { id = 1, name = "Ann" }, { id = 2, name = "Bob" }, { id = 3, name = "Cid" }, { id = 4, name = "Dee" } }
	local rows = RoundRules.ranking({
		{ to = 2, value = 300 },
		{ to = 1, value = 120.4 },
		{ to = 2, value = 50 },
		{ to = 3, value = 100 },
		{ to = 3, value = 20.4 },
		{ to = 9, value = 999 }, -- (nobody of the round's: never counted)
	}, players)
	local order = {}
	for _, row in rows do
		table.insert(order, `{row.name}:{row.count}:{row.value}:{row.place}`)
	end
	check("ranking: the most value first (Bob 350, Ann 120, Cid 120 on two pieces), everybody in it (Dee 0); a stranger's piece not counted",
		table.concat(order, " ") == "Bob:2:350:1 Cid:2:120:2 Ann:1:120:3 Dee:0:0:4", table.concat(order, " "))
	local tie = RoundRules.ranking({ { to = 1, value = 100 }, { to = 2, value = 100 } }, players)
	check("ranking: the same value and count share a place (then who came first); nobody's: the last place shared",
		tie[1].name == "Ann" and tie[1].place == 1 and tie[2].name == "Bob" and tie[2].place == 1 and tie[3].place == 3 and tie[4].place == 3)
	check("rankOf: a player's row, nil for a stranger", (RoundRules.rankOf(rows, 3) :: any).place == 2 and RoundRules.rankOf(rows, 9) == nil)
	check("ranking: nobody loaded anything: everybody at 0, in the order they came", RoundRules.ranking({}, players)[1].name == "Ann" and RoundRules.ranking({}, players)[4].value == 0)
end

-- ── The vans' spots ───────────────────────────────────────────────────────

local function extent(spot: any, P: any): (number, number)
	local a = math.rad(spot.yaw)
	local lx, lz = math.abs(math.sin(a)), math.abs(math.cos(a))
	return lx * P.Length / 2 + lz * P.Width / 2, lz * P.Length / 2 + lx * P.Width / 2
end

for _, house in SandboxMap.Houses do
	local zone = SandboxMap.zone(house.id)
	if not zone then
		continue
	end
	local P = Q.Park
	local spots = RoundRules.parking(house.curb, zone.rect, house.lot, FULL, P)
	local inside, offLot, apart = true, true, true
	for n, s in spots do
		local ex, ez = extent(s, P)
		if s.x - ex < zone.rect.x0 + P.Margin - 0.01 or s.x + ex > zone.rect.x1 - P.Margin + 0.01 or s.z - ez < zone.rect.z0 + P.Margin - 0.01 or s.z + ez > zone.rect.z1 - P.Margin + 0.01 then
			inside = false
		end
		local lot = house.lot
		if s.x + ex > lot.x0 + 0.01 and s.x - ex < lot.x1 - 0.01 and s.z + ez > lot.z0 + 0.01 and s.z - ez < lot.z1 - 0.01 then
			offLot = false
		end
		for m = n + 1, #spots do
			local o = spots[m]
			if math.abs(o.x - s.x) < 2 * ex - 0.01 and math.abs(o.z - s.z) < 2 * ez - 0.01 then
				apart = false
			end
		end
	end
	local first = spots[1]
	check(`parking at {house.name}: room for {FULL} vans ({#spots} spots), inside the zone ({P.Margin} studs off its edge), off the house's lot, none on another, the curb's first, all facing the curb's way`,
		#spots >= FULL and inside and offLot and apart and first ~= nil and math.abs(first.x - house.curb.x) < 0.01 and math.abs(first.z - house.curb.z) < 0.01
			and first.yaw == house.curb.yaw and spots[#spots].yaw == house.curb.yaw,
		`{#spots} spots, inside {inside}, off the lot {offLot}, apart {apart}`)
	local zoneHouse = zone.arrive
	local landed = RoundRules.spread(zoneHouse, FULL, Q.Spread)
	local inZone = true
	for _, s in landed do
		inZone = inZone and s.x > zone.rect.x0 and s.x < zone.rect.x1 and s.z > zone.rect.z0 and s.z < zone.rect.z1
	end
	check(`spread at {house.name}: {FULL} players land inside its zone`, #landed == FULL and inZone)
end

do
	local spot = { x = 0, y = 3, z = 100, yaw = 0 } -- (looking north, -z: the door that way)
	local S = { PerRow = 4, Apart = 3, Back = 2 }
	local out = RoundRules.spread(spot, 6, S)
	check("spread: rows of PerRow abreast, centred on the spot, Apart apart; the next row Back nearer the way it looks (the door)",
		#out == 6 and out[1].x == -4.5 and out[4].x == 4.5 and out[1].z == 100 and out[5].z == 98 and out[5].x == -1.5 and out[6].x == 1.5 and out[6].yaw == 0,
		`{out[1].x} {out[4].x} {out[5].z} {out[5].x}`)
	check("spread: one player stands on the spot itself", RoundRules.spread(spot, 1, S)[1].x == 0 and RoundRules.spread(spot, 1, S)[1].z == 100)
end

check("clock: m:ss, whole seconds up, never under 0", RoundRules.clock(300) == "5:00" and RoundRules.clock(61.2) == "1:02" and RoundRules.clock(-3) == "0:00")

-- ── 10.5 no zombies ───────────────────────────────────────────────────────

do
	local none = true
	for id, level in Config.Runs.Danger do
		if level.Inside ~= 0 or level.Yard ~= 0 or level.Wave ~= 0 or level.Boss or level.Weapon or next(level.Kinds) ~= nil then
			none = false
			print("  zombies at " .. id)
		end
	end
	check("10.5 (the owner: \"zombies I don't want in the game at all\"): no zombie at any difficulty, no boss, no bat", none)
end

if failures > 0 then
	error(`{failures} checks failed`)
end
print("ALL CHECKS PASSED")
