--!strict
-- 4.5, the admin's movement tools for the local character. Each works only while the server set its player attribute
-- (server/Admin.luau sets them for admins and the players they target; a client cannot set a replicated attribute):
--   AdminFly     fly: WASD (a gamepad's or a touch screen's stick) where the camera looks, Space up, Ctrl down, Shift
--                faster. A LinearVelocity and an AlignOrientation on the HumanoidRootPart, the Humanoid platform-stands;
--                a car seat ends the flight (it comes back when you get out).
--   AdminNoclip  the character's parts do not collide (through walls; the Humanoid still stands on the floor).
--   AdminJump    super jump (JumpPower × JUMP_POWER, JumpHeight × JUMP_HEIGHT; back to the character's own values).
-- The walk multiplier (AdminSpeed) is in client/CameraRig.luau, the car boost (AdminCarBoost) in client/Drive.luau.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AdminFly = {}

local player = Players.LocalPlayer

local FLY_SPEED = 70 -- studs per second
local FLY_FAST = 3 -- × with Shift
local JUMP_POWER = 2.5
local JUMP_HEIGHT = 6.25 -- (the height grows with the square of the power)

type Flight = { humanoid: Humanoid, attachment: Attachment, mover: LinearVelocity, align: AlignOrientation }
local flight: Flight? = nil

local function typing(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function held(...: Enum.KeyCode): boolean
	if typing() then
		return false
	end
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function land()
	local current = flight
	if not current then
		return
	end
	flight = nil
	current.mover:Destroy()
	current.align:Destroy()
	current.attachment:Destroy()
	if current.humanoid.Parent then
		current.humanoid.PlatformStand = false
		if current.humanoid.Health > 0 and current.humanoid.SeatPart == nil then
			current.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
end

local function takeOff(humanoid: Humanoid, root: BasePart): Flight
	local attachment = Instance.new("Attachment")
	attachment.Name = "AdminFly"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "AdminFly"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = math.huge
	mover.VectorVelocity = Vector3.zero
	mover.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "AdminFly"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 40
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	humanoid.PlatformStand = true
	return { humanoid = humanoid, attachment = attachment, mover = mover, align = align }
end

-- Every frame (after the camera): fly while the attribute is on, on foot and alive.
local function fly()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local want = player:GetAttribute("AdminFly") == true
		and humanoid ~= nil
		and humanoid.Health > 0
		and humanoid.SeatPart == nil
		and root ~= nil
		and root:IsA("BasePart")
	local current = flight
	if current and (not want or current.humanoid ~= humanoid or not current.mover.Parent) then
		land()
		current = nil
	end
	if not want or not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	if not current then
		current = takeOff(humanoid, root)
		flight = current
	end
	local active = current :: Flight
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatRight = Vector3.new(right.X, 0, right.Z)
	if flatLook.Magnitude < 1e-3 then
		flatLook = Vector3.new(0, 0, -1)
	end
	flatLook = flatLook.Unit
	flatRight = if flatRight.Magnitude > 1e-3 then flatRight.Unit else Vector3.new(1, 0, 0)
	-- The keys, else the stick (touch / gamepad: the Humanoid's MoveDirection, already turned with the camera).
	local forward = (if held(Enum.KeyCode.W, Enum.KeyCode.Up) then 1 else 0) - (if held(Enum.KeyCode.S, Enum.KeyCode.Down) then 1 else 0)
	local side = (if held(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0) - (if held(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0)
	if forward == 0 and side == 0 then
		local stick = humanoid.MoveDirection
		forward = stick:Dot(flatLook)
		side = stick:Dot(flatRight)
	end
	local up = (if held(Enum.KeyCode.Space) or (humanoid.Jump and not typing()) then 1 else 0)
		- (if held(Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl) then 1 else 0)
	local move = look * forward + flatRight * side + Vector3.new(0, up, 0)
	if move.Magnitude > 1 then
		move = move.Unit
	end
	local fast = held(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
	active.mover.VectorVelocity = move * FLY_SPEED * (if fast then FLY_FAST else 1)
	active.align.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
end

-- ── Noclip ─────────────────────────────────────────────────────────────────

local clipped: { [BasePart]: boolean } = {} -- the parts this turned off (to turn them on again)
local parts: { BasePart } = {}
local partsOf: Model? = nil
local partsConnection: RBXScriptConnection? = nil

local function collectParts(character: Model)
	if partsConnection then
		partsConnection:Disconnect()
		partsConnection = nil
	end
	table.clear(parts)
	table.clear(clipped)
	partsOf = character
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	-- (a tool or an accessory added later)
	partsConnection = character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end)
end

local function unclip()
	for part in clipped do
		if part.Parent then
			part.CanCollide = true
		end
	end
	table.clear(clipped)
end

-- Before every physics step (the Humanoid turns the torso's collision on again each step).
local function noclip()
	local character = player.Character
	if player:GetAttribute("AdminNoclip") ~= true or not character then
		if next(clipped) then
			unclip()
		end
		return
	end
	if character ~= partsOf then
		collectParts(character)
	end
	for _, part in parts do
		if part.CanCollide and part.Parent then
			clipped[part] = true
			part.CanCollide = false
		end
	end
end

-- ── Super jump ─────────────────────────────────────────────────────────────

local jumpBase: { [Humanoid]: { power: number, height: number } } = {}

local function applyJump()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local base = jumpBase[humanoid]
	if not base then
		table.clear(jumpBase) -- (only the current character's)
		base = { power = humanoid.JumpPower, height = humanoid.JumpHeight }
		jumpBase[humanoid] = base
	end
	local on = player:GetAttribute("AdminJump") == true
	humanoid.JumpPower = base.power * (if on then JUMP_POWER else 1)
	humanoid.JumpHeight = base.height * (if on then JUMP_HEIGHT else 1)
end

function AdminFly.start()
	RunService:BindToRenderStep("ZombieDeliveryAdminFly", Enum.RenderPriority.Camera.Value + 5, fly)
	RunService.Stepped:Connect(noclip)
	player:GetAttributeChangedSignal("AdminJump"):Connect(applyJump)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Humanoid", 10)
		applyJump()
	end)
	if player.Character then
		applyJump()
	end
end

-- Is the local character flying right now (the attribute on and the flight running)?
function AdminFly.flying(): boolean
	return flight ~= nil
end

return AdminFly
