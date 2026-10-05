--!strict
-- Cargo you handle on foot: crates, sacks, barrels, ice boxes, furniture you pick up and carry in your hands, horses
-- you lead on a rope, kids who walk in and out by themselves. Loaded pieces ride visibly in the vehicle.
--
-- server/Jobs.luau opens a Session for every job and gives it one stop (a Plan) at a time:
--   carry  the giver stands at the pile with the pieces: "Pick up" (E) puts one in your hands (the character
--          attribute Carrying = its kind, the model is welded in front of the chest), "Load" at the back of the
--          vehicle puts it in a cargo slot. At the drop "Take out" at the back, then "Hand over" at the receiver.
--   lead   the same with horses: "Lead" takes one on the rope (Carrying = "horse"), "Load" puts it in a stall.
--   board  park in the circle and wait: the kids walk from the house to the bus door (and at the school out of it),
--          a patient shuffles slowly from home to the ambulance (bandaged, on a stretcher inside) and at the clinic
--          over to the doctor; survivors (3.0, the missions) walk in at a normal pace, dirty, a backpack on.
--   serve  park in the circle and hold still while the customers buy (the ice cream route).
-- "Put down" (G) drops what you hold where you stand (to shoot); it also drops when the carrier dies, leaves or sits.
-- Only the job's owner and their crew (who rode in the owner's car, or joined it by invitation: server/Crew.luau) may
-- use the prompts, checked here (Info.allowed).
--
-- 3.0, the missions' twists: Info.lift (heavy pieces: carried alone they slow you to Config.Missions.LiftSlowSpeed,
-- the character attribute CarrySpeed tells the client; with a crew mate within LiftHelpRange the normal step), and
-- Cargo.setBlocked (the defend twist: at the last drop nothing is unloaded until the area is held). The mission
-- cargo has its own looks (water, generator, battery, tnt, documents, electronics, weapons, painting, mail, tires,
-- plants, survivor).
--
-- 3.2, the back that opens (server/Vehicles.luau: doors, a tailgate, a trunk lid, a ramp): carry and lead go through
-- it. "Load" and "Take out" only work while it is open, and opening or closing it needs empty hands (Vehicles'
-- BackPrompt, for the owner and the job's crew: the hook Vehicles.backAllowed). So a piece is picked up, put down (G)
-- at the car, the back opened (E), the piece picked up again (E) and loaded (E); when the stop is done the back is
-- closed (E) before the car can drive. Unloading the same way round. The BackPrompt and the Load prompt sit at the
-- same spot and take turns (one E at a time): the Load / Take out prompt while there is something to put in or take
-- out, else the BackPrompt. board and serve do not use the back (the people get in by themselves).
-- Info.pair (3.2, the DUO missions' pair twist): a piece only moves with two: no other job member within
-- Config.Missions.Duo.PairRange of you, no pick-up; the partner gone for PAIR_GRACE s while you carry, it goes down.
-- Cargo.setBlocked takes a reason (the DUO switches twist blocks a pick-up as well as a drop).
-- 3.3, Quick Hands (the loading upgrade of the job's car): the holds of the prompts here are shorter (holdFor).
-- 3.7, two in your hands: a light piece (Config.Cargo.LightLooks: a pizza stack, a parcel, a mail sack …) can be
-- carried two at a time (Config.Cargo.HandsMax), stacked in front of the chest, a little slower (TwoPieceSpeed, the
-- CarrySpeed attribute). Heavy pieces, horses and every piece of a lift or pair job stay one at a time (handsMax).
-- With one light piece a hand is free (the character attribute CarryHands = 1): you open and close the back yourself
-- (server/Vehicles.luau); two pieces or a heavy one fill both (CarryHands = 2): put one down or let a crew mate open
-- it. G puts down ONE piece (the top one), so two in hand → G → one in hand → open the back yourself. Load puts both
-- in at once; at a drop Take out with one light piece in hand takes a second, and Hand over gives the receiver all
-- you carry (as many as they still need). The character attribute CarryCount says how many you hold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)
local Animals = require(script.Parent.Animals)

local Tuning = Config.Cargo
local Cargo = {}

-- One stop as Jobs sees it.
export type Plan = {
	stage: string, -- pickup | drop
	mode: string, -- carry | lead | board | serve
	needed: number, -- pieces handled at this stop
	park: Vector3, -- the circle (the vehicle stops here)
	pile: Vector3, -- where the cargo stands / the receiver waits
	facing: Vector3, -- the way the person faces (flat, unit)
	person: Npcs.Look?, -- the giver / the receiver
	hold: number, -- serve: seconds to hold still
	keep: number, -- serve: pieces left in the vehicle after this stop
}

-- What the job is about, given when it starts.
export type Info = {
	kind: string, -- the Carrying kind: crate | ammo | sack | barrel | icebox | furniture | soup | horse | kid | patient …
	look: string, -- the model of a piece
	piece: string, -- "ammo crate"
	plural: string,
	total: number,
	handles: boolean, -- some stop is carry / lead (the vehicle gets the Load prompt)
	allowed: (Player) -> boolean, -- the owner and the crew
	changed: () -> (), -- something to send to the HUD
	lift: boolean?, -- the lift twist: heavy pieces, carried alone you walk at Config.Missions.LiftSlowSpeed
	pair: boolean?, -- 3.2, the pair twist: a piece moves only with another job member close (Config.Missions.Duo)
}

type Piece = {
	kind: string,
	look: string,
	variant: number,
	origin: number, -- the stop it was picked up at
	horse: Model?, -- a horse (lead)
	model: Model?, -- the visible piece where it is now (pile, hands, ground, a slot in the vehicle)
	npc: Model?, -- a kid standing or walking
	walkingSince: number?,
}

-- 3.7: pieces, bottom first (two light pieces stacked; one otherwise). The prompt (Put down / Let go) sits on the top one.
type Held = { pieces: { Piece }, character: Model, root: BasePart, prompt: ProximityPrompt?, last: CFrame }
type Loose = { piece: Piece, prompt: ProximityPrompt, handle: Part? }

export type Session = {
	owner: Player,
	info: Info,
	load: { Piece }, -- in the vehicle, in slot order
	held: { [Player]: Held },
	loose: { Loose }, -- put down somewhere
	lost: number, -- stolen, wrecked
	deliveredTotal: number,
	nextVariant: number,
	-- the current stop
	plan: Plan?,
	stop: number,
	built: boolean,
	greeted: boolean,
	pile: { Piece },
	walking: { Piece },
	moved: number, -- loaded at this pick-up / handed over at this drop
	hold: number, -- serve: seconds held still
	served: boolean,
	customers: boolean,
	nextKid: number,
	person: Model?,
	pilePart: Part?,
	pilePrompt: ProximityPrompt?,
	props: { Instance }, -- the stop's people, delivered pieces
	propHorses: { Model },
	-- the vehicle
	car: Vehicles.Car?,
	carPrompt: ProximityPrompt?,
	shown: { Model },
	ended: boolean,
	busy: number, -- people being spawned right now (Npcs.spawn may yield): the stop is not done meanwhile
	blocked: boolean, -- the defend twist: nothing is unloaded at this stop until the area is held (Cargo.setBlocked)
	blockedReason: string?, -- 3.2: what to tell while blocked (nil: the defend twist's "Hold out first!")
	pairAlone: { [Player]: number }, -- 3.2, the pair twist: since when (os.clock) the carrier has nobody close
	slowed: { [Player]: Model }, -- the lift twist: carriers walking slowly right now (their character, CarrySpeed set)
	liftTold: boolean, -- the lift twist's hint was given
	atStop: boolean, -- 3.2: the vehicle stood in the stop's circle at the last tick (Take out only there)
}

export type Status = {
	inCar: number,
	delivered: number,
	needed: number,
	total: number,
	deliveredTotal: number,
	lost: number,
	carrying: string?,
	person: string?,
	pile: Vector3?,
	looseAt: Vector3?, -- a piece put down (G) that has to be picked up again
	progress: number,
}

local folder: Instance = workspace
local rng = Random.new()
local notice = Net.get("Notice")
local active: { [Player]: Session } = {} -- the running sessions by owner (the back's hooks find them here)
local PAIR_GRACE = 1.5 -- the pair twist: seconds a carrier may be without the partner before the piece goes down

local KID_NAMES = { "Tommy", "Lily", "Max", "Sophie", "Leo", "Mia", "Ben", "Zoe", "Sam", "Ava", "Noah", "Ella" }
local PATIENT_NAMES = { "Mr. Brown", "Mrs. Lopez", "Old Pete", "Mr. Dvorak", "Mrs. Chen", "Mr. Okafor", "Miss Hart", "Mr. Svoboda" }
local SURVIVOR_NAMES = { "Jake", "Rosa", "Old Mike", "Priya", "Dmitri", "Hannah", "Carlos", "June", "Bogdan", "Amara", "Wes", "Lena" }
-- Npcs' walk animation (server/Npcs.luau WALK): a patient's steps are slowed to their shuffle.
local WALK_ANIMATION = "rbxassetid://507777826"
local LINES = {
	take = { "Careful, it's heavy!", "Lift with your legs!", "Got it?", "Easy, that one's fragile.", "Watch your back out there." },
	horse = { "Easy now, she's gentle.", "Walk him slowly up the ramp.", "Keep the rope short." },
	loaded = { "That's all of it. Drive safe!", "All loaded. Watch out for bandits!" },
	thanks = { "Thanks!", "Perfect, thank you!", "Just in time!", "Great work!", "Put it right there." },
	done = { "That's everything. Thank you!", "All here. You're a lifesaver!" },
	kidOn = { "Bye mom!", "Hi driver!", "Can I sit at the back?" },
	kidOff = { "Bye!", "Thanks for the ride!", "School, yay..." },
	customer = { "Vanilla, please!", "Chocolate!", "Two scoops!", "Strawberry, please!" },
	patientOn = { "Ow... careful with me.", "Is it far to the clinic?", "Thank you for coming...", "I feel dizzy..." },
	patientOff = { "Am I going to be okay?", "Thank you, driver...", "Is that the doctor?" },
	survivorOn = { "Go, go, go!", "You came back for us!", "Is there room for my bag?", "I haven't slept in days..." },
	survivorOff = { "We made it!", "Real walls. Real food!", "Thank you, driver!", "Is this place safe?" },
}

local function line(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

local function tell(player: Player, text: string)
	notice:FireClient(player, text)
end

local function article(noun: string): string
	local first = string.lower(string.sub(noun, 1, 1))
	return if string.find("aeiou", first, 1, true) then "an " .. noun else "a " .. noun
end

local function capital(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Is this character carrying something (the kind) or leading an animal ("horse")?
function Cargo.carrying(character: Model?): string?
	if not character then
		return nil
	end
	local value = character:GetAttribute("Carrying")
	return if type(value) == "string" then value else nil
end

-- Do the pieces of this kind walk in and out by themselves (the kids, the patients)? They cannot be stolen; a wreck or
-- bandits at the vehicle scare them (the job's condition drops) instead.
function Cargo.isPeople(kind: string): boolean
	return kind == "kid" or kind == "patient" or kind == "survivor"
end

-- The look of a person at a stop: Npcs.look, plus the roles Npcs does not know (the clinic's doctor, a patient, a
-- survivor).
function Cargo.look(role: string, name: string, title: string?): Npcs.Look
	local look = Npcs.look(if role == "doctor" or role == "patient" or role == "survivor" then "townsperson" else role, name, title)
	if role == "doctor" then
		-- A white coat over light blue scrubs.
		look.hat = "none"
		look.shirt, look.pants, look.apron = { 236, 240, 244 }, { 110, 160, 190 }, { 246, 248, 250 }
		look.vest, look.shortSleeves, look.boots = nil, false, false
		look.shoes = { 230, 232, 236 }
	elseif role == "patient" then
		-- A pale hospital gown and slippers (the bandages come with Cargo's dressPatient).
		look.hat = "none"
		look.shirt, look.pants = { 168, 200, 222 }, { 168, 200, 222 }
		look.vest, look.apron, look.boots = nil, nil, false
		look.shortSleeves = true
		look.shoes = { 200, 200, 204 }
	elseif role == "survivor" then
		-- Weeks out there: a dirty jacket, worn jeans, a beanie (the backpack comes with Cargo's dressSurvivor).
		local jackets = { { 104, 92, 66 }, { 88, 96, 74 }, { 120, 84, 60 }, { 76, 82, 92 } }
		look.hat, look.hatColor = "beanie", { 70, 64, 58 }
		look.shirt = jackets[#name % #jackets + 1]
		look.pants, look.vest, look.apron, look.coat, look.tie = { 72, 78, 92 }, nil, nil, nil, nil
		look.shortSleeves, look.boots, look.bandage = false, true, false
		look.shoes = { 58, 48, 40 }
	end
	return look
end

-- ── The ground ─────────────────────────────────────────────────────────────

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- The height of the walkable ground at x, z (near `around`): not a roof, a tree or a car.
local function groundY(x: number, z: number, around: number): number
	local skip: { Instance } = { folder }
	for _, name in { "Cars", "Zombies", "Npcs", "Animals", "Effects", "Loot", "Showroom" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = skip
	local result = workspace:Raycast(Vector3.new(x, around + 25, z), Vector3.new(0, -60, 0), groundParams)
	if result and result.Position.Y < around + 6 and result.Position.Y > around - 10 then
		return result.Position.Y
	end
	return around
end

local function onGround(position: Vector3): Vector3
	return Vector3.new(position.X, groundY(position.X, position.Z, position.Y), position.Z)
end

-- ── The pieces ─────────────────────────────────────────────────────────────

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = model
	return p
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Text printed on a side of a part (a stencil on a crate).
local function stencil(part: BasePart, text: string, color: Color3, faces: { Enum.NormalId })
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.9, 0.5)
		label.Position = UDim2.fromScale(0.05, 0.25)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = color
		label.Parent = gui
		gui.Parent = part
	end
end

local FRONT_BACK = { Enum.NormalId.Front, Enum.NormalId.Back }
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

-- The missions' cargo (3.0, Config.Cargo.Kinds), built into `model` like buildLook's (the bottom centre is the pivot,
-- the front is -Z; the first part is the main one). False for a look it does not know.
local function missionLook(model: Model, look: string, variant: number): boolean
	local black = Color3.new(0, 0, 0)
	local function block(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material): Part
		return newPart(model, name, size, CFrame.new(at), color, material)
	end
	-- A cylinder `length` long: standing up, or lying along Z (a disc facing the front, a stick front to back) or X.
	local function cylinder(name: string, length: number, diameter: number, at: Vector3, color: Color3, material: Enum.Material, axis: string?): Part
		local turn = if axis == "z" then CFrame.Angles(0, math.rad(90), 0) elseif axis == "x" then CFrame.identity else UPRIGHT
		local p = newPart(model, name, Vector3.new(length, diameter, diameter), CFrame.new(at) * turn, color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	local function ball(name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material): Part
		local p = block(name, Vector3.new(diameter, diameter, diameter), at, color, material)
		p.Shape = Enum.PartType.Ball
		return p
	end

	if look == "water" then
		-- A big water jug: clear plastic, the water inside, a blue cap.
		local body = cylinder("Body", 1.9, 1.5, Vector3.new(0, 0.95, 0), rgb(176, 214, 240), Enum.Material.Glass)
		body.Transparency = 0.4
		cylinder("Water", 1.55, 1.34, Vector3.new(0, 0.82, 0), rgb(70, 150, 230), Enum.Material.SmoothPlastic).Transparency = 0.2
		for _, y in { 0.45, 1.45 } do
			cylinder("Ring", 0.12, 1.56, Vector3.new(0, y, 0), rgb(150, 196, 232), Enum.Material.Glass).Transparency = 0.3
		end
		cylinder("Neck", 0.35, 0.6, Vector3.new(0, 2.07, 0), rgb(176, 214, 240), Enum.Material.Glass).Transparency = 0.3
		cylinder("Cap", 0.22, 0.7, Vector3.new(0, 2.33, 0), rgb(40, 90, 200), Enum.Material.SmoothPlastic)
	elseif look == "generator" then
		-- An orange generator in a black tube frame: the fuel tank on top, the control panel at the front.
		local frame = rgb(36, 36, 40)
		local body = block("Body", Vector3.new(2.5, 1.4, 1.6), Vector3.new(0, 0.95, 0), rgb(232, 132, 32), Enum.Material.SmoothPlastic)
		block("Tank", Vector3.new(1.6, 0.42, 1.2), Vector3.new(-0.2, 1.86, 0), rgb(220, 120, 26), Enum.Material.SmoothPlastic)
		cylinder("FuelCap", 0.14, 0.4, Vector3.new(0.3, 2.13, 0), frame, Enum.Material.Metal)
		for _, z in { -0.85, 0.85 } do
			block("Skid", Vector3.new(2.9, 0.22, 0.22), Vector3.new(0, 0.11, z), frame, Enum.Material.Metal)
			block("Rail", Vector3.new(2.9, 0.18, 0.18), Vector3.new(0, 2.05, z), frame, Enum.Material.Metal)
			for _, x in { -1.36, 1.36 } do
				block("Post", Vector3.new(0.18, 2.0, 0.18), Vector3.new(x, 1.08, z), frame, Enum.Material.Metal)
			end
		end
		block("Panel", Vector3.new(0.9, 0.7, 0.05), Vector3.new(0.6, 0.95, -0.82), frame, Enum.Material.Metal)
		block("Socket", Vector3.new(0.2, 0.2, 0.05), Vector3.new(0.4, 0.95, -0.85), rgb(240, 240, 235), Enum.Material.SmoothPlastic)
		block("Lamp", Vector3.new(0.14, 0.14, 0.05), Vector3.new(0.85, 1.15, -0.85), rgb(90, 255, 90), Enum.Material.Neon)
		cylinder("Exhaust", 0.6, 0.28, Vector3.new(-1.45, 1.35, 0.4), rgb(120, 120, 126), Enum.Material.Metal, "x")
		stencil(body, "POWER", frame, { Enum.NormalId.Back })
	elseif look == "battery" then
		-- A heavy battery pack: the terminals, a yellow band, 12V.
		local body = block("Body", Vector3.new(2.0, 1.3, 1.3), Vector3.new(0, 0.65, 0), rgb(36, 38, 42), Enum.Material.SmoothPlastic)
		block("Top", Vector3.new(2.05, 0.15, 1.35), Vector3.new(0, 1.37, 0), rgb(62, 64, 70), Enum.Material.SmoothPlastic)
		block("Band", Vector3.new(2.02, 0.2, 1.32), Vector3.new(0, 1.15, 0), rgb(240, 200, 40), Enum.Material.SmoothPlastic)
		cylinder("Plus", 0.28, 0.34, Vector3.new(-0.62, 1.58, -0.3), rgb(210, 40, 36), Enum.Material.Metal)
		cylinder("Minus", 0.28, 0.34, Vector3.new(0.62, 1.58, -0.3), rgb(150, 150, 156), Enum.Material.Metal)
		block("Handle", Vector3.new(1.0, 0.12, 0.25), Vector3.new(0, 1.62, 0.3), rgb(24, 24, 26), Enum.Material.SmoothPlastic)
		stencil(body, "12V", rgb(240, 200, 40), FRONT_BACK)
	elseif look == "tnt" then
		-- A dynamite crate: red sticks bundled on the lid, a fuse, DANGER.
		local wood = rgb(150, 104, 62)
		local body = block("Body", Vector3.new(2.2, 1.5, 1.5), Vector3.new(0, 0.75, 0), wood, Enum.Material.WoodPlanks)
		local dark = wood:Lerp(black, 0.35)
		for _, y in { 0.12, 1.38 } do
			block("Rim", Vector3.new(2.3, 0.25, 1.6), Vector3.new(0, y, 0), dark, Enum.Material.Wood)
		end
		for n, z in { -0.36, 0, 0.36 } do
			cylinder("Stick", 1.5, 0.34, Vector3.new(0.05 * n, 1.68, z), rgb(200, 36, 30), Enum.Material.SmoothPlastic, "x")
		end
		block("Band", Vector3.new(0.22, 0.4, 1.14), Vector3.new(0, 1.7, 0), rgb(30, 30, 30), Enum.Material.Fabric)
		block("Fuse", Vector3.new(0.5, 0.08, 0.08), Vector3.new(1.0, 1.82, 0), rgb(40, 34, 30), Enum.Material.Fabric)
		stencil(body, "TNT", rgb(210, 30, 24), FRONT_BACK)
		stencil(body, "DANGER", rgb(210, 30, 24), { Enum.NormalId.Left, Enum.NormalId.Right })
	elseif look == "documents" then
		-- A briefcase with gold clasps and a TOP SECRET tag.
		local leather = if variant % 2 == 0 then rgb(74, 48, 30) else rgb(32, 32, 36)
		local dark = leather:Lerp(black, 0.35)
		block("Body", Vector3.new(2.0, 1.4, 0.55), Vector3.new(0, 0.7, 0), leather, Enum.Material.Leather)
		block("Seam", Vector3.new(2.04, 0.08, 0.59), Vector3.new(0, 1.12, 0), dark, Enum.Material.Leather)
		block("Handle", Vector3.new(0.72, 0.14, 0.18), Vector3.new(0, 1.62, 0), dark, Enum.Material.Leather)
		for _, x in { -0.32, 0.32 } do
			block("Grip", Vector3.new(0.12, 0.24, 0.18), Vector3.new(x, 1.5, 0), dark, Enum.Material.Leather)
		end
		for _, x in { -0.65, 0.65 } do
			block("Clasp", Vector3.new(0.22, 0.16, 0.05), Vector3.new(x, 1.12, -0.3), rgb(222, 180, 60), Enum.Material.Metal)
		end
		local tag = block("Tag", Vector3.new(0.8, 0.42, 0.03), Vector3.new(0.45, 0.55, -0.29), rgb(240, 236, 220), Enum.Material.SmoothPlastic)
		stencil(tag, "TOP SECRET", rgb(200, 30, 30), { Enum.NormalId.Front })
	elseif look == "electronics" then
		-- A grey crate of radio parts: a circuit board at the front, a blinking light, an antenna.
		local body = block("Body", Vector3.new(2.2, 1.5, 1.6), Vector3.new(0, 0.75, 0), rgb(112, 120, 112), Enum.Material.Metal)
		block("Lid", Vector3.new(2.3, 0.2, 1.7), Vector3.new(0, 1.6, 0), rgb(82, 88, 82), Enum.Material.Metal)
		block("Board", Vector3.new(1.1, 0.7, 0.05), Vector3.new(-0.4, 0.8, -0.82), rgb(40, 124, 62), Enum.Material.SmoothPlastic)
		for n = 0, 2 do
			block("Chip", Vector3.new(0.2, 0.16, 0.04), Vector3.new(-0.75 + n * 0.32, 0.9, -0.86), rgb(26, 26, 28), Enum.Material.SmoothPlastic)
		end
		block("Led", Vector3.new(0.14, 0.14, 0.04), Vector3.new(0.6, 1.2, -0.82), rgb(255, 64, 40), Enum.Material.Neon)
		cylinder("Knob", 0.12, 0.3, Vector3.new(0.6, 0.7, -0.84), rgb(30, 30, 32), Enum.Material.SmoothPlastic, "z")
		block("Antenna", Vector3.new(0.08, 0.9, 0.08), Vector3.new(0.85, 2.15, 0.5), rgb(40, 40, 44), Enum.Material.Metal)
		stencil(body, "RADIO PARTS", rgb(240, 240, 230), { Enum.NormalId.Back })
	elseif look == "weapons" then
		-- A long hard case (rifles inside), army green, the latches at the back.
		local body = block("Body", Vector3.new(3.2, 0.9, 1.3), Vector3.new(0, 0.45, 0), rgb(42, 46, 36), Enum.Material.SmoothPlastic)
		block("Lid", Vector3.new(3.24, 0.12, 1.34), Vector3.new(0, 0.62, 0), rgb(58, 64, 50), Enum.Material.SmoothPlastic)
		for _, x in { -1.0, 0, 1.0 } do
			block("Latch", Vector3.new(0.25, 0.25, 0.06), Vector3.new(x, 0.6, 0.68), rgb(150, 150, 156), Enum.Material.Metal)
		end
		block("Handle", Vector3.new(0.8, 0.12, 0.2), Vector3.new(0, 0.97, 0), rgb(20, 20, 22), Enum.Material.SmoothPlastic)
		for _, x in { -0.5, 0.5 } do
			block("Grip", Vector3.new(0.12, 0.3, 0.2), Vector3.new(x, 0.8, 0), rgb(20, 20, 22), Enum.Material.SmoothPlastic)
		end
		stencil(body, "ARMY", rgb(222, 204, 124), { Enum.NormalId.Front })
	elseif look == "painting" then
		-- A framed painting (hills and a sun), cardboard corners against the knocks.
		local canvases = { rgb(90, 140, 200), rgb(220, 150, 90), rgb(120, 90, 160) }
		block("Frame", Vector3.new(2.6, 2.0, 0.25), Vector3.new(0, 1.0, 0), rgb(200, 160, 62), Enum.Material.Wood)
		block("Canvas", Vector3.new(2.2, 1.6, 0.05), Vector3.new(0, 1.0, -0.14), canvases[variant % #canvases + 1], Enum.Material.SmoothPlastic)
		block("Hill", Vector3.new(2.2, 0.5, 0.04), Vector3.new(0, 0.45, -0.17), rgb(70, 130, 64), Enum.Material.SmoothPlastic)
		block("Hill", Vector3.new(1.0, 0.75, 0.04), Vector3.new(-0.55, 0.55, -0.18), rgb(56, 110, 54), Enum.Material.SmoothPlastic)
		cylinder("Sun", 0.04, 0.45, Vector3.new(0.6, 1.4, -0.18), rgb(250, 212, 80), Enum.Material.SmoothPlastic, "z")
		for _, x in { -1.2, 1.2 } do
			for _, y in { 0.15, 1.85 } do
				block("Corner", Vector3.new(0.42, 0.42, 0.36), Vector3.new(x, y, 0), rgb(196, 158, 108), Enum.Material.Cardboard)
			end
		end
	elseif look == "mail" then
		-- A canvas mail sack, letters sticking out of the top.
		local canvas = if variant % 2 == 0 then rgb(70, 92, 142) else rgb(150, 140, 110)
		local body = block("Body", Vector3.new(1.7, 1.6, 1.2), Vector3.new(0, 0.8, 0), canvas, Enum.Material.Fabric)
		block("Top", Vector3.new(1.2, 0.5, 0.85), Vector3.new(0, 1.85, 0), canvas, Enum.Material.Fabric)
		block("Tie", Vector3.new(1.25, 0.14, 0.9), Vector3.new(0, 1.7, 0), rgb(150, 110, 60), Enum.Material.Fabric)
		for n, x in { -0.25, 0.2 } do
			newPart(model, "Letter", Vector3.new(0.6, 0.42, 0.04), CFrame.new(x, 2.18, 0.05 * n) * CFrame.Angles(0, 0, math.rad(if n == 1 then 14 else -10)), rgb(245, 240, 226), Enum.Material.SmoothPlastic)
		end
		stencil(body, "MAIL", rgb(240, 240, 240), FRONT_BACK)
	elseif look == "tires" then
		-- Two or three tires stacked flat.
		for n = 0, 1 + variant % 2 do
			local y = 0.3 + n * 0.62
			cylinder("Tire", 0.6, 2.0, Vector3.new(0, y, 0), rgb(30, 30, 32), Enum.Material.Rubber)
			cylinder("Rim", 0.62, 0.95, Vector3.new(0, y, 0), rgb(176, 176, 182), Enum.Material.Metal)
		end
	elseif look == "plants" then
		-- A tray of seedlings in dark soil.
		block("Tray", Vector3.new(2.2, 0.4, 1.5), Vector3.new(0, 0.2, 0), rgb(56, 48, 40), Enum.Material.SmoothPlastic)
		block("Soil", Vector3.new(2.0, 0.08, 1.3), Vector3.new(0, 0.42, 0), rgb(82, 58, 38), Enum.Material.Ground)
		local greens = { rgb(84, 160, 70), rgb(110, 180, 80), rgb(70, 140, 60) }
		for i = 0, 2 do
			for j = 0, 1 do
				local x, z = -0.7 + i * 0.7, -0.35 + j * 0.7
				block("Stem", Vector3.new(0.08, 0.5, 0.08), Vector3.new(x, 0.7, z), rgb(70, 120, 50), Enum.Material.Grass)
				ball("Leaves", 0.5, Vector3.new(x, 1.0, z), greens[(i + j + variant) % #greens + 1], Enum.Material.Grass)
			end
		end
	elseif look == "survivor" then
		-- A survivor in the vehicle: a dirty jacket, a beanie, the backpack they never put down.
		local jackets = { rgb(104, 92, 66), rgb(88, 96, 74), rgb(120, 84, 60), rgb(76, 82, 92) }
		local skins = { rgb(255, 214, 180), rgb(200, 150, 110), rgb(140, 95, 65), rgb(240, 190, 150) }
		block("Body", Vector3.new(1.5, 1.4, 0.8), Vector3.new(0, 0.7, 0), jackets[variant % #jackets + 1], Enum.Material.Fabric)
		ball("Head", 1.0, Vector3.new(0, 1.95, 0), skins[variant % #skins + 1], Enum.Material.SmoothPlastic)
		block("Beanie", Vector3.new(1.02, 0.4, 1.02), Vector3.new(0, 2.33, 0.03), rgb(70, 64, 58), Enum.Material.Fabric)
		block("Backpack", Vector3.new(1.1, 1.1, 0.5), Vector3.new(0, 0.85, 0.62), rgb(62, 82, 52), Enum.Material.Fabric)
		block("Dirt", Vector3.new(0.5, 0.3, 0.03), Vector3.new(-0.3, 0.6, -0.41), rgb(70, 56, 40), Enum.Material.Fabric)
	else
		return false
	end
	return true
end

-- A piece of cargo built at the origin: the bottom centre is the pivot, the front is -Z.
local function buildLook(look: string, variant: number): Model
	local model = Instance.new("Model")
	model.Name = "Cargo"
	local function block(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material): Part
		return newPart(model, name, size, CFrame.new(at), color, material)
	end
	local function cylinder(name: string, height: number, diameter: number, y: number, color: Color3, material: Enum.Material): Part
		local p = newPart(model, name, Vector3.new(height, diameter, diameter), CFrame.new(0, y, 0) * UPRIGHT, color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	local function crate(size: Vector3, wood: Color3): Part
		local body = block("Body", size, Vector3.new(0, size.Y / 2, 0), wood, Enum.Material.WoodPlanks)
		local dark = wood:Lerp(Color3.new(0, 0, 0), 0.3)
		block("Rim", Vector3.new(size.X + 0.1, 0.25, size.Z + 0.1), Vector3.new(0, size.Y - 0.12, 0), dark, Enum.Material.Wood)
		block("Rim", Vector3.new(size.X + 0.1, 0.25, size.Z + 0.1), Vector3.new(0, 0.12, 0), dark, Enum.Material.Wood)
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				block("Post", Vector3.new(0.28, size.Y, 0.28), Vector3.new(x * (size.X / 2 - 0.1), size.Y / 2, z * (size.Z / 2 - 0.1)), dark, Enum.Material.Wood)
			end
		end
		return body
	end
	local function cardboard(size: Vector3): Part
		local body = block("Body", size, Vector3.new(0, size.Y / 2, 0), rgb(196, 158, 108), Enum.Material.Cardboard)
		block("Tape", Vector3.new(0.45, size.Y + 0.02, size.Z + 0.02), Vector3.new(0, size.Y / 2, 0), rgb(222, 200, 160), Enum.Material.SmoothPlastic)
		return body
	end

	if look == "crate" or look == "tools" then
		local body = crate(Vector3.new(2.2, 2, 2.2), rgb(163, 120, 74))
		if look == "tools" then
			stencil(body, "TOOLS", rgb(190, 40, 30), FRONT_BACK)
		end
	elseif look == "ammo" then
		local olive = rgb(84, 96, 58)
		local body = block("Body", Vector3.new(2.6, 1.4, 1.5), Vector3.new(0, 0.7, 0), olive, Enum.Material.Metal)
		block("Lid", Vector3.new(2.7, 0.25, 1.6), Vector3.new(0, 1.45, 0), olive:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal)
		for _, x in { -1.4, 1.4 } do
			block("Handle", Vector3.new(0.25, 0.3, 0.8), Vector3.new(x, 1.0, 0), rgb(40, 42, 40), Enum.Material.Metal)
		end
		stencil(body, "7.62 AMMO", rgb(235, 205, 70), FRONT_BACK)
	elseif look == "sack" or look == "bread" then
		local colors = { rgb(186, 160, 112), rgb(170, 140, 95), rgb(200, 178, 126) }
		local color = if look == "bread" then rgb(228, 210, 172) else colors[variant % #colors + 1]
		local body = block("Body", Vector3.new(1.8, 1.5, 1.2), Vector3.new(0, 0.75, 0), color, Enum.Material.Fabric)
		block("Top", Vector3.new(1.3, 0.45, 0.9), Vector3.new(0, 1.7, 0), color, Enum.Material.Fabric)
		block("Tie", Vector3.new(1.35, 0.14, 0.95), Vector3.new(0, 1.55, 0), rgb(120, 90, 50), Enum.Material.Fabric)
		if look == "bread" then
			for n, x in { -0.35, 0.3 } do
				local loaf = newPart(model, "Baguette", Vector3.new(1.6, 0.35, 0.35), CFrame.new(x, 2.05, 0) * CFrame.Angles(0, 0, math.rad(if n == 1 then 75 else 100)), rgb(212, 150, 70), Enum.Material.SmoothPlastic)
				loaf.Shape = Enum.PartType.Cylinder
			end
			stencil(body, "BREAD", rgb(120, 70, 30), FRONT_BACK)
		else
			stencil(body, "OLD FARM", rgb(90, 60, 30), FRONT_BACK)
		end
	elseif look == "barrel" then
		local colors = { rgb(190, 50, 40), rgb(40, 80, 170), rgb(214, 170, 40) }
		local color = colors[variant % #colors + 1]
		cylinder("Body", 3, 2.2, 1.5, color, Enum.Material.Metal)
		for _, y in { 0.15, 1.0, 2.0, 2.85 } do
			cylinder("Rib", 0.16, 2.3, y, color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Metal)
		end
		cylinder("Lid", 0.06, 2.0, 3.0, rgb(70, 70, 74), Enum.Material.Metal)
		local label = block("Label", Vector3.new(1, 0.8, 0.05), Vector3.new(0, 1.55, -1.1), rgb(240, 240, 235), Enum.Material.SmoothPlastic)
		stencil(label, "FUEL", rgb(200, 30, 30), { Enum.NormalId.Front })
	elseif look == "icebox" or look == "vaccine" then
		local lid = if look == "vaccine" then rgb(200, 40, 40) else rgb(60, 140, 220)
		local body = block("Body", Vector3.new(2.4, 1.5, 1.6), Vector3.new(0, 0.75, 0), rgb(240, 244, 248), Enum.Material.SmoothPlastic)
		block("Lid", Vector3.new(2.5, 0.35, 1.7), Vector3.new(0, 1.65, 0), lid, Enum.Material.SmoothPlastic)
		block("Handle", Vector3.new(1.4, 0.2, 0.3), Vector3.new(0, 1.92, 0), rgb(60, 60, 64), Enum.Material.Metal)
		stencil(body, if look == "vaccine" then "VACCINE" else "FROSTY'S", lid, FRONT_BACK)
	elseif look == "sample" then
		local body = block("Body", Vector3.new(2.2, 1.4, 1.4), Vector3.new(0, 0.7, 0), rgb(160, 165, 170), Enum.Material.DiamondPlate)
		block("Window", Vector3.new(1.2, 0.5, 0.05), Vector3.new(0, 0.75, -0.72), rgb(90, 255, 90), Enum.Material.Neon)
		block("Handle", Vector3.new(1.2, 0.2, 0.3), Vector3.new(0, 1.5, 0), rgb(50, 50, 54), Enum.Material.Metal)
		stencil(body, "BIOHAZARD", rgb(230, 200, 40), { Enum.NormalId.Back })
	elseif look == "soup" then
		local body = block("Body", Vector3.new(2, 1.6, 1.6), Vector3.new(0, 0.8, 0), rgb(230, 120, 40), Enum.Material.SmoothPlastic)
		block("Lid", Vector3.new(2.1, 0.3, 1.7), Vector3.new(0, 1.75, 0), rgb(70, 70, 74), Enum.Material.SmoothPlastic)
		block("Handle", Vector3.new(1.2, 0.2, 0.3), Vector3.new(0, 2.0, 0), rgb(40, 40, 44), Enum.Material.Metal)
		stencil(body, "HOT SOUP", rgb(255, 255, 255), FRONT_BACK)
		local steam = Instance.new("Smoke")
		steam.Color = rgb(255, 255, 255)
		steam.Opacity = 0.08
		steam.Size = 0.6
		steam.RiseVelocity = 2
		steam.Parent = body
	elseif look == "parcel" then
		local sizes = { Vector3.new(1.8, 1.4, 1.4), Vector3.new(2.2, 1.6, 1.6), Vector3.new(1.6, 1.2, 1.3) }
		local size = sizes[variant % #sizes + 1]
		cardboard(size)
		block("Label", Vector3.new(0.7, 0.5, 0.03), Vector3.new(0.45, size.Y * 0.55, -size.Z / 2 - 0.02), rgb(245, 245, 240), Enum.Material.SmoothPlastic)
	elseif look == "groceries" then
		block("Body", Vector3.new(2.2, 1.3, 1.6), Vector3.new(0, 0.65, 0), rgb(196, 158, 108), Enum.Material.Cardboard)
		for n, color in { rgb(200, 40, 40), rgb(240, 150, 40), rgb(110, 170, 60) } do
			local fruit = block("Fruit", Vector3.new(0.6, 0.6, 0.6), Vector3.new(-0.7 + (n - 1) * 0.7, 1.35, (n % 2) * 0.3 - 0.15), color, Enum.Material.SmoothPlastic)
			fruit.Shape = Enum.PartType.Ball
		end
	elseif look == "medicine" then
		block("Body", Vector3.new(2, 1.4, 1.4), Vector3.new(0, 0.7, 0), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
		for _, z in { -0.71, 0.71 } do
			block("Cross", Vector3.new(0.8, 0.25, 0.03), Vector3.new(0, 0.75, z), rgb(210, 30, 30), Enum.Material.SmoothPlastic)
			block("Cross", Vector3.new(0.25, 0.8, 0.03), Vector3.new(0, 0.75, z), rgb(210, 30, 30), Enum.Material.SmoothPlastic)
		end
	elseif look == "pizza" then
		for n = 0, 2 + variant % 2 do
			block("Box", Vector3.new(2, 0.32, 2), Vector3.new(0, 0.16 + n * 0.34, 0), rgb(214, 184, 140), Enum.Material.Cardboard)
		end
		block("Logo", Vector3.new(0.9, 0.04, 0.9), Vector3.new(0, 0.34 * (3 + variant % 2) + 0.01, 0), rgb(200, 40, 30), Enum.Material.SmoothPlastic)
	elseif look == "gold" then
		-- A strongbox (the bank's gold, the cash transport's sacks of cash ride in these).
		local body = block("Body", Vector3.new(2, 1.2, 1.4), Vector3.new(0, 0.6, 0), rgb(60, 62, 66), Enum.Material.DiamondPlate)
		block("Trim", Vector3.new(2.05, 0.15, 1.45), Vector3.new(0, 1.2, 0), rgb(230, 180, 50), Enum.Material.Metal)
		block("Lock", Vector3.new(0.4, 0.4, 0.05), Vector3.new(0, 0.8, -0.72), rgb(230, 180, 50), Enum.Material.Metal)
		stencil(body, "$", rgb(230, 180, 50), { Enum.NormalId.Back })
	elseif look == "patient" then
		-- The patient on a stretcher under a blanket, the head toward the front (the ambulance's stretcher bay).
		local metal = rgb(186, 190, 196)
		local skins = { rgb(255, 214, 180), rgb(200, 150, 110), rgb(140, 95, 65), rgb(240, 190, 150) }
		block("Body", Vector3.new(2.2, 0.35, 5.2), Vector3.new(0, 1.3, 0), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
		block("Frame", Vector3.new(2.3, 0.15, 5.4), Vector3.new(0, 1.05, 0), metal, Enum.Material.Metal)
		for _, z in { -2.2, 2.2 } do
			block("Leg", Vector3.new(1.9, 0.75, 0.15), Vector3.new(0, 0.6, z), metal, Enum.Material.Metal)
			for _, x in { -0.85, 0.85 } do
				local wheel = block("Wheel", Vector3.new(0.4, 0.4, 0.4), Vector3.new(x, 0.2, z), rgb(40, 40, 44), Enum.Material.SmoothPlastic)
				wheel.Shape = Enum.PartType.Ball
			end
		end
		block("Blanket", Vector3.new(2.0, 0.5, 3.6), Vector3.new(0, 1.72, 0.6), rgb(70, 120, 190), Enum.Material.Fabric)
		for _, size in { Vector3.new(0.8, 0.04, 0.25), Vector3.new(0.25, 0.04, 0.8) } do
			block("Cross", size, Vector3.new(0, 1.98, 0.6), rgb(210, 30, 30), Enum.Material.SmoothPlastic)
		end
		block("Pillow", Vector3.new(1.5, 0.3, 0.9), Vector3.new(0, 1.62, -2.0), rgb(250, 250, 250), Enum.Material.Fabric)
		local head = block("Head", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 2.05, -1.9), skins[variant % #skins + 1], Enum.Material.SmoothPlastic)
		head.Shape = Enum.PartType.Ball
		local bandage = newPart(model, "Bandage", Vector3.new(0.3, 0.95, 0.95), CFrame.new(0, 2.25, -1.9) * UPRIGHT, rgb(250, 250, 248), Enum.Material.Fabric)
		bandage.Shape = Enum.PartType.Cylinder
	elseif look == "cake" then
		block("Body", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, 0.9, 0), rgb(250, 248, 245), Enum.Material.SmoothPlastic)
		local pink = rgb(240, 120, 170)
		block("Ribbon", Vector3.new(0.3, 1.82, 1.82), Vector3.new(0, 0.9, 0), pink, Enum.Material.Fabric)
		block("Ribbon", Vector3.new(1.82, 1.82, 0.3), Vector3.new(0, 0.9, 0), pink, Enum.Material.Fabric)
		block("Bow", Vector3.new(0.8, 0.3, 0.4), Vector3.new(0, 1.95, 0), pink, Enum.Material.Fabric)
	elseif look == "furniture" then
		local fabric = ({ rgb(150, 50, 50), rgb(60, 110, 80), rgb(60, 80, 140), rgb(170, 140, 100) })[variant % 4 + 1]
		local wood = rgb(110, 76, 46)
		local kind = variant % 6
		if kind == 0 then
			local body = cardboard(Vector3.new(2.2, 2, 2.2))
			stencil(body, "FRAGILE", rgb(200, 30, 30), FRONT_BACK)
		elseif kind == 1 then -- an armchair
			block("Seat", Vector3.new(2.4, 0.8, 2.2), Vector3.new(0, 0.9, 0), fabric, Enum.Material.Fabric)
			block("Back", Vector3.new(2.4, 1.8, 0.5), Vector3.new(0, 1.9, 0.85), fabric, Enum.Material.Fabric)
			for _, x in { -1.1, 1.1 } do
				block("Arm", Vector3.new(0.45, 1.0, 2.2), Vector3.new(x, 1.3, 0), fabric:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
				for _, z in { -0.9, 0.9 } do
					block("Leg", Vector3.new(0.25, 0.5, 0.25), Vector3.new(x, 0.25, z), wood, Enum.Material.Wood)
				end
			end
		elseif kind == 2 then -- a floor lamp
			cylinder("Base", 0.2, 1.2, 0.1, rgb(50, 50, 54), Enum.Material.Metal)
			block("Pole", Vector3.new(0.15, 3.2, 0.15), Vector3.new(0, 1.7, 0), rgb(50, 50, 54), Enum.Material.Metal)
			cylinder("Shade", 1, 1.4, 3.4, rgb(240, 225, 190), Enum.Material.Fabric)
		elseif kind == 3 then -- a television
			block("Body", Vector3.new(2.4, 1.6, 0.7), Vector3.new(0, 0.8, 0), rgb(30, 30, 34), Enum.Material.SmoothPlastic)
			block("Screen", Vector3.new(2.1, 1.3, 0.05), Vector3.new(0, 0.82, -0.36), rgb(25, 35, 50), Enum.Material.Glass)
		elseif kind == 4 then -- a chair
			block("Seat", Vector3.new(1.6, 0.25, 1.6), Vector3.new(0, 1.1, 0), wood, Enum.Material.Wood)
			block("Back", Vector3.new(1.6, 1.5, 0.25), Vector3.new(0, 1.95, 0.7), wood, Enum.Material.Wood)
			for _, x in { -0.65, 0.65 } do
				for _, z in { -0.65, 0.65 } do
					block("Leg", Vector3.new(0.22, 1.0, 0.22), Vector3.new(x, 0.5, z), wood, Enum.Material.Wood)
				end
			end
		else -- a potted plant
			cylinder("Pot", 1.1, 1.2, 0.55, rgb(170, 90, 60), Enum.Material.Slate)
			local leaves = block("Leaves", Vector3.new(1.9, 1.9, 1.9), Vector3.new(0, 1.9, 0), rgb(70, 130, 60), Enum.Material.Grass)
			leaves.Shape = Enum.PartType.Ball
		end
	elseif look == "kid" then
		-- A kid in the bus window: shoulders and a head.
		local shirts = { rgb(220, 60, 60), rgb(60, 120, 220), rgb(250, 200, 60), rgb(90, 180, 90), rgb(200, 100, 200) }
		local skins = { rgb(255, 214, 180), rgb(200, 150, 110), rgb(140, 95, 65), rgb(240, 190, 150) }
		block("Body", Vector3.new(1.1, 1.0, 0.6), Vector3.new(0, 0.5, 0), shirts[variant % #shirts + 1], Enum.Material.Fabric)
		local head = block("Head", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 1.45, 0), skins[variant % #skins + 1], Enum.Material.SmoothPlastic)
		head.Shape = Enum.PartType.Ball
		block("Hair", Vector3.new(0.92, 0.3, 0.92), Vector3.new(0, 1.8, 0.05), rgb(70, 45, 25), Enum.Material.Fabric)
	elseif not missionLook(model, look, variant) then
		crate(Vector3.new(2.2, 2, 2.2), rgb(163, 120, 74))
	end

	local main = model:FindFirstChildWhichIsA("BasePart")
	if main then
		model.PrimaryPart = main
		main.PivotOffset = main.CFrame:Inverse()
	end
	local size = model:GetExtentsSize()
	model:SetAttribute("Height", size.Y)
	model:SetAttribute("Depth", size.Z)
	return model
end

local function buildPiece(piece: Piece): Model
	local model = buildLook(piece.look, piece.variant)
	model.Parent = folder
	return model
end

local function unweld(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

-- Weld a piece to a part (the chassis, the carrier's root) with its pivot at `at`.
local function weldTo(model: Model, target: BasePart, at: CFrame)
	unweld(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(at)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			d.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = target
			weld.Part1 = d
			weld.Parent = d
		end
	end
end

-- Put a piece on the ground (anchored, solid: you walk around it).
local function setDown(model: Model, at: CFrame)
	unweld(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Massless = false
			d.CanCollide = d == model.PrimaryPart
		end
	end
	model:PivotTo(at)
	model.Parent = folder
end

-- A piece's height and depth (buildLook measured them).
local function pieceSize(model: Model): (number, number)
	local height = model:GetAttribute("Height")
	local depth = model:GetAttribute("Depth")
	return if type(height) == "number" then height else 2, if type(depth) == "number" then depth else 2
end

-- In front of the chest: one piece's middle at chest height, its back against the body; 3.7: two stacked, the first
-- at the bottom, the stack a little lower so you still see over it.
local function stackHeld(held: Held)
	local total, depth = 0, 0
	for _, piece in held.pieces do
		local model = piece.model
		if model then
			local h, d = pieceSize(model)
			total += h
			depth = math.max(depth, d)
		end
	end
	local y = 1.1 - total / 2 - (if #held.pieces > 1 then 0.25 else 0)
	for _, piece in held.pieces do
		local model = piece.model
		if model then
			weldTo(model, held.root, held.root.CFrame * CFrame.new(0, y, -(0.6 + depth / 2)))
			local h = pieceSize(model)
			y += h
		end
	end
end

local function prompt(parent: Instance, action: string, object: string, key: Enum.KeyCode?, hold: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key or Enum.KeyCode.E
	if key == Enum.KeyCode.G then
		p.GamepadKeyCode = Enum.KeyCode.ButtonB
	end
	p.HoldDuration = hold or Tuning.HoldDuration
	p.MaxActivationDistance = Tuning.PromptDistance
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- 3.3, Quick Hands: the hold of the job's pick-up / load / take-out / hand-over prompts follows the loading level of
-- the job's car (Vehicles.loadHold; the plain Config hold without a car).
local function holdFor(session: Session): number
	local car = session.car
	return if car then Vehicles.loadHold(car) else Tuning.HoldDuration
end

-- A horse's body part (prompts go there), if the horse has one.
local function horsePart(horse: Model): BasePart?
	return horse.PrimaryPart or horse:FindFirstChildWhichIsA("BasePart", true)
end

local function removeNpc(npc: Model?)
	if npc and npc.Parent then
		Npcs.remove(npc)
	end
end

local function say(npc: Model?, text: string)
	if npc and npc.Parent then
		Npcs.say(npc, text, 3)
	end
end

-- A person for this stop. Should the spawn yield and the job end or move on meanwhile, the person goes again (nil).
local function spawnFor(session: Session, look: Npcs.Look, at: CFrame): Model?
	local stop = session.stop
	session.busy += 1
	local npc = Npcs.spawn(look, at)
	session.busy -= 1
	if session.ended or session.stop ~= stop then
		npc:Destroy()
		return nil
	end
	return npc
end

local function isPatient(session: Session): boolean
	return session.info.kind == "patient"
end

local function isSurvivor(session: Session): boolean
	return session.info.kind == "survivor"
end

-- A cosmetic part welded onto a body part (no mass, no collisions, not hit by rays).
local function strap(npc: Model, on: BasePart, name: string, size: Vector3, offset: CFrame, shape: Enum.PartType?, color: Color3?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color or Color3.fromRGB(250, 250, 246)
	p.Material = Enum.Material.Fabric
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.CFrame = on.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = on
	weld.Part1 = p
	weld.Parent = p
	p.Parent = npc
end

-- A patient: a bandage round the head, an arm in a sling, and a slow shuffle.
local function dressPatient(npc: Model)
	local head = npc:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local h = math.min(head.Size.X, head.Size.Y, head.Size.Z)
		strap(npc, head, "Bandage", Vector3.new(h * 0.3, h * 1.1, h * 1.1), CFrame.new(0, h * 0.2, 0) * UPRIGHT, Enum.PartType.Cylinder)
	end
	local torso = npc:FindFirstChild("UpperTorso") or npc:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local t = torso.Size
		strap(npc, torso, "Sling", Vector3.new(t.X * 1.08, t.Y * 0.16, t.Z * 1.12), CFrame.Angles(0, 0, math.rad(38)))
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Tuning.PatientWalkSpeed
	end
end

-- Slows the walk animation Npcs.walkTo just started down to the patient's shuffle.
local function shuffle(npc: Model)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Animation and track.Animation.AnimationId == WALK_ANIMATION then
			track:AdjustSpeed(Tuning.PatientWalkSpeed / 11)
		end
	end
end

-- A survivor: a backpack with a rolled blanket, a smudge of dirt on the face. They walk at the normal pace.
local function dressSurvivor(npc: Model)
	local torso = npc:FindFirstChild("UpperTorso") or npc:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local t = torso.Size
		strap(npc, torso, "Backpack", Vector3.new(t.X * 0.8, t.Y * 0.9, 0.55), CFrame.new(0, 0, t.Z / 2 + 0.27), nil, Color3.fromRGB(62, 82, 52))
		strap(npc, torso, "Bedroll", Vector3.new(t.X * 0.9, 0.42, 0.42), CFrame.new(0, t.Y * 0.5 + 0.12, t.Z / 2 + 0.3), Enum.PartType.Cylinder, Color3.fromRGB(150, 60, 50))
	end
	local head = npc:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local h = head.Size
		strap(npc, head, "Dirt", Vector3.new(h.X * 0.3, h.Y * 0.18, 0.05), CFrame.new(h.X * 0.18, -h.Y * 0.15, -h.Z / 2 - 0.01), nil, Color3.fromRGB(96, 74, 52))
	end
end

-- A kid, a patient or a survivor of this piece, standing at `at`. Nil when the stop moved on meanwhile (spawnFor).
local function spawnRider(session: Session, piece: Piece, at: CFrame): Model?
	if isSurvivor(session) then
		local npc = spawnFor(session, Cargo.look("survivor", SURVIVOR_NAMES[piece.variant % #SURVIVOR_NAMES + 1], "Survivor"), at)
		if npc then
			dressSurvivor(npc)
		end
		return npc
	end
	if isPatient(session) then
		local npc = spawnFor(session, Cargo.look("patient", PATIENT_NAMES[piece.variant % #PATIENT_NAMES + 1], "Patient"), at)
		if npc then
			dressPatient(npc)
		end
		return npc
	end
	return spawnFor(session, Npcs.look("kid", KID_NAMES[piece.variant % #KID_NAMES + 1], nil), at)
end

-- ── The session ─────────────────────────────────────────────────────────────

local function newPiece(session: Session): Piece
	session.nextVariant += 1
	return { kind = session.info.kind, look = session.info.look, variant = session.nextVariant, origin = session.stop }
end

-- The pieces in hands (3.7: a player may hold two).
local function heldCount(session: Session): number
	local n = 0
	for _, held in session.held do
		n += #held.pieces
	end
	return n
end

-- 3.7: how many pieces of this job one player may hold: two of a light look, else one (a horse, a person, a lift or
-- pair job's piece).
local function handsMax(session: Session): number
	local info = session.info
	if info.kind == "horse" or info.lift or info.pair or Cargo.isPeople(info.kind) or not Tuning.LightLooks[info.look] then
		return 1
	end
	return math.max(1, Tuning.HandsMax)
end

-- The pieces this drop can still get: what it needs, or less when pieces were lost on the way.
local function neededNow(session: Session): number
	local plan = session.plan
	if not plan then
		return 0
	end
	if plan.stage == "pickup" then
		return plan.needed
	end
	return math.min(plan.needed, session.moved + #session.load + heldCount(session) + #session.loose + #session.walking)
end

-- The owner's car standing in the stop's circle.
local function parkedCar(session: Session): Vehicles.Car?
	local car = Vehicles.get(session.owner)
	local plan = session.plan
	if not car or not plan then
		return nil
	end
	if flat(car.chassis.Position, plan.park) > Config.Jobs.DeliverRadius or Vehicles.speed(car) > Config.Jobs.HoldMaxSpeed then
		return nil
	end
	return car
end

local function ownerPosition(session: Session): Vector3?
	local car = Vehicles.seatedIn(session.owner)
	if car then
		return car.chassis.Position
	end
	local root = rootOf(session.owner.Character)
	return if root then root.Position else nil
end

-- 3.2: the vehicle stands in the stop's circle (moving or not). Away from it the E at the back only opens and closes it.
local function atStop(session: Session): boolean
	local car = session.car
	local plan = session.plan
	return car ~= nil and plan ~= nil and flat(car.chassis.Position, plan.park) <= Config.Jobs.DeliverRadius
end

-- 3.2: does a piece still have to come out of the vehicle at this drop (not taken out, put down or handed over yet)?
-- Only at the stop: elsewhere (the drive there) the back has to close.
local function toTakeOut(session: Session): boolean
	local plan = session.plan
	if not plan or plan.stage ~= "drop" or (plan.mode ~= "carry" and plan.mode ~= "lead") or session.blocked or not atStop(session) then
		return false
	end
	return #session.load > 0 and session.moved + heldCount(session) + #session.loose < neededNow(session)
end

-- 3.2: the vehicle has a back that opens and it is closed (nothing goes in or out).
local function backShut(session: Session): boolean
	local car = session.car
	return car ~= nil and Vehicles.hasBack(car) and not Vehicles.backOpen(car)
end

-- 3.2: the vehicle's back is open.
local function backOpen(session: Session): boolean
	local car = session.car
	return car ~= nil and Vehicles.hasBack(car) and Vehicles.backOpen(car)
end

-- 3.2: has the back still a use at this stop (pieces to load or to take out, somebody carrying)? Else: close it.
local function backNeeded(session: Session): boolean
	local plan = session.plan
	if not plan or (plan.mode ~= "carry" and plan.mode ~= "lead") then
		return false
	end
	local busy = heldCount(session) > 0 or #session.loose > 0
	if plan.stage == "pickup" then
		return busy or not session.built or #session.pile > 0
	end
	return busy or (#session.load > 0 and session.moved < neededNow(session))
end

-- 3.2: who besides the owner may use the back right now (the job's crew), on the car for client/CarVisuals.luau:
-- the BackPrompt shows only to them, so a stranger's car does not take the E at a shared stop.
local function shareBack(session: Session, car: Vehicles.Car?)
	if not car or not car.model.Parent then
		return
	end
	local ids: { string } = {}
	if not session.ended then
		for _, player in Players:GetPlayers() do
			if player ~= session.owner and session.info.allowed(player) then
				table.insert(ids, tostring(player.UserId))
			end
		end
	end
	local list = if #ids > 0 then table.concat(ids, ",") else nil
	if car.model:GetAttribute("BackCrew") ~= list then
		car.model:SetAttribute("BackCrew", list)
	end
end

local function refresh(session: Session)
	local plan = session.plan
	local horse = session.info.kind == "horse"
	local carPrompt = session.carPrompt
	local car = session.car
	if carPrompt and car then
		local takeOut = toTakeOut(session)
		-- 3.2: only through an open back. 3.7: what you hold goes in at a pick-up (or a drop that has everything); at a
		-- drop that still needs it you carry it on (with one light piece in hand Take out gives you a second).
		local loadable = plan == nil or plan.stage == "pickup" or session.moved >= neededNow(session)
		carPrompt.Enabled = (takeOut or (heldCount(session) > 0 and loadable)) and not backShut(session)
		carPrompt.ActionText = if takeOut then (if horse then "Lead out" else "Take out") else (if horse then "Lead in" else "Load")
		carPrompt.ObjectText = `{capital(Vehicles.cargoNoun(car))}: {#session.load} inside`
	end
	-- 3.2: one E at the back at a time. A piece put down that goes into the vehicle is picked up again only once the
	-- back is open; the BackPrompt (the same spot as the Load prompt) waits while the Load / Take out prompt or such a
	-- piece has something to do.
	local intoCar = plan ~= nil and (plan.stage == "pickup" or session.moved >= neededNow(session))
	local shut = backShut(session)
	for _, loose in session.loose do
		loose.prompt.Enabled = not (intoCar and shut)
	end
	local backPrompt = car and Vehicles.backPrompt(car)
	if backPrompt then
		backPrompt.Enabled = not (carPrompt ~= nil and carPrompt.Enabled) and not (intoCar and not shut and #session.loose > 0)
	end
	local pilePrompt = session.pilePrompt
	if pilePrompt and plan then
		if plan.stage == "pickup" then
			pilePrompt.Enabled = #session.pile > 0 and not session.blocked
			pilePrompt.ObjectText = `{capital(if horse then "horse" else session.info.piece)} ({#session.pile} left)`
		else
			pilePrompt.Enabled = session.moved < neededNow(session) and not session.blocked
			pilePrompt.ObjectText = if plan.person then plan.person.name else "Receiver"
		end
	end
end

-- Show the load in the vehicle: every piece in its slot (the horses in their stalls).
local function render(session: Session)
	for _, model in session.shown do
		model:Destroy()
	end
	table.clear(session.shown)
	local car = session.car
	if not car or car.wrecked then
		-- No vehicle any more: the horses still loaded stand on the ground, not welded to a wreck about to go.
		for _, piece in session.load do
			local horse = piece.horse
			if horse and horse.Parent then
				local at = horse:GetPivot()
				Animals.stable(horse, CFrame.new(onGround(at.Position)) * at.Rotation)
			end
		end
		return
	end
	car.model:SetAttribute("CargoCount", #session.load)
	car.model:SetAttribute("CargoKind", if #session.load > 0 then session.info.kind else nil)
	local slots = Vehicles.cargoSlots(car)
	for index, piece in session.load do
		local slot = slots[index]
		local horse = piece.horse
		if horse then
			local stall = slot or slots[#slots]
			if stall then
				Animals.stable(horse, car.chassis.CFrame * stall, car.chassis)
			end
		elseif #slots > 0 then
			-- More pieces than slots: the extra ones ride on top.
			local layer = (index - 1) // #slots
			local base = slots[(index - 1) % #slots + 1]
			local model = buildLook(piece.look, piece.variant)
			local _, size = model:GetBoundingBox()
			weldTo(model, car.chassis, car.chassis.CFrame * base * CFrame.new(0, layer * size.Y, 0))
			model.Parent = car.model
			table.insert(session.shown, model)
		end
	end
end

-- The lift twist (Info.lift): a heavy piece carried alone slows the carrier down. The character attribute CarrySpeed
-- tells the client's walk (client/CameraRig.luau) the speed; the server's WalkSpeed is set too, as a fallback.
local function restoreSpeed(session: Session, player: Player)
	local character = session.slowed[player]
	if not character then
		return
	end
	session.slowed[player] = nil
	character:SetAttribute("CarrySpeed", nil)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and character.Parent then
		humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
	end
end

-- Is somebody else of the job (the owner or a crew mate), alive and on foot, within `range` of `at`?
local function partnerNear(session: Session, player: Player, at: Vector3, range: number): boolean
	for _, other in Players:GetPlayers() do
		if other ~= player and session.info.allowed(other) then
			local root = rootOf(other.Character)
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and humanoid.SeatPart == nil and (root.Position - at).Magnitude <= range then
				return true
			end
		end
	end
	return false
end

-- Is somebody else of the job close enough to help carry a heavy piece (the lift twist)?
local function liftHelped(session: Session, player: Player, at: Vector3): boolean
	return partnerNear(session, player, at, Config.Missions.LiftHelpRange)
end

-- 3.2, the pair twist (Info.pair): a piece (not a horse) only moves with somebody else of the job within PairRange.
-- True (and the player told) when this player may not lift one now.
local function pairRefused(session: Session, player: Player): boolean
	if not session.info.pair or session.info.kind == "horse" then
		return false
	end
	local root = rootOf(player.Character)
	if root and partnerNear(session, player, root.Position, Config.Missions.Duo.PairRange) then
		return false
	end
	tell(player, "Pair lift: you need your partner on the other side.")
	return true
end

-- Every tick: who carries a heavy piece alone walks at LiftSlowSpeed, with help at the normal step.
local function updateLift(session: Session)
	for player, held in session.held do
		local alone = held.pieces[1].horse == nil and not liftHelped(session, player, held.root.Position)
		if alone and session.slowed[player] ~= held.character then
			restoreSpeed(session, player)
			session.slowed[player] = held.character
			held.character:SetAttribute("CarrySpeed", Config.Missions.LiftSlowSpeed)
			local humanoid = held.character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = Config.Missions.LiftSlowSpeed
			end
			if not session.liftTold then
				session.liftTold = true
				tell(player, `Heavy! Alone you can barely walk. Get a crew mate within {Config.Missions.LiftHelpRange} studs to carry it faster.`)
			end
		elseif not alone and session.slowed[player] then
			restoreSpeed(session, player)
		end
	end
end

local function clearHeld(session: Session, player: Player): Held?
	local held = session.held[player]
	restoreSpeed(session, player)
	if not held then
		return nil
	end
	session.held[player] = nil
	local character = held.character
	if character.Parent then
		character:SetAttribute("Carrying", nil)
		character:SetAttribute("CarryCount", nil)
		character:SetAttribute("CarryHands", nil)
		character:SetAttribute("CarrySpeed", nil)
	end
	if held.prompt then
		held.prompt:Destroy()
	end
	return held
end

local onLoose: (Session, Player, Loose) -> ()
local putDown: (Session, Player, boolean?) -> ()

-- 3.7: the hands changed: the pieces stacked, the Put down (Let go) prompt on the top one, the character's attributes
-- (Carrying = the kind, CarryCount, CarryHands = 1 while a light piece leaves a hand free, CarrySpeed with two).
local function armHands(session: Session, player: Player, held: Held)
	if held.prompt then
		held.prompt:Destroy()
		held.prompt = nil
	end
	local count = #held.pieces
	local top = held.pieces[count]
	local made: ProximityPrompt? = nil
	local horse = top.horse
	if horse then
		local part = horsePart(horse)
		if part then
			local letGo = prompt(part, "Let go", "Horse", Enum.KeyCode.G, 0)
			letGo.MaxActivationDistance = 13 -- the horse walks ~9 studs behind
			made = letGo
		end
	else
		stackHeld(held)
		local main = top.model and top.model.PrimaryPart
		if main then
			local down = prompt(main, if count > 1 then "Put one down" else "Put down", capital(session.info.piece), Enum.KeyCode.G, 0)
			down.MaxActivationDistance = 4 -- only for the one holding it
			made = down
		end
	end
	if made then
		held.prompt = made
		made.Triggered:Connect(function(by)
			if by == player and session.held[player] == held then
				putDown(session, player)
				session.info.changed()
			end
		end)
	end
	local character = held.character
	character:SetAttribute("Carrying", top.kind)
	character:SetAttribute("CarryCount", count)
	character:SetAttribute("CarryHands", if count == 1 and handsMax(session) > 1 then 1 else 2)
	if not session.info.lift then
		character:SetAttribute("CarrySpeed", if count > 1 then Tuning.TwoPieceSpeed else nil)
	end
end

-- 3.7: the top piece leaves the hands (the last one: the hands are empty again). Returns it, still where it was.
local function release(session: Session, player: Player): Piece?
	local held = session.held[player]
	if not held then
		return nil
	end
	local piece = table.remove(held.pieces)
	if #held.pieces == 0 then
		clearHeld(session, player)
	else
		armHands(session, player, held)
	end
	return piece
end

-- Into the hands (or on the rope); 3.7: a second light piece goes on top of the first. False when it does not fit.
local function take(session: Session, player: Player, piece: Piece): boolean
	local character = player.Character
	local root = rootOf(character)
	if not character or not root then
		return false
	end
	local existing = session.held[player]
	if existing and (existing.character ~= character or piece.horse or existing.pieces[1].horse or #existing.pieces >= handsMax(session)) then
		return false
	end
	local horse = piece.horse
	if horse then
		Animals.stable(horse, nil)
		Animals.lead(horse, character)
	else
		local model = piece.model or buildPiece(piece)
		piece.model = model
		model.Parent = folder
	end
	local held: Held = existing or { pieces = {}, character = character, root = root, prompt = nil, last = root.CFrame }
	session.held[player] = held
	table.insert(held.pieces, piece)
	armHands(session, player, held)
	refresh(session)
	return true
end

-- 3.7: where a piece put down goes: in front of where the carrier stood, beside the ones already lying there.
local function dropFrame(session: Session, last: CFrame): CFrame
	local look = last.LookVector
	local ahead = Vector3.new(look.X, 0, look.Z)
	local spot = last.Position
	for _, side in { 0, 2.4, -2.4, 4.8 } do
		local front = last * CFrame.new(side, 0, -2.2)
		spot = onGround(Vector3.new(front.Position.X, last.Position.Y - 3, front.Position.Z))
		local free = true
		for _, loose in session.loose do
			local model = loose.piece.model
			if model and model.Parent and flat(model:GetPivot().Position, spot) < 1.8 then
				free = false
				break
			end
		end
		if free then
			break
		end
	end
	return CFrame.lookAt(spot, spot + ahead)
end

-- Drop what the player holds right where they are; anybody of the crew can pick it up again. 3.7: one piece (the top
-- one: G again for the next), or all of them (`all`: the carrier died, left, sat down, lost the partner).
putDown = function(session: Session, player: Player, all: boolean?)
	local held = session.held[player]
	if not held then
		return
	end
	local last = held.last
	for _ = 1, if all then #held.pieces else 1 do
		local piece = release(session, player)
		if not piece then
			break
		end
		local frame = dropFrame(session, last)
		local loose: Loose
		local horse = piece.horse
		if horse then
			Animals.lead(horse, nil)
			local at = horse:GetPivot().Position
			local handle = Instance.new("Part")
			handle.Name = "LooseHorse"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Transparency = 1
			handle.Anchored = true
			handle.CanCollide = false
			handle.CanQuery = false
			handle.CanTouch = false
			handle.Position = if at.Magnitude > 0 then at + Vector3.new(0, 3, 0) else frame.Position + Vector3.new(0, 3, 0)
			handle.Parent = folder
			loose = { piece = piece, prompt = prompt(handle, "Lead", "Horse", nil, holdFor(session)), handle = handle }
		else
			local model = piece.model or buildPiece(piece)
			piece.model = model
			setDown(model, frame)
			local main = model.PrimaryPart :: BasePart
			loose = { piece = piece, prompt = prompt(main, "Pick up", capital(session.info.piece), nil, holdFor(session)), handle = nil }
		end
		loose.prompt.Triggered:Connect(function(by)
			onLoose(session, by, loose)
		end)
		table.insert(session.loose, loose)
	end
	refresh(session)
end

local function allowed(session: Session, player: Player): boolean
	if session.ended then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		tell(player, "Get out first.")
		return false
	end
	if session.info.allowed(player) then
		return true
	end
	tell(player, "This is not your delivery.")
	return false
end

-- 3.2, the pair twist, every tick: a carrier whose partner is gone for longer than PAIR_GRACE puts the piece down.
-- True when a piece went down.
local function updatePair(session: Session): boolean
	local now = os.clock()
	local dropped = false
	for player, held in table.clone(session.held) do
		if held.pieces[1].horse or partnerNear(session, player, held.root.Position, Config.Missions.Duo.PairRange) then
			session.pairAlone[player] = nil
		elseif not session.pairAlone[player] then
			session.pairAlone[player] = now
		elseif now - session.pairAlone[player] > PAIR_GRACE then
			session.pairAlone[player] = nil
			putDown(session, player, true)
			dropped = true
			tell(player, `Your partner is gone: you put the {session.info.piece} down. Pair lift: carry it together!`)
		end
	end
	for player in table.clone(session.pairAlone) do
		if not session.held[player] then
			session.pairAlone[player] = nil
		end
	end
	return dropped
end

-- Can the player not take another piece of this job (3.7: one light piece in hand leaves room for a second)?
local function handsFull(session: Session, player: Player): boolean
	local held = session.held[player]
	if held then
		if #held.pieces < handsMax(session) then
			return false
		end
		tell(player, if #held.pieces > 1 then `Your hands are full: two {session.info.plural}.` else "Your hands are full.")
		return true
	end
	if not Cargo.carrying(player.Character) then
		return false
	end
	tell(player, "Your hands are full.")
	return true
end

onLoose = function(session: Session, player: Player, loose: Loose)
	if not allowed(session, player) or handsFull(session, player) or pairRefused(session, player) then
		return
	end
	if not table.find(session.loose, loose) or not take(session, player, loose.piece) then
		return -- (3.7: a piece that does not fit the hands stays where it lies)
	end
	local index = table.find(session.loose, loose)
	if index then
		table.remove(session.loose, index)
	end
	loose.prompt:Destroy()
	if loose.handle then
		loose.handle:Destroy()
	end
	refresh(session)
	session.info.changed()
end

-- Where the receiver puts the delivered pieces: a neat stack at their left.
local function stackFrame(plan: Plan, index: number, side: number): CFrame
	local right = plan.facing:Cross(Vector3.yAxis)
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	local spot = plan.pile + right * side * (3 + col * 2.8) - plan.facing * (row * 2.8 + 0.5)
	spot = onGround(spot)
	return CFrame.lookAt(spot, spot + plan.facing) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
end

local function handOver(session: Session, player: Player)
	local plan = session.plan
	if not plan then
		return
	end
	local everything = `{if plan.person then plan.person.name else "They"} has everything. Put it back in the vehicle.`
	if session.moved >= neededNow(session) then
		tell(player, everything)
		return
	end
	-- 3.7: everything in your hands goes (two light pieces at once), as many as they still need.
	local gave = 0
	while session.held[player] and session.moved < neededNow(session) do
		local piece = release(session, player)
		if not piece then
			break
		end
		gave += 1
		session.moved += 1
		session.deliveredTotal += 1
		local horse = piece.horse
		if horse then
			-- The receiver takes the rope: the horse walks over to the paddock behind them.
			Animals.lead(horse, nil)
			local right = plan.facing:Cross(Vector3.yAxis)
			local paddock = plan.pile - plan.facing * 9 + right * (session.moved * 5 - 7)
			Animals.walkTo(horse, onGround(paddock))
			table.insert(session.propHorses, horse)
		else
			local model = piece.model or buildPiece(piece)
			piece.model = nil
			setDown(model, stackFrame(plan, session.moved, -1))
			table.insert(session.props, model)
		end
	end
	if gave == 0 then
		return
	end
	say(session.person, if session.moved >= neededNow(session) then line(LINES.done) else line(LINES.thanks))
	if session.held[player] then
		tell(player, everything)
	end
	refresh(session)
end

-- What to tell while the stop is blocked (Cargo.setBlocked).
local function blockedText(session: Session): string
	return session.blockedReason or "Hold out first! Nothing gets unloaded until the area is safe."
end

local function onPile(session: Session, player: Player)
	local plan = session.plan
	if not plan or not allowed(session, player) then
		return
	end
	if session.blocked then
		tell(player, blockedText(session))
		return
	end
	if plan.stage == "drop" then
		if not session.held[player] then
			local car = session.car
			tell(player, `Take {article(session.info.piece)} out of the {if car then Vehicles.cargoNoun(car) else "vehicle"} first (E at the back).`)
			return
		end
		handOver(session, player)
		session.info.changed()
		return
	end
	if handsFull(session, player) or pairRefused(session, player) then
		return
	end
	local piece = table.remove(session.pile)
	if not piece then
		return
	end
	if take(session, player, piece) then
		say(session.person, if piece.horse then line(LINES.horse) else line(LINES.take))
	else
		table.insert(session.pile, piece)
	end
	session.info.changed()
end

-- The back of the vehicle: load what you hold, or take a piece out at a drop. 3.7: everything in your hands goes in
-- at once; at a drop with one light piece in hand you take out a second.
local function onCar(session: Session, player: Player)
	local plan = session.plan
	local car = session.car
	if not car or car.wrecked or not allowed(session, player) then
		return
	end
	if Vehicles.speed(car) > Tuning.MaxCarSpeed then
		tell(player, "Stop the vehicle first.")
		return
	end
	local held = session.held[player]
	if backShut(session) then
		-- 3.2: only through an open back (a race with somebody closing it). 3.7: a light piece leaves a hand free.
		local open = Vehicles.backVerb(car, true)
		local full = held ~= nil and (#held.pieces > 1 or handsMax(session) == 1)
		tell(player, if full then `Put it down (G) and {open} (E).` else `{capital(open)} first (E).`)
		return
	end
	local handling = plan ~= nil and plan.stage == "drop" and (plan.mode == "carry" or plan.mode == "lead")
	if held and (not handling or session.moved >= neededNow(session)) then
		clearHeld(session, player)
		local before = session.moved
		for _, piece in held.pieces do
			local horse = piece.horse
			if horse then
				Animals.lead(horse, nil)
			elseif piece.model then
				piece.model:Destroy()
				piece.model = nil
			end
			table.insert(session.load, piece)
			if plan and plan.stage == "pickup" and piece.origin == session.stop then
				session.moved += 1
			end
		end
		if plan and plan.stage == "pickup" and before < plan.needed and session.moved >= plan.needed then
			say(session.person, line(LINES.loaded))
		end
		render(session)
		refresh(session)
		session.info.changed()
		return
	end
	if handling and plan then
		if session.blocked then
			tell(player, blockedText(session))
			return
		end
		if not atStop(session) then
			tell(player, "Drive to the stop first.")
			return
		end
		local who = if plan.person then plan.person.name else "the receiver"
		if #session.load == 0 then
			tell(player, `The {Vehicles.cargoNoun(car)} is empty.`)
			return
		end
		if held and #held.pieces >= handsMax(session) then
			tell(player, `Hands full: carry {if #held.pieces > 1 then "them" else "it"} to {who} (E).`)
			return
		end
		if not toTakeOut(session) then
			tell(player, `{capital(who)} gets no more: carry what you have.`)
			return
		end
		if pairRefused(session, player) then
			return
		end
		local piece = table.remove(session.load) :: Piece
		render(session)
		local horse = piece.horse
		if horse then
			-- Down the ramp: the horse stands behind the truck, on the rope.
			Animals.stable(horse, nil)
			local behind = (car.chassis.CFrame * CFrame.new(0, 0, car.size.Z / 2 + 5)).Position
			local spot = onGround(Vector3.new(behind.X, car.chassis.Position.Y - 2, behind.Z))
			Animals.stable(horse, CFrame.lookAt(spot, spot + car.chassis.CFrame.LookVector)) -- hooves at spot, anchored
		end
		if not take(session, player, piece) then
			table.insert(session.load, piece)
			render(session)
		end
		session.info.changed()
		return
	end
	tell(player, `Pick up {article(session.info.piece)} first.`)
end

local function attachCar(session: Session, old: Vehicles.Car?)
	if session.carPrompt then
		session.carPrompt:Destroy()
		session.carPrompt = nil
	end
	local oldBack = old and Vehicles.backPrompt(old)
	if oldBack then
		oldBack.Enabled = true -- not this job's car any more: its back opens and closes freely
	end
	local car = session.car
	if not car or not session.info.handles then
		return
	end
	local door = Vehicles.cargoDoor(car)
	if not door then
		return
	end
	local p = prompt(door, "Load", "", nil, holdFor(session))
	p.MaxActivationDistance = 9
	p.Triggered:Connect(function(player)
		onCar(session, player)
	end)
	session.carPrompt = p
	refresh(session)
end

-- The stop's people and pieces: built when the owner gets close.
local function build(session: Session)
	local plan = session.plan
	if not plan or session.built then
		return
	end
	session.built = true
	local base = onGround(plan.pile)
	local right = plan.facing:Cross(Vector3.yAxis)
	if plan.person then
		local npc = spawnFor(session, plan.person, CFrame.lookAt(base, base + plan.facing))
		if not npc then
			return
		end
		session.person = npc
		table.insert(session.props, npc)
	end
	if plan.mode == "carry" or plan.mode == "lead" then
		local part = Instance.new("Part")
		part.Name = "CargoPile"
		part.Size = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Position = base + right * 1.5 + Vector3.new(0, 2.5, 0)
		part.Parent = folder
		session.pilePart = part
		table.insert(session.props, part)
		local horse = plan.mode == "lead"
		local action = if plan.stage == "pickup" then (if horse then "Lead" else "Pick up") else "Hand over"
		local p = prompt(part, action, "", nil, holdFor(session))
		p.MaxActivationDistance = Tuning.PromptDistance + 2
		p.Triggered:Connect(function(player)
			onPile(session, player)
		end)
		session.pilePrompt = p
	end
	if plan.stage ~= "pickup" then
		refresh(session)
		return
	end
	for n = 1, plan.needed do
		local piece = newPiece(session)
		if plan.mode == "carry" then
			local model = buildPiece(piece)
			setDown(model, stackFrame(plan, n, 1))
			piece.model = model
		elseif plan.mode == "lead" then
			local spot = onGround(base + right * (4 + (n - 1) * 4.5) - plan.facing * 3)
			piece.horse = Animals.horse(CFrame.lookAt(spot, spot + plan.facing))
		elseif plan.mode == "board" then
			local spot = onGround(base + right * (1.5 + n * 1.8) - plan.facing * 0.5)
			piece.npc = spawnRider(session, piece, CFrame.lookAt(spot, spot + plan.facing))
			if not piece.npc then
				return
			end
		end
		table.insert(session.pile, piece)
	end
	refresh(session)
end

-- Removes what the stop left in the world (people, delivered pieces, the pile); `linger` leaves them a moment.
local function clearStop(session: Session, linger: boolean)
	local props = session.props
	local horses = session.propHorses
	local npcs: { Model } = {}
	local models: { Instance } = {}
	for _, piece in session.pile do
		if piece.horse then
			table.insert(horses, piece.horse)
		end
		if piece.npc then
			table.insert(npcs, piece.npc)
		end
		if piece.model then
			table.insert(models, piece.model)
		end
	end
	for _, piece in session.walking do
		if piece.npc then
			table.insert(npcs, piece.npc)
		end
	end
	session.props = {}
	session.propHorses = {}
	session.pile = {}
	session.walking = {}
	session.person = nil
	session.pilePart = nil
	session.pilePrompt = nil
	local function destroy()
		for _, instance in props do
			if instance:IsA("Model") and instance.Parent and instance:FindFirstChildOfClass("Humanoid") then
				removeNpc(instance)
			else
				instance:Destroy()
			end
		end
		for _, npc in npcs do
			removeNpc(npc)
		end
		for _, model in models do
			model:Destroy()
		end
		for _, horse in horses do
			if horse.Parent then
				Animals.remove(horse)
			end
		end
	end
	if linger then
		-- The prompts go now, the people stay a moment (the receiver says thanks while you drive off).
		for _, instance in props do
			for _, d in instance:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					d:Destroy()
				end
			end
		end
		task.delay(Tuning.Linger, destroy)
	else
		destroy()
	end
end

-- ── Kids, patients and customers ───────────────────────────────────────────

local function kidArrived(session: Session, piece: Piece, stop: number, timedOut: boolean)
	local index = table.find(session.walking, piece)
	if session.ended or session.stop ~= stop or not index then
		return
	end
	local plan = session.plan
	if not plan then
		return
	end
	if plan.stage == "pickup" then
		local car = parkedCar(session)
		local npc = piece.npc
		local close = car ~= nil and npc ~= nil and npc.Parent ~= nil and flat(npc:GetPivot().Position, Vehicles.cargoEntry(car)) < 9
		if not car or not (close or timedOut) then
			-- The bus is not there (any more): wait where you are.
			table.remove(session.walking, index)
			piece.walkingSince = nil
			table.insert(session.pile, piece)
			return
		end
		table.remove(session.walking, index)
		removeNpc(npc)
		piece.npc = nil
		table.insert(session.load, piece)
		session.moved += 1
		render(session)
	else
		table.remove(session.walking, index)
		removeNpc(piece.npc)
		piece.npc = nil
		session.moved += 1
		session.deliveredTotal += 1
		if session.moved >= neededNow(session) then
			say(session.person, if isPatient(session) then "We'll take it from here. You saved a life!"
				elseif isSurvivor(session) then "Everybody inside! You're safe now."
				else "Good morning, everybody! Inside, quick!")
		end
	end
	session.info.changed()
end

local function walkKid(session: Session, piece: Piece, target: Vector3)
	local npc = piece.npc
	if not npc then
		return
	end
	piece.walkingSince = os.clock()
	table.insert(session.walking, piece)
	local stop = session.stop
	Npcs.walkTo(npc, target, function(ok: boolean)
		-- Could not get there in time (a curb, a car in the way): close enough, count it.
		kidArrived(session, piece, stop, not ok)
	end, if isPatient(session) then Tuning.PatientWalkTimeout else Tuning.WalkTimeout)
	if isPatient(session) then
		shuffle(npc)
	end
end

local function updateBoard(session: Session, plan: Plan, now: number)
	-- Walkers who never arrive (stuck on a curb) count as arrived after a while.
	for _, piece in table.clone(session.walking) do
		local timeout = if isPatient(session) then Tuning.PatientWalkTimeout else Tuning.WalkTimeout
		if piece.walkingSince and now - piece.walkingSince > timeout + 1 then
			kidArrived(session, piece, session.stop, true)
		end
	end
	local car = parkedCar(session)
	if not car or now < session.nextKid or session.blocked then
		return
	end
	if plan.stage == "pickup" then
		local piece = table.remove(session.pile, 1)
		if piece then
			session.nextKid = now + Tuning.KidGap
			if session.moved == 0 and #session.walking == 0 then
				say(session.person, if isPatient(session) then "There's the ambulance! Easy now, one step at a time."
					elseif isSurvivor(session) then "That's our ride! Go, go, go!"
					else "There's the bus! Off you go.")
			end
			if piece.npc then
				say(piece.npc, line(if isPatient(session) then LINES.patientOn elseif isSurvivor(session) then LINES.survivorOn else LINES.kidOn))
			end
			walkKid(session, piece, Vehicles.cargoEntry(car))
		end
	elseif session.moved + #session.walking < neededNow(session) then
		local piece = table.remove(session.load)
		if piece then
			session.nextKid = now + Tuning.KidGap
			render(session)
			local door = Vehicles.cargoEntry(car)
			local spot = onGround(door)
			piece.npc = spawnRider(session, piece, CFrame.lookAt(spot, Vector3.new(plan.pile.X, spot.Y, plan.pile.Z)))
			if not piece.npc then
				table.insert(session.load, piece)
				return
			end
			say(piece.npc, line(if isPatient(session) then LINES.patientOff elseif isSurvivor(session) then LINES.survivorOff else LINES.kidOff))
			walkKid(session, piece, onGround(plan.pile))
			session.info.changed()
		end
	end
end

local function updateServe(session: Session, plan: Plan, dt: number)
	if session.blocked then
		return
	end
	local car = parkedCar(session)
	local holding = car ~= nil and Vehicles.isDriving(session.owner)
	if not holding or not car then
		if session.hold > 0 then
			session.hold = 0
			session.info.changed()
		end
		return
	end
	if not session.customers then
		-- Two kids come to the serving window (the right side).
		session.customers = true
		for n, z in { 0.5, 3.5 } do
			local spot = onGround((car.chassis.CFrame * CFrame.new(car.size.X / 2 + 2.6, 0, z)).Position)
			local npc = spawnFor(session, Npcs.look("kid", KID_NAMES[rng:NextInteger(1, #KID_NAMES)], nil), CFrame.lookAt(spot, spot - car.chassis.CFrame.RightVector))
			if not npc then
				return
			end
			table.insert(session.props, npc)
			task.delay(n * 0.6, say, npc, line(LINES.customer))
		end
	end
	session.hold += dt
	session.info.changed()
	if session.hold >= plan.hold and not session.served then
		session.served = true
		while #session.load > plan.keep do
			local piece = table.remove(session.load)
			if piece and piece.model then
				piece.model:Destroy()
			end
			session.deliveredTotal += 1
		end
		session.moved = plan.needed
		render(session)
	end
end

-- ── API (server/Jobs.luau) ─────────────────────────────────────────────────

function Cargo.begin(owner: Player, info: Info): Session
	local session: Session = {
		owner = owner,
		info = info,
		load = {},
		held = {},
		loose = {},
		lost = 0,
		deliveredTotal = 0,
		nextVariant = rng:NextInteger(0, 11),
		plan = nil,
		stop = 0,
		built = false,
		greeted = false,
		pile = {},
		walking = {},
		moved = 0,
		hold = 0,
		served = false,
		customers = false,
		nextKid = 0,
		person = nil,
		pilePart = nil,
		pilePrompt = nil,
		props = {},
		propHorses = {},
		car = nil,
		carPrompt = nil,
		shown = {},
		ended = false,
		busy = 0,
		blocked = false,
		blockedReason = nil,
		pairAlone = {},
		slowed = {},
		liftTold = false,
		atStop = false,
	}
	active[owner] = session
	return session
end

-- The defend twist (server/Jobs.luau): while blocked, nothing is unloaded at the current stop (no Take out, no Hand
-- over, the passengers stay in, no serving); the stop is not done. 3.2: a pick-up can be blocked too (nothing is
-- picked up, nobody gets on: the DUO switches twist, server/DuoGates.luau), and `reason` is what the players are told
-- (the HUD's hint near the stop; nil: the defend twist's "Hold out first!").
function Cargo.setBlocked(session: Session, blocked: boolean, reason: string?)
	local text = if blocked then reason else nil
	if session.blocked == blocked and session.blockedReason == text then
		return
	end
	session.blocked = blocked
	session.blockedReason = text
	refresh(session)
	session.info.changed()
end

-- Pieces that start in the vehicle (an ice cream truck that starts loaded, the admin tools).
function Cargo.fill(session: Session, count: number)
	for _ = 1, count do
		table.insert(session.load, newPiece(session))
	end
	render(session)
	refresh(session)
end

-- The next stop; the last one's people stay a moment.
function Cargo.setStop(session: Session, plan: Plan)
	if session.plan then
		clearStop(session, true)
	end
	session.stop += 1
	session.plan = plan
	session.built = false
	session.greeted = false
	session.moved = 0
	session.hold = 0
	session.served = false
	session.customers = false
	session.nextKid = 0
	refresh(session)
end

-- Every job tick (Jobs, 0.2 s): follow the car, check the carriers, build the stop, walk the kids, serve.
function Cargo.update(session: Session, dt: number)
	if session.ended then
		return
	end
	local car = Vehicles.get(session.owner)
	if car ~= session.car then
		local old = session.car
		session.car = car
		attachCar(session, old)
		render(session)
		if old then
			old.model:SetAttribute("BackCrew", nil)
		end
	end
	shareBack(session, car)

	-- Dead, gone, sitting, out of the crew: the piece falls where it was.
	local dropped = false
	for player, held in table.clone(session.held) do
		local character = held.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = rootOf(character)
		local fine = player.Parent ~= nil and player.Character == character and humanoid ~= nil and humanoid.Health > 0 and root ~= nil and humanoid.SeatPart == nil
			and session.info.allowed(player) -- left or was removed from the crew: put it down
		if fine and root then
			if root ~= held.root then
				-- The body was rebuilt (the avatar loaded): hold it in the new one.
				held.root = root
				if held.pieces[1].horse == nil then
					stackHeld(held)
				end
			end
			held.last = root.CFrame
		else
			putDown(session, player, true)
			dropped = true
		end
	end
	if session.info.pair and updatePair(session) then
		dropped = true
	end
	if dropped then
		session.info.changed()
	end
	if session.info.lift then
		updateLift(session)
	end

	local plan = session.plan
	if not plan then
		return
	end
	-- 3.2: arriving at / leaving the stop switches the E at the back between Take out and the doors.
	local here = atStop(session)
	if here ~= session.atStop then
		session.atStop = here
		refresh(session)
	end
	local position = ownerPosition(session)
	if not session.built and position and flat(position, plan.park) < Tuning.SpawnDistance then
		build(session)
	end
	if session.built and not session.greeted and position and flat(position, plan.pile) < 45 then
		session.greeted = true
		local handling = plan.mode == "carry" or plan.mode == "lead"
		if plan.stage == "pickup" and handling then
			say(session.person, if plan.needed == 1 then `Over here! One {session.info.piece}, handle it with care.` else `Over here! {plan.needed} {session.info.plural} to load.`)
		elseif plan.stage == "drop" and handling then
			say(session.person, "Finally! Bring it over here.")
		elseif plan.mode == "board" and isPatient(session) then
			say(session.person, if plan.stage == "pickup" then "Over here! Please hurry, it's bad." else "Bring the patient to me, quick!")
		elseif plan.mode == "board" and isSurvivor(session) then
			say(session.person, if plan.stage == "pickup" then "Over here! We've been holding out for days!" else "Bring them in, we've got beds ready!")
		end
	end
	if plan.mode == "board" then
		updateBoard(session, plan, os.clock())
	elseif plan.mode == "serve" then
		updateServe(session, plan, dt)
	end
end

-- Is the current stop done (everything loaded / handed over / served)?
function Cargo.stopDone(session: Session): boolean
	local plan = session.plan
	if not plan or session.busy > 0 or session.blocked then
		return false
	end
	if plan.mode == "serve" then
		return session.served
	end
	if #session.walking > 0 then
		return false
	end
	if plan.stage == "pickup" then
		return session.built and session.moved >= plan.needed and #session.pile == 0 and heldCount(session) == 0 and #session.loose == 0
	end
	return session.moved >= neededNow(session)
end

-- Pieces still somewhere on the way (in the vehicle, in hands, put down, at the current pile, walking).
function Cargo.remaining(session: Session): number
	local pile = #session.pile
	local plan = session.plan
	if plan and plan.stage == "pickup" and (not session.built or session.busy > 0) then
		pile = math.max(pile, plan.needed)
	end
	local spawning = if plan and plan.stage ~= "pickup" then session.busy else 0 -- a kid getting off right now
	return #session.load + heldCount(session) + #session.loose + pile + #session.walking + spawning
end

-- Bandits at the car carry a piece off (not the kids or a patient). Returns the piece's name, or nil.
function Cargo.steal(session: Session): string?
	if Cargo.isPeople(session.info.kind) or #session.load == 0 then
		return nil
	end
	local piece = table.remove(session.load) :: Piece
	if piece.horse then
		Animals.remove(piece.horse)
	end
	session.lost += 1
	render(session)
	refresh(session)
	session.info.changed()
	return session.info.piece
end

-- A wreck: `share` of the load is ruined (at least one piece). The rest moves to the next vehicle. Returns how many.
function Cargo.wreck(session: Session, share: number): number
	if Cargo.isPeople(session.info.kind) or #session.load == 0 then
		return 0
	end
	local count = math.clamp(math.floor(#session.load * share + 0.5), 1, #session.load)
	for _ = 1, count do
		local piece = table.remove(session.load) :: Piece
		if piece.horse then
			Animals.remove(piece.horse)
		end
		session.lost += 1
	end
	render(session)
	refresh(session)
	session.info.changed()
	return count
end

-- For the HUD (Jobs.payload).
function Cargo.status(session: Session): Status
	local plan = session.plan
	local held = session.held[session.owner]
	local handling = plan ~= nil and (plan.mode == "carry" or plan.mode == "lead")
	local progress = 0
	if plan and plan.mode == "serve" then
		progress = math.clamp(session.hold / math.max(plan.hold, 0.1), 0, 1)
	elseif plan and plan.needed > 0 then
		progress = math.clamp(session.moved / plan.needed, 0, 1)
	end
	local looseAt: Vector3? = nil
	local first = session.loose[1]
	if first then
		local model = first.piece.model
		if first.handle then
			looseAt = first.handle.Position
		elseif model then
			looseAt = model:GetPivot().Position
		end
	end
	return {
		inCar = #session.load,
		delivered = session.moved,
		needed = if plan then neededNow(session) else 0,
		total = session.info.total,
		deliveredTotal = session.deliveredTotal,
		lost = session.lost,
		carrying = if held then held.pieces[1].kind else nil,
		person = if plan and plan.person then plan.person.name else nil,
		pile = if plan and handling then plan.pile else nil,
		looseAt = looseAt,
		progress = progress,
	}
end

-- What to do now, for the HUD: (handling, step). handling = drive | carry | lead | board | serve.
function Cargo.step(session: Session): (string, string)
	local plan = session.plan
	if not plan then
		return "drive", ""
	end
	local owner = session.owner
	local held = session.held[owner]
	local car = session.car
	local noun = if car then Vehicles.cargoNoun(car) else "vehicle"
	local circle = if plan.stage == "pickup" then "blue" else "yellow"
	local seatedCar, driving = Vehicles.seatedIn(owner)
	local position = ownerPosition(session)
	local near = position ~= nil and flat(position, plan.park) < Tuning.ApproachDistance
	if session.blocked and near then
		return plan.mode, blockedText(session)
	end
	-- 3.2: the back is open and nothing more goes in or out here: close it, the car does not drive open. A serve or
	-- board stop needs no back: its own hint first while near, the nag once away.
	local noBack = plan.mode == "serve" or plan.mode == "board"
	if car and backOpen(session) and not held and (not near or (not noBack and not backNeeded(session))) then
		local close = capital(Vehicles.backVerb(car, false))
		return if near then plan.mode else "drive", if seatedCar then `Get out and {Vehicles.backVerb(car, false)} (E)` else `{close} (E), then drive on`
	end
	if not held and not near and heldCount(session) == 0 then
		return "drive", `Drive to the {circle} circle`
	end
	local parked = parkedCar(session) ~= nil
	local mode = plan.mode
	local who = if plan.person then plan.person.name else "the receiver"
	local piece = session.info.piece
	if mode == "serve" then
		if parked and driving then
			return mode, "Hold still while the customers buy"
		end
		return mode, `Park in the {circle} circle and hold still`
	elseif mode == "board" then
		if not parked then
			return mode, `Park in the {circle} circle`
		end
		local needed = neededNow(session)
		if isPatient(session) or isSurvivor(session) then
			local riders = if isSurvivor(session) then (if needed == 1 then "the survivor gets" else "the survivors get")
				elseif needed == 1 then "the patient gets"
				else "the patients get"
			return mode, `Wait while {riders} {if plan.stage == "pickup" then "in" else "out"} ({session.moved}/{needed})`
		end
		if plan.stage == "pickup" then
			return mode, `Wait while the kids get on ({session.moved}/{needed})`
		end
		return mode, `Wait while the kids get off ({session.moved}/{needed})`
	end
	local horse = session.info.kind == "horse"
	-- 3.2: the back is closed: open it first (with empty hands), load or take out after.
	local shut = car ~= nil and backShut(session)
	local open = if car then Vehicles.backVerb(car, true) else ""
	local two = if session.info.pair and not horse then " together" else "" -- the pair twist
	local intoCar = plan.stage == "pickup" or session.moved >= neededNow(session)
	if held then
		-- 3.7: one light piece leaves a hand free (open the back, take a second one); two fill both hands.
		local count = #held.pieces
		local it = if count > 1 then "them" else "it"
		local free = count < handsMax(session)
		if intoCar then
			if shut then
				if horse then
					return mode, `Let the horse go (G) and {open} (E)`
				elseif free then
					return mode, `{capital(open)} (E) with your free hand`
				elseif count > 1 then
					return mode, `Hands full: put one down (G) and {open} (E), or a crew mate opens it`
				end
				return mode, `Put it down (G) and {open} (E)`
			end
			if free and plan.stage == "pickup" and #session.pile > 0 then
				return mode, `Load it into the {noun} (E), or pick up a second {piece}`
			end
			return mode, if horse then `Lead the horse into the {noun} (E)` else `Load {it} into the back of the {noun}{two} (E)`
		end
		if free and toTakeOut(session) then
			return mode, `Carry it to {who} (E), or take out a second {piece}`
		end
		return mode, if horse then `Lead the horse to {who} (E)` else `Carry {it} to {who}{two} (E)`
	end
	if driving and not parked then
		return mode, `Park in the {circle} circle`
	end
	if #session.loose > 0 then
		if shut and intoCar then
			return mode, `{capital(open)} (E), then {if horse then "lead the horse in" else `pick up the {piece} again`}`
		end
		return mode, if horse then "Catch the horse you let go (E)" else `Pick up the {piece} you put down{two} (E)`
	end
	if plan.stage == "pickup" then
		if #session.pile > 0 or not session.built then
			if seatedCar then
				return mode, if horse then `Get out and take a horse from {who} (E)` else `Get out and pick up {article(piece)}{two} (E)`
			end
			return mode, if horse then `Take a horse from {who} (E)` else `Pick up {article(piece)} from {who}{two} (E)`
		end
		return mode, "Wait for your crew to load"
	end
	if #session.load > 0 and session.moved < neededNow(session) then
		if not atStop(session) then
			-- 3.2: Take out only with the vehicle in the circle.
			if car and backOpen(session) and not seatedCar then
				return mode, `{capital(Vehicles.backVerb(car, false))} (E), then park in the {circle} circle`
			end
			return mode, `Park in the {circle} circle`
		end
		if shut then
			return mode, if seatedCar then `Get out and {open} (E)` else `{capital(open)} (E)`
		end
		if seatedCar then
			return mode, if horse then `Get out and lead a horse out of the {noun} (E)` else `Get out and take {article(piece)} out of the {noun} (E)`
		end
		return mode, if horse then `Lead a horse out of the {noun} (E)` else `Take {article(piece)} out of the {noun}{two} (E)`
	end
	return mode, "Wait for your crew"
end

-- Is anybody of the job handling cargo on foot at the current stop (the enemies come on foot then)?
function Cargo.onFoot(session: Session): boolean
	local plan = session.plan
	if not plan or (plan.mode ~= "carry" and plan.mode ~= "lead") then
		return false
	end
	if heldCount(session) > 0 then
		return true
	end
	local position = ownerPosition(session)
	return position ~= nil and Vehicles.seatedIn(session.owner) == nil and flat(position, plan.park) < Tuning.ApproachDistance
end

-- The admin tools: the current stop is done at once (loaded / handed over / served).
function Cargo.adminFinish(session: Session): boolean
	local plan = session.plan
	if not plan or session.ended then
		return false
	end
	for player in table.clone(session.held) do
		local held = clearHeld(session, player)
		local pieces: { Piece } = if held then held.pieces else {}
		for _, piece in pieces do
			if piece.horse then
				Animals.lead(piece.horse, nil)
			end
			if piece.model then
				piece.model:Destroy()
				piece.model = nil
			end
			table.insert(session.load, piece)
		end
	end
	for _, loose in session.loose do
		loose.prompt:Destroy()
		if loose.handle then
			loose.handle:Destroy()
		end
		if loose.piece.model then
			loose.piece.model:Destroy()
			loose.piece.model = nil
		end
		table.insert(session.load, loose.piece)
	end
	table.clear(session.loose)
	if plan.mode == "serve" then
		session.hold = plan.hold
		session.served = true
		while #session.load > plan.keep do
			table.remove(session.load)
			session.deliveredTotal += 1
		end
		session.moved = plan.needed
	elseif plan.stage == "pickup" then
		build(session)
		for _, piece in session.pile do
			removeNpc(piece.npc)
			piece.npc = nil
			if piece.model then
				piece.model:Destroy()
				piece.model = nil
			end
			table.insert(session.load, piece)
		end
		for _, piece in session.walking do
			removeNpc(piece.npc)
			piece.npc = nil
			table.insert(session.load, piece)
		end
		table.clear(session.pile)
		table.clear(session.walking)
		session.moved = plan.needed
	else
		for _, piece in session.walking do
			removeNpc(piece.npc)
			piece.npc = nil
			session.moved += 1
			session.deliveredTotal += 1
		end
		table.clear(session.walking)
		while session.moved < plan.needed and #session.load > 0 do
			local piece = table.remove(session.load) :: Piece
			if piece.horse then
				Animals.remove(piece.horse)
			end
			session.moved += 1
			session.deliveredTotal += 1
		end
		session.moved = math.max(session.moved, neededNow(session))
	end
	render(session)
	refresh(session)
	session.info.changed()
	return true
end

-- The job is over: everything goes (the last stop's people stay a moment when `linger`).
function Cargo.finish(session: Session, linger: boolean?)
	if session.ended then
		return
	end
	for player in table.clone(session.held) do
		local held = clearHeld(session, player)
		local pieces: { Piece } = if held then held.pieces else {}
		for _, piece in pieces do
			if piece.horse then
				Animals.lead(piece.horse, nil)
				Animals.remove(piece.horse)
			end
			if piece.model then
				piece.model:Destroy()
			end
		end
	end
	session.ended = true
	for _, loose in session.loose do
		loose.prompt:Destroy()
		if loose.handle then
			loose.handle:Destroy()
		end
		if loose.piece.horse then
			Animals.remove(loose.piece.horse)
		end
		if loose.piece.model then
			loose.piece.model:Destroy()
		end
	end
	table.clear(session.loose)
	for _, piece in session.load do
		if piece.horse then
			Animals.remove(piece.horse)
		end
	end
	table.clear(session.load)
	for _, model in session.shown do
		model:Destroy()
	end
	table.clear(session.shown)
	if session.carPrompt then
		session.carPrompt:Destroy()
		session.carPrompt = nil
	end
	local car = session.car
	if car and car.model.Parent then
		car.model:SetAttribute("CargoCount", 0)
		car.model:SetAttribute("CargoKind", nil)
		Vehicles.setBack(car, false) -- 3.2: the next job starts with the back shut (a preloaded drop would offer Take out)
		car.model:SetAttribute("BackCrew", nil)
		local backPrompt = Vehicles.backPrompt(car)
		if backPrompt then
			backPrompt.Enabled = true -- the back is the owner's own again
		end
	end
	if active[session.owner] == session then
		active[session.owner] = nil
	end
	table.clear(session.pairAlone)
	clearStop(session, linger == true)
	session.plan = nil
end

function Cargo.start()
	-- 3.2, the back that opens: the job's crew may open and close the owner's car too, and every change updates the
	-- job's prompts (one E at the back at a time) and the HUD's hint.
	Vehicles.backAllowed = function(player: Player, car: Vehicles.Car): boolean
		local session = active[car.owner]
		return session ~= nil and not session.ended and session.info.allowed(player)
	end
	Vehicles.backChanged = function(car: Vehicles.Car)
		local session = active[car.owner]
		if session and not session.ended and session.car == car then
			refresh(session)
			session.info.changed()
		end
	end
	local existing = workspace:FindFirstChild("Cargo")
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Cargo"
		created.Parent = workspace
		folder = created
	end
end

return Cargo
