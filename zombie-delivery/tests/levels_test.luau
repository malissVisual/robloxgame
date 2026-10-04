-- Driver levels (shared/Levels.luau): the XP curve, ranks and job XP. Run with tests/run_tests.py.
local Config = require("./Config")
local Levels = require("./Levels")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

check("level 1 needs no XP", Levels.xpFor(1) == 0)
check("level 2 needs XpBase", Levels.xpFor(2) == Config.Levels.XpBase, Levels.xpFor(2))
local rising = true
for level = 2, Config.Levels.MaxLevel do
	if Levels.xpFor(level) <= Levels.xpFor(level - 1) then
		rising = false
	end
end
check("every level needs more XP", rising)
check("0 XP is level 1", Levels.levelFor(0) == 1)
check("exactly the threshold reaches the level", Levels.levelFor(Levels.xpFor(5)) == 5)
check("one XP short stays below", Levels.levelFor(Levels.xpFor(5) - 1) == 4)
check("capped at MaxLevel", Levels.levelFor(10 ^ 9) == Config.Levels.MaxLevel)
check("rank of level 1", Levels.rank(1) == "Rookie Courier", Levels.rank(1))
check("rank between steps", Levels.rank(7) == Levels.rank(6), Levels.rank(7))
check("progress in range", Levels.progress(Levels.xpFor(3) + 1) > 0 and Levels.progress(Levels.xpFor(3) + 1) < 1)
check("job XP grows with stars", Levels.jobXp(3, 2, 0, false, true) > Levels.jobXp(1, 2, 0, false, true))
check("night bonus", Levels.jobXp(2, 2, 2, true, true) > Levels.jobXp(2, 2, 2, false, true))
check("a failed job gives less", Levels.jobXp(2, 2, 2, false, false) < Levels.jobXp(2, 2, 2, false, true))
for _, tier in Config.Jobs.Tiers do
	check(`tier {tier.stars} has a reachable level`, tier.level >= 1 and tier.level <= Config.Levels.MaxLevel)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
