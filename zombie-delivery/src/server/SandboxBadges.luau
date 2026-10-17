--!strict
-- 8.3 SANDBOX: Roblox badges for the sandbox's milestones (Config.SandboxBadges; the rules shared/SandboxBadgeRules.luau,
-- the owner's guide design/sandbox/BADGES.md). server/SandboxBoot.luau starts it after the collection, the upgrades and
-- the leaders, before the moves; the city never does. It only listens: it changes nothing in the game but the moves'
-- counter in the save (profile.sandboxMoves: server/PlayerData.luau keeps it with its flag), and it never breaks its
-- caller (every listener and every BadgeService call guarded).
--
-- Which moment awards what (SandboxBadgeRules' fromX):
--   Moving.onResult        a move done or late with a piece home, for everybody in its crew: the counter +1, then
--                          firstMove, tenMoves (Config.SandboxBadges.Moves) and cleanMove (nothing of it broken)
--   Collection.onPaid      a "sale": firstSale; a hot piece in it (8.3's market, paid.hot): hotSale
--   Collection.onAdded     a legendary piece came home: legendary
--   Upgrades.onBought      8.3: a level bought at the UPGRADES desk: firstUpgrade (the warehouse's levels too: a save
--                          from before 8.3 has the Big Warehouse for free, so its state says nothing of them)
--   the player's state     (SandboxBadgeRules.stateOf, at the frame's end after Collection.onChanged / onAdded,
--                          Upgrades.onChanged and PlayerData.Changed, and when the save has loaded: a milestone reached
--                          before its badge was set up is awarded on the next join) firstMove / tenMoves (the counter),
--                          firstShow (a piece of theirs on one of their stands), legendary and fullBook (the collection
--                          book), firstUpgrade (anything bought at the UPGRADES desk but the warehouse's free levels:
--                          SandboxBadgeRules.upgraded), warehouse5 (the warehouse at
--                          Config.SandboxBadges.Level), painted (anything bought at the PAINT shop)
--   the TOP MOVERS board   at most every TopEvery s after a collection changed or somebody's save loaded: with at least
--                          TopPlayers players ranked (server/SandboxLeaders.luau rows), the one alone at the top
--                          (worth more than $0): topMover
-- The award (SandboxBadges.give), on the server only: nothing for a badge whose id is 0 (not set up: no call at all), and
-- nothing in Studio unless Config.SandboxBadges.Studio. Once a session a badge: BadgeService:UserHasBadgeAsync first (in
-- a pcall; owned: done), then AwardBadgeAsync (Roblox's AwardBadge, renamed; in a pcall, an error tried again Wait s
-- later, Tries times in all; Roblox saying no is never asked again this session). An error only warns (once a badge).
-- The admin panel's SANDBOX tab shows the player attribute AdminBadges this module keeps on the admins
-- (SandboxBadgeRules.summary: what is set up, whether this server awards, how many it awarded).
--
--   SandboxBadges.start()          the listeners (once)
--   SandboxBadges.give(player, key)   badge `key` for the player now (the rules above; returns at once, the calls run in
--                                  their own thread)
--   SandboxBadges.session(player)  a copy of this session's badges: key → "busy" | "owned" | "awarded" | "refused" |
--                                  "failed" (the tests', the admin's)
--   SandboxBadges.awarded()        how many badges this server awarded
--   SandboxBadges.service          BadgeService (a test sets its fake)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.SandboxBadgeRules)
local PlayerData = require(script.Parent.PlayerData)

local SandboxBadges = {}

SandboxBadges.service = game:GetService("BadgeService") :: any

type Session = { [string]: string } -- key → "busy" | "owned" | "awarded" | "refused" | "failed"

local sessions: { [Player]: Session } = {} -- this session's badges, by player (gone when they leave)
local joined: { [Player]: boolean } = {} -- the save has loaded
local looking: { [Player]: boolean } = {} -- a look at the state waits for the frame's end
local warned: { [string]: boolean } = {}
local live: { awarded: number, topPending: boolean, topAt: number } = { awarded = 0, topPending = false, topAt = -math.huge }
local collection: any = nil -- server/Collection.luau (nil: not in this build)
local started = false

local function tune(): any
	return Config.SandboxBadges
end

local function warnOnce(what: string, err: any)
	if not warned[what] then
		warned[what] = true
		warn(`[SandboxBadges] {what}: {err}`)
	end
end

local function awarding(): boolean
	return Rules.live(RunService:IsStudio())
end

-- ── The admin panel's line ─────────────────────────────────────────────────

local function tellAdmins()
	local text = Rules.summary(awarding(), live.awarded)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Admin") == true then
			player:SetAttribute("AdminBadges", text)
		end
	end
end

-- ── The award ──────────────────────────────────────────────────────────────

-- Asks Roblox (in this thread: the calls yield): owned already, else awarded. → how it ended.
local function award(player: Player, key: string, id: number): string
	local service: any = SandboxBadges.service
	local userId = player.UserId
	local checked, has = pcall(function(): any
		return service:UserHasBadgeAsync(userId, id)
	end)
	if checked and has == true then
		return "owned"
	elseif not checked then
		warnOnce(`{key}: UserHasBadgeAsync failed`, has) -- (then the award is tried anyway)
	end
	local tries = math.max(1, math.floor(tonumber(tune().Tries) or 1))
	for try = 1, tries do
		if not player.Parent then
			return "failed"
		end
		local done, given = pcall(function(): any
			return service:AwardBadgeAsync(userId, id)
		end)
		if done then
			if given == true then
				live.awarded += 1
				return "awarded"
			end
			-- (Roblox said no: a badge not enabled, another experience's; not asked again this session)
			warnOnce(`{key}: Roblox did not award it`, `badge {id} (is it enabled, and this experience's?)`)
			return "refused"
		end
		warnOnce(`{key}: AwardBadgeAsync failed`, given)
		if try < tries then
			task.wait(math.max(0, tonumber(tune().Wait) or 1))
		end
	end
	return "failed"
end

function SandboxBadges.give(player: Player, key: string)
	local id = Rules.idOf(key)
	if not id or not awarding() or not player.Parent then
		return
	end
	local mine = sessions[player]
	if not mine then
		mine = {}
		sessions[player] = mine
	end
	assert(mine)
	if mine[key] ~= nil then
		return -- (on its way, or settled this session: owned, awarded, refused, given up)
	end
	mine[key] = "busy"
	task.spawn(function()
		local ok, outcome = pcall(award, player, key, id)
		if not ok then
			warnOnce(`{key}: the award failed`, outcome)
		end
		mine[key] = if ok then outcome else "failed"
		tellAdmins()
	end)
end

function SandboxBadges.session(player: Player): { [string]: string }
	local mine = sessions[player]
	return if mine then table.clone(mine) else {}
end

function SandboxBadges.awarded(): number
	return live.awarded
end

-- ── The player's state ─────────────────────────────────────────────────────

-- Any state badge set up and not settled this session? (none: no look at all)
local function open(player: Player): boolean
	if not awarding() then
		return false
	end
	local mine = sessions[player]
	for _, key in Rules.States do
		if Rules.idOf(key) and not (mine and mine[key]) then
			return true
		end
	end
	return false
end

-- A piece of theirs on one of their own stands (no warehouse of their own: nothing on show).
local function shownOf(player: Player): boolean
	local api = collection
	if not api then
		return false
	end
	local housed = api.hasWarehouse
	if housed and not housed(player) then
		return false
	end
	local stands = api.stands(player)
	for _, entry in api.stock(player) do
		if entry.stand ~= nil and entry.stand <= stands then
			return true
		end
	end
	return false
end

local function lookNow(player: Player)
	looking[player] = nil
	local profile = PlayerData.get(player)
	if not profile or not player.Parent or not open(player) then
		return
	end
	for _, key in Rules.fromState(Rules.stateOf(profile, shownOf(player))) do
		SandboxBadges.give(player, key)
	end
end

-- The player's state looked at once at the frame's end, however many changes came in it.
local function look(player: Player)
	if looking[player] or not open(player) then
		return
	end
	looking[player] = true
	task.defer(function()
		local ok, err = pcall(function()
			lookNow(player)
		end)
		if not ok then
			looking[player] = nil
			warnOnce("the state's look failed", err)
		end
	end)
end

-- ── The TOP MOVERS board ───────────────────────────────────────────────────

local function topNow()
	live.topPending = false
	live.topAt = os.clock()
	local Leaders = require(script.Parent.SandboxLeaders) :: any
	local userId = Rules.topOf(Leaders.rows(), tune().TopPlayers)
	local leader = if userId then Players:GetPlayerByUserId(userId) else nil
	if leader then
		SandboxBadges.give(leader, "topMover")
	end
end

-- A look at the board soon (at most every TopEvery s; only with the badge set up and enough players here).
local function topSoon()
	if live.topPending or not Rules.idOf("topMover") or not awarding() or #Players:GetPlayers() < (tonumber(tune().TopPlayers) or 1) then
		return
	end
	live.topPending = true
	task.delay(math.max(0, live.topAt + (tonumber(tune().TopEvery) or 5) - os.clock()), function()
		local ok, err = pcall(function()
			topNow()
		end)
		if not ok then
			live.topPending = false
			warnOnce("the TOP MOVERS look failed", err)
		end
	end)
end

-- ── The listeners ──────────────────────────────────────────────────────────

-- A move's end (Moving.onResult): done or late with a piece home is a finished move for everybody in its crew.
local function onResult(owner: Player?, move: any, result: any, crew: any)
	local finished, clean = Rules.finished(move, result)
	if not finished then
		return
	end
	local everybody: { Player } = {}
	if owner then
		table.insert(everybody, owner)
	end
	if type(crew) == "table" then
		for _, member in crew do
			if not table.find(everybody, member) then
				table.insert(everybody, member)
			end
		end
	end
	for _, member in everybody do
		local profile = PlayerData.get(member)
		local moves = 0
		if profile then
			profile.sandboxMoves = Rules.count(profile.sandboxMoves)
			moves = profile.sandboxMoves
		end
		for _, key in Rules.fromMove(true, clean, moves) do
			SandboxBadges.give(member, key)
		end
	end
end

local function hookMoving()
	local Moving = require(script.Parent.Moving) :: any
	Moving.onResult(onResult)
end

local function hookCollection()
	local api = require(script.Parent.Collection) :: any
	collection = api
	api.onChanged(function(player: Player)
		look(player)
		topSoon()
	end)
	api.onAdded(function(player: Player, entry: any)
		for _, key in Rules.fromAdded(if type(entry) == "table" then entry.item else nil, if type(entry) == "table" then entry.rarity else nil) do -- (9.x loot: its rarity)
			SandboxBadges.give(player, key)
		end
		look(player)
	end)
	api.onPaid(function(player: Player, kind: string, money: number, paid: any)
		for _, key in Rules.fromSale(kind, money, if type(paid) == "table" then paid.hot else 0) do
			SandboxBadges.give(player, key)
		end
	end)
end

local function hookUpgrades()
	local Upgrades = require(script.Parent.Upgrades) :: any
	Upgrades.onChanged(look)
	if type(Upgrades.onBought) == "function" then
		Upgrades.onBought(function(player: Player, id: string, level: number)
			for _, key in Rules.fromBought(id, level) do
				SandboxBadges.give(player, key)
			end
		end)
	end
end

-- PlayerData.Changed: the save loaded (the admins' line, the board), the money moved (a PAINT shop purchase), …
local function onChanged(player: Player)
	if not joined[player] then
		if not player.Parent or not PlayerData.get(player) then
			return
		end
		joined[player] = true
		tellAdmins()
		topSoon()
	end
	look(player)
end

-- Each part on its own: one that fails (a module missing) leaves the others.
local function part(name: string, fn: () -> ())
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		warn(`[SandboxBadges] {name}: {err}`)
	end
end

function SandboxBadges.start()
	if started then
		return
	end
	started = true
	part("collection", hookCollection)
	part("upgrades", hookUpgrades)
	part("moves", hookMoving)
	PlayerData.Changed:Connect(onChanged)
	for _, player in Players:GetPlayers() do
		task.defer(onChanged, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player], joined[player], looking[player] = nil, nil, nil
	end)
	local ready = #Rules.ready()
	if ready > 0 and not awarding() then
		print(`[SandboxBadges] Studio: {ready} badges set up, none awarded here (Config.SandboxBadges.Studio is off)`)
	end
end

return SandboxBadges
