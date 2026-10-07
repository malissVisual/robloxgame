--!strict
-- 5.0: how a player moves cargo right now (shared/Transport.luau has the rules): on foot with their personal gear
-- (profile.kit, Config.Kit), or with their car when they sit in it or stand by it (the car's room: Economy.capacity
-- with its stage and gear, Vehicles.capacity). 5.1: or on their bike (Config.Cars bike = true): its room, its bike
-- gear's and the pack, light pieces only (Rules.bike).
--
--   Transport.kitOf(player)    the kit owned (empty while the save loads)
--   Transport.footOf(player)   Info on foot with that kit (a foot job's room, whatever the player drives)
--   Transport.packRoomOf(player), Transport.warmOf(player)   the pack's room (6.6: the bag's), the jacket's food drain
--   Transport.bikeBagOf(player) 6.6: the bike's own bag (its rack / basket / box with its bike gear: Rules.bikeRoom) of
--                              the bike a bike job is ridden on (bikeOf), 0 without a bike
--   Transport.of(player)       Info now: "car" / "bike" seated on or within NEAR studs of your own vehicle, else on foot
--   Transport.bikeOf(player)   5.1: the bike a bike job is ridden on (the equipped one, else your bike of choice) and
--                              its Info (nil, nil without a bike): the board's BIKE section, Jobs' room checks
--   Transport.riding(player)   5.1: is the equipped vehicle a bike (profile.car is one)?
--   Transport.renting(player)  5.6: is the player's vehicle out a ZDC RIDE rental (server/Rental.luau)? Transport.of
--                              then counts it as a bike (its rack's slot and the pack), like the owned E-Scooter
--   Transport.applyKit(player) the character attribute KitSpeed (the shoes' walk / sprint multiplier, nil = 1) that
--                              client/CameraRig.luau multiplies the walk and the sprint with; set on every spawn and
--                              whenever the profile changes (a purchase). 6.4: and BreathCost, the active bag's
--                              bagBreath while the bag is your hand (the duffel: the sprint drains the breath faster,
--                              client/Stamina.luau; nil = 1), set again when the Hand attribute changes
--   Transport.bagOf(player)    6.4: the bag choice (profile.activeBag; nil = the best owned): every room here and in
--                              shared/Transport.luau counts the ACTIVE bag only (Rules.activeBag / bagRoom)
--   Transport.activeBagOf(player)  6.4: that bag's Config.Kit entry (nil without a bag)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Transport)
local Config = require(Shared.Config) -- 6.4: the bag's KitDef
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)

local Transport = {}

local NEAR = 25 -- studs from your car's chassis that still count as "with your car"

function Transport.kitOf(player: Player): Rules.Kit
	local profile = PlayerData.get(player)
	return if profile then profile.kit else {}
end

-- 6.4: the bag choice (nil: the best bag owned).
function Transport.bagOf(player: Player): string?
	local profile = PlayerData.get(player)
	return if profile then profile.activeBag else nil
end

function Transport.activeBagOf(player: Player): Config.KitDef?
	return Rules.activeBag(Transport.kitOf(player), Transport.bagOf(player))
end

function Transport.footOf(player: Player): Rules.Info
	return Rules.foot(Transport.kitOf(player), Transport.bagOf(player))
end

-- The pieces of a foot job that ride over the hands (server/Cargo.luau's pack; 6.6: the active bag's, no backpack).
function Transport.packRoomOf(player: Player): number
	return Rules.packRoom(Transport.kitOf(player), Transport.bagOf(player))
end

-- The food's freshness drain while this player carries it on foot (the thermal jacket).
function Transport.warmOf(player: Player): number
	return Rules.warm(Transport.kitOf(player))
end

-- 5.1: is the vehicle CAR / MY BIKE brings a bike?
function Transport.riding(player: Player): boolean
	local profile = PlayerData.get(player)
	return profile ~= nil and Rules.isBike(profile.car)
end

-- 5.1: the bike of a bike job (the equipped one, else your bike of choice, while you own it) and its Info.
function Transport.bikeOf(player: Player): (string?, Rules.Info?)
	local profile = PlayerData.get(player)
	if not profile then
		return nil, nil
	end
	local id: string? = if Rules.isBike(profile.car) then profile.car else profile.bike
	if id == nil or not profile.cars[id] or not Rules.isBike(id) then
		return nil, nil
	end
	return id, Rules.bike(Rules.bikeRoom(id, profile.carGear), profile.kit, profile.activeBag)
end

-- 6.6: the bike's own bag of the bike bikeOf names (0 without one).
function Transport.bikeBagOf(player: Player): number
	local profile = PlayerData.get(player)
	local id = Transport.bikeOf(player)
	return if profile and id then Rules.bikeRoom(id, profile.carGear) else 0
end

function Transport.of(player: Player): Rules.Info
	local car = Vehicles.get(player)
	if car and (not car.lent or car.rental) then -- (5.6: a ZDC RIDE rental rides like your E-Scooter)
		local seated = Vehicles.seatedIn(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local near = root ~= nil and root:IsA("BasePart") and (root.Position - car.chassis.Position).Magnitude <= NEAR
		if seated == car or near then
			if Rules.isBike(car.id) then
				return Rules.bike(Vehicles.capacity(car, nil), Transport.kitOf(player), Transport.bagOf(player)) -- 5.1
			end
			return Rules.car(Vehicles.capacity(car, nil))
		end
	end
	return Transport.footOf(player)
end

-- 5.6: a ZDC RIDE rental out (server/Rental.luau)?
function Transport.renting(player: Player): boolean
	local car = Vehicles.get(player)
	return car ~= nil and car.rental
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
	-- 6.4: a heavy bag in your hand (the duffel) costs more breath to sprint with (client/Stamina.luau); nil = 1
	local cost = if character:GetAttribute("Hand") == "bag" then Rules.bagBreath(Transport.kitOf(player), Transport.bagOf(player)) else 1
	local breath = if cost ~= 1 then cost else nil
	if character:GetAttribute("BreathCost") ~= breath then
		character:SetAttribute("BreathCost", breath)
	end
end

function Transport.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			Transport.applyKit(player)
			-- 6.4: the bag's speed counts only while it is your hand (server/Hand.luau sets the Hand attribute)
			character:GetAttributeChangedSignal("Hand"):Connect(function()
				Transport.applyKit(player)
			end)
		end)
		local character = player.Character
		if character then
			character:GetAttributeChangedSignal("Hand"):Connect(function()
				Transport.applyKit(player)
			end)
		end
		Transport.applyKit(player)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	PlayerData.Changed:Connect(Transport.applyKit)
end

return Transport
