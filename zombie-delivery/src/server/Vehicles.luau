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
-- Other players ride along in the passenger seats (a "Ride along" prompt at their door, 3.7) and shoot from there
-- (server/Gun.luau).
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
-- Vehicles.callCar: a chauffeur drives it to you. While a chauffeur drives a car (car.chauffeured, the attribute
-- Chauffeured) the SERVER owns and drives it, nobody gets in (the door prompts refuse, the clients hide them);
-- Vehicles.handOver gives it to its owner (the chauffeur's door swings, the owner's client owns it again). The
-- instant cases stay instant (force: PLAY, a respawn, a car bought or equipped, a job's vehicle): next to you and
-- seated, or, when you spawn at home, parked at your home's garage drive-out spot (the hook Vehicles.homeGarage).
--
-- 3.2, the back that opens: every car that takes cargo by hand (all but the bus) has one, its Style.back: two rear
-- doors (the vans and the box trucks), a tailgate (the pickup, the monster truck, the fuel truck's flatbed), a trunk
-- lid (the muscle car), a horse ramp (the livestock truck). Each leaf hangs on a Motor6D "BackHinge" on the chassis
-- (C0 = the hinge line, set once when it is built; closed = no Transform; the attributes Axis and Angle = the open
-- turn). The car model's attribute BackOpen says where it is and every client swings the leaves there
-- (client/CarVisuals.luau). The "BackPrompt" at the back (Open doors / Close doors …) opens and closes it: on foot,
-- a hand free (3.7), the car standing, the owner or who the hook Vehicles.backAllowed lets (server/Cargo.luau: the
-- job's crew). While it is open nobody gets behind the wheel (the Drive prompt refuses) and the driver's client
-- holds the throttle (client/Drive.luau); server/Cargo.luau loads and unloads only through an open back. A new car
-- (a chauffeur's, a respawn) starts closed. The NPC and traffic cars and the showroom models have the leaves welded shut.
--
-- 3.3: five more vans (courier, highroof, boxtruck, armorvan, rallyvan: their STYLES below) and the upgrades you can
-- see. A player's car carries the "UpgradeKit" (buildKit) for ITS car-track levels (profile.carUpgrades, Economy
-- carLevels): Ram Plow a bull bar on the front (wider and heavier with the level), Armor side plates (window grilles
-- from level 3; not on a style that has its own, Style.armored), Engine a hood scoop and twin exhaust pipes from
-- level 3. Cosmetic: welded, massless, no collisions, not hit by rays, their own colours (never painted). It is built
-- with the car and rebuilt when the levels change (Vehicles.refreshStats). Quick Hands (the loading track) shortens
-- the BackPrompt's hold (Vehicles.loadHold; server/Cargo.luau uses it for the cargo prompts of the job's car).
--
-- 3.4: cargo capacity. A car takes Config.Cars capacity pieces (= its STYLES cargo slots). The car's damage stays with it:
-- its share of health is kept per car in profile.carHealth (remember: every hit, every repair, when it is parked); a
-- car comes back as damaged as it went, a wrecked one with Config.Repair.WreckedHealth. A company vehicle lent for a
-- job (Car.lent) always comes fresh from its employer. No free repairs any more (the depot yard and Wrench Garage
-- healed before 3.4): server/Repair.luau runs the repair bays (Vehicles.setRepairing locks the car on the lift; the
-- hook Vehicles.beforeDrive tells it the owner got back in).
--
-- 3.5, the stages (Config.Cars stages, the car's stage in profile.carUpgrades[carId].stage): every stage after 0 has
-- a LOOK (LOOKS below, styleFor): boxes added to the style's body (painted like it when they are "body"), cosmetic
-- trim added, boxes and trim with some tags taken off (the Old Van's rust, primer patches and loose bumper go at the
-- Work Van), its own cargo slots (as many as the stage holds: tests/run_tests.py counts them), and maybe a new roof
-- height for the gun. Stage 0 is the plain style (the Old Van's is the Rusty Van). A new stage builds the live car
-- again where it stands (Vehicles.refreshStats → rebuild). The traffic drives the vans at random stages. The 3.4
-- Cargo Rack (a roof rack with extra slots in the UpgradeKit) is gone: a 3.4 save got the stage that covers it.
--
-- 3.7, the doors (doorsOf below): you get in at a door. The E shows only there and only close (Config.Cargo.DoorReach):
-- "Drive" at the driver's door on the left for the owner, "Ride along" at a passenger door (the front passenger's on
-- the right, a rear seat's at its own side, the bus's folding door) for everybody else, so a passenger on the right
-- never gets the driver's seat. The seats never take you by touch (CanTouch off), only through these prompts. A cabin
-- door swings open as you get in or out (the Motor6D "DoorHinge", client/CarVisuals.luau) and you step out at your
-- own door. 3.7 too, a free hand: one light piece in your hands (the character attribute CarryHands = 1, server/
-- Cargo.luau) and you open and close the back yourself; two pieces or a heavy one, put one down first (G).
-- 3.10, getting in and out (shared/Boarding.luau): the E at a door reserves the seat (its attribute Reserved) and
-- starts the move (the character's attributes Boarding = "ownerId:door:seat", BoardAt, BoardReach); the player's
-- own client plays it (client/CarBoarding.luau: a step to the handle, the hand on it, the slide in) and THIS server
-- seats them Config.Cargo.BoardSeconds after the E, when they are still there (else it is cancelled: they stand at
-- the door). Out (E in a seat: the CarDoor remote; Space; an eject) the client slides out at its door in
-- AlightSeconds (the attribute AlightAt for the others' arm); somebody still over the car after that is put out at
-- the door. The doors swing from their DoorOpenAt / DoorCloseAt attributes (server times).
--
-- 4.0, Freight (the vehicles):
-- * The Rusty Van looks the part (STYLES.van): big corroded rust patches, a primer-grey driver's door (Style.primerDoor),
--   a dented crooked bumper (Box.tilt), a cracked windscreen ("crack" trim), bald grey tyres (Style.bald), a yellowed
--   dim headlight (Style.dimHead) and a smoking exhaust (Style.smoky: the model's attribute Smoky till Engine 1;
--   client/CarVisuals.luau puffs at the Attachment "Exhaust"). Later stages fix it (Look.fresh).
-- * A look may STRETCH the body (Look.stretch, stretchStyle): the Work Van +1.5, the Long Cargo Van +3.5, the Box
--   Truck's Freight Hauler +3. Everything behind the style's split moves back, the long boxes across it grow, the car
--   stays centred on its chassis; the stretched style is cached per look (its doors with it).
-- * The UpgradeKit also shows Tyres & Suspension (new tyres with tread rings from 1, alloy rims from 3; the stance at 5
--   lowers the body: Car.lower, a rebuild) and the Hand Trolley folded inside the back (the model "FoldedTrolley" and
--   the chassis Attachment "TrolleyMount", Economy.hasTrolley).
-- * The Freight Truck (STYLES.freighttruck): a cab-over truck with a long box, 12 slots in three pallet bays, a
--   roll-up door (rollUpDoor), twin rear tyres (Style.dual) and the Attachment "JackMount" inside the back (its pallet
--   jack: server/Cargo.luau). A long car comes out of a garage further from the door (Vehicles.placeAt).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
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
local Boarding = require(Shared.Boarding)
local VehicleArt = require(script.Parent.VehicleArt.Builder)

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
	kit: string, -- 3.3: the car-track levels its UpgradeKit shows (kitKey)
	stage: number, -- 3.5: the stage its body was built at (Config.Cars stages; 0 for a company vehicle)
	lower: number, -- 4.0: how much lower its body sits (Tyres & Suspension 5: stanceOf); a change builds it again
	lent: boolean, -- 3.4: a company vehicle lent for a job: its damage is not kept
	repairing: boolean, -- 3.4: on the lift of a repair bay (server/Repair.luau): anchored, nobody drives it
	doors: { CarDoor }, -- 3.7: its doors (doorsOf): index 1 is the driver's
}

local Vehicles = {}

local cars: { [Player]: Car } = {}
local lastSpawn: { [Player]: number } = {}

-- Set by Main: (player, car, reason) when a car is destroyed.
Vehicles.onWrecked = function(_player: Player, _car: Car, _reason: string) end

local DARK = Color3.fromRGB(34, 34, 38)
local GLASS = Color3.fromRGB(150, 190, 210)
local BALD = Color3.fromRGB(112, 110, 104) -- 4.0: worn, bald tyres
local DIM_HEAD_LIT, DIM_HEAD_DIM = Color3.fromRGB(232, 196, 118), Color3.fromRGB(150, 136, 98) -- 4.0: a yellowed lamp

-- kind: body | dark | glass | accent | plate | white | ball | logo | wood | rail | cross | sirenred | sirenblue |
-- lightbar | hole | amber; 3.5: rust | primer | chrome | lamp | tyre; 4.0: crack (a line on cracked glass). tag (3.5): a
-- stage's look takes off the boxes with the tags it names (LOOKS drop). tilt (4.0): degrees of roll about the car's
-- length (a crooked bumper, a crack across the windscreen).
type Box = { size: Vector3, offset: Vector3, kind: string, tag: string?, tilt: number? }

-- 3.2: one leaf of the back (a door, a tailgate, a lid, a ramp), relative to the chassis top centre, closed.
type Leaf = {
	size: Vector3,
	center: Vector3,
	hinge: Vector3, -- a point on the hinge line
	axis: string, -- "Y": a door swinging out sideways | "X": a tailgate or a ramp dropping, a lid rising
	angle: number, -- degrees of the open turn about the axis
	kind: string?, -- its look (a Box kind), default body (painted)
	trim: { Box }?, -- welded onto the leaf: offsets from the leaf's centre
}
-- noun: doors | tailgate | trunk | ramp; hole: the dark opening the leaves cover (the body behind them is solid).
type Back = { noun: string, leaves: { Leaf }, hole: Box? }

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
	back: Back?, -- 3.2: the back that opens (nil: the bus, nobody loads it by hand)
	armored: boolean?, -- 3.3: plates and grilles of its own: the Armor upgrade adds none (buildKit)
	trim: { Box }?, -- 3.5: cosmetic boxes (no collisions, not hit by rays): rust, ladders, racks, lamps …
	hoodBusy: boolean?, -- 3.5: something sits on the hood already (a blower): the Engine upgrade adds no scoop
	rideDoor: number?, -- 3.7: every passenger gets in through one door on the right at this z (the bus)
	doorTrim: { Box }?, -- 3.7: on both front doors' panels: offsets from the panel's centre, +x outward
	-- 4.0: where a look's stretch goes in (z): what lies behind it moves back, a long box across it gets longer (stretch).
	split: number?,
	-- 4.0, the Rusty Van's faults (a fresh stage, Look.fresh, fixes them): the door (doorsOf index) in mismatched grey
	-- primer, one yellowed dim headlight, bald grey tyres (till Tyres & Suspension 1), a smoking exhaust (till Engine 1).
	primerDoor: number?,
	dimHead: boolean?,
	bald: boolean?,
	smoky: boolean?,
	dual: boolean?, -- 4.0: twin tyres on the rear axle (the Freight Truck)
	jack: Vector3?, -- 4.0: the Attachment JackMount (the pallet jack, server/Cargo.luau), relative to the chassis top centre
}

local function box(size: Vector3, offset: Vector3, kind: string, tag: string?, tilt: number?): Box
	return { size = size, offset = offset, kind = kind, tag = tag, tilt = tilt }
end

-- 4.0: a crack across a window (a thin dark line in the plane of the glass face at z, tilted).
local function crack(length: number, x: number, y: number, z: number, tilt: number): Box
	return box(Vector3.new(0.05, length, 0.03), Vector3.new(x, y, z), "crack", "crack", tilt)
end

-- 4.0: a box's turn (its tilt) on top of where it sits.
local function tilted(b: Box): CFrame
	local tilt = b.tilt
	return if tilt then CFrame.Angles(0, 0, math.rad(tilt)) else CFrame.identity
end

local function cargo(noun: string, length: number, width: number, slots: { Vector3 }, entry: Vector3?): CargoSpec
	return {
		slots = slots,
		noun = noun,
		door = Vector3.new(0, 2.4, length / 2 + 0.6),
		entry = entry or Vector3.new(width / 2 + 1.5, 0, 0),
	}
end

-- 3.2: two rear doors over the back face of a box (`width` wide, from `bottom` to `top`, the face at z = `rear`),
-- hinged at the outer edges, swinging out to the sides. trim(side): what else sits on that side's door (-1 left).
-- The doors start above the tail lights (DOOR_SILL): those stay on the body below them.
local DOOR_SILL = 0.95
local function rearDoors(width: number, bottom: number, top: number, rear: number, trim: ((side: number) -> { Box })?): Back
	local leafWidth = width / 2 - 0.05
	local height = top - bottom
	local y = (bottom + top) / 2
	local leaves: { Leaf } = {}
	for _, side in { -1, 1 } do
		local extra: { Box } = if trim then trim(side) else {}
		-- A handle at the inner edge of every door.
		table.insert(extra, box(Vector3.new(0.3, 0.9, 0.1), Vector3.new(-side * (leafWidth / 2 - 0.45), -0.3, 0.13), "dark"))
		table.insert(leaves, {
			size = Vector3.new(leafWidth, height, 0.2),
			center = Vector3.new(side * (width / 2 - leafWidth / 2), y, rear + 0.1),
			hinge = Vector3.new(side * width / 2, y, rear + 0.2),
			axis = "Y",
			angle = side * 120,
			trim = extra,
		})
	end
	return { noun = "doors", leaves = leaves, hole = box(Vector3.new(width - 0.5, height - 0.3, 0.05), Vector3.new(0, y, rear + 0.04), "hole") }
end

-- 3.2: a tailgate (or a ramp) hinged at its bottom back edge, dropping backward by `angle` degrees.
local function tailgate(noun: string, size: Vector3, center: Vector3, angle: number, kind: string?, trim: { Box }?): Back
	local hinge = Vector3.new(center.X, center.Y - size.Y / 2, center.Z + size.Z / 2)
	return { noun = noun, leaves = { { size = size, center = center, hinge = hinge, axis = "X", angle = angle, kind = kind, trim = trim } } }
end

-- 4.0: a roll-up door over the back face of a box (`width` wide, from `bottom` to `top`, the face at z = `rear`): one
-- slatted leaf hinged at its top edge that turns up and in under the roof (the noun "roll-up door").
local function rollUpDoor(width: number, bottom: number, top: number, rear: number): Back
	local height = top - bottom
	local y = (bottom + top) / 2
	local trim: { Box } = {}
	for n = 1, math.floor(height / 0.8) do
		table.insert(trim, box(Vector3.new(width - 0.3, 0.08, 0.04), Vector3.new(0, -height / 2 + n * 0.8, 0.12), "dark")) -- the slats
	end
	table.insert(trim, box(Vector3.new(1.4, 0.22, 0.16), Vector3.new(0, -height / 2 + 0.45, 0.17), "chrome")) -- the handle
	local leaf: Leaf = {
		size = Vector3.new(width - 0.2, height, 0.2),
		center = Vector3.new(0, y, rear + 0.1),
		hinge = Vector3.new(0, top, rear + 0.1),
		axis = "X",
		angle = 88,
		trim = trim,
	}
	return { noun = "roll-up door", leaves = { leaf }, hole = box(Vector3.new(width - 0.4, height - 0.2, 0.05), Vector3.new(0, y, rear + 0.04), "hole") }
end

-- 4.0, the Freight Truck: a cab-over cab (no hood: you sit over the front wheels) with a wind deflector, a long box with
-- its floor at dock height, side skirts, a fuel tank, an exhaust stack, twin rear tyres, a roll-up door at the back.
local function freightBoxes(): { Box }
	return {
		box(Vector3.new(8.8, 3.0, 6.2), Vector3.new(0, 1.5, -11.9), "body"), -- the cab's lower body (the doors)
		box(Vector3.new(8.8, 4.0, 5.8), Vector3.new(0, 5.0, -12.1), "glass"), -- the cab
		box(Vector3.new(8.8, 4.0, 0.4), Vector3.new(0, 5.0, -9.0), "body"), -- its back wall
		box(Vector3.new(8.8, 0.8, 6.2), Vector3.new(0, 7.4, -11.9), "body"), -- its roof
		box(Vector3.new(8.2, 1.6, 2.6), Vector3.new(0, 8.6, -10.6), "body"), -- the wind deflector
		box(Vector3.new(5.0, 1.2, 0.12), Vector3.new(0, 1.0, -15.06), "dark"), -- the grille
		box(Vector3.new(9.2, 1.0, 0.7), Vector3.new(0, 0.1, -15.3), "dark"), -- the bumper
		box(Vector3.new(9.0, 9.2, 23.6), Vector3.new(0, 4.6, 3.2), "body"), -- the box
		box(Vector3.new(9.1, 1.0, 22.8), Vector3.new(0, 2.2, 3.2), "accent"), -- a stripe down the box
		box(Vector3.new(9.1, 1.6, 14.0), Vector3.new(0, 6.4, 3.2), "logo"), -- the freight band
		box(Vector3.new(9.2, 0.5, 23.6), Vector3.new(0, 0.25, 3.2), "dark"), -- the bottom rail
		box(Vector3.new(0.3, 9.2, 0.3), Vector3.new(-4.55, 4.6, -8.45), "rail"), -- the box's corner posts
		box(Vector3.new(0.3, 9.2, 0.3), Vector3.new(4.55, 4.6, -8.45), "rail"),
		box(Vector3.new(0.3, 9.2, 0.3), Vector3.new(-4.55, 4.6, 14.85), "rail"),
		box(Vector3.new(0.3, 9.2, 0.3), Vector3.new(4.55, 4.6, 14.85), "rail"),
	}
end

local function freightTrim(): { Box }
	local list: { Box } = {
		box(Vector3.new(0.15, 1.1, 15.0), Vector3.new(-4.55, -0.45, 2.5), "dark"), -- side skirts
		box(Vector3.new(0.15, 1.1, 15.0), Vector3.new(4.55, -0.45, 2.5), "dark"),
		box(Vector3.new(1.2, 1.2, 2.6), Vector3.new(-4.0, -0.2, -7.5), "chrome"), -- the fuel tank
		box(Vector3.new(0.45, 6.0, 0.45), Vector3.new(-4.7, 5.0, -9.5), "chrome"), -- the exhaust stack
		box(Vector3.new(0.5, 0.25, 1.6), Vector3.new(-4.65, 0.4, -12.4), "dark"), -- the cab steps
		box(Vector3.new(0.5, 0.25, 1.6), Vector3.new(4.65, 0.4, -12.4), "dark"),
		box(Vector3.new(0.2, 1.3, 0.5), Vector3.new(-4.8, 4.6, -14.4), "dark"), -- the mirrors
		box(Vector3.new(0.2, 1.3, 0.5), Vector3.new(4.8, 4.6, -14.4), "dark"),
		box(Vector3.new(8.6, 0.4, 0.4), Vector3.new(0, -0.7, 15.3), "rail"), -- the rear underride bar
		box(Vector3.new(5.6, 0.25, 0.5), Vector3.new(0, 0.55, 15.25), "plate"), -- the dock plate at the loading floor
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(-4.56, 8.9, -8.2), "amber"), -- marker lights on the box
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(4.56, 8.9, -8.2), "amber"),
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(-4.56, 8.9, 14.6), "amber"),
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(4.56, 8.9, 14.6), "amber"),
	}
	for _, x in { -2, -1, 0, 1, 2 } do
		table.insert(list, box(Vector3.new(0.35, 0.25, 0.35), Vector3.new(x, 7.9, -14.6), "amber")) -- on the cab roof
	end
	for _, side in { -1, 1 } do
		for _, z in { -10.55, 14.65 } do
			table.insert(list, box(Vector3.new(1.6, 1.4, 0.1), Vector3.new(side * 3.4, -0.85, z), "dark")) -- mud flaps
		end
	end
	return list
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
		-- (3.7: the hazard plates ride on the doors now: Style.doorTrim)
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
	return list
end

-- 3.2: the ambulance's rear doors carry the windows, the red stripes round the back and a red cross on the right one.
local function ambulanceDoor(side: number): { Box }
	local list = {
		box(Vector3.new(2.4, 1.6, 0.06), Vector3.new(-side * 0.375, 0.875, 0.12), "glass"),
		box(Vector3.new(3.65, 0.9, 0.06), Vector3.new(0, -1.625, 0.12), "accent"),
		box(Vector3.new(3.65, 0.3, 0.06), Vector3.new(0, 2.075, 0.12), "accent"),
	}
	if side > 0 then
		table.insert(list, box(Vector3.new(1.4, 0.45, 0.08), Vector3.new(-0.375, -0.725, 0.15), "cross"))
		table.insert(list, box(Vector3.new(0.45, 1.4, 0.08), Vector3.new(-0.375, -0.725, 0.15), "cross"))
	end
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
		split = 2, -- 4.0: the Work Van and the Long Cargo Van grow in the middle of the cargo box
		boxes = {
			box(Vector3.new(6.6, 2, 2.6), Vector3.new(0, 1, -5.2), "body"), -- hood
			box(Vector3.new(6.6, 4.4, 4), Vector3.new(0, 2.2, -2), "glass"), -- cabin
			box(Vector3.new(6.6, 0.6, 4), Vector3.new(0, 4.7, -2), "body"), -- cabin roof
			box(Vector3.new(6.6, 5, 6.4), Vector3.new(0, 2.5, 3.2), "body"), -- cargo box
			-- 3.5: a loose, rusty bumper; 4.0: dented and crooked (one end hangs low).
			box(Vector3.new(6.8, 0.7, 0.5), Vector3.new(0.25, 0.25, -6.6), "rust", "bumper", -4),
		},
		-- 3.5, the Rusty Van (stage 0): rust and grey primer over the dents (the Patched Van grinds the rust off, the Work
		-- Van paints it all over). 4.0: big corroded patches (the sills, the arches, the hood, the roof), a cracked
		-- windscreen, a dented bumper corner.
		trim = {
			box(Vector3.new(0.06, 1.6, 2.6), Vector3.new(-3.32, 1.2, 4.6), "rust", "rust"), -- the left side, low at the back
			box(Vector3.new(0.06, 0.55, 5.4), Vector3.new(-3.33, 0.3, 2.9), "rust", "rust"), -- both sills
			box(Vector3.new(0.06, 0.55, 5.8), Vector3.new(3.33, 0.3, 3.0), "rust", "rust"),
			box(Vector3.new(0.06, 1.2, 1.9), Vector3.new(3.32, 3.6, 2.3), "rust", "rust"), -- the right side, high up
			box(Vector3.new(0.06, 1.0, 1.4), Vector3.new(3.32, 1.2, 6.0), "rust", "rust"), -- the right rear corner
			box(Vector3.new(0.06, 1.0, 1.3), Vector3.new(3.32, 1.1, -5.6), "rust", "rust"), -- the front arches
			box(Vector3.new(0.06, 0.8, 1.1), Vector3.new(-3.32, 1.3, -5.0), "rust", "rust"),
			box(Vector3.new(2.4, 0.06, 1.5), Vector3.new(1.5, 2.03, -5.4), "rust", "rust"), -- on the hood
			box(Vector3.new(2.2, 0.06, 2.4), Vector3.new(-1.3, 5.03, 4.4), "rust", "rust"), -- on the roof
			box(Vector3.new(0.08, 0.9, 1.3), Vector3.new(-3.33, 2.9, 1.4), "primer", "primer"),
			box(Vector3.new(0.08, 0.7, 1.0), Vector3.new(3.33, 1.5, 4.4), "primer", "primer"),
			box(Vector3.new(0.7, 0.3, 0.12), Vector3.new(-2.4, 0.15, -6.88), "dark", "bumper"), -- the dent in the bumper
			-- The cracked windscreen: a few dark lines from a stone chip on the right.
			crack(1.7, 1.55, 3.35, -4.02, 38),
			crack(1.3, 0.75, 3.0, -4.02, -62),
			crack(1.1, 1.95, 2.75, -4.02, -24),
			crack(0.9, 1.05, 3.75, -4.02, 72),
			crack(0.7, 2.35, 3.8, -4.02, 12),
		},
		primerDoor = 1, -- the driver's door, from another van (4.0)
		dimHead = true,
		bald = true,
		smoky = true,
		cargo = cargo("van", 13, 6.6, { Vector3.new(-1.5, 0, 4.6), Vector3.new(1.5, 0, 4.6) }),
		back = rearDoors(6.6, DOOR_SILL, 4.8, 6.4, function(side: number): { Box }
			return { box(Vector3.new(2.2, 1.2, 0.06), Vector3.new(-side * 0.25, 0.825, 0.12), "glass") } -- rear windows
		end),
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
			box(Vector3.new(6.8, 0.9, 0.7), Vector3.new(0, 0.3, -6.7), "dark"),
		},
		cargo = cargo("pickup", 13, 6.4, { Vector3.new(-1.4, 0, 5.1), Vector3.new(1.4, 0, 5.1) }),
		back = tailgate("tailgate", Vector3.new(5.6, 1.6, 0.4), Vector3.new(0, 0.8, 6.3), 92, nil, {
			box(Vector3.new(5.0, 0.25, 0.08), Vector3.new(0, 0.45, 0.22), "dark"), -- the latch bar
		}),
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
			box(Vector3.new(1.6, 0.05, 13.5), Vector3.new(0.9, 1.42, 0), "accent"), -- stripes
			box(Vector3.new(1.6, 0.05, 13.5), Vector3.new(-0.9, 1.42, 0), "accent"),
		},
		cargo = cargo("car", 13.5, 6.4, { Vector3.new(0, 0.3, 5) }),
		-- The trunk lid on the rear deck, hinged at its front edge; the spoiler and the stripes ride on it.
		back = {
			noun = "trunk",
			leaves = {
				{
					size = Vector3.new(6.0, 0.12, 3.0),
					center = Vector3.new(0, 1.46, 5.0),
					hinge = Vector3.new(0, 1.52, 3.5),
					axis = "X",
					angle = -65,
					trim = {
						box(Vector3.new(6.4, 0.3, 1.4), Vector3.new(0, 1.14, 1.2), "dark"), -- spoiler
						box(Vector3.new(0.4, 1.2, 0.4), Vector3.new(-2.6, 0.54, 1.2), "dark"),
						box(Vector3.new(0.4, 1.2, 0.4), Vector3.new(2.6, 0.54, 1.2), "dark"),
						box(Vector3.new(1.6, 0.03, 3.0), Vector3.new(0.9, 0.07, 0), "accent"), -- the stripes
						box(Vector3.new(1.6, 0.03, 3.0), Vector3.new(-0.9, 0.07, 0), "accent"),
					},
				},
			},
			hole = box(Vector3.new(5.6, 0.02, 2.8), Vector3.new(0, 1.45, 5.0), "hole"),
		},
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
		cargo = cargo("truck", 14, 6.8, {
			Vector3.new(-1.6, 0, 1.4),
			Vector3.new(1.6, 0, 1.4),
			Vector3.new(-1.6, 0, 4.6),
			Vector3.new(1.6, 0, 4.6),
			Vector3.new(-1.6, 2.5, 1.4), -- 3.4: a shelf over the front pair
			Vector3.new(1.6, 2.5, 1.4),
		}),
		back = rearDoors(6.8, DOOR_SILL, 5.4, 7.0, function(_side: number): { Box }
			return { box(Vector3.new(3.35, 0.65, 0.06), Vector3.new(0, -1.9, 0.12), "accent") } -- the pink stripe goes round
		end),
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
		cargo = cargo("truck", 15, 7.4, {
			Vector3.new(-1.8, 0, 2),
			Vector3.new(1.8, 0, 2),
			Vector3.new(-1.8, 0, 5.2),
			Vector3.new(1.8, 0, 5.2),
			Vector3.new(-1.8, 2.6, 2), -- 3.4: stacked on top (the army's big loads)
			Vector3.new(1.8, 2.6, 2),
			Vector3.new(-1.8, 2.6, 5.2),
			Vector3.new(1.8, 2.6, 5.2),
		}),
		back = rearDoors(7.4, DOOR_SILL, 5.8, 7.3, function(_side: number): { Box }
			return {
				box(Vector3.new(3.65, 1, 0.08), Vector3.new(0, -1.775, 0.13), "plate"), -- the armour plates go on over the doors
				box(Vector3.new(3.65, 1, 0.08), Vector3.new(0, 1.025, 0.13), "plate"),
			}
		end),
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
		rideDoor = -9.6, -- the folding door at the front right (where the kids get on: the cargo entry)
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
			Vector3.new(-1.8, 3.6, -0.6), -- 3.4: a second layer in the tall box
			Vector3.new(1.8, 3.6, -0.6),
			Vector3.new(-1.8, 3.6, 2.8),
			Vector3.new(1.8, 3.6, 2.8),
		}),
		back = rearDoors(7.6, DOOR_SILL, 7.8, 8.2, function(_side: number): { Box }
			return { box(Vector3.new(3.7, 0.25, 0.06), Vector3.new(0, 2.625, 0.12), "dark") } -- the top rail
		end),
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
			box(Vector3.new(0.3, 1.0, 5), Vector3.new(-3.35, 2.3, 4), "body"), -- 3.2: rails round the bed
			box(Vector3.new(0.3, 1.0, 5), Vector3.new(3.35, 2.3, 4), "body"),
		},
		cargo = cargo("truck", 14, 8, {
			Vector3.new(-2.2, 1.8, 5.6),
			Vector3.new(0, 1.8, 5.6),
			Vector3.new(2.2, 1.8, 5.6),
			Vector3.new(0, 3.8, 5.6),
			Vector3.new(-2.2, 3.8, 5.6), -- 3.4: piled higher in the bed
			Vector3.new(2.2, 3.8, 5.6),
		}),
		back = tailgate("tailgate", Vector3.new(6.4, 1.0, 0.25), Vector3.new(0, 2.3, 6.375), 92),
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
		-- The ramp, folded up at the back: lowered it reaches the ground, the cleats on its inside face up.
		back = tailgate("ramp", Vector3.new(6.8, 6.6, 0.35), Vector3.new(0, 3.5, 9.8), 112, "wood", {
			box(Vector3.new(6.4, 0.2, 0.12), Vector3.new(0, -2.4, -0.22), "rail"),
			box(Vector3.new(6.4, 0.2, 0.12), Vector3.new(0, -1.2, -0.22), "rail"),
			box(Vector3.new(6.4, 0.2, 0.12), Vector3.new(0, 0, -0.22), "rail"),
			box(Vector3.new(6.4, 0.2, 0.12), Vector3.new(0, 1.2, -0.22), "rail"),
			box(Vector3.new(6.4, 0.2, 0.12), Vector3.new(0, 2.4, -0.22), "rail"),
		}),
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
		doorTrim = { box(Vector3.new(0.06, 1.6, 1.3), Vector3.new(0.06, 0.05, -0.45), "white") }, -- the hazard plates
		cargo = cargo("truck", 16, 7.2, {
			Vector3.new(-1.7, 0.5, 2.6),
			Vector3.new(1.7, 0.5, 2.6),
			Vector3.new(-1.7, 0.5, 6),
			Vector3.new(1.7, 0.5, 6),
			Vector3.new(-1.7, 3.3, 2.6), -- 3.4: a second row on top, against the headboard
			Vector3.new(1.7, 3.3, 2.6),
		}),
		back = tailgate("tailgate", Vector3.new(6.4, 1.6, 0.25), Vector3.new(0, 1.3, 7.875), 95, "accent", {
			box(Vector3.new(6.4, 0.3, 0.08), Vector3.new(0, 0.2, 0.15), "rail"),
		}),
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
		back = rearDoors(7.4, DOOR_SILL, 6.1, 7.5, ambulanceDoor),
	},
	-- 3.3, the dealer's new vans. A compact courier van: low, a sliding-door line on the right, an amber light bar.
	courier = {
		width = 6.2,
		length = 12,
		wheel = 1.2,
		wheelWidth = 0.95,
		clearance = 0.8,
		seat = Vector3.new(-1.3, 0.4, -1.8),
		passengers = { Vector3.new(1.3, 0.4, -1.8) },
		roof = 4.7,
		boxes = {
			box(Vector3.new(6.2, 1.8, 2.4), Vector3.new(0, 0.9, -4.8), "body"), -- hood
			box(Vector3.new(6.2, 3.8, 3.6), Vector3.new(0, 1.9, -1.8), "glass"), -- cabin
			box(Vector3.new(6.2, 0.5, 3.6), Vector3.new(0, 4.05, -1.8), "body"), -- cabin roof
			box(Vector3.new(6.2, 4.3, 6), Vector3.new(0, 2.15, 3), "body"), -- cargo box
			box(Vector3.new(6.4, 0.7, 0.5), Vector3.new(0, 0.35, -6.15), "dark"), -- bumper
			box(Vector3.new(0.06, 3.4, 0.12), Vector3.new(3.11, 1.95, 3.2), "dark"), -- the sliding door's seam …
			box(Vector3.new(0.08, 0.14, 3.6), Vector3.new(3.12, 3.45, 1.6), "dark"), -- … its rail …
			box(Vector3.new(0.1, 0.25, 0.6), Vector3.new(3.14, 2.0, 0.7), "dark"), -- … and its handle
			box(Vector3.new(3.2, 0.3, 0.8), Vector3.new(0, 4.45, -2.9), "dark"), -- the light bar
			box(Vector3.new(1.1, 0.3, 0.6), Vector3.new(-0.95, 4.75, -2.9), "amber"),
			box(Vector3.new(1.1, 0.3, 0.6), Vector3.new(0.95, 4.75, -2.9), "amber"),
		},
		cargo = cargo("van", 12, 6.2, { Vector3.new(-1.4, 0, 4.4), Vector3.new(1.4, 0, 4.4) }),
		back = rearDoors(6.2, DOOR_SILL, 4.1, 6.0, function(side: number): { Box }
			return { box(Vector3.new(2.0, 1.0, 0.06), Vector3.new(-side * 0.25, 0.6, 0.12), "glass") } -- rear windows
		end),
	},
	-- A high-roof van: the roof well over your head, windows down the cargo box, a jump seat behind the passenger.
	highroof = {
		width = 6.8,
		length = 14,
		wheel = 1.35,
		wheelWidth = 1.05,
		clearance = 0.95,
		seat = Vector3.new(-1.4, 0.5, -2.4),
		passengers = { Vector3.new(1.4, 0.5, -2.4), Vector3.new(1.6, 0.5, 0.4) },
		roof = 7.0,
		boxes = {
			box(Vector3.new(6.8, 2, 2.6), Vector3.new(0, 1, -5.7), "body"), -- hood
			box(Vector3.new(6.8, 4.4, 4), Vector3.new(0, 2.2, -2.4), "glass"), -- cabin
			box(Vector3.new(6.8, 2.2, 4), Vector3.new(0, 5.5, -2.4), "body"), -- the high roof over the cabin
			box(Vector3.new(6.8, 6.6, 7.4), Vector3.new(0, 3.3, 3.3), "body"), -- cargo box
			box(Vector3.new(6.86, 1.2, 3.6), Vector3.new(0, 4.4, 1.6), "glass"), -- side windows of the box
			box(Vector3.new(6.86, 0.5, 7.4), Vector3.new(0, 1.6, 3.3), "accent"), -- a stripe
			box(Vector3.new(1.6, 0.3, 1.6), Vector3.new(0, 6.75, 4.6), "dark"), -- roof vent
			box(Vector3.new(7, 0.8, 0.6), Vector3.new(0, 0.4, -7.1), "dark"), -- bumper
		},
		cargo = cargo("van", 14, 6.8, {
			Vector3.new(-1.6, 0, 2.6),
			Vector3.new(1.6, 0, 2.6),
			Vector3.new(-1.6, 0, 5.4),
			Vector3.new(1.6, 0, 5.4),
		}),
		back = rearDoors(6.8, DOOR_SILL, 6.4, 7.0, function(side: number): { Box }
			return {
				box(Vector3.new(2.2, 1.4, 0.06), Vector3.new(-side * 0.25, 1.0, 0.12), "glass"), -- rear windows
				box(Vector3.new(3.35, 0.5, 0.06), Vector3.new(0, -2.075, 0.12), "accent"), -- the stripe goes round
			}
		end),
	},
	-- A box truck: a cab, a gap, a big separate box with a wind deflector over the cab and a bottom rail.
	boxtruck = {
		width = 7.4,
		length = 17,
		wheel = 1.55,
		wheelWidth = 1.25,
		clearance = 1.05,
		seat = Vector3.new(-1.6, 0.5, -4.4),
		passengers = { Vector3.new(1.6, 0.5, -4.4), Vector3.new(0, 0.5, -4.4) },
		roof = 8.2,
		split = 3, -- 4.0: the Freight Hauler's box grows in its middle
		boxes = {
			box(Vector3.new(7.2, 2.4, 2.4), Vector3.new(0, 1.2, -7.3), "body"), -- hood
			box(Vector3.new(7.2, 4.6, 3.4), Vector3.new(0, 2.3, -4.4), "glass"), -- cab
			box(Vector3.new(7.2, 0.8, 3.4), Vector3.new(0, 5.0, -4.4), "body"), -- cab roof
			box(Vector3.new(6.6, 1.4, 1.6), Vector3.new(0, 6.1, -3.9), "body", "deflector"), -- wind deflector
			box(Vector3.new(7.6, 7.6, 10.4), Vector3.new(0, 4.0, 3.0), "body"), -- the box
			box(Vector3.new(7.7, 0.9, 9.8), Vector3.new(0, 1.6, 3.0), "accent"), -- a stripe down the box
			box(Vector3.new(7.8, 0.4, 10.4), Vector3.new(0, 0.2, 3.0), "dark"), -- the bottom rail
			box(Vector3.new(0.3, 7.6, 0.3), Vector3.new(-3.85, 4.0, -2.05), "rail"), -- the box's front corner posts
			box(Vector3.new(0.3, 7.6, 0.3), Vector3.new(3.85, 4.0, -2.05), "rail"),
			box(Vector3.new(7.6, 0.8, 0.6), Vector3.new(0, 0.4, -8.8), "dark", "bumper"), -- bumper
		},
		cargo = cargo("truck", 17, 7.4, {
			Vector3.new(-1.8, 0.4, -0.2),
			Vector3.new(1.8, 0.4, -0.2),
			Vector3.new(-1.8, 0.4, 3.2),
			Vector3.new(1.8, 0.4, 3.2),
			Vector3.new(-1.8, 0.4, 6.4),
			Vector3.new(1.8, 0.4, 6.4),
		}),
		back = rearDoors(7.6, DOOR_SILL, 7.6, 8.2, function(_side: number): { Box }
			return {
				box(Vector3.new(3.7, 0.25, 0.06), Vector3.new(0, 0.2, 0.12), "dark"), -- the latch bar
				box(Vector3.new(3.65, 0.3, 0.06), Vector3.new(0, -3.0, 0.12), "accent"), -- a reflector strip
			}
		end),
	},
	-- An armored van: steel plates on the box, the hood and the nose, bars over the windows (its own: Style.armored).
	armorvan = {
		width = 7.0,
		length = 14.5,
		wheel = 1.45,
		wheelWidth = 1.15,
		clearance = 1.0,
		seat = Vector3.new(-1.5, 0.5, -2.45),
		passengers = { Vector3.new(1.5, 0.5, -2.45), Vector3.new(1.6, 0.5, 0.5) },
		roof = 5.5,
		head = Vector2.new(1.75, -7.3), -- above the ram plate
		armored = true,
		boxes = {
			box(Vector3.new(7.0, 2.2, 2.8), Vector3.new(0, 1.1, -5.85), "body"), -- hood
			box(Vector3.new(7.0, 4.4, 4), Vector3.new(0, 2.2, -2.45), "glass"), -- cabin
			box(Vector3.new(7.0, 0.7, 4), Vector3.new(0, 4.75, -2.45), "body"), -- cabin roof
			box(Vector3.new(7.0, 5.1, 7.7), Vector3.new(0, 2.55, 3.4), "body"), -- cargo box
			box(Vector3.new(7.2, 1.2, 7.4), Vector3.new(0, 1.4, 3.4), "plate"), -- steel plates
			box(Vector3.new(7.2, 1.2, 7.4), Vector3.new(0, 3.7, 3.4), "plate"),
			box(Vector3.new(7.1, 0.25, 2.6), Vector3.new(0, 2.3, -5.85), "plate"), -- on the hood
			box(Vector3.new(7.4, 1.6, 0.6), Vector3.new(0, 0.6, -7.5), "plate"), -- ram plate
			-- Grilles over the windscreen and the side windows.
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(-1.8, 3.3, -4.53), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(0, 3.3, -4.53), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(1.8, 3.3, -4.53), "rail"),
			box(Vector3.new(6.6, 0.16, 0.16), Vector3.new(0, 3.3, -4.53), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(-3.58, 3.3, -3.6), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(-3.58, 3.3, -2.45), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(-3.58, 3.3, -1.3), "rail"),
			box(Vector3.new(0.16, 0.16, 3.4), Vector3.new(-3.58, 3.3, -2.45), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(3.58, 3.3, -3.6), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(3.58, 3.3, -2.45), "rail"),
			box(Vector3.new(0.16, 2.0, 0.16), Vector3.new(3.58, 3.3, -1.3), "rail"),
			box(Vector3.new(0.16, 0.16, 3.4), Vector3.new(3.58, 3.3, -2.45), "rail"),
			box(Vector3.new(7.0, 0.8, 0.6), Vector3.new(0, 0.4, -7.0), "dark"), -- bumper under the plate
		},
		cargo = cargo("van", 14.5, 7.0, { Vector3.new(-1.7, 0, 5.2), Vector3.new(1.7, 0, 5.2), Vector3.new(-1.7, 0, 2.2) }),
		back = rearDoors(7.0, DOOR_SILL, 4.9, 7.25, function(side: number): { Box }
			return {
				box(Vector3.new(3.4, 0.9, 0.08), Vector3.new(0, -1.2, 0.13), "plate"), -- a plate over each door
				box(Vector3.new(1.8, 0.35, 0.06), Vector3.new(-side * 0.3, 1.1, 0.12), "glass"), -- a gun slit
			}
		end),
	},
	-- A rally van: lowered, big wheels under flares, stripes over the top and down the side, a roof spoiler.
	rallyvan = {
		width = 6.6,
		length = 13.2,
		wheel = 1.45,
		wheelWidth = 1.3,
		clearance = 0.6,
		seat = Vector3.new(-1.3, 0.3, -2.0),
		passengers = { Vector3.new(1.3, 0.3, -2.0) },
		roof = 4.3,
		boxes = {
			box(Vector3.new(6.6, 1.6, 2.6), Vector3.new(0, 0.8, -5.3), "body"), -- hood
			box(Vector3.new(6.6, 3.4, 3.8), Vector3.new(0, 1.7, -2.1), "glass"), -- cabin
			box(Vector3.new(6.6, 0.5, 3.8), Vector3.new(0, 3.65, -2.1), "body"), -- cabin roof
			box(Vector3.new(6.6, 3.9, 6.8), Vector3.new(0, 1.95, 3.2), "body"), -- cargo box
			box(Vector3.new(6.68, 0.45, 12.4), Vector3.new(0, 1.1, 0.1), "accent"), -- side stripe
			box(Vector3.new(1.2, 0.05, 2.6), Vector3.new(-0.9, 1.63, -5.3), "accent"), -- stripes over the hood …
			box(Vector3.new(1.2, 0.05, 2.6), Vector3.new(0.9, 1.63, -5.3), "accent"),
			box(Vector3.new(1.2, 0.05, 10.6), Vector3.new(-0.9, 3.93, 1.3), "accent"), -- … and the roof
			box(Vector3.new(1.2, 0.05, 10.6), Vector3.new(0.9, 3.93, 1.3), "accent"),
			box(Vector3.new(6.4, 0.25, 1.2), Vector3.new(0, 4.55, 5.9), "dark"), -- the spoiler on its posts
			box(Vector3.new(0.3, 0.5, 0.3), Vector3.new(-2.6, 4.15, 5.9), "dark"),
			box(Vector3.new(0.3, 0.5, 0.3), Vector3.new(2.6, 4.15, 5.9), "dark"),
			box(Vector3.new(0.5, 0.35, 3.4), Vector3.new(-3.4, 1.3, -4.65), "dark"), -- wheel flares
			box(Vector3.new(0.5, 0.35, 3.4), Vector3.new(3.4, 1.3, -4.65), "dark"),
			box(Vector3.new(0.5, 0.35, 3.4), Vector3.new(-3.4, 1.3, 4.65), "dark"),
			box(Vector3.new(0.5, 0.35, 3.4), Vector3.new(3.4, 1.3, 4.65), "dark"),
			box(Vector3.new(6.8, 0.7, 0.5), Vector3.new(0, 0.35, -6.75), "dark"), -- bumper
		},
		cargo = cargo("van", 13.2, 6.6, { Vector3.new(-1.4, 0, 4.4), Vector3.new(1.4, 0, 4.4) }),
		back = rearDoors(6.6, DOOR_SILL, 3.7, 6.6, function(side: number): { Box }
			return {
				box(Vector3.new(2.1, 0.9, 0.06), Vector3.new(-side * 0.25, 0.6, 0.12), "glass"), -- rear windows
				box(Vector3.new(3.2, 0.45, 0.06), Vector3.new(0, -1.225, 0.12), "accent"), -- the side stripe goes round
			}
		end),
	},
	-- 4.0, the Freight Truck: 9 wide, 30 long, 12 high; 12 slots in three 2 x 2 pallet bays (front to back: a pallet
	-- fills the first free bay, server/Cargo.luau), the floor at dock height, a roll-up door, the pallet jack inside.
	freighttruck = {
		width = 9,
		length = 30,
		wheel = 1.9,
		wheelWidth = 1.3,
		clearance = 1.6,
		seat = Vector3.new(-2.4, 2.2, -12.4),
		passengers = { Vector3.new(2.4, 2.2, -12.4) },
		roof = 9.4,
		dual = true,
		jack = Vector3.new(-3.4, 0.6, 12.8), -- (its grip 2.1 behind: inside the shut roll-up door at 15)
		boxes = freightBoxes(),
		trim = freightTrim(),
		cargo = cargo("truck", 30, 9, {
			Vector3.new(-2.0, 0.6, -6.7),
			Vector3.new(2.0, 0.6, -6.7),
			Vector3.new(-2.0, 0.6, -3.3),
			Vector3.new(2.0, 0.6, -3.3),
			Vector3.new(-2.0, 0.6, 0.9),
			Vector3.new(2.0, 0.6, 0.9),
			Vector3.new(-2.0, 0.6, 4.3),
			Vector3.new(2.0, 0.6, 4.3),
			Vector3.new(-2.0, 0.6, 8.5),
			Vector3.new(2.0, 0.6, 8.5),
			Vector3.new(-2.0, 0.6, 11.9),
			Vector3.new(2.0, 0.6, 11.9),
		}),
		back = rollUpDoor(8.6, 0.6, 8.8, 15.0),
	},
}

local CHASSIS_HEIGHT = 1.2
local FRICTIONLESS = PhysicalProperties.new(0.7, 0, 0, 100, 1)

-- ── 3.5, the stages' looks ─────────────────────────────────────────────────
-- What a stage (Config.Cars stages look) does to its car's style: `drop` takes off the style's boxes and trim with
-- those tags, `boxes` adds solid body boxes (a "body" box is painted like the body), `trim` adds cosmetic ones,
-- `slots` are the cargo slots at this stage (as many as the stage's capacity, so the loading fits: tests/run_tests.py
-- counts them), `roof` a new height for the roof gun (over a high roof). Every look keeps the style's back.
-- 4.0: `stretch` makes the body that many studs longer at the style's split (Style.split, stretchStyle): the rear
-- axle, the back, the rear lights, the slots, the CargoDoor, the TrolleyMount, the seats and doors behind the split move
-- back, the long boxes across it get longer, the chassis and the wheel colliders follow (the car stays centred on its
-- chassis: everything also moves forward by half the stretch). The look's own boxes, trim and slots are placed on the
-- stretched body. `fresh`: a stage that fixed the Rusty Van's faults (no primer door, no dim headlight, no bald tyres,
-- no smoke).

type Look = {
	drop: { string }?,
	boxes: { Box }?,
	trim: { Box }?,
	slots: { Vector3 },
	roof: number?,
	hoodBusy: boolean?,
	stretch: number?,
	fresh: boolean?,
}

-- The lists one after the other in a new list.
local function join(...: { Box }): { Box }
	local list: { Box } = {}
	for _, part in { ... } do
		for _, b in part do
			table.insert(list, b)
		end
	end
	return list
end

-- A ladder standing on the side of a body at x (facing out), centred on z, from `foot` up to `top`.
local function ladder(x: number, z: number, foot: number, top: number): { Box }
	local height = top - foot
	local list = {
		box(Vector3.new(0.14, height, 0.14), Vector3.new(x, foot + height / 2, z - 0.35), "chrome"),
		box(Vector3.new(0.14, height, 0.14), Vector3.new(x, foot + height / 2, z + 0.35), "chrome"),
	}
	for n = 1, math.floor(height / 0.8) do
		table.insert(list, box(Vector3.new(0.12, 0.12, 0.7), Vector3.new(x, foot + n * 0.8 - 0.3, z), "chrome"))
	end
	return list
end

-- Shelves behind the rear doors (seen when they open): boards and uprights on the dark opening at the back face z.
local function shelves(z: number, half: number, rows: { number }): { Box }
	local list: { Box } = {}
	for _, side in { -1, 1 } do
		for _, y in rows do
			table.insert(list, box(Vector3.new(1.2, 0.1, 0.04), Vector3.new(side * (half - 0.75), y, z), "wood"))
		end
		table.insert(list, box(Vector3.new(0.1, rows[#rows] - rows[1] + 0.8, 0.04), Vector3.new(side * (half - 1.4), (rows[1] + rows[#rows]) / 2, z), "wood"))
	end
	return list
end

-- Four mud flaps behind the wheels (y = their middle over the chassis top).
local function mudFlaps(x: number, y: number, front: number, rear: number, kind: string): { Box }
	local list: { Box } = {}
	for _, side in { -1, 1 } do
		for _, z in { front, rear } do
			table.insert(list, box(Vector3.new(1.0, 1.2, 0.1), Vector3.new(side * x, y, z), kind))
		end
	end
	return list
end

-- 4.0, the Old Van's stages. The Patched Van: the rust ground off and primed grey where it was, a plain straight
-- bumper; the cracked windscreen, the grey door, the bald tyres, the dim lamp and the smoke stay.
local VAN_PRIMED: { Box } = {
	box(Vector3.new(0.07, 1.6, 2.6), Vector3.new(-3.325, 1.2, 4.6), "primer"),
	box(Vector3.new(0.07, 0.55, 5.4), Vector3.new(-3.335, 0.3, 2.9), "primer"),
	box(Vector3.new(0.07, 0.55, 5.8), Vector3.new(3.335, 0.3, 3.0), "primer"),
	box(Vector3.new(0.07, 1.2, 1.9), Vector3.new(3.325, 3.6, 2.3), "primer"),
	box(Vector3.new(0.07, 1.0, 1.4), Vector3.new(3.325, 1.2, 6.0), "primer"),
	box(Vector3.new(0.07, 1.0, 1.3), Vector3.new(3.325, 1.1, -5.6), "primer"),
	box(Vector3.new(0.07, 0.8, 1.1), Vector3.new(-3.325, 1.3, -5.0), "primer"),
	box(Vector3.new(2.4, 0.07, 1.5), Vector3.new(1.5, 2.035, -5.4), "primer"),
	box(Vector3.new(2.2, 0.07, 2.4), Vector3.new(-1.3, 5.035, 4.4), "primer"),
}

-- The Work Van (1.5 studs longer: the front half 0.75 forward, the back 0.75 back): clean (no rust, no primer, a new
-- windscreen), a chrome bumper, a step at the back, a ladder up the right side, shelves in the back.
local VAN_WORK_TRIM = join({
	box(Vector3.new(5.0, 0.3, 0.6), Vector3.new(0, 0.2, 7.5), "dark"), -- the rear step
}, ladder(3.55, 0.6, 0.7, 5.3), shelves(7.23, 3.05, { 1.9, 2.9, 3.9 }))
local VAN_CLEAN = { "rust", "primer", "bumper", "crack" }
local function vanBumper(z: number): Box
	return box(Vector3.new(6.9, 0.8, 0.6), Vector3.new(0, 0.4, z), "chrome")
end

-- The box truck's Liftgate Truck: a chrome bumper, the liftgate folded under the back, marker lights on the box (4.0:
-- on a box `by` studs longer: the Freight Hauler's).
local function liftTrim(by: number, shelf: boolean): { Box }
	local front, back = -by / 2, by / 2
	local list = {
		box(Vector3.new(7.0, 0.25, 1.1), Vector3.new(0, -0.25, 8.95 + back), "plate"), -- the liftgate's platform
		box(Vector3.new(0.25, 1.3, 0.25), Vector3.new(-3.3, 0.3, 8.6 + back), "dark"),
		box(Vector3.new(0.25, 1.3, 0.25), Vector3.new(3.3, 0.3, 8.6 + back), "dark"),
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(-3.75, 7.65, -2.0 + front), "amber"), -- marker lights
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(3.75, 7.65, -2.0 + front), "amber"),
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(-3.75, 7.65, 8.0 + back), "amber"),
		box(Vector3.new(0.3, 0.3, 0.3), Vector3.new(3.75, 7.65, 8.0 + back), "amber"),
	}
	if shelf then
		table.insert(list, box(Vector3.new(7.0, 0.12, 0.04), Vector3.new(0, 2.7, 8.28 + back), "wood")) -- the stacked row's shelf
	end
	return list
end
local function truckBumper(z: number): Box
	return box(Vector3.new(7.8, 0.8, 0.6), Vector3.new(0, 0.4, z), "chrome")
end

local LOOKS: { [string]: Look } = {
	-- 4.0: the Patched Van (2 slots, the same body).
	van_patched = {
		drop = { "rust", "bumper" },
		boxes = { box(Vector3.new(6.8, 0.7, 0.5), Vector3.new(0, 0.35, -6.6), "dark") }, -- a plain new bumper, straight
		trim = VAN_PRIMED,
		slots = { Vector3.new(-1.5, 0, 4.6), Vector3.new(1.5, 0, 4.6) },
	},
	-- The Work Van: 1.5 studs longer (4.0), clean, the third slot.
	van_work = {
		drop = VAN_CLEAN,
		fresh = true,
		stretch = 1.5,
		boxes = { vanBumper(-7.4) },
		trim = VAN_WORK_TRIM,
		slots = { Vector3.new(-1.5, 0, 5.35), Vector3.new(1.5, 0, 5.35), Vector3.new(-1.5, 0, 2.0) },
	},
	-- The Long Cargo Van (4.0; 3.5's Cargo Van): 3.5 studs longer than the Rusty Van, a high roof (a roof rack on it, the
	-- gun goes up), a light bar, mud flaps.
	van_cargo = {
		drop = VAN_CLEAN,
		fresh = true,
		stretch = 3.5,
		boxes = { vanBumper(-8.4), box(Vector3.new(6.4, 1.3, 9.8), Vector3.new(0, 5.65, 3.2), "body") }, -- the high roof
		trim = join({
			box(Vector3.new(5.0, 0.3, 0.6), Vector3.new(0, 0.2, 8.5), "dark"), -- the rear step
			-- The roof rack on the high roof: two rails on four legs, four cross bars.
			box(Vector3.new(0.2, 0.2, 7.4), Vector3.new(-2.9, 6.75, 3.6), "dark"),
			box(Vector3.new(0.2, 0.2, 7.4), Vector3.new(2.9, 6.75, 3.6), "dark"),
			box(Vector3.new(0.2, 0.35, 0.2), Vector3.new(-2.9, 6.45, 0.2), "dark"),
			box(Vector3.new(0.2, 0.35, 0.2), Vector3.new(2.9, 6.45, 0.2), "dark"),
			box(Vector3.new(0.2, 0.35, 0.2), Vector3.new(-2.9, 6.45, 7.0), "dark"),
			box(Vector3.new(0.2, 0.35, 0.2), Vector3.new(2.9, 6.45, 7.0), "dark"),
			box(Vector3.new(5.8, 0.15, 0.25), Vector3.new(0, 6.75, 0.3), "dark"),
			box(Vector3.new(5.8, 0.15, 0.25), Vector3.new(0, 6.75, 2.6), "dark"),
			box(Vector3.new(5.8, 0.15, 0.25), Vector3.new(0, 6.75, 4.9), "dark"),
			box(Vector3.new(5.8, 0.15, 0.25), Vector3.new(0, 6.75, 7.2), "dark"),
			-- The light bar on the cabin roof.
			box(Vector3.new(3.4, 0.3, 0.7), Vector3.new(0, 5.15, -4.55), "dark"),
			box(Vector3.new(1.2, 0.3, 0.6), Vector3.new(-1.0, 5.45, -4.55), "amber"),
			box(Vector3.new(1.2, 0.3, 0.6), Vector3.new(1.0, 5.45, -4.55), "amber"),
		}, ladder(3.55, 0.0, 0.7, 6.3), shelves(8.23, 3.05, { 1.9, 2.9, 3.9 }), mudFlaps(2.75, -1.05, -4.9, 7.9, "tyre")),
		slots = { Vector3.new(-1.5, 0, 6.3), Vector3.new(1.5, 0, 6.3), Vector3.new(-1.5, 0, 2.6), Vector3.new(1.5, 0, 2.6) },
		roof = 6.8,
	},
	-- The Express Courier: a body-coloured roof pod behind the gun, a checker stripe down both sides.
	courier_express = {
		boxes = { box(Vector3.new(4.4, 0.8, 3.4), Vector3.new(0, 4.7, 3.9), "body") },
		trim = (function(): { Box }
			local list: { Box } = {}
			for _, side in { -1, 1 } do
				for n = 0, 5 do
					table.insert(list, box(Vector3.new(0.06, 0.5, 0.9), Vector3.new(side * 3.12, 2.75, 0.75 + n * 0.9), if n % 2 == 0 then "dark" else "logo"))
				end
			end
			return list
		end)(),
		slots = { Vector3.new(-1.4, 0, 4.4), Vector3.new(1.4, 0, 4.4), Vector3.new(-1.4, 0, 1.6) },
	},
	-- The Tall Hauler: a ladder rack on the roof with a spare wheel, side steps, a stacked shelf in the back.
	highroof_hauler = {
		trim = {
			box(Vector3.new(0.2, 0.2, 4.8), Vector3.new(-3.0, 7.15, 4.2), "dark"),
			box(Vector3.new(0.2, 0.2, 4.8), Vector3.new(3.0, 7.15, 4.2), "dark"),
			box(Vector3.new(0.2, 0.45, 0.2), Vector3.new(-3.0, 6.82, 2.0), "dark"),
			box(Vector3.new(0.2, 0.45, 0.2), Vector3.new(3.0, 6.82, 2.0), "dark"),
			box(Vector3.new(0.2, 0.45, 0.2), Vector3.new(-3.0, 6.82, 6.4), "dark"),
			box(Vector3.new(0.2, 0.45, 0.2), Vector3.new(3.0, 6.82, 6.4), "dark"),
			box(Vector3.new(6.0, 0.15, 0.25), Vector3.new(0, 7.15, 2.0), "dark"),
			box(Vector3.new(6.0, 0.15, 0.25), Vector3.new(0, 7.15, 4.2), "dark"),
			box(Vector3.new(6.0, 0.15, 0.25), Vector3.new(0, 7.15, 6.4), "dark"),
			box(Vector3.new(2.2, 0.6, 2.2), Vector3.new(0, 7.55, 4.9), "tyre"), -- the spare wheel
			box(Vector3.new(1.0, 0.64, 1.0), Vector3.new(0, 7.55, 4.9), "chrome"),
			box(Vector3.new(0.5, 0.2, 2.8), Vector3.new(-3.6, -0.15, -2.4), "dark"), -- side steps
			box(Vector3.new(0.5, 0.2, 2.8), Vector3.new(3.6, -0.15, -2.4), "dark"),
			box(Vector3.new(6.0, 0.12, 0.04), Vector3.new(0, 2.3, 7.08), "wood"), -- the stacked shelf
		},
		slots = { Vector3.new(-1.6, 0, 2.6), Vector3.new(1.6, 0, 2.6), Vector3.new(-1.6, 0, 5.4), Vector3.new(1.6, 0, 5.4), Vector3.new(-1.6, 2.3, 5.4) },
	},
	-- The Ranch Pickup: a roll bar behind the cab with two spotlights, chrome rails on the bed.
	pickup_ranch = {
		trim = {
			box(Vector3.new(0.25, 4.2, 0.25), Vector3.new(-2.8, 2.1, 1.7), "dark"),
			box(Vector3.new(0.25, 4.2, 0.25), Vector3.new(2.8, 2.1, 1.7), "dark"),
			box(Vector3.new(5.85, 0.25, 0.25), Vector3.new(0, 4.2, 1.7), "dark"),
			box(Vector3.new(0.7, 0.5, 0.35), Vector3.new(-1.6, 4.55, 1.7), "lamp"),
			box(Vector3.new(0.7, 0.5, 0.35), Vector3.new(1.6, 4.55, 1.7), "lamp"),
			box(Vector3.new(0.2, 0.2, 5.0), Vector3.new(-3.0, 1.75, 3.9), "chrome"),
			box(Vector3.new(0.2, 0.2, 5.0), Vector3.new(3.0, 1.75, 3.9), "chrome"),
		},
		slots = { Vector3.new(-1.4, 0, 5.1), Vector3.new(1.4, 0, 5.1), Vector3.new(0, 0, 3.6) },
	},
	boxtruck_lift = {
		drop = { "bumper" },
		boxes = { truckBumper(-8.8) },
		trim = liftTrim(0, true),
		slots = {
			Vector3.new(-1.8, 0.4, -0.2),
			Vector3.new(1.8, 0.4, -0.2),
			Vector3.new(-1.8, 0.4, 3.2),
			Vector3.new(1.8, 0.4, 3.2),
			Vector3.new(-1.8, 0.4, 6.4),
			Vector3.new(1.8, 0.4, 6.4),
			Vector3.new(-1.8, 2.8, 6.4), -- the stacked row
		},
	},
	-- The Freight Hauler: the Liftgate Truck with a box 3 studs longer (4.0: four rows on the floor, the front 2 x 2 takes
	-- a pallet: StageDef.pallets), a tall wind deflector over the cab and side skirts.
	boxtruck_freight = {
		drop = { "bumper", "deflector" },
		stretch = 3,
		boxes = { truckBumper(-10.3), box(Vector3.new(6.8, 2.2, 2.0), Vector3.new(0, 6.5, -5.4), "body") },
		trim = join(liftTrim(3, false), {
			box(Vector3.new(0.15, 1.1, 9.0), Vector3.new(-3.85, -0.35, 0), "dark"),
			box(Vector3.new(0.15, 1.1, 9.0), Vector3.new(3.85, -0.35, 0), "dark"),
		}),
		slots = {
			Vector3.new(-1.8, 0.4, -1.6),
			Vector3.new(1.8, 0.4, -1.6),
			Vector3.new(-1.8, 0.4, 1.8),
			Vector3.new(1.8, 0.4, 1.8),
			Vector3.new(-1.8, 0.4, 5.2),
			Vector3.new(1.8, 0.4, 5.2),
			Vector3.new(-1.8, 0.4, 8.4),
			Vector3.new(1.8, 0.4, 8.4),
		},
	},
	-- The Street Machine: a blower through the hood (no scoop from the Engine upgrade), side pipes, a wider trunk.
	muscle_street = {
		trim = {
			box(Vector3.new(1.4, 0.7, 1.4), Vector3.new(0, 1.75, -4.6), "rail"),
			box(Vector3.new(1.6, 0.35, 0.9), Vector3.new(0, 2.27, -4.6), "chrome"),
			box(Vector3.new(0.3, 0.3, 4.5), Vector3.new(-3.35, 0.15, -0.6), "chrome"),
			box(Vector3.new(0.3, 0.3, 4.5), Vector3.new(3.35, 0.15, -0.6), "chrome"),
		},
		slots = { Vector3.new(-1.2, 0.3, 5), Vector3.new(1.2, 0.3, 5) },
		hoodBusy = true,
	},
	-- The Fortress Van: a shield round the roof gun, lockers on the sides, a spare wheel on the roof.
	armorvan_fortress = {
		trim = {
			box(Vector3.new(3.2, 1.1, 0.2), Vector3.new(0, 5.75, -0.9), "plate"),
			box(Vector3.new(0.2, 0.9, 2.2), Vector3.new(-1.75, 5.65, 0.4), "plate"),
			box(Vector3.new(0.2, 0.9, 2.2), Vector3.new(1.75, 5.65, 0.4), "plate"),
			box(Vector3.new(0.25, 1.0, 2.6), Vector3.new(-3.72, 2.55, 4.8), "rail"),
			box(Vector3.new(0.25, 1.0, 2.6), Vector3.new(3.72, 2.55, 4.8), "rail"),
			box(Vector3.new(2.2, 0.55, 2.2), Vector3.new(0, 5.38, 5.7), "tyre"),
			box(Vector3.new(1.0, 0.57, 1.0), Vector3.new(0, 5.38, 5.7), "chrome"),
		},
		slots = { Vector3.new(-1.7, 0, 5.2), Vector3.new(1.7, 0, 5.2), Vector3.new(-1.7, 0, 2.2), Vector3.new(1.7, 0, 2.2) },
	},
	-- The Works Rally: a light pod over the windscreen, a roof scoop, mud flaps (cosmetic: no more room).
	rally_works = {
		trim = join({
			box(Vector3.new(3.8, 0.35, 0.5), Vector3.new(0, 4.1, -3.6), "dark"),
			box(Vector3.new(0.7, 0.7, 0.2), Vector3.new(-1.4, 4.15, -3.9), "lamp"),
			box(Vector3.new(0.7, 0.7, 0.2), Vector3.new(-0.47, 4.15, -3.9), "lamp"),
			box(Vector3.new(0.7, 0.7, 0.2), Vector3.new(0.47, 4.15, -3.9), "lamp"),
			box(Vector3.new(0.7, 0.7, 0.2), Vector3.new(1.4, 4.15, -3.9), "lamp"),
			box(Vector3.new(1.4, 0.45, 1.6), Vector3.new(0, 4.12, -1.4), "dark"),
		}, mudFlaps(2.6, -0.95, -3.05, 6.2, "accent")),
		slots = { Vector3.new(-1.4, 0, 4.4), Vector3.new(1.4, 0, 4.4) },
	},
}

-- 4.0: a style `by` studs longer at its split (Style.split): a z behind the split moves back by `by`, then everything
-- moves forward by by / 2 (the car stays centred on its chassis, both axles move out by by / 2); a box at least 3 long
-- across the split gets longer instead, a shorter one moves with its centre.
local function stretchStyle(style: Style, by: number): Style
	local split = style.split or 0
	local function z(v: number): number
		return v + (if v > split then by else 0) - by / 2
	end
	local function point(p: Vector3): Vector3
		return Vector3.new(p.X, p.Y, z(p.Z))
	end
	local function moved(b: Box): Box
		local z0, z1 = b.offset.Z - b.size.Z / 2, b.offset.Z + b.size.Z / 2
		if b.size.Z >= 3 and z0 < split and z1 > split then
			return box(b.size + Vector3.new(0, 0, by), b.offset, b.kind, b.tag, b.tilt)
		end
		return box(b.size, point(b.offset), b.kind, b.tag, b.tilt)
	end
	local function boxes(list: { Box }?): { Box }
		local out: { Box } = {}
		local from: { Box } = list or {}
		for _, b in from do
			table.insert(out, moved(b))
		end
		return out
	end
	local out = table.clone(style)
	out.length = style.length + by
	out.boxes = boxes(style.boxes)
	out.trim = boxes(style.trim)
	out.seat = point(style.seat)
	local passengers: { Vector3 } = {}
	for _, p in style.passengers do
		table.insert(passengers, point(p))
	end
	out.passengers = passengers
	local head = style.head
	if head then
		out.head = Vector2.new(head.X, z(head.Y))
	end
	local rideDoor = style.rideDoor
	if rideDoor then
		out.rideDoor = z(rideDoor)
	end
	local jack = style.jack
	if jack then
		out.jack = point(jack)
	end
	local slots: { Vector3 } = {}
	for _, slot in style.cargo.slots do
		table.insert(slots, point(slot))
	end
	out.cargo = { slots = slots, noun = style.cargo.noun, door = point(style.cargo.door), entry = point(style.cargo.entry) }
	local back = style.back
	if back then
		local leaves: { Leaf } = {}
		for _, leaf in back.leaves do
			local copy = table.clone(leaf)
			copy.center = point(leaf.center)
			copy.hinge = point(leaf.hinge)
			table.insert(leaves, copy)
		end
		local hole = back.hole
		out.back = { noun = back.noun, leaves = leaves, hole = if hole then moved(hole) else nil }
	end
	return out
end

-- The style of a car at a stage: its STYLES body with the stage's look on it (cached per look, so a stage's doors,
-- doorsOf, are cached per look too), the plain style for stage 0, a car without stages or a look that is missing.
-- 4.0: the look's stretch first (stretchStyle), then its own boxes, trim and slots on the stretched body.
local lookStyles: { [string]: Style } = {}
local function styleFor(def: Config.CarDef, stage: number?): Style
	local base = STYLES[def.style] or STYLES.van
	local stageDef = Economy.stageDef(def.id, math.clamp(stage or 0, 0, Economy.maxStage(def.id)))
	local lookId = stageDef and stageDef.look
	local look = if lookId then LOOKS[lookId] else nil
	if not lookId or not look then
		return base
	end
	local cached = lookStyles[lookId]
	if cached then
		return cached
	end
	local dropped: { [string]: boolean } = {}
	local tags: { string } = look.drop or {}
	for _, tag in tags do
		dropped[tag] = true
	end
	local function keep(list: { Box }?): { Box }
		local out: { Box } = {}
		local from: { Box } = list or {}
		for _, b in from do
			if not (b.tag and dropped[b.tag]) then
				table.insert(out, b)
			end
		end
		return out
	end
	local style = table.clone(base)
	style.boxes = keep(base.boxes)
	style.trim = keep(base.trim)
	local stretch = look.stretch
	if stretch and stretch > 0 then
		style = stretchStyle(style, stretch)
	end
	style.boxes = join(style.boxes, look.boxes or {})
	style.trim = join(style.trim or {}, look.trim or {})
	style.cargo = { slots = look.slots, noun = style.cargo.noun, door = style.cargo.door, entry = style.cargo.entry }
	style.roof = look.roof or base.roof
	style.hoodBusy = look.hoodBusy or base.hoodBusy
	if look.fresh then
		style.primerDoor = nil
		style.dimHead = nil
		style.bald = nil
		style.smoky = nil
	end
	lookStyles[lookId] = style
	return style
end

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

-- 3.1: a paint job's finish on the painted body panels (PaintDef.material: Neon, Foil, Metal, Glass …), else the
-- body's own SmoothPlastic. Only the panels in paintParts take it (never the windows, the trim or the lights). A
-- neon paint glows by itself, so its colour is toned down to stay a glow and not a floodlight in the dark.
local BODY_MATERIAL = Enum.Material.SmoothPlastic
local function applyPaint(parts: { BasePart }, def: Config.CarDef, paintId: string?)
	local color = paintColor(def, paintId)
	local paint = paintId and Economy.findPaint(paintId)
	local material = BODY_MATERIAL
	if paint and paint.material then
		local ok, found = pcall(function()
			return (Enum.Material :: any)[paint.material]
		end)
		if ok and typeof(found) == "EnumItem" then
			material = found :: Enum.Material
		end
	end
	if material == Enum.Material.Neon then
		color = color:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	for _, p in parts do
		p.Color = color
		p.Material = material
		-- Glass: a dark, glossy, still solid shell (the Phantom), never see-through.
		p.Reflectance = if material == Enum.Material.Glass then 0.25 elseif material == Enum.Material.Foil then 0.1 else 0
	end
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

-- The colour and the material of a Box kind on a car painted `color` (its accent colour: `accent`).
local function boxLook(kind: string, color: Color3, accent: Color3): (Color3, Enum.Material)
	if kind == "dark" or kind == "lightbar" then
		return DARK, Enum.Material.Metal
	elseif kind == "glass" then
		return GLASS, Enum.Material.Glass
	elseif kind == "accent" then
		return accent, Enum.Material.SmoothPlastic
	elseif kind == "plate" then
		return color:Lerp(DARK, 0.5), Enum.Material.DiamondPlate
	elseif kind == "white" then
		return Color3.fromRGB(220, 180, 120), Enum.Material.SmoothPlastic
	elseif kind == "ball" then
		return Color3.fromRGB(255, 150, 200), Enum.Material.SmoothPlastic
	elseif kind == "logo" then
		return Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic
	elseif kind == "wood" then
		return Color3.fromRGB(128, 92, 58), Enum.Material.WoodPlanks
	elseif kind == "rail" then
		return Color3.fromRGB(70, 72, 76), Enum.Material.Metal
	elseif kind == "cross" then
		return Color3.fromRGB(205, 30, 34), Enum.Material.SmoothPlastic
	elseif kind == "hole" then
		return Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic
	elseif kind == "amber" then
		return Color3.fromRGB(255, 168, 36), Enum.Material.Glass
	elseif kind == "rust" then
		return Color3.fromRGB(146, 80, 38), Enum.Material.CorrodedMetal -- 4.0: orange-brown, corroded
	elseif kind == "primer" then
		return Color3.fromRGB(146, 146, 138), Enum.Material.SmoothPlastic
	elseif kind == "chrome" then
		return Color3.fromRGB(196, 198, 204), Enum.Material.Metal
	elseif kind == "lamp" then
		return Color3.fromRGB(255, 244, 214), Enum.Material.Glass
	elseif kind == "tyre" then
		return Color3.fromRGB(24, 24, 24), Enum.Material.Rubber
	elseif kind == "crack" then
		return Color3.fromRGB(46, 50, 54), Enum.Material.SmoothPlastic
	elseif SIREN_DIM[kind] then
		return SIREN_DIM[kind], Enum.Material.SmoothPlastic
	end
	return color, Enum.Material.SmoothPlastic
end

-- A cosmetic part of the car (no mass, no collisions, not hit by rays), welded to `to` (nil: not welded).
local function trimPart(model: Model, name: string, b: Box, at: CFrame, to: BasePart?, color: Color3, accent: Color3): Part
	local c, material = boxLook(b.kind, color, accent)
	local p = newPart(model, name, b.size, at, c, material)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if b.kind == "glass" then
		p.Transparency = 0.45
	end
	if to then
		weld(to, p)
	end
	return p
end

-- 3.2: the back that opens (Style.back): every leaf with its trim, the dark opening behind. working (a player's car):
-- each leaf hangs on a Motor6D "BackHinge" that the clients turn (client/CarVisuals.luau), else it is welded shut.
-- The body-coloured leaves join paintParts.
local function buildBack(model: Model, chassis: Part, top: CFrame, back: Back, working: boolean, color: Color3, accent: Color3, paintParts: { BasePart })
	if back.hole then
		local hole = trimPart(model, "BackHole", back.hole, top * CFrame.new(back.hole.offset), chassis, color, accent)
		if model:GetAttribute("FleetArt") then hole.Transparency = 1 end
	end
	for _, leaf in back.leaves do
		local kind = leaf.kind or "body"
		local p = trimPart(model, "BackDoor", box(leaf.size, leaf.center, kind), top * CFrame.new(leaf.center), if working then nil else chassis, color, accent)
		if kind == "body" then
			table.insert(paintParts, p)
		end
		if model:GetAttribute("FleetArt") and back.noun == "doors" then
			VehicleArt.rear(p, color, paintParts, { weld = weld, nightLight = DayNight.nightLight })
		end
		local trim: { Box } = leaf.trim or {}
		for _, b in trim do
			local t = trimPart(model, "BackTrim", b, top * CFrame.new(leaf.center + b.offset), p, color, accent)
			if b.kind == "body" then
				table.insert(paintParts, t)
			end
		end
		if working then
			-- Hinged, not welded: Part1 = chassis * C0 * Transform * C1:Inverse(), closed with no Transform.
			local hinge = Instance.new("Motor6D")
			hinge.Name = "BackHinge"
			hinge.Part0 = chassis
			hinge.Part1 = p
			hinge.C0 = CFrame.new(Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + leaf.hinge)
			hinge.C1 = CFrame.new(leaf.hinge - leaf.center)
			hinge:SetAttribute("Axis", leaf.axis)
			hinge:SetAttribute("Angle", leaf.angle)
			hinge.Parent = chassis
		end
	end
end

-- The Open / Close text of the back's prompt.
local function backAction(noun: string, open: boolean): string
	if noun == "ramp" then
		return if open then "Raise ramp" else "Lower ramp"
	end
	return `{if open then "Close" else "Open"} {noun}`
end

-- ── The upgrades you can see (3.3) ─────────────────────────────────────────
-- The "UpgradeKit" folder in a player's car: a bull bar (Ram Plow), side plates and window grilles (Armor), a hood
-- scoop and twin pipes (Engine). Fitted to every style from its boxes: the front end, the hood, the first window.

local KIT_STEEL = Color3.fromRGB(56, 58, 62)
local KIT_PLATE = Color3.fromRGB(108, 112, 118)
local KIT_CHROME = Color3.fromRGB(196, 198, 204)

type Hull = {
	front: number, -- z of the front end (the bumper, the ram plate)
	hoodTop: number, -- the hood's top (y over the chassis top)
	hoodZ: number, -- where the scoop goes (z)
	hoodLen: number,
	hood: boolean, -- false: no hood to put a scoop on (the bus)
	glass: Box?, -- the frontmost window box (the windscreen and the front side windows)
}

-- Is the point inside one of the style's glass boxes?
local function inGlass(style: Style, point: Vector3): boolean
	for _, b in style.boxes do
		if b.kind == "glass" then
			local d = point - b.offset
			if math.abs(d.X) < b.size.X / 2 and math.abs(d.Y) < b.size.Y / 2 and math.abs(d.Z) < b.size.Z / 2 then
				return true
			end
		end
	end
	return false
end

local function hullOf(style: Style): Hull
	local front = -style.length / 2
	local hoodBox: Box? = nil
	local glass: Box? = nil
	for _, b in style.boxes do
		local edge = b.offset.Z - b.size.Z / 2
		front = math.min(front, edge)
		if b.kind == "body" and (hoodBox == nil or edge < (hoodBox :: Box).offset.Z - (hoodBox :: Box).size.Z / 2 - 0.01) then
			hoodBox = b
		end
		if b.kind == "glass" and (glass == nil or edge < (glass :: Box).offset.Z - (glass :: Box).size.Z / 2) then
			glass = b
		end
	end
	local hull: Hull = { front = front, hoodTop = 2, hoodZ = front + 2, hoodLen = 2, hood = false, glass = glass }
	local h = hoodBox
	if h then
		local edge = h.offset.Z - h.size.Z / 2
		hull.hoodTop = h.offset.Y + h.size.Y / 2
		hull.hoodLen = math.min(h.size.Z, 4)
		hull.hoodZ = if h.size.Z <= 6 then h.offset.Z else edge + 2.6 -- a long body (the muscle car): the front part
		hull.hood = not inGlass(style, Vector3.new(0, hull.hoodTop + 0.3, hull.hoodZ))
	end
	return hull
end

-- The levels the kit shows, as a key (rebuilt only when it changes). 4.0: the tyres and the Hand Trolley too.
local function kitKey(levels: Economy.Upgrades): string
	local tracks = `{Economy.level(levels, "plow")}/{Economy.level(levels, "armor")}/{Economy.level(levels, "engine")}`
	return `{tracks}/{Economy.level(levels, "handling")}/{Economy.level(levels, "trolley")}`
end

-- 4.0, Tyres & Suspension 5: the body sits this much lower over its wheels (a new stance builds the car again).
local STANCE = 0.25
local function stanceOf(levels: Economy.Upgrades): number
	return if Economy.level(levels, "handling") >= 5 then STANCE else 0
end

-- 4.0: where the folded Hand Trolley stands (the Attachment TrolleyMount, relative to the chassis top centre): on the
-- cargo floor (the lowest slot), against the right wall, just inside the back.
local function trolleySpot(style: Style): Vector3
	local floor = math.huge
	for _, slot in style.cargo.slots do
		floor = math.min(floor, slot.Y)
	end
	return Vector3.new(style.width / 2 - 0.9, if floor == math.huge then 0 else floor, style.cargo.door.Z - 1.5)
end

local KIT_TYRE = Color3.fromRGB(22, 22, 24)
local KIT_TREAD = Color3.fromRGB(64, 64, 66)
local KIT_ALLOY = Color3.fromRGB(206, 210, 216)
local KIT_TROLLEY = Color3.fromRGB(196, 46, 38)

-- 4.0, Tyres & Suspension on every tyre of the car: from level 1 new black tyres with a tread ring (two grooves round
-- the tread), from 3 alloy rims (a silver disc, silver spokes); before, a Rusty Van's tyres stay bald and grey (build).
-- The new parts are welded to the tyre (they spin with it) and live in the kit's folder.
local function fitTyres(model: Model, folder: Instance, style: Style, handling: number)
	if model:GetAttribute("FleetArt") then
		VehicleArt.fitTyres(model, handling, { weld = weld, nightLight = DayNight.nightLight })
		return
	end
	for _, tyre in model:GetChildren() do
		if not tyre:IsA("BasePart") or tyre.Name ~= "Tyre" then
			continue
		end
		local width, diameter = tyre.Size.X, tyre.Size.Y
		local function piece(name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material, cylinder: boolean)
			local p = newPart(model, name, size, tyre.CFrame * at, color, material)
			if cylinder then
				p.Shape = Enum.PartType.Cylinder
			end
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Parent = folder
			weld(tyre :: BasePart, p)
			return p
		end
		tyre.Color = if handling >= 1 then KIT_TYRE elseif style.bald then BALD else Color3.fromRGB(24, 24, 24)
		if handling >= 1 then
			for _, side in { -1, 1 } do
				piece("TreadRing", Vector3.new(0.1, diameter + 0.05, diameter + 0.05), CFrame.new(side * width * 0.22, 0, 0), KIT_TREAD, Enum.Material.Rubber, true)
			end
		end
		local spoke: Instance? = nil
		for _, d in model:GetChildren() do
			if d.Name == "Spoke" and d:IsA("BasePart") and (d.Position - tyre.Position).Magnitude < 0.05 then
				spoke = d
			end
		end
		if spoke and spoke:IsA("BasePart") then
			spoke.Color = if handling >= 3 then KIT_ALLOY:Lerp(DARK, 0.3) else Color3.fromRGB(90, 90, 90)
		end
		if handling >= 3 then
			local rim = piece("AlloyRim", Vector3.new(width + 0.11, diameter * 0.72, diameter * 0.72), CFrame.identity, KIT_ALLOY, Enum.Material.Metal, true)
			rim.Reflectance = 0.15
			piece("AlloySpoke", Vector3.new(width + 0.16, 0.35, diameter * 0.7), CFrame.identity, KIT_ALLOY:Lerp(DARK, 0.3), Enum.Material.Metal, false)
		end
	end
end

-- (Re)builds the kit of a player's car (carId) for these car-track levels.
local function buildKit(model: Model, chassis: Part, style: Style, levels: Economy.Upgrades, carId: string)
	local old = model:FindFirstChild("UpgradeKit")
	if old then
		old:Destroy()
	end
	local oldMount = chassis:FindFirstChild("TrolleyMount")
	if oldMount then
		oldMount:Destroy()
	end
	local plow = Economy.level(levels, "plow")
	local armor = Economy.level(levels, "armor")
	local engine = Economy.level(levels, "engine")
	-- 4.0: the Rusty Van smokes until the Engine's first level (client/CarVisuals.luau puffs it at the Exhaust).
	model:SetAttribute("Smoky", style.smoky == true and engine < 1)
	local folder = Instance.new("Folder")
	folder.Name = "UpgradeKit"
	fitTyres(model, folder, style, Economy.level(levels, "handling"))
	local top = chassis.CFrame * CFrame.new(0, CHASSIS_HEIGHT / 2, 0)
	local function add(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material, cylinder: boolean?): Part
		local frame = top * CFrame.new(at)
		local p = newPart(model, name, size, if cylinder then frame * ALONG_Z else frame, color, material)
		if cylinder then
			p.Shape = Enum.PartType.Cylinder
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = folder
		weld(chassis, p)
		return p
	end
	local hull = hullOf(style)

	if model:GetAttribute("FleetArt") then
		VehicleArt.upgrades(model, chassis, style :: any, folder, plow, armor, engine, { weld = weld, nightLight = DayNight.nightLight })
	else
	-- Ram Plow: a bull bar in front of the nose, wider, thicker and lower-reaching with every level.
	if plow >= 1 then
		local width = math.min(style.width + 0.2, style.width - 1.6 + 0.36 * plow)
		local thick = 0.2 + 0.05 * plow
		local h = math.clamp(hull.hoodTop, 1.5, 2.6)
		local z = hull.front - 0.35 - 0.05 * plow
		for _, side in { -1, 1 } do
			add("BullBarPost", Vector3.new(thick, h + 1.0, thick), Vector3.new(side * (width / 2 - 0.6), (h - 1.0) / 2, z), KIT_STEEL, Enum.Material.Metal)
		end
		add("BullBar", Vector3.new(width, thick, thick), Vector3.new(0, h - thick / 2, z), KIT_STEEL, Enum.Material.Metal)
		add("BullBar", Vector3.new(width, thick, thick), Vector3.new(0, h * 0.35, z), KIT_STEEL, Enum.Material.Metal)
		if plow >= 3 then
			add("PlowBlade", Vector3.new(width + 0.2, 0.8, 0.25), Vector3.new(0, -0.6, z - 0.15), KIT_PLATE, Enum.Material.DiamondPlate)
		end
		if plow >= 5 then
			for _, side in { -1, 1 } do
				add("PlowPad", Vector3.new(1.2, 0.8, 0.3), Vector3.new(side * (width / 2 - 0.6), h * 0.55, z - 0.25), Color3.fromRGB(24, 24, 24), Enum.Material.Rubber)
			end
		end
	end

	-- Armor: plates along both sides between the wheels (taller with the level), grilles over the first windows from 3.
	if armor >= 1 and not style.armored then
		local wz = style.length / 2 - style.wheel - 0.5
		local z0, z1 = -wz + style.wheel + 0.25, wz - style.wheel - 0.25
		-- Up to the waist of the body (a little over the hood), taller with the level.
		local y0 = 0.3
		local y1 = math.min(y0 + 1.4 + 0.15 * armor, math.max(hull.hoodTop + 0.4, 1.8))
		local height = y1 - y0
		if z1 - z0 >= 2 then
			-- Outside everything already on the sides there.
			local half = style.width / 2
			for _, b in style.boxes do
				local by0, by1 = b.offset.Y - b.size.Y / 2, b.offset.Y + b.size.Y / 2
				local bz0, bz1 = b.offset.Z - b.size.Z / 2, b.offset.Z + b.size.Z / 2
				if b.kind ~= "hole" and by1 > y0 and by0 < y1 and bz1 > z0 and bz0 < z1 then
					half = math.max(half, math.abs(b.offset.X) + b.size.X / 2)
				end
			end
			for _, side in { -1, 1 } do
				add("ArmorPlate", Vector3.new(0.15, height, z1 - z0), Vector3.new(side * (half + 0.08), (y0 + y1) / 2, (z0 + z1) / 2), KIT_PLATE, Enum.Material.DiamondPlate)
				if armor >= 4 then
					add("ArmorRim", Vector3.new(0.22, 0.22, z1 - z0), Vector3.new(side * (half + 0.12), y1 - 0.11, (z0 + z1) / 2), KIT_STEEL, Enum.Material.Metal)
				end
			end
		end
		local g = hull.glass
		if armor >= 3 and g then
			local gTop = g.offset.Y + g.size.Y / 2
			local gFront = g.offset.Z - g.size.Z / 2
			local yTop = gTop - 0.25
			local yBottom = math.max(g.offset.Y - g.size.Y / 2 + 0.2, gTop - 2.2, if hull.hood then hull.hoodTop + 0.1 else -math.huge)
			local band = yTop - yBottom
			if band >= 0.6 then
				local y = (yTop + yBottom) / 2
				-- The windscreen: three bars and a cross bar.
				for _, f in { -0.25, 0, 0.25 } do
					add("Grille", Vector3.new(0.14, band, 0.14), Vector3.new(f * g.size.X, y, gFront - 0.08), KIT_STEEL, Enum.Material.Metal)
				end
				add("Grille", Vector3.new(g.size.X - 0.4, 0.14, 0.14), Vector3.new(0, y, gFront - 0.08), KIT_STEEL, Enum.Material.Metal)
				-- The front side windows: two bars and a cross bar on each side.
				local span = math.min(g.size.Z, 4.4) - 0.6
				for _, side in { -1, 1 } do
					local x = side * (g.size.X / 2 + 0.08)
					for _, f in { 0.3, 0.7 } do
						add("Grille", Vector3.new(0.14, band, 0.14), Vector3.new(x, y, gFront + 0.3 + span * f), KIT_STEEL, Enum.Material.Metal)
					end
					add("Grille", Vector3.new(0.14, 0.14, span), Vector3.new(x, y, gFront + 0.3 + span / 2), KIT_STEEL, Enum.Material.Metal)
				end
			end
		end
	end

	-- Engine from 3: a scoop on the hood (taller at 5) and two exhaust pipes under the back.
	if engine >= 3 then
		if hull.hood and not style.hoodBusy then
			local tall = 0.45 + 0.1 * (engine - 3)
			local length = math.min(hull.hoodLen * 0.55, 2.2)
			add("HoodScoop", Vector3.new(2.2, tall, length), Vector3.new(0, hull.hoodTop + tall / 2, hull.hoodZ), KIT_STEEL, Enum.Material.Metal)
			add("ScoopIntake", Vector3.new(1.8, tall * 0.6, 0.06), Vector3.new(0, hull.hoodTop + tall / 2, hull.hoodZ - length / 2 - 0.03), Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic)
		end
		-- (Not under a horse ramp: it folds down over the back end.)
		local back = style.back
		if not (back and back.noun == "ramp") then
			for _, side in { -1, 1 } do
				add("Exhaust", Vector3.new(1.0, 0.42, 0.42), Vector3.new(side * (style.width / 2 - 1.3), -0.75, style.length / 2 + 0.3), KIT_CHROME, Enum.Material.Metal, true)
			end
		end
	end

	end -- stock company vehicle kit

	-- 4.0, the Hand Trolley: folded upright against the right wall just inside the back (seen when the back opens), its
	-- Attachment TrolleyMount on the chassis at its foot (the chassis' axes). server/Cargo.luau builds the trolley you
	-- push at the mount and may hide this folded one (the model "FoldedTrolley" in the kit) while it is out.
	if Economy.hasTrolley(carId, levels) then
		local spot = trolleySpot(style)
		local mount = Instance.new("Attachment")
		mount.Name = "TrolleyMount"
		mount.Position = Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + spot
		mount.Parent = chassis
		local trolley = Instance.new("Model")
		trolley.Name = "FoldedTrolley"
		trolley.Parent = folder
		local function bar(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material, cylinder: boolean?)
			add(name, size, spot + at, color, material, cylinder).Parent = trolley
		end
		for _, z in { -0.5, 0.5 } do
			bar("TrolleyRail", Vector3.new(0.12, 3.0, 0.12), Vector3.new(0, 1.6, z), KIT_TROLLEY, Enum.Material.Metal)
			bar("TrolleyWheel", Vector3.new(0.25, 0.7, 0.7), Vector3.new(0.12, 0.35, z * 1.15), Color3.fromRGB(24, 24, 24), Enum.Material.Rubber, true)
		end
		bar("TrolleyHandle", Vector3.new(0.12, 0.12, 1.12), Vector3.new(0, 3.1, 0), KIT_TROLLEY, Enum.Material.Metal)
		bar("TrolleyBar", Vector3.new(0.1, 0.1, 1.0), Vector3.new(0, 1.7, 0), KIT_TROLLEY, Enum.Material.Metal)
		bar("TrolleyNose", Vector3.new(0.08, 0.7, 1.1), Vector3.new(-0.14, 0.45, 0), KIT_PLATE, Enum.Material.DiamondPlate)
	end

	folder.Parent = model
end

-- ── 3.7, the doors ─────────────────────────────────────────────────────────
-- You get in at a door, not anywhere round the car: the driver's door on the left (every style seats the driver on
-- the left, -X; the front is -Z), the front passenger's on the right, a seat further back (a pickup's or a monster
-- truck's bed, the army truck's roof gunners, a van's jump seat) at its own side, and the bus's passengers all through
-- its folding door at the front right (Style.rideDoor). Seats side by side at one door share it (the box truck's
-- middle seat). A door of the cabin has a panel that swings open (a hinged, massless, non-colliding part painted like
-- the body, over the lower half of the cabin's side glass: the window shows above it); the others only a prompt.
-- Each door has an Attachment "Door{n}" on the chassis just outside it with the prompt in it: the DrivePrompt at the
-- driver's door, a RidePrompt at every passenger door (the attribute Door = n; its seats carry the same attribute).
-- The prompts reach only Config.Cargo.DoorReach, so on the passenger side the driver's E never shows.

export type CarDoor = {
	side: number, -- -1 left, 1 right
	z: number, -- the middle of the door along the car (also where you step out)
	driver: boolean,
	seats: { number }, -- the passenger seats (Style.passengers / Car.passengers indices) behind it; none at the driver's
	outside: number, -- the outer face of the body there (|x|, relative to the chassis centre line)
	promptY: number, -- the prompt's height over the chassis top
	panel: Box?, -- the door panel (relative to the chassis top centre, closed); nil: no panel, only the prompt
	hinge: Vector3?, -- the panel's front outer edge, where it turns out
	trim: { Box }, -- on the panel: offsets from its centre
}

local DOOR_THICK = 0.1
local DOOR_FRONT, DOOR_BACK = 1.3, 1.2 -- the panel reaches this far before and behind the seat's middle
local DOOR_SOLID: { [string]: boolean } = { body = true, glass = true, plate = true } -- the shell a door sits on
local DOOR_STRIPES: { [string]: boolean } = { accent = true, dark = true, logo = true } -- side stripes go on over it

local doorCache: { [Style]: { CarDoor } } = setmetatable({}, { __mode = "k" }) :: any

-- The highest point of the wheels between z0 and z1 (over the chassis top), -inf when no wheel is there.
local function wheelTop(style: Style, z0: number, z1: number): number
	local wz = style.length / 2 - style.wheel - 0.5
	local centreY = style.wheel - style.clearance - CHASSIS_HEIGHT
	local top = -math.huge
	for _, wheelZ in { -wz, wz } do
		local d = math.abs(math.clamp(wheelZ, z0, z1) - wheelZ)
		if d < style.wheel then
			top = math.max(top, centreY + math.sqrt(style.wheel * style.wheel - d * d))
		end
	end
	return top
end

-- The style's doors (cached per style; a stage's look is a style of its own).
local function doorsOf(style: Style): { CarDoor }
	local cached = doorCache[style]
	if cached then
		return cached
	end
	local hull = hullOf(style)
	local list: { CarDoor } = {}
	local function add(side: number, z: number, driver: boolean, cabin: boolean): CarDoor
		local front, back = z - DOOR_FRONT, z + DOOR_BACK
		-- Over the wheel arch, up to the waist (the hood's top; the bus's lower body); a monster truck's door sits high
		-- over its tyres.
		local bottom = math.max(0.1, wheelTop(style, front, back) + 0.05)
		local top = math.max(math.min(hull.hoodTop, 3) + 0.05, bottom + 1.2)
		-- On the outside of the shell there (the cabin, a bed wall, a plate; not the frame of a monster truck).
		local outside = 0
		for _, b in style.boxes do
			local y0, y1 = b.offset.Y - b.size.Y / 2, b.offset.Y + b.size.Y / 2
			local z0, z1 = b.offset.Z - b.size.Z / 2, b.offset.Z + b.size.Z / 2
			if DOOR_SOLID[b.kind] and y1 > bottom and y0 < top and z1 > front and z0 < back then
				outside = math.max(outside, side * b.offset.X + b.size.X / 2)
			end
		end
		outside = if outside > 0 then outside else style.width / 2
		local door: CarDoor = {
			side = side,
			z = z,
			driver = driver,
			seats = {},
			outside = outside,
			promptY = math.max(0.4, 3 - style.clearance - CHASSIS_HEIGHT),
			panel = nil,
			hinge = nil,
			trim = {},
		}
		if cabin then
			local height, length = top - bottom, back - front
			local centre = Vector3.new(side * (outside + DOOR_THICK / 2), (bottom + top) / 2, (front + back) / 2)
			door.panel = box(Vector3.new(DOOR_THICK, height, length), centre, "body")
			door.hinge = Vector3.new(side * (outside + DOOR_THICK), centre.Y, front)
			-- The handle near the back edge, under the window.
			table.insert(door.trim, box(Vector3.new(0.1, 0.16, 0.55), Vector3.new(side * (DOOR_THICK / 2 + 0.05), height / 2 - 0.45, length / 2 - 0.55), "dark"))
			-- A stripe round the body (as wide as the car) goes on over the door.
			for _, b in style.boxes do
				local y0, y1 = math.max(bottom, b.offset.Y - b.size.Y / 2), math.min(top, b.offset.Y + b.size.Y / 2)
				local z0, z1 = math.max(front, b.offset.Z - b.size.Z / 2), math.min(back, b.offset.Z + b.size.Z / 2)
				if DOOR_STRIPES[b.kind] and b.size.X >= style.width - 0.5 and y1 - y0 > 0.05 and z1 - z0 > 0.05 then
					local at = Vector3.new(side * (DOOR_THICK / 2 + 0.02), (y0 + y1) / 2 - centre.Y, (z0 + z1) / 2 - centre.Z)
					table.insert(door.trim, box(Vector3.new(0.04, y1 - y0, z1 - z0), at, b.kind))
				end
			end
			if driver or #list == 1 then
				local extra: { Box } = style.doorTrim or {}
				for _, b in extra do
					table.insert(door.trim, box(b.size, Vector3.new(side * b.offset.X, b.offset.Y, b.offset.Z), b.kind))
				end
			end
		end
		table.insert(list, door)
		return door
	end
	add(if style.seat.X > 0 then 1 else -1, style.seat.Z, true, true)
	for index, position in style.passengers do
		local side = if style.rideDoor then 1 elseif position.X < -0.3 then -1 else 1
		local z = style.rideDoor or position.Z
		local found: CarDoor? = nil
		for _, door in list do
			if not door.driver and door.side == side and math.abs(door.z - z) < 1.2 then
				found = door
				break
			end
		end
		local door = found or add(side, z, false, style.rideDoor ~= nil or inGlass(style, position + Vector3.new(0, 1.6, 0)))
		table.insert(door.seats, index)
	end
	doorCache[style] = list
	return list
end

-- The door panels: hinged on a player's car (Motor6D "DoorHinge", the attributes Axis, Angle and Door; the clients
-- swing it open from its attribute DoorOpenAt to DoorCloseAt, server times: client/CarVisuals.luau), else welded shut.
local function buildDoors(model: Model, chassis: Part, top: CFrame, style: Style, working: boolean, color: Color3, accent: Color3, paintParts: { BasePart })
	for index, door in doorsOf(style) do
		local panel, hingeAt = door.panel, door.hinge
		if not panel or not hingeAt then
			continue
		end
		-- 4.0: the Rusty Van's door from another van, in grey primer (never painted).
		local primer = style.primerDoor == index
		local p = trimPart(model, "CarDoor", if primer then box(panel.size, panel.offset, "primer") else panel, top * CFrame.new(panel.offset), if working then nil else chassis, color, accent)
		if not primer then
			table.insert(paintParts, p)
		end
		if model:GetAttribute("FleetArt") then
			VehicleArt.door(model, p, style :: any, door.side, color, paintParts, primer, { weld = weld, nightLight = DayNight.nightLight })
		end
		for _, b in door.trim do
			local t = trimPart(model, "DoorTrim", b, top * CFrame.new(panel.offset + b.offset), p, color, accent)
			if b.kind == "body" then
				table.insert(paintParts, t)
			end
		end
		if working then
			local hinge = Instance.new("Motor6D")
			hinge.Name = "DoorHinge"
			hinge.Part0 = chassis
			hinge.Part1 = p
			hinge.C0 = CFrame.new(Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + hingeAt)
			hinge.C1 = CFrame.new(hingeAt - panel.offset)
			hinge:SetAttribute("Axis", "Y")
			hinge:SetAttribute("Angle", door.side * Config.Cargo.DoorSwing) -- out to its side, the back edge first
			hinge:SetAttribute("Door", index)
			hinge.Parent = chassis
		end
	end
end

-- Builds the body. display = a showroom model (anchored, no seats, no movers). gunId = the car gun on its roof (nil:
-- none). oneBeam: only one headlight carries a SpotLight (the NPC cars: cheaper). stage (3.5): the car's stage, its
-- look (styleFor; nil: stage 0). lower (4.0, Tyres & Suspension 5): the body sits this much lower over its wheels.
local function build(def: Config.CarDef, color: Color3, ground: CFrame, display: boolean, gunId: string?, oneBeam: boolean?, stage: number?, lower: number?): Built
	local style = styleFor(def, stage)
	local accent = if def.style == "icecream"
		then Color3.fromRGB(255, 120, 180)
		elseif def.style == "bus" or def.style == "ambulance" or def.style == "boxtruck" then Color3.fromRGB(205, 30, 34)
		else color:Lerp(Color3.new(1, 1, 1), 0.45)

	local model = Instance.new("Model")
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local chassisY = style.clearance - (lower or 0) + CHASSIS_HEIGHT / 2
	local chassisCF = ground * CFrame.new(0, chassisY, 0)
	local chassis = newPart(model, "Chassis", Vector3.new(style.width - 0.4, CHASSIS_HEIGHT, style.length), chassisCF, DARK, Enum.Material.Metal)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2, 0, 0, 100, 1)
	model.PrimaryPart = chassis

	local polished = not oneBeam and VehicleArt.supports(def.style)
	if polished then
		chassis.Transparency = 1
		model:SetAttribute("FleetArt", true)
		model:SetAttribute("FleetStyle", def.style)
		model:SetAttribute("FleetStage", stage or 0)
	end
	local paintParts: { BasePart } = {}
	local top = chassisCF * CFrame.new(0, CHASSIS_HEIGHT / 2, 0)
	local height = CHASSIS_HEIGHT
	for _, b in style.boxes do
		local c, material = boxLook(b.kind, color, accent)
		local name = if b.kind == "glass" then "Cabin" elseif b.kind == "lightbar" then "LightBar" elseif SIREN_DIM[b.kind] then "SirenLens" else "Body"
		local p = newPart(model, name, b.size, top * CFrame.new(b.offset) * tilted(b), c, material)
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
		-- Keep the original massless collision/raycast hull; the panelled skin supplies its appearance.
		if polished then p.Transparency = 1 end
		weld(chassis, p)
		height = math.max(height, CHASSIS_HEIGHT + b.offset.Y + b.size.Y / 2)
	end
	-- 3.5: the cosmetic trim (the Rusty Van's rust, a stage's ladder, racks, lamps …); body-coloured trim is painted.
	local trim: { Box } = if polished then {} else style.trim or {}
	for _, b in trim do
		local p = trimPart(model, "Trim", b, top * CFrame.new(b.offset) * tilted(b), chassis, color, accent)
		if b.kind == "body" then
			table.insert(paintParts, p)
		end
	end

	if polished then
		VehicleArt.body(model, chassis, top, style :: any, color, paintParts, { weld = weld, nightLight = DayNight.nightLight })
	end

	-- 3.2: the back that opens: hinged on a player's car, welded shut on a showroom model or an NPC car (oneBeam).
	if style.back then
		buildBack(model, chassis, top, style.back, not display and not oneBeam, color, accent, paintParts)
	end
	-- 3.7: the cabin doors: hinged on a player's car, welded shut on a showroom model or an NPC car.
	buildDoors(model, chassis, top, style, not display and not oneBeam, color, accent, paintParts)

	-- Wheels: an invisible welded frictionless collider (the car slides on it) and a visible tyre on a Motor6D. 4.0: bald
	-- grey tyres on the Rusty Van (Style.bald; the UpgradeKit's Tyres & Suspension puts new ones on), a twin tyre inside
	-- each rear one (Style.dual: no collider of its own).
	local wheelY = style.wheel - chassisY
	local wx = style.width / 2 - style.wheelWidth / 2 + 0.3
	local wz = style.length / 2 - style.wheel - 0.5
	local tyreColor = if style.bald then BALD else Color3.fromRGB(24, 24, 24)
	local function wheel(offset: Vector3, collides: boolean)
		if collides then
			local collider = newPart(model, "WheelCollider", Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2), chassisCF * CFrame.new(offset), DARK, Enum.Material.Rubber)
			collider.Shape = Enum.PartType.Cylinder
			collider.Transparency = 1
			collider.CustomPhysicalProperties = FRICTIONLESS
			weld(chassis, collider)
		end
		local tyre = newPart(model, "Tyre", Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2), chassisCF * CFrame.new(offset), tyreColor, Enum.Material.Rubber)
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
		if polished then
			VehicleArt.wheel(tyre, 0, { weld = weld, nightLight = DayNight.nightLight })
			return
		end
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
	for _, offset in { Vector3.new(-wx, wheelY, -wz), Vector3.new(wx, wheelY, -wz), Vector3.new(-wx, wheelY, wz), Vector3.new(wx, wheelY, wz) } do
		wheel(offset, true)
	end
	if style.dual then
		local inner = wx - style.wheelWidth - 0.12
		wheel(Vector3.new(-inner, wheelY, wz), false)
		wheel(Vector3.new(inner, wheelY, wz), false)
	end

	-- Lights: they glow at night (DayNight switches them); the headlights throw a beam.
	local front = -style.length / 2
	local headY = if style.head then style.head.X else 1.2
	local headZ = if style.head then style.head.Y else front - 0.05
	for n, x in { -style.width / 2 + 1, style.width / 2 - 1 } do
		-- 4.0: the Rusty Van's right lamp is yellowed and dim (Style.dimHead).
		local yellowed = style.dimHead == true and n == 2
		local head = newPart(model, "Headlight", Vector3.new(1.2, 0.6, 0.2), top * CFrame.new(x, headY, headZ), if yellowed then DIM_HEAD_DIM else HEAD_DIM, Enum.Material.Glass)
		head.CanCollide = false
		head.CanQuery = false
		head.Massless = true
		weld(chassis, head)
		if not display and (n == 1 or not oneBeam) then
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = if oneBeam then 50 elseif yellowed then 34 else 60
			spot.Angle = if oneBeam then 70 else 55
			spot.Brightness = if oneBeam then 3.4 elseif yellowed then 1.4 else 4
			spot.Color = if yellowed then Color3.fromRGB(255, 214, 140) else Color3.fromRGB(255, 240, 210)
			spot.Shadows = false
			spot.Parent = head
		end
		if yellowed then
			DayNight.nightLight(head, DIM_HEAD_LIT, DIM_HEAD_DIM, "Glass")
		else
			DayNight.nightLight(head, HEAD_LIT, HEAD_DIM, "Glass")
		end
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

	-- The driver's seat (only the owner may sit in it, see watchSeats) and the passenger seats. Nobody sits down by
	-- touching one (CanTouch off): only through a door's prompt (3.7) and Seat:Sit.
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
	seat:SetAttribute("Door", 1)
	seat.Parent = model
	weld(chassis, seat)
	built.seat = seat
	local doors = doorsOf(style)
	local doorOf: { [number]: number } = {}
	for index, door in doors do
		for _, n in door.seats do
			doorOf[n] = index
		end
	end
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
		p:SetAttribute("Door", doorOf[n] or 1)
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
	-- 4.0: where the exhaust smokes (client/CarVisuals.luau, while the car's attribute Smoky is on) and, on the Freight
	-- Truck, where its pallet jack stands inside the back (server/Cargo.luau builds the jack at JackMount).
	local exhaust = Instance.new("Attachment")
	exhaust.Name = "Exhaust"
	exhaust.Position = Vector3.new(-(style.width / 2 - 1.3), CHASSIS_HEIGHT / 2 - 0.75, style.length / 2 + 0.35)
	exhaust.Parent = chassis
	local jack = style.jack
	if jack then
		local mount = Instance.new("Attachment")
		mount.Name = "JackMount"
		mount.Position = Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + jack
		mount.Parent = chassis
	end
	-- 3.2: the prompt that opens and closes the back (a player's car only: the NPC cars lose every prompt).
	if style.back and not oneBeam then
		local backPrompt = Instance.new("ProximityPrompt")
		backPrompt.Name = "BackPrompt"
		backPrompt.ActionText = backAction(style.back.noun, false)
		backPrompt.ObjectText = def.name
		backPrompt.HoldDuration = Config.Cargo.HoldDuration
		backPrompt.MaxActivationDistance = 9
		backPrompt.RequiresLineOfSight = false
		backPrompt.KeyboardKeyCode = Enum.KeyCode.E
		backPrompt.Parent = door
		model:SetAttribute("BackOpen", false)
	end

	-- Prompts, 3.7 one at every door (doorsOf): the owner drives (the driver's door), everybody else rides along (a
	-- passenger door with a free seat); the clients show only the ones that fit them (client/CarVisuals.luau).
	for index, carDoor in doors do
		local at = Instance.new("Attachment")
		at.Name = `Door{index}`
		at.Position = Vector3.new(carDoor.side * (carDoor.outside + Config.Cargo.DoorStandOut), CHASSIS_HEIGHT / 2 + carDoor.promptY, carDoor.z)
		at.Parent = chassis
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = if carDoor.driver then "DrivePrompt" else "RidePrompt"
		prompt.ActionText = if carDoor.driver then "Drive" else "Ride along"
		prompt.ObjectText = def.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = if carDoor.driver then Config.Cargo.DriverDoorReach
			elseif carDoor.panel == nil then Config.Cargo.SeatReach
			else Config.Cargo.DoorReach
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt:SetAttribute("Door", index)
		prompt.Parent = at
	end
	return built
end

-- A showroom model for the dealer (anchored, no seats); 3.5: at a stage (its look).
function Vehicles.displayModel(def: Config.CarDef, ground: CFrame, stage: number?, levels: Economy.Upgrades?): Model
	local built = build(def, rgb(def.color), ground, true, nil, nil, stage)
	if levels then
		buildKit(built.model, built.chassis, styleFor(def, stage), levels, def.id)
		for _, p in built.model:GetDescendants() do
			if p:IsA("BasePart") then p.Anchored = true; p.CollisionGroup = "Default" end
		end
	end
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
-- like an NPC car; anchor it to step it by CFrame. Its parts are in the "Car" collision group. 3.5: at a stage (its
-- look; the traffic picks one at random).
function Vehicles.buildTraffic(def: Config.CarDef, ground: CFrame, color: Color3?, stage: number?): TrafficCar
	local built = build(def, color or rgb(def.color), ground, false, nil, true, stage)
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
	local pushing = player.Character and player.Character:GetAttribute("Pushing")
	local loaded = player.Character ~= nil and player.Character:GetAttribute("CarryCount") ~= nil -- (pieces on the trolley)
	Net.get("Notice"):FireClient(player, if pushing == "trolley" and loaded then "Load them first (E at the back) or set the trolley down (G)."
		elseif pushing == "trolley" then "Stow the trolley first (G at the open back) or set it down (G)."
		elseif pushing == "jack" then "Set the pallet jack down first (G)."
		elseif held == "horse" then "Load the horse first (E at the back of the truck)."
		else "Load it first (E at the back of the vehicle).")
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

-- 3.10: a cabin door's opening, in server times (the clients swing it: client/CarVisuals.luau); two people at one door
-- share it (it shuts after the later one). A door without a panel (a bed, the roof) has nothing to swing.
local function swingDoor(car: Car, index: number, openAt: number, closeAt: number)
	local now = workspace:GetServerTimeNow()
	for _, child in car.chassis:GetChildren() do
		if child.Name == "DoorHinge" and child:GetAttribute("Door") == index then
			local oldOpen, oldClose = child:GetAttribute("DoorOpenAt"), child:GetAttribute("DoorCloseAt")
			local a, b = Boarding.mergeDoor(if type(oldOpen) == "number" then oldOpen else nil, if type(oldClose) == "number" then oldClose else nil, openAt, closeAt, now)
			child:SetAttribute("DoorOpenAt", a)
			child:SetAttribute("DoorCloseAt", b)
		end
	end
end

-- 3.10, getting in (see the top): who is on the way into which seat. A reserved seat takes nobody else meanwhile.
type Boarder = { car: Car, seat: Seat | VehicleSeat, door: number, humanoid: Humanoid, character: Model, at: number }
local boarders: { [Player]: Boarder } = {}
local reserved: { [Instance]: Player } = {}

local function seatFree(seat: Seat | VehicleSeat): boolean
	return seat.Occupant == nil and not reserved[seat]
end

local function endBoarding(player: Player, b: Boarder)
	if boarders[player] == b then
		boarders[player] = nil
	end
	if reserved[b.seat] == player then
		reserved[b.seat] = nil
		b.seat:SetAttribute("Reserved", nil)
	end
end

local function clearBoardAttributes(character: Model)
	character:SetAttribute("Boarding", nil)
	character:SetAttribute("BoardAt", nil)
	character:SetAttribute("BoardReach", nil)
end

-- Getting in did not work out (the car left, a death, a wreck…): the seat is free again, the door shuts, the
-- player's client stands them at the door and gives the controls back (the attributes are gone).
local function cancelBoarding(player: Player, b: Boarder)
	endBoarding(player, b)
	clearBoardAttributes(b.character)
	if b.humanoid.Parent then
		b.humanoid.PlatformStand = false
	end
	if not b.car.wrecked and b.car.chassis.Parent then
		local now = workspace:GetServerTimeNow()
		for _, child in b.car.chassis:GetChildren() do
			if child.Name == "DoorHinge" and child:GetAttribute("Door") == b.door then
				child:SetAttribute("DoorCloseAt", now)
			end
		end
	end
end

-- The move is over: into the seat (the door shuts from now: its DoorCloseAt). The attributes stay a moment, so the
-- client sees the seat before they go.
local function finishBoarding(player: Player, b: Boarder)
	-- 4.0: something in the hands by now (a piece, a trolley taken on the way in): no seat, the move is cancelled
	-- (handsFull says why).
	if handsFull(player) then
		cancelBoarding(player, b)
		return
	end
	endBoarding(player, b)
	b.humanoid.PlatformStand = false
	local seat = b.seat
	if seat:IsA("VehicleSeat") then
		seat:Sit(b.humanoid)
	elseif seat:IsA("Seat") then
		seat:Sit(b.humanoid)
	end
	local at = b.at
	task.delay(1, function()
		if b.character:GetAttribute("BoardAt") == at then
			clearBoardAttributes(b.character)
		end
	end)
end

-- The E at a door, checked: the seat is reserved and the move starts (the player's client plays it).
local function startBoarding(player: Player, car: Car, seat: Seat | VehicleSeat, index: number, humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local cfg = Config.Cargo
	local now = workspace:GetServerTimeNow()
	local door = car.doors[index]
	local panel = door ~= nil and door.panel ~= nil
	local seatNo = 0
	if seat ~= car.seat then
		local n = seat:GetAttribute("Index")
		seatNo = if type(n) == "number" then n else 1
	end
	reserved[seat] = player
	seat:SetAttribute("Reserved", player.UserId)
	boarders[player] = { car = car, seat = seat, door = index, humanoid = humanoid, character = character, at = now }
	character:SetAttribute("BoardAt", now)
	character:SetAttribute("BoardReach", panel)
	character:SetAttribute("Boarding", Boarding.encode(car.owner.UserId, index, seatNo))
	humanoid.PlatformStand = true -- (the client does it at once too; it goes off again at the seat or on a cancel)
	if panel then
		-- Open as the hand reaches the handle, shut as they sit.
		swingDoor(car, index, now + cfg.BoardStepSeconds * 0.7, now + cfg.BoardSeconds)
	end
end

-- Every frame: a move still fine goes on, and into the seat at its time; anything wrong cancels it.
local function stepBoarding()
	if next(boarders) == nil then
		return
	end
	local cfg = Config.Cargo
	local now = workspace:GetServerTimeNow()
	for player, b in boarders do
		local car = b.car
		local root = b.humanoid.RootPart
		local fine = player.Parent ~= nil and player.Character == b.character and b.humanoid.Health > 0
			and b.humanoid.SeatPart == nil and root ~= nil and not car.wrecked and car.chassis.Parent ~= nil
			and cars[car.owner] == car and not car.chauffeured and b.seat.Parent ~= nil and b.seat.Occupant == nil
			and Vehicles.speed(car) <= cfg.BoardMaxSpeed and (b.seat == car.seat or not car.repairing)
		if not fine or not root then
			cancelBoarding(player, b)
		elseif now >= b.at + cfg.BoardSeconds then
			if (root.Position - b.seat.Position).Magnitude <= cfg.BoardRange then
				finishBoarding(player, b)
			else
				cancelBoarding(player, b)
			end
		end
	end
end

-- Whoever gets out slides out at their own door (3.10: their client plays it, client/CarBoarding.luau; the door opens
-- at once and shuts behind them). Still over the car a moment later (no client move: a lag, a failed start), they are
-- put out next to it at their door, not left inside the cabin.
local function watchSeat(car: Car, seat: Seat | VehicleSeat, index: number, driver: boolean)
	local door = car.doors[index] or car.doors[1]
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
		if not left or not character or not character:IsA("Model") or left.Health <= 0 then
			return
		end
		local cfg = Config.Cargo
		local now = workspace:GetServerTimeNow()
		character:SetAttribute("AlightAt", now)
		character:SetAttribute("AlightReach", door.panel ~= nil)
		if not car.wrecked and door.panel then
			swingDoor(car, index, now, now + cfg.AlightSeconds + 0.05)
		end
		task.delay(cfg.AlightSeconds + 0.4, function()
			if character:GetAttribute("AlightAt") == now then
				character:SetAttribute("AlightAt", nil)
				character:SetAttribute("AlightReach", nil)
			end
			local root = left.RootPart
			local player = Players:GetPlayerFromCharacter(character)
			if not root or not character.Parent or not car.chassis.Parent or left.SeatPart or left.Health <= 0 or (player and boarders[player]) then
				return
			end
			local frame = car.chassis.CFrame
			local rel = frame:PointToObjectSpace(root.Position)
			if Boarding.inside(rel.X, rel.Z, car.size.X / 2, car.size.Z / 2) and math.abs(rel.Y) < car.size.Y + 2 then
				character:PivotTo(frame * CFrame.new(door.side * (car.size.X / 2 + 3), 2, door.z))
			end
		end)
	end)
end

-- 3.7: is the player standing at this door (the prompt's reach, and a little slack for the lag)?
local function atDoor(car: Car, index: number, humanoid: Humanoid): boolean
	local at = car.chassis:FindFirstChild(`Door{index}`)
	local root = humanoid.RootPart
	if not at or not at:IsA("Attachment") or not root then
		return false
	end
	local prompt = at:FindFirstChildOfClass("ProximityPrompt")
	local reach = if prompt then prompt.MaxActivationDistance else Config.Cargo.DoorReach
	return (root.Position - at.WorldPosition).Magnitude <= reach + 6
end

-- 3.7: the prompts at the doors: the driver's door seats the owner, a passenger door the next free seat behind it;
-- 3.10: through the move (startBoarding), not at once, and only while the car stands.
local function watchPrompts(car: Car)
	local function humanoidOf(player: Player): Humanoid?
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return if humanoid and humanoid.Health > 0 then humanoid else nil
	end
	for index, door in car.doors do
		local at = car.chassis:FindFirstChild(`Door{index}`)
		local prompt = at and at:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			continue
		end
		if door.driver then
			prompt.Triggered:Connect(function(player)
				-- 3.2: not with the back open (it must be closed before the car goes anywhere).
				if player == car.owner and Vehicles.backOpen(car) then
					Net.get("Notice"):FireClient(player, `Close the back first: {Vehicles.backVerb(car, false)} (E at the back).`)
					return
				end
				local humanoid = humanoidOf(player)
				if player == car.owner and not car.wrecked and not car.chauffeured and seatFree(car.seat) and humanoid and not humanoid.SeatPart
					and not boarders[player] and atDoor(car, index, humanoid) and not handsFull(player)
					and Vehicles.speed(car) <= Config.Cargo.BoardMaxSpeed then
					-- 3.4: back in a car on the lift of a repair bay: the repair is cancelled (server/Repair.luau).
					if car.repairing then
						Vehicles.beforeDrive(player, car)
						Vehicles.setRepairing(car, false) -- (in case nobody was running it)
					end
					startBoarding(player, car, car.seat, index, humanoid)
				end
			end)
		else
			prompt.Triggered:Connect(function(player)
				local humanoid = humanoidOf(player)
				if player == car.owner or car.wrecked or car.chauffeured or car.repairing or not humanoid or humanoid.SeatPart or boarders[player] then
					return
				end
				if not atDoor(car, index, humanoid) or handsFull(player) then
					return
				end
				if Vehicles.speed(car) > Config.Cargo.BoardMaxSpeed then
					Net.get("Notice"):FireClient(player, "Wait for the car to stop.")
					return
				end
				for _, n in door.seats do
					local seat = car.passengers[n]
					if seat and seatFree(seat) then
						startBoarding(player, car, seat, index, humanoid)
						return
					end
				end
				Net.get("Notice"):FireClient(player, "No free seat at this door.")
			end)
		end
	end
end

-- 3.10: E in a seat (the CarDoor remote, client/CarBoarding.luau): out of the seat; watchSeat opens the door and the
-- client slides out. Space still does the same through the Humanoid's own jump.
local lastOut: { [Player]: number } = {}
local function onCarDoor(player: Player, action: any)
	if action ~= "out" then
		return
	end
	local now = os.clock()
	if lastOut[player] and now - lastOut[player] < 0.3 then
		return
	end
	lastOut[player] = now
	local car, _, seatPart = Vehicles.seatedIn(player)
	if not car or not seatPart or not (seatPart:IsA("Seat") or seatPart:IsA("VehicleSeat")) then
		return
	end
	local seatWeld = seatPart:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end
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

-- 4.2: the speed a ram may count. The driver's client owns the car's physics, so a hacked velocity must not kill
-- everything in one touch: never more than the car's top speed with room for a downhill run.
function Vehicles.ramSpeed(car: Car): number
	return math.min(Vehicles.speed(car), car.stats.maxSpeed * 1.7 + 10) -- (nitro is +60%)
end

-- ── Cargo (server/Cargo.luau) ───────────────────────────────────────────────

local function styleOf(car: Car): Style
	local def = Economy.findCar(car.id)
	return if def then styleFor(def, car.stage) else STYLES.van
end

-- Where the loaded pieces ride, relative to the chassis: the bottom centre of a piece, facing the front.
-- 3.5: the slots of the car's stage (its look's: as many as Economy.capacity counts).
function Vehicles.cargoSlots(car: Car): { CFrame }
	local list = {}
	for _, slot in styleOf(car).cargo.slots do
		table.insert(list, CFrame.new(Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + slot))
	end
	return list
end

-- 3.4: how many pieces the car takes at once (3.5: at its stage).
function Vehicles.capacity(car: Car): number
	return Economy.capacity(car.id, { stage = car.stage })
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

-- ── The back that opens (3.2) ──────────────────────────────────────────────

-- Set by server/Cargo.luau: may this player (not the owner) open and close the back of this car (the job's crew)?
Vehicles.backAllowed = function(_player: Player, _car: Car): boolean
	return false
end
-- Set by server/Cargo.luau: the back of this car was opened or closed (the job's prompts and hints follow).
Vehicles.backChanged = function(_car: Car) end

-- The prompt that opens and closes the back; nil: no back (the bus) or wrecked (the prompts burnt).
function Vehicles.backPrompt(car: Car): ProximityPrompt?
	local door = Vehicles.cargoDoor(car)
	local prompt = door and door:FindFirstChild("BackPrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- Has this car a back that opens (doors, a tailgate, a trunk, a ramp)?
function Vehicles.hasBack(car: Car): boolean
	return not car.wrecked and Vehicles.backPrompt(car) ~= nil
end

function Vehicles.backOpen(car: Car): boolean
	return car.model:GetAttribute("BackOpen") == true
end

-- What the back is: doors | tailgate | trunk | ramp ("" without one).
function Vehicles.backNoun(car: Car): string
	local back = styleOf(car).back
	return if back then back.noun else ""
end

-- "open the back doors", "close the tailgate", "lower the ramp" … (opening: the way it goes now).
function Vehicles.backVerb(car: Car, opening: boolean): string
	local noun = Vehicles.backNoun(car)
	if noun == "ramp" then
		return if opening then "lower the ramp" else "raise the ramp"
	end
	return `{if opening then "open" else "close"} the {if noun == "doors" then "back doors" else noun}`
end

-- Opens or closes the back (the clients swing it, client/CarVisuals.luau). Nothing happens without a back.
function Vehicles.setBack(car: Car, open: boolean)
	if not Vehicles.hasBack(car) or Vehicles.backOpen(car) == open then
		return
	end
	car.model:SetAttribute("BackOpen", open)
	local prompt = Vehicles.backPrompt(car)
	if prompt then
		prompt.ActionText = backAction(Vehicles.backNoun(car), open)
	end
	Vehicles.backChanged(car)
end

-- The BackPrompt pressed: open or close it. On foot, a hand free (3.7: empty hands, or one light piece in them:
-- the character attribute CarryHands = 1 from server/Cargo.luau), the car standing; the owner or the job's crew.
local function toggleBack(car: Car, player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if car.wrecked or car.chauffeured or not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local notice = Net.get("Notice")
	if humanoid.SeatPart then
		notice:FireClient(player, "Get out first.")
		return
	end
	if player ~= car.owner and not Vehicles.backAllowed(player, car) then
		notice:FireClient(player, "This is not your car.")
		return
	end
	local open = Vehicles.backOpen(car)
	local held = carrying(character)
	if held and (held == "horse" or character:GetAttribute("CarryHands") ~= 1) then
		local verb = Vehicles.backVerb(car, not open)
		local count = character:GetAttribute("CarryCount")
		if held == "horse" then
			notice:FireClient(player, `Your hands are full. Let the horse go (G), then {verb} (E).`)
		elseif type(count) == "number" and count >= 2 then
			notice:FireClient(player, `Hands full: put a piece down with G, then {verb} (E). Or a crew mate opens it for you.`)
		else
			notice:FireClient(player, `Your hands are full. Put it down (G), then {verb} (E).`)
		end
		return
	end
	if Vehicles.speed(car) > Config.Cargo.MaxCarSpeed then
		notice:FireClient(player, "Stop the vehicle first.")
		return
	end
	Vehicles.setBack(car, not open)
	-- Somebody waits at the wheel: they cannot drive until it is closed again.
	local driver = car.seat.Occupant
	local other = driver and Players:GetPlayerFromCharacter(driver.Parent)
	if not open and other and other ~= player then
		notice:FireClient(other, `{player.DisplayName} opened the back: you can't drive until it is closed.`)
	end
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

-- 3.4: keeps the car's share of health in the profile (profile.carHealth, saved): it comes back as damaged as it
-- went. Not a lent company vehicle (it goes back to its employer).
local function remember(car: Car)
	if car.lent then
		return
	end
	local profile = PlayerData.get(car.owner)
	if profile then
		profile.carHealth[car.id] = math.clamp(car.health / math.max(1, car.stats.health), 0, 1)
	end
end

-- 3.4, set by server/Repair.luau: the owner gets back into a car on the lift (the repair is cancelled).
Vehicles.beforeDrive = function(_player: Player, _car: Car) end

-- 3.4: a car on the lift of a repair bay: anchored where it stands (nobody pushes or drives it, its passengers step
-- out and nobody rides along until it is done) and marked for the clients (the attribute Repairing); off again, the
-- owner's client drives it as before.
function Vehicles.setRepairing(car: Car, on: boolean)
	if car.repairing == on or car.wrecked or not car.chassis.Parent then
		car.repairing = on
		return
	end
	car.repairing = on
	car.model:SetAttribute("Repairing", on)
	car.chassis.AssemblyLinearVelocity = Vector3.zero
	car.chassis.AssemblyAngularVelocity = Vector3.zero
	car.chassis.Anchored = on
	if on then
		for _, seat in car.passengers do
			eject(seat) -- the SeatWeld goes too: nobody stays in a car on the lift
		end
	else
		pcall(function()
			car.chassis:SetNetworkOwner(if car.chauffeured then nil else car.owner)
		end)
	end
end

-- The player's car leaves the world (a new one, a garage, leaving the game): parked as it is (its damage kept).
function Vehicles.remove(player: Player)
	local car = cars[player]
	if car then
		cars[player] = nil
		if not car.wrecked then
			remember(car)
		end
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

	-- 3.3: this car's own car-track levels (a company vehicle has none).
	local levels = Economy.carLevels(profile.carUpgrades, def.id)
	local stats = Economy.carStats(def.id, levels)
	-- 3.4: your own car comes as damaged as it was parked (profile.carHealth); a lent company vehicle comes fresh.
	local lent = carId ~= nil and def.company == true and carId ~= profile.car
	local share = if lent then 1 else math.clamp(profile.carHealth[def.id] or 1, 0.05, 1)
	local gunId = gunFor(player, def.id)
	local paintId = if def.company then nil else profile.carPaint[def.id]
	local stage = if def.company then 0 else Economy.stageOf(def.id, levels) -- 3.5: its stage's look
	local lower = stanceOf(levels) -- 4.0: Tyres & Suspension 5
	local built = build(def, paintColor(def, paintId), ground, false, gunId, nil, stage, lower)
	applyPaint(built.paintParts, def, paintId)
	buildKit(built.model, built.chassis, styleFor(def, stage), levels, def.id)
	local doors = doorsOf(styleFor(def, stage))
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
		health = math.max(1, stats.health * share),
		wrecked = false,
		latched = {},
		chauffeured = chauffeured == true,
		born = os.clock(),
		kit = kitKey(levels),
		stage = stage,
		lower = lower,
		lent = lent,
		repairing = false,
		doors = doors,
	}
	car.model.Name = `{player.DisplayName}'s {def.name}`
	car.model:SetAttribute("OwnerId", player.UserId)
	car.model:SetAttribute("OwnerName", player.DisplayName)
	car.model:SetAttribute("CarId", def.id)
	car.model:SetAttribute("Stage", stage)
	car.model:SetAttribute("SpeedMult", 1)
	car.model:SetAttribute("CarGun", gunId)
	-- A company vehicle lent for a job runs with its lights flashing (the ambulance's light bar).
	car.model:SetAttribute("Siren", carId ~= nil and def.company == true)
	car.model:SetAttribute("Chauffeured", car.chauffeured)
	writeAttributes(car)
	watchPrompts(car)
	local backPrompt = Vehicles.backPrompt(car)
	if backPrompt then
		backPrompt.HoldDuration = Economy.loadHold(Config.Cargo.HoldDuration, levels) -- 3.3: Quick Hands
		backPrompt.Triggered:Connect(function(by: Player)
			toggleBack(car, by)
		end)
	end
	car.model.Parent = workspace:FindFirstChild("Cars") or workspace
	cars[player] = car
	watchSeat(car, driverSeat, 1, true)
	for _, p in car.passengers do
		local door = p:GetAttribute("Door")
		watchSeat(car, p, if type(door) == "number" then door else 1, false)
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

-- The chauffeur got out: the car is its owner's now (its doors take you in again, the owner's client drives it).
function Vehicles.handOver(car: Car)
	if not car.chauffeured then
		return
	end
	car.chauffeured = false
	car.model:SetAttribute("Chauffeured", false)
	if car.wrecked or not car.chassis.Parent then
		return
	end
	Vehicles.setBack(car, false) -- the chauffeur leaves it closed
	-- 3.7: the chauffeur got out of the driver's door (server/CarCall.luau steps them out there).
	local now = workspace:GetServerTimeNow()
	swingDoor(car, 1, now, now + Config.Cargo.AlightSeconds + 0.1)
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
		local car = Vehicles.placeAt(player, carId, home)
		if not car then
			return "Still loading..."
		end
		local def = Economy.findCar(car.id)
		Net.get("Notice"):FireClient(player, `Your {if def then def.name else "car"} is parked in front of your garage.`)
		return nil
	end
	return Vehicles.placeNear(player, carId)
end

-- 4.0: how long the car the player would get is (its style at its stage: a stretched van, the Freight Truck).
local function lengthFor(player: Player, carId: string?): number
	local profile = PlayerData.get(player)
	local def = Economy.findCar(carId or (if profile then profile.car else "van")) or Config.Cars[1]
	local levels = if profile then Economy.carLevels(profile.carUpgrades, def.id) else {}
	return styleFor(def, if def.company then 0 else Economy.stageOf(def.id, levels)).length
end

-- The car parked at a garage's drive-out spot (a home's garage, 3.4: any garage you take a car out of), facing the
-- road, the player not in it (seat: they get in, 3.4: a swap from the driver's seat). Returns the car, or nil while
-- the save loads. 4.0: a car longer than a Box Truck (the Freight Truck, a Freight Hauler) stands further out, its
-- back a stud clear of the garage's front wall (the spot is Map.GarageApron = 8 in front of it).
-- 4.0: how much farther out of a garage door a long car stands (the Freight Truck, the Freight Hauler: their back
-- would reach into the door's lintel), studs along the spot's look; 0 for an ordinary car. Also its length.
function Vehicles.driveOut(player: Player, carId: string?): (number, number)
	local length = lengthFor(player, carId)
	return if length > 17 then length / 2 - (Map.GarageApron - 1) else 0, length
end

function Vehicles.placeAt(player: Player, carId: string?, spot: CFrame, seat: boolean?): Car?
	local look = Vector3.new(spot.LookVector.X, 0, spot.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, 1)
	local out = Vehicles.driveOut(player, carId)
	Vehicles.remove(player) -- the old car is not in the way; a co-owner's car is (step out to the road)
	local at = freeSpot(spot.Position + look * out, look, 16)
	local position = Vector3.new(at.X, Vehicles.groundY(at.X, at.Z, spot.Position.Y) + 0.5, at.Z)
	return Vehicles.spawnAt(player, carId, CFrame.lookAt(position, position + look), seat == true)
end

-- 3.3, Quick Hands: how long the holds of this car's back and its cargo prompts take (its loading level).
function Vehicles.loadHold(car: Car): number
	local profile = PlayerData.get(car.owner)
	local levels = if profile then Economy.carLevels(profile.carUpgrades, car.id) else {}
	return Economy.loadHold(Config.Cargo.HoldDuration, levels)
end

-- 3.5: a new stage is a new body: the live car is built again where it stands (its damage kept: Vehicles.remove
-- remembers it), the owner back behind the wheel when they sat there (the passengers step out). Not while a chauffeur
-- drives it or it is on a repair lift (the shop waits for those). Returns whether it was rebuilt.
local function rebuild(car: Car): boolean
	if car.chauffeured or car.repairing or car.wrecked or car.lent then
		return false
	end
	local player = car.owner
	local frame = car.chassis.CFrame
	local look = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, 1)
	local base = STYLES[(Economy.findCar(car.id) or Config.Cars[1]).style] or STYLES.van
	local position = frame.Position - Vector3.new(0, base.clearance - car.lower + CHASSIS_HEIGHT / 2, 0)
	local occupant = car.seat.Occupant
	local seated = occupant ~= nil and Players:GetPlayerFromCharacter(occupant.Parent) == player
	return Vehicles.spawnAt(player, car.id, CFrame.lookAt(position, position + look), seated) ~= nil
end

-- New upgrades / a new car equipped: the live car takes the new numbers (health keeps its share), and (3.3) its
-- upgrade kit and its back's hold follow its car-track levels; 3.5: a new stage builds it again (rebuild); 4.0: so
-- does a new stance (Tyres & Suspension 5).
function Vehicles.refreshStats(player: Player)
	local car = Vehicles.get(player)
	local profile = PlayerData.get(player)
	if not car or not profile then
		return
	end
	local levels = Economy.carLevels(profile.carUpgrades, car.id)
	local rebuilt = Economy.stageOf(car.id, levels) ~= car.stage or stanceOf(levels) ~= car.lower
	if not car.lent and rebuilt and rebuild(car) then
		return
	end
	local share = car.health / car.stats.health
	car.stats = Economy.carStats(car.id, levels)
	car.health = car.stats.health * share
	writeAttributes(car)
	local backPrompt = Vehicles.backPrompt(car)
	if backPrompt then
		backPrompt.HoldDuration = Vehicles.loadHold(car)
	end
	local key = kitKey(levels)
	if key ~= car.kit then
		car.kit = key
		buildKit(car.model, car.chassis, styleOf(car), levels, car.id)
		-- The new parts joined the car's assembly: the driver's client keeps simulating it.
		pcall(function()
			car.chassis:SetNetworkOwner(if car.chauffeured then nil else player)
		end)
	end
end

-- A new paint job on the live car.
function Vehicles.repaint(player: Player)
	local car = Vehicles.get(player)
	local profile = PlayerData.get(player)
	local def = car and Economy.findCar(car.id)
	if not car or not profile or not def then
		return
	end
	applyPaint(car.paintParts, def, if def.company then nil else profile.carPaint[car.id])
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
	-- The turning goes too: client/Drive.luau stops writing it once "Drive" is gone, and the burnt car span on
	-- at its last steer rate.
	local angular = car.chassis:FindFirstChild("Steer")
	if angular then
		angular:Destroy()
	end
	car.model:SetAttribute("Health", 0)
	-- 3.4: it comes back (CAR) badly damaged: a trip to a repair shop.
	local profile = PlayerData.get(car.owner)
	if profile and not car.lent then
		profile.carHealth[car.id] = Config.Repair.WreckedHealth
	end
	car.repairing = false
	car.chassis.Anchored = false
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
	else
		remember(car)
	end
end

function Vehicles.repair(car: Car, share: number)
	if car.wrecked then
		return
	end
	car.health = math.min(car.stats.health, car.health + car.stats.health * share)
	car.model:SetAttribute("Health", math.ceil(car.health))
	remember(car)
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
	-- 3.10: getting in and out, the body passes through the car's shell (client/CarBoarding.luau puts the character
	-- into this group for the move).
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Boarding")
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("Boarding", "Car", false)
	end)
	Net.get("CarDoor").OnServerEvent:Connect(onCarDoor)
	Players.PlayerRemoving:Connect(function(player)
		local b = boarders[player]
		if b then
			cancelBoarding(player, b)
		end
		Vehicles.remove(player)
		lastSpawn[player] = nil
		lastOut[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		stepBoarding()
		for _, car in cars do
			if car.wrecked then
				continue
			end
			local position = car.chassis.Position
			-- (3.4: no free repairs any more: the repair bays, server/Repair.luau.)
			-- Drove into the water (or off the world).
			if position.Y < -7 then
				Vehicles.damage(car, math.huge, "Your car sank!")
			end
		end
	end)
end

return Vehicles
