--!strict
-- GTA-style aiming on a computer: the mouse is locked in the middle of the screen, the mouse moves the camera
-- (behind you on foot, behind the car when driving), a dot in the middle shows where the gun hits (dim over nothing,
-- white over an enemy, a pulse on a hit, red on a kill).
-- On foot it plays like GTA: a calm walk (Shift sprints while you have breath, client/Stamina.luau; a gamepad clicks
-- the left stick), the speed builds up and bleeds off (the body has weight),
-- the character turns where it goes; aiming (right mouse) or shooting (left mouse) it slows to a careful step, turns
-- to the crosshair and raises the gun (shots wait until it is up, client/ArmPose.luau; out of a sprint the body
-- first slows down and the gun comes up slower), the camera moves in over the shoulder. When a window is open (map, shop, backpack, job
-- board …) or while you hold Alt the mouse is free to click. Touch screens keep the normal Roblox camera (and walk at
-- Config.Movement.Walk; a gamepad without a mouse sprints with the left stick click there too; 4.2: a touch screen with
-- the SPRINT toggle, CameraRig.setTouchSprint).
-- With cargo in your hands (the Carrying attribute, server/Cargo.luau) there is no aiming, no sprint and a slower step.
-- 3.9: with the gun holstered (B, client/Holster.luau) there is no aiming either; the first right or left click draws
-- the gun (the left one does not shoot then), and the gun comes up as usual from there.
-- 3.10: getting in or out of a car (client/CarBoarding.luau moves the body, Drive.boardingCar) the camera eases between
-- the walk's view and the car's over CAR_BLEND seconds instead of jumping, and the walk (speed, turning, aiming) is
-- left alone meanwhile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Drive = require(script.Parent.Drive)
local Stamina = require(script.Parent.Stamina)
local Holster = require(script.Parent.Holster)

local CameraRig = {}

local player = Players.LocalPlayer
local enabled = false
local yaw = 0
local pitch = -0.12
local zoom = 1
local lastMouse = 0
local altHeld = false
local rmbHeld = false -- aiming
local lmbHeld = false -- shooting
local lastFire = 0
local aimBlend = 0 -- 0 = walking camera, 1 = over the shoulder
local aimingSent = false
local shiftHeld = false -- sprint
local padSprint = false -- a gamepad's left stick click: sprint until you stop (or run out of breath)
local touchSprint = false -- 4.2: the touch SPRINT toggle (client/TouchControls.luau): on until tapped off or out of breath
local sprintingNow = false -- the last step's answer (the SPRINT button lights while you really run)
local aimSince = 0 -- when the gun started going up (shots wait until it is up)
local WALK_SPEED = Config.Movement.Walk -- 3.7: 14 (3.2.4: 12)
local SPRINT_SPEED = Config.Movement.Sprint -- 3.7: 28 (3.2.4: 25)
local AIM_WALK_SPEED = 3.5 -- a careful step with the gun up
local CARRY_SPEED = 8 -- a crate, a barrel or a horse on a rope: no sprinting

-- The step with cargo in the hands: slower still with a heavy piece and nobody helping (the TWO-MAN LIFT twist:
-- server/Cargo.luau sets the character's CarrySpeed attribute).
local function carrySpeed(character: Model): number
	local lift = character:GetAttribute("CarrySpeed")
	if type(lift) == "number" and character:GetAttribute("Pushing") ~= nil then
		return lift -- 4.0: a trolley rolls a little faster than a crate is carried (server/Equipment.luau)
	end
	return if type(lift) == "number" then math.min(lift, CARRY_SPEED) else CARRY_SPEED
end
-- The body has weight: the speed builds up and bleeds off instead of jumping (studs per second, per second).
-- 3.7: up a little with the wider walk-to-sprint gap (14 to 28 still takes half a second); running out of breath
-- drops you from a sprint to the walk in about 0.4 s.
local SPEED_UP = 28
local SLOW_DOWN = 38
local speed = WALK_SPEED
-- Out of a sprint the gun comes up slower: first the body slows, then the arms find the aim.
local SPRINT_RAISE_TIME = 0.5
local raiseTime = 0.25
local RAISE_TIME = 0.25
local armPitch = 0 -- how far up (+) or down the gun arm points: from the shoulder to what is under the crosshair
local smoothFocus: Vector3? = nil -- the camera's focus follows smoothly (no shaking with every bump of the car)
local SENSITIVITY = 0.0032
-- 3.10: 0 = the walk's view, 1 = the car's; the car it eases toward or away from.
local CAR_BLEND = 0.45
local carBlend = 0
local viewCar: Model? = nil

-- Set by Main: is a window open that needs the mouse?
CameraRig.mouseNeeded = function(): boolean
	return false
end

local supported = UserInputService.KeyboardEnabled and UserInputService.MouseEnabled

-- ── The crosshair: one small dot ────────────────────────────────────────────
-- Dim grey over nothing, white over an enemy (it fades between the two), a quick pulse on every hit, a short red
-- tint on a kill (Shooting draws the X of a headshot on top).

local DOT_SIZE = 6
local DOT_IDLE = Color3.fromRGB(62, 64, 68)
local DOT_ENEMY = Color3.new(1, 1, 1)
local DOT_KILL = Color3.fromRGB(255, 64, 52)
local RING_IDLE = Color3.fromRGB(215, 215, 215)

local crosshair: Frame? = nil
local dotScale: UIScale? = nil
local dotStroke: UIStroke? = nil
local enemyBlend = 0 -- 0 = nothing hostile under the dot, 1 = an enemy
local pulse = 0 -- 1 right after a hit, fades fast
local killTint = 0 -- 1 right after a kill, fades

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
	-- A thin outline keeps the dot readable on a dark street and on a bright sky.
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

-- Shooting: one of your shots hit ("hit"), killed ("kill") or hit a head ("head").
function CameraRig.hitFeedback(kind: string)
	pulse = 1
	if kind == "kill" or kind == "head" then
		killTint = 1
	end
end

-- Is an enemy (a living zombie, bandit or bandit car) right under the dot?
local enemyParams = RaycastParams.new()
enemyParams.FilterType = Enum.RaycastFilterType.Exclude
-- The camera's own rays (the wall check and the aim), made once: only their exclude lists change each frame.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
-- The shown car's size (GetExtentsSize walks every part), measured once per car.
local extentsCar: Model? = nil
local extentsSize = Vector3.zero

local function hostile(hit: Instance): boolean
	local model: Instance? = hit:FindFirstAncestorOfClass("Model")
	while model and model ~= workspace do
		if model:GetAttribute("Zombie") ~= nil or model:GetAttribute("Bandit") ~= nil then
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

local function enemyUnderCrosshair(camera: Camera, character: Model, car: Model?): boolean
	local exclude: { Instance } = { character }
	if car then
		table.insert(exclude, car)
	end
	for _, name in { "LocalEffects", "DeliveryGuide" } do
		local thing = workspace:FindFirstChild(name)
		if thing then
			table.insert(exclude, thing)
		end
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
	pulse = math.max(0, pulse - dt * 6)
	killTint = math.max(0, killTint - dt * 2.6)
	if not show then
		return
	end
	local hot = math.max(enemyBlend, killTint)
	dot.BackgroundColor3 = DOT_IDLE:Lerp(DOT_ENEMY, enemyBlend):Lerp(DOT_KILL, killTint)
	dot.BackgroundTransparency = 0.25 * (1 - hot)
	local stroke = dotStroke
	if stroke then
		stroke.Color = RING_IDLE:Lerp(Color3.new(0, 0, 0), hot)
		stroke.Transparency = 0.6 - 0.25 * hot
	end
	local scale = dotScale
	if scale then
		-- Pops out on the hit and settles back (eased).
		scale.Scale = 1 + 0.9 * pulse * pulse + 0.15 * enemyBlend
	end
end

-- What the local character holds in its hands (server/Cargo.luau sets the Carrying attribute), or nil.
local function carryingOf(character: Model?): string?
	local value = if character then character:GetAttribute("Carrying") else nil
	return if type(value) == "string" and value ~= "" then value else nil
end

function CameraRig.carrying(): string?
	return carryingOf(player.Character)
end

-- Is the mouse captured right now (aiming), or free (a window, Alt, Roblox's menu, typing)?
function CameraRig.locked(): boolean
	return enabled and supported and not altHeld and not CameraRig.mouseNeeded() and UserInputService:GetFocusedTextBox() == nil
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

-- Tell the server (the gun arm goes up / down for everybody, and follows where you aim up or down).
local pitchSent = 0
local pitchSentAt = 0
local function sendAiming(aiming: boolean)
	local now = os.clock()
	local pitchMoved = aiming and math.abs(armPitch - pitchSent) > 0.08 and now - pitchSentAt > 0.2
	if aiming ~= aimingSent or pitchMoved then
		aimingSent = aiming
		pitchSent = armPitch
		pitchSentAt = now
		Net.get("Aiming"):FireServer(aiming, armPitch)
	end
end

-- ArmPose: is the local character aiming, and how far up or down (radians, + is up).
-- ArmPose: how long the arms take to come up this time (longer out of a sprint).
function CameraRig.raiseTime(): number
	return raiseTime
end

function CameraRig.aimPose(): (boolean, number)
	return enabled and supported and aimingSent, armPitch
end

-- On foot the gun must be up before it fires (it takes RAISE_TIME after you start aiming); in a car always.
function CameraRig.canShoot(): boolean
	if not enabled or not supported or Drive.seatedCar() then
		return true
	end
	return aimingSent and os.clock() - aimSince >= raiseTime
end

-- Shooting module: a shot was fired (the character turns to the aim for a moment).
function CameraRig.noteFire()
	lastFire = os.clock()
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
			sendAiming(false)
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
	UserInputService.MouseBehavior = if locked then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not locked

	local car, driving = Drive.seatedCar()
	local boardCar, into = Drive.boardingCar() -- 3.10: getting in or out right now
	local busy = boardCar ~= nil
	local now = os.clock()
	-- Cargo in the hands (on foot): the aim inputs do nothing.
	local handsFull = car == nil and carryingOf(character) ~= nil
	-- Aiming from a car (drive-by): right mouse held, any seat.
	local carAim = locked and car ~= nil and rmbHeld and humanoid.Health > 0

	-- Driving and not touching the mouse for a moment: the camera swings back behind the car.
	if car and driving and car.PrimaryPart and now - lastMouse > 1.2 and not carAim then
		local chassis = car.PrimaryPart
		local v = chassis.AssemblyLinearVelocity
		if Vector3.new(v.X, 0, v.Z).Magnitude > 8 then
			local look = chassis.CFrame.LookVector
			local carYaw = math.atan2(-look.X, -look.Z)
			local diff = (carYaw - yaw + math.pi) % (2 * math.pi) - math.pi
			yaw += diff * math.min(1, 0.06)
			pitch += (-0.18 - pitch) * 0.05
		end
	end

	-- Aiming: right mouse held, shooting, or a shot a moment ago (on foot only).
	local wantAim = locked and not car and not busy and not handsFull and not Holster.holstered() and (rmbHeld or lmbHeld or now - lastFire < 0.7) and humanoid.Health > 0
	aimBlend = lerp(aimBlend, if wantAim or carAim then 1 else 0, math.min(1, dt * 10))
	if wantAim and not aimingSent then
		aimSince = now
		raiseTime = if speed > WALK_SPEED + 3 then SPRINT_RAISE_TIME else RAISE_TIME
	end
	sendAiming(wantAim)

	-- On foot: walk, sprint with Shift while the breath lasts (client/Stamina.luau), a careful step with the gun up
	-- (aiming or shooting). Carrying or aiming there is no sprint, and the breath comes back.
	local moving = car == nil and humanoid.Health > 0 and movingOn(humanoid, root)
	if padSprint and humanoid.MoveDirection.Magnitude < 0.1 then
		padSprint = false -- the stick let go: the gamepad's sprint ends
	end
	local sprinting = Stamina.update(dt, car == nil and not wantAim and not handsFull and (shiftHeld or padSprint), moving)
	if padSprint and not sprinting then
		padSprint = false -- out of breath: click again once it is back
	end
	if not car and not busy then
		local target = if wantAim then AIM_WALK_SPEED
			elseif handsFull then carrySpeed(character)
			elseif sprinting then SPRINT_SPEED
			else WALK_SPEED
		local rate = if target > speed then SPEED_UP else SLOW_DOWN
		speed = if target > speed then math.min(target, speed + rate * dt) else math.max(target, speed - rate * dt)
		humanoid.WalkSpeed = speed
	end

	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	-- Walking: behind, a little to the side. Aiming: close over the right shoulder.
	local focus = root.Position + Vector3.new(0, lerp(2.2, 1.8, aimBlend), 0)
	local back = Vector3.new(lerp(0.8, 2.3, aimBlend), lerp(1.2, 0.5, aimBlend), lerp(11, 6.5, aimBlend) * zoom)
	local exclude: { Instance } = { character }
	-- 3.10: in a car (or getting in) the view eases over to the car's; getting out it eases back.
	local near = car or boardCar
	if near then
		viewCar = near
	end
	local carGoal = if car or (boardCar and into) then 1 else 0
	carBlend = if carGoal > carBlend then math.min(carGoal, carBlend + dt / CAR_BLEND) else math.max(carGoal, carBlend - dt / CAR_BLEND)
	local shown = viewCar
	if shown and (carBlend <= 0 or not shown.Parent) then
		viewCar = nil
		shown = nil
	end
	local chassis = shown and shown.PrimaryPart
	if shown and chassis then
		if extentsCar ~= shown then
			extentsCar = shown
			extentsSize = shown:GetExtentsSize()
		end
		local size = extentsSize
		local carFocus = chassis.Position + Vector3.new(0, size.Y * 0.6 + 2, 0)
		-- Behind the car; aiming: closer, over the right side of the roof.
		local carBack = Vector3.new(lerp(0, 3, aimBlend), lerp(2, 0.8, aimBlend), lerp(size.Z * 0.7 + 9, size.Z * 0.3 + 4, aimBlend) * zoom)
		local k = carBlend * carBlend * (3 - 2 * carBlend)
		focus = focus:Lerp(carFocus, k)
		back = back:Lerp(carBack, k)
		table.insert(exclude, shown)
	end
	-- Only the world stops the camera, not things that move around (a horse on the rope right behind you too).
	for _, name in { "LocalEffects", "DeliveryGuide", "Zombies", "Cars", "BanditCars", "Loot", "Effects", "Npcs", "Animals", "Traffic" } do
		local thing = workspace:FindFirstChild(name)
		if thing then
			table.insert(exclude, thing)
		end
	end
	-- Smooth follow: sideways tight, up and down soft (the car's bumps do not shake the picture).
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
	camera.CFrame = CFrame.lookAt(position, position + rotation.LookVector)
	camera.FieldOfView = lerp(70, 55, aimBlend)

	-- The gun arm points from the shoulder at whatever is under the crosshair (not simply where the camera looks:
	-- a camera looking down from above would point the arms at your feet).
	if wantAim then
		local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
		local aimExclude: { Instance } = { character }
		local effects = workspace:FindFirstChild("LocalEffects")
		if effects then
			table.insert(aimExclude, effects)
		end
		aimParams.FilterDescendantsInstances = aimExclude
		local aimHit = workspace:Raycast(ray.Origin, ray.Direction * 600, aimParams)
		local target = if aimHit then aimHit.Position else ray.Origin + ray.Direction * 600
		local shoulder = root.Position + Vector3.new(0, 1.5, 0)
		local offset = target - shoulder
		-- Something very close under the crosshair (or the ground at your feet): keep the arms level-ish.
		local goal = if offset.Magnitude > 4 then math.asin(math.clamp(offset.Unit.Y, -1, 1)) else 0
		armPitch = lerp(armPitch, math.clamp(goal, -0.6, 0.95), math.min(1, dt * 15))
	else
		armPitch = 0
	end

	-- On foot: the character turns where it walks (the Humanoid does it), or toward the aim while aiming.
	if wantAim then
		humanoid.AutoRotate = false
		local look = root.CFrame.LookVector
		local current = math.atan2(-look.X, -look.Z)
		local diff = (yaw - current + math.pi) % (2 * math.pi) - math.pi
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, current + diff * math.min(1, dt * 18), 0)
	elseif not busy then
		humanoid.AutoRotate = true
	end

	local showDot = locked and not handsFull and humanoid.Health > 0
	updateCrosshair(dt, showDot, showDot and enemyUnderCrosshair(camera, character, car))
end

-- Touch screens (and a gamepad without a mouse) keep the Roblox camera and walk; the speed is set here: the walk of
-- Config.Movement, the slower step with cargo in the hands, and a gamepad's sprint (left stick click) on the breath.
-- WalkSpeed is only written when it changes (the server's fallback, server/Cargo.luau, is not fought every frame).
local function touchSpeed()
	local written: number? = nil
	local writtenFor: Humanoid? = nil -- a new character (a respawn) gets its speed again
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonL3 then
			padSprint = true
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
		local target = if handsFull then carrySpeed(character) elseif sprinting then SPRINT_SPEED else WALK_SPEED
		local rate = if target > speed then SPEED_UP else SLOW_DOWN
		speed = if target > speed then math.min(target, speed + rate * dt) else math.max(target, speed - rate * dt)
		if speed ~= written or humanoid ~= writtenFor then
			written = speed
			writtenFor = humanoid
			humanoid.WalkSpeed = speed
		end
	end)
end

function CameraRig.start()
	if not supported then
		touchSpeed()
		return
	end
	makeCrosshair()
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and CameraRig.locked() then
			yaw -= input.Delta.X * SENSITIVITY
			pitch = math.clamp(pitch - input.Delta.Y * SENSITIVITY, -1.2, 0.9)
			lastMouse = os.clock()
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			-- The wheel scrolls a window (the job board, the missions…) or a list under the mouse, not the camera.
			if processed or CameraRig.mouseNeeded() then
				return
			end
			zoom = math.clamp(zoom - input.Position.Z * 0.1, 0.5, 2)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = true
		elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = true
		elseif input.KeyCode == Enum.KeyCode.ButtonL3 then
			padSprint = true
		elseif processed then
			return
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			Holster.pressDraws(input) -- 3.9: holstered, the gun comes out and goes up
			rmbHeld = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- 3.9: holstered, this click only draws the gun (no shot, no aim)
			lmbHeld = not Holster.pressDraws(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = false
		elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			lmbHeld = false
		end
	end)
	-- Leaving the window (Alt+Tab, a screenshot) can swallow the key-up events: nothing stays held.
	UserInputService.WindowFocusReleased:Connect(function()
		altHeld = false
		shiftHeld = false
		padSprint = false
		rmbHeld = false
		lmbHeld = false
	end)
	RunService:BindToRenderStep("ZombieDeliveryCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

-- 4.2: the touch SPRINT toggle (client/TouchControls.luau): on, you sprint whenever you move and have breath (the
-- same breath, Stamina.update); it turns itself off when the breath runs dry, in a seat or on death.
function CameraRig.setTouchSprint(on: boolean)
	touchSprint = on and Stamina.canSprintNow()
end

-- Is the touch SPRINT toggle on, and do you really sprint right now?
function CameraRig.touchSprint(): (boolean, boolean)
	return touchSprint, sprintingNow
end

-- The point under the crosshair (locked) for the guns and the thrown items.
function CameraRig.aimRay(): Ray?
	if not CameraRig.locked() then
		return nil
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local viewport = camera.ViewportSize
	return camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
end

return CameraRig
