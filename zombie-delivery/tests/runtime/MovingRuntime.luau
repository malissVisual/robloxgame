--!strict
-- 7.0: the few services and server modules the real server/Moving.luau needs in the Luau CLI (7.0 planning: and the
-- real server/MoveLobby.luau, MoveLobbyServer.luau; the driver's seat, the truck's and the zombies' damage, a garage)
-- (tests/moving_runtime_test.luau through tests/run_tests.py, which builds MovingServer.luau from src/server/Moving.luau
-- with these in place of its requires; Config, Economy, Map and MovingRules are the real ones). The instances are
-- tools/fixtures/item-mock.luau's recorder with signals a test fires (Triggered, Died, HealthChanged …), players and
-- their bodies, a truck, zombies and the house art (fake FurnitureLooks / HouseLayout / HouseInterior shaped like the
-- art branch's interface). No physics: a weld is a record, a teleport sets the root's CFrame. os.clock and the server
-- time are the test's (Runtime.clock, Runtime.now); task.delay runs at once.
-- 7.0, the depot's helper: the real server/MoveHelper.luau (MoveHelperServer.luau, tests/movehelper_runtime_test.luau)
-- runs on these too: its body from the fake Npcs (Runtime.said: what he says), the zombies' roots and Zombies.all.
-- 8.0 SANDBOX: the city's game by default (Config.Sandbox.On false: Moving.start reads it); a sandbox test sets it true
-- before Moving.start (tests/sandboxmove_runtime_test.luau). Its fakes: SandboxPlots (Runtime.plots: player → a
-- SandboxMap plot) and Collection (Runtime.collected: every Collection.add, its uid back unless Runtime.refuse); the
-- test sets server/SandboxBoot.luau's hook Moving.parkVan itself (Runtime.makeCar: a fake car).
-- 8.3 Danny for hire: PlayerData.spend takes from Runtime.wallet (player → money; Runtime.startMoney when not set) and
-- records it (Runtime.spent); a car (not a bike) has its driver's seat and one passenger seat (Seat:Sit puts a humanoid
-- in it: its Occupant, SeatPart, Sit and a SeatWeld), its doors (the driver's on the left, the passenger's on the
-- right) and its size; Vehicles.speed is the car's `speed` (0 unless the test sets it). 8.5 Danny getting in and out
-- like a player: Vehicles.swingDoor records each door swing (Runtime.doorSwings); RunService's Heartbeat (his pose every
-- frame meanwhile) fires only when a test fires it.
local Mock = require("./ItemMock") :: any
local CityConfig = require("./Config") :: any
CityConfig.Sandbox.On = false
-- 8.1 grip: no timing checks by default (a pick lifts at once, no wobbles: the moves' other tests carry as before);
-- tests/carrygrip_runtime_test.luau turns them on (the server reads Config.CarryGrip.On at every lift and carry).
CityConfig.CarryGrip.On = false
-- 8.3 keeping up: Danny not aimed ahead of his place by default (the moves' tests check him right at the far end: this
-- runtime has no network delay to make up for); tests/movehelper_keepup_runtime_test.luau turns HoldLead on again
-- (Runtime.gameLead: the game's numbers).
local gameLead = table.clone(CityConfig.MoveHelper.HoldLead)
CityConfig.MoveHelper.HoldLead.Base = 0
CityConfig.MoveHelper.HoldLead.Ping = 0
local Runtime: any = {
	now = 1000, -- workspace:GetServerTimeNow()
	clock = 50, -- os.clock()
	messages = {}, -- { { player, kind, a, b, c } } every FireClient (8.3: c, a door trip's fade in's arrival)
	money = {}, -- { { player, amount, reason } }
	xp = {}, -- { { player, amount } }
	tracked = {}, -- { { name, ... } }
	cars = {}, -- player → the fake car
	crew = {}, -- owner → { members }
	zombies = {}, -- every zombie spawned
	marched = 0,
	tags = {},
	holstered = 0,
	floor = 0, -- the floor's height the rays find (the interiors' own: Runtime.interiorFloor near them)
	-- 7.0 planning
	seated = {}, -- player → the car they drive (Vehicles.seatedIn)
	carHits = {}, -- { { car, amount, cause } } what Vehicles.damage took
	zombieHits = {}, -- { { z, amount, by, info } } what Zombies.damage was asked
	noises = 0,
	stoodUp = 0,
	gameLead = gameLead, -- 8.3 Config.MoveHelper.HoldLead as the game has it
}

local O = getmetatable(Mock.Instance.new("Model"))
local F = getmetatable(Mock.CFrame.new())
local V = getmetatable(Mock.Vector3.new())

-- ── Signals ─────────────────────────────────────────────────────────────────

local function signal(): any
	local s: any = { handlers = {} }
	function s.Connect(self: any, fn: any)
		local handler = { fn = fn, on = true }
		table.insert(self.handlers, handler)
		return {
			Connected = true,
			Disconnect = function()
				handler.on = false
			end,
		}
	end
	function s.Fire(self: any, ...: any)
		for _, handler in table.clone(self.handlers) do
			if handler.on then
				handler.fn(...)
			end
		end
	end
	function s.Wait()
		return nil
	end
	return s
end
Runtime.signal = signal

-- ── The recorder's gaps ────────────────────────────────────────────────────

local baseIndex = O.__index
O.__index = function(self: any, key: string): any
	if key == "WorldPosition" and self.props.WorldPosition == nil then
		local parent = self.props.Parent
		local position = self.props.Position or Mock.Vector3.new()
		if parent and parent.props.CFrame then
			return parent.props.CFrame * position
		end
		return position
	end
	return baseIndex(self, key)
end
-- 8.6 a WeldConstraint keeps its Part1 where it was from its Part0 as it was made (Roblox's physics); the recorder only
-- records that (its Rel) and Runtime.welded(model) puts a welded piece there: the tests' stand-in for the weld (a piece
-- carried in two lies along the carry, turned: server/Moving.luau's holdOffset).
local baseNewIndex = O.__newindex
O.__newindex = function(self: any, key: string, value: any)
	baseNewIndex(self, key, value)
	if key == "Parent" and value ~= nil and self.props.ClassName == "WeldConstraint" then
		local a, b = self.props.Part0, self.props.Part1
		if a and b then
			self.props.Rel = a.CFrame:ToObjectSpace(b.CFrame)
		end
	end
end
local SIGNALS = { "Triggered", "AncestryChanged", "Died", "HealthChanged", "StateChanged", "AttributeChanged", "CharacterAdded", "Destroying" }
local create = Mock.Instance.new
Mock.Instance.new = function(class: string): any
	local obj = create(class)
	for _, name in SIGNALS do
		obj[name] = signal()
	end
	if class == "ProximityPrompt" then
		obj.Enabled = true
		obj.MaxActivationDistance = 10
	end
	return obj
end
function O.GetPropertyChangedSignal(self: any, name: string): any
	local key = "Changed_" .. name
	if not self.props[key] then
		self.props[key] = signal()
	end
	return self.props[key]
end
function O.GetPivot(self: any): any
	if self.PrimaryPart then
		return self.PrimaryPart.CFrame
	end
	return (self:GetBoundingBox())
end
function O.IsDescendantOf(self: any, ancestor: any): boolean
	local node = self.props.Parent
	while node do
		if node == ancestor then
			return true
		end
		node = node.props.Parent
	end
	return false
end
function O.FindFirstChildWhichIsA(self: any, class: string): any
	for _, child in self.children do
		if child:IsA(class) then
			return child
		end
	end
	return nil
end
-- (7.0 review: Runtime.onStream runs once during the next door trip's stream wait: a test ends the move there)
function O.RequestStreamAroundAsync()
	local hook = Runtime.onStream
	if hook then
		Runtime.onStream = nil
		hook()
	end
end
local baseIsA = O.IsA
function O.IsA(self: any, class: string): boolean
	if class == "Instance" then
		return true
	end
	if class == "ModuleScript" then
		return self.ClassName == "ModuleScript"
	end
	return baseIsA(self, class)
end
-- 8.1 carrying in two: who simulates a part (server/PairHold.luau: the server holds a crew mate's body at a far end;
-- props.NetworkOwner: false = the server, a player, or nil = never set)
function O.SetNetworkOwner(self: any, owner: any)
	self.props.NetworkOwner = if owner == nil then false else owner
end
local baseDestroy = O.Destroy
function O.Destroy(self: any)
	self.destroyed = true
	local hook = self.props.OnDestroyed -- (8.3: a fake's own clean-up: a SeatWeld's)
	if hook then
		hook()
	end
	baseDestroy(self)
end
-- (a part's AncestryChanged when it leaves the world: the character's watchers)

local frame = function(position: any, r: any): any
	return setmetatable({ Position = position, R = r }, F)
end
F.__index = function(self: any, key: string): any
	if key == "Rotation" then
		return frame(Mock.Vector3.new(), self.R)
	elseif key == "LookVector" then
		return Mock.Vector3.new(-self.R[3], -self.R[6], -self.R[9])
	elseif key == "X" then
		return self.Position.X
	elseif key == "Y" then
		return self.Position.Y
	elseif key == "Z" then
		return self.Position.Z
	end
	return rawget(F, key)
end
F.__add = function(a: any, v: any): any
	return frame(a.Position + v, a.R)
end
function F.ToOrientation(self: any): (number, number, number)
	local r = self.R
	return 0, math.atan2(r[3], r[9]), 0
end
local _ = V

Mock.UDim2.fromOffset = function(x: number, y: number)
	return { x, y }
end
Mock.UDim2.new = function(a: any, b: any, c: any, d: any)
	return { a, b, c, d }
end
Mock.UDim = { new = function(a: any, b: any)
	return { a, b }
end }
Mock.RaycastParams = { new = function()
	return {}
end }
Mock.OverlapParams = { new = function() -- (7.0 review: the barricades' clear way)
	return {}
end }
local baseTypeof = Mock.typeof
Mock.typeof = function(x: any): string
	if type(x) == "table" and getmetatable(x) == O then
		return "Instance"
	end
	return baseTypeof(x)
end

-- ── The world ──────────────────────────────────────────────────────────────

local workspace = Mock.workspace
workspace.Name = "Workspace"
workspace.GetServerTimeNow = function()
	return Runtime.now
end
-- The floor under a point: an interior's (Runtime.interiorFloor within 400 studs of an interior's origin), else 0.
workspace.Raycast = function(_, origin: any, _direction: any, _params: any): any
	local floor = Runtime.floor
	for _, at in Runtime.interiors do
		if (origin - at.Position).Magnitude < 400 then
			floor = at.Position.Y
		end
	end
	return { Position = Mock.Vector3.new(origin.X, floor, origin.Z) }
end
Runtime.interiors = {}
-- The parts of params' Include list whose middle is within the box (in the box's own frame; a part's size not counted).
workspace.GetPartBoundsInBox = function(_, frame: any, size: any, params: any): any
	local found = {}
	for _, model in (params and params.FilterDescendantsInstances) or {} do
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local d = frame:PointToObjectSpace(part.CFrame.Position)
				if math.abs(d.X) <= size.X / 2 and math.abs(d.Y) <= size.Y / 2 and math.abs(d.Z) <= size.Z / 2 then
					table.insert(found, part)
				end
			end
		end
	end
	return found
end

Runtime.os = {
	clock = function()
		return Runtime.clock
	end,
	time = os.time,
}

Runtime.task = {
	delay = function(_, callback: any, ...: any)
		callback(...)
	end,
	spawn = function(callback: any, ...: any)
		Runtime.spawned = callback -- (the tick loop: the test runs Moving.step instead)
		local _ = ...
	end,
	defer = function(callback: any, ...: any)
		callback(...)
	end,
	wait = function()
		return 0
	end,
}

-- ── Players ────────────────────────────────────────────────────────────────

local playersFolder = Mock.Instance.new("Folder")
playersFolder.Name = "Players"
local Players: any = {
	PlayerAdded = signal(),
	PlayerRemoving = signal(),
	list = {},
}
function Players.GetPlayers(_: any): any
	return table.clone(Players.list)
end
function Players.GetPlayerByUserId(_: any, id: number): any
	for _, player in Players.list do
		if player.UserId == id then
			return player
		end
	end
	return nil
end

-- A player standing at `at` (a Vector3), alive, on foot.
function Runtime.player(id: number, name: string, at: any): any
	local player = Mock.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = id
	player.Parent = playersFolder
	local character = Mock.Instance.new("Model")
	character.Name = name
	local root = Mock.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Mock.Vector3.new(2, 2, 1)
	root.CFrame = Mock.CFrame.new(at.X, at.Y, at.Z)
	root.Parent = character
	character.PrimaryPart = root
	local humanoid = Mock.Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.Health = 100
	humanoid.HipHeight = 2
	humanoid.SeatPart = nil
	humanoid.Parent = character
	humanoid.RootPart = root
	character.Parent = workspace
	player.Character = character
	table.insert(Players.list, player)
	return player
end

function Runtime.rootOf(player: any): any
	return player.Character:FindFirstChild("HumanoidRootPart")
end

-- 8.6 a welded piece (server/Moving.luau's weldTo) put where its weld keeps it from its holder; false: no weld on it.
function Runtime.welded(model: any): boolean
	local root = model and model.PrimaryPart
	local weld = root and root:FindFirstChild("WeldConstraint")
	local rel = weld and weld.props.Rel
	if not weld or weld.destroyed or not rel or not weld.props.Part0 then
		return false
	end
	root.CFrame = weld.props.Part0.CFrame * rel
	return true
end

function Runtime.place(player: any, at: any)
	Runtime.rootOf(player).CFrame = Mock.CFrame.new(at.X, at.Y, at.Z)
end

function Runtime.leave(player: any)
	Runtime.crew[player] = nil -- (server/Crew.luau's own PlayerRemoving breaks the crew up first)
	Players.PlayerRemoving:Fire(player)
	local index = table.find(Players.list, player)
	if index then
		table.remove(Players.list, index)
	end
	player.Parent = nil
end

-- ── The remotes ────────────────────────────────────────────────────────────

local remotes: { [string]: any } = {}
Runtime.Net = {
	get = function(name: string): any
		local remote = remotes[name]
		if not remote then
			remote = {
				name = name,
				OnServerEvent = signal(),
				FireClient = function(_, player: any, kind: any, a: any, b: any, c: any)
					table.insert(Runtime.messages, { player = player, remote = name, kind = kind, a = a, b = b, c = c })
				end,
				FireAllClients = function() end,
			}
			remotes[name] = remote
		end
		return remote
	end,
	limit = function()
		return true
	end,
}
-- The last message of `kind` (a notice's text: kind = the text) sent to `player` on `remote`.
function Runtime.last(player: any, remote: string, kind: string?): any
	for index = #Runtime.messages, 1, -1 do
		local m = Runtime.messages[index]
		if m.player == player and m.remote == remote and (kind == nil or m.kind == kind) then
			return m
		end
	end
	return nil
end
function Runtime.lastNotice(player: any): string
	local m = Runtime.last(player, "Notice")
	return if m then tostring(m.kind) else ""
end
function Runtime.request(player: any, ...: any)
	remotes.Moving.OnServerEvent:Fire(player, ...)
end

-- ── The server modules ─────────────────────────────────────────────────────

local function stub(name: string, fields: { [string]: any }): any
	return setmetatable(fields, { __index = function(_, key)
		error(`MovingRuntime: unmocked {name}.{tostring(key)}`, 2)
	end })
end
local noop = function() end

Runtime.Crew = stub("Crew", {
	members = function(owner: any): any
		local list = {}
		for _, member in Runtime.crew[owner] or {} do
			if member.Parent then
				table.insert(list, member)
			end
		end
		return list
	end,
	ownerOf = function(player: any): any
		for owner, list in Runtime.crew do
			if table.find(list, player) and owner.Parent then
				return owner
			end
		end
		return nil
	end,
	hasJob = function(): boolean -- (Main's: Jobs.active; 7.0 review: Moving wraps it)
		return false
	end,
})

Runtime.wallet = {} -- 8.3: player → their money (PlayerData.get's money, spend's)
Runtime.startMoney = 1000
Runtime.spent = {} -- { { player, amount, reason, sku } } every PlayerData.spend that took the money
local function moneyOf(player: any): number
	local money = Runtime.wallet[player]
	return if type(money) == "number" then money else Runtime.startMoney
end
Runtime.PlayerData = stub("PlayerData", {
	addMoney = function(player: any, amount: number, reason: string)
		table.insert(Runtime.money, { player = player, amount = amount, reason = reason })
	end,
	spend = function(player: any, amount: number, reason: string?, sku: string?): boolean
		local money = moneyOf(player)
		if type(amount) ~= "number" or amount < 0 or money < amount then
			return false
		end
		Runtime.wallet[player] = money - amount
		table.insert(Runtime.spent, { player = player, amount = amount, reason = reason, sku = sku })
		return true
	end,
	addXp = function(player: any, amount: number)
		table.insert(Runtime.xp, { player = player, amount = amount })
		return 1, false
	end,
	track = function(name: string, ...: any)
		table.insert(Runtime.tracked, { name = name, args = { ... } })
	end,
	-- 7.x farm move: a player's profile (its story flags: Runtime.story[player], its car) and a flag kept in it
	-- (7.2 review: a test's own Runtime.profiles[player] when it set one: its car, bike and lastCar kept)
	get = function(player: any): any
		Runtime.story[player] = Runtime.story[player] or {}
		local own = Runtime.profiles[player]
		if own then
			own.story = Runtime.story[player]
			own.money = moneyOf(player)
			return own
		end
		return { story = Runtime.story[player], car = Runtime.carId, money = moneyOf(player) }
	end,
	-- 8.4: was the player's save read? A test's own Runtime.profiles[player] stands for one (its sandboxHouseSeed the
	-- save's, kept there as Moving sets it); without one: a fresh profile, never saved (Moving's own memory counts)
	loaded = function(player: any): boolean
		return Runtime.profiles[player] ~= nil
	end,
	notify = noop, -- (7.2 review: the profile's car changed)
	markStory = function(player: any, key: string): boolean
		Runtime.story[player] = Runtime.story[player] or {}
		local new = Runtime.story[player][key] ~= true
		Runtime.story[player][key] = true
		table.insert(Runtime.marked, { player = player, key = key })
		return new
	end,
})

-- The truck: a chassis at `at`, its back door attachment 9 studs behind it, a BackPrompt. (7.2 review: a bike,
-- Runtime.bikes: no back at all.)
Runtime.bikes = { rustbike = true, escooter = true }
local function makeCar(owner: any, id: string, at: any): any
	local model = Mock.Instance.new("Model")
	model.Name = `{owner.Name}'s {id}`
	local chassis = Mock.Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.CFrame = Mock.CFrame.new(at.X, at.Y, at.Z)
	chassis.Parent = model
	model.PrimaryPart = chassis
	local bike = Runtime.bikes[id] == true
	if not bike then
		local door = Mock.Instance.new("Attachment")
		door.Name = "CargoDoor"
		door.Position = Mock.Vector3.new(0, 3, 9)
		door.Parent = chassis
		local back = Mock.Instance.new("ProximityPrompt")
		back.Name = "BackPrompt"
		back.Parent = door
		model:SetAttribute("BackOpen", false)
	end
	model.Parent = workspace
	local car: any = { owner = owner, id = id, model = model, chassis = chassis, wrecked = false, lent = false, rental = false, bike = bike, speed = 0 }
	if not bike then
		-- 8.3: its seats (the driver's, one passenger's on the right: Door 2), its doors and its size
		local function sit(seat: any, humanoid: any)
			if seat.Occupant ~= nil or humanoid.SeatPart ~= nil then
				return
			end
			seat.Occupant, humanoid.SeatPart, humanoid.Sit = humanoid, seat, true
			local weld = Mock.Instance.new("Weld")
			weld.Name = "SeatWeld"
			weld.Part0, weld.Part1 = seat, humanoid.RootPart or humanoid.Parent.PrimaryPart
			weld.OnDestroyed = function() -- (Roblox: the seat's occupant gone with its weld)
				if seat.Occupant == humanoid then
					seat.Occupant = nil
				end
				if humanoid.SeatPart == seat then
					humanoid.SeatPart = nil
				end
			end
			weld.Parent = seat
			table.insert(Runtime.sat, { seat = seat, humanoid = humanoid })
		end
		local driver = Mock.Instance.new("VehicleSeat")
		driver.Name = "DriverSeat"
		driver.CFrame = chassis.CFrame * Mock.CFrame.new(-1.4, 1.5, -3)
		driver:SetAttribute("Door", 1)
		driver.Parent = model
		driver.Sit = sit
		local passenger = Mock.Instance.new("Seat")
		passenger.Name = "PassengerSeat"
		passenger.CFrame = chassis.CFrame * Mock.CFrame.new(1.4, 1.5, -3)
		passenger:SetAttribute("Index", 1)
		passenger:SetAttribute("Door", 2)
		passenger.Parent = model
		passenger.Sit = sit
		car.seat, car.passengers = driver, { passenger }
		car.doors = { { side = -1, z = -3, driver = true, seats = {} }, { side = 1, z = -3, driver = false, seats = { 1 } } }
		car.size = Mock.Vector3.new(6, 6, 18)
	end
	return car
end
Runtime.sat = {} -- 8.3: { { seat, humanoid } } every Seat:Sit
Runtime.makeCar = makeCar -- (8.0 SANDBOX: the test's own Moving.parkVan parks one)
Runtime.truckAt = Mock.Vector3.new(0, 2, 0) -- where placeNear puts the truck (the test sets it)
-- 7.x van moves: a move goes with its owner's own car: the one placeNear makes when it is given no id (the old tests'
-- big Moving Truck bed: Config.Moving.Beds.movingtruck; the van tests set "zdcvan")
Runtime.carId = "movingtruck"
Runtime.story = {} -- 7.x farm move: player → their story flags (PlayerData.get(player).story)
Runtime.marked = {} -- { { player, key } } every PlayerData.markStory
Runtime.profiles = {} -- 7.2 review: player → a profile of the test's own (PlayerData.get returns it)

Runtime.Vehicles = stub("Vehicles", {
	get = function(player: any): any
		return Runtime.cars[player]
	end,
	-- (no id: the profile's car, as CAR brings it: a test's own profile's, else Runtime.carId)
	placeNear = function(player: any, id: string): any
		local old = Runtime.cars[player]
		if old then
			old.model:Destroy()
		end
		local own = Runtime.profiles[player]
		Runtime.cars[player] = makeCar(player, id or (own and own.car) or Runtime.carId, Runtime.truckAt)
		return nil
	end,
	isBike = function(car: any): boolean -- 7.2 review
		return car.bike == true
	end,
	hasBack = function(car: any): boolean -- 7.2 review: Vehicles.hasBack's (not wrecked, a BackPrompt)
		local door = car.chassis:FindFirstChild("CargoDoor")
		return not car.wrecked and door ~= nil and door:FindFirstChild("BackPrompt") ~= nil
	end,
	cargoDoor = function(car: any): any
		return car.chassis:FindFirstChild("CargoDoor")
	end,
	backPrompt = function(car: any): any
		local door = car.chassis:FindFirstChild("CargoDoor")
		return door and door:FindFirstChild("BackPrompt")
	end,
	backOpen = function(car: any): boolean
		return car.model:GetAttribute("BackOpen") == true
	end,
	setBack = function(car: any, open: boolean) -- (7.x Danny opens the back himself)
		car.model:SetAttribute("BackOpen", open)
		Runtime.backSet = (Runtime.backSet or 0) + 1
	end,
	backVerb = function(_car: any, opening: boolean): string
		return if opening then "open the back doors" else "close the back doors"
	end,
	speed = function(car: any): number -- (8.3: the test's `speed` on the car)
		return if type(car.speed) == "number" then car.speed else 0
	end,
	cargoSlots = function(): any
		return { Mock.CFrame.new(0, 0.6, 0) }
	end,
	cargoHolder = function(car: any): any
		return car.chassis
	end,
	all = function(): any -- (7.0 review: the barricades keep clear of every car)
		local list = {}
		for _, car in Runtime.cars do
			table.insert(list, car)
		end
		return list
	end,
	-- (7.0 review: Moving wraps these: nothing replaces the moving truck mid-move; the fakes say what they would do)
	spawn = function(player: any): any
		Runtime.vehicleCalls = (Runtime.vehicleCalls or 0) + 1
		local _ = player
		return nil
	end,
	placeAt = function(player: any, carId: any): any
		Runtime.vehicleCalls = (Runtime.vehicleCalls or 0) + 1
		local _ = carId
		return Runtime.cars[player]
	end,
	spawnAt = function(player: any, carId: any, ground: any): any
		Runtime.vehicleCalls = (Runtime.vehicleCalls or 0) + 1
		if Runtime.cars[player] == nil and type(carId) == "string" and ground then -- (8.0 SANDBOX: the van at the plot)
			Runtime.cars[player] = makeCar(player, carId, ground.Position)
		end
		return Runtime.cars[player]
	end,
	seatedIn = function(player: any): (any, boolean, any)
		local car = Runtime.seated[player]
		if car then
			return car, true, car.chassis
		end
		return nil, false, nil
	end,
	damage = function(car: any, amount: number, _reason: any, cause: any): number
		table.insert(Runtime.carHits, { car = car, amount = amount, cause = cause })
		return amount
	end,
	standUp = function(_car: any, _heading: any)
		Runtime.stoodUp += 1
	end,
	groundY = function()
		return 0
	end,
	backAllowed = function()
		return false
	end,
	callCar = function()
		return "called"
	end,
	-- 8.3 review: the hook a passenger door's Ride along asks (server/Buddy.luau's: no buddy here; server/MoveHelper.luau
	-- wraps it: Danny gets out for his crew; a test calls it as the door's prompt would)
	yieldSeat = function(_seat: any, _player: any): boolean
		return false
	end,
	-- 8.5: a cabin door swung for Danny getting in or out (server/MoveHelper.luau): recorded in Runtime.doorSwings
	-- (the car, the door, openAt, closeAt: openAt nil shuts it from closeAt; the server time and the clock it came at)
	swingDoor = function(car: any, index: number, openAt: number?, closeAt: number)
		table.insert(Runtime.doorSwings, { car = car, door = index, openAt = openAt, closeAt = closeAt, now = Runtime.now, clock = Runtime.clock })
	end,
})
Runtime.doorSwings = {} -- 8.5 { { car, door, openAt, closeAt, now, clock } } every Vehicles.swingDoor

Runtime.Zombies = stub("Zombies", {
	hunts = function()
		return false
	end,
	onCarDamaged = noop,
	findSpot = function(center: any): any
		return center + Mock.Vector3.new(60, 0, 0)
	end,
	pickKind = function()
		return "walker"
	end,
	spawn = function(kind: string, at: any, owner: any, guard: any, resident: any, roamer: any): any
		local model = Mock.Instance.new("Model")
		model.Parent = workspace
		local root = Mock.Instance.new("Part") -- (7.0 helper: where it stands, for Danny's running away; 7.0 planning: a barricade)
		root.Name = "HumanoidRootPart"
		root.CFrame = Mock.CFrame.new(at.X, at.Y, at.Z)
		root.Parent = model
		local z = { kind = kind, at = at, owner = owner, roamer = roamer == true, dead = false, model = model, root = root }
		table.insert(Runtime.zombies, z)
		local _ = guard and resident
		return z
	end,
	march = function(z: any, at: any)
		z.march = at
		if at then
			Runtime.marched += 1
		end
	end,
	-- 7.0 planning: the Guard's hits (Zombies.damage wrapped); a noise (nothing on a move makes one now)
	damage = function(z: any, amount: number, by: any, info: any): boolean
		table.insert(Runtime.zombieHits, { z = z, amount = amount, by = by, info = info })
		return false
	end,
	noise = function()
		Runtime.noises += 1
	end,
	-- 7.0, the depot's helper (server/MoveHelper.luau): every zombie, and the buddies' targets he adds himself to
	all = function(): any
		return Runtime.zombies
	end,
	extraTargets = function(): any
		return {}
	end,
})

-- 7.0, the depot's helper's body (server/Npcs.luau): a model with a root and a humanoid where it is put; what he says.
-- 7.0 greeters (server/MoveGreeters.luau): who said what (and seen from how far), the gestures, the glances.
Runtime.said = {} -- { text } every Npcs.say
Runtime.saidBy = {} -- { { npc, text, range } } every Npcs.say
Runtime.acts = {} -- { { npc, kind } } every Npcs.act
Runtime.glances = {} -- { { npc, at } } every Npcs.glance
Runtime.Npcs = stub("Npcs", {
	look = function(role: string, name: string, title: string?): any
		return { name = name, title = title, role = role }
	end,
	spawn = function(look: any, at: any): any
		local model = Mock.Instance.new("Model")
		model.Name = look.name
		model:SetAttribute("Title", look.title) -- (7.0 greeters: the name tag's second line)
		local root = Mock.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Mock.Vector3.new(2, 2, 1)
		root.CFrame = at + Mock.Vector3.new(0, 3, 0)
		root.Parent = model
		model.PrimaryPart = root
		local humanoid = Mock.Instance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.HipHeight = 2
		humanoid.MaxHealth = 1e6
		humanoid.Health = 1e6
		humanoid.Parent = model
		model.Parent = workspace
		return model
	end,
	say = function(npc: any, text: string, _seconds: number?, range: number?)
		table.insert(Runtime.said, text)
		table.insert(Runtime.saidBy, { npc = npc, text = text, range = range })
	end,
	act = function(npc: any, kind: string)
		table.insert(Runtime.acts, { npc = npc, kind = kind })
	end,
	glance = function(npc: any, at: any)
		table.insert(Runtime.glances, { npc = npc, at = at })
	end,
	remove = function(npc: any)
		npc:Destroy()
	end,
	stop = noop,
	pace = noop,
	walkTo = noop,
	-- 8.1 carrying in two: his legs' speed along his facing while he holds the far end (negative: backwards)
	stride = function(npc: any, speed: number)
		table.insert(Runtime.strides, { npc = npc, speed = speed })
	end,
	carried = noop,
})
Runtime.strides = {} -- { { npc, speed } } every Npcs.stride
-- Did he say `text` (since message `from`)?
function Runtime.saidSince(text: string, from: number?): boolean
	for index = (from or 0) + 1, #Runtime.said do
		if Runtime.said[index] == text then
			return true
		end
	end
	return false
end

Runtime.Jobs = stub("Jobs", {
	active = function(player: any): boolean
		return Runtime.jobOf == player
	end,
	returnLent = function()
		return true
	end,
})
Runtime.BanditCars = stub("BanditCars", { onCarDamaged = noop })
-- 8.0 SANDBOX: the plots (server/SandboxPlots.luau) and the collection (server/Collection.luau)
Runtime.plots = {} -- player → their SandboxMap plot
Runtime.collected = {} -- { { player, entry, uid } } every Collection.add
Runtime.refuse = false -- Collection.add says nil (no save yet)
Runtime.SandboxPlots = stub("SandboxPlots", {
	of = function(player: any): any
		return Runtime.plots[player]
	end,
	owner = function(id: number): any
		for player, plot in Runtime.plots do
			if plot.id == id then
				return player
			end
		end
		return nil
	end,
	onChanged = noop,
})
Runtime.Collection = stub("Collection", {
	add = function(player: any, entry: any): string?
		if Runtime.refuse then
			return nil
		end
		local uid = `uid{#Runtime.collected + 1}`
		table.insert(Runtime.collected, { player = player, entry = entry, uid = uid })
		return uid
	end,
})
Runtime.Hand = stub("Hand", {
	holster = function()
		Runtime.holstered += 1
	end,
})

local services: { [string]: any } = {
	Players = Players,
	ReplicatedStorage = { WaitForChild = function()
		return {}
	end },
	CollectionService = {
		AddTag = function(_, obj: any, tag: string)
			obj:SetAttribute("Tag_" .. tag, true)
		end,
		RemoveTag = function(_, obj: any, tag: string)
			obj:SetAttribute("Tag_" .. tag, nil)
		end,
	},
	-- 8.5: Danny's pose every frame while he gets in or out of the van (server/MoveHelper.luau hooks Heartbeat only
	-- then); nothing fires it but a test
	RunService = { Heartbeat = signal() },
}
Runtime.game = { GetService = function(_, name: string): any
	assert(services[name], `MovingRuntime: unmocked service {name}`)
	return services[name]
end }
Runtime.services = services -- (8.3: a test adds its own, e.g. a PathfindingService that records Danny's paths)
Runtime.Players = Players

-- ── The art (shaped like the art branch's interface) ───────────────────────

local V3 = Mock.Vector3.new
Runtime.items = {
	lamp = { id = "lamp", name = "Lamp", icon = "💡", size = V3(1, 3, 1), class = "hand", weight = 1, value = 40, fragile = true, room = "living" },
	tv = { id = "tv", name = "TV", icon = "📺", size = V3(3, 2, 0.8), class = "both", weight = 4, value = 250, fragile = true, room = "living" },
	sofa = { id = "sofa", name = "Sofa", icon = "🛋", size = V3(6, 3, 2.8), class = "pair", weight = 8, value = 300, fragile = false, room = "living" },
	clock = { id = "clock", name = "Grandpa's Clock", icon = "🕰", size = V3(1.5, 6, 1), class = "both", weight = 6, value = 400, fragile = true, room = "hall" },
	box = { id = "box", name = "Box of memories", icon = "📦", size = V3(2, 1.5, 1.5), class = "hand", weight = 3, value = 120, fragile = false, room = "attic" },
	slab = { id = "slab", name = "Marble slab", icon = "🪨", size = V3(7, 3.6, 9.8), class = "pair", weight = 10, value = 500, fragile = false, room = "hall" },
}
local SPOTS = {
	{ id = 1, item = "lamp", room = "living", at = Mock.CFrame.new(4, 1.5, 6), star = false },
	{ id = 2, item = "tv", room = "living", at = Mock.CFrame.new(-4, 1, 6), star = false },
	{ id = 3, item = "sofa", room = "living", at = Mock.CFrame.new(0, 1.5, 12), star = false },
	{ id = 4, item = "clock", room = "hall", at = Mock.CFrame.new(2, 3, 2), star = true },
	{ id = 5, item = "box", room = "attic", at = Mock.CFrame.new(-2, 0.75, 20), star = true },
	{ id = 6, item = "slab", room = "hall", at = Mock.CFrame.new(-6, 1.8, 2), star = true },
}
Runtime.built = 0
Runtime.destroyed = 0
Runtime.art = {
	looks = {
		Items = Runtime.items,
		build = function(id: string): any
			local def = Runtime.items[id]
			local model = Mock.Instance.new("Model")
			model.Name = id
			local root = Mock.Instance.new("Part")
			root.Name = "Root"
			root.Size = def.size
			root.Transparency = 1
			root.Parent = model
			local look = Mock.Instance.new("Part")
			look.Name = "Look"
			look.CanCollide = false
			look.Massless = true
			look.Parent = model
			model.PrimaryPart = root
			model:SetAttribute("FurnitureId", id)
			model:SetAttribute("Class", def.class)
			return model
		end,
	},
	layout = {
		plan = function(seed: number, kind: string): any
			return {
				kind = kind,
				seed = seed,
				size = V3(30, 12, 30),
				doors = {},
				entry = Mock.CFrame.new(0, 0, 1),
				exit = V3(0, 0, 0.5),
				spots = SPOTS,
				rooms = { { id = "garage", kind = "garage", min = V3(-12, 0, 14), max = V3(-2, 10, 26) } },
			}
		end,
	},
	interior = {
		slot = function(index: number): any
			return Mock.CFrame.new(5000 * index, 600, 0)
		end,
		build = function(plan: any, origin: any): (any, any)
			Runtime.built += 1
			table.insert(Runtime.interiors, origin)
			local model = Mock.Instance.new("Model")
			model.Name = "Interior"
			local items = Mock.Instance.new("Folder")
			items.Name = "Items"
			items.Parent = model
			local byspot = {}
			for _, spot in plan.spots do
				local made = Runtime.art.looks.build(spot.item)
				made:PivotTo(origin * spot.at)
				for _, part in made:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
					end
				end
				made:SetAttribute("Spot", spot.id)
				made:SetAttribute("Star", spot.star)
				made.Parent = items
				byspot[spot.id] = made
			end
			-- the lights (on from the start: no fuse box any more) and the porch's daylight
			local lamp = Mock.Instance.new("Part")
			lamp.Name = "Lamp"
			lamp.Material = "Neon"
			lamp.Parent = model
			local light = Mock.Instance.new("PointLight")
			light.Enabled = true
			light.Parent = lamp
			local porch = Mock.Instance.new("Part")
			porch.Name = "Daylight"
			porch.Parent = model
			local daylight = Mock.Instance.new("SpotLight")
			daylight.Enabled = true
			daylight.Parent = porch
			model.Parent = workspace
			return model, byspot
		end,
		destroy = function(model: any)
			Runtime.destroyed += 1
			model:Destroy()
		end,
	},
}

Runtime.Mock = Mock
return Runtime
