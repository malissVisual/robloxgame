--!strict
-- 3.7: the first-day tutorial's words and steps (pure: no Roblox services, tested by tests/tutorial_test.luau).
-- server/Tutorial.luau decides the phase and sends it over the "Tutorial" remote; client/TutorialUi.luau shows Marge's
-- dialog for it (TutorialSteps.dialog) and a one-line hint under the objective (TutorialSteps.hint).
--
-- The phases (server → client): welcome (Marge greets a new player), board (no easy job could be made: take one from
-- the board), job (a job runs), retry (it failed or was cancelled: she offers another), done (delivered: the rest of the
-- game in a few pages, the reward), say (a single line when somebody talks to her outside the tutorial); skip is the
-- client's own question before the hint line's SKIP.
--
-- During the job the hint is read from the Job payload (server/Jobs.luau payload(): stage, handling, carrying, person,
-- piece, delivered, looseAt), the same state the HUD's own instruction comes from, so it never runs ahead of the game.
-- Only a few broad steps (drive to the pickup, pick up, carry and load, drive to the drop-off, take out, hand over):
-- the HUD's ticket says the exact key for every moment, the hint says why. The texts stay true whether the back
-- opens with a piece in your hands or not (one light piece: yes; two: put them down with G first).

local Config = require(script.Parent.Config)

local TutorialSteps = {}

export type Dialog = {
	speaker: string, -- small caps over the line ("MARGE · DISPATCHER")
	pages: { string },
	primary: string, -- the last page's action ("LET'S GO"); the earlier pages say CONTINUE
	secondary: string?, -- a quiet second action on every page ("SKIP TUTORIAL", "LATER")
}

-- The job's steps (TutorialSteps.jobStep), in the order they come.
TutorialSteps.JobSteps = { "drive_pickup", "pickup", "pickup_more", "carry", "loose", "drive_drop", "unload", "handover" }

-- Marge's speech bubbles over her head (server/Tutorial.luau, Npcs.say).
TutorialSteps.Bubble = {
	give = "Here's your first job. Off you go!",
	board = "Check the board, hon. Press J.",
	busy = "You're on a job! Get going.",
	done = "Jobs are on the board. Good luck out there.",
}

local function speaker(radio: boolean): string
	local tuning = Config.Tutorial
	return string.upper(`{tuning.NpcName} · {if radio then "radio" else tuning.NpcTitle}`)
end

local function article(noun: string): string
	local first = string.lower(string.sub(noun, 1, 1))
	return if string.find("aeiou", first, 1, true) then `an {noun}` else `a {noun}`
end

local function text(value: any, fallback: string): string
	return if type(value) == "string" and value ~= "" then value else fallback
end

-- Which step of the delivery the Job payload is at: one of JobSteps, "other" (a special job or a mission: their own
-- ticket explains them; a board / serve / lead stop) or "none" (no job).
function TutorialSteps.jobStep(job: { [string]: any }?): string
	if type(job) ~= "table" then
		return "none"
	end
	if job.mission ~= nil or job.jobType ~= nil then
		return "other"
	end
	local handling = job.handling
	if handling ~= "drive" and handling ~= "carry" then
		return "other"
	end
	local carrying = type(job.carrying) == "string" and job.carrying ~= ""
	local loose = job.looseAt ~= nil
	local delivered = if type(job.delivered) == "number" then job.delivered else 0
	if job.stage == "pickup" then
		if carrying then
			return "carry"
		elseif handling == "drive" then
			return "drive_pickup"
		elseif loose then
			return "loose"
		end
		return if delivered > 0 then "pickup_more" else "pickup"
	elseif job.stage == "drop" then
		if carrying then
			return "handover"
		elseif handling == "drive" then
			return "drive_drop"
		elseif loose then
			return "loose"
		end
		return "unload"
	end
	return "other"
end

-- The one-line hint for a phase (welcome, board, retry) or a job step (TutorialSteps.jobStep, with its payload). ""
-- when there is nothing to add to the HUD.
function TutorialSteps.hint(step: string, job: { [string]: any }?): string
	local payload: { [string]: any } = job or {}
	local piece = text(payload.piece, "parcel")
	local person = text(payload.person, if payload.stage == "drop" then "the customer" else "the shop")
	local name = Config.Tutorial.NpcName
	if step == "welcome" then
		return `Talk to {name} by the job board (E)`
	elseif step == "board" then
		return "Open the job board (J) and take a ★ job"
	elseif step == "retry" then
		return `Talk to {name} at the depot (E) for another job`
	elseif step == "drive_pickup" then
		return "Get in your van and follow the GPS line to the blue circle: the pickup"
	elseif step == "pickup" then
		return `Park in the circle, get out and pick up {article(piece)} from {person} (E)`
	elseif step == "pickup_more" then
		return `One in! Pick up the next {piece} from {person} (E)`
	elseif step == "carry" then
		return "Carry it to the back of the van and load it (E). Hands full? G puts it down while you open the back"
	elseif step == "loose" then
		return `Pick the {piece} up again (E)`
	elseif step == "drive_drop" then
		return "All loaded! Close the back of the van, get in and follow the GPS to the yellow circle: the drop-off"
	elseif step == "unload" then
		return `Get out, open the back of the van (E) and take the {piece} out (E)`
	elseif step == "handover" then
		return `Carry it to {person} (E)`
	end
	return ""
end

-- Marge's dialog for a phase the server sent (data: reward for done, text for say), nil for a phase without one.
function TutorialSteps.dialog(phase: string, data: { [string]: any }?): Dialog?
	local info: { [string]: any } = data or {}
	local name = Config.Tutorial.NpcName
	if phase == "welcome" then
		return {
			speaker = speaker(false),
			pages = {
				`Hey, you must be the new driver! I'm {name}, I run dispatch here at Zombie Delivery Co.`,
				"The city's overrun, but folks still need their stuff. We pick it up, we drive it over, we get paid.",
				"I've got an easy one for you: a short trip, ★ danger. I'll talk you through it on the radio.",
			},
			primary = "LET'S GO",
			secondary = "SKIP TUTORIAL",
		}
	elseif phase == "job" then
		if info.given ~= true then
			return nil -- (a job taken from the board: the hint is enough)
		end
		return {
			speaker = speaker(false),
			pages = { "Here's your job. The GPS line on the road and the map lead to the pickup. Get in your van and go!" },
			primary = "ON MY WAY",
		}
	elseif phase == "board" then
		return {
			speaker = speaker(false),
			pages = { "Nothing easy on my list right now. Open the job board (J) and take any ★ job: I'll talk you through it." },
			primary = "OPEN THE BOARD",
			secondary = "LATER",
		}
	elseif phase == "retry" then
		return {
			speaker = speaker(true),
			pages = {
				"That one didn't work out. Happens to everybody on day one.",
				"I've got another one ready. Take it now, or come and see me at the depot when you're set.",
			},
			primary = "ANOTHER JOB",
			secondary = "LATER",
		}
	elseif phase == "done" then
		local reward = if type(info.reward) == "number" then math.floor(info.reward) else Config.Tutorial.Reward
		return {
			speaker = speaker(true),
			pages = {
				`Delivered! Nice work, driver. There's ${reward} on top from me.`,
				"New jobs land on the board (J) every few minutes, the easiest ★ ones at the top. Missions (U) are bigger stories with better pay.",
				"Upgrade your van at Wrench Garage. Hold Q to pick a gun. And explore: the map fills in as you go.",
			},
			primary = "GOT IT",
		}
	elseif phase == "skip" then
		-- (client only: the hint line's SKIP asks first, a skipped tutorial does not come back)
		return {
			speaker = speaker(false),
			pages = { "Skip the tutorial? I won't walk you through your first job, and there's no first-day bonus." },
			primary = "SKIP TUTORIAL",
			secondary = "KEEP IT",
		}
	elseif phase == "say" then
		return {
			speaker = speaker(false),
			pages = { text(info.text, TutorialSteps.Bubble.done) },
			primary = "OK",
		}
	end
	return nil
end

return TutorialSteps
