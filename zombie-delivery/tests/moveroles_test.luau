-- shared/MoveRoles.luau (pure; tests/run_tests.py runs it with the real Config): a run's quick chat, the climb with a
-- carried piece, the van call's words, and their numbers (the module keeps the 7.0 roles' name; 10.9: the roles and the
-- planning lobby deleted).
local MoveRoles = require("./MoveRoles")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

local R = Config.MoveRoles

check("the numbers", R.Climb.Walk > 0 and R.Climb.Walk < 1 and R.Climb.Rise > 0 and R.Climb.Hold > 0 and R.CallNear > 0
	and R.Chat.Bubble > 0 and R.Chat.Feed > 0 and R.Chat.Hold > 0 and Config.Robust.Limits.QuickChat > 0 and Config.Robust.Limits.QuickChat <= 1)

-- The climb ------------------------------------------------------------------------------------------------------------

check("a climb: 3 up over 2 along; not a step on the flat, nor a gentle ramp", MoveRoles.climbing(3, 2) and MoveRoles.climbing(1, 0) and not MoveRoles.climbing(0.1, 0)
	and not MoveRoles.climbing(1, 10) and not MoveRoles.climbing(-3, 2) and not MoveRoles.climbing(0 / 0, 1))
check("up a climb: × Climb.Walk with both hands, a drag and a pair piece; a piece in one hand not", near(MoveRoles.climbFactor("both"), R.Climb.Walk)
	and near(MoveRoles.climbFactor("drag"), R.Climb.Walk) and near(MoveRoles.climbFactor("pair"), R.Climb.Walk) and MoveRoles.climbFactor("hand") == 1)

-- The quick chat, the words ----------------------------------------------------------------------------------------------

local lines = {}
for _, line in MoveRoles.Chat do
	table.insert(lines, line.text)
	if line.icon == "" then
		lines = {}
		break
	end
end
check("the quick chat's six lines", #MoveRoles.Chat == 6 and MoveRoles.Chat[2].id == "hand" and lines[1] == "Hold the door" and lines[2] == "Need a hand here" and lines[3] == "Zombies!" and lines[4] == "Truck's here"
	and lines[5] == "I'll come pick you up" and lines[6] == "Done — let's go")
check("the van's second call has its own words", MoveRoles.whyText("called") ~= MoveRoles.whyText("no such code") and MoveRoles.whyText(nil) ~= "")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
