-- 10.4 PARTY LOBBIES at the lobby's PLAY circle (the owner: "on the map just one circle where you'd stand, like PLAY,
-- and you'd create a lobby"), on the real boot: tests/runtime/SandboxE2E.luau's stand-in with the REAL
-- server/SandboxBoot.luau, server/LobbyWorld.luau (the circle), server/Parties.luau (the lobbies), server/Runs.luau and
-- server/Moving.luau (the run) and the rest of the sandbox (E2E<Name>.luau through tests/run_tests.py); the clock the
-- test's. Checked:
--   * the circle: who stands in it gets the PLAY view (the six houses, the difficulties open to them), whoever is away
--     and in no lobby nothing; a lobby made or joined away from it is refused;
--   * a friends-only lobby (Player:IsFriendsWithAsync, here Parties.friendsWith): listed to the host's friend and joined
--     by him, not listed to a stranger and his JOIN refused; the map's attribute (PartyRules.decode) has it;
--   * walking away keeps you in it (the lobby's view wherever you are, circle false); READY from away; the host's START
--     refused before the host is READY; START, CANCEL, START; a house held by a lobby refused to another lobby;
--   * the countdown (Party.Countdown s): the run with both (the friend from his warehouse), the host's helper with it
--     (Danny: the crew comes along), the lobby gone, the map's attribute a run, the house IN A RUN in the PLAY view;
--     FINISH: the results card, back beside the PLAY circle (its way back, apart, facing it, none in it);
--   * four at most (a fifth refused), KICK (out, and kept out Party.Kicked s), the host's LEAVE closes it, the host
--     leaving the game closes it; a member dead at the start stays behind (told), the run goes without him; a member
--     taken into a run by the admin is out of his lobby; a lobby's START on a house the admin's run took is refused;
--   * no script error, no warning.
-- Run: python3 tests/run_tests.py [path to the luau binary]
math.randomseed(1004)

local E = require("./SandboxE2E")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local PartyRules = require("./PartyRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local V3 = E.Mock.Vector3.new
local workspace = E.workspace
local R = Config.Runs
local L = SandboxMap.Lobby
local T: any = {} -- the test's helpers (one register)

Config.Visitors.On = false -- (the showroom's visitors: tests/visitors_runtime_test.luau's)
for _, level in R.Danger do -- (the hazards: tests/danger_runtime_test.luau's; none on these walks)
	level.Creak, level.Puddle, level.Plaster = 0, 0, 0
end

local Boot = E.module("SandboxBoot")
local Runs = E.module("Runs")
local Parties = E.module("Parties")
local MoveHelper = E.module("MoveHelper")
local Vehicles = E.fakes.Vehicles
MoveHelper.useMover(E.mover) -- (no pathfinding in the CLI: Danny walks straight)
Boot.start(function() end)
E.advance(1)

function T.at(x: number, z: number): any
	return V3(x, E.groundY(x, z) + 3, z)
end
-- the n-th of a few spots round the circle's middle, 3 studs apart
function T.circle(n: number): any
	local k = n - 1
	return T.at(L.play.x + (k % 3 - 1) * 3, L.play.z + (k // 3 - 1) * 3)
end
function T.flat(a: any, b: any): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end
function T.view(player: any, from: number?): any
	return E.lastKind(player, "Party", "play", from)
end
-- a request on the Party remote, then a moment (its rate limit; the loop's look)
function T.ask(player: any, message: any)
	E.fire(player, "Party", message)
	E.advance(0.25)
end
function T.attr(): { PartyRules.Entry }
	local circle = workspace:FindFirstChild("Sandbox"):FindFirstChild("Lobby"):FindFirstChild("PlayCircle")
	return PartyRules.decode(circle and circle:GetAttribute(R.Party.Attribute))
end
function T.sign(): string
	local circle = workspace:FindFirstChild("Sandbox"):FindFirstChild("Lobby"):FindFirstChild("PlayCircle")
	local status = circle and circle:FindFirstChild("Status", true)
	return if status then status.Text else ""
end
function T.house(view: any, id: string): any
	for _, h in (if view then view.houses else {}) do
		if h.id == id then
			return h
		end
	end
	return nil
end
function T.waitRun(player: any): boolean
	local ok = E.waitUntil(function(): boolean
		return Runs.runOf(player) ~= nil
	end, R.Party.Countdown + 1)
	E.advance(R.Fade.Out + 0.3)
	return ok
end
function T.home()
	E.advance(R.EndHold + R.Fade.Out + 0.5)
end

local ann = E.join(11, "Ann")
local bob = E.join(22, "Bob")
local cid = E.join(33, "Cid")
E.advance(1)
local lone = SandboxMap.house("lone_house") :: SandboxMap.House

-- ── The circle ─────────────────────────────────────────────────────────────

do
	check("the boot: the PLAY circle's sign STEP IN TO PLAY, the map's attribute no lobby", T.sign() == "STEP IN TO PLAY" and #T.attr() == 0)
	local at = #E.sent
	T.ask(ann, { kind = "create", house = lone.id, difficulty = "normal", friends = true })
	check("NEG. a lobby made at the spawn (not in the circle): refused, told to step in", Parties.lobbyOf(ann) == nil and E.heard(ann, "Step into the PLAY circle", at))
	-- Bob is Ann's Roblox friend, Cid is nobody's (Player:IsFriendsWithAsync's stand-in)
	Parties.friendsWith = function(host: any, id: number): boolean
		return host == ann and id == bob.UserId
	end
	at = #E.sent
	E.walk(ann, T.circle(1))
	E.advance(R.Every + 0.05)
	local view = T.view(ann, at)
	check("Ann into the circle: the PLAY view (circle; the six houses; Easy and Normal open to her; no lobby)", view ~= nil and view.circle == true and #view.houses == 6
		and table.concat(view.open, ",") == "easy,normal" and view.lobby == nil and Parties.inCircle(ann) and T.view(bob, at) == nil)
	T.ask(ann, { kind = "create", house = lone.id, difficulty = "normal", friends = true })
	local lobby = Parties.lobbyOf(ann) :: any
	view = T.view(ann)
	check("CREATE A LOBBY: The Lone House, Normal, FRIENDS ONLY; her panel the lobby's (hers, 1/4)", lobby ~= nil and lobby.house == lone.id and lobby.friends == true
		and view.lobby ~= nil and view.lobby.mine == true and view.lobby.friends == true and #view.lobby.members == 1)
	local entries = T.attr()
	check("…the map's attribute: Ann · the lone house · Normal · 1/4 · friends only · open; the sign 1 OPEN LOBBY", #entries == 1 and entries[1].host == "Ann"
		and entries[1].house == lone.id and entries[1].n == 1 and entries[1].friends == true and entries[1].state == "open" and T.sign() == "1 OPEN LOBBY · STEP IN", T.sign())
	-- Cid (a stranger) and Bob (her friend) step in
	at = #E.sent
	E.walk(cid, T.circle(2))
	E.walk(bob, T.circle(3))
	E.advance(R.Every * 2 + 0.05)
	local cidView, bobView = T.view(cid), T.view(bob)
	check("a friends-only lobby: listed to her friend Bob, not to Cid", cidView ~= nil and #cidView.lobbies == 0 and bobView ~= nil and #bobView.lobbies == 1
		and bobView.lobbies[1].hostName == "Ann" and bobView.lobbies[1].friends == true, cidView and #cidView.lobbies)
	T.ask(cid, { kind = "join", id = lobby.id })
	check("NEG. …Cid's JOIN (he knows its id): refused (friends only)", Parties.lobbyOf(cid) == nil and E.heard(cid, "friends only", at))
	T.ask(bob, { kind = "join", id = lobby.id })
	check("…Bob JOINs: in (2/2 … 2/4), Ann told", Parties.lobbyOf(bob) == lobby and #lobby.members == 2 and E.heard(ann, "Bob joined the lobby", at))
	T.ask(cid, { kind = "create", house = lone.id, difficulty = "normal", friends = false })
	check("NEG. Cid's lobby on The Lone House: taken by Ann's lobby (told)", Parties.lobbyOf(cid) == nil and E.heard(cid, "The Lone House is taken", at))
end

-- ── Walking away, READY, START, CANCEL ─────────────────────────────────────

do
	local lobby = Parties.lobbyOf(ann) :: any
	local plot = SandboxMap.Plots[bob:GetAttribute("Plot") or 2]
	E.walk(bob, T.at(plot.door.x, plot.door.z + 6))
	E.advance(R.Every + 0.05)
	local away = T.view(bob)
	check("Bob walks to his warehouse: still in the lobby, its view wherever he is (circle false)", Parties.lobbyOf(bob) == lobby and away ~= nil and away.circle == false
		and away.lobby ~= nil and away.lobby.hostName == "Ann" and not Parties.inCircle(bob))
	T.ask(bob, { kind = "ready", on = true })
	local at = #E.sent
	T.ask(ann, { kind = "start" })
	check("Bob READY from there; NEG. Ann's START before she is READY: refused", lobby.ready[bob.UserId] == true and lobby.endsAt == nil and E.heard(ann, "Press READY", at))
	T.ask(ann, { kind = "ready", on = true })
	T.ask(ann, { kind = "start" })
	check("Ann READY, START: the countdown (Party.Countdown s), the sign STARTING IN … · THE LONE HOUSE", lobby.endsAt ~= nil
		and lobby.endsAt - E.now <= R.Party.Countdown and string.find(T.sign(), "STARTING IN", 1, true) == 1 and string.find(T.sign(), "THE LONE HOUSE", 1, true) ~= nil,
		T.sign())
	T.ask(ann, { kind = "cancel" })
	check("CANCEL: no countdown, the sign as before", lobby.endsAt == nil and T.sign() == "1 OPEN LOBBY · STEP IN")
	T.ask(ann, { kind = "start" })
	local started = T.waitRun(ann)
	local run = Runs.runOf(ann)
	local zone = SandboxMap.zone(lone.id) :: SandboxMap.Zone
	local inZone = true
	for _, p in { ann, bob } do
		local where = E.rootOf(p).Position
		inZone = inZone and SandboxMap.zoneAt(where.X, where.Z) == zone
	end
	check("START again: Party.Countdown s later the run: Ann the host, Bob with her (from his warehouse), both in the lone house's front yard; the lobby gone",
		started and run ~= nil and run.house == lone.id and run.difficulty == "normal" and #run.party == 2 and run.host == ann and inZone and #Parties.lobbies() == 0)
	check("…her truck at its curb; the crew comes along (her helper, Danny)", Vehicles.get(ann) ~= nil and MoveHelper.find(ann) ~= nil and MoveHelper.find(ann).hirer == ann)
	E.advance(R.Every + 0.05)
	local entries = T.attr()
	local cidView = T.view(cid)
	check("…the map's attribute: the run (the lone house, Ann, Bob); Cid's PLAY view: the lone house IN A RUN (Ann's)", #entries == 1 and entries[1].state == "run"
		and entries[1].who == "Ann, Bob" and T.house(cidView, lone.id) ~= nil and T.house(cidView, lone.id).state == "run" and T.house(cidView, lone.id).by == "Ann"
		and T.sign() == "STEP IN TO PLAY", entries[1] and entries[1].who)
	local at = #E.sent
	Runs.finish(ann)
	E.advance(0.5)
	local card = E.lastKind(bob, "Runs", "result", at)
	check("FINISH (the host's): the run over, a results card for both", Runs.runOf(ann) == nil and Runs.runOf(bob) == nil and card ~= nil and E.lastKind(ann, "Runs", "result", at) ~= nil)
	T.home()
	local back = L.play.back
	local home = true
	for _, p in { ann, bob } do
		local where = E.rootOf(p).Position
		home = home and not SandboxMap.inPlay(where.X, where.Z, 1) and T.flat(where, V3(back.x, 0, back.z)) <= R.Apart + 0.5 and SandboxMap.inLobby(where.X, where.Z)
			and E.rootOf(p).CFrame.LookVector.Z < -0.99
	end
	check("…EndHold s later: both back beside the PLAY circle (its way back, apart, facing it, none in it), the truck gone, the lone house free", home
		and Vehicles.get(ann) == nil and not Runs.inUse(lone.id) and #T.attr() == 0)
end

-- ── Four at most, KICK, the host's LEAVE, the host leaving the game ────────

local dee = E.join(44, "Dee")
local eve = E.join(55, "Eve")
E.advance(4) -- (SandboxBoot's wait for a plot: Eve, the fifth, none)
do
	local mill = SandboxMap.house("old_mill") :: SandboxMap.House
	for n, p in { cid, ann, bob, dee, eve } do
		E.walk(p, T.circle(n))
	end
	E.advance(R.Every + 0.05)
	local at = #E.sent
	T.ask(cid, { kind = "create", house = mill.id, difficulty = "easy", friends = false })
	local lobby = Parties.lobbyOf(cid) :: any
	for _, p in { ann, bob, dee } do
		T.ask(p, { kind = "join", id = lobby.id })
	end
	T.ask(eve, { kind = "join", id = lobby.id })
	check("Cid's public lobby: Ann, Bob and Dee JOIN (4/4); NEG. Eve, the fifth: refused (full)", #lobby.members == R.MaxParty and Parties.lobbyOf(eve) == nil
		and E.heard(eve, "That lobby is full", at) and T.attr()[1].state == "full")
	T.ask(cid, { kind = "kick", id = dee.UserId })
	T.ask(dee, { kind = "join", id = lobby.id })
	check("KICK: Dee out (told); NEG. his JOIN again: refused for Party.Kicked s", Parties.lobbyOf(dee) == nil and E.heard(dee, "took you out of the lobby", at)
		and E.heard(dee, "The host took you out of that lobby", at))
	T.ask(eve, { kind = "join", id = lobby.id })
	check("…Eve JOINs in his place (4/4)", Parties.lobbyOf(eve) == lobby and #lobby.members == 4)
	E.advance(R.Party.Kicked)
	T.ask(dee, { kind = "create", house = SandboxMap.House.id, difficulty = "normal", friends = false })
	check("(Dee makes his own lobby on the farmstead meanwhile)", Parties.lobbyOf(dee) ~= nil and #Parties.lobbies() == 2)
	at = #E.sent
	T.ask(eve, { kind = "leave" })
	check("Eve LEAVEs: out, the lobby stays (Cid told)", Parties.lobbyOf(eve) == nil and Parties.lobbyOf(cid) == lobby and E.heard(cid, "Eve left the lobby", at))
	T.ask(cid, { kind = "leave" })
	check("Cid (the host) LEAVEs: his lobby closed, Ann and Bob in none (told)", Parties.lobbyOf(ann) == nil and Parties.lobbyOf(bob) == nil
		and E.heard(ann, "Cid (the host) closed the lobby", at) and #Parties.lobbies() == 1)
	T.ask(bob, { kind = "join", id = Parties.lobbyOf(dee).id })
	at = #E.sent
	E.leave(dee)
	E.advance(R.Every + 0.05)
	check("Dee (a host) leaves the game: his lobby closed, Bob in none (told)", Parties.lobbyOf(bob) == nil and #Parties.lobbies() == 0 and E.heard(bob, "Dee's lobby closed", at))
end

-- ── A member dead at the start; the admin's runs ───────────────────────────

do
	local cabin = SandboxMap.house("pond_cabin") :: SandboxMap.House
	for n, p in { bob, cid } do
		E.walk(p, T.circle(n))
	end
	E.advance(R.Every + 0.05)
	T.ask(bob, { kind = "create", house = cabin.id, difficulty = "normal", friends = false })
	T.ask(cid, { kind = "join", id = Parties.lobbyOf(bob).id })
	T.ask(bob, { kind = "ready", on = true })
	T.ask(bob, { kind = "start" })
	local at = #E.sent
	local humanoid = cid.Character:FindFirstChildOfClass("Humanoid")
	humanoid.Health = 0
	local started = T.waitRun(bob)
	check("a member dead when the countdown ends: the run goes without him (told), the host's run alone", started and #Runs.runOf(bob).party == 1
		and Runs.runOf(cid) == nil and E.heard(cid, "it went without you", at))
	Runs.finish(bob)
	T.home()
	E.spawn(cid, T.at(L.spawn.x, L.spawn.z))
	E.advance(1)
	-- the admin's run takes a member out of his lobby; another lobby's START on a house the admin's run holds: refused
	for n, p in { cid, ann } do
		E.walk(p, T.circle(n))
	end
	E.advance(R.Every + 0.05)
	T.ask(cid, { kind = "create", house = SandboxMap.House.id, difficulty = "normal", friends = false })
	T.ask(ann, { kind = "join", id = Parties.lobbyOf(cid).id })
	local said = Runs.admin(ann, "start", "orchard_cottage", ann)
	E.advance(R.Fade.Out + R.Every + 0.5)
	check("the admin's run for Ann (the orchard): she is out of Cid's lobby (Cid told)", string.find(said, "started", 1, true) ~= nil and Runs.runOf(ann) ~= nil
		and Parties.lobbyOf(ann) == nil and #Parties.lobbyOf(cid).members == 1, said)
	Runs.admin(ann, "end")
	T.home()
	E.advance(1)
	local farmRun = Runs.admin(bob, "start", SandboxMap.House.id, bob)
	E.advance(R.Fade.Out + 0.5)
	at = #E.sent
	T.ask(cid, { kind = "ready", on = true })
	T.ask(cid, { kind = "start" })
	check("NEG. the admin's run in the farmstead (Bob's): Cid's lobby's START there refused (in a run), no countdown", string.find(farmRun, "started", 1, true) ~= nil
		and Parties.lobbyOf(cid).endsAt == nil and E.heard(cid, "The Old Farmstead is in a run", at), farmRun)
	Runs.admin(bob, "end")
	T.home()
end

do
	check("no script error in any thread (E.errors)", #E.errors == 0, table.concat(E.errors, "\n"))
	local mine: { string } = {}
	for _, line in E.warnings do
		if string.find(line, "Parties", 1, true) or string.find(line, "Runs", 1, true) then
			table.insert(mine, line)
		end
	end
	check("no warning from the lobbies or the runs", #mine == 0, mine[1])
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
