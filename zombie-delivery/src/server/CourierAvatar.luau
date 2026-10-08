--!strict
-- Installs the same StarterCharacter for every player before the world builds. Personal avatar animations are replaced
-- by one common animation set; profile equipment still comes from KitWear.
-- No movement speeds, rewards, saved data or input are changed.
-- 5.9.2: the server only builds the template. The walk (shared/CourierMotion.luau) is chosen on each owning client by
-- the template's own Animate LocalScript (CharacterArt/Animate.client.luau), whose tracks replicate to everybody; the
-- server's 10 Hz animation loop over every body is gone.
-- 6.0.1: the template wears plain workwear: the red reflective vest is bought kit (Config.Kit "hivis", worn by KitWear).
-- 6.9 (the owner: "everybody the same figure, but the look stays the player's; a Roblox head with the player's face"):
-- the template is Roblox's own classic blocky R15 (Players:CreateHumanoidModelFromDescription, shared/AvatarLook.luau's
-- Body) in the courier's workwear, and each player's own look goes on it once spawned: their HumanoidDescription with
-- the torso, the arms, the legs, the proportions and the animations reset (AvatarLook.Body), the head, the face, the
-- clothes, the skin colours and the accessories kept (Humanoid:ApplyDescriptionAsync; KitWear dresses the kit again when a
-- part is replaced). The 6.7 native courier (CharacterArt) only if Roblox's body cannot be made at the start.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Geometry = require(script.Parent.CharacterArt.Geometry)
local Rig = require(script.Parent.CharacterArt.Rig)
local AvatarLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AvatarLook"))
local Avatar = {}

local watches: { [Player]: { RBXScriptConnection } } = {}
local replacing: { [Player]: boolean } = {}
-- 6.9: each player's own look on the classic body (false: none could be loaded); loading while the request runs
local looks: { [Player]: HumanoidDescription | false } = {}
local loading: { [Player]: boolean } = {}
local dressed: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local started = false

local WAIT_FOR_WORLD = 5 -- seconds a fresh body may take to reach the workspace before its look is put on

-- The classic body's fields on a description (the player's own or a new one).
local function classic(description: HumanoidDescription): HumanoidDescription
	for field, value in AvatarLook.Body do
		(description :: any)[field] = value
	end
	-- (a description may also list its body parts as BodyPartDescription children: those to Roblox's defaults too)
	for _, child in description:GetChildren() do
		pcall(function()
			if child:IsA("BodyPartDescription") and table.find(AvatarLook.Parts, (child :: any).BodyPart.Name) then
				(child :: any).AssetId = 0
			end
		end)
	end
	return description
end

local function workwear(): HumanoidDescription
	local description = classic(Instance.new("HumanoidDescription"))
	for field, c in AvatarLook.Workwear do
		(description :: any)[field] = Color3.fromRGB(c[1], c[2], c[3])
	end
	return description
end

-- As the native body was (5.9 – 6.8): only the root weighs (a rider does not slow the bike, the scooter or the car
-- the vehicles were tuned with), and the root stays out of the raycasts. Again after the player's own look went on (a
-- new head, the accessories).
local function settle(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Name == "HumanoidRootPart" and part.Parent == model then
				part.CanQuery = false
				part.RootPriority = 127
			else
				part.Massless = true
			end
		end
	end
end

-- Roblox's classic R15 in the workwear; the native courier when Roblox's body cannot be made (no avatar service).
local function templateBody(): Model
	local ok, body = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(workwear(), Enum.HumanoidRigType.R15)
	end)
	if ok and body then
		return body
	end
	warn(`[CourierAvatar] Roblox's R15 body did not load ({body}): the native courier instead`)
	return Rig.build(Geometry.spec("courier"))
end

-- The player's own look on a courier body, once the body is in the world and the look has loaded.
local function dress(player: Player, model: Model)
	local look = looks[player]
	if not look or dressed[model] then
		return
	end
	local description = look :: HumanoidDescription
	dressed[model] = true
	task.spawn(function()
		local waited = 0
		while model.Parent ~= workspace and waited < WAIT_FOR_WORLD do
			waited += task.wait(0.1)
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if player.Character ~= model or model.Parent ~= workspace or not humanoid or humanoid.Health <= 0 then
			return
		end
		local ok, err = pcall(function()
			humanoid:ApplyDescriptionAsync(description:Clone())
		end)
		if not ok then
			warn(`[CourierAvatar] {player.Name}'s own look did not go on: {err}`)
		end
		if model.Parent then
			settle(model)
		end
	end)
end

-- Once per player: their avatar's description, made classic. A body that spawned meanwhile is dressed when it comes.
local function loadLook(player: Player)
	if looks[player] ~= nil or loading[player] then
		return
	end
	loading[player] = true
	task.spawn(function()
		local ok, result = pcall(function(): HumanoidDescription
			return Players:GetHumanoidDescriptionFromUserId(player.CharacterAppearanceId)
		end)
		loading[player] = nil
		if player.Parent ~= Players then
			return
		end
		if ok and result then
			looks[player] = classic(result)
		else
			looks[player] = false
			print(`[CourierAvatar] {player.Name} wears the ZDC workwear (their own look did not load: {result})`)
		end
		local character = player.Character
		if character and character:GetAttribute("CharacterArt") == "courier" then
			dress(player, character)
		end
	end)
end

local function characterAdded(player: Player, model: Model)
	if model:GetAttribute("CharacterArt") == "courier" then
		dress(player, model) -- (its Animate LocalScript animates it on the owner's client)
		return
	end
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
end

local function watch(player: Player)
	if watches[player] then return end
	watches[player] = {
		player.CharacterAdded:Connect(function(model) characterAdded(player, model) end),
	}
	loadLook(player)
	if player.Character then characterAdded(player, player.Character) end
end

function Avatar.start()
	if started then return end
	local template = templateBody()
	settle(template)
	template.Name = "StarterCharacter"
	-- (every courier body, Roblox's or the native one: CourierAvatar dresses it, KitWear wears the kit on it)
	template:SetAttribute("CharacterArt", "courier")
	local humanoid = template:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
	-- Enabled/Disabled are NOT replicated. Supply an actual local Animate replacement in the template, rather
	-- than trying to disable the engine's default LocalScript on the server.
	local stock = template:FindFirstChild("Animate")
	if stock then stock:Destroy() end
	script.Parent.CharacterArt.Animate:Clone().Parent = template
	local previous = StarterPlayer:FindFirstChild("StarterCharacter")
	if previous then previous:Destroy() end
	StarterPlayer.LoadCharacterAppearance = false
	template.Parent = StarterPlayer
	started = true
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local list: { RBXScriptConnection } = watches[player] or {}
		for _, connection in list do connection:Disconnect() end
		watches[player], replacing[player], looks[player], loading[player] = nil, nil, nil, nil
	end)
	for _, player in Players:GetPlayers() do watch(player) end
end

return Avatar
