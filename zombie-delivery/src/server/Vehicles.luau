--!strict
-- The cars. Each player has at most one car in the world, built in code from its style.
--
-- Driving is arcade, not wheel physics: invisible frictionless wheel colliders (they ride over curbs) and two
-- constraints on the chassis move the car. A LinearVelocity in the ground plane (gravity still works) and an
-- AngularVelocity that turns it around the vertical axis and keeps it upright. The owner's client simulates the car
-- (network owner) and sets both constraints from the VehicleSeat's throttle / steer (client/Drive.luau), the
-- server only reads where the car is and how fast it goes (ramming, deliveries).
--
-- The visible tyres hang on Motor6Ds that every client spins and steers (client/CarVisuals.luau).
-- Other players ride along in the passenger seats (the "Ride" prompt) and shoot from there (server/Gun.luau).
--
-- A car has no roof gun until one is bought at Wrench Garage (Config.CarGuns, profile.carGuns, only on the cars with
-- CarDef.mount). Then a turret with that gun's look sits on the roof: the model "CarGun" inside the car, its "Barrel"
-- part holds the "Muzzle" attachment (client/Shooting.luau draws the tracers from there), and the car model carries
-- the attribute CarGun = the gun's id (the clients read it).
--
-- Lights: every car (the players', the bandits', the traffic's) has headlights and tail lights that glow at night
-- (registered with server/DayNight.luau, which switches them with the workspace attribute "Night"); the headlights
-- carry SpotLights (two on a player's car, one on an NPC car: cheap). The ambulance has a roof light bar: its lenses
-- are tagged "SirenLight" and flash on every client (client/Weather.luau) while the car's attribute Siren is true
-- (a company ambulance lent for a job, or Vehicles.setSiren).
--
-- Calling the car (the CAR button: Vehicles.spawn without force) goes to server/CarCall.luau through the hook
-- Vehicles.callCar: a chauffeur drives it to you. While a chauffeur drives a car (car.chauffeured) the SERVER owns
-- and drives it, its Drive / Ride prompts wait in the folder "ParkedPrompts" (client/CarVisuals.luau only looks on
-- the chassis) and nobody gets in; Vehicles.handOver gives it to its owner (the prompts come back, the owner's
-- client owns it again). The instant cases stay instant (force: PLAY, a respawn, a car bought or equipped, a job's
-- vehicle): next to you and seated, or, when you spawn at home, parked at your home's garage drive-out spot (the
-- hook Vehicles.homeGarage).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local PlayerData = require(script.Parent.PlayerData)
local DayNight = require(script.Parent.DayNight)

export type Car = {
	owner: Player,
	id: string,
	model: Model,
	chassis: Part,
	seat: VehicleSeat,
	passengers: { Seat },
	turret: Weld?, -- the roof gun's turning joint; nil = no car gun on this car
	turretBase: CFrame, -- where a roof gun sits (relative to the chassis), with a gun or without
	muzzle: Attachment?,
	gunId: string?, -- the car gun installed (Config.CarGuns)
	paintParts: { BasePart },
	size: Vector3, -- the hull (width, height, length) for ramming and latching
	stats: Economy.CarStats,
	health: number,
	wrecked: boolean,
	latched: { [number]: boolean }, -- taken latch slots
	chauffeured: boolean, -- a chauffeur drives it to its owner (server/CarCall.luau): server-owned, no prompts
	born: number, -- os.clock() when it was placed
}

local Vehicles = {}

local cars: { [Player]: Car } = {}
local lastSpawn: { [Player]: number } = {}

-- Set by Main: (player, car, reason) when a car is destroyed.
Vehicles.onWrecked = function(_player: Player, _car: Car, _reason: string) end

local DARK = Color3.fromRGB(34, 34, 38)
local GLASS = Color3.fromRGB(150, 190, 210)

type Box = { size: Vector3, offset: Vector3, kind: string } -- kind: body | dark | glass | accent | plate | white | ball | logo | wood | rail | cross | sirenred | sirenblue | lightbar

-- Where the cargo rides (server/Cargo.luau): the slots are the bottom centres of the pieces (facing the front),
-- the door is where you load at the back, the entry is where passengers (the school kids) get in.
type CargoSpec = {
	slots: { Vector3 },
	noun: string, -- "Load it into the back of the {noun}"
	door: Vector3,
	entry: Vector3,
}

type Style = {
	width: number,
	length: number,
	wheel: number, -- radius
	wheelWidth: number,
	clearance: number, -- chassis bottom above the ground
	seat: Vector3, -- the driver, relative to the chassis top centre
	passengers: { Vector3 },
	roof: number, -- turret height above the chassis top
	head: Vector2?, -- the headlights' height and z (default: 1.2 up, on the front end)
	boxes: { Box }, -- relative to the chassis top centre (offset = centre of the box)
	cargo: CargoSpec, -- relative to the chassis top centre
}

local function box(size: Vector3, offset: Vector3, kind: string): Box
	return { size = size, offset = offset, kind = kind }
end

local function cargo(noun: string, length: number, width: number, slots: { Vector3 }, entry: Vector3?): CargoSpec
	return {
		slots = slots,
		noun = noun,
		door = Vector3.new(0, 2.4, length / 2 + 0.6),
		entry = entry or Vector3.new(width / 2 + 1.5, 0, 0),
	}
end

-- The slatted stall box of the livestock truck: posts and boards on both sides, the horses show between them.
local function stallBoxes(): { Box }
	local list = {
		box(Vector3.new(7.6, 2.4, 2.6), Vector3.new(0, 1.2, -8.7), "body"), -- hood
		box(Vector3.new(7.6, 4.6, 3.6), Vector3.new(0, 2.3, -5.6), "glass"), -- cab
		box(Vector3.new(7.6, 0.8, 3.6), Vector3.new(0, 5, -5.6), "body"),
		box(Vector3.new(7.8, 0.8, 0.6), Vector3.new(0, 0.4, -10.1), "dark"), -- bumper
		box(Vector3.new(7.6, 0.4, 13.6), Vector3.new(0, 0.2, 3), "dark"), -- stall floor
		box(Vector3.new(7.6, 7.6, 0.5), Vector3.new(0, 3.8, -3.65), "body"), -- front wall
		box(Vector3.new(0.25, 3.2, 12.4), Vector3.new(0, 2, 3.2), "rail"), -- divider between the two stalls
		box(Vector3.new(7.2, 6.6, 0.35), Vector3.new(0, 3.5, 9.8), "wood"), -- the ramp, folded up
		box(Vector3.new(7.6, 0.4, 0.5), Vector3.new(0, 7.6, 9.8), "dark"),
	}
	for _, x in { -3.65, 3.65 } do
		for _, y in { 1.3, 3.1, 4.9, 6.7 } do
			table.insert(list, box(Vector3.new(0.3, 0.8, 13.4), Vector3.new(x, y, 3), "wood"))
		end
		for _, z in { -3.5, 0.6, 3.6, 6.6, 9.6 } do
			table.insert(list, box(Vector3.new(0.45, 7.8, 0.45), Vector3.new(x, 3.9, z), "dark"))
		end
		table.insert(list, box(Vector3.new(0.5, 0.4, 13.6), Vector3.new(x, 7.9, 3), "body"))
	end
	return list
end

-- The fuel truck: a cab, a flatbed with stake sides and a headboard, the barrels stand in a rack.
local function flatbedBoxes(): { Box }
	local list = {
		box(Vector3.new(7.2, 2.2, 5.2), Vector3.new(0, 1.1, -5.4), "body"), -- hood
		box(Vector3.new(7.2, 4.4, 3.6), Vector3.new(0, 2.2, -1), "glass"), -- cab
		box(Vector3.new(7.2, 0.8, 3.6), Vector3.new(0, 4.8, -1), "body"),
		box(Vector3.new(7.4, 0.8, 0.6), Vector3.new(0, 0.4, -8.1), "dark"), -- bumper
		box(Vector3.new(7.2, 0.5, 7.2), Vector3.new(0, 0.25, 4.4), "plate"), -- the flatbed
		box(Vector3.new(7.2, 3.4, 0.3), Vector3.new(0, 2.2, 1), "rail"), -- headboard
		box(Vector3.new(7.2, 0.3, 0.3), Vector3.new(0, 1.9, 4.2), "rail"), -- the rack between the rows
		box(Vector3.new(7.2, 0.5, 0.3), Vector3.new(0, 0.8, 7.9), "accent"), -- tail rail
		box(Vector3.new(0.3, 2.4, 1.4), Vector3.new(-3.5, 1.4, -1.6), "white"), -- hazard plates on the doors
		box(Vector3.new(0.3, 2.4, 1.4), Vector3.new(3.5, 1.4, -1.6), "white"),
	}
	for _, x in { -3.45, 3.45 } do
		table.insert(list, box(Vector3.new(0.3, 0.4, 7), Vector3.new(x, 2.3, 4.4), "accent")) -- stake rails
		table.insert(list, box(Vector3.new(0.3, 0.4, 7), Vector3.new(x, 1.3, 4.4), "accent"))
		for _, z in { 1.2, 4.4, 7.7 } do
			table.insert(list, box(Vector3.new(0.4, 2.4, 0.4), Vector3.new(x, 1.5, z), "rail"))
		end
	end
	return list
end

-- The ambulance: a white box van with red stripes and crosses, the light bar on the cab roof, the rear doors where
-- the patient gets in (the cargo entry is behind the car).
local function ambulanceBoxes(): { Box }
	local list = {
		box(Vector3.new(7, 2.2, 2.6), Vector3.new(0, 1.1, -6.2), "body"), -- hood
		box(Vector3.new(7.06, 0.6, 2.6), Vector3.new(0, 1.3, -6.2), "accent"), -- the stripe goes round the nose
		box(Vector3.new(7, 4.4, 3.6), Vector3.new(0, 2.2, -3.2), "glass"), -- cab
		box(Vector3.new(7, 0.6, 3.6), Vector3.new(0, 4.7, -3.2), "body"), -- cab roof
		box(Vector3.new(7.4, 6.4, 8.6), Vector3.new(0, 3.2, 3.2), "body"), -- the patient box
		box(Vector3.new(7.5, 0.9, 8.6), Vector3.new(0, 1.9, 3.2), "accent"), -- red stripe
		box(Vector3.new(7.5, 0.3, 8.6), Vector3.new(0, 5.6, 3.2), "accent"), -- thin stripe up top
		box(Vector3.new(7.2, 0.8, 0.6), Vector3.new(0, 0.4, -7.6), "dark"), -- bumper
		box(Vector3.new(7.6, 0.3, 0.5), Vector3.new(0, 0.15, 7.6), "dark"), -- rear step
		box(Vector3.new(0.15, 5.4, 0.12), Vector3.new(0, 3.2, 7.56), "dark"), -- the rear doors' seam
		box(Vector3.new(2.4, 1.6, 0.1), Vector3.new(-1.5, 4.4, 7.55), "glass"), -- rear windows
		box(Vector3.new(2.4, 1.6, 0.1), Vector3.new(1.5, 4.4, 7.55), "glass"),
		box(Vector3.new(5.8, 0.4, 1.3), Vector3.new(0, 5.2, -3.4), "lightbar"), -- the light bar on the cab roof
		box(Vector3.new(2.5, 0.6, 1.1), Vector3.new(-1.45, 5.7, -3.4), "sirenred"),
		box(Vector3.new(2.5, 0.6, 1.1), Vector3.new(1.45, 5.7, -3.4), "sirenblue"),
		box(Vector3.new(0.8, 0.5, 0.8), Vector3.new(-3.1, 6.65, 7.1), "sirenred"), -- corner lights at the back
		box(Vector3.new(0.8, 0.5, 0.8), Vector3.new(3.1, 6.65, 7.1), "sirenblue"),
	}
	-- A red cross on both sides and on the back.
	for _, x in { -3.76, 3.76 } do
		table.insert(list, box(Vector3.new(0.1, 2.4, 0.8), Vector3.new(x, 4.1, 3.6), "cross"))
		table.insert(list, box(Vector3.new(0.1, 0.8, 2.4), Vector3.new(x, 4.1, 3.6), "cross"))
	end
	table.insert(list, box(Vector3.new(1.4, 0.45, 0.1), Vector3.new(1.5, 2.8, 7.56), "cross"))
	table.insert(list, box(Vector3.new(0.45, 1.4, 0.1), Vector3.new(1.5, 2.8, 7.56), "cross"))
	return list
end

-- Front of the car is -Z (the LookVector).
local STYLES: { [string]: Style } = {
	van = {
		width = 6.6,
		length = 13,
		wheel = 1.3,
		wheelWidth = 1,
		clearance = 0.9,
		seat = Vector3.new(-1.4, 0.5, -2.6),
		passengers = { Vector3.new(1.4, 0.5, -2.6) },
		roof = 5.4,
		boxes = {
			box(Vector3.new(6.6, 2, 2.6), Vector3.new(0, 1, -5.2), "body"), -- hood
			box(Vector3.new(6.6, 4.4, 4), Vector3.new(0, 2.2, -2), "glass"), -- cabin
			box(Vector3.new(6.6, 0.6, 4), Vector3.new(0, 4.7, -2), "body"), -- cabin roof
			box(Vector3.new(6.6, 5, 6.4), Vector3.new(0, 2.5, 3.2), "body"), -- cargo box
			box(Vector3.new(6.8, 0.8, 0.6), Vector3.new(0, 0.4, -6.6), "dark"), -- bumper
		},
		cargo = cargo("van", 13, 6.6, { Vector3.new(-1.5, 0, 1.6), Vector3.new(1.5, 0, 1.6), Vector3.new(-1.5, 0, 4.6), Vector3.new(1.5, 0, 4.6) }),
	},
	pickup = {
		width = 6.4,
		length = 13,
		wheel = 1.4,
		wheelWidth = 1.1,
		clearance = 1.0,
		seat = Vector3.new(-1.3, 0.5, -1.4),
		passengers = { Vector3.new(1.3, 0.5, -1.4), Vector3.new(-1.5, 0.4, 2.8), Vector3.new(1.5, 0.4, 2.8) },
		roof = 4.8,
		boxes = {
			box(Vector3.new(6.4, 1.8, 3.6), Vector3.new(0, 0.9, -4.7), "body"),
			box(Vector3.new(6.4, 4, 4), Vector3.new(0, 2, -0.9), "glass"),
			box(Vector3.new(6.4, 0.6, 4), Vector3.new(0, 4.3, -0.9), "body"),
			box(Vector3.new(0.4, 1.6, 5.4), Vector3.new(-3, 0.8, 3.8), "body"), -- bed walls
			box(Vector3.new(0.4, 1.6, 5.4), Vector3.new(3, 0.8, 3.8), "body"),
			box(Vector3.new(6.4, 1.6, 0.4), Vector3.new(0, 0.8, 6.3), "body"),
			box(Vector3.new(6.8, 0.9, 0.7), Vector3.new(0, 0.3, -6.7), "dark"),
		},
		cargo = cargo("pickup", 13, 6.4, { Vector3.new(-1.4, 0, 5.1), Vector3.new(1.4, 0, 5.1), Vector3.new(0, 0, 3.6), Vector3.new(0, 2.1, 5.1) }),
	},
	muscle = {
		width = 6.4,
		length = 13.5,
		wheel = 1.25,
		wheelWidth = 1.2,
		clearance = 0.8,
		seat = Vector3.new(-1.3, 0.2, 0.4),
		passengers = { Vector3.new(1.3, 0.2, 0.4) },
		roof = 3.6,
		boxes = {
			box(Vector3.new(6.4, 1.4, 13.5), Vector3.new(0, 0.7, 0), "body"),
			box(Vector3.new(5.6, 2.2, 5), Vector3.new(0, 2.5, 0.6), "glass"),
			box(Vector3.new(5.6, 0.4, 4), Vector3.new(0, 3.4, 0.8), "body"),
			box(Vector3.new(6.4, 0.3, 1.4), Vector3.new(0, 2.6, 6.2), "dark"), -- spoiler
			box(Vector3.new(0.4, 1.2, 0.4), Vector3.new(-2.6, 2, 6.2), "dark"),
			box(Vector3.new(0.4, 1.2, 0.4), Vector3.new(2.6, 2, 6.2), "dark"),
			box(Vector3.new(1.6, 0.05, 13.5), Vector3.new(0.9, 1.42, 0), "accent"), -- stripes
			box(Vector3.new(1.6, 0.05, 13.5), Vector3.new(-0.9, 1.42, 0), "accent"),
		},
		cargo = cargo("car", 13.5, 6.4, { Vector3.new(-1.2, 0.3, 5), Vector3.new(1.2, 0.3, 5) }),
	},
	icecream = {
		width = 6.8,
		length = 14,
		wheel = 1.35,
		wheelWidth = 1.1,
		clearance = 0.9,
		seat = Vector3.new(-1.4, 0.5, -2.4),
		passengers = { Vector3.new(1.4, 0.5, -2.4) },
		roof = 5.8,
		boxes = {
			box(Vector3.new(6.8, 2, 2.6), Vector3.new(0, 1, -5.7), "body"),
			box(Vector3.new(6.8, 4.4, 4), Vector3.new(0, 2.2, -2.4), "glass"),
			box(Vector3.new(6.8, 0.6, 4), Vector3.new(0, 4.7, -2.4), "body"),
			box(Vector3.new(6.8, 5.6, 7.4), Vector3.new(0, 2.8, 3.3), "body"),
			box(Vector3.new(6.9, 0.8, 7.4), Vector3.new(0, 1.2, 3.3), "accent"), -- pink stripe
			box(Vector3.new(0.2, 2.2, 4), Vector3.new(3.45, 3.4, 3.3), "dark"), -- serving window
			box(Vector3.new(1.4, 2.4, 1.4), Vector3.new(0, 6.6, 4.6), "white"), -- the cone
			box(Vector3.new(2.6, 2.6, 2.6), Vector3.new(0, 8.4, 4.6), "ball"), -- the scoop
			box(Vector3.new(7, 0.8, 0.6), Vector3.new(0, 0.4, -7.1), "dark"),
		},
		cargo = cargo("truck", 14, 6.8, { Vector3.new(-1.6, 0, 1.4), Vector3.new(1.6, 0, 1.4), Vector3.new(-1.6, 0, 4.6), Vector3.new(1.6, 0, 4.6) }),
	},
	armored = {
		width = 7.4,
		length = 15,
		wheel = 1.6,
		wheelWidth = 1.3,
		clearance = 1.1,
		seat = Vector3.new(-1.6, 0.5, -3.6),
		passengers = { Vector3.new(1.6, 0.5, -3.6), Vector3.new(-2, 6.2, 5), Vector3.new(2, 6.2, 5) },
		roof = 6.4,
		head = Vector2.new(1.5, -8.35), -- on the ram plate
		boxes = {
			box(Vector3.new(7.4, 2.4, 3), Vector3.new(0, 1.2, -6), "body"),
			box(Vector3.new(7.4, 4.6, 4), Vector3.new(0, 2.3, -2.6), "glass"),
			box(Vector3.new(7.4, 0.8, 4), Vector3.new(0, 5, -2.6), "body"),
			box(Vector3.new(7.4, 6, 7), Vector3.new(0, 3, 3.6), "body"),
			box(Vector3.new(7.8, 1, 7.4), Vector3.new(0, 1.6, 3.6), "plate"),
			box(Vector3.new(7.8, 1, 7.4), Vector3.new(0, 4.4, 3.6), "plate"),
			box(Vector3.new(8, 2.4, 1), Vector3.new(0, 0.9, -7.8), "plate"), -- ram plate
			box(Vector3.new(7.6, 1.2, 0.4), Vector3.new(0, 6.6, 7), "plate"), -- roof rail for the gunners
		},
		cargo = cargo("truck", 15, 7.4, { Vector3.new(-1.8, 0, 2), Vector3.new(1.8, 0, 2), Vector3.new(-1.8, 0, 5.2), Vector3.new(1.8, 0, 5.2) }),
	},
	bus = {
		width = 8,
		length = 24,
		wheel = 1.6,
		wheelWidth = 1.2,
		clearance = 1.0,
		seat = Vector3.new(-2.4, 0.5, -9.4),
		passengers = {
			Vector3.new(2.4, 0.5, -6),
			Vector3.new(-2.4, 0.5, -2),
			Vector3.new(2.4, 0.5, -2),
			Vector3.new(-2.4, 0.5, 3),
			Vector3.new(2.4, 0.5, 3),
		},
		roof = 7,
		boxes = {
			box(Vector3.new(8, 3, 24), Vector3.new(0, 1.5, 0), "body"),
			box(Vector3.new(8, 3, 23), Vector3.new(0, 4.5, 0.5), "glass"),
			box(Vector3.new(8.2, 0.8, 24.2), Vector3.new(0, 6.4, 0), "body"),
			box(Vector3.new(8.1, 0.4, 24.1), Vector3.new(0, 2.6, 0), "dark"), -- black stripe
			box(Vector3.new(8.4, 0.8, 0.6), Vector3.new(0, 0.4, -12.2), "dark"),
			box(Vector3.new(0.2, 1.6, 1.6), Vector3.new(-4.2, 3.6, -8.6), "accent"), -- stop sign
		},
		cargo = cargo("bus", 24, 8, {
			-- the kids sit at the windows
			Vector3.new(-2.6, 2.2, -4.2),
			Vector3.new(2.6, 2.2, -4.2),
			Vector3.new(-2.6, 2.2, 0.5),
			Vector3.new(2.6, 2.2, 0.5),
			Vector3.new(-2.6, 2.2, 5.5),
			Vector3.new(2.6, 2.2, 5.5),
			Vector3.new(-2.6, 2.2, 8.5),
			Vector3.new(2.6, 2.2, 8.5),
		}, Vector3.new(5.5, 0, -9.6)),
	},
	movingtruck = {
		width = 7.4,
		length = 17,
		wheel = 1.6,
		wheelWidth = 1.3,
		clearance = 1.1,
		seat = Vector3.new(-1.6, 0.5, -4.8),
		passengers = { Vector3.new(1.6, 0.5, -4.8) },
		roof = 8.6,
		boxes = {
			box(Vector3.new(7.4, 2.4, 2.4), Vector3.new(0, 1.2, -7.3), "body"),
			box(Vector3.new(7.4, 4.6, 3.6), Vector3.new(0, 2.3, -4.6), "glass"),
			box(Vector3.new(7.4, 0.8, 3.6), Vector3.new(0, 5, -4.6), "body"),
			box(Vector3.new(7.6, 8, 10.6), Vector3.new(0, 4, 2.9), "body"), -- the box
			box(Vector3.new(7.7, 1.4, 9.6), Vector3.new(0, 5, 2.9), "logo"),
			box(Vector3.new(7.8, 0.8, 0.6), Vector3.new(0, 0.4, -8.6), "dark"),
		},
		cargo = cargo("truck", 17, 7.4, {
			Vector3.new(-1.8, 0, -0.6),
			Vector3.new(1.8, 0, -0.6),
			Vector3.new(-1.8, 0, 2.8),
			Vector3.new(1.8, 0, 2.8),
			Vector3.new(-1.8, 0, 6.2),
			Vector3.new(1.8, 0, 6.2),
		}),
	},
	monster = {
		width = 8,
		length = 14,
		wheel = 3,
		wheelWidth = 2.2,
		clearance = 2.6,
		seat = Vector3.new(-1.4, 0.5, -0.8),
		passengers = { Vector3.new(1.4, 0.5, -0.8), Vector3.new(-1.8, 2.0, 4), Vector3.new(1.8, 2.0, 4) },
		roof = 5,
		head = Vector2.new(1.2, -6.65), -- on the hood's face
		boxes = {
			box(Vector3.new(7, 2, 4), Vector3.new(0, 1, -4.6), "body"),
			box(Vector3.new(7, 4, 4), Vector3.new(0, 2, -0.6), "glass"),
			box(Vector3.new(7, 0.6, 4), Vector3.new(0, 4.3, -0.6), "body"),
			box(Vector3.new(7, 1.8, 5), Vector3.new(0, 0.9, 4), "body"),
			box(Vector3.new(8.4, 1.2, 1), Vector3.new(0, 0.2, -7.2), "plate"),
			box(Vector3.new(1, 1.4, 12), Vector3.new(-3.2, -0.6, 0), "accent"), -- frame rails
			box(Vector3.new(1, 1.4, 12), Vector3.new(3.2, -0.6, 0), "accent"),
		},
		cargo = cargo("truck", 14, 8, { Vector3.new(-2.2, 1.8, 5.6), Vector3.new(0, 1.8, 5.6), Vector3.new(2.2, 1.8, 5.6), Vector3.new(0, 3.8, 5.6) }),
	},
	livestock = {
		width = 7.6,
		length = 20,
		wheel = 1.6,
		wheelWidth = 1.3,
		clearance = 1.1,
		seat = Vector3.new(-1.6, 0.5, -5.8),
		passengers = { Vector3.new(1.6, 0.5, -5.8) },
		roof = 8.4,
		boxes = stallBoxes(),
		cargo = cargo("truck", 20, 7.6, { Vector3.new(-1.8, 0.4, 3.2), Vector3.new(1.8, 0.4, 3.2) }),
	},
	fueltruck = {
		width = 7.2,
		length = 16,
		wheel = 1.5,
		wheelWidth = 1.2,
		clearance = 1.0,
		seat = Vector3.new(-1.5, 0.5, -1),
		passengers = { Vector3.new(1.5, 0.5, -1) },
		roof = 5.2,
		boxes = flatbedBoxes(),
		cargo = cargo("truck", 16, 7.2, { Vector3.new(-1.7, 0.5, 2.6), Vector3.new(1.7, 0.5, 2.6), Vector3.new(-1.7, 0.5, 6), Vector3.new(1.7, 0.5, 6) }),
	},
	ambulance = {
		width = 7,
		length = 15,
		wheel = 1.4,
		wheelWidth = 1.1,
		clearance = 1.0,
		seat = Vector3.new(-1.5, 0.5, -3.2),
		passengers = { Vector3.new(1.5, 0.5, -3.2) },
		roof = 6.4,
		boxes = ambulanceBoxes(),
		-- The patient lies on the stretcher in the back; they get in through the rear doors.
		cargo = cargo("ambulance", 15, 7, { Vector3.new(0, 0.6, 3.6) }, Vector3.new(0, 0, 15 / 2 + 2.5)),
	},
}

local CHASSIS_HEIGHT = 1.2
local FRICTIONLESS = PhysicalProperties.new(0.7, 0, 0, 100, 1)

-- The lights' colours: lit at night (Neon), dim by day.
local HEAD_LIT, HEAD_DIM = Color3.fromRGB(255, 246, 214), Color3.fromRGB(196, 202, 206)
local TAIL_LIT, TAIL_DIM = Color3.fromRGB(255, 36, 30), Color3.fromRGB(116, 22, 22)
Vehicles.SirenTag = "SirenLight" -- the ambulance's light bar (client/Weather.luau flashes it)
local SIREN_DIM: { [string]: Color3 } = {
	sirenred = Color3.fromRGB(120, 34, 34),
	sirenblue = Color3.fromRGB(34, 44, 120),
}

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Car"
	p.Parent = model
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The colour of a car: its paint job, or the factory colour.
local function paintColor(def: Config.CarDef, paintId: string?): Color3
	local paint = paintId and Economy.findPaint(paintId)
	if paint and paint.color then
		return rgb(paint.color)
	end
	return rgb(def.color)
end

type Built = {
	model: Model,
	chassis: Part,
	seat: VehicleSeat?,
	passengers: { Seat },
	turret: Weld?,
	turretBase: CFrame,
	muzzle: Attachment?,
	paintParts: { BasePart },
	size: Vector3,
}

-- ── The roof guns ──────────────────────────────────────────────────────────
-- Every car gun's look, in "mount space": the centre of the turret's ring at the roof, -Z forward, Y up. The ring
-- (a flat cylinder 1 stud high) turns; every piece is welded to it. The "Barrel" piece holds the muzzle.

local GUNMETAL = Color3.fromRGB(60, 60, 64)
local OLIVE = Color3.fromRGB(78, 92, 56)
local BRASS = Color3.fromRGB(196, 156, 64)
local METAL = Enum.Material.Metal

type GunPiece = {
	name: string,
	size: Vector3, -- a cylinder's length is X
	at: CFrame, -- in mount space
	color: Color3,
	material: Enum.Material?,
	cylinder: boolean?,
}
type GunLook = { pieces: { GunPiece }, muzzle: Vector3 }

local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's axis (X) to lie along the barrel (Z)

local function gunLook(gunId: string): GunLook
	local pieces: { GunPiece } = {}
	local function add(name: string, size: Vector3, at: CFrame, color: Color3, cylinder: boolean?, material: Enum.Material?)
		table.insert(pieces, { name = name, size = size, at = at, color = color, cylinder = cylinder, material = material })
	end
	if gunId == "roofminigun" then
		-- A rotary cluster: six barrels around a spindle, two clamps, the motor behind, an ammo drum on the side.
		local y = 1
		add("Housing", Vector3.new(0.95, 0.95, 1.3), CFrame.new(0, y, 0.45), DARK)
		add("Barrel", Vector3.new(0.25, 0.25, 3.2), CFrame.new(0, y, -1.4), DARK)
		for n = 0, 5 do
			local angle = n * math.pi / 3
			add("RotaryBarrel", Vector3.new(3, 0.2, 0.2), CFrame.new(math.cos(angle) * 0.3, y + math.sin(angle) * 0.3, -1.5) * ALONG_Z, GUNMETAL, true)
		end
		add("Clamp", Vector3.new(0.2, 0.95, 0.95), CFrame.new(0, y, -2.75) * ALONG_Z, DARK, true)
		add("Clamp", Vector3.new(0.2, 0.95, 0.95), CFrame.new(0, y, -0.9) * ALONG_Z, DARK, true)
		add("AmmoDrum", Vector3.new(0.7, 1.3, 1.3), CFrame.new(1, 0.95, 0.45), OLIVE, true)
		add("Feed", Vector3.new(0.5, 0.18, 0.35), CFrame.new(0.55, y + 0.15, 0.45), BRASS)
		return { pieces = pieces, muzzle = Vector3.new(0, y, -3.1) }
	elseif gunId == "rooflauncher" then
		-- One fat tube with rings, the breech behind it and a sight.
		local y = 1.15
		add("Barrel", Vector3.new(3.4, 1.2, 1.2), CFrame.new(0, y, -1.1) * ALONG_Z, OLIVE, true)
		add("Ring", Vector3.new(0.3, 1.4, 1.4), CFrame.new(0, y, -2.7) * ALONG_Z, DARK, true)
		add("Ring", Vector3.new(0.3, 1.4, 1.4), CFrame.new(0, y, 0.4) * ALONG_Z, DARK, true)
		add("Breech", Vector3.new(1, 1, 0.8), CFrame.new(0, y, 0.95), DARK)
		add("Sight", Vector3.new(0.15, 0.5, 0.3), CFrame.new(0.55, y + 0.75, -0.6), GUNMETAL)
		return { pieces = pieces, muzzle = Vector3.new(0, y, -2.9) }
	end
	-- roofmg (and the bandits' pickup): a slim barrel in a cooling jacket on a receiver, an ammo box on the side.
	local y = 0.9
	add("Receiver", Vector3.new(0.7, 0.6, 1.6), CFrame.new(0, y, 0.1), DARK)
	add("Barrel", Vector3.new(0.28, 0.28, 3), CFrame.new(0, y, -2.2), GUNMETAL)
	add("Jacket", Vector3.new(1.4, 0.45, 0.45), CFrame.new(0, y, -1.3) * ALONG_Z, DARK, true)
	add("AmmoBox", Vector3.new(0.8, 0.75, 1), CFrame.new(0.8, 0.8, 0.2), OLIVE)
	add("Belt", Vector3.new(0.45, 0.12, 0.35), CFrame.new(0.38, y + 0.2, 0), BRASS)
	add("Handles", Vector3.new(0.9, 0.15, 0.15), CFrame.new(0, y, 1), GUNMETAL)
	return { pieces = pieces, muzzle = Vector3.new(0, y, -3.8) }
end

-- Builds a roof gun on the car: the model "CarGun" with the ring on a Weld (the server turns its C0, Vehicles.aim)
-- and the gun's pieces welded to the ring. Returns the joint and the muzzle.
local function buildTurret(model: Model, chassis: BasePart, turretBase: CFrame, gunId: string): (Weld, Attachment)
	local holder = Instance.new("Model")
	holder.Name = "CarGun"
	holder:SetAttribute("Gun", gunId)
	holder.Parent = model
	local mount = chassis.CFrame * turretBase
	local base = newPart(holder, "Turret", Vector3.new(1, 2.2, 2.2), mount * CFrame.Angles(0, 0, math.rad(90)), DARK, METAL)
	base.Shape = Enum.PartType.Cylinder
	base.CanCollide = false
	base.Massless = true
	local turret = Instance.new("Weld")
	turret.Name = "TurretWeld"
	turret.Part0 = chassis
	turret.Part1 = base
	turret.C0 = turretBase
	turret.C1 = CFrame.Angles(0, 0, math.rad(90)):Inverse()
	turret.Parent = base
	local look = gunLook(gunId)
	local barrel: BasePart = base
	for _, piece in look.pieces do
		local p = newPart(holder, piece.name, piece.size, mount * piece.at, piece.color, piece.material or METAL)
		if piece.cylinder then
			p.Shape = Enum.PartType.Cylinder
		end
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		weld(base, p)
		if piece.name == "Barrel" then
			barrel = p
		end
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = barrel
	muzzle.WorldCFrame = mount * CFrame.new(look.muzzle)
	return turret, muzzle
end

-- Builds the body. display = a showroom model (anchored, no seats, no movers). gunId = the car gun on its roof (nil:
-- none). oneBeam: only one headlight carries a SpotLight (the NPC cars: cheaper).
local function build(def: Config.CarDef, color: Color3, ground: CFrame, display: boolean, gunId: string?, oneBeam: boolean?): Built
	local style = STYLES[def.style] or STYLES.van
	local accent = if def.style == "icecream"
		then Color3.fromRGB(255, 120, 180)
		elseif def.style == "bus" or def.style == "ambulance" then Color3.fromRGB(205, 30, 34)
		else color:Lerp(Color3.new(1, 1, 1), 0.45)

	local model = Instance.new("Model")
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local chassisY = style.clearance + CHASSIS_HEIGHT / 2
	local chassisCF = ground * CFrame.new(0, chassisY, 0)
	local chassis = newPart(model, "Chassis", Vector3.new(style.width - 0.4, CHASSIS_HEIGHT, style.length), chassisCF, DARK, Enum.Material.Metal)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2, 0, 0, 100, 1)
	model.PrimaryPart = chassis

	local paintParts: { BasePart } = {}
	local top = chassisCF * CFrame.new(0, CHASSIS_HEIGHT / 2, 0)
	local height = CHASSIS_HEIGHT
	for _, b in style.boxes do
		local c, material = color, Enum.Material.SmoothPlastic
		if b.kind == "dark" then
			c, material = DARK, Enum.Material.Metal
		elseif b.kind == "glass" then
			c, material = GLASS, Enum.Material.Glass
		elseif b.kind == "accent" then
			c = accent
		elseif b.kind == "plate" then
			c, material = color:Lerp(DARK, 0.5), Enum.Material.DiamondPlate
		elseif b.kind == "white" then
			c = Color3.fromRGB(220, 180, 120)
		elseif b.kind == "ball" then
			c = Color3.fromRGB(255, 150, 200)
		elseif b.kind == "logo" then
			c = Color3.fromRGB(240, 240, 240)
		elseif b.kind == "wood" then
			c, material = Color3.fromRGB(128, 92, 58), Enum.Material.WoodPlanks
		elseif b.kind == "rail" then
			c, material = Color3.fromRGB(70, 72, 76), Enum.Material.Metal
		elseif b.kind == "cross" then
			c = Color3.fromRGB(205, 30, 34)
		elseif b.kind == "lightbar" then
			c, material = DARK, Enum.Material.Metal
		elseif SIREN_DIM[b.kind] then
			c = SIREN_DIM[b.kind]
		end
		local name = if b.kind == "glass" then "Cabin" elseif b.kind == "lightbar" then "LightBar" elseif SIREN_DIM[b.kind] then "SirenLens" else "Body"
		local p = newPart(model, name, b.size, top * CFrame.new(b.offset), c, material)
		p.Massless = true
		p.CustomPhysicalProperties = FRICTIONLESS
		if b.kind == "glass" then
			p.Transparency = 0.45
		elseif b.kind == "ball" then
			p.Shape = Enum.PartType.Ball
		end
		if b.kind == "body" then
			table.insert(paintParts, p)
		elseif SIREN_DIM[b.kind] or b.kind == "lightbar" then
			-- The light bar: the lenses flash red / blue, the bar holds the light that throws the colour around.
			p.CanCollide = false
			local lens: { [string]: string } = { sirenred = "red", sirenblue = "blue" }
			p:SetAttribute("Lens", lens[b.kind] or "bar")
			if b.kind == "lightbar" and not display then
				local glow = Instance.new("PointLight")
				glow.Name = "SirenGlow"
				glow.Range = 24
				glow.Brightness = 3
				glow.Shadows = false
				glow.Enabled = false
				glow.Parent = p
			end
			CollectionService:AddTag(p, Vehicles.SirenTag)
		end
		weld(chassis, p)
		height = math.max(height, CHASSIS_HEIGHT + b.offset.Y + b.size.Y / 2)
	end

	-- Wheels: an invisible welded frictionless collider (the car slides on it) and a visible tyre on a Motor6D.
	local wheelY = style.wheel - chassisY
	local wx = style.width / 2 - style.wheelWidth / 2 + 0.3
	local wz = style.length / 2 - style.wheel - 0.5
	for _, offset in { Vector3.new(-wx, wheelY, -wz), Vector3.new(wx, wheelY, -wz), Vector3.new(-wx, wheelY, wz), Vector3.new(wx, wheelY, wz) } do
		local collider = newPart(model, "WheelCollider", Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2), chassisCF * CFrame.new(offset), DARK, Enum.Material.Rubber)
		collider.Shape = Enum.PartType.Cylinder
		collider.Transparency = 1
		collider.CustomPhysicalProperties = FRICTIONLESS
		weld(chassis, collider)
		local tyre = newPart(model, "Tyre", Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2), chassisCF * CFrame.new(offset), Color3.fromRGB(24, 24, 24), Enum.Material.Rubber)
		tyre.Shape = Enum.PartType.Cylinder
		tyre.CanCollide = false
		tyre.CanQuery = false
		tyre.Massless = true
		local motor = Instance.new("Motor6D")
		motor.Name = "WheelMotor"
		motor.Part0 = chassis
		motor.Part1 = tyre
		motor.C0 = CFrame.new(offset)
		motor:SetAttribute("Front", offset.Z < 0)
		motor:SetAttribute("Radius", style.wheel)
		motor.Parent = chassis
		local hub = newPart(model, "Hub", Vector3.new(style.wheelWidth + 0.1, style.wheel, style.wheel), tyre.CFrame, Color3.fromRGB(170, 170, 170), Enum.Material.Metal)
		hub.Shape = Enum.PartType.Cylinder
		hub.CanCollide = false
		hub.CanQuery = false
		hub.Massless = true
		weld(tyre, hub)
		-- A spoke, so the spin shows.
		local spoke = newPart(model, "Spoke", Vector3.new(style.wheelWidth + 0.15, style.wheel * 1.6, 0.35), tyre.CFrame, Color3.fromRGB(90, 90, 90), Enum.Material.Metal)
		spoke.CanCollide = false
		spoke.CanQuery = false
		spoke.Massless = true
		weld(tyre, spoke)
	end

	-- Lights: they glow at night (DayNight switches them); the headlights throw a beam.
	local front = -style.length / 2
	local headY = if style.head then style.head.X else 1.2
	local headZ = if style.head then style.head.Y else front - 0.05
	for n, x in { -style.width / 2 + 1, style.width / 2 - 1 } do
		local head = newPart(model, "Headlight", Vector3.new(1.2, 0.6, 0.2), top * CFrame.new(x, headY, headZ), HEAD_DIM, Enum.Material.Glass)
		head.CanCollide = false
		head.CanQuery = false
		head.Massless = true
		weld(chassis, head)
		if not display and (n == 1 or not oneBeam) then
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = if oneBeam then 50 else 60
			spot.Angle = if oneBeam then 70 else 55
			spot.Brightness = if oneBeam then 3.4 else 4
			spot.Color = Color3.fromRGB(255, 240, 210)
			spot.Shadows = false
			spot.Parent = head
		end
		DayNight.nightLight(head, HEAD_LIT, HEAD_DIM, "Glass")
		local tail = newPart(model, "Taillight", Vector3.new(1, 0.5, 0.2), top * CFrame.new(x, 0.6, -front + 0.05), TAIL_DIM, Enum.Material.SmoothPlastic)
		tail.CanCollide = false
		tail.CanQuery = false
		tail.Massless = true
		weld(chassis, tail)
		DayNight.nightLight(tail, TAIL_LIT, TAIL_DIM, "SmoothPlastic")
	end

	-- The roof gun, only when one is installed.
	local turretBase = CFrame.new(0, CHASSIS_HEIGHT / 2 + style.roof, 0.5)
	local turret: Weld?, muzzle: Attachment? = nil, nil
	if gunId then
		turret, muzzle = buildTurret(model, chassis, turretBase, gunId)
	end

	local built: Built = {
		model = model,
		chassis = chassis,
		seat = nil,
		passengers = {},
		turret = turret,
		turretBase = turretBase,
		muzzle = muzzle,
		paintParts = paintParts,
		size = Vector3.new(style.width, height, style.length),
	}

	if display then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CollisionGroup = "Default"
			end
		end
		return built
	end

	-- The driver's seat (only the owner may sit in it, see watchSeats) and the passenger seats.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = top * CFrame.new(style.seat)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.MaxSpeed = 0 -- the legacy motor is unused, client/Drive.luau drives the car
	seat.HeadsUpDisplay = false
	seat.CollisionGroup = "Car"
	seat.Parent = model
	weld(chassis, seat)
	built.seat = seat
	for n, position in style.passengers do
		local p = Instance.new("Seat")
		p.Name = "PassengerSeat"
		p.Size = Vector3.new(2, 0.4, 2)
		p.CFrame = top * CFrame.new(position)
		p.Transparency = 1
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.CollisionGroup = "Car"
		p:SetAttribute("Index", n)
		p.Parent = model
		weld(chassis, p)
		table.insert(built.passengers, p)
	end

	-- The movers (their values are set by the owner's client).
	local root = Instance.new("Attachment")
	root.Name = "Root"
	root.Parent = chassis
	local linear = Instance.new("LinearVelocity")
	linear.Name = "Drive"
	linear.Attachment0 = root
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linear.PrimaryTangentAxis = Vector3.xAxis
	linear.SecondaryTangentAxis = Vector3.zAxis
	linear.PlaneVelocity = Vector2.zero
	linear.Parent = chassis
	local angular = Instance.new("AngularVelocity")
	angular.Name = "Steer"
	angular.Attachment0 = root
	angular.RelativeTo = Enum.ActuatorRelativeTo.World
	angular.AngularVelocity = Vector3.zero
	angular.Parent = chassis

	-- The cargo: the back door (server/Cargo.luau puts the Load / Take out prompt there) and the passengers' door.
	local door = Instance.new("Attachment")
	door.Name = "CargoDoor"
	door.Position = Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + style.cargo.door
	door.Parent = chassis
	local entry = Instance.new("Attachment")
	entry.Name = "CargoEntry"
	entry.Position = Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + style.cargo.entry
	entry.Parent = chassis
	model:SetAttribute("CargoCount", 0)

	-- Prompts: the owner drives, everybody else rides (the clients show only the one that fits them).
	type PromptInfo = { name: string, action: string, key: Enum.KeyCode }
	local promptInfos: { PromptInfo } = {
		{ name = "DrivePrompt", action = "Drive", key = Enum.KeyCode.E },
		{ name = "RidePrompt", action = "Ride along", key = Enum.KeyCode.R },
	}
	for _, info in promptInfos do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = info.name
		prompt.ActionText = info.action
		prompt.ObjectText = def.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = info.key
		prompt.Parent = chassis
	end
	return built
end

-- A showroom model for the dealer (anchored, no seats).
function Vehicles.displayModel(def: Config.CarDef, ground: CFrame): Model
	local built = build(def, rgb(def.color), ground, true)
	return built.model
end

export type NpcCar = {
	model: Model,
	chassis: Part,
	turret: Weld, -- the bandits' pickup always has a roof machine gun
	turretBase: CFrame,
	size: Vector3,
	linear: LinearVelocity,
	angular: AngularVelocity,
	guns: { BasePart }, -- the gunners' guns (where the shots come from)
}

-- A bandit figure sitting where a seat was: a body, a head with a bandana, and a gun for the gunners.
local function dummy(model: Model, chassis: Part, seat: CFrame, gunner: boolean): BasePart?
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = newPart(model, name, size, seat * offset, color, material)
		p.CanCollide = false
		p.Massless = true
		weld(chassis, p)
		return p
	end
	piece("BanditBody", Vector3.new(2, 2, 1), CFrame.new(0, 1.4, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
	piece("BanditHead", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 3, 0), Color3.fromRGB(205, 160, 120), Enum.Material.SmoothPlastic)
	piece("Bandana", Vector3.new(1.25, 0.5, 1.25), CFrame.new(0, 2.75, 0), Color3.fromRGB(170, 30, 30), Enum.Material.Fabric)
	if not gunner then
		return nil
	end
	return piece("BanditGun", Vector3.new(0.35, 0.5, 2.8), CFrame.new(0.9, 2.1, -1.2), Color3.fromRGB(25, 25, 28), Enum.Material.Metal)
end

-- A car for the enemies, driven by the server (server/BanditCars.luau): no seats, no prompts, bandit figures inside.
function Vehicles.buildNpc(def: Config.CarDef, ground: CFrame): NpcCar
	local built = build(def, rgb(def.color), ground, false, "roofmg", true)
	local model = built.model
	local spots: { CFrame } = {}
	local seat = built.seat
	if seat then
		table.insert(spots, seat.CFrame)
		seat:Destroy()
	end
	for _, p in built.passengers do
		table.insert(spots, p.CFrame)
		p:Destroy()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	local guns: { BasePart } = {}
	for n, spot in spots do
		local gun = dummy(model, built.chassis, spot, n > 1)
		if gun then
			table.insert(guns, gun)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "EnemyCar"
		end
	end
	return {
		model = model,
		chassis = built.chassis,
		turret = built.turret :: Weld,
		turretBase = built.turretBase,
		size = built.size,
		linear = built.chassis:FindFirstChild("Drive") :: LinearVelocity,
		angular = built.chassis:FindFirstChild("Steer") :: AngularVelocity,
		guns = guns,
	}
end

export type TrafficCar = {
	model: Model,
	chassis: Part,
	size: Vector3,
	linear: LinearVelocity,
	angular: AngularVelocity,
}

-- A civilian at the wheel: a body and a head in the driver's seat.
local DRIVER_SHIRTS = { Color3.fromRGB(70, 110, 160), Color3.fromRGB(160, 60, 60), Color3.fromRGB(90, 130, 90), Color3.fromRGB(200, 180, 140), Color3.fromRGB(60, 60, 66) }
local DRIVER_SKINS = { Color3.fromRGB(255, 224, 196), Color3.fromRGB(214, 160, 120), Color3.fromRGB(132, 88, 60), Color3.fromRGB(241, 194, 160) }

-- A civilian car for the traffic (server/Traffic.luau): an ordinary style in `color` (default: its factory colour),
-- no gun, no seats, no prompts, a driver at the wheel, one headlight beam. It keeps its movers ("Drive", "Steer")
-- like an NPC car; anchor it to step it by CFrame. Its parts are in the "Car" collision group.
function Vehicles.buildTraffic(def: Config.CarDef, ground: CFrame, color: Color3?): TrafficCar
	local built = build(def, color or rgb(def.color), ground, false, nil, true)
	local model = built.model
	local seat = built.seat
	local rng = Random.new()
	if seat then
		local at = seat.CFrame
		local function piece(name: string, size: Vector3, offset: CFrame, c: Color3)
			local p = newPart(model, name, size, at * offset, c, Enum.Material.SmoothPlastic)
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			weld(built.chassis, p)
		end
		piece("DriverBody", Vector3.new(2, 2, 1), CFrame.new(0, 1.4, 0), DRIVER_SHIRTS[rng:NextInteger(1, #DRIVER_SHIRTS)])
		piece("DriverHead", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 3, 0), DRIVER_SKINS[rng:NextInteger(1, #DRIVER_SKINS)])
		seat:Destroy()
	end
	for _, p in built.passengers do
		p:Destroy()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("Attachment") and (d.Name == "CargoDoor" or d.Name == "CargoEntry") then
			d:Destroy()
		end
	end
	model:SetAttribute("Traffic", true)
	return {
		model = model,
		chassis = built.chassis,
		size = built.size,
		linear = built.chassis:FindFirstChild("Drive") :: LinearVelocity,
		angular = built.chassis:FindFirstChild("Steer") :: AngularVelocity,
	}
end

local function writeAttributes(car: Car)
	local model = car.model
	model:SetAttribute("MaxSpeed", car.stats.maxSpeed)
	model:SetAttribute("Accel", car.stats.accel)
	model:SetAttribute("Turn", car.stats.turn)
	model:SetAttribute("MaxHealth", car.stats.health)
	model:SetAttribute("Health", math.ceil(car.health))
end

-- What the character holds in its hands (server/Cargo.luau sets it), or nil.
local function carrying(character: Instance?): string?
	local value = character and character:GetAttribute("Carrying")
	return if type(value) == "string" then value else nil
end

-- Nobody gets into a seat with a crate in the hands (or a horse on the rope): load it first.
local function handsFull(player: Player): boolean
	local held = carrying(player.Character)
	if not held then
		return false
	end
	Net.get("Notice"):FireClient(player, if held == "horse" then "Load the horse first (E at the back of the truck)." else "Load it first (E at the back of the vehicle).")
	return true
end

local function eject(seat: Seat | VehicleSeat)
	local occupant = seat.Occupant
	local seatWeld = seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	if occupant then
		occupant.Sit = false
		occupant.Jump = true
	end
end

-- Whoever gets out steps out next to the car, not inside the cabin.
local function watchSeat(car: Car, seat: Seat | VehicleSeat, side: number, driver: boolean)
	local sitting: Humanoid? = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			if driver and occupant.Parent ~= car.owner.Character then
				eject(seat) -- somebody else's car
			elseif driver and handsFull(car.owner) then
				eject(seat)
			else
				sitting = occupant
			end
			return
		end
		local left = sitting
		sitting = nil
		local character = left and left.Parent
		if left and character and character:IsA("Model") and left.Health > 0 then
			task.defer(function()
				if character.Parent and car.chassis.Parent then
					character:PivotTo(car.chassis.CFrame * CFrame.new(side * (car.size.X / 2 + 3), 2, -1))
				end
			end)
		end
	end)
end

local function watchPrompts(car: Car)
	local drive = car.chassis:FindFirstChild("DrivePrompt") :: ProximityPrompt
	local ride = car.chassis:FindFirstChild("RidePrompt") :: ProximityPrompt
	local function humanoidOf(player: Player): Humanoid?
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return if humanoid and humanoid.Health > 0 then humanoid else nil
	end
	drive.Triggered:Connect(function(player)
		local humanoid = humanoidOf(player)
		if player == car.owner and not car.wrecked and not car.chauffeured and not car.seat.Occupant and humanoid and not handsFull(player) then
			car.seat:Sit(humanoid)
		end
	end)
	ride.Triggered:Connect(function(player)
		local humanoid = humanoidOf(player)
		if player == car.owner or car.wrecked or car.chauffeured or not humanoid or humanoid.SeatPart or handsFull(player) then
			return
		end
		for _, seat in car.passengers do
			if not seat.Occupant then
				seat:Sit(humanoid)
				return
			end
		end
	end)
end

function Vehicles.get(player: Player): Car?
	local car = cars[player]
	if car and not car.wrecked then
		return car
	end
	return nil
end

-- All live cars (for the zombies).
function Vehicles.all(): { Car }
	local list = {}
	for _, car in cars do
		if not car.wrecked then
			table.insert(list, car)
		end
	end
	return list
end

function Vehicles.isDriving(player: Player): boolean
	local car = Vehicles.get(player)
	local occupant = car and car.seat.Occupant
	return occupant ~= nil and player.Character ~= nil and occupant.Parent == player.Character
end

-- The car the player sits in (any seat) and whether they drive it.
function Vehicles.seatedIn(player: Player): (Car?, boolean, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seatPart = humanoid and humanoid.SeatPart
	if not seatPart then
		return nil, false, nil
	end
	for _, car in cars do
		if not car.wrecked and seatPart:IsDescendantOf(car.model) then
			return car, seatPart == car.seat, seatPart
		end
	end
	return nil, false, nil
end

-- The players riding in a car's passenger seats.
function Vehicles.passengersOf(car: Car): { Player }
	local list = {}
	for _, seat in car.passengers do
		local occupant = seat.Occupant
		local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if player then
			table.insert(list, player)
		end
	end
	return list
end

-- Speed along the ground (studs / s).
function Vehicles.speed(car: Car): number
	local v = car.chassis.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- ── Cargo (server/Cargo.luau) ───────────────────────────────────────────────

local function styleOf(car: Car): Style
	local def = Economy.findCar(car.id)
	return (def and STYLES[def.style]) or STYLES.van
end

-- Where the loaded pieces ride, relative to the chassis: the bottom centre of a piece, facing the front.
function Vehicles.cargoSlots(car: Car): { CFrame }
	local list = {}
	for _, slot in styleOf(car).cargo.slots do
		table.insert(list, CFrame.new(Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + slot))
	end
	return list
end

-- What the HUD calls the cargo space: "Load it into the back of the {noun}".
function Vehicles.cargoNoun(car: Car): string
	return styleOf(car).cargo.noun
end

-- The back of the vehicle, where the Load / Take out prompt sits.
function Vehicles.cargoDoor(car: Car): Attachment?
	local door = car.chassis:FindFirstChild("CargoDoor")
	return if door and door:IsA("Attachment") then door else nil
end

-- Where passengers get in (the school bus door), on the ground next to the vehicle, in world space.
function Vehicles.cargoEntry(car: Car): Vector3
	local entry = car.chassis:FindFirstChild("CargoEntry")
	local point = if entry and entry:IsA("Attachment") then entry.WorldPosition else car.chassis.Position
	return Vector3.new(point.X, car.chassis.Position.Y - CHASSIS_HEIGHT / 2 - styleOf(car).clearance, point.Z)
end

-- The car gun that goes on this car of the player's: the one in their profile, if the car can carry one.
local function gunFor(player: Player, carId: string): string?
	local profile = PlayerData.get(player)
	local gunId = profile and profile.carGuns[carId]
	if gunId and Economy.canMount(carId) and Economy.findCarGun(gunId) then
		return gunId
	end
	return nil
end

function Vehicles.remove(player: Player)
	local car = cars[player]
	if car then
		cars[player] = nil
		car.wrecked = true
		car.model:Destroy()
	end
end

-- ── Placing a car ──────────────────────────────────────────────────────────

-- Set by server/CarCall.luau: the CAR button (Vehicles.spawn without force) calls the car instead of placing it.
-- Returns an error text, or nil when a chauffeur is on the way.
Vehicles.callCar = nil :: ((player: Player, carId: string?) -> string?)?
-- Set by server/CarCall.luau: where an instant car (force) goes when the player spawns at home (the home garage's
-- drive-out spot), or nil for the usual spot next to them.
Vehicles.homeGarage = function(_player: Player): CFrame?
	return nil
end

-- What a ray looking for the ground must not see: the cars, the people, the enemies, the loot.
local function groundIgnore(): { Instance }
	local list: { Instance } = {}
	for _, name in { "Cars", "Traffic", "BanditCars", "Npcs", "Zombies", "Animals", "Loot", "Showroom" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- The top of the ground at (x, z): a road, a bridge, a hill road, a driveway (looking down from well above refY).
-- Under the mountain (the tunnel) and where nothing is found: the road level.
function Vehicles.groundY(x: number, z: number, refY: number?): number
	local mountain = Map.Mountain
	if (x - mountain.x) ^ 2 + (z - mountain.z) ^ 2 < (mountain.radius + 30) ^ 2 then
		return World.RoadTop
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = groundIgnore()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local top = math.max(refY or World.RoadTop, World.RoadTop) + 90
	local origin = Vector3.new(x, top, z)
	-- Look past what nothing drives on: a sign board, a beam, a steep face (a few tries down through them).
	for _ = 1, 5 do
		local hit = workspace:Raycast(origin, Vector3.new(0, Map.WaterLevel - 6 - origin.Y, 0), params)
		if not hit then
			break
		end
		local part = hit.Instance
		local broad = not part:IsA("BasePart") or part:IsA("Terrain") or math.min(part.Size.X, part.Size.Z) >= 3
		if hit.Normal.Y > 0.6 and broad then
			return if hit.Position.Y > Map.WaterLevel - 2 then hit.Position.Y else World.RoadTop
		end
		origin = hit.Position - Vector3.new(0, 0.05, 0)
	end
	return World.RoadTop
end

-- Moves a spot along `direction` until no other car stands there (a few tries).
local function freeSpot(position: Vector3, direction: Vector3, step: number): Vector3
	for _ = 1, 6 do
		local free = true
		for _, other in cars do
			if (other.chassis.Position - position).Magnitude < 26 then
				free = false
				break
			end
		end
		if free then
			break
		end
		position += direction * step
	end
	return position
end

-- The cooldown of the CAR button: an error text while it runs, else nil (and it starts again).
function Vehicles.cooldown(player: Player): string?
	local now = os.clock()
	if lastSpawn[player] and now - lastSpawn[player] < Config.SpawnCarCooldown then
		return "Wait a moment before calling the car again."
	end
	lastSpawn[player] = now
	return nil
end

-- Builds the player's car (their equipped one, or carId: a company vehicle lent for a job) standing on `ground`
-- (its position on the ground, facing its LookVector) and makes it theirs; the old one goes. seat: the player gets
-- in at once. chauffeured: a chauffeur drives it (server/CarCall.luau): the server owns it and nobody gets in until
-- Vehicles.handOver. Returns nil when the profile is not loaded yet.
function Vehicles.spawnAt(player: Player, carId: string?, ground: CFrame, seat: boolean, chauffeured: boolean?): Car?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local def = Economy.findCar(carId or profile.car) or Config.Cars[1]
	Vehicles.remove(player)

	local stats = Economy.carStats(def.id, profile.upgrades)
	local gunId = gunFor(player, def.id)
	local built = build(def, paintColor(def, if def.company then nil else profile.carPaint[def.id]), ground, false, gunId)
	local driverSeat = built.seat :: VehicleSeat
	local car: Car = {
		owner = player,
		id = def.id,
		model = built.model,
		chassis = built.chassis,
		seat = driverSeat,
		passengers = built.passengers,
		turret = built.turret,
		turretBase = built.turretBase,
		muzzle = built.muzzle,
		gunId = gunId,
		paintParts = built.paintParts,
		size = built.size,
		stats = stats,
		health = stats.health,
		wrecked = false,
		latched = {},
		chauffeured = chauffeured == true,
		born = os.clock(),
	}
	car.model.Name = `{player.DisplayName}'s {def.name}`
	car.model:SetAttribute("OwnerId", player.UserId)
	car.model:SetAttribute("OwnerName", player.DisplayName)
	car.model:SetAttribute("CarId", def.id)
	car.model:SetAttribute("SpeedMult", 1)
	car.model:SetAttribute("CarGun", gunId)
	-- A company vehicle lent for a job runs with its lights flashing (the ambulance's light bar).
	car.model:SetAttribute("Siren", carId ~= nil and def.company == true)
	car.model:SetAttribute("Chauffeured", car.chauffeured)
	writeAttributes(car)
	-- Connect the prompts while they are still on the chassis (the connections follow them into ParkedPrompts and back).
	watchPrompts(car)
	if car.chauffeured then
		-- Out of reach while the chauffeur drives (client/CarVisuals.luau looks for them on the chassis only).
		local parked = Instance.new("Folder")
		parked.Name = "ParkedPrompts"
		parked.Parent = car.model
		for _, name in { "DrivePrompt", "RidePrompt" } do
			local prompt = car.chassis:FindFirstChild(name)
			if prompt then
				prompt.Parent = parked
			end
		end
	end
	car.model.Parent = workspace:FindFirstChild("Cars") or workspace
	cars[player] = car
	watchSeat(car, driverSeat, -1, true)
	for _, p in car.passengers do
		watchSeat(car, p, 1, false)
	end

	-- Heavy enough to plough through, light enough to stop against a wall.
	local mass = car.chassis.AssemblyMass
	local linear = car.chassis:FindFirstChild("Drive") :: LinearVelocity
	local angular = car.chassis:FindFirstChild("Steer") :: AngularVelocity
	linear.MaxForce = mass * 160
	angular.MaxTorque = mass * 6000

	pcall(function()
		car.chassis:SetNetworkOwner(if car.chauffeured then nil else player)
	end)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if seat and not car.chauffeured and humanoid and humanoid.Health > 0 and not carrying(character) then
		task.defer(function()
			if not car.wrecked then
				driverSeat:Sit(humanoid)
			end
		end)
	end
	return car
end

-- The chauffeur got out: the car is its owner's now (the prompts come back, the owner's client drives it again).
function Vehicles.handOver(car: Car)
	if not car.chauffeured then
		return
	end
	car.chauffeured = false
	car.model:SetAttribute("Chauffeured", false)
	if car.wrecked or not car.chassis.Parent then
		return
	end
	local parked = car.model:FindFirstChild("ParkedPrompts")
	if parked then
		for _, prompt in parked:GetChildren() do
			prompt.Parent = car.chassis
		end
		parked:Destroy()
	end
	local linear = car.chassis:FindFirstChild("Drive")
	if linear and linear:IsA("LinearVelocity") then
		linear.PlaneVelocity = Vector2.zero
	end
	local angular = car.chassis:FindFirstChild("Steer")
	if angular and angular:IsA("AngularVelocity") then
		angular.AngularVelocity = Vector3.zero
	end
	pcall(function()
		car.chassis:SetNetworkOwner(car.owner)
	end)
end

-- The car right next to the player on the nearest road, and they get in: the old instant way (a force spawn away
-- from home, the chauffeur's fallback). Returns an error text when it cannot.
function Vehicles.placeNear(player: Player, carId: string?): string?
	if not PlayerData.get(player) then
		return "Still loading..."
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if rootPart then rootPart.Position else World.DepotSpawn
	local look = if rootPart then rootPart.CFrame.LookVector else Vector3.new(0, 0, 1)
	Vehicles.remove(player) -- the old car is not in the way of the new one

	local x, z, dx, dz = Map.nearestRoad(from.X, from.Z)
	local direction = Vector3.new(dx, 0, dz)
	if direction:Dot(look) < 0 then
		direction = -direction
	end
	-- Step along the road if another car stands there.
	local spot = freeSpot(Vector3.new(x, World.RoadTop, z), direction, 28)
	local position = Vector3.new(spot.X, Vehicles.groundY(spot.X, spot.Z, from.Y) + 0.5, spot.Z)
	local car = Vehicles.spawnAt(player, carId, CFrame.lookAt(position, position + direction), true)
	return if car then nil else "Still loading..."
end

-- Gets the player their car. Without force it is the CAR button: a chauffeur brings it (server/CarCall.luau, which
-- also runs the cooldown), unless they sit in their own car (that one is reset right there, as before). force (PLAY,
-- a respawn, a car just bought or equipped, a job's vehicle) is instant: parked at the home garage when they spawn
-- at home, else next to them and seated. carId = a company vehicle lent for a job. Returns an error text when it
-- cannot.
function Vehicles.spawn(player: Player, force: boolean?, carId: string?): string?
	if not PlayerData.get(player) then
		return "Still loading..."
	end
	if not force then
		local inCar = Vehicles.seatedIn(player)
		local call = Vehicles.callCar
		if call and not (inCar and inCar.owner == player) then
			return call(player, carId)
		end
		local err = Vehicles.cooldown(player)
		if err then
			return err
		end
		return Vehicles.placeNear(player, carId)
	end
	lastSpawn[player] = os.clock()
	local home = Vehicles.homeGarage(player)
	if home then
		local look = Vector3.new(home.LookVector.X, 0, home.LookVector.Z)
		look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, 1)
		Vehicles.remove(player) -- the old car is not in the way; a co-owner's car is (step out to the road)
		local spot = freeSpot(home.Position, look, 16)
		local position = Vector3.new(spot.X, Vehicles.groundY(spot.X, spot.Z, home.Position.Y) + 0.5, spot.Z)
		local car = Vehicles.spawnAt(player, carId, CFrame.lookAt(position, position + look), false)
		if not car then
			return "Still loading..."
		end
		local def = Economy.findCar(car.id)
		Net.get("Notice"):FireClient(player, `Your {if def then def.name else "car"} is parked in front of your garage.`)
		return nil
	end
	return Vehicles.placeNear(player, carId)
end

-- New upgrades / a new car equipped: the live car takes the new numbers (health keeps its share).
function Vehicles.refreshStats(player: Player)
	local car = Vehicles.get(player)
	local profile = PlayerData.get(player)
	if not car or not profile then
		return
	end
	local share = car.health / car.stats.health
	car.stats = Economy.carStats(car.id, profile.upgrades)
	car.health = car.stats.health * share
	writeAttributes(car)
end

-- A new paint job on the live car.
function Vehicles.repaint(player: Player)
	local car = Vehicles.get(player)
	local profile = PlayerData.get(player)
	local def = car and Economy.findCar(car.id)
	if not car or not profile or not def then
		return
	end
	local color = paintColor(def, profile.carPaint[car.id])
	for _, p in car.paintParts do
		p.Color = color
	end
end

-- A car gun bought (or changed): the live car gets the turret that fits it now, or loses the one it should not have.
function Vehicles.refreshGun(player: Player)
	local car = Vehicles.get(player)
	if not car then
		return
	end
	local want = gunFor(player, car.id)
	if want == car.gunId and (want == nil) == (car.model:FindFirstChild("CarGun") == nil) then
		return
	end
	local old = car.model:FindFirstChild("CarGun")
	if old then
		old:Destroy()
	end
	car.turret, car.muzzle, car.gunId = nil, nil, nil
	if want then
		car.turret, car.muzzle = buildTurret(car.model, car.chassis, car.turretBase, want)
		car.gunId = want
		-- The new parts joined the car's assembly: the driver's client keeps simulating it (the server while a
		-- chauffeur drives it).
		pcall(function()
			car.chassis:SetNetworkOwner(if car.chauffeured then nil else player)
		end)
	end
	car.model:SetAttribute("CarGun", want)
end

-- The light bar on (an ambulance on a job) or off; every client flashes it (client/Weather.luau).
function Vehicles.setSiren(player: Player, on: boolean)
	local car = Vehicles.get(player)
	if car then
		car.model:SetAttribute("Siren", on)
	end
end

-- A job modifier (HEAVY LOAD) slows the car down; the owner's client reads the attribute.
function Vehicles.setSpeedMultiplier(player: Player, multiplier: number)
	local car = Vehicles.get(player)
	if car then
		car.model:SetAttribute("SpeedMult", multiplier)
	end
end

local function wreck(car: Car, reason: string)
	car.wrecked = true
	eject(car.seat)
	for _, seat in car.passengers do
		eject(seat)
	end
	local explosion = Instance.new("Explosion")
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.BlastRadius = 8
	explosion.Position = car.chassis.Position
	explosion.Parent = workspace
	car.model:SetAttribute("Siren", false)
	for _, d in car.model:GetDescendants() do
		if d:IsA("BasePart") then
			-- Burnt out: the lights stay dark through the night.
			CollectionService:RemoveTag(d, DayNight.Tag)
			CollectionService:RemoveTag(d, Vehicles.SirenTag)
			if d.Material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
			end
			d.Color = d.Color:Lerp(Color3.new(0.08, 0.08, 0.08), 0.75)
		elseif d:IsA("ProximityPrompt") or d:IsA("Light") then
			d:Destroy()
		end
	end
	local fire = Instance.new("Fire")
	fire.Size = 9
	fire.Heat = 12
	fire.Parent = car.chassis
	local linear = car.chassis:FindFirstChild("Drive")
	if linear then
		linear:Destroy()
	end
	car.model:SetAttribute("Health", 0)
	Vehicles.onWrecked(car.owner, car, reason)
	task.delay(5, function()
		if cars[car.owner] == car then
			cars[car.owner] = nil
		end
		car.model:Destroy()
	end)
end

function Vehicles.damage(car: Car, amount: number, reason: string?)
	if car.wrecked or amount <= 0 then
		return
	end
	car.health = math.max(0, car.health - amount)
	car.model:SetAttribute("Health", math.ceil(car.health))
	if car.health <= 0 then
		wreck(car, reason or "Your car was destroyed!")
	end
end

function Vehicles.repair(car: Car, share: number)
	if car.wrecked then
		return
	end
	car.health = math.min(car.stats.health, car.health + car.stats.health * share)
	car.model:SetAttribute("Health", math.ceil(car.health))
end

-- Points the roof gun (if the car has one) at a world position.
function Vehicles.aim(car: Car, target: Vector3)
	local turret = car.turret
	if not turret then
		return
	end
	local localTarget = car.chassis.CFrame:PointToObjectSpace(target)
	local yaw = math.atan2(-localTarget.X, -localTarget.Z)
	turret.C0 = car.turretBase * CFrame.Angles(0, yaw, 0)
end

-- Where a shot out of the side window of this seat starts: beside the seat, at head height, just outside the body
-- (client/Shooting.luau draws the tracer from the same point).
function Vehicles.windowPoint(car: Car, seat: BasePart): Vector3
	local frame = car.chassis.CFrame
	local at = frame:PointToObjectSpace(seat.Position)
	local side = if at.X >= 0 then 1 else -1
	return (frame * CFrame.new(side * (car.chassis.Size.X / 2 + 0.6), at.Y + 2.6, at.Z)).Position
end

function Vehicles.start()
	Players.PlayerRemoving:Connect(function(player)
		Vehicles.remove(player)
		lastSpawn[player] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		for _, car in cars do
			if car.wrecked then
				continue
			end
			local position = car.chassis.Position
			-- Repairs in the depot yard and in Wrench Garage: 15 % of the health per second.
			if car.health < car.stats.health and World.canRepair(position) then
				Vehicles.repair(car, 0.15 * dt)
			end
			-- Drove into the water (or off the world).
			if position.Y < -7 then
				Vehicles.damage(car, math.huge, "Your car sank!")
			end
		end
	end)
end

return Vehicles
