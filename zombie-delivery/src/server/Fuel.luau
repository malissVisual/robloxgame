--!strict
-- 5.4, fuel (Config.Fuel, shared/FuelMath.luau): the tanks, the burn, the pumps, the jerry can and the tow. The server
-- decides every litre and every dollar; the clients only read the car's attributes and ask through the Fuel remote.
--
--   * The tank: every car (not a bike) Vehicles builds gets the attributes Tank (litres) and Fuel (litres, 0.01 L steps)
--     before anybody drives it (Vehicles.onSpawned). Your own cars keep their level in profile.carFuel (saved; a car
--     with no entry, a new one, comes full), so a call, a rebuild, a repair or a garage swap keeps it; a company vehicle
--     a job lends you comes full and is not kept.
--   * The burn: every Config.Fuel.Tick s the chassis' flat distance since the last tick, while somebody sits in the
--     driver's seat (never while a chauffeur drives it or it stands on a repair lift), burns CarDef.burn litres per
--     1,000 studs; a jump of more than MaxJump studs (a teleport, the tow, a rebuild) burns nothing. Empty, the car
--     crawls (client/Drive.luau).
--   * The pumps (World.GasPumps: the Refuel prompt, hold): on foot, your car parked with its body within PumpReach
--     studs of the pump and standing still, the pump pours PourRate litres a second into it and charges as it pours
--     (FuelMath.pourStep: whole dollars, never more than you have; the cents of the last litre at the end), until the
--     tank is full, the money runs out, you walk off (PumpWalk), the car moves or you use the prompt again. The pump's
--     display shows the litres and the total; one driver at a pump at a time.
--   * The kiosks (World.GasKiosks): a jerry can for its Config.Items price (it goes in your items: key 6). Using one
--     (server/Items.luau → Fuel.pourCan) pours CanLitres into your car while you stand by it (CanReach) or sit in it.
--   * The tow (the phone's TOW, the Fuel remote's "tow"): only with an empty tank and TowPrice in your pocket; CarCall.tow
--     takes the car (and you, in it or close by) to the nearest station's free bay with TowLitres in the tank.
--   * The admin's REFUEL / EMPTY TANK (server/Admin.luau "refuel"): Fuel.adminFill.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local FuelMath = require(Shared.FuelMath)
local Map = require(Shared.Map)
local Net = require(Shared.Net)

local Server = script.Parent
local World = require(Server.World)
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local CarCall = require(Server.CarCall)

local Tuning = Config.Fuel
local PUMP_ROOM = 1.3 -- studs from a pump's middle a car's side keeps (its collider is 1.9 wide)
local POST_OUT = 10.7 -- studs from a pump's middle to just outside an island canopy's posts (server/GasArt: 10)

local Fuel = {}

local notice = Net.get("Notice")

-- The exact litres in every car's tank (the attribute carries them rounded) and where its chassis stood last tick.
local levels: { [Model]: number } = {}
local lastAt: { [Model]: Vector3 } = {}

type Pour = {
	player: Player,
	car: Vehicles.Car,
	pump: World.GasPump,
	poured: number, -- litres this time
	charged: number, -- whole dollars taken so far
	at: number, -- os.clock() of the last step
}
local pours: { [Player]: Pour } = {}
local pumpUser: { [BasePart]: Player } = {}
local towing: { [Player]: boolean } = {}
local lastAsk: { [Player]: number } = {}

local function defOf(car: Vehicles.Car): Config.CarDef?
	return Economy.findCar(car.id)
end

-- Is this car's level kept in its owner's profile (your own car; never a lent or company vehicle)?
local function kept(car: Vehicles.Car): boolean
	local def = defOf(car)
	return not car.lent and def ~= nil and def.company ~= true
end

local function money(player: Player): number
	local profile = PlayerData.get(player)
	return if profile then profile.money else 0
end

local function dollars(amount: number): string
	return "$" .. tostring(math.floor(amount + 0.5))
end

-- Studs (flat) from a point to the car's body (its hull box around the chassis; 0 inside).
local function bodyGap(car: Vehicles.Car, point: Vector3): number
	local relative = car.chassis.CFrame:PointToObjectSpace(point)
	local dx = math.max(math.abs(relative.X) - car.size.X / 2, 0)
	local dz = math.max(math.abs(relative.Z) - car.size.Z / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then root else nil
end

-- ── The tank ───────────────────────────────────────────────────────────────

-- The tank of this car in litres (0: no fuel, a bike).
function Fuel.tankOf(car: Vehicles.Car): number
	return FuelMath.tank(defOf(car))
end

-- The litres in the car's tank now.
function Fuel.level(car: Vehicles.Car): number
	return levels[car.model] or Fuel.tankOf(car)
end

-- Sets the litres in the car's tank (kept within it): the attributes, and the owner's profile for an own car.
function Fuel.set(car: Vehicles.Car, litres: number)
	local tank = Fuel.tankOf(car)
	if tank <= 0 or litres ~= litres then
		return
	end
	local value = math.clamp(litres, 0, tank)
	levels[car.model] = value
	local shown = math.floor(value * 100 + 0.5) / 100
	if car.model:GetAttribute("Fuel") ~= shown then
		car.model:SetAttribute("Fuel", shown)
	end
	if kept(car) then
		local profile = PlayerData.get(car.owner)
		if profile then
			profile.carFuel[car.id] = value
		end
	end
end

-- Pours `litres` into the car's tank; returns how many went in.
function Fuel.add(car: Vehicles.Car, litres: number): number
	local before = Fuel.level(car)
	Fuel.set(car, before + math.max(0, litres))
	return Fuel.level(car) - before
end

-- A car was just built (Vehicles.onSpawned): its tank as it was (an own car: profile.carFuel, else full).
local function onSpawned(car: Vehicles.Car)
	local tank = Fuel.tankOf(car)
	if tank <= 0 then
		return -- a bike: no fuel
	end
	local litres = tank
	if kept(car) then
		local profile = PlayerData.get(car.owner)
		local saved = profile and profile.carFuel[car.id]
		if saved then
			litres = math.clamp(saved, 0, tank)
		end
	end
	car.model:SetAttribute("Tank", tank)
	lastAt[car.model] = nil
	Fuel.set(car, litres)
end

-- The burn: every Tick, each driven car by the flat distance its chassis moved.
local function burnAll()
	for model in levels do
		if not model.Parent then
			levels[model] = nil
			lastAt[model] = nil
		end
	end
	for _, car in Vehicles.all() do
		local litres = levels[car.model]
		if not litres then
			continue
		end
		local p = car.chassis.Position
		local here = Vector3.new(p.X, 0, p.Z)
		local before = lastAt[car.model]
		lastAt[car.model] = here
		if not before or car.chauffeured or car.repairing or car.seat.Occupant == nil then
			continue
		end
		local moved = (here - before).Magnitude
		if moved > Tuning.MaxJump or moved < 0.05 or litres <= 0 then
			continue
		end
		Fuel.set(car, litres - FuelMath.burn(defOf(car), moved))
	end
end

-- ── The pumps ──────────────────────────────────────────────────────────────

local function showPump(pump: World.GasPump, litres: number, total: number)
	local l, t = pump.labels.Litres, pump.labels.Total
	if l then
		l.Text = string.format("%.2f L", litres)
	end
	if t then
		t.Text = string.format("$%.2f", total)
	end
end

-- Stops a driver's pouring: the cents of the last litre taken (when there is the money), the pump free again.
local function stopPour(player: Player, why: string?)
	local pour = pours[player]
	if not pour then
		return
	end
	pours[player] = nil
	if pumpUser[pour.pump.part] == player then
		pumpUser[pour.pump.part] = nil
	end
	pour.pump.prompt.ActionText = "Refuel"
	local rest = FuelMath.settle(pour.poured, pour.charged)
	if rest > 0 and money(player) >= rest and PlayerData.spend(player, rest) then
		pour.charged += rest
	end
	showPump(pour.pump, pour.poured, FuelMath.cost(pour.poured))
	if not player.Parent then
		return
	end
	local what = string.format("%.1f L for %s", pour.poured, dollars(pour.charged))
	if why == "full" then
		notice:FireClient(player, `Tank full: {what}.`)
	elseif why == "money" then
		notice:FireClient(player, `Out of money: {what}.`)
	elseif pour.poured > 0.05 then
		notice:FireClient(player, `Refuel stopped: {what}{if why then ` ({why})` else ""}.`)
	elseif why then
		notice:FireClient(player, `Refuel stopped: {why}.`)
	end
end

-- Why this driver cannot pour into this car at this pump now (nil: they can).
local function cannotPour(player: Player, car: Vehicles.Car?, pump: World.GasPump): string?
	local root = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return "you are not here"
	elseif humanoid.SeatPart then
		return "get out of the car to refuel"
	elseif (root.Position - pump.part.Position).Magnitude > Tuning.PumpWalk then
		return "you walked away from the pump"
	elseif not car or car.wrecked or not car.chassis.Parent then
		return "no car of yours at the pump"
	elseif Fuel.tankOf(car) <= 0 then
		return "a bike takes no fuel"
	elseif car.chauffeured or car.repairing then
		return "your car is busy"
	elseif bodyGap(car, pump.part.Position) > Tuning.PumpReach then
		return `park your car next to the pump (within {Tuning.PumpReach} studs)`
	elseif Vector3.new(car.chassis.AssemblyLinearVelocity.X, 0, car.chassis.AssemblyLinearVelocity.Z).Magnitude > 3 then
		return "the car must stand still"
	end
	return nil
end

-- The Refuel prompt: starts pouring (or, pouring here already, stops).
local function onPump(player: Player, pump: World.GasPump)
	local pour = pours[player]
	if pour then
		local same = pour.pump == pump
		stopPour(player, if same then nil else "you went to another pump")
		if same then
			return
		end
	end
	local user = pumpUser[pump.part]
	if user and user ~= player and pours[user] then
		notice:FireClient(player, "Somebody is filling up at this pump. Take the other one.")
		return
	end
	local car = Vehicles.get(player)
	local why = cannotPour(player, car, pump)
	if why or not car then
		local text = why or "no car of yours at the pump"
		notice:FireClient(player, string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2) .. ".")
		return
	end
	if Fuel.tankOf(car) - Fuel.level(car) < 0.05 then
		notice:FireClient(player, "The tank is full.")
		return
	end
	if money(player) < Tuning.PricePerLitre then
		notice:FireClient(player, `No money for fuel ({string.format("$%.2f", Tuning.PricePerLitre)} a litre).`)
		return
	end
	pours[player] = { player = player, car = car, pump = pump, poured = 0, charged = 0, at = os.clock() }
	pumpUser[pump.part] = player
	pump.prompt.ActionText = "Stop"
	showPump(pump, 0, 0)
end

-- One step of every pump that pours.
local function pourAll()
	local now = os.clock()
	for player, pour in pours do
		local seconds = math.min(now - pour.at, 0.5)
		pour.at = now
		local car = pour.car
		local why = cannotPour(player, if Vehicles.get(player) == car then car else nil, pour.pump)
		if why then
			stopPour(player, why)
			continue
		end
		local level = Fuel.level(car)
		local missing = Fuel.tankOf(car) - level
		local litres, due = FuelMath.pourStep(missing, seconds, pour.poured, pour.charged, money(player))
		if due > 0 and not PlayerData.spend(player, due) then
			stopPour(player, "money")
			continue
		end
		pour.charged += due
		pour.poured += litres
		Fuel.set(car, level + litres)
		showPump(pour.pump, pour.poured, FuelMath.cost(pour.poured))
		if missing - litres <= 0.01 then
			stopPour(player, "full")
		elseif litres <= 0 and seconds > 0 then
			stopPour(player, "money")
		end
	end
end

-- ── The jerry can, the kiosk ───────────────────────────────────────────────

-- Using a jerry can (server/Items.luau): an error text, or nil when it was poured (the can is then used up).
function Fuel.pourCan(player: Player): string?
	local car = Vehicles.get(player)
	if not car or car.wrecked then
		return "No car of yours to pour the jerry can into."
	end
	if Fuel.tankOf(car) <= 0 then
		return "Your bike takes no fuel."
	end
	local inside = Vehicles.seatedIn(player) == car
	local root = rootOf(player)
	if not inside and (not root or bodyGap(car, root.Position) > Tuning.CanReach) then
		return "Stand next to your car to pour the jerry can."
	end
	if Fuel.tankOf(car) - Fuel.level(car) < 0.05 then
		return "The tank is full."
	end
	local added = Fuel.add(car, Tuning.CanLitres)
	notice:FireClient(player, string.format("+%.1f L from the jerry can.", added))
	return nil
end

local function onKiosk(player: Player)
	local def = Economy.findItem("jerrycan")
	local profile = PlayerData.get(player)
	if not def or not profile then
		return
	end
	if (profile.items[def.id] or 0) >= def.max then
		notice:FireClient(player, `You carry {def.max} jerry cans already.`)
		return
	end
	if not PlayerData.spend(player, def.price) then
		notice:FireClient(player, `A jerry can costs {dollars(def.price)}.`)
		return
	end
	PlayerData.addItem(player, def.id, 1)
	notice:FireClient(player, `Jerry can bought: +{Tuning.CanLitres} L. Use it next to your car (key 6).`)
end

-- ── The tow ────────────────────────────────────────────────────────────────

-- The free bay of a station nearest to the car (a bay with no other car on it), else its first.
local function freeBay(station: Map.GasStation, car: Vehicles.Car): Map.GasBay
	local best: Map.GasBay = station.bays[1]
	local bestD = math.huge
	for _, bay in station.bays do
		local taken = false
		for _, other in Vehicles.all() do
			local p = other.chassis.Position
			if other ~= car and (Vector3.new(p.X, 0, p.Z) - Vector3.new(bay.x, 0, bay.z)).Magnitude < 8 then
				taken = true
			end
		end
		local p = car.chassis.Position
		local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(bay.x, 0, bay.z)).Magnitude
		if not taken and d < bestD then
			best, bestD = bay, d
		end
	end
	return best
end

-- The phone's TOW: an error text, or nil when the car was towed.
function Fuel.tow(player: Player): string?
	local car = Vehicles.get(player)
	if not car or car.wrecked then
		return "No car of yours to tow."
	end
	if Fuel.tankOf(car) <= 0 then
		return "A bike needs no tow."
	end
	if CarCall.busy(player) or car.chauffeured then
		return "Your car is on its way already."
	end
	if car.repairing then
		return "Your car is in the repair shop."
	end
	if not FuelMath.isEmpty(Fuel.level(car)) then
		return "The tow only comes for an empty tank. Drive to a pump (MAP: the gas stations)."
	end
	if towing[player] then
		return nil
	end
	if money(player) < Tuning.TowPrice then
		return `The tow costs {dollars(Tuning.TowPrice)}. A jerry can (Last Stop Supplies) or a crawl to a pump will do too.`
	end
	local p = car.chassis.Position
	local station = Map.nearestGas(p.X, p.Z)
	local bay = freeBay(station, car)
	if not PlayerData.spend(player, Tuning.TowPrice) then
		return `The tow costs {dollars(Tuning.TowPrice)}.`
	end
	towing[player] = true
	stopPour(player)
	-- Out of the bay away from the pump: its pump is on the car's right or left (looking out of the station).
	local pump = station.pumps[bay.pump]
	local across = -1
	local x, z = bay.x, bay.z
	if pump then
		local right = Vector3.new(-bay.look.z, 0, bay.look.x)
		local away = Vector3.new(bay.x - pump.x, 0, bay.z - pump.z)
		across = if right:Dot(away) < 0 then -1 else 1
		-- A wide vehicle (wider than the bay: the Freight Truck) stands farther out: clear of the pump, and at a new
		-- station clear of the canopy's posts (GasArt's island: posts 10 studs out from the pumps), still in reach.
		local half, gap = car.size.X / 2, away.Magnitude
		if gap > 0.1 and half + PUMP_ROOM > gap then
			local out = if station.id ~= "gas" then POST_OUT + half else half + PUMP_ROOM
			local spot = Vector3.new(pump.x, 0, pump.z) + away.Unit * out
			x, z = spot.X, spot.Z
		end
	end
	local from = Vector3.new(x, p.Y, z)
	local ok = CarCall.tow(player, car, CFrame.lookAt(from, from + Vector3.new(bay.look.x, 0, bay.look.z)), across)
	towing[player] = nil
	if not ok then
		local profile = PlayerData.get(player)
		if profile then
			profile.money += Tuning.TowPrice -- (back: not earned money)
			PlayerData.notify(player)
		end
		return "The tow truck can't come right now. Try again in a moment."
	end
	lastAt[car.model] = nil
	Fuel.set(car, Tuning.TowLitres)
	notice:FireClient(player, `Towed to {station.name}: {Tuning.TowLitres} L in the tank. Hold E at the pump to fill up.`)
	return nil
end

-- ── Admin ──────────────────────────────────────────────────────────────────

-- The admin's REFUEL (share 1, the default) or EMPTY TANK (share 0) on the player's car: what to say.
function Fuel.adminFill(player: Player, share: number?): string
	local car = Vehicles.get(player)
	if not car then
		return "ADMIN: no car out to fill."
	end
	local tank = Fuel.tankOf(car)
	if tank <= 0 then
		return "ADMIN: a bike takes no fuel."
	end
	local s = math.clamp(if share and share == share then share else 1, 0, 1)
	stopPour(player)
	Fuel.set(car, tank * s)
	return if s <= 0 then "ADMIN: your tank is empty (it crawls now; the phone shows TOW)." else string.format("ADMIN: %.0f L in your tank.", tank * s)
end

function Fuel.start()
	Vehicles.onSpawned = onSpawned
	for _, car in Vehicles.all() do
		onSpawned(car)
	end
	for _, pump in World.GasPumps do
		pump.prompt.Triggered:Connect(function(player: Player)
			onPump(player, pump)
		end)
	end
	for _, kiosk in World.GasKiosks do
		kiosk.prompt.Triggered:Connect(onKiosk)
	end
	Net.get("Fuel").OnServerEvent:Connect(function(player: Player, action: any)
		local now = os.clock()
		if now - (lastAsk[player] or -1) < 1 then
			return
		end
		lastAsk[player] = now
		if action == "tow" then
			local err = Fuel.tow(player)
			if err then
				notice:FireClient(player, err)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		stopPour(player)
		towing[player] = nil
		lastAsk[player] = nil
	end)
	task.spawn(function()
		local sinceBurn = 0
		while true do
			local dt = task.wait(0.1)
			pourAll()
			sinceBurn += dt
			if sinceBurn >= Tuning.Tick then
				sinceBurn = 0
				burnAll()
			end
		end
	end)
end

return Fuel
