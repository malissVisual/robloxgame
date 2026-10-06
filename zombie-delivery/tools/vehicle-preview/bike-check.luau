--!strict
-- 5.1: audit the real Vehicles factory's bikes (CarDef.bike) with the property recorder: Codex's art on our hidden
-- roots, the movers and joints CarVisuals needs, one doorless saddle on the leaning frame, no back, the hidden stable
-- hull, the cargo slots (the bike's own = its capacity; each piece of bike gear adds its room), display anchoring and
-- the part budget. Run by check_fleet.py next to the fleet audit (the bikes are not in the garage data).
-- 5.1.1: the E-Scooter (style "scooter", Style.stand) on its own art (ScooterArt): small wheels, no crank, a standing
-- rider (the BikeStand attribute, the seat a hip's height over the deck), the basket only (no panniers or trailer).
local Mock = require('./roblox-mock')
local Vehicles = require('./Vehicles')
local Config = require('./Config')
local Economy = require('./Economy')

local BUDGET = 80 -- BaseParts of a bike as built (art ~60 + 4 roots + chassis, hull, 4 colliders, the saddle)
local GEAR_BUDGET = 50 -- what the basket, the panniers and the trailer add at most (Codex: 10 + 11 + 25)
local ROOM = { basket = 2, panniers = 3, trailer = 4 }
local SCOOTER_BUDGET = 60 -- the E-Scooter as built (art 39 + 3 roots + chassis, hull, 4 colliders, the seat)

local function count(model: any, check: (any) -> boolean): number
	local n = 0
	for _, d in model:GetDescendants() do
		if check(d) then
			n += 1
		end
	end
	return n
end
local function isPart(d: any): boolean
	return d:IsA('BasePart')
end
local function named(model: any, name: string): any
	for _, d in model:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local bikes = 0
for _, def in Config.Cars do
	if not def.bike then
		continue
	end
	bikes += 1
	assert(not def.company and not def.mount and not def.trolley and def.stages == nil, def.id .. ': a bike has no car gun, trolley or stages')
	local built = Vehicles.__testBuild(def, Mock.Color3.fromRGB(unpack(def.color)), Mock.CFrame.identity, false, nil, nil, 0)
	local model, chassis = built.model, built.chassis
	assert(model:GetAttribute('Bike') == true and chassis.Transparency == 1, def.id .. ': a hidden hull, the Bike attribute')
	assert(built.seat ~= nil and #built.passengers == 0, def.id .. ': one saddle, no passengers')
	local style = Vehicles.__testStyle(def, 0)
	local stand = style.stand == true
	assert(stand == (def.stand == true), def.id .. ': a standing rider on a standing style only')
	assert((model:GetAttribute('BikeStand') == true) == stand, def.id .. ': the BikeStand attribute')
	local frame = model:FindFirstChild('BikeFrame')
	assert(frame and frame.Transparency == 1 and frame.Massless and not frame.CanCollide, def.id .. ': the hidden BikeFrame root')
	local lean = chassis:FindFirstChild('BikeLean')
	assert(lean and lean.ClassName == 'Motor6D' and lean.Part0 == chassis and lean.Part1 == frame, def.id .. ': the BikeLean joint')
	local crank = chassis:FindFirstChild('CrankMotor')
	if stand then
		assert(crank == nil and named(model, 'Crank') == nil, def.id .. ': no crank on a scooter')
		-- The deck under the standing rider: the seat's top about a hip's height (1.6 – 2.2) over the art's Deck point.
		local deck = frame:FindFirstChild('Deck')
		local seatTop = built.seat.Position.Y + built.seat.Size.Y / 2
		assert(deck, def.id .. ': the Deck point')
		local over = seatTop - (frame.Position.Y + deck.Position.Y)
		assert(over > 1.6 and over < 2.2, def.id .. ': the seat ' .. over .. ' over the deck')
	else
		assert(crank and crank.Part0 == frame and crank.Part1 and crank.Part1.Name == 'Crank', def.id .. ': the CrankMotor joint')
	end
	local wheels = 0
	for _, d in chassis:GetChildren() do
		if d.Name == 'WheelMotor' then
			wheels += 1
			assert(d.Part0 == frame and d:GetAttribute('Radius') == style.wheel and style.wheel == (if stand then 0.6 else 1.3), def.id .. ': a wheel on the leaning frame')
		end
	end
	assert(wheels == 2, def.id .. ': two visible wheels')
	assert(count(model, function(d) return d.Name == 'WheelCollider' and d.CanCollide and d.Transparency == 1 end) == 4, def.id .. ': four hidden colliders')
	assert(count(model, function(d) return d.Name == 'DoorHinge' or d.Name == 'BackHinge' or d.Name == 'BackPrompt' or d.Name == 'RidePrompt' end) == 0, def.id .. ': no doors, no back')
	assert(count(model, function(d) return d.Name == 'DrivePrompt' end) == 1, def.id .. ': one Drive prompt (the saddle)')
	assert(chassis:FindFirstChild('KeepUpright') and chassis:FindFirstChild('Drive') and chassis:FindFirstChild('Steer') and chassis:FindFirstChild('CargoDoor'), def.id .. ': the movers, kept upright, the cargo door')
	local seatWelded = false
	for _, d in built.seat:GetChildren() do
		if d.ClassName == 'WeldConstraint' and d.Part0 == frame then
			seatWelded = true
		end
	end
	assert(seatWelded, def.id .. ': the saddle leans with the frame')
	-- The art: visible, welded, never physics.
	local art = model:FindFirstChild(def.id .. 'Art')
	assert(art, def.id .. ': Codex art built from its own id')
	for _, p in art:GetDescendants() do
		if p:IsA('BasePart') then
			assert(not p.CanCollide and not p.CanQuery and not p.CanTouch and p.Massless and not p.Anchored, p.Name .. ' affects physics')
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA('BasePart') and d.CanCollide then
			assert(d.Transparency == 1, def.id .. ': a visible collider ' .. d.Name)
		end
	end
	assert(named(model, 'Headlight') == nil and named(model, 'Tyre') == nil, def.id .. ': no car lamps or car tyres')
	assert(named(model, 'BikeLamp') ~= nil, def.id .. ': a small beam at night')
	local parts = count(model, isPart)
	assert(parts <= (if stand then SCOOTER_BUDGET else BUDGET), def.id .. ': ' .. parts .. ' parts (budget ' .. BUDGET .. ')')
	-- The cargo: its own slots = its capacity; every piece of bike gear adds its room.
	local car: any = { id = def.id, stage = 0, gear = {} }
	assert(#Vehicles.cargoSlots(car) == def.capacity and Economy.capacity(def.id, {}, {}, nil) == def.capacity, def.id .. ': slots = capacity')
	local gear: { [string]: boolean } = {}
	for _, g in Config.Gear do
		if g.bikeOnly and Economy.gearFits(def.id, g.id) then
			gear[g.id] = true
		end
	end
	assert(gear.basket and (gear.panniers == true) == not stand and (gear.trailer == true) == (def.id ~= 'cargobike' and not stand), def.id .. ': the bike gear it takes')
	car.gear = gear
	local want = def.capacity
	for id in gear do
		local g = Economy.findGear(id)
		want += if g and g.room then g.room else ROOM[id]
	end
	local slots = Vehicles.cargoSlots(car)
	assert(#slots == want, def.id .. ': ' .. #slots .. ' slots with its gear, ' .. want .. ' wanted')
	for _, slot in slots do
		local y = slot.Position.Y + chassis.Position.Y -- (the bike stands on the ground at y = 0)
		assert(y > 0.3 and y < 4, def.id .. ': a cargo slot at ' .. y .. ' over the ground')
	end
	-- The gear on the kit: Codex's pieces, the trailer's wheels on WheelMotors in the kit.
	Vehicles.__testBuildKit(model, chassis, Vehicles.__testStyle(def, 0), {}, def.id, gear)
	local kit = model:FindFirstChild('UpgradeKit')
	assert(kit and model:GetAttribute('KitBuilt') == 1, def.id .. ': the kit, KitBuilt')
	assert(named(kit, 'basketArt') and (named(kit, 'panniersArt') ~= nil) == (gear.panniers == true), def.id .. ': basket and panniers shown')
	assert((named(kit, 'trailerArt') ~= nil) == (gear.trailer == true), def.id .. ': the trailer shown when installed')
	assert(count(kit, function(d) return d.Name == 'WheelMotor' end) == (if gear.trailer then 2 else 0), def.id .. ': the trailer wheels turn')
	assert(count(kit, function(d) return d.Name == 'BullBar' or d.Name == 'ArmorPlate' or d.Name == 'FoldedTrolley' end) == 0, def.id .. ': no car kit')
	local gearParts = count(kit, isPart)
	assert(gearParts <= GEAR_BUDGET, def.id .. ': gear ' .. gearParts .. ' parts')
	-- Rebuilding the kit leaves no stale pieces behind.
	Vehicles.__testBuildKit(model, chassis, Vehicles.__testStyle(def, 0), {}, def.id, {})
	assert(count(model:FindFirstChild('UpgradeKit'), isPart) == 0, def.id .. ': an empty kit without gear')
	-- The showroom: anchored all through.
	local shown = Vehicles.displayModel(def, Mock.CFrame.identity, 0)
	for _, d in shown:GetDescendants() do
		if d:IsA('BasePart') then
			assert(d.Anchored, def.id .. ': unanchored display part ' .. d.Name)
		end
	end
	print(string.format('  %-9s %2d parts, %d slot(s), %2d with its gear (+%d gear parts)', def.id, parts, def.capacity, #slots, gearParts))
end
assert(bikes == 5, 'four bikes and the E-Scooter')
print('Bike PASS: 4 bikes on Codex art and the E-Scooter on its own, hidden hull and colliders, leaning saddle / standing deck, two wheels (and a crank on a bike), no back, slots = capacity + gear room, display anchored')
