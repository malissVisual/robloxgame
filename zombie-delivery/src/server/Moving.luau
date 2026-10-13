--!strict
-- 7.0 prototype, MOVES (the owner's rework, design/rework/NAVRH.md): one house move, run on the server. The rules are
-- shared/MovingRules.luau's (pure, tests/moving_test.luau), the numbers Config.Moving's, the client's side
-- client/MovingHud.luau (and client/Fade.luau). The old game stays as it was beside it.
--
--   * The contract: the depot's "Moving contracts" board (Config.Moving.Board) or the admin panel opens the contract
--     card (the Moving remote's "contract": the house, its ★ things, the pay, the time); its START (checked here: the
--     card was opened within CardFor s, near the board or by an admin; no job, no other move, a free interior slot)
--     builds the house's interior far away (server/HouseInterior.luau build at its slot(n), the plan shared/
--     HouseLayout.luau's, the furniture shared/FurnitureLooks.luau's: found by name when first needed, see artNow) and
--     lends the company's Moving Truck (Config.Moving.Truck) right next to the owner, who sits in it; the GPS shows
--     the house (the prologue: Marge's, 155 Willow Ln, Config.Moving.Contracts).
--   * The crew: the owner's crew (server/Crew.luau Crew.members) is on the move with them, joining or leaving any time
--     (the player attribute MoveWith = the owner's UserId while you are; client/MovingHud.luau shows only the prompts
--     of your own move: the tag MovePrompt with MoveOwner / MoveOnly / MoveSkip).
--   * The door: "Enter house" at the contract's front door (one prompt: it takes you into YOUR move's interior) fades
--     out (the "fade" message), streams the interior in (RequestStreamAroundAsync), moves you (and what you carry, and
--     the other end of a pair thing) to the plan's entry and fades in; "Leave house" by the door inside the other way.
--   * The things: "Pick up" (hand, both) / "Lift" (pair) on every thing, "Help lift" on a pair thing somebody lifted,
--     "Put down" / "Let go" (G, or the touch PUT DOWN: the PutDown remote) for whoever holds it. In the hands it is
--     welded in front of the chest like a cargo piece (the character attributes Carrying, CarryCount, CarryHands,
--     CarryAt, CarrySize, CarrySpeed and MoveCarry = the spot: client/CameraRig.luau walks at CarrySpeed with
--     MoveCarry, client/ArmPose.luau reaches for it); a pair thing alone is dragged low in front, slowly. Its condition
--     drops when its carrier falls from a height, is bitten, dies (it drops), and in the truck when the truck is hit;
--     its helper too far from it for Grace s, it goes down. Moving faster than the carry allows (a teleport) puts it
--     down where its carrier was.
--   * The truck: "Load" (E) at its open back puts what you hold onto the bed (MovingRules' packer: first-fit, turned
--     90° when that fits, stacked flat; "No room — unload something or bring a bigger truck"), welded in the box where
--     it is seen through the open back; "Unload" (Z) takes the last one in that nothing rests on back into your hands.
--     The back is the owner's and the crew's (Vehicles.backAllowed, BackCrew); its own prompt waits while Load shows
--     (one E at a time).
--   * The clock: Config.Moving.Time; at HordeAt left the horde (Zombies.spawn + Zombies.march to the door, in bursts);
--     a few roaming zombies round the house while somebody is outside near it; none inside (the crew on a move is
--     "hunted" like a job's: no ordinary roamers come round them anywhere). The truck within DropRadius of the
--     depot's drop-off (the Wall) with a load ends the move: the pay (MovingRules.result) split among the crew within
--     Present studs (Economy.crewSplit, "MovePay"), XP, the result card ("result"), analytics (MoveDone). At 0:00 it
--     ends late (the load paid at LateShare). GIVE UP (the owner) or the owner leaving calls it off; a wrecked or lost
--     truck loses it.
--   * The edges: whoever leaves, dies, sits down or leaves the crew drops what they hold where they are (inside: on the
--     floor); somebody inside an interior that goes is brought out to the door; every prompt and request is checked
--     here (who, how far, the state), the remote is rate limited (Config.Robust.Limits.Moving).
--   * 7.0 planning (NAVRH.md §2–3; shared/MoveRoles.luau's rules, Config.MoveRoles' numbers): START on the contract
--     card opens the planning lobby (server/MoveLobby.luau: the crew picks roles, gets READY; the owner's LAUNCH starts
--     the move with them: startMove's `roles`; the admin's "start" skips it). On the move everybody has a role (the
--     player attribute MoveRole; a newcomer the first free one; the list's SWITCH, the Moving remote's "role", every
--     Switch s, to a role nobody else has: solo you switch to do everything). The roles' blocks below ("7.0 planning"):
--       Driver      no wait at Load / Unload (their prompts' MoveQuick: client/MovingHud.luau), the truck (and its load)
--                   takes Driver.TruckDamage of a hit while a Driver is at its wheel (Vehicles.damage wrapped), "Call
--                   truck to door" once a move (the remote's "call": to the house's curb with a fade, unless somebody
--                   sits in it);
--       Mover       a pair thing alone at Mover.Alone of the walk, held up (not dragged), × Mover.Carry on the rest; the
--                   others go up stairs and slopes slower with a thing (× Mover.Climb), a Mover not;
--       Guard       × Guard.Damage on the zombies (Zombies.damage wrapped), plank barricades outside ("barricade": they
--                   stop the zombies, which wear them down), the outline through walls (client/EnemyOutline.luau).
--     (The owner took the Technician out: the front door is never locked, the interior is lit from the start.)
--   * 7.0 greeters (server/MoveGreeters.luau; Config.MoveGreeters, the words shared/MoveStory.luau's): the client
--     greets the crew on the house's porch and reacts to the move (MoveGreeters.sync in the tick, gone at the end:
--     MoveGreeters.done in cleanup), the soldier at the Wall welcomes a delivered truck (done), Marge greets a player
--     at the Moving contracts kiosk (MoveGreeters.start's own loop).
--   * 7.0 review (server): while you own a move with its truck out, nothing of the old game takes the truck's place
--     (Vehicles.spawn / placeNear / placeAt / spawnAt wrapped: CAR, MY BIKE, the phone's CALL CAR in the truck, a car
--     job, a garage's car, a dealer's; ZDC RIDE asks Moving.busy), no job or mission starts while you are on a move
--     (server/Jobs.luau startJob asks Moving.busy), a move's owner counts as busy for the crews (Crew.hasJob). A door
--     trip whose move ends meanwhile comes out at the house's door; Load checks the carry's pace (no teleport to the
--     truck) and that the thing still exists (a missing model never pays); the end's pay runs in a pcall (the cleanup
--     always frees the slot). Late: at 0:00 the truck has LateGrace s to reach the Wall (it pays LateShare), else the
--     load is lost. LAUNCH only at the depot's board. The house's "Enter house" is each move's own (its crew's only).
--   * 7.x farm move (chapter 1, Walt's Farm; the blocks marked "7.x farm move"): Config.Moving.Contracts holds several
--     contracts; a contract opens once its chapter's chapters before it are done (shared/MoveStory.luau; the owner's
--     save flags "done:<chapter>", PlayerData.markStory for the crew present when a chapter's move was delivered; the
--     admin's card and start skip the lock). The card lists them (card.contracts: open or 🔒 and why; the Moving
--     remote's ("card", id) opens another one's card), has the contract's own clock and pay (time, hordeAt, pay). A
--     farm stands at its Map.Places place (Config.Moving.Sites.farm through shared/MoveSiteLooks.luau: the place's
--     frame turns with map step 2's relocation): "Enter house" at the farmhouse's front door, "Enter barn" at the barn
--     doors, each to its own way in (shared/HouseLayout.luau entries: the barn's by the plan's exits[2]); inside a
--     "Leave" by every exit, out at the matching door; a piece may only go through the exits HouseLayout.exitsFor
--     allows (a bigDoor piece: the barn doors; elsewhere "Too big — use the barn doors"); the Driver's call brings the
--     van to the door nearest to them, its back to it; Danny (server/MoveHelper.luau) takes the nearest way he may.
--   * 7.x van moves (the owner: "the move should be driven with MY van, the new ZDC model"): no truck is lent; the move
--     uses its owner's own car (out already, else placed by them at LAUNCH): `truck` is that van, its bed Config.Moving
--     .Beds[its id] (else the ZDC Van's), a piece too big for it that may be towed rides on the hitch behind. The
--     Wall unloads it: every piece in it is delivered (MovingRules.deliver: a trip; the models go), the move goes on
--     until the owner's FINISH (the Moving remote's "finish": the HUD asks twice) or the clock (0:00: LateGrace s to
--     bring what is in the van, delivered late at LateShare, then the end). The pay is what was delivered over every
--     trip. A van lost mid-move (wrecked, gone) loses what is in it (condition 0), the move goes on: CAR brings it back
--     after VanAgain s and the move takes it over (its Load / Unload prompts made again on it).
--   Moving.start()            builds the board, the drop-off and the doors, wires the hooks (after Main's own)
--   Moving.busy(player)       why `player` can't take a job, a mission or a rental now (on a move), or nil
--   Moving.admin(player, arg) the admin panel's MOVES buttons: "card" | "start" | "house" | "horde" | "time" | "deliver"
--                             | "end"; returns what to say
--   Moving.useArt(art)        the art modules given (a test or a fallback), instead of finding them by name
--   Moving.step()             one tick of every move (the loop's; tests/moving_runtime_test.luau runs the real module)
--   Moving.helperTake / helperDrop / helperLoad / helperHurt   7.0: the depot's helper's hands (server/MoveHelper.luau:
--                             Danny joins a crew of one; MoveHelper.sync in the tick)
--   7.0 grip: the carry's grip bar (shared/CarryGrip.luau, client/CarryGripUi.luau): the grip hook (setHands: the
--                             character attribute CarryGrip, the steady walk) and the grip block (the remote's "slip",
--                             "grip")

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Rules = require(Shared.MovingRules)
local MoveRoles = require(Shared.MoveRoles) -- 7.0 planning: the roles' rules
local Crew = require(script.Parent.Crew)
local MoveLobby = require(script.Parent.MoveLobby) -- 7.0 planning: the lobby before a move
local MoveHelper = require(script.Parent.MoveHelper) -- 7.0: the depot's helper (Danny) for a crew of one
local MoveGreeters = require(script.Parent.MoveGreeters) -- 7.0 greeters: the client on the porch, the soldier at the Wall
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)

local T = Config.Moving
local Moving = {}

local remote = Net.get("Moving")
local notice = Net.get("Notice")
local TAG = "MovePrompt" -- client/MovingHud.luau shows a tagged prompt only to the players it is for
local CARRY_ATTRIBUTES = { "Carrying", "CarryCount", "CarryHands", "CarryAt", "CarrySize", "CarrySpeed", "MoveCarry", "CarryGrip" } -- (7.0 grip: CarryGrip)

-- The art (another branch builds it): shared/FurnitureLooks.luau (Items, build), shared/HouseLayout.luau (plan),
-- server/HouseInterior.luau (build, slot, destroy).
export type Art = { looks: any, layout: any, interior: any }
type Contract = { id: string, name: string, client: string, icon: string, home: string?, place: string?, seed: number, kind: string, blurb: string, time: number?, hordeAt: number?, pay: number? }

-- 7.x farm move: a way in from outside (a house has one, the front door; a farm the farmhouse's and the barn doors),
-- in the plan's exits' order.
type SiteDoor = {
	exit: number, -- the plan's exit it leads to (1: the front door)
	name: string, -- "front door", "barn doors" (the hints')
	door: Vector3, -- its foot, outside
	facing: Vector3, -- out of it
	outside: CFrame, -- where you come out
	park: Vector3, -- the van's spot (its middle, its back to the door: "Call truck to door")
	heading: Vector3, -- the van's nose there (a house's: along the road; a farm's: out of the door)
	width: number,
	part: BasePart?, -- the Enter prompt's part
}

type Site = {
	contract: Contract,
	home: Map.Home, -- (7.x farm move: a farm's is made from its place: its front door, the van's spot)
	door: Vector3, -- the front door's foot, outside
	facing: Vector3, -- out of the door
	outside: CFrame, -- where you come out
	model: Model,
	doors: { SiteDoor }, -- 7.x farm move: every way in (doors[1] the front door)
}

-- 7.x farm move: a way out of the interior: its exit (the Leave prompt's part), where you come in by it, its door.
type Way = { exit: number, part: BasePart, inside: Vector3, entry: CFrame, door: SiteDoor }

type Item = {
	spot: number,
	model: Model,
	root: BasePart,
	home: CFrame, -- where it stood in the interior
	pick: ProximityPrompt,
	help: ProximityPrompt,
	down: { ProximityPrompt }, -- the holders' G
	weld: WeldConstraint?,
	hooks: { RBXScriptConnection },
	health: { [Player]: number }, -- its holders' health a moment ago (a bite takes a share)
	lastAt: Vector3?, -- the pace check: its carrier's last place …
	lastTime: number, -- … and when
	apartSince: number?, -- its helper too far since
	fallFrom: number?, -- its carrier is falling from this high
}

-- 7.0 planning: the roles on a move (shared/MoveRoles.luau) and what they did.
type Barricade = { model: Model, at: Vector3, hp: number, endsAt: number, by: Player }
type Climb = { at: Vector3, time: number, upUntil: number, slow: boolean, who: number? }
type Team = {
	of: { [number]: string }, -- user id → role id (the player attribute MoveRole)
	switched: { [number]: number }, -- user id → the server time of their last switch
	called: boolean, -- the Driver called the truck to the door (once a move)
	placed: { [number]: number }, -- user id → barricades put up
	barricades: { Barricade },
	enter: ProximityPrompt?, -- "Enter house": this move's own, for its crew only (the door is never locked)
	doors: { ProximityPrompt }, -- 7.x farm move: the other doors' Enter prompts (a farm's "Enter barn")
	climb: { [number]: Climb }, -- by spot: a carried thing going up stairs or a slope
	lastTick: number,
}

type Session = {
	id: number,
	owner: Player,
	contract: Contract,
	site: Site,
	move: Rules.Move,
	plan: any,
	origin: CFrame,
	slot: number,
	interior: Model?,
	items: { [number]: Item },
	exit: BasePart?,
	truck: Vehicles.Car?,
	load: ProximityPrompt?,
	unload: ProximityPrompt?,
	horde: { Zombies.Zombie },
	roam: { Zombies.Zombie },
	nextRoam: number,
	bursts: number,
	nextBurst: number,
	members: { [Player]: boolean },
	inside: { [Player]: boolean },
	dirty: boolean,
	sentAt: number,
	ended: boolean,
	emptyWarned: number,
	team: Team, -- 7.0 planning: the roles and what they did
	late: boolean, -- 7.0 review: the clock ran out: LateGrace s to reach the Wall
	ways: { Way }, -- 7.x farm move: the ways out (ways[1] the front door: `exit`)
	lostAt: number?, -- 7.x van moves: the van was lost then (server time; nil: it is out or never was)
}

local art: Art? = nil
local contractFacts: { [string]: any } = {} -- 7.0 review: a contract's plan and card facts, made once (factsOf)
local sessions: { [Player]: Session } = {} -- by owner
local slots: { [number]: Session } = {}
local sites: { [string]: Site } = {}
local armed: { [Player]: { at: number, admin: boolean, card: { [string]: any }? } } = {} -- the contract card was opened (START is good a while; 7.0 planning: the card itself, for the lobby)
local traveling: { [Player]: boolean } = {}
local folder: Folder? = nil
local boardPart: BasePart? = nil
local nextId = 0
local jobs: any = nil -- server/Jobs.luau (required in start: Jobs.active)

-- ── Small helpers ──────────────────────────────────────────────────────────

local function now(): number
	return workspace:GetServerTimeNow()
end

local function say(player: Player, text: string)
	if player.Parent then
		notice:FireClient(player, text)
	end
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A player's living body on foot or seated: (character, humanoid, root) or nils.
local function bodyOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- The same for a player who may be nil.
local function bodyOrNil(player: Player?): (Model?, Humanoid?, BasePart?)
	if not player then
		return nil, nil, nil
	end
	return bodyOf(player)
end

local function contractById(id: any): Contract?
	for _, contract in T.Contracts do
		if contract.id == id then
			return contract
		end
	end
	return nil
end

local function moduleNamed(parent: Instance, name: string): ModuleScript?
	local found = parent:FindFirstChild(name)
	return if found and found:IsA("ModuleScript") then found else nil
end

-- The art modules, found by name the first time they are needed (nil: not in this place yet: no move starts).
local function artNow(): Art?
	if art then
		return art
	end
	local looksModule = moduleNamed(Shared, "FurnitureLooks")
	local layoutModule = moduleNamed(Shared, "HouseLayout")
	local interiorModule = moduleNamed(script.Parent, "HouseInterior")
	if not looksModule or not layoutModule or not interiorModule then
		return nil
	end
	local ok, loaded = pcall(function(): Art
		return { looks = require(looksModule) :: any, layout = require(layoutModule) :: any, interior = require(interiorModule) :: any }
	end)
	if not ok then
		warn(`[Moving] the house art failed to load: {loaded}`)
		return nil
	end
	art = loaded
	return loaded
end

function Moving.useArt(given: Art)
	art = given
	table.clear(contractFacts)
end

-- The furniture as MovingRules' defs (FurnitureLooks.Items; a Vector3 size as plain numbers).
local function defsOf(a: Art): { [string]: Rules.ItemDef }
	local defs: { [string]: Rules.ItemDef } = {}
	for key, item in (a.looks.Items :: { [string]: any }) do
		local size = item.size
		if typeof(size) ~= "Vector3" then
			continue
		end
		local id = if type(item.id) == "string" then item.id else key
		defs[key] = {
			id = id,
			name = if type(item.name) == "string" then item.name else id,
			icon = if type(item.icon) == "string" then item.icon else "📦",
			size = { X = size.X, Y = size.Y, Z = size.Z },
			class = if type(item.class) == "string" then item.class else "both",
			weight = tonumber(item.weight) or 5,
			value = tonumber(item.value) or 0,
			fragile = item.fragile == true,
			room = if type(item.room) == "string" then item.room else "",
			tow = item.bigDoor == true, -- 7.x van moves: too big for a bed, it rides on the hitch (the hay wagon)
		}
	end
	return defs
end

local function spotsOf(plan: any): { Rules.Spot }
	local list: { Rules.Spot } = {}
	for _, spot in (plan.spots :: { any }) do
		if type(spot.id) == "number" and type(spot.item) == "string" then
			table.insert(list, { id = spot.id, item = spot.item, room = tostring(spot.room), star = spot.star == true })
		end
	end
	return list
end

-- The session this player works on: their own, or their crew's owner's.
local function sessionOf(player: Player): Session?
	local own = sessions[player]
	if own and not own.ended then
		return own
	end
	local owner = Crew.ownerOf(player)
	local theirs = if owner then sessions[owner] else nil
	return if theirs and not theirs.ended then theirs else nil
end

local function membersOf(s: Session): { Player }
	local list: { Player } = { s.owner }
	for _, member in Crew.members(s.owner) do
		table.insert(list, member)
	end
	return list
end

-- Everybody on the move now or at the last tick (server/Crew.luau may have broken the crew up already when its owner
-- leaves: they still hear the end).
local function everyone(s: Session): { Player }
	local list = membersOf(s)
	for player in s.members do
		if player.Parent and not table.find(list, player) then
			table.insert(list, player)
		end
	end
	return list
end

local function tellAll(s: Session, text: string)
	for _, player in everyone(s) do
		say(player, text)
	end
end

-- ── MoveStory hook (7.0 story, shared/MoveStory.luau) ───────────────────────────────────────────────────────────────
-- Marge's texts on the crew's phones (the Tutorial remote's "message": client/Phone.luau's MESSAGES): at START her
-- word on the ★ things (`how` nil), at the end her debrief for the outcome (`how`: the phase, `stars`: the rating).
-- A contract without a chapter says nothing. Called twice: startMove and finish.
local MoveStory = require(Shared.MoveStory)
local function storyText(s: Session, how: string?, stars: number?)
	local text = if how then MoveStory.debriefText(s.contract.id, how, stars) else MoveStory.dispatchText(s.contract.id)
	if text then
		for _, player in everyone(s) do
			Net.get("Tutorial"):FireClient(player, "message", { from = MoveStory.Sender, text = text })
		end
	end
end
-- ── (end of the MoveStory hook) ──────────────────────────────────────────────────────────────────────────────────────

local function playerById(id: number?): Player?
	return if id then Players:GetPlayerByUserId(id) else nil
end

local function labelOf(thing: Rules.Thing): string
	return `{thing.icon} {thing.name}{if thing.star then " ★" else ""}`
end

local function tag(prompt: ProximityPrompt, owner: Player)
	prompt:SetAttribute("MoveOwner", owner.UserId)
	CollectionService:AddTag(prompt, TAG)
end

local function newPrompt(parent: Instance, action: string, object: string, key: Enum.KeyCode, hold: number, reach: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = reach
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function invisible(name: string, size: Vector3, frame: CFrame, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = frame
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

-- ── 7.0 planning: the roles (shared/MoveRoles.luau; their abilities further down) ──

-- A plain anchored part (the roles' own things: the barricades' planks; the places' art is server/MoveSites.luau's).
local function rolePart(name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = frame
	part.Anchored = true
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function newTeam(): Team
	return {
		of = {},
		switched = {},
		called = false,
		placed = {},
		barricades = {},
		enter = nil,
		doors = {},
		climb = {},
		lastTick = 0,
	}
end

-- This player's role on the move (nil: none).
local function roleOf(s: Session, player: Player?): string?
	return if player then s.team.of[player.UserId] else nil
end

-- The carry's walk for this thing: its carrier's role's (a Mover lifts a pair thing alone, carries faster).
local function speedOf(s: Session, thing: Rules.Thing): number
	local mode = Rules.mode(thing)
	local role = s.team.of[thing.carrier or 0]
	return Config.Movement.Walk * MoveRoles.speedFactor(role, mode, Rules.speedFactor(mode, thing.weight))
end

-- How it is held: a Mover holds a pair thing alone up in front ("pair"), anybody else drags it low.
local function heldMode(s: Session, thing: Rules.Thing): string
	return MoveRoles.holdMode(s.team.of[thing.carrier or 0], Rules.mode(thing))
end

-- × the carry's walk now: going up stairs or a slope (the climb watch in watchCarried), unless a Mover carries it.
local function climbOf(s: Session, spot: number): number
	local c = s.team.climb[spot]
	local thing = s.move.things[spot]
	if not c or not c.slow or not thing then
		return 1
	end
	return MoveRoles.climbFactor(s.team.of[thing.carrier or 0], Rules.mode(thing))
end

-- ── The places: the board, the drop-off, the houses' doors ─────────────────
-- (their art: server/MoveSites.luau, shared/MoveSiteLooks.luau; the prompts and the rules stay here)

local function dropOffAt(): Vector3
	return Vector3.new(Map.Depot.x + T.DropOff[1], Map.WalkTop, Map.Depot.z + T.DropOff[2])
end

local function buildBoard(parent: Instance)
	-- the "MovingBoard" kiosk (server/MoveSites.luau, Persistent, facing the yard: the corkboard with the houses' photos
	-- and the notices, its lamp, the ZDC logo); the prompt hangs on its corkboard
	local _, board = require(script.Parent.MoveSites).board(parent)
	local prompt = newPrompt(board, "Moving contracts", "ZDC Moving", Enum.KeyCode.E, 0, T.Reach.Board)
	prompt.Triggered:Connect(function(player: Player)
		if not Net.limit(player, "MovingBoard", Config.Robust.Limits.MovingBoard) then
			return -- (7.0 review: a card a second at most)
		end
		local _, _, root = bodyOf(player)
		if root and flat(root.Position, board.Position) <= T.Reach.Board + 4 then
			Moving.openCard(player, nil, false)
		end
	end)
	boardPart = board
end

-- The drop-off at the depot ("the Wall"): the army's checkpoint round its bay (server/MoveSites.luau, Persistent: the
-- bay's orange outline as before, the gantry's SAFE ZONE sign, the Wall's stubs, the booth, the raised barrier, the
-- floodlights, the army truck; nothing in the truck's way in from Bone St), and with it the rework's dressing (the
-- depot's ZDC MOVING & EVACUATION banner, the evacuation spots in the city).
local function buildDropOff(parent: Instance)
	local sites = require(script.Parent.MoveSites)
	sites.dropOff(parent)
	sites.dressing(parent)
end

local onEnter: (Player, string, number?) -> ()

-- A contract's house: the "Enter house" prompt at its front door and its moving-day dress-up outside (the rest of the
-- house stays as server/World.luau built it).
-- 7.x farm move: a house's kerb spot for the van (the road by its park, the van along it: the Driver's call).
local function houseCurb(home: Map.Home): (Vector3, Vector3)
	local park = home.park
	local x, z, dx, dz, width = Map.nearestRoad(park.x, park.z)
	local side = Vector3.new(park.x - x, 0, park.z - z)
	local lane = if side.Magnitude > 0.1 then side.Unit * math.max(0, width / 2 - Config.MoveRoles.Driver.Curb) else Vector3.zero
	return Vector3.new(x, 0, z) + lane, Vector3.new(dx, 0, dz)
end

local farmSite: (Contract, Instance) -> Site?

local function buildSite(contract: Contract, parent: Instance): Site?
	if contract.kind == "farm" then
		return farmSite(contract, parent) -- 7.x farm move
	end
	local home = if contract.home then Map.home(contract.home) else nil
	if not home then
		warn(`[Moving] {contract.id}: no home {contract.home} on the map`)
		return nil
	end
	local facing = Vector3.new(home.facing.x, 0, home.facing.z)
	local door = Vector3.new(home.door.x, Map.WalkTop, home.door.z)
	local model = Instance.new("Model")
	model.Name = `Move_{contract.id}`
	local up = Vector3.new(0, 3.5, 0)
	-- (its "Enter house" prompt is each move's own, for that move's crew only: enterPrompt, 7.0 review)
	local enter = invisible("EnterDoor", Vector3.new(4, 6, 1), CFrame.lookAt(door + facing * 0.9 + up, door + facing * 3 + up), model)
	-- (server/MoveSites.luau: the ZDC MOVING yard sign left of the path, boxes by the door, MOVING DAY over it, cones at
	-- the truck's kerb, the EVACUATED realtor's sign; nothing solid, nothing on the path to the kerb)
	model.PrimaryPart = require(script.Parent.MoveSites).house(model, contract.name, home)
	model.Parent = parent
	local out = door + facing * 4 + Vector3.new(0, 0.1, 0)
	local curb, heading = houseCurb(home)
	local outside = CFrame.lookAt(out, out + facing)
	return {
		contract = contract,
		home = home,
		door = door,
		facing = facing,
		outside = outside,
		model = model,
		doors = { { exit = 1, name = "front door", door = door, facing = facing, outside = outside, park = curb, heading = heading, width = 4, part = enter } },
	}
end

-- ── 7.x farm move: a farm's site (shared/MoveSiteLooks.luau, Config.Moving.Sites) ──────────────────────────────────
-- At its Map.Places place, in the place's frame (it follows map step 2's relocation): an "Enter" part at every door
-- (the farmhouse's front door, the barn doors), where you come out of each, the van's spot in front of each (its back
-- to the door), the farmhouse and the dress (server/MoveSites.luau). Its `home` is made from the place for what reads
-- a house (the address, the GPS's park, the greeter's door).
farmSite = function(contract: Contract, parent: Instance): Site?
	local Looks = require(Shared.MoveSiteLooks)
	local placeId = contract.place or ""
	local found = Looks.siteDoors(contract.kind, placeId)
	if not found or #found == 0 then
		warn(`[Moving] {contract.id}: no place {placeId} on the map`)
		return nil
	end
	local name = placeId
	for _, place in Map.Places do
		if place.id == placeId then
			name = place.name
		end
	end
	local model = Instance.new("Model")
	model.Name = `Move_{contract.id}`
	local up = Vector3.new(0, 3.5, 0)
	local doors: { SiteDoor } = {}
	for index, d in found do
		local foot = Vector3.new(d.x, Map.RoadTop, d.z)
		local facing = Vector3.new(d.fx, 0, d.fz)
		local part = invisible(if index == 1 then "EnterDoor" else `EnterDoor{index}`, Vector3.new(math.min(d.width, 8), 6, 1), CFrame.lookAt(foot + facing * 0.9 + up, foot + facing * 3 + up), model)
		local out = Vector3.new(d.out.x, Map.RoadTop + 0.1, d.out.z)
		table.insert(doors, { exit = index, name = d.name, door = foot, facing = facing, outside = CFrame.lookAt(out, out + facing), park = Vector3.new(d.park.x, 0, d.park.z), heading = facing, width = d.width, part = part })
	end
	model.PrimaryPart = require(script.Parent.MoveSites).farm(model, contract.name, placeId) or doors[1].part
	model.Parent = parent
	local front = doors[1]
	local home: Map.Home = {
		id = contract.id,
		kind = "farm",
		name = name,
		address = name,
		street = name,
		district = "farm",
		x = front.door.X,
		z = front.door.Z,
		facing = { x = front.facing.X, z = front.facing.Z },
		door = { x = front.door.X, z = front.door.Z },
		park = { x = front.park.X, z = front.park.Z },
		pile = { x = front.outside.Position.X, z = front.outside.Position.Z },
	}
	return { contract = contract, home = home, door = front.door, facing = front.facing, outside = front.outside, model = model, doors = doors }
end

-- ── The carry ──────────────────────────────────────────────────────────────

local function clearHands(player: Player?)
	local character = player and player.Character
	if character and character:GetAttribute("MoveCarry") ~= nil then
		for _, name in CARRY_ATTRIBUTES do
			character:SetAttribute(name, nil)
		end
	end
end

-- Where a thing sits from its carrier's root: in front of the chest (MovingRules' mode "drag": low, a step ahead).
local function holdOffset(thing: Rules.Thing, mode: string, root: BasePart, humanoid: Humanoid): CFrame
	local size = thing.size
	local tune = Config.Cargo
	if mode == "drag" then
		local feet = -(root.Size.Y / 2 + humanoid.HipHeight)
		return CFrame.new(0, feet + size.Y / 2 + 0.2, -(tune.CarryFront + 1.2 + size.Z / 2))
	end
	return CFrame.new(0, tune.CarryLow + size.Y / 2, -(tune.CarryFront + size.Z / 2))
end

local function setParts(model: Model, anchored: boolean, carried: boolean, root: BasePart)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = anchored
			part.Massless = carried
			if part == root then
				part.CanCollide = not carried
			elseif carried then
				part.CanCollide = false
			end
		end
	end
end

local function unweld(item: Item)
	local weld = item.weld
	if weld then
		weld:Destroy()
		item.weld = nil
	end
end

-- Welds the thing to `holder` at `frame` (its middle), carried (massless, not colliding).
local function weldTo(item: Item, holder: BasePart, frame: CFrame)
	unweld(item)
	setParts(item.model, true, true, item.root)
	item.model:PivotTo(frame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = holder
	weld.Part1 = item.root
	weld.Parent = item.root
	item.weld = weld
	setParts(item.model, false, true, item.root)
end

-- ── 7.0 grip hook (shared/CarryGrip.luau; the requests: the grip block before "Start") ───────────────────────────────
-- Where a carry starts or changes (setHands asks first): every player holding a thing with a grip bar gets the
-- character attribute CarryGrip (CarryGrip.encode: the kind, the weight, fragile; client/CarryGripUi.luau shows the bar
-- while it is there), nil without one (a one-hand thing that is not fragile); Danny has none (he never slips). It goes
-- with the other carry attributes (CARRY_ATTRIBUTES). A new carry (MoveCarry not this spot yet) or another kind (a
-- helper took the other end) starts the holder's record over. Returns × the carry's walk: CarryGrip.speedFactor while
-- every player holding it last reported steady.
local CarryGrip = require(Shared.CarryGrip)
type GripHold = { session: number, spot: number, kind: string, steady: boolean, last: number }
local grips: { [Player]: GripHold } = {}
Players.PlayerRemoving:Connect(function(player: Player)
	grips[player] = nil
end)

local function gripHands(s: Session, item: Item): number
	local thing = s.move.things[item.spot]
	local kind = CarryGrip.kind(thing.class, thing.fragile, thing.helper ~= nil, roleOf(s, playerById(thing.carrier)))
	local steady = kind ~= nil
	for _, id in { thing.carrier, thing.helper } do
		local player = playerById(id)
		local character, humanoid = bodyOrNil(player)
		if not player or not character or not humanoid then
			continue -- (Danny, or a body that is gone)
		end
		local hold = grips[player]
		if character:GetAttribute("MoveCarry") ~= item.spot or not hold or hold.session ~= s.id or hold.spot ~= item.spot or hold.kind ~= (kind or "") then
			hold = { session = s.id, spot = item.spot, kind = kind or "", steady = false, last = 0 }
			grips[player] = hold
		end
		character:SetAttribute("CarryGrip", if kind then CarryGrip.encode(kind, thing.weight, thing.fragile) else nil)
		steady = steady and hold.steady
	end
	return CarryGrip.speedFactor(steady)
end
-- ── (end of the grip hook) ───────────────────────────────────────────────────────────────────────────────────────────

-- The holders' attributes for the thing now (its mode: the walk, the hands).
local function setHands(s: Session, item: Item)
	local thing = s.move.things[item.spot]
	local mode = heldMode(s, thing) -- 7.0 planning: a Mover holds a pair thing alone up …
	local grip = gripHands(s, item) -- 7.0 grip hook: the bar's kind for its holders, × the steady walk
	local speed = speedOf(s, thing) * climbOf(s, item.spot) * grip -- … and carries faster; the others slower up stairs
	local carrier = playerById(thing.carrier)
	local _, humanoid, root = bodyOrNil(carrier)
	local character = carrier and carrier.Character
	if character and humanoid and root then
		character:SetAttribute("Carrying", if mode == "hand" then "crate" else "furniture")
		character:SetAttribute("CarryCount", 1)
		character:SetAttribute("CarryHands", Rules.hands(mode))
		character:SetAttribute("CarryAt", holdOffset(thing, mode, root, humanoid).Position)
		character:SetAttribute("CarrySize", Vector3.new(thing.size.X, thing.size.Y, thing.size.Z))
		character:SetAttribute("CarrySpeed", speed)
		character:SetAttribute("MoveCarry", item.spot)
	end
	local helper = playerById(thing.helper)
	local helperBody = helper and helper.Character
	if helperBody then
		helperBody:SetAttribute("Carrying", "furniture")
		helperBody:SetAttribute("CarryCount", 1)
		helperBody:SetAttribute("CarryHands", 2)
		helperBody:SetAttribute("CarryAt", nil)
		helperBody:SetAttribute("CarrySize", nil)
		helperBody:SetAttribute("CarrySpeed", speed)
		helperBody:SetAttribute("MoveCarry", item.spot)
	end
end

local hurtThing: (Session, number, number) -> ()
local release: (Session, Player, string) -> ()

-- The holders' hooks and G prompts made again (after any change of who holds it).
local function rewire(s: Session, item: Item)
	for _, hook in item.hooks do
		hook:Disconnect()
	end
	table.clear(item.hooks)
	for _, prompt in item.down do
		prompt:Destroy()
	end
	table.clear(item.down)
	table.clear(item.health)
	local thing = s.move.things[item.spot]
	item.pick.Enabled = thing.state == "home" or thing.state == "ground"
	item.help.Enabled = thing.state == "carried" and thing.class == "pair" and thing.helper == nil
	item.help:SetAttribute("MoveSkip", thing.carrier)
	if thing.state ~= "carried" then
		return
	end
	for _, id in { thing.carrier, thing.helper } do
		local player = playerById(id)
		local character, humanoid, root = bodyOrNil(player)
		if not player or not character or not humanoid or not root then
			continue
		end
		local holder: Player = player
		local isCarrier = id == thing.carrier
		local down = newPrompt(item.root, if isCarrier then "Put down" else "Let go", labelOf(thing), Enum.KeyCode.G, 0, 6)
		down.GamepadKeyCode = Enum.KeyCode.ButtonB
		down:SetAttribute("MoveOnly", holder.UserId)
		tag(down, s.owner)
		table.insert(item.down, down)
		table.insert(item.hooks, down.Triggered:Connect(function(by: Player)
			if by == holder then
				release(s, holder, "put")
			end
		end))
		local function lost(why: string)
			if not s.ended and (thing.carrier == holder.UserId or thing.helper == holder.UserId) then
				release(s, holder, why)
			end
		end
		table.insert(item.hooks, humanoid.Died:Connect(function()
			lost("died")
		end))
		table.insert(item.hooks, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if humanoid.SeatPart ~= nil then
				lost("seat")
			end
		end))
		table.insert(item.hooks, character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				lost("gone")
			end
		end))
		-- a bite (any health lost) knocks it
		item.health[holder] = humanoid.Health
		table.insert(item.hooks, humanoid.HealthChanged:Connect(function(health: number)
			local before = item.health[holder] or health
			item.health[holder] = health
			if health < before and health > 0 then
				hurtThing(s, item.spot, Rules.hitDamage(before - health, thing.fragile))
			end
		end))
		if isCarrier then
			-- a fall from a height jolts it (the highest point of the fall: the tick keeps it)
			table.insert(item.hooks, humanoid.StateChanged:Connect(function(_, state: Enum.HumanoidStateType)
				if state == Enum.HumanoidStateType.Freefall then
					item.fallFrom = root.Position.Y
				elseif state == Enum.HumanoidStateType.Landed or state == Enum.HumanoidStateType.Running then
					local from = item.fallFrom
					item.fallFrom = nil
					if from then
						hurtThing(s, item.spot, Rules.fallDamage(from - root.Position.Y, thing.fragile))
					end
				end
			end))
		end
	end
end

-- Into the carrier's arms (or dragged), welded to their root.
local function carry(s: Session, item: Item)
	local thing = s.move.things[item.spot]
	local carrier = playerById(thing.carrier)
	local _, humanoid, root = bodyOrNil(carrier)
	if not carrier or not humanoid or not root then
		return
	end
	local mode = heldMode(s, thing) -- (7.0 planning: a Mover's pair thing alone is held up, not dragged)
	item.model.Parent = folder -- (out of the interior's model: it goes where its carrier goes)
	weldTo(item, root, root.CFrame * holdOffset(thing, mode, root, humanoid))
	item.lastAt, item.lastTime, item.apartSince, item.fallFrom = nil, 0, nil, nil
	setHands(s, item)
	rewire(s, item)
	pcall(function()
		require(script.Parent.Hand).holster(carrier, true) -- (no gun in the hand with a thing in your arms)
	end)
end

-- Set down on the floor under where it is now (its turn kept); returns how far it fell onto it. No floor under it (out
-- of the world): back at its spot in the house.
local function settle(item: Item, thing: Rules.Thing, at: CFrame): number
	unweld(item)
	setParts(item.model, true, false, item.root)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { item.model }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, name in { "Zombies", "Npcs" } do -- (7.0 review: never on a zombie's or Danny's body)
		local bodies = workspace:FindFirstChild(name)
		if bodies then
			table.insert(ignore, bodies)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(at.Position + Vector3.new(0, 1, 0), Vector3.new(0, -80, 0), params)
	if not hit then
		item.model:PivotTo(item.home)
		return 0
	end
	local bottom = at.Position.Y - thing.size.Y / 2
	local floor = hit.Position.Y
	local _, yaw = at:ToOrientation()
	item.model:PivotTo(CFrame.new(at.X, floor + thing.size.Y / 2, at.Z) * CFrame.Angles(0, yaw, 0))
	return bottom - floor
end

-- `player` lets go of what they hold. why: "put" (G), "died", "seat", "gone" (left), "apart" (the pair too far
-- apart), "pace" (too fast), "left" (out of the crew), "end". The carrier sets it down (the helper's end too); a helper
-- lets go of their end only (the carrier drags it on), but a pair torn apart goes down whole.
release = function(s: Session, player: Player, why: string)
	local spot, role = Rules.holding(s.move, player.UserId)
	if not spot then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local apart = why == "apart"
	if role == "helper" and not apart then
		Rules.release(s.move, player.UserId)
		clearHands(player)
		if item then
			local carrier = playerById(thing.carrier)
			if carrier and why ~= "end" then
				say(carrier, `{player.DisplayName} let go: you drag the {thing.name} alone now.`)
			end
			carry(s, item) -- (dragged again: the carrier's weld and walk)
		end
		s.dirty = true
		return
	end
	local carrier = playerById(thing.carrier)
	local helper = playerById(thing.helper)
	local at = if item then item.root.CFrame else nil
	if why == "pace" and item and item.lastAt then
		at = CFrame.new(item.lastAt) * (if at then at.Rotation else CFrame.identity)
	end
	Rules.release(s.move, thing.carrier or player.UserId)
	clearHands(carrier)
	clearHands(helper)
	if item and at then
		for _, hook in item.hooks do
			hook:Disconnect()
		end
		table.clear(item.hooks)
		local fell = settle(item, thing, at)
		rewire(s, item)
		if why == "died" then
			hurtThing(s, spot, Rules.deathDamage(thing.fragile))
		elseif why == "put" then
			hurtThing(s, spot, Rules.fallDamage(fell, thing.fragile))
		end
	end
	if apart then
		for _, who in { carrier, helper } do
			if who then
				say(who, `Too far apart: the {thing.name} went down. Stay close when you carry it together.`)
			end
		end
	elseif why == "pace" and carrier then
		say(carrier, `Too fast with the {thing.name}: it went down where you were.`)
	end
	s.dirty = true
end

hurtThing = function(s: Session, spot: number, share: number)
	local thing = s.move.things[spot]
	if not thing or share <= 0 or s.ended then
		return
	end
	local before = thing.condition
	local broke = Rules.hurt(thing, share)
	s.dirty = true
	if broke then
		tellAll(s, `💥 The {thing.name} broke! It pays nothing now.`)
	elseif before - thing.condition >= 0.1 then
		local holder = playerById(thing.carrier)
		if holder then
			say(holder, `⚠ The {thing.name} took a knock: {math.floor(thing.condition * 100 + 0.5)}% left.`)
		end
	end
end

-- ── The truck ──────────────────────────────────────────────────────────────

local function truckOk(s: Session): Vehicles.Car?
	local truck = s.truck
	if truck and not truck.wrecked and truck.model.Parent and Vehicles.get(s.owner) == truck then
		return truck
	end
	return nil
end

-- 7.x van moves: a car's bed (Config.Moving.Beds by its id, else the ZDC Van's) and as MovingRules' numbers.
local function bedOf(truck: Vehicles.Car?): { Width: number, Length: number, Height: number, Cell: number, Center: { number } }
	return (if truck then T.Beds[truck.id] else nil) or T.Beds[T.Van]
end

local function rulesBed(truck: Vehicles.Car?): Rules.Bed
	local bed = bedOf(truck)
	return { width = bed.Width, length = bed.Length, height = bed.Height, cell = bed.Cell }
end

-- The bed's place in the truck's chassis frame: (its middle at the floor, from MovingRules.where's numbers).
local function bedFrame(truck: Vehicles.Car, x: number, y: number, z: number, turned: boolean): CFrame
	local slots = Vehicles.cargoSlots(truck)
	local floor = if slots[1] then slots[1].Position.Y else 0.6
	local turn = if turned then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
	local center = bedOf(truck).Center -- (7.x van moves: the car's own bay)
	return truck.chassis.CFrame * CFrame.new(center[1] + x, floor + y, center[2] + z) * turn
end

-- 7.x van moves: a hitched piece behind the car (Config.Moving.Hitch), its wheels on the ground.
local function hitchFrame(truck: Vehicles.Car, thing: Rules.Thing): CFrame
	local h = T.Hitch
	return truck.chassis.CFrame * CFrame.new(0, -h.Drop + thing.size.Y / 2, h.Back + h.Gap + thing.size.Z / 2)
end

local function stow(s: Session, item: Item, at: Rules.Placement)
	local truck = truckOk(s)
	if not truck then
		return
	end
	for _, hook in item.hooks do
		hook:Disconnect()
	end
	table.clear(item.hooks)
	if at.hitch then
		weldTo(item, Vehicles.cargoHolder(truck), hitchFrame(truck, s.move.things[item.spot])) -- (7.x van moves: towed)
	else
		local x, y, z = Rules.where(s.move.packing, at)
		weldTo(item, Vehicles.cargoHolder(truck), bedFrame(truck, x, y, z, at.turned))
	end
	rewire(s, item)
end

-- Near the truck's open back, on foot, the truck standing: (ok, what to say).
local function atBack(s: Session, player: Player): (boolean, string?)
	local truck = truckOk(s)
	local door = truck and Vehicles.cargoDoor(truck)
	local _, humanoid, root = bodyOf(player)
	if not truck or not door or not humanoid or not root then
		return false, nil
	end
	if humanoid.SeatPart then
		return false, "Get out first."
	elseif flat(root.Position, door.WorldPosition) > T.Reach.Truck + 3 then
		return false, nil
	elseif not Vehicles.backOpen(truck) then
		return false, `Open the back first (E): {Vehicles.backVerb(truck, true)}.`
	elseif Vehicles.speed(truck) > Config.Cargo.MaxCarSpeed then
		return false, "Stop the van first."
	end
	return true, nil
end

-- 7.0 review: did `holder` move the thing faster than its carry allows since the last look (item.lastAt at
-- item.lastTime: a teleport)? watchCarried looks every tick, Load right before it takes it.
local function paceBroken(s: Session, item: Item, thing: Rules.Thing, holder: Player, character: Model, root: BasePart, clock: number): boolean
	local last = item.lastAt
	if traveling[holder] or not last or item.lastTime <= 0 then
		return false
	end
	local walk = speedOf(s, thing) -- (7.0 planning: the carrier's role's walk)
	local admin = holder:GetAttribute("AdminSpeed")
	local kit = character:GetAttribute("KitSpeed")
	local boost = (if type(admin) == "number" then math.clamp(admin, 1, 4) else 1) * (if type(kit) == "number" then math.clamp(kit, 1, 2) else 1)
	return flat(root.Position, last) > walk * boost * T.Pace.Factor * (clock - item.lastTime) + T.Pace.Slack
end

local function onLoad(s: Session, player: Player)
	if s.ended or sessionOf(player) ~= s then
		return
	end
	local ok, why = atBack(s, player)
	if not ok then
		if why then
			say(player, why)
		end
		return
	end
	local spot = Rules.holding(s.move, player.UserId)
	local thing = if spot then s.move.things[spot] else nil
	local helper = if thing then playerById(thing.helper) else nil
	-- 7.0 review: the thing is still there (a missing model never loads nor pays), and came at a carry's pace
	local held = if spot then s.items[spot] else nil
	if spot and thing and thing.carrier == player.UserId then
		if not held or not held.model.Parent then
			Rules.release(s.move, player.UserId)
			clearHands(player)
			clearHands(helper)
			say(player, Rules.whyText("gone"))
			s.dirty = true
			return
		end
		local character, _, root = bodyOf(player)
		if character and root and paceBroken(s, held, thing, player, character, root, os.clock()) then
			release(s, player, "pace")
			return
		end
	end
	local at, refused = Rules.load(s.move, player.UserId)
	if not at or not spot or not thing then
		say(player, Rules.whyText(refused))
		return
	end
	clearHands(player)
	clearHands(helper)
	local item = s.items[spot]
	if item then
		stow(s, item, at)
	end
	local c = Rules.counts(s.move)
	local fill = math.floor(Rules.fill(s.move.packing) * 100 + 0.5)
	say(player, if at.hitch
		then `{labelOf(thing)} hitched behind the van · {c.out} in the van · drive it to the Wall`
		else `{labelOf(thing)} loaded · {c.out} in the van · van {fill}% full · {c.delivered}/{c.total} delivered`)
	s.dirty = true
end

local function onUnload(s: Session, player: Player)
	if s.ended or sessionOf(player) ~= s then
		return
	end
	local ok, why = atBack(s, player)
	if not ok then
		if why then
			say(player, why)
		end
		return
	end
	local character = player.Character -- (7.0 review: like Pick up: a crate, a trolley in your hands)
	if character and (character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil) then
		say(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	local spot, refused = Rules.unload(s.move, player.UserId)
	if not spot then
		say(player, Rules.whyText(refused))
		return
	end
	local item = s.items[spot]
	if item then
		carry(s, item)
	end
	s.dirty = true
end

local function truckPrompts(s: Session)
	local truck = truckOk(s)
	local door = truck and Vehicles.cargoDoor(truck)
	if not truck or not door then
		return
	end
	for _, old in { s.load, s.unload } do
		if old then
			old:Destroy() -- (7.x van moves: a van called again after the last was lost: its prompts on the new one)
		end
	end
	local load = newPrompt(door, "Load", "ZDC Van", Enum.KeyCode.E, 0.25, T.Reach.Truck)
	local unload = newPrompt(door, "Unload", "ZDC Van", Enum.KeyCode.Z, 0.4, T.Reach.Truck)
	unload.GamepadKeyCode = Enum.KeyCode.ButtonY
	load.Enabled, unload.Enabled = false, false
	tag(load, s.owner)
	tag(unload, s.owner)
	load.Triggered:Connect(function(player: Player)
		onLoad(s, player)
	end)
	unload.Triggered:Connect(function(player: Player)
		onUnload(s, player)
	end)
	s.load, s.unload = load, unload
	for _, prompt in { load, unload } do
		prompt:SetAttribute("MoveQuick", "driver") -- (client/MovingHud.luau: no hold for a Driver; a new van's too)
	end
end

-- 7.x van moves: the van's back as it was before the move (the end; a van lost mid-move).
local function releaseBack(truck: Vehicles.Car?)
	if truck and truck.model.Parent then
		truck.model:SetAttribute("BackCrew", nil)
		local back = Vehicles.backPrompt(truck)
		if back then
			back.Enabled = true
		end
	end
end

-- The truck's prompts as things stand: Load while somebody of the crew carries a thing (the back's own E waits
-- then), Unload while one may come out; the back for the crew too (BackCrew).
local function refreshTruck(s: Session)
	local truck = truckOk(s)
	local load, unload = s.load, s.unload
	if not truck or not load or not unload then
		return
	end
	local open = Vehicles.backOpen(truck)
	local carried: Rules.Thing? = nil
	local carriers = 0
	local door = Vehicles.cargoDoor(truck)
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local _, _, carrierRoot = bodyOrNil(playerById(thing.carrier)) -- (7.0 helper: not what Danny carries)
		-- (7.0 review: only a carrier at the back: one in the house does not keep the back from closing)
		if thing.state == "carried" and carrierRoot and door and flat(carrierRoot.Position, door.WorldPosition) <= T.Reach.Truck + 3 then
			carriers += 1
			carried = thing
		end
	end
	local fill = math.floor(Rules.fill(s.move.packing) * 100 + 0.5)
	load.Enabled = open and carriers > 0
	load.ActionText = if carriers == 1 and carried then `Load {carried.name}` else "Load"
	load.ObjectText = `ZDC Van · {fill}% full`
	local out = Rules.lastOut(s.move)
	unload.Enabled = open and out ~= nil
	unload.ActionText = if out then `Unload {s.move.things[out].name}` else "Unload"
	unload.ObjectText = `ZDC Van · {fill}% full`
	local back = Vehicles.backPrompt(truck)
	if back then
		back.Enabled = not load.Enabled
	end
	local ids: { string } = {}
	for _, member in Crew.members(s.owner) do
		table.insert(ids, tostring(member.UserId))
	end
	local crew = if #ids > 0 then table.concat(ids, ",") else nil
	if truck.model:GetAttribute("BackCrew") ~= crew then
		truck.model:SetAttribute("BackCrew", crew)
	end
end

-- ── 7.0: the depot's helper's hands (server/MoveHelper.luau) ──────────────
-- Danny ("Danny from the depot", an NPC for a crew of one) does what a player's hands do through these, with the same
-- rules, welds and damage. `npc` is his body; its attribute MoveHelper is his id in the rules (a negative number: no
-- player has it, so the player-only paths above leave him alone: no G prompt, no pace or apart check, no Load prompt).
-- Server/MoveHelper.luau checks how near he is; these check the rules.

local function helperIdOf(npc: Model): number?
	local id = npc:GetAttribute("MoveHelper")
	return if type(id) == "number" then id else nil
end

-- A holder's name for the list: a player's, or the helper's.
local function holderName(id: number?): string?
	local player = playerById(id)
	if player then
		return player.DisplayName
	end
	return MoveHelper.nameOf(id)
end

-- He takes `spot`: a one-hand thing into his arms (in front of his chest, like a player's), or the other end of a pair
-- thing a player lifted (their walk: two people's now). Never a "both" thing, never a pair thing alone. (ok, why)
function Moving.helperTake(s: Session, spot: number, npc: Model): (boolean, string?)
	local who = helperIdOf(npc)
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local root = npc.PrimaryPart
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if s.ended or not who or not item or not thing or not root or not humanoid then
		return false, "gone"
	end
	if thing.class == "pair" then
		local ok, why = Rules.help(s.move, spot, who)
		if not ok then
			return false, why
		end
		carry(s, item) -- (carried now, not dragged: the carrier's weld and walk change)
		local carrier = playerById(thing.carrier)
		if carrier then
			say(carrier, `{npc.Name} took the other end of the {thing.name}: walk together.`)
		end
		s.dirty = true
		return true, nil
	elseif thing.class ~= "hand" then
		return false, "single"
	end
	local ok, why = Rules.pick(s.move, spot, who)
	if not ok then
		return false, why
	end
	item.model.Parent = folder
	weldTo(item, root, root.CFrame * holdOffset(thing, "hand", root, humanoid))
	item.lastAt, item.lastTime, item.apartSince, item.fallFrom = nil, 0, nil, nil
	rewire(s, item)
	s.dirty = true
	return true, nil
end

-- He lets go. why: "put" (set down gently where he is), "died" (it falls: knocked), "apart" (his end of a pair thing:
-- left behind) or "end". His end of a pair thing: the carrier drags it on alone.
function Moving.helperDrop(s: Session, npc: Model, why: string)
	local who = helperIdOf(npc)
	if not who then
		return
	end
	local spot, role = Rules.holding(s.move, who)
	if not spot then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	if role == "helper" then
		Rules.release(s.move, who)
		local carrier = playerById(thing.carrier)
		if item and carrier and not s.ended then
			if why ~= "end" then
				say(carrier, `{npc.Name} let go: you drag the {thing.name} alone now.`)
			end
			carry(s, item) -- (dragged again: the carrier's weld and walk)
		end
		s.dirty = true
		return
	end
	local at = if item then item.root.CFrame else nil
	Rules.release(s.move, who)
	if item and at then
		for _, hook in item.hooks do
			hook:Disconnect()
		end
		table.clear(item.hooks)
		local fell = settle(item, thing, at)
		rewire(s, item)
		if why == "died" then
			hurtThing(s, spot, Rules.deathDamage(thing.fragile))
		elseif why == "put" then
			hurtThing(s, spot, Rules.fallDamage(fell, thing.fragile))
		end
	end
	s.dirty = true
end

-- He puts what he carries into the truck (MovingRules' packer, like Load). (ok, why: "noroom", "empty" …)
function Moving.helperLoad(s: Session, npc: Model): (boolean, string?)
	local who = helperIdOf(npc)
	if s.ended or not who or not truckOk(s) then
		return false, "over"
	end
	local spot = Rules.holding(s.move, who)
	local thing = if spot then s.move.things[spot] else nil
	local held = if spot then s.items[spot] else nil
	if spot and (not held or not held.model.Parent) then -- (7.0 review: a missing model never loads nor pays)
		Rules.release(s.move, who)
		s.dirty = true
		return false, "gone"
	end
	local at, refused = Rules.load(s.move, who)
	if not at or not spot or not thing then
		return false, refused
	end
	local item = s.items[spot]
	if item then
		stow(s, item, at)
	end
	local c = Rules.counts(s.move)
	say(s.owner, `{npc.Name} loaded {labelOf(thing)} · {c.out}/{c.total} out · truck {math.floor(Rules.fill(s.move.packing) * 100 + 0.5)}% full`)
	s.dirty = true
	return true, nil
end

-- A bite took `hp` of his health: what he holds takes the knock (like a player's).
function Moving.helperHurt(s: Session, npc: Model, hp: number)
	local who = helperIdOf(npc)
	local spot = if who then Rules.holding(s.move, who) else nil
	local thing = if spot then s.move.things[spot] else nil
	if spot and thing then
		hurtThing(s, spot, Rules.hitDamage(hp, thing.fragile))
	end
end

-- ── Doors: in and out with a fade ──────────────────────────────────────────

local travel: (Player, CFrame, Session, boolean, boolean?) -> ()

travel = function(player: Player, target: CFrame, s: Session, inside: boolean, partner: boolean?)
	if traveling[player] then
		return
	end
	traveling[player] = true
	remote:FireClient(player, "fade", "out", T.Fade)
	task.delay(T.Fade, function()
		-- (7.0 review: in a pcall; whatever happens the trip is over and the fade lifts)
		local ok, err = pcall(function()
			pcall(function()
				player:RequestStreamAroundAsync(target.Position, 4)
			end)
			-- the move ended (or its house went) while the screen was dark: out at the house's door, never the void
			local goal, goalInside = target, inside
			if inside and (s.ended or not (s.interior and s.interior.Parent)) then
				goal, goalInside = s.site.outside, false
			end
			local character, humanoid, root = bodyOf(player)
			if character and humanoid and root then
				local lift = humanoid.HipHeight + root.Size.Y / 2
				character:PivotTo(goal + Vector3.new(0, lift, 0))
				if goalInside then
					s.inside[player] = true
				else
					s.inside[player] = nil
				end
				local spot, role = Rules.holding(s.move, player.UserId)
				if spot then
					local item = s.items[spot]
					if item then
						item.lastAt, item.fallFrom, item.apartSince = nil, nil, nil
					end
					-- the other end of a pair thing comes along, beside you
					local thing = s.move.things[spot]
					local other = playerById(if role == "carrier" then thing.helper else thing.carrier)
					if other and not partner then
						travel(other, goal * CFrame.new(3.5, 0, 0), s, goalInside, true)
					end
				end
			end
		end)
		if not ok then
			warn(`[Moving] a door trip failed: {err}`)
		end
		traveling[player] = nil
		if player.Parent then
			remote:FireClient(player, "fade", "in", T.Fade)
		end
		s.dirty = true
	end)
end

-- ── 7.x farm move: the ways in and out (a house's front door; a farm's farmhouse door and barn doors) ──────────────

-- The exits a thing may go through (shared/HouseLayout.luau exitsFor: a farm's bigDoor piece the barn doors only);
-- every exit when the art does not say.
local function exitsFor(s: Session, spot: number): { number }
	local thing = s.move.things[spot]
	local a = art
	local layout = if a then a.layout else nil
	if thing and layout and type(layout.exitsFor) == "function" then
		local ok, list = pcall(layout.exitsFor, s.plan, thing.item)
		if ok and type(list) == "table" then
			return list
		end
	end
	local all: { number } = {}
	for index in s.ways do
		table.insert(all, index)
	end
	return all
end

-- server/MoveHelper.luau: the ways out (indexes into s.ways) Danny may take with what he holds (`spot`; nil: any).
function Moving.helperExits(s: Session, spot: number?): { number }
	if spot then
		return exitsFor(s, spot)
	end
	local all: { number } = {}
	for index in s.ways do
		table.insert(all, index)
	end
	return all
end

-- May what `player` carries (as its carrier) go through exit `index`? (true, nil) or (false, the hint).
local function mayPass(s: Session, player: Player, index: number): (boolean, string?)
	local spot, role = Rules.holding(s.move, player.UserId)
	if not spot or role ~= "carrier" then
		return true, nil
	end
	local allowed = exitsFor(s, spot)
	if table.find(allowed, index) then
		return true, nil
	end
	local way = s.ways[allowed[1] or 0]
	return false, `Too big — use the {if way then way.door.name else "other door"}.`
end

-- The way out nearest a point inside (the one a player who must come out takes), else the front door's.
local function wayNear(s: Session, at: Vector3?): Way?
	local best: Way? = s.ways[1]
	local bestDistance = math.huge
	if at then
		for _, way in s.ways do
			local d = (way.inside - at).Magnitude
			if d < bestDistance then
				best, bestDistance = way, d
			end
		end
	end
	return best
end

-- Where somebody inside comes out when they must (the move ended, they left the crew): the nearest door's outside.
local function outsideFor(s: Session, player: Player): CFrame
	local _, _, root = bodyOf(player)
	local way = wayNear(s, if root then root.Position else nil)
	return if way then way.door.outside else s.site.outside
end

onEnter = function(player: Player, contractId: string, index: number?)
	local s = sessionOf(player)
	if not s or s.contract.id ~= contractId then
		say(player, "Locked. Take this moving contract at the depot's board first (ZDC Moving).")
		return
	end
	if traveling[player] or s.ended then
		return
	end
	local _, humanoid, root = bodyOf(player)
	if not humanoid or not root then
		return
	end
	if humanoid.SeatPart then
		say(player, "Get out first.")
		return
	end
	local door = s.site.doors[index or 1] or s.site.doors[1]
	if flat(root.Position, door.door) > T.Reach.Door + 4 + door.width / 2 then
		return
	end
	local spot, role = Rules.holding(s.move, player.UserId)
	if spot and role == "helper" then
		say(player, "The one at the front leads the way in.")
		return
	end
	local ok, why = mayPass(s, player, door.exit) -- (7.x farm move: the hay wagon in by the barn doors only)
	if not ok then
		say(player, why or "")
		return
	end
	local way = s.ways[door.exit] or s.ways[1]
	travel(player, if way then way.entry else s.origin * (s.plan.entry :: CFrame), s, true)
end

local function onLeave(player: Player, s: Session, index: number?)
	local way = s.ways[index or 1]
	local exit = if way then way.part else s.exit
	local _, humanoid, root = bodyOf(player)
	if traveling[player] or not exit or not humanoid or not root then
		return
	end
	if flat(root.Position, exit.Position) > T.Reach.Exit + 4 + exit.Size.X / 2 then
		return
	end
	local spot, role = Rules.holding(s.move, player.UserId)
	if spot and role == "helper" then
		say(player, "The one at the front leads the way out.")
		return
	end
	local ok, why = mayPass(s, player, if way then way.exit else 1) -- (7.x farm move: "Too big — use the barn doors")
	if not ok then
		say(player, why or "")
		return
	end
	travel(player, if way then way.door.outside else s.site.outside, s, false)
end

-- ── The things' prompts ────────────────────────────────────────────────────

local function onPick(s: Session, spot: number, player: Player)
	if s.ended or sessionOf(player) ~= s or traveling[player] then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local character, humanoid, root = bodyOf(player)
	if not item or not thing or not character or not humanoid or not root then
		return
	end
	if humanoid.SeatPart then
		say(player, "Get out first.")
		return
	end
	if flat(root.Position, item.root.Position) > T.Reach.Item + math.max(thing.size.X, thing.size.Z) / 2 + 2 then
		return
	end
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil then
		say(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	local ok, why = Rules.pick(s.move, spot, player.UserId)
	if not ok then
		say(player, Rules.whyText(why))
		return
	end
	carry(s, item)
	if thing.class == "pair" then
		say(player, `The {thing.name} needs two: you drag it slowly. A crew mate can "Help lift" the other end.`)
	end
	s.dirty = true
end

local function onHelp(s: Session, spot: number, player: Player)
	if s.ended or sessionOf(player) ~= s or traveling[player] then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local character, humanoid, root = bodyOf(player)
	if not item or not thing or not character or not humanoid or not root or humanoid.SeatPart then
		return
	end
	if flat(root.Position, item.root.Position) > T.Reach.Item + math.max(thing.size.X, thing.size.Z) / 2 + 2 then
		return
	end
	if thing.carrier == player.UserId then
		say(player, Rules.whyText("yours"))
		return
	end
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil then
		say(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	local ok, why = Rules.help(s.move, spot, player.UserId)
	if not ok then
		say(player, Rules.whyText(why))
		return
	end
	pcall(function()
		require(script.Parent.Hand).holster(player, true)
	end)
	carry(s, item) -- (carried now, not dragged: the carrier's weld and walk change)
	local carrier = playerById(thing.carrier)
	if carrier then
		say(carrier, `{player.DisplayName} took the other end of the {thing.name}: walk together.`)
	end
	say(player, `You hold the other end of the {thing.name}: stay close to it.`)
	s.dirty = true
end

local function setupItem(s: Session, spot: number, model: Model)
	local thing = s.move.things[spot]
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not thing or not root or not root:IsA("BasePart") then
		return -- (a spot of furniture the rules do not know stays where it is)
	end
	local hold = if thing.class == "hand" then 0 elseif thing.class == "both" then 0.3 else 0.5
	local pick = newPrompt(root, if thing.class == "pair" then "Lift" else "Pick up", labelOf(thing), Enum.KeyCode.E, hold, T.Reach.Item)
	local help = newPrompt(root, "Help lift", labelOf(thing), Enum.KeyCode.E, 0.3, T.Reach.Item)
	help.Enabled = false
	tag(pick, s.owner)
	tag(help, s.owner)
	pick.Triggered:Connect(function(player: Player)
		onPick(s, spot, player)
	end)
	help.Triggered:Connect(function(player: Player)
		onHelp(s, spot, player)
	end)
	model:SetAttribute("MoveSpot", spot)
	s.items[spot] = {
		spot = spot,
		model = model,
		root = root,
		home = model:GetPivot(),
		pick = pick,
		help = help,
		down = {},
		weld = nil,
		hooks = {},
		health = {},
		lastAt = nil,
		lastTime = 0,
		apartSince = nil,
		fallFrom = nil,
	}
end

-- ── 7.0 planning: the roles' abilities ─────────────────────────────────────

local R = Config.MoveRoles

local function setAttr(player: Player, name: string, value: any)
	if player.Parent and player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function memberIds(s: Session): { number }
	local ids: { number } = {}
	for _, player in membersOf(s) do
		table.insert(ids, player.UserId)
	end
	return ids
end

-- Gives `player` the role: their attribute, what they hold at that role's walk and hold.
local function setRole(s: Session, player: Player, role: string)
	s.team.of[player.UserId] = role
	setAttr(player, "MoveRole", role)
	local spot, as = Rules.holding(s.move, player.UserId)
	local item = if spot then s.items[spot] else nil
	if item and as == "carrier" then
		carry(s, item)
	end
	s.dirty = true
end

-- "Enter house" at the house's front door: this move's own, for its crew only (MoveOwner). The door is never locked
-- (the owner took the Technician out): the client on the porch greets the crew there (server/MoveGreeters.luau).
-- 7.x farm move: one at every door of the site (a farm's: "Enter house" at the farmhouse, "Enter barn" at the barn
-- doors), each to its own way in (onEnter's index); the front door's is team.enter, the others team.doors.
local function enterPrompt(s: Session)
	for index, door in s.site.doors do
		local spot = door.part
		if not spot then
			continue
		end
		local action = if index == 1 then "Enter house" else "Enter barn"
		local enter = newPrompt(spot, action, `{s.contract.icon} {s.contract.name}`, Enum.KeyCode.E, 0, T.Reach.Door + door.width / 2)
		tag(enter, s.owner)
		enter.Triggered:Connect(function(player: Player)
			onEnter(player, s.contract.id, index)
		end)
		if index == 1 then
			s.team.enter = enter
		else
			table.insert(s.team.doors, enter)
		end
	end
end

-- 7.x farm move: the site's door nearest a player (inside: the nearest way out's), and how far.
local function doorNear(s: Session, player: Player): SiteDoor
	local _, _, root = bodyOf(player)
	if root and s.inside[player] then
		local way = wayNear(s, root.Position)
		if way then
			return way.door
		end
	end
	local best = s.site.doors[1]
	local bestDistance = math.huge
	for _, door in s.site.doors do
		local d = if root then flat(root.Position, door.door) else 0
		if d < bestDistance then
			best, bestDistance = door, d
		end
	end
	return best
end

-- 7.x farm move: how far `at` is from the nearest door of the site.
local function fromDoors(s: Session, at: Vector3): number
	local best = math.huge
	for _, door in s.site.doors do
		best = math.min(best, flat(at, door.door))
	end
	return best
end

-- Is a Driver of the crew at the truck's wheel?
local function driverAtWheel(s: Session): boolean
	local truck = s.truck
	if not truck then
		return false
	end
	for _, player in membersOf(s) do
		if s.team.of[player.UserId] == "driver" then
			local car, driving = Vehicles.seatedIn(player)
			if car == truck and driving then
				return true
			end
		end
	end
	return false
end

-- The Driver's "Call truck to door" (once a move): the empty van to the curb of the site's door nearest the caller
-- (7.x farm move: a farm's farmhouse door or barn doors, its back to the door; a house's kerb along the road), with a
-- fade for the caller.
local function callTruck(s: Session, player: Player)
	local ok, why = MoveRoles.canCall(roleOf(s, player), s.team.called)
	if not ok then
		say(player, MoveRoles.whyText(why))
		return
	end
	local truck = truckOk(s)
	if not truck then
		say(player, "No van to call: bring it back with CAR first.")
		return
	end
	for _, other in Players:GetPlayers() do
		if Vehicles.seatedIn(other) == truck then
			say(player, "Somebody sits in the van: it can't drive itself.")
			return
		end
	end
	local door = doorNear(s, player)
	local spot, heading = door.park, door.heading
	if flat(truck.chassis.Position, spot) <= R.Driver.Near then
		say(player, "The van is at the door already.")
		return
	end
	s.team.called = true
	remote:FireClient(player, "fade", "out", T.Fade)
	task.delay(T.Fade, function()
		if not s.ended and truckOk(s) == truck then
			local ground = Vector3.new(spot.X, Vehicles.groundY(spot.X, spot.Z) + 4, spot.Z)
			truck.chassis.AssemblyLinearVelocity = Vector3.zero
			truck.chassis.AssemblyAngularVelocity = Vector3.zero
			truck.model:PivotTo(CFrame.lookAt(ground, ground + heading))
			pcall(Vehicles.standUp, truck, heading) -- (on its wheels, on free ground: Vehicles.clearFor)
			local where = if door.exit == 1 then `{s.contract.name}'s {door.name}` else `the {door.name}`
			tellAll(s, `🚐 {player.DisplayName} called the van: it waits at {where}.`)
			s.dirty = true
		end
		remote:FireClient(player, "fade", "in", T.Fade)
	end)
end

local function barricadeModel(frame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "MoveBarricade"
	local wood = Color3.fromRGB(128, 96, 64)
	local dark = Color3.fromRGB(84, 62, 42)
	local post = rolePart("Post", Vector3.new(0.7, 5.2, 0.7), frame * CFrame.new(-3.8, 2.6, 0), dark, Enum.Material.Wood, model)
	rolePart("Post", Vector3.new(0.7, 5.2, 0.7), frame * CFrame.new(3.8, 2.6, 0), dark, Enum.Material.Wood, model)
	for index, height in { 1.1, 2.5, 3.9 } do
		local tilt = math.rad(if index == 2 then -6 else 4)
		rolePart("Plank", Vector3.new(8.6, 0.9, 0.35), frame * CFrame.new(0, height, -0.5) * CFrame.Angles(0, 0, tilt), wood, Enum.Material.WoodPlanks, model)
	end
	rolePart("Brace", Vector3.new(9.2, 0.6, 0.3), frame * CFrame.new(0, 2.5, -0.85) * CFrame.Angles(0, 0, math.rad(27)), dark, Enum.Material.Wood, model)
	model.PrimaryPart = post
	return model
end

-- The Guard's barricade: across the way in front of them, outside, near the house's door or the truck.
local function putBarricade(s: Session, player: Player)
	local team = s.team
	local id = player.UserId
	local ok, why = MoveRoles.canBarricade(roleOf(s, player), team.placed[id] or 0)
	if not ok then
		say(player, MoveRoles.whyText(why))
		return
	end
	local _, humanoid, root = bodyOf(player)
	if not humanoid or not root or traveling[player] then
		return
	elseif humanoid.SeatPart then
		say(player, "Get out first.")
		return
	elseif s.inside[player] then
		say(player, "Barricades go up outside: across the path, by the door or round the truck.")
		return
	end
	if fromDoors(s, root.Position) > R.Guard.Near then -- (7.0 review: by the house only; 7.x farm move: by any of its doors)
		say(player, `Put it up by the house: within {R.Guard.Near} studs of its front door.`)
		return
	end
	local look = root.CFrame.LookVector
	local ahead = Vector3.new(look.X, 0, look.Z)
	ahead = if ahead.Magnitude > 0.1 then ahead.Unit else s.site.facing
	local at = root.Position + ahead * 4
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -24, 0), params)
	local ground = if hit then hit.Position.Y else root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local base = Vector3.new(at.X, ground, at.Z)
	-- (7.0 review: never on the road's driving lane, never in a car's way (the truck's too) or on a player)
	local rx, rz, _, _, width = Map.nearestRoad(base.X, base.Z)
	if flat(base, Vector3.new(rx, base.Y, rz)) < width / 2 + 2 then
		say(player, "Not on the road: put it up on the path or in the yard.")
		return
	end
	local inWay: { Instance } = {}
	for _, car in Vehicles.all() do
		table.insert(inWay, car.model)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(inWay, other.Character)
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = inWay
	overlap.RespectCanCollide = true
	local box = CFrame.lookAt(base, base + ahead) * CFrame.new(0, 2.9, -0.4)
	if #workspace:GetPartBoundsInBox(box, Vector3.new(9.4, 4.8, 1.8), overlap) > 0 then
		say(player, "Something is in the way: a car, the truck or somebody. Put it up on a clear path.")
		return
	end
	local model = barricadeModel(CFrame.lookAt(base, base + ahead))
	model:SetAttribute("Hp", R.Guard.Hp)
	model.Parent = folder or workspace
	team.placed[id] = (team.placed[id] or 0) + 1
	table.insert(team.barricades, { model = model, at = base, hp = R.Guard.Hp, endsAt = now() + R.Guard.Life, by = player })
	local left = R.Guard.Barricades - team.placed[id]
	tellAll(s, `🪵 {player.DisplayName} put up a barricade{if left > 0 then ` ({left} left)` else " (the last one)"}.`)
	s.dirty = true
end

-- A role switch from the list (Tab): to a role nobody else has, Switch s after the last one.
local function switchRole(s: Session, player: Player, role: any)
	local team = s.team
	local id = player.UserId
	local ok, why, wait = MoveRoles.canSwitch(team.of, memberIds(s), id, role, team.switched[id], now())
	if not ok then
		say(player, if why == "cooldown" then `{MoveRoles.whyText(why)} Wait {wait} s.` else MoveRoles.whyText(why))
		return
	end
	team.switched[id] = now()
	setRole(s, player, role)
	local def = MoveRoles.get(role)
	if def then
		tellAll(s, `{def.icon} {player.DisplayName} is the {def.name} now.`)
	end
end

-- The Moving remote's role requests on a move: ("role", id) a switch, ("call") the truck, ("barricade").
local function teamRequest(s: Session, player: Player, action: string, arg: any)
	if s.ended or sessionOf(player) ~= s then
		return
	end
	if action == "role" then
		switchRole(s, player, arg)
	elseif action == "call" then
		callTruck(s, player)
	elseif action == "barricade" then
		putBarricade(s, player)
	end
end

-- A carried thing going up stairs or a slope (its carrier rose Mover.Rise a stud along, held Hold s): its walk ×
-- Mover.Climb (not a Mover's, nor a thing in one hand); watchCarried calls it every tick.
local function climbStep(s: Session, spot: number, holder: Player, root: BasePart, clock: number)
	local thing = s.move.things[spot]
	local c = s.team.climb[spot]
	local at = root.Position
	if not c or c.who ~= thing.carrier or clock - c.time > 1 or traveling[holder] then
		s.team.climb[spot] = { at = at, time = clock, upUntil = 0, slow = false, who = thing.carrier }
		if c and c.slow then
			local item = s.items[spot]
			if item then
				setHands(s, item)
			end
		end
		return
	end
	if clock - c.time >= 0.15 then
		if MoveRoles.climbing(at.Y - c.at.Y, flat(at, c.at)) then
			c.upUntil = clock + R.Mover.Hold
		end
		c.at, c.time = at, clock
	end
	local slow = clock < c.upUntil and MoveRoles.climbFactor(s.team.of[thing.carrier or 0], Rules.mode(thing)) < 1
	if slow ~= c.slow then
		c.slow = slow
		local item = s.items[spot]
		if item then
			setHands(s, item)
		end
	end
end

-- The barricades: the zombies at one wear it down (Bite hp a second each); broken or old, it goes.
local function teamTick(s: Session)
	local team = s.team
	local t = now()
	local dt = if team.lastTick > 0 then math.clamp(t - team.lastTick, 0, 1) else 0
	team.lastTick = t
	for index = #team.barricades, 1, -1 do
		local b = team.barricades[index]
		local count = 0
		for _, list in { s.horde, s.roam } do
			for _, z in list do
				local zroot = z.root
				if not z.dead and zroot and flat(zroot.Position, b.at) <= R.Guard.Reach then
					count += 1
				end
			end
		end
		b.hp = MoveRoles.wear(b.hp, count, dt)
		local hp = math.ceil(b.hp)
		if b.model:GetAttribute("Hp") ~= hp then
			b.model:SetAttribute("Hp", hp)
		end
		if b.hp <= 0 or t >= b.endsAt then
			b.model:Destroy()
			table.remove(team.barricades, index)
			say(b.by, if b.hp <= 0 then "🪵 The zombies broke a barricade down." else "🪵 A barricade fell apart (its time was up).")
			s.dirty = true
		end
	end
end

-- Everybody on the move has a role: the lobby's at the start, a newcomer the first free one; a leaver's goes.
local function teamSync(s: Session)
	local team = s.team
	local ids = memberIds(s)
	local changed = false
	for id in team.of do
		if not table.find(ids, id) then
			team.of[id] = nil
			local gone = playerById(id)
			if gone then
				setAttr(gone, "MoveRole", nil)
			end
			changed = true
		end
	end
	for _, player in membersOf(s) do
		local id = player.UserId
		local role = team.of[id]
		if not MoveRoles.get(role) then
			role = MoveRoles.freeRole(team.of, ids, id)
			team.of[id] = role
			changed = true
		end
		if player:GetAttribute("MoveRole") ~= role then
			setAttr(player, "MoveRole", role)
			local def = MoveRoles.get(role)
			if def then
				say(player, `{def.icon} You are the {def.name}: {def.hint}.`)
			end
		end
	end
	if changed then
		s.dirty = true
	end
end

-- The move starts: the lobby's roles (by user id; nil: the admin's start, everybody gets a free one), the house's
-- "Enter house" (never locked), the Driver's no-wait truck prompts. (No fuse box: the interior is lit as it was built.)
local function teamSetup(s: Session, roles: { [number]: string }?)
	for _, id in memberIds(s) do
		local role = if roles then roles[id] else nil
		if MoveRoles.get(role) then
			s.team.of[id] = role :: string
		end
	end
	enterPrompt(s)
	for _, prompt in { s.load, s.unload } do
		if prompt then
			prompt:SetAttribute("MoveQuick", "driver") -- (client/MovingHud.luau: no hold for a Driver)
		end
	end
	teamSync(s)
end

local function teamCleanup(s: Session)
	local team = s.team
	for _, b in team.barricades do
		b.model:Destroy()
	end
	table.clear(team.barricades)
	if team.enter then
		team.enter:Destroy()
		team.enter = nil
	end
	for _, prompt in team.doors do
		prompt:Destroy()
	end
	table.clear(team.doors)
	for id in team.of do
		local player = playerById(id)
		if player then
			setAttr(player, "MoveRole", nil)
		end
	end
	for _, player in everyone(s) do
		setAttr(player, "MoveRole", nil)
	end
end

-- What one player sees of the roles (client/MovingHud.luau).
local function teamView(s: Session, player: Player): { [string]: any }
	local team = s.team
	local id = player.UserId
	local ids = memberIds(s)
	local crew = {}
	for _, member in membersOf(s) do
		table.insert(crew, { name = member.DisplayName, role = team.of[member.UserId], you = member == player })
	end
	local free: { string } = {}
	for _, role in MoveRoles.Order do
		if MoveRoles.canSwitch(team.of, ids, id, role, nil, 0) then
			table.insert(free, role)
		end
	end
	local last = team.switched[id]
	return {
		role = team.of[id],
		crew = crew,
		free = free,
		switchAt = if last then last + R.Switch else 0,
		called = team.called,
		barricades = if team.of[id] == "guard" then math.max(0, R.Guard.Barricades - (team.placed[id] or 0)) else 0,
		up = #team.barricades,
	}
end

-- The hooks for the roles (wireHooks): the Guard's hits, the Driver's truck.
local function teamHooks()
	local damage = Zombies.damage
	Zombies.damage = function(z: any, amount: number, by: Player?, info: any): boolean
		if by and amount < math.huge then
			local s = sessionOf(by)
			local zroot = if type(z) == "table" then z.root else nil
			local at: Vector3? = if typeof(zroot) == "Instance" and zroot:IsA("BasePart") then zroot.Position else nil
			-- (7.0 review: only round this move: within Guard.Range of its house's door or its truck)
			local truck = s and s.truck
			if s and not s.ended and at and (fromDoors(s, at) <= R.Guard.Range or (truck ~= nil and flat(at, truck.chassis.Position) <= R.Guard.Range)) then
				amount *= MoveRoles.weaponFactor(roleOf(s, by), if type(info) == "table" then info.cause else nil)
			end
		end
		return damage(z, amount, by, info)
	end
	local hurtCar = Vehicles.damage
	Vehicles.damage = function(car: Vehicles.Car, amount: number, reason: string?, cause: string?): number
		if amount > 0 and amount < math.huge then
			local s = sessions[car.owner]
			if s and not s.ended and s.truck == car then
				amount *= MoveRoles.truckFactor(driverAtWheel(s)) -- (its load: onCarDamaged gets what it took)
			end
		end
		return hurtCar(car, amount, reason, cause)
	end
end

-- ── The state for the clients ──────────────────────────────────────────────

local function viewFor(s: Session, player: Player): { [string]: any }
	local items = {}
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local carrier, helper = holderName(thing.carrier), holderName(thing.helper) -- (7.0 helper: Danny's name too)
		table.insert(items, {
			spot = spot,
			name = thing.name,
			icon = thing.icon,
			star = thing.star,
			class = thing.class,
			weight = thing.weight,
			fragile = thing.fragile,
			value = thing.value,
			room = thing.room,
			state = thing.state,
			condition = math.floor(thing.condition * 100 + 0.5) / 100,
			broken = Rules.broken(thing),
			by = if carrier then carrier .. (if helper then ` + {helper}` else "") else nil,
			mine = thing.carrier == player.UserId or thing.helper == player.UserId,
		})
	end
	local truck = truckOk(s)
	local drop = dropOffAt()
	return {
		id = s.id,
		contract = s.contract.id,
		name = s.contract.name,
		icon = s.contract.icon,
		client = s.contract.client,
		owner = s.owner.DisplayName,
		mine = player == s.owner,
		endsAt = s.move.endsAt,
		hordeAt = s.move.endsAt - (s.move.hordeAt or T.HordeAt), -- (7.x farm move: the contract's own)
		seconds = s.move.seconds,
		horde = s.move.phase == "horde",
		items = items,
		counts = Rules.counts(s.move),
		fill = Rules.fill(s.move.packing),
		truck = truck ~= nil,
		backOpen = truck ~= nil and Vehicles.backOpen(truck),
		house = { x = s.site.home.park.x, z = s.site.home.park.z },
		door = { x = s.site.door.X, z = s.site.door.Z },
		dropOff = { x = drop.X, z = drop.Z },
		inside = s.inside[player] == true,
		team = teamView(s, player), -- 7.0 planning: your role, the crew's, the door, the lights, the abilities
		graceEndsAt = if s.late then s.move.endsAt + T.LateGrace else nil, -- 7.0 review: late: the Wall by then
		trips = s.move.trips or 0, -- 7.x van moves: the trips delivered at the Wall (the HUD's TRIP n: the next one)
		vanAgainAt = if s.lostAt then s.lostAt + T.VanAgain else nil, -- 7.x van moves: the van lost: CAR again then
	}
end

local function send(s: Session)
	s.dirty = false
	s.sentAt = os.clock()
	for _, player in membersOf(s) do
		remote:FireClient(player, "state", viewFor(s, player))
	end
end

-- ── The end ────────────────────────────────────────────────────────────────

local function letGoZombies(list: { Zombies.Zombie })
	for _, z in list do
		if not z.dead then
			Zombies.march(z, nil)
		end
	end
	table.clear(list)
end

-- Everything of the session goes: whoever is inside comes out, the things, the interior, the truck's prompts.
local function cleanup(s: Session)
	for player in s.inside do
		local _, _, root = bodyOf(player)
		if root and player.Parent and (root.Position - s.origin.Position).Magnitude < 600 then
			travel(player, outsideFor(s, player), s, false) -- (7.x farm move: out at the nearest door)
		end
	end
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		clearHands(playerById(thing.carrier))
		clearHands(playerById(thing.helper))
		local item = s.items[spot]
		if item and thing.state == "carried" then
			unweld(item)
			setParts(item.model, true, false, item.root)
		end
	end
	task.delay(T.Fade + 0.5, function()
		-- the interior first (server/HouseInterior.luau's own way), then the things that left it (carried, set down
		-- outside, in the truck: unloaded at the Wall)
		local interior = s.interior
		local a = art
		if interior then
			local ok = a ~= nil and pcall(function()
				(a :: Art).interior.destroy(interior)
			end)
			if not ok then
				interior:Destroy()
			end
		end
		for _, item in s.items do
			for _, hook in item.hooks do
				hook:Disconnect()
			end
			item.model:Destroy()
		end
		if s.exit then
			s.exit:Destroy()
		end
		for _, way in s.ways do -- (7.x farm move: every way out's Leave)
			way.part:Destroy()
		end
		if slots[s.slot] == s then
			slots[s.slot] = nil
		end
	end)
	for _, prompt in { s.load, s.unload } do
		if prompt then
			prompt:Destroy()
		end
	end
	releaseBack(s.truck) -- (7.x van moves: the owner's van's back as it was)
	letGoZombies(s.horde)
	letGoZombies(s.roam)
	teamCleanup(s) -- 7.0 planning: the barricades, the Enter prompt, the roles' attributes
	pcall(MoveGreeters.done, s) -- 7.0 greeters: the client leaves the porch; delivered: the soldier's welcome at the Wall
	for member in s.members do
		if member:GetAttribute("MoveWith") == s.owner.UserId then
			member:SetAttribute("MoveWith", nil)
		end
	end
	if sessions[s.owner] == s then
		sessions[s.owner] = nil
	end
end

local payOut: (Session, string, string?) -> ()

-- 7.x farm move: a chapter's move delivered (done or late, something at the Wall): the chapter done in the save of
-- everybody who shares the pay (PlayerData.markStory "done:<chapter>": the next chapter opens; real saves only, as
-- every story flag).
local function chapterDone(s: Session, phase: string, delivered: number, present: { Player })
	local chapter = MoveStory.forContract(s.contract.id)
	if not chapter or delivered <= 0 or (phase ~= "done" and phase ~= "late") then
		return
	end
	for _, player in present do
		pcall(PlayerData.markStory, player, MoveStory.doneKey(chapter.id))
	end
end

local HOW_TEXT: { [string]: string } = {
	done = "Delivered to the Wall",
	late = `Time's up: what reached the Wall late counts at {math.floor(T.Pay.LateShare * 100 + 0.5)}% of its pay`,
	cancelled = "Called off",
	failed = "Lost",
}

-- The move ends with `event` (deliver, timeout, cancel, lose): the pay, the XP, the cards; `why` for the card.
local function finish(s: Session, event: string, why: string?)
	if s.ended then
		return
	end
	local phase = Rules.advance(s.move.phase, event)
	if not phase then
		return
	end
	s.move.phase = phase
	s.ended = true -- (7.0 review: ended first; the pay and the story in a pcall: the cleanup always runs, the slot frees)
	local paid, err = pcall(function()
		payOut(s, phase, why)
	end)
	if not paid then
		warn(`[Moving] {s.contract.id}: the end's pay failed: {err}`)
		for _, member in everyone(s) do
			remote:FireClient(member, "state", nil)
		end
	end
	cleanup(s)
end

-- The end's pay (finish's, in a pcall): the things whose model went never count, the crew near the truck (or near
-- the owner without one) shares the pay, the XP, the cards, Marge's debrief, the analytics.
payOut = function(s: Session, phase: string, why: string?)
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local item = s.items[spot]
		if (thing.state == "truck" or thing.state == "carried") and (not item or not item.model.Parent) then
			thing.state, thing.carrier, thing.helper, thing.place = "ground", nil, nil, nil
		end
	end
	local result = Rules.result(s.move, phase, now())
	-- the crew near the truck (or near the owner without one) shares the pay
	local truck = truckOk(s)
	local _, _, ownerRoot = bodyOf(s.owner)
	local center = if truck then truck.chassis.Position elseif ownerRoot then ownerRoot.Position else nil
	local present: { Player } = { s.owner }
	for _, member in everyone(s) do
		if member == s.owner then
			continue
		end
		local _, _, root = bodyOf(member)
		if root and center and (root.Position - center).Magnitude <= T.Present then
			table.insert(present, member)
		end
	end
	local ownerPay, share = 0, 0
	if result.total > 0 then
		ownerPay, share = Economy.crewSplit(result.total, #present - 1)
	end
	local c = Rules.counts(s.move)
	for _, member in everyone(s) do
		local paid = if member == s.owner then ownerPay elseif table.find(present, member) then share else 0
		if paid > 0 then
			PlayerData.addMoney(member, paid, "MovePay")
		end
		local xp = if table.find(present, member) then result.xp else 0
		if xp > 0 then
			PlayerData.addXp(member, xp)
		end
		remote:FireClient(member, "result", {
			name = s.contract.name,
			icon = s.contract.icon,
			how = phase,
			howText = why or HOW_TEXT[phase] or phase,
			delivered = result.delivered,
			left = result.left,
			broken = result.broken,
			total = c.total,
			starsOut = result.starsOut,
			starsTotal = c.stars,
			stars = result.stars,
			pay = result.total,
			money = paid,
			xp = xp,
			base = math.floor(result.base + 0.5),
			starBonus = math.floor(result.starBonus + 0.5),
			timeBonus = math.floor(result.timeBonus + 0.5),
			fine = math.floor(result.fine + 0.5),
			crew = #present,
			trips = s.move.trips or 0, -- 7.x van moves
		})
		remote:FireClient(member, "state", nil)
	end
	storyText(s, phase, result.stars) -- MoveStory hook: Marge's debrief at the end
	chapterDone(s, phase, result.delivered, present) -- 7.x farm move: the chapter done for the crew present
	if phase == "done" or phase == "late" then
		local owner = s.owner
		PlayerData.track("event", owner, "MoveDone", result.stars, s.contract.id, if #present > 1 then "crew" else "solo")
	end
end

-- ── Starting ───────────────────────────────────────────────────────────────

local function freeSlot(): number?
	for index = 1, T.Slots do
		if not slots[index] then
			return index
		end
	end
	return nil
end

-- Why this player can't start a move now (nil: they can).
local function cantStart(owner: Player): string?
	if sessionOf(owner) then
		return "You are on a move already."
	end
	local leader = Crew.ownerOf(owner)
	if leader then
		return `You are in {leader.DisplayName}'s crew: they take the contract (or leave the crew).`
	end
	if jobs and jobs.active(owner) then
		return "Finish or cancel your job first."
	end
	if not artNow() then
		return "Moving is not ready in this place yet (the house art is missing)."
	end
	if not freeSlot() then
		return "Every moving crew is out right now: try again in a minute."
	end
	return nil
end

-- 7.0 review: a contract's house plan and its card's facts, made once (shared/HouseLayout.luau's plan is the same for
-- its seed every time and takes tens of ms): the board's card and every START of it use them (read only).
type Facts = { plan: any, defs: { [string]: Rules.ItemDef }, spots: { Rules.Spot }, stars: { string }, count: number, estimate: number }

local function factsOf(contract: Contract, a: Art): Facts?
	local known = contractFacts[contract.id]
	if known then
		return known
	end
	local ok, plan = pcall(function(): any
		return a.layout.plan(contract.seed, contract.kind)
	end)
	if not ok or type(plan) ~= "table" then
		warn(`[Moving] the plan of {contract.id} failed: {plan}`)
		return nil
	end
	local defs = defsOf(a)
	local spots = spotsOf(plan)
	local stars: { string } = {}
	local count = 0
	for _, spot in spots do
		local def = defs[spot.item]
		if def then
			count += 1
			if spot.star then
				table.insert(stars, `{def.icon} {def.name}`)
			end
		end
	end
	local made: Facts = { plan = plan, defs = defs, spots = spots, stars = stars, count = count, estimate = Rules.estimate(spots, defs, contract.pay) }
	contractFacts[contract.id] = made
	return made
end

-- ── 7.x farm move: the contracts a player may take (shared/MoveStory.luau's chapters, the save's flags) ─────────────

-- The player's story flags (server/PlayerData.luau profile.story: "intro", "done:<chapter>"), empty without a profile.
local function seenOf(player: Player): { [string]: boolean }
	local profile = PlayerData.get(player)
	local story = if profile then (profile :: any).story else nil
	return if type(story) == "table" then story else {}
end

-- Why `player` can't take this contract yet (its chapter's chapters before it not done: "🔒 Finish the PROLOGUE, …"),
-- nil: they can (a contract without a chapter is always open).
local function lockedFor(player: Player, contract: Contract): string?
	local chapter = MoveStory.forContract(contract.id)
	return if chapter then MoveStory.lockText(chapter, seenOf(player)) else nil
end

-- The board's contract for this player: the first open one whose chapter is not done yet, else the last open one.
local function nextContract(player: Player): Contract?
	local seen = seenOf(player)
	local last: Contract? = nil
	for _, contract in T.Contracts do
		if not sites[contract.id] or lockedFor(player, contract) then
			continue
		end
		local chapter = MoveStory.forContract(contract.id)
		if chapter and seen[MoveStory.doneKey(chapter.id)] ~= true then
			return contract
		end
		last = contract
	end
	return last or T.Contracts[1]
end

-- The card's list of contracts (open, or 🔒 and why; the admin's all open).
local function contractList(player: Player, admin: boolean): { { [string]: any } }
	local list = {}
	for _, contract in T.Contracts do
		local why = if admin then nil else lockedFor(player, contract)
		local chapter = MoveStory.forContract(contract.id)
		table.insert(list, {
			id = contract.id,
			name = contract.name,
			icon = contract.icon,
			client = contract.client,
			chapter = if chapter then chapter.id else nil,
			open = why == nil and sites[contract.id] ~= nil,
			why = why,
		})
	end
	return list
end

-- 7.x van moves: the name of the car a move of this player goes with (theirs; the ZDC Van when the save has none).
local function vanName(player: Player): string
	local profile = PlayerData.get(player)
	local def = Economy.findCar(if profile and type((profile :: any).car) == "string" then (profile :: any).car else T.Van)
	return if def then def.name else "ZDC Van"
end

-- The contract card (the board, the admin): the house, its ★ things, the pay, the time; arms START.
-- 7.x farm move: `contractId` nil: the board's next contract for the player; the card lists every contract (open or
-- 🔒) and a locked one's START waits (busy: why).
function Moving.openCard(player: Player, contractId: string?, admin: boolean)
	local contract = contractById(contractId) or nextContract(player)
	local a = artNow()
	if not contract or not a then
		say(player, "Moving is not ready in this place yet (the house art is missing).")
		return
	end
	local known = factsOf(contract, a)
	if not known then
		say(player, "Moving is not ready in this place yet (the house plan failed).")
		return
	end
	local starNames, count = known.stars, known.count
	local site = sites[contract.id]
	local card: { [string]: any } = {
		id = contract.id,
		name = contract.name,
		client = contract.client,
		icon = contract.icon,
		blurb = contract.blurb,
		address = if site then site.home.address else "",
		stars = starNames,
		items = count,
		estimate = known.estimate,
		time = contract.time or T.Time, -- (7.x farm move: the contract's own clock)
		hordeAt = contract.hordeAt or T.HordeAt,
		truck = vanName(player), -- (7.x van moves: your own van)
		crew = #Crew.members(player),
		busy = cantStart(player) or (if admin then nil else lockedFor(player, contract)),
		contracts = contractList(player, admin), -- 7.x farm move: the board's contracts
	}
	armed[player] = { at = now(), admin = admin, card = card } -- (7.0 planning: the lobby shows this card)
	remote:FireClient(player, "contract", card)
end

-- `roles` (7.0 planning): the lobby's, by user id (nil: the admin's start, everybody gets a free role).
local function startMove(owner: Player, contractId: any, admin: boolean, roles: { [number]: string }?): string?
	local contract = contractById(contractId)
	local site = contract and sites[contract.id]
	if not contract or not site then
		return "No such moving contract."
	end
	local busy = cantStart(owner)
	if busy then
		return busy
	end
	local card = armed[owner]
	if not admin then
		local _, _, root = bodyOf(owner)
		local board = boardPart
		if not card or now() - card.at > T.CardFor then
			return "Open the contract at the depot's board first."
		end
		if not card.admin and (not root or not board or flat(root.Position, board.Position) > T.Reach.Board + 12) then
			return "Take the contract at the depot's board (ZDC Moving)."
		end
	end
	armed[owner] = nil
	local a = artNow() :: Art
	local slot = freeSlot() :: number
	local known = factsOf(contract, a)
	if not known then
		return "The house could not be planned: try again."
	end
	local plan = known.plan
	local origin: CFrame = a.interior.slot(slot)
	local built, interior, models = pcall(function(): (Model, { [number]: Model })
		return a.interior.build(plan, origin)
	end)
	if not built or typeof(interior) ~= "Instance" then
		warn(`[Moving] the interior of {contract.id} failed: {interior}`)
		return "The house could not be built: try again."
	end
	if not (interior :: Model).Parent then
		(interior :: Model).Parent = folder or workspace -- (server/HouseInterior.luau builds it unparented)
	end
	-- 7.x van moves: the owner's own van (out already, else right next to them, they in the driver's seat); a job's or a
	-- rental's lent car is not theirs: their own comes instead
	local truck = Vehicles.get(owner)
	if not truck or truck.wrecked or truck.lent or truck.rental then
		local err = Vehicles.placeNear(owner, nil)
		truck = Vehicles.get(owner)
		if err or not truck then
			pcall(function()
				a.interior.destroy(interior)
			end)
			return err or "Your van could not come: try again."
		end
	end
	nextId += 1
	local s: Session = {
		id = nextId,
		owner = owner,
		contract = contract,
		site = site,
		move = Rules.newMove(known.spots, known.defs, rulesBed(truck), now(), contract.time or T.Time, contract.hordeAt, contract.pay),
		plan = plan,
		origin = origin,
		slot = slot,
		interior = interior :: Model,
		items = {},
		exit = nil,
		truck = truck,
		load = nil,
		unload = nil,
		horde = {},
		roam = {},
		nextRoam = 0,
		bursts = 0,
		nextBurst = 0,
		members = {},
		inside = {},
		dirty = true,
		sentAt = 0,
		ended = false,
		emptyWarned = 0,
		team = newTeam(), -- 7.0 planning
		late = false,
		ways = {}, -- 7.x farm move
		lostAt = nil, -- 7.x van moves
	}
	sessions[owner] = s
	slots[slot] = s
	for spot, model in (models :: { [number]: Model }) do
		if typeof(model) == "Instance" and model:IsA("Model") then
			setupItem(s, spot, model)
		end
	end
	-- "Leave house" by the front door inside; 7.x farm move: a Leave by every way out (a farm's barn doors too), each
	-- to its own door outside, and where you come in by each (shared/HouseLayout.luau exitsOf / entries)
	local layout = a.layout
	local exits: { Vector3 } = if type(layout.exitsOf) == "function" then layout.exitsOf(plan) else { plan.exit :: Vector3 }
	local entries: { CFrame } = if type(layout.entries) == "function" then layout.entries(plan) else { plan.entry :: CFrame }
	for index, at in exits do
		local door = site.doors[index]
		if not door then
			continue -- (an exit without a door outside: nobody goes through it)
		end
		local width = if index == 1 then 4 else math.min(door.width, 10)
		local exitAt = origin * CFrame.new(at)
		local part = invisible(if index == 1 then "LeaveDoor" else `LeaveDoor{index}`, Vector3.new(width, 6, 1), exitAt + Vector3.new(0, 3.5, 0), folder or workspace)
		local leave = newPrompt(part, if index == 1 then "Leave house" else `Leave by the {door.name}`, `{contract.icon} {contract.name}`, Enum.KeyCode.E, 0, T.Reach.Exit + (width - 4) / 2)
		leave.Triggered:Connect(function(player: Player)
			onLeave(player, s, index)
		end)
		if index == 1 then
			s.exit = part
		end
		table.insert(s.ways, { exit = index, part = part, inside = exitAt.Position, entry = origin * (entries[index] or plan.entry), door = door })
	end
	truckPrompts(s)
	tellAll(s, `🚐 Move started: {contract.name}, {site.home.address}. Drive your van there (GPS), carry the things out, load them and bring them to the Wall at the depot: as many trips as it takes, then FINISH. {Rules.counts(s.move).stars} ★ things are a must!`)
	storyText(s) -- MoveStory hook: Marge's text at the start
	teamSetup(s, roles) -- 7.0 planning: the roles, the house's Enter prompt
	return nil
end

-- ── The clock ──────────────────────────────────────────────────────────────

local function startHorde(s: Session)
	local phase = Rules.advance(s.move.phase, "horde")
	if not phase then
		return
	end
	s.move.phase = phase
	s.bursts = T.Horde.Bursts
	s.nextBurst = 0
	tellAll(s, `🧟 A HORDE is coming to {s.contract.name}! Load what you can and drive to the Wall!`)
	s.dirty = true
end

local function hordeBurst(s: Session, clock: number)
	if s.bursts <= 0 or clock < s.nextBurst then
		return
	end
	s.bursts -= 1
	s.nextBurst = clock + T.Horde.Every
	local doors = s.site.doors -- (7.x farm move: the bursts take turns at the farm's doors)
	local door = doors[s.bursts % #doors + 1].door
	for _ = 1, math.ceil(T.Horde.Count / math.max(1, T.Horde.Bursts)) do
		local spot = Zombies.findSpot(door, nil, T.Horde.Near, T.Horde.Far)
		local z = if spot then Zombies.spawn(Zombies.pickKind(T.Horde.Kinds, spot, s.owner), spot, s.owner) else nil
		if z then
			Zombies.march(z, door, "move")
			table.insert(s.horde, z)
		end
	end
end

-- A few zombies roam round the house while somebody of the crew is outside near it.
local function keepRoam(s: Session, clock: number)
	if clock < s.nextRoam then
		return
	end
	s.nextRoam = clock + T.Roam.Every
	for index = #s.roam, 1, -1 do
		local z = s.roam[index]
		if z.dead or not z.model.Parent then
			table.remove(s.roam, index)
		end
	end
	local near = false
	for member in s.members do
		local _, _, root = bodyOf(member)
		if root and not s.inside[member] and flat(root.Position, s.site.door) <= T.Roam.Range then
			near = true
		end
	end
	if not near then
		return
	end
	for _ = 1, T.Roam.Count - #s.roam do
		local spot = Zombies.findSpot(s.site.door, nil, T.Roam.Near, T.Roam.Far)
		local z = if spot then Zombies.spawn(Zombies.pickKind(T.Roam.Kinds, spot, s.owner), spot, s.owner, false, false, true) else nil
		if z then
			table.insert(s.roam, z)
		end
	end
end

-- Who is on the move now (the owner and their crew): joiners hear about it, leavers drop what they hold and come out.
local function syncMembers(s: Session)
	local current: { [Player]: boolean } = {}
	for _, player in membersOf(s) do
		current[player] = true
		if player:GetAttribute("MoveWith") ~= s.owner.UserId then
			player:SetAttribute("MoveWith", s.owner.UserId)
		end
		if not s.members[player] then
			s.dirty = true
			if player ~= s.owner then
				say(player, `🚚 You are on {s.owner.DisplayName}'s move: {s.contract.name}. Help carry the things out to the truck.`)
			end
		end
	end
	for player in s.members do
		if not current[player] then
			release(s, player, "left")
			if player.Parent then
				if player:GetAttribute("MoveWith") == s.owner.UserId then
					player:SetAttribute("MoveWith", nil)
				end
				remote:FireClient(player, "state", nil)
				say(player, `You are off {s.owner.DisplayName}'s move.`)
				if s.inside[player] then
					travel(player, outsideFor(s, player), s, false) -- (7.x farm move: the nearest door)
				end
			end
		end
	end
	s.members = current
	teamSync(s) -- 7.0 planning: a newcomer's role, a leaver's gone
end

-- The carried things: a helper too far for Grace s, a carrier faster than the carry (a teleport), a fall's top.
local function watchCarried(s: Session, clock: number)
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local item = s.items[spot]
		if thing.state ~= "carried" or not item then
			continue
		end
		local carrier = playerById(thing.carrier)
		local character, _, root = bodyOrNil(carrier)
		if not carrier or not character or not root then
			continue
		end
		local holder: Player = carrier
		climbStep(s, spot, holder, root, clock) -- 7.0 planning: slower up stairs and slopes (not a Mover)
		if item.fallFrom then
			item.fallFrom = math.max(item.fallFrom, root.Position.Y)
		end
		if not traveling[holder] then
			if paceBroken(s, item, thing, holder, character, root, clock) then
				release(s, holder, "pace")
				continue
			end
			item.lastAt, item.lastTime = root.Position, clock
		end
		local helper = playerById(thing.helper)
		if helper then
			local _, _, helperRoot = bodyOf(helper)
			local reach = math.max(thing.size.X, thing.size.Z) / 2 + T.Tether
			if helperRoot and flat(helperRoot.Position, item.root.Position) > reach and not traveling[helper] then
				item.apartSince = item.apartSince or clock
				if clock - (item.apartSince :: number) > T.Grace then
					release(s, holder, "apart")
				end
			else
				item.apartSince = nil
			end
		end
	end
end

-- ── 7.x van moves: the trips, FINISH, a van lost ─────────────────────────────────────────────────────────────────

-- The van at the Wall with a load: everything in it (and on its hitch) is delivered (MovingRules.deliver: a trip; its
-- models unloaded, gone), the soldier welcomes it, the crew hears the tally. The move goes on (an empty van comes back
-- for more), except late (the grace's delivery ends it) or with nothing left to bring (everything delivered or lost).
local function deliverTrip(s: Session, clock: number)
	for _, spot in s.move.order do -- (7.0 review: a thing whose model went never counts: lost, not delivered)
		local thing = s.move.things[spot]
		local item = s.items[spot]
		if thing.state == "truck" and (not item or not item.model.Parent) then
			thing.state, thing.condition = "lost", 0
		end
	end
	local spots = Rules.deliver(s.move, now())
	for _, spot in spots do
		local item = s.items[spot]
		if item then
			for _, hook in item.hooks do
				hook:Disconnect()
			end
			table.clear(item.hooks)
			unweld(item)
			item.model:Destroy()
		end
	end
	if #spots == 0 then
		return
	end
	s.emptyWarned = clock
	s.dirty = true
	pcall(MoveGreeters.delivered, s) -- (7.0 greeters: the soldier's welcome at the Wall, every trip)
	local c = Rules.counts(s.move)
	local trips = s.move.trips or 1
	if s.late then
		finish(s, "timeout") -- (late: what came now pays LateShare)
		return
	elseif c.delivered + c.lost >= c.total then
		finish(s, "deliver", "Everything delivered to the Wall")
		return
	end
	tellAll(s, `🧱 Trip {trips} at the Wall: {#spots} delivered · {c.delivered}/{c.total} in all · ★ {c.starsDelivered}/{c.stars}. Back for more, or FINISH.`)
end

-- 0:00 and the grace over (or nothing in the van to bring): the end, paid for what was delivered (nothing: lost).
local function timeUp(s: Session)
	if Rules.counts(s.move).delivered > 0 then
		finish(s, "timeout", "Time's up: the Wall paid what reached it")
	else
		finish(s, "lose", "Time's up: nothing reached the Wall")
	end
end

-- The owner's FINISH (the Moving remote's "finish": client/MovingHud.luau asks twice): the end, paid for every trip;
-- what is still in the van stays behind. Not before a first delivery (GIVE UP calls it off).
local function finishMove(player: Player)
	local s = sessions[player]
	if not s or s.ended then
		return
	end
	local c = Rules.counts(s.move)
	if c.delivered == 0 then
		say(player, "Nothing delivered yet: bring a load to the Wall first (or GIVE UP in the move's list, O).")
		return
	end
	finish(s, if s.late then "timeout" else "deliver", if c.out > 0 then "Finished: what was still in the van stayed behind" else "Finished: everything at the Wall is paid")
end

-- The van lost mid-move (wrecked, gone, not the owner's car any more): what was in it is lost (condition 0, its models
-- go), the move goes on without a van; the owner's CAR brings one again after VanAgain s (the wrappers in wireHooks)
-- and the move takes it over (an empty bed, the prompts on it).
local function keepVan(s: Session, t: number)
	local truck = s.truck
	if truck and truckOk(s) then
		return
	elseif truck then
		local lost = Rules.lose(s.move)
		for _, spot in lost do
			local item = s.items[spot]
			if item then
				for _, hook in item.hooks do
					hook:Disconnect()
				end
				table.clear(item.hooks)
				item.model:Destroy()
			end
		end
		for _, prompt in { s.load, s.unload } do
			if prompt then
				prompt:Destroy()
			end
		end
		s.load, s.unload = nil, nil
		releaseBack(truck)
		s.truck, s.lostAt, s.dirty = nil, t, true
		local why = if truck.wrecked then "wrecked" else "gone"
		tellAll(s, `💥 The van is {why}{if #lost > 0 then `: the {#lost} things in it are lost` else ""}. The move goes on: CAR brings it back in {T.VanAgain} s.`)
		return
	end
	local car = Vehicles.get(s.owner)
	if car and not car.wrecked and car.model.Parent and not car.lent and not car.rental then
		s.truck, s.lostAt, s.dirty = car, nil, true
		Rules.setBed(s.move, rulesBed(car))
		truckPrompts(s)
		tellAll(s, `🚐 {s.owner.DisplayName}'s van is back: carry on.`)
	end
end

local function tick(s: Session)
	local t = now()
	local clock = os.clock()
	local due = Rules.due(s.move, t)
	if due == "timeout" then
		-- 7.0 review: late: the load still pays LateShare if the truck reaches the Wall within LateGrace s, else it is lost
		-- (7.x van moves: what is in the van then; an empty van ends the move at once, the trips before paid in full)
		if t >= s.move.endsAt + T.LateGrace or (not s.late and Rules.counts(s.move).out == 0) then
			timeUp(s)
			return
		elseif not s.late then
			s.late = true
			s.dirty = true
			tellAll(s, `⏱ Time's up! Drive what's in the van to the Wall within {math.floor(T.LateGrace / 60 + 0.5)} minutes: it pays {math.floor(T.Pay.LateShare * 100 + 0.5)}%.`)
		end
	elseif due == "horde" then
		startHorde(s)
	end
	keepVan(s, t) -- 7.x van moves: a van lost mid-move loses its load (the move goes on), the owner's next one is taken
	syncMembers(s)
	watchCarried(s, clock)
	keepRoam(s, clock)
	teamTick(s) -- 7.0 planning: the barricades
	if s.move.phase == "horde" then
		hordeBurst(s, clock)
	end
	MoveHelper.sync(s, Moving) -- 7.0: Danny joins a crew of one, goes when it grows (his own loop walks him)
	MoveGreeters.sync(s) -- 7.0 greeters: the client on the porch greets the crew and reacts to the move
	refreshTruck(s)
	local truck = truckOk(s) -- (7.x van moves: none while it is lost)
	if truck and flat(truck.chassis.Position, dropOffAt()) <= T.DropRadius then
		if Rules.counts(s.move).out > 0 then
			deliverTrip(s, clock) -- 7.x van moves: a trip: its load delivered, the move goes on (late: then it ends)
			if s.ended then
				return
			end
		elseif clock - s.emptyWarned > 15 then
			s.emptyWarned = clock
			say(s.owner, "The van is empty: load the things at the house first.")
		end
	end
	if (s.dirty and clock - s.sentAt > 0.25) or clock - s.sentAt > 5 then
		send(s)
	end
end

-- ── The admin ──────────────────────────────────────────────────────────────

function Moving.admin(player: Player, arg: any): string
	local s = sessions[player]
	-- (7.x farm move: "farm…" is Walt's Farm's: farmcard, farm (start), farmgo; the rest Marge's House)
	local contract = if type(arg) == "string" and string.sub(arg, 1, 4) == "farm" then contractById("walt") or T.Contracts[1] else T.Contracts[1]
	if arg == "card" or arg == "farmcard" then
		Moving.openCard(player, if arg == "card" then nil else contract.id, true)
		return `ADMIN: the moving contract card is open (every contract open for the admin).`
	elseif arg == "start" or arg == "farm" then
		MoveLobby.close(player, nil) -- (7.0 planning: the admin's start skips the planning)
		local err = startMove(player, contract.id, true)
		return if err then `ADMIN: {err}` else `ADMIN: {contract.name} started with your van.`
	elseif arg == "house" or arg == "farmgo" then
		local site = sites[contract.id]
		local character = player.Character
		if not site or not character then
			return "ADMIN: no house to go to."
		end
		local car = Vehicles.get(player)
		local seatedIn = Vehicles.seatedIn(player)
		if car and seatedIn == car then
			local door = site.doors[1] -- (its kerb, along the road; a farm's van spot by its door)
			local spot = Vector3.new(door.park.X, Vehicles.groundY(door.park.X, door.park.Z) + 3, door.park.Z)
			car.model:PivotTo(CFrame.lookAt(spot, spot + door.heading))
		else
			pcall(function()
				player:RequestStreamAroundAsync(site.outside.Position, 4)
			end)
			character:PivotTo(site.outside + Vector3.new(0, 3, 0))
		end
		return `ADMIN: at {site.contract.name}.`
	end
	if not s then
		return "ADMIN: you are not running a move (START one first)."
	end
	if arg == "horde" then
		if s.move.phase == "running" then
			s.move.endsAt = math.min(s.move.endsAt, now() + (s.move.hordeAt or T.HordeAt))
			startHorde(s)
		end
		return "ADMIN: the horde comes now."
	elseif arg == "time" then
		s.move.endsAt = now() + 60
		s.dirty = true
		return "ADMIN: one minute left."
	elseif arg == "trip" then
		deliverTrip(s, os.clock()) -- (7.x van moves: what is in the van delivered now, as at the Wall)
		return "ADMIN: the van's load delivered (a trip)."
	elseif arg == "deliver" then
		deliverTrip(s, os.clock())
		finish(s, if s.late then "timeout" else "deliver") -- (7.0 review: past 0:00: late)
		return "ADMIN: delivered with what is in the van, and finished."
	elseif arg == "end" then
		finish(s, "cancel", "Called off by the admin")
		return "ADMIN: the move is called off."
	end
	return "ADMIN: card | start | house | farmcard | farm | farmgo | horde | time | trip | deliver | end."
end

-- ── 7.0 grip: a slip, the wear (the Moving remote's "slip" and "grip"; the hook: setHands' gripHands) ─────────────────
-- ("slip", spot): the sender's grip bar ran out: what they hold goes down from its carrier's hands (a pair thing whole,
-- both ends: either carrier's slip drops it) and takes CarryGrip.slipDamage (fragile: more). ("grip", spot, quality,
-- steady) about once a Config.CarryGrip.Report s: quality, the share of the time the load was outside the grip box,
-- wears the thing a little (CarryGrip.wear, capped a second; a report sooner than Server.Every after the last one is
-- dropped; a client that never reports wears nothing); a steady report (at most Server.SteadyOutside outside) makes the
-- carry's walk × CarryGrip.speedFactor until one that is not (setHands asks gripHands). Only for what the sender holds
-- now with a bar (its spot, their grip record on this move), never during a door's fade; Danny never slips.
local function gripRequest(player: Player, action: string, spotArg: any, quality: any, steady: any)
	local s = sessionOf(player)
	if not s or s.ended or traveling[player] or type(spotArg) ~= "number" then
		return
	end
	local spot = Rules.holding(s.move, player.UserId)
	local thing = if spot then s.move.things[spot] else nil
	local item = if spot then s.items[spot] else nil
	local hold = grips[player]
	if spot ~= spotArg or not thing or not item or thing.state ~= "carried" or not hold or hold.session ~= s.id or hold.spot ~= spot or hold.kind == "" then
		return -- (not what the sender holds, or no bar on it)
	end
	local G = Config.CarryGrip
	if action == "slip" then
		local carrier = playerById(thing.carrier)
		if not carrier then
			return
		end
		local helper = playerById(thing.helper)
		release(s, carrier, "slip")
		hurtThing(s, thing.spot, CarryGrip.slipDamage(thing.fragile))
		local left = math.floor(thing.condition * 100 + 0.5)
		local holders: { Player? } = { carrier, helper }
		for _, who in holders do
			if who and who == player then
				say(who, `💥 It slipped! The {thing.name} fell: {left}% left. Hold to keep it steady.`)
			elseif who then
				say(who, `💥 {player.DisplayName} lost their grip: the {thing.name} fell ({left}% left).`)
			end
		end
		return
	end
	local t = now()
	if hold.last > 0 and t - hold.last < G.Server.Every then
		return -- (about one a second)
	end
	local dt = if hold.last > 0 then t - hold.last else G.Report
	hold.last = t
	local wear = CarryGrip.wear(quality, thing.fragile, dt)
	if wear > 0 then
		hurtThing(s, thing.spot, wear)
	end
	local outside = if type(quality) == "number" and quality == quality then quality else 1
	local nowSteady = steady == true and outside <= G.Server.SteadyOutside
	if nowSteady ~= hold.steady then
		hold.steady = nowSteady
		setHands(s, item) -- (the walk: × CarryGrip.speedFactor, or back)
	end
end
-- ── (end of the grip block) ──────────────────────────────────────────────────────────────────────────────────────────

-- ── Start ──────────────────────────────────────────────────────────────────

local function onPutDown(player: Player)
	local s = sessionOf(player)
	if s and Rules.holding(s.move, player.UserId) then
		release(s, player, "put")
	end
end

-- 7.x farm move: ("card", id) from an open card's list of contracts: that contract's card, while the card opened at the
-- board (or the admin's) is still good (CardFor s, near the board).
local function cardRequest(player: Player, contractId: any)
	local armedCard = armed[player]
	local contract = contractById(contractId)
	if not armedCard or not contract or now() - armedCard.at > T.CardFor then
		return
	end
	local _, _, root = bodyOf(player)
	local board = boardPart
	if not armedCard.admin and (not root or not board or flat(root.Position, board.Position) > T.Reach.Board + 12) then
		return
	end
	Moving.openCard(player, contract.id, armedCard.admin)
end

-- 7.0 planning: START on the contract card opens the planning lobby (server/MoveLobby.luau) on that card, checked as
-- START was (the card opened a moment ago at the board, free to start); its LAUNCH starts the move (Moving.start wires
-- MoveLobby.onLaunch: startMove with the lobby's roles).
local function planMove(owner: Player, contractId: any): string?
	local contract = contractById(contractId)
	if not contract or not sites[contract.id] then
		return "No such moving contract."
	end
	local busy = cantStart(owner)
	if busy then
		return busy
	end
	local armedCard = armed[owner]
	local locked = if armedCard and armedCard.admin then nil else lockedFor(owner, contract) -- (7.x farm move)
	if locked then
		return locked
	end
	local card = if armedCard then armedCard.card else nil
	local _, _, root = bodyOf(owner)
	local board = boardPart
	if not armedCard or not card or card.id ~= contract.id or now() - armedCard.at > T.CardFor then
		return "Open the contract at the depot's board first."
	end
	if not armedCard.admin and (not root or not board or flat(root.Position, board.Position) > T.Reach.Board + 12) then
		return "Take the contract at the depot's board (ZDC Moving)."
	end
	armed[owner] = nil
	local summary = table.clone(card)
	summary.busy = nil
	summary.contracts = nil -- (7.x farm move: the card's list stays on the card)
	local bed = bedOf(Vehicles.get(owner)) -- (7.x van moves: your van's bay)
	summary.bed = { bed.Width, bed.Length }
	return MoveLobby.open(owner, summary)
end

local function onRequest(player: Player, action: any, arg: any, arg2: any, arg3: any)
	if not Net.limit(player, "Moving", Config.Robust.Limits.Moving) then
		return
	end
	if action == "slip" or action == "grip" then -- 7.0 grip: the grip bar ran out / its report (the grip block)
		gripRequest(player, action, arg, arg2, arg3)
	elseif action == "start" then
		local err = planMove(player, arg) -- 7.0 planning: the lobby first (its LAUNCH starts the move)
		if err then
			say(player, err)
		end
	elseif action == "role" or action == "call" or action == "barricade" then -- 7.0 planning: the roles on a move
		local s = sessionOf(player)
		if s then
			teamRequest(s, player, action, arg)
		end
	elseif action == "giveup" then
		local s = sessions[player]
		if s then
			finish(s, "cancel", "You called it off")
		end
	elseif action == "state" then
		local s = sessionOf(player)
		if s then
			remote:FireClient(player, "state", viewFor(s, player))
		end
	elseif action == "card" then -- 7.x farm move: another contract's card from the open card's list
		cardRequest(player, arg)
	elseif action == "finish" then -- 7.x van moves: the owner's FINISH (paid for every trip)
		finishMove(player)
	end
end

-- 7.0 review: the owner's truck is out on a live move (nothing else of theirs may take its place).
local TRUCK_OUT = "Your van is out on a move: finish the move first."
local function truckOut(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and not s.ended and truckOk(s) ~= nil
end

-- 7.x van moves: the van was lost on a move a moment ago: CAR brings it again after VanAgain s (the wait's words).
local function vanWait(player: Player): string?
	local s = sessions[player]
	local lost = if s and not s.ended and s.truck == nil then s.lostAt else nil
	if lost and now() - lost < T.VanAgain then
		return `Your van comes back in {math.ceil(T.VanAgain - (now() - lost))} s.`
	end
	return nil
end

-- Why `player` can't take a job, a mission or a rental now (server/Jobs.luau startJob, server/Rental.luau): on a
-- move (its owner or its crew), nil: they can.
function Moving.busy(player: Player): string?
	if sessionOf(player) then
		return "You are on a move: finish it first (or GIVE UP in the move's list, Tab)."
	end
	return nil
end

local function wireHooks()
	jobs = require(script.Parent.Jobs)
	-- a crew on a move is "hunted" like a job's: no ordinary roamers round them (the move brings its own), none inside
	local hunts = Zombies.hunts
	Zombies.hunts = function(player: Player): boolean
		return hunts(player) or sessionOf(player) ~= nil
	end
	-- the truck's knocks knock its load
	local function truckHit(player: Player, amount: number)
		local s = sessions[player]
		if not s or s.ended or type(amount) ~= "number" then
			return
		end
		for _, spot in s.move.order do
			local thing = s.move.things[spot]
			if thing.state == "truck" then
				hurtThing(s, spot, Rules.truckDamage(amount, thing.fragile))
			end
		end
	end
	local zombieHit = Zombies.onCarDamaged
	Zombies.onCarDamaged = function(player: Player, amount: number)
		zombieHit(player, amount)
		truckHit(player, amount)
	end
	local BanditCars = require(script.Parent.BanditCars)
	local banditHit = BanditCars.onCarDamaged
	BanditCars.onCarDamaged = function(player: Player, amount: number)
		banditHit(player, amount)
		truckHit(player, amount)
	end
	-- the crew opens and closes the truck's back too
	local backAllowed = Vehicles.backAllowed
	Vehicles.backAllowed = function(player: Player, car: Vehicles.Car): boolean
		if backAllowed(player, car) then
			return true
		end
		local s = sessions[car.owner]
		return s ~= nil and not s.ended and s.truck == car and sessionOf(player) == s
	end
	-- the truck stays while the move runs: CAR does not swap it, a respawn does not take it back
	local returnLent = jobs.returnLent
	jobs.returnLent = function(player: Player): boolean
		local s = sessions[player]
		if s and not s.ended and truckOk(s) then
			return false
		end
		return returnLent(player)
	end
	teamHooks() -- 7.0 planning: the Guard's hits, the Driver's truck
	-- 7.0 review: while your move's truck is out nothing of yours takes its place (each of these would remove it first:
	-- CAR, MY BIKE, the phone's CALL CAR in the truck, a car job, a garage's car, a dealer's; startMove's own placeNear
	-- runs before the session exists, a respawn's giveCar sees the truck and asks nothing)
	local spawn = Vehicles.spawn
	Vehicles.spawn = function(player: Player, force: boolean?, carId: string?): string?
		if truckOut(player) then
			return TRUCK_OUT
		end
		return vanWait(player) or spawn(player, force, carId) -- (7.x van moves: a lost van back after VanAgain s)
	end
	local placeNear = Vehicles.placeNear
	Vehicles.placeNear = function(player: Player, carId: string?): string?
		if truckOut(player) then
			return TRUCK_OUT
		end
		return vanWait(player) or placeNear(player, carId)
	end
	local placeAt = Vehicles.placeAt
	Vehicles.placeAt = function(player: Player, carId: string?, spot: CFrame, seat: boolean?): Vehicles.Car?
		if truckOut(player) then
			say(player, TRUCK_OUT)
			return nil
		end
		return placeAt(player, carId, spot, seat)
	end
	local spawnAt = Vehicles.spawnAt
	Vehicles.spawnAt = function(player: Player, carId: string?, ground: CFrame, seat: boolean, chauffeured: boolean?, rental: boolean?, keep: { Instance }?): Vehicles.Car?
		if truckOut(player) then
			say(player, TRUCK_OUT)
			return nil
		end
		return spawnAt(player, carId, ground, seat, chauffeured, rental, keep)
	end
	-- a move's owner is busy for the crews (no other crew's invitation mid-move: they would be on two moves)
	local hasJob = Crew.hasJob
	Crew.hasJob = function(player: Player): boolean
		local own = sessions[player]
		return hasJob(player) or (own ~= nil and not own.ended)
	end
	local callCar = Vehicles.callCar
	if callCar then
		local call: (Player, string?) -> string? = callCar
		Vehicles.callCar = function(player: Player, carId: string?): string?
			local s = sessions[player]
			if s and not s.ended and truckOk(s) then
				return "Your van is out on a move: finish the move first (or GIVE UP in the move's list, O)."
			end
			return vanWait(player) or call(player, carId)
		end
	end
end

function Moving.start()
	local made = Instance.new("Folder")
	made.Name = "Moves"
	made.Parent = workspace
	folder = made
	for _, contract in T.Contracts do
		local site = buildSite(contract, made)
		if site then
			sites[contract.id] = site
		end
	end
	buildBoard(made)
	buildDropOff(made)
	MoveGreeters.start(boardPart) -- 7.0 greeters: the soldier at the Wall, Marge's word at the kiosk (their own loop)
	wireHooks()
	-- 7.0 planning: the lobby before a move (its LAUNCH starts it with the roles; the quick chat reaches the move's crew)
	MoveLobby.onLaunch = function(owner: Player, contractId: string, roles: { [number]: string }): string?
		-- (7.0 review: the truck comes where you stand: LAUNCH at the depot's board, not at the house)
		local _, _, root = bodyOf(owner)
		local board = boardPart
		if not root or not board or flat(root.Position, board.Position) > T.Reach.Board + 24 then
			return "LAUNCH at the depot's board (ZDC Moving): the truck comes there."
		end
		return startMove(owner, contractId, true, roles)
	end
	MoveLobby.canStart = cantStart
	MoveLobby.moveCrew = function(player: Player): { Player }?
		local s = sessionOf(player)
		return if s then membersOf(s) else nil
	end
	-- (the quick chat's "Need a hand here" on a move calls the depot's helper over: HELP ME)
	MoveLobby.onQuickChat = function(player: Player, index: number)
		local line = MoveRoles.Chat[index]
		if line and line.id == "hand" and sessionOf(player) then
			MoveHelper.order(player, "help")
		end
	end
	MoveLobby.start()
	remote.OnServerEvent:Connect(onRequest)
	Net.get("PutDown").OnServerEvent:Connect(onPutDown)
	Players.PlayerRemoving:Connect(function(player: Player)
		local own = sessions[player]
		if own then
			for _, member in everyone(own) do
				if member ~= player then
					say(member, `The move was called off: {player.DisplayName} left.`)
				end
			end
			finish(own, "cancel", `{player.DisplayName} left the game`)
		end
		for _, session in sessions do
			if session.members[player] then
				release(session, player, "gone")
			end
			session.inside[player] = nil
			session.members[player] = nil
		end
		armed[player] = nil
		traveling[player] = nil
	end)
	-- a new body is never inside (a death inside respawns you at the depot)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			for _, session in sessions do
				session.inside[player] = nil
				session.dirty = true
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	task.spawn(function()
		while true do
			task.wait(T.Tick)
			Moving.step()
		end
	end)
end

-- One tick of every running move (the loop's, every Config.Moving.Tick s; tests/moving_runtime_test.luau calls it).
function Moving.step()
	for _, s in sessions do
		if not s.ended then
			local ok, err = pcall(function()
				tick(s)
			end)
			if not ok then
				warn(`[Moving] {s.contract.id}: {err}`)
			end
		end
	end
end

return Moving
