-- 7.x farm move, chapter 1 (Walt's Farm) × 7.x van moves, end to end on the real art: the real server/Moving.luau,
-- MoveLobby, MoveGreeters, MoveHelper and MoveSites with the real shared/FurnitureLooks.luau, shared/HouseLayout.luau
-- (shared/Layouts/Farm.luau) and server/HouseInterior.luau (tests/run_tests.py builds them on the recorder
-- tests/runtime/MovingRuntime.luau's fakes stand on), the owner's car a ZDC Van (Config.Moving.Beds.zdcvan).
--   * Chapter 1 opens with the prologue done: the board's card lists Walt's Farm 🔒 (why, START refused); 7.2 review:
--     one piece of the prologue and FINISH is no chapter done; its ★ pieces a van can take (the record player, the
--     rocking horse: Grandpa's clock fits none) delivered and FINISH keep "done:prologue" in the crew's saves
--     (PlayerData.markStory; MoveStory.cleanSeen keeps it for the next load), then the board opens on Walt's Farm: its
--     clock (14 min, the horde at 3:30), its ★ pieces the chapter's keepsakes (seed 1921 of the farm's plan), the
--     lobby's van bay.
--   * The farm at the Old Farm (its Map.Places place): "Enter house" and "Enter barn"; Walt on his porch in his own look
--     (the hat, the check shirt, the moustache). In by the barn doors (by the plan's exits[2]); the hay wagon (bigDoor,
--     a pair piece) lifted with Bob: the farmhouse's Leave refuses it ("Too big — use the barn doors"), the barn's lets
--     it out at the barn doors; the Driver calls the van to the nearest door (the barn's, its back to it); too big for
--     the van's bay, the wagon rides on its hitch. Thunder's saddle carried out by the farmhouse past Walt ("Easy with
--     Thunder's saddle!") into the bed.
--   * Three trips to the Wall (each unloads the van, the soldier welcomes it, the move goes on; the third Grandma's
--     churn, the last ★ keepsake), the van wrecked with the milk churn in it (lost, the move goes on; CAR after VanAgain
--     s, the new van taken over), FINISH: paid for the three trips at the farm's pay (× its pay), chapter 1 done in the
--     crew's saves (7.2 review: not for Cy, who joined without the prologue), the interior gone, the van's back its own
--     again.
--   * Danny on a solo farm move: two ways; 8.3 hired and given the branding iron, with the van at the barn he goes in
--     and out by the barn doors for it (the nearest way he may take); 7.x Danny, a partner: he takes the far end of a pair piece
--     and comes out of the farmhouse's front door with Sol, then the hay wagon's (bigDoor) out of the barn doors to the
--     van's hitch.
--   * 8.1 walk-in doors (no E): a doormat at both doors; in by walking into the barn doors' zone; the hay wagon walked
--     into the farmhouse's way out is refused once ("Too big — use the barn doors"), nobody goes; walked into the barn
--     doors' way out, out at the barn with the other end at its far end in front (8.3: lined up), facing away; not
--     straight back in.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Greeters = require("./MoveGreetersServer")
local Config = require("./Config")
local Map = require("./Map")
local Rules = require("./MovingRules")
local MoveStory = require("./MoveStory")
local Looks = require("./MoveSiteLooks")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Moving
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace
E.carId = "zdcvan" -- (7.x van moves: every player's own car)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (the move's roamers far off)
end

local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and d.ActionText ~= nil and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function trigger(prompt: any, player: any)
	prompt.Triggered:Fire(player)
end
local function lobbyRequest(player: any, ...: any)
	E.Net.get("MoveLobby").OnServerEvent:Fire(player, ...)
end
local function spotModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function stateOf(player: any, spot: number): any
	local view = E.last(player, "Moving", "state")
	for _, item in (view and view.a and view.a.items) or {} do
		if item.spot == spot then
			return item
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
local function flat(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function tick(seconds: number?)
	E.clock += seconds or 0.3
	Moving.step()
end
-- A carried thing stays in front of its carrier (the weld, in Roblox: the recorder's weld is a record).
local function follow(model: any, player: any)
	model:PivotTo(E.rootOf(player).CFrame * M.CFrame.new(0, 0, -6))
end

-- the real art, its builds kept
local built: { any } = {}
Moving.useArt({
	looks = FurnitureLooks,
	layout = HouseLayout,
	interior = {
		slot = HouseInterior.slot,
		build = function(plan: any, origin: any): (any, any)
			E.built += 1
			table.insert(E.interiors, origin)
			local model, pieces = HouseInterior.build(plan, origin)
			table.insert(built, { model = model, plan = plan, origin = origin, pieces = pieces })
			return model, pieces
		end,
		destroy = function(model: any)
			E.destroyed += 1
			HouseInterior.destroy(model)
		end,
	},
})
-- Walt's look (the people's bodies record it)
local looks: { [string]: any } = {}
local spawn = E.Npcs.spawn
E.Npcs.spawn = function(look: any, at: any): any
	looks[look.name] = look
	return spawn(look, at)
end

local walt: any = nil
local farm: any = nil
for _, c in T.Contracts do
	if c.id == "walt" then
		farm = c
	end
end
local chapter = MoveStory.forContract("walt") :: any
local doors = Looks.siteDoors("farm", "farm") :: { any }
local front, barnDoor = doors[1], doors[2]
local board = V3(Map.Depot.x + T.Board[1], 3, Map.Depot.z + T.Board[2])
local home = Map.home(T.Contracts[1].home) :: any
E.truckAt = V3(home.park.x, 2, home.park.z)
local ann = E.player(11, "Ann", board + V3(-3, 0, 0))
local bob = E.player(22, "Bob", board + V3(-4, 0, 2))
E.crew[ann] = { bob }
Moving.start()
Greeters.step() -- (the greeters' loop: the soldier at the Wall)
local moves = workspace:FindFirstChild("Moves")
local boardPrompt = promptIn(moves:FindFirstChild("MovingBoard"), "Moving contracts")

-- Chapter 1 locked, then the prologue, then chapter 1 open ---------------------------------------------------------------

check("the farm contract: Walt's Farm, kind farm at the Old Farm, chapter 1's, its own clock and pay", farm ~= nil and farm.kind == "farm" and farm.place == "farm"
	and chapter.id == "ranch" and farm.time == 14 * 60 and farm.hordeAt == 3.5 * 60 and (farm.pay or 1) > 1)
trigger(boardPrompt, ann)
local card = E.last(ann, "Moving", "contract")
local listed: any = nil
for _, c in card.a.contracts or {} do
	if c.id == "walt" then
		listed = c
	end
end
check("a new crew: the board opens on Marge's House, Walt's Farm listed 🔒 (finish the prologue)", card.a.id == "marge" and listed ~= nil and listed.open == false
	and string.find(tostring(listed.why), "PROLOGUE", 1, true) ~= nil and #card.a.contracts == #T.Contracts)
E.request(ann, "card", "walt")
card = E.last(ann, "Moving", "contract")
check("…its card from the list: START waits (busy: why)", card.a.id == "walt" and type(card.a.busy) == "string" and string.find(card.a.busy, "PROLOGUE", 1, true) ~= nil)
E.request(ann, "start", "walt")
check("…START refused, no lobby", string.find(E.lastNotice(ann), "PROLOGUE", 1, true) ~= nil and E.last(ann, "MoveLobby", "lobby") == nil)
-- the prologue, a real piece of Marge's house to the Wall and FINISH
Moving.admin(ann, "start")
Moving.step()
local prologueBuild = built[#built]
local handSpot: any = nil
for _, s in prologueBuild.plan.spots do
	if not handSpot and FurnitureLooks.Items[s.item].class == "hand" then
		handSpot = s
	end
end
local outside = V3(home.door.x, 3, home.door.z) + V3(home.facing.x, 0, home.facing.z) * 3
E.place(ann, outside)
trigger(promptIn(moves:FindFirstChild("Move_marge"), "Enter house"), ann)
local piece = prologueBuild.pieces[handSpot.id]
E.place(ann, piece.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(piece, "Pick up"), ann)
E.place(ann, (prologueBuild.origin * M.CFrame.new(prologueBuild.plan.exit)).Position + V3(0, 3, 0))
trigger(promptIn(workspace, "Leave house"), ann)
local van = E.cars[ann]
check("7.x van moves: the prologue goes with Ann's own ZDC Van", van ~= nil and van.id == "zdcvan" and not van.lent)
van.model:SetAttribute("BackOpen", true)
E.place(ann, van.chassis:FindFirstChild("CargoDoor").WorldPosition + V3(0, 0, 2))
tick()
trigger(promptIn(van.model, "Load"), ann)
local wall = V3(Map.Depot.x + T.DropOff[1], 2, Map.Depot.z + T.DropOff[2])
van.chassis.CFrame = M.CFrame.new(wall.X + 4, wall.Y, wall.Z)
E.place(ann, wall + V3(0, 1, 0))
E.place(bob, wall + V3(3, 1, 0))
tick()
E.request(ann, "finish")
local result = E.last(ann, "Moving", "result")
check("the prologue's move delivered (a trip, FINISH)", result ~= nil and result.a.how == "done" and result.a.delivered == 1)
-- 7.2 review: one piece and FINISH is no chapter done: every ★ piece at the Wall whole (MovingRules.starsHome)
check("7.2 review: …one piece and FINISH: the prologue not done (its ★ pieces still at Marge's)", (E.story[ann] or {})["done:prologue"] ~= true
	and (E.story[bob] or {})["done:prologue"] ~= true)
-- The prologue again, its ★ pieces to the Wall this time: the record player and the rocking horse, a trip each. (Grandpa's
-- clock, 7.2 tall and never towed, fits no van, not even lying down: MovingRules.starsHome does not ask for it.)
Moving.admin(ann, "start")
Moving.step()
prologueBuild = built[#built]
local starred: { any } = {}
for _, s in prologueBuild.plan.spots do
	if s.star then
		table.insert(starred, s)
	end
end
local carried = 0
for _, s in starred do
	local item = FurnitureLooks.Items[s.item]
	if item.size.Y > 7 then
		continue -- (the clock)
	end
	van.chassis.CFrame = M.CFrame.new(home.park.x, 2, home.park.z)
	E.clock += 30
	E.place(ann, outside)
	tick()
	trigger(promptIn(moves:FindFirstChild("Move_marge"), "Enter house"), ann)
	local model = prologueBuild.pieces[s.id]
	E.place(ann, model.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(model, "Pick up"), ann)
	E.clock += 12
	E.place(ann, (prologueBuild.origin * M.CFrame.new(prologueBuild.plan.exit)).Position + V3(0, 3, 0))
	follow(model, ann)
	tick()
	trigger(promptIn(workspace, "Leave house"), ann)
	E.clock += 5
	van.model:SetAttribute("BackOpen", true)
	E.place(ann, van.chassis:FindFirstChild("CargoDoor").WorldPosition + V3(0, 0, 2))
	follow(model, ann)
	tick()
	trigger(promptIn(van.model, "Load"), ann)
	van.chassis.CFrame = M.CFrame.new(wall.X + 4, wall.Y, wall.Z)
	E.place(ann, wall + V3(0, 1, 0))
	E.place(bob, wall + V3(3, 1, 0))
	tick()
	carried += if model.destroyed then 1 else 0
end
E.request(ann, "finish")
result = E.last(ann, "Moving", "result")
check("the prologue again: its ★ pieces a van can take (the record player, the rocking horse) to the Wall whole, FINISH", #starred == 3 and carried == 2
	and result ~= nil and result.a.how == "done" and result.a.starsOut == 2, result and `{carried} carried, {result.a.how}, ★ {result.a.starsOut}`)
check("…chapter done in the crew's saves: \"done:prologue\" (PlayerData.markStory)", E.story[ann]["done:prologue"] == true and E.story[bob]["done:prologue"] == true)
check("…kept by the save: the next load still has it (MoveStory.cleanSeen, real saves only)", MoveStory.cleanSeen(E.story[ann])["done:prologue"] == true
	and string.find(MoveStory.encodeSeen(MoveStory.cleanSeen(E.story[ann])), "done:prologue", 1, true) ~= nil)
E.place(ann, board + V3(-3, 0, 0))
E.place(bob, board + V3(-4, 0, 2))
trigger(boardPrompt, ann)
card = E.last(ann, "Moving", "contract")
local plan = HouseLayout.plan(farm.seed, "farm")
local stars: { string } = {}
for _, s in plan.spots do
	if s.star then
		table.insert(stars, s.item)
	end
end
table.sort(stars)
local keep: { string } = {}
for index = 1, 3 do
	table.insert(keep, chapter.keepsakes[index].item)
end
table.sort(keep)
check("the board now opens on Walt's Farm (the next chapter), open, START free", card.a.id == "walt" and card.a.busy == nil and (function()
	for _, c in card.a.contracts do
		if c.id == "walt" then
			return c.open == true
		end
	end
	return false
end)())
check("…its clock: 14 min, the horde at 3:30; the real farm's pieces; the pay × the farm's", card.a.time == 14 * 60 and card.a.hordeAt == 210 and card.a.items == #plan.spots
	and card.a.estimate == Rules.estimate((function()
		local list = {}
		for _, s in plan.spots do
			table.insert(list, { id = s.id, item = s.item, room = s.room, star = s.star })
		end
		return list
	end)(), (function()
		local defs = {}
		for id, item in FurnitureLooks.Items do
			defs[id] = { id = id, name = item.name, icon = item.icon, size = { X = item.size.X, Y = item.size.Y, Z = item.size.Z }, class = item.class, weight = item.weight, value = item.value, fragile = item.fragile, room = item.room }
		end
		return defs
	end)(), farm.pay))
check(`the farm's ★ pieces (seed {farm.seed}) are chapter 1's first three keepsakes ({table.concat(stars, ", ")})`, table.concat(stars, ",") == table.concat(keep, ",")
	and #card.a.stars == 3)
check("…and Walt's briefing names them", (function()
	local said = ""
	for _, line in chapter.briefing do
		said ..= string.lower(line.text) .. " "
	end
	for index = 1, 3 do
		local name = string.gsub(string.lower(chapter.keepsakes[index].name), "^the ", "")
		if not string.find(said, name, 1, true) then
			return false
		end
	end
	return string.find(said, "guitar", 1, true) == nil
end)())
E.request(ann, "start", "walt")
local lobby = E.last(ann, "MoveLobby", "lobby")
local bay = T.Beds.zdcvan
check("START: the planning lobby, the van's bay in it (the ZDC Van's: 6.2 × 6.4)", lobby ~= nil and lobby.a ~= nil and lobby.a.card.id == "walt" and lobby.a.card.bed[1] == bay.Width
	and lobby.a.card.bed[2] == bay.Length and lobby.a.card.contracts == nil)
lobbyRequest(bob, "role", "mover")
lobbyRequest(bob, "ready", true)
-- (the van stays where it is: at the Wall, out already; parked at the barn by the Driver later)
lobbyRequest(ann, "launch")
local build = built[#built]
local origin = build.origin
check("LAUNCH: the real farm built (kind farm, its two exits), Ann's van still hers", build.plan.kind == "farm" and #build.plan.exits == 2 and E.cars[ann] == van
	and build.model:IsDescendantOf(workspace))
tick()

-- The farm at the Old Farm: two doors, Walt ---------------------------------------------------------------------------------

local site = moves:FindFirstChild("Move_walt")
local enterHouse, enterBarn = promptIn(site, "Enter house"), promptIn(site, "Enter barn")
check("the farm's two doors: Enter house at the farmhouse, Enter barn at the barn doors (the place's frame)", enterHouse ~= nil and enterBarn ~= nil
	and flat(enterHouse.Parent.Position, V3(front.x, 0, front.z)) < 1.5 and flat(enterBarn.Parent.Position, V3(barnDoor.x, 0, barnDoor.z)) < 1.5
	and enterHouse:GetAttribute("MoveOwner") == 11 and enterBarn:GetAttribute("MoveOwner") == 11)
local place: any = nil
for _, p in Map.Places do
	if p.id == "farm" then
		place = p
	end
end
check("…both at the Old Farm's place, in its yard", flat(V3(front.x, 0, front.z), V3(place.x, 0, place.z)) < 120 and flat(V3(barnDoor.x, 0, barnDoor.z), V3(place.x, 0, place.z)) < 120)
for _, child in workspace:GetChildren() do
	if child:GetAttribute("MoveGreeter") == "porch" and child:GetAttribute("MoveGreeterOf") == 11 and not child.destroyed then
		walt = child
	end
end
local look = looks.Walt
check("Walt greets at his farmhouse door, in his own look: the rancher's hat, a check shirt, a moustache", walt ~= nil and walt.Name == "Walt"
	and flat(walt.PrimaryPart.Position, V3(front.x, 0, front.z)) < 8 and look ~= nil and look.hat == "cowboy" and look.plaid ~= nil and look.moustache ~= nil
	and look.vest == nil)

-- In by the barn doors; the hay wagon refused at the farmhouse, out by the barn ------------------------------------------------

local barnOut = V3(barnDoor.out.x, 3, barnDoor.out.z)
E.place(ann, barnOut)
E.place(bob, barnOut + V3(3, 0, 0))
trigger(enterBarn, ann)
trigger(enterBarn, bob)
local entries = HouseLayout.entries(build.plan)
local barnEntry = (origin * entries[2]).Position
local barnExit = (origin * M.CFrame.new(build.plan.exits[2])).Position
check("Enter barn: in by the barn doors (near the plan's exits[2], not the front door)", (E.rootOf(ann).Position - barnEntry).Magnitude < 6
	and (E.rootOf(ann).Position - barnExit).Magnitude < 8 and (E.rootOf(ann).Position - (origin * build.plan.entry).Position).Magnitude > 30, E.rootOf(ann).Position)
local wagonSpot: any, saddleSpot: any, ironSpot: any, churnSpot: any, milkSpot: any = nil, nil, nil, nil, nil
for _, s in build.plan.spots do
	if s.item == "hay_wagon" then
		wagonSpot = s
	elseif s.item == "thunders_saddle" then
		saddleSpot = s
	elseif s.item == "branding_iron" then
		ironSpot = s
	elseif s.item == "grandmas_churn" then
		churnSpot = s
	elseif s.item == "milk_churn" then -- (7.2 review: a piece that is no ★, lost with the van)
		milkSpot = s
	end
end
check("the farm has the hay wagon (bigDoor), Thunder's saddle, the branding iron, Grandma's churn", wagonSpot and saddleSpot and ironSpot and churnSpot
	and FurnitureLooks.Items.hay_wagon.bigDoor == true and true or false)
local wagon = build.pieces[wagonSpot.id]
E.place(ann, wagon.PrimaryPart.Position + V3(0, 0, -6))
trigger(promptIn(wagon, "Lift"), ann)
E.place(bob, wagon.PrimaryPart.Position + V3(0, 0, 6))
trigger(promptIn(wagon, "Help lift"), bob)
check("Ann lifts the hay wagon, Bob takes the other end", ann.Character:GetAttribute("MoveCarry") == wagonSpot.id and bob.Character:GetAttribute("MoveCarry") == wagonSpot.id)
-- to the farmhouse's front door with it: refused
local houseExit = (origin * M.CFrame.new(build.plan.exits[1])).Position
E.clock += 12
E.place(ann, houseExit + V3(0, 3, 0))
E.place(bob, houseExit + V3(3, 3, 0))
follow(wagon, ann)
tick()
local before = #E.messages
trigger(promptIn(workspace, "Leave house"), ann)
check("the farmhouse's Leave with the hay wagon: refused, \"Too big — use the barn doors\"", heard(ann, "Too big — use the barn doors", before)
	and (E.rootOf(ann).Position - houseExit).Magnitude < 5 and ann.Character:GetAttribute("MoveCarry") == wagonSpot.id, E.lastNotice(ann))
E.clock += 12
E.place(ann, barnExit + V3(0, 3, 0))
E.place(bob, barnExit + V3(3, 3, 0))
follow(wagon, ann)
tick()
trigger(promptIn(workspace, "Leave by the barn doors"), ann)
follow(wagon, ann)
local apart = E.rootOf(bob).Position - E.rootOf(ann).Position
local annLook = E.rootOf(ann).CFrame.LookVector
check("…out by the barn doors: at the barn's outside, Bob with the other end at its far end, straight in front of her (8.3: lined up)",
	flat(E.rootOf(ann).Position, barnOut) < 4 and apart.X * annLook.X + apart.Z * annLook.Z > 3 and math.abs(apart.X * annLook.Z - apart.Z * annLook.X) < 1
	and ann.Character:GetAttribute("MoveCarry") == wagonSpot.id and bob.Character:GetAttribute("MoveCarry") == wagonSpot.id, E.rootOf(ann).Position)
-- the Driver calls the van to the nearest door: the barn's
E.request(ann, "call")
local park = V3(barnDoor.park.x, 0, barnDoor.park.z)
local cargoDoor = van.chassis:FindFirstChild("CargoDoor")
check("Call truck to door: the van at the barn doors' spot (the nearest door), its back to them", flat(van.chassis.Position, park) < 1
	and flat(cargoDoor.WorldPosition, V3(barnDoor.x, 0, barnDoor.z)) < flat(van.chassis.Position, V3(barnDoor.x, 0, barnDoor.z)) and heard(ann, "barn doors"))
van.model:SetAttribute("BackOpen", true)
E.clock += 3
E.place(ann, cargoDoor.WorldPosition + V3(1, 0, 0))
E.place(bob, cargoDoor.WorldPosition + V3(-2, 0, 0))
follow(wagon, ann)
tick()
trigger(promptIn(van.model, "Load"), ann)
local weld = wagon.PrimaryPart:FindFirstChildOfClass("WeldConstraint")
check("too big for the van's bay: the hay wagon rides on its hitch, behind the van", heard(ann, "hitched behind the van") and weld ~= nil and weld.Part0 == van.chassis
	and flat(wagon.PrimaryPart.Position, cargoDoor.WorldPosition) < flat(wagon.PrimaryPart.Position, van.chassis.Position)
	and ann.Character:GetAttribute("MoveCarry") == nil and bob.Character:GetAttribute("MoveCarry") == nil, E.lastNotice(ann))
tick()
check("…in the van's load (state truck), the bed still empty", stateOf(ann, wagonSpot.id).state == "truck" and (E.last(ann, "Moving", "state").a.fill or 1) == 0)

-- Thunder's saddle out by the farmhouse, past Walt -------------------------------------------------------------------------

trigger(enterBarn, ann)
local saddle = build.pieces[saddleSpot.id]
E.place(ann, saddle.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(saddle, "Pick up"), ann)
E.clock += 12
E.place(ann, houseExit + V3(0, 3, 0))
follow(saddle, ann)
tick()
trigger(promptIn(workspace, "Leave house"), ann)
follow(saddle, ann)
local frontOut = V3(front.out.x, 3, front.out.z)
check("Thunder's saddle (not bigDoor) may leave by the farmhouse: out at its front door", flat(E.rootOf(ann).Position, frontOut) < 4 and ann.Character:GetAttribute("MoveCarry") == saddleSpot.id,
	E.rootOf(ann).Position)
for _ = 1, 12 do
	tick(1)
	follow(saddle, ann)
end
local said = false
for _, entry in E.saidBy do
	if entry.npc == walt and entry.text == "Easy with Thunder's saddle!" then
		said = true
	end
end
check("Walt's hello, then his ★ line for the saddle: \"Easy with Thunder's saddle!\"", said and E.saidSince(chapter.greeter.hello[1], 0))
E.clock += 15
E.place(ann, cargoDoor.WorldPosition + V3(1, 0, 0))
follow(saddle, ann)
tick()
trigger(promptIn(van.model, "Load"), ann)
check("…into the van's bed", stateOf(ann, saddleSpot.id) ~= nil and heard(ann, "loaded"), E.lastNotice(ann))

-- Trip 1, trip 2 ------------------------------------------------------------------------------------------------------------

van.chassis.CFrame = M.CFrame.new(wall.X + 4, wall.Y, wall.Z)
E.place(ann, wall + V3(0, 1, 0))
E.place(bob, wall + V3(3, 1, 0))
local said0 = #E.said
tick()
check("trip 1 at the Wall: the saddle and the hitched wagon delivered, the move goes on", heard(ann, "Trip 1") and stateOf(ann, wagonSpot.id).state == "delivered"
	and stateOf(ann, saddleSpot.id).state == "delivered" and E.last(ann, "Moving", "state").a.trips == 1 and E.last(ann, "Moving", "result") == result
	and wagon.destroyed == true and saddle.destroyed == true)
check("…the soldier welcomes the van", E.saidSince(MoveStory.Wall.welcome, said0))
van.chassis.CFrame = M.CFrame.new(park.X, 2, park.Z) * M.CFrame.Angles(0, math.pi, 0)
E.clock += 30
E.place(ann, barnOut)
tick()
trigger(enterBarn, ann)
local iron = build.pieces[ironSpot.id]
E.place(ann, iron.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(iron, "Pick up"), ann)
E.clock += 12
E.place(ann, barnExit + V3(0, 3, 0))
follow(iron, ann)
tick()
trigger(promptIn(workspace, "Leave by the barn doors"), ann)
E.clock += 5
E.place(ann, cargoDoor.WorldPosition + V3(1, 0, 0))
follow(iron, ann)
tick()
trigger(promptIn(van.model, "Load"), ann)
van.chassis.CFrame = M.CFrame.new(wall.X + 4, wall.Y, wall.Z)
E.place(ann, wall + V3(0, 1, 0))
E.place(bob, wall + V3(3, 1, 0))
tick()
check("trip 2: the branding iron delivered", heard(ann, "Trip 2") and stateOf(ann, ironSpot.id).state == "delivered" and E.last(ann, "Moving", "state").a.trips == 2)

-- Trip 3: Grandma's churn; then the van wrecked with the milk churn in it --------------------------------------------------------

-- A piece of the farmhouse carried out by its front door into the van parked there.
local function fromHouse(spot: any): any
	van.chassis.CFrame = M.CFrame.new(front.park.x, 2, front.park.z) * M.CFrame.Angles(0, math.pi, 0)
	E.clock += 30
	E.place(ann, frontOut)
	tick()
	trigger(enterHouse, ann)
	local piece = build.pieces[spot.id]
	E.place(ann, piece.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(piece, "Pick up"), ann)
	E.clock += 12
	E.place(ann, houseExit + V3(0, 3, 0))
	follow(piece, ann)
	tick()
	trigger(promptIn(workspace, "Leave house"), ann)
	E.clock += 5
	E.place(ann, cargoDoor.WorldPosition + V3(1, 0, 0))
	follow(piece, ann)
	tick()
	trigger(promptIn(van.model, "Load"), ann)
	tick()
	return piece
end
local churn = fromHouse(churnSpot)
check("Grandma's churn in the van", stateOf(ann, churnSpot.id).state == "truck", stateOf(ann, churnSpot.id) and stateOf(ann, churnSpot.id).state)
van.chassis.CFrame = M.CFrame.new(wall.X + 4, wall.Y, wall.Z)
E.place(ann, wall + V3(0, 1, 0))
E.place(bob, wall + V3(3, 1, 0))
tick()
check("trip 3: Grandma's churn delivered (every ★ keepsake at the Wall)", heard(ann, "Trip 3") and stateOf(ann, churnSpot.id).state == "delivered" and churn.destroyed == true)
local milk = fromHouse(milkSpot)
check("the milk churn in the van", stateOf(ann, milkSpot.id).state == "truck", stateOf(ann, milkSpot.id) and stateOf(ann, milkSpot.id).state)
van.wrecked = true
tick()
check("7.x van moves: the van wrecked: the milk churn in it lost (condition 0), the move goes on", heard(ann, "The van is wrecked") and stateOf(ann, milkSpot.id).state == "lost"
	and stateOf(ann, milkSpot.id).condition == 0 and milk.destroyed == true and E.last(ann, "Moving", "result") == result and E.last(ann, "Moving", "state").a.truck == false)
check("…CAR waits VanAgain s", string.find(E.Vehicles.spawn(ann, false, nil) or "", "comes back", 1, true) ~= nil)
E.now += T.VanAgain
E.truckAt = park
E.Vehicles.placeNear(ann, nil)
tick()
local van2 = E.cars[ann]
check("…then CAR brings a van and the move takes it over (an empty bed, its prompts)", van2 ~= van and heard(ann, "van is back") and promptIn(van2.model, "Load") ~= nil
	and E.last(ann, "Moving", "state").a.truck == true and E.last(ann, "Moving", "state").a.fill == 0)

-- FINISH ------------------------------------------------------------------------------------------------------------------------

E.place(bob, park + V3(3, 3, 0))
E.place(ann, park + V3(0, 3, 3))
-- 7.2 review: Cy joins Ann's crew for the end, the prologue not done: chapter 1 is not his (no skipping ahead)
local cy = E.player(66, "Cy", park + V3(-3, 3, 0))
E.crew[ann] = { bob, cy }
tick()
local view = E.last(ann, "Moving", "state").a
local expected = 0
for _, item in view.items do
	if item.state == "delivered" then
		expected += item.value * item.condition * T.Pay.Scale * farm.pay * (if item.star then T.Pay.Star else 1)
	end
end
E.request(ann, "finish")
result = E.last(ann, "Moving", "result")
check("FINISH: done, paid for the three trips (4 delivered, every ★)", result ~= nil and result.a.how == "done" and result.a.delivered == 4 and result.a.trips == 3
	and result.a.starsOut == 3 and result.a.pay > 0 and result.a.crew == 3, result and `{result.a.how} {result.a.delivered} {result.a.trips} {result.a.crew}`)
check("…at the farm's pay (× its pay, ★ × Star)", math.abs(result.a.base + result.a.starBonus - expected) < 5, `{result.a.base + result.a.starBonus} vs {expected}`)
check("…chapter 1 done in the crew's saves (\"done:ranch\")", E.story[ann]["done:ranch"] == true and E.story[bob]["done:ranch"] == true)
check("7.2 review: …not for Cy, who joined without the prologue (paid, but no chapter skipped)", (E.story[cy] or {})["done:ranch"] ~= true
	and (E.story[cy] or {})["done:prologue"] ~= true)
check("…the farm's interior gone, the van's back its own again", build.model.Parent == nil and van2.model:GetAttribute("BackCrew") == nil
	and van2.chassis:FindFirstChild("CargoDoor"):FindFirstChild("BackPrompt").Enabled == true and ann:GetAttribute("MoveWith") == nil)

-- Danny on a solo farm move: the nearest way he may take ------------------------------------------------------------------------

local walker = {
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local step = math.min(length, speed * dt)
			root.CFrame = M.CFrame.new(here.X + way.X / length * step, here.Y, here.Z + way.Z / length * step)
		end
		body.walking = true
	end,
	halt = function(body: any)
		body.walking = false
	end,
}
MoveHelper.useMover(walker)
local sol = E.player(55, "Sol", barnOut + V3(6, 0, 0))
E.truckAt = park
E.Vehicles.placeNear(sol, nil)
E.cars[sol].chassis.CFrame = M.CFrame.new(park.X, 2, park.Z) * M.CFrame.Angles(0, math.pi, 0)
Moving.admin(sol, "farm")
Moving.step()
local danny = MoveHelper.find(sol)
local solBuild = built[#built]
check("a solo farm move: Danny comes, with both ways (the front door, the barn doors)", danny ~= nil and #danny.ways == 2 and solBuild.plan.kind == "farm")
E.cars[sol].model:SetAttribute("BackOpen", true)
-- (8.3 Danny for hire: Sol hires him and gives him the branding iron, from beside it inside, then waits outside)
E.request(sol, "helper", "hire")
local solIron = solBuild.pieces[ironSpot.id]
local outsideSol = E.rootOf(sol).Position
E.place(sol, solIron.PrimaryPart.Position + V3(3, 0, 0))
E.request(sol, "helper", "assign", solIron)
E.place(sol, outsideSol)
check("8.3 Sol hires Danny and gives him the branding iron", danny.hirer == sol and danny.queue[1] == ironSpot.id, danny.queue[1])
local solOrigin = solBuild.origin
local solBarnEntry = (solOrigin * HouseLayout.entries(solBuild.plan)[2]).Position
local solFrontEntry = (solOrigin * solBuild.plan.entry).Position
local cameIn: any, cameOut: any, ironIn = nil, nil, false
local wasInside = false
for _ = 1, 2400 do
	E.clock += 0.1
	MoveHelper.step(0.1)
	if danny.body then
		local root = danny.body.root
		local inside = (root.Position - solOrigin.Position).Magnitude < 400
		if inside and not wasInside and not cameIn then
			cameIn = root.Position
		elseif not inside and wasInside and cameIn and not cameOut then
			cameOut = root.Position
		end
		wasInside = inside
		local spot, role = Rules.holding(danny.s.move, danny.id)
		local model = if spot and role == "carrier" then spotModel(spot) else nil
		if model then
			model:PivotTo(root.CFrame * M.CFrame.new(0, 0, -1.5))
		end
	end
	if math.floor(E.clock * 10 + 0.5) % 2 == 0 then
		Moving.step()
	end
	local thing = danny.s.move.things[ironSpot.id]
	if thing and thing.state == "truck" then
		ironIn = true
		break
	end
end
check("Danny goes in by the barn doors (the nearest way to the branding iron, his list's)", cameIn ~= nil and (cameIn - solBarnEntry).Magnitude < 6 and (cameIn - solFrontEntry).Magnitude > 30,
	cameIn)
check("…comes out by them with it and loads it into the van at the barn", cameOut ~= nil and flat(cameOut, barnOut) < 6 and ironIn, cameOut)

-- 7.x Danny carries with you on the farm: a pair piece out of the farmhouse's front door, the hay wagon (bigDoor) out of
-- the barn doors and onto the van's hitch; he holds the far end through either door (no keep in this walker: his root is
-- put at the far end each step, as his constraints hold him in Roblox).
local H = Config.MoveHelper
local s = danny.s
local function hold(model: any) -- (Sol's weld, the root set straight)
	model.PrimaryPart.CFrame = E.rootOf(sol).CFrame * M.CFrame.new(0, 0, -(model.PrimaryPart.Size.Z / 2 + 1))
end
local function steps(seconds: number, done: (() -> boolean)?, carried: any?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		if carried then
			hold(carried)
		end
		MoveHelper.step(0.1)
		local spot, role = Rules.holding(s.move, danny.id)
		local own = if spot and role == "carrier" then spotModel(spot) else nil
		if own and danny.body then
			own.PrimaryPart.CFrame = danny.body.root.CFrame * M.CFrame.new(0, 0, -1.5)
		end
		if index % 2 == 0 then
			Moving.step()
		end
		if done and done() then
			return true
		end
	end
	return done == nil
end
local function farEndOf(model: any): any
	return (model.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(model.PrimaryPart.Size.Z / 2 + H.Standoff))).Position
end
local function heldBy(spot: number): boolean
	local held, role = Rules.holding(s.move, danny.id)
	return held == spot and role == "helper"
end
-- a pair piece the farmhouse's front door lets out (not the hay wagon)
local benchSpot: any = nil
for _, sp in solBuild.plan.spots do
	local def = FurnitureLooks.Items[sp.item]
	if not benchSpot and def and def.class == "pair" and not def.bigDoor and table.find(Moving.helperExits(s, sp.id), 1) then
		benchSpot = sp
	end
end
check("the farm has a pair piece that leaves by the farmhouse's front door", benchSpot ~= nil, benchSpot and benchSpot.item)
local bench = solBuild.pieces[benchSpot.id]
E.place(sol, bench.PrimaryPart.Position + V3(0, 0, 4))
trigger(promptIn(bench, "Lift"), sol)
check(`8.3 Sol lifts the {benchSpot.item}: no drag alone, she calls Danny and waits`, sol.Character:GetAttribute("MoveCarry") == nil and danny.call ~= nil)
local took = 0
local helped = steps(20, function() -- (8.3: he walks over, the piece on the floor meanwhile)
	took += 0.1
	return heldBy(benchSpot.id)
end)
check(`8.3 Danny walks to the far end of the {benchSpot.item} on the farm: up together`, helped and sol.Character:GetAttribute("MoveCarry") == benchSpot.id, took)
steps(0.6, nil, bench)
local solFrontExit = (solOrigin * M.CFrame.new(solBuild.plan.exits[1])).Position
E.clock += 12 -- (the pace check's allowance: the test jumps)
E.place(sol, solFrontExit + V3(0, 3, 0))
steps(0.2, nil, bench)
trigger(promptIn(workspace, "Leave house"), sol)
steps(0.3, nil, bench)
check("…out of the farmhouse's front door together: Sol at its outside, Danny at the far end", flat(E.rootOf(sol).Position, V3(front.out.x, 0, front.out.z)) < 4
	and heldBy(benchSpot.id) and flat(danny.body.root.Position, farEndOf(bench)) < 0.05, flat(danny.body.root.Position, farEndOf(bench)))
E.Net.get("PutDown").OnServerEvent:Fire(sol)
steps(0.3)
check("…set down outside: his hands free, his arms down, Sol's grip as before", Rules.holding(s.move, danny.id) == nil and danny.body.model:GetAttribute("Carrying") == nil
	and sol.Character:GetAttribute("GripSteady") == nil)
-- the hay wagon: only the barn doors let it out; he holds the far end through them and to the hitch
local wagonId: any = nil
for _, sp in solBuild.plan.spots do
	if sp.item == "hay_wagon" then
		wagonId = sp.id
	end
end
local solWagon = solBuild.pieces[wagonId]
check("…the hay wagon may leave by the barn doors only", wagonId ~= nil and #Moving.helperExits(s, wagonId) == 1 and Moving.helperExits(s, wagonId)[1] == 2)
E.clock += 12
E.place(sol, solWagon.PrimaryPart.Position + V3(0, 0, 7))
trigger(promptIn(solWagon, "Lift"), sol)
took = 0
helped = steps(20, function() -- (8.3: a call: he walks over)
	took += 0.1
	return heldBy(wagonId)
end)
check("8.3 Danny walks to the hay wagon's far end: up together", helped and sol.Character:GetAttribute("MoveCarry") == wagonId, took)
steps(0.6, nil, solWagon)
local solBarnExit = (solOrigin * M.CFrame.new(solBuild.plan.exits[2])).Position
E.clock += 12
E.place(sol, solBarnExit + V3(0, 3, 0))
steps(0.2, nil, solWagon)
trigger(promptIn(workspace, "Leave by the barn doors"), sol)
steps(0.3, nil, solWagon)
check("…out of the barn doors together: Sol at the barn's outside, Danny at the far end", flat(E.rootOf(sol).Position, barnOut) < 4 and heldBy(wagonId)
	and flat(danny.body.root.Position, farEndOf(solWagon)) < 0.05, flat(danny.body.root.Position, farEndOf(solWagon)))
local solVan = E.cars[sol]
local solBack = solVan.chassis:FindFirstChild("CargoDoor").WorldPosition
E.clock += 12
E.place(sol, V3(solBack.X, 3, solBack.Z) + (V3(solBack.X, 0, solBack.Z) - V3(solVan.chassis.Position.X, 0, solVan.chassis.Position.Z)).Unit * 3)
-- (8.1: never put at the far end while he holds it: he walks after Sol's jump there at his top speed)
local caughtUp = steps(4, function()
	return flat(danny.body.root.Position, farEndOf(solWagon)) < 0.05
end, solWagon)
check("…to the van at the barn together, its back open", heldBy(wagonId) and caughtUp and flat(danny.body.root.Position, farEndOf(solWagon)) < 0.05
	and solVan.model:GetAttribute("BackOpen") == true)
trigger(promptIn(solVan.model, "Load"), sol)
steps(0.3)
check("…Sol loads it: on the van's hitch, Danny's hands free", s.move.things[wagonId].state == "truck" and s.move.hitch == wagonId
	and Rules.holding(s.move, danny.id) == nil, E.lastNotice(sol))
-- the ZDC Van's back shut: he opens it himself when he comes with his next piece (8.3: one Sol gives him), and it
-- goes in (helperLoad)
solVan.model:SetAttribute("BackOpen", false)
local nextPiece: any = nil
for _, sp in solBuild.plan.spots do
	local def = FurnitureLooks.Items[sp.item]
	if not nextPiece and def and def.class == "hand" and s.move.things[sp.id].state == "home" and table.find(Moving.helperExits(s, sp.id), 2) then
		nextPiece = sp
	end
end
local nextModel = solBuild.pieces[nextPiece.id]
E.place(sol, nextModel.PrimaryPart.Position + V3(3, 0, 0))
E.request(sol, "helper", "assign", nextModel)
E.place(sol, barnOut + V3(-20, 0, 0)) -- (out of the way, hands free)
local saidBefore = #E.said
local loadedBefore = Rules.counts(s.move).out
local opened = steps(90, function()
	return solVan.model:GetAttribute("BackOpen") == true and Rules.counts(s.move).out > loadedBefore
end)
check("the ZDC Van's back shut: Danny opens it himself (\"I'll get the doors!\") and loads his piece", opened and E.saidSince("I'll get the doors!", saidBefore),
	Rules.counts(s.move).out)
Moving.admin(sol, "end")

-- 8.1 walk-in doors on the farm (no E): a doormat at both doors; Uma and Vic walk in by the barn doors' zone; the hay wagon
-- (bigDoor) walked into the farmhouse's way out: refused once with the same words, nobody goes; walked into the barn
-- doors' way out: out at the barn, the other end at its far end in front (8.3: lined up), facing away from the doors.
do
	local D = T.Doors
	local THROUGH = math.max(D.Dwell, D.Open) + 0.01 -- (8.3: in the zone facing the door Dwell s, its leaf open Open s)
	local uma = E.player(166, "Uma", board + V3(-2, 0, 5))
	local vic = E.player(167, "Vic", board + V3(-3, 0, 6))
	E.crew[uma] = { vic }
	E.truckAt = park
	Moving.admin(uma, "farm")
	Moving.step()
	local b = built[#built]
	local o = b.origin
	local up = V3(0, Config.Furniture.EntryUp, 0)
	local barnFacing = V3(barnDoor.fx, 0, barnDoor.fz)
	local barnSide = V3(-barnFacing.Z, 0, barnFacing.X)
	local barnFoot = V3(barnDoor.x, Map.RoadTop, barnDoor.z)
	local entries = HouseLayout.entries(b.plan)
	local function stand(player: any, at: any, look: any)
		E.rootOf(player).CFrame = M.CFrame.lookAt(at, at + look)
	end
	local function isIn(player: any): boolean
		return (E.rootOf(player).Position - o.Position).Magnitude < 400
	end
	local function times(player: any, text: string, since: number): number
		local n = 0
		for index = since + 1, #E.messages do
			local m = E.messages[index]
			n += if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then 1 else 0
		end
		return n
	end
	-- a way out inside: its exit (a body's height over the floor) and the flat way into the room from it
	local function wayIn(n: number): (any, any)
		local exit = (o * M.CFrame.new(b.plan.exits[n])).Position
		local step = (o * entries[n]).Position - exit
		return exit, V3(step.X, 0, step.Z).Unit
	end
	local function mats(model: any, text: string): number
		local n = 0
		for _, d in model:GetDescendants() do
			local gui = if d.Name == "WalkInMat" and not d.destroyed then d:FindFirstChildOfClass("SurfaceGui") else nil
			local label = gui and gui:FindFirstChildOfClass("TextLabel")
			n += if label and label.Text == text and d.Transparency == 0 then 1 else 0
		end
		return n
	end
	check("8.1 walk-in doors: a doormat at both farm doors outside (▲ IN), one by both ways out inside (▲ OUT)", mats(moves:FindFirstChild("Move_walt"), "▲ IN") == 2
		and mats(b.model, "▲ OUT") == 2)
	check("…the E prompts there, off", not promptIn(moves:FindFirstChild("Move_walt"), "Enter barn").Enabled and not promptIn(workspace, "Leave by the barn doors").Enabled)

	stand(uma, barnFoot + up + barnFacing * 2, -barnFacing)
	stand(vic, barnFoot + up + barnFacing * 2 + barnSide * 3, -barnFacing)
	tick(0.1)
	tick(THROUGH)
	check("walked into the barn doors' zone: both in by the barn's entry (no E)", isIn(uma) and isIn(vic) and (E.rootOf(uma).Position - (o * entries[2]).Position).Magnitude < 6,
		E.rootOf(uma).Position)

	local wagonId: any = nil
	for _, sp in b.plan.spots do
		if sp.item == "hay_wagon" then
			wagonId = sp.id
		end
	end
	local wagon = b.pieces[wagonId]
	E.place(uma, wagon.PrimaryPart.Position + V3(0, 0, -6))
	trigger(promptIn(wagon, "Lift"), uma)
	E.place(vic, wagon.PrimaryPart.Position + V3(0, 0, 6))
	trigger(promptIn(wagon, "Help lift"), vic)
	check("(Uma lifts the hay wagon, Vic the other end)", uma.Character:GetAttribute("MoveCarry") == wagonId and vic.Character:GetAttribute("MoveCarry") == wagonId,
		`{E.lastNotice(uma)} / {E.lastNotice(vic)} / {uma.Character:GetAttribute("MoveCarry")} {vic.Character:GetAttribute("MoveCarry")}`)

	-- to the farmhouse's way out with it, facing its door: refused, once
	local houseExit, houseInto = wayIn(1)
	local houseSide = V3(-houseInto.Z, 0, houseInto.X)
	E.clock += 12 -- (the pace check's allowance: the test jumps)
	stand(uma, houseExit + houseInto * 1, -houseInto)
	stand(vic, houseExit + houseInto * 1 + houseSide * 5, -houseInto) -- (beside her, out of the doorway's zone)
	follow(wagon, uma)
	local since = #E.messages
	tick(0.1)
	tick(THROUGH)
	tick(0.4)
	tick(0.4)
	check("the hay wagon walked into the farmhouse's way out: refused once, \"Too big — use the barn doors\", nobody goes", isIn(uma) and isIn(vic)
		and times(uma, "Too big — use the barn doors", since) == 1 and uma.Character:GetAttribute("MoveCarry") == wagonId
		and vic.Character:GetAttribute("MoveCarry") == wagonId, times(uma, "Too big", since))

	-- to the barn doors' way out with it: out at the barn, Vic with the other end
	local barnExit, barnInto = wayIn(2)
	local side = V3(-barnInto.Z, 0, barnInto.X)
	E.clock += 12
	stand(uma, barnExit + barnInto * 1, -barnInto)
	stand(vic, barnExit + barnInto * 1 + side * 7.5, -barnInto)
	follow(wagon, uma)
	tick(0.1)
	tick(THROUGH)
	follow(wagon, uma)
	local barnOut = V3(barnDoor.out.x, 0, barnDoor.out.z)
	local apart = E.rootOf(vic).Position - E.rootOf(uma).Position
	local look = E.rootOf(uma).CFrame.LookVector
	check("…walked into the barn doors' way out with it: out at the barn, Vic at its far end straight in front of her (8.3: lined up)", not isIn(uma)
		and not isIn(vic) and flat(E.rootOf(uma).Position, barnOut) < 1 and apart.X * look.X + apart.Z * look.Z > 3
		and math.abs(apart.X * look.Z - apart.Z * look.X) < 1 and uma.Character:GetAttribute("MoveCarry") == wagonId
		and vic.Character:GetAttribute("MoveCarry") == wagonId, E.rootOf(uma).Position)
	check("…facing away from the barn doors, clear of their zone", E.rootOf(uma).CFrame.LookVector:Dot(barnFacing) > 0.99
		and (E.rootOf(uma).Position - barnFoot):Dot(barnFacing) > D.Depth)
	-- no way straight back: Rearm s and out of the zone first
	stand(uma, barnFoot + up + barnFacing * 2, -barnFacing)
	follow(wagon, uma)
	tick(0.1)
	tick(THROUGH)
	tick(0.3)
	check("…and not straight back in (Rearm s)", not isIn(uma))
	E.Net.get("PutDown").OnServerEvent:Fire(uma)
	Moving.admin(uma, "end")
	E.leave(uma)
	E.leave(vic)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
