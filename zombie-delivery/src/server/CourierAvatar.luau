--!strict
-- Installs the same native StarterCharacter for every player before the world builds. Personal avatar assets and
-- Animate scripts are replaced by one common animation set; profile equipment still comes from KitWear.
-- No movement speeds, rewards, saved data or input are changed.
-- 5.9.2: the server only builds the template. The walk (shared/CourierMotion.luau) is chosen on each owning client by
-- the template's own Animate LocalScript (CharacterArt/Animate.client.luau), whose tracks replicate to everybody; the
-- server's 10 Hz animation loop over every body is gone.
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local Geometry = require(script.Parent.CharacterArt.Geometry)
local Rig = require(script.Parent.CharacterArt.Rig)
local Avatar = {}

local watches: { [Player]: { RBXScriptConnection } } = {}
local replacing: { [Player]: boolean } = {}
local started = false

local function characterAdded(player: Player, model: Model)
	if model:GetAttribute("CharacterArt") == "courier" then
		return -- (its Animate LocalScript animates it on the owner's client)
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
	if player.Character then characterAdded(player, player.Character) end
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
		local list: { RBXScriptConnection } = watches[player] or {}
		for _, connection in list do connection:Disconnect() end
		watches[player], replacing[player] = nil, nil
	end)
	for _, player in Players:GetPlayers() do watch(player) end
end

return Avatar
