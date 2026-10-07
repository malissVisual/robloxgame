--!strict
-- 6.1: the plastic bag in a courier's hand swings behind them (the owner's wish: "the bag just flutters behind you"), on
-- every player's character within Config.Courier.Bag.Range of the camera (yours always), every frame in
-- RunService.PreSimulation. The only writer of the BagSwing joint's Transform (server/KitWear.luau hangs KitBagPivot from
-- the left hand by that Motor6D; client/SprintPose.luau no longer touches it).
--
-- shared/BagSwing.luau is the pendulum: a damped spring driven by the grip's real acceleration (it trails when you start,
-- swings forward when you stop, out on a turn) and the speed's air (it leans back at a run), a flutter and a twist at
-- speed. Here its tilt becomes a world orientation: the bag's broad sides along your facing (its +X to your right, as it
-- hangs), its up axis leaning away from where its bottom has gone, turned about the handles by the twist; the Transform
-- is that orientation seen from the grip (the hand · C0), straight from the hand's frame each frame. (6.0 built it from
-- the pivot's last solved CFrame and its old Transform: any frame the pivot was not solved again compounded the
-- error; with the step jolt at 8 Hz and the flutter on top, the bag jittered and blinked.)
-- A character's joint is looked up once (again when it leaves the body, every LOOK seconds while it has none); out of
-- range or gone, the joint goes back to the identity once and its swing is forgotten.
-- 6.4: each bag swings with its own tuning (the pivot's Bag attribute, Config.Courier.Bags): a tote a little slower,
-- the thermal and the padded bag heavy and boxy, the duffel slow with hardly any flutter. Each way of wearing it (the
-- pivot's Worn attribute, server/KitWear.luau: "hand" | "shoulder" | "hip" | "back") its own motion: in the hand the
-- pendulum, on the shoulder or the hip a stiff little swing (Config.Courier.Wear) and a bounce with the steps
-- (BagSwing.bob, Bounce), on the back a soft bob (BackBob). When the bag moves between the front and the back (the
-- character's BagSwitchAt, the server time: the new pivot replaces the old one) it starts where it was, relative to
-- the body, and moves to its new place over Config.Courier.Switch seconds while the sling / unsling gesture plays
-- (client/ArmPose.luau). Still the joint's only writer.
-- 6.4.1: the joint may hang from an R6 body's "Left Arm" or "Torso" (server/KitWear.luau, KitFit.R6): it is found by
-- its pivot, whatever its Part0. The Transform stays a rotation about the grip in the hand (and a few hundredths of a
-- stud of bounce elsewhere), so the bag never leaves its place. And once per spawn, Config.Courier.BagCheck.After
-- seconds after your bag shows (the character's BagWorn attribute), a look whether it really is on you; when not, the
-- Output says why, for the owner to paste: no parts, all see-through, or farther than BagCheck.Far studs from your hand
-- or from its place, e.g. "[BagSway] your bag is 37.2 studs from your hand (style hand, joint LeftHand → KitBagPivot,
-- C0 (0.00, -0.27, 0.00), Transform (0.00, 0.00, 0.00))".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BagSwing = require(Shared.BagSwing)
local Bodies = require(script.Parent.Bodies)

local BagSway = {}

local B = Config.Courier.Bag
local C = Config.Courier -- 6.4: Bounce, BackBob, Step, Switch, Wear
local SWITCH = math.max(0.05, C.Switch)
local WEAR = BagSwing.tuning(B :: any, C.Wear) -- 6.4: a bag on the shoulder or the hip: a stiff little swing
local LOOK = 0.4 -- seconds between the looks for a bag on a character that has none
local CHECK = Config.Courier.BagCheck -- 6.4.1: the look whether your bag is really on you
local SWEEP = 5 -- seconds between the clean-ups of the characters that are gone

-- 6.4: every bag's own swing (Config.Courier.Bags over Bag: the bigger, the heavier), made once per bag id. The pivot's
-- Bag attribute (server/KitWear.luau) names the bag in that hand.
local tunings: { [string]: BagSwing.Tuning } = {}
local function tuningOf(pivot: Instance?): BagSwing.Tuning
	local id = if pivot then pivot:GetAttribute("Bag") else nil
	local key = if type(id) == "string" then id else Config.Courier.BagKit
	local made = tunings[key]
	if not made then
		made = BagSwing.tuning(B :: any, Config.Courier.Bags[key])
		tunings[key] = made
	end
	return made
end

type Rec = {
	joint: Motor6D?,
	hand: BasePart?,
	state: BagSwing.State,
	nextLook: number,
	written: boolean, -- a Transform of ours is on the joint
	tuning: BagSwing.Tuning, -- 6.4: this bag's swing
	worn: string, -- 6.4: "hand" | "shoulder" | "hip" | "back" (the pivot's Worn attribute)
	walked: number, -- 6.4: studs walked (the steps' bounce)
	rel: CFrame?, -- 6.4: the bag's last pose relative to the body (a move to the back or the front starts there) …
	from: CFrame?, -- … the pose the running move started from, and the move's start (the server time)
	fromAt: number,
	relBag: string?, -- (the bag that pose was of)
}

local recs: { [Model]: Rec } = {}
local checks: { [Model]: number | boolean } = {} -- 6.4.1: your body → when its bag showed (os.clock), true: looked
local missingSince: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- 6.5.1: Hand "bag", no BagWorn since
local missingTold: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local sweptAt = 0
local handVec = { 0, 0, 0 } -- (reused every frame)
local bodyVec = { 0, 0, 0 }

-- The bag's joint on this character (nil without a bag: in a seat, stowed, another hand).
local function find(character: Model): (Motor6D?, BasePart?)
	local pivot = character:FindFirstChild("KitBagPivot")
	local joint = if pivot then pivot:FindFirstChild("BagSwing") else nil
	if joint and joint:IsA("Motor6D") then
		local hand = joint.Part0
		if hand and hand:IsA("BasePart") then
			return joint, hand
		end
	end
	return nil, nil
end

-- 6.4.1: "(x, y, z)" to two decimals, for the Output.
local function v3(v: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

-- 6.4.1: is your bag really on you? Once, a while after it showed; says in the Output what is wrong (nothing when all
-- is well). `worn` the BagWorn attribute.
local function diagnose(character: Model, worn: string)
	local pivot = character:FindFirstChild("KitBagPivot")
	local art = character:FindFirstChild("KitBagArt")
	local parts: { BasePart } = {}
	if art then
		for _, child in art:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
	end
	if not pivot or not pivot:IsA("BasePart") or #parts == 0 then
		warn(`[BagSway] your bag ({worn}) has no parts on your character (pivot {if pivot then "yes" else "no"}, art parts {#parts}): the server built none, look for a [KitWear] line in the server Output`)
		return
	end
	local joint = pivot:FindFirstChild("BagSwing")
	if not joint or not joint:IsA("Motor6D") or not joint.Part0 then
		warn(`[BagSway] your bag's joint is {if joint then joint.ClassName else "missing"}: it cannot hang from your hand (style {worn})`)
		return
	end
	local hand = joint.Part0 :: BasePart
	local about = `style {worn}, joint {hand.Name} → {pivot.Name}, C0 {v3(joint.C0.Position)}, Transform {v3(joint.Transform.Position)}`
	local place = (hand.CFrame * joint.C0).Position
	local off = (pivot.Position - place).Magnitude
	if off > CHECK.Far then
		warn(string.format("[BagSway] your bag sits %.1f studs from its place (%s)", off, about))
	end
	local far, clear = 0, 0
	for _, part in parts do
		far = math.max(far, (part.Position - hand.Position).Magnitude)
		if part.Transparency < 0.95 and part.LocalTransparencyModifier < 0.95 then
			clear += 1
		end
	end
	if far > CHECK.Far then
		warn(string.format("[BagSway] your bag is %.1f studs from your hand (%s)", far, about))
	end
	local camera = workspace.CurrentCamera
	local head = character:FindFirstChild("Head")
	local firstPerson = camera ~= nil and head ~= nil and head:IsA("BasePart") and (camera.CFrame.Position - head.Position).Magnitude < 1
	if clear == 0 and not firstPerson then
		local part = parts[1]
		warn(string.format("[BagSway] your bag's %d parts are all see-through (Transparency %.2f, LocalTransparencyModifier %.2f; %s)", #parts, part.Transparency, part.LocalTransparencyModifier, about))
	end
	-- 6.5.1: and always one line of what it found (the owner still sees no bag: this tells us where it is)
	print(string.format("[BagSway] your bag: %d parts (%d visible), %.1f studs from your %s, %.1f from its place (%s)", #parts, clear, far, hand.Name, off, about))
end

-- Our Transform off the joint (it hangs as the hand holds it), the swing forgotten.
local function release(rec: Rec)
	local joint = rec.joint
	if joint and rec.written and joint.Parent then
		joint.Transform = CFrame.identity
	end
	rec.written = false
	rec.joint, rec.hand = nil, nil
	rec.state = BagSwing.new()
end

local function forget(character: Model)
	local rec = recs[character]
	if rec then
		release(rec)
		recs[character] = nil
	end
end

local function step(dt: number)
	local me = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for _, player in Bodies.players() do
		local character = player.Character
		if not character then
			continue
		end
		local humanoid, root = Bodies.of(character)
		if not humanoid or not root or (player ~= me and eye ~= nil and (root.Position - eye).Magnitude > B.Range) then
			if recs[character] then
				forget(character)
			end
			continue
		end
		-- 6.4.1: your bag, once per spawn: a look whether it is really on you
		if player == me and checks[character] ~= true then
			local worn = character:GetAttribute("BagWorn")
			local since = checks[character]
			if type(worn) ~= "string" then
				checks[character] = nil
				-- 6.5.1: the bag is your hand but the server put none on you: say so once (the Output)
				if character:GetAttribute("Hand") == "bag" and not missingTold[character] then
					local at = missingSince[character]
					if not at then
						missingSince[character] = now
					elseif now - at > 4 then
						missingTold[character] = true
						warn("[BagSway] you hold your bag (2) but the server put none on you (no BagWorn): look for a [KitWear] line in the server Output")
					end
				else
					missingSince[character] = nil
				end
			elseif type(since) ~= "number" then
				checks[character] = now
			elseif now - since >= CHECK.After then
				-- (6.4.1 review: not on a dead body, nor while a body part is being swapped: the bag hangs loose
				-- for a moment then; look again a little later)
				local pivot = character:FindFirstChild("KitBagPivot")
				local joint = pivot and pivot:FindFirstChild("BagSwing")
				local part0 = if joint and joint:IsA("Motor6D") then joint.Part0 else nil
				if humanoid.Health <= 0 or (part0 ~= nil and part0.Parent ~= character) then
					checks[character] = now
				else
					checks[character] = true
					diagnose(character, worn)
				end
			end
		end
		local rec = recs[character]
		if not rec then
			rec = { joint = nil, hand = nil, state = BagSwing.new(), nextLook = 0, written = false, tuning = tuningOf(nil), worn = "hand", walked = 0, rel = nil, from = nil, fromAt = 0, relBag = nil }
			recs[character] = rec
		end
		local joint, hand = rec.joint, rec.hand
		local switchAt = character:GetAttribute("BagSwitchAt")
		local switching = type(switchAt) == "number" and serverNow - switchAt < SWITCH + 0.3
		if joint and (joint.Parent == nil or not hand or hand.Parent ~= character) then
			release(rec) -- (the bag went: put away, rebuilt)
			joint, hand = nil, nil
		end
		if not joint then
			if now < rec.nextLook and not switching then
				continue
			end
			rec.nextLook = now + LOOK
			joint, hand = find(character)
			if not joint or not hand then
				continue
			end
			rec.joint, rec.hand = joint, hand
			-- 6.4: the bag that hangs there and how it is worn (a new one is a new joint); moved between the front and
			-- the back just now: it starts from where it was (rec.rel) and moves over SWITCH seconds
			local pivot = (joint :: Motor6D).Parent
			local worn = if pivot then pivot:GetAttribute("Worn") else nil
			rec.worn = if type(worn) == "string" then worn else "hand"
			rec.tuning = if rec.worn == "hand" then tuningOf(pivot) else WEAR
			local bagId = if pivot then pivot:GetAttribute("Bag") else nil
			rec.from = if switching and rec.rel and rec.relBag == bagId then rec.rel else nil -- (the same bag only)
			rec.relBag = if type(bagId) == "string" then bagId else nil
			rec.fromAt = if type(switchAt) == "number" then switchAt else 0
		end
		local grip = (hand :: BasePart).CFrame * (joint :: Motor6D).C0
		local at = grip.Position
		handVec[1], handVec[2], handVec[3] = at.X, at.Y, at.Z
		local velocity = root.AssemblyLinearVelocity
		bodyVec[1], bodyVec[2], bodyVec[3] = velocity.X, velocity.Y, velocity.Z
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		rec.walked = (rec.walked + speed * dt) % (C.Step * 64)
		local transform: CFrame
		if rec.worn == "hand" then
			local tx, tz, twist = BagSwing.step(rec.state, dt, handVec, bodyVec, rec.tuning)
			-- The world orientation: your facing, the twist about the handles, tilted away from where the bottom went.
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local facing = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			local right = facing:Cross(Vector3.yAxis)
			local want = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis) * CFrame.Angles(0, twist, 0)
			local size = math.sqrt(tx * tx + tz * tz)
			if size > 1e-4 then
				-- (the bottom moved toward (tx, tz): the up axis leans the other way; axis = bottom's way × up)
				local axis = Vector3.new(tx / size, 0, tz / size):Cross(Vector3.yAxis)
				want = CFrame.fromAxisAngle(axis, size) * want
			end
			transform = grip.Rotation:Inverse() * want
		else
			-- 6.4: on the shoulder or the hip a small stiff swing and a bounce with the steps; on the back a soft bob
			local back = rec.worn == "back"
			local want = grip.Rotation
			if not back then
				local tx, tz = BagSwing.step(rec.state, dt, handVec, bodyVec, rec.tuning)
				local size = math.sqrt(tx * tx + tz * tz)
				if size > 1e-4 then
					want = CFrame.fromAxisAngle(Vector3.new(tx / size, 0, tz / size):Cross(Vector3.yAxis), size) * want
				end
			end
			local lift = BagSwing.bob(rec.walked, speed, if back then C.BackBob else C.Bounce, C.Step, B.FullSpeed)
			transform = CFrame.new(0, lift, 0) * (grip.Rotation:Inverse() * want)
		end
		-- 6.4: the move between the front and the back (from where it was, relative to the body, to its new place)
		local from = rec.from
		if from then
			local u = math.clamp((serverNow - rec.fromAt) / SWITCH, 0, 1)
			if u >= 1 then
				rec.from = nil
			else
				local blend = u * u * (3 - 2 * u)
				transform = grip:Inverse() * (root.CFrame * from):Lerp(grip * transform, blend)
			end
		end
		if transform == transform then -- (never a NaN on a joint)
			(joint :: Motor6D).Transform = transform
			rec.written = true
			rec.rel = root.CFrame:Inverse() * (grip * transform)
		end
	end
	if now - sweptAt > SWEEP then
		sweptAt = now
		for character in recs do
			if not character.Parent then
				recs[character] = nil
			end
		end
		for character in checks do
			if not character.Parent then
				checks[character] = nil
			end
		end
	end
end

function BagSway.start()
	RunService.PreSimulation:Connect(step)
end

return BagSway
