--!strict
-- MOVES, every one a RUN (9.7; 10.6: only the sandbox is the game): one house emptied by a party, run on the server.
-- server/Runs.luau starts it (the lobby's portals, the admin's Runs group: Moving.startRun) with the host's van parked
-- at the house's curb; the rules are shared/MovingRules.luau's (pure, tests/moving_test.luau), the numbers
-- Config.Moving's, the client's side client/MovingHud.luau (and client/Fade.luau).
--
--   * The houses: shared/SandboxMap.luau's Houses (The Old Farmstead, the big one, and five places of their own), a
--     contract each (SB.contracts, Config.Moving.Sandbox.Houses: its family, address, plan's kind and clock) and a
--     site each (SB.site: its front door's "Enter house" on that house's map door, the part with the attribute
--     SandboxDoor in the model whose SandboxHouse is its id, SB.frontDoor; "Call the van to the door" to its curb; its
--     back door only where it has one, the farmstead's).
--   * The run: Moving.startRun(host, house, difficulty): the house's contract with the host's card's seed for it (kept
--     while nothing came home: SB.seeds, SB.houses, the save's sandboxHouse and sandboxHouseSeed; 8.3 economy: GIVE UP
--     or leaving never rerolls it), its clock RunRules.time of the house's Time × the difficulty's, the plan built far
--     off (server/HouseInterior.luau build at its slot(n), the plan shared/HouseLayout.luau's, the furniture
--     shared/FurnitureLooks.luau's: found by name when first needed, see artNow), the inside's RunDifficulty for the
--     traps, the zombies and the loot (server/Loot.luau tags every piece). The host's party is the crew (server/Runs.luau
--     wraps Crew.members and Crew.ownerOf; the player attribute MoveWith = the host's UserId while you are on it;
--     client/MovingHud.luau shows only the prompts of your own run: the tag MovePrompt with MoveOwner / MoveOnly /
--     MoveSkip). 8.8 no roles: everybody does everything (anybody calls the van to the door once a run, the truck's
--     Load / Take out hold no time).
--   * The door: "Enter house" at the house's front door (one prompt: it takes you into YOUR run's interior; 8.1 walked
--     through, the prompt off) fades out, streams the interior in, moves you (and what you carry, and the other end of a
--     pair thing) to the plan's entry and fades in; out the same way by the door inside (a Leave by every way out:
--     the farmstead's back door too, each to its own door outside).
--   * The things: "Pick up" (hand, both) / "Lift" (pair) on every thing, "Help lift" on a pair thing somebody lifted,
--     "Put down" / "Let go" (G, or the touch PUT DOWN: the PutDown remote) for whoever holds it. In the hands it is
--     welded in front of the chest (the character attributes Carrying, CarryCount, CarryHands, CarryAt, CarrySize,
--     CarrySpeed and MoveCarry = the spot: client/CameraRig.luau walks at CarrySpeed with MoveCarry, client/ArmPose.luau
--     reaches for it); a pair thing alone is dragged low in front, slowly. Its condition drops when its carrier falls
--     from a height, is bitten, dies (it drops), and in the truck when the truck is hit; its helper too far from it for
--     Grace s, it goes down. Moving faster than the carry allows (a teleport) puts it down where its carrier was. Up
--     stairs or a slope a thing in both hands or two is carried slower (climbStep). 8.1 carrying in two (the owner:
--     "when I turn around he teleports … we must walk, like, backwards and slowly"): its carrier (the leader) gets
--     PairTurn (client/PairSteer.luau turns their heading slowly, a way behind them walked backwards:
--     shared/PairCarry.luau), its helper is held at its far end by the server like Danny (server/PairHold.luau; the
--     tether waits for its ease back too), both at the pair's walk. 8.6 (the owner: "he teleports from side to side",
--     "the table seems to float between them"): carried in two it lies along the carry, low (holdOffset: a piece wider
--     than deep turned a quarter round, its grips at the hands: MovingRules.pairLift), the leader at one end of its
--     length and the other at the far one; the leader's hands on its near end's edge (CarryAt / CarrySize:
--     Config.MoveHelper.Edge). Danny's lift on your call goes up at once once he is there (Moving.helperCalled:
--     Config.MoveHelper.CallCheck, no lift check after the wait, the steady walk).
--   * The truck: "Load" (E) at its open back puts what you hold onto the bed (MovingRules' packer: the best scored
--     place, turned 90°, resting on uneven tops, a both / pair piece lying on its side when it has no place standing,
--     the bed repacked biggest first when it has no room as it is: the moved models welded anew; "No room" else, and
--     the prompt says "won't fit" before), welded in the box where it is seen through the open back; "Take out" (Z,
--     Unload) takes the last one in that nothing rests on back into your hands: beside the door on its own spot, and
--     only while nobody at the back carries a thing. The Sprinter's walk-in bay (Beds' WalkIn): a carrier inside it
--     Loads there, the bay's own Load prompt. The back is the host's and the party's (Vehicles.backAllowed, BackCrew);
--     its own prompt waits while Load shows (one E at a time). 8.6 (the owner's screenshot: "Load" and "Put down" drawn
--     on top of each other): while Load is up for a carrier at the back, their piece's G prompts draw nothing (Style
--     Custom: G still puts it down).
--   * The end: the host's FINISH (the Moving remote's "finish", the truck's prompt: server/Runs.luau), the party's vote,
--     the clock, GIVE UP, the host leaving: everything in the truck goes home at once (SB.unloadAll), each piece into
--     the stock of whoever loaded it last (server/Collection.luau Collection.add: item, variant, condition, name,
--     rarity; Danny's loads his boss's), no pay, no XP (the warehouse earns); Moving.onRunEnd's facts give server/Runs.luau
--     its results card. A van lost mid-run (wrecked, gone) loses what is in it (condition 0), the run goes on without it
--     (a car placed for its host after VanAgain s is taken over: its Load / Take out prompts made again on it). A death
--     mid-run stands the new body by the run's van, else outside the house (Moving.respawnAt, SandboxBoot's spawn).
--   * The clock and the zombies: the run's clock (0:00 ends it: late, the truck's load home); the horde (Config.Moving
--     Horde; Config.Moving.Sandbox.Horde false: none by the clock, the admin's HORDE NOW brings it) marches on the door
--     in bursts; Sandbox.Roam roamers round the house while somebody of the party is outside near it (0 by default);
--     the party is "hunted" (no ordinary roamers come round them). A run's own danger (its traps, its zombies from Hard,
--     the vault) is server/RunDanger.luau's (Moving.onRunStart, Moving.runDrop).
--   * The edges: whoever leaves, dies, sits down or leaves the party drops what they hold where they are (inside: on
--     the floor); somebody inside an interior that goes is brought out to the door; every prompt and request is checked
--     here (who, how far, the state), the remote is rate limited (Config.Robust.Limits.Moving). While a run's truck is
--     out nothing of its host's takes its place (Vehicles.spawn / placeNear / placeAt / spawnAt wrapped), a run's people
--     count as busy (Moving.busy). A door trip whose run ends
--     meanwhile comes out at the house's door; Load checks the carry's pace (no teleport to the truck) and that the
--     thing still exists (a missing model never comes home); the end's facts run in a pcall (the cleanup always frees
--     the slot).
--   * 8.1 walk-in doors (the owner: "no E at the house, neither in nor out"; Config.Moving.Doors; the table WalkIn, the
--     blocks marked "8.1 walk-in doors"): walking into a door's zone takes you through it, no prompt. Outside, a box in
--     front of every door of the site, inside one at every way out (the run's ways), about the doorway's width and
--     Depth deep, Through into the doorway and beyond: a party member on foot standing in one Dwell s facing the door
--     goes through it the way the prompts did (onEnter / onLeave: the same checks, the same fade, a piece in the hands
--     and a pair piece's other end come along). The server looks with the positions (no Touched), in the run's tick and
--     every Doors.Every s between two (Moving.doors: the loop's), only at the run's members. No ping-pong: after any
--     trip (travel) the zones stay shut for that player until they have stepped out of the one they came out in and
--     Rearm s have gone by; you come out a few studs from the door facing away (the house's 4, the plan's entry
--     inside). The E prompts stay, disabled (Doors.Walk false: as before). A doormat on the ground at every door:
--     "▲ IN" outside (shown while a run uses that door), "▲ OUT" inside.
--     8.3 (the owner: "the door should open, and then it teleports me smoothly"; the block "8.3 the doors swing"): a
--     door's leaf (DoorLeaf: shared/DoorSwing.luau) swings open as you walk up to it (its DoorOpen; client/WalkDoors.luau
--     on every client), the trip waits until it is open, then the fade out, the move in the dark (FadeOut + Margin s
--     later: the other end of a pair piece with you, Danny too), the client's dark held until it sees you there.
--     8.5 walking through (the owner: "so it doesn't feel like I bumped into the door, but I keep walking smoothly"):
--     the leaf opens as you come at its door (WalkIn.coming: near it facing it or walking at it, or a run at its
--     doorway from farther), and walking into the doorway is the trip: your root across its threshold (Doors.Cross,
--     looked Ahead s along your walk) starts the fade at once while you walk on into the house's dark hall (the
--     house's doorways are walkable: server/SandboxWorld.luau), no dwell; standing at a door facing it, the 8.3 dwell
--     as before. 8.5.1 (the owner: "the doors just disappear; I'd like them to open nicely"): a leaf says since when it
--     is open (DoorOpenAt, the server's time: a client that first sees it opening swings it on from there), and walking
--     through waits until its leaf has swung Seen × Open s (WalkIn.swung: from just beside a shut door, the swing mostly
--     seen before the screen darkens).
--   * 8.3 Danny's orders (the owner: "when you want to take a heavy thing you must wait until the helper comes";
--     Config.MoveHelper.WaitForHelper; server/MoveHelper.luau's call; 10.1 the crew: the run's helper, free, with you
--     from the start): Lift on a two-person piece calls him (onPick asks MoveHelper.call): no drag alone, you wait at
--     your end ("Stop waiting" on its prompt; Lift again or G stop it) while he walks to its far end; there he makes
--     your lift (Moving.helperCalled: onPick again, the lift check, or the pick without the grip) and the pick hands him
--     its far end at once (MoveHelper.joinLift). Moving.helperLiftFrame says where you will hold it, Moving.helperMark
--     words its prompt ("Lift with Danny" while he waits at a two-person piece of his list), Moving.helperCallOff closes
--     its open lift check when the call ends before the lift. A piece you pick up leaves his list (onPick:
--     MoveHelper.taken). Without a helper (all of the crew in hospital): a two-person piece is dragged alone. 8.3
--     review: a crew mate's Lift on the piece somebody waits at with him is refused (who waits: MoveHelper.call's
--     "busy"); the lift check his arrival opens, left unanswered, closes without a knock.
--   Moving.start()            builds the houses' doors, wires the hooks (SandboxBoot's before it)
--   Moving.busy(player)       why `player` can't start another run now (on one), or nil
--   Moving.respawnAt(player)  where a new body of a player on a run stands (by the run's van, else outside the house),
--                             or nil (off a run)
--   Moving.houseOf(player)    the SandboxMap house of the run `player` is on, else of their card (its seed unspent;
--                             nil: none)
--   Moving.parkVan            the hook server/SandboxBoot.luau sets (its parkVan: a run's van, repaired)
--   Moving.admin(player, arg) the admin panel's SANDBOX tab's Runs group: "time" (one minute left) | "horde" (the horde
--                             now) | "end" (called off) on `player`'s run; returns what to say
--   Moving.useArt(art)        the art modules given (a test or a fallback), instead of finding them by name
--   Moving.step()             one tick of every run (the loop's; tests/moving_runtime_test.luau runs the real module)
--   Moving.doors()            8.1 walk-in doors: one look at every run's doors (the loop's, between two ticks)
--   Moving.helperTake / helperDrop / helperLoad / helperHurt   7.0: the helper's hands (server/MoveHelper.luau: the
--                             run's helper, MoveHelper.sync in the tick); 8.3 helperLiftFrame / helperCalled /
--                             helperMark / helperCallOff: his side of your call (after onHelp)
--   8.1 grip: the carry's timing checks (shared/CarryGrip.luau, client/CarryGripUi.luau): the grip hook (setHands: the
--                             character attribute CarryGrip, the steady walk; the lift moment in onPick / onHelp opens
--                             a lift check) and the grip block (the checks, the remote's "grip" answers, the wobbles)
--   Moving.gripCheck(player)  8.1 grip: a wobble check now on what `player` carries (the tests')
--   Moving.onStart / onEnterHouse / onLoad / onTrip / onFinish / onGrip(fn)   8.2: plain registration of listeners
--                             (SB.listeners; server/SandboxAnalytics.luau's): fn(player, facts) in a pcall (the block
--                             "8.2 SANDBOX: the listeners", after tellAll: SB.tell, SB.facts)
--   Moving.onStored / onResult(fn)   8.2: server/SandboxTasks.luau's and SandboxBadges.luau's (what came home, the end)
--   Moving.startRun / endRun / onRunEnd / onRunStart / runDrop   9.7 runs, 10.x danger (the block "9.7 RUNS")

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Rules = require(Shared.MovingRules)
local MoveRoles = require(Shared.MoveRoles) -- (8.8 no roles: only the climb's rules and the van call's words)
local SandboxMap = require(Shared.SandboxMap) -- the houses and the plots
local Crew = require(script.Parent.Crew)
local MoveLobby = require(script.Parent.MoveLobby) -- 7.0 planning: the quick chat on a run
local MoveHelper = require(script.Parent.MoveHelper) -- 7.0: the run's helper (10.1 the crew: Danny and the others)
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)

local T = Config.Moving
local Moving = {}

local remote = Net.get("Moving")
local notice = Net.get("Notice")
local TAG = "MovePrompt" -- client/MovingHud.luau shows a tagged prompt only to the players it is for
local CARRY_ATTRIBUTES = { "Carrying", "CarryCount", "CarryHands", "CarryAt", "CarrySize", "CarrySpeed", "MoveCarry", "CarryGrip", "PairTurn", "CarryPair",
	"PairWith", "PairFar", "PairWall" } -- (7.0 grip: CarryGrip; 8.1: PairTurn; 8.3: CarryPair; 9.0 the far end's holder: PairWith, PairFar, PairWall)

-- The art (another branch builds it): shared/FurnitureLooks.luau (Items, build), shared/HouseLayout.luau (plan),
-- server/HouseInterior.luau (build, slot, destroy).
export type Art = { looks: any, layout: any, interior: any }
type Contract = { id: string, name: string, client: string, icon: string, seed: number, kind: string, time: number?, hordeAt: number?, difficulty: string?, round: boolean? } -- (9.7 runs: difficulty; 10.5 rounds: round)

-- A house's address and where its van stands (the state's GPS point).
type Home = { address: string, park: { x: number, z: number } }

-- A way in from outside (the front door; the farmstead's back door too), in the plan's exits' order.
type SiteDoor = {
	exit: number, -- the plan's exit it leads to (1: the front door)
	name: string, -- "front door", "back door" (the hints')
	door: Vector3, -- its foot, outside
	facing: Vector3, -- out of it
	outside: CFrame, -- where you come out
	park: Vector3, -- the van's spot (its middle, its back to the door: "Call the van to the door")
	heading: Vector3, -- the van's nose there
	width: number,
	part: BasePart?, -- the Enter prompt's part
}

type Site = {
	contract: Contract,
	home: Home,
	door: Vector3, -- the front door's foot, outside
	facing: Vector3, -- out of the door
	outside: CFrame, -- where you come out
	model: Model,
	doors: { SiteDoor }, -- every way in (doors[1] the front door)
}

-- A way out of the interior: its exit (the Leave prompt's part), where you come in by it, its door.
-- 8.1 walk-in doors: its doorway's width and the flat way into the room from it (WalkIn.ways sets them).
type Way = { exit: number, part: BasePart, inside: Vector3, entry: CFrame, door: SiteDoor, width: number?, into: Vector3? }

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

-- 8.8 no roles: what a run's party shares (the van called, the Enter prompts, the climbs).
type Climb = { at: Vector3, time: number, upUntil: number, slow: boolean, who: number? }
type Team = {
	called: boolean, -- somebody called the van to the door (once a run)
	enter: ProximityPrompt?, -- "Enter house": this run's own, for its party only (the door is never locked)
	doors: { ProximityPrompt }, -- the other doors' Enter prompts (the farmstead's back door)
	climb: { [number]: Climb }, -- by spot: a carried thing going up stairs or a slope
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
	loadIn: ProximityPrompt?, -- the walk-in bay's own Load (Beds' WalkIn: the Sprinter's), inside it
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
	team: Team, -- 8.8: what the party shares (the van called, the Enter prompts, the climbs)
	ways: { Way }, -- the ways out (ways[1] the front door: `exit`)
	lostAt: number?, -- 7.x van moves: the van was lost then (server time; nil: it is out or never was)
	loaders: { [number]: number }?, -- 9.7 runs: spot → the user id of whoever loaded it into the truck last (Danny's: his hirer's)
	homeTo: { [number]: number }?, -- 9.7 runs: spot → the user id whose stock it went into (SB.store)
	rarity: { [number]: string }?, -- 9.7 runs: spot → its model's Rarity attribute as it went home (the loot's own, when it has one)
	danger: any?, -- 10.x danger: server/RunDanger.luau's state of this run (its sealed vault pieces, Danny's shut doorways)
	claims: { [number]: { count: number, value: number } }?, -- 10.5 rounds: user id → what they loaded into their own van
}

local art: Art? = nil
local contractFacts: { [string]: any } = {} -- 7.0 review: a contract's plan and card facts, made once (factsOf)
local sessions: { [Player]: Session } = {} -- by owner
local slots: { [number]: Session } = {}
local sites: { [string]: Site } = {}
local traveling: { [Player]: boolean } = {}
local folder: Folder? = nil
local nextId = 0

-- The houses' state and helpers in one table (this chunk's registers are few: the -O0 limit). Its functions come where
-- what they use is (the blocks marked "8.0 SANDBOX", "six houses", "9.7 RUNS").
--   contracts house id → its contract (SandboxMap.Houses, Config.Moving.Sandbox.Houses: SB.newContract); a run's is a
--             copy with its seed, its clock and its difficulty (Moving.startRun); all: the same in SandboxMap.Houses' order
--   seeds     user id → the seed of the house their card shows, kept until a run of theirs brings something home
--             (SB.store; a new one then). 8.3 economy: a run called off with nothing home (GIVE UP, the host leaving)
--             keeps it, so starting, peeking and calling off never rerolls the house. 8.4: kept in their save too
--             (PlayerData's sandboxHouseSeed: SB.keep sets and drops both), and their save's is the one while it is
--             loaded (SB.cardOf): leaving and joining another server shows the same house
--   houses    six houses: user id → the house of their card (with its seed in seeds; the seed spent, the house they
--             emptied last), in their save too (PlayerData's sandboxHouse)
--   last      the last seed handed out (never twice in a row)
--   doors     six houses: house id → its map front door (the part with the attribute SandboxDoor), once found
--   how       a run's end in words (SB.runResult's, when finish gave none)
local SB = {
	contracts = {} :: { [string]: Contract },
	all = {} :: { Contract },
	seeds = {} :: { [number]: number },
	houses = {} :: { [number]: string },
	last = 0,
	doors = {} :: { [string]: BasePart },
	how = {
		done = "Brought home to your warehouse",
		late = "Time's up: what reached your warehouse is yours",
		cancelled = "Called off: what came home is yours",
		failed = "Lost: nothing came home",
	} :: { [string]: string },
}

-- 8.1 walk-in doors (Config.Moving.Doors): the state of the doors you walk through, in one table (the registers), its
-- functions further down (the block "8.1 walk-in doors", after onLeave).
--   at      player → the zone they stand in (key: 100 + a site door's index outside, a way's inside), since when they
--           face its door (nil: not facing it), tried: gone for it once this visit (a refusal is said once)
--   held    player → after a trip: the zones shut for them until they stepped out of the one they came out in (left;
--           nil: not looked at yet, `from` where they came out) and Rearm s have gone by (untilAt, os.clock)
--   mats    a site → its doormats outside ("▲ IN"), shown while a move uses that site
-- 8.3 the doors swing (Config.Moving.Doors Swing …; shared/DoorSwing.luau; client/WalkDoors.luau swings them):
--   leaves  a door (a site door outside, a way inside: its table) → its leaves (the parts and models with the attribute
--           DoorLeaf at its doorway, tagged DoorLeaf for the clients), found once (WalkIn.leavesOf; weak keys)
--   want    a leaf → the os.clock somebody last wanted it open (in its approach facing it, Danny hired near it, a
--           trip through it); its DoorOpen is true from then until Shut s after (WalkIn.sweep)
--   opened  a leaf → when it opened (the dwell's trip waits until it has been open Open s: WalkIn.ready; 8.5 walking
--           through it waits for nothing)
--   send    the move's state to its crew now (send's: a trip sends where you are before its fade in, so the client's
--           eyes, client/SandboxLight.luau, adapt while the screen is still black)
local WalkIn = {
	at = {} :: { [Player]: { key: number, since: number?, tried: boolean } },
	held = {} :: { [Player]: { untilAt: number, left: boolean?, from: Vector3? } },
	mats = {} :: { [Site]: { BasePart } },
	leaves = setmetatable({}, { __mode = "k" }) :: any,
	want = {} :: { [Instance]: number },
	opened = {} :: { [Instance]: number },
	none = table.freeze({}) :: { Instance },
	send = nil :: ((any) -> ())?,
}

-- MovingRules' words for a refusal (whyText), the drop-off's name in them ("your warehouse").
function SB.why(code: string?): string
	return (string.gsub(Rules.whyText(code), "the Wall", "your warehouse"))
end

-- The move owner's plot (server/SandboxPlots.luau), nil without one.
function SB.plotOf(player: Player): SandboxMap.Plot?
	return require(script.Parent.SandboxPlots).of(player)
end

-- 8.4: `player`'s card seed set (a number) or dropped (nil), here and in their profile (their next save keeps it).
-- six houses: with its house (`house`: a SandboxMap.Houses id; the seed dropped, the house they emptied last).
function SB.keep(player: Player, house: string?, seed: number?)
	local id = player.UserId
	if house then
		SB.houses[id] = house
	else
		SB.houses[id] = nil
	end
	if seed then
		SB.seeds[id] = seed
	else
		SB.seeds[id] = nil
	end
	local profile = PlayerData.get(player)
	if profile then
		profile.sandboxHouse = house
		profile.sandboxHouseSeed = seed
	end
end

-- 8.4: `player`'s card, its house and its seed: their save's while it is loaded (PlayerData's sandboxHouse and
-- sandboxHouseSeed, as their join read them: a house rolled on another server is the same here, and one a trip spent
-- there is spent here too, whatever this server remembered of them), else this server's (SB.houses, SB.seeds: a save
-- not read, Studio without a DataStore). A nil seed: none yet, or spent (the house the one emptied last).
function SB.cardOf(player: Player): (string?, number?)
	local profile = PlayerData.get(player)
	if profile and PlayerData.loaded(player) then
		SB.keep(player, profile.sandboxHouse, profile.sandboxHouseSeed)
	end
	return SB.houses[player.UserId], SB.seeds[player.UserId]
end

-- `player`'s card seed is spent (8.3 economy: a run of theirs brought something home, SB.store; a plan that failed):
-- their next run on that house rolls a new one; that house's plan facts go (factsOf keeps one per seed). `keep` (they
-- left): only the facts go, the seed stays theirs (by user id) for when they come back (8.4: and in their save,
-- written as they leave, for another server).
function SB.forget(player: Player, keep: boolean?)
	local house, seed = SB.houses[player.UserId], SB.seeds[player.UserId]
	if not keep then
		SB.keep(player, house, nil) -- (8.4: their save's too)
	end
	if seed and house then
		contractFacts[`{house}#{seed}`] = nil
	end
end

-- six houses: the SandboxMap house of the run `player` is on (theirs or their party's), else of their card (its seed
-- not spent), nil without one.
function Moving.houseOf(player: Player): SandboxMap.House?
	local own = sessions[player]
	local s = if own and not own.ended then own else nil
	if not s then
		local owner = Crew.ownerOf(player)
		local theirs = if owner then sessions[owner] else nil
		s = if theirs and not theirs.ended then theirs else nil
	end
	if s then
		return SandboxMap.house(s.contract.id)
	end
	local house, seed = SB.cardOf(player)
	return if seed then SandboxMap.house(house) else nil
end

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

-- ── 8.2 SANDBOX: the listeners (server/SandboxAnalytics.luau: the onboarding funnel, the moves' events) ──────────────
-- Plain registration functions; at the moment each listener runs as fn(player, facts) in a pcall (one that errors never
-- stops a move). `facts` is a fresh table of the move's numbers (SB.facts) with what the moment adds (SB.tell's
-- `extra`); a grip check's holds only its own. The moments: startMove's end, a door trip in (travel), Load (onLoad,
-- Danny's helperLoad), the truck's load home (SB.unloadAll), the end (finish) and a grip check's outcome (Grip.result).
-- (stored / result: the daily tasks' hooks with the move itself, Moving.onStored / onResult below)
SB.listeners = { start = {}, enter = {}, load = {}, trip = {}, finish = {}, grip = {}, stored = {}, result = {}, run = {}, runStart = {}, handOver = {} } :: { [string]: { any } } -- (10.x danger: runStart; 10.5 rounds: handOver)

-- A run started (Moving.startRun): fn(owner, facts).
function Moving.onStart(fn: (Player?, { [string]: any }) -> ())
	table.insert(SB.listeners.start, fn)
end

-- A player of a move came into its house (a door trip in): fn(player, facts).
function Moving.onEnterHouse(fn: (Player?, { [string]: any }) -> ())
	table.insert(SB.listeners.enter, fn)
end

-- A piece went into the van: fn(loader, facts) (loader nil: Danny; facts.item).
function Moving.onLoad(fn: (Player?, { [string]: any }) -> ())
	table.insert(SB.listeners.load, fn)
end

-- The truck's load home (a run's end): fn(owner, facts) (facts.pieces: its pieces; facts.stored: into the stocks).
function Moving.onTrip(fn: (Player?, { [string]: any }) -> ())
	table.insert(SB.listeners.trip, fn)
end

-- The move ended: fn(owner, facts) (facts.phase: done | late | cancelled | failed; facts.event, facts.why: finish's).
function Moving.onFinish(fn: (Player?, { [string]: any }) -> ())
	table.insert(SB.listeners.finish, fn)
end

-- A grip check's outcome: fn(player, { what: lift | wobble, outcome, item, fragile }).
function Moving.onGrip(fn: (Player?, { [string]: any }) -> ())
	table.insert(SB.listeners.grip, fn)
end

-- The move's numbers: its owner and contract, the crew, the trips, what came home (home: pieces; value: their worth at
-- their condition, $), the pieces in all, in the van and lost, the minutes since the start, the clock's seconds left
-- (under 0 past it) and the phase.
function SB.facts(s: Session): { [string]: any }
	local c = Rules.counts(s.move)
	local value = 0
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		if thing.state == "delivered" then
			value += thing.value * thing.condition
		end
	end
	local t = now()
	return {
		owner = s.owner,
		contract = s.contract.id,
		crew = #everyone(s),
		trips = s.move.trips or 0,
		home = c.delivered,
		value = math.floor(value + 0.5),
		total = c.total,
		out = c.out,
		lost = c.lost,
		minutes = math.max(0, t - s.move.startedAt) / 60,
		left = s.move.endsAt - t,
		phase = s.move.phase,
	}
end

-- Tells the `kind` listeners (none: nothing is worked out) about move `s` (nil: only `extra`).
function SB.tell(kind: string, s: Session?, player: Player?, extra: { [string]: any }?)
	local list = SB.listeners[kind]
	if not list or #list == 0 then
		return
	end
	local made, built = pcall(function(): { [string]: any }
		return if s then SB.facts(s) else {}
	end)
	if not made then
		warn(`[Moving] the {kind} listeners' facts failed: {built}`) -- (8.2 review: never in the way of the move's end)
		return
	end
	local facts: { [string]: any } = built
	if extra then
		for key, value in extra do
			facts[key] = value
		end
	end
	for _, fn in list do
		local ok, err = pcall(function()
			fn(player, facts)
		end)
		if not ok then
			warn(`[Moving] a {kind} listener failed: {err}`)
		end
	end
end

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

-- 8.8 no roles: what the party shares on a run.
local function newTeam(): Team
	return {
		called = false,
		enter = nil,
		doors = {},
		climb = {},
	}
end

-- The carry's walk for this thing (MovingRules': its kind and weight).
local function speedOf(thing: Rules.Thing): number
	local mode = Rules.mode(thing)
	return Config.Movement.Walk * Rules.speedFactor(mode, thing.weight)
end

-- × the carry's walk now: going up stairs or a slope (the climb watch in watchCarried), a thing in both hands or two.
local function climbOf(s: Session, spot: number): number
	local c = s.team.climb[spot]
	local thing = s.move.things[spot]
	if not c or not c.slow or not thing then
		return 1
	end
	return MoveRoles.climbFactor(nil, Rules.mode(thing))
end

-- ── The places: the drop-off, the houses' doors ────────────────────────────

-- Where a run's party's warehouse is: the middle of the host's plot's unload circle (the state's dropOff; no plot: the
-- house's door).
function SB.dropAt(s: Session): Vector3
	local plot = SB.plotOf(s.owner)
	return if plot then Vector3.new(plot.unload.x, SandboxMap.GroundTop, plot.unload.z) else s.site.door
end

local onEnter: (Player, string, number?) -> ()

-- ── The houses' sites (shared/SandboxMap.luau Houses) ────────────────────────────────────────────────────────────────
-- Its front door (the spot outside it, looking out to the road), the van's curb (its pivot: the nose to the road, the
-- back to the door: "Call the van to the door"), out where you came in (4 studs out of the door). Its "Enter house" part
-- is an invisible one at the door until the map's front door is found (SB.frontDoor: the prompt goes onto that); the
-- map's house (server/SandboxWorld.luau) stands there as it is. 8.3 the big move: its second door, the back door
-- (House.back, the owner's model's back door: "Enter" there to the plan's exits[2], out there by it); the van's spot for
-- both the curb.
local function yawLook(yaw: number): Vector3
	local r = math.rad(yaw)
	return Vector3.new(-math.sin(r), 0, -math.cos(r))
end

-- six houses: every house's site, the contract's house's (SandboxMap.house(contract.id)): its front door, its curb, its
-- street and address (Config.Moving.Sandbox.Houses'); its back door only where it has one.
function SB.site(contract: Contract, parent: Instance): Site
	local h = SandboxMap.house(contract.id) or SandboxMap.House
	local facing = yawLook(h.door.yaw)
	local door = Vector3.new(h.door.x, h.door.y, h.door.z)
	local park = Vector3.new(h.curb.x, 0, h.curb.z)
	local model = Instance.new("Model")
	model.Name = `Move_{contract.id}`
	local up = Vector3.new(0, 3.5, 0)
	local enter = invisible("EnterDoor", Vector3.new(4, 6, 1), CFrame.lookAt(door + facing * 0.9 + up, door + facing * 3 + up), model)
	model.PrimaryPart = enter
	model.Parent = parent
	local out = door + facing * 4 + Vector3.new(0, 0.1, 0) -- (8.1 walk-in doors: 4 out, clear of its zone)
	local outside = CFrame.lookAt(out, out + facing)
	local own = T.Sandbox.Houses[h.id]
	local home: Home = { address = if own then own.Address else h.street, park = { x = park.X, z = park.Z } }
	local front: SiteDoor = { exit = 1, name = "front door", door = door, facing = facing, outside = outside, park = park, heading = yawLook(h.curb.yaw), width = 4, part = enter }
	local doors = { front }
	-- 8.3 the big move: its back door (House.back, the plan's exits[2]), a second way in and out; the van's spot the curb
	-- (six houses: only where the house has one, the farmstead)
	local back = h.back
	if back then
		local backFacing = yawLook(back.yaw)
		local backDoor = Vector3.new(back.x, back.y, back.z)
		local backOut = backDoor + backFacing * 4 + Vector3.new(0, 0.1, 0)
		table.insert(doors, {
			exit = 2,
			name = "back door",
			door = backDoor,
			facing = backFacing,
			outside = CFrame.lookAt(backOut, backOut + backFacing),
			park = park,
			heading = yawLook(h.curb.yaw),
			width = 4,
			part = invisible("EnterDoor2", Vector3.new(4, 6, 1), CFrame.lookAt(backDoor + backFacing * 0.9 + up, backDoor + backFacing * 3 + up), model),
		})
	end
	return { contract = contract, home = home, door = door, facing = facing, outside = outside, model = model, doors = doors }
end

-- The house a map door belongs to (six houses): its own attribute SandboxHouse, else its nearest model's that has one;
-- none: the farmstead (a door of 8.0 – 8.9's map, a test's).
function SB.doorHouse(d: Instance): string
	local at: Instance? = d
	while at and at ~= workspace do
		local id = at:GetAttribute("SandboxHouse")
		if type(id) == "string" then
			return id
		end
		at = at.Parent
	end
	return SandboxMap.House.id
end

-- The map's front door of the house `id` (server/SandboxWorld.luau's FrontDoor: the part with the attribute
-- SandboxDoor in that house's model, SB.doorHouse), looked for when a move starts (kept while it stands); nil while the
-- map has none.
function SB.frontDoor(id: string): BasePart?
	local known = SB.doors[id]
	if known and known:IsDescendantOf(workspace) then
		return known
	end
	SB.doors[id] = nil
	for _, d in workspace:GetDescendants() do
		local mark = d:GetAttribute("SandboxDoor")
		if mark ~= nil and mark ~= false and d:IsA("BasePart") and SB.doorHouse(d) == id then
			SB.doors[id] = d
			return d
		end
	end
	return nil
end

-- A house's contract (its seed, clock, horde and difficulty set per run: Moving.startRun): six houses, its own words in
-- Config.Moving.Sandbox.Houses (its family, its plan's kind: 8.3 the farmstead the big house's, HouseLayout's "big";
-- the family house "house"), the icon Config.Moving.Sandbox's.
function SB.newContract(h: SandboxMap.House): Contract
	local S = T.Sandbox
	local own = S.Houses[h.id]
	return {
		id = h.id,
		name = h.name,
		client = if own then own.Client else "The Nováks",
		icon = S.Icon,
		seed = 0,
		kind = if own then own.Kind else h.kind,
		time = if own then own.Time else T.Time,
		hordeAt = 0,
	}
end

-- ── The carry ──────────────────────────────────────────────────────────────

local function clearHands(player: Player?)
	if player then
		require(script.Parent.PairHold).free(player) -- 8.1: a crew mate held at a piece's far end: their body theirs again
	end
	local character = player and player.Character
	if character and character:GetAttribute("MoveCarry") ~= nil then
		for _, name in CARRY_ATTRIBUTES do
			character:SetAttribute(name, nil)
		end
	end
end

-- Where a thing sits from its carrier's root: in front of the chest (MovingRules' mode "drag": low, a step ahead).
-- 8.6 carried in two (mode "pair" with a helper on its other end, or `two`: Danny's call; the owner: "he teleports from
-- side to side", "the table seems to float between them"): lengthwise, its long side along the carry (a piece wider
-- than deep turned a quarter round: its +X ahead), its near end in your hands and its far end the other one's
-- (MoveHelperBrain.holdEnd: decided once); low, its grips at your hands (MovingRules.pairLift).
local function holdOffset(thing: Rules.Thing, mode: string, root: BasePart, humanoid: Humanoid, two: boolean?): CFrame
	local size = thing.size
	local tune = Config.Cargo
	local feet = -(root.Size.Y / 2 + humanoid.HipHeight)
	if mode == "drag" then
		return CFrame.new(0, feet + size.Y / 2 + 0.2, -(tune.CarryFront + 1.2 + size.Z / 2))
	elseif mode == "pair" and (two or thing.helper ~= nil) then
		local middle = Rules.pairLift(size.Y, feet)
		if size.X > size.Z then
			return CFrame.new(0, middle, -(tune.CarryFront + size.X / 2)) * CFrame.Angles(0, math.pi / 2, 0)
		end
		return CFrame.new(0, middle, -(tune.CarryFront + size.Z / 2))
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

-- ── 8.1 grip hook (shared/CarryGrip.luau; the checks and the answers: the grip block before "Start") ─────────────────
-- The grip's state is one table, Grip (this chunk's registers are few: the -O0 limit): a record per player (a GripHold)
-- from a lift check on a piece with a grip until its carry ends; its functions come where what they use is (the
-- hands here, setHands asks them first; the checks in the grip block). Grip.hands, where a carry starts or changes:
-- every player holding a piece with a grip gets the character attribute CarryGrip (CarryGrip.encode: the kind, the
-- weight, fragile; client/KeyHints.luau's key chip), nil without one (a one-hand thing that is not fragile, or
-- Config.CarryGrip.On false); Danny has none (he never wobbles). It goes with the other carry attributes
-- (CARRY_ATTRIBUTES). The carry a lift check led to starts its wobble clock; the same carry with another kind (a
-- helper took the other end, Danny steadies it) keeps its clock, its steady and its misses. Returns × the carry's walk:
-- CarryGrip.speedFactor (steady while every player holding it hit their last check; × Miss.Slow while one of them
-- staggers).
local CarryGrip = require(Shared.CarryGrip)
type GripOpen = { id: number, check: CarryGrip.Check, spot: number, help: boolean, opened: number, called: boolean? } -- (8.3 review: called, Moving.helperCalled's)
type GripHold = {
	session: number,
	spot: number, -- the piece (its lift check's, then the carry's)
	carrying: boolean, -- in their hands (false: a lift check on it, or a miss's moment after one)
	kind: string, -- the carry's kind (CarryGrip.kind)
	steady: boolean, -- their last check was a hit (the steady walk)
	misses: number, -- wobble misses in a row (one or more: shaky)
	slowUntil: number, -- a stagger's slowdown until (server time; 0: none)
	clock: CarryGrip.Wobbles?, -- the carry's wobble clock
	open: GripOpen?, -- the check on now
	again: number, -- no new lift check before (server time: a moment after a miss)
	tick: number, -- the server time of the last look (the grip block's Grip.tick)
	at: Vector3?, -- the body then (the clock's pace) …
	yaw: number?,
	health: number?, -- … and its health (a bite moves the clock on)
	owed: boolean?, -- a wobble a door's fade turned off: it opens again on the other side (8.1 review)
}
local Grip = {
	holds = {} :: { [Player]: GripHold },
	nextId = 0,
	-- 8.1 review: a shaky carry's misses stay with the piece a moment after it is put down (Miss.Remember s), so a new
	-- lift of the same piece picks them up again (putting it down to dodge the next miss's drop does nothing)
	recent = {} :: { [Player]: { session: number, spot: number, misses: number, till: number } },
}
Players.PlayerRemoving:Connect(function(player: Player)
	Grip.holds[player] = nil
	Grip.recent[player] = nil
end)

-- A new record (`player`'s misses on this piece a moment ago come back with it).
function Grip.newHold(s: Session, spot: number, carrying: boolean, kind: string, player: Player): GripHold
	local misses = 0
	local was = Grip.recent[player]
	if was and was.session == s.id and was.spot == spot and now() < was.till then
		misses = was.misses
	end
	Grip.recent[player] = nil
	return { session = s.id, spot = spot, carrying = carrying, kind = kind, steady = false, misses = misses, slowUntil = 0, clock = nil, open = nil, again = 0, tick = now(), at = nil, yaw = nil, health = nil }
end

-- `player`'s checks on `thing` as a carry of `kind`: Danny steadying it (GripSteady on their body) a bigger zone.
function Grip.profile(thing: Rules.Thing, kind: string, player: Player): CarryGrip.Profile
	local character = player.Character
	local steadied = character ~= nil and character:GetAttribute("GripSteady") == true
	return CarryGrip.profile(kind, thing.weight, thing.fragile, false, steadied)
end

function Grip.hands(s: Session, item: Item): number
	local thing = s.move.things[item.spot]
	local kind = if Config.CarryGrip.On then CarryGrip.kind(thing.class, thing.fragile, thing.helper ~= nil, nil) else nil
	local steady, staggered = kind ~= nil, false
	local t = now()
	for _, id in { thing.carrier, thing.helper } do
		local player = playerById(id)
		local character, humanoid = bodyOrNil(player)
		if not player or not character or not humanoid then
			continue -- (Danny, or a body that is gone)
		end
		if not kind then
			character:SetAttribute("CarryGrip", nil)
			continue
		end
		local found = Grip.holds[player]
		local hold: GripHold = if found and found.session == s.id and found.spot == item.spot then found
			else Grip.newHold(s, item.spot, false, kind, player) -- (a carry no lift check led to: not balanced)
		Grip.holds[player] = hold
		if not hold.carrying then -- (the lift: its wobble clock starts)
			hold.carrying = true
			hold.clock = CarryGrip.wobbles(Grip.profile(thing, kind, player), math.random())
			hold.tick, hold.at, hold.yaw, hold.health = t, nil, nil, humanoid.Health
		end
		hold.kind = kind
		character:SetAttribute("CarryGrip", CarryGrip.encode(kind, thing.weight, thing.fragile))
		steady = steady and hold.steady
		staggered = staggered or hold.slowUntil > t
	end
	return CarryGrip.speedFactor(steady, staggered)
end
-- ── (end of the grip hook) ───────────────────────────────────────────────────────────────────────────────────────────

-- The holders' attributes for the thing now (its mode: the walk, the hands).
local function setHands(s: Session, item: Item)
	local thing = s.move.things[item.spot]
	local mode = Rules.mode(thing)
	local grip = Grip.hands(s, item) -- 8.1 grip hook: the carry's kind for its holders, × the steady walk (or a stagger)
	local speed = speedOf(thing) * climbOf(s, item.spot) * grip -- (slower up stairs)
	local carrier = playerById(thing.carrier)
	local _, humanoid, root = bodyOrNil(carrier)
	local character = carrier and carrier.Character
	if character and humanoid and root then
		character:SetAttribute("Carrying", if mode == "hand" then "crate" else "furniture")
		character:SetAttribute("CarryCount", 1)
		character:SetAttribute("CarryHands", Rules.hands(mode))
		local at, size = holdOffset(thing, mode, root, humanoid).Position, Vector3.new(thing.size.X, thing.size.Y, thing.size.Z)
		if mode == "pair" and thing.helper ~= nil then
			-- 8.6 carried in two: your hands on its near end's edge at its grips' height (client/ArmPose.luau's box: Config.
			-- MoveHelper.Edge, its width across), not on the sides of its middle (a long piece's: out of reach)
			local edge = Config.MoveHelper.Edge
			local _, hands = Rules.pairLift(thing.size.Y, -(root.Size.Y / 2 + humanoid.HipHeight))
			at = Vector3.new(0, hands, -(Config.Cargo.CarryFront + edge.Depth / 2))
			size = Vector3.new(math.min(thing.size.X, thing.size.Z, edge.Width), edge.Height, edge.Depth)
		end
		character:SetAttribute("CarryAt", at)
		character:SetAttribute("CarrySize", size)
		character:SetAttribute("CarrySpeed", speed)
		character:SetAttribute("MoveCarry", item.spot)
		-- 8.1 carrying in two: the leader's heading turns PairTurn degrees a second at most (client/PairSteer.luau)
		character:SetAttribute("PairTurn", if thing.helper ~= nil then Config.MoveHelper.PairTurn else nil)
		-- 8.3 (the owner: "when I run, he just goes behind me"): two carry it, nobody runs (client/PairSteer.luau holds
		-- the walk at CarrySpeed, the run key says Config.MoveHelper.RunHint once)
		character:SetAttribute("CarryPair", if thing.helper ~= nil then true else nil)
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
		helperBody:SetAttribute("CarryPair", true) -- (8.3: nobody runs)
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
	item.help.Enabled = thing.state == "carried" and thing.class == "pair" and thing.helper == nil and playerById(thing.carrier) ~= nil -- (10.1: never on Bruno's)
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
	item.model.Parent = folder -- (out of the interior's model: it goes where its carrier goes)
	weldTo(item, root, root.CFrame * holdOffset(thing, Rules.mode(thing), root, humanoid))
	item.lastAt, item.lastTime, item.apartSince, item.fallFrom = nil, 0, nil, nil
	setHands(s, item)
	rewire(s, item)
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
		tellAll(s, `💥 The {thing.name} broke! It is worth next to nothing now.`)
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
type BedDef = { Width: number, Length: number, Height: number, Cell: number, Center: { number }, Back: number?, WalkIn: boolean? }
local function bedOf(truck: Vehicles.Car?): BedDef
	return (if truck then T.Beds[truck.id] else nil) or T.Beds[T.Van]
end

-- A bed's middle in the chassis' frame (x, z): its Center, or (Beds' Back, 8.0 SANDBOX: the Sprinter's) its back end
-- Back studs in front of the car's CargoDoor: the bay follows the body's length.
function SB.center(truck: Vehicles.Car, bed: BedDef): (number, number)
	local back = bed.Back
	local door = if back then Vehicles.cargoDoor(truck) else nil
	if back and door then
		return bed.Center[1], door.Position.Z - back - bed.Length / 2
	end
	return bed.Center[1], bed.Center[2]
end

-- The floor of the car's bed over the chassis' middle (its first cargo slot's height).
local function bedFloor(truck: Vehicles.Car): number
	local slots = Vehicles.cargoSlots(truck)
	return if slots[1] then slots[1].Position.Y else 0.6
end

-- 8.0 SANDBOX: is `at` inside the car's walk-in bay (Beds' WalkIn: the Sprinter's)? Its box over the floor, the bed's
-- width and length (half a stud of slack round it), up to its roof; in the chassis' frame as bedFrame places the load
-- (the cargoHolder's at rest). Never for a bed you can't walk into.
function SB.inBay(truck: Vehicles.Car, at: Vector3): boolean
	local bed = bedOf(truck)
	if not bed.WalkIn then
		return false
	end
	local cx, cz = SB.center(truck, bed)
	local floor = bedFloor(truck)
	local p = truck.chassis.CFrame:PointToObjectSpace(at)
	return math.abs(p.X - cx) <= bed.Width / 2 + 0.5 and math.abs(p.Z - cz) <= bed.Length / 2 + 0.5 and p.Y >= floor - 1 and p.Y <= floor + bed.Height + 2
end

-- server/SandboxBoot.luau's parkVan (the player's van parked at a spot as their one vehicle, repaired: a run's van,
-- CAR's), set by it before Moving.start (a hook: the two modules never require each other).
Moving.parkVan = nil :: ((player: Player, spot: SandboxMap.Spot, seat: boolean, carId: string?) -> (string?, Vehicles.Car?))?

-- 10.5 rounds: server/Runs.luau's hook: the van a player has at a round's house (respawnAt stands a new body by it).
Moving.roundVan = nil :: ((player: Player) -> Vehicles.Car?)?

-- The host's own van when none is out as their run starts (server/Runs.luau parks it first: a run started some other
-- way) at the house's curb, its back to the door, not seated, the sandbox's way (Moving.parkVan: repaired). nil, or why
-- it could not come.
function SB.bringVan(owner: Player, house: SandboxMap.House?): string?
	local park = Moving.parkVan
	if not park then
		return "Your van could not come: try again."
	end
	local err, car = park(owner, (house or SandboxMap.House).curb, false)
	return err or (if car then nil else "Your van could not come: try again.")
end

-- The van's name on its prompts: the car's own ("Sprinter").
function SB.vanLabel(truck: Vehicles.Car): string
	local def = Economy.findCar(truck.id)
	return if def then def.name else "Deliveros Van"
end

local function rulesBed(truck: Vehicles.Car?): Rules.Bed
	local bed = bedOf(truck)
	return { width = bed.Width, length = bed.Length, height = bed.Height, cell = bed.Cell }
end

-- The bed's place in the truck's chassis frame: (its middle at the floor, from MovingRules.where's numbers). A thing
-- lying on its side (Placement.lying, Config.Moving.Pack.Lie) is rolled first: "x" its height along its width (about
-- its depth), "z" along its depth (about its width); then turned.
local function bedFrame(truck: Vehicles.Car, x: number, y: number, z: number, turned: boolean, lying: string?): CFrame
	local floor = bedFloor(truck)
	local turn = if turned then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
	local lie = if lying == "x" then CFrame.Angles(0, 0, math.rad(90)) elseif lying == "z" then CFrame.Angles(math.rad(90), 0, 0) else CFrame.identity
	local cx, cz = SB.center(truck, bedOf(truck)) -- (7.x van moves: the car's own bay; 8.0 SANDBOX: from its back doors)
	return truck.chassis.CFrame * CFrame.new(cx + x, floor + y, cz + z) * turn * lie
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
	local x, y, z = Rules.where(s.move.packing, at)
	weldTo(item, Vehicles.cargoHolder(truck), bedFrame(truck, x, y, z, at.turned, at.lying))
	rewire(s, item)
end

-- The packing fix: Load repacked the bed (MovingRules.load's moved spots): their models welded at their new places.
local function restow(s: Session, moved: { number }?)
	if not moved then
		return
	end
	for _, spot in moved do
		local item = s.items[spot]
		local place = s.move.things[spot].place
		if item and place then
			stow(s, item, place)
		end
	end
end

-- Near the truck's open back, on foot, the truck standing: (ok, what to say). 8.0 SANDBOX: or inside its walk-in bay
-- (the back open or not: you are in already).
local function atBack(s: Session, player: Player): (boolean, string?)
	local truck = truckOk(s)
	local door = truck and Vehicles.cargoDoor(truck)
	local _, humanoid, root = bodyOf(player)
	if not truck or not door or not humanoid or not root then
		return false, nil
	end
	local inBay = SB.inBay(truck, root.Position)
	if humanoid.SeatPart then
		return false, "Get out first."
	elseif not inBay and flat(root.Position, door.WorldPosition) > T.Reach.Truck + 3 then
		return false, nil
	elseif not inBay and not Vehicles.backOpen(truck) then
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
	local walk = speedOf(thing)
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
			say(player, SB.why("gone"))
			s.dirty = true
			return
		end
		local character, _, root = bodyOf(player)
		if character and root and paceBroken(s, held, thing, player, character, root, os.clock()) then
			release(s, player, "pace")
			return
		end
	end
	local at, refused, moved = Rules.load(s.move, player.UserId)
	if not at or not spot or not thing then
		say(player, SB.why(refused))
		return
	end
	clearHands(player)
	clearHands(helper)
	local item = s.items[spot]
	if item then
		stow(s, item, at)
	end
	restow(s, moved)
	local c = Rules.counts(s.move)
	local fill = math.floor(Rules.fill(s.move.packing) * 100 + 0.5)
	say(player, `{if moved then "Van repacked: " else ""}{labelOf(thing)} loaded · {c.out} in the van · van {fill}% full · {c.delivered}/{c.total} home`)
	s.dirty = true
	SB.loaded(s, spot, player) -- 9.7 runs: whose stock it goes into
	SB.tell("load", s, player, { item = thing.item, spot = spot }) -- 8.2: the listeners (Moving.onLoad)
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
		say(player, SB.why(refused))
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
	for _, old in { s.load, s.unload, s.loadIn } do
		if old then
			local spot = old.Parent
			old:Destroy() -- (7.x van moves: a van called again after the last was lost: its prompts on the new one)
			if spot and (spot.Name == "MoveTakeOut" or spot.Name == "MoveLoadBay") then
				spot:Destroy()
			end
		end
	end
	s.loadIn = nil
	local label = SB.vanLabel(truck)
	local load = newPrompt(door, "Load", label, Enum.KeyCode.E, 0, T.Reach.Truck) -- (8.8 no roles: nobody waits at the back)
	-- (the owner's report: on the door's own attachment Unload stacked with Load and the back's E: its own spot, 2.5
	-- studs aside from the door's middle, toward the bed's edge; destroyed with the prompts at the end)
	local side = Instance.new("Attachment")
	side.Name = "MoveTakeOut"
	side.Position = door.Position + Vector3.new(2.5, 0, 0)
	side.Parent = door.Parent
	local unload = newPrompt(side, "Take out", label, Enum.KeyCode.Z, 0, T.Reach.Truck)
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
	-- a walk-in bay (Beds' WalkIn: the Sprinter's) has its own Load in its middle, for a carrier inside it (refreshTruck
	-- shows it; atBack lets them load from there); destroyed with the others
	local bed = bedOf(truck)
	if bed.WalkIn then
		local cx, cz = SB.center(truck, bed)
		local middle = Instance.new("Attachment")
		middle.Name = "MoveLoadBay"
		middle.Position = Vector3.new(cx, bedFloor(truck) + 3, cz)
		middle.Parent = door.Parent
		local inside = newPrompt(middle, "Load", label, Enum.KeyCode.E, 0, math.max(bed.Length, bed.Width) / 2 + 3)
		inside.Enabled = false
		tag(inside, s.owner)
		inside.Triggered:Connect(function(player: Player)
			onLoad(s, player)
		end)
		s.loadIn = inside
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

-- The truck's prompts as things stand (MovingRules.truckPrompts): Load while somebody of the crew at the back carries
-- a thing (the back's own E and Unload wait then), Unload ("Take out") while one may come out and nobody there
-- carries one; the back for the crew too (BackCrew). 8.0 SANDBOX: a carrier inside the walk-in bay counts as at the
-- back (the back's E never shuts on them, Take out waits) and gets the bay's own Load (the back open or not); the
-- door's Load then only for a carrier outside at the doors.
local function refreshTruck(s: Session)
	local truck = truckOk(s)
	local load, unload = s.load, s.unload
	if not truck or not load or not unload then
		return
	end
	local open = Vehicles.backOpen(truck)
	local carried: Rules.Thing? = nil
	local carriers = 0
	local inBay: Rules.Thing? = nil -- (8.0 SANDBOX: carried inside the walk-in bay)
	local insiders = 0
	local door = Vehicles.cargoDoor(truck)
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local _, _, carrierRoot = bodyOrNil(playerById(thing.carrier)) -- (7.0 helper: not what Danny carries)
		-- (7.0 review: only a carrier at the back: one in the house does not keep the back from closing)
		if thing.state == "carried" and carrierRoot and SB.inBay(truck, carrierRoot.Position) then
			insiders += 1
			inBay = thing
		elseif thing.state == "carried" and carrierRoot and door and flat(carrierRoot.Position, door.WorldPosition) <= T.Reach.Truck + 3 then
			carriers += 1
			carried = thing
		end
	end
	local fill = math.floor(Rules.fill(s.move.packing) * 100 + 0.5)
	local out = Rules.lastOut(s.move)
	local label = SB.vanLabel(truck)
	local showLoad, showUnload, showBack = Rules.truckPrompts(open, carriers + insiders > 0, out ~= nil)
	load.Enabled = showLoad and (carriers > 0 or insiders == 0)
	load.ActionText = if carriers == 1 and carried then `Load {carried.name}` else "Load"
	-- (the packing fix: the carried thing has no room even repacked: Load says so before it is pressed)
	local fits = true
	if carriers == 1 and carried and showLoad then
		fits = Rules.canLoad(s.move, carried.spot)
	end
	load.ObjectText = if fits then `{label} · {fill}% full` else `won't fit · {fill}% full`
	local bay = s.loadIn
	if bay then
		local fitsIn = not (insiders == 1 and inBay) or Rules.canLoad(s.move, (inBay :: Rules.Thing).spot)
		bay.Enabled = insiders > 0
		bay.ActionText = if insiders == 1 and inBay then `Load {inBay.name}` else "Load"
		bay.ObjectText = if fitsIn then `{label} · {fill}% full` else `won't fit · {fill}% full`
	end
	unload.Enabled = showUnload
	unload.ActionText = if out then `Take out {s.move.things[out].name}` else "Take out"
	unload.ObjectText = `{label} · {fill}% full`
	-- 8.6 (the owner's screenshot: "Load Dining Table" and "Put down" drawn on top of each other at the van's back): while
	-- the van's Load is up for a carrier there, their piece's own G prompts draw nothing (ProximityPromptStyle.Custom:
	-- G still puts it down, the HUD's action pill says so): Load is the one prompt there
	for _, spot in s.move.order do
		local item = s.items[spot]
		local thing = s.move.things[spot]
		if item and #item.down > 0 then
			local _, _, at = bodyOrNil(playerById(thing.carrier))
			local loading = thing.state == "carried" and at ~= nil and ((load.Enabled and door ~= nil and flat(at.Position, door.WorldPosition) <= T.Reach.Truck + 3)
				or (bay ~= nil and bay.Enabled and SB.inBay(truck, at.Position)))
			local style = if loading then Enum.ProximityPromptStyle.Custom else Enum.ProximityPromptStyle.Default
			for _, prompt in item.down do
				if prompt.Style ~= style then
					prompt.Style = style
				end
			end
		end
	end
	local back = Vehicles.backPrompt(truck)
	if back then
		back.Enabled = showBack
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
-- thing a player lifted (their walk: two people's now). Never a pair thing alone. (ok, why)
-- 7.x Danny, a partner: a "both" thing into his arms too, or the other side of one a player carries (the pair's walk).
-- 10.1 the crew (server/HelperCrew.luau): a helper whose model says CrewSolo (Bruno) picks a pair thing up alone, as
-- his own (its carrier: in his arms, his carry the drag's slow walk; nobody's Help on it: rewire), never its far end.
function Moving.helperTake(s: Session, spot: number, npc: Model): (boolean, string?)
	local who = helperIdOf(npc)
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local root = npc.PrimaryPart
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if s.ended or not who or not item or not thing or not root or not humanoid then
		return false, "gone"
	elseif s.danger and s.danger.sealed[spot] then
		return false, "sealed" -- 10.x danger: in the run's vault
	end
	local solo = thing.class == "pair" and thing.state ~= "carried" and npc:GetAttribute("CrewSolo") == true -- 10.1 Bruno
	if not solo and (thing.class == "pair" or (thing.class == "both" and thing.state == "carried")) then -- (7.x: a both thing's other side)
		local ok, why = Rules.help(s.move, spot, who, true)
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
	elseif not solo and thing.class ~= "hand" and thing.class ~= "both" then -- (7.x: a both thing alone too)
		return false, "single"
	end
	local ok, why = Rules.pick(s.move, spot, who)
	if not ok then
		return false, why
	end
	item.model.Parent = folder
	weldTo(item, root, root.CFrame * holdOffset(thing, if solo then "both" else Rules.mode(thing), root, humanoid)) -- (7.x: "hand" or "both"; 10.1 a pair thing alone in his arms)
	item.lastAt, item.lastTime, item.apartSince, item.fallFrom = nil, 0, nil, nil
	rewire(s, item)
	s.dirty = true
	return true, nil
end

-- He lets go. why: "put" (set down gently where he is), "died" (it falls: knocked), "apart" (his end of a pair thing:
-- left behind) or "end". His end of a pair thing: the carrier drags it on alone. 8.6 "together" (the crew's PUT IT
-- DOWN, server/MoveHelper.luau's order): his end of a pair thing goes down with the carrier's, the carrier's own "put"
-- (as their G: release).
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
	if role == "helper" and why == "together" and playerById(thing.carrier) and not s.ended then
		release(s, playerById(thing.carrier) :: Player, "put")
		return
	end
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
	local at, refused, moved = Rules.load(s.move, who)
	if not at or not spot or not thing then
		return false, refused
	end
	local item = s.items[spot]
	if item then
		stow(s, item, at)
	end
	restow(s, moved)
	local c = Rules.counts(s.move)
	say(s.owner, `{npc.Name} loaded {labelOf(thing)} · {c.out}/{c.total} out · truck {math.floor(Rules.fill(s.move.packing) * 100 + 0.5)}% full`)
	s.dirty = true
	local hired = MoveHelper.find(s.owner) -- (9.7 runs: his loads go into his boss's stock: 10.1 the move's owner, the host)
	SB.loaded(s, spot, if hired then hired.hirer else nil)
	SB.tell("load", s, nil, { item = thing.item, spot = spot }) -- 8.2: the listeners (Moving.onLoad: Danny's, no player)
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

-- ── 8.3 the doors swing (Config.Moving.Doors Swing …; shared/DoorSwing.luau has the attributes) ──────────────────────
-- A door's leaves are the parts and models with the attribute DoorLeaf at its doorway (outside: anywhere in the world
-- within its width of the site door's foot, the map's house's; inside: the move's interior's, at the way out), found
-- once a move (WalkIn.ways forgets the site's) and tagged DoorLeaf: every client swings a tagged leaf open while its
-- DoorOpen is true (client/WalkDoors.luau). The server only says when: somebody wants it open (a crew member in its
-- approach facing it, Danny near it, a trip through it: WalkIn.open; 8.5 a crew member walking at it, from farther at
-- a run: WalkIn.coming), and it shuts Shut s after the last of that (WalkIn.sweep). The leaves never collide (the
-- builders' parts don't, the clients move only their own view).

-- The door (a site door outside, a way inside) nearest `at` on that side, within its approach's reach; nil: none.
function WalkIn.doorNear(s: Session, at: Vector3, inside: boolean): any
	local best: any = nil
	local reach = T.Doors.Approach + T.Doors.Through
	if inside then
		for _, way in s.ways do
			local d = flat(way.inside, at)
			if d <= reach + (way.width or 4) / 2 then
				best, reach = way, d
			end
		end
	else
		for _, door in s.site.doors do
			local d = flat(door.door, at)
			if d <= reach + door.width / 2 then
				best, reach = door, d
			end
		end
	end
	return best
end

-- The leaves under `root` within `reach` studs (flat) of `at` and Height of its height, tagged for the clients.
function WalkIn.find(root: Instance?, at: Vector3, reach: number): { Instance }
	local found: { Instance } = {}
	for _, d in (if root then root:GetDescendants() else {}) :: { Instance } do
		if d:GetAttribute("DoorLeaf") == nil then
			continue
		end
		local pivot: Vector3? = if d:IsA("BasePart") then d.Position elseif d:IsA("Model") then d:GetPivot().Position else nil
		if pivot and flat(pivot, at) <= reach and math.abs(pivot.Y - at.Y) <= T.Doors.Height then
			CollectionService:AddTag(d, "DoorLeaf")
			table.insert(found, d)
		end
	end
	return found
end

-- A door's leaves (`door`: a site door outside, a way inside; nil: none), found the first time (again once one went).
function WalkIn.leavesOf(s: Session, door: any, inside: boolean): { Instance }
	if not door or not T.Doors.Swing then
		return WalkIn.none
	end
	local known = WalkIn.leaves[door]
	if known then
		local whole = true
		for _, leaf in known do
			whole = whole and leaf.Parent ~= nil
		end
		if whole then
			return known
		end
	end
	local found = if inside
		then WalkIn.find(s.interior, door.inside, (door.width or 4) / 2 + 2)
		else WalkIn.find(workspace, door.door, door.width / 2 + 2)
	WalkIn.leaves[door] = found
	return found
end

-- Somebody wants these leaves open now: open from now (DoorOpen) until Shut s after the last want. 8.5.1: and since
-- when, in the server's time (DoorOpenAt: a client that first sees it open swings it on from where it is now).
function WalkIn.open(leaves: { Instance }, clock: number)
	for _, leaf in leaves do
		WalkIn.want[leaf] = clock
		if not WalkIn.opened[leaf] then
			WalkIn.opened[leaf] = clock
			leaf:SetAttribute("DoorOpenAt", workspace:GetServerTimeNow())
			leaf:SetAttribute("DoorOpen", true)
		end
	end
end

-- 8.5.1 (the owner: "I'd like them to open nicely"): has every one of these leaves been swinging open Seen × Open s
-- (most of its swing seen before the fade darkens the screen)? No leaf: yes.
function WalkIn.swung(leaves: { Instance }, clock: number): boolean
	for _, leaf in leaves do
		local at = WalkIn.opened[leaf]
		if at == nil or clock - at < T.Doors.Open * T.Doors.Seen then
			return false
		end
	end
	return true
end

-- The leaves nobody wanted open for Shut s shut again (DoorOpen false); gone ones forgotten.
function WalkIn.sweep(clock: number)
	for leaf, at in WalkIn.want do
		if leaf.Parent == nil then
			WalkIn.want[leaf], WalkIn.opened[leaf] = nil, nil
		elseif clock - at >= T.Doors.Shut then
			WalkIn.want[leaf], WalkIn.opened[leaf] = nil, nil
			leaf:SetAttribute("DoorOpen", false)
		end
	end
end

-- May a crew member who has faced the door since `since` go through it now? Dwell s in its zone, and its leaves open
-- Open s (they swing open first); a door without a leaf: Open s since the dwell's start, as if it had one.
function WalkIn.ready(leaves: { Instance }, clock: number, since: number): boolean
	local opened = since
	if #leaves > 0 then
		opened = -math.huge
		for _, leaf in leaves do
			opened = math.max(opened, WalkIn.opened[leaf] or clock)
		end
	end
	return clock - since >= T.Doors.Dwell and clock - opened >= T.Doors.Open
end

-- Danny (server/MoveHelper.luau; 10.1 any helper of the crew), near a door opens it too, whichever
-- way he faces (he goes through it his own way): the front door, the back door, inside and out.
function WalkIn.helper(s: Session, clock: number)
	local h = MoveHelper.find(s.owner)
	local body = if h and h.hirer then h.body else nil
	local root = if body then body.root else nil
	if typeof(root) ~= "Instance" or not root:IsA("BasePart") or root.Parent == nil then
		return
	end
	local at = root.Position
	local index = WalkIn.zoneOf(s, at, true, T.Doors.Approach, T.Doors.ApproachSide)
	if index then
		WalkIn.open(WalkIn.leavesOf(s, s.ways[index], true), clock)
		return
	end
	index = WalkIn.zoneOf(s, at, false, T.Doors.Approach, T.Doors.ApproachSide)
	if index then
		WalkIn.open(WalkIn.leavesOf(s, s.site.doors[index], false), clock)
	end
end

-- The trip's moment in the dark (travel's, FadeOut + Margin s after the fade out): `player` at `target` (their root
-- their hips over it, facing on), the crew mate of the trip (`party`'s second) at the pair piece's far end as it stands
-- in front of `player` (their hold's place, else where they stood from `player`); the walk `speed` carried on the way
-- they face; the door there opens behind them (it shuts Shut s later). Danny at that far end comes by his own hold's
-- next step (server/MoveHelper.luau: the piece in the other world puts him there at once, within Config.MoveHelper.Tick
-- s, inside the client's Dark). The move ended (or its house went) while the screen was dark: out at the house's door,
-- never the void. Returns, by player, where each one is now and the way they face, for the fade in (the client's dark
-- lasts until it sees them there).
function WalkIn.trip(s: Session, player: Player, target: CFrame, inside: boolean, party: { Player }, speed: number): { [Player]: any }
	local D = T.Doors
	local arrived: { [Player]: any } = {}
	local goal, goalInside = target, inside
	if inside and (s.ended or not (s.interior and s.interior.Parent)) then
		goal, goalInside = s.site.outside, false
	end
	local character, humanoid, root = bodyOf(player)
	if not character or not humanoid or not root then
		return arrived
	end
	-- the far end's place in front of you (the piece where you hold it, its far end where its hold keeps the other one:
	-- it comes along lined up; else where they stand from you)
	local before = root.CFrame
	local spot, role = Rules.holding(s.move, player.UserId)
	local thing = if spot then s.move.things[spot] else nil
	local item = if spot then s.items[spot] else nil
	local held = if thing and role == "carrier" then holdOffset(thing, Rules.mode(thing), root, humanoid) else nil
	local mate = party[2]
	local mateAt: CFrame? = nil
	if mate and spot and Rules.holding(s.move, mate.UserId) == spot then
		local hold = require(script.Parent.PairHold).of(mate)
		local _, _, mateRoot = bodyOf(mate)
		if hold and held and item and hold.anchor == item.root then
			local far = held * hold.offset -- (at your root's height, as the hold keeps them)
			mateAt = CFrame.new(far.X, 0, far.Z) * far.Rotation
		elseif mateRoot then
			mateAt = before:ToObjectSpace(mateRoot.CFrame)
		end
	end

	local function land(who: Player, body: Model, at: CFrame)
		body:PivotTo(at)
		local _, _, whoRoot = bodyOf(who)
		if whoRoot then
			whoRoot.AssemblyLinearVelocity = goal.LookVector * speed -- (still walking, the way they face now)
			local look = whoRoot.CFrame.LookVector
			arrived[who] = { at = whoRoot.Position, look = Vector3.new(look.X, 0, look.Z), dark = D.Dark, wait = D.Wait, near = D.Arrive }
		end
		if goalInside then
			s.inside[who] = true
			SB.tell("enter", s, who) -- 8.2: the listeners (Moving.onEnterHouse)
		else
			s.inside[who] = nil
		end
	end
	local now = goal + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	land(player, character, now)
	if item then
		item.lastAt, item.fallFrom, item.apartSince = nil, nil, nil
	end
	local mateBody = if mate then mate.Character else nil
	if mate and mateBody and mateAt then
		land(mate, mateBody, now * mateAt)
	end
	WalkIn.open(WalkIn.leavesOf(s, WalkIn.doorNear(s, now.Position, goalInside), goalInside), os.clock()) -- (behind them)
	return arrived
end

-- ── Doors: in and out with a fade ──────────────────────────────────────────
-- 8.3 the trip (Config.Moving.Doors; the owner: "the door should open, and then it teleports me smoothly"): the door
-- you go by opens (an E prompt's trip too) and the fade out starts (FadeOut s on the client) for you and the crew mate
-- at the other end of the pair piece you hold; the other side streams in meanwhile (each one's
-- RequestStreamAroundAsync, Stream s at most). FadeOut + Margin s after the fade out was sent (the screen black on the
-- client by then, whatever the network's unevenness) everybody of the trip is moved in one moment (WalkIn.trip), and
-- the fade in carries where you are and the way you face: the client holds the dark until it sees you there, its
-- camera behind you, then Dark s, then FadeIn s (client/Fade.luau). (8.3 review: Stream stays 2, not 7.0's 4: the
-- trip's worst case, FadeOut + Margin + Stream, must end before client/Fade.luau lifts an unanswered black by itself,
-- HOLD 4 s after its FadeOut; a stream done sooner moves you sooner, the big house's rest streams in round you there.)

local travel: (Player, CFrame, Session, boolean) -> ()

travel = function(player: Player, target: CFrame, s: Session, inside: boolean)
	if traveling[player] then
		return
	end
	local D = T.Doors
	-- the trip's party: you, and the crew mate at the other end of your pair piece (Danny there: his hold's own step)
	local spot, role = Rules.holding(s.move, player.UserId)
	local thing = if spot then s.move.things[spot] else nil
	local other = if thing then playerById(if role == "carrier" then thing.helper else thing.carrier) else nil
	local party = { player }
	if other and other ~= player and not traveling[other] then
		table.insert(party, other)
	end
	local _, _, root = bodyOf(player)
	local from = s.inside[player] == true
	WalkIn.open(WalkIn.leavesOf(s, if root then WalkIn.doorNear(s, root.Position, from) else nil, from), os.clock()) -- (the door you go by)
	local speed = 0 -- (your walk now, carried on there)
	local v: Vector3? = if root then root.AssemblyLinearVelocity else nil
	if v then
		speed = math.sqrt(v.X * v.X + v.Z * v.Z)
	end
	local streamed = 0
	for _, member in party do
		traveling[member] = true
		remote:FireClient(member, "fade", "out", D.FadeOut)
		task.delay(0, function()
			pcall(function()
				member:RequestStreamAroundAsync(target.Position, D.Stream)
			end)
			streamed += 1
		end)
	end
	task.delay(D.FadeOut + D.Margin, function()
		-- (7.0 review: in a pcall; whatever happens the trip is over and the fade lifts)
		local arrived: { [Player]: any } = {}
		local ok, err = pcall(function()
			local waited = 0
			while streamed < #party and waited < D.Stream do -- (the stream's own wait, Stream s at most)
				waited += math.max(task.wait(0.05), 0.05)
			end
			arrived = WalkIn.trip(s, player, target, inside, party, speed)
		end)
		if not ok then
			warn(`[Moving] a door trip failed: {err}`)
		end
		local push = WalkIn.send -- (where you are now, before the fade in: the HUD, the sounds and the eyes while black)
		if push and not s.ended then
			pcall(push, s)
		end
		for _, member in party do
			traveling[member] = nil
			-- 8.1 walk-in doors: no way back until they stepped out of the zone here (come out clear of it: out already,
			-- judged by WalkIn.check from where they came out) and Rearm s went by
			local _, _, body = bodyOf(member)
			WalkIn.at[member] = nil
			WalkIn.held[member] = { untilAt = os.clock() + D.Rearm, left = nil, from = if body then body.Position else nil }
			if member.Parent then
				remote:FireClient(member, "fade", "in", D.FadeIn, arrived[member])
			end
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
		say(player, "Locked: this house is another party's run.")
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

-- ── 8.1 walk-in doors: through a door by walking into it (Config.Moving.Doors) ─────────────────────────────────────
-- The zones are boxes at the doorways: outside one in front of every door of the site (at its foot, out of it along
-- its facing), inside one at every way out (at its exit, a body's height over the floor, into the room toward where
-- you come in by it). A crew member on foot standing in one Dwell s facing its door goes through it (8.5: or walking
-- on into its doorway, at once): onEnter / onLeave, their checks, words and fade (what they carry and a pair piece's
-- other end come along).

-- Is `at` in a doorway's zone: `mid` its threshold at a body's middle, `out` the flat way out of it on the side you
-- stand (outside: the door's facing; inside: into the room), `width` the doorway's? Depth in front of it, Through
-- through it, Side past its jambs, Height round the middle. 8.3: `depth` / `side` given: that box instead (the door's
-- approach: Approach deep, ApproachSide wider).
function WalkIn.inZone(at: Vector3, mid: Vector3, out: Vector3, width: number, depth: number?, side: number?): boolean
	local D = T.Doors
	local dx, dz = at.X - mid.X, at.Z - mid.Z
	local along = dx * out.X + dz * out.Z
	return along <= (depth or D.Depth) and along >= -D.Through and math.abs(dx * out.Z - dz * out.X) <= width / 2 + D.Side + (side or 0)
		and math.abs(at.Y - mid.Y) <= D.Height / 2
end

-- 8.5: door `index`'s doorway on that side (inside: way `index`'s; outside: the site's door `index`'s) as the zones
-- see it: its threshold at a body's middle (outside: the door's foot a root's height up; inside: its exit), the flat
-- way out of it on that side and its width; nil: none (a way without its zone yet).
function WalkIn.frame(s: Session, index: number, inside: boolean): (Vector3?, Vector3?, number)
	if inside then
		local way = s.ways[index]
		if not way or not way.into then
			return nil, nil, 0
		end
		return way.inside, way.into, way.width or way.part.Size.X
	end
	local door = s.site.doors[index]
	if not door then
		return nil, nil, 0
	end
	return door.door + Vector3.new(0, Config.Furniture.EntryUp, 0), door.facing, door.width -- (the door's foot is on the ground)
end

-- The zone a body at `at` stands in (inside: the ways out's; outside: the site's doors'): its index and its flat way
-- out of the doorway on that side, or nil. 8.3: `depth` / `side` given: the door's approach (WalkIn.inZone).
function WalkIn.zoneOf(s: Session, at: Vector3, inside: boolean, depth: number?, side: number?): (number?, Vector3?)
	for index in (if inside then s.ways else s.site.doors) :: { any } do
		local mid, out, width = WalkIn.frame(s, index, inside)
		if mid and out and WalkIn.inZone(at, mid, out, width, depth, side) then
			return index, out
		end
	end
	return nil, nil
end

-- 8.5 walking through: how fast a body walks into a doorway (`out`: its flat way out on the side it stands): its flat
-- walk's share toward it, studs/s, when it heads at it (within Face of straight at it); 0 when it walks along it, away
-- from it or stands.
function WalkIn.into(root: BasePart, out: Vector3): number
	local v: Vector3? = root.AssemblyLinearVelocity
	if not v then
		return 0
	end
	local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
	local into = -(v.X * out.X + v.Z * out.Z)
	return if speed > 1e-3 and into >= T.Doors.Face * speed then into else 0
end

-- 8.5: the door a body comes at on its side (its index; nil: none), the one whose leaf opens for it: in the door's
-- approach (Approach deep, ApproachSide wider than its zone) facing it or walking at it (PairWalk studs/s or more), or
-- farther out walking at its doorway: its walk crosses the doorway's face within the approach's width in Lead s (a run
-- finds the leaf open).
function WalkIn.coming(s: Session, character: Model?, root: BasePart, inside: boolean): number?
	local D = T.Doors
	local at = root.Position
	for index in (if inside then s.ways else s.site.doors) :: { any } do
		local mid, out, width = WalkIn.frame(s, index, inside)
		if not mid or not out then
			continue
		end
		local speed = WalkIn.into(root, out)
		if WalkIn.inZone(at, mid, out, width, D.Approach, D.ApproachSide) and (speed >= D.PairWalk or WalkIn.toward(character, root, out) >= D.Face) then
			return index
		end
		local dx, dz = at.X - mid.X, at.Z - mid.Z
		local along = dx * out.X + dz * out.Z
		local v: Vector3? = root.AssemblyLinearVelocity
		if v and speed >= D.PairWalk and along > 0 and along <= speed * D.Lead and math.abs(at.Y - mid.Y) <= D.Height / 2 then
			local t = along / speed -- (when it reaches the doorway's face, and where across it)
			if math.abs((dx + v.X * t) * out.Z - (dz + v.Z * t) * out.X) <= width / 2 + D.Side + D.ApproachSide then
				return index
			end
		end
	end
	return nil
end

-- Through door `index` on that side: out by a way inside (onLeave), in by a site door outside (onEnter).
function WalkIn.go(s: Session, player: Player, index: number, inside: boolean)
	if inside then
		onLeave(player, s, index)
	else
		onEnter(player, s.contract.id, index)
	end
end

-- How much a body faces the way through a door (`out`: its flat way out on the side they stand): the root's look ·
-- the way in (1 straight at it, -1 away from it). 8.1 carrying in two (PairTurn): a leader backs through it, facing the
-- piece and the partner: their walk into it counts then, only at PairWalk studs/s or more (8.1 review: a drift back
-- toward the door no longer takes them through).
function WalkIn.toward(character: Model?, root: BasePart, out: Vector3): number
	local look = root.CFrame.LookVector
	local toward = -(look.X * out.X + look.Z * out.Z)
	if toward < T.Doors.Face and character and character:GetAttribute("PairTurn") ~= nil then
		local v: Vector3? = root.AssemblyLinearVelocity
		local speed = if v then math.sqrt(v.X * v.X + v.Z * v.Z) else 0
		toward = if v and speed >= T.Doors.PairWalk then -(v.X * out.X + v.Z * out.Z) / speed else -1
	end
	return toward
end

-- One look at a crew member (WalkIn.look): on foot in a zone, facing its door (Face) for Dwell s: through it, once a
-- visit (a refusal is said once; out of the zone and in again tries again). 8.1 carrying in two (PairTurn): the back
-- to the door counts too (the leader walks backwards through it, facing the piece and the partner). After a trip nothing until they have left
-- the zone they came out in and Rearm s have gone by (WalkIn.held, set by travel). 8.3: walking up to a door facing it
-- (its approach) opens its leaf, and the trip waits until it has been open Open s (WalkIn.ready). 8.5 walking through
-- (the owner: "I keep walking smoothly, and then the transition"): the leaf opens as they come at it (WalkIn.coming),
-- and walking into the doorway is the trip: their walk at it (PairWalk studs/s or more, within Face of straight at it)
-- takes their root across its threshold (Cross studs out of its face) now or within Ahead s (the server sees them a
-- moment late, its looks Every s apart): through at once, no dwell, no wait for the leaf (open long before; 8.5.1 from
-- just beside the door, until it has swung Seen × Open s: WalkIn.swung). The dwell stays for standing at a door.
function WalkIn.check(s: Session, player: Player, clock: number)
	local character, humanoid, root = bodyOf(player)
	if not humanoid or not root or humanoid.SeatPart or traveling[player] then
		WalkIn.at[player] = nil
		return
	end
	local D = T.Doors
	local inside = s.inside[player] == true
	local index, out = WalkIn.zoneOf(s, root.Position, inside)
	local hold = WalkIn.held[player]
	if hold then
		if hold.left == nil then -- (the first look since the trip: did they come out clear of every zone?)
			local from = hold.from
			hold.left = from == nil or WalkIn.zoneOf(s, from, inside) == nil
		end
		hold.left = hold.left or index == nil
		if not hold.left or clock < hold.untilAt then
			WalkIn.at[player] = nil
			return
		end
		WalkIn.held[player] = nil
	end
	-- 8.3 the leaf swings open as they walk up to the door facing it (its approach: the zone, deeper and wider); 8.5 as
	-- they come at it (walking at it too, from farther at a run: WalkIn.coming)
	local near = WalkIn.coming(s, character, root, inside)
	if near then
		WalkIn.open(WalkIn.leavesOf(s, if inside then s.ways[near] else s.site.doors[near], inside), clock)
	end
	if not index or not out then
		WalkIn.at[player] = nil
		return
	end
	local key = if inside then index else 100 + index
	local visit = WalkIn.at[player]
	if not visit or visit.key ~= key then
		local fresh = { key = key, since = nil :: number?, tried = false }
		WalkIn.at[player] = fresh
		visit = fresh
	end
	-- 8.5 walking through: their walk into the doorway takes their root across its threshold (now, or within Ahead s);
	-- 8.5.1 once its leaf has swung most of the way (WalkIn.swung: from just beside the door, a moment's wait)
	local mid = WalkIn.frame(s, index, inside)
	local speed = WalkIn.into(root, out)
	if mid and not visit.tried and speed >= D.PairWalk
		and (root.Position.X - mid.X) * out.X + (root.Position.Z - mid.Z) * out.Z - speed * D.Ahead <= D.Cross
		and WalkIn.swung(WalkIn.leavesOf(s, if inside then s.ways[index] else s.site.doors[index], inside), clock) then
		visit.tried = true
		WalkIn.go(s, player, index, inside)
		return
	end
	if WalkIn.toward(character, root, out) < D.Face then
		visit.since = nil -- (facing away, or walking past it: the dwell starts when they turn to the door)
		return
	end
	local since = visit.since
	if since == nil then
		visit.since = clock
	elseif not visit.tried and WalkIn.ready(WalkIn.leavesOf(s, if inside then s.ways[index] else s.site.doors[index], inside), clock, since) then
		visit.tried = true
		WalkIn.go(s, player, index, inside)
	end
end

-- The move's crew at its doors: every member's look (the tick's, and Moving.doors' between two ticks). 8.3: the
-- leaves nobody wants open any more shut (WalkIn.sweep), Danny near a door opens it (WalkIn.helper).
function WalkIn.look(s: Session, clock: number)
	WalkIn.sweep(clock)
	if not T.Doors.Walk then
		return
	end
	for player in s.members do
		if s.ended then
			return
		end
		WalkIn.check(s, player, clock)
	end
	WalkIn.helper(s, clock)
end

-- A doormat on the ground: its middle `at` (on the floor), the door `toward` it (flat), the doorway's `width`; its words
-- read upright to whoever walks at the door. Light: no collision, no query, no shadow.
function WalkIn.mat(parent: Instance, at: Vector3, toward: Vector3, width: number, text: string): BasePart
	local size = T.Doors.Mat
	local up = Vector3.new(0, 0.12, 0) -- (over a garden path's top or a rug)
	local part = Instance.new("Part")
	part.Name = "WalkInMat"
	part.Size = Vector3.new(math.min(width, size[1]), 0.06, size[2])
	part.CFrame = CFrame.lookAt(at + up, at + up + Vector3.new(toward.X, 0, toward.Z))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = Color3.fromRGB(96, 72, 50)
	part.Material = Enum.Material.Fabric
	part.TopSurface = Enum.SurfaceType.Smooth
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Words"
	gui.Face = Enum.NormalId.Top -- (its top edge toward the part's front: the door)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.MaxDistance = 120
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.86, 0.6)
	label.Position = UDim2.fromScale(0.07, 0.2)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(240, 226, 196)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	part.Parent = parent
	return part
end

-- A site's doormats outside ("▲ IN" just in front of every door), hidden until a move uses the site (WalkIn.show).
function WalkIn.siteMats(site: Site)
	local list: { BasePart } = {}
	for _, door in site.doors do
		table.insert(list, WalkIn.mat(site.model, door.door + door.facing * (T.Doors.Mat[2] / 2 + 0.3), -door.facing, door.width, "▲ IN"))
	end
	WalkIn.mats[site] = list
end

-- Every site's doormats outside shown while a move that goes on uses it (a move's start and end).
function WalkIn.show()
	for site, list in WalkIn.mats do
		local used = false
		for _, s in sessions do
			used = used or (s.site == site and not s.ended)
		end
		for _, mat in list do
			mat.Transparency = if used then 0 else 1
			local gui = mat:FindFirstChildOfClass("SurfaceGui")
			if gui then
				gui.Enabled = used
			end
		end
	end
end

-- A new move's ways out (startMove): each one's doorway width (the plan's doors to the outside, in the exits' order;
-- else its Leave part's), its flat way into the room (from its exit to where you come in by it: you come in facing
-- that way, away from the door, Danny too) and its doormat inside ("▲ OUT" on the floor just inside the doorway, in the
-- interior: it goes with it). 8.3: every door's leaves of the move found now (the interior's, the site's), shut and
-- tagged before anybody walks up to them.
function WalkIn.ways(s: Session)
	local widths: { number } = {}
	local doors = s.plan.doors
	for _, d in (if type(doors) == "table" then doors else {}) :: { any } do
		if type(d) == "table" and type(d.rooms) == "table" and d.rooms[2] == "outside" and type(d.width) == "number" then
			table.insert(widths, d.width)
		end
	end
	local fallback = (s.origin * Vector3.new(0, 0, 1)) - s.origin.Position -- (the plan's +Z: into the house)
	for index, way in s.ways do
		local step = way.entry.Position - way.inside
		local level = Vector3.new(step.X, 0, step.Z)
		local into = if level.Magnitude > 1e-3 then level.Unit else fallback
		local width = widths[index] or way.part.Size.X
		way.into, way.width = into, width
		way.entry = CFrame.lookAt(way.entry.Position, way.entry.Position + into)
		if T.Doors.Walk then
			local floor = way.inside - Vector3.new(0, Config.Furniture.EntryUp, 0)
			WalkIn.mat(s.interior or folder or workspace, floor + into * (T.Doors.Mat[2] / 2 + 0.3), -into, width, "▲ OUT")
		end
		WalkIn.leavesOf(s, way, true) -- (8.3: its leaves found and tagged now, shut: the clients know them before they swing)
	end
	for _, door in s.site.doors do
		WalkIn.leaves[door] = nil -- (8.3: the site's leaves looked for again, the map's house as it stands now)
		WalkIn.leavesOf(s, door, false)
	end
end

-- ── The things' prompts ────────────────────────────────────────────────────

-- 9.0 (the owner, 8.9: "He must not take things through walls (that's funny), and neither may the player"): is a wall of
-- the move's interior between `from` (a player's root) and the piece's middle? A ray at the interior's Shell only (its
-- walls, floors and ceiling: the furniture, the fixtures and the bodies never block); a piece out of the house, or an
-- interior without a shell: none. Its prompts need a line of sight too (setupItem: RequiresLineOfSight).
function Moving.walled(s: Session, from: Vector3, item: Item): boolean
	local interior = s.interior
	local shell = if interior and interior.Parent then interior:FindFirstChild("Shell") else nil
	if not shell or (from - s.origin.Position).Magnitude > 400 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { shell }
	return workspace:Raycast(from, item.root.Position - from, params) ~= nil
end

local function onPick(s: Session, spot: number, player: Player, lifted: boolean?)
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
	if Moving.walled(s, root.Position, item) then
		say(player, `You can't reach the {thing.name} through the wall.`) -- 9.0 (a pick, a lift, a drag)
		return
	end
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil then
		say(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	local sealed = if s.danger then s.danger.sealed[spot] else nil -- 10.x danger: in the run's vault (server/RunDanger.luau)
	if sealed then
		say(player, sealed)
		return
	end
	-- 8.3 Danny's orders (Config.MoveHelper.WaitForHelper): a two-person piece with Danny on the move calls him, you wait
	-- at your end ("wait"; Lift again: "cancel"); once he is at its far end ("ready") its lift goes on. nil: today's rules
	-- (8.3 review: "busy", a crew mate waits for him at it: refused, never lifted from under their call)
	local answer = if not lifted and thing.class == "pair" then MoveHelper.call(s, player, spot) else nil
	if answer == "wait" or answer == "cancel" or answer == "busy" then
		s.dirty = true
		return
	end
	if not lifted and Grip.liftStart(s, spot, player, false) then
		return -- 8.1 grip: a piece with a grip is lifted by its lift check's hit (the grip block calls this again, lifted)
	end
	local ok, why = Rules.pick(s.move, spot, player.UserId)
	if not ok then
		say(player, SB.why(why))
		return
	end
	carry(s, item)
	MoveHelper.taken(s, spot, player) -- (8.3: off Danny's list, if it was on it)
	if thing.class == "pair" and not MoveHelper.joinLift(s, spot, player) then -- (8.3: lifted with Danny at its far end)
		say(player, `The {thing.name} needs two: you drag it slowly. A crew mate can "Help lift" the other end.`)
	end
	s.dirty = true
end

local function onHelp(s: Session, spot: number, player: Player, lifted: boolean?)
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
	if Moving.walled(s, root.Position, item) then
		say(player, `You can't reach the {thing.name} through the wall.`) -- 9.0 (Help lift)
		return
	end
	if thing.carrier == player.UserId then
		say(player, SB.why("yours"))
		return
	end
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil then
		say(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	if not lifted and Grip.liftStart(s, spot, player, true) then
		return -- 8.1 grip: the other end is taken by its lift check's hit (the grip block calls this again, lifted)
	end
	local ok, why = Rules.help(s.move, spot, player.UserId)
	if not ok then
		say(player, SB.why(why))
		return
	end
	carry(s, item) -- (carried now, not dragged: the carrier's weld and walk change)
	local carrier = playerById(thing.carrier)
	if carrier then
		say(carrier, `{player.DisplayName} took the other end of the {thing.name}: walk together.`)
	end
	say(player, `You hold the other end of the {thing.name}: stay close to it.`)
	s.dirty = true
end

-- 8.3 Danny's orders: his side of your call (server/MoveHelper.luau's call; the gate is onPick's). Where `player` will
-- hold the piece lifted with him (its far end is his place): their root's frame and the pair's hold.
function Moving.helperLiftFrame(s: Session, spot: number, player: Player): CFrame?
	local thing = s.move.things[spot]
	local _, humanoid, root = bodyOrNil(player)
	if not thing or not humanoid or not root then
		return nil
	end
	return root.CFrame * holdOffset(thing, "pair", root, humanoid, true) -- (8.6: as two hold it, lengthwise)
end

-- He is in place: `player`'s lift now (8.6: up at once, him at its far end; Config.MoveHelper.CallCheck true: its check
-- opens, as without the grip it is up). True when the check is open or the piece is up. 8.3 review: that check opened
-- by his arrival, not by a press (maybe half a minute after it), is marked `called`: unanswered it closes without a
-- knock (Grip.tick), the next Lift opens a new one.
function Moving.helperCalled(s: Session, spot: number, player: Player): boolean
	-- 8.6 (the owner: "he does come to me and waits, but it doesn't look good"): Config.MoveHelper.CallCheck false, up at
	-- once on his "On three... lift!" (no lift check after the wait; balanced: he steadies it, the steady walk)
	local check = Config.MoveHelper.CallCheck == true
	onPick(s, spot, player, not check)
	local hold = Grip.holds[player]
	if not check and hold and hold.carrying and hold.spot == spot and s.items[spot] then
		hold.steady = true
		setHands(s, s.items[spot])
	end
	local open = if hold then hold.open else nil
	if hold and open and hold.spot == spot and open.check.what == "lift" then
		open.called = true
	end
	return Rules.holding(s.move, player.UserId) == spot or (hold ~= nil and hold.open ~= nil and hold.spot == spot)
end

-- The piece's Lift prompt while a call is on it or he waits at it for you: "wait" (E again stops waiting), "ask" ("Lift
-- with Danny"), nil (as it was made).
function Moving.helperMark(s: Session, spot: number, how: string?)
	local item = s.items[spot]
	local thing = s.move.things[spot]
	if not item or not thing then
		return
	end
	local verb = if thing.class == "pair" then "Lift" else "Pick up"
	local helper = MoveHelper.find(s.owner) -- (10.1 the crew's helper: his own name)
	local name = if helper then helper.name else Config.MoveHelper.Name
	item.pick.ActionText = if how == "wait" then "Stop waiting" elseif how == "ask" then `{verb} with {name}` else verb
	item.pick.ObjectText = if how == "wait" then `Waiting for {name}…` else labelOf(thing)
end

-- The call is off once he was in place (G, walked away, him down): `player`'s lift check on it, still open, closes
-- (no outcome: never a lift alone after).
function Moving.helperCallOff(s: Session, spot: number, player: Player)
	local hold = Grip.holds[player]
	local open = if hold then hold.open else nil
	if hold and open and hold.session == s.id and open.spot == spot and open.check.what == "lift" and not hold.carrying then
		Grip.close(player, hold)
		Grip.holds[player] = nil
	end
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
	pick.RequiresLineOfSight = true -- 9.0 (never offered through a wall; the server checks it again: Moving.walled)
	help.RequiresLineOfSight = true
	tag(pick, s.owner)
	tag(help, s.owner)
	pick.Triggered:Connect(function(player: Player)
		onPick(s, spot, player)
	end)
	help.Triggered:Connect(function(player: Player)
		onHelp(s, spot, player)
	end)
	model:SetAttribute("MoveSpot", spot)
	require(script.Parent.Loot).tag(model, spot, s) -- 9.x loot: its rarity, stars and value (server/Loot.luau)
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

-- ── The party on a run (8.8 no roles: everybody does everything) ──────────

local R = Config.MoveRoles -- (the van call's Driver.Near, the climb's Mover.Hold: the numbers stayed there)

-- "Enter house" at the house's front door: this run's own, for its party only (MoveOwner); the door is never locked.
-- One at every door of the site (the farmstead's back door too: "Enter by the back door"), each to its own way in
-- (onEnter's index); the front door's is team.enter, the others team.doors.
local function enterPrompt(s: Session)
	local front = SB.frontDoor(s.contract.id) -- (on the map's front door once it has one: its house's)
	if front then
		s.site.doors[1].part = front
	end
	for index, door in s.site.doors do
		local spot = door.part
		if not spot then
			continue
		end
		local action = if index == 1 then "Enter house" else `Enter by the {door.name}`
		local enter = newPrompt(spot, action, `{s.contract.icon} {s.contract.name}`, Enum.KeyCode.E, 0, T.Reach.Door + door.width / 2)
		enter.Enabled = not T.Doors.Walk -- (8.1 walk-in doors: you walk in; the prompt stays, off)
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

-- The site's door nearest a player (inside: the nearest way out's), and how far.
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

-- "Call the van to the door" (the Moving remote's "call"; once a run, whoever is first): the empty van to the curb of
-- the site's door nearest the caller, its back to the door, with a fade for the caller.
local function callTruck(s: Session, player: Player)
	if s.team.called then
		say(player, MoveRoles.whyText("called"))
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

-- A carried thing going up stairs or a slope (its carrier rose Mover.Rise a stud along, held Hold s): its walk ×
-- Mover.Climb (not a thing in one hand: MoveRoles.climbFactor); watchCarried calls it every tick.
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
	local slow = clock < c.upUntil and MoveRoles.climbFactor(nil, Rules.mode(thing)) < 1
	if slow ~= c.slow then
		c.slow = slow
		local item = s.items[spot]
		if item then
			setHands(s, item)
		end
	end
end

-- The run's Enter prompts go with it.
local function teamCleanup(s: Session)
	local team = s.team
	if team.enter then
		team.enter:Destroy()
		team.enter = nil
	end
	for _, prompt in team.doors do
		prompt:Destroy()
	end
	table.clear(team.doors)
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
	local drop = SB.dropAt(s) -- (the host's plot's unload circle)
	local hordeAt = s.move.hordeAt or T.HordeAt -- (the contract's own: Config.Sandbox's, 0 none)
	return {
		id = s.id,
		contract = s.contract.id,
		name = s.contract.name,
		icon = s.contract.icon,
		client = s.contract.client,
		owner = s.owner.DisplayName,
		mine = player == s.owner and not s.contract.round, -- (10.5 rounds: nobody's own: no FINISH, no GIVE UP)
		endsAt = s.move.endsAt,
		hordeAt = if hordeAt > 0 then s.move.endsAt - hordeAt else nil,
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
		drop = "your warehouse", -- (the drop-off in the HUD's words)
		inside = s.inside[player] == true,
		team = { called = s.team.called }, -- (8.8 no roles: the van called to the door once a run)
		trips = s.move.trips or 0,
		vanAgainAt = if s.lostAt then s.lostAt + T.VanAgain else nil, -- (the van lost: CAR again then)
		run = if s.contract.difficulty then SB.runView(s, player) else nil, -- 9.7 runs: the run's difficulty, its host
	}
end

-- 9.7 runs: what the move's HUD shows of a run (client/MovingHud.luau: no trips, no drive; the host's FINISH, the
-- others' VOTE FINISH and LEAVE THE RUN).
function SB.runView(s: Session, player: Player): { [string]: any }
	local def = require(Shared.RunRules).def(s.contract.difficulty)
	if s.contract.round then -- 10.5 rounds: no host, no FINISH; what you loaded into your own van
		local mine = (s.claims or {})[player.UserId]
		return { difficulty = s.contract.difficulty, name = if def then def.name else "", host = "", mine = false, round = true,
			count = if mine then mine.count else 0, value = if mine then mine.value else 0 }
	end
	return { difficulty = s.contract.difficulty, name = if def then def.name else "", host = s.owner.DisplayName, mine = player == s.owner }
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
	-- 8.3 review: the interior goes once the door trips are over: somebody of the crew on one now (those sent out just
	-- above: travel moves them FadeOut + Margin s after the fade out, and up to Stream s later while the street streams
	-- in), not before FadeOut + Margin + Stream + 0.5 s, and a moment more while one is still on it (a lagging server,
	-- Stream s at most): never the floor gone under somebody in the dark. Nobody on a trip: T.Fade + 0.5 s, as ever.
	local D = T.Doors
	local function tripping(): boolean
		for member in s.members do
			if traveling[member] then
				return true
			end
		end
		for member in s.inside do
			if traveling[member] then
				return true
			end
		end
		return false
	end
	task.delay(if tripping() then math.max(T.Fade, D.FadeOut + D.Margin + D.Stream) + 0.5 else T.Fade + 0.5, function()
		local waited = 0
		while tripping() and waited < D.Stream do
			waited += math.max(task.wait(0.1), 0.1)
		end
		-- the interior first (server/HouseInterior.luau's own way), then the things that left it (carried, set down
		-- outside, in the truck: gone home)
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
	local takeOut = if s.unload then s.unload.Parent else nil -- (Unload's own attachment on the truck)
	local bay = if s.loadIn then s.loadIn.Parent else nil -- (8.0 SANDBOX: the walk-in bay's Load's own)
	for _, prompt in { s.load, s.unload, s.loadIn } do
		if prompt then
			prompt:Destroy()
		end
	end
	if takeOut and takeOut.Name == "MoveTakeOut" then
		takeOut:Destroy()
	end
	if bay and bay.Name == "MoveLoadBay" then
		bay:Destroy()
	end
	releaseBack(s.truck) -- (7.x van moves: the owner's van's back as it was)
	letGoZombies(s.horde)
	letGoZombies(s.roam)
	teamCleanup(s) -- (the Enter prompts)
	for member in s.members do
		if member:GetAttribute("MoveWith") == s.owner.UserId then
			member:SetAttribute("MoveWith", nil)
		end
	end
	if sessions[s.owner] == s then
		sessions[s.owner] = nil
	end
	WalkIn.show() -- 8.1 walk-in doors: the doormats outside go with the last move at the house
end

local payOut: (Session, string, string?) -> ()

-- A run ends with `event` (deliver, timeout, cancel, lose): what is in the truck goes home first (SB.unloadAll: the
-- event it takes), then the results card (payOut); `why` for the card.
local function finish(s: Session, event: string, why: string?)
	if s.ended then
		return
	end
	event = SB.unloadAll(s, event)
	local phase = Rules.advance(s.move.phase, event)
	if not phase then
		return
	end
	s.move.phase = phase
	s.ended = true -- (7.0 review: ended first; the results in a pcall: the cleanup always runs, the slot frees)
	local paid, err = pcall(function()
		payOut(s, phase, why)
	end)
	if not paid then
		warn(`[Moving] {s.contract.id}: the end's results failed: {err}`)
		for _, member in everyone(s) do
			remote:FireClient(member, "state", nil)
		end
	end
	SB.tell("finish", s, s.owner, { event = event, why = why }) -- 8.2: the listeners (Moving.onFinish)
	cleanup(s)
end

-- The end's results (finish's, in a pcall): the things whose model went never count; no pay, no XP (the warehouse
-- earns): the run's results card (SB.runResult).
payOut = function(s: Session, phase: string, why: string?)
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local item = s.items[spot]
		if (thing.state == "truck" or thing.state == "carried") and (not item or not item.model.Parent) then
			thing.state, thing.carrier, thing.helper, thing.place = "ground", nil, nil, nil
		end
	end
	SB.runResult(s, phase, why, Rules.result(s.move, phase, now()))
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
	if not artNow() then
		return "Moving is not ready in this place yet (the house art is missing)."
	end
	if not freeSlot() then
		return "Every moving crew is out right now: try again in a minute."
	end
	if not SB.plotOf(owner) then
		return "You have no warehouse here (every plot is taken): nowhere to bring the things."
	end
	return nil
end

-- 7.0 review: a house's plan and its facts, made once per seed (shared/HouseLayout.luau's plan is the same for its
-- seed every time and takes tens of ms): every run on it uses them (read only).
type Facts = { plan: any, defs: { [string]: Rules.ItemDef }, spots: { Rules.Spot }, stars: { string }, count: number, estimate: number }

local function factsOf(contract: Contract, a: Art, owner: Player?): Facts?
	local key = `{contract.id}#{contract.seed}` -- (a house per seed)
	local known = contractFacts[key]
	if known then
		return known
	end
	-- 8.3 economy: a house that rolls a legendary tries the ones the host's collection book lacks first (`owner`: the
	-- run's host; their seed is theirs alone, so its facts are too)
	local profile = if owner then PlayerData.get(owner) else nil
	local book = if profile then (profile :: any).collectionBook else nil
	local ok, plan = pcall(function(): any
		return a.layout.plan(contract.seed, contract.kind, if type(book) == "table" then book else nil)
	end)
	if not ok or type(plan) ~= "table" then
		warn(`[Moving] the plan of {contract.id} failed: {plan}`)
		return nil
	end
	local defs = defsOf(a)
	local spots = spotsOf(plan)
	local stars: { string } = {}
	local count, worth = 0, 0
	for _, spot in spots do
		local def = defs[spot.item]
		if def then
			count += 1
			worth += def.value
			if spot.star then
				table.insert(stars, `{def.icon} {def.name}`)
			end
		end
	end
	-- (no pay per piece: what the house holds, every piece's value)
	local made: Facts = { plan = plan, defs = defs, spots = spots, stars = stars, count = count, estimate = worth }
	contractFacts[key] = made
	return made
end

-- A run's move on `contract` (Moving.startRun's: its seed, clock and difficulty set) with the host's van at the door.
local function startMove(owner: Player, contract: Contract): string?
	local site = sites[contract.id]
	if not site then
		return "No such house."
	end
	local busy = cantStart(owner)
	if busy then
		return busy
	end
	local a = artNow() :: Art
	local slot = freeSlot() :: number
	local known = factsOf(contract, a, owner)
	if not known then
		SB.forget(owner) -- (the next try plans another house)
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
	if contract.difficulty then -- 9.7 runs: the run's difficulty on its inside (traps, zombies and the loot read it)
		(interior :: Model):SetAttribute("RunDifficulty", contract.difficulty)
	end
	-- the host's own van (parked at the house's curb by server/Runs.luau; else it comes there now: SB.bringVan)
	local truck = Vehicles.get(owner)
	if not truck or truck.wrecked or not (truck.id == T.Van or Vehicles.hasBack(truck)) then
		local err = SB.bringVan(owner, SandboxMap.house(contract.id))
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
		move = Rules.newMove(known.spots, known.defs, rulesBed(truck), now(), contract.time or T.Time, contract.hordeAt),
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
		team = newTeam(),
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
		leave.Enabled = not T.Doors.Walk -- (8.1 walk-in doors: you walk out; the prompt stays, off)
		leave.Triggered:Connect(function(player: Player)
			onLeave(player, s, index)
		end)
		if index == 1 then
			s.exit = part
		end
		table.insert(s.ways, { exit = index, part = part, inside = exitAt.Position, entry = origin * (entries[index] or plan.entry), door = door })
	end
	WalkIn.ways(s) -- 8.1 walk-in doors: the ways' zones and their doormats inside
	truckPrompts(s)
	tellAll(s, SB.runStartText(s)) -- 9.7 runs: no driving, the truck at the door
	enterPrompt(s) -- (the house's Enter prompts)
	WalkIn.show() -- 8.1 walk-in doors: the house's doormats outside
	SB.tell("start", s, owner) -- 8.2: the listeners (Moving.onStart)
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
	tellAll(s, `🧟 A HORDE is coming to {s.contract.name}! Load what you can into the truck and FINISH!`)
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
	for _ = 1, T.Sandbox.Roam - #s.roam do -- (Config.Moving.Sandbox.Roam: the test world's few; 0: none)
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
end

-- The carried things: a helper too far for Grace s, a carrier faster than the carry (a teleport), a fall's top; 8.1
-- grip: the checks' clocks and their timeouts first (Grip.tick, the grip block); 8.1 carrying in two: the helper held
-- at the far end (PairHold.follow).
local function watchCarried(s: Session, clock: number)
	Grip.tick(s, now())
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
		climbStep(s, spot, holder, root, clock) -- (slower up stairs and slopes)
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
			-- 8.1 carrying in two: the crew mate held at the far end by the server, as Danny is (server/PairHold.luau: never
			-- put there but through a door's fade, eased back when stuck); the tether waits for that ease too
			local grace = T.Grace
			if helperRoot and require(script.Parent.PairHold).follow(helper, helperRoot, item.root, thing.size, root, holder, traveling[helper] == true or traveling[holder] == true) then
				grace += Config.MoveHelper.HoldStuck + Config.MoveHelper.HoldEase
			end
			if helperRoot and flat(helperRoot.Position, item.root.Position) > reach and not traveling[helper] then
				item.apartSince = item.apartSince or clock
				if clock - (item.apartSince :: number) > grace then
					release(s, holder, "apart")
				end
			else
				item.apartSince = nil
			end
		end
	end
end

-- ── The truck's load home, FINISH ─────────────────────────────────────────────────────────────────────────────────

-- The truck's pieces into their loaders' warehouse stocks (server/Collection.luau Collection.add, one a piece: its item,
-- its colours' variant from the plan, its condition, its name; 9.x its loot rarity, server/Loot.luau's); how many it
-- took (refused: no save yet).
function SB.store(s: Session, spots: { number }): number
	local Collection = require(script.Parent.Collection)
	local took = 0
	for _, spot in spots do
		local thing = s.move.things[spot]
		local variant = 1
		for _, planned in (s.plan.spots :: { any }) do
			if planned.id == spot and type(planned.variant) == "number" then
				variant = planned.variant
			end
		end
		local to = SB.stockFor(s, spot) -- (9.7 runs: whoever loaded it, else the host)
		local ok, uid = pcall(Collection.add, to, { item = thing.item, variant = variant, condition = thing.condition, name = thing.name, rarity = (thing :: any).rarity }) -- (9.x loot: server/Loot.luau's)
		if ok and uid ~= nil then
			took += 1
			local home = s.homeTo or {}
			home[spot] = to.UserId
			s.homeTo = home
		else
			if not ok then
				warn(`[Moving] Collection.add of {thing.item}: {uid}`)
			end
			-- (8.2 e2e: refused (a full warehouse): it never came home, so the result, the facts and the tasks do not
			-- count it; its model is gone with the trip; its condition kept: lost, not broken)
			thing.state, thing.place = "lost", nil
			s.dirty = true
		end
	end
	if #spots > 0 then for _, fn in SB.listeners.stored do task.spawn(fn, s.owner, s.move, spots) end end -- 8.2: Moving.onStored
	if took > 0 then
		SB.forget(s.owner) -- 8.3 economy: something came home: this house is spent, the owner's next card shows a new one
	end
	return took
end

-- The host's FINISH (the Moving remote's "finish": client/MovingHud.luau asks twice): what is in the truck goes home.
local function finishMove(player: Player)
	local s = sessions[player]
	if not s or s.ended then
		return
	end
	if s.contract.round then
		say(player, "⏱ The round ends when its clock runs out.") -- 10.5 rounds: nobody finishes it
		return
	end
	finish(s, "deliver", "Finished: what was in the truck went home") -- 9.7 runs: the host's FINISH (SB.unloadAll)
end

-- ── 9.7 RUNS (server/Runs.luau: the lobby's portals; Config.Runs, shared/RunRules.luau) ───────────────────────────
-- A run is a sandbox move whose contract has a difficulty: one house, its party the host's (Runs wraps Crew.members and
-- Crew.ownerOf), its truck the host's van parked at the house's curb (Runs parks it there before Moving.startRun: no
-- driving). Nothing is unloaded at a plot: at the run's end (the host's FINISH, the party's vote, the clock, GIVE UP,
-- the host gone) everything in the truck goes home at once (SB.unloadAll), each piece into the stock of whoever loaded
-- it last (SB.loaded: the helper's loads the host's; one who left the game: the host's), and Runs shows the results card
-- (Moving.onRunEnd) and takes the party back to the lobby.
--   Moving.startRun(host, house, difficulty)   the run's move: its contract (the house's, the host's card's seed for it
--                             while unspent, else a new one; its clock RunRules.time; contract.difficulty) started
--                             as the admin's start (no card, no planning) → an error text or nil
--   Moving.endRun(host, why)  the host's run ends now (FINISH, the vote, the host leaving it): true when one ended
--   Moving.onRunEnd(fn)       fn(host, facts) at a run's end: { contract, house, difficulty, phase, why, crew (the
--                             players still on it), pieces ({ spot, item, name, icon, value (× its condition), to (the
--                             user id whose stock it went into), rarity? (its model's Rarity attribute) }) }
--   10.x danger (server/RunDanger.luau; marked "10.x danger" here, in onPick and in helperTake):
--   Moving.onRunStart(fn)     fn(s, Moving) once a run's move has started (its interior built, its pieces tagged)
--   Moving.runDrop(player, why, hp)   what `player` holds on a run goes down where they are (why: "bite", "stumble"),
--                             the piece knocked as by a bite of `hp` (MovingRules.hitDamage: a fragile one more); true
--                             when they held something
--   A piece the run's vault seals (s.danger.sealed[spot]: the words) is never picked up, lifted or taken by Danny.

function Moving.onRunEnd(fn: (Player, { [string]: any }) -> ())
	table.insert(SB.listeners.run, fn)
end

-- 10.x danger: the run's danger (server/RunDanger.luau) hears every run's start.
function Moving.onRunStart(fn: (any, any) -> ())
	table.insert(SB.listeners.runStart, fn)
end

-- 10.x danger: a bite or a stumble on a run: what `player` holds goes down where they are, knocked as by `hp`.
function Moving.runDrop(player: Player, why: string, hp: number): boolean
	local s = sessionOf(player)
	local spot = if s and s.contract.difficulty and not s.ended then Rules.holding(s.move, player.UserId) else nil
	if not s or not spot then
		return false
	end
	local thing = s.move.things[spot]
	release(s, player, why)
	if hp > 0 and thing then
		hurtThing(s, spot, Rules.hitDamage(hp, thing.fragile))
	end
	return true
end

-- Who loaded the piece at `spot` (a player; nil: nobody known, the host's then).
function SB.loaded(s: Session, spot: number?, who: Player?)
	if not spot then
		return
	end
	local list = s.loaders or {}
	list[spot] = if who then who.UserId else nil
	s.loaders = list
end

-- The player whose stock the piece at `spot` goes into: a run's loader while still in the game (RunRules.stockOwner),
-- else the move's owner.
function SB.stockFor(s: Session, spot: number): Player
	if not s.contract.difficulty then
		return s.owner
	end
	local loaders = s.loaders or {}
	local id = require(Shared.RunRules).stockOwner(loaders[spot], s.owner.UserId, function(userId: number): boolean
		return playerById(userId) ~= nil
	end)
	return playerById(id) or s.owner
end

-- A run's end: everything in the truck goes home now (its pieces into their loaders' stocks, the models gone), as a
-- trip; returns the event the end takes (FINISH or the vote with nothing ever home: called off).
function SB.unloadAll(s: Session, event: string): string
	for _, spot in s.move.order do -- (a thing whose model went never counts: lost)
		local thing = s.move.things[spot]
		local item = s.items[spot]
		if thing.state == "truck" and (not item or not item.model.Parent) then
			thing.state, thing.condition = "lost", 0
		end
	end
	local rarity = s.rarity or {}
	for _, spot in s.move.order do
		local item = s.items[spot]
		local mark = if s.move.things[spot].state == "truck" and item then item.model:GetAttribute("Rarity") else nil
		if type(mark) == "string" then
			rarity[spot] = mark
		end
	end
	s.rarity = rarity
	local spots = Rules.deliver(s.move, now())
	if #spots > 0 then
		local stored = SB.store(s, spots)
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
		s.dirty = true
		SB.tell("trip", s, s.owner, { pieces = #spots, stored = stored }) -- 8.2: the listeners (Moving.onTrip)
		if stored < #spots then
			tellAll(s, `⚠ {#spots - stored} of the truck's pieces could not be stored: a warehouse is full`)
		end
	end
	local c = Rules.counts(s.move)
	if c.delivered == 0 and event == "deliver" then
		return "cancel" -- (FINISH with nothing home: called off)
	elseif c.delivered == 0 and event == "timeout" then
		return "lose"
	elseif c.delivered > 0 and event == "cancel" then
		return "deliver" -- (GIVE UP, the admin's end, the host gone: what was in the truck came home all the same)
	end
	return event
end

-- The run's first words to its party.
function SB.runStartText(s: Session): string
	local def = require(Shared.RunRules).def(s.contract.difficulty)
	local clock = require(Shared.RunRules).clock(s.contract.time or T.Time)
	if s.contract.round then -- 10.5 rounds
		return `🏁 ROUND: {s.contract.name} · {if def then string.upper(def.name) else "ROUND"} · {clock}. Grab the loot, carry it to YOUR van and Load it (E): it is yours at once. Most value wins!`
	end
	return `🏠 {s.contract.name} · {if def then string.upper(def.name) else "RUN"} · {clock} on the clock. Carry the loot out and load it into the truck at the door; FINISH at the truck (or beat the clock): what is in the truck goes to your warehouse.`
end

-- A run's end (payOut's): the party's move HUD closes, the listeners (server/Runs.luau: the results card), the
-- analytics' MoveDone and the daily tasks' and the badges' result listeners as a move's.
function SB.runResult(s: Session, phase: string, why: string?, result: Rules.Result)
	local crew = everyone(s)
	for _, member in crew do
		remote:FireClient(member, "state", nil)
	end
	local pieces: { { [string]: any } } = {}
	local home = s.homeTo or {}
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		if thing.state == "delivered" and home[spot] then
			table.insert(pieces, { spot = spot, item = thing.item, name = thing.name, icon = thing.icon, value = thing.value * thing.condition,
				condition = thing.condition, to = home[spot], rarity = (s.rarity or {})[spot] })
		end
	end
	local facts = { contract = s.contract.id, house = s.contract.id, name = s.contract.name, difficulty = s.contract.difficulty, phase = phase,
		why = why or SB.how[phase] or phase, crew = crew, pieces = pieces, stars = result.stars, total = Rules.counts(s.move).total }
	for _, fn in SB.listeners.run do
		local ok, err = pcall(fn, s.owner, facts)
		if not ok then
			warn(`[Moving] a run's end listener failed: {err}`)
		end
	end
	if phase == "done" or phase == "late" then
		PlayerData.track("event", s.owner, "MoveDone", result.stars, s.contract.id, if #crew > 1 then "crew" else "solo")
	end
	for _, fn in SB.listeners.result do task.spawn(fn, s.owner, s.move, result, crew) end -- 8.2: Moving.onResult
end

function Moving.startRun(host: Player, house: string, difficulty: string, round: number?): string?
	local base = SB.contracts[house]
	if not base then
		return "No such house."
	end
	local RunRules = require(Shared.RunRules)
	local card, kept = SB.cardOf(host)
	local seed = kept
	if round then -- (10.5 rounds: a new house every round, the host's card left be)
		seed = math.random(1, T.Sandbox.Seeds)
		while seed == SB.last and T.Sandbox.Seeds > 1 do
			seed = math.random(1, T.Sandbox.Seeds)
		end
		SB.last, kept = seed :: number, seed
	elseif card ~= house or seed == nil then -- (8.3 economy: the host's seed for this house stays until a run brings something home)
		local fresh = math.random(1, T.Sandbox.Seeds)
		while fresh == SB.last do
			fresh = math.random(1, T.Sandbox.Seeds)
		end
		SB.last, seed = fresh, fresh
		SB.keep(host, house, fresh)
	end
	local own = T.Sandbox.Houses[house]
	local made = table.clone(base)
	made.seed = seed :: number
	made.difficulty = RunRules.clean(difficulty)
	made.time = if round then round else RunRules.time(if own then own.Time else (base.time or T.Time), made.difficulty)
	made.hordeAt = if T.Sandbox.Horde and not round then T.Sandbox.HordeAt else 0
	made.round = if round then true else nil
	local failed = startMove(host, made)
	if failed and seed ~= kept then
		SB.keep(host, card, kept) -- (no run: the card as it was)
	end
	local s = if failed then nil else sessions[host]
	if s and round then
		SB.noTruck(s) -- 10.5 rounds: no move truck: everybody loads into their own van (Moving.claim)
		s.claims = {}
	end
	for _, fn in (if s then SB.listeners.runStart else {}) :: { any } do -- 10.x danger: the run's danger (server/RunDanger.luau)
		local ok, err = pcall(fn, s, Moving)
		if not ok then
			warn(`[Moving] a run's start listener failed: {err}`)
		end
	end
	return failed
end

function Moving.endRun(host: Player, why: string?): boolean
	local s = sessions[host]
	if not s or s.ended or not s.contract.difficulty then
		return false
	end
	finish(s, "deliver", why or "Finished: what was in the truck went home")
	return true
end

-- ── 10.5 ROUNDS (server/Runs.luau's round loop; Config.Rounds, shared/RoundRules.luau) ────────────────────────────
-- A round is a run (its contract's `round`) for everybody in the game at once: its clock Config.Rounds.Seconds, a new
-- seed every round (no player's card), no move truck (SB.noTruck: the host's van is one van among the others), no
-- helper (the tick leaves MoveHelper be), no FINISH and no GIVE UP (viewFor's mine is false for all: the list's LEAVE
-- is server/Runs.luau's), CAR refused. Every player has their own van parked at the house (Runs parks them, its Load
-- prompt only theirs): Moving.claim there takes what they carry into their stock at once (MovingRules.claim: delivered,
-- s.homeTo and s.claims theirs; the stored listeners hear it as theirs: the daily tasks). The clock's end is the run's
-- end as ever (finish: nothing in a truck; Moving.onRunEnd's pieces, each `to` its claimer).
--   Moving.claim(player, car)     → the piece ({ spot, item, name, icon, value, rarity? }) or nil and why
--   Moving.carrying(player)       the name of what `player` carries (as its carrier) on a move, nil none
--   Moving.handOver(old, new)     the round's session goes over to `new` (its owner: the host who left the game or the
--                                 round); every MoveOwner = old becomes new's: true when it did
--   Moving.onHandOver(fn)         fn(old, new) after the host left the game and the round went on (Runs: the run's host)
--   Moving.roundVan               Runs' hook: a player's van at the round's house (respawnAt)

-- The move's truck off the session (a round's: the host's van is just theirs): its Load / Take out prompts gone, its
-- back as it was.
function SB.noTruck(s: Session)
	local truck = s.truck
	local takeOut = if s.unload then s.unload.Parent else nil
	local bay = if s.loadIn then s.loadIn.Parent else nil
	for _, prompt in { s.load, s.unload, s.loadIn } do
		if prompt then
			prompt:Destroy()
		end
	end
	if takeOut and takeOut.Name == "MoveTakeOut" then
		takeOut:Destroy()
	end
	if bay and bay.Name == "MoveLoadBay" then
		bay:Destroy()
	end
	s.load, s.unload, s.loadIn = nil, nil, nil
	releaseBack(truck)
	s.truck, s.lostAt, s.dirty = nil, nil, true
end

function Moving.claim(player: Player, car: Vehicles.Car): ({ [string]: any }?, string?)
	local s = sessionOf(player)
	if not s or s.ended or not s.contract.round then
		return nil, nil
	end
	local spot, role = Rules.holding(s.move, player.UserId)
	if not spot then
		return nil, "Carry something to your van first."
	elseif role ~= "carrier" then
		return nil, SB.why("helper")
	end
	local thing = s.move.things[spot]
	local item = s.items[spot]
	local helper = playerById(thing.helper)
	if not item or not item.model.Parent then -- (7.0 review: a missing model never counts)
		Rules.release(s.move, player.UserId)
		clearHands(player)
		clearHands(helper)
		s.dirty = true
		return nil, SB.why("gone")
	end
	local character, humanoid, root = bodyOf(player)
	if not character or not humanoid or not root then
		return nil, nil
	elseif humanoid.SeatPart then
		return nil, "Get out first."
	end
	local door = Vehicles.cargoDoor(car)
	if not SB.inBay(car, root.Position) and (not door or flat(root.Position, door.WorldPosition) > Config.Rounds.Reach + 3) then
		return nil, "Bring it to your own van's back."
	end
	if paceBroken(s, item, thing, player, character, root, os.clock()) then
		release(s, player, "pace")
		return nil, nil
	end
	-- the stock first: a full warehouse keeps it in your hands
	local variant = 1
	for _, planned in (s.plan.spots :: { any }) do
		if planned.id == spot and type(planned.variant) == "number" then
			variant = planned.variant
		end
	end
	local Collection = require(script.Parent.Collection)
	local ok, uid = pcall(Collection.add, player, { item = thing.item, variant = variant, condition = thing.condition, name = thing.name, rarity = (thing :: any).rarity })
	if not ok or uid == nil then
		if not ok then
			warn(`[Moving] Collection.add of {thing.item}: {uid}`)
		end
		return nil, "Your warehouse is full: sell something first."
	end
	local mark = item.model:GetAttribute("Rarity")
	Rules.claim(s.move, player.UserId, now())
	clearHands(player)
	clearHands(helper)
	for _, hook in item.hooks do
		hook:Disconnect()
	end
	table.clear(item.hooks)
	unweld(item)
	item.model:Destroy()
	local home = s.homeTo or {}
	home[spot] = player.UserId
	s.homeTo = home
	local marks = s.rarity or {}
	if type(mark) == "string" then
		marks[spot] = mark
	end
	s.rarity = marks
	local value = thing.value * thing.condition
	local claims = s.claims or {}
	local mine = claims[player.UserId] or { count = 0, value = 0 }
	mine.count += 1
	mine.value += value
	claims[player.UserId] = mine
	s.claims = claims
	s.dirty = true
	SB.tell("load", s, player, { item = thing.item, spot = spot }) -- 8.2: the listeners (Moving.onLoad)
	for _, fn in SB.listeners.stored do -- (8.2: Moving.onStored, the daily tasks: the claimer's own)
		task.spawn(fn, player, s.move, { spot })
	end
	return { spot = spot, item = thing.item, name = thing.name, icon = thing.icon, value = value, rarity = if type(mark) == "string" then mark else nil }, nil
end

function Moving.carrying(player: Player): string?
	local s = sessionOf(player)
	if not s or s.ended then
		return nil
	end
	local spot, role = Rules.holding(s.move, player.UserId)
	return if spot and role == "carrier" then s.move.things[spot].name else nil
end

function Moving.handOver(old: Player, new: Player): boolean
	local s = sessions[old]
	if not s or s.ended or not s.contract.round or (sessions[new] ~= nil and sessions[new] ~= s) then
		return false
	end
	sessions[old] = nil
	sessions[new] = s
	s.owner = new
	local was, to = old.UserId, new.UserId
	local function retag(d: Instance)
		if d:GetAttribute("MoveOwner") == was then
			d:SetAttribute("MoveOwner", to)
		end
	end
	for _, d in CollectionService:GetTagged("MovePrompt") do
		retag(d)
	end
	for _, top in { s.interior, s.site.model } :: { Instance? } do
		if top then
			for _, d in top:GetDescendants() do
				retag(d)
			end
		end
	end
	for _, item in s.items do
		retag(item.model)
		for _, d in item.model:GetDescendants() do
			retag(d)
		end
	end
	for member in s.members do
		if member.Parent and member:GetAttribute("MoveWith") == was then
			member:SetAttribute("MoveWith", to)
		end
	end
	new:SetAttribute("MoveWith", to)
	s.dirty = true
	return true
end

function Moving.onHandOver(fn: (Player, Player) -> ())
	table.insert(SB.listeners.handOver, fn)
end

-- The van lost mid-move (wrecked, gone, not the owner's car any more): what was in it is lost (condition 0, its models
-- go), the run goes on without a van; one placed for its host after VanAgain s (the wrappers in wireHooks) is taken
-- over (an empty bed, the prompts on it).
local function keepVan(s: Session, t: number)
	local truck = s.truck
	if s.contract.round then
		return -- (10.5 rounds: no move truck: every player's own van is server/Runs.luau's)
	elseif truck and truckOk(s) then
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
		local bay = if s.loadIn then s.loadIn.Parent else nil -- (8.0 SANDBOX: the walk-in bay's Load's own)
		for _, prompt in { s.load, s.unload, s.loadIn } do
			if prompt then
				prompt:Destroy()
			end
		end
		if bay and bay.Name == "MoveLoadBay" then
			bay:Destroy()
		end
		s.load, s.unload, s.loadIn = nil, nil, nil
		releaseBack(truck)
		s.truck, s.lostAt, s.dirty = nil, t, true
		local why = if truck.wrecked then "wrecked" else "gone"
		tellAll(s, `💥 The van is {why}{if #lost > 0 then `: the {#lost} things in it are lost` else ""}. The run goes on without it.`)
		return
	end
	local car = Vehicles.get(s.owner)
	if car and not car.wrecked and car.model.Parent and (car.id == T.Van or Vehicles.hasBack(car)) then
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
		finish(s, "timeout", if s.contract.round then "Time's up: what you loaded is in your warehouse" else "Time's up: what was in the truck went home") -- 9.7 runs: the clock ends the run (no drive home; 10.5 a round)
		return
	elseif due == "horde" then
		startHorde(s)
	end
	keepVan(s, t) -- 7.x van moves: a van lost mid-move loses its load (the move goes on), the owner's next one is taken
	syncMembers(s)
	watchCarried(s, clock)
	WalkIn.look(s, clock) -- 8.1 walk-in doors: the crew walking through the doors
	keepRoam(s, clock)
	if s.move.phase == "horde" then
		hordeBurst(s, clock)
	end
	if not s.contract.round then -- (10.5 rounds: no helper: everybody for themselves)
		MoveHelper.sync(s, Moving) -- 7.0: Danny joins a crew of one, goes when it grows (his own loop walks him)
	end
	refreshTruck(s)
	if (s.dirty and clock - s.sentAt > 0.25) or clock - s.sentAt > 5 then
		send(s)
	end
end

-- ── The admin ──────────────────────────────────────────────────────────────

function Moving.admin(player: Player, arg: any): string
	local s = sessions[player]
	if not s then
		return "ADMIN: you are not on a run (start one at a portal first)."
	end
	if arg == "horde" then
		if s.move.phase == "running" then
			local at = s.move.hordeAt or T.HordeAt
			if at > 0 then -- (a house without a horde keeps its clock)
				s.move.endsAt = math.min(s.move.endsAt, now() + at)
			end
			startHorde(s)
		end
		return "ADMIN: the horde comes now."
	elseif arg == "time" then
		s.move.endsAt = now() + 60
		s.dirty = true
		return "ADMIN: one minute left."
	elseif arg == "end" then
		finish(s, "cancel", "Called off by the admin")
		return "ADMIN: the run is called off."
	end
	return "ADMIN: horde | time | end."
end

-- ── 8.1 grip: the checks (shared/CarryGrip.luau; the hook: setHands' Grip.hands, the lift moment in onPick / onHelp) ──
-- The server opens every check, judges every answer and applies every outcome; the client (client/CarryGripUi.luau)
-- only draws a check and says when its player pressed. Config.CarryGrip.On false: no checks (the carry as before).
--   * The lift ("feeling for the grip"): Pick up / Lift / Help lift on a piece with a grip (CarryGrip.kind) opens a lift
--     check instead of the pick (Grip.liftStart; the gun goes away, both hands on it). A hit lifts it balanced (onPick /
--     onHelp again, `lifted`: every check of theirs once more, then the steady walk); a miss knocks it (Lift.Knock,
--     fragile × FragileKnock, the other end of a piece in a crew mate's hands × Shared), it hops and slips back down
--     where it stood, and the next try waits Lift.Again s.
--   * Wobbles: a carry's wobble clock (CarryGrip.rate: the body's speed against the carry's walk, its turn, a jump; a
--     bite moves it on) opens a WOBBLE! check when it is due. A hit: steady again (the misses in a row back to 0); a
--     miss: the next one drops it (CarryGrip.outcome: Miss.Drop in a row, a fragile piece at once), else a stagger (a
--     knock, the walk × Miss.Slow for Miss.SlowFor s, the next wobble × Miss.Sooner). A drop drops the whole piece (a
--     pair: both ends) with CarryGrip.slipDamage. Two players holding a piece each have their own checks; a stagger's
--     knock is half each (Shared).
--   * The Moving remote, server → client: ("grip", "open", CarryGrip.wire(check, { id, spot, name, icon, drop, help })),
--     ("grip", "result", { id, what, outcome, left, name }), ("grip", "close", id) (a check off without an outcome: put
--     down, a door trip, the piece gone). Client → server: ("grip", id, "ok" | "miss", pressed s into the check) once a
--     check (the remote's rate limit, Config.Robust.Limits.Moving, on top).
--   * Trust: an answer counts only for the sender's own open check (its id); "ok" is a hit only when CarryGrip.judge
--     finds its press time true (Server.Lag / Ahead of the server's own clock of the check) with the needle in the zone;
--     no answer by the window + Server.Grace is a miss (Grip.tick). Nothing while either end of the piece is on a door
--     trip (the check off, the clock waits). Danny never has a check. 8.3 review: a lift check his arrival opened
--     (Moving.helperCalled: no press of yours) and never answered closes without a knock (Grip.unheard).
--   Moving.gripCheck(player)  a wobble check now on what `player` carries (tests; true when one opened)

-- The check's outcome to its player (the client shows it; the piece's condition after it).
function Grip.result(player: Player, open: GripOpen, outcome: string, thing: Rules.Thing)
	if player.Parent then
		remote:FireClient(player, "grip", "result", { id = open.id, what = open.check.what, outcome = outcome, left = math.floor(thing.condition * 100 + 0.5), name = thing.name })
	end
	SB.tell("grip", nil, player, { what = open.check.what, outcome = outcome, item = thing.item, fragile = thing.fragile }) -- 8.2 (Moving.onGrip)
end

-- The check on `hold` goes without an outcome (the client closes it).
function Grip.close(player: Player, hold: GripHold)
	local open = hold.open
	if open then
		hold.open = nil
		if player.Parent then
			remote:FireClient(player, "grip", "close", open.id)
		end
	end
end

-- 8.3 review: a lift check Danny's arrival opened (`called`: Moving.helperCalled), never answered (its time ran out, or
-- a door's trip): closed without an outcome, no knock; the piece stays as it is, his call ready, and the next Lift
-- opens a new check (`thing`: told so; nil: a door's trip, nothing said).
function Grip.unheard(player: Player, hold: GripHold, thing: Rules.Thing?)
	Grip.close(player, hold)
	Grip.holds[player] = nil
	if thing then
		say(player, `{Config.MoveHelper.Name} waits at the other end of the {thing.name}: lift it when you're ready.`)
	end
end

-- Opens a check ("lift" | "wobble") on `hold` for `player` and sends it (a wobble says when its miss drops the piece).
function Grip.open(s: Session, player: Player, hold: GripHold, thing: Rules.Thing, what: string, help: boolean)
	local profile = Grip.profile(thing, hold.kind, player)
	local check = CarryGrip.check(profile, what, math.random())
	Grip.nextId += 1
	local id = Grip.nextId
	hold.open = { id = id, check = check, spot = thing.spot, help = help, opened = now() }
	hold.owed = nil -- (a wobble a door's fade took off: this one is it)
	local drop = what == "wobble" and CarryGrip.outcome(what, false, profile, hold.misses + 1) == "drop"
	remote:FireClient(player, "grip", "open", CarryGrip.wire(check, { id = id, spot = thing.spot, name = thing.name, icon = thing.icon, drop = drop, help = help }))
end

-- The hook in onPick (help false) and onHelp (help true), after their own checks: a piece with a grip gets a lift check
-- first (true: the pick waits for its hit). A check of theirs already on, or a moment after a miss on it: true (the
-- press does nothing). A piece the pick would refuse anyway (taken, gone, the move over): false (it says why).
function Grip.liftStart(s: Session, spot: number, player: Player, help: boolean): boolean
	local thing = s.move.things[spot]
	if not Config.CarryGrip.On or not thing then
		return false
	end
	local kind = CarryGrip.kind(thing.class, thing.fragile, help, nil)
	if not kind then
		return false
	end
	local hold = Grip.holds[player]
	local t = now()
	if hold and hold.session == s.id and (hold.open or (not hold.carrying and hold.spot == spot and t < hold.again)) then
		return true
	end
	local free = if help then thing.state == "carried" and thing.class == "pair" and thing.helper == nil and thing.carrier ~= player.UserId
		else thing.state == "home" or thing.state == "ground"
	if not free or (s.move.phase ~= "running" and s.move.phase ~= "horde") or Rules.holding(s.move, player.UserId) then
		return false
	end
	local fresh = Grip.newHold(s, spot, false, kind, player)
	Grip.holds[player] = fresh
	Grip.open(s, player, fresh, thing, "lift", help)
	return true
end

-- A little hop of a piece on the floor (a lift's miss: it slipped back down).
function Grip.hop(item: Item, thing: Rules.Thing)
	if thing.state ~= "home" and thing.state ~= "ground" then
		return -- (Help lift's miss: the piece is in its carrier's hands)
	end
	local base = item.model:GetPivot()
	item.model:PivotTo(base * CFrame.new(0, 0.3, 0))
	task.delay(0.12, function()
		if (thing.state == "home" or thing.state == "ground") and item.model.Parent then
			item.model:PivotTo(base)
		end
	end)
end

-- The open check on `hold` ends: a hit or a miss, and what it does.
function Grip.settle(s: Session, player: Player, hold: GripHold, hit: boolean)
	local open = hold.open
	if not open then
		return
	end
	hold.open = nil
	local thing = s.move.things[open.spot]
	local item = s.items[open.spot]
	if not thing or not item then
		return
	end
	local G = Config.CarryGrip
	if open.check.what == "lift" then
		if hit then
			hold.steady = true -- (balanced: the steady walk)
			if open.help then
				onHelp(s, open.spot, player, true)
			else
				onPick(s, open.spot, player, true)
			end
			if Rules.holding(s.move, player.UserId) == open.spot then
				Grip.result(player, open, "balanced", thing)
			else
				Grip.holds[player] = nil -- (the pick could not be: it said why)
				if player.Parent then
					remote:FireClient(player, "grip", "close", open.id)
				end
			end
			return
		end
		hold.again = now() + G.Lift.Again
		hurtThing(s, open.spot, CarryGrip.knock("lift", thing.fragile, open.help))
		Grip.hop(item, thing)
		Grip.result(player, open, "knock", thing)
		say(player, `The {thing.name} slipped back down ({math.floor(thing.condition * 100 + 0.5)}% left). Feel for the grip again (E).`)
		return
	end
	-- a wobble
	local profile = Grip.profile(thing, hold.kind, player)
	if hit then
		hold.steady, hold.misses = true, 0
		local clock = hold.clock
		if clock then
			CarryGrip.rearm(clock, profile, math.random(), false)
		end
		Grip.result(player, open, "steady", thing)
		setHands(s, item) -- (the walk: steady again)
		return
	end
	hold.misses += 1
	hold.steady = false
	local carrier = playerById(thing.carrier)
	local helper = playerById(thing.helper)
	if CarryGrip.outcome("wobble", false, profile, hold.misses) == "drop" then
		-- (the drop is the consequence for the whole piece: no end's record goes on, nor the other end's open check)
		local ends: { Player? } = { carrier, helper }
		for _, who in ends do
			local other = if who then Grip.holds[who] else nil
			if who and other and other.spot == open.spot then
				if other ~= hold then
					Grip.close(who, other)
				end
				Grip.holds[who] = nil
			end
		end
		Grip.holds[player] = nil
		if carrier then
			release(s, carrier, "slip") -- (the whole piece: both ends)
		end
		hurtThing(s, open.spot, CarryGrip.slipDamage(thing.fragile))
		Grip.result(player, open, "drop", thing)
		local left = math.floor(thing.condition * 100 + 0.5)
		local holders: { Player? } = { carrier, helper }
		for _, who in holders do
			if who and who == player then
				say(who, `💥 It slipped! The {thing.name} fell: {left}% left. Hit the next wobble to keep it.`)
			elseif who then
				say(who, `💥 {player.DisplayName} lost their grip: the {thing.name} fell ({left}% left).`)
			end
		end
		return
	end
	hold.slowUntil = now() + G.Miss.SlowFor
	local clock = hold.clock
	if clock then
		CarryGrip.rearm(clock, profile, math.random(), true) -- (shaky: the next wobble sooner)
	end
	hurtThing(s, open.spot, CarryGrip.knock("wobble", thing.fragile, carrier ~= nil and helper ~= nil))
	Grip.result(player, open, "stagger", thing)
	say(player, `⚠ The {thing.name} wobbled ({math.floor(thing.condition * 100 + 0.5)}% left): miss the next one and it drops.`)
	setHands(s, item) -- (the stagger's slow walk; Grip.tick takes it back)
end

-- 8.1 review: `hold`'s carry ended (put down, loaded, its holder down): a wobble still open is a miss all the same
-- (something always happens: its knock, or the slip's damage when this miss would have dropped it; the piece is down
-- already), and a shaky carry's misses stay with the piece a moment (Grip.recent). Anything else just closes.
function Grip.forfeit(s: Session, player: Player, hold: GripHold, t: number)
	local open = hold.open
	local thing = s.move.things[hold.spot]
	if not open or open.check.what ~= "wobble" or not thing then
		Grip.close(player, hold)
	else
		hold.open = nil
		hold.misses += 1
		local drop = CarryGrip.outcome("wobble", false, Grip.profile(thing, hold.kind, player), hold.misses) == "drop"
		hurtThing(s, open.spot, if drop then CarryGrip.slipDamage(thing.fragile) else CarryGrip.knock("wobble", thing.fragile, false))
		Grip.result(player, open, if drop then "drop" else "stagger", thing)
		local left = math.floor(thing.condition * 100 + 0.5)
		say(player, if drop then `💥 The {thing.name} slipped as it went down: {left}% left.` else `⚠ The {thing.name} wobbled as it went down ({left}% left).`)
		if drop then
			hold.misses = 0 -- (it fell: that was the consequence)
		end
	end
	if hold.misses > 0 then
		Grip.recent[player] = { session = s.id, spot = hold.spot, misses = hold.misses, till = t + Config.CarryGrip.Miss.Remember }
	end
end

-- ("grip", id, verdict, pressed) from the client: its answer to its own open check (anything else does nothing).
function Grip.answer(player: Player, id: any, verdict: any, pressed: any)
	local s = sessionOf(player)
	local hold = Grip.holds[player]
	local open = if hold then hold.open else nil
	if not s or s.ended or not hold or not open or hold.session ~= s.id or open.id ~= id or traveling[player] then
		return
	end
	local ping: number? = nil
	pcall(function()
		ping = player:GetNetworkPing() -- (8.1 review: a press may be only as old as this player's round trip allows)
	end)
	Grip.settle(s, player, hold, CarryGrip.judge(open.check, verdict, pressed, now() - open.opened, CarryGrip.lagFor(ping)))
end

-- Every tick (watchCarried): each record on this move: a carry or a lift that ended goes; a door trip turns its check
-- off; a check with no answer past its window + Server.Grace is a miss; a stagger's slowdown ends; the wobble clock runs
-- (the body since the last look) and opens a wobble when it is due.
function Grip.tick(s: Session, t: number)
	local players: { Player } = {}
	for player, hold in Grip.holds do
		if hold.session == s.id then
			table.insert(players, player)
		end
	end
	local G = Config.CarryGrip
	for _, player in players do
		local hold = Grip.holds[player]
		if not hold or not player.Parent or sessionOf(player) ~= s then
			Grip.holds[player] = nil -- (gone, or off this move)
			continue
		end
		local dt = math.clamp(t - hold.tick, 0, 1)
		hold.tick = t
		local spot, role = Rules.holding(s.move, player.UserId)
		local thing = s.move.things[hold.spot]
		local item = s.items[hold.spot]
		local carrying = hold.carrying and spot == hold.spot
		if not thing or not item or (hold.carrying and not carrying) or (not hold.carrying and spot ~= nil) then
			if hold.carrying and thing then
				Grip.forfeit(s, player, hold, t) -- (the carry ended: put down, loaded, dropped: an open wobble is a miss)
			else
				Grip.close(player, hold) -- (their hands took another, or the piece is gone)
			end
			Grip.holds[player] = nil
			continue
		end
		local partner = if carrying then playerById(if role == "carrier" then thing.helper else thing.carrier) else nil
		if traveling[player] or (partner and traveling[partner]) then
			local open = hold.open
			if open and open.called then
				Grip.unheard(player, hold, nil) -- (8.3 review: Danny's arrival opened it, not a press: no knock)
			elseif open and open.check.what == "lift" then
				Grip.settle(s, player, hold, false) -- (8.1 review: walked off mid-lift: its knock all the same)
			else
				hold.owed = hold.owed or open ~= nil -- (a wobble: it opens again on the other side)
				Grip.close(player, hold) -- (a door's fade: no check, the clock waits)
			end
			hold.at = nil
			continue
		end
		local open = hold.open
		if open then
			local gone = not carrying and not (if open.help then thing.state == "carried" else thing.state == "home" or thing.state == "ground")
			if gone then
				Grip.close(player, hold) -- (somebody else took it meanwhile)
				Grip.holds[player] = nil
			elseif t - open.opened > open.check.window + G.Server.Grace and open.called then
				Grip.unheard(player, hold, thing) -- (8.3 review: Danny's arrival opened it: no answer, no knock)
			elseif t - open.opened > open.check.window + G.Server.Grace then
				Grip.settle(s, player, hold, false) -- (no answer: a miss)
			end
			continue
		end
		if not carrying then
			if t >= hold.again then
				Grip.holds[player] = nil -- (a lift's miss: its moment is over)
			end
			continue
		end
		if hold.slowUntil > 0 and t >= hold.slowUntil then
			hold.slowUntil = 0
			setHands(s, item) -- (the stagger is over: the walk back)
		end
		if hold.owed then
			hold.owed = nil
			Grip.open(s, player, hold, thing, "wobble", false) -- (the wobble the door's fade turned off)
			continue
		end
		local clock = hold.clock
		local character, humanoid, root = bodyOf(player)
		if not clock or not character or not humanoid or not root then
			continue
		end
		local at = root.Position
		local look = root.CFrame.LookVector
		local yaw = math.atan2(look.X, look.Z)
		local speed, turn = 0, 0
		local lastAt, lastYaw = hold.at, hold.yaw
		if lastAt and lastYaw and dt > 0 then
			speed = flat(at, lastAt) / dt
			turn = ((yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi) / dt
		end
		hold.at, hold.yaw = at, yaw
		local health = humanoid.Health
		if hold.health and health < hold.health then
			CarryGrip.bump(clock) -- (a bite jolts it)
		end
		hold.health = health
		local walk = character:GetAttribute("CarrySpeed")
		local rate = CarryGrip.rate(speed, if type(walk) == "number" then walk else Config.Movement.Walk, turn, humanoid.FloorMaterial == Enum.Material.Air)
		if CarryGrip.advance(clock, dt, rate) then
			Grip.open(s, player, hold, thing, "wobble", false)
		end
	end
end

-- A wobble check now on what `player` carries (the tests'); true when one opened.
function Moving.gripCheck(player: Player): boolean
	local s = sessionOf(player)
	local hold = Grip.holds[player]
	local spot = if s then Rules.holding(s.move, player.UserId) else nil
	local thing = if s and spot then s.move.things[spot] else nil
	if not s or not hold or not thing or hold.open or not hold.carrying or hold.spot ~= spot or traveling[player] then
		return false
	end
	Grip.open(s, player, hold, thing, "wobble", false)
	return true
end
-- ── (end of the grip block) ──────────────────────────────────────────────────────────────────────────────────────────

-- ── Start ──────────────────────────────────────────────────────────────────

local function onPutDown(player: Player)
	local s = sessionOf(player)
	if s and Rules.holding(s.move, player.UserId) then
		release(s, player, "put")
	elseif s then
		MoveHelper.cancel(player) -- 8.3 G with empty hands: you stop waiting for Danny
	end
end

local function onRequest(player: Player, action: any, arg: any, arg2: any, arg3: any)
	if action == "helper" then
		return -- (8.3: Danny's own, server/MoveHelper.luau's, at its own rate limits)
	end
	if not Net.limit(player, "Moving", Config.Robust.Limits.Moving) then
		return
	end
	if action == "grip" then -- 8.1 grip: the answer to a check (its id, "ok" | "miss", the press's time; the grip block)
		Grip.answer(player, arg, arg2, arg3)
	elseif action == "call" then -- "Call the van to the door"
		local s = sessionOf(player)
		if s and not s.ended then
			callTruck(s, player)
		end
	elseif action == "giveup" then
		local s = sessions[player]
		if s and s.contract.round then
			return -- (10.5 rounds: leaving the round is server/Runs.luau's: the list's LEAVE)
		elseif s then
			finish(s, "cancel", "You called it off") -- (what was in the truck comes home all the same: SB.unloadAll)
		end
	elseif action == "state" then
		local s = sessionOf(player)
		if s then
			remote:FireClient(player, "state", viewFor(s, player))
		end
	elseif action == "finish" then -- the host's FINISH
		finishMove(player)
	end
end

-- 7.0 review: the owner's truck is out on a live move (nothing else of theirs may take its place).
local TRUCK_OUT = "Your van is out on a move: finish the move first."
local function truckOut(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and not s.ended and truckOk(s) ~= nil
end

-- 7.x van moves: the van was lost on a run a moment ago: no other car for its host before VanAgain s (the wait's words).
local function vanWait(player: Player): string?
	local s = sessions[player]
	local lost = if s and not s.ended and s.truck == nil then s.lostAt else nil
	if lost and now() - lost < T.VanAgain then
		return `Your van comes back in {math.ceil(T.VanAgain - (now() - lost))} s.`
	end
	return nil
end

-- Why `player` can't start another run now (server/Runs.luau, server/SandboxBoot.luau): on one (its host or its
-- party), nil: they can.
function Moving.busy(player: Player): string?
	if sessionOf(player) then
		return "You are on a move: finish it first (or GIVE UP in the move's list, Tab)."
	end
	return nil
end

-- 8.2 SANDBOX (server/SandboxTasks.luau: the moves' own tables, beside the analytics' Moving.onTrip / onFinish facts):
-- fn(owner, move, spots) after the truck's load home stored pieces (SB.store), fn(owner, move, result, crew) at a run's
-- end (SB.runResult).
function Moving.onStored(fn: (Player, Rules.Move, { number }) -> ()) table.insert(SB.listeners.stored, fn) end
function Moving.onResult(fn: (Player, Rules.Move, Rules.Result, { Player }) -> ()) table.insert(SB.listeners.result, fn) end

-- 8.0 SANDBOX (server/SandboxBoot.luau: every spawn): where a new body of a player on a move (its owner or its crew)
-- stands, never stranded at home while the van is out: by the move's van when it is out and not wrecked (beside its
-- back, its side's way, on the ground, looking at the back doors), else 6 studs out of the house's front door
-- (the run's house's SandboxMap door, looking out); nil off a run.
function Moving.respawnAt(player: Player): CFrame?
	local s = sessionOf(player)
	if not s then
		return nil
	end
	local own = if s.contract.round and Moving.roundVan then Moving.roundVan(player) else nil -- (10.5 rounds: by your own van)
	local truck = if own and not own.wrecked and own.model.Parent then own else truckOk(s)
	if truck then
		local door = Vehicles.cargoDoor(truck)
		local frame = truck.chassis.CFrame
		local backZ = if door then frame:PointToObjectSpace(door.WorldPosition).Z else 0
		local side = frame * Vector3.new(bedOf(truck).Width / 2 + 3, 0, backZ - 1)
		local at = Vector3.new(side.X, Vehicles.groundY(side.X, side.Z, frame.Position.Y) + 3, side.Z)
		local look = frame * Vector3.new(0, 0, backZ)
		return CFrame.lookAt(at, Vector3.new(look.X, at.Y, look.Z))
	end
	local spot = (SandboxMap.house(s.contract.id) or SandboxMap.House).door -- (six houses: the move's house's)
	return CFrame.new(spot.x, spot.y + 3, spot.z) * CFrame.Angles(0, math.rad(spot.yaw), 0) * CFrame.new(0, 0, -6)
end

local function wireHooks()
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
	-- the crew opens and closes the truck's back too
	local backAllowed = Vehicles.backAllowed
	Vehicles.backAllowed = function(player: Player, car: Vehicles.Car): boolean
		if backAllowed(player, car) then
			return true
		end
		local s = sessions[car.owner]
		return s ~= nil and not s.ended and s.truck == car and sessionOf(player) == s
	end
	-- 7.0 review: while your run's truck is out nothing of yours takes its place (each of these would remove it first:
	-- CAR, the phone's CALL CAR; startMove's own SB.bringVan runs before the session exists)
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
	-- (7.2 review: these wait for a lost van's VanAgain s too: the garage's TAKE OUT is placeAt)
	local placeAt = Vehicles.placeAt
	Vehicles.placeAt = function(player: Player, carId: string?, spot: CFrame, seat: boolean?): Vehicles.Car?
		local refused = if truckOut(player) then TRUCK_OUT else vanWait(player)
		if refused then
			say(player, refused)
			return nil
		end
		return placeAt(player, carId, spot, seat)
	end
	local spawnAt = Vehicles.spawnAt
	Vehicles.spawnAt = function(player: Player, carId: string?, ground: CFrame, seat: boolean, chauffeured: boolean?, rental: boolean?, keep: { Instance }?): Vehicles.Car?
		local refused = if truckOut(player) then TRUCK_OUT else vanWait(player)
		if refused then
			say(player, refused)
			return nil
		end
		return spawnAt(player, carId, ground, seat, chauffeured, rental, keep)
	end
end

function Moving.start()
	local made = Instance.new("Folder")
	made.Name = "Moves"
	made.Parent = workspace
	folder = made
	-- the houses (a contract and a site each; no board: the lobby's portals start the runs, server/Runs.luau)
	for _, h in SandboxMap.Houses do
		local house = SB.newContract(h)
		SB.contracts[house.id] = house
		table.insert(SB.all, house)
		sites[house.id] = SB.site(house, made)
	end
	if T.Doors.Walk then -- 8.1 walk-in doors: a doormat at every door outside (shown while a move uses it)
		for _, site in sites do
			WalkIn.siteMats(site)
		end
		WalkIn.show()
	end
	WalkIn.send = send -- 8.3 walk-in doors: a trip sends where you are before its fade in (travel)
	wireHooks()
	-- the quick chat (server/MoveLobby.luau) reaches the run's party
	MoveLobby.moveCrew = function(player: Player): { Player }?
		local s = sessionOf(player)
		return if s then membersOf(s) else nil
	end
	MoveLobby.start()
	remote.OnServerEvent:Connect(onRequest)
	Net.get("PutDown").OnServerEvent:Connect(onPutDown)
	Players.PlayerRemoving:Connect(function(player: Player)
		local own = sessions[player]
		if own and own.contract.round and not own.ended then
			-- 10.5 rounds: the host left the game: the round goes on, its session another player's (the first still in it)
			for _, member in everyone(own) do
				if member ~= player and member.Parent and (sessions[member] == nil or sessions[member] == own) and Moving.handOver(player, member) then
					for _, fn in SB.listeners.handOver do
						local ok, err = pcall(fn, player, member)
						if not ok then
							warn(`[Moving] a round's hand-over listener failed: {err}`)
						end
					end
					return
				end
			end
		end
		if own and not own.ended then
			-- 9.7 runs: the host left: the run ends, what is in the truck goes home (each piece to whoever loaded it)
			for _, member in everyone(own) do
				if member ~= player then
					say(member, `The run ended: {player.DisplayName} (the host) left. What was in the truck went home.`)
				end
			end
			finish(own, "deliver", `{player.DisplayName} left the game: what was in the truck went home`)
		end
		for _, session in sessions do
			if session.members[player] then
				release(session, player, "gone")
			end
			session.inside[player] = nil
			session.members[player] = nil
		end
		traveling[player] = nil
		WalkIn.at[player], WalkIn.held[player] = nil, nil -- (8.1 walk-in doors)
		SB.forget(player, true) -- (their house's facts; 8.3 economy: its seed kept for their return)
	end)
	-- a new body is never inside (a death inside respawns you by the van: Moving.respawnAt)
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
	-- the moves' tick every Tick s; 8.1 walk-in doors: the loop runs every Doors.Every s, the doors looked at between two
	-- ticks too (the tick looks at them itself)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(if T.Doors.Walk then math.min(T.Doors.Every, T.Tick) else T.Tick)
			local clock = os.clock()
			if clock - last >= T.Tick * 0.9 then
				last = clock
				Moving.step()
			else
				Moving.doors()
			end
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

-- 8.1 walk-in doors: one look at every running move's doors (the loop's between two ticks, about every Doors.Every s).
-- 8.3: the leaves nobody wants open any more shut first (a move's end leaves none open).
function Moving.doors()
	local clock = os.clock()
	WalkIn.sweep(clock)
	for _, s in sessions do
		if not s.ended then
			local ok, err = pcall(function()
				WalkIn.look(s, clock)
			end)
			if not ok then
				warn(`[Moving] {s.contract.id}'s doors: {err}`)
			end
		end
	end
end

return Moving
