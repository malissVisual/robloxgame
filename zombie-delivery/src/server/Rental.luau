--!strict
-- 5.6, ZDC RIDE: the free rental e-scooters (Config.Rental; the docks' places: shared/RentalDocks.luau).
--
-- The docks, built when this starts (after World): on the sidewalk along the kerb, 8 native parts each (a base plate,
-- a charging rail, three bollards, a sign post with the ZDC RIDE · free board facing the street and a small lamp that
-- glows at night) and 2 – 3 docked E-Scooters in the ZDC RIDE red (Vehicles.displayModel: anchored, nothing of them
-- collides). A Model per dock in workspace.World.RentalDocks (Atomic streaming), tagged RentalDock (attribute DockId).
-- Two prompts at every dock, tagged RentalPrompt (attribute Kind = "rent" | "return"; client/RentalUi.luau shows each
-- player the one that fits them): "Rent scooter" (hold Hold s) and "Return scooter" (the attribute Seated: it works
-- from the saddle, client/CarBoarding.luau).
--
-- Renting (the server checks it all): on foot only (not seated, not getting in, not on a zip line), never on a mission
-- or a car job, not while a chauffeur brings your car, nothing in your hands that your bag cannot take (6.6)
-- (Cargo.canStowHands; Cargo.update stows them as you sit, like on your bike), one rental at a time, a scooter in the
-- dock, and the price (Config.Rental.Price: 0, free; the money check stays). Your own car or bike out goes home first
-- (you are told: BRING MY CAR / MY BIKE brings it back). The rental is a Vehicles.spawnAt(…, rental = true) E-Scooter
-- where the docked one stood (that one leaves the dock): your vehicle while it lasts (it rides like the owned E-Scooter:
-- one rack slot and your pack, server/Transport.luau; foot and bike jobs go on as on foot), never saved, never in
-- your cars, no paint, no gear, no fuel, no garage; you mount it (5.7: Vehicles.mount, the slide off the dock). The player attribute Rental = the dock's id
-- while you have one (the phone, the prompts).
--
-- Returning: Return at any dock ends it at once; off the scooter and more than WalkAway studs from it, or off it for
-- Idle seconds, it goes back by itself; calling your own car or bike (Jobs.returnLent: it is lent), buying one, a
-- respawn, a wreck or leaving ends it too. A returned scooter stands in its own dock again Restock seconds later.
--
-- 6.3, the rack at the spawn (RentalDocks' dock1, Config.Rental.SpawnRack): built like any dock, but its six scooters
-- stand side by side facing out of the yard (the plate deeper, the rail behind them, a bollard at each end) and its
-- board reads TAKE ONE AND GO under ZDC RIDE · free. The rides from it are the same rentals.
--
-- 6.10 (the owner: "don't teleport me onto the scooter, I want to grab it and jump on it quickly"): every docked
-- scooter has its own "Ride" prompt just left of its deck (Kind "rent", the attribute Slot; the owned scooter's place
-- and short reach, Config.Interact.ScooterReach; no hold): E at the scooter you want and that one is yours, you hop on
-- it at once while it slides off the rail (Vehicles.mount). The dock's own Rent prompt shows only while the dock is
-- empty (refreshDock: its reach), and says where the next scooter is.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local RentalDocks = require(Shared.RentalDocks)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)
local Jobs = require(script.Parent.Jobs)
local Cargo = require(script.Parent.Cargo)
local CarCall = require(script.Parent.CarCall)
local Zombies = require(script.Parent.Zombies)
local DayNight = require(script.Parent.DayNight)

local Rental = {}

Rental.DockTag = "RentalDock"
Rental.PromptTag = "RentalPrompt"

local Tuning = Config.Rental
local TICK = 0.25
local WALK_TOP = Map.WalkTop
local RED = Color3.fromRGB(Tuning.Color[1], Tuning.Color[2], Tuning.Color[3])
local METAL = Color3.fromRGB(46, 48, 52)
local PLATE = Color3.fromRGB(70, 72, 76)
local LAMP_LIT = Color3.fromRGB(255, 236, 200)
local LAMP_DIM = Color3.fromRGB(120, 120, 116)

type Slot = { ground: CFrame, model: Model?, taken: boolean }
type DockState = { dock: RentalDocks.Dock, model: Model, slots: { Slot }, rentPrompt: ProximityPrompt? }
type Ride = { car: Vehicles.Car, state: DockState, slot: number, leftAt: number? }

local docks: { DockState } = {}
local rides: { [Player]: Ride } = {}
local started = false

local function tell(player: Player, text: string)
	Net.get("Notice"):FireClient(player, text)
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.Parent = parent
	return p
end

local function priceText(): string
	return if Tuning.Price > 0 then `${Tuning.Price}` else "free"
end

-- The sign's face: ZDC RIDE, the price, the dock's corner.
local function signFace(board: BasePart, face: Enum.NormalId, dock: RentalDocks.Dock)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = board
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(24, 27, 32)
	back.BorderSizePixel = 0
	back.Parent = gui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0.08, 0)
	bar.BackgroundColor3 = RED
	bar.BorderSizePixel = 0
	bar.Parent = back
	local function line(text: string, y: number, h: number, color: Color3, font: Enum.Font)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.9, 0, h, 0)
		label.Position = UDim2.new(0.05, 0, y, 0)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = font
		label.TextColor3 = color
		label.Parent = back
	end
	line(`ZDC RIDE · {priceText()}`, 0.16, 0.42, Color3.fromRGB(242, 242, 240), Enum.Font.GothamBold)
	line(if dock.spawn then "TAKE ONE AND GO" else string.upper(dock.name), 0.64, 0.24, Color3.fromRGB(169, 174, 180), Enum.Font.GothamMedium)
end

local function prompt(parent: Instance, name: string, action: string, kind: string, dock: RentalDocks.Dock, hold: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = `ZDC RIDE · {priceText()}`
	p.HoldDuration = hold
	p.MaxActivationDistance = Tuning.Reach
	p.RequiresLineOfSight = false
	p:SetAttribute("Kind", kind)
	p:SetAttribute("DockId", dock.id)
	CollectionService:AddTag(p, Rental.PromptTag)
	p.Parent = parent
	return p
end

local function scooterDef(): Config.CarDef
	return Economy.findCar(Tuning.CarId) or Config.Cars[1]
end

local rent: (Player, DockState, number?) -> () -- (below; 6.10: a docked scooter's own Ride prompt calls it)

local function dockScooter(state: DockState, slot: Slot)
	if slot.model then
		slot.model.Parent = state.model
		return
	end
	local model = Vehicles.displayModel(scooterDef(), slot.ground, nil, nil, nil, RED)
	model.Name = "DockedScooter"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	-- 6.10: its own Ride prompt where an owned scooter has its Drive prompt (just left of the deck, a short reach): E at
	-- this scooter and it is yours. (It goes and comes back with the model.)
	local index = table.find(state.slots, slot)
	local chassis = model.PrimaryPart
	if index and chassis then
		local at = Instance.new("Attachment")
		at.Name = "RidePoint"
		at.Position = Vector3.new(-Config.Interact.ScooterPromptOut, 1.3, -0.2)
		at.Parent = chassis
		local ride = prompt(at, "DockRidePrompt", "Ride", "rent", state.dock, Tuning.Hold) -- (not "RidePrompt": a car door's)
		ride.MaxActivationDistance = Config.Interact.ScooterReach
		ride:SetAttribute("Slot", index)
		ride.Triggered:Connect(function(player: Player)
			rent(player, state, index)
		end)
	end
	model.Parent = state.model
	slot.model = model
end

local function buildDock(folder: Instance, dock: RentalDocks.Dock): DockState
	local model = Instance.new("Model")
	model.Name = `ZDC RIDE · {dock.name}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("DockId", dock.id)
	local t = Vector3.new(dock.tx, 0, dock.tz)
	local n = Vector3.new(dock.nx, 0, dock.nz)
	local centre = Vector3.new(dock.x, WALK_TOP, dock.z)
	-- along the kerb (the scooters' way), out toward the street, up
	local function at(along: number, out: number, y: number): Vector3
		return centre + t * along + n * out + Vector3.new(0, y, 0)
	end
	local facing = CFrame.lookAt(centre, centre + t)
	local function frameAt(along: number, out: number, y: number): CFrame
		return facing.Rotation + at(along, out, y)
	end
	local half = dock.length / 2
	-- 6.3: the spawn's rack holds its scooters side by side (each 5 long, facing n): a deeper plate, the rail
	-- behind their tails and a bollard at each end of the row only (one in the middle would stand in a slot).
	local rack = dock.spawn
	local plate = part(model, "DockPlate", Vector3.new(if rack then 5.6 else 2.6, 0.12, dock.length + 1.2), frameAt(0, 0, 0.06), PLATE, Enum.Material.DiamondPlate)
	part(model, "ChargeRail", Vector3.new(0.3, 0.5, dock.length), frameAt(0, if rack then -2.65 else -1.15, 0.37), METAL, Enum.Material.Metal)
	local bollards: { number } = if rack then { -half - 0.3, half + 0.3 } else { -half - 0.3, 0, half + 0.3 }
	for _, along in bollards do
		-- (they do not collide: a rental takes off from its slot beside them)
		part(model, "Bollard", Vector3.new(0.4, 1.1, 0.4), frameAt(along, if rack then 0 else 1.05, 0.55), RED, Enum.Material.SmoothPlastic)
	end
	local signAlong = half + 1.4
	part(model, "SignPost", Vector3.new(0.3, 5.6, 0.3), frameAt(signAlong, -0.2, 2.8), METAL, Enum.Material.Metal, true)
	local signPos = at(signAlong, -0.2, 4.9)
	local board = part(model, "Sign", Vector3.new(3.2, 1.7, 0.15), CFrame.lookAt(signPos, signPos + n), Color3.fromRGB(24, 27, 32), Enum.Material.Metal)
	signFace(board, Enum.NormalId.Front, dock)
	signFace(board, Enum.NormalId.Back, dock)
	local lamp = part(model, "Lamp", Vector3.new(0.5, 0.3, 0.5), frameAt(signAlong, -0.2, 5.75), LAMP_DIM, Enum.Material.SmoothPlastic)
	DayNight.nightLight(lamp, LAMP_LIT, LAMP_DIM, "SmoothPlastic")
	-- The prompts, at the plate's middle.
	local spot = Instance.new("Attachment")
	spot.Name = "RentalPrompts"
	spot.Position = Vector3.new(0, 2.2, 0)
	spot.Parent = plate
	-- (6.10: only while the dock is empty, refreshDock: it says where the next scooter is; each scooter has its Ride)
	local empty = prompt(spot, "RentPrompt", "Find a scooter", "rent", dock, 0)
	local back = prompt(spot, "ReturnPrompt", "Return scooter", "return", dock, 0)
	back:SetAttribute("Seated", true) -- (from the saddle too: client/CarBoarding.luau leaves it)
	local state: DockState = { dock = dock, model = model, slots = {}, rentPrompt = empty }
	for _, slot in dock.slots do
		local ground = CFrame.lookAt(Vector3.new(slot.x, WALK_TOP, slot.z), Vector3.new(slot.x, WALK_TOP, slot.z) + (if rack then n else t))
		local s: Slot = { ground = ground, model = nil, taken = false }
		table.insert(state.slots, s)
		local ok, err = pcall(function()
			dockScooter(state, s)
		end)
		if not ok then
			warn(`[Rental] {dock.name}: no docked scooter: {err}`)
		end
	end
	local docked = false
	for _, slot in state.slots do
		docked = docked or slot.model ~= nil
	end
	empty.MaxActivationDistance = if docked then 0 else Tuning.Reach
	CollectionService:AddTag(model, Rental.DockTag)
	model.Parent = folder
	return state
end

local function freeSlot(state: DockState): number?
	for index, slot in state.slots do
		if not slot.taken then
			return index
		end
	end
	return nil
end

-- 6.10: the free slot nearest to `position` (the scooter you stand at), or nil.
local function nearestFree(state: DockState, position: Vector3): number?
	local best: number? = nil
	local bestD = math.huge
	for index, slot in state.slots do
		local d = (Vector3.new(slot.ground.Position.X - position.X, 0, slot.ground.Position.Z - position.Z)).Magnitude
		if not slot.taken and d < bestD then
			best, bestD = index, d
		end
	end
	return best
end

-- 6.10: the dock's own Rent prompt reaches only while no scooter stands in it (each one has its own Ride prompt).
local function refreshDock(state: DockState)
	local empty = state.rentPrompt
	if empty then
		empty.MaxActivationDistance = if freeSlot(state) then 0 else Tuning.Reach
	end
end

-- The nearest other dock with a scooter in it, and how far.
local function nextDock(from: DockState): (DockState?, number)
	local best: DockState? = nil
	local bestD = math.huge
	for _, state in docks do
		if state ~= from and freeSlot(state) then
			local d = math.sqrt((state.dock.x - from.dock.x) ^ 2 + (state.dock.z - from.dock.z) ^ 2)
			if d < bestD then
				best, bestD = state, d
			end
		end
	end
	return best, bestD
end

local function restock(state: DockState, index: number)
	task.delay(Tuning.Restock, function()
		local slot = state.slots[index]
		if slot and slot.taken then
			slot.taken = false
			pcall(dockScooter, state, slot)
			refreshDock(state)
		end
	end)
end

-- The rental is over (`why`: what the player is told). Its scooter goes (when it is still theirs).
local function finish(player: Player, why: string?)
	local ride = rides[player]
	if not ride then
		return
	end
	rides[player] = nil
	if player.Parent then
		player:SetAttribute("Rental", nil)
	end
	if Vehicles.get(player) == ride.car then
		Vehicles.remove(player)
	end
	restock(ride.state, ride.slot)
	if why and player.Parent then
		tell(player, why)
	end
end

-- Renting at this dock (6.10: `chosen` the slot whose Ride prompt was used; else the free one nearest to you).
function rent(player: Player, state: DockState, chosen: number?)
	local profile = PlayerData.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not profile or not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if rides[player] then
		tell(player, "You already have a ZDC RIDE scooter: hop on it, or Return it at any dock.")
		return
	end
	if humanoid.SeatPart ~= nil or Vehicles.seatedIn(player) ~= nil or character:GetAttribute("Boarding") ~= nil then
		tell(player, "Get off first: ZDC RIDE is for people on foot.")
		return
	end
	if character:GetAttribute("ZipLine") ~= nil then
		return
	end
	if (Vector3.new(root.Position.X - state.dock.x, 0, root.Position.Z - state.dock.z)).Magnitude > Tuning.Reach + state.dock.length / 2 + 4 then
		return
	end
	local picked = if chosen then state.slots[chosen] else nil
	if picked and (Vector3.new(root.Position.X - picked.ground.Position.X, 0, root.Position.Z - picked.ground.Position.Z)).Magnitude > Config.Interact.ScooterReach + 6 then
		return -- (6.10: the scooter's own prompt: you stand right at it)
	end
	if Jobs.onMission(player) then
		tell(player, "No rentals on a mission: they are counting on you.")
		return
	end
	if Jobs.active(player) and not Jobs.isFoot(player) then
		tell(player, "Not on a car job: your car is your ride.")
		return
	end
	if CarCall.busy(player) then
		tell(player, "Your car is already on the way.")
		return
	end
	if character:GetAttribute("Pushing") ~= nil then
		tell(player, "Set the trolley down first.")
		return
	end
	if not Cargo.canStowHands(player) then
		tell(player, "Your hands are full: no room in your bag.")
		return
	end
	local index = if picked and not picked.taken then chosen else nearestFree(state, root.Position)
	if not index then
		local other, far = nextDock(state)
		tell(player, if other then `This dock is empty. The next scooter: {other.dock.name}, {math.floor(far)} studs.` else "Every scooter is out. Try again in a moment.")
		return
	end
	-- 5.7: everything the rental needs is checked before your own vehicle goes home (the scooter's def, the money).
	if not Economy.findCar(Tuning.CarId) then
		warn(`[Rental] Config.Rental.CarId {Tuning.CarId} is not a car`)
		tell(player, "ZDC RIDE is not working right now.")
		return
	end
	if Tuning.Price > 0 and profile.money < Tuning.Price then
		tell(player, "Not enough money.")
		return
	end
	local own = Vehicles.get(player)
	local ownId: string?, ownFrame: CFrame? = nil, nil
	if own then
		if own.repairing then
			tell(player, "Your car is on a repair lift: wait for it, or take it off first.")
			return
		end
		ownId, ownFrame = own.id, own.chassis.CFrame
		Vehicles.remove(player)
	end
	-- 5.7: the rental did not come (an error, the save gone): your own vehicle comes back where it stood.
	local function giveOwnBack()
		if not ownId or not ownFrame or not player.Parent then
			return
		end
		local p = ownFrame.Position
		local flat = Vector3.new(ownFrame.LookVector.X, 0, ownFrame.LookVector.Z)
		local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
		local at = Vector3.new(p.X, Vehicles.groundY(p.X, p.Z, p.Y) + 0.5, p.Z)
		local ok, err = pcall(Vehicles.spawnAt, player, ownId, CFrame.lookAt(at, at + look), false)
		if not ok then
			warn(`[Rental] {player.Name}'s own vehicle could not come back: {err}`)
		end
	end
	if Tuning.Price > 0 and not PlayerData.spend(player, Tuning.Price, "Rental") then
		giveOwnBack()
		tell(player, "Not enough money.")
		return
	end
	local slot = state.slots[index]
	local x, z = slot.ground.Position.X, slot.ground.Position.Z
	local position = Vector3.new(x, Vehicles.groundY(x, z, WALK_TOP) + 0.5, z)
	local spawned, result = pcall(Vehicles.spawnAt, player, Tuning.CarId, CFrame.lookAt(position, position + slot.ground.LookVector), false, nil, true)
	local car = if spawned then result else nil
	if not car then
		if not spawned then
			warn(`[Rental] the scooter for {player.Name} failed: {result}`)
			pcall(Vehicles.remove, player) -- (a scooter half built before the error)
		end
		if Tuning.Price > 0 then
			PlayerData.addMoney(player, Tuning.Price, "Refund", "Rental")
		end
		giveOwnBack()
		tell(player, if spawned then "Still loading..." else "ZDC RIDE is not working right now: try again in a moment.")
		return
	end
	if own and not own.lent then
		local def = Economy.findCar(own.id)
		local bike = def ~= nil and def.bike == true
		tell(player, `Your {if def then def.name else "vehicle"} went home: {if bike then "MY BIKE" else "BRING MY CAR"} on your phone brings it back.`)
	end
	for _, p in car.paintParts do
		p.Color = RED
	end
	slot.taken = true
	if slot.model then
		slot.model.Parent = nil
	end
	refreshDock(state)
	rides[player] = { car = car, state = state, slot = index, leftAt = nil }
	player:SetAttribute("Rental", state.dock.id)
	PlayerData.track("event", player, "ScooterRental", 1, state.dock.id) -- 6.13
	task.defer(function()
		if not car.wrecked and car.model.Parent and humanoid.Health > 0 and humanoid.SeatPart == nil then
			Vehicles.mount(player, car, Vector3.new(state.dock.nx, 0, state.dock.nz) * Config.Interact.DockSlide) -- 5.7: it slides off the dock (6.10: as you hop on)
		end
	end)
	tell(player, "ZDC RIDE: it's yours for the ride. Leave it anywhere, or Return it at any dock.")
end

local function giveBack(player: Player, state: DockState)
	local ride = rides[player]
	if not ride then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (Vector3.new(root.Position.X - state.dock.x, 0, root.Position.Z - state.dock.z)).Magnitude > Tuning.Reach + state.dock.length / 2 + 8 then
		return
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(ride.car.model) then
		humanoid.Sit = false
	end
	finish(player, "Scooter returned. Thanks for riding ZDC RIDE!")
end

-- Every TICK: the rentals that ended some other way, the ones left behind.
local function check()
	local now = os.clock()
	for player, ride in table.clone(rides) do
		local car = ride.car
		if Vehicles.get(player) ~= car or car.wrecked or not car.model.Parent then
			-- (your own car or bike came, a shop, a respawn, a wreck: Vehicles took it already)
			rides[player] = nil
			if player.Parent then
				player:SetAttribute("Rental", nil)
			end
			restock(ride.state, ride.slot)
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if not player.Parent or not humanoid or not root or humanoid.Health <= 0 then
			finish(player, nil)
			continue
		end
		if Vehicles.seatedIn(player) == car then
			ride.leftAt = nil
			continue
		end
		ride.leftAt = ride.leftAt or now
		local away = (root.Position - car.chassis.Position).Magnitude > Tuning.WalkAway
		if away or now - (ride.leftAt :: number) > Tuning.Idle then
			finish(player, "Your ZDC RIDE scooter went back to its dock. Thanks for riding!")
		end
	end
end

-- Is this player riding (or keeping) a rental now?
function Rental.renting(player: Player): boolean
	return rides[player] ~= nil
end

function Rental.start()
	if started then
		return
	end
	started = true
	local world = workspace:FindFirstChild("World") or workspace
	local folder = Instance.new("Folder")
	folder.Name = "RentalDocks"
	folder.Parent = world
	for _, dock in RentalDocks.docks() do
		local ok, state = pcall(buildDock, folder, dock)
		if ok then
			table.insert(docks, state)
		else
			warn(`[Rental] {dock.name}: {state}`)
		end
	end
	for _, state in docks do
		for _, p in state.model:GetDescendants() do
			if p:IsA("ProximityPrompt") and p:GetAttribute("Slot") == nil then -- (6.10: a scooter's Ride prompt is wired already)
				local kind = p:GetAttribute("Kind")
				p.Triggered:Connect(function(player: Player)
					if kind == "rent" then
						rent(player, state)
					else
						giveBack(player, state)
					end
				end)
			end
		end
	end
	-- A wrecked rental: no "press CAR" (it is not yours), the zombies let go of it (Main's handler does that for cars).
	local onWrecked = Vehicles.onWrecked
	Vehicles.onWrecked = function(player: Player, car: Vehicles.Car, reason: string)
		if car.rental then
			Zombies.releaseCar(car)
			tell(player, "Your ZDC RIDE scooter broke down: it goes back by itself. Rent another at any dock.")
			return
		end
		onWrecked(player, car, reason)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < TICK then
			return
		end
		acc = 0
		check()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		finish(player, nil)
	end)
end

return Rental
