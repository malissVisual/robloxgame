-- 10.5 ROUNDS end to end (the owner: "16 people on one server … a round starts at one place, everybody runs there,
-- everyone has their own car, what you carry off to it quickly is yours … not teams"): the REAL sandbox server
-- (SandboxBoot, Moving, Runs, Collection …) on tests/runtime/SandboxE2E.luau's stand-in, Config.Rounds.On.
--   1. Three join; nothing counts down before PLAY (InGame); Ann and Bob press PLAY: the countdown, the next place
--      named (its portal's sign, the round view), Cid (still on the start screen) not in it
--   2. The countdown ends: Ann and Bob ride to the place (the ride's round count), each one's own van parked at its
--      curb (side by side, locked, the back open, the owner's name over it, the Load prompt only theirs), no move
--      truck's Load, no helper, the move's view a round's (no FINISH for anybody)
--   3. Ann carries a piece out: Bob's van's Load does nothing for her, her own takes it: into her stock at once, the
--      model gone, the feed to both, the table (Ann first); Bob loads one of his own; an empty-handed Load is off;
--      CAR, FINISH and GIVE UP do nothing in a round
--   4. Cid presses PLAY mid-round: he waits in the lobby (not in it, his view says so)
--   5. Ann (the host) leaves the game: the round goes on, Bob's now (its move his, the pieces' prompts his), he loads
--      another
--   6. The clock: the results card ranks everybody who came (Ann too), the ride back to the plaza, the vans gone, the
--      next countdown (never the same place twice in a row), Bob and Cid in it; Cid leaves it alone (the list's LEAVE)
local E = require("./SandboxE2E")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
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
local H: any = {} -- the test's helpers (one register)
local S: any = {}

Config.Rounds.On = true
math.randomseed(1050) -- (the rounds' places and their houses' dice: the same every run)
Config.Visitors.On = false
for _, level in Config.Runs.Danger do -- (no hazards on these straight walks: a creak would drop the piece)
	level.Creak, level.Puddle, level.Plaster = 0, 0, 0
end

local baseplate = E.Mock.Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Parent = workspace
local Boot = E.module("SandboxBoot")
local Collection = E.module("Collection")
local Moving = E.module("Moving")
local MoveHelper = E.module("MoveHelper")
local Runs = E.module("Runs")
local Danger = E.module("RunDanger")
local Vehicles = E.fakes.Vehicles
MoveHelper.useMover(E.mover)
Boot.start(function() end)
E.advance(1)

-- ── The helpers (the e2e test's, trimmed) ─────────────────────────────────

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
function H.walkThrough(player: any, points: { any }): boolean
	return not E.walkPath(player, points)
end
function H.enterHouse(player: any, house: any): boolean
	local facing = H.yawLook(house.door.yaw)
	local door = V3(house.door.x, house.door.y + 3, house.door.z)
	E.walk(player, door + facing * 14)
	H.walkThrough(player, { door - facing * (Config.Moving.Doors.Hall.Depth - 1) })
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
	H.walkThrough(player, { inside - way * 5 + up })
	return E.waitUntil(function(): boolean
		return not H.isInside(player)
	end, 3)
end
-- The model of the round's piece at `spot` (its prompts the round's move's: MoveOwner its host).
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
-- Not in the vault, not behind a locked door (the round's danger), a hand piece.
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
S.taken = {}
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
function H.loadPrompt(van: any): any
	return van.chassis:FindFirstChild("CargoDoor"):FindFirstChild("RoundLoadPrompt")
end
-- Walks to `van`'s back, a look of the round (its prompt on), Load → ok, why
function H.loadAt(player: any, van: any): (boolean, string?)
	E.walk(player, H.behindVan(van, 2))
	E.advance(Q.Every + 0.05)
	return E.trigger(H.loadPrompt(van), player)
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
function H.round(player: any, from: number?): any
	return E.lastKind(player, "Runs", "round", from)
end
function H.sign(house: string): string
	local model = workspace:FindFirstChild("Sandbox"):FindFirstChild("Lobby"):FindFirstChild("Portals"):FindFirstChild(`Portal_{house}`)
	local sign = model and model:FindFirstChild("GateSign")
	local words = sign and sign:FindFirstChild("Words")
	local status = words and words:FindFirstChild("Status")
	return if status then status.Text else ""
end
function H.inRect(at: any, rect: any): boolean
	return at.X > rect.x0 and at.X < rect.x1 and at.Z > rect.z0 and at.Z < rect.z1
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

-- ── 1. Join, PLAY, the countdown ──────────────────────────────────────────

local ann = E.join(11, "Ann")
local bob = E.join(22, "Bob")
local cid = E.join(33, "Cid")
for _, p in { ann, bob, cid } do
	E.clients[p] = H.client(p)
end
E.advance(1)
check("1. three in the server, nobody pressed PLAY: no countdown (the round idle)", Runs.round().phase == "idle" and Runs.round().house == nil)
local playAt = #E.sent
E.fire(ann, "Play")
E.fire(bob, "Play")
E.advance(1)
local round = Runs.round()
local house = SandboxMap.house(round.house or "")
local view = H.round(ann, playAt)
check("…Ann and Bob press PLAY (InGame): the countdown (Config.Rounds.Wait), its place and difficulty picked", ann:GetAttribute("InGame") == true
	and round.phase == "wait" and house ~= nil and table.find(Config.Rounds.Difficulties, round.difficulty) ~= nil
	and math.abs(round.endsAt - workspace:GetServerTimeNow() - Q.Wait) < 2, round.phase)
check("…their round view: the countdown, the place's name, 2 in the game", view ~= nil and view.phase == "wait" and view.name == (house and house.name)
	and view.players == 2 and view.ready == true and view.inRound == false)
check("…Cid (still on the start screen) hears the round too, but is not ready", H.round(cid, playAt) ~= nil and H.round(cid, playAt).ready == false)
check("…the place's portal says NEXT ROUND HERE, the others ROUNDS · WAIT IN THE LOBBY", house ~= nil and string.find(H.sign(house.id), "NEXT ROUND HERE", 1, true) ~= nil
	and H.sign(if house.id == "old_mill" then "lone_house" else "old_mill") == "ROUNDS · WAIT IN THE LOBBY", house and H.sign(house.id))
S.house = house

-- ── 2. The round starts ──────────────────────────────────────────────────

local rideAt = #E.sent
E.advance(Q.Wait + 0.5)
E.advance(R.Fade.Out + 0.5)
round = Runs.round()
local annVan, bobVan = Vehicles.get(ann), Vehicles.get(bob)
local zone = SandboxMap.zone(house.id)
local ride = E.lastKind(ann, "Runs", "ride", rideAt)
check("2. the countdown over: the round on (Ann and Bob in it: Runs.runOf, a round), Cid not", round.phase == "play" and Runs.runOf(ann) ~= nil
	and Runs.runOf(bob) ~= nil and Runs.runOf(ann).house == house.id and Runs.runOf(cid) == nil and #Runs.runOf(ann).party == 2)
check("…the ride there: to the place, 2 movers (its round count), no names", ride ~= nil and ride.to == house.name and ride.round == 2 and #ride.party == 0)
check("…both land in the place's zone, by its door", H.inRect(E.rootOf(ann).Position, zone.rect) and H.inRect(E.rootOf(bob).Position, zone.rect))
check("…each has their own van at the place: two vans, side by side (Across apart), in the zone, facing the curb's way", annVan ~= nil and bobVan ~= nil and annVan ~= bobVan
	and H.inRect(annVan.chassis.Position, zone.rect) and H.inRect(bobVan.chassis.Position, zone.rect)
	and math.abs((annVan.chassis.Position - bobVan.chassis.Position).Magnitude - Q.Park.Across) < 1, annVan and bobVan and (annVan.chassis.Position - bobVan.chassis.Position).Magnitude)
check("…locked (Config.Runs.Truck.Attribute, the seat off), the back open, RoundVan its owner's, the owner's name over it", annVan.model:GetAttribute(R.Truck.Attribute) == true
	and annVan.seat.Disabled == true and Vehicles.backOpen(annVan) and annVan.model:GetAttribute("RoundVan") == ann.UserId
	and bobVan.model:GetAttribute("RoundVan") == bob.UserId and annVan.chassis:FindFirstChild("RoundVanTag") ~= nil
	and annVan.chassis:FindFirstChild("RoundVanTag"):FindFirstChild("Words").Text == "🚐 Ann")
local annLoad, bobLoad = H.loadPrompt(annVan), H.loadPrompt(bobVan)
check("…each van's Load prompt only its owner's (MoveOnly), off while they carry nothing; no move truck's Load", annLoad ~= nil and bobLoad ~= nil
	and annLoad:GetAttribute("MoveOnly") == ann.UserId and bobLoad:GetAttribute("MoveOnly") == bob.UserId and annLoad.Enabled == false
	and E.promptIn(annVan.chassis:FindFirstChild("CargoDoor"), "Load", function(p: any): boolean
		return p.Name ~= "RoundLoadPrompt"
	end) == nil)
local state = H.stateOf(ann)
check("…the move's view a round's: nobody's own (no FINISH, no GIVE UP), run.round, YOURS 0", state ~= nil and state.mine == false and state.run ~= nil
	and state.run.round == true and state.run.count == 0 and H.stateOf(bob).mine == false)
check("…no helper comes (everybody for themselves)", MoveHelper.find(ann) == nil and MoveHelper.find(bob) == nil)
view = H.round(cid)
check("…Cid's view: a round on (not his: inRound false)", view ~= nil and view.phase == "play" and view.inRound == false)

-- ── 3. Load at your own van ──────────────────────────────────────────────

local item, model = H.fetch(ann, house)
check("3. Ann carries a piece out of the house", item ~= nil and ann.Character:GetAttribute("MoveCarry") == item.spot, item and item.name)
local before = #Collection.stock(bob)
E.walk(ann, H.behindVan(bobVan, 2))
E.advance(Q.Every + 0.05)
E.trigger(bobLoad, ann)
E.advance(0.2)
check("NEG. …at Bob's van his Load does nothing for her (hers is hers: still in her hands, nothing in his stock)", item ~= nil
	and ann.Character:GetAttribute("MoveCarry") == item.spot and #Collection.stock(bob) == before)
local claimAt = #E.sent
local ok = H.loadAt(ann, annVan)
E.advance(0.3)
local stock = Collection.stock(ann)
check("…at her own van: Load (the prompt on, its name) takes it: in her stock at once, out of her hands, the model gone", ok and #stock == 1
	and stock[1].name == item.name and ann.Character:GetAttribute("MoveCarry") == nil and rawget(model, "destroyed") == true, #stock)
local feedAnn, feedBob = E.lastKind(ann, "Runs", "claim", claimAt), E.lastKind(bob, "Runs", "claim", claimAt)
check("…the feed: hers to her (mine), Bob hears who took what", feedAnn ~= nil and feedAnn.mine == true and feedAnn.name == item.name
	and feedBob ~= nil and feedBob.mine == false and feedBob.by == "Ann")
view = H.round(bob)
check("…the table: Ann first (1 piece, its value), Bob at 0", view ~= nil and view.top[1].name == "Ann" and view.top[1].count == 1 and view.top[1].value > 0
	and view.top[2].name == "Bob" and view.top[2].count == 0 and view.mine.place == 2)
check("…her move view: YOURS 1", H.stateOf(ann).run.count == 1)
E.advance(Q.Every + 0.05)
check("…empty-handed again: her Load is off", annLoad.Enabled == false)
local bobItem = H.fetch(bob, house)
local bobOk = bobItem ~= nil and H.loadAt(bob, bobVan)
E.advance(0.3)
check("…Bob loads one of his own: into his stock", bobOk and #Collection.stock(bob) == before + 1)
local carAt = #E.sent
E.fire(ann, "SpawnCar")
E.advance(0.3)
check("NEG. …CAR in a round: nothing (10.6: no CAR at all; the van stays parked)", Vehicles.get(ann) == annVan, E.lastNotice(ann, carAt))
E.fire(ann, "Moving", "finish")
E.advance(0.3)
E.fire(ann, "Moving", "giveup")
E.advance(0.3)
check("NEG. …FINISH and GIVE UP in a round: nothing (the clock ends it)", Runs.runOf(ann) ~= nil and Runs.round().phase == "play" and E.heard(ann, "clock runs out", carAt))

-- ── 4. A late PLAY ───────────────────────────────────────────────────────

local lateAt = #E.sent
E.fire(cid, "Play")
E.advance(1)
view = H.round(cid, lateAt)
check("4. Cid presses PLAY mid-round: not in it (he waits for the next one), his view says so", Runs.runOf(cid) == nil and view ~= nil and view.ready == true
	and view.phase == "play" and view.inRound == false and Vehicles.get(cid) == nil)

-- ── 5. The host leaves the game ──────────────────────────────────────────

local host = Runs.runOf(ann).host
check("5. (Ann is the round's host: the first in it)", host == ann)
E.leave(ann)
E.advance(1)
local run = Runs.runOf(bob)
check("…Ann leaves the game: the round goes on, Bob's now (Runs' host, his move's view still there), Ann out of it",
	run ~= nil and run.host == bob and #run.party == 1 and Runs.round().phase == "play" and H.stateOf(bob) ~= nil and H.stateOf(bob).run.round == true)
local third = H.fetch(bob, house)
local thirdOk = third ~= nil and H.loadAt(bob, bobVan)
E.advance(0.3)
check("…the pieces' prompts his now: he carries another out and loads it", thirdOk and #Collection.stock(bob) == before + 2, third and third.name)

-- ── 6. The clock ─────────────────────────────────────────────────────────

local endAt = #E.sent
local left = Runs.round().endsAt - workspace:GetServerTimeNow()
E.advance(left + 1.5)
local result = E.lastKind(bob, "Runs", "result", endAt)
local rows = if result and result.round then result.round.ranking else {}
local byName: { [string]: any } = {}
for _, row in rows do
	byName[row.name] = row
end
check("6. the clock: the results card, a round's: both who came ranked (Bob's 2 pieces, Ann's 1: she left, they are hers), the most value first, Bob's place his row's",
	result ~= nil and result.round ~= nil and result.round.players == 2 and #rows == 2 and byName.Bob ~= nil and byName.Bob.count == 2 and byName.Ann ~= nil
		and byName.Ann.count == 1 and rows[1].value >= rows[2].value and result.round.place == byName.Bob.place,
	result and result.round and `{result.round.place} {#rows}`)
check("…the round over (its view), Bob out of it", Runs.round().phase == "over" and Runs.runOf(bob) == nil and H.round(bob, endAt).phase == "over")
local backAt = #E.sent
E.advance(Q.Results + R.Fade.Out + 1)
local back = E.lastKind(bob, "Runs", "ride", backAt)
check("…Results s later the ride back: Bob in the lobby (the plaza), his van gone", back ~= nil and back.back == true
	and SandboxMap.inLobby(E.rootOf(bob).Position.X, E.rootOf(bob).Position.Z) and Vehicles.get(bob) == nil)
E.advance(2)
round = Runs.round()
check("…the next countdown: another place (never the same twice in a row), Bob and Cid in the game", round.phase == "wait" and round.house ~= nil
	and round.house ~= S.house.id and H.round(cid).players == 2, round.house)
local secondAt = #E.sent
E.advance(Q.Wait + R.Fade.Out + 1)
check("…its round takes them both (Cid too now)", Runs.runOf(bob) ~= nil and Runs.runOf(cid) ~= nil and Runs.runOf(cid).house == Runs.runOf(bob).house
	and Vehicles.get(cid) ~= nil and Vehicles.get(bob) ~= nil)

E.advance(0.5)
E.fire(cid, "Runs", { kind = "leave" })
E.advance(R.LeaveHold + R.Fade.Out + 1)
check("…Cid leaves the round (the list's LEAVE): back in the lobby alone, his van gone; the round goes on, Bob's",
	Runs.runOf(cid) == nil and SandboxMap.inLobby(E.rootOf(cid).Position.X, E.rootOf(cid).Position.Z) and Vehicles.get(cid) == nil
		and Runs.runOf(bob) ~= nil and Runs.round().phase == "play" and Vehicles.get(bob) ~= nil)

check("no errors in any thread", #E.errors == 0, table.concat(E.errors, " | "))
if failures > 0 then
	error(`{failures} checks failed`)
end
print("ALL CHECKS PASSED")
