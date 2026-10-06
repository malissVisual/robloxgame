--!strict
-- 5.0: how a player moves cargo right now (shared/Transport.luau has the rules): on foot with their personal gear
-- (profile.kit, Config.Kit), or with their car when they sit in it or stand by it (the car's room: Economy.capacity
-- with its stage and gear, Vehicles.capacity). 5.1 adds the bike.
--
--   Transport.kitOf(player)    the kit owned (empty while the save loads)
--   Transport.footOf(player)   Info on foot with that kit (a foot job's room, whatever the player drives)
--   Transport.packRoomOf(player), Transport.warmOf(player)   the pack's room, the jacket's food drain (Cargo, Jobs)
--   Transport.of(player)       Info now: "car" seated in or within NEAR studs of your own car, else on foot
--   Transport.applyKit(player) the character attribute KitSpeed (the shoes' walk / sprint multiplier, nil = 1) that
--                              client/CameraRig.luau multiplies the walk and the sprint with; set on every spawn and
--                              whenever the profile changes (a purchase)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Transport)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)

local Transport = {}

local NEAR = 25 -- studs from your car's chassis that still count as "with your car"

function Transport.kitOf(player: Player): Rules.Kit
	local profile = PlayerData.get(player)
	return if profile then profile.kit else {}
end

function Transport.footOf(player: Player): Rules.Info
	return Rules.foot(Transport.kitOf(player))
end

-- The pieces of a foot job that ride in the pack (the backpack's room over the hands: server/Cargo.luau).
function Transport.packRoomOf(player: Player): number
	return Rules.packRoom(Transport.kitOf(player))
end

-- The food's freshness drain while this player carries it on foot (the thermal jacket).
function Transport.warmOf(player: Player): number
	return Rules.warm(Transport.kitOf(player))
end

function Transport.of(player: Player): Rules.Info
	local car = Vehicles.get(player)
	if car and not car.lent then
		local seated = Vehicles.seatedIn(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local near = root ~= nil and root:IsA("BasePart") and (root.Position - car.chassis.Position).Magnitude <= NEAR
		if seated == car or near then
			return Rules.car(Vehicles.capacity(car, nil))
		end
	end
	return Transport.footOf(player)
end

function Transport.applyKit(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local mult = Rules.speedMult(Transport.kitOf(player))
	local value = if mult ~= 1 then mult else nil
	if character:GetAttribute("KitSpeed") ~= value then
		character:SetAttribute("KitSpeed", value)
	end
end

function Transport.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			Transport.applyKit(player)
		end)
		Transport.applyKit(player)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	PlayerData.Changed:Connect(Transport.applyKit)
end

return Transport
