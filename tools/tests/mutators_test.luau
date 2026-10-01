-- Logic test of the wave twists (Mutators.luau) and the formations (Formations.luau). Run by run_mutators_test.py.
local Stubs = require("./stubs")
local Vector3 = Stubs.Vector3
local Balance = require("./Balance")
local Mutators = require("./Mutators")
local Formations = require("./Formations")

local failures = 0
local checks = 0
local function check(ok, message)
	checks += 1
	if not ok then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- A fake map: 100 waves, 20 phases, four kinds per phase (archetypes by a name map).
local ARCH = { Grunt = "Grunt", Archer = "Archer", Brute = "Brute", Shaman = "Shaman", Boss = "Chief", Treasure = "Treasure", Totem = "Totem" }
local function archetypeOf(kind)
	return ARCH[kind]
end
local map = { waves = 100, phases = {} }
for n = 1, 20 do
	map.phases[n] = { name = "Phase " .. n, kinds = { "Grunt", "Grunt", "Archer", "Brute", "Shaman" }, boss = "Boss" }
end

local function ids(list)
	local out = {}
	for _, def in list do
		table.insert(out, def.id)
	end
	return out
end
local function same(a, b)
	if #a ~= #b then
		return false
	end
	for i, x in a do
		if b[i] ~= x then
			return false
		end
	end
	return true
end

-- (1) Deterministic: two calls (and a fresh map table) give the same ids.
for wave = 1, 100 do
	local a, b = Mutators.forWave(wave, map), Mutators.forWave(wave, map)
	check(same(ids(a), ids(b)), "forWave deterministic at wave " .. wave)
end
local map2 = { waves = 100, phases = map.phases }
for wave = 1, 100 do
	check(same(ids(Mutators.forWave(wave, map)), ids(Mutators.forWave(wave, map2))), "forWave equal across map tables at wave " .. wave)
end

-- (2) Slots per wave.
for wave = 1, 100 do
	local list = Mutators.forWave(wave, map)
	local boss = wave % Balance.PhaseLength == 0
	local expected
	if wave < 3 or wave == 100 then
		expected = 0
	elseif boss then
		expected = if wave >= 25 then 1 else 0
	elseif wave <= 40 then
		expected = 1
	elseif wave <= 70 then
		expected = if wave % 3 == 0 then 2 else 1
	else
		expected = 2
	end
	check(#list == expected, string.format("wave %d has %d twists, expected %d", wave, #list, expected))
	if boss then
		for _, def in list do
			check(def.bossOk, "boss wave " .. wave .. " got a twist without bossOk: " .. def.id)
		end
	end
	for _, def in list do
		check(def.minWave <= wave, "wave " .. wave .. " got a twist before its minWave: " .. def.id)
	end
end

-- (3) No id repeats within 2 consecutive waves.
for wave = 3, 99 do
	local list = Mutators.forWave(wave, map)
	for back = 1, 2 do
		for _, def in list do
			for _, earlier in Mutators.forWave(wave - back, map) do
				check(def.id ~= earlier.id, string.format("twist %s repeats at wave %d (used at %d)", def.id, wave, wave - back))
			end
		end
	end
end

-- (4) Double waves: different tags, no exclusion either way, threat ≤ 2.1.
local function excludes(def, id)
	for _, other in def.excludes do
		if other == id then
			return true
		end
	end
	return false
end
for wave = 3, 99 do
	local list = Mutators.forWave(wave, map)
	if #list == 2 then
		local a, b = list[1], list[2]
		check(a.tag ~= b.tag, string.format("wave %d: same tag %s + %s", wave, a.id, b.id))
		check(not excludes(a, b.id) and not excludes(b, a.id), string.format("wave %d: excluded pair %s + %s", wave, a.id, b.id))
		check(a.threat + b.threat <= 2.1 + 1e-9, string.format("wave %d: threat %.2f", wave, a.threat + b.threat))
		check(a.id ~= b.id, "wave " .. wave .. " picked the same twist twice")
	end
end

-- (5) Every twist appears at least 3 times over waves 3-99.
local uses = {}
for wave = 3, 99 do
	for _, def in Mutators.forWave(wave, map) do
		uses[def.id] = (uses[def.id] or 0) + 1
	end
end
for _, id in Mutators.Order do
	check((uses[id] or 0) >= 3, string.format("twist %s used only %d times", id, uses[id] or 0))
end

-- (6) The coin bonus is capped.
local all = {}
for _, id in Mutators.Order do
	table.insert(all, Mutators.Defs[id])
end
check(Mutators.coinBonus(all) <= 0.35 + 1e-9, "coinBonus over the cap")
check(Mutators.coinBonus({}) == 0, "coinBonus of nothing is 0")
check(math.abs(Mutators.coinBonus({ Mutators.Defs.swift, Mutators.Defs.shielded }) - 0.15) < 1e-9, "coinBonus sums")

-- (7) Composition rewrites.
local function wave12()
	local list = {}
	for i = 1, 12 do
		table.insert(list, { kind = ({ "Grunt", "Grunt", "Archer", "Brute", "Shaman" })[(i - 1) % 5 + 1], tier = 4 })
	end
	return list
end
local swarm = Mutators.applyComposition(wave12(), { Mutators.Defs.swarm }, 30, archetypeOf)
check(#swarm <= 18 and #swarm == 18, "swarm count " .. #swarm)
for _, e in swarm do
	check(e.kind == "Grunt" or e.kind == "Archer", "swarm kind " .. e.kind)
end
local small = Mutators.applyComposition({ { kind = "Grunt", tier = 1 }, { kind = "Grunt", tier = 1 }, { kind = "Grunt", tier = 1 }, { kind = "Grunt", tier = 1 } }, { Mutators.Defs.swarm }, 10, archetypeOf)
check(#small == 6, "swarm of 4 → 6, got " .. #small)
local big = Mutators.applyComposition(wave12(), { Mutators.Defs.bigBoys }, 30, archetypeOf)
check(#big == 10, "bigBoys 12 → 10, got " .. #big)
check(big[1].tier == 5, "bigBoys raises the tier")
local tiny = Mutators.applyComposition({ { kind = "Grunt", tier = 1 }, { kind = "Grunt", tier = 1 }, { kind = "Grunt", tier = 1 }, { kind = "Grunt", tier = 1 } }, { Mutators.Defs.bigBoys }, 5, archetypeOf)
check(#tiny == 3, "bigBoys keeps at least 3, got " .. #tiny)
local champ = Mutators.applyComposition(wave12(), { Mutators.Defs.champion }, 30, archetypeOf)
local flagged, flaggedKind = 0, nil
for _, e in champ do
	if e.champion then
		flagged += 1
		flaggedKind = e.kind
	end
end
check(flagged == 1, "champion flags exactly one entry, got " .. flagged)
check(flaggedKind == "Brute", "champion is the first Brute, got " .. tostring(flaggedKind))
local treasure = Mutators.applyComposition(wave12(), { Mutators.Defs.treasure }, 30, archetypeOf)
check(#treasure == 13 and treasure[13].kind == "Treasure" and treasure[13].role == "treasure", "treasure appended")
local totems = Mutators.applyComposition(wave12(), { Mutators.Defs.totems }, 30, archetypeOf)
check(#totems == 14 and totems[13].kind == "Totem" and totems[14].role == "totem", "2 totems appended")
local lateTotems = Mutators.applyComposition(wave12(), { Mutators.Defs.totems }, 65, archetypeOf)
check(#lateTotems == 15, "3 totems from wave 60")

-- (8) Formations: every layout, counts 1-18, within bounds and apart.
local center = Vector3.new(10, 2, 100)
local function rolesFor(count, withBoss)
	local roles = {}
	for i = 1, count do
		if withBoss and i == count then
			table.insert(roles, "boss")
		elseif i % 4 == 0 then
			table.insert(roles, "heavy")
		elseif i % 3 == 0 then
			table.insert(roles, "ranged")
		else
			table.insert(roles, "melee")
		end
	end
	return roles
end
local function checkSpots(name, roles, label)
	local spots = Formations.spots(name, roles, center)
	check(#spots == #roles, label .. ": " .. #spots .. " spots for " .. #roles .. " roles")
	for i, p in spots do
		check(math.abs(p.X - center.X) <= 34 + 1e-6, string.format("%s: spot %d x out of bounds (%.1f)", label, i, p.X - center.X))
		check(p.Z - center.Z >= -8 - 1e-6 and p.Z - center.Z <= 32 + 1e-6, string.format("%s: spot %d z out of bounds (%.1f)", label, i, p.Z - center.Z))
		check(p.Y == center.Y, label .. ": spot y")
		for j = 1, i - 1 do
			check((spots[j] - p).Magnitude >= 4 - 1e-6, string.format("%s: spots %d and %d too close (%.2f)", label, j, i, (spots[j] - p).Magnitude))
		end
	end
	return spots
end
for _, name in Formations.Names do
	for count = 1, 18 do
		checkSpots(name, rolesFor(count, false), name .. " x" .. count)
		checkSpots(name, rolesFor(count, true), name .. " boss x" .. count)
	end
end
-- Totems and the treasure goblin with the plain layouts.
for _, name in { "line", "wedge", "shieldwall", "pincer" } do
	for count = 3, 12 do
		local roles = rolesFor(count, false)
		table.insert(roles, "treasure")
		table.insert(roles, "totem")
		table.insert(roles, "totem")
		table.insert(roles, "totem")
		checkSpots(name, roles, name .. " + extras x" .. count)
	end
end
-- The boss court puts the boss in the middle, scatter spreads 18 over 3 rows (nothing past z +32).
local court = Formations.spots("bossCourt", rolesFor(9, true), center)
check(math.abs(court[9].X - center.X) < 1e-6 and math.abs(court[9].Z - center.Z - 14) < 1e-6, "bossCourt boss in the middle")
local scatter = Formations.spots("line", rolesFor(18, false), center) -- 18 asks for scatter whatever the name
local maxZ = -math.huge
for _, p in scatter do
	maxZ = math.max(maxZ, p.Z - center.Z)
end
check(maxZ <= 30 + 1e-6, "18 enemies stay within three rows")
-- Pincer melee stand on the flanks.
local pincer = Formations.spots("pincer", { "melee", "melee", "ranged" }, center)
check(math.abs(pincer[1].X - center.X) >= 15 and math.abs(pincer[2].X - center.X) >= 15, "pincer melee on the flanks")

print(string.format("%d checks, %d failures", checks, failures))
if failures == 0 then
	print("ALL CHECKS PASSED")
end
