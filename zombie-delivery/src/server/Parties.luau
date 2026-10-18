--!strict
-- 10.4 PARTY LOBBIES (the owner: "and on the map there'd be just one circle where you'd stand, like PLAY, and you'd
-- create a lobby"; Dungeon Quest's way): the lobby's one PLAY circle (shared/SandboxMap.luau Lobby.play, built by
-- server/LobbyWorld.luau) and the party lobbies that start the runs (the rules shared/PartyRules.luau; Config.Runs.Party;
-- the PLAY panel client/PlayUi.luau). server/Runs.luau starts it (Runs.start) and keeps every run's own life.
--   * The circle: every Config.Runs.Every s the server looks who stands in it (Runs.free: alive, on foot, in no run,
--     not on a jump; within its radius, Play.Height over the ground at most). Whoever stands in it gets the PLAY view
--     (the Party remote's { kind = "play", circle = true, … }: their panel opens); whoever is in a lobby gets it
--     wherever they walk (circle = false: the lobby bar); everybody else { kind = "play" } (nothing). A view goes only
--     when it changed.
--   * CREATE A LOBBY (in the circle only): a house (one lobby holds a house; a house in a run is busy: Runs.inUse), a
--     difficulty open to the host (their save's runUnlocked), public or friends only (the host's Roblox friends:
--     Player:IsFriendsWithAsync through pcall, the answer kept Party.Friends s; a lobby for friends only is listed to its
--     host's friends alone, and joined by them alone). JOIN (in the circle only): a lobby you see, not full, not
--     starting, not one whose host took you out a moment ago. In it: READY on / off, LEAVE (the host's closes it); the
--     host's house, difficulty, KICK, START (the host READY, the house in no run: Party.Countdown s), CANCEL. Walking
--     away keeps you in it; only LEAVE (or KICK, or leaving the game) takes you out. A member who ends up in a run
--     some other way (the admin's) is out of their lobby.
--   * The countdown over: the run (Runs.begin with the lobby's members who are free to go, the host first, its house
--     and difficulty); the lobby is gone. A member who is not free then (dead, seated) stays behind, told so; a host
--     who is not, or a run that cannot start: the countdown is off, the lobby stays, everybody told why.
--   * For the map (read-only, client/SandboxMapData.luau): the PLAY circle model's attribute Party.Attribute, the open
--     lobbies (host, house, difficulty, n / max, friends only, open / full / starting) and the runs now (state "run",
--     who), PartyRules.encode, written only when it changes; its ring, posts and glow in Play.Waiting while a lobby
--     counts down (else Play.Free) and its sign's Status line ("STEP IN TO PLAY", "2 OPEN LOBBIES · STEP IN",
--     "STARTING IN 3 · THE OLD MILL").
--   * 10.6 BOTH IN PLAY (the owner: "Both in the PLAY circle"): the PLAY view's `round` (server/Runs.luau's
--     Runs.roundOf: the quick round's phase, its next or current place, difficulty, clock, how many are queued, you
--     queued or not; nil while Config.Rounds.On is false) and the Party remote's { kind = "round", on }: JOIN THE QUEUE
--     (in the circle only, in no lobby: Runs.queue) or LEAVE THE QUEUE (anywhere). Somebody queued makes or joins no
--     lobby ("queued": LEAVE THE QUEUE first). A house is busy for a lobby (Runs.houseBusy, RunRules.houseBusy: the
--     one check the rounds use too) while a run is in it or it is the quick round's place (its countdown, its round,
--     its ride back): the house cards say QUICK ROUND, CREATE / CHANGE HOUSE / START refuse it. The map's IN A RUN
--     lists the lobbies' runs only (the round has its own line: Runs' attributes on the circle); the circle's sign
--     names the next round ("QUICK ROUND IN 0:42 · THE OLD MILL") when no lobby counts down.
--
--   Parties.start(runs)              the remote, the loop (once; `runs`: server/Runs.luau)
--   Parties.step()                   one look (the loop's; the tests')
--   Parties.lobbyOf(player) -> Lobby?   the lobby a player is in (PartyRules.Lobby, the server's own: read it only)
--   Parties.lobbies() -> { Lobby }   every lobby now
--   Parties.inCircle(player) -> bool    stood in the circle at the last look
--   Parties.viewOf(player) -> view?  the PLAY view that player gets now (nil: none)
--   Parties.friendsWith              a test's stand-in for Player:IsFriendsWithAsync (host, userId) -> boolean (nil: Roblox's)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PartyRules = require(Shared.PartyRules)
local RunRules = require(Shared.RunRules)
local SandboxMap = require(Shared.SandboxMap)

local Parties = {}

Parties.friendsWith = nil :: ((Player, number) -> boolean)?

local R = Config.Runs
local PA = R.Party
local PL = R.Play

local runs: any = nil -- (server/Runs.luau: Parties.start's)
local remote: RemoteEvent? = nil
local book = PartyRules.newBook()
local inside: { [Player]: boolean } = {} -- in the circle at the last look
local sent: { [Player]: string } = {} -- the last view sent, flattened ("" none, nil: send it again)
local friends: { [string]: { yes: boolean, at: number } } = {} -- "host:viewer" → the answer and when
local asking: { [string]: boolean } = {}
local circle: { model: Instance?, glows: { BasePart }, status: TextLabel?, key: string, attribute: string } = { glows = {}, key = "", attribute = "" }
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function say(player: Player?, text: string)
	if player and player.Parent then
		Net.get("Notice"):FireClient(player, text)
	end
end

local function playerOf(id: number): Player?
	return Players:GetPlayerByUserId(id)
end

local function nameOf(id: number): string
	local p = playerOf(id)
	return if p then p.DisplayName else "?"
end

local function houseName(house: string): string
	local h = SandboxMap.house(house)
	return if h then h.name else house
end

-- 10.6: why a house takes no lobby's run now ("round": the quick round's place; "run": a run in it), nil free
-- (server/Runs.luau's Runs.houseBusy: RunRules.houseBusy, the one check both use).
local function busy(house: string): string?
	return if runs then runs.houseBusy(house) else nil
end

local function openOf(player: Player): number
	return if runs then runs.openOf(player) else R.Open
end

-- Everybody in a lobby but `except`: told `text`.
local function tell(lobby: PartyRules.Lobby, text: string, except: number?)
	for _, id in lobby.members do
		if id ~= except then
			say(playerOf(id), text)
		end
	end
end

-- ── Friends (Player:IsFriendsWithAsync through pcall, the answer kept a while) ──

local function friendKnown(host: number, viewer: number): boolean?
	if host == viewer then
		return true
	end
	local e = friends[`{host}:{viewer}`]
	if e and os.clock() - e.at < PA.Friends then
		return e.yes
	end
	return nil
end

-- The answer now (it may wait for Roblox): false when the host is gone or the call fails.
local function askFriend(host: number, viewer: number): boolean
	local known = friendKnown(host, viewer)
	if known ~= nil then
		return known
	end
	local who = playerOf(host)
	local yes = false
	if who then
		local hook = Parties.friendsWith
		local ok, answer = pcall(function(): any
			if hook then
				return hook(who, viewer)
			end
			return who:IsFriendsWithAsync(viewer)
		end)
		yes = ok and answer == true
	end
	friends[`{host}:{viewer}`] = { yes = yes, at = os.clock() }
	return yes
end

-- The answer known now, else false while it is asked in the background (the next look lists the lobby).
local function friendSoon(host: number, viewer: number): boolean
	local known = friendKnown(host, viewer)
	if known ~= nil then
		return known
	end
	local key = `{host}:{viewer}`
	if not asking[key] then
		asking[key] = true
		task.spawn(function()
			askFriend(host, viewer)
			asking[key] = nil
		end)
	end
	return false
end

-- ── The views ──────────────────────────────────────────────────────────────

local function lobbyView(lobby: PartyRules.Lobby, player: Player): { [string]: any }
	local members: { { [string]: any } } = {}
	for _, id in lobby.members do
		table.insert(members, { id = id, name = nameOf(id), ready = lobby.ready[id] == true, host = id == lobby.host })
	end
	local host = playerOf(lobby.host)
	local open: { string } = {}
	local count = if host then openOf(host) else R.Open
	for _, def in RunRules.list() do
		if RunRules.isOpen(count, def.id) then
			table.insert(open, def.id)
		end
	end
	local ok, why = PartyRules.canStart(lobby, busy)
	return {
		id = lobby.id,
		host = lobby.host,
		hostName = nameOf(lobby.host),
		mine = lobby.host == player.UserId,
		house = lobby.house,
		name = houseName(lobby.house),
		difficulty = lobby.difficulty,
		friends = lobby.friends,
		max = R.MaxParty,
		endsAt = lobby.endsAt,
		members = members,
		ready = PartyRules.readyCount(lobby),
		open = open, -- (the host's: what the difficulty buttons offer)
		canStart = ok,
		why = if why then PartyRules.why(why, lobby.house) else nil,
	}
end

function Parties.viewOf(player: Player): { [string]: any }?
	local id = player.UserId
	local mine = PartyRules.lobbyOf(book, id)
	local here = inside[player] == true
	if not here and not mine then
		return nil
	end
	local houses: { { [string]: any } } = {}
	for _, h in SandboxMap.Houses do
		local state, holder = PartyRules.houseState(book, h.id, busy)
		local by: string? = nil
		if holder then
			by = nameOf(holder.host)
		elseif state == "run" and runs then
			for _, run in runs.list() do
				if run.house == h.id and not run.round then
					by = run.host.DisplayName
				end
			end
		end
		table.insert(houses, { id = h.id, name = h.name, state = state, by = by, mine = holder ~= nil and holder == mine })
	end
	local open: { string } = {}
	for _, def in RunRules.list() do
		if RunRules.isOpen(openOf(player), def.id) then
			table.insert(open, def.id)
		end
	end
	local lobbies: { { [string]: any } } = {}
	for _, lobby in PartyRules.list(book, id, function(host: number): boolean
		return friendSoon(host, id)
	end) do
		local entry = PartyRules.entry(lobby, nameOf)
		table.insert(lobbies, {
			id = lobby.id,
			host = lobby.host,
			hostName = entry.host,
			house = lobby.house,
			name = houseName(lobby.house),
			difficulty = lobby.difficulty,
			n = entry.n,
			max = entry.max,
			friends = lobby.friends,
			state = entry.state,
			mine = lobby == mine,
		})
	end
	return { kind = "play", circle = here, me = id, open = open, houses = houses, lobbies = lobbies, lobby = if mine then lobbyView(mine, player) else nil,
		round = if runs then runs.roundOf(player) else nil } -- (10.6: the quick round, the panel's QUICK ROUND)
end

-- A view as one string (a key: is it the one sent last?), its fields sorted.
local function flat(value: any): string
	if type(value) ~= "table" then
		return tostring(value)
	end
	local out: { string } = {}
	for k, v in value do
		table.insert(out, `{k}={flat(v)}`)
	end
	table.sort(out)
	return "{" .. table.concat(out, ";") .. "}"
end

local function push(player: Player)
	local r = remote
	if not r or not player.Parent then
		return
	end
	local view = Parties.viewOf(player)
	local key = if view then flat(view) else ""
	if sent[player] == key then
		return
	end
	sent[player] = key
	r:FireClient(player, view or { kind = "play" })
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		push(player)
	end
end

-- ── The circle's look and the map's copy ───────────────────────────────────

local function findCircle()
	local world = workspace:FindFirstChild("Sandbox")
	local lobby = world and world:FindFirstChild("Lobby")
	local model = lobby and lobby:FindFirstChild("PlayCircle")
	if not model then
		return
	end
	circle.model = model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "PlayRing" or d.Name == "PlayGlow" or d.Name == "PlayLamp") then
			table.insert(circle.glows, d)
		elseif d:IsA("TextLabel") and d.Name == "Status" then
			circle.status = d
		end
	end
end

local function publish()
	local model = circle.model
	if not model then
		return
	end
	local entries: { PartyRules.Entry } = {}
	local starting: PartyRules.Lobby? = nil
	for _, lobby in book.lobbies do
		table.insert(entries, PartyRules.entry(lobby, nameOf))
		if lobby.endsAt and (not starting or lobby.endsAt < (starting.endsAt :: number)) then
			starting = lobby
		end
	end
	if runs then
		for _, run in runs.list() do
			if run.round then
				continue -- (10.6: the quick round has its own line on the map: Runs' attributes on the circle)
			end
			local who: { string } = {}
			for _, p in run.party do
				table.insert(who, p.DisplayName)
			end
			table.insert(entries, { host = run.host.DisplayName, house = run.house, difficulty = run.difficulty, n = #run.party, max = R.MaxParty, friends = false, state = "run",
				who = table.concat(who, ", ") })
		end
	end
	local text = PartyRules.encode(entries)
	if text ~= circle.attribute then
		circle.attribute = text
		model:SetAttribute(PA.Attribute, text)
	end
	local open = #book.lobbies
	local round = if runs then runs.roundOf(nil) else nil -- (10.6: the quick round's next place)
	local upcoming = round and round.phase == "wait" and round.house and round.endsAt
	local line = if starting then `STARTING IN {PartyRules.left(starting, now())} · {string.upper(houseName(starting.house))}`
		elseif upcoming then `QUICK ROUND IN {RunRules.clock(math.max(0, round.endsAt - now()))} · {string.upper(houseName(round.house))}`
		elseif open > 0 then `{open} OPEN LOBB{if open == 1 then "Y" else "IES"} · STEP IN`
		else "STEP IN TO PLAY"
	local color = if starting then PL.Waiting else PL.Free
	local key = `{line}|{color[1]}`
	if key == circle.key then
		return
	end
	circle.key = key
	local c = Color3.fromRGB(color[1], color[2], color[3])
	for _, part in circle.glows do
		part.Color = c
	end
	local status = circle.status
	if status then
		status.Text = line
		status.TextColor3 = c
	end
	model:SetAttribute("PlayState", if starting then "starting" else "free")
end

-- ── The start of a lobby's run ─────────────────────────────────────────────

local function launch(lobby: PartyRules.Lobby)
	local party: { Player } = {}
	local behind: { Player } = {}
	for _, id in lobby.members do
		local p = playerOf(id)
		if p and runs.free(p) then
			table.insert(party, p)
		elseif p then
			table.insert(behind, p)
		end
	end
	local host = playerOf(lobby.host)
	if not host or party[1] ~= host then
		lobby.endsAt = nil
		tell(lobby, `⛔ The run could not start: {nameOf(lobby.host)} can't go right now. Press START again when ready.`)
		return
	end
	local err = runs.begin(lobby.house, party, lobby.difficulty)
	if err then
		lobby.endsAt = nil
		tell(lobby, `⛔ The run could not start: {err}`)
		return
	end
	PartyRules.close(book, lobby.id)
	for _, p in behind do
		say(p, "⏸ You were busy when the run started: it went without you. Step into PLAY for the next one.")
	end
end

-- ── A look ─────────────────────────────────────────────────────────────────

local function inCircleNow(player: Player): boolean
	local root = if runs then runs.free(player) else nil
	if not root then
		return false
	end
	local at = root.Position
	return SandboxMap.inPlay(at.X, at.Z) and at.Y >= SandboxMap.GroundTop - 2 and at.Y <= SandboxMap.GroundTop + PL.Height
end

function Parties.step()
	if not runs then
		return
	end
	for _, player in Players:GetPlayers() do
		if inCircleNow(player) then
			inside[player] = true
		else
			inside[player] = nil
		end
	end
	-- a member gone from the game or in a run some other way (the admin's): out of their lobby
	for _, lobby in table.clone(book.lobbies) do
		for _, id in table.clone(lobby.members) do
			local p = playerOf(id)
			if not p or runs.runOf(p) then
				local left, closed = PartyRules.leave(book, id)
				if left and closed then
					tell(left, `🚪 {nameOf(id)}'s lobby closed.`, id)
				elseif left then
					tell(left, `🚪 {nameOf(id)} left the lobby.`, id)
				end
			end
		end
	end
	local t = now()
	for _, lobby in table.clone(book.lobbies) do
		if PartyRules.due(lobby, t) then
			launch(lobby)
		end
	end
	pushAll()
	publish()
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onRequest(player: Player, message: any)
	if type(message) ~= "table" or not Net.limit(player, "Party", Config.Robust.Limits.Party) or not runs then
		return
	end
	local kind = message.kind
	local id = player.UserId
	local why: string? = nil
	local house: string? = nil
	if kind == "state" then
		sent[player] = nil
	elseif kind == "create" then
		house = if type(message.house) == "string" then message.house else nil
		if not inCircleNow(player) then
			why = "circle"
		elseif runs.queued(player) then
			why = "queued" -- (10.6: the quick round's queue first)
		else
			local lobby, refused = PartyRules.create(book, id, message.house, message.difficulty, message.friends, openOf(player), busy, now())
			why = refused
			if lobby and lobby.friends then
				for _, other in Players:GetPlayers() do
					if other ~= player then
						friendSoon(id, other.UserId) -- (asked now: the list knows who sees it by the next look)
					end
				end
			end
		end
	elseif kind == "join" then
		local lobby = PartyRules.get(book, message.id)
		if not inCircleNow(player) then
			why = "circle"
		elseif not lobby then
			why = "gone"
		elseif runs.queued(player) then
			why = "queued" -- (10.6)
		else
			local friend = lobby.host == id or not lobby.friends or askFriend(lobby.host, id) -- (it may wait: join checks again)
			local joined, refused = PartyRules.join(book, message.id, id, friend, now())
			why = refused
			if joined and refused == nil then
				tell(joined, `👋 {player.DisplayName} joined the lobby.`, id)
			end
		end
	elseif kind == "leave" then
		local lobby, closed = PartyRules.leave(book, id)
		if not lobby then
			why = "notIn"
		elseif closed then
			tell(lobby, `🚪 {player.DisplayName} (the host) closed the lobby.`, id)
		else
			tell(lobby, `🚪 {player.DisplayName} left the lobby.`, id)
		end
	elseif kind == "ready" then
		why = PartyRules.ready(book, id, message.on == true)
	elseif kind == "house" then
		house = if type(message.id) == "string" then message.id else nil
		why = PartyRules.setHouse(book, id, message.id, busy)
	elseif kind == "difficulty" then
		why = PartyRules.setDifficulty(book, id, message.id, openOf(player))
	elseif kind == "kick" then
		local target = tonumber(message.id)
		why = if target then PartyRules.kick(book, id, target, now()) else "notMember"
		if why == nil and target then
			say(playerOf(target), `🚫 {player.DisplayName} took you out of the lobby.`)
		end
	elseif kind == "start" then
		local lobby = PartyRules.lobbyOf(book, id)
		house = if lobby then lobby.house else nil
		if lobby and lobby.host == id and not runs.free(player) then
			why = "busy"
		else
			why = PartyRules.start(book, id, busy, now())
		end
	elseif kind == "cancel" then
		why = PartyRules.cancel(book, id)
	elseif kind == "round" then -- 10.6 the QUICK ROUND: JOIN THE QUEUE (in the circle) / LEAVE THE QUEUE (anywhere)
		if message.on == true and not inCircleNow(player) then
			why = "circle"
		else
			why = runs.queue(player, message.on == true)
			if why == nil then
				local round = runs.roundOf(player)
				say(player, if message.on ~= true then "⚡ You left the QUICK ROUND queue."
					elseif round and round.phase == "play" then "⚡ You are in the QUICK ROUND queue: a round is on, you go in the next one. Walk around while you wait."
					else "⚡ You are in the QUICK ROUND queue: the banner counts down to the next round. Walk around while you wait.")
			end
		end
	else
		return
	end
	if why then
		say(player, `⛔ {PartyRules.why(why, house)}`)
	end
	pushAll()
	publish()
end

-- ── Queries, starting ──────────────────────────────────────────────────────

function Parties.lobbyOf(player: Player): PartyRules.Lobby?
	return PartyRules.lobbyOf(book, player.UserId)
end

function Parties.lobbies(): { PartyRules.Lobby }
	return book.lobbies
end

function Parties.inCircle(player: Player): boolean
	return inside[player] == true
end

function Parties.start(runsModule: any)
	if started then
		return
	end
	started = true
	runs = runsModule
	remote = Net.get("Party")
	findCircle()
	;(remote :: RemoteEvent).OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player: Player)
		local lobby, closed = PartyRules.leave(book, player.UserId)
		if lobby and closed then
			tell(lobby, `🚪 {player.DisplayName}'s lobby closed (they left the game).`)
		elseif lobby then
			tell(lobby, `🚪 {player.DisplayName} left the lobby.`)
		end
		inside[player], sent[player] = nil, nil
	end)
	task.spawn(function()
		while true do
			task.wait(R.Every)
			local ok, err = pcall(Parties.step :: any)
			if not ok then
				warn(`[Parties] {err}`)
			end
		end
	end)
end

return Parties
