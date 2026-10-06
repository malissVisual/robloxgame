--!strict
-- 5.3 review: only your own job's prompts. Two couriers at the same storefront (or door) both get a "Pick up" there;
-- with Exclusivity OnePerButton the nearer one would take your E and the server would answer "This is not your
-- delivery". server/Cargo.luau tags every job prompt (Config.Cargo.PromptTag, the attribute CargoOwner = the job
-- owner's UserId) and keeps the player attribute CargoWith (",<owner UserId>,…," of every job you work for: yours, the
-- one you ride along or crew for). Here a tagged prompt of any other job is hidden for you: its reach set to 0 locally
-- (never through Enabled, which the server switches), given back when you join that job.
--
-- client/CarBoarding.luau mutes prompts the same way while you sit (reach 0, given back only when still 0): a prompt
-- hidden here never shows, so it never mutes one; one shown anyway (it was muted when it became somebody else's) is
-- hidden again when it shows.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local CargoPrompts = {}

local player = Players.LocalPlayer
local TAG = Config.Cargo.PromptTag
local hidden: { [ProximityPrompt]: number } = {} -- the prompts hidden here, with their reach

-- Is this prompt one of your jobs' (or no job's at all)?
local function mine(prompt: ProximityPrompt): boolean
	local owner = prompt:GetAttribute("CargoOwner")
	if type(owner) ~= "number" or owner == player.UserId then
		return true
	end
	local with = player:GetAttribute("CargoWith")
	return type(with) == "string" and string.find(with, `,{owner},`, 1, true) ~= nil
end

local function apply(prompt: ProximityPrompt)
	if mine(prompt) then
		local reach = hidden[prompt]
		if reach then
			hidden[prompt] = nil
			if prompt.MaxActivationDistance == 0 then
				prompt.MaxActivationDistance = reach
			end
		end
	elseif not hidden[prompt] and prompt.MaxActivationDistance > 0 then
		hidden[prompt] = prompt.MaxActivationDistance
		prompt.MaxActivationDistance = 0
	end
end

local function added(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		apply(instance)
	end
end

function CargoPrompts.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(added)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("ProximityPrompt") then
			hidden[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		added(instance)
	end
	-- You joined or left a job: every job prompt again.
	player:GetAttributeChangedSignal("CargoWith"):Connect(function()
		for _, instance in CollectionService:GetTagged(TAG) do
			added(instance)
		end
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, TAG) and not mine(prompt) then
			hidden[prompt] = nil -- (its reach now is the one to keep)
			apply(prompt)
		end
	end)
end

return CargoPrompts
