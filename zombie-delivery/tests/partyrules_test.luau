-- 10.4 PARTY LOBBIES (shared/PartyRules.luau; Config.Runs.Party): the lobbies a party gathers in at the lobby's PLAY
-- circle before a run, pure: making one (a house, a difficulty open to the host, public or friends only; a house in a
-- run or held by another lobby refused, too many lobbies refused), joining (full, friends only, starting, kicked, in
-- another lobby), leaving (the host's closes it), KICK, READY, the host's house and difficulty, START (the host READY,
-- the house in no run), the countdown, CANCEL, who sees what, and the map's copy (encode / decode).
-- Run with tests/run_tests.py.
local Config = require("./Config")
local PartyRules = require("./PartyRules")
local SandboxMap = require("./SandboxMap")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local R = Config.Runs
local P = R.Party
local ANN, BOB, CID, DEE, EVE = 11, 22, 33, 44, 55
local runs: { [string]: boolean } = {}
local function busy(house: string): boolean
	return runs[house] == true
end

do
	check("Config.Runs.Party: a 5 s countdown, at most 6 lobbies, 4 players a lobby, a kicked player kept out a while, the map's attribute",
		P.Countdown == 5 and P.MaxLobbies == 6 and R.MaxParty == 4 and P.Kicked > 0 and P.Friends > 0 and P.Attribute == "RunLobbies")
	check("Config.Runs.Play: the circle's radius the lobby's (SandboxMap.Lobby.play.r), its glow's colours", R.Play.Radius == SandboxMap.Lobby.play.r
		and #R.Play.Free == 3 and #R.Play.Waiting == 3 and R.Play.Height > 0)
	local cards = true
	for _, h in SandboxMap.Houses do
		local c = R.Houses[h.id]
		cards = cards and c ~= nil and #c.icon > 0 and #c.line > 10 and #c.line <= 48 and #c.wall == 3 and #c.roof == 3
	end
	check("Config.Runs.Houses: a card for each of the six houses (an icon, a short line, its colours)", cards)
	check("Config.Robust.Limits.Party: the Party remote's rate limit", Config.Robust.Limits.Party ~= nil and Config.Robust.Limits.Party > 0)
end

-- ── Making one ─────────────────────────────────────────────────────────────

local book = PartyRules.newBook()
do
	local lobby, why = PartyRules.create(book, ANN, "old_mill", "normal", false, R.Open, busy, 100)
	check("Ann makes a lobby: The Old Mill at Normal, public, she its host and first member, nobody READY, no countdown", lobby ~= nil and why == nil
		and lobby.host == ANN and lobby.house == "old_mill" and lobby.difficulty == "normal" and lobby.friends == false and #lobby.members == 1
		and lobby.members[1] == ANN and PartyRules.readyCount(lobby) == 0 and lobby.endsAt == nil and lobby.made == 100)
	check("…PartyRules.lobbyOf / get / holder find it", PartyRules.lobbyOf(book, ANN) == lobby and PartyRules.get(book, (lobby :: any).id) == lobby
		and PartyRules.holder(book, "old_mill") == lobby and PartyRules.lobbyOf(book, BOB) == nil and PartyRules.get(book, 999) == nil)
	local again, why2 = PartyRules.create(book, ANN, "pond_cabin", "normal", false, R.Open, busy, 101)
	check("NEG. a second lobby of hers: refused (in a lobby already)", again == nil and why2 == "inLobby" and #book.lobbies == 1)
	local taken, why3 = PartyRules.create(book, BOB, "old_mill", "easy", false, R.Open, busy, 102)
	check("NEG. Bob's lobby on The Old Mill: taken by Ann's lobby (its words name the house)", taken == nil and why3 == "taken"
		and PartyRules.why(why3, "old_mill") == "The Old Mill is taken by another lobby: pick another house.")
	runs.lone_house = true
	local inRun, why4 = PartyRules.create(book, BOB, "lone_house", "easy", false, R.Open, busy, 103)
	check("NEG. …on The Lone House while a run is in it: refused (in a run)", inRun == nil and why4 == "run"
		and string.find(PartyRules.why(why4, "lone_house"), "in a run", 1, true) ~= nil)
	local nowhere, why5 = PartyRules.create(book, BOB, "the_moon", "easy", false, R.Open, busy, 103)
	check("NEG. …on no such house: refused", nowhere == nil and why5 == "house")
	check("houseState: the mill held by Ann's lobby, the lone house in a run, the cabin free", PartyRules.houseState(book, "old_mill", busy) == "lobby"
		and select(2, PartyRules.houseState(book, "old_mill", busy)) == lobby and PartyRules.houseState(book, "lone_house", busy) == "run"
		and PartyRules.houseState(book, "pond_cabin", busy) == "free")
	local hard, _ = PartyRules.create(book, BOB, "pond_cabin", "nightmare", true, R.Open, busy, 104)
	check("Bob's lobby: The Pond Cabin, friends only; Nightmare not open to him: the hardest open one (Normal)", hard ~= nil and hard.difficulty == "normal"
		and hard.friends == true and #book.lobbies == 2)
end

-- ── Joining, leaving, kicking ──────────────────────────────────────────────

local ann = PartyRules.lobbyOf(book, ANN) :: PartyRules.Lobby
local bob = PartyRules.lobbyOf(book, BOB) :: PartyRules.Lobby
do
	local joined, why = PartyRules.join(book, ann.id, CID, false, 110)
	check("Cid joins Ann's (public) lobby: a member after her, not READY", joined == ann and why == nil and ann.members[2] == CID and ann.ready[CID] == nil)
	check("…joining it again: nothing changes", PartyRules.join(book, ann.id, CID, false, 111) == ann and #ann.members == 2)
	local other, why2 = PartyRules.join(book, bob.id, CID, true, 112)
	check("NEG. …Bob's lobby while in Ann's: refused (LEAVE first)", other == nil and why2 == "inLobby")
	local stranger, why3 = PartyRules.join(book, bob.id, DEE, false, 112)
	check("NEG. Dee (not Bob's friend) into Bob's friends-only lobby: refused", stranger == nil and why3 == "friends"
		and PartyRules.why(why3) == "That lobby is for the host's friends only.")
	local friend = PartyRules.join(book, bob.id, DEE, true, 113)
	check("…Dee as Bob's friend: in", friend == bob and bob.members[2] == DEE)
	check("NEG. a lobby that is gone: refused", select(2, PartyRules.join(book, 999, EVE, true, 113)) == "gone")
	-- full: Ann's lobby takes four
	PartyRules.join(book, ann.id, EVE, false, 114)
	PartyRules.join(book, ann.id, 66, false, 114)
	local full, why4 = PartyRules.join(book, ann.id, 77, false, 115)
	check("Ann's lobby of four (Ann, Cid, Eve, 66); NEG. a fifth: refused (full)", #ann.members == 4 and full == nil and why4 == "full")
	check("…the map's copy says full", PartyRules.entry(ann, tostring).state == "full" and PartyRules.entry(ann, tostring).n == 4)
	-- kick
	check("NEG. Cid (not the host) kicks Eve: refused", PartyRules.kick(book, CID, EVE, 116) == "notHost" and #ann.members == 4)
	check("NEG. Ann kicks herself: refused (LEAVE instead)", PartyRules.kick(book, ANN, ANN, 116) == "self")
	check("NEG. Ann kicks Dee (Bob's): refused (not in her lobby)", PartyRules.kick(book, ANN, DEE, 116) == "notMember")
	PartyRules.ready(book, 66, true)
	check("Ann kicks 66 (READY): out, the READY gone", PartyRules.kick(book, ANN, 66, 116) == nil and table.find(ann.members, 66) == nil and ann.ready[66] == nil)
	local back, why5 = PartyRules.join(book, ann.id, 66, false, 116 + P.Kicked - 1)
	check("NEG. …66 back before Kicked s: refused", back == nil and why5 == "kicked")
	check("…after Kicked s: in again", PartyRules.join(book, ann.id, 66, false, 116 + P.Kicked) == ann and table.find(ann.members, 66) ~= nil)
	-- leave
	local left, closed = PartyRules.leave(book, 66)
	check("66 LEAVEs: out of Ann's lobby, the lobby stays", left == ann and closed == false and table.find(ann.members, 66) == nil and PartyRules.get(book, ann.id) == ann)
	check("NEG. leaving with no lobby: nothing", PartyRules.leave(book, 66) == nil)
end

-- ── READY, the host's choices, START ───────────────────────────────────────

do
	check("NEG. Cid picks the house: refused (the host's)", PartyRules.setHouse(book, CID, "orchard_cottage", busy) == "notHost")
	check("NEG. Ann picks The Pond Cabin (Bob's lobby holds it): refused", PartyRules.setHouse(book, ANN, "pond_cabin", busy) == "taken" and ann.house == "old_mill")
	check("NEG. …The Lone House (in a run): refused", PartyRules.setHouse(book, ANN, "lone_house", busy) == "run")
	check("Ann picks The Orchard Cottage: hers now, the mill free again", PartyRules.setHouse(book, ANN, "orchard_cottage", busy) == nil and ann.house == "orchard_cottage"
		and PartyRules.holder(book, "old_mill") == nil)
	check("…her own house again: fine", PartyRules.setHouse(book, ANN, "orchard_cottage", busy) == nil)
	check("NEG. Ann picks Hard (not open: Easy and Normal): refused, told how to open it", PartyRules.setDifficulty(book, ANN, "hard", R.Open) == "locked"
		and ann.difficulty == "normal" and string.find(PartyRules.why("locked"), "Finish a run", 1, true) ~= nil)
	check("…Easy: hers", PartyRules.setDifficulty(book, ANN, "easy", R.Open) == nil and ann.difficulty == "easy")
	check("…Hard once she opened it (3 open)", PartyRules.setDifficulty(book, ANN, "hard", 3) == nil and ann.difficulty == "hard")
	check("NEG. Cid picks the difficulty: refused", PartyRules.setDifficulty(book, CID, "easy", R.Open) == "notHost")
	-- START
	check("NEG. START with Ann not READY: refused", PartyRules.start(book, ANN, busy, 200) == "notReady" and ann.endsAt == nil
		and select(2, PartyRules.canStart(ann, busy)) == "notReady")
	PartyRules.ready(book, CID, true)
	check("Cid READY: one of three ready", ann.ready[CID] == true and PartyRules.readyCount(ann) == 1)
	check("NEG. Cid presses START: refused (the host's)", PartyRules.start(book, CID, busy, 200) == "notHost")
	PartyRules.ready(book, ANN, true)
	check("Ann READY (Eve not: the host's READY is enough): START may go", PartyRules.readyCount(ann) == 2 and (PartyRules.canStart(ann, busy)))
	runs.orchard_cottage = true
	check("NEG. …but a run took her house meanwhile (the admin's): START refused", PartyRules.start(book, ANN, busy, 200) == "run")
	runs.orchard_cottage = nil
	check("START: the countdown (Countdown s)", PartyRules.start(book, ANN, busy, 200) == nil and ann.endsAt == 200 + P.Countdown
		and PartyRules.left(ann, 200) == P.Countdown and PartyRules.left(ann, 202.5) == P.Countdown - 2 and not PartyRules.due(ann, 204.9))
	check("…the map's copy says starting", PartyRules.entry(ann, tostring).state == "starting")
	check("NEG. START again: refused (counting already)", PartyRules.start(book, ANN, busy, 201) == "counting")
	check("NEG. a new house or difficulty while it counts: refused", PartyRules.setHouse(book, ANN, "old_mill", busy) == "counting"
		and PartyRules.setDifficulty(book, ANN, "easy", 3) == "counting")
	local late, why = PartyRules.join(book, ann.id, 88, false, 201)
	check("NEG. joining while it counts: refused (starting)", late == nil and why == "starting")
	check("CANCEL: no countdown", PartyRules.cancel(book, ANN) == nil and ann.endsAt == nil and PartyRules.left(ann, 201) == 0)
	check("NEG. CANCEL with nothing starting; Cid's CANCEL", PartyRules.cancel(book, ANN) == "notCounting" and PartyRules.cancel(book, CID) == "notHost")
	PartyRules.start(book, ANN, busy, 300)
	PartyRules.ready(book, ANN, false)
	check("the host's READY off calls the countdown off", ann.endsAt == nil and ann.ready[ANN] == nil)
	PartyRules.ready(book, ANN, true)
	PartyRules.start(book, ANN, busy, 400)
	PartyRules.ready(book, CID, false)
	check("…a member's READY off does not", ann.endsAt == 400 + P.Countdown)
	check("the countdown over: due", PartyRules.due(ann, 400 + P.Countdown) and PartyRules.left(ann, 400 + P.Countdown) == 0)
	check("NEG. READY with no lobby: refused", PartyRules.ready(book, 999, true) == "notIn")
end

-- ── Who sees what ──────────────────────────────────────────────────────────

do
	local friends: { [number]: { [number]: boolean } } = { [BOB] = { [EVE] = true } }
	local function friendOf(viewer: number): (number) -> boolean
		return function(host: number): boolean
			return friends[host] ~= nil and friends[host][viewer] == true
		end
	end
	local function ids(list: { PartyRules.Lobby }): string
		local out = {}
		for _, l in list do
			table.insert(out, tostring(l.host))
		end
		return table.concat(out, ",")
	end
	check("a stranger (77) sees Ann's public lobby only (Bob's is friends only)", ids(PartyRules.list(book, 77, friendOf(77))) == tostring(ANN))
	check("…Bob's friend (Eve) sees both, the oldest first", ids(PartyRules.list(book, EVE, friendOf(EVE))) == `{ANN},{BOB}`)
	check("…Dee (in Bob's lobby) and Bob himself see his", string.find(ids(PartyRules.list(book, DEE, friendOf(DEE))), tostring(BOB), 1, true) ~= nil
		and string.find(ids(PartyRules.list(book, BOB, friendOf(BOB))), tostring(BOB), 1, true) ~= nil)
end

-- ── The host leaves; too many lobbies; the run starts ──────────────────────

do
	local left, closed = PartyRules.leave(book, BOB)
	check("Bob (the host) leaves: his lobby closes (Dee in no lobby now), the cabin free", left ~= nil and closed and PartyRules.lobbyOf(book, DEE) == nil
		and PartyRules.holder(book, "pond_cabin") == nil and #book.lobbies == 1)
	check("the run starts: PartyRules.close takes the lobby away", PartyRules.close(book, ann.id) == ann and #book.lobbies == 0 and PartyRules.lobbyOf(book, ANN) == nil)
	local many = PartyRules.newBook()
	local made = 0
	for n, h in SandboxMap.Houses do
		if PartyRules.create(many, 100 + n, h.id, "easy", false, R.Open, function(): boolean
			return false
		end, n) then
			made += 1
		end
	end
	check(`six houses, six lobbies (MaxLobbies {P.MaxLobbies}); the ids count up`, made == 6 and many.lobbies[6].id == 6)
	local seventh, why = PartyRules.create(many, 200, "old_mill", "easy", false, R.Open, function(): boolean
		return false
	end, 9)
	check("NEG. a seventh: refused (every house is held, or too many)", seventh == nil and (why == "taken" or why == "many"))
end

-- ── The map's copy ─────────────────────────────────────────────────────────

do
	local entries: { PartyRules.Entry } = {
		{ host = "Ann", house = "old_mill", difficulty = "hard", n = 2, max = 4, friends = false, state = "open" },
		{ host = 'Bo "the" \\Mover\n', house = "pond_cabin", difficulty = "normal", n = 4, max = 4, friends = true, state = "full" },
		{ host = "Cid", house = "lone_house", difficulty = "nightmare", n = 3, max = 4, friends = false, state = "run", who = "Cid, Dee, Eve" },
		{ host = "Žofie ✓", house = "forest_lodge", difficulty = "easy", n = 1, max = 4, friends = false, state = "starting" },
	}
	local text = PartyRules.encode(entries)
	check("encode: a JSON array of flat objects", string.sub(text, 1, 2) == "[{" and string.sub(text, -2) == "}]" and string.find(text, '"house":"old_mill"', 1, true) ~= nil
		and string.find(text, '"friends":true', 1, true) ~= nil, text)
	local back = PartyRules.decode(text)
	local same = #back == #entries
	for n, e in entries do
		local b = back[n]
		same = same and b ~= nil and b.host == e.host and b.house == e.house and b.difficulty == e.difficulty and b.n == e.n and b.max == e.max
			and b.friends == e.friends and b.state == e.state and b.who == e.who
	end
	check("decode: every entry back as it was (quotes, a backslash, a new line, letters outside ASCII)", same)
	check("decode: none from nil, junk, a broken array, an empty one", #PartyRules.decode(nil) == 0 and #PartyRules.decode("nonsense") == 0
		and #PartyRules.decode('[{"house":"x"') == 0 and #PartyRules.decode("[]") == 0 and #PartyRules.decode(5) == 0)
	check("decode: an entry without a house or a state dropped", #PartyRules.decode('[{"host":"Ann"},{"house":"old_mill","state":"open"}]') == 1)
	check("encode of nothing: []", PartyRules.encode({}) == "[]")
	local lobby = (PartyRules.create(PartyRules.newBook(), ANN, "old_mill", "easy", true, R.Open, busy, 1)) :: PartyRules.Lobby
	local e = PartyRules.entry(lobby, function(id: number): string
		return if id == ANN then "Ann" else "?"
	end)
	check("entry: the host's name, the house, the difficulty, 1/4, friends only, open", e.host == "Ann" and e.house == "old_mill" and e.difficulty == "easy"
		and e.n == 1 and e.max == R.MaxParty and e.friends and e.state == "open")
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
