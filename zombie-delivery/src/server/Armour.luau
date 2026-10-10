--!strict
-- 6.0: the one place a player is hurt by the world (a zombie's bite, a bandit's shot, a bandit car's roof gun). The
-- best vest owned (profile.kit, shared/Armour.luau) takes its share off; the rest goes through Humanoid:TakeDamage, so
-- a ForceField (a spawn's, the admin's god mode: server/Admin.luau) still stops all of it. A humanoid that is not a
-- player's (a buddy, an NPC) takes the full hit.
--
--   Armour.hurt(humanoid, amount)   deals the hit after the vest (6.20: ★ Second Wind may turn a lethal one into
--                                   SecondWindHealth left, server/Skills.luau)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Armour)
local Config = require(Shared.Config) -- 6.20: Second Wind's health
local Net = require(Shared.Net)
local PlayerData = require(script.Parent.PlayerData)

local Armour = {}

function Armour.hurt(humanoid: Humanoid, amount: number)
	local character = humanoid.Parent
	local player = if character then Players:GetPlayerFromCharacter(character) else nil
	local profile = if player then PlayerData.get(player) else nil
	local damage = if profile then Rules.reduce(amount, profile.kit) else math.max(0, amount)
	-- 6.20: ★ Second Wind (Config.Skills): a hit that would kill leaves the courier at SecondWindHealth instead, once a job
	-- or a mission (server/Skills.luau's charge; never through a ForceField, which stops the hit anyway).
	if player and damage > 0 and damage >= humanoid.Health and humanoid.Health > 0 and character and not character:FindFirstChildOfClass("ForceField") then
		local Skills = require(script.Parent.Skills)
		if Skills.secondWind(player) then
			humanoid.Health = math.min(humanoid.MaxHealth, Config.Skills.SecondWindHealth)
			Net.get("Notice"):FireClient(player, "💨 Second Wind! You're still standing.")
			return
		end
	end
	if damage > 0 then
		humanoid:TakeDamage(damage)
	end
end

return Armour
