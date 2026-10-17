--!strict
-- 6.26: no vehicle touches the ground with anything but its wheels (the owner's tilted ZDC Van: its bumper boxes hung
-- 0.155 under its chassis, the fleet's lowest hull, and its nose came to rest on one). Every car of Config.Cars at
-- every stage, with its full kit and all the gear that fits it, the bikes, the E-Scooter and the company vehicles, as
-- the real factory builds a player's (Vehicles build + buildKit), standing on the ground (y = 0):
--   * the wheels' contact plane is the bottom of its wheel colliders;
--   * every other part that collides is at least MARGIN over it (the hull boxes, the chassis, the kit);
--   * whatever collides past its axles leaves the climb of the steepest road (14°) with ROOM to spare at the front
--     (approach) and the back (departure), from the wheel's contact under its axle;
--   * nothing that swings (a cab door, a back door, a tailgate, a ramp, what is welded onto them) and nothing on the
--     body that sways (the BodyRoot) collides: an open door never props the car up;
--   * the ZDC Van (the Old Van's size and wheels) rides no lower than the Old Van;
--   * the spawn's rays (Vehicles' wheelsOf) look under its four wheel colliders (a bike's too).
-- Run by check_fleet.py.
local Mock = require("./roblox-mock")
local Vehicles = require("./Vehicles")
local Config = require("./Config")
local Economy = require("./Economy")

local MARGIN = 0.25 -- studs over the wheels' contact plane (the E-Scooter's deck is the lowest hull: 0.3)
local CLIMB, ROOM = 14, 1 -- degrees: the steepest road (Map's curb grade), and the spare

local function extent(p: any): (number, number, number)
	local r, s = p.CFrame.R, p.Size -- (the mock's rotation, row by row: its second row is the world's up)
	local ry = math.abs(r[4]) * s.X / 2 + math.abs(r[5]) * s.Y / 2 + math.abs(r[6]) * s.Z / 2
	local rz = math.abs(r[7]) * s.X / 2 + math.abs(r[8]) * s.Y / 2 + math.abs(r[9]) * s.Z / 2
	return p.Position.Y - ry, p.Position.Z - rz, p.Position.Z + rz
end

local checked, lowestAll, lowestWho = 0, math.huge, ""
local lowestOf: { [string]: number } = {}
-- 7.x (one car): every body the factory builds: the player's (Config.Cars: the ZDC Van, the bikes) and the world's
-- (Config.AmbientCars: the old cars the traffic and Earl's lot still show, the company vehicles), in the old Config.Cars
-- order (the ZDC Van after the Pickup, where it stood: the garage snapshots' colours follow the order)
local ALL = {}
for _, d in Config.AmbientCars do
	table.insert(ALL, d)
	if d.id == "pickup" then
		for _, c in Config.Cars do
			table.insert(ALL, c)
		end
	end
end
for _, def in ALL do
	local gear = {}
	for _, piece in Config.Gear do
		if Economy.gearFits(def.id, piece.id) then
			gear[piece.id] = true
		end
	end
	for stage = 0, Economy.maxStage(def.id) do
		local built = Vehicles.__testBuild(def, Mock.Color3.fromRGB(200, 200, 200), Mock.CFrame.identity, false, nil, nil, stage)
		Vehicles.__testBuildKit(built.model, built.chassis, Vehicles.__testStyle(def, stage), { engine = 5, handling = 5, armor = 5, plow = 5 }, def.id, gear)
		local who = `{def.id} stage {stage}`
		local parts = built.model:GetDescendants()
		-- The parts that swing (on a DoorHinge / BackHinge) or sway (on the BodyRoot) and everything welded onto them.
		local moving: { [any]: string } = {}
		for _, d in parts do
			if d.ClassName == "Motor6D" and (d.Name == "DoorHinge" or d.Name == "BackHinge" or d.Name == "BodyRoll") then
				moving[d.Part1] = d.Name
			end
		end
		local grew = true
		while grew do
			grew = false
			for _, d in parts do
				if d.ClassName == "WeldConstraint" and moving[d.Part0] and not moving[d.Part1] then
					moving[d.Part1] = moving[d.Part0]
					grew = true
				end
			end
		end
		local contact, front, back = math.huge, math.huge, -math.huge
		for _, p in parts do
			if p:IsA("BasePart") and p.CanCollide and p.Name == "WheelCollider" then
				local y = extent(p)
				contact = math.min(contact, y)
				front, back = math.min(front, p.Position.Z), math.max(back, p.Position.Z)
			end
		end
		assert(contact < math.huge, `{who} has no wheel colliders`)
		-- The spawn's rays look under the wheels where the factory puts them (findRoom: wheelsOf; a bike's own spots).
		local colliders = {}
		for _, p in parts do
			if p:IsA("BasePart") and p.Name == "WheelCollider" then
				table.insert(colliders, p.Position)
			end
		end
		table.sort(colliders, function(a: any, b: any): boolean
			if math.abs(a.Z - b.Z) > 0.01 then
				return a.Z < b.Z
			end
			return a.X < b.X
		end)
		local spots = Vehicles.__testWheels(def, Vehicles.__testStyle(def, stage))
		assert(#spots == 4 and #colliders == 4, `{who}: {#colliders} wheel colliders, {#spots} spawn spots`)
		for n, spot in spots do
			assert(math.abs(spot.x - colliders[n].X) < 1e-6 and math.abs(spot.z - colliders[n].Z) < 1e-6,
				string.format("%s: the spawn looks under (%.2f, %.2f), the wheel stands at (%.2f, %.2f)", who, spot.x, spot.z, colliders[n].X, colliders[n].Z))
		end
		local lowest = math.huge
		for _, p in parts do
			if not p:IsA("BasePart") then
				continue
			end
			if moving[p] then
				assert(not p.CanCollide, `{who}: {p.Name} on the {moving[p]} collides (it swings or sways: it would prop the car up)`)
			end
			if not p.CanCollide or p.Name == "WheelCollider" then
				continue
			end
			local y, z0, z1 = extent(p)
			local over = y - contact
			lowest = math.min(lowest, over)
			assert(over >= MARGIN - 1e-6, string.format("%s: %s collides %.2f over the wheels' ground (at least %.2f)", who, p.Name, over, MARGIN))
			if z0 < front then
				local angle = math.deg(math.atan2(over, front - z0))
				assert(angle >= CLIMB + ROOM - 1e-6, string.format("%s: %s in front leaves an approach of %.1f° (at least %d°)", who, p.Name, angle, CLIMB + ROOM))
			end
			if z1 > back then
				local angle = math.deg(math.atan2(over, z1 - back))
				assert(angle >= CLIMB + ROOM - 1e-6, string.format("%s: %s behind leaves a departure of %.1f° (at least %d°)", who, p.Name, angle, CLIMB + ROOM))
			end
		end
		lowestOf[def.id] = math.min(lowestOf[def.id] or math.huge, lowest)
		if lowest < lowestAll then
			lowestAll, lowestWho = lowest, who
		end
		checked += 1
	end
end
assert(lowestOf.zdcvan and lowestOf.van and lowestOf.zdcvan >= lowestOf.van - 1e-6,
	string.format("the Deliveros Van's lowest hull is %.2f over its wheels' ground, the Old Van's %.2f: it rides lower", lowestOf.zdcvan or -1, lowestOf.van or -1))
print(string.format("Ground PASS: %d builds (every car, stage, bike and company vehicle with its full kit): only the wheels touch the ground (the lowest hull %.2f over it: %s; the Deliveros Van %.2f, the Old Van %.2f), %d°+ approach and departure, nothing that swings or sways collides, the spawn's rays under every wheel",
	checked, lowestAll, lowestWho, lowestOf.zdcvan, lowestOf.van, CLIMB + ROOM))
