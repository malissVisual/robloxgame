-- 7.0 greeters: the real server/MoveGreeters.luau with the real server/Moving.luau in the Luau CLI (tests/run_tests.py
-- builds MoveGreetersServer.luau and MovingServer.luau on tests/runtime/MovingRuntime.luau's fakes: Npcs records what
-- the people say, their gestures and glances). The soldier at the Wall from the start (his body made again when it
-- goes); a move of a crew of two (no Danny): Marge on the porch of her house from its start, beside the door and off
-- the path; nothing goes after her; her hello once, to the first crew member who comes near (a wave, the lines LineGap s
-- apart, a hand out to the open door at the last), never again that move; a ★ thing carried past her ("Careful with
-- that!": not for a plain thing, not twice within StarAgain s), the loaded truck driving off (her thanks, the crew's
-- notice too), the horde; the delivery at the Wall: the soldier turns to the truck, waves and welcomes it, Marge gone;
-- a move called off: no welcome; a contract without a greeter: nobody on the porch. Marge at the kiosk: the tutorial's
-- dispatcher (no second Marge), to a player on foot and on no move who comes up to the kiosk, once per player every
-- Again s, her bubble seen from afar, the player's notice; 7.1 review: never into her first day (a player with the
-- attribute TutorialPhase, her own tutorial talk going: TutorialTalk), the line waiting till that talk is over.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local Greeters = require("./MoveGreetersServer")
local Config = require("./Config")
local Map = require("./Map")
local MoveStory = require("./MoveStory")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local G = Config.MoveGreeters
local T = Config.Moving
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

local home = Map.home(T.Contracts[1].home) :: any
local door = V3(home.door.x, 3, home.door.z)
local facing = V3(home.facing.x, 0, home.facing.z)
local right = V3(-facing.Z, 0, facing.X)
local outside = door + facing * 4
local drop = V3(Map.Depot.x + T.DropOff[1], 3, Map.Depot.z + T.DropOff[2])
local depot = V3(Map.Depot.x, 3, Map.Depot.z)
E.truckAt = V3(home.park.x, 2, home.park.z) -- (the truck at the house's kerb at once)
local lines = MoveStory.greeterOf("marge") :: any

local ann = E.player(11, "Ann", depot)
local bob = E.player(22, "Bob", depot + V3(3, 0, 0))
local cid = E.player(33, "Cid", depot + V3(-60, 0, 0))
E.crew[ann] = { bob }
Moving.useArt(E.art)
Moving.start()

local function flat(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.ActionText ~= nil and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function trigger(prompt: any, player: any)
	prompt.Triggered:Fire(player)
end
local function itemModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
-- The porch greeter of `owner`'s move (her body in the world), or nil.
local function porchOf(owner: any): any
	for _, child in workspace:GetChildren() do
		if child:GetAttribute("MoveGreeter") == "porch" and child:GetAttribute("MoveGreeterOf") == owner.UserId and not child.destroyed then
			return child
		end
	end
	return nil
end
-- How many times `npc` said `text` (since entry `from` of E.saidBy), and the last such entry.
local function saidBy(npc: any, text: string, from: number?): (number, any)
	local count, last = 0, nil
	for index = (from or 0) + 1, #E.saidBy do
		local entry = E.saidBy[index]
		if entry.npc == npc and entry.text == text then
			count += 1
			last = entry
		end
	end
	return count, last
end
local function acted(npc: any, kind: string, from: number?): boolean
	for index = (from or 0) + 1, #E.acts do
		if E.acts[index].npc == npc and E.acts[index].kind == kind then
			return true
		end
	end
	return false
end
local function lastGlance(npc: any): any
	for index = #E.glances, 1, -1 do
		if E.glances[index].npc == npc then
			return E.glances[index].at
		end
	end
	return nil
end
local function heard(player: any, text: string, since: number?): boolean
	for index = since or 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			return true
		end
	end
	return false
end
-- One tick of the move after `seconds` (the greeters' lines wait their turn on the clock).
local function tick(seconds: number?)
	E.clock += seconds or 0.2
	Moving.step()
end

-- The soldier at the Wall -------------------------------------------------------------------------------------------------

Greeters.step()
local soldier = Greeters.soldier()
local soldierAt = drop + V3(G.Soldier.At[1], 0, G.Soldier.At[2])
check("the soldier at the Wall from the start: his name, his title", soldier ~= nil and soldier.Parent ~= nil and soldier.Name == G.Soldier.Name
	and soldier:GetAttribute("Title") == G.Soldier.Title and soldier:GetAttribute("MoveGreeter") == "soldier")
local sroot = soldier.PrimaryPart
check("…by the booth, off the drop-off's bay", flat(sroot.Position, soldierAt) < 0.01 and math.abs(sroot.Position.X - drop.X) > Config.MoveSites.Bay[1] / 2 + 1,
	sroot.Position)
local toBay = V3(drop.X - sroot.Position.X, 0, drop.Z - sroot.Position.Z).Unit
check("…facing the bay", sroot.CFrame.LookVector:Dot(toBay) > 0.99, sroot.CFrame.LookVector)
Greeters.step()
check("one soldier (his loop does not make another)", Greeters.soldier() == soldier)

-- Marge on the porch ---------------------------------------------------------------------------------------------------------

local started = Moving.admin(ann, "start")
check("a move of two starts (no Danny for a crew of two)", string.find(started, "started", 1, true) ~= nil, started)
local truck = E.cars[ann]
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
local saidAtStart = #E.saidBy
tick()
local marge = porchOf(ann)
check("Marge on the porch from the move's start", marge ~= nil and marge.Name == "Marge" and marge:GetAttribute("Title") == `Client · {home.address}`)
local mroot = marge.PrimaryPart
local offset = V3(mroot.Position.X - door.X, 0, mroot.Position.Z - door.Z)
check("…beside the front door, out on the porch", offset.Magnitude < 7 and offset:Dot(facing) > 1, offset)
check("…off the path to the kerb (its ±2.4 studs, her body a stud each side)", math.abs(offset:Dot(right)) >= 2.4 + 1, offset:Dot(right))
check("…facing the street", mroot.CFrame.LookVector:Dot(facing) > 0.99)
check("the crew at the depot: no hello yet", #E.saidBy == saidAtStart)
local hunted = false
for _, target in E.Zombies.extraTargets() do
	if target.humanoid == marge:FindFirstChildOfClass("Humanoid") then
		hunted = true
	end
end
check("nothing goes after her (no Zombies.extraTargets entry)", not hunted)
local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
local enter = promptIn(site, "Enter house")
check("the front door is open all along (Enter house before her hello)", enter ~= nil and enter.Enabled)

-- her hello: once, to the first who comes near
E.place(bob, mroot.Position + facing * (G.Hello + 6))
tick()
check("Bob still too far: no hello", #E.saidBy == saidAtStart)
local before = #E.saidBy
local actsBefore = #E.acts
E.place(bob, mroot.Position + facing * (G.Hello - 6))
tick()
check("Bob comes within Hello: she turns to him, waves and says her first line", saidBy(marge, lines.hello[1], before) == 1 and acted(marge, "wave", actsBefore)
	and lastGlance(marge) ~= nil and flat(lastGlance(marge), E.rootOf(bob).Position) < 0.01)
tick(0.2)
check("…the next line waits LineGap s", saidBy(marge, lines.hello[2], before) == 0)
tick(G.LineGap)
check("…then her second line", saidBy(marge, lines.hello[2], before) == 1)
tick(G.LineGap)
local _, lastHello = saidBy(marge, lines.hello[#lines.hello], before)
check("…and the last with a hand out to the open door", lastHello ~= nil and acted(marge, "give", actsBefore) and flat(lastGlance(marge), door) < 0.01)
E.place(ann, outside)
for _ = 1, 5 do
	tick(G.LineGap)
end
check("her hello once a move (Ann comes too: nothing more)", saidBy(marge, lines.hello[1], before) == 1 and #E.saidBy - before == #lines.hello, #E.saidBy - before)

-- a ★ thing carried past her ("Careful with that!"), a plain one not
trigger(enter, ann)
local origin = E.interiors[#E.interiors]
local leave = promptIn(workspace, "Leave house")
local lamp = itemModel(1)
E.place(ann, lamp.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(lamp, "Pick up"), ann)
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(leave, ann)
lamp:PivotTo(E.rootOf(ann).CFrame * M.CFrame.new(0, 0, -3)) -- (the weld, in Roblox)
before = #E.saidBy
tick(G.Gap)
tick(G.Gap)
check("a plain thing carried past her: nothing", saidBy(marge, lines.star, before) == 0)
E.Net.get("PutDown").OnServerEvent:Fire(ann)
trigger(enter, ann)
local box = itemModel(5) -- (the box of memories ★, one hand)
E.place(ann, box.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(box, "Pick up"), ann)
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(leave, ann)
box:PivotTo(E.rootOf(ann).CFrame * M.CFrame.new(0, 0, -3))
tick(G.Gap)
local _, careful = saidBy(marge, lines.star, before)
check("the box of memories (★) carried past her: \"Careful with that!\", turned to it", careful ~= nil and flat(lastGlance(marge), box.PrimaryPart.Position) < 0.01)
-- Bob brings Grandpa's clock (★) right after: not within StarAgain s, then yes
E.place(bob, outside)
trigger(enter, bob)
local clock = itemModel(4)
E.place(bob, clock.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(clock, "Pick up"), bob)
E.place(bob, origin.Position + V3(0, 3, 1))
trigger(leave, bob)
clock:PivotTo(E.rootOf(bob).CFrame * M.CFrame.new(0, 0, -3))
tick(G.Gap)
check("…another ★ thing within StarAgain s: not again", saidBy(marge, lines.star, before) == 1)
tick(G.StarAgain)
tick(G.Gap)
check("…after StarAgain s: Grandpa's clock gets its \"Careful with that!\"", saidBy(marge, lines.star, before) == 2)
E.Net.get("PutDown").OnServerEvent:Fire(bob)

-- the loaded truck drives off: her thanks (the crew's notice too: they drive away from her)
truck.model:SetAttribute("BackOpen", true)
E.clock += 1
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
tick()
trigger(promptIn(truck.model, "Load"), ann)
check("the box in the truck", string.find(E.lastNotice(ann), "loaded", 1, true) ~= nil, E.lastNotice(ann))
tick()
before = #E.saidBy
local noticesBefore = #E.messages
truck.chassis.CFrame = M.CFrame.new(door.X + G.Leave.Far - 20, 2, door.Z)
tick(G.Gap)
check("the truck not yet past Leave.Far: nothing", saidBy(marge, lines.leave, before) == 0)
truck.chassis.CFrame = M.CFrame.new(door.X + G.Leave.Far + 10, 2, door.Z)
tick(G.Gap)
local _, thanks = saidBy(marge, lines.leave, before)
check("past Leave.Far with a load: her thanks, seen from afar", thanks ~= nil and (thanks.range or 0) >= G.Leave.Far and acted(marge, "wave", actsBefore))
check("…and the crew hears it (they drive away from her)", heard(ann, lines.leave, noticesBefore) and heard(bob, lines.leave, noticesBefore))
truck.chassis.CFrame = M.CFrame.new(E.truckAt.X, 2, E.truckAt.Z)
tick(G.Gap)
truck.chassis.CFrame = M.CFrame.new(door.X + G.Leave.Far + 10, 2, door.Z)
tick(G.Gap)
check("back and off again within LeaveAgain s: no second thanks", saidBy(marge, lines.leave, before) == 1)

-- the horde
before = #E.saidBy
Moving.admin(ann, "horde")
tick(G.Gap)
check("the horde: \"They're coming! Hurry!\"", saidBy(marge, lines.horde, before) == 1)
tick(G.Gap)
check("…once", saidBy(marge, lines.horde, before) == 1)

-- the delivery at the Wall: the soldier's welcome, Marge gone
before = #E.saidBy
actsBefore = #E.acts
truck.chassis.CFrame = M.CFrame.new(drop.X + 5, 2, drop.Z)
E.place(ann, drop + V3(0, 1, 0))
E.place(bob, drop + V3(4, 1, 0))
tick()
local result = E.last(ann, "Moving", "result")
check("delivered at the Wall", result ~= nil and result.a.how == "done", result and result.a.how)
check("the soldier welcomes the truck: \"Welcome to the safe zone. Unload over there.\"", saidBy(soldier, MoveStory.Wall.welcome, before) == 1 and acted(soldier, "wave", actsBefore)
	and flat(lastGlance(soldier), truck.chassis.Position) < 0.01)
check("Marge left the porch with the move", marge.destroyed == true and porchOf(ann) == nil)

-- a move called off: no welcome; she goes all the same
Moving.admin(ann, "start")
tick()
local second = porchOf(ann)
check("the next move: a new Marge on the porch", second ~= nil and second ~= marge)
before = #E.saidBy
Moving.admin(ann, "end")
Greeters.step()
check("called off: she goes, no welcome at the Wall", second.destroyed == true and saidBy(soldier, MoveStory.Wall.welcome, before) == 0)

-- a contract without a greeter: nobody on the porch
local prologue = MoveStory.Chapters[1]
local kept = prologue.greeter
prologue.greeter = nil
Moving.admin(ann, "start")
tick()
check("no greeter for the contract: nobody on the porch", porchOf(ann) == nil)
Moving.admin(ann, "end")
prologue.greeter = kept

-- the soldier's body made again when it goes (at most every Respawn s)
soldier:Destroy()
Greeters.step()
local again = Greeters.soldier()
check("the soldier's body gone: made again by his loop", again ~= soldier and again ~= nil and again.Parent ~= nil and again.Name == G.Soldier.Name)
again:Destroy()
Greeters.step()
check("…gone again at once: not made again within Respawn s", Greeters.soldier() == again)
E.clock += G.Respawn + 0.1
Greeters.step()
check("…Respawn s later: he is back", Greeters.soldier() ~= again and Greeters.soldier().Parent ~= nil)

-- Marge at the kiosk ---------------------------------------------------------------------------------------------------------

local boardPart = promptIn(workspace:FindFirstChild("Moves"):FindFirstChild("MovingBoard"), "Moving contracts").Parent
-- the tutorial's Marge (server/Tutorial.luau) stands by the job board: a person with the attribute Dispatcher
local npcs = M.Instance.new("Folder")
npcs.Name = "Npcs"
npcs.Parent = workspace
local dispatcher = M.Instance.new("Model")
dispatcher.Name = "Marge"
local droot = M.Instance.new("Part")
droot.Name = "HumanoidRootPart"
droot.CFrame = M.CFrame.new(Map.Depot.x + Config.Tutorial.NpcSpot[1], 3, Map.Depot.z + Config.Tutorial.NpcSpot[2])
droot.Parent = dispatcher
dispatcher.PrimaryPart = droot
dispatcher:SetAttribute("Dispatcher", true)
dispatcher.Parent = npcs
E.clock += G.Respawn + 0.1
local kioskLine = MoveStory.kioskLine(1)
before = #E.saidBy
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near + 8), 0, 0))
Greeters.step()
check("a player away from the kiosk: nothing", #E.saidBy == before)
local noticeAt = #E.messages
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near - 4), 0, 0))
Greeters.step()
local _, hi = saidBy(dispatcher, kioskLine, before)
check("Cid comes up to the kiosk: the tutorial's Marge says \"New contract, sweetie?\", turned to Cid", hi ~= nil and kioskLine == "New contract, sweetie?"
	and flat(lastGlance(dispatcher), E.rootOf(cid).Position) < 0.01)
check("…her bubble seen from across the yard (she stands by the job board)", hi ~= nil and (hi.range or 0) >= G.Kiosk.Hear
	and flat(droot.Position, boardPart.Position) < G.Kiosk.Hear)
check("…and Cid gets the words", heard(cid, kioskLine, noticeAt) and not heard(ann, kioskLine, noticeAt))
local greeters = 0
for _, child in workspace:GetChildren() do
	if child:GetAttribute("MoveGreeter") ~= nil and not child.destroyed then
		greeters += 1
	end
end
check("no second Marge at the depot (only the soldier is the greeters' own)", greeters == 1)
before = #E.saidBy
Greeters.step()
E.clock += 1
Greeters.step()
check("standing there: not again", #E.saidBy == before)
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near + 8), 0, 0))
Greeters.step()
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near - 4), 0, 0))
E.clock += 1
Greeters.step()
check("away and back within Again s: not again (no spam)", #E.saidBy == before)
local dan = E.player(44, "Dan", boardPart.Position + V3(-(G.Kiosk.Near + 8), 0, 2))
Greeters.step()
dan:SetAttribute("MoveWith", 11)
E.place(dan, boardPart.Position + V3(-(G.Kiosk.Near - 4), 0, 2))
Greeters.step()
check("a player on a move: no new contract for them", #E.saidBy == before)
dan:SetAttribute("MoveWith", nil)
E.place(dan, boardPart.Position + V3(-(G.Kiosk.Near + 8), 0, 2))
Greeters.step()
E.place(dan, boardPart.Position + V3(-(G.Kiosk.Near - 4), 0, 2))
Greeters.step()
check("Dan on no move comes up: his own greeting, her next line", saidBy(dispatcher, MoveStory.kioskLine(2), before) == 1 and heard(dan, MoveStory.kioskLine(2)))
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near + 8), 0, 0))
Greeters.step()
E.clock += G.Kiosk.Again
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near - 4), 0, 0))
Greeters.step()
check("Cid again after Again s: greeted again", saidBy(dispatcher, MoveStory.kioskLine(3), before) == 1)
-- 7.1 review: her kiosk line never cuts into her first day (server/Tutorial.luau's TutorialPhase and TutorialTalk)
local away, near = boardPart.Position + V3(-(G.Kiosk.Near + 8), 0, -2), boardPart.Position + V3(-(G.Kiosk.Near - 4), 0, -2)
local eve = E.player(55, "Eve", away)
eve:SetAttribute("TutorialPhase", "board")
Greeters.step()
before = #E.saidBy
local eveAt = #E.messages
E.place(eve, near)
Greeters.step()
check("7.1 review: a player on her first day with Marge (TutorialPhase) comes up to the kiosk: no kiosk line", #E.saidBy == before and not heard(eve, "💬", eveAt))
eve:SetAttribute("TutorialPhase", nil)
E.clock += 1
Greeters.step()
check("…the first day over while still by the kiosk: nothing then either (only on coming up to it)", #E.saidBy == before)
E.place(eve, away)
Greeters.step()
dispatcher:SetAttribute("TutorialTalk", E.clock + 5) -- (her tutorial bubble or a Talk with somebody: 5 s more)
E.place(eve, near)
Greeters.step()
E.clock += 2
Greeters.step()
check("…Eve comes up again while Marge's tutorial talk goes on (TutorialTalk): she waits", #E.saidBy == before and not heard(eve, "💬", eveAt))
E.clock += 4
Greeters.step()
check("…the talk over, Eve still by the kiosk: her line now, once", saidBy(dispatcher, MoveStory.kioskLine(4), before) == 1 and heard(eve, MoveStory.kioskLine(4), eveAt))
Greeters.step()
check("…and not again", #E.saidBy == before + 1)
dispatcher:Destroy()
E.clock += G.Kiosk.Again + G.Respawn
before = #E.saidBy
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near + 8), 0, 0))
Greeters.step()
E.place(cid, boardPart.Position + V3(-(G.Kiosk.Near - 4), 0, 0))
Greeters.step()
check("no dispatcher in the world: nobody speaks (and no Marge is made)", #E.saidBy == before)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
