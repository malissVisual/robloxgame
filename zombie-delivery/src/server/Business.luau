--!strict
-- Your delivery company (Config.Business), run from an office computer. Owning an office (server/Estate.luau
-- officeOf: the biggest one you own) opens the company; the office decides how many couriers it can seat.
--
--   * The office computer (World.OfficePrompts, a ProximityPrompt "OfficePrompt" with the attribute Office) opens the
--     company window on your screen (client/BusinessUi.luau) through the `Business` remote. Somebody else's office
--     opens its listing instead (the `Estate` remote: buy it yourself).
--   * Actions (client → server, `Business` remote: action, arg), every one checked here, nothing trusted:
--       "hire"     a courier for Config.Business.CourierCost, up to the office's couriers
--       "fire"     one courier (no refund)
--       "upgrade"  the next level of a Config.Business.Upgrades track (arg = its id), baseCost × costGrowth^level
--       "collect"  the safe → your money
--     all four only standing at the computer of an office you own. "open" / "sync" / "close" ask for the state
--     (sync once after loading: the welcome-back message waits for it) and tell whether the window is open (an open
--     window gets the safe pushed after every payout).
--   * Earnings: every TICK (10) seconds online the working couriers (at most the office's seats) earn
--     CourierPerMinute × the upgrades' multiplier per minute into the safe, up to SafeCap. On join the time since
--     the profile's business.lastTick (os.time) pays OfflineShare of that, for at most OfflineHours, and the client
--     says "While you were away your company made $x" once it is there.
--   * Server → client payload: the company state (see stateFor), with open = true when the window should open and
--     welcome = { amount, seconds } once after a join that earned something.
--
-- The profile's business table (server/PlayerData.luau) is { couriers, upgrades = { [id] = level }, safe, lastTick };
-- PlayerData saves and parses it (stream "estate-logic"). The admin tools may fill the safe directly; Business.addToSafe
-- and Business.push are there for them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local PlayerData = require(script.Parent.PlayerData)
local Estate = require(script.Parent.Estate)

local Business = {}

type BusinessData = { couriers: number, upgrades: { [string]: number }, safe: number, lastTick: number }
type UpgradeDef = { id: string, name: string, description: string, maxLevel: number, baseCost: number, costGrowth: number, perLevel: number }

local B = Config.Business
local TICK = 10 -- seconds between two payouts into the safe while online
local MAX_ONLINE_STEP = 60 -- a payout never covers more than this (a stalled server does not pay a lump)
local ACTION_GAP = 0.25 -- seconds between two actions of one player (spam guard)
local REACH_FLAT = 26 -- "at the office": this close to the office computer on the ground plane …
local REACH_UP = 10 -- … and on the same floor (the towers stack offices)
local LOAD_WAIT = 30 -- seconds a joining player's save may take to load

local remote = Net.get("Business")
local notice = Net.get("Notice")

-- Per player, for this session only.
local started: { [Player]: boolean } = {} -- the save is loaded and the offline earnings are paid
local ready: { [Player]: boolean } = {} -- the client asked for its state (sync): it listens now
local viewing: { [Player]: boolean } = {} -- the company window is open on their screen
local carry: { [Player]: number } = {} -- the fraction of a dollar not in the safe yet
local welcome: { [Player]: { amount: number, seconds: number } } = {} -- offline earnings waiting to be told
local lastAction: { [Player]: number } = {}
local pushQueued: { [Player]: boolean } = {}

-- Where every office's computer is (office id → points): World.OfficePrompts, or a scan for OfficePrompt.
local officeSpots: { [string]: { Vector3 } } = {}

-- ── The numbers (pure) ─────────────────────────────────────────────────────

local function findEstate(id: string): Config.EstateDef?
	for _, def in Config.Estate.Properties do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function findUpgrade(id: string): UpgradeDef?
	for _, def in B.Upgrades do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- The earnings multiplier of these upgrade levels: 1 + Σ level × perLevel.
function Business.multiplier(upgrades: { [string]: number }): number
	local m = 1
	for _, def in B.Upgrades do
		m += math.clamp(upgrades[def.id] or 0, 0, def.maxLevel) * def.perLevel
	end
	return m
end

-- What the next level of an upgrade costs (level = the level you have now).
function Business.upgradeCost(def: UpgradeDef, level: number): number
	return math.floor(def.baseCost * def.costGrowth ^ level + 0.5)
end

-- What the working couriers earn per minute while you are online.
function Business.perMinute(working: number, upgrades: { [string]: number }): number
	return working * B.CourierPerMinute * Business.multiplier(upgrades)
end

-- The offline earnings for `seconds` away (OfflineShare, at most OfflineHours), before the safe's cap.
function Business.offlineEarnings(working: number, upgrades: { [string]: number }, seconds: number): number
	local away = math.clamp(seconds, 0, B.OfflineHours * 3600)
	return math.floor(Business.perMinute(working, upgrades) * B.OfflineShare * away / 60)
end

-- ── The profile ────────────────────────────────────────────────────────────

-- The player's company data, repaired if anything is missing (an older save, a fallback).
local function dataOf(player: Player): BusinessData?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local data: any = (profile :: any).business
	if type(data) ~= "table" then
		data = { couriers = 0, upgrades = {}, safe = 0, lastTick = 0 }
		;(profile :: any).business = data
	end
	if type(data.couriers) ~= "number" or data.couriers ~= data.couriers then
		data.couriers = 0
	end
	if type(data.upgrades) ~= "table" then
		data.upgrades = {}
	end
	if type(data.safe) ~= "number" or data.safe ~= data.safe then
		data.safe = 0
	end
	if type(data.lastTick) ~= "number" or data.lastTick ~= data.lastTick then
		data.lastTick = 0
	end
	return data :: BusinessData
end

local function owns(player: Player, id: string): boolean
	if Estate.owns(player, id) then
		return true
	end
	-- [FALLBACK] until Estate is filled in: the profile's properties (the contract's field).
	local profile = PlayerData.get(player)
	local properties: any = profile and (profile :: any).properties
	return type(properties) == "table" and properties[id] == true
end

-- The office the company runs from (the biggest one owned) and its seats.
local function officeOf(player: Player): (string?, number)
	local id = Estate.officeOf(player)
	if not id then
		-- [FALLBACK] until Estate is filled in: the owned office with the most seats.
		local best = 0
		for _, def in Config.Estate.Properties do
			if def.kind == "office" and owns(player, def.id) and (def.couriers or 0) > best then
				best = def.couriers or 0
				id = def.id
			end
		end
	end
	local def = if id then findEstate(id) else nil
	if not def or def.kind ~= "office" then
		return nil, 0
	end
	return def.id, def.couriers or 0
end

-- How many couriers are working: the hired ones the office has seats for.
local function workingOf(player: Player, data: BusinessData): number
	local office, seats = officeOf(player)
	if not office then
		return 0
	end
	return math.clamp(math.floor(data.couriers), 0, seats)
end

-- ── Where the offices are ──────────────────────────────────────────────────

local function promptPoint(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

local function addSpot(office: string, point: Vector3)
	local list = officeSpots[office]
	if not list then
		list = {}
		officeSpots[office] = list
	end
	table.insert(list, point)
end

-- The office computer of an owned office the player stands at, or nil.
local function officeAt(player: Player): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local here = root.Position
	for office, points in officeSpots do
		for _, point in points do
			local flat = Vector3.new(here.X - point.X, 0, here.Z - point.Z).Magnitude
			if flat <= REACH_FLAT and math.abs(here.Y - point.Y) <= REACH_UP and owns(player, office) then
				return office
			end
		end
	end
	return nil
end

-- A point to send the GPS to: the computer of the company's office.
local function officePoint(office: string?): Vector3?
	local points = if office then officeSpots[office] else nil
	return if points then points[1] else nil
end

-- ── Earnings ───────────────────────────────────────────────────────────────

-- Pays the time since lastTick (online) into the safe and moves lastTick to now. Returns what went in.
local function accrue(player: Player): number
	local data = dataOf(player)
	if not data or not started[player] then
		return 0
	end
	local now = os.time()
	local seconds = math.clamp(now - data.lastTick, 0, MAX_ONLINE_STEP)
	data.lastTick = now
	local working = workingOf(player, data)
	if working <= 0 or seconds <= 0 then
		return 0
	end
	local earned = Business.perMinute(working, data.upgrades) * seconds / 60 + (carry[player] or 0)
	local whole = math.floor(earned)
	carry[player] = earned - whole
	local room = math.max(0, B.SafeCap - math.floor(data.safe))
	local added = math.min(whole, room)
	if added < whole then
		carry[player] = 0 -- the safe is full: nothing piles up behind it
	end
	data.safe = math.floor(data.safe) + added
	return added
end

-- Adds money to the safe (the admin tools), up to SafeCap. Returns what went in.
function Business.addToSafe(player: Player, amount: number): number
	local data = dataOf(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	local added = math.min(math.floor(amount), math.max(0, B.SafeCap - math.floor(data.safe)))
	data.safe = math.floor(data.safe) + added
	Business.push(player)
	return added
end

-- ── The state for the client ───────────────────────────────────────────────

local function stateFor(player: Player): { [string]: any }?
	local data = dataOf(player)
	if not data then
		return nil
	end
	local profile = PlayerData.get(player)
	local office, seats = officeOf(player)
	local officeDef = if office then findEstate(office) else nil
	local working = workingOf(player, data)
	local levels: { [string]: number } = {}
	for _, def in B.Upgrades do
		levels[def.id] = math.clamp(math.floor(data.upgrades[def.id] or 0), 0, def.maxLevel)
	end
	local at = officeAt(player)
	return {
		company = `{player.DisplayName} Express`,
		office = office,
		officeName = if officeDef then officeDef.name else nil,
		officePos = officePoint(office),
		seats = seats,
		couriers = math.max(0, math.floor(data.couriers)),
		working = working,
		upgrades = levels,
		multiplier = Business.multiplier(levels),
		perMinute = Business.perMinute(working, levels),
		safe = math.floor(data.safe),
		safeCap = B.SafeCap,
		money = if profile then profile.money else 0,
		atOffice = at ~= nil,
		userId = player.UserId,
	}
end

local function send(player: Player, extra: { [string]: any }?)
	local state = stateFor(player)
	if not state or not player.Parent then
		return
	end
	if extra then
		for key, value in extra do
			state[key] = value
		end
	end
	remote:FireClient(player, state)
end

-- Sends the state again (the window shows the new safe). Batched: many changes in one frame send once.
function Business.push(player: Player)
	if pushQueued[player] or not ready[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		if player.Parent then
			send(player, nil)
		end
	end)
end

-- The welcome-back message, once the client listens and the offline earnings are known.
local function tellWelcome(player: Player)
	local w = welcome[player]
	if not w or not ready[player] or not started[player] then
		return
	end
	welcome[player] = nil
	send(player, { welcome = w })
end

-- ── Joining: the offline earnings ──────────────────────────────────────────

local function begin(player: Player)
	local waited = 0
	while player.Parent and not PlayerData.get(player) and waited < LOAD_WAIT do
		waited += task.wait(0.5)
	end
	local data = dataOf(player)
	if not player.Parent or not data or started[player] then
		return
	end
	local now = os.time()
	local working = workingOf(player, data)
	if data.lastTick > 0 and working > 0 then
		local away = now - data.lastTick
		local earned = Business.offlineEarnings(working, data.upgrades, away)
		local added = math.min(earned, math.max(0, B.SafeCap - math.floor(data.safe)))
		if added > 0 then
			data.safe = math.floor(data.safe) + added
			welcome[player] = { amount = added, seconds = math.clamp(away, 0, B.OfflineHours * 3600) }
		end
	end
	data.lastTick = now
	started[player] = true
	if ready[player] then
		send(player, nil)
	end
	tellWelcome(player)
end

-- ── Actions ────────────────────────────────────────────────────────────────

local function say(player: Player, text: string)
	notice:FireClient(player, text)
end

-- The office the player manages from right now, or nil (and why not, said).
local function atOwnOffice(player: Player): string?
	local office = officeOf(player)
	if not office then
		say(player, "You have no office. Buy one in a tower downtown or at the harbor to run a company.")
		return nil
	end
	local at = officeAt(player)
	if not at then
		say(player, "Manage your company at your office computer.")
		return nil
	end
	return at
end

local function hire(player: Player, data: BusinessData)
	local office, seats = officeOf(player)
	if not office then
		return
	end
	if data.couriers >= seats then
		say(player, `Every desk is taken: this office seats {seats} couriers. A bigger office seats more.`)
		return
	end
	if not PlayerData.spend(player, B.CourierCost, "Company", "Courier") then
		say(player, `Hiring a courier costs ${B.CourierCost}.`)
		return
	end
	data.couriers = math.floor(data.couriers) + 1
	say(player, `A new courier joined your company: {data.couriers} on the road.`)
end

local function fire(player: Player, data: BusinessData)
	if data.couriers < 1 then
		return
	end
	data.couriers = math.floor(data.couriers) - 1
	say(player, `You let a courier go. {data.couriers} left.`)
end

local function upgrade(player: Player, data: BusinessData, id: any)
	local def = if type(id) == "string" then findUpgrade(id) else nil
	if not def then
		return
	end
	local level = math.clamp(math.floor(data.upgrades[def.id] or 0), 0, def.maxLevel)
	if level >= def.maxLevel then
		say(player, `{def.name} is at the top level.`)
		return
	end
	local cost = Business.upgradeCost(def, level)
	if not PlayerData.spend(player, cost, "Company", def.id) then
		say(player, `{def.name} level {level + 1} costs ${cost}.`)
		return
	end
	data.upgrades[def.id] = level + 1
	say(player, `{def.name} level {level + 1}: your couriers earn ×{string.format("%.2f", Business.multiplier(data.upgrades))} now.`)
end

local function collect(player: Player, data: BusinessData)
	local amount = math.floor(data.safe)
	if amount < 1 then
		say(player, "The safe is empty. Your couriers are on it.")
		return
	end
	data.safe -= amount
	PlayerData.addMoney(player, amount, "CompanySafe")
	say(player, `You took ${amount} out of the company safe.`)
end

local function onAction(player: Player, action: any, arg: any)
	if type(action) ~= "string" then
		return
	end
	if action == "close" then
		viewing[player] = nil
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or -math.huge) < ACTION_GAP then
		return
	end
	lastAction[player] = now
	if action == "sync" then
		ready[player] = true
		if started[player] then
			send(player, nil)
			tellWelcome(player)
		end
		return
	end
	local data = dataOf(player)
	if not data or not started[player] then
		return
	end
	ready[player] = true
	if action == "open" then
		viewing[player] = true
		accrue(player)
		send(player, nil)
		return
	end
	if action ~= "hire" and action ~= "fire" and action ~= "upgrade" and action ~= "collect" then
		return
	end
	if not atOwnOffice(player) then
		send(player, nil)
		return
	end
	-- Pay the seconds since the last payout first, at the old numbers.
	accrue(player)
	if action == "hire" then
		hire(player, data)
	elseif action == "fire" then
		fire(player, data)
	elseif action == "upgrade" then
		upgrade(player, data, arg)
	else
		collect(player, data)
	end
	viewing[player] = true
	send(player, nil)
end

-- The office computer was used.
local function onPrompt(player: Player, office: string)
	local def = findEstate(office)
	if not def then
		return
	end
	if not owns(player, office) then
		say(player, `{def.name} is not yours. Buy it to run your delivery company from here.`)
		Net.get("Estate"):FireClient(player, office) -- its listing (client/EstateUi.luau)
		return
	end
	if not started[player] then
		return
	end
	ready[player] = true
	viewing[player] = true
	accrue(player)
	send(player, { open = true })
end

-- ── Start ──────────────────────────────────────────────────────────────────

local function connectPrompt(prompt: ProximityPrompt, office: string)
	local point = promptPoint(prompt)
	if point then
		addSpot(office, point)
	end
	prompt.Triggered:Connect(function(player)
		onPrompt(player, office)
	end)
end

local function connectPrompts()
	local world: any = World
	local entries = world.OfficePrompts
	local found = 0
	if type(entries) == "table" then
		for _, entry in entries do
			local prompt = entry.prompt
			local office = entry.office or (prompt and prompt:GetAttribute("Office"))
			if typeof(prompt) == "Instance" and prompt:IsA("ProximityPrompt") and type(office) == "string" then
				connectPrompt(prompt, office)
				found += 1
			end
		end
	end
	if found == 0 then
		-- [FALLBACK] no World.OfficePrompts: look for the prompts in the world once.
		for _, instance in workspace:GetDescendants() do
			if instance:IsA("ProximityPrompt") and instance.Name == "OfficePrompt" then
				local office = instance:GetAttribute("Office")
				if type(office) == "string" then
					connectPrompt(instance, office)
					found += 1
				end
			end
		end
	end
	-- The office's room spawn counts as the office too (the computer is in the same room).
	local spawns = world.EstateSpawns
	if type(spawns) == "table" then
		for id, spot in spawns do
			local def = if type(id) == "string" then findEstate(id) else nil
			if def and def.kind == "office" and officeSpots[id] and typeof(spot) == "CFrame" then
				addSpot(id, spot.Position)
			end
		end
	end
	if found == 0 then
		warn("[Business] no office computers (World.OfficePrompts) in the world: the companies cannot be managed")
	end
end

local function forget(player: Player)
	started[player] = nil
	ready[player] = nil
	viewing[player] = nil
	carry[player] = nil
	welcome[player] = nil
	lastAction[player] = nil
	pushQueued[player] = nil
end

function Business.start()
	connectPrompts()
	remote.OnServerEvent:Connect(onAction)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(begin, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(begin, player)
	end
	-- Pay before the save goes (PlayerData saves on PlayerRemoving too; whichever runs first, lastTick is recent).
	Players.PlayerRemoving:Connect(function(player)
		accrue(player)
		forget(player)
	end)
	-- Money or property changed (a purchase, the admin tools): an open window shows it.
	PlayerData.Changed:Connect(function(player: Player)
		if viewing[player] then
			Business.push(player)
		end
	end)
	-- The payouts.
	task.spawn(function()
		while true do
			task.wait(TICK)
			for player in started do
				if player.Parent then
					local added = accrue(player)
					if added > 0 and viewing[player] then
						Business.push(player)
					end
				end
			end
		end
	end)
end

return Business
