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

-- ── A new courier: Paper Trail needs level 4; the ZDC Van is yours already (7.x: one car) ─────

local VAN = Config.CompanyVan.Car
local fresh = Readiness.evaluate({ xp = 0, money = 40, cars = { [VAN] = true }, car = VAN, tutorial = "board", phone = true })
check("a new courier: the mission is Paper Trail, First Shift 1/6", fresh.mission ~= nil and fresh.mission.name == "Paper Trail" and fresh.mission.number == 1 and fresh.mission.total == 6
	and Readiness.chapterLine(fresh.mission) == "First Shift · 1/6", fresh.mission and Readiness.chapterLine(fresh.mission))
check("its rows: the level to reach, the van and its room done (7.x: everybody's ZDC Van), the kits recommended", ids(fresh) == "level-,vehicle+,cargo+,medkit-,repair-", ids(fresh))
local levelRow = find(fresh, "level") :: Readiness.Check
check("the level row: Reach level 4, the XP have / need, JOBS", levelRow.text == "Reach level 4" and levelRow.required and levelRow.have == 0 and levelRow.need == Levels.xpFor(4) and levelRow.action == "jobs")
local van = find(fresh, "vehicle") :: Readiness.Check
check("the van row: your ZDC Van, done, nothing to buy", van.done and van.cost == nil and van.place == nil and string.find(van.detail or "", "ZDC Van", 1, true) ~= nil, Readiness.line(van))
check("not ready: 2 of 3", not fresh.ready and fresh.done == 2 and fresh.required == 3 and Readiness.status(fresh) == "2 of 3 ready", Readiness.status(fresh))
check("7.x: no car to save up for: the kits are no savings goal, nothing else costs", fresh.goal == nil, fresh.goal and fresh.goal.name)
check("Marge's first day: quiet (no HUD line, no toast)", fresh.quiet)
check("no phone yet: quiet", Readiness.evaluate({ phone = false }).quiet and not Readiness.evaluate({ phone = true, tutorial = "done" }).quiet and not Readiness.evaluate({}).quiet)
check("the marks: ✖ required, ☆ recommended, ✔ done", Readiness.mark(levelRow) == "✖" and Readiness.mark(find(fresh, "medkit") :: Readiness.Check) == "☆" and Readiness.mark({ id = "x", icon = "", text = "", done = true, required = false }) == "✔")
-- (a state still loading has no car yet: the row asks for the van, CAR brings it, never a buy)
local loading = Readiness.evaluate({ xp = Levels.xpFor(5), money = 0, cars = {} })
local noCar = find(loading, "vehicle") :: Readiness.Check
check("7.x: no car in the state yet: Your ZDC Van, CAR brings it (GARAGE), nothing to buy, no goal", noCar.text == "Your ZDC Van" and noCar.action == "garage" and noCar.cost == nil and not noCar.done and loading.goal == nil, Readiness.line(noCar))

-- ── The words (6.14), on a savings goal: the Shotgun after First Shift (6.19: its finale unlocks it) ─────

local done = progressTo("dispatch", 6)
local function shotgun(xp: number, money: number): Readiness.Result
	return Readiness.evaluate({ xp = xp, money = money, cars = { [VAN] = true }, car = VAN, progress = done, mission = "dispatch_10", crewSize = 1, kit = { kevlar = true }, items = { medkit = 1, repair = 1 } })
end
local saving = shotgun(Levels.xpFor(5), 400)
local goal = saving.goal :: Readiness.Goal
check("the goal: the Shotgun at Lead & Co.'s range ($15,000, level 5)", goal ~= nil and goal.name == "Shotgun" and goal.have == 400 and goal.need == 15000 and goal.left == 14600 and goal.place == "guns" and not goal.afford and not goal.locked, goal and goal.name)
check("the goal's line: Shotgun · $400 / $15,000, $14,600 to go", Readiness.goalLine(goal) == "Shotgun · $400 / $15,000" and Readiness.toGo(goal) == "$14,600 to go")
check("the HUD's savings line: 🔫 Shotgun  $400 / $15,000", Readiness.hudLine(goal) == "🔫 Shotgun  $400 / $15,000" and goal.icon == "🔫", Readiness.hudLine(goal))
check("WORK's line: Earn for the Shotgun · $14,600 to go", Readiness.workLine(goal) == "Earn for the Shotgun · $14,600 to go" and Readiness.workLine(nil) == nil)
check("the job result's line: +$85 · $14,515 to go for the Shotgun", Readiness.resultLine(85, goal, 400 + 85) == "+$85 · $14,515 to go for the Shotgun" and Readiness.resultLine(85, nil, 125) == nil and Readiness.resultLine(0, goal, 400) == nil)
check("Readiness.money: $1,234,567", Readiness.money(1234567) == "$1,234,567" and Readiness.money(80) == "$80")
local rich = shotgun(Levels.xpFor(5), 15500)
check("level 5 with $15,500: the goal affordable", rich.goal ~= nil and rich.goal.afford and Readiness.toGo(rich.goal) == "✓ you can buy it" and Readiness.workLine(rich.goal) == "Buy the Shotgun now · $15,000")
check("… the HUD says buy it", rich.goal ~= nil and Readiness.hudLine(rich.goal) == "🔫 Shotgun  ✓ buy it · $15,000")
check("… the job result's line: enough now", rich.goal ~= nil and Readiness.resultLine(85, rich.goal, 15585) == "+$85 · enough for the Shotgun now")
-- 6.14 review: the money without the level is no "buy it" (the range refuses below level 5).
local early = shotgun(Levels.xpFor(4), 15600)
local saved = early.goal :: Readiness.Goal
check("level 4 with $15,600: the goal is locked, not affordable, its level carried", saved ~= nil and saved.locked and not saved.afford and saved.level == 5 and saved.left == 0)
check("… the HUD: $15,000 saved · level 5", Readiness.hudLine(saved) == "🔫 Shotgun  $15,000 saved · level 5" and Readiness.goalMoney(saved) == "$15,000 saved · level 5", Readiness.hudLine(saved))
check("… WORK: Shotgun saved · reach level 5 to buy", Readiness.workLine(saved) == "Shotgun saved · reach level 5 to buy" and Readiness.toGo(saved) == "level 5 to buy", Readiness.workLine(saved))
check("… the result line and the goal line say so too", Readiness.resultLine(85, saved, 15685) == "+$85 · the Shotgun is saved: level 5 to buy" and Readiness.goalLine(saved) == "Shotgun · $15,000 saved · level 5")
local short = shotgun(Levels.xpFor(4), 600).goal :: Readiness.Goal
check("… short of the money too: the money as before", short.locked and not short.afford and Readiness.hudLine(short) == "🔫 Shotgun  $600 / $15,000" and Readiness.toGo(short) == "$14,400 to go")

-- ── With the van ────────────────────────────────────────────────────────────

local ready = Readiness.evaluate({ xp = Levels.xpFor(4), money = 300, cars = { [VAN] = true }, car = VAN, items = { medkit = 2 }, progress = {} })
check("the van at level 4: Paper Trail is READY (the level, the van, room for 2)", ready.ready and ready.done == 3 and ready.required == 3 and Readiness.status(ready) == "READY · START", ids(ready))
check("… the repair kit recommended once you drive, the medkit done", ids(ready) == "level+,vehicle+,cargo+,repair-,medkit+", ids(ready))
check("… room for 2: your ZDC Van holds 4", (find(ready, "cargo") :: Readiness.Check).text == "Room for 2 pieces" and (find(ready, "cargo") :: Readiness.Check).detail == "Your ZDC Van holds 4")
check("… a repair kit is no savings goal (Config.Readiness.NotGoals): nothing to save up for", ready.goal == nil)
check("the READY toast's words", Readiness.readyToast(ready.mission :: Readiness.MissionInfo) == "Ready for Paper Trail · open MISSIONS (U)" and Readiness.readyToast(ready.mission :: Readiness.MissionInfo, true) == "Ready for Paper Trail · open MISSIONS")

-- A bike out while the van waits: the server says "a bike won't do".
local biking = Readiness.evaluate({ xp = Levels.xpFor(4), money = 300, cars = { [VAN] = true, rustbike = true }, car = "rustbike", lastCar = VAN })
local riding = find(biking, "vehicle") :: Readiness.Check
check("a bike out, the van at home: not ready, CALL CAR (GARAGE), nothing to buy", not biking.ready and not riding.done and riding.action == "garage" and riding.cost == nil and riding.text == "Your car, not the bike")
check("… its room counted in the van", (find(biking, "cargo") :: Readiness.Check).done)

-- ── Room: 7.x, every mission fits the ZDC Van ───────────────────────────────

local tooBig: { string } = {}
for _, mission in Missions.List do
	local result = Readiness.evaluate({ mission = mission.id, xp = Levels.xpFor(15), money = 0, cars = { [VAN] = true }, car = VAN, progress = {} })
	local roomRow = find(result, "cargo")
	if roomRow and not roomRow.done then
		table.insert(tooBig, mission.id)
	end
end
check("7.x: no mission needs more room than the ZDC Van (no stage, no other car to buy)", #tooBig == 0, table.concat(tooBig, ", "))
check("… keptAt: the ZDC Van at the depot lot (the starting van)", (Readiness.keptAt({ garages = { "garage_rented" }, cars = { [VAN] = true } }, VAN)) == "depot")
local mess = Missions.find("army_2") :: Missions.MissionDef
check("Mess Hall: four pots of stew, a full van (7.x: six before)", mess ~= nil and Economy.cargoNeed(mess.load, mess.items) == 4 and mess.vehicle == nil)
-- A mission whose people board (Code Blue's patient): no room row; 7.x: nothing lent, your van is asked for.
local boards = Readiness.evaluate({ mission = "clinic_2", xp = Levels.xpFor(5), money = 0, cars = { [VAN] = true }, car = VAN, progress = progressTo("clinic", 1) })
check("a mission whose patient boards: no room row, your van (7.x: no ambulance lent)", find(boards, "cargo") == nil and (find(boards, "vehicle") :: Readiness.Check).done and boards.mission ~= nil and boards.mission.lends == nil)
-- 4.6: the Roof Rack's two slots count for light pieces (parcels), as on the server.
local rackMission = Missions.find("dispatch_1") :: Missions.MissionDef
local look = Config.Cargo.Kinds[rackMission.itemKind].look
check("the Roof Rack counts for light pieces", Economy.capacity(VAN, {}, { roofrack = true }, look) == 6 or not Config.Cargo.LightLooks[look])

-- ── Co-op, hard missions, DUO ───────────────────────────────────────────────

local rush = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { [VAN] = true }, car = VAN, progress = progressTo("dispatch", 5), items = { medkit = 1, repair = 1 } })
check("Rush Hour of the Dead (co-op, ★★★): bring a friend, a vest, a two-handed gun", rush.mission ~= nil and rush.mission.coop and rush.mission.tier >= tuning.HardTier
	and ids(rush) == "level+,vehicle+,cargo+,friend-,vest-", ids(rush))
check("… recommended rows never block: READY", rush.ready)
local friend = find(rush, "friend") :: Readiness.Check
check("… the friend row: INVITE, co-op pays more", friend.action == "invite" and not friend.required and string.find(friend.detail or "", "+25%", 1, true) ~= nil)
check("… the vest: the Kevlar Vest at the gear stall, the goal", (find(rush, "vest") :: Readiness.Check).name == "Kevlar Vest" and (find(rush, "vest") :: Readiness.Check).place == "supplies" and rush.goal ~= nil and rush.goal.id == "vest")
check("… at most MaxRows rows, the required ones first", #rush.checks <= tuning.MaxRows and rush.checks[1].required and rush.checks[3].required and not rush.checks[4].required)
local geared = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { [VAN] = true }, car = VAN, progress = progressTo("dispatch", 5), crewSize = 1, kit = { kevlar = true }, weapons = { pistol = true, shotgun = true }, items = { medkit = 1, repair = 1 } })
check("… with a friend, a vest and a shotgun: all done, no goal", geared.ready and geared.goal == nil and (find(geared, "friend") :: Readiness.Check).done and (find(geared, "vest") :: Readiness.Check).done)
local member = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { [VAN] = true }, car = VAN, progress = progressTo("dispatch", 5), crewOwner = "Ann", kit = { kevlar = true }, weapons = { shotgun = true }, items = { medkit = 1, repair = 1 } })
check("… in a friend's crew counts as bringing one", (find(member, "friend") :: Readiness.Check).done)
local busy = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { [VAN] = true }, car = VAN, progress = progressTo("dispatch", 5), crewOwner = "Ann" })
check("… the rows still to do come before the done ones (the friend cut at MaxRows)", find(busy, "friend") == nil and #busy.checks == tuning.MaxRows, ids(busy))
local gun = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { [VAN] = true }, car = VAN, progress = progressTo("dispatch", 5), crewSize = 1, kit = { kevlar = true }, items = { medkit = 1, repair = 1 } })
local long = find(gun, "gun") :: Readiness.Check
-- 6.19: the Shotgun is the First Shift finale's own unlock: no two-handed gun is open before it (no row, no goal) …
check("6.19: … no two-handed gun open before the finale: no gun row, no gun goal", long == nil and (gun.goal == nil or gun.goal.id ~= "gun"), gun.goal and gun.goal.id)
-- … and once the finale is done (a replay of it): the Shotgun at Lead & Co.'s range, the goal.
local done = progressTo("dispatch", 6)
local replayGun = Readiness.evaluate({ xp = Levels.xpFor(5), money = 400, cars = { [VAN] = true }, car = VAN, progress = done, mission = "dispatch_10", crewSize = 1, kit = { kevlar = true }, items = { medkit = 1, repair = 1 } })
local long2 = find(replayGun, "gun") :: Readiness.Check
check("… no two-handed gun: the Shotgun at Lead & Co.'s range", long2 ~= nil and long2.name == "Shotgun" and long2.place == "guns" and long2.cost == 15000 and replayGun.goal ~= nil and replayGun.goal.id == "gun")
local easy = Readiness.evaluate({ xp = Levels.xpFor(4), money = 400, cars = { [VAN] = true }, car = VAN, progress = {} })
check("an easy mission: no vest, no gun, no friend", find(easy, "vest") == nil and find(easy, "gun") == nil and find(easy, "friend") == nil)
local duo = Readiness.evaluate({ xp = Levels.xpFor(15), money = 0, cars = { [VAN] = true }, car = VAN, progress = story })
local partner = find(duo, "partner") :: Readiness.Check
check("the DUO chapter: a partner in your crew is required, INVITE", duo.mission ~= nil and duo.mission.duo and partner ~= nil and partner.required and not partner.done and partner.action == "invite" and not duo.ready
	and Readiness.chapterLine(duo.mission) == "DUO · Partners in Crime · 1/6", duo.mission and Readiness.chapterLine(duo.mission))
local paired = Readiness.evaluate({ xp = Levels.xpFor(15), money = 0, cars = { [VAN] = true }, car = VAN, progress = story, crewSize = 1 })
check("… with a crew member: done", (find(paired, "partner") :: Readiness.Check).done and find(paired, "friend") == nil)
local far = Readiness.evaluate({ xp = Levels.xpFor(15), money = 0, cars = { [VAN] = true }, car = VAN, progress = story, crewSize = 1, partnerNear = false })
local away = find(far, "partner") :: Readiness.Check
check("… the partner far away: not done, bring them here (the server's StartRange)", not away.done and not far.ready and away.action == nil and string.find(away.detail or "", `within {Config.Missions.Duo.StartRange} studs`, 1, true) ~= nil, away.detail)
local replay = Readiness.evaluate({ xp = Levels.xpFor(15), money = 0, cars = { [VAN] = true }, car = VAN, progress = all })
check("a replay for stars: no level row, its words", replay.mission ~= nil and replay.mission.replay and find(replay, "level") == nil and Readiness.chapterLine(replay.mission) == "Replay for stars · Empty Shelves")

-- ── 6.14 review: NIGHT ONLY, and whether START can work now ───────────────

local nightly: { string } = {}
for _, mission in Missions.List do
	if table.find(mission.twists or {}, "night") then
		table.insert(nightly, mission.id)
	end
end
check("the night missions (the test's premise)", table.find(nightly, "power_6") ~= nil and #nightly >= 3, table.concat(nightly, ", "))
local base = { mission = "power_6", xp = Levels.xpFor(15), money = 0, cars = { [VAN] = true }, car = VAN, progress = {} }
local function with(extra: { [string]: any }): Readiness.Result
	local input = table.clone(base) :: { [string]: any }
	for k, v in extra do
		input[k] = v
	end
	return Readiness.evaluate(input :: any)
end
local day = with({ night = false })
local nightRow = find(day, "night") :: Readiness.Check
check("a NIGHT ONLY mission by day: a required row, not ready", nightRow ~= nil and nightRow.required and not nightRow.done and not day.ready and string.find(nightRow.detail or "", "after dark", 1, true) ~= nil, ids(day))
local dark = with({ night = true })
check("… at night: done, READY · START", (find(dark, "night") :: Readiness.Check).done and dark.ready and dark.start.can and Readiness.status(dark) == "READY · START" and (Readiness.badge(dark)) == "✔ READY · START")
check("… a day mission has no night row", find(Readiness.evaluate({ mission = "dispatch_1", xp = Levels.xpFor(4), night = false }), "night") == nil)
local going = with({ night = true, active = "power_6" })
check("this mission running: IN PROGRESS", not going.start.can and going.start.label == "IN PROGRESS" and Readiness.status(going) == "IN PROGRESS" and (Readiness.badge(going)) == "▶ IN PROGRESS")
local led = with({ night = true, crewOwner = "Ann" })
local ledBadge, ledTone = Readiness.badge(led)
check("in somebody else's crew: LEADER PICKS (never READY · START)", not led.start.can and led.start.label == "LEADER PICKS" and Readiness.status(led) == "LEADER PICKS" and ledBadge == "👥 LEADER PICKS" and ledTone == "wait")
local working = with({ night = true, onJob = true })
check("a job of yours runs: AFTER YOUR RUN", not working.start.can and working.start.label == "AFTER YOUR RUN" and Readiness.status(working) == "READY · AFTER YOUR RUN")
local walking = with({ night = true, carOut = false })
local walkBadge, walkTone = Readiness.badge(walking)
check("no car of yours out: CALL CAR", not walking.start.can and walking.start.label == "CALL CAR" and walkBadge == "✔ READY · CALL CAR" and walkTone == "wait" and walking.ready)
local lends = Readiness.evaluate({ mission = "clinic_2", xp = Levels.xpFor(5), cars = { [VAN] = true }, car = VAN, progress = progressTo("clinic", 1), carOut = false })
check("… 7.x: no mission lends a vehicle: Code Blue wants your van out too (CALL CAR)", lends.ready and not lends.start.can and lends.start.label == "CALL CAR", lends.start.label)
check("not ready: NOT READY, the rows say why", not day.start.can and day.start.label == "NOT READY" and (Readiness.badge(day)) == `✖ {string.upper(Readiness.status(day))}`)
check("the key follows START's label", Readiness.key(dark) ~= Readiness.key(walking))
check("nothing left: ALL DONE", none.start.label == "ALL DONE" and not none.start.can and (Readiness.badge(none)) == "★ ALL YOURS")

-- ── A level-locked chapter: the next chapter's first mission and its level ─

local waits = Readiness.evaluate({ xp = Levels.xpFor(4) + 500, money = 2400, cars = { [VAN] = true }, car = VAN, progress = progressTo("dispatch", 6) })
local reach = find(waits, "level") :: Readiness.Check
check("First Shift done at level 4: Code Red's House Call, Reach level 5", waits.mission ~= nil and waits.mission.chapter == "Code Red" and reach ~= nil and reach.text == "Reach level 5" and not reach.done and not waits.ready)
check("… its XP: have / need", reach.have == Levels.xpFor(4) + 500 and reach.need == Levels.xpFor(5) and reach.detail == `{string.sub(Readiness.money(Levels.xpFor(4) + 500), 2)} / {string.sub(Readiness.money(Levels.xpFor(5)), 2)} XP`)
-- The phone's own pick (a window's mission): input.mission.
local pick = Readiness.evaluate({ mission = "dispatch_3", xp = Levels.xpFor(4), progress = {} })
check("input.mission checks that one", pick.mission ~= nil and pick.mission.id == "dispatch_3")

-- The READY CHECK is drawn again only when what it shows changes: not for money.
local before = Readiness.key(Readiness.evaluate({ xp = Levels.xpFor(4), money = 100, cars = { [VAN] = true }, car = VAN }))
check("the key ignores the money, follows the rows", before == Readiness.key(Readiness.evaluate({ xp = Levels.xpFor(4), money = 2400, cars = { [VAN] = true }, car = VAN }))
	and before ~= Readiness.key(Readiness.evaluate({ xp = Levels.xpFor(4), money = 100, cars = { [VAN] = true }, car = VAN, items = { medkit = 1 } })))

-- Every story mission at its own level with a car that has the room: never a missing required row but the level.
local stuck: { string } = {}
for _, mission in Missions.List do
	if mission.duo then
		continue
	end
	local need = Economy.cargoNeed(mission.load, mission.items)
	local result = Readiness.evaluate({ mission = mission.id, xp = Levels.xpFor(15), money = 0, cars = { [VAN] = true }, car = VAN, progress = {} })
	if not result.ready and need <= 4 then
		table.insert(stuck, mission.id)
	end
end
check("every story mission: ready with level 15 and the ZDC Van (7.x: the one car)", #stuck == 0, table.concat(stuck, ", "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
