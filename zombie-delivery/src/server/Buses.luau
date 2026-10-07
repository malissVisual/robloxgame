--!strict
-- 5.5, the city buses: free rides on the three loops of shared/BusLines.luau (Config.Bus), one set for the whole
-- server, seen by everybody.
--
-- The buses. Each line's `buses` drive its loop evenly spaced, on the timetable BusLines.position works out from
-- workspace:GetServerTimeNow(). They are anchored bus bodies (Vehicles.buildBus: the traffic's bus with its passenger
-- seats, the line's stripe and its number and name on the board over the windscreen) in workspace.Buses; the server
-- sets each one's CFrame 10 times a second (TICK, like server/Traffic.luau), and every client places the buses near
-- it on every frame from the same timetable (client/BusRide.luau), so a ride is smooth and the seated riders (welded
-- to their seats) glide with the bus. The model carries BusLine (the line id), BusIndex (0-based), BusOffset (the
-- chassis over its point on the road), BusNext (the next stop's name) and BusAt (the stop it stands at, nil driving).
--
-- Never running anybody over, simply: a bus keeps to its timetable (it ignores the lights and the traffic, so every
-- client agrees where it is) and NOTHING of it collides (CanCollide off on every part): a person in its way is
-- passed through, never pushed or flung, and nobody can block it. The traffic gives way to it instead: its cars stop
-- for a bus in their lane like for any car (server/Traffic.luau reads workspace.Buses). The riders' bodies are put
-- in the collision group BusRider (nothing collides with it) while they sit, so they do not shove anybody either.
--
-- Getting on: a "Board" prompt at the front-right door while the bus stands at a stop (Dwell seconds, Config.Bus).
-- On foot only (not out of a car or off a bike, not mid-boarding, not pushing a trolley), never during a mission,
-- and the hands must go into the backpack (Cargo.canStowHands; Cargo.update stows them as you sit, like on a bike):
-- else "Your hands are full: no room in the backpack". A free passenger seat → Seat:Sit. Free of charge.
-- 5.7: not at once: the seat is kept for you and your character marked (BusBoard = "line:index:seat", BusBoardAt = the
-- server time), your own client walks you in (to the door, up its step, along the aisle, sit: client/BusRide.luau,
-- Config.Interact.BusBoard; everybody's clients pose it, the folding door opens for it) and THIS server seats you
-- (Seat:Sit) BusBoard seconds after the Board, when you are still alive, standing and the seat free (else the seat is
-- let go and you are put on the kerb, like getting off).
-- Riding: the player attribute BusLine (the line's id) while you ride. The Bus remote's "stop": while it drives, the
-- bell (BusBell: the next stop's name; you get off there); while it stands at a stop, off now. Getting off at a stop:
-- 5.7, your client walks you out (up from the seat, along the aisle, down the door's step onto the kerb: the
-- character's BusOff = "line:index", BusOffAt and BusOffTo, the kerb by the door) in Config.Interact.BusAlight; the
-- server puts you on that kerb when you are not there BusAlightGrace later. Jumping is switched off on the client
-- while you ride; leaving the seat any other way mid-ride (alive) lands you on the kerb beside the bus at once.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BusLines = require(Shared.BusLines)
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)
local Cargo = require(script.Parent.Cargo)
local Jobs = require(script.Parent.Jobs)

local Buses = {}

local Tuning = Config.Bus
local TICK = 0.1
local RIDER_GROUP = "BusRider"
local SIT_GRACE = 0.6 -- seconds for a new rider's seat to report them
local SAME_PRESS = 0.3 -- the Bus remote, at most this often per player
local DOOR_OUT = 1.6 -- the Board prompt: this far out of the bus's side, by the door
local KERB_NEAR = 3 -- 5.7: somebody getting off within this of the kerb's spot by then stays where they are

type Bus = {
	line: BusLines.Line,
	index: number, -- 0-based
	model: Model,
	chassis: BasePart,
	offset: CFrame, -- the chassis over its point on the road
	seats: { Seat },
	prompt: ProximityPrompt,
	lights: { SpotLight },
	at: number, -- the stop it stands at (0: driving)
	nextStop: number,
	leaveIn: number,
}

type Rider = {
	bus: Bus,
	seat: Seat,
	humanoid: Humanoid,
	character: Model,
	since: number,
	bell: boolean,
	groups: { [BasePart]: string },
}

local buses: { Bus } = {}
local riders: { [Player]: Rider } = {}
local lastPress: { [Player]: number } = {}
local started = false

local function tell(player: Player, text: string)
	Net.get("Notice"):FireClient(player, text)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function groundFrame(x: number, z: number, hx: number, hz: number): CFrame
	local at = Vector3.new(x, Map.RoadTop, z)
	if hx * hx + hz * hz < 1e-6 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, at + Vector3.new(hx, 0, hz))
end

local function isNight(): boolean
	return workspace:GetAttribute("Night") == true
end

-- ── Building ───────────────────────────────────────────────────────────────

local function busDef(): Config.CarDef?
	for _, def in Config.Cars do
		if def.style == "bus" then
			return def
		end
	end
	return nil
end

-- The line's number on its colour and its name, on the board over the windscreen.
local function writeSign(board: BasePart, line: BusLines.Line)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LineSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = board
	local number = Instance.new("TextLabel")
	number.Size = UDim2.new(0, 64, 1, -8)
	number.Position = UDim2.fromOffset(6, 4)
	number.BackgroundColor3 = rgb(line.color)
	number.BorderSizePixel = 0
	number.Text = tostring(line.id)
	number.TextColor3 = Color3.new(1, 1, 1)
	number.Font = Enum.Font.GothamBold
	number.TextScaled = true
	number.Parent = gui
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -84, 1, -8)
	name.Position = UDim2.fromOffset(78, 4)
	name.BackgroundTransparency = 1
	name.Text = string.upper(line.name)
	name.TextColor3 = Color3.fromRGB(255, 196, 70)
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = gui
end

local function build(parent: Instance, def: Config.CarDef, line: BusLines.Line, index: number): Bus?
	local now = workspace:GetServerTimeNow()
	local x, z, hx, hz, _, _, leaveIn = BusLines.position(line, index, now)
	local ground = groundFrame(x, z, hx, hz)
	local ok, built, board = pcall(Vehicles.buildBus, def, ground, rgb(Tuning.BodyColor), rgb(line.color))
	if not ok then
		warn(`[Buses] no bus for line {line.id}: {built}`)
		return nil
	end
	local model, chassis = built.model, built.chassis
	model.Name = `Bus {line.id} · {line.name}`
	model:SetAttribute("Traffic", nil)
	model:SetAttribute("CargoCount", nil)
	built.linear:Destroy()
	built.angular:Destroy()
	local root = chassis:FindFirstChild("Root")
	if root then
		root:Destroy()
	end
	writeSign(board, line)
	local lights: { SpotLight } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "WheelCollider" then
				d:Destroy()
				continue
			end
			d.CanCollide = false -- never pushes anybody (see the header)
			d.CanTouch = false
		elseif d:IsA("SpotLight") then
			table.insert(lights, d)
			d.Enabled = isNight()
		end
	end
	chassis.Anchored = true
	-- The door's prompt, out of the front-right side.
	local door = Instance.new("Attachment")
	door.Name = "BusDoor"
	door.Position = Vector3.new(built.size.X / 2 + DOOR_OUT, 2, -BusLines.DoorAhead)
	door.Parent = chassis
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = `Board · Line {line.id}`
	prompt.ObjectText = `{line.name} · free`
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Tuning.Reach
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Enabled = false
	prompt:SetAttribute("BusLine", line.id)
	prompt.Parent = door
	model:SetAttribute("BusLine", line.id)
	model:SetAttribute("BusIndex", index)
	model:SetAttribute("BusColor", rgb(line.color))
	local bus: Bus = {
		line = line,
		index = index,
		model = model,
		chassis = chassis,
		offset = ground:ToObjectSpace(chassis.CFrame),
		seats = built.seats,
		prompt = prompt,
		lights = lights,
		at = -1, -- (the first step writes the attributes)
		nextStop = 0,
		leaveIn = leaveIn,
	}
	model:SetAttribute("BusOffset", bus.offset)
	model.Parent = parent
	return bus
end

-- ── Riders ─────────────────────────────────────────────────────────────────

local function freeSeat(bus: Bus): Seat?
	for _, seat in bus.seats do
		if seat.Parent and seat.Occupant == nil then
			local taken = false
			for _, rider in riders do
				if rider.seat == seat then
					taken = true
				end
			end
			if not taken then
				return seat
			end
		end
	end
	return nil
end

local function setGroups(rider: Rider)
	for _, d in rider.character:GetDescendants() do
		if d:IsA("BasePart") then
			rider.groups[d] = d.CollisionGroup
			d.CollisionGroup = RIDER_GROUP
		end
	end
end

local function restoreGroups(rider: Rider)
	for part, group in rider.groups do
		if part.Parent and part.CollisionGroup == RIDER_GROUP then
			part.CollisionGroup = group
		end
	end
	table.clear(rider.groups)
end

-- Where the character stands on the kerb at (x, z) (its root), facing (fx, fz).
local function kerbFrame(humanoid: Humanoid, root: BasePart, x: number, z: number, fx: number, fz: number): CFrame
	local lift = humanoid.HipHeight + root.Size.Y / 2 + 0.3
	local at = Vector3.new(x, Map.WalkTop + lift, z)
	return CFrame.lookAt(at, at + Vector3.new(fx, 0, fz))
end

-- Stands the character on the kerb at (x, z), facing (fx, fz).
local function standAt(character: Model, humanoid: Humanoid, x: number, z: number, fx: number, fz: number)
	local root = humanoid.RootPart
	if not root then
		return
	end
	character:PivotTo(kerbFrame(humanoid, root, x, z, fx, fz))
end

local function forget(player: Player)
	local rider = riders[player]
	if not rider then
		return
	end
	riders[player] = nil
	restoreGroups(rider)
	if player.Parent then
		player:SetAttribute("BusLine", nil)
		player:SetAttribute("BusBell", nil)
	end
end

-- Off the bus onto the kerb: at a stop by its door, else beside the bus (a jump, an eject mid-ride). 5.7, walk: at a
-- stop the player's client walks them out first (see the top); the kerb is theirs only if they are not on it by then.
local function land(rider: Rider, walk: boolean?)
	local bus = rider.bus
	local humanoid = rider.humanoid
	local character = rider.character
	if not character.Parent or humanoid.Health <= 0 then
		return
	end
	local stop = if bus.at > 0 then bus.line.stops[bus.at] else nil
	local root = humanoid.RootPart
	if stop and walk and root then
		local spot = kerbFrame(humanoid, root, stop.kx + stop.nx * 1.5, stop.kz + stop.nz * 1.5, stop.nx, stop.nz)
		local now = workspace:GetServerTimeNow()
		local tuning = Config.Interact
		character:SetAttribute("BusOff", `{bus.line.id}:{bus.index}`)
		character:SetAttribute("BusOffTo", spot.Position)
		character:SetAttribute("BusOffAt", now)
		task.delay(tuning.BusAlight + tuning.BusAlightGrace, function()
			if character:GetAttribute("BusOffAt") ~= now then
				return
			end
			character:SetAttribute("BusOff", nil)
			character:SetAttribute("BusOffTo", nil)
			character:SetAttribute("BusOffAt", nil)
			local stillRoot = humanoid.RootPart
			if character.Parent and humanoid.Health > 0 and humanoid.SeatPart == nil and stillRoot
				and (stillRoot.Position - spot.Position).Magnitude > KERB_NEAR then
				stillRoot.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(spot)
			end
		end)
		return
	end
	if stop then
		standAt(character, humanoid, stop.kx + stop.nx * 1.5, stop.kz + stop.nz * 1.5, stop.nx, stop.nz)
		return
	end
	local frame = bus.chassis.CFrame
	local right = frame.RightVector
	local spot = frame.Position + right * (BusLines.HalfWidth + Map.RoadWidth / 4 + 2) - frame.LookVector * (BusLines.DoorAhead - 2)
	standAt(rider.character, humanoid, spot.X, spot.Z, right.X, right.Z)
end

local function getOff(player: Player)
	local rider = riders[player]
	if not rider then
		return
	end
	forget(player)
	local weld = rider.seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	rider.humanoid.Sit = false
	land(rider, true)
end

local function board(player: Player, bus: Bus)
	if riders[player] then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if bus.at <= 0 or bus.leaveIn < Config.Interact.BusBoard + 0.2 then -- 5.7: the walk-in ends before it leaves
		tell(player, "Wait until the bus stops.")
		return
	end
	if humanoid.SeatPart ~= nil or Vehicles.seatedIn(player) ~= nil or character:GetAttribute("Boarding") ~= nil then
		tell(player, "Get out of your vehicle first: the bus is for people on foot.")
		return
	end
	local door = (bus.prompt.Parent :: Attachment).WorldPosition
	if (Vector3.new(root.Position.X - door.X, 0, root.Position.Z - door.Z)).Magnitude > Tuning.Reach + 4 then
		return
	end
	if Jobs.onMission(player) then
		tell(player, "No bus on a mission: they are counting on you.")
		return
	end
	if not Cargo.canStowHands(player) then
		tell(player, "Your hands are full: no room in the backpack.")
		return
	end
	local seat = freeSeat(bus)
	if not seat then
		tell(player, "The bus is full. The next one is right behind it.")
		return
	end
	-- 5.7: the walk in first (the seat is kept meanwhile: freeSeat skips it; checkRiders waits for it)
	local walk = Config.Interact.BusBoard
	local rider: Rider = {
		bus = bus,
		seat = seat,
		humanoid = humanoid,
		character = character,
		since = os.clock() + walk,
		bell = false,
		groups = {},
	}
	riders[player] = rider
	setGroups(rider)
	player:SetAttribute("BusLine", bus.line.id)
	player:SetAttribute("BusBell", nil)
	local at = workspace:GetServerTimeNow()
	local seatNo = seat:GetAttribute("Index")
	character:SetAttribute("BusBoard", `{bus.line.id}:{bus.index}:{if type(seatNo) == "number" then seatNo else 0}`)
	character:SetAttribute("BusBoardAt", at)
	task.delay(walk, function()
		if riders[player] == rider then
			if player.Character == character and humanoid.Health > 0 and humanoid.SeatPart == nil and seat.Parent and seat.Occupant == nil then
				seat:Sit(humanoid)
			else
				-- (it did not work out: the seat is free again, somebody still standing in the bus goes onto the kerb)
				forget(player)
				if player.Character == character and humanoid.Health > 0 and humanoid.SeatPart == nil then
					land(rider)
				end
			end
		end
		-- (the attributes a moment after the seat, so the client sees it seated first)
		task.delay(1, function()
			if character:GetAttribute("BusBoardAt") == at then
				character:SetAttribute("BusBoard", nil)
				character:SetAttribute("BusBoardAt", nil)
			end
		end)
	end)
end

-- The Bus remote: "stop" rings the bell while it drives, gets you off while it stands ("off": the same).
local function onBus(player: Player, action: any)
	if action ~= "stop" and action ~= "off" then
		return
	end
	local now = os.clock()
	if now - (lastPress[player] or 0) < SAME_PRESS then
		return
	end
	lastPress[player] = now
	local rider = riders[player]
	if not rider then
		return
	end
	local bus = rider.bus
	if bus.at > 0 then
		getOff(player)
		return
	end
	if not rider.bell then
		rider.bell = true
		local stop = bus.line.stops[bus.nextStop]
		player:SetAttribute("BusBell", if stop then stop.name else "")
	end
end

-- ── The loop ───────────────────────────────────────────────────────────────

local function arrived(bus: Bus)
	for player, rider in table.clone(riders) do
		if rider.bus == bus and rider.bell then
			getOff(player)
		end
	end
end

local function stepBus(bus: Bus, now: number)
	local x, z, hx, hz, at, nextStop, leaveIn = BusLines.position(bus.line, bus.index, now)
	bus.chassis.CFrame = groundFrame(x, z, hx, hz) * bus.offset
	bus.leaveIn = leaveIn
	if nextStop ~= bus.nextStop then
		bus.nextStop = nextStop
		local stop = bus.line.stops[nextStop]
		bus.model:SetAttribute("BusNext", if stop then stop.name else nil)
	end
	if at ~= bus.at then
		bus.at = at
		local stop = if at > 0 then bus.line.stops[at] else nil
		bus.model:SetAttribute("BusAt", if stop then stop.name else nil)
		if at > 0 then
			arrived(bus)
		end
	end
	local open = at > 0 and leaveIn > Config.Interact.BusBoard + 0.2 and freeSeat(bus) ~= nil
	if bus.prompt.Enabled ~= open then
		bus.prompt.Enabled = open
	end
end

-- Riders who left their seat some other way: died, reset, left the game, or out of the seat mid-ride.
local function checkRiders()
	local clock = os.clock()
	for player, rider in table.clone(riders) do
		if not player.Parent then
			forget(player)
			continue
		end
		local alive = player.Character == rider.character and rider.humanoid.Health > 0
		if alive and (rider.seat.Occupant == rider.humanoid or clock - rider.since < SIT_GRACE) then
			continue
		end
		if not alive then
			-- (a death or a respawn while seated: the seat is freed even if the engine still lists the old body)
			local weld = rider.seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
		end
		forget(player)
		if player.Character == rider.character and rider.humanoid.Health > 0 and rider.humanoid.SeatPart == nil then
			land(rider)
		end
	end
end

function Buses.start()
	if started then
		return
	end
	started = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(RIDER_GROUP)
	end)
	for _, other in { "Default", "Car", "EnemyCar", "Zombie", "Corpse", "Npc", RIDER_GROUP } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(other)
		end)
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, other, false)
		end)
	end
	local def = busDef()
	if not def then
		warn("[Buses] no bus style in Config.Cars: no city buses")
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Buses"
	folder:SetAttribute("Tick", TICK)
	folder.Parent = workspace
	for _, line in BusLines.lines() do
		for index = 0, line.buses - 1 do
			local bus = build(folder, def, line, index)
			if bus then
				table.insert(buses, bus)
				local captured = bus
				bus.prompt.Triggered:Connect(function(player)
					board(player, captured)
				end)
			end
		end
	end
	Net.get("Bus").OnServerEvent:Connect(onBus)
	Players.PlayerRemoving:Connect(function(player)
		forget(player)
		lastPress[player] = nil
	end)
	workspace:GetAttributeChangedSignal("Night"):Connect(function()
		local night = isNight()
		for _, bus in buses do
			for _, light in bus.lights do
				light.Enabled = night
			end
		end
	end)
	print(`[Buses] {#buses} buses on {#BusLines.lines()} lines, {#BusLines.allStops()} stops`)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(function()
				local now = workspace:GetServerTimeNow()
				for _, bus in buses do
					stepBus(bus, now)
				end
				checkRiders()
			end)
			if not ok then
				warn(`[Buses] {err}`)
			end
		end
	end)
end

return Buses
