-- 10.6 BOTH IN PLAY end to end (the owner: "Both in the PLAY circle": the QUICK ROUND, the server's rounds, beside
-- the PRIVATE LOBBY, the party lobbies' runs): the REAL sandbox server (SandboxBoot, Moving, MoveHelper, Runs, Parties,
-- Collection …) on tests/runtime/SandboxE2E.luau's stand-in, Config.Rounds.On.
--   1. Ann joins the QUICK ROUND queue in the PLAY circle: its countdown, its place X. Bob's PLAY view: X is the quick
--      round's (QUICK ROUND); NEG. his lobby on X refused, on Y made; NEG. Ann (queued) makes or joins no lobby; NEG.
--      Bob (in a lobby) joins no queue; NEG. Bob's CHANGE HOUSE to X refused; NEG. the admin's run on X refused
--   2. Bob's lobby (Cid joins) READY, START: their run at Y (the ride with Cid's name, his truck at the curb, Danny the
--      crew's helper). While it is on, the round's places never take Y (RoundRules.places: re-planned 40 times), nor
--      a house Dee's lobby holds while another is free
--   3. The countdown ends: Ann's round at X and Bob's run at Y AT THE SAME TIME: Ann's own van (Load only hers, no
--      helper, the ride's round count), Bob's truck with its FINISH; the map's IN A RUN lists Bob's run only, the
--      circle's attributes the round; Ann loads a piece into her van (her stock at once, the table); NEG. Bob's lobby
--      on X while the round plays there: refused
--   4. Bob loads a piece into his truck, FINISHes: his card the pieces' (no ranking), Hard opened for the party (the
--      difficulty unlocks), back beside the PLAY circle; Ann's round still on
--   5. The round's clock: Ann's card the ranking (1st of 1), X busy for lobbies while the round rides back (over), then
--      free; Ann still queued (Config.Rounds.Stay): the next countdown elsewhere than X
--   6. No script error, no warning from the lobbies or the runs
local E = require("./SandboxE2E")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local PartyRules = require("./PartyRules")
local FurnitureLooks = require("./FurnitureLooks")
local CarryGrip = require("./CarryGrip")

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
local Q = Config.Rounds
local R = Config.Runs
local L = SandboxMap.Lobby
local H: any = {} -- the test's helpers (one register)
local S: any = {} -- what the test keeps between its parts

Config.Rounds.On = true
math.randomseed(1060) -- (the rounds' places and their houses' dice: the same every run)
Config.Visitors.On = false
for _, level in Config.Runs.Danger do -- (no hazards on these straight walks: a creak would drop the piece)
	level.Creak, level.Puddle, level.Plaster = 0, 0, 0
end

local baseplate = E.Mock.Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Parent = workspace
local Boot = E.module("SandboxBoot")
local Collection = E.module("Collection")
local MoveHelper = E.module("MoveHelper")
local Runs = E.module("Runs")
local Parties = E.module("Parties")
local Danger = E.module("RunDanger")
local Vehicles = E.fakes.Vehicles
MoveHelper.useMover(E.mover)
Boot.start(function() end)
E.advance(1)

-- ── The helpers ──────────────────────────────────────────────────────────

function H.groundAt(at: any): any
	return V3(at.X, E.groundY(at.X, at.Z) + 3, at.Z)
end
function H.yawLook(yaw: number): any
	local r = math.rad(yaw)
	return V3(-math.sin(r), 0, -math.cos(r))
end
function H.stateOf(player: any): any
	E.advance(0.3)
	E.fire(player, "Moving", "state")
	local last = E.lastOf(player, "Moving", "state")
	return last and last[2]
end
function H.isInside(player: any): boolean
	return E.interiorAt(E.rootOf(player).Position) ~= nil
end
function H.enterHouse(player: any, house: any): boolean
	local facing = H.yawLook(house.door.yaw)
	local door = V3(house.door.x, house.door.y + 3, house.door.z)
	E.walk(player, door + facing * 14)
	E.walkPath(player, { door - facing * (Config.Moving.Doors.Hall.Depth - 1) })
	local inside = E.waitUntil(function(): boolean
		return H.isInside(player)
	end, 3)
	if inside then
		E.advance(0.3)
		local look = E.rootOf(player).CFrame.LookVector
		S.into = V3(look.X, 0, look.Z).Unit
	end
	return inside
end
function H.leaveHouse(player: any): boolean
	local origin = E.interiorAt(E.rootOf(player).Position)
	local exit: any = nil
	for _, d in workspace:FindFirstChild("Moves"):GetChildren() do
		if d.Name == "LeaveDoor" and origin and (d.Position - origin.Position).Magnitude < 400 then
			exit = d
		end
	end
	if not exit then
		return false
	end
	local inside = exit.Position - V3(0, 3.5, 0)
	local way = S.into or V3(0, 0, 1)
	local up = V3(0, Config.Furniture.EntryUp, 0)
	if not E.walk(player, inside + way * 5 + up) then
		return not H.isInside(player)
	end
	E.walkPath(player, { inside - way * 5 + up })
	return E.waitUntil(function(): boolean
		return not H.isInside(player)
	end, 3)
end
-- The model of the run's piece at `spot` (its prompts the run's move's: MoveOwner its host).
function H.pieceOf(player: any, spot: number): any
	local run = Runs.runOf(player)
	local owner = if run then run.host.UserId else player.UserId
	for _, d in workspace:FindFirstChild("Moves"):GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not rawget(d, "destroyed") then
			local root = d.PrimaryPart
			if root and E.promptIn(root, "", function(p: any): boolean
				return p:GetAttribute("MoveOwner") == owner
			end) then
				return d
			end
		end
	end
	return nil
end
-- Not in the vault, not behind a locked door (the run's danger), a hand piece.
function H.free(player: any, spot: number): boolean
	local st = Danger.stateFor(player)
	if not st then
		return true
	end
	if st.sealed[spot] then
		return false
	end
	local room: string? = nil
	for _, planned in st.s.plan.spots do
		if planned.id == spot then
			room = planned.room
		end
	end
	for _, lock in st.locks do
		if not lock.open and table.find(lock.plan.behind, room) then
			return false
		end
	end
	return true
end
S.taken = {}
function H.choose(player: any): (any, any)
	for _, item in H.stateOf(player).items do
		local model = H.pieceOf(player, item.spot)
		local id = model and model:GetAttribute("FurnitureId")
		local def = id and FurnitureLooks.Items[id]
		if item.state == "home" and def and def.class ~= "pair" and H.free(player, item.spot) and not S.taken[item.spot] then
			S.taken[item.spot] = true
			return item, model
		end
	end
	return nil, nil
end
function H.walkTo(player: any, model: any)
	local origin = E.interiorAt(E.rootOf(player).Position)
	local at = model.PrimaryPart.Position
	local floor = (if origin then origin.Position.Y else E.groundY(at.X, at.Z)) + Config.Furniture.EntryUp
	local toward = V3(E.rootOf(player).Position.X - at.X, 0, E.rootOf(player).Position.Z - at.Z)
	toward = if toward.Magnitude > 1e-3 then toward.Unit else V3(1, 0, 0)
	local size = model.PrimaryPart.Size
	E.walk(player, V3(at.X, floor, at.Z) + toward * (math.max(size.X, size.Z) / 2 + 1.5))
end
function H.pickUp(player: any, model: any): boolean
	H.walkTo(player, model)
	local prompt = E.promptIn(model.PrimaryPart, "Pick up") or E.promptIn(model.PrimaryPart, "Lift")
	local ok = prompt ~= nil and E.trigger(prompt, player)
	E.advance(3)
	return ok and player.Character:GetAttribute("MoveCarry") == model:GetAttribute("MoveSpot")
end
function H.behindVan(van: any, out: number): any
	local door = van.chassis:FindFirstChild("CargoDoor")
	local back = van.chassis.CFrame:PointToObjectSpace(door.WorldPosition)
	return H.groundAt(van.chassis.CFrame * V3(0, 0, back.Z + out))
end
-- One piece out of the house (in, picked, out) → its item and model, or nil
function H.fetch(player: any, house: any): (any, any)
	if not H.enterHouse(player, house) then
		return nil, nil
	end
	local item, model = H.choose(player)
	if not item or not H.pickUp(player, model) then
		return nil, nil
	end
	if not H.leaveHouse(player) then
		return nil, nil
	end
	return item, model
end
-- The client: answers its grip checks with a good press (client/CarryGripUi.luau's), a ping later.
function H.client(player: any): (string, ...any) -> ()
	return function(remote: string, kind: any, what: any, payload: any)
		if remote == "Moving" and kind == "grip" and what == "open" then
			local gripCheck = CarryGrip.fromWire(payload)
			if not gripCheck then
				return
			end
			local press = CarryGrip.firstHit(gripCheck)
			local id = payload.id
			E.task.delay(press + E.ping, function()
				if player.Parent then
					E.fire(player, "Moving", "grip", id, "ok", press)
				end
			end)
		end
	end
end
function H.circleModel(): any
	return workspace:FindFirstChild("Sandbox"):FindFirstChild("Lobby"):FindFirstChild("PlayCircle")
end
function H.attr(): { PartyRules.Entry }
	return PartyRules.decode(H.circleModel():GetAttribute(R.Party.Attribute))
end
-- the n-th of a few spots round the circle's middle, 3 studs apart
function H.inCircle(n: number): any
	local x, z = L.play.x + ((n - 1) % 3 - 1) * 3, L.play.z + ((n - 1) // 3 - 1) * 3
	return V3(x, E.groundY(x, z) + 3, z)
end
-- a request on the Party remote, then a moment (its rate limit; the loop's look)
function H.ask(player: any, message: any)
	E.fire(player, "Party", message)
	E.advance(0.25)
end
function H.play(player: any, from: number?): any
	return E.lastKind(player, "Party", "play", from)
end
function H.houseIn(view: any, id: string): any
	for _, h in (if view then view.houses else {}) do
		if h.id == id then
			return h
		end
	end
	return nil
end
-- Another house than any of `not` (in SandboxMap.Houses' order).
function H.other(...: string): string
	local skip = { ... }
	for _, h in SandboxMap.Houses do
		if not table.find(skip, h.id) and SandboxMap.zone(h.id) then
			return h.id
		end
	end
	error("no other house")
end

local ann = E.join(11, "Ann")
local bob = E.join(22, "Bob")
local cid = E.join(33, "Cid")
for _, p in { ann, bob, cid } do
	E.clients[p] = H.client(p)
end
E.advance(1)

-- ── 1. The quick round's place is busy for the lobbies ───────────────────

do
	for n, p in { ann, bob, cid } do
		E.walk(p, H.inCircle(n))
	end
	E.advance(R.Every + 0.05)
	H.ask(ann, { kind = "round", on = true })
	E.advance(Q.Every + R.Every + 0.05)
	local round = Runs.round()
	S.x = round.house
	local view = H.play(bob)
	check("1. Ann joins the QUICK ROUND queue: its countdown to X; Bob's PLAY view: X the quick round's (state round), the others free", round.phase == "wait"
		and S.x ~= nil and Runs.queued(ann) and H.houseIn(view, S.x) ~= nil and H.houseIn(view, S.x).state == "round"
		and H.houseIn(view, H.other(S.x)).state == "free" and Runs.houseBusy(S.x) == "round", S.x)
	local at = #E.sent
	H.ask(bob, { kind = "create", house = S.x, difficulty = "normal", friends = false })
	check("NEG. …Bob's lobby on X: refused (the quick round's place, told)", Parties.lobbyOf(bob) == nil and E.heard(bob, "is the quick round's place", at))
	S.y = H.other(S.x)
	H.ask(bob, { kind = "create", house = S.y, difficulty = "normal", friends = false })
	check("…on Y: made (his lobby, Y)", Parties.lobbyOf(bob) ~= nil and (Parties.lobbyOf(bob) :: any).house == S.y)
	H.ask(ann, { kind = "create", house = H.other(S.x, S.y), difficulty = "normal", friends = false })
	H.ask(ann, { kind = "join", id = (Parties.lobbyOf(bob) :: any).id })
	check("NEG. …Ann (queued) makes no lobby and joins none (told: LEAVE THE QUEUE first)", Parties.lobbyOf(ann) == nil and E.heard(ann, "LEAVE THE QUEUE first", at)
		and Runs.queued(ann))
	H.ask(cid, { kind = "join", id = (Parties.lobbyOf(bob) :: any).id })
	H.ask(cid, { kind = "round", on = true })
	check("NEG. …Cid (in Bob's lobby) joins no queue (told)", Parties.lobbyOf(cid) == Parties.lobbyOf(bob) and not Runs.queued(cid) and E.heard(cid, "You are in a lobby", at))
	H.ask(bob, { kind = "house", id = S.x })
	check("NEG. …Bob's CHANGE HOUSE to X: refused, his lobby keeps Y", (Parties.lobbyOf(bob) :: any).house == S.y and E.heard(bob, "is the quick round's place", at))
	local said = Runs.begin(S.x, { cid }, "normal", true)
	check("NEG. …even the admin's run on X: refused (Runs.begin)", said ~= nil and string.find(said, "quick round's place", 1, true) ~= nil and Runs.runOf(cid) == nil, said)
end

-- ── 2. Bob's lobby's run; the round's places never take it ───────────────

do
	local rideAt = #E.sent
	H.ask(cid, { kind = "ready", on = true })
	H.ask(bob, { kind = "ready", on = true })
	H.ask(bob, { kind = "start" })
	E.waitUntil(function(): boolean
		return Runs.runOf(bob) ~= nil
	end, R.Party.Countdown + 1)
	E.advance(R.Fade.Out + 0.5)
	local run = Runs.runOf(bob)
	local ride = E.lastKind(bob, "Runs", "ride", rideAt)
	check("2. Bob's lobby READY, START: the run at Y (Bob the host, Cid with him, no round), the ride with Cid's name (no round count)", run ~= nil and run.house == S.y
		and run.host == bob and #run.party == 2 and run.round ~= true and ride ~= nil and ride.round == nil and table.find(ride.party, "Cid") ~= nil and #Parties.lobbies() == 0)
	check("…his truck at Y's curb, the crew's helper with them (Danny)", Vehicles.get(bob) ~= nil and MoveHelper.find(bob) ~= nil and MoveHelper.find(bob).hirer == bob)
	check("…Y is busy for the round too (a run in it: RunRules.houseBusy's run)", Runs.houseBusy(S.y) == "run")
	-- the round's places never take Y: Ann out of the queue and in again, 40 plans
	local picks: { [string]: boolean } = {}
	local onY = 0
	for _ = 1, 40 do
		Runs.queue(ann, false)
		Runs.roundStep()
		Runs.queue(ann, true)
		local house = Runs.round().house
		if house == S.y then
			onY += 1
		end
		if house then
			picks[house] = true
		end
	end
	local kinds = 0
	for _ in picks do
		kinds += 1
	end
	check("…40 plans of the round (Ann out of the queue and in again): never Y (Bob's run), every one a place, several places", onY == 0 and kinds >= 3
		and not picks[S.y], `{onY} on Y, {kinds} places`)
	-- a lobby holding a house: the round leaves it be while another is free
	local dee = E.join(44, "Dee")
	E.advance(4)
	E.walk(dee, H.inCircle(1))
	E.advance(R.Every + 0.05)
	S.z = H.other(S.y, Runs.round().house or "")
	H.ask(dee, { kind = "create", house = S.z, difficulty = "easy", friends = false })
	local onZ = 0
	for _ = 1, 40 do
		Runs.queue(ann, false)
		Runs.roundStep()
		Runs.queue(ann, true)
		local house = Runs.round().house
		if house == S.z or house == S.y then
			onZ += 1
		end
	end
	check("…Dee's lobby holds Z: 40 plans more, never Z nor Y (another place free)", Parties.lobbyOf(dee) ~= nil and onZ == 0, onZ)
	H.ask(dee, { kind = "leave" })
	S.dee = dee
	S.x = Runs.round().house
	check("(the countdown again, to X now; Dee's lobby closed)", Runs.round().phase == "wait" and S.x ~= nil and S.x ~= S.y and #Parties.lobbies() == 0, S.x)
end

-- ── 3. Ann's round and Bob's run at the same time ───────────────────────

do
	local rideAt = #E.sent
	E.advance(Runs.round().endsAt - workspace:GetServerTimeNow() + 0.5)
	E.advance(R.Fade.Out + 0.5)
	local mine, his = Runs.runOf(ann), Runs.runOf(bob)
	local ride = E.lastKind(ann, "Runs", "ride", rideAt)
	check("3. the countdown over: Ann's round at X AND Bob's run at Y, both on at once", Runs.round().phase == "play" and mine ~= nil and mine.round == true
		and mine.house == S.x and his ~= nil and his.house == S.y and his.round ~= true and #Runs.list() == 2)
	check("…Ann's ride: to X, the round's count (1 mover)", ride ~= nil and ride.round == 1 and ride.to == (SandboxMap.house(S.x) :: any).name)
	local annVan = Vehicles.get(ann)
	check("…Ann's own van at X (RoundVan hers, its Load prompt only hers), no helper for her; Bob keeps his truck and Danny", annVan ~= nil
		and annVan.model:GetAttribute("RoundVan") == ann.UserId and annVan.chassis:FindFirstChild("CargoDoor"):FindFirstChild("RoundLoadPrompt") ~= nil
		and MoveHelper.find(ann) == nil and Vehicles.get(bob) ~= nil and Vehicles.get(bob) ~= annVan and MoveHelper.find(bob) ~= nil)
	local state, theirs = H.stateOf(ann), H.stateOf(bob)
	check("…Ann's move a round's (nobody's FINISH), Bob's a run's (his FINISH)", state ~= nil and state.run.round == true and state.mine == false
		and theirs ~= nil and theirs.run.round ~= true and theirs.mine == true)
	E.advance(R.Every + 0.05)
	local entries = H.attr()
	local circle = H.circleModel()
	check("…the map: IN A RUN lists Bob's run only (Y, Bob and Cid), the circle's round attributes Ann's round (play, X, 1 mover)", #entries == 1
		and entries[1].state == "run" and entries[1].house == S.y and entries[1].who == "Bob, Cid" and circle:GetAttribute("RoundPhase") == "play"
		and circle:GetAttribute("RoundHouse") == S.x and circle:GetAttribute("RoundMovers") == 1, #entries)
	local item = H.fetch(ann, SandboxMap.house(S.x))
	E.walk(ann, H.behindVan(annVan, 2))
	E.advance(Q.Every + 0.05)
	local loaded = item ~= nil and E.trigger(annVan.chassis:FindFirstChild("CargoDoor"):FindFirstChild("RoundLoadPrompt"), ann)
	E.advance(0.3)
	local view = E.lastKind(ann, "Runs", "round")
	check("…Ann loads a piece into her van: hers at once (her stock), the round's table her row", loaded and #Collection.stock(ann) == 1 and view ~= nil
		and view.top[1] ~= nil and view.top[1].name == "Ann" and view.top[1].count == 1, item and item.name)
	E.walk(S.dee, H.inCircle(2))
	E.advance(R.Every + 0.05)
	local at = #E.sent
	H.ask(S.dee, { kind = "create", house = S.x, difficulty = "easy", friends = false })
	check("NEG. …Dee's lobby on X while the round plays there: refused (the quick round's place)", Parties.lobbyOf(S.dee) == nil and E.heard(S.dee, "is the quick round's place", at))
end

-- ── 4. Bob finishes; Ann's round goes on ────────────────────────────────

do
	local bobVan = Vehicles.get(bob)
	local item = H.fetch(bob, SandboxMap.house(S.y))
	E.walk(bob, H.behindVan(bobVan, 2))
	E.advance(0.3)
	local loaded = item ~= nil and E.trigger(E.promptIn(bobVan.chassis:FindFirstChild("CargoDoor"), "Load"), bob)
	E.advance(0.3)
	check("4. Bob carries a piece out of Y and loads it into his truck (the truck's Load: a lobby run's), while Ann's round goes on", loaded
		and Runs.round().phase == "play", item and item.name)
	local at = #E.sent
	Runs.finish(bob)
	E.advance(0.5)
	local card = E.lastKind(bob, "Runs", "result", at)
	check("…Bob FINISHes: the run over; his card the pieces' (his piece, no ranking), Hard opened for the party (the difficulty unlocks)", Runs.runOf(bob) == nil
		and card ~= nil and card.round == nil and type(card.pieces) == "table" and #card.pieces >= 1 and card.opened == "hard"
		and E.lastKind(cid, "Runs", "unlocked", at) ~= nil, card and `{card.phase} {card.opened} {#card.pieces}`)
	E.advance(R.EndHold + R.Fade.Out + 0.5)
	local where = E.rootOf(bob).Position
	check("…back beside the PLAY circle (never in it), his truck gone; Ann's round still on at X", not SandboxMap.inPlay(where.X, where.Z, 1) and SandboxMap.inLobby(where.X, where.Z)
		and Vehicles.get(bob) == nil and Runs.round().phase == "play" and Runs.runOf(ann) ~= nil and not Runs.inUse(S.y))
end

-- ── 5. The round's end ──────────────────────────────────────────────────

do
	local at = #E.sent
	E.advance(Runs.round().endsAt - workspace:GetServerTimeNow() + 1)
	local card = E.lastKind(ann, "Runs", "result", at)
	check("5. the round's clock: Ann's card the ranking (1st of 1), her piece hers; still in the queue", card ~= nil and card.round ~= nil and card.round.place == 1
		and card.round.players == 1 and card.round.queued == true and Runs.queued(ann))
	check("…X busy for the lobbies while the round rides back (over)", Runs.round().phase == "over" and Runs.houseBusy(S.x) == "round")
	E.advance(Q.Results + R.Fade.Out + 2)
	local round = Runs.round()
	check("…then the next countdown (Ann still queued), elsewhere than X; X free for a lobby again", round.phase == "wait" and round.house ~= S.x
		and Runs.houseBusy(S.x) == nil and Vehicles.get(ann) == nil, round.house)
end

-- ── 6. Clean ─────────────────────────────────────────────────────────────

do
	check("6. no script error in any thread", #E.errors == 0, table.concat(E.errors, " | "))
	local mine: { string } = {}
	for _, line in E.warnings do
		if string.find(line, "Parties", 1, true) or string.find(line, "Runs", 1, true) then
			table.insert(mine, line)
		end
	end
	check("…no warning from the lobbies or the runs", #mine == 0, mine[1])
end

if failures > 0 then
	error(`{failures} checks failed`)
end
print("ALL CHECKS PASSED")
