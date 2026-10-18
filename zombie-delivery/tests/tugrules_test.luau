-- 10.6 SNATCHING: shared/TugRules.luau, the rules of a tug of war over a piece in a round (Config.Rounds.Tug): the mark
-- starts on the carrier's side, each press pulls (the carrier's further), only Rate presses a second are heard, it ends at
-- either end or at its time (a tie the carrier's); who may be snatched from (a piece carried alone, not just picked up,
-- not by their own van or the house's door, not again at once) and who may try (empty hands, not again at once, near).
-- The server's side (the prompts, the tugs, the stun): tests/rounds_runtime_test.luau. Run with tests/run_tests.py.
local Config = require("./Config")
local TugRules = require("./TugRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Rounds.Tug

-- Both press at `carrier` and `snatcher` presses a second for the whole tug → the winner.
local function play(carrier: number, snatcher: number): (string?, number)
	local tug = TugRules.new(100, T)
	local t = 100
	local nextC, nextS = 100 + (if carrier > 0 then 1 / carrier else math.huge), 100 + (if snatcher > 0 then 1 / snatcher else math.huge)
	while true do
		t = math.min(nextC, nextS, tug.endsAt)
		if t >= tug.endsAt then
			break
		end
		if t == nextS then
			TugRules.pull(tug, "snatcher", t, T)
			nextS += 1 / snatcher
		else
			TugRules.pull(tug, "carrier", t, T)
			nextC += 1 / carrier
		end
		local won = TugRules.result(tug, t)
		if won then
			return won, t - 100
		end
	end
	return TugRules.result(tug, tug.endsAt), T.Seconds
end

do
	local tug = TugRules.new(100, T)
	check("a new tug: the mark on the carrier's side (Start), over in Seconds, nobody's yet", tug.p == T.Start and T.Start < 0 and tug.endsAt == 100 + T.Seconds
		and TugRules.result(tug, 100.5) == nil)
	check("a snatcher's press pulls Pull toward them", TugRules.pull(tug, "snatcher", 100.2, T) and math.abs(tug.p - (T.Start + T.Pull)) < 1e-9)
	check("NEG. …again at once: not heard (Rate a second at most)", not TugRules.pull(tug, "snatcher", 100.2 + 0.5 / T.Rate, T) and tug.pulls.snatcher == 1)
	check("a carrier's press pulls Boost times as far the other way", TugRules.pull(tug, "carrier", 100.25, T)
		and math.abs(tug.p - (T.Start + T.Pull - T.Pull * T.Boost)) < 1e-9 and T.Boost > 1)
	check("NEG. …a stranger's side, a press after its time: not heard", not TugRules.pull(tug, "crowd", 100.4, T) and not TugRules.pull(tug, "snatcher", 100 + T.Seconds, T))
	check("its time over on the carrier's side: the carrier's", TugRules.result(tug, 100 + T.Seconds) == "carrier")
	local tie = TugRules.new(0, T)
	tie.p = 0
	check("…a tie at its end: the carrier's (the carrier is favoured)", TugRules.result(tie, T.Seconds) == "carrier")
	tie.p = 0.01
	check("…past the middle at its end: the snatcher's", TugRules.result(tie, T.Seconds) == "snatcher")
	tie.p = 1
	check("…at an end: over at once (no more presses heard)", TugRules.result(tie, 1) == "snatcher" and not TugRules.pull(tie, "carrier", 1, T))
end

do
	local who, took = play(0, T.Rate)
	check(`a carrier who does nothing: the snatcher takes it (in {string.format("%.1f", took)} s, under Seconds)`, who == "snatcher" and took < T.Seconds, who)
	who = play(T.Rate, T.Rate)
	check("both pressing as fast as is heard: the carrier keeps it", who == "carrier", who)
	who = play(T.Rate * 0.8, T.Rate)
	check("…the carrier a fifth slower: still the carrier's (not too easily)", who == "carrier", who)
	who = play(T.Rate * 0.5, T.Rate)
	check("…the carrier at half the pace: the snatcher's", who == "snatcher", who)
	who = play(T.Rate, T.Rate * 3)
	check("NEG. a snatcher mashing three times faster than is heard gains nothing: the carrier's", who == "carrier", who)
end

do
	local c: TugRules.Carrier = { carrying = true, alone = true, since = 0, now = 10, van = 50, door = 50, busy = false, targetAt = nil }
	local function with(fields: { [string]: any }): TugRules.Carrier
		local copy = table.clone(c) :: any
		for key, value in fields do
			copy[key] = value
		end
		return copy
	end
	check("a carrier with a piece alone, away from their van and the door, long since they picked it up: open", (TugRules.open(c, T)))
	check("NEG. nothing in their hands, or a piece carried in two: not", select(2, TugRules.open(with({ carrying = false }), T)) == "alone"
		and select(2, TugRules.open(with({ alone = false }), T)) == "alone")
	check(`NEG. picked up under Protect ({T.Protect} s) ago: not`, select(2, TugRules.open(with({ since = 10 - T.Protect + 0.1 }), T)) == "fresh"
		and (TugRules.open(with({ since = 10 - T.Protect }), T)))
	check(`NEG. within SafeVan ({T.SafeVan} studs) of their own van: not (nobody waits at your van to take it)`,
		select(2, TugRules.open(with({ van = T.SafeVan }), T)) == "van" and (TugRules.open(with({ van = T.SafeVan + 0.1 }), T)))
	check(`NEG. within SafeDoor ({T.SafeDoor} studs) of the house's door: not`, select(2, TugRules.open(with({ door = T.SafeDoor - 1 }), T)) == "door")
	check("NEG. in a tug, stunned, on a door's trip: not", select(2, TugRules.open(with({ busy = true }), T)) == "busy")
	check(`NEG. tugged at under Target ({T.Target} s) ago: not; after it: open`, select(2, TugRules.open(with({ targetAt = 10 - T.Target + 0.5 }), T)) == "again"
		and (TugRules.open(with({ targetAt = 10 - T.Target }), T)))
	check("inside the house (no van, no door near): open", (TugRules.open(with({ van = nil, door = nil }), T)))
end

do
	local g: TugRules.Grabber = { full = false, busy = false, triedAt = nil, now = 10, distance = 4 }
	check("a snatcher with empty hands, near: may", (TugRules.grab(g, T)))
	check("NEG. hands full, busy, far: may not", select(2, TugRules.grab({ full = true, busy = false, now = 10, distance = 4 }, T)) == "full"
		and select(2, TugRules.grab({ full = false, busy = true, now = 10, distance = 4 }, T)) == "busy"
		and select(2, TugRules.grab({ full = false, busy = false, now = 10, distance = T.Reach + 3 }, T)) == "far")
	check(`NEG. tried under Again ({T.Again} s) ago: may not`, select(2, TugRules.grab({ full = false, busy = false, triedAt = 10 - T.Again + 1, now = 10, distance = 4 }, T)) == "again")
end

check("Config.Rounds.Tug: on, the carrier favoured (Start < 0, Boost > 1), a short tug, a stun under the protection",
	T.On and T.Start < 0 and T.Boost > 1 and T.Seconds <= 4 and T.Stun < T.Protect and T.SafeVan > Config.Rounds.Reach)

if failures > 0 then
	error(`{failures} checks failed`)
end
print("ALL CHECKS PASSED")
