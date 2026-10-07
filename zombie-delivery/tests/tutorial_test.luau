-- 3.7, the first-day tutorial (shared/TutorialSteps.luau): the step read from the Job payload, a hint for every step
-- and phase, Marge's dialogs. Run with tests/run_tests.py.
-- 6.5: a one-page welcome, failed run and done screen; no pages during the run; the hints are short goals.
-- 6.7: the welcome's SHOW ME / SKIP TUTORIAL, the arrow tour of the screen (ScreenTour, tourLine, placeArrow), the
-- "ready" page (TAKE A JOB / SKIP TUTORIAL); no pages during play (board, retry, done), no job of hers.
local Config = require("./Config")
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

local step = TutorialSteps.jobStep
-- A Job payload as server/Jobs.luau payload() sends it (only the fields the tutorial reads).
local function job(fields: { [string]: any }): { [string]: any }
	local out: { [string]: any } = { stage = "pickup", handling = "drive", delivered = 0, piece = "medicine box", person = "Doctor Ellie" }
	for key, value in fields do
		out[key] = value
	end
	return out
end

check("no job", step(nil) == "none")
check("driving to the pickup", step(job({})) == "drive_pickup", step(job({})))
check("at the pickup", step(job({ handling = "carry" })) == "pickup")
check("one loaded, the next", step(job({ handling = "carry", delivered = 1 })) == "pickup_more")
check("carrying at the pickup", step(job({ handling = "carry", carrying = "crate" })) == "carry")
check("carrying while still out of the circle", step(job({ handling = "drive", carrying = "crate" })) == "carry")
check("put down", step(job({ handling = "carry", looseAt = { 1, 2, 3 } })) == "loose")
check("driving to the drop", step(job({ stage = "drop" })) == "drive_drop")
check("at the drop", step(job({ stage = "drop", handling = "carry" })) == "unload")
check("carrying at the drop", step(job({ stage = "drop", handling = "carry", carrying = "crate" })) == "handover")
check("a mission explains itself", step(job({ mission = { id = "x" } })) == "other")
check("a special job explains itself", step(job({ jobType = { name = "Pizza Rush" } })) == "other")
check("a serve stop", step(job({ handling = "serve" })) == "other")
check("an empty carrying is nothing", step(job({ handling = "carry", carrying = "" })) == "pickup")

for _, name in TutorialSteps.JobSteps do
	check(`hint for {name}`, TutorialSteps.hint(name, job({})) ~= "", name)
end
for _, name in { "welcome", "board", "retry" } do
	check(`hint for the {name} phase`, TutorialSteps.hint(name, nil) ~= "")
end
check("no hint for other", TutorialSteps.hint("other", job({})) == "")
local pickup = TutorialSteps.hint("pickup", job({}))
check("the pickup hint names the piece and the giver", string.find(pickup, "a medicine box from Doctor Ellie", 1, true) ~= nil, pickup)
check("an before a vowel", string.find(TutorialSteps.hint("pickup", job({ piece = "ice box" })), "an ice box", 1, true) ~= nil)
check("a hint without a payload still reads", string.find(TutorialSteps.hint("drive_pickup", nil), "the shop", 1, true) ~= nil)
-- The texts must stay true with the 3.7 back rules (one light piece opens it, two need G first): no hand rule promised.
for _, name in TutorialSteps.JobSteps do
	local text = string.lower(TutorialSteps.hint(name, job({})))
	check(`{name}: no hand rule promised`, string.find(text, "empty hands", 1, true) == nil)
end

for _, phase in { "welcome", "ready", "say", "skip" } do
	local dialog = TutorialSteps.dialog(phase, { reward = 50, text = "Hi." })
	check(`dialog for {phase}`, dialog ~= nil and #dialog.pages >= 1 and dialog.primary ~= "" and dialog.speaker ~= "")
end
-- 6.7: no page of hers during play.
for _, phase in { "tour", "board", "job", "retry", "done", "phone" } do
	check(`no dialog during play: {phase}`, TutorialSteps.dialog(phase, { reward = 50 }) == nil)
end
-- 6.5: no pages of hers during the run (the goal card shows each step).
check("no job dialog, not even for her own job", TutorialSteps.dialog("job", nil) == nil and TutorialSteps.dialog("job", { given = true }) == nil)
check("no dialog for an unknown phase", TutorialSteps.dialog("nope", nil) == nil)
check("the welcome can be skipped", (TutorialSteps.dialog("welcome", nil) :: any).secondary == "SKIP TUTORIAL")
-- 6.7: the tour's end, one page: TAKE A JOB (any job) or SKIP TUTORIAL, the bonus named.
local ready = TutorialSteps.dialog("ready", { reward = 75 }) :: any
check("ready: one page", #ready.pages == 1)
check("ready: take your first job", string.find(ready.pages[1], "Ready? Take your first job", 1, true) == 1, ready.pages[1])
check("ready names the bonus", string.find(ready.pages[1], "+$75", 1, true) ~= nil, ready.pages[1])
check("ready: TAKE A JOB or SKIP TUTORIAL", ready.primary == "TAKE A JOB" and ready.secondary == "SKIP TUTORIAL")
check("ready without data: Config's reward", string.find((TutorialSteps.dialog("ready", nil) :: any).pages[1], `+${Config.Tutorial.Reward}`, 1, true) ~= nil)
check("the welcome is one page", #(TutorialSteps.dialog("welcome", nil) :: any).pages == 1)
local said = TutorialSteps.dialog("say", nil) :: any
check("say falls back to her line", said.pages[1] == TutorialSteps.Bubble.done and said.primary == "OK")
local talk = TutorialSteps.dialog("say", { board = true, reward = 50 }) :: any
check("talking to her while she waits: OPEN THE BOARD or LATER", talk.primary == "OPEN THE BOARD" and talk.secondary == "LATER" and #talk.pages == 1)
check("talking to her: any job, the bonus", string.find(talk.pages[1], "any job", 1, true) ~= nil and string.find(talk.pages[1], "+$50", 1, true) ~= nil, talk.pages[1])
local welcomeDialog = TutorialSteps.dialog("welcome", nil) :: any
check("the speaker is her name", string.find(welcomeDialog.speaker, string.upper(Config.Tutorial.NpcName), 1, true) == 1, welcomeDialog.speaker)
check("skip asks first: SKIP TUTORIAL or KEEP IT", (TutorialSteps.dialog("skip", nil) :: any).primary == "SKIP TUTORIAL" and (TutorialSteps.dialog("skip", nil) :: any).secondary == "KEEP IT")

-- 4.2: on a touch screen her words name no keys.
local touch = TutorialSteps.forTouch
check("touch: no (E)", touch("Carry it to Bob (E)") == "Carry it to Bob", touch("Carry it to Bob (E)"))
check("touch: the G advice names the button", touch("Hands full? G puts it down while you open the back") == "Hands full? PUT DOWN sets it down while you open the back")
-- 5.7: the van's hints are gone (nobody has a car on the first day): no step says van; a bike rides.
for _, name in TutorialSteps.JobSteps do
	local line = TutorialSteps.hint(name, job({}))
	check(`{name}: no van hint any more`, string.find(string.lower(line), "van", 1, true) == nil, line)
end
-- 6.5: the hints are short imperative goals (the HUD's goal card shows them).
for _, name in TutorialSteps.JobSteps do
	local line = TutorialSteps.hint(name, job({ stopLabel = "PICK UP the letters at Post Office" }))
	check(`{name}: a short goal`, #line <= 60 and string.find(line, "^%u") ~= nil, line)
end
check("going to the pickup: the stop's label as a goal", TutorialSteps.hint("drive_pickup", job({ stopLabel = "PICK UP the letters at the Post Office" })) == "Pick up the letters at the Post Office")
check("going to the drop: deliver to the person · the address", TutorialSteps.hint("drive_drop", job({ stage = "drop", stopLabel = "DELIVER to Sarah, Apt 4C" })) == "Deliver to Sarah · Apt 4C")
check("no label: the giver and the pieces", TutorialSteps.hint("drive_pickup", job({ pieces = "letters" })) == "Pick up the letters at Doctor Ellie")
check("at the door: hand it over", TutorialSteps.hint("handover", job({ stage = "drop", carrying = "crate" })) == "Hand it over (E)")
-- 5.7: the world tour (6.7: SHOW ME AROUND in the phone's SETTINGS).
check("the tour: the dock, the bus stop, the board", #TutorialSteps.Tour == 3 and TutorialSteps.Tour[1] == "dock" and TutorialSteps.Tour[2] == "bus" and TutorialSteps.Tour[3] == "board")
for index, step in TutorialSteps.Tour do
	local dialog = TutorialSteps.tourDialog(step, { dock = "Maple St · 3rd Ave", stop = "Cedar St / 6th Ave" }) :: any
	check(`tour {step}: one short page, skippable`, dialog ~= nil and #dialog.pages == 1 and #dialog.pages[1] <= 200 and dialog.secondary == "SKIP TOUR", dialog and dialog.pages[1])
	check(`tour {step}: NEXT, the last OPEN THE BOARD`, dialog.primary == (if index == #TutorialSteps.Tour then "OPEN THE BOARD" else "NEXT"))
	local line = touch(dialog.pages[1])
	check(`tour {step} on touch names no key`, string.find(line, "%([A-Z]%)") == nil and string.find(line, "%f[%w]Q opens") == nil, line)
end
check("the dock page names the dock", string.find((TutorialSteps.tourDialog("dock", { dock = "Maple St" }) :: any).pages[1], "Maple St", 1, true) ~= nil)
check("the bus page names the stop", string.find((TutorialSteps.tourDialog("bus", { stop = "Cedar St / 6th Ave" }) :: any).pages[1], "Cedar St / 6th Ave", 1, true) ~= nil)
check("the board page: Q, JOBS", string.find((TutorialSteps.tourDialog("board", nil) :: any).pages[1], "Q opens your phone, JOBS", 1, true) ~= nil)
check("no tour page for an unknown step", TutorialSteps.tourDialog("nope", nil) == nil)
check("touch: no Press J", touch(TutorialSteps.Bubble.board) == "Take any job you like, hon.", touch(TutorialSteps.Bubble.board))
for _, phase in { "welcome", "ready", "say", "skip" } do
	local dialog = TutorialSteps.dialog(phase, { reward = 50, text = "Hi.", board = phase == "say" }) :: any
	for index, page in dialog.pages do
		local line = touch(page)
		check(`touch: {phase} page {index} names no key`, string.find(line, "%([A-Z]%)") == nil and string.find(line, "Press [A-Z]") == nil and string.find(line, "Hold Q") == nil, line)
	end
end
for _, name in TutorialSteps.JobSteps do
	local line = touch(TutorialSteps.hint(name, job({})))
	check(`touch: {name} hint names no key`, string.find(line, "%([A-Z]%)") == nil and string.find(line, "%f[%w]G puts") == nil, line)
end
check("touch: J and Q name the PHONE button", touch("Next: press J for a job. Shops are in your phone (Q → SHOP).") == "Next: PHONE → JOBS for a job. Shops are in your phone (PHONE → SHOP).", touch("Next: press J for a job. Shops are in your phone (Q → SHOP)."))
check("touch: plain words stay", touch("Delivered! Nice work, driver.") == "Delivered! Nice work, driver.")

-- 5.0: the first job is on foot (no van), Marge gives the phone, and her last pages send you to the shops and a bike.
local footJob = function(fields: { [string]: any }): { [string]: any }
	local out = job(fields)
	out.mode = "foot"
	return out
end
check("on foot: walking to the pickup", step(footJob({})) == "drive_pickup")
check("on foot: walking to the drop with letters in hand", step(footJob({ stage = "drop", carrying = "crate" })) == "handover")
for _, name in TutorialSteps.JobSteps do
	local line = TutorialSteps.hint(name, footJob({}))
	check(`on foot: {name} hint, no van`, line ~= "" and string.find(string.lower(line), "van", 1, true) == nil, line)
	check(`on foot touch: {name} names no key`, string.find(touch(line), "%([A-Z]%)") == nil, touch(line))
end
check("on foot: hand over", TutorialSteps.hint("handover", footJob({})) == "Hand it over (E)")
local welcome = (TutorialSteps.dialog("welcome", nil) :: any).pages[1]
check("the welcome: Marge, dispatch, take jobs, deliver, get paid, 20 seconds", welcome == "Hi, I'm Marge, dispatch. You're a courier now: take jobs, deliver, get paid. Let me show you around in 20 seconds.", welcome)
check("SHOW ME starts the tour (no job of hers)", (TutorialSteps.dialog("welcome", nil) :: any).primary == "SHOW ME")
check("the phone is a message, not a dialog", TutorialSteps.dialog("phone", nil) == nil and table.find(TutorialSteps.Phases, "phone") ~= nil)
check("tour is a phase", table.find(TutorialSteps.Phases, "tour") ~= nil)
check("the board hint: your first job, J", TutorialSteps.hint("board", nil) == "Take your first job (J)", TutorialSteps.hint("board", nil))
check("the retry hint: another job, J", TutorialSteps.hint("retry", nil) == "Take another job (J)", TutorialSteps.hint("retry", nil))
check("no hint during the tour (the arrows say it)", TutorialSteps.hint("tour", nil) == "")
check("she gives no job: no give bubble", (TutorialSteps.Bubble :: any).give == nil and TutorialSteps.Bubble.tour ~= "")
check("two letters fit two hands", Config.Jobs.TutorialPieces == 2 and Config.Jobs.TutorialPieces <= Config.Cargo.HandsMax)
check("the tutorial's cargo is light", Config.Cargo.LightLooks[Config.Jobs.Foot.TutorialCargo.look] == true)

-- 6.7: the arrow tour of the screen ------------------------------------------------------------------------
local tourList = TutorialSteps.ScreenTour
local ids = {}
for _, stop in tourList do
	table.insert(ids, stop.id)
end
check("the screen tour: NEXT card, PHONE, JOBS, MAP, SHOP, BAG, the bottom bar, the minimap", table.concat(ids, ",") == "next,phone,jobs,map,shop,bag,hotbar,minimap", table.concat(ids, ","))
local wantTargets = { next = "next", phone = "phone", jobs = "jobsApp", map = "mapApp", shop = "shopApp", bag = "bagApp", hotbar = "hotbar", minimap = "minimap" }
local wantTexts = {
	next = "This card always tells you what to do next.",
	phone = "Your phone (Q): jobs, map, shops, everything.",
	jobs = "Take jobs here.",
	map = "The map and GPS.",
	shop = "Shops: tap one to get GPS there.",
	bag = "Your bag and items.",
	hotbar = "1 fists, 2 your bag, 3 your gun, 4–8 items.",
	minimap = "The minimap: M opens the big map.",
}
for index, stop in tourList do
	check(`tour {stop.id}: its target`, stop.target == wantTargets[stop.id], stop.target)
	check(`tour {stop.id}: its words`, stop.text == wantTexts[stop.id], stop.text)
	check(`tour {stop.id}: a side`, table.find({ "left", "right", "above", "below" }, stop.side) ~= nil, stop.side)
	local open = stop.target:sub(-3) == "App"
	check(`tour {stop.id}: the phone {if open then "open" else "away"}`, stop.phone == (if open then "open" else "closed"), stop.phone)
	for _, touchScreen in { false, true } do
		local line = TutorialSteps.tourLine(stop, touchScreen)
		local _, stops = string.gsub(line, "[%.!?]", "")
		check(`tour {stop.id}{if touchScreen then " (touch)" else ""}: one short sentence`, #line <= 60 and stops == 1 and string.find(line, "[%.!?]$") ~= nil and string.find(line, "^%w") ~= nil, line)
	end
	local line = TutorialSteps.tourLine(stop, true)
	check(`tour {stop.id} on touch names no key`, string.find(line, "%([A-Z]%)") == nil and string.find(line, "%f[%w]M opens") == nil and string.find(line, "^%d") == nil, line)
	check(`tour {stop.id}: step {index}`, tourList[index] == stop)
end
check("the phone's stops come together (it opens once)", tourList[3].phone == "open" and tourList[6].phone == "open" and tourList[7].phone == "closed" and tourList[2].phone == "closed")
check("about six things, eight stops at most", #tourList >= 6 and #tourList <= 8)
check("touch: the phone without its key", TutorialSteps.tourLine(tourList[2], true) == "Your phone: jobs, map, shops, everything.", TutorialSteps.tourLine(tourList[2], true))
check("a computer: the bottom bar's keys", TutorialSteps.tourLine(tourList[7], false) == wantTexts.hotbar)

-- 6.7: where the arrow and its caption go (TutorialSteps.placeArrow).
local screen = { w = 1280, h = 720 }
local caption = { w = 300, h = 110 }
local function place(target: { x: number, y: number, w: number, h: number }, side: string, size: { w: number, h: number }?): TutorialSteps.ArrowPlace
	return TutorialSteps.placeArrow({ target = target, screen = size or screen, side = side, length = 76, travel = 10, gap = 8, caption = caption })
end
local function inside(p: TutorialSteps.ArrowPlace, size: { w: number, h: number }?): boolean
	local s = size or screen
	return p.captionX >= 8 - 1e-6 and p.captionY >= 8 - 1e-6 and p.captionX + caption.w <= s.w - 8 + 1e-6 and p.captionY + caption.h <= s.h - 8 + 1e-6
end
local card = { x = 16, y = 14, w = 380, h = 90 }
local p = place(card, "right")
check("right of the NEXT card: points left", p.side == "right" and p.rotation == 90 and p.dirX == -1 and p.dirY == 0, p.side)
check("its tip a gap off the card", math.abs((p.arrowX - 38) - (card.x + card.w + 8)) < 1e-6 and p.arrowY == card.y + card.h / 2)
check("the caption beyond the arrow and its bounce", math.abs(p.captionX - (card.x + card.w + 8 + 76 + 10 + 8)) < 1e-6 and inside(p))
local tile = { x = 1040, y = 380, w = 120, h = 104 }
p = place(tile, "left")
check("left of a phone tile: points right", p.side == "left" and p.rotation == -90 and p.dirX == 1 and math.abs((p.arrowX + 38) - (tile.x - 8)) < 1e-6, p.side)
check("its caption left of the arrow, on screen", p.captionX + caption.w <= tile.x - 8 - 76 - 10 - 8 + 1e-6 and inside(p))
local bar = { x = 400, y = 640, w = 480, h = 64 }
p = place(bar, "above")
check("over the bottom bar: points down", p.side == "above" and p.rotation == 0 and p.dirY == 1 and math.abs((p.arrowY + 38) - (bar.y - 8)) < 1e-6, p.side)
check("its caption over the arrow, centred", math.abs(p.captionX - (bar.x + bar.w / 2 - caption.w / 2)) < 1e-6 and inside(p))
local top = { x = 600, y = 10, w = 80, h = 30 }
p = place(top, "below")
check("under a button: points up", p.side == "below" and p.rotation == 180 and p.dirY == -1 and inside(p), p.side)
-- No room on its side: the side with the most room.
local edge = { x = 4, y = 300, w = 200, h = 100 }
p = place(edge, "left")
check("no room on the left: the right", p.side == "right" and inside(p), p.side)
local small = { w = 390, h = 844 }
p = place({ x = 20, y = 20, w = 300, h = 90 }, "right", small)
check("a narrow phone: under the card instead", p.side == "below" and inside(p, small), p.side)
p = place({ x = 1100, y = 20, w = 160, h = 44 }, "left")
check("PHONE top right: left of it", p.side == "left" and inside(p), p.side)
p = place({ x = 16, y = 560, w = 200, h = 150 }, "right")
check("the minimap bottom left: the caption kept on screen", p.side == "right" and inside(p), p.captionY)
p = place(card, "sideways")
check("an unknown side: under it, or where there is room", p.side == "below" or p.side == "right", p.side)
check("the tour's numbers", Config.Tutorial.TourBounce > 0 and Config.Tutorial.TourBounceSpeed > 0 and Config.Tutorial.TourGap >= 0 and Config.Tutorial.TourCaptionWidth >= 240)
check("the welcome comes on its own about 2 s after PLAY", Config.Tutorial.StartDelay >= 1 and Config.Tutorial.StartDelay <= 3)

check("a reward", Config.Tutorial.Reward > 0)
check("a talk range", Config.Tutorial.TalkRange > 0 and Config.Tutorial.TalkRange < 12)
local half = Config.City.BlockSize / 2
check("a spot inside the depot block", math.abs(Config.Tutorial.NpcSpot[1]) < half and math.abs(Config.Tutorial.NpcSpot[2]) < half)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
