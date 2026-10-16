-- 8.3 (the owner: "he just jumps weirdly"): the real client/PairSteer.luau, the leader's side of carrying in two
-- (tests/run_tests.py builds PairSteerClient.luau: a function of its globals), on the item recorder's body: while your
-- character carries a piece in two (PairTurn) no jump (Humanoid.Jump cleared every step before the physics: a jump
-- lifted the piece and Danny with it), AutoRotate off and the heading PairTurn degrees a second at most (8.1); let go,
-- AutoRotate back on (8.1) and your jumps your own again (nothing switched off: a bus ride's own jump lock untouched).
-- 8.3 (the owner: "when I run, he just goes behind me with his arms stretched out"): nobody runs with a move's piece:
-- its walk held at the server's CarrySpeed (× the admin's boost) every step before the physics whatever wrote
-- Humanoid.WalkSpeed (a sprint's 28, client/CameraRig.luau's bleed-off); in two (CarryPair: the leader and the far end's
-- crew mate) the run key says Config.MoveHelper.RunHint once a carry; let go, your walk is yours again.
local E = require("./MovingRuntime") -- (the recorder with a CFrame's LookVector)
local PairCarry = require("./PairCarry")
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

local M = E.Mock
local V3 = M.Vector3.new

-- your character: a root facing -Z, a humanoid walking
local character = M.Instance.new("Model")
character.Name = "You"
local root = M.Instance.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = M.CFrame.new(0, 3, 0)
root.Parent = character
local humanoid = M.Instance.new("Humanoid")
humanoid.Name = "Humanoid"
humanoid.AutoRotate = true
humanoid.Jump = false
humanoid.MoveDirection = V3(0, 0, 0)
humanoid.SeatPart = nil
humanoid.Health = 100
humanoid.Parent = character
local moved: any = nil -- 9.0 the last Humanoid:Move this module made (this physics step's walk)
humanoid.Move = function(self: any, direction: any, _relative: boolean)
	moved = direction
	self.MoveDirection = direction
end
local playerAttributes: { [string]: any } = {}
local localPlayer = { Character = character, GetAttribute = function(_: any, name: string): any
	return playerAttributes[name]
end }
-- 9.0 the far end's holder: Danny's body in workspace.Npcs (its MoveHelper attribute his id), a crew mate's character
local npcs = M.Instance.new("Folder")
npcs.Name = "Npcs"
local dannyBody = M.Instance.new("Model")
dannyBody.Name = "Danny"
dannyBody:SetAttribute("MoveHelper", -7)
local dannyRoot = M.Instance.new("Part")
dannyRoot.Name = "HumanoidRootPart"
dannyRoot.CFrame = M.CFrame.new(0, 3, -9)
dannyRoot.Parent = dannyBody
dannyBody.Parent = npcs
local fakeWorkspace = { FindFirstChild = function(_: any, name: string): any
	return if name == "Npcs" then npcs else nil
end }
local game = { GetService = function(_: any, name: string): any
	if name == "Players" then
		return { LocalPlayer = localPlayer, GetPlayerByUserId = function(_: any, _id: number): any
			return nil -- (Danny's id is no player's)
		end }
	elseif name == "RunService" then
		return { PreSimulation = { Connect = function() end } }
	end
	return { WaitForChild = function(self: any, child: string): any
		return { Name = child, WaitForChild = self.WaitForChild }
	end }
end }
local PairSteer = require("./PairSteerClient")(game, function(module: any): any
	return require(`./{module.Name}`)
end, M.CFrame, M.typeof, M.Vector3, fakeWorkspace)

local function heading(): number
	local look = root.CFrame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end

-- carrying alone: your jumps are yours
humanoid.Jump = true
PairSteer.step(1 / 60)
check("carrying nothing in two: a jump is yours, AutoRotate on", humanoid.Jump == true and humanoid.AutoRotate == true and not PairSteer.steering())

-- carrying in two (Danny at the far end: PairTurn)
character:SetAttribute("PairTurn", Config.MoveHelper.PairTurn)
humanoid.Jump = true -- (Space, the touch jump button)
PairSteer.step(1 / 60)
check("8.3 carrying in two: no jump (Humanoid.Jump cleared before the physics step), AutoRotate off", humanoid.Jump == false and humanoid.AutoRotate == false
	and PairSteer.steering())
local most = 0
for _ = 1, 30 do
	humanoid.Jump = true -- (Space held: asked again every frame)
	humanoid.MoveDirection = V3(1, 0, 0) -- (the way to your right)
	local before = heading()
	PairSteer.step(0.1)
	most = math.max(most, math.abs(PairCarry.wrap(heading() - before)))
	if humanoid.Jump then
		break
	end
end
check("8.3 …Space held while walking and turning: never a jump", humanoid.Jump == false)
check("8.1 …the heading turns PairTurn degrees a second at most", most > 0 and most <= math.rad(Config.MoveHelper.PairTurn) * 0.1 + 1e-9, math.deg(most) * 10)

-- let go: AutoRotate back, jumps yours again
character:SetAttribute("PairTurn", nil)
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(1 / 60)
humanoid.Jump = true
PairSteer.step(1 / 60)
check("8.1 let go: AutoRotate on again; 8.3 your jump yours again (nothing was switched off)", humanoid.AutoRotate == true and humanoid.Jump == true
	and not PairSteer.steering() and PairSteer.walk() == 1)

-- 8.3 nobody runs with a move's piece --------------------------------------------------------------------------------------

local hints: { string } = {}
PairSteer.notify = function(text: string)
	table.insert(hints, text)
end
humanoid.WalkSpeed = 28
character:SetAttribute("MoveCarry", 3) -- (a move's piece in your hands alone: the server's CarrySpeed)
character:SetAttribute("CarrySpeed", 10.5)
PairSteer.step(1 / 60)
check("8.3 a move's piece in your hands: the walk held at its CarrySpeed before the physics (a sprint's 28 cut to 10.5)",
	humanoid.WalkSpeed == 10.5 and PairSteer.cap() == 10.5 and not PairSteer.holding(), humanoid.WalkSpeed)
humanoid.WalkSpeed = 6
PairSteer.step(1 / 60)
PairSteer.refuseRun()
check("…a slower walk (a turn, a stagger) left as it is; alone, the run key says nothing", humanoid.WalkSpeed == 6 and #hints == 0)
-- the leader of a piece carried in two (Danny or a crew mate at its far end): Shift held, the sprint asked every frame
character:SetAttribute("PairTurn", Config.MoveHelper.PairTurn)
character:SetAttribute("CarryPair", true)
local fastest = 0
for _ = 1, 120 do
	humanoid.WalkSpeed = 28 -- (the sprint's speed, written before every physics step: Shift, the stick click, a script)
	humanoid.MoveDirection = V3(0, 0, -1)
	PairSteer.step(1 / 60)
	fastest = math.max(fastest, humanoid.WalkSpeed)
end
check("8.3 the leader sprints while carrying in two: the walk stays at CarrySpeed every step (2 s of Shift)", fastest == 10.5 and PairSteer.holding(), fastest)
PairSteer.refuseRun()
PairSteer.refuseRun()
PairSteer.refuseRun()
check(`…the run key says "{Config.MoveHelper.RunHint}" once a carry`, #hints == 1 and hints[1] == Config.MoveHelper.RunHint
	and Config.MoveHelper.RunHint == "Too heavy to run with", #hints)
playerAttributes.AdminSpeed = 2 -- (the admin's walk × 2: the carry's too, the server's walkOf the same)
humanoid.WalkSpeed = 50
PairSteer.step(1 / 60)
check("…an admin's walk × 2: held at CarrySpeed × 2", humanoid.WalkSpeed == 21 and PairSteer.cap() == 21, humanoid.WalkSpeed)
playerAttributes.AdminSpeed = nil
-- let go: your walk is yours again, and the next carry in two says it again
for _, name in { "MoveCarry", "CarrySpeed", "PairTurn", "CarryPair" } do
	character:SetAttribute(name, nil)
end
humanoid.MoveDirection = V3(0, 0, 0)
humanoid.WalkSpeed = 28
PairSteer.step(1 / 60)
PairSteer.refuseRun()
check("8.3 let go: the sprint yours again (nothing held), no hint", humanoid.WalkSpeed == 28 and PairSteer.cap() == nil and #hints == 1)
-- the far end's crew mate (CarryPair, no PairTurn: the server holds their body; their walk held too)
character:SetAttribute("MoveCarry", 3)
character:SetAttribute("CarrySpeed", 9.8)
character:SetAttribute("CarryPair", true)
humanoid.AutoRotate = true
PairSteer.step(1 / 60)
PairSteer.refuseRun()
PairSteer.refuseRun()
check("8.3 a crew mate at the far end: the same rule (walk held at CarrySpeed, the hint once this carry), their body not steered",
	humanoid.WalkSpeed == 9.8 and #hints == 2 and humanoid.AutoRotate == true and not PairSteer.steering() and PairSteer.holding(), humanoid.WalkSpeed)
for _, name in { "MoveCarry", "CarrySpeed", "CarryPair" } do
	character:SetAttribute(name, nil)
end
PairSteer.step(1 / 60)

-- 9.0 (the owner, 8.9.3: "When I want to walk forwards, Danny can't walk backwards"; his screenshot of Danny inside the
-- Sofa): your screen shows your partner late (the server holds him), the piece in your hands at once ------------------------

local K = Config.MoveHelper.PairKeep
character:SetAttribute("PairTurn", Config.MoveHelper.PairTurn)
root.CFrame = M.CFrame.new(0, 3, 0) -- (facing -Z: Danny ahead of you across the piece)
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(1 / 60)
local eased: { number } = {}
for _ = 1, 8 do
	humanoid.MoveDirection = V3(0, 0, -1) -- (forwards, toward him)
	PairSteer.step(0.1)
	table.insert(eased, PairSteer.walk())
end
check("9.0 standing, then forwards: the walk eases in over PairStart s (never at once from standing)", eased[1] < 0.3 and eased[3] > eased[1]
	and eased[3] < 1 and eased[8] == 1, table.concat(eased, ", "))
-- Danny's place in your root's frame (PairFar) and who he is (PairWith: his id, his body in workspace.Npcs)
character:SetAttribute("PairWith", -7)
character:SetAttribute("PairFar", V3(0, 0, -9))
moved = nil
humanoid.MoveDirection = V3(0, 0, -1)
PairSteer.step(0.1)
check("9.0 your screen shows him at his place: your walk toward him as it is", moved == nil and PairSteer.walk() == 1)
dannyRoot.CFrame = M.CFrame.new(0, 3, -9 + K.Stop + 0.2) -- (shown nearer than his place: the piece into him on your screen)
humanoid.MoveDirection = V3(0, 0, -1)
PairSteer.step(0.1)
check("9.0 …shown PairKeep.Stop studs nearer or more: your walk toward him goes (never the piece pushed into him on your screen)",
	moved ~= nil and math.abs(moved.Z) < 1e-6, moved and moved.Z)
moved = nil
humanoid.MoveDirection = V3(1, 0, 0)
PairSteer.step(0.1)
local sideways = moved == nil
moved = nil
humanoid.MoveDirection = V3(0, 0, 1)
PairSteer.step(0.1)
check("9.0 …sideways or backwards (away from him): your walk as it is", sideways and moved == nil)
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(0.1)
dannyRoot.CFrame = M.CFrame.new(0, 3, -9 + (K.Wait + K.From) / 2) -- (a little nearer: not yet into him)
local held: { number } = {}
for _ = 1, 4 do
	moved = nil
	humanoid.MoveDirection = V3(0, 0, -1)
	PairSteer.step(0.1)
	table.insert(held, PairSteer.walk())
end
check("9.0 …shown a little nearer from standing: the start waits for him (the walk held, not slowed), your walk untouched",
	held[1] > 0 and held[4] == held[1] and moved == nil, table.concat(held, ", "))
dannyRoot.CFrame = M.CFrame.new(0, 3, -9)
-- his end against a wall of the house (the server's PairWall: the way into it × the share to take away)
character:SetAttribute("PairWall", V3(0, 0, -1))
moved = nil
humanoid.MoveDirection = V3(0, 0, -1)
PairSteer.step(0.1)
local stopped = moved ~= nil and math.abs(moved.Z) < 1e-6
character:SetAttribute("PairWall", V3(0, 0, -0.5))
moved = nil
humanoid.MoveDirection = V3(0.6, 0, -0.8)
PairSteer.step(0.1)
check("9.0 his end against a wall (PairWall): your walk into it goes (all of it at a full share, half at half), along it as ever",
	stopped and moved ~= nil and math.abs(moved.Z + 0.4) < 1e-6 and math.abs(moved.X - 0.6) < 1e-6, moved and `{moved.X} {moved.Z}`)
for _, name in { "PairTurn", "PairWith", "PairFar", "PairWall" } do
	character:SetAttribute(name, nil)
end
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(1 / 60)
check("9.0 let go: your walk yours again", PairSteer.walk() == 1 and not PairSteer.steering())

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
