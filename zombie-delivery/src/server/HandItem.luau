--!strict
-- 6.7, items in the hand (the owner: "there are no animations … I want better animations: take care that it's like
-- that"): a piece of cargo held in a character's hand while a gesture plays (shared/Gestures.luau, server/Npcs.luau
-- Npcs.act; client/ArmPose.luau lays it over the arms on every client). Hand-overs were empty-handed: the piece jumped
-- from your arms to the stack at the door. Now server/Cargo.luau puts it in the hand:
--   give / receive  handed over at a door: in your right hand while you hold it out (Config.Courier.HandItem.Reach
--                   seconds), then in the receiver's hands ("receive", Pass seconds), then on the door's stack
--   bag             put into the bag: in your right hand until BagIn seconds into the "bag" gesture, then gone into it
--   throw           in your right hand through the wind-up (Config.Throw.WindUp), then it flies
-- The piece's parts are welded (Weld, Part0 the hand) where the gesture's held pose puts the hand: the two-handed
-- grips (give, receive, take) between both hands, level with the torso, worked out from the body's own rig attachments
-- and the pose's joint angles (Part1 = Part0 · C0 · Transform · C1⁻¹, the way ArmPose turns the joints), so it holds
-- for any R15 body; the one-handed grips (bag, throw) under the fingers, turning with the hand. The welds follow the
-- hand wherever each client's animation puts it; nothing runs per frame. Massless, never colliding, touched or hit by
-- rays. It stays where it was in the world (a body that goes lets it drop, the timers still let it go: the job never
-- loses a piece with a body). An R6 body or one without the rig's attachments holds it in front of the chest instead.
--
--   HandItem.hold(character, model, kind)  welds `model` (in the world; its pivot: the bottom centre) to the right
--                                          hand for the gesture `kind`; nil without a hand. Any earlier weld goes first
--   HandItem.release(hold, parent)         unwelds it, anchors it where it is, under `parent`; nil when it is gone
--   HandItem.drop(hold)                    it goes (into the bag)
--   HandItem.pass(model, giver, taker, parent, done)  the hand-over: the giver's hand (Reach), the taker's hands
--                                          (Pass: they reach for it Lead seconds before), then done(model) under
--                                          `parent` (not when it went meanwhile)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Gestures = require(Shared.Gestures)
local Npcs = require(script.Parent.Npcs)

local HandItem = {}

export type Hold = { model: Model, character: Model, welds: { Weld } }

local H = Config.Courier.HandItem
local WELD = "HandItemWeld"
-- Where in each gesture the grip is worked out (seconds in: the pose held there).
local HELD: { [string]: number } = { give = 0.25, receive = 0.6, take = 0.22 }
local TWO_HANDS: { [string]: boolean } = { give = true, receive = true, take = true }

local function angles(a: { number }?): CFrame
	if not a then
		return CFrame.identity
	end
	return CFrame.Angles(0, math.rad(a[2]), 0) * CFrame.Angles(math.rad(a[1]), 0, math.rad(a[3]))
end

local function rigAt(part: Instance?, name: string): CFrame?
	local found = if part then part:FindFirstChild(name) else nil
	return if found and found:IsA("Attachment") then found.CFrame else nil
end

-- The hand's frame on the UpperTorso with the arm in `pose` (nil without an R15 arm and its rig attachments).
local function handIn(character: Model, side: string, pose: Gestures.Pose): CFrame?
	local torso = character:FindFirstChild("UpperTorso")
	local upper = character:FindFirstChild(side .. "UpperArm")
	local lower = character:FindFirstChild(side .. "LowerArm")
	local hand = character:FindFirstChild(side .. "Hand")
	local s0, s1 = rigAt(torso, side .. "ShoulderRigAttachment"), rigAt(upper, side .. "ShoulderRigAttachment")
	local e0, e1 = rigAt(upper, side .. "ElbowRigAttachment"), rigAt(lower, side .. "ElbowRigAttachment")
	local w0, w1 = rigAt(lower, side .. "WristRigAttachment"), rigAt(hand, side .. "WristRigAttachment")
	if not (s0 and s1 and e0 and e1 and w0 and w1) then
		return nil
	end
	local k = if side == "Right" then "r" else "l"
	local arm = s0 * angles(pose[k .. "s"]) * s1:Inverse()
	local forearm = arm * e0 * angles(pose[k .. "e"]) * e1:Inverse()
	return forearm * w0 * angles(pose[k .. "w"]) * w1:Inverse()
end

-- Where the piece's pivot sits on the hand (Weld C0 for its pivot), for a piece `size` big.
local function gripOf(character: Model, hand: BasePart, kind: string, size: Vector3): CFrame
	if TWO_HANDS[kind] then
		local pose = Gestures.pose(kind, HELD[kind] or 0.2)
		local right = if pose then handIn(character, "Right", pose) else nil
		local left = if pose then handIn(character, "Left", pose) else nil
		if right and left then
			-- between both hands, level with the torso, held a little under its middle
			local mid = (right.Position + left.Position) / 2
			local pivot = CFrame.new(mid - Vector3.new(0, size.Y * 0.4, 0))
			return right:Inverse() * pivot
		end
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			-- (an R6 body or no rig attachments: in front of the chest)
			return hand.CFrame:ToObjectSpace(torso.CFrame * CFrame.new(0, -size.Y / 2, -(torso.Size.Z / 2 + size.Z / 2 + 0.25)))
		end
	end
	-- one hand: held by its top under the fingers, turning with the hand
	local grip = hand:FindFirstChild("RightGripAttachment")
	local at = if grip and grip:IsA("Attachment") then grip.CFrame else CFrame.new(0, -hand.Size.Y / 2, 0)
	return at * CFrame.new(0, -(size.Y - math.min(0.12, size.Y * 0.3)), 0)
end

local function unweld(model: Model)
	for _, d in model:GetDescendants() do
		if (d:IsA("Weld") and d.Name == WELD) or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

function HandItem.hold(character: Model?, model: Model, kind: string): Hold?
	if not character or not character.Parent or not model.Parent then
		return nil
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	unweld(model)
	local pivot = model:GetPivot()
	local _, size = model:GetBoundingBox()
	local grip = gripOf(character, hand, kind, size)
	local welds: { Weld } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local offset = grip * pivot:ToObjectSpace(d.CFrame)
			d.Anchored = false
			d.Massless, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			d.CFrame = hand.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Name = WELD
			weld.Part0 = hand
			weld.Part1 = d
			weld.C0 = offset
			weld.Parent = d
			table.insert(welds, weld)
		end
	end
	return { model = model, character = character, welds = welds }
end

function HandItem.release(hold: Hold, parent: Instance): Model?
	local model = hold.model
	for _, weld in hold.welds do
		weld:Destroy()
	end
	table.clear(hold.welds)
	if not model.Parent then
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model.Parent = parent
	return model
end

function HandItem.drop(hold: Hold)
	table.clear(hold.welds)
	hold.model:Destroy()
end

function HandItem.pass(model: Model, giver: Model?, taker: Model?, parent: Instance, done: (Model) -> ())
	local first = HandItem.hold(giver, model, "give")
	if taker then
		task.delay(if first then math.max(0, H.Reach - H.Lead) else 0, function()
			if taker.Parent then
				Npcs.act(taker, "receive")
			end
		end)
	end
	task.delay(if first then H.Reach else 0, function()
		if first then
			if not HandItem.release(first, parent) then
				return -- (gone with the stop or the body)
			end
		end
		local second = if taker and taker.Parent then HandItem.hold(taker, model, "receive") else nil
		task.delay(if second then H.Pass else 0, function()
			local kept = if second then HandItem.release(second, parent) else (if model.Parent then model else nil)
			if kept then
				done(kept)
			end
		end)
	end)
end

return HandItem
