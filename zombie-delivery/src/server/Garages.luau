--!strict
-- 3.4, your cars live in garages. You switch the car you drive only at one of your garages: an owned garage or the
-- garage of an owned home (its drive-out spot, World.EstateGarages, with the GARAGE prompt World.GaragePrompts), or
-- the depot lot (the Depot Garage terminal) for what the depot keeps: the starting van, the company vehicles the
-- employers gave you (they need no slot) and, for a save from before 3.4 with more cars than slots, every car (they
-- wait at the depot until there is a garage for them).
--
-- The garage window (client/GarageUi.luau) lists your cars: the name, the capacity (Economy.capacity), the health
-- (profile.carHealth, the live car's own), the upgrades and TAKE OUT. Taking another car out parks the one you have
-- (Vehicles.remove: its damage is kept) and puts the chosen one at the garage's drive-out spot (Vehicles.placeAt).
-- Not during a delivery (the job's car stays). Calling your car (CAR, server/CarCall.luau) still brings the equipped
-- car anywhere.
-- 5.1.1: no bikes here (CarDef.bike: the bikes and the E-Scooter need no garage slot; you switch them at the BIKES counter
-- or with the phone's MY BIKE): the window leaves them out and "take" refuses one.
--
-- The "Garage" remote (shared/Net.luau):
--   client → server  ("take", car id)  take that car out here
--                    ("refresh")      send the window again (when it is open)
--   server → client  (GarageState)    { open, at, center, range, name, depot, cars = { { id, name, capacity, health,
--                                      upgrades, equipped, out, company, here } }, slots, used }: open = the prompt
--                                      was used; center / range = where a swap is accepted (flat distance)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)

local Server = script.Parent
local World = require(Server.World)
local Vehicles = require(Server.Vehicles)
local PlayerData = require(Server.PlayerData)
local Estate = require(Server.Estate)
local Jobs = require(Server.Jobs)
local CarCall = require(Server.CarCall)

local Garages = {}

local GARAGE_RANGE = 34 -- studs from a garage's drive-out spot that count as "at the garage"
local ACTION_GAP = 0.5
local DEPOT = "depot"

local remote = Net.get("Garage")
local notice = Net.get("Notice")
local lastAction: { [Player]: number } = {}
local opened: { [Player]: string } = {} -- where the player's window was opened (a garage id or "depot")

-- Short names of the car tracks for the window's upgrade line.
local SHORT: { [string]: string } = { engine = "Engine", handling = "Tyres", armor = "Armor", plow = "Plow" }

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The garages of a player's properties (homes and garages with slots) that the world placed: id → drive-out spot.
local function ownedSpots(player: Player): { [string]: CFrame }
	local list: { [string]: CFrame } = {}
	local profile = PlayerData.get(player)
	if not profile then
		return list
	end
	for id, owned in profile.properties do
		local def = Estate.find(id)
		local spot = World.EstateGarages[id]
		if owned and def and def.garageSlots > 0 and spot then
			list[id] = spot
		end
	end
	return list
end

-- Where the player stands: at one of their garages (its id), at the depot lot ("depot"), or nil.
function Garages.where(player: Player): string?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local best, bestDistance = nil :: string?, GARAGE_RANGE
	for id, spot in ownedSpots(player) do
		local d = flat(root.Position, spot.Position)
		if d < bestDistance then
			best, bestDistance = id, d
		end
	end
	if best then
		return best
	end
	local depot = Map.Shops.depot
	if depot and flat(root.Position, Vector3.new(depot.x, 0, depot.z)) < Map.ShopRadius then
		return DEPOT
	end
	return nil
end

-- More cars than slots (a save from before 3.4): they wait at the depot lot.
local function overflow(player: Player): boolean
	return Estate.carsOwned(player) > Estate.carSlots(player)
end

-- Is this car kept here? At the depot: the starting van, the company vehicles, every car of an overflowing save;
-- at a garage of yours: every car.
local function keptAt(player: Player, at: string, carId: string): boolean
	if at ~= DEPOT then
		return true
	end
	local def = Economy.findCar(carId)
	return def ~= nil and (def.id == Config.Cars[1].id or def.company == true or overflow(player))
end

local function placeName(at: string): string
	if at == DEPOT then
		return "the depot lot"
	end
	local def = Estate.find(at)
	return if def then def.name else "your garage"
end

-- The share of health of one of the player's cars: the live one's, else what it was parked with.
local function healthOf(player: Player, carId: string): number
	local car = Vehicles.get(player)
	if car and car.id == carId and not car.lent then
		return math.clamp(car.health / math.max(1, car.stats.health), 0, 1)
	end
	local profile = PlayerData.get(player)
	return if profile then (profile.carHealth[carId] or 1) else 1
end

local function upgradeLine(levels: Economy.Upgrades, gear: { [string]: boolean }?): string
	local parts: { string } = {}
	for _, def in Config.Upgrades do
		local level = levels[def.id] or 0
		if def.car and level > 0 then
			table.insert(parts, `{SHORT[def.id] or def.name} {level}`)
		end
	end
	-- 4.6: the gear installed on it (Config.Gear).
	for _, def in Config.Gear do
		if gear and gear[def.id] then
			table.insert(parts, def.name)
		end
	end
	return if #parts > 0 then table.concat(parts, " · ") else "stock"
end

local function stateFor(player: Player, at: string, open: boolean): { [string]: any }?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local live = Vehicles.get(player)
	local cars = {}
	for _, def in Config.Cars do
		if not profile.cars[def.id] or def.bike then
			continue -- (5.1.1: a bike is not kept in a garage)
		end
		local levels = Economy.carLevels(profile.carUpgrades, def.id)
		table.insert(cars, {
			id = def.id,
			stage = Economy.stageOf(def.id, levels), -- visual metadata only; server still owns progression
			paint = profile.carPaint[def.id],
			name = Economy.carTitle(def.id, levels), -- 3.5: with its stage ("Old Van · Work Van")
			capacity = Economy.capacity(def.id, levels),
			health = healthOf(player, def.id),
			upgrades = if def.company then "company vehicle" else upgradeLine(levels, Economy.installedGear(profile.carGear, def.id)),
			equipped = profile.car == def.id,
			out = live ~= nil and live.id == def.id,
			company = def.company == true,
			here = keptAt(player, at, def.id),
		})
	end
	-- Where a swap counts as "here" (Garages.where): the client closes the window outside it.
	local depot = Map.Shops.depot
	local spot = if at == DEPOT then nil else World.EstateGarages[at]
	local center = if spot then spot.Position elseif depot then Vector3.new(depot.x, 0, depot.z) else nil
	return {
		open = open,
		at = at,
		center = center,
		range = if at == DEPOT then Map.ShopRadius else GARAGE_RANGE,
		name = placeName(at),
		depot = at == DEPOT,
		cars = cars,
		slots = Estate.carSlots(player),
		used = Estate.carsOwned(player),
	}
end

local function send(player: Player, at: string, open: boolean)
	local state = stateFor(player, at, open)
	if state then
		opened[player] = at
		remote:FireClient(player, state)
	end
end

-- Opens the garage window at a garage of the player's (the GARAGE prompt) or at the depot lot (the terminal).
function Garages.open(player: Player, at: string)
	if at ~= DEPOT then
		local def = Estate.find(at)
		if not Estate.owns(player, at) then
			notice:FireClient(player, `{if def then def.name else "This garage"} is not yours. Buy it at its FOR SALE sign (ESTATE, H).`)
			return
		end
	end
	send(player, at, true)
end

-- Takes a car out at the garage the player stands at. Returns an error text, or nil when it is out.
function Garages.take(player: Player, carId: string): string?
	local profile = PlayerData.get(player)
	local def = Economy.findCar(carId)
	if not profile or not def then
		return "Still loading..."
	end
	if not profile.cars[carId] then
		return `The {def.name} is not yours.`
	end
	if def.bike then
		return `Bikes need no garage: MY BIKE on your phone (or {Config.BikeShop.Shop}) puts your {def.name} by the kerb.` -- 5.1.1
	end
	local at = Garages.where(player)
	if not at then
		return "Switch cars at one of your garages (🅿 GARAGE) or the depot lot for your starting van."
	end
	if not keptAt(player, at, carId) then
		return `The {def.name} is not kept at the depot: take it out at one of your garages (🅿 GARAGE).`
	end
	local live = Vehicles.get(player)
	if profile.car == carId and live and live.id == carId then
		return `Your {def.name} is already out.`
	end
	if Jobs.active(player) then
		return "Finish your delivery first: the job's car stays with you."
	end
	local spot = if at == DEPOT then nil else World.EstateGarages[at]
	if CarCall.busy(player) then
		CarCall.cancel(player)
	end
	local old = if live then Economy.findCar(live.id) else nil
	profile.car = carId
	PlayerData.notify(player)
	local err: string? = nil
	if spot then
		-- Not on top of the player: from the driver's seat they get into the new car; on foot on the drive-out spot
		-- they step to the post first.
		local seatedCar = Vehicles.seatedIn(player)
		local seated = live ~= nil and seatedCar == live
		local root = rootOf(player)
		local character = player.Character
		if not seated and root and character then
			local rel = spot:PointToObjectSpace(root.Position)
			-- (a long truck stands farther out: Vehicles.driveOut; the spot looks out of the door, -Z in its space)
			local out, length = Vehicles.driveOut(player, nil)
			if math.abs(rel.X) < 6 and math.abs(rel.Z + out) < math.max(12, length / 2 + 2) then
				character:PivotTo(spot * CFrame.new(-7, 3, 0))
			end
		end
		if not Vehicles.placeAt(player, nil, spot, seated) then
			err = "Still loading..."
		end
	else
		err = Vehicles.placeNear(player, nil)
	end
	if err then
		return err
	end
	local parked = if old and old.id ~= carId then ` Your {old.name} is parked in {placeName(at)}.` else ""
	notice:FireClient(player, `Your {def.name} is out.{parked}`)
	return nil
end

local function onRequest(player: Player, action: any, arg: any)
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_GAP then
		return
	end
	lastAction[player] = now
	if action == "take" and type(arg) == "string" then
		local err = Garages.take(player, arg)
		if err then
			notice:FireClient(player, err)
		end
		local at = opened[player]
		if at then
			send(player, at, false)
		end
	elseif action == "refresh" then
		local at = opened[player]
		if at then
			send(player, at, false)
		end
	end
end

function Garages.start()
	for _, entry in World.GaragePrompts do
		local id = entry.estate
		entry.prompt.Triggered:Connect(function(player)
			Garages.open(player, id)
		end)
	end
	remote.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		opened[player] = nil
	end)
end

return Garages
