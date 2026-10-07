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
--
-- 5.0, from the bottom: a new player has no vehicle. Marge gives them the phone (the server's "phone" message, not a
-- phase: client/Phone.luau shows it) with their first job, ON FOOT: two letters on one street (Jobs.startTutorialJob).
-- A payload with mode = "foot" gets the walking hints (walk, pick up, hand over: no van). Her last pages send you to
-- Last Stop Supplies for a backpack and to save up for a bike (level 2).
-- 5.7: the van's hints are gone (a new player never has a car on the first day: every job step has the walking hint,
-- "Ride" on a bike). After the first delivery her last page offers SHOW ME AROUND, a short tour (TutorialSteps.Tour,
-- tourDialog): the ZDC RIDE dock by the depot, the nearest bus stop (each on the GPS: client/TutorialUi.luau), then
-- Q → BOARD. Every page can skip the rest.
-- 6.5, a tutorial that shows instead of talks: her welcome is one short page (take a job, deliver it, get paid; follow
-- NEXT at the top left), the run has no pages of hers (the HUD's goal card shows TutorialSteps.hint: short imperative
-- goals, "Pick up the letters at the Post Office", "Deliver to Sarah · Apt 4C", "Hand it over (E)"), a failed run
-- one page, and the done screen one page with the reward and where to go next (J for a job, Q → SHOP for the shops),
-- SHOW ME AROUND (the tour, still optional) or CLOSE. The tour's last page points to JOBS (the phone's 6.5 tile).

local Config = require(script.Parent.Config)

local TutorialSteps = {}

export type Dialog = {
	speaker: string, -- small caps over the line ("MARGE · DISPATCHER")
	pages: { string },
	primary: string, -- the last page's action ("LET'S GO"); the earlier pages say CONTINUE
	secondary: string?, -- a quiet second action on every page ("SKIP TUTORIAL", "LATER")
}

-- The phases the server sends (server/Tutorial.luau); "phone" (5.0) is a message, not a phase.
TutorialSteps.Phases = { "welcome", "board", "job", "retry", "done", "say", "phone" }

-- 5.7: the tour after the first delivery, in order.
TutorialSteps.Tour = { "dock", "bus", "board" }

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

-- 6.5: a stop's label from the Job payload (server/Jobs.luau: "PICK UP the letters at Post Office", "DELIVER to
-- Sarah, Apt 4C") as a goal ("Pick up the letters at Post Office", "Deliver to Sarah · Apt 4C"); nil without one.
local function goal(label: any): string?
	if type(label) ~= "string" then
		return nil
	end
	local verb, rest = string.match(label, "^(%u[%u ]-)%s+(%l.*)$")
	if not verb or not rest then
		return nil
	end
	if verb == "DELIVER" then
		rest = (string.gsub(rest, ", ", " · ", 1))
	end
	local lower = string.lower(verb)
	return `{string.upper(string.sub(lower, 1, 1))}{string.sub(lower, 2)} {rest}`
end

-- The one-line hint for a phase (welcome, board, retry) or a job step (TutorialSteps.jobStep, with its payload). ""
-- when there is nothing to add to the HUD.
-- 6.5: a short imperative goal (the HUD's goal card shows it during the run): where to go comes from the stop's own
-- label (the route and the world marker show the way), at a stop the key to press.
function TutorialSteps.hint(step: string, job: { [string]: any }?): string
	local payload: { [string]: any } = job or {}
	local piece = text(payload.piece, "parcel")
	local pieces = text(payload.pieces, `{piece}s`)
	local person = text(payload.person, if payload.stage == "drop" then "the customer" else "the shop")
	local name = Config.Tutorial.NpcName
	-- 5.0: on foot (the first job): walk, pick up, hand over. 5.7: every job step (the van's hints were never reached:
	-- nobody has a car on the first day).
	if step == "drive_pickup" then
		return goal(payload.stopLabel) or `Pick up the {pieces} at {person}`
	elseif step == "pickup" then
		return `Pick up {article(piece)} from {person} (E)`
	elseif step == "pickup_more" or step == "carry" then
		return `Pick up the next {piece} (E)`
	elseif step == "loose" then
		return `Pick the {piece} up again (E)`
	elseif step == "drive_drop" then
		return goal(payload.stopLabel) or `Deliver to {person}`
	elseif step == "unload" or step == "handover" then
		return "Hand it over (E)"
	end
	if step == "welcome" then
		return `Talk to {name} by the job board (E)`
	elseif step == "board" then
		return "Take an ON FOOT job from the board (J)"
	elseif step == "retry" then
		return `Talk to {name} at the depot (E) for another job`
	end
	return ""
end

-- Marge's dialog for a phase the server sent (data: reward for done, text for say), nil for a phase without one.
function TutorialSteps.dialog(phase: string, data: { [string]: any }?): Dialog?
	local info: { [string]: any } = data or {}
	local name = Config.Tutorial.NpcName
	if phase == "welcome" then
		-- 6.5: one short page (LET'S GO: her phone and the first easy job, on foot)
		return {
			speaker = speaker(false),
			pages = { `I'm {name}, dispatch. You're a courier now. Take a job, deliver it, get paid. Follow NEXT at the top left.` },
			primary = "LET'S GO",
			secondary = "SKIP TUTORIAL",
		}
	elseif phase == "job" then
		return nil -- 6.5: no pages during the run (the goal card and the world marker show each step)
	elseif phase == "board" then
		return {
			speaker = speaker(false),
			pages = { "Nothing easy on my list right now. Open the job board (J) and take an ON FOOT job: I'll talk you through it." },
			primary = "OPEN THE BOARD",
			secondary = "LATER",
		}
	elseif phase == "retry" then
		return {
			speaker = speaker(true),
			pages = { "That one didn't work out. Happens on day one. Want another?" }, -- 6.5: one page
			primary = "ANOTHER JOB",
			secondary = "LATER",
		}
	elseif phase == "done" then
		-- 6.5: one page: the reward and where to go next; SHOW ME AROUND (5.7: the tour, TutorialSteps.tourDialog) or CLOSE
		local reward = if type(info.reward) == "number" then math.floor(info.reward) else Config.Tutorial.Reward
		return {
			speaker = speaker(true),
			pages = { `Delivered! +${reward}. Next: press J for a job. Shops are in your phone (Q → SHOP).` },
			primary = "SHOW ME AROUND",
			secondary = "CLOSE",
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

-- 5.7, the tour after the first delivery (TutorialSteps.Tour): one short page a stop, the place on your GPS
-- (client/TutorialUi.luau). info.dock: the dock's name, info.stop: the bus stop's. Nil for an unknown step.
function TutorialSteps.tourDialog(step: string, info: { [string]: any }?): Dialog?
	local data: { [string]: any } = info or {}
	local last = step == TutorialSteps.Tour[#TutorialSteps.Tour]
	local page: string? = nil
	if step == "dock" then
		page = `See the red ZDC RIDE dock{if type(data.dock) == "string" then ` on {data.dock}` else ""}, right by the depot? Free e-scooters: rent one, ride to your run, leave it at any dock. It's on your GPS.`
	elseif step == "bus" then
		page = `The buses are free too. Your nearest stop is {text(data.stop, "a short walk away")}: board at the door, ring the bell (E) and hop off where you need. GPS is on it.`
	elseif step == "board" then
		page = "And the work: Q opens your phone, JOBS has every run. New ones come in every few minutes. Go get 'em, courier!"
	end
	if not page then
		return nil
	end
	return {
		speaker = speaker(true),
		pages = { page },
		primary = if last then "OPEN THE BOARD" else "NEXT",
		secondary = "SKIP TOUR",
	}
end

-- 4.2, a touch screen (no keys): her words without the keys. "(E)" / "(J)" go (the prompts and the buttons are
-- tapped), "Press J." goes (her board dialog opens the board itself), "G puts it down" names the PUT DOWN button and
-- "Hold T to pick a gun" the weapon line, 6.0: "V punches" the PUNCH button (client/TutorialUi.luau asks on a touch
-- layout only). 6.5: "press J for a job" and "(Q → SHOP)" name the PHONE button.
function TutorialSteps.forTouch(line: string): string
	local out = string.gsub(line, "%s*%([EGJQUKHLMI]%)", "")
	out = string.gsub(out, "%s*Press [A-Z]%.", "")
	out = string.gsub(out, "G puts it down", "PUT DOWN sets it down")
	out = string.gsub(out, "Hold T to pick a gun", "Tap your gun's line to pick a gun")
	out = string.gsub(out, "V punches", "tap PUNCH")
	out = string.gsub(out, "3 draws your gun, 2 holds the bag", "tap DRAW or the hand slots") -- 6.1 (B still draws)
	out = string.gsub(out, "Q opens your phone", "The PHONE button opens your phone") -- 5.7
	out = string.gsub(out, "press J for a job", "PHONE → JOBS for a job") -- 6.5: the done page
	out = string.gsub(out, "%(Q → ", "(PHONE → ")
	return out
end

return TutorialSteps
