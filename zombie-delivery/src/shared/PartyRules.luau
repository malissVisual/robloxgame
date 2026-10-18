--!strict
-- 10.4 PARTY LOBBIES (the owner: "on the map just one circle where you'd stand, like PLAY, and you'd create a lobby";
-- Config.Runs.Party): the rules of the lobbies a party gathers in at the lobby's PLAY circle before a run, pure (no
-- Roblox: tests/partyrules_test.luau). server/Parties.luau keeps them and starts their runs (server/Runs.luau), the PLAY
-- panel shows them (client/PlayUi.luau), the map reads what the server publishes (client/SandboxMapData.luau). 10.6
-- both in PLAY: the lobbies are the PLAY panel's PRIVATE LOBBY beside its QUICK ROUND (server/Runs.luau's rounds): a
-- house is busy (`busy(house)`: server/Runs.luau's Runs.houseBusy, RunRules.houseBusy) while a run is in it ("run" or
-- true) or while it is the quick round's place ("round"); somebody in the round's queue makes or joins no lobby
-- (server/Parties.luau asks first: "queued").
--
-- A lobby: its host (who made it: a user id), a house (a SandboxMap.Houses id: one lobby holds a house at a time, a
-- house in a run is busy), a difficulty (the host's pick, open to the host: RunRules), public or friends only (the
-- host's Roblox friends: the server asks Player:IsFriendsWithAsync and says here who is one), its members (the host
-- first, then in the order they joined; Config.Runs.MaxParty at most), who is READY, and the countdown once the host
-- pressed START (endsAt: Config.Runs.Party.Countdown s). Everybody stays in it wherever they walk: only LEAVE, the
-- host's KICK or leaving the game take you out; the host leaving closes it; it closes when its run starts. START needs
-- the host READY (the others' READY tells the host they are set) and its house out of any run; everybody in it goes.
--   PartyRules.newBook() -> Book                     no lobbies yet
--   PartyRules.lobbyOf(book, user) -> Lobby?         the lobby a user is in (its host or a member)
--   PartyRules.get(book, id) -> Lobby?               a lobby by its id
--   PartyRules.holder(book, house) -> Lobby?         the lobby that holds that house
--   PartyRules.houseState(book, house, busy) -> (state, Lobby?)   "round" (10.6: busy(house) "round": the quick
--                                                    round's place), "run" (busy(house): a run in it), "lobby" (a lobby
--                                                    holds it: that lobby) or "free"
--   PartyRules.busyWhy(busy, house) -> why?          10.6: a busy answer as a why: "round", "run" (true too) or nil
--   PartyRules.create(book, host, house, difficulty, friends, open, busy, now) -> (Lobby?, why?)   a new lobby
--                                                    (`open`: the host's open difficulties' count; a pick not open to
--                                                    them is the hardest open one under it: RunRules.choose)
--   PartyRules.join(book, id, user, friend, now) -> (Lobby?, why?)   `friend`: is `user` the host's friend
--   PartyRules.leave(book, user) -> (Lobby?, closed)  out of their lobby (closed: the host left, the lobby is gone)
--   PartyRules.kick(book, host, user, now) -> why?   the host takes a member out (who cannot come back for Kicked s)
--   PartyRules.ready(book, user, on) -> why?         READY on / off (the host's off calls a countdown off)
--   PartyRules.setHouse(book, host, house, busy) -> why?        the host's other house (not while counting down)
--   PartyRules.setDifficulty(book, host, id, open) -> why?      the host's other difficulty (open to them)
--   PartyRules.canStart(lobby, busy) -> (ok, why?)   START may go (the host READY, its house in no run and not the
--                                                    quick round's, no countdown)
--   PartyRules.start(book, host, busy, now) -> why?  START: the countdown (endsAt)
--   PartyRules.cancel(book, host) -> why?            the countdown called off
--   PartyRules.due(lobby, now) -> bool               the countdown is over: its run now
--   PartyRules.left(lobby, now) -> s                 whole seconds left of the countdown (0: none)
--   PartyRules.close(book, id) -> Lobby?             the lobby gone (its run started)
--   PartyRules.sees(lobby, viewer, friend) -> bool   is it in that viewer's list (public, theirs, or the host's friend)
--   PartyRules.list(book, viewer, friendOf) -> { Lobby }   the lobbies a viewer sees, the oldest first
--   PartyRules.readyCount(lobby) -> n
--   PartyRules.why(code, house?) -> string           a refusal's words (house: its name)
-- The map's copy (the PLAY circle's attribute Config.Runs.Party.Attribute, written by the server only when it changes):
--   PartyRules.entry(lobby, names) -> Entry          a lobby as the map shows it (names(id): a display name)
--   PartyRules.encode(entries) -> string             a short JSON array of flat objects
--   PartyRules.decode(text) -> { Entry }             it back (nil, junk or broken: none)
local Config = require(script.Parent.Config)
local RunRules = require(script.Parent.RunRules)
local SandboxMap = require(script.Parent.SandboxMap)

local PartyRules = {}

local R = Config.Runs
local P = R.Party

export type Lobby = {
	id: number,
	host: number,
	house: string,
	difficulty: string,
	friends: boolean,
	members: { number },
	ready: { [number]: boolean },
	endsAt: number?,
	made: number,
	kicked: { [number]: number },
}
export type Book = { lobbies: { Lobby }, next: number }
-- a house's busy answer (10.6: server/Runs.luau's Runs.houseBusy): nil / false free, "run" / true a run in it, "round"
-- the quick round's place
export type Busy = (string) -> any
-- the map's: host (a display name), house (its id), difficulty (its id), n / max players, friends only, state ("open",
-- "full", "starting": a lobby's; "run": a run in that house now), who (a run's party: names, comma-joined)
export type Entry = { host: string, house: string, difficulty: string, n: number, max: number, friends: boolean, state: string, who: string? }

local WORDS: { [string]: string } = {
	inLobby = "You are in a lobby already: LEAVE it first.",
	house = "No such house.",
	run = "%s is in a run right now: pick another house.",
	round = "%s is the quick round's place right now: pick another house.", -- 10.6
	queued = "You are in the QUICK ROUND queue: LEAVE THE QUEUE first.", -- 10.6
	notQueued = "You are in no queue.",
	inRun = "You are in a run: finish it first.",
	roundOff = "There are no quick rounds right now.",
	taken = "%s is taken by another lobby: pick another house.",
	many = "Too many lobbies right now: join one instead.",
	gone = "That lobby is gone.",
	full = "That lobby is full.",
	friends = "That lobby is for the host's friends only.",
	starting = "That lobby's run is starting: join the next one.",
	kicked = "The host took you out of that lobby: try another one.",
	notIn = "You are in no lobby.",
	notHost = "Only the lobby's host can do that.",
	notMember = "That player is not in your lobby.",
	self = "You can't take yourself out: press LEAVE.",
	locked = "🔒 Finish a run at the difficulty before it to open that one.",
	notReady = "Press READY first: then START.",
	counting = "The run is starting: CANCEL it first.",
	notCounting = "Nothing is starting.",
	circle = "Step into the PLAY circle to make or join a lobby.",
	busy = "Finish what you are doing first.",
}

function PartyRules.why(code: string?, house: string?): string
	local words = WORDS[code or ""] or "That did not work."
	if string.find(words, "%s", 1, true) then
		local h = SandboxMap.house(house)
		return string.format(words, if h then h.name else "That house")
	end
	return words
end

-- ── The book ───────────────────────────────────────────────────────────────

function PartyRules.newBook(): Book
	return { lobbies = {}, next = 1 }
end

function PartyRules.lobbyOf(book: Book, user: number): Lobby?
	for _, lobby in book.lobbies do
		if table.find(lobby.members, user) then
			return lobby
		end
	end
	return nil
end

function PartyRules.get(book: Book, id: any): Lobby?
	for _, lobby in book.lobbies do
		if lobby.id == id then
			return lobby
		end
	end
	return nil
end

function PartyRules.holder(book: Book, house: string): Lobby?
	for _, lobby in book.lobbies do
		if lobby.house == house then
			return lobby
		end
	end
	return nil
end

function PartyRules.busyWhy(busy: Busy, house: string): string?
	local answer = busy(house)
	if answer == "round" then
		return "round"
	elseif answer then
		return "run"
	end
	return nil
end

function PartyRules.houseState(book: Book, house: string, busy: Busy): (string, Lobby?)
	local why = PartyRules.busyWhy(busy, house)
	if why then
		return why, nil
	end
	local lobby = PartyRules.holder(book, house)
	if lobby then
		return "lobby", lobby
	end
	return "free", nil
end

-- Can `house` be this lobby's (`mine`: the lobby asking; nil: a new one)? why or nil.
local function houseFree(book: Book, house: any, busy: Busy, mine: Lobby?): string?
	if type(house) ~= "string" or not SandboxMap.house(house) then
		return "house"
	end
	local why = PartyRules.busyWhy(busy, house)
	if why then
		return why
	end
	local held = PartyRules.holder(book, house)
	if held and held ~= mine then
		return "taken"
	end
	return nil
end

function PartyRules.create(book: Book, host: number, house: any, difficulty: any, friends: any, open: number, busy: Busy, now: number): (Lobby?, string?)
	if PartyRules.lobbyOf(book, host) then
		return nil, "inLobby"
	end
	local why = houseFree(book, house, busy, nil)
	if why then
		return nil, why
	end
	if #book.lobbies >= P.MaxLobbies then
		return nil, "many"
	end
	local lobby: Lobby = {
		id = book.next,
		host = host,
		house = house :: string,
		difficulty = RunRules.choose(open, difficulty),
		friends = friends == true,
		members = { host },
		ready = {},
		endsAt = nil,
		made = now,
		kicked = {},
	}
	book.next += 1
	table.insert(book.lobbies, lobby)
	return lobby, nil
end

function PartyRules.join(book: Book, id: any, user: number, friend: boolean, now: number): (Lobby?, string?)
	local lobby = PartyRules.get(book, id)
	if not lobby then
		return nil, "gone"
	end
	local mine = PartyRules.lobbyOf(book, user)
	if mine == lobby then
		return lobby, nil -- (in it already: nothing to do)
	elseif mine then
		return nil, "inLobby"
	end
	if lobby.endsAt then
		return nil, "starting"
	end
	if #lobby.members >= R.MaxParty then
		return nil, "full"
	end
	if lobby.friends and not friend then
		return nil, "friends"
	end
	local banned = lobby.kicked[user]
	if banned and now < banned then
		return nil, "kicked"
	end
	lobby.kicked[user] = nil
	table.insert(lobby.members, user)
	lobby.ready[user] = nil
	return lobby, nil
end

function PartyRules.close(book: Book, id: number): Lobby?
	for n, lobby in book.lobbies do
		if lobby.id == id then
			table.remove(book.lobbies, n)
			return lobby
		end
	end
	return nil
end

function PartyRules.leave(book: Book, user: number): (Lobby?, boolean)
	local lobby = PartyRules.lobbyOf(book, user)
	if not lobby then
		return nil, false
	end
	if lobby.host == user then
		PartyRules.close(book, lobby.id)
		return lobby, true
	end
	local at = table.find(lobby.members, user)
	if at then
		table.remove(lobby.members, at)
	end
	lobby.ready[user] = nil
	return lobby, false
end

-- The lobby `host` hosts (why: notIn / notHost).
local function hosted(book: Book, host: number): (Lobby?, string?)
	local lobby = PartyRules.lobbyOf(book, host)
	if not lobby then
		return nil, "notIn"
	end
	if lobby.host ~= host then
		return nil, "notHost"
	end
	return lobby, nil
end

function PartyRules.kick(book: Book, host: number, user: any, now: number): string?
	local lobby, why = hosted(book, host)
	if not lobby then
		return why
	end
	if user == host then
		return "self"
	end
	local at = table.find(lobby.members, user)
	if not at then
		return "notMember"
	end
	table.remove(lobby.members, at)
	lobby.ready[user] = nil
	lobby.kicked[user] = now + P.Kicked
	return nil
end

function PartyRules.ready(book: Book, user: number, on: any): string?
	local lobby = PartyRules.lobbyOf(book, user)
	if not lobby then
		return "notIn"
	end
	if on == true then
		lobby.ready[user] = true
	else
		lobby.ready[user] = nil
	end
	if lobby.host == user and on ~= true then
		lobby.endsAt = nil -- (the host not ready: no start)
	end
	return nil
end

function PartyRules.setHouse(book: Book, host: number, house: any, busy: Busy): string?
	local lobby, why = hosted(book, host)
	if not lobby then
		return why
	end
	if lobby.endsAt then
		return "counting"
	end
	why = houseFree(book, house, busy, lobby)
	if why then
		return why
	end
	lobby.house = house :: string
	return nil
end

function PartyRules.setDifficulty(book: Book, host: number, id: any, open: number): string?
	local lobby, why = hosted(book, host)
	if not lobby then
		return why
	end
	if lobby.endsAt then
		return "counting"
	end
	if not RunRules.isOpen(open, id) then
		return "locked"
	end
	lobby.difficulty = RunRules.clean(id)
	return nil
end

function PartyRules.canStart(lobby: Lobby, busy: Busy): (boolean, string?)
	if lobby.endsAt then
		return false, "counting"
	end
	if lobby.ready[lobby.host] ~= true then
		return false, "notReady"
	end
	local why = PartyRules.busyWhy(busy, lobby.house)
	if why then
		return false, why
	end
	return true, nil
end

function PartyRules.start(book: Book, host: number, busy: Busy, now: number): string?
	local lobby, why = hosted(book, host)
	if not lobby then
		return why
	end
	local ok, refused = PartyRules.canStart(lobby, busy)
	if not ok then
		return refused
	end
	lobby.endsAt = now + P.Countdown
	return nil
end

function PartyRules.cancel(book: Book, host: number): string?
	local lobby, why = hosted(book, host)
	if not lobby then
		return why
	end
	if not lobby.endsAt then
		return "notCounting"
	end
	lobby.endsAt = nil
	return nil
end

function PartyRules.due(lobby: Lobby, now: number): boolean
	local at = lobby.endsAt
	return at ~= nil and now >= at
end

function PartyRules.left(lobby: Lobby, now: number): number
	local at = lobby.endsAt
	return if at then math.max(0, math.ceil(at - now)) else 0
end

function PartyRules.readyCount(lobby: Lobby): number
	local n = 0
	for _, id in lobby.members do
		if lobby.ready[id] == true then
			n += 1
		end
	end
	return n
end

function PartyRules.sees(lobby: Lobby, viewer: number, friend: boolean): boolean
	return not lobby.friends or friend or table.find(lobby.members, viewer) ~= nil
end

function PartyRules.list(book: Book, viewer: number, friendOf: (number) -> boolean): { Lobby }
	local out: { Lobby } = {}
	for _, lobby in book.lobbies do
		if PartyRules.sees(lobby, viewer, lobby.host == viewer or friendOf(lobby.host)) then
			table.insert(out, lobby)
		end
	end
	table.sort(out, function(a: Lobby, b: Lobby): boolean
		if a.made ~= b.made then
			return a.made < b.made
		end
		return a.id < b.id
	end)
	return out
end

-- ── The map's copy ─────────────────────────────────────────────────────────

function PartyRules.entry(lobby: Lobby, names: (number) -> string): Entry
	local state = if lobby.endsAt then "starting" elseif #lobby.members >= R.MaxParty then "full" else "open"
	return { host = names(lobby.host), house = lobby.house, difficulty = lobby.difficulty, n = #lobby.members, max = R.MaxParty, friends = lobby.friends, state = state }
end

local function quote(text: string): string
	return '"' .. string.gsub(text, '[%c"\\]', function(ch: string): string
		if ch == '"' then
			return '\\"'
		elseif ch == "\\" then
			return "\\\\"
		end
		return string.format("\\u%04x", string.byte(ch))
	end) .. '"'
end

local KEYS = { "host", "house", "difficulty", "n", "max", "friends", "state", "who" }

function PartyRules.encode(entries: { Entry }): string
	local out: { string } = {}
	for _, e in entries do
		local fields: { string } = {}
		for _, key in KEYS do
			local value = (e :: any)[key]
			local t = type(value)
			if t == "string" then
				table.insert(fields, `"{key}":{quote(value)}`)
			elseif t == "number" and value == value and math.abs(value) < 1e9 then
				table.insert(fields, `"{key}":{math.floor(value + 0.5)}`)
			elseif t == "boolean" then
				table.insert(fields, `"{key}":{if value then "true" else "false"}`)
			end
		end
		table.insert(out, "{" .. table.concat(fields, ",") .. "}")
	end
	return "[" .. table.concat(out, ",") .. "]"
end

-- A small reader of what encode writes (an array of flat objects: strings, whole numbers, true / false): nil on
-- anything else.
local function read(text: string): { { [string]: any } }?
	local at = 1
	local function space()
		at = (string.find(text, "[^ \t\r\n]", at) or #text + 1) :: number
	end
	local function str(): string?
		if string.sub(text, at, at) ~= '"' then
			return nil
		end
		at += 1
		local parts: { string } = {}
		while at <= #text do
			local ch = string.sub(text, at, at)
			if ch == '"' then
				at += 1
				return table.concat(parts)
			elseif ch == "\\" then
				local nxt = string.sub(text, at + 1, at + 1)
				if nxt == "u" then
					local code = tonumber(string.sub(text, at + 2, at + 5), 16)
					if not code then
						return nil
					end
					table.insert(parts, utf8.char(code))
					at += 6
				else
					table.insert(parts, if nxt == "n" then "\n" elseif nxt == "t" then "\t" else nxt)
					at += 2
				end
			else
				table.insert(parts, ch)
				at += 1
			end
		end
		return nil
	end
	local function value(): (boolean, any)
		space()
		local ch = string.sub(text, at, at)
		if ch == '"' then
			local s = str()
			return s ~= nil, s
		elseif string.sub(text, at, at + 3) == "true" then
			at += 4
			return true, true
		elseif string.sub(text, at, at + 4) == "false" then
			at += 5
			return true, false
		end
		local a, b = string.find(text, "^-?%d+%.?%d*", at)
		if a and b then
			at = b + 1
			return true, tonumber(string.sub(text, a, b))
		end
		return false, nil
	end
	space()
	if string.sub(text, at, at) ~= "[" then
		return nil
	end
	at += 1
	local out: { { [string]: any } } = {}
	space()
	if string.sub(text, at, at) == "]" then
		return out
	end
	while true do
		space()
		if string.sub(text, at, at) ~= "{" then
			return nil
		end
		at += 1
		local object: { [string]: any } = {}
		space()
		if string.sub(text, at, at) == "}" then
			at += 1
		else
			while true do
				space()
				local key = str()
				space()
				if not key or string.sub(text, at, at) ~= ":" then
					return nil
				end
				at += 1
				local ok, v = value()
				if not ok then
					return nil
				end
				object[key] = v
				space()
				local ch = string.sub(text, at, at)
				at += 1
				if ch == "}" then
					break
				elseif ch ~= "," then
					return nil
				end
			end
		end
		table.insert(out, object)
		space()
		local ch = string.sub(text, at, at)
		at += 1
		if ch == "]" then
			return out
		elseif ch ~= "," then
			return nil
		end
	end
end

function PartyRules.decode(text: any): { Entry }
	if type(text) ~= "string" or #text > 20000 then
		return {}
	end
	local ok, list = pcall(read, text)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out: { Entry } = {}
	for _, o in list do
		if type(o.house) == "string" and type(o.state) == "string" then
			table.insert(out, {
				host = if type(o.host) == "string" then o.host else "",
				house = o.house,
				difficulty = if type(o.difficulty) == "string" then o.difficulty else R.Default,
				n = if type(o.n) == "number" then o.n else 0,
				max = if type(o.max) == "number" then o.max else R.MaxParty,
				friends = o.friends == true,
				state = o.state,
				who = if type(o.who) == "string" then o.who else nil,
			})
		end
	end
	return out
end

return PartyRules
