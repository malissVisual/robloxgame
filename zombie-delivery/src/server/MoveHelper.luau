--!strict
-- 7.0, the depot's helper ("Danny from the depot"; the owner's decision in design/rework/NAVRH.md: solo play is allowed
-- with an AI helper). An NPC mover who comes with a move whose crew is a single player (Config.MoveHelper.Duo: two
-- players too, off by default; 10.1 the sandbox's runs: every party, its host's pick of their crew).
-- server/Moving.luau calls MoveHelper.sync(session, Moving) every tick: he comes when the crew is small enough and goes
-- when it grows (setting down what he holds); his own loop
-- (Config.MoveHelper.Tick) walks him. His decisions are shared/MoveHelperBrain.luau's (pure: tests/movehelper_test.luau);
-- what he does with the pieces goes through Moving's helper hooks (Moving.helperTake / helperDrop / helperLoad /
-- helperHurt: the same rules, welds and damage as a player's hands); tests/movehelper_runtime_test.luau and
-- tests/movehelper_art_runtime_test.luau run the real module with the real Moving.
-- 8.3 Danny's list (the owner: "It doesn't work well when he does 4 things. Instead: he helps, but for example you go
-- into the house, click on something, and that assigns it to him, and the rest you carry yourself"; and "mainly, he
-- must sit in my car with me"). (8.3 - 10.0 he was for hire first: a price a move, the HIRE on his card; 10.1 the crew,
-- below: free and with you from the start. "Hired" in this module's words is every move's helper now.)
--   * His list: a click (a tap; a gamepad's "Give to Danny") on a piece of the move sends ("helper", "assign", its
--     model): checked here (MoveHelperBrain.assignCheck: the move's crew, 8.5 the player's clipboard out (orders
--     mode: their character's ClipboardHeld, server/Clipboard.luau's; else "Take out your clipboard"), the move's own
--     piece, not in the van or home, nobody holding it, near enough, Config.MoveHelper.Queue at most;
--     Config.Robust.Limits.MoveHelperAssign) it goes on his list ("Danny will take the Lamp."), a 🧑‍🔧 marker over it with its number (the piece's
--     attributes DannyQueue / DannyNeeds for the clients); a click on it again takes it back. He carries them in that
--     order (MoveHelperBrain.nextQueued: the first that still fits the van), each as he always has: a path inside, the
--     front door his own way, a path to the van's back, the back opened, loaded (MovingRules' packer), his walk × the
--     carry's. A two-person piece of his list: he goes to it and waits at one end ("needs": "🙋 Danny needs you" over
--     it, a toast, its Lift says "Lift with Danny"); your Lift there is your call below. A piece of his list you pick up
--     yourself leaves it ("All yours, boss."); CLEAR QUEUE (the card's: ("helper", "clear")) empties it; an empty list,
--     he waits by the van ("All done. Anything else, boss?"). Everything else is yours to carry.
--   * Your call (Config.MoveHelper.WaitForHelper; hired only): Lift on a two-person piece while he can come (his body up,
--     his hands not on another piece's end) is no drag alone: you say "Danny, give me a hand!" (a
--     bubble over your head, a toast; the player attribute MoveHelperCall = its name: your status line says you wait,
--     its STOP and G stop it), its Lift prompt says "Stop waiting", and he WALKS to its far end as you will hold it
--     (Moving's helperLiftFrame), through the walk-in doors his own way, never faded over but as the last resort
--     (CallBlink s no closer). His own piece first: into the van right there, else set down (back at the head of his
--     list). In place (MoveHelperBrain.inPlace): "On three... lift!", your grip steadied, and Moving opens your lift
--     check (helperCalled; no grip: the lift at once); its hit lifts it with him at its far end (joinLift: his hold
--     starts where he stands). Lift again, G, STOP, walking away (callKept) or his fall end it.
--   * 10.6 (only the sandbox is the game: nobody drives, the ride is the clients' animation, client/RideUi.luau): he never
--     sits in the van (8.3 - 10.5 he rode along in its passenger seat while you sat at its wheel, got out for a crew
--     mate's Ride along, and GET OUT took him out). 8.5.1 (the owner: "Danny STILL goes through it"; checked on the van
--     the game builds, tests/movehelper_realvan_runtime_test.luau): EVERY way of his outside keeps RideHug off the van's
--     footprint (go: aroundVan, round the van when a way crosses it), he is never left inside it (outOfVan: beside it
--     at once, faded in; besideVan: where he comes out of the house). His right hand is free of a door's handle.
--   * Carrying together: he moves WITH the piece: his own walk is off (Npcs.carried), constraints on his root
--     (AlignPosition / AlignOrientation aimed at the piece's far end, turned to you; 9.0 one attachment each, his own,
--     their goals the server's) hold him there every physics step, on the floor under that end (stairs, steps: within
--     HoldStep of you), through door frames like the piece itself (a collision group nothing collides with; 9.0 inside
--     a house along the walls, never through them: HoldWall), through the front door's fade with you. Never a
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
--   * 8.6 (the owner: "the carrying is still bad. He teleports from side to side"; a screenshot: Danny beside the Dining
--     Table, at its side, the table floating between them): the piece lies along the carry, low (server/Moving.luau's
--     holdOffset: its grips at the hands), and his end is the face across it from you, decided once as the hold starts
--     and kept in the piece's own frame (h.holdEnd: MoveHelperBrain.holdEnd), so the far end of its length: your turn,
--     a square-ish piece, a late look at you never make it another end. His lead follows his END's own way (the
--     piece's turn in it) and changes HoldLead.Rate studs a second at most (MoveHelperBrain.endLead: it was your root's
--     velocity, taken at once: your step back, a turn's step aside, an uneven look at you threw his aim across and he
--     ran there); an ease back is HoldCap at most. His hands on his end's edge at its grips' height (Config.MoveHelper
--     Edge). Your call: once he is there it goes up at once on his "On three... lift!" (no lift check after the wait,
--     Config.MoveHelper.CallCheck; the hold turns him to you, never a snap).
--   * Your two-person piece dragged alone (hired; he could not come to your call: a crew mate's call, him down): he
--     sprints to its far end and takes it (MoveHelperBrain.pickLift).
--   * The van's back: somebody of the crew coming with a piece within OpenNear of the shut back while he is within
--     OpenFar of it (hired): he opens it ("I'll get the doors!"). With a piece of his own at the shut back he opens it
--     himself (OpenBack, else "Open the back, boss!" and WaitShut s, then set down beside it); no room: set down beside
--     the van ("Van's full, boss - drive it home?").
--   * Unstuck (9.3, see below): no progress along his way for Unstuck.Repath s, a new way; then his ways out, walked;
--     only Unstuck.Fade s without progress a fade over (8.9's nudge to his way's next point after 4 s is gone). Where
--     he stands still (waiting) he keeps out of the doorways (MoveHelperBrain.aside).
--   * The crew's attributes (client/MoveHelperHud.luau's status line under the move's panel, his card): MoveHelper =
--     "hired" (with you: 10.1 always; the 8.3 word kept), MoveHelperQueue (the pieces on his list), MoveHelperDoing
--     (what he does), MoveHelperId (his id: the card finds his body by it), 10.1 MoveHelperName and MoveHelperKind.
--   * He stays out of fights: a zombie within FleeRange, he runs (never while holding the other end of your piece).
--     The zombies go after him like after a player on foot (Zombies.extraTargets); a bite knocks
--     what he holds (Moving.helperHurt); at 0 health he drops it (knocked; his own piece back on his list) and lies down
--     (10.1: down in the run, the revive prompt on him: server/HelperCrew.luau).
--   * He talks a little: a speech bubble (Npcs.say) on the way's events, never the same line within TalkRepeat s
--     (MoveHelperBrain.line's sandbox words: no Wall, no depot).
-- 8.6 (the owner: "Somewhere I'd like to see an indicator of what Danny is doing right now, and to be able to tell him,
-- for example, put it down on the ground, or get out of the car"):
--   * What he does over his head: setDoing makes the status line's words and the bubble's from the same action
--     (MoveHelperBrain.doing / bubble: "📦 Carrying: Sofa → van"), the crew's attributes MoveHelperBubble and
--     MoveHelperAlert (orange: he needs you, he is down, running); client/DannyBubble.luau draws it for the crew only.
--   * The crew's orders, the Moving remote's ("helper", "putdown" | "getout") at Config.Robust.Limits.MoveHelperOrder:
--     a crew player's only (anybody else: nothing), checked (MoveHelperBrain.orderCheck), refused with a notice that
--     says why ("Danny isn't carrying anything."); the orders that apply now go to the crew (MoveHelperOrders: his
--     card's buttons, the orders menu). PUT IT DOWN (putDown): what he carries set down where he stands, its condition
--     kept; a piece of his list stays off it (your word beats the list); a two-person piece he holds with you: both
--     ends down (Moving's helperDrop "together"). (10.6: GET OUT never applies: he is never in the van.)
-- Performance: one helper per move, one loop for all of them, a path at most every Repath s (computed in the background,
-- one Path object each), his walk ordered again only when its goal moves (Npcs.walkTo), his list's room in the van
-- worked out only when the load changes (every Think s); carrying together the physics engine moves him (the loop only
-- re-aims his place at the far end and his top speed, a ray down a step, 9.0 a slide along a few wall slabs; PairHold's
-- one Heartbeat sets the constraints' goals from it).
--   MoveHelper.sync(s, port)   Moving's tick: the move's crew (he comes or goes; 10.1 the crew's: HelperCrew.sync) and his
--                              hands (Moving's helper hooks)
--   MoveHelper.step(dt)        one step of every helper (his loop's; the runtime test calls it)
--   MoveHelper.useMover(m)     how he walks (a test's: the Luau CLI has no physics and no pathfinding)
--   MoveHelper.gameMover       9.0 the game's own mover (a test's walk can borrow its keep and free: the real hold)
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
-- 9.0 (the owner, 8.9: "Danny can't walk around things logically. He goes to take things through the wall: he can't get
-- to the thing, he got stuck on the wall because he can't walk around it. He must not take things through walls … And he
-- must come to the thing nicely and take it into his hands properly, with an animation"; Config.MoveHelper Route, Pick,
-- MarkFar). The cause (tests/houseroute_test.luau measures it on the real plans): he was aimed at a point straight out of
-- the piece toward where he came in (besidePiece), whatever stood between: in the next room, in a wall, out of the
-- house; PathfindingService found no way there (a point within its agent radius of a wall) and he walked the straight
-- line into the wall, the stuck nudge put him on along it, and his take asked only how far the piece's middle was (from
-- the next room: near enough, a take through the wall). Now:
--   * Inside a house with a plan (shared/HouseRoute.luau; tests' fakes without walls: as before) his ways are the plan's
--     grid's (routeTo: the walls, the solid fixtures and every piece standing in the house, blocked again when one goes
--     or moves: think's routeNow), through the doorways and round the furniture, never into a wall (9.3: a stuck spell
--     his ways out, walked, no nudge any more). PathfindingService outside.
--   * The piece he goes for: he walks to its near side and stops at arm's length (standOf: HouseRoute.reach, its line to
--     the piece's middle through no wall); none, or out of his reach there Pick.Tries times: he can't get to it, it is
--     off his list ("can't get to it"). A piece the crew gives him that has no such spot is refused at once (assign:
--     MoveHelperBrain.assignCheck's "reach"). He takes it only beside it (canTake: within Pick.Arm of its footprint, his
--     chest's ray to its middle hitting none of the interior's walls).
--   * His pick-up (handle, a few steps; everybody sees it: his body's attributes, the server's piece): he turns to it
--     (Npcs.face, Pick.Turn s), bends and reaches with both arms (Npcs.act "lift": shared/BodyMotion.luau, his hands on
--     the piece by the Carrying attributes, client/ArmPose.luau), Pick.Bend s later it is his (Moving.helperTake) and it
--     glides up into his hands over Pick.Lift s (its weld off meanwhile, eased every frame: handFrames) as he stands up
--     into his carry. Setting one down the other way ("setdown": it glides down to the floor in front of him, then
--     Moving.helperDrop). A piece for two: his end the same bend ("lift") as your lift takes it up, then the 8.6 carry.
--   * His list's markers (newMark): AlwaysOnTop off, MaxDistance MarkFar: seen in the same room and through an open
--     doorway, never through a wall.
-- 9.0 carrying in two, walked forwards (the owner, 8.9.3: "Danny carries better now, but only when I walk backwards.
-- When I want to walk forwards, Danny can't walk backwards"; then "and he still teleports", his screenshots: Danny
-- standing inside the Sofa, his own body lying across it; tests/movehelper_backwards_runtime_test.luau measures it):
--   * His hold's constraints reached into your assembly (their Attachment1 on the piece, welded to your root): one
--     mechanism of his server-owned body and your own. Now they have one attachment, his (server/PairHold.luau: the
--     server sets their goals from the piece every Heartbeat); nothing of his hold touches your body.
--   * His body never in the piece: following you, his lead toward its middle is HoldLead.In at most (it put his chest 2
--     studs into the Sofa where everybody else saw him, and on your screen once you stopped); his hands reach on by the
--     rest (poseHands: MoveHelperBrain.endLead's reach, Edge.Reach at most). Walking backwards himself his lead is
--     HoldLead.Back s longer (your screen may show him later than its guess).
--   * Your side (client/PairSteer.luau): your character's PairWith (his id) and PairFar (his place in your root's frame,
--     pairOn) let your client see him as your screen does: your walk's start waits for him and you never push the
--     piece into him there (Config.MoveHelper.PairStart, PairKeep).
--   * Inside a house he walks backwards along the walls, never through them (slideAlong: the plan's wall slabs,
--     HouseRoute.slide, HoldWall.Clear off them; every Heartbeat as his hold's bound), never while he follows you (his
--     end goes where you went, a corner cut through a doorway's jamb as the piece cuts it); held back by a wall, your
--     walk into it goes (PairWall: HoldWall.Block's share), slowed as he nears it, stopped against it.
--   * Nothing else steers him while he holds it: his way (HouseRoute), a stuck nudge, placeAt and the van's outline are
--     other actions' (actHold alone runs; think only blocks his grid's cells again).
-- 9.2 you drive his end (the owner, 8.9.5: "the carrying is better, but it feels like it's harder to control … fix it so
-- it's playable"; 9.0's start waited 0.85 s in Studio, 2 s online, for his late body on your screen):
--   * Holding the far end of a piece a player leads (its carrier: Config.MoveHelper.PairLead.On), his body's physics is
--     that player's (gripOn → server/PairHold.luau make / lead: root:SetNetworkOwner(them); his model's PairLead,
--     PairLeadAt, PairLeadPiece): their client sets his hold's goals from their own piece every frame (client/
--     PairLead.luau), so on their screen he is at his end with no lag, and their walk is not held back at all (client/
--     PairSteer.luau). The server writes none of his constraints meanwhile, aims him with no lead (actHold: his hands on
--     the edge, never into the piece) and leaves the house's walls to their client (its rays: no slide here, no PairWall).
--   * A door's trip still puts him there (snap: the server's PivotTo moves a body a client owns on every machine; their
--     client also puts him there when his place is Jump studs off).
--   * The server looks (MoveHelperBrain.leadKept): his body more than PairLead.Sane studs off his end in its own view for
--     Grace s (an exploit flinging him, a client that stopped driving) and it takes his body back for the rest of that
--     carry (h.leadOff): the 9.0 hold again (lead, slide, PairFar), never a snap.
--   * Let go (put down, dropped, his fall, you leave, his body gone): the hold's drop takes his body back before
--     Npcs.carried stands him. A crew mate at the far end is the server's as before (server/PairHold.luau follow).
-- 9.3 (the owner, 8.9.5: "Danny still annoys me. He takes it completely like a robot. For example, he runs for 2 seconds
-- and then on the spot he somehow teleports around … fix it so it's playable"; tests/movehelper_stuck_runtime_test.luau
-- sweeps his body along his ways in the six real houses, their parts as built, and runs him with a walk that never
-- goes into a collidable part):
--   * The cause: his walk turned to his way's next corner a stud before it (routeTo), cutting the corner: his 2-stud
--     body came 0.35 studs off a wall's end (1,130 swept steps within his half width), so in Roblox he was pressed
--     against it, and from there off the open cells his next leg ran along that wall's end into it; a new path gave the
--     same leg, and StuckSnap s later the nudge put him on (the teleport on the spot). The plan also missed a part that
--     collides (the garage door's leaf).
--   * His walk (go, wayTo): aimed at a point Walk.Ahead studs or more along his way (HouseRoute.ahead: the farthest whose
--     straight line from him keeps Walk.Clear studs off every wall, fixture and piece exactly; outside, PathfindingService's
--     way, its corners cut Walk.Cut studs at most), ordered again as it moves on (never a stop at a corner), slowing over
--     the last Walk.Ease studs (MoveHelperBrain.ease), at his goal turned to what he does (Npcs.face, Walk.Turn s: a
--     tween, never a PivotTo). His grid closes the cells of the built interior's collidable parts too (HouseRoute.solid)
--     and pulls its legs straight only that far off them. His legs: Npcs.walkTo's `legs` (the walk only while he really
--     moves, the idle when he stands: no running on the spot).
--   * Stuck (MoveHelperBrain.progress / unstuck): no progress along his way for Unstuck.Repath s, a new way from where he
--     stands; then his own ways out, walked (a step back, a step aside onto open ground, a new way, round again); only
--     Unstuck.Fade s without progress the last resort, a fade over onto his way (never the pop on the spot).
--   * The front door: walked into its doorway while he fades out (Config.Moving.Doors FadeOut + Margin), then on its
--     other side fading in and walking on (crossStart / crossEnd: the players' walk-in doors). The Far jump only where no
--     player can see it (Walk.Seen), faded in; else he walks.
--   * Every time he is put somewhere (placeAt, pivot, blink) says why (h.teleports counts them); in Roblox Studio the
--     Output says so ("[Danny] teleport …"), and a stuck spell what blocks him ("[Danny] stuck …": Config.MoveHelper.Diag).
-- 10.1 THE CREW (the owner: "Danny will be the base, so I'd cancel having to buy him … you'll be able to get different
-- employees who can do something different"; Config.Crew, shared/CrewRules.luau, server/HelperCrew.luau):
--   * No hire any more: the helper is free and the move's from its start (h.hirer is the move's owner, the 8.3 code's
--     "hired" paths are every move's; no price, no "Hire Danny" sign, no HIRE request). He comes with every party (a
--     run's: MoveHelperBrain.wanted's `every`).
--   * Which helper: the move's owner's pick of their crew (Crew.kindFor: Danny by default, a run's host's pick: Bruno,
--     Zip, Gus or Lucy; nobody ready: no helper). h.kind and h.name are his; his look, name tag, health and the words of
--     his own are his kind's (Crew.look, Crew.health, Crew.line), his walk × his kind's (Crew.pace in go), what he may
--     carry his kind's (Crew.refuse at assign; Crew.lifts: your two-person Lift calls him and he comes to one you drag
--     only when his kind lifts with you; Crew.classFor: Bruno's list takes a piece for two as his own, carried alone:
--     Moving.helperTake's CrewSolo). Gus walks with his boss and fights (Crew.guard, before his brain's step).
--   * Down in a run (Crew.downed in his down step): no comeback at the van: he lies there with the revive prompt on him
--     for Config.Crew.Down.Seconds (a party player's E held: up with half his health), else he is out of the run (faded
--     away) and in hospital.
--   Every hook is one line here (marked "10.1"); the crew's own code is server/HelperCrew.luau's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.MovingRules)
local Brain = require(Shared.MoveHelperBrain)
local Route = require(Shared.HouseRoute) -- 9.0 his way inside a house
local Npcs = require(script.Parent.Npcs)
local PairHold = require(script.Parent.PairHold) -- 8.1: the far end's hold (Danny's and a crew mate's)
local Crew = require(script.Parent.HelperCrew) -- 10.1 the helpers' crew: each kind's carry, walk and words; down in a run
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
-- in, the door's outside, as Brain.Doors for the costs. 9.3 `door`: the door's foot outside (he walks on into its
-- doorway as he fades out).
type Way = { exitIn: Vector3, entryIn: CFrame, outside: CFrame, door: Vector3, doors: Brain.Doors }

-- 9.3 his walk through a door now: by which way, into the house or out of it (`inside`: where he goes), since when, the
-- point in its doorway he walks on to while he fades out.
type Crossing = { way: Way, inside: boolean, at: number, through: Vector3 }

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
	held: { [Instance]: number }?, -- 9.3 the piece in his hands' own transparency while it fades with him through a door
}

-- How he walks: one step toward `to` at `speed` studs / s; a stop; his way round the walls (may yield; nil: straight).
-- 7.x carrying together: keep him at `offset` in `anchor`'s frame (the far end of your piece) / let go of it; a fade-in
-- where he was just put (the fade-over). 8.1: keep walks him there at `limit` studs / s at most (snap: put there, a
-- door's fade only). Without keep he steps there at `limit` × dt at most (a test: no physics). 9.2 `driver`: the leader
-- whose client drives his hold (server/PairHold.luau lead; nil: the server holds him).
export type Mover = {
	move: (body: Body, to: Vector3, speed: number, dt: number) -> (),
	halt: (body: Body) -> (),
	route: ((body: Body, from: Vector3, to: Vector3) -> { Vector3 }?)?,
	keep: ((body: Body, anchor: BasePart, offset: CFrame, dt: number, limit: number, snap: boolean, driver: Player?) -> ())?,
	free: ((body: Body) -> ())?,
	appear: ((body: Body) -> ())?,
	fade: ((body: Body, out: boolean, seconds: number, with: Instance?) -> ())?, -- 9.3 a door's walk-through: out of sight (`with` the piece in his hands), in sight again
}

-- 8.3 a crew player's call: their two-person piece, since when, he is in place (their lift check open) since readyAt,
-- his walk there (MoveHelperBrain.approach: the last resort's clock).
type Call = { player: Player, spot: number, since: number, ready: boolean, readyAt: number, approach: Brain.Approach }

-- 9.0 where he goes to take a piece (standOf): its spot, the pieces standing as it was worked out (routeKey), from
-- inside the house or from its way in, waiting there or not; the stand (nil: he can't get to it).
type Stand = { spot: number, key: string, from: boolean, wait: boolean, at: Vector3? }

-- 9.0 a way in or out chosen for a goal (wayFor): the goal, from inside or not, the pieces (routeKey) and the ways he
-- might take then, which.
type WayPick = { goal: Vector3, inside: boolean, key: string, may: string, which: number }

-- 9.0 his pick-up or his setting down (handle): which piece, the phase ("turn" → "bend" → "lift"; "down") and since when
-- (os.clock); while the piece glides, its root and its weld to his root (off meanwhile), from where (world) to where
-- (pick: his hold in his root's frame; put: on the floor, world); a put's why (Moving's helperDrop) and whether it goes
-- back on his list after.
type Handle = {
	kind: string,
	spot: number,
	phase: string,
	at: number,
	root: BasePart?,
	weld: WeldConstraint?,
	from: CFrame?,
	to: CFrame?,
	why: string,
	requeue: boolean,
}

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
	repathed: boolean, -- (8.9's: a new path asked in this stuck spell; 9.3 his phase says so)
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
	holdEnd: Vector3?, -- 8.6 his end of it in its own frame (its axis × studs out of its middle), decided as the hold starts
	trail: Brain.Trail, -- 8.1 how long he has been behind his place at the far end (MoveHelperBrain.holdTrack)
	holdAt: Vector3?, -- 8.1 where his root was a step ago holding it (his legs' speed)
	holdLimit: number, -- 8.1 his top speed holding it now (the tests read it)
	steadied: Model?, -- 7.x the carrier's character with GripSteady
	walled: Model?, -- 9.0 the carrier's character with PairWith / PairFar / PairWall (pairOn)
	leadOff: BasePart?, -- 9.2 the piece whose drive the server took back (its look: MoveHelperBrain.leadKept): his for that carry
	leadAway: number?, -- 9.2 …s his body has been off his end while driven
	wallWay: Vector3?, -- 9.0 his end against a wall of the house: the way into it × how much of the walk into it goes
	bound: ((Vector3, Vector3) -> Vector3)?, -- 9.0 his hold's bound along the house's walls (boundOf: made once)
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
	told: { [Player]: boolean }, -- the players with his attributes
	call: Call?, -- 8.3 a crew player waits for him at their two-person piece
	helpWalk: Brain.Approach?, -- 8.3 his walk to a piece you drag alone (the last resort's clock)
	-- 8.3 his list (10.1: no hire: the move's owner is his boss from the start)
	hirer: Player?, -- whose helper he is (the move's owner: his loads go into their stock in a run)
	kind: string, -- 10.1 his kind (Config.Crew.Kinds: danny, bruno, zip, gus, lucy)
	name: string, -- 10.1 his name (Danny, Bruno …)
	queue: { number }, -- his list: the pieces' spots in the order they were clicked
	marks: { [number]: BillboardGui }, -- the markers over them
	needs: number?, -- the two-person piece of his list he waits at for you …
	needsAt: number, -- … since (0: on his way)
	needsTold: number?, -- the one the crew was told about (once a piece)
	bubble: string, -- 8.6 what he does over his head (MoveHelperBrain.bubble: the same action's as doing)
	alert: boolean, -- …in the movers' orange
	orderIn: Brain.Order, -- 8.6 his state for the crew's orders (orderState fills it)
	-- 9.0 his way inside the house (shared/HouseRoute.luau), his pick-up
	route: Route.Grid?, -- the plan's grid (nil: a plan without walls, a test's fake)
	routeKey: string, -- the pieces standing in the house when it was blocked last
	doorZones: { Route.Rect }, -- the interior's doorways in the plan's frame (Aside's zones): never a spot to wait in
	pathInside: boolean, -- path is a way on the grid (inside), not PathfindingService's
	pathKey: string, -- … worked out with the pieces as routeKey says
	stand: Stand?, -- where he goes to take the piece he goes for
	wayPicks: { WayPick }, -- his ways in and out chosen for his last goals (wayFor)
	tries: { [number]: number }, -- takes that found a piece out of his reach or behind a wall (Pick.Tries: given up)
	handle: Handle?, -- his pick-up or setting down now
	-- 9.3 his walk
	pathXZ: { Route.Point }, -- his way's points as HouseRoute.ahead reads them (inside: the plan's frame; outside: X, Z)
	pathFresh: boolean, -- a new way since his last step (its length his progress's best)
	progress: Brain.Progress, -- his progress along his way (MoveHelperBrain.progress: stuckFor)
	progressGoal: Vector3?, -- … toward this goal
	phase: string, -- his stuck spell's phase (MoveHelperBrain.unstuck) and its round
	phaseRound: number,
	recover: Vector3?, -- where a way out of it walks him now (back, aside)
	crossing: Crossing?, -- his walk through a door now
	solids: boolean, -- the built interior's parts closed on his grid (HouseRoute.solid: once)
	teleports: { [string]: number }, -- every time he was put somewhere, by why (the tests')
	diagAt: { [string]: number }, -- Studio's lines, when each was said last
}

local ID_BASE = -2000000000 -- (no player's id is this low; Studio's test players are -1, -2 …)
local FALL = 3 -- s a body that went (removed by something else) counts as fallen that long ago
local INSIDE = 400 -- studs from a move's interior origin that count as inside it
-- Npcs.walkTo's options: he walks on into the next order (8.3: no jump; 9.3 his legs by his real speed: Npcs' `legs`).
-- (Roblox: Humanoid:MoveTo walks him straight at the point and stops there by itself; with the Jumping state off a
-- ledge higher than a step (Config.MoveHelper.Body.StepUp) stops him: his ways keep off every such part.)
local WALK = { through = true, near = 0.6, jump = false, legs = true }
local HANDS = { "Carrying", "CarryCount", "CarryHands", "CarryAt", "CarrySize" } -- 7.x his arms (client/ArmPose.luau)
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local ATTRIBUTES = { "MoveHelper", "MoveHelperDoing", "MoveHelperId", "MoveHelperCall", "MoveHelperReady", "MoveHelperQueue",
	"MoveHelperBubble", "MoveHelperAlert", "MoveHelperOrders", "MoveHelperName", "MoveHelperKind" } -- (8.6: the bubble over his head, the orders that apply; 10.1 his name and kind)

local helpers: { [any]: Helper } = {} -- by the move's session
local byId: { [number]: Helper } = {}
local wired = false
local notice = Net.get("Notice")

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 9.3 Roblox Studio's Output (Config.MoveHelper.Diag): on only in Studio (a test turns it on with its own sink:
-- MoveHelper.diagnose). A line of `key` Every s apart at most per helper.
local diagnostics = { on = false, sink = nil :: ((string) -> ())? }
local Walking = {} -- 9.3 his walk's helpers (one table: the module's top level is near the 200-register limit)
pcall(function()
	diagnostics.on = game:GetService("RunService"):IsStudio()
end)
function MoveHelper.diagnose(on: boolean, sink: ((string) -> ())?)
	diagnostics.on, diagnostics.sink = on, sink
end
function Walking.report(h: Helper, key: string, text: string, clock: number)
	if not diagnostics.on then
		return
	end
	local last = h.diagAt[key]
	if last and clock - last < cfg.Diag.Every then
		return
	end
	h.diagAt[key] = clock
	local line = `[{cfg.Name}] {text}`
	local sink = diagnostics.sink
	if sink then
		sink(line)
	else
		print(line)
	end
end
function Walking.spot3(at: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", at.X, at.Y, at.Z)
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

-- 7.x his root glued to `offset` in the piece's frame: AlignPosition and AlignOrientation on his root aimed there (the
-- physics engine moves him every step, the server owns him; 9.0 one attachment each, his own: the server sets their
-- goals, nothing joins him to the piece), his own walk off, his parts in the group nothing collides with (8.1
-- server/PairHold.luau's make: at `limit` studs / s at most). 9.2 `driver`: the leader whose client drives him (his body
-- theirs, PairHold.lead), after Npcs.carried set his Physics state while the server owned him.
local function gripOn(body: Body, anchor: BasePart, offset: CFrame, limit: number, driver: Player?)
	gripOff(body)
	Npcs.carried(body.model, true)
	body.walking, body.ordered = false, nil
	body.grip = PairHold.make(body.model, body.root, anchor, offset, limit, { ghost = true, flat = false, owner = nil, lift = true, driver = driver }) -- (8.3 lift)
end

-- 9.3 his parts' own transparency (the fades'), read once.
function Walking.ownLook(body: Body): { [Instance]: number }
	local alpha = body.alpha
	if alpha then
		return alpha
	end
	local seen: { [Instance]: number } = {}
	for _, d in body.model:GetDescendants() do
		if d:IsA("BasePart") then
			seen[d] = d.Transparency
		elseif d:IsA("Decal") then
			seen[d] = d.Transparency
		end
	end
	body.alpha = seen
	return seen
end

-- 9.3 his body faded out of sight (`out`) or into it again over `seconds` (a few steps; the server's parts, every client
-- sees it), a newer fade taking over; `with` (fading out): the piece in his hands fades with him (its own look kept in
-- body.held, given back as he fades in again: never a piece floating through the doorway alone).
function Walking.fadeBody(body: Body, out: boolean, seconds: number, with: Instance?)
	local own = Walking.ownLook(body)
	if out and with then
		local held: { [Instance]: number } = {}
		for _, d in with:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				held[d] = (d :: any).Transparency
			end
		end
		body.held = held
	end
	local held = body.held
	body.fade += 1
	local token = body.fade
	local steps = math.max(1, math.ceil(seconds / 0.05))
	task.spawn(function()
		for k = 1, steps do
			task.wait(seconds / steps)
			if body.fade ~= token then
				return
			end
			local u = k / steps
			for _, list in { own, held or {} } do
				for obj, t in list do
					if obj.Parent then
						(obj :: any).Transparency = if out then t + (1 - t) * u else 1 - (1 - t) * u
					end
				end
			end
		end
		if not out and body.held == held then
			body.held = nil
		end
	end)
end

-- 9.3 the piece that faded with him given its own look back at once (his fall, his body gone, a walk through a door
-- broken off).
function Walking.unfade(body: Body?)
	local held = body and body.held
	if body and held then
		body.held = nil
		for obj, t in held do
			if obj.Parent then
				(obj :: any).Transparency = t
			end
		end
	end
end

local mover: Mover = {
	-- 9.3 ordered again as the point he is aimed at moves on (Walk.Reorder s apart), at once when it jumped or he is
	-- within Walk.Near of it (Humanoid:MoveTo stops at its point: never a stop on the way); his walk's speed is the
	-- humanoid's WalkSpeed (his legs Npcs.walkTo's `legs`: by his real speed)
	move = function(body: Body, to: Vector3, speed: number, _dt: number)
		if math.abs(body.speed - speed) > 0.05 then
			body.speed = speed
			body.humanoid.WalkSpeed = speed
		end
		local ordered = body.ordered
		local clock = os.clock()
		local w = cfg.Walk
		local moved = if ordered then (to - ordered).Magnitude else math.huge
		if not body.walking or not ordered or moved > 4 or (moved > 0.2 and (clock - body.orderedAt >= w.Reorder or flat(body.root.Position, ordered) < w.Near))
			or clock - body.orderedAt > 2 then
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
	-- only through a door's fade (snap: MoveHelperBrain.holdTrack); his legs: actHold's. 9.2 driven by `driver`'s client
	-- (PairHold.lead: given to them, or taken back when nil)
	keep = function(body: Body, anchor: BasePart, offset: CFrame, _dt: number, limit: number, snap: boolean, driver: Player?)
		local grip = body.grip
		if not grip or not PairHold.alive(grip, anchor) then
			gripOn(body, anchor, offset, limit, driver)
			grip = body.grip
		end
		local g = grip :: Grip
		PairHold.aim(g, offset, limit)
		PairHold.lead(g, driver)
		if snap then
			PairHold.snap(g, anchor.CFrame * offset)
		end
	end,
	free = gripOff,
	-- 7.x the fade-over's end: he fades in where he was just put (his parts from clear to their own look)
	appear = function(body: Body)
		for obj in Walking.ownLook(body) do
			(obj :: any).Transparency = 1
		end
		Walking.fadeBody(body, false, 0.25)
	end,
	fade = Walking.fadeBody, -- 9.3
}

function MoveHelper.useMover(given: Mover)
	mover = given
end
MoveHelper.gameMover = mover -- 9.0 (the game's own: a test plays Roblox's constraints on its keep and free)

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

local NOT_FLOOR = { "Npcs", "Zombies", "Cars", "Moves" } -- (outside: never a floor)

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
	table.clear(h.pathXZ) -- 9.3
	h.pathIndex, h.pathGoal, h.pathInside = 1, nil, false
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
local URGENT: { [string]: boolean } = { help = true, three = true, door = true, open = true, mine = true, queued = true, revived = true }
local function say(h: Helper, key: string, clock: number, force: boolean?): boolean
	local body = h.body
	local text = Crew.line(h, key) or Brain.line(key, true) -- (the sandbox's words: no Wall, no depot; 10.1 his kind's own)
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

-- 8.6 his state for the crew's orders (MoveHelperBrain.orderCheck): down, his hands. (10.6: never in the van, which
-- never rolls: orderIn's seated, boarding, riding, leaving and moving stay false.)
local function orderState(h: Helper): Brain.Order
	local o = h.orderIn
	local spot, role = Rules.holding(h.s.move, h.id)
	o.down = h.dead or h.body == nil
	o.holding = if role == "helper" then "pair" elseif spot then "hand" else nil
	return o
end

-- His attributes on the crew (the status line, his card): with you (MoveHelper "hired": the 8.3 word, 10.1 every
-- move's), his list, what he does; off for those who left. 8.6 the bubble's words (MoveHelperBubble, MoveHelperAlert:
-- client/DannyBubble.luau) and the orders that apply now (MoveHelperOrders: his card's buttons, the orders menu, the
-- status line's GET OUT). 10.1 his name and kind (MoveHelperName, MoveHelperKind: the clients' words for him).
local function tellCrew(h: Helper)
	local s = h.s
	local state = "hired"
	local count: number? = #h.queue
	local orders = Brain.orders(orderState(h))
	local alert: boolean? = if h.alert then true else nil
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
		if player:GetAttribute("MoveHelperName") ~= h.name then
			player:SetAttribute("MoveHelperName", h.name) -- 10.1
			player:SetAttribute("MoveHelperKind", h.kind)
		end
		if player:GetAttribute("MoveHelperQueue") ~= count then
			player:SetAttribute("MoveHelperQueue", count)
		end
		if player:GetAttribute("MoveHelperBubble") ~= h.bubble then
			player:SetAttribute("MoveHelperBubble", h.bubble)
		end
		if player:GetAttribute("MoveHelperAlert") ~= alert then
			player:SetAttribute("MoveHelperAlert", alert)
		end
		if player:GetAttribute("MoveHelperOrders") ~= orders then
			player:SetAttribute("MoveHelperOrders", orders)
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
end

-- What he does, in words (made again only when it changes): the status line's and 8.6 the bubble's over his head, from
-- the same action (MoveHelperBrain.doing / bubble: one entry each, never apart).
local function setDoing(h: Helper, action: string, spot: number?)
	if action == h.doingAction and spot == h.doingSpot and h.full == h.doingFull then
		return
	end
	h.doingAction, h.doingSpot, h.doingFull = action, spot, h.full
	local thing = if spot then (h.s.move :: Rules.Move).things[spot] else nil
	local name = if thing then thing.name else nil
	h.doing = Brain.doing(action, name, h.full)
	h.bubble, h.alert = Brain.bubble(action, name, h.full)
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

-- The marker over a piece of his list: its number, or "needs you". 9.0 (the owner's screenshot: "Danny · 1 / 2 / 3"
-- over pieces in the other rooms, through the walls): drawn in the world, not on top (AlwaysOnTop off: a wall hides it,
-- the same room and an open doorway show it), MarkFar studs at most (the house's rooms, never the street).
local function newMark(root: BasePart, height: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "DannyMark"
	gui.Size = UDim2.fromOffset(160, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 1.8, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = cfg.MarkFar
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
			label.Text = Brain.markText(index, needs, h.name) -- (10.1 his name)
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

local CALL_OFF: { [string]: string } = { -- (%s: his name, 10.1)
	cancel = "You stopped waiting for %s.",
	away = "You walked away: %s's call is off.",
	idle = "%s waited at its other end, nobody lifted: the call is off.",
	down = "%s is down: lift it when they're up again, or drag it alone.",
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
		notice:FireClient(player, string.format(text, h.name))
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

-- 9.3 a stuck spell over (progress again, put somewhere, a new goal): its clock, its phase, its way out.
function Walking.unstick(h: Helper)
	h.stuckFor, h.repathed, h.lastPos = 0, false, nil
	h.phase, h.phaseRound, h.recover = "walk", 0, nil
	h.progress.best = math.huge
end

-- 9.3 every time he is put somewhere (`why`): counted (h.teleports), and in Studio a line in the Output ("[Danny]
-- teleport door 312.4 studs at (x, y, z)": where he appears) when it moves him more than a hair.
function Walking.noteJump(h: Helper, body: Body, why: string, to: Vector3)
	local studs = (to - body.root.Position).Magnitude
	if studs <= 0.25 then
		return
	end
	h.teleports[why] = (h.teleports[why] or 0) + 1
	Walking.report(h, "teleport " .. why, string.format("teleport %s %.1f studs at %s", why, studs, Walking.spot3(to)), os.clock())
end

-- 9.3 his body put at `frame` (not a walk: lying down), counted and said as placeAt is.
function Walking.pivot(h: Helper, body: Body, frame: CFrame, why: string)
	Walking.noteJump(h, body, why, frame.Position)
	body.model:PivotTo(frame)
end

-- Stands him with his feet at `at`, facing along `face` (flat); the walk stops, the way is worked out again. 9.3 `why`:
-- what put him there (noteJump; nil: "release", his hold let go of where he stands).
local function placeAt(h: Helper, at: Vector3, face: Vector3?, why: string?)
	local body = h.body
	if not body then
		return
	end
	mover.halt(body)
	local look = face or body.root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local up = Vector3.new(at.X, floorAt(h, at) + body.humanoid.HipHeight + body.root.Size.Y / 2, at.Z)
	Walking.pivot(h, body, if flatLook.Magnitude > 0.05 then CFrame.lookAt(up, up + flatLook) else CFrame.new(up), why or "release")
	Walking.unstick(h)
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

-- 9.0 the carrier's side of the hold (client/PairSteer.luau, shared/PairCarry.luau keep and wall): their character's
-- attributes PairWith (his id: their MoveHelperId), PairFar (his place in their root's frame: their screen shows him
-- there or nearer, never the piece pushed into him) and PairWall (`way`: the way into the wall his end is against × the
-- share of their walk into it to take away; nil: none); written only when they changed, all gone when he lets go (nil).
local PAIR_ATTRIBUTES = { "PairWith", "PairFar", "PairWall" }
local function setPair(character: Model, name: string, value: any)
	local now = character:GetAttribute(name)
	if value == nil then
		if now ~= nil then
			character:SetAttribute(name, nil)
		end
	elseif typeof(value) ~= "Vector3" or typeof(now) ~= "Vector3" or (now - value).Magnitude > 0.05 then
		if now ~= value then
			character:SetAttribute(name, value)
		end
	end
end
-- 9.2 `with`: PairWith all the same (their client finds his body by it: a drive needs no PairFar).
local function pairOn(h: Helper, character: Model?, far: Vector3?, way: Vector3?, with: boolean?)
	local was = h.walled
	if was and was ~= character and was.Parent then
		for _, name in PAIR_ATTRIBUTES do
			was:SetAttribute(name, nil)
		end
	end
	h.walled = character
	if not character then
		return
	end
	setPair(character, "PairWith", if far or with then h.id else nil)
	setPair(character, "PairFar", far)
	setPair(character, "PairWall", way)
end

-- 7.x the far end let go of: the glue off (he stands again), the carrier's grip as before.
local function ungrip(h: Helper, body: Body?)
	local free = mover.free
	if body and free then
		free(body)
	end
	steady(h, nil)
	pairOn(h, nil, nil, nil) -- 9.0
	h.wallWay = nil
	h.gripped, h.holdOffset, h.lineKey, h.holdAt, h.holdEnd = nil, nil, nil, nil, nil
	h.leadOff, h.leadAway = nil, nil -- 9.2
end

-- …and on his feet on the floor where he is.
local function unhold(h: Helper, body: Body)
	ungrip(h, body)
	placeAt(h, body.root.Position, body.root.CFrame.LookVector, "release")
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
		-- 8.6 (the owner: "his hands aren't on the table's edge"): its end's edge at its grips' height (MovingRules.pairLift:
		-- the grips over its middle), as wide as that end (Config.MoveHelper.Edge)
		local edge = cfg.Edge
		local mid, grip = Rules.pairLift(thing.size.Y, 0)
		-- 9.0 following you his body never goes into the piece: the lead it did not take his hands reach on toward its
		-- edge (MoveHelperBrain.endLead's reach, Edge.Reach at most: on your screen, where he shows late, on the edge)
		local reach = math.clamp(h.trail.reach or 0, 0, edge.Reach or 0)
		reach = math.floor(reach * 10 + 0.5) / 10 -- (a tenth of a stud: the attribute written only when it changes)
		at = Vector3.new(0, middle.Y + grip - mid, -(cfg.Standoff + edge.Depth / 2 + reach))
		size = Vector3.new(math.min(thing.size.X, thing.size.Z, edge.Width), edge.Height, edge.Depth)
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

-- ── 8.5.1 round the van, never through it ─────────────────────────────────

-- 8.5.1 (the owner: "Danny STILL goes through it"): the van's outline on EVERY way of his outside (go: to the
-- house's door, to the van's back with a piece, to wait by it), the van as built (its chassis' frame, its hull's
-- size). A path that knows nothing of the van, or the straight line when none came, may run across it, and his
-- collision group passes through its parts (nothing stops him, nothing says he is stuck): a next point (`way`) across its
-- footprint grown by RideHug gives way to the next point round the van to his goal (MoveHelperBrain.roundVan:
-- RideMargin out; a goal nearer it than that, its own distance). A goal inside the van itself (the walk-in bay) is left
-- as 8.5 had it.
local function vanSize(truck: Vehicles.Car): Vector3
	return (truck :: any).size or Vector3.new(6, 6, 12)
end

local function aroundVan(truck: Vehicles.Car, here: Vector3, way: Vector3, goal: Vector3): Vector3
	local frame = truck.chassis.CFrame
	local size = vanSize(truck)
	local hx, hz = size.X / 2, size.Z / 2
	local a, b, g = frame:PointToObjectSpace(here), frame:PointToObjectSpace(way), frame:PointToObjectSpace(goal)
	local off = math.max(math.abs(g.X) - hx, math.abs(g.Z) - hz) -- (the goal's studs out of the footprint)
	if off <= 0 or not Brain.crossesVan(a.X, a.Z, b.X, b.Z, hx, hz, cfg.RideHug) then
		return way
	end
	local x, z = Brain.roundVan(a.X, a.Z, g.X, g.Z, hx, hz, cfg.RideCorner, math.clamp(off - 0.1, 0.05, cfg.RideMargin))
	local point = frame * Vector3.new(x, g.Y, z)
	return Vector3.new(point.X, way.Y, point.Z)
end

-- 8.5.1: `at` clear of the move's van's outline (its footprint grown by RideHug): itself, or beside its nearer side (where
-- he comes out of the house's door with the van backed up to it).
local function besideVan(h: Helper, at: Vector3): Vector3
	local truck = truckOf(h.s)
	if not truck then
		return at
	end
	local frame = truck.chassis.CFrame
	local size = vanSize(truck)
	local rel = frame:PointToObjectSpace(at)
	local x, z = Brain.outOfVan(rel.X, rel.Z, size.X / 2, size.Z / 2, cfg.RideHug, false)
	if x == rel.X and z == rel.Z then
		return at
	end
	local point = frame * Vector3.new(x, rel.Y, z)
	return Vector3.new(point.X, at.Y, point.Z)
end

-- 8.5.1: his root inside the van itself, as high as its body (the van parked over him; a load into the walk-in bay with
-- him at its far end left him on the ground under its floor: groundAt's ray passes the cars) while his goal is outside
-- it: beside its nearer side at once, RideHug out, faded in (his body never walks out through its shell). True: he was
-- in it.
local function outOfVan(h: Helper, body: Body, truck: Vehicles.Car, goal: Vector3): boolean
	local frame = truck.chassis.CFrame
	local size = vanSize(truck)
	local rel, g = frame:PointToObjectSpace(body.root.Position), frame:PointToObjectSpace(goal)
	if math.abs(rel.X) >= size.X / 2 or math.abs(rel.Z) >= size.Z / 2 or math.abs(rel.Y) >= size.Y
		or (math.abs(g.X) < size.X / 2 and math.abs(g.Z) < size.Z / 2) then
		return false
	end
	local x, z = Brain.outOfVan(rel.X, rel.Z, size.X / 2, size.Z / 2, cfg.RideHug, false)
	local out = frame * Vector3.new(x, rel.Y, z)
	placeAt(h, out, Vector3.new(out.X - frame.Position.X, 0, out.Z - frame.Position.Z), "van") -- (facing away from the van)
	local appear = mover.appear
	if appear then
		appear(body)
	end
	return true
end

-- 8.3 his own piece back at the head of his list (set down for your call, knocked out of his arms).
local function requeue(h: Helper, spot: number?)
	if spot and not table.find(h.queue, spot) then
		table.insert(h.queue, 1, spot)
		refreshMarks(h)
	end
end

-- ── 9.0 His pick-up and his setting down ───────────────────────────────────

local function ease(u: number): number
	local x = math.clamp(u, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The weld Moving made between the piece and his root (helperTake's WeldConstraint), nil: none.
local function weldOf(item: any, root: BasePart): WeldConstraint?
	for _, child in item.root:GetChildren() do
		if child:IsA("WeldConstraint") and (child :: WeldConstraint).Part0 == root then
			return child :: WeldConstraint
		end
	end
	return nil
end

-- Is there a wall of the interior between two points (a ray at its Shell: its walls, floors and ceiling, never the
-- furniture or the fixtures)? Outside the house, or no shell: none.
local function wallBetween(h: Helper, from: Vector3, to: Vector3): boolean
	local interior: Instance? = h.s.interior
	local shell = if interior and interior.Parent then interior:FindFirstChild("Shell") else nil
	if not shell or not insideAt(h, from) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { shell }
	return workspace:Raycast(from, to - from, params) ~= nil
end

-- Can he take the piece now: in its world, within Pick.Arm studs of its footprint (in its own frame; a piece out of the
-- house or no grid: its middle within half its size and PickReach, as before), the ray from his chest to its middle
-- through none of the interior's walls.
local function canTake(h: Helper, body: Body, item: any, thing: Rules.Thing): boolean
	local here = body.root.Position
	local at: Vector3 = item.root.Position
	if insideAt(h, here) ~= insideAt(h, at) then
		return false
	end
	local rel = (item.root.CFrame :: CFrame):PointToObjectSpace(here)
	local dx = math.max(math.abs(rel.X) - thing.size.X / 2, 0)
	local dz = math.max(math.abs(rel.Z) - thing.size.Z / 2, 0)
	local near = math.sqrt(dx * dx + dz * dz) <= cfg.Pick.Arm
	if not near and (not h.route or not insideAt(h, at)) then
		near = flat(here, at) <= math.max(thing.size.X, thing.size.Z) / 2 + cfg.PickReach
	end
	return near and not wallBetween(h, here + Vector3.new(0, 1, 0), at)
end

-- One frame of a piece's glide (pick: up into his hands, `to` his hold in his root's frame; put: down to the floor,
-- `to` in the world), eased over Pick.Lift s. True once it is there.
local function glide(body: Body, handle: Handle, clock: number): boolean
	local root, from, to = handle.root, handle.from, handle.to
	if not root or not from or not to or not root.Parent then
		return true
	end
	local u = (clock - handle.at) / math.max(cfg.Pick.Lift, 0.05)
	local goal = if handle.kind == "pick" then body.root.CFrame * to else to
	root.CFrame = from:Lerp(goal, ease(u))
	return u >= 1
end

-- The glide every frame while a piece glides (his steps are Tick apart: it would jump), his hands on it (poseHands:
-- CarryAt its real place); the hook gone again once none does.
local handHook: RBXScriptConnection? = nil
local function handFrames()
	local busy = false
	for _, h in helpers do
		local handle = h.handle
		if handle and handle.root then
			busy = true
			break
		end
	end
	if busy and not handHook then
		handHook = game:GetService("RunService").Heartbeat:Connect(function()
			local clock = os.clock()
			for _, h in helpers do
				local body, handle = h.body, h.handle
				if body and handle and handle.root then
					pcall(glide :: any, body, handle, clock)
					pcall(poseHands :: any, h, body, handle.spot, "carrier")
				end
			end
		end)
	elseif not busy and handHook then
		handHook:Disconnect()
		handHook = nil
	end
end

-- His pick-up or setting down over (done, or broken off: his fall, the move's end, an order): a gliding piece where it
-- was going (in his hands; a put's on the floor), its weld on again; a put's piece set down then (Moving.helperDrop:
-- `why`, else the put's own) and back on his list when it was to be.
local function endHandle(h: Helper, body: Body?, why: string?)
	local handle = h.handle
	if not handle then
		return
	end
	h.handle = nil
	local root, weld, to = handle.root, handle.weld, handle.to
	local held = Rules.holding(h.s.move, h.id) == handle.spot -- (set down or knocked out of his hands meanwhile: left alone)
	if held and root and to and root.Parent then
		if handle.kind == "pick" and body then
			root.CFrame = body.root.CFrame * to
		elseif handle.kind == "put" then
			root.CFrame = to
		end
	end
	if held and weld and weld.Parent then
		weld.Enabled = true
	end
	if held and root and root.Parent then
		root.Anchored = false
	end
	if handle.kind == "put" and body then
		if held then
			h.port.helperDrop(h.s, body.model, why or handle.why)
		end
		if handle.requeue then
			requeue(h, handle.spot)
		end
		poseHands(h, body, nil, nil)
	elseif handle.kind == "pick" and handle.phase ~= "lift" and body then
		poseHands(h, body, nil, nil) -- (broken off before it was his: the hands down)
	end
	h.thinkAt = 0
	handFrames()
end

-- He sets the piece in his arms down where he stands (his pick-up the other way): it glides from his hands down to the
-- floor in front of him as he bends ("setdown"), then Moving.helperDrop(`why`); `again`: back on his list after. Not his
-- alone (the other end of yours) or busy: set down at once, as before.
local function startPut(h: Helper, body: Body, why: string, again: boolean?)
	local s = h.s
	local spot, role = Rules.holding(s.move, h.id)
	local item = if spot then s.items[spot] else nil
	local thing = if spot then (s.move :: Rules.Move).things[spot] else nil
	if not spot or role ~= "carrier" or not item or not thing or h.handle then
		h.port.helperDrop(s, body.model, why)
		if again then
			requeue(h, spot)
		end
		return
	end
	mover.halt(body)
	local from: CFrame = item.root.CFrame
	local _, yaw = from:ToOrientation()
	local floor = floorAt(h, from.Position)
	local to = CFrame.new(from.Position.X, floor + thing.size.Y / 2, from.Position.Z) * CFrame.Angles(0, yaw, 0)
	local weld = weldOf(item, body.root)
	if weld then
		weld.Enabled = false
		item.root.Anchored = true
	end
	h.handle = { kind = "put", spot = spot, phase = "down", at = os.clock(), root = if weld then item.root else nil, weld = weld, from = from, to = to,
		why = why, requeue = again == true }
	Npcs.act(body.model, "setdown")
	handFrames()
end

-- His pick-up begins at the piece (beside it, within his arm, no wall between): he stops and turns to it (Npcs.face).
local function startPick(h: Helper, body: Body, spot: number, clock: number)
	local item = h.s.items[spot]
	mover.halt(body)
	h.handle = { kind = "pick", spot = spot, phase = "turn", at = clock, root = nil, weld = nil, from = nil, to = nil, why = "put", requeue = false }
	if item then
		Npcs.face(body.model, item.root.Position, cfg.Pick.Turn) -- (9.3 turned in Pick.Turn s: the bend starts as he faces it)
	end
end

-- One step of his pick-up or setting down (nothing else for him meanwhile): turned to it (Pick.Turn s; still his to take,
-- else broken off: a try), the bend and both hands on it (Npcs.act "lift", Pick.Bend s), then his (Moving.helperTake),
-- off his list, and up it glides into his hands (Pick.Lift s); a put's glide down, then set down (endHandle).
local function stepHandle(h: Helper, body: Body, clock: number)
	local handle = h.handle :: Handle
	local s = h.s
	local spot = handle.spot
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or not item.root.Parent then
		endHandle(h, body)
		return
	end
	local elapsed = clock - handle.at
	if handle.phase == "turn" then
		if elapsed < cfg.Pick.Turn then
			return
		end
		if (thing.state ~= "home" and thing.state ~= "ground") or thing.carrier ~= nil or thing.helper ~= nil or not canTake(h, body, item, thing) then
			h.tries[spot] = (h.tries[spot] or 0) + 1 -- (taken meanwhile, or out of his reach after all: his spot again)
			h.stand = nil
			endHandle(h, body)
			return
		end
		handle.phase, handle.at = "bend", clock
		Npcs.act(body.model, "lift")
		poseHands(h, body, spot, "carrier") -- (both hands on it where it stands)
		return
	elseif handle.phase == "bend" then
		poseHands(h, body, spot, "carrier")
		if elapsed < cfg.Pick.Bend then
			return
		end
		local from: CFrame = item.root.CFrame
		local ok = h.port.helperTake(s, spot, body.model) -- (refused: it can't be his after all; off his list either way)
		unqueue(h, spot)
		refreshMarks(h)
		h.pick, h.stand, h.tries[spot] = nil, nil, nil
		h.waited, h.dropping, h.thinkAt = 0, false, 0
		if not ok then
			endHandle(h, body)
			return
		end
		handle.to = body.root.CFrame:ToObjectSpace(item.root.CFrame) -- (his hold, as Moving welded it)
		local weld = weldOf(item, body.root)
		if weld then
			weld.Enabled = false
			item.root.Anchored = true
			item.root.CFrame = from
			handle.root, handle.weld, handle.from = item.root, weld, from
		end
		handle.phase, handle.at = "lift", clock
		h.action, h.spot = "deliver", spot
		setDoing(h, "deliver", spot) -- (his now: "Carrying" as it comes up)
		handFrames()
		return
	end
	-- "lift" (up into his hands) and "down" (a put: down to the floor)
	local done = glide(body, handle, clock)
	poseHands(h, body, spot, "carrier")
	if done then
		endHandle(h, body)
	end
end

local function spawnBody(h: Helper, at: Vector3): boolean
	local look = Crew.look(h.kind) -- 10.1 his kind's look and name tag
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
	model.Name = h.name
	model:SetAttribute("MoveHelper", h.id)
	model:SetAttribute("Busy", true) -- (Npcs' greeting leaves him alone)
	Crew.dress(h, model) -- 10.1 (CrewKind, CrewSolo: the map's, Moving's)
	local health = Crew.health(h)
	humanoid.MaxHealth = health
	humanoid.Health = health
	h.health = health
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
	placeAt(h, at, nil, "spawn")
	return true
end

local function removeBody(h: Helper)
	for _, hook in h.hooks do
		hook:Disconnect()
	end
	table.clear(h.hooks)
	local body = h.body
	h.crossing = nil -- (9.3 his walk through a door with his body: the piece in his hands its own look again)
	Walking.unfade(body)
	endHandle(h, body) -- (9.0 a pick-up or a put down done at once)
	ungrip(h, body) -- (7.x the attachment on the piece goes too)
	h.body = nil
	if body then
		Npcs.remove(body.model)
	end
	clearPath(h)
end
-- Down: what he holds falls, he lies on his back (10.1: down in the run, the revive prompt on him:
-- server/HelperCrew.luau).
-- Down: what he holds falls, he lies on his back; his body goes FALL s later, he is back Respawn s later.
local function fall(h: Helper, body: Body, clock: number)
	Walking.crossOff(h, body) -- 9.3 (in sight where he falls)
	endHandle(h, body, "died") -- 9.0 (a piece going down with him: knocked)
	endCall(h, "down", clock) -- 8.3
	endNeeds(h)
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
	Walking.pivot(h, body, CFrame.new(at) * CFrame.Angles(-math.pi / 2, 0, 0), "down")
	tell(h, Crew.fallText(h) or `🧑‍🔧 {h.name} is down!`) -- (10.1 a run's: revive or out)
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

-- 9.0 studs on foot inside the house from `a` to `b` along his grid's way (math.huge: none), nil without a grid.
local function insideCost(h: Helper, a: Vector3, b: Vector3): number?
	local grid = h.route
	if not grid then
		return nil
	end
	local origin: CFrame = h.s.origin
	local pa, pb = origin:PointToObjectSpace(a), origin:PointToObjectSpace(b)
	local points = Route.path(grid, pa.X, pa.Z, pb.X, pb.Z)
	if not points then
		return math.huge
	end
	local total, x, z = 0, pa.X, pa.Z
	for _, point in points do
		total += math.sqrt((point.x - x) ^ 2 + (point.z - z) ^ 2)
		x, z = point.x, point.z
	end
	return total
end

-- 7.x farm move: the best way from `here` (inside or not) to `goal` in the other world, among those he may take. 9.0 in
-- a house with a grid its inside part is his way's own length (insideCost: through the doorways, round the walls; the
-- straight line had him turn back to the far door once his walk round a wall began), worked out once for a goal
-- (wayPicks: the pieces as they stand, the ways he may take; a few goals kept) and kept: no change of mind on the way.
local function wayFor(h: Helper, here: Vector3, inside: boolean, goal: Vector3): Way
	if #h.ways < 2 then
		return h.ways[1]
	end
	local allowed = allowedWays(h)
	if not h.route then
		local _, which = Brain.routeVia(inside, here.X, here.Z, not inside, goal.X, goal.Z, h.wayDoors, allowed)
		return h.ways[which] or h.ways[1]
	end
	local may = if allowed then table.concat(allowed, ",") else "*"
	for _, pick in h.wayPicks do
		if pick.inside == inside and pick.key == h.routeKey and pick.may == may and flat(pick.goal, goal) <= cfg.PathAgain then
			return h.ways[pick.which] or h.ways[1]
		end
	end
	local best, which = math.huge, 1
	for index, way in h.ways do
		if allowed and not table.find(allowed, index) then
			continue
		end
		local cost = if inside then (insideCost(h, here, way.exitIn) or 0) + flat(way.outside.Position, goal)
			else flat(here, way.outside.Position) + (insideCost(h, way.entryIn.Position, goal) or 0)
		if cost < best then
			best, which = cost, index
		end
	end
	table.insert(h.wayPicks, 1, { goal = goal, inside = inside, key = h.routeKey, may = may, which = which })
	h.wayPicks[5] = nil -- (the last four goals)
	return h.ways[which] or h.ways[1]
end

-- Through the front door, to where the players come out or in (7.x farm move: through `way`, the front door's when
-- nil). 8.1 walk-in doors (the players' rule, Config.Moving.Doors): he comes out facing away from the door and out of
-- its reach (DoorReach: inside 1.5 past the entry, outside beside the players' spot), and goes through a door again only
-- Rearm s later (go): no ping-pong. 9.3 never a pop in sight: he walked into the doorway fading out (crossStart), here he
-- fades in (crossEnd) and walks on.
local function transfer(h: Helper, inside: boolean, clock: number, way: Way?)
	h.doorAt = clock
	local through = way or h.ways[1]
	if inside then
		placeAt(h, through.entryIn.Position + through.entryIn.LookVector * 1.5, through.entryIn.LookVector, "door")
	else
		local out: CFrame = through.outside
		local right = Vector3.new(-out.LookVector.Z, 0, out.LookVector.X)
		placeAt(h, besideVan(h, out.Position + right * (cfg.DoorReach + 0.5)), out.LookVector, "door") -- (8.5.1 never in the van)
	end
end

-- 9.3 through a door as the players walk through theirs (Config.Moving.Doors; the owner: "he just pops in or out"):
-- from DoorReach he walks on into its doorway (Walk.DoorIn past its foot) while he fades out (FadeOut s; crossEnd
-- FadeOut + Margin s later: transfer, then he fades in over FadeIn s, walking on).
function Walking.crossStart(h: Helper, body: Body, way: Way, inside: boolean, clock: number)
	local at = if inside then way.door - way.outside.LookVector * cfg.Walk.DoorIn else way.exitIn - way.entryIn.LookVector * cfg.Walk.DoorIn
	h.crossing = { way = way, inside = inside, at = clock, through = Vector3.new(at.X, body.root.Position.Y, at.Z) }
	local fade = mover.fade
	if fade then
		local spot, role = Rules.holding(h.s.move, h.id)
		local item = if spot and role == "carrier" then h.s.items[spot] else nil
		fade(body, true, Config.Moving.Doors.FadeOut, if item then item.model else nil) -- (the piece in his hands with him)
	end
end

function Walking.crossEnd(h: Helper, body: Body, clock: number)
	local c = h.crossing
	if not c then
		return
	end
	h.crossing = nil
	transfer(h, c.inside, clock, c.way)
	local fade = mover.fade
	if fade then
		fade(body, false, Config.Moving.Doors.FadeIn)
	end
end

-- (a walk through a door broken off: his fall, the move's end: in sight again where he is)
function Walking.crossOff(h: Helper, body: Body?)
	if h.crossing then
		h.crossing = nil
		Walking.unfade(body)
		local fade = mover.fade
		if body and fade then
			fade(body, false, 0.1)
		end
	end
end

-- ── 9.0 His way inside the house (shared/HouseRoute.luau) ─────────────────

-- A world point in the plan's frame (its origin's: X and Z along the floor), and back at height `y`.
local function planAt(h: Helper, at: Vector3): (number, number)
	local p = (h.s.origin :: CFrame):PointToObjectSpace(at)
	return p.X, p.Z
end

local function worldAt(h: Helper, x: number, z: number, y: number): Vector3
	local p = (h.s.origin :: CFrame) * Vector3.new(x, 0, z)
	return Vector3.new(p.X, y, p.Z)
end

-- A piece's footprint in the plan's frame (its box turned as it stands: the rect round it).
local function footprintOf(h: Helper, item: any, thing: Rules.Thing): Route.Rect
	local frame = (h.s.origin :: CFrame):ToObjectSpace(item.root.CFrame)
	local _, yaw = frame:ToOrientation()
	return Route.footprint(frame.Position.X, frame.Position.Z, thing.size.X, thing.size.Z, yaw)
end

-- His grid with the pieces standing in the house now (at home, or set down in it): blocked again only when one of them
-- went or moved (routeKey; think's every Think s, an assignment's); nil: no grid (a plan without walls).
-- 9.3 the built interior's collidable parts in his body's height (Body.StepUp … Body.Height over its floor: a part
-- lower he steps onto, a higher one is over his head), not the pieces (Items: blocked as they stand) nor the plan's own
-- wall slabs (the Shell's Wall and Header): what the plan does not know (a garage door's leaf, a fixture's part past its
-- plan's box) closes his grid's cells too (HouseRoute.solid), once the interior stands. (Roblox: CanCollide is what
-- stops a Humanoid; his collision group passes only the cars, the zombies and the people.)
function Walking.builtSolids(h: Helper, grid: Route.Grid)
	local interior: Instance? = h.s.interior
	if h.solids or not interior or not interior.Parent then
		return
	end
	h.solids = true
	local origin: CFrame = h.s.origin
	local body = cfg.Body
	local items = interior:FindFirstChild("Items")
	local shell = interior:FindFirstChild("Shell")
	local gx0, gz0 = grid.x0 - grid.step, grid.z0 - grid.step
	local gx1, gz1 = grid.x0 + grid.nx * grid.step, grid.z0 + grid.nz * grid.step
	local rects: { Route.Rect } = {}
	for _, d in interior:GetDescendants() do
		if not d:IsA("BasePart") or not d.CanCollide or (items and d:IsDescendantOf(items))
			or (d.Parent == shell and (d.Name == "Wall" or d.Name == "Header")) then
			continue
		end
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = origin:ToObjectSpace(d.CFrame):GetComponents()
		local size = d.Size
		local ex = (math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2
		local ey = (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
		local ez = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
		if y + ey <= body.StepUp or y - ey >= body.Height or x + ex < gx0 or x - ex > gx1 or z + ez < gz0 or z - ez > gz1 then
			continue
		end
		table.insert(rects, { x0 = x - ex, z0 = z - ez, x1 = x + ex, z1 = z + ez })
	end
	Route.solid(grid, rects)
	h.routeKey = "" -- (the pieces blocked again on the cells as they are now)
end

local function routeNow(h: Helper): Route.Grid?
	local grid = h.route
	if not grid then
		return nil
	end
	Walking.builtSolids(h, grid) -- 9.3
	local s = h.s
	local move: Rules.Move = s.move
	local list: { Route.Rect } = {}
	local parts: { string } = {}
	for _, spot in move.order do
		local thing = move.things[spot]
		local item = s.items[spot]
		if thing and item and item.root.Parent and (thing.state == "home" or thing.state == "ground") and insideAt(h, item.root.Position) then
			local r = footprintOf(h, item, thing)
			table.insert(list, r)
			table.insert(parts, `{spot}:{math.floor(r.x0 * 4 + 0.5)},{math.floor(r.z0 * 4 + 0.5)},{math.floor(r.x1 * 4 + 0.5)},{math.floor(r.z1 * 4 + 0.5)}`)
		end
	end
	local danger = s.danger -- 10.x danger: a run's locked doorways are walls until opened, its hazards he walks round
	if danger then
		Route.shut(grid, danger.route.walls, danger.route.floors, danger.route.key) -- (server/RunDanger.luau's)
		table.insert(parts, danger.route.key) -- (shut anew: his way worked out again)
	end
	local key = table.concat(parts, ";")
	if key ~= h.routeKey then
		h.routeKey = key
		Route.block(grid, list)
	end
	return grid
end

-- The point he is aimed at on his way to `target`, both inside, and the way's studs left: the grid's way (worked out
-- again when the target moved PathAgain studs off its end, the pieces changed or a stuck spell asks: Route.Again s apart
-- at most). 9.3 aimed along it (HouseRoute.ahead): the farthest point within `reach` studs of walking whose straight
-- line from him keeps Walk.Clear studs off every wall, fixture and piece (8.9's turn a stud before each corner cut it into
-- the wall's end there). No way: where he stands (never a straight line into a wall; pathFailedAt says so).
local function routeTo(h: Helper, grid: Route.Grid, here: Vector3, target: Vector3, clock: number, reach: number): (Vector3, number)
	local goal = h.pathGoal
	local fresh = h.pathInside and goal ~= nil and h.pathKey == h.routeKey and flat(goal, target) <= cfg.PathAgain
	if not fresh and (not h.pathInside or clock - h.pathAt >= cfg.Route.Again) then
		table.clear(h.path)
		table.clear(h.pathXZ)
		h.pathAt, h.pathInside, h.pathKey, h.pathIndex = clock, true, h.routeKey, 1
		local fx, fz = planAt(h, here)
		local tx, tz = planAt(h, target)
		-- (a goal off the open cells, in a wall or a piece: the far end of your piece against a wall, its nearest open
		-- cell within CallClose all the same: as near as he gets, the hold walks him the rest)
		local points = Route.path(grid, fx, fz, tx, tz) or Route.path(grid, fx, fz, tx, tz, cfg.CallClose)
		if points then
			for index, p in points do
				h.path[index] = worldAt(h, p.x, p.z, here.Y)
				h.pathXZ[index] = p
			end
			h.pathGoal, h.pathFresh = target, true
		else
			h.pathGoal, h.pathFailedAt = nil, clock
		end
	end
	if #h.pathXZ == 0 then
		return here, flat(here, target)
	end
	local fx, fz = planAt(h, here)
	local ax, az, index, left = Route.ahead(grid, h.pathXZ, h.pathIndex, fx, fz, reach, cfg.Walk.Clear)
	h.pathIndex = index
	return worldAt(h, ax, az, here.Y), left
end

-- ── The way ────────────────────────────────────────────────────────────────

-- The point he is aimed at toward `target` and the way's studs left: his path's (worked out again at most every Repath
-- s, in the background, when the target moved off it, or at once when asked: a stuck spell), else straight. 9.0 inside
-- the house (both inside): the plan's grid's (routeTo), never straight. 9.3 aimed `reach` studs along it (HouseRoute.ahead:
-- its corners cut Walk.Cut studs at most), never stopping at its corners.
local function wayTo(h: Helper, body: Body, here: Vector3, target: Vector3, clock: number, reach: number): (Vector3, number)
	local grid = h.route
	if grid and insideAt(h, here) and insideAt(h, target) then
		return routeTo(h, grid, here, target, clock, reach) -- 9.0
	elseif h.pathInside then
		clearPath(h) -- (9.0 a way inside, not this one)
	end
	local route = mover.route
	local goal = h.pathGoal
	if route and not h.pathing and clock - h.pathAt >= cfg.Repath and (goal == nil or flat(goal, target) > cfg.PathAgain) then
		h.pathAt, h.pathing = clock, true
		task.spawn(function()
			local ok, points = pcall(route, body, here, target)
			h.pathing = false
			if h.body ~= body or h.pathInside then
				return -- (9.0 inside since: the grid's way is his)
			end
			table.clear(h.path)
			table.clear(h.pathXZ)
			if ok and points then
				for index, point in points do
					h.path[index] = point
					h.pathXZ[index] = { x = point.X, z = point.Z }
				end
				h.pathIndex, h.pathGoal, h.pathFresh = math.min(2, #points), target, true
			else
				h.pathGoal = nil
				h.pathFailedAt = clock
			end
		end)
	end
	goal = h.pathGoal
	local path = h.path
	if goal and flat(goal, target) <= cfg.PathDrift and #path > 0 and #h.pathXZ == #path then -- (8.3: on along it while the new one is worked out)
		local ax, az, index, left = Route.ahead(nil, h.pathXZ, h.pathIndex, here.X, here.Z, reach, 0, cfg.Walk.Cut)
		h.pathIndex = index
		return Vector3.new(ax, here.Y, az), left + flat(path[#path], target)
	end
	return target, flat(here, target)
end

-- 9.3 could a player see a jump of his from `a` to `b` (one within Walk.Seen studs of either)?
function Walking.seen(a: Vector3, b: Vector3): boolean
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and ((root.Position - a).Magnitude <= cfg.Walk.Seen or (root.Position - b).Magnitude <= cfg.Walk.Seen) then
			return true
		end
	end
	return false
end

-- 9.3 is the straight line from `a` to `b` his to walk: inside the house no nearer to a wall, a fixture or a piece than
-- Walk.Clear (or than he is now: out of a corner, never deeper in); outside, yes.
function Walking.walkable(h: Helper, a: Vector3, b: Vector3): boolean
	local grid = h.route
	if not grid or not insideAt(h, a) then
		return true
	end
	local ax, az = planAt(h, a)
	local bx, bz = planAt(h, b)
	return Route.free(grid, ax, az, bx, bz, math.min(cfg.Walk.Clear, Route.gap(grid, ax, az, ax, az) - 1e-3))
end

-- 9.3 a stuck spell's way out, walked: back Unstuck.BackStep studs (or half) from where he is aimed (`side` nil), or
-- Unstuck.SideStep studs across his way (`side` ±1, the other side when that one has no room) onto open ground (inside:
-- the grid's nearest open cell there); nil: no room.
function Walking.wayOut(h: Helper, body: Body, here: Vector3, aim: Vector3, side: number?): Vector3?
	local way = Vector3.new(aim.X - here.X, 0, aim.Z - here.Z)
	if way.Magnitude < 0.05 then
		local look = body.root.CFrame.LookVector
		way = Vector3.new(look.X, 0, look.Z)
	end
	if way.Magnitude < 0.05 then
		return nil
	end
	local u = cfg.Unstuck
	local tries: { Vector3 }
	if side then
		local across = Vector3.new(-way.Z, 0, way.X).Unit
		tries = { here + across * (side * u.SideStep), here - across * (side * u.SideStep) }
	else
		tries = { here - way.Unit * u.BackStep, here - way.Unit * (u.BackStep / 2) }
	end
	local grid = h.route
	for _, to in tries do
		if side and grid and insideAt(h, here) then
			local px, pz = planAt(h, to)
			local sx, sz = Route.snap(grid, px, pz, u.SideStep / 2)
			if sx and sz then
				to = worldAt(h, sx, sz, here.Y)
			end
		end
		if flat(to, here) > 0.3 and Walking.walkable(h, here, to) then
			return to
		end
	end
	return nil
end

-- 9.3 the last resort (Unstuck.Fade s without progress): he fades over onto his way Unstuck.Rescue studs on (inside:
-- onto an open cell of it), never the pop on the spot of 8.9.
function Walking.rescue(h: Helper, body: Body, here: Vector3, target: Vector3)
	local to = target
	local inside = insideAt(h, here)
	local grid = if inside then h.route else nil
	if #h.pathXZ > 0 and h.pathInside == inside then
		local fx, fz = here.X, here.Z
		if h.pathInside then
			fx, fz = planAt(h, here)
		end
		local ax, az = Route.ahead(nil, h.pathXZ, h.pathIndex, fx, fz, cfg.Unstuck.Rescue, 0)
		if grid then
			local sx, sz = Route.snap(grid, ax, az)
			if sx and sz then
				ax, az = sx, sz
			end
		end
		to = if h.pathInside then worldAt(h, ax, az, here.Y) else Vector3.new(ax, here.Y, az)
	end
	local face = Vector3.new(to.X - here.X, 0, to.Z - here.Z)
	placeAt(h, to, if face.Magnitude > 0.05 then face else nil, "stuck")
	local appear = mover.appear
	if appear then
		appear(body)
	end
end

-- 9.3 Studio's stuck line: the part his walk runs into (a ray along it at his chest, his knees, his head; only parts he
-- collides with: his collision group), by its full name.
function Walking.blockedBy(body: Body, here: Vector3, aim: Vector3): string
	local way = Vector3.new(aim.X - here.X, 0, aim.Z - here.Z)
	if way.Magnitude < 0.05 then
		local look = body.root.CFrame.LookVector
		way = Vector3.new(look.X, 0, look.Z)
	end
	if way.Magnitude < 0.05 then
		return "nothing (he faces no way)"
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { body.model }
	params.RespectCanCollide = true
	params.CollisionGroup = body.root.CollisionGroup
	for _, lift in { 0, -1.6, 1.6 } do
		local hit = workspace:Raycast(here + Vector3.new(0, lift, 0), way.Unit * 3, params)
		if hit then
			return hit.Instance:GetFullName()
		end
	end
	return "nothing within 3 studs of his walk"
end

-- Toward `goal` (inside the interior or in the street: `goalInside`): to the front door first when it is in the other
-- world (9.3 walked through it fading: crossStart), then by the way; far off (Far), he appears at the next point (8.3
-- `walk`: never, your call's walk and Gus's; 9.3 nor in a player's sight: Walk.Seen, faded in). True: there (within
-- near; 9.3 or settled within Walk.Arrive more: MoveHelperBrain.arrived). 8.5.1 outside, the move's van's outline
-- (aroundVan, outOfVan): never a way across it, never left inside it. 9.3 his walk aimed along his way (wayTo), slowing
-- into his goal (MoveHelperBrain.ease); stuck (MoveHelperBrain.progress / unstuck): a new way, then his ways out walked
-- (back, aside: wayOut), the fade over only as the last resort (rescue).
local function go(h: Helper, body: Body, goal: Vector3, goalInside: boolean, near: number, speed: number, dt: number, clock: number, walk: boolean?): boolean
	speed *= Brain.trained(h.s.owner) * Crew.pace(h) -- 8.1 SANDBOX: Danny's training (the owner's upgrade, server/Upgrades.luau); 10.1 his kind's
	local here = body.root.Position
	local inside = insideAt(h, here)
	local crossing = h.crossing
	if crossing then -- 9.3 on into the doorway, fading out; then its other side
		local D = Config.Moving.Doors
		if clock - crossing.at >= D.FadeOut + D.Margin then
			Walking.crossEnd(h, body, clock)
		else
			mover.move(body, crossing.through, speed, dt)
		end
		return false
	end
	local target = goal
	local same = inside == goalInside
	if not same then
		local way = wayFor(h, here, inside, goal) -- (7.x farm move: the nearest way he may take)
		local door = if inside then way.exitIn else way.outside.Position
		if flat(here, door) <= cfg.DoorReach and clock - h.doorAt > Config.Moving.Doors.Rearm then -- (8.1 walk-in doors)
			Walking.crossStart(h, body, way, not inside, clock)
			mover.move(body, (h.crossing :: Crossing).through, speed, dt)
			return false
		end
		target = door
	elseif flat(here, goal) <= near then
		mover.halt(body)
		Walking.unstick(h)
		return true
	end
	local van = if inside then nil else truckOf(h.s) -- 8.5.1
	if van and outOfVan(h, body, van, target) then
		return false
	end
	local grid = if inside then h.route else nil -- 9.0 inside the house: the plan's grid
	if flat(here, target) > cfg.Far and not walk then
		local put = target
		if grid and insideAt(h, target) then
			local fx, fz = planAt(h, target)
			local sx, sz = Route.snap(grid, fx, fz)
			if sx and sz then
				put = worldAt(h, sx, sz, target.Y) -- (9.0 inside: on an open cell, never in a wall or a piece)
			end
		end
		if not Walking.seen(here, put) then -- 9.3 (in a player's sight he walks)
			placeAt(h, put, nil, "far")
			local appear = mover.appear
			if appear then
				appear(body)
			end
			return false
		end
	end
	local w = cfg.Walk
	local aim, left = wayTo(h, body, here, target, clock, math.clamp(speed * w.Lead, w.Ahead, w.AheadMost))
	-- 9.3 his progress along his way (a new goal: a new clock; a new way: its own length the best)
	local was = h.progressGoal
	local newGoal = was == nil or flat(was, target) > cfg.PathAgain
	if newGoal or h.pathFresh then
		if newGoal then
			h.stuckFor, h.phase, h.phaseRound, h.recover = 0, "walk", 0, nil
		end
		h.pathFresh, h.progressGoal = false, target
		Brain.rebase(h.progress, left, h.stuckFor >= cfg.Unstuck.Repath)
	end
	h.stuckFor = Brain.progress(h.progress, left, dt, h.stuckFor)
	if same and Brain.arrived(flat(here, goal), near, h.stuckFor) then
		mover.halt(body)
		Walking.unstick(h)
		return true
	end
	-- 9.3 stuck: a new way, then his ways out walked; at his way's end (as near as it gets: your piece's far end against a
	-- wall) he waits there, a new way each round
	local phase, round = Brain.unstuck(h.stuckFor)
	if phase ~= h.phase or round ~= h.phaseRound then
		local atEnd = left <= 0.3
		h.phase, h.phaseRound, h.recover = phase, round, nil
		if phase == "repath" then
			h.pathAt, h.pathGoal = -math.huge, nil -- (a new way from where he stands, at once)
		elseif phase == "back" and not atEnd then
			h.recover = Walking.wayOut(h, body, here, aim, nil)
		elseif phase == "side" and not atEnd then
			h.recover = Walking.wayOut(h, body, here, aim, if round % 2 == 0 then 1 else -1)
		elseif phase == "rescue" and not atEnd and not walk then -- (your call's walk: its own last resort)
			Walking.rescue(h, body, here, target)
			return false
		end
	end
	if diagnostics.on and h.stuckFor >= cfg.Diag.Stuck and clock - (h.diagAt.stuck or -math.huge) >= cfg.Diag.Every then
		Walking.report(h, "stuck", string.format("stuck %.1fs at %s going to %s, blocked by %s", h.stuckFor, Walking.spot3(here), Walking.spot3(target), Walking.blockedBy(body, here, aim)), clock)
	end
	local recover = h.recover
	if recover then
		if flat(here, recover) > 0.3 then
			mover.move(body, recover, speed * cfg.Unstuck.Pace, dt)
			return false
		end
		h.recover = nil
		h.pathAt, h.pathGoal = -math.huge, nil -- (on from here: a new way)
	end
	if van then
		aim = aroundVan(van, here, aim, target) -- 8.5.1
	end
	mover.move(body, aim, if same then speed * Brain.ease(left) else speed, dt)
	return false
end

-- ── Choosing (every Think s) ───────────────────────────────────────────────

local function think(h: Helper, body: Body, clock: number)
	h.thinkAt = clock + cfg.Think
	routeNow(h) -- 9.0 (the pieces standing in the house: his grid blocked again when one went or moved)
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
	-- a crew player's two-person piece dragged alone (he comes to its far end; 10.1 a kind that lifts with you)
	table.clear(h.lifts)
	if Crew.lifts(h) then
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
		q.spot, q.class, q.fits = spot, Crew.classFor(h, move.things[spot].class), fits -- (10.1 Bruno's piece for two: his own)
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
	if not cfg.OpenBack or not truck or Vehicles.backOpen(truck) or not Vehicles.backPrompt(truck) or not truckAtHouse(s, truck) then
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
	if not Vehicles.backOpen(truck) then
		return false
	end
	return (h.port.helperLoad(h.s, body.model))
end

-- 8.3 his own piece out of his arms (your call, your lift come first): into the van right here, else set down where
-- he is, back at the head of his list (9.0 his put down: startPut).
local function setDownOwn(h: Helper, body: Body)
	if loadHere(h, body) then
		return
	end
	startPut(h, body, "put", true)
end

-- 8.6 his end of the piece in `frame` (the owner: "he teleports from side to side"): the face across it from
-- `carrierRoot` (MoveHelperBrain.holdEnd; none: its old far face, -Z), Standoff past it: its axis × studs out of the
-- middle, in the piece's own frame. A hold decides it once as it starts (h.holdEnd) and keeps it.
local function endIn(thing: Rules.Thing, frame: CFrame, carrierRoot: BasePart?): Vector3
	local from = if carrierRoot then frame:PointToObjectSpace(carrierRoot.Position) else Vector3.new(0, 0, 1)
	local ax, az, half = Brain.holdEnd(thing.size.X, thing.size.Z, from.X, from.Z)
	return Vector3.new(ax, 0, az) * Brain.farEnd(half * 2)
end

-- 7.x his place at the far end of your piece, in its frame: Standoff past its far face, turned to you, on the floor
-- under it (within HoldStep of the floor under you). 8.3: that floor from a ray down from your root (your jump never
-- lifts him), his end's from a step over it to a step under it (MoveHelperBrain.endRise: a floor farther off is not
-- his); holding it (`trail`), his height follows it at HoldClimb studs a second at most (MoveHelperBrain.holdClimb: at
-- once on a new hold and through a door's fade). 8.6: his end (`ends`: the hold's, endIn's; else across from you now).
local function endOffset(h: Helper, body: Body, thing: Rules.Thing, anchor: BasePart, carrierRoot: BasePart?, trail: Brain.Trail?, dt: number?, ends: Vector3?): CFrame
	local frame = anchor.CFrame
	local out = ends or endIn(thing, frame, carrierRoot)
	local far = frame * out
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
	local reach = out.Magnitude
	return PairHold.endOffset(out.X / reach, out.Z / reach, reach, rise)
end

-- 7.x kept at `offset` in the piece's frame (the mover's constraints; 8.1 at `limit` studs / s at most, put there only
-- on `snap`; a test's mover without them: his root stepped there, limit × dt at most; 9.2 `driver`: the leader whose
-- client drives the constraints, the mover's keep).
local function keepAt(body: Body, anchor: BasePart, offset: CFrame, dt: number, limit: number, snap: boolean, driver: Player?)
	local keep = mover.keep
	if keep then
		keep(body, anchor, offset, dt, limit, snap, driver)
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
-- the walk played in reverse backwards); none across a door's fade (9.2: nor across a jump of more than HoldPace.Jump
-- studs: the leader's client put him there before the server saw the fade). (Near players the clients' gait poses his
-- legs from the same velocity: Npcs.carried's Physics state.)
local function strideOf(h: Helper, body: Body, dt: number, snap: boolean)
	local here = body.root.Position
	local last = h.holdAt
	h.holdAt = here
	if snap or not last or dt <= 0 or (here - last).Magnitude > cfg.HoldPace.Jump then -- (9.2 or put there by the leader's client)
		Npcs.stride(body.model, 0)
		return
	end
	local look = body.root.CFrame.LookVector
	local vx, vz = (here.X - last.X) / dt, (here.Z - last.Z) / dt
	Npcs.stride(body.model, Brain.holdLegs(h.trail, vx * look.X + vz * look.Z, vz * look.X - vx * look.Z, dt))
end

-- 9.0 (the owner: "When I want to walk forwards, Danny can't walk backwards"; walking backwards with your piece he goes
-- first, into whatever is behind him): inside the house (its plan's grid, h.route) his goal from where he stands keeps
-- HoldWall.Clear studs off the wall slabs, along them, never through (HouseRoute.slide): (the goal kept, how far the
-- wall held it back, the way into that wall in the world: nil when none held it).
local function slideAlong(h: Helper, here: Vector3, goal: Vector3): (Vector3, number, Vector3?)
	local grid = h.route
	if not grid or not insideAt(h, here) or not insideAt(h, goal) then
		return goal, 0, nil
	end
	local fx, fz = planAt(h, here)
	local gx, gz = planAt(h, goal)
	local x, z, nx, nz = Route.slide(grid, fx, fz, gx, gz, cfg.HoldWall.Clear)
	local held = math.sqrt((x - gx) * (x - gx) + (z - gz) * (z - gz))
	if held < 1e-4 then
		return goal, 0, nil
	end
	local into: Vector3? = nil
	if nx ~= 0 or nz ~= 0 then
		local way = (h.s.origin :: CFrame).Rotation * Vector3.new(-nx, 0, -nz)
		into = Vector3.new(way.X, 0, way.Z).Unit
	end
	return worldAt(h, x, z, goal.Y), held, into
end

-- 9.0 his hold's bound (PairHold's hold.bound: every Heartbeat, the goal from the piece where it is now): along the
-- house's walls from where he stands (slideAlong), made once a helper.
local function boundOf(h: Helper): (Vector3, Vector3) -> Vector3
	local made = h.bound
	if made then
		return made
	end
	local fn = function(goal: Vector3, here: Vector3): Vector3
		return (slideAlong(h, here, goal))
	end
	h.bound = fn
	return fn
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
	if h.gripped ~= item.root or not h.holdEnd then
		h.trail, h.holdAt = Brain.newTrail(), nil -- (8.1 a new hold)
		h.holdEnd = endIn(thing, item.root.CFrame, carrierRoot) -- 8.6 his end, decided once: kept in the piece's frame
		h.leadOff, h.leadAway = nil, nil -- (9.2 a new carry: the leader drives it again)
	end
	local offset = endOffset(h, body, thing, item.root, carrierRoot, h.trail, dt, h.holdEnd) -- (8.3 his height: holdClimb's)
	h.holdOffset, h.gripped = offset, item.root
	-- 8.1 never put there while holding (a door's fade only: the piece in the other world); eased back when stuck behind
	local here = body.root.Position
	local crossed = insideAt(h, here) ~= insideAt(h, (item.root.CFrame * offset).Position)
	local carrier = playerOf(thing.carrier)
	-- 9.2 the leader drives his end (their client: no lag, no lead); the server only looks (MoveHelperBrain.leadKept: his
	-- body more than PairLead.Sane studs off his end for Grace s, a door's trip aside: taken back for this carry, h.leadOff)
	local driver = if cfg.PairLead.On and carrier and carrierRoot and h.leadOff ~= item.root then carrier else nil
	if driver then
		local off = (here - (item.root.CFrame * offset).Position).Magnitude
		local away, kept = Brain.leadKept(h.leadAway or 0, off, crossed, dt)
		h.leadAway = away
		if not kept then
			h.leadOff, h.leadAway, driver = item.root, nil, nil
			warn(`[MoveHelper] {h.name} {string.format("%.1f", off)} studs off his end of the piece on its leader's client: the server holds him for this carry`)
		end
	end
	-- 8.3 keeping up (the owner: "when I run, he just goes behind me"): his top speed follows your real speed (your
	-- root's, MoveHelperBrain.holdPace), and he is aimed ahead × leadTime (your screen shows his body late). 8.6 (the
	-- owner: "he teleports from side to side"): ahead along his END's own way (the piece's turn in it), the lead changing
	-- at HoldLead.Rate studs a second at most (MoveHelperBrain.endLead): your step back, a turn, an uneven look at you
	-- never throws his aim across (it was your root's velocity, taken at once)
	local from = if carrierRoot then carrierRoot.Position else nil
	local pace = Brain.holdPace(h.trail, if from then from.X else 0 / 0, if from then from.Z else 0 / 0, dt, crossed or from == nil)
	local speed = Brain.holdSpeed(PairHold.walkOf(carrier, Rules.carrySpeed(walkSpeed(), "pair", thing.weight)), pace)
	local endAt = item.root.CFrame * offset.Position
	local aim = offset
	local walls = false
	h.wallWay = nil
	if driver then
		-- 9.2 driven: his place itself (nothing late to lead: his body is where the leader's screen has it), his hands on
		-- the edge (no reach on), the walls the leader's client's
		local trail = h.trail
		trail.leadX, trail.leadZ, trail.reach, trail.endX, trail.endZ, trail.evx, trail.evz = 0, 0, 0, nil, nil, 0, 0
	else
		-- 9.0 (the owner's screenshot: Danny inside the Sofa): his lead toward the piece's middle HoldLead.In studs at
		-- most, along his end's way out of it (his body never in the piece: following you, his hands reach on instead)
		local out = item.root.CFrame.Rotation * (h.holdEnd :: Vector3)
		local outFlat = Vector3.new(out.X, 0, out.Z)
		local way = if outFlat.Magnitude > 1e-6 then outFlat.Unit else Vector3.zero
		local leadX, leadZ = Brain.endLead(h.trail, endAt.X, endAt.Z, dt, Brain.leadTime(PairHold.pingOf(carrier)), crossed or from == nil, way.X, way.Z)
		aim = if leadX == 0 and leadZ == 0 then offset
			else CFrame.new(item.root.CFrame:PointToObjectSpace(item.root.Position + Vector3.new(leadX, 0, leadZ))) * offset
		-- 9.0 inside the house along the walls, never through them (slideAlong; following you, his end goes where you
		-- went, a corner cut through a doorway's jamb as the piece itself cuts it): this step's goal, and every
		-- Heartbeat's (the hold's bound). How far a wall held it back (his lead looks ahead by the time your screen shows
		-- him late) makes h.wallWay: the way into that wall × HoldWall.Block's share, the part of your walk into it
		-- client/PairSteer.luau takes away (slowed as he nears it, stopped against it).
		local following = h.trail.evx * way.X + h.trail.evz * way.Z < -cfg.HoldLegs.From
		walls = not crossed and not following and h.route ~= nil
		if walls then
			local goal = (item.root.CFrame * aim).Position
			local along, held, into = slideAlong(h, here, goal)
			if held > 0 then
				aim = CFrame.new(item.root.CFrame:PointToObjectSpace(along)) * offset.Rotation
				if into then
					h.wallWay = into * math.clamp(held / math.max(cfg.HoldWall.Block, 0.01), 0, 1)
				end
			end
		end
	end
	local goal = (item.root.CFrame * aim).Position
	local limit, snap = Brain.holdTrack(h.trail, (goal - here).Magnitude, crossed, speed, dt)
	h.holdLimit = limit
	keepAt(body, item.root, aim, dt, limit, snap, driver)
	local grip = body.grip
	if driver and grip and PairHold.drives(grip) ~= driver then
		h.leadOff, driver = item.root, nil -- (9.2 his body could not be the leader's: the server holds him for this carry)
	end
	if grip then
		grip.bound = if walls then boundOf(h) else nil -- (9.0 the goal every Heartbeat: along the walls)
	end
	strideOf(h, body, dt, snap)
	steady(h, if carrierRoot then carrierRoot.Parent :: Model? else nil)
	-- 9.0 your side of it: his place in your root's frame (your screen: never the piece pushed into him), the wall; 9.2
	-- driven: who he is only (your client drives him: nothing late on your screen)
	local far = if carrierRoot and not crossed and not driver then carrierRoot.CFrame:PointToObjectSpace(endAt) else nil
	pairOn(h, if carrierRoot then carrierRoot.Parent :: Model? else nil, far, h.wallWay, driver ~= nil)
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
	if cfg.OpenBack and not Vehicles.backOpen(truck) and Vehicles.backPrompt(truck) then
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
		Npcs.act(body.model, "lift") -- 9.0 (his end taken up: the bend of his pick-up)
		say(h, "lift", clock, true)
		h.lineKey, h.lineAt, h.vanSaid = "three", clock + cfg.ThreeAfter, nil
	else
		h.gaveUp[spot] = clock + cfg.HelpRetry
	end
	h.thinkAt = 0
end

-- 7.x the fade-over: he is at `goal` at once (on the floor there, turned its way) and fades in. 9.3 `why`: placeAt's.
local function blink(h: Helper, body: Body, goal: CFrame, why: string)
	placeAt(h, goal.Position, goal.LookVector, why)
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
		blink(h, body, goal, "help")
		takeEnd(h, body, spot, clock)
		return
	end
	go(h, body, at, inside, 0.5, Brain.speed(walkSpeed(), "help", nil, 0), dt, clock, cfg.WaitForHelper)
end

-- ── 8.3 your call: he walks to its far end, "On three... lift!", your lift ─

-- His place at the far end of your piece as you will hold it (`frame`: Moving's helperLiftFrame), like endOffset's.
local function farEndFrom(h: Helper, body: Body, thing: Rules.Thing, frame: CFrame, carrierRoot: BasePart): CFrame
	local out = endIn(thing, frame, carrierRoot) -- (8.6 the end across from you: lengthwise, its length's far end)
	local far = frame * out
	local stand = body.humanoid.HipHeight + body.root.Size.Y / 2
	local step = cfg.HoldStep
	local at = carrierRoot.Position
	local base = floorDown(h, at, at.Y, 40) or (at.Y - stand) -- (the floor under you, as endOffset finds it)
	local found = floorDown(h, far, base + step, 2 * step + 1)
	local rise = Brain.endRise(if found then found + stand - frame.Position.Y else 0 / 0, base + stand - frame.Position.Y)
	local reach = out.Magnitude
	return frame * PairHold.endOffset(out.X / reach, out.Z / reach, reach, rise)
end

-- In place: turned to you, your grip steadied, "On three... lift!" and your lift (8.6: up at once, him at its far end:
-- joinLift, the hold turning him to you at holdTurn, never a snap; Config.MoveHelper.CallCheck: Moving opens its check,
-- him turned to you as he waits for it). Not there to lift it any more: the call is off.
local function callReady(h: Helper, body: Body, call: Call, clock: number)
	call.ready, call.readyAt = true, clock
	mover.halt(body)
	local root = rootOf(call.player)
	local here = body.root.Position
	if root then
		local look = Vector3.new(root.Position.X - here.X, 0, root.Position.Z - here.Z)
		if cfg.CallCheck and look.Magnitude > 0.05 then
			Npcs.face(body.model, root.Position, cfg.Walk.Turn) -- (9.3 a short turn, never a PivotTo)
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
		blink(h, body, goal, "call") -- (the last resort: no way there)
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
		endCall(h, "gone", clock) -- (left, down, it was taken or the hands took another)
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
-- doorways. (9.0: a piece out of the house, or a plan without walls; in a house standOf's spot.)
local function besidePiece(h: Helper, here: Vector3, at: Vector3, inside: boolean, half: number): Vector3
	local from = here
	if insideAt(h, here) ~= inside then
		local way = wayFor(h, here, not inside, at) -- (7.x farm move: the way he will come by)
		from = if inside then way.entryIn.Position else way.outside.Position
	end
	local side = Vector3.new(from.X - at.X, 0, from.Z - at.Z)
	return if side.Magnitude > 0.1 then at + side.Unit * (half + 1.5) else at
end

-- 9.0 where he goes to take the piece at `spot` (`wait`: to wait at it for you, out of the doorways when it can be): in
-- the house, the spot at arm's length on its near side his way finds (HouseRoute.reach from where he is, or from where
-- he will come in; worked out again when the pieces moved, he came in or a take there failed); nil: he can't get to it.
-- Out of the house, or no grid: beside it as before.
local function standOf(h: Helper, here: Vector3, spot: number, wait: boolean): Vector3?
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	local at: Vector3 = item.root.Position
	local inside = insideAt(h, at)
	local grid = if inside then h.route else nil
	if not grid then
		local beside = besidePiece(h, here, at, inside, math.max(thing.size.X, thing.size.Z) / 2)
		return if wait then clearOf(h, beside, inside) else beside
	end
	local from = insideAt(h, here)
	local cached = h.stand
	if cached and cached.spot == spot and cached.key == h.routeKey and cached.from == from and cached.wait == wait then
		return cached.at
	end
	local start = if from then here else wayFor(h, here, false, at).entryIn.Position
	local fx, fz = planAt(h, start)
	local piece = footprintOf(h, item, thing)
	local x, z = Route.reach(grid, fx, fz, piece, nil, if wait then h.doorZones else nil)
	if not x and wait then
		x, z = Route.reach(grid, fx, fz, piece) -- (only by a doorway: there all the same)
	end
	local stand = if x and z then worldAt(h, x, z, at.Y) else nil
	h.stand = { spot = spot, key = h.routeKey, from = from, wait = wait, at = stand }
	return stand
end

-- 9.0 at the piece he goes for: "take" (he can take it from where he stands: canTake; `stop`: only once at his spot),
-- "walk" (not yet), "fail" (at his spot and still out of his reach or behind a wall Pick.Tries times: he gives it up).
-- A try that fails asks for his spot and his way again.
local function arrive(h: Helper, body: Body, spot: number, stand: Vector3, stop: boolean): string
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	local here = body.root.Position
	local there = flat(here, stand) <= 0.6
	if (there or not stop) and canTake(h, body, item, thing) then
		return "take"
	elseif not there then
		return "walk"
	end
	local tries = (h.tries[spot] or 0) + 1
	h.tries[spot] = tries
	h.stand = nil
	clearPath(h)
	return if tries >= cfg.Pick.Tries then "fail" else "walk"
end

-- 9.0 a piece of his list he can't get to (no spot to take it from, or out of his reach there): off his list, the crew
-- told.
local function cantReach(h: Helper, spot: number)
	local thing = (h.s.move :: Rules.Move).things[spot]
	unqueue(h, spot)
	if h.needs == spot then
		endNeeds(h)
	end
	refreshMarks(h)
	h.pick, h.stand, h.thinkAt = nil, nil, 0
	h.tries[spot] = nil
	tell(h, `🧑‍🔧 {h.name} can't get to the {if thing then thing.name else "piece"}: it's off the list.`)
	tellCrew(h)
end

-- A two-person piece of his list: to it, "give me a hand!" there (the crew's toast once, the marker "needs you", its
-- prompt "Lift with Danny"), then he waits for your lift (your call: he answers it at once). 9.0 at its near side at
-- arm's length (standOf, out of the doorways), turned to it; none: he can't get to it.
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
	local stand = standOf(h, here, spot, true)
	local verdict = if stand then arrive(h, body, spot, stand, true) else "fail"
	if verdict == "fail" then
		cantReach(h, spot)
		return
	elseif verdict == "take" then
		mover.halt(body)
		Npcs.face(body.model, at, cfg.Walk.Turn) -- 9.0 (turned to it; 9.3 a short turn)
		h.needsAt = clock
		say(h, "ask", clock, true)
		if h.needsTold ~= spot then
			h.needsTold = spot
			tell(h, `🙋 {h.name} is at the {thing.name}: lift it together.`)
		end
		mark(h, spot, "ask")
		refreshMarks(h)
		return
	end
	go(h, body, stand :: Vector3, inside, 0.5, Brain.speed(walkSpeed(), "fetch", nil, 0), dt, clock)
end

-- To the next piece of his list; there, he picks it up (off his list: in his arms now). 9.0 to its near side at arm's
-- length (standOf; none: he can't get to it), and his pick-up there (startPick: turned to it, the bend, the piece up
-- into his hands), never from the next room.
local function actFetch(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	local class = if thing then Crew.classFor(h, thing.class) else nil -- 10.1 (Bruno: a piece for two his alone)
	if not thing or not item or (class ~= "hand" and class ~= "both") or (thing.state ~= "home" and thing.state ~= "ground") then
		h.pick, h.thinkAt = nil, 0
		return
	end
	local stand = standOf(h, body.root.Position, spot, false)
	local verdict = if stand then arrive(h, body, spot, stand, false) else "fail"
	if verdict == "fail" then
		cantReach(h, spot)
		return
	elseif verdict == "take" then
		startPick(h, body, spot, clock)
		return
	end
	go(h, body, stand :: Vector3, insideAt(h, item.root.Position), 0.5, Brain.speed(walkSpeed(), "fetch", nil, 0), dt, clock)
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
			startPut(h, body, "put") -- 9.0 (set down, bending)
			h.thinkAt = 0
		end
		return
	end
	if h.dropping then
		local beside = byTruck(truck, 4 + (spot % 3) * 2.2, 2 + (spot // 3 % 2) * 2.5)
		if not beside or go(h, body, beside, false, 1, speed, dt, clock) then
			startPut(h, body, "put") -- 9.0 (set down, bending)
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
	-- 9.3 within reach of its back he walks on into it, slowing (go: MoveHelperBrain.ease), then turns to it (never a
	-- stop the moment he is within reach)
	local walking = body.walking
	if walking and h.stuckFor < cfg.Walk.Settle and not go(h, body, back, false, 1, speed, dt, clock) then
		return
	end
	mover.halt(body)
	local cargo = if walking then Vehicles.cargoDoor(truck) else nil
	if cargo then
		Npcs.face(body.model, cargo.WorldPosition, cfg.Walk.Turn)
	end
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

-- At the van (on its left, out of the way). It stands far off and not by the house (parked somewhere else): he stands
-- where he is (he appears at it once it is parked by the house). No van: outside the house's door (beside it, out of
-- the doorway). (With nothing to carry.)
local function actWait(h: Helper, body: Body, dt: number, clock: number)
	local truck = truckOf(h.s)
	local speed = Brain.speed(walkSpeed(), "wait", nil, 0)
	local spot = if truck then byTruck(truck, -4, 3) else nil
	if not spot then
		local out: CFrame = h.s.site.outside
		spot = out.Position
	elseif truck and not truckAtHouse(h.s, truck) and flat(body.root.Position, spot) > cfg.Far then
		-- (the van far from the house: he stays where he is; he comes to the van at the house)
		mover.halt(body)
		return
	end
	go(h, body, clearOf(h, spot :: Vector3, false), false, 1.5, speed, dt, clock)
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
		-- 10.1 down in the run (every move is one): the revive prompt on him, else out (no comeback at the van)
		local kept = Crew.downed(h, body, clock)
		endCall(h, "down", clock) -- 8.3 (no call waits for him while he is down)
		setDoing(h, if kept == "out" then "out" elseif kept then "revive" else "down", nil)
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
	if h.handle then
		stepHandle(h, body, clock) -- 9.0 his pick-up or setting down: nothing else meanwhile
		return
	end
	local crossing = h.crossing
	if crossing and clock - crossing.at >= Config.Moving.Doors.FadeOut + Config.Moving.Doors.Margin + 0.3 then
		Walking.crossEnd(h, body, clock) -- 9.3 (a walk through a door nothing walks on any more: through it all the same)
	end
	if holding == nil and Crew.guard(h, body, dt, clock) then
		return -- 10.1 Gus: with his boss, at the zombies (his own step)
	end
	local threat, threatAt = nil, nil
	if holding ~= "pair" then
		threat, threatAt = nearestZombie(body.root.Position)
	end
	local truck = truckOf(s)
	local input = h.input
	input.dead, input.holding = false, holding -- (input.seated, input.ride: false for good, 10.6: never in the van)
	input.threat, input.fleeing = threat, h.fleeing
	input.lift = h.lift
	input.queued, input.pair = h.pick, h.pair
	input.open = holding == nil and wantOpen(h, body)
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
	elseif action == "flee" and threatAt then
		actFlee(h, body, threatAt, dt, clock)
	elseif action == "come" and target then
		actCome(h, body, target, holding, dt, clock) -- 8.3
	elseif action == "help" and target then
		actHelp(h, body, target, holding, dt, clock)
	elseif action == "deliver" and spot then
		actDeliver(h, body, spot, dt, clock)
	elseif action == "open" then
		actOpen(h, body, dt, clock)
	elseif action == "needs" and target then
		actNeeds(h, body, target, dt, clock) -- 8.3
	elseif action == "fetch" and target then
		actFetch(h, body, target, dt, clock)
	else
		if h.full and not h.toldFull then
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
	endHandle(h, body) -- 9.0
	if body and not h.dead and not s.ended then
		h.port.helperDrop(s, body.model, "put")
	end
	if why == "crew" then
		tell(h, `🧑‍🔧 {h.name} heads home: your crew has it now.`)
	end
	local clock = os.clock()
	endCall(h, if s.ended then nil else "gone", clock) -- 8.3
	table.clear(h.queue)
	endNeeds(h)
	refreshMarks(h)
	removeBody(h)
	Crew.left(h) -- 10.1
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

-- (8.3 review: the notices' words fit every device: "pick" a piece or him, never a computer's "click"; 8.5 a key in
-- brackets goes on a phone and with a gamepad: SandboxPad.notice)
local ASSIGN_WHY: { [string]: string } = { -- (%s: the piece; HELPER: his name, 10.1)
	clipboard = `📋 Take out your clipboard ({cfg.Clipboard.Key}) to give HELPER pieces.`, -- 8.5 orders mode
	far = "Get closer to the %s to give it to HELPER.",
	his = "HELPER has the %s already.",
	van = "The %s is in the van already.",
	held = "Somebody holds the %s.",
	full = "HELPER's list is full: pick a piece of it to take it back first.",
	reach = "HELPER can't get to the %s: clear a way to it first.", -- 9.0
}

-- 9.0 can he get to the piece at `spot` at all: a spot at arm's length by it (HouseRoute.reach) that his way reaches from
-- where he is (inside) or from any way in. The assignment's check (MoveHelperBrain.assignCheck's "reach"); a piece out of
-- the house, or no grid: yes.
local function reachable(h: Helper, spot: number): boolean
	local s = h.s
	local item = s.items[spot]
	local thing = (s.move :: Rules.Move).things[spot]
	if s.danger and s.danger.sealed[spot] then
		return false -- 10.x danger: in the run's vault (server/RunDanger.luau)
	end
	local grid = routeNow(h)
	if not grid or not item or not thing or not insideAt(h, item.root.Position) then
		return true
	end
	local piece = footprintOf(h, item, thing)
	local starts: { Vector3 } = {}
	local body = h.body
	if body and insideAt(h, body.root.Position) then
		table.insert(starts, body.root.Position)
	end
	for _, way in h.ways do
		table.insert(starts, way.entryIn.Position)
	end
	for _, at in starts do
		local fx, fz = planAt(h, at)
		if Route.reach(grid, fx, fz, piece) then
			return true
		end
	end
	return false
end

-- 8.3 a click on a piece (its model): onto his list, or off it again; checked (MoveHelperBrain.assignCheck). 8.5 only
-- with the player's clipboard out (orders mode: the character attribute ClipboardHeld, server/Clipboard.luau's).
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
	local character = player.Character
	local check: Brain.Assign = { crew = true, mine = true, state = thing.state, held = thing.carrier ~= nil or thing.helper ~= nil,
		his = Rules.holding(s.move, h.id) == spot, queued = table.find(h.queue, spot) ~= nil, count = #h.queue, near = near,
		clipboard = character ~= nil and character:GetAttribute("ClipboardHeld") == true }
	local verdict = Brain.assignCheck(check)
	if verdict == "add" and not reachable(h, spot) then
		check.reach = false -- 9.0 (no spot beside it he can walk to: refused now, never a walk into a wall)
		verdict = Brain.assignCheck(check)
	end
	local clock = os.clock()
	local refused = if verdict == "add" then Crew.refuse(h, thing) else nil -- 10.1 a piece his kind may not carry
	if refused then
		notice:FireClient(player, refused)
	elseif verdict == "add" then
		table.insert(h.queue, spot)
		h.tries[spot] = nil -- (9.0 given again: his tries afresh)
		refreshMarks(h)
		h.thinkAt = 0
		notice:FireClient(player, `🧑‍🔧 {h.name} will take the {thing.name}.`)
		say(h, "queued", clock)
	elseif verdict == "remove" then
		unqueue(h, spot)
		if h.needs == spot then
			endNeeds(h)
		end
		refreshMarks(h)
		h.thinkAt = 0
		notice:FireClient(player, `{h.name} leaves the {thing.name} to you.`)
	else
		local text = ASSIGN_WHY[verdict]
		if text then
			notice:FireClient(player, (string.gsub(string.format(text, thing.name), "HELPER", h.name)))
		end
	end
	tellCrew(h)
end

-- 8.3 CLEAR QUEUE: his list empty (he waits by the van; a piece in his arms still goes into the van).
local function clearQueue(player: Player)
	local h = helperOf(player)
	if not h then
		return
	end
	if #h.queue == 0 then
		notice:FireClient(player, `{h.name}'s list is empty already.`)
		return
	end
	table.clear(h.queue)
	endNeeds(h)
	refreshMarks(h)
	h.thinkAt = 0
	say(h, "cleared", os.clock(), true)
	tell(h, `{player.DisplayName} cleared {h.name}'s list: waiting by the van now.`)
	tellCrew(h)
end

-- 8.6 PUT IT DOWN: what he carries set down where he stands, on the ground, its condition kept (Moving's "put": no fall
-- worth a knock). A piece in his arms alone (one of his list: he took it off it as he picked it up) stays off his list:
-- your word beats the list (back on it he would only pick it up again, at once when it is his only one); your
-- clipboard gives it to him again any time. A two-person piece he holds the far end of: both ends down at once (Moving's
-- helperDrop "together": its carrier's own "put", as their G), his hold off.
local function putDown(h: Helper, body: Body, clock: number, by: Player)
	local s = h.s
	local spot, role = Rules.holding(s.move, h.id)
	local thing = if spot then (s.move :: Rules.Move).things[spot] else nil
	if not spot or not thing then
		return
	end
	local carrier = if role == "helper" then playerOf(thing.carrier) else nil
	if role == "helper" and carrier ~= by then
		-- (8.6 review: a piece for two is put down by whoever carries it with him, never from elsewhere by a crew mate)
		notice:FireClient(by, `🧑‍🔧 {if carrier then carrier.DisplayName else "Someone"} carries the {thing.name} with {h.name}: only they can set it down.`)
		return
	end
	endHandle(h, body) -- (9.0 a pick-up in progress: done at once, the piece in his hands)
	if role == "helper" then
		h.port.helperDrop(s, body.model, "together")
		unhold(h, body) -- (his hold off now: on his feet where he stood)
		poseHands(h, body, nil, nil)
	else
		startPut(h, body, "put") -- 9.0 (set down, bending: his pick-up the other way)
	end
	h.dropping, h.waited, h.vanSaid, h.thinkAt = false, 0, nil, 0
	say(h, if role == "helper" then "putTogether" else "putDown", clock, true)
	for player in s.members do
		if player.Parent then
			notice:FireClient(player, if carrier == player then `🧑‍🔧 You and {h.name} set the {thing.name} down.`
				elseif carrier then `🧑‍🔧 {carrier.DisplayName} and {h.name} set the {thing.name} down.`
				elseif by == player then `🧑‍🔧 {h.name} set the {thing.name} down here: off the list.`
				else `🧑‍🔧 {by.DisplayName} had {h.name} set the {thing.name} down: off the list.`)
		end
	end
end

-- 8.6 the crew's orders, ("helper", "putdown" | "getout"): only a crew player's (anybody else has no Danny here:
-- nothing), checked (MoveHelperBrain.orderCheck: up, something in his hands; 10.6 GET OUT never: he is never in the
-- van), refused with a notice that says why; done, he says so.
local function order(player: Player, kind: string)
	local h = helperOf(player)
	if not h then
		return
	end
	local verdict = Brain.orderCheck(kind, orderState(h)) -- (down, his body gone too: "down")
	local body = h.body
	if verdict ~= "ok" or not body then
		local text = Brain.orderWhy(verdict, h.name)
		if text then
			notice:FireClient(player, text)
		end
		return
	end
	local clock = os.clock()
	putDown(h, body, clock, player) -- (the one order that can be "ok")
	tellCrew(h)
end

-- The crew's requests on the Moving remote: ("helper", "clear" | "stop") at Config.Robust.Limits.MoveHelper (10.1 no "hire"),
-- ("helper", "assign", a piece's model) at MoveHelperAssign, 8.6 ("helper", "putdown" | "getout") at MoveHelperOrder;
-- anything else is dropped.
local function onRequest(player: Player, action: any, kind: any, arg: any)
	if action ~= "helper" then
		return
	end
	if kind == "assign" then
		if Net.limit(player, "MoveHelperAssign", Config.Robust.Limits.MoveHelperAssign) then
			assign(player, arg)
		end
		return
	elseif kind == "putdown" or kind == "getout" then
		if Net.limit(player, "MoveHelperOrder", Config.Robust.Limits.MoveHelperOrder) then
			order(player, kind)
		end
		return
	end
	if not Net.limit(player, "MoveHelper", Config.Robust.Limits.MoveHelper) then
		return
	end
	if kind == "stop" then
		stopCall(player)
	elseif kind == "clear" then
		clearQueue(player)
	end
end

-- 8.3 Moving's Lift on a two-person piece (Config.MoveHelper.WaitForHelper): see the header.
function MoveHelper.call(s: any, player: Player, spot: number): string?
	local h = helpers[s]
	if not h or s.ended or not cfg.WaitForHelper or not Crew.lifts(h) then
		return nil -- (10.1: a kind that never lifts with you: today's rules, you drag it alone)
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
		notice:FireClient(player, `{call.player.DisplayName} is waiting for {h.name} with the {if waited then waited.name else "piece"}.`)
		return "busy"
	elseif call then
		return nil -- (he is on a crew mate's call: today's rules for yours)
	end
	local thing = (s.move :: Rules.Move).things[spot]
	local body = h.body
	if h.dead or not body or not s.members[player] or not thing or thing.class ~= "pair" or (thing.state ~= "home" and thing.state ~= "ground")
		or select(2, Rules.holding(s.move, h.id)) == "helper" then
		return nil -- (he can't come now: today's rules, you drag it alone)
	end
	h.call = { player = player, spot = spot, since = clock, ready = false, readyAt = 0, approach = Brain.newApproach() }
	h.thinkAt = 0
	shout(player.Character, `{h.name}, give me a hand!`)
	notice:FireClient(player, `🙋 "{h.name}, give me a hand!" Wait at your end of the {thing.name}: help's coming. Lift again or press STOP to call it off.`) -- (8.3 review: no key named: every device)
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
	if h.dead or not body or h.handle or not h.port.helperTake(s, spot, body.model) then
		steady(h, nil)
		return false
	end
	Npcs.act(body.model, "lift") -- 9.0 (his end taken up as yours: the bend of his pick-up)
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
		notice:FireClient(player, `You took the {if thing then thing.name else "piece"}: off {h.name}'s list.`)
		say(h, "mine", os.clock())
	end
	tellCrew(h)
end

-- Once: the zombies go after him too (Zombies.extraTargets), the crew's requests, his loop.
local function wire()
	if wired then
		return
	end
	wired = true
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
	Crew.wire({ go = go, inside = insideAt, place = placeAt, say = say, setDoing = setDoing, tellCrew = tellCrew, tell = tell, remove = removeBody, -- 10.1
		halt = function(body: Body)
			mover.halt(body)
		end,
		fade = function(body: Body, out: boolean, seconds: number)
			local f = mover.fade
			if f then
				f(body, out, seconds)
			end
		end,
	})
	task.spawn(function()
		while true do
			local dt = task.wait(cfg.Tick)
			if next(helpers) ~= nil then
				MoveHelper.step(math.min(dt or cfg.Tick, 0.5))
			end
		end
	end)
end

local function create(s: any, port: Port, kind: string): Helper
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
		local foot: Vector3 = if typeof(way.door.door) == "Vector3" then way.door.door else out.Position -- (9.3 its doorway)
		local made: Way = { exitIn = way.inside, entryIn = way.entry, outside = out, door = foot,
			doors = { outX = out.Position.X, outZ = out.Position.Z, inX = way.inside.X, inZ = way.inside.Z } }
		table.insert(ways, made)
		table.insert(wayDoors, made.doors)
	end
	if #ways == 0 then
		local foot: Vector3 = if typeof(s.site.door) == "Vector3" then s.site.door else outside.Position
		local made: Way = { exitIn = exitIn, entryIn = entry, outside = outside, door = foot,
			doors = { outX = outside.Position.X, outZ = outside.Position.Z, inX = exitIn.X, inZ = exitIn.Z } }
		table.insert(ways, made)
		table.insert(wayDoors, made.doors)
	end
	local doorways, fronts = doorwaysOf(s, origin)
	-- 9.0 his way inside: the plan's grid (none for a plan without walls) and its doorways' zones (Aside's, the plan's
	-- frame): no spot to wait in. 9.3 its legs Walk.Clear off everything exactly (the built parts: routeNow, once)
	local made, grid = pcall(Route.grid, s.plan, nil, nil, cfg.Walk.Clear)
	local zones: { Route.Rect } = {}
	for _, door in (s.plan.doors or {}) :: { any } do
		local at: Vector3 = door.at
		local along = (tonumber(door.width) or 4) / 2 + cfg.Aside.Margin
		local through = cfg.Aside.Depth
		local wide = door.axis == "X" -- (a wall along X: through it along Z)
		table.insert(zones, { x0 = at.X - (if wide then along else through), z0 = at.Z - (if wide then through else along),
			x1 = at.X + (if wide then along else through), z1 = at.Z + (if wide then through else along) })
	end
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
		holdEnd = nil,
		trail = Brain.newTrail(),
		holdAt = nil,
		holdLimit = 0,
		steadied = nil,
		walled = nil,
		wallWay = nil,
		bound = nil,
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
		input = { dead = false, holding = nil, seated = false, ride = false, threat = nil, fleeing = false, lift = nil, queued = nil, pair = false, open = false,
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
		doing = Brain.doing("wait"),
		doingAction = "wait",
		doingSpot = nil,
		doingFull = false,
		told = {},
		call = nil,
		helpWalk = nil,
		hirer = s.owner, -- (10.1: free, the move's owner's from the start)
		kind = kind, -- 10.1
		name = Crew.name(kind),
		queue = {},
		marks = {},
		needs = nil,
		needsAt = 0,
		needsTold = nil,
		bubble = "",
		alert = false,
		orderIn = { down = false, holding = nil, seated = false, boarding = false, riding = false, leaving = false, moving = false },
		route = if made then grid else nil,
		routeKey = "",
		doorZones = zones,
		pathInside = false,
		pathKey = "",
		stand = nil,
		wayPicks = {},
		tries = {},
		handle = nil,
		pathXZ = {}, -- 9.3
		pathFresh = false,
		progress = Brain.newProgress(),
		progressGoal = nil,
		phase = "walk",
		phaseRound = 0,
		recover = nil,
		crossing = nil,
		solids = false,
		teleports = {},
		diagAt = {},
	}
	if not made then
		warn(`[MoveHelper] no way inside: {grid}`)
	end
	h.bubble = (Brain.bubble("wait", nil, false)) -- 8.6
	helpers[s] = h
	byId[id] = h
	Crew.joined(h) -- 10.1
	if spawnBody(h, homeSpot(h)) then
		say(h, "hello", clock, true)
	else
		h.dead, h.downAt = true, clock - cfg.Respawn + 2 -- (tried again in a moment)
	end
	tell(h, Crew.helloText(h)) -- (10.1: free, no hire)
	return h
end

local function syncOne(s: any, port: Port)
	if s.ended then
		return
	end
	local h = helpers[s]
	local count = 0
	for player in s.members do
		if player.Parent then
			count += 1
		end
	end
	local want = Brain.wanted(count, true) -- (10.1: with every party)
	local kind = if want and not h then Crew.kindFor(s) else nil -- 10.1 the owner's pick of their crew (nil: nobody ready)
	if kind and not h then
		h = create(s, port, kind)
	elseif not want and h then
		dismiss(h, "crew")
		return
	end
	if h then
		tellCrew(h)
	end
	Crew.sync(s, h) -- 10.1 a run's rescue, Lucy's sense
end

function MoveHelper.sync(s: any, port: Port)
	local ok, err = pcall(syncOne :: any, s, port)
	if not ok then
		warn(`[MoveHelper] {err}`)
	end
end

function MoveHelper.nameOf(id: number?): string?
	local h = if id then byId[id] else nil
	return if h then h.name else nil
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
