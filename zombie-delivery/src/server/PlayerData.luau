--!strict
-- The player's progress: money, the cars and guns they own, the equipped ones, the upgrade levels and lifetime stats.
-- Loaded from and saved to a DataStore. In Studio without API access it simply runs without saving.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)

export type Profile = {
	money: number,
	cars: { [string]: boolean },
	car: string,
	weapons: { [string]: boolean },
	weapon: string,
	upgrades: { [string]: number },
	deliveries: number,
	kills: number,
	earned: number,
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
local changed = Instance.new("BindableEvent")

-- Fires (player) whenever money or the inventory changed, so the state is sent to the client.
PlayerData.Changed = changed.Event

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function newProfile(): Profile
	return {
		money = Config.StartMoney,
		cars = { [Config.Cars[1].id] = true },
		car = Config.Cars[1].id,
		weapons = { [Config.Weapons[1].id] = true },
		weapon = Config.Weapons[1].id,
		upgrades = {},
		deliveries = 0,
		kills = 0,
		earned = 0,
	}
end

local function number(value: any, default: number, high: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(math.floor(value), 0, high)
end

-- Saved data is checked, never trusted.
local function applySaved(profile: Profile, saved: any)
	if type(saved) ~= "table" then
		return
	end
	profile.money = number(saved.money, profile.money, 2 ^ 50)
	profile.deliveries = number(saved.deliveries, 0, 2 ^ 50)
	profile.kills = number(saved.kills, 0, 2 ^ 50)
	profile.earned = number(saved.earned, 0, 2 ^ 50)
	if type(saved.cars) == "table" then
		for id, owned in saved.cars do
			if owned == true and type(id) == "string" and Economy.findCar(id) then
				profile.cars[id] = true
			end
		end
	end
	if type(saved.weapons) == "table" then
		for id, owned in saved.weapons do
			if owned == true and type(id) == "string" and Economy.findWeapon(id) then
				profile.weapons[id] = true
			end
		end
	end
	if type(saved.upgrades) == "table" then
		for _, def in Config.Upgrades do
			profile.upgrades[def.id] = number(saved.upgrades[def.id], 0, def.maxLevel)
		end
	end
	if type(saved.car) == "string" and profile.cars[saved.car] then
		profile.car = saved.car
	end
	if type(saved.weapon) == "string" and profile.weapons[saved.weapon] then
		profile.weapon = saved.weapon
	end
end

local function key(player: Player): string
	return "Player_" .. player.UserId
end

function PlayerData.load(player: Player)
	local profile = newProfile()
	local ok = true
	local dataStore = store
	if dataStore then
		local saved: any = nil
		ok = false
		for attempt = 1, 3 do
			local success, result = pcall(function()
				return dataStore:GetAsync(key(player))
			end)
			if success then
				saved = result
				ok = true
				break
			end
			warn(`[PlayerData] load failed ({attempt}/3): {result}`)
			if RunService:IsStudio() then
				break -- Studio without API access: play without saving, right away
			end
			task.wait(attempt)
		end
		applySaved(profile, saved)
	end
	-- Never overwrite a save we could not read.
	canSave[player] = ok and dataStore ~= nil
	if RunService:IsStudio() and not canSave[player] then
		profile.money = Config.StudioStartMoney
	end
	if player.Parent then
		profiles[player] = profile
		changed:Fire(player)
	end
end

function PlayerData.save(player: Player)
	local profile = profiles[player]
	local dataStore = store
	if not profile or not dataStore or not canSave[player] then
		return
	end
	local data = {
		money = profile.money,
		cars = profile.cars,
		car = profile.car,
		weapons = profile.weapons,
		weapon = profile.weapon,
		upgrades = profile.upgrades,
		deliveries = profile.deliveries,
		kills = profile.kills,
		earned = profile.earned,
	}
	local success, err = pcall(function()
		dataStore:SetAsync(key(player), data)
	end)
	if not success then
		warn(`[PlayerData] save failed: {err}`)
	end
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	profiles[player] = nil
	canSave[player] = nil
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.addMoney(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.money += math.floor(amount)
	profile.earned += math.floor(amount)
	changed:Fire(player)
end

-- Takes the money if there is enough; true when paid.
function PlayerData.spend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or amount < 0 or profile.money < amount then
		return false
	end
	profile.money -= amount
	changed:Fire(player)
	return true
end

function PlayerData.notify(player: Player)
	changed:Fire(player)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(function(player)
		PlayerData.load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerData.load, player)
	end
	Players.PlayerRemoving:Connect(PlayerData.release)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.save, player)
		end
		task.wait(2)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for player in profiles do
				task.spawn(PlayerData.save, player)
			end
		end
	end)
end

return PlayerData
