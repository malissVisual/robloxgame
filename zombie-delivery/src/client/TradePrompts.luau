--!strict
-- 8.7 SANDBOX, trading between players, the world's side on this client:
--   * the stands' trade prompts for the other players ("Make an offer", "Buy $X": server/Warehouse.luau tags them
--     Config.PlayerTrade.PromptTag with their owner's UserId, the attribute Config.PlayerTrade.SellerAttribute) are
--     hidden on your own stands: their reach set to 0 here (never through Enabled, which the server switches), as
--     client/CargoPrompts.luau hides somebody else's job prompts; the server refuses you anyway;
--   * a big sale (Config.PlayerTrade.BigSale: the "PlayerTrade" remote's { kind = "news", text }) is a line in the chat
--     for everybody (TextChatService's RBXGeneral channel: a system message; no channel: a toast).
--   TradePrompts.start()

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local TradePrompts = {}

local player = Players.LocalPlayer
local hidden: { [ProximityPrompt]: number } = {} -- the prompts hidden here, with their reach
local started = false

local function tune(): any
	return (Config :: any).PlayerTrade
end

-- Is this one of the trade prompts on your own stands?
local function mine(prompt: ProximityPrompt): boolean
	return prompt:GetAttribute(tune().SellerAttribute) == player.UserId
end

local function apply(prompt: ProximityPrompt)
	if not mine(prompt) then
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

-- A big sale's line in the chat (a toast when there is no chat channel).
local function news(text: string)
	local ok = pcall(function()
		local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if not general or not general:IsA("TextChannel") then
			error("no chat channel")
		end
		general:DisplaySystemMessage(text)
	end)
	if not ok then
		pcall(function()
			require(script.Parent.Hud).toast(text)
		end)
	end
end

function TradePrompts.start()
	local trade = tune()
	if started or type(trade) ~= "table" or trade.On ~= true then
		return
	end
	started = true
	local tag = trade.PromptTag
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("ProximityPrompt") then
			hidden[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		added(instance)
	end
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, tag) and mine(prompt) then
			hidden[prompt] = nil -- (its reach now is the one to keep)
			apply(prompt)
		end
	end)
	task.spawn(function()
		local ok, remote = pcall(Net.get, "PlayerTrade")
		if ok and remote then
			remote.OnClientEvent:Connect(function(message: any)
				if type(message) == "table" and message.kind == "news" and type(message.text) == "string" and #message.text <= 200 then
					news(message.text)
				end
			end)
		end
	end)
end

return TradePrompts
