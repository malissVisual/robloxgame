-- 6.15: the enemies' subtle outline (shared/OutlinePick.luau, Config.Outline) in the standalone Luau CLI: within
-- Roblox's 31 Highlights, subtle, the nearest living ones in range, no corpses, the colours (zombies red, the people
-- orange), no blinking at the edge, the phone's smaller budget.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local OutlinePick = require("./OutlinePick")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local O = Config.Outline
local function isColor(c: any): boolean
	return type(c) == "table" and #c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255 and c[3] >= 0 and c[3] <= 255
end

-- The numbers.
check("the colours are { r, g, b }", isColor(O.Zombie) and isColor(O.Human))
check("zombies red: red strong, green and blue weak", O.Zombie[1] >= 200 and O.Zombie[2] <= 80 and O.Zombie[3] <= 80, table.concat(O.Zombie, ","))
check("people orange: red strong, green between, blue weak", O.Human[1] >= 200 and O.Human[2] >= 100 and O.Human[2] <= 190 and O.Human[3] <= 80, table.concat(O.Human, ","))
check("just subtle: the outline half see-through or more, never gone", O.Transparency >= 0.5 and O.Transparency <= 0.7, O.Transparency)
check("Count plus Spare within Roblox's 31 Highlights", O.Count + O.Spare <= OutlinePick.ROBLOX_MAX and O.Count >= 4 and O.Spare >= 1, O.Count + O.Spare)
check("the limit is the count (it fits)", OutlinePick.limit == O.Count, OutlinePick.limit)
check("a range for the street (100 … 250 studs)", O.Range >= 100 and O.Range <= 250, O.Range)
check("picked a few times a second (0.1 … 0.5 s)", O.Every >= 0.1 and O.Every <= 0.5, O.Every)
check("the hold is a little more than the range", O.HoldRange > 1 and O.HoldRange < 1.5, O.HoldRange)
check("a phone still outlines a few", math.floor(O.Count * Config.Performance.Lite.Count + 0.5) >= 4 and O.Range * Config.Performance.Lite.Range >= 60)

-- Which colour: the server's Bandit mark (bandits, gunners, the pickups) is orange; the zombie kinds red.
check("a walker is red", OutlinePick.tone("walker", false) == "zombie")
check("a runner is red", OutlinePick.tone("runner", false) == "zombie")
check("a brute is red", OutlinePick.tone("brute", false) == "zombie")
check("a bandit (marked Bandit) is orange", OutlinePick.tone("bandit", true) == "human")
check("a gunner (marked Bandit) is orange", OutlinePick.tone("gunner", true) == "human")
check("a bandits' pickup (no kind, marked Bandit) is orange", OutlinePick.tone(nil, true) == "human")
check("the base's soldier (infected look, bites) follows HumanKinds", OutlinePick.tone("soldier", false) == (if O.HumanKinds.soldier == true then "human" else "zombie"))
check("no kind and no mark: red", OutlinePick.tone(nil, false) == "zombie")
-- (server/Zombies.luau marks Bandit exactly the ranged kinds)
check("every kind: orange when it shoots (Bandit) or HumanKinds names it, else red", (function(): boolean
	for kind, def in Config.Zombies do
		local want = if def.ranged == true or O.HumanKinds[kind] == true then "human" else "zombie"
		if OutlinePick.tone(kind, def.ranged == true) ~= want then
			return false
		end
	end
	return true
end)())
check("HumanKinds names only real kinds", (function(): boolean
	for kind in O.HumanKinds do
		if Config.Zombies[kind] == nil then
			return false
		end
	end
	return true
end)())
check("the tones' colours", OutlinePick.color("zombie") == O.Zombie and OutlinePick.color("human") == O.Human)

-- Who wears one: OutlinePick.choose.
local function entries(list: { { any } }): { OutlinePick.Entry }
	local out: { OutlinePick.Entry } = {}
	for _, e in list do
		table.insert(out, { distance = e[1], alive = e[2] ~= false, human = e[3] == true, outlined = e[4] == true })
	end
	return out
end
local function size(set: { [number]: any }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

local picked = OutlinePick.choose(entries({ { 50 }, { 400 }, { 10 }, { 90 }, { 30 }, { 150 } }), 3, 160)
check("the three nearest in range", picked[3] ~= nil and picked[5] ~= nil and picked[1] ~= nil and size(picked) == 3, size(picked))
check("nothing out of range", picked[2] == nil)
local all = OutlinePick.choose(entries({ { 50 }, { 400 }, { 10 } }), 24, 160)
check("fewer in range than allowed: all of those", all[1] ~= nil and all[3] ~= nil and all[2] == nil)
check("no enemies: none", next(OutlinePick.choose({}, 24, 160)) == nil)
check("a count of 0: none", next(OutlinePick.choose(entries({ { 5 } }), 0, 160)) == nil)

local dead = OutlinePick.choose(entries({ { 5, false }, { 20 }, { 8, false, true, true } }), 24, 160)
check("a corpse never (even the nearest)", dead[1] == nil)
check("a corpse that wore one loses it", dead[3] == nil)
check("the living one does", dead[2] ~= nil)

local tones = OutlinePick.choose(entries({ { 10, true, false }, { 20, true, true } }), 24, 160)
check("a zombie red, a person orange", tones[1] == "zombie" and tones[2] == "human", `{tones[1]} {tones[2]}`)

-- Never over the limit (Roblox's 31), whatever the count asked.
local many: { { any } } = {}
for n = 1, 60 do
	table.insert(many, { n })
end
local capped = OutlinePick.choose(entries(many), 100, 1000)
check("never more than the limit", size(capped) == OutlinePick.limit, size(capped))
check("never more than Roblox's 31 less the spare", size(capped) <= OutlinePick.ROBLOX_MAX - O.Spare)
check("the limit's are the nearest", capped[1] ~= nil and capped[OutlinePick.limit] ~= nil and capped[OutlinePick.limit + 1] == nil)
local phone = OutlinePick.choose(entries(many), 12, 1000)
check("a phone's smaller count", size(phone) == 12, size(phone))

-- No blinking at the edge: one outlined keeps it a little past the range, a new one only within it.
local edge = 160 * (1 + (O.HoldRange - 1) / 2)
local held = OutlinePick.choose(entries({ { edge, true, false, true }, { edge, true, false, false } }), 24, 160)
check("an outlined one just past the range keeps it", held[1] ~= nil)
check("a new one there does not get one", held[2] == nil)
local gone = OutlinePick.choose(entries({ { 160 * O.HoldRange + 1, true, false, true } }), 24, 160)
check("past the hold it goes", gone[1] == nil)
-- … and no swapping: two at about the same distance, the outlined one stays when only one fits.
local stay = OutlinePick.choose(entries({ { 52, true, false, false }, { 55, true, false, true } }), 1, 160)
check("about as near as a new one: the outlined one stays", stay[2] ~= nil and stay[1] == nil)
local closer = OutlinePick.choose(entries({ { 20, true, false, false }, { 55, true, false, true } }), 1, 160)
check("a much nearer new one takes it", closer[1] ~= nil and closer[2] == nil)
local ties = OutlinePick.choose(entries({ { 30 }, { 30 }, { 30 } }), 2, 160)
check("a tie goes to the first (steady)", ties[1] ~= nil and ties[2] ~= nil and ties[3] == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
