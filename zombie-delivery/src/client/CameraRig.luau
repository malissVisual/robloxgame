--!strict
-- The camera and the walk on a computer (a keyboard and a mouse): the camera behind you, the cursor free.
-- 9.0 (the owner: "aiming the way I have the crosshair now only when I want to shoot or have pistols; I want the mouse
-- normally available, so remove the Alt option"): the cursor shows and the mouse moves no camera; the right mouse held
-- turns it (LockCurrentPosition, like Roblox's own camera) while no window needs the mouse (CameraRig.mouseNeeded, set
-- by client/Main.client.luau); the wheel zooms; the left click is the world's (Danny, a piece, the grip check). A weapon
-- in the hands (CameraRig.armed: a Tool equipped, the run's bat) locks the mouse in the middle: the mouse moves the
-- camera and a dot in the middle shows what is under it (dim over nothing, white over a zombie).
-- 9.0.1 (the owner: "on the Mac you can't turn with the touchpad at all"): a two-finger swipe on a trackpad turns it
-- (UserInputService.PointerAction's pan, Config.CameraTurn.Pan) and a pinch zooms (its pinch); the arrow keys Left /
-- Right and , / . turn it at Config.CameraTurn.Keys. A window that needs the mouse keeps its own scroll, and typing in a
-- text box turns nothing.
-- The walk: a calm walk (Shift sprints while you have breath, client/Stamina.luau; a gamepad clicks the left stick), the
-- speed builds up and bleeds off (the body has weight), the character turns where it goes. With a piece in your hands
-- (the Carrying attribute) there is no sprint and a slower step: a move's piece (MoveCarry, server/Moving.luau) walks at
-- its own CarrySpeed. 8.1 carrying in two (client/PairSteer.luau, started here): the body no longer turns where it
-- walks (AutoRotate stays off while it steers), and the carry's walk is slower while the heading turns
-- (PairSteer.walk); in two, Shift, the stick click and the touch SPRINT do nothing and say so once a carry
-- (PairSteer.refuseRun).
-- Touch screens (and a gamepad without a mouse) keep the Roblox camera; the walk's speed is set here too (4.2: a touch
-- screen's SPRINT toggle, CameraRig.setTouchSprint).
-- 5.7, the feel (Config.LivingCity.Camera): a small shake that dies away on an explosion nearby (a bloater) and a hit
-- you take (CameraRig.shake for anything else; a touch screen's Roblox camera shakes too: Humanoid.CameraOffset).
-- Reduced motion (the player's Roblox setting): no shake.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Stamina = require(script.Parent.Stamina)
local PairSteer = require(script.Parent.PairSteer) -- 8.1: carrying in two (the leader's heading turns slowly)

local CameraRig = {}

local player = Players.LocalPlayer
local enabled = false
local yaw = 0
local pitch = -0.12
local zoom = 1
local turning = false -- the right mouse held to turn the camera (the cursor free)
local shiftHeld = false -- sprint
local padSprint = false -- a gamepad's left stick click: sprint until you stop (or run out of breath)
local touchSprint = false -- 4.2: the touch SPRINT toggle (client/TouchControls.luau): on until tapped off or out of breath
local sprintingNow = false -- the last step's answer (the SPRINT button lights while you really run)
local WALK_SPEED = Config.Movement.Walk -- 3.7: 14 (3.2.4: 12)
local SPRINT_SPEED = Config.Movement.Sprint -- 3.7: 28 (3.2.4: 25)
local CARRY_SPEED = 8 -- a piece in the hands: no sprinting

-- 4.5: the admin's walk multiplier (the player attribute AdminSpeed: 1, 2 or 4; only server/Admin.luau sets it).
-- 5.0: × the kit's (the character attribute KitSpeed), on every step on foot: the walk, the sprint, the carry.
local function adminSpeed(): number
	local value = player:GetAttribute("AdminSpeed")
	local character = player.Character
	local kit = if character then character:GetAttribute("KitSpeed") else nil
	local kitMult = if type(kit) == "number" and kit >= 1 and kit <= 2 then kit else 1
	return (if type(value) == "number" and value >= 1 and value <= 4 then value else 1) * kitMult
end

-- The step with a piece in the hands: 7.0 a move's thing (MoveCarry, server/Moving.luau) walks at its own CarrySpeed (a
-- lamp near the walk, a sofa dragged alone a crawl).
local function carrySpeed(character: Model): number
	local lift = character:GetAttribute("CarrySpeed")
	if type(lift) == "number" and character:GetAttribute("MoveCarry") ~= nil then
		return lift * PairSteer.walk() -- (8.1: slower while the heading of a piece carried in two turns)
	end
	return if type(lift) == "number" then math.min(lift, CARRY_SPEED) else CARRY_SPEED
end
-- The body has weight: the speed builds up and bleeds off instead of jumping (studs per second, per second).
-- 3.7: up a little with the wider walk-to-sprint gap (14 to 28 still takes half a second); running out of breath
-- drops you from a sprint to the walk in about 0.4 s.
local SPEED_UP = 28
local SLOW_DOWN = 38
local speed = WALK_SPEED
local smoothFocus: Vector3? = nil -- the camera's focus follows smoothly
local SENSITIVITY = 0.0032
-- 9.0.1 the keys that turn the camera, held (1) or not (0): , / . and the arrows
local turnKeys = { left = 0, right = 0, arrowLeft = 0, arrowRight = 0 }
local TURN_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Comma] = "left",
	[Enum.KeyCode.Period] = "right",
	[Enum.KeyCode.Left] = "arrowLeft",
	[Enum.KeyCode.Right] = "arrowRight",
}

-- Set by Main: is a window open that needs the mouse?
CameraRig.mouseNeeded = function(): boolean
	return false
end
-- Set by Main: is a window open (the modules that step aside under one ask it)?
CameraRig.windowOpen = function(): boolean
	return false
end
-- A weapon in the hands now? Then the mouse locks and the crosshair shows. Its own: a Tool equipped (the run's bat).
function CameraRig.toolEquipped(): boolean
	local character = player.Character
	return character ~= nil and character:FindFirstChildOfClass("Tool") ~= nil
end
CameraRig.armed = CameraRig.toolEquipped

local supported = UserInputService.KeyboardEnabled and UserInputService.MouseEnabled

-- ── 5.7: the shake ─────────────────────────────────────────────────────────

local Feel = Config.LivingCity.Camera
local shakeAmount = 0 -- 0 … 1, dies away at Feel.Decay a second

local function reducedMotion(): boolean
	local ok, on = pcall(function(): any
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

-- Shake the camera a little (0 … 1, added up to 1 at most): an explosion, a hit.
function CameraRig.shake(amount: number)
	if amount <= 0 or reducedMotion() then
		return
	end
	shakeAmount = math.min(1, shakeAmount + amount)
end

-- This frame's shake (a turn of the camera).
local function shakeTurn(): CFrame
	if shakeAmount <= 0.001 then
		return CFrame.identity
	end
	local t = os.clock()
	local k = math.rad(Feel.Angle) * shakeAmount * shakeAmount
	return CFrame.Angles(math.sin(t * 31) * k, math.sin(t * 27 + 1.3) * k, math.sin(t * 23 + 2.1) * k * 0.5)
end

local function stepFeel(dt: number)
	shakeAmount = math.max(0, shakeAmount - Feel.Decay * dt)
end

-- What shakes the camera: explosions near you, hits you take.
local function watchFeel()
	workspace.ChildAdded:Connect(function(child)
		if not child:IsA("Explosion") then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		local from = if root and root:IsA("BasePart") then root.Position elseif camera then camera.CFrame.Position else nil
		if from then
			local distance = (from - child.Position).Magnitude
			CameraRig.shake(Feel.Explosion * math.clamp(1 - distance / Feel.ExplosionReach, 0, 1))
		end
	end)
	local function watchHealth(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local last = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if health < last and health > 0 then
				CameraRig.shake(Feel.Damage * (last - health) / math.max(humanoid.MaxHealth, 1))
			end
			last = health
		end)
	end
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
	player.CharacterAdded:Connect(watchHealth)
end

-- ── The crosshair: one small dot ────────────────────────────────────────────
-- Shown only while the mouse is locked (a weapon in the hands): dim grey over nothing, white over a zombie (it fades
-- between the two).

local DOT_SIZE = 6
local DOT_IDLE = Color3.fromRGB(62, 64, 68)
local DOT_ENEMY = Color3.new(1, 1, 1)
local RING_IDLE = Color3.fromRGB(215, 215, 215)

local crosshair: Frame? = nil
local dotScale: UIScale? = nil
local dotStroke: UIStroke? = nil
local enemyBlend = 0 -- 0 = nothing hostile under the dot, 1 = a zombie

local function makeCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = DOT_IDLE
	dot.BackgroundTransparency = 0.25
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	-- A thin outline keeps the dot readable on a dark room and on a bright sky.
	local stroke = Instance.new("UIStroke")
	stroke.Color = RING_IDLE
	stroke.Thickness = 1
	stroke.Transparency = 0.6
	stroke.Parent = dot
	local scale = Instance.new("UIScale")
	scale.Parent = dot
	crosshair = dot
	dotScale = scale
	dotStroke = stroke
end

-- Is a zombie (a living one) right under the dot?
local enemyParams = RaycastParams.new()
enemyParams.FilterType = Enum.RaycastFilterType.Exclude
-- The camera's wall check, made once: only its exclude list changes each frame.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude

local function hostile(hit: Instance): boolean
	local model: Instance? = hit:FindFirstAncestorOfClass("Model")
	while model and model ~= workspace do
		if model:GetAttribute("Zombie") ~= nil then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return humanoid.Health > 0
			end
			local health = model:GetAttribute("Health")
			return type(health) ~= "number" or health > 0
		end
		local parent = model.Parent
		model = if parent and parent:IsA("Model") then parent elseif parent then parent:FindFirstAncestorOfClass("Model") else nil
	end
	return false
end

local function enemyUnderCrosshair(camera: Camera, character: Model): boolean
	local exclude: { Instance } = { character }
	local effects = workspace:FindFirstChild("LocalEffects")
	if effects then
		table.insert(exclude, effects)
	end
	enemyParams.FilterDescendantsInstances = exclude
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, enemyParams)
	return result ~= nil and hostile(result.Instance)
end

local function updateCrosshair(dt: number, show: boolean, over: boolean)
	local dot = crosshair
	if not dot then
		return
	end
	dot.Visible = show
	enemyBlend += ((if over and show then 1 else 0) - enemyBlend) * math.min(1, dt * 14)
	if not show then
		return
	end
	dot.BackgroundColor3 = DOT_IDLE:Lerp(DOT_ENEMY, enemyBlend)
	dot.BackgroundTransparency = 0.25 * (1 - enemyBlend)
	local stroke = dotStroke
	if stroke then
		stroke.Color = RING_IDLE:Lerp(Color3.new(0, 0, 0), enemyBlend)
		stroke.Transparency = 0.6 - 0.25 * enemyBlend
	end
	local scale = dotScale
	if scale then
		scale.Scale = 1 + 0.15 * enemyBlend
	end
end

-- What the local character holds in its hands (the server's Carrying attribute), or nil.
local function carryingOf(character: Model?): string?
	local value = if character then character:GetAttribute("Carrying") else nil
	return if type(value) == "string" and value ~= "" then value else nil
end

-- Is the mouse captured right now (a weapon in the hands), or free (the cursor shown; a window, Roblox's menu,
-- typing)?
function CameraRig.locked(): boolean
	if not enabled or not supported or CameraRig.mouseNeeded() or UserInputService:GetFocusedTextBox() ~= nil then
		return false
	end
	return CameraRig.armed()
end

function CameraRig.setEnabled(on: boolean)
	enabled = on
	if on then
		local camera = workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
		end
	end
end

local wasActive = false

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Does the character really go somewhere (the breath drains only then)? Input held and a speed to show for it:
-- running against a wall does not cost breath.
local function movingOn(humanoid: Humanoid, root: BasePart): boolean
	if humanoid.MoveDirection.Magnitude < 0.1 then
		return false
	end
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude > 3
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local active = enabled and supported
	if not active then
		if wasActive then
			wasActive = false
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			updateCrosshair(dt, false, false)
		end
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return
	end
	wasActive = true

	local locked = CameraRig.locked()
	if turning and (locked or CameraRig.mouseNeeded()) then
		turning = false
	end
	UserInputService.MouseBehavior = if locked then Enum.MouseBehavior.LockCenter
		elseif turning then Enum.MouseBehavior.LockCurrentPosition
		else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not locked

	-- 9.0.1 the keys that turn it
	local spin = (turnKeys.right - turnKeys.left) + (turnKeys.arrowRight - turnKeys.arrowLeft)
	if spin ~= 0 then
		yaw -= math.clamp(spin, -1, 1) * Config.CameraTurn.Keys * dt
	end

	-- The walk, the sprint with Shift while the breath lasts (client/Stamina.luau); with a piece in the hands no sprint,
	-- and the breath comes back.
	local seated = humanoid.SeatPart ~= nil
	local handsFull = carryingOf(character) ~= nil
	local moving = not seated and humanoid.Health > 0 and movingOn(humanoid, root)
	if padSprint and humanoid.MoveDirection.Magnitude < 0.1 then
		padSprint = false -- the stick let go: the gamepad's sprint ends
	end
	local sprinting = Stamina.update(dt, not seated and not handsFull and (shiftHeld or padSprint), moving)
	if padSprint and not sprinting then
		padSprint = false -- out of breath: click again once it is back
	end
	if not seated then
		local target = if handsFull then carrySpeed(character)
			elseif sprinting then SPRINT_SPEED * Stamina.sprintBoost() -- (6.20: Light Step)
			else WALK_SPEED
		local rate = if target > speed then SPEED_UP else SLOW_DOWN
		speed = if target > speed then math.min(target, speed + rate * dt) else math.max(target, speed - rate * dt)
		humanoid.WalkSpeed = speed * adminSpeed()
	end

	-- Behind you, a little to the side.
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local focus = root.Position + Vector3.new(0, 2.2, 0)
	local back = Vector3.new(0.8, 1.2, 11 * zoom)
	local exclude: { Instance } = { character }
	-- Only the world stops the camera, not things that move around.
	for _, name in { "LocalEffects", "Zombies", "Cars", "Loot", "Effects", "Npcs" } do
		local thing = workspace:FindFirstChild(name)
		if thing then
			table.insert(exclude, thing)
		end
	end
	-- Smooth follow: sideways tight, up and down soft.
	local last = smoothFocus
	local previous: Vector3 = if last and (last - focus).Magnitude <= 40 then last else focus
	local side = math.min(1, dt * 25)
	local vertical = math.min(1, dt * 7)
	focus = Vector3.new(lerp(previous.X, focus.X, side), lerp(previous.Y, focus.Y, vertical), lerp(previous.Z, focus.Z, side))
	smoothFocus = focus
	local desired = focus + rotation:VectorToWorldSpace(back)
	-- Do not go through walls.
	wallParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(focus, desired - focus, wallParams)
	local position = if hit then hit.Position + (focus - desired).Unit * 0.6 else desired
	camera.CameraType = Enum.CameraType.Scriptable
	stepFeel(dt)
	camera.CFrame = CFrame.lookAt(position, position + rotation.LookVector) * shakeTurn() -- (5.7: the shake)
	camera.FieldOfView = 70

	-- The character turns where it walks (the Humanoid does it), unless carrying in two (PairSteer's heading).
	if not PairSteer.steering() then
		humanoid.AutoRotate = true
	end

	local showDot = locked and not handsFull and humanoid.Health > 0
	updateCrosshair(dt, showDot, showDot and enemyUnderCrosshair(camera, character))
end

-- Touch screens (and a gamepad without a mouse) keep the Roblox camera and walk; the speed is set here: the walk of
-- Config.Movement, the slower step with a piece in the hands, and a gamepad's sprint (left stick click) on the breath.
-- WalkSpeed is only written when it changes.
local function touchSpeed()
	local written: number? = nil
	local writtenFor: Humanoid? = nil -- a new character (a respawn) gets its speed again
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonL3 then
			padSprint = true
			PairSteer.refuseRun() -- (8.3: a piece in two: no run, said once)
		end
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root then
			return
		end
		local seated = humanoid.SeatPart ~= nil
		local handsFull = not seated and carryingOf(character) ~= nil
		local moving = not seated and humanoid.Health > 0 and movingOn(humanoid, root)
		if padSprint and humanoid.MoveDirection.Magnitude < 0.1 then
			padSprint = false
		end
		-- 4.2: the touch toggle stays on while you stand (no breath goes then); a seat, death or an empty breath end it.
		if touchSprint and (seated or humanoid.Health <= 0 or not Stamina.canSprintNow()) then
			touchSprint = false
		end
		local sprinting = Stamina.update(dt, (padSprint or touchSprint) and not handsFull, moving)
		if padSprint and not sprinting then
			padSprint = false
		end
		sprintingNow = sprinting and moving
		if seated then
			written = nil
			return
		end
		local target = if handsFull then carrySpeed(character) elseif sprinting then SPRINT_SPEED * Stamina.sprintBoost() else WALK_SPEED -- (6.20: Light Step)
		local rate = if target > speed then SPEED_UP else SLOW_DOWN
		speed = if target > speed then math.min(target, speed + rate * dt) else math.max(target, speed - rate * dt)
		local walk = speed * adminSpeed()
		if walk ~= written or humanoid ~= writtenFor then
			written = walk
			writtenFor = humanoid
			humanoid.WalkSpeed = walk
		end
	end)
end

-- 5.7: the Roblox camera of a touch screen shakes (Humanoid.CameraOffset: a small move, it never turns).
local function touchFeel()
	local offsetOn: Humanoid? = nil
	RunService:BindToRenderStep("ZombieDeliveryFeel", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
		stepFeel(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and shakeAmount > 0.001 then
			local t = os.clock()
			local k = Feel.Offset * shakeAmount * shakeAmount
			humanoid.CameraOffset = Vector3.new(math.sin(t * 29) * k, math.sin(t * 33 + 0.7) * k, 0)
			offsetOn = humanoid
		elseif offsetOn then
			offsetOn.CameraOffset = Vector3.zero
			offsetOn = nil
		end
	end)
end

function CameraRig.start()
	PairSteer.start() -- 8.1: carrying in two (a computer and a touch screen alike)
	watchFeel()
	if not supported then
		touchSpeed()
		touchFeel()
		return
	end
	makeCrosshair()
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and (turning or CameraRig.locked()) then
			yaw -= input.Delta.X * SENSITIVITY
			pitch = math.clamp(pitch - input.Delta.Y * SENSITIVITY, -1.2, 0.9)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			-- The wheel scrolls a window or a list under the mouse, not the camera.
			if processed or CameraRig.mouseNeeded() then
				return
			end
			zoom = math.clamp(zoom - input.Position.Z * 0.1, 0.5, 2)
		end
	end)
	-- 9.0.1 a trackpad (the Mac's): a two-finger swipe turns the camera, a pinch zooms (Roblox's own camera's way; its
	-- wheel is the MouseWheel's above). A window under the cursor keeps its scroll.
	UserInputService.PointerAction:Connect(function(_wheel: number, pan: Vector2, pinch: number, processed: boolean)
		if not enabled or processed or CameraRig.mouseNeeded() then
			return
		end
		local turn = Config.CameraTurn
		if pan.X ~= 0 or pan.Y ~= 0 then
			yaw -= pan.X * turn.Pan
			pitch = math.clamp(pitch - pan.Y * turn.Pan * turn.PanPitch, -1.2, 0.9)
		end
		if pinch ~= 0 then
			zoom = math.clamp(zoom - pinch * turn.Pinch, 0.5, 2)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		local turnKey = TURN_KEYS[input.KeyCode]
		if turnKey and UserInputService:GetFocusedTextBox() == nil then
			turnKeys[turnKey] = 1 -- 9.0.1 (never while typing; the camera's own key bindings may mark them processed)
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = true
			if not processed then
				PairSteer.refuseRun() -- (8.3: a piece in two: no run, said once; not a capital typed in the chat)
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonL3 then
			padSprint = true
			PairSteer.refuseRun()
		elseif processed then
			return
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if not CameraRig.locked() and not CameraRig.mouseNeeded() then
				turning = true -- the right mouse held turns the camera, the cursor stays free
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local turnKey = TURN_KEYS[input.KeyCode]
		if turnKey then
			turnKeys[turnKey] = 0
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			turning = false
		end
	end)
	-- Leaving the window (Alt+Tab, a screenshot) can swallow the key-up events: nothing stays held.
	UserInputService.WindowFocusReleased:Connect(function()
		for key in turnKeys do
			turnKeys[key] = 0
		end
		shiftHeld = false
		padSprint = false
		turning = false
	end)
	RunService:BindToRenderStep("ZombieDeliveryCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

-- 4.2: the touch SPRINT toggle (client/TouchControls.luau): on, you sprint whenever you move and have breath (the
-- same breath, Stamina.update); it turns itself off when the breath runs dry, in a seat or on death.
function CameraRig.setTouchSprint(on: boolean)
	if on and PairSteer.holding() then
		PairSteer.refuseRun() -- (8.3: a piece in two: no run, said once)
		touchSprint = false
		return
	end
	touchSprint = on and Stamina.canSprintNow()
end

-- Is the touch SPRINT toggle on, and do you really sprint right now?
function CameraRig.touchSprint(): (boolean, boolean)
	return touchSprint, sprintingNow
end

-- 8.3 walk-in doors (client/WalkDoors.luau, while a door's trip keeps the screen black): the camera behind you, looking
-- the way `look` goes (its pitch and zoom kept, the follow started afresh where you are). False: this rig does not
-- drive the camera now (a touch screen keeps the Roblox camera: the caller turns that one).
function CameraRig.face(look: Vector3): boolean
	if not enabled or not supported then
		return false
	end
	if look.X * look.X + look.Z * look.Z > 1e-6 then
		yaw = math.atan2(-look.X, -look.Z)
	end
	smoothFocus = nil
	return true
end

return CameraRig
