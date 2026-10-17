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
-- 9.6, the courier you make (the start screen's character creator; Config.Characters, shared/CharacterLooks.luau): once
-- a save slot is loaded, server/SaveSlots.luau calls Avatar.setLook with the slot's courier. A made one (base
-- "custom") is worn instead of the player's own look: the classic body in its colours (a HumanoidDescription: the skin,
-- the top, the trousers; no clothes, no accessories, the classic head and face) and its pieces welded on
-- (StyleBuild.character: the hair, a hat, the sleeves or a jacket, the belt, the face's extra); none (or base "own"):
-- the player's own look as before. A look changed while one is going on waits for it, then goes on (never two at once).
--   Avatar.setLook(player, look?)   the slot's courier (nil: their own avatar), on the body at once and at every spawn
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Geometry = require(script.Parent.CharacterArt.Geometry)
local Rig = require(script.Parent.CharacterArt.Rig)
local AvatarLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AvatarLook"))
local CharacterLooks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterLooks")) -- 9.6
local StyleBuild = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StyleBuild")) -- 9.6: a made courier's pieces
local Avatar = {}

local watches: { [Player]: { RBXScriptConnection } } = {}
local replacing: { [Player]: boolean } = {}
-- 6.9: each player's own look on the classic body (false: none could be loaded); loading while the request runs
local looks: { [Player]: HumanoidDescription | false } = {}
local loading: { [Player]: boolean } = {}
local dressed: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- 9.6: the courier made for the slot played (base "custom"); a body being dressed, and one to dress again after it
local made: { [Player]: CharacterLooks.Look } = {}
local busy: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local again: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local classicBody = false -- the template is Roblox's classic R15 (not the native fallback: no own look goes on that)
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

-- Roblox's classic R15 in the workwear (true); the native courier when Roblox's body cannot be made (no avatar
-- service: false, the players keep the workwear).
local function templateBody(): (Model, boolean)
	local ok, body = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(workwear(), Enum.HumanoidRigType.R15)
	end)
	if ok and body then
		return body, true
	end
	warn(`[CourierAvatar] Roblox's R15 body did not load ({body}): the native courier instead`)
	return Rig.build(Geometry.spec("courier")), false
end

-- 9.6: a made courier's body: the classic one in its colours (no clothes, no accessories, the classic head and face).
local function madeDescription(look: CharacterLooks.Look): HumanoidDescription
	local description = classic(Instance.new("HumanoidDescription"))
	for field, c in CharacterLooks.colors(look) do
		(description :: any)[field] = Color3.fromRGB(c[1], c[2], c[3])
	end
	return description
end

-- What the player wears now: their made courier (9.6), else their own look (nil: not loaded yet).
local function wanted(player: Player): (HumanoidDescription?, CharacterLooks.Look?)
	local look = made[player]
	if look then
		return madeDescription(look), look
	end
	local own = looks[player]
	return if own then own :: HumanoidDescription else nil, nil
end

-- The player's look on a courier body, once the body is in the world and the look has loaded. 9.6: again (the same
-- thread) when the look changed while it went on.
local function dress(player: Player, model: Model)
	if not classicBody or dressed[model] or not wanted(player) then
		return
	end
	dressed[model] = true
	busy[model] = true
	task.spawn(function()
		local waited = 0
		while model.Parent ~= workspace and waited < WAIT_FOR_WORLD do
			waited += task.wait(0.1)
		end
		repeat
			again[model] = nil
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local description, look = wanted(player)
			if player.Character ~= model or model.Parent ~= workspace or not humanoid or humanoid.Health <= 0 or not description then
				break
			end
			local ok, err = pcall(function()
				humanoid:ApplyDescriptionAsync((description :: HumanoidDescription):Clone())
			end)
			if not ok then
				warn(`[CourierAvatar] {player.Name}'s look did not go on: {err}`)
			end
			if model.Parent then
				local built, why = pcall(function()
					if look then
						StyleBuild.character(model, look) -- (9.6: the hair, the hat, the top, the belt, the extra)
					else
						local old = model:FindFirstChild(StyleBuild.Look)
						if old then
							old:Destroy()
						end
					end
				end)
				if not built then
					warn(`[CourierAvatar] {player.Name}'s courier pieces did not go on: {why}`)
				end
				settle(model)
			end
		until not again[model]
		busy[model] = nil
	end)
end

function Avatar.setLook(player: Player, look: any?)
	local clean = if type(look) == "table" then CharacterLooks.clean(look) else nil
	if clean and CharacterLooks.custom(clean) then
		made[player] = clean
	else
		made[player] = nil
	end
	local character = player.Character
	if not character or character:GetAttribute("CharacterArt") ~= "courier" then
		return
	end
	if busy[character] then
		again[character] = true
	else
		dressed[character] = nil
		dress(player, character)
	end
end

-- Once per player: their avatar's description, made classic. A body that spawned meanwhile is dressed when it comes.
local function loadLook(player: Player)
	if not classicBody or looks[player] ~= nil or loading[player] then
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
			print(`[CourierAvatar] {player.Name} wears the Deliveros workwear (their own look did not load: {result})`)
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
	local template, isClassic = templateBody()
	classicBody = isClassic
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
		watches[player], replacing[player], looks[player], loading[player], made[player] = nil, nil, nil, nil, nil
	end)
	for _, player in Players:GetPlayers() do watch(player) end
end

return Avatar
