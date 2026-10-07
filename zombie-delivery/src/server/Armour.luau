--!strict
-- 6.0: the one place a player is hurt by the world (a zombie's bite, a bandit's shot, a bandit car's roof gun). The
-- best vest owned (profile.kit, shared/Armour.luau) takes its share off; the rest goes through Humanoid:TakeDamage, so
-- a ForceField (a spawn's, the admin's god mode: server/Admin.luau) still stops all of it. A humanoid that is not a
-- player's (a buddy, an NPC) takes the full hit.
--
--   Armour.hurt(humanoid, amount)   deals the hit after the vest

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Armour)
local PlayerData = require(script.Parent.PlayerData)

local Armour = {}

function Armour.hurt(humanoid: Humanoid, amount: number)
	local character = humanoid.Parent
	local player = if character then Players:GetPlayerFromCharacter(character) else nil
	local profile = if player then PlayerData.get(player) else nil
	local damage = if profile then Rules.reduce(amount, profile.kit) else math.max(0, amount)
	if damage > 0 then
		humanoid:TakeDamage(damage)
	end
end

return Armour
