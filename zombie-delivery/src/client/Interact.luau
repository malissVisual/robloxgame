--!strict
-- 5.7: the shared helpers of the interactions at the car's level (Config.Interact; the curves and the routes are
-- shared/InteractPose.luau): getting on a bike or a scooter (client/CarBoarding.luau), the bus's door and seat
-- (client/BusRide.luau); 5.7 – 6.9 the zip lines' ladders too (6.10: real trusses, climbed by the body itself).
--
-- * Interact.pose(character, pose, dt, owner): an InteractPose.Pose laid ON TOP of what the Animator wrote this frame
--   into the R15 joints' Transform (shared/Joints.luau: Motor6Ds or AnimationConstraints; C0 is never written), eased
--   toward over a few frames so one move's pose flows into the next. Called in RunService.PreSimulation, every frame
--   the pose lasts; Interact.release(character, owner) gives every joint back to the animation. `owner` names the
--   module posing (a character is in one move at a time; the newest owner takes it over, another's release leaves it
--   alone). A joint the Animator left alone this frame still holds our value: its last animated value is the base
--   then, so the pose never piles up on itself (the way client/BikeRider.luau layers the rider). R6 bodies are left
--   alone; Interact.sweep forgets the bodies that are gone.
-- * Interact.freeze(humanoid, on): your own controls off (the PlayerModule's: keys, the touch stick, a gamepad), the
--   humanoid standing still (PlatformStand) and no prompts (a car's door under a ladder) while a move carries the
--   body; or all of it back.
-- * Interact.place(root, frame, dt): the root put where the move is this frame, gravity cancelled over the step (the
--   next frame sets it again anyway). Your own body's physics are yours, so everybody sees the move.
-- * Interact.standHeight / Interact.groundY: where a body stands on the ground.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Joints = require(Shared:WaitForChild("Joints"))
local InteractPose = require(Shared:WaitForChild("InteractPose"))

local Interact = {}

local player = Players.LocalPlayer
local EASE_RATE = 18 -- the pose eases toward its goal at this rate (1 / s)

-- The joints a pose names: its key → the part and the joint in it.
local JOINTS: { [string]: { string } } = {
	waist = { "UpperTorso", "Waist" },
	rightHip = { "RightUpperLeg", "RightHip" },
	rightKnee = { "RightLowerLeg", "RightKnee" },
	leftHip = { "LeftUpperLeg", "LeftHip" },
	leftKnee = { "LeftLowerLeg", "LeftKnee" },
	rightShoulder = { "RightUpperArm", "RightShoulder" },
	leftShoulder = { "LeftUpperArm", "LeftShoulder" },
	rightElbow = { "RightLowerArm", "RightElbow" },
	leftElbow = { "LeftLowerArm", "LeftElbow" },
}

type Posed = { joints: { [string]: any }, now: InteractPose.Pose, owner: string }

local written: { [Instance]: CFrame } = {}
local animated: { [Instance]: CFrame } = {}
local posed: { [Model]: Posed } = {}

-- The animation's own value of a joint this frame.
local function baseOf(joint: any): CFrame
	local live: CFrame = joint.Transform
	local mine = written[joint]
	if mine and Joints.same(live, mine) then
		return animated[joint] or CFrame.identity
	end
	animated[joint] = live
	return live
end

local function rotation(a: InteractPose.Angles): CFrame
	return CFrame.Angles(0, a.y, 0) * CFrame.Angles(0, 0, a.z) * CFrame.Angles(a.x, 0, 0)
end

-- `pose` over the character's animation this frame, eased toward from the pose before (dt nil: at once).
function Interact.pose(character: Model, pose: InteractPose.Pose, dt: number?, owner: string)
	local state = posed[character]
	if state and state.owner ~= owner then
		state.owner = owner -- (a new move takes the body over from where the last one left it)
	end
	if not state then
		if not character:FindFirstChild("UpperTorso") then
			return -- not an R15 body
		end
		local joints: { [string]: any } = {}
		for name, pair in JOINTS do
			local joint = Joints.find(character:FindFirstChild(pair[1]), pair[2])
			if joint then
				joints[name] = joint
			end
		end
		state = { joints = joints, now = InteractPose.zero(), owner = owner }
		posed[character] = state
	end
	local current = state :: Posed
	local k = if dt then 1 - math.exp(-EASE_RATE * dt) else 1
	current.now = InteractPose.blend(current.now, pose, k)
	for name, joint in current.joints do
		if joint.Parent then
			local base = baseOf(joint)
			local out = base * rotation(current.now[name])
			joint.Transform = out
			written[joint] = out
		end
	end
end

-- Every joint back to the animation (owner: only when that module poses it now; nil: whoever does).
function Interact.release(character: Model, owner: string?)
	local state = posed[character]
	if not state or (owner ~= nil and state.owner ~= owner) then
		return
	end
	posed[character] = nil
	for _, joint in state.joints do
		if joint.Parent and written[joint] then
			joint.Transform = baseOf(joint)
		end
		written[joint] = nil
		animated[joint] = nil
	end
end

function Interact.posing(character: Model, owner: string?): boolean
	local state = posed[character]
	return state ~= nil and (owner == nil or state.owner == owner)
end

-- The characters posed that are gone (call now and then).
function Interact.sweep()
	for character in posed do
		if not character.Parent then
			Interact.release(character)
		end
	end
end

-- ── Your own body ──────────────────────────────────────────────────────────

local controls: any = nil -- the PlayerModule's controls (false: none found)
local frozen: Humanoid? = nil

local function getControls(): any
	if controls == nil then
		local ok, result = pcall(function(): any
			local scripts = player:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			if module and module:IsA("ModuleScript") then
				return (require(module) :: any):GetControls()
			end
			return nil
		end)
		controls = if ok and result then result else false
	end
	return if controls then controls else nil
end

-- Controls off and the humanoid standing still while a move carries the body (on false: all back).
function Interact.freeze(humanoid: Humanoid?, on: boolean)
	if on then
		if not humanoid or frozen == humanoid then
			return
		end
		frozen = humanoid
		humanoid.PlatformStand = true
	else
		local was = frozen
		if not was then
			return -- (nothing of ours to give back)
		end
		frozen = nil
		if was.Parent then
			was.PlatformStand = false
		end
	end
	ProximityPromptService.Enabled = not on
	local c = getControls()
	if c then
		pcall(function()
			if on then
				c:Disable()
			else
				c:Enable()
			end
		end)
	end
end

function Interact.frozen(): boolean
	return frozen ~= nil
end

-- The root where the move is this frame; `carrier` the velocity of what it rides along with (a car's chassis).
function Interact.place(root: BasePart, frame: CFrame, dt: number, carrier: Vector3?)
	root.CFrame = frame
	root.AssemblyLinearVelocity = (carrier or Vector3.zero) + Vector3.new(0, workspace.Gravity * dt * 0.5, 0)
	root.AssemblyAngularVelocity = Vector3.zero
end

-- The root's height over the ground, standing.
function Interact.standHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- The ground's top under (x, z), looking down from y + 6 (nil: nothing there). Things that move are not ground.
function Interact.groundY(x: number, y: number, z: number, exclude: { Instance }): number?
	local list = table.clone(exclude)
	for _, name in { "Cars", "Zombies", "Npcs", "Traffic", "Animals", "Loot", "LocalEffects", "Buses" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	local character = player.Character
	if character then
		table.insert(list, character)
	end
	rayParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(Vector3.new(x, y + 6, z), Vector3.new(0, -24, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

-- A CFrame from a route's sample (a position and a flat facing).
function Interact.frame(x: number, y: number, z: number, fx: number, fz: number): CFrame
	local at = Vector3.new(x, y, z)
	return CFrame.lookAt(at, at + Vector3.new(fx, 0, fz))
end

return Interact
