-- 6.14, get ready for the mission (shared/Readiness.luau): which story mission is next, what it needs (the READY CHECK's
-- rows, the required ones as server/Missions.luau refusal() asks for them), what would help, the savings goal and the
-- words of the phone's tile, the HUD's line, the job result and the READY toast. Run with tests/run_tests.py.
local Config = require("./Config")
local Economy = require("./Economy")
local Levels = require("./Levels")
local Missions = require("./Missions")
local Readiness = require("./Readiness")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function find(result: Readiness.Result, id: string): Readiness.Check?
	for _, row in result.checks do
		if row.id == id then
			return row
		end
	end
	return nil
end

local function ids(result: Readiness.Result): string
	local out: { string } = {}
	for _, row in result.checks do
		table.insert(out, `{row.id}{if row.done then "+" else "-"}`)
	end
	return table.concat(out, ",")
end

-- Every mission of the chapters before `campaignId` done (and of it, the first `upTo`).
local function progressTo(campaignId: string, upTo: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, campaign in Missions.Campaigns do
		if campaign.duo then
			continue
		end
		for index, def in Missions.ofCampaign(campaign.id) do
			if campaign.id ~= campaignId or index <= upTo then
				out[def.id] = 2
			end
		end
		if campaign.id == campaignId then
			break
		end
	end
	return out
end

local tuning = Config.Readiness
check("Config.Readiness: its numbers", type(tuning) == "table" and tuning.MaxRows >= 4 and tuning.HardTier >= 1 and tuning.Medkits >= 1 and tuning.RepairKits >= 1 and type(tuning.Sound) == "string" and tuning.LineHeight > 0)

-- ── Which mission is next ───────────────────────────────────────────────────

local first = Missions.ofCampaign("dispatch")[1]
local def, kind = Readiness.nextMission({})
check("a new save: First Shift's first mission (where the MISSIONS window opens)", def == first and kind == "story" and first.name == "Paper Trail")
def, kind = Readiness.nextMission(progressTo("dispatch", 2))
check("inside a chapter: its next mission (Missions.nextUp)", def ~= nil and def.id == Missions.ofCampaign("dispatch")[3].id and kind == "story")
def = Readiness.nextMission(progressTo("dispatch", 6))
check("a finished chapter: the next story chapter's first (Code Red), not the DUO side story", def ~= nil and def.campaign == "clinic" and def.number == 1)
local story: { [string]: number } = {}
for _, mission in Missions.List do
	if not mission.duo then
		story[mission.id] = 3
	end
end
def, kind = Readiness.nextMission(story)
check("every story chapter done: the DUO chapter's next", def ~= nil and def.campaign == "duo" and def.number == 1 and kind == "duo")
local all: { [string]: number } = table.clone(story)
for _, mission in Missions.List do
	all[mission.id] = 3
end
def, kind = Readiness.nextMission(all)
check("every star yours: none", def == nil and kind == nil)
all[Missions.ofCampaign("market")[2].id] = 2
def, kind = Readiness.nextMission(all)
check("everything done, a mission short of ★★★: a replay for stars", def ~= nil and def.id == Missions.ofCampaign("market")[2].id and kind == "replay")
local none = Readiness.evaluate({ progress = (function()
	local out = {}
	for _, mission in Missions.List do
		out[mission.id] = 3
	end
	return out
end)(), xp = Levels.xpFor(15) })
check("nothing left: no mission, no rows, no goal", none.mission == nil and #none.checks == 0 and none.goal == nil and Readiness.status(none) == "ALL DONE" and Readiness.chapterLine(nil) == "Every mission done")

-- ── A new courier: Paper Trail needs level 4 and a van (save up early) ─────

local fresh = Readiness.evaluate({ xp = 0, money = 40, cars = {}, tutorial = "board", phone = true })
check("a new courier: the mission is Paper Trail, First Shift 1/6", fresh.mission ~= nil and fresh.mission.name == "Paper Trail" and fresh.mission.number == 1 and fresh.mission.total == 6
	and Readiness.chapterLine(fresh.mission) == "First Shift · 1/6", fresh.mission and Readiness.chapterLine(fresh.mission))
check("its rows: the level and the van (required), a medkit (recommended)", ids(fresh) == "level-,vehicle-,medkit-", ids(fresh))
local levelRow = find(fresh, "level") :: Readiness.Check
check("the level row: Reach level 4, the XP have / need, JOBS", levelRow.text == "Reach level 4" and levelRow.required and levelRow.have == 0 and levelRow.need == Levels.xpFor(4) and levelRow.action == "jobs")
local van = find(fresh, "vehicle") :: Readiness.Check
check("the van row: Earl's Old Van, its price and level, the GPS to Earl", van.text == "A van of your own" and van.cost == 1800 and van.place == "earl" and van.action == "gps" and van.name == "Old Van" and van.level == 4
	and Readiness.line(van) == "A van of your own → Old Van at Earl's Used Wheels · $1,800 · level 4", Readiness.line(van))
check("not ready: 0 of 2", not fresh.ready and fresh.done == 0 and fresh.required == 2 and Readiness.status(fresh) == "0 of 2 ready")
check("the goal: the Old Van, below its level too (save up early)", fresh.goal ~= nil and fresh.goal.name == "Old Van" and fresh.goal.have == 40 and fresh.goal.need == 1800 and fresh.goal.left == 1760 and fresh.goal.place == "earl" and not fresh.goal.afford)
check("Marge's first day: quiet (no HUD line, no toast)", fresh.quiet)
check("no phone yet: quiet", Readiness.evaluate({ phone = false }).quiet and not Readiness.evaluate({ phone = true, tutorial = "done" }).quiet and not Readiness.evaluate({}).quiet)
check("the marks: ✖ required, ☆ recommended, ✔ done", Readiness.mark(van) == "✖" and Readiness.mark(find(fresh, "medkit") :: Readiness.Check) == "☆" and Readiness.mark({ id = "x", icon = "", text = "", done = true, required = false }) == "✔")

-- The words.
local goal = fresh.goal :: Readiness.Goal
check("the goal's line: Old Van · $40 / $1,800, $1,760 to go", Readiness.goalLine(goal) == "Old Van · $40 / $1,800" and Readiness.toGo(goal) == "$1,760 to go")
check("the HUD's savings line: 🚐 Old Van  $40 / $1,800", Readiness.hudLine(goal) == "🚐 Old Van  $40 / $1,800" and goal.icon == "🚐", Readiness.hudLine(goal))
check("WORK's line: Earn for the Old Van · $1,760 to go", Readiness.workLine(goal) == "Earn for the Old Van · $1,760 to go" and Readiness.workLine(nil) == nil)
check("the job result's line: +$85 · $1,675 to go for the Old Van", Readiness.resultLine(85, goal, 40 + 85) == "+$85 · $1,675 to go for the Old Van" and Readiness.resultLine(85, nil, 125) == nil and Readiness.resultLine(0, goal, 40) == nil)
check("… enough now", Readiness.resultLine(85, goal, 1850) == "+$85 · enough for the Old Van now")
check("Readiness.money: $1,234,567", Readiness.money(1234567) == "$1,234,567" and Readiness.money(80) == "$80")

-- Level 4 with the money, no van: the GPS to Earl, the goal affordable.
local rich = Readiness.evaluate({ xp = Levels.xpFor(4), money = 1900, cars = {}, vanQuest = "open" })
check("level 4 with $1,900: the level done, the van to buy (no level note), the goal affordable", (find(rich, "level") :: Readiness.Check).done and Readiness.line(find(rich, "vehicle") :: Readiness.Check) == "A van of your own → Old Van at Earl's Used Wheels · $1,800"
	and rich.goal ~= nil and rich.goal.afford and Readiness.toGo(rich.goal) == "✓ you can buy it" and Readiness.workLine(rich.goal) == "Buy the Old Van now · $1,800" and Readiness.status(rich) == "1 of 2 ready")
check("… the HUD says buy it", rich.goal ~= nil and Readiness.hudLine(rich.goal) == "🚐 Old Van  ✓ buy it · $1,800")

-- ── With the van ────────────────────────────────────────────────────────────

local ready = Readiness.evaluate({ xp = Levels.xpFor(4), money = 300, cars = { van = true }, car = "van", vanQuest = "done", items = { medkit = 2 }, progress = {} })
check("the van at level 4: Paper Trail is READY (the level, the van, room for 2)", ready.ready and ready.done == 3 and ready.required == 3 and Readiness.status(ready) == "READY · START", ids(ready))
check("… the repair kit recommended once you drive, the medkit done", ids(ready) == "level+,vehicle+,cargo+,repair-,medkit+", ids(ready))
check("… room for 2: your Old Van holds 2", (find(ready, "cargo") :: Readiness.Check).text == "Room for 2 pieces" and (find(ready, "cargo") :: Readiness.Check).detail == "Your Old Van holds 2")
check("… a repair kit is no savings goal (Config.Readiness.NotGoals): nothing to save up for", ready.goal == nil)
check("the READY toast's words", Readiness.readyToast(ready.mission :: Readiness.MissionInfo) == "Ready for Paper Trail · open MISSIONS (U)" and Readiness.readyToast(ready.mission :: Readiness.MissionInfo, true) == "Ready for Paper Trail · open MISSIONS")

-- A bike out while the van waits: the server says "a bike won't do".
local biking = Readiness.evaluate({ xp = Levels.xpFor(4), money = 300, cars = { van = true, rustbike = true }, car = "rustbike", lastCar = "van", vanQuest = "done" })
local riding = find(biking, "vehicle") :: Readiness.Check
check("a bike out, the van at home: not ready, CALL CAR (GARAGE), nothing to buy", not biking.ready and not riding.done and riding.action == "garage" and riding.cost == nil and riding.text == "Your car, not the bike")
check("… its room counted in the van", (find(biking, "cargo") :: Readiness.Check).done)

-- The van quest done but no car (sold): the dealer's cheapest.
local dealer = Readiness.evaluate({ xp = Levels.xpFor(5), money = 0, cars = {}, vanQuest = "done", progress = progressTo("dispatch", 0) })
check("no car and Earl's van bought once: the dealer's cheapest car", (find(dealer, "vehicle") :: Readiness.Check).place == "dealer" and (find(dealer, "vehicle") :: Readiness.Check).name == "Courier Van")

-- ── Room: a stage, another car of yours, the dealer ─────────────────────────

local quarantine = progressTo("clinic", 4)
local q = Readiness.evaluate({ xp = Levels.xpFor(5) + 10, money = 900, cars = { van = true }, car = "van", progress = quarantine, items = { medkit = 1, repair = 1 } })
check("Quarantine Zone (3 sample cases) in the Rusty Van: room missing", q.mission ~= nil and q.mission.name == "Quarantine Zone" and not q.ready and q.done == 2, q.mission and q.mission.name)
local room = find(q, "cargo") :: Readiness.Check
check("… build it up to a Work Van at Wrench Garage: both stages' price, the GPS there", room.text == "A vehicle for 3 pieces" and room.place == "mechanic" and room.name == "Work Van" and room.cost == 250 + 700 and room.action == "gps"
	and Readiness.line(room) == "A vehicle for 3 pieces → Your Old Van holds 2: build it up to a Work Van at Wrench Garage · $950", Readiness.line(room))
check("… it is the goal ($50 to go)", q.goal ~= nil and q.goal.name == "Work Van" and q.goal.left == 50)
local built = Readiness.evaluate({ xp = Levels.xpFor(5) + 10, money = 900, cars = { van = true }, car = "van", carUpgrades = { van = { stage = 2 } }, progress = quarantine })
check("… as a Work Van it holds 3: done", (find(built, "cargo") :: Readiness.Check).done and built.ready)
local hard = Readiness.evaluate({ xp = Levels.xpFor(5) + 10, money = 900, cars = { van = true, highroof = true }, car = "van", progress = quarantine })
check("… a High-Roof Van of yours holds it now: GARAGE, nothing to buy", (find(hard, "cargo") :: Readiness.Check).action == "garage" and (find(hard, "cargo") :: Readiness.Check).cost == nil)
-- A load only a truck takes (Mess Hall: 6 soup boxes) in a Long Cargo Van: the dealer's cheapest that holds 6.
local mess = Missions.find("army_2") :: Missions.MissionDef
check("Mess Hall takes 6 pieces of its own (the test's premise)", mess ~= nil and Economy.cargoNeed(mess.load, mess.items) == 6 and mess.vehicle == nil)
local truck = Readiness.evaluate({ mission = "army_2", xp = Levels.xpFor(9), money = 5000, cars = { van = true }, car = "van", carUpgrades = { van = { stage = 3 } }, progress = progressTo("army", 1) })
local need6 = find(truck, "cargo") :: Readiness.Check
check("… the van's last stage holds 4: the Box Truck at Dead End Motors", need6.place == "dealer" and need6.name == "Box Truck" and need6.cost == 22000, need6 and Readiness.line(need6))
-- A mission that lends its vehicle: no room row (a car of your own is still asked for, as the server does).
local lent = Readiness.evaluate({ mission = "clinic_2", xp = Levels.xpFor(5), money = 0, cars = {}, progress = progressTo("clinic", 1) })
check("a mission that lends its vehicle (the ambulance): no room row, a car of your own still required", find(lent, "cargo") == nil and find(lent, "vehicle") ~= nil and lent.mission ~= nil and lent.mission.lends == "ambulance")
-- 4.6: the Roof Rack's two slots count for light pieces (parcels), as on the server.
local rackMission = Missions.find("dispatch_1") :: Missions.MissionDef
local look = Config.Cargo.Kinds[rackMission.itemKind].look
check("the Roof Rack counts for light pieces", Economy.capacity("van", {}, { roofrack = true }, look) == 4 or not Config.Cargo.LightLooks[look])

-- ── Co-op, hard missions, DUO ───────────────────────────────────────────────

local rush = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { van = true }, car = "van", progress = progressTo("dispatch", 5), items = { medkit = 1, repair = 1 } })
check("Rush Hour of the Dead (co-op, ★★★): bring a friend, a vest, a two-handed gun", rush.mission ~= nil and rush.mission.coop and rush.mission.tier >= tuning.HardTier
	and ids(rush) == "level+,vehicle+,cargo+,friend-,vest-", ids(rush))
check("… recommended rows never block: READY", rush.ready)
local friend = find(rush, "friend") :: Readiness.Check
check("… the friend row: INVITE, co-op pays more", friend.action == "invite" and not friend.required and string.find(friend.detail or "", "+25%", 1, true) ~= nil)
check("… the vest: the Kevlar Vest at the gear stall, the goal", (find(rush, "vest") :: Readiness.Check).name == "Kevlar Vest" and (find(rush, "vest") :: Readiness.Check).place == "supplies" and rush.goal ~= nil and rush.goal.id == "vest")
check("… at most MaxRows rows, the required ones first", #rush.checks <= tuning.MaxRows and rush.checks[1].required and rush.checks[3].required and not rush.checks[4].required)
local geared = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { van = true }, car = "van", progress = progressTo("dispatch", 5), crewSize = 1, kit = { kevlar = true }, weapons = { pistol = true, shotgun = true }, items = { medkit = 1, repair = 1 } })
check("… with a friend, a vest and a shotgun: all done, no goal", geared.ready and geared.goal == nil and (find(geared, "friend") :: Readiness.Check).done and (find(geared, "vest") :: Readiness.Check).done)
local member = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { van = true }, car = "van", progress = progressTo("dispatch", 5), crewOwner = "Ann", kit = { kevlar = true }, weapons = { shotgun = true }, items = { medkit = 1, repair = 1 } })
check("… in a friend's crew counts as bringing one", (find(member, "friend") :: Readiness.Check).done)
local busy = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { van = true }, car = "van", progress = progressTo("dispatch", 5), crewOwner = "Ann" })
check("… the rows still to do come before the done ones (the friend cut at MaxRows)", find(busy, "friend") == nil and #busy.checks == tuning.MaxRows, ids(busy))
local gun = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { van = true }, car = "van", progress = progressTo("dispatch", 5), crewSize = 1, kit = { kevlar = true }, items = { medkit = 1, repair = 1 } })
local long = find(gun, "gun") :: Readiness.Check
check("… no two-handed gun: the Shotgun at Lead & Co.'s range", long ~= nil and long.name == "Shotgun" and long.place == "guns" and long.cost == 7500 and gun.goal ~= nil and gun.goal.id == "gun")
local easy = Readiness.evaluate({ xp = Levels.xpFor(4), money = 400, cars = { van = true }, car = "van", progress = {} })
check("an easy mission: no vest, no gun, no friend", find(easy, "vest") == nil and find(easy, "gun") == nil and find(easy, "friend") == nil)
local duo = Readiness.evaluate({ xp = Levels.xpFor(15), money = 0, cars = { van = true }, car = "van", progress = story })
local partner = find(duo, "partner") :: Readiness.Check
check("the DUO chapter: a partner in your crew is required, INVITE", duo.mission ~= nil and duo.mission.duo and partner ~= nil and partner.required and not partner.done and partner.action == "invite" and not duo.ready
	and Readiness.chapterLine(duo.mission) == "DUO · Partners in Crime · 1/6", duo.mission and Readiness.chapterLine(duo.mission))
local paired = Readiness.evaluate({ xp = Levels.xpFor(15), money = 0, cars = { van = true }, car = "van", progress = story, crewSize = 1 })
check("… with a crew member: done", (find(paired, "partner") :: Readiness.Check).done and find(paired, "friend") == nil)
local replay = Readiness.evaluate({ xp = Levels.xpFor(15), money = 0, cars = { van = true }, car = "van", progress = all })
check("a replay for stars: no level row, its words", replay.mission ~= nil and replay.mission.replay and find(replay, "level") == nil and Readiness.chapterLine(replay.mission) == "Replay for stars · Empty Shelves")

-- ── A level-locked chapter: the next chapter's first mission and its level ─

local waits = Readiness.evaluate({ xp = Levels.xpFor(4) + 500, money = 900, cars = { van = true }, car = "van", progress = progressTo("dispatch", 6) })
local reach = find(waits, "level") :: Readiness.Check
check("First Shift done at level 4: Code Red's House Call, Reach level 5", waits.mission ~= nil and waits.mission.chapter == "Code Red" and reach ~= nil and reach.text == "Reach level 5" and not reach.done and not waits.ready)
check("… its XP: have / need", reach.have == Levels.xpFor(4) + 500 and reach.need == Levels.xpFor(5) and reach.detail == `{string.sub(Readiness.money(Levels.xpFor(4) + 500), 2)} / {string.sub(Readiness.money(Levels.xpFor(5)), 2)} XP`)
-- The phone's own pick (a window's mission): input.mission.
local pick = Readiness.evaluate({ mission = "dispatch_3", xp = Levels.xpFor(4), progress = {} })
check("input.mission checks that one", pick.mission ~= nil and pick.mission.id == "dispatch_3")

-- The READY CHECK is drawn again only when what it shows changes: not for money.
local before = Readiness.key(Readiness.evaluate({ xp = Levels.xpFor(4), money = 100, cars = { van = true }, car = "van" }))
check("the key ignores the money, follows the rows", before == Readiness.key(Readiness.evaluate({ xp = Levels.xpFor(4), money = 900, cars = { van = true }, car = "van" }))
	and before ~= Readiness.key(Readiness.evaluate({ xp = Levels.xpFor(4), money = 100, cars = { van = true }, car = "van", items = { medkit = 1 } })))

-- Every story mission at its own level with a car that has the room: never a missing required row but the level.
local stuck: { string } = {}
for _, mission in Missions.List do
	if mission.duo then
		continue
	end
	local need = Economy.cargoNeed(mission.load, mission.items)
	local result = Readiness.evaluate({ mission = mission.id, xp = Levels.xpFor(15), money = 0, cars = { boxtruck = true, van = true }, car = "boxtruck", carUpgrades = { boxtruck = { stage = 2 } }, progress = {} })
	if not result.ready and need <= 8 then
		table.insert(stuck, mission.id)
	end
end
check("every story mission: ready with level 15 and a Freight Hauler", #stuck == 0, table.concat(stuck, ", "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
