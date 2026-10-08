--!strict
-- 6.12, the horn, the server's side (Config.Soundscape). H in the driver's seat (client/SoundScape.luau) plays the
-- driver's horn on their own client at once and fires the Horn remote (rate-limited: HornPerSecond). Here it is
-- checked (the player drives a car now, not a wreck; at most one honk every HornGap seconds) and the car is sent to
-- every other player whose character is within HornRange of it; their clients play the car's own horn from it (its
-- class: shared/SoundPlan.luau horn). Nothing is kept but the time of each player's last honk.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)

local Horn = {}

local started = false
local lastAt: { [Player]: number } = {}

local function onHorn(player: Player)
	local S = Config.Soundscape
	if not Net.limit(player, "Horn", S.HornPerSecond) then
		return
	end
	local now = os.clock()
	if now - (lastAt[player] or -math.huge) < S.HornGap then
		return
	end
	local car, driving = Vehicles.seatedIn(player)
	if not car or not driving or car.wrecked or not car.model.Parent then
		return
	end
	lastAt[player] = now
	local at = car.model:GetPivot().Position
	local remote = Net.get("Horn")
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if other ~= player and root and root:IsA("BasePart") and (root.Position - at).Magnitude < S.HornRange then
			remote:FireClient(other, car.model)
		end
	end
end

function Horn.start()
	if started then
		return
	end
	started = true
	Net.get("Horn").OnServerEvent:Connect(onHorn)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAt[player] = nil
	end)
end

return Horn
