-- 3.7, the first-day tutorial (shared/TutorialSteps.luau): the step read from the Job payload, a hint for every step
-- and phase, Marge's dialogs. Run with tests/run_tests.py.
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
	local out: { [string]: any } = { stage = "pickup", handling = "drive", delivered = 0, piece = "medicine box", person = "Dr. Novak" }
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
check("the pickup hint names the piece and the giver", string.find(pickup, "a medicine box from Dr. Novak", 1, true) ~= nil, pickup)
check("an before a vowel", string.find(TutorialSteps.hint("pickup", job({ piece = "ice box" })), "an ice box", 1, true) ~= nil)
check("a hint without a payload still reads", string.find(TutorialSteps.hint("handover", nil), "the shop", 1, true) ~= nil)
-- The texts must stay true with the 3.7 back rules (one light piece opens it, two need G first): no hand rule promised.
for _, name in TutorialSteps.JobSteps do
	local text = string.lower(TutorialSteps.hint(name, job({})))
	check(`{name}: no hand rule promised`, string.find(text, "empty hands", 1, true) == nil)
end

for _, phase in { "welcome", "board", "retry", "done", "say", "skip" } do
	local dialog = TutorialSteps.dialog(phase, { reward = 50, text = "Hi." })
	check(`dialog for {phase}`, dialog ~= nil and #dialog.pages >= 1 and dialog.primary ~= "" and dialog.speaker ~= "")
end
check("the job dialog only for her own job", TutorialSteps.dialog("job", nil) == nil and TutorialSteps.dialog("job", { given = true }) ~= nil)
check("no dialog for an unknown phase", TutorialSteps.dialog("nope", nil) == nil)
check("the welcome can be skipped", (TutorialSteps.dialog("welcome", nil) :: any).secondary == "SKIP TUTORIAL")
local done = TutorialSteps.dialog("done", { reward = 75 }) :: any
check("done names the reward", string.find(done.pages[1], "$75", 1, true) ~= nil, done.pages[1])
check("done explains the rest in 2 - 3 pages", #done.pages >= 2 and #done.pages <= 3)
local said = TutorialSteps.dialog("say", nil) :: any
check("say falls back to her line", said.pages[1] == TutorialSteps.Bubble.done)
local board = TutorialSteps.dialog("board", nil) :: any
check("the speaker is her name", string.find(board.speaker, string.upper(Config.Tutorial.NpcName), 1, true) == 1, board.speaker)

check("a reward", Config.Tutorial.Reward > 0)
check("a talk range", Config.Tutorial.TalkRange > 0 and Config.Tutorial.TalkRange < 12)
local half = Config.City.BlockSize / 2
check("a spot inside the depot block", math.abs(Config.Tutorial.NpcSpot[1]) < half and math.abs(Config.Tutorial.NpcSpot[2]) < half)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
