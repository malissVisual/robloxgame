--!strict
-- 6.0.1: a safety net for your own courier ending up sunk in the ground (the owner saw it after a delivery; the cause
-- is still being looked for). Twice a second: when a foot's middle sits INSIDE a solid, anchored world part (never so
-- when you stand on it: the feet rest on its top) two checks in a row, the body is lifted onto that part's top. Not
-- while seated, climbing, swimming, flying, platform-standing (zip lines, the interaction moves) or dead. Every lift
-- warns in the Output with what was going on, so the real cause can be found.
-- 6.13, the other safety net: a script error on this device goes to the server as its script's name and line only
-- (the ClientError remote; server/Analytics.luau counts it by script, Roblox's Error Report keeps the message). Each
-- place once a session, one report every 1 / Config.Robust.Limits.ClientError s at most (the server's limit: none of
-- them is dropped there); a place is marked only when its report went, so one that came during the wait goes later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Joints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Joints"))

local Unstuck = {}

local CHECK = 0.5
local MAX_LIFT = 5 -- studs: deeper than this is not "sunk", leave it to the respawn
-- 6.5.1: shallower than this is the body's own feet standing a little in the kerb (the courier's blocky feet reach
-- 0.4 below its hip height: Output showed "0.4 studs in Depot.Sidewalk … lifted out" every second, a jitter)
local MIN_LIFT = 1

local player = Players.LocalPlayer
local started = false
local strikes = 0

local SKIP: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Flying] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Jumping] = true,
}

-- 6.0.1 review: the real shape decides (a wedge ramp's or a turned prop's box is not its body): a small probe ball at
-- the foot asks the engine which parts it truly overlaps; the surface above the foot comes from a short ray down.
local probe: Part? = nil
local function probeAt(point: Vector3): Part
	local p = probe
	if not p or not p.Parent then
		local made = Instance.new("Part")
		made.Name = "UnstuckProbe"
		made.Shape = Enum.PartType.Ball
		made.Size = Vector3.new(0.3, 0.3, 0.3)
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.Transparency = 1
		made.Parent = workspace.CurrentCamera
		probe = made
		p = made
	end
	assert(p)
	p.CFrame = CFrame.new(point)
	return p
end

local function skipList(character: Model): { Instance }
	local skip: { Instance } = { character }
	for _, name in { "Cars", "Zombies", "Npcs", "Traffic", "Animals", "Loot", "Buses" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(skip, folder)
		end
	end
	return skip
end

-- The ground's surface over a foot that is truly inside a solid world part (within REACH above it), or nil.
local REACH = 3.5
local function solidAround(point: Vector3, character: Model): (number?, BasePart?)
	local skip = skipList(character)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	local inside: BasePart? = nil
	for _, hit in workspace:GetPartsInPart(probeAt(point), params) do
		if hit.Anchored and hit.CanCollide and hit.Transparency < 1 and hit.Name ~= "UnstuckProbe" then
			inside = hit
			break
		end
	end
	if not inside then
		return nil, nil
	end
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	rays.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(point + Vector3.new(0, REACH, 0), Vector3.new(0, -REACH, 0), rays)
	if not hit or hit.Position.Y <= point.Y + 0.2 then
		return nil, nil
	end
	return hit.Position.Y, inside
end

local function check()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart or humanoid.Sit or root.Anchored then
		strikes = 0
		return
	end
	local state = humanoid:GetState()
	if SKIP[state] then
		strikes = 0
		return
	end
	-- The body drawn sunk while the root stands right: a Root joint left pushed down (a pose that never let go).
	local rootJoint = Joints.find(character:FindFirstChild("LowerTorso"), "Root")
	if rootJoint and rootJoint.Transform.Position.Y < -0.8 then
		warn(`[Unstuck] the body hung {string.format("%.1f", -rootJoint.Transform.Position.Y)} studs low on its Root joint (state {state.Name}); set straight`)
		rootJoint.Transform = CFrame.identity
	end
	local top: number?, part: BasePart? = nil, nil
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = character:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local t, p = solidAround(foot.Position, character)
			if t and (top == nil or t > top) then
				top, part = t, p
			end
		end
	end
	if not top then
		strikes = 0
		return
	end
	strikes += 1
	if strikes < 2 then
		return
	end
	strikes = 0
	local stand = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else root.Size.Y / 2 + 2
	local lift = top + stand - root.Position.Y
	if lift <= MIN_LIFT or lift > MAX_LIFT then
		return
	end
	warn(
		`[Unstuck] your courier was {string.format("%.1f", lift)} studs in {if part then part:GetFullName() else "the ground"}`
			.. ` (state {state.Name}, AlightAt {tostring(character:GetAttribute("AlightAt"))}, BoardAt {tostring(character:GetAttribute("BoardAt"))},`
			.. ` Rental {tostring(player:GetAttribute("Rental"))}, Root joint offset {string.format("%.2f", root.Position.Y - (character:FindFirstChild("LowerTorso") and (character:FindFirstChild("LowerTorso") :: BasePart).Position.Y or root.Position.Y))}); lifted out`
	)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(character:GetPivot() + Vector3.new(0, lift, 0))
end

-- 6.13: the script errors on this device, counted by script on the server (see the top).
local function reportErrors()
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Plan = require(Shared:WaitForChild("AnalyticsPlan"))
	local Net = require(Shared:WaitForChild("Net"))
	-- (the server's own limit, one report every 1 / Limits.ClientError s, and a second more so none arrives early)
	local gap = 1 / require(Shared:WaitForChild("Config")).Robust.Limits.ClientError + 1
	local remote = Net.get("ClientError")
	local seen: { [string]: boolean } = {}
	local sentAt = -math.huge
	ScriptContext.Error:Connect(function(message: string, _trace: string, source: Instance?)
		pcall(function()
			local name, line = Plan.errorWhere(message, if source then source.Name else nil)
			local key = `{name}:{line}`
			local now = os.clock()
			-- a place is marked only when its report went: one that came during the wait goes when it happens again
			if seen[key] or now - sentAt < gap then
				return
			end
			seen[key] = true
			sentAt = now
			remote:FireServer(name, line)
		end)
	end)
end

function Unstuck.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ok, err = pcall(function()
			reportErrors()
		end)
		if not ok then
			warn(`[Unstuck] the error report could not start: {err}`)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK)
			local ok, err = pcall(function()
				check()
			end)
			if not ok then
				warn(`[Unstuck] {err}`)
				task.wait(5)
			end
		end
	end)
end

return Unstuck
