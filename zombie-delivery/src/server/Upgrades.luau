--!strict
-- 8.1 SANDBOX: the upgrades (the owner: "the money players earn needs something to buy"). Bought at the UPGRADES desk
-- in your warehouse (server/Warehouse.luau builds it; its prompt, the owner's only, calls Upgrades.open), shown by
-- client/UpgradeUi.luau; this module decides every purchase. The rules and the numbers: shared/UpgradeRules.luau,
-- Config.SandboxUpgrades. The levels are in the save (profile.sandboxUpgrades, server/PlayerData.luau: read only from a
-- save written with its flag; 8.3: an older real save without warehouseLevelKept gets the warehouse at level 4, what
-- it had: UpgradeRules.fromSave).
--   ZDC Warehouse     8.3 (design/warehouse-levels/KONTRAKT.md): the warehouse's level, upgrade level k is warehouse
--                     level k + 1 (1 Garage · 2 stands … 5 Logistics Center · 24): UpgradeRules.warehouseLevel. Bought,
--                     server/Warehouse.luau rebuilds the owner's warehouse at the new level (it listens here) and the
--                     stands' pieces stay on their stands (a level up never takes a stand away); the player attribute
--                     Config.SandboxUpgrades.WarehouseAttribute ("WarehouseLevel") holds the level for the client
--   More stands       +2 display stands a level (CollectionRules.standsFor; WarehouseLayout's small stands): 8.3 only
--                     from the Big Warehouse (level 4) on, locked below it (UpgradeRules.locked: "Needs the Big
--                     Warehouse"), 12 … 20 there and 24 … 32 at level 5
--   Showroom lights   the stands' income × 1.1 a level (CollectionRules.boost: the HUD, the stands' tags, the picker)
--   Van engine        your van's top speed +5 % a level: its SpeedMult attribute (client/Drive.luau), set on every van
--                     of yours that comes into workspace.Cars and when you buy
--   Danny's training  Danny walks +10 % a level: the player attribute Config.SandboxUpgrades.Danny holds the level
--                     (shared/MoveHelperBrain.luau trained, server/MoveHelper.luau's walk)
-- A purchase is checked here: a save loaded, a known upgrade, a warehouse of your own (SandboxPlots: a player without a
-- plot can't), 8.3: not locked (UpgradeRules.locked: its reason is the refusal), not at its top, the level the window
-- offered (a second click on one card buys once) and the money (PlayerData.spend, the reason "Upgrade", the upgrade's
-- id its SKU). The warehouse, the stands and the lights change through Collection.upgrade (what the stands earned up to
-- then is paid at the old rates; a stand you lose sends its piece to the stock). Analytics: UpgradeBought (the level,
-- the id).
--
--   Upgrades.levels(player)          { [id]: level } (a copy; {} before the save loads)
--   Upgrades.warehouseLevel(player)  8.3: the player's warehouse level (1 … 5; the Garage's 1 before the save loads)
--   Upgrades.buy(player, id, level?) the next level of `id` (level: the one the window offered) → ok, why
--   Upgrades.open(player)            the UPGRADES desk's prompt: the state, then { kind = "open" } to the client
--   Upgrades.admin(player, what)     the admin's ⬆ MAX UPGRADES ("max": the warehouse at level 5 too) / ↺ RESET
--                                    UPGRADES ("reset": back to the garage, level 1); 8.3: 🏗 LV n ("level1" …
--                                    "level5": the warehouse at that level for free, the other upgrades kept, the
--                                    pieces on stands it hasn't back to the stock) → what to say
--   Upgrades.onChanged(fn)           fn(player) after any change to a player's levels, 8.3: and when their save has
--                                    loaded (server/Warehouse.luau builds their warehouse at its level then)
--   Upgrades.onBought(fn)            8.3: fn(player, id, level) after a level bought at the desk (not the admin's, not a
--                                    save loading: server/SandboxBadges.luau's firstUpgrade)
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
local WarehouseLayout = require(Shared.WarehouseLayout) -- 8.3: the warehouse levels' names (the admin's answers)
local PlayerData = require(script.Parent.PlayerData)
local Collection = require(script.Parent.Collection)
local SandboxPlots = require(script.Parent.SandboxPlots)

local Upgrades = {}

local remote = Net.get("Upgrades")
local notice = Net.get("Notice")

local listeners: { (Player) -> () } = {}
local buyers: { (Player, string, number) -> () } = {} -- 8.3: Upgrades.onBought's fns
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

-- The effects that live outside the collection: every van of the player's in workspace.Cars, Danny's attribute, 8.3:
-- the warehouse level's attribute (the client's cards, the stands' sizes in the picker, the guide).
local function applyEffects(player: Player)
	local levels = levelsOf(player)
	if not levels then
		return
	end
	player:SetAttribute(Config.SandboxUpgrades.Danny, Rules.level(levels, "danny"))
	player:SetAttribute(Config.SandboxUpgrades.WarehouseAttribute, Rules.warehouseLevel(levels))
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
	return Rules.warehouseLevel(levelsOf(player))
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
	local locked = Rules.locked(levelsOf(player), id) -- 8.3: More stands below the Big Warehouse
	if locked then
		return false, locked -- (the reason the window's locked card shows: "Needs the Big Warehouse")
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
	for _, fn in buyers do
		task.spawn(fn, player, id, now)
	end
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

-- 8.3: the player's warehouse in words for the admin's answers: "warehouse level 5, the Logistics Center".
local function warehouseWords(player: Player): string
	local level = Rules.warehouseLevel(levelsOf(player))
	return `warehouse level {level}, the {WarehouseLayout.level(level).name}`
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
		return `ADMIN: every upgrade at its top ({warehouseWords(player)}: {Collection.stands(player)} stands, income ×{string.format("%.2f", Collection.boost(player))}).`
	end
	local wanted = tonumber(string.match(what, "^level(%d)$"))
	if wanted then
		-- (8.3: 🏗 LV n: warehouse level n is the ZDC Warehouse upgrade's level n - 1; 0, the Garage, is not kept)
		local def = Rules.def("warehouse")
		local k = math.clamp(wanted - 1, 0, if def then def.max else 0)
		local moved = change(player, function(levels: Rules.Levels)
			(levels :: any).warehouse = if k > 0 then k else nil
		end)
		local back = if moved == 1 then " 1 piece went back to the stock." elseif moved > 1 then ` {moved} pieces went back to the stock.` else ""
		return `ADMIN: the {warehouseWords(player)} ({Collection.stands(player)} stands).{back}`
	end
	local moved = change(player, function(levels: Rules.Levels)
		table.clear(levels)
	end)
	local back = if moved == 1 then " 1 piece went back to the stock." elseif moved > 1 then ` {moved} pieces went back to the stock.` else ""
	return `ADMIN: the upgrades reset ({warehouseWords(player)}: {Collection.stands(player)} stands).{back}`
end

function Upgrades.onChanged(fn: (Player) -> ())
	table.insert(listeners, fn)
end

function Upgrades.onBought(fn: (Player, string, number) -> ())
	table.insert(buyers, fn)
end

-- ── Joining, leaving, the remote ──────────────────────────────────────────

-- The save has loaded (PlayerData.Changed fires then first): the effects set, the client told, 8.3: the listeners
-- hear (the levels they had before were none: server/Warehouse.luau builds the warehouse at the save's level).
local function joined(player: Player)
	if known[player] or not player.Parent or not levelsOf(player) then
		return
	end
	known[player] = true
	applyEffects(player)
	pushState(player)
	for _, fn in listeners do
		task.spawn(fn, player)
	end
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
