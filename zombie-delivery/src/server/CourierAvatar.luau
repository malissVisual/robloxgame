--!strict
-- Installs the same native StarterCharacter for every player before the world builds. Personal avatar assets and
-- Animate scripts are replaced by one server-owned animation set; profile equipment still comes from KitWear.
-- No movement speeds, rewards, saved data or input are changed. Connections/tracks are cleaned at respawn/leave.
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Motion = require(ReplicatedStorage:WaitForChild("Shared").CourierMotion)
local Geometry = require(script.Parent.CharacterArt.Geometry)
local Rig = require(script.Parent.CharacterArt.Rig)
local Avatar = {}

type Body = { model: Model, humanoid: Humanoid, root: BasePart, tracks: { [string]: AnimationTrack }, active: string?, rate: number, connection: RBXScriptConnection }
local bodies: { [Player]: Body } = {}
local watches: { [Player]: { RBXScriptConnection } } = {}
local replacing: { [Player]: boolean } = {}
local started = false

local function clear(player: Player)
	local body = bodies[player]
	if not body then return end
	bodies[player] = nil
	body.connection:Disconnect()
	for _, track in body.tracks do
		track:Stop(0)
		track:Destroy()
	end
end

local function characterAdded(player: Player, model: Model)
	clear(player)
	if model:GetAttribute("CharacterArt") ~= "courier" then
		-- A player may have spawned while the server was starting. Replace that first body once, not every spawn.
		if replacing[player] then return end
		replacing[player] = true
		task.defer(function()
			if player.Parent == Players and player.Character == model then
				local ok, err = pcall(function() player:LoadCharacterAsync() end)
				if not ok then warn(`[CourierAvatar] initial respawn failed: {err}`) end
			end
			replacing[player] = nil
		end)
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then return end
	local connection = model.Destroying:Connect(function() clear(player) end)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks: { [string]: AnimationTrack } = {}
	for key, id in Motion.Animations do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, result = pcall(function() return animator:LoadAnimation(animation) end)
		animation:Destroy()
		if ok then
			local track = result :: AnimationTrack
			track.Looped = key ~= "jump"
			track.Priority = if key == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			tracks[key] = track
		else
			warn(`[CourierAvatar] animation {key} could not load: {result}`)
		end
	end
	bodies[player] = { model = model, humanoid = humanoid, root = root, tracks = tracks, active = nil, rate = 1, connection = connection }
end

local function watch(player: Player)
	if watches[player] then return end
	watches[player] = {
		player.CharacterAdded:Connect(function(model) characterAdded(player, model) end),
		player.CharacterRemoving:Connect(function() clear(player) end),
	}
	if player.Character then characterAdded(player, player.Character) end
end

local function step()
	for player, body in bodies do
		if player.Character ~= body.model or not body.model.Parent then clear(player); continue end
		local v = body.root.AssemblyLinearVelocity
		local state = if body.humanoid.Health <= 0 then "Dead" else body.humanoid:GetState().Name
		local selected, rate = Motion.select(state, Vector3.new(v.X, 0, v.Z).Magnitude, v.Y, body.humanoid.Sit)
		if selected ~= body.active then
			if body.active and body.tracks[body.active] then body.tracks[body.active]:Stop(Motion.Fade) end
			body.active, body.rate = selected, rate
			if selected and body.tracks[selected] then body.tracks[selected]:Play(Motion.Fade, 1, rate) end
		elseif selected and body.tracks[selected] and math.abs(rate - body.rate) > 0.05 then
			body.tracks[selected]:AdjustSpeed(rate)
			body.rate = rate
		end
	end
end

function Avatar.start()
	if started then return end
	local template = Rig.build(Geometry.spec("courier"))
	template.Name = "StarterCharacter"
	(template:FindFirstChildOfClass("Humanoid") :: Humanoid).WalkSpeed = StarterPlayer.CharacterWalkSpeed
	-- Enabled/Disabled are NOT replicated. Supply an actual local Animate replacement in the template, rather
	-- than trying to disable the engine's default LocalScript on the server.
	script.Parent.CharacterArt.Animate:Clone().Parent = template
	local previous = StarterPlayer:FindFirstChild("StarterCharacter")
	if previous then previous:Destroy() end
	StarterPlayer.LoadCharacterAppearance = false
	template.Parent = StarterPlayer
	started = true
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		clear(player)
		for _, connection in watches[player] or {} do connection:Disconnect() end
		watches[player], replacing[player] = nil, nil
	end)
	for _, player in Players:GetPlayers() do watch(player) end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < Motion.Tick then return end
		elapsed = 0
		step()
	end)
end

return Avatar
