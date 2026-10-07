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
-- 3.7, two in your hands: a light piece (Config.Cargo.LightLooks: a pizza stack, a parcel, a mail sack …) can be
-- carried two at a time (Config.Cargo.HandsMax), stacked in front of the chest, a little slower (TwoPieceSpeed, the
-- CarrySpeed attribute). Heavy pieces, horses and every piece of a lift or pair job stay one at a time (handsMax).
-- With one light piece a hand is free (the character attribute CarryHands = 1): you open and close the back yourself
-- (server/Vehicles.luau); two pieces or a heavy one fill both (CarryHands = 2): put one down or let a crew mate open
-- it. G puts down ONE piece (the top one), so two in hand → G → one in hand → open the back yourself. Load puts both
-- in at once; at a drop Take out with one light piece in hand takes a second, and Hand over gives the receiver all
-- you carry (as many as they still need). The character attribute CarryCount says how many you hold.
--
-- 4.0, freight and equipment (shared/Freight.luau has the rules, server/Equipment.luau the tools themselves):
--   the hand trolley  pushed (Pushing = "trolley"), it is the player's Held with `tool` set: up to TrolleyPieces of
--                     any kind but people, horses and pallets ride on its toe plate. "Load onto trolley" (E) at the
--                     pile takes as many as fit, the pieces on the ground one each; "Load all" at the open back puts
--                     them in (as many as the vehicle has room for), at a drop "Take out" fills it and "Hand over"
--                     gives the receiver all of them. G sets the trolley down: its pieces stay on it (Loose with
--                     `tool`, counted like every piece put down) and come along when it is taken again; when it goes
--                     home on its own they go on the ground. One count for every piece, wherever it is.
--   pallets           the mode "pallet" (the Freight Run): the pallets wait on the dock (Plan.staging) as Loose
--                     pieces, "Lift pallet" (E) only with a pallet jack (Pushing = "jack", one pallet), "Load pallet"
--                     at the open back of a vehicle that takes pallets (Freight.palletsOf: their places on its floor,
--                     palletFrames), at the drop "Unload pallet" onto the jack and "Set down pallet" at the receiving
--                     dock's pad. The hints (Cargo.step) say what to do with a tool in every state.
--
-- 4.8 (server/Jobs.luau, shared/JobRules.luau): Info.heavy, a heavy cargo carried by hand alone walks at that speed
-- (the lift twist's machinery, updateLift; on the hand trolley or with a crew mate the normal pace). Multi-drop:
-- Info.dests / destNames give every piece its stop and customer (Piece.dest / owner, a "FOR GRANDMA ROSE" tag over a
-- piece out of the vehicle, the prompts say it); at a drop only that customer's pieces count (neededNow, toTakeOut),
-- Take out picks theirs (takeHere), and handing over another customer's piece is refused (it goes back in).
-- Cargo.setStop(…, replace): a road event's side pick-up swapped in front of the stop you drive to.
--
-- 5.0, ON FOOT (Info.foot, server/Jobs.luau's foot jobs; shared/Transport.luau): no vehicle takes part (no Load
-- prompt, no back, session.car stays nil). At the pick-up a piece taken from the pile counts at once (session.moved);
-- your hands hold Config.Cargo.HandsMax light pieces and, once they are full, a piece picked up goes into the owner's
-- PACK (session.pack, Info.pack pieces: the backpack's room over the hands; no model). The stop is done when the pile
-- is empty and nothing lies on the ground. At the drop Hand over gives the receiver the hands' pieces first, then the
-- pack's. Sitting down (a car) stows the hands into the pack while it has room (else they go down as before); the
-- owner dying drops the pack's pieces where they fell (loose pieces, picked up again). The player attributes
-- PackCount / PackRoom tell the HUD and the phone (nil without a foot job).
--
-- 5.2, several orders at once (server/Jobs.luau's orders): one session carries the pieces of every order of the job.
-- A Plan names its stop (Plan.index: the session's stop is the job's stop index, not a counter, so the stops may come
-- in any order) and its order (Plan.order), and a pick-up's Plan says where each piece it makes goes (Plan.dests /
-- destNames) and what it is (kind, look, name, heavy: an order's own cargo). Every piece carries its order and its
-- stop (Piece.order / dest): at a drop only that order's pieces for that stop count, Take out picks them, a wrong one
-- is refused; on foot Hand over gives the ones for here from the hands and the pack and keeps the rest. The stop
-- whose pieces were half handled is `engaged` (Jobs keeps it); Cargo.withYou / remainingFor / deliveredOf / lostOf
-- count by stop and by order, Cargo.dropOrder takes a failed order's pieces back, Cargo.carried lists every piece you
-- carry (the job payload's `carried`). packFits(piece) says which pieces may ride in the pack.
--
-- 5.3, real places, the bag and the newspaper round (server/Jobs.luau, shared/Bag.luau, Config.Jobs Places / Round):
--   * packFits by the piece's look (Config.Cargo.PackLooks): mail, newspapers, medicine, pizza, food boxes, bread and
--     small parcels go into a backpack; a bouquet, a cake, an electronics box, groceries, ice cream do not: they stay
--     in the hands, or ride on a bike's rack / basket / box (Info.rack of the pack: at a bike job's pick-up, Info.ride,
--     or stowed when you sit on the bike). Cargo.carried says "rack" for those (and for the pieces over the backpack).
--   * A storefront's cook / clerk stands in its doorway (Plan.personAt). At a home (Plan.door) the receiver is inside
--     until the owner comes within Places.KnockRange of the door (knock): the door swings open (World's "Door" part)
--     and they step out; nobody home (Plan.nobody): "Leave at the door", the pieces are set down there.
--   * The newspaper round: at the print shop "Pick up the bundle" puts every paper into the owner's satchel at once
--     (Plan.bundle); at a door (Plan.toss) "Toss newspaper" works from Round.TossRange: the paper flies from you onto
--     the porch, from farther than Round.SureToss maybe into the bushes (JobRules.tossMiss; Cargo.missesOf counts them).
--
-- 6.0, the courier on foot (Config.Throw, Config.Courier; shared/Throws.luau, client/Throw.luau):
--   * The plastic bag (Config.Kit "bag", the owner's profile.kit): a light piece the owner picks up (the pile, the
--     ground) drops straight into the pack (the bag and any backpack: Info.pack) while it fits and has room, the hands
--     stay free; the "bag" gesture (shared/Gestures.luau) shows it.
--   * Throwing at a home's door (a foot job's drop with Plan.door, or a newspaper round's Plan.toss): the owner holds X
--     and releases; the "Throw" remote brings (the stop's ThrowStop, a direction, a power 0 … 1). Checked here: the
--     stop, the cooldown, the range (Config.Throw.Range from the door), a body on foot, room to throw (a ray from the
--     body to the release point), a piece for here in the hands or the pack that may fly (light, not fragile:
--     Throws.throwable; Info.fragile, a FRAGILE job, refuses all). The arc is traced here (Throws.trace with the
--     world's rays: people and the stop's props let it through) and the piece flies along it for everybody. Within
--     Config.Throw.DoorRadius of the door: delivered (the receiver catches it; nobody out yet: the door opens as for a
--     knock), with the TRICKSHOT tip (Throws.tip: far, over something, off a wall) paid at once; a miss lies on the
--     ground as a loose piece (picked up as ever; on a roof or nowhere it rolls down beside the door). The round's
--     paper that misses the porch counts, as a miss. The owner's attributes ThrowTo (the door's spot), ThrowStop and
--     ThrowFragile tell the client when a throw is possible.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Freight = require(Shared.Freight)
local Bag = require(Shared.Bag) -- 5.3: what fits a backpack
local JobRules = require(Shared.JobRules) -- 5.3: the newspaper's toss
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)
local Animals = require(script.Parent.Animals)
local Equipment = require(script.Parent.Equipment)
local PlayerData = require(script.Parent.PlayerData) -- 6.0: the bag owned, the TRICKSHOT tip
local Throws = require(Shared.Throws) -- 6.0: the throw's arc and tip
local tipsPaid: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- 6.0 review: trickshot tips paid per session

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
	staging: { Vector3 }?, -- 4.0, pallet: where the pallets wait (pick-up) or are set down (drop), on the ground
	-- 5.2, several orders (nil: as before, a counter and the job's Info):
	index: number?, -- the job's stop index (the session's stop)
	order: number?, -- the order the stop belongs to
	dests: { number }?, -- a pick-up: the stop each piece made here goes to, in the order they are made
	destNames: { [number]: string }?, -- the customer at each of those stops (the FOR tag)
	kind: string?, -- the order's cargo, when it is not the Info's
	look: string?,
	name: string?, -- a piece's name ("pizza box")
	heavy: number?, -- 4.8's heavy rule of the order (Info.heavy for the job's first one)
	-- 5.3, real places (server/Jobs.luau from shared/Deliveries.luau):
	personAt: Vector3?, -- a storefront: its cook / clerk stands here, in the doorway (nil: at the pile)
	door: Vector3?, -- a home's door: the receiver is inside until you knock (come within Places.KnockRange)
	nobody: boolean?, -- a home where nobody answers: "Leave at the door"
	toss: boolean?, -- a newspaper round's door: "Toss newspaper" from Round.TossRange, nobody comes out
	bundle: boolean?, -- the round's pick-up: the whole bundle goes into your satchel at once
	place: string?, -- the address, for what you are told ("12 Willow Ln")
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
	-- 4.8, cargo with rules: heavy pieces (Config.Jobs.CargoRules.HeavyCarrySpeed): carried by hand alone you walk this
	-- slowly; on the hand trolley or with a crew mate within Config.Missions.LiftHelpRange at the normal pace.
	heavy: number?,
	-- 4.8, multi-drop: the stop every piece goes to, in the order they are made (JobRules.destinations), and the
	-- customer's name at each of those stops. A piece is only handed over at its own stop.
	dests: { number }?,
	destNames: { [number]: string }?,
	-- 5.0, on foot (no vehicle: no Load prompt, no back): the pieces over the hands ride in the owner's pack, this many.
	foot: boolean?,
	pack: number?,
	-- 5.3, the bag (shared/Bag.luau): of `pack`, the slots of a bike's rack / basket / box (the rest is the backpack, or
	-- a round's satchel). A piece that does not fit a backpack (Bag.fits) rides only there: put there at a pick-up on a
	-- bike job (`ride`), or stowed when you get on the bike with it in your hands.
	rack: number?,
	ride: boolean?,
	-- 6.0: the job's cargo is fragile (the FRAGILE modifier, the fragile cargo rule): nothing of it may be thrown.
	fragile: boolean?,
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
	dest: number?, -- 4.8, multi-drop: the stop it goes to (nil: any drop) …
	owner: string?, -- … and the customer there ("For Grandma Rose" on the piece)
	order: number, -- 5.2: the order it belongs to (1 for a job of one order)
	name: string, -- 5.2: what it is ("pizza box")
	heavy: number?, -- 5.2: carried alone by hand you walk this slowly (the order's heavy rule)
}

-- 3.7: pieces, bottom first (two light pieces stacked; one otherwise). The prompt (Put down / Let go) sits on the top one.
-- 4.0: `tool` = on the trolley or the jack the player pushes (no prompt: the tool's own G).
type Held = { pieces: { Piece }, character: Model, root: BasePart, prompt: ProximityPrompt?, last: CFrame, tool: Equipment.Tool? }
-- 4.0: `tool` = on a trolley or a jack set down somewhere (its prompt off: the pieces come along with the tool).
type Loose = { piece: Piece, prompt: ProximityPrompt, handle: Part?, tool: Equipment.Tool? }

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
	made: number, -- 4.8: pieces made so far (the index into Info.dests)
	pack: { Piece }, -- 5.0, on foot: in the owner's backpack (no model)
	packAt: CFrame?, -- 5.0: where the owner stood at the last tick (the pack's pieces fall there when they die)
	packHumanoid: Humanoid?, -- 5.0: the owner's humanoid at that tick (it died if it is dead and replaced since)
	visit: number, -- 5.2: setStop calls so far (a person spawned for an earlier visit of the same stop goes)
	madeHere: number, -- 5.2: pieces made at this visit of the stop (the index into Plan.dests)
	deliveredBy: { [number]: number }, -- 5.2: handed over, by order
	lostBy: { [number]: number }, -- 5.2: stolen or wrecked, by order
	knocked: boolean, -- 5.3: knocked at this stop's door (the receiver comes out)
	missBy: { [number]: number }, -- 5.3: newspapers in the bushes, by order
	anchor: Vector3?, -- 5.3 review: the stop's pile as Jobs gave it (set when built; another job there takes another slot)
	slot: number, -- … and this job's place beside it (0: right there; Places.SessionGap to a side: build)
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
	pack: number, -- 5.0, on foot: pieces in the owner's backpack …
	packRoom: number, -- … and its room (0: no pack, or not on foot)
	rack: number, -- 5.3: of that room, a bike's rack / basket / box
	foot: boolean, -- 5.0: a foot job (no vehicle)
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
	door = { "Oh, the delivery! Thank you!", "Coming, coming!", "Finally! I'm starving.", "Is that for me?", "You made it through out there?" }, -- 5.3
	bundle = { "Fresh off the press. Don't miss a porch!", "Hot news, still warm. Every door on the list!", "Toss them gently, the porches are old." },
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
	for _, name in { "Cars", "Zombies", "Npcs", "Animals", "Effects", "Loot", "Showroom", "Equipment" } do
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
	elseif look == "pallet" then
		-- 4.0: a wooden pallet with eight boxes in shrink wrap, about 4 × 4 × 4. A pallet jack's forks go in from the
		-- front between the stringers. The wrap is the main part (you walk round it, the prompt sits on it).
		local wrap = block("Body", Vector3.new(3.9, 3.2, 3.9), Vector3.new(0, 2.24, 0), rgb(214, 226, 232), Enum.Material.SmoothPlastic)
		wrap.Transparency = 0.55
		wrap.Reflectance = 0.15
		local wood = rgb(176, 136, 88)
		for _, x in { -1.75, 0, 1.75 } do
			block("Stringer", Vector3.new(0.4, 0.5, 4), Vector3.new(x, 0.25, 0), wood:Lerp(black, 0.15), Enum.Material.WoodPlanks)
		end
		for n = 0, 4 do
			block("Board", Vector3.new(4, 0.12, 0.66), Vector3.new(0, 0.56, -1.6 + n * 0.8), wood, Enum.Material.WoodPlanks)
		end
		local colors = { rgb(196, 158, 108), rgb(60, 110, 170), rgb(90, 150, 80), rgb(200, 70, 50) }
		local color = colors[variant % #colors + 1]
		local cardboard = rgb(196, 158, 108)
		for layer = 0, 1 do
			for i, x in { -0.96, 0.96 } do
				for j, z in { -0.96, 0.96 } do
					block("Box", Vector3.new(1.86, 1.55, 1.86), Vector3.new(x, 1.41 + layer * 1.57, z), if (i + j + layer) % 2 == 0 then color else cardboard, Enum.Material.Cardboard)
				end
			end
		end
		for _, x in { -1, 1 } do
			block("Strap", Vector3.new(0.14, 3.24, 3.96), Vector3.new(x, 2.24, 0), rgb(40, 40, 44), Enum.Material.Fabric)
		end
		local sheet = block("Sheet", Vector3.new(1.4, 1, 0.04), Vector3.new(0.9, 2.6, -1.98), rgb(245, 245, 240), Enum.Material.SmoothPlastic)
		stencil(sheet, "FREIGHT", rgb(30, 30, 34), { Enum.NormalId.Front })
	-- 5.3, the storefronts' own pieces (Config.Jobs.Businesses looks).
	elseif look == "burger" then
		-- Last Bite's paper bag, folded over at the top, a burger sticker.
		local paper = rgb(176, 132, 84)
		local body = block("Body", Vector3.new(1.3, 1.5, 0.9), Vector3.new(0, 0.75, 0), paper, Enum.Material.Cardboard)
		block("Fold", Vector3.new(1.32, 0.3, 0.6), Vector3.new(0, 1.62, 0), paper:Lerp(black, 0.15), Enum.Material.Cardboard)
		cylinder("Sticker", 0.04, 0.6, Vector3.new(0, 0.85, -0.46), rgb(220, 60, 40), Enum.Material.SmoothPlastic, "z")
		stencil(body, "LAST BITE", rgb(250, 230, 160), { Enum.NormalId.Back })
	elseif look == "noodles" then
		-- Two white take-out boxes with wire handles, Wok Dead's red mark.
		for n = 0, 1 do
			local y = 0.4 + n * 0.82
			block("Box", Vector3.new(1.0 - n * 0.1, 0.8, 0.9 - n * 0.1), Vector3.new(0, y, 0), rgb(246, 244, 238), Enum.Material.SmoothPlastic)
			block("Mark", Vector3.new(0.4, 0.4, 0.03), Vector3.new(0, y, -0.46 + n * 0.05), rgb(200, 36, 36), Enum.Material.SmoothPlastic)
		end
		block("Handle", Vector3.new(0.06, 0.4, 0.7), Vector3.new(0, 1.85, 0), rgb(170, 170, 176), Enum.Material.Metal)
	elseif look == "pastry" then
		-- A paper pastry bag, a croissant peeking out.
		block("Body", Vector3.new(1.1, 1.3, 0.7), Vector3.new(0, 0.65, 0), rgb(236, 226, 206), Enum.Material.Cardboard)
		block("Band", Vector3.new(1.12, 0.25, 0.72), Vector3.new(0, 0.9, 0), rgb(46, 110, 70), Enum.Material.SmoothPlastic)
		local croissant = newPart(model, "Croissant", Vector3.new(0.9, 0.35, 0.35), CFrame.new(0, 1.42, 0) * CFrame.Angles(0, 0, math.rad(12)), rgb(214, 156, 74), Enum.Material.SmoothPlastic)
		croissant.Shape = Enum.PartType.Cylinder
	elseif look == "newspaper" then
		-- The morning paper, rolled and held with a rubber band.
		cylinder("Body", 1.3, 0.42, Vector3.new(0, 0.21, 0), rgb(232, 230, 222), Enum.Material.SmoothPlastic, "x")
		cylinder("Band", 0.08, 0.45, Vector3.new(0, 0.21, 0), rgb(200, 50, 40), Enum.Material.SmoothPlastic, "x")
		block("Headline", Vector3.new(0.5, 0.1, 0.02), Vector3.new(0.35, 0.3, -0.2), rgb(30, 30, 32), Enum.Material.SmoothPlastic)
	elseif look == "bouquet" then
		-- Flowers in paper: a cone of kraft paper, the blooms on top.
		block("Paper", Vector3.new(0.9, 1.4, 0.9), Vector3.new(0, 0.7, 0), rgb(214, 186, 140), Enum.Material.Cardboard)
		block("Ribbon", Vector3.new(0.94, 0.15, 0.94), Vector3.new(0, 0.55, 0), rgb(220, 70, 120), Enum.Material.Fabric)
		local blooms = { rgb(230, 60, 80), rgb(250, 220, 70), rgb(240, 140, 190), rgb(250, 250, 245) }
		for n, at in { Vector3.new(-0.25, 1.6, 0), Vector3.new(0.25, 1.65, 0.1), Vector3.new(0, 1.75, -0.2), Vector3.new(0.05, 1.6, 0.3) } do
			ball("Bloom", 0.5, at, blooms[(n + variant) % #blooms + 1], Enum.Material.SmoothPlastic)
		end
		ball("Leaves", 0.9, Vector3.new(0, 1.45, 0), rgb(70, 130, 60), Enum.Material.Grass)
	elseif look == "icecream" then
		-- Frosty's insulated bag, a tub of ice cream on top of it.
		local body = block("Body", Vector3.new(1.5, 1.1, 1.1), Vector3.new(0, 0.55, 0), rgb(60, 140, 220), Enum.Material.Fabric)
		block("Zip", Vector3.new(1.52, 0.08, 1.12), Vector3.new(0, 1.0, 0), rgb(240, 240, 244), Enum.Material.Fabric)
		cylinder("Tub", 0.5, 0.8, Vector3.new(0, 1.35, 0), rgb(250, 236, 214), Enum.Material.SmoothPlastic)
		cylinder("Lid", 0.08, 0.84, Vector3.new(0, 1.62, 0), rgb(240, 120, 160), Enum.Material.SmoothPlastic)
		stencil(body, "FROSTY'S", rgb(255, 255, 255), { Enum.NormalId.Back })
	elseif look == "gadget" then
		-- Volt's printed box: a radio on the front.
		local body = block("Body", Vector3.new(1.8, 1.3, 1.2), Vector3.new(0, 0.65, 0), rgb(40, 50, 64), Enum.Material.Cardboard)
		block("Picture", Vector3.new(1.0, 0.7, 0.03), Vector3.new(-0.2, 0.7, -0.61), rgb(230, 200, 60), Enum.Material.SmoothPlastic)
		block("Bolt", Vector3.new(0.25, 0.5, 0.03), Vector3.new(0.6, 0.75, -0.61), rgb(250, 220, 60), Enum.Material.Neon)
		stencil(body, "VOLT · FRAGILE", rgb(250, 220, 60), { Enum.NormalId.Back })
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
	-- 4.8, multi-drop: a small tag over a piece out of the vehicle says whose it is.
	local owner = piece.owner
	local main = model.PrimaryPart
	if owner and main then
		local tag = Instance.new("BillboardGui")
		tag.Name = "ForTag"
		tag.Size = UDim2.fromOffset(150, 22)
		tag.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") :: number? or 2) / 2 + 1.2, 0)
		tag.MaxDistance = 40
		tag.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(24, 24, 26)
		text.BackgroundTransparency = 0.25
		text.BorderSizePixel = 0
		text.TextColor3 = Color3.fromRGB(245, 245, 245)
		text.Font = Enum.Font.GothamBold
		text.TextSize = 12
		text.Text = `FOR {require(Shared.Residents).caps(owner)}` -- (5.5: a resident's Czech letters in caps)
		text.Parent = tag
		tag.Parent = main
	end
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

-- 5.3 review: `owner`, the job's owner: the prompt carries their UserId (attribute CargoOwner) and the tag
-- Config.Cargo.PromptTag, so client/CargoPrompts.luau hides it from everybody outside that job (another courier's pile
-- at the same storefront never takes your E; the attribute CargoWith on a player lists the jobs they work for).
local function prompt(parent: Instance, action: string, object: string, key: Enum.KeyCode?, hold: number?, owner: Player?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	if owner then
		p:SetAttribute("CargoOwner", owner.UserId)
		game:GetService("CollectionService"):AddTag(p, Tuning.PromptTag)
	end
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

-- The hold of the job's pick-up / load / take-out / hand-over prompts (5.7: Quick Hands' shorter holds are gone).
local function holdFor(_session: Session): number
	return Tuning.HoldDuration
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
	local visit = session.visit -- (5.2: the same stop may come again later: its visit, not its number)
	session.busy += 1
	local npc = Npcs.spawn(look, at)
	session.busy -= 1
	if session.ended or session.visit ~= visit then
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
	session.made += 1
	session.madeHere += 1
	local info = session.info
	local plan = session.plan
	-- 5.2: a Plan that says where its pieces go (an order's pick-up), else 4.8's Info.dests by the job's count.
	local dests = if plan and plan.dests then plan.dests else info.dests
	local names = if plan and plan.destNames then plan.destNames else info.destNames
	local dest = if plan and plan.dests then plan.dests[session.madeHere] elseif dests then dests[session.made] else nil
	return {
		kind = if plan and plan.kind then plan.kind else info.kind,
		look = if plan and plan.look then plan.look else info.look,
		variant = session.nextVariant,
		origin = session.stop,
		dest = dest,
		owner = if dest and names then names[dest] else nil,
		order = if plan and plan.order then plan.order else 1,
		name = if plan and plan.name then plan.name else info.piece,
		heavy = if plan and plan.order then plan.heavy else info.heavy, -- (5.2: an order's own rule)
	}
end

-- 5.2: may this piece ride in the pack (on foot: the backpack; a bike's room)? 5.3: by its look (Config.Cargo.PackLooks,
-- shared/Bag.luau): mail, newspapers, medicine, pizza, food boxes, bread, small parcels do; a bouquet, a cake, an
-- electronics box, groceries do not (the hands, or a bike's rack: rackFree).
local function packFits(piece: Piece): boolean
	return Bag.fits(piece.look)
end

-- 4.8, multi-drop: the customer a piece is for ("Grandma Rose"), nil for a piece any drop takes.
local function destName(_session: Session, piece: Piece): string?
	return piece.owner
end

-- 4.8, multi-drop: does this piece go to the current stop (a piece without a stop of its own goes anywhere)?
-- 5.2: and to the current stop's order (a piece of another order never counts here).
local function forHere(session: Session, piece: Piece): boolean
	local plan = session.plan
	if plan and plan.order and piece.order ~= plan.order then
		return false
	end
	return piece.dest == nil or piece.dest == session.stop
end

-- 4.8: how many of these pieces go to the current stop.
local function countHere(session: Session, pieces: { Piece }): number
	local n = 0
	for _, piece in pieces do
		if forHere(session, piece) then
			n += 1
		end
	end
	return n
end

-- 4.8: does somebody hold a piece for another stop (it goes back into the vehicle)? With `player`: that player.
local function holdsOther(session: Session, player: Player?): boolean
	for who, held in session.held do
		if player == nil or who == player then
			for _, piece in held.pieces do
				if not forHere(session, piece) then
					return true
				end
			end
		end
	end
	return false
end

-- 4.8: the last piece in the vehicle that goes to the current stop, taken out of the load (nil: none).
local function takeHere(session: Session): Piece?
	for index = #session.load, 1, -1 do
		if forHere(session, session.load[index]) then
			return table.remove(session.load, index)
		end
	end
	return nil
end

-- The pieces in hands (3.7: a player may hold two).
local function heldCount(session: Session): number
	local n = 0
	for _, held in session.held do
		n += #held.pieces
	end
	return n
end

-- The tool the player pushes (4.0: "trolley" | "jack"), or nil.
local function toolOf(player: Player): string?
	local tool = Equipment.pushing(player)
	return if tool then tool.kind else nil
end

-- 3.7: how many pieces of this job one player may hold: two of a light look, else one (a horse, a person, a lift or
-- pair job's piece). 4.0: with a tool (`player` given): a trolley's TrolleyPieces, a jack's one pallet, 0 when the
-- piece does not go on it (or a pallet in the hands: shared/Freight.luau handsMax).
-- 5.2: the cargo of the hands: what the player holds, else the current stop's order's (Plan.kind / look), else the job's.
local function handsMax(session: Session, player: Player?): number
	local info = session.info
	local held = if player then session.held[player] else session.held[session.owner]
	local first = if held then held.pieces[1] else nil
	local plan = session.plan
	local kind = if first then first.kind elseif plan and plan.kind then plan.kind else info.kind
	local look = if first then first.look elseif plan and plan.look then plan.look else info.look
	return Freight.handsMax(kind, look, info.lift, info.pair, if player then toolOf(player) else nil)
end

-- 4.0: is this job's cargo pallets (the Freight Run)?
local function isPallet(session: Session): boolean
	return Freight.isPallet(session.info.kind)
end

-- 5.0, on foot: the room left in the owner's pack.
local function packFree(session: Session): number
	return math.max(0, (session.info.pack or 0) - #session.pack)
end

-- 5.3: the room left on a bike's rack / basket / box (Info.rack) for the pieces that do not fit a backpack.
local function rackFree(session: Session): number
	local used = 0
	for _, piece in session.pack do
		if not packFits(piece) then
			used += 1
		end
	end
	return math.max(0, (session.info.rack or 0) - used)
end

-- 5.3: may these pieces go into the pack now? Room for all of them, and the rack's for the ones that do not fit a
-- backpack: only on a bike job's pick-up (Info.ride) or while you sit on the bike (`seated`).
local function packTakes(session: Session, pieces: { Piece }, seated: boolean): boolean
	if #pieces > packFree(session) then
		return false
	end
	local big = 0
	for _, piece in pieces do
		if not packFits(piece) then
			big += 1
		end
	end
	return big == 0 or ((seated or session.info.ride == true) and big <= rackFree(session))
end

-- 5.0: what is in the owner's pack, for the HUD and the phone (the player attributes PackCount and PackRoom; nil when
-- there is no foot job).
local function packShown(session: Session)
	local owner = session.owner
	local on = session.info.foot == true and not session.ended
	local count = if on then #session.pack else nil
	local room = if on then session.info.pack or 0 else nil
	if owner:GetAttribute("PackCount") ~= count then
		owner:SetAttribute("PackCount", count)
	end
	if owner:GetAttribute("PackRoom") ~= room then
		owner:SetAttribute("PackRoom", room)
	end
end

-- 5.0: a piece goes into the owner's pack (its model goes: nothing shows).
local function stash(session: Session, piece: Piece)
	if piece.model then
		piece.model:Destroy()
		piece.model = nil
	end
	table.insert(session.pack, piece)
	packShown(session)
end

-- 6.0: does the job's owner have the plastic bag (Config.Courier.BagKit)?
local function bagged(session: Session): boolean
	local profile = PlayerData.get(session.owner)
	return profile ~= nil and profile.kit[Config.Courier.BagKit] == true
end

-- 5.0: does a piece this player takes go into the pack (a foot job, the owner, the hands full, room left in it)?
-- 6.0: with the plastic bag a piece that fits drops straight in, the hands empty or not (never onto a pushed tool).
local function intoPack(session: Session, player: Player, piece: Piece?): boolean
	if not session.info.foot or player ~= session.owner or packFree(session) <= 0 or (piece ~= nil and not packTakes(session, { piece }, false)) then
		return false
	end
	local held = session.held[player]
	if bagged(session) and (piece == nil or piece.horse == nil) and Equipment.pushing(player) == nil and (held == nil or held.tool == nil) then
		return true
	end
	return held ~= nil and held.tool == nil and #held.pieces >= handsMax(session, player)
end

-- Is this a stop where the cargo is handled on foot (carried, led, 4.0: moved on a pallet jack)?
local function handled(mode: string): boolean
	return mode == "carry" or mode == "lead" or mode == "pallet"
end

-- 4.0: the pieces lying somewhere on the ground (not on a trolley or a jack set down).
local function looseOnGround(session: Session): number
	local n = 0
	for _, loose in session.loose do
		if not loose.tool then
			n += 1
		end
	end
	return n
end

-- 4.0: does somebody of the job push a tool of this kind right now (the prompts' words)?
local function crewPushes(session: Session, kind: string): boolean
	for _, player in Players:GetPlayers() do
		if toolOf(player) == kind and session.info.allowed(player) then
			return true
		end
	end
	return false
end

-- 4.8, multi-drop: the pieces for this stop in hands and put down (not in the vehicle).
local function outHere(session: Session): number
	local n = 0
	for _, hands in session.held do
		n += countHere(session, hands.pieces)
	end
	for _, item in session.loose do
		if forHere(session, item.piece) then
			n += 1
		end
	end
	return n
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
	-- 4.8, multi-drop: only the pieces for this stop count.
	-- 5.0, on foot: the pack's too.
	return math.min(plan.needed, session.moved + countHere(session, session.load) + outHere(session) + countHere(session, session.walking) + countHere(session, session.pack))
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
	if not plan or plan.stage ~= "drop" or not handled(plan.mode) or session.blocked or not atStop(session) then
		return false
	end
	-- (4.8, multi-drop: a piece for this stop)
	return countHere(session, session.load) > 0 and session.moved + outHere(session) < neededNow(session)
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
	if not plan or not handled(plan.mode) then
		return false
	end
	local busy = heldCount(session) > 0 or #session.loose > 0
	if plan.stage == "pickup" then
		return busy or not session.built or #session.pile > 0
	end
	return busy or (countHere(session, session.load) > 0 and session.moved < neededNow(session))
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
	local pallet = isPallet(session)
	local trolley = not pallet and not horse and crewPushes(session, "trolley") -- 4.0: the words for a trolley
	local carPrompt = session.carPrompt
	local car = session.car
	if carPrompt and car then
		local takeOut = toTakeOut(session)
		-- 3.2: only through an open back. 3.7: what you hold goes in at a pick-up (or a drop that has everything); at a
		-- drop that still needs it you carry it on (with one light piece in hand Take out gives you a second).
		local loadable = plan == nil or plan.stage == "pickup" or session.moved >= neededNow(session) or holdsOther(session) -- (4.8: back in)
		carPrompt.Enabled = (takeOut or (heldCount(session) > 0 and loadable)) and not backShut(session)
		if pallet then
			carPrompt.ActionText = if takeOut then "Unload pallet" else "Load pallet"
		elseif trolley then
			carPrompt.ActionText = if takeOut then "Take out" else "Load all"
		else
			carPrompt.ActionText = if takeOut then (if horse then "Lead out" else "Take out") else (if horse then "Lead in" else "Load")
		end
		carPrompt.ObjectText = `{capital(Vehicles.cargoNoun(car))}: {#session.load} inside`
	end
	-- 3.2: one E at the back at a time. A piece put down that goes into the vehicle is picked up again only once the
	-- back is open; the BackPrompt (the same spot as the Load prompt) waits while the Load / Take out prompt or such a
	-- piece has something to do. 4.0: the pieces on a tool set down have no prompt (they come with the tool); a pallet
	-- waits on the dock, far from the back: lifted any time.
	local intoCar = plan ~= nil and (plan.stage == "pickup" or session.moved >= neededNow(session))
	local shut = backShut(session)
	local jack = pallet and crewPushes(session, "jack")
	for _, loose in session.loose do
		loose.prompt.Enabled = loose.tool == nil and (pallet or not (intoCar and shut))
		if pallet then
			loose.prompt.ActionText = if jack then "Lift pallet" else "Too heavy: use a pallet jack"
		elseif loose.handle == nil then
			loose.prompt.ActionText = if trolley then "Load onto trolley" else "Pick up"
		end
	end
	local backPrompt = car and Vehicles.backPrompt(car)
	if backPrompt then
		local nearBack = if pallet then 0 else looseOnGround(session)
		backPrompt.Enabled = not (carPrompt ~= nil and carPrompt.Enabled) and not (intoCar and not shut and nearBack > 0)
	end
	local pilePrompt = session.pilePrompt
	if pilePrompt and plan then
		if plan.stage == "pickup" then
			pilePrompt.Enabled = #session.pile > 0 and not session.blocked
			pilePrompt.ObjectText = `{capital(if horse then "horse" else session.info.piece)} ({#session.pile} left)`
			pilePrompt.ActionText = if horse then "Lead" elseif trolley then "Load onto trolley" else "Pick up"
		else
			pilePrompt.Enabled = session.moved < neededNow(session) and not session.blocked
			pilePrompt.ObjectText = if plan.person then plan.person.name else "Receiver"
			pilePrompt.ActionText = if pallet then "Set down pallet" else "Hand over"
		end
	end
end

-- 4.0: where `count` pallets stand in the vehicle, relative to its chassis: its own pallet places (Attachments
-- PalletSlot1, PalletSlot2 … on the chassis, if a body has them), else the middle of its 2×2 slot groups (slots 1–4,
-- 5–8 …; Freight.palletSpots), then a row behind. Kept generic for a trailer later.
local function palletFrames(car: Vehicles.Car, count: number): { CFrame }
	local out: { CFrame } = {}
	local own = true
	for index = 1, count do
		local slot = car.chassis:FindFirstChild(`PalletSlot{index}`)
		if not slot or not slot:IsA("Attachment") then
			own = false
			break
		end
		table.insert(out, slot.CFrame)
	end
	if own then
		return out
	end
	table.clear(out)
	local points: { Freight.Point } = {}
	for _, slot in Vehicles.cargoSlots(car) do
		table.insert(points, { x = slot.Position.X, y = slot.Position.Y, z = slot.Position.Z })
	end
	for _, spot in Freight.palletSpots(points, count) do
		table.insert(out, CFrame.new(spot.x, spot.y, spot.z))
	end
	for _ = #out + 1, count do
		table.insert(out, CFrame.new(0, car.size.Y / 2, 0)) -- a vehicle without cargo slots: on the chassis
	end
	return out
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
	if isPallet(session) then
		-- 4.0: the pallets on the floor, in their places (palletFrames).
		local frames = palletFrames(car, #session.load)
		for index, piece in session.load do
			local model = buildLook(piece.look, piece.variant)
			weldTo(model, car.chassis, car.chassis.CFrame * frames[index])
			model.Parent = car.model
			table.insert(session.shown, model)
		end
		return
	end
	local slots = Vehicles.cargoSlots(car)
	-- 4.6: a Roof Rack (gear) adds a slot on the roof for a light piece: the Attachment RoofRackSlot, after the others.
	local roof = car.chassis:FindFirstChild("RoofRackSlot")
	if roof and roof:IsA("Attachment") and Vehicles.capacity(car, session.info.look) > #slots then
		slots = table.clone(slots)
		table.insert(slots, roof.CFrame)
	end
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

-- Every tick: who carries a heavy piece alone walks at LiftSlowSpeed, with help at the normal step. 4.8, a heavy
-- cargo (Info.heavy, not the lift twist): at that speed, and a piece on the hand trolley is never slow.
local function updateLift(session: Session)
	for player, held in session.held do
		if held.tool then
			continue -- (4.8: the trolley's own pace, Freight.walkSpeed)
		end
		-- 5.2: the heavy rule is the piece's (its order's): another order's light piece walks at the usual pace.
		local slow = if session.info.lift then Config.Missions.LiftSlowSpeed else held.pieces[1].heavy
		if slow == nil then
			if session.slowed[player] then
				restoreSpeed(session, player)
			end
			continue
		end
		local alone = held.pieces[1].horse == nil and not liftHelped(session, player, held.root.Position)
		if alone and session.slowed[player] ~= held.character then
			restoreSpeed(session, player)
			session.slowed[player] = held.character
			held.character:SetAttribute("CarrySpeed", slow)
			local humanoid = held.character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = slow
			end
			if not session.liftTold then
				session.liftTold = true
				tell(player, if session.info.lift then `Heavy! Alone you can barely walk. Get a crew mate within {Config.Missions.LiftHelpRange} studs to carry it faster.`
					else `Heavy! Alone you can barely walk: put it on the hand trolley, or get a crew mate within {Config.Missions.LiftHelpRange} studs.`)
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
	if held.tool and Equipment.pushing(player) == held.tool then
		Equipment.restore(player) -- 4.0: still pushing it, empty now
	end
	return held
end

local onLoose: (Session, Player, Loose) -> ()
local putDown: (Session, Player, boolean?) -> ()

-- 4.0: the pieces on a trolley's toe plate (side by side, then on top: Freight.trolleyStack) or the pallet on a jack's
-- forks, from the tool's deck (Equipment.deck). Welded to the tool (`weld`) while it is pushed, else standing there.
local function stackOnTool(tool: Equipment.Tool, pieces: { Piece }, weld: boolean)
	local base, deck = Equipment.deck(tool)
	local heights: { number } = {}
	for _, piece in pieces do
		local model = piece.model or buildPiece(piece)
		piece.model = model
		local h = pieceSize(model)
		table.insert(heights, h)
	end
	local spots = Freight.trolleyStack(heights)
	for index, piece in pieces do
		local model = piece.model :: Model
		local _, depth = pieceSize(model)
		-- A pallet's top boards rest on the forks (its stringers clear the ground); a piece stands on the toe plate
		-- against the frame.
		local at = if tool.kind == "jack" then deck * CFrame.new(0, -0.33, 0) else deck * CFrame.new(spots[index].x, spots[index].y, -(depth / 2 + 0.1))
		if weld and base then
			weldTo(model, base, at)
		else
			setDown(model, at)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
				end
			end
		end
	end
end

-- 3.7: the hands changed: the pieces stacked, the Put down (Let go) prompt on the top one, the character's attributes
-- (Carrying = the kind, CarryCount, CarryHands = 1 while a light piece leaves a hand free, CarrySpeed with two).
local function armHands(session: Session, player: Player, held: Held)
	if held.prompt then
		held.prompt:Destroy()
		held.prompt = nil
	end
	local count = #held.pieces
	local top = held.pieces[count]
	local tool = held.tool
	if tool then
		-- 4.0: on the trolley or the jack (its own G sets it down): a hand stays free for the back's doors.
		stackOnTool(tool, held.pieces, true)
		local character = held.character
		character:SetAttribute("Carrying", top.kind)
		character:SetAttribute("CarryCount", count)
		character:SetAttribute("CarryHands", 1)
		character:SetAttribute("CarrySpeed", Freight.walkSpeed(tool.kind, count))
		return
	end
	local made: ProximityPrompt? = nil
	local horse = top.horse
	if horse then
		local part = horsePart(horse)
		if part then
			local letGo = prompt(part, "Let go", "Horse", Enum.KeyCode.G, 0, session.owner)
			letGo.MaxActivationDistance = 13 -- the horse walks ~9 studs behind
			made = letGo
		end
	else
		stackHeld(held)
		local main = top.model and top.model.PrimaryPart
		if main then
			local owner = destName(session, top) -- 4.8, multi-drop: whose it is
			local down = prompt(main, if count > 1 then "Put one down" else "Put down", `{capital(session.info.piece)}{if owner then ` for {owner}` else ""}`, Enum.KeyCode.G, 0, session.owner)
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
	if not session.info.lift and not session.slowed[player] then -- (4.8: a heavy piece carried alone keeps its pace)
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
	local tool = Equipment.pushing(player)
	-- (5.2: a second piece only when both of them may go two at a time: orders of different cargo on one run)
	local info = session.info
	local both = math.min(handsMax(session, player), Freight.handsMax(piece.kind, piece.look, info.lift, info.pair, if tool then tool.kind else nil))
	if existing and (existing.character ~= character or existing.tool ~= tool or piece.horse or existing.pieces[1].horse or #existing.pieces >= both) then
		return false
	end
	if handsMax(session, player) <= 0 then
		return false -- 4.0: a pallet without a jack, a crate on a jack, a horse on a trolley (handsFull said why)
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
	local held: Held = existing or { pieces = {}, character = character, root = root, prompt = nil, last = root.CFrame, tool = tool }
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

-- A piece (not a horse) put on the ground at `frame`, with its Pick up prompt: a loose piece of the job.
local function layDown(session: Session, piece: Piece, frame: CFrame)
	local model = piece.model or buildPiece(piece)
	piece.model = model
	setDown(model, frame)
	local main = model.PrimaryPart :: BasePart
	local owner = piece.owner -- (4.8, multi-drop)
	local loose: Loose = { piece = piece, prompt = prompt(main, "Pick up", `{capital(session.info.piece)}{if owner then ` for {owner}` else ""}`, nil, holdFor(session), session.owner), handle = nil }
	loose.prompt.Triggered:Connect(function(by)
		onLoose(session, by, loose)
	end)
	table.insert(session.loose, loose)
end

-- Drop what the player holds right where they are; anybody of the crew can pick it up again. 3.7: one piece (the top
-- one: G again for the next), or all of them (`all`: the carrier died, left, sat down, lost the partner).
putDown = function(session: Session, player: Player, all: boolean?)
	local held = session.held[player]
	if not held then
		return
	end
	if held.tool then
		-- 4.0: the tool goes down with everything on it (Equipment.released → toolReleased puts them there).
		if Equipment.pushing(player) == held.tool then
			Equipment.setDown(player)
			return
		end
		held.tool = nil -- (not pushed any more: they all go on the ground below)
		all = true
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
			loose = { piece = piece, prompt = prompt(handle, "Lead", "Horse", nil, holdFor(session), session.owner), handle = handle }
		else
			layDown(session, piece, frame)
			continue
		end
		loose.prompt.Triggered:Connect(function(by)
			onLoose(session, by, loose)
		end)
		table.insert(session.loose, loose)
	end
	refresh(session)
end

-- 5.0: the owner died on a foot job: the pack's pieces fall where they stood (anybody of the job picks them up).
local function dropPack(session: Session)
	local at = session.packAt
	if #session.pack == 0 or not at then
		return
	end
	while #session.pack > 0 do
		layDown(session, table.remove(session.pack) :: Piece, dropFrame(session, at))
	end
	packShown(session)
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
-- 4.0: on a trolley up to TrolleyPieces, on a jack one pallet; a pallet never by hand (Freight.refusal says why).
local function handsFull(session: Session, player: Player): boolean
	local info = session.info
	local tool = toolOf(player)
	local max = handsMax(session, player)
	if max <= 0 then
		tell(player, Freight.refusal(info.kind, info.lift, info.pair, tool))
		return true
	end
	local held = session.held[player]
	if held then
		if #held.pieces < max then
			return false
		end
		if tool == "jack" then
			tell(player, "The jack carries one pallet at a time.")
		elseif tool == "trolley" then
			tell(player, `The trolley is full: {#held.pieces} {info.plural}.`)
		else
			tell(player, if #held.pieces > 1 then `Your hands are full: two {info.plural}.` else "Your hands are full.")
		end
		return true
	end
	if tool or not Cargo.carrying(player.Character) then
		return false
	end
	tell(player, "Your hands are full.")
	return true
end

-- 5.3 review, on foot: the owner's hands are full of pieces that fit the backpack and the next one (`piece`) does not
-- (an added order's bouquet while you hold two pizzas): the held ones that fit go into the pack first (while it has
-- room), so the hands take it.
local function makeRoom(session: Session, player: Player, piece: Piece?)
	local held = session.held[player]
	if not piece or not held or held.tool or not session.info.foot or player ~= session.owner or packTakes(session, { piece }, false) then
		return
	end
	local both = math.min(handsMax(session, player), Freight.handsMax(piece.kind, piece.look, session.info.lift, session.info.pair, nil))
	local looks: { string? } = {}
	for _, inHand in held.pieces do
		table.insert(looks, if inHand.horse then nil else inHand.look)
	end
	local need = Bag.makeRoom(looks, both, packFree(session)) -- (0: nothing to do, or it would not help: handsFull says why)
	if need <= 0 then
		return
	end
	local moved = 0
	for index = #held.pieces, 1, -1 do
		if moved >= need then
			break
		end
		local inHand = held.pieces[index]
		if packFits(inHand) and not inHand.horse then
			table.remove(held.pieces, index)
			stash(session, inHand)
			moved += 1
		end
	end
	if moved == 0 then
		return
	end
	if #held.pieces == 0 then
		clearHeld(session, player)
	else
		armHands(session, player, held)
	end
	tell(player, `{if moved == 1 then "One" else tostring(moved)} into your backpack ({#session.pack} / {session.info.pack or 0}): your hands take the {piece.name}.`)
end

onLoose = function(session: Session, player: Player, loose: Loose)
	if loose.tool or not allowed(session, player) then
		return
	end
	makeRoom(session, player, loose.piece)
	if intoPack(session, player, loose.piece) then
		-- 5.0, on foot: the hands are full, it goes into the owner's pack.
		local at = table.find(session.loose, loose)
		if not at then
			return
		end
		table.remove(session.loose, at)
		loose.prompt:Destroy()
		stash(session, loose.piece)
		if bagged(session) then
			Npcs.act(player.Character, "bag") -- 6.0: into the bag
		end
		refresh(session)
		session.info.changed()
		return
	end
	if handsFull(session, player) or pairRefused(session, player) then
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

-- 4.0: where pallet `index` stands at a stop: its staging spot (the dock, the receiving pad), else in a row beside the
-- person.
local function palletSpot(plan: Plan, index: number): CFrame
	local staging = plan.staging
	local right = plan.facing:Cross(Vector3.yAxis)
	local spot = if staging and #staging > 0 then staging[(index - 1) % #staging + 1] else plan.pile + right * (4 + (index - 1) * 4.6)
	spot = onGround(spot)
	return CFrame.lookAt(spot, spot + plan.facing)
end

-- A piece handed over or delivered: counted for the job and (5.2) for its order.
local function countDelivered(session: Session, piece: Piece?)
	session.deliveredTotal += 1
	local order = if piece then piece.order else 1
	session.deliveredBy[order] = (session.deliveredBy[order] or 0) + 1
end

local function handOver(session: Session, player: Player)
	local plan = session.plan
	if not plan then
		return
	end
	local foot = session.info.foot == true
	local who = if plan.person then plan.person.name else "They"
	local everything = if plan.nobody then "Everything for here is at the door." elseif foot then `{who} has everything.` else `{who} has everything. Put it back in the vehicle.`
	if session.moved >= neededNow(session) then
		tell(player, everything)
		return
	end
	local gave = 0
	local function give(piece: Piece)
		gave += 1
		session.moved += 1
		countDelivered(session, piece)
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
			setDown(model, if isPallet(session) then palletSpot(plan, session.moved) else stackFrame(plan, session.moved, -1))
			table.insert(session.props, model)
		end
	end
	-- 3.7: everything in your hands goes (two light pieces at once), as many as they still need. 4.8, multi-drop: a
	-- piece for another customer is refused (it goes back into the vehicle). 5.2, on foot (no vehicle to put it back
	-- into): the pieces for here go from anywhere in your hands, the others stay there.
	while session.held[player] and session.moved < neededNow(session) do
		local hands = session.held[player] :: Held
		local top = hands.pieces[#hands.pieces]
		if top and not forHere(session, top) then
			local mine: number? = nil
			if foot and not hands.tool then
				for index = #hands.pieces, 1, -1 do
					if forHere(session, hands.pieces[index]) then
						mine = index
						break
					end
				end
			end
			if mine then
				table.insert(hands.pieces, table.remove(hands.pieces, mine) :: Piece) -- (on top, then handed over)
				continue
			end
			if foot then
				break -- (then the pack's)
			end
			local car = session.car
			tell(player, `That {top.name} is for {top.owner or "another customer"}, not {if plan.person then plan.person.name else "here"}. Put it back in the {if car then Vehicles.cargoNoun(car) else "vehicle"} (E at the back).`)
			if gave > 0 then
				refresh(session)
			end
			return
		end
		local piece = release(session, player)
		if not piece then
			break
		end
		give(piece)
	end
	-- 5.0, on foot: then what is in the owner's pack (5.2: the pieces for here).
	if foot and player == session.owner and #session.pack > 0 then
		while session.moved < neededNow(session) do
			local at: number? = nil
			for index = #session.pack, 1, -1 do
				if forHere(session, session.pack[index]) then
					at = index
					break
				end
			end
			if not at then
				break
			end
			give(table.remove(session.pack, at) :: Piece)
		end
		packShown(session)
	end
	if gave == 0 then
		if foot then
			tell(player, `You carry nothing for {if plan.person then plan.person.name else "them"}.`)
		end
		return
	end
	say(session.person, if session.moved >= neededNow(session) then line(LINES.done) else line(LINES.thanks))
	Npcs.act(player.Character, "give") -- 5.7: held out …
	Npcs.act(session.person, "take") -- … and taken
	if plan.nobody then
		tell(player, `Left at the door of {plan.place or "the house"}.`) -- 5.3: nobody home
	end
	if session.held[player] and not foot then
		tell(player, everything)
	end
	refresh(session)
end

-- 5.3: a home's door (World's "Door" part of a house, of an apartment entrance) swings open for Places.DoorOpen s and
-- shuts again. An entrance's door does not take part in queries: found through its piers. 5.3 review: outward, onto
-- the porch (the house behind it is solid), and nobody bumps into it meanwhile.
local function swingDoor(door: Vector3, facing: Vector3)
	local places = Config.Jobs.Places
	local found: BasePart? = nil
	for _, hit in workspace:GetPartBoundsInRadius(door + Vector3.new(0, 3.5, 0), 4) do
		local parent = hit.Parent
		if hit.Name == "Door" then
			found = hit
		elseif parent and parent.Name == "Entrance" and parent:IsA("Folder") then
			local inside = parent:FindFirstChild("Door")
			if inside and inside:IsA("BasePart") then
				found = inside
			end
		end
		if found then
			break
		end
	end
	local part = found
	if not part or not part.Anchored or part:GetAttribute("Swinging") then
		return
	end
	local shut = part.CFrame
	local hinge = shut * CFrame.new(-part.Size.X / 2, 0, 0)
	local angle = math.rad(places.DoorSwing)
	local a = hinge * CFrame.Angles(0, angle, 0) * hinge:Inverse() * shut
	local b = hinge * CFrame.Angles(0, -angle, 0) * hinge:Inverse() * shut
	local open = if (a.Position - door):Dot(facing) > (b.Position - door):Dot(facing) then a else b
	local tweens = game:GetService("TweenService")
	local solid = part.CanCollide
	part:SetAttribute("Swinging", true)
	part.CanCollide = false
	tweens:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = open }):Play()
	task.delay(places.DoorOpen, function()
		if part.Parent then
			tweens:Create(part, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { CFrame = shut }):Play()
		end
		task.delay(0.5, function()
			part.CanCollide = solid
			part:SetAttribute("Swinging", nil)
		end)
	end)
end

-- 5.3: the owner came up to a home's door: they knock, the door opens and the receiver steps out (Places.KnockDelay
-- later). Nobody home (Plan.nobody): the door stays shut, the piece is left at the door.
-- 5.7: `by` (who came up) knocks with the fist and everybody near hears it (Npcs.act "knock"; with the door's creak
-- when it opens), the receiver waves as they step out.
-- 6.0: `thrown` = a piece thrown against the door did the knocking (no fist, nobody told).
local function knock(session: Session, plan: Plan, by: Player?, thrown: boolean?)
	local door = plan.door
	if not door then
		return
	end
	local person = plan.person
	local knocker = (by or session.owner).Character
	if plan.nobody or not person then
		if not thrown then
			Npcs.act(knocker, "knock", false)
			tell(session.owner, `You knock at {plan.place or "the door"}… nobody answers. Leave it at the door (E).`)
		end
		return
	end
	if not thrown then
		Npcs.act(knocker, "knock", true)
	end
	swingDoor(door, plan.facing)
	local visit = session.visit
	task.delay(Config.Jobs.Places.KnockDelay, function()
		-- (5.3 review: already handed over meanwhile, left at the door: nobody steps out any more)
		if session.ended or session.visit ~= visit or session.person or (session.moved > 0 and session.moved >= neededNow(session)) then
			return
		end
		local at = door + plan.facing * 1.3
		local npc = spawnFor(session, person, CFrame.lookAt(at, at + plan.facing))
		if not npc then
			return
		end
		session.person = npc
		table.insert(session.props, npc)
		say(npc, line(LINES.door))
		Npcs.act(npc, "wave") -- 5.7
	end)
end

-- 5.3, a newspaper round's door (Plan.toss): a paper for here out of your hands (5.3 review: a paper picked up off
-- the ground) or the owner's satchel, tossed in an arc from where you stand onto the porch. From farther than
-- Round.SureToss it may land in the bushes (JobRules.tossMiss): it still counts, as a miss (the round's tip goes, Jobs).
-- 5.3 review, checked here: farther than Round.TossRange (+ 2) from the porch, or no body, no toss; a wall, a house or
-- a car between you and the porch (a ray from you to it) and it lands in the bushes.
local function toss(session: Session, player: Player)
	local plan = session.plan
	if not plan then
		return
	end
	if session.moved >= neededNow(session) then
		tell(player, `{plan.place or "This door"} has its paper.`)
		return
	end
	local round = Config.Jobs.Round
	local root = rootOf(player.Character)
	if not root or flat(root.Position, plan.pile) > round.TossRange + 2 then
		tell(player, `Too far: walk up to {plan.place or "the house"} and toss it from closer.`)
		return
	end
	local held = session.held[player]
	local inHand: number? = nil
	if held and not held.tool then
		for index = #held.pieces, 1, -1 do
			if forHere(session, held.pieces[index]) then
				inHand = index
				break
			end
		end
	end
	local at: number? = nil
	if not inHand and player == session.owner then
		for index = #session.pack, 1, -1 do
			if forHere(session, session.pack[index]) then
				at = index
				break
			end
		end
	end
	if not inHand and not at then
		tell(player, if player == session.owner then "No paper for this door in your satchel." else "The papers are in the courier's satchel.")
		return
	end
	local piece: Piece
	if inHand and held then
		piece = table.remove(held.pieces, inHand) :: Piece
		if #held.pieces == 0 then
			clearHeld(session, player)
		else
			armHands(session, player, held)
		end
		if piece.model then
			piece.model:Destroy() -- (a new one flies)
			piece.model = nil
		end
	else
		piece = table.remove(session.pack, at :: number) :: Piece
	end
	session.moved += 1
	countDelivered(session, piece)
	local from = root.Position
	local miss = rng:NextNumber() < JobRules.tossMiss(flat(from, plan.pile))
	if not miss then
		-- (only the world: the people, the cargo and the stop's props let it through)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local skip: { Instance } = { folder }
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(skip, other.Character)
			end
		end
		for _, prop in session.props do
			table.insert(skip, prop)
		end
		local ride = Vehicles.get(player) -- (your own bike or car beside you does not block the throw)
		if ride then
			table.insert(skip, ride.model)
		end
		params:AddToFilter(skip)
		local target = plan.pile + Vector3.new(0, 2.5, 0) -- (over a porch step)
		for _ = 1, 4 do
			local hit = workspace:Raycast(from, target - from, params)
			if not hit or (hit.Position - target).Magnitude <= 2 then
				break
			end
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				params:AddToFilter(model) -- (a walker, a receiver: it flies over them)
			elseif hit.Instance.CanCollide then
				miss = true -- (a wall, a car, a fence between you and the porch)
				break
			else
				params:AddToFilter(hit.Instance)
			end
		end
	end
	local right = plan.facing:Cross(Vector3.yAxis)
	local land = plan.pile - plan.facing * 1.2
	if miss then
		land = plan.pile + right * rng:NextNumber(4, 7) * (if rng:NextNumber() < 0.5 then -1 else 1) + plan.facing * rng:NextNumber(1, 4)
		session.missBy[piece.order] = (session.missBy[piece.order] or 0) + 1
	end
	land = onGround(land)
	local model = buildPiece(piece)
	setDown(model, CFrame.new(from))
	table.insert(session.props, model)
	task.spawn(function()
		for n = 1, 10 do
			if not model.Parent then
				return
			end
			local t = n / 10
			model:PivotTo(CFrame.new(from:Lerp(land, t) + Vector3.new(0, math.sin(t * math.pi) * 4, 0)) * CFrame.Angles(0, t * 6, 0))
			task.wait(0.03)
		end
		if model.Parent then
			model:PivotTo(CFrame.lookAt(land, land + right))
		end
	end)
	packShown(session)
	tell(player, if miss then "In the bushes! It counts, but it's a miss: no tip for this round." else `On the porch of {plan.place or "the house"}.`)
	refresh(session)
	session.info.changed()
end

-- ── 6.0: throwing at a door ────────────────────────────────────────────────

-- The current stop when a piece may be thrown at it: a foot job's home drop (Plan.door) or a round's door (Plan.toss),
-- not blocked, still waiting for a piece.
local function throwStop(session: Session): Plan?
	local plan = session.plan
	if session.ended or session.info.foot ~= true or session.blocked or not plan or plan.stage ~= "drop" or not (plan.door or plan.toss) then
		return nil
	end
	return if session.moved < neededNow(session) then plan else nil
end

-- What the player would throw here: a piece for this stop that may fly, the top one in the hands first, then (the
-- owner) the pack's last. Where it is ("hands" | "pack") and its index; else nil and why ("fragile" | "none").
local function throwPick(session: Session, player: Player): (string?, number?, string)
	local job = session.info.fragile == true
	local fragile = false
	local held = session.held[player]
	if held and not held.tool then
		for index = #held.pieces, 1, -1 do
			local piece = held.pieces[index]
			if piece.horse == nil and forHere(session, piece) then
				if Throws.throwable(piece.look, job) then
					return "hands", index, ""
				end
				fragile = fragile or Throws.fragile(piece.look, job)
			end
		end
	end
	if player == session.owner then
		for index = #session.pack, 1, -1 do
			local piece = session.pack[index]
			if forHere(session, piece) then
				if Throws.throwable(piece.look, job) then
					return "pack", index, ""
				end
				fragile = fragile or Throws.fragile(piece.look, job)
			end
		end
	end
	return nil, nil, if fragile then "fragile" else "none"
end

-- The owner's attributes for client/Throw.luau (every tick, written only when they change): ThrowTo = the door's spot
-- while a piece for it is with you, ThrowStop = the stop's visit (the remote names it), ThrowFragile = only fragile ones.
local function throwShown(session: Session)
	local owner = session.owner
	local plan = throwStop(session)
	local to: Vector3? = nil
	local fragile: boolean? = nil
	if plan then
		local where, _, why = throwPick(session, owner)
		if where or why == "fragile" then
			to = plan.pile
			fragile = if where then nil else true
		end
	end
	local stop = if to then session.visit else nil
	if owner:GetAttribute("ThrowTo") ~= to then
		owner:SetAttribute("ThrowTo", to)
	end
	if owner:GetAttribute("ThrowStop") ~= stop then
		owner:SetAttribute("ThrowStop", stop)
	end
	if owner:GetAttribute("ThrowFragile") ~= fragile then
		owner:SetAttribute("ThrowFragile", fragile)
	end
end

local function vec(v: Vector3): Throws.Vec
	return { v.X, v.Y, v.Z }
end

local function v3(v: Throws.Vec): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

-- A ray of the throw through the world only: the people, the cargo, the stop's props, your ride and anything that does
-- not collide let it through; a body (a zombie, a walker) is flown over.
local function throwRay(session: Session, player: Player): (Vector3, Vector3) -> RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local skip: { Instance } = { folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	for _, prop in session.props do
		table.insert(skip, prop)
	end
	for _, name in { "Npcs", "Zombies", "Animals", "Effects", "Loot" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	local ride = Vehicles.get(player)
	if ride then
		table.insert(skip, ride.model)
	end
	params:AddToFilter(skip)
	return function(from: Vector3, to: Vector3): RaycastResult?
		for _ = 1, 4 do
			local hit = workspace:Raycast(from, to - from, params)
			if not hit then
				return nil
			end
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				params:AddToFilter(model)
			else
				return hit
			end
		end
		return nil
	end
end

-- The piece flies along the arc for everybody (anchored, not solid, moved every frame), then `done`.
local function fly(model: Model, trace: Throws.Trace, done: () -> ())
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	task.spawn(function()
		local start = os.clock()
		while model.Parent do
			local t = os.clock() - start
			model:PivotTo(CFrame.new(v3(Throws.at(trace, t))) * CFrame.Angles(t * 9, t * 4, 0))
			if t >= trace.time then
				break
			end
			task.wait()
		end
		if model.Parent then
			done()
		end
	end)
end

-- A throw from the player's hands or the owner's pack at the door (the "Throw" remote: Cargo.start checked the stop).
local function throwAt(session: Session, player: Player, direction: Vector3, power: number)
	local plan = throwStop(session)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	if not plan or not character or not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart ~= nil or Equipment.pushing(player) then
		return
	end
	local tuning = Config.Throw
	if flat(root.Position, plan.pile) > tuning.Range + 3 then -- (+3: the client's view of you is a moment old)
		tell(player, `Too far to throw: come within {tuning.Range} studs of the door.`)
		return
	end
	local where, index, why = throwPick(session, player)
	local velocity = Throws.velocity(vec(direction), power)
	if not where or not index then
		tell(player, if why == "fragile" then "Too fragile to throw: hand it over at the door." else "Nothing to throw at this door.")
		return
	end
	if not velocity then
		return
	end
	local ray = throwRay(session, player)
	local from = v3(Throws.release(vec(root.Position), vec(root.CFrame.LookVector)))
	if ray(root.Position, from) then
		tell(player, "No room to throw here.")
		return
	end
	local piece: Piece
	local held = session.held[player]
	if where == "hands" and held then
		piece = table.remove(held.pieces, index) :: Piece
		if #held.pieces == 0 then
			clearHeld(session, player)
		else
			armHands(session, player, held)
		end
		if piece.model then
			piece.model:Destroy() -- (a new one flies)
			piece.model = nil
		end
	else
		piece = table.remove(session.pack, index) :: Piece
		packShown(session)
	end
	Npcs.act(character, "throw")
	local trace = Throws.trace(vec(from), velocity, function(a: Throws.Vec, b: Throws.Vec): Throws.Hit?
		local hit = ray(v3(a), v3(b))
		return if hit then { at = vec(hit.Position), normal = vec(hit.Normal) } else nil
	end)
	local land = v3(trace.land)
	local hitDoor = trace.grounded and Throws.landed(trace.land, vec(plan.pile))
	local right = plan.facing:Cross(Vector3.yAxis)
	local visit = session.visit
	local model = buildPiece(piece)
	model:PivotTo(CFrame.new(from))
	local tip: Throws.Tip? = nil
	local rest: CFrame
	local loose: Loose? = nil
	if hitDoor or plan.toss then
		-- At the door (or the round's paper anywhere: it counts, a miss in the bushes): delivered now.
		session.moved += 1
		countDelivered(session, piece)
		table.insert(session.props, model)
		if not hitDoor then
			session.missBy[piece.order] = (session.missBy[piece.order] or 0) + 1
		end
		local spot = if trace.grounded then land else onGround(plan.pile + right * 5) -- (a paper flying on: the bushes)
		rest = CFrame.lookAt(spot, spot + right)
		if hitDoor and not plan.toss then -- (6.0 review: a round's papers tip nothing: they are tossed by design)
			local over = not trace.bounced and ray(from, land + Vector3.new(0, 1.5, 0)) ~= nil
			tip = Throws.tip(flat(from, land), over, trace.bounced)
		end
	else
		-- A miss: a loose piece where it lands (on a roof, or nowhere: it rolls down beside the door).
		local ground = onGround(land)
		if not trace.grounded or math.abs(land.Y - plan.pile.Y) > 5 or math.abs(ground.Y - land.Y) > 1 then
			ground = onGround(plan.pile + right * rng:NextNumber(3, 5) * (if rng:NextNumber() < 0.5 then -1 else 1))
		end
		rest = CFrame.lookAt(ground, ground + right)
		piece.model = model
		layDown(session, piece, rest)
		loose = session.loose[#session.loose]
		if loose then
			loose.prompt.Enabled = false
		end
	end
	local paid = if tip then tip.total else 0
	-- 6.0 review: the trickshot tips of one run are capped (Config.Throw.TipCap).
	local before = tipsPaid[session] or 0
	paid = math.max(0, math.min(paid, (Config.Throw.TipCap or 60) - before))
	if paid > 0 then
		tipsPaid[session] = before + paid
		PlayerData.addMoney(player, paid)
	end
	fly(model, trace, function()
		setDown(model, rest)
		if loose then
			loose.prompt.Enabled = true
		end
		local same = not session.ended and session.visit == visit
		if hitDoor and same then
			if session.person then
				say(session.person, line(LINES.thanks)) -- caught
				Npcs.act(session.person, "take")
			elseif plan.door and not session.knocked then
				session.knocked = true -- (it hit the door: they heard)
				knock(session, plan, player, true)
			end
		end
		if hitDoor then
			Net.get("Throw"):FireClient(player, "landed", { tip = paid, far = if tip then tip.far else 0, over = if tip then tip.over else 0, wall = if tip then tip.wall else 0, span = math.floor(flat(from, land) + 0.5) })
		elseif plan.toss then
			tell(player, "In the bushes! It counts, but it's a miss: no tip for this round.")
		else
			tell(player, `Missed the door: the {piece.name} is on the ground. Pick it up (E).`)
		end
	end)
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
	if plan.stage == "drop" and plan.toss then
		toss(session, player) -- 5.3, the newspaper round
		return
	end
	if plan.stage == "drop" then
		local packed = session.info.foot == true and player == session.owner and #session.pack > 0 -- 5.0
		if not session.held[player] and not packed then
			if session.info.foot then
				tell(player, if #session.loose > 0 then `Pick up the {session.info.piece} you put down first.` else `You carry nothing for {if plan.person then plan.person.name else "them"}.`)
				return
			end
			local car = session.car
			local noun = if car then Vehicles.cargoNoun(car) else "vehicle"
			tell(player, if isPallet(session) then `Unload a pallet from the {noun} onto a pallet jack first (E at the back).`
				else `Take {article(session.info.piece)} out of the {noun} first (E at the back).`)
			return
		end
		handOver(session, player)
		session.info.changed()
		return
	end
	if plan.bundle and player ~= session.owner then
		tell(player, "The bundle goes in the courier's satchel.") -- 5.3 review: the round's papers are the owner's
		return
	end
	if plan.bundle and session.info.foot and #session.pile > 0 then
		-- 5.3, the newspaper round: the whole bundle into your satchel at once.
		local count = #session.pile
		while #session.pile > 0 do
			stash(session, table.remove(session.pile) :: Piece)
		end
		session.moved += count
		say(session.person, line(LINES.bundle))
		tell(player, `{count} papers in your satchel: one for every door on the round.`)
		refresh(session)
		session.info.changed()
		return
	end
	makeRoom(session, player, session.pile[#session.pile])
	if intoPack(session, player, session.pile[#session.pile]) then
		-- 5.0, on foot: the hands are full, the next piece goes into the owner's pack.
		local piece = table.remove(session.pile)
		if piece then
			stash(session, piece)
			session.moved += 1
			local bag = bagged(session) -- 6.0: dropped into the bag in your hand
			say(session.person, line(LINES.take))
			Npcs.act(session.person, "give") -- 5.7
			Npcs.act(player.Character, if bag then "bag" else "take")
			tell(player, if not packFits(piece) then `Onto your bike ({#session.pack} / {session.info.pack or 0}).`
				elseif bag then `Into the bag ({#session.pack} / {session.info.pack or 0}).`
				else `Into your backpack ({#session.pack} / {session.info.pack or 0}).`)
			refresh(session)
			session.info.changed()
		end
		return
	end
	if handsFull(session, player) or pairRefused(session, player) then
		return
	end
	-- 4.0: onto a trolley as many as fit at once (the hands: one).
	local loaded = 0
	repeat
		local piece = table.remove(session.pile)
		if not piece then
			break
		end
		if take(session, player, piece) then
			loaded += 1
			if loaded == 1 then
				say(session.person, if piece.horse then line(LINES.horse) else line(LINES.take))
				if not piece.horse and not (session.held[player] and session.held[player].tool) then
					Npcs.act(session.person, "give") -- 5.7: handed to you, you reach for it
					Npcs.act(player.Character, "take")
				end
			end
		else
			table.insert(session.pile, piece)
			break
		end
		local held = session.held[player]
	until not held or not held.tool or #held.pieces >= handsMax(session, player)
	if session.info.foot then
		session.moved += loaded -- 5.0, on foot: picked up is handled (there is no loading)
	end
	refresh(session)
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
	local pallet = isPallet(session)
	local noun = Vehicles.cargoNoun(car)
	if backShut(session) then
		-- 3.2: only through an open back (a race with somebody closing it). 3.7: a light piece leaves a hand free.
		-- 4.0: so does a tool (one hand on its handle).
		local open = Vehicles.backVerb(car, true)
		local full = held ~= nil and held.tool == nil and (#held.pieces > 1 or handsMax(session) == 1)
		tell(player, if full then `Put it down (G) and {open} (E).` else `{capital(open)} first (E).`)
		return
	end
	local handling = plan ~= nil and plan.stage == "drop" and handled(plan.mode)
	if held and (not handling or session.moved >= neededNow(session) or holdsOther(session, player)) then -- (4.8: another customer's piece goes back in)
		-- 4.0: as many as the vehicle has room for (a pallet: only a vehicle that takes pallets); the rest stay on
		-- the trolley. The hands' pieces go in as before.
		local moving: { Piece } = held.pieces
		if held.tool then
			local room = if pallet then Freight.palletRoom(Freight.palletsOf(car.id, car.stage), #session.load)
				else Freight.pieceRoom(Vehicles.capacity(car, session.info.look), #session.load) -- (4.6: a Roof Rack's light slot too)
			if room <= 0 then
				local takes = if pallet then Freight.palletsOf(car.id, car.stage) else 0
				tell(player, if pallet and takes <= 0 then `This {noun} takes no pallets. {Freight.palletAdvice(1)}`
					elseif pallet then `The {noun} is full: it takes {takes} {if takes == 1 then "pallet" else "pallets"}.`
					else `The {noun} is full.`)
				return
			end
			moving = {}
			for _ = 1, math.min(room, #held.pieces) do
				local piece = release(session, player)
				if piece then
					table.insert(moving, 1, piece)
				end
			end
			if session.held[player] then
				tell(player, `The {noun} is full: {#(session.held[player] :: Held).pieces} stay on the trolley.`)
			end
		else
			clearHeld(session, player)
		end
		local before = session.moved
		for _, piece in moving do
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
			tell(player, `The {noun} is empty.`)
			return
		end
		local max = handsMax(session, player)
		if max <= 0 then
			tell(player, Freight.refusal(session.info.kind, session.info.lift, session.info.pair, toolOf(player)))
			return
		end
		if held and #held.pieces >= max then
			tell(player, if pallet then `The jack carries one pallet: set it down at the receiving dock (E).`
				elseif held.tool then `The trolley is full: push it to {who} (E).`
				else `Hands full: carry {if #held.pieces > 1 then "them" else "it"} to {who} (E).`)
			return
		end
		if not toTakeOut(session) then
			tell(player, `{capital(who)} gets no more: carry what you have.`)
			return
		end
		if pairRefused(session, player) then
			return
		end
		-- One piece (3.7: a second light one into a free hand); 4.0: onto a trolley as many as fit and are needed.
		-- 4.8, multi-drop: the pieces for this customer (toTakeOut said there is one).
		repeat
			local found = takeHere(session)
			if not found then
				break
			end
			local piece: Piece = found
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
				break
			end
			local now = session.held[player]
		until not now or not now.tool or #now.pieces >= max or not toTakeOut(session)
		session.info.changed()
		return
	end
	tell(player, if pallet then "Lift a pallet with a pallet jack first." else `Pick up {article(session.info.piece)} first.`)
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
	local p = prompt(door, "Load", "", nil, holdFor(session), session.owner)
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
	local right = plan.facing:Cross(Vector3.yAxis)
	-- 5.3 review: another live job whose stop is here too (two couriers at Luigi's): this one's pile, its clerk and its
	-- pieces go Places.SessionGap to the side (the first free slot: 0, right, left, twice as far right …).
	session.anchor = plan.pile
	local taken: { [number]: boolean } = {}
	for _, other in active do
		local there = other.anchor
		if other ~= session and not other.ended and other.built and there and flat(there, plan.pile) < 2 then
			taken[other.slot] = true
		end
	end
	local slot = 0
	while taken[slot] do
		slot = if slot > 0 then -slot else -slot + 1
	end
	session.slot = slot
	if slot ~= 0 and plan.mode ~= "pallet" and not plan.toss then
		local shift = right * slot * Config.Jobs.Places.SessionGap
		plan.pile += shift
		local personAt = plan.personAt
		if personAt then
			plan.personAt = personAt + shift
		end
	end
	local base = onGround(plan.pile)
	-- 5.3: a storefront's cook / clerk stands in the doorway (Plan.personAt); at a home the receiver is inside until
	-- you knock (knock); a newspaper round's door has nobody to meet.
	if plan.person and not plan.door and not plan.toss then
		local at = plan.personAt or base
		local npc = spawnFor(session, plan.person, CFrame.lookAt(at, at + plan.facing))
		if not npc then
			return
		end
		session.person = npc
		table.insert(session.props, npc)
	end
	local pallet = plan.mode == "pallet"
	if pallet and plan.stage == "pickup" then
		-- 4.0: the pallets wait on the dock (Plan.staging), each with its own "Lift pallet" (a Loose piece: lifted with
		-- a jack, loaded, counted like every piece put down).
		for n = 1, plan.needed do
			local piece = newPiece(session)
			local model = buildPiece(piece)
			setDown(model, palletSpot(plan, n))
			piece.model = model
			local main = model.PrimaryPart :: BasePart
			local loose: Loose = { piece = piece, prompt = prompt(main, "Lift pallet", "Pallet", nil, holdFor(session), session.owner), handle = nil, tool = nil }
			loose.prompt.MaxActivationDistance = Tuning.PromptDistance - 2
			loose.prompt.Triggered:Connect(function(by)
				onLoose(session, by, loose)
			end)
			table.insert(session.loose, loose)
		end
		refresh(session)
		return
	end
	if handled(plan.mode) then
		local part = Instance.new("Part")
		part.Name = "CargoPile"
		part.Size = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Position = base + right * 1.5 + Vector3.new(0, 2.5, 0)
		local staging = plan.staging
		if pallet and staging and #staging > 0 then
			-- The receiving dock's pad: "Set down pallet" in its middle.
			local middle = Vector3.zero
			for _, spot in staging do
				middle += spot
			end
			part.Position = onGround(middle / #staging) + Vector3.new(0, 2.5, 0)
		end
		part.Parent = folder
		session.pilePart = part
		table.insert(session.props, part)
		local horse = plan.mode == "lead"
		local action = if plan.stage == "pickup" then (if horse then "Lead" elseif plan.bundle then "Pick up the bundle" else "Pick up")
			elseif pallet then "Set down pallet"
			elseif plan.toss then "Toss newspaper" -- 5.3
			elseif plan.nobody then "Leave at the door"
			else "Hand over"
		local p = prompt(part, action, plan.place or "", nil, holdFor(session), session.owner)
		p.MaxActivationDistance = if plan.toss then Config.Jobs.Round.TossRange else Tuning.PromptDistance + 2
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

local function kidArrived(session: Session, piece: Piece, visit: number, timedOut: boolean)
	local index = table.find(session.walking, piece)
	if session.ended or session.visit ~= visit or not index then
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
		countDelivered(session, piece)
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
	local visit = session.visit
	Npcs.walkTo(npc, target, function(ok: boolean)
		-- Could not get there in time (a curb, a car in the way): close enough, count it.
		kidArrived(session, piece, visit, not ok)
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
			kidArrived(session, piece, session.visit, true)
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
			countDelivered(session, piece)
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
		made = 0,
		pack = {},
		packAt = nil,
		packHumanoid = nil,
		visit = 0,
		madeHere = 0,
		deliveredBy = {},
		lostBy = {},
		knocked = false,
		missBy = {},
		anchor = nil,
		slot = 0,
	}
	active[owner] = session
	packShown(session)
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

-- The next stop; the last one's people stay a moment. 4.8: `replace` (a road event's side pick-up put in front of the
-- stop you drive to, server/Jobs.luau): the current stop is swapped for this one, the stop's number stays (nothing of
-- it may have been built or handled yet). 5.2: a Plan with its `index` is that stop of the job (the stops come in any
-- order); `replace` then only says the stop left was not done (its people go at once, nothing lingers).
function Cargo.setStop(session: Session, plan: Plan, replace: boolean?)
	if session.plan then
		clearStop(session, not replace)
	end
	if plan.index then
		session.stop = plan.index
	elseif not replace then
		session.stop += 1
	end
	session.visit += 1
	session.madeHere = 0
	session.plan = plan
	session.built = false
	session.greeted = false
	session.moved = 0
	session.hold = 0
	session.served = false
	session.customers = false
	session.nextKid = 0
	session.knocked = false
	session.anchor = nil
	session.slot = 0
	refresh(session)
end

-- Every job tick (Jobs, 0.2 s): follow the car, check the carriers, build the stop, walk the kids, serve.
function Cargo.update(session: Session, dt: number)
	if session.ended then
		return
	end
	local car = if session.info.foot then nil else Vehicles.get(session.owner) -- (5.0: no vehicle on foot)
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
			and (held.tool == nil or (Equipment.pushing(player) == held.tool and root == held.root)) -- 4.0: the tool let go
		if fine and root then
			if root ~= held.root then
				-- The body was rebuilt (the avatar loaded): hold it in the new one.
				held.root = root
				if held.pieces[1].horse == nil then
					stackHeld(held)
				end
			end
			held.last = root.CFrame
		elseif session.info.foot and player == session.owner and player.Character == character and humanoid and humanoid.Health > 0
			and humanoid.SeatPart ~= nil and held.tool == nil and held.pieces[1].horse == nil and packTakes(session, held.pieces, true) then
			-- 5.0, on foot: sitting down (a car) stows the hands into the pack while it has room. 5.3: a piece that does
			-- not fit a backpack only onto the bike's rack.
			clearHeld(session, player)
			for _, piece in held.pieces do
				stash(session, piece)
			end
			tell(player, if (session.info.rack or 0) > 0 then `Stowed on your bike ({#session.pack} / {session.info.pack or 0}).` else `Stowed in your backpack ({#session.pack} / {session.info.pack or 0}).`)
			dropped = true
		else
			putDown(session, player, true)
			dropped = true
		end
	end
	-- 5.0, on foot: the pack goes where the owner goes; when they die its pieces fall there. Only a death drops it: a
	-- character being swapped (the avatar rebuilt, no humanoid or root for a moment) keeps it on the back.
	if session.info.foot then
		local character = session.owner.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = rootOf(character)
		local last = session.packHumanoid
		if last and last ~= humanoid and last.Health <= 0 and #session.pack > 0 then
			dropPack(session) -- (died and already respawned between two looks: where they fell)
			dropped = true
		end
		if humanoid and root and humanoid.Health > 0 then
			session.packAt = root.CFrame
			session.packHumanoid = humanoid
		elseif humanoid and humanoid.Health <= 0 and #session.pack > 0 then
			dropPack(session)
			dropped = true
		end
	end
	if session.info.pair and updatePair(session) then
		dropped = true
	end
	if dropped then
		session.info.changed()
	end
	if next(session.held) ~= nil or next(session.slowed) ~= nil then
		updateLift(session) -- (the lift twist, 4.8's heavy rule: 5.2, by the piece's order)
	end
	throwShown(session) -- 6.0

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
		Npcs.act(session.person, "wave") -- 5.7: over here!
		local handling = handled(plan.mode)
		if plan.mode == "pallet" then
			say(session.person, if plan.stage == "pickup" then `{plan.needed} {if plan.needed == 1 then "pallet" else "pallets"} on the dock. Grab a pallet jack!` else "Set them down on the marked pad, please!")
		elseif plan.stage == "pickup" and handling then
			say(session.person, if plan.needed == 1 then `Over here! One {session.info.piece}, handle it with care.` else `Over here! {plan.needed} {session.info.plural} {if session.info.foot then "for you" else "to load"}.`)
		elseif plan.stage == "drop" and handling then
			say(session.person, "Finally! Bring it over here.")
		elseif plan.mode == "board" and isPatient(session) then
			say(session.person, if plan.stage == "pickup" then "Over here! Please hurry, it's bad." else "Bring the patient to me, quick!")
		elseif plan.mode == "board" and isSurvivor(session) then
			say(session.person, if plan.stage == "pickup" then "Over here! We've been holding out for days!" else "Bring them in, we've got beds ready!")
		end
	end
	-- 5.3: at a home's door you knock (the receiver comes out). 5.3 review: the owner or any crew mate.
	local door = plan.door
	if session.built and door and not session.knocked and plan.stage == "drop" then
		local near = position ~= nil and flat(position, door) < Config.Jobs.Places.KnockRange
		local by = if near then session.owner else nil -- 5.7: who knocks
		if not near then
			for _, player in Players:GetPlayers() do
				local root = rootOf(player.Character)
				if player ~= session.owner and root and flat(root.Position, door) < Config.Jobs.Places.KnockRange and session.info.allowed(player) then
					near = true
					by = player
					break
				end
			end
		end
		if near then
			session.knocked = true
			knock(session, plan, by)
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
	-- 5.2: the pieces of this pick-up still in hands or put down (another order's carried along do not hold it up).
	local held, loose = 0, 0
	for _, hands in session.held do
		for _, piece in hands.pieces do
			if piece.origin == session.stop then
				held += 1
			end
		end
	end
	for _, item in session.loose do
		if item.piece.origin == session.stop then
			loose += 1
		end
	end
	if plan.stage == "pickup" and session.info.foot then
		-- 5.0, on foot: everything picked up (in hands or in the pack), nothing left on the ground: walk on with it.
		return session.built and session.moved >= plan.needed and #session.pile == 0 and loose == 0
	end
	if plan.stage == "pickup" then
		return session.built and session.moved >= plan.needed and #session.pile == 0 and held == 0 and loose == 0
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
	return #session.load + heldCount(session) + #session.loose + pile + #session.walking + spawning + #session.pack -- (5.0: the pack)
end

-- ── 5.2: several orders ─────────────────────────────────────────────────────

-- Every piece of the job still out there (in the vehicle, in hands, put down, in the pack, walking), with where it is:
-- "vehicle" | "hands" | "ground" | "pack" | "walking".
local function eachPiece(session: Session, visit: (Piece, string) -> ())
	for _, piece in session.load do
		visit(piece, "vehicle")
	end
	for _, hands in session.held do
		for _, piece in hands.pieces do
			visit(piece, "hands")
		end
	end
	for _, item in session.loose do
		visit(item.piece, "ground")
	end
	for _, piece in session.pack do
		visit(piece, "pack")
	end
	for _, piece in session.walking do
		visit(piece, "walking")
	end
end

-- Has the current stop been started (something taken from its pile, handed over, people walking, a serve held)? Then
-- it stays the current one until it is done (switching would lose what is half done).
function Cargo.engaged(session: Session): boolean
	local plan = session.plan
	if not plan or not session.built then
		return false
	end
	if session.busy > 0 or #session.walking > 0 or session.moved > 0 or session.hold > 0 then
		return true
	end
	if plan.stage == "pickup" then
		return #session.pile < plan.needed
	end
	return session.car ~= nil and outHere(session) > 0 -- (a piece for here taken out of the vehicle)
end

-- The pieces with you (or put down, walking off) by the stop they go to (pieces without one are not counted).
function Cargo.withYou(session: Session): { [number]: number }
	local out: { [number]: number } = {}
	eachPiece(session, function(piece: Piece)
		local dest = piece.dest
		if dest then
			out[dest] = (out[dest] or 0) + 1
		end
	end)
	return out
end

-- 5.2 review: the pieces with you by order (in hands, on a trolley, in the pack, in the vehicle); `vehicleOnly`: only
-- the ones in the vehicle (what a crash, a hit or a jolt reaches).
function Cargo.ordersWithYou(session: Session, vehicleOnly: boolean?): { [number]: number }
	local out: { [number]: number } = {}
	eachPiece(session, function(piece: Piece, where: string)
		if where == "vehicle" or (not vehicleOnly and (where == "hands" or where == "pack")) then
			out[piece.order] = (out[piece.order] or 0) + 1
		end
	end)
	return out
end

-- Like Cargo.remaining, for one order: its pieces on the way, and the current stop's pile when it is that order's.
function Cargo.remainingFor(session: Session, order: number): number
	local n = 0
	eachPiece(session, function(piece: Piece)
		if piece.order == order then
			n += 1
		end
	end)
	local plan = session.plan
	if plan and (plan.order or 1) == order then
		local pile = #session.pile
		if plan.stage == "pickup" and (not session.built or session.busy > 0) then
			pile = math.max(pile, plan.needed)
		end
		n += pile + (if plan.stage ~= "pickup" then session.busy else 0)
	end
	return n
end

-- Pieces of an order handed over, and lost (stolen, wrecked).
function Cargo.deliveredOf(session: Session, order: number): number
	return session.deliveredBy[order] or 0
end

function Cargo.lostOf(session: Session, order: number): number
	return session.lostBy[order] or 0
end

-- A failed order's pieces go back (out of the vehicle, the hands, a trolley, the ground, the pack; its pile if its stop
-- is the current one). Returns how many.
function Cargo.dropOrder(session: Session, order: number): number
	if session.ended then
		return 0
	end
	local n = 0
	local function gone(piece: Piece)
		n += 1
		if piece.horse then
			Animals.remove(piece.horse)
		end
		if piece.npc then
			removeNpc(piece.npc)
			piece.npc = nil
		end
		if piece.model then
			piece.model:Destroy()
			piece.model = nil
		end
	end
	for index = #session.load, 1, -1 do
		if session.load[index].order == order then
			gone(table.remove(session.load, index) :: Piece)
		end
	end
	for index = #session.pack, 1, -1 do
		if session.pack[index].order == order then
			gone(table.remove(session.pack, index) :: Piece)
		end
	end
	-- (5.2 review: a trolley's pieces too, set down or pushed: the ones left on it close up)
	local tools: { Equipment.Tool } = {}
	for index = #session.loose, 1, -1 do
		local item = session.loose[index]
		if item.piece.order == order then
			table.remove(session.loose, index)
			item.prompt:Destroy()
			if item.handle then
				item.handle:Destroy()
			end
			gone(item.piece)
			local tool = item.tool
			if tool and not table.find(tools, tool) then
				table.insert(tools, tool)
			end
		end
	end
	for _, tool in tools do
		local left: { Piece } = {}
		for _, item in session.loose do
			if item.tool == tool then
				table.insert(left, item.piece)
			end
		end
		if #left > 0 then
			stackOnTool(tool, left, false)
		end
	end
	for player, hands in table.clone(session.held) do
		local keep: { Piece } = {}
		for _, piece in hands.pieces do
			if piece.order == order then
				gone(piece)
			else
				table.insert(keep, piece)
			end
		end
		if #keep < #hands.pieces then
			if #keep == 0 then
				clearHeld(session, player)
			else
				hands.pieces = keep
				armHands(session, player, hands)
			end
		end
	end
	local plan = session.plan
	if plan and plan.order == order then
		for _, piece in session.pile do
			gone(piece)
		end
		table.clear(session.pile)
	end
	render(session)
	refresh(session)
	packShown(session)
	session.info.changed()
	return n
end

-- What you carry, piece by piece (the job payload's `carried`): its order, its look, its name, where it is ("hands" |
-- "pack" | "vehicle"; 5.3: "rack", a bike's rack / basket / box: the pieces that do not fit a backpack, and the ones
-- over the backpack's room) and the stop it goes to and its customer (nil for a piece any drop of its order takes).
export type Carried = { order: number, look: string, name: string, where: string, dest: number?, owner: string? }
function Cargo.carried(session: Session): { Carried }
	local out: { Carried } = {}
	local backpack = math.max(0, (session.info.pack or 0) - (session.info.rack or 0))
	local inBackpack = 0
	eachPiece(session, function(piece: Piece, where: string)
		local shown = where == "hands" or where == "pack" or where == "vehicle"
		if shown then
			local place = where
			if where == "pack" and (session.info.rack or 0) > 0 then
				if packFits(piece) and inBackpack < backpack then
					inBackpack += 1
				else
					place = "rack"
				end
			end
			local entry: Carried = { order = piece.order, look = piece.look, name = piece.name, where = place, dest = piece.dest, owner = piece.owner }
			table.insert(out, entry)
		end
	end)
	return out
end

-- 5.3: the newspapers of an order that landed in the bushes (Round.MissAtRange: tossed from afar).
function Cargo.missesOf(session: Session, order: number): number
	return session.missBy[order] or 0
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
	session.lostBy[piece.order] = (session.lostBy[piece.order] or 0) + 1 -- 5.2
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
		session.lostBy[piece.order] = (session.lostBy[piece.order] or 0) + 1 -- 5.2
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
	local handling = plan ~= nil and handled(plan.mode)
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
		pack = #session.pack, -- 5.0
		packRoom = if session.info.foot then session.info.pack or 0 else 0,
		rack = if session.info.foot then session.info.rack or 0 else 0,
		foot = session.info.foot == true,
	}
end

-- 4.0: the hints with a trolley or a pallet jack, and every step of a pallet stop (Cargo.step asks first). Nil: the
-- usual hints. The handling is "drive" or "carry" (the HUD knows those: a pallet stop is carried, on a jack).
local function toolStep(session: Session, plan: Plan, near: boolean): (string?, string?)
	local owner = session.owner
	local tool = Equipment.pushing(owner)
	local pallet = plan.mode == "pallet"
	local pickup = plan.stage == "pickup"
	local held = session.held[owner]
	local car = session.car
	local noun = if car then Vehicles.cargoNoun(car) else "vehicle"
	local circle = "red" -- 4.4.1: the stop's circle is the contract red, the pick-up's too (client/Hud.luau)
	local seatedCar = Vehicles.seatedIn(owner)
	local who = if plan.person then plan.person.name else "the receiver"
	local shut = car ~= nil and backShut(session)
	local open = if car then Vehicles.backVerb(car, true) else "open the back"
	local kind = if tool then tool.kind else nil
	local name = if kind == "jack" then "pallet jack" else "trolley"
	local count = if held and held.tool then #held.pieces else 0
	local onTool = #session.loose - looseOnGround(session) -- pieces on a tool set down somewhere
	local here = if near then "carry" else "drive"
	local info = session.info
	-- Putting a tool away: at its home G does it; a car's own goes back into the car, a dock's jack is set down.
	local function putAway(): string
		if Equipment.atHome(owner) then
			return if tool and tool.spot then "Park the pallet jack (G)" else `Stow the {name} (G)`
		end
		if tool and tool.owner ~= nil then
			if shut and tool.owner == owner then
				return `{capital(open)} (E), then stow the {name} inside (G)`
			end
			return `Push the {name} to the back of the {noun} and stow it (G)`
		end
		return `Set the {name} down (G)`
	end
	if tool then
		if pallet and kind == "trolley" then
			return here, `Pallets need a pallet jack: {string.lower(string.sub(putAway(), 1, 1))}{string.sub(putAway(), 2)}`
		end
		if not handled(plan.mode) then
			return here, putAway()
		end
		if handsMax(session, owner) <= 0 then
			return here, Freight.refusal(info.kind, info.lift, info.pair, kind)
		end
		if count == 0 and (not near or not backNeeded(session)) then
			return here, putAway()
		end
	end
	if not near then
		if pallet and held == nil then
			return "drive", if pickup then `Drive to the warehouse: back up to the loading dock (the {circle} circle)` else `Drive to the receiving dock (the {circle} circle)`
		end
		return nil, nil
	end
	local stage = `({session.moved}/{neededNow(session)} {if pickup then "loaded" else "delivered"})`
	if pallet then
		local dock = if pickup then "loading dock" else "receiving dock"
		if seatedCar then
			if not parkedCar(session) then
				return "carry", `Back the truck up to the {dock}: park in the {circle} circle`
			end
			return "carry", if pickup then "Get out and take a pallet jack (E)" else "Get out and take a pallet jack (E): the dock's, or your truck's own"
		end
		if not pickup and not atStop(session) and session.moved < neededNow(session) then
			if car and backOpen(session) then
				return "carry", `{capital(Vehicles.backVerb(car, false))} (E), then back up to the {dock} (the {circle} circle)`
			end
			return "carry", `Back up to the {dock}: park in the {circle} circle`
		end
		if kind == "jack" and count > 0 then
			if not pickup then
				return "carry", `Push the pallet to the receiving dock: Set down pallet (E) {stage}`
			end
			if car and Freight.palletsOf(car.id, car.stage) <= 0 then
				return "carry", `Your {noun} takes no pallets: a pallet needs a truck. Cancel and come back with one.`
			end
			if shut then
				return "carry", `{capital(open)} (E), then push the pallet in`
			end
			return "carry", `Push the pallet into the {noun}: Load pallet (E) {stage}`
		end
		if onTool > 0 then
			return "carry", if kind == "jack" then "A pallet waits on another jack: set this one down (G) and take that one (E)" else "Take the pallet jack again (E): a pallet is on it"
		end
		if pickup then
			if looseOnGround(session) > 0 then
				return "carry", if kind == "jack" then `Lift a pallet with the jack (E) {stage}` else "Take a pallet jack (E), then lift a pallet (E)"
			end
			return "carry", "Wait for your crew to load"
		end
		if #session.load > 0 and session.moved < neededNow(session) then
			if kind ~= "jack" then
				return "carry", "Take a pallet jack (E): the dock's, or your truck's own"
			end
			if shut then
				return "carry", `{capital(open)} (E), then unload a pallet`
			end
			return "carry", `Pull a pallet out onto the jack: Unload pallet (E) {stage}`
		end
		return "carry", "Wait for your crew"
	end
	if plan.mode ~= "carry" or seatedCar then
		return nil, nil
	end
	local plural = info.plural
	local piece = info.piece
	if kind == "trolley" then
		local max = handsMax(session, owner)
		if pickup then
			if count > 0 then
				if #session.pile > 0 and count < max then
					return "carry", `Load more onto the trolley (E) at {who} ({count}/{max}), or push it to the {noun}`
				elseif looseOnGround(session) > 0 and count < max then
					return "carry", `Load the {piece} you put down onto the trolley (E)`
				elseif shut then
					return "carry", `{capital(open)} (E), then Load all (E)`
				end
				return "carry", `Push the trolley to the back: Load all into the {noun} (E)`
			end
			if #session.pile > 0 then
				return "carry", `Load the {plural} onto the trolley (E) at {who}`
			elseif looseOnGround(session) > 0 then
				return "carry", `Load the {piece} you put down onto the trolley (E)`
			end
			return nil, nil
		end
		if count > 0 then
			if toTakeOut(session) and count < max then
				return "carry", `Push the trolley to {who}: Hand over (E), or take out more (E)`
			end
			return "carry", `Push the trolley to {who}: Hand over (E)`
		end
		if looseOnGround(session) > 0 then
			return "carry", `Load the {piece} you put down onto the trolley (E)`
		end
		if #session.load > 0 and session.moved < neededNow(session) and atStop(session) then
			return "carry", if shut then `{capital(open)} (E), then take them out onto the trolley` else `Take the {plural} out onto the trolley (E)`
		end
		return nil, nil
	end
	if kind or held then
		return nil, nil
	end
	-- On foot with empty hands: the trolley left somewhere with pieces on it, or the car's trolley would help.
	if onTool > 0 then
		return "carry", `Take the trolley again (E): {onTool} {if onTool == 1 then piece else plural} on it`
	end
	local trolley = Equipment.trolleyOf(owner)
	if trolley and trolley.state == "home" and Freight.trolleyTakes(info.kind, info.lift, info.pair) then
		if pickup and #session.pile >= 3 then
			return "carry", `Take the trolley (E at the back of the {noun}) for {math.min(#session.pile, Tuning.TrolleyPieces)} at once, or pick up {article(piece)} (E)`
		elseif not pickup and atStop(session) and #session.load >= 3 and session.moved + 3 <= neededNow(session) then
			return "carry", `Take the trolley (E at the back of the {noun}), then take the {plural} out onto it`
		end
	end
	return nil, nil
end

-- 5.0: the hints of a foot job (no vehicle): walk to the circle ("drive": the HUD's way there), pick the pieces up
-- (the hands, then the pack), hand them over.
local function footStep(session: Session, plan: Plan, near: boolean): (string, string)
	local owner = session.owner
	local held = session.held[owner]
	local carrying = (if held then #held.pieces else 0) + #session.pack
	local who = if plan.person then plan.person.name else "the receiver"
	local piece = session.info.piece
	local seated = Vehicles.seatedIn(owner) ~= nil
	local pickup = plan.stage == "pickup"
	if plan.toss then
		-- 5.3, the newspaper round: toss one onto every porch.
		if not near then
			return "drive", `To {plan.place or "the next door"}: the red circle`
		elseif countHere(session, session.pack) > 0 then
			return "carry", `Toss the paper onto the porch of {plan.place or "the house"} (E) · from up close it never misses`
		end
		return "carry", "No paper for this door in your satchel"
	end
	if not near then
		if pickup and carrying > 0 then
			return "drive", `Back to {who}: more {session.info.plural} to pick up (the red circle)`
		end
		return "drive", if pickup then `Walk to {who}: the red circle` else `Walk to {who} with the {session.info.plural}: the red circle`
	end
	if #session.loose > 0 and (pickup or carrying == 0) then
		return "carry", `Pick up the {piece} you put down (E)`
	end
	if pickup then
		if #session.pile == 0 and session.built then
			return "carry", "Wait for your crew"
		end
		local start = if seated then "Get out and pick up" else "Pick up"
		if plan.bundle then
			return "carry", `{start} the bundle of {#session.pile} papers from {who} (E)` -- 5.3
		end
		if carrying == 0 then
			return "carry", `{start} {article(piece)} from {who} (E)`
		end
		local room = session.info.pack or 0
		local packNote = if room > 0 then ` · backpack {#session.pack} / {room}` else ""
		return "carry", `{start} another {piece} (E){packNote}`
	end
	-- 5.2: only the pieces for this customer (another order's stay with you).
	local here = countHere(session, session.pack) + (if held then countHere(session, held.pieces) else 0)
	if here > 0 and plan.door and not session.knocked then
		return "carry", `Walk up to the door of {plan.place or "the house"} and knock` -- 5.3
	elseif here > 0 and plan.nobody then
		return "carry", `Nobody's home: leave {if here > 1 then "them" else "it"} at the door (E)`
	elseif here > 0 then
		return "carry", `{if seated then "Get out and hand" else "Hand"} {if here > 1 then "them" else "it"} over to {who} (E)`
	elseif carrying > 0 then
		return "carry", `Nothing you carry is for {who}: pick theirs up first`
	end
	return "carry", "Wait for your crew"
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
	local circle = "red" -- 4.4.1: the stop's circle is the contract red, the pick-up's too (client/Hud.luau)
	local seatedCar, driving = Vehicles.seatedIn(owner)
	local position = ownerPosition(session)
	local near = position ~= nil and flat(position, plan.park) < Tuning.ApproachDistance
	if session.blocked and near then
		return if plan.mode == "pallet" then "carry" else plan.mode, blockedText(session)
	end
	if session.info.foot then
		return footStep(session, plan, near) -- 5.0
	end
	-- 4.0: a trolley, a pallet jack, the pallets: their own hints first.
	local toolHandling, toolText = toolStep(session, plan, near)
	if toolHandling and toolText then
		return toolHandling, toolText
	end
	-- 3.2: the back is open and nothing more goes in or out here: close it, the car does not drive open. A serve or
	-- board stop needs no back: its own hint first while near, the nag once away.
	local noBack = plan.mode == "serve" or plan.mode == "board"
	if car and backOpen(session) and not held and (not near or (not noBack and not backNeeded(session))) then
		local close = capital(Vehicles.backVerb(car, false))
		return if not near then "drive" elseif plan.mode == "pallet" then "carry" else plan.mode, if seatedCar then `Get out and {Vehicles.backVerb(car, false)} (E)` else `{close} (E), then drive on`
	end
	if not held and not near and heldCount(session) == 0 then
		return "drive", `Drive to the {circle} circle`
	end
	local parked = parkedCar(session) ~= nil
	local mode = if plan.mode == "pallet" then "carry" else plan.mode -- (the HUD knows carry)
	local who = if plan.nobody then "the door (nobody's home)" elseif plan.person then plan.person.name else "the receiver"
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
	-- (4.8, multi-drop: another customer's piece in your hands goes back in)
	local other = plan.stage == "drop" and held ~= nil and holdsOther(session, owner)
	local intoCar = plan.stage == "pickup" or session.moved >= neededNow(session) or other
	if held then
		-- 3.7: one light piece leaves a hand free (open the back, take a second one); two fill both hands.
		local count = #held.pieces
		local it = if count > 1 then "them" else "it"
		local free = count < handsMax(session)
		if other and not shut then
			local top = held.pieces[count]
			return mode, `That {piece} is for {top.owner or "another customer"}: put it back in the {noun} (E)`
		end
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
		if session.info.dests then
			return mode, `Take {who}'s {piece} out of the {noun}{two} (E)` -- 4.8, multi-drop: the labelled one
		end
		return mode, if horse then `Lead a horse out of the {noun} (E)` else `Take {article(piece)} out of the {noun}{two} (E)`
	end
	return mode, "Wait for your crew"
end

-- Is anybody of the job handling cargo on foot at the current stop (the enemies come on foot then)?
function Cargo.onFoot(session: Session): boolean
	local plan = session.plan
	if not plan or not handled(plan.mode) then
		return false
	end
	if heldCount(session) > 0 then
		return true
	end
	local position = ownerPosition(session)
	return position ~= nil and Vehicles.seatedIn(session.owner) == nil and flat(position, plan.park) < Tuning.ApproachDistance
end

-- 5.5, a city bus seat (server/Buses.luau): may this player sit down without dropping what the hands hold? Empty
-- hands, or the owner of a foot job whose backpack takes the held pieces (Cargo.update stows them as they sit, the
-- way it does on a bike); not a pushed tool or a horse, and not a piece of somebody else's job.
function Cargo.canStowHands(player: Player): boolean
	for _, session in active do
		local held = session.held[player]
		if held and not session.ended then
			return held.tool == nil and held.pieces[1].horse == nil and session.info.foot == true and player == session.owner
				and packTakes(session, held.pieces, false)
		end
	end
	local character = player.Character
	return Cargo.carrying(character) == nil and (character == nil or character:GetAttribute("Pushing") == nil)
end

-- The admin tools: the current stop is done at once (loaded / handed over / served).
function Cargo.adminFinish(session: Session): boolean
	local plan = session.plan
	if not plan or session.ended then
		return false
	end
	local into = if session.info.foot then session.pack else session.load -- (5.0: on foot it all goes into the pack)
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
			table.insert(into, piece)
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
		table.insert(into, loose.piece)
	end
	table.clear(session.loose)
	if plan.mode == "serve" then
		session.hold = plan.hold
		session.served = true
		while #session.load > plan.keep do
			countDelivered(session, table.remove(session.load))
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
			table.insert(into, piece)
		end
		for _, piece in session.walking do
			removeNpc(piece.npc)
			piece.npc = nil
			table.insert(into, piece)
		end
		table.clear(session.pile)
		table.clear(session.walking)
		session.moved = plan.needed
	else
		for _, piece in session.walking do
			removeNpc(piece.npc)
			piece.npc = nil
			session.moved += 1
			countDelivered(session, piece)
		end
		table.clear(session.walking)
		for index = #session.pack, 1, -1 do -- (5.0, on foot; 5.2: the pieces for here)
			if session.moved < plan.needed and forHere(session, session.pack[index]) then
				countDelivered(session, table.remove(session.pack, index))
				session.moved += 1
			end
		end
		while session.moved < plan.needed and #session.load > 0 do
			local found = takeHere(session) -- (4.8, multi-drop: this customer's pieces)
			if not found then
				break
			end
			local piece: Piece = found
			if piece.horse then
				Animals.remove(piece.horse)
			end
			session.moved += 1
			countDelivered(session, piece)
		end
		session.moved = math.max(session.moved, neededNow(session))
	end
	render(session)
	refresh(session)
	packShown(session)
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
	table.clear(session.pack) -- 5.0
	packShown(session)
	throwShown(session) -- 6.0: no throw any more
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

	-- 4.0, the tools (server/Equipment.luau): the pieces on them are this module's, counted like any other.
	local function changed(session: Session)
		refresh(session)
		session.info.changed()
	end
	-- The pieces on a tool set down stand on it (no prompt of their own: they come along with the tool).
	local function placeOnTool(session: Session, tool: Equipment.Tool)
		local pieces: { Piece } = {}
		for _, loose in session.loose do
			if loose.tool == tool then
				table.insert(pieces, loose.piece)
			end
		end
		if #pieces > 0 then
			stackOnTool(tool, pieces, false)
		end
	end
	Equipment.loadOf = function(tool: Equipment.Tool): number
		local n = 0
		for _, session in active do
			for _, held in session.held do
				if held.tool == tool then
					n += #held.pieces
				end
			end
			for _, loose in session.loose do
				if loose.tool == tool then
					n += 1
				end
			end
		end
		return n
	end
	Equipment.mayTake = function(player: Player, tool: Equipment.Tool): (boolean, string?)
		local owner = tool.owner
		if owner and owner ~= player then
			local session = active[owner]
			if not session or session.ended or not session.info.allowed(player) then
				return false, `That is {owner.DisplayName}'s. Only their crew may use it.`
			end
		end
		for _, session in active do
			for _, loose in session.loose do
				if loose.tool == tool and not session.info.allowed(player) then
					return false, "What is on it is somebody else's delivery."
				end
			end
		end
		return true, nil
	end
	-- Taken: what was left on it comes along (the player's Held on the tool).
	Equipment.taken = function(player: Player, tool: Equipment.Tool)
		for _, session in active do
			if session.ended then
				continue
			end
			local touched = false
			for _, loose in table.clone(session.loose) do
				if loose.tool ~= tool then
					continue
				end
				touched = true
				if session.info.allowed(player) and take(session, player, loose.piece) then
					local index = table.find(session.loose, loose)
					if index then
						table.remove(session.loose, index)
					end
					loose.prompt:Destroy()
				else
					-- (mayTake checked it: should not happen) it stays, on the ground instead
					loose.tool = nil
					local model = loose.piece.model
					if model then
						setDown(model, dropFrame(session, tool.last + Vector3.new(0, 3, 0))) -- (dropFrame wants a root's height)
					end
				end
			end
			if touched or session.info.allowed(player) then
				changed(session)
			end
		end
	end
	-- Set down (G, death, leaving, sitting): what is on it stays on it, as pieces put down.
	Equipment.released = function(player: Player, tool: Equipment.Tool)
		for _, session in active do
			local held = session.held[player]
			if held and held.tool == tool then
				clearHeld(session, player)
				for _, piece in held.pieces do
					local model = piece.model or buildPiece(piece)
					piece.model = model
					local main = model.PrimaryPart :: BasePart
					local loose: Loose = { piece = piece, prompt = prompt(main, "Pick up", capital(session.info.piece), nil, holdFor(session), session.owner), handle = nil, tool = tool }
					loose.prompt.Enabled = false
					loose.prompt.Triggered:Connect(function(by)
						onLoose(session, by, loose)
					end)
					table.insert(session.loose, loose)
				end
				placeOnTool(session, tool)
				changed(session)
			elseif not session.ended and session.info.allowed(player) then
				refresh(session) -- (the prompts' words: no trolley any more)
			end
		end
	end
	-- Going home on its own: what is on it goes on the ground where it stood.
	Equipment.returned = function(tool: Equipment.Tool)
		for _, session in active do
			local touched = false
			for _, loose in session.loose do
				if loose.tool == tool then
					loose.tool = nil
					touched = true
					local model = loose.piece.model
					if model then
						setDown(model, dropFrame(session, tool.last + Vector3.new(0, 3, 0))) -- (dropFrame wants a root's height)
					end
				end
			end
			if touched then
				changed(session)
			end
		end
	end
	Equipment.start()

	-- 4.2: the touch PUT DOWN / LET GO / SET DOWN button (client/TouchControls.luau) does what the G prompt in your
	-- hands does: the pushed tool first (Equipment: stow or set down), else the top piece (or the horse) of whatever
	-- job you carry for. Only your own hands, a few times a second at most.
	-- 6.0: a throw at a door (client/Throw.luau): (the stop's ThrowStop, a direction, a power 0 … 1). Only the owner of a
	-- running foot job, once per Config.Throw.Cooldown; throwAt checks the rest.
	local lastThrow: { [Player]: number } = {}
	Net.get("Throw").OnServerEvent:Connect(function(player: Player, stop: any, direction: any, power: any)
		if type(stop) ~= "number" or typeof(direction) ~= "Vector3" or type(power) ~= "number" then
			return
		end
		local now = os.clock()
		local session = active[player]
		if now - (lastThrow[player] or -math.huge) < Config.Throw.Cooldown or not session or session.ended or session.visit ~= stop then
			return
		end
		lastThrow[player] = now
		throwAt(session, player, direction, power)
		session.info.changed()
	end)
	local lastPut: { [Player]: number } = {}
	Net.get("PutDown").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastPut[player] or 0) < 0.25 then
			return
		end
		lastPut[player] = now
		if Equipment.letGo(player) then
			return
		end
		for _, session in active do
			if session.held[player] then
				putDown(session, player)
				session.info.changed()
				return
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastPut[player] = nil
		lastThrow[player] = nil
	end)

	-- 5.3 review: who works for which job, for client/CargoPrompts.luau (it hides the prompts of the others' jobs):
	-- the player attribute CargoWith, ",<owner UserId>,<…>," of every running job that allows them (the owner, the
	-- riders, the crew), nil for none. Twice a second.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local ids: { number } = {}
				for owner, session in active do
					if not session.ended and owner.Parent ~= nil and session.info.allowed(player) then
						table.insert(ids, owner.UserId)
					end
				end
				table.sort(ids)
				local with = if #ids > 0 then "," .. table.concat(ids, ",") .. "," else nil
				if player:GetAttribute("CargoWith") ~= with then
					player:SetAttribute("CargoWith", with)
				end
			end
		end
	end)
end

return Cargo
