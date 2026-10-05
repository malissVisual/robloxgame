--!strict
-- 3.10: getting in and out of a car, on your own client (you own your character's physics, so the move you play here
-- is what everybody sees). The timing and the curves are shared/Boarding.luau, the numbers Config.Cargo.
--
-- Getting in: E at a door → the server (server/Vehicles.luau) reserves the seat and sets your character's Boarding
-- ("ownerId:door:seat") and BoardAt. From then this module moves the root in the car's own space (so a car that rolls
-- a little carries the move along): a step to the door's handle facing the car (the hand goes to it: client/
-- ArmPose.luau; the door swings open: client/CarVisuals.luau), then a slide in through the door to the seat, ducking
-- on the way (a doorless seat: a short climb in an arc). The whole move ends when the server seats you, BoardAt +
-- BoardSeconds (it started late by the attribute's trip, so it plays a little quicker). Meanwhile your controls are
-- off, the humanoid stands still (PlatformStand) and the body passes through the car (the collision group
-- "Boarding"). Seated, everything comes back; the Boarding attribute gone without a seat (cancelled: the car left,
-- the seat was gone…) you stand at the door with the controls back.
--
-- Getting out: E in a car seat (the CarDoor remote; the server unseats you), Space (the seat's own jump) or an eject:
-- the door opens at once, the body slides out to your door's side in AlightSeconds and the controls come back.
-- Out of a fast car (Config.Cargo.AlightSlideMaxSpeed) you are put out at the door at once, as before.
--
-- E in a seat: while you sit in a car the other prompts around you are hidden (the door prompts and the back's already
-- are, client/CarVisuals.luau), so E means "get out"; a prompt meant for a driver (the 🅿 GARAGE posts, or any prompt
-- with the attribute Seated = true) keeps E while it shows, and Space gets you out then. Gamepad: X (the prompts'
-- button).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boarding = require(Shared:WaitForChild("Boarding"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Drive = require(script.Parent.Drive)

local CarBoarding = {}

local player = Players.LocalPlayer
local GROUP = "Boarding"
local EXIT_ACTION = "ZombieDeliveryCarExit"
local MIN_SPAN = 0.2 -- the move to get in never plays quicker than this
local HOLD = 1.2 -- after the move, waiting this long for the seat; then back out at the door
local OUT_EXTRA = 0.6 -- getting out you end this far beyond the door's stand point

type Move = {
	kind: string, -- "board" | "alight"
	car: Model,
	chassis: BasePart,
	root: BasePart,
	humanoid: Humanoid,
	from: CFrame, -- all in the chassis' space: where the root started
	stand: CFrame, -- at the door, facing the car (getting out: where you end, facing away)
	to: CFrame, -- the seat (getting out: = stand)
	side: number, -- -1 left, 1 right
	outside: number, -- the body's half width at the door
	climb: boolean, -- a seat with no door: an arc, no handle
	started: number, -- os.clock()
	span: number, -- seconds this client plays the move over
	total: number, -- the move's own length (BoardSeconds / AlightSeconds)
	value: number?, -- getting in: the BoardAt it plays
}

local move: Move? = nil
local frozen = false
local savedGroups: { [BasePart]: string } = {}
local controls: any = nil -- the PlayerModule's controls (false: none found)
local seatedIn: BasePart? = nil -- the car seat you sit in (Humanoid.Seated)
local lastExit = 0
-- The prompts that show to you now, and the ones hidden here while you sit in a car.
local shown: { [ProximityPrompt]: boolean } = {}
local muted: { [ProximityPrompt]: number } = {} -- each muted prompt's own reach (put back on the way out)
local CAR_PROMPTS: { [string]: boolean } = { DrivePrompt = true, RidePrompt = true, BackPrompt = true }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getControls(): any
	if controls == nil then
		local ok, result = pcall(function(): any
			local scripts = player:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			if module and module:IsA("ModuleScript") then
				return (require(module) :: any):GetControls()
			end
			return nil
		end)
		controls = if ok and result then result else false
	end
	return if controls then controls else nil
end

-- Controls off, no humanoid forces, through the car's shell (or all of it back).
local function freeze(character: Model, humanoid: Humanoid, on: boolean)
	if on == frozen then
		return
	end
	frozen = on
	local c = getControls()
	if c then
		pcall(function()
			if on then
				c:Disable()
			else
				c:Enable()
			end
		end)
	end
	if humanoid.Parent then
		humanoid.PlatformStand = on
	end
	if on then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				savedGroups[d] = d.CollisionGroup
				pcall(function()
					d.CollisionGroup = GROUP
				end)
			end
		end
	else
		for part, group in savedGroups do
			if part.Parent then
				part.CollisionGroup = group
			end
		end
		table.clear(savedGroups)
	end
end

local function carOf(ownerId: number): Model?
	local folder = workspace:FindFirstChild("Cars")
	if not folder then
		return nil
	end
	for _, car in folder:GetChildren() do
		if car:IsA("Model") and car:GetAttribute("OwnerId") == ownerId then
			return car
		end
	end
	return nil
end

local function seatOf(car: Model, seatNo: number): BasePart?
	for _, child in car:GetChildren() do
		if seatNo == 0 and child:IsA("VehicleSeat") and child.Name == "DriverSeat" then
			return child
		elseif seatNo > 0 and child:IsA("Seat") and child:GetAttribute("Index") == seatNo then
			return child
		end
	end
	return nil
end

-- A door's attachment (Door{n}, the prompt's place just outside it) and whether it has a panel that swings.
local function doorOf(chassis: BasePart, index: number): (Attachment?, boolean)
	local at = chassis:FindFirstChild(`Door{index}`)
	local panel = false
	for _, child in chassis:GetChildren() do
		if child.Name == "DoorHinge" and child:GetAttribute("Door") == index then
			panel = true
			break
		end
	end
	return if at and at:IsA("Attachment") then at else nil, panel
end

-- The root's height over the ground, standing.
local function standHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2
end

-- Where you stand at a door (in the chassis' space): `extra` studs beyond its attachment, on the ground, facing `look`
-- (chassis space, flat).
local function standAt(chassis: BasePart, at: Attachment, side: number, extra: number, humanoid: Humanoid, root: BasePart, character: Model, car: Model, look: Vector3): CFrame
	local frame = chassis.CFrame
	local a = at.Position
	local spot = Vector3.new(a.X + side * extra, a.Y, a.Z)
	local world = frame * spot
	local exclude: { Instance } = { character, car }
	for _, name in { "Cars", "Zombies", "Npcs", "Traffic", "Animals", "Loot", "LocalEffects" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(world + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rayParams)
	local y = if hit then frame:PointToObjectSpace(Vector3.new(world.X, hit.Position.Y + standHeight(humanoid, root), world.Z)).Y else spot.Y + 1
	local position = Vector3.new(spot.X, y, spot.Z)
	return CFrame.lookAt(position, position + look)
end

-- The pose on the way in, t seconds into the move (chassis space).
local function boardPose(m: Move, t: number): CFrame
	local phase, u = Boarding.boardPhase(t)
	if phase == "step" then
		return m.from:Lerp(m.stand, u)
	end
	local a, c = m.stand.Position, m.to.Position
	local bx, by, bz = Boarding.through(m.side, m.outside, a.Y, a.Z, c.Y, m.climb)
	local position = Vector3.new(Boarding.bezier(a.X, bx, c.X, u), Boarding.bezier(a.Y, by, c.Y, u), Boarding.bezier(a.Z, bz, c.Z, u))
	return CFrame.new(position) * m.stand.Rotation:Lerp(m.to.Rotation, u) * CFrame.Angles(-Boarding.duck(u), 0, 0)
end

-- The pose on the way out (chassis space).
local function alightPose(m: Move, t: number): CFrame
	local u = Boarding.ease(t / math.max(1e-3, m.total))
	local a, c = m.from.Position, m.to.Position
	local bx, by, bz = Boarding.through(m.side, m.outside, a.Y, c.Z, c.Y, m.climb)
	local position = Vector3.new(Boarding.bezier(a.X, bx, c.X, u), Boarding.bezier(a.Y, by, c.Y, u), Boarding.bezier(a.Z, bz, c.Z, u))
	return CFrame.new(position) * m.from.Rotation:Lerp(m.to.Rotation, u) * CFrame.Angles(-Boarding.duck(u), 0, 0)
end

-- The move ends: `at` (chassis space) is where the root stays (nil: where it is); the controls come back.
local function stop(at: CFrame?)
	local m = move
	move = nil
	Drive.setBoarding(nil, false)
	if not m then
		return
	end
	if at and m.chassis.Parent and m.root.Parent and not m.humanoid.SeatPart then
		m.root.CFrame = m.chassis.CFrame * at
		m.root.AssemblyLinearVelocity = Vector3.zero
	end
	local character = m.humanoid.Parent
	if character and character:IsA("Model") then
		freeze(character, m.humanoid, false)
	else
		frozen = false
		table.clear(savedGroups)
	end
end

-- The server says: into a seat (the Boarding / BoardAt attributes).
local function beginBoard(character: Model, humanoid: Humanoid)
	local ownerId, door, seatNo = Boarding.decode(character:GetAttribute("Boarding"))
	local value = character:GetAttribute("BoardAt")
	local root = humanoid.RootPart
	if not ownerId or not door or not seatNo or type(value) ~= "number" or not root or humanoid.SeatPart then
		return
	end
	local current = move
	if current and current.kind == "board" and current.value == value then
		return
	end
	local car = carOf(ownerId)
	local chassis = car and car.PrimaryPart
	local seat = car and seatOf(car, seatNo)
	if not car or not chassis or not seat then
		return
	end
	local at, panel = doorOf(chassis, door)
	if not at then
		return
	end
	local cfg = Config.Cargo
	local frame = chassis.CFrame
	local side = if at.Position.X >= 0 then 1 else -1
	local stand = standAt(chassis, at, side, 0, humanoid, root, character, car, Vector3.new(-side, 0, 0))
	local to = frame:ToObjectSpace(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + cfg.BoardSitLift, 0))
	local late = workspace:GetServerTimeNow() - value
	move = {
		kind = "board",
		car = car,
		chassis = chassis,
		root = root,
		humanoid = humanoid,
		from = frame:ToObjectSpace(root.CFrame),
		stand = stand,
		to = to,
		side = side,
		outside = math.max(0, math.abs(at.Position.X) - cfg.DoorStandOut),
		climb = not panel,
		started = os.clock(),
		span = Boarding.span(late, cfg.BoardSeconds, MIN_SPAN),
		total = cfg.BoardSeconds,
		value = value,
	}
	Drive.setBoarding(car, true)
	freeze(character, humanoid, true)
end

-- Out of a car seat (any way): the slide out at the seat's door.
local function beginAlight(character: Model, humanoid: Humanoid, seat: BasePart)
	local car = seat.Parent
	local root = humanoid.RootPart
	if not car or not car:IsA("Model") or not seat:IsDescendantOf(workspace) or not root or humanoid.Health <= 0 then
		return
	end
	if car:GetAttribute("OwnerId") == nil then
		return
	end
	local chassis = car.PrimaryPart
	local index = seat:GetAttribute("Door")
	if not chassis or type(index) ~= "number" then
		return
	end
	local at, panel = doorOf(chassis, index)
	if not at then
		return
	end
	local cfg = Config.Cargo
	local side = if at.Position.X >= 0 then 1 else -1
	local look = Vector3.new(side * 0.7, 0, -1).Unit -- out and toward the front
	local out = standAt(chassis, at, side, OUT_EXTRA, humanoid, root, character, car, look)
	local v = chassis.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude > cfg.AlightSlideMaxSpeed then
		-- Out of a moving car: at the door at once (it would drag you along otherwise).
		root.CFrame = chassis.CFrame * out
		return
	end
	if panel then
		Drive.holdDoor(car, index, cfg.AlightSeconds + 0.05)
	end
	move = {
		kind = "alight",
		car = car,
		chassis = chassis,
		root = root,
		humanoid = humanoid,
		from = chassis.CFrame:ToObjectSpace(root.CFrame),
		stand = out,
		to = out,
		side = side,
		outside = math.max(0, math.abs(at.Position.X) - cfg.DoorStandOut),
		climb = not panel,
		started = os.clock(),
		span = cfg.AlightSeconds,
		total = cfg.AlightSeconds,
		value = nil,
	}
	Drive.setBoarding(car, false)
	freeze(character, humanoid, true)
end

local function step(dt: number)
	local m = move
	if not m then
		return
	end
	if not m.chassis.Parent or not m.root.Parent or m.humanoid.Health <= 0 then
		stop(nil)
		return
	end
	local since = os.clock() - m.started
	if m.kind == "board" then
		if m.humanoid.SeatPart then
			stop(nil) -- seated: the seat holds you now
			return
		elseif since >= m.span + HOLD then
			stop(m.stand) -- no seat came: back at the door
			return
		end
	elseif since >= m.span then
		stop(m.to)
		return
	end
	if (m.root.Position - m.chassis.Position).Magnitude > 40 then
		stop(nil) -- moved far away meanwhile (a teleport): no slide back to the car
		return
	end
	local t = Boarding.moveTime(since, m.span, m.total)
	local pose = if m.kind == "board" then boardPose(m, t) else alightPose(m, t)
	m.root.CFrame = m.chassis.CFrame * pose
	-- Carried along with the car, and gravity cancelled over this step (the next frame sets it again anyway).
	m.root.AssemblyLinearVelocity = m.chassis.AssemblyLinearVelocity + Vector3.new(0, workspace.Gravity * dt * 0.5, 0)
	m.root.AssemblyAngularVelocity = Vector3.zero
end

-- ── E in a seat ────────────────────────────────────────────────────────────

local function seatedUse(prompt: ProximityPrompt): boolean
	return prompt.Name == "GaragePrompt" or prompt:GetAttribute("Seated") == true
end

local function mute(prompt: ProximityPrompt)
	if muted[prompt] or CAR_PROMPTS[prompt.Name] or seatedUse(prompt) or not prompt.Enabled then
		return
	end
	-- Hidden through its reach, never through Enabled: the server switches Enabled (an emptied pile, a shut back,
	-- a pulled lever) while you sit, and turning it back on afterwards would show a prompt it had turned off.
	muted[prompt] = prompt.MaxActivationDistance
	prompt.MaxActivationDistance = 0
end

local function unmuteAll()
	for prompt, reach in muted do
		if prompt.Parent and prompt.MaxActivationDistance == 0 then
			prompt.MaxActivationDistance = reach
		end
	end
	table.clear(muted)
end

-- A prompt for drivers shows: E is its (Space still gets you out).
local function seatedPromptShown(): boolean
	for prompt in shown do
		if prompt.Parent and prompt.Enabled and seatedUse(prompt) then
			return true
		end
	end
	return false
end

local function onExit(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not seatedIn or UserInputService:GetFocusedTextBox() or seatedPromptShown() then
		return Enum.ContextActionResult.Pass
	end
	local now = os.clock()
	if now - lastExit >= 0.4 then
		lastExit = now
		Net.get("CarDoor"):FireServer("out")
	end
	return Enum.ContextActionResult.Sink
end

local function inCarSeat(seat: BasePart?): boolean
	local car = seat and seat.Parent
	return car ~= nil and car:IsA("Model") and car:GetAttribute("OwnerId") ~= nil
end

local function onSeated(character: Model, humanoid: Humanoid, active: boolean, seat: BasePart?)
	if active then
		if move then
			stop(nil) -- in the seat (or sat down again while getting out: the seat wins)
		end
		if seat and inCarSeat(seat) then
			seatedIn = seat
			for prompt in shown do
				mute(prompt)
			end
			ContextActionService:BindActionAtPriority(EXIT_ACTION, onExit, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		end
		return
	end
	local left = seatedIn
	seatedIn = nil
	ContextActionService:UnbindAction(EXIT_ACTION)
	unmuteAll()
	if left then
		beginAlight(character, humanoid, left)
	end
end

local function watchCharacter(character: Model)
	-- A new body: whatever the old one was doing is over.
	if frozen then
		frozen = false
		table.clear(savedGroups)
		local c = getControls()
		if c then
			pcall(function()
				c:Enable()
			end)
		end
	end
	move = nil
	seatedIn = nil
	Drive.setBoarding(nil, false)
	ContextActionService:UnbindAction(EXIT_ACTION)
	unmuteAll()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seat: BasePart?)
		onSeated(character, humanoid, active, seat)
	end)
	character:GetAttributeChangedSignal("Boarding"):Connect(function()
		if character:GetAttribute("Boarding") ~= nil then
			beginBoard(character, humanoid)
			return
		end
		-- Gone: seated (the move already ended) or cancelled (stand at the door).
		local m = move
		if m and m.kind == "board" then
			stop(if humanoid.SeatPart then nil else m.stand)
		end
	end)
	if character:GetAttribute("Boarding") ~= nil then
		beginBoard(character, humanoid)
	elseif humanoid.SeatPart then
		onSeated(character, humanoid, true, humanoid.SeatPart) -- seated before this was listening (PLAY, a respawn)
	end
end

function CarBoarding.start()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		shown[prompt] = true
		if seatedIn then
			mute(prompt)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		shown[prompt] = nil
	end)
	player.CharacterAdded:Connect(function(character)
		task.spawn(watchCharacter, character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	-- Before the physics step, like the poses (client/ArmPose.luau): what is set here is what is simulated and sent.
	RunService.PreSimulation:Connect(step)
end

return CarBoarding
