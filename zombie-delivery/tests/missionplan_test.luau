-- 6.15, the fixed missions (shared/MissionPlan.luau, Config.Missions.Fixed): a mission is always the same. The same id
-- gives the same dice, the same stops and the same enemies at the same spots; the counts follow the tier, the twists
-- and the chapter and stay within bounds; every mission of Missions.List gets a valid plan; HOLD OUT's waves add up
-- to their total. Run with tests/run_tests.py.
local Config = require("./Config")
local Map = require("./Map")
local Missions = require("./Missions")
local MissionPlan = require("./MissionPlan")

local Fixed = Config.Missions.Fixed

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function offenders(list: { string }): string
	if #list == 0 then
		return ""
	end
	local shown = table.concat(list, ", ", 1, math.min(#list, 8))
	return if #list > 8 then `{shown} … ({#list} in all)` else shown
end

-- A plan as text, spot for spot (two plans are the same when these are).
local function text(plan: MissionPlan.Plan): string
	local parts = { `{plan.id}|{plan.total}|{plan.label}|{plan.waves}` }
	for _, group in plan.groups do
		local spots = {}
		for _, spot in group.spots do
			table.insert(spots, string.format("%.3f,%.3f", spot.x, spot.z))
		end
		local block = group.roadblock
		table.insert(parts, `{group.id}:{group.anchor}:{group.stop}:{group.kind}:{group.count}:{group.wave}:{group.point}:{string.format("%.3f,%.3f", group.x, group.z)}:{group.place}:{if block then string.format("%.3f,%.3f,%d", block.x, block.z, block.lane) else "-"}:{table.concat(spots, ";")}`)
	end
	return table.concat(parts, "\n")
end

local function routeText(route: { Map.Address }?): string
	if not route then
		return "none"
	end
	local names = {}
	for _, address in route do
		table.insert(names, `{address.name}@{address.x},{address.z}`)
	end
	return table.concat(names, " > ")
end

-- A copy of a mission with other twists (and nothing else changed).
local function withTwists(def: Missions.MissionDef, twists: { string }): Missions.MissionDef
	local copy = table.clone(def)
	copy.twists = twists
	return copy
end

local function sumOf(plan: MissionPlan.Plan, anchor: string?, stop: number?): number
	local n = 0
	for _, group in plan.groups do
		if (anchor == nil or group.anchor == anchor) and (stop == nil or group.stop == stop) then
			n += group.count
		end
	end
	return n
end

local function planOf(def: Missions.MissionDef): MissionPlan.Plan?
	local stops = MissionPlan.stopsOf(def)
	return if stops then MissionPlan.make(def, stops) else nil
end

-- ── The dice ───────────────────────────────────────────────────────────────
do
	local seeds: { [number]: string } = {}
	local clash: { string } = {}
	local range: { string } = {}
	for _, def in Missions.List do
		local seed = MissionPlan.seed(def.id)
		if seeds[seed] then
			table.insert(clash, `{def.id} = {seeds[seed]}`)
		end
		seeds[seed] = def.id
		if seed < 1 or seed > 2147483646 or seed ~= math.floor(seed) then
			table.insert(range, def.id)
		end
		if MissionPlan.seed(def.id) ~= seed then
			table.insert(range, def.id .. " (not stable)")
		end
	end
	check("seed: every mission id its own stable seed", #clash == 0, offenders(clash))
	check("seed: a whole number 1 … 2147483646", #range == 0, offenders(range))
	check("seed: the same text, the same seed", MissionPlan.seed("dispatch_1") == MissionPlan.seed("dispatch_1") and MissionPlan.seed("dispatch_1") ~= MissionPlan.seed("dispatch_2"))
	local a, b = MissionPlan.dice(MissionPlan.seed("dispatch_1")), MissionPlan.dice(MissionPlan.seed("dispatch_2"))
	local x, y = a(), b()
	check("dice: two ids one letter apart roll apart at once", math.abs(x - y) > 0.01, `{x} {y}`)
	check("dice: in [0, 1)", x >= 0 and x < 1 and y >= 0 and y < 1)
end

-- ── The route: always the same stops ──────────────────────────────────────
do
	local missing, length, again, places, twice, band, rushes = {}, {}, {}, {}, {}, {}, {}
	local firsts: { [string]: boolean } = {}
	local distinct = 0
	local origin = MissionPlan.origin()
	for _, def in Missions.List do
		local route = MissionPlan.route(def)
		if not route then
			table.insert(missing, def.id)
			continue
		end
		if #route ~= def.pickups + def.drops then
			table.insert(length, `{def.id} {#route}`)
		end
		if routeText(MissionPlan.route(def)) ~= routeText(route) then
			table.insert(again, def.id)
		end
		-- the fixed places where the data says
		local pickupAt, dropAt = def.pickupAt, def.dropAt
		if pickupAt and def.pickups >= 1 then
			for n = 1, def.pickups do
				if not route[n].poi then
					table.insert(places, `{def.id} pick-up {n}`)
				end
			end
		end
		if dropAt and not route[#route].poi then
			table.insert(places, `{def.id} drop`)
		end
		local seen: { [Map.Address]: boolean } = {}
		for _, address in route do
			if seen[address] then
				table.insert(twice, def.id)
			end
			seen[address] = true
		end
		-- the first pick-up without a place: in the band from the depot (a rush: 100 … 350, else 120 … 450)
		if def.pickups >= 1 and not pickupAt then
			local d = Map.manhattan(origin.x, origin.z, route[1].x, route[1].z)
			local low, high = if def.timeLimit then 100 else 120, if def.timeLimit then 350 else 450
			if d < low or d > high then
				table.insert(band, `{def.id} {math.floor(d)}`)
			end
			if def.timeLimit then
				table.insert(rushes, def.id)
			end
		end
		local key = `{route[1].x},{route[1].z}`
		if not firsts[key] then
			firsts[key] = true
			distinct += 1
		end
	end
	check(`route: every mission of Missions.List has one ({#Missions.List})`, #missing == 0, offenders(missing))
	check("route: its pick-ups, then its drops", #length == 0, offenders(length))
	check("route: the same id, the same addresses (twice in a row)", #again == 0, offenders(again))
	check("route: pickupAt / dropAt are the named places", #places == 0, offenders(places))
	check("route: no address twice", #twice == 0, offenders(twice))
	check("route: a pick-up without a place in its band from the depot", #band == 0, offenders(band))
	check("route: a rush starts at a fixed address near the depot (not near you)", #rushes >= 2, #rushes)
	check("route: the missions do not all start at the same few places", distinct >= 20, distinct)
end

-- ── The plan: the same every time ─────────────────────────────────────────
do
	local differ, notSize = {}, {}
	for _, def in Missions.List do
		local stops = MissionPlan.stopsOf(def)
		if not stops then
			continue
		end
		local first = MissionPlan.make(def, stops)
		local second = MissionPlan.make(def, MissionPlan.stopsOf(def) or stops)
		if text(first) ~= text(second) then
			table.insert(differ, def.id)
		end
		local total, label = MissionPlan.size(def)
		if total ~= first.total or label ~= first.label then
			table.insert(notSize, `{def.id} {total}/{first.total} {label}/{first.label}`)
		end
	end
	check("plan: the same id and stops, the same enemies at the same spots", #differ == 0, offenders(differ))
	check("plan: MissionPlan.size says its total and word without the places", #notSize == 0, offenders(notSize))
	-- another mission's dice give other spots
	local a, b = Missions.find("dispatch_1"), Missions.find("clinic_1")
	if a and b then
		local stopsA = MissionPlan.stopsOf(a)
		if stopsA then
			local planA = MissionPlan.make(a, stopsA)
			local planB = MissionPlan.make(b, stopsA)
			check("plan: another mission on the same stops stands elsewhere", text(planA) ~= text(planB))
		end
	end
end

-- ── Every mission's plan is valid ─────────────────────────────────────────
do
	local bounds, counts, spots, kinds, places, labels, stopsHorde, anchors = {}, {}, {}, {}, {}, {}, {}, {}
	for _, def in Missions.List do
		local plan = planOf(def)
		if not plan then
			table.insert(bounds, def.id .. " (no plan)")
			continue
		end
		if plan.total < Fixed.Min or plan.total > Fixed.Max then
			table.insert(bounds, `{def.id} {plan.total}`)
		end
		local ranged = false
		for _, group in plan.groups do
			if group.count < 1 or #group.spots ~= group.count then
				table.insert(counts, `{def.id} #{group.id}`)
			end
			local zombie = Config.Zombies[group.kind]
			if not zombie then
				table.insert(kinds, `{def.id} {group.kind}`)
			elseif zombie.ranged then
				ranged = true
			end
			for _, spot in group.spots do
				if Map.isSafe(spot.x, spot.z) or Map.inWater(spot.x, spot.z) then
					table.insert(spots, `{def.id} #{group.id} {math.floor(spot.x)},{math.floor(spot.z)}`)
				end
			end
			if group.place == "" then
				table.insert(places, def.id)
			end
			if group.anchor == "route" and (not Map.onRoad(group.x, group.z) or Map.isSafe(group.x, group.z)) then
				table.insert(anchors, `{def.id} point {group.point}`)
			end
		end
		if (plan.label == "ENEMIES") ~= ranged then
			table.insert(labels, `{def.id} {plan.label}`)
		end
		-- every stop has its horde, the last drop the biggest
		local stops = def.pickups + def.drops
		local last = sumOf(plan, "drop", stops)
		for n = 1, stops do
			local here = sumOf(plan, if n <= def.pickups then "pickup" else "drop", n)
			if here < 1 or here > last then
				table.insert(stopsHorde, `{def.id} stop {n}: {here} (drop {last})`)
			end
		end
	end
	check(`plan: every mission {Fixed.Min} … {Fixed.Max} enemies`, #bounds == 0, offenders(bounds))
	check("plan: every group one spot an enemy", #counts == 0, offenders(counts))
	check("plan: only known kinds (Config.Zombies)", #kinds == 0, offenders(kinds))
	check("plan: no spot in the safe zone or the water", #spots == 0, offenders(spots))
	check("plan: every group says where", #places == 0, offenders(places))
	check("plan: a route point is on a road, out of the safe zone", #anchors == 0, offenders(anchors))
	check("plan: ENEMIES with bandits or gunners, else ZOMBIES", #labels == 0, offenders(labels))
	check("plan: a horde at every stop, the last drop's the biggest", #stopsHorde == 0, offenders(stopsHorde))
end

-- ── The counts: tier, chapter, twists ─────────────────────────────────────
do
	local first = Missions.find("dispatch_1")
	local firstTotal = if first then MissionPlan.size(first) else 0
	check("count: the ★ first mission (Paper Trail) is small (6 … 10)", firstTotal >= 6 and firstTotal <= 10, firstTotal)
	local easy = {}
	for _, def in Missions.List do
		if def.tier == 1 and #(def.twists or {}) <= 1 then
			local total = MissionPlan.size(def)
			if total > 14 then
				table.insert(easy, `{def.id} {total}`)
			end
		end
	end
	check("count: a ★ mission stays small (14 at most)", #easy == 0, offenders(easy))
	-- the chapters grow: the story's last chapter has more than its first, on average
	local sums: { [number]: { n: number, total: number } } = {}
	for _, def in Missions.List do
		if def.duo then
			continue
		end
		local chapter = MissionPlan.chapter(def.campaign)
		local entry = sums[chapter] or { n = 0, total = 0 }
		entry.n += 1
		entry.total += MissionPlan.size(def)
		sums[chapter] = entry
	end
	local one, ten = sums[1], sums[10]
	check("count: chapter 10 (Last Convoy) has more than chapter 1 (First Shift) on average", one ~= nil and ten ~= nil and ten.total / ten.n > one.total / one.n + 5, if one and ten then `{one.total / one.n} / {ten.total / ten.n}` else "missing")
	check("count: the chapters in order (First Shift 1, Last Convoy 10, DUO at its level)", MissionPlan.chapter("dispatch") == 1 and MissionPlan.chapter("exodus") == 10 and MissionPlan.chapter("duo") == MissionPlan.chapter("market"))
	-- the same mission in a later chapter has more (the growth)
	local probe = Missions.find("clinic_1")
	if probe then
		local later = table.clone(probe)
		later.campaign = "exodus"
		check("count: the same mission later in the story has more", MissionPlan.size(later) > MissionPlan.size(probe), `{MissionPlan.size(probe)} / {MissionPlan.size(later)}`)
		-- a higher tier has more
		local harder = table.clone(probe)
		harder.tier = 3
		check("count: a higher tier has more", MissionPlan.size(harder) > MissionPlan.size(probe), `{MissionPlan.size(probe)} / {MissionPlan.size(harder)}`)
	end
	-- the crew never changes the plan: it has no input for it (MissionPlan.make takes the mission and its stops)
	local coop = Missions.find("dispatch_9")
	if coop then
		local plain = table.clone(coop)
		plain.coop = nil
		check("count: co-op or not, the same enemies (a crew only makes them tougher)", MissionPlan.size(plain) == MissionPlan.size(coop))
	end
end

-- ── The twists as fixed groups ────────────────────────────────────────────
do
	local guardedBad, huntedBad, gunnerBad, defendBad, otherBad = {}, {}, {}, {}, {}
	for _, def in Missions.List do
		local twists: { string } = def.twists or {}
		local plan = planOf(def)
		if not plan then
			continue
		end
		local stops = def.pickups + def.drops
		local has = function(twist: string): boolean
			return table.find(twists, twist) ~= nil
		end
		-- guarded: a bigger horde at the drop than without the twist (the same mission otherwise)
		if has("guarded") then
			local without = {}
			for _, twist in twists do
				if twist ~= "guarded" then
					table.insert(without, twist)
				end
			end
			local plain = planOf(withTwists(def, without))
			if plain and sumOf(plan, "drop", stops) <= sumOf(plain, "drop", stops) and plan.total < Fixed.Max then
				table.insert(guardedBad, `{def.id} {sumOf(plan, "drop", stops)} / {sumOf(plain, "drop", stops)}`)
			end
			if plain and sumOf(plan, nil, nil) <= sumOf(plain, nil, nil) and plan.total < Fixed.Max then
				table.insert(guardedBad, `{def.id} total`) -- (both at Max: the cap)
			end
		end
		-- hunted: roadblocks of bandits on the route (a bandit car with each)
		local roadblocks, bandits = 0, 0
		for _, group in plan.groups do
			if group.roadblock then
				roadblocks += 1
				bandits += if group.kind == "bandit" then group.count else 0
			end
		end
		if has("hunted") ~= (roadblocks > 0) or (has("hunted") and bandits < 1) then
			table.insert(huntedBad, `{def.id} {roadblocks} roadblocks, {bandits} bandits`)
		end
		-- gunner: gunners posted on the route (not at a roadblock)
		local posted = 0
		for _, group in plan.groups do
			if group.anchor == "route" and not group.roadblock and group.kind == "gunner" then
				posted += group.count
			end
		end
		if has("gunner") ~= (posted > 0) then
			table.insert(gunnerBad, `{def.id} {posted}`)
		end
		-- defend: the waves at the last drop, their number fixed, each wave's groups add up to the defend total
		local defend = sumOf(plan, "defend", nil)
		if has("defend") then
			local byWave: { [number]: number } = {}
			local sum = 0
			for _, group in plan.groups do
				if group.anchor == "defend" then
					local wave = group.wave or 0
					byWave[wave] = (byWave[wave] or 0) + group.count
					sum += group.count
					if group.stop ~= stops then
						table.insert(defendBad, `{def.id} not at the last drop`)
					end
				end
			end
			if plan.waves ~= #Fixed.DefendSplit or sum ~= defend or defend < plan.waves then
				table.insert(defendBad, `{def.id} {plan.waves} waves, {sum} / {defend}`)
			end
			local total = 0
			for wave = 1, plan.waves do
				local here = byWave[wave] or 0
				total += here
				if here < 1 or (wave > 1 and here < (byWave[wave - 1] or 0)) then
					table.insert(defendBad, `{def.id} wave {wave}: {here}`)
				end
			end
			if total ~= defend then
				table.insert(defendBad, `{def.id} the waves add up to {total}, not {defend}`)
			end
		elseif plan.waves ~= 0 or defend ~= 0 then
			table.insert(defendBad, `{def.id} waves without HOLD OUT`)
		end
		-- the other twists bring no enemies of their own: the plan is the plain one
		local own = false
		for _, twist in twists do
			own = own or twist == "guarded" or twist == "hunted" or twist == "gunner" or twist == "defend"
		end
		if not own and #twists > 0 then
			local plain = planOf(withTwists(def, {}))
			if plain and text(plain) ~= text(plan) then
				table.insert(otherBad, def.id)
			end
		end
	end
	check("twist guarded (HOT ZONE): a bigger horde at the drop and more in all", #guardedBad == 0, offenders(guardedBad))
	check("twist hunted (HUNTED): fixed bandit roadblocks on the route, only then", #huntedBad == 0, offenders(huntedBad))
	check("twist gunner (SHOTGUN SEAT): gunners posted on the route, only then", #gunnerBad == 0, offenders(gunnerBad))
	check(`twist defend (HOLD OUT): {#Fixed.DefendSplit} waves at the last drop, growing, adding up to their total`, #defendBad == 0, offenders(defendBad))
	check("twists quiet / spotless / lift / pair / switches / night: no enemies of their own", #otherBad == 0, offenders(otherBad))
	-- a hunted mission with banditBoost has more roadblocks than its tier's
	local boosted = Missions.find("underworld_10")
	if boosted and (boosted.banditBoost or 1) > 1 then
		local plan = planOf(boosted)
		local points: { [number]: boolean } = {}
		local n = 0
		for _, group in (if plan then plan.groups else {}) do
			if group.roadblock and group.point and not points[group.point] then
				points[group.point] = true
				n += 1
			end
		end
		check("twist hunted: banditBoost brings more roadblocks", n > Fixed.Roadblocks[boosted.tier], n)
	end
end

-- ── The tuning ─────────────────────────────────────────────────────────────
do
	check("tuning: the alive cap holds a stop's horde of a ★ mission", Fixed.MaxAlive >= 8 and Fixed.MaxAlive <= Fixed.Max)
	check("tuning: a group comes before the despawn distance takes it again", Fixed.SpawnRange + Fixed.RingMax < Config.Horde.DespawnDistance)
	check("tuning: the tier tables cover every tier", #Fixed.Stops == #Config.Jobs.Tiers and #Fixed.Kinds == #Config.Jobs.Tiers and #Fixed.Defend == #Config.Jobs.Tiers and #Fixed.Roadblocks == #Config.Jobs.Tiers and #Fixed.RoadblockSize == #Config.Jobs.Tiers and #Fixed.Gunners == #Config.Jobs.Tiers)
	local known = true
	for _, kinds in Fixed.Kinds do
		for kind in kinds do
			known = known and Config.Zombies[kind] ~= nil and Config.Zombies[kind].ranged ~= true
		end
	end
	check("tuning: the stops' kinds are zombies (the bandits come with HUNTED and SHOTGUN SEAT)", known)
	check("tuning: a clock allowance for every enemy", Fixed.TimePerEnemy > 0 and Fixed.TimePerEnemy * Fixed.Max <= 240)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
