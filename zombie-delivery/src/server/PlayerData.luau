--!strict
-- The player's progress: money, the cars and guns they own, the equipped ones, the car guns on their roofs, the upgrade
-- levels, the driver XP (the level and the rank come from it, shared/Levels.luau) and lifetime stats.
-- Loaded from and saved to a DataStore. In Studio without API access it simply runs without saving.
-- The player list (leaderstats) shows Level, Money and Deliveries; the player attributes Xp, Level and Rank carry the
-- driver level to every client (the HUD's XP bar, the level-up flash, the locks in the shops).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)

export type Profile = {
	money: number,
	cars: { [string]: boolean },
	car: string,
	weapons: { [string]: boolean },
	weapon: string,
	upgrades: { [string]: number },
	items: { [string]: number }, -- consumables (Config.Items): how many
	paints: { [string]: boolean }, -- bought paint jobs
	carPaint: { [string]: string }, -- car id → paint id
	carGuns: { [string]: string }, -- car id → the car gun on its roof (Config.CarGuns); no entry = none
	rep: { [string]: number }, -- jobs done for each employer (Config.Employers)
	xp: number, -- driver XP (Config.Levels); older saves have none: 0
	properties: { [string]: boolean }, -- owned real estate (Config.Estate ids)
	home: string?, -- the home you spawn at (an owned mansion / villa / house), nil = the depot
	business: { couriers: number, upgrades: { [string]: number }, safe: number, lastTick: number }, -- your company (Config.Business); lastTick = os.time() of the last payout
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
		items = { repair = 1, molotov = 2 },
		paints = { factory = true },
		carPaint = {},
		carGuns = {}, -- every car starts without a gun
		rep = {},
		xp = 0,
		properties = {},
		home = nil,
		business = { couriers = 0, upgrades = {}, safe = 0, lastTick = 0 },
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
	profile.xp = number(saved.xp, 0, 2 ^ 50) -- older saves have no xp: 0 (level 1)
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
	if type(saved.items) == "table" then
		for _, def in Config.Items do
			profile.items[def.id] = number(saved.items[def.id], 0, def.max)
		end
	end
	if type(saved.paints) == "table" then
		for id, owned in saved.paints do
			if owned == true and type(id) == "string" and Economy.findPaint(id) then
				profile.paints[id] = true
			end
		end
	end
	if type(saved.carPaint) == "table" then
		for carId, paintId in saved.carPaint do
			if type(carId) == "string" and type(paintId) == "string" and Economy.findCar(carId) and profile.paints[paintId] then
				profile.carPaint[carId] = paintId
			end
		end
	end
	-- Older saves have none: { } (no car gun anywhere).
	if type(saved.carGuns) == "table" then
		for carId, gunId in saved.carGuns do
			if type(carId) == "string" and type(gunId) == "string" and profile.cars[carId] and Economy.canMount(carId) and Economy.findCarGun(gunId) then
				profile.carGuns[carId] = gunId
			end
		end
	end
	if type(saved.rep) == "table" then
		for _, employer in Config.Employers do
			profile.rep[employer.id] = number(saved.rep[employer.id], 0, 100000)
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
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		-- The first stat is the one the player list sorts by: the best couriers on top.
		local level = Instance.new("IntValue")
		level.Name = "Level"
		level.Value = Levels.levelFor(profile.xp)
		level.Parent = stats
		local money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = profile.money
		money.Parent = stats
		local deliveries = Instance.new("IntValue")
		deliveries.Name = "Deliveries"
		deliveries.Value = profile.deliveries
		deliveries.Parent = stats
		stats.Parent = player
		changed:Fire(player)
	end
end

-- The player list shows the level, money and deliveries; the attributes carry the XP to the client.
local function updateLeaderstats(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local levelNow = Levels.levelFor(profile.xp)
	if player:GetAttribute("Xp") ~= profile.xp then
		player:SetAttribute("Xp", profile.xp)
	end
	if player:GetAttribute("Level") ~= levelNow then
		player:SetAttribute("Level", levelNow)
		player:SetAttribute("Rank", Levels.rank(levelNow))
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local level = stats:FindFirstChild("Level") :: IntValue?
	local money = stats:FindFirstChild("Money") :: IntValue?
	local deliveries = stats:FindFirstChild("Deliveries") :: IntValue?
	if level then
		level.Value = levelNow
	end
	if money then
		money.Value = math.min(profile.money, 2 ^ 31 - 1)
	end
	if deliveries then
		deliveries.Value = profile.deliveries
	end
end
changed.Event:Connect(updateLeaderstats)

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
		items = profile.items,
		paints = profile.paints,
		carPaint = profile.carPaint,
		carGuns = profile.carGuns,
		rep = profile.rep,
		xp = profile.xp,
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

-- Adds (or with a negative amount takes) consumables; false when there is not enough or no room.
function PlayerData.addItem(player: Player, id: string, amount: number): boolean
	local profile = profiles[player]
	local def = Economy.findItem(id)
	if not profile or not def then
		return false
	end
	local count = (profile.items[id] or 0) + amount
	if count < 0 or count > def.max then
		return false
	end
	profile.items[id] = count
	changed:Fire(player)
	return true
end

-- Gives a gun (an employer's reward, the admin tools); true when it is new. equip = put it in the hand too.
function PlayerData.giveWeapon(player: Player, id: string, equip: boolean?): boolean
	local profile = profiles[player]
	if not profile or not Economy.findWeapon(id) then
		return false
	end
	local new = not profile.weapons[id]
	profile.weapons[id] = true
	if equip then
		profile.weapon = id
	end
	changed:Fire(player)
	return new
end

-- Gives a car (an employer's reward, the admin tools); true when it is new.
function PlayerData.giveCar(player: Player, id: string): boolean
	local profile = profiles[player]
	if not profile or not Economy.findCar(id) then
		return false
	end
	local new = not profile.cars[id]
	profile.cars[id] = true
	changed:Fire(player)
	return new
end

-- ── Driver levels (Config.Levels, shared/Levels.luau) ─────────────────────

-- Adds XP; returns the new level and whether it went up.
function PlayerData.addXp(player: Player, amount: number): (number, boolean)
	local profile = profiles[player]
	if not profile then
		return 1, false
	end
	local before = Levels.levelFor(profile.xp)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return before, false
	end
	profile.xp = math.min(profile.xp + math.floor(amount + 0.5), 2 ^ 50)
	local after = Levels.levelFor(profile.xp)
	changed:Fire(player)
	return after, after > before
end

-- The player's driver level (1 when not loaded).
function PlayerData.level(player: Player): number
	local profile = profiles[player]
	return if profile then Levels.levelFor(profile.xp) else 1
end

-- The player's XP (0 when not loaded).
function PlayerData.xp(player: Player): number
	local profile = profiles[player]
	return if profile then profile.xp else 0
end

-- Sets the driver level (the admin tools): the XP becomes exactly what that level needs. Returns the level.
function PlayerData.setLevel(player: Player, level: number): number
	local profile = profiles[player]
	if not profile then
		return 1
	end
	local target = math.clamp(math.floor(level), 1, Config.Levels.MaxLevel)
	profile.xp = Levels.xpFor(target)
	changed:Fire(player)
	return target
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
