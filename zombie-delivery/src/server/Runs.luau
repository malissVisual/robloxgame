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
--     RunDifficulty too (traps and the loot's rarity read it), the truck gets its prompts (the host's "Finish the run",
--     the others' "Vote to finish") and everybody fades over to the house's front yard (SandboxMap.Zones' arrive, Apart
--     studs across), its door before them, from wherever they waited in the lobby. The host's helper is the move's
--     (server/MoveHelper.luau: he waits by the truck at the house and goes with the run; 10.1 free, the host's pick of
--     their crew: server/HelperCrew.luau, which also traps a helper in some runs' houses to rescue).
--   * One run in a house at a time, and 10.6 never the quick round's house (Runs.houseBusy, RunRules.houseBusy: the
--     PLAY panel shows the house busy, a lobby cannot pick it or start there).
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
--                                      lobbies (server/Parties.luau's start); 10.5 the rounds' loop
--   Runs.begin(house, party, difficulty, admin?)   a run now (a lobby's start, the admin's): an error text or nil
--   Runs.finish(player)                the host's FINISH (true when a run ended)
--   Runs.vote(player) / Runs.leave(player)   a party member's vote to finish / leaving the run (or the round) alone
--   Runs.runOf(player)                 the run a player is in (host or party) or nil: { host, house, difficulty, party,
--                                      round? }
--   Runs.inUse(house)                  a run in that house now (a lobby's or the round's)?
--   Runs.houseBusy(house) -> why?      10.6: why a house takes no lobby's run now ("round": the quick round's place, its
--                                      countdown, its round or its ride back; "run": a run in it), else nil
--   Runs.list()                        10.4: the runs now ({ house, difficulty, host, party, round? }: the map's IN A RUN)
--   Runs.free(player) -> root?         10.4: their body's root while they are free to stand in the PLAY circle and go
--                                      (alive, on foot, in no run or move, not on a jump), else nil
--   Runs.openOf(player) -> n           10.4: the difficulties open to them (their save's runUnlocked)
--   Runs.admin(player, what, arg?, admin?)   the admin panel's SANDBOX tab (`player` its TARGET): "start" (a house: a run
--                                      for `player` alone, at the difficulty `admin` picked, locks ignored) | "difficulty"
--                                      (its id) | "end" (`player`'s run) | 10.5 "round" (the countdown's round now; 10.6
--                                      `player` queued first) → what to say
-- 10.4 the ride (the owner: "there is no driving the car any more, so every time you go to a place, an animation of
-- you driving there"): before every jump to a house and back to the lobby, each player gets { kind = "ride", to, back,
-- difficulty?, party?, round?, seconds } (Config.Runs.Ride): client/RideUi.luau shows the van on its way over the fade.
-- 10.x danger (server/RunDanger.luau: the locks and keys, the vault, the hazards, the zombies, the bat): started with the
-- runs (Runs.start); the results card's `danger` ({ vault = true / false / nil: none, stopped = zombies killed }) is
-- RunDanger.result's (the blocks marked "10.x danger"). 10.5: no zombies, no bat (Config.Runs.Danger).
-- 10.5 ROUNDS (Config.Rounds.On; the owner: "16 people on one server … a round starts at one place, everybody runs
-- there, everyone has their own car, what you carry off to it quickly is yours … not teams"; the rules
-- shared/RoundRules.luau, the client client/RoundUi.luau; the block "10.5 ROUNDS" below): one round at a time for the
-- whole server. 10.6 BOTH IN PLAY (the owner: "Both in the PLAY circle"): the rounds are the PLAY panel's QUICK ROUND,
-- beside its PRIVATE LOBBY (server/Parties.luau): nobody goes on one before they join its queue there.
--   * The queue (Runs.queue: the Party remote's { kind = "round", on }, in the PLAY circle; LEAVE QUEUE in the panel or
--     on the banner, the Runs remote's { kind = "queue", on = false }, anywhere): nobody in a private lobby, nobody
--     twice; LEAVE THE ROUND, leaving the game or (Config.Rounds.Stay false) the round's end take you out of it.
--   * The countdown (Wait s) runs in the lobby while somebody is in the queue (none: no round, "idle"); the next place
--     is picked as it starts (RoundRules.places: no run in it, no private lobby holding it when another is free, never
--     the last one again; then RoundRules.pick) and its difficulty (Config.Rounds.Difficulties, at random): the banner,
--     the PLAY panel and the map say where (the PLAY circle model's attributes RoundPhase, RoundHouse, RoundDifficulty,
--     RoundEndsAt, RoundQueued, RoundMovers: client/SandboxMapData.luau). From then on that house is the round's
--     (Runs.houseBusy "round") until everybody is back.
--   * The start: everybody queued and free (alive, on no move, not on a jump) goes. Each player's own van is parked at
--     the house (RoundRules.parking: side by side at its curb and in rows behind it, the spots with something solid in
--     the way last), locked as a run's truck, its back open, its owner's name over it (its model's attribute RoundVan =
--     their UserId) and its Load prompt (E, only they see it: MoveOnly). The run is the host's (the first player's)
--     Moving.startRun with the round's clock (Seconds): its contract's `round` (server/Moving.luau "10.5 ROUNDS": no
--     move truck, no helper, no FINISH). Everybody rides there (10.4) and lands in rows by the door.
--   * In the round: Load at your own van while you carry something (Moving.claim): it is yours at once, into your
--     warehouse's stock; everybody in the round hears it ({ kind = "claim", … }: the feed) and sees the table
--     ({ kind = "round", … }: RoundUi's). LEAVE (the list's: the Runs remote's "leave") takes you back alone (your van
--     goes, you are out of the queue); the host leaving hands the round's move over (Moving.handOver), it never ends it.
--   * The end: the clock (Moving's tick ends the run): the results card ranks everybody in it (RoundRules.ranking: its
--     `round`), Results s later everybody rides back to the lobby, the vans go, the next countdown starts (somebody
--     still queued).
--   Runs.queue(player, on) -> why?     10.6: into the queue (on) or out of it; why not (a PartyRules.why code) or nil
--   Runs.queued(player) -> bool        10.6: in the queue?
--   Runs.roundOf(player?) -> view?     10.6: the quick round for the PLAY panel (server/Parties.luau's view; nil: rounds
--                                      off): { phase, endsAt, house, name, difficulty, queued, mine, inRound, movers,
--                                      seconds } (no player: nobody's, the circle's sign)
--   Runs.round()                       the round's state now (the tests'): { phase, endsAt, house, difficulty, run?, vans,
--                                      queue }
--   Runs.roundStep()                   one look at the round (the loop's; the tests')

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
local runs: { [string]: Run } = {} -- by house
local runOf: { [Player]: Run } = {} -- every party member's
local away: { [Player]: number } = {} -- on a jump (os.clock until): not free (10.4: the PLAY circle ignores them)
local adminPick: { [Player]: string } = {}
local started = false
-- 10.5 rounds (the block "10.5 ROUNDS" below: its functions): the server's one round, in one table (the -O0 registers)
--   phase    "idle" (nobody queued) | "wait" (the countdown) | "play" (the round) | "over" (its results, the ride back)
--   endsAt   the server's time the phase ends (wait: the start; play: the round's clock; over: the next countdown)
--   house, difficulty   the next round's (wait) or this one's (play, over); last: the round before's house
--   run      this round's run (play); vans / prompts: each player's van at the house and its Load prompt
--   came     everybody who came ({ id, name }, the order they came); pieces: what they loaded ({ to, value })
--   sent     the last round view sent to each player (a key: only what changed goes)
--   queue    10.6: who is in the queue (the PLAY panel's QUICK ROUND), the order they joined; shown: the PLAY circle's
--            round attributes as last written (a key)
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
	queue = {} :: { Player },
	shown = "",
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

-- 10.6: why `house` takes no new run now (RunRules.houseBusy: the quick round's place, or a run in it), else nil.
function Runs.houseBusy(house: string): string?
	return RunRules.houseBusy(house, function(id: string): boolean
		return runs[id] ~= nil
	end, if Config.Rounds.On then { house = Round.house, phase = Round.phase } else nil)
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

-- 10.4: back beside the PLAY circle (Lobby.play.back: just south of it, facing it; never in it). `house` the run's.
-- 10.5 rounds: the plaza's spawn, in rows (RoundRules.spread: the many of a round), never in the circle either.
local function backTo(_house: string, players: { Player }, round: boolean?)
	if round then
		for n, spot in RoundRules.spread(L.spawn, #players, Config.Rounds.Spread) do
			ride(players[n], R.Ride.Home, true, nil)
			jump(players[n], SandboxMap.cframe(spot))
		end
		return
	end
	for n, frame in spread(L.play.back, #players) do
		ride(players[n], R.Ride.Home, true, nil) -- 10.4 the ride home
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
		round = run.round == true, -- (10.5 rounds)
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
	local taken = Runs.houseBusy(house) -- 10.6: never the quick round's house
	if taken == "round" then
		return `{H.name} is the quick round's place right now: try another house.`
	elseif taken then
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
		Runs.queue(p, false) -- (10.6: a run of their own: out of the quick round's queue)
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
	if run.round then
		Runs.queue(player, false) -- (10.6: leaving the round is leaving its queue too)
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
		then "🚪 You leave the round (and its queue): back to the lobby. What you loaded is in your warehouse already."
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
			round = if ranking then { ranking = ranking, place = (RoundRules.rankOf(ranking, p.UserId) or { place = 0 }).place, players = #ranking,
				queued = Runs.queued(p) } else nil, -- 10.5 (10.6: still in the queue: the next one comes)
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

-- The private lobby `player` is in (server/Parties.luau), nil none.
function Round.lobbyOf(player: Player): any
	local ok, lobby = pcall(function(): any
		return require(Server.Parties).lobbyOf(player)
	end)
	return if ok then lobby else nil
end

-- 10.6: queued (the PLAY panel's QUICK ROUND), loaded, alive, on no move and no jump, in no lobby: goes on the round.
function Round.ready(player: Player): boolean
	if not table.find(Round.queue, player) or runOf[player] or (away[player] and os.clock() < away[player]) then
		return false
	end
	return PlayerData.get(player) ~= nil and rootOf(player) ~= nil and moving().busy(player) == nil and Round.lobbyOf(player) == nil
end

-- How many are in the queue (10.6: who joined it in the PLAY panel; gone from the game: out).
function Round.queued(): number
	for n = #Round.queue, 1, -1 do
		if not Round.queue[n].Parent then
			table.remove(Round.queue, n)
		end
	end
	return #Round.queue
end

-- The countdown to the next round: its place (RoundRules.places: no run in it, no private lobby's when another is
-- free, never the last one again) and difficulty. No place free: none yet, a look again in a moment.
function Round.plan(now: number)
	local ids: { string } = {}
	for _, h in SandboxMap.Houses do
		if SandboxMap.zone(h.id) then
			table.insert(ids, h.id)
		end
	end
	local held: { [string]: boolean } = {}
	pcall(function()
		for _, lobby in require(Server.Parties).lobbies() do
			held[lobby.house] = true
		end
	end)
	local places = RoundRules.places(ids, Round.last, function(id: string): boolean
		return RunRules.houseBusy(id, function(house: string): boolean
			return runs[house] ~= nil
		end, nil) ~= nil
	end, function(id: string): boolean
		return held[id] == true
	end)
	Round.house = RoundRules.pick(places, Round.last, math.random())
	Round.difficulty = RoundRules.difficulty(Q.Difficulties, math.random())
	Round.phase, Round.endsAt = "wait", now + (if Round.house then Q.Wait else math.min(Q.Wait, 5))
end

-- 10.6: into the quick round's queue (on) or out of it: why not (a PartyRules.why code) or nil.
function Runs.queue(player: Player, on: boolean): string?
	local at = table.find(Round.queue, player)
	if not on then
		if not at then
			return "notQueued"
		end
		table.remove(Round.queue, at)
		Round.sent[player] = nil
		return nil
	elseif not Q.On then
		return "roundOff"
	elseif at then
		return nil -- (in it already)
	elseif runOf[player] then
		return "inRun"
	elseif Round.lobbyOf(player) then
		return "inLobby"
	end
	table.insert(Round.queue, player)
	Round.sent[player] = nil
	if Round.phase == "idle" then
		Round.plan(workspace:GetServerTimeNow())
	end
	return nil
end

function Runs.queued(player: Player): boolean
	return table.find(Round.queue, player) ~= nil
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
			err, car = park(p, spot, false)
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

-- The round ended (onEnd): its results, then the next countdown once everybody is back (10.6: Stay false: its players
-- out of the queue).
function Round.over(run: Run?)
	Round.phase = "over"
	Round.endsAt = workspace:GetServerTimeNow() + Q.Results + R.Fade.Out + 1
	Round.last = if run then run.house else Round.house
	Round.run = nil
	for _, prompt in Round.prompts do
		prompt:Destroy()
	end
	table.clear(Round.prompts)
	if run and not Q.Stay then
		for _, p in run.party do
			Runs.queue(p, false)
		end
	end
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
		players = if run then #run.party else #Round.queue,
		queued = #Round.queue, -- 10.6
		ready = Runs.queued(player), -- (10.6: in the queue)
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
		local key = `{view.phase}|{view.endsAt}|{view.house}|{view.inRound}|{view.players}|{view.queued}|{view.ready}|{if mine then `{mine.place},{mine.count},{mine.value}` else ""}|{#rows}`
		for _, row in view.top do
			key ..= `|{row.name},{row.place},{row.count},{row.value}`
		end
		if Round.sent[player] ~= key then
			Round.sent[player] = key
			send(player, view)
		end
	end
end

-- 10.6 the map (client/SandboxMapData.luau, read-only; the portals' signs are gone): the PLAY circle model's attributes
-- RoundPhase, RoundHouse, RoundDifficulty, RoundEndsAt, RoundQueued and RoundMovers, written only when they change.
function Round.publish()
	local world = workspace:FindFirstChild("Sandbox")
	local lobby = world and world:FindFirstChild("Lobby")
	local circle = lobby and lobby:FindFirstChild("PlayCircle")
	local run = Round.run
	local phase = if Q.On then Round.phase else "off"
	local movers = if run then #run.party else 0
	local key = `{phase}|{Round.house}|{Round.difficulty}|{Round.endsAt}|{#Round.queue}|{movers}`
	if not circle or Round.shown == key then
		return
	end
	Round.shown = key
	circle:SetAttribute("RoundPhase", phase)
	circle:SetAttribute("RoundHouse", Round.house)
	circle:SetAttribute("RoundDifficulty", Round.difficulty)
	circle:SetAttribute("RoundEndsAt", if Round.phase ~= "idle" then Round.endsAt else nil)
	circle:SetAttribute("RoundQueued", #Round.queue)
	circle:SetAttribute("RoundMovers", movers)
end

function Runs.roundStep()
	local now = workspace:GetServerTimeNow()
	local count = Round.queued()
	if Round.phase == "idle" or Round.phase == "wait" then
		if not Q.On or count == 0 then
			Round.phase, Round.house, Round.difficulty = "idle", nil, nil
		elseif Round.phase == "idle" or (Round.house == nil and now >= Round.endsAt) then
			Round.plan(now) -- (no place free before: a look again)
		elseif now >= Round.endsAt then
			local going: { Player } = {}
			for _, p in Round.queue do
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
		if count > 0 and Q.On then
			Round.plan(now)
		else
			Round.phase, Round.house, Round.difficulty = "idle", nil, nil
		end
	end
	Round.publish()
	if Q.On then
		Round.broadcast()
	end
end

function Runs.round(): { [string]: any }
	return { phase = Round.phase, endsAt = Round.endsAt, house = Round.house, difficulty = Round.difficulty, run = Round.run, vans = Round.vans, prompts = Round.prompts,
		pieces = Round.pieces, queue = table.clone(Round.queue) }
end

-- 10.6: the quick round as the PLAY panel shows it (server/Parties.luau's view), nil while the rounds are off.
function Runs.roundOf(player: Player?): { [string]: any }?
	if not Q.On then
		return nil
	end
	local H = if Round.house then SandboxMap.house(Round.house) else nil
	local run = Round.run
	return {
		phase = Round.phase,
		endsAt = if Round.phase ~= "idle" then Round.endsAt else nil,
		house = Round.house,
		name = if H then H.name else nil,
		difficulty = Round.difficulty,
		queued = #Round.queue,
		mine = player ~= nil and Runs.queued(player),
		inRound = player ~= nil and run ~= nil and runOf[player] == run,
		movers = if run then #run.party else 0,
		seconds = Q.Seconds,
	}
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
		Round.sent[player] = nil -- (10.5 rounds: the round's view again at the next look)
	elseif kind == "vote" then
		Runs.vote(player)
	elseif kind == "leave" then
		Runs.leave(player)
	elseif kind == "queue" and message.on ~= true then -- 10.6: the banner's LEAVE QUEUE (joining is the PLAY panel's)
		if Runs.queue(player, false) == nil then
			say(player, "⚡ You left the QUICK ROUND queue. Step into PLAY to join it again.")
		end
		Round.broadcast()
	end
end

-- ── Queries, the admin ─────────────────────────────────────────────────────

function Runs.runOf(player: Player): { host: Player, house: string, difficulty: string, party: { Player }, round: boolean? }?
	local run = runOf[player]
	return if run then { host = run.host, house = run.house, difficulty = run.difficulty, party = table.clone(run.party), round = run.round } else nil
end

function Runs.inUse(house: string): boolean
	return runs[house] ~= nil
end

function Runs.list(): { { house: string, difficulty: string, host: Player, party: { Player }, round: boolean? } }
	local out = {}
	for house, run in runs do
		if not run.ended then
			table.insert(out, { house = house, difficulty = run.difficulty, host = run.host, party = table.clone(run.party), round = run.round })
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
	elseif what == "round" then -- 10.5 rounds: the countdown over now (10.6: the TARGET queued first)
		if not Config.Rounds.On then
			return "ADMIN: rounds are off (Config.Rounds.On)."
		end
		local why = Runs.queue(player, true)
		if why then
			return `ADMIN: {player.DisplayName} can't join the queue ({why}).`
		elseif Round.phase ~= "wait" then
			return "ADMIN: no countdown now (a round is on)."
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
				prompt.ActionText = "How runs work"
				prompt.ObjectText = "DELIVEROS DISPATCH"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Triggered:Connect(function(player: Player)
					say(player, `▶ Step into the glowing PLAY circle. {if Config.Rounds.On then `QUICK ROUND: join the queue, everybody in it rides to one house, each to their own van: what you load is yours at once, {RoundRules.clock(Config.Rounds.Seconds)} on the clock, the most value wins. ` else ""}PRIVATE LOBBY: CREATE A LOBBY (a house, a difficulty, public or friends only) or JOIN one ({R.MaxParty} at most); everybody READY, the host presses START, carry the loot into the truck at the door and FINISH there: it all comes home to your warehouse.`)
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
		away[player], adminPick[player] = nil, nil
		Runs.queue(player, false) -- (10.6)
		Round.dropVan(player) -- (10.5 rounds)
		Round.sent[player] = nil
	end)
	-- 10.4: the PLAY circle's party lobbies (they start the runs: Runs.begin)
	local started, why = pcall(function()
		require(Server.Parties).start(Runs)
	end)
	if not started then
		warn(`[Runs] the party lobbies did not start: {why}`)
	end
	task.spawn(function() -- 10.5 rounds: the round's loop (10.6: the queue's countdown, the round, its end)
		while true do
			task.wait(Config.Rounds.Every)
			local stepped, err = pcall(Runs.roundStep :: any)
			if not stepped then
				warn(`[Runs] {err}`)
			end
		end
	end)
end

return Runs
