--!strict
-- 9.7 RUNS (the owner: "like Dungeon Quest: from the lobby you go into a house, alone, with friends or with Danny. In
-- the house you carry loot into the truck standing right at the house. When you leave, the loot is taken to your
-- warehouse in the lobby on its own"; Config.Runs, the rules shared/RunRules.luau, the client client/RunUi.luau). 10.4:
-- the lobby's PLAY circle and its party lobbies start the runs (server/Parties.luau, shared/PartyRules.luau: Runs.start
-- starts them; the six portals and their pads are gone); a run is a sandbox move of one house (server/Moving.luau:
-- Moving.startRun, its hooks in the block "9.7 RUNS").
--   * The start (Runs.begin: a party lobby's countdown over, server/Parties.luau; the admin's): the host's van is parked
--     at the house's curb (Moving.parkVan: server/SandboxBoot.luau's, repaired), not drivable (its model's
--     Config.Runs.Truck.Attribute: client/CarVisuals.luau shows no Drive / Ride along, its seats Disabled), the party
--     is the run's (Crew.members and Crew.ownerOf are wrapped: a run's party is its host's crew, nobody else's crew
--     counts in the sandbox), Moving.startRun starts the move (its contract's difficulty, the house's clock × the
--     difficulty's time; the inside's RunDifficulty attribute is Moving's), the map's house model gets the attribute
--     RunDifficulty too (traps, zombies and the loot's rarity read it), the truck gets its prompts (the host's "Finish
--     the run", the others' "Vote to finish") and everybody fades over to the house's front yard (SandboxMap.Zones'
--     arrive, Apart studs across), its door before them, from wherever they waited in the lobby. The host's helper is
--     the move's (server/MoveHelper.luau: he waits by the truck at the house and goes with the run; 10.1 free, the
--     host's pick of their crew: server/HelperCrew.luau, which also traps a helper in some runs' houses to rescue).
--   * One run in a house at a time (Runs.inUse: the PLAY panel shows the house busy, a lobby cannot start there).
--   * In the run: FINISH (the host: the truck's prompt, the move's panel) ends it; so does everybody else's vote
--     (RunRules.voteDone over the party but the host); the clock ends it too (Moving's tick). LEAVE THE RUN (the Runs
--     remote's "leave": the move's list) takes one player back alone (their loaded pieces still count at the end); the
--     host leaving it ends it for everybody (what is in the truck goes home).
--   * The end (Moving.onRunEnd): what was in the truck went into the stock of whoever loaded it (Moving's SB.unloadAll);
--     each player gets the results card ({ kind = "result", … }: the pieces, their rarity, who got them, the value,
--     yours), a run done or late opens the next difficulty for those still in it (RunRules.unlock: the save's
--     runUnlocked, saved soon; { kind = "unlocked" }); EndHold s later everybody fades back to the lobby beside the
--     PLAY circle (Lobby.play.back: just south of it, facing it, Apart studs across: never in it), the van goes, the
--     house's RunDifficulty is cleared.
--
--   Runs.start()                       the remote, the wraps, the dispatch's and the truck's prompts; 10.4 the party
--                                      lobbies (server/Parties.luau's start)
--   Runs.begin(house, party, difficulty, admin?)   a run now (a lobby's start, the admin's): an error text or nil
--   Runs.finish(player)                the host's FINISH (true when a run ended)
--   Runs.vote(player) / Runs.leave(player)   a party member's vote to finish / leaving the run alone
--   Runs.runOf(player)                 the run a player is in (host or party) or nil: { host, house, difficulty, party }
--   Runs.inUse(house)                  a run in that house now?
--   Runs.list()                        10.4: the runs now ({ house, difficulty, host, party }: the map's IN A RUN)
--   Runs.free(player) -> root?         10.4: their body's root while they are free to stand in the PLAY circle and go
--                                      (alive, on foot, in no run or move, not on a jump), else nil
--   Runs.openOf(player) -> n           10.4: the difficulties open to them (their save's runUnlocked)
--   Runs.admin(player, what, arg?, admin?)   the admin panel's SANDBOX tab (`player` its TARGET): "start" (a house: a run
--                                      for `player` alone, at the difficulty `admin` picked, locks ignored) | "difficulty"
--                                      (its id) | "end" (`player`'s run) → what to say
-- 10.x danger (server/RunDanger.luau: the locks and keys, the vault, the hazards, the zombies, the bat): started with the
-- runs (Runs.start); the results card's `danger` ({ vault = true / false / nil: none, stopped = zombies killed }) is
-- RunDanger.result's (the blocks marked "10.x danger").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RunRules = require(Shared.RunRules)
local SandboxMap = require(Shared.SandboxMap)

local Server = script.Parent
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)

local Runs = {}

local R = Config.Runs
local L = SandboxMap.Lobby
type Run = {
	host: Player,
	house: string,
	name: string,
	difficulty: string,
	party: { Player }, -- (in it now, the host first)
	gone: { Player }, -- (left it alone: their results card too)
	votes: { [number]: boolean },
	prompts: { Instance },
	ended: boolean,
}
local remote: RemoteEvent? = nil
local runs: { [string]: Run } = {} -- by house
local runOf: { [Player]: Run } = {} -- every party member's
local away: { [Player]: number } = {} -- on a jump (os.clock until): not free (10.4: the PLAY circle ignores them)
local adminPick: { [Player]: string } = {}
local started = false

local function send(player: Player, message: { [string]: any })
	local r = remote
	if r and player.Parent then
		r:FireClient(player, message)
	end
end

local function say(player: Player, text: string)
	if player.Parent then
		Net.get("Notice"):FireClient(player, text)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function openOf(player: Player): number
	local profile = PlayerData.get(player)
	local count = if profile then (profile :: any).runUnlocked else nil
	return if type(count) == "number" then count else R.Open
end

local function moving(): any
	return require(Server.Moving)
end

-- The map's house model of a place (its attribute SandboxHouse), nil when none.
local function houseModel(house: string): Instance?
	local world = workspace:FindFirstChild("Sandbox")
	if not world then
		return nil
	end
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("SandboxHouse") == house then
			return d
		end
	end
	return nil
end

-- ── The jumps (a fade, the move, the fade in) ──────────────────────────────

-- `player` to `frame` behind a fade (the Moving remote's: client/Fade.luau), the world there streamed in first.
local function jump(player: Player, frame: CFrame)
	away[player] = os.clock() + R.Fade.Out + 3
	local fades = Net.get("Moving")
	if player.Parent then
		fades:FireClient(player, "fade", "out", R.Fade.Out)
	end
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(frame.Position, 3)
		end)
	end)
	task.delay(R.Fade.Out + 0.05, function()
		local character = player.Character
		if character and character.Parent and player.Parent then
			character:PivotTo(frame)
		end
		if player.Parent then
			fades:FireClient(player, "fade", "in", R.Fade.In, { at = frame.Position, look = frame.LookVector, dark = 0.1, wait = 2, near = 8 })
		end
		away[player] = os.clock() + 1.5 -- (a moment where they land before it counts)
	end)
end

-- The spots `count` players stand on round `spot`, Apart studs across the way it looks (the first in the middle).
local function spread(spot: SandboxMap.Spot, count: number): { CFrame }
	local out: { CFrame } = {}
	local base = SandboxMap.cframe(spot)
	for n = 1, count do
		local k = n - 1
		local across = (if k % 2 == 1 then -1 else 1) * math.ceil(k / 2) * R.Apart
		table.insert(out, base * CFrame.new(across, 0, 0))
	end
	return out
end

-- 10.4: back beside the PLAY circle (Lobby.play.back: just south of it, facing it; never in it). `house` the run's.
local function backTo(_house: string, players: { Player })
	for n, frame in spread(L.play.back, #players) do
		jump(players[n], frame)
	end
end

-- ── The views ──────────────────────────────────────────────────────────────

local function runView(run: Run, player: Player): { [string]: any }
	local votes = 0
	for _, member in run.party do
		if run.votes[member.UserId] then
			votes += 1
		end
	end
	return {
		kind = "run",
		house = run.house,
		name = run.name,
		difficulty = run.difficulty,
		host = run.host.UserId,
		hostName = run.host.DisplayName,
		mine = run.host == player,
		members = #run.party,
		votes = votes,
		voted = run.votes[player.UserId] == true,
	}
end

local function sendRun(run: Run)
	for _, member in run.party do
		send(member, runView(run, member))
	end
end

-- ── The truck ──────────────────────────────────────────────────────────────

-- The van at the house's curb, not drivable (the attribute, its seats off).
local function lockVan(car: any)
	car.model:SetAttribute(R.Truck.Attribute, true)
	pcall(function()
		car.seat.Disabled = true
		for _, seat in car.passengers do
			seat.Disabled = true
		end
	end)
end

local function truckPrompts(run: Run, car: any)
	local at = Instance.new("Attachment")
	at.Name = "RunFinish"
	local a = R.Truck.At
	at.Position = Vector3.new(a[1], a[2], a[3])
	at.Parent = car.chassis
	table.insert(run.prompts, at)
	local function prompt(name: string, action: string): ProximityPrompt
		local p = Instance.new("ProximityPrompt")
		p.Name = name
		p.ActionText = action
		p.ObjectText = `{run.name} · {string.upper((RunRules.def(run.difficulty) :: any).name)}`
		p.KeyboardKeyCode = Enum.KeyCode.F
		p.HoldDuration = 0.6
		p.MaxActivationDistance = R.Truck.Reach
		p.RequiresLineOfSight = false
		p:SetAttribute("MoveOwner", run.host.UserId)
		CollectionService:AddTag(p, "MovePrompt")
		p.Parent = at
		return p
	end
	local finish = prompt("RunFinishPrompt", "Finish the run")
	finish:SetAttribute("MoveOnly", run.host.UserId)
	finish.Triggered:Connect(function(player: Player)
		Runs.finish(player)
	end)
	local vote = prompt("RunVotePrompt", "Vote to finish")
	vote:SetAttribute("MoveSkip", run.host.UserId)
	vote.Triggered:Connect(function(player: Player)
		Runs.vote(player)
	end)
end

-- ── A run ──────────────────────────────────────────────────────────────────

local function release(run: Run)
	for _, member in run.party do
		if runOf[member] == run then
			runOf[member] = nil
		end
	end
	if runs[run.house] == run then
		runs[run.house] = nil
	end
	for _, thing in run.prompts do
		thing:Destroy()
	end
	table.clear(run.prompts)
end

function Runs.begin(house: string, party: { Player }, difficulty: string, admin: boolean?): string?
	local H = SandboxMap.house(house)
	local zone = SandboxMap.zone(house)
	local host = party[1]
	if not H or not zone or not host then
		return "No such house."
	end
	if runs[house] then
		return `{H.name} is in use: try another house.`
	end
	for _, p in party do
		if runOf[p] then
			return `{p.DisplayName} is in a run already.`
		end
	end
	local busy = moving().busy(host)
	if busy then
		return busy
	end
	local pick = if admin then RunRules.clean(difficulty) else RunRules.choose(openOf(host), difficulty)
	local park = moving().parkVan
	if not park then
		return "Runs are not ready yet."
	end
	local err, car = park(host, H.curb, false)
	if err or not car then
		return err or "The truck could not come: try again."
	end
	lockVan(car)
	local run: Run = { host = host, house = house, name = H.name, difficulty = pick, party = table.clone(party), gone = {}, votes = {}, prompts = {}, ended = false }
	runs[house] = run
	for _, p in party do
		runOf[p] = run
	end
	local failed = moving().startRun(host, house, pick)
	if failed then
		release(run)
		Vehicles.remove(host)
		return failed
	end
	local model = houseModel(house)
	if model then
		model:SetAttribute("RunDifficulty", pick)
	end
	truckPrompts(run, car)
	for n, frame in spread(zone.arrive, #party) do
		jump(party[n], frame)
	end
	sendRun(run)
	return nil
end

function Runs.finish(player: Player): boolean
	local run = runOf[player]
	if not run or run.ended then
		return false
	end
	if run.host ~= player then
		Runs.vote(player)
		return false
	end
	return moving().endRun(player, `Finished at the truck by {player.DisplayName}: what was in the truck went home`)
end

function Runs.vote(player: Player)
	local run = runOf[player]
	if not run or run.ended then
		return
	end
	if run.host == player then
		Runs.finish(player)
		return
	end
	run.votes[player.UserId] = true
	local others: { number } = {}
	for _, member in run.party do
		if member ~= run.host then
			table.insert(others, member.UserId)
		end
	end
	if RunRules.voteDone(run.votes, others) then
		moving().endRun(run.host, "The party voted to finish: what was in the truck went home")
		return
	end
	local count = 0
	for _, id in others do
		if run.votes[id] then
			count += 1
		end
	end
	for _, member in run.party do
		say(member, `🗳 {player.DisplayName} wants to finish ({count}/{#others} votes; {run.host.DisplayName} can FINISH at the truck).`)
	end
	sendRun(run)
end

function Runs.leave(player: Player)
	local run = runOf[player]
	if not run or run.ended then
		return
	end
	if run.host == player then
		moving().endRun(player, `{player.DisplayName} (the host) left the run: what was in the truck went home`)
		return
	end
	runOf[player] = nil
	local at = table.find(run.party, player)
	if at then
		table.remove(run.party, at)
	end
	run.votes[player.UserId] = nil
	table.insert(run.gone, player)
	send(player, { kind = "run" })
	say(player, "🚪 You leave the run: back to the lobby. What you loaded still goes to your warehouse at its end.")
	for _, member in run.party do
		say(member, `🚪 {player.DisplayName} left the run.`)
	end
	sendRun(run)
	task.delay(R.LeaveHold, function()
		if player.Parent and not runOf[player] then
			backTo(run.house, { player })
		end
	end)
end

-- Moving.onRunEnd: the results card, the unlocks, the jump back, the van gone.
local function onEnd(host: Player, facts: { [string]: any })
	local run = runOf[host]
	if not run or run.host ~= host then
		for _, r in runs do
			if r.host == host then
				run = r
			end
		end
	end
	if not run or run.ended then
		return
	end
	run.ended = true
	local pieces = if type(facts.pieces) == "table" then facts.pieces else {}
	local finished = facts.phase == "done" or facts.phase == "late"
	local names: { [number]: string } = {}
	for _, p in run.party do
		names[p.UserId] = p.DisplayName
	end
	for _, p in run.gone do
		names[p.UserId] = p.DisplayName
	end
	local list: { { [string]: any } } = {}
	for _, piece in pieces do
		local def = nil
		pcall(function()
			local rules = require(Shared.CollectionRules)
			def = rules.defOf(piece.item)
		end)
		local rarity = piece.rarity
		if type(rarity) ~= "string" then
			pcall(function()
				rarity = require(Shared.CollectionRules).rarityOf(def)
			end)
		end
		table.insert(list, { item = piece.item, name = piece.name, icon = piece.icon, value = math.floor((tonumber(piece.value) or 0) + 0.5),
			rarity = if type(rarity) == "string" then rarity else "common", to = piece.to, by = names[piece.to] or host.DisplayName })
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	local everyone = table.clone(run.party)
	for _, p in run.gone do
		if p.Parent and not table.find(everyone, p) then
			table.insert(everyone, p)
		end
	end
	local danger: any = nil -- 10.x danger: the vault opened, the zombies stopped (server/RunDanger.luau)
	pcall(function()
		danger = require(Server.RunDanger).result(host)
	end)
	for _, p in everyone do
		local sum = RunRules.summary(list :: any, p.UserId)
		local opened: string? = nil
		if finished and table.find(run.party, p) then
			local profile = PlayerData.get(p)
			if profile then
				local count, id = RunRules.unlock(openOf(p), run.difficulty)
				;(profile :: any).runUnlocked = count
				opened = id
				if id then
					pcall(PlayerData.saveSoon, p)
				end
			end
		end
		send(p, { kind = "run" })
		send(p, {
			kind = "result",
			house = run.house,
			name = run.name,
			difficulty = run.difficulty,
			phase = facts.phase,
			why = facts.why,
			pieces = list,
			count = sum.count,
			value = sum.value,
			mine = sum.mine,
			mineValue = sum.mineValue,
			total = facts.total,
			me = p.UserId,
			opened = opened,
			openedName = if opened then (RunRules.def(opened) :: any).name else nil,
			danger = danger, -- 10.x danger
		})
		if opened then
			send(p, { kind = "unlocked", id = opened, name = (RunRules.def(opened) :: any).name })
		end
	end
	local model = houseModel(run.house)
	if model then
		model:SetAttribute("RunDifficulty", nil)
	end
	local party = table.clone(run.party)
	release(run)
	task.delay(R.EndHold, function()
		local back: { Player } = {}
		for _, p in party do
			if p.Parent and not runOf[p] then
				table.insert(back, p)
			end
		end
		backTo(run.house, back)
		task.delay(R.Fade.Out + 0.2, function()
			if not runOf[host] then
				pcall(Vehicles.remove, host)
			end
		end)
	end)
end

-- ── Free to go (10.4: server/Parties.luau's PLAY circle and its runs) ───────

function Runs.free(player: Player): BasePart?
	if runOf[player] or (away[player] and os.clock() < away[player]) then
		return nil
	end
	local root = rootOf(player)
	if not root then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		return nil
	end
	if moving().busy(player) then
		return nil
	end
	return root
end

function Runs.openOf(player: Player): number
	return openOf(player)
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onRequest(player: Player, message: any)
	if type(message) ~= "table" or not Net.limit(player, "Runs", Config.Robust.Limits.Runs) then
		return
	end
	local kind = message.kind
	if kind == "state" then
		local run = runOf[player]
		if run then
			send(player, runView(run, player))
		end
	elseif kind == "vote" then
		Runs.vote(player)
	elseif kind == "leave" then
		Runs.leave(player)
	end
end

-- ── Queries, the admin ─────────────────────────────────────────────────────

function Runs.runOf(player: Player): { host: Player, house: string, difficulty: string, party: { Player } }?
	local run = runOf[player]
	return if run then { host = run.host, house = run.house, difficulty = run.difficulty, party = table.clone(run.party) } else nil
end

function Runs.inUse(house: string): boolean
	return runs[house] ~= nil
end

function Runs.list(): { { house: string, difficulty: string, host: Player, party: { Player } } }
	local out = {}
	for house, run in runs do
		if not run.ended then
			table.insert(out, { house = house, difficulty = run.difficulty, host = run.host, party = table.clone(run.party) })
		end
	end
	table.sort(out, function(a, b)
		return a.house < b.house
	end)
	return out
end

function Runs.admin(player: Player, what: string, arg: string?, admin: Player?): string
	local by = admin or player
	if what == "difficulty" then
		local def = RunRules.def(arg)
		if not def then
			return "ADMIN: no such difficulty."
		end
		adminPick[by] = def.id
		return `ADMIN: the next run you start here is {string.upper(def.name)}.`
	elseif what == "start" then
		local house = arg or ""
		local h = SandboxMap.house(house)
		if not h then
			return "ADMIN: no such house."
		end
		local pick = adminPick[by] or R.Default
		local err = Runs.begin(house, { player }, pick, true)
		return if err then `ADMIN: {err}` else `ADMIN: a run at {h.name} ({string.upper((RunRules.def(pick) :: any).name)}) started for you.`
	elseif what == "end" then
		local run = runOf[player]
		if not run then
			return "ADMIN: you are in no run."
		end
		moving().endRun(run.host, "Ended by the admin: what was in the truck went home")
		return "ADMIN: the run ended."
	end
	return "ADMIN: start | difficulty | end."
end

-- ── Starting ───────────────────────────────────────────────────────────────

-- The runs' parties are the moves' crews (the crew panel's crews count for nothing in the sandbox's moves).
local function wrapCrew()
	local Crew = require(Server.Crew) :: any
	Crew.members = function(owner: Player): { Player }
		local run = runOf[owner]
		local out: { Player } = {}
		if run and run.host == owner then
			for _, member in run.party do
				if member ~= owner and member.Parent then
					table.insert(out, member)
				end
			end
		end
		return out
	end
	Crew.ownerOf = function(player: Player): Player?
		local run = runOf[player]
		return if run and run.host ~= player then run.host else nil
	end
end

function Runs.start()
	if started then
		return
	end
	started = true
	remote = Net.get("Runs")
	wrapCrew()
	moving().onRunEnd(onEnd)
	local ok, err = pcall(function() -- 10.x danger: every run's locks, vault, hazards and zombies
		require(Server.RunDanger).start(moving())
	end)
	if not ok then
		warn(`[Runs] the runs' danger did not start: {err}`)
	end
	;(remote :: RemoteEvent).OnServerEvent:Connect(onRequest)
	-- the dispatch kiosk's prompt: how runs work
	local world = workspace:FindFirstChild("Sandbox")
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("RunDispatch") == true then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "DispatchPrompt"
				prompt.ActionText = "How runs work"
				prompt.ObjectText = "DELIVEROS DISPATCH"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Triggered:Connect(function(player: Player)
					say(player, `▶ Step into the glowing PLAY circle: CREATE A LOBBY (a house, a difficulty, public or friends only) or JOIN one ({R.MaxParty} at most). Everybody READY, the host presses START. Carry the loot into the truck at the door, FINISH at the truck (or beat the clock): it all comes home to your warehouse.`)
				end)
				prompt.Parent = d
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local run = runOf[player]
		if run and run.host ~= player then
			runOf[player] = nil
			local at = table.find(run.party, player)
			if at then
				table.remove(run.party, at)
			end
			run.votes[player.UserId] = nil
			sendRun(run)
		end
		away[player], adminPick[player] = nil, nil
	end)
	-- 10.4: the PLAY circle's party lobbies (they start the runs: Runs.begin)
	local started, why = pcall(function()
		require(Server.Parties).start(Runs)
	end)
	if not started then
		warn(`[Runs] the party lobbies did not start: {why}`)
	end
end

return Runs
