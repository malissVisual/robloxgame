-- 8.3 (the owner: "he just jumps weirdly"): the real client/PairSteer.luau, the leader's side of carrying in two
-- (tests/run_tests.py builds PairSteerClient.luau: a function of its globals), on the item recorder's body: while your
-- character carries a piece in two (PairTurn) no jump (Humanoid.Jump cleared every step before the physics: a jump
-- lifted the piece and Danny with it), AutoRotate off and the heading PairTurn degrees a second at most (8.1); let go,
-- AutoRotate back on (8.1) and your jumps your own again (nothing switched off: a bus ride's own jump lock untouched).
-- 8.3 (the owner: "when I run, he just goes behind me with his arms stretched out"): nobody runs with a move's piece:
-- its walk held at the server's CarrySpeed every step before the physics whatever wrote
-- Humanoid.WalkSpeed (a sprint's 28, client/CameraRig.luau's bleed-off); in two (CarryPair: the leader and the far end's
-- crew mate) the run key says Config.MoveHelper.RunHint once a carry; let go, your walk is yours again.
-- 9.2 (the owner, 8.9.5: "the carrying is better, but it feels like it's harder to control … fix it so it's playable"):
-- Danny at the far end of the piece you lead is yours to drive (his model's PairLead your UserId, PairLeadAt, the
-- ObjectValue PairLeadPiece: the real client/PairLead.luau, built as PairLeadClient.luau): your walk at the pair's carry
-- speed at once (no PairStart, no waits, no keep), the heading at PairLead.Turn, his hold's goals set from YOUR piece
-- this very step (its turn in it, a frame on by your velocity: no lag), his humanoid kept in the Physics state, his
-- first catch-up a glide and rigid after, a door's jump put there at once, a wall of the house at his end your own ray:
-- the walk into it goes, his goal never past his clearance. A far end the server holds (a crew mate's) keeps 9.0's way.
local E = require("./MovingRuntime") -- (the recorder with a CFrame's LookVector)
local PairCarry = require("./PairCarry")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local M = E.Mock
local V3 = M.Vector3.new

-- your character: a root facing -Z, a humanoid walking
local character = M.Instance.new("Model")
character.Name = "You"
local root = M.Instance.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = M.CFrame.new(0, 3, 0)
root.Size = V3(2, 2, 1)
root.Parent = character
local humanoid = M.Instance.new("Humanoid")
humanoid.Name = "Humanoid"
humanoid.HipHeight = 2 -- (your feet on the floor at 0)
humanoid.AutoRotate = true
humanoid.Jump = false
humanoid.MoveDirection = V3(0, 0, 0)
humanoid.SeatPart = nil
humanoid.Health = 100
humanoid.Parent = character
local moved: any = nil -- 9.0 the last Humanoid:Move this module made (this physics step's walk)
humanoid.Move = function(self: any, direction: any, _relative: boolean)
	moved = direction
	self.MoveDirection = direction
end
local playerAttributes: { [string]: any } = {}
local localPlayer = { UserId = 77, Character = character, GetAttribute = function(_: any, name: string): any
	return playerAttributes[name]
end }
-- 9.0 the far end's holder: Danny's body in workspace.Npcs (its MoveHelper attribute his id), a crew mate's character
local npcs = M.Instance.new("Folder")
npcs.Name = "Npcs"
local dannyBody = M.Instance.new("Model")
dannyBody.Name = "Danny"
dannyBody:SetAttribute("MoveHelper", -7)
local dannyRoot = M.Instance.new("Part")
dannyRoot.Name = "HumanoidRootPart"
dannyRoot.CFrame = M.CFrame.new(0, 3, -9)
dannyRoot.Parent = dannyBody
dannyBody.Parent = npcs
-- 9.2 the house (workspace.Moves: a HouseInterior with its Shell's Wall), a wall of it across +X at wallX (its face
-- toward -X) when set; the floor at 0
local moves = M.Instance.new("Folder")
moves.Name = "Moves"
local interior = M.Instance.new("Model")
interior.Name = "HouseInterior"
interior.Parent = moves
local shell = M.Instance.new("Folder")
shell.Name = "Shell"
shell.Parent = interior
local wallPart = M.Instance.new("Part")
wallPart.Name = "Wall"
wallPart.Parent = shell
local wallX: number? = nil
local wallRays = 0
local fakeWorkspace = { FindFirstChild = function(_: any, name: string): any
	return if name == "Npcs" then npcs elseif name == "Moves" then moves else nil
end, Raycast = function(_: any, origin: any, direction: any, params: any): any
	if math.abs(direction.X) < 1e-6 and math.abs(direction.Z) < 1e-6 then
		return { Position = V3(origin.X, 0, origin.Z), Normal = V3(0, 1, 0), Distance = origin.Y } -- (the floor)
	end
	wallRays += 1
	local x = wallX
	if params.FilterType ~= "Include" or x == nil or direction.X <= 1e-9 then
		return nil
	end
	local t = (x - origin.X) / direction.X
	if t <= 0 or t > 1 then
		return nil
	end
	return { Instance = wallPart, Position = origin + direction * t, Distance = direction.Magnitude * t, Normal = V3(-1, 0, 0) }
end }
local game = { GetService = function(_: any, name: string): any
	if name == "Players" then
		return { LocalPlayer = localPlayer, GetPlayerByUserId = function(_: any, _id: number): any
			return nil -- (Danny's id is no player's)
		end, GetPlayers = function(): any
			return { localPlayer }
		end }
	elseif name == "RunService" then
		return { PreSimulation = { Connect = function() end } }
	end
	return { WaitForChild = function(self: any, child: string): any
		return { Name = child, WaitForChild = self.WaitForChild }
	end }
end }
local function requireOf(module: any): any
	if module.Name == "PairLead" then -- (9.2 its script.Parent's: the real client/PairLead.luau)
		return require("./PairLeadClient")(game, requireOf, M.CFrame, M.typeof, M.Vector3, fakeWorkspace, os, M.Enum, M.RaycastParams)
	end
	return require(`./{module.Name}`)
end
local script = { Parent = { WaitForChild = function(_: any, name: string): any
	return { Name = name }
end } }
local PairSteer = require("./PairSteerClient")(game, requireOf, M.CFrame, M.typeof, M.Vector3, fakeWorkspace, script)

local function heading(): number
	local look = root.CFrame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end

-- carrying alone: your jumps are yours
humanoid.Jump = true
PairSteer.step(1 / 60)
check("carrying nothing in two: a jump is yours, AutoRotate on", humanoid.Jump == true and humanoid.AutoRotate == true and not PairSteer.steering())

-- carrying in two (Danny at the far end: PairTurn)
character:SetAttribute("PairTurn", Config.MoveHelper.PairTurn)
humanoid.Jump = true -- (Space, the touch jump button)
PairSteer.step(1 / 60)
check("8.3 carrying in two: no jump (Humanoid.Jump cleared before the physics step), AutoRotate off", humanoid.Jump == false and humanoid.AutoRotate == false
	and PairSteer.steering())
local most = 0
for _ = 1, 30 do
	humanoid.Jump = true -- (Space held: asked again every frame)
	humanoid.MoveDirection = V3(1, 0, 0) -- (the way to your right)
	local before = heading()
	PairSteer.step(0.1)
	most = math.max(most, math.abs(PairCarry.wrap(heading() - before)))
	if humanoid.Jump then
		break
	end
end
check("8.3 …Space held while walking and turning: never a jump", humanoid.Jump == false)
check("8.1 …the heading turns PairTurn degrees a second at most", most > 0 and most <= math.rad(Config.MoveHelper.PairTurn) * 0.1 + 1e-9, math.deg(most) * 10)

-- let go: AutoRotate back, jumps yours again
character:SetAttribute("PairTurn", nil)
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(1 / 60)
humanoid.Jump = true
PairSteer.step(1 / 60)
check("8.1 let go: AutoRotate on again; 8.3 your jump yours again (nothing was switched off)", humanoid.AutoRotate == true and humanoid.Jump == true
	and not PairSteer.steering() and PairSteer.walk() == 1)

-- 8.3 nobody runs with a move's piece --------------------------------------------------------------------------------------

local hints: { string } = {}
PairSteer.notify = function(text: string)
	table.insert(hints, text)
end
humanoid.WalkSpeed = 28
character:SetAttribute("MoveCarry", 3) -- (a move's piece in your hands alone: the server's CarrySpeed)
character:SetAttribute("CarrySpeed", 10.5)
PairSteer.step(1 / 60)
check("8.3 a move's piece in your hands: the walk held at its CarrySpeed before the physics (a sprint's 28 cut to 10.5)",
	humanoid.WalkSpeed == 10.5 and PairSteer.cap() == 10.5 and not PairSteer.holding(), humanoid.WalkSpeed)
humanoid.WalkSpeed = 6
PairSteer.step(1 / 60)
PairSteer.refuseRun()
check("…a slower walk (a turn, a stagger) left as it is; alone, the run key says nothing", humanoid.WalkSpeed == 6 and #hints == 0)
-- the leader of a piece carried in two (Danny or a crew mate at its far end): Shift held, the sprint asked every frame
character:SetAttribute("PairTurn", Config.MoveHelper.PairTurn)
character:SetAttribute("CarryPair", true)
local fastest = 0
for _ = 1, 120 do
	humanoid.WalkSpeed = 28 -- (the sprint's speed, written before every physics step: Shift, the stick click, a script)
	humanoid.MoveDirection = V3(0, 0, -1)
	PairSteer.step(1 / 60)
	fastest = math.max(fastest, humanoid.WalkSpeed)
end
check("8.3 the leader sprints while carrying in two: the walk stays at CarrySpeed every step (2 s of Shift)", fastest == 10.5 and PairSteer.holding(), fastest)
PairSteer.refuseRun()
PairSteer.refuseRun()
PairSteer.refuseRun()
check(`…the run key says "{Config.MoveHelper.RunHint}" once a carry`, #hints == 1 and hints[1] == Config.MoveHelper.RunHint
	and Config.MoveHelper.RunHint == "Too heavy to run with", #hints)
playerAttributes.AdminSpeed = 2 -- (10.6: the city's admin walk multiplier; nothing sets it any more)
humanoid.WalkSpeed = 50
PairSteer.step(1 / 60)
check("…10.6: no admin's or kit's boost (a stray AdminSpeed changes nothing): held at CarrySpeed", humanoid.WalkSpeed == 10.5 and PairSteer.cap() == 10.5, humanoid.WalkSpeed)
playerAttributes.AdminSpeed = nil
-- let go: your walk is yours again, and the next carry in two says it again
for _, name in { "MoveCarry", "CarrySpeed", "PairTurn", "CarryPair" } do
	character:SetAttribute(name, nil)
end
humanoid.MoveDirection = V3(0, 0, 0)
humanoid.WalkSpeed = 28
PairSteer.step(1 / 60)
PairSteer.refuseRun()
check("8.3 let go: the sprint yours again (nothing held), no hint", humanoid.WalkSpeed == 28 and PairSteer.cap() == nil and #hints == 1)
-- the far end's crew mate (CarryPair, no PairTurn: the server holds their body; their walk held too)
character:SetAttribute("MoveCarry", 3)
character:SetAttribute("CarrySpeed", 9.8)
character:SetAttribute("CarryPair", true)
humanoid.AutoRotate = true
PairSteer.step(1 / 60)
PairSteer.refuseRun()
PairSteer.refuseRun()
check("8.3 a crew mate at the far end: the same rule (walk held at CarrySpeed, the hint once this carry), their body not steered",
	humanoid.WalkSpeed == 9.8 and #hints == 2 and humanoid.AutoRotate == true and not PairSteer.steering() and PairSteer.holding(), humanoid.WalkSpeed)
for _, name in { "MoveCarry", "CarrySpeed", "CarryPair" } do
	character:SetAttribute(name, nil)
end
PairSteer.step(1 / 60)

-- 9.0 (the owner, 8.9.3: "When I want to walk forwards, Danny can't walk backwards"; his screenshot of Danny inside the
-- Sofa): your screen shows your partner late (the server holds him), the piece in your hands at once. 9.2: a far end the
-- server holds only (a crew mate's; Danny's when nobody drives him): his model has no PairLead here ----------------------

local K = Config.MoveHelper.PairKeep
character:SetAttribute("PairTurn", Config.MoveHelper.PairTurn)
root.CFrame = M.CFrame.new(0, 3, 0) -- (facing -Z: Danny ahead of you across the piece)
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(1 / 60)
local eased: { number } = {}
for _ = 1, 8 do
	humanoid.MoveDirection = V3(0, 0, -1) -- (forwards, toward him)
	PairSteer.step(0.1)
	table.insert(eased, PairSteer.walk())
end
check("9.0 standing, then forwards: the walk eases in over PairStart s (never at once from standing)", eased[1] < 0.3 and eased[3] > eased[1]
	and eased[3] < 1 and eased[8] == 1, table.concat(eased, ", "))
-- Danny's place in your root's frame (PairFar) and who he is (PairWith: his id, his body in workspace.Npcs)
character:SetAttribute("PairWith", -7)
character:SetAttribute("PairFar", V3(0, 0, -9))
moved = nil
humanoid.MoveDirection = V3(0, 0, -1)
PairSteer.step(0.1)
check("9.0 your screen shows him at his place: your walk toward him as it is", moved == nil and PairSteer.walk() == 1)
dannyRoot.CFrame = M.CFrame.new(0, 3, -9 + K.Stop + 0.2) -- (shown nearer than his place: the piece into him on your screen)
humanoid.MoveDirection = V3(0, 0, -1)
PairSteer.step(0.1)
check("9.0 …shown PairKeep.Stop studs nearer or more: your walk toward him goes (never the piece pushed into him on your screen)",
	moved ~= nil and math.abs(moved.Z) < 1e-6, moved and moved.Z)
moved = nil
humanoid.MoveDirection = V3(1, 0, 0)
PairSteer.step(0.1)
local sideways = moved == nil
moved = nil
humanoid.MoveDirection = V3(0, 0, 1)
PairSteer.step(0.1)
check("9.0 …sideways or backwards (away from him): your walk as it is", sideways and moved == nil)
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(0.1)
dannyRoot.CFrame = M.CFrame.new(0, 3, -9 + (K.Wait + K.From) / 2) -- (a little nearer: not yet into him)
local held: { number } = {}
for _ = 1, 4 do
	moved = nil
	humanoid.MoveDirection = V3(0, 0, -1)
	PairSteer.step(0.1)
	table.insert(held, PairSteer.walk())
end
check("9.0 …shown a little nearer from standing: the start waits for him (the walk held, not slowed), your walk untouched",
	held[1] > 0 and held[4] == held[1] and moved == nil, table.concat(held, ", "))
dannyRoot.CFrame = M.CFrame.new(0, 3, -9)
-- his end against a wall of the house (the server's PairWall: the way into it × the share to take away)
character:SetAttribute("PairWall", V3(0, 0, -1))
moved = nil
humanoid.MoveDirection = V3(0, 0, -1)
PairSteer.step(0.1)
local stopped = moved ~= nil and math.abs(moved.Z) < 1e-6
character:SetAttribute("PairWall", V3(0, 0, -0.5))
moved = nil
humanoid.MoveDirection = V3(0.6, 0, -0.8)
PairSteer.step(0.1)
check("9.0 his end against a wall (PairWall): your walk into it goes (all of it at a full share, half at half), along it as ever",
	stopped and moved ~= nil and math.abs(moved.Z + 0.4) < 1e-6 and math.abs(moved.X - 0.6) < 1e-6, moved and `{moved.X} {moved.Z}`)
for _, name in { "PairTurn", "PairWith", "PairFar", "PairWall" } do
	character:SetAttribute(name, nil)
end
humanoid.MoveDirection = V3(0, 0, 0)
PairSteer.step(1 / 60)
check("9.0 let go: your walk yours again", PairSteer.walk() == 1 and not PairSteer.steering())

-- 9.2 you drive Danny's end ----------------------------------------------------------------------------------------------

do
	local L = Config.MoveHelper.PairLead
	local CF = M.CFrame.new
	-- the piece welded 5 studs in front of your root (its frame always your root's × that: a weld moves with the root)
	local pieceAt = CF(0, -0.5, -5)
	local piece = setmetatable({ Name = "Root", Parent = character }, { __index = function(_: any, key: string): any
		if key == "CFrame" then
			return root.CFrame * pieceAt
		elseif key == "Position" then
			return (root.CFrame * pieceAt).Position
		elseif key == "IsA" then
			return function(_: any, class: string): boolean
				return class == "BasePart"
			end
		end
		return nil
	end })
	-- his body: his root (where his place was a moment ago), his humanoid (its state, the owner's to keep), his hold's
	-- constraints (server/PairHold.luau's: named PairHold, the lift by its attribute)
	dannyRoot.Size = V3(2, 2, 1)
	dannyBody.PrimaryPart = dannyRoot
	local his = M.Instance.new("Humanoid")
	his.Name = "Humanoid"
	his.HipHeight = 2
	local state = "Running"
	local changed: { string } = {}
	his.GetState = function(): string
		return state
	end
	his.ChangeState = function(_: any, to: string)
		state = to
		table.insert(changed, to)
	end
	his.Parent = dannyBody
	local function made(class: string, lift: boolean?): any
		local c = M.Instance.new(class)
		c.Name = "PairHold"
		c.MaxVelocity = 20
		c.MaxAngularVelocity = 3
		if lift then
			c:SetAttribute("Lift", true)
		end
		c.Parent = dannyRoot
		return c
	end
	local align, lift, orient = made("AlignPosition"), made("AlignPosition", true), made("AlignOrientation")
	-- his place in the piece's frame: 4.2 studs past its middle along -Z, turned back to it
	local at = CF(0, 0, -4.2) * M.CFrame.Angles(0, math.pi, 0)
	local value = M.Instance.new("ObjectValue")
	value.Name = "PairLeadPiece"
	value.Value = piece
	value.Parent = dannyBody
	dannyBody:SetAttribute("PairLeadAt", at)
	dannyBody:SetAttribute("PairLead", localPlayer.UserId) -- (the server's last word: yours to drive)
	character:SetAttribute("PairTurn", Config.MoveHelper.PairTurn)
	character:SetAttribute("PairWith", -7)
	root.CFrame = CF(0, 3, 0) -- (facing -Z: Danny ahead across the piece)
	dannyRoot.CFrame = CF(0, 3, -7.2) -- (2 studs short of his place: he glides there)
	root.AssemblyLinearVelocity = V3(0, 0, 0)
	humanoid.MoveDirection = V3(0, 0, 0)
	PairSteer.step(1 / 60)
	local place = (piece.CFrame * at).Position
	check("9.2 your drive: his hold's goals from YOUR piece this step (his place, turned to it), his height the floor under his end",
		(align.props.Position - place).Magnitude < 1e-6 and orient.CFrame.LookVector:Dot(V3(0, 0, 1)) > 0.999
		and math.abs(lift.props.Position.Y - (0 + his.HipHeight + dannyRoot.Size.Y / 2)) < 1e-6 and (V3(lift.props.Position.X, 0, lift.props.Position.Z) - V3(place.X, 0, place.Z)).Magnitude < 1e-6,
		`{align.props.Position} vs {place}`)
	check("9.2 …his humanoid kept in the Physics state (the owner runs its state machine: yours now)", state == "Physics" and changed[1] == "Physics")
	check("9.2 …2 studs off his place: his first catch-up glides (his place's speed + Glide, not rigid, his turn at holdTurn)",
		math.abs(align.MaxVelocity - L.Glide) < 1e-6 and orient.MaxAngularVelocity < L.Spin, align.MaxVelocity)
	-- forwards, toward him, from standing: the pair's walk at once (9.0: eased in over PairStart s, waiting for him)
	dannyRoot.CFrame = CF(place.X, 3, place.Z) * M.CFrame.Angles(0, math.pi, 0) -- (there)
	moved = nil
	humanoid.MoveDirection = V3(0, 0, -1)
	root.AssemblyLinearVelocity = V3(0, 0, -10)
	PairSteer.step(0.1)
	local first = PairSteer.walk()
	local ahead = (root.CFrame * pieceAt + V3(0, 0, -10) * 0.1) * at
	check("9.2 forwards toward him from standing: the pair's walk at once (walk × 1 the first step), never held (no Move of this module's)",
		first == 1 and moved == nil, first)
	check("9.2 …his goal where the piece will be after this physics step (your velocity × dt on): no lag on your screen; rigid once there",
		(align.props.Position - ahead.Position).Magnitude < 1e-6 and align.MaxVelocity == L.Rigid and orient.MaxAngularVelocity == L.Spin,
		`{(align.props.Position - ahead.Position).Magnitude} off, {align.MaxVelocity}`)
	-- the turn: to your right, 0.1 s steps: PairLead.Turn degrees a second (PairTurn's 60 a crew mate's)
	root.AssemblyLinearVelocity = V3(0, 0, 0)
	local most = 0
	for _ = 1, 5 do
		humanoid.MoveDirection = V3(1, 0, 0)
		local before = heading()
		PairSteer.step(0.1)
		most = math.max(most, math.abs(PairCarry.wrap(heading() - before)))
		local goalNow = (piece.CFrame * at).Position
		dannyRoot.CFrame = CF(goalNow.X, 3, goalNow.Z) -- (the physics: there)
	end
	check(`9.2 …the heading turns PairLead.Turn ({L.Turn}) degrees a second while you drive him (PairTurn {Config.MoveHelper.PairTurn}: a crew mate's)`,
		math.abs(most - math.rad(L.Turn) * 0.1) < 1e-6 and L.Turn > Config.MoveHelper.PairTurn, math.deg(most) * 10)
	check("9.2 …his goal turned with your piece in the same step (the turn first, then his goals)", (align.props.Position - (piece.CFrame * at).Position).Magnitude < 1e-6)
	-- a wall of the house at his end: face +X, his place out there; the wall 0.3 studs past his clearance + Soft / 2
	root.CFrame = CF(0, 3, 0) * M.CFrame.Angles(0, -math.pi / 2, 0)
	humanoid.MoveDirection = V3(0, 0, 0)
	PairSteer.step(1 / 60)
	local farX = (piece.CFrame * at).Position.X
	local clear = Config.MoveHelper.HoldWall.Clear
	wallX = farX + clear + L.Soft / 2
	PairSteer.step(1 / 60) -- (his ray finds it)
	moved = nil
	humanoid.MoveDirection = V3(1, 0, 0)
	PairSteer.step(1 / 60)
	local half = moved
	wallX = farX + clear - 0.05
	humanoid.MoveDirection = V3(0, 0, 0)
	PairSteer.step(1 / 60)
	moved = nil
	humanoid.MoveDirection = V3(0.6, 0, 0.8)
	PairSteer.step(1 / 60)
	local along = moved
	check("9.2 a wall of the house at his end (your own ray): Soft / 2 before his clearance half your walk into it goes, at it all of it; along it stays",
		wallRays > 0 and half ~= nil and math.abs(half.X - 0.5) < 1e-6 and along ~= nil and math.abs(along.X) < 1e-6 and math.abs(along.Z - 0.8) < 1e-6,
		`{half and half.X} / {along and along.X}, {along and along.Z}`)
	wallX = farX - 1 -- (nearer than his place: the piece pokes into it)
	root.CFrame = CF(0, 3, 0) * M.CFrame.Angles(0, -math.pi / 2, 0)
	humanoid.MoveDirection = V3(0, 0, 0)
	PairSteer.step(1 / 60)
	check("9.2 …his goal never past his clearance off the wall (the piece may poke into it, his body stays out)", align.props.Position.X <= wallX - clear + 1e-6,
		`{align.props.Position.X} vs {wallX - clear}`)
	wallX = nil
	-- a door's trip: your body and the piece 300 studs on at once (the server's): his place far off → put there at once
	root.CFrame = CF(300, 3, 0) * M.CFrame.Angles(0, -math.pi / 2, 0)
	PairSteer.step(1 / 60)
	local there = (piece.CFrame * at).Position
	check("9.2 a door's trip (his place Jump studs off or more): he is put there at once (PivotTo: yours, it replicates)",
		(V3(dannyRoot.Position.X, 0, dannyRoot.Position.Z) - V3(there.X, 0, there.Z)).Magnitude < 1e-6 and align.MaxVelocity == L.Rigid,
		dannyRoot.Position)
	-- let go (the server's PairLead gone): his goals are no longer yours, your walk as a far end the server holds
	dannyBody:SetAttribute("PairLead", nil)
	local kept = align.props.Position
	humanoid.MoveDirection = V3(0, 0, -1)
	root.CFrame = CF(300, 3, 0)
	PairSteer.step(0.1)
	check("9.2 the server took him back (no PairLead): this client writes none of his goals any more", align.props.Position == kept)
	for _, name in { "PairTurn", "PairWith" } do
		character:SetAttribute(name, nil)
	end
	humanoid.MoveDirection = V3(0, 0, 0)
	PairSteer.step(1 / 60)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
