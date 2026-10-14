--!strict
-- 8.1 SANDBOX: the upgrades (the owner: "the money players earn needs something to buy"). Bought at the UPGRADES desk
-- in your warehouse (server/Warehouse.luau builds it; its prompt, the owner's only, calls Upgrades.open), shown by
-- client/UpgradeUi.luau; this module decides every purchase. The rules and the numbers: shared/UpgradeRules.luau,
-- Config.SandboxUpgrades. The levels are in the save (profile.sandboxUpgrades, server/PlayerData.luau: read only from a
-- save written with its flag; 8.3: a save from before the warehouse's levels migrated once, UpgradeRules.fromSave).
--   Warehouse         8.3: the warehouse's level, the Garage 1 … the Logistics centre 5 (Config.WarehouseLevels; it took
--                     8.1's More stands' place): its stands (CollectionRules.standsFor: 2 … 20), its building
--                     (server/Warehouse.luau builds it again at the new level, the pieces on their stands); the player
--                     attribute Config.WarehouseLevels.Attribute holds it (the client's guide and picker)
--   Showroom lights   the stands' income × 1.1 a level (CollectionRules.boost: the HUD, the stands' tags, the picker)
--   Van engine        your van's top speed +5 % a level: its SpeedMult attribute (client/Drive.luau), set on every van
--                     of yours that comes into workspace.Cars and when you buy
--   Danny's training  Danny walks +10 % a level: the player attribute Config.SandboxUpgrades.Danny holds the level
--                     (shared/MoveHelperBrain.luau trained, server/MoveHelper.luau's walk)
-- A purchase is checked here: a save loaded, a known upgrade, a warehouse of your own (SandboxPlots: a player without a
-- plot can't), not at its top, the level the window offered (a second click on one card buys once) and the money
-- (PlayerData.spend, the reason "Upgrade", the upgrade's id its SKU). The warehouse and the lights change through
-- Collection.upgrade (what the stands earned up to then is paid at the old rates; a stand you lose sends its piece to
-- the stock). Analytics: UpgradeBought (the level, the id).
--
--   Upgrades.levels(player)          { [id]: level } (a copy; {} before the save loads)
--   Upgrades.warehouseLevel(player)  8.3: the player's warehouse level (the start's before the save loads)
--   Upgrades.buy(player, id, level?) the next level of `id` (level: the one the window offered) → ok, why
--   Upgrades.open(player)            the UPGRADES desk's prompt: the state, then { kind = "open" } to the client
--   Upgrades.admin(player, what)     the admin's ⬆ MAX UPGRADES ("max") / ↺ RESET UPGRADES ("reset"); 8.3: 🏗 LEVEL n
--                                    ("level1" … "level5": the warehouse at that level for free, the pieces on stands
--                                    it hasn't back to the stock) → what to say
--   Upgrades.onChanged(fn)           fn(player) after any change to a player's levels
--   Upgrades.start()                 the remote, joining and leaving, the vans
--
-- The "Upgrades" remote (Config.Robust.Limits.Upgrades requests a second; every input checked):
--   client → server   { kind = "state" } | { kind = "buy", id, level }; a refusal comes back as a Notice (its why)
--   server → client   { kind = "state", levels, money } after every change (once a frame), when the save has loaded and
--                     when asked; { kind = "open" } opens the window; { kind = "bought", id, level }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.UpgradeRules)
local WarehouseLevels = require(Shared.WarehouseLevels) -- 8.3: the warehouse's levels
local PlayerData = require(script.Parent.PlayerData)
local Collection = require(script.Parent.Collection)
local SandboxPlots = require(script.Parent.SandboxPlots)

local Upgrades = {}

local remote = Net.get("Upgrades")
local notice = Net.get("Notice")

local listeners: { (Player) -> () } = {}
local known: { [Player]: boolean } = {} -- the save has loaded (the effects are set)
local pushing: { [Player]: boolean } = {} -- a state push waits for the frame's end
local started = false

-- The player's levels in their profile (nil: no save yet); a profile without them gets none.
local function levelsOf(player: Player): Rules.Levels?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	if type(profile.sandboxUpgrades) ~= "table" then
		profile.sandboxUpgrades = Rules.empty()
	end
	return profile.sandboxUpgrades
end

local function sendState(player: Player)
	pushing[player] = nil
	local profile = PlayerData.get(player)
	local levels = levelsOf(player)
	if not profile or not levels or not player.Parent then
		return
	end
	remote:FireClient(player, { kind = "state", levels = table.clone(levels), money = profile.money })
end

-- The state goes out once at the frame's end, however many changes it had.
local function pushState(player: Player)
	if pushing[player] then
		return
	end
	pushing[player] = true
	task.defer(function()
		if pushing[player] then
			sendState(player)
		end
	end)
end

-- The van's engine on one car (its owner's level): its SpeedMult (client/Drive.luau: MaxSpeed × SpeedMult).
local function tuneCar(car: Instance, levels: Rules.Levels)
	car:SetAttribute("SpeedMult", Rules.vanSpeed(levels))
end

-- The effects that live outside the collection: every van of the player's in workspace.Cars, Danny's attribute.
local function applyEffects(player: Player)
	local levels = levelsOf(player)
	if not levels then
		return
	end
	player:SetAttribute(Config.SandboxUpgrades.Danny, Rules.level(levels, "danny"))
	player:SetAttribute(Config.WarehouseLevels.Attribute, Rules.warehouseLevel(levels)) -- 8.3
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		for _, car in cars:GetChildren() do
			if car:GetAttribute("OwnerId") == player.UserId then
				tuneCar(car, levels)
			end
		end
	end
end

-- Changes the player's levels (`apply` on them, then cleaned): through the collection (the income settled at the old
-- rates, the stands fitted), the effects, the state, the listeners. → how many pieces left a stand they lost.
local function change(player: Player, apply: (Rules.Levels) -> ()): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	local moved = Collection.upgrade(player, function()
		local levels = levelsOf(player) :: Rules.Levels
		apply(levels)
		profile.sandboxUpgrades = Rules.clean(levels)
	end)
	applyEffects(player)
	pushState(player)
	for _, fn in listeners do
		task.spawn(fn, player)
	end
	return moved
end

-- ── The API ────────────────────────────────────────────────────────────────

function Upgrades.levels(player: Player): Rules.Levels
	local levels = levelsOf(player)
	return if levels then table.clone(levels) else {}
end

function Upgrades.warehouseLevel(player: Player): number
	local profile = PlayerData.get(player)
	return Rules.warehouseLevel(if profile then profile.sandboxUpgrades else nil)
end

function Upgrades.buy(player: Player, id: any, expect: any): (boolean, string?)
	local profile = PlayerData.get(player)
	if not profile then
		return false, "Your save isn't loaded yet."
	end
	local def = Rules.def(id)
	if not def then
		return false, "That's no upgrade."
	end
	if not SandboxPlots.of(player) then
		return false, "Upgrades are for a warehouse of your own: wait for a free plot."
	end
	local level = Rules.level(levelsOf(player), id)
	local price = Rules.price(id, level)
	if not price then
		return false, `{def.name} is at its top level.`
	end
	if expect ~= nil and expect ~= level + 1 then
		sendState(player) -- (the window offered a level that is bought already: it is shown again)
		return false, nil
	end
	if not PlayerData.spend(player, price, "Upgrade", id) then
		return false, `{def.name} costs {Rules.money(price)}: you have {Rules.money(profile.money)}.`
	end
	local now = level + 1
	change(player, function(levels: Rules.Levels)
		levels[id] = now
	end)
	PlayerData.track("event", player, "UpgradeBought", now, id)
	remote:FireClient(player, { kind = "bought", id = id, level = now })
	return true, nil
end

function Upgrades.open(player: Player)
	if not levelsOf(player) then
		notice:FireClient(player, "Your save isn't loaded yet.")
		return
	end
	sendState(player)
	remote:FireClient(player, { kind = "open" })
end

function Upgrades.admin(player: Player, what: string): string
	if not levelsOf(player) then
		return "ADMIN: no save loaded (the upgrades are in it)."
	end
	if what == "max" then
		change(player, function(levels: Rules.Levels)
			for id, level in Rules.full() do
				levels[id] = level
			end
		end)
		return `ADMIN: every upgrade at its top ({Collection.stands(player)} stands, income ×{string.format("%.2f", Collection.boost(player))}).`
	end
	local wanted = tonumber(string.match(what, "^level(%d)$"))
	if wanted then
		local level = WarehouseLevels.clamp(wanted)
		local moved = change(player, function(levels: Rules.Levels)
			levels.warehouse = level
		end)
		local back = if moved == 1 then " 1 piece went back to the stock." elseif moved > 1 then ` {moved} pieces went back to the stock.` else ""
		return `ADMIN: the warehouse at {WarehouseLevels.summary(level)}.{back}`
	end
	local moved = change(player, function(levels: Rules.Levels)
		table.clear(levels)
	end)
	local back = if moved == 1 then " 1 piece went back to the stock." elseif moved > 1 then ` {moved} pieces went back to the stock.` else ""
	return `ADMIN: the upgrades reset ({Collection.stands(player)} stands).{back}`
end

function Upgrades.onChanged(fn: (Player) -> ())
	table.insert(listeners, fn)
end

-- ── Joining, leaving, the remote ──────────────────────────────────────────

-- The save has loaded (PlayerData.Changed fires then first): the effects set, the client told.
local function joined(player: Player)
	if known[player] or not player.Parent or not levelsOf(player) then
		return
	end
	known[player] = true
	applyEffects(player)
	pushState(player)
end

local function left(player: Player)
	known[player] = nil
	pushing[player] = nil
end

-- A van that comes into workspace.Cars (PLAY, CAR, a move's START, an admin's BRING VAN): its owner's engine.
local function watchCars(cars: Instance)
	cars.ChildAdded:Connect(function(car: Instance)
		local id = car:GetAttribute("OwnerId")
		local owner = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
		local levels = if owner then levelsOf(owner) else nil
		if levels then
			tuneCar(car, levels)
		end
	end)
end

local function onRemote(player: Player, message: any)
	if not Net.limit(player, "Upgrades", Config.Robust.Limits.Upgrades) then
		return
	end
	if type(message) ~= "table" then
		return
	end
	if message.kind == "state" then
		sendState(player)
	elseif message.kind == "buy" then
		local ok, why = Upgrades.buy(player, message.id, message.level)
		if not ok and why then
			notice:FireClient(player, why)
		end
	end
end

function Upgrades.start()
	if started then
		return
	end
	started = true
	remote.OnServerEvent:Connect(onRemote)
	PlayerData.Changed:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(left)
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		watchCars(cars)
	else
		local waiting: RBXScriptConnection? = nil
		waiting = workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Cars" and waiting then
				waiting:Disconnect()
				waiting = nil
				watchCars(child)
			end
		end)
	end
end

return Upgrades
