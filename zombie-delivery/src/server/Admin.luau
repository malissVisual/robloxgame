--!strict
-- The admin tools for testing (Config.Admin): the admin panel's SANDBOX tab (shared/SandboxAdmin.luau's buttons: the
-- money, the runs, the warehouse's stock and stands, the book, the upgrades, the paints, the teleports) and the OP
-- toggles FLY and NOCLIP. Admins (a Studio Play test, the owner of a user-owned place, Config.Admin.UserIds) get the
-- player attribute "Admin" (the client shows the panel, client/AdminPanel.luau); every command is checked here again.
-- 10.6 (only the sandbox is the game): the city's commands are gone (the money and XP, the cars, guns and items, the
-- jobs and missions, the estate, the enemies, the time and the weather, the buddies: in git's history up to 10.5).
-- 6.13: every admin's player attribute AdminAnalytics carries the analytics line (server/Analytics.luau summary: on or
-- off, what this server logged), refreshed every second.
--
-- Commands over the "Admin" remote (name, arg, target?): target = the UserId of a player in this server (nil: you).
-- Every notice goes to the target, and a copy to you. Every argument is checked here; a bad one does nothing but say so.
--   fly [T] / noclip [T]      boolean?: toggle (or set) the player attributes AdminFly, AdminNoclip (client/AdminFly.luau)
--   sandbox [T] id            the panel's SANDBOX tab (shared/SandboxAdmin.luau checks the id; at most
--                             Config.Robust.Limits.AdminSandbox a second from one admin): "money" +$10 000, "broke" the
--                             money at $0; 9.7 the Runs group: "rundiff_<id>" the difficulty of the admin's next run,
--                             "run_<house>" a run on that house for the TARGET alone, "runend" the TARGET's run ends
--                             (server/Runs.luau admin), "clock" / "horde" (Moving.admin's time / horde); "fill" 10 random
--                             pieces in random condition into the stock (Collection.add), "clear" the stock emptied ($0
--                             for it: Collection.clear, else every piece sold and the money put back), "stands" the
--                             stock's pieces on the free display stands (Collection.display, Collection.stands: 8.3, the
--                             warehouse level's); "house" to the front door of the TARGET's run's house (else the
--                             farmstead's), "warehouse" to the plot's spawn, "lobby" to the lobby's plaza; 8.1: "upmax" /
--                             "upreset" every upgrade at its top for free / none (server/Upgrades.luau admin); 8.2:
--                             "bookfill" / "bookclear" every piece of the collection book found (its milestones pay) /
--                             the book and its milestones empty (server/CollectionBook.luau admin); 8.3: "paintall" /
--                             "paintreset" every paint and livery of the PAINT shop owned for free / none, the van in the
--                             factory's look (server/VanPaint.luau admin); 8.3: "level1" … "level5" the warehouse at that
--                             level for free (Upgrades.admin: its building rebuilt, the pieces on stands it hasn't back to
--                             the stock)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Server = script.Parent
local PlayerData = require(Server.PlayerData)

local Admin = {}

local notice = Net.get("Notice")
local rng = Random.new()

local lastCommand: { [Player]: number } = {}
-- 4.5: who runs the command on this target right now (another admin): the notices go to both.
local acting: { [Player]: Player } = {}

function Admin.isAdmin(player: Player): boolean
	if Config.Admin.InStudio and RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId then
		return true
	end
	return table.find(Config.Admin.UserIds, player.UserId) ~= nil
end

-- ── Helpers ────────────────────────────────────────────────────────────────

-- A notice to the player; when another admin runs the command on them (4.5), they see who did it and the admin gets a
-- copy with the target's name.
local function say(player: Player, text: string)
	local admin = acting[player]
	if admin and admin ~= player then
		local body = (string.gsub(text, "^ADMIN: ", ""))
		notice:FireClient(player, `ADMIN {admin.DisplayName}: {body}`)
		if admin.Parent then
			notice:FireClient(admin, `ADMIN → {player.DisplayName}: {body}`)
		end
		return
	end
	notice:FireClient(player, text)
end

-- A real, finite number from the remote (nil for anything else: NaN, ±inf, a string).
local function finite(value: any): number?
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

-- $1,234,567
local function moneyText(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

-- The OP toggles: player attributes the client acts on (client/AdminFly.luau).
local FLAGS: { [string]: { attribute: string, name: string } } = {
	fly = { attribute = "AdminFly", name = "FLY (WASD where you look, Space up, Ctrl down, Shift faster)" },
	noclip = { attribute = "AdminNoclip", name = "NOCLIP (through walls)" },
}

local function setFlag(player: Player, command: string, arg: any)
	local flag = FLAGS[command]
	local on = if type(arg) == "boolean" then arg else player:GetAttribute(flag.attribute) ~= true
	player:SetAttribute(flag.attribute, if on then true else nil)
	say(player, `ADMIN: {flag.name} {if on then "ON" else "OFF"}.`)
end

-- A character (out of its seat first) to a spot; true when it went.
local function moveCharacter(player: Player, at: CFrame): boolean
	local character = player.Character
	local humanoid = humanoidOf(player)
	if not character or not humanoid then
		return false
	end
	local seat = humanoid.SeatPart
	if seat then
		humanoid.Sit = false
		local seatWeld = seat:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
		task.wait()
	end
	pcall(function()
		player:RequestStreamAroundAsync(at.Position, 5)
	end)
	if player.Character ~= character or not character.Parent then
		return false
	end
	character:PivotTo(at)
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	return true
end

-- ── SANDBOX (8.0: the panel's SANDBOX tab; shared/SandboxAdmin.luau's buttons) ───────────────────────────────

local Sandbox = {}
Sandbox.Rules = require(Shared.SandboxAdmin)
Sandbox.Map = require(Shared.SandboxMap)
Sandbox.run = {} :: { [string]: (Player, Player) -> () }

type Spot = { x: number, y: number, z: number, yaw: number }

-- A SandboxMap spot as a CFrame, `up` studs over it (SandboxMap.cframe's: yaw about Y, 0 looks north, -z).
function Sandbox.frame(spot: Spot, up: number?): CFrame
	return CFrame.new(spot.x, spot.y + (up or 0), spot.z) * CFrame.Angles(0, math.rad(spot.yaw), 0)
end

-- The player's plot (server/SandboxPlots.luau), nil without one.
function Sandbox.plot(player: Player): any
	local ok, plot = pcall(function()
		return require(Server.SandboxPlots).of(player)
	end)
	return if ok then plot else nil
end

-- Collection[name](...) in a pcall (server/Collection.luau, the collection worker's): ok, then its answers.
function Sandbox.collection(name: string, ...: any): (boolean, any, any)
	return pcall(function(...: any)
		return (require(Server.Collection) :: any)[name](...)
	end, ...)
end

function Sandbox.hasCollection(name: string): boolean
	local ok, found = pcall(function()
		return type((require(Server.Collection) :: any)[name]) == "function"
	end)
	return ok and found == true
end

-- Moving.admin(player, arg) (the MOVES buttons' own: server/Moving.luau) in a pcall: what to say.
function Sandbox.moving(player: Player, arg: string): string
	local ok, text = pcall(function()
		return require(Server.Moving).admin(player, arg)
	end)
	if ok and type(text) == "string" then
		return text
	end
	warn(`[Admin] sandbox: Moving.admin {arg} failed: {text}`)
	return `ADMIN: the move's {arg} failed (see the server Output).`
end

-- A character `up` studs over a spot and `out` studs ahead along its look; `back`: turned to face the way it came.
function Sandbox.walkTo(player: Player, spot: Spot, up: number, out: number, back: boolean): boolean
	local at = Sandbox.frame(spot, up) * CFrame.new(0, 0, -out)
	if back then
		at *= CFrame.Angles(0, math.pi, 0)
	end
	return moveCharacter(player, at)
end

Sandbox.NoPlot = "ADMIN: no plot (server/SandboxPlots.luau gives one to each of the first Config.Sandbox.MaxPlayers players)."

-- Money ----------------------------------------------------------------------------------------------------------------

Sandbox.run.money = function(player: Player)
	if not PlayerData.get(player) then
		say(player, "Still loading...")
		return
	end
	PlayerData.addMoney(player, Sandbox.Rules.Money, "Admin")
	say(player, `ADMIN: +{moneyText(Sandbox.Rules.Money)}.`)
end

Sandbox.run.broke = function(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	profile.money = 0
	PlayerData.notify(player)
	say(player, "ADMIN: your money is $0.")
end

-- Runs (9.7: server/Runs.luau's admin; the moves' clock and horde: Moving's admin) ------------------------------------

-- ("run_<house>"): a run on that house for the TARGET alone, at the difficulty the admin picked ("rundiff_<id>"; locks
-- ignored); "runend": the TARGET's run ends (what is in the truck goes home).
function Sandbox.runs(player: Player, admin: Player, what: string, arg: string?)
	local ok, said = pcall(function(): any
		return require(Server.Runs).admin(player, what, arg, admin)
	end)
	say(admin, if ok and type(said) == "string" then said else `ADMIN: the runs are not ready ({said}).`)
end

function Sandbox.registerRuns()
	for _, action in Sandbox.Rules.Actions do
		local house = Sandbox.Rules.runHouse(action.id)
		local difficulty = Sandbox.Rules.runDifficulty(action.id)
		if house then
			Sandbox.run[action.id] = function(player: Player, admin: Player)
				Sandbox.runs(player, admin, "start", house)
			end
		elseif difficulty then
			Sandbox.run[action.id] = function(player: Player, admin: Player)
				Sandbox.runs(player, admin, "difficulty", difficulty)
			end
		end
	end
	Sandbox.run.runend = function(player: Player, admin: Player)
		Sandbox.runs(player, admin, "end", nil)
	end
end
Sandbox.registerRuns()

Sandbox.run.clock = function(player: Player)
	say(player, Sandbox.moving(player, "time"))
end

Sandbox.run.horde = function(player: Player)
	say(player, Sandbox.moving(player, "horde"))
end

-- Collection (server/Collection.luau) ---------------------------------------------------------------------------------

-- 10 random pieces of the furniture catalogue (shared/FurnitureLooks.luau's ids) in random condition.
Sandbox.run.fill = function(player: Player)
	if not PlayerData.get(player) then
		say(player, "Still loading...")
		return
	end
	local fill = Sandbox.Rules.Fill
	local picks = Sandbox.Rules.picks(require(Shared.FurnitureLooks).Order, fill.Count, function(a: number, b: number): number
		return rng:NextInteger(a, b)
	end, function(): number
		return rng:NextNumber()
	end)
	local added, why = 0, nil
	for _, pick in picks do
		local ok, uid = Sandbox.collection("add", player, { item = pick.item, variant = pick.variant, condition = pick.condition })
		if ok and type(uid) == "string" then
			added += 1
		elseif not ok then
			why = uid
		end
	end
	if why then
		warn(`[Admin] sandbox fill: Collection.add failed: {why}`)
	end
	say(player, if added > 0 then `ADMIN: {added} random pieces in your stock.` else "ADMIN: the stock took nothing (Collection.add refused: no save yet, or the collection is not in this build).")
end

-- Every piece gone, $0 for them: Collection.clear (an admin helper the collection may have), else each one sold and
-- the money and the earnings put back as they were.
Sandbox.run.clear = function(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	if Sandbox.hasCollection("clear") then
		local ok, count = Sandbox.collection("clear", player)
		say(player, if ok then `ADMIN: your stock is empty{if type(count) == "number" then ` ({count} pieces gone)` else ""}.` else "ADMIN: Collection.clear failed (see the server Output).")
		if not ok then
			warn(`[Admin] sandbox clear: Collection.clear failed: {count}`)
		end
		return
	end
	local ok, stock = Sandbox.collection("stock", player)
	if not ok or type(stock) ~= "table" then
		say(player, "ADMIN: the stock can't be read (Collection.stock).")
		return
	end
	local money, earned = profile.money, profile.earned
	local sold = 0
	for _, entry in stock do
		if type(entry) == "table" and type(entry.uid) == "string" then
			local done, paid = Sandbox.collection("sell", player, entry.uid)
			if done and paid ~= nil then
				sold += 1
			end
		end
	end
	profile.money, profile.earned = money, earned -- (the sales paid nothing: $0 for them)
	PlayerData.notify(player)
	say(player, if sold > 0 then `ADMIN: {sold} pieces gone from your stock ($0 for them).` elseif #stock == 0 then "ADMIN: your stock is empty already." else "ADMIN: the stock kept its pieces (Collection.sell refused them).")
end

-- The stock's pieces not on show onto the free display stands (8.1: the player's own count, Collection.stands: 8.3,
-- their warehouse level's; a build without it: Config.Warehouse.Stands of them).
Sandbox.run.stands = function(player: Player)
	local stands = Sandbox.Rules.standCount((Config :: any).Warehouse)
	if Sandbox.hasCollection("stands") then
		local ok, own = Sandbox.collection("stands", player)
		stands = if ok and type(own) == "number" then own else stands
	end
	if stands <= 0 then
		say(player, "ADMIN: no display stands in this build yet (Config.Warehouse.Stands).")
		return
	end
	local ok, stock = Sandbox.collection("stock", player)
	if not ok or type(stock) ~= "table" then
		say(player, "ADMIN: the stock can't be read (Collection.stock).")
		return
	end
	local plan = Sandbox.Rules.standPlan(stock, stands)
	local shown, why = 0, nil
	for _, step in plan do
		local done, put, reason = Sandbox.collection("display", player, step.uid, step.stand)
		if done and put == true then
			shown += 1
		else
			why = if done then reason else put
		end
	end
	say(player, if shown > 0 then `ADMIN: {shown} pieces put on show.` elseif #plan == 0 then "ADMIN: nothing to put on show (no piece in the stock, or no free stand)." else `ADMIN: the stands took nothing ({why or "Collection.display refused"}).`)
end

-- 8.1, the upgrades (server/Upgrades.luau's admin: every one at its top for free, or none) ----------------------------

function Sandbox.upgrades(player: Player, what: string)
	local ok, text = pcall(function()
		return (require(Server.Upgrades) :: any).admin(player, what)
	end)
	if ok and type(text) == "string" then
		say(player, text)
		return
	end
	warn(`[Admin] sandbox: Upgrades.admin {what} failed: {text}`)
	say(player, `ADMIN: the upgrades' {what} failed (see the server Output).`)
end

Sandbox.run.upmax = function(player: Player)
	Sandbox.upgrades(player, "max")
end

Sandbox.run.upreset = function(player: Player)
	Sandbox.upgrades(player, "reset")
end

-- 8.3: 🏗 LV 1 … 5, the warehouse's level (Upgrades.admin "level1" … "level5")
for level = 1, 5 do
	Sandbox.run[`level{level}`] = function(player: Player)
		Sandbox.upgrades(player, `level{level}`)
	end
end

-- 8.2, the collection book (server/CollectionBook.luau's admin: every piece found, or the book empty) ----------------

function Sandbox.book(player: Player, what: string)
	local ok, text = pcall(function()
		return (require(Server.CollectionBook) :: any).admin(player, what)
	end)
	if ok and type(text) == "string" then
		say(player, text)
		return
	end
	warn(`[Admin] sandbox: CollectionBook.admin {what} failed: {text}`)
	say(player, `ADMIN: the collection book's {what} failed (see the server Output).`)
end

Sandbox.run.bookfill = function(player: Player)
	Sandbox.book(player, "fill")
end

Sandbox.run.bookclear = function(player: Player)
	Sandbox.book(player, "clear")
end

-- 8.3, the PAINT shop (server/VanPaint.luau's admin: every paint and livery owned, or none) ---------------------------

function Sandbox.paints(player: Player, what: string)
	local ok, text = pcall(function()
		return (require(Server.VanPaint) :: any).admin(player, what)
	end)
	if ok and type(text) == "string" then
		say(player, text)
		return
	end
	warn(`[Admin] sandbox: VanPaint.admin {what} failed: {text}`)
	say(player, `ADMIN: the paints' {what} failed (see the server Output).`)
end

Sandbox.run.paintall = function(player: Player)
	Sandbox.paints(player, "all")
end

Sandbox.run.paintreset = function(player: Player)
	Sandbox.paints(player, "reset")
end

-- Travel and the van (shared/SandboxMap.luau's spots) -----------------------------------------------------------------

-- 9.7: the lobby's plaza (no van in the lobby: BRING VAN is gone).
Sandbox.run.lobby = function(player: Player)
	say(player, if Sandbox.walkTo(player, Sandbox.Map.Lobby.spawn, 0.5, 0, false) then "ADMIN: the lobby's plaza." else "ADMIN: you have no body right now.")
end

-- To the house's front door (facing it: Enter house): your run's house, else your card's (Moving.houseOf; none yet:
-- the farmstead).
Sandbox.run.house = function(player: Player)
	local ok, found = pcall(function(): any
		return require(Server.Moving).houseOf(player)
	end)
	local house = (if ok and type(found) == "table" then Sandbox.Map.house(found.id) else nil) or Sandbox.Map.House
	say(player, if Sandbox.walkTo(player, house.door, 3, 4, true) then `ADMIN: at {house.name}'s front door.` else "ADMIN: you have no body right now.")
end

-- To your plot's spawn.
Sandbox.run.warehouse = function(player: Player)
	local plot = Sandbox.plot(player)
	if not plot then
		say(player, Sandbox.NoPlot)
		return
	end
	say(player, if Sandbox.walkTo(player, plot.spawn, 0.5, 0, false) then "ADMIN: your warehouse." else "ADMIN: you have no body right now.")
end

-- ("sandbox", id) [T]: the admin's clicks at most Config.Robust.Limits.AdminSandbox a second (Net.limit: the rest
-- dropped), then SandboxAdmin.check (an admin, a button's id; refused: the admin is told why).
function Sandbox.command(player: Player, arg: any, admin: Player)
	local isAdmin = Admin.isAdmin(admin)
	if isAdmin and not Net.limit(admin, "AdminSandbox", Config.Robust.Limits.AdminSandbox) then
		return
	end
	local action, why = Sandbox.Rules.check(isAdmin, true, arg) -- (10.6: the sandbox is the game)
	if not action then
		if isAdmin then
			notice:FireClient(admin, `ADMIN: {why}`)
		end
		return
	end
	local run = Sandbox.run[action.id]
	if run then
		run(player, admin)
	end
end

-- ── The remote ─────────────────────────────────────────────────────────────

local COMMANDS: { [string]: (Player, any, Player) -> () } = {
	sandbox = Sandbox.command, -- 8.0 SANDBOX
}
for command in FLAGS do
	COMMANDS[command] = function(player: Player, arg: any)
		setFlag(player, command, arg)
	end
end

-- 4.5: the commands that take a target (another player in the server); every one here does.
local TARGETED: { [string]: boolean } = { sandbox = true }
for command in FLAGS do
	TARGETED[command] = true
end

local function onCommand(player: Player, name: any, arg: any, targetId: any)
	if not Admin.isAdmin(player) then
		return
	end
	local command = if type(name) == "string" then COMMANDS[name] else nil
	if not command then
		say(player, "ADMIN: unknown command.")
		return
	end
	-- A double click does not run it twice.
	local now = os.clock()
	if lastCommand[player] and now - lastCommand[player] < 0.15 then
		return
	end
	lastCommand[player] = now
	-- 4.5: the target (a player in this server), else you.
	local target = player
	local id = finite(targetId)
	if targetId ~= nil and TARGETED[name] and id ~= player.UserId then
		local found = if id and id >= 1 and id <= 2 ^ 53 then Players:GetPlayerByUserId(math.floor(id)) else nil
		if not found or found.Parent ~= Players then
			say(player, "ADMIN: that player is not in this server any more.")
			return
		end
		target = found
	end
	if target ~= player then
		acting[target] = player
	end
	local ok, err = pcall(function()
		command(target, arg, player)
	end)
	if acting[target] == player then
		acting[target] = nil
	end
	if not ok then
		warn(`[Admin] {name} failed: {err}`)
		say(player, `ADMIN: {name} failed (see the server Output).`)
	end
end

local function onPlayer(player: Player)
	if Admin.isAdmin(player) then
		player:SetAttribute("Admin", true)
		print(`[Admin] {player.Name} is an admin: press P for the admin panel`)
	end
end

function Admin.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastCommand[player] = nil
		acting[player] = nil
		for target, admin in acting do
			if admin == player then
				acting[target] = nil
			end
		end
	end)
	Net.get("Admin").OnServerEvent:Connect(onCommand)
	-- 6.13: the panel's Analytics line: on or off and this server's counts (server/Analytics.luau)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("Admin") == true then
					pcall(function()
						player:SetAttribute("AdminAnalytics", require(Server.Analytics).summary())
					end)
				end
			end
		end
	end)
end

return Admin
