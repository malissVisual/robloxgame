-- 5.7, life on a run on foot or by bike (shared/FootEvents.luau, Config.Jobs.FootEvents) and the step up to a car
-- (JobRules.carStep*, Config.Jobs.CarStep). Run with tests/run_tests.py.
local Config = require("./Config")
local Economy = require("./Economy")
local Levels = require("./Levels")
local JobRules = require("./JobRules")
local FootEvents = require("./FootEvents")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local tuning = Config.Jobs.FootEvents

-- ── Which runs ───────────────────────────────────────────────────────────────

check("foot and bike runs get them", FootEvents.applies("foot", nil, nil) and FootEvents.applies("bike", false, nil))
check("never a car job, the tutorial's delivery or a mission", not FootEvents.applies("car", nil, nil) and not FootEvents.applies("foot", true, nil)
	and not FootEvents.applies("foot", nil, "dispatch1"))
check("about one run in four", tuning.Chance >= 0.2 and tuning.Chance <= 0.3)

-- ── The pick ─────────────────────────────────────────────────────────────────

check("no event over the chance", FootEvents.pick(tuning.Chance, 0.5) == nil and FootEvents.pick(0.99, 0.1) == nil)
local seen: { [string]: number } = {}
local runs, events = 4000, 0
math.randomseed(57)
for _ = 1, runs do
	local kind = FootEvents.pick(math.random(), math.random())
	if kind then
		events += 1
		seen[kind] = (seen[kind] or 0) + 1
	end
end
local share = events / runs
check("the share of runs with an event is the chance", math.abs(share - tuning.Chance) < 0.03, share)
for _, kind in FootEvents.Kinds do
	check(`{kind} comes`, (seen[kind] or 0) > events / 6, seen[kind])
end
check("the three light events, none of the car's", #FootEvents.Kinds == 3 and seen.addon == nil and seen.roadblock == nil)
for kind in tuning.Weights do
	check(`weight {kind} is a known event`, table.find(FootEvents.Kinds, kind) ~= nil)
end
check("the first and the last band of r2", FootEvents.pick(0, 0) == "runner" and FootEvents.pick(0, 0.9999) == "gate")

-- ── When, the tip, the walkers ───────────────────────────────────────────────

check("it comes after After seconds", FootEvents.after(0) == tuning.After[1] and FootEvents.after(1) == tuning.After[2] and FootEvents.after(2) == tuning.After[2])
local tipsOk = true
for n = 0, 20 do
	local tip = FootEvents.tip(n / 20)
	tipsOk = tipsOk and tip >= tuning.Tip[1] and tip <= tuning.Tip[2] and tip % 5 == 0
end
check("a tip within Tip, in $5 steps", tipsOk and FootEvents.tip(0) == tuning.Tip[1] and FootEvents.tip(1) == tuning.Tip[2])
check("a tip is small next to a foot run's pay", tuning.Tip[2] <= Config.Jobs.Foot.PayMin)
check("no walkers over the chance", FootEvents.group(tuning.GroupChance, 0.5) == 0 and FootEvents.group(0.99, 0) == 0)
check("a small group: Group (min … max)", FootEvents.group(0, 0) == tuning.Group[1] and FootEvents.group(0, 0.9999) == tuning.Group[2])
check("about one drop in five", tuning.GroupChance >= 0.15 and tuning.GroupChance <= 0.25)
check("a small group stays small", tuning.Group[2] <= 3 and tuning.Group[1] >= 1)

-- ── The gate ─────────────────────────────────────────────────────────────────

-- A road along X at z = 100, 30 wide; you walk on its north side (z > 100).
local width = 30
local cx, cz, ax, az, sx, sz = FootEvents.gate(0, 100, 1, 0, width, 5, 125)
check("the gate on your side of the road", cz > 100 and sz > 0, cz)
check("from the kerb into the sidewalk", math.abs(cz - (100 + width / 2 + tuning.GateWidth / 2)) < 1e-6 and math.abs(cx) < 1e-6, cz)
check("its face looks along the kerb", ax == 1 and az == 0 and math.abs(sx) < 1e-9)
local _, southZ = FootEvents.gate(0, 100, 1, 0, width, 5, 60)
check("the other side when you come from there", southZ < 100 - width / 2, southZ)
local gx = FootEvents.gate(200, 0, 0, 1, width, 240, 10)
check("a road along Z: the gate to the east", gx > 200 + width / 2, gx)
check("the gate is passable round by the road", tuning.GateWidth <= 12 and tuning.GateTime > 0 and tuning.GateAhead >= 20)

-- ── The words ────────────────────────────────────────────────────────────────

for _, kind in FootEvents.Kinds do
	check(`a notice for {kind}`, FootEvents.notice(kind, "Ada", 20) ~= "")
end
check("the survivor's notice names them and the tip", string.find(FootEvents.notice("survivor", "Ada", 20), "Ada", 1, true) ~= nil
	and string.find(FootEvents.notice("survivor", "Ada", 20), "$20", 1, true) ~= nil)
check("the survivor calls out", FootEvents.say("survivor") ~= "")
check("names to call", #tuning.SurvivorNames >= 4)

-- ── 5.7, the step up to a car (JobRules) ────────────────────────────────────

check("a ★ board delivery in your car is the step", JobRules.carStep("car", 1, false) and not JobRules.carStep("car", 2, false)
	and not JobRules.carStep("car", 1, true) and not JobRules.carStep("foot", 1, false) and not JobRules.carStep("bike", 1, false))
check("+40 XP", JobRules.carStepXp(100) == 100 + Config.Jobs.CarStep.XpBonus and Config.Jobs.CarStep.XpBonus == 40)
local band = Config.Jobs.CarStep.Pieces
check("3 – 4 pieces in a car that holds them", band[1] == 3 and band[2] == 4 and JobRules.carStepPieces("long", 0, 4) == 3 and JobRules.carStepPieces("long", 0.99, 4) == 4)
check("SHORT & SAFE: the fewest", JobRules.carStepPieces("short", 0.99, 4) == band[1])
local rusty = Economy.stageCapacity("van", 0)
check("never more than the car holds (the Rusty Van: 2)", JobRules.carStepPieces("bulk", 0.99, rusty) == rusty and rusty == Config.Jobs.EasyMaxPieces)
check("no car: the Rusty Van's load", JobRules.carStepPieces("long", 0.99, nil) == Config.Jobs.EasyMaxPieces)
check("the Work Van takes 3", JobRules.carStepPieces("long", 0.99, Economy.stageCapacity("van", 2)) == 3)
-- The Old Van at level 4 is a promotion: a ★ car run's XP over a bike run's of the usual size (3 pieces) and a walk's.
local carXp = JobRules.carStepXp(Levels.jobXp(1, 3, 0, false, true))
local bikeXp = JobRules.bikeXp(Levels.jobXp(1, 3, 0, false, true))
local footXp = Levels.jobXp(1, 2, 0, false, true)
print(`  ★ XP: on foot {footXp}, by bike {bikeXp}, by car {carXp}`)
check("the car pays more XP than the bike, the bike more than a walk", carXp > bikeXp and bikeXp > footXp)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
