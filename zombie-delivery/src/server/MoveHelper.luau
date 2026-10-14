--!strict
-- 7.0, the depot's helper ("Danny from the depot"; the owner's decision in design/rework/NAVRH.md: solo play is allowed
-- with an AI helper). An NPC mover who comes with a move whose crew is a single player (Config.MoveHelper.Duo: two
-- players too, off by default). server/Moving.luau calls MoveHelper.sync(session, Moving) every tick: he comes when the
-- crew is small enough and goes when it grows (setting down what he holds; 8.3 a hired Danny stays); his own loop
-- (Config.MoveHelper.Tick) walks him. His decisions are shared/MoveHelperBrain.luau's (pure: tests/movehelper_test.luau);
-- what he does with the pieces goes through Moving's helper hooks (Moving.helperTake / helperDrop / helperLoad /
-- helperHurt: the same rules, welds and damage as a player's hands); tests/movehelper_runtime_test.luau and
-- tests/movehelper_art_runtime_test.luau run the real module with the real Moving.
-- 8.3 Danny for hire (the owner: "make it so I click on the helper, but I have to PAY for him when I want help. It
-- doesn't work well when he does 4 things. Instead: he helps, but for example you go into the house, click on
-- something, and that assigns it to him, and the rest you carry yourself"; and "mainly, he must sit in my car with me"):
--   * Hiring: at a move's start he does not work. He waits by the van (or at the house's curb once the van is parked
--     there) with a "Hire Danny · $X" sign over his head. A click or a tap on him (a gamepad's "Hire Danny" prompt)
--     opens his card (client/MoveHelperCard.luau) and its HIRE sends the Moving remote's ("helper", "hire"): a crew
--     player only, checked (MoveHelperBrain.hireCheck), the money taken (PlayerData.spend, the analytics reason
--     HelperHire). The price is the move's (MoveHelperBrain.hirePrice: Config.MoveHelper.Hire by the house's pieces).
--     He works for that move until it ends; whoever paid owns the hire (they leave the move: he is for hire again).
--     Not hired: today's rules for the two-person pieces (dragged alone, a crew mate's Help lift), no waiting for him.
--   * His list: a click (a tap; a gamepad's "Give to Danny") on a piece of the move sends ("helper", "assign", its
--     model): checked here (MoveHelperBrain.assignCheck: the move's crew, hired, the move's own piece, not in the van
--     or home, nobody holding it, near enough, Config.MoveHelper.Queue at most; Config.Robust.Limits.MoveHelperAssign)
--     it goes on his list ("Danny will take the Lamp."), a 🧑‍🔧 marker over it with its number (the piece's
--     attributes DannyQueue / DannyNeeds for the clients); a click on it again takes it back. He carries them in that
--     order (MoveHelperBrain.nextQueued: the first that still fits the van), each as he always has: a path inside, the
--     front door his own way, a path to the van's back, the back opened, loaded (MovingRules' packer), his walk × the
--     carry's. A two-person piece of his list: he goes to it and waits at one end ("needs": "🙋 Danny needs you" over
--     it, a toast, its Lift says "Lift with Danny"); your Lift there is your call below. A piece of his list you pick up
--     yourself leaves it ("All yours, boss."); CLEAR QUEUE (the card's: ("helper", "clear")) empties it; an empty list,
--     he waits by the van ("All done. Anything else, boss?"). Everything else is yours to carry.
--   * Your call (Config.MoveHelper.WaitForHelper; hired only): Lift on a two-person piece while he can come (his body up,
--     his hands not on another piece's end, not in the van's seat) is no drag alone: you say "Danny, give me a hand!" (a
--     bubble over your head, a toast; the player attribute MoveHelperCall = its name: your status line says you wait,
--     its STOP and G stop it), its Lift prompt says "Stop waiting", and he WALKS to its far end as you will hold it
--     (Moving's helperLiftFrame), through the walk-in doors his own way, never faded over but as the last resort
--     (CallBlink s no closer). His own piece first: into the van right there, else set down (back at the head of his
--     list). In place (MoveHelperBrain.inPlace): "On three... lift!", your grip steadied, and Moving opens your lift
--     check (helperCalled; no grip: the lift at once); its hit lifts it with him at its far end (joinLift: his hold
--     starts where he stands). Lift again, G, STOP, walking away (callKept) or his fall end it.
--   * Riding with you: while he is hired and you sit at the move's van's wheel he walks to its passenger door (Sprint,
--     from the house too: through its door; CallGain / CallBlink the last resort, a fade into the seat) and sits
--     (Seat:Sit: his body welded in, massless, Roblox's sit pose; never his hold, never Npcs.carried); the van may go
--     meanwhile, he gets in as soon as he reaches it. Nobody at the wheel and the van standing (at the house's curb, at
--     your plot), he gets out on his side and goes on with his list. The van wrecked or gone: out at once (8.3 review:
--     at that seat's door, where the van stands or stood: never in its shell). Its seat taken by a crew mate (8.3
--     review: or reserved by their boarding, its Reserved): he follows it on foot (by its back; parked far off, he
--     appears there as ever). 8.3 review: a crew mate's Ride along at his door: he gets out for them
--     (Vehicles.yieldSeat; SeatAside studs aside, out of their way) and takes no seat for SeatYield s.
--   * Carrying together: he moves WITH the piece: his own walk is off (Npcs.carried), constraints on his root
--     (AlignPosition / AlignOrientation to an attachment at the piece's far end, turned to you) hold him there every
--     physics step, on the floor under that end (stairs, steps: within HoldStep of you), through walls and door frames
--     like the piece itself (a collision group nothing collides with), through the front door's fade with you. Never a
--     "too far apart" drop. His arms hold its edge (the Carrying / CarryAt / CarrySize attributes on his body:
--     client/ArmPose.luau), his legs step with his speed (Npcs.stride, backwards when he walks backwards). Your grip bar
--     is easier meanwhile (the character attribute GripSteady: Config.CarryGrip.Steadied × the box). He talks on the
--     way: "Watch the doorframe!", "That's going in the van."
--   * 8.1 carrying in two (the owner: "when I turn around he teleports … we must walk, like, backwards and slowly"):
--     your heading turns slowly (client/PairSteer.luau, shared/PairCarry.luau: PairTurn degrees a second; a way behind
--     you is walked backwards), and he is never put at the far end while he holds it: his constraints (server/
--     PairHold.luau) walk him there at the pair's walk and a margin (MoveHelperBrain.holdSpeed of your CarrySpeed), his
--     body turning to you at holdTurn; only a door's fade puts him there (the piece in the other world). More than
--     HoldBehind studs off his place for HoldStuck s: eased back over HoldEase s (MoveHelperBrain.holdTrack).
--   * 8.3 (the owner: "he just jumps weirdly"): his feet on the floor under his end (endOffset: a ray within a step of
--     the floor under your feet, never a roof or your jump; his height by PairHold's lift at HoldClimb at most), his
--     legs the clients' gait (Npcs.carried's Physics state) and holdLegs' stride; his paths never jump (Path* numbers).
--   * 8.3 keeping up (the owner: "when I run, he just goes behind me with his arms stretched out"): his top speed
--     follows your real speed along the ground (your root's: MoveHelperBrain.holdPace / holdSpeed, HoldCap at most),
--     and he is aimed your velocity × MoveHelperBrain.leadTime (HoldLead: a little + your ping) ahead of his place:
--     your screen shows his body that late, so there he walks at his end (actHold). Nobody runs with a piece in two
--     (the CarryPair attribute: client/PairSteer.luau).
--   * Your two-person piece dragged alone (hired; he could not come to your call: a crew mate's call, him down): he
--     sprints to its far end and takes it (MoveHelperBrain.pickLift).
--   * The van's back: somebody of the crew coming with a piece within OpenNear of the shut back while he is within
--     OpenFar of it (hired): he opens it ("I'll get the doors!"). With a piece of his own at the shut back he opens it
--     himself (OpenBack, else "Open the back, boss!" and WaitShut s, then set down beside it); no room: set down beside
--     the van ("Van's full, boss - drive it home?").
--   * Unstuck: no progress for StuckRepath s, a new path; StuckSnap s, he appears at his way's next point (Nudge studs
--     at most). Where he stands still (waiting) he keeps out of the doorways (MoveHelperBrain.aside).
--   * The crew's attributes (client/MoveHelperHud.luau's status line under the move's panel, his card): MoveHelper =
--     "offer" (for hire) | "hired", MoveHelperPrice (the hire's price while he is for hire), MoveHelperQueue (the pieces
--     on his list while hired), MoveHelperDoing (what he does), MoveHelperId (his id: the card finds his body by it).
--   * He stays out of fights: a zombie within FleeRange, he runs (never while holding the other end of your piece, nor
--     from the van's seat). The zombies go after him like after a player on foot (Zombies.extraTargets); a bite knocks
--     what he holds (Moving.helperHurt); at 0 health he drops it (knocked; his own piece back on his list) and lies down;
--     he is back at the van Respawn s later.
--   * He talks a little: a speech bubble (Npcs.say) on the way's events, never the same line within TalkRepeat s (8.0
--     SANDBOX: MoveHelperBrain.line's sandbox words: no Wall, no depot).
-- Performance: one helper per move, one loop for all of them, a path at most every Repath s (computed in the background,
-- one Path object each), his walk ordered again only when its goal moves (Npcs.walkTo), his list's room in the van
-- worked out only when the load changes (every Think s); carrying together the physics engine moves him (the loop only
-- re-aims the far end's attachment and his top speed, a ray down a step); seated, the van carries him (nothing to do).
--   MoveHelper.sync(s, port)   Moving's tick: the move's crew (he comes or goes; a hirer who left ends the hire) and his
--                              hands (Moving's helper hooks)
--   MoveHelper.step(dt)        one step of every helper (his loop's; the runtime test calls it)
--   MoveHelper.useMover(m)     how he walks (a test's: the Luau CLI has no physics and no pathfinding)
--   MoveHelper.nameOf(id)      his name by his id in a move's rules (nil: not a helper's id)
--   MoveHelper.find(player)    the helper on this player's move (his state: tests, the admin, server/SandboxTasks.luau)
--   MoveHelper.call(s, p, spot)    8.3 Moving's Lift on a two-person piece: "wait" (a call: you wait, he comes), "cancel"
--                              (Lift again while you wait: you stop), "ready" (he is in place: the lift goes on), "busy"
--                              (8.3 review: a crew mate waits for him at it: refused, told who), nil (not hired, no
--                              Danny for it now: today's rules, you drag it alone)
--   MoveHelper.cancel(p)       8.3 G (Moving's PutDown) while you wait: the call is off (true when there was one)
--   MoveHelper.joinLift(s, spot, p)   8.3 Moving's pick of a called piece: he takes its far end at once (the hold starts
--                              there: no pause, no snap); true when he did
--   MoveHelper.taken(s, spot, p)   8.3 Moving's pick: a piece a player picked up leaves his list
-- 7.x farm move: a place with several ways in and out (a farm's front door and barn doors: the session's `ways`, each
-- an exit inside, where you come in by it and its door's outside) has him take the nearest way he may (Moving's
-- helperExits: a piece may only leave by the exits it fits through) and come out at its own door.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.MovingRules)
local Brain = require(Shared.MoveHelperBrain)
local Npcs = require(script.Parent.Npcs)
local PairHold = require(script.Parent.PairHold) -- 8.1: the far end's hold (Danny's and a crew mate's)
local PlayerData = require(script.Parent.PlayerData) -- 8.3: the hire's money
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)

local cfg = Config.MoveHelper
local MoveHelper = {}

-- His hands: server/Moving.luau's helper hooks (Moving itself is passed: no require loop).
export type Port = {
	helperTake: (s: any, spot: number, npc: Model) -> (boolean, string?),
	helperDrop: (s: any, npc: Model, why: string) -> (),
	helperLoad: (s: any, npc: Model) -> (boolean, string?),
	helperHurt: (s: any, npc: Model, hp: number) -> (),
	helperExits: ((s: any, spot: number?) -> { number })?, -- 7.x farm move: the ways out he may take with it
	-- 8.3 your call: where `player` will hold the piece lifted with him (its far end is his place), your lift once he is
	-- in place (true: its check opened, or it is up), the piece's Lift prompt ("wait" | "ask" | nil: as ever)
	helperLiftFrame: ((s: any, spot: number, player: Player) -> CFrame?)?,
	helperCalled: ((s: any, spot: number, player: Player) -> boolean)?,
	helperMark: ((s: any, spot: number, how: string?) -> ())?,
	helperCallOff: ((s: any, spot: number, player: Player) -> ())?, -- (the call off once he was there: its open lift check closes)
}

-- 7.x his hold on the far end of your piece (the real mover's; 8.1 server/PairHold.luau's): the attachment on the piece
-- and on his root, the two constraints, his parts' own collision groups (given back when he lets go).
export type Grip = PairHold.Hold

-- 7.x farm move: one way in and out (the house's front door; a farm's barn doors too): the exit inside, where he comes
-- in, the door's outside, as Brain.Doors for the costs.
type Way = { exitIn: Vector3, entryIn: CFrame, outside: CFrame, doors: Brain.Doors }

export type Body = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	walking: boolean,
	ordered: Vector3?, -- where the walk was last ordered
	orderedAt: number,
	speed: number,
	path: Path?, -- his PathfindingService path (made once)
	grip: Grip?, -- 7.x carrying together (the real mover)
	alpha: { [Instance]: number }?, -- 7.x his parts' own transparency (a fade-over)
	fade: number, -- 7.x the fade-over in progress
	sit: AnimationTrack?, -- 8.3 Roblox's sit, played while he rides in the van (loaded at his first ride)
	weights: { [BasePart]: boolean }?, -- 8.3 his parts' own Massless while he rides (given back when he gets out)
}

-- How he walks: one step toward `to` at `speed` studs / s; a stop; his way round the walls (may yield; nil: straight).
-- 7.x carrying together: keep him at `offset` in `anchor`'s frame (the far end of your piece) / let go of it; a fade-in
-- where he was just put (the fade-over). 8.1: keep walks him there at `limit` studs / s at most (snap: put there, a
-- door's fade only). Without keep he steps there at `limit` × dt at most (a test: no physics).
export type Mover = {
	move: (body: Body, to: Vector3, speed: number, dt: number) -> (),
	halt: (body: Body) -> (),
	route: ((body: Body, from: Vector3, to: Vector3) -> { Vector3 }?)?,
	keep: ((body: Body, anchor: BasePart, offset: CFrame, dt: number, limit: number, snap: boolean) -> ())?,
	free: ((body: Body) -> ())?,
	appear: ((body: Body) -> ())?,
}

-- 8.3 a crew player's call: their two-person piece, since when, he is in place (their lift check open) since readyAt,
-- his walk there (MoveHelperBrain.approach: the last resort's clock).
type Call = { player: Player, spot: number, since: number, ready: boolean, readyAt: number, approach: Brain.Approach }

type Helper = {
	s: any, -- server/Moving.luau's Session (read here: move, site, origin, plan, items, truck, owner, members, ended, id)
	port: Port,
	id: number, -- his id in the move's rules (MovingRules' holders): ID_BASE - the move's id
	body: Body?,
	hooks: { RBXScriptConnection },
	health: number, -- his health a step ago (a bite takes a share of what he holds)
	dead: boolean,
	downAt: number,
	action: string,
	spot: number?,
	fleeing: boolean,
	fleeAt: Vector3?,
	fleeSet: number,
	stuckFor: number,
	repathed: boolean, -- a new path asked in this stuck spell (StuckRepath)
	lastPos: Vector3?,
	doorAt: number, -- when he last went through the front door (not back at once)
	path: { Vector3 },
	pathIndex: number,
	pathGoal: Vector3?,
	pathAt: number,
	pathing: boolean,
	pathFailedAt: number, -- 7.x when his last path failed
	gaveUp: { [number]: number }, -- the lifts whose take failed: until when (HelpRetry s; or the piece goes down)
	helpSince: number, -- 7.x when he set off to your lift (HelpBlink)
	gripped: BasePart?, -- 7.x the piece whose far end he holds (its root)
	holdOffset: CFrame?, -- 7.x his place in its frame
	trail: Brain.Trail, -- 8.1 how long he has been behind his place at the far end (MoveHelperBrain.holdTrack)
	holdAt: Vector3?, -- 8.1 where his root was a step ago holding it (his legs' speed)
	holdLimit: number, -- 8.1 his top speed holding it now (the tests read it)
	steadied: Model?, -- 7.x the carrier's character with GripSteady
	lineKey: string?, -- 7.x a line to say at lineAt ("On three... lift!" after "Got the other end!")
	lineAt: number,
	vanSaid: number?, -- 7.x the piece "That's going in the van." was said for
	waited: number, -- s at the van's shut back with a piece
	dropping: boolean, -- he sets the piece in his arms down beside the van (no room, the back stayed shut)
	thinkAt: number,
	lift: number?,
	pick: number?, -- 8.3 the piece of his list he goes for (MoveHelperBrain.nextQueued)
	pair: boolean, -- … a two-person one
	full: boolean, -- 8.3 pieces on his list, none fits the van
	toldFull: boolean, -- "Van's full" said since it got full
	fitKey: number, -- the van's load when fits was worked out
	fits: { [number]: boolean },
	input: Brain.Input,
	lifts: { Brain.Lift },
	liftPool: { Brain.Lift },
	next: { Brain.Queued }, -- 8.3 his list for nextQueued (its entries kept in nextPool)
	nextPool: { Brain.Queued },
	doors: Brain.Doors,
	doorways: { Brain.Doorway }, -- 7.x the interior's doorways (world)
	fronts: { Brain.Doorway }, -- 7.x the doors outside (the front door; a farm's barn doors too)
	exitIn: Vector3, -- the front door inside (where "Leave house" is)
	entryIn: CFrame, -- where you come in
	ways: { Way }, -- 7.x farm move: every way (ways[1] the front door: doors, exitIn, entryIn)
	wayDoors: { Brain.Doors }, -- (their doors, for Brain.routeVia)
	saidAt: { [string]: number },
	lastSaid: number,
	doing: string,
	doingAction: string,
	doingSpot: number?,
	doingFull: boolean,
	doingHired: boolean,
	told: { [Player]: boolean }, -- the players with his attributes
	call: Call?, -- 8.3 a crew player waits for him at their two-person piece
	helpWalk: Brain.Approach?, -- 8.3 his walk to a piece you drag alone (the last resort's clock)
	-- 8.3 for hire
	hirer: Player?, -- who hired him for this move (nil: for hire)
	price: number, -- the hire for this move (MoveHelperBrain.hirePrice)
	queue: { number }, -- his list: the pieces' spots in the order they were clicked
	marks: { [number]: BillboardGui }, -- the markers over them
	needs: number?, -- the two-person piece of his list he waits at for you …
	needsAt: number, -- … since (0: on his way)
	needsTold: number?, -- the one the crew was told about (once a piece)
	sign: BillboardGui?, -- "Hire Danny · $X" over his head while he is for hire
	seat: Seat?, -- the van's passenger seat he sits in
	seatCar: Vehicles.Car?, -- 8.3 review: the van that seat is in (he gets out at its door, whatever became of it)
	yieldAt: number, -- 8.3 review: he gave his seat up to a crew mate: no seat for him until then (os.clock)
	rideWalk: Brain.Approach?, -- his walk to the van to ride (the last resort's clock)
}

local ID_BASE = -2000000000 -- (no player's id is this low; Studio's test players are -1, -2 …)
local FALL = 3 -- s he lies there before his body goes
local INSIDE = 400 -- studs from a move's interior origin that count as inside it
local NUDGE = 8 -- studs at most a stuck nudge puts him on (his way's next point)
local WALK = { through = true, near = 0.6, jump = false } -- Npcs.walkTo's options: he walks on into the next order (8.3: no jump)
local HANDS = { "Carrying", "CarryCount", "CarryHands", "CarryAt", "CarrySize" } -- 7.x his arms (client/ArmPose.luau)
local EDGE = { Width = 2.4, Depth = 0.6 } -- 7.x the piece's near edge his hands hold at its far end (studs)
local SIT = "rbxassetid://2506281703" -- 8.3 Roblox's R15 sit (server/Buddy.luau's)
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local ATTRIBUTES = { "MoveHelper", "MoveHelperDoing", "MoveHelperId", "MoveHelperCall", "MoveHelperReady", "MoveHelperPrice", "MoveHelperQueue" }

local helpers: { [any]: Helper } = {} -- by the move's session
local byId: { [number]: Helper } = {}
local wired = false
local notice = Net.get("Notice")

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function walkSpeed(): number
	return Config.Movement.Walk
end

-- ── How he walks (a test gives its own) ────────────────────────────────────

local function computeRoute(body: Body, from: Vector3, to: Vector3): { Vector3 }?
	local path = body.path
	if not path then
		-- (8.3: never a jump, never a climb; Config.MoveHelper's Path* numbers)
		local made = game:GetService("PathfindingService"):CreatePath({ AgentRadius = cfg.PathRadius, AgentHeight = cfg.PathHeight, AgentCanJump = false,
			AgentCanClimb = false, WaypointSpacing = cfg.PathSpacing })
		body.path = made
		path = made
	end
	local p = path :: Path
	local ok = pcall(function()
		p:ComputeAsync(from, to)
	end)
	if not ok or (p.Status ~= Enum.PathStatus.Success and p.Status ~= Enum.PathStatus.ClosestNoPath) then
		return nil
	end
	local points: { Vector3 } = {}
	for _, waypoint in p:GetWaypoints() do
		if waypoint.Action ~= Enum.PathWaypointAction.Jump then -- (8.3: he never jumps; walks only)
			table.insert(points, waypoint.Position)
		end
	end
	return points
end

-- 7.x the hold's constraints and attachments gone, his parts' groups given back, he stands again (8.1 server/
-- PairHold.luau's drop).
local function gripOff(body: Body)
	local grip = body.grip
	if not grip then
		return
	end
	body.grip = nil
	PairHold.drop(grip)
	Npcs.carried(body.model, false)
	body.speed = -1 -- (Npcs.pace again on his next walk)
end

-- 7.x his root glued to `offset` in the piece's frame: AlignPosition and AlignOrientation between an attachment on his
-- root and one on the piece (the physics engine moves him every step, the server owns him), his own walk off, his parts
-- in the group nothing collides with (8.1 server/PairHold.luau's make: at `limit` studs / s at most).
local function gripOn(body: Body, anchor: BasePart, offset: CFrame, limit: number)
	gripOff(body)
	Npcs.carried(body.model, true)
	body.walking, body.ordered = false, nil
	body.grip = PairHold.make(body.model, body.root, anchor, offset, limit, { ghost = true, flat = false, owner = nil, lift = true }) -- (8.3 lift)
end

local mover: Mover = {
	move = function(body: Body, to: Vector3, speed: number, _dt: number)
		if math.abs(body.speed - speed) > 0.05 then
			body.speed = speed
			Npcs.pace(body.model, speed)
		end
		local ordered = body.ordered
		local clock = os.clock()
		if not body.walking or not ordered or (to - ordered).Magnitude > 1.5 or clock - body.orderedAt > 2 then
			body.walking, body.ordered, body.orderedAt = true, to, clock
			Npcs.walkTo(body.model, to, nil, 8, WALK)
		end
	end,
	halt = function(body: Body)
		if body.walking then
			body.walking, body.ordered = false, nil
			Npcs.stop(body.model)
		end
	end,
	route = computeRoute,
	-- 7.x carrying together: the constraints made once (again for another piece), the far end's attachment re-aimed
	-- when his place moved (the floor under it); 8.1 his top speed (the pair's walk and a margin), put there at once
	-- only through a door's fade (snap: MoveHelperBrain.holdTrack); his legs: actHold's
	keep = function(body: Body, anchor: BasePart, offset: CFrame, _dt: number, limit: number, snap: boolean)
		local grip = body.grip
		if not grip or not PairHold.alive(grip, anchor) then
			gripOn(body, anchor, offset, limit)
			grip = body.grip
		end
		local g = grip :: Grip
		PairHold.aim(g, offset, limit)
		if snap then
			PairHold.snap(g, anchor.CFrame * offset)
		end
	end,
	free = gripOff,
	-- 7.x the fade-over's end: he fades in where he was just put (his parts from clear to their own look)
	appear = function(body: Body)
		local alpha = body.alpha
		if not alpha then
			local seen: { [Instance]: number } = {}
			for _, d in body.model:GetDescendants() do
				if d:IsA("BasePart") then
					seen[d] = d.Transparency
				elseif d:IsA("Decal") then
					seen[d] = d.Transparency
				end
			end
			alpha = seen
			body.alpha = seen
		end
		local own = alpha :: { [Instance]: number }
		body.fade += 1
		local token = body.fade
		for obj in own do
			(obj :: any).Transparency = 1
		end
		task.spawn(function()
			for k = 1, 5 do
				task.wait(0.05)
				if body.fade ~= token then
					return
				end
				for obj, t in own do
					if obj.Parent then
						(obj :: any).Transparency = 1 - (1 - t) * k / 5
					end
				end
			end
		end)
	end,
}

function MoveHelper.useMover(given: Mover)
	mover = given
end

-- ── Small helpers ──────────────────────────────────────────────────────────

local function insideAt(h: Helper, at: Vector3): boolean
	local origin: CFrame = h.s.origin
	return (at - origin.Position).Magnitude < INSIDE
end

local function truckOf(s: any): Vehicles.Car?
	local truck: Vehicles.Car? = s.truck
	if truck and not truck.wrecked and truck.model.Parent then
		return truck
	end
	return nil
end

-- The van stands by the house (he carries pieces out only then).
local function truckAtHouse(s: any, truck: Vehicles.Car?): boolean
	local door: Vector3 = s.site.door
	return truck ~= nil and flat(truck.chassis.Position, door) <= cfg.TruckFar
end

local function truckStill(truck: Vehicles.Car): boolean
	return Vehicles.speed(truck) <= Config.Cargo.MaxCarSpeed
end

-- A point by the van's back: `side` studs to its right, `out` studs out of it (nil: no back).
local function byTruck(truck: Vehicles.Car, side: number, out: number): Vector3?
	local door = Vehicles.cargoDoor(truck)
	if not door then
		return nil
	end
	local at = door.WorldPosition
	local chassis = truck.chassis.Position
	local away = Vector3.new(at.X - chassis.X, 0, at.Z - chassis.Z)
	local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	return Vector3.new(at.X, chassis.Y, at.Z) + dir * out + right * side
end

local NOT_FLOOR = { "Npcs", "Zombies", "Cars", "Traffic", "BanditCars", "Animals", "Moves" } -- (outside: never a floor)

-- The ground under (x, z) near refY (outside), else refY.
local function groundAt(x: number, z: number, refY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, name in NOT_FLOOR do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(x, refY + 6, z), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else refY
end

-- 7.x the interior's floor under (x, z) near refY (its shell only: not the furniture, not the counters; the Moves folder
-- it sits in is left out of groundAt's ray), else the floor at its front door (its origin).
local function interiorFloorAt(h: Helper, x: number, z: number, refY: number): number
	local origin: CFrame = h.s.origin
	local interior: Instance? = h.s.interior
	if interior and interior.Parent then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { interior:FindFirstChild("Shell") or interior }
		params.RespectCanCollide = true
		local hit = workspace:Raycast(Vector3.new(x, refY + 6, z), Vector3.new(0, -40, 0), params)
		if hit then
			return hit.Position.Y
		end
	end
	return origin.Position.Y
end

-- 8.3 the floor under (at.X, at.Z) a ray finds from `top` down `reach` studs (inside: the interior's shell only;
-- outside: not the pieces, the bodies, the cars: NOT_FLOOR and the players' characters), nil when it finds none. The
-- hold's (MoveHelperBrain.endRise): from the leader's root down (their floor, whatever their jump), and under his end
-- from a step over that floor down to a step under it: never the porch's roof, a ceiling, a door's header or an eave
-- over it (the ray from 6 studs over the piece's middle found the porch's roof with a 3.3-stud Dining Table: his end out
-- of the front door, he popped HoldStep up).
local function floorDown(h: Helper, at: Vector3, top: number, reach: number): number?
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	if insideAt(h, at) then
		local interior: Instance? = h.s.interior
		if not interior or not interior.Parent then
			return nil
		end
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { interior:FindFirstChild("Shell") or interior }
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = {}
		for _, name in NOT_FLOOR do
			local folder = workspace:FindFirstChild(name)
			if folder then
				table.insert(ignore, folder)
			end
		end
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
	end
	local hit = workspace:Raycast(Vector3.new(at.X, top, at.Z), Vector3.new(0, -reach, 0), params)
	return if hit then hit.Position.Y else nil
end

local function clearPath(h: Helper)
	table.clear(h.path)
	h.pathIndex, h.pathGoal = 1, nil
end

local function tell(h: Helper, text: string)
	for player in h.s.members do
		if player.Parent then
			notice:FireClient(player, text)
		end
	end
end

-- A line in a speech bubble (never the same within TalkRepeat s, two TalkGap s apart; `force`: now; 7.x the lines of
-- the moment, URGENT, wait for no TalkGap): true when said.
local URGENT: { [string]: boolean } = { help = true, three = true, door = true, open = true, mine = true, hired = true, queued = true, ride = true }
local function say(h: Helper, key: string, clock: number, force: boolean?): boolean
	local body = h.body
	local text = Brain.line(key, Config.Sandbox.On) -- (8.0 SANDBOX: no Wall, no depot in his words)
	if not body or not text then
		return false
	end
	local last = h.saidAt[key]
	if not force and ((last and clock - last < cfg.TalkRepeat) or (clock - h.lastSaid < cfg.TalkGap and not URGENT[key])) then
		return false
	end
	h.saidAt[key], h.lastSaid = clock, clock
	Npcs.say(body.model, text, 3)
	return true
end

-- 8.3 "Hire Danny · $X" over his head while he is for hire (a sign the clients see from a little way off).
local function hireSign(h: Helper)
	local body = h.body
	local want = body ~= nil and h.hirer == nil and not h.dead
	local sign = h.sign
	if want and body and (not sign or sign.Parent ~= body.root) then
		if sign then
			sign:Destroy()
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "HireSign"
		gui.Size = UDim2.fromOffset(190, 30)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.7, 0)
		gui.MaxDistance = 80
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = ORANGE
		label.TextColor3 = Color3.fromRGB(28, 28, 30)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.Text = `🧑‍🔧 Hire {cfg.Name} · {Brain.money(h.price)}`
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		gui.Parent = body.root
		h.sign = gui
	elseif not want and sign then
		sign:Destroy()
		h.sign = nil
	end
end

-- His attributes on the crew (the status line, his card): for hire or hired, the price or his list, what he does; off
-- for those who left.
local function tellCrew(h: Helper)
	local s = h.s
	local hired = h.hirer ~= nil
	local state = if hired then "hired" else "offer"
	local price: number? = if hired then nil else h.price
	local count: number? = if hired then #h.queue else nil
	for player in s.members do
		if not player.Parent then
			continue
		end
		h.told[player] = true
		if player:GetAttribute("MoveHelper") ~= state then
			player:SetAttribute("MoveHelper", state)
		end
		if player:GetAttribute("MoveHelperDoing") ~= h.doing then
			player:SetAttribute("MoveHelperDoing", h.doing)
		end
		if player:GetAttribute("MoveHelperId") ~= h.id then
			player:SetAttribute("MoveHelperId", h.id) -- 8.3 (his card finds his body by it)
		end
		if player:GetAttribute("MoveHelperPrice") ~= price then
			player:SetAttribute("MoveHelperPrice", price)
		end
		if player:GetAttribute("MoveHelperQueue") ~= count then
			player:SetAttribute("MoveHelperQueue", count)
		end
	end
	for player in h.told do
		if not s.members[player] then
			h.told[player] = nil
			for _, name in ATTRIBUTES do
				player:SetAttribute(name, nil)
			end
		end
	end
	hireSign(h)
end

-- What he does, in words (made again only when it changes).
local function setDoing(h: Helper, action: string, spot: number?)
	local hired = h.hirer ~= nil
	if action == h.doingAction and spot == h.doingSpot and h.full == h.doingFull and hired == h.doingHired then
		return
	end
	h.doingAction, h.doingSpot, h.doingFull, h.doingHired = action, spot, h.full, hired
	local thing = if spot then (h.s.move :: Rules.Move).things[spot] else nil
	h.doing = if not hired and action == "wait" then Brain.doing("offer") else Brain.doing(action, if thing then thing.name else nil, h.full)
end

-- ── 8.3 your call and his list: the words, the marks ───────────────────────

-- The piece's Lift prompt (Moving's helperMark): "wait" (you wait: "Stop waiting"), "ask" ("Lift with Danny"), nil.
local function mark(h: Helper, spot: number, how: string?)
	local marker = h.port.helperMark
	if marker then
		marker(h.s, spot, how)
	end
end

-- A short bubble over a player's head (your "Danny, give me a hand!"), gone a moment later.
local function shout(character: Model?, text: string)
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("CallBubble")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CallBubble"
	gui.Size = UDim2.fromOffset(230, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(250, 250, 246)
	label.TextColor3 = Color3.fromRGB(28, 28, 30)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextWrapped = true
	label.Text = text
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	gui.Parent = head
	task.delay(2.5, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

-- The marker over a piece of his list (seen through walls: the crew finds it): its number, or "needs you".
local function newMark(root: BasePart, height: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "DannyMark"
	gui.Size = UDim2.fromOffset(160, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 1.8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(250, 250, 246)
	label.TextColor3 = Color3.fromRGB(28, 28, 30)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local edge = Instance.new("UIStroke")
	edge.Color = ORANGE
	edge.Thickness = 2
	edge.Parent = label
	gui.Parent = root
	return gui
end

-- His list's markers and the pieces' attributes (DannyQueue = its number, DannyNeeds while he waits at it for you) as
-- the list is now; the gone ones off.
local function refreshMarks(h: Helper)
	local s = h.s
	local listed: { [number]: boolean } = {}
	for index, spot in h.queue do
		local item = s.items[spot]
		local thing = (s.move :: Rules.Move).things[spot]
		if not item or not thing then
			continue
		end
		listed[spot] = true
		local needs = h.needs == spot and h.needsAt > 0
		local gui = h.marks[spot]
		if not gui or gui.Parent ~= item.root then
			if gui then
				gui:Destroy()
			end
			local fresh = newMark(item.root, thing.size.Y)
			h.marks[spot] = fresh
			gui = fresh
		end
		local label = (gui :: BillboardGui):FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = Brain.markText(index, needs)
			label.BackgroundColor3 = if needs then ORANGE else Color3.fromRGB(250, 250, 246)
		end
		if item.model:GetAttribute("DannyQueue") ~= index then
			item.model:SetAttribute("DannyQueue", index)
		end
		if item.model:GetAttribute("DannyNeeds") ~= (if needs then true else nil) then
			item.model:SetAttribute("DannyNeeds", if needs then true else nil)
		end
	end
	for spot, gui in h.marks do
		if not listed[spot] then
			gui:Destroy()
			h.marks[spot] = nil
			local item = s.items[spot]
			if item then
				item.model:SetAttribute("DannyQueue", nil)
				item.model:SetAttribute("DannyNeeds", nil)
			end
		end
	end
end

-- Off his list (true when it was on it).
local function unqueue(h: Helper, spot: number): boolean
	local index = table.find(h.queue, spot)
	if index then
		table.remove(h.queue, index)
		return true
	end
	return false
end

-- He no longer waits at a two-person piece of his list for you: its prompt as ever (unless a call is on it).
local function endNeeds(h: Helper)
	local spot = h.needs
	h.needs, h.needsAt = nil, 0
	if spot then
		local call = h.call
		if not (call and call.spot == spot) then
			mark(h, spot, nil)
		end
		refreshMarks(h)
	end
end

local CALL_OFF: { [string]: string } = {
	cancel = "You stopped waiting for Danny.",
	away = "You walked away: Danny's call is off.",
	idle = "Danny waited at its other end, nobody lifted: his call is off.",
	down = "Danny is down: lift it when he's back, or drag it alone.",
}

-- The call is over (why: "cancel" | "away" | "idle" | "down" | "gone" | nil: said to the caller when it has words).
local function endCall(h: Helper, why: string?, clock: number)
	local call = h.call
	if not call then
		return
	end
	h.call = nil
	mark(h, call.spot, if h.needs == call.spot and h.needsAt > 0 then "ask" else nil)
	local player = call.player
	if player.Parent then
		player:SetAttribute("MoveHelperCall", nil)
		player:SetAttribute("MoveHelperReady", nil)
	end
	local off = h.port.helperCallOff
	if call.ready and off then
		off(h.s, call.spot, player) -- (its lift check, when open, closes with it: never a lift alone after)
	end
	if not h.gripped then
		local was = h.steadied
		if was and was.Parent then
			was:SetAttribute("GripSteady", nil)
		end
		h.steadied = nil
	end
	local text = if why then CALL_OFF[why] else nil
	if text and player.Parent then
		notice:FireClient(player, text)
	end
	h.thinkAt = 0
end

-- 8.3 review: a player by their id in the move's rules (nil: one of the helpers' own ids, ID_BASE and under). Studio's
-- test players have ids -1, -2 …: players all the same (never a check for a positive id).
local function playerOf(id: number?): Player?
	return if id and id > ID_BASE then Players:GetPlayerByUserId(id) else nil
end

-- A player's body's root (nil: no body).
local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function playerRoot(id: number?): BasePart?
	return rootOf(playerOf(id))
end

-- ── Doorways (7.x: he never stands where you walk through) ─────────────────

-- The interior's doorways in the world (the plan's, at its origin) and the doors outside (the site's: the front door, a
-- farm's barn doors too).
local function doorwaysOf(s: any, origin: CFrame): ({ Brain.Doorway }, { Brain.Doorway })
	local a = cfg.Aside
	local list: { Brain.Doorway } = {}
	local frontHalf = 2
	for _, door in (s.plan.doors or {}) :: { any } do
		local at = origin * (door.at :: Vector3)
		local through = if door.axis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0) -- (a wall along X: through along Z)
		local dir = (origin * through) - origin.Position
		local half = (tonumber(door.width) or 4) / 2
		if door.front then
			frontHalf = half
		end
		table.insert(list, { x = at.X, z = at.Z, half = half, dirX = dir.X, dirZ = dir.Z, depth = a.Depth })
	end
	local site = s.site
	local fronts: { Brain.Doorway } = {}
	for index, d in (if type(site.doors) == "table" then site.doors else {}) :: { any } do
		local foot: Vector3, facing: Vector3 = d.door, d.facing
		local half = if index == 1 then frontHalf else (tonumber(d.width) or 4) / 2
		table.insert(fronts, { x = foot.X, z = foot.Z, half = half, dirX = facing.X, dirZ = facing.Z, depth = a.FrontDepth })
	end
	if #fronts == 0 then
		local facing: Vector3 = site.facing
		local doorAt: Vector3 = site.door
		table.insert(fronts, { x = doorAt.X, z = doorAt.Z, half = frontHalf, dirX = facing.X, dirZ = facing.Z, depth = a.FrontDepth })
	end
	return list, fronts
end

-- A place where he will stand still: moved beside a doorway it is in (inside: the interior's; outside: the front door).
local function clearOf(h: Helper, at: Vector3, inside: boolean): Vector3
	local doors: { Brain.Doorway } = if inside then h.doorways else h.fronts
	for _, door in doors do
		local x, z, moved = Brain.aside(at.X, at.Z, door)
		if moved then
			return Vector3.new(x, at.Y, z)
		end
	end
	return at
end

-- Is a point within `reach` studs of an interior doorway (or the front door inside)?
local function nearDoorway(h: Helper, at: Vector3, reach: number): boolean
	for _, door in h.doorways do
		local dx, dz = at.X - door.x, at.Z - door.z
		if math.sqrt(dx * dx + dz * dz) <= door.half + reach then
			return true
		end
	end
	return false
end

-- ── His body ───────────────────────────────────────────────────────────────

-- The floor under a point: the interior's (inside), else the ground under it.
local function floorAt(h: Helper, at: Vector3): number
	return if insideAt(h, at) then interiorFloorAt(h, at.X, at.Z, at.Y) else groundAt(at.X, at.Z, at.Y)
end

-- Stands him with his feet at `at`, facing along `face` (flat); the walk stops, the way is worked out again.
local function placeAt(h: Helper, at: Vector3, face: Vector3?)
	local body = h.body
	if not body then
		return
	end
	mover.halt(body)
	local look = face or body.root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local up = Vector3.new(at.X, floorAt(h, at) + body.humanoid.HipHeight + body.root.Size.Y / 2, at.Z)
	body.model:PivotTo(if flatLook.Magnitude > 0.05 then CFrame.lookAt(up, up + flatLook) else CFrame.new(up))
	h.lastPos, h.stuckFor, h.repathed = nil, 0, false
	clearPath(h)
end

-- 7.x the carrier's grip box bigger while he holds the other end (the character attribute GripSteady).
local function steady(h: Helper, character: Model?)
	local was = h.steadied
	if was == character then
		return
	end
	if was and was.Parent then
		was:SetAttribute("GripSteady", nil)
	end
	h.steadied = character
	if character then
		character:SetAttribute("GripSteady", true)
	end
end

-- 7.x the far end let go of: the glue off (he stands again), the carrier's grip as before.
local function ungrip(h: Helper, body: Body?)
	local free = mover.free
	if body and free then
		free(body)
	end
	steady(h, nil)
	h.gripped, h.holdOffset, h.lineKey, h.holdAt = nil, nil, nil, nil
end

-- …and on his feet on the floor where he is.
local function unhold(h: Helper, body: Body)
	ungrip(h, body)
	placeAt(h, body.root.Position, body.root.CFrame.LookVector)
end

-- 7.x his arms (client/ArmPose.luau reads them on every body in workspace.Npcs): a piece of his own held like a
-- player's (its box in his root's frame), the far end of yours by its near edge; nothing held: down.
local function poseHands(h: Helper, body: Body, spot: number?, role: string?)
	local model = body.model
	local thing = if spot then (h.s.move :: Rules.Move).things[spot] else nil
	local item = if spot then h.s.items[spot] else nil
	if not thing or not item or h.dead then
		if model:GetAttribute("Carrying") ~= nil then
			for _, name in HANDS do
				model:SetAttribute(name, nil)
			end
		end
		return
	end
	local together = role == "helper"
	local at: Vector3
	local size: Vector3
	if together then
		local offset = h.holdOffset
		if not offset then
			return
		end
		local middle = offset:Inverse().Position -- (the piece's middle from his root)
		at = Vector3.new(0, middle.Y, -(cfg.Standoff + EDGE.Depth / 2))
		size = Vector3.new(math.min(thing.size.X, EDGE.Width), thing.size.Y, EDGE.Depth)
	else
		at = body.root.CFrame:PointToObjectSpace(item.root.Position)
		size = Vector3.new(thing.size.X, thing.size.Y, thing.size.Z)
	end
	local alone = not together and thing.class == "hand"
	local carrying = if alone then "crate" else "furniture"
	if model:GetAttribute("Carrying") ~= carrying then
		model:SetAttribute("Carrying", carrying)
	end
	if model:GetAttribute("CarryCount") ~= 1 then
		model:SetAttribute("CarryCount", 1)
	end
	local hands = if alone then 1 else 2
	if model:GetAttribute("CarryHands") ~= hands then
		model:SetAttribute("CarryHands", hands)
	end
	local was = model:GetAttribute("CarryAt")
	if typeof(was) ~= "Vector3" or (was - at).Magnitude > 0.05 then
		model:SetAttribute("CarryAt", at)
	end
	local wasSize = model:GetAttribute("CarrySize")
	if typeof(wasSize) ~= "Vector3" or (wasSize - size).Magnitude > 0.01 then
		model:SetAttribute("CarrySize", size)
	end
end

-- Where he comes (and comes back): by the van's back (on its left: out of the way), else outside the house's door.
local function homeSpot(h: Helper): Vector3
	local truck = truckOf(h.s)
	local spot = if truck then byTruck(truck, -4, 3) else nil
	if spot then
		return spot
	end
	local out: CFrame = h.s.site.outside
	return clearOf(h, out.Position, false)
end

-- ── 8.3 the van's passenger seat ───────────────────────────────────────────

local function seatsOf(truck: Vehicles.Car): { Seat }
	local list = (truck :: any).passengers
	return if type(list) == "table" then list else {}
end

-- The van's passenger seat he takes (MoveHelperBrain.pickSeat: the first nobody sits in), nil: every one taken. 8.3
-- review: a seat somebody is getting into (Vehicles' boarding reserves it: its attribute Reserved) is taken too.
local function freeSeat(truck: Vehicles.Car): Seat?
	local seats = seatsOf(truck)
	local taken: { boolean } = {}
	for index, seat in seats do
		taken[index] = seat.Parent == nil or seat.Occupant ~= nil or seat:GetAttribute("Reserved") ~= nil
	end
	local index = Brain.pickSeat(taken)
	return if index then seats[index] else nil
end

-- Outside a seat's door (Vehicles' doors: its side, its place along the van), a step out of the van's side.
local function seatDoor(truck: Vehicles.Car, seat: Seat): Vector3
	local doors = (truck :: any).doors
	local index = seat:GetAttribute("Door")
	local door = if type(doors) == "table" and type(index) == "number" then doors[index] else nil
	local size: Vector3 = (truck :: any).size or Vector3.new(6, 6, 12)
	local frame = truck.chassis.CFrame
	if door then
		return (frame * CFrame.new(door.side * (size.X / 2 + 1.5), 0, door.z)).Position
	end
	local rel = frame:PointToObjectSpace(seat.Position)
	return (frame * CFrame.new((if rel.X < 0 then -1 else 1) * (size.X / 2 + 1.5), 0, rel.Z)).Position
end

-- Does the move's owner sit at the van's wheel (only the owner drives their van)?
local function driven(s: any, truck: Vehicles.Car?): boolean
	if not truck then
		return false
	end
	local car, driving = Vehicles.seatedIn(s.owner)
	return driving and car == truck
end

-- His parts massless while he rides (the van drives as ever), their own Massless given back after.
local function setMassless(body: Body, on: boolean)
	if not on then
		local was = body.weights
		body.weights = nil
		if not was then
			return
		end
		for part, massless in was do
			if part.Parent then
				part.Massless = massless
			end
		end
		return
	end
	local was: { [BasePart]: boolean } = body.weights or {}
	for _, d in body.model:GetDescendants() do
		if d:IsA("BasePart") then
			if was[d] == nil then
				was[d] = d.Massless == true
			end
			d.Massless = true
		end
	end
	body.weights = was
end

local function sitTrack(body: Body): AnimationTrack?
	local made = body.sit
	if made then
		return made
	end
	local animator = body.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(function(): AnimationTrack
		local animation = Instance.new("Animation")
		animation.AnimationId = SIT
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		body.sit = track
	end
	return body.sit
end

-- Into the seat (of `truck`): his walk over, his body free (welded to the seat by Seat:Sit, massless: the van drives as
-- ever), the sit pose. Never his hold (he holds nothing), never Npcs.carried.
local function sitIn(h: Helper, body: Body, seat: Seat, truck: Vehicles.Car)
	Npcs.stop(body.model)
	body.walking, body.ordered = false, nil
	clearPath(h)
	setMassless(body, true)
	body.root.Anchored = false
	body.model:PivotTo(seat.CFrame * CFrame.new(0, body.humanoid.HipHeight + body.root.Size.Y / 2, 0))
	seat:Sit(body.humanoid)
	h.seat, h.seatCar = seat, truck
	h.stuckFor, h.lastPos, h.repathed, h.rideWalk = 0, nil, false, nil
	local track = sitTrack(body)
	if track then
		track:Play(0.15)
	end
	h.thinkAt = 0
end

-- 8.3 review: a spot clear of every car's parts (workspace.Cars: the ground's ray never finds them, he would stand in
-- one): on along `out`, 2 studs at a time, 3 times at most.
local function outOfCars(at: Vector3, out: Vector3?): Vector3
	local cars = workspace:FindFirstChild("Cars")
	if not cars or not out or out.Magnitude < 0.05 then
		return at
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { cars }
	for _ = 1, 3 do
		if #workspace:GetPartBoundsInBox(CFrame.new(at), Vector3.new(2, 8, 2), params) == 0 then
			break
		end
		at += out.Unit * 2
	end
	return at
end

-- Out of the seat: out at its door, standing on the ground. 8.3 review: always the door of the seat he sat in, of the
-- van he got into (h.seatCar; else `truck`): wrecked, ejected, on a repair lift, taken away, its door where the van
-- stands or stood (a seat or a van gone keeps its last place), never where he sits, in its shell; clear of the cars;
-- `aside` studs farther out (out of the way of whoever gets in there).
local function unseat(h: Helper, body: Body, truck: Vehicles.Car?, aside: number?)
	local seat = h.seat
	local car = h.seatCar or truck
	h.seat, h.seatCar = nil, nil
	local track = body.sit
	if track then
		track:Stop(0.15)
	end
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	body.humanoid.Sit = false
	setMassless(body, false)
	local at = body.root.Position
	local face: Vector3? = nil
	if car and seat then
		at = seatDoor(car, seat)
		local away = Vector3.new(at.X - car.chassis.Position.X, 0, at.Z - car.chassis.Position.Z) -- (away from the van)
		face = away
		local out = Vector3.new(at.X - seat.Position.X, 0, at.Z - seat.Position.Z) -- (straight out of its door)
		if out.Magnitude < 0.05 then
			out = away
		end
		if aside and out.Magnitude > 0.05 then
			at += out.Unit * aside
		end
		at = outOfCars(at, out)
	end
	Npcs.stop(body.model) -- (stands again, anchored)
	placeAt(h, at, face)
	h.thinkAt = 0
end

local function spawnBody(h: Helper, at: Vector3): boolean
	local look = Npcs.look("mover", cfg.Name, cfg.Title)
	look.walkSpeed = walkSpeed() * cfg.Speed
	local ok, made = pcall(Npcs.spawn, look, CFrame.new(at))
	if not ok or typeof(made) ~= "Instance" then
		warn(`[MoveHelper] no body: {made}`)
		return false
	end
	local model = made :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		Npcs.remove(model) -- (no R15 rig on this server: no helper)
		return false
	end
	model.Name = cfg.Name
	model:SetAttribute("MoveHelper", h.id)
	model:SetAttribute("Busy", true) -- (Npcs' greeting leaves him alone)
	humanoid.MaxHealth = cfg.Health
	humanoid.Health = cfg.Health
	h.health = cfg.Health
	local body: Body = { model = model, root = root, humanoid = humanoid, walking = false, ordered = nil, orderedAt = 0, speed = 0, path = nil, grip = nil, alpha = nil, fade = 0, sit = nil, weights = nil }
	h.body = body
	h.dead = false
	-- a bite (any health lost) knocks what he holds
	table.insert(h.hooks, humanoid.HealthChanged:Connect(function(health: number)
		local before = h.health
		h.health = health
		if health < before and health > 0 and h.body == body and not h.s.ended then
			h.port.helperHurt(h.s, model, before - health)
		end
	end))
	placeAt(h, at, nil)
	hireSign(h)
	return true
end

local function removeBody(h: Helper)
	for _, hook in h.hooks do
		hook:Disconnect()
	end
	table.clear(h.hooks)
	local body = h.body
	local seat = h.seat
	h.seat, h.seatCar = nil, nil
	if seat then
		local weld = seat:FindFirstChild("SeatWeld") -- (8.3 out of the van's seat first)
		if weld then
			weld:Destroy()
		end
	end
	ungrip(h, body) -- (7.x the attachment on the piece goes too)
	h.body = nil
	if h.sign then
		h.sign:Destroy()
		h.sign = nil
	end
	if body then
		Npcs.remove(body.model)
	end
	clearPath(h)
end

-- 8.3 his own piece back at the head of his list (set down for your call, knocked out of his arms).
local function requeue(h: Helper, spot: number?)
	if spot and h.hirer and not table.find(h.queue, spot) then
		table.insert(h.queue, 1, spot)
		refreshMarks(h)
	end
end

-- Down: what he holds falls, he lies on his back; his body goes FALL s later, he is back Respawn s later.
local function fall(h: Helper, body: Body, clock: number)
	endCall(h, "down", clock) -- 8.3
	endNeeds(h)
	if h.seat then
		unseat(h, body, nil) -- (8.3 out of the van's seat first)
	end
	ungrip(h, body)
	local own, role = Rules.holding(h.s.move, h.id)
	h.port.helperDrop(h.s, body.model, "died")
	requeue(h, if role == "carrier" then own else nil)
	say(h, "down", clock, true)
	mover.halt(body)
	h.dead, h.downAt = true, clock
	poseHands(h, body, nil, nil)
	local root = body.root
	local y = floorAt(h, root.Position - Vector3.new(0, 2, 0))
	local at = Vector3.new(root.Position.X, y + 0.6, root.Position.Z)
	body.model:PivotTo(CFrame.new(at) * CFrame.Angles(-math.pi / 2, 0, 0))
	tell(h, `🧑‍🔧 {cfg.Name} is down! He is back at the van in {cfg.Respawn} s.`)
end

-- 7.x farm move: the ways a piece may leave by (Moving's helperExits; nil: every way, one way only, or no piece).
local function exitsOf(h: Helper, spot: number?): { number }?
	local exits = h.port.helperExits
	if not exits or #h.ways < 2 then
		return nil
	end
	return exits(h.s, spot)
end

-- 7.x farm move: the ways he may take now (with what he holds).
local function allowedWays(h: Helper): { number }?
	return exitsOf(h, (Rules.holding(h.s.move, h.id)))
end

-- 7.x farm move: the best way from `here` (inside or not) to `goal` in the other world, among those he may take.
local function wayFor(h: Helper, here: Vector3, inside: boolean, goal: Vector3): Way
	if #h.ways < 2 then
		return h.ways[1]
	end
	local _, which = Brain.routeVia(inside, here.X, here.Z, not inside, goal.X, goal.Z, h.wayDoors, allowedWays(h))
	return h.ways[which] or h.ways[1]
end

-- Through the front door (no fade: he is not a player), to where the players come out or in (7.x farm move: through
-- `way`, the front door's when nil). 8.1 walk-in doors (the players' rule, Config.Moving.Doors): he comes out facing
-- away from the door and out of its reach (DoorReach: inside 1.5 past the entry, outside beside the players' spot), and
-- goes through a door again only Rearm s later (go): no ping-pong.
local function transfer(h: Helper, inside: boolean, clock: number, way: Way?)
	h.doorAt = clock
	local through = way or h.ways[1]
	if inside then
		placeAt(h, through.entryIn.Position + through.entryIn.LookVector * 1.5, through.entryIn.LookVector)
	else
		local out: CFrame = through.outside
		local right = Vector3.new(-out.LookVector.Z, 0, out.LookVector.X)
		placeAt(h, out.Position + right * (cfg.DoorReach + 0.5), out.LookVector)
	end
end

-- ── The way ────────────────────────────────────────────────────────────────

-- The next point toward `target`: his path's (worked out again at most every Repath s, in the background, when the
-- target moved off it, or at once when asked: a stuck spell), else straight.
local function wayTo(h: Helper, body: Body, here: Vector3, target: Vector3, clock: number): Vector3
	local route = mover.route
	local goal = h.pathGoal
	if route and not h.pathing and clock - h.pathAt >= cfg.Repath and (goal == nil or flat(goal, target) > cfg.PathAgain) then
		h.pathAt, h.pathing = clock, true
		task.spawn(function()
			local ok, points = pcall(route, body, here, target)
			h.pathing = false
			if h.body ~= body then
				return
			end
			table.clear(h.path)
			if ok and points then
				for index, point in points do
					h.path[index] = point
				end
				h.pathIndex, h.pathGoal = 2, target
			else
				h.pathGoal = nil
				h.pathFailedAt = clock
			end
		end)
	end
	goal = h.pathGoal
	if goal and flat(goal, target) <= cfg.PathDrift then -- (8.3: on along it while the new one is worked out)
		local path = h.path
		while h.pathIndex <= #path and flat(path[h.pathIndex], here) < 2 do
			h.pathIndex += 1
		end
		if h.pathIndex <= #path then
			return path[h.pathIndex]
		end
	end
	return target
end

-- Toward `goal` (inside the interior or in the street: `goalInside`): to the front door first when it is in the other
-- world, then by the way; far off (Far), he appears at the next point (8.3 `walk`: never, your call's walk and the
-- ride's). Stuck (Brain.unstuck): a new path after StuckRepath s, a nudge to the way's next point (NUDGE studs at most)
-- after StuckSnap s. True: there (within near).
local function go(h: Helper, body: Body, goal: Vector3, goalInside: boolean, near: number, speed: number, dt: number, clock: number, walk: boolean?): boolean
	speed *= Brain.trained(h.s.owner) -- 8.1 SANDBOX: Danny's training (the owner's upgrade, server/Upgrades.luau)
	local here = body.root.Position
	local inside = insideAt(h, here)
	local target = goal
	if inside ~= goalInside then
		local way = wayFor(h, here, inside, goal) -- (7.x farm move: the nearest way he may take)
		local door = if inside then way.exitIn else way.outside.Position
		if flat(here, door) <= cfg.DoorReach and clock - h.doorAt > Config.Moving.Doors.Rearm then -- (8.1 walk-in doors)
			transfer(h, not inside, clock, way)
			return false
		end
		target = door
	elseif flat(here, goal) <= near then
		mover.halt(body)
		h.stuckFor, h.lastPos, h.repathed = 0, nil, false
		return true
	end
	if flat(here, target) > cfg.Far and not walk then
		placeAt(h, target, nil)
		return false
	end
	local last = h.lastPos
	h.stuckFor = Brain.stuck(h.stuckFor, if last then flat(here, last) else speed * dt, dt, speed)
	h.lastPos = here
	local fix = Brain.unstuck(h.stuckFor)
	if fix == "walk" then
		h.repathed = false
	elseif fix == "repath" and not h.repathed then
		h.repathed = true
		h.pathAt, h.pathGoal = -math.huge, nil -- (a new path at once)
	end
	local way = wayTo(h, body, here, target, clock)
	if fix == "nudge" then
		local step = Vector3.new(way.X - here.X, 0, way.Z - here.Z)
		local spot = if step.Magnitude > NUDGE then here + step.Unit * NUDGE else Vector3.new(way.X, here.Y, way.Z)
		placeAt(h, spot, if step.Magnitude > 0.05 then step else nil)
		return false
	end
	mover.move(body, way, speed, dt)
	return false
end

-- ── Choosing (every Think s) ───────────────────────────────────────────────

local function think(h: Helper, body: Body, clock: number)
	h.thinkAt = clock + cfg.Think
	local s = h.s
	local move: Rules.Move = s.move
	local here = body.root.Position
	local fromInside = insideAt(h, here)
	-- the van's room for each piece, again only when its load changed
	local key = #move.packing.placed + Rules.fill(move.packing)
	if key ~= h.fitKey then
		h.fitKey = key
		table.clear(h.fits)
	end
	for spot, untilAt in h.gaveUp do
		local thing = move.things[spot]
		if not thing or thing.state ~= "carried" or clock >= untilAt then
			h.gaveUp[spot] = nil
		end
	end
	-- 8.3 his list: the pieces that are no longer his to carry go (home or in the van already, somebody holds them)
	local changed = false
	for index = #h.queue, 1, -1 do
		local spot = h.queue[index]
		local thing = move.things[spot]
		local item = s.items[spot]
		if not thing or not item or not item.model.Parent or not Brain.keepQueued(thing.state, thing.carrier ~= nil or thing.helper ~= nil) then
			table.remove(h.queue, index)
			changed = true
		end
	end
	if changed then
		refreshMarks(h)
	end
	-- hired: a crew player's two-person piece dragged alone (he comes to its far end)
	table.clear(h.lifts)
	if h.hirer then
		for _, spot in move.order do
			local thing = move.things[spot]
			local item = s.items[spot]
			if not item or thing.class ~= "pair" or thing.state ~= "carried" then
				continue
			end
			local at = item.root.Position
			local carrier = playerOf(thing.carrier)
			local n = #h.lifts + 1
			local l = h.liftPool[n]
			if not l then
				l = { spot = 0, class = "", state = "", helped = false, crew = false, cost = 0, gaveUp = false }
				h.liftPool[n] = l
			end
			l.spot, l.class, l.state = spot, thing.class, thing.state
			l.helped = thing.helper ~= nil
			l.crew = carrier ~= nil and s.members[carrier] == true
			l.cost = (Brain.routeVia(fromInside, here.X, here.Z, insideAt(h, at), at.X, at.Z, h.wayDoors))
			l.gaveUp = h.gaveUp[spot] ~= nil
			h.lifts[n] = l
		end
	end
	h.lift = Brain.pickLift(h.lifts)
	-- 8.3 the next piece of his list (the first that still fits the van: the packing fix, lying on its side too)
	table.clear(h.next)
	for n, spot in h.queue do
		local fits = h.fits[spot]
		if fits == nil then
			fits = Rules.canLoad(move, spot)
			h.fits[spot] = fits
		end
		local q = h.nextPool[n]
		if not q then
			q = { spot = 0, class = "", fits = false }
			h.nextPool[n] = q
		end
		q.spot, q.class, q.fits = spot, move.things[spot].class, fits
		h.next[n] = q
	end
	h.pick, h.pair, h.full = Brain.nextQueued(h.next)
	if not h.full then
		h.toldFull = false
	end
end

-- The nearest living zombie within SafeRange: (studs, where) or nils.
local function nearestZombie(here: Vector3): (number?, Vector3?)
	local best: number? = nil
	local at: Vector3? = nil
	for _, z in Zombies.all() do
		local root = z.root
		if z.dead or not root or not root.Parent then
			continue
		end
		local d = (root.Position - here).Magnitude
		if d <= cfg.SafeRange and (best == nil or d < best) then
			best, at = d, root.Position
		end
	end
	return best, at
end

-- 7.x is the van's back shut while somebody of the crew comes with a piece and he is near enough to open it?
local function wantOpen(h: Helper, body: Body): boolean
	local s = h.s
	local truck = truckOf(s)
	if not cfg.OpenBack or not truck or Vehicles.backOpen(truck) or not Vehicles.backPrompt(truck) or not truckAtHouse(s, truck) or not truckStill(truck) then
		return false
	end
	local back = byTruck(truck, 0, 0)
	local here = body.root.Position
	if not back or insideAt(h, here) or flat(here, back) > cfg.OpenFar then
		return false
	end
	for player in s.members do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") and character:GetAttribute("MoveCarry") ~= nil and not insideAt(h, root.Position)
			and flat(root.Position, back) <= cfg.OpenNear then
			return true
		end
	end
	return false
end

-- ── What he does ───────────────────────────────────────────────────────────

-- At the van's open back, the van standing: loads what he carries (true: in).
local function loadHere(h: Helper, body: Body): boolean
	local truck = truckOf(h.s)
	local back = if truck then byTruck(truck, 0, 0) else nil
	if not truck or not back or insideAt(h, body.root.Position) or flat(body.root.Position, back) > cfg.LoadReach then
		return false
	end
	if not Vehicles.backOpen(truck) or not truckStill(truck) then
		return false
	end
	return (h.port.helperLoad(h.s, body.model))
end

-- 8.3 his own piece out of his arms (your call, your lift come first): into the van right here, else set down where
-- he is, back at the head of his list.
local function setDownOwn(h: Helper, body: Body)
	if loadHere(h, body) then
		return
	end
	local spot = Rules.holding(h.s.move, h.id)
	h.port.helperDrop(h.s, body.model, "put")
	requeue(h, spot)
end

-- 7.x his place at the far end of your piece, in its frame: Standoff past its far face, turned to you, on the floor
-- under it (within HoldStep of the floor under you). 8.3: that floor from a ray down from your root (your jump never
-- lifts him), his end's from a step over it to a step under it (MoveHelperBrain.endRise: a floor farther off is not
-- his); holding it (`trail`), his height follows it at HoldClimb studs a second at most (MoveHelperBrain.holdClimb: at
-- once on a new hold and through a door's fade).
local function endOffset(h: Helper, body: Body, thing: Rules.Thing, anchor: BasePart, carrierRoot: BasePart?, trail: Brain.Trail?, dt: number?): CFrame
	local frame = anchor.CFrame
	local ahead = Brain.farEnd(thing.size.Z)
	local far = frame * Vector3.new(0, 0, -ahead)
	local stand = body.humanoid.HipHeight + body.root.Size.Y / 2
	local step = cfg.HoldStep
	local base: number
	if carrierRoot then
		local at = carrierRoot.Position
		base = floorDown(h, at, at.Y, 40) or (at.Y - stand)
	else
		base = frame.Position.Y - thing.size.Y / 2 - Config.Cargo.CarryLow - stand
	end
	local found = floorDown(h, far, base + step, 2 * step + 1)
	local carrierRise = base + stand - frame.Position.Y
	local rise = Brain.endRise(if found then found + stand - frame.Position.Y else 0 / 0, carrierRise)
	if trail then
		local crossed = insideAt(h, body.root.Position) ~= insideAt(h, far) -- (a door's fade: there at once)
		rise = Brain.holdClimb(trail, frame.Position.Y + rise, dt or 0, crossed) - frame.Position.Y
	end
	return CFrame.new(0, rise, -ahead) * CFrame.Angles(0, math.pi, 0)
end

-- 7.x kept at `offset` in the piece's frame (the mover's constraints; 8.1 at `limit` studs / s at most, put there only
-- on `snap`; a test's mover without them: his root stepped there, limit × dt at most).
local function keepAt(body: Body, anchor: BasePart, offset: CFrame, dt: number, limit: number, snap: boolean)
	local keep = mover.keep
	if keep then
		keep(body, anchor, offset, dt, limit, snap)
		return
	end
	local goal = anchor.CFrame * offset
	local here = body.root.Position
	local way = goal.Position - here
	local step = limit * dt
	if snap or way.Magnitude <= step then
		body.root.CFrame = goal
	else
		body.root.CFrame = CFrame.new(here + way.Unit * step) * goal.Rotation
	end
end

-- 8.1 his legs holding the far end: his root's real velocity since the last step, in his frame (8.3 MoveHelperBrain.
-- holdLegs: his whole speed along the ground, backwards when the way is behind him, sideways as they went; Npcs.stride:
-- the walk played in reverse backwards); none across a door's fade. (Near players the clients' gait poses his legs from
-- the same velocity: Npcs.carried's Physics state.)
local function strideOf(h: Helper, body: Body, dt: number, snap: boolean)
	local here = body.root.Position
	local last = h.holdAt
	h.holdAt = here
	if snap or not last or dt <= 0 then
		Npcs.stride(body.model, 0)
		return
	end
	local look = body.root.CFrame.LookVector
	local vx, vz = (here.X - last.X) / dt, (here.Z - last.Z) / dt
	Npcs.stride(body.model, Brain.holdLegs(h.trail, vx * look.X + vz * look.Z, vz * look.X - vx * look.Z, dt))
end

-- 7.x the far end of your piece: he moves with it, glued there; the words.
local function actHold(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or not item.root.Parent then
		h.port.helperDrop(s, body.model, "put")
		ungrip(h, body)
		return
	end
	local carrierRoot = playerRoot(thing.carrier)
	if h.gripped ~= item.root then
		h.trail, h.holdAt = Brain.newTrail(), nil -- (8.1 a new hold)
	end
	local offset = endOffset(h, body, thing, item.root, carrierRoot, h.trail, dt) -- (8.3 his height: holdClimb's)
	h.holdOffset, h.gripped = offset, item.root
	-- 8.1 never put there while holding (a door's fade only: the piece in the other world); eased back when stuck behind
	local here = body.root.Position
	local crossed = insideAt(h, here) ~= insideAt(h, (item.root.CFrame * offset).Position)
	local carrier = playerOf(thing.carrier)
	-- 8.3 keeping up (the owner: "when I run, he just goes behind me"): his top speed follows your real speed (your
	-- root's, MoveHelperBrain.holdPace), and he is aimed your velocity × leadTime ahead (your screen shows his body late)
	local from = if carrierRoot then carrierRoot.Position else nil
	local pace = Brain.holdPace(h.trail, if from then from.X else 0 / 0, if from then from.Z else 0 / 0, dt, crossed or from == nil)
	local speed = Brain.holdSpeed(PairHold.walkOf(carrier, Rules.carrySpeed(walkSpeed(), "pair", thing.weight)), pace)
	local leadX, leadZ = Brain.holdLead(h.trail, Brain.leadTime(PairHold.pingOf(carrier)))
	local aim = if leadX == 0 and leadZ == 0 then offset
		else CFrame.new(item.root.CFrame:PointToObjectSpace(item.root.Position + Vector3.new(leadX, 0, leadZ))) * offset
	local goal = (item.root.CFrame * aim).Position
	local limit, snap = Brain.holdTrack(h.trail, (goal - here).Magnitude, crossed, speed, dt)
	h.holdLimit = limit
	keepAt(body, item.root, aim, dt, limit, snap)
	strideOf(h, body, dt, snap)
	steady(h, if carrierRoot then carrierRoot.Parent :: Model? else nil)
	local at = item.root.Position
	if insideAt(h, at) and nearDoorway(h, at, cfg.DoorWarn) then
		say(h, "door", clock)
	end
	local truck = truckOf(s)
	local back = if truck then byTruck(truck, 0, 0) else nil
	if not truck or not back or insideAt(h, at) or flat(at, back) > cfg.VanSay then
		return
	end
	-- by the van together: the back shut, he opens it (your hands are full, his has an elbow free), else "That's going in
	-- the van."
	if cfg.OpenBack and not Vehicles.backOpen(truck) and Vehicles.backPrompt(truck) and truckStill(truck) then
		Vehicles.setBack(truck, true)
		say(h, "open", clock)
	elseif h.vanSaid ~= spot and say(h, "van", clock) then
		h.vanSaid = spot
	end
end

-- 7.x takes your piece's far end: "Got the other end!", "On three... lift!" a moment later.
local function takeEnd(h: Helper, body: Body, spot: number, clock: number)
	mover.halt(body)
	if h.port.helperTake(h.s, spot, body.model) then
		say(h, "lift", clock, true)
		h.lineKey, h.lineAt, h.vanSaid = "three", clock + cfg.ThreeAfter, nil
	else
		h.gaveUp[spot] = clock + cfg.HelpRetry
	end
	h.thinkAt = 0
end

-- 7.x the fade-over: he is at `goal` at once (on the floor there, turned its way) and fades in.
local function blink(h: Helper, body: Body, goal: CFrame)
	placeAt(h, goal.Position, goal.LookVector)
	local appear = mover.appear
	if appear then
		appear(body)
	end
end

-- To your two-person piece dragged alone: his own piece first (into the van right here, else set down), then a sprint
-- to its far end, and he takes it. 8.3 (WaitForHelper): he walks there, a fade-over only as the last resort (CallBlink
-- s no closer); without it: farther than BlinkFar on foot, his path failing or not there HelpBlink s after he set off.
local function actHelp(h: Helper, body: Body, spot: number, holding: string?, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or thing.state ~= "carried" or thing.class ~= "pair" or thing.helper ~= nil then
		h.thinkAt = 0
		return
	end
	if holding == "hand" then
		setDownOwn(h, body)
		h.thinkAt = 0
		return
	end
	if h.action ~= "help" or h.spot ~= spot then
		h.helpSince, h.stuckFor, h.repathed = clock, 0, false
		h.helpWalk = Brain.newApproach()
		say(h, "help", clock)
	end
	local goal = item.root.CFrame * endOffset(h, body, thing, item.root, playerRoot(thing.carrier))
	local at = goal.Position
	local here = body.root.Position
	local inside = insideAt(h, at)
	local hereInside = insideAt(h, here)
	if hereInside == inside and flat(here, at) <= cfg.HelpReach then
		takeEnd(h, body, spot, clock)
		return
	end
	local cost = (Brain.routeVia(hereInside, here.X, here.Z, inside, at.X, at.Z, h.wayDoors))
	local walkTo = h.helpWalk
	local lastResort = if cfg.WaitForHelper then walkTo ~= nil and Brain.approach(walkTo, cost, dt)
		else cost > cfg.BlinkFar or clock - h.helpSince >= cfg.HelpBlink or h.pathFailedAt >= h.helpSince
	if lastResort then
		blink(h, body, goal)
		takeEnd(h, body, spot, clock)
		return
	end
	go(h, body, at, inside, 0.5, Brain.speed(walkSpeed(), "help", nil, 0), dt, clock, cfg.WaitForHelper)
end

-- ── 8.3 your call: he walks to its far end, "On three... lift!", your lift ─

-- His place at the far end of your piece as you will hold it (`frame`: Moving's helperLiftFrame), like endOffset's.
local function farEndFrom(h: Helper, body: Body, thing: Rules.Thing, frame: CFrame, carrierRoot: BasePart): CFrame
	local ahead = Brain.farEnd(thing.size.Z)
	local far = frame * Vector3.new(0, 0, -ahead)
	local stand = body.humanoid.HipHeight + body.root.Size.Y / 2
	local step = cfg.HoldStep
	local at = carrierRoot.Position
	local base = floorDown(h, at, at.Y, 40) or (at.Y - stand) -- (the floor under you, as endOffset finds it)
	local found = floorDown(h, far, base + step, 2 * step + 1)
	local rise = Brain.endRise(if found then found + stand - frame.Position.Y else 0 / 0, base + stand - frame.Position.Y)
	return frame * CFrame.new(0, rise, -ahead) * CFrame.Angles(0, math.pi, 0)
end

-- In place: turned to you, your grip steadied, "On three... lift!" and your lift (Moving opens its check; without the
-- grip it is up at once, him at its far end: joinLift). Not there to lift it any more: the call is off.
local function callReady(h: Helper, body: Body, call: Call, clock: number)
	call.ready, call.readyAt = true, clock
	mover.halt(body)
	local root = rootOf(call.player)
	local here = body.root.Position
	if root then
		local look = Vector3.new(root.Position.X - here.X, 0, root.Position.Z - here.Z)
		if look.Magnitude > 0.05 then
			body.model:PivotTo(CFrame.lookAt(here, here + look))
		end
		steady(h, root.Parent :: Model?)
	end
	say(h, "three", clock, true)
	mark(h, call.spot, nil) -- (Lift as ever: a miss's next try)
	if call.player.Parent then
		call.player:SetAttribute("MoveHelperReady", true) -- (your status line: he is there, lift)
	end
	local called = h.port.helperCalled
	local ok = called ~= nil and called(h.s, call.spot, call.player)
	if not ok and h.call == call then
		endCall(h, "away", clock)
	end
end

-- To your call: his own piece first (into the van right here, else set down), then he walks to its far end as you will
-- hold it; in place, callReady. The last resort: no closer for CallBlink s, he fades over.
local function actCome(h: Helper, body: Body, spot: number, holding: string?, dt: number, clock: number)
	local s = h.s
	local call = h.call
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not call or not thing or not item then
		h.thinkAt = 0
		return
	end
	if holding == "hand" then
		setDownOwn(h, body)
		h.thinkAt = 0
		return
	end
	if call.ready then
		mover.halt(body) -- (he waits for your lift at its far end)
		return
	end
	local frameOf = h.port.helperLiftFrame
	local frame = if frameOf then frameOf(s, spot, call.player) else nil
	local callerRoot = rootOf(call.player)
	if not frame or not callerRoot then
		return -- (the call's own look ends it)
	end
	if h.action ~= "come" or h.spot ~= spot then
		h.stuckFor, h.repathed = 0, false
	end
	local goal = farEndFrom(h, body, thing, frame, callerRoot)
	local at = goal.Position
	local here = body.root.Position
	local inside, hereInside = insideAt(h, at), insideAt(h, here)
	if hereInside == inside and Brain.inPlace(flat(here, at), h.stuckFor) then
		callReady(h, body, call, clock)
		return
	end
	local cost = (Brain.routeVia(hereInside, here.X, here.Z, inside, at.X, at.Z, h.wayDoors))
	if Brain.approach(call.approach, cost, dt) then
		blink(h, body, goal) -- (the last resort: no way there)
		return
	end
	go(h, body, at, inside, 0.5, Brain.speed(walkSpeed(), "come", nil, 0), dt, clock, true)
end

-- Is the call still on (its caller there, at their end, hands free; the piece home or on the ground)?
local function keepCall(h: Helper, clock: number)
	local call = h.call
	if not call then
		return
	end
	local s = h.s
	local player = call.player
	local thing = (s.move :: Rules.Move).things[call.spot]
	local item = s.items[call.spot]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not player.Parent or not s.members[player] or not thing or not item or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart
		or not root or not root:IsA("BasePart") or (thing.state ~= "home" and thing.state ~= "ground") or Rules.holding(s.move, player.UserId) then
		endCall(h, "gone", clock) -- (left, down, in a seat, it was taken or the hands took another)
		return
	end
	local reach = Config.Moving.Reach.Item + math.max(thing.size.X, thing.size.Z) / 2 + 2 -- (Moving's onPick's)
	local apart = if insideAt(h, root.Position) == insideAt(h, item.root.Position) then flat(root.Position, item.root.Position) else math.huge
	local verdict = Brain.callKept(apart, reach, call.ready, clock - call.readyAt)
	if verdict ~= "on" then
		endCall(h, verdict, clock)
	end
end

-- ── 8.3 his list: the pieces he goes for ───────────────────────────────────

-- Beside a piece, on his side (the way's end: a path can't end inside a piece that stands in the way), out of the
-- doorways.
local function besidePiece(h: Helper, here: Vector3, at: Vector3, inside: boolean, half: number): Vector3
	local from = here
	if insideAt(h, here) ~= inside then
		local way = wayFor(h, here, not inside, at) -- (7.x farm move: the way he will come by)
		from = if inside then way.entryIn.Position else way.outside.Position
	end
	local side = Vector3.new(from.X - at.X, 0, from.Z - at.Z)
	return if side.Magnitude > 0.1 then at + side.Unit * (half + 1.5) else at
end

-- A two-person piece of his list: to it, "give me a hand!" there (the crew's toast once, the marker "needs you", its
-- prompt "Lift with Danny"), then he waits for your lift (your call: he answers it at once).
local function actNeeds(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item then
		h.thinkAt = 0
		return
	end
	if h.needs ~= spot then
		endNeeds(h)
		h.needs, h.needsAt = spot, 0
	end
	if h.needsAt > 0 then
		mover.halt(body) -- (he waits there for you)
		return
	end
	local at = item.root.Position
	local inside = insideAt(h, at)
	local here = body.root.Position
	local half = math.max(thing.size.X, thing.size.Z) / 2
	local beside = clearOf(h, besidePiece(h, here, at, inside, half), inside)
	if insideAt(h, here) == inside and (flat(here, at) <= half + cfg.PickReach or flat(here, beside) <= 0.6) then
		mover.halt(body)
		h.needsAt = clock
		say(h, "ask", clock, true)
		if h.needsTold ~= spot then
			h.needsTold = spot
			tell(h, `🙋 {cfg.Name} is at the {thing.name}: lift it with him.`)
		end
		mark(h, spot, "ask")
		refreshMarks(h)
		return
	end
	go(h, body, beside, inside, 0.5, Brain.speed(walkSpeed(), "fetch", nil, 0), dt, clock)
end

-- To the next piece of his list; there, he picks it up (off his list: in his arms now).
local function actFetch(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or (thing.class ~= "hand" and thing.class ~= "both") or (thing.state ~= "home" and thing.state ~= "ground") then
		h.pick, h.thinkAt = nil, 0
		return
	end
	local at = item.root.Position
	local inside = insideAt(h, at)
	local here = body.root.Position
	local half = math.max(thing.size.X, thing.size.Z) / 2
	if insideAt(h, here) == inside and flat(here, at) <= half + cfg.PickReach then
		mover.halt(body)
		h.port.helperTake(s, spot, body.model) -- (refused: it can't be his after all; off his list either way)
		unqueue(h, spot)
		refreshMarks(h)
		h.pick = nil
		h.waited, h.dropping, h.thinkAt = 0, false, 0
		return
	end
	go(h, body, besidePiece(h, here, at, inside, half), inside, 0.5, Brain.speed(walkSpeed(), "fetch", nil, 0), dt, clock)
end

-- With a piece in his arms: to the van's back and in (shut: he opens it when he may, else he asks and waits); no room
-- or the back shut too long: beside the van. No van by the house: set down outside the house's door.
local function actDeliver(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local speed = Brain.speed(walkSpeed(), "deliver", Rules.mode(thing), thing.weight)
	local truck = truckOf(s)
	local here = body.root.Position
	if not truck or not truckAtHouse(s, truck) then
		local out: CFrame = s.site.outside
		local right = Vector3.new(-out.LookVector.Z, 0, out.LookVector.X)
		if go(h, body, clearOf(h, out.Position + right * 4, false), false, 1.5, speed, dt, clock) then
			h.port.helperDrop(s, body.model, "put")
			h.thinkAt = 0
		end
		return
	end
	if not truckStill(truck) then
		mover.halt(body) -- (the van is moving: he waits with it)
		return
	end
	if h.dropping then
		local beside = byTruck(truck, 4 + (spot % 3) * 2.2, 2 + (spot // 3 % 2) * 2.5)
		if not beside or go(h, body, beside, false, 1, speed, dt, clock) then
			h.port.helperDrop(s, body.model, "put")
			h.dropping, h.waited, h.thinkAt = false, 0, 0
		end
		return
	end
	local back = byTruck(truck, 0, 2)
	if not back then
		h.dropping = true
		return
	end
	if insideAt(h, here) or flat(here, back) > cfg.LoadReach then
		go(h, body, back, false, 1, speed, dt, clock)
		return
	end
	mover.halt(body)
	local verdict = Brain.atTruck(Vehicles.backOpen(truck), true, h.waited, cfg.OpenBack and Vehicles.backPrompt(truck) ~= nil)
	if verdict == "load" then
		local ok = h.port.helperLoad(s, body.model)
		h.waited, h.thinkAt = 0, 0
		if ok then
			say(h, if #h.queue == 0 then "empty" else "loaded", clock) -- (8.3 the last of his list: "All done.")
		else
			h.dropping, h.fits[spot] = true, false -- (no room for it after all)
			h.toldFull = true
			say(h, "full", clock, true)
		end
	elseif verdict == "open" then
		Vehicles.setBack(truck, true)
		say(h, "open", clock)
	elseif verdict == "wait" then
		h.waited += dt
		say(h, "shut", clock)
	else
		h.dropping = true
	end
end

-- 7.x the van's back for whoever comes with a piece: to it, and open.
local function actOpen(h: Helper, body: Body, dt: number, clock: number)
	local truck = truckOf(h.s)
	local spot = if truck then byTruck(truck, -1.5, 1.5) else nil
	if not truck or not spot then
		return
	end
	if flat(body.root.Position, spot) > cfg.LoadReach then
		go(h, body, spot, false, 1, Brain.speed(walkSpeed(), "open", nil, 0), dt, clock)
		return
	end
	mover.halt(body)
	Vehicles.setBack(truck, true)
	say(h, "open", clock)
	h.thinkAt = 0
end

-- At the van (on its left, out of the way). It moves, or it stands far off and not by the house (driven somewhere
-- else, a stop on the way): he stands where he is (he appears at it once it is parked by the house). No van: outside
-- the house's door (beside it, out of the doorway). (8.3: for hire, and hired with nothing to carry.)
local function actWait(h: Helper, body: Body, dt: number, clock: number)
	local truck = truckOf(h.s)
	local speed = Brain.speed(walkSpeed(), "wait", nil, 0)
	if truck and not truckStill(truck) then
		mover.halt(body)
		return
	end
	local spot = if truck then byTruck(truck, -4, 3) else nil
	if not spot then
		local out: CFrame = h.s.site.outside
		spot = out.Position
	elseif truck and (h.hirer == nil or not truckAtHouse(h.s, truck)) and flat(body.root.Position, spot) > cfg.Far then
		-- (8.4, the owner: "Danny always has to be hired, he isn't free": not hired, he stays where the van left him, at
		-- the warehouse, and never turns up at the house; hired, he rides along or comes to the van at the house)
		mover.halt(body)
		return
	end
	go(h, body, clearOf(h, spot :: Vector3, false), false, 1.5, speed, dt, clock)
end

-- 8.3 you sit at the van's wheel: to its passenger door and in (a fade into the seat only as the last resort); the
-- seat taken by a crew mate (8.3 review: or reserved by their boarding; or he gave it up to them SeatYield s ago at
-- most): after the van on foot (by its back; parked far off, he appears there as ever).
local function actRide(h: Helper, body: Body, dt: number, clock: number)
	local truck = truckOf(h.s)
	if not truck then
		return
	end
	if h.action ~= "ride" then
		h.rideWalk, h.stuckFor, h.repathed = Brain.newApproach(), 0, false
		say(h, "ride", clock)
	end
	local speed = Brain.speed(walkSpeed(), "ride", nil, 0)
	local seat = if clock >= h.yieldAt then freeSeat(truck) else nil
	if not seat then
		local spot = byTruck(truck, -4, 3) or truck.chassis.Position
		go(h, body, clearOf(h, spot, false), false, 1.5, speed, dt, clock, not truckStill(truck))
		return
	end
	local at = seatDoor(truck, seat)
	local here = body.root.Position
	local hereInside = insideAt(h, here)
	if not hereInside and flat(here, at) <= cfg.RideReach then
		sitIn(h, body, seat, truck)
		return
	end
	local walkTo = h.rideWalk or Brain.newApproach()
	h.rideWalk = walkTo
	local cost = (Brain.routeVia(hereInside, here.X, here.Z, false, at.X, at.Z, h.wayDoors))
	if Brain.approach(walkTo, cost, dt) then
		sitIn(h, body, seat, truck) -- (the last resort: his path fails, the van drove off: he fades into the seat)
		local appear = mover.appear
		if appear then
			appear(body)
		end
		return
	end
	go(h, body, at, false, 0.5, speed, dt, clock, true)
end

-- 8.3 in the van's seat: out when nobody drives it and it stands (on his side, on with his list), at once when it is
-- wrecked or gone (8.3 review: at its seat's door all the same, unseat's h.seatCar); else the van carries him.
local function actSeat(h: Helper, body: Body, clock: number)
	local s = h.s
	local truck = truckOf(s)
	local seat = h.seat
	local carOk = truck ~= nil and seat ~= nil and seat.Parent ~= nil and seat:IsDescendantOf(truck.model) and body.humanoid.SeatPart == seat
	if Brain.getOut(driven(s, truck), truck == nil or truckStill(truck), carOk) then
		unseat(h, body, if carOk then truck else nil)
		if h.hirer and #h.queue > 0 then
			say(h, "out", clock)
		end
	end
end

local function actFlee(h: Helper, body: Body, from: Vector3, dt: number, clock: number)
	local here = body.root.Position
	local target = h.fleeAt
	if not target or clock - h.fleeSet > 1 or flat(here, target) < 2 then
		local x, z = Brain.fleeTo(here.X, here.Z, from.X, from.Z)
		target = Vector3.new(x, here.Y, z)
		h.fleeAt, h.fleeSet = target, clock
	end
	say(h, "flee", clock)
	mover.move(body, target :: Vector3, Brain.speed(walkSpeed(), "flee", nil, 0), dt)
end

-- ── One step ───────────────────────────────────────────────────────────────

local function stepHelper(h: Helper, dt: number, clock: number)
	local s = h.s
	local body = h.body
	if h.dead then
		if body and clock - h.downAt >= FALL then
			removeBody(h)
		end
		if clock - h.downAt >= cfg.Respawn then
			if h.body then
				removeBody(h)
			end
			if spawnBody(h, homeSpot(h)) then
				say(h, "back", clock, true)
				h.thinkAt, h.waited, h.dropping, h.fleeing = 0, 0, false, false
			else
				h.downAt = clock - cfg.Respawn + 2 -- (no body yet: tried again in a moment)
			end
		end
		endCall(h, "down", clock) -- 8.3 (no call waits for him while he is down)
		setDoing(h, "down", nil)
		return
	end
	if not body or not body.model.Parent or not body.humanoid.Parent then
		-- his body went (removed by something else): like a fall (7.0 review: what he holds falls first, never left
		-- "carried" by nobody)
		if body then
			h.port.helperDrop(s, body.model, "died")
		end
		removeBody(h)
		h.dead, h.downAt = true, clock - FALL
		return
	end
	if body.humanoid.Health <= 0 then
		fall(h, body, clock)
		return
	end
	local move: Rules.Move = s.move
	local spot, role = Rules.holding(move, h.id)
	local holding = if role == "helper" then "pair" elseif spot then "hand" else nil
	if holding ~= "pair" and h.gripped then
		unhold(h, body) -- (7.x your piece went down, into the van, or he let go: on his feet again)
	end
	keepCall(h, clock) -- 8.3 (a call still on?)
	if clock >= h.thinkAt then
		think(h, body, clock)
	end
	local seated = h.seat ~= nil
	local threat, threatAt = nil, nil
	if holding ~= "pair" and not seated then
		threat, threatAt = nearestZombie(body.root.Position)
	end
	local hired = h.hirer ~= nil
	local truck = truckOf(s)
	local input = h.input
	input.hired, input.dead, input.holding, input.seated = hired, false, holding, seated
	input.ride = hired and driven(s, truck) -- 8.3 (you sit at its wheel: he gets in)
	input.threat, input.fleeing = threat, h.fleeing
	input.lift = h.lift
	input.queued, input.pair = h.pick, h.pair
	input.open = hired and holding == nil and not seated and wantOpen(h, body)
	input.atHouse = truckAtHouse(s, truck)
	local call = h.call
	input.call = if call then call.spot else nil -- 8.3
	local action, target = Brain.decide(input)
	local needs = h.needs
	if needs and not ((action == "needs" or action == "come") and target == needs) then
		endNeeds(h) -- 8.3 (lifted, taken back, or something came first)
	end
	h.fleeing = action == "flee"
	if action ~= "flee" then
		h.fleeAt = nil
	end
	if action == "hold" and spot then
		actHold(h, body, spot, dt, clock)
	elseif action == "seat" then
		actSeat(h, body, clock) -- 8.3
	elseif action == "flee" and threatAt then
		actFlee(h, body, threatAt, dt, clock)
	elseif action == "come" and target then
		actCome(h, body, target, holding, dt, clock) -- 8.3
	elseif action == "help" and target then
		actHelp(h, body, target, holding, dt, clock)
	elseif action == "deliver" and spot then
		actDeliver(h, body, spot, dt, clock)
	elseif action == "ride" then
		actRide(h, body, dt, clock) -- 8.3
	elseif action == "open" then
		actOpen(h, body, dt, clock)
	elseif action == "needs" and target then
		actNeeds(h, body, target, dt, clock) -- 8.3
	elseif action == "fetch" and target then
		actFetch(h, body, target, dt, clock)
	else
		if h.full and hired and not h.toldFull then
			say(h, "full", clock, true) -- (once while it stays full)
			h.toldFull = true
		end
		actWait(h, body, dt, clock)
	end
	-- (what he holds now: his arms; a line due: "On three... lift!")
	local nowSpot, nowRole = Rules.holding(move, h.id)
	poseHands(h, body, nowSpot, nowRole)
	local line = h.lineKey
	if line and clock >= h.lineAt then
		h.lineKey = nil
		if nowRole == "helper" then
			say(h, line, clock, true)
		end
	end
	-- (8.3 your call: lifted together in this step already, or him in place)
	local now = h.call
	local doing = if action == "come" and nowRole == "helper" then "hold" elseif action == "come" and now and now.ready then "ready" else action
	h.action, h.spot = if doing == "hold" then "hold" else action, target or spot
	setDoing(h, doing, target or spot)
end

-- ── Coming and going ───────────────────────────────────────────────────────

local function dismiss(h: Helper, why: string?)
	local s = h.s
	local body = h.body
	if body and h.seat then
		unseat(h, body, nil) -- (8.3 out of the van's seat first)
	end
	if body and not h.dead and not s.ended then
		h.port.helperDrop(s, body.model, "put")
	end
	if why == "crew" then
		tell(h, if Config.Sandbox.On then `🧑‍🔧 {cfg.Name} heads home: your crew has it now.` else `🧑‍🔧 {cfg.Name} heads back to the depot: your crew has it now.`)
	end
	local clock = os.clock()
	endCall(h, if s.ended then nil else "gone", clock) -- 8.3
	table.clear(h.queue)
	endNeeds(h)
	refreshMarks(h)
	removeBody(h)
	helpers[s] = nil
	byId[h.id] = nil
	for player in h.told do
		if player.Parent then
			for _, name in ATTRIBUTES do
				player:SetAttribute(name, nil)
			end
		end
	end
	table.clear(h.told)
end

function MoveHelper.step(dt: number)
	local clock = os.clock()
	for s, h in helpers do
		if s.ended then
			dismiss(h, nil)
			continue
		end
		local ok, err = pcall(stepHelper :: any, h, dt, clock) -- (no closure a step)
		if not ok then
			warn(`[MoveHelper] {err}`)
		end
	end
end

-- 8.3 your call is off (G, the status line's STOP): true when there was one.
local function stopCall(player: Player): boolean
	local clock = os.clock()
	for _, h in helpers do
		local call = h.call
		if call and call.player == player then
			endCall(h, "cancel", clock)
			say(h, "callOff", clock)
			return true
		end
	end
	return false
end

-- 8.3 the helper of the move `player` is crew of (nil: none).
local function helperOf(player: Player): Helper?
	for s, h in helpers do
		if not s.ended and s.members[player] == true then
			return h
		end
	end
	return nil
end

-- 8.3 HIRE: checked (MoveHelperBrain.hireCheck: the move's crew, not hired yet, the money), the money taken
-- (PlayerData.spend: "HelperHire"), he works for the move.
local function hire(player: Player)
	local h = helperOf(player)
	if not h then
		return -- (no Danny on a move of yours: nothing to hire)
	end
	local profile = PlayerData.get(player)
	local money = if profile then (profile :: any).money else nil
	local ok, why = Brain.hireCheck(true, h.hirer ~= nil, money, h.price)
	if not ok or not PlayerData.spend(player, h.price, "HelperHire", h.s.contract.id) then
		notice:FireClient(player, if why == "hired" then `{cfg.Name} works for this move already.`
			else `Not enough money: {cfg.Name} costs {Brain.money(h.price)} for this move.`)
		return
	end
	local clock = os.clock()
	h.hirer = player
	h.thinkAt = 0
	say(h, "hired", clock, true)
	tell(h, `🧑‍🔧 {player.DisplayName} hired {cfg.Name} for this move ({Brain.money(h.price)}): pick a piece and he carries it to the van; the rest is yours.`)
	setDoing(h, h.action, h.spot)
	tellCrew(h)
end

-- 8.3 the hire is over before the move (the one who hired him left it): his list gone, what he holds set down.
local function endHire(h: Helper, who: Player)
	h.hirer = nil
	table.clear(h.queue)
	endNeeds(h)
	refreshMarks(h)
	local body = h.body
	if body and not h.dead then
		h.port.helperDrop(h.s, body.model, "put")
	end
	endCall(h, "gone", os.clock())
	h.thinkAt = 0
	tell(h, `🧑‍🔧 {who.DisplayName} left the move: {cfg.Name} waits by the van for hire again.`)
end

-- (8.3 review: the notices' words fit every device: "pick" a piece or him, never a computer's "click")
local ASSIGN_WHY: { [string]: string } = {
	hire = "Hire %s first: pick him by the van.",
	far = "Get closer to the %s to give it to Danny.",
	his = "Danny has the %s already.",
	van = "The %s is in the van already.",
	held = "Somebody holds the %s.",
	full = "Danny's list is full: pick a piece of it to take it back first.",
}

-- 8.3 a click on a piece (its model): onto his list, or off it again; checked (MoveHelperBrain.assignCheck).
local function assign(player: Player, model: any)
	local h = helperOf(player)
	if not h or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local s = h.s
	local raw = model:GetAttribute("MoveSpot")
	local spot: number = if type(raw) == "number" then raw else 0
	local item = s.items[spot]
	local thing = if item then (s.move :: Rules.Move).things[spot] else nil
	if not item or not thing or item.model ~= model then
		return -- (not a piece of this move: another's, or nothing)
	end
	local root = rootOf(player)
	local near = root ~= nil and insideAt(h, root.Position) == insideAt(h, item.root.Position) and flat(root.Position, item.root.Position) <= cfg.ClickReach + 10
	local verdict = Brain.assignCheck({ crew = true, hired = h.hirer ~= nil, mine = true, state = thing.state, held = thing.carrier ~= nil or thing.helper ~= nil,
		his = Rules.holding(s.move, h.id) == spot, queued = table.find(h.queue, spot) ~= nil, count = #h.queue, near = near })
	local clock = os.clock()
	if verdict == "add" then
		table.insert(h.queue, spot)
		refreshMarks(h)
		h.thinkAt = 0
		notice:FireClient(player, `🧑‍🔧 {cfg.Name} will take the {thing.name}.`)
		say(h, "queued", clock)
	elseif verdict == "remove" then
		unqueue(h, spot)
		if h.needs == spot then
			endNeeds(h)
		end
		refreshMarks(h)
		h.thinkAt = 0
		notice:FireClient(player, `{cfg.Name} leaves the {thing.name} to you.`)
	else
		local text = ASSIGN_WHY[verdict]
		if text then
			notice:FireClient(player, string.format(text, if verdict == "hire" then cfg.Name else thing.name))
		end
	end
	tellCrew(h)
end

-- 8.3 CLEAR QUEUE: his list empty (he waits by the van; a piece in his arms still goes into the van).
local function clearQueue(player: Player)
	local h = helperOf(player)
	if not h or not h.hirer then
		return
	end
	if #h.queue == 0 then
		notice:FireClient(player, `{cfg.Name}'s list is empty already.`)
		return
	end
	table.clear(h.queue)
	endNeeds(h)
	refreshMarks(h)
	h.thinkAt = 0
	say(h, "cleared", os.clock(), true)
	tell(h, `{player.DisplayName} cleared {cfg.Name}'s list: he waits by the van.`)
	tellCrew(h)
end

-- The crew's requests on the Moving remote: ("helper", "hire" | "clear" | "stop") at Config.Robust.Limits.MoveHelper,
-- ("helper", "assign", a piece's model) at MoveHelperAssign; anything else is dropped.
local function onRequest(player: Player, action: any, kind: any, arg: any)
	if action ~= "helper" then
		return
	end
	if kind == "assign" then
		if Net.limit(player, "MoveHelperAssign", Config.Robust.Limits.MoveHelperAssign) then
			assign(player, arg)
		end
		return
	end
	if not Net.limit(player, "MoveHelper", Config.Robust.Limits.MoveHelper) then
		return
	end
	if kind == "stop" then
		stopCall(player)
	elseif kind == "hire" then
		hire(player)
	elseif kind == "clear" then
		clearQueue(player)
	end
end

-- 8.3 Moving's Lift on a two-person piece (Config.MoveHelper.WaitForHelper): see the header.
function MoveHelper.call(s: any, player: Player, spot: number): string?
	local h = helpers[s]
	if not h or s.ended or not cfg.WaitForHelper or not h.hirer then
		return nil
	end
	local clock = os.clock()
	local call = h.call
	if call and call.player == player then
		if call.spot == spot then
			if call.ready then
				return "ready"
			end
			endCall(h, "cancel", clock) -- (Lift again while you wait: you stop)
			say(h, "callOff", clock)
			return "cancel"
		end
		endCall(h, nil, clock) -- (another piece: this one now)
	elseif call and call.spot == spot then
		-- 8.3 review: the piece a crew mate waits at with him (its Lift says "Stop waiting" to the whole crew): refused,
		-- never a lift alone from under their call
		local waited = (s.move :: Rules.Move).things[spot]
		notice:FireClient(player, `{call.player.DisplayName} is waiting for {cfg.Name} with the {if waited then waited.name else "piece"}.`)
		return "busy"
	elseif call then
		return nil -- (he is on a crew mate's call: today's rules for yours)
	end
	local thing = (s.move :: Rules.Move).things[spot]
	local body = h.body
	if h.dead or not body or h.seat or not s.members[player] or not thing or thing.class ~= "pair" or (thing.state ~= "home" and thing.state ~= "ground")
		or select(2, Rules.holding(s.move, h.id)) == "helper" then
		return nil -- (he can't come now: today's rules, you drag it alone)
	end
	h.call = { player = player, spot = spot, since = clock, ready = false, readyAt = 0, approach = Brain.newApproach() }
	h.thinkAt = 0
	shout(player.Character, "Danny, give me a hand!")
	notice:FireClient(player, `🙋 "Danny, give me a hand!" Wait at your end of the {thing.name}: he's coming. Lift again or press STOP to call it off.`) -- (8.3 review: no key named: every device)
	if player:GetAttribute("MoveHelperCall") ~= thing.name then
		player:SetAttribute("MoveHelperCall", thing.name)
	end
	mark(h, spot, "wait")
	say(h, "help", clock, true)
	setDoing(h, "come", spot)
	tellCrew(h)
	return "wait"
end

-- 8.3 G (Moving's PutDown) with empty hands: your call is off.
function MoveHelper.cancel(player: Player): boolean
	return stopCall(player)
end

-- 8.3 Moving's pick of a piece you called him to, him in place: he takes its far end now and his hold starts where he
-- stands (no pause, no snap: PairHold walks him the last studs at the pair's walk).
function MoveHelper.joinLift(s: any, spot: number, player: Player): boolean
	local h = helpers[s]
	local call = if h then h.call else nil
	if not h or not call or call.player ~= player or call.spot ~= spot or not call.ready then
		return false
	end
	h.call = nil
	player:SetAttribute("MoveHelperCall", nil)
	player:SetAttribute("MoveHelperReady", nil)
	local body = h.body
	if h.dead or not body or not h.port.helperTake(s, spot, body.model) then
		steady(h, nil)
		return false
	end
	local clock = os.clock()
	h.vanSaid, h.thinkAt, h.lineKey = nil, 0, nil
	actHold(h, body, spot, 0, clock)
	h.action, h.spot = "hold", spot
	setDoing(h, "hold", spot)
	tellCrew(h)
	return true
end

-- 8.3 Moving's pick: a piece `player` picked up leaves his list ("All yours, boss."; not a word when it is the one his
-- call lifts with him).
function MoveHelper.taken(s: any, spot: number, player: Player)
	local h = helpers[s]
	if not h or not unqueue(h, spot) then
		return
	end
	local call = h.call
	local together = call ~= nil and call.spot == spot
	if h.needs == spot then
		h.needs, h.needsAt = nil, 0
	end
	refreshMarks(h)
	h.thinkAt = 0
	if not together and player.Parent then
		local thing = (s.move :: Rules.Move).things[spot]
		notice:FireClient(player, `You took the {if thing then thing.name else "piece"}: off {cfg.Name}'s list.`)
		say(h, "mine", os.clock())
	end
	tellCrew(h)
end

-- 8.3 review: a crew player's Ride along at the door of the van's seat he sits in (Vehicles.yieldSeat; their client
-- shows them that prompt: client/CarVisuals.luau): he gets out for them ("All yours, boss."; SeatAside studs aside from
-- the door they get in by, as server/Buddy.luau's buddy does) and takes no seat for SeatYield s (their boarding
-- reserves it meanwhile). True when he did.
local function yieldTo(seat: Seat, player: Player?): boolean
	for s, h in helpers do
		local body = h.body
		if h.seat == seat and body and not h.dead and not s.ended and player and s.members[player] == true then
			local clock = os.clock()
			unseat(h, body, nil, cfg.SeatAside)
			h.yieldAt = clock + cfg.SeatYield
			say(h, "mine", clock)
			return true
		end
	end
	return false
end

-- Once: the zombies go after him too (Zombies.extraTargets, after server/Buddy.luau's), the crew's requests, his loop;
-- 8.3 review: his seat for a crew mate (Vehicles.yieldSeat, after server/Buddy.luau's).
local function wire()
	if wired then
		return
	end
	wired = true
	local yieldBefore = Vehicles.yieldSeat
	Vehicles.yieldSeat = function(seat: Seat, player: Player?): boolean
		if yieldBefore and yieldBefore(seat, player) then
			return true
		end
		local ok, done = pcall(yieldTo, seat, player)
		return ok and done == true
	end
	local before = Zombies.extraTargets
	Zombies.extraTargets = function(): { Zombies.ExtraTarget }
		local list: { Zombies.ExtraTarget } = {}
		if before then
			local ok, got = pcall(before)
			if ok and type(got) == "table" then
				list = got
			end
		end
		for s, h in helpers do
			local body = h.body
			if not h.dead and not s.ended and body and body.model.Parent and body.humanoid.Health > 0 then
				table.insert(list, { position = body.root.Position, velocity = body.root.AssemblyLinearVelocity, humanoid = body.humanoid, player = s.owner })
			end
		end
		return list
	end
	Net.get("Moving").OnServerEvent:Connect(onRequest)
	task.spawn(function()
		while true do
			local dt = task.wait(cfg.Tick)
			if next(helpers) ~= nil then
				MoveHelper.step(math.min(dt or cfg.Tick, 0.5))
			end
		end
	end)
end

local function create(s: any, port: Port): Helper
	wire()
	local clock = os.clock()
	local id = ID_BASE - (tonumber(s.id) or 0)
	local origin: CFrame = s.origin
	local entry: CFrame = origin * (s.plan.entry :: CFrame)
	local exitIn = (origin * CFrame.new(s.plan.exit :: Vector3)).Position
	local outside: CFrame = s.site.outside
	-- 7.x farm move: every way in and out (Moving's s.ways), else the front door's
	local ways: { Way } = {}
	local wayDoors: { Brain.Doors } = {}
	for _, way in (if type(s.ways) == "table" then s.ways else {}) :: { any } do
		local out: CFrame = way.door.outside
		local made: Way = { exitIn = way.inside, entryIn = way.entry, outside = out, doors = { outX = out.Position.X, outZ = out.Position.Z, inX = way.inside.X, inZ = way.inside.Z } }
		table.insert(ways, made)
		table.insert(wayDoors, made.doors)
	end
	if #ways == 0 then
		local made: Way = { exitIn = exitIn, entryIn = entry, outside = outside, doors = { outX = outside.Position.X, outZ = outside.Position.Z, inX = exitIn.X, inZ = exitIn.Z } }
		table.insert(ways, made)
		table.insert(wayDoors, made.doors)
	end
	local doorways, fronts = doorwaysOf(s, origin)
	local h: Helper = {
		s = s,
		port = port,
		id = id,
		body = nil,
		hooks = {},
		health = cfg.Health,
		dead = false,
		downAt = 0,
		action = "wait",
		spot = nil,
		fleeing = false,
		fleeAt = nil,
		fleeSet = 0,
		stuckFor = 0,
		repathed = false,
		lastPos = nil,
		doorAt = 0,
		path = {},
		pathIndex = 1,
		pathGoal = nil,
		pathAt = -math.huge,
		pathing = false,
		pathFailedAt = -math.huge,
		gaveUp = {},
		helpSince = 0,
		gripped = nil,
		holdOffset = nil,
		trail = Brain.newTrail(),
		holdAt = nil,
		holdLimit = 0,
		steadied = nil,
		lineKey = nil,
		lineAt = 0,
		vanSaid = nil,
		waited = 0,
		dropping = false,
		thinkAt = 0,
		lift = nil,
		pick = nil,
		pair = false,
		full = false,
		toldFull = false,
		fitKey = -1,
		fits = {},
		input = { hired = false, dead = false, holding = nil, seated = false, ride = false, threat = nil, fleeing = false, lift = nil, queued = nil, pair = false, open = false,
			atHouse = false, call = nil },
		lifts = {},
		liftPool = {},
		next = {},
		nextPool = {},
		doors = ways[1].doors,
		doorways = doorways,
		fronts = fronts,
		exitIn = ways[1].exitIn,
		entryIn = ways[1].entryIn,
		ways = ways,
		wayDoors = wayDoors,
		saidAt = {},
		lastSaid = -math.huge,
		doing = Brain.doing("offer"),
		doingAction = "wait",
		doingSpot = nil,
		doingFull = false,
		doingHired = false,
		told = {},
		call = nil,
		helpWalk = nil,
		hirer = nil,
		price = Brain.hirePrice(#((s.move :: Rules.Move).order)),
		queue = {},
		marks = {},
		needs = nil,
		needsAt = 0,
		needsTold = nil,
		sign = nil,
		seat = nil,
		seatCar = nil,
		yieldAt = 0,
		rideWalk = nil,
	}
	helpers[s] = h
	byId[id] = h
	if spawnBody(h, homeSpot(h)) then
		say(h, "hello", clock, true)
	else
		h.dead, h.downAt = true, clock - cfg.Respawn + 2 -- (tried again in a moment)
	end
	local price = Brain.money(h.price)
	tell(h, if Config.Sandbox.On then `🧑‍🔧 {cfg.Name} waits by your van: pick him to hire him for this move ({price}). He carries the pieces you pick and lifts the heavy ones with you.`
		else `🧑‍🔧 {cfg.Name} from the depot waits by your van: HIRE him under the move's panel ({price}) and he lifts the heavy pieces with you.`)
	return h
end

local function syncOne(s: any, port: Port)
	if s.ended then
		return
	end
	local h = helpers[s]
	local hirer = if h then h.hirer else nil
	if h and hirer and (not hirer.Parent or not s.members[hirer]) then
		endHire(h, hirer) -- 8.3 (whoever paid owns the hire)
	end
	local count = 0
	for player in s.members do
		if player.Parent then
			count += 1
		end
	end
	local want = Brain.wanted(count, h ~= nil and h.hirer ~= nil)
	if want and not h then
		h = create(s, port)
	elseif not want and h then
		dismiss(h, "crew")
		return
	end
	if h then
		tellCrew(h)
	end
end

function MoveHelper.sync(s: any, port: Port)
	local ok, err = pcall(syncOne :: any, s, port)
	if not ok then
		warn(`[MoveHelper] {err}`)
	end
end

function MoveHelper.nameOf(id: number?): string?
	return if id and byId[id] then cfg.Name else nil
end

-- The helper on this player's move (his state, for the tests and the admin), or nil.
function MoveHelper.find(player: Player): any
	for s, h in helpers do
		if not s.ended and (s.owner == player or s.members[player]) then
			return h
		end
	end
	return nil
end

return MoveHelper
