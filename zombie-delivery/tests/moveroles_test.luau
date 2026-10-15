-- 7.0 planning: shared/MoveRoles.luau, the planning lobby's rules and the roles' (pure; tests/run_tests.py runs it
-- with the real Config). The lobby: roles one each, READY, LAUNCH (solo at once), the crew coming and going; on a move:
-- the switch and its cooldown, the Mover's carry, the climb, the Guard's hits and barricades, the Driver's truck and
-- call; the quick chat's lines; every refusal has words. The owner took the Technician out: three roles, one each while
-- there are no more than three players, doubles beyond that; no lock, no fuse box.
-- 8.8 (the owner: "I don't want roles in the game. Everyone is simply the same."): all of the above is the city's with
-- Config.MoveRoles.On (MoveRoles.on); the sandbox has no roles whatever the switch says: the lobby gives none and waits
-- only for READY, nobody switches, carries a pair piece alone or climbs at full pace, no damage bonus, no truck's cut,
-- no barricade, anybody calls the van once a move; the city with the switch off the same.
local MoveRoles = require("./MoveRoles")
local Config = require("./Config")
local sandboxOn = Config.Sandbox.On
Config.Sandbox.On = false -- (the city's roles first, the switch on; 8.8: the sandbox's none at the end)

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

local R = Config.MoveRoles

-- The roles ------------------------------------------------------------------------------------------------------------

check("three roles in the lobby's order", #MoveRoles.Order == 3 and MoveRoles.Order[1] == "driver" and MoveRoles.Order[2] == "mover" and MoveRoles.Order[3] == "guard")
check("no Technician any more: no role, no loadout, no lock or fuse rules, no numbers", MoveRoles.get("tech") == nil and MoveRoles.loadout("tech") == ""
	and (MoveRoles :: any).openDoor == nil and (MoveRoles :: any).newDoor == nil and (MoveRoles :: any).canFuse == nil and (Config.MoveRoles :: any).Tech == nil)
local complete = true
for _, id in MoveRoles.Order do
	local def = MoveRoles.get(id)
	if not def or def.id ~= id or def.name == "" or def.icon == "" or def.blurb == "" or def.hint == "" or #def.color ~= 3 or MoveRoles.loadout(id) == "" then
		complete = false
	end
end
check("each has a name, an icon, a colour, a blurb, a hint and a loadout line", complete)
check("no such role", MoveRoles.get("pilot") == nil and MoveRoles.get(nil) == nil and MoveRoles.get(3) == nil and MoveRoles.loadout("pilot") == "")
check("the loadout lines say the numbers", string.find(MoveRoles.loadout("guard"), "+50%", 1, true) ~= nil and string.find(MoveRoles.loadout("mover"), "+15%", 1, true) ~= nil
	and string.find(MoveRoles.loadout("driver"), "40%", 1, true) ~= nil and string.find(MoveRoles.loadout("guard"), "2 barricades", 1, true) ~= nil)
check("the numbers", R.Switch >= 10 and R.Driver.TruckDamage > 0 and R.Driver.TruckDamage < 1 and R.Mover.Alone > Config.Moving.Speed.Drag and R.Mover.Carry > 1
	and R.Mover.Climb < 1 and R.Guard.Damage > 1 and R.Guard.Barricades >= 1 and R.Guard.Hp > 0
	and Config.Robust.Limits.MoveLobby > 0 and Config.Robust.Limits.QuickChat > 0 and Config.Robust.Limits.QuickChat <= 1)

-- The lobby ------------------------------------------------------------------------------------------------------------

local ANN, BOB, CID, DAN, EVE = 1, 2, 3, 4, 5
local lobby = MoveRoles.newLobby(ANN, "marge", 100)
check("a new lobby: the owner in it with the first role", #lobby.members == 1 and lobby.members[1] == ANN and lobby.roles[ANN] == "driver" and lobby.openedAt == 100
	and lobby.contract == "marge")
check("solo: LAUNCH at once (READY is LAUNCH)", MoveRoles.canLaunch(lobby, ANN) == true and MoveRoles.waiting(lobby) == 0)
check("the crew joins: a free role each, NOT READY", MoveRoles.sync(lobby, { ANN, BOB }) == true and lobby.roles[BOB] == "mover" and lobby.ready[BOB] == false
	and #lobby.members == 2)
check("nothing new: no change", MoveRoles.sync(lobby, { ANN, BOB }) == false)
check("the owner stays first whatever the order", MoveRoles.sync(lobby, { BOB, ANN }) == false and lobby.members[1] == ANN)
local ok, why = MoveRoles.canLaunch(lobby, ANN)
check("LAUNCH waits for the crew's READY", ok == false and why == "notready" and MoveRoles.waiting(lobby) == 1)
ok, why = MoveRoles.canLaunch(lobby, BOB)
check("only the owner launches", ok == false and why == "owner")
ok, why = MoveRoles.choose(lobby, BOB, "driver")
check("one role each: taken", ok == false and why == "taken" and lobby.roles[BOB] == "mover")
check("taken: somebody else has it", MoveRoles.taken(lobby, "driver", BOB) and not MoveRoles.taken(lobby, "driver", ANN) and not MoveRoles.taken(lobby, "guard", BOB))
ok, why = MoveRoles.choose(lobby, BOB, "pilot")
check("no such role", ok == false and why == "role")
ok, why = MoveRoles.choose(lobby, BOB, "tech")
check("the Technician is no role any more", ok == false and why == "role" and lobby.roles[BOB] == "mover")
ok, why = MoveRoles.choose(lobby, DAN, "guard")
check("not a member", ok == false and why == "member")
MoveRoles.setReady(lobby, BOB, true)
ok = MoveRoles.choose(lobby, BOB, "guard")
check("a free role: taken; READY goes off with the change", ok and lobby.roles[BOB] == "guard" and lobby.ready[BOB] == false)
check("the same role again: fine, READY kept", (function()
	MoveRoles.setReady(lobby, BOB, true)
	local same = MoveRoles.choose(lobby, BOB, "guard")
	return same and lobby.ready[BOB] == true
end)())
ok, why = MoveRoles.setReady(lobby, ANN, true)
check("the owner has no READY (they launch)", ok == false and why == "owner")
ok, why = MoveRoles.setReady(lobby, DAN, true)
check("a stranger has no READY", ok == false and why == "member")
check("a third player: the last free role, NOT READY, LAUNCH waits", MoveRoles.sync(lobby, { ANN, BOB, CID }) and lobby.roles[CID] == "mover" and lobby.ready[CID] == false
	and MoveRoles.canLaunch(lobby, ANN) == false and MoveRoles.waiting(lobby) == 1)
ok, why = MoveRoles.choose(lobby, CID, "guard")
check("three players, three roles: one each (no doubles)", ok == false and why == "taken" and not MoveRoles.doubles(3) and MoveRoles.doubles(4))
MoveRoles.setReady(lobby, CID, true)
check("everybody READY: LAUNCH", MoveRoles.canLaunch(lobby, ANN) == true and MoveRoles.waiting(lobby) == 0)
MoveRoles.setReady(lobby, CID, false)
check("one takes it back: LAUNCH waits", MoveRoles.canLaunch(lobby, ANN) == false and MoveRoles.waiting(lobby) == 1)
MoveRoles.setReady(lobby, CID, true)
check("a fourth player: doubles allowed, the first role, any role", MoveRoles.sync(lobby, { ANN, BOB, CID, DAN }) and lobby.roles[DAN] == "driver"
	and not MoveRoles.taken(lobby, "guard", DAN) and MoveRoles.choose(lobby, DAN, "guard") == true and lobby.roles[DAN] == "guard")
MoveRoles.setReady(lobby, DAN, true)
check("…LAUNCH with the doubles", MoveRoles.canLaunch(lobby, ANN) == true)
check("a fifth player: doubles still, the first role", MoveRoles.sync(lobby, { ANN, BOB, CID, DAN, EVE }) and lobby.roles[EVE] == "driver" and #lobby.members == 5)
check("a leaver: their role and READY go", MoveRoles.sync(lobby, { ANN, BOB, CID, DAN }) and lobby.roles[EVE] == nil and lobby.ready[EVE] == nil and #lobby.members == 4)
-- a double left over (no more players than roles again): the later one gets a free role
check("down to three with a role doubled: fixed for the later one, NOT READY", MoveRoles.sync(lobby, { ANN, BOB, DAN }) and lobby.roles[BOB] == "guard"
	and lobby.roles[DAN] == "mover" and lobby.ready[DAN] == false and MoveRoles.canLaunch(lobby, ANN) == false)
check("freeRole: the first nobody else has", MoveRoles.freeRole({ [1] = "driver", [2] = "mover" }, { 1, 2, 3 }, 3) == "guard"
	and MoveRoles.freeRole({ [1] = "driver" }, { 1 }, 1) == "driver" and MoveRoles.freeRole({ [1] = "driver", [2] = "mover", [3] = "guard" }, { 1, 2, 3, 4 }, 4) == "driver")

-- On a move ------------------------------------------------------------------------------------------------------------

local roles = { [ANN] = "driver", [BOB] = "guard" }
local members = { ANN, BOB }
local can, no, wait = MoveRoles.canSwitch(roles, members, BOB, "driver", nil, 50)
check("a switch to a crew mate's role: refused", can == false and no == "taken" and wait == nil)
can, no = MoveRoles.canSwitch(roles, members, BOB, "guard", nil, 50)
check("to your own: refused", can == false and no == "same")
can, no = MoveRoles.canSwitch(roles, members, BOB, "pilot", nil, 50)
check("to no role: refused", can == false and no == "role")
can, no = MoveRoles.canSwitch(roles, members, BOB, "tech", nil, 50)
check("to the Technician (no role any more): refused", can == false and no == "role")
check("to a free one: fine", MoveRoles.canSwitch(roles, members, BOB, "mover", nil, 50) == true)
can, no, wait = MoveRoles.canSwitch(roles, members, BOB, "mover", 50, 60)
check("again within Switch s: the cooldown and the wait", can == false and no == "cooldown" and wait == R.Switch - 10)
check("after Switch s: fine", MoveRoles.canSwitch(roles, members, BOB, "mover", 50, 50 + R.Switch) == true)
check("solo: any of the three", MoveRoles.canSwitch({ [ANN] = "driver" }, { ANN }, ANN, "guard", nil, 0) == true and MoveRoles.canSwitch({ [ANN] = "driver" }, { ANN }, ANN, "mover", nil, 0) == true)
check("four on a move: a crew mate's role is fine (doubles)", MoveRoles.canSwitch({ [1] = "driver", [2] = "mover", [3] = "guard", [4] = "driver" }, { 1, 2, 3, 4 }, 4, "guard", nil, 0) == true)

local S = Config.Moving.Speed
check("the Mover: a pair thing alone at Alone (not the drag)", near(MoveRoles.speedFactor("mover", "drag", S.Drag), R.Mover.Alone) and near(MoveRoles.speedFactor("driver", "drag", S.Drag), S.Drag))
check("…× Carry on the rest, never over the walk", near(MoveRoles.speedFactor("mover", "both", S.Both), S.Both * R.Mover.Carry) and near(MoveRoles.speedFactor("mover", "pair", S.Pair), math.min(1, S.Pair * R.Mover.Carry))
	and near(MoveRoles.speedFactor("mover", "hand", 0.97), 1) and near(MoveRoles.speedFactor(nil, "both", S.Both), S.Both))
check("…holds it up, the others drag it", MoveRoles.holdMode("mover", "drag") == "pair" and MoveRoles.holdMode("guard", "drag") == "drag" and MoveRoles.holdMode("mover", "both") == "both")
check("a climb: 3 up over 2 along; not a step on the flat, nor a gentle ramp", MoveRoles.climbing(3, 2) and MoveRoles.climbing(1, 0) and not MoveRoles.climbing(0.1, 0)
	and not MoveRoles.climbing(1, 10) and not MoveRoles.climbing(-3, 2) and not MoveRoles.climbing(0 / 0, 1))
check("up a climb: the others × Climb with both hands, a Mover and a thing in one hand not", near(MoveRoles.climbFactor("driver", "both"), R.Mover.Climb)
	and near(MoveRoles.climbFactor(nil, "drag"), R.Mover.Climb) and MoveRoles.climbFactor("mover", "both") == 1 and MoveRoles.climbFactor("guard", "hand") == 1)
check("the Guard: × Damage with guns, blasts and fists; not the car's ram nor the others", near(MoveRoles.weaponFactor("guard", nil), R.Guard.Damage)
	and near(MoveRoles.weaponFactor("guard", "melee"), R.Guard.Damage) and near(MoveRoles.weaponFactor("guard", "splash"), R.Guard.Damage)
	and MoveRoles.weaponFactor("guard", "car") == 1 and MoveRoles.weaponFactor("guard", "other") == 1 and MoveRoles.weaponFactor("driver", nil) == 1)
check("the Driver at the wheel: the truck takes TruckDamage of a hit", near(MoveRoles.truckFactor(true), R.Driver.TruckDamage) and MoveRoles.truckFactor(false) == 1)
check("Call truck to door: the Driver, once", MoveRoles.canCall("driver", false) == true and select(2, MoveRoles.canCall("driver", true)) == "called"
	and select(2, MoveRoles.canCall("mover", false)) == "driver")
check("barricades: the Guard, Barricades of them", MoveRoles.canBarricade("guard", 0) == true and MoveRoles.canBarricade("guard", R.Guard.Barricades - 1) == true
	and select(2, MoveRoles.canBarricade("guard", R.Guard.Barricades)) == "nomore" and select(2, MoveRoles.canBarricade("mover", 0)) == "guard")
check("a barricade wears Bite hp a second for each zombie at it", near(MoveRoles.wear(400, 2, 1), 400 - 2 * R.Guard.Bite) and MoveRoles.wear(400, 0, 5) == 400
	and MoveRoles.wear(10, 3, 10) == 0 and MoveRoles.wear(50, 1, 0) == 50)

-- 8.8: no roles (the sandbox; the city with the switch off) ---------------------------------------------------------------

check("the city with the switch on: roles", R.On == true and MoveRoles.on())
Config.Sandbox.On = true
check("the sandbox: no roles, whatever the switch says", R.On == true and not MoveRoles.on())
local plain = MoveRoles.newLobby(ANN, "sandbox_house", 100)
check("a new lobby: the owner in it, no role", #plain.members == 1 and plain.members[1] == ANN and next(plain.roles) == nil)
check("…solo: LAUNCH at once", MoveRoles.canLaunch(plain, ANN) == true and MoveRoles.waiting(plain) == 0)
check("the crew joins: no role, NOT READY, LAUNCH waits", MoveRoles.sync(plain, { ANN, BOB }) == true and next(plain.roles) == nil and plain.ready[BOB] ~= true
	and MoveRoles.waiting(plain) == 1 and select(2, MoveRoles.canLaunch(plain, ANN)) == "notready")
check("…nothing new: no change", MoveRoles.sync(plain, { ANN, BOB }) == false)
ok, why = MoveRoles.choose(plain, BOB, "mover")
check("no role to pick (not even a free one)", ok == false and why == "noroles" and next(plain.roles) == nil)
ok, why = MoveRoles.setReady(plain, BOB, true)
check("READY without a role: LAUNCH", ok == true and why == nil and MoveRoles.canLaunch(plain, ANN) == true and MoveRoles.waiting(plain) == 0)
check("four of them: no role, no doubles to speak of", MoveRoles.sync(plain, { ANN, BOB, CID, DAN }) and next(plain.roles) == nil and MoveRoles.waiting(plain) == 2)
check("leavers: their READY goes", MoveRoles.sync(plain, { ANN }) == true and plain.ready[BOB] == nil and #plain.members == 1 and MoveRoles.waiting(plain) == 0)
check("…and back: NOT READY again", MoveRoles.sync(plain, { ANN, BOB }) == true and MoveRoles.waiting(plain) == 1)
can, no, wait = MoveRoles.canSwitch({}, { ANN, BOB }, BOB, "guard", nil, 0)
check("on a move: no switch", can == false and no == "noroles" and wait == nil)
check("nobody carries a pair piece alone: dragged at Drag, low (a stray \"mover\" too)", near(MoveRoles.speedFactor("mover", "drag", S.Drag), S.Drag)
	and near(MoveRoles.speedFactor(nil, "drag", S.Drag), S.Drag) and MoveRoles.holdMode("mover", "drag") == "drag" and MoveRoles.holdMode(nil, "drag") == "drag")
check("…nor faster with the rest", near(MoveRoles.speedFactor("mover", "both", S.Both), S.Both) and near(MoveRoles.speedFactor("mover", "pair", S.Pair), S.Pair))
check("up stairs: everybody × Climb with both hands (one hand not)", near(MoveRoles.climbFactor("mover", "both"), R.Mover.Climb)
	and near(MoveRoles.climbFactor(nil, "pair"), R.Mover.Climb) and MoveRoles.climbFactor(nil, "hand") == 1)
check("no damage bonus", MoveRoles.weaponFactor("guard", nil) == 1 and MoveRoles.weaponFactor("guard", "melee") == 1 and MoveRoles.weaponFactor(nil, nil) == 1)
check("the truck takes every hit whole", MoveRoles.truckFactor(true) == 1 and MoveRoles.truckFactor(false) == 1)
check("anybody calls the van, once a move", MoveRoles.canCall(nil, false) == true and MoveRoles.canCall("mover", false) == true
	and select(2, MoveRoles.canCall(nil, true)) == "called")
check("no barricades", MoveRoles.canBarricade("guard", 0) == false and select(2, MoveRoles.canBarricade("guard", 0)) == "noroles" and MoveRoles.canBarricade(nil, 0) == false)
Config.Sandbox.On = false
R.On = false
check("the city with the switch off: no roles there either", not MoveRoles.on() and next(MoveRoles.newLobby(ANN, "marge", 0).roles) == nil
	and MoveRoles.canCall(nil, false) == true and MoveRoles.holdMode("mover", "drag") == "drag")
R.On = true
check("…on again: the roles as before", MoveRoles.on() and MoveRoles.newLobby(ANN, "marge", 0).roles[ANN] == "driver" and select(2, MoveRoles.canCall(nil, false)) == "driver")

-- The quick chat, the words ----------------------------------------------------------------------------------------------

local lines = {}
for _, line in MoveRoles.Chat do
	table.insert(lines, line.text)
	if line.icon == "" then
		lines = {}
		break
	end
end
check("the quick chat's six lines", #MoveRoles.Chat == 6 and MoveRoles.Chat[2].id == "hand" and lines[1] == "Hold the door" and lines[2] == "Need a hand here" and lines[3] == "Zombies!" and lines[4] == "Truck's here"
	and lines[5] == "I'll come pick you up" and lines[6] == "Done — let's go")
local worded = true
for _, code in { "member", "role", "taken", "owner", "norole", "notready", "same", "cooldown", "driver", "called", "guard", "nomore", "noroles" } do
	if MoveRoles.whyText(code) == MoveRoles.whyText("no such code") then
		worded = false
		print("  (no words for " .. code .. ")")
	end
end
check("every refusal has its own words", worded and MoveRoles.whyText(nil) ~= "")

Config.Sandbox.On = sandboxOn

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
