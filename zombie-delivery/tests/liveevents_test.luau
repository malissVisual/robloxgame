-- Logic test of 6.15's live events (shared/LiveEvents.luau, Config.LiveEvents): the tuning, the clock (night and day
-- left, which event may start when), the deck and the gaps, what an event changes (the pay next to the night bonus in
-- Economy.payout, never a mission's; the waves, the roamers, the zombies' speed and its cap; rush hour's offers through
-- JobRules.roles and its board refresh), the words (the result's, the board's, the phone's, the banner's, the toasts),
-- the rewards (the supply drop's, the horde's shares), the horde's gates and spawns (on the streets, outside the safe
-- zone, never in it) and the supply drop's spots (on a street, outside the zone, in town) and its drop-off at the depot.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local JobRules = require("./JobRules")
local Map = require("./Map")
local LiveEvents = require("./LiveEvents")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.LiveEvents
local D = Config.DayNight
local HALF = Config.City.SafeHalf

-- A stream of numbers in [0, 1) (Park–Miller), the same every run.
local function stream(seed: number): () -> number
	local state = seed
	for _ = 1, 6 do -- (a small seed's first numbers are tiny: warm it up)
		state = state * 48271 % 2147483647
	end
	return function(): number
		state = state * 48271 % 2147483647
		return (state - 1) / 2147483646
	end
end

-- ── The tuning ────────────────────────────────────────────────────────────
do
	local bad = {}
	for _, id in LiveEvents.Ids do
		local def = LiveEvents.def(id)
		if not def or def.name == "" or def.icon == "" or def.hint == "" or def.minutes <= 0 or #def.color ~= 3 then
			table.insert(bad, id)
		end
	end
	check("the four events (the owner's pick), each with a name, icon, hint, length and colour", #LiveEvents.Ids == 4 and #bad == 0, table.concat(bad, ", "))
	local order = table.concat(T.Order, ",")
	check("the deck's order holds the four", #T.Order == 4 and string.find(order, "bloodmoon") and string.find(order, "rush") and string.find(order, "supply") and string.find(order, "horde") ~= nil, order)
	check("one every 20 – 30 minutes (the owner's pick), the first sooner", T.Every[1] == 20 and T.Every[2] == 30 and T.First[1] <= T.First[2] and T.First[2] <= T.Every[1], `{T.First[1]}-{T.First[2]} / {T.Every[1]}-{T.Every[2]}`)
	check("the Blood Moon and rush hour last 5 minutes", LiveEvents.seconds("bloodmoon") == 300 and LiveEvents.seconds("rush") == 300, LiveEvents.seconds("bloodmoon"))
	check("an unknown event: no length, no def", LiveEvents.seconds("party") == 0 and LiveEvents.def("party") == nil and LiveEvents.def(nil) == nil)
	check("the Blood Moon pays ×2, rush hour ×1.5", T.BloodMoon.Pay == 2 and T.Rush.Pay == 1.5)
	check("the night is long enough for a whole Blood Moon", (24 - D.NightFrom + D.NightTo) * D.DayLength / 24 >= T.BloodMoon.MinNightLeft and T.BloodMoon.MinNightLeft >= LiveEvents.seconds("bloodmoon"))
	check("the day is long enough for a whole rush hour", (D.NightFrom - D.NightTo) * D.DayLength / 24 >= T.Rush.MinDayLeft and T.Rush.MinDayLeft >= LiveEvents.seconds("rush"))
	-- A card waiting for its night (or its day) is never shuffled away before that comes round: the window it needs
	-- comes back once a day's cycle.
	local nightWindow = (24 - D.NightFrom + D.NightTo) * D.DayLength / 24 - T.BloodMoon.MinNightLeft
	local dayWindow = (D.NightFrom - D.NightTo) * D.DayLength / 24 - T.Rush.MinDayLeft
	check("MaxWait outlasts the wait for the Blood Moon's and rush hour's moment", T.MaxWait >= D.DayLength - math.min(nightWindow, dayWindow) + T.Retry, T.MaxWait)
	check("headroom under the server's zombie cap for the other players' waves", T.Headroom >= Config.Horde.Roam.reserve and T.Headroom < Config.Horde.MaxTotal - 20, T.Headroom)
	check("the horde fits under the cap with its headroom", T.Horde.Count <= Config.Horde.MaxTotal - T.Headroom, T.Horde.Count)
end

-- ── The clock ─────────────────────────────────────────────────────────────
do
	local perHour = D.DayLength / 24
	check("night left at its start: the whole night", math.abs(LiveEvents.nightLeft(D.NightFrom) - (24 - D.NightFrom + D.NightTo) * perHour) < 1e-6)
	check("night left at midnight", math.abs(LiveEvents.nightLeft(0) - D.NightTo * perHour) < 1e-6)
	check("night left by day: 0", LiveEvents.nightLeft(12) == 0 and LiveEvents.nightLeft(D.NightTo) == 0)
	check("day left at noon", math.abs(LiveEvents.dayLeft(12) - (D.NightFrom - 12) * perHour) < 1e-6)
	check("day left at night: 0", LiveEvents.dayLeft(23) == 0 and LiveEvents.dayLeft(3) == 0 and LiveEvents.dayLeft(D.NightFrom) == 0)
	check("an hour past 24 wraps", LiveEvents.nightLeft(24) == LiveEvents.nightLeft(0) and LiveEvents.dayLeft(36) == LiveEvents.dayLeft(12))
	-- Which may start when.
	check("the Blood Moon only at night", LiveEvents.canStart("bloodmoon", D.NightFrom + 0.1, 3) and not LiveEvents.canStart("bloodmoon", 12, 3))
	local lateNight = D.NightTo - (T.BloodMoon.MinNightLeft - 10) / perHour
	check("… with enough of it left (not just before dawn)", not LiveEvents.canStart("bloodmoon", lateNight, 3), lateNight)
	check("rush hour only by day", LiveEvents.canStart("rush", 9, 1) and not LiveEvents.canStart("rush", 22, 1) and not LiveEvents.canStart("rush", 2, 1))
	check("… not right before dusk", not LiveEvents.canStart("rush", D.NightFrom - (T.Rush.MinDayLeft - 5) / perHour, 1))
	check("the supply drop and the horde any time", LiveEvents.canStart("supply", 3, 1) and LiveEvents.canStart("supply", 13, 1) and LiveEvents.canStart("horde", 23, 2) and LiveEvents.canStart("horde", 10, 2))
	local ok, why = LiveEvents.canStart("horde", 10, 0)
	check("never in an empty server", not ok and why ~= nil and not LiveEvents.canStart("supply", 10, 0) and not LiveEvents.canStart("rush", 10, 0))
	check("an unknown event never starts", not LiveEvents.canStart("party", 10, 4))
end

-- ── The deck and the gaps ─────────────────────────────────────────────────
do
	local bad = {}
	local firsts: { [string]: number } = {}
	for seed = 1, 400 do
		local deck = LiveEvents.deck(stream(seed), "horde")
		local seen: { [string]: boolean } = {}
		for _, id in deck do
			seen[id] = true
		end
		if #deck ~= 4 or not (seen.bloodmoon and seen.rush and seen.supply and seen.horde) then
			table.insert(bad, `seed {seed}: {table.concat(deck, ",")}`)
		end
		if deck[1] == "horde" then
			table.insert(bad, `seed {seed}: the last one first`)
		end
		firsts[deck[1]] = (firsts[deck[1]] or 0) + 1
	end
	check("a deck: the four events once each, the last one played never first", #bad == 0, table.concat(bad, "; "))
	check("every other event comes first now and then", (firsts.bloodmoon or 0) > 60 and (firsts.rush or 0) > 60 and (firsts.supply or 0) > 60, `{firsts.bloodmoon} {firsts.rush} {firsts.supply}`)
	local deck = { "bloodmoon", "rush", "supply", "horde" }
	local id, index = LiveEvents.pick(deck, function(name: string): boolean
		return LiveEvents.canStart(name, 8, 2) -- the morning: no Blood Moon
	end)
	check("by day the Blood Moon waits in the deck, the next one goes", id == "rush" and index == 2, id)
	local late = LiveEvents.pick(deck, function(name: string): boolean
		return LiveEvents.canStart(name, D.NightFrom - 1, 2) -- an hour before dusk: no rush hour either
	end)
	check("… late in the day rush hour waits too", late == "supply", late)
	local none = LiveEvents.pick({ "bloodmoon" }, function(name: string): boolean
		return LiveEvents.canStart(name, 12, 2)
	end)
	check("nothing can start: nil", none == nil)
	check("the gaps: Every minutes from start to start", LiveEvents.gap(0, false) == T.Every[1] * 60 and LiveEvents.gap(1, false) == T.Every[2] * 60 and LiveEvents.gap(0.5, false) == (T.Every[1] + T.Every[2]) * 30)
	check("the first one: First minutes", LiveEvents.gap(0, true) == T.First[1] * 60 and LiveEvents.gap(2, true) == T.First[2] * 60)
end

-- ── What an event changes ─────────────────────────────────────────────────
do
	check("the pay: ×2 in a Blood Moon, ×1.5 in rush hour, nothing in the others", LiveEvents.payOf("bloodmoon", false) == 2 and LiveEvents.payOf("rush", false) == 1.5 and LiveEvents.payOf("supply", false) == 1 and LiveEvents.payOf("horde", false) == 1 and LiveEvents.payOf(nil, false) == 1)
	check("a mission: never", LiveEvents.payOf("bloodmoon", true) == 1 and LiveEvents.payOf("rush", true) == 1 and LiveEvents.wavesOf("bloodmoon", true) == 1)
	check("the Blood Moon's waves and roamers", LiveEvents.wavesOf("bloodmoon", false) == T.BloodMoon.Waves and T.BloodMoon.Waves > 1 and LiveEvents.roamOf("bloodmoon") == T.BloodMoon.Roam and LiveEvents.roamOf("rush") == 1 and LiveEvents.wavesOf("rush", false) == 1)
	local walker, runner, brute = Config.Zombies.walker.speed, Config.Zombies.runner.speed, Config.Zombies.brute.speed
	check("a Blood Moon's zombie is faster", LiveEvents.speedOf("bloodmoon", walker) > walker and LiveEvents.speedOf("bloodmoon", brute) > brute)
	check("… never over MaxSpeed (a runner stays catchable at a sprint's pace)", LiveEvents.speedOf("bloodmoon", runner) <= T.BloodMoon.MaxSpeed and LiveEvents.speedOf("bloodmoon", runner) >= runner, LiveEvents.speedOf("bloodmoon", runner))
	check("… and never slower than it was", LiveEvents.speedOf("bloodmoon", 40) == 40 and LiveEvents.speedOf("rush", walker) == walker and LiveEvents.speedOf(nil, walker) == walker)
	-- The pay next to the night bonus (Economy.payout): on the same subtotal, added, not multiplied.
	local plain = Economy.payout(200, 1, 60, 100, 4)
	local night = Economy.payout(200, 1, 60, 100, 4, D.NightPay)
	local blood = Economy.payout(200, 1, 60, 100, 4, D.NightPay, LiveEvents.payOf("bloodmoon", false))
	local subtotal = plain.conditionPay + plain.fastBonus + plain.killBonus
	check("no event: no event bonus (the old calls)", plain.eventBonus == 0 and night.eventBonus == 0 and night.total == subtotal + night.nightBonus)
	check("the Blood Moon's bonus: the subtotal × (2 − 1)", blood.eventBonus == subtotal and blood.nightBonus == night.nightBonus, `{blood.eventBonus} / {subtotal}`)
	check("… added next to the night's, neither multiplies the other", blood.total == subtotal + blood.nightBonus + blood.eventBonus and blood.total == math.floor(subtotal * (1 + (D.NightPay - 1) + 1) + 0.5), blood.total)
	local rush = Economy.payout(300, 0.8, 10, 100, 0, 1, LiveEvents.payOf("rush", false))
	local rushSub = rush.conditionPay + rush.fastBonus + rush.killBonus
	check("rush hour's bonus: half the subtotal", rush.eventBonus == math.floor(rushSub * 0.5 + 0.5) and rush.total == rushSub + rush.eventBonus, rush.eventBonus)
	local mission = Economy.payout(300, 1, 60, 100, 2, 1, LiveEvents.payOf("bloodmoon", true))
	check("a mission in a Blood Moon: no bonus", mission.eventBonus == 0)
	-- Rush hour's board.
	local base = JobRules.roles(stream(7))
	local more = JobRules.roles(stream(7), LiveEvents.extraOffers("rush"))
	check("rush hour: one more ordinary offer a danger level", #more == #base + T.Rush.ExtraOffers and #base == Config.Jobs.Choice.Offers, `{#base} → {#more}`)
	local seen: { [string]: boolean } = {}
	for _, role in more do
		seen[role] = true
	end
	check("… every trade-off once, SHORT & SAFE first", more[1] == "short" and seen.long and seen.risky and seen.bulk ~= nil, table.concat(more, ","))
	check("no rush hour: as before", LiveEvents.extraOffers("bloodmoon") == 0 and LiveEvents.extraOffers(nil) == 0 and #JobRules.roles(stream(3), 0) == #base)
	check("never more roles than there are", #JobRules.roles(stream(5), 9) == 4)
	check("rush hour: new offers sooner", LiveEvents.refreshOf("rush", Config.Jobs.RefreshSeconds) == math.min(Config.Jobs.RefreshSeconds, T.Rush.Refresh) and LiveEvents.refreshOf("horde", 120) == 120 and LiveEvents.refreshOf("rush", 30) == 30)
end

-- ── The words ─────────────────────────────────────────────────────────────
do
	check("the clock", LiveEvents.clock(192) == "3:12" and LiveEvents.clock(0) == "0:00" and LiveEvents.clock(-5) == "0:00" and LiveEvents.clock(59.2) == "1:00" and LiveEvents.clock(600) == "10:00")
	check("the money", LiveEvents.money(1234567) == "$1,234,567" and LiveEvents.money(85) == "$85" and LiveEvents.money(-3) == "$0")
	check("the multipliers", LiveEvents.times(2) == "×2" and LiveEvents.times(1.5) == "×1.5" and LiveEvents.times(1.25) == "×1.25", LiveEvents.times(1.5))
	check("the result's line", LiveEvents.payLine("bloodmoon") == "🌕 BLOOD MOON ×2" and LiveEvents.payLine("rush") == "🕑 RUSH HOUR ×1.5" and LiveEvents.payLine(nil) == "Live event bonus", LiveEvents.payLine("rush"))
	check("the board's strip (the owner's words)", LiveEvents.boardLine("rush", 192) == "🕑 RUSH HOUR · ×1.5 pay · 3:12" and LiveEvents.boardLine("bloodmoon", 60) == "🌕 BLOOD MOON · ×2 pay · 1:00", LiveEvents.boardLine("rush", 192))
	check("… none for an event that does not pay", LiveEvents.boardLine("supply", 60) == nil and LiveEvents.boardLine("horde", 60) == nil and LiveEvents.boardLine(nil, 60) == nil)
	check("… its words before the clock", LiveEvents.boardPrefix("rush") == "🕑 RUSH HOUR · ×1.5 pay · " and LiveEvents.boardPrefix("supply") == nil)
	check("the phone's WORK line", LiveEvents.workLine("bloodmoon") == "🌕 BLOOD MOON · jobs pay ×2" and LiveEvents.workLine("supply") == nil, LiveEvents.workLine("bloodmoon"))
	local moon = LiveEvents.banner({ id = "bloodmoon", left = 200 })
	check("the banner: title, hint, clock, no count", moon ~= nil and moon.title == "🌕 BLOOD MOON" and moon.hint ~= "" and moon.clock == "3:20" and moon.count == nil and moon.progress == nil)
	local horde = LiveEvents.banner({ id = "horde", left = 90, done = 34, total = 60, side = "east" })
	check("the horde's banner: HORDE 34/60 and its bar", horde ~= nil and horde.count == "HORDE 34/60" and math.abs((horde.progress or 0) - 34 / 60) < 1e-9 and string.find(horde.hint, "east") ~= nil, horde and horde.count)
	local over = LiveEvents.banner({ id = "horde", left = 5, done = 70, total = 60 })
	check("… the bar never past full", over ~= nil and over.progress == 1 and over.count == "HORDE 60/60")
	local carried = LiveEvents.banner({ id = "supply", left = 100, phase = "carried", carrier = "Sam" })
	local falling = LiveEvents.banner({ id = "supply", left = 300, phase = "falling" })
	check("the supply drop's banner says where the crate is", carried ~= nil and string.find(carried.hint, "Sam") ~= nil and falling ~= nil and falling.hint ~= carried.hint)
	local short = LiveEvents.banner({ id = "bloodmoon", left = 200 }, true)
	local shortCarry = LiveEvents.banner({ id = "supply", left = 100, phase = "carried", carrier = "Sam" }, true)
	check("the narrow banner: the hint's first part only", short ~= nil and short.hint == "Jobs pay ×2" and shortCarry ~= nil and shortCarry.hint == "Sam has it", short and short.hint)
	local bad = {}
	for _, id in LiveEvents.Ids do
		for _, phase in { "falling", "ground", "carried" } do
			local words = LiveEvents.banner({ id = id, left = 60, phase = phase, carrier = "Alexandra", side = "south", done = 3, total = 40 }, true)
			if not words or #words.hint > 26 then
				table.insert(bad, `{id} {phase}: {words and words.hint}`)
			end
		end
	end
	check("… short enough for the narrow banner", #bad == 0, table.concat(bad, "; "))
	check("no event: no banner", LiveEvents.banner({ id = nil, left = 0 }) == nil and LiveEvents.banner({ id = "party", left = 10 }) == nil)
	local bad = {}
	for _, id in LiveEvents.Ids do
		local text = LiveEvents.startText(id, "east")
		if #text < 20 or #text > 160 then
			table.insert(bad, `{id}: {text}`)
		end
		for _, why in { "time", "admin", "dawn", "dusk", "delivered", "beaten", "nobody" } do
			if LiveEvents.endText(id, why) == "" then
				table.insert(bad, `{id} {why}`)
			end
		end
	end
	check("the toasts: short enough for a toast", #bad == 0, table.concat(bad, "; "))
end

-- ── The rewards ───────────────────────────────────────────────────────────
do
	check("the level scale", LiveEvents.levelScale(1) == 1 and LiveEvents.levelScale(11) == 1 + 10 * T.LevelScale and LiveEvents.levelScale(0) == 1)
	local money, xp = LiveEvents.supplyReward(1)
	local money7, xp7 = LiveEvents.supplyReward(7)
	check("the supply drop's reward, growing with the level, in $5 steps", money == T.Supply.Money and xp == T.Supply.Xp and money7 > money and xp7 > xp and money7 % 5 == 0, `{money}/{xp} → {money7}/{xp7}`)
	local level = function(_: string): number
		return 1
	end
	local beaten = LiveEvents.hordeShares({ a = 30, b = 10, c = 0 }, 40, 40, true, level)
	check("the horde beaten: the whole pool, split by kills", beaten.a.money == T.Horde.Money * 3 / 4 and beaten.b.money == T.Horde.Money / 4 and beaten.c == nil, `{beaten.a.money} {beaten.b.money}`)
	check("… the XP too", beaten.a.xp == math.floor(T.Horde.Xp * 0.75 + 0.5) and beaten.b.xp == math.floor(T.Horde.Xp * 0.25 + 0.5))
	local half = LiveEvents.hordeShares({ a = 20 }, 20, 40, false, level)
	check("its time ran out: the share of the horde that fell", half.a.money == T.Horde.Money / 2, half.a.money)
	local one = LiveEvents.hordeShares({ a = 1, b = 199 }, 200, 400, false, level)
	check("one kill still pays a little", one.a.money >= 5 and one.a.xp >= 1)
	check("nobody killed any: nothing", next(LiveEvents.hordeShares({}, 0, 40, false, level)) == nil and next(LiveEvents.hordeShares({ a = 0 }, 0, 40, true, level)) == nil)
	local scaled = LiveEvents.hordeShares({ a = 10, b = 10 }, 20, 20, true, function(key: string): number
		return if key == "a" then 11 else 1
	end)
	check("each share × its own level scale", scaled.a.money > scaled.b.money and scaled.b.money == T.Horde.Money / 2, `{scaled.a.money} {scaled.b.money}`)
end

-- ── The horde's way in ────────────────────────────────────────────────────
do
	local bad = {}
	local spots = 0
	for _, side in LiveEvents.Sides do
		local gates = LiveEvents.gates(side)
		if #gates ~= T.Horde.Gates then
			table.insert(bad, `{side}: {#gates} gates`)
		end
		for _, gate in gates do
			if Map.isSafe(gate.x, gate.z) then
				table.insert(bad, `{side}: a gate in the safe zone ({gate.x}, {gate.z})`)
			end
			if not Map.onRoad(gate.x, gate.z) then
				table.insert(bad, `{side}: a gate off the road ({gate.x}, {gate.z})`)
			end
			if math.max(math.abs(gate.x), math.abs(gate.z)) > HALF + T.Horde.Stop + 0.5 then
				table.insert(bad, `{side}: a gate far from the edge`)
			end
			-- one step further in is the safe zone: the gate is right at its edge
			if not Map.isSafe(gate.x - gate.dx * (T.Horde.Stop + 2), gate.z - gate.dz * (T.Horde.Stop + 2)) then
				table.insert(bad, `{side}: the gate does not face the zone`)
			end
			for _, out in { 0, 0.5, 1 } do
				for _, lateral in { 0, 0.5, 1 } do
					local x, z = LiveEvents.hordeSpot(gate, out, lateral)
					spots += 1
					if Map.isSafe(x, z) or not Map.onRoad(x, z) or Map.inWater(x, z) then
						table.insert(bad, `{side}: a spawn at ({math.floor(x)}, {math.floor(z)})`)
					end
					-- the way to the gate is the street itself: every point on it is road, none in the zone
					for k = 1, 9 do
						local px, pz = x + (gate.x - x) * k / 10, z + (gate.z - z) * k / 10
						if Map.isSafe(px, pz) or not Map.onRoad(px, pz) then
							table.insert(bad, `{side}: the way in leaves the street at ({math.floor(px)}, {math.floor(pz)})`)
							break
						end
					end
				end
			end
		end
	end
	check("every side: its gates at the zone's edge, the spawns and the way in on the street, never in the zone", #bad == 0 and spots >= 4 * T.Horde.Gates * 9, table.concat(bad, "; "))
	check("an unknown side: no gates", #LiveEvents.gates("up") == 0)
	local bursts = LiveEvents.bursts(42, 4)
	check("the bursts add up to the count", bursts[1] == 11 and bursts[2] == 11 and bursts[3] == 10 and bursts[4] == 10 and #LiveEvents.bursts(T.Horde.Count, T.Horde.Bursts) == T.Horde.Bursts)
	local sum = 0
	for _, n in LiveEvents.bursts(T.Horde.Count, T.Horde.Bursts) do
		sum += n
	end
	check("… the horde's", sum == T.Horde.Count)
end

-- ── The supply drop ───────────────────────────────────────────────────────
do
	local bad = {}
	local good = 0
	local sides: { [string]: number } = {}
	local r = stream(99)
	for _ = 1, 600 do
		local x, z = LiveEvents.supplySpot(r(), r(), r())
		if x and z then
			good += 1
			if Map.isSafe(x, z) or math.max(math.abs(x), math.abs(z)) < HALF + T.Supply.Margin then
				table.insert(bad, `in or by the safe zone ({math.floor(x)}, {math.floor(z)})`)
			elseif not Map.onRoad(x, z) then
				table.insert(bad, `off the road ({math.floor(x)}, {math.floor(z)})`)
			elseif Map.inWater(x, z) then
				table.insert(bad, `in the water ({math.floor(x)}, {math.floor(z)})`)
			end
			local side = if math.abs(x) >= math.abs(z) then (if x > 0 then "east" else "west") else (if z > 0 then "south" else "north")
			sides[side] = (sides[side] or 0) + 1
		end
	end
	check("the supply drop's spots: on a street, outside the safe zone, never in the water", #bad == 0, table.concat(bad, "; "))
	check("most rolls give a spot (the server tries a few)", good >= 400, good)
	check("all round the town", (sides.north or 0) > 40 and (sides.east or 0) > 40 and (sides.south or 0) > 40 and (sides.west or 0) > 40, `{sides.north} {sides.east} {sides.south} {sides.west}`)
	local dx, dz = LiveEvents.dropOff()
	check("the drop-off at the depot, in the safe zone, on its block", Map.isSafe(dx, dz) and math.abs(dx - Map.Depot.x) <= Map.BlockSize / 2 and math.abs(dz - Map.Depot.z) <= Map.BlockSize / 2, `{dx}, {dz}`)
	check("delivered within DeliverRadius", LiveEvents.delivered(dx, dz) and LiveEvents.delivered(dx + T.Supply.DeliverRadius - 0.5, dz) and not LiveEvents.delivered(dx + T.Supply.DeliverRadius + 1, dz) and not LiveEvents.delivered(0, 0))
	-- The drop-off is clear of the yard's things (server/World.luau buildDepot, Config.GearStall, the scooter rack).
	local off = T.Supply.DropOff
	local function clear(x: number, z: number, r: number): boolean
		return (off[1] - x) ^ 2 + (off[2] - z) ^ 2 > (r + T.Supply.DeliverRadius * 0.5) ^ 2
	end
	local rack = Config.Rental.SpawnRack
	check("the drop-off clear of the spawn, the stall, the rack, the JOBS spot and the terminal", clear(0, 26, 6) and clear(Config.GearStall.X, Config.GearStall.Z, 14) and clear(rack.x, rack.z, 12) and clear(-18, -25, 10) and clear(18, -25, 6), `{off[1]}, {off[2]}`)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
