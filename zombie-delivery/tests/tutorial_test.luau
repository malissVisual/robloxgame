-- 3.7, the first-day tutorial (shared/TutorialSteps.luau): the step read from the Job payload, a hint for every step
-- and phase, Marge's dialogs. Run with tests/run_tests.py.
-- 6.5: a one-page welcome, failed run and done screen; no pages during the run; the hints are short goals.
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

for _, phase in { "welcome", "board", "retry", "done", "say", "skip" } do
	local dialog = TutorialSteps.dialog(phase, { reward = 50, text = "Hi." })
	check(`dialog for {phase}`, dialog ~= nil and #dialog.pages >= 1 and dialog.primary ~= "" and dialog.speaker ~= "")
end
-- 6.5: no pages of hers during the run (the goal card shows each step).
check("no job dialog, not even for her own job", TutorialSteps.dialog("job", nil) == nil and TutorialSteps.dialog("job", { given = true }) == nil)
check("no dialog for an unknown phase", TutorialSteps.dialog("nope", nil) == nil)
check("the welcome can be skipped", (TutorialSteps.dialog("welcome", nil) :: any).secondary == "SKIP TUTORIAL")
local done = TutorialSteps.dialog("done", { reward = 75 }) :: any
check("done names the reward", string.find(done.pages[1], "$75", 1, true) ~= nil, done.pages[1])
-- 6.5: the welcome, a failed run and the done screen are one page each.
check("done is one page", #done.pages == 1)
check("the welcome is one page", #(TutorialSteps.dialog("welcome", nil) :: any).pages == 1)
check("a failed run is one page", #(TutorialSteps.dialog("retry", nil) :: any).pages == 1)
check("done: +$ the reward, J for a job, the shops in the phone", done.pages[1] == "Delivered! +$75. Next: press J for a job. Shops are in your phone (Q → SHOP).", done.pages[1])
local said = TutorialSteps.dialog("say", nil) :: any
check("say falls back to her line", said.pages[1] == TutorialSteps.Bubble.done)
local board = TutorialSteps.dialog("board", nil) :: any
check("the speaker is her name", string.find(board.speaker, string.upper(Config.Tutorial.NpcName), 1, true) == 1, board.speaker)

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
-- 5.7: the tour after the first delivery.
local doneDialog = TutorialSteps.dialog("done", { reward = 75 }) :: any
check("done offers the tour, or CLOSE", doneDialog.primary == "SHOW ME AROUND" and doneDialog.secondary == "CLOSE")
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
check("touch: no Press J", touch(TutorialSteps.Bubble.board) == "Check the board, hon.", touch(TutorialSteps.Bubble.board))
for _, phase in { "welcome", "board", "retry", "done", "say", "skip" } do
	local dialog = TutorialSteps.dialog(phase, { reward = 50, text = "Hi." }) :: any
	for index, page in dialog.pages do
		local line = touch(page)
		check(`touch: {phase} page {index} names no key`, string.find(line, "%([A-Z]%)") == nil and string.find(line, "Press [A-Z]") == nil and string.find(line, "Hold Q") == nil, line)
	end
end
for _, name in TutorialSteps.JobSteps do
	local line = touch(TutorialSteps.hint(name, job({})))
	check(`touch: {name} hint names no key`, string.find(line, "%([A-Z]%)") == nil and string.find(line, "%f[%w]G puts") == nil, line)
end
check("touch: done names the PHONE button", touch(done.pages[1]) == "Delivered! +$75. Next: PHONE → JOBS for a job. Shops are in your phone (PHONE → SHOP).", touch(done.pages[1]))
check("touch: plain words stay", touch("Delivered! Nice work, driver.") == "Delivered! Nice work, driver.")

-- 5.0: the first job is on foot (no van), Marge gives the phone, and her last pages send you to a backpack and a bike.
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
check("the welcome: take a job, deliver it, get paid, follow NEXT", string.find(welcome, "You're a courier now. Take a job, deliver it, get paid. Follow NEXT at the top left.", 1, true) ~= nil, welcome)
check("LET'S GO gives the first job", (TutorialSteps.dialog("welcome", nil) :: any).primary == "LET'S GO")
check("the phone is a message, not a dialog", TutorialSteps.dialog("phone", nil) == nil and table.find(TutorialSteps.Phases, "phone") ~= nil)
check("the board hint: an ON FOOT job", string.find(TutorialSteps.hint("board", nil), "ON FOOT", 1, true) ~= nil)
check("two letters fit two hands", Config.Jobs.TutorialPieces == 2 and Config.Jobs.TutorialPieces <= Config.Cargo.HandsMax)
check("the tutorial's cargo is light", Config.Cargo.LightLooks[Config.Jobs.Foot.TutorialCargo.look] == true)

check("a reward", Config.Tutorial.Reward > 0)
check("a talk range", Config.Tutorial.TalkRange > 0 and Config.Tutorial.TalkRange < 12)
local half = Config.City.BlockSize / 2
check("a spot inside the depot block", math.abs(Config.Tutorial.NpcSpot[1]) < half and math.abs(Config.Tutorial.NpcSpot[2]) < half)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
