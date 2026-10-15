-- 8.5.1 (the owner: "I want him to go, open the door and get in"): Danny's hand on the van's door. The real
-- client/ArmPose.luau (tests/run_tests.py builds ArmPoseClient.luau on tests/runtime/ClientRuntime.luau's few Roblox
-- pieces) poses the people in workspace.Npcs from their attributes; server/MoveHelper.luau's boardIn / boardOut put a
-- player's boarding attributes on his body (BoardAt + BoardReach getting in, AlightAt + AlightReach getting out). Here:
--   * standing, nothing on his arms (the animation's own);
--   * BoardAt and BoardReach: his right arm reaches for the handle as a player's does (the "reach" shape laid on the
--     shoulder, elbow and wrist by shared/Boarding.luau's curve: up over BoardStepSeconds, held, let go), his left arm
--     left alone; the reach over, his arm given back (released);
--   * a doorless seat (BoardReach false): no reach;
--   * AlightAt and AlightReach: the quick push on the door; the attributes gone, nothing more.
local E = require("./ClientRuntime")
local ArmPose = require("./ArmPoseClient")
local Boarding = require("./Boarding")
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

local CF = E.CFrame
local V3 = E.Vector3.new
local CARGO = Config.Cargo
-- ArmPose's "reach" (its SWINGS.reach, a player's hand to the handle): the right shoulder, elbow and wrist
local REACH = {
	rs = CF.Angles(0, math.rad(-12), 0) * CF.Angles(math.rad(68), 0, 0),
	re = CF.Angles(math.rad(24), 0, 0),
	rw = CF.Angles(math.rad(-18), 0, 0),
}
local npcs = E.new("Folder", "Npcs", E.workspace)
local danny = E.body("Danny", V3(0, 3, -4))
danny:SetParent(npcs)
local function joint(part: string, name: string): any
	return danny:FindFirstChild(part):FindFirstChild(name)
end
local rs, re, rw = joint("RightUpperArm", "RightShoulder"), joint("RightLowerArm", "RightElbow"), joint("RightHand", "RightWrist")
local ls = joint("LeftUpperArm", "LeftShoulder")
ArmPose.start()
local FRAME = 1 / 60
local function frame()
	E.clock += FRAME
	E.now += FRAME
	E.step(FRAME)
end
local function near(a: any, b: any): boolean -- (a joint's frame as written, or nil: none)
	return (a == nil and b == nil) or (a ~= nil and b ~= nil and a == b)
end
local function blended(shape: any, t: number): any
	return CF.identity:Lerp(shape, t)
end

for _ = 1, 30 do
	frame()
end
check("standing: nothing on his arms (the animation's own)", next(E.writes) == nil)

-- getting in (boardIn): BoardAt now, BoardReach (a cab door with a panel)
danny:SetAttribute("BoardAt", E.now)
danny:SetAttribute("BoardReach", true)
local start = E.clock + FRAME -- (played from the frame it is first seen, as a swing)
local peak, worst, left = 0, 0, false
while E.clock - start < CARGO.BoardSeconds do
	frame()
	local t = Boarding.reach(E.clock - start, false)
	if t > 0 then
		peak = math.max(peak, t)
		local ok = near(E.writes[rs], blended(REACH.rs, t)) and near(E.writes[re], blended(REACH.re, t)) and near(E.writes[rw], blended(REACH.rw, t))
		worst = if ok then worst else worst + 1
	end
	left = left or E.writes[ls] ~= nil
end
check("8.5.1 getting in (BoardAt, BoardReach on his body): his right arm reaches for the handle as a player's (the reach shape by shared/Boarding.luau's curve, every frame)",
	peak == 1 and worst == 0, `{peak} {worst}`)
check("…full as he stands at the handle (BoardStepSeconds in), his left arm left alone", Boarding.reach(CARGO.BoardStepSeconds + 0.05, false) == 1 and not left)
local released = E.released
danny:SetAttribute("BoardAt", nil) -- (seated: server/MoveHelper.luau's boardEnd)
danny:SetAttribute("BoardReach", nil)
frame()
frame()
check("…the reach over (he sits, the attributes gone): his arm given back to the animation", next(E.writes) == nil and E.released >= released)

-- a doorless seat: no handle to reach for
danny:SetAttribute("BoardAt", E.now)
danny:SetAttribute("BoardReach", false)
for _ = 1, 15 do
	frame()
end
check("a doorless seat (BoardReach false): no reach", next(E.writes) == nil)
danny:SetAttribute("BoardAt", nil)
danny:SetAttribute("BoardReach", nil)
frame()

-- getting out (boardOut): AlightAt now, AlightReach: the quick push on the door
danny:SetAttribute("AlightAt", E.now)
danny:SetAttribute("AlightReach", true)
start = E.clock + FRAME
peak, worst = 0, 0
while E.clock - start < CARGO.AlightSeconds do
	frame()
	local t = Boarding.reach(E.clock - start, true)
	if t > 0 then
		peak = math.max(peak, t)
		worst = if near(E.writes[rs], blended(REACH.rs, t)) then worst else worst + 1
	end
end
check("8.5.1 getting out (AlightAt, AlightReach): his hand pushes the door, a player's quick push", peak > 0.6 and worst == 0, `{peak} {worst}`)
danny:SetAttribute("AlightAt", nil)
danny:SetAttribute("AlightReach", nil)
for _ = 1, 30 do
	frame()
end
check("…then nothing more on his arms", next(E.writes) == nil)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
