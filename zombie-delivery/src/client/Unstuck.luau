--!strict
-- 6.0.1: a safety net for your own courier ending up sunk in the ground (the owner saw it after a delivery; the cause
-- is still being looked for). Twice a second: when a foot's middle sits INSIDE a solid, anchored world part (never so
-- when you stand on it: the feet rest on its top) two checks in a row, the body is lifted onto that part's top. Not
-- while seated, climbing, swimming, flying, platform-standing (zip lines, the interaction moves) or dead. Every lift
-- warns in the Output with what was going on, so the real cause can be found.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Joints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Joints"))

local Unstuck = {}

local CHECK = 0.5
local MAX_LIFT = 8 -- studs: deeper than this is not "sunk", leave it to the respawn

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

-- The top of the solid world part a point is inside, or nil.
local function solidAround(point: Vector3, character: Model): (number?, BasePart?)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { character }
	for _, name in { "Cars", "Zombies", "Npcs", "Traffic", "Animals", "Loot", "Buses" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(skip, folder)
		end
	end
	params.FilterDescendantsInstances = skip
	local best: number?, part: BasePart? = nil, nil
	for _, hit in workspace:GetPartBoundsInBox(CFrame.new(point), Vector3.new(0.2, 0.2, 0.2), params) do
		if hit.Anchored and hit.CanCollide and hit.Transparency < 1 then
			local top = hit.Position.Y + hit.Size.Y / 2
			if top > point.Y and (best == nil or top > best) then
				best, part = top, hit
			end
		end
	end
	return best, part
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
	if lift <= 0.3 or lift > MAX_LIFT then
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

function Unstuck.start()
	if started then
		return
	end
	started = true
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
