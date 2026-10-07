--!strict
-- Cloned into the uniform StarterCharacter as "Animate", replacing Roblox's default personal-avatar animator.
-- 5.9.2: the walk is chosen here, on the owning client (as Roblox's own Animate does), not on the server: this
-- LocalScript loads the common tracks (shared/CourierMotion.luau Animations) on the character's Animator and every
-- frame picks one with CourierMotion.select from the humanoid's state and its actual velocity (idle, walk, run, jump,
-- fall, climb, swim, and the sit track in a seat), fading Motion.Fade between them and matching the pace. Animations
-- the owning client plays replicate to everybody. ArmPose / BikeRider / Interact still lay their poses over it in
-- PreSimulation on every client. Everything stops when the body goes (the script goes with it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Motion = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CourierMotion"))

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local root = character:WaitForChild("HumanoidRootPart") :: BasePart
local animator = humanoid:WaitForChild("Animator") :: Animator

local tracks: { [string]: AnimationTrack } = {}
for key: string, id: string in Motion.Animations :: { [string]: string } do
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if ok then
		local track = result :: AnimationTrack
		track.Looped = key ~= "jump"
		track.Priority = if key == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
		tracks[key] = track
	else
		warn(`[Animate] animation {key} could not load: {result}`)
	end
end

local active: string? = nil
local rate = 1
local connection: RBXScriptConnection? = nil

local function step()
	local v = root.AssemblyLinearVelocity
	local state = if humanoid.Health <= 0 then "Dead" else humanoid:GetState().Name
	local selected, pace = Motion.select(state, Vector3.new(v.X, 0, v.Z).Magnitude, v.Y, humanoid.Sit)
	if selected ~= active then
		local playing = if active then tracks[active] else nil
		if playing then
			playing:Stop(Motion.Fade)
		end
		active, rate = selected, pace
		local track = if selected then tracks[selected] else nil
		if track then
			track:Play(Motion.Fade, 1, pace)
		end
	elseif selected and tracks[selected] and math.abs(pace - rate) > 0.05 then
		tracks[selected]:AdjustSpeed(pace)
		rate = pace
	end
end

local function stop()
	local current = connection
	connection = nil
	if current then
		current:Disconnect()
	end
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(tracks)
end

connection = RunService.Heartbeat:Connect(function()
	if not character.Parent or not humanoid.Parent then
		stop()
		return
	end
	step()
end)
character.Destroying:Connect(stop)
