--!strict
-- Only your own prompts. The owner's prompts of a plot (its warehouse's stands and desks: server/Warehouse.luau; the
-- van's PAINT: server/VanPaint.luau) are tagged Config.Cargo.PromptTag with the attribute CargoOwner = the owner's
-- UserId. Here a tagged prompt of anybody else is hidden for you: its reach set to 0 locally (never through Enabled,
-- which the server switches); one shown anyway is hidden again when it shows.

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

-- Is this prompt yours (or nobody's)?
local function mine(prompt: ProximityPrompt): boolean
	local owner = prompt:GetAttribute("CargoOwner")
	return type(owner) ~= "number" or owner == player.UserId
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
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, TAG) and not mine(prompt) then
			hidden[prompt] = nil -- (its reach now is the one to keep)
			apply(prompt)
		end
	end)
end

return CargoPrompts
