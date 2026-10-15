--!nocheck
-- 9.0 (the owner: "aiming the way I have the crosshair now only when I want to shoot or have pistols; I want the mouse
-- normally available, so remove the Alt option"): the real client/CameraRig.luau (tests/run_tests.py copies it as
-- CameraRigClient.luau, a function of the globals it reads) on a computer's keyboard and mouse, on
-- tests/runtime/ClientRuntime.luau's instances, frames and vectors, made afresh for each world:
--   * the sandbox (CameraRig.aimOnly and CameraRig.armed as client/Main.client.luau sets them there): the cursor free
--     (MouseBehavior Default, shown, no crosshair dot) while the rig still drives the camera (Scriptable: the walk goes
--     the camera's way, the body turns where it walks); a mouse move turns nothing; the right mouse held turns the
--     camera (LockCurrentPosition) and aims nothing (no Aiming to the server, the walk's speed kept); let go, free
--     again; a left click shoots and aims nothing; Alt and the MOUSE button change nothing; the wheel zooms, but not
--     while a window needs the mouse or a list under it takes the wheel; a window open: the right mouse turns nothing;
--     a Tool equipped (armed): the mouse locked (LockCenter, no cursor), the dot, a mouse move turns the camera, the
--     right mouse aims (Aiming); put away: free again; another armed hook decides alone; driving with the cursor free
--     (the mouse moving or not) the camera swings behind the van; a door's trip (CameraRig.face) puts it behind you;
--   * the city (Config.Sandbox.On false: aimOnly never set): locked as before (LockCenter, no cursor, the dot), a
--     mouse move turns the camera, Alt held frees it, the MOUSE button frees it until clicked again, the phone open
--     (freeLook) lets the right mouse turn it, the right and the left mouse aim, a Tool changes nothing;
--   * a touch screen: the Roblox camera as before (the rig never binds its camera step, the mouse is never locked).
-- Run with tests/run_tests.py.

local E = require("./ClientRuntime")
local Config = require("./Config")
local CameraRigClient = require("./CameraRigClient")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- ── What the rig reads beyond ClientRuntime ─────────────────────────────────

local Vector3, CFrame = E.Vector3, E.CFrame
local F = getmetatable(CFrame.new())
F.__index = function(cf: any, key: string): any
	if key == "LookVector" then
		local r = cf.R
		return Vector3.new(-r[3], -r[6], -r[9])
	end
	return rawget(F, key)
end
function F.VectorToWorldSpace(cf: any, v: any): any
	return cf * v - cf.Position
end
local V = getmetatable(Vector3.new(0, 0, 0))
function V.Lerp(a: any, b: any, t: number): any
	return a + (b - a) * t
end
local I = getmetatable(E.new("Folder"))
function I.WaitForChild(self: any, name: string): any
	return self:FindFirstChild(name)
end
local Vector2 = { new = function(x: number, y: number): any
	return { X = x, Y = y }
end }
local UDim = { new = function(scale: number, offset: number): any
	return { Scale = scale, Offset = offset }
end }
local UDim2 = {
	fromOffset = function(x: number, y: number): any
		return { X = UDim.new(0, x), Y = UDim.new(0, y) }
	end,
	fromScale = function(x: number, y: number): any
		return { X = UDim.new(x, 0), Y = UDim.new(y, 0) }
	end,
}
local Enum = setmetatable({ RenderPriority = { Camera = { Value = 200 } } }, { __index = E.Enum })

-- ── A world: the services, the body, the camera, the rig ────────────────────

type World = {
	rig: any,
	uis: any,
	camera: any,
	body: any,
	root: any,
	humanoid: any,
	player: any,
	workspace: any,
	render: { [string]: (number) -> () },
	sent: { { any } },
	window: boolean,
	phone: boolean,
	car: any,
	dt: number,
}

local clock = 100

local function world(sandbox: boolean, touch: boolean?): World
	local w: World = { render = {}, sent = {}, window = false, phone = false, car = nil, dt = 1 / 60 } :: any
	local uis = {
		KeyboardEnabled = not touch,
		MouseEnabled = not touch,
		TouchEnabled = touch == true,
		MouseBehavior = "Default",
		MouseIconEnabled = true,
		InputBegan = E.signal(),
		InputEnded = E.signal(),
		InputChanged = E.signal(),
		WindowFocusReleased = E.signal(),
		focused = nil,
	}
	function uis.GetFocusedTextBox(self: any): any
		return self.focused
	end
	w.uis = uis
	local player = E.new("Player", "Me")
	player.UserId = 1
	player.CharacterAdded = E.signal()
	E.new("PlayerGui", "PlayerGui", player)
	local body = E.body("Me", Vector3.new(0, 3, 0))
	local root = body:FindFirstChild("HumanoidRootPart")
	root.AssemblyLinearVelocity = Vector3.zero
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	humanoid.MoveDirection = Vector3.zero
	humanoid.WalkSpeed = 16
	humanoid.MaxHealth = 100
	humanoid.AutoRotate = true
	humanoid.HealthChanged = E.signal()
	player.Character = body
	w.player, w.body, w.root, w.humanoid = player, body, root, humanoid
	local camera = {
		CFrame = CFrame.new(0, 6, 14),
		CameraType = "Custom",
		FieldOfView = 70,
		ViewportSize = Vector2.new(1280, 800),
	}
	function camera.ViewportPointToRay(self: any, _x: number, _y: number): any
		return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector }
	end
	w.camera = camera
	local workspace = E.new("Workspace", "Workspace")
	workspace.CurrentCamera = camera
	workspace.Raycast = function(): any
		return nil
	end
	w.workspace = workspace
	local services = {
		GuiService = { ReducedMotionEnabled = false },
		Players = { LocalPlayer = player },
		RunService = {
			Heartbeat = E.signal(),
			PreSimulation = E.signal(),
			BindToRenderStep = function(_self: any, name: string, _priority: number, fn: (number) -> ())
				w.render[name] = fn
			end,
		},
		UserInputService = uis,
		ReplicatedStorage = { WaitForChild = function(_self: any, _name: string): any
			return { WaitForChild = function(_shared: any, name: string): any
				return { Name = name }
			end }
		end },
	}
	local game = { GetService = function(_self: any, name: string): any
		return assert(services[name], name)
	end }
	local fakes = {
		Config = Config,
		Net = { get = function(name: string): any
			return { FireServer = function(_remote: any, ...: any)
				table.insert(w.sent, { name, ... })
			end }
		end },
		Drive = {
			seatedCar = function(): (any, boolean)
				return w.car, w.car ~= nil
			end,
			boardingCar = function(): (any, boolean)
				return nil, false
			end,
		},
		Stamina = {
			update = function(): boolean
				return false
			end,
			sprintBoost = function(): number
				return 1
			end,
			canSprintNow = function(): boolean
				return true
			end,
		},
		Holster = {
			holstered = function(): boolean
				return false
			end,
			pressDraws = function(): boolean
				return false
			end,
		},
		ShotKick = { apply = function() end },
		PairSteer = {
			start = function() end,
			steering = function(): boolean
				return false
			end,
			walk = function(): number
				return 1
			end,
			refuseRun = function() end,
			holding = function(): boolean
				return false
			end,
		},
	}
	local script = { Parent = setmetatable({}, { __index = function(_, name: string): any
		return { Name = name }
	end }) }
	local fakeRequire = function(target: any): any
		return assert(fakes[target.Name], target.Name)
	end
	local task = { spawn = function(fn: any, ...: any)
		fn(...)
	end }
	local os = { clock = function(): number
		return clock
	end }
	local Instance = { new = function(class: string): any
		return E.new(class)
	end }
	local RaycastParams = { new = function(): any
		return {}
	end }
	local rig = CameraRigClient(game, workspace, script, fakeRequire, Instance, RaycastParams, task, os, CFrame, Vector3, Vector2, E.Color3, UDim, UDim2, Enum)
	-- what client/Main.client.luau sets (the sandbox's block, or the city's)
	rig.mouseNeeded = function(): boolean
		return w.window or (not sandbox and w.phone)
	end
	rig.windowOpen = function(): boolean
		return w.window
	end
	rig.freeLook = function(): boolean
		return not sandbox and w.phone and not w.window
	end
	if sandbox then
		rig.aimOnly = true
		rig.armed = rig.toolEquipped
	end
	rig.start()
	rig.setEnabled(true)
	w.rig = rig
	return w
end

local function frame(w: World, n: number?)
	for _ = 1, n or 1 do
		clock += w.dt
		local step = w.render.ZombieDeliveryCamera
		if step then
			step(w.dt)
		end
	end
end

local function press(w: World, kind: string, key: string?, processed: boolean?)
	w.uis.InputBegan:Fire({ UserInputType = kind, KeyCode = key or "Unknown" }, processed == true)
end
local function release(w: World, kind: string, key: string?)
	w.uis.InputEnded:Fire({ UserInputType = kind, KeyCode = key or "Unknown" }, false)
end
local function moveMouse(w: World, dx: number, dy: number)
	w.uis.InputChanged:Fire({ UserInputType = "MouseMovement", Delta = Vector3.new(dx, dy, 0) }, false)
end
local function wheel(w: World, z: number, processed: boolean?)
	w.uis.InputChanged:Fire({ UserInputType = "MouseWheel", Position = Vector3.new(0, 0, z) }, processed == true)
end

-- Where the camera looks along the ground (radians, Roblox's yaw: 0 looks down -Z).
local function yawOf(w: World): number
	local look = w.camera.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end
local function turned(a: number, b: number): number
	return math.abs((b - a + math.pi) % (2 * math.pi) - math.pi)
end
local function distance(w: World): number
	return (w.camera.CFrame.Position - w.root.Position).Magnitude
end
local function dot(w: World): any
	local gui = w.player:FindFirstChild("PlayerGui")
	local crosshair = gui and gui:FindFirstChild("Crosshair")
	return crosshair and crosshair:FindFirstChild("Dot")
end
local function aimed(w: World): boolean -- the last word to the server: the gun arm up
	local last = nil
	for _, entry in w.sent do
		if entry[1] == "Aiming" then
			last = entry[2]
		end
	end
	return last == true
end
local function free(w: World): boolean
	local d = dot(w)
	return not w.rig.locked() and w.uis.MouseBehavior == "Default" and w.uis.MouseIconEnabled == true and d ~= nil and d.Visible == false
end
local function lockedAiming(w: World): boolean
	local d = dot(w)
	return w.rig.locked() and w.uis.MouseBehavior == "LockCenter" and w.uis.MouseIconEnabled == false and d ~= nil and d.Visible == true
end

local SENSITIVITY = 0.0032 -- (the rig's: a mouse's px to radians)

-- ── The sandbox ─────────────────────────────────────────────────────────────

do
	local w = world(true)
	frame(w)
	check("sandbox: the cursor is free by default (MouseBehavior Default, shown, no crosshair dot)", free(w),
		`{w.uis.MouseBehavior} {w.uis.MouseIconEnabled}`)
	check("… the rig still drives the camera (Scriptable: the walk goes the camera's way), the body turns where it walks",
		w.camera.CameraType == "Scriptable" and w.humanoid.AutoRotate == true)
	check("… the hooks as Main sets them: aimOnly, armed = a Tool equipped", w.rig.aimOnly == true and w.rig.armed == w.rig.toolEquipped and not w.rig.armed())
	local before = yawOf(w)
	moveMouse(w, 200, 40)
	frame(w)
	check("… a mouse move turns nothing", turned(before, yawOf(w)) < 1e-6, turned(before, yawOf(w)))

	-- the right mouse held turns the camera, like Roblox's own
	press(w, "MouseButton2")
	frame(w)
	check("the right mouse held: the mouse held in place to turn the camera (LockCurrentPosition), the cursor shown, no dot",
		w.uis.MouseBehavior == "LockCurrentPosition" and w.uis.MouseIconEnabled == true and not dot(w).Visible and not w.rig.locked())
	before = yawOf(w)
	moveMouse(w, -100, 0)
	frame(w)
	check("… a mouse move turns the camera (100 px left: the same turn as the city's)", math.abs(turned(before, yawOf(w)) - 100 * SENSITIVITY) < 1e-3,
		turned(before, yawOf(w)))
	check("… and aims nothing (no Aiming to the server, the walk's speed kept, the body still turns where it walks)", not aimed(w)
		and math.abs(w.humanoid.WalkSpeed - Config.Movement.Walk) < 1e-6 and w.humanoid.AutoRotate == true and not (w.rig.aimPose()), w.humanoid.WalkSpeed)
	release(w, "MouseButton2")
	frame(w)
	before = yawOf(w)
	moveMouse(w, 150, 0)
	frame(w)
	check("let go: free again, a mouse move turns nothing", free(w) and turned(before, yawOf(w)) < 1e-6)

	-- a left click is the world's
	press(w, "MouseButton1")
	frame(w, 5)
	check("a left click (held): no shot, no aim, the cursor stays free", not aimed(w) and not (w.rig.aimPose()) and free(w))
	release(w, "MouseButton1")
	frame(w)

	-- Alt and the MOUSE button do nothing here
	press(w, "Keyboard", "LeftAlt")
	frame(w)
	check("Alt held: nothing changes (still free)", free(w))
	release(w, "Keyboard", "LeftAlt")
	w.rig.toggleFreeMouse()
	frame(w)
	check("… nor does the city's MOUSE button (client/Hud.luau hides it here): still free", free(w))
	w.rig.toggleFreeMouse()

	-- the wheel zooms, but not under a window or over a list
	frame(w, 30)
	local far = distance(w)
	wheel(w, 3)
	frame(w, 30)
	check("the wheel zooms the camera in", distance(w) < far - 0.5, `{far} → {distance(w)}`)
	far = distance(w)
	wheel(w, 1, true)
	frame(w, 30)
	check("… not when a list under the mouse takes the wheel", math.abs(distance(w) - far) < 1e-6)
	w.window = true
	wheel(w, -3)
	frame(w, 30)
	check("… nor while a window needs the mouse", math.abs(distance(w) - far) < 1e-6)
	press(w, "MouseButton2")
	frame(w)
	before = yawOf(w)
	moveMouse(w, 120, 0)
	frame(w)
	check("a window open: the right mouse turns nothing (the mouse is the window's)", w.uis.MouseBehavior == "Default" and turned(before, yawOf(w)) < 1e-6 and not aimed(w))
	release(w, "MouseButton2")
	w.window = false
	frame(w)

	-- armed: a Tool in the hands brings back the locked mouse and the crosshair
	local tool = E.new("Tool", "Pistol", w.body)
	frame(w)
	check("a Tool equipped (armed): the mouse locked (LockCenter), no cursor, the crosshair dot", lockedAiming(w), w.uis.MouseBehavior)
	before = yawOf(w)
	moveMouse(w, 50, 0)
	frame(w)
	check("… a mouse move turns the camera", math.abs(turned(before, yawOf(w)) - 50 * SENSITIVITY) < 1e-3, turned(before, yawOf(w)))
	press(w, "MouseButton2")
	frame(w, 10)
	check("… the right mouse aims (Aiming to the server, the careful step)", aimed(w) and (w.rig.aimPose()) and w.humanoid.WalkSpeed < Config.Movement.Walk)
	release(w, "MouseButton2")
	frame(w, 60)
	check("… let go: the aim down", not aimed(w))
	tool:Destroy()
	frame(w)
	check("put away: free again (the cursor, no dot)", free(w))
	w.rig.armed = function(): boolean
		return true
	end
	frame(w)
	check("another armed hook (Main's, guns brought later) decides alone: locked with the dot", lockedAiming(w))
	w.window = true
	frame(w)
	check("… a window open frees the mouse even then", not w.rig.locked() and w.uis.MouseBehavior == "Default" and not dot(w).Visible)
	w.window = false
	w.rig.armed = w.rig.toolEquipped
	frame(w)
	check("… back to a Tool: free", free(w))

	-- driving: the camera follows behind the van with the cursor free
	local car = E.new("Model", "Van", w.workspace)
	local chassis = E.new("Part", "Chassis", car)
	local carYaw = 1.1
	chassis.CFrame = CFrame.new(0, 3, -20) * CFrame.Angles(0, carYaw, 0)
	chassis.Position = chassis.CFrame.Position
	chassis.AssemblyLinearVelocity = Vector3.new(-math.sin(carYaw) * 30, 0, -math.cos(carYaw) * 30)
	chassis.AssemblyAngularVelocity = Vector3.zero
	car.PrimaryPart = chassis
	car.GetExtentsSize = function(): any
		return Vector3.new(7, 8, 18)
	end
	w.car = car
	frame(w, 30)
	for _ = 1, 30 do
		moveMouse(w, 40, 0) -- (the free cursor moving over the screen: not a turn of the camera)
		frame(w, 5)
	end
	local behind = (w.camera.CFrame.Position - chassis.Position):Dot(chassis.CFrame.LookVector)
	check("driving, the cursor free (moving or not): the camera swings round behind the van", turned(yawOf(w), carYaw) < 0.05 and behind < 0 and free(w),
		`{turned(yawOf(w), carYaw)} {behind}`)
	w.car = nil
	frame(w, 30)

	-- a door's trip: the camera behind you, looking the way you go
	check("a door's trip (CameraRig.face): the rig turns the camera", w.rig.face(Vector3.new(1, 0, 0)) == true)
	frame(w)
	check("… it looks the way you go (+X), the cursor still free", turned(yawOf(w), math.atan2(-1, 0)) < 1e-3 and free(w), yawOf(w))
end

-- ── The city: unchanged ─────────────────────────────────────────────────────

do
	local w = world(false)
	frame(w)
	check("city: aimOnly never set (Main's sandbox block only)", w.rig.aimOnly == false)
	check("city: the mouse locked as before (LockCenter, no cursor, the crosshair dot)", lockedAiming(w), w.uis.MouseBehavior)
	local before = yawOf(w)
	moveMouse(w, 100, 0)
	frame(w)
	check("… a mouse move turns the camera", math.abs(turned(before, yawOf(w)) - 100 * SENSITIVITY) < 1e-3)
	press(w, "Keyboard", "LeftAlt")
	frame(w)
	check("… Alt held frees it (Default, the cursor, no dot)", free(w))
	before = yawOf(w)
	moveMouse(w, 100, 0)
	frame(w)
	check("… and the mouse turns nothing then", turned(before, yawOf(w)) < 1e-6)
	release(w, "Keyboard", "LeftAlt")
	frame(w)
	check("… Alt let go: locked again", lockedAiming(w))
	check("… the MOUSE button frees it", w.rig.toggleFreeMouse() == true)
	frame(w)
	check("… (free: the cursor, no dot)", free(w))
	check("… clicked again: locked", w.rig.toggleFreeMouse() == false)
	frame(w)
	check("… (locked with the dot)", lockedAiming(w))
	w.phone = true
	frame(w)
	press(w, "MouseButton2")
	frame(w)
	before = yawOf(w)
	moveMouse(w, -80, 0)
	frame(w)
	check("the phone open (freeLook): the right mouse turns the camera (LockCurrentPosition), no aim", w.uis.MouseBehavior == "LockCurrentPosition"
		and math.abs(turned(before, yawOf(w)) - 80 * SENSITIVITY) < 1e-3 and not aimed(w))
	release(w, "MouseButton2")
	w.phone = false
	frame(w)
	press(w, "MouseButton2")
	frame(w, 10)
	check("the phone away: the right mouse aims (Aiming, the careful step)", aimed(w) and w.humanoid.WalkSpeed < Config.Movement.Walk)
	release(w, "MouseButton2")
	frame(w, 60)
	press(w, "MouseButton1")
	frame(w, 10)
	check("… the left mouse shoots with the gun up (Aiming)", aimed(w))
	release(w, "MouseButton1")
	frame(w, 60)
	E.new("Tool", "Pistol", w.body)
	frame(w)
	check("a Tool changes nothing in the city (still locked with the dot)", lockedAiming(w))
	w.window = true
	frame(w)
	check("a window open frees the mouse as before", free(w))
end

-- ── A touch screen: the Roblox camera as before ─────────────────────────────

do
	local w = world(true, true)
	check("a touch screen: the rig never binds its camera step (the Roblox camera), its feel step only", w.render.ZombieDeliveryCamera == nil
		and w.render.ZombieDeliveryFeel ~= nil)
	check("… the mouse is never locked there", not w.rig.locked() and w.uis.MouseBehavior == "Default")
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
