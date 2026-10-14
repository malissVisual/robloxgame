-- 8.3 (the owner: "he just jumps weirdly"): the real client/PairSteer.luau, the leader's side of carrying in two
-- (tests/run_tests.py builds PairSteerClient.luau: a function of its globals), on the item recorder's body: while your
-- character carries a piece in two (PairTurn) no jump (Humanoid.Jump cleared every step before the physics: a jump
-- lifted the piece and Danny with it), AutoRotate off and the heading PairTurn degrees a second at most (8.1); let go,
-- AutoRotate back on (8.1) and your jumps your own again (nothing switched off: a bus ride's own jump lock untouched).
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
local game = { GetService = function(_: any, name: string): any
	if name == "Players" then
		return { LocalPlayer = { Character = character } }
	elseif name == "RunService" then
		return { PreSimulation = { Connect = function() end } }
	end
	return { WaitForChild = function(self: any, child: string): any
		return { Name = child, WaitForChild = self.WaitForChild }
	end }
end }
local PairSteer = require("./PairSteerClient")(game, function(module: any): any
	return require(`./{module.Name}`)
end, M.CFrame)

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

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
