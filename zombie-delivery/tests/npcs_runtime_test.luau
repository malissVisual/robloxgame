-- 8.3 (the owner: "he just jumps weirdly … I don't know how to make him walk like me and walk backwards"): the real
-- server/Npcs.luau (tests/run_tests.py builds NpcsServer.luau on tests/runtime/NpcsRuntime.luau's environment: a classic
-- R15 body on the item recorder, its Humanoid's states and its Animator's tracks kept) with the real
-- shared/MoveHelperBrain.luau. Danny's body while he holds the far end of your piece (Npcs.carried, Npcs.stride):
--   * carried: the Physics state (the clients' gait poses his legs from his velocity like a player's; 7.x's
--     PlatformStand made it let go), no jump (Jump off, the Jumping state off), AutoRotate off, the root free and the
--     server's; never PlatformStand, so never GettingUp's spring up when he lets go (GettingUp off too)
--   * let go: Running at once, AutoRotate and the Jumping state as they were (8.1: AutoRotate restored), anchored, idle
--   * his legs (the far bodies' walk): his root driven forwards, backwards, sideways, standing: MoveHelperBrain.holdLegs
--     then Npcs.stride each step: the walk track forwards or played in reverse, at his speed / the walk's stride
--   * a walk with jump = false (Danny's) turns the Jumping state off; another person's (a buddy's: they jump) keeps it
local R = require("./NpcsRuntime")
local Npcs = require("./NpcsServer")
local Brain = require("./MoveHelperBrain")
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

local M = R.Mock
local V3 = M.Vector3.new
local H = Config.MoveHelper
local WALK_ID, IDLE_ID = "rbxassetid://507777826", "rbxassetid://507766388"
local STRIDE = 12.8 -- (server/Npcs.luau's: studs a second of a full-size body at the walk's own speed)

local function lastState(humanoid: any): string?
	for index = #R.states, 1, -1 do
		if R.states[index].humanoid == humanoid then
			return R.states[index].state
		end
	end
	return nil
end
local function platformed(humanoid: any): boolean
	for _, p in R.platform do
		if p.humanoid == humanoid and p.value == true then
			return true
		end
	end
	return false
end

-- Danny ---------------------------------------------------------------------------------------------------------------------------

local danny = Npcs.spawn(Npcs.look("mover", "Danny", "ZDC Moving"), M.CFrame.new(0, 0, 0))
local humanoid = danny:FindFirstChildOfClass("Humanoid")
local root = danny.PrimaryPart
local tracks = R.tracks(danny)
local walk, idle = tracks[WALK_ID], tracks[IDLE_ID]
check("a person: an R15 body, anchored, idle, the stock walk loaded", humanoid ~= nil and root.Anchored == true and walk ~= nil and idle ~= nil and idle.IsPlaying)
check("…the Jumping and GettingUp states on as any person's (a buddy jumps over things)", humanoid:GetStateEnabled("Jumping") and humanoid:GetStateEnabled("GettingUp")
	and humanoid.AutoRotate == true)

-- a buddy (server/Buddy.luau: his paths jump) walks: his Jumping state stays
local buddy = Npcs.spawn(Npcs.look("courier", "Ace"), M.CFrame.new(20, 0, 0))
local buddyHumanoid = buddy:FindFirstChildOfClass("Humanoid")
Npcs.walkTo(buddy, V3(40, 0, 0), nil, 8, { through = true, near = 1 })
check("8.3 another person's walk keeps the Jumping state (only `jump = false` turns it off)", buddyHumanoid:GetStateEnabled("Jumping") and buddy.PrimaryPart.Anchored == false)

-- Danny's walk (server/MoveHelper.luau's WALK: jump = false)
humanoid.Jump = true
Npcs.walkTo(danny, V3(-30, 0, 0), nil, 8, { through = true, near = 0.6, jump = false })
check("8.3 Danny's walk (jump = false): no jump (Jump cleared, the Jumping state off), the root free and the server's", humanoid.Jump == false
	and not humanoid:GetStateEnabled("Jumping") and root.Anchored == false and root.NetworkOwner == false and walk.IsPlaying)
check("…a buddy's Jumping state untouched by it", buddyHumanoid:GetStateEnabled("Jumping"))

-- He takes the far end of your piece -----------------------------------------------------------------------------------------------

local jumpingBefore = humanoid:GetStateEnabled("Jumping")
humanoid.Jump = true
Npcs.carried(danny, true)
check("8.3 carried: the Physics state (no forces of his own; the clients' gait poses his legs: PlatformStand made it let go)",
	lastState(humanoid) == "Physics" and humanoid:GetState() == "Physics" and humanoid.PlatformStand ~= true and not platformed(humanoid), lastState(humanoid))
check("…no jump (Jump off, the Jumping state off), AutoRotate off (his constraints turn him), the root free and the server's", humanoid.Jump == false
	and not humanoid:GetStateEnabled("Jumping") and humanoid.AutoRotate == false and root.Anchored == false and root.NetworkOwner == false)
check("…GettingUp off (no spring up when he lets go)", not humanoid:GetStateEnabled("GettingUp"))

-- His legs: his root driven along a way (he faces +X): forwards, backwards, sideways, standing; each step MoveHelper's
-- look (MoveHelperBrain.holdLegs on his root's velocity in his frame) and Npcs.stride
local trail = Brain.newTrail()
local at = V3(0, 3, 0)
local steps: { { v: any, want: number, name: string } } = {
	{ v = V3(4.9, 0, 0), want = 4.9, name = "forwards at the pair's walk turning (4.9)" },
	{ v = V3(-9.8, 0, 0), want = -9.8, name = "backwards at the pair's walk (9.8: you walk toward him)" },
	{ v = V3(0, 0, -5), want = -5, name = "sideways (the way they went: backwards)" },
	{ v = V3(0.2, 0, 0), want = 0, name = "standing" },
}
for _, s in steps do
	local worst, wrongWay = 0, 0
	for _ = 1, 4 do
		local before = at
		at += s.v * 0.1
		root.CFrame = M.CFrame.lookAt(at, at + V3(1, 0, 0))
		local look = root.CFrame.LookVector
		local vx, vz = (at.X - before.X) / 0.1, (at.Z - before.Z) / 0.1
		local speed = Brain.holdLegs(trail, vx * look.X + vz * look.Z, vz * look.X - vx * look.Z, 0.1)
		Npcs.stride(danny, speed)
		if s.want == 0 then
			worst = math.max(worst, if walk.IsPlaying then 1 else 0, if idle.IsPlaying then 0 else 1)
		else
			worst = math.max(worst, math.abs(walk.Speed - s.want / STRIDE), if walk.IsPlaying then 0 else 1)
			if (walk.Speed < 0) ~= (s.want < 0) then
				wrongWay += 1
			end
		end
	end
	local what = if s.want == 0 then "the walk stopped, the idle on" else `the walk at {s.want} / {STRIDE} (negative: played in reverse)`
	check(`8.3 his legs, his root driven {s.name}: every step {what}`, worst < 1e-6 and wrongWay == 0, `{worst} off, {wrongWay} the wrong way`)
end
check("…the slow pair walk turning (Pair × PairTurnWalk) steps", Config.Moving.Speed.Pair * Config.Movement.Walk * H.PairTurnWalk > H.HoldLegs.From)

-- He lets go ---------------------------------------------------------------------------------------------------------------------------

Npcs.carried(danny, false)
check("8.3 let go: Running at once (never GettingUp: no spring up, no hop on his first steps), anchored where he is, idle",
	lastState(humanoid) == "Running" and root.Anchored == true and idle.IsPlaying and not walk.IsPlaying and not platformed(humanoid), lastState(humanoid))
check("…AutoRotate given back (8.1), the Jumping state as it was, Jump off", humanoid.AutoRotate == true and humanoid:GetStateEnabled("Jumping") == jumpingBefore
	and humanoid.Jump == false)

-- a person carried who never walked with jump = false: Jumping given back on
local other = Npcs.spawn(Npcs.look("mover", "Ben"), M.CFrame.new(-20, 0, 0))
local otherHumanoid = other:FindFirstChildOfClass("Humanoid")
Npcs.carried(other, true)
local off = not otherHumanoid:GetStateEnabled("Jumping")
Npcs.carried(other, false)
check("8.3 …and a person who could jump before: off while carried, on again after", off and otherHumanoid:GetStateEnabled("Jumping") and otherHumanoid.AutoRotate == true)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
