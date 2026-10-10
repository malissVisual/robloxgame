-- 6.20, skills for levels (shared/Skills.luau, Config.Skills): the points, the costs, the apex locks, a save's ranks
-- checked, the effects and the attribute's text. Run with tests/run_tests.py.
local Config = require("./Config")
local Skills = require("./Skills")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- The tree as approved (design/skills/PROPOSAL.md): three branches of five, 41 points in all, 14 at level 15.
local total, count, apexes = 0, 0, 0
local ids: { [string]: boolean } = {}
local unique = true
for _, branch in Config.Skills.Branches do
	for _, def in branch.skills do
		total += def.ranks * def.cost
		count += 1
		if def.apex then
			apexes += 1
			check(`{def.id}: an apex is one rank for 3 points`, def.ranks == 1 and def.cost == 3)
		end
		if ids[def.id] then
			unique = false
		end
		ids[def.id] = true
		check(`{def.id}: an English name, an icon, a line and an effect`, def.name ~= "" and def.icon ~= "" and def.text ~= "" and next(def.effect) ~= nil)
	end
end
check("three branches of five skills", #Config.Skills.Branches == 3 and count == 15, count)
check("one apex a branch", apexes == 3)
check("every id once", unique)
check("all of it costs 41 points", total == 41, total)
check("Strong Back: one rank for 2 points", Skills.find("strongBack") ~= nil and (Skills.find("strongBack") :: any).cost == 2 and (Skills.find("strongBack") :: any).ranks == 1)
check("points: none at level 1, level − 1 after", Skills.points(1) == 0 and Skills.points(2) == 1 and Skills.points(9) == 8)
check("14 points at the top level", Skills.points(Config.Levels.MaxLevel) == 14, Skills.points(Config.Levels.MaxLevel))
check("a bad level gives none", Skills.points(0 / 0) == 0 and Skills.points(-3) == 0)

-- Buying.
local none: Skills.Ranks = {}
check("level 1 cannot buy", not Skills.canBuy(none, 1, "longBreath"))
local ok, why = Skills.canBuy(none, 2, "longBreath")
check("level 2 buys a rank", ok and why == nil)
local one = Skills.buy(none, 2, "longBreath")
check("… the new table has it, the old one not", one ~= nil and (one :: any).longBreath == 1 and none.longBreath == nil)
check("… and the point is spent", Skills.free(one, 2) == 0 and Skills.spent(one) == 1)
local _, short = Skills.canBuy(one, 2, "longBreath")
check("no point left: why", short == "Need a point", short)
local _, two = Skills.canBuy(none, 2, "strongBack")
check("Strong Back needs 2 points", two == "Need 2 points", two)
check("an unknown skill", not Skills.canBuy(none, 15, "flying") and Skills.buy(none, 15, "flying") == nil)
local maxed: Skills.Ranks = { longBreath = 3 }
local _, max = Skills.canBuy(maxed, 15, "longBreath")
check("a full skill: Max rank", max == "Max rank", max)
local _, locked = Skills.canBuy({ longBreath = 3, lightStep = 2 }, 15, "express")
check("an apex under 6 points in its branch: 🔒 6", locked == `🔒 {Config.Skills.ApexNeeds}`, locked)
check("6 points in the branch open it", (Skills.canBuy({ longBreath = 3, doorstepSmile = 3 }, 15, "express")))
check("points in another branch do not", not Skills.canBuy({ toughBody = 3, quickHands = 3 }, 15, "express"))
check("an apex costs 3", not Skills.canBuy({ longBreath = 3, doorstepSmile = 3 }, 8, "express") and (Skills.canBuy({ longBreath = 3, doorstepSmile = 3 }, 10, "express")))

-- A save's ranks.
local clean = Skills.clean({ longBreath = 7, doorstepSmile = 2.6, flying = 2, express = 1, hardFist = "x" }, 15)
check("clean: known ids, whole ranks within the skill's", clean.longBreath == 3 and clean.doorstepSmile == 2 and clean.flying == nil and clean.hardFist == nil)
check("clean: an apex without its branch's 6 points goes", clean.express == nil)
check("clean: an apex with them stays", Skills.clean({ longBreath = 3, doorstepSmile = 3, express = 1 }, 15).express == 1)
check("clean: more than the level gives: every point back", next(Skills.clean({ longBreath = 3, doorstepSmile = 3 }, 4)) == nil)
check("clean: nothing saved (an old save): none", next(Skills.clean(nil, 9)) == nil and Skills.free(Skills.clean(nil, 9), 9) == 8)

-- The effects.
local all: Skills.Ranks = { strongBack = 1, longBreath = 3, doorstepSmile = 3, lightStep = 2, toughBody = 3, steadyHand = 2, endurance = 3, fieldMedic = 2 }
check("effects add up by rank", Skills.effect(all, "hands") == 1 and Skills.effect(all, "bag") == 1 and Skills.effect(all, "sprintTime") == 4.5 and math.abs(Skills.effect(all, "tips") - 0.15) < 1e-9)
check("… health +30, two free medkit ranks, no punch", Skills.effect(all, "health") == 30 and Skills.effect(all, "freeMedkit") == 2 and Skills.effect(all, "punch") == 0)
check("… none: 0", Skills.effect(nil, "hands") == 0 and Skills.effect({}, "spread") == 0)
check("car damage: Tough Body −24%", math.abs(Skills.carDamage(all, nil) - 0.76) < 1e-9)
local stunt: Skills.Ranks = { toughBody = 3, quickHands = 3, stuntman = 1 }
check("Stuntman: a zombie run over costs nothing", Skills.carDamage(stunt, "ram") == 0)
check("Stuntman: a ram half (with Tough Body)", math.abs(Skills.carDamage(stunt, "crash") - 0.38) < 1e-9)
check("without Stuntman a ram is a hit like any", math.abs(Skills.carDamage(all, "ram") - 0.76) < 1e-9)
check("the real numbers: sprint 6 s → 10.5 s", Skills.describe((Skills.find("longBreath") :: any), 0) == `Sprint {Config.Movement.Stamina} s` and Skills.describe((Skills.find("longBreath") :: any), 3) == "Sprint 10.5 s")
check("… sprint speed 28 → 30.2", Skills.describe((Skills.find("lightStep") :: any), 2) == "Sprint speed 30.2", Skills.describe((Skills.find("lightStep") :: any), 2))
check("… punch 12 → 21", Skills.describe((Skills.find("hardFist") :: any), 3) == "Punch 21 damage")
check("… health 100 → 130", Skills.describe((Skills.find("endurance") :: any), 3) == "Health 130")
check("… a serve stop 3 s → 2.1 s", Skills.describe((Skills.find("quickHands") :: any), 3) == "Serve 2.1 s", Skills.describe((Skills.find("quickHands") :: any), 3))

-- The attribute's text.
local text = Skills.encode(all)
check("encode: the ranks held, in the tree's order", string.sub(text, 1, 26) == "strongBack:1,longBreath:3,", text)
local back = Skills.decode(text)
local same = true
for id, rank in all do
	if back[id] ~= rank then
		same = false
	end
end
check("decode gives them back", same)
check("decode: junk and unknown ids are nothing", next(Skills.decode("flying:3,longBreath:9")) ~= nil and Skills.decode("flying:3,longBreath:9").longBreath == 3 and Skills.decode(nil).longBreath == nil)
check("encode of none is empty", Skills.encode({}) == "")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
