--!strict
-- 6.20, skills for levels on the server (Config.Skills, shared/Skills.luau; design/skills/PROPOSAL.md). The ranks live
-- in the profile (server/PlayerData.luau profile.skills; the points come from the level, nothing else is saved); the
-- Skills remote asks, this module decides:
--   ("buy", id)   a rank more when Skills.canBuy says yes (points free, the rank not full, an apex opened)
--   ("reset")     every point back, free, never during a job or a mission (yours or your crew's: Jobs.involved)
-- After a change the state goes out again (PlayerData.notify: the state's `skills`, the player attribute Skills).
-- The effects the server owns read Skills.of / Skills.effect (Cargo, Transport, Jobs, Vehicles, Fuel, Repair,
-- CloseCombat, Gun, Items, Armour); this module itself keeps the body's: the max health (Endurance, on every spawn and
-- when it changes), the faster healing (Field Medic's regen: Config.Skills.Regen × its share, a second, on top of
-- Roblox's own) and the charges that last a job or a mission (Field Medic's free medkit, Second Wind): they fill when a
-- job or a mission starts (yours or your crew's) and on every spawn.
--
--   Skills.of(player)             the ranks (an empty table while the save loads)
--   Skills.effect(player, key)    shared/Skills.luau effect of the player's ranks
--   Skills.carDamage(player, cause)  the share of a hit their vehicle takes (Tough Body, Stuntman)
--   Skills.hands(player) / bag(player)  Strong Back's extra light pieces in the hands / in a bag
--   Skills.freeMedkit(player)     a medkit used now is free (and that charge is spent)?
--   Skills.secondWind(player)     a lethal hit now leaves them alive (and that charge is spent)?

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Rules = require(Shared.Skills)
local PlayerData = require(script.Parent.PlayerData)

local Skills = {}

-- Set by Main (Jobs.involved; not required here: Jobs, Cargo and Vehicles read this module): on a job or a mission,
-- theirs or their crew's?
Skills.involved = function(_player: Player): boolean
	return false
end

local notice = Net.get("Notice")
local EMPTY: Rules.Ranks = {}
local medkitUsed: { [Player]: boolean } = {}
local windUsed: { [Player]: boolean } = {}
local wasInvolved: { [Player]: boolean } = {}

function Skills.of(player: Player): Rules.Ranks
	local profile = PlayerData.get(player)
	return if profile and profile.skills then profile.skills else EMPTY
end

function Skills.effect(player: Player?, key: string): number
	if not player then
		return 0
	end
	return Rules.effect(Skills.of(player), key)
end

function Skills.carDamage(player: Player?, cause: string?): number
	if not player then
		return 1
	end
	return Rules.carDamage(Skills.of(player), cause)
end

function Skills.hands(player: Player?): number
	return math.max(0, math.floor(Skills.effect(player, "hands")))
end

function Skills.bag(player: Player?): number
	return math.max(0, math.floor(Skills.effect(player, "bag")))
end

-- The charges of a job or a mission (and of a life) fill again.
local function refill(player: Player)
	medkitUsed[player] = nil
	windUsed[player] = nil
end

function Skills.freeMedkit(player: Player): boolean
	if medkitUsed[player] or Skills.effect(player, "freeMedkit") <= 0 then
		return false
	end
	medkitUsed[player] = true
	return true
end

function Skills.secondWind(player: Player): boolean
	if windUsed[player] or Skills.effect(player, "secondWind") <= 0 then
		return false
	end
	windUsed[player] = true
	return true
end

-- Endurance: the max health (the share of health kept when it changes; a fresh body full).
local function applyHealth(player: Player, fresh: boolean?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local max = Config.Skills.BaseHealth + math.max(0, Skills.effect(player, "health"))
	if humanoid.MaxHealth == max then
		return
	end
	local share = if fresh then 1 else math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
	humanoid.MaxHealth = max
	humanoid.Health = math.max(1, max * share)
end

local function changed(player: Player)
	PlayerData.notify(player) -- (the state and the Skills attribute: server/PlayerData.luau)
	applyHealth(player)
end

local function onRemote(player: Player, action: any, id: any)
	if not Net.limit(player, "Skills", Config.Robust.Limits.Skills) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local level = Levels.levelFor(profile.xp)
	if action == "buy" and type(id) == "string" then
		local def = Rules.find(id)
		local after, why = Rules.buy(profile.skills, level, id)
		if not after or not def then
			notice:FireClient(player, `Can't take that skill: {why or "unknown"}.`)
			return
		end
		profile.skills = after
		notice:FireClient(player, `{def.icon} {def.name} {after[id]}/{def.ranks}: {Rules.describe(def, after[id])}`)
		changed(player)
	elseif action == "reset" then
		if next(profile.skills) == nil then
			return
		end
		if Skills.involved(player) then
			notice:FireClient(player, "Finish the job or the mission first, then reset your skills.")
			return
		end
		profile.skills = {}
		notice:FireClient(player, `Skills reset: {Rules.free(profile.skills, level)} points to spend.`)
		changed(player)
	end
end

function Skills.start()
	Net.get("Skills").OnServerEvent:Connect(onRemote)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			refill(player)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				applyHealth(player, true)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		medkitUsed[player] = nil
		windUsed[player] = nil
		wasInvolved[player] = nil
	end)
	-- A level-up or a loaded save (the points), a purchase elsewhere: the max health follows the profile.
	PlayerData.Changed:Connect(function(player: Player)
		applyHealth(player)
	end)
	-- Once a second: Field Medic's healing on top of Roblox's own, and the charges of a job or a mission that starts.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local involved = Skills.involved(player)
				if involved and not wasInvolved[player] then
					refill(player)
				end
				wasInvolved[player] = involved
				local regen = Skills.effect(player, "regen")
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if regen > 0 and humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * Config.Skills.Regen * regen)
				end
			end
		end
	end)
end

return Skills
