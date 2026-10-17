-- 10.6: the people's arms (Danny, the helpers): the real client/ArmPose.luau (tests/run_tests.py builds
-- ArmPoseClient.luau on tests/runtime/ClientRuntime.luau's few Roblox pieces) poses the people in workspace.Npcs from
-- their attributes. Here:
--   * standing, nothing on his arms (the animation's own);
--   * a move's piece in his arms (Carrying, no CarryAt: the fixed shape of its kind): both arms forward under it,
--     blended in, full after CARRY_IN; put down, blended out and both arms given back (released);
--   * 8.5 the clipboard (ClipboardHeld): the right arm holds it up, the left arm left alone; put away, given back;
--   * nothing else on him (no aim, no boarding reach: nobody drives since 10.0) leaves anything on his arms.
local E = require("./ClientRuntime")
local ArmPose = require("./ArmPoseClient")

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
-- ArmPose's carry shape of furniture (its CARRY_SHAPES.furniture: the shoulders 40° forward, 4° in, the elbows 52°)
local FURNITURE = {
	rs = CF.Angles(0, math.rad(4), 0) * CF.Angles(math.rad(40), 0, 0),
	re = CF.Angles(math.rad(52), 0, 0),
	ls = CF.Angles(0, -math.rad(4), 0) * CF.Angles(math.rad(40), 0, 0),
	le = CF.Angles(math.rad(52), 0, 0),
}
local npcs = E.new("Folder", "Npcs", E.workspace)
local danny = E.body("Danny", V3(0, 3, -4))
danny:SetParent(npcs)
local function joint(part: string, name: string): any
	return danny:FindFirstChild(part):FindFirstChild(name)
end
local rs, re, rw = joint("RightUpperArm", "RightShoulder"), joint("RightLowerArm", "RightElbow"), joint("RightHand", "RightWrist")
local ls, le = joint("LeftUpperArm", "LeftShoulder"), joint("LeftLowerArm", "LeftElbow")
ArmPose.start()
local FRAME = 1 / 60
local function frame(n: number?)
	for _ = 1, n or 1 do
		E.clock += FRAME
		E.now += FRAME
		E.step(FRAME)
	end
end
local function full(shape: any): any
	return CF.identity:Lerp(shape, 1)
end

frame(30)
check("standing: nothing on his arms (the animation's own)", next(E.writes) == nil)

-- a move's piece in his arms (server/Moving.luau's Carrying on his body; no CarryAt: the fixed shape)
danny:SetAttribute("Carrying", "furniture")
frame(3)
local partly = E.writes[rs] ~= nil and E.writes[ls] ~= nil and E.writes[rs] ~= full(FURNITURE.rs)
frame(30)
check("a piece in his arms: both arms blend into the carry (both shoulders and elbows, not at once)", partly)
check("…full after CARRY_IN: the furniture's shape on both arms", E.writes[rs] == full(FURNITURE.rs) and E.writes[re] == full(FURNITURE.re)
	and E.writes[ls] == full(FURNITURE.ls) and E.writes[le] == full(FURNITURE.le))
check("ArmPose has his arms then (client/BodyLife.luau steps aside)", ArmPose.armsBusy(danny))
local released = E.released
danny:SetAttribute("Carrying", nil)
frame(40)
check("put down: blended out, his arms given back to the animation", next(E.writes) == nil and E.released > released and not ArmPose.armsBusy(danny))

-- 8.5 Danny's clipboard (ClipboardHeld)
danny:SetAttribute("ClipboardHeld", true)
frame(30)
check("8.5 the clipboard: his right arm holds it up (shoulder, elbow, wrist), the left arm left alone", E.writes[rs] ~= nil and E.writes[re] ~= nil
	and E.writes[rw] ~= nil and E.writes[ls] == nil and E.writes[le] == nil)
danny:SetAttribute("ClipboardHeld", nil)
frame(40)
check("…put away: given back", next(E.writes) == nil)

-- what the city set on bodies (an aim, a boarding reach) leaves nothing on his arms
danny:SetAttribute("Aiming", true)
danny:SetAttribute("BoardAt", E.now)
danny:SetAttribute("BoardReach", true)
frame(30)
check("no aim and no boarding reach any more: nothing on his arms", next(E.writes) == nil)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
