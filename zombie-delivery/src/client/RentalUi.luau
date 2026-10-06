--!strict
-- 5.6, ZDC RIDE: every dock has two prompts (server/Rental.luau, tagged RentalPrompt, attribute Kind): "Rent scooter"
-- and "Return scooter". Here each player sees the one that fits them: Return while they have a rental (the player
-- attribute Rental), Rent otherwise. Switched through Enabled, locally (the server never switches these two), so
-- client/CarBoarding.luau's muting while you sit (through the reach) stays its own; Return carries the attribute
-- Seated and shows from the saddle.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local RentalUi = {}

local TAG = "RentalPrompt"
local player = Players.LocalPlayer

local function apply(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local renting = player:GetAttribute("Rental") ~= nil
	local kind = prompt:GetAttribute("Kind")
	local show = if kind == "return" then renting else not renting
	if prompt.Enabled ~= show then
		prompt.Enabled = show
	end
end

local function applyAll()
	for _, prompt in CollectionService:GetTagged(TAG) do
		apply(prompt)
	end
end

function RentalUi.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(apply)
	player:GetAttributeChangedSignal("Rental"):Connect(applyAll)
	applyAll()
end

return RentalUi
