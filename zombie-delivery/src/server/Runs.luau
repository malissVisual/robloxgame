--!strict
-- 9.7 RUNS (the owner: "like Dungeon Quest: from the lobby you go into a house, alone, with friends or with Danny. In
-- the house you carry loot into the truck standing right at the house. When you leave, the loot is taken to your
-- warehouse in the lobby on its own"; Config.Runs, the rules shared/RunRules.luau, the client client/RunUi.luau). The
-- lobby's six portals (shared/SandboxMap.luau Lobby.portals, server/LobbyWorld.luau builds them) start the runs; a run
-- is a sandbox move of one house (server/Moving.luau: Moving.startRun, its hooks in the block "9.7 RUNS").
--   * The pads: every Config.Runs.Every s the server looks who stands on each portal's pad (on foot, alive, in no run,
--     not on a jump back). The first one on an empty pad is the host and starts its countdown (Countdown s); whoever
--     steps on joins the line, whoever steps off leaves it (the host's place goes to the next). The host picks the
--     difficulty (the Runs remote's "difficulty": only one open to them, RunRules.isOpen with their save's
--     runUnlocked; a new host keeps it when it is open to them, else the hardest open one under it). The pad's sign
--     says its state (WALK ONTO THE PAD, STARTING IN 7 · 2/4, IN USE) and its glow its colour (Config.Runs.Portal); the
--     players on it get the pad panel ({ kind = "pad", … }). When the countdown ends the first MaxParty on it go.
--   * A portal whose house is in a run already shows IN USE: nobody joins its pad (they hear so once).
--   * 10.x the map (read-only, for client/SandboxMapUi.luau's lobby): each portal model's attributes RunState ("free",
--     "wait": counting down, "use": in a run), RunEndsAt (the countdown's end), RunWho (who is on the pad, else the
--     run's party) and RunDifficulty, written in the same look as its sign, only when they change.
--   * The start: the host's van is parked at the house's curb (Moving.parkVan: server/SandboxBoot.luau's), marked a
--     run's (its model's Config.Runs.Truck.Attribute: client/SandboxMapData.luau finds it by it; 10.6: no van has seats
--     or drives), the party is the run's (Crew.members and Crew.ownerOf are wrapped: a run's party is its host's
--     crew, nobody else's crew counts in the sandbox), Moving.startRun starts the move (its contract's difficulty, the
--     house's clock × the difficulty's time; the inside's RunDifficulty attribute is Moving's), the map's house model
--     gets the attribute RunDifficulty too (traps, zombies and the loot's rarity read it: a later worker's), the truck
--     gets its prompts (the host's "Finish the run", the others' "Vote to finish") and everybody fades over to the
--     house's front yard (SandboxMap.Zones' arrive, Apart studs across), its door before them. The host's helper is
--     the move's (server/MoveHelper.luau: he waits by the truck at the house and goes with the run; 10.1 free, the
--     host's pick of their crew: server/HelperCrew.luau, which also traps a helper in some runs' houses to rescue).
--   * In the run: FINISH (the host: the truck's prompt, the move's panel) ends it; so does everybody else's vote
--     (RunRules.voteDone over the party but the host); the clock ends it too (Moving's tick). LEAVE THE RUN (the Runs
--     remote's "leave": the move's list) takes one player back alone (their loaded pieces still count at the end); the
--     host leaving it ends it for everybody (what is in the truck goes home).
--   * The end (Moving.onRunEnd): what was in the truck went into the stock of whoever loaded it (Moving's SB.unloadAll);
--     each player gets the results card ({ kind = "result", … }: the pieces, their rarity, who got them, the value,
--     yours), a run done or late opens the next difficulty for those still in it (RunRules.unlock: the save's
--     runUnlocked, saved soon; { kind = "unlocked" }); EndHold s later everybody fades back to the lobby by the portal
--     they came from (its `back` spot: just off its pad, facing the plaza: never on it, that would start a run again),
--     the van goes, the house's RunDifficulty is cleared.
--
--   Runs.start()                       the pads' loop, the remote, the wraps, the dispatch's and the truck's prompts
--   Runs.begin(house, party, difficulty, admin?)   a run now (the pad's end, the admin's): an error text or nil
--   Runs.finish(player)                the host's FINISH (true when a run ended)
--   Runs.vote(player) / Runs.leave(player)   a party member's vote to finish / leaving the run alone
--   Runs.runOf(player)                 the run a player is in (host or party) or nil: { host, house, difficulty, party }
--   Runs.padOf(house)                  a portal's pad (RunRules.Pad) or nil
--   Runs.inUse(house)                  a run in that house now?
--   Runs.admin(player, what, arg?, admin?)   the admin panel's SANDBOX tab (`player` its TARGET): "start" (a house: a run
--                                      for `player` alone, at the difficulty `admin` picked, locks ignored) | "difficulty"
--                                      (its id) | "end" (`player`'s run) → what to say
--   Runs.step()                        one look at the pads (the loop's; the tests')
-- 10.4 the ride (the owner: "there is no driving the car any more, so every time you go to a place, an animation of
-- you driving there"): before every jump to a house and back to the lobby, each player gets { kind = "ride", to, back,
-- difficulty?, party?, seconds } (Config.Runs.Ride): client/RideUi.luau shows the van on its way over the fade.
-- 10.x danger (server/RunDanger.luau: the locks and keys, the vault, the hazards, the zombies, the bat): started with the
-- runs (Runs.start); the results card's `danger` ({ vault = true / false / nil: none, stopped = zombies killed }) is
-- RunDanger.result's (the blocks marked "10.x danger"). 10.5: no zombies, no bat (Config.Runs.Danger).
-- 10.5 ROUNDS (Config.Rounds.On; the owner: "16 people on one server … a round starts at one place, everybody runs
-- there, everyone has their own car, what you carry off to it quickly is yours … not teams"; the rules
-- shared/RoundRules.luau, the client client/RoundUi.luau; the block "10.5 ROUNDS" below): the portals' pads do nothing,
-- one round at a time for the whole server instead.
--   * The countdown (Wait s) runs in the lobby while somebody is in the game (the player attribute InGame: PLAY,
--     server/SandboxBoot.luau); the next place is picked as it starts (never the last one again) and its difficulty
--     (Config.Rounds.Difficulties, at random): the portals' signs and the map say where (its portal NEXT ROUND HERE).
--   * The start: everybody in the game and free (alive, on no move, not on a jump) goes. Each player's own van is
--     parked at the house (RoundRules.parking: side by side at its curb and in rows behind it, the spots with
--     something solid in the way last), locked as a run's truck, its back open, its owner's name over it (its model's
--     attribute RoundVan = their UserId) and its Load prompt (E, only they see it: MoveOnly). The run is the host's
--     (the first player's) Moving.startRun with the round's clock (Seconds): its contract's `round` (server/Moving.luau
--     "10.5 ROUNDS": no move truck, no helper, no FINISH). Everybody rides there (10.4) and lands in rows by the door.
--   * In the round: Load at your own van while you carry something (Moving.claim): it is yours at once, into your
--     warehouse's stock; everybody in the round hears it ({ kind = "claim", … }: the feed) and sees the table
--     ({ kind = "round", … }: RoundUi's). LEAVE (the list's: the Runs remote's "leave") takes you back alone (your van
--     goes); the host leaving hands the round's move over (Moving.handOver), it never ends it.
--   * The end: the clock (Moving's tick ends the run): the results card ranks everybody in it (RoundRules.ranking: its
--     `round`), Results s later everybody rides back to the lobby, the vans go, the next countdown starts.
--   Runs.round()                       the round's state now (the tests'): { phase, endsAt, house, difficulty, run?, vans }
--   Runs.roundStep()                   one look at the round (Runs.step's while Config.Rounds.On)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RunRules = require(Shared.RunRules)
local RoundRules = require(Shared.RoundRules) -- 10.5 rounds
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
	round: boolean?, -- 10.5 rounds: the server's round (no host's FINISH, no votes)
}
local remote: RemoteEvent? = nil
local pads: { [string]: RunRules.Pad } = {}
local runs: { [string]: Run } = {} -- by house
local runOf: { [Player]: Run } = {} -- every party member's
local away: { [Player]: number } = {} -- on a jump (os.clock until): no pad, no join
local padKey: { [Player]: string } = {} -- the last pad view sent ("" none)
local signs: { [string]: { status: TextLabel?, pad: BasePart?, model: Instance? } } = {}
local signText: { [string]: string } = {}
local shownState: { [string]: string } = {} -- 10.x the map: the portal's attributes as last written (a key)
local inUseSaid: { [Player]: string } = {}
local adminPick: { [Player]: string } = {}
local started = false
-- 10.5 rounds (the block "10.5 ROUNDS" below: its functions): the server's one round, in one table (the -O0 registers)
--   phase    "idle" (nobody in the game) | "wait" (the countdown) | "play" (the round) | "over" (its results, the ride back)
--   endsAt   the server's time the phase ends (wait: the start; play: the round's clock; over: the next countdown)
--   house, difficulty   the next round's (wait) or this one's (play); last: the round before's house
--   run      this round's run (play); vans / prompts: each player's van at the house and its Load prompt
--   came     everybody who came ({ id, name }, the order they came); pieces: what they loaded ({ to, value })
--   sent     the last round view sent to each player (a key: only what changed goes)
local Round = {
	phase = "idle",
	endsAt = 0,
	house = nil :: string?,
	difficulty = nil :: string?,
	last = nil :: string?,
	run = nil :: Run?,
	vans = {} :: { [Player]: any },
	prompts = {} :: { [Player]: ProximityPrompt },
	came = {} :: { { id: number, name: string } },
	pieces = {} :: { { to: number, value: number } },
	sent = {} :: { [Player]: string },
}

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

local function nameOf(house: string): string
	local h = SandboxMap.house(house)
	return if h then h.name else house
end

-- ── The portals' signs and glow ────────────────────────────────────────────

local function findSigns()
	local world = workspace:FindFirstChild("Sandbox")
	local lobby = world and world:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Portals")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		local house = model:GetAttribute("RunPortal")
		if type(house) == "string" then
			local sign = model:FindFirstChild("GateSign")
			local gui = sign and sign:FindFirstChild("Words")
			local status = gui and gui:FindFirstChild("Status")
			local pad = model:FindFirstChild("RunPad")
			signs[house] = {
				status = if status and status:IsA("TextLabel") then status else nil,
				pad = if pad and pad:IsA("BasePart") then pad else nil,
				model = model,
			}
		end
	end
end

local function paint(house: string, text: string, color: { number })
	local key = `{text}|{color[1]}`
	if signText[house] == key then
		return
	end
	signText[house] = key
	local found = signs[house]
	if not found then
		return
	end
	local c = Color3.fromRGB(color[1], color[2], color[3])
	if found.status then
		found.status.Text = text
		found.status.TextColor3 = c
	end
	if found.pad then
		found.pad.Color = c
	end
end

-- 10.x the map (client/SandboxMapUi.luau, read-only): the portal model's attributes RunState ("free" | "wait": a
-- countdown | "use": a run in its house), RunEndsAt (the countdown's end, the server's time), RunWho (who is on the pad,
-- or the run's party: display names, comma-joined) and RunDifficulty (the pad's pick, the run's): written only when
-- they change.
local function publish(house: string, state: string, endsAt: number?, who: { string }, difficulty: string?)
	local names = table.concat(who, ", ")
	local key = `{state}|{endsAt or ""}|{names}|{difficulty or ""}`
	local found = signs[house]
	local model = found and found.model
	if not model or shownState[house] == key then
		return
	end
	shownState[house] = key
	model:SetAttribute("RunState", state)
	model:SetAttribute("RunEndsAt", endsAt)
	model:SetAttribute("RunWho", if names ~= "" then names else nil)
	model:SetAttribute("RunDifficulty", difficulty)
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
		away[player] = os.clock() + 1.5 -- (a moment on the pad they land on before it counts)
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

-- 10.4: the ride's card (client/RideUi.luau) for `player` on their way to `to` (a house's name; back: the lobby), sent
-- before the jump's fade: the run's difficulty and who else rides along (a run's party; on the way back, nobody).
local function ride(player: Player, to: string, back: boolean, run: Run?)
	local others: { string } = {}
	if run and run.round and not back then -- (10.5 rounds: how many ride along, not their names)
		send(player, { kind = "ride", to = to, back = false, difficulty = run.difficulty, party = {}, round = #run.party, seconds = R.Ride.To })
		return
	elseif run and not back then
		for _, p in run.party do
			if p ~= player then
				table.insert(others, p.DisplayName)
			end
		end
	end
	send(player, {
		kind = "ride",
		to = to,
		back = back,
		difficulty = if run and not back then run.difficulty else nil,
		party = others,
		seconds = if back then R.Ride.Back else R.Ride.To,
	})
end

local function backTo(house: string, players: { Player }, round: boolean?)
	local portal = SandboxMap.portal(house)
	if round then -- (10.5 rounds: the plaza's spawn, in rows: never a portal's pad)
		for n, spot in RoundRules.spread(L.spawn, #players, Config.Rounds.Spread) do
			ride(players[n], R.Ride.Home, true, nil)
			jump(players[n], SandboxMap.cframe(spot))
		end
		return
	end
	local spot = if portal then portal.back else L.spawn
	for n, frame in spread(spot, #players) do
		ride(players[n], R.Ride.Home, true, nil) -- 10.4
		jump(players[n], frame)
	end
end

-- ── The views ──────────────────────────────────────────────────────────────

local function partyNames(list: { number }): { string }
	local out: { string } = {}
	for _, id in list do
		local p = Players:GetPlayerByUserId(id)
		table.insert(out, if p then p.DisplayName else "?")
	end
	return out
end

local function padView(house: string, pad: RunRules.Pad, player: Player): { [string]: any }
	local host = if pad.host then Players:GetPlayerByUserId(pad.host) else nil
	local open: { string } = {}
	local count = if host then openOf(host) else R.Open
	for _, def in RunRules.list() do
		if RunRules.isOpen(count, def.id) then
			table.insert(open, def.id)
		end
	end
	local line = RunRules.party(pad, #pad.order)
	return {
		kind = "pad",
		house = house,
		name = nameOf(house),
		endsAt = pad.endsAt,
		left = RunRules.left(pad, workspace:GetServerTimeNow()),
		host = pad.host,
		hostName = if host then host.DisplayName else "",
		party = partyNames(line),
		going = math.min(#line, R.MaxParty),
		max = R.MaxParty,
		difficulty = pad.difficulty,
		open = open,
		mine = host == player,
		place = table.find(pad.order, player.UserId) or 0,
	}
end

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

-- The van at the house's curb: a run's (the attribute: the lobby's map finds it by it).
local function lockVan(car: Vehicles.Car)
	car.model:SetAttribute(R.Truck.Attribute, true)
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
	local err, car = park(host, H.curb)
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
		local p = party[n]
		padKey[p] = ""
		send(p, { kind = "pad" })
		ride(p, H.name, false, run) -- 10.4: the van on its way there, over the fade
		jump(p, frame)
	end
	sendRun(run)
	return nil
end

function Runs.finish(player: Player): boolean
	local run = runOf[player]
	if not run or run.ended or run.round then -- (10.5 rounds: only the clock ends one)
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
	if not run or run.ended or run.round then
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
	if run.host == player and run.round then -- 10.5 rounds: the round's move goes over to the next player in it
		local heir: Player? = nil
		for _, p in run.party do
			if p ~= player and p.Parent and not heir then
				heir = p
			end
		end
		if not heir or not moving().handOver(player, heir) then
			moving().endRun(player, `{player.DisplayName} left the round: it is over`)
			return
		end
		run.host = heir :: Player
	elseif run.host == player then
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
	say(player, if run.round
		then "🚪 You leave the round: back to the lobby. What you loaded is in your warehouse already."
		else "🚪 You leave the run: back to the lobby. What you loaded still goes to your warehouse at its end.")
	for _, member in run.party do
		say(member, `🚪 {player.DisplayName} left the {if run.round then "round" else "run"}.`)
	end
	sendRun(run)
	task.delay(R.LeaveHold, function()
		if player.Parent and not runOf[player] then
			backTo(run.house, { player }, run.round)
			if run.round then -- (10.5 rounds: their van goes once they are back)
				task.delay(R.Fade.Out + 0.2, function()
					Round.dropVan(player)
				end)
			end
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
	local ranking = if run.round then Round.ranking(list) else nil -- 10.5 rounds: the table
	for _, p in everyone do
		local sum = RunRules.summary(list :: any, p.UserId)
		local opened: string? = nil
		if finished and table.find(run.party, p) and not run.round then
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
			round = if ranking then { ranking = ranking, place = (RoundRules.rankOf(ranking, p.UserId) or { place = 0 }).place, players = #ranking } else nil, -- 10.5
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
	if run.round then
		Round.over(run)
	end
	task.delay(if run.round then Config.Rounds.Results else R.EndHold, function()
		local back: { Player } = {}
		for _, p in party do
			if p.Parent and not runOf[p] then
				table.insert(back, p)
			end
		end
		backTo(run.house, back, run.round)
		task.delay(R.Fade.Out + 0.2, function()
			if run.round then
				for _, p in party do
					if not runOf[p] then
						Round.dropVan(p)
					end
				end
			elseif not runOf[host] then
				pcall(Vehicles.remove, host)
			end
		end)
	end)
end

-- ── 10.5 ROUNDS (Config.Rounds; shared/RoundRules.luau; client/RoundUi.luau) ─────────────────────────────────

local Q = Config.Rounds

-- Pressed PLAY (the attribute InGame: server/SandboxBoot.luau), loaded, alive, on no move and no jump: goes on the round.
function Round.ready(player: Player): boolean
	if player:GetAttribute("InGame") ~= true or runOf[player] or (away[player] and os.clock() < away[player]) then
		return false
	end
	return PlayerData.get(player) ~= nil and rootOf(player) ~= nil and moving().busy(player) == nil
end

-- How many are in the game (pressed PLAY).
function Round.inGame(): number
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InGame") == true then
			n += 1
		end
	end
	return n
end

-- The countdown to the next round: its place (never the last one again) and difficulty.
function Round.plan(now: number)
	local ids: { string } = {}
	for _, h in SandboxMap.Houses do
		if SandboxMap.zone(h.id) then
			table.insert(ids, h.id)
		end
	end
	Round.house = RoundRules.pick(ids, Round.last, math.random())
	Round.difficulty = RoundRules.difficulty(Q.Difficulties, math.random())
	Round.phase, Round.endsAt = "wait", now + Q.Wait
end

-- Is a van's spot clear (nothing solid in the box over it: a tree, a fence, a wall; the players and the cars aside)?
function Round.clear(spot: SandboxMap.Spot): boolean
	local P = Q.Park
	local skip: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		table.insert(skip, cars)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true
	local ok, hits = pcall(function(): { BasePart }
		return workspace:GetPartBoundsInBox(SandboxMap.cframe(spot) * CFrame.new(0, 1 + P.Height / 2, 0), Vector3.new(P.Width, P.Height, P.Length), params)
	end)
	return not ok or #(hits :: { BasePart }) == 0
end

-- The owner's name over their van (client/RoundUi.luau makes yours YOUR VAN).
function Round.label(car: any, player: Player)
	local tag = Instance.new("BillboardGui")
	tag.Name = "RoundVanTag"
	tag.Size = UDim2.fromOffset(180, 34)
	tag.StudsOffset = Vector3.new(0, 8, 0)
	tag.MaxDistance = 160
	tag.AlwaysOnTop = false
	local words = Instance.new("TextLabel")
	words.Name = "Words"
	words.Size = UDim2.fromScale(1, 1)
	words.BackgroundTransparency = 1
	words.TextScaled = true
	words.Font = Enum.Font.GothamBlack
	words.TextColor3 = Color3.fromRGB(255, 255, 255)
	words.TextStrokeTransparency = 0.4
	words.Text = `🚐 {player.DisplayName}`
	words.Parent = tag
	tag.Parent = car.chassis
end

-- The van's Load prompt at its back: only its owner sees it (MoveOnly), on while they carry something (Round.step).
function Round.prompt(player: Player, car: any)
	local door = Vehicles.cargoDoor(car)
	local p = Instance.new("ProximityPrompt")
	p.Name = "RoundLoadPrompt"
	p.ActionText = "Load"
	p.ObjectText = "YOUR VAN"
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = Q.Reach
	p.RequiresLineOfSight = false
	p.Enabled = false
	p:SetAttribute("MoveOnly", player.UserId)
	CollectionService:AddTag(p, "MovePrompt")
	p.Triggered:Connect(function(by: Player)
		if by == player then
			Round.claim(player)
		end
	end)
	p.Parent = door or car.chassis
	Round.prompts[player] = p
end

-- A player's round van goes (back in the lobby, or they left).
function Round.dropVan(player: Player)
	local car = Round.vans[player]
	local prompt = Round.prompts[player]
	Round.vans[player], Round.prompts[player] = nil, nil
	if prompt then
		prompt:Destroy()
	end
	if car and player.Parent and Vehicles.get(player) == car then
		pcall(Vehicles.remove, player)
	end
end

-- Load at your own van: what you carry is yours (Moving.claim), the round hears it.
function Round.claim(player: Player)
	local run = Round.run
	local car = Round.vans[player]
	if not run or runOf[player] ~= run or not car then
		return
	end
	local piece, why = moving().claim(player, car)
	if not piece then
		if why then
			say(player, why)
		end
		return
	end
	local value = math.floor((tonumber(piece.value) or 0) + 0.5)
	table.insert(Round.pieces, { to = player.UserId, value = value })
	for _, p in run.party do
		send(p, { kind = "claim", by = player.DisplayName, mine = p == player, name = piece.name, icon = piece.icon, rarity = piece.rarity, value = value })
	end
	Round.broadcast()
end

function Round.begin(house: string, players: { Player }, difficulty: string): string?
	local H = SandboxMap.house(house)
	local zone = SandboxMap.zone(house)
	local park = moving().parkVan
	if not H or not zone or #players == 0 then
		return "No such house."
	elseif runs[house] then
		return `{H.name} is in use.`
	elseif not park then
		return "Rounds are not ready yet."
	end
	local spots: { SandboxMap.Spot } = {}
	local blocked: { SandboxMap.Spot } = {}
	for _, spot in RoundRules.parking(H.curb, zone.rect, H.lot, #players, Q.Park) do
		table.insert(if Round.clear(spot) then spots else blocked, spot)
	end
	for _, spot in blocked do -- (something in the way: still better than no van)
		table.insert(spots, spot)
	end
	local going: { Player } = {}
	for _, p in players do
		local spot = spots[#going + 1]
		local err, car = nil, nil
		if spot then
			err, car = park(p, spot)
		end
		if car then
			lockVan(car)
			car.model:SetAttribute("RoundVan", p.UserId)
			pcall(Vehicles.setBack, car, true)
			Round.label(car, p)
			Round.vans[p] = car
			Round.prompt(p, car)
			table.insert(going, p)
		else
			say(p, `⛔ Your van could not come to {H.name} ({err or "no room"}): you sit this round out.`)
		end
	end
	if #going == 0 then
		return "The vans could not come."
	end
	local run: Run = { host = going[1], house = house, name = H.name, difficulty = difficulty, party = table.clone(going), gone = {}, votes = {}, prompts = {}, ended = false, round = true }
	runs[house] = run
	for _, p in going do
		runOf[p] = run
	end
	local failed = moving().startRun(going[1], house, difficulty, Q.Seconds)
	if failed then
		release(run)
		for _, p in going do
			Round.dropVan(p)
		end
		return failed
	end
	local model = houseModel(house)
	if model then
		model:SetAttribute("RunDifficulty", difficulty)
	end
	Round.run, Round.phase, Round.endsAt = run, "play", workspace:GetServerTimeNow() + Q.Seconds
	Round.came, Round.pieces = {}, {}
	for _, p in going do
		table.insert(Round.came, { id = p.UserId, name = p.DisplayName })
	end
	for n, spot in RoundRules.spread(zone.arrive, #going, Q.Spread) do
		local p = going[n]
		padKey[p] = ""
		ride(p, H.name, false, run) -- 10.4: the van on its way there, over the fade
		jump(p, SandboxMap.cframe(spot))
	end
	sendRun(run)
	return nil
end

-- The results card's table (RoundRules.ranking over what everybody who came loaded).
function Round.ranking(list: { { [string]: any } }): { RoundRules.Rank }
	local pieces: { RoundRules.Piece } = {}
	for _, piece in list do
		if type(piece.to) == "number" then
			table.insert(pieces, { to = piece.to, value = tonumber(piece.value) or 0 })
		end
	end
	return RoundRules.ranking(pieces, Round.came)
end

-- The round ended (onEnd): its results, then the next countdown once everybody is back.
function Round.over(run: Run?)
	Round.phase = "over"
	Round.endsAt = workspace:GetServerTimeNow() + Q.Results + R.Fade.Out + 1
	Round.last = if run then run.house else Round.house
	Round.run = nil
	for _, prompt in Round.prompts do
		prompt:Destroy()
	end
	table.clear(Round.prompts)
end

-- What RoundUi shows a player now: the phase and its clock, the place, the table's top rows and theirs.
function Round.view(player: Player, rows: { RoundRules.Rank }): { [string]: any }
	local H = if Round.house then SandboxMap.house(Round.house) else nil
	local top: { { [string]: any } } = {}
	for n = 1, math.min(Q.Top, #rows) do
		local row = rows[n]
		table.insert(top, { name = row.name, count = row.count, value = row.value, place = row.place, me = row.id == player.UserId })
	end
	local mine = RoundRules.rankOf(rows, player.UserId)
	local run = Round.run
	return {
		kind = "round",
		phase = Round.phase,
		endsAt = Round.endsAt,
		house = Round.house,
		name = if H then H.name else nil,
		difficulty = Round.difficulty,
		inRound = run ~= nil and runOf[player] == run,
		players = if run then #run.party else Round.inGame(),
		ready = player:GetAttribute("InGame") == true,
		top = top,
		mine = if mine then { place = mine.place, count = mine.count, value = mine.value } else nil,
	}
end

-- Every player's round view, when it changed.
function Round.broadcast()
	local rows = if Round.phase == "play" or Round.phase == "over" then RoundRules.ranking(Round.pieces, Round.came) else {}
	for _, player in Players:GetPlayers() do
		local view = Round.view(player, rows)
		local mine = view.mine
		local key = `{view.phase}|{view.endsAt}|{view.house}|{view.inRound}|{view.players}|{view.ready}|{if mine then `{mine.place},{mine.count},{mine.value}` else ""}|{#rows}`
		for _, row in view.top do
			key ..= `|{row.name},{row.count},{row.value}`
		end
		if Round.sent[player] ~= key then
			Round.sent[player] = key
			send(player, view)
		end
	end
end

-- The portals' signs and the map in rounds: the round's place says so, the others that rounds need no pad.
function Round.signs(now: number)
	local run = Round.run
	for _, portal in L.portals do
		local house = portal.house
		if Round.phase == "wait" and house == Round.house then
			paint(house, `NEXT ROUND HERE · {RoundRules.clock(Round.endsAt - now)}`, R.Portal.Waiting)
			publish(house, "wait", Round.endsAt, {}, Round.difficulty)
		elseif run and house == run.house then
			paint(house, `ROUND ON · {RoundRules.clock(Round.endsAt - now)}`, R.Portal.InUse)
			publish(house, "use", nil, { `{#run.party} movers` }, run.difficulty)
		else
			paint(house, "ROUNDS · WAIT IN THE LOBBY", R.Portal.Free)
			publish(house, "free", nil, {}, nil)
		end
	end
end

function Runs.roundStep()
	local now = workspace:GetServerTimeNow()
	if Round.phase == "idle" or Round.phase == "wait" then
		if Round.inGame() == 0 then
			Round.phase, Round.house = "idle", nil
		elseif Round.phase == "idle" then
			Round.plan(now)
		elseif now >= Round.endsAt then
			local going: { Player } = {}
			for _, p in Players:GetPlayers() do
				if Round.ready(p) then
					table.insert(going, p)
				end
			end
			local house = Round.house
			if #going == 0 then
				Round.plan(now) -- (nobody free to go: the countdown again)
			else
				local err = if house then Round.begin(house, going, Round.difficulty or R.Default) else "No place to go."
				if err then
					for _, p in going do
						say(p, `⛔ The round could not start: {err}`)
					end
					Round.last = house
					Round.plan(now)
					Round.endsAt = now + math.min(Q.Wait, 10)
				end
			end
		end
	elseif Round.phase == "play" then
		local run = Round.run
		if not run or runs[run.house] ~= run then
			Round.over(run) -- (ended without its end heard: never stuck)
		else
			for p, prompt in Round.prompts do -- the Load prompts: on while their owner carries something
				local name = if runOf[p] == run then moving().carrying(p) else nil
				prompt.Enabled = name ~= nil
				if name and prompt.ActionText ~= `Load {name}` then
					prompt.ActionText = `Load {name}`
				end
			end
		end
	elseif Round.phase == "over" and now >= Round.endsAt then
		Round.plan(now)
	end
	Round.signs(now)
	Round.broadcast()
end

function Runs.round(): { [string]: any }
	return { phase = Round.phase, endsAt = Round.endsAt, house = Round.house, difficulty = Round.difficulty, run = Round.run, vans = Round.vans, prompts = Round.prompts, pieces = Round.pieces }
end

-- ── The pads ───────────────────────────────────────────────────────────────

-- Is this player free to stand on a pad (in no run, alive, on foot, not on a jump)?
local function free(player: Player): BasePart?
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

local function onPad(root: BasePart, pad: SandboxMap.Rect): boolean
	local at = root.Position
	return at.X >= pad.x0 and at.X <= pad.x1 and at.Z >= pad.z0 and at.Z <= pad.z1 and at.Y >= SandboxMap.GroundTop - 2 and at.Y <= SandboxMap.GroundTop + R.PadHeight
end

function Runs.step()
	if Config.Rounds.On then
		Runs.roundStep() -- 10.5 rounds: no pads
		return
	end
	local now = workspace:GetServerTimeNow()
	local standing: { [Player]: string } = {}
	local roots: { [Player]: BasePart } = {}
	for _, player in Players:GetPlayers() do
		local root = free(player)
		if root then
			roots[player] = root
		end
	end
	for _, portal in L.portals do
		local house = portal.house
		local here: { number } = {}
		for player, root in roots do
			if onPad(root, portal.pad) then
				if runs[house] then
					if inUseSaid[player] ~= house then
						inUseSaid[player] = house
						say(player, `⛔ {portal.name} is in use: try another house.`)
					end
				else
					standing[player] = house
					table.insert(here, player.UserId)
				end
			elseif inUseSaid[player] == house then
				inUseSaid[player] = nil
			end
		end
		table.sort(here) -- (newcomers in one look: a stable order)
		local pad = pads[house] or RunRules.newPad()
		pads[house] = pad
		local run = runs[house]
		if run then
			RunRules.padStep(pad, {}, now, R.Countdown)
			paint(house, "IN USE · A RUN IS ON", R.Portal.InUse)
			local party: { string } = {}
			for _, member in run.party do
				table.insert(party, member.DisplayName)
			end
			publish(house, "use", nil, party, run.difficulty) -- (10.x the map)
			continue
		end
		local hostBefore = pad.host
		RunRules.padStep(pad, here, now, R.Countdown)
		if pad.host and pad.host ~= hostBefore then
			local host = Players:GetPlayerByUserId(pad.host)
			pad.difficulty = RunRules.choose(if host then openOf(host) else R.Open, pad.difficulty)
		end
		if #pad.order == 0 then
			paint(house, "WALK ONTO THE PAD", R.Portal.Free)
			publish(house, "free", nil, {}, nil) -- (10.x the map)
		else
			paint(house, `STARTING IN {RunRules.left(pad, now)} · {math.min(#pad.order, R.MaxParty)}/{R.MaxParty}`, R.Portal.Waiting)
			publish(house, "wait", pad.endsAt, partyNames(pad.order), pad.difficulty)
		end
		if RunRules.due(pad, now) then
			local ids = RunRules.party(pad, R.MaxParty)
			local difficulty = pad.difficulty
			pads[house] = RunRules.newPad()
			local party: { Player } = {}
			for _, id in ids do
				local p = Players:GetPlayerByUserId(id)
				if p then
					table.insert(party, p)
				end
			end
			if #party > 0 then
				local err = Runs.begin(house, party, difficulty)
				if err then
					for _, p in party do
						say(p, `⛔ The run could not start: {err}`)
					end
				end
			end
		end
	end
	-- the pad panels: to whoever stands on a pad (a view when it changed), none to whoever stepped off
	for _, player in Players:GetPlayers() do
		local house = standing[player]
		local pad = if house then pads[house] else nil
		if house and pad and #pad.order > 0 and not runOf[player] then
			local view = padView(house, pad, player)
			local key = `{house}|{view.left}|{view.host}|{view.difficulty}|{table.concat(view.party, ",")}|{table.concat(view.open, ",")}`
			if padKey[player] ~= key then
				padKey[player] = key
				send(player, view)
			end
		elseif padKey[player] ~= nil and padKey[player] ~= "" then
			padKey[player] = ""
			send(player, { kind = "pad" })
		end
	end
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
		padKey[player] = nil
		Round.sent[player] = nil -- (10.5 rounds: the round's view again at the next look)
	elseif kind == "difficulty" then
		for house, pad in pads do
			if pad.host == player.UserId and not runs[house] then
				if RunRules.isOpen(openOf(player), message.id) then
					pad.difficulty = RunRules.clean(message.id)
					padKey[player] = nil
				else
					say(player, "🔒 Finish a run at the difficulty before it to open that one.")
				end
			end
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

function Runs.padOf(house: string): RunRules.Pad?
	return pads[house]
end

function Runs.inUse(house: string): boolean
	return runs[house] ~= nil
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
	elseif what == "round" then -- 10.5 rounds: the countdown over now
		if not Config.Rounds.On then
			return "ADMIN: rounds are off (Config.Rounds.On)."
		elseif Round.phase ~= "wait" then
			return "ADMIN: no countdown now."
		end
		Round.endsAt = workspace:GetServerTimeNow()
		return "ADMIN: the round starts now."
	elseif what == "end" then
		local run = runOf[player]
		if not run then
			return "ADMIN: you are in no run."
		end
		moving().endRun(run.host, "Ended by the admin: what was in the truck went home")
		return "ADMIN: the run ended."
	end
	return "ADMIN: start | difficulty | round | end."
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
	findSigns()
	wrapCrew()
	moving().onRunEnd(onEnd)
	moving().roundVan = function(player: Player): any -- 10.5 rounds: a new body stands by your own van
		return Round.vans[player]
	end
	moving().onHandOver(function(old: Player, new: Player) -- 10.5 rounds: the host left the game: the round goes on
		local run = runOf[new]
		if run and run.round then
			run.host = new
		end
	end)
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
				prompt.ActionText = if Config.Rounds.On then "How rounds work" else "How runs work"
				prompt.ObjectText = "DELIVEROS DISPATCH"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Triggered:Connect(function(player: Player)
					if Config.Rounds.On then -- 10.5 rounds
						say(player, `🏁 Every round everybody rides to one house, each to their own van. Grab the loot, carry it to YOUR van and Load it: it is yours at once. {RoundRules.clock(Config.Rounds.Seconds)} on the clock, the most value wins. The next round starts by itself: wait here.`)
					else
						say(player, `🏠 Walk onto a house's glowing pad: in {R.Countdown} s everybody on it goes in ({R.MaxParty} at most). The first on it picks the difficulty. Carry the loot into the truck at the door, FINISH at the truck (or beat the clock): it all comes home to your warehouse.`)
					end
				end)
				prompt.Parent = d
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local run = runOf[player]
		if run and (run.host ~= player or run.round) then -- (10.5 rounds: the host's move goes over: Moving.handOver)
			runOf[player] = nil
			local at = table.find(run.party, player)
			if at then
				table.remove(run.party, at)
			end
			run.votes[player.UserId] = nil
			sendRun(run)
		end
		away[player], padKey[player], inUseSaid[player], adminPick[player] = nil, nil, nil, nil
		Round.dropVan(player) -- (10.5 rounds)
		Round.sent[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(R.Every)
			local ok, err = pcall(Runs.step :: any)
			if not ok then
				warn(`[Runs] {err}`)
			end
		end
	end)
end

return Runs
