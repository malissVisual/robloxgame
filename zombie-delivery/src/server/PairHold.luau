--!strict
-- 8.1 carrying in two (the owner: "the way Danny helps me is weird: when I turn around he teleports. When we carry
-- something heavy and I need help, we must walk, like, backwards and slowly"): the far end's carrier held there by the
-- server, Danny (server/MoveHelper.luau's mover) and a crew mate who helps lift (server/Moving.luau's watchCarried)
-- alike. The piece's far end (turned to its leader) the goal of an AlignPosition and an AlignOrientation on the holder's
-- root (9.0: one attachment each, the holder's; the server sets the goals every Heartbeat): the holder walks there at a top speed that fits the pair's walk (MaxVelocity:
-- shared/MoveHelperBrain.luau holdSpeed, the leader's CarrySpeed × PairCarry.boost) and turns to the leader at
-- holdTurn; the server owns the holder's body meanwhile (SetNetworkOwner(nil): the positions are the server's whatever
-- the lag; a player's body is given back when they let go). The leader's client turns the piece slowly (client/
-- PairSteer.luau), so the far end never swings faster than that.
--   * Danny (ghost): his parts in a collision group nothing collides with (through door frames like the piece), his
--     own walk off (server/Npcs.luau carried). 8.3 (the owner: "he just jumps weirdly"): the align pulls him along the
--     ground only, his height is the lift's (a third constraint on his root, up and down only, at the far end's height
--     at each aim: the floor under his end, server/MoveHelper.luau's, and at HoldClimb studs a second at most): the
--     piece's own ups and downs (your step up a kerb, into the van, a jump) never carry him up between two aims.
--   * A crew mate (flat): their body keeps colliding and stands on the floor itself: the align pulls along the ground
--     only. Never put there at once (MoveHelperBrain.holdTrack): more than HoldBehind studs off for HoldStuck s, an ease
--     of HoldEase s (ghost and held in all three axes meanwhile: through whatever is in the way). A door's trip (either
--     end on it) pauses the hold; the piece in the other world without one: put there.
--   8.3 keeping up (the owner: "when I run, he just goes behind me with his arms stretched out"): the top speed follows
--   the leader's real speed along the ground (their root's at each look: MoveHelperBrain.holdPace / holdSpeed, HoldCap at
--   most), Danny and a crew mate alike; Danny is also aimed a little ahead (server/MoveHelper.luau, HoldLead), a crew mate
--   not (on their own screen they would walk ahead of the piece). Neither runs meanwhile (the CarryPair attribute,
--   client/PairSteer.luau holds their walk at CarrySpeed).
--   8.6 (the owner: "he teleports from side to side"): the far end is the face of the piece across it from the leader,
--   decided once as the hold starts and kept in the piece's own frame (MoveHelperBrain.holdEnd): carried in two the
--   piece lies along the carry (server/Moving.luau's holdOffset), so the two hold the ends of its length; a crew mate's
--   end as Danny's (it was always the piece's -Z: its long side once the piece lies along the carry).
--   9.0 (the owner, 8.9.3: "Danny carries better now, but only when I walk backwards. When I want to walk forwards,
--   Danny can't walk backwards"; then "and he still teleports", his screenshot of Danny in the Sofa, another of his own
--   body lying across it): the constraints had their Attachment1 on the piece, and the piece is welded to the leader's
--   root. A constraint between two assemblies makes one mechanism of them, and a mechanism has one network owner: the
--   holder's body (the server's, SetNetworkOwner(nil)) and the leader's (their own client's) were one thing that the two
--   machines fought over (tests/movehelper_backwards_runtime_test.luau counts them: both constraints reached into the
--   leader's assembly). Now each has one attachment, the holder's own (Mode OneAttachment), and the server sets their
--   goals from the piece where it is now (its frame × the hold's offset: PairHold.aim) every Heartbeat (PairHold.step,
--   one connection for all the holds): nothing joins the holder's body to the leader's, nothing of the hold pushes or
--   turns the leader, the server alone moves the holder. The leader's screen shows the holder late (the server's body),
--   so a crew mate's hold gives the leader's character PairWith (their UserId) and PairFar (their place in the leader's
--   root's frame) as Danny's does: client/PairSteer.luau never pushes the piece into them on that screen.
--   9.2 (the owner, 8.9.5, carrying a Sofa with Danny: "the carrying is better, but it feels like it's harder to
--   control … fix it so it's playable"; 8.9.4 hid that lateness by holding the leader's walk back: a start of 0.85 s in
--   Studio, 2 s online): Danny's hold is DRIVEN by its leader (PairHold.lead; server/MoveHelper.luau actHold: the piece's
--   carrier, a player). His body's physics is the leader's (root:SetNetworkOwner(leader)), and his model publishes what
--   their client needs (client/PairLead.luau): PairLead (the leader's UserId), PairLeadAt (his place in the piece's frame
--   at its middle's height: written when it changes) and the ObjectValue PairLeadPiece (the piece's root; an attribute
--   holds no instance). Their client sets the constraints' goals from its own piece every frame before the physics: no
--   lag on their screen. Meanwhile the server writes none of the constraints' properties (no Heartbeat goals, aim keeps
--   its numbers only): a server write replicates and would undo the leader's. Roblox's rules this leans on:
--     * network ownership is per mechanism (assemblies joined by constraints share one owner): his body is one
--       assembly, joined to nothing (the constraints have one attachment each, his own), so it can be the leader's
--       alone; the piece is welded to the leader's root, theirs already
--     * on the owning client a property its own scripts write is what its simulation uses (not replicated); the
--       positions and velocities the simulation makes replicate to the server and everybody
--     * the owner runs a humanoid's state machine: the server's Physics state (server/Npcs.luau carried, set while the
--       server owned him) is kept by the leader's client; given back, the server owns him again before Npcs.carried
--       stands him (drop: the constraints first, then SetNetworkOwner(nil))
--     * a CFrame the server sets on a part a client owns moves it there on every machine (a door's fade: snap)
--     * OneAttachment: no Attachment1, so no reaction force or torque (ReactionForceEnabled / ReactionTorqueEnabled
--       false) ever reaches the leader
--   Taken back (lead(hold, nil): a drive the server's look ended, MoveHelperBrain.leadKept) the hold is the server's
--   again at once (its own goals, its numbers, every Heartbeat), as a crew mate's always is.
--   PairHold.endOffset(ax, az, reach, rise) -> CFrame   8.6 the far end's place in the piece's frame: `reach` studs out
--                                            of its middle along its axis (ax, az), `rise` over it, turned back to it
--   PairHold.make(model, root, anchor, offset, limit, options) -> Hold   the hold made (options: ghost, flat, owner;
--                                            8.3 lift: the height by the lift, the align along the ground; 9.2 driver:
--                                            the player whose client drives it, PairHold.lead)
--   PairHold.lead(hold, driver) -> boolean   9.2 the hold driven by `driver`'s client (his body's physics theirs, the
--                                            server writing none of the constraints), nil: the server's again (its
--                                            goals at once and every Heartbeat); true while driven (false: his body
--                                            could not be given, the server keeps him); PairHold.drives(hold): the driver
--   PairHold.aim(hold, offset, limit, flat?)   its far end's place in the piece's frame, its top speed, along the
--                                            ground only or not (the lift's height: the far end's now); 9.0 hold.bound
--                                            (set by its maker): where the holder may go, applied to the goal every
--                                            Heartbeat (Danny's: along a house's walls); 9.2 driven: the numbers kept
--                                            (written when it is the server's again), PairLeadAt written if it moved
--   PairHold.ghost(hold, on)                 the holder's parts in the collision group nothing collides with, or back
--   PairHold.pause(hold, paused)             the constraints off (a door's trip) or on again
--   PairHold.snap(hold, goal)                put there at once (a door's fade only)
--   PairHold.step()                          9.0 every hold's goals from its piece where it is now (each Heartbeat while
--                                            a hold is live: connected at the first, let go of after the last; a test
--                                            calls it)
--   PairHold.goal(hold) -> CFrame            9.0 where the hold puts its holder now (its piece's frame × its offset)
--   PairHold.alive(hold, anchor) -> boolean  its pieces are all there, on this piece
--   PairHold.drop(hold)                      let go: the constraints gone, the groups and the body's owner given back
--                                            (9.2 a driven one: PairLead* gone, the server's again)
--   PairHold.walkOf(player, fallback)        a leader's walk now (their CarrySpeed × their boosts), else `fallback`
--   PairHold.pingOf(player)                  8.3 a leader's ping (Player:GetNetworkPing, s; 0 without one): Danny's lead
--   PairHold.follow(player, root, anchor, size, carrierRoot, carrier, away) -> boolean   a crew mate holding the far
--                                            end of `anchor`'s piece (`size` its size; 8.6 its end decided at the
--                                            hold's start): held there, one look of Moving's tick (away: a door's trip
--                                            is on); true while held
--   PairHold.free(player)                    a crew mate let go (their body theirs again); PairHold.of(player): the hold

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService") -- 9.0 the holds' goals every Heartbeat

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Brain = require(Shared.MoveHelperBrain)
local PairCarry = require(Shared.PairCarry)

local PairHold = {}

local cfg = Config.MoveHelper
local NAME = "PairHold"
local PIECE = "PairLeadPiece" -- 9.2 the ObjectValue on a driven holder's model: the piece (client/PairLead.luau)
local HELD = "MoveHelperHeld" -- the collision group nothing collides with (7.x Danny's)
local FORCE = 1e6
local WORLD = 300 -- studs: the far end this far off is in the other world (a house's interior far off the map)

export type Hold = {
	model: Model,
	root: BasePart,
	anchor: BasePart, -- the piece (9.0: nothing of the hold on it; its frame read for the goals)
	own: Attachment,
	align: AlignPosition,
	orient: AlignOrientation,
	lift: AlignPosition?, -- 8.3 his height (up and down only), when the hold has one
	groups: { [BasePart]: string }?, -- the parts' own groups while ghosted
	owner: Player?, -- a player's body: theirs again on drop
	flat: boolean,
	offset: CFrame,
	limit: number,
	-- 9.0 where the holder may go now (the goal, the holder's root) → the goal kept (Danny's inside a house: along its
	-- walls, never through: server/MoveHelper.luau's), every Heartbeat; nil: the goal as it is
	bound: ((goal: Vector3, here: Vector3) -> Vector3)?,
	driver: Player?, -- 9.2 the leader whose client drives it (nil: the server's)
	at: CFrame?, -- 9.2 …the place it published (PairLeadAt)
}

export type Options = { ghost: boolean, flat: boolean, owner: Player?, lift: boolean?, driver: Player? }

type Mate = { hold: Hold, trail: Brain.Trail, at: number, ax: number, az: number, reach: number, leader: Model? } -- (8.6 their end; 9.0 the leader's body: PairWith, PairFar)

local mates: { [Player]: Mate } = {}

-- The collision group nothing collides with: registered once.
local heldReady = false
local function heldGroup()
	if heldReady then
		return
	end
	heldReady = true
	local ok, physics = pcall(function(): any
		return game:GetService("PhysicsService")
	end)
	if not ok or not physics then
		return
	end
	pcall(function()
		physics:RegisterCollisionGroup(HELD)
	end)
	local listed, groups = pcall(function(): { any }
		return physics:GetRegisteredCollisionGroups()
	end)
	if listed and groups then
		for _, group in groups do
			pcall(function()
				physics:CollisionGroupSetCollidable(HELD, group.name, false)
			end)
		end
	end
end

local function setForce(align: AlignPosition, flat: boolean)
	align.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	align.ForceRelativeTo = Enum.ActuatorRelativeTo.World
	align.MaxAxesForce = Vector3.new(FORCE, if flat then 0 else FORCE, FORCE)
end

function PairHold.ghost(hold: Hold, on: boolean)
	local groups = hold.groups
	if on and not groups then
		heldGroup()
		local made: { [BasePart]: string } = {}
		for _, d in hold.model:GetDescendants() do
			if d:IsA("BasePart") then
				made[d] = d.CollisionGroup
				d.CollisionGroup = HELD
			end
		end
		hold.groups = made
	elseif not on and groups then
		hold.groups = nil
		for part, group in groups do
			if part.Parent then
				part.CollisionGroup = group
			end
		end
	end
end

function PairHold.endOffset(ax: number, az: number, reach: number, rise: number): CFrame
	return CFrame.new(ax * reach, rise, az * reach) * CFrame.Angles(0, math.atan2(ax, az), 0) -- (looking along -axis: in)
end

-- 9.0 every hold made and not dropped yet (PairHold.step sets their goals every Heartbeat)
local live: { [Hold]: boolean } = {}
local stepping: RBXScriptConnection? = nil

function PairHold.goal(hold: Hold): CFrame
	return hold.anchor.CFrame * hold.offset
end

-- 9.0 one hold's goals from its piece where it is now: the align's place (along the ground, or in all three axes while
-- eased), the turn, the lift's height (8.3: up and down only, the floor his end's puts him at).
local function setGoals(hold: Hold)
	local goal = hold.anchor.CFrame * hold.offset
	local bound = hold.bound
	hold.align.Position = if bound then bound(goal.Position, hold.root.Position) else goal.Position
	hold.orient.CFrame = goal.Rotation
	local lift = hold.lift
	if lift then
		lift.Position = goal.Position
	end
end

-- (no hold left: the Heartbeat let go of until the next one is made)
local function idle()
	local connection = stepping
	if connection and next(live) == nil then
		stepping = nil
		connection:Disconnect()
	end
end

function PairHold.step()
	for hold in live do
		if not hold.align.Parent then
			live[hold] = nil -- (gone without a drop: its holder's body went)
		elseif hold.anchor.Parent then
			setGoals(hold)
		end
	end
	idle()
end

-- (the server's: its goals from now on, every Heartbeat)
local function serve(hold: Hold)
	live[hold] = true
	if not stepping then
		stepping = RunService.Heartbeat:Connect(PairHold.step)
	end
end

-- 9.2 his place in the piece's frame as the leader's client takes it (PairLeadAt): the hold's offset at the piece's
-- middle's height (their client finds the floor under his end itself), written only when it moved.
local function publish(hold: Hold)
	local offset = hold.offset
	local at = CFrame.new(offset.X, 0, offset.Z) * offset.Rotation
	local was = hold.at
	if was and (was.Position - at.Position).Magnitude < 0.01 and was.LookVector:Dot(at.LookVector) > 0.9999 then
		return
	end
	hold.at = at
	hold.model:SetAttribute("PairLeadAt", at)
end

function PairHold.drives(hold: Hold): Player?
	return hold.driver
end

function PairHold.lead(hold: Hold, driver: Player?): boolean
	if driver == hold.driver then
		if driver then
			publish(hold)
		end
		return driver ~= nil
	end
	local model = hold.model
	local given = pcall(function()
		hold.root:SetNetworkOwner(driver) -- (nil: the server's)
	end)
	if driver and not given then
		return false -- (his body could not be theirs, an anchored part on it: the server keeps him, as it was)
	end
	hold.driver = driver
	if driver then
		live[hold] = nil -- (no Heartbeat goals: the leader's client sets them)
		idle()
	end
	local value = model:FindFirstChild(PIECE)
	if driver then
		local made: ObjectValue = if value and value:IsA("ObjectValue") then value :: ObjectValue else Instance.new("ObjectValue")
		made.Name = PIECE
		made.Value = hold.anchor
		made.Parent = model
		publish(hold)
		model:SetAttribute("PairLead", driver.UserId) -- (last: their client drives once it sees itself here)
		return true
	end
	model:SetAttribute("PairLead", nil)
	model:SetAttribute("PairLeadAt", nil)
	hold.at = nil
	if value then
		value:Destroy()
	end
	-- the server's again: its own numbers and goals at once (what the leader's client wrote never reached the server)
	hold.align.MaxVelocity = hold.limit
	setForce(hold.align, hold.flat)
	setGoals(hold)
	serve(hold)
	return false
end

function PairHold.make(model: Model, root: BasePart, anchor: BasePart, offset: CFrame, limit: number, options: Options): Hold
	local own = Instance.new("Attachment")
	own.Name = NAME
	own.Parent = root
	local flat = options.flat or options.lift == true -- (8.3 a lift holds the height: the align along the ground only)
	-- 9.0 one attachment each, the holder's own: the goals the server's (setGoals), nothing on the piece
	local align = Instance.new("AlignPosition")
	align.Name = NAME
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = own
	setForce(align, flat)
	align.MaxVelocity = limit
	align.Responsiveness = cfg.HoldResponse
	align.ReactionForceEnabled = false -- (9.2 one attachment: no reaction reaches anybody)
	align.Parent = root
	local lift: AlignPosition? = nil
	if options.lift then
		-- 8.3 his height: one attachment to a point in the world (the far end's), up and down only, at HoldClimb studs a
		-- second at most
		local made = Instance.new("AlignPosition")
		made.Name = NAME
		made.Mode = Enum.PositionAlignmentMode.OneAttachment
		made.Attachment0 = own
		made.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		made.ForceRelativeTo = Enum.ActuatorRelativeTo.World
		made.MaxAxesForce = Vector3.new(0, FORCE, 0)
		made.MaxVelocity = cfg.HoldClimb
		made.Responsiveness = cfg.HoldResponse
		made.ReactionForceEnabled = false
		made:SetAttribute("Lift", true) -- (9.2 client/PairLead.luau tells it from the align by this)
		made.Parent = root
		lift = made
	end
	local orient = Instance.new("AlignOrientation")
	orient.Name = NAME
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = own
	orient.MaxTorque = FORCE
	orient.MaxAngularVelocity = Brain.holdTurn()
	orient.Responsiveness = cfg.HoldResponse
	orient.ReactionTorqueEnabled = false -- (9.2 one attachment: nothing to push back on, nothing reaches the leader)
	orient.Parent = root
	pcall(function()
		root:SetNetworkOwner(nil) -- (the server's positions, whatever the lag; 9.2 a driven hold's the leader's below)
	end)
	local hold: Hold = { model = model, root = root, anchor = anchor, own = own, align = align, orient = orient, lift = lift, groups = nil,
		owner = options.owner, flat = flat, offset = offset, limit = limit, bound = nil, driver = nil, at = nil }
	setGoals(hold) -- (9.2 driven too: where he is held until the leader's client takes him)
	if options.ghost then
		PairHold.ghost(hold, true)
	end
	if not (options.driver and PairHold.lead(hold, options.driver)) then
		serve(hold)
	end
	return hold
end

function PairHold.aim(hold: Hold, offset: CFrame, limit: number, flat: boolean?)
	hold.offset = offset -- (9.0 the goals from it now and every Heartbeat: setGoals)
	-- 9.2 driven by its leader's client: the numbers kept, nothing of the constraints written (a server write replicates
	-- and would undo the leader's); they are written when the hold is the server's again (PairHold.lead)
	local driven = hold.driver ~= nil
	if math.abs(hold.limit - limit) > 0.01 then
		hold.limit = limit
		if not driven then
			hold.align.MaxVelocity = limit
		end
	end
	local lift = hold.lift
	local wantFlat = if lift then true elseif flat == nil then hold.flat else flat
	if wantFlat ~= hold.flat then
		hold.flat = wantFlat
		if not driven then
			setForce(hold.align, wantFlat)
		end
	end
	if driven then
		publish(hold)
	else
		setGoals(hold)
	end
end

function PairHold.pause(hold: Hold, paused: boolean)
	if hold.align.Enabled ~= not paused then
		hold.align.Enabled = not paused
		hold.orient.Enabled = not paused
		local lift = hold.lift
		if lift then
			lift.Enabled = not paused
		end
	end
end

function PairHold.snap(hold: Hold, goal: CFrame)
	hold.model:PivotTo(goal)
	hold.root.AssemblyLinearVelocity = Vector3.zero
end

function PairHold.alive(hold: Hold, anchor: BasePart?): boolean
	local lift = hold.lift
	return (anchor == nil or hold.anchor == anchor) and hold.anchor.Parent ~= nil and hold.own.Parent ~= nil and hold.align.Parent ~= nil
		and hold.orient.Parent ~= nil and hold.root.Parent ~= nil and (lift == nil or lift.Parent ~= nil)
end

function PairHold.drop(hold: Hold)
	live[hold] = nil
	idle()
	local driver = hold.driver
	if driver then
		-- 9.2 (the leader's client lets go of him once these are gone)
		hold.driver, hold.at = nil, nil
		hold.model:SetAttribute("PairLead", nil)
		hold.model:SetAttribute("PairLeadAt", nil)
		local value = hold.model:FindFirstChild(PIECE)
		if value then
			value:Destroy()
		end
	end
	local made: { Instance } = { hold.align, hold.orient, hold.own }
	local lift = hold.lift
	if lift then
		table.insert(made, lift)
	end
	for _, obj in made do
		obj:Destroy()
	end
	PairHold.ghost(hold, false)
	local owner = hold.owner
	local root = hold.root
	if owner and owner.Parent and root.Parent then
		pcall(function()
			root:SetNetworkOwner(owner) -- (their body theirs again)
		end)
	elseif driver and root.Parent then
		pcall(function()
			root:SetNetworkOwner(nil) -- 9.2 (the server's again before server/Npcs.luau carried stands him: the owner sets his state)
		end)
	end
end

function PairHold.pingOf(player: Player?): number
	if not player then
		return 0
	end
	local ok, ping = pcall(function(): any
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" and ping == ping then ping else 0
end

function PairHold.walkOf(player: Player?, fallback: number): number
	local character = player and player.Character
	if not player or not character then
		return fallback
	end
	local speed = character:GetAttribute("CarrySpeed")
	local walk = if type(speed) == "number" and speed == speed then speed else fallback
	return walk * PairCarry.boost(player:GetAttribute("AdminSpeed"), character:GetAttribute("KitSpeed"))
end

-- ── A crew mate at the far end (server/Moving.luau's tick) ────────────────

-- 9.0 the leader's side of a crew mate's hold (client/PairSteer.luau, shared/PairCarry.luau keep): who holds the far end
-- (PairWith: their UserId) and their place in the leader's root's frame (PairFar); nil, nil: gone.
local function leaderSees(leader: Model?, id: number?, far: Vector3?)
	if not leader then
		return
	end
	if leader:GetAttribute("PairWith") ~= id then
		leader:SetAttribute("PairWith", id)
	end
	local was = leader:GetAttribute("PairFar")
	if far == nil or typeof(was) ~= "Vector3" or (was - far).Magnitude > 0.05 then
		if was ~= far then
			leader:SetAttribute("PairFar", far)
		end
	end
end

function PairHold.free(player: Player)
	local mate = mates[player]
	if mate then
		mates[player] = nil
		PairHold.drop(mate.hold)
		local leader = mate.leader
		if leader and leader:GetAttribute("PairWith") == player.UserId then
			leaderSees(leader, nil, nil)
		end
	end
end

function PairHold.of(player: Player): Hold?
	local mate = mates[player]
	return if mate then mate.hold else nil
end

function PairHold.follow(player: Player, root: BasePart, anchor: BasePart, size: { X: number, Y: number, Z: number }, carrierRoot: BasePart, carrier: Player, away: boolean?): boolean
	local character = player.Character
	if not character or not root.Parent or not anchor.Parent then
		PairHold.free(player)
		return false
	end
	local clock = os.clock()
	local mate: Mate? = mates[player]
	if mate and (mate.hold.root ~= root or not PairHold.alive(mate.hold, anchor)) then
		PairHold.free(player)
		mate = nil
	end
	-- the far end: Standoff past the face across the piece from the leader (8.6: decided as the hold starts, kept in the
	-- piece's frame: MoveHelperBrain.holdEnd), at the leader's root height, turned to them
	local rise = carrierRoot.Position.Y - anchor.Position.Y
	local speed = Brain.holdSpeed(PairHold.walkOf(carrier, Config.Movement.Walk))
	if not mate then
		local from = anchor.CFrame:PointToObjectSpace(carrierRoot.Position)
		local ax, az, half = Brain.holdEnd(size.X, size.Z, from.X, from.Z)
		local reach = Brain.farEnd(half * 2)
		local made = PairHold.make(character, root, anchor, PairHold.endOffset(ax, az, reach, rise), speed, { ghost = false, flat = true, owner = player })
		mate = { hold = made, trail = Brain.newTrail(), at = clock, ax = ax, az = az, reach = reach, leader = nil }
		mates[player] = mate
	end
	local m = mate :: Mate
	local offset = PairHold.endOffset(m.ax, m.az, m.reach, rise)
	local hold = m.hold
	local dt = math.clamp(clock - m.at, 0, 0.5)
	m.at = clock
	PairHold.pause(hold, away == true)
	if away then
		m.trail = Brain.newTrail()
		PairHold.ghost(hold, false)
		PairHold.aim(hold, offset, speed, true)
		return true
	end
	local goal = anchor.CFrame * offset
	local here = root.Position
	local gap = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z).Magnitude
	-- 8.3 keeping up: the top speed follows the leader's real speed along the ground (their root's)
	local from = carrierRoot.Position
	speed = Brain.holdSpeed(PairHold.walkOf(carrier, Config.Movement.Walk), Brain.holdPace(m.trail, from.X, from.Z, dt, gap > WORLD))
	local limit, snap = Brain.holdTrack(m.trail, gap, gap > WORLD, speed, dt)
	local easing = m.trail.ease > 0
	PairHold.ghost(hold, easing) -- (eased back: through whatever was in the way, held in all three axes)
	PairHold.aim(hold, offset, limit, not easing)
	if snap then
		PairHold.snap(hold, goal)
	end
	-- 9.0 the leader's screen shows them late too: the leader never pushes the piece into them there (PairFar, PairWith)
	local leader = carrierRoot.Parent :: Model?
	if m.leader and m.leader ~= leader and m.leader:GetAttribute("PairWith") == player.UserId then
		leaderSees(m.leader, nil, nil)
	end
	m.leader = leader
	leaderSees(leader, player.UserId, carrierRoot.CFrame:PointToObjectSpace(goal.Position))
	return true
end

Players.PlayerRemoving:Connect(PairHold.free)

return PairHold
