-- Logic test of getting in and out of a car (shared/Boarding.luau, Config.Cargo) in the standalone Luau CLI: the move's
-- timing (a step to the handle, then the slide, done at BoardSeconds), a late start plays quicker but never too quick,
-- the curve starts and ends where it should, the hand's reach, the doors' swing (open in DoorSwingSeconds, shut in
-- DoorShutSeconds, two openings at one door joined), the seat's attribute and the footprint check.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Boarding = require("./Boarding")

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

local C = Config.Cargo

-- The numbers ---------------------------------------------------------------------

check("getting in takes about half a second", C.BoardSeconds >= 0.4 and C.BoardSeconds <= 0.8, C.BoardSeconds)
check("the step to the handle is a part of it", C.BoardStepSeconds > 0 and C.BoardStepSeconds < C.BoardSeconds)
check("getting out is quicker than getting in", C.AlightSeconds > 0 and C.AlightSeconds < C.BoardSeconds)
check("the door shuts quickly", C.DoorShutSeconds > 0 and C.DoorShutSeconds <= 0.3, C.DoorShutSeconds)
check("the old 1.1 s open door is gone", (C :: any).DoorOpenSeconds == nil)
check("the stand point is outside the body", C.DoorStandOut > 0.5)
check("a car standing still can be boarded, one rolling away cannot", C.BoardMaxSpeed > 0 and C.BoardMaxSpeed < 20)

-- The phases ----------------------------------------------------------------------

local phase, u = Boarding.boardPhase(0)
check("t 0: the step, at its start", phase == "step" and near(u, 0), `{phase} {u}`)
phase, u = Boarding.boardPhase(C.BoardStepSeconds / 2)
check("halfway to the handle", phase == "step" and near(u, 0.5), `{phase} {u}`)
phase, u = Boarding.boardPhase(C.BoardStepSeconds)
check("at the handle the slide starts", phase == "slide" and near(u, 0), `{phase} {u}`)
phase, u = Boarding.boardPhase(C.BoardSeconds - 1e-4)
check("the slide ends at the seat", phase == "slide" and u > 0.999, `{phase} {u}`)
phase, u = Boarding.boardPhase(C.BoardSeconds)
check("then done", phase == "done" and u == 1, phase)
local last = -1
local monotone = true
for i = 0, 50 do
	local _, v = Boarding.boardPhase(C.BoardStepSeconds + (C.BoardSeconds - C.BoardStepSeconds) * i / 50)
	if v < last - 1e-9 then
		monotone = false
	end
	last = v
end
check("the slide only goes forward", monotone)

-- A late start ---------------------------------------------------------------------

check("on time: the whole move", near(Boarding.span(0, C.BoardSeconds, 0.2), C.BoardSeconds))
check("0.1 s late: the rest of the time", near(Boarding.span(0.1, C.BoardSeconds, 0.2), C.BoardSeconds - 0.1))
check("very late: never quicker than the minimum", near(Boarding.span(5, C.BoardSeconds, 0.2), 0.2))
check("a clock a little ahead does not stretch it", near(Boarding.span(-0.05, C.BoardSeconds, 0.2), C.BoardSeconds))
local span = Boarding.span(0.1, C.BoardSeconds, 0.2)
check("the move starts at 0", near(Boarding.moveTime(0, span, C.BoardSeconds), 0))
check("and ends at the seat when the server seats you", near(Boarding.moveTime(span, span, C.BoardSeconds), C.BoardSeconds))
check("and holds there", near(Boarding.moveTime(span + 1, span, C.BoardSeconds), C.BoardSeconds))

-- The curve ----------------------------------------------------------------------

check("the curve starts at its start", near(Boarding.bezier(1, 5, 9, 0), 1))
check("and ends at its end", near(Boarding.bezier(1, 5, 9, 1), 9))
check("pulled toward the middle point", near(Boarding.bezier(0, 4, 0, 0.5), 2))
check("no duck at the ends", near(Boarding.duck(0), 0) and near(Boarding.duck(1), 0, 1e-9))
check("the most halfway", near(Boarding.duck(0.5), math.rad(C.BoardDuck)))
local x, y, z = Boarding.through(-1, 3.2, 3, 0.5, 2.6, false)
check("the door opening is on the body's side", near(x, -3.2) and near(z, 0.5), `{x} {z}`)
check("a little over the higher end", y > 3 and y < 4, y)
local _, climbY = Boarding.through(1, 3, 3, 0, 4, true)
check("a doorless seat is a climb over the side", near(climbY, 4 + C.ClimbArc), climbY)

-- The hand ------------------------------------------------------------------------

check("no reach before", Boarding.reach(-0.1, false) == 0)
check("the hand on the handle at the step's end", near(Boarding.reach(C.BoardStepSeconds, false), 1))
check("held a moment", near(Boarding.reach(C.BoardStepSeconds + 0.1, false), 1))
check("let go before the seat", Boarding.reach(C.BoardSeconds, false) == 0, Boarding.reach(C.BoardSeconds, false))
check("getting out: a push", Boarding.reach(0.08, true) > 0.5 and Boarding.reach(0.3, true) == 0)

-- The doors -----------------------------------------------------------------------

check("shut before it opens", Boarding.doorGoal(9, 10, 11) == 0)
check("open between", Boarding.doorGoal(10.5, 10, 11) == 1)
check("shut after", Boarding.doorGoal(11, 10, 11) == 0)
check("never opened: shut", Boarding.doorGoal(10, nil, nil) == 0)
local open = 0
local frames = 0
while open < 1 and frames < 1000 do
	open = Boarding.doorStep(open, 1, 1 / 60)
	frames += 1
end
check("open in DoorSwingSeconds", math.abs(frames / 60 - C.DoorSwingSeconds) < 2 / 60, frames / 60)
frames = 0
while open > 0 and frames < 1000 do
	open = Boarding.doorStep(open, 0, 1 / 60)
	frames += 1
end
check("shut in DoorShutSeconds", math.abs(frames / 60 - C.DoorShutSeconds) < 2 / 60, frames / 60)
local a, b = Boarding.mergeDoor(10, 10.5, 10.2, 10.9, 10.1)
check("two at one door: open from the first, shut after the last", near(a, 10) and near(b, 10.9), `{a} {b}`)
a, b = Boarding.mergeDoor(5, 5.5, 10.2, 10.9, 10.1)
check("an old opening is forgotten", near(a, 10.2) and near(b, 10.9), `{a} {b}`)

-- The attribute and the footprint --------------------------------------------------

local owner, door, seat = Boarding.decode(Boarding.encode(123456, 2, 3))
check("the seat's attribute goes both ways", owner == 123456 and door == 2 and seat == 3, `{owner} {door} {seat}`)
owner = Boarding.decode("nonsense")
check("nonsense is nothing", owner == nil)
owner = Boarding.decode(nil)
check("nil is nothing", owner == nil)
check("in the cabin: over the car", Boarding.inside(0.5, -1, 3.5, 6.5))
check("at the door: not", not Boarding.inside(3.5 + 1.5, -1, 3.5, 6.5))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
