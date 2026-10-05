-- Logic test of the sprint's breath (client/Stamina.luau, Config.Movement) in the standalone Luau CLI: it drains only
-- while you really sprint and move, comes back after RecoverDelay over Recover seconds, an empty breath stops the
-- sprint until MinToSprint is back (no stutter), and the bar shows while the breath is not full.
-- Run: python3 tests/run_tests.py [path to the luau binary] (it copies client/Stamina.luau next to this test).

local Config = require("./Config")
local Stamina = require("./Stamina")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end

local M = Config.Movement
local DT = 1 / 60

-- Runs `seconds` of frames; returns the state and how many of those frames sprinted.
local function run(state: Stamina.State, seconds: number, wantSprint: boolean, moving: boolean): (Stamina.State, number)
	local sprinted = 0
	for _ = 1, math.floor(seconds / DT + 0.5) do
		state = Stamina.step(state, DT, wantSprint, moving, M)
		if state.sprinting then
			sprinted += 1
		end
	end
	return state, sprinted
end

-- The numbers --------------------------------------------------------------------

check("walk 14, sprint 28", M.Walk == 14 and M.Sprint == 28, `{M.Walk} / {M.Sprint}`)
check("the sprint is faster than the walk", M.Sprint > M.Walk)
check("6 s of breath, 4 s to full, 0.8 s pause", M.Stamina == 6 and M.Recover == 4 and M.RecoverDelay == 0.8)
check("MinToSprint is a share of the breath", M.MinToSprint > 0 and M.MinToSprint < 1, M.MinToSprint)
check("the red starts at or under MinToSprint", M.Low > 0 and M.Low <= M.MinToSprint, M.Low)
check("the bar lingers a moment", M.HideAfter > 0, M.HideAfter)

-- A fresh breath -----------------------------------------------------------------

local fresh = Stamina.new()
check("a new breath is full", fresh.breath == 1 and not fresh.exhausted)
check("a new breath may sprint", Stamina.canSprint(fresh))
check("a new breath hides the bar", not Stamina.barShown(fresh, M))
check("a new breath is not low", not Stamina.low(fresh, M))

-- step is pure: the given state is left as it was.
local after = Stamina.step(fresh, 1, true, true, M)
check("step returns a new state", after ~= fresh and fresh.breath == 1 and after.breath < 1)
check("one second of sprint costs 1 / Stamina", near(after.breath, 1 - 1 / M.Stamina), after.breath)
check("that step sprinted", after.sprinting)
check("the bar shows once the breath is not full", Stamina.barShown(after, M))

-- Draining only while really sprinting and moving -------------------------------

local s = Stamina.new()
s = run(s, 3, true, false)
check("Shift held, standing still: no drain", s.breath == 1, s.breath)
check("Shift held, standing still: still 'sprinting' (ready to run)", s.sprinting)
s = run(Stamina.new(), 3, false, true)
check("walking: no drain", s.breath == 1, s.breath)
s = run(Stamina.new(), 3, true, true)
check("3 s of sprint: half the breath", near(s.breath, 0.5, 0.01), s.breath)

-- Running dry --------------------------------------------------------------------

local sprinted
-- (just over Stamina seconds: held longer, the sprint would come back once MinToSprint is)
s, sprinted = run(Stamina.new(), M.Stamina + 0.5, true, true)
check("a full breath lasts Stamina seconds", near(sprinted * DT, M.Stamina, 2 * DT), sprinted * DT)
check("after it: out of breath", s.exhausted)
check("out of breath: no sprint", not Stamina.canSprint(s) and not s.sprinting)
check("out of breath: low (red)", Stamina.low(s, M))

-- Shift held all along: no sprint until MinToSprint is back, and no stutter (one run, then one walk, then one run).
s = Stamina.new()
local switches, last = 0, true
local firstBack: number? = nil
local elapsed = 0
for _ = 1, math.floor(14 / DT) do
	s = Stamina.step(s, DT, true, true, M)
	elapsed += DT
	if s.sprinting ~= last then
		switches += 1
		last = s.sprinting
		if s.sprinting and firstBack == nil then
			firstBack = elapsed
		end
	end
end
-- The sprint stops at Stamina s, the breath waits RecoverDelay, then needs MinToSprint * Recover to come back.
local expected = M.Stamina + M.RecoverDelay + M.MinToSprint * M.Recover
check("held Shift: the sprint comes back once MinToSprint is", firstBack ~= nil and near(firstBack, expected, 3 * DT), firstBack)
check("held Shift: whole runs and walks, no flicker", switches <= 5, switches)

-- No stutter at the empty end: right after running dry, many frames of Shift do nothing.
s = run(Stamina.new(), M.Stamina + 0.05, true, true)
local exhaustedAt = s
local blocked = true
for _ = 1, math.floor((M.RecoverDelay + M.MinToSprint * M.Recover - 0.1) / DT) do
	s = Stamina.step(s, DT, true, true, M)
	if s.sprinting then
		blocked = false
	end
end
check("ran dry: Shift does nothing until MinToSprint", blocked and exhaustedAt.exhausted)

-- Recovery -----------------------------------------------------------------------

-- One long sprinting step empties it with no rest after it.
s = Stamina.step(Stamina.new(), M.Stamina + 1, true, true, M)
check("dry", s.breath == 0 and s.rest == 0)
local paused = run(s, M.RecoverDelay - 0.05, false, false)
check("nothing comes back during RecoverDelay", paused.breath == 0, paused.breath)
local back = run(s, M.RecoverDelay + M.Recover / 2, false, false)
check("half the breath back Recover / 2 after the pause", near(back.breath, 0.5, 0.01), back.breath)
check("exhausted clears at MinToSprint", not back.exhausted and Stamina.canSprint(back))
local full = run(s, M.RecoverDelay + M.Recover + 0.05, false, false)
check("full again after RecoverDelay + Recover", full.breath == 1, full.breath)
-- Walking recovers too (only the sprint costs breath).
local walked = run(s, M.RecoverDelay + M.Recover + 0.05, false, true)
check("walking recovers the breath", walked.breath == 1, walked.breath)

-- A short sprint stops recovery again: RecoverDelay starts over.
s = run(Stamina.new(), 2, true, true)
s = run(s, M.RecoverDelay + 0.5, false, false)
local before = s.breath
s = run(s, 0.1, true, true)
s = run(s, M.RecoverDelay - 0.1, false, false)
check("a new sprint restarts the pause", s.breath < before, `{s.breath} vs {before}`)

-- A sprint stopped by something else (aiming, cargo: wantSprint false) recovers like a walk.
s = run(Stamina.new(), 2, true, true)
local aimed = run(s, M.RecoverDelay + 1, false, true)
check("aiming / carrying: the breath comes back", aimed.breath > s.breath)

-- The bar ------------------------------------------------------------------------

s = run(Stamina.new(), 1, true, true)
check("bar shown while not full", Stamina.barShown(s, M))
-- Rest frame by frame until the breath is just full.
for _ = 1, math.floor((M.RecoverDelay + M.Recover) / DT) do
	s = Stamina.step(s, DT, false, false, M)
	if s.breath >= 1 then
		break
	end
end
check("full again", s.breath == 1)
check("the bar stays a moment after full", Stamina.barShown(s, M))
local lingered = run(s, M.HideAfter - 0.2, false, false)
check("still there just before HideAfter", Stamina.barShown(lingered, M))
local gone = run(s, M.HideAfter + 0.1, false, false)
check("gone after HideAfter", not Stamina.barShown(gone, M))

s = run(Stamina.new(), M.Stamina * (1 - M.Low) + 0.1, true, true)
check("nearly empty: low", Stamina.low(s, M) and not s.exhausted, s.breath)
s = run(Stamina.new(), M.Stamina * (1 - M.Low) - 0.3, true, true)
check("a fair amount left: not low", not Stamina.low(s, M), s.breath)

-- Odd input ----------------------------------------------------------------------

s = Stamina.step(Stamina.new(), -5, true, true, M)
check("a negative dt changes nothing", s.breath == 1, s.breath)
s = Stamina.step(Stamina.new(), 1000, true, true, M)
check("a huge dt empties, never below 0", s.breath == 0 and s.exhausted, s.breath)
s = Stamina.step(s, 1000, false, false, M)
check("a huge rest fills, never above 1", s.breath == 1 and not s.exhausted, s.breath)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
