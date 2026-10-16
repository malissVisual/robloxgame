--!strict
-- 9.2 you drive Danny's end (the owner, 8.9.5, carrying a Sofa with Danny: "the carrying is better, but it feels like
-- it's harder to control … figure it out and fix it so it's playable, really just this"; 8.9.4 hid the lag of his
-- server-held body by holding your walk back: its start waited 0.85 s in Studio, 2 s online). While Danny holds the far
-- end of a piece YOU lead, the server gives his body's physics to your client (server/PairHold.luau lead:
-- root:SetNetworkOwner(you)) and his model says so: PairLead (your UserId), PairLeadAt (his place in the piece's frame, at
-- its middle's height) and the ObjectValue PairLeadPiece (the piece's root). Every frame before the physics
-- (client/PairSteer.luau's step calls PairLead.step once it has turned your heading) his hold's constraints (server/
-- PairHold.luau's, named "PairHold" on his root: the AlignPosition along the ground, the lift up and down (its attribute
-- Lift), the AlignOrientation) get their goals from YOUR piece (welded to your root: your own simulation, nothing late)
-- × that place; your physics moves his body with the piece, with real velocity, so client/GaitPose.luau and his stride
-- show his legs walking backwards, forwards and sideways.
-- Roblox's rules this leans on:
--   * network ownership is per mechanism (assemblies joined by constraints share one owner): his body is one assembly
--     joined to nothing (his constraints have one attachment each, OneAttachment), so it is yours alone
--   * on the owner, what its own scripts write into a constraint is what its simulation uses (it does not replicate);
--     the positions and velocities that come out of it replicate to the server and to everybody (the server writes none
--     of these constraints while you drive him: a server write would replicate and undo yours)
--   * the owner runs a humanoid's state machine: his humanoid is kept in the Physics state here (no walk, turn or jump of
--     its own fights the constraints; the server put it there before he was yours: server/Npcs.luau carried)
--   * a part you own that you move (PivotTo) moves for everybody
--   * one attachment each: no reaction force or torque, nothing of his hold pushes or turns you
-- His place: the piece's frame a frame on (your root's velocity × dt: where the piece is after this physics step) ×
-- PairLeadAt; his height the floor under his end (a ray down within a step of the floor under you:
-- MoveHelperBrain.endRise, as the server finds it; the lift climbs at HoldClimb at most). Rigid there once settled
-- (PairCarry.catchUp: PairLead.Rigid, his turn Spin); the first catch-up glides at his place's speed + Glide, never a
-- snap; his place more than Jump studs off (a door's trip into or out of the house, its interior far off the map): put
-- there at once (PivotTo).
-- The house's walls (the Wall parts of every HouseInterior's Shell in workspace.Moves; never the bodies, Danny, the
-- pieces, the fixtures or the porch): a ray from the piece's middle to his place + his body's clearance (HoldWall.Clear)
-- and PairLead.Soft finds a wall along the piece (his goal is never past the clearance), and a ray from his place the way
-- your walk or your turn would move it finds one beside him (a corner, a side wall, a doorway's jamb). PairLead.walk /
-- PairLead.turn take away the part of your walk or turn that pushes his end further into either (PairCarry.wallShare,
-- PairCarry.wall, PairCarry.wallTurn: from Soft studs before the clearance, all of it there); along the wall stays.
-- Performance: one drive at a time; per frame a few attribute reads, up to three short rays at the walls (in a house:
-- along the piece, the way you walk, the way you turn) and two to four down (under you, under his end: the house's floor
-- first, else the ground); the house's walls and floors looked up every PairLead.Look s (each Shell's walls gathered
-- once).
--   PairLead.of(model)            the drive of Danny's body `model` when it is yours (its PairLead your UserId, its piece
--                                 and his hold's constraints there), else nil
--   PairLead.walk(drive, x, z)    your walk (x, z: a way) with the part pushing his end into a wall taken away
--   PairLead.turn(drive, from, to) -> heading   your heading's turn from `from` toward `to`, the part swinging his end
--                                 into a wall taken away
--   PairLead.step(drive, dt, root, humanoid)   his goals now (`root`, `humanoid`: yours; before the physics)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PairCarry = require(Shared:WaitForChild("PairCarry"))
local Brain = require(Shared:WaitForChild("MoveHelperBrain"))

local PairLead = {}

local NAME = "PairHold" -- (server/PairHold.luau's: his hold's constraints)
local PIECE = "PairLeadPiece"
local NOT_FLOOR = { "Npcs", "Zombies", "Cars", "Traffic", "BanditCars", "Animals", "Moves" } -- (server/MoveHelper.luau's)
local cfg = Config.MoveHelper
local player = Players.LocalPlayer

export type Drive = {
	model: Model,
	root: BasePart?,
	humanoid: Humanoid?,
	value: ObjectValue?,
	piece: BasePart?,
	at: CFrame?, -- his place in the piece's frame (PairLeadAt)
	align: AlignPosition?,
	orient: AlignOrientation?,
	lift: AlignPosition?,
	settled: boolean,
	last: Vector3?, -- his place a frame ago (its speed: the glide's)
	wallX: number, -- the wall at his end, the last step's ray: the way into it × the share of a walk or turn into it to go
	wallZ: number,
	armX: number, -- his place from your root (flat), the last step's
	armZ: number,
}

local current: Drive? = nil

-- ── The house's walls and floors (looked up every Look s) ──────────────────

local lookedAt = -math.huge
local wallsOf: { [Instance]: { BasePart } } = setmetatable({}, { __mode = "k" }) :: any -- (each Shell's Wall parts, gathered once)
local wallRay: RaycastParams? = nil -- (Include: the Wall parts; nil: no house)
local shellRay: RaycastParams? = nil -- (Include: the Shells: their floors)
local groundRay: RaycastParams? = nil -- (Exclude: the bodies, the cars, the pieces …)

local lookedFor: Model? = nil -- (his body, left out of the floor's rays)
local function look(now: number, body: Model)
	if now - lookedAt < cfg.PairLead.Look and groundRay and lookedFor == body then
		return
	end
	lookedAt, lookedFor = now, body
	local shells: { Instance } = {}
	local walls: { Instance } = {}
	local moves = workspace:FindFirstChild("Moves")
	for _, child in (if moves then moves:GetChildren() else {}) :: { Instance } do
		local shell = if child.Name == "HouseInterior" then child:FindFirstChild("Shell") else nil
		if shell then
			table.insert(shells, shell)
			local found = wallsOf[shell]
			if not found then
				local list: { BasePart } = {}
				for _, part in shell:GetChildren() do
					if part.Name == "Wall" and part:IsA("BasePart") and part.CanCollide then
						table.insert(list, part)
					end
				end
				wallsOf[shell] = list
				found = list
			end
			for _, part in found :: { BasePart } do
				table.insert(walls, part)
			end
		end
	end
	if #walls > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = walls
		wallRay = params
	else
		wallRay = nil
	end
	if #shells > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = shells
		params.RespectCanCollide = true
		shellRay = params
	else
		shellRay = nil
	end
	local ignore: { Instance } = {}
	for _, name in NOT_FLOOR do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	table.insert(ignore, body) -- (in workspace.Npcs already: never his own body all the same)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	groundRay = params
end

-- The floor under (x, z) a ray finds from `top` down `reach` studs (in a house its Shell's, else the ground's: never a
-- body, a car or a piece), nil when none.
local function floorUnder(x: number, z: number, top: number, reach: number): number?
	local from = Vector3.new(x, top, z)
	local down = Vector3.new(0, -reach, 0)
	local shells = shellRay
	if shells then
		local hit = workspace:Raycast(from, down, shells)
		if hit then
			return hit.Position.Y
		end
	end
	local ground = groundRay
	local hit = if ground then workspace:Raycast(from, down, ground) else nil
	return if hit then hit.Position.Y else nil
end

-- The house's wall a ray finds from `from` along the ground way (ux, uz) (a unit) within `reach` studs + his clearance +
-- Soft: (studs to it along the ray, the way into it along the ground: a unit, how square the ray meets it: the cosine,
-- studs along the ray × it = studs off the wall), nil: none (or no house).
local function wallAlong(from: Vector3, ux: number, uz: number, reach: number): (number?, number, number, number)
	local walls = wallRay
	if not walls then
		return nil, 0, 0, 0
	end
	local far = math.max(reach, 0) + cfg.HoldWall.Clear + math.max(cfg.PairLead.Soft, 0)
	local hit = workspace:Raycast(from, Vector3.new(ux, 0, uz) * far, walls)
	if not hit then
		return nil, 0, 0, 0
	end
	local n = hit.Normal -- (its face toward the ray: the way into it is against it)
	local ix, iz = -n.X, -n.Z
	local size = math.sqrt(ix * ix + iz * iz)
	if size > 1e-3 then
		ix, iz = ix / size, iz / size
	else
		ix, iz = ux, uz
	end
	return hit.Distance, ix, iz, math.clamp(ux * ix + uz * iz, 0, 1)
end

-- ── The drive ──────────────────────────────────────────────────────────────

-- His hold's constraints on his root (looked up again when one went: a new hold makes new ones).
local function constraintsOf(d: Drive, root: BasePart)
	local align, orient, lift = d.align, d.orient, d.lift
	if align and align.Parent == root and orient and orient.Parent == root and (lift == nil or lift.Parent == root) then
		return
	end
	d.align, d.orient, d.lift = nil, nil, nil
	for _, child in root:GetChildren() do
		if child.Name == NAME then
			if child:IsA("AlignOrientation") then
				d.orient = child
			elseif child:IsA("AlignPosition") then
				if child:GetAttribute("Lift") == true then
					d.lift = child
				else
					d.align = child
				end
			end
		end
	end
	d.settled, d.last = false, nil
end

function PairLead.of(model: Model?): Drive?
	if not model or not model.Parent or model:GetAttribute("PairLead") ~= player.UserId then
		current = nil
		return nil
	end
	local d = current
	if not d or d.model ~= model then
		d = { model = model, root = nil, humanoid = nil, value = nil, piece = nil, at = nil, align = nil, orient = nil, lift = nil,
			settled = false, last = nil, wallX = 0, wallZ = 0, armX = 0, armZ = 0 }
		current = d
	end
	local drive = d :: Drive
	local root = drive.root
	if not root or root.Parent ~= model then
		local found = model:FindFirstChild("HumanoidRootPart")
		root = if found and found:IsA("BasePart") then found else nil
		drive.root = root
		drive.humanoid = model:FindFirstChildOfClass("Humanoid")
	end
	local value = drive.value
	if not value or value.Parent ~= model then
		local found = model:FindFirstChild(PIECE)
		value = if found and found:IsA("ObjectValue") then found else nil
		drive.value = value
	end
	local piece = if value then value.Value else nil
	local at = model:GetAttribute("PairLeadAt")
	if not root or not piece or not piece:IsA("BasePart") or not piece.Parent or typeof(at) ~= "CFrame" then
		return nil
	end
	drive.at = at
	if drive.piece ~= piece then
		drive.piece = piece :: BasePart
		drive.settled, drive.last = false, nil -- (another piece: he glides to it)
		drive.wallX, drive.wallZ = 0, 0
	end
	constraintsOf(drive, root)
	if not drive.align or not drive.orient then
		return nil
	end
	return drive
end

-- His place now (the piece's frame × PairLeadAt), nil: none.
local function placeOf(d: Drive): Vector3?
	local piece, at = d.piece, d.at
	return if piece and at then (piece.CFrame * at).Position else nil
end

-- Two walls' takes (each the way into it × its share) as one: the same wall (their ways within a few degrees) the bigger
-- share once, else the first and then the second's (a corner).
local function both(x: number, z: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local a, b = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
	if a > 1e-3 and b > 1e-3 and (ax * bx + az * bz) / (a * b) > 0.99 then
		if a >= b then
			return PairCarry.wall(x, z, ax, az)
		end
		return PairCarry.wall(x, z, bx, bz)
	end
	x, z = PairCarry.wall(x, z, ax, az)
	return PairCarry.wall(x, z, bx, bz)
end

function PairLead.walk(d: Drive, x: number, z: number): (number, number)
	local length = math.sqrt(x * x + z * z)
	local place = placeOf(d)
	local sx, sz = 0, 0
	if place and length > 1e-3 then
		-- a wall beside his end the way your walk moves it (a side wall, a corner, a doorway's jamb)
		local dist, ix, iz, square = wallAlong(place, x / length, z / length, 0)
		if dist then
			local share = PairCarry.wallShare(dist * square) -- (studs off it)
			sx, sz = ix * share, iz * share
		end
	end
	return both(x, z, d.wallX, d.wallZ, sx, sz) -- (and a wall along the piece: the last step's ray from its middle)
end

function PairLead.turn(d: Drive, from: number, to: number): number
	local ax, az = d.armX, d.armZ
	local wx, wz = d.wallX, d.wallZ -- (a wall along the piece: the last step's ray from its middle)
	local turn = PairCarry.wrap(to - from)
	local place = placeOf(d)
	if place and math.abs(turn) > 1e-6 then
		-- a wall beside his end the way your turn swings it (his arm about your root turned by it)
		local c, s = math.cos(turn), math.sin(turn)
		local dx, dz = ax * c + az * s - ax, -ax * s + az * c - az
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 1e-4 then
			local dist, ix, iz, square = wallAlong(place, dx / length, dz / length, length)
			if dist then
				local share = PairCarry.wallShare((dist - length) * square) -- (studs off it after this swing)
				local a, b = math.sqrt(wx * wx + wz * wz), share
				if a > 1e-3 and b > 1e-3 and (wx * ix + wz * iz) / a > 0.99 then
					if b > a then
						wx, wz = ix * share, iz * share -- (the same wall: its bigger share once)
					end
				else
					to = PairCarry.wallTurn(from, to, ax, az, ix * share, iz * share)
				end
			end
		end
	end
	return PairCarry.wallTurn(from, to, ax, az, wx, wz)
end

function PairLead.step(d: Drive, dt: number, root: BasePart, humanoid: Humanoid)
	local body, piece, align, orient, at = d.root, d.piece, d.align, d.orient, d.at
	if not body or not piece or not align or not orient or not at then
		return
	end
	local lead = cfg.PairLead
	look(os.clock(), d.model)
	-- his humanoid in the Physics state (its owner runs its state machine: yours now), no turn or jump of its own
	local his = d.humanoid
	if his then
		if his:GetState() ~= Enum.HumanoidStateType.Physics then
			his:ChangeState(Enum.HumanoidStateType.Physics)
		end
		if his.AutoRotate then
			his.AutoRotate = false
		end
		if his.Jump then
			his.Jump = false
		end
	end
	-- the piece where it is after this physics step: your walk's (the turn is in its frame already)
	local v = root.AssemblyLinearVelocity
	local ahead = if v and dt > 0 then Vector3.new(v.X, 0, v.Z) * math.min(dt, 0.1) else Vector3.zero
	local frame = piece.CFrame + ahead
	local goal = frame * at
	local middle = frame.Position
	-- the house's walls along the piece: a ray from its middle to his place, his clearance and Soft on
	d.wallX, d.wallZ = 0, 0
	local outX, outZ = goal.X - middle.X, goal.Z - middle.Z
	local length = math.sqrt(outX * outX + outZ * outZ)
	if length > 0.05 then
		local ux, uz = outX / length, outZ / length
		local dist, ix, iz, square = wallAlong(middle, ux, uz, length)
		if dist then
			local room = (dist - length) * square -- (studs from his place to the wall, square off it)
			local share = PairCarry.wallShare(room)
			d.wallX, d.wallZ = ix * share, iz * share
			local clear = cfg.HoldWall.Clear
			if room < clear then
				-- never past his clearance off it: pushed back square off the wall (along it he stays)
				local back = clear - room
				goal = CFrame.new(goal.X - ix * back, goal.Y, goal.Z - iz * back) * goal.Rotation
			end
		end
	end
	d.armX, d.armZ = goal.X - root.Position.X, goal.Z - root.Position.Z
	-- his height: the floor under his end within a step of the floor under you (a ray down from your root: never your
	-- height, a jump or a fall off a ledge never lifts him), from a step over it down to a step under it (never a porch's
	-- roof, a ceiling or an eave over his end: server/MoveHelper.luau endOffset's rule)
	local step = cfg.HoldStep
	local stand = (if his then his.HipHeight else 2) + body.Size.Y / 2
	local mine = root.Position
	local base = floorUnder(mine.X, mine.Z, mine.Y, 40) or (mine.Y - (humanoid.HipHeight + root.Size.Y / 2))
	local found = floorUnder(goal.X, goal.Z, base + step, 2 * step + 1)
	local rise = Brain.endRise(if found then found + stand - frame.Y else 0 / 0, base + stand - frame.Y)
	local height = frame.Y + rise
	-- far off (a door's trip): there at once (yours: it replicates). How far off: from his goal as it is this moment
	-- (before the physics step's walk: where his body should be now)
	local here = body.Position
	local gap = Vector3.new(goal.X - ahead.X - here.X, 0, goal.Z - ahead.Z - here.Z).Magnitude
	if gap > lead.Jump then
		d.model:PivotTo(CFrame.new(goal.X, height, goal.Z) * goal.Rotation)
		body.AssemblyLinearVelocity = Vector3.zero
		d.last, gap = nil, 0
	end
	-- the catch-up: rigid at his place once there, else a glide at his place's speed + Glide
	local last = d.last
	local speed = if last and dt > 1e-4 then Vector3.new(goal.X - last.X, 0, goal.Z - last.Z).Magnitude / dt else 0
	d.last = goal.Position
	local limit, settled = PairCarry.catchUp(gap, speed, d.settled)
	d.settled = settled
	if math.abs(align.MaxVelocity - limit) > 0.01 then
		align.MaxVelocity = limit
	end
	local spin = if settled then lead.Spin else Brain.holdTurn()
	if math.abs(orient.MaxAngularVelocity - spin) > 1e-4 then
		orient.MaxAngularVelocity = spin
	end
	align.Position = goal.Position
	orient.CFrame = goal.Rotation
	local lift = d.lift
	if lift then
		lift.Position = Vector3.new(goal.X, height, goal.Z)
	end
end

return PairLead
