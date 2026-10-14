--!strict
-- 8.1 carrying in two (the owner: "the way Danny helps me is weird: when I turn around he teleports. When we carry
-- something heavy and I need help, we must walk, like, backwards and slowly"): the far end's carrier held there by the
-- server, Danny (server/MoveHelper.luau's mover) and a crew mate who helps lift (server/Moving.luau's watchCarried)
-- alike. An attachment at the piece's far end (turned to its leader), one on the holder's root, an AlignPosition and an
-- AlignOrientation between them: the holder walks there at a top speed that fits the pair's walk (MaxVelocity:
-- shared/MoveHelperBrain.luau holdSpeed, the leader's CarrySpeed × PairCarry.boost) and turns to the leader at
-- holdTurn; the server owns the holder's body meanwhile (SetNetworkOwner(nil): the positions are the server's whatever
-- the lag; a player's body is given back when they let go). The leader's client turns the piece slowly (client/
-- PairSteer.luau), so the far end never swings faster than that.
--   * Danny (ghost): his parts in a collision group nothing collides with (through door frames like the piece), held
--     in all three axes (his own walk is off: server/Npcs.luau carried).
--   * A crew mate (flat): their body keeps colliding and stands on the floor itself: the align pulls along the ground
--     only. Never put there at once (MoveHelperBrain.holdTrack): more than HoldBehind studs off for HoldStuck s, an ease
--     of HoldEase s (ghost and held in all three axes meanwhile: through whatever is in the way). A door's trip (either
--     end on it) pauses the hold; the piece in the other world without one: put there.
--   PairHold.make(model, root, anchor, offset, limit, options) -> Hold   the hold made (options: ghost, flat, owner)
--   PairHold.aim(hold, offset, limit, flat?)   its far end's place in the piece's frame, its top speed, along the
--                                            ground only or not
--   PairHold.ghost(hold, on)                 the holder's parts in the collision group nothing collides with, or back
--   PairHold.pause(hold, paused)             the constraints off (a door's trip) or on again
--   PairHold.snap(hold, goal)                put there at once (a door's fade only)
--   PairHold.alive(hold, anchor) -> boolean  its pieces are all there, on this piece
--   PairHold.drop(hold)                      let go: the constraints gone, the groups and the body's owner given back
--   PairHold.walkOf(player, fallback)        a leader's walk now (their CarrySpeed × their boosts), else `fallback`
--   PairHold.follow(player, root, anchor, depth, carrierRoot, carrier, away) -> boolean   a crew mate holding the far
--                                            end of `anchor`'s piece (`depth` its size along the carry): held there,
--                                            one look of Moving's tick (away: a door's trip is on); true while held
--   PairHold.free(player)                    a crew mate let go (their body theirs again); PairHold.of(player): the hold

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Brain = require(Shared.MoveHelperBrain)
local PairCarry = require(Shared.PairCarry)

local PairHold = {}

local cfg = Config.MoveHelper
local NAME = "PairHold"
local HELD = "MoveHelperHeld" -- the collision group nothing collides with (7.x Danny's)
local FORCE = 1e6
local WORLD = 300 -- studs: the far end this far off is in the other world (a house's interior far off the map)

export type Hold = {
	model: Model,
	root: BasePart,
	anchor: BasePart,
	far: Attachment,
	own: Attachment,
	align: AlignPosition,
	orient: AlignOrientation,
	groups: { [BasePart]: string }?, -- the parts' own groups while ghosted
	owner: Player?, -- a player's body: theirs again on drop
	flat: boolean,
	offset: CFrame,
	limit: number,
}

export type Options = { ghost: boolean, flat: boolean, owner: Player? }

type Mate = { hold: Hold, trail: Brain.Trail, at: number }

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

function PairHold.make(model: Model, root: BasePart, anchor: BasePart, offset: CFrame, limit: number, options: Options): Hold
	local far = Instance.new("Attachment")
	far.Name = NAME
	far.CFrame = offset
	far.Parent = anchor
	local own = Instance.new("Attachment")
	own.Name = NAME
	own.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = NAME
	align.Attachment0 = own
	align.Attachment1 = far
	setForce(align, options.flat)
	align.MaxVelocity = limit
	align.Responsiveness = cfg.HoldResponse
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Name = NAME
	orient.Attachment0 = own
	orient.Attachment1 = far
	orient.MaxTorque = FORCE
	orient.MaxAngularVelocity = Brain.holdTurn()
	orient.Responsiveness = cfg.HoldResponse
	orient.Parent = root
	pcall(function()
		root:SetNetworkOwner(nil) -- (the server's positions, whatever the lag)
	end)
	local hold: Hold = { model = model, root = root, anchor = anchor, far = far, own = own, align = align, orient = orient, groups = nil, owner = options.owner,
		flat = options.flat, offset = offset, limit = limit }
	if options.ghost then
		PairHold.ghost(hold, true)
	end
	return hold
end

function PairHold.aim(hold: Hold, offset: CFrame, limit: number, flat: boolean?)
	if (hold.offset.Position - offset.Position).Magnitude > 0.05 then
		hold.offset = offset
		hold.far.CFrame = offset
	end
	if math.abs(hold.limit - limit) > 0.01 then
		hold.limit = limit
		hold.align.MaxVelocity = limit
	end
	local wantFlat = if flat == nil then hold.flat else flat
	if wantFlat ~= hold.flat then
		hold.flat = wantFlat
		setForce(hold.align, wantFlat)
	end
end

function PairHold.pause(hold: Hold, paused: boolean)
	if hold.align.Enabled ~= not paused then
		hold.align.Enabled = not paused
		hold.orient.Enabled = not paused
	end
end

function PairHold.snap(hold: Hold, goal: CFrame)
	hold.model:PivotTo(goal)
	hold.root.AssemblyLinearVelocity = Vector3.zero
end

function PairHold.alive(hold: Hold, anchor: BasePart?): boolean
	return (anchor == nil or hold.anchor == anchor) and hold.far.Parent ~= nil and hold.own.Parent ~= nil and hold.align.Parent ~= nil
		and hold.orient.Parent ~= nil and hold.root.Parent ~= nil
end

function PairHold.drop(hold: Hold)
	local made: { Instance } = { hold.align, hold.orient, hold.own, hold.far }
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
	end
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

function PairHold.free(player: Player)
	local mate = mates[player]
	if mate then
		mates[player] = nil
		PairHold.drop(mate.hold)
	end
end

function PairHold.of(player: Player): Hold?
	local mate = mates[player]
	return if mate then mate.hold else nil
end

function PairHold.follow(player: Player, root: BasePart, anchor: BasePart, depth: number, carrierRoot: BasePart, carrier: Player, away: boolean?): boolean
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
	-- the far end: Standoff past the far face (its -Z, away from the leader), at the leader's root height, turned to them
	local rise = carrierRoot.Position.Y - anchor.Position.Y
	local offset = CFrame.new(0, rise, -Brain.farEnd(depth)) * CFrame.Angles(0, math.pi, 0)
	local speed = Brain.holdSpeed(PairHold.walkOf(carrier, Config.Movement.Walk))
	if not mate then
		mate = { hold = PairHold.make(character, root, anchor, offset, speed, { ghost = false, flat = true, owner = player }), trail = Brain.newTrail(), at = clock }
		mates[player] = mate
	end
	local m = mate :: Mate
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
	local limit, snap = Brain.holdTrack(m.trail, gap, gap > WORLD, speed, dt)
	local easing = m.trail.ease > 0
	PairHold.ghost(hold, easing) -- (eased back: through whatever was in the way, held in all three axes)
	PairHold.aim(hold, offset, limit, not easing)
	if snap then
		PairHold.snap(hold, goal)
	end
	return true
end

Players.PlayerRemoving:Connect(PairHold.free)

return PairHold
