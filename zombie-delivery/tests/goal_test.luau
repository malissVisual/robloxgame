-- 6.5, the NEXT card (shared/Goal.luau): every situation gives its words, its place and its key; the pill at the lower
-- centre (`action`) shows only what you can press right now. Run with tests/run_tests.py.
local Config = require("./Config")
local Goal = require("./Goal")
local TutorialSteps = require("./TutorialSteps")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- A foot job's payload as server/Jobs.luau payload() sends it (only the fields the card reads).
local function job(fields: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {
		stage = "pickup",
		handling = "drive",
		stopLabel = "PICK UP at Tony's Pizza",
		step = "Walk to Tony: the red circle",
		needed = 2,
		delivered = 0,
		piece = "pizza",
		pieces = "pizzas",
		person = "Tony",
		mode = "foot",
	}
	for key, value in fields do
		out[key] = value
	end
	return out
end

local function show(card: Goal.Card): string
	return `{card.kind} | {card.title} | {card.place} | {card.distance} | {card.key} | {card.action and card.action.text}`
end

-- ── The labels ─────────────────────────────────────────────────────────────
do
	local a, j, r = Goal.parseLabel("DELIVER to Sarah, Apt 4C")
	check("label: deliver", a == "Deliver" and j == "to" and r == "Sarah, Apt 4C", `{a}|{j}|{r}`)
	a, j, r = Goal.parseLabel("PICK UP at Tony's Pizza")
	check("label: pick up", a == "Pick up" and j == "at" and r == "Tony's Pizza", `{a}|{j}|{r}`)
	a, j, r = Goal.parseLabel("PICK UP the papers at Elm St 12")
	check("label: the quiet words before at", a == "Pick up the papers" and j == "at" and r == "Elm St 12", `{a}|{j}|{r}`)
	a, j, r = Goal.parseLabel("UNLOAD AT THE NEW HOME, 42 Maple St")
	check("label: a house number starts the place", a == "Unload at the new home" and r == "42 Maple St", `{a}|{j}|{r}`)
	a, j, r = Goal.parseLabel("DELIVER THE AMMO TO Military Base")
	check("label: a shouted joiner", a == "Deliver the ammo" and j == "to" and r == "Military Base", `{a}|{j}|{r}`)
	check("key: trailing", Goal.keyOf("Pick up a pizza from Tony (E)") == "E")
	check("key: the last one", Goal.keyOf("Put it down (G) and open the back (E)") == "E")
	check("key: none", Goal.keyOf("Wait while the kids get on (3/5)") == nil)
	check("without key: the only one", Goal.withoutKey("Pick up another pizza (E) · backpack 1 / 2") == "Pick up another pizza · backpack 1 / 2", Goal.withoutKey("Pick up another pizza (E) · backpack 1 / 2"))
	check("without key: the trailing one of two", Goal.withoutKey("Put it down (G) and open the back (E)") == "Put it down (G) and open the back")
	check("money", Goal.money(1250) == "$1,250" and Goal.money(45) == "$45", Goal.money(1250))
end

-- ── No job ─────────────────────────────────────────────────────────────────
do
	local card = Goal.now({ deliveries = 3, distance = 25 })
	check("no job: take a delivery job, press J", card.kind == "nojob" and card.title == "Take a delivery job" and card.key == "J" and card.distance == 25 and card.opensBoard == true, show(card))
	check("no job: the place says J and the board", card.place == "Press J · or the job board", card.place)
	check("no job: no pill", card.action == nil)
	card = Goal.now({ deliveries = 0, distance = 12 })
	check("a new save after Marge: the first job", card.kind == "first" and card.title == "Take your first job" and card.key == "J", show(card))
	card = Goal.now({ deliveries = 0, touch = true })
	check("touch: no keys, tap the card", card.key == nil and card.place == "Tap here · or the job board", show(card))
	card = Goal.now({ deliveries = 2, holding = "crate" })
	check("cargo in your hands without a job: G puts it down", card.action ~= nil and card.action.key == "G" and card.action.text == "Put it down", show(card))
end

-- ── The tutorial ───────────────────────────────────────────────────────────
do
	local card = Goal.now({ deliveries = 0, tutorial = "welcome", distance = 18 })
	check("tutorial welcome: talk to Marge", card.kind == "tutorial" and string.find(card.title, Config.Tutorial.NpcName, 1, true) ~= nil and card.key == "E" and card.distance == 18, show(card))
	card = Goal.now({ deliveries = 0, tutorial = "board" })
	check("tutorial board: open the board", card.kind == "tutorial" and card.key == "J" and card.opensBoard == true, show(card))
	card = Goal.now({ deliveries = 0, tutorial = "retry" })
	check("tutorial retry: Marge has another", card.kind == "tutorial" and string.find(card.title, "another job", 1, true) ~= nil, show(card))
	card = Goal.now({ deliveries = 0, tutorial = "welcome", touch = true })
	check("tutorial on touch: no (E)", card.key == nil and string.find(card.title, "(E)", 1, true) == nil, card.title)
	card = Goal.now({ deliveries = 0, tutorial = "job", job = job({}) })
	local hint = TutorialSteps.hint(TutorialSteps.jobStep(job({})), job({}))
	-- (6.5 review: on the way to a stop the trip's own card stays: Marge's step there is the one at the stop)
	check("tutorial job, on the way: the trip's card, not her next step", card.kind == "to_pickup" and card.title == "Pick up 2 pizzas" and card.place == "Tony's Pizza", show(card))
	local at = job({ step = "Pick up a pizza (E)", handling = "carry" })
	card = Goal.now({ deliveries = 0, tutorial = "job", job = at })
	hint = TutorialSteps.hint(TutorialSteps.jobStep(at), at)
	check("tutorial job, at the stop: her hint is the title", hint == "" or card.title == hint, show(card))
	card = Goal.now({ deliveries = 0, tutorial = "retry", result = { success = false, total = 0 } })
	check("tutorial retry wins over the failed result", card.kind == "tutorial", show(card))
	card = Goal.now({ deliveries = 3, seat = "bus" })
	check("on a bus: E rings the stop", card.action ~= nil and card.action.key == "E" and string.find(card.action.text, "Stop", 1, true) ~= nil, show(card))
	card = Goal.now({ deliveries = 3, seat = "seat" })
	check("in a seat: E gets out", card.action ~= nil and card.action.text == "Get out", show(card))
	local door = job({ stage = "drop", handling = "carry", carrying = "pizza", stopLabel = "DELIVER to Sarah, Apt 4C", person = "Sarah", step = "Hand it over to Sarah (E)" })
	card = Goal.now({ deliveries = 0, tutorial = "job", job = door, canThrow = true })
	hint = TutorialSteps.hint(TutorialSteps.jobStep(door), door)
	check("tutorial job at the door: her hint, the pill stays", card.title == hint and card.action ~= nil and card.action.key == "E", show(card))
	card = Goal.now({ deliveries = 0, tutorial = "job", job = job({ mission = { number = 1 } }) })
	check("tutorial with a mission: the mission's own card", card.title == "Pick up 2 pizzas" and card.tag == "MISSION 1", show(card))
end

-- ── A delivery on foot ─────────────────────────────────────────────────────
do
	local card = Goal.now({ deliveries = 1, job = job({}), distance = 120 })
	check("going to the pickup: pick up 2 pizzas", card.kind == "to_pickup" and card.title == "Pick up 2 pizzas" and card.place == "Tony's Pizza" and card.distance == 120, show(card))
	check("going to the pickup: no pill", card.action == nil)
	check("going to the pickup: the tag", card.tag == "NEXT")
	card = Goal.now({ deliveries = 1, job = job({ handling = "carry", step = "Pick up a pizza from Tony (E)" }), distance = 6 })
	check("at the pickup: pick up 2 pizzas (E)", card.kind == "pickup" and card.title == "Pick up 2 pizzas (E)" and card.key == "E", show(card))
	check("at the pickup: the pill E Pick up pizza", card.action ~= nil and card.action.key == "E" and card.action.text == "Pick up pizza", show(card))
	card = Goal.now({ deliveries = 1, job = job({ handling = "carry", delivered = 1, step = "Pick up another pizza (E) · backpack 1 / 2" }) })
	check("one picked up: a pizza left", card.title == "Pick up a pizza (E)", card.title)
	local drop = { stage = "drop", stopLabel = "DELIVER to Sarah, Apt 4C", person = "Sarah", step = "Walk to Sarah with the pizzas: the red circle" }
	card = Goal.now({ deliveries = 1, job = job(drop), distance = 300 })
	check("carrying to the drop: deliver to Sarah · Apt 4C", card.kind == "to_drop" and card.title == "Deliver to Sarah" and card.place == "Apt 4C" and card.distance == 300, show(card))
	check("carrying to the drop: no pill", card.action == nil)
	drop.handling = "carry"
	drop.step = "Hand it over to Sarah (E)"
	card = Goal.now({ deliveries = 1, job = job(drop), distance = 8, canThrow = true })
	check("at the door: hand it over (E), or hold X to throw", card.kind == "door" and card.title == "Hand it over (E), or hold X to throw" and card.place == "Sarah · Apt 4C", show(card))
	check("at the door: the pill E Hand it over · or hold X to throw", card.action ~= nil and card.action.key == "E" and card.action.text == "Hand it over" and card.action.sub == "or hold X to throw", show(card))
	card = Goal.now({ deliveries = 1, job = job(drop), distance = 8, canThrow = false })
	check("at the door, nothing to throw: hand it over (E)", card.title == "Hand it over (E)" and card.action ~= nil and card.action.sub == nil, show(card))
	card = Goal.now({ deliveries = 1, job = job(drop), canThrow = true, touch = true })
	check("at the door on touch: tap THROW, no keys", card.title == "Hand it over, or tap THROW" and card.key == nil and card.action ~= nil and card.action.key == nil, show(card))
	drop.step = "Nobody's home: leave them at the door (E)"
	card = Goal.now({ deliveries = 1, job = job(drop) })
	check("nobody's home: leave them at the door", card.kind == "door" and card.title == "Leave them at the door (E)", show(card))
	card = Goal.now({ deliveries = 1, job = job({ handling = "carry", step = "Pick up the pizza you put down (E)", looseAt = { 1, 2, 3 } }) })
	check("a piece put down: the server's words, E", card.kind == "step" and card.title == "Pick up the pizza you put down (E)" and card.action ~= nil and card.action.text == "Pick up the pizza you put down", show(card))
end

-- ── A vehicle job ──────────────────────────────────────────────────────────
do
	local van = { mode = "car", stopLabel = "PICK UP at the Warehouse, Dock Rd 4", piece = "crate", pieces = "crates", needed = 3 }
	local function vanJob(fields: { [string]: any }): { [string]: any }
		local out = job(van)
		for key, value in fields do
			out[key] = value
		end
		return out
	end
	local card = Goal.now({ deliveries = 4, job = vanJob({ step = "Drive to the red circle" }), distance = 410 })
	check("driving to the pickup", card.kind == "to_pickup" and card.title == "Pick up 3 crates" and card.place == "the Warehouse, Dock Rd 4", show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "carry", step = "Park in the red circle" }) })
	check("park: the server's words, no pill", card.kind == "step" and card.title == "Park in the red circle" and card.action == nil, show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "carry", step = "Get out and open the back (E)" }) })
	check("open the back (E)", card.kind == "step" and card.key == "E" and card.action ~= nil and card.action.text == "Get out and open the back", show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "carry", step = "Load it into the back of the van (E)" }) })
	check("load (E)", card.title == "Load it into the back of the van (E)" and card.action ~= nil and card.action.key == "E", show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "carry", stage = "drop", stopLabel = "DELIVER to Bob, 42 Maple St", step = "Take a crate out of the van (E)" }) })
	check("unload (E)", card.kind == "step" and card.place == "42 Maple St" and card.action ~= nil, show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "carry", step = "Get out and close the back (E)" }) })
	check("a key while driving away is an action", card.kind == "step" and card.key == "E", show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "drive", step = "Get out and close the back (E)" }) })
	check("a key on the way is an action too", card.kind == "step" and card.key == "E", show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "board", step = "Wait while the kids get on (2/5)" }) })
	check("wait: no pill", card.kind == "wait" and card.action == nil, show(card))
	card = Goal.now({ deliveries = 4, job = vanJob({ handling = "carry", step = "Put it down (G) and open the back (E)" }) })
	check("two keys: the pill's key is the trailing one", card.action ~= nil and card.action.key == "E" and card.action.text == "Put it down (G) and open the back", show(card))
end

-- ── Blocked, defend, a mission ─────────────────────────────────────────────
do
	local card = Goal.now({ deliveries = 9, job = job({ stage = "drop", handling = "carry", step = "Hold out first! Nothing gets unloaded until the area is safe." }) })
	check("a blocked stop", card.kind == "blocked" and card.title == "Hold out first!" and card.place == "Nothing gets unloaded until the area is safe.", show(card))
	card = Goal.now({ deliveries = 9, job = job({ stage = "drop", handling = "carry", step = "HOLD OUT 0:23 · keep them off Bob!" }) })
	check("defend: the clock", card.kind == "defend" and card.title == "Hold out 0:23" and card.place == "Keep them off Bob!" and card.action == nil, show(card))
	card = Goal.now({ deliveries = 9, job = job({ mission = { number = 3, name = "Iron Supply" }, stopLabel = "LOAD THE AMMO at the Armory", step = "Drive to the red circle" }) })
	check("a mission: its tag", card.tag == "MISSION 3" and card.kind == "to_pickup" and card.title == "Load the ammo" and card.place == "the Armory", show(card))
	-- 6.15, the fixed missions: the tag counts the mission's enemies; delivered with some left, the card says to clear them.
	local enemies = { killed = 7, total = 20, left = 13, label = "ZOMBIES" }
	card = Goal.now({ deliveries = 9, job = job({ mission = { number = 3, name = "Iron Supply", enemies = enemies }, stopLabel = "LOAD THE AMMO at the Armory", step = "Drive to the red circle" }) })
	check("6.15: a mission's tag counts its zombies", card.tag == "MISSION 3 · ZOMBIES 7/20" and card.kind == "to_pickup", card.tag)
	check("6.15: the count's words", Goal.enemyLine({ enemies = { killed = 2, total = 18, label = "ENEMIES" } }) == "ENEMIES 2/18" and Goal.enemyLine({ number = 1 }) == nil and Goal.enemyLine(nil) == nil)
	check("6.15: never more killed than there are", Goal.enemyLine({ enemies = { killed = 25, total = 20, label = "ZOMBIES" } }) == "ZOMBIES 20/20")
	local clearing = job({
		mission = { number = 3, clearing = true, enemies = { killed = 17, total = 20, left = 3, label = "ZOMBIES" } },
		stage = "clear",
		handling = "drive",
		stopLabel = "CLEAR THE ZOMBIES at Lighthouse Point",
		step = "Clear the zombies: 3 left",
		person = "3 ZOMBIES LEFT",
	})
	card = Goal.now({ deliveries = 9, distance = 120, job = clearing })
	check("6.15: delivered, zombies left: clear them, where the nearest are", card.kind == "clear" and card.title == "Clear the zombies: 3 left" and card.place == "Lighthouse Point" and card.distance == 120 and card.action == nil and card.tag == "MISSION 3 · ZOMBIES 17/20", show(card))
	clearing.step = ""
	card = Goal.now({ deliveries = 9, job = clearing })
	check("6.15: the clearing card without the server's words", card.kind == "clear" and card.title == "Clear the zombies: 3 left", show(card))
end

-- ── Delivered ──────────────────────────────────────────────────────────────
do
	local card = Goal.now({ deliveries = 5, result = { success = true, total = 45 } })
	check("delivered: +$45, J for the next job", card.kind == "delivered" and card.title == "Delivered! +$45" and card.place == "Press J for the next job" and card.key == "J" and card.opensBoard == true, show(card))
	card = Goal.now({ deliveries = 5, result = { success = false } })
	check("failed: J for another job", card.kind == "failed" and card.key == "J", show(card))
	card = Goal.now({ deliveries = 5, result = { success = true, total = 45 }, job = job({}) })
	check("a new job wins over the result", card.kind == "to_pickup", show(card))
	check("Config.Goal: the result shows a few seconds", Config.Goal.ResultShown > 2 and Config.Goal.ResultShown <= 15)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
